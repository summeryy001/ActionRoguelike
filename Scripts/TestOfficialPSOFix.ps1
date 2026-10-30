[CmdletBinding()]
param([switch]$Execute)
$ErrorActionPreference='Stop'
$Root=(Resolve-Path "$PSScriptRoot/..").Path
$Engine='F:/Git_Repository/4399-unreal/unrealengine-4399'
$Exe="$Root/Saved/PSOValidation/Package/Windows/ActionRoguelike/Binaries/Win64/ActionRoguelike.exe"
$Evidence="$Root/Saved/PSOOfficialFix/"+(Get-Date -Format 'yyyyMMdd_HHmmss')
New-Item $Evidence -ItemType Directory -Force | Out-Null
$Settings=[ordered]@{'r.PSOPrecaching'=1;'r.PSOPrecache.GlobalShaders'=1;'r.PSOPrecache.Validation'=2;'r.PSOPrecache.ProxyCreationStrategy'=1;'r.ShaderPipelineCache.Enabled'=0}
$Overrides=($Settings.Keys | ForEach-Object {'[SystemSettings]:{0}={1}' -f $_,$Settings[$_]}) -join ','
$Hash=(Get-FileHash $Exe).Hash
$Results=@()
foreach($Name in @('AutoTrace1','AutoTrace2','AutoReadyTrace','AutoNoTrace')) {
    $Run="$Evidence/$Name"
    New-Item $Run -ItemType Directory | Out-Null
    $TraceEnabled=$Name -ne 'AutoNoTrace'
    $ArgsList=@('/Game/ActionRoguelike/Maps/TestLevel?listen','-dx12','-sm6','-windowed','-ResX=1280','-ResY=720','-NoSteam','-NoVSync','-unattended','-PSOValidation',
        ('-PSOValidationOutput="'+$Run+'"'),('-UserDir="'+$Run+'/User"'),('-abslog="'+$Run+'/game.log"'),
        ('-ini:Engine:'+$Overrides),('-ExecCmds="t.IdleWhenNotForeground 0,t.MaxFPS 0,r.VSync 0,pso.StartupCheck 0,'+($Settings.Keys -join ',')+'"'))
    if($TraceEnabled){$ArgsList+=@('-trace=cpu,frame,bookmark,log,gpu','-statnamedevents',('-tracefile="'+$Run+'/capture.utrace"'))}else{$ArgsList+='-trace=none'}
    if($Name -eq 'AutoReadyTrace'){$ArgsList+='-PSOValidationWaitForReady'}
    @{Executable=$Exe;ExeSHA256=$Hash;EngineCommit=(& git -C $Engine rev-parse HEAD);Arguments=$ArgsList;Settings=$Settings;Trace=$TraceEnabled;DriverCacheClearRequested=$false;Purpose='退出崩溃回归；沿用本机缓存，不作为冷启动性能对照'} | ConvertTo-Json -Depth 6 | Set-Content "$Run/manifest.json" -Encoding utf8
    if(!$Execute){continue}
    if(@(Get-Process -ErrorAction SilentlyContinue | Where-Object {$_.ProcessName -match '^(UnrealEditor|ActionRoguelike|Loki)(-|$)'}).Count){throw '请先关闭 UE 编辑器与游戏'}
    if((Get-FileHash $Exe).Hash -ne $Hash){throw '测试期间 EXE 已改变'}
    $Process=Start-Process $Exe -ArgumentList $ArgsList -WorkingDirectory (Split-Path $Exe) -WindowStyle Hidden -PassThru
    if(!$Process.WaitForExit(240000)){Stop-Process -Id $Process.Id;throw "测试超时：$Run"}
    $Process.Refresh()
    $Log=Get-Content "$Run/game.log" -Raw
    $Actual=@{}
    foreach($Key in $Settings.Keys){
        $Found=[regex]::Matches($Log,[regex]::Escape($Key)+'\s*=\s*"?([0-9]+)"?')
        $Actual[$Key]=if($Found.Count){[int]$Found[$Found.Count-1].Groups[1].Value}else{$null}
    }
    $SettingsOK=@($Settings.Keys | Where-Object {$null -eq $Actual[$_] -or $Actual[$_] -ne $Settings[$_]}).Count -eq 0
    $Actions=[regex]::Matches($Log,'PSOValidation action=\S+ started=1').Count
    $Trace=Get-Item "$Run/capture.utrace" -ErrorAction SilentlyContinue
    $TraceOK=if($TraceEnabled){$null -ne $Trace -and $Trace.Length -gt 0}else{$null -eq $Trace}
    $GateOK=$Name -ne 'AutoReadyTrace' -or $Log -match 'gateComplete enabled=1 .*pendingAuto=0 .*asyncLoading=0'
    $Valid=$Process.ExitCode -eq 0 -and $Actions -eq 6 -and $Log.Contains('label=Complete') -and $Log.Contains('respawnAlive=1') -and $Log -notmatch 'Ensure condition failed|Fatal error:|Assertion failed:' -and $SettingsOK -and $TraceOK -and $GateOK -and (Test-Path "$Run/frames.csv")
    $Result=[ordered]@{Name=$Name;Valid=[bool]$Valid;ExitCode=$Process.ExitCode;Actions=$Actions;ActualSettings=$Actual;TraceRequested=$TraceEnabled;TraceCheck=$TraceOK;ReadyGateCheck=$GateOK;Evidence=$Run}
    $Result | ConvertTo-Json -Depth 6 | Set-Content "$Run/acceptance.json" -Encoding utf8
    $Results+=$Result
    $Results | ConvertTo-Json -Depth 6 | Set-Content "$Evidence/results.json" -Encoding utf8
    Write-Output "$Name : Valid=$Valid Exit=$($Process.ExitCode)"
    if(!$Valid){throw "回归失败：$Run"}
}
Write-Output "Evidence: $Evidence"
