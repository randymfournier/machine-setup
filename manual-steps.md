# Manual steps after bootstrap

Things `bootstrap.ps1` can't fully do for you. Work through these once after recovery.

## 1. Network / Wi-Fi driver fallback

A fresh Windows ISO may not include your Wi-Fi driver.

If Wi-Fi is missing after install:

- Use Ethernet temporarily, if available.
- Or USB-tether from your phone long enough to run Windows Update / bootstrap.
- Or keep the vendor Wi-Fi/LAN driver installer on your recovery USB.

**Maintenance habit:** add your exact motherboard/laptop network driver link here after the next successful recovery.

```
Wi-Fi/LAN driver link: [fill in]
```

## 2. Visual Studio 2022 — C++ workload fallback

`bootstrap.ps1` now tries to install/modify Visual Studio automatically with:

- **Desktop development with C++** / `Microsoft.VisualStudio.Workload.NativeDesktop`

This is required for Rust/Tauri/native builds because `cargo` needs the MSVC linker: `link.exe`.

If the `visualstudio` step fails, use this fallback:

1. Open **Visual Studio Installer** from Start menu.
2. Click **Modify** on Visual Studio Community 2022 or Build Tools.
3. Check:
   - ✅ **Desktop development with C++** *(required for Tauri / native Rust deps)*
   - ✅ **.NET desktop development** *(optional, useful if you touch C# / WPF)*
4. Click Modify and wait for it to finish.
5. Re-run:

```powershell
cd C:\machine-setup
.\bootstrap.ps1 -Skip windows,updates,winget-repair,winget,dotfiles,wsl
```

## 3. Microsoft 365

You said you've got your own free method here — set this up on your own and note in a private password-vault entry which path you used, so future-you remembers.

If you ever decide to script it: drop the steps into a new file `m365-setup.md` in this repo (no credentials, just the procedure).

## 4. Hardware drivers

After a fresh Windows install, Windows Update gets you 90% of the way. The other 10% (often the most painful) is vendor-specific:

- **GPU:** NVIDIA App / AMD Adrenalin / Intel Graphics Command Center — install from the manufacturer site, not Windows Update's older builds.
- **Audio:** if you have a discrete audio interface, drivers from the maker.
- **Motherboard chipset:** check your motherboard maker's support page — chipset, LAN, and USB drivers can save mystery problems later.
- **Drawing tablet, controller, etc.**

**Maintenance habit:** keep a one-paragraph note here listing the exact GPU, motherboard, and any peripherals you need drivers for, so future-you doesn't have to dig out the box.

```
GPU:           [fill in]
Motherboard:   [fill in]
Peripherals:   [fill in]
```

## 5. Taskbar extras: Widgets / Chat / Copilot

These registry keys change across Windows 11 builds, so the bootstrap leaves them alone instead of pretending Microsoft will sit still for five minutes.

Manual path:

1. Right-click the taskbar.
2. Open **Taskbar settings**.
3. Turn off whatever you don't want:
   - Widgets
   - Chat / Teams
   - Copilot
   - Search box style

## 6. ScreenRec

Not on winget. Download from https://screenrec.com → run installer → sign in. Preferences:

- Set screenshot/video save location to a synced folder if you want them backed up.

(If you ever switch to OBS Studio, that one *is* on winget: `winget install OBSProject.OBSStudio`.)

## 7. BIOS / UEFI settings

If you do a clean Windows install on a machine you haven't touched in a while, double-check:

- **Secure Boot** = enabled (Win11 expects it)
- **TPM 2.0** = enabled (some CPUs ship with it disabled by default)
- **Virtualization (VT-x / AMD-V / SVM)** = enabled (required for WSL2 and Docker Desktop)
- **Resizable BAR** = enabled (modern GPU performance, harmless if not present)

## 8. Browser sync

After installing Brave and Opera Air via winget:

- Sign in to Brave Sync (you'll need your sync code from another device, or your Brave account if you use one).
- Opera: sign in to Opera account → enable sync.
- Install **Proton Pass** extension in each browser (Chrome Web Store / Edge add-ons).

## 9. AI app sign-ins

The bootstrap attempts to install Claude and ChatGPT, but it cannot sign in for you.

- Sign into **Claude desktop**.
- Sign into **ChatGPT desktop**.
- Run any CLI auth flows you need, such as `claude login` or project-specific Codex/OpenAI auth.

## 10. Windows Terminal — set your starting directory

The terminal settings template assumes username `randy` for the WSL profile:

```json
"startingDirectory": "//wsl$/Ubuntu/home/randy"
```

Edit `shell/windows-terminal-settings.json` to match your actual WSL username, then re-run the dotfiles step of `bootstrap.ps1`:

```powershell
.\bootstrap.ps1 -Skip windows,updates,winget-repair,winget,visualstudio,toolchains,vscode,wsl
```

## 11. Verify everything

After all manual steps, run a quick sanity check:

```powershell
git --version
node --version
python --version
rustc --version
go version
docker --version
wsl --status
ssh -T git@github.com
```

If any of those fail, check the latest files in `C:\machine-setup\logs\` first. That folder is now the black box recorder. Less mystery, fewer gremlins.
