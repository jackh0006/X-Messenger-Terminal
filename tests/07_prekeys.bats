#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Stage 2 — Offline forward secrecy with per-friend one-time prekeys.
#
# Roles in these tests:
#   maker/receiver = bob   (holds the PRIVATE one-time halves)
#   importer/sender = alice (holds bob's signed PUBLIC bundle, consumes one
#                           key per send, refuses to reuse)
# Every passphrase path is driven through the pty driver (XC_TEST_PASS),
# never as argv, never in a file.

load 'test_helper'

# fresh_pair + bob makes a bundle for alice + alice imports it.
prekeys_pair() {
    local count="${1:-3}"
    fresh_pair || return 1
    pty_cmd "$B_DIR" prekeys make alice --count "$count"
    assert_status_zero || return 1
    pty_cmd "$A_DIR" prekeys import bob "$B_DIR/prekeys/alice/bundle.pub"
    assert_status_zero || return 1
}

count_agekeys() { find "$1/prekeys/$2" -maxdepth 1 -name '*.agekey' 2>/dev/null | wc -l | tr -d ' '; }

send_msg() {
    local dir="$1" friend="$2" text="$3"
    shift 3
    STDIN_FILE="$WORK_DIR/msg.bin"
    printf '%s' "$text" >"$STDIN_FILE"
    pty_cmd "$dir" send "$friend" "$@"
}

courier_to_work() { cp "$SCRATCH/message.courier" "$1" && test -s "$1"; }

@test "K01 prekeys: bundle is signed by maker, import verifies, send/read round trip burns exactly one private half" {
    prekeys_pair 3

    # Bob holds three private halves plus a signed public bundle.
    [[ -f "$B_DIR/prekeys/alice/bundle.pub" ]] || { echo "no bundle on maker side"; return 1; }
    [[ $(count_agekeys "$B_DIR" alice) -eq 3 ]] || { echo "expected 3 private halves"; return 1; }

    # Alice holds the imported public bundle and NO private halves.
    [[ -f "$A_DIR/prekeys/bob/bundle.pub" ]] || { echo "no bundle on sender side"; return 1; }
    [[ $(count_agekeys "$A_DIR" bob) -eq 0 ]] || { echo "private halves must never travel to the sender"; return 1; }
    [[ "$(jq -r '.keys | length' "$A_DIR/prekeys/bob/bundle.pub")" == "3" ]] || { echo "imported bundle doesn't decode as 3 keys"; return 1; }

    send_msg "$A_DIR" bob "prekey round trip brown fox 001"
    assert_status_zero || return 1
    courier_to_work "$WORK_DIR/k01.courier" || return 1

    pty_cmd "$B_DIR" read "$WORK_DIR/k01.courier"
    assert_status_zero || return 1
    assert_tty_contains "prekey round trip brown fox 001" || return 1
    assert_tty_contains "Destroyed one-time key 0001" || return 1

    # Exactly the used key's private half is gone; the rest remain.
    [[ ! -f "$B_DIR/prekeys/alice/0001.agekey" ]] || { echo "0001 was not burned after a fully verified read"; return 1; }
    [[ -f "$B_DIR/prekeys/alice/0002.agekey" ]] || { echo "0002 must survive"; return 1; }
    [[ -f "$B_DIR/prekeys/alice/0003.agekey" ]] || { echo "0003 must survive"; return 1; }

    # Sender's bookkeeping marks 0001 used, nothing else.
    [[ "$(cat "$A_DIR/prekeys/bob/used.json")" == '["0001"]' ]] || { echo "used.json wrong: $(cat "$A_DIR/prekeys/bob/used.json")"; return 1; }
}

