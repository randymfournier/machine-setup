# quickstart.ps1
# Entry point. Run on a fresh Windows install via:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
#   irm https://raw.githubusercontent.com/randymfournier/machine-setup/main/quickstart.ps1 | iex
#
# This script's only jobs:
#   1. Make sure winget/App Installer is healthy enough to install git
#   2. Make sure git is available
#   3. Clone the repo to C:\machine-setup
#   4. Hand off to bootstrap.ps1

$ErrorActionPreference = 'Stop'

# --- Must be admin ---------------------------------------------------------
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Run this in PowerShell as Administrator." -ForegroundColor Red
    exit 1
}

# --- Config ----------------------------------------------------------------
$RepoUrl  = 'https://github.com/randymfournier/machine-setup.git'
$RepoPath = 'C:\machine-setup'

function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable('Path','Machine')
    $userPath = [System.Environment]::GetEnvironmentVariable('Path','User')
    $env:Path = @($machinePath, $userPath) -join ';'
}

function Test-WingetHealthy {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warning "winget is not on PATH."
        return $false
    }

    $output = & winget source list 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "winget source list failed: $($output -join ' ')"
        return $false
    }

    return $true
}

function Repair-Winget {
    Write-Host "Repairing App Installer / winget before installing git..." -ForegroundColor Cyan

    $bundlePath = Join-Path $env:TEMP 'winget.msixbundle'
    Invoke-WebRequest -Uri 'https://aka.ms/getwinget' -OutFile $bundlePath -UseBasicParsing
    Add-AppxPackage -Path $bundlePath

    Refresh-Path

    & winget source reset --force
    if ($LASTEXITCODE -ne 0) {
        throw "winget source reset --force failed with exit code $LASTEXITCODE."
    }

    & winget source update
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "winget source update returned exit code $LASTEXITCODE. Continuing after reset."
    }

    if (-not (Test-WingetHealthy)) {
        throw "winget still does not appear healthy after repair."
    }
}

# --- Ensure winget can install git -----------------------------------------
if (-not (Test-WingetHealthy)) {
    Repair-Winget
}

# --- Ensure git is installed -----------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Installing git via winget..." -ForegroundColor Cyan
    & winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "Git install failed with exit code $LASTEXITCODE."
    }

    Refresh-Path

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Git install completed, but git.exe is still not on PATH. Restart PowerShell and run quickstart again."
    }
}

# --- Clone or update -------------------------------------------------------
if (Test-Path $RepoPath) {
    Write-Host "$RepoPath exists, pulling latest..." -ForegroundColor Cyan
    git -C $RepoPath pull --ff-only
    if ($LASTEXITCODE -ne 0) {
        throw "git pull failed with exit code $LASTEXITCODE."
    }
} else {
    Write-Host "Cloning $RepoUrl to $RepoPath..." -ForegroundColor Cyan
    git clone $RepoUrl $RepoPath
    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed with exit code $LASTEXITCODE."
    }
}

# --- Hand off to bootstrap -------------------------------------------------
Write-Host "`nLaunching bootstrap.ps1...`n" -ForegroundColor Green
& "$RepoPath\bootstrap.ps1"
