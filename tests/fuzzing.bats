#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Fuzzing tests

load '../test_helper'

@test "fuzz input parsers (ID import, QR frame reassembly, header parsing) with AFL++/radamsa" {
    run xc_fuzzing
    assert_success
}