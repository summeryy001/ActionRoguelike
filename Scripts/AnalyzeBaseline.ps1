[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$EvidencePath, [ValidateRange(1,10)][int]$ExpectedPairs=3)
$ErrorActionPreference='Stop'
$EvidencePath=(Resolve-Path $EvidencePath).Path
function Median($Values) {
    $v=@($Values | Sort-Object); $n=$v.Count
    if(!$n){return $null}
    if($n%2){return $v[[int][Math]::Floor($n/2)]}
    return ($v[$n/2-1]+$v[$n/2])/2
}
$runs=@(Get-ChildItem $EvidencePath -Directory | Where-Object {$_.Name -match '^\d+_(Cold|Warm)$'} | ForEach-Object {
    $a=Get-Content (Join-Path $_.FullName 'acceptance.json') -Raw | ConvertFrom-Json
    $m=Get-Content (Join-Path $_.FullName 'manifest.json') -Raw | ConvertFrom-Json
    $log=Get-Content (Join-Path $_.FullName 'game.log') -Raw
    $stats=[regex]::Match($log,'runtimeCreated=(\d+) graphicsHitches=(\d+) computeHitches=(\d+) precachedHitches=(\d+)')
    [pscustomobject]@{Run=$_.Name;Mode=$m.Mode;Profile=$m.Profile;Valid=$a.Valid;ExitCode=$a.ExitCode;
        SuccessfulActions=$a.SuccessfulActions;ReadyWaitSeconds=$a.ReadyWaitSeconds;ReadyGateRequired=$a.ReadyGateRequired;ReadyGatePassed=$a.ReadyGatePassed;ProcessToReadyGateSeconds=$a.ProcessToReadyGateSeconds;Settings=$a.ActualSettings;DriverCacheClearVerified=$a.DriverCacheClearVerified;
        RuntimeCreated=if($stats.Success){[int]$stats.Groups[1].Value}else{$null};
        SlowGraphics=if($stats.Success){[int]$stats.Groups[2].Value}else{$null};
        SlowCompute=if($stats.Success){[int]$stats.Groups[3].Value}else{$null}}
})
if($runs.Count -ne (2*$ExpectedPairs) -or @($runs | Where-Object {!$_.Valid -or $_.ExitCode -ne 0}).Count){throw 'Batch incomplete or failed; inspect acceptance.json before summarizing.'}
if(@($runs | Where-Object {$_.Mode -eq 'Cold'}).Count -ne $ExpectedPairs -or @($runs | Where-Object {$_.Mode -eq 'Warm'}).Count -ne $ExpectedPairs){throw 'Missing Cold/Warm pairs.'}
$frames=Import-Csv (Join-Path $EvidencePath 'skill-frames.csv')
$skills=@($frames | Group-Object Mode,Action | ForEach-Object {
    $g=$_.Group
    [pscustomobject]@{Mode=$g[0].Mode;Action=$g[0].Action;Runs=$g.Count;
        MedianMaxFrameMs=(Median @($g | ForEach-Object {[double]::Parse($_.MaxFrameMs,[Globalization.CultureInfo]::InvariantCulture)}))}
})
if($skills.Count -ne 12 -or @($skills | Where-Object {$_.Runs -ne $ExpectedPairs}).Count){throw 'Incomplete skill windows.'}
[ordered]@{Evidence=$EvidencePath;Runs=$runs;Skills=$skills;
    Metric='Median of per-run maximum Tick DeltaSeconds intersecting the 2-second post-action window; not PSO-only cost.';
    Caveats=@('Driver cache clearing is requested, not proven.','AI/visibility are not fully deterministic.','Process wall duration includes the route and shutdown, not startup.','Slow PSO creates are not hitch frame counts.')
} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $EvidencePath 'summary.json') -Encoding UTF8
$skills | Format-Table -AutoSize
