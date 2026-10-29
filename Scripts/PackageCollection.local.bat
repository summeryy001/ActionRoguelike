@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0PackageCollection.ps1" %*
exit /b %errorlevel%
