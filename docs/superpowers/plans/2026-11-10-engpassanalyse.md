# Engpassanalyse nach Störungsmeldung – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** WorkerPerf misst auf einem ausgewählten Citrix-Worker in zwei Takten und liefert einen Bericht, der Engpässe selbst erkennt, Betroffene und Verursacher nennt und jeden Messwert gegen einen Soll-Bereich bewertet.

**Architecture:** Der Collector wird ein dünner Einstieg mit Messschleife, die eine austauschbare Datenquelle (Simulation oder Windows) über feste Funktionsnamen anspricht; alle Entscheidungen (Aktiv-Filter, Verdichtung, Zeitplan, Schutzgrenzen) sind reine Funktionen in `WorkerPerf.Capture.ps1`. Die Auswertung liest den Aufzeichnungsordner in ein Datenmodell (`WorkerPerf.Load.ps1`), bildet daraus Befunde und Vorfälle (`WorkerPerf.Findings.ps1`) und bettet das Ergebnis als JSON in die HTML-Vorlage ein. Alles, was nur unter Windows läuft, steht in einer einzigen Datei und wird zuletzt gebaut, nachdem das Prüfskript auf einem echten VDA gelaufen ist.

**Tech Stack:** PowerShell (Laufzeit: Windows PowerShell 5.1), C# 5 über `Add-Type`, HTML/CSS/JavaScript ohne Bibliotheken. Tests: PowerShell 7.4, Pester 5.7.1, Node.js mit Playwright.

**Spec:** `docs/superpowers/specs/2026-11-10-engpassanalyse-design.md` – Abschnitt 14 enthält die Nachträge aus dieser Planung und geht den Abschnitten davor im Zweifel vor.

## Global Constraints

- **Laufzeit:** Alles unter `src/` läuft unter Windows PowerShell 5.1 auf Windows Server 2022, ohne Installation und ohne zusätzliche Module. Erlaubt sind .NET Framework, CIM, eingebaute Cmdlets und C# über `Add-Type`.
- **5.1-Syntax:** Jede `src/*.ps1` beginnt mit `#Requires -Version 5.1`. Verboten sind `? :`, `??`, `??=`, `?.`, `?[`, `&&`, `||`, `ForEach-Object -Parallel`, `ConvertFrom-Json -AsHashtable`/`-Depth`, `Get-Content -AsByteStream`, `Join-String`, `Test-Json`, `Get-Error`. `$IsWindows` nur in der Form `($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows`. `tests/Compat.Tests.ps1` erzwingt das.
- **Nur ASCII in `src/*.ps1`.** Deutsche Texte mit Umlauten stehen in `texts.de.json`, `thresholds.json`, `roles.json` und `report-template.html` und werden ausdrücklich als UTF-8 gelesen. Konsolenmeldungen der Skripte verwenden die Umschrift ae/oe/ue/ss.
- **C# 5:** keine String-Interpolation, kein `?.`, kein `nameof`, keine `out var`, keine Ausdruckskörper-Member, kein `async`/`await`.
- **Sprachneutral:** kein `Get-Counter`, keine lokalisierten Zählerpfade, keine Auswertung lokalisierter Programmausgaben.
- **Strenger Modus:** Einstiegsskripte setzen `Set-StrictMode -Version 2` und `$ErrorActionPreference = 'Stop'`. Die Dateien `WorkerPerf.*.ps1` definieren beim Einbinden nur Funktionen und Konstanten und führen nichts aus.
- **Datensätze und Listen:** Datensätze sind Hashtables (aus JSON gelesene Einträge `pscustomobject`). Listen in Rückgabewerten und im Datenmodell sind immer Arrays oder Listen, auch leer oder mit einem Element. Im strengen Modus schlagen `.Count` auf `$null` und der Punkt-Zugriff auf einen fehlenden Schlüssel fehl; deshalb jedes Feld eines Datensatzes immer anlegen.
- **Dateien:** UTF-8 ohne BOM. Zahlen immer mit invarianter Kultur (Dezimalpunkt). Dateinamen und Kopfzeilen des Aufzeichnungsformats ausschließlich aus `$script:WorkerPerfHeaders`.
- **Sprache:** Benutzertexte, Bericht und README deutsch; Bezeichner, Kommentare und Commit-Nachrichten englisch.
- **Feste Werte:** schneller Takt 2 s, langsamer Takt 15 s, Verdichtung alle 5 s, Nachlauf 60 s, höchstens 300 s je Auslöser-Signal, Stützpunkt bei jedem 20. regulären Schnappschuss, Aktiv-Schwelle 1 MB Working Set, `-MaxSizeMB` 500, Speicherplatz: Warnung unter 1 GB, Abbruch unter 200 MB, Eingabeverzögerung je Prozess ab 50 ms, Lücken und Zusammenfassen 10 s, Dauerzustand über 15 min, `minTicks` 1 (Eingabeverzögerung) bzw. 3, `minOps` 5, Proben-Zeitlimit 2 s, Fokus-Umkreis 15 min, je Rangliste fünf Beitragende.
- **Bericht:** eine HTML-Datei ohne externe Ressourcen, helles und dunkles Schema. Status nie nur über Farbe, sondern mit Symbol und Wort: `● normal`, `▲ auffällig`, `◆ kritisch`, `○ nicht gemessen`.
- **Datenschutz:** Aufzeichnungen und Berichte werden nicht eingecheckt. Das Prüfskript gibt keine Benutzer-, Client- oder Servernamen aus.
- **Tests:** `bash tests/Install-TestTools.sh` richtet eine frische Linux-Sitzung ein. Alle Tests: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`, erwartete Schlusszeile `Tests Passed: <n>, Failed: 0`. Durchlauf-Tests laufen unter der Kultur `de-DE`. Testdateien dürfen PowerShell-7-Syntax und Umlaute verwenden.
- **Commits:** ein Commit je Task, erst nach grünem Testlauf.

## Review Focus

Eingaben, die die Spezifikation nicht ausdrücklich behandelt, aber beim Einsatz zu erwarten sind. Jede Zeile ist durch einen Test in der genannten Task abgesichert (im Testcode mit `# Review Focus n` markiert).

1. **Ein Signal liegt die ganze Messung über der Schwelle** (z. B. RAM-Auslastung 80 %). Erwartet: Die übrigen Vorfälle bleiben einzeln sichtbar, und die Verdichtung läuft nicht stundenlang. → Task 4, Task 6
2. **Collector und Auswertung laufen auf einem deutschen Windows.** Erwartet: Dateien mit Dezimalpunkt, Bericht mit richtigen Werten; Umlaute und Kommas in Namen bleiben erhalten. → Tasks 2, 6, 8, 9, 12
3. **Die Aufzeichnung wurde hart abgebrochen** (abgeschnittene letzte Zeile, `EndTime` leer, Prozesszeilen ohne zugehörigen Schnappschuss). Erwartet: Der Bericht entsteht aus dem vollständigen Teil. → Tasks 9, 10
4. **Sitzungs-IDs und PIDs werden innerhalb einer Messung neu vergeben.** Erwartet: Verbrauch und Verzögerung landen beim richtigen Benutzer und Prozess. → Tasks 5, 9, 10
5. **Ein nahezu ruhendes Laufwerk liefert einzelne langsame Zugriffe.** Erwartet: kein Datenträger-Befund. → Task 3

## File Structure

| Datei | Verantwortung |
|---|---|
| `src/Test-WorkerPerfSources.ps1` (neu) | Eigenständiges Prüfskript: welche Datenquellen gibt es auf einem Worker |
| `src/WorkerPerf.Common.ps1` (neu) | Formatkonstanten, CSV-Helfer, Leser und Prüfung der JSON-Dateien, Statusbewertung, Host-Signale, Rollen |
| `src/thresholds.json`, `roles.json`, `endpoints.example.json`, `texts.de.json` (neu) | Schwellwerte, Rollen, Beispiel-Gegenstellen, Textbausteine |
| `src/WorkerPerf.Capture.ps1` (neu) | Reine Collector-Logik: Prozesszeilen, Verdichtung, Zeitplan, Schutzgrenzen, Zeilenformat, Writer |
| `src/WorkerPerf.Sources.Simulation.ps1` (neu) | Datenquelle Simulation mit Drehbuch und Soll-Ergebnis |
| `src/WorkerPerf.Sources.Windows.ps1` (neu) | Datenquelle Windows (einzige Datei mit Windows-Aufrufen) |
| `src/Start-WorkerPerfCapture.ps1` (neu geschrieben) | Einstieg und Messschleife |
| `src/WorkerPerf.Load.ps1` (neu) | Aufzeichnungsordner → Datenmodell, Messreihen für die Befund-Logik |
| `src/WorkerPerf.Findings.ps1` (neu) | Befunde, Soll-Ist, Vorfälle, Vorfallsdetails, Klartext |
| `src/New-WorkerPerfReport.ps1` (neu geschrieben) | Einstieg der Auswertung, Kennzahlen, JSON |
| `src/report-template.html` (neu geschrieben) | Berichtsseite |
| `tests/*.Tests.ps1`, `tests/TestHelpers.ps1`, `tests/report-browser.js` | Tests |
| `tests/Install-TestTools.sh`, `tests/Invoke-Tests.ps1`, `tests/New-TestReports.ps1` | Testwerkzeuge |
| `docs/vda-probe/README.md` | Anleitung für den Lauf des Prüfskripts |

Die Tasks 1–14 brauchen kein Windows. Task 15 setzt das Ergebnis des Prüfskripts von einem echten VDA voraus und kann vorgezogen werden, sobald dieses vorliegt und Task 8 abgeschlossen ist.

---

### Task 1: Testwerkzeuge und Quellen-Prüfskript

**Files:**
- Create: `tests/Install-TestTools.sh`, `tests/Invoke-Tests.ps1`, `tests/Compat.Tests.ps1`, `tests/Sources.Tests.ps1`
- Create: `src/Test-WorkerPerfSources.ps1`, `docs/vda-probe/README.md`

**Interfaces:**
- Produces: `Test-WorkerPerfSources.ps1 [-OutFile <Ordner oder Datei>] [-EndpointFile <Pfad>] [-InputSeconds 20] [-ListChecks]`.
  - `-ListChecks` gibt ohne Systemzugriff den Prüfkatalog aus: Objekte mit `Id`, `Signals` (`string[]`), `Title`.
  - Ohne `-ListChecks`: unter Windows alle Prüfungen ausführen, Tabelle auf der Konsole, JSON nach `WorkerPerf-Quellen_<COMPUTER>_<yyyyMMdd-HHmmss>.json`; außerhalb von Windows Fehler mit dem Wort `Windows`.
  - JSON: `{ SchemaVersion: 1, Computer, OS, PSVersion, Culture, UICulture, IsElevated, Checks: [ { Id, Signals, Title, Ok, Detail, Data } ] }`. `Computer` ist die einzige Namensangabe; alle Pfade laufen durch `Hide-WorkerPerfName`.
  - Enthält die Funktion `Hide-WorkerPerfName([string]$Text, [string[]]$Users) -> [string]`.
- Produces: die Zählernamen der folgenden Tabelle; Task 15 baut auf ihnen auf.

| Check-Id | Signals | .NET-Kategorie / Zähler / Instanz | `Data` |
|---|---|---|---|
| `system` | – | – | Kerne, RAM, Hersteller und Modell aus `Win32_ComputerSystem`, Dienst `VMTools` vorhanden |
| `process.snapshot` | – | – | Prozesszahl, Dauer von drei `Win32_Process`-Abfragen in ms |
| `sessions.wts` | – | – | WTS-C# kompiliert, Sitzungen je Zustand |
| `services.map` | – | – | Dienste mit `ProcessId` aus `Win32_Service`, Dauer |
| `perf.cpu` | `cpu.host` | `Processor Information` / `% Processor Time` / `_Total` | je Zähler: Typ, zwei Rohproben im Abstand 1 s, berechneter Wert |
| `perf.queue` | `cpu.queue` | `System` / `Processor Queue Length` | wie oben |
| `perf.steal` | `cpu.steal` | `VM Processor` / `CPU stolen time` / alle Instanzen | wie oben, zusätzlich alle Zählernamen der Kategorie |
| `perf.memory` | `mem.used`, `mem.commit`, `mem.pagesin` | `Memory` / `Available Bytes`, `Committed Bytes`, `Commit Limit`, `Pages Input/sec` | wie oben |
| `perf.disk.total` | – | `PhysicalDisk` / `Disk Read Bytes/sec`, `Disk Write Bytes/sec`, `Disk Reads/sec`, `Disk Writes/sec`, `Current Disk Queue Length` / `_Total` | wie oben |
| `perf.network` | – | `Network Interface` / `Bytes Received/sec`, `Bytes Sent/sec` / alle | wie oben |
| `perf.volumes` | `disk.latency` | `LogicalDisk` / `Avg. Disk sec/Read`, `Avg. Disk sec/Write`, `Disk Reads/sec`, `Disk Writes/sec`, `Disk Read Bytes/sec`, `Disk Write Bytes/sec`, `Current Disk Queue Length` / alle außer `_Total` | Instanznamen, berechnete Antwortzeiten in ms |
| `perf.shares` | `smb.latency` | `SMB Client Shares` / `Avg. sec/Read`, `Avg. sec/Write`, `Read Requests/sec`, `Write Requests/sec`, `Read Bytes/sec`, `Write Bytes/sec` / alle | Instanznamen maskiert, Werte |
| `perf.input.session` | `input.session` | `User Input Delay per Session` / `Max Input Delay` / alle | Zählertyp, Instanznamen, `-InputSeconds` Proben im Abstand 1 s und halb so viele im Abstand 2 s |
| `perf.input.process` | – | `User Input Delay per Process` / `Max Input Delay` / alle | Zahl der Instanzen, zehn Beispiel-Instanznamen |
| `perf.ica` | `ica.rtt`, `ica.latency` | `ICA Session` / alle Zähler | Zählernamen, Instanzformat maskiert; dazu Klassen und Eigenschaften in `root\citrix\euem` |
| `profile.volumes` | – | – | je Datenträger mit `BusType` 15 aus `MSFT_Disk` (`root\Microsoft\Windows\Storage`): `Location`, Partitionen, `AccessPaths`, Gerätename über `QueryDosDevice`, passende `LogicalDisk`-Instanz, ob ein angemeldeter Benutzername im Pfad vorkommt |
| `events.defender` | – | – | Protokoll `Microsoft-Windows-Windows Defender/Operational` lesbar, Anzahl der Ereignisse 1000, 1001, 1002, 2000 der letzten 7 Tage |
| `events.applocker` | – | – | Protokolle `Microsoft-Windows-AppLocker/EXE and DLL` und `.../MSI and Script` lesbar, Anzahl 8004 und 8007 der letzten 7 Tage |
| `security.products` | – | – | je Prozessname in Sitzung 0: Firma und Beschreibung aus der Dateiversion, zugehörige Dienste |
| `user.processes` | – | – | je Prozessname in Benutzersitzungen: Instanzen, Firma, Beschreibung |
| `endpoints` | `probe.connect` | – | je Gegenstelle aus `-EndpointFile`: Verbindungsdauer in ms oder Fehler |

Jede `perf.*`-Prüfung testet zwei Wege und meldet beide in `Data`: `DotNet` (`System.Diagnostics.PerformanceCounterCategory` mit den englischen Namen der Tabelle, `ReadCategory()` zweimal, Wert über `CounterSample.Calculate`) und `Cim` (Namen aller Klassen `Win32_PerfRawData_*`, die zum Kategorienamen ohne Leerzeichen passen). `Ok` ist wahr, wenn der .NET-Weg für alle Zähler Werte liefert.

- [ ] **Step 1: `tests/Install-TestTools.sh` anlegen und ausführen**

```bash
#!/usr/bin/env bash
# Richtet PowerShell 7 und Pester 5 in einer frischen Linux-Sitzung (x64) ein.
set -euo pipefail
PWSH_VERSION=7.4.6
PESTER_VERSION=5.7.1
if ! command -v pwsh >/dev/null 2>&1; then
  curl -sSL -o /tmp/pwsh.tgz "https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_VERSION}/powershell-${PWSH_VERSION}-linux-x64.tar.gz"
  mkdir -p /opt/pwsh && tar -xzf /tmp/pwsh.tgz -C /opt/pwsh
  chmod +x /opt/pwsh/pwsh && ln -sf /opt/pwsh/pwsh /usr/local/bin/pwsh && rm /tmp/pwsh.tgz
fi
MODDIR="${HOME}/.local/share/powershell/Modules/Pester/${PESTER_VERSION}"
if [ ! -f "${MODDIR}/Pester.psd1" ]; then
  # powershellgallery.com ist in Cloud-Sitzungen gesperrt; nuget.org liefert das Modul unter tools/.
  curl -sSL -o /tmp/pester.nupkg "https://api.nuget.org/v3-flatcontainer/pester/${PESTER_VERSION}/pester.${PESTER_VERSION}.nupkg"
  rm -rf /tmp/pester-x && unzip -q /tmp/pester.nupkg 'tools/*' -d /tmp/pester-x
  mkdir -p "${MODDIR}" && cp -r /tmp/pester-x/tools/. "${MODDIR}/" && rm -rf /tmp/pester-x /tmp/pester.nupkg
fi
pwsh -NoProfile -Command 'Import-Module Pester -MinimumVersion 5.0; "Pester " + (Get-Module Pester).Version'
```

Run: `bash tests/Install-TestTools.sh`
Expected: letzte Zeile `Pester 5.7.1`

- [ ] **Step 2: `tests/Invoke-Tests.ps1` anlegen**

```powershell
#Requires -Version 7.0
param([string[]]$Path = @($PSScriptRoot))
Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
$config = New-PesterConfiguration
$config.Run.Path = $Path
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $config
```

- [ ] **Step 3: Die fehlschlagenden Tests schreiben**

`tests/Compat.Tests.ps1` – die Hilfsfunktion `Get-CompatViolations([string]$Path) -> string[]` steht in derselben Datei und liefert Regelkennungen: `parse` (Parserfehler), `ascii` (Byte über 127), `requires` (erste nichtleere Zeile ist nicht `#Requires -Version 5.1`), `ternary` (`TernaryExpressionAst`), `chain` (`PipelineChainAst`), `nullop` (Token `QuestionQuestion`, `QuestionQuestionEquals`, `QuestionDot`, `QuestionLBracket`), `iswindows` (`$IsWindows`, `$IsLinux`, `$IsMacOS` außerhalb der erlaubten Form), `ps7cmd` (Befehle und Parameter der Verbotsliste aus den Global Constraints).

```powershell
BeforeDiscovery { $script:Sources = @(Get-ChildItem (Join-Path $PSScriptRoot '../src') -Filter *.ps1) }
BeforeAll { function Get-CompatViolations([string]$Path) { <# siehe oben #> } }
Describe 'Pruefregeln fuer Windows PowerShell 5.1' {
    It 'erkennt <Rule>' -TestCases @(
        @{ Rule = 'ternary';   Code = "#Requires -Version 5.1`n`$a = `$b ? 1 : 2" }
        @{ Rule = 'chain';     Code = "#Requires -Version 5.1`nGet-Item x && Get-Item y" }
        @{ Rule = 'nullop';    Code = "#Requires -Version 5.1`n`$a = `$b ?? 1" }
        @{ Rule = 'ascii';     Code = "#Requires -Version 5.1`n'Datentr$([char]0xE4)ger'" }
        @{ Rule = 'requires';  Code = "'ohne Requires'" }
        @{ Rule = 'iswindows'; Code = "#Requires -Version 5.1`nif (`$IsWindows) { 1 }" }
        @{ Rule = 'ps7cmd';    Code = "#Requires -Version 5.1`n'{}' | ConvertFrom-Json -AsHashtable" }
    ) {
        $file = Join-Path $TestDrive "$Rule.ps1"
        [IO.File]::WriteAllText($file, $Code, (New-Object System.Text.UTF8Encoding $false))
        Get-CompatViolations $file | Should -Contain $Rule
    }
    It 'laesst die abgesicherte Plattformabfrage zu' {
        $file = Join-Path $TestDrive 'ok.ps1'
        [IO.File]::WriteAllText($file, "#Requires -Version 5.1`n`$w = (`$PSVersionTable.PSVersion.Major -lt 6) -or `$IsWindows")
        Get-CompatViolations $file | Should -BeNullOrEmpty
    }
}
Describe 'Quelltext' {
    It '<_.Name> haelt die Regeln ein' -ForEach $Sources { Get-CompatViolations $_.FullName | Should -BeNullOrEmpty }
}
```

`tests/Sources.Tests.ps1`:

```powershell
BeforeAll {
    $script:Probe = Join-Path $PSScriptRoot '../src/Test-WorkerPerfSources.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Probe, [ref]$null, [ref]$null)
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Hide-WorkerPerfName' }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
    $script:Checks = @(& $Probe -ListChecks)
}
Describe 'Quellen-Pruefskript' {
    It 'listet die Pruefungen ohne Systemzugriff' {
        $Checks.Id | Should -Be @('system', 'process.snapshot', 'sessions.wts', 'services.map', 'perf.cpu', 'perf.queue', 'perf.steal', 'perf.memory',
            'perf.disk.total', 'perf.network', 'perf.volumes', 'perf.shares', 'perf.input.session', 'perf.input.process', 'perf.ica',
            'profile.volumes', 'events.defender', 'events.applocker', 'security.products', 'user.processes', 'endpoints')
    }
    It 'deckt jedes bewertete Signal ab' {
        $covered = @($Checks | ForEach-Object { $_.Signals })
        foreach ($id in 'cpu.host', 'cpu.queue', 'cpu.steal', 'mem.used', 'mem.commit', 'mem.pagesin', 'input.session', 'disk.latency', 'smb.latency', 'ica.rtt', 'ica.latency', 'probe.connect') {
            $covered | Should -Contain $id
        }
    }
    It 'maskiert Benutzer- und Servernamen' {
        Hide-WorkerPerfName -Text '\\fs01.klinik.local\upm$\mueller.KLINIK\Win2022\ProfileContainer.vhdx' -Users @('mueller', 'mu') |
            Should -Be '\\<server>\upm$\<user>.KLINIK\Win2022\ProfileContainer.vhdx'
        Hide-WorkerPerfName -Text 'C:\Users\Mueller\AppData' -Users @('mueller') | Should -Be 'C:\Users\<user>\AppData'
        Hide-WorkerPerfName -Text 'C:\Program Files\Simulator' -Users @('mu') | Should -Be 'C:\Program Files\Simulator'
    }
    It 'verweigert die Messung ausserhalb von Windows' -Skip:$IsWindows { { & $Probe } | Should -Throw '*Windows*' }
}
```

- [ ] **Step 4: Tests ausführen und Fehlschlag prüfen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Compat.Tests.ps1` grün für die beiden vorhandenen Skripte, `Sources.Tests.ps1` rot (Datei fehlt)

- [ ] **Step 5: `src/Test-WorkerPerfSources.ps1` schreiben**

Eine einzige Datei ohne Abhängigkeit zu anderen Dateien des Projekts (sie wird einzeln auf den Worker kopiert). Jede Prüfung läuft in eigenem `try`/`catch`; ein Fehler setzt `Ok = $false` und `Detail` auf die Meldung, die übrigen Prüfungen laufen weiter. `Hide-WorkerPerfName` ersetzt jeden Namen aus `-Users` ohne Rücksicht auf Groß-/Kleinschreibung durch `<user>`, längere Namen zuerst und nur, wenn davor und danach kein Buchstabe und keine Ziffer steht; ein UNC-Servername am Textanfang wird zu `<server>`. Das Skript ändert nichts am System.

- [ ] **Step 6: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 7: `docs/vda-probe/README.md` schreiben**

Inhalt: Zweck in zwei Sätzen; Aufruf `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-WorkerPerfSources.ps1 -OutFile C:\Temp` in einer Konsole mit erhöhten Rechten; Hinweis, währenddessen etwa 40 Sekunden lang in einer Benutzersitzung zu tippen oder Fenster zu bewegen; optional `-EndpointFile` mit einer nach `endpoints.example.json` angelegten Datei; die JSON-Datei enthält außer dem Computernamen keine Namen und wird zur Auswertung zurückgegeben.

- [ ] **Step 8: Commit**

```bash
git add tests/Install-TestTools.sh tests/Invoke-Tests.ps1 tests/Compat.Tests.ps1 tests/Sources.Tests.ps1 src/Test-WorkerPerfSources.ps1 docs/vda-probe/README.md
git commit -m "Add source probe script and test tooling"
```

**Danach, außerhalb des Plans:** Der Auftraggeber führt das Prüfskript auf einem VDA aus und gibt die JSON-Datei zurück. Sie ist Voraussetzung für Task 15, nicht für die Tasks 2–14.

---

### Task 2: Gemeinsame Grundlagen und Konfiguration

