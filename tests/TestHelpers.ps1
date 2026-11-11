# tests/TestHelpers.ps1
function Invoke-SimCapture([string]$OutDir) {
    # 60 Minuten Simulation unter deutscher Kultur; liefert den Aufzeichnungsordner
    [cultureinfo]::CurrentCulture = [cultureinfo]'de-DE'
    $capture = Join-Path $PSScriptRoot '../src/Start-WorkerPerfCapture.ps1'
    (& $capture -Simulate -DurationMinutes 60 -OutputPath $OutDir 6>$null) | Select-Object -Last 1
}
function Get-ReportData([string]$Html) {
    $text = [IO.File]::ReadAllText($Html); $open = '<script id="wp-data" type="application/json">'
    $a = $text.IndexOf($open) + $open.Length
    $text.Substring($a, $text.IndexOf('</script>', $a) - $a) | ConvertFrom-Json
}
function New-SimRoleFile([string]$Path) {
    $r = Get-Content (Join-Path $PSScriptRoot '../src/roles.json') -Raw | ConvertFrom-Json
    ($r.roles | Where-Object label -eq 'Nexus KIS').processes = @('nexus.exe')
    [IO.File]::WriteAllText($Path, ($r | ConvertTo-Json -Depth 6)); $Path
}
function New-NoFindingThresholdFile([string]$Path) {
    $t = Get-Content (Join-Path $PSScriptRoot '../src/thresholds.json') -Raw | ConvertFrom-Json
    foreach ($e in $t.thresholds) { $e.warn = 1e9; $e.crit = 1e9 }
    [IO.File]::WriteAllText($Path, ($t | ConvertTo-Json -Depth 6)); $Path
}
function New-TestReports([string]$OutDir) {
    [void](New-Item -ItemType Directory -Path $OutDir -Force)
    $run = Invoke-SimCapture (Join-Path $OutDir 'capture')
    $report = Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1'; $roles = New-SimRoleFile (Join-Path $OutDir 'roles.sim.json')
    $startMs = (@(Get-Content (Join-Path $run 'expected.json') -Raw | ConvertFrom-Json) | Where-Object Key -eq 'cpu').StartMs - 300000
    $r = @{ Run = $run; StartMs = $startMs; Report = (Join-Path $OutDir 'report.html'); Focus = (Join-Path $OutDir 'report-focus.html'); None = (Join-Path $OutDir 'report-none.html') }
    $reported = [DateTimeOffset]::FromUnixTimeMilliseconds($startMs + 330000).LocalDateTime
    [void](& $report -Path $run -OutFile $r.Report -RoleFile $roles 6>$null)
    [void](& $report -Path $run -OutFile $r.Focus -RoleFile $roles -FocusUser 'user003' -ReportedTime $reported 6>$null)
    [void](& $report -Path $run -OutFile $r.None -RoleFile $roles -ThresholdFile (New-NoFindingThresholdFile (Join-Path $OutDir 'none.json')) 6>$null)
    $r
}
