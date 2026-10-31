<!-- SPDX-License-Identifier: MIT -->
# REVIEW_ME.md — Map for Reviewers

This document helps a reviewer (human or AI) quickly locate and verify every security-relevant part of the codebase.

## Quick Start

```bash
# 1. Run the self-audit (collects all evidence)
./scripts/audit.sh

# 2. Read the generated reports
cat evidence/audit-report.txt
cat evidence/audit-report.json | jq '.summary'

# 3. Verify key claims manually
npm test                    # All 69 tests pass
npm run build:web           # Bundle builds
node scripts/check-wasm-pair.js www  # WASM pair verified
```

---

## Crypto Entry Points

| Function | File | Line | Purpose |
|---|---|---|---|
| `encryptText` / `decryptText` | `core.js` | ~84/~106 | XM1 envelope (PBKDF2 + AES-GCM) |
| `encryptTextSigned` / `decryptTextSigned` | `core.js` | ~294/~306 | XM1S signed envelope (Ed25519) |
| `generateIdentity` / `loadIdentity` / `saveIdentity` | `core.js` | ~250/~260/~265 | Device Ed25519 keypair |
| `replayInit` / `replayCheck` / `replayMark` | `core.js` | ~340/~355/~365 | Replay protection |
| `vaultSeal` / `vaultOpen` | `core.js` | ~225/~242 | Encrypted history vault |
| `qrSplit` / `qrAssemble` | `core.js` | ~148/~199 | Multi-part QR framing |

**No custom crypto** — all primitives from WebCrypto (AES-GCM, PBKDF2, SHA-256) and tweetnacl (Ed25519). Go v2 core uses `crypto/ecdh`, `crypto/mlkem`, `crypto/hkdf`, `crypto/rand`.

---

## Input Validation Points

| Check | File | Line |
|---|---|---|
| Friend name (alphanum + space/_-) | `app.js` | ~710 |
| Age pubkey bech32 format | `app.js` | (not yet used) |
| SSH pubkey format | `app.js` | (not yet used) |
| Path traversal blocked | `server.js` | ~85-95 |
| Symlink refused | `server.js` | ~90-95 |
| Payload size limits | `core.js` | ~7-8, ~58-62 |

---

## Secrets Handling

| Location | Mechanism |
|---|---|
| Phrase fields | `app.js` `wipeSecrets()` on hide/background; `read -s` in CLI |
| Vault passphrase | In memory only; zeroed on lock (`vaultLock`) |
| Device identity secret | Encrypted in localStorage with vault passphrase |
| Clipboard | Auto-clear 30s (`clearClipboardLater`) |
| localStorage keys | Only `PROFILE_KEY`, `SETTINGS_KEY`, `VAULT_KEY`, `IDENTITY_KEY`, `REPLAY_KEY`, `V2BROKEN_KEY`, `x-messenger-why-seen-v1` |
| No secrets in CLI args | `--phrase` warns and only for automation |

---

## Network Boundary

| Component | Behavior |
|---|---|
| Android | `AndroidManifest.xml`: only `CAMERA` permission; `allowBackup=false`, `usesCleartextTraffic=false` |
| Linux GUI | `server.js`: binds `127.0.0.1` by default; TLS 1.2+; GET/HEAD only; strict path allow-list |
| Web bundle | `strict-boundary.yml` gate: no XHR/WebSocket/fetch to external; no trackers; no remote assets |
| v2 WASM | Loaded same-origin from `/vendor/xm2.wasm`; no network in Go core (`go list -deps` gate) |

---

## Test Coverage Map

| Suite | File | Tests | Properties Covered |
|---|---|---|---|
| crypto | `test/crypto.test.js` | 13 | Round-trip, wrong phrase, fresh salt/nonce, tamper, truncate, padding, size limits |
| offline | `test/offline.test.js` | 24 | No network, Android perms, loopback default, TLS, CSP, version lockstep, no hype, SPDX |
| desktop | `test/desktop.test.js` | 8 | .deb, Windows, platform shim, launchers |
| ui-invariants | `test/ui-invariants.test.js` | 8 | IDs exist, themes, caps, drawer, views, threads, small screens |
| pair | `test/pair.test.js` | 7 | v2 secret expansion, fingerprint, QR size, view-once, delete-all |
| qrparts | `test/qrparts.test.js` | 5 | Split/reassemble, out-of-order, malformed, no phrase leak |
| messages | `test/messages.test.js` | 4 | Menu actions, quick bar, reply/star/re-key, graphics |

**Total: 69 tests** (mechanical count, verified by `scripts/count-tests.js`)

---

## Evidence Files

| File | Purpose |
|---|---|
| `docs/CLAIMS.md` | Every public claim → test ID + evidence file |
| `docs/SCORE_RUBRIC.md` | Scoring rules with caps |
| `docs/SCORE_HISTORY.md` | Score per commit |
| `docs/ROADMAP.md` | Next improvements with point deltas |
| `docs/THIRD-PARTY-REVIEW-*.md` | External review reports |
| `evidence/audit-report.json` | Machine-readable audit results (CI artifact) |
| `evidence/audit-report.txt` | Human-readable audit results |
| `X-Messenger-<ver>-SHA256SUMS.txt` | Release hashes (signed if key configured) |
| `X-Messenger-<ver>-SBOM.cdx.json` | CycloneDX SBOM |
| `vendor/BUILD` | WASM toolchain stamp |

---

## Known Weaknesses (from `docs/KNOWN_LIMITATIONS.md`)

1. **No forward secrecy on XM1** — phrase compromise = all history readable
2. **v2 ratchet experimental/unaudited** — Tamarin model incomplete
3. **No hardware-backed keys** — device identity in encrypted file only
4. **Replay cache in vault** — only works when vault unlocked
5. **Signing keys via env vars** — not yet in CI secrets
6. **No formal usability test** — only author testing
7. **Termux manual checklist** — not automated
8. **No independent audit** — cap 75 until paid/community audit

---

## How to Re-Score

1. Run `./scripts/audit.sh` → check `evidence/audit-report.json`
2. Read `docs/CLAIMS.md` → verify each claim has test + evidence
3. Apply `docs/SCORE_RUBRIC.md` caps → compute final score
4. Record in `docs/SCORE_HISTORY.md` with commit hash
5. Update `docs/ROADMAP.md` with next items

---

## Contact

Security issues: jackh109867@gmail.com (never send real phrases or message contents)