# quickstart.ps1
# Internet entry point for a fresh Windows install.
#
# Run PowerShell as Administrator and paste only this:
#   irm https://raw.githubusercontent.com/randymfournier/machine-setup/main/quickstart.ps1 | iex
#
# This script's jobs:
#   1. Set process execution policy bypass for this session
#   2. Repair/check winget/App Installer enough to install Git if Git is missing
#   3. Make sure Git is available
#   4. Clone/update the repo to C:\machine-setup
#   5. Launch setup.ps1 in a no-profile, bypassed child PowerShell process

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# --- Must be admin ---------------------------------------------------------
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Run PowerShell as Administrator, then paste the irm quickstart command again." -ForegroundColor Red
    exit 1
}

# Avoid making the user type the execution-policy line every time.
try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop
} catch {
    Write-Warning "Could not set process execution policy automatically: $($_.Exception.Message)"
    Write-Warning "Continuing anyway; child bootstrap will also run with -ExecutionPolicy Bypass."
}

# --- Config ----------------------------------------------------------------
$RepoUrl  = 'https://github.com/randymfournier/machine-setup.git'
$RepoPath = 'C:\machine-setup'

function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable('Path','Machine')
    $userPath = [System.Environment]::GetEnvironmentVariable('Path','User')
    $gitPaths = @(
        "$env:ProgramFiles\Git\cmd",
        "${env:ProgramFiles(x86)}\Git\cmd"
    ) | Where-Object { $_ -and (Test-Path $_) }
    $env:Path = @($machinePath, $userPath, $gitPaths) -join ';'
}

function Get-GitCommand {
    Refresh-Path
    $command = Get-Command git -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    foreach ($candidate in @(
        "$env:ProgramFiles\Git\cmd\git.exe",
        "${env:ProgramFiles(x86)}\Git\cmd\git.exe"
    )) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }

    return $null
}

function Invoke-NativeBestEffort {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [int]$TimeoutSeconds = 120,
        [string]$Activity = ''
    )

    if (-not $Activity) { $Activity = $FilePath }
    Write-Host ("> {0} {1}" -f $FilePath, ($Arguments -join ' ')) -ForegroundColor DarkGray

    $out = Join-Path $env:TEMP ("machine-setup-quickstart-{0}.out" -f ([guid]::NewGuid().ToString('N')))
    $err = Join-Path $env:TEMP ("machine-setup-quickstart-{0}.err" -f ([guid]::NewGuid().ToString('N')))

    try {
        $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -PassThru
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while (-not $p.HasExited) {
            Start-Sleep -Seconds 10
            try { $p.Refresh() } catch { }
            Write-Host ("  [{0:mm\:ss}] {1} still running..." -f $sw.Elapsed, $Activity) -ForegroundColor DarkGray
            if ($sw.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                Write-Warning "$Activity timed out after $TimeoutSeconds seconds. Stopping it and continuing."
                try { $p.Kill() } catch { }
                return 124
            }
        }
        try { $p.Refresh() } catch { }
        if ($null -eq $p.ExitCode) {
            Write-Warning "$Activity finished, but Windows did not report an exit code."
            return 999
        }
        return [int]$p.ExitCode
    } catch {
        Write-Warning "$Activity failed to start/run: $($_.Exception.Message)"
        return 1
    } finally {
        Remove-Item -Path $out,$err -Force -ErrorAction SilentlyContinue
    }
}

function Test-DriverFolder {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path $Path)) { return $false }
    $inf = Get-ChildItem -Path $Path -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    return [bool]$inf
}

