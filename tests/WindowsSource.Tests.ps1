BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.EventConfig.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Sources.Windows.ps1')
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
    # Aussage ersetzt (Task 10): 'bildet Ereigniskennungen auf Arten ab' prueft jetzt die Zuordnung ueber events.json (unten), weil die feste Zuordnung dorthin umzieht
    It 'liest Treiberversion und Isolationsgruppen' {
        ConvertFrom-WorkerPerfDriverVersion (([uint64]61 -shl 48) + ([uint64]1 -shl 32) + 2) | Should -Be '61.1.0.2'   # [uint64] vor dem Schieben: ein Int32 schiebt nur um 48 mod 32
        ConvertFrom-WorkerPerfDriverVersion ([uint64]0) | Should -Be ''
        $g = ConvertFrom-WorkerPerfIsolationGroups 'Sim A\Sim B\\Sim C\\Sim D\\Sim E'
        $g['sim a'] | Should -Be 'none'; $g['Sim B'] | Should -Be 'none'; $g['Sim C'] | Should -Be 'shared'; $g['Sim D'] | Should -Be 'isolated'; $g['Sim E'] | Should -Be 'isolated'
        (ConvertFrom-WorkerPerfIsolationGroups '').Count | Should -Be 0; (ConvertFrom-WorkerPerfIsolationGroups $null).Count | Should -Be 0
    }
    It 'leitet die wirksame Isolierung wie das Pruefskript ab (P1-R29)' -TestCases @(
        @{ Name = 'Sim C'; Groups = 'Sim A\\Sim C'; Attr = 0; Exec = 1; Override = $null; Want = 'shared' }      # Gruppe geht vor
        @{ Name = 'Sim C'; Groups = 'Sim A\\Sim B\\Sim C'; Attr = 4; Exec = $null; Override = $null; Want = 'isolated' }
        @{ Name = 'Sim C'; Groups = 'Sim A\\Sim C'; Attr = 4; Exec = 0; Override = $null; Want = 'none' }      # Isolierung abgeschaltet
        @{ Name = 'Sim X'; Groups = $null; Attr = 4; Exec = 1; Override = $null; Want = 'shared' }               # isolierbar laut Attribut 0x4
        @{ Name = 'Sim X'; Groups = $null; Attr = 2; Exec = 1; Override = $null; Want = 'none' }
        @{ Name = 'Sim X'; Groups = $null; Attr = 2; Exec = $null; Override = 1; Want = 'shared' }               # Kompatibilitaet uebersteuert
        @{ Name = 'Sim X'; Groups = $null; Attr = $null; Exec = 1; Override = $null; Want = '' }                 # Attribut nicht gelesen
        @{ Name = 'Sim X'; Groups = $null; Attr = -2147483644; Exec = 1; Override = $null; Want = 'shared' }     # DWORD mit gesetztem Vorzeichenbit
    ) {
        $policy = @{}
        if ($null -ne $Exec) { $policy['PrintDriverIsolationExecutionPolicy'] = $Exec }
        if ($null -ne $Override) { $policy['PrintDriverIsolationOverrideCompat'] = $Override }
        Get-WorkerPerfEffectiveIsolation $Name (ConvertFrom-WorkerPerfIsolationGroups $Groups) $Attr $policy | Should -Be $Want
    }
    It 'liest die Warteschlangen ohne Summe' {
        $v = @{ 'Jobs' = @{ '_Total' = 3.0; 'PRN-A' = 1.0; 'PRN-B' = 2.0 }; 'Job Errors' = @{ '_Total' = 5.0; 'PRN-A' = 5.0; 'PRN-B' = 0.0 }; 'Not Ready Errors' = @{ 'PRN-A' = 1.0 } }
        $q = @(ConvertTo-WorkerPerfPrintQueueRows $v)
        $q.Queue | Should -Be @('PRN-A', 'PRN-B'); $q[0].JobErrors | Should -Be 5; $q[0].NotReadyErrors | Should -Be 1; $q[1].NotReadyErrors | Should -BeNullOrEmpty
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
    It 'laesst feste Ordnernamen keinen Container beanspruchen' {
        # Benutzer, die wie feste Ordner heissen, duerfen die UPM-Container eines anderen nicht an sich ziehen
        $s = @([pscustomobject]@{ SessionId = 3; User = 'local' }, [pscustomobject]@{ SessionId = 4; User = 'profiles' },
            [pscustomobject]@{ SessionId = 5; User = 'upm' }, [pscustomobject]@{ SessionId = 6; User = 'Microsoft' }, [pscustomobject]@{ SessionId = 7; User = 'mueller' })
        $paths = @('\\fs01\upm$\mueller.KLINIK\Win2022\UPM_Profile\OutlookOST.vhdx',
            'C:\Users\mueller_UPM_local\UpmTempMount\Profiles\mueller\AppData\Local\Microsoft\Outlook\')
        Resolve-WorkerPerfProfileOwner -Paths $paths -Sessions $s | Should -Be 7
        Resolve-WorkerPerfProfileOwner -Paths @('C:\Users\local_UPM_local\UpmTempMount\') -Sessions $s | Should -Be 3
        Resolve-WorkerPerfProfileOwner -Paths @('\\fs01\upm$\mueller.KLINIK\x.vhdx') -Sessions @($s | Where-Object User -ne 'mueller') | Should -BeNullOrEmpty
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
    It 'erkennt einen seit der Zuordnung eingehaengten UPM-Container am Einhaengepfad' {
        $root = 'C:\Users\neu_UPM_local\UpmTempMount'
        $ost = $root + '\Profiles\neu\AppData\Local\Microsoft\Outlook'
        $v = $Values.Clone()
        $lat = @{ 'C:' = 0.002; $root = 0.03; $ost = 0.02; 'E:' = 0.001; 'C:\Daten\Einhaengepunkt' = 0.001 }
        $v.volumes = @{}
        foreach ($c in 'Avg. Disk sec/Read', 'Avg. Disk sec/Write', 'Disk Reads/sec', 'Disk Writes/sec', 'Disk Read Bytes/sec', 'Disk Write Bytes/sec', 'Current Disk Queue Length') { $v.volumes[$c] = $lat.Clone() }
        $sessions = @([pscustomobject]@{ SessionId = 8; User = 'neu' }, [pscustomobject]@{ SessionId = 9; User = 'andere' })
        $x = ConvertTo-WorkerPerfWinFastSample -Values $v -ElapsedSec 2 -Time $Time -ProfileMap $Map -Sessions $sessions
        foreach ($n in $root, $ost) {
            $vol = $x.Volumes | Where-Object Volume -eq $n
            $vol.Kind | Should -Be 'profile'; $vol.SessionId | Should -Be 8; $vol.Backing | Should -Be ''
        }
        ($x.Volumes | Where-Object Volume -eq 'E:').Kind | Should -Be 'disk'
        ($x.Volumes | Where-Object Volume -eq 'C:\Daten\Einhaengepunkt').Kind | Should -Be 'disk'
        $two = @($sessions + [pscustomobject]@{ SessionId = 11; User = 'NEU' })
        $y = ConvertTo-WorkerPerfWinFastSample -Values $v -ElapsedSec 2 -Time $Time -ProfileMap $Map -Sessions $two
        $vol = $y.Volumes | Where-Object Volume -eq $root
        $vol.Kind | Should -Be 'profile'; $vol.SessionId | Should -BeNullOrEmpty         # zwei Sitzungen: keine Zuordnung
        $z = ConvertTo-WorkerPerfWinFastSample -Values $v -ElapsedSec 2 -Time $Time -ProfileMap $Map
        ($z.Volumes | Where-Object Volume -eq $root).SessionId | Should -BeNullOrEmpty
        ($z.Volumes | Where-Object Volume -eq $root).Kind | Should -Be 'profile'
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
        # Vergleich mit einer Grundlinie auf demselben Rechner: so viele Zeilen nur anlegen; die alte Zuordnung je Zeile
        # brauchte rund das Hundertfache, die jetzige etwa das Dreifache
        $base = [Diagnostics.Stopwatch]::StartNew()
        $plain = foreach ($c in $values.Keys) { foreach ($k in $values[$c].Keys) { [pscustomobject]@{ Source = 'x'; SessionId = 1; Instance = $k; Metric = $c; Value = 1.0 } } }
        $base.Stop()
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $rows = @(ConvertTo-WorkerPerfIcaRows -Values $values -Sessions $sessions)
        $sw.Elapsed.TotalSeconds | Should -BeLessThan (20 * $base.Elapsed.TotalSeconds + 1)
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
    It 'kuerzt Ereignistexte auf die erste Zeile und 300 Zeichen' {
        Get-WorkerPerfEventText "Scan gestartet.`r`n Scan-ID: {1}" | Should -Be 'Scan gestartet.'
        (Get-WorkerPerfEventText ('x' * 400)).Length | Should -Be 300
        Get-WorkerPerfEventText $null | Should -Be ''
    }
    # Aussage geaendert (Fix-Runde 1 von Task 10): der regelmaessige Abruf liest die aeltesten zuerst, damit eine Flut nicht verbirgt, wie sie begann
    It 'behaelt bei mehr als 200 Ereignissen die aeltesten und warnt einmal je Protokoll' {
        . (Join-Path $PSScriptRoot 'WindowsStandIns.ps1'); Reset-WinStandIns
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) 3>$null)
        $script:WinFake.ManyEvents = 250
        $out = @(Get-WorkerPerfEvents -Since ([datetime]::Now.AddHours(-1)) 3>&1)
        $warn = @($out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $ev = @($out | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] -and $_.Log -eq 'defender' })
        $ev.Count | Should -Be 200
        ($ev | Measure-Object -Property Time -Maximum).Maximum | Should -BeLessThan ([datetime]::Now.AddSeconds(-49))   # die aeltesten 200 von 250
        ($ev | Measure-Object -Property Time -Minimum).Minimum | Should -BeLessThan ([datetime]::Now.AddSeconds(-248))
        $warn.Count | Should -Be 1; $warn[0].Message | Should -Match 'Defender'; $warn[0].Message | Should -Match 'neueren'
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
        $script:Cfg = Read-WorkerPerfEventConfig (Join-Path $PSScriptRoot '../src/events.json')
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
    # Aussage ersetzt (Task 10): 'erfuellt die Schnittstelle von Format 3 mit leeren Platzhaltern bis Task 10' - die Platzhalter sind gefuellt
    # Aussage ersetzt: 'bildet Ereigniskennungen auf Arten ab' prueft jetzt die Zuordnung ueber events.json, weil die feste Zuordnung dorthin umzieht
    It 'liefert Ereignisse mit strukturierten Feldern ueber events.json' {
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null)
        $ev = @(Get-WorkerPerfEvents -Since ([datetime]::Now.AddMinutes(-5)))
        @($ev | Where-Object Group -eq 'security').Kind | Should -Be @('scan-start', 'scan-end')
        $c = $ev | Where-Object Kind -eq 'crash'; $c.App | Should -Be 'EXCEL.EXE'; $c.Module | Should -Be 'vbe7.dll'; $c.Pid | Should -Be 7964; $c.Log | Should -Be 'application'
        $c.Code | Should -Be '0xc0000005'; $c.AppVersion | Should -Be '16.0.18129.20158'; $c.Source | Should -Be 'Application Error'; $c.Level | Should -Be 2
        $c.User | Should -Be 'mueller'                                                       # aus der SID im Systemteil, ohne Domaene
        $c.ProcessStart.Kind | Should -Be 'Utc'; [Math]::Abs(($c.ProcessStart - [datetime]::UtcNow.AddHours(-2)).TotalMinutes) | Should -BeLessThan 1
        $c.Text | Should -Be 'Name der fehlerhaften Anwendung: EXCEL.EXE, Version: 16.0.18129.20158'
        # die Profilverwaltung von Citrix nach Ebene: die Warnung, nicht die Information; Quellen ausserhalb des Katalogs nicht
        # Aussage geaendert (P1-R36): die Warnung wird unter einer Art ohne Vorfall aufgezeichnet
        $p = @($ev | Where-Object Source -eq 'Citrix Profile Management'); $p.Count | Should -Be 1; $p[0].EventId | Should -Be 1003; $p[0].Kind | Should -Be 'profile-warning'
        @($ev | Where-Object Source -eq 'Sim Sitzungsdienst').Count | Should -Be 0                # M7: erfundene Quelle ausserhalb des Katalogs
        $svc = $ev | Where-Object Kind -eq 'service'; $svc.Service | Should -Be 'Spooler'; $svc.User | Should -Be 'SYSTEM'
        $pr = $ev | Where-Object Group -eq 'print'; $pr.Driver | Should -Be 'Sim PCL 6'; $pr.Kind | Should -Be 'driver-import'; $pr.User | Should -Be 'NT SERVICE\SimDienst'
        @($ev | ForEach-Object { $_.Time }) | Should -Be @($ev | ForEach-Object { $_.Time } | Sort-Object)
        @($ev | Where-Object Group -eq 'session').Count | Should -Be 0                         # die Anmeldung liegt vor dem Fenster
        @(Get-WorkerPerfEvents -Since ([datetime]::Now.AddMinutes(-15)) | Where-Object Group -eq 'session').User | Should -Be @('mueller')
    }
    It 'fragt je Protokollname einmal ab, mit hoechstens 23 Kennungen je Auswahl' {
        $f = Join-Path $TestDrive 'viele.json'
        $ids = (1..30 | ForEach-Object { 5000 + $_ }) -join ','
        [IO.File]::WriteAllText($f, '{"logs":[{"id":"application","names":["Application"],"lookback":true}],"events":[{"log":"application","provider":"Sim Quelle","ids":[' + $ids + '],"group":"app","kind":"app-detail"}]}')
        Add-WinStandInEvent 'Application' 'Sim Quelle' 5030 2 (-1) 'dreissigste Kennung'
        Add-WinStandInEvent 'Application' 'Sim Quelle' 5001 2 (-1) 'erste Kennung'
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig (Read-WorkerPerfEventConfig $f) 3>$null)
        $script:WinFake.EventQueries = 0
        $out = @(Get-WorkerPerfEvents -Since ([datetime]::Now.AddMinutes(-5)) 3>&1)
        @($out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 0
        @($out.EventId | Sort-Object) | Should -Be @(5001, 5030); $script:WinFake.EventQueries | Should -Be 1
        $sel = @(([xml]$script:WinFake.Queries[$script:WinFake.Queries.Count - 1]).QueryList.Query.Select)
        $sel.Count | Should -Be 2
        @($sel | ForEach-Object { [regex]::Matches($_.InnerText, 'EventID=').Count }) | Should -Be @(23, 7)
    }
    It 'macht je Abruf einen Aufruf je Protokollname (Fix-Runde 1, I1)' {
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null)
        $script:WinFake.EventQueries = 0
        [void](Get-WorkerPerfEvents -Since ([datetime]::Now.AddMinutes(-5)))
        $script:WinFake.EventQueries | Should -Be 8                                   # 7 Protokolle mit Eintraegen (M10: Aussage geaendert), AppLocker mit zwei Namen
        $script:WinFake.EventQueries = 0
        [void](Get-WorkerPerfEventsBefore -Days 7 -Until ([datetime]::Now))
        $script:WinFake.EventQueries | Should -Be 7                                   # ohne Sitzungsprotokoll (M10: Aussage geaendert, ohne das Protokoll ohne Eintraege)
    }
    It 'schreibt Quellennamen mit Hochkomma und Sonderzeichen richtig in die Abfrage' {
        $q = @{ LogName = 'Sim & Log'; Selects = @(@{ Provider = 'Sim "Dienst" <&>'; Ids = [int[]]@(1, 2); Levels = $null }, @{ Provider = 'Sim Ebene'; Ids = $null; Levels = [int[]]@(2, 3) }) }
        $x = [xml](New-WorkerPerfEventQueryXml $q ([datetime]::new(2026, 3, 29, 1, 2, 3, 456, [DateTimeKind]::Utc)) ([datetime]::new(2026, 3, 29, 1, 2, 4, 0, [DateTimeKind]::Utc).AddTicks(1)))
        $x.QueryList.Query.Path | Should -Be 'Sim & Log'
        $sel = @($x.QueryList.Query.Select); $sel[0].Path | Should -Be 'Sim & Log'
        $sel[0].InnerText | Should -BeExactly ("*[System[Provider[@Name='Sim `"Dienst`" <&>'] and (EventID=1 or EventID=2) and TimeCreated[@SystemTime>='2026-03-29T01:02:03.456Z' and @SystemTime<='2026-03-29T01:02:04.001Z']]]")
        $sel[1].InnerText | Should -BeExactly ("*[System[Provider[@Name='Sim Ebene'] and (Level=2 or Level=3) and TimeCreated[@SystemTime>='2026-03-29T01:02:03.456Z' and @SystemTime<='2026-03-29T01:02:04.001Z']]]")
        { ConvertTo-WorkerPerfXPathLiteral "Sim O'Brien" } | Should -Throw                   # nur Literale in ' (Fix-Runde 2, N5)
        # die Nachbildung nimmt, was Windows nimmt: kein Literal in ", keine Query ohne Id, hoechstens 32 Vergleiche je Auswahl
        { ConvertFrom-WinStandInQuery ([xml]'<QueryList><Query Id="0" Path="A"><Select Path="A">*[System[Provider[@Name="X"] and TimeCreated[@SystemTime&gt;=''2026-01-01T00:00:00.000Z'']]]</Select></Query></QueryList>') } | Should -Throw
        { ConvertFrom-WinStandInQuery ([xml]'<QueryList><Query Path="A"><Select Path="A">*[System[Provider[@Name=''X''] and TimeCreated[@SystemTime&gt;=''2026-01-01T00:00:00.000Z'']]]</Select></Query></QueryList>') } | Should -Throw
        $many = @{ LogName = 'A'; Selects = @(@{ Provider = 'X'; Ids = [int[]]@(1..23); Levels = [int[]]@(0, 1, 2, 3, 4, 5, 6) }) }
        { ConvertFrom-WinStandInQuery ([xml](New-WorkerPerfEventQueryXml $many ([datetime]::UtcNow) ([datetime]::UtcNow))) } | Should -Throw '*33 Ausdruecke*'
        $ok = @{ LogName = 'A'; Selects = @(@{ Provider = 'X'; Ids = [int[]]@(1..23); Levels = [int[]]@(0, 1, 2, 3, 4) }) }
        @(ConvertFrom-WinStandInQuery ([xml](New-WorkerPerfEventQueryXml $ok ([datetime]::UtcNow) ([datetime]::UtcNow)))).Count | Should -Be 1
    }
    It 'liest ein Ereignis, das zwei Auswahlen derselben Abfrage nennen, nur einmal (M4)' {
        $f = Join-Path $TestDrive 'doppelt.json'
        [IO.File]::WriteAllText($f, '{"logs":[{"id":"application","names":["Application"],"lookback":true}],"events":[' +
            '{"log":"application","provider":"Sim Profil","ids":[7],"group":"app","kind":"app-detail"},' +
            '{"log":"application","provider":"Sim Profil","ids":"*","levels":["error"],"group":"profile","kind":"profileerror"}]}')
        Add-WinStandInEvent 'Application' 'Sim Profil' 7 2 (-1) 'von beiden Auswahlen genannt'
        Add-WinStandInEvent 'Application' 'Sim Profil' 9 2 (-1) 'nur nach Ebene'
        Add-WinStandInEvent 'Application' 'Sim Profil' 9 4 (-1) 'Information'
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig (Read-WorkerPerfEventConfig $f) 3>$null)
        $ev = @(Get-WorkerPerfEvents -Since ([datetime]::Now.AddMinutes(-5)))
        @($ev | ForEach-Object { '{0}:{1}' -f $_.EventId, $_.Kind } | Sort-Object) | Should -Be @('7:app-detail', '9:profileerror')
        $b = Get-WorkerPerfEventsBefore -Days 1 -Until ([datetime]::Now)
        @($b.Events).Count | Should -Be 2
    }
    It 'meldet ein nicht lesbares Protokoll einmal mit Fehlerklasse und haelt den Rueckblick fuer unvollstaendig (I1, M5)' {
        $script:WinFake.FailLogs = @{ 'System' = 'System.UnauthorizedAccessException' }
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null)
        $b = Get-WorkerPerfEventsBefore -Days 7 -Until ([datetime]::Now) 3>$null
        @($b.Capped) | Should -Be @('system')
        @($b.Events | Where-Object Log -eq 'application').Count | Should -BeGreaterThan 0
        $out = @(foreach ($k in 1..3) { Get-WorkerPerfEvents -Since ([datetime]::Now.AddMinutes(-5)) 3>&1 })
        @($out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 0     # die Konsole bedient der Collector
        @($out | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] -and $_.Log -eq 'defender' }).Count | Should -Be 6
        $f = @(Receive-WorkerPerfSourceErrors)
        @($f | ForEach-Object { $_.Source }) | Should -Be @('eventsbefore', 'events')
        $f[0].Message | Should -BeExactly "Ereignisprotokoll 'System' nicht lesbar (UnauthorizedAccessException): Protokoll System nicht lesbar"
        @(Receive-WorkerPerfSourceErrors).Count | Should -Be 0
        [void](Get-WorkerPerfEvents -Since ([datetime]::Now.AddMinutes(-5))); @(Receive-WorkerPerfSourceErrors).Count | Should -Be 0   # einmal
    }
    It 'nennt jedes Protokoll aus events.json in den Quellen' {
        $info = Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null
        # Aussage geaendert (M10): ein Protokoll ohne Eintraege wird nicht geoeffnet und nicht genannt
        $info.Sources.Contains('events.profileservice') | Should -BeFalse
        foreach ($id in @(@(Get-WorkerPerfEventReadLogs $Cfg) | ForEach-Object { $_.Id })) {
            $info.Sources.Contains("events.$id") | Should -BeTrue -Because $id; $info.Sources["events.$id"].Available | Should -BeTrue -Because $id
        }
        $info.Sources['events.applocker'].Detail | Should -Be 'Microsoft-Windows-AppLocker/EXE and DLL, Microsoft-Windows-AppLocker/MSI and Script'
        $info.Sources['events.application'].Detail | Should -Be 'Application'
    }
    It 'ueberspringt einen einmal nicht lesbaren Datensatz, zaehlt ihn und liest weiter (Fix-Runde 2, N1/N2)' {
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null)
        $crash = @($script:WinFake.Events | Where-Object { $_.ProviderName -eq 'Application Error' })[0]
        $script:WinFake.ReadFailOnce.Add([long]$crash.RecordId)
        $ev = @(Get-WorkerPerfEvents -Since ([datetime]::Now.AddMinutes(-5)))
        @($ev | Where-Object Kind -eq 'crash').Count | Should -Be 0                           # der beschaedigte Datensatz fehlt
        @($ev | Where-Object Source -eq 'Citrix Profile Management').Count | Should -Be 1      # der Rest des Protokolls ist gelesen
        @(Receive-WorkerPerfSourceErrors).Count | Should -Be 0
        $c = Get-WorkerPerfEventCounts
        $c['application'].SkippedRecords | Should -Be 1; $c['application'].UnformattedMessages | Should -Be 0; $c['system'].SkippedRecords | Should -Be 0
        $script:WinFake.OpenReaders | Should -Be 0; $script:WinFake.OpenRecords | Should -Be 0
    }
    It 'beendet nach drei Lesefehlern in Folge das Lesen eines Protokolls, meldet es einmal und liest die anderen (N1)' {
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null)
        $script:WinFake.ReadFailAlways = @('Application')
        $script:WinFake.ReadCalls = 0
        $ev = @(Get-WorkerPerfEvents -Since ([datetime]::Now.AddMinutes(-5)))
        @($ev | Where-Object Log -eq 'application').Count | Should -Be 0
        @($ev | Where-Object Group -eq 'security').Count | Should -Be 2                         # die anderen Protokolle sind gelesen
        $script:WinFake.ReadCalls | Should -BeLessOrEqual 30                                   # 3 im Anwendungsprotokoll, die uebrigen bis zum Ende
        $f = @(Receive-WorkerPerfSourceErrors)
        $f.Count | Should -Be 1; $f[0].Source | Should -Be 'events'
        $f[0].Message | Should -BeExactly "Ereignisprotokoll 'Application' nicht lesbar (InvalidOperationException): Ereignis nicht lesbar"
        (Get-WorkerPerfEventCounts)['application'].SkippedRecords | Should -Be 3
        $b = Get-WorkerPerfEventsBefore -Days 7 -Until ([datetime]::Now)
        @($b.Capped) | Should -Be @('application')
        $script:WinFake.OpenReaders | Should -Be 0; $script:WinFake.OpenRecords | Should -Be 0
    }
    It 'behaelt ein Ereignis mit nicht formatierbarer Meldung mit leerem Text und zaehlt es (N1/N2)' {
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null)
        $crash = @($script:WinFake.Events | Where-Object { $_.ProviderName -eq 'Application Error' })[0]
        $script:WinFake.Unformattable = @([long]$crash.RecordId)
        $c = @(Get-WorkerPerfEvents -Since ([datetime]::Now.AddMinutes(-5)) | Where-Object Kind -eq 'crash')
        $c.Count | Should -Be 1; $c[0].Text | Should -Be ''; $c[0].App | Should -Be 'EXCEL.EXE'
        (Get-WorkerPerfEventCounts)['application'].UnformattedMessages | Should -Be 1
        (Get-WorkerPerfEventCounts)['application'].SkippedRecords | Should -Be 0
    }
    It 'zaehlt die Ereignisse, die die Obergrenze eines Abrufs nicht behaelt (N3)' {
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null)
        $script:WinFake.ManyEvents = 250
        $ev = @(Get-WorkerPerfEvents -Since ([datetime]::Now.AddHours(-1)) 3>$null | Where-Object Log -eq 'defender')
        $ev.Count | Should -Be 200
        (Get-WorkerPerfEventCounts)['defender'].DroppedEvents | Should -Be 50
        [void](Get-WorkerPerfEvents -Since ([datetime]::Now.AddHours(-1)) 3>$null)
        (Get-WorkerPerfEventCounts)['defender'].DroppedEvents | Should -Be 100                 # je Abruf weitergezaehlt
        $script:WinFake.OpenReaders | Should -Be 0; $script:WinFake.OpenRecords | Should -Be 0
    }
    It 'prueft das Zeitbudget des Rueckblicks zwischen den Datensaetzen (N1)' {
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null)
        $script:WinFake.ManyEvents = 2500
        $l = @($script:WinState.Logs | Where-Object Id -eq 'defender')[0]
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $r = Read-WorkerPerfWinLogEvents $l ([datetime]::UtcNow.AddDays(-1)) ([datetime]::UtcNow) 2000 -Clock $clock -BudgetMs ($clock.ElapsedMilliseconds + 150)
        $r.BudgetHit | Should -BeTrue; @($r.Events).Count | Should -BeLessThan 2000
        $script:WinFake.OpenReaders | Should -Be 0; $script:WinFake.OpenRecords | Should -Be 0
    }
    It 'begrenzt jede Leseschleife auch bei einem Leser, der nie endet (N1)' {
        $endless = [pscustomobject]@{ N = 0 }
        $endless | Add-Member -MemberType ScriptMethod -Name ReadEvent -Value {
            $this.N++
            if ($this.N % 3 -eq 0) { $r = [pscustomobject]@{ TimeCreated = [datetime]::Now; RecordId = [long]$this.N }; $r | Add-Member ScriptMethod ToXml { '<x/>' }
                $r | Add-Member ScriptMethod FormatDescription { 'm' }; $r | Add-Member ScriptMethod Dispose { }; return $r }
            throw (New-Object System.InvalidOperationException 'kaputt')
        }
        $r = Read-WorkerPerfEventRecords $endless 10 $null 0 5
        @($r.Records).Count | Should -Be 10; $r.Beyond | Should -Be 5; $r.Skipped | Should -Be 30; $r.Failed | Should -BeFalse
        $endless.N | Should -Be 45                                                                # 3 * (10 + 5) Aufrufe, dann Schluss
    }
    It 'liest den Rueckblick ohne Sitzungsprotokoll und vermerkt die Obergrenze' {
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null)
        $script:WinFake.ManyEvents = 2500
        $b = Get-WorkerPerfEventsBefore -Days 7 -Until ([datetime]::Now)
        $b.Capped | Should -Contain 'defender'; @($b.Events | Where-Object Log -eq 'defender').Count | Should -Be 2000
        @($b.Events | Where-Object Group -eq 'session').Count | Should -Be 0
        @($b.Capped) | Should -Be @('defender')
        @($b.Events | Where-Object Kind -eq 'crash').App | Should -Be @('EXCEL.EXE')
        ($b.Events | Where-Object Log -eq 'defender' | Measure-Object -Property Time -Minimum).Minimum | Should -BeGreaterThan ([datetime]::Now.AddSeconds(-2030))   # die neuesten 2000
    }
    It 'liest den Rueckblick bis zum Ende und nicht weiter als die Tage' {
        Add-WinStandInEvent 'Application' 'Application Hang' 1002 2 (-20000) 'zu alt' -Data @('alt.exe', '1', '10')
        Add-WinStandInEvent 'Application' 'Application Hang' 1002 2 (-60) 'im Rueckblick' -Data @('WINWORD.EXE', '16.0', '1a2c', '01dad0e2a1b2c3d4')
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null)
        $b = Get-WorkerPerfEventsBefore -Days 7 -Until ([datetime]::Now.AddMinutes(-30))
        @($b.Events | Where-Object Kind -eq 'hang').App | Should -Be @('WINWORD.EXE'); @($b.Events | Where-Object Kind -eq 'crash').Count | Should -Be 0
        @($b.Capped).Count | Should -Be 0
        @((Get-WorkerPerfEventsBefore -Days 0 -Until ([datetime]::Now)).Events).Count | Should -Be 0
    }
    It 'begrenzt die Zeit des Rueckblicks und vermerkt die nicht fertig gelesenen Protokolle' {
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null)
        $keep = $script:WorkerPerfWinLookbackBudgetSec
        try {
            $script:WorkerPerfWinLookbackBudgetSec = 0
            $b = Get-WorkerPerfEventsBefore -Days 7 -Until ([datetime]::Now) 3>$null
            @($b.Events).Count | Should -Be 0
            @($b.Capped) | Should -Be @(@(Get-WorkerPerfEventReadLogs $Cfg) | Where-Object { $_.Lookback } | ForEach-Object { $_.Id })
        }
        finally { $script:WorkerPerfWinLookbackBudgetSec = $keep }
    }
    It 'meldet ein fehlendes Protokoll als nicht verfuegbar und liest die anderen' {
        $script:WinFake.Logs = @($script:WinFake.Logs | Where-Object { $_ -ne 'Microsoft-Windows-PrintService/Admin' })
        $info = Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null
        $info.Sources['events.printservice'].Available | Should -BeFalse; $info.Sources['events.application'].Available | Should -BeTrue
        @(Get-WorkerPerfEvents -Since ([datetime]::Now.AddMinutes(-5)) 3>$null).Count | Should -BeGreaterThan 0
    }
    It 'meldet ein abgeschaltetes Protokoll als nicht verfuegbar, ohne bei jedem Abruf zu warnen' {
        $script:WinFake.DisabledLogs = @('Microsoft-Windows-PrintService/Admin', 'Microsoft-Windows-AppLocker/MSI and Script')
        $info = Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null
        $info.Sources['events.printservice'].Available | Should -BeFalse
        $info.Sources['events.printservice'].Detail | Should -Be 'Protokoll nicht vorhanden oder abgeschaltet'
        $info.Sources['events.applocker'].Available | Should -BeTrue; $info.Sources['events.applocker'].Detail | Should -Be 'Microsoft-Windows-AppLocker/EXE and DLL'
        $out = @(foreach ($k in 1..3) { Get-WorkerPerfEvents -Since ([datetime]::Now.AddMinutes(-10)) 3>&1 })
        @($out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 0
        @($out | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] -and $_.Group -eq 'print' }).Count | Should -Be 0
        @((Get-WorkerPerfEventsBefore -Days 7 -Until ([datetime]::Now) 3>&1) | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 0
    }
    It 'loest jede SID einmal auf und fragt nach einer Zeitueberschreitung eine Weile nicht mehr' {
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null)
        $script:WinFake.SidLookups = 0
        Resolve-WorkerPerfEventSid 'S-1-5-21-1000-2000-3000-1108' | Should -Be 'KLINIK\mueller'
        Resolve-WorkerPerfEventSid 'S-1-5-21-1000-2000-3000-1108' | Should -Be 'KLINIK\mueller'
        Resolve-WorkerPerfEventSid 'S-1-5-18' | Should -Be 'SYSTEM'; Resolve-WorkerPerfEventSid 'S-1-5-20' | Should -Be 'NETWORK SERVICE'
        Resolve-WorkerPerfEventSid '' | Should -Be ''
        Resolve-WorkerPerfEventSid 'S-1-5-21-9-9-9-500' | Should -Be ''                       # unbekannt: leer, und gemerkt
        Resolve-WorkerPerfEventSid 'S-1-5-21-9-9-9-500' | Should -Be ''
        $script:WinFake.SidLookups | Should -Be 2                                             # bekannte Dienstkonten ohne Abfrage
        $script:WinFake.SidTimeout = @('S-1-5-21-1000-2000-3000-2001')
        Resolve-WorkerPerfEventSid 'S-1-5-21-1000-2000-3000-2001' | Should -Be ''
        Resolve-WorkerPerfEventSid 'S-1-5-80-1-2-3-4-5' | Should -Be ''                       # Pause nach der Zeitueberschreitung
        $script:WinFake.SidLookups | Should -Be 3
        Resolve-WorkerPerfEventSid 'S-1-5-18' | Should -Be 'SYSTEM'
    }
    It 'liefert Treiberliste und Warteschlangen' {
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null)
        $d = @(Get-WorkerPerfPrintDrivers); $d.Count | Should -Be 2
        ($d | Where-Object Name -eq 'Sim PCL 6').Isolation | Should -Be 'none'; ($d | Where-Object Name -eq 'Sim PCL 6').Type | Should -Be 3
        ($d | Where-Object Name -eq 'Sim PCL 6').Files | Should -Be @('hpsimgr.dll', 'hpsimui.dll')
        ConvertFrom-WorkerPerfDriverVersion (([uint64]61 -shl 48) + ([uint64]1 -shl 32) + 2) | Should -Be '61.1.0.2'   # [uint64] vor dem Schieben: ein Int32 schiebt nur um 48 mod 32
        $q = @(Get-WorkerPerfPrintQueues); $q.Queue | Should -Be @('PRN-TEST-01'); $q[0].JobErrors | Should -Be 4
        $v4 = $d | Where-Object Name -eq 'Sim Klasse v4'
        $v4.Isolation | Should -Be 'shared'; $v4.Type | Should -Be 4; $v4.Version | Should -Be '10.0.0.20348'; $v4.Manufacturer | Should -Be 'Sim'
        $v4.Files | Should -Be @('simklasse.dll', 'simklasse.gpd')
        ($d | Where-Object Name -eq 'Sim PCL 6').Version | Should -Be '61.310.1.25919'
        $q[0].Jobs | Should -Be 1; $q[0].NotReadyErrors | Should -Be 0
    }
    It 'nimmt die Isolationsgruppen vor Richtlinie und Attribut und meldet die Druckquellen' {
        $script:WinFake.IsolationGroups = [string[]]@('Sim Klasse v4', '', 'sim pcl 6')
        $info = Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null
        $info.Sources['print.drivers'].Available | Should -BeTrue; $info.Sources['print.drivers'].Detail | Should -Be 'root/StandardCimv2: MSFT_PrinterDriver'
        $info.Sources['print.queues'].Available | Should -BeTrue; $info.Sources['print.queues'].Detail | Should -Be 'Print Queue / Jobs, Job Errors, Not Ready Errors'
        $d = @(Get-WorkerPerfPrintDrivers)
        ($d | Where-Object Name -eq 'Sim PCL 6').Isolation | Should -Be 'isolated'; ($d | Where-Object Name -eq 'Sim Klasse v4').Isolation | Should -Be 'none'
        $script:WinFake.IsolationGroups = $null; $script:WinFake.IsolationPolicy = @{ PrintDriverIsolationExecutionPolicy = 0 }
        @(Get-WorkerPerfPrintDrivers).Isolation | Should -Be @('none', 'none')
        $script:WinFake.IsolationPolicy = @{}; $script:WinFake.DriverAttributes = @{}
        @(Get-WorkerPerfPrintDrivers).Isolation | Should -Be @('', '')
    }
    It 'meldet fehlende Druckquellen als nicht verfuegbar' {
        $script:WinFake.PrintDriverClass = $false; $script:WinFake.Perf.Remove('Print Queue')
        $info = Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null
        $info.Sources['print.drivers'].Available | Should -BeFalse; $info.Sources['print.drivers'].Detail | Should -Match 'MSFT_PrinterDriver'
        $info.Sources['print.queues'].Available | Should -BeFalse; $info.Sources['print.queues'].Detail | Should -Be 'Print Queue: Kategorie nicht vorhanden'
        @(Get-WorkerPerfPrintQueues).Count | Should -Be 0
    }
    It 'trennt Rueckblick und Messung genau an der Startzeit, auch mit Versatz <Tz> (C1)' -TestCases @(
        @{ Tz = 'UTC' }; @{ Tz = 'Etc/GMT-1' }; @{ Tz = 'Etc/GMT-2' }; @{ Tz = 'Etc/GMT+5' }; @{ Tz = 'Europe/Berlin' }
    ) {
        # Etc/GMT-1 ist UTC+1 h, Etc/GMT-2 UTC+2 h, Etc/GMT+5 UTC-5 h (Vorzeichen nach POSIX umgekehrt)
        $files = @('WorkerPerf.Common.ps1', 'WorkerPerf.EventConfig.ps1', 'WorkerPerf.Sources.Windows.ps1', 'WorkerPerf.Capture.ps1') | ForEach-Object { (Resolve-Path (Join-Path $PSScriptRoot "../src/$_")).Path }
        $standIns = (Resolve-Path (Join-Path $PSScriptRoot 'WindowsStandIns.ps1')).Path
        $body = @'
Reset-WinStandIns
$n = [datetime]::Now; $start = $n.AddTicks(-($n.Ticks % [TimeSpan]::TicksPerSecond)).AddSeconds(-30)
$sys = 'Service Control Manager'
Add-WinStandInEvent 'System' $sys 7031 2 0 'vor' -Data @('a') -Binary 'SimVor' -At $start.AddSeconds(-1)
Add-WinStandInEvent 'System' $sys 7031 2 0 'genau' -Data @('a') -Binary 'SimGenau' -At $start
Add-WinStandInEvent 'System' $sys 7031 2 0 'nach' -Data @('a') -Binary 'SimNach' -At $start.AddSeconds(1)
[void](Initialize-WorkerPerfSource -StartTime $start 3>$null)
$b = @((Get-WorkerPerfEventsBefore -Days 1 -Until $start).Events | Where-Object { $_.Service -like 'Sim*' } | ForEach-Object { $_.Service })
$xb = [xml]@($script:WinFake.Queries | Where-Object { $_ -like '*Path="System"*' })[0]
$script:WinFake.Queries.Clear()
$e = @(Get-WorkerPerfEvents -Since $start | Where-Object { $_.Service -like 'Sim*' } | ForEach-Object { $_.Service })
$xe = [xml]@($script:WinFake.Queries | Where-Object { $_ -like '*Path="System"*' })[0]
$u = $start.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [Globalization.CultureInfo]::InvariantCulture)
$d = $start.ToUniversalTime().AddDays(-1).ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [Globalization.CultureInfo]::InvariantCulture)
$tb = @($xb.QueryList.Query.Select)[0].InnerText; $te = @($xe.QueryList.Query.Select)[0].InnerText
'before=' + ($b -join ',')
'events=' + ($e -join ',')
'lookbackBounds=' + [string]($tb.Contains("@SystemTime>='$d'") -and $tb.Contains("@SystemTime<='$u'"))
'eventsLower=' + [string]$te.Contains("@SystemTime>='$u'")
'offset=' + [string][TimeZoneInfo]::Local.GetUtcOffset($start).TotalHours
'@
        $code = ((($files + $standIns) | ForEach-Object { ". '$_'; " }) -join '') + $body
        $old = $env:TZ
        try { $env:TZ = $Tz; $out = @(& (Get-Process -Id $PID).Path -NoProfile -Command $code) }
        finally { $env:TZ = $old }
        $out | Should -Contain 'before=SimVor,SimGenau'                                       # Rueckblick bis einschliesslich Start
        $out | Should -Contain 'events=SimNach'                                               # Messung nach dem Start, die Startsekunde nur einmal
        $out | Should -Contain 'lookbackBounds=True'; $out | Should -Contain 'eventsLower=True'  # die Grenzen stehen in UTC in der Abfrage
        $want = @{ 'UTC' = '0'; 'Etc/GMT-1' = '1'; 'Etc/GMT-2' = '2'; 'Etc/GMT+5' = '-5' }
        if ($want.ContainsKey($Tz)) { $out | Should -Contain ('offset=' + $want[$Tz]) }
    }
    It 'vergleicht den Zeiger der Ereignisse in UTC (Rechner in Asia/Tokyo)' {
        $files = @('WorkerPerf.Common.ps1', 'WorkerPerf.EventConfig.ps1', 'WorkerPerf.Sources.Windows.ps1', 'WorkerPerf.Capture.ps1') | ForEach-Object { (Resolve-Path (Join-Path $PSScriptRoot "../src/$_")).Path }
        $standIns = (Resolve-Path (Join-Path $PSScriptRoot 'WindowsStandIns.ps1')).Path
        $code = ((($files + $standIns) | ForEach-Object { ". '$_'; " }) -join '') +
            "Reset-WinStandIns; [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) 3>`$null); " +
            "(@(Get-WorkerPerfEvents -Since ([datetime]::UtcNow.AddMinutes(-5)) | Where-Object Group -eq 'security') | ForEach-Object { `$_.Text }) -join '|'"
        $old = $env:TZ
        try { $env:TZ = 'Asia/Tokyo'; $out = & (Get-Process -Id $PID).Path -NoProfile -Command $code }
        finally { $env:TZ = $old }
        $out | Should -Be 'Die Ueberpruefung wurde gestartet.|Die Ueberpruefung wurde beendet.'
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
        $n.Kind | Should -Be 'profile'; $n.SessionId | Should -Be 3                      # am UPM-Einhaengepfad erkannt, noch ohne Neuaufbau
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
    It 'versucht eine gescheiterte Zuordnung erst beim naechsten Stuetzpunkt wieder' {
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) 3>$null)
        [void](Get-WorkerPerfFastSample); [void](Get-WorkerPerfSnapshot -Kind K); [void](Get-WorkerPerfFastSample)
        $script:WinFake.FailStorage = $true
        Add-WinStandInUser -SessionId 3 -User 'neu' -Volume 'C:\Users\neu_UPM_local\UpmTempMount'
        $before = $script:WinFake.DiskQueries
        $out = @(foreach ($k in 1..4) { Get-WorkerPerfFastSample 3>&1; Get-WorkerPerfSnapshot -Kind R 3>&1 })
        $script:WinFake.DiskQueries | Should -Be ($before + 1)                          # ein Versuch, nicht einer je Schnappschuss
        @($out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 1
        Add-WinStandInUser -SessionId 4 -User 'neu2' -Volume 'C:\Users\neu2_UPM_local\UpmTempMount'
        [void](Get-WorkerPerfFastSample 3>$null); [void](Get-WorkerPerfSnapshot -Kind R 3>$null)
        $script:WinFake.DiskQueries | Should -Be ($before + 1)                          # nach einem Fehler nur am Stuetzpunkt
        $script:WinFake.FailStorage = $false
        [void](Get-WorkerPerfSnapshot -Kind K); $s = Get-WorkerPerfFastSample
        $script:WinFake.DiskQueries | Should -Be ($before + 2)
        ($s.Volumes | Where-Object Volume -eq 'C:\Users\neu2_UPM_local\UpmTempMount').SessionId | Should -Be 4
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
        # Aussage geaendert (Task 10): die Quelle ist der Name des Anbieters aus events.json, nicht mehr 'Defender'
        $ev = @(Get-WorkerPerfEvents -Since ([datetime]::Now.AddMinutes(-5)) | Where-Object Group -eq 'security')
        @($ev.Kind) | Should -Be @('scan-start', 'scan-end')
        $ev[0].Source | Should -Be 'Microsoft-Windows-Windows Defender'; $ev[0].Text | Should -Be 'Die Ueberpruefung wurde gestartet.'; $ev[0].Log | Should -Be 'defender'
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
    It 'schreibt Rueckblick, Treiberliste, Warteschlangen und die Quellen der Ereignisse' {
        @(Import-Csv (Join-Path $Run 'printdrivers.csv')).Count | Should -Be 2
        $b = @(Import-Csv (Join-Path $Run 'events_before.csv'))
        @($b | Where-Object Kind -eq 'crash').App | Should -Be @('EXCEL.EXE'); @($b | Where-Object Kind -eq 'crash').User | Should -Be @('mueller')
        @($b | Where-Object Group -eq 'session').Count | Should -Be 0
        @(Import-Csv (Join-Path $Run 'printqueues.csv')).Queue | Select-Object -Unique | Should -Be @('PRN-TEST-01')
        foreach ($id in 'events.application', 'events.system', 'events.printservice', 'events.smbclient', 'events.session', 'events.defender',
            'events.applocker', 'print.drivers', 'print.queues') { $Meta.Sources.$id.Available | Should -BeTrue -Because $id }
        # Aussage geaendert (M10): ein Protokoll ohne Eintraege im Katalog wird nicht geoeffnet und nicht genannt
        $Meta.Sources.PSObject.Properties.Name | Should -Not -Contain 'events.profileservice'
        @($Meta.LookbackCapped).Count | Should -Be 0
    }
}

Describe 'Collector mit einem nicht lesbaren Ereignisprotokoll (Fix-Runde 1, M5)' {
    BeforeAll {
        $dir = Join-Path $TestDrive 'src'; [void](New-Item -ItemType Directory -Path $dir -Force)
        Copy-Item (Join-Path $PSScriptRoot '../src/*') $dir
        [IO.File]::AppendAllText((Join-Path $dir 'WorkerPerf.Common.ps1'), "`nfunction Test-WorkerPerfWindows { return `$true }`n")
        [IO.File]::AppendAllText((Join-Path $dir 'WorkerPerf.Sources.Windows.ps1'),
            "`n" + [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'WindowsStandIns.ps1')) + "`nReset-WinStandIns`n`$script:WinFake.FailLogs = @{ 'System' = 'System.UnauthorizedAccessException' }`n")
        [cultureinfo]::CurrentCulture = [cultureinfo]'de-DE'
        $out = Join-Path $TestDrive 'out'
        $script:Warnings = @()
        $script:Run = (& (Join-Path $dir 'Start-WorkerPerfCapture.ps1') -OutputPath $out -DurationMinutes 0.12 -FastIntervalSeconds 1 -IntervalSeconds 5 3>&1 6>$null) |
            ForEach-Object { if ($_ -is [System.Management.Automation.WarningRecord]) { $script:Warnings += $_.Message } else { $_ } } | Select-Object -Last 1
        $script:Meta = Get-Content (Join-Path $Run 'meta.json') -Raw | ConvertFrom-Json
    }
    It 'vermerkt das Protokoll einmal je Abruf in SourceErrors, warnt einmal und haelt den Rueckblick fuer unvollstaendig' {
        $Meta.SourceErrors.eventsbefore.Count | Should -Be 1
        $Meta.SourceErrors.eventsbefore.FirstMessage | Should -Match "^Ereignisprotokoll 'System' nicht lesbar \(UnauthorizedAccessException\)"
        $Meta.SourceErrors.events.Count | Should -Be 1
        @($Warnings | Where-Object { $_ -like "*Ereignisprotokoll 'System' nicht lesbar*" }).Count | Should -Be 2   # je Quelle einmal
        @($Meta.LookbackCapped) | Should -Be @('system')
        @(Import-Csv (Join-Path $Run 'events_before.csv') | Where-Object Kind -eq 'crash').App | Should -Be @('EXCEL.EXE')
    }
}

