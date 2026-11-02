@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ValidateBundled.ps1" %*
exit /b %errorlevel%
