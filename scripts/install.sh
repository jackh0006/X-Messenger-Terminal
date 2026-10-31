#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# install.sh — Install X Messenger Terminal (xc)
# Verifies SHA256SUMS and signature, checks dependencies, installs to ~/.local/bin or $PREFIX/bin

set -euo pipefail

# Configuration
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$REPO_ROOT/VERSION"
BINARY_NAME="xc"
INSTALL_DIR_LINUX="${HOME}/.local/bin"
INSTALL_DIR_TERMUX="${PREFIX}/bin"
MINISIGN_PUBKEY=""  # Set at release time
SHA256SUMS_FILE="SHA256SUMS"
SIGNATURE_FILE="SHA256SUMS.sig"
DRY_RUN=false
SKIP_VERIFY=false
PREFIX_OVERRIDE=""

# Colors (respect NO_COLOR)
if [[ -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err() { echo -e "${RED}[ERR]${NC} $*"; }

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
    --dry-run          Show what would be done without doing it
    --skip-verify      Skip SHA256SUMS + signature verification (NOT RECOMMENDED)
    --prefix DIR       Installation directory (default: ~/.local/bin on Linux, \$PREFIX/bin on Termux)
    --help             Show this help

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run) DRY_RUN=true; shift ;;
            --skip-verify) SKIP_VERIFY=true; shift ;;
            --prefix) PREFIX_OVERRIDE="$2"; shift 2 ;;
            --help) usage; exit 0 ;;
            *) log_err "Unknown option: $1"; usage; exit 1 ;;
        esac
    done
}

detect_platform() {
    if [[ -n "${TERMUX_VERSION:-}" ]] || [[ -n "${ANDROID_ROOT:-}" ]]; then
        echo "termux"
    else
        echo "linux"
    fi
}

check_dependencies() {
    local platform="$1"
    local missing=()
    local deps=("age" "ssh-keygen" "qrencode" "zbarimg" "minisign" "sha256sum")

    if [[ "$platform" == "linux" ]]; then
        deps+=("bash")
    fi

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_err "Missing dependencies: ${missing[*]}"
        if [[ "$platform" == "linux" ]]; then
            log_info "Install with: apt update && apt install -y ${missing[*]}"
        else
            log_info "Install with: pkg install ${missing[*]}"
        fi
        return 1
    fi
    log_ok "All dependencies found"
    return 0
}

verify_signature() {
    if [[ "$SKIP_VERIFY" == "true" ]]; then
        log_warn "Skipping signature verification (--skip-verify)"
        return 0
    fi

    if [[ -z "$MINISIGN_PUBKEY" ]]; then
        log_err "MINISIGN_PUBKEY not set in script — cannot verify signature"
        log_info "Set MINISIGN_PUBKEY in install.sh or use --skip-verify (NOT RECOMMENDED)"
        return 1
    fi

    if [[ ! -f "$SHA256SUMS_FILE" ]]; then
        log_err "SHA256SUMS file not found: $SHA256SUMS_FILE"
        return 1
    fi

    if [[ ! -f "$SIGNATURE_FILE" ]]; then
        log_err "Signature file not found: $SIGNATURE_FILE"
        return 1
    fi

    log_info "Verifying minisign signature on $SHA256SUMS_FILE..."
    if minisign -Vm "$SHA256SUMS_FILE" -P "$MINISIGN_PUBKEY" 2>/dev/null; then
        log_ok "Signature verified"
    else
        log_err "Signature verification FAILED"
        return 1
    fi

    log_info "Verifying checksums..."
    if sha256sum -c "$SHA256SUMS_FILE" 2>&1 | grep -q "OK$"; then
        log_ok "All checksums match"
    else
        log_err "Checksum verification FAILED"
        return 1
    fi

    return 0
}

install_binary() {
    local platform="$1"
    local install_dir

    if [[ -n "$PREFIX_OVERRIDE" ]]; then
        install_dir="$PREFIX_OVERRIDE"
    elif [[ "$platform" == "termux" ]]; then
        install_dir="$INSTALL_DIR_TERMUX"
    else
        install_dir="$INSTALL_DIR_LINUX"
    fi

    local binary_path="$REPO_ROOT/xc"

    if [[ ! -f "$binary_path" ]]; then
        log_err "Binary not found: $binary_path"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would install $binary_path to $install_dir/xc"
        return 0
    fi

    mkdir -p "$install_dir"
    cp "$binary_path" "$install_dir/xc"
    chmod 700 "$install_dir/xc"
    log_ok "Installed xc to $install_dir/xc"

    # Ensure install dir is in PATH (Linux only)
    if [[ "$platform" == "linux" ]]; then
        local shell_rc=""
        if [[ -n "${BASH_VERSION:-}" ]]; then
            shell_rc="$HOME/.bashrc"
        elif [[ -n "${ZSH_VERSION:-}" ]]; then
            shell_rc="$HOME/.zshrc"
        fi
        if [[ -n "$shell_rc" ]] && ! grep -q "$install_dir" "$shell_rc" 2>/dev/null; then
            echo "export PATH=\"$install_dir:\$PATH\"" >> "$shell_rc"
            log_info "Added $install_dir to PATH in $shell_rc (restart shell or run: source $shell_rc)"
        fi
    fi

    # Create data directory with correct permissions
    local data_dir="$HOME/.xcourier"
    mkdir -p "$data_dir"/{identity,contacts,prekeys,replay,vault}
    chmod 700 "$data_dir"
    chmod 700 "$data_dir"/*
    log_ok "Created data directory: $data_dir (mode 0700)"

    return 0
}

main() {
    parse_args "$@"

    log_info "X Messenger Terminal Installer"
    log_info "Version: $(cat "$VERSION_FILE" 2>/dev/null || echo "unknown")"

    local platform
    platform=$(detect_platform)
    log_info "Platform: $platform"

    check_dependencies "$platform" || exit 1
    verify_signature || exit 1
    install_binary "$platform" || exit 1

    log_ok "Installation complete!"
    log_info "Run 'xc selftest' to verify, then 'xc init' to create your identity."
}

parse_args "$@"
main "$@"