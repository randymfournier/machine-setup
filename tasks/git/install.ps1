[CmdletBinding()]
param(
    [ValidateSet('Detect','Invoke','Verify')]
    [string]$Action = 'Invoke',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

Import-Module (Join-Path $RepoRoot 'core\Setup.Detect.psm1') -Force

$hasGit = Test-SetupCommand -Name 'git'
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
            & winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity
            if ($LASTEXITCODE -ne 0) {
                Write-Host "winget install Git.Git failed with exit code $LASTEXITCODE."
                exit 1
            }
        } elseif (Test-SetupNetwork) {
            $tempRoot = Join-Path $env:TEMP 'machine-setup-installs'
            New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
            $installer = Join-Path $tempRoot 'Git-64-bit.exe'
            $uri = 'https://github.com/git-for-windows/git/releases/latest/download/Git-64-bit.exe'
            Write-Host "Downloading Git installer: $uri"
            $oldProgress = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'
            try {
                Invoke-WebRequest -Uri $uri -OutFile $installer -UseBasicParsing -ErrorAction Stop
            } catch {
                Write-Host "Git download failed: $($_.Exception.Message)"
                exit 1
            } finally {
                $ProgressPreference = $oldProgress
            }

            $p = Start-Process -FilePath $installer -ArgumentList @('/VERYSILENT','/NORESTART','/NOCANCEL','/SP-') -Wait -PassThru
            if ($p.ExitCode -ne 0) {
                Write-Host "Downloaded Git installer failed with exit code $($p.ExitCode)."
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
