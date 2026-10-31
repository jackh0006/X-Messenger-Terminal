#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# X Messenger Terminal — xc
# Offline encrypted message courier using age + OpenSSH signatures

set -euo pipefail

VERSION="0.1.0"
DATA_DIR="${XCOURIER_DATA_DIR:-$HOME/.xcourier}"
IDENTITY_DIR="$DATA_DIR/identity"
CONTACTS_DIR="$DATA_DIR/contacts"
PREKEYS_DIR="$DATA_DIR/prekeys"
REPLAY_DIR="$DATA_DIR/replay"
VAULT_DIR="$DATA_DIR/vault"

declare -A BUCKETS=( ["1k"]=1024 ["4k"]=4096 ["16k"]=16384 ["64k"]=65536 )
BUCKET_ORDER=("1k" "4k" "16k" "64k")

if [[ -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
else RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; NC=''; fi

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err() { echo -e "${RED}[ERR]${NC} $*"; }

die() { log_err "$*"; exit 1; }
confirm() { read -rp "$1 [y/N] " ans; [[ "$ans" =~ ^[Yy]$ ]]; }

ensure_data_dirs() {
    mkdir -p "$IDENTITY_DIR" "$CONTACTS_DIR" "$PREKEYS_DIR" "$REPLAY_DIR" "$VAULT_DIR"
    chmod 700 "$DATA_DIR" "$IDENTITY_DIR" "$CONTACTS_DIR" "$PREKEYS_DIR" "$REPLAY_DIR" "$VAULT_DIR" 2>/dev/null || true
}

require_tool() { command -v "$1" >/dev/null 2>&1 || die "Required tool '$1' not found. Install: $2"; }

read_passphrase() {
    local p1 p2; read -rsp "$1: " p1; echo; read -rsp "Confirm: " p2; echo
    [[ "$p1" == "$p2" ]] || die "Passphrases do not match"
    [[ ${#p1} -ge 12 ]] || die "Passphrase must be at least 12 characters"
    echo "$p1"
}

read_passphrase_verify() { local p; read -rsp "$1: " p; echo; echo "$p"; }

generate_identity() {
    local pass="$1"; ensure_data_dirs
    age-keygen > "$IDENTITY_DIR/age.pub" 2>"$IDENTITY_DIR/age.priv"
    ssh-keygen -t ed25519 -N "" -f "$IDENTITY_DIR/ssh" -C "xc-identity-$(date +%s)" >/dev/null
    age -p -e -r "$(cat "$IDENTITY_DIR/age.pub")" < "$IDENTITY_DIR/age.priv" > "$IDENTITY_DIR/age.priv.enc"
    age -p -e -r "$(cat "$IDENTITY_DIR/age.pub")" < "$IDENTITY_DIR/ssh" > "$IDENTITY_DIR/ssh.enc"
    shred -u "$IDENTITY_DIR/age.priv" "$IDENTITY_DIR/ssh" 2>/dev/null || rm -f "$IDENTITY_DIR/age.priv" "$IDENTITY_DIR/ssh"
    log_ok "Identity created and encrypted"
}

load_identity() {
    local pass="$1"; [[ -f "$IDENTITY_DIR/age.pub" ]] || die "No identity. Run 'xc init'."
    age -d -i - -p < "$IDENTITY_DIR/age.priv.enc" <<< "$pass" > /tmp/age.priv 2>/dev/null || die "Incorrect passphrase"
    age -d -i - -p < "$IDENTITY_DIR/ssh.enc" <<< "$pass" > /tmp/ssh.priv 2>/dev/null || die "Incorrect passphrase"
    AGE_PUBKEY=$(cat "$IDENTITY_DIR/age.pub")
    SSH_PUBKEY=$(cat "$IDENTITY_DIR/ssh.pub")
    AGE_PRIVKEY_FILE="/tmp/age.priv"
    SSH_PRIVKEY_FILE="/tmp/ssh.priv"
}

cleanup_identity() { rm -f /tmp/age.priv /tmp/ssh.priv 2>/dev/null || true; }

get_fingerprint() { ssh-keygen -lf "$IDENTITY_DIR/ssh.pub" | awk '{print $2}' | sed 's/://g' | fold -w 2 | paste -sd' ' - | cut -d' ' -f1-6; }

add_contact() {
    local name="$1"; local method="${2:-paste}"; local file="${3:-}"
    [[ "$name" =~ ^[A-Za-z0-9_-]{1,32}$ ]] || die "Invalid name"
    [[ -f "$CONTACTS_DIR/$name.json" ]] && die "Contact '$name' exists"
    
    local data; case "$method" in paste) data=$(cat);; file) [[ -f "$file" ]] || die "File not found"; data=$(cat "$file");; qr) die "QR not implemented";; *) die "Unknown method"; esac
    
    local age_pub=$(echo "$data" | grep -o 'age1[0-9a-z]*' | head -1)
    local ssh_pub=$(echo "$data" | grep -o 'ssh-ed25519 [A-Za-z0-9+/]*=' | head -1)
    local fp=$(echo "$data" | grep -oE '([a-f0-9]{2}:){5}[a-f0-9]{2}' | head -1)
    [[ -n "$age_pub" && -n "$ssh_pub" ]] || die "Invalid contact data"
    [[ "$age_pub" =~ ^age1[0-9a-z]{58}$ ]] || die "Invalid age pubkey"
    [[ "$ssh_pub" =~ ^ssh-ed25519\ [A-Za-z0-9+/]+=*$ ]] || die "Invalid SSH pubkey"
    
    cat > "$CONTACTS_DIR/$name.json" <<EOF
{"name":"$name","age_pub":"$age_pub","ssh_pub":"$ssh_pub","fingerprint":"$fp","verified":false}
EOF
    chmod 600 "$CONTACTS_DIR/$name.json"
    echo "Contact '$name' added (unverified). Fingerprint: $fp"
    echo "Verify in person, then run: xc verify $name"
}

verify_contact() {
    local name="$1"; local f="$CONTACTS_DIR/$name.json"
    [[ -f "$f" ]] || die "Contact not found"
    echo "Fingerprint: $(jq -r .fingerprint "$f")"
    confirm "Mark verified?" || die "Cancelled"
    jq '.verified=true' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    log_ok "Contact '$name' verified"
}

pad_to_bucket() {
    local in="$1"; local len=${#in}; local bucket=""
    for b in "${BUCKET_ORDER[@]}"; do [[ $len -le $((${BUCKETS[$b]} - 4)) ]] && bucket=$b && break; done
    [[ -n "$bucket" ]] || die "Message too large (max 64 KiB)"
    local sz=${BUCKETS[$bucket]}; printf "%08x%s" "$len" "$in" | head -c $((sz))
}

unpad_message() { echo "${1:8:$((16#${1:0:8}))}"; }

sign_message() { echo -n "$1" | ssh-keygen -Y sign -f "$2" -n "x-courier" | base64 -w0; }
verify_signature() { echo -n "$1" | base64 -d | ssh-keygen -Y verify -f "$3" -n "x-courier" -s - <<< "$2" 2>/dev/null; }

make_signed_bundle() {
    local pt="$1"; local recip_fp="$2"; local expiry="${3:-}"
    local padded=$(pad_to_bucket "$pt")
    local msg_id=$(head -c16 /dev/urandom | xxd -p -c 32)
    local ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local sender_fp=$(get_fingerprint)
    local payload=$(base64 -w0 <<< "$padded")
    local canon=$(jq -c -S -n --arg v 1 --arg mid "$msg_id" --arg ts "$ts" --arg sfp "$sender_fp" --arg rfp "$recip_fp" --arg exp "$expiry" --arg pl "$(base64 -w0 <<< "$padded")" '{v:1, msg_id:$mid, timestamp:$ts, sender_fp:$sfp, recipient_fp:$rfp, expiry:$exp, payload:$pl}')
    local sig=$(sign_message "$canon" "$SSH_PRIVKEY_FILE")
    echo "$canon" | jq --arg sig "$sig" '. + {sig: $sig}'
}

verify_signed_bundle() {
    local b="$1"; local sender_ssh="$2"
    local sig=$(echo "$b" | jq -r .sig)
    local canon=$(echo "$b" | jq -c -S 'del(.sig)')
    verify_signature "$canon" "$sig" <<< "$sender_ssh" || return 1
    local exp=$(echo "$b" | jq -r .expiry)
    [[ "$exp" == "null" || "$exp" == "" || $(date -u +%s) -lt $(date -d "$exp" +%s) ]] || die "Message expired"
    local rfp=$(echo "$b" | jq -r .recipient_fp)
    [[ "$rfp" == "$(get_fingerprint)" ]] || die "Not for this recipient"
    echo "$b" | jq -r .payload
}

replay_check() { local h=$(echo -n "$1" | sha256sum | cut -d' ' -f1); [[ -f "$REPLAY_DIR/seen.hashes" ]] && grep -q "^$h$" "$REPLAY_DIR/seen.hashes"; }
replay_mark() { local h=$(echo -n "$1" | sha256sum | cut -d' ' -f1); echo "$h" >> "$REPLAY_DIR/seen.hashes"; }

cmd_init() {
    [[ "${1:-}" == "--help" ]] && { sed -n "/^cmd_init()/,/^cmd_[a-z]/p" /bin/bash | head -n -1 | sed "s/^cmd_init() {/Usage: xc init/; s/    //" | head -20; exit 0; }
    local pass="" noi=false
    while [[ $# -gt 0 ]]; do case $1 in --passphrase) pass=$2; shift 2;; --no-interactive) noi=true; shift;; *) die "Unknown: $1";; esac; done
    [[ -f "$IDENTITY_DIR/age.pub" ]] && die "Identity exists. Use 'xc wipe'."
    if $noi; then [[ -n "$pass" ]] || die "Passphrase required"; else pass=$(read_passphrase "Enter vault passphrase (min 12 chars)"); fi
    generate_identity "$pass"; log_ok "Identity created. Run 'xc id'."
}

cmd_id() {
    local qr=false; [[ "$1" == "--qr" ]] && qr=true
    local pass=$(read_passphrase_verify "Enter vault passphrase")
    load_identity "$pass"
    echo "Age: $AGE_PUBKEY"; echo "SSH: $SSH_PUBKEY"; echo "Fingerprint: $(get_fingerprint)"
    $qr && echo "age:$AGE_PUBKEY|ssh:$SSH_PUBKEY|fp:$(get_fingerprint)" | qrencode -t UTF8
    cleanup_identity
}

cmd_add() {
    local name=$1 method=${2:-paste} file=${3:-}
    [[ "$name" =~ ^[A-Za-z0-9_-]{1,32}$ ]] || die "Invalid name"
    [[ -f "$CONTACTS_DIR/$name.json" ]] && die "Contact exists"
    local data; case ${2:-paste} in paste) data=$(cat);; file) [[ -f "$3" ]] || die "File not found"; data=$(cat "$3");; qr) die "QR not implemented";; *) die "Unknown method";; esac
    local ap=$(echo "$data" | grep -o 'age1[0-9a-z]*' | head -1)
    local sp=$(echo "$data" | grep -o 'ssh-ed25519 [A-Za-z0-9+/]*=' | head -1)
    local fp=$(echo "$data" | grep -oE '([a-f0-9]{2}:){5}[a-f0-9]{2}' | head -1)
    [[ -n "$ap" && -n "$sp" ]] || die "Invalid data"
    [[ "$ap" =~ ^age1[0-9a-z]{58}$ ]] || die "Invalid age pubkey"
    [[ "$sp" =~ ^ssh-ed25519\ [A-Za-z0-9+/]+=*$ ]] || die "Invalid SSH pubkey"
    cat > "$CONTACTS_DIR/$name.json" <<EOF
{"name":"$name","age_pub":"$ap","ssh_pub":"$sp","fingerprint":"$fp","verified":false}
EOF
    chmod 600 "$CONTACTS_DIR/$name.json"
    echo "Added '$name' (unverified). Fingerprint: $fp"
    echo "Verify in person, then: xc verify $name"
}

