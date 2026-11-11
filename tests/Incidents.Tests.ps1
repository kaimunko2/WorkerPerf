BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Findings.ps1')
    $script:T0 = 1700000000000
    function New-TestFinding([string]$Resource, [double]$StartSec, [double]$EndSec, [int]$Severity = 1, [int]$SessionIndex = -1, [string]$SignalId = '', [string]$Instance = '') {
        $scope = if ($Resource -in 'input', 'profile', 'network') { 'session' } else { 'global' }
        @{ SignalId = $(if ($SignalId) { $SignalId } else { "$Resource.test" }); Resource = $Resource; Instance = $Instance; Label = $Resource; Scope = $scope; SessionIndex = $SessionIndex
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
        $x.Type | Should -Be 'engpass'; $x.Lead | Should -Be 'cpu'; $x.ChronicContext[0].Explains | Should -BeTrue; $x.ChronicContext[0].Resource | Should -Be 'cpu'
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
    It 'nennt einen Dauerzustand einer Sitzung nur bei Vorfaellen derselben Sitzung' {     # Task 14b, Punkt 2
        $net = { New-TestFinding network 0 3600 -SessionIndex 4 -SignalId 'ica.rtt' }
        $own = (Join-Test (& $net) (New-TestFinding input 1200 1202 -SessionIndex 4)) | Where-Object { -not $_.Chronic }
        @($own.ChronicContext).Count | Should -Be 1; $own.ChronicContext[0].SignalId | Should -Be 'ica.rtt'
        $other = (Join-Test (& $net) (New-TestFinding input 1200 1202 -SessionIndex 5)) | Where-Object { -not $_.Chronic }
        @($other.ChronicContext).Count | Should -Be 0
        $cpu = (Join-Test (& $net) (New-TestFinding cpu 1200 1260)) | Where-Object { -not $_.Chronic }
        @($cpu.ChronicContext).Count | Should -Be 0
    }
    It 'nennt einen globalen Dauerzustand bei allen ueberschneidenden Vorfaellen' {
        $i = Join-Test (New-TestFinding memory 0 3600 -SignalId 'mem.used') (New-TestFinding input 1200 1202 -SessionIndex 5) (New-TestFinding cpu 1800 1860) (New-TestFinding network 600 700 -SessionIndex 4)
        $short = @($i | Where-Object { -not $_.Chronic }); $short.Count | Should -Be 3
        foreach ($x in $short) { @($x.ChronicContext).Count | Should -Be 1; $x.ChronicContext[0].SignalId | Should -Be 'mem.used' }
    }
    It 'typisiert einen Dauerzustand nur aus den eigenen Befunden' {                    # Task 14b, Punkt 3
        $i = Join-Test (New-TestFinding network 0 3600 -SessionIndex 4 -SignalId 'ica.rtt') (New-TestFinding cpu 0 2400 -Severity 2 -SignalId 'cpu.host')
        $net = $i | Where-Object { $_.Findings[0].Resource -eq 'network' }; $cpu = $i | Where-Object { $_.Findings[0].Resource -eq 'cpu' }
        $net.Type | Should -Be 'umfeld'; $net.Lead | Should -BeNullOrEmpty
        @($net.ChronicContext).Count | Should -Be 1; $net.ChronicContext[0].SignalId | Should -Be 'cpu.host'; $net.ChronicContext[0].Explains | Should -BeFalse
        $cpu.Type | Should -Be 'engpass'; $cpu.Lead | Should -Be 'cpu'; @($cpu.ChronicContext).Count | Should -Be 0
    }
    It 'gruppiert Befunde ohne bekannte Sitzung je Instanz' {                          # Task 14b, Punkt 4
        $i = Join-Test (New-TestFinding profile 100 110 -Instance 'HarddiskVolume7') (New-TestFinding profile 100 110 -Instance 'HarddiskVolume8')
        $i.Count | Should -Be 2
        foreach ($x in $i) { @($x.Findings).Count | Should -Be 1 }
    }
    It 'haengt einen Befund ohne bekannte Sitzung an keine Eingabeverzoegerung' {
        $i = Join-Test (New-TestFinding input 100 110) (New-TestFinding profile 98 112 -Instance 'HarddiskVolume7')
        $in = $i | Where-Object { @($_.Findings | Where-Object { $_.Resource -eq 'input' }).Count -gt 0 }
        @($in.Findings | Where-Object { $_.Resource -eq 'profile' }).Count | Should -Be 0
        $i.Count | Should -Be 2
    }
    It 'liefert ohne Befunde nichts' { @(Join-WorkerPerfIncidents -Findings @()).Count | Should -Be 0 }
}
