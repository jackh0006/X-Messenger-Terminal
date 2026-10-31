# AUDIT_CHECKLIST.md — For Outside Reviewers

This checklist helps an outside reviewer verify the security claims of X Messenger Terminal. Check each item and note findings.

## Cryptographic Design

- [ ] Only `age` (X25519 + ChaCha20-Poly1305) and `ssh-keygen -Y sign/verify` (Ed25519) are used
- [ ] No custom ciphers, KDFs, key exchanges, or file formats for crypto
- [ ] Sign-then-encrypt order (signature hidden by encryption)
- [ ] Padding to fixed buckets: 1 KiB, 4 KiB, 16 KiB, 64 KiB with length header
- [ ] Replay protection: 128-bit message ID, UTC timestamp, sender/recipient fingerprints, optional expiry
- [ ] Replay cache: local list of seen ID hashes, rejects repeats
- [ ] Randomness: OS CSPRNG only (`/dev/urandom` via `age`/`ssh-keygen`)

## Message Container (`.courier`)

- [ ] ASCII-armored `age` output
- [ ] Plain header line `X-COURIER/1` outside encryption only
- [ ] Nothing identifying outside encryption

## Commands

- [ ] `xc init` — creates age key + SSH signing key, encrypted with passphrase, refuses weak passphrases (min 12 chars or 5-word generated)
- [ ] `xc id` — shows age pubkey + SSH pubkey + 6-word fingerprint, QR display
- [ ] `xc add` — paste/file/QR import, shows fingerprint, asks for in-person confirmation, stores unverified until confirmed
- [ ] `xc verify` — re-checks fingerprint, marks verified
- [ ] `xc send` — types/pipes message, produces `message.courier` + optional QR, refuses unverified friends without `--force`
- [ ] `xc read` — decrypts, verifies signature, checks replay/expiry, shows sender, wipes temp data
- [ ] `xc qr-send` / `xc qr-read` — split/assemble via `qrencode`/`zbarimg`, numbered frames
- [ ] `xc prekeys` — generates 50 one-time age keypairs, signed bundle, private halves encrypted
- [ ] `xc rotate` — new keys, optional keep old, notify contacts
- [ ] `xc wipe` — secure remove with confirmation, flash storage note
- [ ] `xc doctor` — checks tools, versions, permissions, network, history, platform
- [ ] `xc selftest` — end-to-end test with throwaway keys

## UI

- [ ] Menu: numbered choices, plain words ("friend", "secret message", "ID", "password")
- [ ] One question per screen, safe defaults
- [ ] Errors: plain words, no stack traces or crypto internals
- [ ] Colors only when terminal supports, text labels (OK/WARNING/STOP), respects `NO_COLOR`
- [ ] Confirmation before destructive actions, Ctrl+C exits safely
- [ ] First run: guided walk-through
- [ ] Lines under 40 chars for small phone screens

## Security Requirements

- [ ] `set -eu` (pipefail where available), quoted variables, no `eval`, no unvalidated `$IFS`
- [ ] Strict input validation: friend names, age pubkeys, SSH pubkeys, file paths
- [ ] `umask 077`, `~/.xcourier` mode 0700, key files 0600, `xc doctor` fails if wrong
- [ ] Plaintext only in memory/pipes or private tmpfs (`/dev/shm` Linux, `$TMPDIR` Termux)
- [ ] Passwords via `read -s`, never in command-line args
- [ ] No logging of message content, names, keys; `HISTFILE=/dev/null` advised
- [ ] Traps `EXIT INT TERM HUP` to remove temp files
- [ ] No network calls at runtime (no `curl`, `wget`, `ssh` to host, `git`, `apt`, `pkg`)
- [ ] CI runs under `unshare -rn`; canary test confirms network blocked

## Supply Chain

- [ ] Documented tested versions of `age`, `openssh`, `qrencode`, `zbar`
- [ ] `INSTALL.md` with `apt`/`pkg` commands and verification instructions
- [ ] Termux: install from F-Droid, mention Termux:API only if needed

## Platform Notes

- [ ] Android: disable cloud backup, block screenshots, device encrypted, offline keyboard
- [ ] Linux: full-disk encryption, no swap or encrypted swap, lock screen, no clipboard managers

## Tests (all pass in CI)

- [ ] Round trip: sizes 0, 1, 1 KiB, 10 KiB, 60 KiB, unicode, binary
- [ ] Wrong recipient cannot decrypt
- [ ] Wrong password cannot unlock identity
- [ ] Padding: ciphertext sizes only in defined buckets
- [ ] Byte-flip every position: always fails, never outputs wrong text
- [ ] Truncate at every length: fails cleanly
- [ ] Re-sign with different key: reports "not from your friend"
- [ ] Replay same message twice: second rejected
- [ ] Expired/wrong-recipient rejected
- [ ] Malformed IDs, huge input, empty, `../`, newline, `;`, `$()`, backticks: safely rejected
- [ ] Symlink in data dir: refused
- [ ] No temp files after success/failure/Ctrl+C
- [ ] Permissions correct on all created files/dirs
- [ ] No secrets in `ps` or env (test with watcher)
- [ ] Full suite passes under `unshare -rn`; canary confirms network blocked
- [ ] `shellcheck -S style` clean, `shfmt`, semgrep rules for shell
- [ ] Ubuntu LTS amd64 CI runner
- [ ] arm64 CI runner (GitHub `ubuntu-24.04-arm` or QEMU)
- [ ] Real Termux arm64: manual checklist committed (device, Android version, Termux version, date)
- [ ] Fuzzing: AFL++/radamsa ≥1h per parser in CI, 24h before v1.0; corpus + crashes committed

## Evidence System

- [ ] `docs/CLAIMS.md`: every README claim → test ID + evidence file
- [ ] `scripts/audit.sh`: runs all checks, writes `evidence/audit-report.json` + `.txt`
- [ ] `evidence/`: CI uploads test logs, shellcheck output, fuzzing summary, Scorecard JSON, SHA256SUMS, SBOM, dep versions
- [ ] Release assets include evidence bundle
- [ ] `docs/SCORE_RUBRIC.md`: rubric with caps (failing test ≤50, no audit ≤75, no Termux test ≤70, unsigned ≤65, claim w/o evidence ≤60)
- [ ] `docs/SCORE_HISTORY.md`: dated table with commit hash, changes, reviewer
- [ ] `docs/REVIEW_ME.md`: map for reviewers (crypto calls, input validation, temp data, secrets)
- [ ] `docs/ROADMAP.md`: ranked improvements with point deltas

## Releases

- [ ] Signed tags, pinned Actions (commit SHAs), reproducible tarball
- [ ] SHA256SUMS, detached signature (minisign), SBOM, evidence bundle
- [ ] Public signing key + fingerprint in README and second channel
- [ ] Rebuild instructions to compare hashes
- [ ] Topics: offline, age, termux, encryption, cli
- [ ] Honest README with "Status: not independently audited" banner
- [ ] Outside review before "stable" claim; audit linked if done

---

## Reviewer Notes

| Area | Findings | Severity |
|------|----------|----------|
|      |          |          |

---

**Reviewer:** _________________  
**Date:** _________________  
**Commit reviewed:** _________________