[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$EvidencePath,[ValidateRange(1,3)][int]$Repeats=3)
$ErrorActionPreference='Stop'
$Batch=(Resolve-Path $EvidencePath).Path
$Records=@(Get-Content "$Batch/runs.json" -Raw|ConvertFrom-Json)
if($Records.Count -ne 4*$Repeats+2 -or @($Records|Where-Object {!$_.Valid}).Count){throw 'Incomplete iteration'}
function Median($Values){$V=@($Values|Sort-Object);if($V.Count%2){return $V[[int][Math]::Floor($V.Count/2)]};return ($V[$V.Count/2-1]+$V[$V.Count/2])/2}
$Rows=@();$Runs=@();$Probes=@()
foreach($Record in $Records){
    $Run="$($Record.Evidence)/01_Cold"
    $A=Get-Content "$Run/acceptance.json" -Raw|ConvertFrom-Json
    if(!$A.Valid -or $A.ExitCode -ne 0){throw "Invalid run: $Run"}
    $Log=Get-Content "$Run/game.log" -Raw
    $Runs+=[pscustomobject]@{Variant=$Record.Variant;Profile=$Record.Profile;Repeat=$Record.Repeat;Fixture=$Record.Fixture;Evidence=$Run;ProcessToRouteSeconds=$A.ProcessToReadyGateSeconds;BundledQueued=$A.BundledQueued;BundledProcessed=$A.BundledProcessed;BundledWallSeconds=$A.BundledWallSeconds}
    if($Record.Fixture){
        if(!$Log.Contains('PSOCoverage complete effects=20 expected=20')){throw 'Incomplete fixture route'}
        $Ms=@(Import-Csv "$Run/frames.csv"|Where-Object {[double]$_.ElapsedSeconds -ge 52 -and [double]$_.ElapsedSeconds -le 136}|ForEach-Object {[double]$_.FrameMs}|Sort-Object)
        if(!$Ms.Count){throw 'No fixture frame samples'}
        $Probes+=[pscustomobject]@{Variant=$Record.Variant;Samples=$Ms.Count;MaxFrameMs=$Ms[-1];P95FrameMs=$Ms[[int][Math]::Floor(($Ms.Count-1)*0.95)];Over33ms=@($Ms|Where-Object {$_ -gt 33.33}).Count;Over50ms=@($Ms|Where-Object {$_ -gt 50}).Count;Note='One diagnostic route; includes synchronous loads, FX simulation and camera changes, not PSO-only cost'}
    }else{
        foreach($Row in (Import-Csv "$($Record.Evidence)/skill-frames.csv")){
            $Rows+=[pscustomobject]@{Variant=$Record.Variant;Profile=$Record.Profile;Repeat=$Record.Repeat;Action=$Row.Action;MaxFrameMs=[double]$Row.MaxFrameMs}
        }
    }
}
$Skills=@($Rows|Group-Object Variant,Profile,Action|ForEach-Object {
    if($_.Count -ne $Repeats){throw 'Incomplete skill group'}
    $G=$_.Group
    [pscustomobject]@{Variant=$G[0].Variant;Profile=$G[0].Profile;Action=$G[0].Action;MedianMaxFrameMs=(Median $G.MaxFrameMs);Min=($G.MaxFrameMs|Measure-Object -Minimum).Minimum;Max=($G.MaxFrameMs|Measure-Object -Maximum).Maximum}
})
$Timing=@($Runs|Where-Object {!$_.Fixture}|Group-Object Variant,Profile|ForEach-Object {
    $G=$_.Group
    [pscustomobject]@{Variant=$G[0].Variant;Profile=$G[0].Profile;MedianProcessToRouteSeconds=(Median $G.ProcessToRouteSeconds);MedianBundledWallSeconds=(Median $G.BundledWallSeconds);Queued=$G[0].BundledQueued}
})
$Rows|Export-Csv "$Batch/skill-runs.csv" -NoTypeInformation -Encoding UTF8
@{Runs=$Runs;Skills=$Skills;Timing=$Timing;Probes=$Probes;Caveats=@('Cold clearing requested, not proven','Single fixture probe per variant; diagnostic only','Assets/EXE matched across variants, PAK differs due cache','No extra quality modes or arbitrary PSO count target')}|ConvertTo-Json -Depth 8|Set-Content "$Batch/summary.json" -Encoding UTF8
$Skills|Where-Object {$_.Action -like '*First'}|Format-Table -AutoSize
$Timing|Format-Table -AutoSize
$Probes|Format-Table -AutoSize
