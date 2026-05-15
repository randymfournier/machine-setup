# drivers/install-exported-drivers.ps1
# Installs exported driver packages from a local folder, useful immediately after a fresh Windows install.
#
# Examples:
#   .\drivers\install-exported-drivers.ps1
#   .\drivers\install-exported-drivers.ps1 -Source D:\machine-setup-drivers
#
# When -Source is omitted, this script searches common USB/repo locations for
# exported-selected-* driver folders and installs the newest match.

[CmdletBinding()]
param(
    [string]$Source
)

$ErrorActionPreference = 'Stop'

function Assert-Admin {
    if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script in PowerShell as Administrator.'
    }
}

function Test-DriverFolder {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path $Path)) { return $false }
    $inf = Get-ChildItem -Path $Path -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    return [bool]$inf
}

function Find-ExportedDriverFolder {
    $candidates = New-Object System.Collections.Generic.List[object]

    # Repo-local exports first.
    foreach ($pattern in @(
        (Join-Path $PSScriptRoot 'exported-selected-*'),
        (Join-Path $PSScriptRoot 'exported-*')
    )) {
        Get-ChildItem -Path $pattern -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            if (Test-DriverFolder -Path $_.FullName) { $candidates.Add($_) | Out-Null }
        }
    }

    # USB / external drive friendly locations.
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

        # Also allow a simple D:\machine-setup-drivers folder full of .inf files.
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

Assert-Admin

if (-not $Source) {
    $latest = Find-ExportedDriverFolder
    if ($latest) {
        $Source = $latest.FullName
    }
}

if (-not $Source -or -not (Test-Path $Source)) {
    throw 'Driver source folder not found. Put exported-selected-* under a drivers folder or pass -Source D:\path\to\exported-selected-yyyy-mm-dd.'
}

if (-not (Test-DriverFolder -Path $Source)) {
    throw "No .inf files were found under $Source."
}

Write-Host "Installing recovery drivers from: $Source" -ForegroundColor Cyan
Write-Host "This should restore missing Wi-Fi/touchpad support when the exported drivers are present." -ForegroundColor DarkGray

& pnputil /add-driver (Join-Path $Source '*.inf') /subdirs /install
if ($LASTEXITCODE -ne 0) {
    throw "pnputil /add-driver failed with exit code $LASTEXITCODE."
}

Write-Host "Driver install pass complete. Reboot if Windows asks, or if Wi-Fi/touchpad does not appear immediately." -ForegroundColor Green
