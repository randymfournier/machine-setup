[CmdletBinding()]
param(
    [ValidateSet('Detect','Invoke','Verify')]
    [string]$Action = 'Invoke',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

Import-Module (Join-Path $RepoRoot 'core\Setup.Detect.psm1') -Force

$healthy = Test-SetupWingetHealthy
switch ($Action) {
    'Detect' { Write-Host "winget healthy: $healthy" }
    'Verify' {
        Write-Host "winget healthy: $healthy"
        if ($healthy) { exit 0 } else { exit 1 }
    }
    default {
        if (-not (Test-SetupAdmin)) {
            Write-Host 'winget repair requires Administrator.'
            exit 20
        }

        $bootstrap = Join-Path $RepoRoot 'legacy\bootstrap.ps1'
        if (-not (Test-Path $bootstrap)) {
            Write-Host "bootstrap.ps1 not found: $bootstrap"
            exit 1
        }

        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $bootstrap -Only winget-repair
        if ($LASTEXITCODE -ne 0) {
            Write-Host "winget repair failed with exit code $LASTEXITCODE."
            exit 1
        }

        Write-Host 'winget repair completed.'
        exit 0
    }
}
