[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Recording, [switch]$Execute, [switch]$Install)
$ErrorActionPreference='Stop'
$Root=(Resolve-Path "$PSScriptRoot/..").Path
$Recording=(Resolve-Path $Recording).Path
$Engine=if($env:UE_ROOT){$env:UE_ROOT}else{'F:/Git_Repository/4399-unreal/unrealengine-4399'}
$a=Get-Content "$Recording/acceptance.json" -Raw|ConvertFrom-Json
if(!$a.Valid){throw 'Only validated recordings may be converted.'}
foreach($r in $a.Records){if((Get-FileHash $r.Path).Hash -ne $r.SHA256){throw 'Recording hash changed.'}}
$keys=@(Get-ChildItem "$Recording/StableKeys" -Filter '*PCD3D_SM6.shk' -File)
if($keys.Count -ne 2 -or !@($keys|Where-Object {$_.Name -like '*-Global-*'}).Count){throw 'Expected matching SM6 Global and project keys.'}
$cook=Get-Content ($a.Cook+'/manifest.json') -Raw|ConvertFrom-Json
foreach($k in $keys){$expected=@($cook.StableKeys|Where-Object {$_.Name -eq $k.Name});if($expected.Count -ne 1 -or (Get-FileHash $k.FullName).Hash -ne $expected[0].SHA256){throw 'Stable keys differ from matching Cook.'}}
$out=Join-Path $Root ('Saved/PSOCollection/Conversions/'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'_'+[guid]::NewGuid().ToString('N').Substring(0,6))
New-Item $out -ItemType Directory -Force|Out-Null
$spc=Join-Path $out 'PSO_ActionRoguelike_PCD3D_SM6.spc'
$argsList=@(($Root+'/ActionRoguelike.uproject'),'-run=ShaderPipelineCacheTools','expand')+@($a.Records|ForEach-Object {$_.Path})+@($keys|ForEach-Object {$_.FullName})+@($spc,'-unattended','-nop4','-NoSteam','-NullRHI',('-abslog='+$out+'/expand.log'))
@{Recording=$Recording;Cook=$a.Cook;Arguments=$argsList;Execute=[bool]$Execute;Install=[bool]$Install;Revision=(& git -C $Root rev-parse HEAD)}|ConvertTo-Json -Depth 6|Set-Content "$out/command.json" -Encoding UTF8
if(!$Execute){Write-Output "Prepared only: $out";exit}
& "$Engine/Engine/Binaries/Win64/UnrealEditor-Cmd.exe" @argsList *> "$out/console.log"
$code=$LASTEXITCODE
$log=Get-Content "$out/expand.log" -Raw
$count=[regex]::Match($log,'Generated (\d+) stable PSOs total')
$valid=$code -eq 0 -and $count.Success -and [int]$count.Groups[1].Value -gt 0 -and (Test-Path $spc) -and (Get-Item $spc).Length -gt 0
@{Valid=$valid;ExitCode=$code;StablePermutations=if($count.Success){[int]$count.Groups[1].Value}else{$null};Recording=$Recording;Cook=$a.Cook;SPC=$spc;
SHA256=if(Test-Path $spc){(Get-FileHash $spc).Hash}else{$null};Bytes=if(Test-Path $spc){(Get-Item $spc).Length}else{0};
Caveat='Stable permutations can exceed recorded PSOs; runtime Cook resolves and deduplicates again. Inspect mapping warnings in expand.log.'}|ConvertTo-Json -Depth 6|Set-Content "$out/acceptance.json" -Encoding UTF8
if(!$valid){throw "Conversion failed: $out"}
if($Install){
    $dest="$Root/Build/Windows/PipelineCaches/PSO_ActionRoguelike_PCD3D_SM6.spc"
    if((Test-Path $dest) -and (Get-FileHash $dest).Hash -ne (Get-FileHash $spc).Hash){throw 'Existing SPC differs; preserve it and review before replacing.'}
    New-Item (Split-Path $dest) -ItemType Directory -Force|Out-Null
    Copy-Item $spc $dest -Force
}
Write-Output "Stable PSO conversion: $out"
