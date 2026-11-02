[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$EvidencePath,[string]$InsightsExe='F:/UE_Installed/Engine_5.8.x.002/Engine/Binaries/Win64/UnrealInsights.exe')
$ErrorActionPreference='Stop'
$Batch=(Resolve-Path $EvidencePath).Path.Replace('\','/')
if($Batch -match '\s'){throw 'First version requires an evidence path without spaces'}
$Summary=Get-Content "$Batch/summary.json" -Raw|ConvertFrom-Json
if($Summary.ValidRuns -ne 24){throw 'Complete 24-run summary required'}
if(@(Get-Process -ErrorAction SilentlyContinue|Where-Object {$_.ProcessName -match '^(UnrealEditor|ActionRoguelike|Loki)(-|$)'}).Count){throw 'Analyze after all game tests finish'}
$Skills=Import-Csv "$Batch/skill-runs.csv"
$Reports=@()
foreach($Profile in @('Baseline','Auto','Bundled','Combined')){
    $Median=($Summary.Skills|Where-Object {$_.Profile -eq $Profile -and $_.Mode -eq 'Cold' -and $_.Action -eq 'Primary_First'}).MedianMaxFrameMs
    $Chosen=$Skills|Where-Object {$_.Profile -eq $Profile -and $_.Mode -eq 'Cold' -and $_.Action -eq 'Primary_First'}|Sort-Object @{Expression={[Math]::Abs([double]$_.MaxFrameMs-$Median)}}|Select-Object -First 1
    $Run=($Summary.Runs|Where-Object {$_.Profile -eq $Profile -and $_.Mode -eq 'Cold' -and $_.Pair -eq $Chosen.Pair}).Evidence.Replace('\','/')
    $Command="TimingInsights.ExportTimingEvents $Run/comparison-events.csv -columns=ThreadId,ThreadName,TimerId,TimerName,StartTime,EndTime,Duration,Depth -timers=*PSO*,*PipelineState*,*Precompile* -startTime=0 -endTime=15"
    $ArgsList=@('-NoUI','-AutoQuit',('-OpenTraceFile="'+$Run+'/capture.utrace"'),('-ABSLOG="'+$Run+'/insights-comparison.log"'),('-ExecOnAnalysisCompleteCmd="'+$Command+'"'))
    $ArgsList|ConvertTo-Json|Set-Content "$Run/insights-comparison-command.json" -Encoding UTF8
    $Process=Start-Process $InsightsExe -ArgumentList $ArgsList -WindowStyle Hidden -PassThru
    if(!$Process.WaitForExit(120000)){Stop-Process -Id $Process.Id;throw 'Insights analysis timed out'}
    $Process.Refresh();if($Process.ExitCode -ne 0){throw "Insights failed: $Profile"}
    $Rows=Import-Csv "$Run/comparison-events.csv"
    $Events=@($Rows|Where-Object {$_.TimerName -ceq 'PSOPrecache: Unknown' -or $_.TimerName -match '^FShaderPipelineCache::Precompile|RHICreate(Graphics|Compute)PipelineState'})
    if(!$Events.Count){throw "No PSO scopes: $Profile"}
    $Groups=@($Events|Group-Object TimerName|ForEach-Object {
        $Durations=@($_.Group|ForEach-Object {[double]::Parse($_.Duration,[Globalization.CultureInfo]::InvariantCulture)*1000})
        [pscustomobject]@{Timer=$_.Name;Count=$_.Count;MaxMs=($Durations|Measure-Object -Maximum).Maximum;SumMs=($Durations|Measure-Object -Sum).Sum}
    })
    $Report=[ordered]@{Profile=$Profile;Pair=[int]$Chosen.Pair;Evidence=$Run;ChosenFirstSkillMaxFrameMs=[double]$Chosen.MaxFrameMs;WindowSeconds='0..15';ScopeStats=$Groups;Note='Representative cold run selected by median first-primary frame. Startup and first actions share export window. Sums include nested/parallel scopes and are not elapsed time; Unknown is not proof of a missed bundled entry.'}
    $Report|ConvertTo-Json -Depth 7|Set-Content "$Run/comparison-trace-analysis.json" -Encoding UTF8
    $Reports+=$Report
    Write-Output "Insights analyzed: $Profile pair=$($Chosen.Pair)"
}
$Reports|ConvertTo-Json -Depth 8|Set-Content "$Batch/trace-summary.json" -Encoding UTF8
