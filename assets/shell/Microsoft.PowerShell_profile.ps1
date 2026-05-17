# shell/Microsoft.PowerShell_profile.ps1
# Lives at: $PROFILE  (typically C:\Users\<you>\Documents\PowerShell\Microsoft.PowerShell_profile.ps1)

function Add-ProfilePath {
    param([Parameter(Mandatory=$true)][string]$Path)

    if ((Test-Path $Path) -and ($env:Path -notlike "*$Path*")) {
        $env:Path = "$Path;$env:Path"
    }
}

# Elevated PowerShell can miss user-scoped WinGet/tool paths.
Add-ProfilePath (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
Add-ProfilePath (Join-Path $env:LOCALAPPDATA 'Programs\oh-my-posh\bin')
Add-ProfilePath (Join-Path $env:ProgramFiles 'oh-my-posh\bin')

# --- Oh My Posh prompt -----------------------------------------------------
$ompConfig = Join-Path $env:USERPROFILE '.config\oh-my-posh\blueish.omp.json'
if ((Get-Command oh-my-posh -ErrorAction SilentlyContinue) -and (Test-Path $ompConfig)) {
    oh-my-posh init pwsh --config $ompConfig | Invoke-Expression
}

# --- fnm (Node version manager) -------------------------------------------
if (Get-Command fnm -ErrorAction SilentlyContinue) {
    fnm env --use-on-cd | Out-String | Invoke-Expression
}

# --- uv tool shims on PATH ------------------------------------------------
$uvBin = "$env:USERPROFILE\.local\bin"
Add-ProfilePath $uvBin

# --- Cargo (Rust) bin -----------------------------------------------------
$cargoBin = "$env:USERPROFILE\.cargo\bin"
Add-ProfilePath $cargoBin

# --- PSReadLine: better history & completion ------------------------------
if (Get-Module -ListAvailable -Name PSReadLine) {
    $psReadLineOptions = (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue).Parameters
    if ($psReadLineOptions.ContainsKey('PredictionSource')) {
        Set-PSReadLineOption -PredictionSource HistoryAndPlugin
    }
    if ($psReadLineOptions.ContainsKey('PredictionViewStyle')) {
        Set-PSReadLineOption -PredictionViewStyle ListView
    }
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
}

# --- Aliases --------------------------------------------------------------
Set-Alias -Name g     -Value git
Set-Alias -Name py    -Value python
Set-Alias -Name k     -Value kubectl -ErrorAction SilentlyContinue
Set-Alias -Name d     -Value docker
Set-Alias -Name ll    -Value Get-ChildItem
Set-Alias -Name which -Value Get-Command

# --- Functions ------------------------------------------------------------
function .. { Set-Location .. }
function ... { Set-Location ..\.. }
function .... { Set-Location ..\..\.. }

function dc { docker compose $args }

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
