[CmdletBinding()]
param(
    [ValidateSet('Detect','Invoke','Verify')]
    [string]$Action = 'Invoke',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

Import-Module (Join-Path $RepoRoot 'core\Setup.Detect.psm1') -Force

$items = @('fnm','node','npm','rustup','cargo','uv','python','go')
$present = @($items | Where-Object { Test-SetupCommand -Name $_ })
switch ($Action) {
    'Detect' { Write-Host "toolchains present: $($present -join ', ')" }
    'Verify' {
        $required = @('fnm','node','npm','rustup','cargo','uv','go')
        $missing = @($required | Where-Object { -not (Test-SetupCommand -Name $_) })
        if ($missing.Count -eq 0) {
            Write-Host 'Required toolchains ready.'
            exit 0
        }
        Write-Host "Missing toolchains: $($missing -join ', ')"
        exit 1
    }
    default {
        if (-not (Test-SetupAdmin)) {
            Write-Host 'Toolchain install requires Administrator.'
            exit 20
        }

        $legacyScript = Join-Path $RepoRoot 'legacy\dev\install-toolchains.ps1'
        if (-not (Test-Path $legacyScript)) {
            Write-Host "Toolchain installer script not found: $legacyScript"
            exit 1
        }

        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $legacyScript
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Toolchain install failed with exit code $LASTEXITCODE."
            exit 1
        }

        Write-Host 'Toolchain install completed.'
        exit 0
    }
}
