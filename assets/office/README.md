# Office Deployment Tool assets

The setup task uses the Microsoft Office Deployment Tool `setup.exe` from this
folder:

```powershell
C:\machine-setup\assets\office\setup.exe
```

If `setup.exe` is missing, the task downloads the Office Deployment Tool from
Microsoft and extracts it here automatically. The checked-in `configuration.xml`
in this same folder controls what Office installs, then the task runs:

```powershell
.\setup.exe /download configuration.xml
.\setup.exe /configure configuration.xml
```

The task waits for each command to finish before starting the next one. If you
keep `setup.exe` or the downloaded `Office\` payload in this folder, Git will
track them as part of this install source.

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
