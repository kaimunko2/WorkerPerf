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
function Get-ServerTime([string]$Run, [long]$Ms) {
    # Ortszeit des gemessenen Servers zu einem Zeitpunkt (so erwarten -From, -To und -ReportedTime ihre Werte)
    $first = (Get-Content (Join-Path $Run 'ticks.csv') -TotalCount 2)[1].Split(',')[1]
    $offset = [DateTimeOffset]::Parse($first, [cultureinfo]::InvariantCulture).Offset
    [DateTimeOffset]::FromUnixTimeMilliseconds($Ms).ToOffset($offset).DateTime
}
function Copy-SimRun([string]$Run, [string]$OutDir, [string[]]$Without = @()) {
    # Kopie einer Aufzeichnung ohne die genannten Dateien; liefert den neuen Ordner
    $dir = Join-Path $OutDir (Split-Path $Run -Leaf); [void](New-Item -ItemType Directory -Path $dir -Force)
    Get-ChildItem -LiteralPath $Run -File | Where-Object { $Without -notcontains $_.Name -and $_.Name -notlike '*.html' } | Copy-Item -Destination $dir
    $dir
}
function New-SpikeRun([string]$Run, [string]$OutDir) {
    # ruhige Kopie mit zwei kritischen CPU-Takten (unter der Mindestdauer eines Befunds); ohne ICA-Werte, damit der
    # Dauerzustand der Netzstrecke keinen Vorfall bildet
    $dir = Copy-SimRun $Run $OutDir @('citrix.csv'); $file = Join-Path $dir 'ticks.csv'
    $lines = [IO.File]::ReadAllLines($file)
    foreach ($x in @(@(50, '96.5'), @(51, '93.1'))) {
        $at = [array]::FindIndex($lines, [Predicate[string]] { param($l) $l.StartsWith("$($x[0]),") }); $f = $lines[$at].Split(','); $f[3] = $x[1]; $lines[$at] = $f -join ','
    }
    [IO.File]::WriteAllLines($file, $lines); $dir
}
function New-TestReports([string]$OutDir) {
    [void](New-Item -ItemType Directory -Path $OutDir -Force)
    $run = Invoke-SimCapture (Join-Path $OutDir 'capture')
    $report = Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1'; $roles = New-SimRoleFile (Join-Path $OutDir 'roles.sim.json')
    $cpu = @(Get-Content (Join-Path $run 'expected.json') -Raw | ConvertFrom-Json) | Where-Object Key -eq 'cpu'
    $startMs = $cpu.StartMs - 300000
    $r = @{ Run = $run; StartMs = $startMs; Report = (Join-Path $OutDir 'report.html'); Focus = (Join-Path $OutDir 'report-focus.html'); None = (Join-Path $OutDir 'report-none.html')
            Spike = (Join-Path $OutDir 'report-spike.html'); NoData = (Join-Path $OutDir 'report-nodata.html'); CutRep = (Join-Path $OutDir 'report-cutrep.html') }
    # a cut that starts 10 min after the first event of the capture, with a reported time 1 min after that event: the reported
    # time lies inside the capture but before the cut, and events lie around it
    $firstEv = [DateTimeOffset]::Parse((Get-Content (Join-Path $run 'events.csv') -TotalCount 2)[1].Split(',')[0], [cultureinfo]::InvariantCulture).ToUnixTimeMilliseconds()
    [void](& $report -Path $run -OutFile $r.CutRep -RoleFile $roles -From (Get-ServerTime $run ($firstEv + 600000)) -ReportedTime (Get-ServerTime $run ($firstEv + 60000)) 6>$null)
    $reported = [DateTimeOffset]::FromUnixTimeMilliseconds($startMs + 330000).LocalDateTime
    [void](& $report -Path $run -OutFile $r.Report -RoleFile $roles 6>$null)
    [void](& $report -Path $run -OutFile $r.Focus -RoleFile $roles -FocusUser 'user003' -ReportedTime $reported 6>$null)
    # ohne Ereignisse: der Bericht ohne Befund zeigte sonst die Ereignisvorfaelle der Simulation
    $quiet = Copy-SimRun $run (Join-Path $OutDir 'none') @('events.csv', 'events_before.csv')
    [void](& $report -Path $quiet -OutFile $r.None -RoleFile $roles -ThresholdFile (New-NoFindingThresholdFile (Join-Path $OutDir 'none.json')) 6>$null)
    # die ersten dreieinhalb ruhigen Minuten mit zwei kritischen CPU-Takten: kein Vorfall, aber einzelne Ueberschreitungen
    $spike = New-SpikeRun $run (Join-Path $OutDir 'spike')
    [void](& $report -Path $spike -OutFile $r.Spike -RoleFile $roles -To (Get-ServerTime $run ($startMs + 208000)) 6>$null)
    # der CPU-Engpass ohne Prozessdaten und ohne Eingabeverzoegerung je Sitzung
    $bare = Copy-SimRun $run (Join-Path $OutDir 'nodata') @('processes.csv', 'inputdelay.csv')
    [void](& $report -Path $bare -OutFile $r.NoData -RoleFile $roles -From (Get-ServerTime $run ($cpu.StartMs - 60000)) -To (Get-ServerTime $run ($cpu.EndMs + 60000)) 6>$null)
    $r
}
function New-PatchedSource([string]$OutDir, [string]$Overrides) {
    # Kopie von src, deren Simulationsquelle am Ende zusaetzlichen Code erhaelt (Funktionen der Quelle ersetzen oder
    # umhuellen, damit sie Fehler werfen); liefert den Pfad des kopierten Start-WorkerPerfCapture.ps1
    [void](New-Item -ItemType Directory -Path $OutDir -Force)
    Copy-Item (Join-Path $PSScriptRoot '../src/*') $OutDir
    [IO.File]::AppendAllText((Join-Path $OutDir 'WorkerPerf.Sources.Simulation.ps1'), "`n" + $Overrides + "`n")
    Join-Path $OutDir 'Start-WorkerPerfCapture.ps1'
}
