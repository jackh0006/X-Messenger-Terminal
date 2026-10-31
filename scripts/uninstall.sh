#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# X Messenger Terminal — Linux uninstaller
# Removes .deb package, portable install, desktop launcher, CLI symlinks, and user data (with confirmation).
# Usage: ./scripts/uninstall.sh [--purge] [--dry-run]

set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
PURGE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge) PURGE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown option: $1"; exit 2 ;;
  esac
done

log() { echo "[$(date +%H:%M:%S)] $*"; }
run() { if $DRY_RUN; then echo "DRY: $*"; else eval "$*"; fi; }

# 1. Remove .deb package if installed
if dpkg -l | grep -q '^ii  x-messenger '; then
  log "Removing .deb package"
  run "sudo dpkg -r x-messenger"
  run "sudo dpkg -P x-messenger 2>/dev/null || true"
fi

# 2. Remove portable install files
PORTABLE_DIRS=(
  "$PREFIX/lib/x-messenger"
  "$PREFIX/bin/cipherlink"
  "$PREFIX/bin/x-messenger"
  "$PREFIX/bin/cipherlink-gui"
  "$PREFIX/share/applications/x-messenger.desktop"
  "$PREFIX/share/icons/hicolor/*/apps/x-messenger.png"
  "$PREFIX/share/icons/hicolor/*/apps/x-messenger.svg"
  "$PREFIX/share/doc/x-messenger"
)

for p in "${PORTABLE_DIRS[@]}"; do
  if compgen -G "$p" > /dev/null; then
    log "Removing $p"
    run "sudo rm -rf $p"
  fi
done

# 3. Remove user data (requires explicit confirmation unless --purge)
if $PURGE; then
  CONFIRM="YES"
else
  echo ""
  echo "=========================================="
  echo "  REMOVE USER DATA?"
  echo "=========================================="
  echo "This will DELETE ALL local data:"
  echo "  - Vault history (locked messages)"
  echo "  - Local contacts (profiles)"
  echo "  - Settings & preferences"
  echo "  - Device identity (signing key)"
  echo "  - Replay protection cache"
  echo "  - Session messages"
  echo ""
  echo "Type exactly:  YES, I understand this cannot be undone"
  read -r CONFIRM
fi

if [[ "$CONFIRM" == "YES, I understand this cannot be undone" ]]; then
  log "Wiping user data..."
  for dir in \
    "$HOME/.local/share/x-messenger" \
    "$HOME/.config/x-messenger" \
    "$HOME/.cache/x-messenger" \
    "$HOME/.xcourier" 2>/dev/null; do
    if [[ -d "$dir" ]]; then
      log "Removing $dir"
      run "rm -rf \"$dir\""
    fi
  done
  # Also remove from XDG_DATA_HOME if set
  if [[ -n "${XDG_DATA_HOME:-}" && -d "$XDG_DATA_HOME/x-messenger" ]]; then
    run "rm -rf \"$XDG_DATA_HOME/x-messenger\""
  fi
  if [[ -n "${XDG_CONFIG_HOME:-}" && -d "$XDG_CONFIG_HOME/x-messenger" ]]; then
    run "rm -rf \"$XDG_CONFIG_HOME/x-messenger\""
  fi
  log "User data wiped."
else
  log "User data preserved (use --purge to remove)."
fi

log "Uninstall complete."