function New-SetupState {
    [CmdletBinding()]
    param(
        [string]$SelectedMode = '',
        [string]$LogPath = ''
    )

    return [pscustomobject]@{
        version = 1
        selectedMode = $SelectedMode
        startedAt = (Get-Date).ToString('s')
        updatedAt = (Get-Date).ToString('s')
        logPath = $LogPath
        rebootPending = $false
        tasks = [ordered]@{}
        failures = @()
        blockedTasks = @()
        skippedTasks = @()
    }
}

function Read-SetupState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path
    )

    if (-not (Test-Path $Path)) { return $null }
    return Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}

function Save-SetupState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$State,
        [Parameter(Mandatory=$true)][string]$Path
    )

    $State.updatedAt = (Get-Date).ToString('s')
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $State | ConvertTo-Json -Depth 12 | Set-Content -Path $Path -Encoding ASCII
}

function Set-TaskState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$State,
        [Parameter(Mandatory=$true)][string]$TaskId,
        [Parameter(Mandatory=$true)][string]$Status,
        [string]$Message = '',
        [Nullable[int]]$ExitCode = $null
    )

    $entry = [ordered]@{
        status = $Status
        message = $Message
        exitCode = $ExitCode
        updatedAt = (Get-Date).ToString('s')
    }

    if ($Status -eq 'Failed') {
        $State.failures = @($State.failures + $TaskId | Select-Object -Unique)
    }
    if ($Status -eq 'Blocked') {
        $State.blockedTasks = @($State.blockedTasks + $TaskId | Select-Object -Unique)
    }
    if ($Status -eq 'Skipped') {
        $State.skippedTasks = @($State.skippedTasks + $TaskId | Select-Object -Unique)
    }

    if ($State.tasks -is [hashtable] -or $State.tasks -is [System.Collections.Specialized.OrderedDictionary]) {
        $State.tasks[$TaskId] = $entry
    } else {
        $State.tasks | Add-Member -NotePropertyName $TaskId -NotePropertyValue $entry -Force
    }
}

function Get-TaskStateStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$State,
        [Parameter(Mandatory=$true)][string]$TaskId
    )

    if ($State.tasks -is [hashtable] -or $State.tasks -is [System.Collections.Specialized.OrderedDictionary]) {
        if ($State.tasks.Contains($TaskId)) { return $State.tasks[$TaskId].status }
        return $null
    }

    $property = $State.tasks.PSObject.Properties[$TaskId]
    if ($property) { return $property.Value.status }
    return $null
}

function Convert-SetupStateTasksToList {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$State)

    $out = @()
    if ($State.tasks -is [hashtable] -or $State.tasks -is [System.Collections.Specialized.OrderedDictionary]) {
        foreach ($key in $State.tasks.Keys) {
            $value = $State.tasks[$key]
            $out += [pscustomobject]@{
                id = $key
                status = $value.status
                message = $value.message
                exitCode = $value.exitCode
                updatedAt = $value.updatedAt
            }
        }
        return $out
    }

    foreach ($property in $State.tasks.PSObject.Properties) {
        $value = $property.Value
        $out += [pscustomobject]@{
            id = $property.Name
            status = $value.status
            message = $value.message
            exitCode = $value.exitCode
            updatedAt = $value.updatedAt
        }
    }
    return $out
}

Export-ModuleMember -Function New-SetupState,Read-SetupState,Save-SetupState,Set-TaskState,Get-TaskStateStatus,Convert-SetupStateTasksToList
