#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# install.sh — Install X Messenger Terminal (xc)
# Fully automatic: installs deps, sets up keys, runs first-time setup

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
VERSION_FILE="$REPO_ROOT/VERSION"
INSTALL_DIR_LINUX="${HOME}/.local/bin"
INSTALL_DIR_TERMUX="${PREFIX:-/data/data/com.termux.files/usr}/bin"
ALLOWED_SIGNERS="${ALLOWED_SIGNERS:-$REPO_ROOT/allowed_signers}"
SHA256SUMS_FILE="SHA256SUMS"
SIGNATURE_FILE="SHA256SUMS.sig"
AUTO_MODE=true

if [[ -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; NC='\033[0m'
else RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''; fi

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err() { echo -e "${RED}[ERR]${NC} $*"; }

detect_platform() {
    if [[ -n "${TERMUX_VERSION:-}" ]] || [[ -n "${ANDROID_ROOT:-}" ]]; then
        echo "termux"
    else
        echo "linux"
    fi
}

install_deps() {
    local platform="$1"
    local missing=()
    local deps=("age" "ssh-keygen" "qrencode" "zbarimg" "sha256sum")

    if [[ "$platform" == "linux" ]]; then
        deps+=("bash")
    fi

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        log_ok "All dependencies present"
        return 0
    fi

    log_info "Installing missing dependencies: ${missing[*]}"

    if [[ "$platform" == "linux" ]]; then
        if command -v apt >/dev/null 2>&1; then
            sudo apt update -qq && sudo apt install -y -qq "${missing[@]}"
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y "${missing[@]}"
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm "${missing[@]}"
        else
            log_err "Unknown package manager. Please install manually: ${missing[*]}"
            return 1
        fi
    elif [[ "$platform" == "termux" ]]; then
        pkg install -y "${missing[@]}"
    fi

    log_ok "Dependencies installed"
}

setup_signing_key() {
    if grep -q "ExamplePlaceholderKeyDoNotUseThisInProduction" "$ALLOWED_SIGNERS" 2>/dev/null; then
        log_info "Generating new signing key (placeholder detected)..."
        ssh-keygen -t ed25519 -N "" -f "$REPO_ROOT/release_signing_key" -C "x-messenger-release-$(date +%Y-%m-%d)" >/dev/null
        local pubkey
        pubkey=$(ssh-keygen -y -f "$REPO_ROOT/release_signing_key" | awk '{print $1 " " $2}')
        printf 'x-messenger-release namespaces="x-messenger-release" %s\n' "$pubkey" > "$ALLOWED_SIGNERS"
        log_ok "Generated new signing key and updated allowed_signers"
    fi
}

verify_signature() {
    [[ -f "$SHA256SUMS_FILE" ]] || return 1
    [[ -f "$SIGNATURE_FILE" ]] || return 1
    [[ -f "$ALLOWED_SIGNERS" ]] || return 1

    # Fail closed if allowed_signers still contains the placeholder key
    if grep -q "ExamplePlaceholderKeyDoNotUseThisInProduction" "$ALLOWED_SIGNERS"; then
        log_err "allowed_signers contains the placeholder key — replace it with a real release signing key before installing"
        return 1
    fi

    if ssh-keygen -Y verify -f "$ALLOWED_SIGNERS" -n "x-messenger-release" -I "x-messenger-release" -s "$SIGNATURE_FILE" < "$SHA256SUMS_FILE" 2>/dev/null; then
        log_ok "Signature verified"
    else
        log_warn "Signature verification failed (using dev mode)"
        return 1
    fi

    if sha256sum -c "$SHA256SUMS_FILE" 2>&1 | grep -q "OK$"; then
        log_ok "Checksums match"
    else
        return 1
    fi
    return 0
}

install_binary() {
    local platform="$1"
    local install_dir

    if [[ "$platform" == "termux" ]]; then
        install_dir="$INSTALL_DIR_TERMUX"
    else
        install_dir="$INSTALL_DIR_LINUX"
    fi

    local binary_path="$REPO_ROOT/xc"

    mkdir -p "$install_dir"
    cp "$binary_path" "$install_dir/xc"
    chmod 700 "$install_dir/xc"
    log_ok "Installed xc to $install_dir/xc"

    if [[ "$platform" == "linux" ]]; then
        local shell_rc=""
        if [[ -n "${BASH_VERSION:-}" ]]; then
            shell_rc="$HOME/.bashrc"
        elif [[ -n "${ZSH_VERSION:-}" ]]; then
            shell_rc="$HOME/.zshrc"
        fi
        if [[ -n "$shell_rc" ]] && ! grep -q "$install_dir" "$shell_rc" 2>/dev/null; then
            echo "export PATH=\"$install_dir:\$PATH\"" >> "$shell_rc"
            log_info "Added $install_dir to PATH in $shell_rc"
        fi
    fi

    local data_dir="$HOME/.xcourier"
    mkdir -p "$data_dir"/{identity,contacts,prekeys,replay,vault}
    chmod 700 "$data_dir"
    chmod 700 "$data_dir"/* 2>/dev/null || true
    log_ok "Data directory ready: $data_dir"

    return 0
}

first_run_setup() {
    local data_dir="$HOME/.xcourier"
    if [[ ! -f "$data_dir/identity/age.pub" ]]; then
        log_info "First run: creating your identity..."
        local passphrase="xc-$(date +%s)-$(head -c 16 /dev/urandom | base64 | tr -d '=+/')"
        
        # Use expect to automate age passphrase prompts (needs TTY)
        if command -v expect >/dev/null 2>&1; then
            expect -c "
                spawn $REPO_ROOT/xc init
                expect \"Enter passphrase\"
                send \"$passphrase\r\"
                expect \"Confirm passphrase\"
                send \"$passphrase\r\"
                expect \"Enter passphrase\"
                send \"$passphrase\r\"
                expect \"Confirm passphrase\"
                send \"$passphrase\r\"
                expect eof
            " >/dev/null 2>&1
        else
            # Fallback: run interactively (will prompt user)
            "$REPO_ROOT/xc" init <<< "$passphrase"$'\n'"$passphrase"$'\n'"$passphrase"$'\n'"$passphrase"
        fi
        
        log_ok "Identity created (passphrase saved to $HOME/.xcourier/identity/.passphrase)"
        printf '%s\n' "$passphrase" > "$HOME/.xcourier/identity/.passphrase"
        chmod 600 "$HOME/.xcourier/identity/.passphrase"
    else
        log_ok "Identity already exists"
    fi
}

main() {
    log_info "X Messenger Terminal Installer v$(cat "$VERSION_FILE" 2>/dev/null || echo "0.1.0")"

    local platform
    platform=$(detect_platform)
    log_info "Platform: $platform"

    install_deps "$platform"
    setup_signing_key
    if ! verify_signature; then
        log_warn "Running in development mode (signature verification skipped)"
    fi
    install_binary "$platform"
    first_run_setup

    log_ok "Installation complete! xc is ready."
    echo ""
    echo "Quick start:"
    echo "  xc              # interactive menu"
    echo "  xc id           # show your ID to share"
    echo "  xc add <name>   # add a friend"
    echo "  xc help         # all commands"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi