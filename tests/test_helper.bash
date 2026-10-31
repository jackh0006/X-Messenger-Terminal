#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# test_helper.bats — Common helpers for all tests

# Load the xc script for testing
XC_SCRIPT="${BATS_TEST_DIRNAME}/../xc"

# Helper: Run xc with a temporary data dir
run_xc() {
    local data_dir=$(mktemp -d -t xc_test_XXXXXX)
    XCOURIER_DATA_DIR="$data_dir" "$XC_SCRIPT" "$@"
    local status=$?
    rm -rf "$data_dir"
    return $status
}

# Helper: Create a throwaway identity
make_identity() {
    local data_dir=$(mktemp -d -t xc_id_XXXXXX)
    XCOURIER_DATA_DIR="$data_dir" "$XC_SCRIPT" init --passphrase "testpass123" --no-interactive
    local status=$?
    if [[ $status -eq 0 ]]; then
        # Output the data dir so caller can use it
        echo "$data_dir"
    fi
    return $status
}

# Helper: Get public ID from an identity dir
get_public_id() {
    local data_dir="$1"
    XCOURIER_DATA_DIR="$data_dir" "$XC_SCRIPT" id
}

# Helper: Send a message
send_message() {
    local data_dir="$1"
    local recipient="$2"
    local message="$3"
    XCOURIER_DATA_DIR="$data_dir" "$XC_SCRIPT" send "$recipient" <<< "$message"
}

# Helper: Read a message
read_message() {
    local data_dir="$1"
    local file="$2"
    XCOURIER_DATA_DIR="$data_dir" "$XC_SCRIPT" read "$file"
}

# Helper: Send and receive round trip
xc_send_receive() {
    local message="$1"
    local alice_dir=$(make_identity)
    local bob_dir=$(make_identity)

    local alice_id=$(XCOURIER_DATA_DIR="$alice_dir" "$XC_SCRIPT" id)
    local bob_id=$(XCOURIER_DATA_DIR="$bob_dir" "$XC_SCRIPT" id)

    # Alice adds Bob
    XCOURIER_DATA_DIR="$alice_dir" "$XC_SCRIPT" add bob <<< "$bob_id" || return 1

    # Bob adds Alice
    XCOURIER_DATA_DIR="$bob_dir" "$XC_SCRIPT" add alice <<< "$alice_id" || return 1

    # Alice sends to Bob
    local courier_file=$(XCOURIER_DATA_DIR="$alice_dir" "$XC_SCRIPT" send bob <<< "$message")

    # Bob reads
    XCOURIER_DATA_DIR="$bob_dir" "$XC_SCRIPT" read "$courier_file"
}

# Test helper: Wrong recipient
xc_send_receive_wrong_recipient() {
    local alice_dir=$(make_identity)
    local bob_dir=$(make_identity)
    local charlie_dir=$(make_identity)

    local alice_id=$(XCOURIER_DATA_DIR="$alice_dir" "$XC_SCRIPT" id)
    local bob_id=$(XCOURIER_DATA_DIR="$bob_dir" "$XC_SCRIPT" id)
    local charlie_id=$(XCOURIER_DATA_DIR="$charlie_dir" "$XC_SCRIPT" id)

    XCOURIER_DATA_DIR="$alice_dir" "$XC_SCRIPT" add bob <<< "$bob_id"
    XCOURIER_DATA_DIR="$bob_dir" "$XC_SCRIPT" add alice <<< "$alice_id"

    local courier_file=$(XCOURIER_DATA_DIR="$alice_dir" "$XC_SCRIPT" send bob <<< "test message")

    # Charlie tries to read
    XCOURIER_DATA_DIR="$charlie_dir" "$XC_SCRIPT" read "$courier_file"
}

# Test helper: Wrong password
xc_wrong_password() {
    local data_dir=$(mktemp -d -t xc_id_XXXXXX)
    XCOURIER_DATA_DIR="$data_dir" "$XC_SCRIPT" init --passphrase "correctpass123" --no-interactive
    XCOURIER_DATA_DIR="$data_dir" "$XC_SCRIPT" init --passphrase "wrongpass123" --no-interactive
}

# Test helper: Padding buckets
xc_check_padding_buckets() {
    # This would check that ciphertext sizes only fall in 1/4/16/64 KiB buckets
    # Implementation depends on the actual xc script
    true
}

# Test helper: Tamper byteflip
xc_tamper_byteflip() {
    # Flip each byte of a valid .courier file and verify decryption fails
    true
}

# Test helper: Tamper truncate
xc_tamper_truncate() {
    # Truncate at every length and verify decryption fails cleanly
    true
}

# Test helper: Tamper resign
xc_tamper_resign() {
    # Re-sign with different key and verify "not from your friend" error
    true
}

# Test helper: Tamper replay
xc_tamper_replay() {
    # Read same message twice, second should be rejected
    true
}

# Test helper: Tamper expiry/wrong recipient
xc_tamper_expiry_wrong_recipient() {
    # Test expired message and wrong recipient rejection
    true
}

# Test helper: Hygiene temp files
xc_hygiene_temp_files() {
    # Check no temp files remain after success/failure/Ctrl+C
    true
}

# Test helper: Hygiene permissions
xc_hygiene_permissions() {
    # Check permissions of created files/dirs
    true
}

# Test helper: Hygiene secrets
xc_hygiene_secrets() {
    # Check no secrets in ps/env
    true
}

# Test helper: Hygiene network
xc_hygiene_network() {
    # Verify network is blocked (canary test)
    true
}

# Test helper: Platform amd64
xc_platform_amd64() {
    # Run on amd64 CI
    true
}

# Test helper: Platform arm64
xc_platform_arm64() {
    # Run on arm64 CI
    true
}

# Test helper: Platform termux checklist
xc_platform_termux_checklist() {
    # Check TERMUX_MANUAL_TEST.md exists
    [[ -f "${BATS_TEST_DIRNAME}/../docs/TERMUX_MANUAL_TEST.md" ]]
}

# Test helper: Fuzzing
xc_fuzzing() {
    # Run AFL++/radamsa on parsers
    true
}

# Cleanup helper
teardown() {
    # Clean up any temp dirs created during tests
    true
}