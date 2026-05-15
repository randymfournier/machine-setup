# setup-wizard.ps1
# Keyboard-driven console wizard for machine-setup.
#
# This is intentionally a thin wizard shell. It does not replace bootstrap.ps1.
# It can run selected bootstrap steps or open maintenance utilities.
# It does not auto-start installs unless explicitly launched with -Auto.

[CmdletBinding()]
param(
    [switch]$IncludeDebloat,
    [switch]$Auto,
    [ValidateSet('recommended','minimal','dev','apps')]
    [string]$Mode = 'recommended'
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$RepoRoot = $PSScriptRoot
$BootstrapPath = Join-Path $RepoRoot 'bootstrap.ps1'
$PlanPath = Join-Path $RepoRoot 'setup-plan.json'
$LogRoot = Join-Path $RepoRoot 'logs'
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
$RunStamp = Get-Date -Format 'yyyy-MM-dd-HHmmss'
$WizardLogPath = Join-Path $LogRoot "wizard-$RunStamp.log"
$WizardSummaryPath = Join-Path $LogRoot "wizard-summary-$RunStamp.json"
$script:WizardResults = New-Object System.Collections.Generic.List[object]

function Write-WizardLog {
    param([Parameter(Mandatory=$true)][string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $WizardLogPath -Value $line -Encoding UTF8
}

function Test-IsAdmin {
    try {
        return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Test-NetworkLikelyAvailable {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect('github.com', 443, $null, $null)
        $success = $iar.AsyncWaitHandle.WaitOne(3000, $false)
        if ($success) { $client.EndConnect($iar) }
        $client.Close()
        return [bool]$success
    } catch {
        return $false
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
    $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Where-Object { $_.Root -and (Test-Path $_.Root) }

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
    }

    $candidates | Sort-Object FullName -Unique | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Get-LatestLogFile {
    if (-not (Test-Path $LogRoot)) { return $null }
    Get-ChildItem -Path $LogRoot -Filter '*.log' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Show-RecentLogLines {
    param([int]$Tail = 40)
    $latest = Get-LatestLogFile
    if (-not $latest) {
        Write-Host "No log file found yet." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "Recent log lines from: $($latest.FullName)" -ForegroundColor Cyan
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Get-Content -Path $latest.FullName -Tail $Tail -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host $_ -ForegroundColor DarkGray
    }
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
}

function Pause-ForEnter {
    param([string]$Prompt = 'Press Enter to continue')
    [void](Read-Host $Prompt)
}

function Show-Welcome {
    Clear-Host
    Write-Host "machine-setup" -ForegroundColor Green
    Write-Host "=============" -ForegroundColor Green
    Write-Host ""
    Write-Host "One command starts this tool. Nothing installs until you choose a mode." -ForegroundColor Cyan
    Write-Host "Use Recommended for the normal rebuild, or Customize/Toolkit when needed." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Status:" -ForegroundColor Cyan
    Write-Host ("  Repo:        {0}" -f $RepoRoot)
    Write-Host ("  Admin:       {0}" -f ($(if (Test-IsAdmin) { 'YES' } else { 'NO' })))
    Write-Host ("  Network:     {0}" -f ($(if (Test-NetworkLikelyAvailable) { 'LIKELY AVAILABLE' } else { 'NOT DETECTED / LIMITED' })))

    $driverFolder = Find-ExportedDriverFolder
    if ($driverFolder) {
        Write-Host ("  Drivers:     FOUND - {0}" -f $driverFolder.FullName) -ForegroundColor Green
    } else {
        Write-Host "  Drivers:     No exported driver folder found" -ForegroundColor Yellow
    }

    Write-Host ("  Wizard log:  {0}" -f $WizardLogPath)
    Write-Host ""

    if (-not (Test-IsAdmin)) {
        Write-Host "This setup must be run as Administrator." -ForegroundColor Red
        Write-Host "Close this window, open PowerShell as Administrator, and run the quickstart again." -ForegroundColor Yellow
        exit 1
    }

    if (-not (Test-Path $BootstrapPath)) {
        Write-Host "bootstrap.ps1 was not found at: $BootstrapPath" -ForegroundColor Red
        exit 1
    }
}

function Get-StepCatalog {
    if (Test-Path $PlanPath) {
        try {
            $raw = Get-Content -Path $PlanPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            return @($raw.steps)
        } catch {
            Write-Warning "Could not read setup-plan.json. Falling back to built-in step plan: $($_.Exception.Message)"
        }
    }

    $steps = @()
    $steps += [pscustomobject]@{ Key = 'drivers';       Heading = 'Local Wi-Fi/touchpad recovery drivers'; Recommended = $true;  Minimal = $true;  Dev = $false; Apps = $false }
    $steps += [pscustomobject]@{ Key = 'windows';       Heading = 'Windows tweaks';                         Recommended = $true;  Minimal = $false; Dev = $false; Apps = $false }
    $steps += [pscustomobject]@{ Key = 'updates';       Heading = 'Windows updates (no automatic reboot)';  Recommended = $true;  Minimal = $false; Dev = $false; Apps = $false }
    $steps += [pscustomobject]@{ Key = 'winget-repair'; Heading = 'winget health / repair';                  Recommended = $true;  Minimal = $true;  Dev = $false; Apps = $true  }
    $steps += [pscustomobject]@{ Key = 'winget';        Heading = 'winget apps';                             Recommended = $true;  Minimal = $false; Dev = $false; Apps = $true  }
    $steps += [pscustomobject]@{ Key = 'visualstudio';  Heading = 'Visual Studio C++ workload / MSVC linker';Recommended = $true;  Minimal = $true;  Dev = $true;  Apps = $false }
    $steps += [pscustomobject]@{ Key = 'toolchains';    Heading = 'Dev toolchains';                          Recommended = $true;  Minimal = $false; Dev = $true;  Apps = $false }
    $steps += [pscustomobject]@{ Key = 'vscode';        Heading = 'VS Code extensions';                      Recommended = $true;  Minimal = $false; Dev = $true;  Apps = $false }
    $steps += [pscustomobject]@{ Key = 'dotfiles';      Heading = 'Dotfiles / PowerShell profile';           Recommended = $true;  Minimal = $false; Dev = $true;  Apps = $false }
    $steps += [pscustomobject]@{ Key = 'wsl';           Heading = 'WSL2';                                    Recommended = $true;  Minimal = $false; Dev = $true;  Apps = $false }
    $steps += [pscustomobject]@{ Key = 'debloat';       Heading = 'Debloat optional Windows apps';           Recommended = $false; Minimal = $false; Dev = $false; Apps = $false }
    return $steps
}

function Get-StepsForMode {
    param(
        [Parameter(Mandatory=$true)][object[]]$Catalog,
        [Parameter(Mandatory=$true)][string]$ModeName
    )

    switch ($ModeName.ToLowerInvariant()) {
        'recommended' { return @($Catalog | Where-Object { $_.Recommended }) }
        'minimal'     { return @($Catalog | Where-Object { $_.Minimal }) }
        'dev'         { return @($Catalog | Where-Object { $_.Dev }) }
        'apps'        { return @($Catalog | Where-Object { $_.Apps }) }
        default       { return @($Catalog | Where-Object { $_.Recommended }) }
    }
}

function Show-Steps {
    param([Parameter(Mandatory=$true)][object[]]$Steps)
    Write-Host ""
    Write-Host "Selected steps:" -ForegroundColor Cyan
    $i = 1
    foreach ($step in $Steps) {
        Write-Host ("  {0,2}. {1} [{2}]" -f $i, $step.Heading, $step.Key)
        $i++
    }
    Write-Host ""
}

function Select-CustomSteps {
    param([Parameter(Mandatory=$true)][object[]]$Catalog)

    $selected = @{}
    foreach ($step in $Catalog) { $selected[$step.Key] = [bool]$step.Recommended }

    while ($true) {
        Clear-Host
        Write-Host "Custom step selection" -ForegroundColor Green
        Write-Host "=====================" -ForegroundColor Green
        Write-Host "Type a number to toggle it. A = all, N = none, D = defaults, R = run, Q = quit." -ForegroundColor Cyan
        Write-Host ""

        for ($i = 0; $i -lt $Catalog.Count; $i++) {
            $step = $Catalog[$i]
            $mark = if ($selected[$step.Key]) { 'X' } else { ' ' }
            Write-Host ("  [{0}] {1,2}. {2} [{3}]" -f $mark, ($i + 1), $step.Heading, $step.Key)
        }

        Write-Host ""
        $choice = (Read-Host 'Choice').Trim()
        if ([string]::IsNullOrWhiteSpace($choice)) { continue }

        switch -Regex ($choice) {
            '^[Qq]$' { exit 0 }
            '^[Aa]$' { foreach ($step in $Catalog) { $selected[$step.Key] = $true }; continue }
            '^[Nn]$' { foreach ($step in $Catalog) { $selected[$step.Key] = $false }; continue }
            '^[Dd]$' { foreach ($step in $Catalog) { $selected[$step.Key] = [bool]$step.Recommended }; continue }
            '^[Rr]$' {
                $out = @($Catalog | Where-Object { $selected[$_.Key] })
                if ($out.Count -eq 0) {
                    Write-Host "Select at least one step before running." -ForegroundColor Yellow
                    Pause-ForEnter
                    continue
                }
                return $out
            }
            '^\d+$' {
                $n = [int]$choice
                if ($n -ge 1 -and $n -le $Catalog.Count) {
                    $key = $Catalog[$n - 1].Key
                    $selected[$key] = -not $selected[$key]
                }
                continue
            }
            default {
                Write-Host "Unknown choice." -ForegroundColor Yellow
                Pause-ForEnter
            }
        }
    }
}

function Show-TextFilePaged {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [string]$Title = 'Document'
    )

    Clear-Host
    Write-Host $Title -ForegroundColor Green
    Write-Host ('=' * [Math]::Min($Title.Length, 60)) -ForegroundColor Green
    Write-Host ""

    if (-not (Test-Path $Path)) {
        Write-Host "File not found: $Path" -ForegroundColor Yellow
        Pause-ForEnter
        return
    }

    $lines = Get-Content -Path $Path -ErrorAction SilentlyContinue
    $count = 0
    foreach ($line in $lines) {
        Write-Host $line
        $count++
        if ($count -ge 28) {
            $count = 0
            Write-Host ""
            $choice = (Read-Host 'Press Enter for more, Q to stop').Trim()
            if ($choice -match '^[Qq]$') { break }
        }
    }
    Write-Host ""
    Pause-ForEnter
}

function Invoke-ScriptUtility {
    param(
        [Parameter(Mandatory=$true)][string]$ScriptPath,
        [string[]]$Arguments = @(),
        [string]$Name = 'utility'
    )

    if (-not (Test-Path $ScriptPath)) {
        Write-Host "Utility not found: $ScriptPath" -ForegroundColor Red
        Pause-ForEnter
        return 1
    }

    Write-Host ""
    Write-Host "Running $Name..." -ForegroundColor Cyan
    Write-Host ""
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments
    $exit = $LASTEXITCODE
    if ($exit -eq 0) {
        Write-Host ""
        Write-Host "[OK] $Name finished." -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "[FAILED] $Name returned exit code $exit." -ForegroundColor Yellow
    }
    Pause-ForEnter
    return $exit
}

function Show-ToolkitMenu {
    while ($true) {
        Clear-Host
        Write-Host "machine-setup toolkit" -ForegroundColor Green
        Write-Host "=====================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Use this before a wipe, when maintaining the recovery USB, or when you need instructions." -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  1. Prepare/update recovery USB files"
        Write-Host "  2. Export Wi-Fi/touchpad drivers"
        Write-Host "  3. Cache offline recovery assets"
        Write-Host "  4. Export drivers + cache assets"
        Write-Host "  5. Read recovery USB instructions"
        Write-Host "  6. Read slipstream/rebuild boot USB instructions"
        Write-Host "  7. Read main README"
        Write-Host "  B. Back"
        Write-Host "  Q. Quit"
        Write-Host ""

        $choice = (Read-Host 'Toolkit choice').Trim()
        switch -Regex ($choice) {
            '^1$' { Invoke-ScriptUtility -ScriptPath (Join-Path $RepoRoot 'usb\prepare-recovery-usb.ps1') -Name 'Prepare/update recovery USB files' | Out-Null }
            '^2$' { Invoke-ScriptUtility -ScriptPath (Join-Path $RepoRoot 'drivers\export-selected-drivers.ps1') -Name 'Export Wi-Fi/touchpad drivers' | Out-Null }
            '^3$' { Invoke-ScriptUtility -ScriptPath (Join-Path $RepoRoot 'cache-recovery-assets.ps1') -Name 'Cache offline recovery assets' | Out-Null }
            '^4$' {
                Invoke-ScriptUtility -ScriptPath (Join-Path $RepoRoot 'drivers\export-selected-drivers.ps1') -Name 'Export Wi-Fi/touchpad drivers' | Out-Null
                Invoke-ScriptUtility -ScriptPath (Join-Path $RepoRoot 'cache-recovery-assets.ps1') -Name 'Cache offline recovery assets' | Out-Null
            }
            '^5$' { Show-TextFilePaged -Path (Join-Path $RepoRoot 'usb\README.md') -Title 'Recovery USB instructions' }
            '^6$' { Show-TextFilePaged -Path (Join-Path $RepoRoot 'slipstream-iso.md') -Title 'Slipstream/rebuild boot USB instructions' }
            '^7$' { Show-TextFilePaged -Path (Join-Path $RepoRoot 'README.md') -Title 'machine-setup README' }
            '^[Bb]$' { return }
            '^[Qq]$' { exit 0 }
            default { Write-Host "Choose 1-7, B, or Q." -ForegroundColor Yellow; Start-Sleep -Seconds 1 }
        }
    }
}

function Select-InstallMode {
    $catalog = @(Get-StepCatalog)

    while ($true) {
        Clear-Host
        Write-Host "machine-setup mode" -ForegroundColor Green
        Write-Host "==================" -ForegroundColor Green
        Write-Host ""
        Write-Host "  1. Recommended full setup"
        Write-Host "  2. Minimal recovery setup"
        Write-Host "  3. Dev toolchains only"
        Write-Host "  4. Apps only"
        Write-Host "  5. Custom step selection"
        Write-Host "  6. Toolkit / recovery USB utilities"
        Write-Host "  Q. Quit"
        Write-Host ""
        Write-Host "Press Enter for Recommended full setup, or choose another option." -ForegroundColor DarkGray
        Write-Host "Nothing runs until you choose and confirm." -ForegroundColor DarkGray
        Write-Host ""

        $choice = (Read-Host 'Mode').Trim()
        if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }
        switch -Regex ($choice) {
            '^1$' { return [pscustomobject]@{ Steps = @(Get-StepsForMode -Catalog $catalog -ModeName 'recommended'); Auto = $false } }
            '^2$' { return [pscustomobject]@{ Steps = @(Get-StepsForMode -Catalog $catalog -ModeName 'minimal'); Auto = $false } }
            '^3$' { return [pscustomobject]@{ Steps = @(Get-StepsForMode -Catalog $catalog -ModeName 'dev'); Auto = $false } }
            '^4$' { return [pscustomobject]@{ Steps = @(Get-StepsForMode -Catalog $catalog -ModeName 'apps'); Auto = $false } }
            '^5$' { return [pscustomobject]@{ Steps = @(Select-CustomSteps -Catalog $catalog); Auto = $false } }
            '^6$' { Show-ToolkitMenu; continue }
            '^[Qq]$' { exit 0 }
            default { Write-Host "Choose 1-6, Enter, or Q." -ForegroundColor Yellow; Start-Sleep -Seconds 1 }
        }
    }
}

function Invoke-BootstrapStep {
    param([Parameter(Mandatory=$true)][object]$Step)

    $args = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$BootstrapPath,'-Only',$Step.Key)
    if ($IncludeDebloat -or $Step.Key -eq 'debloat') {
        $args += '-IncludeDebloat'
    }

    Write-WizardLog "RUN $($Step.Key) - $($Step.Heading)"
    Write-Host ""
    Write-Host ("Running: {0}" -f $Step.Heading) -ForegroundColor Cyan
    Write-Host ("Step key: {0}" -f $Step.Key) -ForegroundColor DarkGray
    Write-Host ""

    $started = Get-Date
    & powershell.exe @args
    $exitCode = $LASTEXITCODE
    $seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)

    $status = if ($exitCode -eq 0) { 'OK' } else { 'Failed' }
    Write-WizardLog "DONE $($Step.Key) status=$status exit=$exitCode seconds=$seconds"

    $script:WizardResults.Add([pscustomobject]@{
        Key = $Step.Key
        Heading = $Step.Heading
        Status = $status
        ExitCode = $exitCode
        Seconds = $seconds
    }) | Out-Null

    return $exitCode
}

function Run-WizardSteps {
    param(
        [Parameter(Mandatory=$true)][object[]]$Steps,
        [switch]$Automatic
    )

    Show-Steps -Steps $Steps
    if (-not $Automatic) {
        Pause-ForEnter 'Press Enter to start the wizard'
    } else {
        Write-Host "Automatic mode: selected steps will run without stopping between them." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }

    for ($i = 0; $i -lt $Steps.Count; $i++) {
        $step = $Steps[$i]

        if ($Automatic) {
            Write-Host ""
            Write-Host ("Auto step {0}/{1}: {2}" -f ($i + 1), $Steps.Count, $step.Heading) -ForegroundColor Green
            $exit = Invoke-BootstrapStep -Step $step
            if ($exit -eq 0) {
                Write-Host ("[OK] {0}" -f $step.Heading) -ForegroundColor Green
            } else {
                Write-Host ("[FAILED] {0} - continuing automatic setup." -f $step.Heading) -ForegroundColor Yellow
            }
            continue
        }

        while ($true) {
            Write-Host ""
            Write-Host ("Step {0}/{1}: {2}" -f ($i + 1), $Steps.Count, $step.Heading) -ForegroundColor Green
            Write-Host "Options: Enter = run/next, S = skip, Q = quit" -ForegroundColor Cyan
            $choice = (Read-Host 'Choice').Trim()

            if ($choice -match '^[Qq]$') {
                Write-WizardLog 'User quit wizard.'
                return
            }

            if ($choice -match '^[Ss]$') {
                Write-WizardLog "SKIP $($step.Key) - $($step.Heading)"
                $script:WizardResults.Add([pscustomobject]@{
                    Key = $step.Key
                    Heading = $step.Heading
                    Status = 'Skipped'
                    ExitCode = $null
                    Seconds = 0
                }) | Out-Null
                break
            }

            $exit = Invoke-BootstrapStep -Step $step
            if ($exit -eq 0) {
                Write-Host ""
                Write-Host ("[OK] {0}" -f $step.Heading) -ForegroundColor Green
                break
            }

            Write-Host ""
            Write-Host ("[FAILED] {0}" -f $step.Heading) -ForegroundColor Red
            Write-Host "Options: R = retry, L = show recent log, C/Enter = continue, Q = quit" -ForegroundColor Yellow
            $afterFail = (Read-Host 'Choice').Trim()

            if ($afterFail -match '^[Rr]$') { continue }
            if ($afterFail -match '^[Ll]$') {
                Show-RecentLogLines -Tail 50
                Write-Host ""
                Write-Host "Options: R = retry, C/Enter = continue, Q = quit" -ForegroundColor Yellow
                $afterLog = (Read-Host 'Choice').Trim()
                if ($afterLog -match '^[Rr]$') { continue }
                if ($afterLog -match '^[Qq]$') { return }
                break
            }
            if ($afterFail -match '^[Qq]$') { return }
            break
        }
    }
}

function Show-FinalSummary {
    $script:WizardResults | ConvertTo-Json -Depth 5 | Set-Content -Path $WizardSummaryPath -Encoding UTF8

    $failed = @($script:WizardResults | Where-Object { $_.Status -eq 'Failed' })
    $skipped = @($script:WizardResults | Where-Object { $_.Status -eq 'Skipped' })

    Write-Host ""
    Write-Host "machine-setup complete" -ForegroundColor Green
    Write-Host "======================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Step summary:" -ForegroundColor Cyan

    foreach ($result in $script:WizardResults) {
        $color = switch ($result.Status) {
            'OK' { 'Green' }
            'Skipped' { 'Yellow' }
            'Failed' { 'Red' }
            default { 'Gray' }
        }
        Write-Host ("  [{0}] {1} ({2}s)" -f $result.Status, $result.Heading, $result.Seconds) -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "Wizard log:     $WizardLogPath" -ForegroundColor Cyan
    Write-Host "Wizard summary: $WizardSummaryPath" -ForegroundColor Cyan
    Write-Host "Reboots:        Never automatic. Reboot manually after reviewing this summary if Windows asks." -ForegroundColor Yellow

    $latest = Get-LatestLogFile
    if ($latest) { Write-Host "Latest step log: $($latest.FullName)" -ForegroundColor Cyan }

    if ($failed.Count -gt 0) {
        Write-Host ""
        Write-Host "Failed steps:" -ForegroundColor Yellow
        foreach ($result in $failed) { Write-Host ("  - {0} [{1}]" -f $result.Heading, $result.Key) -ForegroundColor Yellow }
        Write-Host ""
        Write-Host "Run this tool again and choose Custom to retry only failed steps." -ForegroundColor Yellow
    }

    if ($skipped.Count -gt 0) {
        Write-Host ""
        Write-Host "Skipped steps can be run later with Custom mode." -ForegroundColor DarkYellow
    }

    Write-Host ""
    Write-Host "Useful docs inside this repo:" -ForegroundColor Cyan
    Write-Host "  README.md"
    Write-Host "  usb\README.md"
    Write-Host "  slipstream-iso.md"
    Write-Host "  accounts-checklist.md"
    Write-Host "  manual-steps.md"
    Write-Host "  ssh\README.md"
}

try {
    Write-WizardLog 'Wizard started.'
    try {
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop
    } catch {
        Write-WizardLog "Could not set process execution policy: $($_.Exception.Message)"
    }

    try {
        Get-ChildItem -Path $RepoRoot -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
    } catch {
        Write-WizardLog "Could not unblock repo files: $($_.Exception.Message)"
    }

    Show-Welcome

    if ($Auto) {
        $catalog = @(Get-StepCatalog)
        $selected = @(Get-StepsForMode -Catalog $catalog -ModeName $Mode)
        Run-WizardSteps -Steps $selected -Automatic
    } else {
        $selection = Select-InstallMode
        Run-WizardSteps -Steps @($selection.Steps) -Automatic:([bool]$selection.Auto)
    }

    Show-FinalSummary

    $failed = @($script:WizardResults | Where-Object { $_.Status -eq 'Failed' })
    if ($failed.Count -gt 0) { exit 2 }
    exit 0
} catch {
    Write-Host ""
    Write-Host "Wizard failed unexpectedly:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Write-WizardLog "FATAL $($_.Exception.Message)"
    exit 1
}
