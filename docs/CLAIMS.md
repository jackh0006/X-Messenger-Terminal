# CLAIMS.md — Every Public Claim Linked to Test + Evidence

| Claim ID | Exact Claim | Test ID(s) | Evidence File | Status |
|----------|-------------|------------|---------------|--------|
| C-01 | Uses `age` (X25519 + ChaCha20-Poly1305) for encryption | `correctness.roundtrip` | `tests/correctness.bats`, `xc` source | not yet |
| C-02 | Uses OpenSSH Ed25519 signatures (`ssh-keygen -Y sign/verify`) | `tamper.resign` | `tests/tamper.bats`, `xc` source | not yet |
| C-03 | Sign-then-encrypt order (signature hidden by encryption) | `tamper.resign` | `tests/tamper.bats`, `xc` source | not yet |
| C-04 | Padding to fixed buckets: 1 KiB, 4 KiB, 16 KiB, 64 KiB | `correctness.padding` | `tests/correctness.bats`, `xc` source | not yet |
| C-05 | Replay protection: 128-bit ID, timestamp, fingerprints, expiry | `tamper.replay` | `tests/tamper.bats`, `xc` source | not yet |
| C-06 | Replay cache rejects repeats | `tamper.replay` | `tests/tamper.bats`, `xc` source | not yet |
| C-07 | Offline by design — no network calls at runtime | `hygiene.network` | `tests/hygiene.bats`, CI logs | not yet |
| C-08 | CI runs full suite under `unshare -rn` | `hygiene.network` | `.github/workflows/ci.yml` | not yet |
| C-09 | Sender authentication on every message | `tamper.resign` | `tests/tamper.bats` | not yet |
| C-10 | Length hiding via padding buckets | `correctness.padding` | `tests/correctness.bats` | not yet |
| C-11 | Forward secrecy via optional prekeys (`xc prekeys`) | `prekeys.test` | `tests/prekeys.bats` (planned) | not yet |
| C-12 | One-time prekeys deleted after read | `prekeys.test` | `tests/prekeys.bats` (planned) | not yet |
| C-13 | `xc doctor` checks tools, versions, permissions, network, history, platform | `doctor.test` | `tests/doctor.bats` (planned) | not yet |
| C-14 | `xc selftest` runs end-to-end with throwaway keys | `selftest.test` | `tests/selftest.bats` (planned) | not yet |
| C-15 | Menu: numbered choices, plain words, <40 chars | `ui.menu` | `tests/ui.bats` (planned) | not yet |
| C-16 | Errors in plain words, no crypto internals | `ui.errors` | `tests/ui.bats` (planned) | not yet |
| C-17 | Colors with text labels, respects NO_COLOR | `ui.colors` | `tests/ui.bats` (planned) | not yet |
| C-18 | Install verifies SHA256SUMS + signature | `install.test` | `scripts/install.sh` | not yet |
| C-19 | Uninstall keeps keys by default, --purge with typed confirmation | `uninstall.test` | `scripts/uninstall.sh` | not yet |
| C-20 | No "unhackable", "guaranteed", "CIA-level" claims anywhere | `claims.no_hype` | README, SECURITY.md | not yet |
| C-21 | Honest limitations stated: no audit, no forward secrecy (default), device compromise | `claims.limitations` | SECURITY.md, README | not yet |
| C-22 | Signed releases with minisign, SHA256SUMS, SBOM, evidence bundle | `release.sign` | `scripts/release.sh` (planned) | not yet |
| C-23 | Pinned GitHub Actions (commit SHAs) | `supply.pinned` | `.github/workflows/*.yml` | not yet |
| C-24 | Reproducible tarball with rebuild instructions | `release.repro` | `scripts/reproducible-check.sh` (planned) | not yet |
| C-25 | Scorecard ≥8, Best Practices badge | `supply.scorecard` | `.github/workflows/scorecard.yml` (planned) | not yet |

*Status: "not yet" = not implemented yet; will update to "verified" when test + evidence exist.*