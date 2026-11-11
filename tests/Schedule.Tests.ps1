BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Capture.ps1')
    $script:Th = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json')
    $script:t = [datetime]'2026-01-15T08:00:00'
    function New-TestVolume([string]$Name, $ReadLat, [double]$ReadOps) {
        [pscustomobject]@{ Volume = $Name; Kind = 'disk'; SessionId = $null; Backing = ''; ReadLatMs = $ReadLat; WriteLatMs = $null; ReadOps = $ReadOps; WriteOps = 0; ReadBps = 5000; WriteBps = 0; Queue = 1 }
    }
    $script:Sample = [pscustomobject]@{
        Time = [datetime]'2026-01-15T08:00:02'; CpuPct = 12.5; ProcQueue = 3; StealPct = $null; MemAvailMB = 20000.4; MemCommittedMB = 30000; MemCommitLimitMB = 70000
        PagesInPerSec = 1.26; DiskReadBps = 1000; DiskWriteBps = 2000; DiskReadIops = 10.5; DiskWriteIops = 20; DiskQueue = 0; NetRecvBps = 300; NetSentBps = 400
        Volumes = @((New-TestVolume 'C:' 2.347 12), (New-TestVolume 'D:' $null 0)); Shares = @()
        InputSessions = @([pscustomobject]@{ SessionId = 5; DelayMs = 0 }, [pscustomobject]@{ SessionId = 6; DelayMs = 300 })
        InputProcesses = @([pscustomobject]@{ SessionId = 6; Pid = 100; Name = 'a.exe'; DelayMs = 30 }, [pscustomobject]@{ SessionId = 6; Pid = 200; Name = 'b.exe'; DelayMs = 80 })
    }
}
Describe 'Update-WorkerPerfBurstState' {
    It 'bleibt 60 Sekunden nach dem letzten Ausloeser aktiv' {
        $s = New-WorkerPerfBurstState
        Update-WorkerPerfBurstState -State $s -Now $t -BadSignals @('cpu.host') | Should -BeTrue
        Update-WorkerPerfBurstState -State $s -Now $t.AddSeconds(60) -BadSignals @() | Should -BeTrue
        Update-WorkerPerfBurstState -State $s -Now $t.AddSeconds(62) -BadSignals @() | Should -BeFalse
    }
    It 'begrenzt die Verdichtung bei dauerhaft ueberschrittener Schwelle' {     # Review Focus 1
        $s = New-WorkerPerfBurstState
        $active = foreach ($i in 0..299) { Update-WorkerPerfBurstState -State $s -Now $t.AddSeconds(2 * $i) -BadSignals @('mem.used') }
        @($active | Where-Object { $_ }).Count | Should -Be 181              # 151 Takte bis 300 s, danach 30 Takte Nachlauf
        Update-WorkerPerfBurstState -State $s -Now $t.AddSeconds(600) -BadSignals @() | Should -BeFalse
        Update-WorkerPerfBurstState -State $s -Now $t.AddSeconds(602) -BadSignals @('mem.used') | Should -BeTrue      # nach Entwarnung wieder scharf
    }
    It 'fuehrt die Begrenzung je Signal' {
        $s = New-WorkerPerfBurstState
        foreach ($i in 0..199) { [void](Update-WorkerPerfBurstState -State $s -Now $t.AddSeconds(2 * $i) -BadSignals @('mem.used')) }
        Update-WorkerPerfBurstState -State $s -Now $t.AddSeconds(400) -BadSignals @('mem.used', 'cpu.host') | Should -BeTrue
    }
}
Describe 'Zeitplan' {
    It 'laesst ausgefallene Takte aus, statt sie nachzuholen' {
        $r = Get-WorkerPerfNextTick -Scheduled $t.AddSeconds(2) -Now $t.AddSeconds(7.5) -IntervalSeconds 2
        $r.Next | Should -Be $t.AddSeconds(8); $r.Skipped | Should -Be 2
        (Get-WorkerPerfNextTick -Scheduled $t.AddSeconds(2) -Now $t.AddSeconds(2.3) -IntervalSeconds 2).Skipped | Should -Be 0
    }
    It 'waehlt den regulaeren Schnappschuss vor der Verdichtung' {
        Get-WorkerPerfSnapshotDue -Now $t.AddSeconds(15) -NextRegular $t.AddSeconds(15) -LastSnapshot $t -BurstActive $true | Should -Be 'regular'
        Get-WorkerPerfSnapshotDue -Now $t.AddSeconds(6) -NextRegular $t.AddSeconds(15) -LastSnapshot $t -BurstActive $true | Should -Be 'burst'
        Get-WorkerPerfSnapshotDue -Now $t.AddSeconds(4) -NextRegular $t.AddSeconds(15) -LastSnapshot $t -BurstActive $true | Should -Be 'none'
        Get-WorkerPerfSnapshotDue -Now $t.AddSeconds(6) -NextRegular $t.AddSeconds(15) -LastSnapshot $t -BurstActive $false | Should -Be 'none'
    }
}
Describe 'Test-WorkerPerfGuard' {
    It 'bricht bei knappem Platz und an der Obergrenze ab' {
        Test-WorkerPerfGuard -FreeMB 150 -SizeMB 0 -MaxSizeMB 500 -Phase start 3>$null | Should -Be 'diskspace'
        $out = @(Test-WorkerPerfGuard -FreeMB 500 -SizeMB 0 -MaxSizeMB 500 -Phase start 3>&1)      # nur eine Warnung, kein Abbruchgrund
        @($out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 1
        @($out | Where-Object { $_ -is [string] }).Count | Should -Be 0
        Test-WorkerPerfGuard -FreeMB 5000 -SizeMB 500 -MaxSizeMB 500 -Phase run | Should -Be 'maxsize'
        Test-WorkerPerfGuard -FreeMB 199 -SizeMB 10 -MaxSizeMB 500 -Phase run | Should -Be 'diskspace'
        Test-WorkerPerfGuard -FreeMB 5000 -SizeMB 10 -MaxSizeMB 500 -Phase run | Should -BeNullOrEmpty
    }
}
Describe 'ConvertTo-WorkerPerfFastRows' {
    It 'schreibt den Takt und nur Instanzen mit Aktivitaet' {                   # Review Focus 2
        [cultureinfo]::CurrentCulture = [cultureinfo]'de-DE'
        $r = ConvertTo-WorkerPerfFastRows -Sample $Sample -T 7 -ElapsedSec 2 -Burst $true -CollectMs 41.6
        $r.Tick | Should -Be '7,2026-01-15T08:00:02.0000000,2,12.5,3,,20000,30000,70000,1.3,1000,2000,10.5,20,0,300,400,1,42'
        $r.Volumes | Should -Be @('7,C:,disk,,,2.35,,12,0,5000,0,1')
        $r.Shares.Count | Should -Be 0
        $r.InputSessions | Should -Be @('7,6,300'); $r.InputProcesses | Should -Be @('7,6,200,b.exe,80')
    }
}
Describe 'Get-WorkerPerfTriggerSignals' {
    It 'meldet nur Ausloeser ueber der Schwelle und beachtet minOps' {
        Get-WorkerPerfTriggerSignals -Sample $Sample -Thresholds $Th -LogicalProcessors 8 -PhysicalMemoryMB 65536 | Should -Be @('input.session')
        $busy = $Sample.PSObject.Copy(); $busy.CpuPct = 80; $busy.MemAvailMB = 6000; $busy.Volumes = @(New-TestVolume 'C:' 30 2)
        Get-WorkerPerfTriggerSignals -Sample $busy -Thresholds $Th -LogicalProcessors 8 -PhysicalMemoryMB 65536 | Should -Be @('cpu.host', 'mem.used', 'input.session')
        $busy.Volumes = @(New-TestVolume 'C:' 30 20)
        Get-WorkerPerfTriggerSignals -Sample $busy -Thresholds $Th -LogicalProcessors 8 -PhysicalMemoryMB 65536 | Should -Contain 'disk.latency'
    }
}
Describe 'New-WorkerPerfWriters' {
    It 'legt alle Dateien mit Kopfzeile ohne BOM an' {
        $dir = Join-Path $TestDrive 'w'; [void](New-Item -ItemType Directory $dir)
        $w = New-WorkerPerfWriters -RunDir $dir; foreach ($x in $w.Values) { $x.Dispose() }
        $w.Count | Should -Be 13
        [IO.File]::ReadAllBytes((Join-Path $dir 'ticks.csv'))[0] | Should -Be ([byte][char]'T')
    }
}
