# Codex Task: Rebuild machine-setup into a proper setup framework

## Project goal

This repo is a Windows 11 recovery/setup toolkit for rebuilding a dev machine after a wipe/reinstall.

The goal is to turn the current scripts into a proper modular setup console with:

- one internet launcher
- one local USB launcher
- one main setup wizard
- one task engine
- one manifest
- modular tasks
- separate tools/utilities
- logs
- state tracking
- retry/resume support

Final launch paths:

Internet path:

    irm https://raw.githubusercontent.com/randymfournier/machine-setup/main/quickstart.ps1 | iex

USB/no-network path:

    _START_HERE.cmd

Both should launch the same setup console.

## Hard rules

- Do not make the user manually run internal scripts during normal use.
- Do not auto-reboot.
- Do not start installing before the user chooses a mode and confirms.
- Do not fake USB autorun.
- Must run on fresh Windows 11 with Windows PowerShell 5.1.
- Do not require external PowerShell modules.
- Use ASCII-only console output.
- No Unicode boxes, emojis, or fancy progress bars.
- Redirect noisy native command output to logs.
- Long-running commands must show heartbeat/status output.
- Continue after non-fatal failures.
- Track task state.
- Support retry/resume.
- Every task must detect before running.
- Every task must verify after running.
- Preserve useful existing logic, but reorganize it cleanly.

## Desired structure

    machine-setup/
    ├── quickstart.ps1
    ├── quickstart-local.ps1
    ├── _START_HERE.cmd
    ├── setup.ps1
    ├── setup.json
    ├── core/
    │   ├── Setup.Engine.psm1
    │   ├── Setup.UI.psm1
    │   ├── Setup.Detect.psm1
    │   ├── Setup.Logging.psm1
    │   ├── Setup.State.psm1
    │   └── Setup.Native.psm1
    ├── tasks/
    │   ├── drivers/
    │   ├── winget/
    │   ├── git/
    │   ├── apps/
    │   ├── visualstudio/
    │   ├── toolchains/
    │   ├── powershell/
    │   ├── windows/
    │   ├── vscode/
    │   ├── wsl/
    │   └── debloat/
    ├── tools/
    │   ├── recovery-usb/
    │   ├── drivers/
    │   ├── cache/
    │   ├── slipstream/
    │   └── diagnostics/
    ├── assets/
    │   ├── drivers/
    │   ├── installers/
    │   └── packages/
    ├── docs/
    ├── state/
    └── logs/

## File roles

### quickstart.ps1

Internet launcher only.

Allowed:
- admin check
- execution-policy bypass for this process
- acquire repo
- install Git only if required to acquire repo
- unblock repo scripts
- launch setup.ps1

Not allowed:
- full setup
- app installs
- Visual Studio install
- Windows updates
- WSL
- dev toolchains
- debloat

### quickstart-local.ps1

USB/local launcher only.

Allowed:
- admin check
- execution-policy bypass for this process
- install emergency exported drivers if present
- copy repo to C:\machine-setup
- unblock repo scripts
- launch setup.ps1

### _START_HERE.cmd

Simple USB launcher for quickstart-local.ps1.

Do not create fake autorun behavior.

### setup.ps1

Main setup console/wizard.

It should show:

1. Automatic recommended setup
2. Custom setup checklist
3. Minimal recovery setup
4. Apps only
5. Dev environment only
6. Recovery / maintenance tools
7. Logs and setup state
8. Read instructions
9. Quit

Nothing should install until the user chooses and confirms.

### setup.json

Central manifest for:

- modes
- tasks
- dependencies
- labels
- descriptions
- required admin/network
- reboot behavior
- task script paths
- setup tasks vs tool tasks

No duplicated hardcoded step lists.

## Task engine

Task statuses:

- NotStarted
- Ready
- Running
- Succeeded
- Skipped
- Failed
- Blocked
- RequiresReboot

The engine must:

- resolve dependencies
- add required prerequisites automatically
- run tasks in correct order
- block dependent tasks when prerequisites fail
- continue after safe failures
- retry failed tasks
- skip selected tasks
- write logs
- write state
- show final summary

## Required setup tasks

### drivers.installRecovery

Install exported Wi-Fi/touchpad recovery drivers if present.

Known important drivers:
- MediaTek Wi-Fi
- Intel Serial IO I2C
- Intel Serial IO GPIO
- I2C HID
- HID/touchpad dependencies

### powershell.policy

Set CurrentUser execution policy to RemoteSigned so normal dev shims like npm.ps1 can run.

### winget.repair

Repair winget/App Installer where possible.

Do not rely on winget source update because it can hang.

### git.install

Install Git if missing.

Use:
1. already installed
2. cached installer
3. winget
4. direct download if available

### apps.install

Install apps one-by-one.

One app failure must not kill the whole setup.

### visualstudio.msvc

Install/modify Visual Studio Build Tools or Community with Desktop development with C++ workload.

Must verify link.exe.

Priority:
1. already installed
2. modify existing Visual Studio install
3. use cached vs_BuildTools.exe
4. download if internet is available
5. mark Blocked if impossible

### toolchains.install

Install:
- fnm
- Node/npm
- Rust
- Python/uv
- Go
- Tauri CLI only if MSVC link.exe is available

If MSVC is missing, Tauri should be Blocked, not Failed.

### windows.updates

Install Windows updates without automatic reboot.

### wsl.install

Install/configure WSL only when selected.

### debloat.run

Optional only.

## Tools menu

Tools are separate from normal setup.

Required tools:

1. Export Wi-Fi/touchpad recovery drivers
2. Cache offline recovery installers
3. Prepare/update recovery USB
4. Validate recovery USB
5. Rebuild/slipstream Windows install USB
6. Diagnostics
7. Read instructions

## Recovery USB tool

Should:

- detect USB drives
- choose target
- copy repo
- copy exported drivers
- copy cached installers
- create _START_HERE.cmd
- create README-FIRST.txt
- validate contents

Must not create fake AutoRun.

## Slipstream/rebuild USB tool

Should live under tools/slipstream.

It can be guided and ask for:

- Windows ISO path
- USB drive
- update packages
- staging folder

It is a tool, not part of normal setup.

## Logging

Each run should create:

    logs/yyyy-mm-dd_hhmmss/
    ├── setup.log
    ├── summary.json
    ├── errors.log
    └── commands/

## State

State file:

    state/setup-state.json

It should track:

- selected mode
- task statuses
- failures
- blocked tasks
- reboot pending
- log path

## Implementation instruction

Do this in phases.

Phase 1:
- Create the framework skeleton.
- Add setup.ps1.
- Add setup.json.
- Add core modules.
- Add logs/state handling.
- Add basic menu.
- Add no-op task execution.
- Do not wire real installers yet.
- Do not remove old scripts yet.

Phase 2:
- Add detection layer.

Phase 3:
- Add dependency engine and task state.

Phase 4:
- Wire real setup tasks one group at a time.

Phase 5:
- Add tools/utilities.

Phase 6:
- Clean old scripts into legacy only after replacements work.
