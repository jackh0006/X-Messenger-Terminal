<!-- SPDX-License-Identifier: MIT -->
# Termux Manual Test Checklist

This checklist must be completed on a real Android device (arm64) for each release.
Record results in `docs/TERMUX_TEST_RESULTS.md` with device info and date.

## Device Info Template

| Field | Value |
|---|---|
| Device model | |
| Android version | |
| Termux version | `termux-info` output |
| Architecture | `uname -m` (should be aarch64) |
| Test date | |
| Tester | |

## Test Cases

### 1. Installation
- [ ] Install APK from GitHub Release (arm64)
- [ ] App launches without crash
- [ ] No "Internet permission" warning during install
- [ ] Camera permission requested on first QR scan

### 2. Core Offline Flow
- [ ] Seal a short message ("hello") with phrase → QR appears
- [ ] Scan QR with second device (or same device camera) → decrypt succeeds
- [ ] Wrong phrase → "Could not decrypt" error (no crash)
- [ ] Tampered QR (draw on it) → rejection error
- [ ] Long message (>2000 chars) → multi-part QR (XMQ1) → scan all parts → decrypt succeeds
- [ ] Multi-part QR missing one part → "Incomplete code" error

### 3. Vault (Locked History)
- [ ] Enable vault with passphrase → history locks
- [ ] Background app → vault auto-locks
- [ ] Unlock with correct passphrase → history readable
- [ ] Wrong vault passphrase → "Could not unlock" error
- [ ] Change vault passphrase → history re-sealed, old passphrase rejected
- [ ] "Forgot" wipe → all data removed, app resets to fresh state

### 4. Contacts & Threads
- [ ] Add contact → appears in Users tab
- [ ] Send message to contact → appears in their thread
- [ ] Delete contact → removed from Users, messages stay in Saved
- [ ] Contact name with special chars (emoji, unicode) → works

### 5. v2 Pairing (Experimental)
- [ ] Open Pair v2 → shows "Not connected"
- [ ] Generate code → QR appears
- [ ] Scan peer code on second device → "Their code scanned"
- [ ] Encapsulate → ciphertext QR appears
- [ ] Scan ciphertext on first device → "Compare fingerprint"
- [ ] Compare fingerprint OUT LOUD → match → confirm
- [ ] Paired contact appears in Users → thread works
- [ ] v2 seal → decrypt via paired session (no phrase needed)
- [ ] Unpair → session ended, contact marked unverified

### 6. Settings & Persistence
- [ ] Theme change (system/light/dark) → persists after restart
- [ ] Font size change → persists after restart
- [ ] Custom port → persists after restart (requires GUI restart)
- [ ] Device identity creation → fingerprint shown
- [ ] Device identity rotation → new fingerprint, old messages show unverified

### 7. Data Export/Import
- [ ] Export backup → `.json` file created
- [ ] Import backup → contacts + sealed envelopes restored
- [ ] Import invalid backup (wrong format, too large) → rejected

### 8. Security Properties
- [ ] No network traffic during any operation (use `tcpdump` or `netstat`)
- [ ] App works in Airplane mode (Wi-Fi + mobile data off)
- [ ] Clipboard auto-clears after 30 seconds
- [ ] Phrase fields clear on background/lock
- [ ] FLAG_SECURE prevents screenshots in app switcher
- [ ] No plaintext in app private storage (check with `adb shell`)

### 9. CLI (Termux)
- [ ] `cipherlink encrypt "msg" --to "contact"` → outputs XM1S envelope
- [ ] `cipherlink decrypt "XM1S..."` → prompts for phrase hidden
- [ ] `cipherlink --phrase "x" decrypt "..."` → warns about shell history
- [ ] `cipherlink version` → shows correct version
- [ ] `x-messenger gui` → launches GUI on https://127.0.0.1:443

### 10. Edge Cases
- [ ] Very long message (near 8000 char limit) → seals/decrypts
- [ ] Unicode/emoji message → round-trips correctly
- [ ] Rapid seal/decrypt cycles → no memory leak
- [ ] App kill during vault write → no corruption on restart

## Results Recording

After testing, create `docs/TERMUX_TEST_RESULTS.md`:

```markdown
# Termux Test Results — X Messenger Terminal v1.6.0

**Date:** 2026-XX-XX
**Device:** [model] | Android [version] | Termux [version] | aarch64
**Tester:** [name]

## Summary
- Total tests: XX
- Passed: XX
- Failed: XX
- Skipped: XX

## Failures (if any)
| Test | Expected | Actual |
|---|---|---|
| ... | ... | ... |

## Notes
[Any observations, performance notes, crashes, etc.]
```

Commit the results with the release.