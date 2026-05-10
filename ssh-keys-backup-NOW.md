# 🚨 SSH keys backup — do this NOW, not on recovery day

Your SSH keys live in `%USERPROFILE%\.ssh\` (typically `C:\Users\<you>\.ssh\`).
The files matter:

- `id_ed25519` / `id_rsa` — **private keys, irreplaceable**
- `id_ed25519.pub` / `id_rsa.pub` — public keys, replaceable
- `config` — host shortcuts, useful but rebuildable
- `known_hosts` — server fingerprints, regenerated on use

If your drive dies right now and these are nowhere else, you lose access to anything those keys are the only authentication for. New keys to GitHub is fine. Servers where you set up `authorized_keys` and forgot the password are not.

## 5-minute fix

1. **Zip the .ssh folder:**

   ```powershell
   Compress-Archive -Path "$env:USERPROFILE\.ssh" -DestinationPath "$env:USERPROFILE\Desktop\ssh-backup.zip"
   ```

2. **Encrypt the zip with 7-Zip and a strong password:**
   - Right-click `ssh-backup.zip` → 7-Zip → Add to archive
   - Archive format: **7z**
   - Encryption method: **AES-256**
   - Check **Encrypt file names**
   - Set a strong password (save it in your password manager)
   - Output: `ssh-backup.7z`

3. **Upload the encrypted archive to Proton Drive.**

4. **Delete the unencrypted `ssh-backup.zip`** from your desktop.

5. **Verify** you can extract it: download from Proton Drive, double-click, enter password, see the files. If yes, you're done.

## How to restore on a fresh install

See [`ssh/README.md`](./ssh/README.md).

## Habit

Re-do this whenever you generate a new key. SSH keys aren't rotated often, so this is rarely. But each new server you add a key to is one more thing you'd lose.
