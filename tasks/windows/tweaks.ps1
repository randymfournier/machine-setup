[CmdletBinding()]
param(
    [ValidateSet('Detect','Invoke','Verify')]
    [string]$Action = 'Invoke',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

Import-Module (Join-Path $RepoRoot 'core\Setup.Detect.psm1') -Force

$ready = Test-SetupWindowsTweaksApplied
switch ($Action) {
    'Detect' { Write-Host "Windows tweaks already applied: $ready" }
    'Verify' {
        Write-Host "Windows tweaks already applied: $ready"
        if ($ready) { exit 0 } else { exit 1 }
    }
    default {
        $legacyScript = Join-Path $RepoRoot 'legacy\windows\apply-tweaks.ps1'
        if (-not (Test-Path $legacyScript)) {
            Write-Host "Windows tweaks script not found: $legacyScript"
            exit 1
        }

        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $legacyScript
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Windows tweaks failed with exit code $LASTEXITCODE."
            exit 1
        }

        Write-Host 'Windows tweaks applied.'
        exit 0
    }
}
