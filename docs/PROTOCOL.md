# PROTOCOL.md — Exact Message Format and Flow

References: `age` spec (age-encryption.org), OpenSSH `ssh-keygen -Y sign/verify` man page.

---

## Message Container (`.courier`)

```
X-COURIER/1
<ASCII-armored age output>
```

- The header `X-COURIER/1` is **outside** encryption.
- Everything after is ASCII-armored `age` output (as produced by `age -e`).
- Decrypt with `age -d` (or `age -d -i identity` for file).

---

## Signing Flow (Sign-then-Encrypt)

```
Plaintext message
       │
       ▼
┌──────────────────┐
│  Pad to bucket   │  (1/4/16/64 KiB + 4-byte length header)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Sign (Ed25519)  │  ssh-keygen -Y sign -f identity.key -n "x-courier"
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Encrypt (age)   │  age -e -r recipient.age1pubkey
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  ASCII-armor     │  base64 with line breaks
└────────┬─────────┘
         │
         ▼
X-COURIER/1
<armored output>
```

---

## Signed Bundle Format (inside age encryption)

The plaintext passed to `age -e` is a JSON document:

```json
{
  "v": 1,
  "msg_id": "a1b2c3d4e5f6...",     // 128-bit random (32 hex chars)
  "timestamp": "2026-11-01T12:34:56Z",
  "sender_fp": "aa:bb:cc:dd:ee:ff", // 6-byte fingerprint (hex, colon-separated)
  "recipient_fp": "11:22:33:44:55:66",
  "expiry": "2026-11-02T12:34:56Z", // optional, ISO8601
  "payload": "base64(padded_plaintext)",
  "sig": "base64(ed25519_signature)" // signature over canonical JSON without "sig" field
}
```

### Canonicalization for Signing

The signature covers the JSON document **without** the `sig` field, with:
- Keys sorted lexicographically
- No whitespace (compact)
- UTF-8 encoding

```bash
# Example canonicalization (pseudocode)
canonical=$(jq -c -S 'del(.sig)' <<< "$bundle")
sig=$(echo -n "$canonical" | ssh-keygen -Y sign -f sender.identity -n "x-courier")
```

---

## Replay Protection

### Message ID

- 128-bit cryptographically random (32 hex chars)
- Generated per message via `head -c16 /dev/urandom | xxd -p -c 32`

### Replay Cache

- Receiver stores SHA-256(message_id) in `~/.xcourier/replay/`
- Cache format: one hash per line (hex)
- On `xc read`: if hash exists → reject with "replay detected"
- On success: append hash to cache
- Cache persists across sessions (encrypted with vault passphrase if enabled)

### Expiry

- Optional `expiry` field in signed bundle (ISO8601 UTC)
- If present and past → reject with "message expired"
- Max age policy: configurable (default 30 days)

---

## Padding (Length Hiding)

Plaintext is padded **before signing** to fixed buckets:

| Bucket | Plaintext Max | Padded Size |
|--------|---------------|-------------|
| 1 KiB  | 1020 bytes    | 1024 bytes  |
| 4 KiB  | 4092 bytes    | 4096 bytes  |
| 16 KiB | 16380 bytes   | 16384 bytes |
| 64 KiB | 65532 bytes   | 65536 bytes |

- 4-byte big-endian length prefix at offset 0
- Random padding bytes (from `/dev/urandom`) fill to bucket boundary
- Padding is part of the signed payload (so tampering detected)

---

## Prekeys (Optional Forward Secrecy)

### `xc prekeys` (Receiver)

```
xc prekeys 50
```

1. Generates N one-time age keypairs: `age-keygen` → `age1pub`, `age1priv`
2. Creates signed bundle of **public** halves:
   ```json
   {
     "v": 1,
     "count": 50,
     "keys": ["age1pub1...", "age1pub2...", ...],
     "sig": "ed25519_signature"
   }
   ```
3. Private halves encrypted individually with vault passphrase, stored in `~/.xcourier/prekeys/NNN.age1priv.enc`
4. Signed bundle shared in person (QR or USB)

### `xc send` (Sender, with prekeys)

1. Imports friend's prekey bundle, verifies signature
2. Selects first unused prekey (tracks used in `~/.xcourier/prekeys/used/`)
3. Encrypts to that one-time `age1pub` (no long-term recipient key used)
4. Marks prekey used

### `xc read` (Receiver, with prekey)

1. Decrypts with corresponding one-time private key
2. **Immediately deletes** that private key file (`shred` if available)
3. If no prekey matches → falls back to long-term identity key (with warning)

### Exhaustion / Rotation

- `xc prekeys` warns when < 5 remain
- `xc prekeys` with no args shows count remaining
- `xc rotate` generates new identity keys + new prekey bundle

---

## QR Frames (`xc qr-send` / `xc qr-read`)

### Framing (for messages > QR capacity)

```
X-COURIER/1
<armored chunk 1 of N>
---
X-COURIER/1
<armored chunk 2 of N>
---
...
```

- Uses `qrencode` with error correction level L
- `qrencode -l L -o frame.png`
- Decoder: `zbarimg` or equivalent; reassembles by `---` delimiter
- Numbered frames: `PART 1/3`, `PART 2/3`, etc. in metadata

---

## Key Files (on Disk)

```
~/.xcourier/
├── identity/
│   ├── age.pub              # age public key (age1...)
│   ├── age.priv.enc         # age private key, encrypted with vault passphrase
│   ├── ssh.pub              # Ed25519 public key (ssh-ed25519 AAAA...)
│   └── ssh.priv.enc         # Ed25519 private key, encrypted with vault passphrase
├── vault.passphrase.enc     # (optional) vault passphrase hash for auto-lock
├── contacts/
│   ├── alice.json           # { name, age_pub, ssh_pub, fingerprint, verified: true }
│   └── bob.json             # { name, age_pub, ssh_pub, fingerprint, verified: false }
├── prekeys/
│   ├── bundle.json          # friend's prekey bundle (signed)
│   ├── used/                # directory of used prekey IDs
│   └── 001.age1priv.enc     # encrypted private halves
├── replay/
│   └── seen.hashes          # one SHA-256 per line
└── vault/                   # (optional) encrypted message history
```

---

## Versioning

- Protocol version in `X-COURIER/1` header
- Signed bundle `"v": 1`
- Breaking changes → new header version