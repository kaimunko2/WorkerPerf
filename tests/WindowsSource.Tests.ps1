BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Sources.Windows.ps1')
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Capture.ps1')
    # Die Probe-Klasse wird einmal vorab uebersetzt, damit die Zeitmessung unten nur den Start der Proben misst.
    Start-WorkerPerfProbes -Endpoints @(); [void](Receive-WorkerPerfProbes)
}
Describe 'Windows-Datenquelle: plattformunabhaengige Teile' {
    It 'laesst sich einbinden, ohne etwas auszufuehren' { Get-Command Initialize-WorkerPerfSource, Get-WorkerPerfFastSample, Receive-WorkerPerfProbes | Should -HaveCount 3 }
    It 'zerlegt Instanznamen der Eingabeverzoegerung' {
        $a = ConvertFrom-WorkerPerfInputInstance '1:4232 <Calculator.exe>'
        $a.SessionId | Should -Be 1; $a.Pid | Should -Be 4232; $a.Name | Should -Be 'Calculator.exe'
        (ConvertFrom-WorkerPerfInputInstance 'explorer <3:7964>').Pid | Should -Be 7964
        ConvertFrom-WorkerPerfInputInstance 'Max' | Should -BeNullOrEmpty; ConvertFrom-WorkerPerfInputInstance 'Average' | Should -BeNullOrEmpty
    }
    It 'ordnet einen Profilcontainer dem Benutzer im Pfad zu' {
        $s = @([pscustomobject]@{ SessionId = 5; User = 'mueller' }, [pscustomobject]@{ SessionId = 6; User = 'mu' })
        Resolve-WorkerPerfProfileOwner -Paths @('\\fs01\upm$\Mueller.KLINIK\Win2022\ProfileContainer.vhdx') -Sessions $s | Should -Be 5
        Resolve-WorkerPerfProfileOwner -Paths @('\\fs01\upm$\gast\ProfileContainer.vhdx') -Sessions $s | Should -BeNullOrEmpty
    }
    It 'bildet Ereigniskennungen auf Arten ab' {
        ConvertTo-WorkerPerfEventKind 'Defender' 1000 | Should -Be 'scan-start'
        ConvertTo-WorkerPerfEventKind 'Defender' 1001 | Should -Be 'scan-end'; ConvertTo-WorkerPerfEventKind 'Defender' 1002 | Should -Be 'scan-end'
        ConvertTo-WorkerPerfEventKind 'Defender' 2000 | Should -Be 'signature-update'
        ConvertTo-WorkerPerfEventKind 'AppLocker' 8004 | Should -Be 'applocker-block'; ConvertTo-WorkerPerfEventKind 'AppLocker' 8007 | Should -Be 'applocker-block'
        ConvertTo-WorkerPerfEventKind 'AppLocker' 8002 | Should -BeNullOrEmpty
    }
    It 'misst Verbindungen gleichzeitig und ohne zu blockieren' {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $listener.Start()
        try {
            $port = $listener.LocalEndpoint.Port
            $list = @([pscustomobject]@{ Name = 'offen'; Role = 'x'; Host = '127.0.0.1'; Port = $port },
                                            [pscustomobject]@{ Name = 'zu'; Role = 'x'; Host = '127.0.0.1'; Port = 1 },
                                            [pscustomobject]@{ Name = 'fehlt'; Role = 'x'; Host = 'nohost.invalid'; Port = 80 })
            $sw = [Diagnostics.Stopwatch]::StartNew(); Start-WorkerPerfProbes -Endpoints $list; $sw.ElapsedMilliseconds | Should -BeLessThan 500
            $r = $null; while ($null -eq $r -and $sw.ElapsedMilliseconds -lt 4000) { Start-Sleep -Milliseconds 100; $r = Receive-WorkerPerfProbes }
            @($r).Count | Should -Be 3
            ($r | Where-Object Name -eq 'offen').Error | Should -BeNullOrEmpty; ($r | Where-Object Name -eq 'offen').ConnectMs | Should -BeLessThan 1000
            ($r | Where-Object Name -eq 'zu').Error | Should -Not -BeNullOrEmpty; ($r | Where-Object Name -eq 'fehlt').Error | Should -Not -BeNullOrEmpty
        }
        finally { $listener.Stop() }
    }
}

