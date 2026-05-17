# Office Deployment Tool assets

Place the Microsoft Office Deployment Tool `setup.exe` in this folder:

```powershell
C:\machine-setup\assets\office\setup.exe
```

The setup task uses the checked-in `configuration.xml` in this same folder and runs:

```powershell
.\setup.exe /download configuration.xml
.\setup.exe /configure configuration.xml
```

The task waits for each command to finish before starting the next one.

Activation should be completed with a legitimate Microsoft account, product key, or organization licensing flow after install.

## Optional post-install hook

The setup workflow includes an optional `office.postInstall` task. To use it,
create this local file:

```powershell
C:\machine-setup\assets\office\postInstall.local.ps1
```

That file is intentionally local so you can keep machine-specific commands out
of the task wrapper. For an allowed remote script, the shape is:

```powershell
Write-Host 'Running Office post-install hook...'

try {
    $script = Invoke-RestMethod 'https://example.com/script.ps1'
    & ([ScriptBlock]::Create($script)) -YourArgument
} catch {
    Write-Host "Office post-install hook failed: $($_.Exception.Message)"
    exit 1
}

Write-Host 'Office post-install hook completed.'
exit 0
```
