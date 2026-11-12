# Messkategorien – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `Start-WorkerPerfCapture.ps1 -Skip <Kategorie>[,…]` lässt einzelne Messkategorien weg (keine Abfrage, keine Datei), die Basis läuft immer, und der Bericht sagt an jeder Stelle, die von einer weggelassenen Kategorie abhängt, „nicht gemessen" mit dem Grund; ohne `-Skip` bleibt alles wie bisher.

**Architecture:** Eine Tabelle der Kategorien in `src/WorkerPerf.Common.ps1` (Dateien, Quellen, abhängige Stellen des Berichts) ist die einzige Stelle, die Kategorien kennt. `-Skip`, `-NoCitrix` und `-EventLookbackDays 0` werden beim Start auf **eine** Darstellung abgebildet: die Liste der kanonischen Kategorienamen in der Reihenfolge der Tabelle (`Resolve-WorkerPerfSkip`). Diese Liste steuert, welche Dateien der Collector anlegt und welche Aufrufe er macht, geht als `-Skip` an beide Datenquellen (die dafür nichts lesen), steht als `Skip` in `meta.json` und kommt über den Lader als `Model.Skip` in die Auswertung. Die Berichtsdaten erhalten einen Block `skipped` (Kategorie, Grund, abhängige Stellen); Vorfallstexte und Muster nennen den Grund, statt „keine" zu sagen. Die Anzeige wird auf der heutigen Seite gebaut; der geführte Bericht liest später dieselben Daten.

**Tech Stack:** Windows PowerShell 5.1 (Laufzeit), HTML/JavaScript ohne Bibliotheken. Tests: PowerShell 7 mit Pester 5, Node.js mit Playwright.

