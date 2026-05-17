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

$officeRoot = Join-Path $RepoRoot 'assets\office'
$setupExe = Join-Path $officeRoot 'setup.exe'
$configurationXml = Join-Path $officeRoot 'configuration.xml'
$odtDownloadUrl = 'https://go.microsoft.com/fwlink/?linkid=2244703'

function Test-OfficeInstalled {
    $clickToRun = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    if (Test-Path $clickToRun) {
        $config = Get-ItemProperty -Path $clickToRun -ErrorAction SilentlyContinue
        if ($config -and ($config.ProductReleaseIds -or $config.ClientVersionToReport)) {
            return $true
        }
    }

    $office16 = Join-Path ${env:ProgramFiles} 'Microsoft Office\root\Office16\WINWORD.EXE'
    $office16x86 = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Office\root\Office16\WINWORD.EXE'
    return ((Test-Path $office16) -or (Test-Path $office16x86))
}

function Invoke-OfficeDeploymentCommand {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('download','configure')][string]$Mode
    )

    $arguments = @("/$Mode", $configurationXml)
    Write-Host ("Starting Office {0}: `"{1}`" {2}" -f $Mode, $setupExe, ($arguments -join ' ')) -ForegroundColor Cyan

    $process = Start-Process -FilePath $setupExe -ArgumentList $arguments -WorkingDirectory $officeRoot -PassThru
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    while (-not $process.HasExited) {
        Start-Sleep -Seconds 30
        try { $process.Refresh() } catch { }
        Write-Host ("Office {0} still running... elapsed {1:hh\:mm\:ss}" -f $Mode, $sw.Elapsed) -ForegroundColor DarkGray
    }

    $sw.Stop()
    Write-Host ("Office {0} finished in {1:hh\:mm\:ss} with exit code {2}." -f $Mode, $sw.Elapsed, $process.ExitCode) -ForegroundColor Cyan
    return $process.ExitCode
}

function Install-OfficeDeploymentTool {
    if (Test-Path $setupExe) { return $true }

    if (-not (Test-Path $officeRoot)) {
        New-Item -ItemType Directory -Path $officeRoot -Force | Out-Null
    }

    $tempRoot = Join-Path $env:TEMP 'machine-setup-installs'
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $odtInstaller = Join-Path $tempRoot 'officedeploymenttool.exe'

    Write-Host 'Office Deployment Tool setup.exe was not found. Downloading ODT...' -ForegroundColor Cyan
    Write-Host "  $odtDownloadUrl" -ForegroundColor DarkGray

    $oldProgress = $ProgressPreference
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $odtDownloadUrl -OutFile $odtInstaller -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Host "Office Deployment Tool download failed: $($_.Exception.Message)"
        return $false
    } finally {
        if ($null -ne $oldProgress) { $ProgressPreference = $oldProgress }
    }

    Write-Host "Extracting Office Deployment Tool to: $officeRoot" -ForegroundColor Cyan
    $process = Start-Process -FilePath $odtInstaller -ArgumentList @('/quiet', "/extract:$officeRoot") -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        Write-Host "Office Deployment Tool extraction failed with exit code $($process.ExitCode)."
        return $false
    }

    return (Test-Path $setupExe)
}

$hasSetup = Test-Path $setupExe
$hasConfig = Test-Path $configurationXml
$installed = Test-OfficeInstalled

switch ($Action) {
    'Detect' {
        Write-Host "Office installed: $installed; ODT setup.exe present: $hasSetup; configuration.xml present: $hasConfig"
    }
    'Verify' {
        $installed = Test-OfficeInstalled
        Write-Host "Office installed: $installed"
        if ($installed) { exit 0 } else { exit 1 }
    }
    default {
        if ($installed) {
            Write-Host 'Office already appears to be installed.'
            exit 0
        }

        if (-not $hasSetup) {
            if (-not (Install-OfficeDeploymentTool)) {
                Write-Host "Office Deployment Tool setup.exe not found: $setupExe"
                Write-Host 'Office install cannot continue without ODT setup.exe.'
                exit 10
            }
            $hasSetup = Test-Path $setupExe
        }

        if (-not $hasConfig) {
            Write-Host "Office configuration.xml not found: $configurationXml"
            exit 1
        }

        $downloadExit = Invoke-OfficeDeploymentCommand -Mode 'download'
        if ($downloadExit -ne 0) {
            Write-Host "Office download failed with exit code $downloadExit."
            exit 1
        }

        $configureExit = Invoke-OfficeDeploymentCommand -Mode 'configure'
        if ($configureExit -ne 0) {
            Write-Host "Office install failed with exit code $configureExit."
            exit 1
        }

        Write-Host 'Office deployment completed.'
        exit 0
    }
}
