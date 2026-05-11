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
3. Connect to Wi-Fi if Windows can see your adapter.
   - If the fresh ISO has no Wi-Fi/touchpad yet, use the USB fallback in Phase 2A first. The internet `irm` command cannot work until some network path exists.


### Phase 2A — No Wi-Fi / no touchpad fallback

If the fresh Windows install cannot connect to Wi-Fi, the internet `irm` command cannot download anything yet. Use the local USB copy instead:

```text
D:\Start-MachineSetup.cmd
```

Replace `D:` with the USB drive letter. This runs `quickstart-local.ps1`, installs any exported Wi-Fi/touchpad drivers it finds, copies the repo to `C:\machine-setup`, and then launches `bootstrap.ps1` with `-NoProfile` and execution-policy bypass.

Before the next wipe, create that driver folder from the working machine with:

```powershell
cd C:\machine-setup
.\drivers\export-selected-drivers.ps1
```

Copy the generated `drivers\exported-selected-yyyy-mm-dd` folder to the recovery USB along with this repo.

### Phase 2 — Run the bootstrap

Open **PowerShell as Administrator** and paste one line:

```powershell
irm https://raw.githubusercontent.com/randymfournier/machine-setup/main/quickstart.ps1 | iex
```

`quickstart.ps1` sets the process execution policy bypass itself and launches the main bootstrap with `-NoProfile`, so you do not have to type the policy command separately.

This will:

- Install saved local Wi-Fi/touchpad recovery drivers first if an exported driver folder is present on USB/local disk
- Repair/check winget before relying on it
- Install/modify Visual Studio Build Tools directly if needed, so broken winget sources do not block the MSVC linker
- Install Git if needed
- Clone this repo to `C:\machine-setup`
- Hand off to `bootstrap.ps1`
- Show step progress
- Continue past recoverable failures
- Write a full log and JSON summary to `C:\machine-setup\logs\`

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
- [`manual-steps.md`](./manual-steps.md) — Wi-Fi fallback, M365, BIOS, drivers, taskbar extras
- [`ssh/README.md`](./ssh/README.md) — restore SSH keys from your encrypted Proton Drive backup
- [`modding/ue4ss-icarus.md`](./modding/ue4ss-icarus.md) — Icarus modding tools

If anything failed, check the latest files in:

```text
C:\machine-setup\logs\
```

The bootstrap is designed to finish the checklist and report failures at the end instead of stopping at the first error.

## Repo layout

```
machine-setup/
├── README.md                    ← you are here
├── quickstart.ps1               ← the irm | iex internet entry point
├── quickstart-local.ps1         ← local USB entry point for no-Wi-Fi installs
├── Start-MachineSetup.cmd       ← double-click/typeable wrapper for quickstart-local.ps1
├── bootstrap.ps1                ← resilient orchestrator, run after install
├── winget-packages.json         ← all Windows apps
├── ssh-keys-backup-NOW.md       ← do this TODAY, not on recovery day
├── accounts-checklist.md        ← post-restore login checklist
├── manual-steps.md              ← M365, BIOS, drivers, etc.
├── slipstream-iso.md            ← build pre-updated install USBs
├── windows/                     ← Windows tweaks + update/debloat scripts
├── dev/                         ← language toolchains, VS C++ workload, VS Code config
├── drivers/                     ← selected Wi-Fi/touchpad driver export + restore helpers
├── shell/                       ← PowerShell profile, Starship, Terminal
├── git/                         ← .gitconfig, global gitignore
├── ssh/                         ← key restore docs (NEVER the keys)
├── wsl/                         ← Ubuntu 24.04 setup
├── logs/                        ← generated bootstrap logs, not committed
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
- **Exported driver packages** — keep these on your recovery USB; `drivers/exported-*` is gitignored.

This repo is the *recipe*, not the *food*.
