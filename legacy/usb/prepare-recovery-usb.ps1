# usb/prepare-recovery-usb.ps1
# Copies machine-setup to a recovery USB and writes easy launch/readme files.
# Does not attempt USB AutoRun or Windows Setup auto-launch.
# Run from setup.ps1 Recovery / maintenance tools, or directly on a working machine.

[CmdletBinding()]
param(
    [string]$UsbRoot,
    [switch]$NoPrompt
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Assert-Admin {
    if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script in PowerShell as Administrator.'
    }
}

function Get-DriveCandidates {
    Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveType -in 2,3 -and $_.DeviceID } |
        Sort-Object DriveType, DeviceID
}

function Select-UsbRoot {
    $drives = @(Get-DriveCandidates)
    Write-Host ""
    Write-Host "Available drives:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $drives.Count; $i++) {
        $d = $drives[$i]
        $sizeGb = if ($d.Size) { [math]::Round($d.Size / 1GB, 1) } else { 0 }
        $freeGb = if ($d.FreeSpace) { [math]::Round($d.FreeSpace / 1GB, 1) } else { 0 }
        $type = if ($d.DriveType -eq 2) { 'Removable' } else { 'Fixed' }
        Write-Host ("  {0,2}. {1}\  {2}  {3} GB free / {4} GB total  {5}" -f ($i + 1), $d.DeviceID, $type, $freeGb, $sizeGb, $d.VolumeName)
    }

    Write-Host ""
    $choice = (Read-Host 'Choose target drive number or type path like E:\').Trim()
    if ($choice -match '^\d+$') {
        $n = [int]$choice
        if ($n -ge 1 -and $n -le $drives.Count) {
            return ($drives[$n - 1].DeviceID + '\')
        }
    }

    if ($choice -match '^[A-Za-z]:\?$') {
        if ($choice.EndsWith('\')) { return $choice }
        return ($choice + '\')
    }

    throw 'No valid USB target was selected.'
}

function Write-ReadmeFirst {
    param([Parameter(Mandatory=$true)][string]$TargetRoot)

    $content = @"
machine-setup recovery USB
==========================

Fresh install with internet:
  irm https://raw.githubusercontent.com/randymfournier/machine-setup/main/quickstart.ps1 | iex

Fresh install with no Wi-Fi/touchpad:
  1. Open PowerShell as Administrator.
  2. Run this from the USB drive, replacing D: if needed:

     D:\_START_HERE.cmd

  3. The USB launcher installs saved recovery drivers only.
  4. Once network is available, it runs the primary GitHub quickstart.

What this USB contains:
  - machine-setup repo
  - saved Wi-Fi/touchpad drivers if exported
  - cached recovery assets if downloaded
  - instructions for rebuilding the bootable Windows USB

Read:
  machine-setup\README.md
  machine-setup\usb\README.md
  machine-setup\docs\slipstream-iso.md

Notes:
  Modern Windows does not reliably autorun commands from USB drives for security reasons.
  This USB gives you the shortest safe driver-rescue path: _START_HERE.cmd.
"@

    Set-Content -Path (Join-Path $TargetRoot 'README-FIRST.txt') -Value $content -Encoding ASCII
}


function Write-StartCmd {
    param([Parameter(Mandatory=$true)][string]$TargetRoot)

    $content = @"
@echo off
setlocal
set ROOT=%~dp0
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%machine-setup\quickstart-local.ps1"
pause
"@

    Set-Content -Path (Join-Path $TargetRoot '_START_HERE.cmd') -Value $content -Encoding ASCII
    Set-Content -Path (Join-Path $TargetRoot 'Start-MachineSetup.cmd') -Value $content -Encoding ASCII
}

function Copy-RepoToUsb {
    param([Parameter(Mandatory=$true)][string]$TargetRoot)

    $targetRepo = Join-Path $TargetRoot 'machine-setup'
    New-Item -ItemType Directory -Path $targetRepo -Force | Out-Null

    Write-Host "Copying repo to: $targetRepo" -ForegroundColor Cyan

    $excludeDirs = @('.git','logs','.vscode','.idea')
    $excludeFiles = @('*.log')

    $args = @(
        $RepoRoot,
        $targetRepo,
        '/MIR',
        '/R:1',
        '/W:1',
        '/XD'
    ) + $excludeDirs + @('/XF') + $excludeFiles

    & robocopy @args
    $code = $LASTEXITCODE

    # robocopy exit codes 0-7 are success/info. 8+ means failure.
    if ($code -ge 8) {
        throw "robocopy failed with exit code $code."
    }

    Write-Host "Repo copy complete." -ForegroundColor Green
}


Assert-Admin

if (-not $UsbRoot) {
    $UsbRoot = Select-UsbRoot
}

if (-not (Test-Path $UsbRoot)) {
    throw "Target path does not exist: $UsbRoot"
}

$UsbRoot = (Resolve-Path $UsbRoot).Path
if (-not $UsbRoot.EndsWith('\')) { $UsbRoot += '\' }

Write-Host ""
Write-Host "Target recovery USB/root: $UsbRoot" -ForegroundColor Cyan

if (-not $NoPrompt) {
    Write-Host "This will mirror the current repo to $UsbRoot\machine-setup and write launch/readme files." -ForegroundColor Yellow
    $ok = (Read-Host 'Continue? Y/N').Trim()
    if ($ok -notmatch '^[Yy]$') { throw 'Cancelled by user.' }
}

Copy-RepoToUsb -TargetRoot $UsbRoot
Write-StartCmd -TargetRoot $UsbRoot
Write-ReadmeFirst -TargetRoot $UsbRoot
Write-Host ""
Write-Host "Recovery USB launch pack updated." -ForegroundColor Green
Write-Host "Root launcher: $UsbRoot\_START_HERE.cmd" -ForegroundColor Cyan
Write-Host "Legacy alias:  $UsbRoot\Start-MachineSetup.cmd" -ForegroundColor Cyan
Write-Host "Read first:    $UsbRoot\README-FIRST.txt" -ForegroundColor Cyan
Write-Host ""
Write-Host "Note: Windows will not auto-run this USB. Use _START_HERE.cmd after Windows is installed." -ForegroundColor Yellow
