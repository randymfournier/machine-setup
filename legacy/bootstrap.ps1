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
# Run only selected steps with -Only:
#   .\bootstrap.ps1 -Only winget-repair,visualstudio
#
# Available step keys:
#   drivers        -- local Wi-Fi/touchpad recovery driver install, if exported drivers are present
#   windows        -- Windows tweaks (taskbar alignment, dark mode, perf)
#   debloat        -- only runs when -IncludeDebloat is also passed
#   updates        -- Windows updates
#   winget-repair  -- winget/App Installer health check and repair
#   winget         -- winget package installs, package-by-package
#   visualstudio   -- Visual Studio C++ workload / MSVC linker verification
#   toolchains     -- fnm, uv, Rust, Tauri CLI, fonts, etc.
#   vscode         -- VS Code extensions
#   dotfiles       -- copy PowerShell profile, oh-my-posh, etc.
#   wsl            -- WSL2 + Ubuntu install
#
# Opt in to debloat (removes Teams, Xbox, Bing, etc.):
#   .\bootstrap.ps1 -IncludeDebloat

[CmdletBinding()]
param(
    [string[]]$Skip = @(),
    [string[]]$Only = @(),
    [switch]$IncludeDebloat
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$LegacyRoot = $PSScriptRoot
$RepoRoot = Split-Path -Parent $PSScriptRoot
$SkipKeys = @($Skip | ForEach-Object { $_.ToLowerInvariant() })
$OnlyKeys = @($Only | ForEach-Object { $_.ToLowerInvariant() })

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

function Get-SafeOutputLines {
    param(
        [AllowNull()][object[]]$Lines,
        [int]$Tail = 40
    )

    if (-not $Lines) { return @() }

    $clean = @(
        foreach ($rawLine in $Lines) {
            $line = [string]$rawLine
            # Normalize progress carriage returns and remove common spinner-only lines.
            $line = $line -replace "`r", ''
            $line = $line.TrimEnd()
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -match '^[\\|/\-]+$') { continue }
            $line
        }
    )

    if ($clean.Count -gt $Tail) {
        return @($clean | Select-Object -Last $Tail)
    }

    return $clean
}

