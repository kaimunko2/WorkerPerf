BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Sizing.ps1')
    $script:SizingFile = Join-Path $PSScriptRoot '../src/sizing.de.json'
    $script:Th = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json')
    $script:BadNo = 0
    function New-BadCatalogue([scriptblock]$Change) {
        # eine Kopie des Katalogs mit einer Aenderung; $Change sieht den Katalog als $j
        $j = [IO.File]::ReadAllText($script:SizingFile, [Text.Encoding]::UTF8) | ConvertFrom-Json
        . $Change
        $script:BadNo++
        $p = Join-Path $TestDrive ("bad{0}.json" -f $script:BadNo)
        [IO.File]::WriteAllText($p, ($j | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding $false))
        $p
    }
}
Describe 'Read-WorkerPerfSizing' {
    It 'liest den Katalog mit Klassen in der Reihenfolge des Vorrangs' {
        $c = Read-WorkerPerfSizing (Join-Path $PSScriptRoot '../src/sizing.de.json') $Th
        @($c.Classes.Keys) | Should -Be $WorkerPerfSizingClassOrder
        $c.Classes['host'].Label | Should -Be 'VMware-Host'; $c.Classes['singlecore'].Label | Should -Be 'Leistung je Kern'
        $c.Classes['host'].Kind | Should -Be 'vendor'; $c.Classes['host'].Sources | Should -Be @('SZ-21', 'SZ-20', 'SZ-26', 'VM-08')
        $c.Classes['app'].Kind | Should -Be 'rule'; $c.Levels.clear | Should -Be 'deutlich'; $c.Levels.tight | Should -Be 'knapp'
    }
    It 'fuehrt die eigenen Werte des Entwurfs' {
        $t = (Read-WorkerPerfSizing (Join-Path $PSScriptRoot '../src/sizing.de.json') $Th).Thresholds
        $t.coreBusyPct.Value | Should -Be 90; $t.appSharePct.Value | Should -Be 50; $t.recurringPct.Value | Should -Be 50
        $t.minRecordings.Value | Should -Be 3; $t.minMainHours.Value | Should -Be 12; $t.mainSessionPct.Value | Should -Be 50
        $t.scalingLow.Value | Should -Be 1.5; $t.scalingHigh.Value | Should -Be 1.9; $t.vcpuScaleOut.Value | Should -Be 16; $t.vcpuMax.Value | Should -Be 24
        $t.memTargetPct.Value | Should -Be 80; $t.memStepGB.Value | Should -Be 4
        $t.sustainedPct.Value | Should -Be 80; $t.pagesOutLowPerSec.Value | Should -Be 10; $t.pagesOutSharePct.Value | Should -Be 50
        $t.singleCoreMaxCores.Value | Should -Be 1.2; $t.leakGrowthPct.Value | Should -Be 10
        $t.scalingLow.Kind | Should -Be 'vendor'; $t.scalingLow.Sources | Should -Be @('SZ-42'); $t.coreBusyPct.Kind | Should -Be 'rule'
    }
    It 'nimmt die Schwellen von cpu.host, cpu.queue, cpu.steal und mem.commit aus thresholds.json' {
        $l = (Read-WorkerPerfSizing (Join-Path $PSScriptRoot '../src/sizing.de.json') $Th).Limits
        $l.target.Value | Should -Be 75; $l.cpuCrit.Value | Should -Be 90; $l.queueWarn.Value | Should -Be 2; $l.stealWarn.Value | Should -Be 5; $l.commitCrit.Value | Should -Be 90
        $th2 = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json'); $th2['cpu.host'].warn = 70
        (Read-WorkerPerfSizing (Join-Path $PSScriptRoot '../src/sizing.de.json') $th2).Limits.target.Value | Should -Be 70
    }
    It 'fuehrt die Nutzerklassen von Microsoft' {
        $u = (Read-WorkerPerfSizing (Join-Path $PSScriptRoot '../src/sizing.de.json') $Th).Users
        @($u.light.PerVcpu, $u.medium.PerVcpu, $u.heavy.PerVcpu, $u.power.PerVcpu) | Should -Be @(6, 4, 2, 1)
    }
    It 'fuehrt jede Quelle mit Titel, Adresse und Datum der Recherche' {
        $s = (Read-WorkerPerfSizing (Join-Path $PSScriptRoot '../src/sizing.de.json') $Th).Sources
        $s['SZ-42'].Url | Should -Be 'https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/session-host-virtual-machine-sizing-guidelines'
        $s['SZ-42'].Date | Should -Be '2025-07-23'; $s['SZ-21'].Url | Should -Be 'https://knowledge.broadcom.com/external/article/438023'; $s['ST-02'].Kind | Should -Be 'practice'
        $doc = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../docs/guidance/quellen.md'))
        foreach ($id in $s.Keys) { $doc.Contains($id) | Should -BeTrue -Because $id; $doc.Contains($s[$id].Url) | Should -BeTrue -Because $id }
    }
    It 'lehnt einen fehlerhaften Katalog mit Teil und Feld ab: <Name>' -TestCases @(
        @{ Name = 'eigene Schwelle mit Kennung aus thresholds.json'; Change = { $j.thresholds | Add-Member 'cpu.host' ([pscustomobject]@{ value = 80; default = 80; unit = '%'; label = 'x'; kind = 'rule'; sources = @() }) }; Message = '*thresholds cpu.host*' }
        @{ Name = 'Klassen in anderer Reihenfolge'; Change = { $j.classes = @($j.classes[1], $j.classes[0]) + @($j.classes | Select-Object -Skip 2) }; Message = '*classes*Reihenfolge*' }
        @{ Name = 'Herstellerangabe ohne Quelle'; Change = { ($j.classes | Where-Object id -eq 'host').sources = @() }; Message = '*classes host: sources*' }
        @{ Name = 'unbekannte Quelle'; Change = { ($j.classes | Where-Object id -eq 'host').sources = @('SZ-99') }; Message = '*SZ-99*' }
        @{ Name = 'Quelle ohne Adresse'; Change = { $j.sources.'SZ-42'.url = '' }; Message = '*sources SZ-42: url*' }
        @{ Name = 'unbekannte Art'; Change = { ($j.classes | Where-Object id -eq 'app').kind = 'hersteller' }; Message = '*classes app: kind*' }
        @{ Name = 'unbekannter Platzhalter'; Change = { ($j.classes | Where-Object id -eq 'host').reason = 'x {cpu}' }; Message = '*classes host: reason*{cpu}*' }
        @{ Name = 'Kern-Schwelle ausserhalb 50 bis 100'; Change = { $j.thresholds.coreBusyPct.value = 40 }; Message = '*thresholds coreBusyPct: value*' }
        @{ Name = 'Verweis auf ein Signal, das thresholds.json nicht kennt'; Change = { $j.limits.target.signal = 'cpu.unbekannt' }; Message = '*limits target: signal*' }
        @{ Name = 'unbekanntes Mitglied'; Change = { $j | Add-Member 'extra' 1 }; Message = '*extra*unbekannt*' }
        @{ Name = 'fehlende Vorlage'; Change = { $j.texts.PSObject.Properties.Remove('pilot') }; Message = '*texts pilot*fehlt*' }
        @{ Name = 'Skalierung vertauscht'; Change = { $j.thresholds.scalingLow.value = 1.95 }; Message = '*thresholds scalingLow: value*' }
    ) { { Read-WorkerPerfSizing (New-BadCatalogue $Change) $Th } | Should -Throw $Message }
}
