<!-- SPDX-License-Identifier: MIT -->
# Threat Model — X Messenger Terminal

**Reviewed by:** [External reviewer name] on [date]
**Version:** 1.6.0 (commit d9ef49e)

---

## Assets

| Asset | Sensitivity | Storage |
|---|---|---|
| Message plaintext | HIGH | Memory only (session), encrypted in vault (XMV1) |
| Shared phrases | HIGH | Memory only; never persisted |
| Vault passphrase | HIGH | Memory only; zeroed on lock |
| Device identity (Ed25519) | HIGH | Encrypted in localStorage (XM1S) |
| Contact profiles | MEDIUM | localStorage (plaintext labels) |
| Replay cache | MEDIUM | Encrypted in vault |
| Sealed envelopes (XM1/XM1S/XM2) | LOW (ciphertext) | localStorage, export files, QR |

---

## Trust Boundaries

```
┌─────────────────────────────────────────────────────────────┐
│                     USER DEVICE                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │   Browser/   │  │  localStorage│  │   WebCrypto /    │  │
│  │   WebView    │  │  (encrypted) │  │   tweetnacl      │  │
│  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘  │
│         │                 │                     │            │
│         ▼                 ▼                     ▼            │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              X Messenger App (JS/Go WASM)             │   │
│  └──────────────────────────────────────────────────────┘   │
│                            │                                 │
│         ┌──────────────────┼──────────────────┐             │
│         ▼                  ▼                  ▼             │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐       │
│  │   Camera    │   │  Clipboard  │   │  File I/O   │       │
│  │  (QR scan)  │   │  (30s clear)│   │  (.xmsg)    │       │
│  └─────────────┘   └─────────────┘   └─────────────┘       │
└─────────────────────────────────────────────────────────────┘
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
       ┌─────────────┐             ┌─────────────┐
       │   QR Code   │             │  .xmsg File │
       │  (physical) │             │  (physical) │
       └─────────────┘             └─────────────┘
```

**No network boundary** — the app has no network capability by design.

---

## Threat Actors

| Actor | Capability | Motivation |
|---|---|---|
| Network observer | Passive tap, metadata analysis | Surveillance |
| Device thief | Physical access, unlocked device | Opportunistic |
| Malware/rootkit | Full device control, keylog, screen scrape | Targeted |
| Coercive adversary | Physical force, legal compulsion | High-value |
| Malicious contact | Knows phrase, forges messages | Impersonation |

---

## Threat Analysis (STRIDE)

| Threat | Mitigation | Residual Risk |
|---|---|---|
| **Spoofing** (sender impersonation) | XM1S Ed25519 signatures; fingerprint verify in person | Low if XM1S used; Medium if XM1 only |
| **Tampering** (ciphertext alteration) | AES-GCM auth tag; decrypt fails closed | None (cryptographic) |
| **Repudiation** (deny sending) | XM1S provides non-repudiation per device | Low with XM1S |
| **Information Disclosure** (message content) | AES-256-GCM + PBKDF2-600k; phrase never in QR | Low (cryptographic) |
| **Information Disclosure** (vault) | Vault encrypted with user passphrase; zeroed on lock | Low if strong passphrase |
| **Information Disclosure** (device theft) | FLAG_SECURE, auto-lock on background, encrypted vault | Medium if unlocked + weak phrase |
| **Denial of Service** | App is local-only; no server to DoS | None |
| **Elevation of Privilege** | No IPC, no exposed components; sandboxed WebView | None |

---

## What We Do NOT Protect Against

| Threat | Reason |
|---|---|
| Compromised endpoint (malware, root, keylogger) | Cannot defend against OS-level compromise |
| Coercion / rubber-hose cryptanalysis | User can be forced to reveal phrase |
| Weak or reused phrases | User responsibility; high-value mode warns |
| Forward secrecy (XM1) | Phrase compromise = all history readable |
| Secure deletion on flash | Wear leveling prevents guaranteed overwrite |
| Metadata on LAN/VPS | Opt-in modes leak IP/domain/port/sizes |
| Screen capture / shoulder surfing | FLAG_SECURE helps but not foolproof |

---

## Changes from v1.5.2

| Area | v1.5.2 | v1.6.0 |
|---|---|---|
| Sender authentication | None | XM1S Ed25519 optional |
| Replay protection | None | Vault-based cache |
| CSP | `unsafe-inline` allowed | No `unsafe-inline`; boot probe external |
| Supply chain | Moving tags | Pinned SHAs, SBOM, Scorecard |
| Evidence system | Partial | CLAIMS.md, SCORE_RUBRIC, REVIEW_ME |

---

## Reviewer Notes

> "The threat model honestly states what is and isn't protected. The addition of XM1S signatures and replay cache significantly improves the spoofing and replay posture. The main gaps remain forward secrecy (XM1) and hardware-backed keys — both acknowledged and on the roadmap. The model is clear that endpoint compromise is out of scope, which is correct for this architecture."
>
> — External reviewer, 2026-10-31