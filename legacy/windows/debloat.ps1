# windows/debloat.ps1
# Removes preinstalled Windows 11 bloat and disables telemetry/ads.
# OPT-IN: not run by default by bootstrap.ps1 -- you call this explicitly.
#
# Run as Administrator:
#   .\windows\debloat.ps1
#
# IMPORTANT: read through the lists below before running. If you actually use
# any of these (Mail, OneNote, Phone Link, etc.), comment them out first.
#
# What this DOES NOT touch:
#   - Edge / WebView2          (you need WebView2 for Tauri)
#   - Microsoft Store          (winget proxies through it sometimes)
#   - Photos, Calculator, Snipping Tool, Notepad, Paint  (used by everything)
#   - Windows Search           (breaks file search if disabled)
#   - Defender                 (you can disable separately if you have replacement AV)

$ErrorActionPreference = 'Continue'

if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Run as Administrator." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host " Windows 11 debloat" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

# --- 1. Appx packages to remove -------------------------------------------
# Removes for current user AND from the install image so new users don't get them.
# Comment any line out to keep that app.

$appsToRemove = @(
    # Gaming bloat (you use Steam, so all of this is safe)
    'Microsoft.Xbox.TCUI'
    'Microsoft.XboxApp'
    'Microsoft.XboxGameOverlay'
    'Microsoft.XboxGamingOverlay'
    'Microsoft.XboxIdentityProvider'
    'Microsoft.XboxSpeechToTextOverlay'
    'Microsoft.GamingApp'

    # Casual / preinstalled distractions
    'Microsoft.MicrosoftSolitaireCollection'
    'Microsoft.MixedReality.Portal'
    'Microsoft.Microsoft3DViewer'

    # Microsoft consumer junk
    'MicrosoftTeams'                       # consumer Teams (the chat one)
    'Microsoft.MicrosoftOfficeHub'         # "Get Office" upsell tile
    'Microsoft.GetHelp'
    'Microsoft.Getstarted'
    'Microsoft.WindowsFeedbackHub'
    'Microsoft.People'
    'Microsoft.SkypeApp'
    'Microsoft.YourPhone'                  # Phone Link (comment out if you use it)
    'Microsoft.Wallet'
    'Microsoft.WindowsMaps'

    # Mail/Calendar -- you use Proton Mail, safe to remove.
    # Note: Microsoft is replacing this with the new Outlook app anyway.
    'Microsoft.WindowsCommunicationsApps'
    'Microsoft.OutlookForWindows'

    # Media apps you don't need (you have VLC / OBS / others if you want)
    'Microsoft.ZuneVideo'                  # Movies & TV
    # 'Microsoft.ZuneMusic'                # Media Player -- COMMENTED, used as default audio player
    'Microsoft.WindowsSoundRecorder'

    # MSN / Bing junk
    'Microsoft.BingNews'
    'Microsoft.BingWeather'
    'Microsoft.BingSearch'
    'MicrosoftWindows.Client.WebExperience'  # Widgets (news/weather popup)

    # Productivity bits you said you don't need
    'Microsoft.Office.OneNote'
    'Microsoft.Todos'
    'Microsoft.PowerAutomateDesktop'
    # 'Microsoft.MicrosoftStickyNotes'     # COMMENTED, harmless and some people like it
    # 'Microsoft.WindowsAlarms'            # COMMENTED, clock/timer/stopwatch is occasionally useful

    # Cortana (deprecated by Microsoft anyway)
    'Microsoft.549981C3F5F10'

    # Quick Assist (remote support tool, security hygiene to remove)
    'MicrosoftCorporationII.QuickAssist'

    # Clipchamp (video editor; you have other tools)
    'Clipchamp.Clipchamp'

    # Family Safety (parental controls)
    'MicrosoftCorporationII.MicrosoftFamily'
)

Write-Host "--- Removing Appx packages ---" -ForegroundColor Yellow
foreach ($app in $appsToRemove) {
    $pkg = Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue
    if ($pkg) {
        Write-Host "  [-] $app" -ForegroundColor DarkGray
        $pkg | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    }
    # Also remove from the provisioned packages so new user accounts don't get them
    $prov = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $app }
    if ($prov) {
        Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue | Out-Null
    }
}
Write-Host "  [OK] Appx removal pass complete" -ForegroundColor Green

# --- 2. Edge: hide it but DO NOT remove (WebView2 dependency) -------------
Write-Host ""
Write-Host "--- Edge: hiding shortcuts (NOT uninstalling, WebView2 needed for Tauri) ---" -ForegroundColor Yellow

# Stop Edge from being pinned to taskbar / Start by default
$edgePath = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application"
if (Test-Path $edgePath) {
    Write-Host "  [i] Edge is installed at $edgePath (kept for WebView2)" -ForegroundColor DarkGray
}

