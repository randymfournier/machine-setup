[CmdletBinding()]
param(
    [ValidateSet('Detect','Invoke','Verify')]
    [string]$Action = 'Invoke',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

switch ($Action) {
    'Detect' { Write-Host 'debloat is optional and has no safe global already-done detector yet' }
    'Verify' {
        Write-Host 'debloat verification is best-effort; optional task completed if script exited successfully'
        exit 0
    }
    default {
        if (-not (Test-SetupAdmin)) {
            Write-Host 'Debloat requires Administrator.'
            exit 20
        }

        $script = Join-Path $RepoRoot 'legacy\windows\debloat.ps1'
        if (-not (Test-Path $script)) {
            $script = Join-Path $RepoRoot 'legacy\debloat.ps1'
        }
        if (-not (Test-Path $script)) {
            Write-Host 'Debloat script was not found.'
            exit 1
        }

        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Debloat failed with exit code $LASTEXITCODE."
            exit 1
        }

        Write-Host 'Debloat completed.'
        exit 0
    }
}
