[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

$script = Join-Path $RepoRoot 'legacy\usb\prepare-recovery-usb.ps1'
if (-not (Test-Path $script)) {
    Write-Host "Recovery USB prepare script not found: $script" -ForegroundColor Red
    exit 1
}

& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script
exit $LASTEXITCODE
