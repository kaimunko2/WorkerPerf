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
        [IO.File]::WriteAllText($meta, $text.Replace('"SchemaVersion":2,', '"SchemaVersion":3,'))
        { Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles } | Should -Throw '*Format 3*Format 2*'
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