**Spec:** `docs/superpowers/specs/2026-11-12-messkategorien-design.md`. Wird **nach** Task 10 von `docs/superpowers/plans/2026-11-11-ereignisse-abstuerze-drucken.md` ausgeführt (Stand der Quellen: `Initialize-WorkerPerfSource` beider Quellen mit `-EventConfig`; Windows-Quelle mit `Get-WorkerPerfEventsBefore`, `Get-WorkerPerfPrintDrivers`, `Get-WorkerPerfPrintQueues`, `Sources['events.<id>']` je Protokoll; der Collector liest `events.json`) und nach `docs/superpowers/plans/2026-11-11-maskierung.md`; **vor** `docs/superpowers/plans/2026-11-11-gefuehrter-bericht.md` (siehe „Folgen für den Plan Geführter Bericht").

## Global Constraints

- **Windows PowerShell 5.1:** jede `src/*.ps1` beginnt mit `#Requires -Version 5.1`, ist reines ASCII (Umlaute nur in JSON-Textdateien und `src/report-template.html`), ohne PowerShell-7-Syntax und ohne API, die es nur unter .NET Core gibt; eingebettetes C# auf Stand C# 5. `tests/Compat.Tests.ps1` erzwingt einen Teil davon und prüft neue Dateien unter `src/` automatisch.
- **Tests unter Linux:** PowerShell 7, Pester 5, Node/Playwright. Windows-Aufrufe bleiben dünn und werden über Platzhalter getestet (`tests/WindowsStandIns.ps1`). Alle Tests: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`. Browserprüfungen: `pwsh -NoProfile -File tests/New-TestReports.ps1 -OutDir <workspace>/scratch/wp-reports && node tests/report-browser.js <workspace>/scratch/wp-reports`, Erfolg: letzte Zeile `browser checks passed: <n>`, Rückgabewert 0.
- **Temporäre Pfade:** nur unter `<workspace>/scratch/` (`<workspace>` = Arbeitsordner der Ausführung dieses Plans unter `.superpowers/sdd/`), nie unter `/tmp`.
- **Listen:** Funktionen, die Listen liefern, geben schlichte Pipeline-Ausgabe; Aufrufer schreiben `@(...)`.
- **Bericht:** eine einzelne HTML-Datei ohne externe Anfragen, ohne eingebundene Bibliotheken oder Schriften; Status immer als Symbol und Wort; deutsche Texte aus JSON-Dateien (`src/texts.de.json`, `src/events.json`), nicht aus dem Code.
- **Collector liest nur:** keine Einstellung des Servers wird geändert, kein Protokoll eingeschaltet. Ein Aufruf der Quelle, der scheitert, wird übersprungen, je Quelle einmal gewarnt und in `meta.json` (`SourceErrors`) vermerkt.
- **Öffentliches Repository:** keine Daten eines echten Servers im Repository (keine Software-Liste, Freigaben-, Benutzer-, Client- oder Servernamen, keine Ereignistexte); Tests verwenden erfundene Namen. Aufzeichnungen, Berichte und Ergebnisse des Prüfskripts werden nicht eingecheckt.
- **Bestand:** die acht Vorfälle der simulierten Stunde und alle bestehenden Tests bleiben grün, außer eine Task nennt genau, welche Aussage sich ändert und warum.
- **TDD:** jede Task schreibt zuerst den fehlschlagenden Test.
- **Commits:** englisch, im Imperativ, ein Commit je Task; keine Modellnamen in Code, Kommentaren oder Dokumenten.
- **Werte der Spezifikation:** Werte von `-Skip` genau `Prozesse`, `Laufwerke`, `Citrix`, `Ereignisse`, `Rueckblick`, `Drucken`, `Gegenstellen`, `Zustand`; ohne Rücksicht auf Groß- und Kleinschreibung, doppelte zählen einmal, ein unbekannter Wert bricht den Start mit den gültigen Werten in der Meldung ab; Vermerk in den Quellen `abgeschaltet (-Skip <Wert>)`; Datenformat bleibt 3; Satz beim Verursacher „Prozesse wurden bei dieser Messung nicht erfasst."; Wort im Bericht „nicht gemessen".

## Review Focus

Jede Zeile ist durch einen Test in der genannten Task abgesichert (im Testcode mit `# Review Focus n` markiert).

1. **Alle Kategorien zugleich weggelassen.** Erwartet: die Aufzeichnung enthält nur die Basis, der Bericht entsteht, die Vorfälle der Basis haben dieselben Zeitfenster wie im vollständigen Lauf, die Seite zeigt keinen Skriptfehler. → Tasks 1, 2, 3, 5
2. **Eine Aufzeichnung von vor diesem Plan** (`meta.json` ohne `Skip`, auch Format 2). Erwartet: gilt als vollständig gemessen; der Bericht ist derselbe wie für dieselbe Aufzeichnung mit `"Skip": []`. → Task 3
3. **Eine Kategorie fehlt, die eine Vorfallserklärung bräuchte** (CPU-Engpass ohne `Prozesse`, Absturz des Druckdienstes ohne `Drucken`, Verzögerung ohne Engpass ohne `Gegenstellen`). Erwartet: der Vorfall bleibt, an der Stelle der Erklärung steht der Grund; nie „keine Prozessdaten", „Ohne Benutzersitzung" oder „Kein Muster erkannt" für etwas, das nicht gemessen wurde. → Task 4
4. **Derselbe Wert doppelt, in anderer Schreibweise oder als eine Zeichenkette mit Kommas** (`-Skip prozesse,PROZESSE`; `powershell.exe -File … -Skip Prozesse,Rueckblick` übergibt *eine* Zeichenkette). Erwartet: dieselbe Aufzeichnung wie mit dem einfachen Wert. → Task 1
5. **`-Skip` zusammen mit den alten Schaltern**, auch widersprüchlich (`-NoCitrix -Skip Citrix`; `-Skip Rueckblick -EventLookbackDays 3`). Erwartet: eine Darstellung, kein Fehler; weggelassen gewinnt, `meta.json` nennt `EventLookbackDays` 0. → Task 1

## File Structure

| Datei | Verantwortung |
|---|---|
| `src/WorkerPerf.Common.ps1` | Tabelle der Kategorien, `-Skip` auflösen, Vermerk in den Quellen, Ausgabe `skipped` für den Bericht |
| `src/Start-WorkerPerfCapture.ps1`, `src/WorkerPerf.Capture.ps1` | Parameter `-Skip`, Meldung beim Start, `meta.json`, nur die Dateien und Aufrufe der gemessenen Kategorien |
| `src/WorkerPerf.Sources.Simulation.ps1`, `src/WorkerPerf.Sources.Windows.ps1` | `-Skip` statt `-NoCitrix`; für eine weggelassene Kategorie wird nichts geprüft und nichts gelesen |
| `src/WorkerPerf.Load.ps1`, `src/New-WorkerPerfReport.ps1` | `Model.Skip`, Block `skipped` |
| `src/WorkerPerf.Findings.ps1`, `src/WorkerPerf.Events.ps1` | Grund in Vorfallstexten, Ursache `notmeasured`, nicht geprüfte Muster |
| `src/WorkerPerf.Mask.ps1`, `tests/MaskCensus.json` | neue Textfelder einordnen; der Vermerk einer weggelassenen Quelle bleibt im maskierten Bericht |
| `src/texts.de.json`, `src/report-template.html`, `README.md` | Texte, Anzeige auf der heutigen Seite, Bedienung |
| `tests/Skip.Tests.ps1` (neu), `tests/TestHelpers.ps1`, bestehende Testdateien, `tests/report-browser.js` | Tests |

## Kategorienmodell (gilt für alle Tasks)

`$script:WorkerPerfCategories` in `src/WorkerPerf.Common.ps1`: `[ordered]` Name → `@{ Files; Sources; Places; Active }`, in dieser Reihenfolge und mit genau diesen Werten.

| Kategorie | Aufrufe der Quelle | Dateien (`Files`) | Quellen (`Sources`) | Stellen im Bericht (`Places`) |
|---|---|---|---|---|
| `Prozesse` | `Processes` im Schnappschuss, `Get-WorkerPerfServices`, `InputProcesses` im schnellen Takt | `processes.csv`, `procinfo.csv`, `procend.csv`, `inputdelay_proc.csv` | `process`, `input.process` | `procs`, `apps`, `sessions.resources`, `incidents.contributors`, `incidents.delayProcs`, `print.processes` |
| `Laufwerke` | `Volumes`, `Shares` im schnellen Takt; unter Windows die Zuordnung der Profilcontainer | `volumes.csv`, `shares.csv` | `disk.latency`, `smb.latency`, `profile.map` | `volumes`, `shares`, `sessions.profile` |
| `Citrix` | `Citrix` im Schnappschuss | `citrix.csv` | `ica.rtt`, `ica.latency` | `citrix`, `sessions.rtt`, `incidents.ica` |
| `Ereignisse` | `Get-WorkerPerfEvents` | `events.csv` | – | `events`, `sessions.events`, `incidents.events` |
| `Rueckblick` | `Get-WorkerPerfEventsBefore` | `events_before.csv` | – | `before` |
| `Drucken` | `Get-WorkerPerfPrintDrivers`, `Get-WorkerPerfPrintQueues` | `printdrivers.csv`, `printqueues.csv` | `print.drivers`, `print.queues` | `print.drivers`, `print.queues` |
| `Gegenstellen` | `Start-WorkerPerfProbes`, `Receive-WorkerPerfProbes` | `probes.csv` | `probe.connect` | `probes`, `incidents.endpoints` |
| `Zustand` | – | – | – | – |

- `Active` ist für `Zustand` `$false`, sonst `$true`. Ein nicht aktiver Wert wird von `-Skip` angenommen und hat keine Wirkung: er steht weder in `meta.json` noch auf der Konsole noch im Bericht. **Einhängepunkt für den Plan zum Zustandsbild:** die Zeile `Zustand` der Tabelle (`Active = $true`, `Files = @('health.json')`, Stellen), die Texte `skip.label.Zustand` und `skip.text.Zustand`, und im Collector das Lesen des Zustandsbilds vor dem ersten Takt hinter `$skip -notcontains 'Zustand'`.
- **Basis** (nicht abschaltbar): `ticks.csv`, `inputdelay.csv`, `snapshots.csv`, `sessions.csv`, dazu `meta.json` und `thresholds.json`.
- Die Quellen `events.<id>` gehören `Ereignisse` und `Rueckblick` gemeinsam: sie gelten nur als abgeschaltet, wenn beide weggelassen sind (Vermerk `abgeschaltet (-Skip Ereignisse,Rueckblick)`).

---

### Task 1: Kategorien, `-Skip` am Collector und `meta.json`

**Files:**
- Modify: `src/WorkerPerf.Common.ps1`, `src/WorkerPerf.Capture.ps1` (`New-WorkerPerfWriters`), `src/Start-WorkerPerfCapture.ps1` (Hilfe, `param`, Einrichtung, `$meta`, Startmeldung, Rückblick und Treiberliste beim Start, `$readSlot`, Schnappschuss, Proben), `tests/TestHelpers.ps1`, `tests/Collector.Tests.ps1` (eine Aussage)
- Create: `tests/Skip.Tests.ps1`
- Test: `tests/Common.Tests.ps1`, `tests/Skip.Tests.ps1`

**Interfaces:**
- Produces:
  - `$script:WorkerPerfCategories` wie oben.
  - `Resolve-WorkerPerfSkip([string[]]$Skip, [bool]$NoCitrix = $false, [int]$EventLookbackDays = 7) -> string[]`: jeder Wert wird an Kommas geteilt und von Leerraum befreit, leere Teile entfallen; Vergleich ohne Rücksicht auf Groß- und Kleinschreibung; `-NoCitrix` fügt `Citrix` hinzu, `-EventLookbackDays 0` fügt `Rueckblick` hinzu; Ergebnis sind die aktiven Kategorien in der Reihenfolge der Tabelle, jede einmal. Unbekannter Wert: `throw "Unbekannte Kategorie '<Wert>' bei -Skip. Gueltige Werte: Prozesse, Laufwerke, Citrix, Ereignisse, Rueckblick, Drucken, Gegenstellen, Zustand."`
  - `Get-WorkerPerfSkipDetail([string[]]$Categories) -> string` = `'abgeschaltet (-Skip ' + ($Categories -join ',') + ')'`; `$script:WorkerPerfSkipDetailPattern = '^abgeschaltet \(-Skip [A-Za-z]+(,[A-Za-z]+)*\)$'` (Task 3 nutzt es).
  - `Set-WorkerPerfSkippedSources -Sources <ordered> -Skip [string[]] -EventLogIds [string[]]`: setzt in `Sources` für jede Quelle einer weggelassenen Kategorie `@{ Available = $false; Detail = (Get-WorkerPerfSkipDetail <Kategorie>) }` (legt den Eintrag an, wenn er fehlt); sind `Ereignisse` und `Rueckblick` beide weggelassen, ebenso für jeden vorhandenen Schlüssel `events.*` und jedes `events.<id>` aus `-EventLogIds`, mit `Get-WorkerPerfSkipDetail @('Ereignisse', 'Rueckblick')`.
  - `New-WorkerPerfWriters -RunDir [string] -Skip [string[]] = @()`: legt nur die Dateien an, die zu keiner weggelassenen Kategorie gehören; das Ergebnis enthält nur diese Schlüssel.
  - Collector: Parameter `[string[]]$Skip = @()`. `$skip = @(Resolve-WorkerPerfSkip $Skip ([bool]$NoCitrix) $EventLookbackDays)` direkt nach dem Einbinden von `WorkerPerf.Common.ps1`, vor dem Initialisieren der Quelle und vor dem Anlegen des Ordners. `meta.json`: neues Feld `Skip` (die Liste, ohne `-Skip` `[]`) nach `LookbackCapped`; `EventLookbackDays` ist 0 ohne `Rueckblick`, `Endpoints` leer ohne `Gegenstellen`; `Sources` nach `Set-WorkerPerfSkippedSources` (mit den Protokoll-Ids der Ereigniskonfiguration, die der Collector seit Task 10 liest). Für eine weggelassene Kategorie macht der Collector keinen ihrer eigenständigen Aufrufe (`Get-WorkerPerfServices`, `Get-WorkerPerfEvents`, `Get-WorkerPerfEventsBefore`, die Druck- und Probenfunktionen) und schreibt keine ihrer Zeilen; ohne `Prozesse` bleiben in `snapshots.csv` die Spalten `Processes` und `RowsWritten` leer, `Get-WorkerPerfProcessRows` und das Prozessgedächtnis entfallen. An die Quelle geht in dieser Task weiter `-NoCitrix:($skip -contains 'Citrix')` (Task 2 ersetzt das).
  - Startmeldung, zwei Zeilen nach „WorkerPerf-Aufzeichnung laeuft": `Gemessen: Basis, Prozesse, Laufwerke, Citrix, Ereignisse, Rueckblick, Drucken, Gegenstellen` (nur die gemessenen) und `Nicht gemessen (-Skip): Prozesse, Rueckblick` bzw. `Nicht gemessen (-Skip): keine`.
  - `tests/TestHelpers.ps1`: `Invoke-SimCapture([string]$OutDir, [hashtable]$Extra = @{})` reicht `$Extra` an den Collector durch; `New-SkipRuns([string]$OutDir) -> ordered`: Schlüssel `Voll` (ohne `-Skip`), die sieben Kategorienamen (je `-Skip <Name>`), `Alle` (alle sieben); Wert ist der Aufzeichnungsordner.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben**

`tests/Common.Tests.ps1`:

```powershell
Describe 'Messkategorien' {
    It 'liefert die Kategorien in der Reihenfolge der Tabelle, jede einmal, ohne Ruecksicht auf die Schreibweise' {   # Review Focus 4
        Resolve-WorkerPerfSkip @('rueckblick', 'PROZESSE', 'Prozesse') | Should -Be @('Prozesse', 'Rueckblick')
        Resolve-WorkerPerfSkip @('Drucken,citrix', ' Zustand ', '') | Should -Be @('Citrix', 'Drucken')   # eine Zeichenkette mit Kommas; Zustand: angenommen, ohne Wirkung
        @(Resolve-WorkerPerfSkip @()).Count | Should -Be 0
    }
    It 'bildet die alten Schalter auf dieselbe Liste ab' {   # Review Focus 5
        Resolve-WorkerPerfSkip @() $true | Should -Be @('Citrix'); Resolve-WorkerPerfSkip @('Citrix') $true | Should -Be @('Citrix')
        Resolve-WorkerPerfSkip @() $false 0 | Should -Be @('Rueckblick'); Resolve-WorkerPerfSkip @('Rueckblick') $false 3 | Should -Be @('Rueckblick')
    }
    It 'lehnt einen unbekannten Wert mit den gueltigen Werten ab' {
        { Resolve-WorkerPerfSkip @('Prozesse', 'Netz') } | Should -Throw "*'Netz'*Gueltige Werte: Prozesse, Laufwerke, Citrix, Ereignisse, Rueckblick, Drucken, Gegenstellen, Zustand.*"
    }
}
```

`tests/Skip.Tests.ps1`:

```powershell
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
    function Get-CsvNames([string]$Run) { , @(Get-ChildItem $Run -Filter *.csv | ForEach-Object Name | Sort-Object) }
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
    }
    It 'misst ohne alle Kategorien die Basis wie im vollstaendigen Lauf' {   # Review Focus 1
        $m = Get-Meta $Runs.Alle
        Get-CsvNames $Runs.Alle | Should -Be @('inputdelay.csv', 'sessions.csv', 'snapshots.csv', 'ticks.csv')
        @($m.Skip) | Should -Be $Names; $m.EventLookbackDays | Should -Be 0; @($m.Endpoints).Count | Should -Be 0; @($m.SourceErrors.PSObject.Properties).Count | Should -Be 0
        $m.Sources.'events.application'.Detail | Should -Be 'abgeschaltet (-Skip Ereignisse,Rueckblick)'; $m.Sources.'input.session'.Available | Should -BeTrue; $m.Sources.sessions.Available | Should -BeTrue
        $base = { param($run) (Get-Content (Join-Path $run 'ticks.csv') | ForEach-Object { $_.Split(',')[2..16] -join ',' }) -join "`n" }   # ElapsedSec bis NetSentBps
        & $base $Runs.Alle | Should -BeExactly (& $base $Runs.Voll)
        Get-Content (Join-Path $Runs.Alle 'inputdelay.csv') -Raw | Should -BeExactly (Get-Content (Join-Path $Runs.Voll 'inputdelay.csv') -Raw)
        $snaps = @(Import-Csv (Join-Path $Runs.Alle 'snapshots.csv'))
        @($snaps | Where-Object Kind -in 'R', 'K').Count | Should -Be 240; $snaps[0].Sessions | Should -Be '25'; $snaps[0].Processes | Should -Be ''; $snaps[0].RowsWritten | Should -Be ''
        @(Import-Csv (Join-Path $Runs.Alle 'sessions.csv') | Where-Object P -eq '0').Count | Should -Be 26
    }
    It 'haelt Ereignisse und Rueckblick unabhaengig' {
        @(Import-Csv (Join-Path $Runs.Ereignisse 'events_before.csv')).Count | Should -Be 5; (Get-Meta $Runs.Ereignisse).Sources.'events.application'.Available | Should -BeTrue
        @(Import-Csv (Join-Path $Runs.Rueckblick 'events.csv')).Count | Should -Be 13; (Get-Meta $Runs.Rueckblick).EventLookbackDays | Should -Be 0   # weggelassen gewinnt gegen 7 Tage
    }
    It 'ergibt mit den alten Schaltern, doppelt, in anderer Schreibweise und als eine Zeichenkette dieselbe Aufzeichnung' {   # Review Focus 4 und 5
        $a = @(& $Capture -Simulate -DurationMinutes 60 -NoCitrix -OutputPath (Join-Path $TestDrive 'a') 6>&1)
        ($a | Out-String) | Should -Match 'Gemessen: Basis, Prozesse, Laufwerke, Ereignisse, Rueckblick, Drucken, Gegenstellen\s+Nicht gemessen \(-Skip\): Citrix'
        Get-Shape ([string]$a[-1]) | Should -BeExactly (Get-Shape $Runs.Citrix)
        $b = (& $Capture -Simulate -DurationMinutes 60 -EventLookbackDays 0 -Skip 'rueckblick,RUECKBLICK', 'Zustand' -OutputPath (Join-Path $TestDrive 'b') 6>$null) | Select-Object -Last 1
        Get-Shape $b | Should -BeExactly (Get-Shape $Runs.Rueckblick)   # Zustand: angenommen, ohne Wirkung
    }
    It 'lehnt einen unbekannten Wert ab, bevor etwas angelegt wird' {
        $dir = Join-Path $TestDrive 'x'
        { & $Capture -Simulate -DurationMinutes 60 -Skip Prozesse, Netz -OutputPath $dir 6>$null } | Should -Throw "*'Netz'*Gueltige Werte: Prozesse, Laufwerke, Citrix, Ereignisse, Rueckblick, Drucken, Gegenstellen, Zustand.*"
        Test-Path $dir | Should -BeFalse
    }
    It 'laesst die Aufzeichnung ohne -Skip wie bisher, bis auf das neue Feld Skip' {
        $m = Get-Meta $Runs.Voll; $names = @($m.PSObject.Properties.Name)
        Get-CsvNames $Runs.Voll | Should -Be @($WorkerPerfHeaders.Keys | Sort-Object)
        $names | Should -Be @('SchemaVersion', 'Computer', 'OS', 'LogicalProcessors', 'PhysicalMemoryMB', 'FastIntervalSeconds', 'IntervalSeconds', 'BurstIntervalSeconds', 'BurstHoldSeconds', 'MaxSizeMB',
            'StartTime', 'EndTime', 'EndReason', 'EndMessage', 'Ticks', 'Snapshots', 'SkippedTicks', 'Simulated', 'IncludeCommandLine', 'EventLookbackDays', 'LookbackCapped', 'Skip', 'CollectorPid', 'Endpoints', 'Sources', 'SourceErrors')
        @($m.Skip).Count | Should -Be 0; $m.EventLookbackDays | Should -Be 7; @($m.Endpoints).Count | Should -Be 3
        @($m.Sources.PSObject.Properties | Where-Object { -not $_.Value.Available -or $_.Value.Detail -notlike 'Simulation*' }).Count | Should -Be 0
    }
}
```

Die Zeilenzahlen der vollständigen Aufzeichnung prüft weiter `tests/Collector.Tests.ps1`. Dort ändert sich eine Aussage, weil `-EventLookbackDays 0` jetzt `-Skip Rueckblick` ist und die Datei einer weggelassenen Kategorie nicht angelegt wird (Abschnitt 4 der Spezifikation): in `'liest ohne Rueckblick nichts vor dem Start'` wird `@(Get-Content (Join-Path $run 'events_before.csv')).Count | Should -Be 1` zu `Test-Path (Join-Path $run 'events_before.csv') | Should -BeFalse`, und die Zeile zu `meta.json` prüft zusätzlich `@(…).Skip | Should -Be @('Rueckblick')` (der alte Schalter allein). `tests/Skip.Tests.ps1` zeichnet elf simulierte Stunden auf und läuft einige Minuten.

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Common.Tests.ps1, tests/Skip.Tests.ps1 -Output Minimal"`
Expected: FAIL, `Resolve-WorkerPerfSkip` nicht definiert; Parameter `Skip` nicht gefunden

