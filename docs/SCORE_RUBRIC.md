<!-- SPDX-License-Identifier: MIT -->
# Score Rubric — X Messenger Terminal

Based on X-Courier_BUILD_SPEC.md section 10, with caps enforced.

| Criterion | Weight | How to Score | Cap if Missing |
|---|---|---|---|
| Cryptography is standard and reviewed | 20 | Uses only published, reviewed primitives (AES-256-GCM, PBKDF2, Ed25519, X25519, ML-KEM), no custom crypto | — |
| Independent audit | 20 | 0 = none, 10 = informal review, 20 = published professional audit | **Overall max 75 if 0** |
| Forward secrecy | 10 | 0 = none, 5 = experimental ratchet, 10 = production double ratchet | — |
| Metadata minimization | 10 | 10 = no accounts/servers, loopback default; −2 per opt-in leaky mode | — |
| Sender authentication + replay protection | 10 | 0 = none, 5 = optional XM1S + replay, 10 = mandatory + default | — |
| Endpoint hardening | 10 | FLAG_SECURE, camera-only, clipboard clear, encrypted vault, CSP, no unsafe-inline | — |
| Supply chain & reproducibility | 10 | Signed releases, pinned SHAs, SBOM, reproducible build, Scorecard ≥8 | **Overall max 65 if unsigned** |
| Ease of use | 10 | Plain-words UI, QR flow, non-technical user tested | **Overall max 60 if claims without evidence** |

## Cap Enforcement

The final score is capped at the lowest applicable cap:
- If independent audit = 0 → score ≤ 75
- If releases unsigned → score ≤ 65
- If any claim lacks evidence → score ≤ 60

## Scoring Formula

```
raw_score = sum(criterion_score)
final_score = min(raw_score, cap_audit, cap_signed, cap_evidence)
```

## Current Assessment (v1.6.0, commit d9ef49e)

| Criterion | Score | Evidence |
|---|---|---|
| Standard crypto | 18 | AES-256-GCM, PBKDF2-600k, Ed25519, X25519, ML-KEM; no custom crypto |
| Independent audit | 0 | None (self-audit only) |
| Forward secrecy | 5 | v2 ratchet experimental, unaudited |
| Metadata minimization | 8 | Loopback default; LAN/VPS opt-in leaky |
| Sender auth + replay | 7 | XM1S optional Ed25519, replay cache in vault |
| Endpoint hardening | 8 | FLAG_SECURE, camera-only, clipboard clear, vault, CSP no unsafe-inline |
| Supply chain | 6 | SBOM, reproducible check, Scorecard, pinned SHAs; signing via env vars |
| Ease of use | 7 | Plain UI, QR flow; no formal user test |
| **Raw total** | **59** | |
| **Cap: no audit (75)** | **59** | |
| **Cap: unsigned releases (65)** | **59** | |
| **Cap: claims without evidence (60)** | **59** | |
| **Final score** | **59 / 100** | |

*Self-audit, not an independent audit. Cap 75 applies until external audit.*