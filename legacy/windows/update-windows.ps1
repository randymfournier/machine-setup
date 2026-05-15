# windows/update-windows.ps1
# Bulk-install available Windows updates without clicking through Settings.
# This script deliberately does NOT auto-reboot by default because it may be
# called from the setup wizard. Reboots should be a controlled manual choice.

[CmdletBinding()]
param(
    # Emergency/manual override only. The wizard/bootstrap should not pass this.
    [switch]$AllowReboot
)

$ErrorActionPreference = 'Continue'

function Test-PendingReboot {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    )

    foreach ($path in $paths) {
        try {
            if ($path -like '*Session Manager') {
                $value = (Get-ItemProperty -Path $path -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
                if ($value) { return $true }
            } elseif (Test-Path $path) {
                return $true
            }
        } catch { }
    }

    return $false
}

Write-Host "Installing PSWindowsUpdate module..." -ForegroundColor Cyan

# NuGet provider is required for module install
Install-PackageProvider -Name NuGet -Force -Scope AllUsers | Out-Null

# Trust PSGallery so Install-Module doesn't prompt
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# Install the module if not present
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Install-Module PSWindowsUpdate -Force -Scope AllUsers
}

Import-Module PSWindowsUpdate

Write-Host "Checking for updates..." -ForegroundColor Cyan
Get-WindowsUpdate

Write-Host "`nInstalling all available updates (this can take 30-60 minutes)..." -ForegroundColor Cyan

if ($AllowReboot) {
    Write-Warning "AllowReboot was supplied. Windows Update may restart this machine automatically."
    Install-WindowsUpdate -AcceptAll -AutoReboot
} else {
    Write-Host "Automatic reboot is disabled. If updates require a restart, setup will finish first and tell you." -ForegroundColor Yellow
    # -IgnoreReboot prevents PSWindowsUpdate from restarting or stopping the setup flow.
    Install-WindowsUpdate -AcceptAll -IgnoreReboot
}

if (Test-PendingReboot) {
    Write-Host "`nWindows reports that a reboot is pending." -ForegroundColor Yellow
    Write-Host "Finish the setup wizard first, then reboot manually when you choose." -ForegroundColor Yellow
} else {
    Write-Host "`nNo pending reboot was detected by common Windows markers." -ForegroundColor Green
}

Write-Host "Updates step done." -ForegroundColor Green
