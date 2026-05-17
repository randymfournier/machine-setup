[CmdletBinding()]
param(
    [ValidateSet('Detect','Invoke','Verify')]
    [string]$Action = 'Invoke',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

Import-Module (Join-Path $RepoRoot 'core\Setup.Detect.psm1') -Force

$policy = Get-SetupPowerShellExecutionPolicy
$effectivePolicy = Get-SetupPowerShellEffectiveExecutionPolicy
switch ($Action) {
    'Detect' { Write-Host "CurrentUser policy: $policy; effective policy: $effectivePolicy" }
    'Verify' {
        $ready = Test-SetupPowerShellPolicyReady
        Write-Host "Policy ready: $ready"
        if ($ready) { exit 0 } else { exit 1 }
    }
    default {
        if (Test-SetupPowerShellPolicyReady) {
            Write-Host "PowerShell execution policy is compatible. CurrentUser: $policy; effective: $effectivePolicy"
            exit 0
        }

        try {
            Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
            Write-Host 'PowerShell CurrentUser execution policy set to RemoteSigned.'
            exit 0
        } catch {
            $effectivePolicy = Get-SetupPowerShellEffectiveExecutionPolicy
            if ($effectivePolicy -in @('RemoteSigned','Unrestricted','Bypass')) {
                Write-Host "Could not persist PowerShell CurrentUser execution policy: $($_.Exception.Message)"
                Write-Host "Continuing because this setup session is already allowed by effective policy: $effectivePolicy"
                exit 0
            }

            Write-Host "Could not set PowerShell CurrentUser execution policy: $($_.Exception.Message)"
            exit 1
        }
    }
}
