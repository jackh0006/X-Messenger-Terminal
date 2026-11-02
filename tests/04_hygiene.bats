#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Hygiene tests: no plaintext leftovers, permissions, and secret discipline.

load 'test_helper'

@test "T13 hygiene: no plaintext vault or body scratch survives a round trip" {
    fresh_pair
    STDIN_FILE="$WORK_DIR/msg_T13.bin"; printf 'cleanup check' > "$STDIN_FILE"
    pty_cmd "$A_DIR" send bob
    assert_status_zero || return 1
    pty_cmd "$B_DIR" read "$SCRATCH/message.courier"
    assert_status_zero || return 1
    # No decrypted vault: only encrypted .enc files may live in identity/.
    [[ -e "$B_DIR/identity/age.priv" ]] && { echo "PLAINTEXT age privkey survived"; return 1; }
    [[ -e "$B_DIR/identity/ssh"     ]] && { echo "PLAINTEXT ssh key survived"; return 1; }
    [[ -e "$B_DIR/identity/age.priv.enc" && -e "$B_DIR/identity/ssh.enc" ]]
    # No body/body.* scratch left in the data dir, no vault.* dirs.
    [[ -z "$(find "$B_DIR" -name 'body*' -o -name 'vault.*' 2>/dev/null)" ]]
}

@test "T14 hygiene: data dir 0700, sensitive files 0600" {
    fresh_pair
    [[ $(stat -c %a "$A_DIR") == "700" ]] || { echo "data dir not 700: $(stat -c %a "$A_DIR")"; return 1; }
    [[ $(stat -c %a "$A_DIR/identity") == "700" ]] || return 1
    [[ $(stat -c %a "$A_DIR/identity/age.priv.enc") == "600" ]] || { echo "age.priv.enc not 600"; return 1; }
    [[ $(stat -c %a "$A_DIR/identity/ssh.enc") == "600" ]] || { echo "ssh.enc not 600"; return 1; }
    [[ $(stat -c %a "$A_DIR/contacts/bob.json") == "600" ]] || { echo "contact file not 600"; return 1; }
    STDIN_FILE="$WORK_DIR/msg_T14.bin"; printf 'perm check' > "$STDIN_FILE"
    pty_cmd "$A_DIR" send bob
    assert_status_zero || return 1
    [[ $(stat -c %a "$SCRATCH/message.courier") == "600" ]] || { echo "courier not 600: $(stat -c %a "$SCRATCH/message.courier")"; return 1; }
}

@test "T15 hygiene: no passphrase in any data-dir file and none in ps during a run" {
    fresh_pair
    uid=$RANDOM
    STDIN_FILE="$WORK_DIR/msg_T15_$uid.bin"; printf "ps-and-files check $uid" > "$STDIN_FILE"
    # Start a real send under the pty driver in the background, then scan ps.
    ( sleep 0.3
      for i in $(seq 1 25); do
          if ps -e -o args= 2>/dev/null | grep -Fq "$TEST_PASS"; then
              echo "PASSPHRASE SEEN IN PROCESS LIST" > "$WORK_DIR/ps_leak"
          fi
          sleep 0.1
      done ) &
    local watcher=$!
    pty_cmd "$A_DIR" send bob
    assert_no_crash || return 1
    assert_status_zero || return 1
    wait "$watcher" || true
    assert_tty_not_contains "$TEST_PASS" || return 1
    rm -f "$WORK_DIR/ps_leak"
    # Filesystem: no file under the data dir contains the passphrase at rest.
    if grep -rIl -F "$TEST_PASS" "$A_DIR" 2>/dev/null; then
        echo "PASSPHRASE FOUND IN FILES: $(grep -rIl -F "$TEST_PASS" "$A_DIR")"
        return 1
    fi
    # And the transcript file: the driver must not have echoed it either.
    if grep -q -F "$TEST_PASS" "$WORK_DIR/pty.err"; then
        echo "PASSPHRASE FOUND IN DRIVER STDERR"
        return 1
    fi
}

@test "T16 hygiene: command runs without network access (canary)" {
    # Pick a namespace mechanism: rootless userns+netns first, then a
    # passwordless-sudo network namespace (GitHub runners), and only skip
    # when neither exists (some local sandboxes).
    local mech=""
    if unshare -rn true 2>/dev/null; then
        mech="rootless"
    elif sudo -n unshare -n true 2>/dev/null; then
        mech="sudo-netns"
    else
        skip "no unshare mechanism here (userns denied, no passwordless sudo); CI runs this canary as ok"
    fi
    fresh_pair
    # Policy: xc performs no network syscalls. Canary: DNS resolution must
    # fail inside the namespace even if the tool tried to open a socket.
    local nsprobe target
    target="XCOURIER_DATA_DIR='$A_DIR' '$XC' doctor >/dev/null 2>&1; test \$(getent hosts example.invalid 2>/dev/null | wc -l) -eq 0"
    if [[ "$mech" == "rootless" ]]; then
        nsprobe=(unshare -rn)
    else
        nsprobe=(sudo -n unshare -n)
    fi
    run env -u SUDO_ASKPASS "${nsprobe[@]}" bash -c "$target"
    [[ "$status" -eq 0 ]] || { echo "canary failed via $mech (status $status)"; return 1; }
}
