@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0CollectPSO.ps1" %*
exit /b %errorlevel%
