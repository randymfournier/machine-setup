# Compatibility wrapper for the pre-framework wizard entry point.
# The real setup console is setup.ps1.

[CmdletBinding()]
param()

$setupPath = Join-Path $PSScriptRoot 'setup.ps1'
if (-not (Test-Path $setupPath)) {
    Write-Host "setup.ps1 was not found at: $setupPath" -ForegroundColor Red
    exit 1
}

& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $setupPath
exit $LASTEXITCODE
