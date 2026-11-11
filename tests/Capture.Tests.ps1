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
