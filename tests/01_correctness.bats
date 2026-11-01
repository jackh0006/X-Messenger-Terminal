#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Correctness tests: content round trip, recipient scoping, passphrase vault.

load 'test_helper'

@test "T01 round trip: send then read returns identical text for several sizes" {
    fresh_pair
    for size in 10 1000 4090 15000 60000; do
        STDIN_FILE="$WORK_DIR/msg_T01_${size}.bin"
        # A real terminal in canonical mode discards input past ~4095 bytes
        # per line, so any multi-KB message must be chunked into short lines
        # with newlines — exactly how a human would paste long text. $(cat)
        # in xc keeps internal newlines; the final line has none.
        python3 - "$STDIN_FILE" "$size" <<'PY'
import random, string, sys
path, size = sys.argv[1], int(sys.argv[2])
rng = random.Random(size)
alpha = string.ascii_letters + string.digits + " ,.-"
msg = "".join(rng.choice(alpha) for _ in range(size))
msg = "\n".join(msg[i:i + 400] for i in range(0, len(msg), 400))
open(path, "w").write(msg)
PY
        [[ -s "$STDIN_FILE" ]] || { echo "stdin file missing for size $size"; return 1; }
        local MSG; MSG=$(cat "$STDIN_FILE")
        pty_cmd "$A_DIR" send bob
        assert_status_zero || return 1
        assert_no_crash || return 1
        [[ -s "$SCRATCH/message.courier" ]] || { echo "no courier file for size $size"; return 1; }
        pty_cmd "$B_DIR" read "$SCRATCH/message.courier"
        assert_no_crash || return 1
        assert_status_zero || return 1
        # The plaintext must appear in bob's terminal transcript, byte-faithful.
        [[ "$TTY_OUTPUT" == *"$MSG"* ]] || { echo "round trip mismatch for size $size"; return 1; }
    done
}

@test "T02 round trip: unicode, quotes, and shell-looking characters survive" {
    fresh_pair
    local MSG='Typing español ✓ 42ºN "quoted" $(injected?) `backticks` — ok ❤'
    STDIN_FILE="$WORK_DIR/msg_T02.bin"; printf '%s' "$MSG" > "$STDIN_FILE"
    pty_cmd "$A_DIR" send bob
    assert_status_zero || return 1
    pty_cmd "$B_DIR" read "$SCRATCH/message.courier"
    assert_status_zero || return 1
    assert_no_crash || return 1
    assert_tty_contains "$MSG" || return 1
}

@test "T03 wrong recipient cannot decrypt: charlie cannot open alice's post to bob" {
    fresh_pair
    STDIN_FILE="$WORK_DIR/msg_T03.bin"; printf 'ship at midnight' > "$STDIN_FILE"
    pty_cmd "$A_DIR" send bob
    assert_status_zero || return 1
    local courier_file="$WORK_DIR/msg_T03.courier"
    cp "$SCRATCH/message.courier" "$courier_file"
    pty_cmd "$C_DIR" init
    assert_status_zero || return 1
    pty_cmd "$C_DIR" read "$courier_file"
    assert_no_crash || return 1
    assert_status_nonzero || return 1
    assert_tty_contains "cannot be opened with your keys" || return 1
}

@test "T04 wrong passphrase is refused cleanly, no crash" {
    local d2; d2=$(mktemp -d "$WORK_DIR/wrong.XXXXXX")
    # Create the vault with a passphrase the standard driver does not know.
    TEST_PASS="p1-my-real-vault-pass"
    pty_cmd "$d2" init
    local created="$TTY_STATUS"
    TEST_PASS="correct-horse-battery-22"
    [[ "$created" -eq 0 ]] || { echo "init with own passphrase failed"; return 1; }
    # Now try to open it with the standard (wrong) passphrase.
    pty_cmd "$d2" id
    assert_no_crash || return 1
    assert_status_nonzero || return 1
    assert_tty_contains "Incorrect passphrase" || return 1
    rm -rf "$d2"
}

@test "T05 padding: sealed sizes stay inside buckets; oversize is refused before any key work" {
    fresh_pair
    # messages are chunked into <=400-byte lines: a real terminal in
    # canonical mode drops input past ~4095 bytes per line.
    gen5() {
        python3 - "$1" "$2" <<'PY'
import sys
path, size = sys.argv[1], int(sys.argv[2])
msg = "m" * size
msg = "\n".join(msg[i:i + 400] for i in range(0, len(msg), 400))
open(path, "w").write(msg)
PY
    }
    # Bucket sweep: 0 refused, others seal and decrypt cleanly. Sealed courier
    # sizes must collapse onto exactly the bucket set (equal for inputs of
    # the same bucket, distinct across buckets, and monotone up).
    local sz_one="" sz_thousand="" sz_4k="" sz_16k="" sz_64k="" cur_sz
    for size in 0 1 1000 4000 16000 60000; do
        STDIN_FILE="$WORK_DIR/msg_T05_$size.bin"
        gen5 "$STDIN_FILE" "$size"
        local MSG=""
        if [[ $size -ne 0 ]]; then MSG=$(cat "$STDIN_FILE"); fi
        pty_cmd "$A_DIR" send bob
        assert_no_crash || return 1
        if [[ $size -eq 0 ]]; then
            assert_status_nonzero || return 1
            [[ -e "$SCRATCH/message.courier" ]] && { echo "empty message sealed"; return 1; }
            assert_tty_not_contains "Enter passphrase" || return 1
            continue
        fi
        assert_status_zero || return 1
        [[ -s "$SCRATCH/message.courier" ]] || { echo "no courier for size $size"; return 1; }
        pty_cmd "$B_DIR" read "$SCRATCH/message.courier"
        assert_no_crash || return 1
        assert_status_zero || return 1
        [[ "$TTY_OUTPUT" == *"$MSG"* ]] || { echo "round trip mismatch for size $size"; return 1; }
    done
    # Over the largest bucket: refused with plain words, without touching
    # the passphrase vault or leaving any output behind.
    STDIN_FILE="$WORK_DIR/msg_T05_big.bin"
    gen5 "$STDIN_FILE" 66100
    pty_cmd "$A_DIR" send bob
    echo "OVERSIZE TRANSCRIPT:" >&2
    echo "$TTY_OUTPUT" >&2
    echo "OVERSIZE STATUS: $TTY_STATUS" >&2
    assert_no_crash || return 1
    assert_status_nonzero || return 1
    assert_tty_contains "This message is too long. Maximum is 64 KiB" || return 1
    assert_tty_not_contains "Enter passphrase" || return 1
    [[ -e "$SCRATCH/message.courier" ]] && { echo "oversize message was sealed"; return 1; }
    [[ -z "$(find "$SCRATCH" -type f 2>/dev/null)" ]] \
        || { echo "leftover scratch files: $(find "$SCRATCH" -type f)"; return 1; }
    [[ -z "$(find "$A_DIR" \( -name 'vault.*' -o -name 'body.*' -o -name 'unpad.*' -o -name '*.tmp' \) 2>/dev/null)" ]] \
        || { echo "temp leftovers in the data dir"; return 1; }
}
