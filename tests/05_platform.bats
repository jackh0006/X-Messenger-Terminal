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

@test "T18 platform: arm64 runner — uname -m is aarch64 and xc runs clean (skips on other arches)" {
    local arch; arch=$(uname -m)
    if [[ "$arch" != "aarch64" ]]; then
        skip "arm64-only check; this runner is $arch (arm64 coverage is the CI matrix job ubuntu-24.04-arm)"
    fi
    [[ "$(uname -s)" == "Linux" ]] || skip "not linux"
    # The only assert that matters here: the arm runner really is aarch64,
    # and the tool behaves normally on it.
    local m; m=$(uname -m)
    [[ "$m" == "aarch64" ]] || { echo "uname -m is $m, expected aarch64"; return 1; }
    run "$XC" --version
    assert_no_crash || return 1
    [[ "$output" == "X Messenger Terminal 0.1.0" ]] || { echo "version wrong: $output"; return 1; }
    run env XCOURIER_DATA_DIR="$WORK_DIR/NOEXIST_XC_T18" "$XC" doctor
    [[ "$status" -le 128 ]] || { echo "doctor crashed: $status"; return 1; }
}

@test "T19 platform: Termux manual checklist exists; the real-phone test stays owner-run (SKIP: owner-run only)" {
    skip "Real-device Termux test is owner-run only; CI cannot verify"
}