- [ ] **Step 3: Kategorientabelle, `Resolve-WorkerPerfSkip`, `Get-WorkerPerfSkipDetail`, `Set-WorkerPerfSkippedSources` und `New-WorkerPerfWriters -Skip` mit den Signaturen der Interfaces umsetzen**

- [ ] **Step 4: Collector umstellen** – ein Schreiber, den es nicht gibt, heißt: der zugehörige Aufruf entfällt (auch `Get-WorkerPerfServices`, der Rückblick, die Treiberliste, das Lesen im regulären Takt, Start und Abholen der Proben). Hilfe des Skripts: `.PARAMETER Skip` mit den acht Werten und der Basis; bei `-NoCitrix` und `-EventLookbackDays` der Verweis auf den gleichbedeutenden Wert; in der Beschreibung der Satz, dass Dateien einer weggelassenen Kategorie fehlen.

- [ ] **Step 5: Tests ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`
Expected: `Failed: 0`

- [ ] **Step 6: Commit**

```bash
git add src/WorkerPerf.Common.ps1 src/WorkerPerf.Capture.ps1 src/Start-WorkerPerfCapture.ps1 tests/TestHelpers.ps1 tests/Common.Tests.ps1 tests/Collector.Tests.ps1 tests/Skip.Tests.ps1
git commit -m "Add capture categories and -Skip to the collector"
```

---

### Task 2: Beide Datenquellen lesen eine weggelassene Kategorie nicht

**Files:**
- Modify: `src/WorkerPerf.Sources.Simulation.ps1`, `src/WorkerPerf.Sources.Windows.ps1` (`Initialize-WorkerPerfSource`, `Get-WorkerPerfFastSample`, `Get-WorkerPerfSnapshot`, `Get-WorkerPerfServices`, die Ereignis-, Druck- und Probenfunktionen), `src/Start-WorkerPerfCapture.ps1` (Aufruf von `Initialize-WorkerPerfSource`), `tests/WindowsStandIns.ps1`, `tests/Collector.Tests.ps1` (Parameterliste eines Platzhalters)
- Test: `tests/Simulation.Tests.ps1`, `tests/WindowsSource.Tests.ps1`

**Interfaces:**
- Consumes: `$script:WorkerPerfCategories`, die Liste `$skip` des Collectors (Task 1).
- Produces:
  - `Initialize-WorkerPerfSource` beider Quellen: `[string[]]$Skip = @()` ersetzt `[switch]$NoCitrix`; die übrigen Parameter bleiben, wie Task 10 sie hinterlässt. Der Collector übergibt `-Skip $skip`. Für eine weggelassene Kategorie prüft und öffnet die Quelle nichts, trägt keinen Eintrag in `Sources` ein (den Vermerk setzt der Collector) und liefert aus jedem Aufruf der Tabelle nichts: leere Listen `Processes`, `Citrix`, `Volumes`, `Shares`, `InputProcesses`; `Get-WorkerPerfServices` eine leere Tabelle; `Get-WorkerPerfEventsBefore` `@{ Events = @(); Capped = @() }`; `Endpoints` leer. Die Werte der Basis ändern sich nicht (die Simulation rechnet die Summen der Datenträger und des Netzwerks weiter aus ihren Laufwerken und Freigaben).
  - Windows, was jeweils entfällt: `Prozesse` – `Win32_Process`, `Win32_Service`, Zählergruppe `inputProcess`; `Laufwerke` – Zählergruppen `volumes` und `shares`, die Abfrage der Profilcontainer beim Start und im Schnappschuss, die Sitzungsabfrage im schnellen Takt; `Citrix` – wie bisher mit `-NoCitrix`; `Ereignisse` und `Rueckblick` zusammen – auch `Get-WinEvent -ListLog`; `Drucken` – Prüfung der Kategorie `Print Queue` und Treiberabfrage; `Gegenstellen` – Übersetzen des Probentyps und jeder Verbindungsaufbau, auch wenn `Start-WorkerPerfProbes -Endpoints` Ziele nennt.
  - Simulation: `$script:WorkerPerfSimReads` (Hashtable, von `Initialize-WorkerPerfSource` geleert) zählt je Aufruf, in dem die Quelle Daten einer Art zusammenstellt: `process`, `input.process`, `services`, `volumes`, `shares`, `citrix`, `events`, `eventsbefore`, `printdrivers`, `printqueues`, `probes`.
  - `tests/WindowsStandIns.ps1`: jeder Platzhalter zählt seinen Aufruf in `$script:WinFake.Calls` (Hashtable, von `Reset-WinStandIns` geleert): `check:<Kategorie>` (`Test-WorkerPerfWinCounter`), `perf:<Kategorie>` (`Read-WorkerPerfWinCategory`), `cim:<Klasse>` (`Get-CimInstance`), `cimclass:<Klasse>` (`Get-CimClass`), `winevent:list` und `winevent:read` (`Get-WinEvent` mit und ohne `-ListLog`), `wts` (`Get-WinSessionRaw`), `registry:print` (der Platzhalter aus Task 10 für die Isolierungsgruppen).

- [ ] **Step 1: Die fehlschlagenden Tests schreiben**

`tests/Simulation.Tests.ps1` (neuer `Describe` am Dateiende):

```powershell
Describe 'Simulation mit weggelassenen Kategorien' {
    BeforeAll {
        function Invoke-SimReads([string[]]$Skip) {   # jeder Aufruf der Schnittstelle einmal, wie der Collector sie nutzt
            [void](Initialize-WorkerPerfSource -StartTime $Start -Skip $Skip); Set-SimTime 47.5
            $r = @{ Fast = (Get-WorkerPerfFastSample); Snap = (Get-WorkerPerfSnapshot -Kind K); Services = (Get-WorkerPerfServices); Events = @(Get-WorkerPerfEvents -Since $Start)
                Before = (Get-WorkerPerfEventsBefore -Days 7 -Until $Start); Drivers = @(Get-WorkerPerfPrintDrivers); Queues = @(Get-WorkerPerfPrintQueues) }
            Start-WorkerPerfProbes; Set-SimTime 47.6; $r.Probes = @(Receive-WorkerPerfProbes); $r.Reads = $script:WorkerPerfSimReads.Clone(); $r
        }
        $script:ReadKeys = @{ Prozesse = @('process', 'input.process', 'services'); Laufwerke = @('volumes', 'shares'); Citrix = @('citrix'); Ereignisse = @('events'); Rueckblick = @('eventsbefore')
            Drucken = @('printdrivers', 'printqueues'); Gegenstellen = @('probes') }
    }
    AfterAll { [void](Initialize-WorkerPerfSource -StartTime $Start) }
    It 'liest die Quellen von <_> nicht und alle anderen weiter' -ForEach 'Prozesse', 'Laufwerke', 'Citrix', 'Ereignisse', 'Rueckblick', 'Drucken', 'Gegenstellen' {
        $cat = $_; $r = Invoke-SimReads @($cat)
        foreach ($c in $ReadKeys.Keys) { foreach ($k in $ReadKeys[$c]) { if ($c -eq $cat) { [int]$r.Reads[$k] | Should -Be 0 -Because $k } else { [int]$r.Reads[$k] | Should -BeGreaterThan 0 -Because $k } } }
    }
    It 'liefert ohne alle Kategorien nur die Basis, mit denselben Werten' {   # Review Focus 1
        $full = Invoke-SimReads @(); $r = Invoke-SimReads @('Prozesse', 'Laufwerke', 'Citrix', 'Ereignisse', 'Rueckblick', 'Drucken', 'Gegenstellen')
        @($r.Reads.Values | Where-Object { $_ -gt 0 }).Count | Should -Be 0
        @($r.Snap.Processes).Count + @($r.Snap.Citrix).Count + $r.Services.Count | Should -Be 0; @($r.Snap.Sessions).Count | Should -Be 26
        @($r.Fast.Volumes).Count + @($r.Fast.Shares).Count + @($r.Fast.InputProcesses).Count | Should -Be 0; @($r.Fast.InputSessions).Count | Should -Be 25
        foreach ($c in 'CpuPct', 'MemAvailMB', 'DiskReadBps', 'DiskWriteBps', 'DiskReadIops', 'DiskQueue', 'NetRecvBps', 'NetSentBps') { $r.Fast.$c | Should -Be $full.Fast.$c -Because $c }
        @($r.Events).Count + @($r.Before.Events).Count + @($r.Drivers).Count + @($r.Queues).Count + @($r.Probes).Count | Should -Be 0
    }
}
```

`tests/WindowsSource.Tests.ps1` (im `Describe 'Windows-Datenquelle mit nachgestellten Windows-Aufrufen'`; `$Cfg` ist die Ereigniskonfiguration aus Task 10):

```powershell
It 'macht fuer <Skip> keinen Windows-Aufruf der Kategorie' -TestCases @(
    @{ Skip = 'Prozesse'; Action = { Get-WorkerPerfFastSample; Get-WorkerPerfSnapshot -Kind K; Get-WorkerPerfServices }; Absent = 'Win32_Process|Win32_Service|Input Delay per Process' }
    @{ Skip = 'Laufwerke'; Action = { Get-WorkerPerfFastSample; Get-WorkerPerfSnapshot -Kind K }; Absent = 'LogicalDisk|SMB Client Shares|MSFT_Disk|MSFT_Partition' }
    @{ Skip = 'Citrix'; Action = { Get-WorkerPerfSnapshot -Kind K }; Absent = 'ICA Session|Citrix_Euem' }
    @{ Skip = 'Ereignisse'; Action = { Get-WorkerPerfEvents -Since ([datetime]::Now.AddMinutes(-5)) }; Absent = '^winevent:read' }
    @{ Skip = 'Rueckblick'; Action = { Get-WorkerPerfEventsBefore -Days 7 -Until ([datetime]::Now) }; Absent = '^winevent:read' }
    @{ Skip = 'Drucken'; Action = { Get-WorkerPerfPrintDrivers; Get-WorkerPerfPrintQueues }; Absent = 'MSFT_PrinterDriver|Print Queue|^registry:print' }
) {
    $calls = { param([string[]]$s) Reset-WinStandIns; [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg -Skip $s 3>$null); [void](& $Action 3>$null); @($script:WinFake.Calls.Keys) }
    @(& $calls @() | Where-Object { $_ -match $Absent }).Count | Should -BeGreaterThan 0   # gemessen: die Aufrufe sind zu sehen
    @(& $calls @($Skip) | Where-Object { $_ -match $Absent }) | Should -BeNullOrEmpty
}
It 'laesst ohne alle Kategorien nur die Aufrufe der Basis uebrig und baut keine Verbindung auf' {   # Review Focus 1
    $ep = @([pscustomobject]@{ name = 'DB'; host = '127.0.0.1'; port = 1; role = 'Datenbank' })
    $info = Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg -Endpoints $ep -Skip Prozesse, Laufwerke, Citrix, Ereignisse, Rueckblick, Drucken, Gegenstellen 3>$null
    [void](Get-WorkerPerfFastSample); $snap = Get-WorkerPerfSnapshot -Kind K; $s = Get-WorkerPerfFastSample
    Start-WorkerPerfProbes -Endpoints $ep; $script:WinProbe | Should -BeNullOrEmpty; @($info.Endpoints).Count | Should -Be 0
    @($script:WinFake.Calls.Keys | Where-Object { $_ -match 'Win32_Process|Win32_Service|per Process|LogicalDisk|SMB Client|MSFT_|ICA Session|Citrix_Euem|Print Queue|^winevent|^registry:print' }) | Should -BeNullOrEmpty
    $s.CpuPct | Should -Be 27.5; @($s.InputSessions).Count | Should -Be 2; @($snap.Sessions).Count | Should -Be 2; @($snap.Processes).Count | Should -Be 0
    foreach ($id in 'process', 'disk.latency', 'ica.rtt', 'print.drivers', 'probe.connect', 'events.application') { $info.Sources.Contains($id) | Should -BeFalse -Because $id }
    $info.Sources['input.session'].Available | Should -BeTrue
}
```

Geänderte Aussagen: In `'meldet fehlende Kategorien, Klassen und Protokolle als nicht verfuegbar'` wird die letzte Zeile zu `(Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -Skip Citrix 3>$null).Sources.Contains('ica.rtt') | Should -BeFalse` (den Vermerk setzt jetzt der Collector für beide Quellen gleich; geprüft in Task 1). Der Platzhalter `Initialize-WorkerPerfSource` in `tests/Collector.Tests.ps1` (`'Zeitplan ueber das Ende der Sommerzeit'`) erhält `[string[]]$Skip = @()` statt `[switch]$NoCitrix` in der Parameterliste; seine Aussage bleibt.

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Simulation.Tests.ps1, tests/WindowsSource.Tests.ps1 -Output Minimal"`
Expected: FAIL, Parameter `Skip` nicht gefunden

