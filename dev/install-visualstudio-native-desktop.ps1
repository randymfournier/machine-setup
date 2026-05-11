# dev/install-visualstudio-native-desktop.ps1
# Ensures the MSVC linker required by Rust/Tauri native builds is installed.
# This fixes the common first-run error:
#   error: linker link.exe not found
#
# Preferred result:
#   Visual Studio / Build Tools has the Desktop development with C++ workload.
#
# Important:
#   This script does NOT depend on winget. If winget/msstore sources are broken,
#   it can still download the Visual Studio Build Tools bootstrapper directly.

$ErrorActionPreference = 'Stop'

$WorkloadId = 'Microsoft.VisualStudio.Workload.NativeDesktop'
$VcToolsComponentId = 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
$VsInstallerDir = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer'
$SetupExe = Join-Path $VsInstallerDir 'setup.exe'
$VsWhereExe = Join-Path $VsInstallerDir 'vswhere.exe'
$TempRoot = Join-Path $env:TEMP 'machine-setup-installs'
$BuildToolsBootstrapper = Join-Path $TempRoot 'vs_BuildTools.exe'
$BuildToolsUrl = 'https://aka.ms/vs/17/release/vs_BuildTools.exe'

New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null

function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable('Path','Machine')
    $userPath = [System.Environment]::GetEnvironmentVariable('Path','User')
    $env:Path = @($machinePath, $userPath) -join ';'
}

function Format-Elapsed {
    param([Parameter(Mandatory=$true)][TimeSpan]$Elapsed)
    if ($Elapsed.TotalHours -ge 1) {
        return ('{0:00}:{1:00}:{2:00}' -f [int]$Elapsed.TotalHours, $Elapsed.Minutes, $Elapsed.Seconds)
    }
    return ('{0:00}:{1:00}' -f $Elapsed.Minutes, $Elapsed.Seconds)
}

function Invoke-ProcessWithHeartbeat {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string]$ArgumentList,
        [Parameter(Mandatory=$true)][string]$Activity,
        [int]$HeartbeatSeconds = 15
    )

    Write-Host "Starting: $Activity" -ForegroundColor Cyan
    Write-Host "> `"$FilePath`" $ArgumentList" -ForegroundColor DarkGray

    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $tick = 0

    while (-not $process.HasExited) {
        Start-Sleep -Seconds $HeartbeatSeconds
        $tick++
        $elapsed = Format-Elapsed -Elapsed $sw.Elapsed
        $percent = ($tick * 7) % 95
        Write-Progress -Activity $Activity -Status "Still running... elapsed $elapsed" -PercentComplete $percent
        Write-Host "  [$elapsed] $Activity still running..." -ForegroundColor DarkGray
        try { $process.Refresh() } catch { }
    }

    $sw.Stop()
    Write-Progress -Activity $Activity -Completed

    $elapsedFinal = Format-Elapsed -Elapsed $sw.Elapsed
    Write-Host "Finished: $Activity in $elapsedFinal with exit code $($process.ExitCode)." -ForegroundColor Cyan

    return $process.ExitCode
}

function Get-VisualStudioInstallPaths {
    $paths = @()

    if (Test-Path $VsWhereExe) {
        $raw = & $VsWhereExe -products * -property installationPath 2>$null
        if ($raw) {
            $paths += @($raw | Where-Object { $_ -and (Test-Path $_) })
        }
    }

    $commonRoot = Join-Path ${env:ProgramFiles} 'Microsoft Visual Studio\2022'
    if (Test-Path $commonRoot) {
        $paths += Get-ChildItem -Path $commonRoot -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
    }

    $x86Root = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\2022'
    if (Test-Path $x86Root) {
        $paths += Get-ChildItem -Path $x86Root -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
    }

    $paths | Select-Object -Unique
}

function Find-MsvcLinker {
    $candidates = @()

    if (Test-Path $VsWhereExe) {
        $installPaths = & $VsWhereExe -products * -requires $VcToolsComponentId -property installationPath 2>$null
        foreach ($installPath in $installPaths) {
            if ($installPath -and (Test-Path $installPath)) {
                $pattern = Join-Path $installPath 'VC\Tools\MSVC\*\bin\Hostx64\x64\link.exe'
                $candidates += Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
            }
        }
    }

    $fallbackPatterns = @(
        (Join-Path ${env:ProgramFiles} 'Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\bin\Hostx64\x64\link.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\bin\Hostx64\x64\link.exe')
    )

    foreach ($pattern in $fallbackPatterns) {
        $candidates += Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
    }

    $found = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    return $found
}

function Wait-ForMsvcLinker {
    param([int]$Seconds = 180)

    $deadline = (Get-Date).AddSeconds($Seconds)
    $attempt = 0

    while ((Get-Date) -lt $deadline) {
        $attempt++
        $linker = Find-MsvcLinker
        if ($linker) { return $linker }

        Write-Progress -Activity 'Checking MSVC linker' -Status "Waiting for link.exe to appear... attempt $attempt" -PercentComplete (($attempt * 10) % 95)
        Start-Sleep -Seconds 10
    }

    Write-Progress -Activity 'Checking MSVC linker' -Completed
    return $null
}

function Invoke-VsInstallerModify {
    param([Parameter(Mandatory=$true)][string]$InstallPath)

    if (-not (Test-Path $SetupExe)) {
        throw "Visual Studio Installer setup.exe not found at $SetupExe."
    }

    Write-Host "Adding Desktop development with C++ workload to:" -ForegroundColor Cyan
    Write-Host "  $InstallPath" -ForegroundColor DarkGray

    $args = "modify --installPath `"$InstallPath`" --add $WorkloadId --includeRecommended --quiet --wait --norestart"
    $exitCode = Invoke-ProcessWithHeartbeat -FilePath $SetupExe -ArgumentList $args -Activity 'Visual Studio workload modify'

    if ($exitCode -notin @(0, 3010)) {
        throw "Visual Studio Installer modify failed with exit code $exitCode."
    }

    if ($exitCode -eq 3010) {
        Write-Warning 'Visual Studio Installer reports that a reboot is required.'
    }
}

