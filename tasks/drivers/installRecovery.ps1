[CmdletBinding()]
param(
    [ValidateSet('Detect','Invoke','Verify')]
    [string]$Action = 'Invoke',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

Import-Module (Join-Path $RepoRoot 'core\Setup.Detect.psm1') -Force

$folder = Find-SetupExportedDriverFolder -RepoRoot $RepoRoot
switch ($Action) {
    'Detect' { if ($folder) { Write-Host "Ready: exported drivers found at $($folder.FullName)" } else { Write-Host 'Skipped: no exported recovery driver folder found' } }
    'Verify' {
        if ($folder) {
            Write-Host "Detected: exported drivers remain available at $($folder.FullName)"
            exit 0
        }
        Write-Host 'No exported recovery drivers detected'
        exit 1
    }
    default {
        if (-not $folder) {
            Write-Host 'No exported recovery driver folder found. Skipping recovery driver install.'
            exit 10
        }

        $legacyScript = Join-Path $RepoRoot 'legacy\drivers\install-exported-drivers.ps1'
        if (-not (Test-Path $legacyScript)) {
            Write-Host "Driver installer script not found: $legacyScript"
            exit 1
        }

        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $legacyScript -Source $folder.FullName
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Recovery driver install failed with exit code $LASTEXITCODE."
            exit 1
        }

        Write-Host "Recovery driver install completed from $($folder.FullName)."
        exit 0
    }
}