- [ ] **Step 3: Platzhalter zählen lassen, dann beide Quellen und den Aufruf im Collector mit den Signaturen der Interfaces umstellen**

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`
Expected: `Failed: 0` (auch `tests/Skip.Tests.ps1` aus Task 1 unverändert grün)

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Sources.Simulation.ps1 src/WorkerPerf.Sources.Windows.ps1 src/Start-WorkerPerfCapture.ps1 tests/WindowsStandIns.ps1 tests/Simulation.Tests.ps1 tests/WindowsSource.Tests.ps1 tests/Collector.Tests.ps1
git commit -m "Make both data sources read nothing of a skipped category"
```

---

### Task 3: Laden und Berichtsdaten – weggelassene Kategorien, abhängige Stellen, Soll-Ist, Maskierung

**Files:**
- Modify: `src/WorkerPerf.Common.ps1`, `src/WorkerPerf.Load.ps1` (`Import-WorkerPerfRun`: nach dem Lesen von `meta.json`, Rückgabe), `src/New-WorkerPerfReport.ps1` (Zusammenbau von `$data`), `src/texts.de.json`, `src/WorkerPerf.Mask.ps1` (Liste der Schlüsselwortfelder, `Clear-WorkerPerfReportFreeText`), `tests/MaskCensus.json`, `tests/TestHelpers.ps1`
- Test: `tests/Load.Tests.ps1`, `tests/Skip.Tests.ps1`

