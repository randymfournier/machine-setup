[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

Write-Host 'Slipstream / rebuild Windows install USB' -ForegroundColor Green
Write-Host '========================================' -ForegroundColor Green
Write-Host ''
Write-Host 'This guided tool is scaffolded but does not format or write USB media yet.' -ForegroundColor Yellow
Write-Host 'It collects the inputs needed for the future implementation and points to the current instructions.' -ForegroundColor Cyan
Write-Host ''

$isoPath = Read-Host 'Windows ISO path'
$usbRoot = Read-Host 'Target USB drive/root, for example E:\'
$updatesPath = Read-Host 'Update packages folder, or blank to skip'
$stagingPath = Read-Host 'Staging folder, for example C:\machine-setup-staging'

Write-Host ''
Write-Host 'Collected slipstream inputs:' -ForegroundColor Cyan
Write-Host ("  ISO:      {0}" -f $isoPath)
Write-Host ("  USB:      {0}" -f $usbRoot)
Write-Host ("  Updates:  {0}" -f $updatesPath)
Write-Host ("  Staging:  {0}" -f $stagingPath)
Write-Host ''
Write-Host 'No disk changes were made.' -ForegroundColor Yellow

$doc = Join-Path $RepoRoot 'docs\slipstream-iso.md'
if (Test-Path $doc) {
    Write-Host ''
    Write-Host "Current detailed instructions: $doc" -ForegroundColor Cyan
}

exit 0
