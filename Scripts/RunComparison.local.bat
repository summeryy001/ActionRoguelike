@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0RunComparison.ps1" %*
exit /b %errorlevel%
