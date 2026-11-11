BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Sources.Simulation.ps1')
    $script:Start = [datetime]'2026-01-15T08:00:00'
    $script:Info = Initialize-WorkerPerfSource -StartTime $Start
    function Set-SimTime([double]$Minutes) { [void](Wait-WorkerPerfTick -Until $Start.AddMinutes($Minutes) -StopFlagPath '') }
    function Get-SimProcess([string]$Name, [int]$SessionId) { , @((Get-WorkerPerfSnapshot).Processes | Where-Object { $_.Name -eq $Name -and ($SessionId -lt 0 -or $_.SessionId -eq $SessionId) }) }
    function Get-CpuSec($p) { ([double]$p.UserModeTime + [double]$p.KernelModeTime) / 1e7 }
}
Describe 'Simulation' {
    It 'meldet die festen Eckdaten' {
        $Info.Computer | Should -Be 'SIM-VDA01'; $Info.LogicalProcessors | Should -Be 8; $Info.PhysicalMemoryMB | Should -Be 65536; $Info.CollectorPid | Should -Be 4242
        @($Info.Endpoints).Name | Should -Be @('Oracle-Listener', 'FortiGate-Proxy', 'Dateiserver')
        @($Info.Sources.Values | Where-Object { -not $_.Available }).Count | Should -Be 0
    }
    It 'liefert zu gleicher Zeit gleiche Werte, auch nach Spruengen der Uhr' {
        Set-SimTime 6; $a = (Get-WorkerPerfFastSample).CpuPct
        Set-SimTime 30; Set-SimTime 6; (Get-WorkerPerfFastSample).CpuPct | Should -Be $a
        Get-WorkerPerfNow | Should -Be $Start.AddMinutes(6)
    }
    It 'bleibt in ruhigen Phasen unter allen Schwellen' {
        foreach ($m in 10, 11.5, 13, 22, 44, 57) {
            Set-SimTime $m; $f = Get-WorkerPerfFastSample
            $f.CpuPct | Should -BeLessThan 75; (1 - $f.MemAvailMB / 65536) * 100 | Should -BeLessThan 75
            $f.ProcQueue | Should -BeLessThan 16; $f.PagesInPerSec | Should -BeLessThan 10
            @($f.InputSessions | Where-Object { $_.DelayMs -ge 150 }).Count | Should -Be 0
            @($f.Volumes | Where-Object { $_.ReadLatMs -ge 10 -or $_.WriteLatMs -ge 10 }).Count | Should -Be 0
            @($f.Shares | Where-Object { $_.ReadLatMs -ge 10 -or $_.WriteLatMs -ge 10 }).Count | Should -Be 0
        }
    }
    It 'spielt den CPU-Engpass' {
        Set-SimTime 6; $f = Get-WorkerPerfFastSample
        $f.CpuPct | Should -BeGreaterOrEqual 90
        @($f.InputSessions | Where-Object { $_.DelayMs -ge 150 }).SessionId | Sort-Object | Should -Be @(2, 3, 4, 5, 6, 7)
        Set-SimTime 5; $a = Get-CpuSec (Get-SimProcess 'EXCEL.EXE' 4)[0]
        Set-SimTime 7; (Get-CpuSec (Get-SimProcess 'EXCEL.EXE' 4)[0]) - $a | Should -BeGreaterThan 560     # 60 % von 8 Kernen ueber 120 s
    }
    It 'laesst robocopy nur im Datentraeger-Fenster laufen' {
        Set-SimTime 24.75; (Get-SimProcess 'robocopy.exe' -1).Count | Should -Be 0
        Set-SimTime 25.5; $p = Get-SimProcess 'robocopy.exe' -1; $p.Count | Should -Be 1; $p[0].SessionId | Should -Be 12
        Set-SimTime 27; (Get-SimProcess 'robocopy.exe' -1).Count | Should -Be 0
    }
    It 'haelt die Mehrheit der Prozesse in Ruhe' {
        Set-SimTime 10; $a = @{}; foreach ($p in (Get-WorkerPerfSnapshot).Processes) { $a[$p.ProcessId] = $p }
        Set-SimTime 10.25; $b = @((Get-WorkerPerfSnapshot).Processes)
        $idle = @($b | Where-Object { $a.ContainsKey($_.ProcessId) -and (Get-CpuSec $_) -eq (Get-CpuSec $a[$_.ProcessId]) -and $_.ReadTransferCount -eq $a[$_.ProcessId].ReadTransferCount })
        $idle.Count | Should -BeGreaterThan ($b.Count / 2)
    }
    It 'kennzeichnet Profilcontainer und Dienste' {
        Set-SimTime 40.5; $v = (Get-WorkerPerfFastSample).Volumes | Where-Object Volume -eq 'HarddiskVolume18'
        $v.Kind | Should -Be 'profile'; $v.SessionId | Should -Be 10; $v.Backing | Should -Be '\\fs01\profile$'
        (Get-WorkerPerfServices).Values | Should -Contain 'AppIDSvc'
    }
    It 'meldet Proben erst im naechsten Takt' {
        Set-SimTime 47.5; Start-WorkerPerfProbes; Receive-WorkerPerfProbes | Should -BeNullOrEmpty
        Set-SimTime (47.5 + 2 / 60); $r = @(Receive-WorkerPerfProbes)
        $r.Count | Should -Be 3; ($r | Where-Object Name -eq 'Oracle-Listener').ConnectMs | Should -BeGreaterOrEqual 200
    }
    It 'liefert Ereignisse seit einem Zeitpunkt' {
        Set-SimTime 31; @(Get-WorkerPerfEvents -Since $Start).Kind | Should -Be @('scan-start', 'scan-end', 'applocker-block')
        @(Get-WorkerPerfEvents -Since $Start.AddMinutes(28)).Kind | Should -Be @('applocker-block')
    }
    It 'beschreibt das Soll-Ergebnis' {
        $e = @(Get-WorkerPerfExpected)
        $e.Key | Should -Be @('homeoffice', 'cpu', 'memory', 'disk', 'share', 'profile', 'backend', 'hang')
        $cpu = $e | Where-Object Key -eq 'cpu'
        $cpu.MainUser | Should -Be 'user003'; $cpu.EndMs - $cpu.StartMs | Should -Be 120000; $cpu.Affected | Should -Be 6
        @($e | Where-Object Chronic).Count | Should -Be 1
    }
}
