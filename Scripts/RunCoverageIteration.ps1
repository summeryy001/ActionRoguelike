[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ControlManifest,[Parameter(Mandatory=$true)][string]$CandidateManifest,[switch]$Execute,[ValidateRange(1,3)][int]$Repeats=3)
$ErrorActionPreference='Stop'
$Root=(Resolve-Path "$PSScriptRoot/..").Path
$Control=Get-Content $ControlManifest -Raw|ConvertFrom-Json
$Candidate=Get-Content $CandidateManifest -Raw|ConvertFrom-Json
if(!$Control.Valid -or !$Candidate.Valid -or $Control.ExeSHA256 -ne $Candidate.ExeSHA256){throw 'Accepted builds with identical EXE required'}
if($Candidate.OutputCounts.Total -le $Control.OutputCounts.Total){throw 'Candidate did not expand runtime PSO count'}
function DataInventory($Build){@(Get-ChildItem "$($Build.Package)/Windows/ActionRoguelike/Content/Paks" -File|Where-Object {$_.Extension -in @('.ucas','.utoc')}|Sort-Object Name|ForEach-Object {[ordered]@{Name=$_.Name;SHA256=(Get-FileHash $_.FullName).Hash}})}
$ControlData=DataInventory $Control;$CandidateData=DataInventory $Candidate
if(($ControlData|ConvertTo-Json -Compress) -ne ($CandidateData|ConvertTo-Json -Compress)){throw 'Cooked resource containers differ; investigate before comparing'}
$Batch="$Root/Saved/PSOCoverage/Comparisons/"+(Get-Date -Format 'yyyyMMdd_HHmmss')+'_'+[guid]::NewGuid().ToString('N').Substring(0,6)
New-Item $Batch -ItemType Directory -Force|Out-Null
@{ControlManifest=$ControlManifest;CandidateManifest=$CandidateManifest;CommonExeSHA256=$Control.ExeSHA256;DataContainers=$ControlData;Repeats=$Repeats;Execute=[bool]$Execute;Design='Two variants, Bundled/Combined, cold requests only; fixed route. One diagnostic expanded fixture run per variant, Bundled only.'}|ConvertTo-Json -Depth 7|Set-Content "$Batch/manifest.json" -Encoding UTF8
$Records=@()
for($Repeat=1;$Repeat -le $Repeats;$Repeat++){
    $Variants=if($Repeat%2){@('Control','Expanded')}else{@('Expanded','Control')}
    foreach($Variant in $Variants){
        $Build=if($Variant -eq 'Control'){$Control}else{$Candidate}
        foreach($Profile in @('Bundled','Combined')){
            $OutputRoot="$Batch/${Variant}_${Profile}_$Repeat"
            & "$PSScriptRoot/RunComparisonPair.ps1" -Execute:$Execute -Profile $Profile -PackageRoot "$($Build.Package)/Windows" -OutputRoot $OutputRoot -ColdOnly
            $Last=Get-Content "$OutputRoot/last-pair.json" -Raw|ConvertFrom-Json
            $Records+=@{Variant=$Variant;Profile=$Profile;Repeat=$Repeat;Fixture=$false;Evidence=$Last.Evidence;Valid=[bool]$Execute}
            $Records|ConvertTo-Json -Depth 6|Set-Content "$Batch/runs.json" -Encoding UTF8
            Write-Output "Completed $Variant $Profile repetition=$Repeat"
        }
    }
}
foreach($Variant in @('Control','Expanded')){
    $Build=if($Variant -eq 'Control'){$Control}else{$Candidate}
    $OutputRoot="$Batch/${Variant}_CoverageProbe"
    & "$PSScriptRoot/RunComparisonPair.ps1" -Execute:$Execute -Profile Bundled -PackageRoot "$($Build.Package)/Windows" -OutputRoot $OutputRoot -ColdOnly -Coverage
    $Last=Get-Content "$OutputRoot/last-pair.json" -Raw|ConvertFrom-Json
    $Records+=@{Variant=$Variant;Profile='Bundled';Repeat=1;Fixture=$true;Evidence=$Last.Evidence;Valid=[bool]$Execute}
    $Records|ConvertTo-Json -Depth 6|Set-Content "$Batch/runs.json" -Encoding UTF8
}
Write-Output "Coverage iteration: $Batch"
