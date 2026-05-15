# machine-setup recovery USB

This folder turns `machine-setup` into a small recovery toolkit, not just a bootstrap script.

## What this USB is for

Use it to:

- start machine setup after a fresh Windows install
- install saved Wi-Fi/touchpad drivers when the fresh ISO has no network or working touchpad
- keep local recovery assets such as `winget.msixbundle` and `vs_BuildTools.exe`
- read the rebuild instructions even months later
- prepare or refresh the recovery USB from the setup console tools menu

## Important: USB launch reality

Modern Windows should not automatically execute programs from a USB drive just because it was inserted. This toolkit does not rely on AutoRun.

Use one of these launch paths:

1. Normal internet path:

   ```powershell
   irm https://raw.githubusercontent.com/randymfournier/machine-setup/main/quickstart.ps1 | iex
   ```

2. No-Wi-Fi/no-touchpad local USB path:

   ```text
   D:\_START_HERE.cmd
   ```

## Recommended maintenance flow before a wipe

From a working machine:

1. Open the setup console.
2. Choose `Recovery / maintenance tools`.
3. Run:
   - Export Wi-Fi/touchpad drivers
   - Cache offline recovery assets
   - Prepare/update recovery USB files

That keeps the USB ready without needing to remember long commands.

## What prepare-recovery-usb.ps1 does

The utility copies this repo to the target USB, excluding logs and Git internals, then writes:

- `_START_HERE.cmd`
- `Start-MachineSetup.cmd` compatibility alias
- `README-FIRST.txt`

## Rebuilding the bootable Windows USB

See:

```text
slipstream-iso.md
```

That file explains the UUP Dump + Rufus process for rebuilding a Windows 11 USB with current cumulative updates baked in.
