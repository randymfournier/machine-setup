# machine-setup

Reproducible Windows 11 dev environment as code.
If this machine dies, follow this README to be back at work in ~45 minutes.

## Recovery flow

### Phase 0 — Make a fresh Windows install USB

- **First time only:** download the latest Windows 11 ISO from microsoft.com and use Rufus to make a USB.
- **Every time after that:** use [`slipstream-iso.md`](./slipstream-iso.md) to build a USB with all current cumulative updates baked in. Saves 30–60 min of post-install patching.

### Phase 1 — Install Windows

1. Boot from USB, install Windows 11.
2. **Skip** the Microsoft account prompt if you can (use a local account; you can attach the MS account later for store apps). Or use one — your call.
3. Connect to Wi-Fi.

### Phase 2 — Run the bootstrap

Open **PowerShell as Administrator** and paste:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
irm https://raw.githubusercontent.com/<YOUR-GH-USERNAME>/machine-setup/main/quickstart.ps1 | iex
```

(Replace `<YOUR-GH-USERNAME>` once your repo is on GitHub.)

This will:
- Clone this repo to `C:\machine-setup`
- Hand off to `bootstrap.ps1`
- Walk you through admin prompts as needed

**To also strip Windows bloat (Teams, Xbox, Bing, etc.) during bootstrap:** after the clone, run instead:

```powershell
cd C:\machine-setup
.\bootstrap.ps1 -IncludeDebloat
```

Read `windows\debloat.ps1` first to confirm what it removes — it leaves Edge alone (WebView2 is needed for Tauri).

Run for further tweaking:

`irm https://christitus.com/win | iex`

### Phase 3 — Manual finishing touches

After `bootstrap.ps1` completes, see:
- [`accounts-checklist.md`](./accounts-checklist.md) — services to log back into
- [`manual-steps.md`](./manual-steps.md) — things scripts can't automate (M365, BIOS, drivers)
- [`ssh/README.md`](./ssh/README.md) — restore SSH keys from your encrypted Proton Drive backup
- [`modding/ue4ss-icarus.md`](./modding/ue4ss-icarus.md) — Icarus modding tools

## Repo layout

```
machine-setup/
├── README.md                    ← you are here
├── quickstart.ps1               ← the irm | iex entry point
├── bootstrap.ps1                ← orchestrator, run after install
├── winget-packages.json         ← all Windows apps
├── ssh-keys-backup-NOW.md       ← do this TODAY, not on recovery day
├── accounts-checklist.md        ← post-restore login checklist
├── manual-steps.md              ← M365, BIOS, drivers, etc.
├── slipstream-iso.md            ← build pre-updated install USBs
├── windows/                     ← Windows tweaks + update bulk-install
├── dev/                         ← language toolchains, VS Code config
├── shell/                       ← PowerShell profile, Starship, Terminal
├── git/                         ← .gitconfig, global gitignore
├── ssh/                         ← key restore docs (NEVER the keys)
├── wsl/                         ← Ubuntu 24.04 setup
└── modding/                     ← Icarus / UE4SS notes
```

## Maintenance — keep this booklet up to date

Once a month, or whenever you install something new, run this on your working machine and commit the output:

```powershell
cd C:\machine-setup
.\maintenance\snapshot.ps1   # exports current winget, vscode extensions, etc.
git add .
git commit -m "snapshot $(Get-Date -Format yyyy-MM-dd)"
git push
```

(That maintenance script is something to add later — for now, manual exports are documented in each file's header.)

## Things that are deliberately NOT in this repo

- **SSH private keys** — encrypted backup on Proton Drive only.
- **Application credentials, API keys, .env files** — these live in your password manager.
- **Project source code** — already in your other GitHub repos.
- **Personal data** — your file backup system covers this.

This repo is the *recipe*, not the *food*.
