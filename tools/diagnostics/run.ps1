[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

Import-Module (Join-Path $RepoRoot 'core\Setup.Detect.psm1') -Force

$snapshot = Get-SetupDetectionSnapshot -RepoRoot $RepoRoot

Write-Host 'machine-setup diagnostics' -ForegroundColor Green
Write-Host '=========================' -ForegroundColor Green
Write-Host ''
Write-Host ("Repo:                 {0}" -f $RepoRoot)
Write-Host ("Admin:                {0}" -f $snapshot.admin)
Write-Host ("Network:              {0}" -f $snapshot.network)
Write-Host ("Pending reboot:       {0}" -f $snapshot.pendingReboot)
Write-Host ("Exported drivers:     {0}" -f $snapshot.exportedDriverFolder)
Write-Host ("winget healthy:       {0}" -f $snapshot.wingetHealthy)
Write-Host ("Git:                  {0}" -f $snapshot.git)
Write-Host ("MSVC linker:          {0}" -f $snapshot.msvcLinker)
Write-Host ("PowerShell policy:    {0}" -f $snapshot.powershellPolicy)
Write-Host ("VS Code CLI:          {0}" -f $snapshot.vscodeCli)
Write-Host ("WSL:                  {0}" -f $snapshot.wsl)
Write-Host ("Ubuntu-24.04:         {0}" -f $snapshot.ubuntu2404)
Write-Host ("Windows tweaks:       {0}" -f $snapshot.windowsTweaksApplied)
Write-Host ''
Write-Host 'Toolchains:' -ForegroundColor Cyan
foreach ($name in @('fnm','node','npm','rustup','cargo','uv','python','go')) {
    Write-Host ("  {0,-8} {1}" -f $name, $snapshot.$name)
}

$statePath = Join-Path $RepoRoot 'state\setup-state.json'
Write-Host ''
Write-Host ("State file exists:    {0}" -f (Test-Path $statePath))
Write-Host ("Logs folder:          {0}" -f (Join-Path $RepoRoot 'logs'))
exit 0
