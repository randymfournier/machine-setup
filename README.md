# machine-setup

Reproducible Windows 11 recovery and dev-machine setup as code.

This repo is a setup framework for rebuilding a Windows 11 development machine after a wipe/reinstall. It supports:

- an internet launcher
- a local USB driver-rescue launcher
- a setup console
- a manifest-driven task engine
- modular setup tasks
- recovery and maintenance tools
- logs, state, retry, and resume support

## Launch Paths

Fresh install with internet:

```powershell
irm https://raw.githubusercontent.com/randymfournier/machine-setup/main/quickstart.ps1 | iex
```

USB driver-rescue path:

```text
D:\_START_HERE.cmd
```

Replace `D:` with the USB drive letter.

Modern Windows should not be expected to automatically run commands from USB drives. This toolkit does not use fake AutoRun behavior.

## Recovery Flow

1. Install Windows 11.
2. If Wi-Fi/touchpad works, run the internet launcher.
3. If Wi-Fi/touchpad does not work, run `_START_HERE.cmd` from the recovery USB.
4. The USB launcher installs saved recovery drivers only.
5. Once networking is available, it hands off to the internet launcher so the latest GitHub repo is used.
6. The setup console waits for you to choose a mode and confirm before running anything.
7. Review the final summary and reboot manually only if Windows asks.

## Setup Modes

The main console provides:

1. Automatic recommended setup
2. Custom setup checklist
3. Minimal recovery setup
4. Apps only
5. Dev environment only
6. Recovery / maintenance tools
7. Logs and setup state
8. Read instructions
9. Quit

Nothing installs until a mode is selected and confirmed.

## What The Engine Does

The task engine reads `setup.json`, resolves dependencies, adds prerequisites, writes logs/state, continues after non-fatal failures, blocks dependent tasks when prerequisites fail, and supports retry/resume.

Task statuses:

- `NotStarted`
- `Ready`
- `Running`
- `Succeeded`
- `Skipped`
- `Failed`
- `Blocked`
- `RequiresReboot`

Generated runtime files:

```text
logs/yyyy-mm-dd_hhmmss/
state/setup-state.json
```

## Recovery USB Toolkit

From a working machine, run `setup.ps1` and choose `Recovery / maintenance tools`.

Tools include:

- export Wi-Fi/touchpad recovery drivers
- cache offline recovery installers
- prepare/update recovery USB
- validate recovery USB
- rebuild/slipstream Windows install USB scaffold
- diagnostics
- read instructions

The recovery USB prepare tool writes both:

- `_START_HERE.cmd`
- `Start-MachineSetup.cmd` as a compatibility alias

## Repo Layout

```text
machine-setup/
  quickstart.ps1                 internet launcher
  quickstart-local.ps1           USB driver-rescue launcher
  _START_HERE.cmd                preferred USB driver-rescue launcher
  setup.ps1                      main setup console
  setup.json                     central manifest
  core/                          engine, UI, detection, logging, state, native helpers
  tasks/                         modular setup tasks
  tools/                         maintenance/recovery tools
  assets/                        future offline assets layout
  drivers/                       legacy driver export/install helpers and local exports
  installers/                    optional local installer cache
  windows/                       legacy Windows tweak/update/debloat scripts
  dev/                           legacy dev setup scripts and VS Code extension list
  wsl/                           WSL setup scripts
  shell/                         PowerShell, oh-my-posh, Terminal config
  git/                           Git config templates
  usb/                           USB docs and legacy prepare helper
  docs/                          future framework docs
  legacy/                        pre-framework wizard and setup plan
  state/                         generated setup state, not committed
  logs/                          generated setup logs, not committed
```

## Manual Finishing Touches

After setup completes, reboot manually if a restart is pending, then review:

- `docs/accounts-checklist.md`
- `docs/manual-steps.md`
- `docs/ssh/README.md`
- `docs/modding/ue4ss-icarus.md`

## Not Stored Here

This repo intentionally does not store:

- SSH private keys
- credentials, API keys, `.env` files
- project source code
- personal data
- exported driver packages
- cached installer binaries

This repo is the recipe, not the food.
