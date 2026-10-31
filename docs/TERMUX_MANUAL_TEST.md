# TERMUX_MANUAL_TEST.md — Real-Device Test Checklist

This checklist must be completed on a **real Android device (arm64)** for each release.  
CI uses QEMU; real device behavior may differ. **Never mark passed until tested on hardware.**

---

## Device Info (Fill In)

| Field | Value |
|-------|-------|
| Device model | |
| Android version | |
| Termux version | `termux-info` |
| Architecture | `uname -m` (should be aarch64) |
| Test date | |
| Tester | |

---

## Test Cases

### 1. Installation

- [ ] Install Termux from **F-Droid** (not Play Store)
- [ ] Run `pkg install age openssh qrencode zbar`
- [ ] Download release tarball + verification files
- [ ] Run `./scripts/install.sh` — completes without error
- [ ] `xc` available in PATH (`which xc`)
- [ ] `xc --version` shows correct version

### 2. Core Functionality

- [ ] `xc init` — creates identity, prompts for passphrase (min 12 chars), stores encrypted
- [ ] `xc id` — shows age pubkey (age1...), SSH pubkey (ssh-ed25519...), 6-word fingerprint
- [ ] `xc id --qr` — displays QR code (scannable)
- [ ] `xc add alice` — imports friend ID (paste/file/QR), shows fingerprint, asks for in-person confirm
- [ ] `xc verify alice` — re-checks fingerprint, marks verified
- [ ] `xc send alice` — types message, produces `message.courier`, optional QR frames
- [ ] `xc read message.courier` — prompts for passphrase, decrypts, shows sender, wipes temp
- [ ] `xc qr-send` — produces numbered QR frames for long message
- [ ] `xc qr-read` — scans frames, reassembles, decrypts
- [ ] Wrong passphrase → "incorrect passphrase" (no crash)
- [ ] Tampered `.courier` → "tampered" error (no wrong output)
- [ ] Replay same message twice → second rejected

### 3. Vault & Prekeys

- [ ] `xc init` with vault passphrase — encrypts identity keys
- [ ] `xc lock` — locks vault, wipes keys from memory
- [ ] `xc unlock` — prompts passphrase, restores keys
- [ ] `xc prekeys 50` — generates 50 one-time keypairs, signed bundle
- [ ] `xc send` with prekeys — uses one prekey, marks used
- [ ] `xc read` with prekey — decrypts, **deletes private half immediately**
- [ ] Exhausted prekeys → falls back to identity key with warning

### 4. Key Management

- [ ] `xc rotate` — generates new identity keys, optional keep old
- [ ] `xc wipe` — removes binary only; `--purge` removes keys/contacts with typed confirmation
- [ ] `xc doctor` — checks tools, versions, permissions, network, history, platform
- [ ] `xc selftest` — end-to-end test with throwaway keys passes

### 5. UI & Usability

- [ ] Menu: numbered choices, plain words ("friend", "secret message", "ID", "password")
- [ ] One question per screen, safe defaults
- [ ] Lines under 40 chars (fits small phone screen)
- [ ] Colors with text labels (OK/WARNING/STOP), respects `NO_COLOR`
- [ ] Errors in plain words, no stack traces or crypto internals
- [ ] Colors work on Termux default theme
- [ ] `read -s` hides passphrase input
- [ ] `Ctrl+C` exits safely, cleans temp files

### 6. Security Properties

- [ ] **No network calls** — verify with `netstat -tuln` during operations
- [ ] **Camera only** — Termux permission `CAMERA` only; no `INTERNET`
- [ ] **FLAG_SECURE** — screenshots/recording blocked (if supported)
- [ ] **Clipboard not used** — QR/file only
- [ ] **Vault passphrase** — `read -s`, never in args, zeroed on lock
- [ ] **Temp files** — in `$TMPDIR` (0700), cleaned on exit/Ctrl+C
- [ ] **Vault passphrase zeroed** on background/lock
- [ ] **Replay cache** — works when vault unlocked

### 7. QR Camera Flow

- [ ] `xc qr-send` produces valid QR codes (scannable)
- [ ] `xc qr-read` opens camera, scans, decodes
- [ ] Multi-frame QR: scans out of order, reassembles correctly
- [ ] Damaged QR → clear error, no crash
- [ ] Camera permission prompted and works

### 8. Edge Cases

- [ ] Empty message → rejected
- [ ] 60 KiB message → padded to 64 KiB bucket, works
- [ ] Unicode/emoji message → round-trips correctly
- [ ] Very long friend name (32 chars) → accepted
- [ ] Friend name with `../`, `;`, `$()`, backticks → rejected
- [ ] Symlink in `~/.xcourier/` → refused
- [ ] `Ctrl+C` during `xc send` → cleans temp, exits cleanly
- [ ] `Ctrl+C` during `xc read` → cleans temp, exits cleanly

### 9. Uninstall

- [ ] `./scripts/uninstall.sh` — removes `xc` binary only
- [ ] Keys/contacts remain in `~/.xcourier/`
- [ ] Re-install works, keys still usable
- [ ] `./scripts/uninstall.sh --purge` — typed confirmation, removes everything
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