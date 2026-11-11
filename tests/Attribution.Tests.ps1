BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Findings.ps1')
    $script:Th = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json')
    $script:Texts = Read-WorkerPerfTexts (Join-Path $PSScriptRoot '../src/texts.de.json')
    $script:T0 = 1700000000000                              # 22:13:20 UTC, mit 60 min Versatz 23:13:20
    function New-TestModel([switch]$Memory) {
        $mb = 1024.0; $m100 = 100 * $mb; $m300 = 300 * $mb; $m600 = 600 * $mb       # the comma binds tighter than *: no products inside array literals
        $m = @{
            Meta = @{ Cores = 4; OffsetMinutes = 60 }
            Tick = @{ N = 30; TimeMs = [long[]](1..30 | ForEach-Object { $T0 + $_ * 2000 }); ElapsedSec = [double[]](1..30 | ForEach-Object { 2 }) }
            Snap = @{ N = 4; TimeMs = [long[]](1..4 | ForEach-Object { $T0 + $_ * 15000 }); ElapsedSec = [double[]](15, 15, 15, 15) }
            Sessions = @(
                @{ Index = 0; Sid = 2; User = 'user017'; Input = (New-Object double[] 30); Rtt = (New-Object double[] 4); Ws = [double[]]($m100, $m100, $m100, $m100) }
                @{ Index = 1; Sid = 3; User = 'user018'; Input = (New-Object double[] 30); Rtt = (New-Object double[] 4); Ws = [double[]]($m300, $m300, $m300, $m300) }
                @{ Index = 2; Sid = 0; User = ''; Input = (New-Object double[] 30); Rtt = (New-Object double[] 4); Ws = [double[]]($m100, $m100, $m100, $m100) })
            Apps = @(@{ Index = 0; Name = 'EXCEL.EXE'; Role = ''; RoleLabel = '' }, @{ Index = 1; Name = 'chrome.exe'; Role = ''; RoleLabel = '' },
                     @{ Index = 2; Name = 'MsMpEng.exe'; Role = 'Sicherheit'; RoleLabel = 'Microsoft Defender' })
            Proc = @(
                @{ K = 0; Pid = 100; Name = 'EXCEL.EXE'; SessionIndex = 0; AppIndex = 0; Role = ''; RoleLabel = ''; IsCollector = $false; FirstP = 0; LastP = 3 }
                @{ K = 1; Pid = 200; Name = 'chrome.exe'; SessionIndex = 1; AppIndex = 1; Role = ''; RoleLabel = ''; IsCollector = $false; FirstP = 0; LastP = 3 }
                @{ K = 2; Pid = 300; Name = 'MsMpEng.exe'; SessionIndex = 2; AppIndex = 2; Role = 'Sicherheit'; RoleLabel = 'Microsoft Defender'; IsCollector = $false; FirstP = 0; LastP = 3 })
            InputProc = @{ TickPos = [int[]]@(10); SessionIndex = [int[]]@(0); Pid = [int[]]@(100); Name = [string[]]@('EXCEL.EXE'); DelayMs = [double[]]@(300); K = [int[]]@(0) }
            Probes = @(@{ Name = 'DB'; Role = 'Datenbank'; Ms = [double[]](5, 350, 5, 5); Error = [string[]]('', '', '', '') })
            Events = @(); Scans = @()
        }
        if ($Memory) {      # K1 und K2 schreiben nur im Stuetzpunkt P0; K0 waechst in P2 von 100 auf 600 MB
            $m.Rows = @{ Start = [int[]](0, 3, 3, 4, 4); K = [int[]](0, 1, 2, 0); CpuMs = [double[]](0, 0, 0, 0); Io = [double[]](0, 0, 0, 0)
                         WsKB = [double[]]($m100, $m300, $m100, $m600) }
            $m.Sessions[0].Ws = [double[]]($m100, $m100, $m600, $m600)
        }
        else {              # je Schnappschuss K0, K1, K2; in P1 und P2 verbraucht K0 41 % der CPU-Zeit, sonst 2 %
            $m.Rows = @{ Start = [int[]](0, 3, 6, 9, 12); K = [int[]](0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2)
                         CpuMs = [double[]](200, 6900, 2900, 4100, 3000, 2900, 4100, 3000, 2900, 200, 6900, 2900)
                         Io = [double[]](0, 5e6, 1e6, 0, 5e6, 1e6, 0, 5e6, 1e6, 0, 5e6, 1e6)
                         WsKB = [double[]](1..4 | ForEach-Object { 100 * $mb; 300 * $mb; 100 * $mb }) }
        }
        $m.Sessions[0].Input[10] = 300                       # Takt bei T0 + 22 s
        $m
    }
    function New-TestIncident([string]$Resource, [string]$SignalId, [double]$Peak, [string]$Type = 'engpass') {
        $isInput = $Resource -eq 'input'
        $f = @{ SignalId = $SignalId; Resource = $Resource; Instance = ''; Label = $Th[$SignalId].label; Scope = $(if ($isInput) { 'session' } else { 'global' })
                SessionIndex = $(if ($isInput) { 0 } else { -1 }); StartMs = [long]($T0 + 15000); EndMs = [long]($T0 + 45000); Severity = 2; PeakValue = $Peak
                PeakTimeMs = [long]($T0 + 30000); BadPoints = 5 }
        @{ Id = 1; StartMs = $f.StartMs; EndMs = $f.EndMs; Severity = 2; Chronic = $false; Type = $Type; Lead = $(if ($Type -eq 'engpass') { $Resource } else { $null })
           Resources = @($(if ($Type -eq 'engpass') { $Resource })); Findings = @($f); ChronicContext = @() }
    }
    function Add-Detail($Model, $Incident) { Add-WorkerPerfIncidentDetail -Incidents @($Incident) -Model $Model -Thresholds $Th }
}
Describe 'Add-WorkerPerfIncidentDetail' {
    It 'nennt Betroffene, Verursacher mit Normalwert und den Begleiter' {
        $m = New-TestModel; $i = New-TestIncident 'cpu' 'cpu.host' 97; Add-Detail $m $i
        $i.Affected.Count | Should -Be 1; $i.Affected[0].SessionIndex | Should -Be 0; $i.Affected[0].PeakMs | Should -Be 300
        $c = $i.Contributors['cpu']
        $c.Measure | Should -Be 'cpu'; $c.Main.App | Should -Be 'EXCEL.EXE'; $c.Main.User | Should -Be 'user017'
        $c.Main.SharePct | Should -Be 41; $c.Main.BaselinePct | Should -Be 2
        $c.Processes.K | Should -Be @(0, 1, 2); $c.Processes[2].SharePct | Should -Be 29
        $c.Sessions[0].SessionIndex | Should -Be 0; $c.Apps[1].Name | Should -Be 'chrome.exe'
        $i.Companion.Label | Should -Be 'Microsoft Defender'; $i.Companion.SharePct | Should -Be 29
        $i.Companion.TopIoApp | Should -Be 'chrome.exe'; $i.Companion.TopIoUser | Should -Be 'user018'
        $i.Security.TotalPct | Should -Be 29; $i.Security.Products[0].Label | Should -Be 'Microsoft Defender'
        $i.DelayProcesses[0].Name | Should -Be 'EXCEL.EXE'; $i.Endpoints[0].MaxMs | Should -Be 350
    }
    It 'fuehrt den Speicher ruhender Prozesse fort' {
        $m = New-TestModel -Memory; $i = New-TestIncident 'memory' 'mem.used' 93
        $i.Findings[0].StartMs = [long]($T0 + 31000); $i.StartMs = $i.Findings[0].StartMs       # das Fenster trifft nur P2
        Add-Detail $m $i; $c = $i.Contributors['memory']
        $c.Main.App | Should -Be 'EXCEL.EXE'; $c.Main.SharePct | Should -Be 60; $c.Main.GrowthMB | Should -Be 500; $c.Main.BaselinePct | Should -Be 40
        $c.Processes[1].K | Should -Be 1; $c.Processes[1].SharePct | Should -Be 30                 # ohne eigene Zeile im Fenster
    }
    It 'beschraenkt den Profilcontainer auf die eigene Sitzung' {
        $m = New-TestModel; $i = New-TestIncident 'profile' 'disk.latency' 45
        $i.Findings[0].Scope = 'session'; $i.Findings[0].SessionIndex = 1; Add-Detail $m $i
        @($i.Contributors['profile'].Processes).Count | Should -Be 1; $i.Contributors['profile'].Main.App | Should -Be 'chrome.exe'
        $i.Contributors['profile'].Measure | Should -Be 'io'
    }
    It 'kennzeichnet den Collector' {
        $m = New-TestModel; $m.Proc[1].IsCollector = $true; $i = New-TestIncident 'cpu' 'cpu.host' 97; Add-Detail $m $i
        $i.Contributors['cpu'].Processes[1].IsCollector | Should -BeTrue
    }
    It 'nennt Ereignisse und laufende Scans im Fenster' {
        $m = New-TestModel; $m.Events = @(@{ TimeMs = $T0 + 20000; Kind = 'applocker-block' }, @{ TimeMs = $T0 + 90000; Kind = 'applocker-block' })
        $m.Scans = @(@{ StartMs = $T0; EndMs = $T0 + 20000 }); $i = New-TestIncident 'cpu' 'cpu.host' 97; Add-Detail $m $i
        @($i.Events).Count | Should -Be 1; $i.ScanActive | Should -BeTrue
    }
}
Describe 'Get-WorkerPerfIncidentText' {
    It 'beschreibt einen Engpass mit Begleiter' {
        $m = New-TestModel; $i = New-TestIncident 'cpu' 'cpu.host' 97; Add-Detail $m $i
        Get-WorkerPerfIncidentText -Incident $i -Model $m -Thresholds $Th -Texts $Texts | Should -Be ('23:13:35–23:14:05: CPU-Engpass (CPU-Auslastung Spitze 97 %, Soll unter 75 %). ' +
            'Betroffen: 1 Sitzung. Hauptverursacher: EXCEL.EXE in der Sitzung von user017 mit 41 % der CPU-Zeit (sonst 2 %). ' +
            'Begleiter: Microsoft Defender mit 29 % der CPU-Zeit; größter I/O-Erzeuger im Fenster: chrome.exe (user018). Scan-Ausschlüsse prüfen.')
    }
    It 'beschreibt eine Verzoegerung ohne Engpass' {
        $m = New-TestModel; $i = New-TestIncident 'input' 'input.session' 300 -Type 'ohne-engpass'; Add-Detail $m $i
        Get-WorkerPerfIncidentText -Incident $i -Model $m -Thresholds $Th -Texts $Texts | Should -Be ('23:13:35–23:14:05: Eingabeverzögerung ohne Engpass auf dem Worker (Spitze 300 ms, Soll unter 150 ms). ' +
            'Betroffen: 1 Sitzung. Höchste Verzögerung in EXCEL.EXE (user017). ' +
            'Die Ursache liegt außerhalb des Workers oder in der Anwendung selbst (Datenbank, Proxy, Netz). Gegenstelle DB: 350 ms.')
    }
    It 'stellt einem Dauerzustand den Hinweis voran und nennt dauerhaft erhoehte Signale' {
        $m = New-TestModel; $i = New-TestIncident 'cpu' 'cpu.host' 97; $i.Chronic = $true
        $i.ChronicContext = @(@{ IncidentId = 9; SignalId = 'mem.used'; Label = 'RAM-Auslastung'; Severity = 1; Explains = $false }); Add-Detail $m $i
        $text = Get-WorkerPerfIncidentText -Incident $i -Model $m -Thresholds $Th -Texts $Texts
        $text | Should -Match '^Dauerzustand: 23:13:35–23:14:05: CPU-Engpass'; $text | Should -Match ' Dauerhaft erhöht: RAM-Auslastung\.$'
    }
    It 'nennt bei einer nur durch einen Dauerzustand erklaerten Ursache diesen im Kopfsatz' {
        $m = New-TestModel; $i = New-TestIncident 'input' 'input.session' 300 -Type 'ohne-engpass'; $i.Type = 'engpass'; $i.Lead = 'cpu'
        $i.ChronicContext = @(@{ IncidentId = 9; SignalId = 'cpu.host'; Label = 'CPU-Auslastung'; Severity = 2; Explains = $true }); Add-Detail $m $i
        Get-WorkerPerfIncidentText -Incident $i -Model $m -Thresholds $Th -Texts $Texts | Should -Be ('23:13:35–23:14:05: CPU-Engpass als Dauerzustand (CPU-Auslastung dauerhaft über dem Soll); im Fenster Eingabeverzögerung Spitze 300 ms, Soll unter 150 ms. ' +
            'Betroffen: 1 Sitzung. Hauptverursacher: EXCEL.EXE in der Sitzung von user017 mit 41 % der CPU-Zeit (sonst 2 %). ' +
            'Begleiter: Microsoft Defender mit 29 % der CPU-Zeit; größter I/O-Erzeuger im Fenster: chrome.exe (user018). Scan-Ausschlüsse prüfen.')
    }
}
Describe 'Betroffene bei Dauerzustaenden und Umfeld' {
    It 'zaehlt bei einem Dauerzustand im Umfeld nur Sitzungen mit eigenem Befund' {
        $m = New-TestModel; $i = New-TestIncident 'network' 'ica.rtt' 225; $i.Type = 'umfeld'; $i.Lead = $null; $i.Chronic = $true
        $i.Findings[0].Scope = 'session'; $i.Findings[0].SessionIndex = 1; $i.StartMs = $T0; $i.EndMs = $T0 + 70000
        Add-Detail $m $i
        @($i.Affected).Count | Should -Be 0
    }
    It 'laesst bei einem Dauerzustand die Takte kurzer Vorfaelle aus' {
        $m = New-TestModel; $short = New-TestIncident 'cpu' 'cpu.host' 97
        $chr = New-TestIncident 'cpu' 'cpu.host' 80; $chr.Id = 2; $chr.Chronic = $true; $chr.StartMs = $T0; $chr.EndMs = $T0 + 70000
        Add-WorkerPerfIncidentDetail -Incidents @($short, $chr) -Model $m -Thresholds $Th
        @($short.Affected).Count | Should -Be 1; @($chr.Affected).Count | Should -Be 0
        $text = Get-WorkerPerfIncidentText -Incident $chr -Model $m -Thresholds $Th -Texts $Texts
        $text | Should -Not -Match 'Betroffen'; $text | Should -Not -Match 'Keine Sitzung'
    }
}
Describe 'Signalnamen im Klartext' {
    It 'nennt bei Netzstrecken die Bezeichnung des Schwellwerts statt der Sitzungsbezeichnung' {
        $m = New-TestModel; $i = New-TestIncident 'network' 'ica.rtt' 225; $i.Type = 'umfeld'; $i.Lead = $null
        $i.Findings[0].Label = 'user018 (#3)'; $i.Findings[0].Scope = 'session'; $i.Findings[0].SessionIndex = 1; Add-Detail $m $i
        Get-WorkerPerfIncidentText -Incident $i -Model $m -Thresholds $Th -Texts $Texts | Should -Be '23:13:35–23:14:05: Netzstrecke von user018 auffällig (ICA Round Trip Spitze 225 ms, Soll unter 150 ms). Betrifft die Sitzung, nicht den Worker.'
    }
    It 'nennt dauerhaft erhoehte Signale mit Instanz nur, wenn die Bezeichnung abweicht' {
        $m = New-TestModel; $i = New-TestIncident 'cpu' 'cpu.host' 97
        $i.ChronicContext = @(@{ IncidentId = 8; SignalId = 'cpu.host'; Label = 'CPU-Auslastung'; Severity = 1; Explains = $false }
                              @{ IncidentId = 9; SignalId = 'disk.latency'; Label = 'Laufwerk D:'; Severity = 1; Explains = $false }); Add-Detail $m $i
        $text = Get-WorkerPerfIncidentText -Incident $i -Model $m -Thresholds $Th -Texts $Texts
        $text | Should -Match ([regex]::Escape(' Dauerhaft erhöht: CPU-Auslastung, ' + $Th['disk.latency'].label + ' – Laufwerk D:.') + '$')
    }
    It 'waehlt den erklaerenden Dauerzustand nach der Ressource' {
        $m = New-TestModel; $i = New-TestIncident 'input' 'input.session' 300 -Type 'ohne-engpass'; $i.Type = 'engpass'; $i.Lead = 'profile'
        $i.ChronicContext = @(@{ IncidentId = 8; SignalId = 'cpu.host'; Label = 'CPU-Auslastung'; Severity = 2; Explains = $true; Resource = 'cpu' }
                              @{ IncidentId = 9; SignalId = 'disk.latency'; Label = 'Laufwerk D:'; Severity = 2; Explains = $true; Resource = 'profile' }); Add-Detail $m $i
        Get-WorkerPerfIncidentText -Incident $i -Model $m -Thresholds $Th -Texts $Texts | Should -Match ([regex]::Escape('(' + $Th['disk.latency'].label + ' – Laufwerk D: dauerhaft'))
    }
}
Describe 'Begleiter' {
    It 'setzt bei einem Sicherheitsprozess unter 10 % keinen Begleiter' {
        $m = New-TestModel; $m.Rows.CpuMs[5] = 100; $m.Rows.CpuMs[8] = 100
        $i = New-TestIncident 'cpu' 'cpu.host' 97; Add-Detail $m $i
        $i.Companion | Should -BeNullOrEmpty; $i.Security.TotalPct | Should -BeGreaterThan 0
        $i.Contributors['cpu'].Processes[2].Role | Should -Be 'Sicherheit'
    }
}
