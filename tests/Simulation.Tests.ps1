BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Sources.Simulation.ps1')
    $script:Start = [datetime]'2026-01-15T08:00:00'
    $script:Info = Initialize-WorkerPerfSource -StartTime $Start
    function Set-SimTime([double]$Minutes) { [void](Wait-WorkerPerfTick -Until $Start.AddMinutes($Minutes) -StopFlagPath '') }
    function Get-SimProcess([string]$Name, [int]$SessionId) { , @((Get-WorkerPerfSnapshot).Processes | Where-Object { $_.Name -eq $Name -and ($SessionId -lt 0 -or $_.SessionId -eq $SessionId) }) }
    function Get-CpuSec($p) { ([double]$p.UserModeTime + [double]$p.KernelModeTime) / 1e7 }
}
Describe 'Simulation' {
    It 'meldet die festen Eckdaten' {
        $Info.Computer | Should -Be 'SIM-VDA01'; $Info.LogicalProcessors | Should -Be 8; $Info.PhysicalMemoryMB | Should -Be 65536; $Info.CollectorPid | Should -Be 4242
        @($Info.Endpoints).Name | Should -Be @('Oracle-Listener', 'FortiGate-Proxy', 'Dateiserver')
        @($Info.Sources.Values | Where-Object { -not $_.Available }).Count | Should -Be 0
    }
    It 'liefert zu gleicher Zeit gleiche Werte, auch nach Spruengen der Uhr' {
        Set-SimTime 6; $a = (Get-WorkerPerfFastSample).CpuPct
        Set-SimTime 30; Set-SimTime 6; (Get-WorkerPerfFastSample).CpuPct | Should -Be $a
        Get-WorkerPerfNow | Should -Be $Start.AddMinutes(6)
    }
    It 'bleibt in ruhigen Phasen unter allen Schwellen' {
        foreach ($m in 10, 11.5, 13, 22, 44, 57) {
            Set-SimTime $m; $f = Get-WorkerPerfFastSample
            $f.CpuPct | Should -BeLessThan 75; (1 - $f.MemAvailMB / 65536) * 100 | Should -BeLessThan 75
            $f.ProcQueue | Should -BeLessThan 16; $f.PagesInPerSec | Should -BeLessThan 10
            @($f.InputSessions | Where-Object { $_.DelayMs -ge 150 }).Count | Should -Be 0
            @($f.Volumes | Where-Object { $_.ReadLatMs -ge 10 -or $_.WriteLatMs -ge 10 }).Count | Should -Be 0
            @($f.Shares | Where-Object { $_.ReadLatMs -ge 10 -or $_.WriteLatMs -ge 10 }).Count | Should -Be 0
        }
    }
    It 'spielt den CPU-Engpass' {
        Set-SimTime 6; $f = Get-WorkerPerfFastSample
        $f.CpuPct | Should -BeGreaterOrEqual 90
        @($f.InputSessions | Where-Object { $_.DelayMs -ge 150 }).SessionId | Sort-Object | Should -Be @(2, 3, 4, 5, 6, 7)
        Set-SimTime 5; $a = Get-CpuSec (Get-SimProcess 'EXCEL.EXE' 4)[0]
        Set-SimTime 7; (Get-CpuSec (Get-SimProcess 'EXCEL.EXE' 4)[0]) - $a | Should -BeGreaterThan 560     # 60 % von 8 Kernen ueber 120 s
    }
    It 'laesst robocopy nur im Datentraeger-Fenster laufen' {
        Set-SimTime 24.75; (Get-SimProcess 'robocopy.exe' -1).Count | Should -Be 0
        Set-SimTime 25.5; $p = Get-SimProcess 'robocopy.exe' -1; $p.Count | Should -Be 1; $p[0].SessionId | Should -Be 12
        Set-SimTime 27; (Get-SimProcess 'robocopy.exe' -1).Count | Should -Be 0
    }
    It 'haelt die Mehrheit der Prozesse in Ruhe' {
        Set-SimTime 10; $a = @{}; foreach ($p in (Get-WorkerPerfSnapshot).Processes) { $a[$p.ProcessId] = $p }
        Set-SimTime 10.25; $b = @((Get-WorkerPerfSnapshot).Processes)
        $idle = @($b | Where-Object { $a.ContainsKey($_.ProcessId) -and (Get-CpuSec $_) -eq (Get-CpuSec $a[$_.ProcessId]) -and $_.ReadTransferCount -eq $a[$_.ProcessId].ReadTransferCount })
        $idle.Count | Should -BeGreaterThan ($b.Count / 2)
    }
    It 'kennzeichnet Profilcontainer und Dienste' {
        Set-SimTime 40.5; $v = (Get-WorkerPerfFastSample).Volumes | Where-Object Volume -eq 'HarddiskVolume18'
        $v.Kind | Should -Be 'profile'; $v.SessionId | Should -Be 10; $v.Backing | Should -Be '\\fs01\profile$'
        (Get-WorkerPerfServices).Values | Should -Contain 'AppIDSvc'
    }
    It 'meldet Proben erst im naechsten Takt' {
        Set-SimTime 47.5; Start-WorkerPerfProbes; Receive-WorkerPerfProbes | Should -BeNullOrEmpty
        Set-SimTime (47.5 + 2 / 60); $r = @(Receive-WorkerPerfProbes)
        $r.Count | Should -Be 3; ($r | Where-Object Name -eq 'Oracle-Listener').ConnectMs | Should -BeGreaterOrEqual 200
    }
    # Aussage geaendert: das Drehbuch bekommt Absturz-, Druck-, Profil- und Sitzungsszenen (Task 4)
    It 'liefert Ereignisse seit einem Zeitpunkt' {
        Set-SimTime 31; @(Get-WorkerPerfEvents -Since $Start | Where-Object Group -eq 'security').Kind | Should -Be @('scan-start', 'scan-end', 'applocker-block')
        @(Get-WorkerPerfEvents -Since $Start.AddMinutes(28)).Kind | Should -Be @('applocker-block')
        Set-SimTime 60; $ev = @(Get-WorkerPerfEvents -Since $Start)
        @($ev | Where-Object Kind -eq 'crash').App | Should -Be @('chrome.exe', 'OUTLOOK.EXE', 'OUTLOOK.EXE', 'OUTLOOK.EXE', 'spoolsv.exe')
        ($ev | Where-Object App -eq 'spoolsv.exe').Module | Should -Be 'hpsimgr.dll'
        @($ev | Where-Object Group -eq 'session').Kind | Should -Be @('logoff', 'logon', 'disconnect', 'reconnect')
    }
    It 'spielt die Szenen mit Zeit, Prozess, Sitzung und Fehlercode des Drehbuchs' {
        Set-SimTime 60; $ev = @(Get-WorkerPerfEvents -Since $Start)
        $ev.Count | Should -Be 13
        $sec = @($ev | ForEach-Object { ($_.Time - $Start).TotalSeconds })
        $sec | Should -Be @(555, 595, 600, 1100, 1490, 1620, 1800, 2100, 2160, 2200, 2220, 2230, 2600)
        $c = $ev | Where-Object App -eq 'chrome.exe'
        $c.Module | Should -Be 'chrome.dll'; $c.Code | Should -Be '0xc0000017'; $c.Level | Should -Be 2
        # ein Absturz nennt keine Sitzung: der Collector findet sie ueber die PID eines Prozesses, der zu der Zeit lief
        $c.SessionId | Should -BeNullOrEmpty; $c.User | Should -Be ''
        Set-SimTime ((1100 - 15) / 60)
        ((Get-WorkerPerfSnapshot).Processes | Where-Object ProcessId -eq $c.Pid).SessionId | Should -Be 9
        ((Get-WorkerPerfSnapshot).Processes | Where-Object ProcessId -eq $c.Pid).Name | Should -Be 'chrome.exe'
        $o = @($ev | Where-Object App -eq 'OUTLOOK.EXE')
        @($o.Module | Select-Object -Unique) | Should -Be @('olmapi32.dll'); @($o.Code | Select-Object -Unique) | Should -Be @('0xc0000005')
        Set-SimTime 35; $snap = @((Get-WorkerPerfSnapshot).Processes)
        @($o | ForEach-Object { $p = $_.Pid; ($snap | Where-Object ProcessId -eq $p).SessionId }) | Should -Be @(11, 12, 13)
        $sp = $ev | Where-Object App -eq 'spoolsv.exe'
        $sp.Code | Should -Be '0xc0000005'; ($snap | Where-Object ProcessId -eq $sp.Pid).Name | Should -Be 'spoolsv.exe'; ($snap | Where-Object ProcessId -eq $sp.Pid).SessionId | Should -Be 0
        # Sitzungsereignisse nennen Sitzung und Benutzer selbst
        @($ev | Where-Object Group -eq 'session' | ForEach-Object { '{0}|{1}' -f $_.User, $_.SessionId }) | Should -Be @('user014|15', 'user014|15', 'user022|23', 'user022|23')
        $pr = $ev | Where-Object Group -eq 'profile'
        $pr.Kind | Should -Be 'profileerror'; $pr.EventId | Should -Be 1511; $pr.Log | Should -Be 'application'; $pr.Text | Should -Match 'user014'
        # der Profildienst nennt den Benutzer (Konto im System-Teil des Ereignisses), aber keine Sitzung
        $pr.User | Should -Be 'user014'; $pr.SessionId | Should -BeNullOrEmpty
    }
    It 'nimmt Protokoll, Quelle, Gruppe und Art jedes Ereignisses aus events.json' {
        $cfg = Read-WorkerPerfEventConfig (Join-Path $PSScriptRoot '../src/events.json')
        Set-SimTime 60
        $all = @(Get-WorkerPerfEvents -Since $Start) + @((Get-WorkerPerfEventsBefore -Days 7 -Until $Start).Events)
        $all.Count | Should -Be 19                                                   # C1: ein Absturz ohne Sitzung im Rueckblick dazu
        foreach ($e in $all) {
            $entry = Resolve-WorkerPerfEventEntry $cfg $e.Log $e.Source $e.EventId
            $entry | Should -Not -BeNullOrEmpty -Because "$($e.Source) $($e.EventId)"
            $e.Group | Should -BeExactly $entry.group; $e.Kind | Should -BeExactly $entry.kind
            # alle Felder eines Datensatzes von ConvertTo-WorkerPerfEventRecord
            @($e.PSObject.Properties.Name | Sort-Object) | Should -Be @('App', 'AppVersion', 'Code', 'Driver', 'EventId', 'Group', 'Kind', 'Level', 'Log', 'Module', 'ModuleVersion',
                'Object', 'Pid', 'Printer', 'ProcessStart', 'Service', 'SessionId', 'Source', 'Text', 'Time', 'User')     # ProcessStart: Task 10
        }
    }
    It 'liefert Rueckblick, Treiber und Warteschlangen' {
        $b = Get-WorkerPerfEventsBefore -Days 7 -Until $Start
        @($b.Events).Count | Should -Be 6; @($b.Capped).Count | Should -Be 0          # C1: Aussage geaendert
        @((Get-WorkerPerfEventsBefore -Days 4 -Until $Start).Events).Count | Should -Be 4
        @(Get-WorkerPerfPrintDrivers).Manufacturer | Should -Be @('HP', 'Microsoft', 'Kyocera')
        Set-SimTime 43.5; (Get-WorkerPerfPrintQueues | Where-Object Queue -eq 'PRN-EG-01').Jobs | Should -Be 3
    }
    It 'spielt Rueckblick, Treiberliste und Zaehler der Warteschlangen wie im Drehbuch' {
        $b = @((Get-WorkerPerfEventsBefore -Days 7 -Until $Start).Events)
        # C1: Aussage geaendert, der letzte Absturz nennt weder Sitzung noch Konto
        @($b | ForEach-Object { ($_.Time - $Start).TotalSeconds }) | Should -Be @(-432000, -431000, -259200, -258600, -258000, -172800)
        @($b | ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.App, $_.Module, $_.User, $_.SessionId }) | Should -Be @('EXCEL.EXE|simaddin.dll|user001|2',
            'WINWORD.EXE|simaddin.dll|user002|3', 'nexus.exe|nxreport.dll|user004|5', 'nexus.exe|nxreport.dll|user004|5', 'nexus.exe|nxreport.dll|user004|5', 'simscan.exe|simscan.dll||')
        # bis zu einem frueheren Zeitpunkt: nur aeltere Ereignisse, gezaehlt ab diesem Zeitpunkt
        @((Get-WorkerPerfEventsBefore -Days 1 -Until $Start.AddSeconds(-258300)).Events).Count | Should -Be 2
        @((Get-WorkerPerfEventsBefore -Days 0 -Until $Start).Events).Count | Should -Be 0
        $d = @(Get-WorkerPerfPrintDrivers)
        $d.Name | Should -Be @('HP Universal Printing PCL 6 (Sim)', 'Microsoft IPP Class Driver', 'Kyocera Sim KX')
        $d.Type | Should -Be @(3, 4, 3); $d.Isolation | Should -Be @('none', 'shared', 'isolated')
        $d[0].Files | Should -Be @('hpsimgr.dll', 'hpsimui.dll'); $d[1].Files | Should -Be @('mxdwdrv.dll'); $d[2].Files | Should -Be @('kxsim.dll')
        $at = { param($s) Set-SimTime ($s / 60); @(Get-WorkerPerfPrintQueues | ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.Queue, $_.Jobs, $_.JobErrors, $_.NotReadyErrors }) }
        & $at 2590 | Should -Be @('PRN-EG-01|0|2|0', 'PRN-OG-02|0|0|0')
        & $at 2595 | Should -Be @('PRN-EG-01|3|2|0', 'PRN-OG-02|0|0|0')
        & $at 2600 | Should -Be @('PRN-EG-01|3|3|0', 'PRN-OG-02|0|0|0')
        & $at 2700 | Should -Be @('PRN-EG-01|3|3|0', 'PRN-OG-02|0|0|0')
        & $at 2715 | Should -Be @('PRN-EG-01|0|3|0', 'PRN-OG-02|0|0|0')
    }
    # Aussage geaendert: expected.json nennt auch die Ereignisvorfaelle (Task 4)
    It 'beschreibt das Soll-Ergebnis' {
        $e = @(Get-WorkerPerfExpected)
        @($e | Where-Object Type -ne 'ereignis').Key | Should -Be @('homeoffice', 'cpu', 'memory', 'disk', 'share', 'profile', 'backend', 'hang')
        @($e | Where-Object Type -eq 'ereignis').Count | Should -Be 8                 # C1: der Absturz ohne Sitzung im Rueckblick
        ($e | Where-Object Key -eq 'crash.memory').Patterns | Should -Be @('resource', 'overlap')
        ($e | Where-Object Key -eq 'profile.logon').Patterns.Count | Should -Be 0
        $cpu = $e | Where-Object Key -eq 'cpu'
        $cpu.MainUser | Should -Be 'user003'; $cpu.EndMs - $cpu.StartMs | Should -Be 120000; $cpu.Affected | Should -Be 6
        @($e | Where-Object Chronic).Count | Should -Be 1
    }
    It 'beschreibt die Ereignisvorfaelle und den Rueckblick' {
        $e = @(Get-WorkerPerfExpected); $ms = ([DateTimeOffset]$Start).ToUnixTimeMilliseconds()
        $e.Key | Should -Be @('homeoffice', 'cpu', 'profile.logon', 'memory', 'crash.memory', 'disk', 'share', 'crash.manyusers', 'profile', 'print.spooler',
            'backend', 'hang', 'before.shared.excel', 'before.shared.word', 'before.oneuser', 'before.nosession')      # C1: Absturz ohne Sitzung und Konto
        $show = { param($r) '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}' -f $r.Kind, (@($r.Patterns) -join '+'), $r.Before, $r.App, $r.Driver, $r.Count, (@($r.Users) -join '+'),
            (($r.StartMs - $ms) / 1000), (($r.EndMs - $ms) / 1000), $r.Affected }
        $rows = @{}; foreach ($r in $e) { $rows[$r.Key] = & $show $r }
        $rows['crash.memory'] | Should -Be 'crash|resource+overlap|False|chrome.exe||1|user008|1100|1100|0'
        $rows['profile.logon'] | Should -Be 'profileerror||False|||1|user014|600|600|0'
        $rows['crash.manyusers'] | Should -Be 'crash|manyusers|False|OUTLOOK.EXE||3|user010+user011+user012|2100|2220|0'
        $rows['print.spooler'] | Should -Be 'print|printdriver|False|spoolsv.exe|HP Universal Printing PCL 6 (Sim)|1||2600|2600|0'
        $rows['before.shared.excel'] | Should -Be 'crash|sharedmodule|True|EXCEL.EXE||1|user001|-432000|-432000|0'
        $rows['before.shared.word'] | Should -Be 'crash|sharedmodule|True|WINWORD.EXE||1|user002|-431000|-431000|0'
        $rows['before.oneuser'] | Should -Be 'crash|oneuser|True|nexus.exe||3|user004|-259200|-258000|0'
        $rows['before.nosession'] | Should -Be 'crash||True|simscan.exe||1||-172800|-172800|0'
        $rows['cpu'] | Should -Be '||False|||0||300|420|6'
        foreach ($r in @($e | Where-Object Type -eq 'ereignis')) { $r.Lead | Should -BeNullOrEmpty; $r.Chronic | Should -BeFalse; $r.Patterns -is [array] | Should -BeTrue }
        foreach ($r in @($e | Where-Object Type -ne 'ereignis')) { $r.Kind | Should -BeNullOrEmpty; $r.Patterns.Count | Should -Be 0; $r.Before | Should -BeFalse }
    }
    It 'fuehrt die Ereignisprotokolle und Druckquellen als verfuegbar' {
        $cfg = Read-WorkerPerfEventConfig (Join-Path $PSScriptRoot '../src/events.json')
        # Aussage geaendert (M10): die Protokolle mit Eintraegen im Katalog
        $Info.Sources.Contains('events.profileservice') | Should -BeFalse
        foreach ($id in @(@(Get-WorkerPerfEventReadLogs $cfg) | ForEach-Object { 'events.' + $_.Id }) + @('print.drivers', 'print.queues')) {
            $Info.Sources.Contains($id) | Should -BeTrue -Because $id; $Info.Sources[$id].Available | Should -BeTrue
        }
    }
}
Describe 'Simulation mit weggelassenen Kategorien' {
    BeforeAll {
        function Invoke-SimReads([string[]]$Skip) {   # jeder Aufruf der Schnittstelle einmal, wie der Collector sie nutzt
            [void](Initialize-WorkerPerfSource -StartTime $Start -Skip $Skip); Set-SimTime 47.5
            $r = @{ Fast = (Get-WorkerPerfFastSample); Snap = (Get-WorkerPerfSnapshot -Kind K); Services = (Get-WorkerPerfServices); Events = @(Get-WorkerPerfEvents -Since $Start)
                Before = (Get-WorkerPerfEventsBefore -Days 7 -Until $Start); Drivers = @(Get-WorkerPerfPrintDrivers); Queues = @(Get-WorkerPerfPrintQueues)
                Health = (Get-WorkerPerfHealth) }
            Start-WorkerPerfProbes; Set-SimTime 47.6; $r.Probes = @(Receive-WorkerPerfProbes); $r.Reads = $script:WorkerPerfSimReads.Clone(); $r
        }
        $script:ReadKeys = @{ Prozesse = @('process', 'input.process', 'services'); Laufwerke = @('volumes', 'shares'); Citrix = @('citrix'); Ereignisse = @('events'); Rueckblick = @('eventsbefore')
            Drucken = @('printdrivers', 'printqueues'); Gegenstellen = @('probes'); Zustand = @('health') }
    }
    AfterAll { [void](Initialize-WorkerPerfSource -StartTime $Start) }
    It 'liest die Quellen von <_> nicht und alle anderen weiter' -ForEach 'Prozesse', 'Laufwerke', 'Citrix', 'Ereignisse', 'Rueckblick', 'Drucken', 'Gegenstellen', 'Zustand' {
        $cat = $_; $r = Invoke-SimReads @($cat)
        foreach ($c in $ReadKeys.Keys) { foreach ($k in $ReadKeys[$c]) { if ($c -eq $cat) { [int]$r.Reads[$k] | Should -Be 0 -Because $k } else { [int]$r.Reads[$k] | Should -BeGreaterThan 0 -Because $k } } }
    }
    It 'liefert ohne alle Kategorien nur die Basis, mit denselben Werten' {   # Review Focus 1
        $full = Invoke-SimReads @(); $r = Invoke-SimReads @('Prozesse', 'Laufwerke', 'Citrix', 'Ereignisse', 'Rueckblick', 'Drucken', 'Gegenstellen', 'Zustand')
        @($r.Reads.Values | Where-Object { $_ -gt 0 }).Count | Should -Be 0
        @($r.Snap.Processes).Count + @($r.Snap.Citrix).Count + $r.Services.Count | Should -Be 0; @($r.Snap.Sessions).Count | Should -Be 26
        @($r.Fast.Volumes).Count + @($r.Fast.Shares).Count + @($r.Fast.InputProcesses).Count | Should -Be 0; @($r.Fast.InputSessions).Count | Should -Be 25
        foreach ($c in 'CpuPct', 'MemAvailMB', 'DiskReadBps', 'DiskWriteBps', 'DiskReadIops', 'DiskQueue', 'NetRecvBps', 'NetSentBps') { $r.Fast.$c | Should -Be $full.Fast.$c -Because $c }
        @($r.Events).Count + @($r.Before.Events).Count + @($r.Drivers).Count + @($r.Queues).Count + @($r.Probes).Count | Should -Be 0
    }
}
Describe 'Simuliertes Zustandsbild' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1'); $script:TestApps = @(Read-WorkerPerfHealthApps (New-TestAppFile $TestDrive))
        [void](Initialize-WorkerPerfSource -StartTime $Start -Apps $TestApps); $script:H = Get-WorkerPerfHealth
        function Get-V([string]$Id) { $H.Areas[$WorkerPerfHealthValues[$Id].Area].Values[$Id] }
        function Get-Row([string]$App, [string]$Id) { (Get-V 'apps.probes').Value | Where-Object { $_.App -eq $App -and $_.Id -eq $Id } }
    }
    AfterAll { [void](Initialize-WorkerPerfSource -StartTime $Start) }
    It 'liefert elf Bereiche mit jedem Wert der Liste und der Dauer 0' {
        $H.FormatVersion | Should -Be 1; $H.DurationMs | Should -Be 0; @($H.Areas.Keys) | Should -Be $WorkerPerfHealthAreas
        foreach ($id in $WorkerPerfHealthValues.Keys) { $H.Areas[$WorkerPerfHealthValues[$id].Area].Values.Contains($id) | Should -BeTrue -Because $id }
        @($H.Areas.Keys | Where-Object { $H.Areas[$_].Status -ne 'read' }) | Should -Be @('security'); $H.Areas['security'].Status | Should -Be 'partial'
        ($H | ConvertTo-Json -Depth 10 | ConvertFrom-Json).Areas.profile.Values.'profile.containers'.Value.Count | Should -Be 25
    }
    It 'traegt die auffaelligen Werte des Drehbuchs' {
        (Get-V 'operation.pendingRename').Value | Should -Be 2; (Get-V 'operation.pendingServicing').Value | Should -BeFalse
        $full = @((Get-V 'profile.containers').Value | Where-Object { $_.UsedPct -ge 95 }); $full.Count | Should -Be 1; $full[0].Owner | Should -Be 'user009'; $full[0].UsedPct | Should -Be 96
        (Get-V 'security.defenderExclusionPaths').State | Should -Be 'unreadable'; (Get-V 'security.defenderExclusionPaths').Reason | Should -Be 'rights'
        $task = (Get-V 'maintenance.tasks').Value | Where-Object Path -eq '\Sim\Inventarlauf'
        $next = [DateTimeOffset]::FromUnixTimeMilliseconds($task.NextRun).LocalDateTime; $next.Hour | Should -Be 10; $next.DayOfWeek | Should -Not -BeIn 'Saturday', 'Sunday'
        (Get-V 'size.memTotalMB').Value | Should -Be 65536; @((Get-V 'sessions.list').Value | Where-Object { $_.User }).Count | Should -Be 25
        @((Get-V 'vda.controllers').Value.Entry) | Should -Be @('ddc01.sim.local', 'ddc02.sim.local')
        # enumerated explicitly: .Address of an array names its method Address(int), not the field of the entries
        @((Get-V 'network.dnsServers').Value | ForEach-Object { $_.Address }) | Should -Be @('10.20.0.10', '10.20.0.11', 'fd00:20::10')
        (Get-V 'maintenance.searchService').State | Should -Be 'absent'; (Get-V 'maintenance.searchService').Reason | Should -Be 'notInstalled'
        (Get-V 'print.isolationExecution').State | Should -Be 'absent'; (Get-V 'print.isolationExecution').Reason | Should -Be ''
        (Get-V 'operation.lastBoot').Value | Should -Be (ConvertTo-WorkerPerfHealthTime $Start.AddDays(-3))
        (Get-V 'network.timeServers').Value | Should -Be 'zeit01.sim.local 10.20.0.20'; (Get-V 'security.defenderSharedSignatures').Value | Should -Be '\\fs01\defsig$'
        @((Get-V 'events.logs').Value).Count | Should -Be 8; @((Get-V 'vda.services').Value.Name) | Should -Be @('BrokerAgent', 'PorticaService', 'CitrixHealthMon', 'ctxProfile', 'CpSvc')
        @((Get-V 'sessions.localProfiles').Value.Path)[-1] | Should -Be 'C:\Users\Administrator'; ((Get-V 'security.services').Value | Where-Object Name -eq 'RpcSs').State | Should -Be 'Running'
        (Get-V 'vda.wemServer').Value | Should -Be 'wem01.sim.local'; (Get-V 'vda.wemCacheLocation').Value | Should -Be 'D:\WEMCache'; @((Get-V 'vda.wemServices').Value).Count | Should -Be 3
        (Get-V 'size.balloonDriver').Value | Should -Be 'Running'; (Get-V 'print.citrixPrintService').Value | Should -Be 'Running'; (Get-V 'maintenance.updateService').Value | Should -Be 'Disabled'
        (Get-V 'network.rss').Value[0].Enabled | Should -BeTrue; ((Get-V 'sessions.limits').Value | Select-Object -First 1).IdleLimitMin | Should -Be 180
        (Get-V 'operation.powerPlan').Value | Should -Be 'highPerformance'; (Get-V 'print.mappingClientVersion').Value | Should -Be '6.4.1'
        $wu = (Get-V 'security.services').Value | Where-Object Name -eq 'wuauserv'; $wu.State | Should -Be 'Stopped'; $wu.StartMode | Should -Be 'Disabled'      # das Drehbuch widerspricht sich nicht
        ((Get-V 'security.services').Value | Where-Object Name -eq 'CpSvc').State | Should -Be 'Running'
    }
    It 'hat die Form des Wertverzeichnisses' {
        # every value that is read: a list is an array of entries with exactly the fields of the value list, in order;
        # a number is a number, a bool a bool, a time a long, a text a string (in a list entry as in a scalar); only the
        # rows of apps.probes leave Value and Names empty by design (Get-WorkerPerfAppRows)
        $numberTypes = @('Byte', 'Int16', 'Int32', 'Int64', 'UInt16', 'UInt32', 'UInt64', 'Single', 'Double', 'Decimal')
        $test = {
            param($Value, [string]$Type, [string]$Because)
            switch -Regex ($Type) {
                '^number$' { $Value | Should -Not -BeNullOrEmpty -Because $Because; $numberTypes | Should -Contain $Value.GetType().Name -Because $Because }
                '^bool$' { ($Value -is [bool]) | Should -BeTrue -Because $Because }
                '^time$' { ($Value -is [long]) | Should -BeTrue -Because $Because }
                '^text' { ($Value -is [string]) | Should -BeTrue -Because $Because }
            }
        }
        $checked = 0
        foreach ($id in $WorkerPerfHealthValues.Keys) {
            $def = $WorkerPerfHealthValues[$id]; $v = Get-V $id
            if ($v.State -ne 'read') { continue }
            $checked++
            if ($def.Type -eq 'list') {
                ($v.Value -is [array]) | Should -BeTrue -Because $id
                foreach ($entry in $v.Value) {
                    @($entry.Keys) | Should -Be @($def.Fields.Keys) -Because $id
                    foreach ($f in $def.Fields.Keys) {
                        if ($id -eq 'apps.probes' -and $null -eq $entry[$f] -and @('Value', 'Names') -contains $f) { continue }
                        & $test $entry[$f] $def.Fields[$f] "$id.$f"
                    }
                }
            }
            else { & $test $v.Value $def.Type $id }
        }
        $checked | Should -Be 91      # 103 values less the twelve absent and unreadable ones
    }
    It 'passt zur simulierten Stunde' {
        # size from the simulation's constants, as Initialize-WorkerPerfSource reports it, and the first tick
        Set-SimTime 0; $f = Get-WorkerPerfFastSample
        (Get-V 'size.cpuLogical').Value | Should -Be $Info.LogicalProcessors; (Get-V 'size.memTotalMB').Value | Should -Be $Info.PhysicalMemoryMB
        (Get-V 'size.commitLimitMB').Value | Should -Be $f.MemCommitLimitMB
        [Math]::Abs((Get-V 'size.commitTotalMB').Value - $f.MemCommittedMB) | Should -BeLessOrEqual 800
        # volumes and shares of the picture occur in the fast sample; the file server of every share path of the picture
        # serves a measured share
        foreach ($vol in @((Get-V 'operation.volumes').Value)) { @($f.Volumes.Volume) | Should -Contain $vol.Drive }
        foreach ($con in @((Get-V 'network.smbConnections').Value)) { @($f.Shares.Share) | Should -Contain $con.Share }
        $servers = @($f.Shares | ForEach-Object { $_.Share.Split('\')[2] })
        $paths = @(@((Get-V 'profile.containers').Value | ForEach-Object { $_.Location }) + (Get-V 'security.defenderSharedSignatures').Value +
            @((Get-V 'profile.policyGpo').Value | Where-Object Name -eq 'PathToUserStore' | ForEach-Object { $_.Value }))
        foreach ($p in $paths) { $servers | Should -Contain $p.Split('\')[2] -Because $p }
        foreach ($c in @((Get-V 'profile.containers').Value)) { $c.Location.StartsWith('\\fs01\profile$\') | Should -BeTrue -Because $c.Location }
        # domain and users of the sessions are those of the simulation
        $users = @((Get-V 'sessions.list').Value | Where-Object { $_.User })
        @($users | ForEach-Object { $_.User }) | Should -Be @($WorkerPerfSimSessions | ForEach-Object { $_.User })
        @($users | Where-Object { $_.Domain -ne $WorkerPerfSimDomain }).Count | Should -Be 0
        # the process view agrees: the service that is stopped has no process, every Teams process runs the installed Teams
        $snap = Get-WorkerPerfSnapshot -Kind K
        $svc = Get-WorkerPerfServices; $svc.Count | Should -BeGreaterThan 0
        @(@($svc.Values) | Where-Object { ([string]$_).Split(';') -contains 'wuauserv' }).Count | Should -Be 0
        $teamsPath = ($TestApps | Where-Object { $_.key -eq 'teams' }).installed.path
        $teams = @($snap.Processes | Where-Object Name -eq 'ms-teams.exe'); $teams.Count | Should -BeGreaterThan 0
        foreach ($p in $teams) { $p.ExecutablePath | Should -BeLike $teamsPath; $WorkerPerfSimAppState['Files'].ContainsKey($p.ExecutablePath) | Should -BeTrue }
    }
    It 'liest die Anwendungen der Liste: zwei auffaellig, eine in Ordnung, eine nicht installiert' {   # Review Focus 3
        $rows = @((Get-V 'apps.probes').Value); $rows.Count | Should -Be 42                                    # 16 Edge, 14 Office, 8 Teams, 4 simapp
        foreach ($k in 'edge', 'office', 'teams') { (Get-Row $k 'installed').Value | Should -BeTrue -Because $k }
        (Get-Row 'edge' 'backgroundMode').Value | Should -Be 1; (Get-Row 'edge' 'version').Value | Should -Be '130.0.2849.80'; (Get-Row 'edge' 'updateDefault').Value | Should -Be 0
        (Get-Row 'edge' 'userDataDir').State | Should -Be 'absent'; (Get-Row 'edge' 'userDataDir').Reason | Should -Be ''; (Get-Row 'edge' 'updateService').Value | Should -Be 'Manual'
        (Get-Row 'teams' 'disableAutoUpdate').State | Should -Be 'absent'; (Get-Row 'teams' 'disableFallback').Value | Should -Be 2
        (Get-Row 'teams' 'version').Value | Should -Be '24277.3502.3161.3007'; (Get-Row 'teams' 'meetingAddin').Value | Should -BeTrue; (Get-Row 'teams' 'classicTeams').Value | Should -BeFalse
        (Get-Row 'office' 'hideEnableDisableUpdates').Value | Should -Be 1; (Get-Row 'office' 'updateTask').Value | Should -BeFalse; (Get-Row 'office' 'outlookAddins').Value | Should -Be 3
        (Get-Row 'office' 'outlookAddinsWow').State | Should -Be 'absent'; (Get-Row 'office' 'updateUrl').Names | Should -Be '\\fs01\office$\updates'; (Get-Row 'office' 'updateUrl').Value | Should -BeNullOrEmpty
        (Get-Row 'simapp' 'installed').Value | Should -BeFalse
        foreach ($id in 'version', 'cacheMode', 'dataPath') { (Get-Row 'simapp' $id).State | Should -Be 'absent' -Because $id; (Get-Row 'simapp' $id).Reason | Should -Be 'notInstalled' -Because $id }
        $H.Areas['apps'].Status | Should -Be 'read'
        # ohne Anwendungsliste: der Bereich ist gelesen und leer
        [void](Initialize-WorkerPerfSource -StartTime $Start); @((Get-WorkerPerfHealth).Areas['apps'].Values['apps.probes'].Value).Count | Should -Be 0
    }
    It 'liest ohne Zustand nichts' {
        [void](Initialize-WorkerPerfSource -StartTime $Start -Skip Zustand); Get-WorkerPerfHealth | Should -BeNullOrEmpty; [int]$script:WorkerPerfSimReads['health'] | Should -Be 0
    }
}
