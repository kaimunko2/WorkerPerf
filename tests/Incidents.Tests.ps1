BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Findings.ps1')
    $script:T0 = 1700000000000
    function New-TestFinding([string]$Resource, [double]$StartSec, [double]$EndSec, [int]$Severity = 1, [int]$SessionIndex = -1, [string]$SignalId = '') {
        $scope = if ($Resource -in 'input', 'profile', 'network') { 'session' } else { 'global' }
        @{ SignalId = $(if ($SignalId) { $SignalId } else { "$Resource.test" }); Resource = $Resource; Instance = ''; Label = $Resource; Scope = $scope; SessionIndex = $SessionIndex
           StartMs = [long]($script:T0 + $StartSec * 1000); EndMs = [long]($script:T0 + $EndSec * 1000); Severity = $Severity; PeakValue = 1.0
           PeakTimeMs = [long]($script:T0 + $StartSec * 1000); BadPoints = 3 }
    }
    function Join-Test { , @(Join-WorkerPerfIncidents -Findings @($args)) }
}
Describe 'Join-WorkerPerfIncidents' {
    It 'fasst ueberlappende und nahe Befunde zusammen' {
        $i = Join-Test (New-TestFinding cpu 100 160) (New-TestFinding disk 165 200)
        $i.Count | Should -Be 1
        $i[0].StartMs | Should -Be ($T0 + 100000); $i[0].EndMs | Should -Be ($T0 + 200000)
        $i[0].Type | Should -Be 'engpass'; $i[0].Lead | Should -Be 'cpu'; $i[0].Resources | Should -Be @('cpu', 'disk'); $i[0].Id | Should -Be 1
    }
    It 'trennt bei mehr als 10 Sekunden Abstand' { (Join-Test (New-TestFinding cpu 100 160) (New-TestFinding disk 171 200)).Count | Should -Be 2 }
    It 'haelt einen Dauerzustand getrennt' {                                   # Review Focus 1
        $i = Join-Test (New-TestFinding memory 0 3600 -SignalId 'mem.used') (New-TestFinding cpu 600 660) (New-TestFinding input 1200 1202 -SessionIndex 3)
        $i.Count | Should -Be 3; @($i | Where-Object Chronic).Count | Should -Be 1
        $c = $i | Where-Object { $_.Lead -eq 'cpu' }
        $c.EndMs - $c.StartMs | Should -Be 60000
        $c.ChronicContext[0].SignalId | Should -Be 'mem.used'; $c.ChronicContext[0].Explains | Should -BeFalse
        @($i | Where-Object { $_.Type -eq 'ohne-engpass' }).Count | Should -Be 1     # ein auffaelliger Dauerzustand erklaert nichts
    }
    It 'laesst einen kritischen Dauerzustand als Erklaerung gelten' {
        $i = Join-Test (New-TestFinding cpu 0 2400 -Severity 2) (New-TestFinding input 1200 1202 -SessionIndex 3)
        $x = $i | Where-Object { -not $_.Chronic }
        $x.Type | Should -Be 'engpass'; $x.Lead | Should -Be 'cpu'; $x.ChronicContext[0].Explains | Should -BeTrue
    }
    It 'fuehrt gleichzeitige Verzoegerungen mehrerer Sitzungen zusammen' {
        $i = Join-Test (New-TestFinding input 100 104 -SessionIndex 1) (New-TestFinding input 102 110 -SessionIndex 2)
        $i.Count | Should -Be 1; $i[0].Type | Should -Be 'ohne-engpass'; $i[0].Lead | Should -BeNullOrEmpty; @($i[0].Resources).Count | Should -Be 0
    }
    It 'ordnet einen Profilcontainer nur der eigenen Sitzung zu' {
        $i = Join-Test (New-TestFinding input 100 110 -SessionIndex 1) (New-TestFinding profile 98 112 -SessionIndex 1) (New-TestFinding profile 100 110 -SessionIndex 7)
        $i.Count | Should -Be 2
        $own = $i | Where-Object { @($_.Findings | Where-Object { $_.Resource -eq 'input' }).Count -gt 0 }
        $own.Type | Should -Be 'engpass'; $own.Lead | Should -Be 'profile'; @($own.Findings).Count | Should -Be 2
        $own.StartMs | Should -Be ($T0 + 100000)                                # das Fenster folgt den Kernbefunden
        $other = $i | Where-Object { $_.Id -ne $own.Id }
        $other.Lead | Should -Be 'profile'; @($other.Findings).Count | Should -Be 1
    }
    It 'stuft reine Netz- und Gegenstellen-Befunde als Umfeld ein' {
        (Join-Test (New-TestFinding network 100 200 -SessionIndex 4))[0].Type | Should -Be 'umfeld'
        (Join-Test (New-TestFinding endpoint 100 200))[0].Type | Should -Be 'umfeld'
    }
    It 'nennt eine traege Gegenstelle, ohne sie als Engpass zu werten' {
        $i = Join-Test (New-TestFinding input 100 110 -SessionIndex 1) (New-TestFinding endpoint 95 130)
        $i.Count | Should -Be 1; $i[0].Type | Should -Be 'ohne-engpass'; $i[0].Resources | Should -Be @('endpoint')
    }
    It 'liefert ohne Befunde nichts' { @(Join-WorkerPerfIncidents -Findings @()).Count | Should -Be 0 }
}
