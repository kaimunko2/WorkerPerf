BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Load.ps1')
    $script:Th = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json')
    $script:Roles = Read-WorkerPerfRoles (Join-Path $PSScriptRoot '../src/roles.json')
    $script:Base = [DateTimeOffset]'2026-01-15T08:00:00+01:00'
    function Get-Ts([double]$Sec) { $Base.AddSeconds($Sec).ToString('o') }
    function New-TickLine([int]$T, [double]$Cpu = 50) { "$T,$(Get-Ts (2 * ($T + 1))),2,$Cpu,8,,4096,8000,20000,0,0,0,0,0,0,0,0,0,5" }
    function New-SnapLine([int]$P, [string]$Kind = 'R') { "$P,$(2 * $P + 1),$(Get-Ts (4 * ($P + 1))),4,$Kind,1,1,3,3,20" }
    function Write-TestRun([string]$Name, [hashtable]$Files) {
        $dir = Join-Path $TestDrive $Name; [void](New-Item -ItemType Directory -Path $dir -Force)
        foreach ($f in $WorkerPerfHeaders.Keys) {
            if ($Files.ContainsKey($f) -and $null -eq $Files[$f]) { continue }             # $null = die Datei fehlt
            [IO.File]::WriteAllLines((Join-Path $dir $f), [string[]](@($WorkerPerfHeaders[$f]) + @($Files[$f] | Where-Object { $_ })))
        }
        $meta = '{"SchemaVersion":2,"Computer":"T1","OS":"x","LogicalProcessors":4,"PhysicalMemoryMB":16384,"FastIntervalSeconds":2,"IntervalSeconds":4,"StartTime":"' + (Get-Ts 0) +
            '","EndTime":null,"CollectorPid":4242,"Simulated":false,"Endpoints":[{"Name":"DB","Host":"h","Port":1521,"Role":"Datenbank"}],' +
            '"Sources":{"cpu.host":{"Available":true,"Detail":""},"cpu.steal":{"Available":false,"Detail":"VM Processor fehlt"}}}'
        [IO.File]::WriteAllText((Join-Path $dir 'meta.json'), $meta); $dir
    }
    function Import-TestRun([string]$Name, [hashtable]$Files, [hashtable]$Extra = @{}) { Import-WorkerPerfRun -Path (Write-TestRun $Name $Files) -Thresholds $Th -Roles $Roles @Extra }
    # Grundgeruest: 8 Takte bei 2, 4, ... 16 s; 4 Schnappschuesse bei 4, 8, 12, 16 s (Schnappschuss P liegt auf Takt 2P + 1)
    $script:Ticks = 0..7 | ForEach-Object { New-TickLine $_ }
    $script:SnapLines = 0..3 | ForEach-Object { New-SnapLine $_ $(if ($_ -eq 0) { 'K' } else { 'R' }) }
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
    }
    It 'kommt ohne optionale Dateien aus' {
        $m = Import-TestRun 'c' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'shares.csv' = $null; 'probes.csv' = $null; 'events.csv' = $null; 'citrix.csv' = $null; 'inputdelay_proc.csv' = $null }
        @($m.Shares).Count | Should -Be 0; @($m.Probes).Count | Should -Be 0; @($m.Events).Count | Should -Be 0
    }
    It 'schneidet auf -From und -To zu' {
        $m = Import-TestRun 'd' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines } @{ From = $Base.AddSeconds(7).LocalDateTime; To = $Base.AddSeconds(13).LocalDateTime }
        $m.Tick.N | Should -Be 3; $m.Snap.N | Should -Be 2
    }
    It 'meldet eine Aufzeichnung ohne Schnappschuss verstaendlich' { { Import-TestRun 'e' @{ 'ticks.csv' = $Ticks } } | Should -Throw '*Schnappschuss*' }
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
        $m = Import-TestRun 'f' $Files @{ From = $Base.AddSeconds(9).LocalDateTime }
        $m.Snap.N | Should -Be 2
        $m.Sessions[0].Rtt[0] | Should -Be 102; $m.Sessions[0].Rtt[1] | Should -Be 103
        $m.Citrix[0].N | Should -Be 2; $m.Citrix[0].Avg | Should -Be 102.5
        $m.Probes[0].Ms[0] | Should -Be 102; $m.Probes[0].Ms[1] | Should -Be 103
    }
    It 'ordnet Zeilen nach -To keinem Schnappschuss zu' {
        $m = Import-TestRun 'g' $Files @{ To = $Base.AddSeconds(9).LocalDateTime }
        $m.Snap.N | Should -Be 2
        $m.Sessions[0].Rtt[1] | Should -Be 101; $m.Citrix[0].N | Should -Be 2; $m.Probes[0].Ms[1] | Should -Be 101
    }
}
