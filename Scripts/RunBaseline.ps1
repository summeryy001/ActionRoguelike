[CmdletBinding()]
param([ValidateRange(1,10)][int]$Pairs=3, [switch]$Execute)
$ErrorActionPreference='Stop'
$Root=(Resolve-Path "$PSScriptRoot/..").Path
$Package=Join-Path $Root 'Saved/PSOValidation/Package/Windows'
$Exe=Join-Path $Package 'ActionRoguelike/Binaries/Win64/ActionRoguelike.exe'
if (!(Test-Path $Exe)) { throw 'Package AR2 before running this script.' }
function Inventory {
    @(Get-ChildItem $Package -Recurse -File | Where-Object {
        $_.FullName -notmatch '[\\/]Saved[\\/]' -and $_.Extension -ne '.pdb'
    } | Sort-Object FullName | ForEach-Object {
        [ordered]@{Path=$_.FullName.Substring($Package.Length+1); Bytes=$_.Length; SHA256=(Get-FileHash $_.FullName).Hash}
    })
}
function CacheSnapshot {
    foreach($folder in @("$env:LOCALAPPDATA/NVIDIA/DXCache", "$env:USERPROFILE/AppData/LocalLow/NVIDIA/DXCache", "$env:USERPROFILE/AppData/LocalLow/NVIDIA/PerDriverVersion/DXCache")) {
        [ordered]@{Directory=$folder; Exists=(Test-Path $folder); Files=@(Get-ChildItem $folder -File -ErrorAction SilentlyContinue | ForEach-Object {
            @{Name=$_.Name;Bytes=$_.Length;ModifiedUtc=$_.LastWriteTimeUtc.ToString('o')}
        })}
    }
}
function AssertIdle {
    $busy=@(Get-Process -ErrorAction SilentlyContinue | Where-Object {$_.ProcessName -match '^(UnrealEditor|ActionRoguelike|Loki)(-|$)'})
    if($busy.Count) { throw ('Close UE editors/games before testing: '+ (($busy | ForEach-Object {$_.ProcessName+':'+$_.Id}) -join ', ')) }
}
$Batch=Join-Path $Root ('Saved/PSOBaseline/'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'_'+[guid]::NewGuid().ToString('N').Substring(0,6))
New-Item $Batch -ItemType Directory -Force | Out-Null
$Baseline=Inventory
$Fingerprint=$Baseline | ConvertTo-Json -Depth 5 -Compress
$Baseline | ConvertTo-Json -Depth 5 | Set-Content "$Batch/package.json" -Encoding UTF8
$Settings=[ordered]@{
    'r.PSOPrecaching'=0; 'r.PSOPrecache.GlobalShaders'=0; 'r.ShaderPipelineCache.Enabled'=0
    'r.PSOPrecache.Validation'=0; 'r.PSOPrecache.ProxyCreationStrategy'=0
}
$Overrides=($Settings.Keys | ForEach-Object {'[SystemSettings]:{0}={1}' -f $_,$Settings[$_]}) -join ','
$Queries=@('t.IdleWhenNotForeground 0','t.MaxFPS 0','r.VSync 0','pso.StartupCheck 0')+@($Settings.Keys)
$Results=@()
for($pair=1;$pair -le $Pairs;$pair++) {
    foreach($mode in @('Cold','Warm')) {
        $Run=Join-Path $Batch ('{0:D2}_{1}' -f $pair,$mode)
        New-Item $Run -ItemType Directory | Out-Null
        $ArgsList=@('/Game/ActionRoguelike/Maps/TestLevel?listen','-dx12','-sm6','-windowed','-ResX=1280','-ResY=720','-NoSteam','-NoVSync','-unattended',
            '-PSOValidation','-trace=cpu,frame,bookmark,log,gpu','-statnamedevents',
            ('-PSOValidationOutput="{0}"' -f $Run), ('-UserDir="{0}/User"' -f $Run),
            ('-abslog="{0}/game.log"' -f $Run), ('-tracefile="{0}/capture.utrace"' -f $Run),
            ('-ini:Engine:'+ $Overrides), ('-ExecCmds="'+($Queries -join ',')+'"'))
        if($mode -eq 'Cold') {$ArgsList+='-clearPSODriverCache'}
        @{Mode=$mode;Pair=$pair;Execute=[bool]$Execute;Executable=$Exe;Arguments=$ArgsList;Settings=$Settings;
          Revision=(& git -C $Root rev-parse HEAD);WorkingTree=@(& git -C $Root status --short);
          ColdCacheRequested=($mode -eq 'Cold');DriverCacheClearVerified=$false;
          Route='Existing PSOValidation actor, direct TestLevel listen; not main-menu startup';
          Caveat='Fixed action schedule; nearest-enemy aim and AI are not deterministic. Cache snapshots do not prove clearing.'
        } | ConvertTo-Json -Depth 6 | Set-Content "$Run/manifest.json" -Encoding UTF8
        if(!$Execute) {Write-Output "Prepared only: $Run"; continue}
        AssertIdle
        if(((Inventory | ConvertTo-Json -Depth 5 -Compress)) -ne $Fingerprint) {throw 'Package changed during batch.'}
        @(CacheSnapshot) | ConvertTo-Json -Depth 6 | Set-Content "$Run/cache-before.json" -Encoding UTF8
        $Start=Get-Date
        $Process=Start-Process $Exe -ArgumentList $ArgsList -WorkingDirectory (Split-Path $Exe) -WindowStyle Hidden -PassThru
        if(!$Process.WaitForExit(300000)) {
            Stop-Process -Id $Process.Id -ErrorAction SilentlyContinue
            @{Valid=$false;Reason='300 second timeout; terminated test-owned process'} | ConvertTo-Json | Set-Content "$Run/acceptance.json"
            throw "Run timed out: $Run"
        }
        $Process.Refresh()
        @(CacheSnapshot) | ConvertTo-Json -Depth 6 | Set-Content "$Run/cache-after.json" -Encoding UTF8
        $Log=Get-Content "$Run/game.log" -Raw
        $Successful=[regex]::Matches($Log,'PSOValidation action=\S+ started=1').Count
        $Actual=@{}
        foreach($key in $Settings.Keys) {
            $matches=[regex]::Matches($Log,[regex]::Escape($key)+'\s*=\s*"?([0-9]+)"?')
            $Actual[$key]=if($matches.Count){[int]$matches[$matches.Count-1].Groups[1].Value}else{$null}
        }
        $SettingsOK=@($Settings.Keys | Where-Object {$null -eq $Actual[$_] -or $Actual[$_] -ne $Settings[$_]}).Count -eq 0
        $Trace=Get-Item "$Run/capture.utrace" -ErrorAction SilentlyContinue
        $Valid=$Process.ExitCode -eq 0 -and $Successful -eq 6 -and $Log.Contains('label=Complete') -and $Log.Contains('respawnAlive=1') -and
            !$Log.Contains('Ensure condition failed') -and !$Log.Contains('Fatal error:') -and $SettingsOK -and $Trace -and $Trace.Length -gt 0 -and (Test-Path "$Run/frames.csv")
        $Init=[regex]::Match($Log,'Engine is initialized\. Leaving FEngineLoop::Init\(\).*?Took ([0-9.]+)')
        $InitSeconds=if($Init.Success){[double]::Parse($Init.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)}else{$null}
        @{Valid=[bool]$Valid;ExitCode=$Process.ExitCode;SuccessfulActions=$Successful;ActualSettings=$Actual;
          EngineReportedInitSeconds=$InitSeconds;StartupTimingNote='Engine-reported init only; not process-to-interactive startup. Inspect Trace and MapReady bookmark.';
          ProcessWallSeconds=((Get-Date)-$Start).TotalSeconds;DriverCacheClearVerified=$false
        } | ConvertTo-Json -Depth 5 | Set-Content "$Run/acceptance.json" -Encoding UTF8
        if(!$Valid) {throw "Validation failed; remaining runs stopped: $Run"}
        $Frames=Import-Csv "$Run/frames.csv"
        foreach($label in @('Primary_First','Blackhole_First','Dash_First','Primary_Repeat','Blackhole_Repeat','Dash_Repeat')) {
            $m=[regex]::Match($Log,'label='+$label+' elapsed=([0-9.]+)')
            if(!$m.Success){throw "Missing action timestamp: $label"}
            $t=[double]::Parse($m.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)
            $values=@($Frames | Where-Object {
                $end=[double]::Parse($_.ElapsedSeconds,[Globalization.CultureInfo]::InvariantCulture)
                $ms=[double]::Parse($_.FrameMs,[Globalization.CultureInfo]::InvariantCulture)
                $end -ge $t -and ($end-$ms/1000) -lt ($t+2)
            } | ForEach-Object {[double]::Parse($_.FrameMs,[Globalization.CultureInfo]::InvariantCulture)})
            $Results += [pscustomobject]@{Pair=$pair;Mode=$mode;Action=$label;MaxFrameMs=($values | Measure-Object -Maximum).Maximum;Samples=$values.Count}
        }
        $Results | Export-Csv "$Batch/skill-frames.csv" -NoTypeInformation -Encoding UTF8
    }
}
if($Execute -and ((Inventory | ConvertTo-Json -Depth 5 -Compress) -ne $Fingerprint)){throw 'Package changed at batch end.'}
Write-Output "Evidence: $Batch"
if(!$Execute){Write-Output 'Dry run only. Use -Execute to launch games and request driver-cache clearing.'}
