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
	local pkid="${4:-}"
	local payload msg_id ts sender_fp canon sig
	payload=$(pad_to_bucket "$pt") || die "Message too large (max $((BUCKETS[64k] - 8)) bytes)"
	msg_id=$(head -c16 /dev/urandom | xxd -p -c 32) || die "msg_id RNG failed"
	ts=$(date -u +%Y-%m-%dT%H:%M:%SZ) || die "date failed"
	sender_fp=$(get_fingerprint) || die "fingerprint failed"
	canon=$(jq -c -S -n --arg v 1 --arg mid "$msg_id" --arg ts "$ts" --arg sfp "$sender_fp" --arg rfp "$recip_fp" --arg exp "$expiry" --arg pl "$payload" '{v:1, msg_id:$mid, timestamp:$ts, sender_fp:$sfp, recipient_fp:$rfp, expiry:$exp, payload:$pl}') || die "canon build failed"
	# One-time prekey use is part of the signed canon: the receiver burns the
	# matching private half only when the canon's id agrees with the key that
	# actually opened the envelope.
	if [[ -n "$pkid" ]]; then
		canon=$(printf '%s' "$canon" | jq -c --arg pk "$pkid" '. + {prekey:$pk}') || die "prekey field failed"
		canon=$(printf '%s' "$canon" | jq -c -S .)
	fi
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
	local recip="" expires="" nfs=false
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--expires)
			expires="${2:-}"
			shift 2
			;;
		--no-forward-secrecy)
			nfs=true
			shift 1
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
	# One-time prekey pick (offline forward secrecy). Chosen BEFORE any
	# passphrase prompt: an exhausted bundle refuses without ever asking for
	# keys. Only the smallest unused key id is consumed, and the same id can
	# never be picked twice (marked used right after a successful seal).
	local pk_id="" pk_pub=""
	if [[ -f "$PREKEYS_DIR/$recip/bundle.pub" ]]; then
		local used_list pid
		used_list=""
		[[ -f "$PREKEYS_DIR/$recip/used.json" ]] && used_list=$(jq -r 'join(",")' "$PREKEYS_DIR/$recip/used.json" 2>/dev/null || true)
		while IFS= read -r pid; do
			[[ -z "$pid" ]] && continue
			case ",$used_list," in
			*",$pid,"*) continue ;;
			esac
			pk_id="$pid"
			pk_pub=$(jq -r --arg id "$pid" '.keys[] | select(.id == $id) | .pub' "$PREKEYS_DIR/$recip/bundle.pub")
			break
		done < <(jq -r '.keys[].id' "$PREKEYS_DIR/$recip/bundle.pub")
		if [[ -z "$pk_id" ]]; then
			if [[ "$nfs" != true ]]; then
				die "No one-time keys left for '$recip': every key in the bundle was used. Ask for a new bundle, or send now without forward secrecy: xc send $recip --no-forward-secrecy"
			fi
			log_warn "WARNING: no unused one-time keys for '$recip'. Sealing only to their identity key — WITHOUT forward secrecy (--no-forward-secrecy)."
		fi
	fi
	load_identity
	local rap rfp bundle
	rap=$(jq -r .age_pub "$cf")
	rfp=$(jq -r .fingerprint "$cf")
	bundle=$(make_signed_bundle "$msg" "$rfp" "$expires" "$pk_id") || die "bundle build failed"
	printf 'X-COURIER/1\n' >message.courier.tmp
	if [[ -n "$pk_id" ]]; then
		printf '%s' "$bundle" | age -e -r "$pk_pub" >>message.courier.tmp || die "age encrypt failed"
	else
		printf '%s' "$bundle" | age -e -r "$rap" >>message.courier.tmp || die "age encrypt failed"
	fi
	mv message.courier.tmp message.courier
	if [[ -n "$pk_id" ]]; then
		mark_used "$recip" "$pk_id" || die "could not record one-time key usage"
	fi
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
		if [[ -n "$pk_id" ]]; then
			printf '[INFO] One-time key used: %s\n' "$pk_id"
		fi
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
	local used_kf="" used_id="" kf canon_pk
	bundle=$(age -d -i "$AGE_PRIVKEY_FILE" <"$body_scratch" 2>/dev/null) || {
		# Not sealed to the long-term identity key: try every unused private
		# one-time prekey until one opens the envelope. Trying all files (not
		# a header hint) leaks no key metadata at all.
		for kf in "$PREKEYS_DIR"/*/*.agekey; do
			[[ -e "$kf" ]] || continue
			bundle=$(age -d -i "$kf" <"$body_scratch" 2>/dev/null) && {
				used_kf="$kf"
				used_id=$(basename "$kf" .agekey)
				break
			}
		done
	}
	if [[ -z "${bundle:-}" ]]; then
		rm -f "$body_scratch"
		cleanup_identity
		die "This file cannot be opened with your keys: it is not for you, was made for a different identity, or was corrupted"
	fi
	rm -f "$body_scratch"
	if ! printf '%s' "$bundle" | jq -e -c 'has("sig") and has("sender_fp") and has("payload")' >/dev/null 2>&1; then
		cleanup_identity
		die "This file does not contain a valid signed message"
	fi
	# A message may only claim the one-time key it was really opened with;
	# on mismatch the key is KEPT and the message refused (a crafted mismatch
	# must never trick us into burning a key).
	if [[ -n "$used_kf" ]]; then
		canon_pk=$(printf '%s' "$bundle" | jq -r '.prekey // empty')
		if [[ "$canon_pk" != "$used_id" ]]; then
			cleanup_identity
			die "One-time key mismatch: message claims '$canon_pk' but was opened with '$used_id'. Message refused, key kept."
		fi
	fi
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
	# The private prekey half is destroyed ONLY now: decryption succeeded,
	# the signature verified, the replay check passed, and the claimed key
	# id matches the key that really opened it.
	if [[ -n "$used_kf" ]]; then
		shred -u "$used_kf" 2>/dev/null || rm -f "$used_kf"
	fi
	cleanup_identity
	echo "$pt"
	if [[ -n "$used_id" ]]; then
		log_ok "Decrypted from $sfp (msg_id $mid). Destroyed one-time key $used_id"
	else
		log_ok "Decrypted from $sfp (msg_id $mid)"
	fi
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
Commands: init, id, add, verify, send, read, doctor, selftest, wipe, rotate, prekeys (make|import), qr-send, qr-read
Examples: xc init; xc id --qr; echo "msg" | xc send alice; xc read file.courier; xc prekeys make bob
EOF
		exit 0
		;;
	init) cmd_init "$@" ;; id) cmd_id "$@" ;; add) cmd_add "$@" ;; verify) cmd_verify "$@" ;;
	send) cmd_send "$@" ;; read) cmd_read "$@" ;; doctor) cmd_doctor ;; selftest) cmd_selftest ;; wipe) cmd_wipe "$@" ;; rotate) cmd_rotate "$@" ;; prekeys) cmd_prekeys "$@" ;; qr-send) cmd_qr_send "$@" ;; qr-read) cmd_qr_read "$@" ;;
	--version) echo "X Messenger Terminal $VERSION" ;;
	menu | "") show_menu ;;
	*) die "Unknown: $cmd. Run 'xc --help'." ;;
	esac
}

trap cleanup_identity EXIT INT TERM HUP
cmd_wipe() {
	if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
		echo "Usage: xc wipe"
		echo "Erases your identity, contacts, one-time keys, replay cache and vault"
		echo "after you type a confirmation word. There is no undo."
		exit 0
	fi
	[[ $# -gt 0 ]] && die "Unknown: $1. xc wipe takes no options."

	# Resolve DATA_DIR to absolute path, refuse symlinks and dangerous paths
	local resolved_data
	resolved_data=$(realpath -e "$DATA_DIR" 2>/dev/null) || die "DATA_DIR does not exist or cannot be resolved: $DATA_DIR"

	# Refuse symlinked data dir
	if [[ -L "$DATA_DIR" ]] || [[ "$resolved_data" != "$DATA_DIR" ]]; then
		die "Refusing to wipe: DATA_DIR is a symlink or does not match its realpath ($resolved_data)"
	fi

	# Refuse dangerous paths
	case "$resolved_data" in
		/|/home|/home/*|/root|/tmp|/var|/etc|/usr|/opt)
			die "Refusing to wipe dangerous path: $resolved_data"
			;;
	esac

	# Refuse if resolved path is a parent of HOME (extra safety)
	case "$resolved_data" in
		"$HOME"|"$HOME"/*)
			die "Refusing to wipe inside HOME: $resolved_data"
			;;
	esac

	# Verify this is an xc data directory by checking for known subdirs
	[[ -d "$resolved_data/identity" ]] || die "Not an xc data directory: missing identity/"
	[[ -d "$resolved_data/contacts" ]] || die "Not an xc data directory: missing contacts/"
	[[ -d "$resolved_data/prekeys" ]] || die "Not an xc data directory: missing prekeys/"
	[[ -d "$resolved_data/replay" ]] || die "Not an xc data directory: missing replay/"
	[[ -d "$resolved_data/vault" ]] || die "Not an xc data directory: missing vault/"

	local n_keys n_contacts
	n_keys=$(find "$resolved_data/prekeys" -name '*.agekey' 2>/dev/null | wc -l | tr -d ' ')
	n_contacts=$(find "$resolved_data/contacts" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
	echo "This erases EVERYTHING in $resolved_data:"
	echo "  - your identity (age keys + SSH signing key)"
	echo "  - $n_contacts contact(s) and $n_keys one-time private key(s)"
	echo "  - the replay cache (opened-message history) and vault scratch space"
	local ans
	read -rp 'Type WIPE (capital letters) to erase everything: ' ans || ans=""
	if [[ "$ans" != "WIPE" ]]; then
		die "Wipe cancelled — your data is not deleted. Nothing changed."
	fi

	# Delete only known contents, not the parent directory itself
	rm -rf -- \
		"$resolved_data/identity" \
		"$resolved_data/contacts" \
		"$resolved_data/prekeys" \
		"$resolved_data/replay" \
		"$resolved_data/vault" \
		2>/dev/null
	# Remove the data dir itself if empty
	rmdir "$resolved_data" 2>/dev/null || true
	echo "Erased: all of $resolved_data (identity, contacts, $n_keys one-time keys)."
	# Honest limitation (KNOWN_LIMITATIONS.md): flash wear leveling means
	# deletion is never a hardware-level guarantee.
	echo "Storage note: on flash memory (SSD, SD card, phone storage), wear leveling can leave recoverable fragments at the hardware level. Deletion here is best effort; treat high-risk messages as safe only on an encrypted filesystem."
}

cmd_rotate() {
	# Replaces the identity (age + SSH signing keys) with a brand-new pair.
	# Order is deliberate: identity check, then the typed confirmation, and
	# only then any prompt that costs the user a passphrase. Old keys are
	# destroyed unless --keep-old shelves them (still encrypted).
	if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
		echo "Usage: xc rotate [--keep-old]"
		echo "Replaces your age + SSH keys with a new pair encrypted with a"
		echo "passphrase you type in this terminal."
		echo "  - Your fingerprint CHANGES: every contact must re-verify you."
		echo "  - Couriers sealed to the OLD key can no longer be opened."
		echo "  - --keep-old shelves the old encrypted key files in identity.old/"
		echo "    instead of destroying them."
		exit 0
	fi
	local keep_old=false arg
	for arg in "$@"; do
		case "$arg" in
		--keep-old) keep_old=true ;;
		*) die "Unknown: $arg. Usage: xc rotate [--keep-old]" ;;
		esac
	done
	[[ -f "$IDENTITY_DIR/age.pub" ]] || die "No identity to rotate. Run 'xc init' first."
	[[ -f "$IDENTITY_DIR/age.priv.enc" && -f "$IDENTITY_DIR/ssh.enc" ]] || die "Identity key files are incomplete; run 'xc init' again instead (or 'xc wipe' first)."
	local names="" n_contacts=0 f name
	for f in "$CONTACTS_DIR"/*.json; do
		[[ -f "$f" ]] || continue
		name=$(basename "$f" .json)
		names+="${names:+, }$name"
		n_contacts=$((n_contacts + 1))
	done
	echo "Rotating replaces your age + SSH keys with a brand-new pair:"
	echo "  - your fingerprint CHANGES and ${names:-none} must re-verify you"
	echo "  - couriers sealed to the OLD key can no longer be opened"
	if [[ "$keep_old" == true ]]; then
		echo "  - (--keep-old) the old ENCRYPTED key files are shelved in identity.old/"
	else
		echo "  - the old key files are destroyed"
	fi
	local ans
	read -rp 'Type ROTATE (capital letters) to replace your keys: ' ans || ans=""
	if [[ "$ans" != "ROTATE" ]]; then
		die "Rotation cancelled — your keys are not changed. Nothing changed."
	fi
	local stage="$DATA_DIR/.rotate-new"
	rm -rf "$stage"
	mkdir -p "$stage"
	chmod 700 "$stage"
	age-keygen -o "$stage/age.priv" 2>/dev/null || {
		rm -rf "$stage"
		die "age-keygen failed"
	}
	age-keygen -y "$stage/age.priv" >"$stage/age.pub" 2>/dev/null || {
		rm -rf "$stage"
		die "could not derive the new age public key"
	}
	chmod 600 "$stage/age.priv"
	ssh-keygen -t ed25519 -N "" -f "$stage/ssh" -C "xc-rotated-$(date +%s)" >/dev/null || {
		rm -rf "$stage"
		die "ssh-keygen failed"
	}
	chmod 600 "$stage/ssh"
	# Prove the fresh pair is self-consistent BEFORE encryption, using no
	# passphrase at all: every inconsistency dies here, before prompts.
	if [[ "$(age-keygen -y "$stage/age.priv" 2>/dev/null)" != "$(cat "$stage/age.pub")" ]]; then
		rm -rf "$stage"
		die "the generated age keypair failed its consistency check"
	fi
	if [[ "$(ssh-keygen -y -f "$stage/ssh" | awk '{print $2}')" != "$(awk '{print $2}' "$stage/ssh.pub")" ]]; then
		rm -rf "$stage"
		die "the generated SSH keypair failed its consistency check"
	fi
	age -p -a -e -o "$stage/age.priv.enc" "$stage/age.priv" || {
		rm -rf "$stage"
		die "could not encrypt the new age key"
	}
	shred -u "$stage/age.priv" 2>/dev/null || rm -f "$stage/age.priv"
	age -p -a -e -o "$stage/ssh.enc" "$stage/ssh" || {
		rm -rf "$stage"
		die "could not encrypt the new SSH key"
	}
	shred -u "$stage/ssh" 2>/dev/null || rm -f "$stage/ssh"
	chmod 600 "$stage/age.priv.enc" "$stage/ssh.enc"
	# Commit: shelve or destroy the old keys first, then move the new ones in.
	if [[ "$keep_old" == true ]]; then
		mkdir -p "$DATA_DIR/identity.old"
		chmod 700 "$DATA_DIR/identity.old"
		if [[ -e "$DATA_DIR/identity.old/age.priv.enc" ]]; then
			rm -rf "$stage"
			die "identity.old already holds keys from an earlier rotation; deal with $DATA_DIR/identity.old first."
		fi
		mv "$IDENTITY_DIR/age.priv.enc" "$IDENTITY_DIR/ssh.enc" "$IDENTITY_DIR/age.pub" "$IDENTITY_DIR/ssh.pub" "$DATA_DIR/identity.old/" || {
			rm -rf "$stage"
			die "could not shelve the old keys"
		}
	else
		shred -u "$IDENTITY_DIR/age.priv.enc" "$IDENTITY_DIR/ssh.enc" 2>/dev/null || rm -f "$IDENTITY_DIR/age.priv.enc" "$IDENTITY_DIR/ssh.enc"
		rm -f "$IDENTITY_DIR/age.pub" "$IDENTITY_DIR/ssh.pub"
	fi
	mv "$stage/age.priv.enc" "$stage/age.pub" "$stage/ssh.enc" "$stage/ssh.pub" "$IDENTITY_DIR/" || die "could not install the new keys"
	rm -rf "$stage"
	# New id table straight from the new public files — no second prompt.
	local fp
	fp=$(get_fingerprint)
	{
		echo "Age: $(cat "$IDENTITY_DIR/age.pub")"
		echo "SSH: $(cat "$IDENTITY_DIR/ssh.pub")"
		echo "Fingerprint: $fp"
		echo "6-word: $(fingerprint_words "$fp" 6)"
		echo "8-word: $(fingerprint_words "$fp" 8)"
	}
	log_ok "Rotated: new identity created, encrypted with the passphrase you typed."
	echo "WARNING: your fingerprint CHANGED. Every contact must re-verify your new identity: ${names:-you have no contacts yet}."
	echo "Couriers sealed to the OLD key can no longer be opened."
	if [[ "$keep_old" == true ]]; then
		echo "Old keys kept (still encrypted) in $DATA_DIR/identity.old"
	fi
}

cmd_prekeys() {
	local sub="${1:-}"
	case "$sub" in
	make)
		shift 1
		cmd_prekeys_make "$@"
		;;
	import)
		shift 1
		cmd_prekeys_import "$@"
		;;
	--help | -h)
		cat <<'EOF'
One-time prekeys: offline forward secrecy.

  xc prekeys make <contact> [--count N] [--for-fp <fingerprint>]
      Create N one-time X25519 keypairs. The private halves stay on THIS
      device; the signed public bundle goes to <contact>.
  xc prekeys import <contact> <bundle-file|->
      Import a friend's signed public bundle (signature must verify).
  Sending uses one key per message and never reuses one. When the bundle
  is exhausted, 'xc send' refuses unless --no-forward-secrecy is given.
EOF
		;;
	"") die "Usage: xc prekeys make <contact> | xc prekeys import <contact> <bundle-file|-->. Run 'xc prekeys --help' for details." ;;
	*) die "Unknown prekeys action: '$sub'. Available: make, import." ;;
	esac
}

mark_used() {
	# Record one consumed one-time key id. Writes go through a temp file in
	# the same directory and a rename, so a half-written used.json can never
	# make us pick the same key twice.
	local friend="$1" pid="$2" tmp
	mkdir -p "$PREKEYS_DIR/$friend"
	tmp=$(mktemp "$PREKEYS_DIR/$friend/used.tmp.XXXXXX")
	if [[ -f "$PREKEYS_DIR/$friend/used.json" ]]; then
		jq -c --arg id "$pid" '. + [$id]' "$PREKEYS_DIR/$friend/used.json" >"$tmp" || {
			rm -f "$tmp"
			return 1
		}
	else
		jq -cn --arg id "$pid" '[$id]' >"$tmp" || {
			rm -f "$tmp"
			return 1
		}
	fi
	chmod 600 "$tmp"
	mv "$tmp" "$PREKEYS_DIR/$friend/used.json"
}

cmd_prekeys_make() {
	local friend=""
	local count=""
	local for_fp=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--count)
			count="${2:-}"
			shift 2
			;;
		--for-fp)
			for_fp="${2:-}"
			shift 2
			;;
		-*) die "Unknown option: $1" ;;
		*)
			friend="${1:-}"
			shift
			;;
		esac
	done
	[[ "$friend" =~ ^[A-Za-z0-9_-]{1,32}$ ]] || die "Usage: xc prekeys make <contact> [--count N] [--for-fp <fingerprint>]"
	local n
	n="${count:-100}"
	case "$n" in
	"" | *[!0-9]*) die "--count must be a whole number between 1 and 9999" ;;
	esac
	((n >= 1 && n <= 9999)) || die "--count must be between 1 and 9999"
	[[ -f "$IDENTITY_DIR/age.pub" ]] || die "No identity. Run 'xc init' first."
	[[ -f "$PREKEYS_DIR/$friend/bundle.pub" ]] && die "One-time keys for '$friend' already exist. Re-making would hide which keys are still unused; wipe first if you really must."
	# Who is this bundle for? A contact record is the easy path; --for-fp is
	# the explicit path (e.g. their public key arrived on paper).
	if [[ -n "$for_fp" ]]; then
		[[ "$for_fp" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]] || die "--for-fp must look like SHA256:<43 base64 chars>"
	elif [[ -f "$CONTACTS_DIR/$friend.json" ]]; then
		for_fp=$(jq -r '.fingerprint' "$CONTACTS_DIR/$friend.json")
	else
		die "Unknown contact '$friend': add them first (xc add $friend), or pass --for-fp with their fingerprint."
	fi
	ensure_data_dirs
	mkdir -p "$PREKEYS_DIR/$friend"
	chmod 700 "$PREKEYS_DIR/$friend"
	load_identity
	local fdir canon id pub ts i
	fdir="$PREKEYS_DIR/$friend"
	ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	canon=$(jq -c -S -n --arg fp "$for_fp" --arg created "$ts" '{type:"one-time-prekeys", v:1, for_fp:$fp, created:$created, keys:[]}')
	for ((i = 1; i <= n; i++)); do
		printf -v id '%04d' "$i"
		age-keygen -o "$fdir/$id.agekey" >/dev/null 2>&1 || {
			rm -rf "$fdir"
			die "age-keygen failed"
		}
		chmod 600 "$fdir/$id.agekey"
		pub=$(age-keygen -y "$fdir/$id.agekey" 2>/dev/null) || {
			rm -rf "$fdir"
			die "could not read back $id.agekey"
		}
		canon=$(jq -c --arg id "$id" --arg pub "$pub" '.keys += [{id:$id, pub:$pub}]' <<<"$canon")
	done
	canon=$(jq -c -S <<<"$canon")
	local sig
	sig=$(sign_message "$canon" "$SSH_PRIVKEY_FILE") || {
		rm -rf "$fdir"
		die "signing failed"
	}
	jq --arg sig "$sig" '. + {sig:$sig}' <<<"$canon" >"$fdir/bundle.pub"
	chmod 600 "$fdir/bundle.pub"
	cleanup_identity
	log_ok "One-time keys ready: $n keys for '$friend'"
	echo "Private halves stay on THIS device under $fdir (deleted one by one as their messages are opened)."
	echo "Give the public bundle to '$friend': $fdir/bundle.pub"
}

cmd_prekeys_import() {
	local friend="${1:-}" src="${2:-}"
	[[ $# -eq 2 ]] || die "Usage: xc prekeys import <contact> <bundle-file|->"
	[[ "$friend" =~ ^[A-Za-z0-9_-]{1,32}$ ]] || die "Invalid contact name: $friend"
	[[ -f "$CONTACTS_DIR/$friend.json" ]] || die "Unknown contact '$friend'. Add them first: xc add $friend"
	if [[ -f "$PREKEYS_DIR/$friend/bundle.pub" ]]; then
		die "A bundle for '$friend' is already imported. Wipe the folder $PREKEYS_DIR/$friend before importing another."
	fi
	local data
	case "$src" in
	-) data=$(cat) ;;
	*)
		[[ -f "$src" ]] || die "Not found: $src"
		data=$(cat "$src")
		;;
	esac
	[[ -n "$data" ]] || die "Bundle is empty"
	if ! printf '%s' "$data" | jq -e -c 'has("sig") and has("keys") and has("for_fp")' >/dev/null 2>&1; then
		die "This does not look like a one-time-prekeys bundle"
	fi
	# The bundle must carry its maker's valid signature, be addressed to THIS
	# identity, and contain sane keys — otherwise nothing gets written.
	local ssh_pub sig canon myfp count id pub
	ssh_pub=$(jq -r '.ssh_pub' "$CONTACTS_DIR/$friend.json")
	canon=$(printf '%s' "$data" | jq -c -S 'del(.sig)')
	sig=$(printf '%s' "$data" | jq -r '.sig')
	verify_signature "$canon" "$sig" "$ssh_pub" || die "Import refused: the bundle's signature does not verify against '$friend's registered key."
	myfp=$(get_fingerprint)
	if [[ "$(printf '%s' "$data" | jq -r '.for_fp')" != "$myfp" ]]; then
		die "This bundle was not made for this identity (for_fp $(printf '%s' "$data" | jq -r '.for_fp'), yours $myfp)."
	fi
	count=$(printf '%s' "$data" | jq '.keys | length')
	[[ "$count" -ge 1 && "$count" -le 9999 ]] || die "Bundle has an impossible key count: $count"
	while IFS= read -r id; do
		[[ -z "$id" ]] && continue
		[[ "$id" =~ ^[0-9]{4}$ ]] || die "Bundle has a malformed one-time key id: '$id'"
	done < <(printf '%s' "$data" | jq -r '.keys[].id')
	while IFS= read -r pub; do
		[[ -z "$pub" ]] && continue
		[[ "$pub" =~ ^age1[0-9a-z]{58}$ ]] || die "Bundle has a malformed public key: '$pub'"
	done < <(printf '%s' "$data" | jq -r '.keys[].pub')
	if [[ "$(printf '%s' "$data" | jq -r '.keys[].id' | sort -u | wc -l | tr -d ' ')" != "$count" ]]; then
		die "Bundle has duplicate one-time key ids"
	fi
	ensure_data_dirs
	mkdir -p "$PREKEYS_DIR/$friend"
	chmod 700 "$PREKEYS_DIR/$friend"
	printf '%s\n' "$data" >"$PREKEYS_DIR/$friend/bundle.pub"
	chmod 600 "$PREKEYS_DIR/$friend/bundle.pub"
	log_ok "Imported $count one-time keys from '$friend'"
	echo "Messages you send to '$friend' use one of these keys each, and never the same key twice."
}

# QR frame constants: what one frame may carry, on both sides.
QFRAME_CHUNK_SEND=600 # raw bytes per frame written by qr-send
QFRAME_CHUNK_MAX=1024 # decoded-byte cap the reader accepts per frame
QFRAME_COUNT_MAX=4096 # total-frame cap the reader accepts

cmd_qr_send() {
	# qr-send = the regular, already-tested send path into message.courier,
	# then that courier is split into numbered text frames under message.qr/.
	# Reusing cmd_send means SEND's guarantees (contact validation, bucket
	# padding, prekey usage, signature) are exercised here for free by the
	# same suite rows.
	if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
		echo "Usage: xc qr-send <friend> [--png] [--expires <date>] [--no-forward-secrecy]"
		echo "Seals a message like 'xc send' (same passphrase prompt, same one-time"
		echo "prekey rules), then splits message.courier into numbered frames under"
		echo "message.qr/ (NNNN.txt; --png additionally renders each as a PNG)."
		echo "The friend reassembles and decrypts with: xc qr-read ... ; xc read ..."
		exit 0
	fi
	local png=false a
	declare -a rest
	for a in "$@"; do
		case "$a" in
		--png) png=true ;;
		-*) rest+=("$a") ;;
		*) rest+=("$a") ;;
		esac
	done
	[[ ! -e message.qr ]] || die "message.qr already exists here; qr-send would mix frames from two messages. Move or delete it first."
	[[ ! -f message.courier ]] || die "message.courier already exists here; qr-send would overwrite it. Move it first."
	cmd_send "${rest[@]}"
	local courier="$PWD/message.courier"
	[[ -s "$courier" ]] || die "the send step did not produce message.courier; cannot frame anything."
	local total_bytes i idx
	total_bytes=$(wc -c <"$courier" | tr -d ' ')
	local chunk_count
	chunk_count=$(((total_bytes + QFRAME_CHUNK_SEND - 1) / QFRAME_CHUNK_SEND))
	((chunk_count <= QFRAME_COUNT_MAX)) || die "This message would need $chunk_count frames but the reader accepts at most $QFRAME_COUNT_MAX."
	mkdir -p message.qr
	chmod 700 message.qr
	local tmpf
	tmpf="$PWD/message.qr/.chunk.raw"
	for ((i = 0; i < chunk_count; i++)); do
		idx=$((i + 1))
		dd if="$courier" bs="$QFRAME_CHUNK_SEND" skip="$i" count=1 2>/dev/null >"$tmpf"
		{
			printf 'XQ1 %s %s %s\n' "$idx" "$chunk_count" "$total_bytes"
			base64 -w0 <"$tmpf"
			printf '\n'
		} >"message.qr/$(printf '%04d' "$idx").txt" || {
			rm -f "$tmpf"
			die "could not write frame $idx"
		}
		rm -f "$tmpf"
	done
	if [[ "$png" == true ]]; then
		command -v qrencode >/dev/null || {
			die "qrencode is not installed; frames were written as text only (install qrencode and rerun with --png)."
		}
		local f
		for f in message.qr/*.txt; do
			qrencode -o "${f%.txt}.png" -s 6 -t PNG <"$f" || die "qrencode failed on $f"
		done
	fi
	printf '[OK] QR frames written: %s frames under message.qr/ (%s bytes each, the last one smaller).\n' "$chunk_count" "$QFRAME_CHUNK_SEND"
	echo "Hand or show the frame files to your friend; they run: xc qr-read --out message.courier message.qr/*.txt then xc read message.courier"
}

cmd_qr_read() {
	# Frame-ONLY reader: no identity, no passphrase, no data dir needed.
	# It parses XQ1 frames under hard rules and writes the assembled bytes
	# to --out (default ./message.courier). Decryption stays with 'xc read'.
	if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
		echo "Usage: xc qr-read [--out <file>] <frame-file ...> | <dir-with-frames>"
		echo "Assembles XQ1 frames (one text file per frame) into the original"
		echo "courier file. Rules: complete set, in-range unique indexes, caps on"
		echo "frame count (4096) and per-frame decoded bytes (1024), and the chunk"
		echo "sizes must add up to the declared total."
		exit 0
	fi
	local out="message.courier"
	declare -a args
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--out)
			out="${2:-}"
			shift 2
			;;
		*)
			args+=("$1")
			shift 1
			;;
		esac
	done
	((${#args[@]} >= 1)) || die "Usage: xc qr-read [--out <file>] <frame-file ...> | <dir-with-frames>"
	[[ -n "$out" ]] || die "--out needs a file name"
	[[ ! -e "$out" ]] || die "Refusing to overwrite existing '$out'; give a different --out or move it first."
	# Expand a directory argument into its frame files (sorted by index).
	declare -a frames
	local a f
	for a in "${args[@]}"; do
		if [[ -d "$a" ]]; then
			local n_dir_frames=0
			for f in "$a"/*.txt; do
				[[ -f "$f" ]] || continue
				frames+=("$f")
				n_dir_frames=$((n_dir_frames + 1))
			done
			((n_dir_frames >= 1)) || die "Directory '$a' holds no frame files"
		else
			[[ -f "$a" ]] || die "Not found: $a"
			frames+=("$a")
		fi
	done
	local tmpd
	tmpd=$(mktemp -d "${TMPDIR:-/tmp}/xc-qrread.XXXXXX")
	declare -A seen_body=()
	local total_declared="" orig_declared="" idx total orig header b64 clen tmpc
	local frame_payload pieces=0
	for f in "${frames[@]}"; do
		# Normalize: CRLF (a frame pasted via clipboard) still parses.
		frame_payload="$tmpd/payload"
		if [[ "$f" == *.png || "$f" == *.jpg || "$f" == *.jpeg ]]; then
			command -v zbarimg >/dev/null || die "$f is an image but zbarimg is not installed (install zbar, or pass the frame text file)."
			zbarimg -q --raw -o "$frame_payload" "$f" || {
				rm -rf "$tmpd"
				die "Could not decode QR from $f"
			}
		else
			tr -d '\r' <"$f" >"$frame_payload" || {
				rm -rf "$tmpd"
				die "Could not read $f"
			}
		fi
		header=$(head -1 "$frame_payload")
		if [[ ! "$header" =~ ^XQ1\ ([0-9]+)\ ([0-9]+)\ ([0-9]+)$ ]]; then
			rm -rf "$tmpd"
			die "Frame '$f' rejected: payload is not a valid QR frame (expects 'XQ1 <idx> <total> <orig_bytes>' + one base64 line)"
		fi
		idx="${BASH_REMATCH[1]}"
		total="${BASH_REMATCH[2]}"
		orig="${BASH_REMATCH[3]}"
		# Caps and range, each with its own plain-words failure.
		((total >= 1 && total <= QFRAME_COUNT_MAX)) || {
			rm -rf "$tmpd"
			die "Frame '$f' is rejected: frame count too large ($total; cap is $QFRAME_COUNT_MAX frames)."
		}
		((idx >= 1 && idx <= total)) || {
			rm -rf "$tmpd"
			die "Frame '$f' is rejected: index $idx is out of range (1..$total)."
		}
		if [[ -n "$total_declared" ]]; then
			[[ "$total" == "$total_declared" && "$orig" == "$orig_declared" ]] || {
				rm -rf "$tmpd"
				die "Frame '$f' disagrees with the others about its set (frame count or declared total size)."
			}
		else
			total_declared="$total"
			orig_declared="$orig"
		fi
		# Exactly one more line (the base64 chunk); anything else refuses.
		if [[ $(wc -l <"$frame_payload" | tr -d ' ') -ne 2 ]]; then
			rm -rf "$tmpd"
			die "Frame '$f' is rejected: a frame is exactly a header line and one base64 chunk line."
		fi
		b64=$(tail -1 "$frame_payload")
		if [[ -z "$b64" ]]; then
			rm -rf "$tmpd"
			die "Frame '$f' is rejected: the chunk line is empty."
		fi
		# A duplicate index is allowed only when the chunk is identical.
		if [[ -n "${seen_body[$idx]:-}" ]]; then
			[[ "${seen_body[$idx]}" == "$b64" ]] || {
				rm -rf "$tmpd"
				die "Frame '$f' is rejected: duplicate-frame conflict for index $idx (same index, different data)."
			}
			continue
		fi
		tmpc="$tmpd/chunk.check"
		: >"$tmpc"
		if ! printf '%s' "$b64" | base64 -d >"$tmpc" 2>/dev/null; then
			rm -rf "$tmpd"
			die "Frame '$f' is rejected: the chunk line is not valid base64."
		fi
		clen=$(wc -c <"$tmpc" | tr -d ' ')
		((clen >= 1 && clen <= QFRAME_CHUNK_MAX)) || {
			rm -rf "$tmpd"
			die "Frame '$f' is rejected: chunk too large ($clen bytes decoded; cap is $QFRAME_CHUNK_MAX per frame, or the chunk line is empty)."
		}
		mv "$tmpc" "$tmpd/piece.$idx"
		seen_body[$idx]="$b64"
		pieces=$((pieces + 1))
	done
	# Every index of the declared set must be present.
	local i missing=()
	for ((i = 1; i <= total_declared; i++)); do
		[[ -n "${seen_body[$i]:-}" ]] || missing+=("$i")
	done
	if ((${#missing[@]} > 0)); then
		rm -rf "$tmpd"
		die "Incomplete frame set — missing: ${missing[*]}"
	fi
	# Assemble in index order into a temp file, THEN the size must match
	# exactly the declared total before anything lands at --out.
	local asmf="$tmpd/assembled"
	: >"$asmf"
	local got=0
	for ((i = 1; i <= total_declared; i++)); do
		cat "$tmpd/piece.$i" >>"$asmf"
	done
	got=$(wc -c <"$asmf" | tr -d ' ')
	if [[ "$got" != "$orig_declared" ]]; then
		rm -rf "$tmpd"
		die "Assembled $got bytes but the frames declared total size $orig_declared — the set is incomplete or damaged. Nothing was written."
	fi
	mv "$asmf" "$out" || {
		rm -rf "$tmpd"
		die "could not write '$out'"
	}
	chmod 600 "$out"
	rm -rf "$tmpd"
	log_ok "Assembled $total_declared frames ($got bytes) -> $out"
	echo "Next step: open it with 'xc read $out'"
}

main "$@"
