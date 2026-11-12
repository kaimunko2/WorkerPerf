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
        $all.Count | Should -Be 18
        foreach ($e in $all) {
            $entry = Resolve-WorkerPerfEventEntry $cfg $e.Log $e.Source $e.EventId
            $entry | Should -Not -BeNullOrEmpty -Because "$($e.Source) $($e.EventId)"
            $e.Group | Should -BeExactly $entry.group; $e.Kind | Should -BeExactly $entry.kind
            # alle Felder eines Datensatzes von ConvertTo-WorkerPerfEventRecord
            @($e.PSObject.Properties.Name | Sort-Object) | Should -Be @('App', 'AppVersion', 'Code', 'Driver', 'EventId', 'Group', 'Kind', 'Level', 'Log', 'Module', 'ModuleVersion',
                'Object', 'Pid', 'Printer', 'Service', 'SessionId', 'Source', 'Text', 'Time', 'User')
        }
    }
    It 'liefert Rueckblick, Treiber und Warteschlangen' {
        $b = Get-WorkerPerfEventsBefore -Days 7 -Until $Start
        @($b.Events).Count | Should -Be 5; @($b.Capped).Count | Should -Be 0
        @((Get-WorkerPerfEventsBefore -Days 4 -Until $Start).Events).Count | Should -Be 3
        @(Get-WorkerPerfPrintDrivers).Manufacturer | Should -Be @('HP', 'Microsoft', 'Kyocera')
        Set-SimTime 43.5; (Get-WorkerPerfPrintQueues | Where-Object Queue -eq 'PRN-EG-01').Jobs | Should -Be 3
    }
    It 'spielt Rueckblick, Treiberliste und Zaehler der Warteschlangen wie im Drehbuch' {
        $b = @((Get-WorkerPerfEventsBefore -Days 7 -Until $Start).Events)
        @($b | ForEach-Object { ($_.Time - $Start).TotalSeconds }) | Should -Be @(-432000, -431000, -259200, -258600, -258000)
        @($b | ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.App, $_.Module, $_.User, $_.SessionId }) | Should -Be @('EXCEL.EXE|simaddin.dll|user001|2',
            'WINWORD.EXE|simaddin.dll|user002|3', 'nexus.exe|nxreport.dll|user004|5', 'nexus.exe|nxreport.dll|user004|5', 'nexus.exe|nxreport.dll|user004|5')
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
        @($e | Where-Object Type -eq 'ereignis').Count | Should -Be 7
        ($e | Where-Object Key -eq 'crash.memory').Patterns | Should -Be @('resource', 'overlap')
        ($e | Where-Object Key -eq 'profile.logon').Patterns.Count | Should -Be 0
        $cpu = $e | Where-Object Key -eq 'cpu'
        $cpu.MainUser | Should -Be 'user003'; $cpu.EndMs - $cpu.StartMs | Should -Be 120000; $cpu.Affected | Should -Be 6
        @($e | Where-Object Chronic).Count | Should -Be 1
    }
    It 'beschreibt die Ereignisvorfaelle und den Rueckblick' {
        $e = @(Get-WorkerPerfExpected); $ms = ([DateTimeOffset]$Start).ToUnixTimeMilliseconds()
        $e.Key | Should -Be @('homeoffice', 'cpu', 'profile.logon', 'memory', 'crash.memory', 'disk', 'share', 'crash.manyusers', 'profile', 'print.spooler',
            'backend', 'hang', 'before.shared.excel', 'before.shared.word', 'before.oneuser')
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
        $rows['cpu'] | Should -Be '||False|||0||300|420|6'
        foreach ($r in @($e | Where-Object Type -eq 'ereignis')) { $r.Lead | Should -BeNullOrEmpty; $r.Chronic | Should -BeFalse; $r.Patterns -is [array] | Should -BeTrue }
        foreach ($r in @($e | Where-Object Type -ne 'ereignis')) { $r.Kind | Should -BeNullOrEmpty; $r.Patterns.Count | Should -Be 0; $r.Before | Should -BeFalse }
    }
    It 'fuehrt die Ereignisprotokolle und Druckquellen als verfuegbar' {
        $cfg = Read-WorkerPerfEventConfig (Join-Path $PSScriptRoot '../src/events.json')
        foreach ($id in @($cfg.Logs.Keys | ForEach-Object { 'events.' + $_ }) + @('print.drivers', 'print.queues')) {
            $Info.Sources.Contains($id) | Should -BeTrue -Because $id; $Info.Sources[$id].Available | Should -BeTrue
        }
    }
}
