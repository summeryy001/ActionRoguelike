param([string]$EvidenceRoot)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../Dependencies.ps1"
if(!$EvidenceRoot){$EvidenceRoot=Join-Path $env:TEMP ('PSOWorkbenchTests_'+[guid]::NewGuid().ToString('N'))}
$EvidenceRoot=[IO.Path]::GetFullPath($EvidenceRoot)
$Root=Join-Path $EvidenceRoot 'Fixture';$Job=Join-Path $EvidenceRoot 'Evidence'
New-Item $Root,$Job -ItemType Directory -Force|Out-Null
function HashFile($Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function JsonFile($Value,$Path){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))}
function WriteFixture($Relative,$Text){$Path=Join-Path $Root $Relative;New-Item (Split-Path $Path) -ItemType Directory -Force|Out-Null;[IO.File]::WriteAllText($Path,$Text);return $Path}
function Entry($Path){return @{path=$Path;sha256=(HashFile $Path)}}
$Project=WriteFixture 'Fixture.uproject' '{}'
$Exe=WriteFixture 'Package/game.exe' 'fixture exe, not runnable'
$Spc=WriteFixture 'Build/Windows/PipelineCaches/PSO_Fixture_PCD3D_SM6.spc' 'fixture spc, not an engine cache'
$Stable=WriteFixture 'Conversion/test.spc' 'fixture converted cache'
$Log=WriteFixture 'Run/game.log' 'complete'
$Csv=WriteFixture 'Analysis/events.csv' 'timer,duration'
$Code=WriteFixture 'Source/Test.cpp' '// original'
$Name='Fixture';$Format='PCD3D_SM6';$StateFile=Join-Path $Job 'state.json'
$R=[pscustomobject]@{ProjectFile=$Project;EngineRoot=$Root;GameTarget='Fixture';Platform=0;CookMaps=@('/Game/A');PrepareScript='';PrepareArguments=@();CaptureMap='/Game/A';MapOptions='';LaunchArguments=@();AutomaticRoute=$true;AutomaticArguments='-FixtureRoute';CompletionMarker='complete';ExpectedActions=2;SuccessPattern='action=ok';OutputArgument='FixtureOutput';CaptureStrategy=0;GroupName='Startup';RuntimeMode=2;ClearDriverCache=$false;Background=$false;BackgroundBudgetMs=2;InsightsExecutable='insights.exe';AnalysisStartSeconds=1;AnalysisEndSeconds=7}
ValidateOptions
$CurrentSourceStamp=SourceStamp
$State=[pscustomobject]@{captures=@();capturesRevision='r1'}
foreach($Key in @('collector','bundled')){
    if($Key -eq 'bundled'){break}
    $State|Add-Member -NotePropertyName $Key -NotePropertyValue (AddIdentity $Key @{id='build1';keys=@();packageFiles=@((Entry $Exe))})
}
$State.captures=@((AddIdentity 'capture' @{records=@((Entry $Log));valid=$true;build='build1'}))
$State|Add-Member conversion (AddIdentity 'conversion' @{spc=$Stable;sha256=(HashFile $Stable)})
$State|Add-Member installed (AddIdentity 'installed' (Entry $Spc))
$State|Add-Member bundled (AddIdentity 'bundled' @{id='build2';keys=@();packageFiles=@((Entry $Exe));inputs=@((Entry $Spc))})
$State|Add-Member validation (AddIdentity 'validation' @{outputs=@((Entry $Log))})
$State|Add-Member analysis (AddIdentity 'analysis' @{outputs=@((Entry $Csv))})
JsonFile $State $StateFile;$Baseline=[IO.File]::ReadAllText($StateFile)
$Checks=[Collections.Generic.List[string]]::new()
function Assert($Condition,$Message){if(!$Condition){throw $Message};$Checks.Add($Message)}
function ResetState {$script:State=$Baseline|ConvertFrom-Json}
RefreshValidity
Assert (!$State.analysis.staleReason) 'matching serialized graph stays valid'
$R.RuntimeMode=3;RefreshValidity
Assert (!$State.collector.staleReason -and !$State.conversion.staleReason -and $State.validation.staleReason -and $State.analysis.staleReason) 'runtime mode invalidates only validation and analysis'
$R.RuntimeMode=2;ResetState
$State.collector.artifactId='new-build';RefreshValidity
Assert ($State.captures[0].staleReason -and $State.conversion.staleReason -and $State.installed.staleReason -and $State.bundled.staleReason -and $State.validation.staleReason) 'new collector propagates invalidation through graph'
ResetState;$State.capturesRevision='r2';RefreshValidity
Assert ($State.conversion.staleReason -and $State.analysis.staleReason) 'new capture set requires reconversion and downstream rebuild'
ResetState;$State.installed.artifactId='new-install';RefreshValidity
Assert ($State.bundled.staleReason -and $State.analysis.staleReason) 'new install invalidates packaged validation'
ResetState;[IO.File]::WriteAllText($Exe,'changed bytes');RefreshValidity
Assert ($State.collector.staleReason -and $State.analysis.staleReason) 'changed package file rejected even at same path'
[IO.File]::WriteAllText($Exe,'fixture exe, not runnable');ResetState
$Extra=WriteFixture 'Build/Windows/PipelineCaches/Extra_Fixture_PCD3D_SM6.spc' 'extra';RefreshValidity
Assert (!$State.installed.staleReason -and $State.bundled.staleReason) 'additional SPC requires bundled rebuild'
Remove-Item -LiteralPath $Extra;ResetState
$State.collector.PSObject.Properties.Remove('schema');RefreshValidity
Assert ($State.collector.staleReason -and $State.analysis.staleReason) 'legacy success record is not accepted as current'
ResetState;$R.CaptureMap='/Game/B';RefreshValidity
Assert (!$State.collector.staleReason -and $State.captures[0].staleReason -and $State.conversion.staleReason) 'route change invalidates capture without rebuilding unchanged cook inputs'
$R.CaptureMap='/Game/A';ResetState
[IO.File]::WriteAllText($Code,'// changed');$CurrentSourceStamp=SourceStamp;RefreshValidity
Assert ($State.collector.staleReason -and $State.bundled.staleReason) 'source edit requires rebuild'
foreach($Bad in @('-ExecCmds=r.PSOPrecaching 0','-UserDir=elsewhere','-ini:Engine:anything','-clearPSODriverCache','-tracefile=other')){
    $Rejected=$false;try{ValidateExtra $Bad}catch{$Rejected=$true};Assert $Rejected ('reserved argument rejected: '+$Bad)
}
Assert ((QuoteNativeArg 'C:\folder name\') -eq '"C:\folder name\\"') 'native argument quoting preserves spaces and trailing slash'
$R.AnalysisEndSeconds=0;$Rejected=$false;try{ValidateOptions}catch{$Rejected=$true};Assert $Rejected 'invalid analysis interval rejected'
$R.AnalysisEndSeconds=7;$R.SuccessPattern='';$Rejected=$false;try{ValidateOptions}catch{$Rejected=$true};Assert $Rejected 'automatic success count requires project regex'
JsonFile @{fixtureOnly=$true;passed=$Checks.Count;checks=@($Checks)} (Join-Path $Job 'acceptance.json')
Write-Output "Passed $($Checks.Count) dependency/option regression checks. Fixture evidence: $Job"
