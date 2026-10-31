#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Reproducible build verification for X Messenger Terminal
# Usage: ./scripts/reproducible-check.sh <version>

set -euo pipefail

VER="${1:-}"
if [[ ! "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 <x.y.z>"
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${X_MESSENGER_OUT:-$REPO_ROOT/dist}"
WORKDIR="$(mktemp -d)"
ORIGINAL_OUT="$OUT"

echo "=== Reproducible build check for $VER ==="
echo "Work dir: $WORKDIR"

# Clone repo at the exact commit
cd "$WORKDIR"
git clone --depth 1 --branch "v$VER" "https://github.com/jackh0006/X-Messenger-Terminal.git" repo 2>/dev/null || git clone --depth 1 "https://github.com/jackh0006/X-Messenger-Terminal.git" repo
cd repo
git checkout "v$VER" 2>/dev/null || git checkout master

echo "Building in clean environment..."
# Build web bundle
npm ci
npm run build:web

# Build packages (if tools available)
if command -v dpkg-deb >/dev/null; then
  bash scripts/build-deb.sh amd64 "$WORKDIR/X-Messenger-$VER-Linux-amd64.deb" || echo "warn: amd64 deb skipped"
fi

# Build tarballs
bash scripts/build-tarball.sh amd64 "$WORKDIR/X-Messenger-$VER-Linux-amd64.tar.gz" || echo "warn: amd64 tarball skipped"

# Build Windows (if tools available)
bash scripts/build-windows.sh all 2>/dev/null || echo "warn: windows build skipped"

# Generate SHA256SUMS
cd "$WORKDIR"
sha256sum X-Messenger-"$VER"-* > "X-Messenger-$VER-SHA256SUMS.txt.repro"

# Compare with published
if [[ -f "$ORIGINAL_OUT/X-Messenger-$VER-SHA256SUMS.txt" ]]; then
  echo "=== Comparing with published ==="
  if diff -u "$ORIGINAL_OUT/X-Messenger-$VER-SHA256SUMS.txt" "$WORKDIR/X-Messenger-$VER-SHA256SUMS.txt.repro"; then
    echo "✓ REPRODUCIBLE: Hashes match published release"
  else
    echo "✗ NOT REPRODUCIBLE: Hashes differ from published release"
    exit 1
  fi
else
  echo "Published SUMS not found at $ORIGINAL_OUT/X-Messenger-$VER-SHA256SUMS.txt"
  echo "Generated reproducible SUMS at $WORKDIR/X-Messenger-$VER-SHA256SUMS.txt.repro"
fi

echo "=== Reproducible check complete ==="