BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1')
    $script:Capture = Join-Path $PSScriptRoot '../src/Start-WorkerPerfCapture.ps1'
    $script:Report = Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1'
    $script:Texts = Read-WorkerPerfTexts (Join-Path $PSScriptRoot '../src/texts.de.json')
    # die Aufzeichnungen von New-SkipRuns und je ein Bericht dazu
    $script:Rep = New-SkipReports (Join-Path $TestDrive 'rep')
    $script:Names = @('Prozesse', 'Laufwerke', 'Citrix', 'Ereignisse', 'Rueckblick', 'Drucken', 'Gegenstellen')
    $script:Runs = [ordered]@{}; $script:D = @{}
    foreach ($k in @('Voll') + $Names + 'Alle') { $Runs[$k] = $Rep[$k].Run; $D[$k] = Get-ReportData $Rep[$k].Report }
    $script:Places = @{ Prozesse = @('procs', 'apps', 'sessions.resources', 'incidents.contributors', 'incidents.delayProcs', 'print.processes'); Laufwerke = @('volumes', 'shares', 'sessions.profile')
        Citrix = @('citrix', 'sessions.rtt', 'incidents.ica'); Ereignisse = @('events', 'sessions.events', 'incidents.events'); Rueckblick = @('before'); Drucken = @('print.drivers', 'print.queues')
        Gegenstellen = @('probes', 'incidents.endpoints') }
    $script:Files = @{ Prozesse = @('processes.csv', 'procinfo.csv', 'procend.csv', 'inputdelay_proc.csv'); Laufwerke = @('volumes.csv', 'shares.csv'); Citrix = @('citrix.csv')
        Ereignisse = @('events.csv'); Rueckblick = @('events_before.csv'); Drucken = @('printdrivers.csv', 'printqueues.csv'); Gegenstellen = @('probes.csv') }
    $script:Ids = @{ Prozesse = @('process', 'input.process'); Laufwerke = @('disk.latency', 'smb.latency', 'profile.map'); Citrix = @('ica.rtt', 'ica.latency'); Ereignisse = @(); Rueckblick = @()
        Drucken = @('print.drivers', 'print.queues'); Gegenstellen = @('probe.connect') }
    function Get-Meta([string]$Run) { Get-Content (Join-Path $Run 'meta.json') -Raw | ConvertFrom-Json }
    function Get-CsvNames([string]$Run) { Get-ChildItem $Run -Filter *.csv | ForEach-Object Name | Sort-Object }   # schlichte Pipeline-Ausgabe: Should -Be vergleicht die Elemente
    function Get-LineCounts([string]$Run) { $c = [ordered]@{}; foreach ($f in Get-ChildItem $Run -Filter *.csv | Sort-Object Name) { $c[$f.Name] = @(Get-Content $f.FullName).Count }; $c }
    $script:VollCounts = Get-LineCounts $Runs.Voll
    function Get-Shape([string]$Run) {   # Dateien mit Zeilenzahl und meta.json ohne die Zeiten des Laufs
        $m = Get-Meta $Run; foreach ($k in 'StartTime', 'EndTime') { $m.PSObject.Properties.Remove($k) }
        (@(Get-ChildItem $Run -Filter *.csv | Sort-Object Name | ForEach-Object { '{0}:{1}' -f $_.Name, @(Get-Content $_.FullName).Count }) -join ' ') + "`n" + ($m | ConvertTo-Json -Depth 8 -Compress)
    }
}
Describe 'Aufzeichnung mit -Skip' {
    It 'legt die Dateien von <_> nicht an, vermerkt ihre Quellen und laesst alles andere stehen' -ForEach 'Prozesse', 'Laufwerke', 'Citrix', 'Ereignisse', 'Rueckblick', 'Drucken', 'Gegenstellen' {
        $cat = $_; $m = Get-Meta $Runs[$cat]
        Get-CsvNames $Runs[$cat] | Should -Be @($WorkerPerfHeaders.Keys | Where-Object { $Files[$cat] -notcontains $_ } | Sort-Object)
        @($m.Skip) | Should -Be @($cat); $m.Ticks | Should -Be 1800; @($m.SourceErrors.PSObject.Properties).Count | Should -Be 0
        foreach ($id in $Ids[$cat]) { $m.Sources.$id.Available | Should -BeFalse -Because $id; $m.Sources.$id.Detail | Should -Be "abgeschaltet (-Skip $cat)" }
        @($m.Sources.PSObject.Properties | Where-Object { -not $_.Value.Available }).Count | Should -Be $Ids[$cat].Count
        # die anderen Kategorien und die Basis behalten ihre Zeilen: jede verbliebene Datei hat so viele Zeilen wie im vollen Lauf
        $counts = Get-LineCounts $Runs[$cat]
        foreach ($f in $counts.Keys) { $counts[$f] | Should -Be $VollCounts[$f] -Because "$f ohne $cat" }
        @($counts.Values | Where-Object { $_ -le 1 }).Count | Should -Be 0   # keine Datei nur mit der Kopfzeile
    }
    It 'misst ohne alle Kategorien die Basis wie im vollstaendigen Lauf' {   # Review Focus 1
        $m = Get-Meta $Runs.Alle
        Get-CsvNames $Runs.Alle | Should -Be @('inputdelay.csv', 'sessions.csv', 'snapshots.csv', 'ticks.csv')
        @($m.Skip) | Should -Be $Names; $m.EventLookbackDays | Should -Be 0; @($m.Endpoints).Count | Should -Be 0; @($m.SourceErrors.PSObject.Properties).Count | Should -Be 0
        $m.Sources.'events.application'.Detail | Should -Be 'abgeschaltet (-Skip Ereignisse,Rueckblick)'; $m.Sources.'input.session'.Available | Should -BeTrue; $m.Sources.sessions.Available | Should -BeTrue
        @($m.Sources.PSObject.Properties | Where-Object { $_.Name -like 'events.*' -and $_.Value.Detail -ne 'abgeschaltet (-Skip Ereignisse,Rueckblick)' }).Count | Should -Be 0
        @($m.EventReadCounts.PSObject.Properties).Count | Should -Be 0; @($m.LookbackReadCounts.PSObject.Properties).Count | Should -Be 0
        $base = { param($run) (Get-Content (Join-Path $run 'ticks.csv') | ForEach-Object { $_.Split(',')[2..16] -join ',' }) -join "`n" }   # ElapsedSec bis NetSentBps
        & $base $Runs.Alle | Should -BeExactly (& $base $Runs.Voll)
        Get-Content (Join-Path $Runs.Alle 'inputdelay.csv') -Raw | Should -BeExactly (Get-Content (Join-Path $Runs.Voll 'inputdelay.csv') -Raw)
        $snaps = @(Import-Csv (Join-Path $Runs.Alle 'snapshots.csv'))
        @($snaps | Where-Object Kind -in 'R', 'K').Count | Should -Be 240; $snaps[0].Sessions | Should -Be '25'; $snaps[0].Processes | Should -Be ''; $snaps[0].RowsWritten | Should -Be ''
        @(Import-Csv (Join-Path $Runs.Alle 'sessions.csv') | Where-Object P -eq '0').Count | Should -Be 26
    }
    It 'haelt Ereignisse und Rueckblick unabhaengig' {
        # Aussage angepasst: die simulierte Stunde hat seit der Korrekturrunde des Ereignisplans sechs Ereignisse im Rueckblick
        @(Import-Csv (Join-Path $Runs.Ereignisse 'events_before.csv')).Count | Should -Be 6; (Get-Meta $Runs.Ereignisse).Sources.'events.application'.Available | Should -BeTrue
        @(Import-Csv (Join-Path $Runs.Rueckblick 'events.csv')).Count | Should -Be 13; (Get-Meta $Runs.Rueckblick).EventLookbackDays | Should -Be 0   # weggelassen gewinnt gegen 7 Tage
        (Get-Meta $Runs.Rueckblick).Sources.'events.application'.Detail | Should -Be 'Simulation'
    }
    It 'ruft die Quelle fuer eine weggelassene Kategorie nicht auf und laesst ihre Zaehler leer' {
        # jeder eigenstaendige Aufruf einer Kategorie wirft (ein Aufruf staende in SourceErrors oder beendete die
        # Aufzeichnung); die Zaehler der Ereignis-Abrufe sind nie leer
        $counts = 'function Get-WorkerPerfEventCounts { [ordered]@{ application = [ordered]@{ Skipped = 1 } } }'
        $throwing = $counts + "`n" + (@('Get-WorkerPerfServices', 'Get-WorkerPerfEvents', 'Get-WorkerPerfEventsBefore', 'Get-WorkerPerfPrintDrivers', 'Get-WorkerPerfPrintQueues',
                'Start-WorkerPerfProbes', 'Receive-WorkerPerfProbes') | ForEach-Object { "function $_ { throw 'Testaufruf $_' }" }) -join "`n"
        $none = (& (New-PatchedSource (Join-Path $TestDrive 'srcthrow') $throwing) -Simulate -DurationMinutes 60 -Skip $Names -OutputPath (Join-Path $TestDrive 'throw') 6>$null 3>$null) | Select-Object -Last 1
        $m = Get-Meta $none
        $m.EndReason | Should -Be 'duration'; @($m.SourceErrors.PSObject.Properties).Count | Should -Be 0
        @($m.EventReadCounts.PSObject.Properties).Count | Should -Be 0; @($m.LookbackReadCounts.PSObject.Properties).Count | Should -Be 0
        # ohne Ereignisse liest nur der Rueckblick (seine Zaehler stehen bei LookbackReadCounts), ohne Rueckblick nur der regulaere Abruf
        $src = New-PatchedSource (Join-Path $TestDrive 'srccount') $counts
        $noEv = Get-Meta ((& $src -Simulate -DurationMinutes 60 -Skip Ereignisse -OutputPath (Join-Path $TestDrive 'noev') 6>$null) | Select-Object -Last 1)
        @($noEv.EventReadCounts.PSObject.Properties).Count | Should -Be 0; $noEv.LookbackReadCounts.application.Skipped | Should -Be 1
        $noLb = Get-Meta ((& $src -Simulate -DurationMinutes 60 -Skip Rueckblick -OutputPath (Join-Path $TestDrive 'nolb') 6>$null) | Select-Object -Last 1)
        @($noLb.LookbackReadCounts.PSObject.Properties).Count | Should -Be 0; $noLb.EventReadCounts.application.Skipped | Should -Be 1
    }
    It 'ergibt mit den alten Schaltern, doppelt, in anderer Schreibweise und als eine Zeichenkette dieselbe Aufzeichnung' {   # Review Focus 4 und 5
        $a = @(& $Capture -Simulate -DurationMinutes 60 -NoCitrix -OutputPath (Join-Path $TestDrive 'a') 6>&1)
        ($a | Out-String) | Should -Match 'Gemessen: Basis, Prozesse, Laufwerke, Ereignisse, Rueckblick, Drucken, Gegenstellen\s+Nicht gemessen \(-Skip\): Citrix'
        Get-Shape ([string]$a[-1]) | Should -BeExactly (Get-Shape $Runs.Citrix)
        $b = @(& $Capture -Simulate -DurationMinutes 60 -EventLookbackDays 0 -Skip 'rueckblick,RUECKBLICK', 'Zustand' -OutputPath (Join-Path $TestDrive 'b') 6>&1)
        Get-Shape ([string]$b[-1]) | Should -BeExactly (Get-Shape $Runs.Rueckblick)   # Zustand: angenommen, ohne Wirkung, auch auf der Konsole
        $console = $b | Out-String
        $console | Should -Match 'Nicht gemessen \(-Skip\): Rueckblick\r?\n'; $console | Should -Not -Match 'Zustand'
    }
    It 'lehnt einen unbekannten Wert ab, bevor etwas angelegt wird' {
        $dir = Join-Path $TestDrive 'x'
        { & $Capture -Simulate -DurationMinutes 60 -Skip Prozesse, Netz -OutputPath $dir 6>$null } | Should -Throw "*'Netz'*Gueltige Werte: Prozesse, Laufwerke, Citrix, Ereignisse, Rueckblick, Drucken, Gegenstellen, Zustand.*"
        Test-Path $dir | Should -BeFalse
    }
    It 'laesst die Aufzeichnung ohne -Skip wie bisher, bis auf das neue Feld Skip' {
        $m = Get-Meta $Runs.Voll; $names = @($m.PSObject.Properties.Name)
        Get-CsvNames $Runs.Voll | Should -Be @($WorkerPerfHeaders.Keys | Sort-Object)
        # Aussage angepasst: EventReadCounts und LookbackReadCounts kamen nach dem Plan dazu; Skip steht hinter ihnen
        $names | Should -Be @('SchemaVersion', 'Computer', 'OS', 'LogicalProcessors', 'PhysicalMemoryMB', 'FastIntervalSeconds', 'IntervalSeconds', 'BurstIntervalSeconds', 'BurstHoldSeconds', 'MaxSizeMB',
            'StartTime', 'EndTime', 'EndReason', 'EndMessage', 'Ticks', 'Snapshots', 'SkippedTicks', 'Simulated', 'IncludeCommandLine', 'EventLookbackDays', 'LookbackCapped', 'EventReadCounts', 'LookbackReadCounts', 'Skip', 'CollectorPid', 'Endpoints', 'Sources', 'SourceErrors')
        @($m.Skip).Count | Should -Be 0; $m.EventLookbackDays | Should -Be 7; @($m.Endpoints).Count | Should -Be 3
        @($m.Sources.PSObject.Properties | Where-Object { -not $_.Value.Available -or $_.Value.Detail -notlike 'Simulation*' }).Count | Should -Be 0
    }
    It 'nennt beim Start die gemessenen und die weggelassenen Kategorien' {
        # die Konsolenausgabe des vollen Laufs: New-SkipRuns legt sie neben den Ordner Voll, der die Aufzeichnung enthaelt
        $out = Get-Content (Join-Path (Split-Path (Split-Path $Runs.Voll -Parent) -Parent) 'Voll.console.txt') -Raw
        $out | Should -Match 'laeuft: [^\r\n]+\r?\nGemessen: Basis, Prozesse, Laufwerke, Citrix, Ereignisse, Rueckblick, Drucken, Gegenstellen\r?\nNicht gemessen \(-Skip\): keine\r?\n'
    }
}
Describe 'Berichtsdaten mit weggelassenen Kategorien' {
    It 'nennt fuer <_> Kategorie, Grund und abhaengige Stellen' -ForEach 'Prozesse', 'Laufwerke', 'Citrix', 'Ereignisse', 'Rueckblick', 'Drucken', 'Gegenstellen' {
        $s = @($D[$_].skipped); $s.Count | Should -Be 1
        $s[0].id | Should -Be $_; $s[0].label | Should -Be $Texts["skip.label.$_"]; $s[0].text | Should -Be $Texts["skip.text.$_"]; @($s[0].places) | Should -Be $Places[$_]
    }
    It 'zaehlt kein Signal einer weggelassenen Kategorie im Soll-Ist' {
        $a = $D.Alle;   # nicht $d: PowerShell unterscheidet $d und $D nicht
        @($a.skipped.id) | Should -Be $Names; $a.skipped[0].text | Should -Be 'Prozesse wurden bei dieser Messung nicht erfasst.'
        foreach ($id in 'disk.latency', 'smb.latency', 'ica.rtt', 'ica.latency', 'probe.connect') {
            $r = $a.sollIst | Where-Object id -eq $id; $r.measured | Should -BeFalse -Because $id; $r.status | Should -Be 0; $r.exceeded | Should -BeFalse
        }
        ($a.sollIst | Where-Object id -eq 'smb.latency').detail | Should -Be 'abgeschaltet (-Skip Laufwerke)'
        @($a.sollIst | Where-Object measured).id | Should -Be @('cpu.host', 'cpu.queue', 'cpu.steal', 'mem.used', 'mem.commit', 'mem.pagesin', 'input.session')
        $a.unmeasured.worker | Should -Be @('Datenträger-Antwortzeit', 'Freigabe-Antwortzeit (SMB)'); $a.before.status | Should -Be 'off'; $D.Rueckblick.before.status | Should -Be 'off'
    }
    It 'erkennt die Vorfaelle der Basis in jeder Kombination wie im vollstaendigen Lauf' {   # Review Focus 1
        $win = { param($d) @($d.incidents | Where-Object { $_.type -ne 'ereignis' -and -not $_.chronic } | ForEach-Object { '{0}-{1}' -f ($_.start - $d.meta.start), ($_.end - $d.meta.start) }) }
        $lead = { param($d) @($d.incidents | Where-Object { $_.lead -in 'cpu', 'memory' } | ForEach-Object { '{0}|{1}|{2}' -f $_.type, $_.lead, ($_.start - $d.meta.start) }) }
        @(& $win $D.Voll).Count | Should -Be 7; @(& $lead $D.Voll).Count | Should -Be 2
        foreach ($k in $Names + 'Alle') { & $win $D[$k] | Should -Be (& $win $D.Voll) -Because $k; & $lead $D[$k] | Should -Be (& $lead $D.Voll) -Because $k }
    }
    It 'wertet eine Aufzeichnung von vor diesem Plan als vollstaendig gemessen aus, mit demselben Bericht' {   # Review Focus 2
        $old = Copy-SimRun $Runs.Voll (Join-Path $TestDrive 'alt'); $f = Join-Path $old 'meta.json'
        [IO.File]::WriteAllText($f, ([IO.File]::ReadAllText($f) -replace '(?s)"Skip":\s*\[\s*\],\s*', '')); (Get-Meta $old).PSObject.Properties.Name | Should -Not -Contain 'Skip'
        $out = Join-Path $TestDrive 'alt.html'; [void](& $Report -Path $old -OutFile $out -RoleFile (Join-Path $TestDrive 'rep/roles.sim.json') 6>$null)
        $norm = { param($file) [IO.File]::ReadAllText($file) -replace '"generated":\d+', '"generated":0' }
        & $norm $out | Should -BeExactly (& $norm $Rep.Voll.Report)
        @($D.Voll.skipped).Count | Should -Be 0; @($D.Voll.PSObject.Properties.Name)[-1] | Should -Be 'skipped'   # das neue Feld der Berichtsdaten, leer
    }
    It 'nennt fuer weggelassene Ereignisse keine Zaehler der Messung und laesst den Rueckblick leer, wenn er weggelassen ist' {
        # ohne Ereignisse: die Zaehler der Messung fehlen (die Seite sagt dann nichts ueber sie, skipped nennt den Grund);
        # der Rueckblick ist derselbe wie im vollen Lauf
        @($D.Ereignisse.quality.eventReads).Count | Should -Be 0; @($D.Alle.quality.eventReads).Count | Should -Be 0
        $D.Ereignisse.before.status | Should -Be $D.Voll.before.status; $D.Ereignisse.before.eventCount | Should -Be $D.Voll.before.eventCount
        $D.Voll.before.status | Should -Be 'read'
        foreach ($k in 'Rueckblick', 'Alle') {
            $b = $D[$k].before; $b.status | Should -Be 'off' -Because $k; $b.eventCount | Should -Be 0
            foreach ($f in 'readCounts', 'oldest', 'perDay', 'incidents', 'capped') { @($b.$f).Count | Should -Be 0 -Because "$k before.$f" }
        }
    }
    It 'zeigt fuer weggelassene Ereignisse und Rueckblick keine Zaehler, auch wenn meta.json welche nennt' {   # Fix-Runde 1 (Minor 4)
        # Der Collector laesst beide Zaehler einer weggelassenen Kategorie leer (oben); erst eine von Hand geaenderte
        # meta.json nennt welche. Dieselbe Aenderung im vollen Lauf zeigt, dass die Zaehler sonst erscheinen.
        $cnt = [pscustomobject]@{ application = [pscustomobject]@{ SkippedRecords = 4; UnformattedMessages = 2; DroppedEvents = 9 } }
        $edit = { param([string]$Run, [string]$Name)
            $dir = Copy-SimRun $Run (Join-Path $TestDrive "gate-$Name"); $f = Join-Path $dir 'meta.json'
            $m = Get-Content $f -Raw | ConvertFrom-Json
            $m | Add-Member -Force EventReadCounts $cnt; $m | Add-Member -Force LookbackReadCounts ([pscustomobject]@{ application = [pscustomobject]@{ SkippedRecords = 1; UnformattedMessages = 1; DroppedEvents = 0 } })
            $m.EventLookbackDays = 7
            [IO.File]::WriteAllText($f, ($m | ConvertTo-Json -Depth 8))
            $out = Join-Path $TestDrive "gate-$Name.html"; [void](& $Report -Path $dir -OutFile $out -RoleFile (Join-Path $TestDrive 'rep/roles.sim.json') 6>$null)
            Get-ReportData $out }
        $full = & $edit $Runs.Voll 'voll'
        @($full.quality.eventReads | ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.log, $_.dropped, $_.skipped, $_.unformatted }) | Should -Be @('application|9|3|1')
        @($full.before.readCounts).Count | Should -Be 1; $full.before.status | Should -Be 'read'
        $noEv = & $edit $Runs.Ereignisse 'ereignisse'
        @($noEv.quality.eventReads).Count | Should -Be 0; @($noEv.before.readCounts).Count | Should -Be 1
        $noLb = & $edit $Runs.Rueckblick 'rueckblick'
        @($noLb.before.readCounts).Count | Should -Be 0; $noLb.before.status | Should -Be 'off'; @($noLb.quality.eventReads).Count | Should -Be 1
    }
    It 'zeigt die Hauptanwendung nur, wenn Prozesse gemessen wurden' {   # Fix-Runde 1 (Important 1)
        $D.Voll.mainApp | Should -Not -BeNullOrEmpty; $D.Voll.mainApp.label | Should -Not -BeNullOrEmpty
        foreach ($k in 'Prozesse', 'Alle') { $null -eq $D[$k].mainApp | Should -BeTrue -Because $k; @($D[$k].PSObject.Properties.Name) | Should -Contain 'mainApp' }
        foreach ($k in 'Laufwerke', 'Citrix', 'Ereignisse', 'Rueckblick', 'Drucken', 'Gegenstellen') {
            $D[$k].mainApp.label | Should -Be $D.Voll.mainApp.label -Because $k; $D[$k].mainApp.status | Should -Be $D.Voll.mainApp.status -Because $k
        }
    }
    It 'ordnet die Felder von skipped im Bestand tests/MaskCensus.json ein' {
        $census = (Get-Content (Join-Path $PSScriptRoot 'MaskCensus.json') -Raw -Encoding UTF8 | ConvertFrom-Json).fields
        $paths = New-Object System.Collections.Generic.SortedSet[string] ([StringComparer]::Ordinal)
        $walk = { param($v, [string]$p)
            if ($null -eq $v -or $v -is [ValueType]) { return }
            if ($v -is [string]) { [void]$paths.Add($p); return }
            if ($v -is [System.Collections.IEnumerable]) { foreach ($x in $v) { & $walk $x "$p[]" }; return }
            foreach ($q in $v.PSObject.Properties) { & $walk $q.Value $(if ($p) { "$p.$($q.Name)" } else { $q.Name }) } }
        & $walk @($D.Alle.skipped) 'skipped'
        @($paths) | Should -Be @($census.PSObject.Properties.Name | Where-Object { $_ -like 'skipped*' } | Sort-Object)
    }
    It 'behaelt Kategorien und Gruende im maskierten Bericht' {
        $m = Get-ReportData $Rep.AlleMasked.Report
        @($m.skipped.id) | Should -Be $Names; $m.skipped[0].text | Should -Be 'Prozesse wurden bei dieser Messung nicht erfasst.'; @($m.skipped[0].places) | Should -Be $Places.Prozesse
        ($m.sollIst | Where-Object id -eq 'ica.rtt').detail | Should -Be 'abgeschaltet (-Skip Citrix)'; ($m.quality.sources | Where-Object id -eq 'process').detail | Should -Be 'abgeschaltet (-Skip Prozesse)'
        [IO.File]::ReadAllText($Rep.AlleMasked.Report) | Should -Not -Match 'user0\d\d|SIM-VDA01|CONTOSO'
    }
}
Describe 'Vorfallserklaerungen und Muster mit weggelassenen Kategorien' {   # Review Focus 3
    BeforeAll { function Get-Ev($Data, [scriptblock]$Where) { @($Data.incidents | Where-Object { $_.type -eq 'ereignis' } | Where-Object $Where) } }   # nicht $d: PowerShell unterscheidet $d und $D nicht
    It 'nennt beim Verursacher den Grund statt fehlender Prozessdaten' {
        $rp = $D.Prozesse; $cpu = $rp.incidents | Where-Object lead -eq 'cpu'
        $cpu.cause.kind | Should -Be 'notmeasured'; $cpu.main | Should -BeNullOrEmpty
        $cpu.text | Should -BeLike '*Betroffen: 6 Sitzungen. Kein Hauptverursacher ermittelt: Prozesse wurden bei dieser Messung nicht erfasst.'
        $back = $rp.incidents | Where-Object { $_.type -eq 'ohne-engpass' -and @($_.affected).Count -eq 8 }
        $back.text | Should -BeLike '*Betroffen: 8 Sitzungen. Prozess mit der höchsten Verzögerung nicht ermittelt: Prozesse wurden bei dieser Messung nicht erfasst. Die Ursache liegt*Gegenstelle Oracle-Listener: *'
        @($rp.incidents | Where-Object { $_.text -match 'keine Prozessdaten' }).Count | Should -Be 0
        ($D.Voll.incidents | Where-Object lead -eq 'cpu').cause.kind | Should -Be 'main'
    }
    It 'sagt bei einer Verzoegerung ohne Engpass, was nicht geprueft wurde' {
        $back = $D.Gegenstellen.incidents | Where-Object { $_.type -eq 'ohne-engpass' -and @($_.affected).Count -eq 8 }
        $back.text | Should -BeLike '*(Datenbank, Proxy, Netz). Gegenstellen wurden bei dieser Messung nicht geprüft.'; @($back.endpoints).Count | Should -Be 0
        $late = @($D.Laufwerke.incidents | Where-Object type -eq 'ohne-engpass'); $late.Count | Should -Be 5
        foreach ($i in $late) { $i.text | Should -Match 'Nicht gemessen: Datenträger-Antwortzeit, Freigabe-Antwortzeit \(SMB\); ein Engpass dort ist nicht ausgeschlossen\.' }
    }
    It 'bildet kein Muster, das eine weggelassene Kategorie braucht, und sagt nicht "kein Muster"' {
        $p = (Get-Ev $D.Drucken { $_.event.kind -eq 'print' })[0]
        @($p.event.patterns).Count | Should -Be 0; @($p.event.unchecked | ForEach-Object { '{0}|{1}|{2}' -f $_.id, $_.category, $_.text }) | Should -Be @('printdriver|Drucken|Bezug zu einem Druckertreiber (Drucken nicht gemessen)')
        $p.text | Should -BeLike '*Nicht geprüft: Bezug zu einem Druckertreiber (Drucken nicht gemessen).'; $p.text | Should -Not -Match 'Kein Muster erkannt'
        $o = (Get-Ev $D.Prozesse { $_.event.app -eq 'OUTLOOK.EXE' })[0]
        @($o.event.patterns.id) | Should -Not -Contain 'manyusers'; @($o.event.unchecked.id) | Should -Be @('users')
        # erweitert: auch "Sitzung nicht ermittelt" entfaellt, den Grund nennt der Satz zum nicht geprueften Muster
        $o.text | Should -BeLike '*Nicht geprüft: Zuordnung zu Benutzern und Sitzungen (Prozesse nicht gemessen).'; $o.text | Should -Not -Match 'Ohne Benutzersitzung|Kein Muster erkannt|Sitzung nicht ermittelt'
        $pr = (Get-Ev $D.Prozesse { $_.event.kind -eq 'profileerror' })[0]   # nennt seinen Benutzer selbst
        @($pr.event.unchecked).Count | Should -Be 0; $pr.text | Should -Match 'Benutzer: user014\. Kein Muster erkannt\.'
        @(@($D.Prozesse.before.incidents) | Where-Object { @($_.event.patterns.id) -contains 'oneuser' }).Count | Should -Be 1   # der Rueckblick nennt Benutzer selbst
        @(@($D.Prozesse.before.incidents) | Where-Object { @($_.event.unchecked).Count -gt 0 }).Count | Should -Be 0
    }
    It 'bildet ohne Prozesse auch aus dem einzelnen Absturz mit unbekannter Sitzung einen Vorfall' {
        # ohne Prozesse ordnet der Collector keinem Absturz eine Sitzung zu; der einzelne Absturz von chrome.exe bleibt ein Vorfall
        @(Get-Ev $D.Prozesse { $true } | ForEach-Object { $_.event.kind + ':' + $_.event.app }) | Should -Be @('profileerror:', 'crash:chrome.exe', 'crash:OUTLOOK.EXE', 'print:spoolsv.exe')
        $c = (Get-Ev $D.Prozesse { $_.event.app -eq 'chrome.exe' })[0]
        @($c.event.patterns.id) | Should -Be @('resource', 'overlap'); @($c.event.unchecked.id) | Should -Be @('users')
        $c.text | Should -BeLike '*Zeitgleich mit Vorfall 3. Nicht geprüft: Zuordnung zu Benutzern und Sitzungen (Prozesse nicht gemessen).'
        $c.text | Should -Not -Match 'Ohne Benutzersitzung|Sitzung nicht ermittelt|Kein Muster erkannt'
        # jede Kombination hat die vier Ereignisvorfaelle der Messung, ausser ohne Ereignisse (dann keinen)
        foreach ($k in @('Voll') + $Names + 'Alle') {
            $want = $(if ($k -eq 'Ereignisse' -or $k -eq 'Alle') { 0 } else { 4 })
            @(Get-Ev $D[$k] { $true }).Count | Should -Be $want -Because $k
        }
    }
    It 'behaelt ein nicht geprueftes Muster im maskierten Bericht' {
        $out = Join-Path $TestDrive 'dm.html'; [void](& $Report -Path $Runs.Drucken -OutFile $out -RoleFile (Join-Path $TestDrive 'rep/roles.sim.json') -Mask Alles 6>$null)
        $u = (Get-Ev (Get-ReportData $out) { $_.event.kind -eq 'print' })[0].event.unchecked
        '{0}|{1}|{2}' -f $u[0].id, $u[0].category, $u[0].text | Should -Be 'printdriver|Drucken|Bezug zu einem Druckertreiber (Drucken nicht gemessen)'
    }
    It 'ordnet die Felder von unchecked im Bestand tests/MaskCensus.json ein' {
        $census = (Get-Content (Join-Path $PSScriptRoot 'MaskCensus.json') -Raw -Encoding UTF8 | ConvertFrom-Json).fields
        $paths = New-Object System.Collections.Generic.SortedSet[string] ([StringComparer]::Ordinal)
        $walk = { param($v, [string]$p)
            if ($null -eq $v -or $v -is [ValueType]) { return }
            if ($v -is [string]) { [void]$paths.Add($p); return }
            if ($v -is [System.Collections.IEnumerable]) { foreach ($x in $v) { & $walk $x "$p[]" }; return }
            foreach ($q in $v.PSObject.Properties) { & $walk $q.Value $(if ($p) { "$p.$($q.Name)" } else { $q.Name }) } }
        # ohne Drucken nennen Vorfaelle der Messung und des Rueckblicks ein Modul
        foreach ($i in @($D.Drucken.incidents)) { if ($null -ne $i.event) { & $walk @($i.event.unchecked) 'incidents[].event.unchecked' } }
        foreach ($i in @($D.Drucken.before.incidents)) { & $walk @($i.event.unchecked) 'before.incidents[].event.unchecked' }
        @($paths) | Should -Be @($census.PSObject.Properties.Name | Where-Object { $_ -like '*unchecked*' } | Sort-Object)
        @($paths | ForEach-Object { '{0}={1}' -f $_, $census.$_ }) | Should -Be @('before.incidents[].event.unchecked[].category=keyword', 'before.incidents[].event.unchecked[].id=keyword',
            'before.incidents[].event.unchecked[].text=composed', 'incidents[].event.unchecked[].category=keyword', 'incidents[].event.unchecked[].id=keyword', 'incidents[].event.unchecked[].text=composed')
        . (Join-Path $PSScriptRoot '../src/WorkerPerf.Mask.ps1'); $WorkerPerfMaskKeywordFields | Should -Contain 'unchecked.category'
    }
    It 'laesst ohne -Skip nichts ungeprueft und haelt Ereignisse und Rueckblick getrennt' {
        @(Get-Ev $D.Voll { @($_.event.unchecked).Count -gt 0 }).Count | Should -Be 0; @(Get-Ev $D.Voll { $true }).Count | Should -Be 4
        @($D.Voll.before.incidents | Where-Object { @($_.event.unchecked).Count -gt 0 }).Count | Should -Be 0
        # Aussage angepasst: der Rueckblick der simulierten Stunde hat seit der Korrekturrunde des Ereignisplans vier Vorfaelle
        @(Get-Ev $D.Ereignisse { $true }).Count | Should -Be 0; @($D.Ereignisse.before.incidents).Count | Should -Be 4
    }
}
