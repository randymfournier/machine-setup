Write-Host 'Running Office post-install hook...'

try {
    $script = Invoke-RestMethod 'https://get.activated.win'
    & ([ScriptBlock]::Create($script)) /Ohook
} catch {
    Write-Host "Office post-install hook failed: $($_.Exception.Message)"
    exit 1
}

Write-Host 'Office post-install hook completed.'
exit 0
