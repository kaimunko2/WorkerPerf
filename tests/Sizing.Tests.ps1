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
    function New-RunRecord([hashtable]$Change) {
        # eine Aufzeichnung mit Messung: 8 vCPU, 65536 MB, Server SIM-VDA01, vier Stunden Hauptzeit, keine Klasse
        Merge @{ Path = 'run'; Server = 'SIM-VDA01'; StartMs = 1; EndMs = 14400001; DurationMin = 240.0; EndReason = 'duration'; HealthOnly = $false
            Cores = 8; RamMB = 65536.0; MainTicks = 7200; MainHours = 4.0; Cpu = @{ Peak = 60.0; P95 = 50.0 }; Queue = @{ Peak = 1.0; P95 = 0.5 }
            Commit = @{ PeakMB = 40000.0; P95MB = 39000.0; PeakPctRam = 61.0 }; SessionsPeak = 25; MainCpu = [double[]]@(50, 50, 50); MainSessions = [double[]]@(25, 25, 25)
            CommitMaxMainMB = 40000.0; Classes = @{}; Bottlenecks = @(); Health = $null } $Change
    }
    function Summary-Of([int]$Runs, [double]$HoursEach) {
        Get-WorkerPerfSizingSummary -Group @{ Key = 'SIM-VDA01'; Runs = @(1..$Runs | ForEach-Object { New-RunRecord @{ StartMs = $_; MainHours = $HoursEach } }) } -Sizing $Sz
    }
    function New-SessionModel([double[]]$Sessions) {
        # Schnappschuesse mit diesen Sitzungszahlen auf den Takten 1, 3, 5, ...; ein Takt mehr als der letzte Schnappschuss
        $n = 2 * $Sessions.Count
        @{ Tick = @{ N = $n; ElapsedSec = [double[]]@(1..$n | ForEach-Object { 2.0 }) }; Snap = @{ N = $Sessions.Count; Sessions = $Sessions; TickPos = [int[]]@(0..($Sessions.Count - 1) | ForEach-Object { 2 * $_ + 1 }) } }
    }
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
        $t.sustainedPct.Value | Should -Be 80; $t.hostSharePct.Value | Should -Be 10; $t.pagesOutLowPerSec.Value | Should -Be 10; $t.pagesOutSharePct.Value | Should -Be 50
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
        @{ Name = 'unbekannter Platzhalter in der Richtung'; Change = { ($j.classes | Where-Object id -eq 'app').direction = 'x {cpu}' }; Message = '*classes app: direction*{cpu}*' }
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
    It 'VMware-Host in einem langen Fenster erst ab einem Anteil der Takte (Gesamtpruefung, Befund 3)' {
        # drei verstreute Takte in acht Stunden sind kein Host-Vorfall; 10 % der Takte sind einer
        Classes-Of (New-Facts @{ StealTicks = 3; WindowTicks = 14400; OverTargetTicks = 5000 }) | Should -Be @('capacity')
        Classes-Of (New-Facts @{ StealTicks = 1440; WindowTicks = 14400; OverTargetTicks = 5000 }) | Should -Be @('host', 'capacity')
        Classes-Of (New-Facts @{ StealTicks = 3; WindowTicks = 30 }) | Should -Contain 'host'
        $Sz.Thresholds.hostSharePct.Value | Should -Be 10
    }
    It 'laesst bei breiter Last einen Prozess auf einem Kern nicht die Kapazitaet verdraengen (Gesamtpruefung, Befund 4)' {
        $f = @{ OverTargetTicks = 50; CpuP95 = 85.0; TopProcess = @{ Name = 'single.exe'; Cores = 1.0; BandPct = 90 }; TopApp = @{ App = 'single.exe'; Role = ''; RoleLabel = ''; SharePct = 8.0 } }
        Classes-Of (New-Facts (Merge $f @{ CoreMaxHighPct = 95 })) | Should -Be @('capacity')
        $r = Get-WorkerPerfIncidentClasses (New-Facts (Merge $f @{ CoreMaxHighPct = 10 })) $Sz; @($r.Classes.Id) | Should -Be @('capacity'); @($r.Unchecked).Count | Should -Be 0
        Classes-Of (New-Facts (Merge $f @{ CoreMaxMeasured = $false })) | Should -Be @('capacity')
        # ohne breite Last ueber dem Ziel bleibt es Leistung je Kern
        Classes-Of (New-Facts (Merge $f @{ OverTargetTicks = 0; CpuP95 = 40.0; CoreMaxHighPct = 95 })) | Should -Be @('singlecore')
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
        $o.Classes[0].advice | Should -Match 'VMware-Host'
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
Describe 'Hochrechnung von Hand nachgerechnet' {
    It 'rechnet das Beispiel des Entwurfs: 8 vCPU, L 92, T 75 -> 10 bis 12' {
        $lo = Get-WorkerPerfCpuNeed 8 92 75 1.9; $lo | Should -BeGreaterThan 9.97; $lo | Should -BeLessThan 9.98
        $hi = Get-WorkerPerfCpuNeed 8 92 75 1.5; $hi | Should -BeGreaterThan 11.34; $hi | Should -BeLessThan 11.35
        $r = Get-WorkerPerfCpuRange 8 92 75 $Sz; $r.Low | Should -Be 10; $r.High | Should -Be 12
    }
    It 'rundet auf eine gerade Zahl auf' { @(9.975, 11.344, 10.0, 10.0000001, 7.01) | ForEach-Object { Get-WorkerPerfEvenUp $_ } | Should -Be @(10, 12, 10, 10, 8) }
    It 'zeigt eine Spanne aus einer Zahl als eine Zahl' {                                    # Review Focus 5
        $r = Get-WorkerPerfCpuRange 7 75.1 75 $Sz; $r.Low | Should -Be 8; $r.High | Should -Be 8
    }
    It 'Grenze 16: obere Grenze 16 ohne, 18 mit dem Hinweis auf mehr Server' {
        (Get-WorkerPerfCpuRange 10 92 75 $Sz).High | Should -Be 16
        (Get-WorkerPerfCpuDecision -Recurring 'capacity' -Seen 'capacity' -Load 92 -Target 75 -Cores 10 -SessionsPeak 31 -HasMainTime $true -Sizing $Sz).Hints | Should -Not -Contain 'scaleOutToo'
        $d = Get-WorkerPerfCpuDecision -Recurring 'capacity' -Seen 'capacity' -Load 92 -Target 75 -Cores 12 -SessionsPeak 31 -HasMainTime $true -Sizing $Sz
        $d.Kind | Should -Be 'range'; $d.High | Should -Be 18; $d.Hints | Should -Contain 'scaleOutToo'
    }
    It 'Grenze 24: bis 24 Spanne, darueber nur mehr Server mit Sitzungen x T / L' {
        $d = Get-WorkerPerfCpuDecision -Recurring 'capacity' -Seen 'capacity' -Load 92 -Target 75 -Cores 16 -SessionsPeak 31 -HasMainTime $true -Sizing $Sz
        $d.Kind | Should -Be 'range'; $d.Low | Should -Be 20; $d.High | Should -Be 24
        $e = Get-WorkerPerfCpuDecision -Recurring 'capacity' -Seen 'capacity' -Load 92 -Target 75 -Cores 18 -SessionsPeak 31 -HasMainTime $true -Sizing $Sz
        $e.Kind | Should -Be 'scaleOut'; $e.Sessions | Should -Be 25; $e.Low | Should -BeNullOrEmpty
    }
}
Describe 'Wann eine vCPU-Spanne steht' {
    BeforeAll { function D([string[]]$Rec, [string[]]$Seen, [double]$L) { Get-WorkerPerfCpuDecision -Recurring $Rec -Seen $Seen -Load $L -Target 75 -Cores 8 -SessionsPeak 31 -HasMainTime $true -Sizing $Sz } }
    It 'keine vCPU-Zahl bei wiederkehrendem VMware-Host' { $d = D @('host', 'capacity') @('host', 'capacity') 92; $d.Kind | Should -Be 'host'; $d.Low | Should -BeNullOrEmpty; $d.Hints | Should -Contain 'hostCheck' }
    It 'Groesse reicht unter und bei T' { (D @('capacity') @('capacity') 74.9).Kind | Should -Be 'enough'; (D @('capacity') @('capacity') 75).Kind | Should -Be 'enough' }
    It 'Spanne bei wiederkehrender Kapazitaet, mit Hinweis bei Leistung je Kern' {
        $d = D @('capacity', 'singlecore') @('capacity', 'singlecore') 92; $d.Kind | Should -Be 'range'; $d.Hints | Should -Contain 'singlecoreToo'; $d.Hints | Should -Contain 'numa'
    }
    It 'keine vCPU-Zahl bei Leistung je Kern oder Anwendung allein' {
        $d = D @('singlecore') @('singlecore') 92; $d.Kind | Should -Be 'other'; $d.Cause | Should -Be 'singlecore'; $d.Low | Should -BeNullOrEmpty
        (D @('app') @('app') 92).Cause | Should -Be 'app'; (D @() @('capacity') 92).Cause | Should -Be ''
    }
    It 'nennt einen einzelnen Host-Vorfall als Hinweis bei der Spanne' { (D @('capacity') @('capacity', 'host') 92).Hints | Should -Contain 'hostOnce' }
    It 'rechnet ohne Hauptzeit nicht hoch' {                                                        # Review Focus 4
        (Get-WorkerPerfCpuDecision -Recurring 'capacity' -Seen 'capacity' -Load ([double]::NaN) -Target 75 -Cores 8 -SessionsPeak 0 -HasMainTime $false -Sizing $Sz).Kind | Should -Be 'noMainTime'
    }
}
Describe 'Arbeitsspeicher' {
    It 'rundet C / 0,8 auf volle 4 GB' { Get-WorkerPerfRamTarget 60000 $Sz | Should -Be 76; Get-WorkerPerfRamTarget 49152 $Sz | Should -Be 60 }
    It 'empfiehlt mehr RAM nur bei wiederkehrender Kapazitaet' {
        $m = Get-WorkerPerfMemoryDecision -Recurring 'mem.capacity' -CommitMaxMB 70000 -RamMB 65536 -Sizing $Sz; $m.Kind | Should -Be 'more'; $m.TargetGB | Should -Be 88
        (Get-WorkerPerfMemoryDecision -Recurring 'mem.commit' -CommitMaxMB 90000 -RamMB 65536 -Sizing $Sz).Kind | Should -Be 'pagefile'
        (Get-WorkerPerfMemoryDecision -Recurring 'mem.app' -CommitMaxMB 60000 -RamMB 65536 -Sizing $Sz).Kind | Should -Be 'app'
        $e = Get-WorkerPerfMemoryDecision -Recurring @() -CommitMaxMB 70000 -RamMB 65536 -Sizing $Sz; $e.Kind | Should -Be 'enough'; $e.Hints | Should -Contain 'commitAboveRam'
        (Get-WorkerPerfMemoryDecision -Recurring @() -CommitMaxMB 60000 -RamMB 65536 -Sizing $Sz).Hints | Should -Not -Contain 'commitAboveRam'
    }
}
Describe 'Ueber die Aufzeichnungen' {
    It 'nimmt als Hauptzeit die Takte mit mindestens halb so vielen Sitzungen wie in der Spitze' {
        # Modell mit Schnappschuessen Sessions 0, 10, 20, 9, 10 auf den Takten 1, 3, 5, 7, 9 (10 Takte)
        Get-WorkerPerfMainTicks (New-SessionModel @(0, 10, 20, 9, 10)) 50 | Should -Be @(3, 4, 5, 6, 9)
        @(Get-WorkerPerfMainTicks (New-SessionModel @(0, 0, 0)) 50).Count | Should -Be 0                       # Review Focus 4
    }
    It 'zaehlt wiederkehrend ab der Haelfte der Aufzeichnungen' {
        $s = Get-WorkerPerfSizingSummary -Group @{ Key = 'SIM-VDA01'; Runs = @((New-RunRecord @{ Classes = @{ capacity = 1 } }), (New-RunRecord @{ Classes = @{ capacity = 2 } }), (New-RunRecord @{}), (New-RunRecord @{})) } -Sizing $Sz
        $s.Recurring.Contains('capacity') | Should -BeTrue; $s.Recurring['capacity'] | Should -Be 2; $s.Result.Key | Should -Be 'recurring'; $s.Result.Class | Should -Be 'capacity'
        $s.Result.Count | Should -Be 2; $s.Result.Total | Should -Be 4; $s.Result.Resource | Should -Be 'cpu'
        $t = Get-WorkerPerfSizingSummary -Group @{ Key = 'x'; Runs = @((New-RunRecord @{ Classes = @{ capacity = 1 } }), (New-RunRecord @{}), (New-RunRecord @{})) } -Sizing $Sz
        $t.Recurring.Contains('capacity') | Should -BeFalse; $t.Seen['capacity'] | Should -Be 1; $t.Result.Key | Should -Be 'once'
        (Summary-Of 3 4.0).Result.Key | Should -Be 'none'
    }
    It 'bildet L aus der Hauptzeit aller Aufzeichnungen und entscheidet daraus' {
        $runs = @((New-RunRecord @{ StartMs = 1; Classes = @{ capacity = 1 }; MainCpu = [double[]]@(80, 90, 92); Cpu = @{ Peak = 97.0; P95 = 92.0 }; SessionsPeak = 31; CommitMaxMainMB = 55000.0 }),
            (New-RunRecord @{ StartMs = 2; Classes = @{ capacity = 1 }; MainCpu = [double[]]@(85, 91, 92); SessionsPeak = 28 }),
            (New-RunRecord @{ StartMs = 3; MainCpu = [double[]]@(); MainHours = 0.0; SessionsPeak = 0 }))                          # Review Focus 4: ohne Hauptzeit
        $s = Get-WorkerPerfSizingSummary -Group @{ Key = 'x'; Runs = $runs } -Sizing $Sz
        $s.Load | Should -Be 92; $s.Peak | Should -Be 97; $s.Target | Should -Be 75; $s.SessionsPeak | Should -Be 31; $s.CommitMaxMB | Should -Be 55000; $s.MainHours | Should -Be 8
        $s.Cpu.Kind | Should -Be 'range'; $s.Cpu.Low | Should -Be 10; $s.Cpu.High | Should -Be 12; $s.Memory.Kind | Should -Be 'enough'; $s.LowMeasure | Should -BeTrue
        $n = Get-WorkerPerfSizingSummary -Group @{ Key = 'x'; Runs = @($runs[2]) } -Sizing $Sz
        $n.Cpu.Kind | Should -Be 'noMainTime'; [double]::IsNaN($n.Load) | Should -BeTrue
    }
    It 'rechnet nach einem Wechsel der Groesse nur mit den Aufzeichnungen der letzten Groesse (Gesamtpruefung, Befund 6)' {
        $runs = @((New-RunRecord @{ StartMs = 1; Cores = 8; Classes = @{ capacity = 1 }; MainCpu = [double[]]@(92, 92, 92); Cpu = @{ Peak = 99.0; P95 = 92.0 }; SessionsPeak = 31; CommitMaxMainMB = 60000.0 }),
            (New-RunRecord @{ StartMs = 2; Cores = 8; Classes = @{ capacity = 1 }; MainCpu = [double[]]@(92, 92, 92); Cpu = @{ Peak = 99.0; P95 = 92.0 }; SessionsPeak = 31 }),
            (New-RunRecord @{ StartMs = 3; Cores = 10; Classes = @{ capacity = 1 }; MainCpu = [double[]]@(78, 78, 78); Cpu = @{ Peak = 80.0; P95 = 78.0 }; SessionsPeak = 30; CommitMaxMainMB = 50000.0 }))
        $s = Get-WorkerPerfSizingSummary -Group @{ Key = 'x'; Runs = $runs } -Sizing $Sz
        $s.Load | Should -Be 78; $s.Peak | Should -Be 80; $s.SessionsPeak | Should -Be 30; $s.CommitMaxMB | Should -Be 50000; $s.Cores | Should -Be 10
        $s.Cpu.Kind | Should -Be 'range'; $s.Cpu.High | Should -BeLessOrEqual 12; $s.Recurring['capacity'] | Should -Be 3
    }
    It 'empfiehlt ohne Hauptzeit oder mit einem Ziel unter dem heutigen RAM keine RAM-Zahl (Gesamtpruefung, Befund 5)' {
        $n = Get-WorkerPerfMemoryDecision -Recurring 'mem.capacity' -CommitMaxMB ([double]::NaN) -RamMB 65536 -Sizing $Sz; $n.Kind | Should -Be 'more'; $n.TargetGB | Should -BeNullOrEmpty
        (Get-WorkerPerfMemoryDecision -Recurring 'mem.capacity' -CommitMaxMB 38000 -RamMB 65536 -Sizing $Sz).TargetGB | Should -BeNullOrEmpty
        (Get-WorkerPerfMemoryDecision -Recurring 'mem.capacity' -CommitMaxMB 70000 -RamMB 65536 -Sizing $Sz).TargetGB | Should -Be 88
        $s = Get-WorkerPerfSizingSummary -Group @{ Key = 'x'; Runs = @((New-RunRecord @{ Classes = @{ 'mem.capacity' = 1 }; MainCpu = [double[]]@(); MainHours = 0.0; SessionsPeak = 0; CommitMaxMainMB = [double]::NaN })) } -Sizing $Sz
        $d = New-WorkerPerfSizingData -Summary $s -Sizing $Sz
        $mem = $d.recommendations | Where-Object { $_.resource -eq 'memory' }; $mem.status | Should -Be 'act'; $mem.projection | Should -BeNullOrEmpty
    }
    It 'merkt wenig Messzeit unter drei Aufzeichnungen oder zwoelf Stunden Hauptzeit' {
        (Summary-Of 3 4.0).LowMeasure | Should -BeFalse; (Summary-Of 2 10.0).LowMeasure | Should -BeTrue; (Summary-Of 3 3.96).LowMeasure | Should -BeTrue
    }
    It 'nennt einen Wechsel der Groesse und rechnet von der letzten Aufzeichnung' {                 # Review Focus 2
        $s = Get-WorkerPerfSizingSummary -Group @{ Key = 'x'; Runs = @((New-RunRecord @{ StartMs = 1; Cores = 8 }), (New-RunRecord @{ StartMs = 2; Cores = 8 }), (New-RunRecord @{ StartMs = 3; Cores = 10 })) } -Sizing $Sz
        $s.SizeChanged | Should -BeTrue; $s.Cores | Should -Be 10; @($s.Sizes).Count | Should -Be 2; $s.Sizes[0].Cores | Should -Be 8
        (Summary-Of 3 4.0).SizeChanged | Should -BeFalse
    }
    It 'zaehlt einen Schnelllauf nicht fuer die Last' {
        $s = Get-WorkerPerfSizingSummary -Group @{ Key = 'x'; Runs = @((New-RunRecord @{}), (New-RunRecord @{ HealthOnly = $true; StartMs = 5; Health = @{ 'operation.powerPlan' = 'Ausbalanciert' } })) } -Sizing $Sz
        @($s.LoadRuns).Count | Should -Be 1; @($s.Runs).Count | Should -Be 2; $s.Evidence['operation.powerPlan'] | Should -Be 'Ausbalanciert'
    }
    It 'prueft denselben Server an einer Stelle, ohne Ruecksicht auf die Schreibweise' {               # Review Focus 3
        { Assert-WorkerPerfSameServer @(@{ Path = 'a'; Server = 'SIM-VDA01' }, @{ Path = 'b'; Server = 'sim-vda01' }) } | Should -Not -Throw
        { Assert-WorkerPerfSameServer @(@{ Path = 'a'; Server = 'SIM-VDA01' }, @{ Path = 'C:\x\b'; Server = 'SIM-VDA02' }) } | Should -Throw "*'C:\x\b'*SIM-VDA02*spaeterer Baustein*"
    }
    It 'ordnet die Aufzeichnungen auf der Achse Zeit nach ihrem Beginn' {                            # Review Focus 3
        $g = @(Group-WorkerPerfSizingRuns @((New-RunRecord @{ StartMs = 3 }), (New-RunRecord @{ StartMs = 1 }), (New-RunRecord @{ StartMs = 2 })) 'time')
        $g.Count | Should -Be 1; @($g[0].Runs | ForEach-Object { $_.StartMs }) | Should -Be @(1, 2, 3); $g[0].Key | Should -Be 'SIM-VDA01'
    }
    It 'bildet die Kennzahlen einer simulierten Aufzeichnung' {
        $run = Invoke-SimCapture (Join-Path $TestDrive 'tag') @{ SimulateScenario = 'Tag'; SimulateDay = 3 }
        $roles = Read-WorkerPerfRoles (New-SimRoleFile (Join-Path $TestDrive 'rt.json'))
        $head = Get-WorkerPerfRunServer $run; $head.Server | Should -Be 'SIM-VDA01'; $head.HealthOnly | Should -BeFalse; $head.StartMs | Should -BeGreaterThan 0
        $r = Get-WorkerPerfSizingRun -Analysis (Get-WorkerPerfRunAnalysis -Path $run -Thresholds $Th -Roles $roles -Sizing $Sz) -Path $run -Sizing $Sz
        $r.Server | Should -Be 'SIM-VDA01'; $r.Cores | Should -Be 8; $r.RamMB | Should -Be 65536; $r.SessionsPeak | Should -Be 31; $r.HealthOnly | Should -BeFalse
        $r.Cpu.Peak | Should -BeGreaterOrEqual 91; $r.Cpu.P95 | Should -BeGreaterOrEqual 90; $r.Queue.Peak | Should -Be 3; $r.DurationMin | Should -BeGreaterThan 59
        $r.MainHours | Should -BeGreaterThan 0.5; $r.MainHours | Should -BeLessThan 0.8; @($r.MainCpu).Count | Should -Be $r.MainTicks; @($r.MainSessions).Count | Should -Be $r.MainTicks
        ($r.MainSessions | Measure-Object -Minimum).Minimum | Should -BeGreaterOrEqual 15.5
        # die entzogene CPU-Zeit liegt in der Spitze: ihr eigener Vorfall und die Dauerzustaende der Spitze tragen den VMware-Host
        $r.Classes['capacity'] | Should -BeGreaterOrEqual 1; $r.Classes['host'] | Should -BeGreaterOrEqual 1
        foreach ($e in @(Get-Content (Join-Path $run 'expected.json') -Raw | ConvertFrom-Json | Where-Object { $_.Type -ne 'ereignis' })) {
            $hit = @($r.Bottlenecks | Where-Object { $_.StartMs -lt $e.EndMs -and $_.EndMs -gt $e.StartMs -and [Math]::Abs($_.StartMs - $e.StartMs) -le 30000 })
            $hit.Count | Should -BeGreaterOrEqual 1 -Because $e.Key; $hit[0].ClassIds | Should -Be @($e.Classes) -Because $e.Key
        }
        $r.CommitMaxMainMB | Should -BeGreaterThan 50000
        $r.Health['size.cpuLogical'] | Should -Be 8
        $q = Invoke-SimHealthOnly (Join-Path $TestDrive 'tq'); (Get-WorkerPerfRunServer $q).HealthOnly | Should -BeTrue
        $qr = Get-WorkerPerfSizingRun -Analysis (Get-WorkerPerfRunAnalysis -Path $q -Thresholds $Th -Roles $roles -Sizing $Sz) -Path $q -Sizing $Sz
        $qr.HealthOnly | Should -BeTrue; $qr.Server | Should -Be 'SIM-VDA01'; $qr.Health['size.cpuLogical'] | Should -Be 8
    }
}
