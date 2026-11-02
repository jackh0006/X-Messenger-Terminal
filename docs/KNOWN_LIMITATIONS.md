# KNOWN_LIMITATIONS.md — Every Weakness the AI Found

This document lists every known limitation, weakness, and caveat of X Messenger Terminal as of the current commit. Do not hide any.

---

## Cryptographic Limitations

| Limitation | Impact | Mitigation | Status |
|------------|--------|------------|--------|
| **No forward secrecy on default path** | Long-term identity key compromise = all past messages readable | Use `xc prekeys` for forward secrecy | Documented; prekeys optional |
| **Prekeys not default** | Most users won't enable forward secrecy | Warn in `xc send` if prekeys available but not used | Planned: warn in `xc send` |
| **Prekey deletion on flash storage is best effort** | Wear leveling may leave private key remnants | Document honestly; recommend encrypted filesystem | Documented in `xc read` output |
| **No ratcheting** | No per-message keys (except optional one-time prekeys); compromise of the current key exposes future messages until you rotate | `xc rotate` replaces the key pair behind a typed confirmation (tested, R01–R05); messages after the rotation are sealed to the new key | Mitigation shipped; full ratcheting planned for v2 |
| **No deniability** | Signatures provide non-repudiation (intentional) | Not a goal; this is a courier, not OTR | By design |

---

## Identity & Key Management

| Limitation | Impact | Mitigation | Status |
|------------|--------|------------|--------|
| **Identity keys in encrypted file only** | No hardware-backed storage (YubiKey) on default | Optional `age-plugin-yubikey` support planned | Planned Stage 3 |
| **Vault passphrase protects everything** | Weak passphrase = all keys exposed | Min 12 chars or 5-word generated; high-value mode warns | Implemented |
| **No key escrow / recovery** | Lost passphrase = permanent data loss | Document clearly; no backdoors | By design |
| **Fingerprint is 6-byte truncation** | 48-bit collision resistance; not 128-bit | 6-word mnemonic for human comparison | Acceptable for in-person verify |

---

## Replay & Expiry

| Limitation | Impact | Mitigation | Status |
|------------|--------|------------|--------|
| **Replay cache persists on disk** | If vault locked, cache not checked until unlock | Document: replay check only when vault unlocked | Documented |
| **Expiry optional** | Messages without expiry never auto-reject | Recommend setting expiry in `xc send` | Default off |
| **Replay cache grows unbounded** | Long-term use = large cache file | Periodic cleanup in `xc doctor` | Planned |

---

## Prekey System

| Limitation | Impact | Mitigation | Status |
|------------|--------|------------|--------|
| **Prekey exchange in person only** | No remote prekey exchange (by design) | QR/USB in person | By design |
| **Exhausted prekeys fall back to identity key** | Forward secrecy lost silently after exhaustion | Warn at <5 remaining; `xc prekeys` shows count | Implemented |
| **Prekey bundle signed but not encrypted** | Public halves visible in transit | Only public keys in bundle; private halves encrypted | By design |
| **No prekey forward secrecy for sender** | Sender's long-term key used to sign bundle | Sender identity is already known to recipient | Acceptable |

---

## Device & Endpoint

| Limitation | Impact | Mitigation | Status |
|------------|--------|------------|--------|
| **Compromised device = total loss** | Malware/root/screen capture keylogger defeats all | Cannot defend against OS compromise | By design |
| **Coercion / rubber-hose** | User can be forced to reveal vault passphrase | No plausible deniability; not a goal | By design |
| **No secure deletion on flash** | Wear leveling prevents guaranteed overwrite | `xc wipe` best effort; recommend encrypted FS | Documented in `xc wipe` |
| **Termux: no FLAG_SECURE on all Android versions** | Screenshots/recording may work on some versions | Best effort; document | Planned |
| **Clipboard not used** | QR/file only; no clipboard leakage | By design | By design |

---

## Network & Metadata

| Limitation | Impact | Mitigation | Status |
|------------|--------|------------|--------|
| **Prekey exchange leaks metadata** | QR/USB reveals timing, size, participants | In-person exchange; no network | By design |
| **QR frames reveal message size** | Number of frames ≈ message size | Padding buckets hide exact length | Partial |
| **No traffic analysis resistance** | Timing of QR scans visible | No network = no remote timing | By design |

---

## Usability & Human Factors

| Limitation | Impact | Mitigation | Status |
|------------|--------|------------|--------|
| **Fingerprint verification in person required** | Users may skip or do incorrectly | 6-word mnemonic; QR shows fingerprint | Documented in `xc add` |
| **No live chat / groups / sync** | Not a chat app; different use case | By design | By design |
| **Vault passphrase entry visible to shoulder surfers** | `read -s` hides but screen may be recorded | FLAG_SECURE on Android; user awareness | Partial |
| **No accessibility testing** | Screen readers, high contrast not verified | Terminal-based; generally accessible | Planned |

---

## Supply Chain & Build

| Limitation | Impact | Mitigation | Status |
|------------|--------|------------|--------|
| **Dependencies on system packages** | `age`, `openssh`, `qrencode`, `zbar` must be present | `install.sh` checks and prints exact install commands | Implemented |
| **No reproducible build for binary** | Single shell script — source is the binary | Source = binary; `xc` is the artifact | By design |
| **No binary signing for `xc` script** | Script itself not signed (only releases) | Release tarball signed; source is the script | Acceptable |
| **No SBOM for script itself** | Only dependencies listed | `SBOM.cdx.json` includes transitive deps | Planned |

---

## Testing Gaps

| Limitation | Impact | Mitigation | Status |
|------------|--------|------------|--------|
| **Real Termux device not tested yet** | arm64 CI uses QEMU; real device behavior may differ | Manual checklist; user will run and commit | Planned Stage 5 |
| **No formal usability test with non-technical users** | Menu clarity not validated | Planned Stage 5 | Planned |
| **Fuzzing duration limited** | CI: 1h/parser; 24h pre-v1.0 | Documented in fuzzing log | Planned |
| **No independent audit** | Cap 75 until audit | Prepare AUDIT_CHECKLIST, REVIEW_ME | Stage 6 |

---

## Platform-Specific

### Linux
| Limitation | Impact | Status |
|------------|--------|--------|
| `qrencode` / `zbar` may not be in default repos | Must install from universe/epel | Documented in INSTALL.md |
| `FLAG_SECURE` not applicable | Screenshots possible | N/A |

### Termux (Android)
| Limitation | Impact | Status |
|------------|--------|--------|
| `termux:api` may be needed for camera | QR scan may not work without | Documented |
| `FLAG_SECURE` not on all Android versions | Screenshots may leak | Documented |
| No background execution | App must stay open for QR scan | By design |

---

## Documentation Gaps

| Gap | Planned |
|-----|---------|
| `docs/ASVS_MAPPING.md` | Stage 4 |
| `docs/KNOWN_LIMITATIONS.md` (this file) — complete | Done |
| `docs/AUDIT_CHECKLIST.md` — complete | Done |
| `docs/REVIEW_ME.md` — complete | Done |

---

**Last updated:** $(date)  
**Commit:** (to be filled at commit time)