**Interfaces:**
- Consumes: `meta.json` mit `Skip`, `Sources` mit dem Vermerk (Task 1).
- Produces:
  - `Get-WorkerPerfRecordedSkip($Value) -> string[]` (`WorkerPerf.Common.ps1`): die aktiven Kategorien aus dem Feld `Skip` einer `meta.json` in der Reihenfolge der Tabelle; `$null`, unbekannte und nicht aktive Werte entfallen ohne Fehler. `Import-WorkerPerfRun` liefert `Skip = [string[]]` im Modell; fehlt das Feld (Aufzeichnung von vor diesem Plan, Format 2), ist die Liste leer.
  - `Get-WorkerPerfSkippedOut([string[]]$Skip, [hashtable]$Texts)` (`WorkerPerf.Common.ps1`): je Kategorie `[ordered]@{ id; label; text; places }` mit `label` = `Texts['skip.label.<id>']`, `text` = `Texts['skip.text.<id>']`, `places` = `[string[]]` der Tabelle.
  - Berichtsdaten: neues Feld `skipped` als letztes Feld von `$data` (`@()` ohne weggelassene Kategorie). Die bestehenden Felder tragen den Rest ohne neue Schlüssel: Zeilen von `sollIst` einer weggelassenen Kategorie haben `measured = $false`, `status = 0`, `detail` = Vermerk der Quelle; `unmeasured.worker` nennt die Bezeichnungen wie bisher; `before.status` ist `off` (über `EventLookbackDays` 0); `quality.sources[].detail` trägt den Vermerk.
  - `texts.de.json`: `"skip.label.Prozesse": "Prozesse"`, `"skip.label.Laufwerke": "Laufwerke"`, `"skip.label.Citrix": "Citrix"`, `"skip.label.Ereignisse": "Ereignisse"`, `"skip.label.Rueckblick": "Rückblick"`, `"skip.label.Drucken": "Drucken"`, `"skip.label.Gegenstellen": "Gegenstellen"`; `"skip.text.Prozesse": "Prozesse wurden bei dieser Messung nicht erfasst."`, `"skip.text.Laufwerke": "Antwortzeiten je Laufwerk, Profilcontainer und Freigabe wurden bei dieser Messung nicht erfasst."`, `"skip.text.Citrix": "ICA-Werte je Sitzung wurden bei dieser Messung nicht erfasst."`, `"skip.text.Ereignisse": "Ereignisse während der Messung wurden nicht erfasst."`, `"skip.text.Rueckblick": "Ereignisse der Tage vor der Messung wurden nicht erfasst."`, `"skip.text.Drucken": "Treiberliste und Zähler der Druckwarteschlangen wurden bei dieser Messung nicht erfasst."`, `"skip.text.Gegenstellen": "Gegenstellen wurden bei dieser Messung nicht geprüft."`
  - Maskierung: `$script:WorkerPerfMaskKeywordFields` erhält `'skipped.places'` (und in Task 4 `'unchecked.category'`); `Clear-WorkerPerfReportFreeText` lässt bei den Feldern mit `?unavailable` ein `detail` stehen, das `$script:WorkerPerfSkipDetailPattern` entspricht (fester Text des Collectors, kein Text des Servers). `tests/MaskCensus.json` erhält `"skipped[].id": "keyword"`, `"skipped[].label": "composed"`, `"skipped[].text": "composed"`, `"skipped[].places[]": "keyword"`. Die Zensus-Prüfung in `tests/Mask.Tests.ps1` bleibt, wie sie ist (ohne `-Skip` sind die neuen Listen leer); das Verhalten der neuen Felder unter `-Mask` prüft der Test des maskierten Berichts unten.
  - `tests/TestHelpers.ps1`: `New-SkipReports([string]$OutDir) -> ordered`: ruft `New-SkipRuns (Join-Path $OutDir 'skip')`, schreibt je Schlüssel `report-skip-<schlüssel in Kleinbuchstaben>.html` nach `$OutDir` (Rollendatei `roles.sim.json` in `$OutDir` über `New-SimRoleFile`) und zusätzlich `report-skip-alle-masked.html` (`Alle` mit `-Mask Alles`); Wert je Schlüssel `@{ Run; Report }`, dazu der Schlüssel `AlleMasked`.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben**

`tests/Load.Tests.ps1`:

```powershell
It 'liest die weggelassenen Kategorien; ohne Angabe gilt alles als gemessen' {   # Review Focus 2
    $dir = Write-TestRun 'skip' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }; $meta = Join-Path $dir 'meta.json'
    @((Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles).Skip).Count | Should -Be 0
    [IO.File]::WriteAllText($meta, [IO.File]::ReadAllText($meta).Replace('"Simulated":false,', '"Simulated":false,"Skip":["rueckblick","Netz","Zustand","Prozesse"],'))
    (Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles).Skip | Should -Be @('Prozesse', 'Rueckblick')
}
```

`tests/Skip.Tests.ps1`: im `BeforeAll` ersetzt `$script:Rep = New-SkipReports (Join-Path $TestDrive 'rep')` den Aufruf von `New-SkipRuns`; `$Runs[<Schlüssel>]` = `$Rep[<Schlüssel>].Run`, `$script:D[<Schlüssel>]` = `Get-ReportData $Rep[<Schlüssel>].Report`, `$script:Report` = Pfad von `New-WorkerPerfReport.ps1`, `$script:Texts` = `Read-WorkerPerfTexts` von `src/texts.de.json`, dazu:

