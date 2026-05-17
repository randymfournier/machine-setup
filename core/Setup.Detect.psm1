function Test-SetupAdmin {
    try {
        return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Test-SetupNetwork {
    param(
        [string]$HostName = 'github.com',
        [int]$Port = 443,
        [int]$TimeoutMilliseconds = 3000
    )

    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($HostName, $Port, $null, $null)
        $success = $iar.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false)
        if ($success) { $client.EndConnect($iar) }
        $client.Close()
        return [bool]$success
    } catch {
        return $false
    }
}

function Test-SetupPendingReboot {
    $markers = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )

    foreach ($marker in $markers) {
        try {
            if (Test-Path $marker) { return $true }
        } catch { }
    }

    try {
        $pendingRename = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
        if ($pendingRename) { return $true }
    } catch { }

    return $false
}

function Test-SetupCommand {
    param([Parameter(Mandatory=$true)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-SetupDriverFolder {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path $Path)) { return $false }
    $inf = Get-ChildItem -Path $Path -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    return [bool]$inf
}

function Find-SetupExportedDriverFolder {
    param([string]$RepoRoot = (Get-Location).Path)

    $candidates = New-Object System.Collections.Generic.List[object]
    $repoDrivers = Join-Path $RepoRoot 'drivers'

    foreach ($pattern in @(
        (Join-Path $repoDrivers 'exported-selected-*'),
        (Join-Path $repoDrivers 'exported-*')
    )) {
        Get-ChildItem -Path $pattern -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            if (Test-SetupDriverFolder -Path $_.FullName) { $candidates.Add($_) | Out-Null }
        }
    }

    $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
        Where-Object { $_.Root -and (Test-Path $_.Root) }

    foreach ($drive in $drives) {
        $root = $drive.Root.TrimEnd('\')
        foreach ($pattern in @(
            "$root\machine-setup-drivers\exported-selected-*",
            "$root\machine-setup-drivers\exported-*",
            "$root\drivers\exported-selected-*",
            "$root\drivers\exported-*",
            "$root\machine-setup\drivers\exported-selected-*",
            "$root\machine-setup\drivers\exported-*",
            "$root\exported-selected-*",
            "$root\exported-*"
        )) {
            Get-ChildItem -Path $pattern -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                if (Test-SetupDriverFolder -Path $_.FullName) { $candidates.Add($_) | Out-Null }
            }
        }

        foreach ($path in @("$root\machine-setup-drivers", "$root\drivers")) {
            if (Test-SetupDriverFolder -Path $path) {
                $item = Get-Item -Path $path -ErrorAction SilentlyContinue
                if ($item) { $candidates.Add($item) | Out-Null }
            }
        }
    }

    $candidates |
        Sort-Object FullName -Unique |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Test-SetupWingetHealthy {
    if (-not (Test-SetupCommand -Name 'winget')) { return $false }

    $output = & winget --version 2>&1
    return ($LASTEXITCODE -eq 0 -and $output)
}

function Find-SetupMsvcLinker {
    $candidates = @()
    $vsInstallerDir = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer'
    $vswhere = Join-Path $vsInstallerDir 'vswhere.exe'
    $componentId = 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
    $relativePatterns = @(
        'VC\Tools\MSVC\*\bin\Hostx64\x64\link.exe',
        'VC\Tools\MSVC\*\bin\Hostx86\x64\link.exe',
        'VC\Tools\MSVC\*\bin\Hostx64\x86\link.exe',
        'VC\Tools\MSVC\*\bin\Hostx86\x86\link.exe',
        'VC\Tools\MSVC\*\bin\*\*\link.exe'
    )

    if (Test-Path $vswhere) {
        $installPaths = @(& $vswhere -products * -requires $componentId -property installationPath 2>$null)
        if (-not $installPaths -or $installPaths.Count -eq 0) {
            $installPaths = @(& $vswhere -products * -property installationPath 2>$null)
        }
        foreach ($installPath in $installPaths) {
            if ($installPath -and (Test-Path $installPath)) {
                foreach ($relativePattern in $relativePatterns) {
                    $pattern = Join-Path $installPath $relativePattern
                    $candidates += Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
                }
            }
        }
    }

    foreach ($pattern in @(
        (Join-Path ${env:ProgramFiles} 'Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\bin\Hostx64\x64\link.exe'),
        (Join-Path ${env:ProgramFiles} 'Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\bin\Hostx86\x64\link.exe'),
        (Join-Path ${env:ProgramFiles} 'Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\bin\Hostx64\x86\link.exe'),
        (Join-Path ${env:ProgramFiles} 'Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\bin\Hostx86\x86\link.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\bin\Hostx64\x64\link.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\bin\Hostx86\x64\link.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\bin\Hostx64\x86\link.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\bin\Hostx86\x86\link.exe'),
        (Join-Path ${env:ProgramFiles} 'Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\bin\*\*\link.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\bin\*\*\link.exe')
    )) {
        $candidates += Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
    }

    $candidates |
        Where-Object { $_ -and (Test-Path $_) } |
        Sort-Object @{ Expression = { if ($_ -like '*\Hostx64\x64\link.exe') { 0 } elseif ($_ -like '*\x64\link.exe') { 1 } else { 2 } } }, @{ Expression = { $_ } } |
        Select-Object -First 1
}

function Test-SetupMsvcLinker {
    return [bool](Find-SetupMsvcLinker)
}

function Get-SetupPowerShellExecutionPolicy {
    try {
        return Get-ExecutionPolicy -Scope CurrentUser -ErrorAction Stop
    } catch {
        return 'Undefined'
    }
}

function Get-SetupPowerShellEffectiveExecutionPolicy {
    try {
        return Get-ExecutionPolicy -ErrorAction Stop
    } catch {
        return 'Undefined'
    }
}

function Test-SetupPowerShellPolicyReady {
    $policy = Get-SetupPowerShellExecutionPolicy
    $effectivePolicy = Get-SetupPowerShellEffectiveExecutionPolicy
    return (
        $policy -in @('RemoteSigned','Unrestricted','Bypass') -or
        $effectivePolicy -in @('RemoteSigned','Unrestricted','Bypass')
    )
}

function Test-SetupWindowsTweaksApplied {
    try {
        $explorer = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -ErrorAction Stop
        $personalize = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction SilentlyContinue
        return (
            $explorer.TaskbarAl -eq 0 -and
            $explorer.HideFileExt -eq 0 -and
            $explorer.Hidden -eq 1 -and
            $personalize.AppsUseLightTheme -eq 0 -and
            $personalize.SystemUsesLightTheme -eq 0
        )
    } catch {
        return $false
    }
}

function Test-SetupWslInstalled {
    if (-not (Test-SetupCommand -Name 'wsl')) { return $false }
    $output = & wsl --status 2>$null
    return ($LASTEXITCODE -eq 0 -and $output)
}

function Test-SetupWslUbuntuInstalled {
    if (-not (Test-SetupCommand -Name 'wsl')) { return $false }
    $distros = @(& wsl --list --quiet 2>$null) | ForEach-Object { ($_ -replace "`0", '').Trim() }
    return ($distros -contains 'Ubuntu-24.04')
}

function Test-SetupVscodeCli {
    return Test-SetupCommand -Name 'code'
}

function Test-SetupToolchain {
    param([Parameter(Mandatory=$true)][string]$Name)
    return Test-SetupCommand -Name $Name
}

function Get-SetupDetectionSnapshot {
    param([string]$RepoRoot = (Get-Location).Path)

    $driverFolder = Find-SetupExportedDriverFolder -RepoRoot $RepoRoot
    $linker = Find-SetupMsvcLinker

    return [pscustomobject]@{
        admin = Test-SetupAdmin
        network = Test-SetupNetwork
        pendingReboot = Test-SetupPendingReboot
        exportedDriverFolder = if ($driverFolder) { $driverFolder.FullName } else { $null }
        wingetHealthy = Test-SetupWingetHealthy
        git = Test-SetupCommand -Name 'git'
        msvcLinker = if ($linker) { $linker } else { $null }
        powershellPolicy = Get-SetupPowerShellExecutionPolicy
        powershellEffectivePolicy = Get-SetupPowerShellEffectiveExecutionPolicy
        powershellPolicyReady = Test-SetupPowerShellPolicyReady
        fnm = Test-SetupCommand -Name 'fnm'
        node = Test-SetupCommand -Name 'node'
        npm = Test-SetupCommand -Name 'npm'
        rustup = Test-SetupCommand -Name 'rustup'
        cargo = Test-SetupCommand -Name 'cargo'
        uv = Test-SetupCommand -Name 'uv'
        python = Test-SetupCommand -Name 'python'
        go = Test-SetupCommand -Name 'go'
        vscodeCli = Test-SetupVscodeCli
        wsl = Test-SetupWslInstalled
        ubuntu2404 = Test-SetupWslUbuntuInstalled
        windowsTweaksApplied = Test-SetupWindowsTweaksApplied
    }
}

Export-ModuleMember -Function Test-SetupAdmin,Test-SetupNetwork,Test-SetupPendingReboot,Test-SetupCommand,Test-SetupDriverFolder,Find-SetupExportedDriverFolder,Test-SetupWingetHealthy,Find-SetupMsvcLinker,Test-SetupMsvcLinker,Get-SetupPowerShellExecutionPolicy,Get-SetupPowerShellEffectiveExecutionPolicy,Test-SetupPowerShellPolicyReady,Test-SetupWindowsTweaksApplied,Test-SetupWslInstalled,Test-SetupWslUbuntuInstalled,Test-SetupVscodeCli,Test-SetupToolchain,Get-SetupDetectionSnapshot
