<!-- SPDX-License-Identifier: MIT -->
# Standards Mapping — X Messenger Terminal

This document maps X Messenger Terminal to relevant security standards and frameworks.
Each entry states exactly what is and is not claimed.

## Cryptographic Primitives

| Primitive | Standard | Implementation | Status |
|---|---|---|---|
| ChaCha20-Poly1305 | RFC 8439 | Not used (uses AES-GCM) | N/A |
| AES-256-GCM | FIPS 197, NIST SP 800-38D | WebCrypto `AES-GCM` | ✅ Used in XM1/XM1S/XMV1 |
| X25519 | RFC 7748 | Go `crypto/ecdh` (v2 core) | ✅ v2 key exchange |
| Ed25519 | RFC 8032 | tweetnacl (JS), Go `crypto/ed25519` (v2) | ✅ XM1S signing, v2 identities |
| ML-KEM-1024 | FIPS 203 | Go `crypto/mlkem` (v2 core) | ✅ v2 post-quantum KEM |
| PBKDF2-SHA256 | RFC 8018 | WebCrypto `PBKDF2` (600k iterations) | ✅ XM1/XM1S/XMV1 key derivation |
| HKDF-SHA384 | RFC 5869 | Go `crypto/hkdf` (v2 core) | ✅ v2 ratchet |
| scrypt | RFC 7914 | Not used (uses PBKDF2) | N/A |

**Not claimed:** FIPS 140 validated, Common Criteria certified. These require paid accredited labs.

## Process Standards

| Standard | Mapping | Status |
|---|---|---|
| OWASP ASVS 4.0 | Relevant sections mapped in `docs/ASVS_MAPPING.md` (planned) | Partial |
| OWASP MASVS (Mobile) | Android: camera-only, no backup, no network, FLAG_SECURE | ✅ Strong |
| NIST SSDF (SP 800-218) | PO.1, PO.3, PW.4, PW.6, PW.7, RV.1, RV.2 | Partial |
| SLSA Build Levels | Level 1 (provenance via GitHub attestations); Level 2 planned | Level 1 |
| CWE Top 25 Review | CWE-79 (XSS): CSP + no innerHTML; CWE-22: path validation; CWE-312: encryption at rest; CWE-319: TLS 1.2+ | ✅ Addressed |

## Compliance Notes

- **Not GDPR/CCPA certified** — no personal data collected
- **Not HIPAA validated** — not a medical device
- **Not SOC 2 audited** — no audit performed
- **Not evaluated for any government classification** — no agency resistance claimed

## Version References

- AES-GCM: NIST SP 800-38D (2007)
- X25519: RFC 7748 (2016)
- Ed25519: RFC 8032 (2017)
- ML-KEM: FIPS 203 (2024)
- PBKDF2: RFC 8018 (2017)
- HKDF: RFC 5869 (2010)
- WebCrypto API: W3C Recommendation
- tweetnacl: MIT licensed, public domain algorithms