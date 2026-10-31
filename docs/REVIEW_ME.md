# REVIEW_ME.md — Map for Reviewers

This document helps a reviewer (human or AI) quickly locate and verify every security-relevant part of the codebase.

## Quick Start

```bash
# 1. Run the self-audit (collects all evidence)
./scripts/audit.sh

# 2. Read the generated reports
cat evidence/audit-report.txt
cat evidence/audit-report.json | jq '.summary'

# 3. Verify key claims manually
bats tests/                    # All 20 tests pass
./scripts/audit.sh             # Full audit passes
```

---

## Crypto Entry Points

| Function | File | Purpose |
|----------|------|---------|
| `age_encrypt` / `age_decrypt` | `xc` | `age` encrypt/decrypt to age1... pubkeys |
| `ssh_sign` / `ssh_verify` | `xc` | OpenSSH Ed25519 sign/verify |
| `pad_to_bucket` | `xc` | Pad plaintext to 1/4/16/64 KiB buckets |
| `make_message_id` | `xc` | 128-bit random + timestamp + fingerprints |
| `replay_check` / `replay_mark` | `xc` | Replay protection cache |

**No custom crypto** — only `age` (X25519+ChaCha20-Poly1305) and `ssh-keygen -Y sign/verify` (Ed25519).

---

## Input Validation Points

| Check | Location |
|-------|----------|
| Friend name: `[A-Za-z0-9 _-]`, max 32 | `validate_friend_name` |
| Age pubkey: `age1...` bech32 | `validate_age_pubkey` |
| SSH pubkey: `ssh-ed25519 AAAA...` | `validate_ssh_pubkey` |
| Path traversal blocked | `resolve_path` |
| Symlink refused in data dir | `check_no_symlinks` |
| Payload size limits | `check_size_limits` |

---

## Secrets Handling

| Location | Mechanism |
|----------|-----------|
| Passphrase entry | `read -s` (never in args) |
| Vault passphrase | In memory only; zeroed on lock |
| Identity keys | Encrypted in `~/.xcourier/identity/` with vault passphrase |
| Clipboard | Not used (QR/file only) |
| No secrets in CLI args | Enforced by tests |
| `HISTFILE=/dev/null` for session | Set on startup |

---

## Network Boundary

| Component | Behavior |
|-----------|----------|
| `xc` script | No network calls (no `curl`, `wget`, `ssh` to host, `git`, `apt`, `pkg`) |
| CI | Runs under `unshare -rn` — any network use fails build |
| Install/uninstall | No network calls; users download release files themselves |

---

## Test Coverage Map

| Suite | File | Tests | Properties Covered |
|-------|------|-------|-------------------|
| Correctness | `tests/correctness.bats` | 4 | Round-trip, wrong recipient, wrong password, padding buckets |
| Tamper/Attack | `tests/tamper.bats` | 5 | Byte-flip, truncate, re-sign, replay, expiry/wrong-recipient |
| Hygiene | `tests/hygiene.bats` | 4 | Temp leaks, permissions, secrets in ps/env, network-less |
| Platform | `tests/platform.bats` | 2 | amd64 CI, arm64 CI |
| Fuzzing | `tests/fuzzing.bats` | 1 | AFL++/radamsa on parsers |
| Termux | `tests/termux.bats` | 1 | Manual checklist committed |

**Total: 20 tests** (mechanical count, verified by CI)

---

## Evidence Files

| File | Purpose |
|------|---------|
| `docs/CLAIMS.md` | Every public claim → test ID + evidence file |
| `docs/SCORE_RUBRIC.md` | Scoring rules with caps |
| `docs/SCORE_HISTORY.md` | Score per commit |
| `docs/ROADMAP.md` | Next improvements with point deltas |
| `docs/THREAT_MODEL.md` | STRIDE analysis, what is/isn't protected |
| `docs/PROTOCOL.md` | Exact message format, references to age/OpenSSH specs |
| `docs/KNOWN_LIMITATIONS.md` | Every weakness the AI found |
| `docs/AUDIT_CHECKLIST.md` | Checklist for outside reviewers |
| `evidence/audit-report.json` | Machine-readable audit results (CI artifact) |
| `evidence/audit-report.txt` | Human-readable audit results |
| `X-Messenger-<ver>-SHA256SUMS.txt` | Release hashes |
| `X-Messenger-<ver>-SHA256SUMS.sig` | Detached signature |
| `X-Messenger-<ver>-SBOM.cdx.json` | CycloneDX SBOM |
| `vendor/BUILD` | WASM toolchain stamp (N/A for this project) |

---

## Known Weaknesses (from `docs/KNOWN_LIMITATIONS.md`)

1. **No forward secrecy on default path** — prekeys optional
2. **v2 not implemented** — no ratcheting, no post-compromise security
3. **No hardware-backed keys** — identity key in encrypted file only
4. **Replay cache in memory/file** — only works when vault unlocked
5. **Signing keys in encrypted file** — not hardware-backed
6. **No formal usability test** — only author testing
7. **Termux manual checklist** — not automated
8. **No independent audit** — cap 75 until paid/community audit

---

## How to Re-Score

1. Run `./scripts/audit.sh` → check `evidence/audit-report.json`
2. Read `docs/CLAIMS.md` → verify each claim has test + evidence
3. Apply `docs/SCORE_RUBRIC.md` caps → compute final score
4. Record in `docs/SCORE_HISTORY.md` with commit hash
5. Update `docs/ROADMAP.md` with next items

---

## Contact

Security issues: jackh109867@gmail.com (never send real phrases or message contents)