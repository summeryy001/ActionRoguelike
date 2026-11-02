[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$EvidencePath,[string]$InsightsExe='F:/UE_Installed/Engine_5.8.x.002/Engine/Binaries/Win64/UnrealInsights.exe')
$ErrorActionPreference='Stop'
$Run=(Resolve-Path $EvidencePath).Path.Replace('\','/')
if($Run -match '\s'){throw 'First version requires an evidence path without spaces'}
$Accepted=Get-Content "$Run/acceptance.json" -Raw | ConvertFrom-Json
if(!$Accepted.Valid){throw 'Runtime acceptance must pass first'}
if(!(Test-Path $InsightsExe) -or !(Test-Path "$Run/capture.utrace")){throw 'Missing Insights or Trace'}
$Command="TimingInsights.ExportTimingEvents $Run/precompile-events.csv -columns=ThreadId,ThreadName,TimerId,TimerName,StartTime,EndTime,Duration,Depth -timers=*Precompile* -startTime=0 -endTime=10"
$ArgsList=@('-NoUI','-AutoQuit',('-OpenTraceFile="'+$Run+'/capture.utrace"'),('-ABSLOG="'+$Run+'/insights-precompile.log"'),('-ExecOnAnalysisCompleteCmd="'+$Command+'"'))
$ArgsList | ConvertTo-Json | Set-Content "$Run/insights-precompile-command.json" -Encoding UTF8
$Process=Start-Process $InsightsExe -ArgumentList $ArgsList -WindowStyle Hidden -PassThru
if(!$Process.WaitForExit(120000)){Stop-Process -Id $Process.Id;throw 'Insights timed out'}
$Process.Refresh()
if($Process.ExitCode -ne 0){throw 'Insights failed'}
# Frame tracks may be exported regardless of timer-name filtering. Select exact CPU scopes.
$Rows=Import-Csv "$Run/precompile-events.csv"
$Graphics=@($Rows | Where-Object {$_.TimerName -ceq 'FShaderPipelineCache::PrecompileGraphics'})
$Compute=@($Rows | Where-Object {$_.TimerName -ceq 'FShaderPipelineCache::PrecompileCompute'})
$Summary=[ordered]@{Valid=($Graphics.Count+$Compute.Count -gt 0);GraphicsScopeCount=$Graphics.Count;ComputeScopeCount=$Compute.Count;ObservedQueued=$Accepted.Queued;ObservedProcessed=$Accepted.Processed;WindowSeconds='0..10';Note='CPU submission scopes are supporting evidence; not unique PSOs, completed driver compiles or a wall-time measurement. Original Trace retains startup bookmarks.'}
$Summary | ConvertTo-Json | Set-Content "$Run/trace-analysis.json" -Encoding UTF8
if(!$Summary.Valid){throw 'Expected precompile CPU scopes not found; inspect Trace manually'}
Write-Output ($Summary | ConvertTo-Json)
