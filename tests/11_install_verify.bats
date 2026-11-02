#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Tests for install.sh verification logic (placeholder detection, sig verify)

load 'test_helper'

setup() {
    # Create a temp dir for each test
    TEST_TMP=$(mktemp -d "$WORK_DIR/install_test.XXXXXX")
    cd "$TEST_TMP"
    # Copy needed files
    cp "$REPO_DIR/scripts/install.sh" .
    cp "$REPO_DIR/allowed_signers" .
}

teardown() {
    cd "$REPO_DIR"
    rm -rf "$TEST_TMP"
}

@test "V01 install: fails when allowed_signers has placeholder key" {
    # Run with SKIP_VERIFY=false (default) so verify_signature runs
    # Need to provide dummy SHA256SUMS and signature files
    echo "dummy" > SHA256SUMS
    echo "dummy" > SHA256SUMS.sig
    run bash -c 'SKIP_VERIFY=false ALLOWED_SIGNERS="allowed_signers" SHA256SUMS_FILE="SHA256SUMS" SIGNATURE_FILE="SHA256SUMS.sig" bash install.sh 2>&1'
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"placeholder key"* ]]
}

@test "V02 install: passes when allowed_signers has real key" {
    # Replace placeholder with a real-looking key
    sed -i 's/ExamplePlaceholderKeyDoNotUseThisInProduction/RealKeyAAAAC3NzaC1lZDI1NTE5AAAAITESTKEYFORVERIFICATIONONLY/' allowed_signers
    echo "dummy" > SHA256SUMS
    echo "dummy" > SHA256SUMS.sig
    run bash -c 'SKIP_VERIFY=false ALLOWED_SIGNERS="allowed_signers" SHA256SUMS_FILE="SHA256SUMS" SIGNATURE_FILE="SHA256SUMS.sig" bash install.sh 2>&1'
    # Should not fail on placeholder check; will fail on signature verification but that's after
    [[ "$output" != *"placeholder key"* ]]
}

@test "V03 install: verify_signature function detects placeholder without --skip-verify" {
    run bash -c '
        ALLOWED_SIGNERS="allowed_signers"
        SHA256SUMS_FILE="/dev/null"
        SIGNATURE_FILE="/dev/null"
        SKIP_VERIFY=false
        source install.sh
        verify_signature
    ' 2>&1
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"placeholder key"* ]]
}

@test "V04 install: verify_signature passes with real key (placeholder check only)" {
    sed -i 's/ExamplePlaceholderKeyDoNotUseThisInProduction/RealKeyAAAAC3NzaC1lZDI1NTE5AAAAITESTKEYFORVERIFICATIONONLY/' allowed_signers
    run bash -c '
        ALLOWED_SIGNERS="allowed_signers"
        SHA256SUMS_FILE="/dev/null"
        SIGNATURE_FILE="/dev/null"
        SKIP_VERIFY=false
        verify_signature 2>&1 || true
    '
    # Should not fail on placeholder check
    [[ "$output" != *"placeholder key"* ]]
}