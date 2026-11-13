BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1')
    $script:Capture = Join-Path $PSScriptRoot '../src/Start-WorkerPerfCapture.ps1'
    $script:Report = Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1'
    $script:Texts = Read-WorkerPerfTexts (Join-Path $PSScriptRoot '../src/texts.de.json')
    # die Aufzeichnungen von New-SkipRuns und je ein Bericht dazu
    $script:Rep = New-SkipReports (Join-Path $TestDrive 'rep')
    $script:Names = @('Prozesse', 'Laufwerke', 'Citrix', 'Ereignisse', 'Rueckblick', 'Drucken', 'Gegenstellen')
    $script:Runs = [ordered]@{}; $script:D = @{}
    foreach ($k in @('Voll') + $Names + 'Zustand' + 'Alle') { $Runs[$k] = $Rep[$k].Run; $D[$k] = Get-ReportData $Rep[$k].Report }
    $script:Places = @{ Prozesse = @('procs', 'apps', 'sessions.resources', 'incidents.contributors', 'incidents.delayProcs', 'print.processes'); Laufwerke = @('volumes', 'shares', 'sessions.profile')
        Citrix = @('citrix', 'sessions.rtt', 'incidents.ica'); Ereignisse = @('events', 'sessions.events', 'incidents.events'); Rueckblick = @('before'); Drucken = @('print.drivers', 'print.queues')
        Gegenstellen = @('probes', 'incidents.endpoints'); Zustand = @() }
    $script:Files = @{ Prozesse = @('processes.csv', 'procinfo.csv', 'procend.csv', 'inputdelay_proc.csv'); Laufwerke = @('volumes.csv', 'shares.csv'); Citrix = @('citrix.csv')
        Ereignisse = @('events.csv'); Rueckblick = @('events_before.csv'); Drucken = @('printdrivers.csv', 'printqueues.csv'); Gegenstellen = @('probes.csv'); Zustand = @('health.json') }
    $script:Ids = @{ Prozesse = @('process', 'input.process'); Laufwerke = @('disk.latency', 'smb.latency', 'profile.map'); Citrix = @('ica.rtt', 'ica.latency'); Ereignisse = @(); Rueckblick = @()
        Drucken = @('print.drivers', 'print.queues'); Gegenstellen = @('probe.connect'); Zustand = @('health') }
    function Get-Meta([string]$Run) { Get-Content (Join-Path $Run 'meta.json') -Raw | ConvertFrom-Json }
    function Get-CsvNames([string]$Run) { Get-ChildItem $Run -Filter *.csv | ForEach-Object Name | Sort-Object }   # schlichte Pipeline-Ausgabe: Should -Be vergleicht die Elemente
    function Get-LineCounts([string]$Run) { $c = [ordered]@{}; foreach ($f in Get-ChildItem $Run -Filter *.csv | Sort-Object Name) { $c[$f.Name] = @(Get-Content $f.FullName).Count }; $c }
    $script:VollCounts = Get-LineCounts $Runs.Voll
    function Get-Shape([string]$Run) {   # Dateien mit Zeilenzahl und meta.json ohne die Zeiten des Laufs
        $m = Get-Meta $Run; foreach ($k in 'StartTime', 'EndTime') { $m.PSObject.Properties.Remove($k) }
        (@(Get-ChildItem $Run -Filter *.csv | Sort-Object Name | ForEach-Object { '{0}:{1}' -f $_.Name, @(Get-Content $_.FullName).Count }) -join ' ') + "`n" + ($m | ConvertTo-Json -Depth 8 -Compress)
    }
}
Describe 'Aufzeichnung mit -Skip' {
    It 'legt die Dateien von <_> nicht an, vermerkt ihre Quellen und laesst alles andere stehen' -ForEach 'Prozesse', 'Laufwerke', 'Citrix', 'Ereignisse', 'Rueckblick', 'Drucken', 'Gegenstellen', 'Zustand' {
        $cat = $_; $m = Get-Meta $Runs[$cat]
        Get-CsvNames $Runs[$cat] | Should -Be @($WorkerPerfHeaders.Keys | Where-Object { $Files[$cat] -notcontains $_ } | Sort-Object)
        @($m.Skip) | Should -Be @($cat); $m.Ticks | Should -Be 1800; @($m.SourceErrors.PSObject.Properties).Count | Should -Be 0
        foreach ($id in $Ids[$cat]) { $m.Sources.$id.Available | Should -BeFalse -Because $id; $m.Sources.$id.Detail | Should -Be "abgeschaltet (-Skip $cat)" }
        @($m.Sources.PSObject.Properties | Where-Object { -not $_.Value.Available }).Count | Should -Be $Ids[$cat].Count
        # die anderen Kategorien und die Basis behalten ihre Zeilen: jede verbliebene Datei hat so viele Zeilen wie im vollen Lauf
        $counts = Get-LineCounts $Runs[$cat]
        foreach ($f in $counts.Keys) { $counts[$f] | Should -Be $VollCounts[$f] -Because "$f ohne $cat" }
        @($counts.Values | Where-Object { $_ -le 1 }).Count | Should -Be 0   # keine Datei nur mit der Kopfzeile
    }
    It 'misst ohne alle Kategorien die Basis wie im vollstaendigen Lauf' {   # Review Focus 1
        $m = Get-Meta $Runs.Alle
        Get-CsvNames $Runs.Alle | Should -Be @('inputdelay.csv', 'sessions.csv', 'snapshots.csv', 'ticks.csv')
        @($m.Skip) | Should -Be $Names; $m.EventLookbackDays | Should -Be 0; @($m.Endpoints).Count | Should -Be 0; @($m.SourceErrors.PSObject.Properties).Count | Should -Be 0
        $m.Sources.'events.application'.Detail | Should -Be 'abgeschaltet (-Skip Ereignisse,Rueckblick)'; $m.Sources.'input.session'.Available | Should -BeTrue; $m.Sources.sessions.Available | Should -BeTrue
        @($m.Sources.PSObject.Properties | Where-Object { $_.Name -like 'events.*' -and $_.Value.Detail -ne 'abgeschaltet (-Skip Ereignisse,Rueckblick)' }).Count | Should -Be 0
        @($m.EventReadCounts.PSObject.Properties).Count | Should -Be 0; @($m.LookbackReadCounts.PSObject.Properties).Count | Should -Be 0
        $base = { param($run) (Get-Content (Join-Path $run 'ticks.csv') | ForEach-Object { $_.Split(',')[2..16] -join ',' }) -join "`n" }   # ElapsedSec bis NetSentBps
        & $base $Runs.Alle | Should -BeExactly (& $base $Runs.Voll)
        Get-Content (Join-Path $Runs.Alle 'inputdelay.csv') -Raw | Should -BeExactly (Get-Content (Join-Path $Runs.Voll 'inputdelay.csv') -Raw)
        $snaps = @(Import-Csv (Join-Path $Runs.Alle 'snapshots.csv'))
        @($snaps | Where-Object Kind -in 'R', 'K').Count | Should -Be 240; $snaps[0].Sessions | Should -Be '25'; $snaps[0].Processes | Should -Be ''; $snaps[0].RowsWritten | Should -Be ''
        @(Import-Csv (Join-Path $Runs.Alle 'sessions.csv') | Where-Object P -eq '0').Count | Should -Be 26
    }
    It 'haelt Ereignisse und Rueckblick unabhaengig' {
        # Aussage angepasst: die simulierte Stunde hat seit der Korrekturrunde des Ereignisplans sechs Ereignisse im Rueckblick
        @(Import-Csv (Join-Path $Runs.Ereignisse 'events_before.csv')).Count | Should -Be 6; (Get-Meta $Runs.Ereignisse).Sources.'events.application'.Available | Should -BeTrue
        @(Import-Csv (Join-Path $Runs.Rueckblick 'events.csv')).Count | Should -Be 13; (Get-Meta $Runs.Rueckblick).EventLookbackDays | Should -Be 0   # weggelassen gewinnt gegen 7 Tage
        (Get-Meta $Runs.Rueckblick).Sources.'events.application'.Detail | Should -Be 'Simulation'
    }
    It 'ruft die Quelle fuer eine weggelassene Kategorie nicht auf und laesst ihre Zaehler leer' {
        # jeder eigenstaendige Aufruf einer Kategorie wirft (ein Aufruf staende in SourceErrors oder beendete die
        # Aufzeichnung); die Zaehler der Ereignis-Abrufe sind nie leer
        $counts = 'function Get-WorkerPerfEventCounts { [ordered]@{ application = [ordered]@{ Skipped = 1 } } }'
        $throwing = $counts + "`n" + (@('Get-WorkerPerfServices', 'Get-WorkerPerfEvents', 'Get-WorkerPerfEventsBefore', 'Get-WorkerPerfPrintDrivers', 'Get-WorkerPerfPrintQueues',
                'Start-WorkerPerfProbes', 'Receive-WorkerPerfProbes', 'Get-WorkerPerfHealth') | ForEach-Object { "function $_ { throw 'Testaufruf $_' }" }) -join "`n"
        $none = (& (New-PatchedSource (Join-Path $TestDrive 'srcthrow') $throwing) -Simulate -DurationMinutes 60 -Skip ($Names + 'Zustand') -OutputPath (Join-Path $TestDrive 'throw') 6>$null 3>$null) | Select-Object -Last 1
        $m = Get-Meta $none
        $m.EndReason | Should -Be 'duration'; @($m.SourceErrors.PSObject.Properties).Count | Should -Be 0
        @($m.EventReadCounts.PSObject.Properties).Count | Should -Be 0; @($m.LookbackReadCounts.PSObject.Properties).Count | Should -Be 0
        # ohne Ereignisse liest nur der Rueckblick (seine Zaehler stehen bei LookbackReadCounts), ohne Rueckblick nur der regulaere Abruf
        $src = New-PatchedSource (Join-Path $TestDrive 'srccount') $counts
        $noEv = Get-Meta ((& $src -Simulate -DurationMinutes 60 -Skip Ereignisse -OutputPath (Join-Path $TestDrive 'noev') 6>$null) | Select-Object -Last 1)
        @($noEv.EventReadCounts.PSObject.Properties).Count | Should -Be 0; $noEv.LookbackReadCounts.application.Skipped | Should -Be 1
        $noLb = Get-Meta ((& $src -Simulate -DurationMinutes 60 -Skip Rueckblick -OutputPath (Join-Path $TestDrive 'nolb') 6>$null) | Select-Object -Last 1)
        @($noLb.LookbackReadCounts.PSObject.Properties).Count | Should -Be 0; $noLb.EventReadCounts.application.Skipped | Should -Be 1
    }
    It 'ergibt mit den alten Schaltern, doppelt, in anderer Schreibweise und als eine Zeichenkette dieselbe Aufzeichnung' {   # Review Focus 4 und 5
        $a = @(& $Capture -Simulate -DurationMinutes 60 -NoCitrix -OutputPath (Join-Path $TestDrive 'a') 6>&1)
        ($a | Out-String) | Should -Match 'Gemessen: Basis, Prozesse, Laufwerke, Ereignisse, Rueckblick, Drucken, Gegenstellen, Zustand\s+Nicht gemessen \(-Skip\): Citrix'
        Get-Shape ([string]$a[-1]) | Should -BeExactly (Get-Shape $Runs.Citrix)
        # Aussage angepasst (Zustandsbild, Task 8): Zustand ist aktiv, der Lauf laesst den Wert 'Zustand' und die Aussagen dazu weg
        $b = @(& $Capture -Simulate -DurationMinutes 60 -EventLookbackDays 0 -Skip 'rueckblick,RUECKBLICK' -OutputPath (Join-Path $TestDrive 'b') 6>&1)
        Get-Shape ([string]$b[-1]) | Should -BeExactly (Get-Shape $Runs.Rueckblick)
        $console = $b | Out-String
        $console | Should -Match 'Nicht gemessen \(-Skip\): Rueckblick\r?\n'
    }
    It 'lehnt einen unbekannten Wert ab, bevor etwas angelegt wird' {
        $dir = Join-Path $TestDrive 'x'
        { & $Capture -Simulate -DurationMinutes 60 -Skip Prozesse, Netz -OutputPath $dir 6>$null } | Should -Throw "*'Netz'*Gueltige Werte: Prozesse, Laufwerke, Citrix, Ereignisse, Rueckblick, Drucken, Gegenstellen, Zustand.*"
        Test-Path $dir | Should -BeFalse
    }
    It 'lehnt einen Wert von -Skip ab, der mit Leerzeichen statt Komma an -OutputPath geht, bevor etwas angelegt wird' {   # Abschlussrunde (Important 3)
        Push-Location $TestDrive
        try {
            { & $Capture -Simulate -DurationMinutes 60 -Skip Prozesse Rueckblick 6>$null } | Should -Throw "-OutputPath 'Rueckblick' ist der Name einer Kategorie: die Werte von -Skip mit Komma trennen (-Skip Prozesse,Rueckblick)."
            { & $Capture -Simulate -DurationMinutes 60 -Skip 'Prozesse,citrix' gegenstellen 6>$null } | Should -Throw "-OutputPath 'gegenstellen' ist der Name einer Kategorie: die Werte von -Skip mit Komma trennen (-Skip Prozesse,citrix,gegenstellen)."
            foreach ($d in 'Rueckblick', 'gegenstellen') { Test-Path (Join-Path $TestDrive $d) | Should -BeFalse }
            # ein Pfad mit Trennzeichen ist ein Ordner, kein Wert von -Skip: der Start laeuft weiter (hier bis zur Pruefung der Dauer)
            { & $Capture -Simulate -DurationMinutes 10 -Skip Prozesse -OutputPath (Join-Path '.' 'Rueckblick') 6>$null } | Should -Throw '-Simulate erfordert -DurationMinutes*'
            { & $Capture -Simulate -DurationMinutes 10 -OutputPath 'Rueckblick' 6>$null } | Should -Throw '-Simulate erfordert -DurationMinutes*'   # ohne -Skip
        }
        finally { Pop-Location }
    }
    It 'zeichnet ohne Prozesse keine Befehlszeilen auf und sagt es beim Start' {   # Abschlussrunde (Minor 7)
        (Get-Meta $Runs.Prozesse).IncludeCommandLine | Should -BeFalse; (Get-Meta $Runs.Voll).IncludeCommandLine | Should -BeFalse
        $out = Get-Content (Join-Path (Split-Path (Split-Path $Runs.Prozesse -Parent) -Parent) 'Prozesse.console.txt') -Raw
        $out | Should -Match 'Nicht gemessen \(-Skip\): Prozesse\r?\nBefehlszeilen werden nicht aufgezeichnet: Prozesse ist weggelassen \(-Skip Prozesse\)\.\r?\n'
        (Get-Content (Join-Path (Split-Path (Split-Path $Runs.Voll -Parent) -Parent) 'Voll.console.txt') -Raw) | Should -Not -Match 'Befehlszeilen'
    }
    It 'laesst die Aufzeichnung ohne -Skip wie bisher, bis auf das neue Feld Skip' {
        $m = Get-Meta $Runs.Voll; $names = @($m.PSObject.Properties.Name)
        Get-CsvNames $Runs.Voll | Should -Be @($WorkerPerfHeaders.Keys | Sort-Object)
        # Aussage angepasst: EventReadCounts und LookbackReadCounts kamen nach dem Plan dazu; Skip steht hinter ihnen
        $names | Should -Be @('SchemaVersion', 'Computer', 'OS', 'LogicalProcessors', 'PhysicalMemoryMB', 'FastIntervalSeconds', 'IntervalSeconds', 'BurstIntervalSeconds', 'BurstHoldSeconds', 'MaxSizeMB',
            'StartTime', 'EndTime', 'EndReason', 'EndMessage', 'Ticks', 'Snapshots', 'SkippedTicks', 'Simulated', 'HealthOnly', 'IncludeCommandLine', 'EventLookbackDays', 'LookbackCapped', 'EventReadCounts', 'LookbackReadCounts', 'Skip', 'CollectorPid', 'Endpoints', 'Sources', 'SourceErrors')
        @($m.Skip).Count | Should -Be 0; $m.EventLookbackDays | Should -Be 7; @($m.Endpoints).Count | Should -Be 3
        $m.HealthOnly | Should -BeFalse
        @($m.Sources.PSObject.Properties | Where-Object { -not $_.Value.Available -or $_.Value.Detail -notlike 'Simulation*' }).Count | Should -Be 0
    }
    It 'nennt beim Start die gemessenen und die weggelassenen Kategorien' {
        # die Konsolenausgabe des vollen Laufs: New-SkipRuns legt sie neben den Ordner Voll, der die Aufzeichnung enthaelt
        $out = Get-Content (Join-Path (Split-Path (Split-Path $Runs.Voll -Parent) -Parent) 'Voll.console.txt') -Raw
        $out | Should -Match 'laeuft: [^\r\n]+\r?\nGemessen: Basis, Prozesse, Laufwerke, Citrix, Ereignisse, Rueckblick, Drucken, Gegenstellen, Zustand\r?\nNicht gemessen \(-Skip\): keine\r?\n'
    }
}
Describe 'Zustandsbild in der Aufzeichnung' {
    It 'schreibt health.json einmal beim Start und nennt es auf der Konsole' {
        $h = Get-Content (Join-Path $Runs.Voll 'health.json') -Raw | ConvertFrom-Json
        $h.FormatVersion | Should -Be 1; @($h.Areas.PSObject.Properties.Name) | Should -Be $WorkerPerfHealthAreas
        @($h.Areas.profile.Values.'profile.containers'.Value).Count | Should -Be 25; $h.Areas.security.Values.'security.defenderExclusionPaths'.Reason | Should -Be 'rights'
        Test-Path (Join-Path $Runs.Voll 'health.json.tmp') | Should -BeFalse
        $out = Get-Content (Join-Path (Split-Path (Split-Path $Runs.Voll -Parent) -Parent) 'Voll.console.txt') -Raw
        $out | Should -Match 'Gemessen: Basis, Prozesse, Laufwerke, Citrix, Ereignisse, Rueckblick, Drucken, Gegenstellen, Zustand\r?\nNicht gemessen \(-Skip\): keine\r?\n'
        $out | Should -Match 'Zustandsbild: 10 Bereiche gelesen, 1 unvollstaendig \(security\), 0\.0 s\r?\n'
        $m = Get-Meta $Runs.Voll; $m.Sources.health.Available | Should -BeTrue; @($m.SourceErrors.PSObject.Properties).Count | Should -Be 0
        $m.Ticks | Should -Be 1800                                                          # das Lesen kostet keinen Takt
    }
    It 'legt mit -Skip Zustand keine health.json an' {
        Test-Path (Join-Path $Runs.Zustand 'health.json') | Should -BeFalse; (Get-Meta $Runs.Zustand).Sources.health.Detail | Should -Be 'abgeschaltet (-Skip Zustand)'
        @($D.Zustand.skipped.id) | Should -Be @('Zustand'); $D.Zustand.skipped[0].text | Should -Be 'Das Zustandsbild des Servers wurde bei dieser Messung nicht gelesen.'
    }
    It 'liest die Anwendungsliste beim Start, kopiert sie und lehnt eine fehlerhafte ab, bevor etwas angelegt ist' {
        $shipped = Join-Path $PSScriptRoot '../src/apps.json'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $Runs.Voll 'apps.json'))) | Should -Be ([Convert]::ToBase64String([IO.File]::ReadAllBytes($shipped))); Test-Path (Join-Path $Runs.Zustand 'apps.json') | Should -BeFalse
        $rows = @((Get-Content (Join-Path $Runs.Voll 'health.json') -Raw | ConvertFrom-Json).Areas.apps.Values.'apps.probes'.Value)
        @(($rows | Where-Object Id -eq 'installed').App | Sort-Object) | Should -Be @('edge', 'office', 'teams'); @($rows | Where-Object { $_.Id -eq 'installed' -and -not $_.Value }).Count | Should -Be 0
        $capture = Join-Path $PSScriptRoot '../src/Start-WorkerPerfCapture.ps1'; $dir = Join-Path $TestDrive 'badapps'; $bad = Join-Path $TestDrive 'apps.bad.json'
        [IO.File]::WriteAllText($bad, (Get-Content $shipped -Raw).Replace('HKLM\\SOFTWARE\\Policies\\Microsoft\\Edge"', 'HKCU\\SOFTWARE\\Policies\\Microsoft\\Edge"'))
        { & $capture -Simulate -DurationMinutes 60 -OutputPath $dir -AppsFile $bad 6>$null } | Should -Throw "*Anwendung 'edge': Probe '*':*HKLM*"
        { & $capture -Simulate -DurationMinutes 60 -OutputPath $dir -AppsFile (Join-Path $TestDrive 'keine.json') 6>$null } | Should -Throw "Anwendungsliste '*keine.json' fehlt."
        Test-Path $dir | Should -BeFalse
    }
    It 'zeichnet weiter auf, wenn das Lesen als Ganzes scheitert' {   # Review Focus 1
        $src = New-PatchedSource (Join-Path $TestDrive 'srchealth') "function Get-WorkerPerfHealth { throw 'Testfehler Zustandsbild' }"
        $out = @(& $src -Simulate -DurationMinutes 60 -OutputPath (Join-Path $TestDrive 'failhealth') 6>$null 3>&1)
        $run = [string]$out[-1]; $m = Get-Meta $run
        $m.EndReason | Should -Be 'duration'; $m.Ticks | Should -Be 1800; $m.SourceErrors.health.Count | Should -Be 1; $m.SourceErrors.health.FirstMessage | Should -Be 'Testfehler Zustandsbild'
        Test-Path (Join-Path $run 'health.json') | Should -BeFalse
        @($out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] -and $_.Message -match "Datenquelle 'Zustandsbild'" }).Count | Should -Be 1
    }
}
Describe 'Berichtsdaten mit weggelassenen Kategorien' {
    It 'nennt fuer <_> Kategorie, Grund und abhaengige Stellen' -ForEach 'Prozesse', 'Laufwerke', 'Citrix', 'Ereignisse', 'Rueckblick', 'Drucken', 'Gegenstellen', 'Zustand' {
        $s = @($D[$_].skipped); $s.Count | Should -Be 1
        $s[0].id | Should -Be $_; $s[0].label | Should -Be $Texts["skip.label.$_"]; $s[0].text | Should -Be $Texts["skip.text.$_"]; @($s[0].places) | Should -Be $Places[$_]
    }
    It 'zaehlt kein Signal einer weggelassenen Kategorie im Soll-Ist' {
        $a = $D.Alle;   # nicht $d: PowerShell unterscheidet $d und $D nicht
        @($a.skipped.id) | Should -Be $Names; $a.skipped[0].text | Should -Be 'Prozesse wurden bei dieser Messung nicht erfasst.'
        foreach ($id in 'disk.latency', 'smb.latency', 'ica.rtt', 'ica.latency', 'probe.connect') {
            $r = $a.sollIst | Where-Object id -eq $id; $r.measured | Should -BeFalse -Because $id; $r.status | Should -Be 0; $r.exceeded | Should -BeFalse
        }
        ($a.sollIst | Where-Object id -eq 'smb.latency').detail | Should -Be 'abgeschaltet (-Skip Laufwerke)'
        @($a.sollIst | Where-Object measured).id | Should -Be @('cpu.host', 'cpu.queue', 'cpu.steal', 'mem.used', 'mem.commit', 'mem.pagesin', 'input.session')
        $a.unmeasured.worker | Should -Be @('Datenträger-Antwortzeit', 'Freigabe-Antwortzeit (SMB)'); $a.before.status | Should -Be 'off'; $D.Rueckblick.before.status | Should -Be 'off'
    }
    It 'erkennt die Vorfaelle der Basis in jeder Kombination wie im vollstaendigen Lauf' {   # Review Focus 1
        $win = { param($d) @($d.incidents | Where-Object { $_.type -ne 'ereignis' -and -not $_.chronic } | ForEach-Object { '{0}-{1}' -f ($_.start - $d.meta.start), ($_.end - $d.meta.start) }) }
        $lead = { param($d) @($d.incidents | Where-Object { $_.lead -in 'cpu', 'memory' } | ForEach-Object { '{0}|{1}|{2}' -f $_.type, $_.lead, ($_.start - $d.meta.start) }) }
        @(& $win $D.Voll).Count | Should -Be 7; @(& $lead $D.Voll).Count | Should -Be 2
        foreach ($k in $Names + 'Alle') { & $win $D[$k] | Should -Be (& $win $D.Voll) -Because $k; & $lead $D[$k] | Should -Be (& $lead $D.Voll) -Because $k }
    }
    It 'wertet eine Aufzeichnung von vor diesem Plan als vollstaendig gemessen aus, mit demselben Bericht' {   # Review Focus 2
        $old = Copy-SimRun $Runs.Voll (Join-Path $TestDrive 'alt'); $f = Join-Path $old 'meta.json'
        [IO.File]::WriteAllText($f, ([IO.File]::ReadAllText($f) -replace '(?s)"Skip":\s*\[\s*\],\s*', '')); (Get-Meta $old).PSObject.Properties.Name | Should -Not -Contain 'Skip'
        $out = Join-Path $TestDrive 'alt.html'; [void](& $Report -Path $old -OutFile $out -RoleFile (Join-Path $TestDrive 'rep/roles.sim.json') 6>$null)
        $norm = { param($file) [IO.File]::ReadAllText($file) -replace '"generated":\d+', '"generated":0' }
        & $norm $out | Should -BeExactly (& $norm $Rep.Voll.Report)
        # das neue Feld der Berichtsdaten, leer; Aussage angepasst (Gefuehrter Bericht, Task 7): nach ihm folgen die Felder des gefuehrten Berichts
        $fields = @($D.Voll.PSObject.Properties.Name)
        @($D.Voll.skipped).Count | Should -Be 0; @($fields[($fields.IndexOf('skipped') + 1)..($fields.Count - 1)]) | Should -Be @('guidance', 'lagebild', 'order', 'cards', 'more', 'copyAll')
    }
    It 'nennt fuer weggelassene Ereignisse keine Zaehler der Messung und laesst den Rueckblick leer, wenn er weggelassen ist' {
        # ohne Ereignisse: die Zaehler der Messung fehlen (die Seite sagt dann nichts ueber sie, skipped nennt den Grund);
        # der Rueckblick ist derselbe wie im vollen Lauf
        @($D.Ereignisse.quality.eventReads).Count | Should -Be 0; @($D.Alle.quality.eventReads).Count | Should -Be 0
        $D.Ereignisse.before.status | Should -Be $D.Voll.before.status; $D.Ereignisse.before.eventCount | Should -Be $D.Voll.before.eventCount
        $D.Voll.before.status | Should -Be 'read'
        foreach ($k in 'Rueckblick', 'Alle') {
            $b = $D[$k].before; $b.status | Should -Be 'off' -Because $k; $b.eventCount | Should -Be 0
            foreach ($f in 'readCounts', 'oldest', 'perDay', 'incidents', 'capped') { @($b.$f).Count | Should -Be 0 -Because "$k before.$f" }
        }
    }
    It 'zeigt fuer weggelassene Ereignisse und Rueckblick keine Zaehler, auch wenn meta.json welche nennt' {   # Fix-Runde 1 (Minor 4)
        # Der Collector laesst beide Zaehler einer weggelassenen Kategorie leer (oben); erst eine von Hand geaenderte
        # meta.json nennt welche. Dieselbe Aenderung im vollen Lauf zeigt, dass die Zaehler sonst erscheinen.
        $cnt = [pscustomobject]@{ application = [pscustomobject]@{ SkippedRecords = 4; UnformattedMessages = 2; DroppedEvents = 9 } }
        $edit = { param([string]$Run, [string]$Name)
            $dir = Copy-SimRun $Run (Join-Path $TestDrive "gate-$Name"); $f = Join-Path $dir 'meta.json'
            $m = Get-Content $f -Raw | ConvertFrom-Json
            $m | Add-Member -Force EventReadCounts $cnt; $m | Add-Member -Force LookbackReadCounts ([pscustomobject]@{ application = [pscustomobject]@{ SkippedRecords = 1; UnformattedMessages = 1; DroppedEvents = 0 } })
            $m.EventLookbackDays = 7
            [IO.File]::WriteAllText($f, ($m | ConvertTo-Json -Depth 8))
            $out = Join-Path $TestDrive "gate-$Name.html"; [void](& $Report -Path $dir -OutFile $out -RoleFile (Join-Path $TestDrive 'rep/roles.sim.json') 6>$null)
            Get-ReportData $out }
        $full = & $edit $Runs.Voll 'voll'
        @($full.quality.eventReads | ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.log, $_.dropped, $_.skipped, $_.unformatted }) | Should -Be @('application|9|3|1')
        @($full.before.readCounts).Count | Should -Be 1; $full.before.status | Should -Be 'read'
        $noEv = & $edit $Runs.Ereignisse 'ereignisse'
        @($noEv.quality.eventReads).Count | Should -Be 0; @($noEv.before.readCounts).Count | Should -Be 1
        $noLb = & $edit $Runs.Rueckblick 'rueckblick'
        @($noLb.before.readCounts).Count | Should -Be 0; $noLb.before.status | Should -Be 'off'; @($noLb.quality.eventReads).Count | Should -Be 1
    }
    It 'zeigt die Hauptanwendung nur, wenn Prozesse gemessen wurden' {   # Fix-Runde 1 (Important 1)
        $D.Voll.mainApp | Should -Not -BeNullOrEmpty; $D.Voll.mainApp.label | Should -Not -BeNullOrEmpty
        foreach ($k in 'Prozesse', 'Alle') { $null -eq $D[$k].mainApp | Should -BeTrue -Because $k; @($D[$k].PSObject.Properties.Name) | Should -Contain 'mainApp' }
        foreach ($k in 'Laufwerke', 'Citrix', 'Ereignisse', 'Rueckblick', 'Drucken', 'Gegenstellen') {
            $D[$k].mainApp.label | Should -Be $D.Voll.mainApp.label -Because $k; $D[$k].mainApp.status | Should -Be $D.Voll.mainApp.status -Because $k
        }
    }
    It 'ordnet die Felder von skipped im Bestand tests/MaskCensus.json ein' {
        $file = Get-Content (Join-Path $PSScriptRoot 'MaskCensus.json') -Raw -Encoding UTF8 | ConvertFrom-Json; $census = $file.fields
        $whole = [string[]]@($file.subtrees)                                                     # ein Eintrag je Teilbaum (P3-R10)
        $paths = New-Object System.Collections.Generic.SortedSet[string] ([StringComparer]::Ordinal)
        $walk = { param($v, [string]$p)
            if ($null -eq $v -or $v -is [ValueType]) { return }
            if ($whole -ccontains $p) { [void]$paths.Add($p); return }
            if ($v -is [string]) { [void]$paths.Add($p); return }
            if ($v -is [System.Collections.IEnumerable]) { foreach ($x in $v) { if ($null -ne $x -and $x -isnot [ValueType]) { & $walk $x "$p[]" } }; return }   # Zahlenreihen ohne Aufruf je Wert
            foreach ($q in $v.PSObject.Properties) { & $walk $q.Value $(if ($p) { "$p.$($q.Name)" } else { $q.Name }) } }
        & $walk @($D.Alle.skipped) 'skipped'
        @($paths) | Should -Be @($census.PSObject.Properties.Name | Where-Object { $_ -like 'skipped*' } | Sort-Object)
        # Abschlussrunde (Minor 11): jedes Textfeld der ganzen Berichtsdaten jedes Laufs ist eingeordnet; ohne Laufwerke
        # fuellen sich Listen, die im vollen Lauf leer sind (unmeasured.worker)
        $paths.Clear()
        foreach ($k in @('Voll') + $Names + 'Alle') { & $walk $D[$k] '' }
        @($paths | Where-Object { $null -eq $census.PSObject.Properties[$_] } | ForEach-Object { "neues Textfeld $_ : in tests/MaskCensus.json einordnen" }) | Should -BeNullOrEmpty
        $census.'unmeasured.worker[]' | Should -Be 'composed'; @($D.Laufwerke.unmeasured.worker).Count | Should -Be 2; @($D.Voll.unmeasured.worker).Count | Should -Be 0
    }
    It 'nennt die Quellen der Treiberspalte "An einem Vorfall beteiligt"' {   # Ergaenzung Task 7 (Gefuehrter Bericht)
        @('Voll', 'Ereignisse', 'Rueckblick', 'Alle', 'Drucken' | ForEach-Object { $D[$_].print.involvedFrom }) | Should -Be @('both', 'lookback', 'capture', 'none', 'both')
        (Get-ReportData $Rep.AlleMasked.Report).print.involvedFrom | Should -Be 'none'
    }
    It 'liest die Dateien einer Kategorie nicht, die Skip nennt, auch wenn die Aufzeichnung sie hat' {   # Abschlussrunde (Minor 6, MK-R20)
        # eine Kopie des vollen Laufs mit "Skip": "Prozesse" (New-SkipReports, Odd) und mit "Skip": ["Prozesse"]: der Bericht
        # ist der einer Aufzeichnung mit -Skip Prozesse, soweit die Dateien reichen
        $dir = Copy-SimRun $Runs.Voll (Join-Path $TestDrive 'odd-list'); $f = Join-Path $dir 'meta.json'
        [IO.File]::WriteAllText($f, ([IO.File]::ReadAllText($f) -replace '(?s)"Skip":\s*\[\s*\]', '"Skip": ["Prozesse"]'))
        $out = Join-Path $TestDrive 'odd-list.html'; [void](& $Report -Path $dir -OutFile $out -RoleFile (Join-Path $TestDrive 'rep/roles.sim.json') 6>$null)
        $rel = { param($x, $v) [regex]::Replace((ConvertTo-Json -InputObject $v -Depth 30 -Compress), '\b1\d{12}\b', { param($m) [string]([long]$m.Value - [long]$x.meta.start) }) }
        $noTime = { param($t) $t -replace '\d\d:\d\d(:\d\d)?', 'hh:mm' }
        $p = $D.Prozesse
        foreach ($o in @((Get-ReportData $Rep.Odd.Report), (Get-ReportData $out))) {
            foreach ($n in 'processes.csv', 'procinfo.csv', 'procend.csv', 'inputdelay_proc.csv') { Test-Path (Join-Path $Rep.Odd.Run $n) | Should -BeTrue }
            @($o.skipped.id) | Should -Be @('Prozesse'); @($o.procs).Count | Should -Be 0; $null -eq $o.mainApp | Should -BeTrue
            foreach ($k in 'procs', 'apps', 'pairs', 'sessions', 'sollIst', 'host', 'unmeasured', 'skipped', 'volumes', 'shares', 'print') { & $rel $o $o.$k | Should -BeExactly (& $rel $p $p.$k) -Because $k }
            & $rel $o $o.quality.sources | Should -BeExactly (& $rel $p $p.quality.sources)
            $o.meta.processRows | Should -Be 0; $o.meta.processCount | Should -Be 0
            # die Vorfaelle der Basis wie mit -Skip Prozesse; die Ereignisvorfaelle zu denselben Zeiten, aber mit den Sitzungen und
            # Benutzern, die der Collector beim Aufzeichnen in events.csv geschrieben hat (die Datei der Ereignisse gibt sie mit)
            $base = { param($x) @($x.incidents | Where-Object type -ne 'ereignis' | ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.type, ($_.start - $x.meta.start), ($_.end - $x.meta.start), (& $noTime $_.text) }) }
            & $base $o | Should -Be (& $base $p)
            $evw = { param($x) @($x.incidents | Where-Object type -eq 'ereignis' | ForEach-Object { '{0}|{1}|{2}' -f $_.event.app, ($_.start - $x.meta.start), ($_.end - $x.meta.start) }) }
            & $evw $o | Should -Be (& $evw $p)
            @($o.incidents | Where-Object { $_.type -eq 'ereignis' -and $_.event.app -eq 'chrome.exe' }).event.users | Should -Be @('user008')
        }
    }
    It 'behaelt Kategorien und Gruende im maskierten Bericht' {
        $m = Get-ReportData $Rep.AlleMasked.Report
        @($m.skipped.id) | Should -Be $Names; $m.skipped[0].text | Should -Be 'Prozesse wurden bei dieser Messung nicht erfasst.'; @($m.skipped[0].places) | Should -Be $Places.Prozesse
        ($m.sollIst | Where-Object id -eq 'ica.rtt').detail | Should -Be 'abgeschaltet (-Skip Citrix)'; ($m.quality.sources | Where-Object id -eq 'process').detail | Should -Be 'abgeschaltet (-Skip Prozesse)'
        [IO.File]::ReadAllText($Rep.AlleMasked.Report) | Should -Not -Match 'user0\d\d|SIM-VDA01|CONTOSO'
    }
}
Describe 'Vorfallserklaerungen und Muster mit weggelassenen Kategorien' {   # Review Focus 3
    BeforeAll { function Get-Ev($Data, [scriptblock]$Where) { @($Data.incidents | Where-Object { $_.type -eq 'ereignis' } | Where-Object $Where) } }   # nicht $d: PowerShell unterscheidet $d und $D nicht
    It 'nennt beim Verursacher den Grund statt fehlender Prozessdaten' {
        $rp = $D.Prozesse; $cpu = $rp.incidents | Where-Object lead -eq 'cpu'
        $cpu.cause.kind | Should -Be 'notmeasured'; $cpu.main | Should -BeNullOrEmpty
        $cpu.text | Should -BeLike '*Betroffen: 6 Sitzungen. Kein Hauptverursacher ermittelt: Prozesse wurden bei dieser Messung nicht erfasst.'
        $back = $rp.incidents | Where-Object { $_.type -eq 'ohne-engpass' -and @($_.affected).Count -eq 8 }
        $back.text | Should -BeLike '*Betroffen: 8 Sitzungen. Prozess mit der höchsten Verzögerung nicht ermittelt: Prozesse wurden bei dieser Messung nicht erfasst. Die Ursache liegt*Gegenstelle Oracle-Listener: *'
        @($rp.incidents | Where-Object { $_.text -match 'keine Prozessdaten' }).Count | Should -Be 0
        ($D.Voll.incidents | Where-Object lead -eq 'cpu').cause.kind | Should -Be 'main'
    }
    It 'nennt im Kopiertext je Vorfall den Teil des Satzes zu Ursache und Umfeld ohne <_>' -ForEach 'Voll', 'Prozesse', 'Gegenstellen', 'Ereignisse' {   # ruling P3-R30
        # one source for the cause: causeText is part of text word for word, and the copy text prints it whole
        $k = $_
        foreach ($f in 'WorkerPerf.EventConfig.ps1', 'WorkerPerf.Events.ps1', 'WorkerPerf.Findings.ps1', 'WorkerPerf.Guidance.ps1') { . (Join-Path $PSScriptRoot "../src/$f") }
        $cat = @{ vendors = @(); userView = @{}; copy = @{ head = 'WorkerPerf {server}'; measure = 'Messwert: {value}'; cause = 'Verursacher:'; affected = 'Betroffen: {affected}' } }
        $guide = @{ title = 'Titel'; tech = ''; userView = ''; impact = ''; checks = @(); remedies = @(); contacts = @() }
        $all = @(@($D[$k].incidents) + @($D[$k].before.incidents) | Where-Object { $null -ne $_ })
        $all.Count | Should -BeGreaterThan 8
        foreach ($i in $all) {
            $c = [string]$i.causeText
            $c | Should -Not -BeNullOrEmpty -Because "Vorfall $($i.id)"
            ([string]$i.text).Contains($c) | Should -BeTrue -Because "Vorfall $($i.id): $c"
            $p = @(Get-WorkerPerfCopyParagraphs -Incident $i -Guide $guide -Data $D[$k] -Catalogue $cat -Texts $Texts)
            $p | Should -Contain "Verursacher: $c" -Because "Vorfall $($i.id)"
            (Format-WorkerPerfCopyLines $p) -replace "`r`n\s*", ' ' | Should -Match ([regex]::Escape($c)) -Because "Vorfall $($i.id)"
        }
        # the backend delay: the endpoint context, or that endpoints were not checked
        $back = @($D[$k].incidents | Where-Object { $_.type -eq 'ohne-engpass' -and @($_.affected).Count -eq 8 })[0]
        if ($k -eq 'Gegenstellen') { $back.causeText | Should -BeLike '*Gegenstellen wurden bei dieser Messung nicht geprüft.' }
        else { $back.causeText | Should -BeLike '*Gegenstelle Oracle-Listener: *' }
    }
    It 'sagt bei einer Verzoegerung ohne Engpass, was nicht geprueft wurde' {
        $back = $D.Gegenstellen.incidents | Where-Object { $_.type -eq 'ohne-engpass' -and @($_.affected).Count -eq 8 }
        $back.text | Should -BeLike '*(Datenbank, Proxy, Netz). Gegenstellen wurden bei dieser Messung nicht geprüft.'; @($back.endpoints).Count | Should -Be 0
        $late = @($D.Laufwerke.incidents | Where-Object type -eq 'ohne-engpass'); $late.Count | Should -Be 5
        foreach ($i in $late) { $i.text | Should -Match 'Nicht gemessen: Datenträger-Antwortzeit, Freigabe-Antwortzeit \(SMB\); ein Engpass dort ist nicht ausgeschlossen\.' }
    }
    It 'bildet kein Muster, das eine weggelassene Kategorie braucht, und sagt nicht "kein Muster"' {
        $p = (Get-Ev $D.Drucken { $_.event.kind -eq 'print' })[0]
        @($p.event.patterns).Count | Should -Be 0; @($p.event.unchecked | ForEach-Object { '{0}|{1}|{2}' -f $_.id, $_.category, $_.text }) | Should -Be @('printdriver|Drucken|Bezug zu einem Druckertreiber (Drucken nicht gemessen)')
        $p.text | Should -BeLike '*Nicht geprüft: Bezug zu einem Druckertreiber (Drucken nicht gemessen).'; $p.text | Should -Not -Match 'Kein Muster erkannt'
        $o = (Get-Ev $D.Prozesse { $_.event.app -eq 'OUTLOOK.EXE' })[0]
        @($o.event.patterns.id) | Should -Not -Contain 'manyusers'; @($o.event.unchecked.id) | Should -Be @('users')
        # erweitert: auch "Sitzung nicht ermittelt" entfaellt, den Grund nennt der Satz zum nicht geprueften Muster
        $o.text | Should -BeLike '*Nicht geprüft: Zuordnung zu Benutzern und Sitzungen (Prozesse nicht gemessen).'; $o.text | Should -Not -Match 'Ohne Benutzersitzung|Kein Muster erkannt|Sitzung nicht ermittelt'
        $pr = (Get-Ev $D.Prozesse { $_.event.kind -eq 'profileerror' })[0]   # nennt seinen Benutzer selbst
        @($pr.event.unchecked).Count | Should -Be 0; $pr.text | Should -Match 'Benutzer: user014\. Kein Muster erkannt\.'
        @(@($D.Prozesse.before.incidents) | Where-Object { @($_.event.patterns.id) -contains 'oneuser' }).Count | Should -Be 1   # der Rueckblick nennt Benutzer selbst
        @(@($D.Prozesse.before.incidents) | Where-Object { @($_.event.unchecked).Count -gt 0 }).Count | Should -Be 0
    }
    It 'bildet ohne Prozesse auch aus dem einzelnen Absturz mit unbekannter Sitzung einen Vorfall' {
        # ohne Prozesse ordnet der Collector keinem Absturz eine Sitzung zu; der einzelne Absturz von chrome.exe bleibt ein Vorfall
        @(Get-Ev $D.Prozesse { $true } | ForEach-Object { $_.event.kind + ':' + $_.event.app }) | Should -Be @('profileerror:', 'crash:chrome.exe', 'crash:OUTLOOK.EXE', 'print:spoolsv.exe')
        $c = (Get-Ev $D.Prozesse { $_.event.app -eq 'chrome.exe' })[0]
        @($c.event.patterns.id) | Should -Be @('resource', 'overlap'); @($c.event.unchecked.id) | Should -Be @('users')
        $c.text | Should -BeLike '*Zeitgleich mit Vorfall 3. Nicht geprüft: Zuordnung zu Benutzern und Sitzungen (Prozesse nicht gemessen).'
        $c.text | Should -Not -Match 'Ohne Benutzersitzung|Sitzung nicht ermittelt|Kein Muster erkannt'
        # jede Kombination hat die vier Ereignisvorfaelle der Messung, ausser ohne Ereignisse (dann keinen)
        foreach ($k in @('Voll') + $Names + 'Alle') {
            $want = $(if ($k -eq 'Ereignisse' -or $k -eq 'Alle') { 0 } else { 4 })
            @(Get-Ev $D[$k] { $true }).Count | Should -Be $want -Because $k
        }
    }
    It 'behaelt ein nicht geprueftes Muster im maskierten Bericht' {
        $out = Join-Path $TestDrive 'dm.html'; [void](& $Report -Path $Runs.Drucken -OutFile $out -RoleFile (Join-Path $TestDrive 'rep/roles.sim.json') -Mask Alles 6>$null)
        $u = (Get-Ev (Get-ReportData $out) { $_.event.kind -eq 'print' })[0].event.unchecked
        '{0}|{1}|{2}' -f $u[0].id, $u[0].category, $u[0].text | Should -Be 'printdriver|Drucken|Bezug zu einem Druckertreiber (Drucken nicht gemessen)'
    }
    It 'ordnet die Felder von unchecked im Bestand tests/MaskCensus.json ein' {
        $file = Get-Content (Join-Path $PSScriptRoot 'MaskCensus.json') -Raw -Encoding UTF8 | ConvertFrom-Json; $census = $file.fields
        $whole = [string[]]@($file.subtrees)                                                     # ein Eintrag je Teilbaum (P3-R10)
        $paths = New-Object System.Collections.Generic.SortedSet[string] ([StringComparer]::Ordinal)
        $walk = { param($v, [string]$p)
            if ($null -eq $v -or $v -is [ValueType]) { return }
            if ($whole -ccontains $p) { [void]$paths.Add($p); return }
            if ($v -is [string]) { [void]$paths.Add($p); return }
            if ($v -is [System.Collections.IEnumerable]) { foreach ($x in $v) { & $walk $x "$p[]" }; return }
            foreach ($q in $v.PSObject.Properties) { & $walk $q.Value $(if ($p) { "$p.$($q.Name)" } else { $q.Name }) } }
        # ohne Drucken nennen Vorfaelle der Messung und des Rueckblicks ein Modul
        foreach ($i in @($D.Drucken.incidents)) { if ($null -ne $i.event) { & $walk @($i.event.unchecked) 'incidents[].event.unchecked' } }
        foreach ($i in @($D.Drucken.before.incidents)) { & $walk @($i.event.unchecked) 'before.incidents[].event.unchecked' }
        @($paths) | Should -Be @($census.PSObject.Properties.Name | Where-Object { $_ -like '*unchecked*' } | Sort-Object)
        @($paths | ForEach-Object { '{0}={1}' -f $_, $census.$_ }) | Should -Be @('before.incidents[].event.unchecked[].category=keyword', 'before.incidents[].event.unchecked[].id=keyword',
            'before.incidents[].event.unchecked[].text=composed', 'incidents[].event.unchecked[].category=keyword', 'incidents[].event.unchecked[].id=keyword', 'incidents[].event.unchecked[].text=composed')
        . (Join-Path $PSScriptRoot '../src/WorkerPerf.Mask.ps1'); $WorkerPerfMaskKeywordFields | Should -Contain 'unchecked.category'
    }
    It 'nennt ohne <_> das Zusammentreffen mit Vorfaellen dieser Kategorie, wo kein Vorfall zeitgleich ist' -ForEach 'Gegenstellen', 'Citrix', 'Laufwerke' {   # Fix-Runde 1
        $cat = $_; $ev = @(Get-Ev $D[$cat] { $true }); $ev.Count | Should -Be 4
        $want = 'overlap|{0}|Zusammentreffen mit einem Vorfall der Kategorie {0} ({0} nicht gemessen)' -f $cat
        foreach ($i in $ev) {
            $u = @($i.event.unchecked | ForEach-Object { '{0}|{1}|{2}' -f $_.id, $_.category, $_.text })
            if (@($i.event.patterns.id) -contains 'overlap') { $u.Count | Should -Be 0 -Because $i.text }
            else { $u | Should -Be @($want) -Because $i.text; $i.text | Should -BeLike "* Nicht geprüft: Zusammentreffen mit einem Vorfall der Kategorie $cat ($cat nicht gemessen)." }
            $i.text | Should -Not -Match 'Kein Muster erkannt'
        }
        @($ev | Where-Object { @($_.event.patterns.id) -contains 'overlap' }).Count | Should -Be 1   # chrome.exe, zeitgleich mit dem Arbeitsspeicher-Engpass
        @($D[$cat].before.incidents | Where-Object { @($_.event.unchecked).Count -gt 0 }).Count | Should -Be 0
    }
    It 'laesst die Muster der Laeufe ohne Laufwerke, Citrix und Gegenstellen unberuehrt' {
        foreach ($k in 'Voll', 'Prozesse', 'Drucken', 'Rueckblick') {
            @(@($D[$k].incidents) + @($D[$k].before.incidents) | Where-Object { $null -ne $_.event } | ForEach-Object { @($_.event.unchecked) } | Where-Object { $_.id -eq 'overlap' }).Count | Should -Be 0 -Because $k
        }
        @(Get-Ev $D.Prozesse { $true } | ForEach-Object { @($_.event.unchecked.id) -join ',' }) | Should -Be @('', 'users', 'users', 'users')
        @(Get-Ev $D.Drucken { $true } | ForEach-Object { @($_.event.unchecked.id) -join ',' }) | Should -Be @('', 'printdriver', 'printdriver', 'printdriver')
    }
    It 'behaelt das Zusammentreffen im maskierten Bericht' {
        $out = Join-Path $TestDrive 'gm.html'; [void](& $Report -Path $Runs.Gegenstellen -OutFile $out -RoleFile (Join-Path $TestDrive 'rep/roles.sim.json') -Mask Alles 6>$null)
        $u = (Get-Ev (Get-ReportData $out) { $_.event.kind -eq 'print' })[0].event.unchecked
        '{0}|{1}|{2}' -f $u[0].id, $u[0].category, $u[0].text | Should -Be 'overlap|Gegenstellen|Zusammentreffen mit einem Vorfall der Kategorie Gegenstellen (Gegenstellen nicht gemessen)'
    }
    It 'nennt eine Eingabeverzoegerung ohne Laufwerke "ohne erkannten Engpass" und kennzeichnet sie' {   # Fix-Runde 1
        foreach ($k in @('Voll') + $Names + 'Alle') {
            $oe = @($D[$k].incidents | Where-Object type -eq 'ohne-engpass'); $oe.Count | Should -BeGreaterThan 0 -Because $k
            $skipped = ($k -eq 'Laufwerke' -or $k -eq 'Alle')
            foreach ($i in $oe) {
                $i.unverified | Should -Be $skipped -Because "$k $($i.text)"
                if ($skipped) { $i.text | Should -Match '^\d\d:\d\d:\d\d–\d\d:\d\d:\d\d: Eingabeverzögerung ohne erkannten Engpass auf dem Worker \(Spitze ' }
                else { $i.text | Should -Match '^\d\d:\d\d:\d\d–\d\d:\d\d:\d\d: Eingabeverzögerung ohne Engpass auf dem Worker \(Spitze ' }
            }
            @($D[$k].incidents | Where-Object { $_.type -ne 'ohne-engpass' -and $null -ne $_.PSObject.Properties['unverified'] }).Count | Should -Be 0 -Because $k
        }
        @($D.Laufwerke.incidents | Where-Object type -eq 'ohne-engpass').Count | Should -Be 5; @($D.Alle.incidents | Where-Object type -eq 'ohne-engpass').Count | Should -Be 5
    }
    It 'laesst ohne -Skip nichts ungeprueft und haelt Ereignisse und Rueckblick getrennt' {
        @(Get-Ev $D.Voll { @($_.event.unchecked).Count -gt 0 }).Count | Should -Be 0; @(Get-Ev $D.Voll { $true }).Count | Should -Be 4
        @($D.Voll.before.incidents | Where-Object { @($_.event.unchecked).Count -gt 0 }).Count | Should -Be 0
        # Aussage angepasst: der Rueckblick der simulierten Stunde hat seit der Korrekturrunde des Ereignisplans vier Vorfaelle
        @(Get-Ev $D.Ereignisse { $true }).Count | Should -Be 0; @($D.Ereignisse.before.incidents).Count | Should -Be 4
    }
}
