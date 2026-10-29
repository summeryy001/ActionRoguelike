@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0RunBaseline.ps1" %*
exit /b %errorlevel%