**Files:**
- Create: `src/WorkerPerf.Common.ps1`, `src/thresholds.json`, `src/roles.json`, `src/endpoints.example.json`
- Test: `tests/Common.Tests.ps1`

**Interfaces:**
- Produces:

```powershell
$script:WorkerPerfFormatVersion = 2
$script:WorkerPerfHeaders        # [ordered] Dateiname -> Kopfzeile, siehe Tabelle
function Test-WorkerPerfWindows                                   # -> [bool]
function Format-WorkerPerfNumber($Value, [int]$Decimals = 1)      # -> [string], '' fuer $null und NaN
function Format-WorkerPerfCsvText([string]$Text)                  # -> [string], CR/LF werden Leerzeichen
function Split-WorkerPerfCsvLine([string]$Line)                   # -> [string[]]
function Read-WorkerPerfThresholds([string]$Path)                 # -> [ordered] id -> Eintrag
function Read-WorkerPerfRoles([string]$Path)                      # -> [object[]] Eintraege
function Read-WorkerPerfEndpoints([string]$Path)                  # -> [object[]], leer wenn die Datei fehlt
function Read-WorkerPerfTexts([string]$Path)                      # -> [hashtable] Schluessel -> Text
function Get-WorkerPerfStatus([double]$Value, $Threshold)         # -> 0 | 1 | 2, $null bei NaN
function Get-WorkerPerfHostSignals($Tick, [int]$LogicalProcessors, [double]$PhysicalMemoryMB)   # -> [hashtable]
function Resolve-WorkerPerfRole($Roles, [string]$ProcessName, [string]$Services, [int]$SessionId)   # -> Objekt mit Role, Label
```

| Datei | Kopfzeile |
|---|---|
| `ticks.csv` | `T,Timestamp,ElapsedSec,CpuPct,ProcQueue,StealPct,MemAvailMB,MemCommittedMB,MemCommitLimitMB,PagesInPerSec,DiskReadBps,DiskWriteBps,DiskReadIops,DiskWriteIops,DiskQueue,NetRecvBps,NetSentBps,Burst,CollectMs` |
| `volumes.csv` | `T,Volume,Kind,SessionId,Backing,ReadLatMs,WriteLatMs,ReadOps,WriteOps,ReadBps,WriteBps,Queue` |
| `shares.csv` | `T,Share,ReadLatMs,WriteLatMs,ReadOps,WriteOps,ReadBps,WriteBps` |
| `inputdelay.csv` | `T,SessionId,DelayMs` |
| `inputdelay_proc.csv` | `T,SessionId,Pid,Name,DelayMs` |
| `citrix.csv` | `T,Source,SessionId,Instance,Metric,Value` |
| `probes.csv` | `T,Name,Role,Host,Port,ConnectMs,Error` |
| `events.csv` | `Timestamp,Source,EventId,Kind,Text` |
| `snapshots.csv` | `P,T,Timestamp,ElapsedSec,Kind,Sessions,ActiveSessions,Processes,RowsWritten,CollectMs` |
| `sessions.csv` | `P,SessionId,User,Domain,State,WinStation,ClientName,LogonTime,IdleSec` |
| `procinfo.csv` | `K,Pid,ParentPid,Name,SessionId,StartTime,Path,Services,CommandLine` |
| `processes.csv` | `P,K,CpuMs,WsKB,PrivKB,ReadBytes,WriteBytes,IoOps,Handles,Threads` |
| `procend.csv` | `P,K` |

`thresholds.json` hat die Form `{ "thresholds": [ ... ] }`, je Eintrag `id`, `label`, `unit`, `direction` (`high`), `warn`, `crit`, `ideal`, `minTicks`, `trigger`, `origin`, `source`, `url`, optional `minOps` und `note`. Zahlenwerte stehen im Test; die Texte:

| id | label | unit | ideal | source | note |
|---|---|---|---|---|---|
| `cpu.host` | CPU-Auslastung | `%` | unter 75 % | Citrix DaaS Monitor, vordefinierte Schwellen | |
| `cpu.queue` | Prozessor-Warteschlange je CPU | – | bis 2 je CPU | Microsoft, System-Level Bottlenecks | |
| `cpu.steal` | Entzogene CPU-Zeit je vCPU | `%` | unter 5 % | Faustregel aus dem VMware-Umfeld (CPU Ready), kein offizieller Grenzwert | |
| `mem.used` | RAM-Auslastung | `%` | unter 75 % | Citrix DaaS Monitor, vordefinierte Schwellen | |
| `mem.commit` | Commit-Auslastung | `%` | unter 80 % | Microsoft, Exchange 2013 Performance Counters | kritisch: eigene Annahme |
| `mem.pagesin` | Von Datenträger gelesene Seiten | `1/s` | nahe 0 | Microsoft, ältere Faustregel zu Pages/sec | kritisch: eigene Annahme |
| `input.session` | Eingabeverzögerung | `ms` | unter 150 ms | Microsoft, Azure Virtual Desktop Insights | |
| `disk.latency` | Datenträger-Antwortzeit | `ms` | unter 10 ms | Microsoft, Richtwerte für Avg. Disk sec/Transfer | |
| `smb.latency` | Freigabe-Antwortzeit (SMB) | `ms` | unter 10 ms | wie Datenträger-Antwortzeit | |
| `ica.rtt` | ICA Round Trip | `ms` | unter 150 ms | Citrix, CTX204274 | |
| `ica.latency` | ICA-Netzwerklatenz | `ms` | unter 150 ms | Citrix DaaS Monitor, vordefinierte Schwellen | |
| `probe.connect` | Antwortzeit-Probe | `ms` | unter 50 ms | eigene Annahme | Verbindungsfehler zählen als kritisch |

`url` je Quelle: Citrix DaaS Monitor `https://docs.citrix.com/en-us/citrix-daas/monitor/site-analytics/thresholds`; System-Level Bottlenecks `https://learn.microsoft.com/biztalk/technical-guides/system-level-bottlenecks`; VMware `https://knowledge.broadcom.com/external/article/438023/rightsizing-virtual-machines-on-esxi-80.html`; Exchange `https://learn.microsoft.com/exchange/exchange-2013-performance-counters-exchange-2013-help`; AVD Insights `https://learn.microsoft.com/azure/virtual-desktop/insights-glossary#input-delay`; Datenträger `https://learn.microsoft.com/troubleshoot/system-center/scom/troubleshoot-gray-agent-states`; CTX204274 `https://support.citrix.com/s/article/CTX204274-how-ica-rtt-is-calculated-on-netscaler-insight`; sonst leer.

`roles.json` hat die Form `{ "roles": [ { "role", "label", "processes": [], "services": [], "note" } ] }`; `processes` sind Muster für `-like`:

| role | label | processes | services | note |
|---|---|---|---|---|
| Sicherheit | Microsoft Defender | `MsMpEng.exe`, `NisSrv.exe`, `MpDefenderCoreService.exe`, `MpCmdRun.exe` | `WinDefend`, `WdNisSvc` | |
| Sicherheit | Arctic Wolf Aurora Endpoint Protection | – | – | Prozessnamen per Prüfskript ermitteln |
| Sicherheit | AppLocker | – | `AppIDSvc` | |
| Profil | Citrix Profile Management | `UserProfileManager.exe` | – | ungeprüft |
| Hauptanwendung | Nexus KIS | – | – | Prozessnamen per Prüfskript ermitteln |
| Hauptanwendung | Oracle-Client | – | – | Prozessnamen per Prüfskript ermitteln |
| Citrix | Citrix VDA | `BrokerAgent.exe`, `Ctx*.exe`, `picaSvc*.exe`, `wfshell.exe` | – | ungeprüft |

`endpoints.example.json`: `{ "endpoints": [ ... ] }` mit `Oracle-Listener` (`ora-db.example.local`, 1521, Rolle `Datenbank`), `FortiGate-Proxy` (`proxy.example.local`, 8080, `Proxy`), `Dateiserver` (`fs01.example.local`, 445, `Dateiserver`).

- [ ] **Step 1: Den fehlschlagenden Test schreiben** (`tests/Common.Tests.ps1`)

```powershell
BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1')
    $script:Src = Join-Path $PSScriptRoot '../src'
    $script:Th = Read-WorkerPerfThresholds (Join-Path $Src 'thresholds.json')
    $script:Roles = Read-WorkerPerfRoles (Join-Path $Src 'roles.json')
    function Write-Json([string]$Name, [string]$Json) { $p = Join-Path $TestDrive $Name; [IO.File]::WriteAllText($p, $Json); $p }
    $script:Entry = '{{"id":"{0}","label":"x","unit":"%","direction":"high","warn":{1},"crit":{2},"ideal":"x","minTicks":3,"trigger":false,"origin":"{3}","source":"x","url":""}}'
}
Describe 'Schwellwerte' {
    It 'liefert <Id> mit den Startwerten der Spezifikation' -TestCases @(
        @{ Id = 'cpu.host';      Warn = 75;  Crit = 90;  MinTicks = 3; Trigger = $true;  Origin = 'Herstellerangabe' }
        @{ Id = 'cpu.queue';     Warn = 2;   Crit = 5;   MinTicks = 3; Trigger = $false; Origin = 'Herstellerangabe' }
        @{ Id = 'cpu.steal';     Warn = 5;   Crit = 10;  MinTicks = 3; Trigger = $false; Origin = 'Faustregel' }
        @{ Id = 'mem.used';      Warn = 75;  Crit = 90;  MinTicks = 3; Trigger = $true;  Origin = 'Herstellerangabe' }
        @{ Id = 'mem.commit';    Warn = 80;  Crit = 90;  MinTicks = 3; Trigger = $false; Origin = 'Herstellerangabe' }
        @{ Id = 'mem.pagesin';   Warn = 10;  Crit = 100; MinTicks = 3; Trigger = $false; Origin = 'Faustregel' }
        @{ Id = 'input.session'; Warn = 150; Crit = 500; MinTicks = 1; Trigger = $true;  Origin = 'Herstellerangabe' }
        @{ Id = 'disk.latency';  Warn = 10;  Crit = 20;  MinTicks = 3; Trigger = $true;  Origin = 'Herstellerangabe' }
        @{ Id = 'smb.latency';   Warn = 10;  Crit = 20;  MinTicks = 3; Trigger = $true;  Origin = 'eigene Annahme' }
        @{ Id = 'ica.rtt';       Warn = 150; Crit = 300; MinTicks = 3; Trigger = $false; Origin = 'Herstellerangabe' }
        @{ Id = 'ica.latency';   Warn = 150; Crit = 250; MinTicks = 3; Trigger = $false; Origin = 'Herstellerangabe' }
        @{ Id = 'probe.connect'; Warn = 50;  Crit = 200; MinTicks = 3; Trigger = $false; Origin = 'eigene Annahme' }
    ) {
        $e = $Th[$Id]
        $e.warn | Should -Be $Warn; $e.crit | Should -Be $Crit; $e.minTicks | Should -Be $MinTicks
        $e.trigger | Should -Be $Trigger; $e.origin | Should -Be $Origin
    }
    It 'kennt zwoelf Signale und Mindestaktivitaet nur bei Antwortzeiten' {
        $Th.Count | Should -Be 12
        $Th['disk.latency'].minOps | Should -Be 5; $Th['smb.latency'].minOps | Should -Be 5; $Th['cpu.host'].minOps | Should -Be 0
    }
    It 'nennt den fehlerhaften Eintrag oder die Datei' {
        { Read-WorkerPerfThresholds (Write-Json 'a.json' ('{"thresholds":[' + ($Entry -f 'cpu.host', 95, 90, 'Faustregel') + ']}')) } | Should -Throw '*cpu.host*'
        { Read-WorkerPerfThresholds (Write-Json 'b.json' ('{"thresholds":[' + ($Entry -f 'x.y', 1, 2, 'geraten') + ']}')) } | Should -Throw '*x.y*'
        { Read-WorkerPerfThresholds (Write-Json 'c.json' ('{"thresholds":[' + ($Entry -f 'x.y', 1, 2, 'Faustregel') + ',' + ($Entry -f 'x.y', 1, 2, 'Faustregel') + ']}')) } | Should -Throw '*x.y*'
        { Read-WorkerPerfThresholds (Write-Json 'd.json' '{ kaputt') } | Should -Throw '*d.json*'
    }
}
Describe 'Get-WorkerPerfStatus' {
    It 'stuft Werte ein' {
        Get-WorkerPerfStatus 74.9 $Th['cpu.host'] | Should -Be 0
        Get-WorkerPerfStatus 75 $Th['cpu.host'] | Should -Be 1
        Get-WorkerPerfStatus 90 $Th['cpu.host'] | Should -Be 2
        Get-WorkerPerfStatus ([double]::PositiveInfinity) $Th['probe.connect'] | Should -Be 2
        Get-WorkerPerfStatus ([double]::NaN) $Th['cpu.host'] | Should -BeNullOrEmpty
    }
    It 'kehrt die Richtung bei direction low um' {
        $low = [pscustomobject]@{ direction = 'low'; warn = 20; crit = 10 }
        Get-WorkerPerfStatus 25 $low | Should -Be 0; Get-WorkerPerfStatus 20 $low | Should -Be 1; Get-WorkerPerfStatus 10 $low | Should -Be 2
    }
}
Describe 'Get-WorkerPerfHostSignals' {
    It 'leitet die bewerteten Groessen ab' {
        $tick = [pscustomobject]@{ CpuPct = 50; ProcQueue = 16; StealPct = $null; MemAvailMB = 16384; MemCommittedMB = 40000; MemCommitLimitMB = 50000; PagesInPerSec = 3 }
        $s = Get-WorkerPerfHostSignals -Tick $tick -LogicalProcessors 8 -PhysicalMemoryMB 65536
        $s['cpu.host'] | Should -Be 50; $s['cpu.queue'] | Should -Be 2; $s['mem.used'] | Should -Be 75; $s['mem.commit'] | Should -Be 80; $s['mem.pagesin'] | Should -Be 3
        [double]::IsNaN($s['cpu.steal']) | Should -BeTrue
    }
}
Describe 'Resolve-WorkerPerfRole' {
    It 'ordnet nach Prozessname, Muster und Dienst zu' {
        (Resolve-WorkerPerfRole $Roles 'msmpeng.EXE' '' 0).Label | Should -Be 'Microsoft Defender'
        (Resolve-WorkerPerfRole $Roles 'CtxSvcHost.exe' '' 0).Role | Should -Be 'Citrix'
        (Resolve-WorkerPerfRole $Roles 'svchost.exe' 'Foo;AppIDSvc' 0).Label | Should -Be 'AppLocker'
        (Resolve-WorkerPerfRole $Roles 'svchost.exe' 'Dnscache' 0).Role | Should -Be 'System'
        (Resolve-WorkerPerfRole $Roles 'winword.exe' '' 5).Role | Should -Be ''
    }
    It 'nennt den fehlerhaften Rolleneintrag' {
        { Read-WorkerPerfRoles (Write-Json 'r.json' '{"roles":[{"role":"Unsinn","label":"Testprodukt","processes":[],"services":[]}]}') } | Should -Throw '*Testprodukt*'
    }
}
Describe 'Gegenstellen' {
    It 'liefert ohne Datei eine leere Liste' { @(Read-WorkerPerfEndpoints (Join-Path $TestDrive 'fehlt.json')).Count | Should -Be 0 }
    It 'liest die Beispieldatei' { @(Read-WorkerPerfEndpoints (Join-Path $Src 'endpoints.example.json')).Count | Should -Be 3 }
    It 'nennt die fehlerhafte Gegenstelle' { { Read-WorkerPerfEndpoints (Write-Json 'e.json' '{"endpoints":[{"name":"DB","host":"h","port":70000,"role":""}]}') } | Should -Throw '*DB*' }
}
Describe 'CSV-Helfer' {
    It 'schreibt Zahlen unabhaengig von der Kultur' {                          # Review Focus 2
        [cultureinfo]::CurrentCulture = [cultureinfo]'de-DE'
        Format-WorkerPerfNumber 12.5 1 | Should -Be '12.5'
        Format-WorkerPerfNumber 1234567.891 0 | Should -Be '1234568'
        Format-WorkerPerfNumber $null | Should -Be ''
        Format-WorkerPerfNumber ([double]::NaN) | Should -Be ''
    }
    It 'uebersteht Komma, Anfuehrungszeichen, Umlaut und Zeilenumbruch' {      # Review Focus 2
        $name = "M$([char]0xFC)ller, K"
        $line = (Format-WorkerPerfCsvText $name) + ',' + (Format-WorkerPerfCsvText 'sagt "hi"') + ',' + (Format-WorkerPerfCsvText "a`r`nb")
        Split-WorkerPerfCsvLine $line | Should -Be @($name, 'sagt "hi"', 'a  b')
    }
}
Describe 'Formatkonstanten' {
    It 'kennt die dreizehn Dateien mit ihren Kopfzeilen' {
        $WorkerPerfHeaders.Count | Should -Be 13
        $WorkerPerfHeaders['processes.csv'] | Should -Be 'P,K,CpuMs,WsKB,PrivKB,ReadBytes,WriteBytes,IoOps,Handles,Threads'
        $WorkerPerfHeaders['ticks.csv'].Split(',').Count | Should -Be 19
    }
}
```

- [ ] **Step 2: Test ausführen und Fehlschlag prüfen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Common.Tests.ps1`
Expected: FAIL, `WorkerPerf.Common.ps1` nicht gefunden

- [ ] **Step 3: Die drei JSON-Dateien und `src/WorkerPerf.Common.ps1` schreiben**

Regeln, die Signaturen und Tests offenlassen:
- JSON immer mit `[IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)` lesen. Ein Lesefehler nennt den Dateinamen, ein Inhaltsfehler die `id` bzw. den `name` des Eintrags.
- Schwellwerte gültig, wenn: `id` eindeutig und nicht leer; `direction` `high` oder `low`; bei `high` `warn <= crit`, bei `low` `warn >= crit`; `minTicks >= 1`; `origin` eines von `Herstellerangabe`, `Faustregel`, `eigene Annahme`. Fehlendes `minOps` wird 0, fehlende `note` wird `''`.
- Gegenstellen gültig, wenn `name` eindeutig und nicht leer, `host` nicht leer, `port` 1–65535.
- Rollen gültig, wenn `role` eines von `Hauptanwendung`, `Sicherheit`, `Profil`, `Citrix`, `System` ist und `label` nicht leer; der Fehler nennt das `label`.
- Status: bei `high` 1 ab `warn`, 2 ab `crit` (jeweils einschließlich). `Get-WorkerPerfStatus` liest vom Schwellwert nur `direction`, `warn` und `crit`.
- Host-Signale: `cpu.host` = `CpuPct`; `cpu.queue` = `ProcQueue / LogicalProcessors`; `cpu.steal` = `StealPct`; `mem.used` = `100 * (1 - MemAvailMB / PhysicalMemoryMB)`; `mem.commit` = `100 * MemCommittedMB / MemCommitLimitMB`; `mem.pagesin` = `PagesInPerSec`; fehlende Eingangswerte ergeben NaN.
- Rollen: erster Eintrag gewinnt, dessen Muster auf den Prozessnamen passt oder der einen der durch `;` getrennten Dienste nennt (ohne Rücksicht auf Groß-/Kleinschreibung). Ohne Treffer: `System` in Sitzung 0, sonst `''`; `Label` dann `''`.
- Die Funktionen `Format-Num`, `Format-CsvText` und `Split-CsvLine` der bestehenden Skripte sind die Vorlage für die drei CSV-Helfer.

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Common.Tests.ps1,tests/Compat.Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Common.ps1 src/thresholds.json src/roles.json src/endpoints.example.json tests/Common.Tests.ps1
git commit -m "Add shared format constants and configuration files"
```

---

### Task 3: Befunde je Signal und Soll-Ist

**Files:**
- Create: `src/WorkerPerf.Findings.ps1`
- Test: `tests/Findings.Tests.ps1`

**Interfaces:**
- Consumes: `Get-WorkerPerfStatus`, Schwellwert-Einträge (Task 2).
- Produces:

```powershell
# Messreihe (Eingabe): Hashtable mit Id, Instance, Label, Resource, Scope ('global'|'session'), SessionIndex (-1 = keine),
#   TimeMs [long[]], ElapsedSec [double[]], Value [double[]] (NaN = kein Wert), Ops [double[]] oder $null
function Get-WorkerPerfFindings { param([AllowEmptyCollection()][object[]]$Series, $Thresholds, [int]$BridgeSeconds = 10) }
#   -> Befunde, nach StartMs sortiert: SignalId, Resource, Instance, Label, Scope, SessionIndex, StartMs, EndMs,
#      Severity (1|2), PeakValue, PeakTimeMs, BadPoints
function Get-WorkerPerfSollIst { param([AllowEmptyCollection()][object[]]$Series, $Thresholds, [hashtable]$Sources = @{}) }
#   -> je Schwellwert in Dateireihenfolge: Id, Label, Unit, Ideal, Warn, Crit, Origin, Source, Url, Note, Measured, Detail,
#      Avg, P95, Max, PctNormal, PctWarn, PctCrit, WorstInstance
```

- [ ] **Step 1: Den fehlschlagenden Test schreiben**

```powershell
BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Findings.ps1')
    $script:Th = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json')
    $script:T0 = 1700000000000
    function New-TestSeries([string]$Id, [double[]]$Values, [int]$StepSec = 2, [double[]]$Ops = $null) {
        $n = $Values.Length
        @{ Id = $Id; Instance = ''; Label = $Id; Resource = 'cpu'; Scope = 'global'; SessionIndex = -1
           TimeMs = [long[]](0..($n - 1) | ForEach-Object { $script:T0 + $_ * $StepSec * 1000 })
           ElapsedSec = [double[]](1..$n | ForEach-Object { $StepSec }); Value = $Values; Ops = $Ops }
    }
    function Get-Found($Series) { , @(Get-WorkerPerfFindings -Series @($Series) -Thresholds $Th) }      # Komma: das Array bleibt auch mit 0 oder 1 Befund erhalten
}
Describe 'Get-WorkerPerfFindings' {
    It 'meldet nichts unter minTicks' { (Get-Found (New-TestSeries 'cpu.host' 50,80,80,50)).Count | Should -Be 0 }
    It 'bildet einen Befund ab drei Messpunkten' {
        $f = Get-Found (New-TestSeries 'cpu.host' 50,80,95,80,50)
        $f.Count | Should -Be 1
        $f[0].StartMs | Should -Be $T0                  # der erste auffaellige Punkt deckt die 2 s davor ab
        $f[0].EndMs | Should -Be ($T0 + 6000)
        $f[0].Severity | Should -Be 2; $f[0].PeakValue | Should -Be 95; $f[0].BadPoints | Should -Be 3
    }
    It 'ueberbrueckt Luecken bis 10 Sekunden' {         # auffaellig bei 0, 2 und 12 s
        $f = Get-Found (New-TestSeries 'cpu.host' 80,80,50,50,50,50,80)
        $f.Count | Should -Be 1; $f[0].BadPoints | Should -Be 3
    }
    It 'trennt bei Luecken ueber 10 Sekunden' { (Get-Found (New-TestSeries 'cpu.host' 80,80,80,50,50,50,50,50,50,80,80,80)).Count | Should -Be 2 }
    It 'wertet aufeinanderfolgende Punkte eines langsamen Takts' { (Get-Found (New-TestSeries 'ica.rtt' 200,200,200 -StepSec 15)).Count | Should -Be 1 }
    It 'wertet einen einzelnen Haenger der Eingabeverzoegerung' {
        $f = Get-Found (New-TestSeries 'input.session' 0,0,800,0)
        $f.Count | Should -Be 1; $f[0].Severity | Should -Be 2
    }
    It 'bewertet Antwortzeiten erst ab minOps Zugriffen' {                      # Review Focus 5
        (Get-Found (New-TestSeries 'disk.latency' 80,80,80,80 -Ops 1,2,1,0)).Count | Should -Be 0
        (Get-Found (New-TestSeries 'disk.latency' 80,80,80,80 -Ops 50,50,50,50)).Count | Should -Be 1
    }
    It 'behandelt fehlende Werte als unauffaellig' {
        $nan = [double]::NaN
        (Get-Found (New-TestSeries 'cpu.host' 80,$nan,80,$nan,80)).Count | Should -Be 1
        (Get-Found (New-TestSeries 'cpu.host' $nan,$nan,$nan)).Count | Should -Be 0
    }
    It 'wertet einen Verbindungsfehler als kritisch' {
        $inf = [double]::PositiveInfinity
        (Get-Found (New-TestSeries 'probe.connect' $inf,$inf,$inf -StepSec 15))[0].Severity | Should -Be 2
    }
    It 'uebergeht Reihen ohne Schwellwert' { (Get-Found (New-TestSeries 'unbekannt.x' 999,999,999)).Count | Should -Be 0 }
}
Describe 'Get-WorkerPerfSollIst' {
    It 'bewertet einen Messwert gegen das Soll' {
        $r = Get-WorkerPerfSollIst -Series @(New-TestSeries 'cpu.host' 50,80,95,80,50) -Thresholds $Th | Where-Object Id -eq 'cpu.host'
        $r.Measured | Should -BeTrue; $r.Avg | Should -Be 71; $r.Max | Should -Be 95
        $r.PctNormal | Should -Be 40; $r.PctWarn | Should -Be 40; $r.PctCrit | Should -Be 20
    }
    It 'weist fehlende Messwerte als nicht gemessen aus und nennt den Grund' {
        $all = @(Get-WorkerPerfSollIst -Series @() -Thresholds $Th -Sources @{ 'cpu.steal' = @{ Available = $false; Detail = 'VM Processor fehlt' } })
        $all.Count | Should -Be 12; @($all | Where-Object Measured).Count | Should -Be 0
        ($all | Where-Object Id -eq 'cpu.steal').Detail | Should -Be 'VM Processor fehlt'
    }
    It 'nimmt bei mehreren Instanzen je Messpunkt die schlechteste' {
        $a = New-TestSeries 'disk.latency' 2,30,2 -Ops 50,50,50; $a.Label = 'Laufwerk C:'
        $b = New-TestSeries 'disk.latency' 4,4,15 -Ops 50,50,50; $b.Label = 'Laufwerk D:'
        $r = Get-WorkerPerfSollIst -Series @($a, $b) -Thresholds $Th | Where-Object Id -eq 'disk.latency'
        $r.Max | Should -Be 30; [Math]::Round($r.PctNormal) | Should -Be 33; $r.WorstInstance | Should -Be 'Laufwerk C:'
    }
}
```

