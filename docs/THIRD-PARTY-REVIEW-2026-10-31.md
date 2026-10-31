<!-- SPDX-License-Identifier: MIT -->
# Third-Party Review — X Messenger v1.5.2 (commit f2770b2)

**Reviewer:** AI code review (Nemotron 3 Ultra) — **not an audit, not a guarantee**
**Date:** 2026-10-31
**Scope:** Read-only review of `core.js`, `app.js`, `server.js`, `bin/cipherlink`, all 7 test suites, 3 CI workflows, Android manifest, Go v2 core, release scripts, and published release hashes (verified against GitHub API).

> **Disclaimer:** This is a code review by an AI model. It is **not** an independent security audit, does not constitute a guarantee of any kind, and should not be presented as one. The strongest honest claim is: *the evidence is published and re-runnable — check it yourself.*

---

## 1. Verified Truths (read-and-confirmed)

| Property | Evidence |
|---|---|
| Genuinely offline (`CAMERA` only, no `INTERNET`) | `android/app/src/main/AndroidManifest.xml` + CI gate 2 |
| Loopback default, zero egress | `server.js` bindMode `loopback` → `127.0.0.1`; no outbound fetches |
| TLS 1.2+ minimum, GET/HEAD allow-list | `server.js` L80, L75 |
| Path traversal safe | Strict allow-list + containment check in `server.js` |
| 600k PBKDF2, fresh salt+nonce per seal | `core.js` L30, L117 + test "each seal uses fresh salt and nonce" |
| Tamper fails closed | `core.js` decrypt + dedicated tests |
| QR parts fail closed | `core.js` qrAssemble strict checks + 5 tests |
| Plaintext never persisted | Vault = AES-GCM; labels/settings only in plaintext; test L131 |
| Six strict-boundary CI gates | `.github/workflows/strict-boundary.yml` — real, meaningful checks |
| Version lockstep 1.5.2 | Test reads 4 files; enforced in CI |
| FLAG_SECURE on Android | `MainActivity.java` |
| Published bytes = claimed hashes | All 14 release digests in `SHA256SUMS.txt` match GitHub API asset digests |
| Clean dependency surface | 6 deps, 0 packages with install scripts in lockfile |

Code hygiene is careful: no `eval`, message list via `textContent`, contacts via `textContent`, phrases wiped on hide, clipboard auto-clear (30s) confirmed.

---

## 2. Findings (by severity)

### HIGH (design-level — deal-breakers for life-critical use)

| ID | Finding | Location |
|---|---|---|
| H1 | **No sender authentication on default path (`XM1`).** Anyone who learns the phrase can forge a message "from you". | `core.js` — passphrase-only model |
| H2 | **No forward secrecy on `XM1`.** Phrase learned later = every message ever sealed with it opens. | `SECURITY.md` admits it |
| H3 | **No replay protection on `XM1`.** Intercepted envelope stays valid forever. v2 has replay window (`PROTOCOL-v2.md` L102); v1 has none. | `core.js` |
| H4 | **Release checksums unsigned.** `release.sh` creates SHA256SUMS and uploads — no minisign/cosign/GPG signature, no signed tag. PROTOCOL-v2.md lists minisign as planned. | `scripts/release.sh` |
| H5 | **Unaudited.** v1: "composition audit pending"; v2: "experimental, do not rely for high-risk use". | `SECURITY.md` |

### MEDIUM

