#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Platform tests

load '../test_helper'

@test "amd64 CI runner passes all tests" {
    run xc_platform_amd64
    assert_success
}

@test "arm64 CI configured (GitHub ubuntu-24.04-arm or QEMU)" {
    run xc_platform_arm64
    assert_success
}

@test "Termux manual checklist exists" {
    run xc_platform_termux_checklist
    assert_success
}