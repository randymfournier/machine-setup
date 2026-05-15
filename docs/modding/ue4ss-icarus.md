# UE4SS for Icarus modding

UE4SS isn't on winget — it's released on GitHub and ships as a folder you drop next to the game's executable. This is a manual flow, but quick.

## Install

1. Go to https://github.com/UE4SS-RE/RE-UE4SS/releases
2. Download the **latest non-experimental** zip (look for `UE4SS_v*.zip`, not the `-experimental` ones unless you specifically need newer features).
3. Locate Icarus's binary folder:
   ```
   C:\Program Files (x86)\Steam\steamapps\common\Icarus\Icarus\Binaries\Win64\
   ```
   (Adjust if your Steam library is on a different drive.)
4. Extract the zip's contents directly into that `Win64` folder. You should end up with `dwmapi.dll`, a `Mods` folder, and `UE4SS-settings.ini` sitting next to `IcarusClient-Shim.exe` (or whichever the launcher exe is).
5. Launch the game once. UE4SS injects on startup. A console window should appear — that confirms it's working.

## Configure

Open `UE4SS-settings.ini` and at minimum:

```ini
[General]
bUseUObjectArrayCache = true

[Debug]
ConsoleEnabled = 1
GuiConsoleEnabled = 1
GuiConsoleVisible = 1
```

The GUI console is your friend during mod development.

## Mod development workflow

Mods live under the `Mods/` folder. Each mod has its own subfolder with `enabled.txt` (empty, presence = enabled) and a `Scripts/main.lua`.

For your map overlay, you'll likely want:
- A Lua mod that hooks player position events
- An external companion app (Tauri is a good fit) that reads from a file or pipe and renders the overlay

## Linkarus Discord

The community has tooling, examples, and people who've solved most of this already. Worth joining if you haven't:
https://discord.gg/linkarus  (or search "Linkarus" on Discord directory if that link rotates)

## When the game updates

UE4SS sometimes breaks against new Icarus builds. If it stops injecting after a game patch, check the UE4SS GitHub for a release that mentions the new game version. Drop the new files over the old ones; configs are preserved.

## What to back up

Your `Mods/` folder and any custom `UE4SS-settings.ini` — these can live in their own git repo (separate from this machine-setup repo). If you publish mods, that repo is also the public release artifact.
