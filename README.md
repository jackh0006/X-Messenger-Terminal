# X Messenger Terminal

**Command:** `xc`  
**Status:** Development — not independently audited  
**License:** MIT

> **Honest banner:** This tool has not been independently audited.  
> It provides offline encrypted messaging with sender authentication and optional forward secrecy via prekeys.  
> A compromised device exposes everything. Fingerprints must be verified in person.

---

## What It Does

`xc` is an offline encrypted message courier for **Linux amd64** and **Termux on Android arm64**.

- **Encrypts** a message to a friend's public key using `age` (X25519 + ChaCha20-Poly1305).
- **Signs** the message with your Ed25519 identity (`ssh-keygen -Y sign`) so the recipient knows it came from you.
- **Pads** plaintext to fixed buckets (1 KiB, 4 KiB, 16 KiB, 64 KiB) to hide message length.
- **Prevents replay** with 128-bit message IDs, timestamps, and a local seen-ID cache.
- **Optional forward secrecy:** Generate one-time prekeys (`xc prekeys`), exchange in person, each message consumes one prekey, and the private half is deleted after decryption.
- **Completely offline:** No network calls at runtime. CI enforces this with `unshare -rn`.
- **Simple menu:** Numbered choices, plain words, works on a small phone screen.

---

## Non-Goals

- Live chat, groups, multi-device sync
- Protection against a compromised device
- Protection against forced unlock
- Anonymity

---

## Quick Start

```bash
# 1. Download release files (tarball, SHA256SUMS, .sig, SBOM, evidence)
# 2. Verify (see "Verify Releases" below)
# 3. Install
./scripts/install.sh

# 4. Create your identity (age key + SSH signing key, encrypted with a passphrase)
xc init

# 5. Show your ID to a friend (QR or text)
xc id

# 6. Add their ID (paste, file, or scan QR), confirm fingerprint in person
xc add alice

# 7. Send a secret message
xc send alice

# 8. Receive and read
xc read message.courier
```

---

## Verify Releases

Every release includes:
- `x-messenger-<version>.tar.gz` — source + prebuilt binary
- `SHA256SUMS` — SHA-256 checksums
- `SHA256SUMS.sig` — **SSH signature** (signed by offline Ed25519 release key)
- `SBOM.cdx.json` — CycloneDX SBOM
- `evidence/audit-report.json` — full self-audit results
- Release notes with exact verify commands

**Verification steps (using the shipped `allowed_signers` file):**

```bash
# 1. Download all files for the version (tarball, SHA256SUMS, .sig, SBOM, evidence)
# 2. Verify SHA256SUMS signature using the repo's allowed_signers file
ssh-keygen -Y verify -f allowed_signers -n x-messenger-release -s SHA256SUMS.sig < SHA256SUMS

# 3. Verify tarball checksum
sha256sum -c SHA256SUMS 2>&1 | grep OK

# 4. (Optional) Rebuild and compare hashes
./scripts/reproducible-check.sh <version>
```

**SSH signing public key (verify against second channel):**
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExamplePlaceholderKeyDoNotUseThisInProduction
```

**Fingerprint:**
```
SHA256:ExamplePlaceholderFingerprintDoNotUseThisInProduction
```

> **⚠️ PRE-RELEASE SOFTWARE** — All releases are labeled **pre-release** (e.g., `v0.x.y-pre`) and **never** "stable". This tool has not been independently audited. Use at your own risk.

**Offline signing key procedure:** [`docs/OFFLINE_SIGNING_KEY.md`](docs/OFFLINE_SIGNING_KEY.md)

---

## Commands

| Command | Description |
|---------|-------------|
| `xc` | Open simple menu |
| `xc init` | Create identity (age + SSH signing key, passphrase-encrypted) |
| `xc id` | Show your public ID (age pubkey + SSH pubkey + 6-word fingerprint) |
| `xc add <friend>` | Add a friend's ID (paste/file/QR), confirm fingerprint |
| `xc verify <friend>` | Re-check fingerprint, mark verified |
| `xc send <friend>` | Write message → produce `message.courier` + optional QR |
| `xc read <file\|->` | Decrypt, verify signature, check replay/expiry, wipe temp |
| `xc qr-send` / `xc qr-read` | Split/assemble large messages via QR frames |
| `xc prekeys` | Generate one-time prekeys for forward secrecy |
| `xc rotate` | New encrypted keys behind a typed `ROTATE` confirmation; fingerprint changes, contacts must re-verify; `--keep-old` shelves old key files |
| `xc wipe` | Remove keys/contacts/state (with confirmation) |
| `xc doctor` | Check tools, permissions, network, history, platform |
| `xc selftest` | End-to-end encrypt/sign/decrypt/verify with throwaway keys |

---

## Install / Uninstall

```bash
# Download release tarball, SHA256SUMS, .sig, SBOM, evidence
# Verify (see "Verify Releases" above — uses ssh-keygen + allowed_signers)

