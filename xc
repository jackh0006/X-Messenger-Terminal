#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# X Messenger Terminal — xc
# Offline encrypted message courier using age + OpenSSH signatures

set -euo pipefail
# Nothing xc writes may ever be readable by others, files or dirs alike.
umask 077

VERSION="0.1.0"
DATA_DIR="${XCOURIER_DATA_DIR:-$HOME/.xcourier}"
IDENTITY_DIR="$DATA_DIR/identity"
CONTACTS_DIR="$DATA_DIR/contacts"
PREKEYS_DIR="$DATA_DIR/prekeys"
REPLAY_DIR="$DATA_DIR/replay"
VAULT_DIR="$DATA_DIR/vault"

declare -A BUCKETS=(["1k"]=1024 ["4k"]=4096 ["16k"]=16384 ["64k"]=65536)
BUCKET_ORDER=("1k" "4k" "16k" "64k")

if [[ -z "${NO_COLOR:-}" ]]; then
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	YELLOW='\033[1;33m'
	BLUE='\033[0;34m'
	NC='\033[0m'
else
	RED=''
	GREEN=''
	YELLOW=''
	BLUE=''
	NC=''
fi

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
# [WARN]/[ERR] go to STDERR: errors printed on stdout have leaked into
# command-substitution results before (a die message was captured as a
# message payload and signed). Only normal UX lines go to stdout.
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_err() { echo -e "${RED}[ERR]${NC} $*" >&2; }

die() {
	log_err "$*"
	exit 1
}
confirm() {
	read -rp "$1 [y/N] " ans
	[[ "$ans" =~ ^[Yy]$ ]]
}

ensure_data_dirs() {
	mkdir -p "$IDENTITY_DIR" "$CONTACTS_DIR" "$PREKEYS_DIR" "$REPLAY_DIR" "$VAULT_DIR"
	chmod 700 "$DATA_DIR" "$IDENTITY_DIR" "$CONTACTS_DIR" "$PREKEYS_DIR" "$REPLAY_DIR" "$VAULT_DIR" 2>/dev/null || true
}

require_tool() { command -v "$1" >/dev/null 2>&1 || die "Required tool '$1' not found. Install: $2"; }

# Key protection at rest is interactive only. age prompts for the passphrase
# on the real terminal (/dev/tty). The passphrase never travels in argv, is
# never written to a file, and is never placed in an exported environment
# variable by this script. Tests exercise these prompts through a local
# pseudo-terminal driver (tests/helpers/) that is never shipped or installed.

require_tty() {
	if ! { : </dev/tty; } 2>/dev/null; then
		die "xc needs your passphrase and you have no terminal to type it in. Run xc directly in a terminal window; it will prompt you there."
	fi
}

generate_identity() {
	ensure_data_dirs
	require_tty
	age-keygen -o "$IDENTITY_DIR/age.priv" 2>/dev/null
	age-keygen -y "$IDENTITY_DIR/age.priv" >"$IDENTITY_DIR/age.pub"
	ssh-keygen -t ed25519 -N "" -f "$IDENTITY_DIR/ssh" -C "xc-identity-$(date +%s)" >/dev/null
	chmod 600 "$IDENTITY_DIR/age.priv" "$IDENTITY_DIR/ssh"
	# age asks for the passphrase on the terminal itself: Enter, then Confirm,
	# once per file (age key, then SSH signing key).
	age -p -a -e -o "$IDENTITY_DIR/age.priv.enc" "$IDENTITY_DIR/age.priv"
	age -p -a -e -o "$IDENTITY_DIR/ssh.enc" "$IDENTITY_DIR/ssh"
	shred -u "$IDENTITY_DIR/age.priv" "$IDENTITY_DIR/ssh" 2>/dev/null || rm -f "$IDENTITY_DIR/age.priv" "$IDENTITY_DIR/ssh"
	chmod 600 "$IDENTITY_DIR/age.priv.enc" "$IDENTITY_DIR/ssh.enc"
	log_ok "Identity created and encrypted"
}

