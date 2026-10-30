[CmdletBinding()]
param([switch]$Execute)
$ErrorActionPreference='Stop'
# Avoid depending on Get-FileHash module discovery when Windows PowerShell is
# launched from PowerShell 7 with an inherited PSModulePath.
function Get-FileHash([string]$Path) {
    $Stream=[IO.File]::OpenRead($Path)
    $Hasher=[Security.Cryptography.SHA256]::Create()
    try { [pscustomobject]@{Hash=([BitConverter]::ToString($Hasher.ComputeHash($Stream))).Replace('-','')} }
    finally { $Hasher.Dispose(); $Stream.Dispose() }
}
$Root=(Resolve-Path "$PSScriptRoot/..").Path
$Engine=if($env:UE_ROOT){$env:UE_ROOT}else{'F:/Git_Repository/4399-unreal/unrealengine-4399'}
$Format='PCD3D_SM6'
$Library='ActionRoguelike'
$CacheName="${Library}_${Format}.stable.upipelinecache"
$InputDir="$Root/Build/Windows/PipelineCaches"
$Inputs=@(Get-ChildItem $InputDir -Recurse -File -Filter "*${Library}_${Format}.spc")
if(!$Inputs.Count){throw "Missing SPC: $InputDir/*${Library}_${Format}.spc"}
if(@($Inputs | Where-Object {$_.Length -eq 0}).Count){throw 'Empty SPC input'}
foreach($Required in @("$Engine/Engine/Build/BatchFiles/RunUAT.bat","$Engine/Engine/Binaries/Win64/UnrealPak.exe","$Root/Binaries/Win64/ActionRoguelike.exe")) {
    if(!(Test-Path $Required)){throw "Missing prerequisite: $Required"}
}
function Inventory($Files) {
    @($Files | Sort-Object FullName | ForEach-Object {
        [ordered]@{Path=$_.FullName;Bytes=$_.Length;SHA256=(Get-FileHash $_.FullName).Hash}
    })
}
$InputInventory=Inventory $Inputs
$InputFingerprint=$InputInventory | ConvertTo-Json -Depth 5 -Compress
$SourceExe="$Root/Binaries/Win64/ActionRoguelike.exe"
$SourceHash=(Get-FileHash $SourceExe).Hash
$Evidence="$Root/Saved/PSOBundled/Builds/"+(Get-Date -Format 'yyyyMMdd_HHmmss')+'_'+[guid]::NewGuid().ToString('N').Substring(0,6)
$Package="$Evidence/Package"
New-Item $Evidence -ItemType Directory -Force | Out-Null
$ArgsList=@('-nocompile','-nocompileuat','BuildCookRun',('-project="'+$Root+'/ActionRoguelike.uproject"'),'-noP4','-platform=Win64','-clientconfig=Development','-skipbuild','-skipbuildeditor','-cook','-stage','-pak','-iostore','-archive',('-archivedirectory="'+$Package+'"'),'-unattended','-utf8output')
@{Execute=[bool]$Execute;Engine=$Engine;EngineRevision=(& git -C $Engine rev-parse HEAD);ProjectRevision=(& git -C $Root rev-parse HEAD);WorkingTree=@(& git -C $Root status --short);Arguments=$ArgsList;SourceExeSHA256=$SourceHash;SPC=$InputInventory;ValidationTarget=$Format;Note='BuildCookRun may also Cook other configured formats. Runtime PSO loading/precompile is a separate acceptance step.'} | ConvertTo-Json -Depth 7 | Set-Content "$Evidence/command.json" -Encoding UTF8
if(!$Execute){Write-Output "Prepared only: $Evidence";Write-Output 'Use -Execute to Cook/package. Existing collection packages are preserved.';exit}
if(@(Get-Process -ErrorAction SilentlyContinue | Where-Object {$_.ProcessName -match '^(UnrealEditor|ActionRoguelike|Loki)(-|$)'}).Count){throw 'Close UE editors/games before Cook/package.'}
New-Item "$Evidence/Inputs" -ItemType Directory | Out-Null
# Keep relative paths so identically named SPC files in subdirectories remain distinct.
foreach($Input in $Inputs){
    $Relative=$Input.FullName.Substring((Resolve-Path $InputDir).Path.Length+1)
    $Destination=Join-Path "$Evidence/Inputs" $Relative
    New-Item (Split-Path $Destination) -ItemType Directory -Force | Out-Null
    Copy-Item -LiteralPath $Input.FullName -Destination $Destination
}
$Start=Get-Date
$Acceptance=[ordered]@{Valid=$false;RuntimeVerified=$false;Evidence=$Evidence;ValidationTarget=$Format}
try {
    & "$Engine/Engine/Build/BatchFiles/RunUAT.bat" @ArgsList *> "$Evidence/cook.log"
    $Acceptance.ExitCode=$LASTEXITCODE
    if($LASTEXITCODE -ne 0){throw "BuildCookRun failed: $LASTEXITCODE"}
    $AfterInputs=@(Get-ChildItem $InputDir -Recurse -File -Filter "*${Library}_${Format}.spc")
    if(((Inventory $AfterInputs | ConvertTo-Json -Depth 5 -Compress)) -ne $InputFingerprint){throw 'SPC inputs changed during Cook'}
    if((Get-FileHash $SourceExe).Hash -ne $SourceHash){throw 'Source EXE changed during Cook'}
    $Log=Get-Content "$Evidence/cook.log" -Raw
    $LoadLines=@($Log -split '\r?\n' | Where-Object {$_ -match 'Loaded \d+ stable PSOs from .*PCD3D_SM6\.spc'})
    if(!$LoadLines.Count){throw 'No log evidence that SM6 SPC was consumed'}
    foreach($Input in $Inputs){if(!@($LoadLines | Where-Object {$_.Contains($Input.Name)}).Count){throw "SPC not observed in build log: $($Input.Name)"}}
    $LoadedCounts=@($LoadLines | ForEach-Object {
        $Match=[regex]::Match($_,'Loaded (\d+) stable PSOs from (.*)\. (\d+) PSOs rejected, (\d+) PSOs merged')
        if(!$Match.Success){throw 'Unrecognized stable PSO load statistics'}
        [ordered]@{Source=$Match.Groups[2].Value;Loaded=[int]$Match.Groups[1].Value;Rejected=[int]$Match.Groups[3].Value;Merged=[int]$Match.Groups[4].Value}
    })
    $WriteLines=@($Log -split '\r?\n' | Where-Object {$_ -match 'Wrote \d+ binary PSOs' -and $_.Contains($CacheName)})
    if($WriteLines.Count -ne 1){throw 'Expected one SM6 runtime cache write statistic'}
    $Written=[regex]::Match($WriteLines[0],'Wrote (\d+) binary PSOs \(graphics: (\d+) compute: (\d+) RT: (\d+)\)')
    if(!$Written.Success -or [int]$Written.Groups[1].Value -le 0){throw 'Invalid runtime PSO count'}
    $Cooked="$Root/Saved/Cooked/Windows/ActionRoguelike"
    $ContentCache="$Cooked/Content/PipelineCaches/Windows/$CacheName"
    $MetadataCache="$Cooked/Metadata/PipelineCaches/$CacheName"
    foreach($Cache in @($ContentCache,$MetadataCache)) {
        $Item=Get-Item $Cache
        if($Item.Length -eq 0 -or $Item.LastWriteTimeUtc -lt $Start.ToUniversalTime().AddSeconds(-2)){throw "Missing/stale output: $Cache"}
    }
    if((Get-FileHash $ContentCache).Hash -ne (Get-FileHash $MetadataCache).Hash){throw 'Content/Metadata runtime caches differ'}
    New-Item "$Evidence/RuntimeCaches","$Evidence/StableKeys" -ItemType Directory | Out-Null
    Copy-Item -LiteralPath $ContentCache -Destination "$Evidence/RuntimeCaches/$CacheName"
    $Keys=@(Get-ChildItem "$Cooked/Metadata/PipelineCaches" -File -Filter "*${Format}.shk")
    if($Keys.Count -lt 2){throw 'Expected project and Global SM6 stable keys'}
    $Keys | Copy-Item -Destination "$Evidence/StableKeys"
    $Exe="$Package/Windows/ActionRoguelike/Binaries/Win64/ActionRoguelike.exe"
    if((Get-FileHash $Exe).Hash -ne $SourceHash){throw 'Archived EXE does not match built Game'}
    $Paks=@(Get-ChildItem "$Package/Windows/ActionRoguelike/Content/Paks" -File -Filter '*.pak')
    if(!$Paks.Count){throw 'No packaged PAK found'}
    $Listing=''
    foreach($Pak in $Paks){
        $ListPath="$Evidence/$($Pak.Name).list.log"
        & "$Engine/Engine/Binaries/Win64/UnrealPak.exe" $Pak.FullName -List *> $ListPath
        if($LASTEXITCODE -ne 0){throw "UnrealPak listing failed: $($Pak.Name)"}
        $Listing+=Get-Content $ListPath -Raw
    }
    if(!$Listing.Contains($CacheName)){throw 'SM6 runtime cache not found in packaged PAK listing'}
    $LogLines=@($Log -split '\r?\n' | Where-Object {$_ -match 'Loaded .*stable PSOs|Re-deduplicated|Wrote .*binary PSOs|Filtered out|PSOs after sanity|PSOs rejected|Copying the binary PSO'})
    $LogLines | Set-Content "$Evidence/pso-build-summary.log" -Encoding UTF8
    $Acceptance.Valid=$true
    $Acceptance.Seconds=((Get-Date)-$Start).TotalSeconds
    $Acceptance.Package=$Package
    $Acceptance.Executable=$Exe
    $Acceptance.ExeSHA256=$SourceHash
    $Acceptance.SPCConsumed=$LoadLines
    $Acceptance.InputCounts=$LoadedCounts
    $Acceptance.OutputCounts=[ordered]@{Total=[int]$Written.Groups[1].Value;Graphics=[int]$Written.Groups[2].Value;Compute=[int]$Written.Groups[3].Value;RayTracing=[int]$Written.Groups[4].Value}
    $Acceptance.RuntimeCaches=Inventory @(Get-Item "$Evidence/RuntimeCaches/$CacheName")
    $Acceptance.StableKeys=Inventory @(Get-ChildItem "$Evidence/StableKeys" -File)
    $Acceptance.PackagedCacheListed=$true
    $Acceptance.Note='Build acceptance only. Bundled enable/startup mode and cache open/begin/complete still require runtime validation. No driver cache was cleared.'
} catch {
    $Acceptance.Error=$_.Exception.Message
    $Acceptance | ConvertTo-Json -Depth 8 | Set-Content "$Evidence/acceptance.json" -Encoding UTF8
    throw
}
$Acceptance | ConvertTo-Json -Depth 8 | Set-Content "$Evidence/acceptance.json" -Encoding UTF8
@{Evidence=$Evidence;Manifest="$Evidence/acceptance.json";Package=$Package} | ConvertTo-Json | Set-Content "$Root/Saved/PSOBundled/current-build.json" -Encoding UTF8
Write-Output "Bundled build accepted: $Evidence"
