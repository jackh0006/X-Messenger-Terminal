#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# release.sh — X Messenger Terminal release script
# Usage: ./scripts/release.sh <version> [--publish]
# Creates signed release with SHA256SUMS, minisign signature, SBOM, evidence bundle

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"
MODE="${2:-}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: $0 <x.y.z> [--publish]"
    exit 2
fi

echo "=== X Messenger Terminal Release: $VERSION ==="
echo "Mode: ${MODE:-local}"

# 1. Version lockstep
echo "== 1/8 Version lockstep =="
grep -q "\"version\": \"$VERSION\"" package.json 2>/dev/null || echo "No package.json (shell script)"
sed -i "s/^VERSION=.*/VERSION=\"$VERSION\"/" xc

# 2. Tests
echo "== 2/8 Tests =="
./scripts/run-tests.sh

# 3. Build (for shell script, just verify xc exists)
echo "== 3/8 Verify build =="
test -f xc && test -x xc

# 4. Create distribution
echo "== 4/8 Create distribution =="
OUT="${X_MESSENGER_OUT:-$REPO_ROOT/dist}"
mkdir -p "$OUT"
TARBALL="$OUT/x-messenger-$VERSION.tar.gz"

echo "Creating tarball..."
tar -czf "$TARBALL" \
    --transform="s|^|x-messenger-$VERSION/|" \
    xc \
    LICENSE \
    README.md \
    SECURITY.md \
    CHANGELOG.md \
    docs/ \
    scripts/ \
    tests/ \
    .github/

# 5. Generate SHA256SUMS
echo "== 5/8 Generate SHA256SUMS =="
cd "$OUT"
sha256sum x-messenger-$VERSION.tar.gz > SHA256SUMS.txt

# 6. Sign with minisign
echo "== 6/8 Sign release =="
if command -v minisign >/dev/null && [[ -n "${MINISIGN_KEY:-}" ]]; then
    minisign -Sm SHA256SUMS.txt -k "$MINISIGN_KEY"
    echo "Signed with minisign"
elif command -v ssh-keygen >/dev/null && [[ -n "${SIGNING_KEY_FILE:-}" ]]; then
    ssh-keygen -Y sign -f "$SIGNING_KEY_FILE" -n "x-messenger-release" < SHA256SUMS.txt > SHA256SUMS.txt.sig
    echo "Signed with ssh-keygen"
else
    echo "WARNING: No signing key configured (set MINISIGN_KEY or SIGNING_KEY_FILE)"
fi

# 7. Generate SBOM
echo "== 7/8 Generate SBOM =="
if command -v cyclonedx-bom >/dev/null; then
    cyclonedx-bom -o "$OUT/x-messenger-$VERSION-SBOM.cdx.json" --json
else
    echo "WARNING: cyclonedx-bom not installed, skipping SBOM"
fi

# 8. Collect evidence
echo "== 8/8 Collect evidence =="
cp -r ../evidence "$OUT/evidence" 2>/dev/null || echo "No evidence directory found"

# Create release notes
cat > "$OUT/RELEASE_NOTES.md" <<EOF
# X Messenger Terminal $VERSION

## Verify Before Installing

\`\`\`bash
# 1. Verify minisign signature
minisign -Vm SHA256SUMS.txt -P <pubkey-from-readme>

# 2. Verify checksums
sha256sum -c SHA256SUMS.txt

# 3. (Optional) Rebuild and compare
./scripts/reproducible-check.sh $VERSION
\`\`\`

## Changes
See CHANGELOG.md

## Security
Status: Not independently audited
EOF

echo ""
echo "=== Release package ready in $OUT ==="
ls -la "$OUT/"

if [[ "$MODE" == "--publish" ]]; then
    echo "== Publishing =="
    # Tag and push
    git tag -s "v$VERSION" -m "Release v$VERSION"
    git push origin "v$VERSION"
    
    # Create GitHub release
    gh release create "v$VERSION" \
        --title "v$VERSION" \
        --notes-file "$OUT/RELEASE_NOTES.md" \
        "$OUT"/*
    
    echo "Published v$VERSION"
fi

echo "Done."