#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Platform tests: linux/amd64 behaviour here, arm64 and Termux coverage.

load 'test_helper'

@test "T17 platform: amd64 Linux runs doctor and reports the tool's version" {
    [[ "$(uname -s)" == "Linux" ]] || skip "not linux"
    local machine; machine=$(uname -m)
    case "$machine" in
        x86_64|amd64) ;;  # this test targets amd64 natively
        *) skip "this is T17; device here is $machine" ;;
    esac
    run "$XC" --version
    assert_no_crash || return 1
    [[ "$output" == "X Messenger Terminal 0.1.0" ]] || { echo "version wrong: $output"; return 1; }
    run env XCOURIER_DATA_DIR="$WORK_DIR/NOEXIST_XC_T17" "$XC" doctor
    [[ "$status" -le 128 ]] || { echo "doctor crashed: $status"; return 1; }
}

@test "T18 platform: CI builds and batteries on arm64 runners are configured (SKIP: verified in CI)" {
    skip "Verified by CI workflow; not run locally"
}

@test "T19 platform: Termux manual checklist exists; the real-phone test stays owner-run (SKIP: owner-run only)" {
    skip "Real-device Termux test is owner-run only; CI cannot verify"
}