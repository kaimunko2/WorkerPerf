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
    It 'fuehrt Speicher und Datentraeger in einem Vorfall' { (Get-Hit 'memory').resources | Should -Be @('memory', 'disk') }
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
    }
    It 'wertet einen Zeitausschnitt aus' {
        $out = Join-Path $TestDrive 'cut.html'; $from = [DateTimeOffset]::FromUnixTimeMilliseconds($R.StartMs + 240000).LocalDateTime
        [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $R.Run -OutFile $out -From $from -To $from.AddMinutes(4) 6>$null)
        $c = Get-ReportData $out
        $c.incidents.Count | Should -Be 2; @($c.incidents | Where-Object chronic).Count | Should -Be 0     # vier Minuten sind kein Dauerzustand
        ($c.incidents | Where-Object type -eq 'engpass').lead | Should -Be 'cpu'
    }
    It 'nennt den fehlerhaften Schwellwert' {
        $bad = Join-Path $TestDrive 'bad.json'; [IO.File]::WriteAllText($bad, '{"thresholds":[{"id":"cpu.host"}]}')
        { & (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $R.Run -OutFile (Join-Path $TestDrive 'x.html') -ThresholdFile $bad 6>$null } | Should -Throw '*cpu.host*'
    }
}
