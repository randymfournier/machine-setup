[CmdletBinding()]
param(
    [ValidateSet('Detect','Invoke','Verify')]
    [string]$Action = 'Invoke',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

Import-Module (Join-Path $RepoRoot 'core\Setup.Detect.psm1') -Force

$reboot = Test-SetupPendingReboot
switch ($Action) {
    'Detect' { Write-Host "pending reboot: $reboot" }
    'Verify' {
        Write-Host "pending reboot: $reboot"
        if ($reboot) { exit 30 } else { exit 0 }
    }
    default {
        if (-not (Test-SetupAdmin)) {
            Write-Host 'Windows Updates task requires Administrator.'
            exit 20
        }
        if ($reboot) {
            Write-Host 'Windows reports a pending reboot. Skipping update install until after manual reboot.'
            exit 30
        }

        try {
            $session = New-Object -ComObject Microsoft.Update.Session
            $searcher = $session.CreateUpdateSearcher()
            Write-Host 'Searching Windows Update via Microsoft.Update.Session...'
            $result = $searcher.Search("IsInstalled=0 and Type='Software'")
        } catch {
            Write-Host "Windows Update search failed: $($_.Exception.Message)"
            exit 1
        }

        if (-not $result -or $result.Updates.Count -eq 0) {
            Write-Host 'No applicable software updates found.'
            exit 0
        }

        $updates = New-Object -ComObject Microsoft.Update.UpdateColl
        for ($i = 0; $i -lt $result.Updates.Count; $i++) {
            $update = $result.Updates.Item($i)
            if ($update.EulaAccepted -eq $false) {
                try { $update.AcceptEula() } catch { }
            }
            Write-Host ("Queued update: {0}" -f $update.Title)
            [void]$updates.Add($update)
        }

        try {
            Write-Host ("Downloading {0} update(s)..." -f $updates.Count)
            $downloader = $session.CreateUpdateDownloader()
            $downloader.Updates = $updates
            $downloadResult = $downloader.Download()
            if ($downloadResult.ResultCode -gt 3) {
                Write-Host "Windows Update download failed with result code $($downloadResult.ResultCode)."
                exit 1
            }

            Write-Host 'Installing downloaded updates without automatic reboot...'
            $installer = $session.CreateUpdateInstaller()
            $installer.Updates = $updates
            $installResult = $installer.Install()
            if ($installResult.ResultCode -gt 3) {
                Write-Host "Windows Update install failed with result code $($installResult.ResultCode)."
                exit 1
            }

            if ($installResult.RebootRequired -or (Test-SetupPendingReboot)) {
                Write-Host 'Windows Update completed and a manual reboot is required.'
                exit 30
            }

            Write-Host 'Windows Update completed without detected reboot requirement.'
            exit 0
        } catch {
            Write-Host "Windows Update install failed: $($_.Exception.Message)"
            exit 1
        }
    }
}
