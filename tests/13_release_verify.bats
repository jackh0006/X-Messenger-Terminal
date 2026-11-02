#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Test release.sh artifact generation and signature verification

load 'test_helper'

setup() {
    # Create a temp dir for this test
    TEST_TMP=$(mktemp -d "$WORK_DIR/release_test.XXXXXX")
    cd "$TEST_TMP"
    # Generate a temp Ed25519 signing key
    SIGNING_KEY="$TEST_TMP/test_signing_key"
    ssh-keygen -t ed25519 -N "" -f "$SIGNING_KEY" -C "test-release-$(date +%s)" >/dev/null 2>&1
    # Copy the repo files needed
    mkdir -p "$TEST_TMP/repo"
    cp -r "$REPO_DIR"/* "$TEST_TMP/repo/"
    cd "$TEST_TMP/repo"
}

teardown() {
    cd "$REPO_DIR"
    rm -rf "$TEST_TMP"
}

@test "RL01 release: creates artifacts and signature verifies" {
    run bash scripts/release.sh v0.1.0-test "$SIGNING_KEY"
    echo "STATUS: $status" >&2
    echo "OUTPUT: $output" >&2
    [[ "$status" -eq 0 ]]
    [[ -f "x-messenger-v0.1.0-test.tar.gz" ]]
    [[ -f "SHA256SUMS" ]]
    [[ -f "SHA256SUMS.sig" ]]
    [[ -f "SBOM.cdx.json" ]]

    # Create allowed_signers for verification (principal + namespaces option)
    local pubkey
    pubkey=$(ssh-keygen -y -f "$SIGNING_KEY" | awk '{print $2}')
    printf 'x-messenger-release namespaces="x-messenger-release" ssh-ed25519 %s\n' "$pubkey" > allowed_signers

    # Verify signature works
    run ssh-keygen -Y verify -f allowed_signers -I x-messenger-release -n x-messenger-release -s SHA256SUMS.sig < SHA256SUMS
    echo "VERIFY STATUS: $status" >&2
    echo "VERIFY OUTPUT: $output" >&2
    [[ "$status" -eq 0 ]]
}

@test "RL02 release: verify fails when one byte of tarball is changed" {
    run bash scripts/release.sh v0.1.0-test "$SIGNING_KEY"
    [[ "$status" -eq 0 ]]

    local pubkey
    pubkey=$(ssh-keygen -y -f "$SIGNING_KEY" | awk '{print $2}')
    printf 'x-messenger-release namespaces="x-messenger-release" ssh-ed25519 %s\n' "$pubkey" > allowed_signers

    # Corrupt the tarball by flipping one byte
    printf '\x00' | dd of=x-messenger-v0.1.0-test.tar.gz bs=1 seek=100 count=1 conv=notrunc 2>/dev/null

    # Re-generate SHA256SUMS (but NOT the signature)
    sha256sum x-messenger-v0.1.0-test.tar.gz > SHA256SUMS

    # Verification should fail
    run ssh-keygen -Y verify -f allowed_signers -I x-messenger-release -n x-messenger-release -s SHA256SUMS.sig < SHA256SUMS
    [[ "$status" -ne 0 ]]
}

@test "RL03 release: verify fails when SHA256SUMS is tampered" {
    run bash scripts/release.sh v0.1.0-test "$SIGNING_KEY"
    [[ "$status" -eq 0 ]]

    local pubkey
    pubkey=$(ssh-keygen -y -f "$SIGNING_KEY" | awk '{print $2}')
    printf 'x-messenger-release namespaces="x-messenger-release" ssh-ed25519 %s\n' "$pubkey" > allowed_signers

    # Tamper with SHA256SUMS (change the hash)
    sed -i 's/^[a-f0-9]\{64\}/0000000000000000000000000000000000000000000000000000000000000000/' SHA256SUMS

    # Verification should fail
    run ssh-keygen -Y verify -f allowed_signers -I x-messenger-release -n x-messenger-release -s SHA256SUMS.sig < SHA256SUMS
    [[ "$status" -ne 0 ]]
}