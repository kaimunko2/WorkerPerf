BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1')
    $script:Capture = Join-Path $PSScriptRoot '../src/Start-WorkerPerfCapture.ps1'
    $script:Console = Join-Path $TestDrive 'ho.console.txt'
    $script:Run = Invoke-SimHealthOnly (Join-Path $TestDrive 'ho') @{} $Console
    function Get-Meta([string]$Dir) { Get-Content (Join-Path $Dir 'meta.json') -Raw | ConvertFrom-Json }
}
Describe 'Schnelllauf -HealthOnly' {
    It 'schreibt Zustandsbild, Rueckblick, Treiberliste, die Kopie der Anwendungsliste und meta.json, sonst nichts' {
        @(Get-ChildItem $Run | ForEach-Object Name | Sort-Object) | Should -Be @('apps.json', 'events_before.csv', 'health.json', 'meta.json', 'printdrivers.csv')
        $m = Get-Meta $Run; $m.HealthOnly | Should -BeTrue; $m.EndReason | Should -Be 'healthonly'; $m.Ticks | Should -Be 0; $m.Snapshots | Should -Be 0; $m.SchemaVersion | Should -Be 3
        @($m.Skip).Count | Should -Be 0; $m.EventLookbackDays | Should -Be 7; $m.Simulated | Should -BeTrue; @($m.SourceErrors.PSObject.Properties).Count | Should -Be 0
        @(Import-Csv (Join-Path $Run 'events_before.csv')).Count | Should -Be 6; @(Import-Csv (Join-Path $Run 'printdrivers.csv')).Count | Should -Be 3
        (Get-Content (Join-Path $Run 'health.json') -Raw | ConvertFrom-Json).FormatVersion | Should -Be 1
        $out = Get-Content $Console -Raw
        $out | Should -Match 'WorkerPerf-Schnelllauf laeuft: [^\r\n]+\r?\nGelesen wird: Zustandsbild, Rueckblick, Treiberliste\r?\nNicht gelesen \(-Skip\): keine\r?\n'
        $out | Should -Match 'Zustandsbild: 10 Bereiche gelesen'; $out | Should -Match 'Schnelllauf beendet: '; $out | Should -Not -Match 'Takt'
        $out | Should -Not -Match 'ohne Zustandsbild'; [string]$m.EndMessage | Should -Be ''
        # Sources nennt nur, was der Schnelllauf liest: die Protokolle des Rueckblicks, die Treiberliste, das Zustandsbild (Fix-Runde 1, Punkt 2)
        $names = @($m.Sources.PSObject.Properties.Name)
        @($names | Where-Object { $_ -notlike 'events.*' }) | Should -Be @('print.drivers', 'health'); @($names | Where-Object { $_ -like 'events.*' }).Count | Should -BeGreaterThan 0
    }
    It 'ruft die Quelle fuer nichts auf, was zur Messung gehoert' {
        $throwing = (@('Get-WorkerPerfFastSample', 'Get-WorkerPerfSnapshot', 'Get-WorkerPerfServices', 'Get-WorkerPerfEvents', 'Get-WorkerPerfPrintQueues', 'Start-WorkerPerfProbes',
                'Receive-WorkerPerfProbes', 'Wait-WorkerPerfTick') | ForEach-Object { "function $_ { throw 'Testaufruf $_' }" }) -join "`n"
        $run = (& (New-PatchedSource (Join-Path $TestDrive 'srcho') $throwing) -Simulate -HealthOnly -OutputPath (Join-Path $TestDrive 'ho2') 6>$null 3>$null) | Select-Object -Last 1
        (Get-Meta $run).EndReason | Should -Be 'healthonly'; @((Get-Meta $run).SourceErrors.PSObject.Properties).Count | Should -Be 0
    }
    It 'beachtet -Skip Rueckblick und -Skip Drucken' {
        $con = Join-Path $TestDrive 'ho3.console.txt'
        $run = Invoke-SimHealthOnly (Join-Path $TestDrive 'ho3') @{ Skip = @('Drucken', 'Rueckblick') } $con
        @(Get-ChildItem $run | ForEach-Object Name | Sort-Object) | Should -Be @('apps.json', 'health.json', 'meta.json'); @((Get-Meta $run).Skip) | Should -Be @('Rueckblick', 'Drucken')
        (Get-Content $con -Raw) | Should -Match 'Gelesen wird: Zustandsbild\r?\nNicht gelesen \(-Skip\): Rueckblick, Drucken\r?\n'
    }
    It 'lehnt -Skip Zustand und die Parameter der Messung ab, bevor etwas angelegt wird' {
        $dir = Join-Path $TestDrive 'no'
        # die vollen Meldungen (Fix-Runde 1, Punkt 5); -NoCitrix:$false ist angegeben und wird darum abgelehnt
        $refused = '-HealthOnly liest nur das Zustandsbild, den Rueckblick und die Treiberliste; nicht zusammen mit: '
        { & $Capture -Simulate -HealthOnly -Skip Zustand -OutputPath $dir 6>$null } | Should -Throw '-HealthOnly und -Skip Zustand schliessen sich aus: der Schnelllauf besteht aus dem Zustandsbild.'
        { & $Capture -Simulate -HealthOnly -DurationMinutes 60 -IntervalSeconds 30 -OutputPath $dir 6>$null } | Should -Throw ($refused + '-IntervalSeconds, -DurationMinutes.')
        { & $Capture -Simulate -HealthOnly -NoCitrix -OutputPath $dir 6>$null } | Should -Throw ($refused + '-NoCitrix.')
        { & $Capture -Simulate -HealthOnly -NoCitrix:$false -OutputPath $dir 6>$null } | Should -Throw ($refused + '-NoCitrix.')
        Test-Path $dir | Should -BeFalse
    }
    It 'nimmt eine andere Anwendungsliste an und liest deren vierte Anwendung ohne Aenderung am Code' {
        $run = Invoke-SimHealthOnly (Join-Path $TestDrive 'ho5') @{ AppsFile = (New-TestAppFile $TestDrive) }
        $rows = @((Get-Content (Join-Path $run 'health.json') -Raw | ConvertFrom-Json).Areas.apps.Values.'apps.probes'.Value)
        @($rows | Where-Object App -eq 'simapp').Count | Should -Be 4; ($rows | Where-Object { $_.App -eq 'simapp' -and $_.Id -eq 'installed' }).Value | Should -BeFalse     # Review Focus 3
        @($rows | Where-Object { $_.App -eq 'simapp' -and $_.Id -ne 'installed' -and $_.Reason -ne 'notInstalled' }).Count | Should -Be 0
        (Get-Content (Join-Path $run 'apps.json') -Raw) | Should -Match '"simapp"'
    }
    It 'schreibt im Schnelllauf kein expected.json und keine Kopie der Schwellen' {
        foreach ($f in 'expected.json', 'thresholds.json', 'ticks.csv', 'stop.flag') { Test-Path (Join-Path $Run $f) | Should -BeFalse -Because $f }
    }
    It 'liest und kopiert eine relativ angegebene Anwendungsliste aus dem Ordner der PowerShell' {     # Review Task 8, Punkt 1
        $here = Join-Path $TestDrive 'rel'; [void](New-Item -ItemType Directory -Path $here -Force)
        $apps = New-TestAppFile $here
        $oldCwd = [Environment]::CurrentDirectory
        Push-Location $here
        try {
            # der Prozess steht anderswo als die PowerShell: ein relativer Pfad gilt fuer den Ordner der PowerShell
            [Environment]::CurrentDirectory = $PSScriptRoot
            $run = Invoke-SimHealthOnly 'out' @{ AppsFile = 'apps.test.json' }
        }
        finally { Pop-Location; [Environment]::CurrentDirectory = $oldCwd }
        $run | Should -BeLike (Join-Path $here 'out*')
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $run 'apps.json'))) | Should -Be ([Convert]::ToBase64String([IO.File]::ReadAllBytes($apps)))
        $rows = @((Get-Content (Join-Path $run 'health.json') -Raw | ConvertFrom-Json).Areas.apps.Values.'apps.probes'.Value)
        @($rows | Where-Object App -eq 'simapp').Count | Should -Be 4
    }
    It 'sagt, wenn das Zustandsbild fehlt (<Name>)' -TestCases @(                         # Fix-Runde 1, Punkt 1
        @{ Name = 'Lesen wirft'; Code = "function Get-WorkerPerfHealth { throw 'Testfehler Zustandsbild' }"; Reason = 'Das Lesen des Zustandsbilds ist gescheitert (RuntimeException).' }
        @{ Name = 'nichts geliefert'; Code = 'function Get-WorkerPerfHealth { $null }'; Reason = 'Die Datenquelle hat kein Zustandsbild geliefert.' }
    ) {
        $key = $Name.Replace(' ', '')
        $cap = New-PatchedSource (Join-Path $TestDrive "src$key") $Code
        $out = @(& $cap -Simulate -HealthOnly -OutputPath (Join-Path $TestDrive "ohne$key") 3>&1 6>&1 | ForEach-Object { [string]$_ })
        $run = $out[-1]
        Test-Path -LiteralPath (Join-Path $run 'meta.json') | Should -BeTrue                    # der Ordner wird ausgegeben wie bisher
        $out[-2] | Should -Be "Schnelllauf beendet ohne Zustandsbild: $run"; $out[-3] | Should -Be $Reason
        @($out | Where-Object { $_ -like '*laeuft weiter*' }) | Should -BeNullOrEmpty
        @(Get-ChildItem $run | ForEach-Object Name | Sort-Object) | Should -Be @('apps.json', 'events_before.csv', 'meta.json', 'printdrivers.csv')
        $m = Get-Meta $run; $m.EndReason | Should -Be 'healthonly'; $m.EndMessage | Should -Be $Reason
        if ($Name -eq 'Lesen wirft') {
            $m.SourceErrors.health.FirstMessage | Should -Be 'Testfehler Zustandsbild'
            $out | Should -Contain "Datenquelle 'Zustandsbild' meldet einen Fehler; der Schnelllauf liest den Rest: Testfehler Zustandsbild"
        }
        else { @($m.SourceErrors.PSObject.Properties).Count | Should -Be 0 }
    }
    It 'meldet eine gescheiterte Konsolenzeile nicht als fehlende health.json' {                  # Nachpruefung Task 9, Lader Task 10 (f)
        $cap = New-PatchedSource (Join-Path $TestDrive 'srcline') "function Format-WorkerPerfHealthLine { throw 'Testfehler Zeile' }"
        $out = @(& $cap -Simulate -HealthOnly -OutputPath (Join-Path $TestDrive 'line') 3>&1 6>&1 | ForEach-Object { [string]$_ })
        $run = $out[-1]
        Test-Path -LiteralPath (Join-Path $run 'health.json') -PathType Leaf | Should -BeTrue
        $out[-2] | Should -Be "Schnelllauf beendet: $run"; $out | Should -Contain 'Zustandsbild: Testfehler Zeile'
        @($out | Where-Object { $_ -like '*konnte nicht geschrieben werden*' -or $_ -like '*ohne Zustandsbild*' }) | Should -BeNullOrEmpty
        $m = Get-Meta $run; [string]$m.EndMessage | Should -Be ''; @($m.SourceErrors.PSObject.Properties).Count | Should -Be 0
    }
    It 'nennt nach Strg+C den Grund des Endes in der letzten Zeile' {                       # Fix-Runde 1, Punkt 1
        # Strg+C erscheint als PipelineStoppedException im Lesen des Zustandsbilds; sie beendet auch den Aufrufer, darum
        # laeuft der Schnelllauf in einem eigenen Prozess
        $cap = New-PatchedSource (Join-Path $TestDrive 'srcstop') 'function Get-WorkerPerfHealth { throw (New-Object System.Management.Automation.PipelineStoppedException) }'
        $dir = Join-Path $TestDrive 'stop'
        $out = @(& (Get-Process -Id $PID).Path -NoProfile -Command "& '$cap' -Simulate -HealthOnly -OutputPath '$dir' 3>&1 6>&1 | ForEach-Object { [string]`$_ }")
        $run = @(Get-ChildItem $dir -Directory)[0].FullName
        $out[-1] | Should -Be "Schnelllauf beendet (interrupted): $run"
        (Get-Meta $run).EndReason | Should -Be 'interrupted'
    }
    It 'liest eine relativ angegebene Anwendungsliste aus dem Dateisystem, auch wenn die PowerShell auf Env: steht' {   # Fix-Runde 1, Punkt 7
        $here = Join-Path $TestDrive 'relenv'; [void](New-Item -ItemType Directory -Path $here -Force)
        $apps = New-TestAppFile $here
        $oldCwd = [Environment]::CurrentDirectory
        Push-Location $here
        try {
            [Environment]::CurrentDirectory = $PSScriptRoot
            Set-Location Env:
            $run = Invoke-SimHealthOnly (Join-Path $TestDrive 'relenvout') @{ AppsFile = 'apps.test.json' }
        }
        finally { Pop-Location; [Environment]::CurrentDirectory = $oldCwd }
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $run 'apps.json'))) | Should -Be ([Convert]::ToBase64String([IO.File]::ReadAllBytes($apps)))
        $rows = @((Get-Content (Join-Path $run 'health.json') -Raw | ConvertFrom-Json).Areas.apps.Values.'apps.probes'.Value)
        @($rows | Where-Object App -eq 'simapp').Count | Should -Be 4
    }
}
Describe 'Zustandsbericht aus dem Schnelllauf' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/WorkerPerf.Load.ps1')
        $script:ReportScript = Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1'; $script:Html = Join-Path $TestDrive 'ho.html'
        $script:Out = @(& $ReportScript -Path $Run -OutFile $Html 6>&1); $script:H = Get-ReportData $Html
    }
    It 'entsteht ohne Fehler und traegt nur Kopf, Zustandsbild, Rueckblick, Treiberliste und Weggelassenes' {
        @($H.PSObject.Properties.Name) | Should -Be @('meta', 'quality', 'health', 'before', 'print', 'skipped')
        $H.meta.healthOnly | Should -BeTrue; $H.meta.endReason | Should -Be 'healthonly'; $H.meta.reportKind | Should -Be 'Zustandsbericht ohne Messung'; $H.meta.computer | Should -Be 'SIM-VDA01'
        $H.meta.ticks | Should -Be 0; $H.meta.start | Should -Be $H.meta.end; $H.meta.start | Should -BeGreaterThan 0
        # Literal angepasst: 208 Werte seit Task 14s und den Proben der Anwendungsliste (Task 16), nicht 202
        $H.health.state | Should -Be 'read'; $H.health.summary.text | Should -Be '1 Bereich zum Handeln, 5 zum Prüfen, 5 in Ordnung'; @($H.health.raw).Count | Should -Be 209
        $H.health.eventsReachText | Should -Match '\d\d\.\d\d\.\d{4}'; $H.health.environmentText | Should -Match 'nicht persistent'      # ab wann die Protokolle reichen: steht im Zustandsbericht ueber dem Rueckblick
        $H.before.status | Should -Be 'read'; @($H.before.incidents).Count | Should -Be 4; @($H.before.incidents | Where-Object { $null -eq $_.guide }).Count | Should -Be 0
        @($H.print.drivers).Count | Should -Be 3; @($H.print.queues).Count | Should -Be 0; $H.print.involvedFrom | Should -Be 'lookback'; @($H.skipped).Count | Should -Be 0
        ($H | ConvertTo-Json -Depth 20) | Should -Not -Match 'keine Vorf|Kein Vorfall|Keine Störung'
        ($Out | Out-String) | Should -Match 'Zustandsbericht erstellt'; ($Out | Out-String) | Should -Not -Match 'Takte'
    }
    It 'bleibt ohne Rueckblick und ohne Treiberliste ehrlich' {   # Review Focus 5
        $run = Invoke-SimHealthOnly (Join-Path $TestDrive 'ho4') @{ Skip = @('Rueckblick', 'Drucken') }; $f = Join-Path $TestDrive 'ho4.html'
        [void](& $ReportScript -Path $run -OutFile $f 6>$null); $d = Get-ReportData $f
        @($d.skipped.id) | Should -Be @('Rueckblick', 'Drucken'); $d.before.status | Should -Be 'off'; @($d.print.drivers).Count | Should -Be 0; $d.print.involvedFrom | Should -Be 'none'
        $g = @{}; foreach ($a in $d.health.areas) { foreach ($c in $a.checks) { $g[$c.id] = $c } }
        $g['print.driversInSpooler'].grade | Should -Be 'unknown'; $g['events.crashes'].grade | Should -Be 'unknown'; $g['profile.containerFull'].grade | Should -Be 'act'
        $g['events.crashes'].why | Should -Match 'Rückblick'; ($d.health.areas | Where-Object id -eq 'events').grade | Should -Be 'ok'
        $g['print.isolationOff'].note | Should -Be ''; $g['sessions.tempProfiles'].grade | Should -Be 'ok'
    }
    It 'nennt eine Anwendung der Liste, die nicht installiert ist, im Bereich und zaehlt sie nicht' {   # Review Focus 3
        $appFile = New-TestAppFile $TestDrive; $run = Invoke-SimHealthOnly (Join-Path $TestDrive 'ho6') @{ AppsFile = $appFile }; $f = Join-Path $TestDrive 'ho6.html'
        [void](& $ReportScript -Path $run -OutFile $f -AppsFile $appFile 6>$null); $a = (Get-ReportData $f).health.areas | Where-Object id -eq 'apps'
        ($a.apps | Where-Object key -eq 'simapp').state | Should -Be 'notInstalled'; ($a.apps | Where-Object key -eq 'simapp').text | Should -Be 'Sim-Fachanwendung: nicht installiert'
        # Literal angepasst: drei zum Pruefen seit der Korrekturrunde 1 von Task 14c (ZB-R57, apps.edgeWebView2Update), nicht zwei
        @($a.checks | Where-Object { $_.app -eq 'simapp' }).Count | Should -Be 0; $a.countsText | Should -Be '3 zum Prüfen'      # der ausgelieferte Katalog hat keine Pruefung fuer sie
        # dieselbe Aufzeichnung mit der ausgelieferten Liste ausgewertet: die vierte Anwendung kommt nicht vor
        [void](& $ReportScript -Path $run -OutFile $f 6>$null); @((Get-ReportData $f).health.areas | Where-Object id -eq 'apps' | ForEach-Object { $_.apps.key } | Sort-Object) | Should -Be @('edge', 'office', 'teams')
        { & $ReportScript -Path $run -OutFile $f -AppsFile (Join-Path $TestDrive 'keine.json') 6>$null } | Should -Throw '*keine.json*'      # die Meldung kommt vom Leser des gefuehrten Berichts: er liest die Datei zuerst
    }
    It 'maskiert den Zustandsbericht wie den Bericht' {
        $f = Join-Path $TestDrive 'ho-masked.html'; [void](& $ReportScript -Path $Run -OutFile $f -Mask Alles 6>$null); $d = Get-ReportData $f
        $json = $d | ConvertTo-Json -Depth 20
        foreach ($n in 'user0\d\d', 'SIM-VDA01', 'CONTOSO', 'ddc0\d', 'Inventarlauf', 'fd00:20::10') { $json | Should -Not -Match $n -Because $n }
        $d.meta.mask | Should -Be 'Alles'; $d.meta.computer | Should -Be 'Server 01'; $d.health.summary.text | Should -Be $H.health.summary.text
    }
    It 'lehnt die Parameter der Messung ab' {
        { & $ReportScript -Path $Run -OutFile (Join-Path $TestDrive 'x.html') -From ([datetime]::Now) 6>$null } | Should -Throw '*Schnelllauf*-From*'
        { & $ReportScript -Path $Run -OutFile (Join-Path $TestDrive 'x.html') -FocusUser 'user003' -TopProcesses 20 6>$null } | Should -Throw '*Schnelllauf*nicht zusammen mit: -FocusUser, -TopProcesses.'
        { & $ReportScript -Path $Run -OutFile (Join-Path $TestDrive 'x.html') -ReportedTime ([datetime]::Now) 6>$null } | Should -Throw 'Die Aufzeichnung ist ein Schnelllauf ohne Messung; nicht zusammen mit: -ReportedTime.'
        Test-Path (Join-Path $TestDrive 'x.html') | Should -BeFalse
    }
    It 'gibt den Rueckblick-Vorfaellen die Felder des gefuehrten Berichts wie im Bericht einer Messung' {
        $inc = @($H.before.incidents)
        @($inc | ForEach-Object { [int]$_.rank } | Sort-Object) | Should -Be @(1..$inc.Count)
        foreach ($i in $inc) {
            $i.guide.situation | Should -Not -BeNullOrEmpty; $i.copy.named | Should -Match 'SIM-VDA01'; $i.copy.anonymous | Should -Not -Match 'SIM-VDA01'
            $i.PSObject.Properties.Name | Should -Contain 'health'
        }
        @($inc | Where-Object { @($_.health).Count -gt 0 }).Count | Should -BeGreaterThan 0          # ein Vorfall verweist auf eine Pruefung des Zustandsbilds
        foreach ($a in $H.health.areas) { $a.copy.named | Should -Not -BeNullOrEmpty; $a.copy.anonymous | Should -Not -Match 'SIM-VDA01' }
        ($Out | Out-String) | Should -Match ('  ' + [regex]::Escape($H.health.summary.text))
    }
    It 'nennt die Rueckblick-Vorfaelle im Schnelllauf "vor dem Lesen" und laesst das Wort der Messung in der Antwort nicht stehen' {   # ZB-R65
        foreach ($i in @($H.before.incidents)) {
            $i.guide.userView | Should -Match '^Vor dem Lesen aufgetreten \(Zahl der Ereignisse: \d+\)\.$'
            ($i.guide | ConvertTo-Json -Depth 10) | Should -Not -Match 'Vor der Messung aufgetreten'
            ($i.copy.named + $i.copy.anonymous) | Should -Not -Match 'Vor der Messung aufgetreten'; $i.copy.named | Should -Match 'Vor dem Lesen aufgetreten'
        }
        $H.PSObject.Properties.Name | Should -Not -Contain 'guidance'
        $g = Get-Content (Join-Path $PSScriptRoot '../src/guidance.de.json') -Raw | ConvertFrom-Json
        $g.userView.before | Should -Be 'Vor der Messung aufgetreten (Zahl der Ereignisse: {count}); für diese Zeit liegen keine Messwerte vor.'
        $g.userView.beforeQuick | Should -Be 'Vor dem Lesen aufgetreten (Zahl der Ereignisse: {count}).'      # ZB-R70/Minor 10: the sentence about the missing values stands once, in the section's intro
    }
    It 'nennt die Pruefschritte der Rueckblick-Vorfaelle im Schnelllauf ohne Messung, Lagebild und Reiter, die es dort nicht gibt' {   # ZB-R70
        $steps = New-Object System.Collections.Generic.List[string]
        foreach ($i in @($H.before.incidents)) { foreach ($c in @($i.guide.checks)) { $steps.Add($c.text + ' | ' + $c.where + ' | ' + $c.sign) }; $steps.Add($i.copy.named); $steps.Add($i.copy.anonymous) }
        $steps.Count | Should -BeGreaterThan 0
        $all = $steps -join "`n"
        $all | Should -Not -Match 'seit Beginn der Messung|Vorfälle der Messzeit|während der Messung|Lagebild|„Vor der Messung“|Reiter „Ereignisse“'
        $all | Should -Match 'nach dem Lesen wieder aufgetreten ist \(zum Beispiel mit einem neuen Schnelllauf\)'; $all | Should -Match 'Bereich „Vor dem Lesen“'
        # the catalogue keeps the wording of both reports side by side, in fields the measurement path drops
        $g = Get-Content (Join-Path $PSScriptRoot '../src/guidance.de.json') -Raw | ConvertFrom-Json
        $g.situations.crash.checks | Where-Object { $_.when -contains 'before' -and $_.text -match 'seit Beginn der Messung' } | ForEach-Object { $_.textQuick | Should -Be 'Prüfen, ob der Absturz nach dem Lesen wieder aufgetreten ist (zum Beispiel mit einem neuen Schnelllauf)'; $_.signQuick | Should -Be 'Absturz derselben Anwendung auch nach dem Lesen' }
    }
    It 'ordnet jedes Textfeld des Zustandsberichts im Bestand tests/MaskCensus.json ein' {                   # Global Constraints, Maskierung
        $file = Get-Content (Join-Path $PSScriptRoot 'MaskCensus.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $marks = @{}; foreach ($p in $file.fields.PSObject.Properties) { $marks[$p.Name] = [string]$p.Value }
        $marks['meta.reportKind'] | Should -Be 'composed'
        # die Berichtsdaten, wie das Skript sie bildet (in einem Kindbereich punktweise ausgefuehrt, der $data behaelt)
        $quick = & { $null = . $ReportScript -Path $Run -OutFile (Join-Path $TestDrive 'census.html') 6>$null; $data }
        $paths = New-Object 'System.Collections.Generic.SortedSet[string]' ([StringComparer]::Ordinal)
        $walk = { param($Value, [string]$Path)
            if ($null -eq $Value -or $Value -is [ValueType] -or $Value -is [System.Text.StringBuilder]) { return }
            if (@($file.subtrees) -ccontains $Path) { [void]$paths.Add($Path); return }
            if ($Value -is [string]) { [void]$paths.Add($Path); return }
            if ($Value -is [System.Collections.IDictionary]) { foreach ($k in @($Value.Keys)) { & $walk $Value[$k] ($(if ($Path) { "$Path.$k" } else { [string]$k })) }; return }
            foreach ($x in $Value) { & $walk $x "$Path[]" } }
        & $walk $quick ''
        $paths.Count | Should -BeGreaterThan 50; $paths | Should -Contain 'meta.reportKind'
        @($paths | Where-Object { -not $marks.ContainsKey($_) } | ForEach-Object { "neues Textfeld $_ : in tests/MaskCensus.json einordnen" }) | Should -BeNullOrEmpty
    }
    It 'laesst im maskierten Zustandsbericht keinen Namen und keinen Freitext des Servers stehen' {          # Zusatz d (Kanarienvoegel wie in Task 16)
        $run = Invoke-SimHealthOnly (Join-Path $TestDrive 'hoc'); $canary = Add-HealthCanaries $run
        $bf = Join-Path $run 'events_before.csv'; $lines = [IO.File]::ReadAllLines($bf); $ix = [array]::IndexOf($lines[0].Split(','), 'Text')
        for ($i = 1; $i -lt $lines.Length; $i++) {
            $f = [string[]]@(Split-WorkerPerfCsvLine $lines[$i]); $f[$ix] = 'Meldung CANARYBEF'
            $lines[$i] = [string]::Join(',', [string[]]@($f | ForEach-Object { if ($_ -match '[",]') { '"' + $_.Replace('"', '""') + '"' } else { $_ } }))
        }
        [IO.File]::WriteAllLines($bf, $lines)
        # the copied texts of meta.json the health report carries: the end message, the first message of a failed source
        # call (quality.sourceErrors) and the reason of a source that is not available (quality.sources), as in Mask.Tests
        $mf = Join-Path $run 'meta.json'; $m = [IO.File]::ReadAllText($mf).Replace('"EndMessage": null', '"EndMessage": "Ende CANARYEND"')
        $m = $m.Replace('"SourceErrors": {}', '"SourceErrors": { "proc.info": { "Count": 2, "FirstTime": "2026-11-12T11:00:00.0000000+00:00", "FirstMessage": "Fehler CANARYERR" } }')
        $m = $m.Replace('"Sources": {', '"Sources": { "cpu.steal": { "Available": false, "Detail": "Grund CANARYSRC" },')
        [IO.File]::WriteAllText($mf, $m)
        foreach ($t in 'CANARYEND', 'CANARYERR', 'CANARYSRC') { $m | Should -Match $t }
        $plain = Join-Path $TestDrive 'hoc-plain.html'; [void](& $ReportScript -Path $run -OutFile $plain 6>$null)
        $strings = New-Object System.Collections.Generic.List[string]
        $collect = { param($Value) if ($null -eq $Value -or $Value -is [ValueType]) { return }; if ($Value -is [string]) { $strings.Add($Value); return }
            if ($Value -is [System.Collections.IEnumerable]) { foreach ($x in $Value) { & $collect $x }; return }; foreach ($q in $Value.PSObject.Properties) { & $collect $q.Value } }
        $pd = Get-ReportData $plain; & $collect $pd; $all = $strings -join "`n"
        foreach ($t in @($canary.Free) + @($canary.Names) + @($canary.Plain.Values) + 'CANARYHER', 'CANARYBEF', 'CANARYEND', 'CANARYERR', 'CANARYSRC') { $all.Contains($t) | Should -BeTrue -Because "$t im unmaskierten Bericht" }
        @($pd.quality.sourceErrors.firstMessage) | Should -Contain 'Fehler CANARYERR'; @($pd.quality.sources | Where-Object id -eq 'cpu.steal').detail | Should -Be 'Grund CANARYSRC'
        # the versions without names never quote free text or a name of the server (P3-R44): lookback incidents, areas, checks
        $anonymous = @(@($pd.before.incidents) | ForEach-Object { $_.copy.anonymous }) + @(foreach ($a in $pd.health.areas) { $a.copy.anonymous; foreach ($c in $a.checks) { $c.copy.anonymous } })
        $anonymous.Count | Should -BeGreaterThan 80
        foreach ($c in $anonymous) { $c | Should -Not -Match 'CANARY|kanari|SIM-VDA01' }
        foreach ($level in 'Personen', 'Alles') {
            $file = Join-Path $TestDrive "hoc-$level.html"; [void](& $ReportScript -Path $run -OutFile $file -Mask $level 6>$null)
            $text = [IO.File]::ReadAllText($file); $text | Should -Not -Match 'CANARY' -Because $level; $text | Should -Not -Match 'KANINSTANZ|KanFirmaAgent' -Because $level
            if ($level -eq 'Alles') {
                $text | Should -Not -Match 'kanari|SIM-VDA01'
                # die Zuordnungsdatei entsteht wie im Bericht einer Messung
                $map = Join-Path $TestDrive 'hoc.map.json'; [void](& $ReportScript -Path $run -OutFile $file -Mask $level -MaskMapFile $map 6>$null)
                @((Get-Content $map -Raw | ConvertFrom-Json).entries | Where-Object { $_.name -eq 'SIM-VDA01' }).replacement | Should -Be 'Server 01'
                $strings.Clear(); & $collect (Get-ReportData $file); $all = $strings -join "`n"
                foreach ($t in $canary.Names) { $all.Contains($t) | Should -BeFalse -Because $t }
                # the plain tokens left are exactly those of the fields the masking keeps by design (as in Mask.Tests)
                $keep = Get-HealthCanaryKeep
                $left = @(foreach ($place in $canary.Plain.Keys) { if ($all.Contains($canary.Plain[$place])) { $place } })
                @($left | Where-Object { $keep -notcontains $_ }) -join ', ' | Should -Be '' -Because 'nicht eingeordnete Textfelder bleiben stehen'
                @($keep | Where-Object { $left -notcontains $_ }) -join ', ' | Should -Be '' -Because 'die Liste nennt nur Felder, die stehen bleiben'
            }
        }
    }
    It 'gibt dem Bericht einer Messung meta.healthOnly falsch und laesst seine Felder' {
        $cap = Invoke-SimCapture (Join-Path $TestDrive 'messung'); $f = Join-Path $TestDrive 'messung.html'
        $o = @(& $ReportScript -Path $cap -OutFile $f 6>&1); $d = Get-ReportData $f
        # ZB-R65: the report of a measurement keeps its wording and its catalogue as it was
        $d.guidance.userView.before | Should -Be 'Vor der Messung aufgetreten (Zahl der Ereignisse: {count}); für diese Zeit liegen keine Messwerte vor.'; @($d.guidance.userView.PSObject.Properties.Name) | Should -Not -Contain 'beforeQuick'
        ($d.guidance | ConvertTo-Json -Depth 20 -Compress) | Should -Not -Match '"(text|where|sign)Quick"'; ($d.before.incidents | ConvertTo-Json -Depth 20 -Compress) | Should -Match 'seit Beginn der Messung'
        foreach ($i in @($d.before.incidents)) { $i.guide.userView | Should -Match '^Vor der Messung aufgetreten \(Zahl der Ereignisse: \d+\)' }
        $d.meta.PSObject.Properties.Name | Should -Contain 'healthOnly'; $d.meta.healthOnly | Should -BeFalse; $d.meta.PSObject.Properties.Name | Should -Not -Contain 'reportKind'
        @($d.PSObject.Properties.Name) | Should -Contain 'incidents'; @($d.PSObject.Properties.Name) | Should -Contain 'lagebild'; $d.print.involvedFrom | Should -Be 'both'
        ($o | Out-String) | Should -Match 'Bericht erstellt in [\d.]+ s \(davon Einlesen [\d.]+ s\): '; ($o | Out-String) | Should -Match '  \d+ Takte, \d+ Schnappschuesse'
    }
}
