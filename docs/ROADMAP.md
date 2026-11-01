# Roadmap — X Messenger Terminal

Each item tagged with rubric criterion and expected point delta.

## Stage 0 — Legacy Migration (COMPLETE)
| Item | Criterion | Δ Points |
|------|-----------|----------|
| Tag legacy, honest README, repo structure | — | — |

---

## Stage 1 — Core Crypto & Commands (Target ~58)
| Item | Criterion | Δ Points | Effort |
|------|-----------|----------|--------|
| `xc` script with menu + 11 commands | Ease of use | +10 | High |
| `age` encrypt/decrypt to age1... pubkeys | Standard crypto | +8 | High |
| `ssh-keygen -Y sign/verify` Ed25519 signatures | Sender auth | +10 | High |
| Sign-then-encrypt order | Standard crypto | +2 | Medium |
| Padding buckets (1/4/16/64 KiB) | Standard crypto | +3 | Medium |
| Replay cache (message ID + timestamp + fingerprint) | Sender auth + replay | +5 | Medium |
| Length header in signed bundle | Standard crypto | +1 | Medium |
| Identity mgmt: `xc init`, `xc id`, `xc add`, `xc verify` | All | +10 | High |
| Contact fingerprint verification (6-word) | Sender auth | +2 | Medium |
| `xc send` / `xc read` with QR frames | Ease of use | +5 | High |
| `xc doctor` / `xc selftest` | Endpoint hardening | +3 | Medium |

---

## Stage 2 — Test Suite & Hardening (Target ~62)
| Item | Criterion | Δ Points | Effort |
|------|-----------|----------|--------|
| 20 bats tests (correctness, tamper, hygiene, platform, fuzzing) | All | +4 | High |
| `scripts/audit.sh` — runs all checks, writes evidence/audit-report.json | All | +3 | High |
| CI: `unshare -rn` network-less tests, pinned Actions (commit SHAs) | Supply chain | +2 | Medium |
| shellcheck -S style clean, shfmt, semgrep | Endpoint hardening | +1 | Medium |
| `docs/CLAIMS.md` — every README claim → test ID + evidence file | Evidence | +2 | Medium |
| `docs/AUDIT_CHECKLIST.md` for outside reviewers | Evidence | +1 | Low |

---

## Stage 3 — Forward Secrecy & Hardware Keys (Target ~66)
| Item | Criterion | Δ Points | Effort |
|------|-----------|----------|--------|
| `xc prekeys` — 50 one-time age keypairs, signed bundle, delete-after-read | Forward secrecy | +10 | High |
| `xc send` uses one prekey per message, marks used | Forward secrecy | +3 | Medium |
| `xc read` deletes private half after decrypt | Forward secrecy | +2 | Medium |
| `xc rotate` — new keys, optional keep old, notify contacts | Standard crypto | +2 | Medium |
| `xc wipe` — secure remove with confirmation, flash storage note | Endpoint hardening | +2 | Medium |
| Optional `age-plugin-yubikey` support (Linux only) | Endpoint hardening | +2 | High |
| Document flash deletion is best effort | Honest claims | +1 | Low |

---

## Stage 4 — Supply Chain & Reproducibility (Target ~70)
| Item | Criterion | Δ Points | Effort |
|------|-----------|----------|--------|
| Pinned GitHub Actions (full commit SHAs) | Supply chain | +2 | Medium |
| Signed releases (ssh-keygen -Y verify), SHA256SUMS.sig, signed tags | Supply chain | +3 | High |
| SBOM (CycloneDX), reproducible tarball, rebuild script | Supply chain | +3 | High |
| SLSA provenance via GitHub attestations | Supply chain | +2 | High |
| Scorecard ≥ 8, Best Practices badge | Supply chain | +2 | Medium |
| `docs/STANDARDS.md` — RFCs, OWASP ASVS/MASVS, CWE Top 25, NIST SSDF, SLSA | Evidence | +2 | Medium |
| `docs/THREAT_MODEL.md` reviewed by outsider | Supply chain | +1 | Low |

---

## Stage 5 — Real-Device Tests & Docs (Target ~73-75)
| Item | Criterion | Δ Points | Effort |
|------|-----------|----------|--------|
| `docs/TERMUX_MANUAL_TEST.md` completed on real arm64 device | Platforms | +3 | High |
| Usability test with 3 non-technical users | Ease of use | +3 | High |
| All docs complete: PROTOCOL.md, KNOWN_LIMITATIONS.md, AUDIT_CHECKLIST.md, REVIEW_ME.md | Evidence | +2 | Medium |
| Fuzzing: AFL++/radamsa ≥1h per parser in CI, 24h before v1.0 | Tamper/attack | +2 | High |

---

## Stage 6 — External Audit (Target ~85-90)
| Item | Criterion | Δ Points | Effort |
|------|-----------|----------|--------|
| Publish design for community review | Independent audit | — | Medium |
| Commission independent audit | Independent audit | +20 | High |
| Fix all findings, re-score, link audit report | Independent audit | — | High |

---

## Notes
- **Cap without audit: 75/100** (rubric cap).
- **Realistic post-audit ceiling: 85-90** for offline, small, high-value messages.
- **100 is not possible** — FIPS 140 / Common Criteria require paid accredited labs.
- Every stage: run `scripts/audit.sh`, update `docs/SCORE_HISTORY.md`, commit.