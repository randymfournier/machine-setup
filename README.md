# machine-setup

Reproducible Windows 11 dev environment as code.
If this machine dies, follow this README to be back at work in ~45 minutes.

## Recovery flow

### Phase 0 — Maintain the recovery toolkit / bootable USB

This repo is now both:

- the **fresh install setup tool**
- the **recovery USB maintenance toolkit**

Before a wipe, or whenever the USB gets stale, run the setup wizard on the working machine and choose:

```text
Toolkit / recovery USB utilities
```

From there you can:

- export the selected Wi-Fi/touchpad drivers
- cache offline recovery assets like App Installer/winget and Visual Studio Build Tools
- prepare/update the recovery USB launch pack
- read the USB rebuild/slipstream instructions

The first command after a fresh install is still only this:

```powershell
irm https://raw.githubusercontent.com/randymfournier/machine-setup/main/quickstart.ps1 | iex
```

But if the fresh Windows install has no Wi-Fi/touchpad yet, use the local USB launcher:

```text
D:\Start-MachineSetup.cmd
```

Replace `D:` with the USB drive letter.

#### About USB launch

Modern Windows should not be expected to automatically run commands from a USB drive just because it was inserted. This toolkit does not rely on AutoRun. The reliable local path is `Start-MachineSetup.cmd` after Windows is installed.

#### Rebuild/slipstream the Windows USB

Use [`slipstream-iso.md`](./slipstream-iso.md) from the wizard/toolkit or from the USB. It explains how to build a Windows 11 USB with current cumulative updates baked in so recovery is faster.

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

Replace `D:` with the USB drive letter. This runs `quickstart-local.ps1`, installs any exported Wi-Fi/touchpad drivers it finds, copies the repo to `C:\machine-setup`, and then launches the setup wizard with `-NoProfile` and execution-policy bypass. If the wizard is missing, it falls back to `bootstrap.ps1`.

Before the next wipe, create that driver folder from the working machine with:

```powershell
cd C:\machine-setup
.\drivers\export-selected-drivers.ps1
```

Copy the generated `drivers\exported-selected-yyyy-mm-dd` folder to the recovery USB along with this repo.

### Phase 2 — Run the setup wizard

Open **PowerShell as Administrator** and paste one line:

```powershell
irm https://raw.githubusercontent.com/randymfournier/machine-setup/main/quickstart.ps1 | iex
```

`quickstart.ps1` sets the process execution policy bypass itself and launches the keyboard-driven setup wizard with `-NoProfile`, so you do not have to type the policy command separately.

The setup tool opens a menu and waits. Nothing installs until you choose a mode and confirm. Press **Enter** for the normal recommended setup, or choose a specific mode.

Wizard modes include:

- **Recommended full setup** — normal rebuild path; runs the standard checklist with your confirmation.
- **Minimal recovery setup** — drivers, winget repair, and Visual Studio/MSVC linker.
- **Dev toolchains only** — Visual Studio, Node/fnm, Rust, Tauri, VS Code extensions, dotfiles, WSL.
- **Apps only** — winget repair and winget apps.
- **Custom step selection** — toggle individual steps and run only what you want.
- **Toolkit / recovery USB utilities** — export drivers, cache recovery assets, update the USB files, and read instructions.

Keyboard controls during guided steps:

- **Enter** — run/continue to the next step.
- **S** — skip the current step.
- **R** — retry a failed step.
- **L** — show recent log lines after a failure.
- **Q** — quit safely.

This will:

- Install saved local Wi-Fi/touchpad recovery drivers first if an exported driver folder is present on USB/local disk
- Repair/check winget before relying on it
- Install winget packages one-by-one with timeouts, not one giant fragile batch
- Install/modify Visual Studio Build Tools directly if needed, using a local cached bootstrapper first when present
- Install Git if needed
- Clone this repo to `C:\machine-setup`
- Hand off to `setup-wizard.ps1` by default
- Wait for you to choose Recommended, Minimal Recovery, Dev Toolchains, Apps Only, Custom, or Toolkit mode
- Run one step at a time after you press Enter
- Let you skip, retry, continue after failure, or view recent log lines
- Never reboot automatically during the wizard; Windows Update only marks a reboot as pending
- Keep `bootstrap.ps1` available as the non-interactive fallback runner
- Write logs and JSON summaries to `C:\machine-setup\logs\`

**To also strip Windows bloat (Teams, Xbox, Bing, etc.) during setup:** use Custom mode in the wizard and select the Debloat step, or run bootstrap manually after the clone:

```powershell
cd C:\machine-setup
.\bootstrap.ps1 -IncludeDebloat
```

Read `windows\debloat.ps1` first to confirm what it removes — it leaves Edge alone (WebView2 is needed for Tauri).

Run for further tweaking:

`irm https://christitus.com/win | iex`

### Phase 3 — Manual finishing touches

After the setup wizard completes, reboot manually if Windows says a restart is pending, then see:

- [`accounts-checklist.md`](./accounts-checklist.md) — services to log back into
- [`manual-steps.md`](./manual-steps.md) — Wi-Fi fallback, M365, BIOS, drivers, taskbar extras
- [`ssh/README.md`](./ssh/README.md) — restore SSH keys from your encrypted Proton Drive backup
- [`modding/ue4ss-icarus.md`](./modding/ue4ss-icarus.md) — Icarus modding tools

If anything failed, check the latest files in:

```text
C:\machine-setup\logs\
```

The wizard and bootstrap are designed to finish the checklist and report failures at the end instead of stopping at the first error.

## Repo layout

```
machine-setup/
├── README.md                    ← you are here
├── quickstart.ps1               ← the irm | iex internet entry point
├── quickstart-local.ps1         ← local USB entry point for no-Wi-Fi installs
├── Start-MachineSetup.cmd       ← double-click/typeable wrapper for quickstart-local.ps1
├── setup-wizard.ps1             ← auto/wizard/toolkit console launcher
├── setup-plan.json              ← modular step list consumed by the wizard
├── bootstrap.ps1                ← resilient non-interactive orchestrator and wizard step runner
├── winget-packages.json         ← all Windows apps
├── ssh-keys-backup-NOW.md       ← do this TODAY, not on recovery day
├── accounts-checklist.md        ← post-restore login checklist
├── manual-steps.md              ← M365, BIOS, drivers, etc.
├── slipstream-iso.md            ← build pre-updated install USBs
├── windows/                     ← Windows tweaks + update/debloat scripts
├── dev/                         ← language toolchains, VS C++ workload, VS Code config
├── drivers/                     ← selected Wi-Fi/touchpad driver export + restore helpers
├── installers/                  ← optional local winget/Visual Studio bootstrappers for USB recovery
├── usb/                         ← recovery USB launcher/prep docs and utilities
├── cache-recovery-assets.ps1    ← downloads optional offline bootstrappers before a wipe
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


## Recovery USB toolkit

Run `setup-wizard.ps1` on a working machine and choose `Toolkit / recovery USB utilities` to handle maintenance without memorizing commands. The toolkit can export drivers, cache offline assets, prepare/update the USB files, and display the slipstream instructions.

## Things that are deliberately NOT in this repo

- **SSH private keys** — encrypted backup on Proton Drive only.
- **Application credentials, API keys, .env files** — these live in your password manager.
- **Project source code** — already in your other GitHub repos.
- **Personal data** — your file backup system covers this.
- **Exported driver packages** — keep these on your recovery USB; `drivers/exported-*` is gitignored.
- **Cached installer binaries** — keep `installers/*.exe` and `installers/*.msixbundle` on USB/local disk; they are gitignored.

This repo is the *recipe*, not the *food*.
