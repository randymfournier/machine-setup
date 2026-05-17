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

$installerPath = Join-Path $RepoRoot 'assets\installers\ScreenRec_webinstall_all.exe'

function Find-ScreenRecInstall {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'ScreenRec\ScreenRec.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'ScreenRec\ScreenRec.exe'),
        (Join-Path $env:LOCALAPPDATA 'StreamingVideoProvider\ScreenRec\ScreenRec.exe'),
        (Join-Path $env:LOCALAPPDATA 'ScreenRec\ScreenRec.exe'),
        (Join-Path $env:APPDATA 'ScreenRec\ScreenRec.exe')
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }

    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($root in $uninstallRoots) {
        $entry = Get-ItemProperty -Path $root -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match 'ScreenRec' } |
            Select-Object -First 1
        if ($entry) { return $entry.DisplayName }
    }

    return $null
}

function Invoke-ScreenRecInstaller {
    Write-Host "Starting ScreenRec silent installer: $installerPath" -ForegroundColor Cyan

    $process = Start-Process -FilePath $installerPath -ArgumentList '/S' -Wait -NoNewWindow -PassThru
    Write-Host "ScreenRec installer finished with exit code $($process.ExitCode)." -ForegroundColor Cyan
    return $process.ExitCode
}

$installed = Find-ScreenRecInstall
$installerPresent = Test-Path $installerPath

switch ($Action) {
    'Detect' {
        if ($installed) {
            Write-Host "ScreenRec installed: $installed"
        } else {
            Write-Host "ScreenRec installed: False; installer present: $installerPresent"
        }
    }
    'Verify' {
        $installed = Find-ScreenRecInstall
        if ($installed) {
            Write-Host "ScreenRec installed: $installed"
            exit 0
        }

        Write-Host 'ScreenRec installed: False'
        exit 1
    }
    default {
        if ($installed) {
            Write-Host "ScreenRec already installed: $installed"
            exit 0
        }

        if (-not $installerPresent) {
            Write-Host "ScreenRec installer not found: $installerPath"
            Write-Host 'Skipping ScreenRec install. Put ScreenRec_webinstall_all.exe in assets\installers and rerun this task.'
            exit 10
        }

        $exitCode = Invoke-ScreenRecInstaller
        if ($exitCode -ne 0) {
            Write-Host "ScreenRec installer failed with exit code $exitCode."
            exit 1
        }

        $installedAfter = Find-ScreenRecInstall
        if ($installedAfter) {
            Write-Host "ScreenRec installed: $installedAfter"
            exit 0
        }

        Write-Host 'ScreenRec installer completed, but ScreenRec was not detected.'
        exit 1
    }
}
