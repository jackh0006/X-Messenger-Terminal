#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Tamper and attack tests

load '../test_helper'

@test "flip each byte of a sample .courier file: reading must always fail" {
    run xc_tamper_byteflip
    assert_success
}

@test "truncate at every length: must fail cleanly" {
    run xc_tamper_truncate
    assert_success
}

@test "re-sign with a different key: reading must report 'not from your friend'" {
    run xc_tamper_resign
    assert_failure
    assert_output --partial "not from your friend"
}

@test "replay the same message twice: second must be rejected" {
    run xc_tamper_replay
    assert_failure
    assert_output --partial "replay"
}

@test "expired message rejected; message addressed to someone else rejected" {
    run xc_tamper_expiry_wrong_recipient
    assert_failure
}