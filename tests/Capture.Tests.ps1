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
