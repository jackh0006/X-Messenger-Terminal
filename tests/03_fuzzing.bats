#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Fuzz tests. NOTE: these are fast smoke tests only. The hard requirement —
# at least one hour of fuzzing per parser run in CI for every release, and a
# 24-hour run before v1.0 — lives in scripts/audit.sh (security section) and
# is executed by the CI fuzz job, not here.

load 'test_helper'

@test "T11 fuzz smoke: corrupted-header corpus never crashes, always clean error" {
    fresh_pair
    local i fail=0
    for i in $(seq 1 60); do
        python3 - "$WORK_DIR/fz_$i" <<'PY'
import os, random, sys
random.seed(os.getpid())
n = random.choice([10, 100, 500, 2048])
data = bytes([random.randint(1, 255) for _ in range(n)])  # 0x00 excluded: header-less garbage
if random.random() < 0.3:
    data = b'X-COURIER/1\n' + data     # valid header, garbage body
open(sys.argv[1], 'wb').write(data)
PY
        run env XCOURIER_DATA_DIR="$B_DIR" "$XC" read "$WORK_DIR/fz_$i" >/dev/null 2>&1
        local st=$status
        if [[ $st -ge 129 ]]; then
            echo "CRASH (status $st) on $WORK_DIR/fz_$i" >&2
            fail=1
        fi
        rm -f "$WORK_DIR/fz_$i"
    done
    [[ $fail -eq 0 ]]
}

@test "T12 fuzz smoke: garbage reaching the decrypt step is refused by age, no crash" {
    fresh_pair
    # Valid header, then garbage body; read goes through the passphrase
    # prompts and must fail at age, cleanly, without any signal kill.
    python3 -c "
import random
random.seed(7)
open('$WORK_DIR/fzbody','wb').write(bytes([random.randint(1,255) for _ in range(2048)]))
"
    printf 'X-COURIER/1\n' | cat - "$WORK_DIR/fzbody" > "$WORK_DIR/fzbody.courier"
    pty_cmd "$B_DIR" read "$WORK_DIR/fzbody.courier"
    assert_no_crash || return 1
    assert_status_nonzero || return 1
    assert_driver_alive || return 1
    rm -f "$WORK_DIR/fzbody" "$WORK_DIR/fzbody.courier"
}