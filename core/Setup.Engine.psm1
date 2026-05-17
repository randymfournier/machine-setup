function Get-SetupManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path
    )

    return Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}

function Get-SetupTaskById {
    param(
        [Parameter(Mandatory=$true)]$Manifest,
        [Parameter(Mandatory=$true)][string]$TaskId
    )

    return $Manifest.tasks | Where-Object { $_.id -eq $TaskId } | Select-Object -First 1
}

function Resolve-SetupTasks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Manifest,
        [Parameter(Mandatory=$true)][string[]]$TaskIds
    )

    $ordered = New-Object System.Collections.Generic.List[string]
    $visiting = @{}
    $visited = @{}

    function Visit([string]$Id) {
        if ($visited[$Id]) { return }
        if ($visiting[$Id]) { throw "Circular dependency detected at task '$Id'." }

        $task = Get-SetupTaskById -Manifest $Manifest -TaskId $Id
        if (-not $task) { throw "Task '$Id' is not defined in setup.json." }

        $visiting[$Id] = $true
        foreach ($dep in @($task.dependencies)) {
            if ($dep) { Visit $dep }
        }
        $visiting.Remove($Id)
        $visited[$Id] = $true
        $ordered.Add($Id) | Out-Null
    }

    foreach ($id in $TaskIds) {
        if ($id) { Visit $id }
    }

    return @($ordered)
}

function Get-TaskDependencyFailures {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Task,
        [Parameter(Mandatory=$true)]$State
    )

    $bad = @()
    foreach ($dep in @($Task.dependencies)) {
        if (-not $dep) { continue }
        $status = Get-TaskStateStatus -State $State -TaskId $dep
        if ($status -ne 'Succeeded') {
            $bad += [pscustomobject]@{ id = $dep; status = $status }
        }
    }
    return $bad
}

function Convert-SetupTaskExitCodeToStatus {
    param([int]$ExitCode)

    switch ($ExitCode) {
        0 { return 'Succeeded' }
        10 { return 'Skipped' }
        20 { return 'Blocked' }
        30 { return 'RequiresReboot' }
        default { return 'Failed' }
    }
}

function Invoke-SetupTaskActionProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$TaskId,
        [Parameter(Mandatory=$true)][string]$TaskPath,
        [Parameter(Mandatory=$true)][string]$Action,
        [Parameter(Mandatory=$true)][string]$RepoRoot
    )

    $logContext = Get-SetupLogContext
    $commandRoot = if ($logContext) { $logContext.Commands } else { $env:TEMP }
    if (-not (Test-Path $commandRoot)) {
        New-Item -ItemType Directory -Path $commandRoot -Force | Out-Null
    }

    $safeName = $TaskId -replace '[^A-Za-z0-9_.-]', '_'
    $stamp = Get-Date -Format 'HHmmss'
    $stdoutPath = Join-Path $commandRoot "$stamp-$safeName-$Action.out.log"
    $stderrPath = Join-Path $commandRoot "$stamp-$safeName-$Action.err.log"

    $arguments = @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $TaskPath,
        '-Action',
        $Action,
        '-RepoRoot',
        $RepoRoot
    )

    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -NoNewWindow -PassThru
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $seen = 0
    $lastText = ''

    while (-not $process.HasExited) {
        Start-Sleep -Seconds 5
        try { $process.Refresh() } catch { }

        $lines = @()
        if (Test-Path $stdoutPath) { $lines += @(Get-Content -Path $stdoutPath -ErrorAction SilentlyContinue) }
        if (Test-Path $stderrPath) { $lines += @(Get-Content -Path $stderrPath -ErrorAction SilentlyContinue) }

        if ($lines.Count -gt $seen) {
            $newLines = @($lines | Select-Object -Skip $seen)
            foreach ($line in $newLines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $lastText = $line
                Write-Host ("       {0}" -f $line) -ForegroundColor DarkGray
                Write-SetupLog -Message "TASK ${TaskId}: $line"
            }
            $seen = $lines.Count
        }
    }

    $sw.Stop()

    $allLines = @()
    if (Test-Path $stdoutPath) { $allLines += @(Get-Content -Path $stdoutPath -ErrorAction SilentlyContinue) }
    if (Test-Path $stderrPath) { $allLines += @(Get-Content -Path $stderrPath -ErrorAction SilentlyContinue) }
    if ($allLines.Count -gt $seen) {
        $newLines = @($allLines | Select-Object -Skip $seen)
        foreach ($line in $newLines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $lastText = $line
            Write-Host ("       {0}" -f $line) -ForegroundColor DarkGray
            Write-SetupLog -Message "TASK ${TaskId}: $line"
        }
    }
    if (-not $lastText -and $allLines.Count -gt 0) {
        $lastText = [string]($allLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1)
    }

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        LastLine = $lastText
        StdOut = $stdoutPath
        StdErr = $stderrPath
    }
}

