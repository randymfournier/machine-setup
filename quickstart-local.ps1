# quickstart-local.ps1
# Local USB driver-rescue entry point.
#
# Easiest path from USB:
#   Run _START_HERE.cmd
#
# This script intentionally does not run the full setup from the USB copy.
# The USB may be stale. Its job is to install saved Wi-Fi/touchpad drivers,
# then hand off to the primary GitHub quickstart once networking is available.

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

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

$QuickstartUrl = 'https://raw.githubusercontent.com/randymfournier/machine-setup/main/quickstart.ps1'

function Test-InternetReady {
    try {
        $response = Invoke-WebRequest -Uri 'https://raw.githubusercontent.com' -UseBasicParsing -Method Head -TimeoutSec 15 -ErrorAction Stop
        return ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500)
    } catch {
        return $false
    }
}

Write-Host "machine-setup USB driver rescue" -ForegroundColor Green
Write-Host "Source: $SourceRoot" -ForegroundColor Cyan

$driverInstaller = Join-Path $SourceRoot 'legacy\drivers\install-exported-drivers.ps1'
if (Test-Path $driverInstaller) {
    Write-Host "`nInstalling saved Wi-Fi/touchpad recovery drivers if present..." -ForegroundColor Cyan
    try {
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $driverInstaller
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Driver install returned exit code $LASTEXITCODE. Continuing to network check."
        }
    } catch {
        Write-Warning "Local driver install failed or no exported folder was found: $($_.Exception.Message)"
        Write-Warning "Continuing to network check."
    }
} else {
    Write-Warning "Driver installer not found at $driverInstaller. Continuing to network check."
}

Write-Host "`nChecking whether the GitHub quickstart is reachable..." -ForegroundColor Cyan
if (-not (Test-InternetReady)) {
    Write-Host "Network is still not ready." -ForegroundColor Yellow
    Write-Host "Connect Wi-Fi/Ethernet if possible, then run the primary command:" -ForegroundColor Yellow
    Write-Host "  irm $QuickstartUrl | iex" -ForegroundColor White
    Write-Host ""
    Write-Host "If the driver install failed, inspect the exported driver folder on this USB." -ForegroundColor Yellow
    exit 20
}

Write-Host "Network looks ready. Launching primary GitHub quickstart..." -ForegroundColor Green
Invoke-Expression (Invoke-RestMethod -Uri $QuickstartUrl -UseBasicParsing)
