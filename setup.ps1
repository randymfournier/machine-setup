# setup.ps1
# Main machine-setup console. Tasks run only after the user chooses a mode
# and confirms the selected checklist.

[CmdletBinding()]
param(
    [ValidateSet('recommended','minimal','apps','dev')]
    [string]$Mode,
    [string[]]$TaskId = @(),
    [string]$ToolId,
    [switch]$ResumeSucceeded,
    [switch]$List
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::ASCII } catch { }

$RepoRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Get-Location).Path
}

$ManifestPath = Join-Path $RepoRoot 'setup.json'
$StatePath = Join-Path (Join-Path $RepoRoot 'state') 'setup-state.json'

Import-Module (Join-Path $RepoRoot 'core\Setup.Logging.psm1') -Force
Import-Module (Join-Path $RepoRoot 'core\Setup.State.psm1') -Force
Import-Module (Join-Path $RepoRoot 'core\Setup.Detect.psm1') -Force
Import-Module (Join-Path $RepoRoot 'core\Setup.Native.psm1') -Force
Import-Module (Join-Path $RepoRoot 'core\Setup.Engine.psm1') -Force
Import-Module (Join-Path $RepoRoot 'core\Setup.UI.psm1') -Force

function Get-ModeById {
    param(
        [Parameter(Mandatory=$true)]$Manifest,
        [Parameter(Mandatory=$true)][string]$Id
    )

    return $Manifest.modes | Where-Object { $_.id -eq $Id } | Select-Object -First 1
}

function Get-TasksByIds {
    param(
        [Parameter(Mandatory=$true)]$Manifest,
        [Parameter(Mandatory=$true)][string[]]$TaskIds
    )

    $tasks = @()
    foreach ($id in $TaskIds) {
        $task = Get-SetupTaskById -Manifest $Manifest -TaskId $id
        if ($task) { $tasks += $task }
    }
    return $tasks
}

function Show-StatusBlock {
    Write-Host 'Status:' -ForegroundColor Cyan
    Write-Host ("  Repo:        {0}" -f $RepoRoot)
    Write-Host ("  Admin:       {0}" -f ($(if (Test-SetupAdmin) { 'YES' } else { 'NO' })))
    Write-Host ("  Network:     {0}" -f ($(if (Test-SetupNetwork) { 'LIKELY AVAILABLE' } else { 'NOT DETECTED / LIMITED' })))
    Write-Host ("  State file:  {0}" -f $StatePath)
    Write-Host ''
}

function Show-LogsAndState {
    param([Parameter(Mandatory=$true)]$Manifest)

    Show-SetupHeader -Title 'Logs and setup state'
    $retryTaskIds = @()

    if (Test-Path $StatePath) {
        Write-Host "State file: $StatePath" -ForegroundColor Cyan
        Write-Host ''
        $state = Read-SetupState -Path $StatePath
        $taskList = @(Convert-SetupStateTasksToList -State $state)

        if ($taskList.Count -gt 0) {
            Write-Host 'Task state:' -ForegroundColor Cyan
            foreach ($item in $taskList) {
                $color = switch ($item.status) {
                    'Succeeded' { 'Green' }
                    'Skipped' { 'Yellow' }
                    'Failed' { 'Red' }
                    'Blocked' { 'Yellow' }
                    'RequiresReboot' { 'Yellow' }
                    default { 'Gray' }
                }
                Write-Host ("  [{0}] {1} - {2}" -f $item.status, $item.id, $item.message) -ForegroundColor $color
            }
            $retryTaskIds = @($taskList | Where-Object { $_.status -in @('Failed','Blocked') } | Select-Object -ExpandProperty id)
        } else {
            Get-Content -Path $StatePath -Raw -ErrorAction SilentlyContinue | Write-Host
        }
    } else {
        Write-Host 'No setup state file found yet.' -ForegroundColor Yellow
    }

    Write-Host ''
    $logRoot = Join-Path $RepoRoot 'logs'
    if (Test-Path $logRoot) {
        $runs = @(Get-ChildItem -Path $logRoot -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 5)
        if ($runs.Count -gt 0) {
            Write-Host 'Recent log runs:' -ForegroundColor Cyan
            foreach ($run in $runs) {
                Write-Host ("  {0}" -f $run.FullName)
            }
        } else {
            Write-Host 'No run log folders found yet.' -ForegroundColor Yellow
        }
    }

    Write-Host ''
    if ($retryTaskIds.Count -gt 0) {
        Write-Host 'R = retry failed/blocked tasks, Enter = back' -ForegroundColor Cyan
        $choice = Read-SetupChoice -Prompt 'Choice'
        if ($choice -match '^[Rr]$') {
            Invoke-ModeSelection -Manifest $Manifest -ModeId 'retry' -TaskIds $retryTaskIds -ResumeSucceeded
        }
    } else {
        Wait-SetupPause
    }
}

