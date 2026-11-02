#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Stage 2 — xc wipe: typed confirmation, everything gone, honest flash note.
#
# wipe handles no passphrase material, but its confirmation prompt needs a
# terminal, so every flow drives the pty driver like the rest of the suite.

load 'test_helper'

@test "W01 wipe: typed confirmation erases the whole data dir" {
    new_dirs
    pty_cmd "$A_DIR" init
    assert_status_zero || return 1
    # There IS something to erase: identity + contacts + replay + vault dirs.
    for part in identity contacts replay vault prekeys; do
        [[ -d "$A_DIR/$part" ]] || { echo "missing $part before wipe"; return 1; }
    done
    [[ -f "$A_DIR/identity/age.pub" ]] || { echo "identity missing before wipe"; return 1; }

    STDIN_FILE="$WORK_DIR/wipe.conf"
    printf 'WIPE\n' >"$STDIN_FILE"
    pty_cmd "$A_DIR" wipe
    assert_status_zero || return 1
    assert_tty_contains "Erased" || return 1
    assert_tty_contains "flash" || return 1
    # Everything under the data dir is gone.
    [[ -z "$(find "$A_DIR" -mindepth 1 2>/dev/null)" ]] || { echo "leftovers after wipe: $(find "$A_DIR" -mindepth 1 | head -5)"; return 1; }
}

@test "W02 wipe: wrong or empty confirmation changes nothing" {
    new_dirs
    pty_cmd "$A_DIR" init
    assert_status_zero || return 1
    [[ -f "$A_DIR/identity/age.pub" ]] || { echo "no identity to protect"; return 1; }

    # Wrong word: refuses in plain words, deletes nothing.
    STDIN_FILE="$WORK_DIR/wipe.bad"
    printf 'yes\n' >"$STDIN_FILE"
    pty_cmd "$A_DIR" wipe
    assert_driver_alive || return 1
    assert_status_nonzero || return 1
    assert_tty_contains "not deleted" || return 1
    [[ -f "$A_DIR/identity/age.pub" ]] || { echo "wrong confirmation still erased the identity"; return 1; }

    # Empty answer (Ctrl-D): same refusal, nothing deleted.
    STDIN_FILE="$WORK_DIR/wipe.empty"
    : >"$STDIN_FILE"
    pty_cmd "$A_DIR" wipe
    assert_driver_alive || return 1
    assert_status_nonzero || return 1
    [[ -f "$A_DIR/identity/age.pub" ]] || { echo "empty confirmation still erased the identity"; return 1; }

    # The identity still works after two refused wipes.
    pty_cmd "$A_DIR" id
    assert_status_zero || return 1
    assert_tty_contains "Fingerprint: SHA256:" || return 1
}

@test "W03 wipe: no data dir backs out with plain words, and init can start over afterwards" {
    D_DIR="$WORK_DIR/wipe_nowhere.$$"
    rm -rf "$D_DIR"
    STDIN_FILE="$WORK_DIR/wipe.n"
    printf 'WIPE\n' >"$STDIN_FILE"
    pty_cmd "$D_DIR" wipe
    assert_driver_alive || return 1
    assert_status_nonzero || return 1
    assert_tty_contains "does not exist or cannot be resolved" || return 1

    # Full recovery path: fresh init on the same machine works normally.
    new_dirs
    pty_cmd "$A_DIR" init
    assert_status_zero || return 1
    pty_cmd "$A_DIR" id
    assert_status_zero || return 1
    assert_tty_contains "Fingerprint: SHA256:" || return 1
}
