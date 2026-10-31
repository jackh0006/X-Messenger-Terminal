<!-- SPDX-License-Identifier: MIT -->
# Roadmap — X Messenger Terminal

Each item tagged with rubric criterion and expected point delta.

## v1.7 (Next Release)

| Item | Criterion | Δ Points | Effort |
|---|---|---|---|
| Promote v2 ratchet from experimental (fuzz Go core, complete Tamarin model) | Forward secrecy | +5 | High |
| Mandatory XM1S for all contacts (no unsigned fallback) | Sender auth + replay | +3 | Medium |
| Formal usability test with 5 non-technical users | Ease of use | +3 | Medium |
| Minisign key published + signing in CI (not just env) | Supply chain | +2 | Low |
| Scorecard ≥ 8 achieved | Supply chain | +2 | Low |
| CLAIMS.md fully populated for all README claims | Evidence (cap 60) | +1 | Low |

**Target score: ~77 (but capped at 75 until audit)**

---

## v1.8 (Audit Preparation)

| Item | Criterion | Δ Points | Effort |
|---|---|---|---|
| External security audit (paid or community) | Independent audit | +20* | High |
| Fix all audit findings | All | — | High |
| Hardware key support (YubiKey/FIDO2) for device identity | Endpoint hardening | +2 | High |
| One-time prekeys for offline forward secrecy (10c.A) | Forward secrecy | +5 | High |
| Two-person review enforced for crypto changes (CI gate) | Supply chain | +1 | Medium |
| THREAT_MODEL.md reviewed by outside party | Supply chain | +1 | Medium |

*After audit + fixes: cap 75 lifted → realistic 85–90*

---

## v2.0 (Post-Audit / Major)

| Item | Criterion | Δ Points | Effort |
|---|---|---|---|
| Migrate crypto core to Rust (libsodium) + FFI | Standard crypto | +2 | Very High |
| Asynchronous double ratchet (Signal-style) | Forward secrecy | +5 | Very High |
| Post-quantum hybrid KEM default (ML-KEM-1024) | Standard crypto | +2 | High |
| Reproducible builds for all platforms (guix/nix) | Supply chain | +2 | High |
| FIPS 140-3 validation (if funded) | Standard crypto | N/A* | Very High |

*FIPS/CC certification requires paid labs — not achievable via repo alone*

---

## Score History

| Version | Commit | Score | Cap | Notes |
|---|---|---|---|---|
| 1.5.2 | f2770b2 | 45 | 75 | Baseline; no auth, no replay, unsigned |
| 1.6.0 | d9ef49e | 59 | 75 | XM1S, replay, CSP, pinned SHAs, SBOM |
| 1.7 (planned) | — | ~75 | 75 | v2 promoted, mandatory XM1S, usability test |
| 1.8 (post-audit) | — | 85–90 | — | External audit + fixes |

---

## Notes

- **100 is not possible** — no certified standard (FIPS 140, Common Criteria) earned through repo; requires paid accredited labs.
- **Realistic ceiling without audit: 75** (rubric cap).
- **Realistic ceiling with audit: 85–90** for niche (offline, small, high-value messages).
- Every score tied to commit in `docs/SCORE_HISTORY.md`.