load_identity() {
	require_tty
	[[ -f "$IDENTITY_DIR/age.pub" ]] || die "No identity. Run 'xc init'."
	local tmpd
	tmpd=$(mktemp -d "$DATA_DIR/vault.XXXXXX")
	chmod 700 "$tmpd"
	if ! age -d -o "$tmpd/age.priv" <"$IDENTITY_DIR/age.priv.enc" 2>/dev/null; then
		rm -rf "$tmpd"
		die "Incorrect passphrase"
	fi
	if ! age -d -o "$tmpd/ssh.priv" <"$IDENTITY_DIR/ssh.enc" 2>/dev/null; then
		rm -rf "$tmpd"
		die "Incorrect passphrase"
	fi
	chmod 600 "$tmpd/age.priv" "$tmpd/ssh.priv"
	AGE_PUBKEY=$(cat "$IDENTITY_DIR/age.pub")
	SSH_PUBKEY=$(cat "$IDENTITY_DIR/ssh.pub")
	AGE_PRIVKEY_FILE="$tmpd/age.priv"
	SSH_PRIVKEY_FILE="$tmpd/ssh.priv"
	IDENTITY_TMPDIR="$tmpd"
}

cleanup_identity() { rm -rf "${IDENTITY_TMPDIR:-/run/xc-cleanup-nonexistent}"; }

get_fingerprint() { ssh-keygen -lf "$IDENTITY_DIR/ssh.pub" | awk '{print "SHA256:" substr($2, index($2, ":") + 1)}' | head -1; }

