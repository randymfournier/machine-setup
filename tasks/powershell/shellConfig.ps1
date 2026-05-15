[CmdletBinding()]
param(
    [ValidateSet('Detect','Invoke','Verify')]
    [string]$Action = 'Invoke',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

$starship = Join-Path $env:USERPROFILE '.config\starship.toml'
switch ($Action) {
    'Detect' { Write-Host "PowerShell profile exists: $(Test-Path $PROFILE); starship config exists: $(Test-Path $starship)" }
    'Verify' {
        $ready = ((Test-Path $PROFILE) -and (Test-Path $starship))
        Write-Host "Shell config ready: $ready"
        if ($ready) { exit 0 } else { exit 1 }
    }
    default {
        $sourceProfile = Join-Path $RepoRoot 'assets\shell\Microsoft.PowerShell_profile.ps1'
        $sourceStarship = Join-Path $RepoRoot 'assets\shell\starship.toml'
        $sourceTerminal = Join-Path $RepoRoot 'assets\shell\windows-terminal-settings.json'

        if (-not (Test-Path $sourceProfile) -or -not (Test-Path $sourceStarship)) {
            Write-Host 'Shell config source files are missing.'
            exit 1
        }

        $profileDir = Split-Path -Parent $PROFILE
        if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
        Copy-Item -Path $sourceProfile -Destination $PROFILE -Force

        New-Item -ItemType Directory -Path (Split-Path -Parent $starship) -Force | Out-Null
        Copy-Item -Path $sourceStarship -Destination $starship -Force

        $wtSettings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
        if ((Test-Path (Split-Path -Parent $wtSettings)) -and (Test-Path $sourceTerminal)) {
            Copy-Item -Path $sourceTerminal -Destination $wtSettings -Force
        }

        Write-Host 'PowerShell profile and Starship config copied.'
        exit 0
    }
}
