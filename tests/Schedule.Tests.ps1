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
    It 'formatiert Rundung, leere Werte und Texte wie bisher' {                # Task 14a: recorded with the former version
        [cultureinfo]::CurrentCulture = [cultureinfo]'de-DE'
        $nan = [double]::NaN
        $vol = { param($Name, $Kind, $Sid, $Back, $Rl, $Wl, $Ro, $Wo, $Rb, $Wb, $Q)
            [pscustomobject]@{ Volume = $Name; Kind = $Kind; SessionId = $Sid; Backing = $Back; ReadLatMs = $Rl; WriteLatMs = $Wl; ReadOps = $Ro; WriteOps = $Wo; ReadBps = $Rb; WriteBps = $Wb; Queue = $Q } }
        $s = [pscustomobject]@{
            Time = [datetime]'2026-01-15T08:00:02.5'; CpuPct = 99.996; ProcQueue = 2.5; StealPct = $nan; MemAvailMB = 20000.5; MemCommittedMB = 30001.5
            MemCommitLimitMB = [double]::PositiveInfinity; PagesInPerSec = 0.25; DiskReadBps = 1234567.891; DiskWriteBps = $null; DiskReadIops = 10.06
            DiskWriteIops = -3.75; DiskQueue = 3.5; NetRecvBps = 123456789012; NetSentBps = 0.0
            Volumes = @(
                (& $vol 'C:' 'disk' $null '' 2.347 0.125 12 0 5000.5 0 1),
                (& $vol 'D:' 'disk' $null '' $null $nan 0 0 0 0 0),
                (& $vol 'HarddiskVolume12' 'profile' 4 '\\fs01\profile$' 1.006 44.4449 30 20.5 6291456 4194304 3),
                (& $vol 'Vol,"x"' 'profile' '' 'Ärzte, "Daten"' $nan $null 0 1 2.5 3.5 ([double]::NegativeInfinity)),
                $null)
            Shares = @(
                [pscustomobject]@{ Share = '\\fs01\daten'; ReadLatMs = 78.125; WriteLatMs = $null; ReadOps = 100; WriteOps = 0.4; ReadBps = 20971520; WriteBps = 0 },
                [pscustomobject]@{ Share = '\\fs01\leer'; ReadLatMs = 1; WriteLatMs = 1; ReadOps = 0; WriteOps = 0; ReadBps = 0; WriteBps = 0 },
                [pscustomobject]@{ Share = "\\fs01\Büro,""neu""`r`nZeile"; ReadLatMs = $nan; WriteLatMs = 2.676; ReadOps = 1.5; WriteOps = 0; ReadBps = 1.5; WriteBps = 0 })
            InputSessions = @([pscustomobject]@{ SessionId = 5; DelayMs = 0 }, [pscustomobject]@{ SessionId = 6; DelayMs = 300.5 },
                [pscustomobject]@{ SessionId = 7; DelayMs = $null }, [pscustomobject]@{ SessionId = 8; DelayMs = 1.5 }, $null)
            InputProcesses = @([pscustomobject]@{ SessionId = 6; Pid = 100; Name = 'a.exe'; DelayMs = 49.9 },
                [pscustomobject]@{ SessionId = 6; Pid = 200; Name = 'Übersicht, "alt".exe'; DelayMs = 80.5 },
                [pscustomobject]@{ SessionId = 8; Pid = 300; Name = 'c.exe'; DelayMs = $null }, [pscustomobject]@{ SessionId = 8; Pid = 301; Name = ''; DelayMs = 50 })
        }
        $r = ConvertTo-WorkerPerfFastRows -Sample $s -T 42 -ElapsedSec 2.0006 -Burst $false -CollectMs 12.5
        $r.Tick | Should -BeExactly '42,2026-01-15T08:00:02.5000000,2.001,100,2,,20000,30002,,0.2,1234568,,10.1,-3.8,4,123456789012,0,0,12'
        $r.Volumes | Should -BeExactly @('42,C:,disk,,,2.35,0.12,12,0,5000,0,1', '42,HarddiskVolume12,profile,4,\\fs01\profile$,1.01,44.44,30,20,6291456,4194304,3',
            '42,"Vol,""x""",profile,0,"Ärzte, ""Daten""",,,0,1,2,4,')
        $r.Shares | Should -BeExactly @('42,\\fs01\daten,78.12,,100,0,20971520,0', '42,"\\fs01\Büro,""neu""  Zeile",,2.68,2,0,2,0')
        $r.InputSessions | Should -BeExactly @('42,6,300', '42,8,2')
        $r.InputProcesses | Should -BeExactly @('42,6,200,"Übersicht, ""alt"".exe",80', '42,8,301,,50')
        foreach ($k in 'Volumes', 'Shares', 'InputSessions', 'InputProcesses') { , $r[$k] | Should -BeOfType [string[]] }
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
Describe 'Proben, meta.json und Fehler der Datenquelle' {                          # Abschlussrunde
    It 'vermerkt eine fehlgeschlagene Probe mit ihrer Dauer bis zum Abbruch' {     # Minor 13
        $ok = [pscustomobject]@{ Name = 'DB'; Role = 'Datenbank'; Host = 'h'; Port = 1521; ConnectMs = 12.34; Error = '' }
        $bad = [pscustomobject]@{ Name = 'Proxy, alt'; Role = 'Proxy'; Host = 'p'; Port = 8080; ConnectMs = 2000.4; Error = 'timeout' }
        ConvertTo-WorkerPerfProbeRow -Result $ok -T 7 | Should -Be '7,DB,Datenbank,h,1521,12.3,'
        ConvertTo-WorkerPerfProbeRow -Result $bad -T 7 | Should -Be '7,"Proxy, alt",Proxy,p,8080,2000.4,timeout'
        ConvertTo-WorkerPerfProbeRow -Result ([pscustomobject]@{ Name = 'X'; Role = ''; Host = 'x'; Port = 1; ConnectMs = $null; Error = 'dns' }) -T 7 | Should -Be '7,X,,x,1,,dns'
    }
    It 'schreibt meta.json ueber eine Zwischendatei' {                              # Minor 7
        $dir = Join-Path $TestDrive 'meta'; [void](New-Item -ItemType Directory $dir); $file = Join-Path $dir 'meta.json'
        Save-WorkerPerfMeta -Path $file -Meta ([ordered]@{ A = 1; EndReason = $null })
        Save-WorkerPerfMeta -Path $file -Meta ([ordered]@{ A = 2; EndReason = 'duration' })
        (Get-Content $file -Raw | ConvertFrom-Json).A | Should -Be 2
        @(Get-ChildItem $dir).Name | Should -Be @('meta.json')
        [IO.File]::ReadAllBytes($file)[0] | Should -Be ([byte][char]'{')              # ohne BOM
        [void](New-Item -ItemType Directory (Join-Path $dir 'meta.json.tmp'))          # das Schreiben der Zwischendatei scheitert
        { Save-WorkerPerfMeta -Path $file -Meta ([ordered]@{ A = 3 }) } | Should -Throw
        (Get-Content $file -Raw | ConvertFrom-Json).A | Should -Be 2                  # die vorhandene Datei bleibt vollstaendig
    }
    It 'zaehlt Fehler je Quelle und merkt sich den ersten' {                         # I6
        $e = [ordered]@{}
        Add-WorkerPerfSourceError -Errors $e -Source 'events' -Time $t -Message 'erster' | Should -BeTrue
        Add-WorkerPerfSourceError -Errors $e -Source 'events' -Time $t.AddSeconds(15) -Message 'zweiter' | Should -BeFalse
        Add-WorkerPerfSourceError -Errors $e -Source 'fast' -Time $t.AddSeconds(20) -Message 'Takt' | Should -BeTrue
        $e['events'].Count | Should -Be 2; $e['events'].FirstMessage | Should -Be 'erster'; $e['events'].FirstTime | Should -Be $t.ToString('o', [cultureinfo]::InvariantCulture)
        @($e.Keys) | Should -Be @('events', 'fast')
    }
    It 'rechnet Zeiten fuer den Zeitplan nach UTC um' {                              # Minor 8
        $utc = [datetime]::SpecifyKind($t, 'Utc'); $local = $utc.ToLocalTime()
        (ConvertTo-WorkerPerfUtc $utc) | Should -Be $utc; (ConvertTo-WorkerPerfUtc $utc).Kind | Should -Be 'Utc'
        (ConvertTo-WorkerPerfUtc $local) | Should -Be $utc; (ConvertTo-WorkerPerfUtc $local).Kind | Should -Be 'Utc'
    }
}