function Show-Instructions {
    Show-SetupHeader -Title 'Read instructions'
    $docs = @(
        'README.md',
        'legacy\usb\README.md',
        'docs\slipstream-iso.md',
        'docs\manual-steps.md',
        'docs\accounts-checklist.md',
        'docs\ssh\README.md'
    )

    foreach ($doc in $docs) {
        $path = Join-Path $RepoRoot $doc
        if (Test-Path $path) {
            Write-Host ("  {0}" -f $doc)
        }
    }

    Write-Host ''
    Write-Host 'Use Recovery / maintenance tools for the paged instruction reader.' -ForegroundColor Yellow
    Write-Host ''
    Wait-SetupPause
}

function Show-ToolsMenu {
    param([Parameter(Mandatory=$true)]$Manifest)

    while ($true) {
        Show-SetupHeader -Title 'Recovery / maintenance tools'
        Write-Host 'Tools are separate from normal setup and run only after confirmation.'
        Write-Host ''

        for ($i = 0; $i -lt $Manifest.tools.Count; $i++) {
            $tool = $Manifest.tools[$i]
            Write-Host ("  {0,2}. {1} [{2}]" -f ($i + 1), $tool.label, $tool.id)
        }

        Write-Host ''
        Write-Host '  B. Back'
        Write-Host '  Q. Quit'
        Write-Host ''
        $choice = Read-SetupChoice -Prompt 'Tool choice'

        switch -Regex ($choice) {
            '^[Qq]$' { exit 0 }
            '^[Bb]$' { return }
            '^\d+$' {
                $n = [int]$choice
                if ($n -ge 1 -and $n -le $Manifest.tools.Count) {
                    $tool = $Manifest.tools[$n - 1]
                    $toolPath = Join-Path $RepoRoot $tool.path
                    Write-Host ''
                    Write-Host ("Tool: {0}" -f $tool.label) -ForegroundColor Cyan
                    Write-Host ("       {0}" -f $tool.description) -ForegroundColor DarkGray
                    Write-Host ("       Path: {0}" -f $tool.path) -ForegroundColor DarkGray
                    Write-Host ''
                    if (-not (Test-Path $toolPath)) {
                        Write-Host "Tool script not found: $toolPath" -ForegroundColor Red
                        Wait-SetupPause
                        continue
                    }

                    $ok = Read-SetupChoice -Prompt 'Run this tool? Y/N'
                    if ($ok -notmatch '^[Yy]$') {
                        Write-Host 'Cancelled. Tool did not run.' -ForegroundColor Yellow
                        Start-Sleep -Seconds 1
                        continue
                    }

                    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $toolPath -RepoRoot $RepoRoot
                    $exitCode = $LASTEXITCODE
                    if ($exitCode -eq 0) {
                        Write-Host ''
                        Write-Host '[OK] Tool completed.' -ForegroundColor Green
                    } else {
                        Write-Host ''
                        Write-Host ("[FAILED] Tool returned exit code {0}." -f $exitCode) -ForegroundColor Yellow
                    }
                    Wait-SetupPause
                }
            }
        }
    }
}

function Invoke-ToolById {
    param(
        [Parameter(Mandatory=$true)]$Manifest,
        [Parameter(Mandatory=$true)][string]$Id
    )

    $tool = $Manifest.tools | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $tool) {
        Write-Host "Tool '$Id' is not defined in setup.json." -ForegroundColor Red
        exit 1
    }

    $toolPath = Join-Path $RepoRoot $tool.path
    if (-not (Test-Path $toolPath)) {
        Write-Host "Tool script not found: $toolPath" -ForegroundColor Red
        exit 1
    }

    Write-Host ("Running tool: {0} [{1}]" -f $tool.label, $tool.id) -ForegroundColor Cyan
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $toolPath -RepoRoot $RepoRoot
    exit $LASTEXITCODE
}

