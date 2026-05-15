[CmdletBinding()]
param(
    [ValidateSet('Detect','Invoke','Verify')]
    [string]$Action = 'Invoke',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

Import-Module (Join-Path $RepoRoot 'core\Setup.Detect.psm1') -Force

$manifestPath = Join-Path $RepoRoot 'assets\packages\winget-packages.json'
switch ($Action) {
    'Detect' { Write-Host "apps manifest exists: $(Test-Path $manifestPath); winget healthy: $(Test-SetupWingetHealthy)" }
    'Verify' {
        $ready = ((Test-Path $manifestPath) -and (Test-SetupWingetHealthy))
        Write-Host "apps task prerequisites ready: $ready"
        if ($ready) { exit 0 } else { exit 1 }
    }
    default {
        if (-not (Test-Path $manifestPath)) {
            Write-Host "App manifest not found: $manifestPath"
            exit 1
        }
        if (-not (Test-SetupWingetHealthy)) {
            Write-Host 'winget is not healthy enough to install apps.'
            exit 20
        }

        $bootstrap = Join-Path $RepoRoot 'legacy\bootstrap.ps1'
        if (-not (Test-Path $bootstrap)) {
            Write-Host "bootstrap.ps1 not found: $bootstrap"
            exit 1
        }

        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $bootstrap -Only winget
        if ($LASTEXITCODE -ne 0) {
            Write-Host "App install pass failed with exit code $LASTEXITCODE."
            exit 1
        }

        Write-Host 'App install pass completed.'
        exit 0
    }
}
