# Shared dependency checks, also exercised by the isolated regression fixtures.
function QuoteNativeArg([string]$Value) {
    return '"'+([regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1'))+'"'
}
function ValidateExtra([string]$Argument) {
    if($Argument -notmatch '^-[A-Za-z][A-Za-z0-9_.-]*(=[^"\r\n]*)?$'){throw '额外参数必须为单独的 -Flag 或 -Name=Value，不能包含引号/换行。'}
    $Key=($Argument -split '=',2)[0]
    if($Key -match '^-(ini|ExecCmds|DPCVars|ConsoleVariables|UserDir|abslog|log|trace.*|PSOWorkbenchSession|dx\d+|sm\d+|clearPSODriverCache|logPSO|r\.(PSO.*|ShaderPipelineCache.*))$'){throw '额外参数不能覆盖工作台管理项：'+$Key}
}
function ValidateOptions {
    if($R.MapOptions -and $R.MapOptions -notmatch '^\?[^\s"\r\n]*$'){throw '地图 URL 选项必须以 ? 开始，且不含空白或引号。'}
    foreach($Arg in @($R.LaunchArguments)){ValidateExtra $Arg}
    foreach($Arg in @($R.AutomaticArguments -split '\s+'|Where-Object {$_})){ValidateExtra $Arg}
    if($R.OutputArgument){ValidateExtra ('-'+$R.OutputArgument+'=output');if($R.OutputArgument -notmatch '^[A-Za-z][A-Za-z0-9_.-]*$'){throw '结果输出参数名无效。'}}
    if($R.AnalysisStartSeconds -lt 0 -or $R.AnalysisEndSeconds -le $R.AnalysisStartSeconds -or [double]::IsInfinity($R.AnalysisEndSeconds) -or [double]::IsNaN($R.AnalysisEndSeconds)){throw '分析时间段必须满足 0 <= 开始 < 结束。'}
    if($R.AutomaticRoute -and !$R.CompletionMarker){throw '自动路线必须配置明确的完成标记。'}
    if($R.AutomaticRoute -and $R.ExpectedActions -gt 0){
        if(!$R.SuccessPattern){throw '请在方案中配置成功动作日志正则，通用插件不内置项目日志格式。'}
        $Regex=[regex]::new($R.SuccessPattern,[Text.RegularExpressions.RegexOptions]::None,[TimeSpan]::FromSeconds(2))
        if($Regex.IsMatch('')){throw '成功动作日志正则不能匹配空文本。'}
    }
    if($R.PrepareScript){$null=ResolvePrepareScript}
}
function SettingsFor([string]$Stage) {
    $Build=@('ProjectFile','EngineRoot','GameTarget','Platform','CookMaps','PrepareScript','PrepareArguments')
    $Route=@('CaptureMap','MapOptions','LaunchArguments','AutomaticRoute','AutomaticArguments','CompletionMarker','ExpectedActions','SuccessPattern','OutputArgument')
    $Capture=$Build+$Route+@('CaptureStrategy')
    $Runtime=$Build+$Route+@('RuntimeMode','ClearDriverCache','Background','BackgroundBudgetMs')
    $Fields=switch($Stage){
        'collector' {$Build}; 'capture' {$Capture}; 'conversion' {$Capture+@('GroupName')}
        'installed' {$Capture+@('GroupName')}; 'bundled' {$Build+@('GroupName')}
        'validation' {$Runtime}; 'analysis' {$Runtime+@('CaptureStrategy','InsightsExecutable','AnalysisStartSeconds','AnalysisEndSeconds')}
    }
    $Out=[ordered]@{};foreach($Key in $Fields){$Out[$Key]=$R.$Key};return $Out
}
function Fingerprint($Value) {
    $Bytes=[Text.Encoding]::UTF8.GetBytes(($Value|ConvertTo-Json -Depth 30 -Compress))
    $Hash=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($Hash.ComputeHash($Bytes))).Replace('-','')}finally{$Hash.Dispose()}
}
function SourceStamp {
    # Code/config are hashed; large source assets use path/size/mtime as a change detector.
    # This is not a substitute for a clean reproducible build or a source-control identity.
    $Files=@(Get-Item -LiteralPath $R.ProjectFile)
    foreach($Dir in @('Source','Config','Plugins','Content')){
        $Path=Join-Path $Root $Dir
        if(Test-Path -LiteralPath $Path){$Files+=Get-ChildItem -LiteralPath $Path -Recurse -File|Where-Object {
            $Relative=$_.FullName.Substring($Root.Length)
            $Relative -notmatch '[\\/](Binaries|Intermediate|Saved|\.git)[\\/]' -and
            $Relative -notmatch '[\\/]Config[\\/]PSOWorkbench[\\/]' -and
            $_.Extension -in @('.cpp','.h','.hpp','.cs','.ini','.uplugin','.ps1','.uasset','.umap')
        }}
    }
    $EngineVersion=Join-Path $R.EngineRoot 'Engine/Build/Build.version'
    if(Test-Path -LiteralPath $EngineVersion){$Files+=Get-Item -LiteralPath $EngineVersion}
    $Rows=@($Files|Sort-Object FullName|ForEach-Object {
        if($_.Extension -in @('.uasset','.umap')){@($_.FullName,$_.Length,$_.LastWriteTimeUtc.Ticks) -join '|'}
        else{$_.FullName+'|'+(HashFile $_.FullName)}
    })
    if($R.PrepareScript){$Prep=ResolvePrepareScript;$Rows+=($Prep+'|'+(HashFile $Prep))}
    return Fingerprint $Rows
}
function ResolvePrepareScript {
    $Path=$R.PrepareScript
    if(![IO.Path]::IsPathRooted($Path)){$Path=Join-Path $Root $Path}
    if(!(Test-Path -LiteralPath $Path -PathType Leaf) -or [IO.Path]::GetExtension($Path) -ne '.ps1'){throw '准备脚本必须是存在的 .ps1 文件。'}
    return (Resolve-Path -LiteralPath $Path).Path
}
function AddIdentity([string]$Key,$Value) {
    $Item=[pscustomobject]$Value
    $Parents=[ordered]@{}
    switch($Key){
        'capture' {$Parents.collector=$State.collector.artifactId}
        'conversion' {$Parents.collector=$State.collector.artifactId;$Parents.capturesRevision=$State.capturesRevision}
        'installed' {$Parents.conversion=$State.conversion.artifactId}
        'bundled' {$Parents.installed=$State.installed.artifactId}
        'validation' {$Parents.bundled=$State.bundled.artifactId}
        'analysis' {
            if($State.validation){$Parents.validation=$State.validation.artifactId}
            else{$Parents.capture=(@($State.captures)|Select-Object -Last 1).artifactId}
        }
    }
    foreach($Pair in @{schema=2;artifactId=[guid]::NewGuid().ToString('N');settings=(SettingsFor $Key);sourceStamp=$CurrentSourceStamp;parents=[pscustomobject]$Parents;parentKeys=@($Parents.Keys);staleReason='';evidence=$Job}.GetEnumerator()){
        $Item|Add-Member -NotePropertyName $Pair.Key -NotePropertyValue $Pair.Value -Force
    }
    return $Item
}
function FileProblem($Items) {
    foreach($Item in @($Items)){
        if(!$Item){continue}
        if(!(Test-Path -LiteralPath $Item.path -PathType Leaf)){return '依赖文件缺失：'+$Item.path}
        if((HashFile $Item.path) -ne $Item.sha256){return '依赖文件 Hash 已改变：'+$Item.path}
    }
    return ''
}
function ArtifactProblem([string]$Key,$Item) {
    if(!$Item){return '尚无产物'}
    if($Item.schema -ne 2){return '旧记录缺少依赖身份，请重新生成'}
    if((Fingerprint $Item.settings) -ne (Fingerprint (SettingsFor $Key))){return '当前方案配置已变化'}
    if($Key -in @('collector','bundled') -and $Item.sourceStamp -ne $CurrentSourceStamp){return '项目源码/配置/资源来源已变化，需重建'}
    foreach($Parent in $Item.parents.PSObject.Properties){
        if($Parent.Name -eq 'capturesRevision'){
            if($Parent.Value -ne $State.capturesRevision){return '采集记录集合已变化，需重新转换'}
        }elseif($Parent.Name -eq 'capture'){
            $Last=@($State.captures)|Select-Object -Last 1
            if(!$Last -or $Last.artifactId -ne $Parent.Value -or $Last.staleReason){return '来源采集已变化或待更新'}
        }else{
            $Current=$State.($Parent.Name)
            if(!$Current -or $Current.artifactId -ne $Parent.Value -or $Current.staleReason){return '上游产物已变化或待更新：'+$Parent.Name}
        }
    }
    switch($Key){
        {$_ -in @('collector','bundled')} {
            if(!$Item.packageFiles){return '缺少包体身份清单，请重建'}
            $Issue=FileProblem (@($Item.keys)+@($Item.packageFiles));if($Issue){return $Issue}
            if($Key -eq 'bundled'){
                $CurrentInputs=@(Get-ChildItem "$Root/Build/Windows/PipelineCaches" -File -Filter "*${Name}_${Format}.spc" -ErrorAction SilentlyContinue|Sort-Object FullName)
                if($CurrentInputs.Count -ne @($Item.inputs).Count){return 'SPC 输入集合已变化，需重建'}
                $Issue=FileProblem $Item.inputs;if($Issue){return $Issue}
                if((Fingerprint @($CurrentInputs.FullName)) -ne (Fingerprint @($Item.inputs|Sort-Object path|ForEach-Object {$_.path}))){return 'SPC 输入路径集合已变化'}
            }
        }
        'capture' {return FileProblem $Item.records}
        'conversion' {return FileProblem @(@{path=$Item.spc;sha256=$Item.sha256})}
        'installed' {return FileProblem @($Item)}
        'validation' {return FileProblem $Item.outputs}
        'analysis' {return FileProblem $Item.outputs}
    }
    return ''
}
function RefreshValidity {
    foreach($Key in @('collector','captures','conversion','installed','bundled','validation','analysis')){
        if($Key -eq 'captures'){
            foreach($Item in @($State.captures)){
                if($Item){$Item|Add-Member -NotePropertyName staleReason -NotePropertyValue (ArtifactProblem 'capture' $Item) -Force}
            }
        }elseif($State.$Key){$State.$Key|Add-Member -NotePropertyName staleReason -NotePropertyValue (ArtifactProblem $Key $State.$Key) -Force}
    }
    JsonFile $State $StateFile
}
function RequireArtifact([string]$Key) {
    if(!$State.$Key -or $State.$Key.staleReason){throw "产物 $Key 待更新：$($State.$Key.staleReason)；请检查依赖并重新生成。"}
}
