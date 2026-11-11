BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Findings.ps1')
    $script:Th = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json')
    $script:T0 = 1700000000000
    function New-TestSeries([string]$Id, [double[]]$Values, [int]$StepSec = 2, [double[]]$Ops = $null) {
        $n = $Values.Length
        @{ Id = $Id; Instance = ''; Label = $Id; Resource = 'cpu'; Scope = 'global'; SessionIndex = -1
           TimeMs = [long[]](0..($n - 1) | ForEach-Object { $script:T0 + $_ * $StepSec * 1000 })
           ElapsedSec = [double[]](1..$n | ForEach-Object { $StepSec }); Value = $Values; Ops = $Ops }
    }
    function Get-Found($Series) { , @(Get-WorkerPerfFindings -Series @($Series) -Thresholds $Th) }      # Komma: das Array bleibt auch mit 0 oder 1 Befund erhalten
}
Describe 'Get-WorkerPerfFindings' {
    It 'meldet nichts unter minTicks' { (Get-Found (New-TestSeries 'cpu.host' 50,80,80,50)).Count | Should -Be 0 }
    It 'bildet einen Befund ab drei Messpunkten' {
        $f = Get-Found (New-TestSeries 'cpu.host' 50,80,95,80,50)
        $f.Count | Should -Be 1
        $f[0].StartMs | Should -Be $T0                  # der erste auffaellige Punkt deckt die 2 s davor ab
        $f[0].EndMs | Should -Be ($T0 + 6000)
        $f[0].Severity | Should -Be 2; $f[0].PeakValue | Should -Be 95; $f[0].BadPoints | Should -Be 3
    }
    It 'ueberbrueckt Luecken bis 10 Sekunden' {         # auffaellig bei 0, 2 und 12 s
        $f = Get-Found (New-TestSeries 'cpu.host' 80,80,50,50,50,50,80)
        $f.Count | Should -Be 1; $f[0].BadPoints | Should -Be 3
    }
    It 'trennt bei Luecken ueber 10 Sekunden' { (Get-Found (New-TestSeries 'cpu.host' 80,80,80,50,50,50,50,50,50,80,80,80)).Count | Should -Be 2 }
    It 'wertet aufeinanderfolgende Punkte eines langsamen Takts' { (Get-Found (New-TestSeries 'ica.rtt' 200,200,200 -StepSec 15)).Count | Should -Be 1 }
    It 'wertet einen einzelnen Haenger der Eingabeverzoegerung' {
        $f = Get-Found (New-TestSeries 'input.session' 0,0,800,0)
        $f.Count | Should -Be 1; $f[0].Severity | Should -Be 2
    }
    It 'bewertet Antwortzeiten erst ab minOps Zugriffen' {                      # Review Focus 5
        (Get-Found (New-TestSeries 'disk.latency' 80,80,80,80 -Ops 1,2,1,0)).Count | Should -Be 0
        (Get-Found (New-TestSeries 'disk.latency' 80,80,80,80 -Ops 50,50,50,50)).Count | Should -Be 1
    }
    It 'behandelt fehlende Werte als unauffaellig' {
        $nan = [double]::NaN
        (Get-Found (New-TestSeries 'cpu.host' 80,$nan,80,$nan,80)).Count | Should -Be 1
        (Get-Found (New-TestSeries 'cpu.host' $nan,$nan,$nan)).Count | Should -Be 0
    }
    It 'wertet einen Verbindungsfehler als kritisch' {
        $inf = [double]::PositiveInfinity
        (Get-Found (New-TestSeries 'probe.connect' $inf,$inf,$inf -StepSec 15))[0].Severity | Should -Be 2
    }
    It 'uebergeht Reihen ohne Schwellwert' { (Get-Found (New-TestSeries 'unbekannt.x' 999,999,999)).Count | Should -Be 0 }
}
Describe 'Get-WorkerPerfSollIst' {
    It 'bewertet einen Messwert gegen das Soll' {
        $r = Get-WorkerPerfSollIst -Series @(New-TestSeries 'cpu.host' 50,80,95,80,50) -Thresholds $Th | Where-Object Id -eq 'cpu.host'
        $r.Measured | Should -BeTrue; $r.Avg | Should -Be 71; $r.Max | Should -Be 95
        $r.PctNormal | Should -Be 40; $r.PctWarn | Should -Be 40; $r.PctCrit | Should -Be 20
    }
    It 'weist fehlende Messwerte als nicht gemessen aus und nennt den Grund' {
        $all = @(Get-WorkerPerfSollIst -Series @() -Thresholds $Th -Sources @{ 'cpu.steal' = @{ Available = $false; Detail = 'VM Processor fehlt' } })
        $all.Count | Should -Be 12; @($all | Where-Object Measured).Count | Should -Be 0
        ($all | Where-Object Id -eq 'cpu.steal').Detail | Should -Be 'VM Processor fehlt'
    }
    It 'nimmt bei mehreren Instanzen je Messpunkt die schlechteste' {
        $a = New-TestSeries 'disk.latency' 2,30,2 -Ops 50,50,50; $a.Label = 'Laufwerk C:'
        $b = New-TestSeries 'disk.latency' 4,4,15 -Ops 50,50,50; $b.Label = 'Laufwerk D:'
        $r = Get-WorkerPerfSollIst -Series @($a, $b) -Thresholds $Th | Where-Object Id -eq 'disk.latency'
        $r.Max | Should -Be 30; [Math]::Round($r.PctNormal) | Should -Be 33; $r.WorstInstance | Should -Be 'Laufwerk C:'
    }
    It 'waehlt die schlechteste Instanz bei Gleichstand nach dem Maximum, dann nach der Bezeichnung' {   # Task 14b, Punkt 5
        $quiet = foreach ($x in @(@('I1', 2), @('I2', 3), @('I3', 4), @('I4', 9), @('I5', 5), @('I6', 1))) {          # kein auffaelliger Punkt
            $s = New-TestSeries 'disk.latency' 1, $x[1], 1 -Ops 50,50,50; $s.Label = $x[0]; $s }
        (Get-WorkerPerfSollIst -Series @($quiet) -Thresholds $Th | Where-Object Id -eq 'disk.latency').WorstInstance | Should -Be 'I4'
        $tie = foreach ($l in 'b', 'c', 'a', 'D', 'e', 'F') {                                # voller Gleichstand; ordinal steht 'D' vor 'a'
            $s = New-TestSeries 'disk.latency' 1, 30, 1 -Ops 50,50,50; $s.Label = $l; $s }
        (Get-WorkerPerfSollIst -Series @($tie) -Thresholds $Th | Where-Object Id -eq 'disk.latency').WorstInstance | Should -BeExactly 'D'
        $more = @($tie) + @(& { $s = New-TestSeries 'disk.latency' 12, 1, 1 -Ops 50,50,50; $s.Label = 'z'; $s })     # mehr auffaellige Punkte gehen vor
        $more[6].Value = [double[]](12, 12, 1)
        (Get-WorkerPerfSollIst -Series $more -Thresholds $Th | Where-Object Id -eq 'disk.latency').WorstInstance | Should -Be 'z'
    }
    It 'leitet die Bewertung aus den Befunden ab und kennzeichnet einzelne Ueberschreitungen' {   # Abschlussrunde I4
        $spike = New-TestSeries 'cpu.host' 50,96,93,50,50                               # zwei kritische Punkte, unter minTicks
        $r = Get-WorkerPerfSollIst -Series @($spike) -Thresholds $Th -Findings (Get-Found $spike) | Where-Object Id -eq 'cpu.host'
        $r.Status | Should -Be 0; $r.Exceeded | Should -BeTrue; $r.PctCrit | Should -Be 40
        $long = New-TestSeries 'cpu.host' 50,80,95,80,50
        $r = Get-WorkerPerfSollIst -Series @($long) -Thresholds $Th -Findings (Get-Found $long) | Where-Object Id -eq 'cpu.host'
        $r.Status | Should -Be 2; $r.Exceeded | Should -BeTrue
        $quiet = New-TestSeries 'cpu.host' 50,50,50
        $r = Get-WorkerPerfSollIst -Series @($quiet) -Thresholds $Th -Findings (Get-Found $quiet) | Where-Object Id -eq 'cpu.host'
        $r.Status | Should -Be 0; $r.Exceeded | Should -BeFalse
    }
    It 'nimmt bei mehreren Instanzen die schlechteste Bewertung der Befunde' {
        $a = New-TestSeries 'disk.latency' 12,12,12,2 -Ops 50,50,50,50; $a.Label = 'Laufwerk C:'; $a.Instance = 'C:'
        $b = New-TestSeries 'disk.latency' 30,30,30,2 -Ops 50,50,50,50; $b.Label = 'Laufwerk D:'; $b.Instance = 'D:'
        $r = Get-WorkerPerfSollIst -Series @($a, $b) -Thresholds $Th -Findings (Get-Found @($a, $b)) | Where-Object Id -eq 'disk.latency'
        $r.Status | Should -Be 2
        $r = Get-WorkerPerfSollIst -Series @($a, $b) -Thresholds $Th -Findings (Get-Found @($a)) | Where-Object Id -eq 'disk.latency'
        $r.Status | Should -Be 1
    }
}
