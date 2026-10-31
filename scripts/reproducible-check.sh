#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# reproducible-check.sh — Verify reproducible build
# Usage: ./scripts/reproducible-check.sh <version>

set -euo pipefail

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: $0 <x.y.z>"
    exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORIGINAL_OUT="${X_MESSENGER_OUT:-$REPO_ROOT/dist}"
WORKDIR="$(mktemp -d)"

echo "=== Reproducible Build Check for $VERSION ==="
echo "Work dir: $WORKDIR"

# Clone repo at the exact commit/tag
cd "$WORKDIR"
git clone --depth 1 --branch "v$VERSION" "https://github.com/jackh0006/X-Messenger-Terminal.git" repo 2>/dev/null || \
    git clone --depth 1 "https://github.com/jackh0006/X-Messenger-Terminal.git" repo
cd repo
git checkout "v$VERSION" 2>/dev/null || git checkout master

echo "Building in clean environment..."
# For shell script, just verify the xc script exists and is identical
if [[ -f xc ]]; then
    ORIGINAL_XC="$ORIGINAL_OUT/x-messenger-$VERSION/xc"
    REBUILT_XC="$WORKDIR/repo/xc"
    
    if [[ -f "$ORIGINAL_XC" ]] && [[ -f "$REBUILT_XC" ]]; then
        echo "Comparing xc scripts..."
        if diff -u "$ORIGINAL_XC" "$REBUILT_XC"; then
            echo "✓ REPRODUCIBLE: xc script matches published release"
        else
            echo "✗ NOT REPRODUCIBLE: xc script differs from published release"
            exit 1
        fi
    else
        echo "WARNING: Could not find xc for comparison"
    fi
else
    echo "No xc script found in repo"
fi

# Compare tarballs if they exist
if [[ -f "$ORIGINAL_OUT/x-messenger-$VERSION.tar.gz" ]]; then
    echo "Comparing tarballs..."
    ORIGINAL_SHA=$(sha256sum "$ORIGINAL_OUT/x-messenger-$VERSION.tar.gz" | cut -d' ' -f1)
    
    # Recreate tarball
    cd "$WORKDIR/repo"
    tar -czf "$WORKDIR/x-messenger-$VERSION-rebuilt.tar.gz" \
        --transform="s|^|x-messenger-$VERSION/|" \
        xc LICENSE README.md SECURITY.md CHANGELOG.md docs/ scripts/ tests/ .github/
    
    REBUILT_SHA=$(sha256sum "$WORKDIR/x-messenger-$VERSION-rebuilt.tar.gz" | cut -d' ' -f1)
    
    if [[ "$ORIGINAL_SHA" == "$REBUILT_SHA" ]]; then
        echo "✓ REPRODUCIBLE: Tarball hashes match"
        echo "  SHA256: $ORIGINAL_SHA"
    else
        echo "✗ NOT REPRODUCIBLE: Tarball hashes differ"
        echo "  Original: $ORIGINAL_SHA"
        echo "  Rebuilt:  $REBUILT_SHA"
        exit 1
    fi
fi

echo ""
echo "=== Reproducible check complete ==="