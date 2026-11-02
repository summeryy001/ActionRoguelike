[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Request)
$Request=(Resolve-Path -LiteralPath $Request).Path
$Job=Split-Path $Request
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot/PSOWorkbench.ps1" -Request $Request *> "$Job/launcher.log"
exit $LASTEXITCODE
