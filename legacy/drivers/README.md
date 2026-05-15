# Selected driver backup

Use this folder for the two drivers that matter on a fresh install:

- Wi-Fi, likely MediaTek
- Touchpad, vendor may be ELAN, Synaptics, Precision Touchpad, or an I2C/HID/System package

## Export from the working Windows install

Run PowerShell as Administrator:

```powershell
cd C:\machine-setup
.\drivers\export-selected-drivers.ps1
```

The default filter now includes MediaTek Wi-Fi plus Intel Serial IO I2C/GPIO entries used by many touchpads, including the `7F4C/7F4D/7F4E/7F7A/7F7B` family and `INTC1082/INTC1084`. Use `-ListCandidates` only when troubleshooting.

The script exports likely matches to:

```text
drivers\exported-selected-yyyy-mm-dd\
```

If the touchpad is still not detected after a fresh install, rerun with `-ListCandidates` and add a missing keyword only if needed.

Copy the exported folder to your recovery USB. Do not depend on GitHub for these driver files because the whole point is surviving a no-Wi-Fi install.

## Install after a fresh Windows install

Preferred recovery path: keep this repo plus the exported driver folder on the recovery USB, then run:

```text
D:\Start-MachineSetup.cmd
```

Replace `D:` with the USB drive letter. The local quickstart will install the exported drivers automatically before the main bootstrap.

Manual driver-only fallback:

```powershell
.\drivers\install-exported-drivers.ps1
```

The installer searches common USB/repo locations for `exported-selected-*`, so you normally do not need to type the full `-Source` path.
