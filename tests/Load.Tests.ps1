BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadHelpers.ps1')
}
Describe 'Import-WorkerPerfRun: Takte' {
    It 'liest Takte und leitet Signale ab' {
        $m = Import-TestRun 'a' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }
        $m.Tick.N | Should -Be 8; $m.Snap.N | Should -Be 4; $m.Meta.Cores | Should -Be 4; $m.Meta.OffsetMinutes | Should -Be 60
        $m.Tick.Signal['mem.used'][0] | Should -Be 75; $m.Tick.Signal['cpu.queue'][0] | Should -Be 2
        [double]::IsNaN($m.Tick.Signal['cpu.steal'][0]) | Should -BeTrue
        $m.Snap.TickPos | Should -Be @(1, 3, 5, 7); $m.Snap.Kind[0] | Should -Be 'K'
    }
    It 'uebergeht eine abgeschnittene letzte Zeile und ein fehlendes Ende' {     # Review Focus 3
        $m = Import-TestRun 'b' @{ 'ticks.csv' = (@($Ticks) + '8,2026-01-15T08:00:18.0000000+01:00,2,5'); 'snapshots.csv' = (@($SnapLines) + '4,9,2026-01-15T08') }
        $m.Tick.N | Should -Be 8; $m.Snap.N | Should -Be 4
        $m.Unreadable.Ticks | Should -Be 1; $m.Unreadable.Snapshots | Should -Be 1     # Abschlussrunde Minor 6: uebersprungene Zeilen werden gezaehlt
        $clean = Import-TestRun 'b0' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }
        $clean.Unreadable.Ticks | Should -Be 0; $clean.Unreadable.Snapshots | Should -Be 0
    }
    It 'kommt ohne optionale Dateien aus' {
        $m = Import-TestRun 'c' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'shares.csv' = $null; 'probes.csv' = $null; 'events.csv' = $null; 'citrix.csv' = $null; 'inputdelay_proc.csv' = $null }
        @($m.Shares).Count | Should -Be 0; @($m.Probes).Count | Should -Be 0; @($m.Events).Count | Should -Be 0
    }
    It 'schneidet auf -From und -To zu' {
        $m = Import-TestRun 'd' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines } @{ From = $Base.AddSeconds(7).DateTime; To = $Base.AddSeconds(13).DateTime }
        $m.Tick.N | Should -Be 3; $m.Snap.N | Should -Be 2
    }
    It 'meldet eine Aufzeichnung ohne Schnappschuss verstaendlich' { { Import-TestRun 'e' @{ 'ticks.csv' = $Ticks } } | Should -Throw '*Schnappschuss*' }
    It 'liest -From und -To als Ortszeit des Servers (Versatz <Offset>)' -TestCases @(@{ Offset = '+02:00' }, @{ Offset = '-07:00' }) {   # Abschlussrunde Minor 3
        $old = $script:Base
        try {
            $script:Base = [DateTimeOffset]"2026-01-15T08:00:00$Offset"                # mindestens einer der beiden weicht vom Versatz dieses Rechners ab
            $files = @{ 'ticks.csv' = @(0..7 | ForEach-Object { New-TickLine $_ }); 'snapshots.csv' = @(0..3 | ForEach-Object { New-SnapLine $_ $(if ($_ -eq 0) { 'K' } else { 'R' }) }) }
            $m = Import-TestRun "tz$($Offset -replace '\W')" $files @{ From = [datetime]'2026-01-15 08:00:07'; To = [datetime]'2026-01-15 08:00:13' }
            $m.Tick.N | Should -Be 3; $m.Snap.N | Should -Be 2
            $m.Tick.TimeMs[0] | Should -Be $Base.AddSeconds(8).ToUnixTimeMilliseconds(); $m.Meta.OffsetMinutes | Should -Be $Base.Offset.TotalMinutes
        }
        finally { $script:Base = $old }
    }
    It 'meldet einen verdrehten und einen leeren Zeitraum mit dem Zeitraum der Aufzeichnung' {      # Abschlussrunde Minor 4
        $files = @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }
        { Import-TestRun 'rev' $files @{ From = $Base.AddSeconds(13).DateTime; To = $Base.AddSeconds(7).DateTime } } | Should -Throw '-From liegt nach -To.'
        { Import-TestRun 'out' $files @{ From = $Base.AddHours(1).DateTime; To = $Base.AddHours(2).DateTime } } |
            Should -Throw 'Der Zeitraum 15.01.2026 09:00:00 bis 15.01.2026 10:00:00 liegt ausserhalb der Aufzeichnung (15.01.2026 08:00:02 bis 15.01.2026 08:00:16, Ortszeit des Servers).'
        { Import-TestRun 'before' $files @{ To = $Base.AddHours(-1).DateTime } } | Should -Throw 'Der Zeitraum bis 15.01.2026 07:00:00 liegt ausserhalb der Aufzeichnung (15.01.2026 08:00:02 bis*'
        { Import-TestRun 'between' $files @{ From = $Base.AddSeconds(4.5).DateTime; To = $Base.AddSeconds(5.5).DateTime } } | Should -Throw 'Im Zeitraum 15.01.2026 08:00:04 bis 15.01.2026 08:00:05 liegt kein Takt der Aufzeichnung (15.01.2026 08:00:02 bis*'
    }
    It 'lehnt eine andere Formatversion ab und duldet eine fehlende' {                  # Abschlussrunde Minor 14
        $dir = Write-TestRun 'ver' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }; $meta = Join-Path $dir 'meta.json'
        $text = [IO.File]::ReadAllText($meta)
        [IO.File]::WriteAllText($meta, $text.Replace('"SchemaVersion":2,', '"SchemaVersion":4,'))       # Format 3 wird gelesen, Format 4 abgelehnt
        { Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles } | Should -Throw '*Format 4*Formate 2 und 3*'
        [IO.File]::WriteAllText($meta, $text.Replace('"SchemaVersion":2,', '"SchemaVersion":3,'))
        (Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles).Tick.N | Should -Be 8
        [IO.File]::WriteAllText($meta, $text.Replace('"SchemaVersion":2,', ''))
        (Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles).Tick.N | Should -Be 8
    }
}
Describe 'Import-WorkerPerfRun: Robustheit' {                                     # Task 14b
    It 'paart Scan-Beginn und -Ende in derselben Millisekunde in der Reihenfolge der Datei' {
        $ev = @("$(Get-Ts 3),Defender,1002,info,a") + @(1..40 | ForEach-Object { "$(Get-Ts 5),Defender,1000,info,x$_" }) +
              @("$(Get-Ts 5),Defender,1000,scan-start,Scan", "$(Get-Ts 5),Defender,1001,scan-end,Scan") + @(1..40 | ForEach-Object { "$(Get-Ts 5),Defender,1000,info,y$_" })
        $m = Import-TestRun 'ev' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'events.csv' = $ev }
        $m.Scans.Count | Should -Be 1; $m.Scans[0].EndMs - $m.Scans[0].StartMs | Should -Be 0
        $m.Events[0].Text | Should -Be 'a'; $m.Events[1].Text | Should -Be 'x1'; $m.Events[$m.Events.Count - 1].Text | Should -Be 'y40'
        $m.Events[41].Kind | Should -Be 'scan-start'; $m.Events[42].Kind | Should -Be 'scan-end'
    }
    It 'ueberspringt einen Takt mit unlesbarer Dauer' {
        . (Join-Path $PSScriptRoot '../src/WorkerPerf.Findings.ps1')
        $t = @(0..7 | ForEach-Object { New-TickLine $_ $(if ($_ -ge 2 -and $_ -le 5) { 95 } else { 50 }) })
        $t[2] = $t[2] -replace '^(2,[^,]+),2,', '$1,abc,'
        $m = Import-TestRun 'nan' @{ 'ticks.csv' = $t; 'snapshots.csv' = $SnapLines }
        $m.Tick.N | Should -Be 7; $m.Tick.TimeMs.Length | Should -Be 7; $m.Tick.ElapsedSec.Length | Should -Be 7
        $m.Unreadable.Ticks | Should -Be 1; $m.Unreadable.Snapshots | Should -Be 0
        @($m.Tick.ElapsedSec | Where-Object { [double]::IsNaN($_) }).Count | Should -Be 0
        $f = @(Get-WorkerPerfFindings -Series @(Get-WorkerPerfSeries -Model $m -Thresholds $Th) -Thresholds $Th)
        @($f | Where-Object SignalId -eq 'cpu.host').Count | Should -Be 1
    }
    It 'ueberspringt einen Schnappschuss mit unlesbarer Dauer' {
        . (Join-Path $PSScriptRoot '../src/WorkerPerf.Findings.ps1')
        $sn = @($SnapLines); $sn[0] = $sn[0] -replace '^(0,1,[^,]+),4,', '$1,abc,'; $sn[2] = $sn[2] -replace '^(2,5,[^,]+),4,', '$1,NaN,'
        $rtt = @(0..3 | ForEach-Object { "$_,Citrix_Euem_RoundTrip,5,,RoundtripTime,400" })
        $m = Import-TestRun 'nansnap' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $sn; 'citrix.csv' = $rtt
            'sessions.csv' = @(0..3 | ForEach-Object { "$_,5,alice,DOM,Active,ICA#5,PC1,,0" }) }
        $m.Snap.N | Should -Be 2; $m.Snap.ElapsedSec | Should -Be @(4, 4); $m.Snap.TickPos | Should -Be @(3, 7)
        $m.Unreadable.Snapshots | Should -Be 2; $m.Unreadable.Ticks | Should -Be 0
        { Get-WorkerPerfFindings -Series @(Get-WorkerPerfSeries -Model $m -Thresholds $Th) -Thresholds $Th } | Should -Not -Throw
    }
}
Describe 'Import-WorkerPerfRun: Sitzungen und Instanzen' {
    BeforeAll {
        $script:Umlaut = "M$([char]0xFC)ller, K"
        $script:M = Import-TestRun 's' @{
            'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines
            'sessions.csv' = @('0,5,alice,DOM,Active,ICA#5,PC1,,0', '1,5,alice,DOM,Active,ICA#5,PC1,,0', "3,5,`"$Umlaut`",DOM,Active,ICA#5,PC2,,0")
            'inputdelay.csv' = @('1,5,300', '7,5,900')
            'volumes.csv' = @('2,C:,disk,,,2.5,12.5,10,20,0,0,0', '2,HarddiskVolume9,profile,5,\\fs01\upm$,40,,30,0,0,0,0')
            'probes.csv' = @('1,DB,Datenbank,h,1521,12.5,', '5,DB,Datenbank,h,1521,,timeout')
            'events.csv' = @("$(Get-Ts 5),Defender,1000,scan-start,Scan", "$(Get-Ts 9),Defender,1001,scan-end,Scan", "$(Get-Ts 11),AppLocker,8004,applocker-block,x.exe")
            'citrix.csv' = @('1,Citrix_Euem_RoundTrip,5,,RoundtripTime,180', '3,Citrix_Euem_RoundTrip,5,,RoundtripTime,220')
        }
    }
    It 'trennt wiederverwendete Sitzungs-IDs und erhaelt Umlaute' {             # Review Focus 2 und 4
        $M.Sessions.Count | Should -Be 2
        $M.Sessions[0].User | Should -Be 'alice'; $M.Sessions[1].User | Should -Be $Umlaut
        $M.Sessions[0].Input[1] | Should -Be 300; $M.Sessions[0].Input[7] | Should -Be 0; $M.Sessions[1].Input[7] | Should -Be 900
    }
    It 'ordnet Laufwerke und Profilcontainer zu' {
        $c = $M.Volumes | Where-Object Name -eq 'C:'; $p = $M.Volumes | Where-Object Name -eq 'HarddiskVolume9'
        $c.Latency[2] | Should -Be 12.5; $c.Ops[2] | Should -Be 30; [double]::IsNaN($c.Latency[3]) | Should -BeTrue
        $p.Kind | Should -Be 'profile'; $p.SessionIndex | Should -Be 0; $p.Latency[2] | Should -Be 40; $p.Backing | Should -Be '\\fs01\upm$'
        $M.Sessions[0].ProfileVolume | Should -BeGreaterOrEqual 0
    }
    It 'liest Proben, Ereignisse und ICA-Werte' {
        $M.Probes[0].Ms[0] | Should -Be 12.5; [double]::IsPositiveInfinity($M.Probes[0].Ms[2]) | Should -BeTrue; [double]::IsNaN($M.Probes[0].Ms[1]) | Should -BeTrue
        $M.Events.Count | Should -Be 3; $M.Scans.Count | Should -Be 1; $M.Scans[0].EndMs - $M.Scans[0].StartMs | Should -Be 4000
        $M.Sessions[0].Rtt[0] | Should -Be 180; $M.Sessions[0].Rtt[1] | Should -Be 220
    }
    It 'wertet eine Probe mit Fehler und Dauer als Fehler' {                      # Abschlussrunde Minor 13
        $m = Import-TestRun 'probefail' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'probes.csv' = @('1,DB,Datenbank,h,1521,12.5,', '5,DB,Datenbank,h,1521,2000,timeout') }
        $m.Probes[0].Ms[0] | Should -Be 12.5; [double]::IsPositiveInfinity($m.Probes[0].Ms[2]) | Should -BeTrue; $m.Probes[0].Error[2] | Should -Be 'timeout'
    }
    It 'liest die Zwischendatei, wenn meta.json beim Ersetzen verloren ging' {      # Abschlussrunde Minor 7
        $dir = Write-TestRun 'metatmp' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }
        Move-Item (Join-Path $dir 'meta.json') (Join-Path $dir 'meta.json.tmp')
        (Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles).Tick.N | Should -Be 8
    }
    It 'liest die Fehler der Datenquelle aus meta.json und duldet ihr Fehlen' {     # Abschlussrunde I6
        $dir = Write-TestRun 'srcerr' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }; $meta = Join-Path $dir 'meta.json'
        (Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles).SourceErrors.Count | Should -Be 0
        $text = [IO.File]::ReadAllText($meta)
        [IO.File]::WriteAllText($meta, $text.Replace('"Simulated":false,', '"Simulated":false,"EndReason":"error","EndMessage":"kaputt","SourceErrors":{"events":{"Count":3,"FirstTime":"' + (Get-Ts 4) + '","FirstMessage":"Zugriff verweigert"},"leer":{}},'))
        $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles
        $m.SourceErrors.Count | Should -Be 1; $m.SourceErrors[0].Source | Should -Be 'events'; $m.SourceErrors[0].Count | Should -Be 3
        $m.SourceErrors[0].FirstMs | Should -Be $Base.AddSeconds(4).ToUnixTimeMilliseconds(); $m.SourceErrors[0].FirstMessage | Should -Be 'Zugriff verweigert'
        $m.Meta.EndReason | Should -Be 'error'; $m.Meta.EndMessage | Should -Be 'kaputt'
    }
    It 'bildet Messreihen fuer die Befund-Logik' {
        $s = @(Get-WorkerPerfSeries -Model $M -Thresholds $Th)
        @($s | Where-Object Id -eq 'cpu.host').Count | Should -Be 1
        @($s | Where-Object Id -eq 'cpu.steal').Count | Should -Be 0                 # ohne bewertbaren Punkt keine Reihe
        $in = @($s | Where-Object Id -eq 'input.session'); $in.Count | Should -Be 2
        $in[0].Resource | Should -Be 'input'; $in[0].Scope | Should -Be 'session'; $in[0].SessionIndex | Should -Be 0
        ($s | Where-Object { $_.Id -eq 'disk.latency' -and $_.Instance -eq 'HarddiskVolume9' }).Resource | Should -Be 'profile'
        ($s | Where-Object { $_.Id -eq 'disk.latency' -and $_.Instance -eq 'C:' }).Scope | Should -Be 'global'
        ($s | Where-Object Id -eq 'probe.connect').TimeMs.Length | Should -Be 2       # nur Messpunkte mit Probe
        ($s | Where-Object Id -eq 'ica.rtt').Resource | Should -Be 'network'
    }
}
Describe 'Import-WorkerPerfRun: Zeitraum und T-Zeilen' {
    BeforeAll {
        $script:Files = @{
            'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines
            'sessions.csv' = @('0,5,alice,DOM,Active,ICA#5,PC1,,0', '1,5,alice,DOM,Active,ICA#5,PC1,,0', '2,5,alice,DOM,Active,ICA#5,PC1,,0', '3,5,alice,DOM,Active,ICA#5,PC1,,0')
            'probes.csv' = @('1,DB,Datenbank,h,1521,100,', '3,DB,Datenbank,h,1521,101,', '5,DB,Datenbank,h,1521,102,', '7,DB,Datenbank,h,1521,103,')
            'citrix.csv' = @('1,Citrix_Euem_RoundTrip,5,,RoundtripTime,100', '3,Citrix_Euem_RoundTrip,5,,RoundtripTime,101', '5,Citrix_Euem_RoundTrip,5,,RoundtripTime,102', '7,Citrix_Euem_RoundTrip,5,,RoundtripTime,103')
        }
    }
    It 'ordnet Zeilen vor -From keinem Schnappschuss im Zeitraum zu' {
        $m = Import-TestRun 'f' $Files @{ From = $Base.AddSeconds(9).DateTime }
        $m.Snap.N | Should -Be 2
        $m.Sessions[0].Rtt[0] | Should -Be 102; $m.Sessions[0].Rtt[1] | Should -Be 103
        $m.Citrix[0].N | Should -Be 2; $m.Citrix[0].Avg | Should -Be 102.5
        $m.Probes[0].Ms[0] | Should -Be 102; $m.Probes[0].Ms[1] | Should -Be 103
    }
    It 'ordnet Zeilen nach -To keinem Schnappschuss zu' {
        $m = Import-TestRun 'g' $Files @{ To = $Base.AddSeconds(9).DateTime }
        $m.Snap.N | Should -Be 2
        $m.Sessions[0].Rtt[1] | Should -Be 101; $m.Citrix[0].N | Should -Be 2; $m.Probes[0].Ms[1] | Should -Be 101
    }
}
Describe 'Import-WorkerPerfRun: Ereignisse und Drucken (Format 3)' {
    It 'liest Ereignisse im Format 2 und 3, den Rueckblick und die Druckdateien' {
        $old = Import-TestRun 'ev2' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'events.csv' = @("$(Get-Ts 5),Defender,1000,scan-start,Scan") }
        $old.Events[0].Group | Should -Be 'security'; $old.Events[0].App | Should -Be ''; $old.Events[0].Pid | Should -Be -1
        @($old.EventsBefore).Count | Should -Be 0; @($old.PrintDrivers).Count | Should -Be 0
        $dir = Write-TestRun 'ev3' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }
        [IO.File]::WriteAllLines((Join-Path $dir 'events.csv'), @($WorkerPerfHeaders['events.csv'], "$(Get-Ts 5),application,Application Error,1000,2,app,crash,EXCEL.EXE,16.0,vbe7.dll,7.1,0xc0000005,812,3,user002,,,,,Absturz"))
        [IO.File]::WriteAllLines((Join-Path $dir 'events_before.csv'), @($WorkerPerfHeaders['events.csv'], "$($Base.AddDays(-2).ToString('o')),application,Application Error,1000,2,app,crash,EXCEL.EXE,,,,,,,user002,,,,,x"))
        [IO.File]::WriteAllLines((Join-Path $dir 'printdrivers.csv'), @($WorkerPerfHeaders['printdrivers.csv'], 'Sim PCL 6,HP,61.1.0.0,3,none,hpsimgr.dll;hpsimui.dll'))
        $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles
        $m.Events[0].Module | Should -Be 'vbe7.dll'; $m.Events[0].SessionId | Should -Be 3; @($m.EventsBefore).Count | Should -Be 1
        $m.PrintDrivers[0].Type | Should -Be 3; $m.PrintDrivers[0].Files | Should -Be @('hpsimgr.dll', 'hpsimui.dll')
    }
    It 'fuellt jedes Feld von Format 3 und haelt alte Felder' {
        $m = Import-TestRun 'ev2b' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'events.csv' = @("$(Get-Ts 7),AppLocker,8004,applocker-block,""x, y.exe""", "$(Get-Ts 6),Defender,1000,info,i") }
        $e = $m.Events
        $e[0].Text | Should -Be 'i'; $e[0].Group | Should -Be ''; $e[1].Group | Should -Be 'security'; $e[1].Text | Should -Be 'x, y.exe'
        $e[1].Source | Should -Be 'AppLocker'; $e[1].EventId | Should -Be 8004; $e[1].Level | Should -Be -1; $e[1].SessionId | Should -Be -1; $e[1].Log | Should -Be ''
        foreach ($k in 'TimeMs', 'Timestamp', 'Log', 'Source', 'EventId', 'Level', 'Group', 'Kind', 'App', 'AppVersion', 'Module', 'ModuleVersion', 'Code', 'Pid', 'SessionId', 'User', 'Printer', 'Driver', 'Service', 'Object', 'Text') {
            $e[1].ContainsKey($k) | Should -BeTrue -Because $k
        }
        $e[1].Pid | Should -BeOfType [int]; $e[1].TimeMs | Should -Be $Base.AddSeconds(7).ToUnixTimeMilliseconds()
    }
    It 'liest Warteschlangen im Zeitraum und Treiber ohne Bauart' {
        $q = @("$(Get-Ts 3),Drucker 1,0,4,1", "$(Get-Ts 9),Drucker 1,2,5,1", "$(Get-Ts 30),Drucker 1,0,5,1", 'kaputt')
        $m = Import-TestRun 'pq' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'printqueues.csv' = $q; 'printdrivers.csv' = @('Typ 4 Treiber,,,,,') } @{ From = $Base.AddSeconds(5).DateTime; To = $Base.AddSeconds(20).DateTime }
        # Aussage geaendert (M6): dazu die letzte Zeile vor dem Zeitraum, die Werte, die bei seinem Beginn galten
        @($m.PrintQueues).Count | Should -Be 2; $m.PrintQueues[0].Queue | Should -Be 'Drucker 1'; $m.PrintQueues[0].Jobs | Should -Be 2; $m.PrintQueues[0].JobErrors | Should -Be 5
        $m.PrintQueues[0].TimeMs | Should -Be $Base.AddSeconds(9).ToUnixTimeMilliseconds()
        $m.PrintQueues[1].TimeMs | Should -Be $Base.AddSeconds(3).ToUnixTimeMilliseconds(); $m.PrintQueues[1].JobErrors | Should -Be 4
        $m.PrintDrivers[0].Type | Should -Be 0; @($m.PrintDrivers[0].Files).Count | Should -Be 0; $m.PrintDrivers[0].Isolation | Should -Be ''
    }
    It 'liest Rueckblick und Vermerk aus meta.json und duldet ihr Fehlen' {
        $dir = Write-TestRun 'lbm' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }; $meta = Join-Path $dir 'meta.json'
        $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles
        $m.Meta['EventLookbackDays'] | Should -BeNullOrEmpty; @($m.Meta['LookbackCapped']).Count | Should -Be 0
        $text = [IO.File]::ReadAllText($meta)
        [IO.File]::WriteAllText($meta, $text.Replace('"Simulated":false,', '"Simulated":false,"EventLookbackDays":7,"LookbackCapped":["system","application"],'))
        $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles
        $m.Meta['EventLookbackDays'] | Should -Be 7; $m.Meta['LookbackCapped'] | Should -Be @('system', 'application')
    }
    It 'liest die weggelassenen Kategorien; ohne Angabe gilt alles als gemessen' {   # Review Focus 2
        $dir = Write-TestRun 'skip' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }; $meta = Join-Path $dir 'meta.json'
        @((Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles).Skip).Count | Should -Be 0
        [IO.File]::WriteAllText($meta, [IO.File]::ReadAllText($meta).Replace('"Simulated":false,', '"Simulated":false,"Skip":["rueckblick","Netz","Zustand","Prozesse"],'))
        (Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles).Skip | Should -Be @('Prozesse', 'Rueckblick', 'Zustand')   # Aussage angepasst (Zustandsbild, Task 8): Zustand ist aktiv
        # ein beschaedigtes Feld bricht nichts: kein Text, kein Wert, ein einzelner Text, eine Zahl
        @(Get-WorkerPerfRecordedSkip $null).Count | Should -Be 0; Get-WorkerPerfRecordedSkip @($null, 5, '', 'Zustand') | Should -Be @('Zustand')
        Get-WorkerPerfRecordedSkip 'CITRIX' | Should -Be @('Citrix'); @(Get-WorkerPerfRecordedSkip ([pscustomobject]@{ a = 'Citrix' })).Count | Should -Be 0
    }
}
Describe 'Import-WorkerPerfRun: unlesbare Zeilen der Ereignis- und Druckdateien (Fix-Runde 1)' {
    It 'zaehlt Zeilen, die kuerzer als ihre eigene Kopfzeile sind' {                       # Minor 9
        $dir = Write-TestRun 'skip' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'printqueues.csv' = @("$(Get-Ts 3),Drucker 1,0,4,1", 'kaputt') }
        $row = "$(Get-Ts 5),application,Application Error,1000,2,app,crash,EXCEL.EXE,,,,,,,user002,,,,,x"
        [IO.File]::WriteAllLines((Join-Path $dir 'events.csv'), @(($WorkerPerfHeaders['events.csv'] + ',Extra'), $row, $row))
        [IO.File]::WriteAllLines((Join-Path $dir 'events_before.csv'), @($WorkerPerfHeaders['events.csv'], $row, 'zu,kurz'))
        [IO.File]::WriteAllLines((Join-Path $dir 'printdrivers.csv'), @($WorkerPerfHeaders['printdrivers.csv'], 'a,b'))
        $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles
        @($m.Events).Count | Should -Be 0; @($m.EventsBefore).Count | Should -Be 1
        $m.Unreadable.Events | Should -Be 2; $m.Unreadable.EventsBefore | Should -Be 1; $m.Unreadable.PrintDrivers | Should -Be 1; $m.Unreadable.PrintQueues | Should -Be 1
        $ok = Import-TestRun 'skip0' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'events.csv' = @("$(Get-Ts 5),Defender,1000,scan-start,Scan") }
        $ok.Unreadable.Events | Should -Be 0; $ok.Unreadable.EventsBefore | Should -Be 0; $ok.Unreadable.PrintQueues | Should -Be 0
    }
}
Describe 'Import-WorkerPerfRun: Zustandsbild' {
    BeforeAll {
        # Ein Schnelllauf im Ordner <Name>: meta.json, Rueckblick, Treiberliste und, wenn angegeben, health.json
        function Write-QuickRun([string]$Name, [string]$HealthText, [string]$MetaExtra = '') {
            $dir = Join-Path $TestDrive $Name; [void](New-Item -ItemType Directory $dir -Force)
            [IO.File]::WriteAllText((Join-Path $dir 'meta.json'), '{"SchemaVersion":3,"Computer":"T1","OS":"x","LogicalProcessors":4,"PhysicalMemoryMB":16384,"FastIntervalSeconds":2,"IntervalSeconds":15,' +
                '"StartTime":"2026-01-15T08:00:00.0000000+02:00","EndTime":"2026-01-15T08:00:05.0000000+02:00","EndReason":"healthonly","Ticks":0,"Snapshots":0,"Simulated":false,"HealthOnly":true,' +
                '"EventLookbackDays":7,"Skip":[],' + $MetaExtra + '"Sources":{"print.drivers":{"Available":true,"Detail":""},"health":{"Available":true,"Detail":""}}}')
            [IO.File]::WriteAllLines((Join-Path $dir 'events_before.csv'), [string[]]@($WorkerPerfHeaders['events_before.csv']))
            [IO.File]::WriteAllLines((Join-Path $dir 'printdrivers.csv'), [string[]]@($WorkerPerfHeaders['printdrivers.csv']))
            if ($HealthText) { [IO.File]::WriteAllText((Join-Path $dir 'health.json'), $HealthText) }
            $dir
        }
        # $true, wenn irgendwo im Wert ein pscustomobject steckt
        function Test-HasPsObject($Value) {
            if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) { return $false }
            if ($Value -is [System.Management.Automation.PSCustomObject]) { return $true }
            if ($Value -is [System.Collections.IDictionary]) { foreach ($k in @($Value.Keys)) { if (Test-HasPsObject $Value[$k]) { return $true } }; return $false }
            foreach ($item in $Value) { if (Test-HasPsObject $item) { return $true } }
            return $false
        }
    }
    It 'liest health.json in das Modell' {
        $dir = Write-TestRun 'h1' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }
        [IO.File]::WriteAllText((Join-Path $dir 'health.json'), '{"FormatVersion":1,"ReadAt":"2026-01-15T07:59:50.0000000+02:00","DurationMs":1200,"Areas":{"operation":{"Status":"partial","DurationMs":300,"Error":"","Values":{' +
            '"operation.pendingRename":{"State":"read","Reason":"","Value":2},"operation.lastBoot":{"State":"unreadable","Reason":"rights","Value":null},"operation.unbekannt":{"State":"read","Reason":"","Value":1},' +
            '"operation.pendingUpdate":{"State":"gelesen","Reason":"","Value":true},' +
            '"print.spooler":{"State":"read","Reason":"","Value":"Running"},' +
            '"operation.volumes":{"State":"read","Reason":"","Value":[{"Drive":"C:","SizeGB":100,"FreeGB":8.5,"FileSystem":"NTFS","System":true,"PageFile":true}]}}}}}')
        $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles
        $m.HealthState | Should -Be 'read'; $m.Health.DurationMs | Should -Be 1200; $m.Health.OffsetMinutes | Should -Be 120
        $m.Health.ReadAtMs | Should -Be ([DateTimeOffset]'2026-01-15T07:59:50+02:00').ToUnixTimeMilliseconds()
        $o = $m.Health.Areas['operation']; $o.Status | Should -Be 'partial'; $o.DurationMs | Should -Be 300; $o.Values['operation.pendingRename'].Value | Should -Be 2
        $o.Values['operation.lastBoot'].Reason | Should -Be 'rights'; $o.Values.Contains('operation.unbekannt') | Should -BeFalse; $o.Values['operation.powerPlan'].State | Should -Be 'unreadable'
        $o.Values['operation.pendingUpdate'].State | Should -Be 'unreadable'; $o.Values['operation.pendingUpdate'].Reason | Should -Be 'error'      # ein Zustand, den das Format nicht kennt
        $o.Values.Contains('print.spooler') | Should -BeFalse; $m.Health.Areas['print'].Values['print.spooler'].State | Should -Be 'unreadable'      # eine Kennung unter dem falschen Bereich wird uebergangen, die Datei bleibt lesbar
        $vol = @($o.Values['operation.volumes'].Value); $vol[0] | Should -BeOfType [System.Collections.IDictionary]; $vol[0]['FreeGB'] | Should -Be 8.5; $vol[0]['System'] | Should -BeTrue
        @($m.Health.Areas.Keys) | Should -Be $WorkerPerfHealthAreas; $m.Health.Areas['size'].Status | Should -Be 'failed'; $m.Health.Areas['size'].Error | Should -Be 'notInFile'
        $m.Meta.HealthOnly | Should -BeFalse; $m.Recorded.EventsBefore | Should -BeFalse; $m.Recorded.PrintDrivers | Should -BeFalse     # Format 2: beide Dateien gibt es nicht
    }
    It 'unterscheidet nicht erfasst, weggelassen und nicht lesbar' {   # Review Focus 2
        $dir = Write-TestRun 'h2' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }; $meta = Join-Path $dir 'meta.json'; $file = Join-Path $dir 'health.json'
        $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles
        $m.HealthState | Should -Be 'notRecorded'; $m.Health | Should -BeNullOrEmpty; @($m.Skip) | Should -Not -Contain 'Zustand'
        [IO.File]::WriteAllText($file, '{"FormatVersion":2,"Areas":{}}')
        $w = @(Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $w.Count | Should -Be 1; $w[0].Message | Should -Match 'health\.json'; $w[0].Message | Should -Match 'Format 2'
        (Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles 3>$null).HealthState | Should -Be 'unreadable'
        [IO.File]::WriteAllText($file, '{ kein json'); (Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles 3>$null).HealthState | Should -Be 'unreadable'
        # Skip gewinnt gegen die Datei: eine lesbare Datei wird nicht gelesen
        [IO.File]::WriteAllText($file, '{"FormatVersion":1,"ReadAt":"2026-01-15T07:59:50.0000000+01:00","DurationMs":1,"Areas":{}}')
        [IO.File]::WriteAllText($meta, [IO.File]::ReadAllText($meta).Replace('"Simulated":false,', '"Simulated":false,"Skip":["Zustand"],'))
        $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles
        $m.HealthState | Should -Be 'skipped'; $m.Health | Should -BeNullOrEmpty; $m.Sources['health'].Detail | Should -Be 'abgeschaltet (-Skip Zustand)'
    }
    It 'liest einen Schnelllauf ohne Takte und Schnappschuesse' {   # Review Focus 5
        $dir = Join-Path $TestDrive 'ho'; [void](New-Item -ItemType Directory $dir); $meta = Join-Path $dir 'meta.json'
        [IO.File]::WriteAllText($meta, '{"SchemaVersion":3,"Computer":"T1","OS":"x","LogicalProcessors":4,"PhysicalMemoryMB":16384,"FastIntervalSeconds":2,"IntervalSeconds":15,' +
            '"StartTime":"2026-01-15T08:00:00.0000000+02:00","EndTime":"2026-01-15T08:00:05.0000000+02:00","EndReason":"healthonly","Ticks":0,"Snapshots":0,"Simulated":false,"HealthOnly":true,"EventLookbackDays":7,"Skip":[],"Sources":{}}')
        [IO.File]::WriteAllLines((Join-Path $dir 'events_before.csv'), [string[]]@($WorkerPerfHeaders['events_before.csv'], ('2026-01-14T09:00:00.0000000+02:00,application,Application Error,1000,2,app,crash,EXCEL.EXE' + (',' * 12) + 'x')))
        [IO.File]::WriteAllLines((Join-Path $dir 'printdrivers.csv'), [string[]]@($WorkerPerfHeaders['printdrivers.csv'], 'Sim PCL 6,HP,1.0,3,none,a.dll'))
        [IO.File]::WriteAllText((Join-Path $dir 'health.json'), '{"FormatVersion":1,"ReadAt":"2026-01-15T08:00:01.0000000+02:00","DurationMs":900,"Areas":{}}')
        $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles
        $m.Meta.HealthOnly | Should -BeTrue; $m.Tick.N | Should -Be 0; $m.Snap.N | Should -Be 0; $m.Meta.OffsetMinutes | Should -Be 120; $m.HealthState | Should -Be 'read'
        $m.CaptureStartMs | Should -Be ([DateTimeOffset]'2026-01-15T08:00:00+02:00').ToUnixTimeMilliseconds()
        @($m.EventsBefore).Count | Should -Be 1; @($m.PrintDrivers).Count | Should -Be 1; @($m.Events).Count | Should -Be 0; @($m.Sessions).Count | Should -Be 0; $m.Rows.K.Length | Should -Be 0
        $m.Recorded.EventsBefore | Should -BeTrue; $m.Recorded.PrintDrivers | Should -BeTrue; @($m.EventsAll).Count | Should -Be 0
        { Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles -From ([datetime]'2026-01-15T08:00:00') } | Should -Throw '*Schnelllauf*-From*'
        # ohne das Feld bleibt eine Aufzeichnung ohne Takte ein Fehler
        [IO.File]::WriteAllText($meta, [IO.File]::ReadAllText($meta).Replace('"HealthOnly":true,', ''))
        { Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles } | Should -Throw '*keine Messung*'
    }
    It 'haelt die Ereignisse der ganzen Messung neben dem Ausschnitt' {
        $ev = @("$(Get-Ts 3),Sim,1,crash,a", "$(Get-Ts 13),Sim,1,crash,b")
        $m = Import-TestRun 'hcut' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'events.csv' = $ev } @{ From = $Base.AddSeconds(9).DateTime }
        @($m.Events).Count | Should -Be 1; @($m.EventsAll).Count | Should -Be 2; $m.EventsOutsideCut | Should -Be 1
        # Fix-Runde 1, Punkt 6: nach Zeit geordnet, auch wenn die Datei sie anders ordnet
        $ev = @("$(Get-Ts 15),Sim,1,crash,c", "$(Get-Ts 3),Sim,1,crash,a", "$(Get-Ts 13),Sim,1,crash,b")
        $m = Import-TestRun 'hsort' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'events.csv' = $ev } @{ From = $Base.AddSeconds(9).DateTime }
        $times = @($m.EventsAll | ForEach-Object { $_.TimeMs })
        $times.Count | Should -Be 3; $times | Should -Be @($times | Sort-Object); $times[0] | Should -Be $Base.AddSeconds(3).ToUnixTimeMilliseconds()
    }
    It 'verwirft einen Wert, der nicht zu seinem Typ passt, und behaelt den Rest der Datei' {   # ZB-R27
        $values = @{
            size = '"size.cpuLogical":{"State":"read","Reason":"","Value":4},"size.memTotalMB":{"State":"read","Reason":"","Value":16384.5},' +
                '"size.cpuSockets":2,' +                                                                               # kein Objekt
                '"size.commitTotalMB":{"State":"read","Reason":"","Value":"viel"},' +                                  # number als Text
                '"size.hypervisor":{"State":"read","Reason":"","Value":1},' +                                          # bool als Zahl
                '"size.pageFileManaged":{"State":"read","Reason":"","Value":true},' +                                  # falsche Schreibweise der Kennung
                '"size.model":{"State":"read","Reason":"","Value":"2026-11-13T10:00:00"},' +                           # Text, der wie eine Zeit aussieht
                '"size.balloonDriver":{"State":"read","Reason":"","Value":"\/Date(1234)\/"},' +
                '"size.vmtoolsService":{"State":"read","Reason":"","Value":5},' +                                      # text als Zahl
                '"size.pagefiles":{"State":"read","Reason":"","Value":"C:\\pagefile.sys"},' +                          # list als Text
                '"size.netAdapters":{"State":"read","Reason":"","Value":[1,2]},' +                                     # Eintraege keine Datensaetze
                '"size.storageControllers":{"State":"read","Reason":"","Value":null},' +                               # list ohne Inhalt
                '"size.vmtoolsPresent":{"State":"absent","Reason":"notInstalled","Value":null}'
            operation = '"operation.lastBoot":{"State":"read","Reason":"","Value":1.5},"operation.lastUpdate":{"State":"read","Reason":"","Value":1768460390000},' +
                '"operation.pendingRename":{"State":"read","Reason":"vielleicht","Value":1},' +                         # unbekannter Grund
                '"operation.volumes":{"State":"read","Reason":"","Value":{"Drive":"C:","SizeGB":100,"FreeGB":8.5,"FileSystem":"NTFS","System":true,"PageFile":true}}'   # ein Datensatz statt einer Liste
            apps = '"apps.probes":{"State":"read","Reason":"","Value":[{"App":"simapp","Id":"stand","Kind":"registryValue","Read":"value","State":"read","Reason":"","Value":"2026-11-13T10:00:00","Names":""}]}'
        }
        $areas = (@($values.Keys) | ForEach-Object { '"{0}":{{"Status":"read","DurationMs":5,"Error":"","Values":{{{1}}}}}' -f $_, $values[$_] }) -join ','
        $dir = Write-QuickRun 'hr27' ('{"FormatVersion":1,"ReadAt":"2026-01-15T08:00:01.0000000-07:00","DurationMs":900,"Areas":{' + $areas + ',"unbekannt":{"Values":{}},"vda":17}}')
        $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles
        $m.HealthState | Should -Be 'read'; $m.Health.OffsetMinutes | Should -Be -420; $m.Health.FormatVersion | Should -Be 1
        $s = $m.Health.Areas['size'].Values
        $s['size.cpuLogical'].Value | Should -Be 4; $s['size.memTotalMB'].Value | Should -Be 16384.5; $s['size.vmtoolsPresent'].State | Should -Be 'absent'
        foreach ($id in 'size.cpuSockets', 'size.commitTotalMB', 'size.hypervisor', 'size.pagefileManaged', 'size.vmtoolsService', 'size.pagefiles', 'size.netAdapters', 'size.storageControllers') {
            $s[$id].State | Should -Be 'unreadable' -Because $id; $s[$id].Reason | Should -Be 'error' -Because $id; $s[$id].Value | Should -BeNullOrEmpty -Because $id
        }
        (@($s.Keys) -ccontains 'size.pageFileManaged') | Should -BeFalse
        # ein Text, der wie eine Zeit aussieht, kommt unter beiden Shells als derselbe Text an
        $s['size.model'].Value | Should -BeOfType [string]; $s['size.model'].Value | Should -BeExactly '2026-11-13T10:00:00'; $s['size.balloonDriver'].Value | Should -BeExactly '/Date(1234)/'
        $o = $m.Health.Areas['operation'].Values
        $o['operation.lastBoot'].State | Should -Be 'unreadable'; $o['operation.lastBoot'].Reason | Should -Be 'error'; $o['operation.lastUpdate'].Value | Should -Be 1768460390000
        $o['operation.pendingRename'].State | Should -Be 'unreadable'; $o['operation.pendingRename'].Reason | Should -Be 'error'
        , $o['operation.volumes'].Value | Should -BeOfType [object[]]; $o['operation.volumes'].Value.Count | Should -Be 1; $o['operation.volumes'].Value[0]['Drive'] | Should -Be 'C:'
        $rows = $m.Health.Areas['apps'].Values['apps.probes'].Value
        , $rows | Should -BeOfType [object[]]; $rows.Count | Should -Be 1; $rows[0] | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
        $rows[0]['Value'] | Should -BeOfType [string]; $rows[0]['Value'] | Should -BeExactly '2026-11-13T10:00:00'
        $m.Health.Areas['vda'].Status | Should -Be 'failed'; $m.Health.Areas['vda'].Error | Should -Be 'notInFile'   # ein Bereich, der kein Objekt ist
        $m.Health.Areas['size'].Status | Should -Be 'partial'; $m.Health.Areas['size'].DurationMs | Should -Be 5
        Test-HasPsObject $m.Health | Should -BeFalse
    }
    It 'nimmt die Zeit eines Felds der obersten Ebene mit ihrem Versatz aus dem Text' {
        $text = '{"Areas":{"x":{"ReadAt":"2020-01-01T00:00:00+00:00"}},"Text":"\"ReadAt\":\"2021-01-01T00:00:00+00:00\"", "ReadAt" : "2026-01-15T08:00:01.0000000-07:00"}'
        $t = Get-WorkerPerfJsonTimeText $text 'ReadAt'
        $t | Should -BeOfType [DateTimeOffset]; $t.Offset.TotalMinutes | Should -Be -420; $t.ToUnixTimeMilliseconds() | Should -Be ([DateTimeOffset]'2026-01-15T15:00:01Z').ToUnixTimeMilliseconds()
        Get-WorkerPerfJsonTimeText $text 'StartTime' | Should -BeNullOrEmpty
        Get-WorkerPerfJsonTimeText '{"ReadAt":"keine Zeit"}' 'ReadAt' | Should -BeNullOrEmpty
        foreach ($case in @(@('[1,2]', 'kein gueltiges JSON'), @('{"FormatVersion":1}', 'Areas fehlt'), @('{"FormatVersion":1,"Areas":[]}', 'Areas fehlt'), @('{"FormatVersion":"1","Areas":{}}', 'Format 1 unbekannt'),
                # Fix-Runde 1, Punkt 3: oberste Ebene kein Objekt, unter beiden Shells (PowerShell 7 wickelt ein Array mit einem Element aus)
                @('[{"FormatVersion":1,"ReadAt":"2026-01-15T08:00:01.0000000+02:00","DurationMs":900,"Areas":{}}]', 'kein gueltiges JSON'), @(' "{\"FormatVersion\":1}"', 'kein gueltiges JSON'), @('5', 'kein gueltiges JSON'),
                # Fix-Runde 1, Punkt 5: ohne lesbare Lesezeit kein Zustandsbild
                @('{"FormatVersion":1,"Areas":{}}', 'ReadAt fehlt'), @('{"FormatVersion":1,"ReadAt":"keine Zeit","Areas":{}}', 'ReadAt fehlt'), @('{"FormatVersion":1,"ReadAt":null,"Areas":{}}', 'ReadAt fehlt'))) {
            $f = Read-WorkerPerfHealthFile (Join-Path (Write-QuickRun 'hbad' $case[0]) 'health.json')
            $f.State | Should -Be 'unreadable' -Because $case[0]; $f.Message | Should -Be $case[1] -Because $case[0]
        }
    }
    It 'verwirft eine Zeit <Text>, ohne die Datei aufzugeben' -TestCases @(@{ Text = '1e30' }, @{ Text = '-1e30' }, @{ Text = '1.5' }, @{ Text = '"gestern"' }) {   # Fix-Runde 1, Punkt 1 (ZB-R27)
        $dir = Write-QuickRun ('htime' + [Math]::Abs($Text.GetHashCode())) ('{"FormatVersion":1,"ReadAt":"2026-01-15T08:00:01.0000000+02:00","DurationMs":900,"Areas":{"operation":{"Status":"read","DurationMs":5,"Error":"","Values":{' +
            '"operation.lastBoot":{"State":"read","Reason":"","Value":' + $Text + '},"operation.lastUpdate":{"State":"read","Reason":"","Value":1768460390000}}}}}')
        $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles
        $m.HealthState | Should -Be 'read'
        $o = $m.Health.Areas['operation'].Values
        $o['operation.lastBoot'].State | Should -Be 'unreadable'; $o['operation.lastBoot'].Reason | Should -Be 'error'; $o['operation.lastBoot'].Value | Should -BeNullOrEmpty
        $o['operation.lastUpdate'].State | Should -Be 'read'; $o['operation.lastUpdate'].Value | Should -Be 1768460390000
    }
    It 'liest jede Zahl unter beiden Shells als [long] oder [double]' {   # Fix-Runde 1, Punkt 2
        $dir = Write-QuickRun 'hnum' ('{"FormatVersion":1,"ReadAt":"2026-01-15T08:00:01.0000000+02:00","DurationMs":900,"Areas":{"size":{"Status":"read","DurationMs":5,"Error":"","Values":{' +
            '"size.cpuLogical":{"State":"read","Reason":"","Value":4},"size.cpuSockets":{"State":"read","Reason":"","Value":2.0},"size.memTotalMB":{"State":"read","Reason":"","Value":16384.5},' +
            '"size.commitTotalMB":{"State":"read","Reason":"","Value":1e30},"size.commitLimitMB":{"State":"read","Reason":"","Value":99999999999999999999},' +
            '"size.commitPeakMB":{"State":"read","Reason":"","Value":-9223372036854775808}}},' +
            '"operation":{"Status":"read","DurationMs":5,"Error":"","Values":{"operation.lastBoot":{"State":"read","Reason":"","Value":1768460390000},' +
            '"operation.volumes":{"State":"read","Reason":"","Value":[{"Drive":"C:","SizeGB":100,"FreeGB":8.5,"UsedGB":1e30,"Files":99999999999999999999,"FileSystem":"NTFS","System":true,"PageFile":false}]}}}}}')
        $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles
        $s = $m.Health.Areas['size'].Values
        $s['size.cpuLogical'].Value -is [long] | Should -BeTrue; $s['size.cpuLogical'].Value | Should -Be 4
        $s['size.cpuSockets'].Value -is [long] | Should -BeTrue; $s['size.cpuSockets'].Value | Should -Be 2         # ganzzahlig, auch mit ".0"
        $s['size.memTotalMB'].Value -is [double] | Should -BeTrue; $s['size.memTotalMB'].Value | Should -Be 16384.5
        $s['size.commitPeakMB'].Value -is [long] | Should -BeTrue; $s['size.commitPeakMB'].Value | Should -Be ([long]::MinValue)
        foreach ($id in 'size.commitTotalMB', 'size.commitLimitMB') {   # ganzzahlig ausserhalb von [long]
            $s[$id].State | Should -Be 'unreadable' -Because $id; $s[$id].Reason | Should -Be 'error' -Because $id; $s[$id].Value | Should -BeNullOrEmpty -Because $id
        }
        $o = $m.Health.Areas['operation'].Values
        $o['operation.lastBoot'].Value -is [long] | Should -BeTrue
        $vol = $o['operation.volumes'].Value[0]
        $vol['SizeGB'] -is [long] | Should -BeTrue; $vol['FreeGB'] -is [double] | Should -BeTrue; $vol['System'] -is [bool] | Should -BeTrue
        $vol['UsedGB'] | Should -BeNullOrEmpty; $vol['Files'] | Should -BeNullOrEmpty; $vol.Contains('UsedGB') | Should -BeTrue    # ein Feld eines Eintrags wird $null
        $m.Health.DurationMs | Should -Be 900
    }
    It 'nennt eine nicht lesbare health.json mit dem ganzen Text der Warnung' {   # Fix-Runde 1, Punkt 5 und 6
        $dir = Write-QuickRun 'hwarn' '{"FormatVersion":1,"DurationMs":900,"Areas":{}}'
        $w = @(Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $w.Count | Should -Be 1; $w[0].Message | Should -BeExactly 'health.json ist nicht lesbar (ReadAt fehlt); der Bericht zeigt kein Zustandsbild.'
        (Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles 3>$null).HealthState | Should -Be 'unreadable'
    }
    It 'nimmt HealthOnly nur als Wahrheitswert true als Schnelllauf' {   # Fix-Runde 1, Punkt 4
        foreach ($given in '"false"', '"true"', '1', '0', 'null', '{}') {
            $dir = Write-TestRun ('hof' + [Math]::Abs($given.GetHashCode())) @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }; $meta = Join-Path $dir 'meta.json'
            [IO.File]::WriteAllText($meta, [IO.File]::ReadAllText($meta).Replace('"Simulated":false,', '"Simulated":false,"HealthOnly":' + $given + ','))
            $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles
            $m.Meta.HealthOnly | Should -BeFalse -Because $given; $m.Tick.N | Should -Be 8 -Because $given
        }
        $dir = Write-QuickRun 'hoftext' '{"FormatVersion":1,"ReadAt":"2026-01-15T08:00:01.0000000+02:00","DurationMs":900,"Areas":{}}'; $meta = Join-Path $dir 'meta.json'
        [IO.File]::WriteAllText($meta, [IO.File]::ReadAllText($meta).Replace('"HealthOnly":true,', '"HealthOnly":"true",'))
        { Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles } | Should -Throw '*keine Messung*'
    }
    It 'lehnt -To allein fuer einen Schnelllauf ab' {   # Fix-Runde 1, Punkt 6
        $dir = Write-QuickRun 'hto' '{"FormatVersion":1,"ReadAt":"2026-01-15T08:00:01.0000000+02:00","DurationMs":900,"Areas":{}}'
        { Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles -To ([datetime]'2026-01-15T09:00:00') } | Should -Throw 'Die Aufzeichnung ist ein Schnelllauf ohne Messung; -From und -To gelten nicht.'
    }
    It 'liest einen Schnelllauf ohne lesbare Startzeit' {   # Fix-Runde 1, Punkt 6
        $dir = Write-QuickRun 'hnostart' '{"FormatVersion":1,"ReadAt":"2026-01-15T08:00:01.0000000+02:00","DurationMs":900,"Areas":{}}'; $meta = Join-Path $dir 'meta.json'
        [IO.File]::WriteAllText($meta, [IO.File]::ReadAllText($meta).Replace('"StartTime":"2026-01-15T08:00:00.0000000+02:00"', '"StartTime":"keine Zeit"'))
        $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles
        $m.Meta.HealthOnly | Should -BeTrue; $m.CaptureStartMs | Should -BeNullOrEmpty; $m.CaptureEndMs | Should -BeNullOrEmpty; $m.Meta.OffsetMinutes | Should -Be 0
        $m.HealthState | Should -Be 'read'
    }
    It 'fuehrt Rueckblick und Treiberliste, die Skip weglaesst, als nicht aufgezeichnet' {   # Fix-Runde 1, Punkt 6
        $dir = Write-QuickRun 'hskiprec' '{"FormatVersion":1,"ReadAt":"2026-01-15T08:00:01.0000000+02:00","DurationMs":900,"Areas":{}}'; $meta = Join-Path $dir 'meta.json'
        (Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles).Recorded.EventsBefore | Should -BeTrue
        [IO.File]::WriteAllText($meta, [IO.File]::ReadAllText($meta).Replace('"Skip":[]', '"Skip":["Rueckblick","Drucken"]'))
        Test-Path (Join-Path $dir 'events_before.csv') | Should -BeTrue; Test-Path (Join-Path $dir 'printdrivers.csv') | Should -BeTrue
        $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles
        $m.Recorded.EventsBefore | Should -BeFalse; $m.Recorded.PrintDrivers | Should -BeFalse
    }
    It 'fuehrt einen Schnelllauf ohne Zustandsbild als nicht erfasst und liest keine Zwischendatei' {   # Ergaenzung e
        $dir = Write-QuickRun 'hnone' '' '"EndMessage":"Das Lesen des Zustandsbilds ist gescheitert (RuntimeException).","SourceErrors":{"health":{"Count":1,"FirstTime":"2026-01-15T08:00:01.0000000+02:00","FirstMessage":"Testfehler"}},'
        [IO.File]::WriteAllText((Join-Path $dir 'health.json.tmp'), '{"FormatVersion":1,"ReadAt":"2026-01-15T08:00:01.0000000+02:00","DurationMs":900,"Areas":{}}')
        $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles 3>$null
        $m.HealthState | Should -Be 'notRecorded'; $m.Health | Should -BeNullOrEmpty
        @($m.SourceErrors | ForEach-Object { $_.Source }) | Should -Be @('health'); $m.Meta.EndMessage | Should -Match 'Zustandsbild'
    }
    It 'gibt einem Schnelllauf dieselben Schluessel wie einer Messung' {   # Ergaenzung g
        $c = Import-TestRun 'hkeys' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }
        $q = Import-WorkerPerfRun -Path (Write-QuickRun 'qkeys' '{"FormatVersion":1,"ReadAt":"2026-01-15T08:00:01.0000000+02:00","DurationMs":900,"Areas":{}}') -Thresholds $Th -Roles $Roles
        @($q.Keys | Sort-Object) | Should -Be @($c.Keys | Sort-Object)
        foreach ($part in 'Tick', 'Snap', 'Rows', 'InputProc', 'Carried', 'Unreadable', 'Recorded') {
            @($q[$part].Keys | Sort-Object) | Should -Be @($c[$part].Keys | Sort-Object) -Because $part
            foreach ($k in @($c[$part].Keys)) {
                if ($c[$part][$k] -is [array]) { $q[$part][$k].GetType() | Should -Be $c[$part][$k].GetType() -Because "$part.$k" }
            }
        }
        foreach ($part in 'Raw', 'Signal') { @($q.Tick[$part].Keys | Sort-Object) | Should -Be @($c.Tick[$part].Keys | Sort-Object) -Because $part }
        foreach ($k in 'Cores', 'RamMB', 'OffsetMinutes', 'FastSec', 'SnapSec', 'HealthOnly', 'EventLookbackDays', 'LookbackCapped', 'EventReadCounts', 'LookbackReadCounts', 'Computer') {
            $q.Meta.ContainsKey($k) | Should -BeTrue -Because $k; $c.Meta.ContainsKey($k) | Should -BeTrue -Because $k
        }
        foreach ($k in @($c.Keys)) {
            if ($c[$k] -is [array]) { $q[$k].GetType() | Should -Be $c[$k].GetType() -Because $k; $q[$k].Length | Should -Be 0 -Because $k }
        }
        $q.MainApp | Should -BeNullOrEmpty; $q.TotalCpuMs | Should -Be 0; $q.EventsOutsideCut | Should -Be 0; $q.CaptureEndMs | Should -Be $q.CaptureStartMs
        $q.Rows.Start | Should -Be @(0); $q.Pairs.Count | Should -Be 0
    }
}
