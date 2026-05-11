# bootstrap.ps1
# Main orchestrator. Run from quickstart.ps1, or directly:
#   cd C:\machine-setup
#   .\bootstrap.ps1
#
# Idempotent -- safe to re-run.
#
# Skip steps with -Skip (use the lowercase keys below):
#   .\bootstrap.ps1 -Skip windows,updates,wsl,dotfiles
#
# Available skip keys:
#   drivers        -- local Wi-Fi/touchpad recovery driver install, if exported drivers are present
#   windows        -- Windows tweaks (taskbar alignment, dark mode, perf)
#   debloat        -- only runs when -IncludeDebloat is also passed
#   updates        -- Windows updates
#   winget-repair  -- winget/App Installer health check and repair
#   winget         -- winget package installs, package-by-package
#   visualstudio   -- Visual Studio C++ workload / MSVC linker verification
#   toolchains     -- fnm, uv, Rust, Tauri CLI, fonts, etc.
#   vscode         -- VS Code extensions
#   dotfiles       -- copy PowerShell profile, starship, etc.
#   wsl            -- WSL2 + Ubuntu install
#
# Opt in to debloat (removes Teams, Xbox, Bing, etc.):
#   .\bootstrap.ps1 -IncludeDebloat

[CmdletBinding()]
param(
    [string[]]$Skip = @(),
    [switch]$IncludeDebloat
)

$ErrorActionPreference = 'Continue'
$RepoRoot = $PSScriptRoot
$SkipKeys = @($Skip | ForEach-Object { $_.ToLowerInvariant() })

# --- Must be admin ---------------------------------------------------------
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Run as Administrator." -ForegroundColor Red
    exit 1
}

# --- Logging ---------------------------------------------------------------
$LogRoot = Join-Path $RepoRoot 'logs'
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
$RunStamp = Get-Date -Format 'yyyy-MM-dd-HHmmss'
$LogPath = Join-Path $LogRoot "bootstrap-$RunStamp.log"
$SummaryPath = Join-Path $LogRoot "bootstrap-summary-$RunStamp.json"
$script:StepResults = New-Object System.Collections.Generic.List[object]
$script:CurrentStep = 0

try {
    Start-Transcript -Path $LogPath -Append | Out-Null
} catch {
    Write-Warning "Could not start transcript logging: $($_.Exception.Message)"
}

function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable('Path','Machine')
    $userPath = [System.Environment]::GetEnvironmentVariable('Path','User')
    $env:Path = @($machinePath, $userPath, "$env:USERPROFILE\.cargo\bin") -join ';'
}

function Write-SetupHeader([string]$heading) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  $heading" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
}

function Invoke-LoggedNativeCommand {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [switch]$ThrowOnFailure
    )

    Write-Host ("> {0} {1}" -f $FilePath, ($Arguments -join ' ')) -ForegroundColor DarkGray
    $output = & $FilePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    if ($output) {
        $output | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    }

    if ($exitCode -ne 0 -and $ThrowOnFailure) {
        throw "$FilePath failed with exit code $exitCode."
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output)
    }
}

function Test-WingetCommandAvailable {
    return [bool](Get-Command winget -ErrorAction SilentlyContinue)
}

