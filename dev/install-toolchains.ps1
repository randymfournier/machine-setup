# dev/install-toolchains.ps1
# Installs language toolchains and tools that are better installed outside winget:
#   - fnm (Node version manager)
#   - uv (Python toolchain)
#   - rustup (Rust toolchain)
#   - Tauri CLI (after MSVC/link.exe is verified by bootstrap)
#   - FiraCode Nerd Font (for Starship glyphs in your terminal)
#   - ScreenRec note (manual download, not on winget)

$ErrorActionPreference = 'Stop'
$tmp = "$env:TEMP\machine-setup-installs"
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

$script:ToolchainFailures = New-Object System.Collections.Generic.List[string]

function Has($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable('Path','Machine')
    $userPath = [System.Environment]::GetEnvironmentVariable('Path','User')
    $env:Path = @($machinePath, $userPath, "$env:USERPROFILE\.cargo\bin") -join ';'
}

function Find-MsvcLinker {
    $vsInstallerDir = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer'
    $vswhere = Join-Path $vsInstallerDir 'vswhere.exe'
    $componentId = 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
    $candidates = @()

    if (Test-Path $vswhere) {
        $installPaths = & $vswhere -products * -requires $componentId -property installationPath 2>$null
        foreach ($installPath in $installPaths) {
            if ($installPath -and (Test-Path $installPath)) {
                $pattern = Join-Path $installPath 'VC\Tools\MSVC\*\bin\Hostx64\x64\link.exe'
                $candidates += Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
            }
        }
    }

    $fallbackPatterns = @(
        (Join-Path ${env:ProgramFiles} 'Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\bin\Hostx64\x64\link.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\bin\Hostx64\x64\link.exe')
    )

    foreach ($pattern in $fallbackPatterns) {
        $candidates += Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
    }

    $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}

function Invoke-ToolStep {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][scriptblock]$Action
    )

    Write-Host ""
    Write-Host "--- $Name ---" -ForegroundColor Cyan

    try {
        $global:LASTEXITCODE = 0
        & $Action
        Refresh-Path
        Write-Host "[OK] $Name" -ForegroundColor Green
    } catch {
        $message = $_.Exception.Message
        $script:ToolchainFailures.Add("$Name :: $message") | Out-Null
        Write-Host "[FAILED] $Name" -ForegroundColor Red
        Write-Host "  $message" -ForegroundColor Yellow
        Write-Host "  Continuing with remaining toolchain steps." -ForegroundColor DarkYellow
    }
}

Invoke-ToolStep 'fnm / Node LTS' {
    if (-not (Has fnm)) {
        Write-Host 'Installing fnm...' -ForegroundColor Cyan
        & winget install --id Schniz.fnm -e --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) { throw "winget install Schniz.fnm failed with exit code $LASTEXITCODE." }
        Refresh-Path
    } else {
        Write-Host 'fnm already installed.' -ForegroundColor DarkGray
    }

    if (Has fnm) {
        & fnm install --lts
        if ($LASTEXITCODE -ne 0) { throw "fnm install --lts failed with exit code $LASTEXITCODE." }
        & fnm default lts-latest
        if ($LASTEXITCODE -ne 0) { throw "fnm default lts-latest failed with exit code $LASTEXITCODE." }
    } else {
        throw 'fnm is still not available after install attempt.'
    }
}

Invoke-ToolStep 'uv / Python 3.12' {
    if (-not (Has uv)) {
        Write-Host 'Installing uv...' -ForegroundColor Cyan
        irm https://astral.sh/uv/install.ps1 | iex
        Refresh-Path
    } else {
        Write-Host 'uv already installed.' -ForegroundColor DarkGray
    }

    if (Has uv) {
        & uv python install 3.12
        if ($LASTEXITCODE -ne 0) { throw "uv python install 3.12 failed with exit code $LASTEXITCODE." }
    } else {
        throw 'uv is still not available after install attempt.'
    }
}

Invoke-ToolStep 'rustup / Rust stable' {
    if (-not (Has rustup)) {
        Write-Host 'Installing rustup...' -ForegroundColor Cyan
        $rustupExe = "$tmp\rustup-init.exe"
        Invoke-WebRequest -Uri 'https://win.rustup.rs/x86_64' -OutFile $rustupExe -UseBasicParsing
        & $rustupExe -y --default-toolchain stable
        if ($LASTEXITCODE -ne 0) { throw "rustup-init failed with exit code $LASTEXITCODE." }
        Refresh-Path
    } else {
        Write-Host 'rustup already installed.' -ForegroundColor DarkGray
    }

    if (Has rustup) {
        & rustup default stable
        if ($LASTEXITCODE -ne 0) { throw "rustup default stable failed with exit code $LASTEXITCODE." }
    }
}

Invoke-ToolStep 'Tauri CLI' {
    if (-not (Has cargo)) {
        throw 'cargo is not available. Rust/rustup needs to succeed first.'
    }

    $linker = Find-MsvcLinker
    if (-not $linker) {
        throw 'MSVC link.exe was not found. Run or repair the visualstudio bootstrap step before installing tauri-cli.'
    }

    Write-Host "Using MSVC linker: $linker" -ForegroundColor DarkGray
    Write-Host 'Installing tauri-cli via cargo...' -ForegroundColor Cyan
    & cargo install tauri-cli --locked
    if ($LASTEXITCODE -ne 0) { throw "cargo install tauri-cli failed with exit code $LASTEXITCODE." }
}

Invoke-ToolStep 'FiraCode Nerd Font' {
    $fontInstalled = Get-ChildItem "$env:WINDIR\Fonts" -Filter 'FiraCode*' -ErrorAction SilentlyContinue
    if ($fontInstalled) {
        Write-Host 'FiraCode font already installed.' -ForegroundColor DarkGray
    } else {
        Write-Host 'Installing FiraCode Nerd Font...' -ForegroundColor Cyan
        $fontZip = "$tmp\FiraCode.zip"
        $fontDir = "$tmp\FiraCode"
        Invoke-WebRequest -Uri 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip' -OutFile $fontZip -UseBasicParsing
        Expand-Archive -Path $fontZip -DestinationPath $fontDir -Force

        $shell = New-Object -ComObject Shell.Application
        $fonts = $shell.Namespace(0x14)  # Fonts folder
        Get-ChildItem -Path $fontDir -Include *.ttf, *.otf -Recurse | ForEach-Object {
            $dest = "$env:WINDIR\Fonts\$($_.Name)"
            if (-not (Test-Path $dest)) {
                $fonts.CopyHere($_.FullName, 0x10)  # 0x10 = no progress UI
            }
        }
    }
}

# --- ScreenRec (no winget package; manual download) ------------------------
# Skipped here -- see manual-steps.md. Greenshot covers screenshots already
# (installed via winget); ScreenRec is for video. If you want, OBS Studio is
# a winget option that's much more powerful:
#   winget install OBSProject.OBSStudio

Write-Host ""
Write-Host 'Dev toolchains pass complete.' -ForegroundColor Green
Write-Host 'Languages targeted: Node (via fnm), Python (via uv), Rust (via rustup), Go (via winget).' -ForegroundColor Cyan

if ($script:ToolchainFailures.Count -gt 0) {
    Write-Host ""
    Write-Host 'Toolchain failures:' -ForegroundColor Yellow
    $script:ToolchainFailures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    throw "$($script:ToolchainFailures.Count) toolchain sub-step(s) failed. See log for details."
}
