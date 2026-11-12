BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1')
    $script:Capture = Join-Path $PSScriptRoot '../src/Start-WorkerPerfCapture.ps1'
    $script:Runs = New-SkipRuns (Join-Path $TestDrive 'runs')
    $script:Names = @('Prozesse', 'Laufwerke', 'Citrix', 'Ereignisse', 'Rueckblick', 'Drucken', 'Gegenstellen')
    $script:Files = @{ Prozesse = @('processes.csv', 'procinfo.csv', 'procend.csv', 'inputdelay_proc.csv'); Laufwerke = @('volumes.csv', 'shares.csv'); Citrix = @('citrix.csv')
        Ereignisse = @('events.csv'); Rueckblick = @('events_before.csv'); Drucken = @('printdrivers.csv', 'printqueues.csv'); Gegenstellen = @('probes.csv') }
    $script:Ids = @{ Prozesse = @('process', 'input.process'); Laufwerke = @('disk.latency', 'smb.latency', 'profile.map'); Citrix = @('ica.rtt', 'ica.latency'); Ereignisse = @(); Rueckblick = @()
        Drucken = @('print.drivers', 'print.queues'); Gegenstellen = @('probe.connect') }
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
    It 'legt die Dateien von <_> nicht an, vermerkt ihre Quellen und laesst alles andere stehen' -ForEach 'Prozesse', 'Laufwerke', 'Citrix', 'Ereignisse', 'Rueckblick', 'Drucken', 'Gegenstellen' {
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
                'Start-WorkerPerfProbes', 'Receive-WorkerPerfProbes') | ForEach-Object { "function $_ { throw 'Testaufruf $_' }" }) -join "`n"
        $none = (& (New-PatchedSource (Join-Path $TestDrive 'srcthrow') $throwing) -Simulate -DurationMinutes 60 -Skip $Names -OutputPath (Join-Path $TestDrive 'throw') 6>$null 3>$null) | Select-Object -Last 1
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
        ($a | Out-String) | Should -Match 'Gemessen: Basis, Prozesse, Laufwerke, Ereignisse, Rueckblick, Drucken, Gegenstellen\s+Nicht gemessen \(-Skip\): Citrix'
        Get-Shape ([string]$a[-1]) | Should -BeExactly (Get-Shape $Runs.Citrix)
        $b = @(& $Capture -Simulate -DurationMinutes 60 -EventLookbackDays 0 -Skip 'rueckblick,RUECKBLICK', 'Zustand' -OutputPath (Join-Path $TestDrive 'b') 6>&1)
        Get-Shape ([string]$b[-1]) | Should -BeExactly (Get-Shape $Runs.Rueckblick)   # Zustand: angenommen, ohne Wirkung, auch auf der Konsole
        $console = $b | Out-String
        $console | Should -Match 'Nicht gemessen \(-Skip\): Rueckblick\r?\n'; $console | Should -Not -Match 'Zustand' 
    }
    It 'lehnt einen unbekannten Wert ab, bevor etwas angelegt wird' {
        $dir = Join-Path $TestDrive 'x'
        { & $Capture -Simulate -DurationMinutes 60 -Skip Prozesse, Netz -OutputPath $dir 6>$null } | Should -Throw "*'Netz'*Gueltige Werte: Prozesse, Laufwerke, Citrix, Ereignisse, Rueckblick, Drucken, Gegenstellen, Zustand.*"
        Test-Path $dir | Should -BeFalse
    }
    It 'laesst die Aufzeichnung ohne -Skip wie bisher, bis auf das neue Feld Skip' {
        $m = Get-Meta $Runs.Voll; $names = @($m.PSObject.Properties.Name)
        Get-CsvNames $Runs.Voll | Should -Be @($WorkerPerfHeaders.Keys | Sort-Object)
        # Aussage angepasst: EventReadCounts und LookbackReadCounts kamen nach dem Plan dazu; Skip steht hinter ihnen
        $names | Should -Be @('SchemaVersion', 'Computer', 'OS', 'LogicalProcessors', 'PhysicalMemoryMB', 'FastIntervalSeconds', 'IntervalSeconds', 'BurstIntervalSeconds', 'BurstHoldSeconds', 'MaxSizeMB',
            'StartTime', 'EndTime', 'EndReason', 'EndMessage', 'Ticks', 'Snapshots', 'SkippedTicks', 'Simulated', 'IncludeCommandLine', 'EventLookbackDays', 'LookbackCapped', 'EventReadCounts', 'LookbackReadCounts', 'Skip', 'CollectorPid', 'Endpoints', 'Sources', 'SourceErrors')
        @($m.Skip).Count | Should -Be 0; $m.EventLookbackDays | Should -Be 7; @($m.Endpoints).Count | Should -Be 3
        @($m.Sources.PSObject.Properties | Where-Object { -not $_.Value.Available -or $_.Value.Detail -notlike 'Simulation*' }).Count | Should -Be 0
    }
    It 'nennt beim Start die gemessenen und die weggelassenen Kategorien' {
        $out = Get-Content (Join-Path $TestDrive 'runs/Voll.console.txt') -Raw   # die Konsolenausgabe des vollen Laufs aus New-SkipRuns
        $out | Should -Match 'laeuft: [^\r\n]+\r?\nGemessen: Basis, Prozesse, Laufwerke, Citrix, Ereignisse, Rueckblick, Drucken, Gegenstellen\r?\nNicht gemessen \(-Skip\): keine\r?\n'
    }
}