cmd_verify() { verify_contact "$1"; }

cmd_send() {
    local recip=$1; [[ -n "$recip" ]] || die "Usage: xc send <friend>"
    local cf="$CONTACTS_DIR/$recip.json"; [[ -f "$cf" ]] || die "Contact not found"
    [[ $(jq -r .verified "$cf") == true ]] || die "Not verified. Use --force or verify first."
    local msg=$(cat); [[ -n "$msg" ]] || die "No message"
    local pass=$(read_passphrase_verify "Passphrase"); load_identity "$pass"
    local rap=$(jq -r .age_pub "$cf"); local rfp=$(jq -r .fingerprint "$cf")
    local bundle=$(make_signed_bundle "$msg" "$rfp" "")
    echo "$bundle" | age -e -r "$rap" > message.courier.tmp
    echo "X-COURIER/1" > message.courier
    cat message.courier.tmp >> message.courier; rm message.courier.tmp
    log_ok "Sealed to $recip: message.courier"
    cleanup_identity
}

cmd_read() {
    local file=$1; [[ -n "$file" ]] || die "Usage: xc read <file|->"
    local input; [[ "$file" == "-" ]] && input=$(cat) || { [[ -f "$file" ]] || die "Not found: $file"; input=$(cat "$file"); }
    [[ "$(head -1 <<< "$input")" == "X-COURIER/1" ]] || die "Not a .courier file"
    local pass=$(read_passphrase_verify "Passphrase"); load_identity "$pass"
    local armored=$(tail -n +2 <<< "$input")
    local bundle=$(echo "$armored" | age -d -i "$AGE_PRIVKEY_FILE")
    local payload=$(verify_signed_bundle "$bundle" "$(cat "$CONTACTS_DIR"/*.json | jq -r .ssh_pub | head -1)")
    local pt=$(unpad_message "$(base64 -d <<< "$payload")")
    local mid=$(echo "$bundle" | jq -r .msg_id)
    replay_check "$mid" && die "Replay detected"
    replay_mark "$mid"
    echo "$pt"; log_ok "Decrypted from $(echo "$bundle" | jq -r .sender_fp)"
    cleanup_identity
}

