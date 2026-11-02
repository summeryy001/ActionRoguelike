[CmdletBinding()]
param([switch]$Execute,[string]$BuildManifest)
$ErrorActionPreference='Stop'
$Root=(Resolve-Path "$PSScriptRoot/..").Path
function HashFile([string]$Path){
    $Stream=[IO.File]::OpenRead($Path);$Hasher=[Security.Cryptography.SHA256]::Create()
    try {([BitConverter]::ToString($Hasher.ComputeHash($Stream))).Replace('-','')}finally{$Stream.Dispose();$Hasher.Dispose()}
}
if(!$BuildManifest){$BuildManifest=(Get-Content "$Root/Saved/PSOBundled/current-build.json" -Raw | ConvertFrom-Json).Manifest}
$Build=Get-Content $BuildManifest -Raw | ConvertFrom-Json
if(!$Build.Valid -or !$Build.PackagedCacheListed){throw 'Build acceptance must pass first'}
$Exe=$Build.Executable
if((HashFile $Exe) -ne $Build.ExeSHA256){throw 'EXE differs from accepted build'}
foreach($Cache in $Build.RuntimeCaches){if((HashFile $Cache.Path) -ne $Cache.SHA256){throw 'Runtime cache evidence changed'}}
$Paks=@(Get-ChildItem "$($Build.Package)/Windows/ActionRoguelike/Content/Paks" -File | Sort-Object Name)
if(!$Paks.Count){throw 'No package containers'}
$Inventory=@($Paks | ForEach-Object {[ordered]@{Name=$_.Name;Bytes=$_.Length;SHA256=(HashFile $_.FullName)}})
$Run="$Root/Saved/PSOBundled/Runs/"+(Get-Date -Format 'yyyyMMdd_HHmmss')+'_'+[guid]::NewGuid().ToString('N').Substring(0,6)
New-Item $Run -ItemType Directory -Force | Out-Null
$Settings=[ordered]@{'r.PSOPrecaching'=0;'r.PSOPrecache.GlobalShaders'=0;'r.PSOPrecache.Validation'=0;'r.PSOPrecache.ProxyCreationStrategy'=0;'r.ShaderPipelineCache.Enabled'=1;'r.ShaderPipelineCache.StartupMode'=1;'r.ShaderPipelineCache.SaveUserCache'=0}
$Overrides=($Settings.Keys | ForEach-Object {'[SystemSettings]:{0}={1}' -f $_,$Settings[$_]}) -join ','
$ArgsList=@('/Game/ActionRoguelike/Maps/TestLevel?listen','-dx12','-sm6','-windowed','-ResX=1280','-ResY=720','-NoSteam','-NoVSync','-unattended','-PSOValidation','-trace=cpu,frame,bookmark,log,gpu','-statnamedevents',
    ('-PSOValidationOutput="'+$Run+'"'),('-UserDir="'+$Run+'/User"'),('-abslog="'+$Run+'/game.log"'),('-tracefile="'+$Run+'/capture.utrace"'),('-ini:Engine:'+$Overrides),
    ('-ExecCmds="t.IdleWhenNotForeground 0,t.MaxFPS 0,r.VSync 0,pso.StartupCheck 0,'+($Settings.Keys -join ',')+'"'))
