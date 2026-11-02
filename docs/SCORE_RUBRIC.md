# Score Rubric — X Messenger Terminal

Based on the project's own rubric with caps enforced.

| Criterion | Weight | How to Score | Cap if Missing |
|-----------|--------|--------------|----------------|
| Cryptography is standard and reviewed | 20 | Uses only published, reviewed primitives (age, OpenSSH), no custom crypto. **Stays ≤15 until an independent review exists.** | — |
| Independent audit | 20 | 0 = none, 10 = informal review, 20 = published professional audit | **Overall max 75 if 0** |
| Forward secrecy | 10 | 0 = none, 5 = optional prekeys, 10 = default prekeys | — |
| Metadata minimization | 10 | 10 = no servers/accounts, loopback default; −2 per opt-in leaky mode | — |
| Sender authentication + replay protection | 10 | 0 = none, 5 = optional XM1S + replay, 10 = mandatory + default | — |
| Endpoint hardening | 10 | FLAG_SECURE (Android), encrypted vault, CSP, no unsafe-inline | — |
| Supply chain & reproducibility | 10 | Signed releases, pinned SHAs, SBOM, reproducible build, Scorecard ≥8. **Never exceeds what has actually been exercised** (no signed release exists → stays low) | **Overall max 65 if unsigned** |
| Ease of use | 10 | User-tested with non-technical people. **Counts 0 until a real user test exists; code reading is not a test** | **Overall max 60 if claims without evidence** |

## Scoring Rules

1. **A number goes up only when a test exercises it.** No test, no points — file existence, keyword greps, or future work never earn security-category points.
2. **Crypto stays ≤15/20 until an independent review** of the crypto-relevant code by someone outside this project.
3. Caps still apply on top: no audit → ≤75; unsigned releases → ≤65; claims without evidence → ≤60.

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

## Current Assessment (Stage 2a — prekeys)

| Criterion | Score | Evidence Reference |
|-----------|-------|-------------------|
| Standard crypto | **15** | Exercised: tests/01_correctness.bats T01–T05, tests/02_tamper.bats T06–T10 (round-trip, wrong recipient, wrong passphrase, buckets, byte-flip, truncation, re-signed key, replay, expiry) — run inside audit.sh / CI. Below 20 by rule: no independent review yet. |
| Independent audit | **0** | No audit; audit.sh is a self-check suite (up to 39 checks — the exact count varies by environment because skipped suite tests surface as per-test SKIP rows; statuses PASS/FAIL/SKIP/PLANNED). |
| Forward secrecy | **5** | Optional one-time prekeys, implemented and exercised: `tests/07_prekeys.bats` K01–K06 — signed per-identity bundles (K01/K04/K05), one distinct key consumed per send and never reused (K01/K02), private half burned only after decrypt AND signature AND replay all pass (K01/K02), garbage never burns a key (K06), exhausted bundle refuses without `--no-forward-secrecy` and falls back with an honest warning (K03). Rubric 10 ("default prekeys") not claimed: a message is sealed to a one-time key only after the friend's bundle is imported; exchanges without bundles use the legacy identity-key path. |
| Metadata minimization | **10** | No servers/accounts by design (xc, README); offline property exercised by T16 (CANARY: SKIP locally, runs in the rootless CI job) and `unshare` audit check when available. |
| Sender auth + replay | **10** | Ed25519 sign-then-encrypt + replay cache exercised by T08 (re-signed wrong key), T09 (replay rejected). |
| Endpoint hardening | **5** | Exercised by T13 (no plaintext leftovers), T14 (0700 dir / 0600 files), T15 (no passphrase in files or `ps`). FLAG_SECURE/csp not applicable yet (no web app). |
| Supply chain & reproducibility | **5** | Exercised by T20 (no expect/minisign/passphrase-CLI in shipped code) + supply.pinned_actions config check + Actions pinned by SHA. No signed release, SBOM, or reproducible build has been exercised (audit rows are PLANNED). |
| Ease of use | **0** | Rule: counts only after a real user test with non-technical people. C-15 (menu plain-words) is code-only; no user test exists. |

| **Raw total** (15+0+5+10+10+5+5+0) | **50** | |
| **Cap: no audit (75)** | not binding | |
| **Cap: unsigned releases (65)** | not binding | |
| **Cap: claims without evidence (60)** | not binding numerically (raw 50 already ≤ 60); note several claim rows (C-14, C-15, C-17–C-19) are code-existence claims without test IDs yet | CLAIMS.md rows map to real test IDs where applicable (claims.test_ids_covered).

| **Final score** | **50 / 100** | |

Changes from the 45 recorded for Stage 1.8: forward secrecy 0→5 — the ONLY change; one-time prekeys are implemented and test-exercised (K01–K06 run in this suite, and the audit's adv.forward_secrecy_prekeys check derives from that suite run). "Optional prekeys" per the rubric scale, not 10: a one-time key is used only after the friend's bundle is imported, so no default-on claim is made. Nothing else moved.