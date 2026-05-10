# dev/install-toolchains.ps1
# Installs language toolchains and tools that are better installed outside winget:
#   - fnm (Node version manager)
#   - uv (Python toolchain)
#   - rustup (Rust toolchain)
#   - Tauri prereqs (WebView2 is preinstalled on Win11; MSVC build tools come from VS 2022)
#   - FiraCode Nerd Font (for Starship glyphs in your terminal)
#   - ScreenRec (manual download, not on winget)

$ErrorActionPreference = 'Stop'
$tmp = "$env:TEMP\machine-setup-installs"
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

function Has($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

# --- fnm (Node version manager) --------------------------------------------
if (-not (Has fnm)) {
    Write-Host "Installing fnm..." -ForegroundColor Cyan
    winget install --id Schniz.fnm -e --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path','User')
} else {
    Write-Host "fnm already installed." -ForegroundColor DarkGray
}

# Use fnm to install latest LTS Node and set as default
if (Has fnm) {
    fnm install --lts
    fnm default lts-latest
}

# --- uv (Python toolchain) -------------------------------------------------
if (-not (Has uv)) {
    Write-Host "Installing uv..." -ForegroundColor Cyan
    irm https://astral.sh/uv/install.ps1 | iex
    # uv installs to $env:USERPROFILE\.cargo\bin and adds itself to user PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path','User')
} else {
    Write-Host "uv already installed." -ForegroundColor DarkGray
}

# Pin a recent Python so projects without their own .python-version still work
if (Has uv) {
    uv python install 3.12
}

# --- rustup (Rust toolchain, for Tauri etc.) -------------------------------
if (-not (Has rustup)) {
    Write-Host "Installing rustup..." -ForegroundColor Cyan
    $rustupExe = "$tmp\rustup-init.exe"
    Invoke-WebRequest -Uri "https://win.rustup.rs/x86_64" -OutFile $rustupExe
    & $rustupExe -y --default-toolchain stable
    $env:Path = "$env:USERPROFILE\.cargo\bin;" + $env:Path
} else {
    Write-Host "rustup already installed." -ForegroundColor DarkGray
}

# --- Tauri prereqs ---------------------------------------------------------
# WebView2 ships with Win11 already.
# MSVC build tools come from Visual Studio 2022 -- make sure these workloads
# are installed via the Visual Studio Installer:
#
#   - Desktop development with C++
#     (includes MSVC, Windows SDK -- required for Tauri / native deps)
#
# The bootstrap script can't reliably automate VS workload installs without
# the VS Installer being present, so this is documented in manual-steps.md.
# Tauri CLI itself:
if (Has cargo) {
    Write-Host "Installing tauri-cli via cargo..." -ForegroundColor Cyan
    cargo install tauri-cli --locked
}

# --- FiraCode Nerd Font (for Starship glyphs) ------------------------------
$fontInstalled = Get-ChildItem "$env:WINDIR\Fonts" -Filter "FiraCode*" -ErrorAction SilentlyContinue
if (-not $fontInstalled) {
    Write-Host "Installing FiraCode Nerd Font..." -ForegroundColor Cyan
    $fontZip = "$tmp\FiraCode.zip"
    $fontDir = "$tmp\FiraCode"
    Invoke-WebRequest -Uri "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip" -OutFile $fontZip
    Expand-Archive -Path $fontZip -DestinationPath $fontDir -Force

    $shell = New-Object -ComObject Shell.Application
    $fonts = $shell.Namespace(0x14)  # Fonts folder
    Get-ChildItem -Path $fontDir -Include *.ttf, *.otf -Recurse | ForEach-Object {
        $dest = "$env:WINDIR\Fonts\$($_.Name)"
        if (-not (Test-Path $dest)) {
            $fonts.CopyHere($_.FullName, 0x10)  # 0x10 = no progress UI
        }
    }
} else {
    Write-Host "FiraCode font already installed." -ForegroundColor DarkGray
}

# --- ScreenRec (no winget package; manual download) ------------------------
# Skipped here -- see manual-steps.md. Greenshot covers screenshots already
# (installed via winget); ScreenRec is for video. If you want, OBS Studio is
# a winget option that's much more powerful:
#   winget install OBSProject.OBSStudio

Write-Host "`nDev toolchains done." -ForegroundColor Green
Write-Host "Languages installed: Node (via fnm), Python (via uv), Rust (via rustup), Go (via winget)." -ForegroundColor Cyan
Write-Host "Don't forget the VS 2022 'Desktop development with C++' workload (manual-steps.md)." -ForegroundColor Yellow