function Invoke-LoggedNativeCommand {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [switch]$ThrowOnFailure,
        [int]$TimeoutSeconds = 0,
        [string]$Activity = '',
        [switch]$QuietOutput
    )

    if (-not $Activity) { $Activity = $FilePath }

    Write-Host ("> {0} {1}" -f $FilePath, ($Arguments -join ' ')) -ForegroundColor DarkGray

    $tempBase = Join-Path $env:TEMP ("machine-setup-native-{0}" -f ([guid]::NewGuid().ToString('N')))
    $stdoutPath = "$tempBase.out.log"
    $stderrPath = "$tempBase.err.log"
    $exitCode = $null
    $timedOut = $false

    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -NoNewWindow -PassThru
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $heartbeatSeconds = 15

        while (-not $process.HasExited) {
            Start-Sleep -Seconds $heartbeatSeconds
            try { $process.Refresh() } catch { }

            $elapsed = [math]::Round($sw.Elapsed.TotalSeconds)
            Write-Host ("  [{0:mm\:ss}] {1} still running..." -f $sw.Elapsed, $Activity) -ForegroundColor DarkGray

            if ($TimeoutSeconds -gt 0 -and $elapsed -ge $TimeoutSeconds) {
                $timedOut = $true
                Write-Warning "$Activity timed out after $TimeoutSeconds seconds. Stopping it and continuing."
                try { $process.Kill() } catch { }
                break
            }
        }

        if (-not $timedOut) {
            $exitCode = $process.ExitCode
        } else {
            $exitCode = 124
        }
    } catch {
        if ($ThrowOnFailure) { throw }
        $exitCode = 1
        Set-Content -Path $stderrPath -Value $_.Exception.Message -Encoding UTF8 -ErrorAction SilentlyContinue
    }

    $stdout = @()
    $stderr = @()
    if (Test-Path $stdoutPath) { $stdout = @(Get-Content -Path $stdoutPath -ErrorAction SilentlyContinue) }
    if (Test-Path $stderrPath) { $stderr = @(Get-Content -Path $stderrPath -ErrorAction SilentlyContinue) }
    $output = @($stdout + $stderr)
    $safeOutput = @(Get-SafeOutputLines -Lines $output -Tail 60)

    if (-not $QuietOutput -and $safeOutput.Count -gt 0) {
        $safeOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    }

    Remove-Item -Path $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue

    if ($exitCode -ne 0 -and $ThrowOnFailure) {
        throw "$FilePath failed with exit code $exitCode."
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($safeOutput)
        TimedOut = $timedOut
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

function Test-PendingReboot {
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

function Repair-Winget {
    Write-Host "Repairing App Installer / winget sources..." -ForegroundColor Cyan
    Write-Host "This step is best-effort. It will not block the rest of setup if Microsoft's source metadata hangs." -ForegroundColor DarkGray

    $bundlePath = Join-Path $env:TEMP 'winget.msixbundle'
    $localBundle = Join-Path $RepoRoot 'assets\installers\winget.msixbundle'

    try {
        if (Test-Path $localBundle) {
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

    if (-not (Test-WingetCommandAvailable)) {
        throw 'winget is still not available after App Installer repair.'
    }

    $reset = Invoke-LoggedNativeCommand -FilePath 'winget' -Arguments @('source','reset','--force') -TimeoutSeconds 90 -Activity 'winget source reset' -QuietOutput
    if ($reset.ExitCode -ne 0) {
        Write-Warning "winget source reset --force failed with exit code $($reset.ExitCode). Continuing anyway."
        if ($reset.Output.Count -gt 0) { $reset.Output | Select-Object -Last 8 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkYellow } }
    } else {
        Write-Host 'winget source reset completed.' -ForegroundColor Green
    }

    # Do NOT run 'winget source update' here. On fresh installs it can hang forever
    # on the winget source spinner. Package installs will refresh/check each source as needed.

    if (-not (Test-WingetHealthy)) {
        throw 'winget command still does not appear healthy after repair.'
    }

    Write-Host 'winget command is available. Package installs will run individually with timeouts.' -ForegroundColor Green
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

            $result = Invoke-LoggedNativeCommand -FilePath 'winget' -Arguments $args -TimeoutSeconds 900 -Activity "winget install $id" -QuietOutput

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
                    if ($result.Output.Count -gt 0) {
                        $result.Output | Select-Object -Last 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkYellow }
                    }
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
        $driverInstaller = Join-Path $LegacyRoot 'drivers\install-exported-drivers.ps1'
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
    $Steps += [pscustomobject]@{ Key = 'windows'; Heading = 'Windows tweaks'; Action = { & (Join-Path $LegacyRoot 'windows\apply-tweaks.ps1') } }

    if ($IncludeDebloat -or ('debloat' -in $OnlyKeys)) {
        $Steps += [pscustomobject]@{ Key = 'debloat'; Heading = 'Debloat'; Action = {
            $debloatScript = Join-Path $LegacyRoot 'windows\debloat.ps1'
            if (-not (Test-Path $debloatScript)) {
                $debloatScript = Join-Path $LegacyRoot 'debloat.ps1'
            }
            if (-not (Test-Path $debloatScript)) {
                throw 'Debloat script was not found in windows\debloat.ps1 or repo root.'
            }
            & $debloatScript
        } }
    }

    $Steps += [pscustomobject]@{ Key = 'updates'; Heading = 'Windows updates (no automatic reboot)'; Action = { & (Join-Path $LegacyRoot 'windows\update-windows.ps1') } }
    $Steps += [pscustomobject]@{ Key = 'winget-repair'; Heading = 'winget health / repair'; Action = {
        if (Test-WingetHealthy) {
            Write-Host 'winget command is available. Running quick source reset only; skipping source update to avoid fresh-install hangs.' -ForegroundColor DarkGray
        }
        Repair-Winget
    } }
    $Steps += [pscustomobject]@{ Key = 'winget'; Heading = 'winget packages'; Action = {
        Install-WingetPackagesFromManifest -ManifestPath (Join-Path $RepoRoot 'assets\packages\winget-packages.json')
    } }
    $Steps += [pscustomobject]@{ Key = 'visualstudio'; Heading = 'Visual Studio C++ workload / MSVC linker'; Action = { & (Join-Path $LegacyRoot 'dev\install-visualstudio-native-desktop.ps1') } }
    $Steps += [pscustomobject]@{ Key = 'toolchains'; Heading = 'Dev toolchains'; Action = { & (Join-Path $LegacyRoot 'dev\install-toolchains.ps1') } }
    $Steps += [pscustomobject]@{ Key = 'vscode'; Heading = 'VS Code extensions'; Action = {
        if (Get-Command code -ErrorAction SilentlyContinue) {
            Get-Content (Join-Path $LegacyRoot 'dev\vscode-extensions.txt') |
                Where-Object { $_ -and -not $_.StartsWith('#') } |
                ForEach-Object { code --install-extension $_ --force }
        } else {
            throw 'code CLI is not on PATH yet. Open VS Code once, then re-run this step.'
        }
    } }
    $Steps += [pscustomobject]@{ Key = 'dotfiles'; Heading = 'Dotfiles'; Action = {
        # Allow normal PowerShell dev-tool shims like npm.ps1 to run after setup.
        try {
            Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
            Write-Host "PowerShell CurrentUser execution policy set to RemoteSigned." -ForegroundColor Green
        } catch {
            Write-Warning "Could not set CurrentUser execution policy: $($_.Exception.Message)"
        }

        # PowerShell profile
        $profileDir = Split-Path -Parent $PROFILE
        if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
        Copy-Item (Join-Path $RepoRoot 'assets\shell\Microsoft.PowerShell_profile.ps1') $PROFILE -Force

        # oh-my-posh config
        $ompConfig = "$env:USERPROFILE\.config\oh-my-posh\blueish.omp.json"
        New-Item -ItemType Directory -Path (Split-Path $ompConfig) -Force | Out-Null
        Copy-Item (Join-Path $RepoRoot 'assets\shell\blueish.omp.json') $ompConfig -Force

        # Windows Terminal settings (only if Terminal is installed)
        $wtSettings = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
        if (Test-Path (Split-Path $wtSettings)) {
            Copy-Item (Join-Path $RepoRoot 'assets\shell\windows-terminal-settings.json') $wtSettings -Force
        }

        # Git config -- copy as template, user fills in name/email
        Copy-Item (Join-Path $RepoRoot 'assets\git\.gitconfig') "$env:USERPROFILE\.gitconfig" -Force
        Copy-Item (Join-Path $RepoRoot 'assets\git\.gitignore_global') "$env:USERPROFILE\.gitignore_global" -Force
        Write-Host "Remember to edit $env:USERPROFILE\.gitconfig with your name/email." -ForegroundColor Yellow
    } }
    $Steps += [pscustomobject]@{ Key = 'wsl'; Heading = 'WSL2'; Action = { & (Join-Path $LegacyRoot 'wsl\setup-wsl.ps1') } }

    if ($OnlyKeys.Count -gt 0) {
        $requestedOnly = @($OnlyKeys)
        $Steps = @($Steps | Where-Object { $_.Key.ToLowerInvariant() -in $requestedOnly })

        if ($Steps.Count -eq 0) {
            throw "No matching bootstrap steps found for -Only: $($requestedOnly -join ', ')"
        }
    }

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

    if (Test-PendingReboot) {
        Write-Host ""
        Write-Host "REBOOT PENDING: Windows is asking for a restart, but setup did not restart automatically." -ForegroundColor Yellow
        Write-Host "Finish reviewing this summary first, then reboot manually when you choose." -ForegroundColor Yellow
    }

    Write-Host @"

NEXT STEPS:

  1. Restore SSH keys      -> see docs\ssh\README.md
  2. Edit .gitconfig       -> set user.name and user.email
  3. Log in to services    -> see docs\accounts-checklist.md
  4. Manual stuff          -> see docs\manual-steps.md (M365, drivers, taskbar extras, etc.)
  5. Modding tools         -> see docs\modding\ue4ss-icarus.md (only if you need it)

If WSL or Windows Updates were installed, reboot manually after reviewing this summary.
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
