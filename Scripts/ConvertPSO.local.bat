@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ConvertPSO.ps1" %*
exit /b %errorlevel%
