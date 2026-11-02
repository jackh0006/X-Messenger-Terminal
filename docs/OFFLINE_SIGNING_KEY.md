# Offline Signing Key Generation — RELEASE MANAGER ONLY

This document describes how to generate the **offline Ed25519 signing key** used to sign `SHA256SUMS` for releases. The private key **never enters the repo or CI**.

## Generate the offline key (run on an air-gapped machine)

```bash
# 1. Generate the Ed25519 keypair (no passphrase for the signing key itself;
#    the release artifacts are public anyway; the key's security is physical isolation)
ssh-keygen -t ed25519 -N "" -f release_signing_key -C "x-messenger-release-$(date +%Y-%m-%d)"

# 2. The public key goes into the repo's allowed_signers file:
#    (edit allowed_signers to replace the placeholder)
#    Format: <pattern> <namespace> <public-key>
#    For releases: "* x-messenger-release <public-key>"
cat release_signing_key.pub | awk '{print "* x-messenger-release " $2}' > allowed_signers.new
mv allowed_signers.new allowed_signers

# 3. Verify the allowed_signers format is correct:
ssh-keygen -Y verify -f allowed_signers -n x-messenger-release -s SHA256SUMS.sig < SHA256SUMS

# 4. The PRIVATE key (release_signing_key) is stored OFFLINE.
#    - Write it to a USB drive and lock it in a safe
#    - Or use a hardware security module (HSM) / YubiKey with ssh-agent
#    - NEVER put it in the repo, CI secrets, or any online system
#    - NEVER type the private key into any internet-connected machine

# 5. The public key fingerprint for README (users verify this out-of-band):
ssh-keygen -lf release_signing_key.pub
# Output: 256 SHA256:abc123... user@host (ED25519)
# Copy the SHA256:... part to README.md's "Fingerprint" section
```

## Signing a release (offline machine)

```bash
# 1. Copy SHA256SUMS to the offline machine
# 2. Sign it:
ssh-keygen -Y sign -f release_signing_key -n x-messenger-release < SHA256SUMS > SHA256SUMS.sig

# 3. Copy SHA256SUMS.sig back to the release directory
# 4. The signature is verified by users via: ssh-keygen -Y verify -f allowed_signers ...
```

## Key rotation

If the offline key is ever compromised or needs rotation:

1. Generate a new offline keypair as above
2. Update `allowed_signers` in the repo (commit the new file)
3. Publish the new fingerprint in README.md
4. Tag the commit that updates allowed_signers as the "key rotation" commit
5. All future releases use the new key; old signatures remain verifiable with the old allowed_signers (git history)

## Security notes

- The signing key is an **Ed25519 SSH key** (same algorithm as user identities in xc)
- Namespace `x-messenger-release` scopes the key to this project only
- `allowed_signers` uses `*` pattern meaning "any identity" — the namespace restricts it
- The private key file `release_signing_key` is the **only secret** — it must remain offline
- No passphrase on the signing key is fine because it's physically isolated (like a CA root key)
- If you prefer a passphrase on the signing key, add `-N "your-passphrase"` to ssh-keygen -Y sign