# SSH keys — backup and restore

**This directory contains DOCS only. Never commit private keys to git.**
A `.gitignore` is in place to make sure of that.

## Backup (do this regularly on your working machine)

See [`../ssh-keys-backup-NOW.md`](../ssh-keys-backup-NOW.md) for the urgent first-time setup.

Habit:
1. Whenever you generate a new SSH key (`ssh-keygen -t ed25519 -C "you@email"`), re-do the backup.
2. The backup is `ssh-backup.7z`, AES-256 encrypted, password from your Proton Pass vault, stored on Proton Drive.

## Restore on a fresh install

1. Sign in to Proton Drive in the browser (or via the Proton Drive desktop app once it's installed).
2. Download `ssh-backup.7z` to `Downloads`.
3. Right-click → 7-Zip → Extract → enter password.
4. Move the contents into `%USERPROFILE%\.ssh\`:

   ```powershell
   $sshDir = "$env:USERPROFILE\.ssh"
   New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
   Move-Item "$env:USERPROFILE\Downloads\.ssh\*" $sshDir -Force
   ```

5. **Fix permissions** — Windows OpenSSH refuses to use keys that "anyone" can read:

   ```powershell
   # Lock down the .ssh directory and private keys
   icacls "$env:USERPROFILE\.ssh" /inheritance:r /grant "$($env:USERNAME):(OI)(CI)F" /T
   ```

6. **Add keys to ssh-agent** so you don't enter the passphrase every time:

   ```powershell
   # Start the OpenSSH ssh-agent service (one-time)
   Get-Service ssh-agent | Set-Service -StartupType Automatic
   Start-Service ssh-agent

   # Add your key
   ssh-add "$env:USERPROFILE\.ssh\id_ed25519"
   ```

7. **Test:**

   ```powershell
   ssh -T git@github.com
   ```

   Expected: `Hi <your-username>! You've successfully authenticated…`

## In WSL2

WSL has its own filesystem. You can either:

**Option A: re-use Windows keys** (simplest):
```bash
# In your WSL home
mkdir -p ~/.ssh
cp /mnt/c/Users/<YouOnWindows>/.ssh/id_ed25519* ~/.ssh/
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
```

**Option B: separate keys for WSL** (cleaner if you want to revoke independently). Generate `ssh-keygen -t ed25519` in WSL, add the new pubkey to GitHub etc.

## Don't commit

The `.gitignore` in this folder excludes everything except `README.md`. Don't override it.
