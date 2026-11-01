#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Shared helpers for the X Messenger Terminal test suite.
#
# The passphrase used in tests lives only in TEST_PASS here. It is given to
# the pty driver as an inline (temporary) environment prefix — never as an
# argument, never written to a file — and the driver strips it from the
# child's environment before exec. xc itself never sees a passphrase other
# than through the terminal it prompts on.

REPO_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
XC="$REPO_DIR/xc"
HELPERS="$REPO_DIR/tests/helpers"
WORK_DIR="${XC_TEST_WORK:-/tmp/xc-bats}"
DRIVER_TIMEOUT="${XC_TEST_TIMEOUT:-120}"

mkdir -p "$WORK_DIR"

TEST_PASS="correct-horse-battery-22"

# Per-test scratch state; each test creates its own dirs.
A_DIR=""; B_DIR=""; C_DIR=""; SCRATCH=""
TTY_STATUS=""; TTY_OUTPUT=""
STDIN_FILE=""

fail_with_transcript() {
    echo "wanted: $1" >&2
    echo "== pty stderr (full) ==" >&2
    cat "$WORK_DIR/pty.err" 2>/dev/null | tr -d '\r' >&2 || true
    echo "== pty transcript (full) ==" >&2
    printf '%s\n' "$TTY_OUTPUT" >&2 || true
    return 1
}

pty_cmd() {
    local dir="$1"; shift
    # STDIN_FILE is consumed ONCE per call, then cleared: a leftover message
    # must never be typed into a later command's passphrase prompt.
    local sin="$STDIN_FILE"
    STDIN_FILE=""
    # Fresh scratch dir EVERY call: the previous implementation reused
    # SCRATCH across calls via ${SCRATCH:-...}, which caused stale output
    # files (e.g., a successful 60KB send's message.courier) to persist
    # and falsely appear as "oversize was sealed" when a later send died.
    SCRATCH=$(mktemp -d "$WORK_DIR/run.XXXXXX")
    local trans st=0
    trans=$(mktemp "$WORK_DIR/trans.XXXXXX")
    : > "$trans"
    local args=()
    [[ -n "$sin" ]] && args+=(--stdin-text "$sin" --stdin-first)
    # `|| st=$?` is load-bearing: bats runs with errexit, and a nonzero
    # driver status here must land in TTY_STATUS (asserted later on) rather
    # than abort this helper before the asserts can record a transcript.
    XC_TEST_PASS="$TEST_PASS" python3 "$HELPERS/pty_drive.py" \
        --cwd "$SCRATCH" --timeout "$DRIVER_TIMEOUT" \
        ${args[@]+"${args[@]}"} --transcript "$trans" \
        -- XCOURIER_DATA_DIR="$dir" "$XC" "$@" \
        </dev/null 2>"$WORK_DIR/pty.err" || st=$?
    TTY_STATUS=$st
    TTY_OUTPUT=$(tr -d '\r' < "$trans")
    rm -f "$trans"
    return 0
}

# Asserts for pty-driven runs. Per spec: any status above 128 means the
# child was killed by a signal and is treated as a failure, never expected.
assert_status_zero() {
    [[ "$TTY_STATUS" -eq 0 ]] || { fail_with_transcript "exit status 0, got $TTY_STATUS"; return 1; }
}

assert_no_crash() {
    [[ "$TTY_STATUS" -le 128 ]] || { fail_with_transcript "no signal crash allowed, got status $TTY_STATUS"; return 1; }
}

assert_status_nonzero() {
    [[ "$TTY_STATUS" -ne 0 ]] || { fail_with_transcript "nonzero exit status, got 0"; return 1; }
}

assert_tty_contains() {
    [[ "$TTY_OUTPUT" == *"$1"* ]] || { fail_with_transcript "output contains [$1]"; return 1; }
}

assert_tty_not_contains() {
    [[ "$TTY_OUTPUT" != *"$1"* ]] || { fail_with_transcript "output must NOT contain [$1]"; return 1; }
}

new_dirs() {
    A_DIR=$(mktemp -d "$WORK_DIR/alic.XXXXXX")
    B_DIR=$(mktemp -d "$WORK_DIR/bob.XXXXXX")
    C_DIR=$(mktemp -d "$WORK_DIR/chal.XXXXXX")
    SCRATCH=$(mktemp -d "$WORK_DIR/run.XXXXXX")
}

# Builds alice + bob, mutually added and verified. SLOW-ish (two identities).
fresh_pair() {
    new_dirs
    pty_cmd "$A_DIR" init
    [[ "$TTY_STATUS" -eq 0 ]] || { echo "alice init failed"; return 1; }
    pty_cmd "$B_DIR" init
    [[ "$TTY_STATUS" -eq 0 ]] || { echo "bob init failed"; return 1; }
    pty_cmd "$A_DIR" id && A_ID="$TTY_OUTPUT"
    pty_cmd "$B_DIR" id && B_ID="$TTY_OUTPUT"
    XCOURIER_DATA_DIR="$A_DIR" "$XC" add bob <<< "$B_ID"
    XCOURIER_DATA_DIR="$A_DIR" "$XC" verify bob <<< "y"
    XCOURIER_DATA_DIR="$B_DIR" "$XC" add alice <<< "$A_ID"
    XCOURIER_DATA_DIR="$B_DIR" "$XC" verify alice <<< "y"
}

# -- counts as crash failure if the driver reports >128; zero for success
# sanity: driver exits 124 on its own timeout — treat as failure too.
assert_driver_alive() {
    [[ "$TTY_STATUS" -ne 124 ]] || { fail_with_transcript "driver timeout — child never finished"; return 1; }
}
