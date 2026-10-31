#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Hygiene tests

load '../test_helper'

@test "no temp files remain after success, failure, and Ctrl+C" {
    run xc_hygiene_temp_files
    assert_success
}

@test "permissions of every created file/dir are correct" {
    run xc_hygiene_permissions
    assert_success
}

@test "no secrets appear in ps output or in the environment during run" {
    run xc_hygiene_secrets
    assert_success
}

@test "no network: full suite passes under unshare -rn; canary confirms blocked" {
    run xc_hygiene_network
    assert_success
}