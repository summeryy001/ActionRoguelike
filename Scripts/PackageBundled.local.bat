@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0PackageBundled.ps1" %*
exit /b %errorlevel%
