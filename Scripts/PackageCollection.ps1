[CmdletBinding()]
param([switch]$Execute)
$ErrorActionPreference='Stop'
$Root=(Resolve-Path "$PSScriptRoot/..").Path
$Engine=if($env:UE_ROOT){$env:UE_ROOT}else{'F:/Git_Repository/4399-unreal/unrealengine-4399'}
$Package=Join-Path $Root 'Saved/PSOCollection/Package'
$Evidence=Join-Path $Root ('Saved/PSOCollection/Cooks/'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'_'+[guid]::NewGuid().ToString('N').Substring(0,6))
New-Item $Evidence -ItemType Directory -Force|Out-Null
$ArgsList=@('-nocompile','-nocompileuat','BuildCookRun',('-project="'+$Root+'/ActionRoguelike.uproject"'),'-noP4','-platform=Win64','-clientconfig=Development','-skipbuild','-skipbuildeditor','-cook','-stage','-pak','-iostore','-archive',('-archivedirectory="'+$Package+'"'),'-unattended','-utf8output')
@{Engine=$Engine;Revision=(& git -C $Root rev-parse HEAD);WorkingTree=@(& git -C $Root status --short);Arguments=$ArgsList;Execute=[bool]$Execute} | ConvertTo-Json -Depth 5 | Set-Content "$Evidence/command.json" -Encoding UTF8
if(!$Execute){Write-Output "Prepared only: $Evidence";exit}
$start=Get-Date
& "$Engine/Engine/Build/BatchFiles/RunUAT.bat" @ArgsList *> "$Evidence/cook.log"
if($LASTEXITCODE -ne 0){throw "Cook failed: $Evidence"}
$keys=@(Get-ChildItem "$Root/Saved/Cooked/Windows/ActionRoguelike/Metadata/PipelineCaches" -Filter '*.shk' -File)
if(!@($keys|Where-Object {$_.Name -like '*PCD3D_SM6*'}).Count){throw 'No SM6 stable shader keys generated.'}
New-Item "$Evidence/StableKeys" -ItemType Directory|Out-Null
$keys | Copy-Item -Destination "$Evidence/StableKeys"
$Exe="$Package/Windows/ActionRoguelike/Binaries/Win64/ActionRoguelike.exe"
$manifest=[ordered]@{Complete=$true;Seconds=((Get-Date)-$start).TotalSeconds;Package=$Package;Executable=$Exe;ExeSHA256=(Get-FileHash $Exe).Hash;
    StableKeys=@(Get-ChildItem "$Evidence/StableKeys" -File | ForEach-Object {@{Name=$_.Name;Bytes=$_.Length;SHA256=(Get-FileHash $_.FullName).Hash}});
    Revision=(& git -C $Root rev-parse HEAD);Target='Windows DX12; SM5 and SM6 cooked; collection will select SM6';
    Caveat='Keys must be paired with a recording from this matching Cook/package. No driver cache clearing is required for collection.'}
$manifest|ConvertTo-Json -Depth 6|Set-Content "$Evidence/manifest.json" -Encoding UTF8
@{Cook=$Evidence;Package=$Package;Manifest="$Evidence/manifest.json"}|ConvertTo-Json|Set-Content "$Root/Saved/PSOCollection/current-cook.json" -Encoding UTF8
Write-Output "Collection Cook: $Evidence"
