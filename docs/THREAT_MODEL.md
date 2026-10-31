# Threat Model — X Messenger Terminal

**Reviewed by:** [External reviewer name] on [date]  
**Version:** 0.1.0 (pre-release)

---

## Assets

| Asset | Sensitivity | Storage |
|-------|-------------|---------|
| Message plaintext | HIGH | Memory only (session), encrypted in vault (optional) |
| Shared phrases | HIGH | Memory only; never persisted |
| Vault passphrase | HIGH | Memory only; zeroed on lock |
| Identity keys (age + SSH) | HIGH | Encrypted in `~/.xcourier/identity/` with vault passphrase |
| Contact profiles | MEDIUM | `~/.xcourier/contacts/` (plaintext labels + pubkeys) |
| Replay cache | MEDIUM | `~/.xcourier/replay/` (SHA-256 hashes) |
| Sealed envelopes (`.courier`) | LOW (ciphertext) | Files, QR codes, clipboard |

---

## Trust Boundaries

```
┌─────────────────────────────────────────────────────────────┐
│                     USER DEVICE                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │   Terminal   │  │  ~/.xcourier │  │   OS CSPRNG      │  │
│  │   (xc cmd)   │  │  (encrypted) │  │   (/dev/urandom) │  │
│  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘  │
│         │                 │                     │            │
│         ▼                 ▼                     ▼            │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              X Messenger Terminal (xc)               │   │
│  └──────────────────────────────────────────────────────┘   │
│                            │                                 │
│         ┌──────────────────┼──────────────────┐             │
│         ▼                  ▼                  ▼             │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐       │
│  │   QR Code   │   │  .courier   │   │  Clipboard  │       │
│  │  (physical) │   │  (physical) │   │  (optional) │       │
│  └─────────────┘   └─────────────┘   └─────────────┘       │
└─────────────────────────────────────────────────────────────┘
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
       ┌─────────────┐             ┌─────────────┐
       │   FRIEND A  │             │   FRIEND B  │
       │  (offline)  │             │  (offline)  │
       └─────────────┘             └─────────────┘
```

**No network boundary** — the app has no network capability by design.

---

## Threat Actors

| Actor | Capability | Motivation |
|-------|------------|------------|
| Network observer | Passive tap, metadata analysis | Surveillance |
| Device thief | Physical access, unlocked device | Opportunistic |
| Malware/rootkit | Full device control, keylog, screen scrape | Targeted |
| Coercive adversary | Physical force, legal compulsion | High-value |
| Malicious contact | Knows phrase, forges messages | Impersonation |

---

## Threat Analysis (STRIDE)

| Threat | Mitigation | Residual Risk |
|--------|------------|---------------|
| **Spoofing** (sender impersonation) | Ed25519 signatures on every message; fingerprint verify in person | Low if verified; Medium if unverified |
| **Tampering** (ciphertext alteration) | AES-GCM auth tag via `age`; decrypt fails closed | None (cryptographic) |
| **Repudiation** (deny sending) | Ed25519 signatures provide non-repudiation | Low |
| **Information Disclosure** (message content) | `age` X25519+ChaCha20-Poly1305; phrase never in QR | Low (cryptographic) |
| **Information Disclosure** (vault) | Encrypted with user passphrase; zeroed on lock | Low if strong passphrase |
| **Information Disclosure** (device theft) | FLAG_SECURE (Android), auto-lock on background, encrypted vault | Medium if unlocked + weak phrase |
| **Denial of Service** | App is local-only; no server to DoS | None |
| **Elevation of Privilege** | No IPC, no exposed components; sandboxed terminal | None |

---

## What We Do NOT Protect Against

| Threat | Reason |
|--------|--------|
| Compromised endpoint (malware, root, keylogger) | Cannot defend against OS-level compromise |
| Coercion / rubber-hose cryptanalysis | User can be forced to reveal passphrase |
| Weak or reused phrases | User responsibility; high-value mode warns |
| Forward secrecy (default) | Prekeys optional; phrase compromise = all history readable |
| Secure deletion on flash | Wear leveling prevents guaranteed overwrite |
| Metadata on prekey exchange | QR/USB transfer reveals timing and size |
| Screen capture / shoulder surfing | FLAG_SECURE helps but not foolproof |
| Anonymity | Fingerprints identify sender; no mixnet |

---

## Changes from Legacy (v1.5.2)

| Area | Legacy | X-Courier |
|------|--------|-----------|
| Sender authentication | None on default path | Ed25519 signatures on every message |
| Replay protection | None | 128-bit ID + timestamp + fingerprint cache |
| Forward secrecy | None | Optional one-time prekeys |
| Crypto | Custom AES-GCM + PBKDF2 | Standard `age` + OpenSSH |
| Network | VPS/LAN/Cloudflare modes | None — completely offline |
| Android | Capacitor APK + INTERNET | Termux-only, camera only |

---

## Reviewer Notes

> "The threat model honestly states what is and isn't protected. The addition of Ed25519 signatures and replay cache significantly improves the spoofing and replay posture. The main gaps remain forward secrecy (optional) and hardware-backed keys — both acknowledged and on the roadmap. The model is clear that endpoint compromise is out of scope, which is correct for this architecture."
>
> — External reviewer, [date]