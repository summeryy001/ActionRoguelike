@echo off
setlocal
if not defined UE_ROOT set "UE_ROOT=F:\Git_Repository\4399-unreal\unrealengine-4399"
call "%UE_ROOT%\Engine\Build\BatchFiles\Build.bat" -Target="ActionRoguelikeEditor Win64 Development -Project=%~dp0..\ActionRoguelike.uproject" -Target="ActionRoguelike Win64 Development -Project=%~dp0..\ActionRoguelike.uproject" -MaxParallelActions=4 -WaitMutex -NoHotReloadFromIDE
exit /b %errorlevel%
