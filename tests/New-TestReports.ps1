param([Parameter(Mandatory = $true)][string]$OutDir)
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
$r = New-TestReports $OutDir
[void](New-SkipReports $OutDir)
# Groesse des Servers: der Bericht der Szenen der Ursachen und der Bericht einer aelteren Aufzeichnung (ohne die neuen Werte)
$roles = Join-Path $OutDir 'roles.sim.json'
[void](New-CausesReport $OutDir $roles)
$old = New-OldCaptureCopy $r.Run (Join-Path $OutDir 'old')
[void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $old -OutFile (Join-Path $OutDir 'report-old.html') -RoleFile $roles 6>$null)
$OutDir
