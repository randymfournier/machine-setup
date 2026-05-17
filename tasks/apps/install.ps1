[CmdletBinding()]
param(
    [ValidateSet('Detect','Invoke','Verify')]
    [string]$Action = 'Invoke',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

Import-Module (Join-Path $RepoRoot 'core\Setup.Detect.psm1') -Force

$manifestPath = Join-Path $RepoRoot 'assets\packages\winget-packages.json'

$bestEffortDependencyPackages = @(
    'Microsoft.UI.Xaml.2.7',
    'Microsoft.DotNet.Native.Runtime',
    'Microsoft.VCLibs.Desktop.14',
    'Microsoft.VCLibs.14',
    'Microsoft.WindowsAppRuntime.1.1'
)

function Get-CleanWingetOutput {
    param([string[]]$Lines)

    foreach ($line in @($Lines)) {
        $text = ([string]$line) -replace "`r", ''
        $text = $text.Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($text -match '^[\\|/\-]+$') { continue }
        if ($text -match '^[\.\s]+$') { continue }
        $text
    }
}

function Invoke-WingetPackageInstall {
    param(
        [Parameter(Mandatory=$true)][string]$PackageId,
        [Parameter(Mandatory=$true)][string]$DisplayName,
        [Parameter(Mandatory=$true)][string]$SourceName,
        [Parameter(Mandatory=$true)][int]$Index,
        [Parameter(Mandatory=$true)][int]$Total
    )

    $tempBase = Join-Path $env:TEMP ("machine-setup-winget-{0}" -f ([guid]::NewGuid().ToString('N')))
    $stdoutPath = "$tempBase.out.log"
    $stderrPath = "$tempBase.err.log"

    $args = @(
        'install',
        '--id', $PackageId,
        '-e',
        '--source', $SourceName,
        '--accept-package-agreements',
        '--accept-source-agreements',
        '--silent',
        '--disable-interactivity'
    )

    Write-Host ''
    Write-Host ("[{0}/{1}] Installing {2}" -f $Index, $Total, $DisplayName) -ForegroundColor Cyan
    Write-Progress -Activity 'Installing apps' -Status $DisplayName -PercentComplete ([Math]::Floor((($Index - 1) / [Math]::Max($Total, 1)) * 100))

    try {
        $process = Start-Process -FilePath 'winget' -ArgumentList $args -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -NoNewWindow -PassThru
        while (-not $process.HasExited) {
            Start-Sleep -Milliseconds 500
            try { $process.Refresh() } catch { }
            Write-Progress -Activity 'Installing apps' -Status ("Installing {0}" -f $DisplayName) -PercentComplete ([Math]::Floor((($Index - 1) / [Math]::Max($Total, 1)) * 100))
        }

        $stdout = @()
        $stderr = @()
        if (Test-Path $stdoutPath) { $stdout = @(Get-Content -Path $stdoutPath -ErrorAction SilentlyContinue) }
        if (Test-Path $stderrPath) { $stderr = @(Get-Content -Path $stderrPath -ErrorAction SilentlyContinue) }
        $clean = @(Get-CleanWingetOutput -Lines @($stdout + $stderr))
        $joined = $clean -join ' '

        $alreadyCurrent = ($joined -match 'already installed|No available upgrade|No newer package versions|Found an existing package already installed')
        $installed = ($joined -match 'Successfully installed|Installer hash verified successfully|Installation complete')

        if ($process.ExitCode -eq 0 -or $alreadyCurrent -or $installed) {
            if ($alreadyCurrent) {
                Write-Host ("[OK] {0} already installed/current" -f $DisplayName) -ForegroundColor Green
                return [pscustomobject]@{ PackageId = $PackageId; DisplayName = $DisplayName; Status = 'Current'; ExitCode = $process.ExitCode; Detail = 'Already installed/current' }
            }

            Write-Host ("[OK] {0} installed" -f $DisplayName) -ForegroundColor Green
            return [pscustomobject]@{ PackageId = $PackageId; DisplayName = $DisplayName; Status = 'Installed'; ExitCode = $process.ExitCode; Detail = 'Installed' }
        }

        $detail = if ($clean.Count -gt 0) { ($clean | Select-Object -Last 3) -join ' | ' } else { "winget exit code $($process.ExitCode)" }
        if ($PackageId -in $bestEffortDependencyPackages) {
            Write-Host ("[WARN] {0} dependency install failed; continuing." -f $DisplayName) -ForegroundColor Yellow
            Write-Host ("       {0}" -f $detail) -ForegroundColor DarkYellow
            return [pscustomobject]@{ PackageId = $PackageId; DisplayName = $DisplayName; Status = 'OptionalFailed'; ExitCode = $process.ExitCode; Detail = $detail }
        }

        Write-Host ("[FAILED] {0}" -f $DisplayName) -ForegroundColor Red
        Write-Host ("         {0}" -f $detail) -ForegroundColor Yellow
        return [pscustomobject]@{ PackageId = $PackageId; DisplayName = $DisplayName; Status = 'Failed'; ExitCode = $process.ExitCode; Detail = $detail }
    } catch {
        if ($PackageId -in $bestEffortDependencyPackages) {
            Write-Host ("[WARN] {0} dependency install failed; continuing." -f $DisplayName) -ForegroundColor Yellow
            Write-Host ("       {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
            return [pscustomobject]@{ PackageId = $PackageId; DisplayName = $DisplayName; Status = 'OptionalFailed'; ExitCode = 1; Detail = $_.Exception.Message }
        }

        Write-Host ("[FAILED] {0}" -f $DisplayName) -ForegroundColor Red
        Write-Host ("         {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        return [pscustomobject]@{ PackageId = $PackageId; DisplayName = $DisplayName; Status = 'Failed'; ExitCode = 1; Detail = $_.Exception.Message }
    } finally {
        Remove-Item -Path $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue
    }
}

switch ($Action) {
    'Detect' { Write-Host "apps manifest exists: $(Test-Path $manifestPath); winget healthy: $(Test-SetupWingetHealthy)" }
    'Verify' {
        $ready = ((Test-Path $manifestPath) -and (Test-SetupWingetHealthy))
        Write-Host "apps task prerequisites ready: $ready"
        if ($ready) { exit 0 } else { exit 1 }
    }
    default {
        if (-not (Test-Path $manifestPath)) {
            Write-Host "App manifest not found: $manifestPath"
            exit 1
        }
        if (-not (Test-SetupWingetHealthy)) {
            Write-Host 'winget is not healthy enough to install apps.'
            exit 20
        }

        $manifest = Get-Content -Path $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json
        $packages = @()
        foreach ($source in $manifest.Sources) {
            $sourceName = $source.SourceDetails.Name
            if (-not $sourceName) { $sourceName = 'winget' }
            foreach ($pkg in $source.Packages) {
                if ($pkg.PackageIdentifier) {
                    $packages += [pscustomobject]@{
                        Id = $pkg.PackageIdentifier
                        DisplayName = if ($pkg.DisplayName) { $pkg.DisplayName } else { $pkg.PackageIdentifier }
                        Source = $sourceName
                    }
                }
            }
        }

        if ($packages.Count -eq 0) {
            Write-Host 'No apps were found in the winget manifest.'
            exit 10
        }

        Write-Host ''
        Write-Host ("Installing apps from manifest: {0} package(s)" -f $packages.Count) -ForegroundColor Cyan

        $results = New-Object System.Collections.Generic.List[object]
        for ($i = 0; $i -lt $packages.Count; $i++) {
            $pkg = $packages[$i]
            $result = Invoke-WingetPackageInstall -PackageId $pkg.Id -DisplayName $pkg.DisplayName -SourceName $pkg.Source -Index ($i + 1) -Total $packages.Count
            $results.Add($result) | Out-Null
        }
        Write-Progress -Activity 'Installing apps' -Completed

        $installed = @($results | Where-Object { $_.Status -eq 'Installed' }).Count
        $current = @($results | Where-Object { $_.Status -eq 'Current' }).Count
        $optionalFailed = @($results | Where-Object { $_.Status -eq 'OptionalFailed' })
        $failed = @($results | Where-Object { $_.Status -eq 'Failed' })

        Write-Host ''
        Write-Host ("Apps complete: {0} installed, {1} already current, {2} dependency warning(s), {3} failed." -f $installed, $current, $optionalFailed.Count, $failed.Count) -ForegroundColor Cyan
        if ($optionalFailed.Count -gt 0) {
            Write-Host 'Dependency warnings:' -ForegroundColor Yellow
            foreach ($warning in $optionalFailed) {
                Write-Host ("  - {0}: {1}" -f $warning.DisplayName, $warning.Detail) -ForegroundColor Yellow
            }
        }
        if ($failed.Count -gt 0) {
            Write-Host 'Failed apps:' -ForegroundColor Yellow
            foreach ($failure in $failed) {
                Write-Host ("  - {0}: {1}" -f $failure.DisplayName, $failure.Detail) -ForegroundColor Yellow
            }
            exit 1
        }

        exit 0
    }
}
