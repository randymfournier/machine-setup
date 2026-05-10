# Slipstreaming an updated Windows 11 install USB

After your *first* recovery (where you have to download all updates after install — that's what `windows/update-windows.ps1` is for), build a fresh USB with current cumulative updates already integrated. Saves 30–60 min on every future recovery.

## Tool: UUP Dump

UUP Dump pulls Microsoft's own Update Catalog files directly and bakes them into a fresh ISO. It's the modern, no-shenanigans way to do this.

### Steps

1. Go to **https://uupdump.net**
2. Click **Latest Public Release builds** (or Latest Beta if you're on Insider).
3. Pick the build you want — usually the topmost `Windows 11, version 24H2` (or whatever's current) for `amd64`.
4. Choose your language and edition (Pro is the usual pick; Home is fine if that's what you license).
5. On the next screen, **Download method**: pick **"Download and convert to ISO"**.
6. **Conversion options** — leave defaults checked:
   - ✅ Include updates
   - ✅ Run aria2 download in a separate window
7. Click **Create download package**. You get a `.zip`.
8. Extract the zip. Run `uup_download_windows.cmd` as a regular user (not admin).
9. Wait. It downloads ~5 GB and assembles an ISO. Takes 15–60 min depending on your connection and CPU.
10. The output is a single `.ISO` in the same folder.

## Burn to USB with Rufus

1. Get **Rufus** from https://rufus.ie (or `winget install Rufus.Rufus` on a working machine).
2. Plug in an 8 GB+ USB stick.
3. Open Rufus → select your USB → select the ISO from UUP Dump.
4. Partition scheme: **GPT** for modern UEFI machines.
5. Click Start. ~5 min later you have a bootable, pre-updated install USB.

## Optional: bypass Microsoft account requirement

If you want to skip the "sign in to your Microsoft account" page during install (i.e., create a local account), Rufus offers checkboxes for this when you click Start. They include:
- Remove requirement for an online Microsoft account
- Remove requirement for 4GB+ RAM, Secure Boot and TPM 2.0 (only relevant for unsupported hardware)

These are safe.

## How often to refresh

- Microsoft ships a new Windows 11 feature update roughly once a year.
- Cumulative updates ship monthly (Patch Tuesday).
- A USB built today will be stale-ish in 2–3 months. Once a quarter is a reasonable refresh cadence.
- Or just before you ever expect to need it.

## What this DOES NOT replace

UUP Dump gives you Windows + cumulative updates. You still need `bootstrap.ps1` to install your apps and set up your dev environment. The two layers compose — slipstream handles the OS, the bootstrap handles everything on top.
