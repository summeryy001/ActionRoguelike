[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Request)
$ErrorActionPreference='Stop'
$Request=(Resolve-Path -LiteralPath $Request).Path
$R=[IO.File]::ReadAllText($Request)|ConvertFrom-Json
$Job=Split-Path $Request
$Root=[IO.Path]::GetDirectoryName($R.ProjectFile)
$Name=[IO.Path]::GetFileNameWithoutExtension($R.ProjectFile)
$Format='PCD3D_SM6'
$LogPath="$Job/task.log"
$TaskMutex=$null;$OwnMutex=$false
function HashFile([string]$Path){$S=[IO.File]::OpenRead($Path);$H=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($H.ComputeHash($S))).Replace('-','')}finally{$S.Dispose();$H.Dispose()}}
function JsonFile($Value,[string]$Path){$Value|ConvertTo-Json -Depth 15|Set-Content -LiteralPath $Path -Encoding UTF8}
function Note([string]$Text){Add-Content -LiteralPath "$Job/task.log" -Value ((Get-Date -Format 'HH:mm:ss')+' '+$Text) -Encoding UTF8}
function Status([string]$Phase,[string]$Message,[string]$ActiveLog=$LogPath,[string]$Session=''){
    JsonFile @{phase=$Phase;message=$Message;log=$ActiveLog;session=$Session;action=$R.Action;job=$Job} "$Job/status.json"
    Note $Message
}
function Inventory($Files){@($Files|Sort-Object FullName|ForEach-Object {[ordered]@{name=$_.Name;path=$_.FullName;bytes=$_.Length;sha256=(HashFile $_.FullName)}})}
function PutState([string]$Key,$Value){$State|Add-Member -NotePropertyName $Key -NotePropertyValue $Value -Force;JsonFile $State $StateFile}
function GetIni([string]$File,[string]$Section,[string]$Key){
    if(!(Test-Path $File)){return $null};$InSection=$false;$Value=$null
    foreach($Line in [IO.File]::ReadAllLines($File)){
        if($Line -match '^\s*\[(.+)\]\s*$'){$InSection=$Matches[1] -eq $Section}
        elseif($InSection -and $Line -match ('^\s*'+[regex]::Escape($Key)+'\s*=\s*(.*)$')){$Value=$Matches[1]}
    };return $Value
}
function SetIni([string]$File,[string]$Section,[string]$Key,[string]$Value){
    $Lines=[Collections.Generic.List[string]]::new()
    if(Test-Path $File){foreach($Line in [IO.File]::ReadAllLines($File)){$Lines.Add($Line)}}
    $Start=-1;$End=$Lines.Count
    for($I=0;$I -lt $Lines.Count;$I++){if($Lines[$I] -match '^\s*\[(.+)\]\s*$'){if($Start -ge 0){$End=$I;break};if($Matches[1] -eq $Section){$Start=$I}}}
    if($Start -lt 0){$Lines.Add('');$Lines.Add("[$Section]");$Lines.Add("$Key=$Value")}else{
        $Found=$false
        for($I=$Start+1;$I -lt $End;$I++){if($Lines[$I] -match ('^\s*'+[regex]::Escape($Key)+'\s*=')){$Lines[$I]="$Key=$Value";$Found=$true}}
        if(!$Found){$Lines.Insert($End,"$Key=$Value")}
    }
    [IO.File]::WriteAllLines($File,$Lines,[Text.UTF8Encoding]::new($false))
}
function RequireConfig {
    if((GetIni "$Root/Config/DefaultEngine.ini" 'DevOptions.Shaders' 'NeedsShaderStableKeys') -ne 'true'){throw '请先点击“应用构建配置”，启用 Stable Shader Keys。'}
    if((GetIni "$Root/Config/DefaultGame.ini" '/Script/UnrealEd.ProjectPackagingSettings' 'bShareMaterialShaderCode') -ne 'True'){throw '请先应用共享 Shader 代码库配置。'}
}
function BuildPackage([bool]$Bundled){
    RequireConfig
    if($Bundled -and !$State.installed){throw '请先转换并安装 Stable PSO 清单。'}
    $Engine=$R.EngineRoot
    $BuildLog="$Job/build.log";Status 'Build' '正在构建 Windows Game（不会链接编辑器 DLL）' $BuildLog
    & "$Engine/Engine/Build/BatchFiles/Build.bat" $R.GameTarget Win64 Development ('-Project="'+$R.ProjectFile+'"') -WaitMutex -NoHotReloadFromIDE -MaxParallelActions=4 *> $BuildLog
    if($LASTEXITCODE -ne 0){throw "Game 构建失败，见 $BuildLog"}
    $Archive="$Job/Package";$CookLog="$Job/cook.log"
    $Maps=@($R.CookMaps|Where-Object {$_})
    if(!$Maps.Count){throw '请至少选择一个 Cook 地图。'}
    $ArgsList=@('-nocompile','-nocompileuat','BuildCookRun',('-project="'+$R.ProjectFile+'"'),'-noP4','-platform=Win64','-clientconfig=Development','-skipbuild','-skipbuildeditor','-cook','-stage','-pak','-iostore','-archive',('-archivedirectory="'+$Archive+'"'),('-map='+($Maps -join '+')),'-unattended','-utf8output')
    JsonFile $ArgsList "$Job/cook-command.json"
    Status 'Cook' '正在 Cook、打包并保存本次构建快照' $CookLog
    & "$Engine/Engine/Build/BatchFiles/RunUAT.bat" @ArgsList *> $CookLog
    if($LASTEXITCODE -ne 0){throw "Cook/打包失败，见 $CookLog"}
    $Meta="$Root/Saved/Cooked/Windows/$Name/Metadata/PipelineCaches"
    $Keys=@(Get-ChildItem $Meta -File -Filter "*$Format.shk")
    if($Keys.Count -lt 2){throw 'Cook 未输出匹配的项目/Global SHK，请检查配置。'}
    New-Item "$Job/StableKeys" -ItemType Directory|Out-Null
    $Keys|Copy-Item -Destination "$Job/StableKeys"
    $Exe="$Archive/Windows/$Name/Binaries/Win64/$($R.GameTarget).exe"
    if(!(Test-Path $Exe)){throw "未找到 Game EXE：$Exe。请检查构建目标。"}
    $Result=[ordered]@{id=(Split-Path $Job -Leaf);package=$Archive;exe=$Exe;exeHash=(HashFile $Exe);keys=(Inventory @(Get-ChildItem "$Job/StableKeys" -File));created=(Get-Date).ToString('o');evidence=$Job}
    if($Bundled){
        $InputDir="$Root/Build/Windows/PipelineCaches"
        $Inputs=@(Get-ChildItem $InputDir -Recurse -File -Filter "*${Name}_${Format}.spc")
        $CookText=Get-Content $CookLog -Raw
        foreach($Spc in $Inputs){if($CookText -notmatch ('Loaded \d+ stable PSOs from [^\r\n]*'+[regex]::Escape($Spc.Name))){throw "Cook 未确认读取：$($Spc.Name)"}}
        $Cache="$Root/Saved/Cooked/Windows/$Name/Content/PipelineCaches/Windows/${Name}_${Format}.stable.upipelinecache"
        New-Item "$Job/RuntimeCaches" -ItemType Directory|Out-Null
        Copy-Item -LiteralPath $Cache -Destination "$Job/RuntimeCaches"
        $Count=[regex]::Match($CookText,'Wrote (\d+) binary PSOs \(graphics: (\d+) compute: (\d+) RT: (\d+)\)[^\r\n]*'+[regex]::Escape("${Name}_${Format}.stable.upipelinecache"))
        if(!$Count.Success -or [int]$Count.Groups[1].Value -le 0){throw '未找到有效的 SM6 缓存写入统计。'}
        $Result.count=[int]$Count.Groups[1].Value;$Result.graphics=[int]$Count.Groups[2].Value;$Result.compute=[int]$Count.Groups[3].Value
        $Result.inputs=Inventory $Inputs;$Result.cacheHash=HashFile $Cache
        $PakLogs=''
        foreach($Pak in (Get-ChildItem "$Archive/Windows/$Name/Content/Paks" -File -Filter '*.pak')){
            $Listing="$Job/$($Pak.Name).list.log"
            & "$Engine/Engine/Binaries/Win64/UnrealPak.exe" $Pak.FullName -List *> $Listing
            if($LASTEXITCODE -ne 0){throw 'PAK 清单读取失败。'}
            $PakLogs+=Get-Content $Listing -Raw
        }
        if(!$PakLogs.Contains("${Name}_${Format}.stable.upipelinecache")){throw '包内未找到目标运行时缓存。'}
        PutState 'bundled' $Result
    }else{PutState 'collector' $Result}
    JsonFile $Result "$Job/build-result.json"
    Note ('构建成功：'+$Exe)
}
function RunGame([bool]$Capture){
    $Build=if($Capture){$State.collector}else{$State.bundled}
    if(!$Build){throw '请先生成对应的 Windows 包。'}
    if((HashFile $Build.exe) -ne $Build.exeHash){throw 'EXE 与构建记录不匹配，请重新构建。'}
    $Settings=[ordered]@{'r.PSOPrecaching'=0;'r.PSOPrecache.GlobalShaders'=0;'r.PSOPrecache.Validation'=0;'r.PSOPrecache.ProxyCreationStrategy'=0;'r.ShaderPipelineCache.Enabled'=0;'r.ShaderPipelineCache.SaveUserCache'=0}
    if($Capture){
        $Auto=$R.CaptureStrategy -ne 2
        $Settings['r.ShaderPipelineCache.Enabled']=1;$Settings['r.ShaderPipelineCache.StartupMode']=0
        $Settings['r.ShaderPipelineCache.ExcludePrecachePSO']=if($R.CaptureStrategy -eq 1){1}else{0}
        $Settings['r.ShaderPipelineCache.LogPSO']=1;$Settings['r.ShaderPipelineCache.SaveBoundPSOLog']=1
    }else{
        $Auto=$R.RuntimeMode -in @(1,3)
        $Settings['r.ShaderPipelineCache.Enabled']=if($R.RuntimeMode -in @(2,3)){1}else{0}
        $Settings['r.ShaderPipelineCache.StartupMode']=if($R.Background){2}else{1}
        $Settings['r.ShaderPipelineCache.BackgroundBatchTime']=$R.BackgroundBudgetMs
    }
    if($Auto){$Settings['r.PSOPrecaching']=1;$Settings['r.PSOPrecache.GlobalShaders']=1;$Settings['r.PSOPrecache.Validation']=2;$Settings['r.PSOPrecache.ProxyCreationStrategy']=1}
    $Overrides=($Settings.Keys|ForEach-Object {'[SystemSettings]:{0}={1}' -f $_,$Settings[$_]}) -join ','
    $Session="$Job/Session";New-Item $Session -ItemType Directory|Out-Null
    $ArgsList=@(($R.CaptureMap+'?listen'),'-dx12','-sm6','-windowed','-ResX=1280','-ResY=720','-NoSteam','-NoVSync','-trace=cpu,frame,bookmark,log,gpu','-statnamedevents',
        ('-UserDir="'+$Session+'/User"'),('-abslog="'+$Session+'/game.log"'),('-tracefile="'+$Session+'/capture.utrace"'),('-PSOWorkbenchSession="'+$Session+'"'),('-PSOValidationOutput="'+$Session+'"'),('-ini:Engine:'+$Overrides),('-ExecCmds="t.IdleWhenNotForeground 0,t.MaxFPS 0,r.VSync 0,'+($Settings.Keys -join ',')+'"'))
    if($Capture){$ArgsList+='-logPSO'}elseif($R.ClearDriverCache){$ArgsList+='-clearPSODriverCache'}
    if($R.AutomaticRoute -and $R.AutomaticArguments){$ArgsList+=@($R.AutomaticArguments -split '\s+'|Where-Object {$_})}
    JsonFile @{build=$Build.id;settings=$Settings;arguments=$ArgsList;capture=$Capture;clearDriverCacheRequested=(!$Capture -and $R.ClearDriverCache)} "$Session/manifest.json"
    Status 'GameRunning' $(if($R.AutomaticRoute){'游戏运行中：执行项目自动路线'}else{'手动跑包中：完成覆盖后点击“结束当前游戏”'}) "$Session/game.log" $Session
    $Process=Start-Process $Build.exe -ArgumentList $ArgsList -WorkingDirectory (Split-Path $Build.exe) -PassThru
    $Limit=if($R.AutomaticRoute){600}else{7200}
    if(!$Process.WaitForExit($Limit*1000)){Stop-Process -Id $Process.Id;throw '运行超时，已终止本次游戏；证据保留。'}
    $Process.Refresh();if($Process.ExitCode -ne 0){throw "游戏退出码异常：$($Process.ExitCode)"}
    $Text=Get-Content "$Session/game.log" -Raw
    if($Text -match 'Ensure condition failed|Fatal error:|Assertion failed:'){throw '运行包含 Ensure/Fatal/Assertion，请检查游戏日志。'}
    if($R.AutomaticRoute -and $R.CompletionMarker -and !$Text.Contains($R.CompletionMarker)){throw '未观察到自动路线完成标记。'}
    if($R.AutomaticRoute -and $R.ExpectedActions -gt 0 -and [regex]::Matches($Text,'PSOValidation action=\S+ started=1').Count -ne $R.ExpectedActions){throw '自动路线成功动作数不足，未通过验收。'}
    foreach($Key in $Settings.Keys){
        $Found=[regex]::Matches($Text,[regex]::Escape($Key)+'\s*=\s*"?([0-9.]+)"?')
        if(!$Found.Count -or [double]$Found[$Found.Count-1].Groups[1].Value -ne [double]$Settings[$Key]){throw "运行配置未生效：$Key"}
    }
    if(!(Test-Path "$Session/runtime-summary.json")){throw '缺少工作台 Runtime 记录，请重新构建包含插件的包。'}
    $Runtime=Get-Content "$Session/runtime-summary.json" -Raw|ConvertFrom-Json
    if((HashFile $Build.exe) -ne $Build.exeHash){throw '运行期间 EXE 已改变。'}
    $Result=[ordered]@{build=$Build.id;session=$Session;created=(Get-Date).ToString('o');runtime=$Runtime;valid=$true}
    if($Capture){
        $Records=@(Get-ChildItem "$Session/User" -Recurse -File -Filter '*.rec.upipelinecache')
        if(!$Records.Count -or @($Records|Where-Object {$_.Length -eq 0}).Count){throw '没有有效原始 PSO 记录，请实际覆盖场景后再结束。'}
        $Result.records=Inventory $Records
        PutState 'captures' (@($State.captures)+@($Result))
    }else{
        if($R.RuntimeMode -in @(2,3)){
            $Batches=@($Runtime.batches|Where-Object {$_.name -eq $Name -and $_.queued -gt 0 -and $_.complete -and $_.queued -eq $_.processed})
            if(!$Batches.Count){throw '未观察到目标 Bundled 批次开始并完整结束。'}
            if(!$Text.Contains("${Name}_${Format}.stable.upipelinecache")){throw '未观察到目标随包缓存打开。'}
        }
        PutState 'validation' $Result
    }
    JsonFile $Result "$Session/acceptance.json"
    Note '运行验收成功；批次完成不代表全游戏覆盖。'
}
try {
    $Hasher=[Security.Cryptography.SHA256]::Create()
    try{$MutexKey=([BitConverter]::ToString($Hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($Root.ToLowerInvariant())))).Replace('-','')}finally{$Hasher.Dispose()}
    $TaskMutex=[Threading.Mutex]::new($false,('Local\PSOWorkbench_'+$MutexKey))
    try{$OwnMutex=$TaskMutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$OwnMutex=$true}
    if(!$OwnMutex){throw '同一项目已有工作台任务运行，请等待完成。'}
    foreach($Part in @($R.ProfileName,$R.GroupName)){if($Part -notmatch '^[\p{L}\p{N}_-]{1,60}$'){throw '方案和缓存组名称仅允许文字、数字、下划线和短横线，最长60字符。'}}
    if($R.Platform -ne 0){throw 'Android 尚未实现设备部署、采集回收和打包闭环；当前只支持 Windows DX12 SM6。'}
    $StateRoot="$Root/Saved/PSOWorkbench/Profiles/$($R.ProfileName)"
    New-Item $StateRoot -ItemType Directory -Force|Out-Null
    $StateFile="$StateRoot/state.json"
    $State=if(Test-Path $StateFile){Get-Content $StateFile -Raw|ConvertFrom-Json}else{[pscustomobject]@{captures=@()}}
    Status 'Starting' ('开始任务：'+$R.Action)
    switch($R.Action){
        'Preflight' {
            if(!(Test-Path "$($R.EngineRoot)/Engine/Build/BatchFiles/RunUAT.bat")){throw '引擎根目录不正确。'}
            if(!$R.CaptureMap -or !@($R.CookMaps|Where-Object {$_ -eq $R.CaptureMap}).Count){throw '运行地图必须包含在 Cook 地图列表。'}
            Note "工程：$($R.ProjectFile)；平台 Windows DX12 SM6；模式 $($R.RuntimeMode)；采集策略 $($R.CaptureStrategy)"
            RequireConfig
            Note '基础配置检查通过。构建与运行步骤还会检查具体产物依赖。'
        }
        'ApplyConfig' {
            $Backups=@()
            foreach($File in @("$Root/Config/DefaultEngine.ini","$Root/Config/DefaultGame.ini")){
                if((Test-Path $File) -and (Get-Item $File).IsReadOnly){throw "配置文件只读，请先从版本控制检出：$File"}
                $Exists=Test-Path $File;$Backup="$Job/"+[IO.Path]::GetFileName($File)+'.before'
                if($Exists){Copy-Item -LiteralPath $File -Destination $Backup}
                $Backups+=@{path=$File;backup=$Backup;existed=$Exists}
            }
            SetIni "$Root/Config/DefaultEngine.ini" 'DevOptions.Shaders' 'NeedsShaderStableKeys' 'true'
            SetIni "$Root/Config/DefaultGame.ini" '/Script/UnrealEd.ProjectPackagingSettings' 'bShareMaterialShaderCode' 'True'
            SetIni "$Root/Config/DefaultGame.ini" '/Script/UnrealEd.ProjectPackagingSettings' 'bSharedMaterialNativeLibraries' 'True'
            foreach($Item in $Backups){$Item.appliedHash=HashFile $Item.path}
            PutState 'configBackup' $Backups
            Note '已备份并应用3项构建设置。没有修改项目默认运行模式；本次运行由启动参数覆盖。'
        }
        'RestoreConfig' {
            if(!$State.configBackup){throw '没有工作台配置备份。'}
            foreach($Item in $State.configBackup){if((HashFile $Item.path) -ne $Item.appliedHash){throw '配置在应用后已被其他操作修改，拒绝覆盖，请检查备份。'}}
            foreach($Item in $State.configBackup){if($Item.existed){Copy-Item -LiteralPath $Item.backup -Destination $Item.path}else{Remove-Item -LiteralPath $Item.path}}
            Note '已恢复应用构建配置前的文件。'
        }
        'BuildCollector' { BuildPackage $false }
        'Capture' { RunGame $true }
        'Convert' {
            if(!$State.collector){throw '没有采集包。'}
            $Captures=@($State.captures|Where-Object {$_.build -eq $State.collector.id -and $_.valid})
            if(!$Captures.Count){throw '没有与当前采集包匹配的有效记录。'}
            $Records=@($Captures|ForEach-Object {$_.records})
            foreach($Item in @($Records)+@($State.collector.keys)){if((HashFile $Item.path) -ne $Item.sha256){throw '采集记录或 SHK 已改变。'}}
            $Out="$Job/PSOWB_$($R.ProfileName)_$($R.GroupName)_${Name}_${Format}.spc"
            $ArgsList=@($R.ProjectFile,'-run=ShaderPipelineCacheTools','expand')+@($Records|ForEach-Object {$_.path})+@($State.collector.keys|ForEach-Object {$_.path})+@($Out,'-unattended','-nop4','-NoSteam','-NullRHI',('-abslog='+$Job+'/expand.log'))
            Status 'Convert' '正在将匹配的原始记录与 SHK 转为 Stable 清单' "$Job/expand.log"
            & "$($R.EngineRoot)/Engine/Binaries/Win64/UnrealEditor-Cmd.exe" @ArgsList *> "$Job/convert-console.log"
            if($LASTEXITCODE -ne 0){throw '转换失败。'}
            $Text=Get-Content "$Job/expand.log" -Raw;$Count=[regex]::Match($Text,'Generated (\d+) stable PSOs total')
            if(!$Count.Success -or [int]$Count.Groups[1].Value -le 0 -or !(Test-Path $Out)){throw '没有生成有效 Stable PSO 清单。'}
            PutState 'conversion' @{spc=$Out;sha256=(HashFile $Out);count=[int]$Count.Groups[1].Value;build=$State.collector.id;group=$R.GroupName}
        }
        'Install' {
            if(!$State.conversion -or (HashFile $State.conversion.spc) -ne $State.conversion.sha256){throw '请先生成有效 Stable 清单。'}
            $DestDir="$Root/Build/Windows/PipelineCaches";New-Item $DestDir -ItemType Directory -Force|Out-Null
            $Dest=Join-Path $DestDir ([IO.Path]::GetFileName($State.conversion.spc))
            if(Test-Path $Dest){Copy-Item -LiteralPath $Dest -Destination "$Job/previous.spc"}
            Copy-Item -LiteralPath $State.conversion.spc -Destination $Dest
            PutState 'installed' @{path=$Dest;sha256=(HashFile $Dest);group=$State.conversion.group}
            Note '已安装本方案输入，保留项目其他 SPC；Cook 将按引擎规则合并。'
        }
        'BuildBundled' { BuildPackage $true }
        'Validate' { RunGame $false }
        'Analyze' {
            $Run=if($State.validation){$State.validation}else{@($State.captures)|Select-Object -Last 1}
            if(!$Run -or !(Test-Path "$($Run.session)/capture.utrace")){throw '没有可分析的 Trace。'}
            if(!(Test-Path $R.InsightsExecutable)){throw '请在高级设置中选择 UnrealInsights.exe。'}
            $Out="$Job/events.csv"
            $Command="TimingInsights.ExportTimingEvents $Out -columns=ThreadId,ThreadName,TimerId,TimerName,StartTime,EndTime,Duration,Depth -timers=*PSO*,*PipelineState*,*Precompile* -startTime=0 -endTime=15"
            $ArgsList=@('-NoUI','-AutoQuit',('-OpenTraceFile="'+$Run.session+'/capture.utrace"'),('-ABSLOG="'+$Job+'/insights.log"'),('-ExecOnAnalysisCompleteCmd="'+$Command+'"'))
            Status 'Analyze' 'Insights 正在离线解析 Trace' "$Job/insights.log"
            $Process=Start-Process $R.InsightsExecutable -ArgumentList $ArgsList -PassThru -WindowStyle Hidden
            if(!$Process.WaitForExit(180000)){Stop-Process -Id $Process.Id;throw 'Insights 超时。'}
            $Process.Refresh();if($Process.ExitCode -ne 0 -or !(Test-Path $Out)){throw 'Insights 导出失败。'}
            $Rows=Import-Csv $Out
            $Count=@($Rows|Where-Object {$_.TimerName -match '^FShaderPipelineCache::Precompile|^PSOPrecache:|RHICreate(Graphics|Compute)PipelineState'}).Count
            PutState 'analysis' @{events=$Out;source=$Run.session;scopeCount=$Count;evidence=$Job}
            Note "已导出预编译/创建相关 CPU Scope：$Count。Scope 数量不是独立 PSO 数量。"
        }
        default {throw '未知工作台任务。'}
    }
    Status 'Succeeded' '任务成功；产物与日志已保存。'
    JsonFile @{success=$true;action=$R.Action;evidence=$Job;state=$StateFile} "$Job/result.json"
}catch{
    Note $_.Exception.Message
    Status 'Failed' $_.Exception.Message
    JsonFile @{success=$false;action=$R.Action;error=$_.Exception.Message;evidence=$Job} "$Job/result.json"
    exit 1
}finally{if($OwnMutex){$TaskMutex.ReleaseMutex()};if($TaskMutex){$TaskMutex.Dispose()}}
