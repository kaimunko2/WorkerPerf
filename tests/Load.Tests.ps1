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