```powershell
    $script:Places = @{ Prozesse = @('procs', 'apps', 'sessions.resources', 'incidents.contributors', 'incidents.delayProcs', 'print.processes'); Laufwerke = @('volumes', 'shares', 'sessions.profile')
        Citrix = @('citrix', 'sessions.rtt', 'incidents.ica'); Ereignisse = @('events', 'sessions.events', 'incidents.events'); Rueckblick = @('before'); Drucken = @('print.drivers', 'print.queues')
        Gegenstellen = @('probes', 'incidents.endpoints') }
```

```powershell
Describe 'Berichtsdaten mit weggelassenen Kategorien' {
    It 'nennt fuer <_> Kategorie, Grund und abhaengige Stellen' -ForEach 'Prozesse', 'Laufwerke', 'Citrix', 'Ereignisse', 'Rueckblick', 'Drucken', 'Gegenstellen' {
        $s = @($D[$_].skipped); $s.Count | Should -Be 1
        $s[0].id | Should -Be $_; $s[0].label | Should -Be $Texts["skip.label.$_"]; $s[0].text | Should -Be $Texts["skip.text.$_"]; @($s[0].places) | Should -Be $Places[$_]
    }
    It 'zaehlt kein Signal einer weggelassenen Kategorie im Soll-Ist' {
        $d = $D.Alle; @($d.skipped.id) | Should -Be $Names; $d.skipped[0].text | Should -Be 'Prozesse wurden bei dieser Messung nicht erfasst.'
        foreach ($id in 'disk.latency', 'smb.latency', 'ica.rtt', 'ica.latency', 'probe.connect') {
            $r = $d.sollIst | Where-Object id -eq $id; $r.measured | Should -BeFalse -Because $id; $r.status | Should -Be 0; $r.exceeded | Should -BeFalse
        }
        ($d.sollIst | Where-Object id -eq 'smb.latency').detail | Should -Be 'abgeschaltet (-Skip Laufwerke)'
        @($d.sollIst | Where-Object measured).id | Should -Be @('cpu.host', 'cpu.queue', 'cpu.steal', 'mem.used', 'mem.commit', 'mem.pagesin', 'input.session')
        $d.unmeasured.worker | Should -Be @('Datenträger-Antwortzeit', 'Freigabe-Antwortzeit (SMB)'); $d.before.status | Should -Be 'off'; $D.Rueckblick.before.status | Should -Be 'off'
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
        @($D.Voll.skipped).Count | Should -Be 0; @($D.Voll.PSObject.Properties.Name)[-1] | Should -Be 'skipped'   # das neue Feld der Berichtsdaten, leer
    }
    It 'behaelt Kategorien und Gruende im maskierten Bericht' {
        $m = Get-ReportData $Rep.AlleMasked.Report
        @($m.skipped.id) | Should -Be $Names; $m.skipped[0].text | Should -Be 'Prozesse wurden bei dieser Messung nicht erfasst.'; @($m.skipped[0].places) | Should -Be $Places.Prozesse
        ($m.sollIst | Where-Object id -eq 'ica.rtt').detail | Should -Be 'abgeschaltet (-Skip Citrix)'; ($m.quality.sources | Where-Object id -eq 'process').detail | Should -Be 'abgeschaltet (-Skip Prozesse)'
        [IO.File]::ReadAllText($Rep.AlleMasked.Report) | Should -Not -Match 'user0\d\d|SIM-VDA01|CONTOSO'
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Load.Tests.ps1, tests/Skip.Tests.ps1 -Output Minimal"`
Expected: FAIL, `New-SkipReports` nicht definiert; kein Feld `skipped`

- [ ] **Step 3: `Get-WorkerPerfRecordedSkip`, `Model.Skip`, `Get-WorkerPerfSkippedOut`, das Feld `skipped`, die Texte und `New-SkipReports` mit den Signaturen der Interfaces umsetzen**

- [ ] **Step 4: Maskierungslisten nachziehen** – `'skipped.places'` in `$script:WorkerPerfMaskKeywordFields`, die Ausnahme in `Clear-WorkerPerfReportFreeText`, die vier Pfade in `tests/MaskCensus.json`.

- [ ] **Step 5: Tests ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`
Expected: `Failed: 0`

- [ ] **Step 6: Commit**

```bash
git add src/WorkerPerf.Common.ps1 src/WorkerPerf.Load.ps1 src/New-WorkerPerfReport.ps1 src/texts.de.json src/WorkerPerf.Mask.ps1 tests/MaskCensus.json tests/TestHelpers.ps1 tests/Load.Tests.ps1 tests/Skip.Tests.ps1
git commit -m "Carry skipped categories, their reason and dependent places into the report data"
```

---

### Task 4: Vorfallserklärungen und Muster der Ereignisvorfälle

**Files:**
- Modify: `src/WorkerPerf.Findings.ps1` (`Add-WorkerPerfIncidentDetail`: Ursache; `Get-WorkerPerfIncidentText`), `src/WorkerPerf.Events.ps1` (`Add-WorkerPerfEventPatterns`, `Get-WorkerPerfEventIncidentText`, `ConvertTo-WorkerPerfEventIncidentOut`, `Get-WorkerPerfLookback`), `src/New-WorkerPerfReport.ps1` (Aufruf von `Add-WorkerPerfEventPatterns`), `src/texts.de.json`, `src/WorkerPerf.Mask.ps1`, `tests/MaskCensus.json`
- Test: `tests/Skip.Tests.ps1`

**Interfaces:**
- Consumes: `Model.Skip`, `Texts['skip.text.<id>']` (Task 3). Ein Modell ohne `Skip` (bestehende Tests) gilt als vollständig gemessen (`Get-WorkerPerfField $Model 'Skip'`).
- Produces:
  - `Cause.Kind = 'notmeasured'` (Berichtsdaten `cause.kind`) für jeden `engpass`, wenn `Prozesse` weggelassen ist; `nodata` bleibt der Fall „gemessen, aber im Fenster keine Prozessdaten". Text: `Texts['main.notmeasured'] -f Texts['skip.text.Prozesse']`.
  - `ohne-engpass`: ohne `Prozesse` steht an der Stelle von `ohne.process` `Texts['ohne.process.notmeasured'] -f Texts['skip.text.Prozesse']`; ohne `Gegenstellen` folgt auf den Satz zur Ursache (`ohne.cause` bzw. `ohne.unmeasured`) ein Leerzeichen und `Texts['skip.text.Gegenstellen']`. Ohne `Laufwerke` sagt der bestehende Satz `ohne.unmeasured`, was fehlt (unverändert).
  - `Add-WorkerPerfEventPatterns … -Skip [string[]] = @()` setzt je Vorfall `Unchecked` = Liste von `@{ Id; Category }` in dieser Reihenfolge: `printdriver`/`Drucken`, wenn `Drucken` weggelassen ist und der Vorfall ein echtes Modul nennt (`Test-WorkerPerfRealModule`); `users`/`Prozesse`, wenn `Prozesse` weggelassen ist, der Vorfall nicht aus dem Rückblick stammt und einer seiner Datensätze der Art `crash` oder `hang` keine Sitzungsnummer hat (`[int]SessionId -lt 0`) und `Get-WorkerPerfEventAffectedUser` leer liefert. Mit `users` werden `manyusers` und `oneuser` für den Vorfall nicht gebildet. `Get-WorkerPerfLookback` übergibt `Model.Skip`, das Berichtsskript `$model.Skip`.
  - `Get-WorkerPerfEventIncidentText`: mit `users` in `Unchecked` entfällt `event.nouser`; nach den Aussagen der Muster folgt bei nicht leerem `Unchecked` `Texts['pattern.unchecked'] -f (<Texte 'pattern.unchecked.<id>' mit ', ' verbunden>)`; `pattern.none` steht nur, wenn `Patterns` und `Unchecked` beide leer sind.
  - Berichtsdaten: `event.unchecked` nach `event.patterns`, Liste von `[ordered]@{ id; category; text }` (`text` = `Texts['pattern.unchecked.<id>']`), `@()` ohne nicht geprüftes Muster.
  - `texts.de.json`: `"main.notmeasured": " Kein Hauptverursacher ermittelt: {0}"`, `"ohne.process.notmeasured": " Prozess mit der höchsten Verzögerung nicht ermittelt: {0}"`, `"pattern.unchecked": " Nicht geprüft: {0}."`, `"pattern.unchecked.printdriver": "Bezug zu einem Druckertreiber (Drucken nicht gemessen)"`, `"pattern.unchecked.users": "Zuordnung zu Benutzern und Sitzungen (Prozesse nicht gemessen)"`.
  - Maskierung: `'unchecked.category'` in `$script:WorkerPerfMaskKeywordFields`; `tests/MaskCensus.json` erhält für `incidents[].event.unchecked[]` und `before.incidents[].event.unchecked[]` je `.id` und `.category` als `keyword` und `.text` als `composed`.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/Skip.Tests.ps1`)