function Show-CommandLineUsage {
    param([Parameter(Mandatory=$true)]$Manifest)

    Write-Host 'Modes:' -ForegroundColor Cyan
    foreach ($modeItem in $Manifest.modes) {
        if ($modeItem.id -eq 'custom') { continue }
        Write-Host ("  {0,-14} {1}" -f $modeItem.id, $modeItem.label)
    }

    Write-Host ''
    Write-Host 'Tasks:' -ForegroundColor Cyan
    foreach ($task in $Manifest.tasks) {
        Write-Host ("  {0,-24} {1}" -f $task.id, $task.label)
    }

    Write-Host ''
    Write-Host 'Tools:' -ForegroundColor Cyan
    foreach ($tool in $Manifest.tools) {
        Write-Host ("  {0,-24} {1}" -f $tool.id, $tool.label)
    }
}

function Invoke-ModeSelection {
    param(
        [Parameter(Mandatory=$true)]$Manifest,
        [Parameter(Mandatory=$true)][string]$ModeId,
        [Parameter(Mandatory=$true)][string[]]$TaskIds,
        [switch]$ResumeSucceeded
    )

    if ($TaskIds.Count -eq 0) { return }

    $mode = Get-ModeById -Manifest $Manifest -Id $ModeId
    $modeLabel = if ($mode) { $mode.label } else { $ModeId }
    $resolvedIds = @(Resolve-SetupTasks -Manifest $Manifest -TaskIds $TaskIds)
    $resolvedTasks = @(Get-TasksByIds -Manifest $Manifest -TaskIds $resolvedIds)

    Show-SetupHeader -Title 'Confirm setup run'
    if (-not (Confirm-SetupRun -ModeLabel $modeLabel -Tasks $resolvedTasks)) {
        Write-Host 'Cancelled. Nothing ran.' -ForegroundColor Yellow
        Start-Sleep -Seconds 1
        return
    }

    $logContext = New-SetupLogContext -RepoRoot $RepoRoot
    $state = $null
    if ($ResumeSucceeded -and (Test-Path $StatePath)) {
        $state = Read-SetupState -Path $StatePath
        $state.selectedMode = $ModeId
        $state.logPath = $logContext.Root
    }
    if (-not $state) {
        $state = New-SetupState -SelectedMode $ModeId -LogPath $logContext.Root
    }

    foreach ($id in $resolvedIds) {
        if ($ResumeSucceeded -and (Get-TaskStateStatus -State $state -TaskId $id) -eq 'Succeeded') { continue }
        Set-TaskState -State $state -TaskId $id -Status 'Ready' -Message 'Ready to run.'
    }
    Save-SetupState -State $state -Path $StatePath

    Write-SetupLog -Message "Setup started. mode=$ModeId"
    Show-SetupHeader -Title 'Running setup tasks'
    Write-Host ("Log folder: {0}" -f $logContext.Root) -ForegroundColor Cyan
    Write-Host ''

    $ran = @(Invoke-SetupPlan -Manifest $Manifest -TaskIds $TaskIds -State $state -StatePath $StatePath -RepoRoot $RepoRoot -ResumeSucceeded:$ResumeSucceeded)
    $state.rebootPending = Test-SetupPendingReboot
    Save-SetupState -State $state -Path $StatePath

    $summary = [pscustomobject]@{
        mode = $ModeId
        taskIds = $ran
        statePath = $StatePath
        rebootPending = $state.rebootPending
        completedAt = (Get-Date).ToString('s')
    }
    Write-SetupSummary -Summary $summary
    Write-SetupLog -Message "Setup finished. mode=$ModeId"

    $taskSummary = @(Convert-SetupStateTasksToList -State $state)
    $succeeded = @($taskSummary | Where-Object { $_.status -eq 'Succeeded' }).Count
    $skipped = @($taskSummary | Where-Object { $_.status -eq 'Skipped' }).Count
    $blocked = @($taskSummary | Where-Object { $_.status -eq 'Blocked' }).Count
    $failed = @($taskSummary | Where-Object { $_.status -eq 'Failed' }).Count

    Write-Host ''
    Write-Host 'Setup run complete.' -ForegroundColor Green
    Write-Host ("Summary: {0} succeeded, {1} skipped, {2} blocked, {3} failed" -f $succeeded, $skipped, $blocked, $failed) -ForegroundColor Cyan
    Write-Host ("State:   {0}" -f $StatePath) -ForegroundColor Cyan
    Write-Host ("JSON:    {0}" -f $logContext.SummaryJson) -ForegroundColor Cyan
    Write-Host 'Only the selected task scripts were run.' -ForegroundColor Yellow
    Write-Host ''
    Wait-SetupPause
}