Describe 'Collector mit einem Protokoll, dessen Datensaetze sich nie lesen lassen (Fix-Runde 2, N1)' {
    BeforeAll {
        $dir = Join-Path $TestDrive 'src'; [void](New-Item -ItemType Directory -Path $dir -Force)
        Copy-Item (Join-Path $PSScriptRoot '../src/*') $dir
        [IO.File]::AppendAllText((Join-Path $dir 'WorkerPerf.Common.ps1'), "`nfunction Test-WorkerPerfWindows { return `$true }`n")
        [IO.File]::AppendAllText((Join-Path $dir 'WorkerPerf.Sources.Windows.ps1'),
            "`n" + [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'WindowsStandIns.ps1')) + "`nReset-WinStandIns`n`$script:WinFake.ReadFailAlways = @('Application')`n" +
            "`$script:WinFake.Unformattable = @([long]@(`$script:WinFake.Events | Where-Object { `$_.ProviderName -eq 'Service Control Manager' })[0].RecordId)`n")
        [cultureinfo]::CurrentCulture = [cultureinfo]'de-DE'
        $out = Join-Path $TestDrive 'out'
        $script:Run = (& (Join-Path $dir 'Start-WorkerPerfCapture.ps1') -OutputPath $out -DurationMinutes 0.12 -FastIntervalSeconds 1 -IntervalSeconds 5 3>$null 6>$null) |
            Select-Object -Last 1
        $script:Meta = Get-Content (Join-Path $Run 'meta.json') -Raw | ConvertFrom-Json
    }
    It 'laeuft bis zum Ende, meldet das Protokoll und schreibt die Zaehler in meta.json' {
        $Meta.EndReason | Should -Be 'duration'; $Meta.Ticks | Should -BeGreaterOrEqual 5
        $Meta.SourceErrors.eventsbefore.FirstMessage | Should -Match "^Ereignisprotokoll 'Application' nicht lesbar \(InvalidOperationException\)"
        $Meta.SourceErrors.events.Count | Should -Be 1
        @($Meta.LookbackCapped) | Should -Be @('application')
        $Meta.EventReadCounts.application.SkippedRecords | Should -BeGreaterOrEqual 6                # 3 im Rueckblick, 3 je Abruf
        $Meta.EventReadCounts.system.UnformattedMessages | Should -BeGreaterOrEqual 1
        foreach ($p in $Meta.EventReadCounts.PSObject.Properties) {
            foreach ($q in $p.Value.PSObject.Properties) { $q.Value | Should -BeOfType [long] -Because "$($p.Name).$($q.Name)" }
        }
        @(Import-Csv (Join-Path $Run 'events_before.csv') | Where-Object Kind -eq 'service').Text | Should -Be @('')
        @(Import-Csv (Join-Path $Run 'events_before.csv') | Where-Object Group -eq 'security').Count | Should -BeGreaterThan 0
    }
}