```powershell
Describe 'Vorfallserklaerungen und Muster mit weggelassenen Kategorien' {   # Review Focus 3
    BeforeAll { function Get-Ev($d, [scriptblock]$Where) { @($d.incidents | Where-Object { $_.type -eq 'ereignis' } | Where-Object $Where) } }
    It 'nennt beim Verursacher den Grund statt fehlender Prozessdaten' {
        $d = $D.Prozesse; $cpu = $d.incidents | Where-Object lead -eq 'cpu'
        $cpu.cause.kind | Should -Be 'notmeasured'; $cpu.main | Should -BeNullOrEmpty
        $cpu.text | Should -BeLike '*Betroffen: 6 Sitzungen. Kein Hauptverursacher ermittelt: Prozesse wurden bei dieser Messung nicht erfasst.'
        $back = $d.incidents | Where-Object { $_.type -eq 'ohne-engpass' -and @($_.affected).Count -eq 8 }
        $back.text | Should -BeLike '*Betroffen: 8 Sitzungen. Prozess mit der höchsten Verzögerung nicht ermittelt: Prozesse wurden bei dieser Messung nicht erfasst. Die Ursache liegt*Gegenstelle Oracle-Listener: *'
        @($d.incidents | Where-Object { $_.text -match 'keine Prozessdaten' }).Count | Should -Be 0
        ($D.Voll.incidents | Where-Object lead -eq 'cpu').cause.kind | Should -Be 'main'
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
        $o.text | Should -BeLike '*Nicht geprüft: Zuordnung zu Benutzern und Sitzungen (Prozesse nicht gemessen).'; $o.text | Should -Not -Match 'Ohne Benutzersitzung|Kein Muster erkannt'
        $pr = (Get-Ev $D.Prozesse { $_.event.kind -eq 'profileerror' })[0]   # nennt seinen Benutzer selbst
        @($pr.event.unchecked).Count | Should -Be 0; $pr.text | Should -Match 'Benutzer: user014\. Kein Muster erkannt\.'
        @(@($D.Prozesse.before.incidents) | Where-Object { @($_.event.patterns.id) -contains 'oneuser' }).Count | Should -Be 1   # der Rueckblick nennt Benutzer selbst
    }
    It 'behaelt ein nicht geprueftes Muster im maskierten Bericht' {
        $out = Join-Path $TestDrive 'dm.html'; [void](& $Report -Path $Runs.Drucken -OutFile $out -RoleFile (Join-Path $TestDrive 'rep/roles.sim.json') -Mask Alles 6>$null)
        $u = (Get-Ev (Get-ReportData $out) { $_.event.kind -eq 'print' })[0].event.unchecked
        '{0}|{1}|{2}' -f $u[0].id, $u[0].category, $u[0].text | Should -Be 'printdriver|Drucken|Bezug zu einem Druckertreiber (Drucken nicht gemessen)'
    }
    It 'laesst ohne -Skip nichts ungeprueft und haelt Ereignisse und Rueckblick getrennt' {
        @(Get-Ev $D.Voll { @($_.event.unchecked).Count -gt 0 }).Count | Should -Be 0; @(Get-Ev $D.Voll { $true }).Count | Should -Be 4
        @(Get-Ev $D.Ereignisse { $true }).Count | Should -Be 0; @($D.Ereignisse.before.incidents).Count | Should -Be 3
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Skip.Tests.ps1 -Output Minimal"`
Expected: FAIL, `cause.kind` ist `nodata`; kein Feld `unchecked`

- [ ] **Step 3: Ursache, Texte, `Unchecked` und die Ausgabe mit den Signaturen der Interfaces umsetzen; `'unchecked.category'` und die sechs Pfade in Maskierungsliste und Zensus eintragen**

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`
Expected: `Failed: 0` (der Vergleich mit der Aufzeichnung von vor diesem Plan aus Task 3 bleibt grün: `unchecked` ist dort überall leer)

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Findings.ps1 src/WorkerPerf.Events.ps1 src/New-WorkerPerfReport.ps1 src/texts.de.json src/WorkerPerf.Mask.ps1 tests/MaskCensus.json tests/Skip.Tests.ps1
git commit -m "Name the reason where a skipped category would explain an incident"
```

---

### Task 5: Seite und README

**Files:**
- Modify: `src/report-template.html`, `tests/New-TestReports.ps1` (ruft zusätzlich `New-SkipReports $OutDir`), `tests/report-browser.js`, `README.md`

**Interfaces:**
- Consumes: `skipped`, `cause.kind = 'notmeasured'`, `event.unchecked`, `before.status` (Tasks 3 und 4); die Berichte `report-skip-*.html`.
- Produces (heutige Seite; der geführte Bericht übernimmt die Regeln):
  - `#skipInfo` (Klasse `sub`) direkt nach `#subtitle`, vor `#maskInfo`, nur bei nicht leerem `skipped`: Symbol `○` (`aria-hidden`) und Text `Nicht gemessen (-Skip): <label, label …>`.
  - Ein Helfer der Seite liefert zu einer Stelle den Hinweis oder nichts: ein Element mit Klasse `notmeasured` und `data-place="<Stelle>"`, Inhalt Statuskennzeichen `○ nicht gemessen` und dahinter `– <text> (-Skip <id>)`. Wo der Hinweis steht, entfallen die leere Tabelle, das leere Diagramm und Sätze wie „keine", „Keine … gemessen", „Keine … aufgezeichnet":

| Stelle | Ort auf der Seite |
|---|---|
| `procs` | Reiter Prozesse (statt `#tProcs` und `#procNote`); gestapelte Diagramme `#chCpuStack`, `#chMemStack`; im Fuß die Prozesszahlen und der Anteil von WorkerPerf |
| `apps` | Reiter Anwendungen (statt `#tApps`); Karte `#cardMainApp` |
| `sessions.resources` | Sitzungstabelle: Spalten für CPU, Arbeitsspeicher, I/O und Prozesse zeigen „–", Hinweis über der Tabelle; Sitzungsansicht: Diagramme CPU und Arbeitsspeicher, Tabellen der Anwendungen und Prozesse |
| `incidents.contributors` | Vorfall: Tabellen „Verursacher" und Liste „Schutzprodukte" |
| `incidents.delayProcs` | Vorfall: „Höchste Eingabeverzögerung je Prozess" |
| `print.processes`, `print.drivers`, `print.queues` | Karte `#print` (erscheint auch, wenn nur ein Hinweis darin steht) |
| `volumes`, `shares`, `probes` | Diagramme `#chVolumes`, `#chShares`, `#chProbes` |
| `sessions.profile`, `sessions.rtt`, `citrix`, `sessions.events` | Sitzungsansicht: Antwortzeit des Profilcontainers, ICA Round Trip, Tabelle „Citrix-Messwerte", „Sitzungsereignisse" |
| `incidents.ica`, `incidents.endpoints`, `incidents.events` | Vorfall: „ICA Round Trip", „Gegenstellen", „Ereignisse im Fenster" |
| `events` | Zeitleiste: statt der Ereigniszeilen eine Zeile mit dem Hinweis |
| `before` | Karte `#before`; der Satz für `off` lautet neu „Der Rückblick war abgeschaltet (-Skip Rueckblick oder -EventLookbackDays 0)." |

  - Ursache: bei `cause.kind === "notmeasured"` zeigt `.causebox` „Kein Hauptverursacher ermittelt: " und den Text der Kategorie `Prozesse`. Muster eines Ereignisvorfalls: je Eintrag von `event.unchecked` ein Listenpunkt „nicht geprüft: <text>"; „Kein Muster erkannt" nur, wenn `patterns` und `unchecked` leer sind.
  - Soll-Ist-Tabelle, Kacheln, Hinweis ohne Befund und Quellentabelle zeigen den Vermerk aus `detail` wie bisher.

- [ ] **Step 1: Die fehlschlagenden Prüfungen schreiben** (neue Funktion, in der Schleife je Farbschema aufrufen)