@test "K02 prekeys: every send consumes the next unused key; a courier re-read is refused after the key burned" {
    prekeys_pair 2

    send_msg "$A_DIR" bob "first one-time message 0xA"
    assert_status_zero || return 1
    courier_to_work "$WORK_DIR/k02a.courier" || return 1
    [[ "$(cat "$A_DIR/prekeys/bob/used.json")" == '["0001"]' ]] || { echo "after first send used.json=$(cat "$A_DIR/prekeys/bob/used.json")"; return 1; }

    send_msg "$A_DIR" bob "second one-time message 0xB"
    assert_status_zero || return 1
    [[ "$(cat "$A_DIR/prekeys/bob/used.json")" == '["0001","0002"]' ]] || { echo "two sends must consume two DISTINCT keys"; return 1; }

    pty_cmd "$B_DIR" read "$WORK_DIR/k02a.courier"
    assert_status_zero || return 1
    assert_tty_contains "first one-time message 0xA" || return 1

    # Same courier again: the private half is gone and the replay is refused.
    pty_cmd "$B_DIR" read "$WORK_DIR/k02a.courier"
    assert_driver_alive || return 1
    assert_status_nonzero || return 1
    assert_tty_not_contains "first one-time message 0xA" || return 1
}

@test "K03 prekeys: exhausted bundle refuses to send in plain words; --no-forward-secrecy sends with an honest warning" {
    prekeys_pair 1

    send_msg "$A_DIR" bob "the only key gets used here 0x1"
    assert_status_zero || return 1

    # No unused keys and no flag: plain refusal, no courier, no state change.
    send_msg "$A_DIR" bob "refusal candidate 0x2"
    assert_driver_alive || return 1
    assert_status_nonzero || return 1
    assert_tty_contains "No one-time keys left" || return 1
    [[ ! -f "$SCRATCH/message.courier" ]] || { echo "a refused send must not produce a courier"; return 1; }
    # exactly one key was consumed by the first (successful) send, and the
    # refused send changed nothing: still only 0001 in the used list.
    [[ "$(cat "$A_DIR/prekeys/bob/used.json")" == '["0001"]' ]] || { echo "refused send changed key state: $(cat "$A_DIR/prekeys/bob/used.json")"; return 1; }

    # Explicit fallback: sends, says what it did, touches no key state.
    send_msg "$A_DIR" bob "fallback without forward secrecy 0x3" --no-forward-secrecy
    assert_status_zero || return 1
    assert_tty_contains "WITHOUT forward secrecy" || return 1
    [[ "$(cat "$A_DIR/prekeys/bob/used.json")" == '["0001"]' ]] || { echo "fallback send must not mark keys: $(cat "$A_DIR/prekeys/bob/used.json")"; return 1; }
    courier_to_work "$WORK_DIR/k03.courier" || return 1
    pty_cmd "$B_DIR" read "$WORK_DIR/k03.courier"
    assert_status_zero || return 1
    assert_tty_contains "fallback without forward secrecy 0x3" || return 1
}

@test "K04 prekeys: import refuses a bundle made for another identity, and refuses duplicates" {
    # Order matters: the wrong-identity attempt happens BEFORE any import,
    # so it hits the for_fp gate, not the duplicate gate.
    fresh_pair || return 1
    pty_cmd "$B_DIR" prekeys make alice --count 3
    assert_status_zero || return 1
    # bob makes a bundle FOR SOMEONE ELSE (C_DIR is a third identity,
    # 'charlie', whose fingerprint bob gets explicitly).
    pty_cmd "$C_DIR" init
    assert_status_zero || return 1
    pty_cmd "$C_DIR" id && C_ID="$TTY_OUTPUT"
    C_FP=$(printf '%s\n' "$C_ID" | sed -n 's/^Fingerprint: //p' | head -1)
    [[ "$C_FP" == SHA256:* ]] || { echo "could not read charlie's fingerprint from id output"; return 1; }
    pty_cmd "$B_DIR" prekeys make charlie --count 2 --for-fp "$C_FP"
    assert_status_zero || return 1

    # Alice tries to import charlie's bundle as 'bob': signature verifies
    # (bob really made it) but it was not made for ALICE -> refused, and
    # nothing is written.
    pty_cmd "$A_DIR" prekeys import bob "$B_DIR/prekeys/charlie/bundle.pub"
    assert_driver_alive || return 1
    assert_status_nonzero || return 1
    assert_tty_contains "was not made for this identity" || return 1
    [[ ! -e "$A_DIR/prekeys/bob" ]] || { echo "refused import still wrote prekeys/bob"; return 1; }

    # Now the genuine import works...
    pty_cmd "$A_DIR" prekeys import bob "$B_DIR/prekeys/alice/bundle.pub"
    assert_status_zero || return 1
    # ...and a duplicate of it is refused, keeping the first intact.
    pty_cmd "$A_DIR" prekeys import bob "$B_DIR/prekeys/alice/bundle.pub"
    assert_driver_alive || return 1
    assert_status_nonzero || return 1
    assert_tty_contains "already imported" || return 1
    [[ "$(jq -r '.keys | length' "$A_DIR/prekeys/bob/bundle.pub")" == "3" ]] || { echo "genuine import was damaged"; return 1; }
}

