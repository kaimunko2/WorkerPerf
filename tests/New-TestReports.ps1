param([Parameter(Mandatory = $true)][string]$OutDir)
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
[void](New-TestReports $OutDir)
$OutDir
