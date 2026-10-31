<!-- SPDX-License-Identifier: MIT -->
# Score History — X Messenger

Every score is tied to a specific commit. Scores always refer to the project's own rubric (section 10 of X-Courier_BUILD_SPEC.md / docs/SCORE_RUBRIC.md).

| Date | Commit | Score | Reviewer | Notes |
|---|---|---|---|---|
| 2026-10-31 | f2770b2b91baaef0113da8014361c053face69e1 | **45 / 100** | AI review (Nemotron 3 Ultra) | **AI review, not an audit.** Baseline: no audit (cap 75), v1 lacks sender auth/forward secrecy/replay; unsigned releases; CSP gaps; test count drift (69 vs 72 claimed). |

---

## Scoring Rubric Reference (from docs/SCORE_RUBRIC.md)

| Criterion | Weight | Cap if missing |
|---|---|---|
| Cryptography is standard and reviewed | 20 | — |
| Independent audit | 20 | overall max 75 if none |
| Forward secrecy | 10 | — |
| Metadata minimization | 10 | — |
| Sender authentication and replay protection | 10 | — |
| Endpoint hardening | 10 | — |
| Supply chain and reproducibility | 10 | overall max 65 if unsigned |
| Ease of use | 10 | overall max 60 if claims without evidence |

*Caps are enforced by the rubric. A score above a cap requires the condition to be met.*

---

## Next Targets (from docs/ROADMAP.md)

| Target | Expected Δ | Prerequisite |
|---|---|---|
| Signed releases + pinned Actions + SBOM + reproducibility proof | +4 | release signing key |
| XM1S (Ed25519 sender auth on default path) | +5 | device keypair + verify flow |
| v2 ratchet promoted from experimental (fuzzed, model done) | +5 | Go core audit |
| XM1 replay cache | +2 | vault integration |
| CSP + innerHTML removal | +1 | boot-probe extraction |
| Real usability tests (3 non-technical) | +3 | human sessions |
| **Independent external audit** | **+20** | paid/community audit |

**Realistic ceiling without audit:** 75 (rubric cap).
**Realistic ceiling with audit + fixes:** 85–90 for its niche (offline, small, high-value messages).
**100 is not possible** — no certified standard (FIPS 140, Common Criteria) is earned through a repo; those need paid accredited labs.