# Die Eingaben unten sind erfunden, haben aber die Form, die das Pruefskript auf einem VDA (Windows Server 2022,
# de-DE, Citrix Profile Management mit Containern) gemeldet hat.
Describe 'Windows-Datenquelle: Instanznamen und Zuordnungen' {
    It 'nimmt nur ganze Zahlen als Sitzungsinstanz der Eingabeverzoegerung' {
        ConvertFrom-WorkerPerfSessionInstance '55' | Should -Be 55
        foreach ($n in 'Average', 'Max', '_Total', 'Durchschnitt', '', '5a') { ConvertFrom-WorkerPerfSessionInstance $n | Should -BeNullOrEmpty }
        (ConvertFrom-WorkerPerfInputInstance '0:4120 <dienst.exe>').SessionId | Should -Be 0
        (ConvertFrom-WorkerPerfInputInstance '12:880 <Name mit Leerzeichen.exe>').Name | Should -Be 'Name mit Leerzeichen.exe'
    }
    It 'erkennt Summeninstanzen ohne englischen Namen' {
        Test-WorkerPerfTotalInstance '_Total' | Should -BeTrue
        Test-WorkerPerfTotalInstance '_Server gesamt' | Should -BeTrue
        Test-WorkerPerfTotalInstance 'C:' | Should -BeFalse
    }
    It 'schreibt Freigaben mit zwei fuehrenden Schraegstrichen' {
        ConvertTo-WorkerPerfShareName '\fs01\daten' | Should -Be '\\fs01\daten'
        ConvertTo-WorkerPerfShareName '\\fs01\daten' | Should -Be '\\fs01\daten'
        Get-WorkerPerfShareRoot '\\fs01.klinik.local\upm$\mueller.KLINIK\Profile\ProfileContainer_RW.vhdx' | Should -Be '\\fs01.klinik.local\upm$'
        Get-WorkerPerfShareRoot 'C:\Users\x' | Should -Be ''
    }
    It 'findet den Benutzer auch in Zugriffspfaden und anderen Namensschemata' {
        $s = @([pscustomobject]@{ SessionId = 3; User = 'anna.meier' }, [pscustomobject]@{ SessionId = 4; User = 'anna' }, [pscustomobject]@{ SessionId = 7; User = 'mueller' })
        Resolve-WorkerPerfProfileOwner -Paths @('C:\Users\mueller_UPM_local\UpmTempMount\') -Sessions $s | Should -Be 7
        Resolve-WorkerPerfProfileOwner -Paths @('\\fs01\upm$\anna.meier.KLINIK\x.vhdx') -Sessions $s | Should -Be 3      # der laengere Name gewinnt
        Resolve-WorkerPerfProfileOwner -Paths @('\\fs01\upm$\anna.KLINIK\x.vhdx') -Sessions $s | Should -Be 4
        Resolve-WorkerPerfProfileOwner -Paths @('\\fs01\fslogix\S-1-5-21-1-2-3-1108_mueller\Profile_mueller.VHDX') -Sessions $s | Should -Be 7
        Resolve-WorkerPerfProfileOwner -Paths @('\\fs01\upm$\muellerin.KLINIK\x.vhdx') -Sessions $s | Should -BeNullOrEmpty
        Resolve-WorkerPerfProfileOwner -Paths @() -Sessions $s | Should -BeNullOrEmpty
    }
    It 'ordnet nicht zu, wenn ein Benutzer zwei Sitzungen hat' {
        $s = @([pscustomobject]@{ SessionId = 3; User = 'mueller' }, [pscustomobject]@{ SessionId = 9; User = 'Mueller' }, [pscustomobject]@{ SessionId = 0; User = '' })
        Resolve-WorkerPerfProfileOwner -Paths @('\\fs01\upm$\mueller.KLINIK\x.vhdx') -Sessions $s | Should -BeNullOrEmpty
    }
    It 'baut die Zuordnung der drei UPM-Container je Benutzer' {
        $disk = {
            param($User, $File, $Mount, $Volume)
            @{ Location = "\\fs01\upm$\$User.KLINIK\Win2022\UPM_Profile\$File"
                Partitions = @(@{ DriveLetter = ''; AccessPaths = @(); DeviceName = '' },
                    @{ DriveLetter = ''; AccessPaths = @("$Mount\", '\\?\Volume{0f1e2d3c-0000-0000-0000-00000000000' + $Volume + '}\'); DeviceName = "\Device\HarddiskVolume$Volume" }) }
        }
        $disks = @(
            (& $disk 'mueller' 'ProfileContainer_RW.vhdx' 'C:\Users\mueller_UPM_local\UpmTempMount' 1)
            (& $disk 'mueller' 'OutlookOST.vhdx' 'C:\Users\mueller_UPM_local\UpmTempMount\Profiles\mueller\AppData\Local\Microsoft\Outlook' 2)
            (& $disk 'mueller' 'OutlookSearchIndex.vhdx' 'C:\Users\mueller_UPM_local\UpmTempMount\Profiles\mueller\AppData\Roaming\Microsoft\Search' 3)
            (& $disk 'gast' 'ProfileContainer_RW.vhdx' 'C:\Users\gast_UPM_local\UpmTempMount' 4))
        $sessions = @([pscustomobject]@{ SessionId = 0; User = '' }, [pscustomobject]@{ SessionId = 5; User = 'mueller' })
        $map = New-WorkerPerfProfileMap -Disks $disks -Sessions $sessions -Known @('C:', 'D:', 'HarddiskVolume1')
        $e = $map.Entries['C:\Users\mueller_UPM_local\UpmTempMount']
        $e.Kind | Should -Be 'profile'; $e.SessionId | Should -Be 5; $e.Backing | Should -Be '\\fs01\upm$'
        $map.Entries['C:\Users\mueller_UPM_local\UpmTempMount\Profiles\mueller\AppData\Local\Microsoft\Outlook'].SessionId | Should -Be 5
        $map.Entries['HarddiskVolume3'].SessionId | Should -Be 5                    # ueber den Geraetenamen, falls der Zugriffspfad fehlt
        $g = $map.Entries['C:\Users\gast_UPM_local\UpmTempMount']
        $g.Kind | Should -Be 'profile'; $g.SessionId | Should -BeNullOrEmpty
        $map.Entries.ContainsKey('C:') | Should -BeFalse
        $map.Known.ContainsKey('D:') | Should -BeTrue
        @(Get-WorkerPerfUnknownVolumes -Instances @('C:', 'D:', 'C:\Users\gast_UPM_local\UpmTempMount', 'C:\Users\neu_UPM_local\UpmTempMount', '_Total') -Map $map) |
            Should -Be @('C:\Users\neu_UPM_local\UpmTempMount')
        @(Get-WorkerPerfUnknownVolumes -Instances @('C:') -Map $null) | Should -Be @('C:')
    }
    It 'ordnet ICA-Instanzen ueber die WinStation oder den Benutzer zu' {
        $s = @([pscustomobject]@{ SessionId = 0; WinStation = 'Services'; User = '' },
            [pscustomobject]@{ SessionId = 7; WinStation = 'ICA-CGP#2'; User = 'mueller' },
            [pscustomobject]@{ SessionId = 9; WinStation = ''; User = 'anna' })
        Resolve-WorkerPerfIcaSession 'ICA-CGP 2 (mueller)' $s | Should -Be 7
        Resolve-WorkerPerfIcaSession 'ICA-CGP 2 (KLINIK\mueller)' $s | Should -Be 7
        Resolve-WorkerPerfIcaSession 'ICA-CGP 5 (KLINIK\anna)' $s | Should -Be 9
        Resolve-WorkerPerfIcaSession 'ICA-CGP 6 (gast)' $s | Should -BeNullOrEmpty
        Resolve-WorkerPerfIcaSession '_Server gesamt' $s | Should -BeNullOrEmpty
    }
}

Describe 'Windows-Datenquelle: Umrechnung der Leistungsindikatoren' {
    BeforeAll {
        # Werte, wie sie CounterSample.Calculate liefert: Antwortzeiten in s, Raten je s, Steal laut Zaehlertyp Timer100Ns in %
        $script:Values = @{
            cpu = @{ '% Processor Time' = @{ '_Total' = 31.5; '0,_Total' = 33.0 } }
            queue = @{ 'Processor Queue Length' = @{ 'systemdiagnosticsperfcounterlibsingleinstance' = 3.0 } }
            steal = @{ 'CPU stolen time' = @{ '_Total' = 1.5 } }
            memory = @{ 'Available Bytes' = @{ '' = 34359738368.0 }; 'Committed Bytes' = @{ '' = 38654705664.0 }; 'Commit Limit' = @{ '' = 85899345920.0 }; 'Pages Input/sec' = @{ '' = 12.5 } }
            disk = @{ 'Disk Read Bytes/sec' = @{ '_Total' = 4096.0 }; 'Disk Write Bytes/sec' = @{ '_Total' = 120000.0 }; 'Disk Reads/sec' = @{ '_Total' = 2.0 }
                'Disk Writes/sec' = @{ '_Total' = 20.5 }; 'Current Disk Queue Length' = @{ '_Total' = 1.0 } }
            network = @{ 'Bytes Received/sec' = @{ 'Ethernet-Adapter 1' = 6000.0; 'isatap' = 300.5 }; 'Bytes Sent/sec' = @{ 'Ethernet-Adapter 1' = 10000.0; 'isatap' = 0.0 } }
            volumes = @{
                'Avg. Disk sec/Read' = @{ 'C:' = 0.0021; 'C:\Users\mueller_UPM_local\UpmTempMount' = 0.044; '_Total' = 0.003 }
                'Avg. Disk sec/Write' = @{ 'C:' = 0.000075; 'C:\Users\mueller_UPM_local\UpmTempMount' = 0.0 ; '_Total' = 0.001 }
                'Disk Reads/sec' = @{ 'C:' = 10.0; 'C:\Users\mueller_UPM_local\UpmTempMount' = 25.0; '_Total' = 35.0 }
                'Disk Writes/sec' = @{ 'C:' = 6.2; 'C:\Users\mueller_UPM_local\UpmTempMount' = 0.0; '_Total' = 5.99 }
                'Disk Read Bytes/sec' = @{ 'C:' = 81920.0; 'C:\Users\mueller_UPM_local\UpmTempMount' = 6291456.0; '_Total' = 1.0 }
                'Disk Write Bytes/sec' = @{ 'C:' = 20000.0; 'C:\Users\mueller_UPM_local\UpmTempMount' = 0.0; '_Total' = 1.0 }
                'Current Disk Queue Length' = @{ 'C:' = 0.0; 'C:\Users\mueller_UPM_local\UpmTempMount' = 3.0; '_Total' = 3.0 } }
            shares = @{
                'Avg. sec/Read' = @{ '\fs01\daten' = 0.08; '_Total' = 0.08 }; 'Avg. sec/Write' = @{ '\fs01\daten' = 0.0; '_Total' = 0.0 }
                'Read Requests/sec' = @{ '\fs01\daten' = 50.0; '_Total' = 50.0 }; 'Write Requests/sec' = @{ '\fs01\daten' = 0.0; '_Total' = 0.0 }
                'Read Bytes/sec' = @{ '\fs01\daten' = 1048576.0; '_Total' = 1048576.0 }; 'Write Bytes/sec' = @{ '\fs01\daten' = 0.0; '_Total' = 0.0 } }
            inputSession = @{ 'Max Input Delay' = @{ '0' = 0.0; '2' = 16.0; '55' = 312.0; 'Average' = 0.29; 'Max' = 312.0 } }
            inputProcess = @{ 'Max Input Delay' = @{ '0:4120 <dienst.exe>' = 0.0; '55:7964 <EXCEL.EXE>' = 312.0; '2:880 <explorer.exe>' = 16.0 } }
        }
        $script:Map = New-WorkerPerfProfileMap -Disks @(@{ Location = '\\fs01\upm$\mueller.KLINIK\ProfileContainer_RW.vhdx'
                Partitions = @(@{ DriveLetter = ''; AccessPaths = @('C:\Users\mueller_UPM_local\UpmTempMount\'); DeviceName = '' }) }) `
            -Sessions @([pscustomobject]@{ SessionId = 55; User = 'mueller' }) -Known @('C:')
        $script:Time = [datetime]::Now
        $script:S = ConvertTo-WorkerPerfWinFastSample -Values $Values -ElapsedSec 2 -Time $Time -ProfileMap $Map -LogicalProcessors 6
    }
    It 'liefert die Host-Werte laut Zaehlertabelle' {
        $S.Time | Should -Be $Time; $S.Time.Kind | Should -Be 'Local'
        $S.CpuPct | Should -Be 31.5; $S.ProcQueue | Should -Be 3; $S.StealPct | Should -Be 0.25        # _Total ueber 6 vCPUs
        $S.MemAvailMB | Should -Be 32768; $S.MemCommittedMB | Should -Be 36864; $S.MemCommitLimitMB | Should -Be 81920; $S.PagesInPerSec | Should -Be 12.5
        $S.DiskReadBps | Should -Be 4096; $S.DiskWriteIops | Should -Be 20.5; $S.DiskQueue | Should -Be 1
        $S.NetRecvBps | Should -Be 6300.5; $S.NetSentBps | Should -Be 10000
    }
    It 'rechnet Laufwerke in ms und Zugriffe im Takt um, ohne Summe' {
        @($S.Volumes).Count | Should -Be 2
        $c = $S.Volumes | Where-Object Volume -eq 'C:'
        $c.Kind | Should -Be 'disk'; $c.SessionId | Should -BeNullOrEmpty; $c.Backing | Should -Be ''
        $c.ReadLatMs | Should -Be 2.1; $c.WriteLatMs | Should -Be 0.075; $c.ReadOps | Should -Be 20; $c.WriteOps | Should -Be 12; $c.ReadBps | Should -Be 81920; $c.WriteBps | Should -Be 20000
        $p = $S.Volumes | Where-Object Kind -eq 'profile'
        $p.SessionId | Should -Be 55; $p.Backing | Should -Be '\\fs01\upm$'; $p.ReadLatMs | Should -Be 44; $p.ReadOps | Should -Be 50; $p.Queue | Should -Be 3
    }
    It 'liefert Freigaben und Eingabeverzoegerung ohne Summen' {
        @($S.Shares).Count | Should -Be 1; $S.Shares[0].Share | Should -Be '\\fs01\daten'; $S.Shares[0].ReadLatMs | Should -Be 80; $S.Shares[0].ReadOps | Should -Be 100
        @($S.InputSessions).SessionId | Sort-Object | Should -Be @(0, 2, 55)
        ($S.InputSessions | Where-Object SessionId -eq 55).DelayMs | Should -Be 312
        @($S.InputProcesses).Count | Should -Be 2
        ($S.InputProcesses | Where-Object Pid -eq 7964).Name | Should -Be 'EXCEL.EXE'
    }
    It 'meldet eine fehlende Kategorie als leere Werte, ohne abzubrechen' {
        $v = $Values.Clone(); $v.cpu = $null; $v.volumes = $null; $v.inputProcess = $null; $v.steal = $null
        $x = ConvertTo-WorkerPerfWinFastSample -Values $v -ElapsedSec 2 -Time $Time -ProfileMap $null -LogicalProcessors 6
        $x.CpuPct | Should -BeNullOrEmpty; $x.StealPct | Should -BeNullOrEmpty; $x.MemAvailMB | Should -Not -BeNullOrEmpty
        @($x.Volumes).Count | Should -Be 0; @($x.InputProcesses).Count | Should -Be 0; @($x.InputSessions).Count | Should -Be 3
    }
    It 'berechnet Werte aus zwei Lesungen und ueberspringt neue Instanzen' {
        $mk = { param([hashtable]$Inst) $c = @{}; foreach ($k in $Inst.Keys) { $c[$k] = [pscustomobject]@{ InstanceName = $k; Sample = $Inst[$k] } }; $c }
        $prev = @{ 'max input delay' = (& $mk @{ '2' = @{ RawValue = 16; Value = 0 }; '3' = @{ RawValue = 31; Value = 0 } }) }
        $cur = @{ 'max input delay' = (& $mk @{ '2' = @{ RawValue = 16; Value = 9 }; '3' = @{ RawValue = 62; Value = 31 }; '4' = @{ RawValue = 5; Value = 5 } }) }
        function Get-WorkerPerfWinSampleValue($Previous, $Current) { $Current.Value }
        $r = Get-WorkerPerfWinCounterValues -Previous $prev -Current $cur -Counters @('Max Input Delay')
        $r['Max Input Delay']['2'] | Should -Be 9; $r['Max Input Delay']['3'] | Should -Be 31; $r['Max Input Delay'].ContainsKey('4') | Should -BeFalse
        $z = Get-WorkerPerfWinCounterValues -Previous $prev -Current $cur -Counters @('Max Input Delay', 'fehlt') -ZeroUnchanged
        $z['Max Input Delay']['2'] | Should -Be 0; $z['Max Input Delay']['3'] | Should -Be 31; $z['fehlt'].Count | Should -Be 0
    }
    It 'rechnet die entzogene CPU-Zeit aus Millisekunden in Prozent um' {
        # Groessenordnung des Pruefergebnisses: der Rohwert waechst um 15 in gut 1 s (erfundene Zahlen)
        $p = ConvertTo-WorkerPerfStealPct -Raw1 500000 -Raw2 500015 -Time1 100000000000000000 -Time2 100000000010010000
        [Math]::Round($p, 4) | Should -Be 1.4985
        ConvertTo-WorkerPerfStealPct -Raw1 5 -Raw2 5 -Time1 0 -Time2 20000000 | Should -Be 0
        ConvertTo-WorkerPerfStealPct -Raw1 5 -Raw2 9 -Time1 7 -Time2 7 | Should -BeNullOrEmpty                 # ohne Zeitabstand kein Wert
        ConvertTo-WorkerPerfStealPct -Raw1 9 -Raw2 5 -Time1 0 -Time2 20000000 | Should -BeNullOrEmpty           # Zaehler zurueckgesetzt
        $mk = { param([hashtable]$Inst) $c = @{}; foreach ($k in $Inst.Keys) { $c[$k] = [pscustomobject]@{ InstanceName = $k; Sample = $Inst[$k] } }; $c }
        $prev = @{ 'cpu stolen time' = (& $mk @{ '_Total' = @{ RawValue = 500000; TimeStamp100nSec = 100000000000000000 } }) }
        $cur = @{ 'cpu stolen time' = (& $mk @{ '_Total' = @{ RawValue = 500030; TimeStamp100nSec = 100000000020000000 } }) }
        $r = Get-WorkerPerfWinCounterValues -Previous $prev -Current $cur -Counters @('CPU stolen time') -MsPercent
        $r['CPU stolen time']['_Total'] | Should -Be 1.5
    }
    It 'schreibt die entzogene CPU-Zeit je vCPU, ohne sie auf 0 zu runden' {
        $v = $Values.Clone(); $v.steal = @{ 'CPU stolen time' = @{ '_Total' = 0.05 } }            # 1 ms in 2 s auf 6 vCPUs
        $x = ConvertTo-WorkerPerfWinFastSample -Values $v -ElapsedSec 2 -Time $Time -ProfileMap $null -LogicalProcessors 6
        $row = ConvertTo-WorkerPerfFastRows -Sample $x -T 0 -ElapsedSec 2 -Burst $false -CollectMs 1
        $row.Tick.Split(',')[5] | Should -Be '0.008'
        $v.steal = @{ 'CPU stolen time' = @{ '_Total' = 3.0; '0' = 1.0; '1' = 2.0 } }             # Instanzen je vCPU haben Vorrang
        (ConvertTo-WorkerPerfWinFastSample -Values $v -ElapsedSec 2 -Time $Time -ProfileMap $null -LogicalProcessors 6).StealPct | Should -Be 1.5
    }
}

Describe 'Windows-Datenquelle: Citrix, Dienste, Ereignisse, Warten' {
    It 'schreibt ICA-Werte je Sitzung, ohne Summe und ohne Bandbreiten von 0' {
        $values = @{ 'Latency - Last Recorded' = @{ '_Server gesamt' = 0.0; 'ICA-CGP 2 (mueller)' = 0.0 }
            'Output Session Bandwidth' = @{ '_Server gesamt' = 4104.0; 'ICA-CGP 2 (mueller)' = 280.0 }
            'Input Audio Bandwidth' = @{ '_Server gesamt' = 0.0; 'ICA-CGP 2 (mueller)' = 0.0 } }
        $s = @([pscustomobject]@{ SessionId = 7; WinStation = 'ICA-CGP#2'; User = 'mueller' })
        $rows = @(ConvertTo-WorkerPerfIcaRows -Values $values -Sessions $s | Sort-Object Metric)
        $rows.Count | Should -Be 2
        $rows[0].Metric | Should -Be 'Latency - Last Recorded'; $rows[0].Value | Should -Be 0; $rows[0].SessionId | Should -Be 7
        $rows[0].Source | Should -Be 'ICA Session'; $rows[0].Instance | Should -Be 'ICA-CGP 2 (mueller)'
        $rows[1].Metric | Should -Be 'Output Session Bandwidth'
        @(ConvertTo-WorkerPerfIcaRows -Values @{ 'Latency - Last Recorded' = @{} } -Sessions $s).Count | Should -Be 0     # ohne ICA-Sitzung
    }
    It 'ordnet 60 Sitzungen mit 54 Zaehlern zuegig zu' {
        $sessions = @(foreach ($k in 0..60) { [pscustomobject]@{ SessionId = $k + 2; WinStation = "ICA-CGP#$k"; User = "user$k" } })
        $values = @{}
        foreach ($c in 1..54) {
            $inst = @{ '_Server gesamt' = 1.0 }
            foreach ($k in 0..59) { $inst["ICA-CGP $k (user$k)"] = [double]$c }
            $values["Latency $c"] = $inst
        }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $rows = @(ConvertTo-WorkerPerfIcaRows -Values $values -Sessions $sessions)
        $sw.Elapsed.TotalSeconds | Should -BeLessThan 3
        $rows.Count | Should -Be 3240
        @($rows | Where-Object Instance -eq 'ICA-CGP 7 (user7)' | ForEach-Object SessionId | Sort-Object -Unique) | Should -Be @(9)
    }
    It 'liest Citrix-EUEM-Werte nach dem Filter' {
        $inst = @([pscustomobject]@{ SessionID = [uint32]7; RoundtripTime = [uint32]42; NetworkLatency = [uint32]0; InputBandwidthUsed = [uint32]0; ProcessId = '1234'; InstanceId = 'x'; Timestamp = [datetime]::Now })
        $rows = @(ConvertTo-WorkerPerfCimCitrixRows -Instances $inst -Source 'Citrix_Euem_RoundTrip' -MetricFilter 'Latency|Round|Bandwidth')
        @($rows.Metric) | Should -Be @('RoundtripTime', 'NetworkLatency')
        $rows[0].SessionId | Should -Be 7; $rows[0].Value | Should -Be 42; $rows[0].Instance | Should -Be ''
    }
    It 'fasst Dienste je Prozess zusammen' {
        $m = ConvertTo-WorkerPerfServiceMap @([pscustomobject]@{ Name = 'RpcSs'; ProcessId = 900 }, [pscustomobject]@{ Name = 'RpcEptMapper'; ProcessId = 900 },
            [pscustomobject]@{ Name = 'Spooler'; ProcessId = 0 }, [pscustomobject]@{ Name = 'CylanceSvc'; ProcessId = 4000 })
        $m[900] | Should -Be 'RpcEptMapper;RpcSs'; $m[4000] | Should -Be 'CylanceSvc'; $m.ContainsKey(0) | Should -BeFalse
    }
    It 'kuerzt Ereignistexte auf die erste Zeile und 200 Zeichen' {
        Get-WorkerPerfEventText "Scan gestartet.`r`n Scan-ID: {1}" | Should -Be 'Scan gestartet.'
        (Get-WorkerPerfEventText ('x' * 300)).Length | Should -Be 200
        Get-WorkerPerfEventText $null | Should -Be ''
    }
    It 'behaelt bei mehr als 200 Ereignissen die neuesten und warnt einmal je Protokoll' {
        . (Join-Path $PSScriptRoot 'WindowsStandIns.ps1'); Reset-WinStandIns
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) 3>$null)
        $script:WinFake.ManyEvents = 250
        $out = @(Get-WorkerPerfEvents -Since ([datetime]::Now.AddHours(-1)) 3>&1)
        $warn = @($out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $ev = @($out | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
        $ev.Count | Should -Be 200
        ($ev | Measure-Object -Property Time -Minimum).Minimum | Should -BeGreaterThan ([datetime]::Now.AddSeconds(-202))
        $warn.Count | Should -Be 1; $warn[0].Message | Should -Match 'Defender'
        @(Get-WorkerPerfEvents -Since ([datetime]::Now.AddHours(-1)) 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 0
    }
    It 'wartet bis zur Zielzeit und meldet die Stopp-Datei' {
        $flag = Join-Path $TestDrive 'stop.flag'
        $sw = [Diagnostics.Stopwatch]::StartNew()
        Wait-WorkerPerfTick -Until ([datetime]::Now.AddMilliseconds(700)) -StopFlagPath $flag | Should -BeFalse
        $sw.ElapsedMilliseconds | Should -BeGreaterOrEqual 650
        Wait-WorkerPerfTick -Until ([datetime]::UtcNow.AddMilliseconds(300)) -StopFlagPath '' | Should -BeFalse
        Set-Content -LiteralPath $flag -Value ''
        $sw.Restart()
        Wait-WorkerPerfTick -Until ([datetime]::Now.AddSeconds(30)) -StopFlagPath $flag | Should -BeTrue
        $sw.ElapsedMilliseconds | Should -BeLessThan 1000
    }
    It 'meldet den freien Platz des Laufwerks' { Get-WorkerPerfFreeSpaceMB -Path $TestDrive | Should -BeGreaterThan 0 }
    It 'liefert die Zeit des Servers als Ortszeit' { (Get-WorkerPerfNow).Kind | Should -Be 'Local' }
}

Describe 'Windows-Datenquelle mit nachgestellten Windows-Aufrufen' {
    # Nur die untersten Windows-Aufrufe (Leistungsindikatoren, CIM, Ereignisprotokoll, WTS) werden ersetzt; alles
    # darueber laeuft wie auf dem Server. Die Daten haben die Form des Pruefergebnisses, die Namen sind erfunden.
    BeforeAll {
        . (Join-Path $PSScriptRoot 'WindowsStandIns.ps1')
    }
    BeforeEach { Reset-WinStandIns }
    It 'meldet Eckdaten und verfuegbare Quellen' {
        $info = Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -Endpoints @([pscustomobject]@{ name = 'Oracle'; host = '127.0.0.1'; port = 1; role = 'Datenbank' }) `
            -CitrixMetricFilter 'Latency|Round' 3>$null
        $info.Computer | Should -Be 'VDA-TEST'; $info.LogicalProcessors | Should -Be 6; $info.PhysicalMemoryMB | Should -Be 59392; $info.CollectorPid | Should -Be $PID
        $info.OS | Should -Be 'Microsoft Windows Server 2022 Standard 10.0.20348'
        @($info.Endpoints).Count | Should -Be 1
        foreach ($id in 'cpu.host', 'cpu.queue', 'cpu.steal', 'mem.used', 'mem.commit', 'mem.pagesin', 'input.session', 'disk.latency', 'smb.latency',
            'ica.rtt', 'ica.latency', 'probe.connect', 'process', 'sessions', 'input.process', 'profile.map', 'events.defender', 'events.applocker') {
            $info.Sources.Contains($id) | Should -BeTrue
            $info.Sources[$id].Available | Should -BeTrue -Because $id
        }
    }
    It 'meldet fehlende Kategorien, Klassen und Protokolle als nicht verfuegbar' {
        $script:WinFake.Perf.Remove('VM Processor'); $script:WinFake.Perf.Remove('ICA Session'); $script:WinFake.EuemClass = $false
        $script:WinFake.Logs = @('Microsoft-Windows-Windows Defender/Operational')
        $info = Initialize-WorkerPerfSource -StartTime ([datetime]::Now) 3>$null
        $info.Sources['cpu.steal'].Available | Should -BeFalse; $info.Sources['cpu.steal'].Detail | Should -Match 'VM Processor'
        $info.Sources['ica.rtt'].Available | Should -BeFalse; $info.Sources['ica.latency'].Available | Should -BeFalse
        $info.Sources['probe.connect'].Available | Should -BeFalse
        $info.Sources['events.applocker'].Available | Should -BeFalse; $info.Sources['events.defender'].Available | Should -BeTrue
        (Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -NoCitrix 3>$null).Sources['ica.rtt'].Detail | Should -Match 'NoCitrix'
    }
    It 'liefert den schnellen Messwert ab der zweiten Lesung' {
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) 3>$null)
        $first = Get-WorkerPerfFastSample
        $first.CpuPct | Should -BeNullOrEmpty
        [void](Get-WorkerPerfSnapshot -Kind K)                                       # wie im Collector: Grundlage mit Stuetzpunkt
        $s = Get-WorkerPerfFastSample
        $s.CpuPct | Should -Be 27.5; $s.Time.Kind | Should -Be 'Local'
        [Math]::Round($s.StealPct, 4) | Should -Be 0.0083                          # 1 ms je 2 s der Nachbildung, auf 6 vCPUs
        $p = @($s.Volumes | Where-Object Kind -eq 'profile')
        $p.Count | Should -Be 2
        ($p | Where-Object Volume -eq 'C:\Users\mueller_UPM_local\UpmTempMount').SessionId | Should -Be 2
        ($p | Where-Object Volume -eq 'C:\Users\gast_UPM_local\UpmTempMount').SessionId | Should -BeNullOrEmpty
        @($s.InputSessions).Count | Should -Be 2; @($s.Shares).Share | Should -Be @('\\fs01\daten')
    }
    It 'baut die Profilzuordnung beim Stuetzpunkt und fuer neue Laufwerke beim naechsten regulaeren Schnappschuss neu' {
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) 3>$null)
        [void](Get-WorkerPerfFastSample); [void](Get-WorkerPerfSnapshot -Kind K); [void](Get-WorkerPerfFastSample)
        $builds = $script:WinFake.DiskQueries
        [void](Get-WorkerPerfSnapshot -Kind R); [void](Get-WorkerPerfFastSample)
        $script:WinFake.DiskQueries | Should -Be $builds                                # nichts Neues: kein Neuaufbau
        Add-WinStandInUser -SessionId 3 -User 'neu' -Volume 'C:\Users\neu_UPM_local\UpmTempMount'
        [void](Get-WorkerPerfFastSample); $s = Get-WorkerPerfFastSample
        $script:WinFake.DiskQueries | Should -Be $builds                                # nie im schnellen Takt
        $n = $s.Volumes | Where-Object Volume -eq 'C:\Users\neu_UPM_local\UpmTempMount'
        $n.Kind | Should -Be 'profile'; $n.SessionId | Should -BeNullOrEmpty
        [void](Get-WorkerPerfSnapshot -Kind B)
        $script:WinFake.DiskQueries | Should -Be $builds                                # nicht im verdichteten Schnappschuss
        [void](Get-WorkerPerfSnapshot -Kind R)
        $script:WinFake.DiskQueries | Should -Be ($builds + 1)
        ($s = Get-WorkerPerfFastSample) | Out-Null
        ($s.Volumes | Where-Object Volume -eq 'C:\Users\neu_UPM_local\UpmTempMount').SessionId | Should -Be 3
        ($s.Volumes | Where-Object Volume -eq 'C:').Kind | Should -Be 'disk'
        [void](Get-WorkerPerfSnapshot -Kind K)
        $script:WinFake.DiskQueries | Should -Be ($builds + 2)                          # jeder Stuetzpunkt baut neu
    }
    It 'startet, wenn die Pruefung eines Zaehlers scheitert, und meldet das Signal als nicht verfuegbar' {
        $script:WinFake.ThrowCheck = 'LogicalDisk'
        $info = Initialize-WorkerPerfSource -StartTime ([datetime]::Now) 3>$null
        $info.Sources['disk.latency'].Available | Should -BeFalse; $info.Sources['disk.latency'].Detail | Should -Match 'Leistungsindikatoren beschaedigt'
        $info.Sources['cpu.host'].Available | Should -BeTrue
    }
    It 'laeuft weiter, wenn eine Kategorie beim Lesen scheitert' {
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) 3>$null)
        [void](Get-WorkerPerfFastSample)
        $script:WinFake.FailRead = 'LogicalDisk'
        $s = Get-WorkerPerfFastSample 3>$null
        @($s.Volumes).Count | Should -Be 0; $s.CpuPct | Should -Be 27.5
    }
    It 'liefert Schnappschuss, Dienste und Ereignisse' {
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -CitrixMetricFilter 'Latency|Round' 3>$null)
        $snap = Get-WorkerPerfSnapshot -Kind K
        $snap.Time.Kind | Should -Be 'Local'
        @($snap.Processes).Count | Should -Be 2; @($snap.Sessions).Count | Should -Be 2
        $ica = @($snap.Citrix | Where-Object Source -eq 'ICA Session'); $ica.Count | Should -Be 1; $ica[0].SessionId | Should -Be 2
        @($snap.Citrix | Where-Object Metric -eq 'RoundtripTime').Count | Should -Be 1
        (Get-WorkerPerfServices)[900] | Should -Be 'RpcSs'
        $ev = @(Get-WorkerPerfEvents -Since ([datetime]::Now.AddMinutes(-5)))
        @($ev.Kind) | Should -Be @('scan-start', 'scan-end')
        $ev[0].Source | Should -Be 'Defender'; $ev[0].Text | Should -Be 'Die Ueberpruefung wurde gestartet.'
    }
    It 'liefert Prozesse und Sitzungen, wenn die Citrix-Abfrage scheitert' {
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -CitrixMetricFilter 'Latency|Round' 3>$null)
        $script:WinFake.FailCitrix = $true; $script:WinFake.FailRead = 'ICA Session'
        $snap = Get-WorkerPerfSnapshot 3>$null
        @($snap.Processes).Count | Should -Be 2; @($snap.Citrix).Count | Should -Be 0
    }
}

Describe 'Collector mit der Windows-Datenquelle und nachgestellten Windows-Aufrufen' {
    BeforeAll {
        # Kopie von src: die Windows-Sperre der gemeinsamen Datei und die untersten Windows-Aufrufe sind ersetzt
        $dir = Join-Path $TestDrive 'src'; [void](New-Item -ItemType Directory -Path $dir -Force)
        Copy-Item (Join-Path $PSScriptRoot '../src/*') $dir
        [IO.File]::AppendAllText((Join-Path $dir 'WorkerPerf.Common.ps1'), "`nfunction Test-WorkerPerfWindows { return `$true }`n")
        [IO.File]::AppendAllText((Join-Path $dir 'WorkerPerf.Sources.Windows.ps1'),
            "`n" + [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'WindowsStandIns.ps1')) + "`nReset-WinStandIns`n")
        [cultureinfo]::CurrentCulture = [cultureinfo]'de-DE'
        $out = Join-Path $TestDrive 'out'
        $script:Run = (& (Join-Path $dir 'Start-WorkerPerfCapture.ps1') -OutputPath $out -DurationMinutes 0.12 -FastIntervalSeconds 1 -IntervalSeconds 5 3>$null 6>$null) |
            Select-Object -Last 1
        $script:Meta = Get-Content (Join-Path $Run 'meta.json') -Raw | ConvertFrom-Json
    }
    It 'schreibt Takte mit Werten in jeder verfuegbaren Spalte' {
        $Meta.EndReason | Should -Be 'duration'; $Meta.Simulated | Should -BeFalse; $Meta.Ticks | Should -BeGreaterOrEqual 5
        @($Meta.SourceErrors.PSObject.Properties).Count | Should -Be 0
        $t = @(Import-Csv (Join-Path $Run 'ticks.csv'))
        foreach ($col in 'CpuPct', 'ProcQueue', 'StealPct', 'MemAvailMB', 'MemCommittedMB', 'MemCommitLimitMB', 'PagesInPerSec', 'DiskReadBps', 'DiskWriteBps',
            'DiskReadIops', 'DiskWriteIops', 'DiskQueue', 'NetRecvBps', 'NetSentBps') { $t[0].$col | Should -Not -BeNullOrEmpty -Because $col }
    }
    It 'schreibt Profilcontainer, Freigaben, Eingabeverzoegerung, Prozesse und Citrix-Werte' {
        $v = @(Import-Csv (Join-Path $Run 'volumes.csv') | Where-Object Kind -eq 'profile')
        $v.Count | Should -BeGreaterThan 0; ($v | Where-Object SessionId -eq '2')[0].Backing | Should -Be '\\fs01\upm$'
        @(Import-Csv (Join-Path $Run 'shares.csv'))[0].Share | Should -Be '\\fs01\daten'
        @(Import-Csv (Join-Path $Run 'inputdelay_proc.csv'))[0].Name | Should -Be 'EXCEL.EXE'
        @(Import-Csv (Join-Path $Run 'procinfo.csv')).Name | Should -Contain 'EXCEL.EXE'
        @(Import-Csv (Join-Path $Run 'sessions.csv')).User | Should -Contain 'mueller'
        @(Import-Csv (Join-Path $Run 'citrix.csv')).Metric | Should -Contain 'Latency - Last Recorded'
    }
}