# Install (checks deps, verifies checksums/signature via ssh-keygen -Y verify,
# installs to ~/.local/bin or $PREFIX/bin)
./scripts/install.sh

# Uninstall (keeps keys/contacts by default)
./scripts/uninstall.sh

# Purge everything (requires typed confirmation)
./scripts/uninstall.sh --purge
```

**Platform support:**
- Linux amd64: `apt install age openssh qrencode zbar`
- Termux arm64: `pkg install age openssh qrencode zbar`

---

## Verification

> **Don't trust us — run the audit yourself. Verifiable, minimal, open, offline.**

```bash
# Full self-audit (runs all tests, checks, fuzzing, network-less CI)
./scripts/audit.sh

# Output: evidence/audit-report.json (machine-readable) and .txt (human)
```

All claims in this README have a corresponding row in `docs/CLAIMS.md` linking to a test and evidence file.

---

## Roadmap & Score

| Stage | Target | Est. Score |
|-------|--------|------------|
| 0 | Legacy migration, honest README | ~50 |
| 1 | Core crypto + commands + menu | ~58 |
| 2 | Full test suite + audit.sh | ~62 |
| 3 | Prekeys + hardware keys | ~66 |
| 4 | Supply chain + Scorecard | ~70 |
| 5 | Real-device tests + usability | ~73-75 (cap) |
| 6 | Independent audit | ~85-90 |

**Cap without audit: 75/100.** With audit + fixes: ~85-90.  
100 is not possible (FIPS/CC require paid labs).

See `docs/SCORE_HISTORY.md`, `docs/SCORE_RUBRIC.md`, `docs/ROADMAP.md`.

---

## Comparison (Evidence-Based)

| Need | X Messenger Terminal | Signal | WhatsApp | Telegram (Secret) | Telegram | plain age/GPG |
|------|---------------------|--------|----------|-------------------|----------|---------------|
| Zero bars / offline | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ |
| No account / SIM | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ |
| No server copy | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Sender auth | ✅ (signatures) | ✅ | ✅ | ✅ | ❌ | ❌ (age) |
| Replay protection | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| Forward secrecy | ⚠️ prekeys (opt-in) | ✅ | ✅ | ✅ | ❌ | ❌ |
| Independent audit | ❌ | ✅ | ✅ | ⚠️ | ❌ | ❌ |
| Verifiable builds | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Small auditable size | ✅ (~600 LOC) | ❌ | ❌ | ❌ | ❌ | ✅ |

*Evidence links in `docs/CLAIMS.md`. Expect Signal to win on audit, forward secrecy, polish. X Messenger Terminal wins on offline, zero metadata, auditable size.*

---

## License

MIT — see `LICENSE`.  
Third-party tools: `age` (BSD-3), `openssh` (OpenSSH), `qrencode` (GPL-2), `zbar` (GPL-2).

---

## Contact

Security: jackh109867@gmail.com (never send real phrases or message contents)  
Source: https://github.com/jackh0006/X-Messenger-Terminal