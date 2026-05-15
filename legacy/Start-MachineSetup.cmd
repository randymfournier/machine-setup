@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0quickstart-local.ps1"
exit /b %ERRORLEVEL%
