function Read-SetupChoice {
    param([string]$Prompt = 'Choice')
    return (Read-Host $Prompt).Trim()
}

function Wait-SetupPause {
    param([string]$Prompt = 'Press Enter to continue')
    [void](Read-Host $Prompt)
}

function Show-SetupHeader {
    param([Parameter(Mandatory=$true)][string]$Title)

    Clear-Host
    Write-Host 'machine-setup' -ForegroundColor Green
    Write-Host '=============' -ForegroundColor Green
    Write-Host ''
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ''
}

function Show-TaskList {
    param([Parameter(Mandatory=$true)]$Tasks)

    $i = 1
    foreach ($task in $Tasks) {
        Write-Host ("  {0,2}. {1} [{2}]" -f $i, $task.label, $task.id)
        $i++
    }
}

function Confirm-SetupRun {
    param(
        [Parameter(Mandatory=$true)][string]$ModeLabel,
        [Parameter(Mandatory=$true)]$Tasks
    )

    Write-Host ''
    Write-Host ("Selected mode: {0}" -f $ModeLabel) -ForegroundColor Cyan
    Write-Host ''
    Show-TaskList -Tasks $Tasks
    Write-Host ''
    Write-Host 'Some tasks are now wired. Nothing runs until you confirm here.' -ForegroundColor Yellow
    $choice = Read-SetupChoice -Prompt 'Run this selection? Y/N'
    return ($choice -match '^[Yy]$')
}

function Select-SetupTasks {
    param([Parameter(Mandatory=$true)]$Manifest)

    $setupTasks = @($Manifest.tasks | Where-Object { $_.type -eq 'setup' })
    $selected = @{}
    foreach ($task in $setupTasks) { $selected[$task.id] = $false }

    while ($true) {
        Show-SetupHeader -Title 'Custom setup checklist'
        Write-Host 'Type a number to toggle it. A = all, N = none, R = run, B = back, Q = quit.'
        Write-Host ''

        for ($i = 0; $i -lt $setupTasks.Count; $i++) {
            $task = $setupTasks[$i]
            $mark = if ($selected[$task.id]) { 'X' } else { ' ' }
            Write-Host ("  [{0}] {1,2}. {2} [{3}]" -f $mark, ($i + 1), $task.label, $task.id)
        }

        Write-Host ''
        $choice = Read-SetupChoice
        switch -Regex ($choice) {
            '^[Qq]$' { exit 0 }
            '^[Bb]$' { return @() }
            '^[Aa]$' { foreach ($task in $setupTasks) { $selected[$task.id] = $true }; continue }
            '^[Nn]$' { foreach ($task in $setupTasks) { $selected[$task.id] = $false }; continue }
            '^[Rr]$' { return @($setupTasks | Where-Object { $selected[$_.id] } | Select-Object -ExpandProperty id) }
            '^\d+$' {
                $n = [int]$choice
                if ($n -ge 1 -and $n -le $setupTasks.Count) {
                    $id = $setupTasks[$n - 1].id
                    $selected[$id] = -not $selected[$id]
                }
            }
        }
    }
}

Export-ModuleMember -Function Read-SetupChoice,Wait-SetupPause,Show-SetupHeader,Show-TaskList,Confirm-SetupRun,Select-SetupTasks
