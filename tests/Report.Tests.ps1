BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1')
    $script:R = New-TestReports (Join-Path $TestDrive 'r')
    $script:D = Get-ReportData $R.Report
    $script:Exp = @(Get-Content (Join-Path $R.Run 'expected.json') -Raw | ConvertFrom-Json)
    function Find-Incident($Data, $E) {
        @($Data.incidents | Where-Object { $_.type -eq $E.Type -and [bool]$_.chronic -eq [bool]$E.Chronic -and $_.lead -eq $E.Lead -and
            [Math]::Abs($_.start - $E.StartMs) -le 20000 -and [Math]::Abs($_.end - $E.EndMs) -le 20000 })
    }
    function Get-Hit([string]$Key) { (Find-Incident $D ($Exp | Where-Object Key -eq $Key))[0] }
}
Describe 'Durchlauf Simulation -> Bericht' {
    It 'findet genau die Vorfaelle des Drehbuchs' {
        # Aussage geaendert (Task 8): der Vergleich laeuft ueber die Zeilen der Messzeit, weil expected.json jetzt auch den
        # Rueckblick nennt; die Ereignisvorfaelle der Messzeit stehen seit Task 8 im Bericht
        $D.incidents.Count | Should -Be @($Exp | Where-Object { -not $_.Before }).Count; $D.noFinding | Should -BeFalse
        foreach ($e in @($Exp | Where-Object { -not $_.Before })) {
            $hit = Find-Incident $D $e
            $hit.Count | Should -Be 1 -Because $e.Key
            if ($e.MainApp) { $hit[0].main.app | Should -Be $e.MainApp -Because $e.Key; $hit[0].main.user | Should -Be $e.MainUser -Because $e.Key }
            @($hit[0].affected).Count | Should -Be $e.Affected -Because $e.Key
        }
    }
    It 'beschreibt den CPU-Engpass im Klartext' {
        (Get-Hit 'cpu').text | Should -Match '^\d\d:\d\d:\d\d–\d\d:\d\d:\d\d: CPU-Engpass \(.+ Spitze .+, Soll .+\)\. Betroffen: 6 Sitzungen\. Hauptverursacher: EXCEL\.EXE in der Sitzung von user003 mit \d+ % der CPU-Zeit \(sonst \d+(,\d)? %\)\.'
    }
    It 'nennt den Dauerzustand einer Sitzung nicht bei Vorfaellen ohne diese Sitzung' {   # Task 14b, Punkt 2
        $i = Get-Hit 'cpu'
        @($i.chronicContext).Count | Should -Be 0; $i.text | Should -Not -Match 'Dauerhaft erhöht'
    }
    It 'fuehrt Speicher und Datentraeger in einem Vorfall' { (Get-Hit 'memory').resources | Should -Be @('memory', 'disk') }
    It 'nennt beim Speicher-Engpass den Prozess, der mit dem Vorfall endet' {          # Abschlussrunde C1
        $i = Get-Hit 'memory'
        $i.main.app | Should -Be 'ms-teams.exe'; $i.main.user | Should -Be 'user007'; $i.main.sharePct | Should -BeGreaterThan 35; $i.main.growthMB | Should -BeGreaterThan 20000
        $top = $i.contributors.memory.procs[0]; $top.name | Should -Be 'ms-teams.exe'
        $p = $D.procs | Where-Object k -eq $top.k
        $p.last | Should -BeLessThan $i.end                                         # im letzten Schnappschuss des Fensters ist der Prozess schon beendet
        $i.text | Should -Match 'Hauptverursacher: ms-teams\.exe in der Sitzung von user007 mit \d+ % des Arbeitsspeichers aller Prozesse \(Working Set\)'
    }
    It 'nennt den Begleiter beim Datentraeger-Engpass' {
        $i = Get-Hit 'disk'; $i.companion.label | Should -Be 'Microsoft Defender'; $i.scanActive | Should -BeTrue
    }
    It 'erkennt die Verzoegerung ohne Engpass samt Gegenstelle' {
        $i = Get-Hit 'backend'
        $i.delayProcs[0].name | Should -Be 'nexus.exe'; $i.resources | Should -Be @('endpoint')
        ($i.endpoints | Where-Object name -eq 'Oracle-Listener').maxMs | Should -BeGreaterOrEqual 200
        $i.text | Should -Match 'außerhalb des Workers'
    }
    It 'bewertet alle zwoelf Messwerte gegen das Soll' {
        $D.sollIst.Count | Should -Be 12; @($D.sollIst | Where-Object measured).Count | Should -Be 12
        ($D.sollIst | Where-Object id -eq 'cpu.host').max | Should -BeGreaterOrEqual 90
    }
    It 'weist Messqualitaet und Collector-Anteil aus' {
        $D.quality.skippedTicks | Should -Be 0; $D.quality.burstSnapshots | Should -BeGreaterThan 50
        $D.quality.collectorCpuPct | Should -BeGreaterThan 0; @($D.procs | Where-Object isCollector).Count | Should -Be 1
    }
    It 'benennt jede Datenquelle' {                                                   # Task 14b, Punkt 8
        @($D.quality.sources).Count | Should -BeGreaterThan 12
        @($D.quality.sources | Where-Object { $_.label -eq $_.id } | ForEach-Object { $_.id }) | Should -BeNullOrEmpty
    }
    It 'liefert Verlaeufe in voller Aufloesung' {
        $D.tickT.Count | Should -Be 1800; $D.host.cpu.Count | Should -Be 1800; $D.sessions[0].cpu.Count | Should -Be $D.snapT.Count
        $D.mainApp.label | Should -Be 'Nexus KIS'; $D.meta.usersPerCore | Should -Be 3.125
        ($D.volumes | Where-Object kind -eq 'profile').Count | Should -Be 25
    }
    It 'rechnet unter deutscher Kultur richtig' {                               # Review Focus 2
        $cpu = $D.sollIst | Where-Object id -eq 'cpu.host'
        $cpu.avg | Should -BeGreaterThan 30; $cpu.avg | Should -BeLessThan 50
        ($D.sessions | Measure-Object cpuShare -Sum).Sum | Should -BeGreaterThan 99
    }
    It 'bleibt unter 8 MB' { (Get-Item $R.Report).Length | Should -BeLessThan 8MB }
    It 'leitet die Bewertung der Messwerte aus den Befunden ab' {                    # Abschlussrunde I4
        ($D.sollIst | Where-Object id -eq 'cpu.host').status | Should -Be 2           # der CPU-Engpass ist ein kritischer Befund
        ($D.sollIst | Where-Object id -eq 'ica.rtt').status | Should -Be 1            # die Netzstrecke von user020 ist dauerhaft auffaellig
        ($D.sollIst | Where-Object id -eq 'cpu.steal').status | Should -Be 0; ($D.sollIst | Where-Object id -eq 'cpu.steal').exceeded | Should -BeFalse
        $D.unmeasured.input | Should -BeFalse; @($D.unmeasured.worker).Count | Should -Be 0
    }
    It 'nennt beim Dauerzustand der Netzstrecke nur Belege der eigenen Sitzung' {     # Abschlussrunde I2
        $i = Get-Hit 'homeoffice'; $own = @($i.signals | ForEach-Object { $_.s } | Sort-Object -Unique)
        $own.Count | Should -Be 1
        @($i.delayProcs | Where-Object { $_.s -ne $own[0] }).Count | Should -Be 0; @($i.endpoints).Count | Should -Be 0
        @($i.events).Count | Should -Be 0; $i.scanActive | Should -BeFalse; @($i.ica | Where-Object { $_.s -ne $own[0] }).Count | Should -Be 0
        $i.cause | Should -BeNullOrEmpty; $i.main | Should -BeNullOrEmpty
    }
    It 'gibt die Aussage zum Verursacher an die Seite weiter' {                       # Abschlussrunde I1 und I2
        $disk = Get-Hit 'disk'
        $disk.cause.kind | Should -Be 'main'; $disk.cause.measure | Should -Be 'io'; $disk.cause.scan | Should -BeTrue; $disk.cause.minSharePct | Should -Be 10
        $disk.text | Should -Match 'Hauptverursacher: robocopy\.exe in der Sitzung von user011 mit \d+ % der I/O-Menge \(sonst \d+(,\d)? %\)\. Begleiter: Microsoft Defender mit \d+ % der I/O-Menge; größter I/O-Erzeuger im Fenster: robocopy\.exe \(user011\)\. Scan-Ausschlüsse prüfen\.$'
        $profile = Get-Hit 'profile'
        $profile.contributors.profile.scope | Should -Be 'session'; $profile.text | Should -Match 'OUTLOOK\.EXE in der Sitzung von user009 mit \d+ % der I/O-Menge dieser Sitzung'
        (Get-Hit 'backend').cause | Should -BeNullOrEmpty
    }
}
Describe 'Fokus, kein Befund, Zeitausschnitt' {
    It 'hebt Vorfaelle des gemeldeten Benutzers und der gemeldeten Uhrzeit hervor' {
        $f = Get-ReportData $R.Focus
        $f.meta.focus.found | Should -BeTrue
        $cpu = $f.incidents | Where-Object lead -eq 'cpu'
        $cpu.focus | Should -BeTrue; $cpu.nearReported | Should -BeTrue
        @($f.incidents | Where-Object focus).Count | Should -Be 1
    }
    It 'meldet einen unbekannten Benutzer, ohne abzubrechen' {
        $out = Join-Path $TestDrive 'u.html'
        [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $R.Run -OutFile $out -FocusUser 'niemand' 6>$null)
        (Get-ReportData $out).meta.focus.found | Should -BeFalse
    }
    It 'sagt ausdruecklich, wenn nichts gefunden wurde' {
        $n = Get-ReportData $R.None; $n.noFinding | Should -BeTrue; $n.incidents.Count | Should -Be 0; $n.sollIst.Count | Should -Be 12
        @($n.sollIst | Where-Object { $_.exceeded -or $_.status -ne 0 }).Count | Should -Be 0
    }
    It 'nennt einzelne Ueberschreitungen ohne Befund, statt sie zu verneinen' {       # Abschlussrunde I4
        $n = Get-ReportData $R.Spike; $n.noFinding | Should -BeTrue; $n.incidents.Count | Should -Be 0
        $cpu = $n.sollIst | Where-Object id -eq 'cpu.host'
        $cpu.max | Should -Be 96.5; $cpu.pctCrit | Should -BeGreaterThan 0; $cpu.status | Should -Be 0; $cpu.exceeded | Should -BeTrue
        @($n.sollIst | Where-Object exceeded).id | Should -Be @('cpu.host')
        @($n.sollIst | Where-Object { -not $_.measured }).id | Should -Be @('ica.rtt', 'ica.latency')
    }
    It 'sagt bei einem Engpass ohne Prozessdaten und ohne gemessene Eingabeverzoegerung, was fehlt' {   # Abschlussrunde I1, I2 und I3
        $n = Get-ReportData $R.NoData
        $i = @($n.incidents | Where-Object { $_.type -eq 'engpass' -and $_.lead -eq 'cpu' }); $i.Count | Should -Be 1
        $i[0].cause.kind | Should -Be 'nodata'; $i[0].main | Should -BeNullOrEmpty; $n.unmeasured.input | Should -BeTrue
        $i[0].text | Should -Match 'CPU-Engpass \(.+\)\. Eingabeverzögerung nicht gemessen; betroffene Sitzungen sind nicht bestimmbar\. Kein Hauptverursacher ermittelt: im Fenster liegen keine Prozessdaten vor\.$'
    }
    It 'schliesst einen Engpass in einer nicht gemessenen Worker-Ressource nicht aus' {   # Abschlussrunde I3
        $disk = $Exp | Where-Object Key -eq 'disk'; $out = Join-Path $TestDrive 'novol.html'
        $bare = Copy-SimRun $R.Run (Join-Path $TestDrive 'novol') @('volumes.csv')
        [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $bare -OutFile $out -From (Get-ServerTime $R.Run ($disk.StartMs - 60000)) -To (Get-ServerTime $R.Run ($disk.EndMs + 60000)) 6>$null)
        $n = Get-ReportData $out
        $n.unmeasured.worker | Should -Be @('Datenträger-Antwortzeit'); ($n.sollIst | Where-Object id -eq 'disk.latency').measured | Should -BeFalse
        $i = @($n.incidents | Where-Object type -eq 'ohne-engpass'); $i.Count | Should -Be 1
        $i[0].text | Should -Match 'Kein Engpass in den gemessenen Worker-Ressourcen\. Nicht gemessen: Datenträger-Antwortzeit; ein Engpass dort ist nicht ausgeschlossen\.'
        $i[0].text | Should -Not -Match 'außerhalb des Workers'
    }
    It 'wertet einen Zeitausschnitt aus' {
        $out = Join-Path $TestDrive 'cut.html'; $from = [DateTimeOffset]::FromUnixTimeMilliseconds($R.StartMs + 240000).LocalDateTime
        [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $R.Run -OutFile $out -From $from -To $from.AddMinutes(4) 6>$null)
        $c = Get-ReportData $out
        $c.incidents.Count | Should -Be 2; @($c.incidents | Where-Object chronic).Count | Should -Be 0     # vier Minuten sind kein Dauerzustand
        ($c.incidents | Where-Object type -eq 'engpass').lead | Should -Be 'cpu'
    }
    It 'nennt beim Speicher-Engpass denselben Hauptverursacher mit demselben Anteil, auch wenn der Ausschnitt kurz vor oder nach einem Stuetzpunkt beginnt' {   # Abschlussrunde I5
        $mem = $Exp | Where-Object Key -eq 'memory'; $full = Get-Hit 'memory'
        # der Stuetzpunkt im Speicher-Fenster (15 s nach dessen Beginn); Uhrzeiten als Ortszeit des Servers
        $key = @(Import-Csv (Join-Path $R.Run 'snapshots.csv') | Where-Object Kind -eq 'K' | ForEach-Object { [DateTimeOffset]::Parse($_.Timestamp, [cultureinfo]::InvariantCulture) } |
            Where-Object { $_.ToUnixTimeMilliseconds() -gt $mem.StartMs -and $_.ToUnixTimeMilliseconds() -lt $mem.EndMs })[0]
        $key | Should -Not -BeNullOrEmpty
        foreach ($shift in -5, 5) {
            $out = Join-Path $TestDrive "mem$shift.html"
            [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $R.Run -OutFile $out -From $key.AddSeconds($shift).DateTime -To $key.AddMinutes(8).DateTime 6>$null)
            $c = Get-ReportData $out
            $i = @($c.incidents | Where-Object lead -eq 'memory'); $i.Count | Should -Be 1 -Because "Schnitt $shift s"
            $i[0].main.app | Should -Be $full.main.app -Because "Schnitt $shift s"; $i[0].main.user | Should -Be $full.main.user
            [Math]::Abs($i[0].main.sharePct - $full.main.sharePct) | Should -BeLessOrEqual 0.2 -Because "Schnitt $shift s"
            $fullTop = @($full.contributors.memory.sessions | ForEach-Object { '{0}:{1:0}' -f $_.user, $_.sharePct })
            @($i[0].contributors.memory.sessions | ForEach-Object { '{0}:{1:0}' -f $_.user, $_.sharePct }) | Should -Be $fullTop -Because "Schnitt $shift s"
            # jeder Prozess, der am ersten Schnappschuss des Ausschnitts lebt, hat dort einen Speicherwert
            @($c.procs | Where-Object { $_.o -eq 0 -and $null -eq $_.ws[0] }).Count | Should -Be 0 -Because "Schnitt $shift s"
        }
    }
    It 'ersetzt einen vorhandenen Bericht ohne Reste' {                          # Task 14a: delete and move, no *.tmp
        $dir = Join-Path $TestDrive 'over'; [void](New-Item -ItemType Directory $dir)
        $out = Join-Path $dir 'report.html'; Copy-Item $R.Report $out
        $from = [DateTimeOffset]::FromUnixTimeMilliseconds($R.StartMs + 240000).LocalDateTime
        [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $R.Run -OutFile $out -From $from -To $from.AddMinutes(4) 6>$null)
        (Get-ReportData $out).tickT.Count | Should -BeLessThan $D.tickT.Count
        @(Get-ChildItem -LiteralPath $dir -Filter '*.tmp').Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $dir).Count | Should -Be 1
    }
    It 'nennt den fehlerhaften Schwellwert' {
        $bad = Join-Path $TestDrive 'bad.json'; [IO.File]::WriteAllText($bad, '{"thresholds":[{"id":"cpu.host"}]}')
        { & (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $R.Run -OutFile (Join-Path $TestDrive 'x.html') -ThresholdFile $bad 6>$null } | Should -Throw '*cpu.host*'
    }
}
Describe 'Kleine Aufzeichnung: Maskierung, Fokus, Uhrzeit, Fehlermeldungen' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'LoadHelpers.ps1')
        $script:Report = Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1'
        $script:Base = [DateTimeOffset]'2026-01-15T08:00:00+02:00'                  # Server-Versatz 120 Minuten
        $script:Nasty = '</script> <b>&amp; "q" back\slash ' + [char]1 + " tab`t " + [char]::ConvertFromUtf32(0x1F600) + ' ' + [char]0x2028 + ' Ende'
        $csv = Format-WorkerPerfCsvText $Nasty
        $sess = 0..3 | ForEach-Object { "$_,2,user1,DOM,Active,ICA-1,CL1,,0" }
        $script:Small = Write-TestRun 'small' @{
            'ticks.csv' = @(0..7 | ForEach-Object { New-TickLine $_ }); 'snapshots.csv' = @(0..3 | ForEach-Object { New-SnapLine $_ $(if ($_ -eq 0) { 'K' } else { 'R' }) })
            'sessions.csv' = $sess; 'procinfo.csv' = @("0,100,1,EXCEL.EXE,2,,C:\x.exe,,$csv"); 'processes.csv' = @('0,0,100,1024,1024,0,0,0,10,2')
            'events.csv' = @("$(Get-Ts 5),Test,1,info,$csv")
        }
        function Invoke-Small([string]$Name, [hashtable]$Extra = @{}) {
            $out = Join-Path $TestDrive "$Name.html"
            [void](& $Report -Path $Small -OutFile $out @Extra 6>$null); $out
        }
        $script:SmallHtml = Invoke-Small 'small'
    }
    It 'maskiert Sonderzeichen im Datenblock' {
        $text = [IO.File]::ReadAllText($SmallHtml); $open = '<script id="wp-data" type="application/json">'
        $a = $text.IndexOf($open) + $open.Length; $block = $text.Substring($a, $text.IndexOf('</script>', $a) - $a)
        $block.IndexOfAny([char[]]@('<', '>', '&', [char]0x2028)) | Should -Be -1
        ([regex]::Matches($text, '</script>')).Count | Should -Be 2
        $d = Get-ReportData $SmallHtml
        $d.procs[0].cmd | Should -BeExactly $Nasty; $d.events[0].text | Should -BeExactly $Nasty
    }
    It 'findet den Fokus-Benutzer als Domaene\Benutzer ohne Ruecksicht auf Schreibweise' {
        (Get-ReportData (Invoke-Small 'dom' @{ FocusUser = 'dom\USER1' })).meta.focus.found | Should -BeTrue
    }
    It 'rechnet die gemeldete Uhrzeit mit dem Versatz des Servers um' {
        $expected = ([DateTimeOffset]'2026-01-15T08:00:10+02:00').ToUnixTimeMilliseconds()
        foreach ($kind in 'Unspecified', 'Utc') {
            $t = [datetime]::SpecifyKind([datetime]'2026-01-15 08:00:10', $kind)
            (Get-ReportData (Invoke-Small "rt$kind" @{ ReportedTime = $t })).meta.focus.reportedMs | Should -Be $expected -Because $kind
        }
    }
    It 'liest -From und -To als Ortszeit des Servers' {                               # Abschlussrunde Minor 3: der Server liegt zwei Stunden vor UTC
        $d = Get-ReportData (Invoke-Small 'cutsrv' @{ From = [datetime]'2026-01-15 08:00:09'; To = [datetime]'2026-01-15 08:00:13' })
        $d.tickT.Count | Should -Be 2
        $d.meta.start | Should -Be ([DateTimeOffset]'2026-01-15T08:00:10+02:00').ToUnixTimeMilliseconds()
        { Invoke-Small 'cutout' @{ From = [datetime]'2026-01-15 10:00:09' } } | Should -Throw '*liegt ausserhalb der Aufzeichnung (15.01.2026 08:00:02 bis 15.01.2026 08:00:16, Ortszeit des Servers)*'
    }
    It 'nennt einen fehlenden Aufzeichnungsordner' {
        { & $Report -Path (Join-Path $TestDrive 'fehlt') -OutFile (Join-Path $TestDrive 'y.html') 6>$null } | Should -Throw '*Aufzeichnungsordner*'
    }
    It 'nennt einen fehlenden Ausgabeordner' {
        { & $Report -Path $Small -OutFile (Join-Path $TestDrive 'fehlt/z.html') 6>$null } | Should -Throw '*Ausgabeordner*'
    }
}
Describe 'Ereignisvorfaelle im Bericht' {
    It 'bildet die Ereignisvorfaelle und Muster des Drehbuchs' {
        foreach ($e in @($Exp | Where-Object { $_.Type -eq 'ereignis' })) {
            $pool = if ($e.Before) { $D.before.incidents } else { $D.incidents }
            $hit = @($pool | Where-Object { $_.type -eq 'ereignis' -and $_.event.kind -eq $e.Kind -and [Math]::Abs($_.start - $e.StartMs) -le 20000 })
            $hit.Count | Should -Be 1 -Because $e.Key
            @($hit[0].event.patterns | ForEach-Object { $_.id }) | Should -Be @($e.Patterns) -Because $e.Key
        }
    }
    It 'nennt Anwendung, Modul, Benutzer und die Aussagen der Muster' {
        $i = $D.incidents | Where-Object { $_.event -and $_.event.app -eq 'OUTLOOK.EXE' }
        $i.event.count | Should -Be 3; $i.event.users | Should -Be @('user010', 'user011', 'user012'); $i.event.sameModule | Should -BeTrue
        $i.text | Should -Match 'Absturz von OUTLOOK\.EXE \(3-mal\)\..*olmapi32\.dll, immer dasselbe.*3 Benutzer betroffen: spricht für Installation oder Update\.'
        $m = $D.incidents | Where-Object { $_.event -and $_.event.app -eq 'chrome.exe' }
        $mem = $D.incidents | Where-Object lead -eq 'memory'
        $m.event.overlap | Should -Be @($mem.id); $mem.eventIncidents | Should -Be @($m.id); $m.text | Should -Match 'Wahrscheinlich Folge des Speichermangels\.'
        ($D.incidents | Where-Object { $_.event -and $_.event.kind -eq 'profileerror' }).text | Should -Match 'Kein Muster erkannt\.$'
    }
    It 'liefert Rueckblick, Druckzustand und Sitzungsereignisse' {
        # C1: the crash of the lookback without session and account is an incident of its own, worded as unknown session
        $ns = @($D.before.incidents | Where-Object { $_.event.app -eq 'simscan.exe' })
        $ns.Count | Should -Be 1; $ns[0].severity | Should -Be 1; $ns[0].event.sessionUnknown | Should -BeTrue
        $ns[0].text | Should -Match 'Absturz von simscan\.exe \(1-mal\)\. Sitzung nicht ermittelt\. .*Kein Muster erkannt\.$'
        $D.before.days | Should -Be 7; $D.before.eventCount | Should -Be 6; ($D.before.perDay | Measure-Object count -Sum).Sum | Should -Be 6   # C1: ein Absturz ohne Sitzung dazu
        ($D.print.drivers | Where-Object involved).name | Should -Be 'HP Universal Printing PCL 6 (Sim)'
        ($D.print.queues | Where-Object name -eq 'PRN-EG-01').maxJobs | Should -Be 3; ($D.print.queues | Where-Object name -eq 'PRN-EG-01').jobErrors | Should -Be 1
        @($D.print.processes).name | Should -Contain 'spoolsv.exe'
        $s = $D.sessions | Where-Object user -eq 'user014'; @($s.events | ForEach-Object { $D.events[$_].kind }) | Should -Be @('logoff', 'logon')
        ($D.events | Where-Object app -eq 'chrome.exe').user | Should -Be 'user008'
    }
    It 'laesst die acht Leistungsvorfaelle mit und ohne die neuen Ereignisse gleich' {
        $dir = Copy-SimRun $R.Run (Join-Path $TestDrive 'onlysec') @('events_before.csv')
        $f = Join-Path $dir 'events.csv'; $lines = [IO.File]::ReadAllLines($f)
        [IO.File]::WriteAllLines($f, @($lines[0]) + @($lines | Select-Object -Skip 1 | Where-Object { (Split-WorkerPerfCsvLine $_)[5] -eq 'security' }))
        $out = Join-Path $TestDrive 'onlysec.html'; [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $dir -OutFile $out -RoleFile (Join-Path $TestDrive 'r/roles.sim.json') 6>$null)
        $strip = { param($i) $c = $i.PSObject.Copy(); $c.PSObject.Properties.Remove('eventIncidents'); $c.PSObject.Properties.Remove('events'); $c | ConvertTo-Json -Depth 8 }
        $a = @($D.incidents | Where-Object type -ne 'ereignis'); $b = @((Get-ReportData $out).incidents)
        $b.Count | Should -Be 8; for ($k = 0; $k -lt 8; $k++) { & $strip $a[$k] | Should -Be (& $strip $b[$k]) }
    }
    It 'wertet eine Aufzeichnung im Format 2 weiter aus' {
        $dir = Copy-SimRun $R.Run (Join-Path $TestDrive 'v2') @('events_before.csv', 'printdrivers.csv', 'printqueues.csv')
        $meta = Join-Path $dir 'meta.json'; [IO.File]::WriteAllText($meta, ([IO.File]::ReadAllText($meta) -replace '"SchemaVersion":\s*3', '"SchemaVersion": 2'))
        $f = Join-Path $dir 'events.csv'
        $rows = @([IO.File]::ReadAllLines($f) | Select-Object -Skip 1 | ForEach-Object { $x = Split-WorkerPerfCsvLine $_; if ($x[5] -eq 'security') { '{0},{1},{2},{3},{4}' -f $x[0], $x[2], $x[3], $x[6], $x[19] } })
        [IO.File]::WriteAllLines($f, @('Timestamp,Source,EventId,Kind,Text') + $rows)
        $out = Join-Path $TestDrive 'v2.html'; [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $dir -OutFile $out 6>$null)
        $d2 = Get-ReportData $out; @($d2.incidents | Where-Object type -eq 'ereignis').Count | Should -Be 0; @($d2.incidents).Count | Should -Be 8
        @($d2.before.incidents).Count | Should -Be 0; @($d2.print.drivers).Count | Should -Be 0
    }
}
Describe 'Ereignisdaten im Einzelnen' {
    It 'gibt jedes Ereignis mit seinem eigenen Zeitversatz aus und laesst leere Textfelder weg' {
        # Aussage geaendert (Task 8, Runde 1): ein leeres Feld fehlt im Datensatz (die Anmeldung hat keine Anwendung)
        @($D.events[0].PSObject.Properties.Name) | Should -Be @('t', 'offsetMin', 'log', 'source', 'id', 'level', 'group', 'kind', 's', 'user', 'text')
        $sp = $D.events | Where-Object { $_.PSObject.Properties['app'] -and $_.app -eq 'spoolsv.exe' }
        @($sp.PSObject.Properties.Name) | Should -Be @('t', 'offsetMin', 'log', 'source', 'id', 'level', 'group', 'kind', 'app', 'module', 'code', 's', 'text')
        $v2 = $D.events | Where-Object kind -eq 'scan-start'
        @($v2.PSObject.Properties.Name) | Should -Be @('t', 'offsetMin', 'log', 'source', 'id', 'level', 'group', 'kind', 's', 'text')
        @($D.events).Count | Should -Be 13; @($D.events | Where-Object { $_.offsetMin -ne $D.meta.offsetMin }).Count | Should -Be 0
        $c = $D.events | Where-Object app -eq 'chrome.exe'
        $c.module | Should -Be 'chrome.dll'; $c.code | Should -Be '0xc0000017'; $c.s | Should -BeGreaterOrEqual 0; $D.sessions[$c.s].user | Should -Be 'user008'
        ($D.events | Where-Object app -eq 'spoolsv.exe').s | Should -Be -1
    }
    It 'nennt in Leistungsvorfaellen keine Anwendungs-, Dienst- und Sitzungsereignisse' {
        $groups = @($D.incidents | Where-Object type -ne 'ereignis' | ForEach-Object { $_.events } | ForEach-Object { $_.group })
        $groups | Should -Not -Contain 'app'; $groups | Should -Not -Contain 'session'; $groups | Should -Not -Contain 'service'
        # der Absturz von chrome.exe im Fenster des Speicher-Engpasses ist ein eigener Vorfall mit gegenseitigem Verweis
        @((Get-Hit 'memory').events).Count | Should -Be 0; @((Get-Hit 'memory').eventIncidents).Count | Should -Be 1
    }
    It 'gibt Ereignisvorfaellen alle Schluessel eines Leistungsvorfalls und den Leistungsvorfaellen den Schluessel event' {
        $perf = @($D.incidents | Where-Object type -ne 'ereignis')[0]; $ev = @($D.incidents | Where-Object type -eq 'ereignis')[0]
        foreach ($k in $perf.PSObject.Properties.Name) { $ev.PSObject.Properties.Name | Should -Contain $k }
        $perf.event | Should -BeNullOrEmpty; @($perf.eventIncidents).Count | Should -BeGreaterOrEqual 0
        $ev.chronic | Should -BeFalse; $ev.lead | Should -BeNullOrEmpty; @($ev.resources).Count | Should -Be 0; $ev.security.totalPct | Should -BeNullOrEmpty
        @($D.incidents.id) | Should -Be @(1..12); @($D.before.incidents.id) | Should -Be @(13..16)   # C1: der Absturz ohne Sitzung im Rueckblick
        @($D.incidents | Where-Object type -ne 'ereignis').Count | Should -Be 8; @($D.incidents)[8].type | Should -Be 'ereignis'
    }
    It 'gibt die Aussagen der Muster einzeln und die Einzelheiten mit kleinen Schluesseln aus' {
        $p = ($D.incidents | Where-Object { $_.event -and $_.event.kind -eq 'print' }).event.patterns[0]
        $p.id | Should -Be 'printdriver'; $p.text | Should -BeExactly 'Das Modul hpsimgr.dll gehört zum Druckertreiber HP Universal Printing PCL 6 (Sim).'
        $p.detail.module | Should -Be 'hpsimgr.dll'; $p.detail.driver | Should -Be 'HP Universal Printing PCL 6 (Sim)'
        $r = ($D.incidents | Where-Object { $_.event -and $_.event.app -eq 'chrome.exe' }).event.patterns | Where-Object id -eq 'resource'
        $r.detail.signalId | Should -BeIn @('mem.used', 'mem.commit'); $r.detail.peak | Should -BeGreaterThan 0
        $sh = $D.before.incidents | Where-Object { $_.event.app -eq 'EXCEL.EXE' }
        $sh.event.before | Should -BeTrue; $sh.text | Should -Match '^\d\d\.\d\d\.\d{4} '; @($sh.event.patterns[0].detail.apps) | Should -Be @('EXCEL.EXE', 'WINWORD.EXE')
    }
    It 'liefert den Druckzustand mit beiden Beteiligungen und dem Verlauf der Druckprozesse' {
        $drv = $D.print.drivers[0]
        @($drv.PSObject.Properties.Name) | Should -Be @('name', 'manufacturer', 'version', 'type', 'isolation', 'isolated', 'files', 'involved', 'possiblyInvolved')
        @($D.print.drivers | Where-Object possiblyInvolved).Count | Should -Be 0; $drv.files | Should -Be @('hpsimgr.dll', 'hpsimui.dll')
        $sp = @($D.print.processes | Where-Object name -eq 'spoolsv.exe')[0]
        $proc = $D.procs | Where-Object k -eq $sp.k; $proc | Should -Not -BeNullOrEmpty
        $ws = @($proc.ws | Where-Object { $null -ne $_ })
        $sp.wsStartMB | Should -Be ([Math]::Round($ws[0])); $sp.wsEndMB | Should -Be ([Math]::Round($ws[-1])); $sp.wsMaxMB | Should -BeGreaterOrEqual $sp.wsEndMB
        $D.before.incidentEventCount | Should -Be 6; $D.before.from | Should -Be ($D.meta.start - 7 * 86400000)
    }
    It 'nennt im Rueckblick die Ereignisse um eine gemeldete Uhrzeit mit dem Zeitversatz des Ereignisses' {
        # die Absturzreihe von nexus.exe vor der Messung mit einem Versatz eine Stunde ueber dem der Messung (Sommerzeit)
        $dir = Copy-SimRun $R.Run (Join-Path $TestDrive 'dst'); $f = Join-Path $dir 'events_before.csv'; $lines = [IO.File]::ReadAllLines($f)
        $off = [DateTimeOffset]::Parse((Split-WorkerPerfCsvLine $lines[1])[0], [cultureinfo]::InvariantCulture).Offset.Add([TimeSpan]::FromHours(1))
        for ($i = 1; $i -lt $lines.Count; $i++) {
            $x = Split-WorkerPerfCsvLine $lines[$i]
            if ($x[7] -ne 'nexus.exe') { continue }
            $ts = [DateTimeOffset]::Parse($x[0], [cultureinfo]::InvariantCulture).ToOffset($off).ToString('yyyy-MM-ddTHH:mm:ss.fffffffzzz', [cultureinfo]::InvariantCulture)
            $lines[$i] = $ts + $lines[$i].Substring($lines[$i].IndexOf(','))
        }
        [IO.File]::WriteAllLines($f, $lines)
        $nexus = $Exp | Where-Object Key -eq 'before.oneuser'
        $wall = [DateTimeOffset]::FromUnixTimeMilliseconds($nexus.StartMs + 300000).ToOffset($off).DateTime
        $out = Join-Path $TestDrive 'dst.html'; [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $dir -OutFile $out -RoleFile (Join-Path $TestDrive 'r/roles.sim.json') -ReportedTime $wall 6>$null)
        $b = (Get-ReportData $out).before
        @($b.near | ForEach-Object { $_.app }) | Should -Be @('nexus.exe', 'nexus.exe', 'nexus.exe'); @($b.nearCapture).Count | Should -Be 0
        @($b.near)[0].offsetMin | Should -Be $off.TotalMinutes
        ($b.incidents | Where-Object { $_.event.app -eq 'nexus.exe' }).nearReported | Should -BeTrue
        @($b.incidents | Where-Object nearReported).Count | Should -Be 1
    }
    It 'nennt bei einer gemeldeten Uhrzeit kurz vor der Messung auch die Ereignisse der Messung' {
        $wall = Get-ServerTime $R.Run ($D.meta.start - 300000)
        $out = Join-Path $TestDrive 'pre.html'; [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $R.Run -OutFile $out -RoleFile (Join-Path $TestDrive 'r/roles.sim.json') -ReportedTime $wall 6>$null)
        $pre = Get-ReportData $out
        @($pre.before.near | ForEach-Object { $_.kind }) | Should -Be @('logoff', 'logon', 'profileerror')
        @($pre.before.nearCapture | ForEach-Object { $pre.events[$_].kind }) | Should -Be @('logoff', 'logon', 'profileerror')
        ($pre.incidents | Where-Object { $_.event -and $_.event.kind -eq 'profileerror' }).nearReported | Should -BeTrue
        @($pre.incidents | Where-Object { $_.type -eq 'ereignis' -and $_.nearReported }).Count | Should -Be 1
    }
    It 'hebt Ereignisvorfaelle des gemeldeten Benutzers hervor' {
        $out = Join-Path $TestDrive 'fu.html'; [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $R.Run -OutFile $out -RoleFile (Join-Path $TestDrive 'r/roles.sim.json') -FocusUser 'CONTOSO\USER011' 6>$null)
        $fu = Get-ReportData $out
        @($fu.incidents | Where-Object { $_.type -eq 'ereignis' -and $_.focus } | ForEach-Object { $_.event.app }) | Should -Be @('OUTLOOK.EXE')
        $out = Join-Path $TestDrive 'fu4.html'; [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $R.Run -OutFile $out -RoleFile (Join-Path $TestDrive 'r/roles.sim.json') -FocusUser 'user004' 6>$null)
        @((Get-ReportData $out).before.incidents | Where-Object focus | ForEach-Object { $_.event.app }) | Should -Be @('nexus.exe')
    }
    It 'hebt nichts hervor, wenn der gemeldete Benutzer nicht gefunden wird, und vergleicht wie die Sitzungssuche' {
        foreach ($u in 'OTHER\user008', 'OTHER\user004', 'niemand') {
            $out = Join-Path $TestDrive 'fx.html'; [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $R.Run -OutFile $out -RoleFile (Join-Path $TestDrive 'r/roles.sim.json') -FocusUser $u 6>$null)
            $fx = Get-ReportData $out
            $fx.meta.focus.found | Should -BeFalse -Because $u
            @($fx.incidents | Where-Object focus).Count | Should -Be 0 -Because $u; @($fx.before.incidents | Where-Object focus).Count | Should -Be 0 -Because $u
        }
        $dom = @($D.sessions | Where-Object user -eq 'user004')[0].domain
        $out = Join-Path $TestDrive 'fd.html'; [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $R.Run -OutFile $out -RoleFile (Join-Path $TestDrive 'r/roles.sim.json') -FocusUser "$dom\USER004" 6>$null)
        @((Get-ReportData $out).before.incidents | Where-Object focus | ForEach-Object { $_.event.app }) | Should -Be @('nexus.exe')
    }
    It 'nennt im Rueckblick bei einer mehrdeutigen Uhrzeit am Ende der Sommerzeit die Ereignisse beider Lesarten' {
        # EXCEL.EXE um 02:20 Sommerzeit (+01:00) und WINWORD.EXE um 02:35 Winterzeit (+00:00) desselben Tages: 02:30 liegt bei beiden
        $dir = Copy-SimRun $R.Run (Join-Path $TestDrive 'amb'); $f = Join-Path $dir 'events_before.csv'; $lines = [IO.File]::ReadAllLines($f)
        $day = (Split-WorkerPerfCsvLine $lines[1])[0].Substring(0, 10)
        $lines[1] = $day + 'T02:20:00.0000000+01:00' + $lines[1].Substring($lines[1].IndexOf(','))
        $lines[2] = $day + 'T02:35:00.0000000+00:00' + $lines[2].Substring($lines[2].IndexOf(','))
        [IO.File]::WriteAllLines($f, $lines)
        $out = Join-Path $TestDrive 'amb.html'
        [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $dir -OutFile $out -RoleFile (Join-Path $TestDrive 'r/roles.sim.json') -ReportedTime ([datetime]::ParseExact("$day 02:30:00", 'yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture)) 6>$null)
        $b = (Get-ReportData $out).before
        @($b.near | ForEach-Object { $_.app }) | Should -Be @('EXCEL.EXE', 'WINWORD.EXE')
        @($b.incidents | Where-Object nearReported | ForEach-Object { $_.event.app }) | Should -Be @('EXCEL.EXE', 'WINWORD.EXE')
    }
    It 'beginnt den Rueckblick unter einem Zeitausschnitt mit dem Beginn der Aufzeichnung und zaehlt die herausgeschnittenen Ereignisse' {
        $from = Get-ServerTime $R.Run ($D.meta.start + 20 * 60000)
        $out = Join-Path $TestDrive 'lbcut.html'; [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $R.Run -OutFile $out -RoleFile (Join-Path $TestDrive 'r/roles.sim.json') -From $from 6>$null)
        $c = Get-ReportData $out
        $c.before.from | Should -Be $D.before.from; $c.before.eventCount | Should -Be 6
        $cut = @($D.events | Where-Object { $_.t -lt $c.meta.start }).Count; $cut | Should -BeGreaterThan 0
        $c.eventsOutsideCut | Should -Be $cut; @($c.events).Count | Should -Be (13 - $cut); $D.eventsOutsideCut | Should -Be 0
        # the start of the capture stays the first tick under the cut, so the page need not take the cut for the start (Task 9, C1)
        $D.before.captureStart | Should -Be $D.meta.start; $c.before.captureStart | Should -Be $D.before.captureStart
        $c.before.captureStart | Should -BeLessThan $c.meta.start
    }
    It 'sagt, ob der Rueckblick gelesen, abgeschaltet, nicht verfuegbar oder nicht aufgezeichnet ist' {     # Task 9, I1
        $D.before.status | Should -Be 'read'
        # changed in fix round 2 (N2): a missing file has its own status, the sources of this capture were available
        (Get-ReportData $R.None).before.status | Should -Be 'missingFile'          # ohne events_before.csv
        # Aussage geaendert (M10): ein Protokoll ohne Eintraege im Katalog wird nicht gelesen und nicht genannt
        @($D.before.logs | ForEach-Object { $_.id }) | Should -Be @('application', 'system', 'printservice', 'smbclient', 'defender', 'applocker')
        @($D.quality.sources | Where-Object { $_.id -eq 'events.profileservice' }).Count | Should -Be 0
        @($D.before.logs | Where-Object { -not $_.available }).Count | Should -Be 0
        @($D.before.logs | Where-Object id -eq 'application')[0].label | Should -Be 'Ereignisprotokoll Anwendung' 
        function New-MetaVariant([string]$Name, [scriptblock]$Change, [switch]$HeaderOnly) {
            $dir = Copy-SimRun $R.Run (Join-Path $TestDrive $Name); $f = Join-Path $dir 'meta.json'
            if ($HeaderOnly) { $lb = Join-Path $dir 'events_before.csv'; [IO.File]::WriteAllLines($lb, @([IO.File]::ReadAllLines($lb)[0])) }
            $m = Get-Content $f -Raw | ConvertFrom-Json; & $Change $m; [IO.File]::WriteAllText($f, ($m | ConvertTo-Json -Depth 8))
            $out = Join-Path $TestDrive "$Name.html"
            [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $dir -OutFile $out -RoleFile (Join-Path $TestDrive 'r/roles.sim.json') 6>$null)
            (Get-ReportData $out).before
        }
        (New-MetaVariant 'lboff' { param($m) $m.EventLookbackDays = 0 }).status | Should -Be 'off'
        # the Windows source of today lists no lookback log apart from Defender and AppLocker and writes only the header line
        $win = New-MetaVariant 'lbwin' { param($m) foreach ($id in 'application', 'system', 'printservice', 'smbclient') { $m.Sources.PSObject.Properties.Remove("events.$id") } } -HeaderOnly
        $win.status | Should -Be 'unavailable'
        # read and empty: every lookback log listed and available, the file holds only its header line
        (New-MetaVariant 'lbempty' { param($m) } -HeaderOnly).status | Should -Be 'read'
        (New-MetaVariant 'lbfmt2' { param($m) $m.PSObject.Properties.Remove('EventLookbackDays') }).status | Should -Be 'notRecorded'
        # fix round 2 (N1): five lookback logs listed as not available, Defender and AppLocker available, header only
        $part = New-MetaVariant 'lbpart' { param($m) foreach ($id in 'application', 'system', 'printservice', 'smbclient') { $m.Sources."events.$id".Available = $false } } -HeaderOnly
        $part.status | Should -Be 'partial'
        @($part.logs | Where-Object available | ForEach-Object { $_.id }) | Should -Be @('defender', 'applocker')
        # the same with the lookback rows of the simulation: still partial, never read
        (New-MetaVariant 'lbpart2' { param($m) $m.Sources.'events.system'.Available = $false }).status | Should -Be 'partial'
    }
    It 'zeigt die Zaehler der Ereignis-Abrufe, Lesefehler je Protokoll und den Rueckblick eines abgeschalteten Protokolls (I5, M5, M13, M14)' {
        $dir = Copy-SimRun $R.Run (Join-Path $TestDrive 'reads'); $f = Join-Path $dir 'meta.json'
        $m = Get-Content $f -Raw | ConvertFrom-Json
        $cnt = { param($s, $u, $d) [pscustomobject]@{ SkippedRecords = $s; UnformattedMessages = $u; DroppedEvents = $d } }
        $m | Add-Member -Force EventReadCounts ([pscustomobject]@{ application = (& $cnt 3 0 1000); system = (& $cnt 0 0 0); defender = (& $cnt 0 2 0) })
        $m | Add-Member -Force LookbackReadCounts ([pscustomobject]@{ application = (& $cnt 2 1 0); system = (& $cnt 0 0 0) })
        $m.Sources.'events.system' | Add-Member -Force ReadFailed $true
        $m.Sources.'events.printservice'.Available = $false; $m.Sources.'events.printservice' | Add-Member -Force LookbackRead $true
        $err = { param($n, $msg) [pscustomobject]@{ Count = $n; FirstTime = $m.StartTime; FirstMessage = $msg } }
        $m.SourceErrors = [pscustomobject]@{ 'events.system' = (& $err 2 'Sim nicht lesbar'); 'eventsbefore.application' = (& $err 1 'Sim nicht lesbar') }
        $m.LookbackCapped = @('application')
        [IO.File]::WriteAllText($f, ($m | ConvertTo-Json -Depth 8))
        $out = Join-Path $TestDrive 'reads.html'
        [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $dir -OutFile $out -RoleFile (Join-Path $TestDrive 'r/roles.sim.json') 6>$null)
        $d = Get-ReportData $out
        @($d.quality.eventReads | ForEach-Object { '{0}|{1}|{2}|{3}|{4}' -f $_.log, $_.label, $_.dropped, $_.skipped, $_.unformatted }) |
            Should -Be @('application|Ereignisprotokoll Anwendung|1000|3|0', 'defender|Ereignisprotokoll Microsoft Defender|0|0|2')
        @($d.before.readCounts | ForEach-Object { '{0}|{1}|{2}' -f $_.log, $_.skipped, $_.unformatted }) | Should -Be @('application|2|1')
        @($d.before.readCounts[0].PSObject.Properties.Name) | Should -Not -Contain 'dropped'
        @($d.quality.sources | Where-Object readFailed | ForEach-Object { $_.id }) | Should -Be @('events.system')
        @($d.quality.sources | Where-Object lookbackRead | ForEach-Object { $_.id }) | Should -Be @('events.printservice')
        ($d.before.logs | Where-Object id -eq 'printservice').available | Should -BeTrue                # im Rueckblick gelesen
        ($d.quality.sourceErrors | Where-Object source -eq 'events.system').label | Should -Be 'Ereignisprotokoll System'
        ($d.quality.sourceErrors | Where-Object source -eq 'eventsbefore.application').label | Should -Be ('Ereignisse vor der Messung ' + [char]0x2013 + ' Ereignisprotokoll Anwendung')
        # the oldest event read per log: the lookback of the simulation reads only the application log
        $first = @($d.before.incidents | ForEach-Object { $_.start } | Sort-Object)[0]
        @($d.before.oldest | ForEach-Object { '{0}|{1}' -f $_.log, $_.t }) | Should -Be @("application|$first")
        # a capture without these fields shows nothing of them
        $old = Copy-SimRun $R.Run (Join-Path $TestDrive 'reads-old'); $g = Join-Path $old 'meta.json'
        $o = Get-Content $g -Raw | ConvertFrom-Json; $o.PSObject.Properties.Remove('EventReadCounts'); $o.PSObject.Properties.Remove('LookbackReadCounts')
        [IO.File]::WriteAllText($g, ($o | ConvertTo-Json -Depth 8))
        $out2 = Join-Path $TestDrive 'reads-old.html'
        [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $old -OutFile $out2 -RoleFile (Join-Path $TestDrive 'r/roles.sim.json') 6>$null)
        $d2 = Get-ReportData $out2
        @($d2.quality.eventReads).Count | Should -Be 0; @($d2.before.readCounts).Count | Should -Be 0
        @($d2.quality.sources | Where-Object { $_.readFailed -or $_.lookbackRead }).Count | Should -Be 0
    }
    It 'nennt das Ende der Aufzeichnung auch unter einem Ausschnitt mit -To' {          # Task 9, fix round 2 (N3)
        $D.before.captureEnd | Should -Be $D.tickT[-1]
        $to = Get-ServerTime $R.Run ($D.tickT[-1] - 10 * 60000)
        $out = Join-Path $TestDrive 'tocut.html'; [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $R.Run -OutFile $out -RoleFile (Join-Path $TestDrive 'r/roles.sim.json') -To $to 6>$null)
        $c = Get-ReportData $out
        $c.before.captureEnd | Should -Be $D.before.captureEnd; $c.before.captureEnd | Should -BeGreaterThan $c.tickT[-1]
    }
}
