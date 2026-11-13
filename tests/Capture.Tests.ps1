BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Capture.ps1')
    $script:t = [datetime]'2026-01-15T08:00:00'
    function New-TestProc([int]$Id, [double]$CpuSec, [double]$WsMB, [double]$IoBytes = 0, [datetime]$Start = [datetime]'2026-01-01') {
        [pscustomobject]@{ ProcessId = $Id; ParentProcessId = 4; Name = "p$Id.exe"; SessionId = 1
            KernelModeTime = [uint64]0; UserModeTime = [uint64]($CpuSec * 1e7); WorkingSetSize = [uint64]($WsMB * 1MB); PrivatePageCount = [uint64]($WsMB * 1MB)
            ReadTransferCount = [uint64]$IoBytes; WriteTransferCount = [uint64]0; ReadOperationCount = [uint64]0; WriteOperationCount = [uint64]0
            HandleCount = 100; ThreadCount = 5; CreationDate = $Start; ExecutablePath = "C:\App\p$Id.exe"; CommandLine = '' }
    }
    function Start-TestState([object[]]$Procs) {      # Grundstand und erster Stuetzpunkt
        $s = New-WorkerPerfProcessState
        [void](Get-WorkerPerfProcessRows -State $s -Processes $Procs -P -1 -PrevTime $t)
        [void](Get-WorkerPerfProcessRows -State $s -Processes $Procs -P 0 -PrevTime $t -Keyframe)
        $s
    }
}
Describe 'Get-WorkerPerfProcessRows' {
    It 'schreibt im Stuetzpunkt alle, danach nur aktive Prozesse' {
        $s = New-WorkerPerfProcessState; $both = @((New-TestProc 10 1 100), (New-TestProc 20 1 100))
        (Get-WorkerPerfProcessRows -State $s -Processes $both -P -1 -PrevTime $t).Rows.Count | Should -Be 0
        $r0 = Get-WorkerPerfProcessRows -State $s -Processes $both -P 0 -PrevTime $t -Keyframe
        $r0.Rows.Count | Should -Be 2; $r0.Info.Count | Should -Be 2; $r0.Total | Should -Be 2
        $r1 = Get-WorkerPerfProcessRows -State $s -Processes @((New-TestProc 10 1.5 100), (New-TestProc 20 1 100)) -P 1 -PrevTime $t
        $r1.Rows | Should -Be @('1,0,500,102400,102400,0,0,0,100,5'); $r1.CpuMs | Should -Be 500
    }
    It 'sammelt Speicheraenderungen bis zur Schwelle von 1 MB' {
        $s = Start-TestState @(New-TestProc 10 1 100)
        $counts = foreach ($i in 1..4) { (Get-WorkerPerfProcessRows -State $s -Processes @(New-TestProc 10 1 (100 + 0.3 * $i)) -P $i -PrevTime $t).Rows.Count }
        $counts | Should -Be @(0, 0, 0, 1)
    }
    It 'verliert keine CPU-Zeit unterhalb einer Millisekunde' {
        $s = Start-TestState @(New-TestProc 10 1 100); $ms = 0
        foreach ($i in 1..10) {
            $r = Get-WorkerPerfProcessRows -State $s -Processes @(New-TestProc 10 (1 + 0.0004 * $i) 100) -P $i -PrevTime $t
            foreach ($row in $r.Rows) { $ms += [int]$row.Split(',')[2] }
        }
        $ms | Should -Be 4
    }
    It 'wertet I/O als Aktivitaet' {
        $s = Start-TestState @(New-TestProc 10 1 100)
        (Get-WorkerPerfProcessRows -State $s -Processes @(New-TestProc 10 1 100 -IoBytes 4096) -P 1 -PrevTime $t).Rows | Should -Be @('1,0,0,102400,102400,4096,0,0,100,5')
    }
    It 'rechnet einem im Intervall gestarteten Prozess seine bisherige CPU-Zeit an' {
        $s = New-WorkerPerfProcessState
        [void](Get-WorkerPerfProcessRows -State $s -Processes @() -P -1 -PrevTime $t)
        $r = Get-WorkerPerfProcessRows -State $s -Processes @((New-TestProc 30 2 50 -Start $t.AddSeconds(5)), (New-TestProc 40 7 50 -Start $t.AddHours(-1))) -P 0 -PrevTime $t -Keyframe
        ($r.Rows | ForEach-Object { $_.Split(',')[2] }) | Should -Be @('2000', '0')
    }
    It 'meldet beendete Prozesse und unterscheidet wiederverwendete PIDs' {    # Review Focus 4
        $a = New-TestProc 10 1 100; $s = Start-TestState @($a, (New-TestProc 20 1 100))
        $r = Get-WorkerPerfProcessRows -State $s -Processes @($a, (New-TestProc 20 0.5 80 -Start $t.AddSeconds(20))) -P 2 -PrevTime $t.AddSeconds(15)
        $r.Ended | Should -Be @('2,1'); $r.Info.Count | Should -Be 1; $r.Info[0] | Should -Match '^2,20,'
        $r.Rows | Should -Be @('2,2,500,81920,81920,0,0,0,100,5')
    }
    It 'traegt Dienste und auf Wunsch die Befehlszeile ein' {
        $s = New-WorkerPerfProcessState; $p = New-TestProc 10 1 100; $p.CommandLine = 'p10.exe /x'
        [void](Get-WorkerPerfProcessRows -State $s -Processes @($p) -P -1 -PrevTime $t)
        (Get-WorkerPerfProcessRows -State $s -Processes @($p) -P 0 -PrevTime $t -Keyframe -Services @{ 10 = 'AppIDSvc;Foo' }).Info[0] | Should -Match ',AppIDSvc;Foo,$'
        $s2 = New-WorkerPerfProcessState
        [void](Get-WorkerPerfProcessRows -State $s2 -Processes @($p) -P -1 -PrevTime $t)
        (Get-WorkerPerfProcessRows -State $s2 -Processes @($p) -P 0 -PrevTime $t -Keyframe -IncludeCommandLine).Info[0] | Should -Match ',p10\.exe /x$'
    }
}
Describe 'Zeilen von Format 3' {
    It 'schreibt Ereigniszeilen in der Spaltenfolge der Kopfzeile' {
        $e = [pscustomobject]@{ Time = [datetime]'2026-01-15T08:00:00'; Log = 'application'; Source = 'Application Error'; EventId = 1000; Level = 2; Group = 'app'; Kind = 'crash'
            App = 'EXCEL.EXE'; Module = 'vbe7.dll'; Code = '0xc0000005'; Pid = 812; SessionId = 3; User = 'user002'; Text = 'a, "b"' }
        $f = Split-WorkerPerfCsvLine (ConvertTo-WorkerPerfEventRow $e)
        $f.Count | Should -Be 20; $f[1] | Should -Be 'application'; $f[7] | Should -Be 'EXCEL.EXE'; $f[12] | Should -Be '812'; $f[19] | Should -Be 'a, "b"'; $f[8] | Should -Be ''
    }
    It 'schreibt eine Ereigniszeile mit allen Feldern und laesst leere Zahlen leer' {
        $e = [pscustomobject]@{ Time = [datetime]'2026-01-15T08:00:00'; Log = 'printservice'; Source = 'Microsoft-Windows-PrintService'; EventId = 372; Level = 2; Group = 'print'; Kind = 'print'
            App = ''; AppVersion = '1.2'; Module = ''; ModuleVersion = '3.4'; Code = ''; Pid = $null; SessionId = $null; User = ''; Printer = 'Drucker 1'; Driver = 'Sim PCL 6'
            Service = 'Spooler'; Object = 'obj'; Text = 'x' }
        $f = Split-WorkerPerfCsvLine (ConvertTo-WorkerPerfEventRow $e)
        $f.Count | Should -Be 20
        $f[0] | Should -Be ([datetime]'2026-01-15T08:00:00').ToString('o'); $f[2] | Should -Be 'Microsoft-Windows-PrintService'; $f[3] | Should -Be '372'; $f[4] | Should -Be '2'
        $f[5] | Should -Be 'print'; $f[6] | Should -Be 'print'; $f[8] | Should -Be '1.2'; $f[10] | Should -Be '3.4'; $f[12] | Should -Be ''; $f[13] | Should -Be ''
        $f[15] | Should -Be 'Drucker 1'; $f[16] | Should -Be 'Sim PCL 6'; $f[17] | Should -Be 'Spooler'; $f[18] | Should -Be 'obj'
    }
    It 'schreibt einen Datensatz von Format 2 mit leeren neuen Spalten' {
        $e = [pscustomobject]@{ Time = [datetime]'2026-01-15T08:00:00'; Source = 'Defender'; EventId = 1000; Kind = 'scan-start'; Text = 'Scan' }
        $f = Split-WorkerPerfCsvLine (ConvertTo-WorkerPerfEventRow $e)
        $f.Count | Should -Be 20; $f[2] | Should -Be 'Defender'; $f[6] | Should -Be 'scan-start'; $f[19] | Should -Be 'Scan'
        @($f[1], $f[4], $f[5], $f[12], $f[13], $f[14]) | Should -Be @('', '', '', '', '', '')
    }
    It 'schreibt Treiber- und Warteschlangenzeilen' {
        $d = [pscustomobject]@{ Name = 'Sim PCL 6, x'; Manufacturer = 'HP'; Version = '61.1.0.0'; Type = 3; Isolation = 'shared'; Files = @('hpsimgr.dll', 'hpsimui.dll') }
        ConvertTo-WorkerPerfPrintDriverRow $d | Should -Be '"Sim PCL 6, x",HP,61.1.0.0,3,shared,hpsimgr.dll;hpsimui.dll'
        $d2 = [pscustomobject]@{ Name = 'Typ 4'; Manufacturer = ''; Version = ''; Type = $null; Isolation = ''; Files = @() }
        ConvertTo-WorkerPerfPrintDriverRow $d2 | Should -Be 'Typ 4,,,,,'
        $q = [pscustomobject]@{ Queue = 'Drucker 1'; Jobs = 2; JobErrors = 17; NotReadyErrors = 0 }
        ConvertTo-WorkerPerfPrintQueueRow $q ([datetime]'2026-01-15T08:00:00') | Should -Be (([datetime]'2026-01-15T08:00:00').ToString('o') + ',Drucker 1,2,17,0')
    }
    It 'ergaenzt Sitzung und Benutzer ueber die PID des letzten Schnappschusses' {                # Review Focus 4
        $procs = @([pscustomobject]@{ ProcessId = 812; SessionId = 3 }, [pscustomobject]@{ ProcessId = 900; SessionId = 0 })
        $sess = @([pscustomobject]@{ SessionId = 3; User = 'user002' }, [pscustomobject]@{ SessionId = 0; User = '' })
        $ev = @([pscustomobject]@{ Pid = 812; SessionId = $null; User = '' }, [pscustomobject]@{ Pid = 900; SessionId = $null; User = '' },
                [pscustomobject]@{ Pid = 4711; SessionId = $null; User = '' }, [pscustomobject]@{ Pid = 812; SessionId = 5; User = 'anders' })
        $r = @(Complete-WorkerPerfEventSession -Events $ev -Processes $procs -Sessions $sess)
        $r[0].SessionId | Should -Be 3; $r[0].User | Should -Be 'user002'; $r[1].SessionId | Should -Be 0; $r[1].User | Should -Be ''
        $r[2].SessionId | Should -BeNullOrEmpty; $r[3].SessionId | Should -Be 5; $r[3].User | Should -Be 'anders'
    }
    It 'ordnet keinem Prozess zu, der erst nach dem Ereignis gestartet ist (PID wiederverwendet)' {   # Review Focus 4
        $crash = $t.AddSeconds(10)
        $procs = @([pscustomobject]@{ ProcessId = 812; SessionId = 7; CreationDate = $t.AddSeconds(12) }, [pscustomobject]@{ ProcessId = 900; SessionId = 3; CreationDate = $t.AddHours(-1) })
        $sess = @([pscustomobject]@{ SessionId = 7; User = 'falsch' }, [pscustomobject]@{ SessionId = 3; User = 'user002' })
        $ev = @([pscustomobject]@{ Time = $crash; Pid = 812; SessionId = $null; User = '' }, [pscustomobject]@{ Time = $crash; Pid = 900; SessionId = $null; User = '' })
        $r = @(Complete-WorkerPerfEventSession -Events $ev -Processes $procs -Sessions $sess)
        $r[0].SessionId | Should -BeNullOrEmpty; $r[0].User | Should -Be ''
        $r[1].SessionId | Should -Be 3; $r[1].User | Should -Be 'user002'
    }
    It 'ergaenzt den Benutzer einer genannten Sitzung und uebersteht Datensaetze ohne Felder' {
        $sess = @([pscustomobject]@{ SessionId = 3; User = 'user002' })
        $ev = @([pscustomobject]@{ Pid = $null; SessionId = 3; User = '' }, [pscustomobject]@{ Time = $t; Source = 'Defender'; EventId = 1000; Kind = 'scan-start'; Text = '' })
        $r = @(Complete-WorkerPerfEventSession -Events $ev -Processes @() -Sessions $sess)
        $r.Count | Should -Be 2; $r[0].User | Should -Be 'user002'; $r[1].Kind | Should -Be 'scan-start'
        @(Complete-WorkerPerfEventSession -Events @() -Processes @() -Sessions @()).Count | Should -Be 0
    }
}
Describe 'Gedaechtnis der Prozesse und Fenster der Ereignisse (Fix-Runde 1)' {
    BeforeAll {
        function New-MemProc([int]$Id, [int]$Sid, [datetime]$Created) { [pscustomobject]@{ ProcessId = $Id; SessionId = $Sid; CreationDate = $Created } }
        $script:Old = $t.AddHours(-1)
        $script:Sess = @([pscustomobject]@{ SessionId = 3; User = 'user002' }, [pscustomobject]@{ SessionId = 4; User = 'user003' }, [pscustomobject]@{ SessionId = 7; User = 'user006' })
        function New-CrashEvent([double]$Sec, $ProcId = 812) { [pscustomobject]@{ Time = $t.AddSeconds($Sec); Pid = $ProcId; SessionId = $null; User = '' } }
    }
    It 'findet einen beendeten Prozess: Ende, dann Absturz nach 0, 1 und 14 s' {          # Important 1, Versuch des Reviews
        $mem = New-WorkerPerfProcessMemory
        Update-WorkerPerfProcessMemory -Memory $mem -Processes @((New-MemProc 812 3 $Old), (New-MemProc 900 4 $Old)) -Time $t
        Update-WorkerPerfProcessMemory -Memory $mem -Processes @((New-MemProc 812 3 $Old), (New-MemProc 900 4 $Old)) -Time $t.AddSeconds(15)
        # 812 endet bei 20 s; der Schnappschuss bei 30 s fuehrt ihn nicht mehr
        Update-WorkerPerfProcessMemory -Memory $mem -Processes @(New-MemProc 900 4 $Old) -Time $t.AddSeconds(30)
        $ev = @((New-CrashEvent 20), (New-CrashEvent 21), (New-CrashEvent 34))
        $r = @(Complete-WorkerPerfEventSession -Events $ev -Processes @(Get-WorkerPerfProcessMemoryEntries $mem) -Sessions $Sess -MaxGapSeconds 35)
        $r.SessionId | Should -Be @(3, 3, 3); $r.User | Should -Be @('user002', 'user002', 'user002')
    }
    It 'gibt einer wiederverwendeten PID den Prozess, der zur Zeit des Ereignisses lief' {
        $mem = New-WorkerPerfProcessMemory
        Update-WorkerPerfProcessMemory -Memory $mem -Processes @(New-MemProc 812 3 $Old) -Time $t.AddSeconds(15)
        Update-WorkerPerfProcessMemory -Memory $mem -Processes @(New-MemProc 812 7 $t.AddSeconds(40)) -Time $t.AddSeconds(45)
        $r = @(Complete-WorkerPerfEventSession -Events @((New-CrashEvent 38), (New-CrashEvent 46)) -Processes @(Get-WorkerPerfProcessMemoryEntries $mem) -Sessions $Sess -MaxGapSeconds 35)
        $r[0].SessionId | Should -Be 3; $r[1].SessionId | Should -Be 7; $r[1].User | Should -Be 'user006'
    }
    It 'nimmt bei einer Startzeit im Ereignis nur den Prozess mit dieser Startzeit (Task 10)' {
        # beide Prozesse lebten zur Zeit des Absturzes laut Gedaechtnis; die Startzeit des Ereignisses nennt den alten
        $mem = New-WorkerPerfProcessMemory
        Update-WorkerPerfProcessMemory -Memory $mem -Processes @(New-MemProc 812 3 $Old) -Time $t.AddSeconds(15)
        Update-WorkerPerfProcessMemory -Memory $mem -Processes @(New-MemProc 812 7 $t.AddSeconds(20)) -Time $t.AddSeconds(30)
        $e1 = New-CrashEvent 25; $e1 | Add-Member -NotePropertyName ProcessStart -NotePropertyValue $Old.ToUniversalTime().AddMilliseconds(0.4)
        $e2 = New-CrashEvent 25; $e2 | Add-Member -NotePropertyName ProcessStart -NotePropertyValue $t.AddSeconds(20).ToUniversalTime()
        $e3 = New-CrashEvent 25; $e3 | Add-Member -NotePropertyName ProcessStart -NotePropertyValue $null
        $e4 = New-CrashEvent 25; $e4 | Add-Member -NotePropertyName ProcessStart -NotePropertyValue $t.AddSeconds(5).ToUniversalTime()
        $r = @(Complete-WorkerPerfEventSession -Events @($e1, $e2, $e3, $e4) -Processes @(Get-WorkerPerfProcessMemoryEntries $mem) -Sessions $Sess -MaxGapSeconds 35)
        $r[0].SessionId | Should -Be 3; $r[0].User | Should -Be 'user002'
        $r[1].SessionId | Should -Be 7
        $r[2].SessionId | Should -Be 7                                                        # ohne Startzeit: der zuletzt gestartete
        $r[3].SessionId | Should -BeNullOrEmpty                                               # kein Prozess mit dieser Startzeit
    }
    It 'laesst ein Ereignis lange nach dem letzten Sehen und vor dem Start des Prozesses leer' {
        $mem = New-WorkerPerfProcessMemory
        Update-WorkerPerfProcessMemory -Memory $mem -Processes @(New-MemProc 812 3 $Old) -Time $t
        Update-WorkerPerfProcessMemory -Memory $mem -Processes @(New-MemProc 900 4 $t.AddSeconds(50)) -Time $t.AddSeconds(60)
        $r = @(Complete-WorkerPerfEventSession -Events @((New-CrashEvent 40), (New-CrashEvent 45 900)) -Processes @(Get-WorkerPerfProcessMemoryEntries $mem) -Sessions $Sess -MaxGapSeconds 35)
        $r[0].SessionId | Should -BeNullOrEmpty; $r[1].SessionId | Should -BeNullOrEmpty
    }
    It 'vergisst Prozesse 10 Minuten nach dem letzten Sehen und haelt die Zahl der Eintraege begrenzt' {
        $mem = New-WorkerPerfProcessMemory -MaxEntries 5
        Update-WorkerPerfProcessMemory -Memory $mem -Processes @(New-MemProc 1 3 $Old) -Time $t
        Update-WorkerPerfProcessMemory -Memory $mem -Processes @(New-MemProc 2 3 $Old) -Time $t.AddSeconds(599)
        @(Get-WorkerPerfProcessMemoryEntries $mem).Count | Should -Be 2
        # aufgeraeumt wird hoechstens einmal je Minute Serverzeit: bei 601 s noch nicht, bei 660 s
        Update-WorkerPerfProcessMemory -Memory $mem -Processes @(New-MemProc 3 3 $Old) -Time $t.AddSeconds(601)
        @(Get-WorkerPerfProcessMemoryEntries $mem).Count | Should -Be 3
        Update-WorkerPerfProcessMemory -Memory $mem -Processes @(New-MemProc 3 3 $Old) -Time $t.AddSeconds(660)
        @(Get-WorkerPerfProcessMemoryEntries $mem | ForEach-Object { $_.ProcessId } | Sort-Object) | Should -Be @(2, 3)
        Update-WorkerPerfProcessMemory -Memory $mem -Processes @(10..17 | ForEach-Object { New-MemProc $_ 3 $Old }) -Time $t.AddSeconds(661)
        $left = @(Get-WorkerPerfProcessMemoryEntries $mem); $left.Count | Should -Be 5
        @($left | Where-Object { $_.ProcessId -lt 10 }).Count | Should -Be 0                 # die zuletzt gesehenen bleiben
    }
    It 'behandelt eine PID oder Sitzung, die keine Zahl ist, als leer und wirft nicht' {      # Minor 6
        $mem = New-WorkerPerfProcessMemory
        Update-WorkerPerfProcessMemory -Memory $mem -Processes @((New-MemProc 812 3 $Old), [pscustomobject]@{ ProcessId = 'x'; SessionId = 'y'; CreationDate = $Old }) -Time $t
        $ev = @((New-CrashEvent 5 'bad'), [pscustomobject]@{ Time = $t; Pid = 812; SessionId = 'abc'; User = '' }, (New-CrashEvent 6))
        $r = @(Complete-WorkerPerfEventSession -Events $ev -Processes @(Get-WorkerPerfProcessMemoryEntries $mem) -Sessions $Sess -MaxGapSeconds 35)
        $r.Count | Should -Be 3; $r[0].SessionId | Should -BeNullOrEmpty; $r[1].SessionId | Should -Be 3; $r[2].User | Should -Be 'user002'
    }
    It 'waehlt Ereignisse im Fenster nach dem Zeiger bis zum Ende, je Grenze genau einmal' {    # Minor 3
        $ev = @(-1, 0, 1, 15, 16 | ForEach-Object { [pscustomobject]@{ Time = $t.AddSeconds($_); Text = "t$_" } })
        @(Select-WorkerPerfEventsInWindow -Events $ev -After $t -Until $t.AddSeconds(15)).Text | Should -Be @('t1', 't15')
        @(Select-WorkerPerfEventsInWindow -Events $ev -Until $t).Text | Should -Be @('t-1', 't0')
        @(Select-WorkerPerfEventsInWindow -Events @($null, [pscustomobject]@{ Time = 'x' }, [pscustomobject]@{ Text = 'ohne' }) -Until $t).Count | Should -Be 0
    }
    It 'vergleicht die Zeiten in UTC (Rechner in Europe/Berlin)' {                                # Minor 4
        $capture = (Resolve-Path (Join-Path $PSScriptRoot '../src/WorkerPerf.Capture.ps1')).Path; $common = (Resolve-Path (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1')).Path
        $code = ". '$common'; . '$capture'; `$s = [datetime]::SpecifyKind([datetime]'2026-01-15T08:00:00', 'Local'); " +
            "`$ev = @([pscustomobject]@{ Time = [datetime]::SpecifyKind([datetime]'2026-01-15T07:30:00', 'Utc'); Text = 'nach' }, [pscustomobject]@{ Time = [datetime]::SpecifyKind([datetime]'2026-01-15T06:59:00', 'Utc'); Text = 'vor' }); " +
            "(@(Select-WorkerPerfEventsInWindow -Events `$ev -Until `$s) | ForEach-Object { `$_.Text }) -join ','"
        $old = $env:TZ
        try { $env:TZ = 'Europe/Berlin'; $out = & (Get-Process -Id $PID).Path -NoProfile -Command $code }
        finally { $env:TZ = $old }
        $out | Should -Be 'vor'
    }
    It 'schreibt einen Zaehler, der keine Zahl ist, leer und behaelt die Zeile' {                 # Minor 5
        $q = [pscustomobject]@{ Queue = 'Drucker 1'; Jobs = 'abc'; JobErrors = '7'; NotReadyErrors = $null }
        ConvertTo-WorkerPerfPrintQueueRow $q $t | Should -Be ($t.ToString('o') + ',Drucker 1,,7,')
    }
}
Describe 'Zustandsbild schreiben' {
    It 'schreibt geschachtelte Werte vollstaendig, ueber eine temporaere Datei, und fasst das Lesen in einer Zeile zusammen' {
        $v = @{ 'profile.containers' = (New-WorkerPerfHealthValue 'read' '' @([ordered]@{ Location = '\\fs01\profile$\a.vhdx'; UsedPct = 96.5 })) }
        $h = New-WorkerPerfHealth ([datetime]::Now) 4210 @{ profile = (Complete-WorkerPerfHealthArea 'profile' $v 5) }
        $file = Join-Path $TestDrive 'health.json'; Save-WorkerPerfHealth -Path $file -Health $h; Save-WorkerPerfHealth -Path $file -Health $h
        $j = Get-Content $file -Raw | ConvertFrom-Json
        $j.Areas.profile.Values.'profile.containers'.Value[0].UsedPct | Should -Be 96.5; $j.Areas.profile.Values.'profile.containers'.Value[0].Location | Should -Be '\\fs01\profile$\a.vhdx'
        $j.Areas.profile.Values.'profile.containers'.Value -is [array] | Should -BeTrue                  # Review Task 8, Punkt 3: [0] traefe auch einen Einzelwert
        [IO.File]::ReadAllBytes($file)[0] | Should -Be ([byte][char]'{'); Test-Path ($file + '.tmp') | Should -BeFalse
        Format-WorkerPerfHealthLine $h | Should -Be 'Zustandsbild: 0 Bereiche gelesen, 11 unvollstaendig (size, operation, sessions, vda, profile, print, security, network, events, maintenance, apps), 4.2 s'
        $all = @{}; foreach ($a in $WorkerPerfHealthAreas) { $vals = @{}; foreach ($id in @($WorkerPerfHealthValues.Keys | Where-Object { $WorkerPerfHealthValues[$_].Area -eq $a })) { $vals[$id] = New-WorkerPerfHealthValue 'absent' }
            $all[$a] = Complete-WorkerPerfHealthArea $a $vals 1 }
        Format-WorkerPerfHealthLine (New-WorkerPerfHealth ([datetime]::Now) 0 $all) | Should -Be 'Zustandsbild: 11 Bereiche gelesen, 0.0 s'
    }
    It 'laesst nach einem gescheiterten Schreiben keine health.json.tmp zurueck' {                  # Review Task 8, Punkt 2
        $h = New-WorkerPerfHealth ([datetime]::Now) 10 @{}
        # ein Ordner mit dem Namen der Zieldatei: die Zwischendatei ist geschrieben, das Verschieben scheitert
        $dir = Join-Path $TestDrive 'blocked'; $file = Join-Path $dir 'health.json'; [void](New-Item -ItemType Directory -Path $file -Force)
        { Save-WorkerPerfHealth -Path $file -Health $h } | Should -Throw
        Test-Path ($file + '.tmp') | Should -BeFalse
        # ein Ordner mit dem Namen der Zwischendatei: schon das Schreiben scheitert, der Ordner bleibt unberuehrt
        $dir2 = Join-Path $TestDrive 'blocked2'; $file2 = Join-Path $dir2 'health.json'; [void](New-Item -ItemType Directory -Path ($file2 + '.tmp') -Force)
        { Save-WorkerPerfHealth -Path $file2 -Health $h } | Should -Throw
        Test-Path ($file2 + '.tmp') -PathType Container | Should -BeTrue; Test-Path $file2 | Should -BeFalse
    }
}
Describe 'New-WorkerPerfWriters -Only' {
    It 'legt nur die genannten Dateien an, ohne die weggelassener Kategorien' {
        $dir = Join-Path $TestDrive 'only'; [void](New-Item -ItemType Directory $dir)
        $w = New-WorkerPerfWriters -RunDir $dir -Skip @() -Only @('events_before.csv', 'printdrivers.csv'); foreach ($x in $w.Values) { $x.Dispose() }
        @($w.Keys | Sort-Object) | Should -Be @('events_before.csv', 'printdrivers.csv')
        @(Get-ChildItem $dir | ForEach-Object Name | Sort-Object) | Should -Be @('events_before.csv', 'printdrivers.csv')
        Get-Content (Join-Path $dir 'printdrivers.csv') -TotalCount 1 | Should -Be $WorkerPerfHeaders['printdrivers.csv']
        $dir2 = Join-Path $TestDrive 'only2'; [void](New-Item -ItemType Directory $dir2)
        $w = New-WorkerPerfWriters -RunDir $dir2 -Skip @('Rueckblick') -Only @('events_before.csv', 'printdrivers.csv'); foreach ($x in $w.Values) { $x.Dispose() }
        @(Get-ChildItem $dir2 | ForEach-Object Name) | Should -Be @('printdrivers.csv')
        $dir3 = Join-Path $TestDrive 'only3'; [void](New-Item -ItemType Directory $dir3)
        $w = New-WorkerPerfWriters -RunDir $dir3 -Skip @('Rueckblick', 'Drucken') -Only @('events_before.csv', 'printdrivers.csv')
        $w.Count | Should -Be 0; @(Get-ChildItem $dir3).Count | Should -Be 0
    }
}