function Invoke-SetupTaskScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Task,
        [Parameter(Mandatory=$true)]$State,
        [Parameter(Mandatory=$true)][string]$StatePath,
        [Parameter(Mandatory=$true)][string]$RepoRoot
    )

    $taskPath = Join-Path $RepoRoot $Task.path
    $detectResult = $null
    $verifyResult = $null

    if (Test-Path $taskPath) {
        Write-SetupLog -Message "Detect task: $($Task.id)"
        $detectResult = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $taskPath -Action Detect -RepoRoot $RepoRoot 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-SetupLog -Level 'WARN' -Message "Detect returned exit code $LASTEXITCODE for $($Task.id)"
        }
    }

    $detectText = ''
    if ($detectResult) {
        $detectText = [string]($detectResult | Select-Object -Last 1)
    }

    $runningMessage = 'Task is running.'
    if ($detectText) { $runningMessage = "Detect: $detectText" }

    Set-TaskState -State $State -TaskId $Task.id -Status 'Running' -Message $runningMessage
    Save-SetupState -State $State -Path $StatePath

    Write-SetupLog -Message "Task started: $($Task.id)"
    Write-Host ("[RUN] {0}" -f $Task.label) -ForegroundColor Cyan
    Write-Host ("       {0}" -f $Task.description) -ForegroundColor DarkGray
    if ($detectText) { Write-Host ("       Detect: {0}" -f $detectText) -ForegroundColor DarkGray }

    if (Test-Path $taskPath) {
        Write-SetupLog -Message "Invoke task: $($Task.id)"
        $invoke = Invoke-SetupTaskActionProcess -TaskId $Task.id -TaskPath $taskPath -Action 'Invoke' -RepoRoot $RepoRoot
        $invokeExit = $invoke.ExitCode
    } else {
        $invokeExit = 1
        $invoke = [pscustomobject]@{ LastLine = "Task script not found: $taskPath" }
    }

    $status = Convert-SetupTaskExitCodeToStatus -ExitCode $invokeExit
    $invokeText = $invoke.LastLine

    if ($invokeText) {
        $color = if ($status -eq 'Failed') { 'Yellow' } else { 'DarkGray' }
        Write-Host ("       Result: {0}" -f $invokeText) -ForegroundColor $color
    }

    if ($status -in @('Succeeded','RequiresReboot') -and (Test-Path $taskPath)) {
        Write-SetupLog -Message "Verify task: $($Task.id)"
        $verify = Invoke-SetupTaskActionProcess -TaskId $Task.id -TaskPath $taskPath -Action 'Verify' -RepoRoot $RepoRoot
        $verifyExit = $verify.ExitCode
        if ($verifyExit -ne 0) {
            Write-SetupLog -Level 'WARN' -Message "Verify returned exit code $LASTEXITCODE for $($Task.id)"
            $status = Convert-SetupTaskExitCodeToStatus -ExitCode $verifyExit
        }
    }

    $message = 'Task completed.'
    if ($invokeText) { $message = $invokeText }
    if ($verify) {
        if ($verify.LastLine) { $message = $verify.LastLine }
    }

    Set-TaskState -State $State -TaskId $Task.id -Status $status -Message $message -ExitCode $invokeExit
    Save-SetupState -State $State -Path $StatePath
    Write-SetupLog -Message "Task completed: $($Task.id) status=$status exit=$invokeExit"
}

function Invoke-SetupPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Manifest,
        [Parameter(Mandatory=$true)][string[]]$TaskIds,
        [Parameter(Mandatory=$true)]$State,
        [Parameter(Mandatory=$true)][string]$StatePath,
        [Parameter(Mandatory=$true)][string]$RepoRoot,
        [string[]]$SkipTaskIds = @(),
        [switch]$ResumeSucceeded
    )

    $resolved = @(Resolve-SetupTasks -Manifest $Manifest -TaskIds $TaskIds)
    foreach ($id in $resolved) {
        $task = Get-SetupTaskById -Manifest $Manifest -TaskId $id

        if ($ResumeSucceeded -and (Get-TaskStateStatus -State $State -TaskId $id) -eq 'Succeeded') {
            Write-Host ("[SKIP] {0} already succeeded" -f $task.label) -ForegroundColor DarkGray
            continue
        }

        if ($id -in $SkipTaskIds) {
            Set-TaskState -State $State -TaskId $id -Status 'Skipped' -Message 'Skipped by user selection.'
            Save-SetupState -State $State -Path $StatePath
            Write-Host ("[SKIP] {0}" -f $task.label) -ForegroundColor Yellow
            continue
        }

        $dependencyFailures = @(Get-TaskDependencyFailures -Task $task -State $State)
        if ($dependencyFailures.Count -gt 0) {
            $message = 'Blocked by prerequisite task(s): ' + (($dependencyFailures | ForEach-Object { "$($_.id)=$($_.status)" }) -join ', ')
            Set-TaskState -State $State -TaskId $id -Status 'Blocked' -Message $message
            Save-SetupState -State $State -Path $StatePath
            Write-Host ("[BLOCKED] {0}" -f $task.label) -ForegroundColor Yellow
            Write-Host ("          {0}" -f $message) -ForegroundColor DarkYellow
            continue
        }

        Invoke-SetupTaskScript -Task $task -State $State -StatePath $StatePath -RepoRoot $RepoRoot
    }

    return $resolved
}

Export-ModuleMember -Function Get-SetupManifest,Get-SetupTaskById,Resolve-SetupTasks,Get-TaskDependencyFailures,Convert-SetupTaskExitCodeToStatus,Invoke-SetupTaskActionProcess,Invoke-SetupPlan,Invoke-SetupTaskScript
