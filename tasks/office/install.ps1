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
            Write-Host "Office Deployment Tool setup.exe not found: $setupExe"
            Write-Host 'Skipping Office install. Put setup.exe in assets\office and rerun this task.'
            exit 10
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