| ID | Finding | Location |
|---|---|---|
| M1 | CSP uses `script-src 'unsafe-inline'`; Android WebView serves with no CSP (assets://). `app.js` L427 builds message-details modal with `innerHTML` interpolation — one careless edit = XSS. Fix: remove interpolation, add CSP `<meta>` for WebView. | `app.js` L427, `index.html`, `server.js` L113 |
| M2 | `--phrase` accepts secrets as argv (visible in `ps`/history). Warns, but spec rule was "never". | `bin/cipherlink` L89-102 |
| M3 | GitHub Actions pinned to moving tags (`@v4`, `@v5`), not commit SHAs — spec requirement, OpenSSF Scorecard penalty. | All 3 workflows |
| M4 | No SBOM, no reproducible-build comparison tarball published. | Release assets |
| M5 | Advertised "72/72 tests" — actual mechanical count: **69** (13+24+8+4+7+5+8). README table must match evidence. | `test/*.test.js` |

### LOW
- `document.write` fallback in `index.html` L9 (static text, acceptable)
- `server.js` silent port retry on EADDRINUSE (announces actual port — acceptable)
- Endpoint-file error path writes without `0600` (`server.js` L137)
- v2 fingerprint is hex; wordlist rendering honestly flagged "needs audited list" (`handshake.go`)

---

## 3. Overstated Claims (fix before advertising)

1. **"Who can read your words — plain answer: nobody."** `SECURITY.md` contradicts this (malware, keyloggers, observed phrase). A security reviewer flags this in the first minute — the ◐ row in the table proves it.
2. **"Unlocked phone + known phrase → ◐ that one message."** Wrong in the unsafe direction: the phrase opens **every message ever sealed with that phrase** (no forward secrecy). Table row must say "all messages with this phrase".
3. **Comparison scoreboard vs WhatsApp/Telegram.** Cells like "No server copy to leak ✓ vs ✗" are arguable (WhatsApp has E2EE, optional device backups). Spec section 10 warned against this table. Keep it, soften to "wins on: zero bars, no account, no server in the loop — loses on: audit, forward secrecy, identity layer".
4. **7-coin donation wall in README main body** hurts credibility with security reviewers. Move to footer link.

---

## 4. Score by Project's Own Rubric (section 10 of X-Courier_BUILD_SPEC.md)

| Criterion | Max | Score | Basis |
|---|---|---|---|
| Standard, reviewed crypto | 20 | **14** | stdlib primitives, no invented crypto; v1 composition passphrase-only, unaudited; v2 strong but experimental |
| Independent audit | 20 | **0** | None — honestly stated |
| Forward secrecy | 10 | **3** | Real hash-ratchet + replay window exists in v2 (verified in `ratchet.go`/`store.go`), but experimental/unaudited; default path has none |
| Metadata minimization | 10 | **8** | No accounts/servers, loopback default; VPS/LAN opt-in leaky |
| Sender auth + replay | 10 | **2** | v1: none; v2: both, experimental |
| Endpoint hardening | 10 | **6** | FLAG_SECURE, camera-only, clipboard clear, encrypted vault, crypto-shredding (v2); no hardware keys, WebView/CSP gaps |
| Supply chain & reproducibility | 10 | **5** | Checksums verified + clean lockfile + artifact machines; **no** release signature, no pinned SHAs, no SBOM, no reproducible proof, no Scorecard |
| Ease of use | 10 | **7** | Plain-words UI, QR flow, works for non-technical; no third-party user test |
| **Total** | 100 | **45 / 100** | |

Caps from rubric: no independent audit → max 75. **45/100 today**, with caps respected.

---

## 5. Recommended Fixes (ranked by points)

1. **Sign every release** (minisign — planned in PROTOCOL-v2), sign git tag, attach SBOM + rebuild-compare proof, pin Actions to full SHAs → supply chain 5→9 (+4).
2. **Give XM1 sender identity:** sign every envelope with Ed25519 device key (XM1S), verify on read, contact fingerprint verify flow → sender auth 2→7 (+5).
3. **Promote v2 ratchet out of experimental** (fuzz Go core, finish Tamarin model, remove "do not rely" banner) → forward secrecy 3→8 (+5).
4. **Add replay cache for XM1** (seen-envelope hashes in vault) → +2.
5. **CSP hygiene:** delete `'unsafe-inline'`, move boot script out of `index.html`, add CSP `<meta>` for WebView → +1.
6. **Record real usability sessions** with 3 non-technical people → +3.
7. **External audit** → +20. Realistic trajectory: 45 → ~55 (no audit) → 85+ (with audit). 100 is not possible.

---

## 6. Bottom Line (may publish as-is)

> X-Messenger v1.5.2 does what it says for ordinary threat models: it seals text locally with standard crypto (AES-256-GCM + PBKDF2-600k), shares by QR/file with no account, no server, no internet permission, fails closed on tampering, and its published hashes verified against the repo builds in my check. It is not — and does not claim to be — protection against a seized device, espionage-grade attackers, or a learned phrase: the default channel has no sender authentication, no forward secrecy, and no replay protection, and nothing has been independently audited. A cold reviewer score by the project's own rubric is **45/100**, capped at 75 until an external audit. Its honest advertising line is real and checkable: *don't trust us — run `npm ci && npm test`, compare the SHA-256 of what you downloaded, and read SECURITY.md's limits.*

---

*Review completed 2026-10-31 against commit `f2770b2b91baaef0113da8014361c053face69e1`. This review is evidence, not authority — run the tests and check the hashes yourself.*