function Find-ExportedDriverFolder {
    $candidates = New-Object System.Collections.Generic.List[object]

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
                if (Test-DriverFolder -Path $_.FullName) { $candidates.Add($_) | Out-Null }
            }
        }

        foreach ($path in @("$root\machine-setup-drivers", "$root\drivers")) {
            if (Test-DriverFolder -Path $path) {
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

function Install-RecoveryDriversIfPresent {
    Write-Host "Checking for saved Wi-Fi/touchpad recovery drivers..." -ForegroundColor Cyan

    $folder = Find-ExportedDriverFolder
    if (-not $folder) {
        Write-Host "No exported recovery driver folder found. Continuing." -ForegroundColor DarkGray
        return
    }

    Write-Host "Found recovery drivers: $($folder.FullName)" -ForegroundColor Cyan
    Write-Host "Installing them now so Wi-Fi/touchpad can come online before the main setup." -ForegroundColor DarkGray

    try {
        & pnputil /add-driver (Join-Path $folder.FullName '*.inf') /subdirs /install
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Driver install returned exit code $LASTEXITCODE. Continuing anyway."
        } else {
            Write-Host "Recovery driver install pass complete." -ForegroundColor Green
        }
    } catch {
        Write-Warning "Recovery driver install failed: $($_.Exception.Message)"
        Write-Warning "Continuing anyway."
    }
}

function Test-WingetHealthy {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warning "winget is not on PATH."
        return $false
    }

    $output = & winget --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "winget --version failed: $($output -join ' ')"
        return $false
    }

    return $true
}

function Test-Network {
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

function Find-LocalInstallerFile {
    param([Parameter(Mandatory=$true)][string]$FileName)

    $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
        Where-Object { $_.Root -and (Test-Path $_.Root) }

    foreach ($drive in $drives) {
        $root = $drive.Root.TrimEnd('\')
        foreach ($candidate in @(
            "$root\machine-setup\installers\$FileName",
            "$root\installers\$FileName",
            "$root\machine-setup-offline\installers\$FileName",
            "$root\$FileName"
        )) {
            if (Test-Path $candidate) { return $candidate }
        }
    }

    return $null
}

function Find-LocalGitInstaller {
    foreach ($fileName in @('Git-64-bit.exe','Git.exe')) {
        $local = Find-LocalInstallerFile -FileName $fileName
        if ($local) { return $local }
    }

    return $null
}

function Install-GitFromInstaller {
    param([Parameter(Mandatory=$true)][string]$InstallerPath)

    Write-Host "Using local Git installer: $InstallerPath" -ForegroundColor Green
    return Invoke-NativeBestEffort -FilePath $InstallerPath -Arguments @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/NOCANCEL','/SP-') -TimeoutSeconds 300 -Activity 'Git for Windows installer'
}

function Repair-Winget {
    Write-Host "Repairing App Installer / winget before installing Git..." -ForegroundColor Cyan
    Write-Host "This is best-effort. It skips winget source update because that can hang on fresh installs." -ForegroundColor DarkGray

    $bundlePath = Join-Path $env:TEMP 'winget.msixbundle'
    $localBundle = Find-LocalInstallerFile -FileName 'winget.msixbundle'

    try {
        if ($localBundle) {
            Write-Host "Using local App Installer bundle: $localBundle" -ForegroundColor Green
            $bundlePath = $localBundle
        } else {
            $oldProgress = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri 'https://aka.ms/getwinget' -OutFile $bundlePath -UseBasicParsing -ErrorAction Stop
        }

        Add-AppxPackage -Path $bundlePath -ForceApplicationShutdown -ErrorAction Stop
        Write-Host "App Installer package applied from $bundlePath" -ForegroundColor Green
    } catch {
        Write-Warning "App Installer repair download/apply did not complete: $($_.Exception.Message)"
    } finally {
        if ($null -ne $oldProgress) { $ProgressPreference = $oldProgress }
    }

    Refresh-Path

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $exit = Invoke-NativeBestEffort -FilePath 'winget' -Arguments @('source','reset','--force') -TimeoutSeconds 90 -Activity 'winget source reset'
        if ($exit -ne 0) {
            Write-Warning "winget source reset --force returned exit code $exit. Continuing anyway."
        }
    }

    if (-not (Test-WingetHealthy)) {
        Write-Warning "winget still does not appear healthy after repair."
    }
}

# --- Ensure git is installed -----------------------------------------------
if (-not (Get-GitCommand)) {
    $localGitInstaller = Find-LocalGitInstaller
    $gitExit = 1

    if ($localGitInstaller) {
        try {
            $gitExit = Install-GitFromInstaller -InstallerPath $localGitInstaller
        } catch {
            Write-Warning "Local Git installer failed: $($_.Exception.Message)"
            $gitExit = 1
        }
    }

    if ($gitExit -ne 0) {
        if (-not (Test-WingetHealthy)) {
            Repair-Winget
        } else {
            Write-Host "winget is available; skipping repair and using it only as a Git fallback." -ForegroundColor DarkGray
        }

        Write-Host "Installing Git via winget..." -ForegroundColor Cyan
        $gitExit = Invoke-NativeBestEffort -FilePath 'winget' -Arguments @('install','--id','Git.Git','-e','--source','winget','--accept-package-agreements','--accept-source-agreements','--silent','--disable-interactivity') -TimeoutSeconds 300 -Activity 'winget install Git'
    }

    if (Get-GitCommand) {
        Write-Host 'Git installed and available.' -ForegroundColor Green
        $gitExit = 0
    }

    if ($gitExit -ne 0) {
        throw "Git install failed with exit code $gitExit. Install Git for Windows manually or place Git-64-bit.exe under an installers folder, then re-run quickstart."
    }

    Refresh-Path

    if (-not (Get-GitCommand)) {
        throw "Git install completed, but git.exe is still not on PATH. Restart PowerShell and run quickstart again."
    }
}

# --- Clone or update -------------------------------------------------------
$gitCommand = Get-GitCommand
if (-not $gitCommand) {
    throw "Git is not available. Install Git for Windows manually or place Git-64-bit.exe under an installers folder, then re-run quickstart."
}

if (Test-Path $RepoPath) {
    Write-Host "$RepoPath exists, pulling latest..." -ForegroundColor Cyan
    & $gitCommand -C $RepoPath pull --ff-only
    if ($LASTEXITCODE -ne 0) {
        throw "git pull failed with exit code $LASTEXITCODE."
    }
} else {
    Write-Host "Cloning $RepoUrl to $RepoPath..." -ForegroundColor Cyan
    & $gitCommand clone $RepoUrl $RepoPath
    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed with exit code $LASTEXITCODE."
    }
}

