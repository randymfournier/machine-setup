# backup-current-configs.ps1
# Snapshots your current Windows config to a timestamped folder on Desktop.
# READ-ONLY -- touches nothing on your live system.
# Run this BEFORE testing anything from machine-setup, so you have a rollback.

$ErrorActionPreference = 'Continue'

$stamp      = Get-Date -Format "yyyy-MM-dd_HHmm"
$backupRoot = "$env:USERPROFILE\Desktop\config-backup-$stamp"
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

Write-Host ""
Write-Host "Backing up current configs to:" -ForegroundColor Cyan
Write-Host "  $backupRoot" -ForegroundColor White
Write-Host ""

function Copy-IfExists($src, $destFolder, $label) {
    if (Test-Path $src) {
        New-Item -ItemType Directory -Path $destFolder -Force | Out-Null
        Copy-Item $src $destFolder -Recurse -Force
        Write-Host "  [OK]  $label" -ForegroundColor Green
    } else {
        Write-Host "  [--]  $label (not present)" -ForegroundColor DarkGray
    }
}

Write-Host "--- Shell ---" -ForegroundColor Yellow
Copy-IfExists "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"        "$backupRoot\powershell" "PowerShell 7 profile"
Copy-IfExists "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" "$backupRoot\powershell" "Windows PowerShell 5.1 profile"
Copy-IfExists "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" "$backupRoot\windows-terminal" "Windows Terminal settings"
Copy-IfExists "$env:USERPROFILE\.config\oh-my-posh" "$backupRoot\oh-my-posh" "oh-my-posh config (if any)"

Write-Host ""
Write-Host "--- Git ---" -ForegroundColor Yellow
Copy-IfExists "$env:USERPROFILE\.gitconfig"        "$backupRoot\git" ".gitconfig"
Copy-IfExists "$env:USERPROFILE\.gitignore_global" "$backupRoot\git" ".gitignore_global"

Write-Host ""
Write-Host "--- VS Code ---" -ForegroundColor Yellow
$vscodeUser = "$env:APPDATA\Code\User"
Copy-IfExists "$vscodeUser\settings.json"    "$backupRoot\vscode" "VS Code settings.json"
Copy-IfExists "$vscodeUser\keybindings.json" "$backupRoot\vscode" "VS Code keybindings.json"
Copy-IfExists "$vscodeUser\snippets"         "$backupRoot\vscode" "VS Code snippets"

if (Get-Command code -ErrorAction SilentlyContinue) {
    code --list-extensions > "$backupRoot\vscode-extensions.txt"
    Write-Host "  [OK]  VS Code extensions list" -ForegroundColor Green
} else {
    Write-Host "  [--]  VS Code 'code' CLI not on PATH (skipped extensions list)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "--- Currently installed apps (winget) ---" -ForegroundColor Yellow
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "  [..]  Exporting (this takes about 30 sec)..." -ForegroundColor Cyan
    winget export -o "$backupRoot\winget-packages-CURRENT.json" --accept-source-agreements 2>&1 | Out-Null
    Write-Host "  [OK]  winget packages" -ForegroundColor Green
} else {
    Write-Host "  [--]  winget not found" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "--- SSH (this includes PRIVATE keys, handle carefully) ---" -ForegroundColor Yellow
$sshDir = "$env:USERPROFILE\.ssh"
if (Test-Path $sshDir) {
    Copy-Item $sshDir "$backupRoot\ssh-PRIVATE-KEYS-INSIDE" -Recurse -Force
    Write-Host "  [!!]  .ssh folder copied" -ForegroundColor Yellow
    Write-Host "        Move into encrypted Proton Drive 7z, then DELETE the unencrypted copy" -ForegroundColor Yellow
} else {
    Write-Host "  [--]  No .ssh folder found" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "--- Registry tweaks reference ---" -ForegroundColor Yellow
$taskbarAl   = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'    -Name TaskbarAl            -ErrorAction SilentlyContinue).TaskbarAl
$hideFileExt = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'    -Name HideFileExt          -ErrorAction SilentlyContinue).HideFileExt
$hidden      = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'    -Name Hidden               -ErrorAction SilentlyContinue).Hidden
$appsLight   = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'   -Name AppsUseLightTheme    -ErrorAction SilentlyContinue).AppsUseLightTheme
$sysLight    = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'   -Name SystemUsesLightTheme -ErrorAction SilentlyContinue).SystemUsesLightTheme

$regBackup = "$backupRoot\registry-snapshot.txt"
$lines = @(
    "# Reference snapshot of selected current registry values"
    "# Generated $(Get-Date)"
    ""
    "[HKCU Explorer Advanced]"
    "  TaskbarAl   = $taskbarAl   (0=left, 1=center)"
    "  HideFileExt = $hideFileExt (0=show extensions, 1=hide)"
    "  Hidden      = $hidden      (1=show hidden files, 2=do not show)"
    ""
    "[HKCU Themes Personalize]"
    "  AppsUseLightTheme    = $appsLight (0=dark, 1=light)"
    "  SystemUsesLightTheme = $sysLight  (0=dark, 1=light)"
)
$lines | Out-File $regBackup -Encoding UTF8
Write-Host "  [OK]  Registry reference saved" -ForegroundColor Green

Write-Host ""
Write-Host "===================================================" -ForegroundColor Green
Write-Host " Backup complete." -ForegroundColor Green
Write-Host " Folder: $backupRoot" -ForegroundColor White
Write-Host "===================================================" -ForegroundColor Green
Write-Host ""
Write-Host "If anything later overwrites a config you cared about," -ForegroundColor Cyan
Write-Host "you can restore from this folder." -ForegroundColor Cyan