function Test-WingetHealthy {
    if (-not (Test-WingetCommandAvailable)) {
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

function Test-WingetSourceHealthy {
    param([Parameter(Mandatory=$true)][string]$SourceName)

    if (-not (Test-WingetHealthy)) { return $false }

    $output = & winget source list 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "winget source list failed: $($output -join ' ')"
        return $false
    }

    $joined = $output -join "`n"
    return ($joined -match "(?im)^\s*$([regex]::Escape($SourceName))\s")
}

function Repair-Winget {
    Write-Host "Repairing App Installer / winget sources..." -ForegroundColor Cyan
    Write-Host "This step is best-effort. If source reset still fails, package installs will continue package-by-package." -ForegroundColor DarkGray

    $bundlePath = Join-Path $env:TEMP 'winget.msixbundle'

    try {
        Invoke-WebRequest -Uri 'https://aka.ms/getwinget' -OutFile $bundlePath -UseBasicParsing
        Add-AppxPackage -Path $bundlePath -ForceApplicationShutdown
        Write-Host "App Installer package applied from $bundlePath" -ForegroundColor Green
    } catch {
        Write-Warning "App Installer repair failed or was already current: $($_.Exception.Message)"
    }

    Refresh-Path

    if (-not (Test-WingetCommandAvailable)) {
        throw 'winget is still not available after App Installer repair.'
    }

    $reset = Invoke-LoggedNativeCommand -FilePath 'winget' -Arguments @('source','reset','--force')
    if ($reset.ExitCode -ne 0) {
        Write-Warning "winget source reset --force failed with exit code $($reset.ExitCode). Continuing anyway."
    }

    $update = Invoke-LoggedNativeCommand -FilePath 'winget' -Arguments @('source','update')
    if ($update.ExitCode -ne 0) {
        Write-Warning "winget source update failed with exit code $($update.ExitCode). Continuing anyway."
    }

    if (-not (Test-WingetHealthy)) {
        throw 'winget command still does not appear healthy after repair.'
    }

    Write-Host 'winget command is available. Individual sources will be tested during package installs.' -ForegroundColor Green
}

function Install-WingetPackagesFromManifest {
    param([Parameter(Mandatory=$true)][string]$ManifestPath)

    if (-not (Test-Path $ManifestPath)) {
        throw "winget manifest not found: $ManifestPath"
    }

    if (-not (Test-WingetHealthy)) {
        throw 'winget is not available enough to install packages.'
    }

    $manifest = Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json
    $failures = New-Object System.Collections.Generic.List[string]
    $installed = 0
    $skipped = 0

    foreach ($source in $manifest.Sources) {
        $sourceName = $source.SourceDetails.Name
        if (-not $sourceName) { $sourceName = 'winget' }

        Write-Host ""
        Write-Host "Source: $sourceName" -ForegroundColor Cyan

        if (-not (Test-WingetSourceHealthy -SourceName $sourceName)) {
            Write-Warning "Source '$sourceName' did not pass a source-list check. Attempting packages anyway so one bad source check does not skip the whole manifest."
        }

        foreach ($pkg in $source.Packages) {
            $id = $pkg.PackageIdentifier
            if (-not $id) { continue }

            Write-Host ""
            Write-Host "Installing/checking $id ..." -ForegroundColor Cyan

            $args = @(
                'install',
                '--id', $id,
                '-e',
                '--source', $sourceName,
                '--accept-package-agreements',
                '--accept-source-agreements',
                '--silent',
                '--disable-interactivity'
            )

            $result = Invoke-LoggedNativeCommand -FilePath 'winget' -Arguments $args

            if ($result.ExitCode -eq 0) {
                $installed++
                Write-Host "[OK] $id" -ForegroundColor Green
            } else {
                $text = ($result.Output -join ' ')
                if ($text -match 'No available upgrade|already installed|No newer package versions') {
                    $skipped++
                    Write-Host "[OK] $id already installed/current" -ForegroundColor Green
                } else {
                    $failures.Add("$id :: winget exit code $($result.ExitCode)") | Out-Null
                    Write-Host "[FAILED] $id" -ForegroundColor Red
                    Write-Host "  Continuing with next package." -ForegroundColor DarkYellow
                }
            }
        }
    }

    Write-Host ""
    Write-Host "winget package pass complete: $installed installed, $skipped already current, $($failures.Count) failed." -ForegroundColor Cyan

    if ($failures.Count -gt 0) {
        Write-Host ""
        Write-Host "winget package failures:" -ForegroundColor Yellow
        $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
        throw "$($failures.Count) winget package(s) failed. See log for details."
    }
}

function Invoke-SetupStep {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][string]$Heading,
        [Parameter(Mandatory=$true)][scriptblock]$Action,
        [Parameter(Mandatory=$true)][int]$TotalSteps
    )

    $script:CurrentStep++
    $percent = [math]::Floor((($script:CurrentStep - 1) / [math]::Max($TotalSteps, 1)) * 100)
    Write-Progress -Activity 'machine-setup bootstrap' -Status "[$script:CurrentStep/$TotalSteps] $Heading" -PercentComplete $percent

    if ($Key.ToLowerInvariant() -in $SkipKeys) {
        Write-Host "`n[SKIP] $Heading ($Key)" -ForegroundColor Yellow
        $script:StepResults.Add([pscustomobject]@{
            Key = $Key
            Heading = $Heading
            Status = 'Skipped'
            Seconds = 0
            Error = $null
        }) | Out-Null
        return
    }

    Write-SetupHeader "[$script:CurrentStep/$TotalSteps] $Heading"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $errorMessage = $null
    $status = 'OK'

    try {
        $global:LASTEXITCODE = 0
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        try {
            & $Action
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        Refresh-Path
        Write-Host "[OK] $Heading" -ForegroundColor Green
    } catch {
        $status = 'Failed'
        $errorMessage = $_.Exception.Message
        Write-Host "[FAILED] $Heading" -ForegroundColor Red
        Write-Host "  $errorMessage" -ForegroundColor Yellow
        Write-Host "  Continuing with the remaining steps. Full details are in the log." -ForegroundColor DarkYellow
    } finally {
        $sw.Stop()
        $script:StepResults.Add([pscustomobject]@{
            Key = $Key
            Heading = $Heading
            Status = $status
            Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
            Error = $errorMessage
        }) | Out-Null
    }
}

