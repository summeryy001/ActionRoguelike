[CmdletBinding()]
param([switch]$Execute,[ValidateRange(1,3)][int]$Pairs=3)
$ErrorActionPreference='Stop'
$Root=(Resolve-Path "$PSScriptRoot/..").Path
$Pointer=Get-Content "$Root/Saved/PSOBundled/current-build.json" -Raw | ConvertFrom-Json
$Build=Get-Content $Pointer.Manifest -Raw | ConvertFrom-Json
if(!$Build.Valid){throw 'Accepted stage 4 build required'}
$Package="$($Build.Package)/Windows"
$Stream=[IO.File]::OpenRead($Build.Executable);$Hasher=[Security.Cryptography.SHA256]::Create()
try {$ExeHash=([BitConverter]::ToString($Hasher.ComputeHash($Stream))).Replace('-','')}finally{$Stream.Dispose();$Hasher.Dispose()}
if($ExeHash -ne $Build.ExeSHA256){throw 'EXE differs from accepted build'}
$Batch="$Root/Saved/PSOComparison/"+(Get-Date -Format 'yyyyMMdd_HHmmss')+'_'+[guid]::NewGuid().ToString('N').Substring(0,6)
New-Item $Batch -ItemType Directory -Force | Out-Null
@{Execute=[bool]$Execute;Pairs=$Pairs;BuildManifest=$Pointer.Manifest;ProjectRevision=(& git -C $Root rev-parse HEAD);Package=$Package;Route='Fixed timing, direct TestLevel, no readiness gate';Order='Rotate profile order by repetition; Cold immediately followed by Warm';ColdCache='Engine clearPSODriverCache requested, success not independently proven';Retry='At most 3 attempts per pair; only action-start failures with exit 0; preserve all attempts and rerun the entire cold/warm pair'} | ConvertTo-Json -Depth 5 | Set-Content "$Batch/manifest.json" -Encoding UTF8
Write-Output "Comparison: $Batch"
$Profiles=@('Baseline','Auto','Bundled','Combined')
$Records=@()
for($Pair=1;$Pair -le $Pairs;$Pair++) {
    for($Index=0;$Index -lt 4;$Index++) {
        $Profile=$Profiles[($Index+$Pair-1)%4]
        for($Attempt=1;$Attempt -le 3;$Attempt++) {
            $Start=Get-Date
            try {
                & "$PSScriptRoot/RunComparisonPair.ps1" -Execute:$Execute -Profile $Profile -PackageRoot $Package -OutputRoot $Batch
                $Latest=Get-Content "$Batch/last-pair.json" -Raw | ConvertFrom-Json
                if($Execute){& "$PSScriptRoot/AnalyzeBaseline.ps1" -EvidencePath $Latest.Evidence -ExpectedPairs 1}
                $Records+=@{Pair=$Pair;Profile=$Profile;Attempt=$Attempt;Valid=[bool]$Execute;Evidence=$Latest.Evidence}
                $Records | ConvertTo-Json -Depth 5 | Set-Content "$Batch/pairs.json" -Encoding UTF8
                Write-Output "Completed repetition=$Pair profile=$Profile attempt=$Attempt"
                break
            } catch {
                $Failed=Get-ChildItem $Batch -Directory | Where-Object {$_.Name -like "$Profile*" -and $_.LastWriteTime -ge $Start.AddSeconds(-2)} | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                $Acceptance=if($Failed){@(Get-ChildItem $Failed.FullName -Recurse -Filter acceptance.json | ForEach-Object {Get-Content $_.FullName -Raw | ConvertFrom-Json})}else{@()}
                $Records+=@{Pair=$Pair;Profile=$Profile;Attempt=$Attempt;Valid=$false;Evidence=$Failed.FullName;Error=$_.Exception.Message}
                $Records | ConvertTo-Json -Depth 5 | Set-Content "$Batch/pairs.json" -Encoding UTF8
                $Bad=@($Acceptance | Where-Object {!$_.Valid})
                $SeriousLog=if($Failed){@(Get-ChildItem $Failed.FullName -Recurse -Filter game.log | Where-Object {(Get-Content $_.FullName -Raw) -match 'Ensure condition failed|Fatal error:|Assertion failed:'}).Count -gt 0}else{$true}
                if($Attempt -eq 3 -or !$Bad.Count -or $SeriousLog -or @($Bad | Where-Object {$_.ExitCode -ne 0 -or $_.SuccessfulActions -ge 6 -or !$_.BundledCheck}).Count){throw}
                Write-Output "Retry entire pair after action-start failure: $Profile repetition=$Pair"
            }
        }
    }
}
Write-Output "Comparison finished: $Batch"
