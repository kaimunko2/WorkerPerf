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
        $Meta.SchemaVersion | Should -Be 3; $Meta.EventLookbackDays | Should -Be 7; @($Meta.LookbackCapped).Count | Should -Be 0      # Format 3 statt 2
        $Meta.EndReason | Should -Be 'duration'; $Meta.Ticks | Should -Be 1800
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
    # Aussagen geaendert: neue Ereignisse, Rueckblick, Treiber und Warteschlangen der Simulation (Task 4)
    It 'legt Proben, Ereignisse und Citrix-Werte ab' {
        @(Import-Csv (Join-Path $Run 'probes.csv')).Count | Should -Be (240 * 3)
        @(Import-Csv (Join-Path $Run 'events.csv') | Where-Object Group -eq 'security').Kind | Should -Be @('scan-start', 'scan-end', 'applocker-block')
        @(Import-Csv (Join-Path $Run 'events.csv')).Count | Should -Be 13
        @(Import-Csv (Join-Path $Run 'events_before.csv')).Count | Should -Be 6; @(Import-Csv (Join-Path $Run 'printdrivers.csv')).Count | Should -Be 3
        # Aussage geaendert (M6): eine Zeile beim ersten Auftreten einer Warteschlange und bei jeder Aenderung eines Werts
        # (PRN-EG-01: Start, 3 Auftraege ab 2595 s, ein Fehler mehr ab 2610 s, leer ab 2715 s; PRN-OG-02 bleibt unveraendert)
        @(Import-Csv (Join-Path $Run 'printqueues.csv') | ForEach-Object { '{0}|{1}|{2}' -f $_.Queue, $_.Jobs, $_.JobErrors }) | Should -Be @('PRN-EG-01|0|2', 'PRN-OG-02|0|0',
            'PRN-EG-01|3|2', 'PRN-EG-01|3|3', 'PRN-EG-01|0|3')
        ((Import-Csv (Join-Path $Run 'events.csv')) | Where-Object App -eq 'chrome.exe').User | Should -Be 'user008'
        @(Get-Content (Join-Path $Run 'citrix.csv')).Count | Should -BeGreaterThan 1000
    }
    # Aussagen geaendert: die Simulation legt jetzt Rueckblick, Treiber und Warteschlangen an (Task 4)
    It 'ergaenzt Sitzung und Benutzer der Abstuerze ueber die PID und legt die Druckdateien an' {
        $ev = @(Import-Csv (Join-Path $Run 'events.csv'))
        $sec = $ev | Where-Object Group -eq 'security'
        $sec.Log | Should -Be @('defender', 'defender', 'applocker')
        $sec.Source | Should -Be @('Microsoft-Windows-Windows Defender', 'Microsoft-Windows-Windows Defender', 'Microsoft-Windows-AppLocker')
        @($ev | Where-Object Kind -eq 'crash' | ForEach-Object { '{0}|{1}|{2}' -f $_.App, $_.SessionId, $_.User }) | Should -Be @('chrome.exe|9|user008',
            'OUTLOOK.EXE|11|user010', 'OUTLOOK.EXE|12|user011', 'OUTLOOK.EXE|13|user012', 'spoolsv.exe|0|')
        @($ev | Where-Object Group -eq 'session' | ForEach-Object { '{0}|{1}|{2}' -f $_.Kind, $_.SessionId, $_.User }) | Should -Be @('logoff|15|user014',
            'logon|15|user014', 'disconnect|23|user022', 'reconnect|23|user022')
        $pr = $ev | Where-Object Group -eq 'profile'; $pr.User | Should -Be 'user014'; $pr.SessionId | Should -Be ''
        $b = @(Import-Csv (Join-Path $Run 'events_before.csv')); @($b.App) | Should -Be @('EXCEL.EXE', 'WINWORD.EXE', 'nexus.exe', 'nexus.exe', 'nexus.exe', 'simscan.exe')   # C1
        (Import-Csv (Join-Path $Run 'printdrivers.csv'))[0].Files | Should -Be 'hpsimgr.dll;hpsimui.dll'
        $q = @(Import-Csv (Join-Path $Run 'printqueues.csv') | Where-Object Queue -eq 'PRN-EG-01')
        ($q | Measure-Object { [int]$_.Jobs } -Maximum).Maximum | Should -Be 3
        [int]$q[-1].JobErrors - [int]$q[0].JobErrors | Should -Be 1
    }
    It 'liest ohne Rueckblick nichts vor dem Start' {                                                 # Review Focus 3
        # eine Quelle, deren Rueckblick ein Ereignis liefern wuerde (Fix-Runde 1, Minor 11)
        $capture = New-PatchedSource (Join-Path $TestDrive 'srcnolb') @'
function Get-WorkerPerfEventsBefore { param([int]$Days, [datetime]$Until)
    @{ Events = @([pscustomobject]@{ Time = $Until.AddMinutes(-5); Log = 'system'; Source = 'Sim'; EventId = 7031; Kind = 'service'; Text = 'vorher' }); Capped = @() } }
'@
        $run = (& $capture -Simulate -DurationMinutes 60 -EventLookbackDays 0 -OutputPath (Join-Path $TestDrive 'nolb') 6>$null) | Select-Object -Last 1
        @(Get-Content (Join-Path $run 'events_before.csv')).Count | Should -Be 1
        (Get-Content (Join-Path $run 'meta.json') -Raw | ConvertFrom-Json).EventLookbackDays | Should -Be 0
    }
    It 'bleibt unter 10 MB' { (Get-ChildItem $Run | Measure-Object Length -Sum).Sum | Should -BeLessThan 10MB }
    # Aussage geaendert: expected.json nennt auch die Ereignisvorfaelle (Task 4)
    It 'legt das Soll-Ergebnis ab' { @($Exp | Where-Object Type -ne 'ereignis').Count | Should -Be 8; $Exp[1].Key | Should -Be 'cpu' }
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
        $e.events.Count | Should -Be 241; $e.events.FirstMessage | Should -Be 'Testfehler im Ereignisprotokoll'    # Aussage geaendert (P1-R34): 240 Abrufe und der letzte zum Ende
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
        ($q.sourceErrors | Where-Object source -eq 'events').count | Should -Be 241                               # Aussage geaendert (P1-R34)
        ($q.sourceErrors | Where-Object source -eq 'events').label | Should -Be 'Ereignisprotokoll'
        ($q.sourceErrors | Where-Object source -eq 'fast').firstMessage | Should -Be 'Testfehler im schnellen Takt'
        ($q.sourceErrors | Where-Object source -eq 'fast').firstMs | Should -Be ($FailData.meta.start + 596000)
        $q.skippedTicks | Should -Be 1; $q.unreadable.ticks | Should -Be 0             # ein ausgefallener Takt ist eine Luecke, keine unlesbare Zeile
        @($FailData.events).Count | Should -Be 0
    }
}
Describe 'Rueckblick, Ereignisse der Messzeit und Drucken' {                       # Review Focus 3 und 4
    BeforeAll {
        # Eine nachlaessige Quelle: der Rueckblick liefert auch Ereignisse nach dem Start, die Messzeit liest einschliesslich
        # Since und ohne obere Grenze. Ereignisse bei -3600 s, -1 s, 0 s (genau der Start), +1 s, +30 s und +77 s (genau
        # die Grenze zwischen dem ersten und zweiten regulaeren Abruf: Takt 16 s nach dem verschobenen Beginn); bei +30 s zusaetzlich ein Absturz eines laufenden
        # Prozesses und einer, dessen PID in keinem Schnappschuss vorkommt; Abstuerze eines Prozesses 0, 1 und 14 s nach
        # seinem Ende. Der Rueckblick dauert 61 s Serverzeit (Fix-Runde 1, Important 2); die Warteschlangen brauchen bei
        # 361 s und die Ereignisse bei 391 s 300 ms (Spec 4.4: zaehlt zur Messdauer des Schnappschusses).
        $capture = New-PatchedSource (Join-Path $TestDrive 'srclb') @'
function Get-TestEvents {
    $p = @($script:WorkerPerfSimProcs | Where-Object { $_.SessionId -gt 1 -and $_.CreatedSec -lt 0 -and $_.EndSec -gt 3600 })[0]
    $script:TestPid = $p.Pid; $script:TestSid = $p.SessionId
    $gone = @($script:WorkerPerfSimProcs | Where-Object { $_.SessionId -gt 1 -and $_.EndSec -gt 300 -and $_.EndSec -lt 3000 })[0]
    foreach ($d in 0, 1, 14) {
        [pscustomobject]@{ Time = $script:WorkerPerfSimStart.AddSeconds($gone.EndSec + $d); Log = 'application'; Source = 'Application Error'; EventId = 1000; Level = 2; Group = 'app'; Kind = 'crash'
            App = $gone.Name; AppVersion = ''; Module = ''; ModuleVersion = ''; Code = ''; Pid = $gone.Pid; SessionId = $null; User = ''; Printer = ''; Driver = ''; Service = ''; Object = ''; Text = "end$d|$($gone.SessionId)" }
    }
    foreach ($sec in -3600, -1, 0, 1, 30, 77) {
        [pscustomobject]@{ Time = $script:WorkerPerfSimStart.AddSeconds($sec); Log = 'system'; Source = 'Sim'; EventId = 7031; Level = 2; Group = 'service'; Kind = 'service'
            App = ''; AppVersion = ''; Module = ''; ModuleVersion = ''; Code = ''; Pid = $null; SessionId = $null; User = ''; Printer = ''; Driver = ''; Service = 'Spooler'; Object = ''; Text = "t$sec" }
    }
    foreach ($x in @(@($p.Pid, 'crash-known'), @(99999, 'crash-unknown'))) {
        [pscustomobject]@{ Time = $script:WorkerPerfSimStart.AddSeconds(30); Log = 'application'; Source = 'Application Error'; EventId = 1000; Level = 2; Group = 'app'; Kind = 'crash'
            App = 'x.exe'; AppVersion = ''; Module = ''; ModuleVersion = ''; Code = ''; Pid = $x[0]; SessionId = $null; User = ''; Printer = ''; Driver = ''; Service = ''; Object = ''; Text = $x[1] }
    }
}
# wie unter Windows: das Warten stellt die Uhr nicht zurueck
$script:TestWait = ${function:Wait-WorkerPerfTick}
function Wait-WorkerPerfTick { param([datetime]$Until, [string]$StopFlagPath)
    if ($Until -gt $script:WorkerPerfSimNow) { & $script:TestWait -Until $Until -StopFlagPath $StopFlagPath } else { & $script:TestWait -Until $script:WorkerPerfSimNow -StopFlagPath $StopFlagPath } }
function Get-WorkerPerfEventsBefore { param([int]$Days, [datetime]$Until)
    $script:WorkerPerfSimNow = $script:WorkerPerfSimNow.AddSeconds(61)
    @{ Events = @(Get-TestEvents); Capped = @('system') } }
function Get-WorkerPerfEvents { param([datetime]$Since)
    if ((Get-WorkerPerfSimElapsed) -eq 391) { Start-Sleep -Milliseconds 300 }
    foreach ($e in @(Get-TestEvents)) { if ($e.Time -ge $Since) { $e } } }
function Get-WorkerPerfPrintDrivers { [pscustomobject]@{ Name = 'Sim PCL 6'; Manufacturer = 'Sim'; Version = '1.0'; Type = 3; Isolation = 'shared'; Files = @('a.dll', 'b.dll') } }
function Get-WorkerPerfPrintQueues {
    if ((Get-WorkerPerfSimElapsed) -eq 361) { Start-Sleep -Milliseconds 300 }
    [pscustomobject]@{ Queue = 'Drucker 1'; Jobs = 1; JobErrors = 2; NotReadyErrors = 3 } }
'@
        $script:LbRun = (& $capture -Simulate -DurationMinutes 60 -EventLookbackDays 3 -OutputPath (Join-Path $TestDrive 'lb') 6>$null) | Select-Object -Last 1
        $script:LbMeta = Get-Content (Join-Path $LbRun 'meta.json') -Raw | ConvertFrom-Json
        $script:LbBefore = @(Import-Csv (Join-Path $LbRun 'events_before.csv'))
        $script:LbEvents = @(Import-Csv (Join-Path $LbRun 'events.csv'))
    }
    It 'zaehlt jedes Ereignis genau einmal; der Rueckblick haelt nur Ereignisse bis zum Start' {
        $LbBefore.Text | Should -Be @('t-3600', 't-1', 't0')
        @($LbEvents | Where-Object Kind -eq 'service').Text | Should -Be @('t1', 't30', 't77')
        # ConvertFrom-Json liefert Zeiten je nach PowerShell-Version als DateTime oder als Text
        $start = $(if ($LbMeta.StartTime -is [datetime]) { [DateTimeOffset]$LbMeta.StartTime } else { [DateTimeOffset]::Parse($LbMeta.StartTime, [cultureinfo]::InvariantCulture) })
        $firstTick = [DateTimeOffset]::Parse((Get-Content (Join-Path $LbRun 'ticks.csv') -TotalCount 2)[1].Split(',')[1], [cultureinfo]::InvariantCulture)
        foreach ($b in $LbBefore) {
            $t = [DateTimeOffset]::Parse($b.Timestamp, [cultureinfo]::InvariantCulture)
            $t | Should -BeLessOrEqual $start; $t | Should -BeLessThan $firstTick
        }
    }
    It 'beginnt den Takt nach einem langsamen Rueckblick ohne ausgelassene Takte' {             # Fix-Runde 1, Important 2
        $LbMeta.SkippedTicks | Should -Be 0; $LbMeta.Ticks | Should -Be 1800; $LbMeta.EndReason | Should -Be 'duration'
        $lbSnaps = @(Import-Csv (Join-Path $LbRun 'snapshots.csv'))
        $lbSnaps[0].Kind | Should -Be 'K'; $lbSnaps[0].ElapsedSec | Should -Be $Snaps[0].ElapsedSec       # der erste regulaere Takt wie ohne Verzoegerung
        $lbSnaps[0].ElapsedSec | Should -Be '16'; @($lbSnaps | Where-Object Kind -in 'R', 'K').Count | Should -Be 240
    }
    It 'findet die Sitzung eines Prozesses, der vor seinem Absturzereignis endete (0, 1, 14 s)' {    # Fix-Runde 1, Important 1
        $ended = @($LbEvents | Where-Object { $_.Text -like 'end*' }); $ended.Count | Should -Be 3
        foreach ($e in $ended) {
            $sid = [int]$e.Text.Split('|')[1]
            [int]$e.SessionId | Should -Be $sid -Because $e.Text; $e.User | Should -Be ('user{0:d3}' -f ($sid - 1))
        }
    }
    It 'zaehlt das Lesen der Ereignisse und Warteschlangen zur Messdauer des Schnappschusses' {   # Fix-Runde 1, Spec 4.4
        $start = $(if ($LbMeta.StartTime -is [datetime]) { [DateTimeOffset]$LbMeta.StartTime } else { [DateTimeOffset]::Parse($LbMeta.StartTime, [cultureinfo]::InvariantCulture) })
        $snaps = @(Import-Csv (Join-Path $LbRun 'snapshots.csv'))
        foreach ($sec in 361, 391) {
            $row = @($snaps | Where-Object { $_.Kind -ne 'B' -and [Math]::Round(([DateTimeOffset]::Parse($_.Timestamp, [cultureinfo]::InvariantCulture) - $start).TotalSeconds) -eq $sec })
            $row.Count | Should -Be 1 -Because $sec; [double]$row[0].CollectMs | Should -BeGreaterOrEqual 300 -Because $sec
        }
    }
    It 'vermerkt Tage und unvollstaendige Protokolle in meta.json' {
        $LbMeta.EventLookbackDays | Should -Be 3; @($LbMeta.LookbackCapped) | Should -Be @('system')
    }
    It 'ergaenzt die Sitzung nur fuer den Prozess aus dem Schnappschuss' {
        $known = $LbEvents | Where-Object Text -eq 'crash-known'; $unknown = $LbEvents | Where-Object Text -eq 'crash-unknown'
        [int]$known.SessionId | Should -BeGreaterThan 1; $known.User | Should -Be ('user{0:d3}' -f ([int]$known.SessionId - 1))
        $unknown.SessionId | Should -Be ''; $unknown.User | Should -Be ''
    }
    It 'schreibt Treiberliste und Warteschlangen je regulaerem Schnappschuss' {
        @(Get-Content (Join-Path $LbRun 'printdrivers.csv')) | Should -Be @($WorkerPerfHeaders['printdrivers.csv'], 'Sim PCL 6,Sim,1.0,3,shared,a.dll;b.dll')
        $q = @(Import-Csv (Join-Path $LbRun 'printqueues.csv')); $q.Count | Should -Be 1                         # Aussage geaendert (M6): die Werte aendern sich nicht
        $q[0].Queue | Should -Be 'Drucker 1'; $q[0].NotReadyErrors | Should -Be '3'
    }
}
Describe 'Fehler der neuen Quellenaufrufe' {
    BeforeAll {
        $capture = New-PatchedSource (Join-Path $TestDrive 'srclbfail') @'
function Get-WorkerPerfEventsBefore { param([int]$Days, [datetime]$Until) throw 'Testfehler im Rueckblick' }
function Get-WorkerPerfPrintDrivers { throw 'Testfehler bei den Treibern' }
function Get-WorkerPerfPrintQueues { throw 'Testfehler bei den Warteschlangen' }
'@
        $out = @(& $capture -Simulate -DurationMinutes 60 -OutputPath (Join-Path $TestDrive 'lbfail') 6>$null 3>&1)
        $script:LfWarnings = @($out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $_.Message })
        $script:LfRun = [string]($out | Where-Object { $_ -is [string] } | Select-Object -Last 1)
        $script:LfMeta = Get-Content (Join-Path $LfRun 'meta.json') -Raw | ConvertFrom-Json
    }
    It 'vermerkt sie je Quelle, warnt einmal und misst weiter' {
        $e = $LfMeta.SourceErrors
        $e.eventsbefore.Count | Should -Be 1; $e.eventsbefore.FirstMessage | Should -Be 'Testfehler im Rueckblick'
        $e.printdrivers.Count | Should -Be 1; $e.printqueues.Count | Should -Be 240
        foreach ($word in 'Ereignisse vor der Messung', 'Druckertreiber', 'Druckwarteschlangen') { @($LfWarnings | Where-Object { $_ -like "*$word*" }).Count | Should -Be 1 -Because $word }
        $LfWarnings.Count | Should -Be 3; $LfMeta.EndReason | Should -Be 'duration'; $LfMeta.Ticks | Should -Be 1800
        @(Get-Content (Join-Path $LfRun 'events.csv')).Count | Should -Be 14                       # Aussage geaendert (Task 4): Kopfzeile und 13 Ereignisse des Drehbuchs
    }
    It 'nennt sie im Bericht mit ihren Texten' {
        $out = Join-Path $TestDrive 'lbfail.html'
        [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $LfRun -OutFile $out -RoleFile (New-SimRoleFile (Join-Path $TestDrive 'roles.lbfail.json')) 6>$null)
        $d = Get-ReportData $out
        # Aussage geaendert (Task 8): neben den acht Leistungsvorfaellen stehen die vier Ereignisvorfaelle der Messzeit im Bericht;
        # ohne Rueckblick und Treiberliste bleiben diese Teile leer
        @($d.incidents | Where-Object type -ne 'ereignis').Count | Should -Be 8; @($d.incidents | Where-Object type -eq 'ereignis').Count | Should -Be 4
        @($d.before.incidents).Count | Should -Be 0; @($d.print.drivers).Count | Should -Be 0
        $labels = @{}; foreach ($e in @($d.quality.sourceErrors)) { $labels[$e.source] = $e.label }
        $labels['eventsbefore'] | Should -Be 'Ereignisse vor der Messung'; $labels['printdrivers'] | Should -Be 'Druckertreiber'; $labels['printqueues'] | Should -Be 'Druckwarteschlangen'
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
Describe 'Ereignisse, die Windows spaet sichtbar macht, und die letzten Sekunden der Aufzeichnung (P1-R34)' {
    BeforeAll {
        # Ein Absturz mit dem Zeitstempel 299 s wird erst ab 302 s sichtbar (er liegt vor dem Abruf bei 300 s, erscheint aber
        # erst danach); ein Absturz bei 1208 s ist sofort sichtbar. Die Aufzeichnung endet ueber stop.flag bei 1210 s, nach
        # dem letzten regulaeren Abruf bei 1200 s. Die Quelle liest bis jetzt, ohne obere Grenze.
        $capture = New-PatchedSource (Join-Path $TestDrive 'srclate') @'
$script:TestEvents = ${function:Get-WorkerPerfEvents}
$script:TestLate = $null
function Get-WorkerPerfEvents { param([datetime]$Since)
    & $script:TestEvents -Since $Since
    if ($null -eq $script:TestLate) {
        $c = Read-WorkerPerfEventConfig $script:WorkerPerfSimEventFile
        $script:TestLate = @(@{ Visible = 302; E = (New-WorkerPerfSimCrash $c 299 'spaet.exe' '1.0' 'spaet.dll' '1.0' '0xc0000005') },
            @{ Visible = 1208; E = (New-WorkerPerfSimCrash $c 1208 'zuletzt.exe' '1.0' 'zuletzt.dll' '1.0' '0xc0000005') })
    }
    foreach ($x in $script:TestLate) {
        if ((Get-WorkerPerfSimElapsed) -ge $x.Visible -and $script:WorkerPerfSimStart.AddSeconds($x.E.Sec) -gt $Since) { ConvertTo-WorkerPerfSimEventRecord $x.E }
    }
}
$script:TestWait = ${function:Wait-WorkerPerfTick}
function Wait-WorkerPerfTick { param([datetime]$Until, [string]$StopFlagPath)
    $r = & $script:TestWait -Until $Until -StopFlagPath $StopFlagPath
    if (-not [string]::IsNullOrEmpty($StopFlagPath) -and (Get-WorkerPerfSimElapsed) -ge 1210) { return $true }
    $r
}
'@
        $script:LateRun = (& $capture -Simulate -DurationMinutes 60 -OutputPath (Join-Path $TestDrive 'late') 6>$null) | Select-Object -Last 1
        $script:LateEvents = @(Import-Csv (Join-Path $LateRun 'events.csv'))
        $script:LateMeta = Get-Content (Join-Path $LateRun 'meta.json') -Raw | ConvertFrom-Json
    }
    It 'schreibt ein spaet sichtbares Ereignis mit frueherem Zeitstempel genau einmal' {
        @($LateEvents | Where-Object App -eq 'spaet.exe').Count | Should -Be 1
    }
    It 'nimmt ein Ereignis der letzten Sekunden vor dem Ende auf' {
        $LateMeta.EndReason | Should -Be 'stopflag'
        @($LateEvents | Where-Object App -eq 'zuletzt.exe').Count | Should -Be 1
    }
    It 'schreibt auch die Ereignisse des Drehbuchs bis zum Ende je einmal' {
        @($LateEvents | Where-Object App -eq 'chrome.exe').Count | Should -Be 1
        @($LateEvents | Group-Object { $_.Timestamp + '|' + $_.App + '|' + $_.EventId } | Where-Object Count -gt 1).Count | Should -Be 0
    }
}
