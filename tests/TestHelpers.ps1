# tests/TestHelpers.ps1
function Invoke-SimCapture([string]$OutDir, [hashtable]$Extra = @{}, [string]$ConsoleFile = '') {
    # 60 Minuten Simulation unter deutscher Kultur; $Extra geht an den Collector (etwa @{ Skip = @('Prozesse') }); mit
    # $ConsoleFile landet die Konsolenausgabe (Write-Host) in dieser Datei; liefert den Aufzeichnungsordner
    [cultureinfo]::CurrentCulture = [cultureinfo]'de-DE'
    $capture = Join-Path $PSScriptRoot '../src/Start-WorkerPerfCapture.ps1'
    if (-not $ConsoleFile) { (& $capture -Simulate -DurationMinutes 60 -OutputPath $OutDir @Extra 6>$null) | Select-Object -Last 1 }
    else {
        $out = @(& $capture -Simulate -DurationMinutes 60 -OutputPath $OutDir @Extra 6>&1)
        [IO.File]::WriteAllText($ConsoleFile, ($out | Out-String))
        [string]$out[-1]
    }
}
function New-SkipRuns([string]$OutDir) {
    # Je eine simulierte Stunde: Voll (ohne -Skip), je Kategorie -Skip <Name> (Zustand: -Skip Zustand), Alle (die acht
    # Kategorien); Name -> Aufzeichnungsordner.
    # Die Konsolenausgabe des vollen Laufs steht in <OutDir>/Voll.console.txt (neben den Aufzeichnungen). Der Lauf
    # Prozesse hat dazu -IncludeCommandLine (ohne Prozesse ohne Wirkung), seine Konsolenausgabe in <OutDir>/Prozesse.console.txt.
    $names = @('Prozesse', 'Laufwerke', 'Citrix', 'Ereignisse', 'Rueckblick', 'Drucken', 'Gegenstellen', 'Zustand')
    [void](New-Item -ItemType Directory -Path $OutDir -Force)
    $runs = [ordered]@{ Voll = (Invoke-SimCapture (Join-Path $OutDir 'Voll') @{} (Join-Path $OutDir 'Voll.console.txt')) }
    foreach ($n in $names) {
        if ($n -eq 'Prozesse') { $runs[$n] = Invoke-SimCapture (Join-Path $OutDir $n) @{ Skip = @($n); IncludeCommandLine = $true } (Join-Path $OutDir 'Prozesse.console.txt') }
        else { $runs[$n] = Invoke-SimCapture (Join-Path $OutDir $n) @{ Skip = @($n) } }
    }
    $runs['Alle'] = Invoke-SimCapture (Join-Path $OutDir 'Alle') @{ Skip = $names }
    $runs
}
function New-SkipReports([string]$OutDir) {
    # Die Aufzeichnungen von New-SkipRuns (unter <OutDir>/skip) mit je einem Bericht <OutDir>/report-skip-<name>.html
    # (Rollendatei <OutDir>/roles.sim.json), dazu Alle mit -Mask Alles; Name -> @{ Run; Report }, zusaetzlich AlleMasked,
    # NoneEreignisse, NoneAlle, FocusEreignisse, FocusProzesse und Odd (siehe unten).
    [void](New-Item -ItemType Directory -Path $OutDir -Force)
    $runs = New-SkipRuns (Join-Path $OutDir 'skip')
    $report = Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1'; $roles = New-SimRoleFile (Join-Path $OutDir 'roles.sim.json')
    $out = [ordered]@{}
    foreach ($k in @($runs.Keys)) {
        $file = Join-Path $OutDir ('report-skip-{0}.html' -f $k.ToLowerInvariant())
        [void](& $report -Path $runs[$k] -OutFile $file -RoleFile $roles 6>$null)
        $out[$k] = @{ Run = $runs[$k]; Report = $file }
    }
    $masked = Join-Path $OutDir 'report-skip-alle-masked.html'
    [void](& $report -Path $runs['Alle'] -OutFile $masked -RoleFile $roles -Mask Alles 6>$null)
    $out['AlleMasked'] = @{ Run = $runs['Alle']; Report = $masked }
    # ohne Befund (Schwellen wie report-none.html): ohne Ereignisse und ohne alle acht; mit gemeldetem Benutzer user008
    # (zwei Vorfaelle im vollen Lauf) ohne Ereignisse und ohne Prozesse
    $none = New-NoFindingThresholdFile (Join-Path $OutDir 'none.skip.json')
    foreach ($k in 'Ereignisse', 'Alle') {
        $file = Join-Path $OutDir ('report-skip-none-{0}.html' -f $k.ToLowerInvariant())
        [void](& $report -Path $runs[$k] -OutFile $file -RoleFile $roles -ThresholdFile $none 6>$null)
        $out["None$k"] = @{ Run = $runs[$k]; Report = $file }
    }
    foreach ($k in 'Ereignisse', 'Prozesse') {
        $file = Join-Path $OutDir ('report-skip-focus-{0}.html' -f $k.ToLowerInvariant())
        [void](& $report -Path $runs[$k] -OutFile $file -RoleFile $roles -FocusUser 'user008' 6>$null)
        $out["Focus$k"] = @{ Run = $runs[$k]; Report = $file }
    }
    # eine von Hand geaenderte Aufzeichnung: der volle Lauf mit "Skip": "Prozesse" (die Dateien der Prozesse sind da)
    $odd = Copy-SimRun $runs['Voll'] (Join-Path $OutDir 'skip-odd'); $mf = Join-Path $odd 'meta.json'
    [IO.File]::WriteAllText($mf, ([IO.File]::ReadAllText($mf) -replace '(?s)"Skip":\s*\[\s*\]', '"Skip": "Prozesse"'))
    $file = Join-Path $OutDir 'report-skip-odd.html'
    [void](& $report -Path $odd -OutFile $file -RoleFile $roles 6>$null)
    $out['Odd'] = @{ Run = $odd; Report = $file }
    $out
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
function New-CausesReport([string]$OutDir, [string]$RoleFile) {
    # Die Szenen der Ursachen (Groesse des Servers): je Ursache eines Engpasses ein Vorfall mit seiner Einordnung, und ihr
    # Bericht report-causes.html; liefert @{ Run; Report }. Nicht Teil von New-TestReports: die Pruefungen ueber alle
    # Testberichte (Reihung der Anleitung, P3-R75) behalten ihren Umfang.
    [void](New-Item -ItemType Directory -Path $OutDir -Force)
    $run = Invoke-SimCapture (Join-Path $OutDir 'causes') @{ SimulateScenario = 'Ursachen' }
    $out = Join-Path $OutDir 'report-causes.html'
    [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $run -OutFile $out -RoleFile $RoleFile 6>$null)
    @{ Run = [string]$run; Report = $out }
}
function New-SizingRuns([string]$OutDir) {
    # Fuenf simulierte Arbeitstage desselben Servers (Drehbuch Tag, Tag 1 bis 5) und ein Schnelllauf; alle SIM-VDA01
    $days = @(1..5 | ForEach-Object { [string](Invoke-SimCapture $OutDir @{ SimulateScenario = 'Tag'; SimulateDay = $_ }) })
    [ordered]@{ Days = [string[]]$days; Quick = [string](Invoke-SimHealthOnly (Join-Path $OutDir 'quick')) }
}
function New-SizingReports([string]$OutDir) {
    # Groessenberichte aus den fuenf Tagen und dem Schnelllauf: sizing.html, sizing-masked.html (-Mask Alles),
    # sizing-personen.html (-Mask Personen), sizing-enough.html (Katalog mit minRecordings 1 und minMainHours 0.1);
    # liefert @{ Runs; Report; Masked; MaskedP; Enough }
    [void](New-Item -ItemType Directory -Path $OutDir -Force)
    $runs = New-SizingRuns (Join-Path $OutDir 'runs')
    $script = Join-Path $PSScriptRoot '../src/New-WorkerPerfSizingReport.ps1'; $roles = New-SimRoleFile (Join-Path $OutDir 'roles.sim.json')
    $all = [string[]](@($runs.Days) + @($runs.Quick))
    $r = @{ Runs = $runs; Report = (Join-Path $OutDir 'sizing.html'); Masked = (Join-Path $OutDir 'sizing-masked.html'); MaskedP = (Join-Path $OutDir 'sizing-personen.html')
            Enough = (Join-Path $OutDir 'sizing-enough.html'); Roles = $roles }
    [void](& $script -Path $all -OutFile $r.Report -RoleFile $roles 6>$null)
    [void](& $script -Path $all -OutFile $r.Masked -RoleFile $roles -Mask Alles 6>$null)
    [void](& $script -Path $all -OutFile $r.MaskedP -RoleFile $roles -Mask Personen 6>$null)
    $cat = Join-Path $OutDir 'sizing-enough.json'
    $j = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../src/sizing.de.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
    $j.thresholds.minRecordings.value = 1; $j.thresholds.minMainHours.value = 0.1
    [IO.File]::WriteAllText($cat, ($j | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding $false))
    [void](& $script -Path $all -OutFile $r.Enough -RoleFile $roles -SizingFile $cat 6>$null)
    $r
}
function Get-StringFieldPaths($Value) {
    # jeder Pfad gelesener Berichtsdaten (Get-ReportData), der einen Text haelt; Listenebenen als []
    $out = New-Object System.Collections.Generic.List[string]
    $walk = { param($v, [string]$p)
        if ($null -eq $v -or $v -is [ValueType]) { return }
        if ($v -is [string]) { if (-not $out.Contains($p)) { $out.Add($p) }; return }
        if ($v -is [System.Management.Automation.PSCustomObject]) { foreach ($m in $v.PSObject.Properties) { & $walk $m.Value $(if ($p) { "$p.$($m.Name)" } else { [string]$m.Name }) }; return }
        foreach ($x in $v) { & $walk $x "$p[]" } }
    & $walk $Value ''
    $out.ToArray()
}
function New-OldCaptureCopy([string]$Run, [string]$OutDir) {
    # Kopie einer Aufzeichnung, wie ein aelterer Collector sie schrieb: ticks.csv ohne die fuenf Spalten der Groesse
    # (Kopfzeile und Zeilen), meta.json ohne CoreBusyPct und ohne die fuenf Eintraege in Sources; liefert den neuen Ordner
    $dir = Copy-SimRun $Run $OutDir
    $tf = Join-Path $dir 'ticks.csv'
    $lines = [IO.File]::ReadAllLines($tf)
    $keep = $lines[0].Split(',').Count - 5
    [IO.File]::WriteAllLines($tf, [string[]]@($lines | ForEach-Object { ($_.Split(',') | Select-Object -First $keep) -join ',' }))
    $mf = Join-Path $dir 'meta.json'
    $meta = [IO.File]::ReadAllText($mf, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $meta.PSObject.Properties.Remove('CoreBusyPct')
    foreach ($id in 'cpu.coreMax', 'cpu.coreBusy', 'cpu.perf', 'cpu.utility', 'mem.pagesout') { $meta.Sources.PSObject.Properties.Remove($id) }
    [IO.File]::WriteAllText($mf, ($meta | ConvertTo-Json -Depth 12 -Compress), (New-Object Text.UTF8Encoding $false))
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
            NoneReported = (Join-Path $OutDir 'report-none-reported.html')
            Spike = (Join-Path $OutDir 'report-spike.html'); NoData = (Join-Path $OutDir 'report-nodata.html'); CutRep = (Join-Path $OutDir 'report-cutrep.html')
            Masked = (Join-Path $OutDir 'report-masked.html'); MaskedP = (Join-Path $OutDir 'report-masked-personen.html')
            Health = (Join-Path $OutDir 'report-health.html'); HealthMasked = (Join-Path $OutDir 'report-health-masked.html') }
    # a cut that starts 10 min after the first event of the capture, with a reported time 1 min after that event: the reported
    # time lies inside the capture but before the cut, and events lie around it
    $firstEv = [DateTimeOffset]::Parse((Get-Content (Join-Path $run 'events.csv') -TotalCount 2)[1].Split(',')[0], [cultureinfo]::InvariantCulture).ToUnixTimeMilliseconds()
    [void](& $report -Path $run -OutFile $r.CutRep -RoleFile $roles -From (Get-ServerTime $run ($firstEv + 600000)) -ReportedTime (Get-ServerTime $run ($firstEv + 60000)) 6>$null)
    $reported = [DateTimeOffset]::FromUnixTimeMilliseconds($startMs + 330000).LocalDateTime
    [void](& $report -Path $run -OutFile $r.Report -RoleFile $roles 6>$null)
    [void](& $report -Path $run -OutFile $r.Focus -RoleFile $roles -FocusUser 'user003' -ReportedTime $reported 6>$null)
    # ohne Ereignisse: der Bericht ohne Befund zeigte sonst die Ereignisvorfaelle der Simulation
    $quiet = Copy-SimRun $run (Join-Path $OutDir 'none') @('events.csv', 'events_before.csv')
    $noneThresholds = New-NoFindingThresholdFile (Join-Path $OutDir 'none.json')
    [void](& $report -Path $quiet -OutFile $r.None -RoleFile $roles -ThresholdFile $noneThresholds 6>$null)
    # derselbe Bericht ohne Befund mit einer gemeldeten Uhrzeit in der Mitte der Messung
    $firstTick = [DateTimeOffset]::Parse((Get-Content (Join-Path $run 'ticks.csv') -TotalCount 2)[1].Split(',')[1], [cultureinfo]::InvariantCulture).ToUnixTimeMilliseconds()
    [void](& $report -Path $quiet -OutFile $r.NoneReported -RoleFile $roles -ThresholdFile $noneThresholds -ReportedTime (Get-ServerTime $run ($firstTick + 1800000)) 6>$null)
    # die ersten dreieinhalb ruhigen Minuten mit zwei kritischen CPU-Takten: kein Vorfall, aber einzelne Ueberschreitungen
    $spike = New-SpikeRun $run (Join-Path $OutDir 'spike')
    [void](& $report -Path $spike -OutFile $r.Spike -RoleFile $roles -To (Get-ServerTime $run ($startMs + 208000)) 6>$null)
    # der CPU-Engpass ohne Prozessdaten und ohne Eingabeverzoegerung je Sitzung
    $bare = Copy-SimRun $run (Join-Path $OutDir 'nodata') @('processes.csv', 'inputdelay.csv')
    [void](& $report -Path $bare -OutFile $r.NoData -RoleFile $roles -From (Get-ServerTime $run ($cpu.StartMs - 60000)) -To (Get-ServerTime $run ($cpu.EndMs + 60000)) 6>$null)
    # der ganze Bericht mit allen Namen ersetzt
    [void](& $report -Path $run -OutFile $r.Masked -RoleFile $roles -Mask Alles 6>$null)
    # die Stufe Personen, mit einem gemeldeten Benutzer, den die Aufzeichnung nicht kennt
    [void](& $report -Path $run -OutFile $r.MaskedP -RoleFile $roles -Mask Personen -FocusUser 'KLINIK\schmidt.unbekannt' -ReportedTime $reported 6>$null)
    # the health report of a quick run (Task 17), plain and with all names replaced
    $r.HealthRun = Invoke-SimHealthOnly (Join-Path $OutDir 'health')
    [void](& $report -Path $r.HealthRun -OutFile $r.Health -RoleFile $roles 6>$null)
    [void](& $report -Path $r.HealthRun -OutFile $r.HealthMasked -RoleFile $roles -Mask Alles 6>$null)
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
function New-TestAppFile([string]$Dir) {
    # Writes <Dir>/apps.test.json: the shipped application list plus a fourth application with probes, the invented
    # simapp; returns the path.
    $list = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../src/apps.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
    $sim = [ordered]@{
        key = 'simapp'; label = 'Sim-Fachanwendung'; processes = @('simapp.exe')
        installed = [ordered]@{ kind = 'file'; path = 'C:\Program Files\SimApp\simapp.exe' }
        probes = @(
            [ordered]@{ id = 'version'; label = 'Version der Sim-Fachanwendung'; kind = 'file'; path = 'C:\Program Files\SimApp\simapp.exe' }
            [ordered]@{ id = 'cacheMode'; label = 'Cache-Betriebsart'; kind = 'registryValue'; path = 'HKLM\SOFTWARE\SimApp'; name = 'CacheMode'; names = $false }
            [ordered]@{ id = 'dataPath'; label = 'Datenordner der Sim-Fachanwendung'; kind = 'registryValue'; path = 'HKLM\SOFTWARE\SimApp'; name = 'DataPath'; names = $true }
        )
    }
    $list.apps = @($list.apps) + [pscustomobject]$sim
    $file = Join-Path $Dir 'apps.test.json'
    [IO.File]::WriteAllText($file, ($list | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
    $file
}
function Invoke-SimHealthOnly([string]$OutDir, [hashtable]$Extra = @{}, [string]$ConsoleFile = '') {
    # Schnelllauf (-HealthOnly) der Simulation unter deutscher Kultur, sonst wie Invoke-SimCapture; liefert den
    # Aufzeichnungsordner
    [cultureinfo]::CurrentCulture = [cultureinfo]'de-DE'
    $capture = Join-Path $PSScriptRoot '../src/Start-WorkerPerfCapture.ps1'
    if (-not $ConsoleFile) { (& $capture -Simulate -HealthOnly -OutputPath $OutDir @Extra 6>$null) | Select-Object -Last 1 }
    else {
        $out = @(& $capture -Simulate -HealthOnly -OutputPath $OutDir @Extra 6>&1)
        [IO.File]::WriteAllText($ConsoleFile, ($out | Out-String))
        [string]$out[-1]
    }
}
function Add-HealthCanaries([string]$Dir) {
    # Plants tokens in <Dir>/health.json of a capture or a quick run (Task 16, moved here from tests/Mask.Tests.ps1 in
    # Task 17) and returns them as @{ Free; Names; Plain }: a token of its own in every text field of the value list (a
    # single value, or in a list the field of the first entry; a value that is not read and an empty list become a read
    # value with one entry whose other fields are empty), in the value of every probe of the application list that reads a
    # text or a registry value (as the collector writes it: in Names where the probe carries names, else in Value; the row
    # is made read), in the fields App, Id, Kind, Read, State and Reason of one more probe row, and in the first empty
    # Error of an area. A field that can carry free server text or a name of a server, person, client, domain or address
    # gets a token of its kind (Free, Names); every other text field a plain token (Plain: place -> token, the place being
    # the id, id.Field or apps.probes[app.probe].Field), which the masking keeps by design: the canary test of
    # tests/Mask.Tests.ps1 compares the places whose token is left at level Alles with its list of the fields that cannot
    # hold a name of the customer's environment, so that a new text field fails the test until it is classified (fix round
    # 1 of Task 16, follow-up). Two services an administrator named (ruling ZB-R61) are added to the list of all services.
    # Needs src/WorkerPerf.Common.ps1 and src/WorkerPerf.Load.ps1 dot-sourced by the caller.
    $hf = Join-Path $Dir 'health.json'; $h = ConvertFrom-WorkerPerfHealthJsonText ([IO.File]::ReadAllText($hf))
    $free = New-Object System.Collections.Generic.List[string]; $names = New-Object System.Collections.Generic.List[string]; $plain = [ordered]@{}
    $marker = { param([string]$Type, [string]$Place)
        $k = '{0:000}' -f ($free.Count + $names.Count + $plain.Count + 1)          # one count over all tokens, of one width
        switch ($Type) {
            'text:free' { $t = "CANARYH$k"; $free.Add($t) }
            'text:path' { $t = "\\kanari$k\frei\ordner"; $names.Add($t) }
            'text:share' { $t = "\\kanari$k\frei"; $names.Add($t) }
            'text:user' { $t = "kanari$k"; $names.Add($t) }
            'text:domain' { $t = "KANARI$k"; $names.Add($t) }
            'text:client' { $t = "KANARI-WS$k"; $names.Add($t) }
            'text:address' { $t = '10.77.0.' + [int]$k; $names.Add($t) }
            'text:host' { $t = "kanari$k.sim.local"; $names.Add($t) }
            'text:hosts' { $t = "kanari$k.sim.local"; $names.Add($t) }
            default { $t = "KANPLAIN$k"; $plain[$Place] = $t }
        }
        $t }
    $isText = { param([string]$Type) $Type -eq 'value' -or $Type.StartsWith('text') }
    $appTypes = @{}
    foreach ($a in @(Read-WorkerPerfHealthApps (Join-Path $PSScriptRoot '../src/apps.json'))) {
        foreach ($p in @($a.probes)) { $appTypes['{0}.{1}' -f $a.key, $p.id] = Get-WorkerPerfAppFactType $p }
    }
    foreach ($id in $WorkerPerfHealthValues.Keys) {
        $def = $WorkerPerfHealthValues[$id]; $values = $h['Areas'][$def.Area]['Values']
        if ($def.Type -ne 'list') {
            if (& $isText $def.Type) { $values[$id] = [ordered]@{ State = 'read'; Reason = ''; Value = (& $marker $def.Type $id) } }
            continue
        }
        $v = $values[$id]; $rows = @(); if ($null -ne $v -and $v['State'] -eq 'read') { $rows = @($v['Value']) }
        if ($id -eq 'apps.probes') {
            foreach ($row in $rows) {
                $probe = '{0}.{1}' -f $row['App'], $row['Id']; $type = $appTypes[$probe]
                if (@('value', 'text', 'text:free') -notcontains $type) { continue }
                $row['State'] = 'read'; $row['Reason'] = ''; $row['Value'] = $null; $row['Names'] = $null
                if ($type -eq 'text:free') { $row['Names'] = & $marker $type "apps.probes[$probe].Names" } else { $row['Value'] = & $marker $type "apps.probes[$probe].Value" }
            }
            $row = [ordered]@{}; foreach ($f in $def.Fields.Keys) { $row[$f] = $null }
            foreach ($f in 'App', 'Id', 'Kind', 'Read', 'State', 'Reason') { $row[$f] = & $marker $def.Fields[$f] "apps.probes.$f" }
            $values[$id] = [ordered]@{ State = 'read'; Reason = ''; Value = @($rows) + @($row) }
            continue
        }
        if ($rows.Count -eq 0) {
            $row = [ordered]@{}; foreach ($f in $def.Fields.Keys) { $row[$f] = $null }
            $values[$id] = [ordered]@{ State = 'read'; Reason = ''; Value = @($row) }
        }
        else { $row = $rows[0] }
        foreach ($f in $def.Fields.Keys) { if (& $isText $def.Fields[$f]) { $row[$f] = & $marker $def.Fields[$f] "$id.$f" } }
        if ($id -eq 'security.services') {
            $values[$id]['Value'] = @($values[$id]['Value']) + @([ordered]@{ Name = 'MSSQL$KANINSTANZ'; State = 'Running'; StartMode = 'Auto' },
                [ordered]@{ Name = 'KanFirmaAgent'; State = 'Running'; StartMode = 'Auto' })
        }
    }
    $areaWithoutError = @($h['Areas'].Values | Where-Object { [string]$_['Error'] -eq '' })[0]; $areaWithoutError['Error'] = 'Fehler CANARYHER'
    $text = ConvertTo-Json -InputObject $h -Depth 20; [IO.File]::WriteAllText($hf, $text)
    foreach ($t in @($free) + @($names) + @($plain.Values) + 'Fehler CANARYHER' + 'MSSQL$KANINSTANZ') {
        if (-not $text.Contains((ConvertTo-Json $t).Trim('"'))) { throw "Kanarienvogel nicht gesetzt: $t" }
    }
    @{ Free = [string[]]$free.ToArray(); Names = [string[]]$names.ToArray(); Plain = $plain }
}
function Get-HealthCanaryKeep {
    # The places of Add-HealthCanaries (Plain) whose plain token a report of level Alles keeps, by id and field
    # (apps.probes: the value of each probe), for the measurement report and the health report of a quick run alike:
    # what the collector writes there cannot be a name of the customer's environment (re-review of fix round 1 of
    # Task 16): keywords of Windows and of the collector (states, start modes, modes, kinds, the fixed WEM service
    # names), versions, numbers and times, device and driver texts of the vendor, the services under a Citrix folder,
    # names from the event catalogue and the application list. Every other plain text field must lose its token: the
    # names of the other services (ruling ZB-R61) and the value of a probe with names, and a new text field until it
    # is classified here.
    @(
        'size.model', 'size.vmtoolsService', 'size.vmtoolsVersion', 'size.netAdapters.Name', 'size.netAdapters.Service', 'size.storageControllers.Name',
        'size.storageControllers.Driver', 'size.balloonDriver',
        'operation.lastUpdateId', 'operation.powerPlan', 'operation.volumes.Drive', 'operation.volumes.FileSystem',
        'sessions.list.State',
        'vda.version', 'vda.services.Name', 'vda.services.State', 'vda.services.StartMode', 'vda.desktopService', 'vda.controllers.Kind', 'vda.controllers.From',
        'vda.wemService', 'vda.wemServices.Name', 'vda.wemServices.State', 'vda.wemServices.StartMode', 'vda.wemVersion', 'vda.teamsService', 'vda.webSocketService',
        'profile.service', 'profile.version',
        'print.spooler', 'print.spoolerStartMode', 'print.citrixPrintService', 'print.mappingClientVersion',
        'security.services.State', 'security.services.StartMode', 'security.defenderService', 'security.defenderMode', 'security.defenderVersion',
        'security.mdeService', 'security.filters.Name', 'security.filters.Altitude', 'security.applockerService', 'security.applockerCollections.Collection',
        'network.smb1', 'network.smbConnections.Dialect', 'network.rss.Description', 'network.rssGlobal', 'network.timeType', 'network.timeService',
        'events.logs.Log', 'events.logs.Mode',
        'maintenance.tasks.State', 'maintenance.tasks.Triggers', 'maintenance.scanTime', 'maintenance.quickScanTime', 'maintenance.searchService',
        'maintenance.updateService',
        'apps.probes.App', 'apps.probes.Id', 'apps.probes.Kind', 'apps.probes.Read', 'apps.probes.State', 'apps.probes.Reason',
        'apps.probes[edge.version].Value', 'apps.probes[edge.webview2Version].Value', 'apps.probes[edge.updateDefault].Value', 'apps.probes[edge.updateStable].Value',
        'apps.probes[edge.updateWebView2].Value', 'apps.probes[edge.updateCheckMinutes].Value', 'apps.probes[edge.startupBoost].Value',
        'apps.probes[edge.backgroundMode].Value', 'apps.probes[edge.sleepingTabs].Value', 'apps.probes[edge.autoDiscard].Value',
        'apps.probes[edge.roamingProfile].Value', 'apps.probes[edge.updateService].Value',
        'apps.probes[office.policyUpdateBranch].Value', 'apps.probes[office.hideUpdateNotifications].Value', 'apps.probes[office.hideEnableDisableUpdates].Value',
        'apps.probes[office.perUserCatalog].Value', 'apps.probes[office.version].Value', 'apps.probes[office.platform].Value', 'apps.probes[office.updatesEnabled].Value',
        'apps.probes[teams.version].Value', 'apps.probes[teams.disableAutoUpdate].Value', 'apps.probes[teams.disableFallback].Value', 'apps.probes[teams.maxFps].Value',
        'apps.probes[teams.webview2Version].Value')
}
