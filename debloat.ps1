# debloat.ps1
# Compatibility wrapper. The real script lives at windows\debloat.ps1.

$scriptPath = Join-Path $PSScriptRoot 'windows\debloat.ps1'
if (-not (Test-Path $scriptPath)) {
    throw "Could not find $scriptPath"
}

& $scriptPath @args
