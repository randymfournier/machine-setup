$script:SetupLogContext = $null

function New-SetupLogContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$RepoRoot
    )

    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $runRoot = Join-Path (Join-Path $RepoRoot 'logs') $stamp
    $commandsRoot = Join-Path $runRoot 'commands'

    New-Item -ItemType Directory -Path $commandsRoot -Force | Out-Null

    $script:SetupLogContext = [pscustomobject]@{
        RunId = $stamp
        Root = $runRoot
        SetupLog = Join-Path $runRoot 'setup.log'
        ErrorsLog = Join-Path $runRoot 'errors.log'
        SummaryJson = Join-Path $runRoot 'summary.json'
        Commands = $commandsRoot
    }

    New-Item -ItemType File -Path $script:SetupLogContext.SetupLog -Force | Out-Null
    New-Item -ItemType File -Path $script:SetupLogContext.ErrorsLog -Force | Out-Null

    return $script:SetupLogContext
}

function Get-SetupLogContext {
    return $script:SetupLogContext
}

function Write-SetupLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG')]
        [string]$Level = 'INFO'
    )

    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    if ($script:SetupLogContext) {
        Add-Content -Path $script:SetupLogContext.SetupLog -Value $line -Encoding ASCII
        if ($Level -eq 'ERROR') {
            Add-Content -Path $script:SetupLogContext.ErrorsLog -Value $line -Encoding ASCII
        }
    }
}

function Write-SetupSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Summary
    )

    if (-not $script:SetupLogContext) { return }
    $Summary | ConvertTo-Json -Depth 12 | Set-Content -Path $script:SetupLogContext.SummaryJson -Encoding ASCII
}

Export-ModuleMember -Function New-SetupLogContext,Get-SetupLogContext,Write-SetupLog,Write-SetupSummary
