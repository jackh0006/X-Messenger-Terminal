# Security Policy and Threat Model

**Version:** 0.1.0 (pre-release)  
**Status:** Not independently audited  
**Report security issues privately to:** jackh109867@gmail.com

---

## What X Messenger Terminal Protects

With uncompromised endpoints, verified fingerprints, and correct tool versions:

- **Message confidentiality:** `age` (X25519 + ChaCha20-Poly1305) encrypts to the recipient's public key.
- **Sender authentication:** OpenSSH Ed25519 signatures (`ssh-keygen -Y sign/verify`) on every message. Sign-then-encrypt hides the signer from outsiders.
- **Replay protection:** 128-bit message ID, UTC timestamp, sender/recipient fingerprints, optional expiry. Receiver tracks seen ID hashes and rejects repeats.
- **Length hiding:** Plaintext padded to fixed buckets (1 KiB, 4 KiB, 16 KiB, 64 KiB) before signing.
- **Offline by design:** No network calls at runtime. CI enforces this with `unshare -rn`.
- **Verifiable builds:** Pinned Actions (commit SHAs), signed releases (minisign), SHA256SUMS, SBOM, reproducible tarball.

---

## What X Messenger Terminal Does NOT Protect

| Threat | Why |
|--------|-----|
| Compromised device (malware, root, screen capture, keylogger) | No software can defend against a fully compromised endpoint |
| Coercion / forced unlock | No plausible deniability; the vault passphrase decrypts everything |
| Forward secrecy (default) | Prekeys are optional; without them, a seized device with the identity key decrypts all past messages |
| Secure deletion on flash storage | Wear leveling prevents guaranteed overwrite; `xc wipe` is best effort |
| Metadata on prekey exchange | QR/USB transfer reveals timing and size |
| Anonymity | Fingerprints identify the sender; no onion routing or mixnet |
| Live chat / groups / multi-device sync | Out of scope — this is a message courier, not a chat app |

---

## Supported Versions

| Version | Status |
|---------|--------|
| 0.x (pre-1.0) | Development — no guarantees |
| 1.0+ (when tagged) | First stable release after audit |

---

## Security Requirements for Users

- **Verify fingerprints in person** before trusting a contact (6-word mnemonic from `xc id`).
- **Use a strong vault passphrase** (min 12 chars or 5-word generated).
- **Enable prekeys** (`xc prekeys`) for forward secrecy.
- **Keep device encrypted** with a strong lock screen; disable cloud backup of Termux data.
- **Do not use cloud-synced keyboards**; they may log passphrases.

---

## Reporting

Email `jackh109867@gmail.com` with version, impact, and reproduction steps.  
Do not send private keys, real message contents, recovery phrases, or tokens.  
Do not open public issues for vulnerabilities.

---

## Honest Claims

- Uses `age` (X25519 + ChaCha20-Poly1305) and OpenSSH Ed25519 signatures.
- Offline by design — no network calls at runtime.
- Tested against tampering, replay, and malformed inputs.
- Builds are reproducible and signed.

- **NOT independently audited** (unless a future release states otherwise with a link).
- **NO forward secrecy** without enabling prekeys.
- A hacked or seized device exposes everything on it.
- Key fingerprints **must be verified in person**.

Do not claim "unhackable", "military-grade", "CIA-level", "guaranteed", or "proven secure".