# windows/apply-tweaks.ps1
# Windows 11 customizations: taskbar left-align, smooth visuals, perf, dark mode.
# Idempotent.

$ErrorActionPreference = 'Stop'

Write-Host "Applying Windows 11 tweaks..." -ForegroundColor Cyan

# --- Taskbar: left align (0 = left, 1 = center) ---------------------------
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
    -Name "TaskbarAl" -Value 0 -Type DWord

# --- Show file extensions --------------------------------------------------
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
    -Name "HideFileExt" -Value 0 -Type DWord

# --- Show hidden files -----------------------------------------------------
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
    -Name "Hidden" -Value 1 -Type DWord

# --- Dark mode (apps + system) ---------------------------------------------
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" `
    -Name "AppsUseLightTheme" -Value 0 -Type DWord
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" `
    -Name "SystemUsesLightTheme" -Value 0 -Type DWord

# --- Smooth visuals: keep animations, font smoothing, drop shadows -------
# UserPreferencesMask: a packed binary blob. The hex below preserves smooth
# animations + ClearType + drop shadows + smooth-edges-of-screen-fonts while
# trimming the heaviest effects. This is the "Adjust for best appearance"
# preset minus a couple of cosmetic toggles you don't notice.
$smoothMask = [byte[]](0x9E, 0x3E, 0x07, 0x80, 0x12, 0x00, 0x00, 0x00)
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" `
    -Name "UserPreferencesMask" -Value $smoothMask -Type Binary

# Force VisualFXSetting = 3 (custom)
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" `
    -Name "VisualFXSetting" -Value 3 -Type DWord -ErrorAction SilentlyContinue

# --- Performance: high-performance power plan ------------------------------
try {
    powercfg /setactive SCHEME_MIN  # SCHEME_MIN = High performance
} catch {
    Write-Host "Could not set high-perf power plan (might be a laptop on battery saver mode)" -ForegroundColor Yellow
}

# --- Disable fast startup (causes random update issues, esp. on dual-boot) -
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" `
    -Name "HiberbootEnabled" -Value 0 -Type DWord

# --- Disable web search in Start menu --------------------------------------
$searchPath = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
if (-not (Test-Path $searchPath)) { New-Item -Path $searchPath -Force | Out-Null }
Set-ItemProperty -Path $searchPath -Name "DisableSearchBoxSuggestions" -Value 1 -Type DWord

# --- Disable Widgets and Chat from taskbar ---------------------------------
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
    -Name "TaskbarDa" -Value 0 -Type DWord  # widgets
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
    -Name "TaskbarMn" -Value 0 -Type DWord  # chat

# --- Restart Explorer to apply -----------------------------------------
Stop-Process -Name explorer -Force
Start-Sleep -Seconds 1

Write-Host "Windows tweaks applied." -ForegroundColor Green
Write-Host "Note: a sign-out/in may be needed for some visual effects to fully take effect." -ForegroundColor Yellow
