<!-- SPDX-License-Identifier: MIT -->
# Android Uninstall Guide

X Messenger Terminal for Android is a **CAMERA-only** app with **no INTERNET permission**.
There is no server, no account, no cloud sync — everything lives on your device.

## Standard uninstall (keeps no data behind)

1. Long-press the X Messenger Terminal app icon
2. Tap **Uninstall** → **OK**
3. Done. No data leaves your device.

## Complete wipe (if you want to be absolutely sure)

If you used the **vault** (locked history) or created a **device identity** for message signing, those are stored in the app's private data directory. Standard uninstall removes them, but you can also:

1. Settings → Apps → X Messenger Terminal → **Storage**
2. Tap **Clear data** (this wipes vault, identity, contacts, settings, replay cache)
3. Then **Uninstall**

## What gets removed

| Data | Location | Removed by |
|---|---|---|
| Vault history (XMV1 envelopes) | App private storage (`/data/data/com.jackh0006.xmessenger/...`) | Uninstall + Clear data |
| Device identity (Ed25519 signing key) | Same | Uninstall + Clear data |
| Local contacts (profiles) | Same | Uninstall + Clear data |
| Settings / preferences | Same | Uninstall + Clear data |
| Replay protection cache | Same | Uninstall + Clear data |
| Session messages (unlocked plaintext) | In-memory only | Gone on close/background |

## No cloud, no backup

- `android:allowBackup="false"` in manifest → Google Backup never stores your data
- No `INTERNET` permission → nothing can be uploaded anywhere
- No account → nothing to "log out" of

**Your sealed messages (`.xmsg` files, QR codes) are just files you copied/shared yourself — they live wherever you put them, not in the app.**

## Verifying clean removal

After uninstall + clear data:
```bash
# On device (via Termux or ADB)
ls /data/data/com.jackh0006.xmessenger 2>/dev/null || echo "Clean — directory gone"
```

If the directory is gone, everything is removed. There are no hidden locations.