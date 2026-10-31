# Standards Mapping — X Messenger Terminal

Each entry links to the real document and marks exactly what is and is not claimed.

## Cryptographic Primitives

| Primitive | Standard | Implementation | Status |
|-----------|----------|----------------|--------|
| ChaCha20-Poly1305 | RFC 8439 | `age` (internal) | ✅ Used |
| X25519 | RFC 7748 | `age` (internal) | ✅ Used |
| Ed25519 | RFC 8032 | `ssh-keygen -Y sign/verify` | ✅ Used |
| scrypt | RFC 7914 | `age -p` (passphrase mode) | ✅ Used |
| HKDF | RFC 5869 | `age` (internal) | ✅ Used |
| AES-256-GCM | NIST SP 800-38D | Not directly used (via `age`) | N/A |

**Not claimed:** FIPS 140 validated, Common Criteria certified. These require paid accredited labs.

## Process Standards

| Standard | Mapping | Status |
|----------|---------|--------|
| OWASP ASVS 4.0 | Relevant sections in `docs/ASVS_MAPPING.md` (planned) | Partial |
| OWASP MASVS (Mobile) | Android/Termux: camera-only, no backup, no network, FLAG_SECURE | ✅ Strong |
| NIST SSDF (SP 800-218) | PO.1, PO.3, PW.4, PW.6, PW.7, RV.1, RV.2 | Partial |
| SLSA Build Levels | Level 1 (provenance via GitHub attestations); Level 2 planned | Level 1 |
| CWE Top 25 Review | CWE-79 (XSS): N/A (terminal); CWE-22: path validation; CWE-312: encryption at rest; CWE-319: no network | ✅ Addressed |

## Compliance Notes

- **Not GDPR/CCPA certified** — no personal data collected
- **Not HIPAA validated** — not a medical device
- **Not SOC 2 audited** — no audit performed
- **Not evaluated for any government classification** — no agency resistance claimed

## Version References

- `age` v1.x (X25519 + ChaCha20-Poly1305, BSD-3-Clause)
- OpenSSH 9.x (Ed25519, OpenSSH license)
- qrencode 4.x (GPL-2.0)
- zbar 0.23+ (GPL-2.0)
- bash 5.x (GPL-3.0)
- bats 1.x (MIT)