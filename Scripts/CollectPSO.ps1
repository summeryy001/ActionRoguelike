[CmdletBinding()]
param([switch]$Execute)
$ErrorActionPreference='Stop'
$Root=(Resolve-Path "$PSScriptRoot/..").Path
$cook=Get-Content "$Root/Saved/PSOCollection/current-cook.json" -Raw|ConvertFrom-Json
$inputManifest=Get-Content $cook.Manifest -Raw|ConvertFrom-Json
$Exe=$inputManifest.Executable
if((Get-FileHash $Exe).Hash -ne $inputManifest.ExeSHA256){throw 'Collection executable changed after Cook.'}
$Run=Join-Path $Root ('Saved/PSOCollection/Recordings/'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'_'+[guid]::NewGuid().ToString('N').Substring(0,6))
New-Item $Run -ItemType Directory -Force|Out-Null
$settings=[ordered]@{'r.PSOPrecaching'=0;'r.PSOPrecache.GlobalShaders'=0;'r.PSOPrecache.Validation'=0;'r.PSOPrecache.ProxyCreationStrategy'=0;
'r.ShaderPipelineCache.Enabled'=1;'r.ShaderPipelineCache.StartupMode'=0;'r.ShaderPipelineCache.ExcludePrecachePSO'=0;
'r.ShaderPipelineCache.LogPSO'=1;'r.ShaderPipelineCache.SaveBoundPSOLog'=1;'r.ShaderPipelineCache.SaveUserCache'=0}
$overrides=($settings.Keys|ForEach-Object {'[SystemSettings]:{0}={1}' -f $_,$settings[$_]}) -join ','
$queries=@('t.IdleWhenNotForeground 0','t.MaxFPS 0','r.VSync 0','pso.StartupCheck 0')+@($settings.Keys)
$argsList=@('/Game/ActionRoguelike/Maps/TestLevel?listen','-dx12','-sm6','-windowed','-ResX=1280','-ResY=720','-NoSteam','-NoVSync','-unattended','-PSOValidation','-logPSO',
'-trace=cpu,frame,bookmark,log,gpu','-statnamedevents',('-PSOValidationOutput="'+$Run+'"'),('-UserDir="'+$Run+'/User"'),('-abslog="'+$Run+'/game.log"'),('-tracefile="'+$Run+'/capture.utrace"'),('-ini:Engine:'+$overrides),('-ExecCmds="'+($queries -join ',')+'"'))
@{Cook=$cook.Cook;Executable=$Exe;Arguments=$argsList;Settings=$settings;Execute=[bool]$Execute;Revision=(& git -C $Root rev-parse HEAD);
Purpose='Record bound PSO descriptions, not a performance benchmark. Auto off; file cache recording on, playback paused; no driver-cache clearing.'} | ConvertTo-Json -Depth 6 | Set-Content "$Run/command.json" -Encoding UTF8
if(!$Execute){Write-Output "Prepared only: $Run";exit}
$busy=@(Get-Process -ErrorAction SilentlyContinue|Where-Object {$_.ProcessName -match '^(UnrealEditor|ActionRoguelike|Loki)(-|$)'})
if($busy.Count){throw 'Close other UE editors/games before recording.'}
$files=@(Get-ChildItem ($cook.Package+'/Windows') -Recurse -File|Where-Object {$_.FullName.Substring($cook.Package.Length+1) -notmatch '[\\/]Saved[\\/]' -and $_.Extension -ne '.pdb'})
function PackageFingerprint { @($files|ForEach-Object {[ordered]@{Path=$_.FullName;Hash=(Get-FileHash $_.FullName).Hash}})|ConvertTo-Json -Compress }
$fingerprint=PackageFingerprint
$fingerprint|Set-Content "$Run/package.json" -Encoding UTF8
New-Item "$Run/StableKeys" -ItemType Directory|Out-Null
foreach($key in @($inputManifest.StableKeys|Where-Object {$_.Name -like '*PCD3D_SM6*'})) {
    $source=Join-Path ($cook.Cook+'/StableKeys') $key.Name
    if((Get-FileHash $source).Hash -ne $key.SHA256){throw 'Stable key snapshot changed.'}
    Copy-Item $source "$Run/StableKeys"
}
$p=Start-Process $Exe -ArgumentList $argsList -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(300000)){Stop-Process -Id $p.Id;throw 'Recording timed out.'}
$p.Refresh()
$log=Get-Content "$Run/game.log" -Raw
$actual=@{}
foreach($key in $settings.Keys){$m=[regex]::Matches($log,[regex]::Escape($key)+'\s*=\s*"?([0-9]+)"?');$actual[$key]=if($m.Count){[int]$m[$m.Count-1].Groups[1].Value}else{$null}}
$settingsOK=@($settings.Keys|Where-Object {$null -eq $actual[$_] -or $actual[$_] -ne $settings[$_]}).Count -eq 0
$records=@(Get-ChildItem "$Run/User" -Recurse -Filter '*.rec.upipelinecache' -File)
$actions=[regex]::Matches($log,'PSOValidation action=\S+ started=1').Count
$valid=$p.ExitCode -eq 0 -and $actions -eq 6 -and $settingsOK -and $log.Contains('label=Complete') -and $log.Contains('respawnAlive=1') -and !$log.Contains('Ensure condition failed') -and !$log.Contains('Fatal error:') -and $records.Count -gt 0 -and @($records|Where-Object {$_.Length -eq 0}).Count -eq 0
$unchanged=(PackageFingerprint) -eq $fingerprint
@{Valid=($valid -and $unchanged);ExitCode=$p.ExitCode;SuccessfulActions=$actions;ActualSettings=$actual;PackageUnchanged=$unchanged;
Records=@($records|ForEach-Object {@{Path=$_.FullName;Bytes=$_.Length;SHA256=(Get-FileHash $_.FullName).Hash}});Cook=$cook.Cook;
Caveat='One fixed route is a first coverage sample, not full game coverage. SM6 only. Driver warmth does not replace PSO recording.'} | ConvertTo-Json -Depth 7 | Set-Content "$Run/acceptance.json" -Encoding UTF8
if(!$valid -or !$unchanged){throw "Recording failed validation: $Run"}
Write-Output "PSO recording: $Run"
