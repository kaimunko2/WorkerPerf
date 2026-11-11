BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
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
        $D.incidents.Count | Should -Be $Exp.Count; $D.noFinding | Should -BeFalse
        foreach ($e in $Exp) {
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