- [ ] **Step 2: Test ausführen und Fehlschlag prüfen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Findings.Tests.ps1`
Expected: FAIL, `WorkerPerf.Findings.ps1` nicht gefunden

- [ ] **Step 3: Beide Funktionen implementieren**

- Ein Messpunkt ist auffällig, wenn sein Status mindestens 1 ist. Nicht bewertbar (und damit nicht auffällig) ist er bei NaN oder wenn der Schwellwert `minOps > 0` hat und `Ops` an dieser Stelle darunter liegt.
- Eine Folge beginnt an einem auffälligen Punkt. Der nächste auffällige Punkt gehört dazu, wenn er unmittelbar folgt oder höchstens `BridgeSeconds` nach dem letzten auffälligen Punkt liegt. Ein Befund entsteht, wenn die Folge mindestens `minTicks` auffällige Punkte enthält.
- `StartMs` = Zeit des ersten auffälligen Punkts minus dessen `ElapsedSec`, `EndMs` = Zeit des letzten. `PeakValue` ist der schlechteste Wert der auffälligen Punkte.
- Soll-Ist: je Signal alle Reihen mit dieser `Id`; je Messpunkt zählt der schlechteste bewertbare Wert aller Instanzen. `Measured` ist wahr, wenn es mindestens einen bewertbaren Punkt gibt; sonst sind die Kennzahlen `$null`. `P95` wie `Get-Stats` im bestehenden Berichtsskript. Die Anteile beziehen sich auf die bewertbaren Punkte. `WorstInstance` ist das `Label` der Instanz mit den meisten auffälligen Punkten, bei Gleichstand mit der höchsten Spitze; bei nur einer Reihe `''`. `Detail` kommt aus `Sources[id].Detail`.

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Findings.Tests.ps1,tests/Compat.Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Findings.ps1 tests/Findings.Tests.ps1
git commit -m "Add per-signal findings and target comparison"
```

---

### Task 4: Vorfälle

**Files:**
- Modify: `src/WorkerPerf.Findings.ps1`
- Test: `tests/Incidents.Tests.ps1`

**Interfaces:**
- Consumes: Befunde aus `Get-WorkerPerfFindings`.
- Produces:

```powershell
function Join-WorkerPerfIncidents { param([AllowEmptyCollection()][object[]]$Findings, [int]$MergeSeconds = 10, [int]$ChronicMinutes = 15) }
#   -> Vorfaelle (Hashtables), nach StartMs sortiert und ab 1 nummeriert: Id, StartMs, EndMs, Severity, Chronic,
#      Type ('engpass'|'ohne-engpass'|'umfeld'), Lead (Ressource oder $null), Resources [string[]], Findings [object[]],
#      ChronicContext [object[]] mit IncidentId, SignalId, Label, Severity, Explains
```

Ressourcen: `input` (Symptom); Worker-Ressourcen `cpu`, `memory`, `disk`, `share`, `profile`; Umfeld `network`, `endpoint`. Sitzungsbezogen (`Scope = 'session'`) sind `input`, `profile`, `network`.

- [ ] **Step 1: Den fehlschlagenden Test schreiben**

```powershell
BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Findings.ps1')
    $script:T0 = 1700000000000
    function New-TestFinding([string]$Resource, [double]$StartSec, [double]$EndSec, [int]$Severity = 1, [int]$SessionIndex = -1, [string]$SignalId = '') {
        $scope = if ($Resource -in 'input', 'profile', 'network') { 'session' } else { 'global' }
        @{ SignalId = $(if ($SignalId) { $SignalId } else { "$Resource.test" }); Resource = $Resource; Instance = ''; Label = $Resource; Scope = $scope; SessionIndex = $SessionIndex
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
        $x.Type | Should -Be 'engpass'; $x.Lead | Should -Be 'cpu'; $x.ChronicContext[0].Explains | Should -BeTrue
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
    It 'liefert ohne Befunde nichts' { @(Join-WorkerPerfIncidents -Findings @()).Count | Should -Be 0 }
}
```

- [ ] **Step 2: Test ausführen und Fehlschlag prüfen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Incidents.Tests.ps1`
Expected: FAIL, `Join-WorkerPerfIncidents` nicht definiert

- [ ] **Step 3: `Join-WorkerPerfIncidents` implementieren**

1. **Dauerzustand:** Ein Befund mit Dauer über `ChronicMinutes` wird ein eigener Vorfall mit `Chronic = $true` und nimmt an Schritt 2 und 3 nicht teil.
2. **Kern:** Die übrigen Befunde der Ressourcen `input`, `cpu`, `memory`, `disk`, `share`, `endpoint` nach `StartMs` sortieren und transitiv zusammenfassen, solange der nächste höchstens `MergeSeconds` nach dem bisherigen Ende beginnt. Das Fenster des Vorfalls ist die Vereinigung dieser Befunde.
3. **Sitzungsbezogene Ursachen** (`profile`, `network`): an den Kernvorfall anhängen, der einen `input`-Befund derselben `SessionIndex` enthält, der sich mit ihm überschneidet oder höchstens `MergeSeconds` entfernt liegt; das Fenster ändert sich dadurch nicht. Sonst bildet der Befund einen eigenen Vorfall; eigenständige Befunde derselben Sitzung werden untereinander nach derselben Zeitregel zusammengefasst.
4. **Typ:** `engpass`, wenn der Vorfall einen Befund einer Worker-Ressource enthält oder sich mit einem Dauerzustand einer Worker-Ressource der Stufe 2 überschneidet; sonst `ohne-engpass`, wenn er einen `input`-Befund enthält; sonst `umfeld`.
5. **Lead:** die Worker-Ressource mit dem frühesten Beginn (bei Gleichstand in der Reihenfolge `cpu`, `memory`, `disk`, `share`, `profile`); bei reiner Erklärung durch einen Dauerzustand dessen Ressource; sonst `$null`.
6. **Resources:** alle Ressourcen der Befunde außer `input`, nach frühestem Beginn.
7. **ChronicContext:** alle Dauerzustände, die das Fenster überschneiden; `Explains` ist wahr bei Worker-Ressource und Stufe 2.
8. `Severity` ist die höchste Stufe der Befunde. Zum Schluss alle Vorfälle nach `StartMs`, dann `EndMs` sortieren und nummerieren.

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Incidents.Tests.ps1,tests/Findings.Tests.ps1,tests/Compat.Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Findings.ps1 tests/Incidents.Tests.ps1
git commit -m "Merge findings into incidents with chronic and session rules"
```

---

### Task 5: Collector-Logik – Prozesszeilen und Aktiv-Filter

**Files:**
- Create: `src/WorkerPerf.Capture.ps1`
- Test: `tests/Capture.Tests.ps1`

**Interfaces:**
- Consumes: `Format-WorkerPerfCsvText`, `Format-WorkerPerfNumber` (Task 2).
- Produces:

```powershell
function New-WorkerPerfProcessState                       # -> Hashtable
function Get-WorkerPerfProcessRows {
    param($State, [AllowEmptyCollection()][object[]]$Processes, [int]$P, [datetime]$PrevTime, [switch]$Keyframe,
          [hashtable]$Services = @{}, [switch]$IncludeCommandLine)
}   # -> @{ Rows = [string[]]; Info = [string[]]; Ended = [string[]]; Total = [int]; CpuMs = [double] }
```

`Processes` sind Objekte mit den Eigenschaften von `Win32_Process`: `ProcessId`, `ParentProcessId`, `Name`, `SessionId`, `KernelModeTime`, `UserModeTime` (100 ns), `WorkingSetSize`, `PrivatePageCount`, `ReadTransferCount`, `WriteTransferCount` (Bytes), `ReadOperationCount`, `WriteOperationCount`, `HandleCount`, `ThreadCount`, `CreationDate` (`[datetime]` oder `$null`), `ExecutablePath`, `CommandLine`. `Rows`, `Info` und `Ended` sind fertige Zeilen für `processes.csv`, `procinfo.csv` und `procend.csv`. `Services` bildet PID auf `Dienst1;Dienst2` ab.

- [ ] **Step 1: Den fehlschlagenden Test schreiben**

```powershell
BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Capture.ps1')
    $script:t = [datetime]'2026-01-15T08:00:00'
    function New-TestProc([int]$Id, [double]$CpuSec, [double]$WsMB, [double]$IoBytes = 0, [datetime]$Start = [datetime]'2026-01-01') {
        [pscustomobject]@{ ProcessId = $Id; ParentProcessId = 4; Name = "p$Id.exe"; SessionId = 1
            KernelModeTime = [uint64]0; UserModeTime = [uint64]($CpuSec * 1e7); WorkingSetSize = [uint64]($WsMB * 1MB); PrivatePageCount = [uint64]($WsMB * 1MB)
            ReadTransferCount = [uint64]$IoBytes; WriteTransferCount = [uint64]0; ReadOperationCount = [uint64]0; WriteOperationCount = [uint64]0
            HandleCount = 100; ThreadCount = 5; CreationDate = $Start; ExecutablePath = "C:\App\p$Id.exe"; CommandLine = '' }
    }
    function Start-TestState([object[]]$Procs) {      # Grundstand und erster Stuetzpunkt
        $s = New-WorkerPerfProcessState
        [void](Get-WorkerPerfProcessRows -State $s -Processes $Procs -P -1 -PrevTime $t)
        [void](Get-WorkerPerfProcessRows -State $s -Processes $Procs -P 0 -PrevTime $t -Keyframe)
        $s
    }
}
Describe 'Get-WorkerPerfProcessRows' {
    It 'schreibt im Stuetzpunkt alle, danach nur aktive Prozesse' {
        $s = New-WorkerPerfProcessState; $both = @((New-TestProc 10 1 100), (New-TestProc 20 1 100))
        (Get-WorkerPerfProcessRows -State $s -Processes $both -P -1 -PrevTime $t).Rows.Count | Should -Be 0
        $r0 = Get-WorkerPerfProcessRows -State $s -Processes $both -P 0 -PrevTime $t -Keyframe
        $r0.Rows.Count | Should -Be 2; $r0.Info.Count | Should -Be 2; $r0.Total | Should -Be 2
        $r1 = Get-WorkerPerfProcessRows -State $s -Processes @((New-TestProc 10 1.5 100), (New-TestProc 20 1 100)) -P 1 -PrevTime $t
        $r1.Rows | Should -Be @('1,0,500,102400,102400,0,0,0,100,5'); $r1.CpuMs | Should -Be 500
    }
    It 'sammelt Speicheraenderungen bis zur Schwelle von 1 MB' {
        $s = Start-TestState @(New-TestProc 10 1 100)
        $counts = foreach ($i in 1..4) { (Get-WorkerPerfProcessRows -State $s -Processes @(New-TestProc 10 1 (100 + 0.3 * $i)) -P $i -PrevTime $t).Rows.Count }
        $counts | Should -Be @(0, 0, 0, 1)
    }
    It 'verliert keine CPU-Zeit unterhalb einer Millisekunde' {
        $s = Start-TestState @(New-TestProc 10 1 100); $ms = 0
        foreach ($i in 1..10) {
            $r = Get-WorkerPerfProcessRows -State $s -Processes @(New-TestProc 10 (1 + 0.0004 * $i) 100) -P $i -PrevTime $t
            foreach ($row in $r.Rows) { $ms += [int]$row.Split(',')[2] }
        }
        $ms | Should -Be 4
    }
    It 'wertet I/O als Aktivitaet' {
        $s = Start-TestState @(New-TestProc 10 1 100)
        (Get-WorkerPerfProcessRows -State $s -Processes @(New-TestProc 10 1 100 -IoBytes 4096) -P 1 -PrevTime $t).Rows | Should -Be @('1,0,0,102400,102400,4096,0,0,100,5')
    }
    It 'rechnet einem im Intervall gestarteten Prozess seine bisherige CPU-Zeit an' {
        $s = New-WorkerPerfProcessState
        [void](Get-WorkerPerfProcessRows -State $s -Processes @() -P -1 -PrevTime $t)
        $r = Get-WorkerPerfProcessRows -State $s -Processes @((New-TestProc 30 2 50 -Start $t.AddSeconds(5)), (New-TestProc 40 7 50 -Start $t.AddHours(-1))) -P 0 -PrevTime $t -Keyframe
        ($r.Rows | ForEach-Object { $_.Split(',')[2] }) | Should -Be @('2000', '0')
    }
    It 'meldet beendete Prozesse und unterscheidet wiederverwendete PIDs' {    # Review Focus 4
        $a = New-TestProc 10 1 100; $s = Start-TestState @($a, (New-TestProc 20 1 100))
        $r = Get-WorkerPerfProcessRows -State $s -Processes @($a, (New-TestProc 20 0.5 80 -Start $t.AddSeconds(20))) -P 2 -PrevTime $t.AddSeconds(15)
        $r.Ended | Should -Be @('2,1'); $r.Info.Count | Should -Be 1; $r.Info[0] | Should -Match '^2,20,'
        $r.Rows | Should -Be @('2,2,500,81920,81920,0,0,0,100,5')
    }
    It 'traegt Dienste und auf Wunsch die Befehlszeile ein' {
        $s = New-WorkerPerfProcessState; $p = New-TestProc 10 1 100; $p.CommandLine = 'p10.exe /x'
        [void](Get-WorkerPerfProcessRows -State $s -Processes @($p) -P -1 -PrevTime $t)
        (Get-WorkerPerfProcessRows -State $s -Processes @($p) -P 0 -PrevTime $t -Keyframe -Services @{ 10 = 'AppIDSvc;Foo' }).Info[0] | Should -Match ',AppIDSvc;Foo,$'
        $s2 = New-WorkerPerfProcessState
        [void](Get-WorkerPerfProcessRows -State $s2 -Processes @($p) -P -1 -PrevTime $t)
        (Get-WorkerPerfProcessRows -State $s2 -Processes @($p) -P 0 -PrevTime $t -Keyframe -IncludeCommandLine).Info[0] | Should -Match ',p10\.exe /x$'
    }
}
```

- [ ] **Step 2: Test ausführen und Fehlschlag prüfen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Capture.Tests.ps1`
Expected: FAIL, `WorkerPerf.Capture.ps1` nicht gefunden

- [ ] **Step 3: Beide Funktionen implementieren**

- Schlüssel eines Prozesses: `ProcessId` und `CreationDate.Ticks` (0 ohne Datum).
- `P = -1` ist der Grundstand: Zählerstände merken, nichts ausgeben.
- Ein Prozess bekommt seine Nummer `K` (fortlaufend ab 0) und seine `procinfo`-Zeile, wenn zum ersten Mal eine Zeile für ihn geschrieben wird.
- Die Deltas zählen gegen den **verbuchten** Stand, nicht gegen den letzten Schnappschuss: verbucht wird nur, was geschrieben wurde (CPU in ganzen Millisekunden, I/O in Bytes, Working Set in KB). So geht durch Rundung und durch ausgelassene Zeilen nichts verloren.
- Eine Zeile wird geschrieben, wenn `-Keyframe` gesetzt ist, der Prozess neu ist, das CPU-Delta mindestens 1 ms beträgt, Lese- oder Schreibbytes angefallen sind oder das Working Set mindestens 1024 KB vom zuletzt geschriebenen Wert abweicht.
- Ein unbekannter Prozess, dessen `CreationDate` nach `PrevTime` liegt, bekommt seine gesamten bisherigen Zählerstände als Delta, jeder andere unbekannte Prozess 0.
- Für jeden Prozess mit `K`, der nicht mehr vorkommt: Zeile `P,K` in `Ended`, Eintrag aus dem Zustand entfernen.
- `IoOps` ist das Delta aus Lese- plus Schreiboperationen; negative Deltas werden 0.

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Capture.Tests.ps1,tests/Compat.Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Capture.ps1 tests/Capture.Tests.ps1
git commit -m "Add process row logic with activity filter"
```

---

### Task 6: Collector-Logik – Takte, Verdichtung, Schutzgrenzen

**Files:**
- Modify: `src/WorkerPerf.Capture.ps1`
- Test: `tests/Schedule.Tests.ps1`

**Interfaces:**
- Consumes: `Get-WorkerPerfStatus`, `Get-WorkerPerfHostSignals`, `$script:WorkerPerfHeaders` (Task 2).
- Produces:

```powershell
function New-WorkerPerfBurstState                        # -> Hashtable
function Update-WorkerPerfBurstState { param($State, [datetime]$Now, [AllowEmptyCollection()][string[]]$BadSignals, [int]$HoldSeconds = 60, [int]$MaxEpisodeSeconds = 300) }   # -> [bool]
function Get-WorkerPerfTriggerSignals { param($Sample, $Thresholds, [int]$LogicalProcessors, [double]$PhysicalMemoryMB) }   # -> [string[]] in Dateireihenfolge
function Get-WorkerPerfSnapshotDue { param([datetime]$Now, [datetime]$NextRegular, [datetime]$LastSnapshot, [bool]$BurstActive, [int]$BurstIntervalSeconds = 5) }   # -> 'none'|'regular'|'burst'
function Get-WorkerPerfNextTick { param([datetime]$Scheduled, [datetime]$Now, [double]$IntervalSeconds) }   # -> @{ Next = [datetime]; Skipped = [int] }
function Test-WorkerPerfGuard { param([double]$FreeMB, [double]$SizeMB, [double]$MaxSizeMB, [ValidateSet('start', 'run')][string]$Phase) }   # -> $null|'diskspace'|'maxsize'
function ConvertTo-WorkerPerfFastRows { param($Sample, [int]$T, [double]$ElapsedSec, [bool]$Burst, [double]$CollectMs) }
#   -> @{ Tick = [string]; Volumes = [string[]]; Shares = [string[]]; InputSessions = [string[]]; InputProcesses = [string[]] }
function New-WorkerPerfWriters { param([string]$RunDir) }    # -> Hashtable Dateiname -> StreamWriter, Kopfzeile geschrieben
```

Der schnelle Messwert `Sample` (von der Datenquelle, Task 7 und 15): `Time`, `CpuPct`, `ProcQueue`, `StealPct`, `MemAvailMB`, `MemCommittedMB`, `MemCommitLimitMB`, `PagesInPerSec`, `DiskReadBps`, `DiskWriteBps`, `DiskReadIops`, `DiskWriteIops`, `DiskQueue`, `NetRecvBps`, `NetSentBps` (jeweils Zahl oder `$null`), `Volumes` (`Volume`, `Kind`, `SessionId`, `Backing`, `ReadLatMs`, `WriteLatMs`, `ReadOps`, `WriteOps`, `ReadBps`, `WriteBps`, `Queue`; `Backing` ist bei Profilcontainern die Freigabe `\\server\share` hinter dem Container, sonst leer), `Shares` (`Share`, `ReadLatMs`, `WriteLatMs`, `ReadOps`, `WriteOps`, `ReadBps`, `WriteBps`), `InputSessions` (`SessionId`, `DelayMs`), `InputProcesses` (`SessionId`, `Pid`, `Name`, `DelayMs`). `ReadOps`/`WriteOps` sind Anzahlen im Takt.

- [ ] **Step 1: Den fehlschlagenden Test schreiben**

```powershell
BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Capture.ps1')
    $script:Th = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json')
    $script:t = [datetime]'2026-01-15T08:00:00'
    function New-TestVolume([string]$Name, $ReadLat, [double]$ReadOps) {
        [pscustomobject]@{ Volume = $Name; Kind = 'disk'; SessionId = $null; Backing = ''; ReadLatMs = $ReadLat; WriteLatMs = $null; ReadOps = $ReadOps; WriteOps = 0; ReadBps = 5000; WriteBps = 0; Queue = 1 }
    }
    $script:Sample = [pscustomobject]@{
        Time = [datetime]'2026-01-15T08:00:02'; CpuPct = 12.5; ProcQueue = 3; StealPct = $null; MemAvailMB = 20000.4; MemCommittedMB = 30000; MemCommitLimitMB = 70000
        PagesInPerSec = 1.26; DiskReadBps = 1000; DiskWriteBps = 2000; DiskReadIops = 10.5; DiskWriteIops = 20; DiskQueue = 0; NetRecvBps = 300; NetSentBps = 400
        Volumes = @((New-TestVolume 'C:' 2.347 12), (New-TestVolume 'D:' $null 0)); Shares = @()
        InputSessions = @([pscustomobject]@{ SessionId = 5; DelayMs = 0 }, [pscustomobject]@{ SessionId = 6; DelayMs = 300 })
        InputProcesses = @([pscustomobject]@{ SessionId = 6; Pid = 100; Name = 'a.exe'; DelayMs = 30 }, [pscustomobject]@{ SessionId = 6; Pid = 200; Name = 'b.exe'; DelayMs = 80 })
    }
}
Describe 'Update-WorkerPerfBurstState' {
    It 'bleibt 60 Sekunden nach dem letzten Ausloeser aktiv' {
        $s = New-WorkerPerfBurstState
        Update-WorkerPerfBurstState -State $s -Now $t -BadSignals @('cpu.host') | Should -BeTrue
        Update-WorkerPerfBurstState -State $s -Now $t.AddSeconds(60) -BadSignals @() | Should -BeTrue
        Update-WorkerPerfBurstState -State $s -Now $t.AddSeconds(62) -BadSignals @() | Should -BeFalse
    }
    It 'begrenzt die Verdichtung bei dauerhaft ueberschrittener Schwelle' {     # Review Focus 1
        $s = New-WorkerPerfBurstState
        $active = foreach ($i in 0..299) { Update-WorkerPerfBurstState -State $s -Now $t.AddSeconds(2 * $i) -BadSignals @('mem.used') }
        @($active | Where-Object { $_ }).Count | Should -Be 181              # 151 Takte bis 300 s, danach 30 Takte Nachlauf
        Update-WorkerPerfBurstState -State $s -Now $t.AddSeconds(600) -BadSignals @() | Should -BeFalse
        Update-WorkerPerfBurstState -State $s -Now $t.AddSeconds(602) -BadSignals @('mem.used') | Should -BeTrue      # nach Entwarnung wieder scharf
    }
    It 'fuehrt die Begrenzung je Signal' {
        $s = New-WorkerPerfBurstState
        foreach ($i in 0..199) { [void](Update-WorkerPerfBurstState -State $s -Now $t.AddSeconds(2 * $i) -BadSignals @('mem.used')) }
        Update-WorkerPerfBurstState -State $s -Now $t.AddSeconds(400) -BadSignals @('mem.used', 'cpu.host') | Should -BeTrue
    }
}
Describe 'Zeitplan' {
    It 'laesst ausgefallene Takte aus, statt sie nachzuholen' {
        $r = Get-WorkerPerfNextTick -Scheduled $t.AddSeconds(2) -Now $t.AddSeconds(7.5) -IntervalSeconds 2
        $r.Next | Should -Be $t.AddSeconds(8); $r.Skipped | Should -Be 2
        (Get-WorkerPerfNextTick -Scheduled $t.AddSeconds(2) -Now $t.AddSeconds(2.3) -IntervalSeconds 2).Skipped | Should -Be 0
    }
    It 'waehlt den regulaeren Schnappschuss vor der Verdichtung' {
        Get-WorkerPerfSnapshotDue -Now $t.AddSeconds(15) -NextRegular $t.AddSeconds(15) -LastSnapshot $t -BurstActive $true | Should -Be 'regular'
        Get-WorkerPerfSnapshotDue -Now $t.AddSeconds(6) -NextRegular $t.AddSeconds(15) -LastSnapshot $t -BurstActive $true | Should -Be 'burst'
        Get-WorkerPerfSnapshotDue -Now $t.AddSeconds(4) -NextRegular $t.AddSeconds(15) -LastSnapshot $t -BurstActive $true | Should -Be 'none'
        Get-WorkerPerfSnapshotDue -Now $t.AddSeconds(6) -NextRegular $t.AddSeconds(15) -LastSnapshot $t -BurstActive $false | Should -Be 'none'
    }
}
Describe 'Test-WorkerPerfGuard' {
    It 'bricht bei knappem Platz und an der Obergrenze ab' {
        Test-WorkerPerfGuard -FreeMB 150 -SizeMB 0 -MaxSizeMB 500 -Phase start 3>$null | Should -Be 'diskspace'
        $out = @(Test-WorkerPerfGuard -FreeMB 500 -SizeMB 0 -MaxSizeMB 500 -Phase start 3>&1)      # nur eine Warnung, kein Abbruchgrund
        @($out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 1
        @($out | Where-Object { $_ -is [string] }).Count | Should -Be 0
        Test-WorkerPerfGuard -FreeMB 5000 -SizeMB 500 -MaxSizeMB 500 -Phase run | Should -Be 'maxsize'
        Test-WorkerPerfGuard -FreeMB 199 -SizeMB 10 -MaxSizeMB 500 -Phase run | Should -Be 'diskspace'
        Test-WorkerPerfGuard -FreeMB 5000 -SizeMB 10 -MaxSizeMB 500 -Phase run | Should -BeNullOrEmpty
    }
}
Describe 'ConvertTo-WorkerPerfFastRows' {
    It 'schreibt den Takt und nur Instanzen mit Aktivitaet' {                   # Review Focus 2
        [cultureinfo]::CurrentCulture = [cultureinfo]'de-DE'
        $r = ConvertTo-WorkerPerfFastRows -Sample $Sample -T 7 -ElapsedSec 2 -Burst $true -CollectMs 41.6
        $r.Tick | Should -Be '7,2026-01-15T08:00:02.0000000,2,12.5,3,,20000,30000,70000,1.3,1000,2000,10.5,20,0,300,400,1,42'
        $r.Volumes | Should -Be @('7,C:,disk,,,2.35,,12,0,5000,0,1')
        $r.Shares.Count | Should -Be 0
        $r.InputSessions | Should -Be @('7,6,300'); $r.InputProcesses | Should -Be @('7,6,200,b.exe,80')
    }
}
Describe 'Get-WorkerPerfTriggerSignals' {
    It 'meldet nur Ausloeser ueber der Schwelle und beachtet minOps' {
        Get-WorkerPerfTriggerSignals -Sample $Sample -Thresholds $Th -LogicalProcessors 8 -PhysicalMemoryMB 65536 | Should -Be @('input.session')
        $busy = $Sample.PSObject.Copy(); $busy.CpuPct = 80; $busy.MemAvailMB = 6000; $busy.Volumes = @(New-TestVolume 'C:' 30 2)
        Get-WorkerPerfTriggerSignals -Sample $busy -Thresholds $Th -LogicalProcessors 8 -PhysicalMemoryMB 65536 | Should -Be @('cpu.host', 'mem.used', 'input.session')
        $busy.Volumes = @(New-TestVolume 'C:' 30 20)
        Get-WorkerPerfTriggerSignals -Sample $busy -Thresholds $Th -LogicalProcessors 8 -PhysicalMemoryMB 65536 | Should -Contain 'disk.latency'
    }
}
Describe 'New-WorkerPerfWriters' {
    It 'legt alle Dateien mit Kopfzeile ohne BOM an' {
        $dir = Join-Path $TestDrive 'w'; [void](New-Item -ItemType Directory $dir)
        $w = New-WorkerPerfWriters -RunDir $dir; foreach ($x in $w.Values) { $x.Dispose() }
        $w.Count | Should -Be 13
        [IO.File]::ReadAllBytes((Join-Path $dir 'ticks.csv'))[0] | Should -Be ([byte][char]'T')
    }
}
```

