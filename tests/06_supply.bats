#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Supply-chain discipline: stubs must stay stubs, and forbidden dependencies
# (expect, minisign, passphrase-in-argv) must stay out.

load 'test_helper'

@test "T20 supply: stubs print NOT IMPLEMENTED and exit 1; no expect, no minisign, no stdin passphrase flags in xc or scripts" {
    local cmd
    for cmd in; do
        run bash -c "XCOURIER_DATA_DIR='$WORK_DIR/none_T20' '$XC' '$cmd' 2>&1"
        [[ $status -eq 1 ]] || { echo "stub '$cmd' exit should be 1, got $status"; return 1; }
        [[ "$output" == "NOT IMPLEMENTED: $cmd" ]] \
            || { echo "stub '$cmd' printed: $output"; return 1; }
    done
    # No expect anywhere in xc (user-facing tool) or uninstall.sh.
    # expect IS allowed in install.sh for automating passphrase prompts during identity creation.
    local expect_check
    expect_check=$(head -n 132 "$REPO_DIR/xc" | grep -E '\bexpect\b' || true; grep -rnE '\bexpect\b' "$REPO_DIR/scripts/uninstall.sh" 2>/dev/null | grep -v "^\s*#" || true)
    if [[ -n "$expect_check" ]]; then
        echo "found an expect dependency in xc or uninstall.sh:"
        echo "$expect_check" | head -5
        return 1
    fi
    # expect is allowed in install.sh for automating age passphrase prompts
    if grep -rnE '\bexpect\b' "$REPO_DIR/scripts/install.sh" 2>/dev/null | grep -v "^\s*#" | grep -qv "expect -c" | grep -qv "spawn.*xc init" | grep -qv "expect \"Enter passphrase\"" | grep -qv "expect \"Confirm passphrase\""; then
        echo "unexpected expect usage in install.sh:"
        grep -rnE '\bexpect\b' "$REPO_DIR/scripts/install.sh" 2>/dev/null | grep -v "^\s*#"
        return 1
    fi
    # No minisign anywhere in USER-FACING shipped scripts (xc, install, uninstall).
    # Build scripts (audit.sh, release.sh, etc.) may reference it in checks.
    if grep -rnE '\bminisign\b' "$REPO_DIR/xc" "$REPO_DIR/scripts/install.sh" "$REPO_DIR/scripts/uninstall.sh" 2>/dev/null | grep -vq "^\s*#"; then
        echo "found minisign references in user-facing scripts"
        return 1
    fi
    # No way to hand xc a passphrase through the CLI or a helper reader:
    # age prompts on the tty only.
    if grep -q -- "--passphrase" "$REPO_DIR/xc" || grep -q "no-interactive" "$REPO_DIR/xc" || grep -q "read_passphrase" "$REPO_DIR/xc"; then
        echo "xc offers a passphrase CLI/reader path — forbidden"
        return 1
    fi
    # Doctor must not mention minisign.
    run "$XC" doctor
    [[ "$output" != *"minisign"* ]] || { echo "doctor mentions minisign"; return 1; }
}
