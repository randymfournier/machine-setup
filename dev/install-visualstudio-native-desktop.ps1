# dev/install-visualstudio-native-desktop.ps1
# Ensures the MSVC linker required by Rust/Tauri native builds is installed.
# This fixes the common first-run error:
#   error: linker link.exe not found
#
# Preferred result:
#   Visual Studio / Build Tools has the Desktop development with C++ workload.

$ErrorActionPreference = 'Stop'

$WorkloadId = 'Microsoft.VisualStudio.Workload.NativeDesktop'
$VcToolsComponentId = 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
$VsInstallerDir = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer'
$SetupExe = Join-Path $VsInstallerDir 'setup.exe'
$VsWhereExe = Join-Path $VsInstallerDir 'vswhere.exe'

function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable('Path','Machine')
    $userPath = [System.Environment]::GetEnvironmentVariable('Path','User')
    $env:Path = @($machinePath, $userPath) -join ';'
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

function Invoke-VsInstallerModify {
    param([Parameter(Mandatory=$true)][string]$InstallPath)

    if (-not (Test-Path $SetupExe)) {
        throw "Visual Studio Installer setup.exe not found at $SetupExe."
    }

    Write-Host "Adding Desktop development with C++ workload to:" -ForegroundColor Cyan
    Write-Host "  $InstallPath" -ForegroundColor DarkGray

    $args = "modify --installPath `"$InstallPath`" --add $WorkloadId --includeRecommended --quiet --norestart"

    $process = Start-Process -FilePath $SetupExe -ArgumentList $args -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) {
        throw "Visual Studio Installer modify failed with exit code $($process.ExitCode)."
    }

    if ($process.ExitCode -eq 3010) {
        Write-Warning 'Visual Studio Installer reports that a reboot is required.'
    }
}

function Install-BuildToolsWithNativeDesktop {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget is required to install Visual Studio Build Tools automatically.'
    }

    Write-Host 'Installing Visual Studio Build Tools with Desktop development with C++ workload...' -ForegroundColor Cyan

    & winget install --id Microsoft.VisualStudio.BuildTools -e --source winget `
        --accept-package-agreements --accept-source-agreements `
        --override "--quiet --wait --norestart --add $WorkloadId --includeRecommended"

    if ($LASTEXITCODE -ne 0) {
        throw "winget Visual Studio Build Tools install failed with exit code $LASTEXITCODE."
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
        $linker = Find-MsvcLinker
        if ($linker) { break }
    }
} else {
    Install-BuildToolsWithNativeDesktop
}

Refresh-Path

# Give VS setup a short moment to finish writing any final toolchain metadata.
for ($i = 1; $i -le 12; $i++) {
    $linker = Find-MsvcLinker
    if ($linker) { break }
    Start-Sleep -Seconds 10
}

if (-not $linker) {
    throw "Desktop development with C++ workload was requested, but link.exe still was not found. Open Visual Studio Installer and verify '$WorkloadId'."
}

Write-Host "MSVC linker ready:" -ForegroundColor Green
Write-Host "  $linker" -ForegroundColor DarkGray
