[CmdletBinding()]
param(
    [ValidateSet('Detect','Invoke','Verify')]
    [string]$Action = 'Invoke',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

Import-Module (Join-Path $RepoRoot 'core\Setup.Detect.psm1') -Force

switch ($Action) {
    'Detect' { Write-Host "WSL installed: $(Test-SetupWslInstalled); Ubuntu-24.04 installed: $(Test-SetupWslUbuntuInstalled)" }
    'Verify' {
        $wslReady = Test-SetupWslInstalled
        Write-Host "WSL installed: $wslReady; Ubuntu-24.04 installed: $(Test-SetupWslUbuntuInstalled)"
        if ($wslReady) { exit 0 } else { exit 1 }
    }
    default {
        if (-not (Test-SetupAdmin)) {
            Write-Host 'WSL install requires Administrator.'
            exit 20
        }

        $legacyScript = Join-Path $RepoRoot 'legacy\wsl\setup-wsl.ps1'
        if (-not (Test-Path $legacyScript)) {
            Write-Host "WSL setup script not found: $legacyScript"
            exit 1
        }

        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $legacyScript
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WSL setup failed with exit code $LASTEXITCODE."
            exit 1
        }

        if (Test-SetupPendingReboot) {
            Write-Host 'WSL setup completed and Windows reports a pending reboot.'
            exit 30
        }

        Write-Host 'WSL setup completed.'
        exit 0
    }
}
