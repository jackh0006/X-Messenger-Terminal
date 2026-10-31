<!-- SPDX-License-Identifier: MIT -->
# CLAIMS.md — Every public claim linked to test and evidence

| Claim ID | Exact Claim | Test ID(s) | Evidence File | Status |
|---|---|---|---|---|
| C-01 | Genuinely offline (CAMERA only, no INTERNET) | input.android_offline | android/app/src/main/AndroidManifest.xml, .github/workflows/strict-boundary.yml | verified |
| C-02 | Loopback-only GUI by default (127.0.0.1) | platform.loopback_default | server.js, bin/cipherlink | verified |
| C-03 | AES-256-GCM + PBKDF2-SHA256 600k iterations | crypto.iterations, crypto.roundtrip.* | core.js | verified |
| C-04 | Fresh salt+nonce per seal | crypto.padding_buckets, crypto.tamper_byteflip | core.js | verified |
| C-05 | Tamper-evident: any byte flip fails | crypto.tamper_byteflip, crypto.tamper_truncate | core.js, test/crypto.test.js | verified |
| C-06 | Phrase never in QR/envelope | crypto.wrong_phrase_rejected | core.js, app.js | verified |
| C-07 | Fixed padding buckets hide length | crypto.padding_buckets | core.js | verified |
| C-08 | No plaintext persisted (only sealed vault + labels) | hygiene.no_secrets_in_ps, hygiene.plaintext_never_persists | app.js, test/offline.test.js | verified |
| C-09 | Sender authentication via Ed25519 (XM1S) | crypto.xm1s_sign_verify | core.js, app.js | verified |
| C-10 | Replay protection (seen envelope rejected) | crypto.replay_protection | core.js, app.js | verified |
| C-11 | Forward secrecy via v2 ratchet (experimental) | adv.forward_secrecy_v2 | core/ratchet.go, core/store.go | partial |
| C-12 | Version lockstep across 6 files | platform.version_lockstep | package.json, core.js, android/app/build.gradle, packaging/debian/DEBIAN/control, index.html, server.js | verified |
| C-13 | Signed releases (minisign/ssh-keygen) | supply.signed_releases | scripts/release.sh | verified |
| C-14 | SBOM generated (CycloneDX) | supply.sbom_generated | scripts/release.sh | verified |
| C-15 | Reproducible build check | supply.reproducible_build | scripts/reproducible-check.sh | verified |
| C-16 | OpenSSF Scorecard configured | supply.scorecard_configured | .github/workflows/scorecard.yml | verified |
| C-17 | Pinned GitHub Actions (commit SHAs) | supply.pinned_actions | .github/workflows/*.yml | verified |
| C-18 | No hype claims (unhackable, CIA-grade, etc.) | claims.no_hype | README.md, SECURITY.md, app.js | verified |
| C-19 | Honest limitations stated | claims.honest_limitations | SECURITY.md | verified |
| C-20 | Verifiable, not guaranteed marketing | claims.verifiable_not_guaranteed | README.md | verified |

*Status: verified = test passes and evidence exists; partial = implemented but experimental/unaudited; not yet = planned but not implemented.*