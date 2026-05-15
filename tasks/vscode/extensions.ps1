[CmdletBinding()]
param(
    [ValidateSet('Detect','Invoke','Verify')]
    [string]$Action = 'Invoke',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

Import-Module (Join-Path $RepoRoot 'core\Setup.Detect.psm1') -Force

$list = Join-Path $RepoRoot 'legacy\dev\vscode-extensions.txt'
switch ($Action) {
    'Detect' { Write-Host "code CLI: $(Test-SetupVscodeCli); extension list exists: $(Test-Path $list)" }
    'Verify' {
        $ready = ((Test-SetupVscodeCli) -and (Test-Path $list))
        Write-Host "VS Code extension task ready: $ready"
        if ($ready) { exit 0 } else { exit 1 }
    }
    default {
        if (-not (Test-Path $list)) {
            Write-Host "VS Code extension list not found: $list"
            exit 1
        }
        if (-not (Test-SetupVscodeCli)) {
            Write-Host 'code CLI is not on PATH yet. Open VS Code once, then rerun this task.'
            exit 20
        }

        $failures = New-Object System.Collections.Generic.List[string]
        $extensions = @(Get-Content -Path $list -ErrorAction Stop | Where-Object { $_ -and -not $_.Trim().StartsWith('#') })
        foreach ($extension in $extensions) {
            $id = $extension.Trim()
            if (-not $id) { continue }
            Write-Host "Installing VS Code extension: $id"
            & code --install-extension $id --force
            if ($LASTEXITCODE -ne 0) {
                $failures.Add($id) | Out-Null
                Write-Host "Extension install failed: $id"
            }
        }

        if ($failures.Count -gt 0) {
            Write-Host "VS Code extension failures: $($failures -join ', ')"
            exit 1
        }

        Write-Host 'VS Code extensions installed.'
        exit 0
    }
}
