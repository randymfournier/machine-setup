# quickstart.ps1
# Internet entry point for a fresh Windows install.
#
# Run PowerShell as Administrator and paste only this:
#   irm https://raw.githubusercontent.com/randymfournier/machine-setup/main/quickstart.ps1 | iex
#
# This script's jobs:
#   1. Set process execution policy bypass for this session
#   2. Install saved local recovery drivers if an exported folder is found on USB/local disk
#   3. Repair/check winget/App Installer enough to install Git
#   4. Make sure Git is available
#   5. Clone/update the repo to C:\machine-setup
#   6. Launch bootstrap.ps1 in a no-profile, bypassed child PowerShell process

$ErrorActionPreference = 'Stop'

# --- Must be admin ---------------------------------------------------------
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Run PowerShell as Administrator, then paste the irm quickstart command again." -ForegroundColor Red
    exit 1
}

# Avoid making the user type the execution-policy line every time.
try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop
} catch {
    Write-Warning "Could not set process execution policy automatically: $($_.Exception.Message)"
    Write-Warning "Continuing anyway; child bootstrap will also run with -ExecutionPolicy Bypass."
}

# --- Config ----------------------------------------------------------------
$RepoUrl  = 'https://github.com/randymfournier/machine-setup.git'
$RepoPath = 'C:\machine-setup'

function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable('Path','Machine')
    $userPath = [System.Environment]::GetEnvironmentVariable('Path','User')
    $env:Path = @($machinePath, $userPath) -join ';'
}

function Test-DriverFolder {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path $Path)) { return $false }
    $inf = Get-ChildItem -Path $Path -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    return [bool]$inf
}

function Find-ExportedDriverFolder {
    $candidates = New-Object System.Collections.Generic.List[object]

    $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
        Where-Object { $_.Root -and (Test-Path $_.Root) }

    foreach ($drive in $drives) {
        $root = $drive.Root.TrimEnd('\')
        foreach ($pattern in @(
            "$root\machine-setup-drivers\exported-selected-*",
            "$root\machine-setup-drivers\exported-*",
            "$root\drivers\exported-selected-*",
            "$root\drivers\exported-*",
            "$root\machine-setup\drivers\exported-selected-*",
            "$root\machine-setup\drivers\exported-*",
            "$root\exported-selected-*",
            "$root\exported-*"
        )) {
            Get-ChildItem -Path $pattern -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                if (Test-DriverFolder -Path $_.FullName) { $candidates.Add($_) | Out-Null }
            }
        }

        foreach ($path in @("$root\machine-setup-drivers", "$root\drivers")) {
            if (Test-DriverFolder -Path $path) {
                $item = Get-Item -Path $path -ErrorAction SilentlyContinue
                if ($item) { $candidates.Add($item) | Out-Null }
            }
        }
    }

    $candidates |
        Sort-Object FullName -Unique |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Install-RecoveryDriversIfPresent {
    Write-Host "Checking for saved Wi-Fi/touchpad recovery drivers..." -ForegroundColor Cyan

    $folder = Find-ExportedDriverFolder
    if (-not $folder) {
        Write-Host "No exported recovery driver folder found. Continuing." -ForegroundColor DarkGray
        return
    }

    Write-Host "Found recovery drivers: $($folder.FullName)" -ForegroundColor Cyan
    Write-Host "Installing them now so Wi-Fi/touchpad can come online before the main setup." -ForegroundColor DarkGray

    try {
        & pnputil /add-driver (Join-Path $folder.FullName '*.inf') /subdirs /install
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Driver install returned exit code $LASTEXITCODE. Continuing anyway."
        } else {
            Write-Host "Recovery driver install pass complete." -ForegroundColor Green
        }
    } catch {
        Write-Warning "Recovery driver install failed: $($_.Exception.Message)"
        Write-Warning "Continuing anyway."
    }
}

function Test-WingetHealthy {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warning "winget is not on PATH."
        return $false
    }

    $output = & winget --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "winget --version failed: $($output -join ' ')"
        return $false
    }

    return $true
}

function Repair-Winget {
    Write-Host "Repairing App Installer / winget before installing Git..." -ForegroundColor Cyan
    Write-Host "This is best-effort. If source reset fails, Git install will still be attempted." -ForegroundColor DarkGray

    $bundlePath = Join-Path $env:TEMP 'winget.msixbundle'

    try {
        Invoke-WebRequest -Uri 'https://aka.ms/getwinget' -OutFile $bundlePath -UseBasicParsing
        Add-AppxPackage -Path $bundlePath -ForceApplicationShutdown
    } catch {
        Write-Warning "App Installer repair failed or was already current: $($_.Exception.Message)"
    }

    Refresh-Path

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        & winget source reset --force
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "winget source reset --force failed with exit code $LASTEXITCODE. Continuing anyway."
        }

        & winget source update
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "winget source update returned exit code $LASTEXITCODE. Continuing anyway."
        }
    }

    if (-not (Test-WingetHealthy)) {
        Write-Warning "winget still does not appear healthy after repair."
    }
}

# --- Local recovery drivers ------------------------------------------------
# If the exported Wi-Fi/touchpad driver folder is on a USB, install it before
# relying on winget/Git/network-heavy steps.
Install-RecoveryDriversIfPresent

# --- Ensure winget can install git -----------------------------------------
if (-not (Test-WingetHealthy)) {
    Repair-Winget
} else {
    # Fresh installs can have broken source metadata even when winget itself exists.
    # Run the best-effort repair anyway so Git has the best chance of installing.
    Repair-Winget
}

# --- Ensure git is installed -----------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Git via winget..." -ForegroundColor Cyan
    & winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "Git install failed with exit code $LASTEXITCODE. If winget source repair is still broken, install Git for Windows manually or use the USB local quickstart, then re-run quickstart."
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

# Belt-and-suspenders: unblock repo files and launch bootstrap without loading a profile.
try {
    Get-ChildItem -Path $RepoPath -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
} catch {
    Write-Warning "Could not unblock all repo files: $($_.Exception.Message)"
}

# --- Hand off to bootstrap -------------------------------------------------
Write-Host "`nLaunching bootstrap.ps1 with -NoProfile and -ExecutionPolicy Bypass...`n" -ForegroundColor Green
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$RepoPath\bootstrap.ps1"
$bootstrapExit = $LASTEXITCODE

if ($bootstrapExit -ne 0) {
    Write-Warning "bootstrap.ps1 finished with exit code $bootstrapExit. Check C:\machine-setup\logs for details."
}

exit $bootstrapExit
