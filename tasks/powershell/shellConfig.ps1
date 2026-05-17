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

$ompConfig = Join-Path $env:USERPROFILE '.config\oh-my-posh\blueish.omp.json'
$profileTargets = @(
    $PROFILE,
    (Join-Path $env:USERPROFILE 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'),
    (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1')
) | Select-Object -Unique

switch ($Action) {
    'Detect' {
        $profileCount = @($profileTargets | Where-Object { Test-Path $_ }).Count
        Write-Host "PowerShell profiles present: $profileCount/$($profileTargets.Count); oh-my-posh config exists: $(Test-Path $ompConfig)"
    }
    'Verify' {
        $ready = ((@($profileTargets | Where-Object { Test-Path $_ }).Count -eq $profileTargets.Count) -and (Test-Path $ompConfig))
        Write-Host "Shell config ready: $ready"
        if ($ready) { exit 0 } else { exit 1 }
    }
    default {
        $sourceProfile = Join-Path $RepoRoot 'assets\shell\Microsoft.PowerShell_profile.ps1'
        $sourceOmpConfig = Join-Path $RepoRoot 'assets\shell\blueish.omp.json'
        $sourceTerminal = Join-Path $RepoRoot 'assets\shell\windows-terminal-settings.json'

        if (-not (Test-Path $sourceProfile) -or -not (Test-Path $sourceOmpConfig)) {
            Write-Host 'Shell config source files are missing.'
            exit 1
        }

        foreach ($profileTarget in $profileTargets) {
            $profileDir = Split-Path -Parent $profileTarget
            if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
            Copy-Item -Path $sourceProfile -Destination $profileTarget -Force
        }

        New-Item -ItemType Directory -Path (Split-Path -Parent $ompConfig) -Force | Out-Null
        Copy-Item -Path $sourceOmpConfig -Destination $ompConfig -Force

        $wtSettings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
        if ((Test-Path (Split-Path -Parent $wtSettings)) -and (Test-Path $sourceTerminal)) {
            Copy-Item -Path $sourceTerminal -Destination $wtSettings -Force
        }

        Write-Host 'PowerShell profiles and oh-my-posh config copied.'
        exit 0
    }
}
