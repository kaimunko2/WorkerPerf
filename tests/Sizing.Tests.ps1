BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.EventConfig.ps1')
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Events.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Load.ps1')
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Findings.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Sizing.ps1')
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:SizingFile = Join-Path $PSScriptRoot '../src/sizing.de.json'
    $script:Th = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json')
    $script:Sz = Read-WorkerPerfSizing $SizingFile $Th
    function Merge([hashtable]$A, [hashtable]$B) { $c = $A.Clone(); foreach ($k in $B.Keys) { $c[$k] = $B[$k] }; $c }
    function New-Facts([hashtable]$Change) {
        # Fakten eines ruhigen CPU-Vorfalls auf 8 vCPU, mit den genannten Aenderungen
        Merge @{ Cpu = $true; Memory = $false; Delay = $false; MinTicks = @{ 'cpu.steal' = 3; 'cpu.host' = 3; 'mem.commit' = 3 }
            StealMeasured = $true; StealTicks = 0; StealMax = 0.0; CpuP95 = 50.0; CpuMax = 50.0; OverTargetTicks = 0; ClearTicks = 0; QueueMax = 0.0
            CoreMaxMeasured = $true; CoreMaxHighPct = 0.0; CoreMaxP95 = 60.0; Processes = $true
            TopProcess = @{ Name = 'quiet.exe'; Cores = 0.2; BandPct = 0 }; TopApp = $null; Scan = $false
            PagesOutMeasured = $true; PagesOutPct = 0.0; PagesOutMax = 0.0; CommitOverRamTicks = 0; CommitCritTicks = 0; CommitMax = 50.0; CommittedMaxMB = 40000.0
            RamMB = 65536.0; MemTop = $null; UsedMax = 60.0 } $Change
    }
    function Classes-Of($Facts) { @((Get-WorkerPerfIncidentClasses $Facts $Sz).Classes | ForEach-Object { $_.Id }) }
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
Describe 'Get-WorkerPerfPercentile' {
    It 'nimmt den naechsten Rang und uebergeht NaN' {
        Get-WorkerPerfPercentile ([double[]]@(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)) 95 | Should -Be 10
        Get-WorkerPerfPercentile ([double[]]@(5, 1, [double]::NaN, 3)) 50 | Should -Be 3
        Get-WorkerPerfPercentile ([double[]]@(7)) 95 | Should -Be 7
        [double]::IsNaN((Get-WorkerPerfPercentile ([double[]]@()) 95)) | Should -BeTrue
    }
}
Describe 'Get-WorkerPerfIncidentClasses: Grenzen' {
    It 'VMware-Host ab drei Takten ueber auffaellig' {
        Classes-Of (New-Facts @{ StealTicks = 3; StealMax = 5.0 }) | Should -Contain 'host'
        Classes-Of (New-Facts @{ StealTicks = 2; StealMax = 9.0 }) | Should -Not -Contain 'host'
        (Get-WorkerPerfIncidentClasses (New-Facts @{ StealMeasured = $false }) $Sz).Unchecked.Id | Should -Contain 'host'
    }
    It 'Leistung je Kern: ein Kern voll, die CPU unter kritisch' {
        $f = @{ Delay = $true; Cpu = $false; TopProcess = @{ Name = 'simcalc.exe'; Cores = 1.0; BandPct = 80 }; CoreMaxHighPct = 80; CpuP95 = 89.9 }
        Classes-Of (New-Facts $f) | Should -Be @('singlecore')
        Classes-Of (New-Facts (Merge $f @{ CpuP95 = 90 })) | Should -BeNullOrEmpty
        Classes-Of (New-Facts (Merge $f @{ TopProcess = @{ Name = 'simcalc.exe'; Cores = 1.0; BandPct = 79.9 } })) | Should -BeNullOrEmpty
        Classes-Of (New-Facts (Merge $f @{ TopProcess = @{ Name = 'simcalc.exe'; Cores = 1.3; BandPct = 0 } })) | Should -BeNullOrEmpty     # mehr als 1,2 Kerne: kein Einzelkern
    }
    It 'Leistung je Kern ohne staerksten Kern: nicht entscheidbar' {                    # Review Focus 1
        $r = Get-WorkerPerfIncidentClasses (New-Facts @{ Delay = $true; Cpu = $false; TopProcess = @{ Name = 'simcalc.exe'; Cores = 1.0; BandPct = 100 }; CoreMaxMeasured = $false }) $Sz
        @($r.Classes.Id) | Should -Be @('undecidable'); $r.Unchecked[0].Id | Should -Be 'singlecore'; $r.Unchecked[0].Missing | Should -Be @('cpu.coreMax')
    }
    It 'Prozess bei einem Kern, der staerkste Kern aber frei: Widerspruch' {
        $r = Get-WorkerPerfIncidentClasses (New-Facts @{ Delay = $true; Cpu = $false; TopProcess = @{ Name = 'a.exe'; Cores = 1.0; BandPct = 100 }; CoreMaxHighPct = 10 }) $Sz
        $r.Unchecked[0].Id | Should -Be 'singlecore'; @($r.Unchecked[0].Missing).Count | Should -Be 0
        (Get-WorkerPerfClassOut @{ Classes = $r.Classes; Unchecked = $r.Unchecked } $Sz).Line | Should -Match 'widersprechen sich'
    }
    It 'Anwendung ab 50 % der genutzten CPU, sonst Kapazitaet' {
        $f = @{ OverTargetTicks = 3; TopApp = @{ App = 'EXCEL.EXE'; Role = ''; RoleLabel = ''; SharePct = 50.0 } }
        Classes-Of (New-Facts $f) | Should -Be @('app')
        Classes-Of (New-Facts (Merge $f @{ TopApp = @{ App = 'EXCEL.EXE'; Role = ''; RoleLabel = ''; SharePct = 49.9 } })) | Should -Be @('capacity')
    }
    It 'Einmalig bei Scan oder Wartung, nicht zugleich Anwendung' {
        $scan = @{ OverTargetTicks = 3; Scan = $true; TopApp = @{ App = 'MsMpEng.exe'; Role = 'Sicherheit'; RoleLabel = 'Microsoft Defender'; SharePct = 70 } }
        Classes-Of (New-Facts $scan) | Should -Be @('oneoff')
        Classes-Of (New-Facts (Merge $scan @{ Scan = $false })) | Should -Be @('app')
        Classes-Of (New-Facts @{ OverTargetTicks = 3; TopApp = @{ App = 'TiWorker.exe'; Role = 'Wartung'; RoleLabel = 'Windows Update'; SharePct = 12 } }) | Should -Be @('oneoff')
    }
    It 'Kapazitaet deutlich ab Warteschlange 2 je CPU bei CPU ab 90 %, sonst knapp' {
        ((Get-WorkerPerfIncidentClasses (New-Facts @{ OverTargetTicks = 5; ClearTicks = 3 }) $Sz).Classes | Where-Object Id -eq 'capacity').Level | Should -Be 'clear'
        ((Get-WorkerPerfIncidentClasses (New-Facts @{ OverTargetTicks = 5; ClearTicks = 2 }) $Sz).Classes | Where-Object Id -eq 'capacity').Level | Should -Be 'tight'
        Classes-Of (New-Facts @{ OverTargetTicks = 2; QueueMax = 6 }) | Should -BeNullOrEmpty          # nur Warteschlange: kein CPU-Mangel (SZ-18)
    }
    It 'stellt den VMware-Host vor jede andere Klasse' { Classes-Of (New-Facts @{ StealTicks = 4; OverTargetTicks = 5 }) | Should -Be @('host', 'capacity') }
    It 'Arbeitsspeicher: Kapazitaet nur mit anhaltendem Auslagern' {
        $m = @{ Cpu = $false; Memory = $true; CommitOverRamTicks = 3; CommitCritTicks = 0; PagesOutPct = 50.1 }
        Classes-Of (New-Facts $m) | Should -Be @('mem.capacity')
        Classes-Of (New-Facts (Merge $m @{ PagesOutPct = 50 })) | Should -Be @('mem.used')
        Classes-Of (New-Facts (Merge $m @{ PagesOutPct = 50; CommitCritTicks = 3 })) | Should -Be @('mem.commit')      # hoher Commit ohne Auslagern: keine Kapazitaet
        $r = Get-WorkerPerfIncidentClasses (New-Facts (Merge $m @{ PagesOutMeasured = $false })) $Sz
        @($r.Classes.Id) | Should -Be @('undecidable'); $r.Unchecked[0].Missing | Should -Be @('mem.pagesout')
    }
    It 'Arbeitsspeicher: Anwendung ab 10 % des RAM Zuwachs' {
        $m = @{ Cpu = $false; Memory = $true; RamMB = 65536; MemTop = @{ App = 'simleak.exe'; SharePct = 20; GrowthMB = 6553.6 } }
        Classes-Of (New-Facts $m) | Should -Be @('mem.app')
        Classes-Of (New-Facts (Merge $m @{ MemTop = @{ App = 'simleak.exe'; SharePct = 20; GrowthMB = 6553.5 } })) | Should -Be @('mem.used')
    }
    It 'ohne Prozessdaten: nicht entscheidbar mit der fehlenden Messung' {
        $r = Get-WorkerPerfIncidentClasses (New-Facts @{ OverTargetTicks = 5; Processes = $false; TopProcess = $null; TopApp = $null }) $Sz
        @($r.Classes.Id) | Should -Be @('undecidable'); (Get-WorkerPerfClassOut @{ Classes = $r.Classes; Unchecked = $r.Unchecked } $Sz).Line | Should -Match 'Prozessdaten'
    }
    It 'bildet die Texte der Klassen aus dem Katalog' {
        $r = Get-WorkerPerfIncidentClasses (New-Facts @{ StealTicks = 4; StealMax = 12.6; OverTargetTicks = 5; ClearTicks = 3; CpuP95 = 96.4; QueueMax = 3 }) $Sz
        $o = Get-WorkerPerfClassOut @{ Classes = $r.Classes; Unchecked = $r.Unchecked } $Sz
        $o.Line | Should -Match '^Einordnung: VMware-Host, Kapazität \(deutlich\) – '; $o.Line | Should -Match '12,6 % je vCPU'; $o.Line | Should -Not -Match '\{'
        @($o.Classes.id) | Should -Be @('host', 'capacity'); $o.Classes[1].level | Should -Be 'clear'; $o.Classes[0].sources | Should -Be @('SZ-21', 'SZ-20', 'SZ-26', 'VM-08')
        $o.Classes[0].direction | Should -Match 'VMware-Host'
        (Get-WorkerPerfClassOut @{ Classes = @(); Unchecked = @() } $Sz).Line | Should -Be ''
    }
    It 'laesst einen Vorfall ohne CPU, Arbeitsspeicher und Verzoegerung ohne Einordnung' {
        $r = Get-WorkerPerfIncidentClasses (New-Facts @{ Cpu = $false; StealTicks = 9; StealMeasured = $false }) $Sz
        @($r.Classes).Count | Should -Be 0; @($r.Unchecked).Count | Should -Be 0
    }
}
Describe 'Einordnung an simulierten Aufzeichnungen' {
    BeforeAll {
        $script:Causes = Invoke-SimCapture (Join-Path $TestDrive 'u') @{ SimulateScenario = 'Ursachen' }
        $script:SimRoles = Read-WorkerPerfRoles (New-SimRoleFile (Join-Path $TestDrive 'r.json'))
    }
    It 'ordnet jede Szene ihrer Soll-Klasse zu' {
        $a = Get-WorkerPerfRunAnalysis -Path $Causes -Thresholds $Th -Roles $SimRoles -Sizing $Sz
        foreach ($e in @(Get-Content (Join-Path $Causes 'expected.json') -Raw | ConvertFrom-Json | Where-Object { $_.Type -ne 'ereignis' })) {
            $inc = @($a.Incidents | Where-Object { $_.StartMs -lt $e.EndMs -and $_.EndMs -gt $e.StartMs -and $_.Type -ne 'umfeld' })[0]
            @($inc.Classes | ForEach-Object { $_.Id }) | Should -Be @($e.Classes) -Because $e.Key
            $inc.Type | Should -Be $e.Type -Because $e.Key
        }
        ($a.Incidents | Where-Object { @($_.Classes | ForEach-Object { $_.Id }) -contains 'host' }).Classes[1].Level | Should -Be 'tight'
        @($a.Incidents | Where-Object { @($_.Classes | Where-Object { $_.Id -eq 'capacity' -and $_.Level -eq 'clear' }).Count -gt 0 }).Count | Should -Be 1
    }
    It 'ordnet die simulierte Stunde ein' {
        $a = Get-WorkerPerfRunAnalysis -Path (Invoke-SimCapture (Join-Path $TestDrive 's')) -Thresholds $Th -Roles $SimRoles -Sizing $Sz
        @(($a.Incidents | Where-Object Lead -eq 'cpu').Classes | ForEach-Object { $_.Id }) | Should -Be @('app')            # EXCEL.EXE von user003, 4,8 Kerne
        @(($a.Incidents | Where-Object Lead -eq 'memory').Classes | ForEach-Object { $_.Id }) | Should -Be @('mem.app')     # ms-teams.exe waechst um ein Drittel des RAM
        foreach ($i in @($a.Incidents | Where-Object Type -eq 'ohne-engpass')) { @($i.Classes).Count | Should -Be 0 }
        foreach ($i in @($a.Incidents | Where-Object { $_.Lead -in 'disk', 'share', 'profile' })) { @($i.Classes).Count | Should -Be 0; @($i.Unchecked).Count | Should -Be 0 }
    }
    It 'sagt an einer aelteren Aufzeichnung, was ohne die neuen Werte nicht unterscheidbar ist' {          # Review Focus 2
        $old = New-OldCaptureCopy $Causes (Join-Path $TestDrive 'old')
        $a = Get-WorkerPerfRunAnalysis -Path $old -Thresholds $Th -Roles $SimRoles -Sizing $Sz
        $one = @($a.Incidents | Where-Object Type -eq 'ohne-engpass')[0]
        @($one.Classes | ForEach-Object { $_.Id }) | Should -Be @('undecidable'); $one.Unchecked[0].Missing | Should -Be @('cpu.coreMax')
        (@($a.Incidents | Where-Object { @($_.Classes | ForEach-Object { $_.Id }) -contains 'capacity' })).Count | Should -BeGreaterThan 0      # breite Last bleibt entscheidbar
    }
    It 'liefert fuer einen Schnelllauf leere Listen' {
        $a = Get-WorkerPerfRunAnalysis -Path (Invoke-SimHealthOnly (Join-Path $TestDrive 'q')) -Thresholds $Th -Roles $SimRoles -Sizing $Sz
        @($a.Incidents).Count | Should -Be 0; @($a.Findings).Count | Should -Be 0; $a.Model.Meta.HealthOnly | Should -BeTrue
    }
}
