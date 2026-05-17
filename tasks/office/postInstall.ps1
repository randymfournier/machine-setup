[CmdletBinding()]
param(
    [ValidateSet('Detect','Invoke','Verify')]
    [string]$Action = 'Invoke',
    [string]$RepoRoot
)

if (-not $RepoRoot) {
    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    if (-not $scriptRoot) { $scriptRoot = (Get-Location).Path }
    $RepoRoot = (Resolve-Path (Join-Path $scriptRoot '..\..')).Path
}

$localPostInstallScript = Join-Path $RepoRoot 'assets\office\postInstall.local.ps1'

switch ($Action) {
    'Detect' {
        Write-Host "Office post-install script present: $(Test-Path $localPostInstallScript)"
    }
    'Verify' {
        Write-Host 'Office post-install step is optional; no verification required.'
        exit 0
    }
    default {
        if (-not (Test-Path $localPostInstallScript)) {
            Write-Host "Optional Office post-install script not found: $localPostInstallScript"
            Write-Host 'Skipping Office post-install step.'
            exit 0
        }

        Write-Host "Running Office post-install script: $localPostInstallScript"
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $localPostInstallScript
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Office post-install script failed with exit code $LASTEXITCODE."
            exit 1
        }

        Write-Host 'Office post-install script completed.'
        exit 0
    }
}
