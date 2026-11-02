[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$EvidencePath,[ValidateRange(1,3)][int]$ExpectedPairs=3)
$ErrorActionPreference='Stop'
$Batch=(Resolve-Path $EvidencePath).Path
function Median($Values){$V=@($Values|Sort-Object);if(!$V.Count){return $null};if($V.Count%2){return $V[[int][Math]::Floor($V.Count/2)]};return ($V[$V.Count/2-1]+$V[$V.Count/2])/2}
function Number($Text){[double]::Parse($Text,[Globalization.CultureInfo]::InvariantCulture)}
$Pairs=@(Get-Content "$Batch/pairs.json" -Raw|ConvertFrom-Json)
$Good=@($Pairs|Where-Object {$_.Valid})
if($Good.Count -ne 4*$ExpectedPairs){throw 'Comparison incomplete'}
$Skills=@();$Runs=@();$Fingerprint=$null
foreach($Profile in @('Baseline','Auto','Bundled','Combined')) {
    $ProfilePairs=@($Good|Where-Object {$_.Profile -eq $Profile})
    if($ProfilePairs.Count -ne $ExpectedPairs){throw "Pair count mismatch: $Profile"}
    foreach($Pair in $ProfilePairs){
        $Package=(Get-Content "$($Pair.Evidence)/package.json" -Raw|ConvertFrom-Json)|ConvertTo-Json -Depth 6 -Compress
        if($null -eq $Fingerprint){$Fingerprint=$Package}elseif($Fingerprint -ne $Package){throw 'Package fingerprint differs across modes/pairs'}
        foreach($Mode in @('Cold','Warm')){
            $Run=Join-Path $Pair.Evidence "01_$Mode"
            $A=Get-Content "$Run/acceptance.json" -Raw|ConvertFrom-Json
            $M=Get-Content "$Run/manifest.json" -Raw|ConvertFrom-Json
            if(!$A.Valid -or $A.ExitCode -ne 0 -or $M.Profile -ne $Profile -or $M.Mode -ne $Mode){throw "Invalid run: $Run"}
            $Log=Get-Content "$Run/game.log" -Raw
            $Stats=[regex]::Match($Log,'runtimeCreated=(\d+) graphicsHitches=(\d+) computeHitches=(\d+) precachedHitches=(\d+)')
            $Runs+=[pscustomobject]@{Profile=$Profile;Pair=$Pair.Pair;Mode=$Mode;Evidence=$Run;ProcessToRouteStartSeconds=$A.ProcessToReadyGateSeconds;BundledQueued=$A.BundledQueued;BundledProcessed=$A.BundledProcessed;BundledWallSeconds=$A.BundledWallSeconds;BundledSubmissionSeconds=$A.BundledSubmissionSeconds;RuntimeCreated=if($Stats.Success){[int]$Stats.Groups[1].Value}else{$null};SlowGraphics=if($Stats.Success){[int]$Stats.Groups[2].Value}else{$null};SlowCompute=if($Stats.Success){[int]$Stats.Groups[3].Value}else{$null};DriverCacheClearVerified=$A.DriverCacheClearVerified}
        }
        foreach($Frame in (Import-Csv "$($Pair.Evidence)/skill-frames.csv")){
            $Skills+=[pscustomobject]@{Profile=$Profile;Pair=$Pair.Pair;Mode=$Frame.Mode;Action=$Frame.Action;MaxFrameMs=(Number $Frame.MaxFrameMs)}
        }
    }
}
$Aggregates=@($Skills|Group-Object Profile,Mode,Action|ForEach-Object {
    $G=$_.Group
    if($G.Count -ne $ExpectedPairs){throw 'Skill group incomplete'}
    [pscustomobject]@{Profile=$G[0].Profile;Mode=$G[0].Mode;Action=$G[0].Action;Runs=$G.Count;MedianMaxFrameMs=(Median @($G.MaxFrameMs));Min=($G.MaxFrameMs|Measure-Object -Minimum).Minimum;Max=($G.MaxFrameMs|Measure-Object -Maximum).Maximum}
})
if($Aggregates.Count -ne 48){throw 'Expected 48 skill aggregates'}
$Startup=@($Runs|Group-Object Profile,Mode|ForEach-Object {
    $G=$_.Group
    [pscustomobject]@{Profile=$G[0].Profile;Mode=$G[0].Mode;MedianProcessToRouteStartSeconds=(Median @($G.ProcessToRouteStartSeconds|Where-Object {$null -ne $_}));MedianBundledWallSeconds=(Median @($G.BundledWallSeconds|Where-Object {$null -ne $_}));MedianSlowGraphics=(Median @($G.SlowGraphics|Where-Object {$null -ne $_}));MedianSlowCompute=(Median @($G.SlowCompute|Where-Object {$null -ne $_}))}
})
$Skills|Export-Csv "$Batch/skill-runs.csv" -NoTypeInformation -Encoding UTF8
$Aggregates|Export-Csv "$Batch/skill-summary.csv" -NoTypeInformation -Encoding UTF8
$Runs|Export-Csv "$Batch/run-summary.csv" -NoTypeInformation -Encoding UTF8
@{Evidence=$Batch;ValidRuns=$Runs.Count;ExcludedAttempts=@($Pairs|Where-Object {!$_.Valid});Runs=$Runs;Skills=$Aggregates;Startup=$Startup;Caveats=@('Driver clearing requested, not proven; engine does not target legacy LocalLow/NVIDIA/DXCache.','Existing fixed-timing route, nearest enemy/visibility/AI not deterministic.','Process-to-route time is not full interactive startup.','Bundled batch duration is not all PSO work; combined mode may overlap Auto tasks.','Frame maxima include all work, not PSO-only time.','Auto/Combined include validation=2 and proxy strategy=1 as tested configuration bundles.','Do not pool excluded attempts into medians.')}|ConvertTo-Json -Depth 9|Set-Content "$Batch/summary.json" -Encoding UTF8
$Aggregates|Where-Object {$_.Mode -eq 'Cold' -and $_.Action -like '*First'}|Format-Table -AutoSize
$Startup|Format-Table -AutoSize
