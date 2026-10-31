# INSTALL.md — Installation & Verification

## Requirements

| Platform | Dependencies | Install Command |
|----------|--------------|-----------------|
| **Linux (amd64)** | `age`, `openssh`, `qrencode`, `zbar`, `bash` | `apt update && apt install -y age openssh-client qrencode zbar` |
| **Termux (arm64)** | `age`, `openssh`, `qrencode`, `zbar`, `bash` | `pkg install age openssh qrencode zbar` |

**Note:** On Linux, `age` may need `universe` repo (`apt install software-properties-common && add-apt-repository universe`). On older distros, build `age` from source (see below).

---

## Download & Verify

### 1. Download Release Files

From the [releases page](https://github.com/jackh0006/X-Messenger-Terminal/releases):

- `x-messenger-<version>.tar.gz` — source + prebuilt `xc` script
- `SHA256SUMS` — checksums
- `SHA256SUMS.sig` — minisign signature
- `SBOM.cdx.json` — CycloneDX SBOM
- `evidence/audit-report.json` — self-audit results

### 2. Verify Minisign Signature

The minisign public key is in the README and below:

```
RWQ... (to be generated at first release)
```

```bash
# Verify SHA256SUMS signature
minisign -Vm SHA256SUMS -P <pubkey-from-readme>
```

### 3. Verify Checksums

```bash
sha256sum -c SHA256SUMS 2>&1 | grep OK
# Should show: x-messenger-<version>.tar.gz: OK
```

### 4. (Optional) Rebuild and Compare Hashes

```bash
./scripts/reproducible-check.sh <version>
```

---

## Install

### Quick Install (Linux / Termux)

```bash
# 1. Extract
tar -xzf x-messenger-<version>.tar.gz
cd x-messenger-<version>

# 2. Run installer (checks deps, verifies checksums/signature, installs)
./scripts/install.sh

# 3. Verify
xc selftest
xc doctor
```

### Installer Options

```bash
./scripts/install.sh --help
# Options:
#   --dry-run          Show what would be done without doing it
#   --prefix DIR       Install directory (default: ~/.local/bin on Linux, $PREFIX/bin on Termux)
#   --skip-verify      Skip SHA256SUMS + signature verification (NOT RECOMMENDED)
```

### What the Installer Does

1. **Detects platform** (Linux amd64 / Termux arm64)
2. **Checks dependencies** — prints exact `apt`/`pkg` command if missing
3. **Verifies SHA256SUMS** against downloaded tarball
4. **Verifies minisign signature** on SHA256SUMS
5. **Installs `xc`** to `~/.local/bin` (Linux) or `$PREFIX/bin` (Termux)
6. **Sets umask 077** for data directories
7. **Creates desktop entry** (Linux) / app shortcut (Termux:API if available)

---

## Manual Install (if installer fails)

```bash
# 1. Verify tarball (steps 2-3 above)
# 2. Extract
tar -xzf x-messenger-<version>.tar.gz

# 2. Copy xc to PATH
mkdir -p ~/.local/bin
cp x-messenger-<version>/xc ~/.local/bin/xc
chmod 700 ~/.local/bin/xc

# 3. Ensure ~/.local/bin in PATH
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# 4. Verify
xc selftest
```

---

## Build `age` from Source (if not in repo)

```bash
# Linux
git clone https://github.com/FiloSottile/age
cd age
make
sudo cp age age-keygen /usr/local/bin/

# Verify
age -version
```

---

## Uninstall

```bash
# Removes xc binary only (keeps keys/contacts)
./scripts/uninstall.sh

# Purge everything (keys, contacts, replay cache) — requires typed confirmation
./scripts/uninstall.sh --purge

# Dry run (show what would be removed)
./scripts/uninstall.sh --dry-run
```

---

## Platform Notes

### Linux (amd64)
- Install to `~/.local/bin` (respects XDG)
- Desktop entry in `~/.local/share/applications/`
- `FLAG_SECURE` not applicable (terminal)

### Termux (Android arm64)
- Install to `$PREFIX/bin` (usually `/data/data/com.termux/files/usr/bin/`)
- Requires Termux from **F-Droid** (Play Store build outdated)
- `qrencode` / `zbar` provide QR encode/decode
- Camera permission needed for `xc qr-read`
- `FLAG_SECURE` set via `termux:api` if available (blocks screenshots)

### Build `age` on Termux
```bash
pkg install golang
git clone https://github.com/FiloSottile/age
cd age && go build -o $PREFIX/bin/age ./cmd/age
go build -o $PREFIX/bin/age-keygen ./cmd/age-keygen
```

---

## Verify Installation

```bash
# Self-test (end-to-end with throwaway keys)
xc selftest

# Doctor (checks tools, versions, permissions, network, history, platform)
xc doctor

# Show version
xc --version
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `age: command not found` | Install per platform table above |
| `qrencode: not found` | `apt install qrencode` / `pkg install qrencode` |
| `zbarimg: not found` | `apt install zbar` / `pkg install zbar` |
| Signature verification fails | Ensure minisign public key matches README; re-download files |
| `xc: permission denied` | `chmod 700 ~/.local/bin/xc` |
| `~/.../xc` not in PATH | Add `export PATH="$HOME/.local/bin:$PATH"` to shell RC |

---

## Security Reminder

- **Never** run `curl ... | sh` — download files yourself, verify, then run installer
- **Verify** SHA256SUMS and signature before installing
- **Keep** your vault passphrase secure — lost passphrase = permanent data loss
- **Verify** fingerprints in person before trusting a contact