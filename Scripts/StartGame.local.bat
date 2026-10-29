@echo off
setlocal
set "GAME=%~dp0..\Saved\PSOValidation\Package\Windows\ActionRoguelike.exe"
if not exist "%GAME%" (
 echo AR2 has not been packaged yet.
 exit /b 1
)
start "AR2 Baseline" "%GAME%" -dx12 -sm6 -windowed -ResX=1280 -ResY=720 -NoSteam -UserDir="%~dp0..\Saved\IsolatedGameUser" %*
