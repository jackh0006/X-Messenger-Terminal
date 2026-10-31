# Score Rubric — X Messenger Terminal

Based on the project's own rubric (section 10 of spec) with caps enforced.

| Criterion | Weight | How to Score | Cap if Missing |
|-----------|--------|--------------|----------------|
| Cryptography is standard and reviewed | 20 | Uses only published, reviewed primitives (age, OpenSSH), no custom crypto | — |
| Independent audit | 20 | 0 = none, 10 = informal review, 20 = published professional audit | **Overall max 75 if 0** |
| Forward secrecy | 10 | 0 = none, 5 = optional prekeys, 10 = default prekeys | — |
| Metadata minimization | 10 | 10 = no servers/accounts, loopback default; −2 per opt-in leaky mode | — |
| Sender authentication + replay protection | 10 | 0 = none, 5 = optional XM1S + replay, 10 = mandatory + default | — |
| Endpoint hardening | 10 | FLAG_SECURE (Android), encrypted vault, CSP, no unsafe-inline | — |
| Supply chain & reproducibility | 10 | Signed releases, pinned SHAs, SBOM, reproducible build, Scorecard ≥8 | **Overall max 65 if unsigned** |
| Ease of use | 10 | User-tested with non-technical people | **Overall max 60 if claims without evidence** |

## Cap Enforcement

The final score is capped at the lowest applicable cap:
- If independent audit = 0 → score ≤ 75
- If releases unsigned → score ≤ 65
- If any claim lacks evidence in CLAIMS.md → score ≤ 60

## Scoring Formula

```
raw_score = sum(criterion_score)
final_score = min(raw_score, cap_audit, cap_signed, cap_evidence)
```

## Current Assessment (Stage 0)

| Criterion | Score | Evidence |
|-----------|-------|----------|
| Standard crypto | 0 | Not implemented yet |
| Independent audit | 0 | None |
| Forward secrecy | 0 | Not implemented |
| Metadata minimization | 8 | No servers/accounts by design |
| Sender auth + replay | 0 | Not implemented |
| Endpoint hardening | 2 | Planned FLAG_SECURE, encrypted vault |
| Supply chain | 2 | Planned pinned Actions, signed releases |
| Ease of use | 3 | Planned simple menu |
| **Raw total** | **15** | |
| **Cap: no audit (75)** | **15** | |
| **Cap: unsigned releases (65)** | **15** | |
| **Cap: claims without evidence (60)** | **15** | |
| **Final score** | **15 / 100** | |

*Stage 0: Repository structure only. Score will rise as stages complete.*