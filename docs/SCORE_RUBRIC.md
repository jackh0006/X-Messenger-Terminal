# Score Rubric — X Messenger Terminal

Based on the project's own rubric with caps enforced.

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

## Current Assessment (Stage 1.6)

| Criterion | Score | Evidence Reference |
|-----------|-------|-------------------|
| Standard crypto | **20** | `tests/01_correctness.bats` T01–T05, `tests/02_tamper.bats` T06–T10; `xc` uses `age` (X25519+ChaCha20-Poly1305) + OpenSSH Ed25519 (`ssh-keygen -Y sign/verify`) |
| Independent audit | **0** | No audit; `scripts/audit.sh` is self-audit only |
| Forward secrecy | **0** | Not implemented; `xc prekeys`/`rotate`/`wipe`/`qr-send`/`qr-read` are stubs (`NOT IMPLEMENTED`) |
| Metadata minimization | **10** | No servers/accounts, offline by design; `tests/04_hygiene.bats` T16 (network blocked under `unshare -rn`) |
| Sender auth + replay | **10** | Ed25519 sign-then-encrypt + replay cache; `tests/02_tamper.bats` T08 (forged sig), T09 (replay) |
| Endpoint hardening | **5** | Vault encryption, 0700/0600 perms; `tests/04_hygiene.bats` T13–T15 |
| Supply chain & reproducibility | **5** | Pinned Actions (`tests/06_supply.bats` T20); `scripts/release.sh` has `ssh-keygen -Y sign` but **no signed release exists yet**; no SBOM/reproducible build verification |
| Ease of use | **5** | Menu-driven, plain words, <40 chars; `xc` shows numbered menu |

| **Raw total** | **55** | |
| **Cap: no audit (75)** | 55 | |
| **Cap: unsigned releases (65)** | 55 | No signed release published |
| **Cap: claims without evidence (60)** | 55 | CLAIMS.md has 25 claims with test+evidence mapping |

| **Final score** | **55 / 100** | |