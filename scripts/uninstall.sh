#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# uninstall.sh — Uninstall X Messenger Terminal (xc)
# Removes binary only by default. Keys/contacts kept unless --purge with typed confirmation.

set -euo pipefail

# Configuration
BINARY_NAME="xc"
DATA_DIR="${HOME}/.xcourier"
PURGE=false
DRY_RUN=false
FORCE=false

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
    --purge          Remove keys, contacts, replay cache, and all data (requires typed confirmation)
    --dry-run        Show what would be removed without doing it
    --force          Skip confirmation prompts (use with caution)
    --help           Show this help

By default, removes the xc binary only. Keys, contacts, and data are preserved.
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --purge) PURGE=true; shift ;;
            --dry-run) DRY_RUN=true; shift ;;
            --force) FORCE=true; shift ;;
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

remove_binary() {
    local platform="$1"
    local install_dir

    if [[ "$platform" == "termux" ]]; then
        install_dir="${PREFIX}/bin"
    else
        install_dir="${HOME}/.local/bin"
    fi

    local binary_path="${install_dir}/${BINARY_NAME}"

    if [[ -f "$binary_path" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would remove binary: $binary_path"
        else
            rm -f "$binary_path"
            log_ok "Removed binary: $binary_path"
        fi
    else
        log_info "Binary not found at $binary_path (already removed?)"
    fi

    # Remove desktop entry (Linux only)
    if [[ "$platform" == "linux" ]]; then
        local desktop_file="${HOME}/.local/share/applications/x-messenger.desktop"
        if [[ -f "$desktop_file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would remove desktop entry: $desktop_file"
            else
                rm -f "$desktop_file"
                log_ok "Removed desktop entry: $desktop_file"
            fi
        fi
    fi
}

remove_data() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove data directory: $DATA_DIR"
        return 0
    fi

    if [[ ! -d "$DATA_DIR" ]]; then
        log_info "Data directory not found: $DATA_DIR"
        return 0
    fi

    log_warn "About to PERMANENTLY DELETE all data in $DATA_DIR"
    log_warn "This includes:"
    log_warn "  - Identity keys (age + SSH)"
    log_warn "  - Contacts and verified fingerprints"
    log_warn "  - Prekeys (forward secrecy)"
    log_warn "  - Replay protection cache"
    log_warn "  - Vault (if enabled)"
    log_warn ""
    log_warn "On flash storage, deletion is BEST EFFORT — wear leveling may leave remnants."

    if [[ "$FORCE" != "true" ]]; then
        echo ""
        read -rp "Type 'YES, I understand this cannot be undone' to confirm: " confirm
        if [[ "$confirm" != "YES, I understand this cannot be undone" ]]; then
            log_err "Confirmation failed. Aborting."
            return 1
        fi
    fi

    rm -rf "$DATA_DIR"
    log_ok "Removed data directory: $DATA_DIR"
    log_warn "Note: On flash storage, deletion is best effort — wear leveling may leave remnants."
    return 0
}

main() {
    parse_args "$@"

    log_info "X Messenger Terminal Uninstaller"

    local platform
    platform=$(detect_platform)
    log_info "Platform: $platform"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY RUN MODE — no changes will be made"
    fi

    remove_binary "$platform"

    if [[ "$PURGE" == "true" ]]; then
        remove_data
    else
        log_info "Keys and data preserved in $DATA_DIR"
        log_info "Run with --purge to remove everything (requires typed confirmation)"
    fi

    log_ok "Uninstall complete!"
}

parse_args "$@"
main "$@"