@{BuildManifest=(Resolve-Path $BuildManifest).Path;ExeSHA256=$Build.ExeSHA256;Containers=$Inventory;Settings=$Settings;Arguments=$ArgsList;Execute=[bool]$Execute;DriverCacheClearRequested=$false;Purpose='仅 Bundled 运行验收，使用已有驱动缓存，不作为冷启动性能测试'} | ConvertTo-Json -Depth 8 | Set-Content "$Run/manifest.json" -Encoding UTF8
if(!$Execute){Write-Output "Prepared only: $Run";exit}
if(@(Get-Process -ErrorAction SilentlyContinue | Where-Object {$_.ProcessName -match '^(UnrealEditor|ActionRoguelike|Loki)(-|$)'}).Count){throw 'Close UE editors/games first'}
$Acceptance=[ordered]@{Valid=$false;BuildManifest=$BuildManifest;Evidence=$Run}
try {
    $Process=Start-Process $Exe -ArgumentList $ArgsList -WorkingDirectory (Split-Path $Exe) -WindowStyle Hidden -PassThru
    if(!$Process.WaitForExit(300000)){Stop-Process -Id $Process.Id;throw 'Test timed out; terminated test-owned process'}
    $Process.Refresh();$Acceptance.ExitCode=$Process.ExitCode
    $Log=Get-Content "$Run/game.log" -Raw
    $Actual=@{}
    foreach($Key in $Settings.Keys){
        $Found=[regex]::Matches($Log,[regex]::Escape($Key)+'\s*=\s*"?([0-9]+)"?')
        $Actual[$Key]=if($Found.Count){[int]$Found[$Found.Count-1].Groups[1].Value}else{$null}
    }
    $Acceptance.ActualSettings=$Actual
    if(@($Settings.Keys | Where-Object {$null -eq $Actual[$_] -or $Actual[$_] -ne $Settings[$_]}).Count){throw 'Effective settings mismatch'}
    $Opened=[regex]::Match($Log,'Opened FPipelineCacheFile: ([^\r\n]*ActionRoguelike_PCD3D_SM6\.stable\.upipelinecache).*with (\d+) entries')
    $Begin=[regex]::Match($Log,'LogPSOStartupCheck: Display: Begin cache=ActionRoguelike queued=(\d+) clock=([\d.]+)')
    $Complete=[regex]::Match($Log,'LogPSOStartupCheck: Display: Complete cache=ActionRoguelike processed=(\d+) wallSeconds=([\d.]+) submissionSeconds=([\d.]+) clock=([\d.]+)')
    if(!$Opened.Success -or !$Begin.Success -or !$Complete.Success){throw 'Missing target cache open/begin/complete evidence'}
    if([int]$Begin.Groups[1].Value -le 0 -or [int]$Complete.Groups[1].Value -ne [int]$Begin.Groups[1].Value){throw 'Non-positive or incomplete observed batch'}
    if($Complete.Index -lt $Begin.Index -or $Begin.Index -lt $Opened.Index){throw 'Unexpected cache event order'}
    foreach($Library in @('Global','ActionRoguelike')){if(!$Log.Contains("Loaded Shared Shader Library $Library")){throw "Shader library not observed: $Library"}}
    $Actions=[regex]::Matches($Log,'PSOValidation action=\S+ started=1').Count
    $Acceptance.SuccessfulActions=$Actions
    if($Process.ExitCode -ne 0 -or $Actions -ne 6 -or !$Log.Contains('label=Complete') -or !$Log.Contains('respawnAlive=1') -or $Log -match 'Ensure condition failed|Fatal error:|Assertion failed:'){throw 'Gameplay/exit acceptance failed'}
    if((Get-Item "$Run/capture.utrace").Length -le 0 -or !(Test-Path "$Run/frames.csv")){throw 'Missing Trace/frames'}
    $AfterFiles=@(Get-ChildItem "$($Build.Package)/Windows/ActionRoguelike/Content/Paks" -File | Sort-Object Name)
    $After=@($AfterFiles | ForEach-Object {[ordered]@{Name=$_.Name;Bytes=$_.Length;SHA256=(HashFile $_.FullName)}})
    if(($After | ConvertTo-Json -Compress) -ne ($Inventory | ConvertTo-Json -Compress) -or (HashFile $Exe) -ne $Build.ExeSHA256){throw 'Package changed during run'}
    $Acceptance.CachePath=$Opened.Groups[1].Value
    $Acceptance.CacheEntries=[int]$Opened.Groups[2].Value
    $Acceptance.Queued=[int]$Begin.Groups[1].Value
    $Acceptance.Processed=[int]$Complete.Groups[1].Value
    $Acceptance.WallSeconds=[double]::Parse($Complete.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture)
    $Acceptance.SubmissionSeconds=[double]::Parse($Complete.Groups[3].Value,[Globalization.CultureInfo]::InvariantCulture)
    $Acceptance.Valid=$true
    $Acceptance.Note='Observed batch complete does not prove full game coverage or zero driver work. Existing driver cache; no performance A/B claim.'
} catch {
    $Acceptance.Error=$_.Exception.Message
    $Acceptance | ConvertTo-Json -Depth 8 | Set-Content "$Run/acceptance.json" -Encoding UTF8
    throw
}
$Acceptance | ConvertTo-Json -Depth 8 | Set-Content "$Run/acceptance.json" -Encoding UTF8
($Log -split '\r?\n' | Where-Object {$_ -match 'PSOStartupCheck|Opened FPipelineCacheFile|Loaded Shared Shader Library|FShaderPipelineCache .*completed|PSOValidation action=|label=Complete'}) | Set-Content "$Run/runtime-summary.log" -Encoding UTF8
Write-Output "Bundled runtime accepted: $Run"