# 6/8-word fingerprint from BIP39 wordlist (2048 words, lowercase)
# Deterministic: SHA256 fingerprint -> 6 or 8 words (11-bit indices)
# Wordlist: lib/wordlist.txt (2048 words, SHA-256: c25de3592a60649897fab56aeae60945721e6cf5785f6f1fbf4d2a0650f3a31f)
fingerprint_words() {
	local fp="$1" word_count="${2:-6}"
	fp="${fp#SHA256:}"
	local raw hex indices=()
	raw=$(printf '%s' "$fp" | base64 -d 2>/dev/null) || return 1
	hex=$(printf '%s' "$raw" | xxd -p -c 256)
	local i bitval=0 bits=0
	for ((i = 0; i < ${#hex}; i += 2)); do
		byte=$((16#${hex:i:2}))
		bitval=$(((bitval << 8) | byte))
		bits=$((bits + 8))
		while ((bits >= 11)); do
			bits=$((bits - 11))
			indices+=($(((bitval >> bits) & 0x7FF)))
			((${#indices[@]} == word_count)) && break 2
		done
	done
	# Load BIP39 wordlist from lib/wordlist.txt (2048 words, SHA-256: c25de3592a60649897fab56aeae60945721e6cf5785f6f1fbf4d2a0650f3a31f)
	local words
	words=()
	while IFS= read -r w; do
		words+=("$w")
	done <"$REPO_DIR/lib/wordlist.txt"
	if ((${#words[@]} != 2048)); then
		die "wordlist corruption: expected 2048 words, got ${#words[@]}"
	fi
	local result=()
	for idx in "${indices[@]}"; do
		result+=("${words[idx]}")
	done
	echo "${result[*]}"
}
verify_contact() {
	local name="$1"
	local f="$CONTACTS_DIR/$name.json"
	[[ -f "$f" ]] || die "Contact not found"
	local fp
	fp=$(jq -r .fingerprint "$f")
	echo "Fingerprint: $fp"
	echo "6-word: $(fingerprint_words "$fp" 6)"
	echo "8-word: $(fingerprint_words "$fp" 8)"
	confirm "Mark verified?" || die "Cancelled"
	jq '.verified=true' "$f" >"$f.tmp" && mv "$f.tmp" "$f"
	log_ok "Contact '$name' verified"
}

pad_to_bucket() {
	# Prints base64 of: 8 lowercase-hex length header || message || random pad,
	# so the plaintext reaches exactly the chosen bucket size (including header).
	# The length is counted in BYTES (${#} counts characters, which breaks on
	# multibyte input), so the header always matches the true payload size.
	local in="$1"
	local len bucket="" b sz pad
	len=$(printf '%s' "$in" | wc -c | tr -d ' ')
	for b in "${BUCKET_ORDER[@]}"; do
		((8 + len <= BUCKETS[$b])) && {
			bucket=$b
			break
		}
	done
	[[ -n "$bucket" ]] || die "Message too large (max $((BUCKETS[64k] - 8)) bytes)"
	sz=$((BUCKETS[$bucket] - 8))
	pad=$((sz - len))
	{
		printf '%08x' "$len"
		printf '%s' "$in"
		head -c "$pad" /dev/urandom
	} | base64 -w0
}

unpad_message() {
	# ARG: base64 of padded bucket. Writes the original message to stdout.
	# The decoded blob is materialised in a 0600 scratch file: piping it into
	# `head` risks a SIGPIPE kill under set -o pipefail, and the random pad
	# may contain NUL bytes which command substitution would strip. Only the
	# message body (never the pad, which can hold NULs) passes through a
	# shell variable, and only up to the byte length the header states.
	local b64="$1" tmp n
	tmp=$(mktemp "${DATA_DIR:-/tmp}/unpad.XXXXXX")
	printf '%s' "$b64" | base64 -d >"$tmp" || {
		rm -f "$tmp"
		return 1
	}
	n=$((16#$(head -c 8 "$tmp")))
	((n >= 0 && n <= BUCKETS[64k])) || {
		rm -f "$tmp"
		return 1
	}
	dd if="$tmp" bs=1 skip=8 count="$n" 2>/dev/null
	rm -f "$tmp"
}

sign_message() { printf '%s' "$1" | ssh-keygen -Y sign -f "$2" -n "x-courier" | base64 -w0; }

# verify_signature MSG SIG_B64 SSH_PUBKEY — uses `ssh-keygen -Y verify` only.
verify_signature() {
	local msg="$1" sig="$2" pub="$3" tmpd ok=0
	[[ "$pub" == ssh-ed25519\ * || "$pub" == ssh-rsa\ * ]] || return 1
	tmpd=$(mktemp -d)
	printf '* %s\n' "$pub" >"$tmpd/signers"
	printf '%s' "$sig" | base64 -d >"$tmpd/sig" 2>/dev/null || {
		rm -rf "$tmpd"
		return 1
	}
	chmod 600 "$tmpd/sig" "$tmpd/signers"
	printf '%s' "$msg" | ssh-keygen -Y verify -f "$tmpd/signers" -I '*' -n "x-courier" -s "$tmpd/sig" >/dev/null 2>&1 && ok=1
	rm -rf "$tmpd"
	[[ $ok -eq 1 ]]
}

make_signed_bundle() {
	local pt="$1"
	local recip_fp="$2"
	local expiry="${3:-}"
	local payload msg_id ts sender_fp canon sig
	payload=$(pad_to_bucket "$pt") || die "Message too large (max $((BUCKETS[64k] - 8)) bytes)"
	msg_id=$(head -c16 /dev/urandom | xxd -p -c 32) || die "msg_id RNG failed"
	ts=$(date -u +%Y-%m-%dT%H:%M:%SZ) || die "date failed"
	sender_fp=$(get_fingerprint) || die "fingerprint failed"
	canon=$(jq -c -S -n --arg v 1 --arg mid "$msg_id" --arg ts "$ts" --arg sfp "$sender_fp" --arg rfp "$recip_fp" --arg exp "$expiry" --arg pl "$payload" '{v:1, msg_id:$mid, timestamp:$ts, sender_fp:$sfp, recipient_fp:$rfp, expiry:$exp, payload:$pl}') || die "canon build failed"
	sig=$(sign_message "$canon" "$SSH_PRIVKEY_FILE") || die "sign failed"
	printf '%s' "$canon" | jq --arg sig "$sig" '. + {sig: $sig}' || die "sig embed failed"
}

verify_signed_bundle() {
	local b="$1"
	local sender_ssh="$2"
	local sig canon exp rfp payload
	sig=$(printf '%s' "$b" | jq -r .sig)
	canon=$(printf '%s' "$b" | jq -c -S 'del(.sig)')
	verify_signature "$canon" "$sig" "$sender_ssh" || return 1
	exp=$(printf '%s' "$b" | jq -r .expiry)
	if [[ "$exp" != "null" && -n "$exp" ]]; then
		[[ $(date -u +%s) -lt $(date -u -d "$exp" +%s) ]] || die "Message expired"
	fi
	rfp=$(printf '%s' "$b" | jq -r .recipient_fp)
	[[ "$rfp" == "$(get_fingerprint)" ]] || die "Not for this recipient"
	printf '%s' "$b" | jq -r .payload
}

replay_check() {
	local h
	h=$(echo -n "$1" | sha256sum | cut -d' ' -f1)
	[[ -f "$REPLAY_DIR/seen.hashes" ]] && grep -q "^$h$" "$REPLAY_DIR/seen.hashes"
}
replay_mark() {
	local h
	h=$(echo -n "$1" | sha256sum | cut -d' ' -f1)
	echo "$h" >>"$REPLAY_DIR/seen.hashes"
}

cmd_init() {
	[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && {
		echo "Usage: xc init"
		echo "Creates your age + SSH keys and encrypts them with a passphrase."
		echo "You will be asked to type the passphrase in this terminal."
		exit 0
	}
	[[ $# -gt 0 ]] && die "Unknown: $1. xc init takes no options. Keys are encrypted with a passphrase you type when prompted."
	[[ -f "$IDENTITY_DIR/age.pub" ]] && die "Identity exists. Use 'xc wipe'."
	generate_identity
}

cmd_id() {
	local qr=false show_8_words=false
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--qr)
			qr=true
			shift
			;;
		--8-words)
			show_8_words=true
			shift
			;;
		*) die "Unknown option: $1" ;;
		esac
	done
	load_identity
	local fp
	fp=$(get_fingerprint)
	echo "Age: $AGE_PUBKEY"
	echo "SSH: $SSH_PUBKEY"
	echo "Fingerprint: $fp"
	echo "6-word: $(fingerprint_words "$fp" 6)"
	if [[ $show_8_words == true ]]; then
		echo "8-word: $(fingerprint_words "$fp" 8)"
	fi
	$qr && echo "age:$AGE_PUBKEY|ssh:$SSH_PUBKEY|fp:$fp" | qrencode -t UTF8
	cleanup_identity
}

cmd_add() {
	local name=$1
	[[ "$name" =~ ^[A-Za-z0-9_-]{1,32}$ ]] || die "Invalid name"
	[[ -f "$CONTACTS_DIR/$name.json" ]] && die "Contact exists"
	local data
	case ${2:-paste} in
	paste) data=$(cat) ;;
	file)
		[[ -f "$3" ]] || die "File not found"
		data=$(cat "$3")
		;;
	qr) die "QR not implemented" ;;
	*) die "Unknown method" ;;
	esac
	local ap
	ap=$(echo "$data" | grep -o 'age1[0-9a-z]*' | head -1)
	local sp
	sp=$(echo "$data" | grep -oE 'ssh-ed25519 [A-Za-z0-9+/]+' | head -1)
	local fp
	fp=$(echo "$data" | grep -oE 'SHA256:[A-Za-z0-9+/=]{40,64}' | head -1)
	[[ -n "$ap" && -n "$sp" && -n "$fp" ]] || die "Invalid data: need an age key, an ssh-ed25519 key and a SHA256:... fingerprint (from 'xc id')"
	[[ "$ap" =~ ^age1[0-9a-z]{58}$ ]] || die "Invalid age pubkey"
	[[ "$sp" =~ ^ssh-ed25519\ [A-Za-z0-9+/]+=*$ ]] || die "Invalid SSH pubkey"
	cat >"$CONTACTS_DIR/$name.json" <<EOF
{"name":"$name","age_pub":"$ap","ssh_pub":"$sp","fingerprint":"$fp","verified":false}
EOF
	chmod 600 "$CONTACTS_DIR/$name.json"
	echo "Added '$name' (unverified). Fingerprint: $fp"
	echo "Verify in person, then: xc verify $name"
}

cmd_verify() { verify_contact "$1"; }

cmd_send() {
	local recip="" expires=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--expires)
			expires="${2:-}"
			shift 2
			;;
		*)
			recip="${1:-}"
			shift
			;;
		esac
	done
	[[ -n "$recip" ]] || die "Usage: xc send <friend> [--expires <ISO date>]"
	local cf="$CONTACTS_DIR/$recip.json"
	[[ -f "$cf" ]] || die "Contact not found: $recip"
	[[ $(jq -r .verified "$cf") == "true" ]] || die "Contact '$recip' is not verified. Meet in person, compare fingerprints, then run: xc verify $recip"
	local msg
	msg=$(cat)
	[[ -n "$msg" ]] || die "No message on stdin"
	# Early size check: reject oversize BEFORE any passphrase prompt or
	# key work. Plain words per spec. Must match the bucket limit exactly.
	local msg_bytes
	msg_bytes=$(printf '%s' "$msg" | wc -c | tr -d ' ')
	((msg_bytes <= BUCKETS[64k] - 8)) || die "This message is too long. Maximum is 64 KiB."
	load_identity
	local rap rfp bundle
	rap=$(jq -r .age_pub "$cf")
	rfp=$(jq -r .fingerprint "$cf")
	bundle=$(make_signed_bundle "$msg" "$rfp" "$expires") || die "bundle build failed"
	printf 'X-COURIER/1\n' >message.courier.tmp
	printf '%s' "$bundle" | age -e -r "$rap" >>message.courier.tmp || die "age encrypt failed"
	mv message.courier.tmp message.courier
	cleanup_identity
	# Post-seal assertion: the payload that went into age (base64 of the
	# padded bucket) must decode to exactly one of the bucket sizes.
	# We can't check the final courier size because age encryption adds
	# random IV/salt — identical inputs give different ciphertexts.
	local pl_b64
	pl_b64=$(jq -r .payload <<<"$bundle") || die "bundle payload extract failed"
	local pl_decoded
	pl_decoded=$(printf '%s' "$pl_b64" | base64 -d 2>/dev/null | wc -c | tr -d ' ')
	# Check against bucket sizes (numeric constants, not globs)
	if [[ "$pl_decoded" -eq ${BUCKETS[1k]} || "$pl_decoded" -eq ${BUCKETS[4k]} || "$pl_decoded" -eq ${BUCKETS[16k]} || "$pl_decoded" -eq ${BUCKETS[64k]} ]]; then
		: # valid bucket size
	else
		die "INTERNAL ERROR: payload decoded size $pl_decoded is not a valid bucket (logic bug)"
	fi
	{
		printf '[OK] Sealed to %s: message.courier\n' "$recip"
		printf '[INFO] Payload bucket: %s bytes\n' "$msg_bytes"
	}
}

cmd_read() {
	local file="${1:-}"
	[[ -n "$file" ]] || die "Usage: xc read <file|->"
	# The courier body is binary age ciphertext: it must never pass through
	# a shell variable (command substitution strips NUL bytes). The whole
	# input is materialised to a 0600 scratch file first; only the text
	# header is inspected and the body is sliced inside the file.
	local body_scratch body_tmp
	[[ -d "$DATA_DIR" ]] || die "No data directory. Run 'xc init' first."
	body_scratch=$(mktemp "$DATA_DIR/body.XXXXXX")
	if [[ "$file" == "-" ]]; then
		cat >"$body_scratch"
	else
		[[ -f "$file" ]] || {
			rm -f "$body_scratch"
			die "Not found: $file"
		}
		cp -- "$file" "$body_scratch"
	fi
	if ! head -1 "$body_scratch" | grep -q '^X-COURIER/1'; then
		rm -f "$body_scratch"
		die "Not a .courier file"
	fi
	body_tmp="$body_scratch.tmp"
	tail -c +13 "$body_scratch" >"$body_tmp" && mv "$body_tmp" "$body_scratch"
	load_identity
	local bundle sfp found f payload pt mid
	bundle=$(age -d -i "$AGE_PRIVKEY_FILE" <"$body_scratch") || {
		rm -f "$body_scratch"
		cleanup_identity
		die "This file cannot be opened with your keys: it is not for you, was made for a different identity, or was corrupted"
	}
	rm -f "$body_scratch"
	sfp=$(printf '%s' "$bundle" | jq -r .sender_fp)
	found=""
	for f in "$CONTACTS_DIR"/*.json; do
		[[ -f "$f" ]] || continue
		[[ "$(jq -r .fingerprint "$f")" == "$sfp" ]] && {
			found=$f
			break
		}
	done
	[[ -n "$found" ]] || die "Unknown sender (fingerprint $sfp). Add the sender with 'xc add' before opening their mail."
	payload=$(verify_signed_bundle "$bundle" "$(jq -r .ssh_pub "$found")") || die "Signature check FAILED. Do not trust this message."
	[[ -n "${XCDEBUG:-}" ]] && printf 'DBG bundle_len=%s payload_len=%s payload_head=%s\n' "${#bundle}" "${#payload}" "${payload:0:12}" >&2
	[[ $(jq -r .verified "$found") == "true" ]] || log_warn "Sender '$(jq -r .name "$found")' is not yet verified; signature came from their registered key."
	pt=$(unpad_message "$payload")
	mid=$(printf '%s' "$bundle" | jq -r .msg_id)
	if replay_check "$mid"; then
		rm -f "$body_scratch" 2>/dev/null || true
		cleanup_identity
		die "Replay detected: this exact message was already opened"
	fi
	replay_mark "$mid"
	cleanup_identity
	echo "$pt"
	log_ok "Decrypted from $sfp (msg_id $mid)"
}

cmd_doctor() {
	log_info "Doctor"
	for t in age age-keygen ssh-keygen ssh qrencode zbarimg; do
		if command -v "$t" >/dev/null; then log_ok "$t"; else log_warn "$t missing"; fi
	done
	if [[ -d "$DATA_DIR" ]] && [[ $(stat -c %a "$DATA_DIR") == "700" ]]; then log_ok "Data dir 700"; else log_warn "Data dir perms"; fi
	if unshare -rn true 2>/dev/null; then log_ok "unshare -rn works"; else log_warn "unshare -rn needs root"; fi
	if [[ -z "${HISTFILE:-}" ]]; then log_ok "HISTFILE unset"; else log_warn "HISTFILE set"; fi
	# Verify BIP39 wordlist SHA-256
	local expected="2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda"
	local actual
	actual=$(sha256sum "$REPO_ROOT/lib/wordlist.txt" | awk "{print \$1}")
	if [[ "$actual" == "$expected" ]]; then
		log_ok "wordlist SHA-256"
	else
		log_err "wordlist SHA-256 mismatch: expected $expected, got $actual"
	fi
}

cmd_selftest() {
	# No passphrase is involved here: full round-trip testing lives in tests/
	# and is driven with a pseudo-terminal through tests/helpers/pty_drive.py.
	log_info "Self-test"
	local fails=0 t
	bash -n "$0" || fails=1
	for t in age age-keygen ssh-keygen ssh qrencode zbarimg jq; do
		command -v "$t" >/dev/null || {
			log_err "missing tool: $t"
			fails=1
		}
	done
	# Padding invariants: the header length decodes to the message length.
	local pb pt nb
	pb=$(pad_to_bucket "hello")
	pt=$(unpad_message "$pb")
	[[ "$pt" == "hello" ]] || {
		log_err "unpad broken"
		fails=1
	}
	nb=$(printf '%s' "$pt" | wc -c | tr -d ' ')
	[[ "$nb" == "5" ]] || {
		log_err "padding header broken"
		fails=1
	}
	# Replay cache round trip in a throwaway dir.
	local rd
	rd=$(mktemp -d)
	REPLAY_DIR="$rd" replay_mark "id-a"
	if REPLAY_DIR="$rd" replay_check "id-a"; then log_ok "replay cache works"; else
		log_err "replay cache broken"
		fails=1
	fi
	rm -rf "$rd"
	if [[ $fails -eq 0 ]]; then log_ok "Self-test passed"; else die "Self-test failed"; fi
}

show_menu() {
	cat <<'EOF'
  X-COURIER

  What do you want to do?

   1  Write a secret message
   2  Open a secret message
   3  Add a friend
   4  Show my ID to a friend
   5  Check everything is OK
   0  Leave

  Type a number and press Enter:
EOF
	read -r c
	case $c in 1) echo "NYI" ;; 2) echo "NYI" ;; 3) echo "NYI" ;; 4) cmd_id ;; 5) cmd_doctor ;; 0) exit ;; *) echo "Invalid" ;; esac
}

main() {
	local cmd="${1:-menu}"
	shift || true
	case $cmd in
	--help | help)
		cat <<EOF
X Messenger Terminal — Offline Encrypted Courier

Usage: xc <command> [options]
Commands: init, id, add, verify, send, read, doctor, selftest, wipe, rotate, prekeys, qr-send, qr-read
Examples: xc init; xc id --qr; echo "msg" | xc send alice; xc read file.courier
EOF
		exit 0
		;;
	init) cmd_init "$@" ;; id) cmd_id "$@" ;; add) cmd_add "$@" ;; verify) cmd_verify "$@" ;;
	send) cmd_send "$@" ;; read) cmd_read "$@" ;; doctor) cmd_doctor ;; selftest) cmd_selftest ;; wipe) cmd_wipe ;; rotate) cmd_rotate ;; prekeys) cmd_prekeys ;; qr-send) cmd_qr_send ;; qr-read) cmd_qr_read ;;
	--version) echo "X Messenger Terminal $VERSION" ;;
	menu | "") show_menu ;;
	*) die "Unknown: $cmd. Run 'xc --help'." ;;
	esac
}

trap cleanup_identity EXIT INT TERM HUP
cmd_wipe() {
	echo "NOT IMPLEMENTED: wipe" >&2
	exit 1
}

cmd_rotate() {
	echo "NOT IMPLEMENTED: rotate" >&2
	exit 1
}

cmd_prekeys() {
	echo "NOT IMPLEMENTED: prekeys" >&2
	exit 1
}

cmd_qr_send() {
	echo "NOT IMPLEMENTED: qr-send" >&2
	exit 1
}

cmd_qr_read() {
	echo "NOT IMPLEMENTED: qr-read" >&2
	exit 1
}

main "$@"
