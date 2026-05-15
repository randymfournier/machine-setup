[CmdletBinding()]
param(
    [ValidateSet('Detect','Invoke','Verify')]
    [string]$Action = 'Invoke',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

Import-Module (Join-Path $RepoRoot 'core\Setup.Detect.psm1') -Force

$policy = Get-SetupPowerShellExecutionPolicy
switch ($Action) {
    'Detect' { Write-Host "CurrentUser policy: $policy" }
    'Verify' {
        $ready = Test-SetupPowerShellPolicyReady
        Write-Host "Policy ready: $ready"
        if ($ready) { exit 0 } else { exit 1 }
    }
    default {
        if (Test-SetupPowerShellPolicyReady) {
            Write-Host "PowerShell CurrentUser execution policy is already compatible: $policy"
            exit 0
        }

        try {
            Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
            Write-Host 'PowerShell CurrentUser execution policy set to RemoteSigned.'
            exit 0
        } catch {
            Write-Host "Could not set PowerShell CurrentUser execution policy: $($_.Exception.Message)"
            exit 1
        }
    }
}
