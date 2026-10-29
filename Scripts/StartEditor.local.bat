@echo off
setlocal
if not defined UE_ROOT set "UE_ROOT=F:\Git_Repository\4399-unreal\unrealengine-4399"
start "AR2 UE 5.8" "%UE_ROOT%\Engine\Binaries\Win64\UnrealEditor.exe" "%~dp0..\ActionRoguelike.uproject" -NoLiveCoding -NoSteam -UserDir="%~dp0..\Saved\IsolatedUser"