try {
    # Belt-and-suspenders: unblock any internet-marked files in the repo so
    # child scripts can run regardless of execution policy.
    Get-ChildItem -Path $RepoRoot -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

    $Steps = @()
    $Steps += [pscustomobject]@{ Key = 'drivers'; Heading = 'Local Wi-Fi/touchpad recovery drivers'; Action = {
        $driverInstaller = Join-Path $RepoRoot 'drivers\install-exported-drivers.ps1'
        if (-not (Test-Path $driverInstaller)) {
            Write-Host 'Driver installer script not found. Skipping local driver pass.' -ForegroundColor DarkGray
            return
        }

        try {
            & $driverInstaller
        } catch {
            $message = $_.Exception.Message
            if ($message -match 'Driver source folder not found|No \.inf files were found') {
                Write-Host 'No local exported driver folder found. Skipping local driver pass.' -ForegroundColor DarkGray
            } else {
                throw
            }
        }
    } }
    $Steps += [pscustomobject]@{ Key = 'windows'; Heading = 'Windows tweaks'; Action = { & (Join-Path $RepoRoot 'windows\apply-tweaks.ps1') } }

    if ($IncludeDebloat) {
        $Steps += [pscustomobject]@{ Key = 'debloat'; Heading = 'Debloat'; Action = {
            $debloatScript = Join-Path $RepoRoot 'windows\debloat.ps1'
            if (-not (Test-Path $debloatScript)) {
                $debloatScript = Join-Path $RepoRoot 'debloat.ps1'
            }
            if (-not (Test-Path $debloatScript)) {
                throw 'Debloat script was not found in windows\debloat.ps1 or repo root.'
            }
            & $debloatScript
        } }
    }

    $Steps += [pscustomobject]@{ Key = 'updates'; Heading = 'Windows updates'; Action = { & (Join-Path $RepoRoot 'windows\update-windows.ps1') } }
    $Steps += [pscustomobject]@{ Key = 'winget-repair'; Heading = 'winget health / repair'; Action = {
        if (Test-WingetHealthy) {
            Write-Host 'winget command is available. Running source repair/check anyway because fresh installs can have broken source metadata.' -ForegroundColor DarkGray
        }
        Repair-Winget
    } }
    $Steps += [pscustomobject]@{ Key = 'visualstudio'; Heading = 'Visual Studio C++ workload / MSVC linker'; Action = { & (Join-Path $RepoRoot 'dev\install-visualstudio-native-desktop.ps1') } }
    $Steps += [pscustomobject]@{ Key = 'winget'; Heading = 'winget packages'; Action = {
        Install-WingetPackagesFromManifest -ManifestPath (Join-Path $RepoRoot 'winget-packages.json')
    } }
    $Steps += [pscustomobject]@{ Key = 'toolchains'; Heading = 'Dev toolchains'; Action = { & (Join-Path $RepoRoot 'dev\install-toolchains.ps1') } }
    $Steps += [pscustomobject]@{ Key = 'vscode'; Heading = 'VS Code extensions'; Action = {
        if (Get-Command code -ErrorAction SilentlyContinue) {
            Get-Content (Join-Path $RepoRoot 'dev\vscode-extensions.txt') |
                Where-Object { $_ -and -not $_.StartsWith('#') } |
                ForEach-Object { code --install-extension $_ --force }
        } else {
            throw 'code CLI is not on PATH yet. Open VS Code once, then re-run this step.'
        }
    } }
    $Steps += [pscustomobject]@{ Key = 'dotfiles'; Heading = 'Dotfiles'; Action = {
        # PowerShell profile
        $profileDir = Split-Path -Parent $PROFILE
        if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
        Copy-Item (Join-Path $RepoRoot 'shell\Microsoft.PowerShell_profile.ps1') $PROFILE -Force

        # Starship config
        $starshipConfig = "$env:USERPROFILE\.config\starship.toml"
        New-Item -ItemType Directory -Path (Split-Path $starshipConfig) -Force | Out-Null
        Copy-Item (Join-Path $RepoRoot 'shell\starship.toml') $starshipConfig -Force

        # Windows Terminal settings (only if Terminal is installed)
        $wtSettings = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
        if (Test-Path (Split-Path $wtSettings)) {
            Copy-Item (Join-Path $RepoRoot 'shell\windows-terminal-settings.json') $wtSettings -Force
        }

        # Git config -- copy as template, user fills in name/email
        Copy-Item (Join-Path $RepoRoot 'git\.gitconfig') "$env:USERPROFILE\.gitconfig" -Force
        Copy-Item (Join-Path $RepoRoot 'git\.gitignore_global') "$env:USERPROFILE\.gitignore_global" -Force
        Write-Host "Remember to edit $env:USERPROFILE\.gitconfig with your name/email." -ForegroundColor Yellow
    } }
    $Steps += [pscustomobject]@{ Key = 'wsl'; Heading = 'WSL2'; Action = { & (Join-Path $RepoRoot 'wsl\setup-wsl.ps1') } }

    foreach ($step in $Steps) {
        Invoke-SetupStep -Key $step.Key -Heading $step.Heading -Action $step.Action -TotalSteps $Steps.Count
    }

    Write-Progress -Activity 'machine-setup bootstrap' -Completed

    $script:StepResults | ConvertTo-Json -Depth 5 | Set-Content -Path $SummaryPath -Encoding UTF8

    $failed = @($script:StepResults | Where-Object { $_.Status -eq 'Failed' })
    $skipped = @($script:StepResults | Where-Object { $_.Status -eq 'Skipped' })

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    if ($failed.Count -eq 0) {
        Write-Host "  Bootstrap complete." -ForegroundColor Green
    } else {
        Write-Host "  Bootstrap finished with $($failed.Count) failed step(s)." -ForegroundColor Yellow
    }
    Write-Host "========================================" -ForegroundColor Green

    Write-Host ""
    Write-Host "Step summary:" -ForegroundColor Cyan
    foreach ($result in $script:StepResults) {
        $color = switch ($result.Status) {
            'OK' { 'Green' }
            'Skipped' { 'Yellow' }
            'Failed' { 'Red' }
            default { 'Gray' }
        }
        Write-Host ("  [{0}] {1} ({2}s)" -f $result.Status, $result.Heading, $result.Seconds) -ForegroundColor $color
        if ($result.Error) {
            Write-Host "       $($result.Error)" -ForegroundColor DarkYellow
        }
    }

    Write-Host ""
    Write-Host "Logs:" -ForegroundColor Cyan
    Write-Host "  Full log:     $LogPath"
    Write-Host "  JSON summary: $SummaryPath"

    Write-Host @"

NEXT STEPS:

  1. Restore SSH keys      -> see ssh\README.md
  2. Edit .gitconfig       -> set user.name and user.email
  3. Log in to services    -> see accounts-checklist.md
  4. Manual stuff          -> see manual-steps.md (M365, drivers, taskbar extras, etc.)
  5. Modding tools         -> see modding\ue4ss-icarus.md (only if you need it)

If WSL or Windows Updates were installed, REBOOT before using them heavily.
"@ -ForegroundColor Cyan

    if ($failed.Count -gt 0) {
        exit 2
    }
} finally {
    try {
        Stop-Transcript | Out-Null
    } catch {
        # no-op; transcript may not have started
    }
}