```js
async function checkSkip(browser, dir, scheme) {   // Messkategorien
  const full = await open(browser, path.join(dir, 'report.html'), scheme);
  ok(await full.page.locator('#skipInfo').count() === 0 && await full.page.locator('.notmeasured').count() === 0, 'ohne -Skip kein Hinweis und keine Stelle "nicht gemessen"');
  await full.page.close();
  for (const n of ['prozesse', 'laufwerke', 'citrix', 'ereignisse', 'rueckblick', 'drucken', 'gegenstellen', 'alle', 'alle-masked']) {   // Review Focus 1
    const { page, D } = await open(browser, path.join(dir, `report-skip-${n}.html`), scheme);
    for (const t of ['overview', 'apps', 'procs', 'sessions']) await page.click(`nav button[data-tab=${t}]`);
    await page.click('#tSessions tbody tr >> nth=0'); await page.click('nav button[data-tab=findings]');
    for (const i of D.incidents) await openIncident(page, i.id);
    const info = await page.locator('header #skipInfo').innerText();
    ok(info.includes('Nicht gemessen (-Skip): ' + D.skipped.map((s) => s.label).join(', ')), n + ': Kopf nennt die Kategorien: ' + info);
    const all = await page.evaluate(() => { const b = document.body.cloneNode(true); b.querySelectorAll('script').forEach((x) => x.remove()); return b.textContent; });
    for (const s of D.skipped) {
      ok(all.includes(s.text + ' (-Skip ' + s.id + ')'), n + ': Grund von ' + s.id + ' steht auf der Seite');
      for (const p of s.places) ok(await page.locator(`.notmeasured[data-place="${p}"]`).count() > 0, n + ': Stelle ' + p + ' sagt "nicht gemessen"');
    }
    ok(page.errors.length === 0, n + ': Skriptfehler: ' + page.errors.join(' | '));
    await page.close();
  }
  const p = await open(browser, path.join(dir, 'report-skip-prozesse.html'), scheme);
  const cpu = p.D.incidents.find((i) => i.lead === 'cpu'), sentence = 'Kein Hauptverursacher ermittelt: Prozesse wurden bei dieser Messung nicht erfasst.';
  let entry = await openIncident(p.page, cpu.id);
  ok((await entry.locator('.causebox').innerText()).includes(sentence) && cpu.text.includes(sentence), 'Verursacher: Text und Seite gleich');   // Review Focus 3
  ok(!(await entry.locator('.detail').innerText()).match(/keine Prozessdaten|keine Prozesse mit der Rolle Sicherheit/), 'kein "keine" fuer nicht Gemessenes');
  await p.page.close();
  const d = await open(browser, path.join(dir, 'report-skip-drucken.html'), scheme);
  entry = await openIncident(d.page, d.D.incidents.find((i) => i.type === 'ereignis' && i.event.kind === 'print').id);
  const pat = await entry.locator('.patterns').innerText();
  ok(pat.includes('nicht geprüft: Bezug zu einem Druckertreiber (Drucken nicht gemessen)') && !pat.includes('Kein Muster erkannt'), 'Muster nicht geprueft statt "kein Muster"');
  ok(!(await d.page.locator('#print').innerText()).includes('Keine Treiberliste aufgezeichnet'), 'Drucken: nicht "keine Treiberliste"');
  await d.page.close();
  const r = await open(browser, path.join(dir, 'report-skip-rueckblick.html'), scheme);
  ok((await r.page.locator('#before').innerText()).includes('Der Rückblick war abgeschaltet (-Skip Rueckblick oder -EventLookbackDays 0).'), 'Rueckblick abgeschaltet');
  await r.page.close();
}
```

Geänderte Aussage: in `checkFix1` erwartet der Fall `off` den neuen Satz `Der Rückblick war abgeschaltet (-Skip Rueckblick oder -EventLookbackDays 0).` (beide Schreibweisen bedeuten dasselbe).

- [ ] **Step 2: Prüfung ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/New-TestReports.ps1 -OutDir <workspace>/scratch/wp-reports && node tests/report-browser.js <workspace>/scratch/wp-reports`
Expected: `AssertionError`, kein Element `#skipInfo`

- [ ] **Step 3: Hinweis im Kopf, den Helfer und die Stellen der Tabelle in der Vorlage bauen**

- [ ] **Step 4: Prüfungen ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"` und die Browserprüfungen
Expected: `Failed: 0` und `browser checks passed: <n>`

- [ ] **Step 5: README** – „1. Aufzeichnen": `-Skip` in der Parametertabelle, der Aufruf `.\Start-WorkerPerfCapture.ps1 -DurationMinutes 10 -Skip Prozesse,Rueckblick`, die Tabelle aus Abschnitt 3 der Spezifikation und ihre Regeln (Basis nicht abschaltbar; `-NoCitrix` = `-Skip Citrix`, `-EventLookbackDays 0` = `-Skip Rueckblick`, weggelassen gewinnt; Schreibweise egal; unbekannter Wert bricht ab; `Zustand` wird angenommen und wirkt erst mit dem Zustandsbild; Meldung beim Start). „Was bei welcher Stufe zu tun ist": statt der Zeile `-NoCitrix` eine Zeile je Kategorie, dazu Abschnitt 8 der Spezifikation (`Prozesse` spart am meisten und macht Vorfälle unerklärbar: nur weglassen, wenn die Messung selbst spürbar stört; die Kosten auf einem Server zeigt die Messdauer je Takt und je Schnappschuss unter „Messqualität"). „Der Bericht": Kopf, „nicht gemessen" mit Grund an den abhängigen Stellen, Soll-Ist. „Datenformat": `Skip` in `meta.json`, fehlende Dateien, Format bleibt 3. „Datenquellen": Vermerk `abgeschaltet (-Skip <Wert>)`.

- [ ] **Step 6: Commit**

```bash
git add src/report-template.html tests/New-TestReports.ps1 tests/report-browser.js README.md
git commit -m "Show skipped categories as not measured in the report and document -Skip"
```

---

## Folgen für den Plan Geführter Bericht

`docs/superpowers/plans/2026-11-11-gefuehrter-bericht.md` wird nach diesem Plan ausgeführt und braucht an diesen Zeilen eine Ergänzung (dieser Plan ändert ihn nicht):

- **Zeile 11** (Voraussetzungen): dieser Plan mit `skipped[] { id, label, text, places }`, `cause.kind = notmeasured`, `event.unchecked[] { id, category, text }`.
- **Zeile 69** (`hints`) und **Zeile 283** (`Get-WorkerPerfLagebild`, `hints`): ein Hinweis `skipped` mit den `label` aus `skipped`, neben `unmeasured`.
- **Zeile 81** und **Zeilen 105–107** (bekannte Bedingungen und ihr Test): `cause.notmeasured`, `skipped.<Kategorie>` mit einem Namen aus `$script:WorkerPerfCategories`, `pattern.unchecked`.
- **Zeile 144** (Consumes: `Data.skipped`), **Zeile 147** (Ableitung: `cause.notmeasured` aus `cause.kind`; `pattern.none` nur, wenn `event.patterns` und `event.unchecked` leer sind; `pattern.unchecked`; `skipped.<id>`), **Zeile 150** (`New-Inc`, `New-Ctx`: `event.unchecked = @()`, `skipped = @()`).
- **Zeile 347** (`New-WorkerPerfCopyText`, Teil `copy.cause`): bei `cause.kind = notmeasured` der Satz der Kategorie, bei Ereignisvorfällen die Texte aus `event.unchecked` als „nicht geprüft".
- **Zeile 407** (Inhalt des Katalogs): Varianten für `cause.notmeasured`, `skipped.*` und `pattern.unchecked` mit der Formulierung „nicht gemessen".
- **Zeile 561** (Kopfleiste): `#skipInfo` neben `#maskInfo`.
- **Zeile 570** (`details#measured`): die weggelassenen Kategorien mit ihrem `text`; **Zeile 573** (Vorfallsansicht, `.iv-cause` und `.iv-evidence`) und **Zeile 575** (Tabellenbereich der Expertenansicht): der Hinweis je Stelle aus `skipped[].places` nach der Tabelle in Task 5.
- **Zeile 589** (Umstellung der Browserprüfungen): `checkSkip` ruft `showExpert` wie die übrigen Prüfungen.

## Self-Review

- **Spec coverage:** Abschnitt 2 → Architecture (Auswahl nur am Collector); 3 → Task 1 (Parameter, Werte, alte Schalter, `Zustand`, Startmeldung), Kategorienmodell (Basis); 4 → Task 1 (`meta.json`, Vermerk in den Quellen, Dateien, Format 3, Schutzgrenzen unberührt), Task 2 (keine Abfragen); 5 → Task 3 (Kopf- und Abschnittsdaten, Soll-Ist), Task 4 (Vorfälle, Muster), Task 5 (Seite), „Folgen" (geführter Bericht); 6 → Task 1 (unabhängige Kategorien, keine Kombination abgelehnt), Task 4 (Zuordnung ohne `Prozesse`, Treiberbezug ohne `Drucken`), Task 2 (Sitzungsliste bleibt); 7 → Tests der Tasks 1–5 in der Reihenfolge der Liste, Maskierung in Tasks 3 und 4; 8 → Task 5 (README); 9 → offen, keine Task.
- **Step scan:** jeder Code-Schritt nennt Datei und Signatur; Funktionskörper stehen nicht im Plan; die Werte der Kategorientabelle, die Vermerke, die Meldungen und die Texte stehen wörtlich da.
- **Type consistency:** die Liste der Kategorien heißt überall `Skip` (`$skip` im Collector, `-Skip` an Quellen und Funktionen, `Skip` in `meta.json`, `Model.Skip`), in den Berichtsdaten `skipped`; `Places` (Tabelle) ↔ `places` (Daten) ↔ `data-place` (Seite); `Unchecked` (Vorfall) ↔ `event.unchecked` (Daten); `cause.kind` kennt `main`, `security`, `none`, `nodata`, `notmeasured`.
- **Review Focus:** fünf Zeilen, jede mit Test in den genannten Tasks; die Gleichheit ohne `-Skip` prüfen Task 1 (Aufzeichnung) und Task 3 (Bericht).
- **Proportion:** die Codeblöcke sind Tests; die Spezifikation hat 92 Zeilen, der Plan trägt Tabelle, Signaturen, Texte und Tests.
