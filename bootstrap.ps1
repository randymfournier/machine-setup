# bootstrap.ps1
# Main orchestrator. Run from quickstart.ps1, or directly:
#   cd C:\machine-setup
#   .\bootstrap.ps1
#
# Idempotent -- safe to re-run.
#
# Skip steps with -Skip (use the lowercase keys below):
#   .\bootstrap.ps1 -Skip windows,updates,wsl,dotfiles
#
# Available skip keys:
#   windows     -- Windows tweaks (taskbar, dark mode, perf)
#   debloat     -- only runs when -IncludeDebloat is also passed
#   updates     -- Windows updates
#   winget      -- winget package import
#   toolchains  -- fnm, uv, Rust, fonts, etc.
#   vscode      -- VS Code extensions
#   dotfiles    -- copy PowerShell profile, starship, etc.
#   wsl         -- WSL2 + Ubuntu install
#
# Opt in to debloat (removes Teams, Xbox, Bing, etc.):
#   .\bootstrap.ps1 -IncludeDebloat

[CmdletBinding()]
param(
    [string[]]$Skip = @(),
    [switch]$IncludeDebloat
)

$ErrorActionPreference = 'Stop'
$RepoRoot = $PSScriptRoot

# --- Must be admin ---------------------------------------------------------
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Run as Administrator." -ForegroundColor Red
    exit 1
}

# Belt-and-suspenders: unblock any internet-marked files in the repo so
# child scripts can run regardless of execution policy.
Get-ChildItem -Path $RepoRoot -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

function Step($key, $heading) {
    if ($key -in $Skip) {
        Write-Host "`n[SKIP] $heading ($key)" -ForegroundColor Yellow
        return $false
    }
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  $heading" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    return $true
}

# --- 1. Apply Windows tweaks (taskbar, perf, dark mode, etc.) -------------
if (Step "windows" "Windows tweaks") {
    & "$RepoRoot\windows\apply-tweaks.ps1"
}

# --- 1b. Debloat (OPT-IN: only runs when -IncludeDebloat passed) ----------
if ($IncludeDebloat -and (Step "debloat" "Debloat")) {
    & "$RepoRoot\windows\debloat.ps1"
}

# --- 2. Bulk-install Windows updates --------------------------------------
if (Step "updates" "Windows updates") {
    & "$RepoRoot\windows\update-windows.ps1"
}

# --- 3. Install all winget packages ---------------------------------------
if (Step "winget" "winget packages") {
    winget import -i "$RepoRoot\winget-packages.json" --accept-package-agreements --accept-source-agreements --ignore-unavailable
    # PATH refresh
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path','User')
}

# --- 4. Install dev toolchains (fnm, uv, Rust, Tauri prereqs, fonts) -----
if (Step "toolchains" "Dev toolchains") {
    & "$RepoRoot\dev\install-toolchains.ps1"
}

# --- 5. VS Code extensions -------------------------------------------------
if (Step "vscode" "VS Code extensions") {
    if (Get-Command code -ErrorAction SilentlyContinue) {
        Get-Content "$RepoRoot\dev\vscode-extensions.txt" |
            Where-Object { $_ -and -not $_.StartsWith('#') } |
            ForEach-Object { code --install-extension $_ --force }
    } else {
        Write-Host "code CLI not on PATH yet -- open VS Code once, then re-run this step." -ForegroundColor Yellow
    }
}

# --- 6. Copy dotfiles into place ------------------------------------------
if (Step "dotfiles" "Dotfiles") {
    # PowerShell profile
    $profileDir = Split-Path -Parent $PROFILE
    if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
    Copy-Item "$RepoRoot\shell\Microsoft.PowerShell_profile.ps1" $PROFILE -Force

    # Starship config
    $starshipConfig = "$env:USERPROFILE\.config\starship.toml"
    New-Item -ItemType Directory -Path (Split-Path $starshipConfig) -Force | Out-Null
    Copy-Item "$RepoRoot\shell\starship.toml" $starshipConfig -Force

    # Windows Terminal settings (only if Terminal is installed)
    $wtSettings = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    if (Test-Path (Split-Path $wtSettings)) {
        Copy-Item "$RepoRoot\shell\windows-terminal-settings.json" $wtSettings -Force
    }

    # Git config -- copy as template, user fills in name/email
    Copy-Item "$RepoRoot\git\.gitconfig" "$env:USERPROFILE\.gitconfig" -Force
    Copy-Item "$RepoRoot\git\.gitignore_global" "$env:USERPROFILE\.gitignore_global" -Force
    Write-Host "Remember to edit $env:USERPROFILE\.gitconfig with your name/email." -ForegroundColor Yellow
}

# --- 7. WSL2 + Ubuntu ------------------------------------------------------
if (Step "wsl" "WSL2") {
    & "$RepoRoot\wsl\setup-wsl.ps1"
}

# --- Done -----------------------------------------------------------------
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  Bootstrap complete." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host @"

NEXT STEPS:

  1. Restore SSH keys      -> see ssh\README.md
  2. Edit .gitconfig       -> set user.name and user.email
  3. Log in to services    -> see accounts-checklist.md
  4. Manual stuff          -> see manual-steps.md (M365, drivers, etc.)
  5. Modding tools         -> see modding\ue4ss-icarus.md (only if you need it)

If WSL was just installed, REBOOT before using it.
"@ -ForegroundColor Cyan