function Install-BuildToolsWithNativeDesktopDirect {
    Write-Host 'Installing Visual Studio Build Tools directly with Desktop development with C++ workload...' -ForegroundColor Cyan
    Write-Host 'This bypasses winget so broken winget/msstore sources do not block the MSVC linker.' -ForegroundColor DarkGray

    if (-not (Test-Path $BuildToolsBootstrapper)) {
        Write-Host "Downloading Build Tools bootstrapper to $BuildToolsBootstrapper" -ForegroundColor Cyan
        Invoke-WebRequest -Uri $BuildToolsUrl -OutFile $BuildToolsBootstrapper -UseBasicParsing
    } else {
        Write-Host "Using existing bootstrapper: $BuildToolsBootstrapper" -ForegroundColor DarkGray
    }

    $args = "--quiet --wait --norestart --add $WorkloadId --includeRecommended"
    $exitCode = Invoke-ProcessWithHeartbeat -FilePath $BuildToolsBootstrapper -ArgumentList $args -Activity 'Visual Studio Build Tools install'

    if ($exitCode -notin @(0, 3010)) {
        throw "Visual Studio Build Tools installer failed with exit code $exitCode."
    }

    if ($exitCode -eq 3010) {
        Write-Warning 'Visual Studio Build Tools installer reports that a reboot is required.'
    }
}

$linker = Find-MsvcLinker
if ($linker) {
    Write-Host "MSVC linker already present:" -ForegroundColor Green
    Write-Host "  $linker" -ForegroundColor DarkGray
    return
}

Write-Host 'MSVC linker was not found. Installing/modifying Visual Studio C++ workload...' -ForegroundColor Cyan

$installPaths = @(Get-VisualStudioInstallPaths)
if ($installPaths.Count -gt 0 -and (Test-Path $SetupExe)) {
    foreach ($installPath in $installPaths) {
        Invoke-VsInstallerModify -InstallPath $installPath
        Refresh-Path
        $linker = Wait-ForMsvcLinker -Seconds 180
        if ($linker) { break }
    }
}

if (-not $linker) {
    Install-BuildToolsWithNativeDesktopDirect
    Refresh-Path
    $linker = Wait-ForMsvcLinker -Seconds 240
}

if (-not $linker) {
    throw "Desktop development with C++ workload was requested, but link.exe still was not found. Open Visual Studio Installer and verify '$WorkloadId'."
}

Write-Host "MSVC linker ready:" -ForegroundColor Green
Write-Host "  $linker" -ForegroundColor DarkGray
