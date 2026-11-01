#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Tamper tests: flipping, truncating, forging, replaying, expiring.

load 'test_helper'

@test "T06 tamper: a flipped byte in the body is refused" {
    fresh_pair
    STDIN_FILE="$WORK_DIR/msg_T06.bin"; printf 'secret handoff' > "$STDIN_FILE"
    pty_cmd "$A_DIR" send bob
    assert_status_zero || return 1
    cp "$SCRATCH/message.courier" "$WORK_DIR/badflip.courier"
    python3 - "$WORK_DIR/badflip.courier" <<'PY'
import sys
p = sys.argv[1]
b = bytearray(open(p, 'rb').read())
b[14] ^= 0xFF
open(p, 'wb').write(bytes(b))
PY
    pty_cmd "$B_DIR" read "$WORK_DIR/badflip.courier"
    assert_no_crash || return 1
    assert_status_nonzero || return 1
    assert_tty_contains "cannot be opened with your keys" || return 1
}

@test "T07 tamper: a truncated courier is refused, never a crash" {
    fresh_pair
    STDIN_FILE="$WORK_DIR/msg_T07.bin"; printf 'short note' > "$STDIN_FILE"
    pty_cmd "$A_DIR" send bob
    assert_status_zero || return 1
    truncate -s 40 "$SCRATCH/message.courier"
    pty_cmd "$B_DIR" read "$SCRATCH/message.courier"
    assert_no_crash || return 1
    assert_status_nonzero || return 1
}

@test "T08 tamper: re-signed by a wrong key is rejected by the signature check" {
    fresh_pair
    # An attacker's own ed25519 key signs a bundle that claims alice's
    # identity, sealed to bob. Bob must stop at the signature check.
    local attacker_dir; attacker_dir=$(mktemp -d "$WORK_DIR/forger.XXXXXX")
    ssh-keygen -t ed25519 -N "" -f "$attacker_dir/forged" -C forgery >/dev/null
    python3 - "$A_DIR" "$B_DIR" "$attacker_dir/forged" "$SCRATCH/forged.courier" <<'PY'
import base64, json, subprocess, sys
a_dir, b_dir, forge_key, out_path = sys.argv[1:5]
with open(f'{b_dir}/contacts/alice.json') as f: alice = json.load(f)
with open(f'{a_dir}/contacts/bob.json') as f: bob = json.load(f)
payload = base64.b64encode(b'00000009HELLOGARB').decode()
canon = json.dumps({
    'v': '1',
    'msg_id': '0'*28 + 'abcd',
    'timestamp': '2026-01-01T00:00:00Z',
    'sender_fp': alice['fingerprint'],
    'recipient_fp': bob['fingerprint'],
    'expiry': '',
    'payload': payload,
}, sort_keys=True, separators=(',', ':'))
signed = subprocess.run(['ssh-keygen','-Y','sign','-f',forge_key,'-n','x-courier'],
                        input=canon.encode(), capture_output=True, check=True).stdout
package = json.loads(canon)
package['sig'] = base64.b64encode(signed).decode()
text = json.dumps(package, separators=(',', ':'))
enc = subprocess.run(['age','-e','-r',bob['age_pub']],
                     input=text.encode(), capture_output=True, check=True).stdout
with open(out_path, 'wb') as f:
    f.write(b'X-COURIER/1\n')
    f.write(enc)
PY
    pty_cmd "$B_DIR" read "$SCRATCH/forged.courier"
    assert_no_crash || return 1
    assert_status_nonzero || return 1
    assert_tty_contains "Signature check FAILED" || return 1
    rm -rf "$attacker_dir"
}

@test "T09 tamper: replay is rejected on the second read" {
    fresh_pair
    STDIN_FILE="$WORK_DIR/msg_T09.bin"; printf 'one-time order' > "$STDIN_FILE"
    pty_cmd "$A_DIR" send bob
    assert_status_zero || return 1
    local courier_file="$WORK_DIR/msg_T09.courier"
    cp "$SCRATCH/message.courier" "$courier_file"
    pty_cmd "$B_DIR" read "$courier_file"
    assert_status_zero || return 1
    pty_cmd "$B_DIR" read "$courier_file"
    assert_no_crash || return 1
    assert_status_nonzero || return 1
    assert_tty_contains "Replay detected" || return 1
}

@test "T10 tamper: an expired message is rejected" {
    fresh_pair
    STDIN_FILE="$WORK_DIR/msg_T10.bin"; printf 'must be past' > "$STDIN_FILE"
    pty_cmd "$A_DIR" send bob --expires "2020-01-01T00:00:00Z"
    assert_status_zero || return 1
    local courier_file="$WORK_DIR/msg_T10.courier"
    cp "$SCRATCH/message.courier" "$courier_file"
    pty_cmd "$B_DIR" read "$courier_file"
    assert_no_crash || return 1
    assert_status_nonzero || return 1
    assert_tty_contains "Message expired" || return 1
}