- [ ] **Step 2: Test ausführen und Fehlschlag prüfen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Schedule.Tests.ps1`
Expected: FAIL, `New-WorkerPerfBurstState` nicht definiert

- [ ] **Step 3: Die Funktionen implementieren**

- **Verdichtung:** je Signal die Zustände „scharf" und „Episodenbeginn". Ein auffälliges Signal löst aus, wenn es scharf ist (dann beginnt die Episode und es wird entschärft) oder seine Episode höchstens `MaxEpisodeSeconds` alt ist. Ein Signal, das nicht in `BadSignals` steht, wird wieder scharf. Die Verdichtung ist aktiv, solange der letzte Auslöser höchstens `HoldSeconds` zurückliegt (Grenzen einschließlich).
- **Auslöser-Signale:** nur Schwellwerte mit `trigger`. Host-Signale über `Get-WorkerPerfHostSignals`; `input.session` ist das Maximum über `InputSessions`; `disk.latency` und `smb.latency` sind das Maximum von Lese- und Schreib-Antwortzeit über die Instanzen, deren Zugriffe (`ReadOps + WriteOps`) `minOps` erreichen.
- **Schnappschuss fällig:** `regular`, wenn `Now >= NextRegular`; sonst `burst`, wenn die Verdichtung aktiv ist und seit `LastSnapshot` mindestens `BurstIntervalSeconds` vergangen sind.
- **Nächster Takt:** `Scheduled + Intervall`; liegt das nicht nach `Now`, der nächste Rasterpunkt nach `Now`. `Skipped` zählt die ausgelassenen Rasterpunkte.
- **Schutzgrenzen:** `diskspace` unter 200 MB frei; in der Phase `start` zusätzlich eine Warnung unter 1024 MB; `maxsize`, wenn `SizeMB >= MaxSizeMB`.
- **Schnelle Zeilen:** Nachkommastellen: `ElapsedSec` 3, `CpuPct` und `StealPct` 2, `PagesInPerSec` und IOPS 1, Antwortzeiten 2, alles andere 0; Zeit als `ToString('o')`. Laufwerke und Freigaben nur mit `ReadOps + WriteOps > 0`, Sitzungen nur mit `DelayMs > 0`, Prozesse nur ab 50 ms.

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Schedule.Tests.ps1,tests/Capture.Tests.ps1,tests/Compat.Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Capture.ps1 tests/Schedule.Tests.ps1
git commit -m "Add burst control, scheduling, guards and fast row format"
```

---

### Task 7: Datenquelle Simulation mit Drehbuch

**Files:**
- Create: `src/WorkerPerf.Sources.Simulation.ps1`
- Test: `tests/Simulation.Tests.ps1`

**Interfaces:**
- Produces – dieselben Funktionsnamen stellt später die Windows-Datenquelle bereit (Task 15):

```powershell
function Initialize-WorkerPerfSource { param([datetime]$StartTime, [object[]]$Endpoints = @(), [string]$CitrixMetricFilter = '', [switch]$IncludeCommandLine, [switch]$NoCitrix) }
#   -> @{ Computer; OS; LogicalProcessors; PhysicalMemoryMB; CollectorPid; Endpoints [object[]]; Sources [ordered] id -> @{ Available; Detail } }
function Get-WorkerPerfNow                                   # -> [datetime]
function Wait-WorkerPerfTick { param([datetime]$Until, [string]$StopFlagPath) }   # -> [bool], $true bei Stopp-Wunsch
function Get-WorkerPerfFastSample                            # -> schneller Messwert (Task 6)
function Get-WorkerPerfSnapshot                              # -> @{ Time; Processes; Sessions; Citrix }
function Get-WorkerPerfServices                              # -> Hashtable PID -> 'Dienst1;Dienst2'
function Start-WorkerPerfProbes { param([object[]]$Endpoints) }   # startet die Proben; ohne Angabe zu den bei der Initialisierung gemerkten Gegenstellen
function Receive-WorkerPerfProbes                            # -> $null solange offen, sonst Objekte mit Name, Role, Host, Port, ConnectMs, Error
function Get-WorkerPerfEvents { param([datetime]$Since) }    # -> Objekte mit Time, Source, EventId, Kind, Text (Since < Time <= jetzt)
function Get-WorkerPerfFreeSpaceMB { param([string]$Path) }  # -> [double]
function Get-WorkerPerfExpected                              # nur Simulation: Soll-Ergebnis
```

`Sessions`: `SessionId`, `State`, `WinStation`, `User`, `Domain`, `ClientName`, `LogonTime` (`[datetime]`, `MinValue` = unbekannt), `IdleSec` (-1 = unbekannt). `Citrix`: `Source`, `SessionId`, `Instance`, `Metric`, `Value`. `Sources` enthält die zwölf Signal-Kennungen sowie `process`, `sessions`, `input.process`, `profile.map`, `events.defender`, `events.applocker`.

Feste Eckdaten: Computer `SIM-VDA01`, Betriebssystem `Simulated Windows Server 2022`, 8 logische Prozessoren, 65536 MB RAM, Domäne `CONTOSO`. 25 Sitzungen `user001`…`user025` mit den Sitzungs-IDs 2…26, alle vor Messbeginn angemeldet und aktiv; Sitzung 0 für Dienste. Je Benutzersitzung zehn Prozesse (`explorer.exe`, `nexus.exe`, viermal `chrome.exe`, `OUTLOOK.EXE`, `WINWORD.EXE`, `EXCEL.EXE`, `ms-teams.exe`), in Sitzung 0 rund 30 (darunter `MsMpEng.exe`, ein `svchost.exe` mit Dienst `AppIDSvc`, `BrokerAgent.exe` und `powershell.exe` mit PID 4242 als Collector). Laufwerke `C:`, `D:` und je Sitzung ein Profilcontainer `HarddiskVolume<Sitzungs-ID + 8>` (Kind `profile`, `Backing` `\\fs01\profile$`, in der Grundlast etwa in jedem zehnten Takt mit Zugriffen); Freigaben `\\fs01\daten`, `\\fs01\profile$`. Gegenstellen (unabhängig von `-Endpoints`): `Oracle-Listener` (`ora01.sim.local`, 1521, `Datenbank`), `FortiGate-Proxy` (`proxy.sim.local`, 8080, `Proxy`), `Dateiserver` (`fs01.sim.local`, 445, `Dateiserver`). Citrix-Werte `RoundtripTime` und `NetworkLatency` (60 % davon) aus Quelle `Citrix_Euem_RoundTrip`.

Grundlast, jeweils unter allen Schwellen: CPU 30–40 %, RAM-Auslastung 55–60 %, Commit unter 70 %, Warteschlange unter 1 je CPU, entzogene CPU-Zeit unter 1 %, gelesene Seiten unter 5 je Sekunde, Eingabeverzögerung 0–40 ms, Antwortzeiten 1–5 ms, Proben 2–8 ms, ICA Round Trip 20–60 ms. Mindestens die Hälfte der Prozesse verbraucht außerhalb der Vorfälle weder CPU noch I/O.

Drehbuch – ein Fenster a–b gilt für Zeitpunkte t mit a < t ≤ b (Minuten:Sekunden nach Messbeginn):

| Key | Fenster | Signale im Fenster | Verursacher | Soll-Ergebnis |
|---|---|---|---|---|
| `homeoffice` | 00:00–60:00 | ICA Round Trip von user020: 220 ms | – | `umfeld`, Dauerzustand, 0 Betroffene |
| `cpu` | 05:00–07:00 | CPU 96 %, Warteschlange 24, Eingabeverzögerung 300–600 ms bei user001–user006 | `EXCEL.EXE` von user003 mit 60 % der Host-CPU | `engpass`, Lead `cpu`, `EXCEL.EXE`/user003, 6 Betroffene |
| `memory` | 15:00–19:00 | RAM-Auslastung steigt bis 16:00 linear auf 93 % und bleibt dort; ab 15:30 gelesene Seiten 400/s; ab 16:00 `C:` Schreib-Antwortzeit 15 ms bei 300 Zugriffen je Takt; Eingabeverzögerung 200–400 ms bei user007–user010 | `ms-teams.exe` von user007 wächst entsprechend und wird um 19:00 neu gestartet | `engpass`, Lead `memory`, `ms-teams.exe`/user007, 4 Betroffene |
| `disk` | 25:00–26:30 | `D:` Schreib-Antwortzeit 60 ms bei 200 Zugriffen je Takt, Eingabeverzögerung 250 ms bei user011 | `robocopy.exe` von user011 (läuft nur im Fenster) mit 80 MB/s; `MsMpEng.exe` mit 30 MB/s und 8 % CPU | `engpass`, Lead `disk`, `robocopy.exe`/user011, Begleiter `Microsoft Defender`, 1 Betroffener |
| `share` | 33:00–34:00 | `\\fs01\daten` Lese-Antwortzeit 80 ms bei 100 Zugriffen je Takt, Eingabeverzögerung 300 ms bei user005 | `WINWORD.EXE` von user005 mit 20 MB/s | `engpass`, Lead `share`, `WINWORD.EXE`/user005, 1 Betroffener |
| `profile` | 40:00–41:00 | Profilcontainer von user009 (`HarddiskVolume18`) Antwortzeit 45 ms bei 50 Zugriffen je Takt, Eingabeverzögerung 400 ms bei user009 | `OUTLOOK.EXE` von user009 mit 10 MB/s | `engpass`, Lead `profile`, `OUTLOOK.EXE`/user009, 1 Betroffener |
| `backend` | 47:00–48:30 | Eingabeverzögerung 1200 ms in `nexus.exe` bei user012–user019, Probe `Oracle-Listener` 350 ms | – | `ohne-engpass`, 8 Betroffene, höchste Verzögerung `nexus.exe`, Gegenstelle `Oracle-Listener` |
| `hang` | 52:58–53:00 | Eingabeverzögerung 800 ms bei user014 in einem einzigen Takt | – | `ohne-engpass`, 1 Betroffener |

Ereignisse: 24:50 Defender 1000 (`scan-start`), 27:00 Defender 1001 (`scan-end`), 30:00 AppLocker 8004 (`applocker-block`).

`Get-WorkerPerfExpected` liefert je Zeile ein Objekt mit `Key`, `Type`, `Lead`, `Chronic`, `StartMs`, `EndMs` (Epochen-Millisekunden), `MainApp`, `MainUser`, `Affected`, `DelayApp`, `Endpoint`, `Companion`, nach `StartMs` sortiert.

- [ ] **Step 1: Den fehlschlagenden Test schreiben**

```powershell
BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Sources.Simulation.ps1')
    $script:Start = [datetime]'2026-01-15T08:00:00'
    $script:Info = Initialize-WorkerPerfSource -StartTime $Start
    function Set-SimTime([double]$Minutes) { [void](Wait-WorkerPerfTick -Until $Start.AddMinutes($Minutes) -StopFlagPath '') }
    function Get-SimProcess([string]$Name, [int]$SessionId) { , @((Get-WorkerPerfSnapshot).Processes | Where-Object { $_.Name -eq $Name -and ($SessionId -lt 0 -or $_.SessionId -eq $SessionId) }) }
    function Get-CpuSec($p) { ([double]$p.UserModeTime + [double]$p.KernelModeTime) / 1e7 }
}
Describe 'Simulation' {
    It 'meldet die festen Eckdaten' {
        $Info.Computer | Should -Be 'SIM-VDA01'; $Info.LogicalProcessors | Should -Be 8; $Info.PhysicalMemoryMB | Should -Be 65536; $Info.CollectorPid | Should -Be 4242
        @($Info.Endpoints).Name | Should -Be @('Oracle-Listener', 'FortiGate-Proxy', 'Dateiserver')
        @($Info.Sources.Values | Where-Object { -not $_.Available }).Count | Should -Be 0
    }
    It 'liefert zu gleicher Zeit gleiche Werte, auch nach Spruengen der Uhr' {
        Set-SimTime 6; $a = (Get-WorkerPerfFastSample).CpuPct
        Set-SimTime 30; Set-SimTime 6; (Get-WorkerPerfFastSample).CpuPct | Should -Be $a
        Get-WorkerPerfNow | Should -Be $Start.AddMinutes(6)
    }
    It 'bleibt in ruhigen Phasen unter allen Schwellen' {
        foreach ($m in 10, 11.5, 13, 22, 44, 57) {
            Set-SimTime $m; $f = Get-WorkerPerfFastSample
            $f.CpuPct | Should -BeLessThan 75; (1 - $f.MemAvailMB / 65536) * 100 | Should -BeLessThan 75
            $f.ProcQueue | Should -BeLessThan 16; $f.PagesInPerSec | Should -BeLessThan 10
            @($f.InputSessions | Where-Object { $_.DelayMs -ge 150 }).Count | Should -Be 0
            @($f.Volumes | Where-Object { $_.ReadLatMs -ge 10 -or $_.WriteLatMs -ge 10 }).Count | Should -Be 0
            @($f.Shares | Where-Object { $_.ReadLatMs -ge 10 -or $_.WriteLatMs -ge 10 }).Count | Should -Be 0
        }
    }
    It 'spielt den CPU-Engpass' {
        Set-SimTime 6; $f = Get-WorkerPerfFastSample
        $f.CpuPct | Should -BeGreaterOrEqual 90
        @($f.InputSessions | Where-Object { $_.DelayMs -ge 150 }).SessionId | Sort-Object | Should -Be @(2, 3, 4, 5, 6, 7)
        Set-SimTime 5; $a = Get-CpuSec (Get-SimProcess 'EXCEL.EXE' 4)[0]
        Set-SimTime 7; (Get-CpuSec (Get-SimProcess 'EXCEL.EXE' 4)[0]) - $a | Should -BeGreaterThan 560     # 60 % von 8 Kernen ueber 120 s
    }
    It 'laesst robocopy nur im Datentraeger-Fenster laufen' {
        Set-SimTime 24.75; (Get-SimProcess 'robocopy.exe' -1).Count | Should -Be 0
        Set-SimTime 25.5; $p = Get-SimProcess 'robocopy.exe' -1; $p.Count | Should -Be 1; $p[0].SessionId | Should -Be 12
        Set-SimTime 27; (Get-SimProcess 'robocopy.exe' -1).Count | Should -Be 0
    }
    It 'haelt die Mehrheit der Prozesse in Ruhe' {
        Set-SimTime 10; $a = @{}; foreach ($p in (Get-WorkerPerfSnapshot).Processes) { $a[$p.ProcessId] = $p }
        Set-SimTime 10.25; $b = @((Get-WorkerPerfSnapshot).Processes)
        $idle = @($b | Where-Object { $a.ContainsKey($_.ProcessId) -and (Get-CpuSec $_) -eq (Get-CpuSec $a[$_.ProcessId]) -and $_.ReadTransferCount -eq $a[$_.ProcessId].ReadTransferCount })
        $idle.Count | Should -BeGreaterThan ($b.Count / 2)
    }
    It 'kennzeichnet Profilcontainer und Dienste' {
        Set-SimTime 40.5; $v = (Get-WorkerPerfFastSample).Volumes | Where-Object Volume -eq 'HarddiskVolume18'
        $v.Kind | Should -Be 'profile'; $v.SessionId | Should -Be 10; $v.Backing | Should -Be '\\fs01\profile$'
        (Get-WorkerPerfServices).Values | Should -Contain 'AppIDSvc'
    }
    It 'meldet Proben erst im naechsten Takt' {
        Set-SimTime 47.5; Start-WorkerPerfProbes; Receive-WorkerPerfProbes | Should -BeNullOrEmpty
        Set-SimTime (47.5 + 2 / 60); $r = @(Receive-WorkerPerfProbes)
        $r.Count | Should -Be 3; ($r | Where-Object Name -eq 'Oracle-Listener').ConnectMs | Should -BeGreaterOrEqual 200
    }
    It 'liefert Ereignisse seit einem Zeitpunkt' {
        Set-SimTime 31; @(Get-WorkerPerfEvents -Since $Start).Kind | Should -Be @('scan-start', 'scan-end', 'applocker-block')
        @(Get-WorkerPerfEvents -Since $Start.AddMinutes(28)).Kind | Should -Be @('applocker-block')
    }
    It 'beschreibt das Soll-Ergebnis' {
        $e = @(Get-WorkerPerfExpected)
        $e.Key | Should -Be @('homeoffice', 'cpu', 'memory', 'disk', 'share', 'profile', 'backend', 'hang')
        $cpu = $e | Where-Object Key -eq 'cpu'
        $cpu.MainUser | Should -Be 'user003'; $cpu.EndMs - $cpu.StartMs | Should -Be 120000; $cpu.Affected | Should -Be 6
        @($e | Where-Object Chronic).Count | Should -Be 1
    }
}
```

- [ ] **Step 2: Test ausführen und Fehlschlag prüfen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Simulation.Tests.ps1`
Expected: FAIL, `WorkerPerf.Sources.Simulation.ps1` nicht gefunden

- [ ] **Step 3: Die Datenquelle implementieren**

Alle Werte sind reine Funktionen der virtuellen Zeit: Rauschen aus einem Hash von Zeit und Name statt aus einem fortlaufenden Zufallsgenerator; fortlaufende Prozesszähler als geschlossene Formel (Grundrate mal verstrichene Zeit plus Drehbuch-Anteil mal Überdeckung mit dem Fenster). `Wait-WorkerPerfTick` setzt die Uhr auf `Until` und liefert `$false`. `Receive-WorkerPerfProbes` liefert die Ergebnisse der beim Start gültigen Zeit, sobald die Uhr danach weitergestellt wurde. `Get-WorkerPerfFreeSpaceMB` liefert 100000. Die simulierten Summen müssen zusammenpassen: Die CPU-Zeit aller Prozesse entspricht der gemeldeten Host-CPU auf 5 Prozentpunkte genau.

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Simulation.Tests.ps1,tests/Compat.Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Sources.Simulation.ps1 tests/Simulation.Tests.ps1
git commit -m "Add scripted simulation source with expected incidents"
```

---

### Task 8: Collector-Einstieg

