@echo off
setlocal
if not defined UE_ROOT set "UE_ROOT=F:\Git_Repository\4399-unreal\unrealengine-4399"
call "%UE_ROOT%\Engine\Build\BatchFiles\RunUAT.bat" -nocompile -nocompileuat BuildCookRun -project="%~dp0..\ActionRoguelike.uproject" -noP4 -platform=Win64 -clientconfig=Development -skipbuild -skipbuildeditor -cook -stage -pak -iostore -archive -archivedirectory="%~dp0..\Saved\PSOValidation\Package" -unattended -utf8output
exit /b %errorlevel%
