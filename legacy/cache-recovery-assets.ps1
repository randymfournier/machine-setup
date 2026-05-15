# cache-recovery-assets.ps1
# Run on a working machine before a wipe/reinstall.
# Downloads the tiny bootstrappers/assets that fresh Windows may fail to fetch
# during first-run setup.

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$RepoRoot = Split-Path -Parent $PSScriptRoot
$InstallerDir = Join-Path $RepoRoot 'assets\installers'
New-Item -ItemType Directory -Path $InstallerDir -Force | Out-Null

function Download-Asset {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Uri,
        [Parameter(Mandatory=$true)][string]$OutFile
    )

    Write-Host "Downloading $Name..." -ForegroundColor Cyan
    Write-Host "  $Uri" -ForegroundColor DarkGray
    Write-Host "  -> $OutFile" -ForegroundColor DarkGray

    $oldProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
    } finally {
        $ProgressPreference = $oldProgress
    }

    $sizeMb = [math]::Round((Get-Item $OutFile).Length / 1MB, 2)
    Write-Host "[OK] $Name cached ($sizeMb MB)" -ForegroundColor Green
}

Download-Asset `
    -Name 'Visual Studio Build Tools bootstrapper' `
    -Uri 'https://aka.ms/vs/17/release/vs_BuildTools.exe' `
    -OutFile (Join-Path $InstallerDir 'vs_BuildTools.exe')

Download-Asset `
    -Name 'App Installer / winget msixbundle' `
    -Uri 'https://aka.ms/getwinget' `
    -OutFile (Join-Path $InstallerDir 'winget.msixbundle')

Write-Host ""
Write-Host "Recovery assets cached in:" -ForegroundColor Green
Write-Host "  $InstallerDir"
Write-Host ""
Write-Host "Copy this repo folder to your recovery USB after this finishes." -ForegroundColor Cyan