**Files:**
- Modify: `src/Start-WorkerPerfCapture.ps1` (vollständig neu)
- Create: `src/WorkerPerf.Sources.Windows.ps1`, `tests/TestHelpers.ps1`
- Modify: `README.md` (Abschnitt „Aufzeichnen"), `.gitignore`
- Test: `tests/Collector.Tests.ps1`

**Interfaces:**
- Consumes: Tasks 2, 5, 6, 7.
- Produces: `Start-WorkerPerfCapture.ps1` mit den Parametern `-OutputPath`, `-FastIntervalSeconds` (1–60, Standard 2), `-IntervalSeconds` (5–3600, Standard 15), `-BurstIntervalSeconds` (Standard 5), `-BurstHoldSeconds` (Standard 60), `-DurationMinutes` (0 = bis zum Stopp), `-MaxSizeMB` (Standard 500), `-ThresholdFile` (Standard `thresholds.json` neben dem Skript), `-EndpointFile` (Standard `endpoints.json` neben dem Skript; fehlt sie, gibt es keine Proben), `-IncludeCommandLine`, `-NoCitrix`, `-CitrixMetricFilter`, `-Simulate`. Ausgabe: der Pfad des Aufzeichnungsordners.
- Produces: Aufzeichnungsordner `<Computer>_<yyyyMMdd-HHmmss>` mit den dreizehn CSV-Dateien, einer Kopie von `thresholds.json`, `meta.json` und in der Simulation `expected.json` (Ausgabe von `Get-WorkerPerfExpected` als JSON-Array).
- Produces: `meta.json` mit `SchemaVersion` 2, `Computer`, `OS`, `LogicalProcessors`, `PhysicalMemoryMB`, `FastIntervalSeconds`, `IntervalSeconds`, `BurstIntervalSeconds`, `BurstHoldSeconds`, `MaxSizeMB`, `StartTime`, `EndTime`, `EndReason` (`duration`, `stopflag`, `interrupted`, `maxsize`, `diskspace`), `Ticks`, `Snapshots`, `SkippedTicks`, `Simulated`, `IncludeCommandLine`, `CollectorPid`, `Endpoints`, `Sources`.
- Produces: `tests/TestHelpers.ps1` mit `Invoke-SimCapture([string]$OutDir) -> [string]`.

- [ ] **Step 1: `tests/TestHelpers.ps1` und den fehlschlagenden Test schreiben**

```powershell
# tests/TestHelpers.ps1
function Invoke-SimCapture([string]$OutDir) {
    # 60 Minuten Simulation unter deutscher Kultur; liefert den Aufzeichnungsordner
    [cultureinfo]::CurrentCulture = [cultureinfo]'de-DE'
    $capture = Join-Path $PSScriptRoot '../src/Start-WorkerPerfCapture.ps1'
    (& $capture -Simulate -DurationMinutes 60 -OutputPath $OutDir 6>$null) | Select-Object -Last 1
}
```

```powershell
# tests/Collector.Tests.ps1
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
```

- [ ] **Step 2: Test ausführen und Fehlschlag prüfen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Collector.Tests.ps1`
Expected: FAIL (das bisherige Skript kennt die Dateien des Formats 2 nicht)

- [ ] **Step 3: Windows-Funktionen auslagern**

Die Windows-spezifischen Teile des bisherigen Skripts unverändert nach `src/WorkerPerf.Sources.Windows.ps1` verschieben: den C#-Text `$wtsSource` (als `$script:WorkerPerfWtsSource`) und die Funktionen `Write-WarningOnce`, `Get-CimSafe`, `Get-WinProcessRaw`, `Get-WinSessionRaw`, `Initialize-CitrixSources`, `Get-WinCitrixRaw`. Die Datei definiert in dieser Task noch keine der Funktionen aus der Schnittstelle von Task 7; das folgt in Task 15.

- [ ] **Step 4: `src/Start-WorkerPerfCapture.ps1` neu schreiben**

Ablauf:
1. `WorkerPerf.Common.ps1`, `WorkerPerf.Capture.ps1` und je nach `-Simulate` genau eine Datenquelle einbinden. Ohne `-Simulate` außerhalb von Windows: Fehler. Fehlt nach dem Einbinden `Initialize-WorkerPerfSource`, Fehler mit dem Hinweis, dass die Windows-Datenquelle noch nicht fertiggestellt ist. `-Simulate` verlangt `-DurationMinutes` von mindestens 60 (die Meldung nennt die Zahl 60).
2. Schwellwerte und Gegenstellen lesen (Fehler brechen ab), Datenquelle initialisieren, Ordner anlegen, `Test-WorkerPerfGuard -Phase start`, Writer öffnen, `thresholds.json` kopieren, `meta.json` schreiben.
3. Grundstand: einen schnellen Messwert verwerfen, einen Schnappschuss mit `P = -1` verarbeiten.
4. Je schnellem Takt: `Wait-WorkerPerfTick` (bei `$true` Ende mit `stopflag`; die Stopp-Datei heißt `stop.flag` im Aufzeichnungsordner); Messwert holen; Zeilen über `ConvertTo-WorkerPerfFastRows` schreiben; Auslöser und Verdichtung aktualisieren; `Get-WorkerPerfSnapshotDue` auswerten.
5. Bei fälligem Schnappschuss: Prozesszeilen (Stützpunkt, wenn der Zähler der regulären Schnappschüsse durch 20 teilbar ist; der erste ist einer), Sitzungen, Citrix-Werte mit dem `T` des Takts, Zeile in `snapshots.csv` (`Kind` `K`, `R` oder `B`). Nur bei regulären Schnappschüssen zusätzlich: Dienste neu lesen (an Stützpunkten), Proben starten, Ereignisse seit dem letzten Abruf schreiben, `Test-WorkerPerfGuard -Phase run`, alle Writer leeren.
6. In jedem Takt `Receive-WorkerPerfProbes` abfragen; Ergebnisse mit dem `T` schreiben, an dem die Proben gestartet wurden.
7. Nächsten Takt über `Get-WorkerPerfNextTick` bestimmen, ausgelassene Takte zählen. Ende, wenn der nächste Takt nach Messbeginn plus Dauer läge (`duration`).
8. Vor dem Ende einmal `Wait-WorkerPerfTick` um einen schnellen Takt und `Receive-WorkerPerfProbes`, damit die zuletzt gestarteten Proben nicht verloren gehen.
9. Im `finally`: Writer schließen, `meta.json` mit `EndTime`, `EndReason`, `Ticks`, `Snapshots`, `SkippedTicks` neu schreiben, in der Simulation `expected.json` schreiben. Ohne gesetzten Grund ist `EndReason` `interrupted`.

Die gesamte Zeitrechnung läuft über `Get-WorkerPerfNow`; die Messdauer eines Takts (`CollectMs`) misst eine Stoppuhr.

- [ ] **Step 5: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 6: README und `.gitignore` anpassen**

README-Abschnitt „Aufzeichnen": neue Parameter-Tabelle, die zwei Takte in zwei Sätzen, Beispielaufruf für eine Messung über vier Stunden, Hinweis auf `endpoints.example.json`, Simulationsaufruf mit `-DurationMinutes 60`. `.gitignore`: `src/endpoints.json` und `docs/vda-probe/*.json` ergänzen.

- [ ] **Step 7: Commit**

```bash
git add src/Start-WorkerPerfCapture.ps1 src/WorkerPerf.Sources.Windows.ps1 tests/TestHelpers.ps1 tests/Collector.Tests.ps1 README.md .gitignore
git commit -m "Rewrite collector entry script for the two-cadence format"
```

---

### Task 9: Datenmodell – Takte, Instanzsignale, Sitzungen

**Files:**
- Create: `src/WorkerPerf.Load.ps1`
- Test: `tests/Load.Tests.ps1`

**Interfaces:**
- Consumes: Task 2.
- Produces:

```powershell
function Import-WorkerPerfRun { param([string]$Path, [datetime]$From = [datetime]::MinValue, [datetime]$To = [datetime]::MaxValue, $Thresholds, [object[]]$Roles) }   # -> Modell
function Get-WorkerPerfSeries { param($Model, $Thresholds) }      # -> Messreihen fuer Get-WorkerPerfFindings
```

Das Modell ist eine Hashtable; alle Einträge darin sind Hashtables oder typisierte Arrays. `nT` = Zahl der Takte, `nP` = Zahl der Schnappschüsse im gewählten Zeitraum.

| Feld | Inhalt |
|---|---|
| `Meta` | Inhalt von `meta.json` plus `Cores`, `RamMB`, `OffsetMinutes` (aus dem ersten Takt), `FastSec`, `SnapSec` |
| `Sources` | `id` → `@{ Available; Detail }` |
| `Tick` | `N`, `TimeMs [long[]]`, `ElapsedSec`, `Burst [bool[]]`, `CollectMs`, `Raw` (Spaltenname → `double[]`), `Signal` (die sechs Host-Signale → `double[]`) |
| `Snap` | `N`, `TimeMs`, `ElapsedSec`, `Kind [string[]]`, `TickPos [int[]]`, `Sessions`, `ActiveSessions`, `Processes`, `RowsWritten`, `CollectMs` |
| `Sessions` | Liste: `Index`, `Sid`, `User`, `Domain`, `Client`, `Logon` (ms oder `$null`), `FirstP`, `LastP`, `SeenN`, `ActiveN`, `IdleMaxSec`, `Input [double[] nT]` (Standard 0), `Rtt`, `Latency [double[] nP]` (Standard NaN), `ProfileVolume` (Index in `Volumes` oder -1) |
| `Volumes` | Liste: `Name`, `Kind`, `SessionIndex`, `Backing`, `Label`, `ReadMs`, `WriteMs`, `Latency` (Maximum beider), `Ops` (`double[] nT`, NaN bzw. 0 ohne Zeile) |
| `Shares` | Liste: `Name`, `Label`, `ReadMs`, `WriteMs`, `Latency`, `Ops` |
| `Probes` | Liste: `Name`, `Role`, `Host`, `Port`, `Ms [double[] nP]` (NaN = keine Probe, `PositiveInfinity` = Fehler), `Error [string[]]` |
| `Events` | `TimeMs`, `Source`, `EventId`, `Kind`, `Text` |
| `Scans` | `StartMs`, `EndMs` aus gepaarten `scan-start`/`scan-end`; ohne Ende bis zum Messende |
| `InputProc` | `TickPos`, `SessionIndex`, `Pid`, `Name`, `DelayMs` als parallele Arrays (`K` folgt in Task 10) |
| `MainApp` | `Label`, `Delay [double[] nT]`: je Takt das Maximum der Zeilen aus `inputdelay_proc.csv`, deren Prozessname die Rolle `Hauptanwendung` hat; `Label` sind die Bezeichnungen der Rolleneinträge mit Prozessmustern, mit ` / ` verbunden; `$null`, wenn keine Rolle `Hauptanwendung` Prozesse nennt |
| `Citrix` | `Source`, `SessionIndex`, `Instance`, `Metric`, `Avg`, `Max`, `N` |

- [ ] **Step 1: Den fehlschlagenden Test schreiben**

```powershell
BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Load.ps1')
    $script:Th = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json')
    $script:Roles = Read-WorkerPerfRoles (Join-Path $PSScriptRoot '../src/roles.json')
    $script:Base = [DateTimeOffset]'2026-01-15T08:00:00+01:00'
    function Get-Ts([double]$Sec) { $Base.AddSeconds($Sec).ToString('o') }
    function New-TickLine([int]$T, [double]$Cpu = 50) { "$T,$(Get-Ts (2 * ($T + 1))),2,$Cpu,8,,4096,8000,20000,0,0,0,0,0,0,0,0,0,5" }
    function New-SnapLine([int]$P, [string]$Kind = 'R') { "$P,$(2 * $P + 1),$(Get-Ts (4 * ($P + 1))),4,$Kind,1,1,3,3,20" }
    function Write-TestRun([string]$Name, [hashtable]$Files) {
        $dir = Join-Path $TestDrive $Name; [void](New-Item -ItemType Directory -Path $dir -Force)
        foreach ($f in $WorkerPerfHeaders.Keys) {
            if ($Files.ContainsKey($f) -and $null -eq $Files[$f]) { continue }             # $null = die Datei fehlt
            [IO.File]::WriteAllLines((Join-Path $dir $f), [string[]](@($WorkerPerfHeaders[$f]) + @($Files[$f] | Where-Object { $_ })))
        }
        $meta = '{"SchemaVersion":2,"Computer":"T1","OS":"x","LogicalProcessors":4,"PhysicalMemoryMB":16384,"FastIntervalSeconds":2,"IntervalSeconds":4,"StartTime":"' + (Get-Ts 0) +
            '","EndTime":null,"CollectorPid":4242,"Simulated":false,"Endpoints":[{"Name":"DB","Host":"h","Port":1521,"Role":"Datenbank"}],' +
            '"Sources":{"cpu.host":{"Available":true,"Detail":""},"cpu.steal":{"Available":false,"Detail":"VM Processor fehlt"}}}'
        [IO.File]::WriteAllText((Join-Path $dir 'meta.json'), $meta); $dir
    }
    function Import-TestRun([string]$Name, [hashtable]$Files, [hashtable]$Extra = @{}) { Import-WorkerPerfRun -Path (Write-TestRun $Name $Files) -Thresholds $Th -Roles $Roles @Extra }
    # Grundgeruest: 8 Takte bei 2, 4, ... 16 s; 4 Schnappschuesse bei 4, 8, 12, 16 s (Schnappschuss P liegt auf Takt 2P + 1)
    $script:Ticks = 0..7 | ForEach-Object { New-TickLine $_ }
    $script:SnapLines = 0..3 | ForEach-Object { New-SnapLine $_ $(if ($_ -eq 0) { 'K' } else { 'R' }) }
}
Describe 'Import-WorkerPerfRun: Takte' {
    It 'liest Takte und leitet Signale ab' {
        $m = Import-TestRun 'a' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }
        $m.Tick.N | Should -Be 8; $m.Snap.N | Should -Be 4; $m.Meta.Cores | Should -Be 4; $m.Meta.OffsetMinutes | Should -Be 60
        $m.Tick.Signal['mem.used'][0] | Should -Be 75; $m.Tick.Signal['cpu.queue'][0] | Should -Be 2
        [double]::IsNaN($m.Tick.Signal['cpu.steal'][0]) | Should -BeTrue
        $m.Snap.TickPos | Should -Be @(1, 3, 5, 7); $m.Snap.Kind[0] | Should -Be 'K'
    }
    It 'uebergeht eine abgeschnittene letzte Zeile und ein fehlendes Ende' {     # Review Focus 3
        $m = Import-TestRun 'b' @{ 'ticks.csv' = (@($Ticks) + '8,2026-01-15T08:00:18.0000000+01:00,2,5'); 'snapshots.csv' = (@($SnapLines) + '4,9,2026-01-15T08') }
        $m.Tick.N | Should -Be 8; $m.Snap.N | Should -Be 4
    }
    It 'kommt ohne optionale Dateien aus' {
        $m = Import-TestRun 'c' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'shares.csv' = $null; 'probes.csv' = $null; 'events.csv' = $null; 'citrix.csv' = $null; 'inputdelay_proc.csv' = $null }
        @($m.Shares).Count | Should -Be 0; @($m.Probes).Count | Should -Be 0; @($m.Events).Count | Should -Be 0
    }
    It 'schneidet auf -From und -To zu' {
        $m = Import-TestRun 'd' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines } @{ From = $Base.AddSeconds(7).LocalDateTime; To = $Base.AddSeconds(13).LocalDateTime }
        $m.Tick.N | Should -Be 3; $m.Snap.N | Should -Be 2
    }
    It 'meldet eine Aufzeichnung ohne Schnappschuss verstaendlich' { { Import-TestRun 'e' @{ 'ticks.csv' = $Ticks } } | Should -Throw '*Schnappschuss*' }
}
Describe 'Import-WorkerPerfRun: Sitzungen und Instanzen' {
    BeforeAll {
        $script:Umlaut = "M$([char]0xFC)ller, K"
        $script:M = Import-TestRun 's' @{
            'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines
            'sessions.csv' = @('0,5,alice,DOM,Active,ICA#5,PC1,,0', '1,5,alice,DOM,Active,ICA#5,PC1,,0', "3,5,`"$Umlaut`",DOM,Active,ICA#5,PC2,,0")
            'inputdelay.csv' = @('1,5,300', '7,5,900')
            'volumes.csv' = @('2,C:,disk,,,2.5,12.5,10,20,0,0,0', '2,HarddiskVolume9,profile,5,\\fs01\upm$,40,,30,0,0,0,0')
            'probes.csv' = @('1,DB,Datenbank,h,1521,12.5,', '5,DB,Datenbank,h,1521,,timeout')
            'events.csv' = @("$(Get-Ts 5),Defender,1000,scan-start,Scan", "$(Get-Ts 9),Defender,1001,scan-end,Scan", "$(Get-Ts 11),AppLocker,8004,applocker-block,x.exe")
            'citrix.csv' = @('1,Citrix_Euem_RoundTrip,5,,RoundtripTime,180', '3,Citrix_Euem_RoundTrip,5,,RoundtripTime,220')
        }
    }
    It 'trennt wiederverwendete Sitzungs-IDs und erhaelt Umlaute' {             # Review Focus 2 und 4
        $M.Sessions.Count | Should -Be 2
        $M.Sessions[0].User | Should -Be 'alice'; $M.Sessions[1].User | Should -Be $Umlaut
        $M.Sessions[0].Input[1] | Should -Be 300; $M.Sessions[0].Input[7] | Should -Be 0; $M.Sessions[1].Input[7] | Should -Be 900
    }
    It 'ordnet Laufwerke und Profilcontainer zu' {
        $c = $M.Volumes | Where-Object Name -eq 'C:'; $p = $M.Volumes | Where-Object Name -eq 'HarddiskVolume9'
        $c.Latency[2] | Should -Be 12.5; $c.Ops[2] | Should -Be 30; [double]::IsNaN($c.Latency[3]) | Should -BeTrue
        $p.Kind | Should -Be 'profile'; $p.SessionIndex | Should -Be 0; $p.Latency[2] | Should -Be 40; $p.Backing | Should -Be '\\fs01\upm$'
        $M.Sessions[0].ProfileVolume | Should -BeGreaterOrEqual 0
    }
    It 'liest Proben, Ereignisse und ICA-Werte' {
        $M.Probes[0].Ms[0] | Should -Be 12.5; [double]::IsPositiveInfinity($M.Probes[0].Ms[2]) | Should -BeTrue; [double]::IsNaN($M.Probes[0].Ms[1]) | Should -BeTrue
        $M.Events.Count | Should -Be 3; $M.Scans.Count | Should -Be 1; $M.Scans[0].EndMs - $M.Scans[0].StartMs | Should -Be 4000
        $M.Sessions[0].Rtt[0] | Should -Be 180; $M.Sessions[0].Rtt[1] | Should -Be 220
    }
    It 'bildet Messreihen fuer die Befund-Logik' {
        $s = @(Get-WorkerPerfSeries -Model $M -Thresholds $Th)
        @($s | Where-Object Id -eq 'cpu.host').Count | Should -Be 1
        @($s | Where-Object Id -eq 'cpu.steal').Count | Should -Be 0                 # ohne bewertbaren Punkt keine Reihe
        $in = @($s | Where-Object Id -eq 'input.session'); $in.Count | Should -Be 2
        $in[0].Resource | Should -Be 'input'; $in[0].Scope | Should -Be 'session'; $in[0].SessionIndex | Should -Be 0
        ($s | Where-Object { $_.Id -eq 'disk.latency' -and $_.Instance -eq 'HarddiskVolume9' }).Resource | Should -Be 'profile'
        ($s | Where-Object { $_.Id -eq 'disk.latency' -and $_.Instance -eq 'C:' }).Scope | Should -Be 'global'
        ($s | Where-Object Id -eq 'probe.connect').TimeMs.Length | Should -Be 2       # nur Messpunkte mit Probe
        ($s | Where-Object Id -eq 'ica.rtt').Resource | Should -Be 'network'
    }
}
```

- [ ] **Step 2: Test ausführen und Fehlschlag prüfen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Load.Tests.ps1`
Expected: FAIL, `WorkerPerf.Load.ps1` nicht gefunden

- [ ] **Step 3: `Import-WorkerPerfRun` (ohne Prozessdaten) und `Get-WorkerPerfSeries` implementieren**

- Dateien zeilenweise mit `StreamReader` und `Split-WorkerPerfCsvLine` lesen; Zeilen mit zu wenig Feldern und nicht lesbare Zahlen überspringen; fehlende optionale Dateien wie leere behandeln. Ohne Takte oder ohne Schnappschuss im Zeitraum: Fehler, dessen Text das Wort `Schnappschuss` bzw. `Messung` enthält.
- Zeiten stammen aus `ticks.csv` und `snapshots.csv` über `[DateTimeOffset]::Parse(…, InvariantCulture)`. `StartTime` und `EndTime` aus `meta.json` nicht auswerten: PowerShell 7 wandelt sie beim Einlesen in Datumswerte, Windows PowerShell 5.1 nicht.
- Sitzungen wie im bestehenden Berichtsskript (`New-SessionEntity`): Eine Sitzungs-ID bekommt eine neue Sitzung, wenn sie einen Schnappschuss lang fehlte oder der Benutzer wechselt; Sitzung 0 ist immer eine Sitzung.
- Zeilen mit `T` und Sitzungs-ID (Eingabeverzögerung, Laufwerke mit Sitzung) gehören zur Sitzung des ersten Schnappschusses ab dem Zeitpunkt des Takts, ersatzweise des vorhergehenden; ohne Treffer zu einer Ersatzsitzung für diese ID.
- Zeilen mit `T` für Proben und Citrix-Werte gehören zum Schnappschuss mit diesem `T`, ersatzweise zum ersten mit größerem `T`.
- `Sessions[].Rtt` nimmt den ersten vorhandenen Messwert aus `RoundtripTime`; `Latency` den ersten aus `NetworkLatency`, `Latency - Last Recorded`, `LatencyLastRecorded`.
- Messreihen: Host-Signale auf dem Takt-Raster; `input.session` je Sitzung mit mindestens einem Wert über 0 (`Resource` `input`, `Scope` `session`); `disk.latency` je Laufwerk mit `Ops` (`Resource` `disk`, bei `Kind` `profile` `Resource` `profile` und `Scope` `session`); `smb.latency` je Freigabe (`share`); `ica.rtt` und `ica.latency` je Sitzung (`network`, `session`) und `probe.connect` je Gegenstelle (`endpoint`) nur mit den Messpunkten, an denen ein Wert vorliegt, `ElapsedSec` als Abstand zum vorigen Messpunkt. Eine Reihe ohne bewertbaren Punkt entfällt. `Label` ist eine deutsche Bezeichnung der Instanz, z. B. `Laufwerk C:`, `Profilcontainer von alice (\\fs01\upm$)`, `Profilcontainer (Benutzer unbekannt)` oder der Benutzername.

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Load.Tests.ps1,tests/Compat.Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Load.ps1 tests/Load.Tests.ps1
git commit -m "Load ticks, instance signals and sessions into a model"
```

---

### Task 10: Datenmodell – Prozesse mit Fortführung

**Files:**
- Modify: `src/WorkerPerf.Load.ps1`
- Test: `tests/LoadProcesses.Tests.ps1`

**Interfaces:**
- Consumes: Modell aus Task 9, `Resolve-WorkerPerfRole` (Task 2).
- Produces: zusätzliche Modellfelder.

| Feld | Inhalt |
|---|---|
| `Sessions[]` | zusätzlich `CpuMs`, `Ws`, `Priv`, `Io` (`double[] nP`) und `N` (`int[] nP`); `Ws`, `Priv`, `N` einschließlich ruhender Prozesse |
| `Apps` | Liste: `Index`, `Name`, `Role`, `RoleLabel`, `Path`, `Instances`, `CpuMs`, `Ws`, `Priv`, `Io`, `N` |
| `Proc` | Array nach `K` (`$null` für unbekannte): `K`, `Pid`, `Name`, `Sid`, `StartMs`, `Path`, `Services`, `Cmd`, `SessionIndex`, `AppIndex`, `Role`, `RoleLabel`, `IsCollector`, `FirstP`, `LastP`, `CpuMs`, `CpuMaxPct`, `WsMaxKB`, `WsAvgKB`, `PrivMaxKB`, `IoBytes`, `Handles`, `Threads` |
| `Pairs` | `"<SessionIndex>|<AppIndex>"` → `S`, `A`, `Instances`, `CpuMs`, `IoBytes`, `WsSumKB`, `WsMaxKB` |
| `Rows` | `Start [int[] nP+1]`, `K [int[]]`, `CpuMs`, `Io`, `WsKB` (`double[]`): die Prozesszeilen je Schnappschuss |
| `InputProc.K` | `int[]`, -1 wenn kein Prozess passt |
| `TotalCpuMs` | Summe aller `CpuMs` im Zeitraum |

- [ ] **Step 1: Den fehlschlagenden Test schreiben**

`tests/LoadProcesses.Tests.ps1` beginnt mit demselben `BeforeAll` wie `tests/Load.Tests.ps1`; die gemeinsamen Hilfsfunktionen (`Get-Ts`, `New-TickLine`, `New-SnapLine`, `Write-TestRun`, `Import-TestRun`) wandern dafür aus `Load.Tests.ps1` in eine neue Datei `tests/LoadHelpers.ps1`, die beide Testdateien einbinden.

```powershell
Describe 'Import-WorkerPerfRun: Prozesse' {
    BeforeAll {
        $start = Get-Ts -3600
        $info = @("0,100,4,EXCEL.EXE,5,$start,C:\x\EXCEL.EXE,,", "1,200,4,chrome.exe,5,$start,C:\x\chrome.exe,,", "2,300,4,chrome.exe,5,$start,C:\x\chrome.exe,,",
                  "3,4242,4,powershell.exe,0,$start,C:\x\powershell.exe,,", "4,200,4,notepad.exe,5,$(Get-Ts 11),C:\x\notepad.exe,,")
        # K0 EXCEL: 100 MB, CPU in P1, 200 MB in P3.  K1 chrome (PID 200): endet in P2.  K2 chrome: ruht.  K3 Collector.  K4 notepad uebernimmt PID 200 in P3.
        $rows = @('0,0,0,102400,102400,0,0,0,10,2', '0,1,0,51200,51200,0,0,0,10,2', '0,2,0,51200,51200,0,0,0,10,2', '0,3,10,20480,20480,0,0,0,10,2',
                  '1,0,500,102400,102400,1048576,0,5,10,2', '3,0,100,204800,204800,0,0,0,10,2', '3,4,40,10240,10240,0,0,0,10,2')
        $script:Files = @{
            'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'procinfo.csv' = $info; 'processes.csv' = $rows; 'procend.csv' = @('2,1')
            'sessions.csv' = @(0..3 | ForEach-Object { "$_,5,alice,DOM,Active,ICA#5,PC1,,0" }) + @(0..3 | ForEach-Object { "$_,0,,,Disconnected,Services,,," })
            'inputdelay_proc.csv' = @('1,5,200,chrome.exe,400', '7,5,200,notepad.exe,250')
        }
        $script:M = Import-TestRun 'p' $Files
        $script:A = $M.Sessions | Where-Object User -eq 'alice'
    }
    It 'fuehrt ruhende Prozesse fort und beendet sie' {
        $A.Ws | Should -Be @(204800, 204800, 153600, 266240); $A.N | Should -Be @(3, 3, 2, 3)
        $A.CpuMs | Should -Be @(0, 500, 0, 140); $A.Io[1] | Should -Be 1048576
    }
    It 'fasst Anwendungen und Paare zusammen' {
        $chrome = $M.Apps | Where-Object Name -eq 'chrome.exe'
        $chrome.Instances | Should -Be 2; $chrome.Ws | Should -Be @(102400, 102400, 51200, 51200)
        $M.Pairs["$($A.Index)|$($chrome.Index)"].Instances | Should -Be 2
    }
    It 'fuehrt Kennzahlen je Prozess' {
        $M.Proc[0].CpuMs | Should -Be 600; $M.Proc[0].WsMaxKB | Should -Be 204800; $M.Proc[0].FirstP | Should -Be 0; $M.Proc[0].LastP | Should -Be 3
        $M.Proc[0].WsAvgKB | Should -Be 128000                    # drei Schnappschuesse mit 100 MB, einer mit 200 MB
        $M.Proc[1].LastP | Should -Be 1; $M.Proc[0].SessionIndex | Should -Be $A.Index
        $M.Proc[3].IsCollector | Should -BeTrue; $M.Proc[0].IsCollector | Should -BeFalse
        $M.TotalCpuMs | Should -Be 650
    }
    It 'legt die Zeilen je Schnappschuss ab' {
        $M.Rows.Start | Should -Be @(0, 4, 5, 5, 7); $M.Rows.K[4] | Should -Be 0; $M.Rows.CpuMs[4] | Should -Be 500
    }
    It 'ordnet Eingabeverzoegerungen dem Prozess zu, der die PID zu dieser Zeit hatte' {       # Review Focus 4
        $M.InputProc.K | Should -Be @(1, 4)
    }
    It 'heilt fehlende Ende-Meldungen am Stuetzpunkt' {
        $f = $Files.Clone(); $f['procend.csv'] = @()
        $f['snapshots.csv'] = @((New-SnapLine 0 'K'), (New-SnapLine 1), (New-SnapLine 2), (New-SnapLine 3 'K'))
        $f['processes.csv'] = @($Files['processes.csv']) + '3,2,0,51200,51200,0,0,0,10,2' + '3,3,0,20480,20480,0,0,0,10,2'
        $m = Import-TestRun 'heal' $f
        ($m.Sessions | Where-Object User -eq 'alice').N | Should -Be @(3, 3, 3, 3)      # K1 fehlt im Stuetzpunkt P3 und gilt ab dort als beendet
        $m.Proc[1].LastP | Should -Be 2
    }
    It 'beginnt einen Zeitausschnitt am vorhergehenden Stuetzpunkt' {
        $m = Import-TestRun 'cut' $Files @{ From = $Base.AddSeconds(11).LocalDateTime }
        $a = $m.Sessions | Where-Object User -eq 'alice'
        $m.Snap.N | Should -Be 2; $a.Ws | Should -Be @(153600, 266240); $a.CpuMs | Should -Be @(0, 140); $m.Proc[0].CpuMs | Should -Be 100
    }
    It 'uebergeht Zeilen jenseits des letzten vollstaendigen Schnappschusses' {        # Review Focus 3
        $f = $Files.Clone(); $f['processes.csv'] = @($Files['processes.csv']) + '4,0,999,1,1,0,0,0,1,1' + '4,0,12'; $f['procend.csv'] = @('2,1', '9,77')
        (Import-TestRun 'abort' $f).TotalCpuMs | Should -Be 650
    }
}
```

- [ ] **Step 2: Test ausführen und Fehlschlag prüfen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/LoadProcesses.Tests.ps1`
Expected: FAIL (`$A.Ws` ist leer)

- [ ] **Step 3: Prozessdaten in `Import-WorkerPerfRun` ergänzen**

- Ein Durchlauf über `processes.csv` mit `StreamReader` und `Split(',')`; `procend.csv` vorab nach `P` gruppiert einlesen. Die Schleife ist die laufzeitkritische Stelle der Auswertung: keine Funktionsaufrufe und keine Pipeline je Zeile.
- Je Prozess den letzten Stand von Working Set und Private Bytes führen; Sitzung und Anwendung führen laufende Summen, die bei jeder Zeile um die Differenz zum letzten Stand und beim Ende eines Prozesses um dessen Stand verändert und am Ende jedes Schnappschusses in die Arrays geschrieben werden.
- An einem Stützpunkt gilt jeder bisher lebende Prozess ohne Zeile als beendet.
- Bei `-From` beginnt das Lesen am letzten Stützpunkt, der nicht nach dem ersten Schnappschuss des Zeitraums liegt; Zeilen davor bauen nur den Stand auf und zählen in keiner Kennzahl.
- Zeilen mit `P` außerhalb der gelesenen Schnappschüsse oder unbekanntem `K` werden übergangen.
- Sitzung eines Prozesses: die Sitzung seiner Sitzungs-ID am Schnappschuss seiner ersten Zeile. Anwendung: Name ohne Rücksicht auf Groß-/Kleinschreibung. Rolle des Prozesses über `Resolve-WorkerPerfRole` mit Name, Diensten und Sitzungs-ID; Rolle der Anwendung mit Name und der Sitzungs-ID der ersten Instanz, ohne Dienste.
- `WsAvgKB` ist der Mittelwert über die Schnappschüsse von `FirstP` bis `LastP` mit fortgeführtem Stand. `CpuMaxPct` bezieht sich auf die Host-Kapazität des Schnappschusses (`ElapsedSec * 1000 * Cores`).
- `InputProc.K`: der Prozess mit dieser PID, dessen `FirstP`…`LastP` den Schnappschuss des Takts einschließt; `IsCollector`: PID gleich `Meta.CollectorPid`.

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/LoadProcesses.Tests.ps1,tests/Load.Tests.ps1,tests/Compat.Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Load.ps1 tests/LoadProcesses.Tests.ps1 tests/LoadHelpers.ps1 tests/Load.Tests.ps1
git commit -m "Load process rows with carry-forward state"
```

---

### Task 11: Vorfallsdetails und Klartext

**Files:**
- Modify: `src/WorkerPerf.Findings.ps1`
- Create: `src/texts.de.json`
- Test: `tests/Attribution.Tests.ps1`

**Interfaces:**
- Consumes: Vorfälle (Task 4); aus dem Modell die Felder `Meta.OffsetMinutes`, `Tick.TimeMs`, `Snap.TimeMs`, `Snap.ElapsedSec`, `Sessions[].User/Sid/Input/Rtt/Ws`, `Apps[]`, `Proc[]`, `Rows`, `InputProc`, `Probes`, `Events`, `Scans`.
- Produces:

```powershell
function Add-WorkerPerfIncidentDetail { param([AllowEmptyCollection()][object[]]$Incidents, $Model, $Thresholds) }
#   ergaenzt je Vorfall: Affected, Contributors (Ressource -> Rangliste), DelayProcesses, Endpoints, Ica, Security, Companion, Events, ScanActive
function Get-WorkerPerfIncidentText { param($Incident, $Model, $Thresholds, [hashtable]$Texts) }   # -> [string]
```

Formen: `Affected[]` = `SessionIndex`, `PeakMs`. Rangliste = `Measure` (`cpu`|`memory`|`io`), `Main` (`App`, `AppIndex`, `SessionIndex`, `User`, `SharePct`, `BaselinePct`, `GrowthMB`), `Processes[]` (`K`, `Name`, `Pid`, `SessionIndex`, `SharePct`, `BaselinePct`, `GrowthMB`, `Role`, `RoleLabel`, `IsCollector`), `Apps[]` (`AppIndex`, `Name`, `SharePct`, `BaselinePct`), `Sessions[]` (`SessionIndex`, `User`, `SharePct`, `BaselinePct`). `DelayProcesses[]` = `Name`, `Pid`, `K`, `SessionIndex`, `MaxMs`, `Role`. `Endpoints[]` = `Name`, `Role`, `MaxMs`, `Failed`. `Ica[]` = `SessionIndex`, `MaxMs`. `Security` = `Products[]` (`Label`, `SharePct`), `TotalPct`. `Companion` = `Label`, `SharePct`, `Resource`, `TopIoApp`, `TopIoUser` oder `$null`.

`src/texts.de.json` (genauer Wortlaut):

```json
{
  "resource.cpu": "CPU", "resource.memory": "Arbeitsspeicher", "resource.disk": "Datenträger", "resource.share": "Dateiserver",
  "resource.profile": "Profilcontainer", "resource.network": "Netzstrecke", "resource.endpoint": "Gegenstelle", "resource.input": "Eingabeverzögerung",
  "measure.cpu": "der CPU-Zeit", "measure.memory": "des belegten Arbeitsspeichers", "measure.io": "der I/O-Menge",
  "engpass": "{0}–{1}: {2}-Engpass ({3} Spitze {4}, Soll {5}).",
  "ohne": "{0}–{1}: Eingabeverzögerung ohne Engpass auf dem Worker (Spitze {2}, Soll {3}).",
  "umfeld.network": "{0}–{1}: Netzstrecke von {2} auffällig ({3} Spitze {4}, Soll {5}). Betrifft die Sitzung, nicht den Worker.",
  "umfeld.endpoint": "{0}–{1}: Gegenstelle {2} träge oder nicht erreichbar (Spitze {3}).",
  "chronic.prefix": "Dauerzustand: ",
  "affected.one": " Betroffen: 1 Sitzung.", "affected.many": " Betroffen: {0} Sitzungen.", "affected.none": " Keine Sitzung mit messbarer Eingabeverzögerung.",
  "main": " Hauptverursacher: {0} in der Sitzung von {1} mit {2} % {3} (sonst {4} %).",
  "main.nobase": " Hauptverursacher: {0} in der Sitzung von {1} mit {2} % {3}.",
  "companion": " Begleiter: {0} mit {1} % {2}; größter I/O-Erzeuger im Fenster: {3} ({4}). Scan-Ausschlüsse prüfen.",
  "ohne.process": " Höchste Verzögerung in {0} ({1}).",
  "ohne.cause": " Die Ursache liegt außerhalb des Workers oder in der Anwendung selbst (Datenbank, Proxy, Netz).",
  "endpoint.context": " Gegenstelle {0}: {1}.", "chronic.context": " Dauerhaft erhöht: {0}.",
  "probe.error": "Verbindungsfehler", "user.system": "Dienste/System", "user.unknown": "unbekannt"
}
```

- [ ] **Step 1: Den fehlschlagenden Test schreiben**

```powershell
BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Findings.ps1')
    $script:Th = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json')
    $script:Texts = Read-WorkerPerfTexts (Join-Path $PSScriptRoot '../src/texts.de.json')
    $script:T0 = 1700000000000                              # 22:13:20 UTC, mit 60 min Versatz 23:13:20
    function New-TestModel([switch]$Memory) {
        $mb = 1024.0
        $m = @{
            Meta = @{ Cores = 4; OffsetMinutes = 60 }
            Tick = @{ N = 30; TimeMs = [long[]](1..30 | ForEach-Object { $T0 + $_ * 2000 }); ElapsedSec = [double[]](1..30 | ForEach-Object { 2 }) }
            Snap = @{ N = 4; TimeMs = [long[]](1..4 | ForEach-Object { $T0 + $_ * 15000 }); ElapsedSec = [double[]](15, 15, 15, 15) }
            Sessions = @(
                @{ Index = 0; Sid = 2; User = 'user017'; Input = (New-Object double[] 30); Rtt = (New-Object double[] 4); Ws = [double[]](100 * $mb, 100 * $mb, 100 * $mb, 100 * $mb) }
                @{ Index = 1; Sid = 3; User = 'user018'; Input = (New-Object double[] 30); Rtt = (New-Object double[] 4); Ws = [double[]](300 * $mb, 300 * $mb, 300 * $mb, 300 * $mb) }
                @{ Index = 2; Sid = 0; User = ''; Input = (New-Object double[] 30); Rtt = (New-Object double[] 4); Ws = [double[]](100 * $mb, 100 * $mb, 100 * $mb, 100 * $mb) })
            Apps = @(@{ Index = 0; Name = 'EXCEL.EXE'; Role = ''; RoleLabel = '' }, @{ Index = 1; Name = 'chrome.exe'; Role = ''; RoleLabel = '' },
                     @{ Index = 2; Name = 'MsMpEng.exe'; Role = 'Sicherheit'; RoleLabel = 'Microsoft Defender' })
            Proc = @(
                @{ K = 0; Pid = 100; Name = 'EXCEL.EXE'; SessionIndex = 0; AppIndex = 0; Role = ''; RoleLabel = ''; IsCollector = $false; FirstP = 0; LastP = 3 }
                @{ K = 1; Pid = 200; Name = 'chrome.exe'; SessionIndex = 1; AppIndex = 1; Role = ''; RoleLabel = ''; IsCollector = $false; FirstP = 0; LastP = 3 }
                @{ K = 2; Pid = 300; Name = 'MsMpEng.exe'; SessionIndex = 2; AppIndex = 2; Role = 'Sicherheit'; RoleLabel = 'Microsoft Defender'; IsCollector = $false; FirstP = 0; LastP = 3 })
            InputProc = @{ TickPos = [int[]]@(10); SessionIndex = [int[]]@(0); Pid = [int[]]@(100); Name = [string[]]@('EXCEL.EXE'); DelayMs = [double[]]@(300); K = [int[]]@(0) }
            Probes = @(@{ Name = 'DB'; Role = 'Datenbank'; Ms = [double[]](5, 350, 5, 5); Error = [string[]]('', '', '', '') })
            Events = @(); Scans = @()
        }
        if ($Memory) {      # K1 und K2 schreiben nur im Stuetzpunkt P0; K0 waechst in P2 von 100 auf 600 MB
            $m.Rows = @{ Start = [int[]](0, 3, 3, 4, 4); K = [int[]](0, 1, 2, 0); CpuMs = [double[]](0, 0, 0, 0); Io = [double[]](0, 0, 0, 0)
                         WsKB = [double[]](100 * $mb, 300 * $mb, 100 * $mb, 600 * $mb) }
            $m.Sessions[0].Ws = [double[]](100 * $mb, 100 * $mb, 600 * $mb, 600 * $mb)
        }
        else {              # je Schnappschuss K0, K1, K2; in P1 und P2 verbraucht K0 41 % der CPU-Zeit, sonst 2 %
            $m.Rows = @{ Start = [int[]](0, 3, 6, 9, 12); K = [int[]](0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2)
                         CpuMs = [double[]](200, 6900, 2900, 4100, 3000, 2900, 4100, 3000, 2900, 200, 6900, 2900)
                         Io = [double[]](0, 5e6, 1e6, 0, 5e6, 1e6, 0, 5e6, 1e6, 0, 5e6, 1e6)
                         WsKB = [double[]](1..4 | ForEach-Object { 100 * $mb; 300 * $mb; 100 * $mb }) }
        }
        $m.Sessions[0].Input[10] = 300                       # Takt bei T0 + 22 s
        $m
    }
    function New-TestIncident([string]$Resource, [string]$SignalId, [double]$Peak, [string]$Type = 'engpass') {
        $isInput = $Resource -eq 'input'
        $f = @{ SignalId = $SignalId; Resource = $Resource; Instance = ''; Label = $Th[$SignalId].label; Scope = $(if ($isInput) { 'session' } else { 'global' })
                SessionIndex = $(if ($isInput) { 0 } else { -1 }); StartMs = [long]($T0 + 15000); EndMs = [long]($T0 + 45000); Severity = 2; PeakValue = $Peak
                PeakTimeMs = [long]($T0 + 30000); BadPoints = 5 }
        @{ Id = 1; StartMs = $f.StartMs; EndMs = $f.EndMs; Severity = 2; Chronic = $false; Type = $Type; Lead = $(if ($Type -eq 'engpass') { $Resource } else { $null })
           Resources = @($(if ($Type -eq 'engpass') { $Resource })); Findings = @($f); ChronicContext = @() }
    }
    function Add-Detail($Model, $Incident) { Add-WorkerPerfIncidentDetail -Incidents @($Incident) -Model $Model -Thresholds $Th }
}
Describe 'Add-WorkerPerfIncidentDetail' {
    It 'nennt Betroffene, Verursacher mit Normalwert und den Begleiter' {
        $m = New-TestModel; $i = New-TestIncident 'cpu' 'cpu.host' 97; Add-Detail $m $i
        $i.Affected.Count | Should -Be 1; $i.Affected[0].SessionIndex | Should -Be 0; $i.Affected[0].PeakMs | Should -Be 300
        $c = $i.Contributors['cpu']
        $c.Measure | Should -Be 'cpu'; $c.Main.App | Should -Be 'EXCEL.EXE'; $c.Main.User | Should -Be 'user017'
        $c.Main.SharePct | Should -Be 41; $c.Main.BaselinePct | Should -Be 2
        $c.Processes.K | Should -Be @(0, 1, 2); $c.Processes[2].SharePct | Should -Be 29
        $c.Sessions[0].SessionIndex | Should -Be 0; $c.Apps[1].Name | Should -Be 'chrome.exe'
        $i.Companion.Label | Should -Be 'Microsoft Defender'; $i.Companion.SharePct | Should -Be 29
        $i.Companion.TopIoApp | Should -Be 'chrome.exe'; $i.Companion.TopIoUser | Should -Be 'user018'
        $i.Security.TotalPct | Should -Be 29; $i.Security.Products[0].Label | Should -Be 'Microsoft Defender'
        $i.DelayProcesses[0].Name | Should -Be 'EXCEL.EXE'; $i.Endpoints[0].MaxMs | Should -Be 350
    }
    It 'fuehrt den Speicher ruhender Prozesse fort' {
        $m = New-TestModel -Memory; $i = New-TestIncident 'memory' 'mem.used' 93
        $i.Findings[0].StartMs = [long]($T0 + 31000); $i.StartMs = $i.Findings[0].StartMs       # das Fenster trifft nur P2
        Add-Detail $m $i; $c = $i.Contributors['memory']
        $c.Main.App | Should -Be 'EXCEL.EXE'; $c.Main.SharePct | Should -Be 60; $c.Main.GrowthMB | Should -Be 500; $c.Main.BaselinePct | Should -Be 40
        $c.Processes[1].K | Should -Be 1; $c.Processes[1].SharePct | Should -Be 30                 # ohne eigene Zeile im Fenster
    }
    It 'beschraenkt den Profilcontainer auf die eigene Sitzung' {
        $m = New-TestModel; $i = New-TestIncident 'profile' 'disk.latency' 45
        $i.Findings[0].Scope = 'session'; $i.Findings[0].SessionIndex = 1; Add-Detail $m $i
        @($i.Contributors['profile'].Processes).Count | Should -Be 1; $i.Contributors['profile'].Main.App | Should -Be 'chrome.exe'
        $i.Contributors['profile'].Measure | Should -Be 'io'
    }
    It 'kennzeichnet den Collector' {
        $m = New-TestModel; $m.Proc[1].IsCollector = $true; $i = New-TestIncident 'cpu' 'cpu.host' 97; Add-Detail $m $i
        $i.Contributors['cpu'].Processes[1].IsCollector | Should -BeTrue
    }
    It 'nennt Ereignisse und laufende Scans im Fenster' {
        $m = New-TestModel; $m.Events = @(@{ TimeMs = $T0 + 20000; Kind = 'applocker-block' }, @{ TimeMs = $T0 + 90000; Kind = 'applocker-block' })
        $m.Scans = @(@{ StartMs = $T0; EndMs = $T0 + 20000 }); $i = New-TestIncident 'cpu' 'cpu.host' 97; Add-Detail $m $i
        @($i.Events).Count | Should -Be 1; $i.ScanActive | Should -BeTrue
    }
}
Describe 'Get-WorkerPerfIncidentText' {
    It 'beschreibt einen Engpass mit Begleiter' {
        $m = New-TestModel; $i = New-TestIncident 'cpu' 'cpu.host' 97; Add-Detail $m $i
        Get-WorkerPerfIncidentText -Incident $i -Model $m -Thresholds $Th -Texts $Texts | Should -Be ('23:13:35–23:14:05: CPU-Engpass (CPU-Auslastung Spitze 97 %, Soll unter 75 %). ' +
            'Betroffen: 1 Sitzung. Hauptverursacher: EXCEL.EXE in der Sitzung von user017 mit 41 % der CPU-Zeit (sonst 2 %). ' +
            'Begleiter: Microsoft Defender mit 29 % der CPU-Zeit; größter I/O-Erzeuger im Fenster: chrome.exe (user018). Scan-Ausschlüsse prüfen.')
    }
    It 'beschreibt eine Verzoegerung ohne Engpass' {
        $m = New-TestModel; $i = New-TestIncident 'input' 'input.session' 300 -Type 'ohne-engpass'; Add-Detail $m $i
        Get-WorkerPerfIncidentText -Incident $i -Model $m -Thresholds $Th -Texts $Texts | Should -Be ('23:13:35–23:14:05: Eingabeverzögerung ohne Engpass auf dem Worker (Spitze 300 ms, Soll unter 150 ms). ' +
            'Betroffen: 1 Sitzung. Höchste Verzögerung in EXCEL.EXE (user017). ' +
            'Die Ursache liegt außerhalb des Workers oder in der Anwendung selbst (Datenbank, Proxy, Netz). Gegenstelle DB: 350 ms.')
    }
    It 'stellt einem Dauerzustand den Hinweis voran und nennt dauerhaft erhoehte Signale' {
        $m = New-TestModel; $i = New-TestIncident 'cpu' 'cpu.host' 97; $i.Chronic = $true
        $i.ChronicContext = @(@{ IncidentId = 9; SignalId = 'mem.used'; Label = 'RAM-Auslastung'; Severity = 1; Explains = $false }); Add-Detail $m $i
        $text = Get-WorkerPerfIncidentText -Incident $i -Model $m -Thresholds $Th -Texts $Texts
        $text | Should -Match '^Dauerzustand: 23:13:35–23:14:05: CPU-Engpass'; $text | Should -Match ' Dauerhaft erhöht: RAM-Auslastung\.$'
    }
}
```

- [ ] **Step 2: Test ausführen und Fehlschlag prüfen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Attribution.Tests.ps1`
Expected: FAIL, `texts.de.json` nicht gefunden

- [ ] **Step 3: `texts.de.json` anlegen und die Funktionen implementieren**

- **Fenster:** Ein Takt gehört dazu, wenn `StartMs < TimeMs <= EndMs`. Ein Schnappschuss gehört dazu, wenn `TimeMs > StartMs` und `TimeMs - ElapsedSec * 1000 < EndMs`. Für Proben und ICA-Werte gilt das Fenster mit 15 s Zugabe an beiden Enden.
- **Betroffene:** Sitzungen mit `Input` ab der Schwelle „auffällig" in einem Takt des Fensters, nach Spitze absteigend.
- **Verursacher** je Worker-Ressource des Vorfalls: Maß `cpu` (Summe `Rows.CpuMs` im Fenster) für `cpu`, `io` (Summe `Rows.Io`) für `disk`, `share`, `profile`, `memory` (Working Set am letzten Schnappschuss des Fensters mit fortgeführtem Stand) für `memory`. `SharePct` ist der Anteil an der Summe aller Prozesse. `BaselinePct` ist derselbe Anteil über alle Schnappschüsse, die in keinem Vorfall liegen, der kein Dauerzustand ist (`$null`, wenn es keine gibt); beim Speicher der mittlere Working Set geteilt durch den mittleren Gesamt-Working-Set dieser Schnappschüsse, wobei der Gesamtwert aus `Sessions[].Ws` kommt. `GrowthMB` (nur Speicher) ist der Stand am letzten Schnappschuss des Fensters minus der Stand vor dem ersten. Für `profile` zählen nur Prozesse der Sitzung des Befunds. Je Rangliste die fünf größten, Gleichstand nach Name.
- **Main** ist die Anwendung-in-Sitzung mit dem größten Anteil, ohne Prozesse der Rolle `Sicherheit`.
- **Security:** Anteil der Prozesse der Rolle `Sicherheit` am Maß der führenden Ressource (`cpu` bei Vorfällen ohne Worker-Ressource), nach `RoleLabel` getrennt und als Summe. **Companion:** gesetzt, wenn ein Prozess der Rolle `Sicherheit` in einer `Processes`-Rangliste steht; `TopIoApp`/`TopIoUser` ist die Anwendung-in-Sitzung mit der größten I/O-Menge im Fenster ohne Rolle `Sicherheit`.
- **DelayProcesses:** die fünf Einträge aus `InputProc` im Fenster mit der höchsten Verzögerung, je Prozess zusammengefasst.
- **Anteile** auf eine Nachkommastelle gerundet.
- **Klartext:** Zeiten als `HH:mm:ss` in der Ortszeit des Servers (`OffsetMinutes`). Zahlen deutsch formatiert; unter 10 mit einer Nachkommastelle, sofern nicht ganzzahlig, sonst ganzzahlig; mit Einheit des Schwellwerts. Aufbau `engpass`: Kopfsatz aus dem Befund der führenden Ressource mit der höchsten Stufe, dann Betroffene, dann `main` (ohne Normalwert `main.nobase`), dann `companion`. Aufbau `ohne-engpass`: `ohne`, Betroffene, `ohne.process` für den ersten Eintrag aus `DelayProcesses`, `ohne.cause`, je Gegenstelle mit mindestens 50 ms oder Fehler `endpoint.context`. `umfeld`: `umfeld.network` oder `umfeld.endpoint`. Bei `Chronic` steht `chronic.prefix` davor; bei nichtleerem `ChronicContext` folgt `chronic.context` mit den Bezeichnungen. Benutzer ohne Namen: `user.system` in Sitzung 0, sonst `user.unknown`.

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Attribution.Tests.ps1,tests/Incidents.Tests.ps1,tests/Findings.Tests.ps1,tests/Compat.Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Findings.ps1 src/texts.de.json tests/Attribution.Tests.ps1
git commit -m "Attribute incidents to contributors and render plain-language text"
```

---

### Task 12: Berichtsskript und Durchlauf

**Files:**
- Modify: `src/New-WorkerPerfReport.ps1` (vollständig neu), `src/report-template.html` (nur der Datenplatzhalter), `tests/TestHelpers.ps1`, `README.md` (Abschnitt „Auswerten")
- Create: `tests/New-TestReports.ps1`
- Test: `tests/Report.Tests.ps1`

**Interfaces:**
- Consumes: Tasks 2, 3, 4, 9, 10, 11.
- Produces: `New-WorkerPerfReport.ps1 -Path <Ordner> [-OutFile] [-From] [-To] [-ThresholdFile] [-RoleFile] [-FocusUser <Name>] [-ReportedTime <datetime>] [-TopProcesses 150]`. `-ReportedTime` ist die Ortszeit des gemessenen Servers und wird mit `Model.Meta.OffsetMinutes` umgerechnet, nicht mit der Zeitzone des auswertenden Rechners.
- Produces: Datenplatzhalter in der Vorlage `<script id="wp-data" type="application/json">null</script>`; das Skript ersetzt `null` durch das JSON. `<`, `>` und `&` stehen im JSON als `\u003c`, `\u003e`, `\u0026`.
- Produces: Testhelfer `Get-ReportData([string]$Html)`, `New-SimRoleFile([string]$Path)`, `New-NoFindingThresholdFile([string]$Path)`, `New-TestReports([string]$OutDir) -> @{ Run; Report; Focus; None; StartMs }`; Skript `tests/New-TestReports.ps1 -OutDir <Ordner>` (ruft die Funktion auf und gibt den Ordner aus).
- Produces: das Berichts-JSON. Zeitreihen auf dem Takt-Raster haben `tickT.length` Werte, auf dem Schnappschuss-Raster `snapT.length`; `null` steht für „kein Wert".

```text
meta        computer, os, cores, ramGB, start, end, offsetMin, fastSec, snapSec, durationMin, ticks, snapshots, simulated, endReason, usersPerCore,
            processRows, processCount, totalCpuSec, generated, focus { user, found, sessions[], reportedMs }
quality     skippedTicks, tickMsAvg, tickMsMax, snapMsAvg, snapMsMax, burstSec, burstSnapshots, collectorCpuPct, collectorCpuMaxPct,
            sources[] { id, label, available, detail }
thresholds  [] { id, label, unit, warn, crit, ideal, origin, source, url, note, direction }
tickT, snapT, snapKind (Zeichenkette aus K, R, B)
host        cpu, queue, steal, memUsedPct, memUsedGB, commitPct, commitGB, pagesIn, inputMax, diskR, diskW, iopsR, iopsW, netR, netS, burst   (Takt-Raster)
            sessions, active, procs   (Schnappschuss-Raster)
volumes     [] { name, label, kind, s, backing, t[], ms[], ops[] }      t = Indizes in tickT mit Zeile
shares      [] { name, label, t[], ms[], ops[] }
probes      [] { name, role, host, port, ms[], failed[] }      Schnappschuss-Raster
mainApp     { label, t[], ms[] } oder null
events      [] { t, source, id, kind, text }
sessions    [] { i, id, user, domain, client, logon, first, last, durMin, activePct, idleMaxMin, cpuSec, cpuShare, cpuAvg, cpuP95, cpuMax,
                 wsAvg, wsMax, privAvg, privMax, ioMB, procsAvg, procsMax, rttAvg, rttP95, rttMax, inP95, inMax, inWarnPct, profileVolume,
                 cpu[], ws[], io[], rtt[], inT[], inMs[] }
apps        [] { i, name, role, roleLabel, path, inst, sess, instAvg, instMax, cpuSec, cpuShare, cpuAvg, cpuP95, cpuMax, wsAvg, wsMax, privMax,
                 wsPerInst, ioMB, cpu[] | null, ws[] | null }
pairs       [] { s, a, inst, cpuSec, wsAvg, wsMax, ioMB }
procs       [] { k, pid, name, role, roleLabel, services, s, a, start, path, cmd, first, last, cpuSec, cpuAvg, cpuMax, wsAvg, wsMax, privMax, ioMB,
                 handles, threads, isCollector, o, cpu[], ws[] }      o = erster Index in snapT
citrix      [] { source, s, instance, metric, avg, max, n }
sollIst     [] { id, label, unit, ideal, warn, crit, origin, source, url, note, measured, detail, avg, p95, max, pctNormal, pctWarn, pctCrit, worstInstance }
incidents   [] { id, type, chronic, severity, start, end, durSec, lead, resources[], text, focus, nearReported, scanActive, events[],
                 signals[] { id, label, resource, instance, s, peak, unit, ideal, severity, start, end },
                 affected[] { s, peakMs }, main { resource, app, a, s, user, sharePct, baselinePct, growthMB } | null,
                 contributors { <resource>: { measure, procs[], apps[], sessions[] } }, delayProcs[], endpoints[], ica[],
                 security { products[], totalPct }, companion | null, chronicContext[] }
noFinding   true, wenn incidents leer ist
```

Einheiten: CPU in % der Host-Kapazität (zwei Nachkommastellen), Speicher in MB (ganzzahlig), I/O-Verläufe in KB/s, Zeiten in Epochen-Millisekunden, Antwortzeiten in ms mit einer Nachkommastelle. Feldnamen in den Ranglisten der Vorfälle entsprechen denen aus Task 11 in Kleinschreibung mit kleinem Anfangsbuchstaben (`sharePct`, `baselinePct`, `isCollector`, …).

- [ ] **Step 1: Testhelfer ergänzen und den fehlschlagenden Test schreiben**

```powershell
# tests/TestHelpers.ps1 – Ergaenzung
function Get-ReportData([string]$Html) {
    $text = [IO.File]::ReadAllText($Html); $open = '<script id="wp-data" type="application/json">'
    $a = $text.IndexOf($open) + $open.Length
    $text.Substring($a, $text.IndexOf('</script>', $a) - $a) | ConvertFrom-Json
}
function New-SimRoleFile([string]$Path) {
    $r = Get-Content (Join-Path $PSScriptRoot '../src/roles.json') -Raw | ConvertFrom-Json
    ($r.roles | Where-Object label -eq 'Nexus KIS').processes = @('nexus.exe')
    [IO.File]::WriteAllText($Path, ($r | ConvertTo-Json -Depth 6)); $Path
}
function New-NoFindingThresholdFile([string]$Path) {
    $t = Get-Content (Join-Path $PSScriptRoot '../src/thresholds.json') -Raw | ConvertFrom-Json
    foreach ($e in $t.thresholds) { $e.warn = 1e9; $e.crit = 1e9 }
    [IO.File]::WriteAllText($Path, ($t | ConvertTo-Json -Depth 6)); $Path
}
function New-TestReports([string]$OutDir) {
    [void](New-Item -ItemType Directory -Path $OutDir -Force)
    $run = Invoke-SimCapture (Join-Path $OutDir 'capture')
    $report = Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1'; $roles = New-SimRoleFile (Join-Path $OutDir 'roles.sim.json')
    $startMs = (@(Get-Content (Join-Path $run 'expected.json') -Raw | ConvertFrom-Json) | Where-Object Key -eq 'cpu').StartMs - 300000
    $r = @{ Run = $run; StartMs = $startMs; Report = (Join-Path $OutDir 'report.html'); Focus = (Join-Path $OutDir 'report-focus.html'); None = (Join-Path $OutDir 'report-none.html') }
    $reported = [DateTimeOffset]::FromUnixTimeMilliseconds($startMs + 330000).LocalDateTime
    [void](& $report -Path $run -OutFile $r.Report -RoleFile $roles 6>$null)
    [void](& $report -Path $run -OutFile $r.Focus -RoleFile $roles -FocusUser 'user003' -ReportedTime $reported 6>$null)
    [void](& $report -Path $run -OutFile $r.None -RoleFile $roles -ThresholdFile (New-NoFindingThresholdFile (Join-Path $OutDir 'none.json')) 6>$null)
    $r
}
```

```powershell
# tests/Report.Tests.ps1
BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:R = New-TestReports (Join-Path $TestDrive 'r')
    $script:D = Get-ReportData $R.Report
    $script:Exp = @(Get-Content (Join-Path $R.Run 'expected.json') -Raw | ConvertFrom-Json)
    function Find-Incident($Data, $E) {
        @($Data.incidents | Where-Object { $_.type -eq $E.Type -and [bool]$_.chronic -eq [bool]$E.Chronic -and $_.lead -eq $E.Lead -and
            [Math]::Abs($_.start - $E.StartMs) -le 20000 -and [Math]::Abs($_.end - $E.EndMs) -le 20000 })
    }
    function Get-Hit([string]$Key) { (Find-Incident $D ($Exp | Where-Object Key -eq $Key))[0] }
}
Describe 'Durchlauf Simulation -> Bericht' {
    It 'findet genau die Vorfaelle des Drehbuchs' {
        $D.incidents.Count | Should -Be $Exp.Count; $D.noFinding | Should -BeFalse
        foreach ($e in $Exp) {
            $hit = Find-Incident $D $e
            $hit.Count | Should -Be 1 -Because $e.Key
            if ($e.MainApp) { $hit[0].main.app | Should -Be $e.MainApp -Because $e.Key; $hit[0].main.user | Should -Be $e.MainUser -Because $e.Key }
            @($hit[0].affected).Count | Should -Be $e.Affected -Because $e.Key
        }
    }
    It 'beschreibt den CPU-Engpass im Klartext' {
        (Get-Hit 'cpu').text | Should -Match '^\d\d:\d\d:\d\d–\d\d:\d\d:\d\d: CPU-Engpass \(.+ Spitze .+, Soll .+\)\. Betroffen: 6 Sitzungen\. Hauptverursacher: EXCEL\.EXE in der Sitzung von user003 mit \d+ % der CPU-Zeit \(sonst \d+(,\d)? %\)\.'
    }
    It 'fuehrt Speicher und Datentraeger in einem Vorfall' { (Get-Hit 'memory').resources | Should -Be @('memory', 'disk') }
    It 'nennt den Begleiter beim Datentraeger-Engpass' {
        $i = Get-Hit 'disk'; $i.companion.label | Should -Be 'Microsoft Defender'; $i.scanActive | Should -BeTrue
    }
    It 'erkennt die Verzoegerung ohne Engpass samt Gegenstelle' {
        $i = Get-Hit 'backend'
        $i.delayProcs[0].name | Should -Be 'nexus.exe'; $i.resources | Should -Be @('endpoint')
        ($i.endpoints | Where-Object name -eq 'Oracle-Listener').maxMs | Should -BeGreaterOrEqual 200
        $i.text | Should -Match 'außerhalb des Workers'
    }
    It 'bewertet alle zwoelf Messwerte gegen das Soll' {
        $D.sollIst.Count | Should -Be 12; @($D.sollIst | Where-Object measured).Count | Should -Be 12
        ($D.sollIst | Where-Object id -eq 'cpu.host').max | Should -BeGreaterOrEqual 90
    }
    It 'weist Messqualitaet und Collector-Anteil aus' {
        $D.quality.skippedTicks | Should -Be 0; $D.quality.burstSnapshots | Should -BeGreaterThan 50
        $D.quality.collectorCpuPct | Should -BeGreaterThan 0; @($D.procs | Where-Object isCollector).Count | Should -Be 1
    }
    It 'liefert Verlaeufe in voller Aufloesung' {
        $D.tickT.Count | Should -Be 1800; $D.host.cpu.Count | Should -Be 1800; $D.sessions[0].cpu.Count | Should -Be $D.snapT.Count
        $D.mainApp.label | Should -Be 'Nexus KIS'; $D.meta.usersPerCore | Should -Be 3.125
        ($D.volumes | Where-Object kind -eq 'profile').Count | Should -Be 25
    }
    It 'rechnet unter deutscher Kultur richtig' {                               # Review Focus 2
        $cpu = $D.sollIst | Where-Object id -eq 'cpu.host'
        $cpu.avg | Should -BeGreaterThan 30; $cpu.avg | Should -BeLessThan 50
        ($D.sessions | Measure-Object cpuShare -Sum).Sum | Should -BeGreaterThan 99
    }
    It 'bleibt unter 8 MB' { (Get-Item $R.Report).Length | Should -BeLessThan 8MB }
}
Describe 'Fokus, kein Befund, Zeitausschnitt' {
    It 'hebt Vorfaelle des gemeldeten Benutzers und der gemeldeten Uhrzeit hervor' {
        $f = Get-ReportData $R.Focus
        $f.meta.focus.found | Should -BeTrue
        $cpu = $f.incidents | Where-Object lead -eq 'cpu'
        $cpu.focus | Should -BeTrue; $cpu.nearReported | Should -BeTrue
        @($f.incidents | Where-Object focus).Count | Should -Be 1
    }
    It 'meldet einen unbekannten Benutzer, ohne abzubrechen' {
        $out = Join-Path $TestDrive 'u.html'
        [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $R.Run -OutFile $out -FocusUser 'niemand' 6>$null)
        (Get-ReportData $out).meta.focus.found | Should -BeFalse
    }
    It 'sagt ausdruecklich, wenn nichts gefunden wurde' {
        $n = Get-ReportData $R.None; $n.noFinding | Should -BeTrue; $n.incidents.Count | Should -Be 0; $n.sollIst.Count | Should -Be 12
    }
    It 'wertet einen Zeitausschnitt aus' {
        $out = Join-Path $TestDrive 'cut.html'; $from = [DateTimeOffset]::FromUnixTimeMilliseconds($R.StartMs + 240000).LocalDateTime
        [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $R.Run -OutFile $out -From $from -To $from.AddMinutes(4) 6>$null)
        $c = Get-ReportData $out
        $c.incidents.Count | Should -Be 2; @($c.incidents | Where-Object chronic).Count | Should -Be 0     # vier Minuten sind kein Dauerzustand
        ($c.incidents | Where-Object type -eq 'engpass').lead | Should -Be 'cpu'
    }
    It 'nennt den fehlerhaften Schwellwert' {
        $bad = Join-Path $TestDrive 'bad.json'; [IO.File]::WriteAllText($bad, '{"thresholds":[{"id":"cpu.host"}]}')
        { & (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $R.Run -OutFile (Join-Path $TestDrive 'x.html') -ThresholdFile $bad 6>$null } | Should -Throw '*cpu.host*'
    }
}
```

`tests/New-TestReports.ps1`:

```powershell
param([Parameter(Mandatory = $true)][string]$OutDir)
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
[void](New-TestReports $OutDir)
$OutDir
```

- [ ] **Step 2: Test ausführen und Fehlschlag prüfen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Report.Tests.ps1`
Expected: FAIL (das bisherige Skript findet `system.csv` nicht)

- [ ] **Step 3: Datenplatzhalter in der Vorlage ersetzen**

In `src/report-template.html` die Zeile `const D = /*__WORKERPERF_DATA__*/null;` durch `const D = JSON.parse(document.getElementById('wp-data').textContent);` ersetzen und vor dem bestehenden `<script>` das Element `<script id="wp-data" type="application/json">null</script>` einfügen. Die Seite selbst wird erst in Task 13 an die neuen Daten angepasst und ist bis dahin nicht lauffähig.

- [ ] **Step 4: `src/New-WorkerPerfReport.ps1` neu schreiben**

Ablauf: Bibliotheken einbinden; Schwellwerte (`-ThresholdFile`, sonst `thresholds.json` neben dem Skript), Rollen (`-RoleFile`, sonst `roles.json`) und Texte lesen; `Import-WorkerPerfRun`; `Get-WorkerPerfSeries`; `Get-WorkerPerfFindings`; `Join-WorkerPerfIncidents`; `Add-WorkerPerfIncidentDetail`; je Vorfall `Get-WorkerPerfIncidentText`; `Get-WorkerPerfSollIst` mit `Model.Sources`; Kennzahlen; JSON; Vorlage füllen; Datei schreiben; `Get-Item` der Datei ausgeben.

- Aus dem bisherigen Skript übernehmen: `Get-Stats`, `Format-JsonString`, `ConvertTo-JsonText` (mit `StringBuilder` als Rohtext) und die Kennzahlenlogik von `Get-EntitySummary`, jetzt auf dem Schnappschuss-Raster. `Get-BucketSeries` entfällt; Verläufe werden vollständig eingebettet, NaN als `null`.
- Verläufe je Anwendung nur bei `cpuShare >= 0.1` oder `wsMax >= 50` MB, sonst `null`.
- Prozessauswahl wie bisher (`-TopProcesses` nach CPU-Zeit und nach Spitzenspeicher, ein Drittel davon nach I/O, je Sitzung die acht größten nach CPU und fünf nach Speicher), zusätzlich jeder Prozess, der in einer Rangliste eines Vorfalls steht.
- `meta.usersPerCore` ist die höchste Zahl gleichzeitiger Benutzersitzungen geteilt durch die logischen Prozessoren; der Wert wird angezeigt, aber nicht bewertet.
- `host.inputMax` ist je Takt das Maximum über alle Sitzungen. `inWarnPct` ist der Anteil der Takte einer Sitzung mit Eingabeverzögerung ab „auffällig".
- `incidents[].main` ist `Contributors[Lead].Main` mit `resource`; ohne `Lead` `null`. `signals` sind die Befunde des Vorfalls.
- Fokus: `-FocusUser` passt ohne Rücksicht auf Groß-/Kleinschreibung auf `User` oder `Domain\User`. `focus` ist wahr, wenn eine dieser Sitzungen unter den Betroffenen ist oder ein sitzungsbezogener Befund des Vorfalls ihr gehört. `nearReported` ist wahr, wenn die gemeldete Uhrzeit im Fenster oder höchstens 15 Minuten davor oder danach liegt.
- `quality.collectorCpuPct` ist der Anteil des Collector-Prozesses an der gesamten CPU-Zeit, `collectorCpuMaxPct` sein höchster Anteil an der Host-Kapazität in einem Schnappschuss. `quality.skippedTicks` zählt Takte mit `ElapsedSec` über dem 1,5-Fachen des schnellen Takts.

- [ ] **Step 5: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 6: README anpassen**

Abschnitt „Auswerten": neue Parameter, Beispiel mit `-FocusUser` und `-ReportedTime`, Hinweis, dass Schwellen und Rollen bei der Auswertung gelesen werden und eine Messung sich mit geänderten Dateien neu auswerten lässt. Die Tabelle „Datenformat" durch die Dateien des Formats 2 ersetzen.

- [ ] **Step 7: Commit**

```bash
git add src/New-WorkerPerfReport.ps1 src/report-template.html tests/TestHelpers.ps1 tests/New-TestReports.ps1 tests/Report.Tests.ps1 README.md
git commit -m "Rewrite report builder around incidents and target comparison"
```

---

### Task 13: Berichtsseite – neue Daten, Hineinzoomen, Soll-Bänder

**Files:**
- Modify: `src/report-template.html`
- Create: `tests/report-browser.js`

**Interfaces:**
- Consumes: Berichts-JSON (Task 12), `tests/New-TestReports.ps1`.
- Produces – Bezeichner, auf die Task 14 und die Browserprüfung aufbauen:
  - Reiter `nav button[data-tab]` mit `findings`, `overview`, `sessions`, `apps`, `procs`; Abschnitte `#tab-<name>`. In dieser Task ist `overview` der Startreiter und `#tab-findings` leer.
  - `window.WP = { zoom, setZoom(t0, t1), resetZoom(), onZoom(fn) }`; `zoom` ist `null` oder `{ t0, t1 }`. Schaltfläche `#zoomReset` („Gesamter Zeitraum"), nur bei gesetztem Zoom sichtbar; `#zoomInfo` nennt den Zeitraum.
  - Diagrammfunktion `chart(host, { series, axis: 'tick' | 'snap', signal, stacked, unit, decimals, limit, limitLabel })`. Reihen sind dicht (`values`) oder dünn (`t`, `v`). Mit `signal` zeichnet sie Linien `.band-warn` und `.band-crit` mit Beschriftung.
  - Kacheln `.tile[data-signal][data-status]` mit `data-status` `0`, `1`, `2` oder `na`.
  - Rollenfilter `select#fRoleApps`, `select#fRoleProcs`.
  - Diagramm-Container der Übersicht: `#chCpu`, `#chQueue`, `#chMem`, `#chInput`, `#chVolumes`, `#chShares`, `#chProbes`, `#chDisk`, `#chIops`, `#chNet`, `#chSess`, `#chMainApp`, `#chCpuStack`, `#chMemStack`.

- [ ] **Step 1: Die fehlschlagende Browserprüfung schreiben** (`tests/report-browser.js`)

```js
// Aufruf: node tests/report-browser.js <Ordner aus tests/New-TestReports.ps1>
const { chromium } = require('playwright');
const path = require('path');
const assert = require('assert');
let checks = 0;
const ok = (cond, msg) => { assert.ok(cond, msg); checks++; };
const hhmm = (ms, offMin) => new Date(ms + offMin * 60000).toISOString().substr(11, 5);

async function open(browser, file, scheme) {
  const page = await browser.newPage({ viewport: { width: 1400, height: 900 }, colorScheme: scheme });
  page.errors = [];
  page.on('pageerror', (e) => page.errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error') page.errors.push(m.text()); });
  await page.goto('file://' + file);
  const D = await page.evaluate(() => JSON.parse(document.getElementById('wp-data').textContent));
  return { page, D };
}

async function checkPage(browser, dir, scheme) {                    // Task 13
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme);
  ok(await page.locator('nav button[data-tab]').count() === 5, 'fuenf Reiter');
  await page.click('nav button[data-tab=overview]');
  for (const id of ['chCpu', 'chMem', 'chInput', 'chVolumes', 'chCpuStack', 'chMemStack']) ok(await page.locator(`#${id} svg path`).count() > 0, id + ' gezeichnet');
  ok(await page.locator('#chCpu .band-warn').count() === 1 && await page.locator('#chCpu .band-crit').count() === 1, 'Soll-Baender im CPU-Diagramm');
  ok(await page.locator('.tile[data-signal="cpu.host"]').getAttribute('data-status') === '2', 'CPU-Kachel kritisch');
  ok((await page.locator('.tile[data-signal="cpu.host"]').innerText()).includes('kritisch'), 'Status als Wort');
  ok(await page.locator('.tile.info[data-info="userspercore"]').count() === 1, 'Benutzer je logischer CPU als Information');
  ok(await page.locator('#chMainApp svg path').count() > 0, 'Verlauf der Hauptanwendung');
  ok(!(await page.locator('#zoomReset').isVisible()), 'ohne Zoom keine Ruecksetz-Schaltflaeche');
  const inc = D.incidents.find((i) => i.lead === 'cpu');
  await page.evaluate(([a, b]) => window.WP.setZoom(a, b), [inc.start, inc.end]);
  ok(await page.locator('#zoomReset').isVisible(), 'Ruecksetz-Schaltflaeche sichtbar');
  ok((await page.locator('#chCpu svg text.xaxis').first().innerText()).startsWith(hhmm(inc.start, D.meta.offsetMin)), 'Zeitachse beginnt am Fensteranfang');
  await page.click('#zoomReset');
  ok(await page.evaluate(() => window.WP.zoom === null), 'Zoom zurueckgesetzt');
  await page.click('nav button[data-tab=apps]');
  await page.selectOption('#fRoleApps', 'Sicherheit');
  const roles = await page.locator('#tApps tbody tr td.role').allInnerTexts();
  ok(roles.length > 0 && roles.every((r) => r.includes('Sicherheit')), 'Rollenfilter Anwendungen');
  await page.click('nav button[data-tab=sessions]');
  await page.click('#tSessions tbody tr >> nth=0');
  ok(await page.locator('#dSessions .chart-input svg path').count() > 0, 'Eingabeverzoegerung in der Sitzungsansicht');
  await page.click('nav button[data-tab=procs]');
  ok(await page.locator('#tProcs tbody tr.collector').count() === 1, 'Collector gekennzeichnet');
  ok(page.errors.length === 0, 'Skriptfehler: ' + page.errors.join(' | '));
  await page.close();
}

(async () => {
  const dir = path.resolve(process.argv[2]);
  const browser = await chromium.launch();
  for (const scheme of ['light', 'dark']) await checkPage(browser, dir, scheme);
  console.log('browser checks passed: ' + checks);
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
```

- [ ] **Step 2: Prüfung ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/New-TestReports.ps1 -OutDir /tmp/wp-reports && node tests/report-browser.js /tmp/wp-reports`
Expected: Abbruch mit `AssertionError` (die Seite kennt die neuen Daten nicht)

- [ ] **Step 3: Die Seite umbauen**

- Farb-Tokens, Tabellen- und Kachel-Stil der bestehenden Vorlage bleiben; zusätzlich `--good: #0ca30c`. Helles und dunkles Schema wie bisher.
- **Diagramme:** eine y-Achse je Diagramm; Legende ab zwei Reihen; Text nie in der Farbe einer Reihe; Fadenkreuz mit Tooltip wie bisher. Sichtbarer Ausschnitt nach `WP.zoom`. Bei mehr als 1200 sichtbaren Punkten auf höchstens 600 Abschnitte verdichten: Mittelwert, bei CPU, Eingabeverzögerung und Antwortzeiten das Maximum. Dünne Reihen: fehlende Punkte sind bei der Eingabeverzögerung 0, bei Antwortzeiten eine Lücke. Achsenbeschriftung als `text.xaxis`, mit Sekunden, sobald der Ausschnitt kürzer als 10 Minuten ist. Ziehen mit gedrückter Maustaste über mindestens 10 Pixel setzt den Zoom.
- **Übersicht:** Kacheln für alle Einträge aus `sollIst` (Mittel, P95, Maximum, Symbol und Wort) sowie für die Hauptanwendung, wenn `mainApp` vorhanden ist (`data-signal="mainapp"`), dann auch mit eigenem Verlauf `#chMainApp`. Eine weitere Kachel `.tile.info[data-info="userspercore"]` zeigt „Benutzer je logischer CPU" ohne Bewertung. Gestapelte Diagramme CPU und Arbeitsspeicher nach Sitzung oder Anwendung (sieben größte plus „Sonstige") wie bisher. Host-Diagramme laut Liste in den Interfaces: `#chVolumes` zeigt die fünf Laufwerke mit der höchsten Spitze, `#chShares` alle Freigaben, `#chProbes` alle Gegenstellen, `#chInput` `host.inputMax`.
- **Sitzungen:** zusätzliche Spalten Eingabeverzögerung P95 und Maximum; Detailansicht mit Diagrammen CPU, Working Set, I/O, Eingabeverzögerung (`.chart-input`), ICA Round Trip und, falls vorhanden, Antwortzeit des Profilcontainers.
- **Anwendungen und Prozesse:** Spalte Rolle (`td.role`), Rollenfilter, bei `svchost.exe` die Dienste; die Zeile des Collectors trägt die Klasse `collector` und den Zusatz „(WorkerPerf selbst)".
- Kopfzeile wie bisher, zusätzlich Ende-Grund, wenn er nicht `duration` ist.

- [ ] **Step 4: Prüfung ausführen**

Run: `pwsh -NoProfile -File tests/New-TestReports.ps1 -OutDir /tmp/wp-reports && node tests/report-browser.js /tmp/wp-reports`
Expected: letzte Zeile `browser checks passed: <n>`, Rückgabewert 0

- [ ] **Step 5: Seite ansehen**

Bildschirmfotos der Übersicht in hellem und dunklem Schema und einer Sitzungsansicht mit gesetztem Zoom anfertigen und auf überlappende Beschriftungen, abgeschnittene Legenden und waagerechtes Scrollen der Seite prüfen; Mängel beheben und Step 4 wiederholen.

- [ ] **Step 6: Commit**

```bash
git add src/report-template.html tests/report-browser.js
git commit -m "Rebuild report page on full-resolution data with zoom and target bands"
```

---

### Task 14: Berichtsseite – Befunde

**Files:**
- Modify: `src/report-template.html`, `tests/report-browser.js`, `README.md` (Abschnitt „Der Bericht")

**Interfaces:**
- Consumes: Task 13 (`WP`, `chart`), Berichts-JSON.
- Produces: `#tab-findings` als Startreiter mit `#focusInfo`, `#noFinding`, `#timeline` (`.mark[data-incident]` mit Klasse `sev1`/`sev2` und `chronic`, `.event[data-kind]`, `.reported`), `#incidents` (`.incident[data-id]` mit Klassen `type-engpass`/`type-ohne-engpass`/`type-umfeld`, `focus`, `near`, `chronic`; darin `.text`, `.badge`, aufklappbar `.detail` mit `.affected`, `.contributors`, `.signals`), `#sollist` (`tbody tr[data-id][data-measured]`), `#limits`, `#quality`.

- [ ] **Step 1: Die Browserprüfung erweitern**

In `tests/report-browser.js` die Funktion ergänzen und in der Schleife nach `checkPage` aufrufen; die Zeile mit `ok(... 'fuenf Reiter')` bleibt.

```js
async function checkFindings(browser, dir, scheme) {                // Task 14
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme);
  ok(await page.locator('#tab-findings').isVisible(), 'Befunde ist der Startreiter');
  ok(await page.locator('#incidents .incident').count() === D.incidents.length, 'ein Eintrag je Vorfall');
  ok(await page.locator('#timeline .mark').count() === D.incidents.length, 'eine Markierung je Vorfall');
  ok(await page.locator('#timeline .event').count() === D.events.length, 'Ereignisse in der Zeitleiste');
  ok(!(await page.locator('#noFinding').isVisible()), 'kein Hinweis auf fehlende Befunde');
  const cpu = D.incidents.find((i) => i.lead === 'cpu');
  const entry = page.locator(`#incidents .incident[data-id="${cpu.id}"]`);
  ok((await entry.locator('.text').innerText()).includes('CPU-Engpass'), 'Klartext sichtbar');
  ok((await entry.locator('.badge').innerText()).includes('kritisch'), 'Schwere als Wort');
  await entry.locator('.text').click();
  ok(await entry.locator('.detail .affected li').count() === cpu.affected.length, 'Betroffene aufgelistet');
  ok((await entry.locator('.detail .contributors').innerText()).includes('EXCEL.EXE'), 'Verursacher aufgelistet');
  ok(await entry.locator('.detail svg path').count() > 0, 'Verlauf im Vorfall');
  await page.click(`#timeline .mark[data-incident="${cpu.id}"]`);
  const z = await page.evaluate(() => window.WP.zoom);
  ok(z && z.t0 < cpu.start && z.t1 > cpu.end && z.t1 - z.t0 < (cpu.end - cpu.start) * 3, 'Klick stellt die Diagramme auf das Fenster ein');
  ok(await page.locator('#sollist tbody tr').count() === D.sollIst.length, 'Soll-Ist-Tabelle vollstaendig');
  ok((await page.locator('#sollist tbody tr[data-id="cpu.host"]').innerText()).includes('unter 75 %'), 'Idealbereich genannt');
  ok(await page.locator('#sollist tbody tr[data-id="cpu.host"] a[href]').count() === 1, 'Herkunft verlinkt');
  ok((await page.locator('#quality').innerText()).includes('WorkerPerf'), 'Messqualitaet nennt den Collector');
  ok((await page.locator('#limits').innerText()).includes('SYSTEM'), 'Grenzen der Aussage genannt');
  ok(page.errors.length === 0, 'Skriptfehler: ' + page.errors.join(' | '));
  await page.close();

  const f = await open(browser, path.join(dir, 'report-focus.html'), scheme);
  ok((await f.page.locator('#incidents .incident').first().getAttribute('class')).includes('focus'), 'Vorfall des Benutzers steht vorn');
  ok(await f.page.locator('#timeline .reported').count() === 1, 'gemeldete Uhrzeit markiert');
  ok((await f.page.locator('#focusInfo').innerText()).includes('user003'), 'Fokus genannt');
  await f.page.close();

  const n = await open(browser, path.join(dir, 'report-none.html'), scheme);
  ok(await n.page.locator('#noFinding').isVisible(), 'Hinweis ohne Befund');
  ok((await n.page.locator('#noFinding').innerText()).includes('Keine Schwelle wurde überschritten'), 'ausdrueckliche Aussage');
  ok(await n.page.locator('#incidents .incident').count() === 0, 'keine Vorfaelle');
  ok(n.page.errors.length === 0, 'Skriptfehler ohne Befund: ' + n.page.errors.join(' | '));
  await n.page.close();
}
```

In `checkPage` die Zeile `await page.click('nav button[data-tab=overview]');` beibehalten (die Übersicht ist nicht mehr der Startreiter).

- [ ] **Step 2: Prüfung ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/New-TestReports.ps1 -OutDir /tmp/wp-reports && node tests/report-browser.js /tmp/wp-reports`
Expected: `AssertionError: Befunde ist der Startreiter`

- [ ] **Step 3: Den Reiter „Befunde" bauen**

- **Kopf:** ein Satz mit der Zahl der Vorfälle je Typ. `#focusInfo` nennt Benutzer und gemeldete Uhrzeit oder „Benutzer … in der Messung nicht gefunden".
- **`#noFinding`** (nur bei `noFinding`): „Keine Schwelle wurde überschritten." und darunter zwei Listen aus `sollIst`: gemessene und nicht gemessene Messwerte, letztere mit Grund.
- **Zeitleiste:** ein Balken über die ganze Messung mit Zeitachse; je Vorfall eine Markierung von Beginn bis Ende, mindestens 6 Pixel breit, eingefärbt nach Schwere, mit Symbol; Dauerzustände als schmale Linie in einer eigenen Zeile darunter; Ereignisse als kleine Marken mit Tooltip; die gemeldete Uhrzeit als senkrechte Linie mit Beschriftung. Ein Klick auf eine Markierung ruft `WP.setZoom` mit dem Fenster plus Rand auf (das Größere aus 30 s und einem Viertel der Dauer je Seite) und klappt den Vorfall auf.
- **Vorfallsliste:** Reihenfolge: zuerst `focus`, dann die übrigen nach Beginn; Dauerzustände zuletzt. Je Eintrag: Symbol und Wort der Schwere (`.badge`), Typ, Klartext (`.text`), Kennzeichen „nahe der gemeldeten Uhrzeit" bei `nearReported`. Aufgeklappt (`.detail`): Betroffene mit Spitze (`.affected`, Liste), je Ressource die drei Ranglisten mit Anteil und Normalwert (`.contributors`), beteiligte Signale mit Spitze und Soll (`.signals`), Prozesse mit der höchsten Eingabeverzögerung, Gegenstellen, ICA Round Trip der Betroffenen, Anteile der Schutzprodukte getrennt und als Summe, Ereignisse im Fenster, Dauerzustände im Hintergrund, und ein Diagramm der beteiligten Signale im Fenster. Ein Klick auf einen Benutzer oder Prozess wechselt in den jeweiligen Reiter und wählt die Zeile aus.
- **Soll-Ist-Tabelle:** je Messwert Bezeichnung, Idealbereich, Mittel, P95, Maximum, Zeitanteile als dreiteiliger Balken mit Zahlen, schlechteste Instanz, Herkunft (`origin`, `note`) mit Link auf `url`. Nicht gemessene Zeilen zeigen `○ nicht gemessen` und den Grund.
- **Grenzen der Aussage (`#limits`):** drei feste Hinweise aus Abschnitt 5 der Spezifikation: Bei Datenträgern und Freigaben ist sichtbar, dass ein Ziel langsam antwortet und welche Prozesse viel I/O erzeugen, nicht aber, welcher Prozess auf welche Datei wartet. Die Eingabeverzögerung enthält keine Prozesse, die als SYSTEM laufen. Entzogene CPU-Zeit ist nur verfügbar, wenn die VMware Tools den Zähler bereitstellen.
- **Messqualität:** ausgelassene Takte, Messdauer je Takt und je Schnappschuss, Zeit in der Verdichtung, Anteil von WorkerPerf selbst an der CPU-Zeit, Liste der Quellen mit Verfügbarkeit.

- [ ] **Step 4: Prüfung ausführen**

Run: `pwsh -NoProfile -File tests/New-TestReports.ps1 -OutDir /tmp/wp-reports && node tests/report-browser.js /tmp/wp-reports`
Expected: letzte Zeile `browser checks passed: <n>`, Rückgabewert 0

- [ ] **Step 5: Seite ansehen**

Bildschirmfotos des Reiters „Befunde" in beiden Schemata, mit aufgeklapptem CPU-Vorfall, im Fokus-Bericht und im Bericht ohne Befund; auf Lesbarkeit der Zeitleiste bei dicht liegenden Vorfällen, Zeilenumbrüche im Klartext und Tabellenbreite prüfen; Mängel beheben und Step 4 wiederholen.

- [ ] **Step 6: README anpassen und alle Tests ausführen**

README-Abschnitt „Der Bericht": Reiter „Befunde" mit Zeitleiste, Vorfallstypen, Soll-Ist-Tabelle und Fokus beschreiben; Lesehilfe um Eingabeverzögerung, Dauerzustand und Begleiter ergänzen.

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 7: Commit**

```bash
git add src/report-template.html tests/report-browser.js README.md
git commit -m "Add findings page with timeline, incidents and target table"
```

---

### Task 15: Datenquelle Windows

**Voraussetzung:** Das Ergebnis des Prüfskripts von einem echten VDA liegt als `docs/vda-probe/<Datei>.json` vor. Ohne diese Datei wird die Task nicht begonnen.

**Files:**
- Modify: `src/WorkerPerf.Sources.Windows.ps1`, `README.md` (Abschnitt „Datenquellen"), `docs/superpowers/specs/2026-11-10-engpassanalyse-design.md` (Tabelle in Abschnitt 5), `src/roles.json`
- Test: `tests/WindowsSource.Tests.ps1`

**Interfaces:**
- Consumes: die in Task 8 verschobenen Funktionen, die Zählertabelle aus Task 1, den schnellen Messwert aus Task 6.
- Produces: alle Funktionen der Schnittstelle aus Task 7 außer `Get-WorkerPerfExpected`, dazu die unter Linux testbaren Helfer:

```powershell
function ConvertFrom-WorkerPerfInputInstance([string]$Instance)     # -> @{ SessionId; Pid; Name } oder $null
function Resolve-WorkerPerfProfileOwner { param([string[]]$Paths, [object[]]$Sessions) }   # -> Sitzungs-ID oder $null
function ConvertTo-WorkerPerfEventKind([string]$Source, [int]$EventId)   # -> Art oder $null
```

- [ ] **Step 1: Prüfergebnis einarbeiten**

Für jede `perf.*`-Prüfung in der JSON-Datei: Ist `Ok` wahr, gelten die Namen der Tabelle aus Task 1. Weicht ein Name ab, die Tabelle in Abschnitt 5 der Spezifikation und die Zuordnung in dieser Datei korrigieren. Fehlt eine Kategorie, wird das Signal als nicht verfügbar gemeldet (`Sources[id].Available = $false` mit Grund). **Abbruchbedingung:** Liefert der .NET-Weg für `perf.cpu`, `perf.memory` oder `perf.volumes` keine Werte, der CIM-Weg aber schon, diese Task anhalten und den Plan für den CIM-Weg überarbeiten. Aus `security.products` und `user.processes` die Prozessnamen für Arctic Wolf Aurora, Nexus KIS und den Oracle-Client in `src/roles.json` eintragen. Aus `perf.input.session` ablesen, ob der Zähler bei Abfrage alle 2 s das Maximum beider Sekunden liefert; wenn nicht, den Standard von `-FastIntervalSeconds` auf 1 setzen und das im README begründen. Aus `perf.steal` Zählertyp und Einheit für die Umrechnung entnehmen. Aus `profile.volumes` ablesen, ob `Location` oder `AccessPaths` den Benutzer nennen.

- [ ] **Step 2: Den fehlschlagenden Test schreiben**

```powershell
BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Sources.Windows.ps1')
}
Describe 'Windows-Datenquelle: plattformunabhaengige Teile' {
    It 'laesst sich einbinden, ohne etwas auszufuehren' { Get-Command Initialize-WorkerPerfSource, Get-WorkerPerfFastSample, Receive-WorkerPerfProbes | Should -HaveCount 3 }
    It 'zerlegt Instanznamen der Eingabeverzoegerung' {
        $a = ConvertFrom-WorkerPerfInputInstance '1:4232 <Calculator.exe>'
        $a.SessionId | Should -Be 1; $a.Pid | Should -Be 4232; $a.Name | Should -Be 'Calculator.exe'
        (ConvertFrom-WorkerPerfInputInstance 'explorer <3:7964>').Pid | Should -Be 7964
        ConvertFrom-WorkerPerfInputInstance 'Max' | Should -BeNullOrEmpty; ConvertFrom-WorkerPerfInputInstance 'Average' | Should -BeNullOrEmpty
    }
    It 'ordnet einen Profilcontainer dem Benutzer im Pfad zu' {
        $s = @([pscustomobject]@{ SessionId = 5; User = 'mueller' }, [pscustomobject]@{ SessionId = 6; User = 'mu' })
        Resolve-WorkerPerfProfileOwner -Paths @('\\fs01\upm$\Mueller.KLINIK\Win2022\ProfileContainer.vhdx') -Sessions $s | Should -Be 5
        Resolve-WorkerPerfProfileOwner -Paths @('\\fs01\upm$\gast\ProfileContainer.vhdx') -Sessions $s | Should -BeNullOrEmpty
    }
    It 'bildet Ereigniskennungen auf Arten ab' {
        ConvertTo-WorkerPerfEventKind 'Defender' 1000 | Should -Be 'scan-start'
        ConvertTo-WorkerPerfEventKind 'Defender' 1001 | Should -Be 'scan-end'; ConvertTo-WorkerPerfEventKind 'Defender' 1002 | Should -Be 'scan-end'
        ConvertTo-WorkerPerfEventKind 'Defender' 2000 | Should -Be 'signature-update'
        ConvertTo-WorkerPerfEventKind 'AppLocker' 8004 | Should -Be 'applocker-block'; ConvertTo-WorkerPerfEventKind 'AppLocker' 8007 | Should -Be 'applocker-block'
        ConvertTo-WorkerPerfEventKind 'AppLocker' 8002 | Should -BeNullOrEmpty
    }
    It 'misst Verbindungen gleichzeitig und ohne zu blockieren' {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $listener.Start()
        try {
            $port = $listener.LocalEndpoint.Port
            $list = @([pscustomobject]@{ Name = 'offen'; Role = 'x'; Host = '127.0.0.1'; Port = $port },
                                            [pscustomobject]@{ Name = 'zu'; Role = 'x'; Host = '127.0.0.1'; Port = 1 },
                                            [pscustomobject]@{ Name = 'fehlt'; Role = 'x'; Host = 'nohost.invalid'; Port = 80 })
            $sw = [Diagnostics.Stopwatch]::StartNew(); Start-WorkerPerfProbes -Endpoints $list; $sw.ElapsedMilliseconds | Should -BeLessThan 500
            $r = $null; while ($null -eq $r -and $sw.ElapsedMilliseconds -lt 4000) { Start-Sleep -Milliseconds 100; $r = Receive-WorkerPerfProbes }
            @($r).Count | Should -Be 3
            ($r | Where-Object Name -eq 'offen').Error | Should -BeNullOrEmpty; ($r | Where-Object Name -eq 'offen').ConnectMs | Should -BeLessThan 1000
            ($r | Where-Object Name -eq 'zu').Error | Should -Not -BeNullOrEmpty; ($r | Where-Object Name -eq 'fehlt').Error | Should -Not -BeNullOrEmpty
        }
        finally { $listener.Stop() }
    }
}
```

- [ ] **Step 3: Test ausführen und Fehlschlag prüfen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/WindowsSource.Tests.ps1`
Expected: FAIL, `Initialize-WorkerPerfSource` nicht definiert

- [ ] **Step 4: Die Datenquelle implementieren**

- **Initialisierung:** Warnung ohne erhöhte Rechte; WTS-C# kompilieren; Eckdaten aus `Win32_ComputerSystem` und `Win32_OperatingSystem`; `CollectorPid = $PID`; je Signal prüfen, ob Kategorie und Zähler vorhanden sind, und `Sources` füllen; Gegenstellen für `Start-WorkerPerfProbes` merken.
- **Leistungsindikatoren:** je Kategorie ein `PerformanceCounterCategory`-Objekt; je Takt `ReadCategory()` und der Wert über `[System.Diagnostics.CounterSample]::Calculate(vorher, jetzt)`. Ein Fehler in einer Kategorie erzeugt eine einmalige Warnung und `$null` für ihre Werte, die Messung läuft weiter.
- **Schneller Messwert:** Host-Werte laut Zählertabelle; Antwortzeiten in ms; `ReadOps`/`WriteOps` als Rate mal vergangene Sekunden; Laufwerke ohne `_Total`. `StealPct` nach dem in Step 1 ermittelten Zählertyp.
- **Profilcontainer:** Zuordnung Laufwerksinstanz → Art und Sitzung über `MSFT_Disk` mit `BusType` 15, deren Partitionen und `Resolve-WorkerPerfProfileOwner`; neu aufbauen an jedem Stützpunkt und sobald eine unbekannte Laufwerksinstanz erscheint. Ohne Zuordnung zum Benutzer `Kind = 'profile'` und `SessionId = $null`. `Backing` ist der Teil `\\server\share` des Containerpfads, soweit bekannt.
- **Schnappschuss:** `Get-WinProcessRaw`, `Get-WinSessionRaw`, `Get-WinCitrixRaw` aus Task 8.
- **Dienste:** `Win32_Service` mit `ProcessId` größer 0.
- **Proben:** C#-Klasse `WorkerPerf.Probe` mit `TcpClient.BeginConnect`, Stoppuhr je Verbindung und Zeitlimit 2000 ms; `Start` kehrt sofort zurück, `Receive` liefert erst, wenn alle Verbindungen beendet oder abgelaufen sind. Fehlertexte kurz: `timeout`, `refused`, `dns`, sonst der Name der Ausnahme.
- **Ereignisse:** `Get-WinEvent -FilterHashtable` mit `StartTime` auf den Protokollen aus Task 1, höchstens 200 je Abruf, Text auf die erste Zeile und 200 Zeichen gekürzt. Nicht lesbare Protokolle: einmalige Warnung.
- **Warten:** in Schritten von höchstens 500 ms bis `Until`, dabei auf die Stopp-Datei prüfen.
- **Freier Platz:** `[System.IO.DriveInfo]` des Laufwerks von `Path`.

- [ ] **Step 5: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 6: README und Spezifikation nachziehen**

README-Abschnitt „Datenquellen": Tabelle der Quellen mit den geprüften Namen und dem Hinweis, welche Signale auf dem geprüften VDA nicht verfügbar waren. In Abschnitt 5 der Spezifikation die Spalte „Status" mit dem Ergebnis des Prüfskripts füllen.

- [ ] **Step 7: Commit**

```bash
git add src/WorkerPerf.Sources.Windows.ps1 src/roles.json tests/WindowsSource.Tests.ps1 README.md docs/superpowers/specs/2026-11-10-engpassanalyse-design.md
git commit -m "Wire Windows data source to verified performance counters"
```

---

## Nach dem Plan

Diese Schritte brauchen einen echten VDA und liegen beim Auftraggeber; sie entsprechen Schritt 5 der Spezifikation.

1. **Kurzmessung:** `Start-WorkerPerfCapture.ps1 -DurationMinutes 10` mit erhöhten Rechten auf einem Worker mit angemeldeten Benutzern, danach `New-WorkerPerfReport.ps1`. Geprüft wird: keine Warnungen zu Datenquellen, die laut Prüfskript vorhanden sind; `ticks.csv` enthält Werte in jeder verfügbaren Spalte; der Bericht öffnet ohne Fehler; unter „Messqualität" liegt die Messdauer je Schnappschuss deutlich unter dem schnellen Takt.
2. **Datenmenge:** Größe des Ordners auf acht Stunden hochrechnen und mit dem Ziel von 100 MB vergleichen (Erfolgskriterium 2 der Spezifikation). Bei Überschreitung zuerst den langsamen Takt vergrößern.
3. **Schwellen nachstellen:** Soll-Ist-Tabelle einer Messung ohne gemeldete Störung durchsehen. Signale, die ohne spürbare Störung dauerhaft „auffällig" sind, in `thresholds.json` anheben; zu erwarten ist das vor allem bei `mem.pagesin`. Microsoft nennt im Leitfaden „Troubleshoot performance problems in Windows" für Datenträger 15/25/50 ms; das ist eine Alternative zu den Startwerten 10/20 ms.
4. **Gegenstellen und Rollen:** `endpoints.json` anlegen, Rollen mit den Prozessnamen aus dem Prüfskript ergänzen.
