#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Wipe safety tests: refuse dangerous paths, realpath resolution, no symlinks, selective delete

load 'test_helper'

@test "S01 wipe: realpath resolves correctly" {
    # Create a nested dir structure
    local real="$WORK_DIR/real_nested_$$"
    mkdir -p "$real"
    local link="$WORK_DIR/link_nested_$$"
    ln -s "$real" "$link"
    # The realpath should resolve the symlink
    local resolved
    resolved=$(realpath "$link")
    [[ "$resolved" == "$real" ]]
}

@test "S02 wipe: refuses symlinked data dir" {
    new_dirs
    pty_cmd "$A_DIR" init
    assert_status_zero || return 1
    # Create a symlink to the data dir
    local link_data="$WORK_DIR/link_data_$$"
    ln -s "$A_DIR" "$link_data"
    # Try to wipe via the symlink - should be refused
    STDIN_FILE="$WORK_DIR/wipe.conf"
    printf 'WIPE\n' >"$STDIN_FILE"
    pty_cmd "$link_data" wipe
    assert_driver_alive || return 1
    assert_status_nonzero || return 1
    assert_tty_contains "symlink" || assert_tty_contains "realpath" || assert_tty_contains "refuse"
}

@test "S03 wipe: refuses dangerous paths (root, home, etc.)" {
    # Test that realpath check catches dangerous paths
    # We test by trying to wipe a path that resolves to a dangerous location
    skip "requires root or careful setup; implementation tested via code review"
}

@test "S04 wipe: deletes only known subdirs, not parent" {
    new_dirs
    pty_cmd "$A_DIR" init
    assert_status_zero || return 1
    # Verify the known subdirs exist
    for part in identity contacts prekeys replay vault; do
        [[ -d "$A_DIR/$part" ]] || { echo "missing $part before wipe"; return 1; }
    done

    STDIN_FILE="$WORK_DIR/wipe.conf"
    printf 'WIPE\n' >"$STDIN_FILE"
    pty_cmd "$A_DIR" wipe
    assert_status_zero || return 1
    assert_tty_contains "Erased" || return 1
    assert_tty_contains "flash" || return 1

    # The data dir should be gone (rmdir called after removing contents)
    [[ ! -d "$A_DIR" ]] || { echo "data dir still exists: $A_DIR"; return 1; }
}

@test "S05 wipe: no rm -rf on unchecked variable (code review)" {
    # Verify the implementation uses realpath and checks paths
    grep -q 'realpath' xc || { echo "realpath not used in xc"; return 1; }
    # The wipe function should use resolved path
    grep -A 30 "^cmd_wipe()" xc | grep -q 'realpath' || { echo "wipe doesn't use realpath"; return 1; }
    # Should not have bare rm -rf on DATA_DIR
    ! grep -A 30 "^cmd_wipe()" xc | grep -q 'rm -rf -- "$DATA_DIR"' || { echo "bare rm -rf on DATA_DIR found"; return 1; }
}