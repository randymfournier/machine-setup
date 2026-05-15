[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$UsbRoot
)

function Select-ValidationRoot {
    $choice = (Read-Host 'USB/root path to validate, for example E:\').Trim()
    if (-not $choice) { throw 'No validation path supplied.' }
    return $choice
}

if (-not $UsbRoot) {
    $UsbRoot = Select-ValidationRoot
}

if (-not (Test-Path $UsbRoot)) {
    Write-Host "Path does not exist: $UsbRoot" -ForegroundColor Red
    exit 1
}

$root = (Resolve-Path $UsbRoot).Path
$required = @(
    'README-FIRST.txt',
    '_START_HERE.cmd',
    'machine-setup\quickstart-local.ps1',
    'machine-setup\setup.ps1',
    'machine-setup\setup.json',
    'machine-setup\core\Setup.Engine.psm1'
)

$missing = @()
foreach ($relative in $required) {
    $path = Join-Path $root $relative
    if (Test-Path $path) {
        Write-Host "[OK] $relative" -ForegroundColor Green
    } else {
        Write-Host "[MISSING] $relative" -ForegroundColor Yellow
        $missing += $relative
    }
}

$driverFolders = @(Get-ChildItem -Path (Join-Path $root 'machine-setup\drivers') -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'exported-*' })
$installers = @(Get-ChildItem -Path (Join-Path $root 'machine-setup\installers') -File -ErrorAction SilentlyContinue)

Write-Host ''
Write-Host ("Exported driver folders: {0}" -f $driverFolders.Count) -ForegroundColor Cyan
Write-Host ("Cached installers:        {0}" -f $installers.Count) -ForegroundColor Cyan

if ($missing.Count -gt 0) {
    Write-Host ''
    Write-Host "Recovery USB validation failed: $($missing.Count) required item(s) missing." -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host 'Recovery USB validation passed.' -ForegroundColor Green
exit 0
