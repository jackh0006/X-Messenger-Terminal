#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# pty_drive.py — TEST-ONLY pty driver for X Messenger Terminal.
#
# This file exists only under tests/helpers/. It is never installed, never
# shipped with a release, and is not referenced by any shipped script.
#
# What it does:
#   * opens a pseudo-terminal and runs the target command in it,
#   * answers passphrase prompts by typing the value of the XC_TEST_PASS
#     environment variable — the passphrase goes only over the pty file
#     descriptor, never on a command line, never in a file, and it is
#     stripped from the child process environment before exec,
#   * returns the child's exit code, and writes the child's output
#     (prompts visible; typed passphrase is suppressed when the child
#     turns echo off, as age does) to --transcript.
#
# Rules obeyed (spec):
#   * no passphrase in argv: passphrases are read from XC_TEST_PASS here,
#   * child environment never contains XC_TEST_PASS,
#   * exit status above 128 means "crashed by signal"; also reported on
#     stderr so tests can assert no-signal.

import os
import pty
import select
import signal
import sys
import time
import argparse
import termios


def die(msg):
    sys.stderr.write("pty_drive: %s\n" % msg)
    sys.exit(125)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cwd")
    ap.add_argument("--timeout", type=float, default=60.0)
    ap.add_argument("--transcript")
    ap.add_argument("--respond", action="append", default=[],
                    help="PATTERN=TEXT: when PATTERN appears in child output, type TEXT")
    ap.add_argument("--stdin-text", help="text file to type into the child's tty after the passphrase prompts (end of input is typed as Ctrl-D)")
    ap.add_argument("--stdin-after-pairs", type=int, default=2,
                    help="number of answered passphrase prompts to complete before typing the stdin text")
    ap.add_argument("--stdin-first", action="store_true",
                    help="type the stdin text immediately (for commands that read stdin before any prompt, like xc send)")
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    args = ap.parse_args()

    # Child env: no XC_TEST_PASS, plus any VAR=VAL assignments the caller
    # placed before the command name (structure only, never secrets).
    import re
    if args.cmd and args.cmd[0] == "--":
        args.cmd = args.cmd[1:]
    assignments = []
    while args.cmd and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", args.cmd[0]):
        k, _, v = args.cmd[0].partition("=")
        assignments.append((k, v))
        args.cmd = args.cmd[1:]
    if not args.cmd:
        die("no command given")

    # execve does not consult PATH; resolve bare command names here so a
    # typo never turns into a silent-fork-forever situation.
    import shutil
    prog = args.cmd[0]
    if not ("/" in prog):
        prog = shutil.which(prog)
        if prog is None:
            die("command not found: %s" % args.cmd[0])

    # The passphrase lives in this driver's env only.
    passphrase = os.environ.get("XC_TEST_PASS")
    extra = []
    for spec in args.respond:
        pat, sep, text = spec.partition("=")
        if not sep:
            die("--respond must be PATTERN=TEXT")
        extra.append((pat, text))

    # Defaults: age's own prompts. If XC_TEST_PASS is unset and a passphrase
    # prompt appears, we fail loudly instead of typing anything.
    rules = []
    if passphrase is not None:
        rules.append(("Enter passphrase", passphrase))
        rules.append(("Confirm passphrase", passphrase))
    rules.extend(extra)

    # Child env: no XC_TEST_PASS, no exposure.
    env = {k: v for k, v in os.environ.items() if k != "XC_TEST_PASS"}
    for k, v in assignments:
        env[k] = v

    pid, fd = pty.fork()
    if pid == 0:
        try:
            if args.cwd:
                os.chdir(args.cwd)
            os.execve(prog, args.cmd, env)
        except Exception as e:  # pragma: no cover
            sys.stderr.write("pty_drive exec failed: %s\n" % e)
            os._exit(127)

    # Turn off echo on the terminal itself. The child may re-enable it, but
    # our typed bytes (passphrases, message, Ctrl-D) then never reach the
    # transcript via the line discipline's echo, regardless of timing races
    # between our writes and the child's termios changes.
    attrs = termios.tcgetattr(fd)
    attrs[3] &= ~termios.ECHO
    termios.tcsetattr(fd, termios.TCSANOW, attrs)

    os.set_blocking(fd, False)
    out = bytearray()
    deadline = time.monotonic() + args.timeout
    status = None

    def write_all(data):
        # pty input queue is small; a master write can be partial or EAGAIN.
        # Every byte counts: retry until the whole buffer is accepted — but
        # never hang on a child that died before consuming its stdin. On
        # deadline or a dead pty, stop typing; the main loop then reaps the
        # child and reports whatever happens.
        idx = 0
        while idx < len(data):
            if time.monotonic() > deadline:
                if os.environ.get("PTY_DEBUG"):
                    sys.stderr.write("pty_drive: gave up writing stdin at %d/%d bytes\r\n" % (idx, len(data)))
                return
            try:
                idx += os.write(fd, data[idx:])
            except BlockingIOError:
                time.sleep(0.005)
            except OSError:
                return

    def type_text(text):
        if os.environ.get("PTY_DEBUG"):
            sys.stderr.write("pty_drive: typing %s\r\n" % ("*" * len(text)))
        for chunk_start in range(0, len(text), 1024):
            chunk = text[chunk_start:chunk_start + 1024].encode()
            time.sleep(0.01)
            write_all(chunk)
        write_all(b"\r")

    def enter_pat():
        return "Enter passphrase"
    def confirm_pat():
        return "Confirm passphrase"

    # State machine: an 'enter' prompt wants the passphrase; the next prompt
    # must be 'confirm'; terminal redraws may repeat prompt text, so only act
    # when the sequence order matches. Handles any number of prompt pairs.
    last = None
    cursor = 0
    prompts_done = 0
    stdin_path = args.stdin_text
    entered_stdin = False
    answered = []

    def type_stdin_once():
        nonlocal entered_stdin, stdin_path
        if entered_stdin or not stdin_path:
            return
        with open(stdin_path, "rb") as f:
            payload = f.read()
        # A tty in canonical mode delivers buffered input on \n or Ctrl-D;
        # Ctrl-D alone does not flush a line with no terminator, so make
        # sure the typed payload ends with newline. $(cat) inside xc strips
        # the trailing newline again, so content is unchanged.
        if not payload.endswith(b"\n"):
            payload += b"\n"
        if os.environ.get("PTY_DEBUG"):
            sys.stderr.write("pty_drive: typing stdin (%d bytes)\r\n" % len(payload))
        write_all(payload)
        write_all(b"\x04")
        entered_stdin = True
        stdin_path = None

    if args.stdin_first:
        try:
            type_stdin_once()
        except Exception:
            pass

    while True:
        if time.monotonic() > deadline:
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
            try:
                _, st = os.waitpid(pid, 0)
            except OSError:
                st = -1
            status = ("timeout", st)
            break

        events, _, _ = select.select([fd], [], [], 0.05)
        if fd in events:
            try:
                data = os.read(fd, 65536)
            except OSError:
                data = b""
            if data:
                out.extend(data)
                chunk_text = out.decode("utf-8", "replace")
                # Answer prompts exactly once per occurrence. `cursor` is a
                # persistent offset into the full transcript so an already
                # answered prompt is never re-considered.
                while True:
                    i_enter = chunk_text.find(enter_pat(), cursor)
                    i_conf = chunk_text.find(confirm_pat(), cursor)
                    if i_enter != -1 and (i_conf == -1 or i_enter < i_conf):
                        type_text(passphrase)
                        prompts_done += 1
                        cursor = i_enter + len(enter_pat())
                        # Encrypt mode expects a Confirm next; decrypt mode
                        # has no confirmation step, so the next prompt may
                        # again be a plain 'Enter passphrase'.
                        if "(leave empty" in chunk_text[i_enter:i_enter + 90]:
                            last = "enter"
                        else:
                            last = "confirm"
                        continue
                    if last == "enter" and i_conf != -1 and (i_enter == -1 or i_conf < i_enter):
                        type_text(passphrase)
                        prompts_done += 1
                        last = "confirm"
                        cursor = i_conf + len(confirm_pat())
                        continue
                    # A prompt redraw (same prompt re-shown after we already
                    # answered its kind) just advances the cursor.
                    if last == "enter" and i_enter != -1 and i_conf != -1 and i_conf < i_enter:
                        break
                    if last is None and i_enter == -1 and i_conf != -1:
                        break
                    if i_enter == -1 and i_conf == -1:
                        break
                    # nothing well-ordered to answer; avoid infinite loop
                    nxt = min(x for x in (i_enter, i_conf) if x != -1)
                    if nxt == cursor:
                        break
                    cursor = nxt
                # generic --respond patterns (non-passphrase prompts)
                for pat, ans in extra:
                    if pat in chunk_text and pat not in answered:
                        answered.append(pat)
                        type_text(ans)
                # stdin payload: typed after N answered passphrase prompts,
                # then Ctrl-D as EOF for the child's `$(cat)` on a tty.
                if stdin_path and prompts_done >= args.stdin_after_pairs:
                    type_stdin_once()
                continue
        # check for child exit
        try:
            wpid, st = os.waitpid(pid, os.WNOHANG)
        except OSError:
            break
        if wpid == pid:
            # drain remaining output shortly
            try:
                ends = time.monotonic() + 0.3
                while time.monotonic() < ends:
                    events, _, _ = select.select([fd], [], [], 0.05)
                    if fd in events:
                        try:
                            more = os.read(fd, 65536)
                        except OSError:
                            break
                        if not more:
                            break
                        out.extend(more)
            except Exception:
                pass
            status = ("exit", st)
            break

    os.close(fd)
    transcript = out.decode("utf-8", "replace")
    if args.transcript:
        with open(args.transcript, "w") as f:
            f.write(transcript)
    else:
        sys.stdout.write(transcript)

    kind, st = status or ("exit", -1)
    if kind == "timeout":
        sys.stderr.write("pty_drive: TIMEOUT\n")
        sys.exit(124)
    if os.WIFSIGNALED(st):
        sig = os.WTERMSIG(st)
        sys.stderr.write("pty_drive: SIGNAL %d\n" % sig)
        sys.exit(128 + sig)
    code = os.WEXITSTATUS(st)
    if code > 128:
        sys.stderr.write("pty_drive: SUSPICIOUS-EXIT %d\n" % code)
    sys.exit(code)


if __name__ == "__main__":
    main()
