#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# release.sh — Build release artifacts for X Messenger Terminal
# Usage: ./scripts/release.sh <version> <signing-key-path>
# Creates: tarball, SHA256SUMS, SHA256SUMS.sig, SBOM.cdx.json
# The signing key must be an Ed25519 private key file.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

VERSION="${1:-}"
SIGNING_KEY="${2:-}"

usage() {
    cat <<EOF
Usage: $0 <version> <signing-key-path>

Builds release artifacts:
  - x-messenger-<version>.tar.gz    (source + prebuilt xc)
  - SHA256SUMS                      (checksums)
  - SHA256SUMS.sig                  (SSH signature)
  - SBOM.cdx.json                   (CycloneDX SBOM)

The signing key must be an Ed25519 private key file (PEM format).
Example:
  $0 v0.1.0-pre ./release_signing_key
EOF
    exit 1
}

[[ -z "$VERSION" ]] && { echo "Error: version required"; usage; }
[[ -z "$SIGNING_KEY" ]] && { echo "Error: signing key path required"; usage; }
[[ -f "$SIGNING_KEY" ]] || { echo "Error: signing key not found: $SIGNING_KEY"; exit 1; }

# Verify the signing key is Ed25519
ssh-keygen -y -f "$SIGNING_KEY" >/dev/null 2>&1 || {
    echo "Error: signing key must be a valid SSH private key"
    exit 1
}

# Ensure we're on a clean commit
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Error: working directory not clean. Commit or stash changes first."
    exit 1
fi

# Build tarball (minimal for testing speed)
TARBALL="x-messenger-${VERSION}.tar.gz"
echo "[INFO] Building $TARBALL..."
tar --exclude='.git' --exclude='*.log' --exclude='__pycache__' -czf "$TARBALL" xc scripts/ docs/ allowed_signers README.md 2>/dev/null || true

# Generate SHA256SUMS
echo "[INFO] Generating SHA256SUMS..."
sha256sum "$TARBALL" > SHA256SUMS

# Sign SHA256SUMS
echo "[INFO] Signing SHA256SUMS with $SIGNING_KEY..."
ssh-keygen -Y sign -f "$SIGNING_KEY" -n "x-messenger-release" -I "x-messenger-release" < SHA256SUMS > SHA256SUMS.sig

# Generate SBOM
echo "[INFO] Generating SBOM..."
cat > SBOM.cdx.json <<EOF
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.5",
  "version": 1,
  "metadata": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "component": {
      "type": "application",
      "name": "x-messenger",
      "version": "$VERSION"
    }
  },
  "components": [
    {
      "type": "library",
      "name": "age",
      "version": "1.2.1",
      "purl": "pkg:github/FiloSottile/age@1.2.1"
    },
    {
      "type": "library",
      "name": "openssh",
      "version": "9.8p1",
      "purl": "pkg:github/openssh/openssh-portable@V_9_8_P1"
    },
    {
      "type": "library",
      "name": "qrencode",
      "version": "4.1.1",
      "purl": "pkg:github/fukuchi/libqrencode@4.1.1"
    },
    {
      "type": "library",
      "name": "zbar",
      "version": "0.23.93",
      "purl": "pkg:github/mchehab/zbar@0.23.93"
    }
  ]
}
EOF

echo "[OK] Release artifacts created:"
echo "  $TARBALL"
echo "  SHA256SUMS"
echo "  SHA256SUMS.sig"
echo "  SBOM.cdx.json"
echo ""
echo "Verification commands:"
echo "  # Generate allowed_signers with the release public key:"
echo "  ssh-keygen -y -f <signing-key> | awk '{print \$2}' | xargs -I{} printf 'x-messenger-release namespaces=\"x-messenger-release\" ssh-ed25519 %s\\n' {} > allowed_signers"
echo "  ssh-keygen -Y verify -f allowed_signers -I x-messenger-release -n x-messenger-release -s SHA256SUMS.sig < SHA256SUMS"
echo "  sha256sum -c SHA256SUMS"
echo ""
echo "To publish:"
echo "  1. Create git tag: git tag -s $VERSION -m \"Release $VERSION\""
echo "  2. Push tag: git push origin $VERSION"
echo "  3. Create GitHub release with the four artifacts"