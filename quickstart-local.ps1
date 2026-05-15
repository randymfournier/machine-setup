# quickstart-local.ps1
# Offline/local USB entry point for the ugly case where a fresh Windows install
# has no Wi-Fi and/or no usable touchpad yet.
#
# Easiest path from USB:
#   Run Start-MachineSetup.cmd
#
# Keyboard-only fallback, replacing D: with the USB drive letter:
#   D:\Start-MachineSetup.cmd
#
# This script does not need Git or winget. It installs saved local drivers,
# copies this repo to C:\machine-setup, then launches setup-wizard.ps1 with
# -NoProfile and -ExecutionPolicy Bypass. If the wizard is missing, it falls
# back to bootstrap.ps1.

$ErrorActionPreference = 'Stop'

if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Run this from PowerShell/CMD as Administrator." -ForegroundColor Red
    exit 1
}

try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop
} catch {
    Write-Warning "Could not set process execution policy automatically: $($_.Exception.Message)"
}

$SourceRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = (Get-Location).Path
}

$RepoPath = 'C:\machine-setup'

Write-Host "machine-setup local USB bootstrap" -ForegroundColor Green
Write-Host "Source: $SourceRoot" -ForegroundColor Cyan
Write-Host "Target: $RepoPath" -ForegroundColor Cyan

# Install exported drivers before doing anything network-dependent.
$driverInstaller = Join-Path $SourceRoot 'drivers\install-exported-drivers.ps1'
if (Test-Path $driverInstaller) {
    Write-Host "`nInstalling saved Wi-Fi/touchpad recovery drivers if present..." -ForegroundColor Cyan
    try {
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $driverInstaller
    } catch {
        Write-Warning "Local driver install failed or no exported folder was found: $($_.Exception.Message)"
        Write-Warning "Continuing anyway."
    }
} else {
    Write-Warning "Driver installer not found at $driverInstaller. Continuing."
}

# Copy repo from USB/local source to C:\machine-setup unless already there.
$sourceFull = [System.IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')
$targetFull = [System.IO.Path]::GetFullPath($RepoPath).TrimEnd('\')

if ($sourceFull -ieq $targetFull) {
    Write-Host "Source is already C:\machine-setup. No copy needed." -ForegroundColor DarkGray
} else {
    New-Item -ItemType Directory -Path $RepoPath -Force | Out-Null
    Write-Host "`nCopying setup repo to $RepoPath ..." -ForegroundColor Cyan
    & robocopy $SourceRoot $RepoPath /E /XD .git logs /NFL /NDL /NJH /NJS /NP
    $robocopyExit = $LASTEXITCODE
    if ($robocopyExit -ge 8) {
        throw "robocopy failed with exit code $robocopyExit."
    }
}

try {
    Get-ChildItem -Path $RepoPath -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
} catch {
    Write-Warning "Could not unblock all repo files: $($_.Exception.Message)"
}

$wizardPath = Join-Path $RepoPath 'setup-wizard.ps1'
$bootstrapPath = Join-Path $RepoPath 'bootstrap.ps1'

if (Test-Path $wizardPath) {
    Write-Host "`nLaunching setup-wizard.ps1 with -NoProfile and -ExecutionPolicy Bypass...`n" -ForegroundColor Green
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $wizardPath
    $setupExit = $LASTEXITCODE

    if ($setupExit -ne 0) {
        Write-Warning "setup-wizard.ps1 finished with exit code $setupExit. Check C:\machine-setup\logs for details."
    }

    exit $setupExit
}

Write-Warning "setup-wizard.ps1 was not found. Falling back to bootstrap.ps1."
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $bootstrapPath
$bootstrapExit = $LASTEXITCODE

if ($bootstrapExit -ne 0) {
    Write-Warning "bootstrap.ps1 finished with exit code $bootstrapExit. Check C:\machine-setup\logs for details."
}

exit $bootstrapExit
