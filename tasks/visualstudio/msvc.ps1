[CmdletBinding()]
param(
    [ValidateSet('Detect','Invoke','Verify')]
    [string]$Action = 'Invoke',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

Import-Module (Join-Path $RepoRoot 'core\Setup.Detect.psm1') -Force

$linker = Find-SetupMsvcLinker
switch ($Action) {
    'Detect' { if ($linker) { Write-Host "MSVC linker found: $linker" } else { Write-Host 'MSVC linker found: False' } }
    'Verify' {
        if ($linker) {
            Write-Host "MSVC linker found: $linker"
            exit 0
        }
        Write-Host 'MSVC linker found: False'
        exit 1
    }
    default {
        if ($linker) {
            Write-Host "MSVC linker already present: $linker"
            exit 0
        }
        if (-not (Test-SetupAdmin)) {
            Write-Host 'Visual Studio/MSVC install requires Administrator.'
            exit 20
        }

        $legacyScript = Join-Path $RepoRoot 'legacy\dev\install-visualstudio-native-desktop.ps1'
        if (-not (Test-Path $legacyScript)) {
            Write-Host "Visual Studio installer script not found: $legacyScript"
            exit 1
        }

        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $legacyScript
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Visual Studio/MSVC task failed with exit code $LASTEXITCODE."
            exit 1
        }

        $linkerAfter = Find-SetupMsvcLinker
        if ($linkerAfter) {
            Write-Host "MSVC linker ready: $linkerAfter"
            exit 0
        }

        Write-Host 'Visual Studio/MSVC task completed, but link.exe was not found.'
        exit 1
    }
}