cmd_doctor() {
    log_info "Doctor"; for t in age age-keygen ssh-keygen ssh qrencode zbarimg minisign; do command -v "$t" >/dev/null && log_ok "$t" || log_warn "$t missing"; done
    [[ -d "$DATA_DIR" ]] && [[ $(stat -c %a "$DATA_DIR") == 700 ]] && log_ok "Data dir 700" || log_warn "Data dir perms"
    unshare -rn true 2>/dev/null && log_ok "unshare -rn works" || log_warn "unshare -rn needs root"
    [[ -z "${HISTFILE:-}" ]] && log_ok "HISTFILE unset" || log_warn "HISTFILE set"
}

cmd_selftest() {
    log_info "Self-test..."; local td=$(mktemp -d -t xc_test_XXXXXX)
    XCOURIER_DATA_DIR="$td/alice" "$0" init --passphrase a --no-interactive
    XCOURIER_DATA_DIR="$td/bob" "$0" init --passphrase b --no-interactive
    XCOURIER_DATA_DIR="$td/alice" "$0" id > /tmp/a.id
    XCOURIER_DATA_DIR="$td/bob" "$0" id > /tmp/b.id
    XCOURIER_DATA_DIR="$td/alice" "$0" add bob < /tmp/b.id
    XCOURIER_DATA_DIR="$td/bob" "$0" add alice < /tmp/a.id
    XCOURIER_DATA_DIR="$td/alice" "$0" send bob <<< "selftest"
    XCOURIER_DATA_DIR="$td/bob" "$0" read message.courier
    rm -rf "$td" /tmp/a.id /tmp/b.id; log_ok "Self-test passed"
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
    read -r c; case $c in 1) echo "NYI";; 2) echo "NYI";; 3) echo "NYI";; 4) cmd_id;; 5) cmd_doctor;; 0) exit;; *) echo "Invalid";; esac
}

