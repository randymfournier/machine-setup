[CmdletBinding()]
param(
    [ValidateSet('Detect','Invoke','Verify')]
    [string]$Action = 'Invoke',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

Import-Module (Join-Path $RepoRoot 'core\Setup.Detect.psm1') -Force

$hasGit = Test-SetupCommand -Name 'git'
function Invoke-NativeWithTimeout {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [Parameter(Mandatory=$true)][string]$Activity,
        [int]$TimeoutSeconds = 300
    )

    Write-Host ("> {0} {1}" -f $FilePath, ($Arguments -join ' '))
    $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -PassThru
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $process.HasExited) {
        Start-Sleep -Seconds 10
        try { $process.Refresh() } catch { }
        Write-Host ("  [{0:mm\:ss}] {1} still running..." -f $sw.Elapsed, $Activity)
        if ($sw.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            Write-Host "$Activity timed out after $TimeoutSeconds seconds."
            try { $process.Kill() } catch { }
            return 124
        }
    }

    return $process.ExitCode
}

switch ($Action) {
    'Detect' { Write-Host "git available: $hasGit" }
    'Verify' {
        Write-Host "git available: $hasGit"
        if ($hasGit) { exit 0 } else { exit 1 }
    }
    default {
        if ($hasGit) {
            Write-Host 'Git already available.'
            exit 0
        }

        $installerCandidates = @(
            (Join-Path $RepoRoot 'installers\Git-64-bit.exe'),
            (Join-Path $RepoRoot 'installers\Git.exe')
        )

        $localInstaller = $installerCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($localInstaller) {
            Write-Host "Installing Git from local installer: $localInstaller"
            $args = @('/VERYSILENT','/NORESTART','/NOCANCEL','/SP-')
            $p = Start-Process -FilePath $localInstaller -ArgumentList $args -Wait -PassThru
            if ($p.ExitCode -ne 0) {
                Write-Host "Local Git installer failed with exit code $($p.ExitCode)."
                exit 1
            }
        } elseif (Test-SetupWingetHealthy) {
            Write-Host 'Installing Git via winget.'
            $exitCode = Invoke-NativeWithTimeout -FilePath 'winget' -Arguments @('install','--id','Git.Git','-e','--source','winget','--accept-package-agreements','--accept-source-agreements','--disable-interactivity') -Activity 'winget install Git' -TimeoutSeconds 300
            if ($exitCode -ne 0) {
                Write-Host "winget install Git.Git failed with exit code $exitCode."
                exit 1
            }
        } else {
            Write-Host 'Git is missing and no install source is available.'
            exit 20
        }

        $machinePath = [System.Environment]::GetEnvironmentVariable('Path','Machine')
        $userPath = [System.Environment]::GetEnvironmentVariable('Path','User')
        $env:Path = @($machinePath, $userPath) -join ';'

        if (Test-SetupCommand -Name 'git') {
            Write-Host 'Git installed and available.'
            exit 0
        }

        Write-Host 'Git install completed, but git is not available on PATH yet.'
        exit 1
    }
}
