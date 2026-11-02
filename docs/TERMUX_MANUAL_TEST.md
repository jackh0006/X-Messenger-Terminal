# TERMUX_MANUAL_TEST.md — Real-Device Test Checklist

**Status: NOT YET VERIFIED — no real-device run has been recorded yet.**

This checklist must be completed on a **real Android device (arm64, aarch64)**
for each release. CI uses emulated runners; real device behavior may differ.
**Never mark the device test passed until the owner has run it and committed
the results below.**

---

## Device Info (Fill In)

| Field | Value |
|-------|-------|
| Device model | |
| Android version | |
| Termux version | `termux-info` |
| Architecture | `uname -m` (should be aarch64 / arm64) |
| Test date | |
| Tester | |

---

## Test Cases (matching shipped commands)

### 1. Installation

- [ ] Install Termux from **F-Droid** (not Play Store)
- [ ] Run `pkg install bash age openssh jq util-linux` (+ `qrencode zbar` for QR id checks)
- [ ] Download release tarball + SHA256SUMS + signature
- [ ] Verify with `ssh-keygen -Y verify` (see release notes commands)
- [ ] Run `./scripts/install.sh` — completes without error, no silent package installs
- [ ] `xc` available in PATH (`which xc`), `xc --version` prints the version

### 2. Core Functionality

- [ ] `xc init` — creates identity, 4 passphrase prompts (type `QC` vh, min), keys stored encrypted at rest (no plaintext key files under the data dir)
- [ ] `xc init` twice — refuses, points to `xc wipe`
- [ ] `xc id` — shows age pubkey (age1...), ssh-ed25519 key, `SHA256:...` fingerprint
- [ ] `xc add alice` — imports friend ID pasted from their `xc id`, shows fingerprint
- [ ] `xc verify alice` — fingerprint compare in person, marks verified
- [ ] `xc send alice` — type message + Ctrl-D on terminal, produces `message.courier`
- [ ] `xc read message.courier` — prompts for passphrase, decrypts, prints message
- [ ] Wrong passphrase → "Incorrect passphrase" (no crash)
- [ ] Second `xc read` of the same message → "Replay detected"
- [ ] `xc send unverified` — refuses until contact is verified
- [ ] `--expires` in the past → "Message expired" on read

### 3. Hygiene & Security

- [ ] `find ~/.xcourier -type f | xargs grep -F '<passphrase>'` finds nothing
- [ ] `ps` during `xc send`/`xc read` — passphrase never appears
- [ ] Data dir and files are 700/600 (inspect with `ls -la`)
- [ ] No network calls — `netstat -tuln` while sending/reading
- [ ] `xc doctor` — lists tools, no missing-required output

### 4. UX

- [ ] Errors in plain words, no stack traces or crypto internals
- [ ] Passphrase input is not echoed by age prompts (or is masked)
- [ ] `Ctrl+C` during `xc send`/`xc read` → no leftover scratch files

### 5. Edge Cases

- [ ] Empty message → rejected
- [ ] >64 KiB message → "Message too large" refused
- [ ] Unicode/emoji message → round-trips correctly
- [ ] Tampered `.courier` → refused ("cannot be opened with your keys"), never a crash

### 6. Roadmap stubs stay honest

- [ ] `xc qr-send|qr-read` still print `NOT IMPLEMENTED: <cmd>` and exit 1
- [ ] `xc prekeys --help` shows make/import; a make + hand-over + import round trip with a second phone works (see ROADMAP Stage 2)
- [ ] `xc wipe` on a copy dir: lowercase `yes` is refused, `WIPE` erases the whole folder including contacts and one-time keys; after wiping, `xc init` works again
- [ ] `xc rotate` with `--keep-old`: fingerprint changes, `identity.old/` holds the old encrypted keys, contacts must re-add and re-verify, and a courier sealed before the rotation really cannot be opened anymore

### 7. Uninstall

- [ ] `./scripts/uninstall.sh` — removes `xc` binary only
- [ ] Keys/contacts remain in `~/.xcourier/`
- [ ] `./scripts/uninstall.sh --dry-run` — shows what would be removed

---

## Results Recording

After testing, create a commit with results:

```markdown
# Termux Test Results — X Messenger Terminal v<version>

**Date:** YYYY-MM-DD
**Device:** [model] | Android [version] | Termux [version] | aarch64
**Tester:** [name]

## Summary
- Total tests: XX
- Passed: XX
- Failed: XX
- Skipped: XX

## Failures (if any)
| Test | Expected | Actual |
|------|----------|--------|

## Notes
[Observations, performance, crashes, UI issues, etc.]
```

Commit this file as `docs/TERMUX_TEST_RESULTS_<version>.md` with the release.

---

## Sign-Off

**Tester:** _________________  
**Date:** _________________  
**All critical tests passed:** ☐ Yes / ☐ No