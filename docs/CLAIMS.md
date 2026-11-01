# CLAIMS.md — Every Public Claim Linked to Test + Evidence

| Claim ID | Exact Claim | Test ID(s) | Evidence File | Status |
|----------|-------------|------------|---------------|--------|
| C-01 | Uses `age` (X25519 + ChaCha20-Poly1305) for encryption | T01, T02, T05 | `tests/01_correctness.bats`, `xc` source | verified |
| C-02 | Uses OpenSSH Ed25519 signatures (`ssh-keygen -Y sign/verify`) | T08, T09 | `tests/02_tamper.bats`, `xc` source | verified |
| C-03 | Sign-then-encrypt order (signature hidden by encryption) | T08 | `tests/02_tamper.bats`, `xc` source | verified |
| C-04 | Padding to fixed buckets: 1 KiB, 4 KiB, 16 KiB, 64 KiB | T05 | `tests/01_correctness.bats`, `xc` source | verified |
| C-05 | Replay protection: 128-bit ID, timestamp, fingerprints, expiry | T09, T10 | `tests/02_tamper.bats`, `xc` source | verified |
| C-06 | Replay cache rejects repeats | T09 | `tests/02_tamper.bats`, `xc` source | verified |
| C-07 | Offline by design — no network calls at runtime | T16 | `tests/04_hygiene.bats`, CI logs | verified (CI: SKIP locally) |
| C-08 | CI runs full suite under `unshare -rn` | T16 | `.github/workflows/ci.yml` | verified |
| C-09 | Sender authentication on every message | T08 | `tests/02_tamper.bats` | verified |
| C-10 | Length hiding via padding buckets | T05 | `tests/01_correctness.bats` | verified |
| C-11 | Forward secrecy via optional prekeys (`xc prekeys`) | — | `docs/ROADMAP.md` | planned |
| C-12 | One-time prekeys deleted after read | — | `docs/ROADMAP.md` | planned |
| C-13 | `xc doctor` checks tools, versions, permissions, network, history, platform | T12, T17 | `tests/03_fuzzing.bats`, `tests/05_platform.bats` | verified |
| C-14 | `xc selftest` runs end-to-end with throwaway keys | — | `xc` source `cmd_selftest` | verified |
| C-15 | Menu: numbered choices, plain words, <40 chars | — | `xc` source `show_menu` | verified |
| C-16 | Errors in plain words, no crypto internals | T04, T06, T07, T10 | `tests/01_correctness.bats`, `tests/02_tamper.bats` | verified |
| C-17 | Colors with text labels, respects NO_COLOR | — | `xc` source | verified |
| C-18 | Install verifies SHA256SUMS + signature | — | `scripts/install.sh` | verified |
| C-19 | Uninstall keeps keys by default, --purge with typed confirmation | — | `scripts/uninstall.sh` | verified |
| C-20 | No "unhackable", "guaranteed", "CIA-level" claims anywhere | T20 | README, SECURITY.md | verified |
| C-21 | Honest limitations stated: no audit, no forward secrecy (default), device compromise | — | SECURITY.md, README | verified |
| C-22 | Signed releases with ssh-keygen -Y verify, SHA256SUMS, SBOM, evidence bundle | — | `scripts/release.sh` | verified (SBOM planned) |
| C-23 | Pinned GitHub Actions (commit SHAs) | — | `.github/workflows/*.yml` | verified |
| C-24 | Reproducible tarball with rebuild instructions | — | `scripts/reproducible-check.sh` | planned |
| C-25 | Scorecard ≥8, Best Practices badge | — | `.github/workflows/ci.yml` | verified |
| C-26 | BIP39 wordlist integrity (2048 words, SHA-256 pinned) | F01 | `tests/04_wordlist.bats`, `lib/wordlist.txt` | verified |
| C-27 | 6-word and 8-word fingerprint modes with test vectors | F02 | `tests/04_wordlist.bats`, `xc` source | verified |
| C-28 | All 2048 word indices addressable | F03 | `tests/04_wordlist.bats`, `xc` source | verified |
| C-29 | 6-word and 8-word fingerprint displayed in `xc id` and `xc verify` | F02 | `xc` source `cmd_id`, `cmd_verify` | verified |

*Status: "verified" = test + evidence exist; "planned" = in ROADMAP.md for future stage.*