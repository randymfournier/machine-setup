# windows/update-windows.ps1
# Bulk-install all available Windows updates without clicking through Settings.
# Use this on first-run recovery (when you don't have a slipstreamed ISO yet).

$ErrorActionPreference = 'Continue'

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
Write-Host "The machine may reboot itself. After reboot, re-run bootstrap.ps1." -ForegroundColor Yellow

# -AcceptAll: don't prompt per update
# -AutoReboot: reboot if any update demands it
# Remove -AutoReboot if you want to control timing yourself.
Install-WindowsUpdate -AcceptAll -AutoReboot

Write-Host "Updates done." -ForegroundColor Green