main() {
    local cmd="${1:-menu}"; shift || true
    case $cmd in
        --help|help)
            cat <<EOF
X Messenger Terminal — Offline Encrypted Courier

Usage: xc <command> [options]
Commands: init, id, add, verify, send, read, doctor, selftest, wipe, rotate, prekeys, qr-send, qr-read
Examples: xc init; xc id --qr; echo "msg" | xc send alice; xc read file.courier
EOF
            exit 0;;
        init) cmd_init "$@";; id) cmd_id "$@";; add) cmd_add "$@";; verify) cmd_verify "$@";;
        send) cmd_send "$@";; read) cmd_read "$@";; doctor) cmd_doctor;; selftest) cmd_selftest;;
        --version) echo "X Messenger Terminal $VERSION";;
        --help|help) cat <<'EOF'
X Messenger Terminal — Offline Encrypted Courier
Usage: xc <command> [options]
Commands: init, id, add, verify, send, read, doctor, selftest, wipe, rotate, prekeys, qr-send, qr-read
Examples: xc init; xc id --qr; echo "msg" | xc send alice; xc read file.courier
EOF
            ;;
        menu|"") show_menu;;
        *) die "Unknown: $cmd. Run 'xc --help'.";;
    esac
}

trap cleanup_identity EXIT INT TERM HUP
main "$@"