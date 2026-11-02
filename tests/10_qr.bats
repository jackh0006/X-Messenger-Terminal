#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Stage 2 — qr-send / qr-read: numbered QR frames with hard framing rules.
#
# Frame payload format under test (text, one file per frame, e.g.
# message.qr/0001.txt .. NNNN.txt):
#   XQ1 <idx> <total> <orig_total_bytes>
#   <base64-of-chunk-on-one-line>
#
# Reader rules (each its own assertion here):
#   * idx must be 1..total and total <= the frame-count cap,
#   * a duplicate index with a DIFFERENT chunk is refused (identical is ok),
#   * the decoded chunk must not exceed the chunk byte cap,
#   * the sum of decoded chunk lengths must equal orig_total_bytes,
#   * the frame set must be complete before anything is written,
#   * garbage frames refuse cleanly, never crash.
# qr-send seals first, so it needs a passphrase and drives the pty driver;
# qr-read itself touches no key material and must work without an identity.

load 'test_helper'

courier_to_work() { cp "$SCRATCH/message.courier" "$1" && test -s "$1"; }

# mk_frame <dir> <name> <idx> <total> <orig> <chunk-bytes>
mk_frame() {
    local dir="$1" name="$2" idx="$3" total="$4" orig="$5" chunk="$6"
    {
        printf 'XQ1 %s %s %s\n' "$idx" "$total" "$orig"
        base64 -w0 "$chunk"
        printf '\n'
    } >"$dir/$name"
}

