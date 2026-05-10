# quickstart.ps1
# Entry point. Run on a fresh Windows install via:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
#   irm https://raw.githubusercontent.com/<YOUR-GH-USERNAME>/machine-setup/main/quickstart.ps1 | iex
#
# This script's only jobs:
#   1. Make sure git is available
#   2. Clone the repo to C:\machine-setup
#   3. Hand off to bootstrap.ps1

$ErrorActionPreference = 'Stop'

# --- Must be admin ---------------------------------------------------------
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Run this in PowerShell as Administrator." -ForegroundColor Red
    exit 1
}

# --- Config ----------------------------------------------------------------
$RepoUrl  = 'https://github.com/randymfournier/machine-setup.git'   # <-- EDIT ME
$RepoPath = 'C:\machine-setup'

# --- Ensure git is installed (winget ships in Win11) -----------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Installing git via winget..." -ForegroundColor Cyan
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
    # Refresh PATH for current session so `git` resolves
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path','User')
}

# --- Clone or update -------------------------------------------------------
if (Test-Path $RepoPath) {
    Write-Host "$RepoPath exists, pulling latest..." -ForegroundColor Cyan
    git -C $RepoPath pull --ff-only
} else {
    Write-Host "Cloning $RepoUrl to $RepoPath..." -ForegroundColor Cyan
    git clone $RepoUrl $RepoPath
}

# --- Hand off to bootstrap -------------------------------------------------
Write-Host "`nLaunching bootstrap.ps1...`n" -ForegroundColor Green
& "$RepoPath\bootstrap.ps1"
