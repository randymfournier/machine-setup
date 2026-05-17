[CmdletBinding()]
param(
    [string]$RepoRoot
)

if (-not $RepoRoot) {
    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    if (-not $scriptRoot) { $scriptRoot = (Get-Location).Path }
    $RepoRoot = (Resolve-Path (Join-Path $scriptRoot '..\..')).Path
}

$script = Join-Path $RepoRoot 'legacy\drivers\export-selected-drivers.ps1'
$destination = Join-Path $RepoRoot ("drivers\exported-selected-{0}" -f (Get-Date -Format 'yyyy-MM-dd'))
if (-not (Test-Path $script)) {
    Write-Host "Driver export script not found: $script" -ForegroundColor Red
    exit 1
}

& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script -Destination $destination
exit $LASTEXITCODE
