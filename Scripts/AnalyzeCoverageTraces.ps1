[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$EvidencePath,[string]$InsightsExe='F:/UE_Installed/Engine_5.8.x.002/Engine/Binaries/Win64/UnrealInsights.exe')
$ErrorActionPreference='Stop'
$Batch=(Resolve-Path $EvidencePath).Path.Replace('\','/')
if($Batch -match '\s'){throw 'First version requires paths without spaces'}
$Summary=Get-Content "$Batch/summary.json" -Raw|ConvertFrom-Json
if(@($Summary.Probes).Count -ne 2){throw 'Both fixture probes required'}
if(@(Get-Process -ErrorAction SilentlyContinue|Where-Object {$_.ProcessName -match '^(UnrealEditor|ActionRoguelike|Loki)(-|$)'}).Count){throw 'Analyze only after game tests finish'}
$Results=@()
foreach($Run in @($Summary.Runs|Where-Object {$_.Fixture})){
    $Path=$Run.Evidence.Replace('\','/')
    $Command="TimingInsights.ExportTimingEvents $Path/coverage-events.csv -columns=ThreadId,ThreadName,TimerId,TimerName,StartTime,EndTime,Duration,Depth -timers=*PSO*,*PipelineState*,*Precompile* -startTime=0 -endTime=155"
    $ArgsList=@('-NoUI','-AutoQuit',('-OpenTraceFile="'+$Path+'/capture.utrace"'),('-ABSLOG="'+$Path+'/insights-coverage.log"'),('-ExecOnAnalysisCompleteCmd="'+$Command+'"'))
    $ArgsList|ConvertTo-Json|Set-Content "$Path/insights-coverage-command.json" -Encoding UTF8
    $Process=Start-Process $InsightsExe -ArgumentList $ArgsList -WindowStyle Hidden -PassThru
    if(!$Process.WaitForExit(180000)){Stop-Process -Id $Process.Id;throw 'Insights timed out'}
    $Process.Refresh();if($Process.ExitCode -ne 0){throw 'Insights failed'}
    $Rows=Import-Csv "$Path/coverage-events.csv"
    $Tick=$Rows|Where-Object {$_.TimerName -ceq 'RoguePSOValidation'}|Sort-Object {[double]$_.StartTime}|Select-Object -First 1
    if(!$Tick){throw 'No validation Tick for alignment'}
    $Start=[double]$Tick.StartTime+52;$End=[double]$Tick.StartTime+136
    $Events=@($Rows|Where-Object {$_.TimerName -match '^FD3D12DynamicRHI::RHICreate(Graphics|Compute)PipelineState$' -and [double]$_.StartTime -ge $Start -and [double]$_.StartTime -lt $End})
    $Groups=@($Events|Group-Object TimerName|ForEach-Object {
        $Ms=@($_.Group|ForEach-Object {[double]$_.Duration*1000})
        [pscustomobject]@{Timer=$_.Name;Count=$Ms.Count;MaxMs=($Ms|Measure-Object -Maximum).Maximum;Over10ms=@($Ms|Where-Object {$_ -gt 10}).Count;Over50ms=@($Ms|Where-Object {$_ -gt 50}).Count}
    })
    $Results+=[ordered]@{Variant=$Run.Variant;Evidence=$Path;ApproximateWindowStart=$Start;ApproximateWindowEnd=$End;Scopes=$Groups;Note='Approximate alignment from first validation Tick; driver API scopes are not pure compilation CPU time or game-frame duration. One probe per variant.'}
    Write-Output "Analyzed fixture: $($Run.Variant)"
}
$Results|ConvertTo-Json -Depth 8|Set-Content "$Batch/trace-summary.json" -Encoding UTF8