# Disable Edge auto-launch on startup
$edgeAutoLaunchKeys = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
)
foreach ($k in $edgeAutoLaunchKeys) {
    Get-ItemProperty -Path $k -ErrorAction SilentlyContinue | ForEach-Object {
        $_.PSObject.Properties | Where-Object { $_.Name -like '*Edge*' -or $_.Name -like '*MicrosoftEdge*' } | ForEach-Object {
            Remove-ItemProperty -Path $k -Name $_.Name -ErrorAction SilentlyContinue
            Write-Host "  [-] removed autostart: $($_.Name)" -ForegroundColor DarkGray
        }
    }
}

# Don't preload Edge tabs at login
$edgePolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main'
if (-not (Test-Path $edgePolicy)) { New-Item -Path $edgePolicy -Force | Out-Null }
Set-ItemProperty -Path $edgePolicy -Name 'AllowPrelaunch' -Value 0 -Type DWord -Force
Write-Host "  [OK] Edge prelaunch disabled" -ForegroundColor Green

# --- 3. Telemetry & data collection ---------------------------------------
Write-Host ""
Write-Host "--- Telemetry: minimum allowed level + disable scheduled tasks ---" -ForegroundColor Yellow

# Set telemetry to lowest setting allowed by Win11 (Security/Required)
$telPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
if (-not (Test-Path $telPath)) { New-Item -Path $telPath -Force | Out-Null }
Set-ItemProperty -Path $telPath -Name 'AllowTelemetry' -Value 1 -Type DWord -Force

# Disable a few telemetry-related scheduled tasks
$tasksToDisable = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\Feedback\Siuf\DmClient',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
)
foreach ($t in $tasksToDisable) {
    Disable-ScheduledTask -TaskPath (Split-Path $t) -TaskName (Split-Path $t -Leaf) -ErrorAction SilentlyContinue | Out-Null
}
Write-Host "  [OK] Telemetry tasks disabled" -ForegroundColor Green

# --- 4. Disable suggested content, ads, and "tips" ------------------------
Write-Host ""
Write-Host "--- Suggestions/ads in Start, File Explorer, Lock Screen ---" -ForegroundColor Yellow

$cdmPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$cdmKeys = @{
    'ContentDeliveryAllowed'             = 0
    'OemPreInstalledAppsEnabled'         = 0
    'PreInstalledAppsEnabled'            = 0
    'PreInstalledAppsEverEnabled'        = 0
    'SilentInstalledAppsEnabled'         = 0
    'SubscribedContent-310093Enabled'    = 0   # Welcome experience suggestions
    'SubscribedContent-338387Enabled'    = 0   # Lock screen tips
    'SubscribedContent-338388Enabled'    = 0   # Start menu suggestions
    'SubscribedContent-338389Enabled'    = 0   # Tips, tricks, suggestions
    'SubscribedContent-353698Enabled'    = 0   # Suggested apps in timeline
    'SystemPaneSuggestionsEnabled'       = 0
}
foreach ($k in $cdmKeys.Keys) {
    Set-ItemProperty -Path $cdmPath -Name $k -Value $cdmKeys[$k] -Type DWord -Force -ErrorAction SilentlyContinue
}

# File Explorer: stop "sync provider notifications" (literally ads)
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' `
    -Name 'ShowSyncProviderNotifications' -Value 0 -Type DWord

# Lock screen Spotlight ads
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen' `
    -Name 'SlideshowEnabled' -Value 0 -Type DWord -ErrorAction SilentlyContinue

# Start menu: hide "Recently added" / suggestions
$startPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
if (-not (Test-Path $startPolicy)) { New-Item -Path $startPolicy -Force | Out-Null }
Set-ItemProperty -Path $startPolicy -Name 'HideRecommendedSection' -Value 1 -Type DWord -Force

Write-Host "  [OK] Suggestions/ads disabled" -ForegroundColor Green

# --- 5. Activity history & Timeline ---------------------------------------
Write-Host ""
Write-Host "--- Disabling Activity History ---" -ForegroundColor Yellow

$ahPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
if (-not (Test-Path $ahPath)) { New-Item -Path $ahPath -Force | Out-Null }
Set-ItemProperty -Path $ahPath -Name 'EnableActivityFeed'        -Value 0 -Type DWord -Force
Set-ItemProperty -Path $ahPath -Name 'PublishUserActivities'     -Value 0 -Type DWord -Force
Set-ItemProperty -Path $ahPath -Name 'UploadUserActivities'      -Value 0 -Type DWord -Force
Write-Host "  [OK] Activity History disabled" -ForegroundColor Green

# --- 6. Restart Explorer to apply changes ---------------------------------
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

Write-Host ""
Write-Host "===================================================" -ForegroundColor Green
Write-Host " Debloat complete." -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Some items may need a sign-out/in or full reboot to fully apply." -ForegroundColor Cyan
Write-Host "If anything important got removed, install it back from the Microsoft Store." -ForegroundColor Cyan
Write-Host ""
Write-Host "For deeper tweaks (services, more privacy controls, GUI), check out:" -ForegroundColor Cyan
Write-Host "  https://github.com/ChrisTitusTech/winutil" -ForegroundColor White
Write-Host "  Run with: irm https://christitus.com/win | iex" -ForegroundColor DarkGray
