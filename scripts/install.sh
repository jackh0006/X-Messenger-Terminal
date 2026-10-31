#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# X Messenger Terminal — Linux installer
# Installs the portable tarball or .deb, creates desktop launcher + CLI symlinks.
# Usage: ./scripts/install.sh [--deb|--tarball] [--prefix DIR] [--dry-run]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${X_MESSENGER_DIST:-$REPO_ROOT/dist}"
PREFIX="${PREFIX:-/usr/local}"
DRY_RUN=false
MODE="auto"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --deb) MODE="deb"; shift ;;
    --tarball) MODE="tarball"; shift ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown option: $1"; exit 2 ;;
  esac
done

log() { echo "[$(date +%H:%M:%S)] $*"; }
run() { if $DRY_RUN; then echo "DRY: $*"; else eval "$*"; fi; }

# Detect architecture
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) DEB_ARCH="amd64"; TAR_ARCH="amd64" ;;
  aarch64|arm64) DEB_ARCH="arm64"; TAR_ARCH="arm64" ;;
  armv7l|armhf) DEB_ARCH="armhf"; TAR_ARCH="armhf" ;;
  *) echo "Unsupported arch: $ARCH"; exit 1 ;;
esac

log "Installing X Messenger Terminal v$(node -p "require('./package.json').version") for $ARCH"

# 1. Check dependencies
if ! command -v node >/dev/null; then echo "ERROR: node not found (need >=18)"; exit 1; fi
if ! command -v openssl >/dev/null; then echo "ERROR: openssl not found"; exit 1; fi
NODE_VER=$(node -p "process.version.slice(1).split('.')[0]")
if [[ $NODE_VER -lt 18 ]]; then echo "ERROR: Node >=18 required (found $NODE_VER)"; exit 1; fi

# 2. Find artifact
if [[ "$MODE" == "deb" || "$MODE" == "auto" ]]; then
  DEB_FILE=$(ls -1 "$DIST_DIR"/X-Messenger-*-Linux-"$DEB_ARCH".deb 2>/dev/null | head -1 || true)
fi
if [[ -z "${DEB_FILE:-}" && ("$MODE" == "tarball" || "$MODE" == "auto") ]]; then
  TAR_FILE=$(ls -1 "$DIST_DIR"/X-Messenger-*-Linux-"$TAR_ARCH".tar.gz 2>/dev/null | head -1 || true)
fi

if [[ -z "${DEB_FILE:-}" && -z "${TAR_FILE:-}" ]]; then
  echo "No artifact found in $DIST_DIR. Run 'npm run build:deb' or 'npm run build:tarball' first."
  exit 1
fi

# 3. Install
if [[ -n "${DEB_FILE:-}" && "$MODE" != "tarball" ]]; then
  log "Installing .deb: $DEB_FILE"
  run "sudo dpkg -i \"$DEB_FILE\" || sudo apt-get install -f -y"
else
  log "Installing tarball: $TAR_FILE"
  run "tar -xzf \"$TAR_FILE\" -C \"$PREFIX\" --strip-components=1"
fi

# 4. Verify CLI
if ! command -v x-messenger >/dev/null && ! command -v cipherlink >/dev/null; then
  log "Creating CLI symlinks in $PREFIX/bin"
  run "mkdir -p \"$PREFIX/bin\""
  run "ln -sf \"$PREFIX/lib/x-messenger/bin/cipherlink\" \"$PREFIX/bin/cipherlink\""
  run "ln -sf \"$PREFIX/lib/x-messenger/bin/cipherlink-gui\" \"$PREFIX/bin/x-messenger\""
fi

# 5. Desktop entry (already in .deb; for tarball ensure it exists)
DESKTOP_FILE="$PREFIX/share/applications/x-messenger.desktop"
if [[ ! -f "$DESKTOP_FILE" ]]; then
  log "Creating desktop entry"
  run "mkdir -p \"$(dirname "$DESKTOP_FILE")\""
  run "cat > \"$DESKTOP_FILE\" <<'EOF'
[Desktop Entry]
Name=X Messenger Terminal
Comment=Offline encrypted QR courier
Exec=x-messenger gui
Icon=x-messenger
Terminal=false
Type=Application
Categories=Network;Security;
StartupNotify=false
EOF"
fi

# 6. Permissions
run "find \"$PREFIX/lib/x-messenger\" -type f -name '*.pem' -o -name '*.key' -o -name '*.crt' 2>/dev/null | xargs -r chmod 600"
run "find \"$PREFIX/lib/x-messenger\" -type d -exec chmod 755 {} +"

log "Installation complete."
echo "Run 'x-messenger gui' to start the offline GUI (https://127.0.0.1:443)"
echo "Run 'cipherlink encrypt \"message\" --to \"contact\"' for CLI use"