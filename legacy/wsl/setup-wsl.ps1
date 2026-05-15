# wsl/setup-wsl.ps1
# Installs WSL2 + Ubuntu 24.04, then runs ubuntu-setup.sh inside the distro.

$ErrorActionPreference = 'Stop'

# --- Make sure WSL is installed -------------------------------------------
$wslInstalled = $null
try { $wslInstalled = wsl --status 2>$null } catch {}

if (-not $wslInstalled) {
    Write-Host "Installing WSL2 (this may require a reboot)..." -ForegroundColor Cyan
    wsl --install --no-distribution
    Write-Host "REBOOT REQUIRED. After reboot, re-run bootstrap.ps1 -- WSL setup will resume." -ForegroundColor Yellow
    return
}

# --- Set WSL2 as default --------------------------------------------------
wsl --set-default-version 2 | Out-Null

# --- Install Ubuntu 24.04 if not already present --------------------------
$installedDistros = (wsl --list --quiet) 2>$null
if ($installedDistros -notcontains 'Ubuntu-24.04') {
    Write-Host "Installing Ubuntu 24.04..." -ForegroundColor Cyan
    wsl --install -d Ubuntu-24.04 --no-launch
    Write-Host @"

Ubuntu installed. To finish:
  1. Open the 'Ubuntu 24.04' app from Start menu.
  2. Create your Linux username + password when prompted.
  3. Close that window.
  4. Re-run this script (or just bootstrap.ps1) to run the in-distro setup.

"@ -ForegroundColor Yellow
    return
}

# --- Run the in-distro setup script ---------------------------------------
$setupSh = "$PSScriptRoot\ubuntu-setup.sh"
if (Test-Path $setupSh) {
    Write-Host "Running ubuntu-setup.sh inside Ubuntu-24.04..." -ForegroundColor Cyan

    # Convert Windows path to WSL path so the script can read itself
    $wslPath = (wsl -d Ubuntu-24.04 wslpath -a "$setupSh") -replace "`r", ""
    wsl -d Ubuntu-24.04 -e bash -lc "chmod +x '$wslPath' && '$wslPath'"

    Write-Host "`nUbuntu setup complete." -ForegroundColor Green
} else {
    Write-Host "ubuntu-setup.sh not found at $setupSh" -ForegroundColor Red
}