# Belt-and-suspenders: unblock repo files and launch setup without loading a profile.
try {
    Get-ChildItem -Path $RepoPath -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
} catch {
    Write-Warning "Could not unblock all repo files: $($_.Exception.Message)"
}

# --- Hand off to setup console --------------------------------------------
$setupPath = Join-Path $RepoPath 'setup.ps1'
$wizardPath = Join-Path $RepoPath 'legacy\setup-wizard-wrapper.ps1'
$bootstrapPath = Join-Path $RepoPath 'legacy\bootstrap.ps1'

if (Test-Path $setupPath) {
    Write-Host "`nLaunching setup.ps1 with -NoProfile and -ExecutionPolicy Bypass...`n" -ForegroundColor Green
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $setupPath
    $setupExit = $LASTEXITCODE

    if ($setupExit -ne 0) {
        Write-Warning "setup.ps1 finished with exit code $setupExit. Check C:\machine-setup\logs for details."
    }

    exit $setupExit
}

Write-Warning "setup.ps1 was not found. Falling back to legacy compatibility launchers."
if (Test-Path $wizardPath) {
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $wizardPath
    exit $LASTEXITCODE
}

& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $bootstrapPath
$bootstrapExit = $LASTEXITCODE

if ($bootstrapExit -ne 0) {
    Write-Warning "bootstrap.ps1 finished with exit code $bootstrapExit. Check C:\machine-setup\logs for details."
}

exit $bootstrapExit
