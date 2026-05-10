# shell/Microsoft.PowerShell_profile.ps1
# Lives at: $PROFILE  (typically C:\Users\<you>\Documents\PowerShell\Microsoft.PowerShell_profile.ps1)

# --- Starship prompt -------------------------------------------------------
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}

# --- fnm (Node version manager) -------------------------------------------
if (Get-Command fnm -ErrorAction SilentlyContinue) {
    fnm env --use-on-cd | Out-String | Invoke-Expression
}

# --- uv tool shims on PATH ------------------------------------------------
$uvBin = "$env:USERPROFILE\.local\bin"
if ((Test-Path $uvBin) -and ($env:Path -notlike "*$uvBin*")) {
    $env:Path = "$uvBin;$env:Path"
}

# --- Cargo (Rust) bin -----------------------------------------------------
$cargoBin = "$env:USERPROFILE\.cargo\bin"
if ((Test-Path $cargoBin) -and ($env:Path -notlike "*$cargoBin*")) {
    $env:Path = "$cargoBin;$env:Path"
}

# --- PSReadLine: better history & completion ------------------------------
if (Get-Module -ListAvailable -Name PSReadLine) {
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
    Set-PSReadLineOption -PredictionViewStyle ListView
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
}

# --- Aliases --------------------------------------------------------------
Set-Alias -Name g     -Value git
Set-Alias -Name py    -Value python
Set-Alias -Name k     -Value kubectl -ErrorAction SilentlyContinue
Set-Alias -Name d     -Value docker
Set-Alias -Name dc    -Value 'docker compose' -ErrorAction SilentlyContinue
Set-Alias -Name ll    -Value Get-ChildItem
Set-Alias -Name which -Value Get-Command

# --- Functions ------------------------------------------------------------
function .. { Set-Location .. }
function ... { Set-Location ..\.. }
function .... { Set-Location ..\..\.. }

# Git shortcuts
function gs { git status $args }
function ga { git add $args }
function gc { git commit $args }
function gp { git push $args }
function gpl { git pull $args }
function gco { git checkout $args }
function gb { git branch $args }
function gd { git diff $args }
function gl { git log --oneline --graph --decorate --all $args }

# Quick edit of profile
function Edit-Profile { code $PROFILE }

# Reload profile
function Reload-Profile { . $PROFILE }

# Make a new project dir + cd into it
function mkcd($name) {
    New-Item -ItemType Directory -Path $name -Force | Out-Null
    Set-Location $name
}
