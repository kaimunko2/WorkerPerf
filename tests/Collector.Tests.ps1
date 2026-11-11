BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1')
    $script:Run = Invoke-SimCapture (Join-Path $TestDrive 'out')
    $script:Meta = Get-Content (Join-Path $Run 'meta.json') -Raw | ConvertFrom-Json
    $script:Snaps = @(Import-Csv (Join-Path $Run 'snapshots.csv'))
    $script:Exp = @(Get-Content (Join-Path $Run 'expected.json') -Raw | ConvertFrom-Json)
}
Describe 'Start-WorkerPerfCapture -Simulate' {
    It 'schreibt jede Datei des Formats mit ihrer Kopfzeile' {
        foreach ($name in $WorkerPerfHeaders.Keys) { Get-Content (Join-Path $Run $name) -TotalCount 1 | Should -Be $WorkerPerfHeaders[$name] }
        Test-Path (Join-Path $Run 'thresholds.json') | Should -BeTrue
    }
    It 'fuehrt meta.json' {
        $Meta.SchemaVersion | Should -Be 2; $Meta.EndReason | Should -Be 'duration'; $Meta.Ticks | Should -Be 1800
        $Meta.Snapshots | Should -Be $Snaps.Count; $Meta.SkippedTicks | Should -Be 0; $Meta.CollectorPid | Should -Be 4242
        $Meta.Sources.'input.session'.Available | Should -BeTrue; @($Meta.Endpoints).Count | Should -Be 3
    }
    It 'schreibt Zahlen mit Dezimalpunkt trotz deutscher Kultur' {              # Review Focus 2
        $lines = Get-Content (Join-Path $Run 'ticks.csv') | Select-Object -Skip 1 -First 50
        foreach ($line in $lines) { $line.Split(',').Count | Should -Be 19 }
        $lines[0] | Should -Match '^0,[^,]+,2,\d+(\.\d+)?,'
    }
    It 'nimmt 240 regulaere Schnappschuesse, davon 12 Stuetzpunkte' {
        @($Snaps | Where-Object Kind -in 'R', 'K').Count | Should -Be 240
        @($Snaps | Where-Object Kind -eq 'K').Count | Should -Be 12; $Snaps[0].Kind | Should -Be 'K'
    }
    It 'verdichtet nur waehrend der Vorfaelle und 60 Sekunden danach' {
        $burst = @($Snaps | Where-Object Kind -eq 'B'); $burst.Count | Should -BeGreaterThan 50
        $windows = @($Exp | Where-Object { -not $_.Chronic })
        foreach ($b in $burst) {
            $ms = [DateTimeOffset]::Parse($b.Timestamp, [cultureinfo]::InvariantCulture).ToUnixTimeMilliseconds()
            @($windows | Where-Object { $ms -ge $_.StartMs -and $ms -le $_.EndMs + 62000 }).Count | Should -BeGreaterThan 0
        }
    }
    It 'laesst ruhende Prozesse aus' {
        $regular = @($Snaps | Where-Object Kind -eq 'R')
        ($regular | Measure-Object RowsWritten -Average).Average | Should -BeLessThan (0.6 * [double]$regular[0].Processes)
    }
    It 'meldet das Ende des robocopy-Prozesses' { @(Get-Content (Join-Path $Run 'procend.csv')).Count | Should -BeGreaterThan 1 }
    It 'legt Proben, Ereignisse und Citrix-Werte ab' {
        @(Import-Csv (Join-Path $Run 'probes.csv')).Count | Should -Be (240 * 3)
        @(Import-Csv (Join-Path $Run 'events.csv')).Kind | Should -Be @('scan-start', 'scan-end', 'applocker-block')
        @(Get-Content (Join-Path $Run 'citrix.csv')).Count | Should -BeGreaterThan 1000
    }
    It 'bleibt unter 10 MB' { (Get-ChildItem $Run | Measure-Object Length -Sum).Sum | Should -BeLessThan 10MB }
    It 'legt das Soll-Ergebnis ab' { $Exp.Count | Should -Be 8; $Exp[1].Key | Should -Be 'cpu' }
    It 'verlangt fuer die Simulation mindestens 60 Minuten' {
        { & (Join-Path $PSScriptRoot '../src/Start-WorkerPerfCapture.ps1') -Simulate -DurationMinutes 10 -OutputPath (Join-Path $TestDrive 'kurz') 6>$null } | Should -Throw '*60*'
    }
}
Describe 'Fehler der Datenquelle beenden die Aufzeichnung nicht' {                  # Abschlussrunde I6
    BeforeAll {
        # der schnelle Takt scheitert einmal (598 s), der Prozess-Schnappschuss einmal (660 s), das Ereignisprotokoll bei jedem Aufruf
        $capture = New-PatchedSource (Join-Path $TestDrive 'srcfail') @'
$script:TestFast = ${function:Get-WorkerPerfFastSample}
$script:TestSnap = ${function:Get-WorkerPerfSnapshot}
function Get-WorkerPerfFastSample { if ((Get-WorkerPerfSimElapsed) -eq 598) { throw 'Testfehler im schnellen Takt' }; & $script:TestFast }
function Get-WorkerPerfSnapshot { if ((Get-WorkerPerfSimElapsed) -eq 660) { throw 'Testfehler im Schnappschuss' }; & $script:TestSnap }
function Get-WorkerPerfEvents { param([datetime]$Since) throw 'Testfehler im Ereignisprotokoll' }
'@
        [cultureinfo]::CurrentCulture = [cultureinfo]'de-DE'
        $out = @(& $capture -Simulate -DurationMinutes 60 -OutputPath (Join-Path $TestDrive 'fail') 6>$null 3>&1)
        $script:FailWarnings = @($out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $_.Message })
        $script:FailRun = [string]($out | Where-Object { $_ -is [string] } | Select-Object -Last 1)
        $script:FailMeta = Get-Content (Join-Path $FailRun 'meta.json') -Raw | ConvertFrom-Json
        $script:FailReport = Join-Path $TestDrive 'fail.html'
        [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $FailRun -OutFile $FailReport -RoleFile (New-SimRoleFile (Join-Path $TestDrive 'roles.fail.json')) 6>$null)
        $script:FailData = Get-ReportData $FailReport
    }
    It 'erreicht das geplante Ende' {
        $FailMeta.EndReason | Should -Be 'duration'; $FailMeta.Ticks | Should -Be 1799; $FailMeta.EndMessage | Should -BeNullOrEmpty
    }
    It 'vermerkt je Quelle die Zahl der Fehler sowie Zeit und Meldung des ersten' {
        $e = $FailMeta.SourceErrors
        $e.fast.Count | Should -Be 1; $e.fast.FirstMessage | Should -Be 'Testfehler im schnellen Takt'
        $e.snapshot.Count | Should -Be 1; $e.snapshot.FirstMessage | Should -Be 'Testfehler im Schnappschuss'
        $e.events.Count | Should -Be 240; $e.events.FirstMessage | Should -Be 'Testfehler im Ereignisprotokoll'
        # ConvertFrom-Json liefert Zeiten je nach PowerShell-Version als DateTime oder als Text
        $toDto = { param($v) if ($v -is [datetime]) { [DateTimeOffset]$v } else { [DateTimeOffset]::Parse($v, [cultureinfo]::InvariantCulture) } }
        ((& $toDto $e.fast.FirstTime) - (& $toDto $FailMeta.StartTime)).TotalSeconds | Should -Be 598
    }
    It 'warnt je Quelle genau einmal' {
        foreach ($word in 'schneller Takt', 'Prozess-Schnappschuss', 'Ereignisprotokoll') { @($FailWarnings | Where-Object { $_ -like "*$word*" }).Count | Should -Be 1 -Because $word }
        $FailWarnings.Count | Should -Be 3
    }
    It 'laesst nur den betroffenen Takt und Schnappschuss aus' {
        $ticks = @(Import-Csv (Join-Path $FailRun 'ticks.csv')); $ticks.Count | Should -Be 1799
        @($ticks | Where-Object { [double]$_.ElapsedSec -ne 2 }).Count | Should -Be 1      # der Takt nach dem ausgefallenen deckt 4 s ab
        ($ticks | Where-Object { [double]$_.ElapsedSec -ne 2 }).ElapsedSec | Should -Be '4'
        $snaps = @(Import-Csv (Join-Path $FailRun 'snapshots.csv'))
        @($snaps | Where-Object Kind -in 'R', 'K').Count | Should -Be 239; @($snaps | Where-Object Kind -eq 'K').Count | Should -Be 12
        @(Import-Csv (Join-Path $FailRun 'probes.csv')).Count | Should -Be (240 * 3)       # die Proben laufen auch ohne den Schnappschuss
        @(Get-Content (Join-Path $FailRun 'events.csv')).Count | Should -Be 1
        foreach ($name in $WorkerPerfHeaders.Keys) { Get-Content (Join-Path $FailRun $name) -TotalCount 1 | Should -Be $WorkerPerfHeaders[$name] }
    }
    It 'bleibt auswertbar und zeigt die Fehler im Bericht' {
        $FailData.incidents.Count | Should -Be 8; $FailData.meta.endReason | Should -Be 'duration'
        $q = $FailData.quality
        @($q.sourceErrors).source | Should -Be @('events', 'fast', 'snapshot')
        ($q.sourceErrors | Where-Object source -eq 'events').count | Should -Be 240
        ($q.sourceErrors | Where-Object source -eq 'events').label | Should -Be 'Ereignisprotokoll'
        ($q.sourceErrors | Where-Object source -eq 'fast').firstMessage | Should -Be 'Testfehler im schnellen Takt'
        ($q.sourceErrors | Where-Object source -eq 'fast').firstMs | Should -Be ($FailData.meta.start + 596000)
        $q.skippedTicks | Should -Be 1; $q.unreadable.ticks | Should -Be 0             # ein ausgefallener Takt ist eine Luecke, keine unlesbare Zeile
        @($FailData.events).Count | Should -Be 0
    }
}
Describe 'Ende der Aufzeichnung mit Fehler' {                                       # Abschlussrunde I6, Minor 17
    BeforeAll {
        $script:Loop = @'
$script:TestRows = ${function:ConvertTo-WorkerPerfFastRows}
function ConvertTo-WorkerPerfFastRows { param($Sample, [int]$T, [double]$ElapsedSec, [bool]$Burst, [double]$CollectMs)
    if ($T -eq 50) { throw 'Testfehler in der Schleife' }
    & $script:TestRows -Sample $Sample -T $T -ElapsedSec $ElapsedSec -Burst $Burst -CollectMs $CollectMs }
'@
        function Invoke-FailingCapture([string]$Name, [string]$Overrides) {
            $capture = New-PatchedSource (Join-Path $TestDrive "src$Name") $Overrides
            $r = @{ Error = $null; Warnings = @(); Run = $null }
            try { $r.Warnings = @(& $capture -Simulate -DurationMinutes 60 -OutputPath (Join-Path $TestDrive $Name) 6>$null 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $_.Message }) }
            catch { $r.Error = $_.Exception.Message }
            $r.Run = (Get-ChildItem (Join-Path $TestDrive $Name) -Directory)[0].FullName
            $r
        }
    }
    It 'vermerkt eine Ausnahme in der Schleife als Ende mit Fehler samt Meldung' {
        $r = Invoke-FailingCapture 'loop' $Loop
        $r.Error | Should -Be 'Testfehler in der Schleife'
        $meta = Get-Content (Join-Path $r.Run 'meta.json') -Raw | ConvertFrom-Json
        $meta.EndReason | Should -Be 'error'; $meta.EndMessage | Should -Be 'Testfehler in der Schleife'; $meta.Ticks | Should -Be 50; $meta.EndTime | Should -Not -BeNullOrEmpty
        @(Get-ChildItem $r.Run -Filter '*.tmp').Count | Should -Be 0
        $out = Join-Path $TestDrive 'loop.html'
        [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $r.Run -OutFile $out 6>$null)
        $d = Get-ReportData $out; $d.meta.endReason | Should -Be 'error'; $d.meta.endMessage | Should -Be 'Testfehler in der Schleife'; $d.tickT.Count | Should -Be 50
    }
    It 'laesst einen Fehler beim Abschluss den eigentlichen Fehler nicht ersetzen' {
        # meta.json laesst sich nach dem Start nicht mehr schreiben
        $r = Invoke-FailingCapture 'cleanup' ($Loop + @'

$script:TestSave = ${function:Save-WorkerPerfMeta}; $script:TestSaves = 0
function Save-WorkerPerfMeta { param([string]$Path, $Meta) $script:TestSaves++; if ($script:TestSaves -gt 1) { throw 'Testfehler beim Abschluss' }; & $script:TestSave -Path $Path -Meta $Meta }
'@)
        $r.Error | Should -Be 'Testfehler in der Schleife'
        (Get-Content (Join-Path $r.Run 'meta.json') -Raw | ConvertFrom-Json).EndReason | Should -BeNullOrEmpty      # der Stand vom Start bleibt lesbar
        Test-Path (Join-Path $r.Run 'expected.json') | Should -BeTrue                # der Rest des Abschlusses laeuft weiter
    }
}
Describe 'Zeitplan ueber das Ende der Sommerzeit' -Skip:(-not [TimeZoneInfo]::Local.SupportsDaylightSavingTime) {   # Abschlussrunde Minor 8
    It 'schreibt fortlaufende Takte, wenn die Ortszeit um eine Stunde zurueckspringt' {
        # Start 45 Minuten vor dem Ende der Sommerzeit dieses Rechners (auf die Stunde genau gesucht)
        $tz = [TimeZoneInfo]::Local; $u = [datetime]::SpecifyKind([datetime]'2026-01-01', 'Utc'); $switch = $null
        for ($h = 0; $h -lt 8760 -and $null -eq $switch; $h++) { if ($tz.IsDaylightSavingTime($u.AddHours($h)) -and -not $tz.IsDaylightSavingTime($u.AddHours($h + 1))) { $switch = $u.AddHours($h + 1) } }
        $switch | Should -Not -BeNullOrEmpty
        $startUtc = $switch.AddMinutes(-45).Ticks
        $capture = New-PatchedSource (Join-Path $TestDrive 'srcdst') @"
`$script:TestInit = `${function:Initialize-WorkerPerfSource}
function Initialize-WorkerPerfSource { param([datetime]`$StartTime, [object[]]`$Endpoints = @(), [string]`$CitrixMetricFilter = '', [switch]`$IncludeCommandLine, [switch]`$NoCitrix)
    & `$script:TestInit -StartTime (New-Object DateTime ($startUtc, [DateTimeKind]::Utc)).ToLocalTime() -Endpoints `$Endpoints -CitrixMetricFilter `$CitrixMetricFilter }
"@
        $run = (& $capture -Simulate -DurationMinutes 60 -OutputPath (Join-Path $TestDrive 'dst') 6>$null 3>$null) | Select-Object -Last 1
        $ticks = @(Import-Csv (Join-Path $run 'ticks.csv')); $ticks.Count | Should -Be 1800
        $ms = @($ticks | ForEach-Object { [DateTimeOffset]::Parse($_.Timestamp, [cultureinfo]::InvariantCulture).ToUnixTimeMilliseconds() })
        $steps = @(1..($ms.Count - 1) | ForEach-Object { $ms[$_] - $ms[$_ - 1] } | Sort-Object -Unique)
        $steps | Should -Be @(2000)                                                 # kein Sprung in der aufgezeichneten Zeit
        @($ticks | Where-Object { [double]$_.ElapsedSec -ne 2 }).Count | Should -Be 0
        @($ticks | ForEach-Object { [DateTimeOffset]::Parse($_.Timestamp, [cultureinfo]::InvariantCulture).Offset } | Sort-Object -Unique).Count | Should -Be 2   # Sommer- und Normalzeit
        (Get-Content (Join-Path $run 'meta.json') -Raw | ConvertFrom-Json).EndReason | Should -Be 'duration'
    }
}
