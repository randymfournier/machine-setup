[CmdletBinding()]
param(
    [ValidateSet('Detect','Invoke','Verify')]
    [string]$Action = 'Invoke',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

$gitConfig = Join-Path $env:USERPROFILE '.gitconfig'
$gitIgnore = Join-Path $env:USERPROFILE '.gitignore_global'
switch ($Action) {
    'Detect' { Write-Host "user .gitconfig exists: $(Test-Path $gitConfig); global ignore exists: $(Test-Path $gitIgnore)" }
    'Verify' {
        $ready = ((Test-Path $gitConfig) -and (Test-Path $gitIgnore))
        Write-Host "Git config ready: $ready"
        if ($ready) { exit 0 } else { exit 1 }
    }
    default {
        $sourceConfig = Join-Path $RepoRoot 'assets\git\.gitconfig'
        $sourceIgnore = Join-Path $RepoRoot 'assets\git\.gitignore_global'
        if (-not (Test-Path $sourceConfig) -or -not (Test-Path $sourceIgnore)) {
            Write-Host 'Git config template files are missing.'
            exit 1
        }

        Copy-Item -Path $sourceConfig -Destination $gitConfig -Force
        Copy-Item -Path $sourceIgnore -Destination $gitIgnore -Force
        Write-Host "Git config templates copied to $env:USERPROFILE."
        exit 0
    }
}
