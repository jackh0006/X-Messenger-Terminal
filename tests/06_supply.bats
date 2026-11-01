#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Supply-chain discipline: stubs must stay stubs, and forbidden dependencies
# (expect, minisign, passphrase-in-argv) must stay out.

load 'test_helper'

@test "T20 supply: stubs print NOT IMPLEMENTED and exit 1; no expect, no minisign, no stdin passphrase flags in xc or scripts" {
    local cmd
    for cmd in wipe rotate prekeys qr-send qr-read; do
        run bash -c "XCOURIER_DATA_DIR='$WORK_DIR/none_T20' '$XC' '$cmd' 2>&1"
        [[ $status -eq 1 ]] || { echo "stub '$cmd' exit should be 1, got $status"; return 1; }
        [[ "$output" == "NOT IMPLEMENTED: $cmd" ]] \
            || { echo "stub '$cmd' printed: $output"; return 1; }
    done
    # No expect anywhere: user-facing shipped tool and shipped scripts (word-boundary).
    # Exclude the BIP39 wordlist in fingerprint_words function which contains "expect" as a word.
    local expect_check
    expect_check=$(head -n 132 "$REPO_DIR/xc" | grep -E '\bexpect\b' || true; grep -rnE '\bexpect\b' "$REPO_DIR/scripts/install.sh" "$REPO_DIR/scripts/uninstall.sh" 2>/dev/null | grep -v "^\s*#" || true)
    if [[ -n "$expect_check" ]]; then
        echo "found an expect dependency:"
        echo "$expect_check" | head -5
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