@test "Q01 qr: qr-send frames reassemble byte-identically and the courier still opens" {
    fresh_pair || return 1
    rm -f "$WORK_DIR/q1.courier" "$WORK_DIR/q1.reassembled.courier"
    STDIN_FILE="$WORK_DIR/msg.bin"
    printf 'Big message for the QR frame path 0xQR — repeated to make several frames.\n%.0s' $(seq 1 40) >"$STDIN_FILE"
    pty_cmd "$A_DIR" qr-send bob
    assert_status_zero || return 1
    courier_to_work "$WORK_DIR/q1.courier" || return 1
    # qr-send must have produced numbered frame files.
    local qdir="$SCRATCH/message.qr"
    [[ -d "$qdir" ]] || { echo "no message.qr dir produced"; return 1; }
    local n
    n=$(find "$qdir" -maxdepth 1 -name '*.txt' | wc -l | tr -d ' ')
    [[ "$n" -ge 2 ]] || { echo "expected >=2 frames, got $n"; return 1; }

    # Assemble from the frame files and compare bytes.
    local out="$WORK_DIR/q1.reassembled.courier"
    rm -f "$out"
    pty_cmd "$B_DIR" qr-read --out "$out" "$qdir"/*.txt
    assert_status_zero || return 1
    cmp -s "$WORK_DIR/q1.courier" "$out" || { echo "reassembled courier differs byte-wise"; return 1; }
    # Full round trip: bob reads the assembled courier as a normal message.
    pty_cmd "$B_DIR" read "$out"
    assert_status_zero || return 1
    assert_tty_contains "0xQR" || return 1
}

@test "Q02 qr: an out-of-range frame index is refused in plain words" {
    fresh_pair || return 1
    STDIN_FILE="$WORK_DIR/msg.bin"
    printf 'range-check payload\n' >"$STDIN_FILE"
    pty_cmd "$A_DIR" qr-send bob
    assert_status_zero || return 1
    local qdir="$SCRATCH/message.qr"
    local files
    files=("$qdir"/*.txt)
    local total orig header body
    header=$(head -1 "${files[0]}")
    orig=$(printf '%s' "$header" | awk '{print $4}')
    total=$(printf '%s' "$header" | awk '{print $3}')
    body=$(tail -1 "${files[0]}")
    [[ "$total" -ge 1 ]] || { echo "bad total parsed: $total"; return 1; }

    # Craft an out-of-range frame from a real one: idx = total+1.
    local bad="$WORK_DIR/bad_idx.txt"
    rm -f "$bad" "$WORK_DIR/never.courier"
    {
        printf 'XQ1 %s %s %s\n' "$((total + 1))" "$total" "$orig"
        printf '%s\n' "$body"
    } >"$bad"
    local out="$WORK_DIR/never.courier"
    pty_cmd "$B_DIR" qr-read --out "$out" "${files[0]}" "$bad"
    assert_driver_alive || return 1
    assert_status_nonzero || return 1
    assert_tty_contains "out of range" || return 1
    [[ ! -e "$out" ]] || { echo "refused assembly still wrote output"; return 1; }

    # Zero-based index is equally invalid.
    {
        printf 'XQ1 0 %s %s\n' "$total" "$orig"
        printf '%s\n' "$body"
    } >"$bad"
    pty_cmd "$B_DIR" qr-read --out "$out" "$bad"
    assert_status_nonzero || return 1
    assert_tty_contains "out of range" || return 1
}

@test "Q03 qr: duplicate index with a conflicting chunk is refused; an identical duplicate is accepted" {
    fresh_pair || return 1
    # WORK_DIR is fixed (/tmp/xc-bats) — clean our output paths first.
    rm -f "$WORK_DIR/q3.ok.courier" "$WORK_DIR/never2.courier"
    STDIN_FILE="$WORK_DIR/msg.bin"
    printf 'dupe test payload\n' >"$STDIN_FILE"
    pty_cmd "$A_DIR" qr-send bob
    assert_status_zero || return 1
    local qdir="$SCRATCH/message.qr"
    local files
    files=("$qdir"/*.txt)

    # Assemble with ALL frames plus an IDENTICAL copy of frame 1: fine.
    local out="$WORK_DIR/q3.ok.courier"
    rm -f "$out"
    pty_cmd "$B_DIR" qr-read --out "$out" "${files[@]}" "${files[0]}"
    assert_status_zero || return 1
    [[ -s "$out" ]] || return 1

    # Now a CONFLICTING duplicate: same index, different chunk body.
    local bad="$WORK_DIR/q3.bad.txt"
    {
        printf '%s\n' "$(head -1 "${files[0]}")"
        printf 'Tm90IHRoZSBzYW1lIGRhdGE=\n'
    } >"$bad"
    ! cmp -s "$bad" "${files[0]}" || { echo "tamper did not change the duplicate"; return 1; }
    local out2="$WORK_DIR/never2.courier"
    rm -f "$out2"
    pty_cmd "$B_DIR" qr-read --out "$out2" "${files[@]}" "$bad"
    assert_driver_alive || return 1
    assert_status_nonzero || return 1
    assert_tty_contains "conflict" || return 1
    [[ ! -e "$out2" ]] || { echo "conflicting duplicate still wrote output"; return 1; }
}

@test "Q04 qr: a missing frame refuses and nothing is written back" {
    fresh_pair || return 1
    STDIN_FILE="$WORK_DIR/msg.bin"
    printf 'missing-frame payload\n' >"$STDIN_FILE"
    pty_cmd "$A_DIR" qr-send bob
    assert_status_zero || return 1
    local qdir="$SCRATCH/message.qr"
    local files
    files=("$qdir"/*.txt)
    local n
    n=$(printf '%s\n' "${files[@]}" | wc -l | tr -d ' ')
    [[ "$n" -ge 2 ]] || { echo "singleton frame set makes this test impossible"; return 1; }
    # Drop the LAST frame: incomplete set, nothing written.
    local out="$WORK_DIR/never3.courier"
    rm -f "$out"
    local partial
    partial=("${files[@]:0:$((n - 1))}")
    pty_cmd "$B_DIR" qr-read --out "$out" "${partial[@]}"
    assert_driver_alive || return 1
    assert_status_nonzero || return 1
    assert_tty_contains "missing" || return 1
    [[ ! -e "$out" ]] || { echo "incomplete set still wrote output"; return 1; }
}

@test "Q05 qr: caps and totals are enforced; qr-read needs no identity" {
    # A BARE data dir (never init-ed): qr-read must not care.
    local bare="$WORK_DIR/q5bare"
    mkdir -p "$bare" "$WORK_DIR/q5caps"
    local d="$WORK_DIR/q5caps"
    local out="$WORK_DIR/never4.courier"

    # Hand-made frame whose decoded chunk exceeds the chunk byte cap.
    {
        printf 'XQ1 1 1 4096\n'
        head -c 4096 /dev/zero | tr '\0' 'A' | base64 -w0
        printf '\n'
    } >"$d/big.txt"
    pty_cmd "$bare" qr-read --out "$out" "$d/big.txt"
    assert_driver_alive || return 1
    assert_status_nonzero || return 1
    assert_tty_contains "chunk too large" || return 1
    [[ ! -e "$out" ]] || { echo "over-cap chunk still wrote output"; return 1; }

    # An absurd frame-count claim.
    {
        printf 'XQ1 1 99999 4096\n'
        head -c 32 /dev/zero | tr '\0' 'A' | base64 -w0
        printf '\n'
    } >"$d/count.txt"
    pty_cmd "$bare" qr-read --out "$out" "$d/count.txt"
    assert_status_nonzero || return 1
    assert_tty_contains "frame count too large" || return 1

    # A sum-check violation: orig_total_bytes says 100, chunk holds 32.
    {
        printf 'XQ1 1 1 100\n'
        head -c 32 /dev/zero | tr '\0' 'A' | base64 -w0
        printf '\n'
    } >"$d/sum.txt"
    pty_cmd "$bare" qr-read --out "$out" "$d/sum.txt"
    assert_status_nonzero || return 1
    assert_tty_contains "declared total size" || return 1
}

@test "Q06 qr fuzz: garbage frames always refuse cleanly, never crash" {
    local bare="$WORK_DIR/q6bare"
    mkdir -p "$bare"
    local i fail=0
    for i in $(seq 1 40); do
        python3 - "$WORK_DIR/fq_$i" <<'PY'
import os, random, sys
random.seed(os.getpid())
n = random.choice([8, 40, 200, 900])
data = bytes([random.randint(1, 255) for _ in range(n)])
if random.random() < 0.4:
    data = b'XQ1 ' + data   # plausible-looking header, garbage rest
open(sys.argv[1], 'wb').write(data)
PY
        pty_cmd "$bare" qr-read --out "$WORK_DIR/fz_out.courier" "$WORK_DIR/fq_$i"
        if [[ "$TTY_STATUS" -ge 129 ]]; then
            echo "CRASH (status $TTY_STATUS) on frame $i" >&2
            fail=1
        fi
        if [[ "$TTY_STATUS" -eq 0 ]]; then
            echo "garbage frame $i was ACCEPTED (status 0) — parser too lax" >&2
            fail=1
        fi
        if [[ "$TTY_OUTPUT" == *"NOT IMPLEMENTED"* ]]; then
            echo "frame $i hit an unimplemented path instead of a real refusal" >&2
            fail=1
        fi
        if [[ -e "$WORK_DIR/fz_out.courier" ]]; then
            echo "garbage frame $i produced output" >&2
            fail=1
        fi
        rm -f "$WORK_DIR/fq_$i"
    done
    [[ $fail -eq 0 ]]
}
