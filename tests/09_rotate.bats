#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Stage 2 — xc rotate: fresh identity keys behind a typed confirmation.
#
# Rotation REPLACES the user's age + SSH keys with a new pair. The old
# keys are destroyed (unless --keep-old), so:
#   * the fingerprint changes — every contact must re-verify,
#   * couriers sealed to the OLD age key can never be opened again.
# Every passphrase path drives the pty driver like the rest of the suite.

load 'test_helper'

grab_fp() { printf '%s\n' "$1" | sed -n 's/^Fingerprint: //p' | head -1; }

send_msg() {
    local dir="$1" friend="$2" text="$3"
    STDIN_FILE="$WORK_DIR/msg.bin"
    printf '%s' "$text" >"$STDIN_FILE"
    pty_cmd "$dir" send "$friend"
}

courier_to_work() { cp "$SCRATCH/message.courier" "$1" && test -s "$1"; }

@test "R01 rotate: typed confirmation produces a NEW fingerprint and tells every contact to re-verify" {
    fresh_pair || return 1
    pty_cmd "$B_DIR" id && B_BEFORE="$TTY_OUTPUT"

    STDIN_FILE="$WORK_DIR/rotate.conf"
    printf 'ROTATE\n' >"$STDIN_FILE"
    pty_cmd "$B_DIR" rotate
    assert_status_zero || return 1
    assert_tty_contains "Rotated" || return 1
    assert_tty_contains "fingerprint CHANGED" || return 1
    assert_tty_contains "re-verify" || return 1
    assert_tty_contains "alice" || return 1

    pty_cmd "$B_DIR" id && B_AFTER="$TTY_OUTPUT"
    assert_status_zero || return 1
    local fp0 fp1
    fp0=$(grab_fp "$B_BEFORE")
    fp1=$(grab_fp "$B_AFTER")
    [[ -n "$fp0" && -n "$fp1" && "$fp0" != "$fp1" ]] || { echo "fingerprint did not change: $fp0 -> $fp1"; return 1; }
    # Contacts survive rotation (their keys are their business) and the new
    # identity is a real encrypted pair in the identity dir.
    [[ -f "$B_DIR/contacts/alice.json" ]] || { echo "contacts were lost in rotation"; return 1; }
    [[ -f "$B_DIR/identity/age.priv.enc" && -f "$B_DIR/identity/ssh.enc" ]] || { echo "new encrypted key files missing"; return 1; }
}

@test "R02 rotate: a wrong or empty confirmation changes nothing" {
    fresh_pair || return 1
    pty_cmd "$B_DIR" id && B_BEFORE="$TTY_OUTPUT"
    STDIN_FILE="$WORK_DIR/rotate.bad"
    printf 'yes\n' >"$STDIN_FILE"
    pty_cmd "$B_DIR" rotate
    assert_driver_alive || return 1
    assert_status_nonzero || return 1
    assert_tty_contains "not changed" || return 1
    # Nothing was overwritten: the new-keys staging dir must not linger.
    [[ ! -d "$B_DIR/.rotate-new" ]] || { echo "staging dir left behind after refusal"; return 1; }
    STDIN_FILE="$WORK_DIR/rotate.empty"
    : >"$STDIN_FILE"
    pty_cmd "$B_DIR" rotate
    assert_driver_alive || return 1
    assert_status_nonzero || return 1
    pty_cmd "$B_DIR" id && B_AFTER="$TTY_OUTPUT"
    assert_status_zero || return 1
    [[ "$(grab_fp "$B_BEFORE")" == "$(grab_fp "$B_AFTER")" ]] || { echo "refused rotation still changed the identity"; return 1; }
}

@test "R03 rotate: couriers sealed to the old key are honestly unopenable afterwards" {
    fresh_pair || return 1
    send_msg "$A_DIR" bob "sealed before the rotation"
    assert_status_zero || return 1
    courier_to_work "$WORK_DIR/r3.courier" || return 1

    STDIN_FILE="$WORK_DIR/rotate.conf"
    printf 'ROTATE\n' >"$STDIN_FILE"
    pty_cmd "$B_DIR" rotate
    assert_status_zero || return 1

    pty_cmd "$B_DIR" read "$WORK_DIR/r3.courier"
    assert_driver_alive || return 1
    assert_status_nonzero || return 1
    assert_tty_not_contains "sealed before the rotation" || return 1
    assert_tty_contains "cannot be opened" || return 1
}

@test "R04 rotate: after the friend re-adds the new identity, messaging with the new keys works" {
    fresh_pair || return 1
    STDIN_FILE="$WORK_DIR/rotate.conf"
    printf 'ROTATE\n' >"$STDIN_FILE"
    pty_cmd "$B_DIR" rotate
    assert_status_zero || return 1

    # Alice must re-add bob: his fingerprint changed completely.
    pty_cmd "$B_DIR" id && NEW_ID="$TTY_OUTPUT"
    rm -f "$A_DIR/contacts/bob.json"
    XCOURIER_DATA_DIR="$A_DIR" "$XC" add bob <<<"$NEW_ID"
    XCOURIER_DATA_DIR="$A_DIR" "$XC" verify bob <<<"y"

    send_msg "$A_DIR" bob "post-rotation round trip"
    assert_status_zero || return 1
    courier_to_work "$WORK_DIR/r4.courier" || return 1
    pty_cmd "$B_DIR" read "$WORK_DIR/r4.courier"
    assert_status_zero || return 1
    assert_tty_contains "post-rotation round trip" || return 1
    # The contact record really is the NEW identity, not the stale one.
    [[ "$(jq -r .fingerprint "$A_DIR/contacts/bob.json")" == "$(grab_fp "$NEW_ID")" ]] || { echo "re-added fingerprint is stale"; return 1; }
}

@test "R05 rotate: --keep-old preserves the old encrypted key files under identity.old/" {
    fresh_pair || return 1
    STDIN_FILE="$WORK_DIR/rotate.conf"
    printf 'ROTATE\n' >"$STDIN_FILE"
    pty_cmd "$B_DIR" rotate --keep-old
    assert_status_zero || return 1
    [[ -f "$B_DIR/identity.old/age.priv.enc" ]] || { echo "old encrypted age key not kept"; return 1; }
    [[ -f "$B_DIR/identity.old/ssh.enc" ]] || { echo "old encrypted ssh key not kept"; return 1; }
    [[ -f "$B_DIR/identity.old/age.pub" && -f "$B_DIR/identity.old/ssh.pub" ]] || { echo "old public key files not kept"; return 1; }
    # The live identity is the NEW one and id still works normally.
    pty_cmd "$B_DIR" id
    assert_status_zero || return 1
    assert_tty_contains "Fingerprint: SHA256:" || return 1
    # No staging leftover.
    [[ ! -d "$B_DIR/.rotate-new" ]] || { echo "staging dir left behind"; return 1; }
}
