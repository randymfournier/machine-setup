# installers

Optional offline/bootstrapper cache.

Put these files here before copying this repo to a recovery USB:

```text
installers/
├── vs_BuildTools.exe
└── winget.msixbundle
```

Why this exists:

- Fresh Windows installs can have broken DNS/source metadata for `aka.ms`.
- Wi-Fi or App Installer/winget may not be healthy yet.
- The bootstrap can use these local files instead of downloading them during the fragile first-run window.

Use the root script below on a working machine:

```powershell
.\cache-recovery-assets.ps1
```
