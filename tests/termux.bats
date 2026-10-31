#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Termux real-device test (manual checklist committed)

load '../test_helper'

@test "Termux manual checklist exists and is committed" {
    run xc_platform_termux_checklist
    assert_success
}