@test "K05 prekeys: a tampered public bundle is refused at import, no sender state is written" {
    fresh_pair || return 1
    pty_cmd "$B_DIR" prekeys make alice --count 2
    assert_status_zero || return 1

    # Tamper: swap a byte inside one public key in the bundle.
    sed 's/age1[0-9a-z]\{20\}/age1XXXXXXXXXXXXXXXXXXXX/' \
        "$B_DIR/prekeys/alice/bundle.pub" >"$WORK_DIR/bad.bundle.pub"
    ! cmp -s "$WORK_DIR/bad.bundle.pub" "$B_DIR/prekeys/alice/bundle.pub" || { echo "tamper did not change the bundle"; return 1; }

    pty_cmd "$A_DIR" prekeys import bob "$WORK_DIR/bad.bundle.pub"
    assert_driver_alive || return 1
    assert_status_nonzero || return 1
    assert_tty_contains "signature" || return 1
    assert_tty_not_contains "Imported" || return 1
    # No sender state whatsoever may exist after a refused import.
    [[ ! -e "$A_DIR/prekeys/bob" ]] || { echo "refused import still wrote prekeys/bob"; return 1; }
}

@test "K06 prekeys: a garbage message addressed to a prekey must NOT burn it" {
    prekeys_pair 2

    # Alice knows bob's first public key from the bundle; seals garbage to it.
    local pk_pub
    pk_pub=$(jq -r '.keys[0].pub' "$A_DIR/prekeys/bob/bundle.pub")
    [[ "$pk_pub" == age1* ]] || { echo "bad pub in bundle: $pk_pub"; return 1; }
    mkdir -p "$SCRATCH" 2>/dev/null
    printf 'this is not a signed bundle, just garbage\n' |
        age -e -r "$pk_pub" >"$SCRATCH/evil.courier" 2>/dev/null
    test -s "$SCRATCH/evil.courier" || { echo "crafting garbage failed"; return 1; }
    cp "$SCRATCH/evil.courier" "$WORK_DIR/k06_evil.courier"

    pty_cmd "$B_DIR" read "$WORK_DIR/k06_evil.courier"
    assert_driver_alive || return 1
    assert_status_nonzero || return 1
    assert_tty_not_contains "this is not a signed bundle" || return 1

    # NO private half may have been burned by the garbage message.
    [[ -f "$B_DIR/prekeys/alice/0001.agekey" ]] || { echo "garbage burned 0001!"; return 1; }
    [[ -f "$B_DIR/prekeys/alice/0002.agekey" ]] || { echo "garbage burned 0002!"; return 1; }

    # The same prekey still works for a genuine message afterwards.
    send_msg "$A_DIR" bob "genuine message after garbage 0x4"
    assert_status_zero || return 1
    courier_to_work "$WORK_DIR/k06_ok.courier" || return 1
    pty_cmd "$B_DIR" read "$WORK_DIR/k06_ok.courier"
    assert_status_zero || return 1
    assert_tty_contains "genuine message after garbage 0x4" || return 1
    [[ ! -f "$B_DIR/prekeys/alice/0001.agekey" ]] || { echo "genuine read did not burn 0001"; return 1; }
    [[ -f "$B_DIR/prekeys/alice/0002.agekey" ]] || { echo "0002 must survive"; return 1; }
}
