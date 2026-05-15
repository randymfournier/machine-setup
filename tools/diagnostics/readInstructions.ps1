[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

function Show-TextFilePaged {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Title
    )

    Clear-Host
    Write-Host $Title -ForegroundColor Green
    Write-Host ('=' * [Math]::Min($Title.Length, 60)) -ForegroundColor Green
    Write-Host ''

    if (-not (Test-Path $Path)) {
        Write-Host "File not found: $Path" -ForegroundColor Yellow
        return
    }

    $count = 0
    Get-Content -Path $Path -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host $_
        $count++
        if ($count -ge 28) {
            $count = 0
            Write-Host ''
            $choice = (Read-Host 'Press Enter for more, Q to stop').Trim()
            if ($choice -match '^[Qq]$') { throw 'StopPaging' }
        }
    }
}

$docs = @(
    [pscustomobject]@{ Title = 'Main README'; Path = 'README.md' },
    [pscustomobject]@{ Title = 'Recovery USB instructions'; Path = 'legacy\usb\README.md' },
    [pscustomobject]@{ Title = 'Slipstream/rebuild boot USB instructions'; Path = 'docs\slipstream-iso.md' },
    [pscustomobject]@{ Title = 'Manual steps'; Path = 'docs\manual-steps.md' },
    [pscustomobject]@{ Title = 'Accounts checklist'; Path = 'docs\accounts-checklist.md' },
    [pscustomobject]@{ Title = 'SSH restore instructions'; Path = 'docs\ssh\README.md' }
)

while ($true) {
    Clear-Host
    Write-Host 'Read instructions' -ForegroundColor Green
    Write-Host '=================' -ForegroundColor Green
    Write-Host ''
    for ($i = 0; $i -lt $docs.Count; $i++) {
        Write-Host ("  {0}. {1}" -f ($i + 1), $docs[$i].Title)
    }
    Write-Host '  B. Back'
    Write-Host ''

    $choice = (Read-Host 'Choice').Trim()
    if ($choice -match '^[BbQq]$') { exit 0 }
    if ($choice -match '^\d+$') {
        $n = [int]$choice
        if ($n -ge 1 -and $n -le $docs.Count) {
            try {
                Show-TextFilePaged -Path (Join-Path $RepoRoot $docs[$n - 1].Path) -Title $docs[$n - 1].Title
            } catch {
                if ($_.Exception.Message -ne 'StopPaging') { throw }
            }
            [void](Read-Host 'Press Enter to continue')
        }
    }
}
