function Invoke-SetupNativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [string]$Activity = '',
        [string]$CommandLogRoot = '',
        [int]$TimeoutSeconds = 0,
        [int]$HeartbeatSeconds = 15
    )

    if (-not $Activity) { $Activity = $FilePath }
    if (-not $CommandLogRoot) { $CommandLogRoot = $env:TEMP }
    if (-not (Test-Path $CommandLogRoot)) {
        New-Item -ItemType Directory -Path $CommandLogRoot -Force | Out-Null
    }

    $name = ($Activity -replace '[^A-Za-z0-9_.-]', '_')
    $stamp = Get-Date -Format 'HHmmss'
    $stdoutPath = Join-Path $CommandLogRoot "$stamp-$name.out.log"
    $stderrPath = Join-Path $CommandLogRoot "$stamp-$name.err.log"
    $timedOut = $false

    Write-Host ("> {0} {1}" -f $FilePath, ($Arguments -join ' ')) -ForegroundColor DarkGray

    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -NoNewWindow -PassThru
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        while (-not $process.HasExited) {
            Start-Sleep -Seconds $HeartbeatSeconds
            try { $process.Refresh() } catch { }
            Write-Host ("  [{0:mm\:ss}] {1} still running..." -f $sw.Elapsed, $Activity) -ForegroundColor DarkGray

            if ($TimeoutSeconds -gt 0 -and $sw.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                $timedOut = $true
                try { $process.Kill() } catch { }
                break
            }
        }

        $exitCode = if ($timedOut) { 124 } else { $process.ExitCode }
    } catch {
        $exitCode = 1
        Set-Content -Path $stderrPath -Value $_.Exception.Message -Encoding ASCII -ErrorAction SilentlyContinue
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        TimedOut = $timedOut
        StdOut = $stdoutPath
        StdErr = $stderrPath
    }
}

Export-ModuleMember -Function Invoke-SetupNativeCommand
