# drivers/export-selected-drivers.ps1
# Exports only the likely Wi-Fi and touchpad driver packages from the current Windows install.
#
# Run from an elevated PowerShell session:
#   .\drivers\export-selected-drivers.ps1
#
# Useful flags:
#   .\drivers\export-selected-drivers.ps1 -ListCandidates
#   .\drivers\export-selected-drivers.ps1 -Destination D:\machine-setup-drivers
#   .\drivers\export-selected-drivers.ps1 -TouchpadKeywords ELAN,Synaptics,Touchpad,"I2C HID"
#
# Defaults include MediaTek Wi-Fi plus Intel Serial IO I2C/GPIO controllers
# that commonly sit underneath Windows Precision touchpads.

[CmdletBinding()]
param(
    [string]$Destination = (Join-Path $PSScriptRoot ("exported-selected-{0}" -f (Get-Date -Format 'yyyy-MM-dd'))),
    [string[]]$WifiKeywords = @('MediaTek','Wi-Fi','Wireless','WLAN','802.11','MT792','MT79'),
    [string[]]$TouchpadKeywords = @('Touchpad','Precision Touchpad','ELAN','Synaptics','I2C HID','HID-compliant touch pad','Serial IO','I2C Host Controller','GPIO Host Controller','INTC1082','INTC1084','7F4C','7F4D','7F4E','7F7A','7F7B'),
    [switch]$ListCandidates
)

$ErrorActionPreference = 'Stop'

function Assert-Admin {
    if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script in PowerShell as Administrator.'
    }
}

function Get-DriverText {
    param($Driver)
    return @(
        $Driver.DeviceName,
        $Driver.DriverProviderName,
        $Driver.Manufacturer,
        $Driver.Description,
        $Driver.FriendlyName,
        $Driver.HardwareID,
        $Driver.InfName,
        $Driver.DeviceClass
    ) -join ' '
}

function Test-KeywordMatch {
    param(
        [Parameter(Mandatory=$true)]$Driver,
        [Parameter(Mandatory=$true)][string[]]$Keywords
    )

    $text = Get-DriverText -Driver $Driver
    foreach ($keyword in $Keywords) {
        if ($keyword -and $text -match [regex]::Escape($keyword)) {
            return $true
        }
    }
    return $false
}

function Show-DriverTable {
    param(
        [Parameter(Mandatory=$true)]$Drivers,
        [Parameter(Mandatory=$true)][string]$Title
    )

    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
    $Drivers |
        Sort-Object DeviceClass, DeviceName, InfName |
        Select-Object DeviceClass, DeviceName, DriverProviderName, InfName, DriverVersion |
        Format-Table -AutoSize
}

function Export-DriverInf {
    param(
        [Parameter(Mandatory=$true)][string]$InfName,
        [Parameter(Mandatory=$true)][string]$Destination
    )

    Write-Host "Exporting $InfName ..." -ForegroundColor Cyan
    $output = & pnputil /export-driver $InfName $Destination 2>&1
    $exitCode = $LASTEXITCODE
    if ($output) { $output | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray } }

    if ($exitCode -ne 0) {
        Write-Warning "pnputil failed to export $InfName with exit code $exitCode."
        return $false
    }

    return $true
}

Assert-Admin
New-Item -ItemType Directory -Path $Destination -Force | Out-Null

$allOemDrivers = Get-CimInstance Win32_PnPSignedDriver |
    Where-Object { $_.InfName -like 'oem*.inf' }

$wifiDrivers = @(
    $allOemDrivers |
        Where-Object {
            ($_.DeviceClass -eq 'NET' -or (Get-DriverText $_) -match 'Wireless|Wi-Fi|WLAN|802\.11') -and
            (Test-KeywordMatch -Driver $_ -Keywords $WifiKeywords)
        }
)

$touchpadDrivers = @(
    $allOemDrivers |
        Where-Object {
            ($_.DeviceClass -in @('Mouse','HIDClass','System','Keyboard')) -and
            (Test-KeywordMatch -Driver $_ -Keywords $TouchpadKeywords)
        }
)

if ($ListCandidates) {
    $wifiCandidates = @(
        $allOemDrivers |
            Where-Object { $_.DeviceClass -eq 'NET' -or (Get-DriverText $_) -match 'Wireless|Wi-Fi|WLAN|802\.11|MediaTek' }
    )
    $touchpadCandidates = @(
        $allOemDrivers |
            Where-Object { $_.DeviceClass -in @('Mouse','HIDClass','System','Keyboard') }
    )

    Show-DriverTable -Drivers $wifiCandidates -Title 'Wi-Fi / network candidates'
    Show-DriverTable -Drivers $touchpadCandidates -Title 'Touchpad / HID / system candidates'
}

Show-DriverTable -Drivers $wifiDrivers -Title 'Selected Wi-Fi driver(s)'
Show-DriverTable -Drivers $touchpadDrivers -Title 'Selected touchpad driver(s)'

if ($wifiDrivers.Count -eq 0) {
    Write-Warning "No Wi-Fi driver matched. Re-run with -ListCandidates, then add a keyword with -WifiKeywords."
}

if ($touchpadDrivers.Count -eq 0) {
    Write-Warning "No touchpad driver matched. Re-run with -ListCandidates, then add a keyword with -TouchpadKeywords."
    Write-Warning "Touchpads may depend on an I2C/Serial IO/System driver, not just a device literally named Touchpad."
}

$selected = @($wifiDrivers + $touchpadDrivers) |
    Where-Object { $_.InfName } |
    Sort-Object InfName -Unique

$exported = New-Object System.Collections.Generic.List[object]
foreach ($driver in $selected) {
    $ok = Export-DriverInf -InfName $driver.InfName -Destination $Destination
    $exported.Add([pscustomobject]@{
        DeviceClass = $driver.DeviceClass
        DeviceName = $driver.DeviceName
        Provider = $driver.DriverProviderName
        Manufacturer = $driver.Manufacturer
        InfName = $driver.InfName
        DriverVersion = $driver.DriverVersion
        Exported = $ok
    }) | Out-Null
}

$manifestPath = Join-Path $Destination 'selected-drivers-manifest.json'
$exported | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8

Write-Host ""
Write-Host "Driver export complete." -ForegroundColor Green
Write-Host "Destination: $Destination" -ForegroundColor Cyan
Write-Host "Manifest:    $manifestPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "Copy this exported folder to your recovery USB. Do not rely on GitHub for these driver files if Wi-Fi may be missing." -ForegroundColor Yellow
