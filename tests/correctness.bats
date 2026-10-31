#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Correctness tests

load '../test_helper'

@test "round trip: send then read returns identical text for various sizes" {
    for size in 0 1 1024 10240 61440; do
        run xc_send_receive "test message size $size"
        assert_success
        assert_output --partial "test message size $size"
    done
}

@test "round trip: unicode and binary-looking input" {
    run xc_send_receive $'Héllo — offline ✓ QR قمر 🌙 "XM1" test!'
    assert_success
    assert_output --partial $'Héllo — offline ✓ QR قمر 🌙 "XM1" test!'
}

@test "wrong recipient cannot decrypt" {
    run xc_send_receive_wrong_recipient
    assert_failure
    assert_output --partial "decrypt"
}

@test "wrong password cannot unlock identity" {
    run xc_wrong_password
    assert_failure
    assert_output --partial "incorrect"
}

@test "padding: ciphertext sizes fall only in defined buckets" {
    run xc_check_padding_buckets
    assert_success
}