if (-not (Test-Path $ManifestPath)) {
    Write-Host "setup.json was not found at: $ManifestPath" -ForegroundColor Red
    exit 1
}

$manifest = Get-SetupManifest -Path $ManifestPath

if ($List) {
    Show-CommandLineUsage -Manifest $manifest
    exit 0
}

if (-not (Test-SetupAdmin)) {
    Write-Host 'Run this setup console as Administrator.' -ForegroundColor Red
    exit 1
}

if ($TaskId.Count -gt 0) {
    Invoke-ModeSelection -Manifest $manifest -ModeId 'custom' -TaskIds $TaskId -ResumeSucceeded:$ResumeSucceeded
    exit 0
}

if ($Mode) {
    $selectedMode = Get-ModeById -Manifest $manifest -Id $Mode
    if (-not $selectedMode) {
        Write-Host "Mode '$Mode' is not defined in setup.json." -ForegroundColor Red
        exit 1
    }

    Invoke-ModeSelection -Manifest $manifest -ModeId $Mode -TaskIds @($selectedMode.tasks) -ResumeSucceeded:$ResumeSucceeded
    exit 0
}

if ($ToolId) {
    Invoke-ToolById -Manifest $manifest -Id $ToolId
}

while ($true) {
    Show-SetupHeader -Title 'Main setup console'
    Show-StatusBlock
    Write-Host '  1. Automatic recommended setup'
    Write-Host '  2. Custom setup checklist'
    Write-Host '  3. Minimal recovery setup'
    Write-Host '  4. Apps only'
    Write-Host '  5. Dev environment only'
    Write-Host '  6. Recovery / maintenance tools'
    Write-Host '  7. Logs and setup state'
    Write-Host '  8. Read instructions'
    Write-Host '  9. Quit'
    Write-Host ''
    Write-Host 'Nothing installs until you choose a mode and confirm.' -ForegroundColor DarkGray
    Write-Host 'Some tasks may install software or modify Windows after confirmation.' -ForegroundColor DarkGray
    Write-Host ''

    $choice = Read-SetupChoice -Prompt 'Choice'
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }

    switch -Regex ($choice) {
        '^1$' {
            $mode = Get-ModeById -Manifest $manifest -Id 'recommended'
            Invoke-ModeSelection -Manifest $manifest -ModeId 'recommended' -TaskIds @($mode.tasks)
        }
        '^2$' {
            $ids = @(Select-SetupTasks -Manifest $manifest)
            Invoke-ModeSelection -Manifest $manifest -ModeId 'custom' -TaskIds $ids
        }
        '^3$' {
            $mode = Get-ModeById -Manifest $manifest -Id 'minimal'
            Invoke-ModeSelection -Manifest $manifest -ModeId 'minimal' -TaskIds @($mode.tasks)
        }
        '^4$' {
            $mode = Get-ModeById -Manifest $manifest -Id 'apps'
            Invoke-ModeSelection -Manifest $manifest -ModeId 'apps' -TaskIds @($mode.tasks)
        }
        '^5$' {
            $mode = Get-ModeById -Manifest $manifest -Id 'dev'
            Invoke-ModeSelection -Manifest $manifest -ModeId 'dev' -TaskIds @($mode.tasks)
        }
        '^6$' { Show-ToolsMenu -Manifest $manifest }
        '^7$' { Show-LogsAndState -Manifest $manifest }
        '^8$' { Show-Instructions }
        '^9$' { exit 0 }
        '^[Qq]$' { exit 0 }
        default {
            Write-Host 'Choose 1-9.' -ForegroundColor Yellow
            Start-Sleep -Seconds 1
        }
    }
}
