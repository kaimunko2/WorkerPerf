# Ereignisse, Abstürze und Drucken – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** WorkerPerf zeichnet Ereignisse aus Anwendung, System, Druckdienst, SMB-Client, Profildienst und Sitzungsverwaltung samt Rückblick, Treiberliste und Warteschlangenzählern auf, bildet daraus eigene Vorfälle mit Mustern und zeigt sie im heutigen Bericht.

**Architecture:** Welche Ereignisse wie zu lesen sind, steht in `src/events.json`; Laden, Prüfen und die Umsetzung eines Rohereignisses in einen Datensatz liegen in `src/WorkerPerf.EventConfig.ps1` (gemeinsam für Collector und Auswertung). Der Collector schreibt Format 3 (`events.csv` mit strukturierten Spalten, `events_before.csv`, `printdrivers.csv`, `printqueues.csv`); die Auswertung liest Format 2 und 3. Zusammenfassen, Muster, Rückblick und Druckzustand liegen in der neuen Datei `src/WorkerPerf.Events.ps1`; `WorkerPerf.Load.ps1`, `WorkerPerf.Findings.ps1` und `New-WorkerPerfReport.ps1` erhalten nur die Verdrahtung. Die Windows-Datenquelle wird zuletzt umgestellt, auf Grundlage des Prüfergebnisses vom Zielserver.

**Tech Stack:** Windows PowerShell 5.1 (Laufzeit), C# 5 über `Add-Type` (nur wo schon vorhanden), HTML/CSS/JavaScript ohne Bibliotheken. Tests: PowerShell 7 mit Pester 5, Node.js mit Playwright.

**Spec:** `docs/superpowers/specs/2026-11-11-ereignisse-abstuerze-drucken-design.md` (baut auf `docs/superpowers/specs/2026-11-10-engpassanalyse-design.md` auf).

## Global Constraints

- **Windows PowerShell 5.1:** jede `src/*.ps1` beginnt mit `#Requires -Version 5.1`, ist reines ASCII (Umlaute nur in JSON-Textdateien und `src/report-template.html`), ohne PowerShell-7-Syntax und ohne API, die es nur unter .NET Core gibt; eingebettetes C# auf Stand C# 5. `tests/Compat.Tests.ps1` erzwingt einen Teil davon und prüft neue Dateien unter `src/` automatisch.
- **Tests unter Linux:** PowerShell 7, Pester 5, Node/Playwright. Windows-Aufrufe bleiben dünn und werden über Platzhalter getestet (`tests/WindowsStandIns.ps1`). Alle Tests: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"` (heute 311 bestanden, 1 übersprungen). Browserprüfungen: `pwsh -NoProfile -File tests/New-TestReports.ps1 -OutDir /tmp/wp-reports && node tests/report-browser.js /tmp/wp-reports`, Erfolg: letzte Zeile `browser checks passed: <n>`, Rückgabewert 0.
- **Listen:** Funktionen, die Listen liefern, geben schlichte Pipeline-Ausgabe; Aufrufer schreiben `@(...)`.
- **Bericht:** eine einzelne HTML-Datei ohne externe Anfragen, ohne eingebundene Bibliotheken oder Schriften; Status immer als Symbol und Wort; deutsche Texte aus JSON-Dateien (`src/texts.de.json`, `src/events.json`), nicht aus dem Code.
- **Collector liest nur:** keine Einstellung des Servers wird geändert, kein Protokoll eingeschaltet. Ein Aufruf der Quelle, der scheitert, wird übersprungen, je Quelle einmal gewarnt und in `meta.json` (`SourceErrors`) vermerkt.
- **Öffentliches Repository:** keine Daten eines echten Servers im Repository (keine Software-Liste, Freigaben-, Benutzer-, Client- oder Servernamen, keine Ereignistexte); Tests verwenden erfundene Namen. Aufzeichnungen, Berichte und Ergebnisse des Prüfskripts werden nicht eingecheckt.
- **Bestand:** die acht Vorfälle der simulierten Stunde und alle bestehenden Tests bleiben grün, außer eine Task nennt genau, welche Aussage sich ändert und warum.
- **TDD:** jede Task schreibt zuerst den fehlschlagenden Test.
- **Commits:** englisch, im Imperativ, ein Commit je Task; keine Modellnamen in Code, Kommentaren oder Dokumenten.
- **Werte der Spezifikation:** Meldungstext erste Zeile, höchstens 300 Zeichen; `-EventLookbackDays` Standard 7, 0 schaltet ab; `eventGroupMinutes` 30; Abstand `resource` 5 min, `afterhang` 2 min, `companion` 2 min; `manyusers` ab 3 Benutzern; `oneuser` ab 3 Ereignissen; gemeldete Zeit vor der Messung: Umkreis 15 min. Die Zeitabstände stehen in `src/thresholds.json`.

## Review Focus

Jede Zeile ist durch einen Test in der genannten Task abgesichert (im Testcode mit `# Review Focus n` markiert).

1. **Ein Ereignis hat andere oder fehlende Datenfelder** (anderer Patch-Stand, unbenannte Datenfelder, unbekannte Quelle). Erwartet: das Ereignis wird mit Gruppe und Art aus `events.json` und leeren Feldern geschrieben; nichts bricht ab. → Task 2
2. **Ein Hintergrunddienst stürzt in der Messung hundertfach ab.** Erwartet: ein Vorfall mit der vollen Anzahl, höchstens 50 Einzelereignisse im Vorfall, der Bericht bleibt klein. → Task 5
3. **Rückblick und Messzeit überschneiden sich** (Ereignisse genau zum Start, Uhr des Servers springt). Erwartet: jedes Ereignis zählt genau einmal, im Rückblick nur Ereignisse vor dem ersten Takt. → Tasks 3, 7
4. **Der abgestürzte Prozess ist in keinem Schnappschuss** (gestartet und beendet zwischen zwei Schnappschüssen, PID inzwischen neu vergeben). Erwartet: keine falsche Sitzung; ohne Sitzung aus dem Ereignis bleibt sie leer. → Task 3
5. **Eine eigene `thresholds.json` ohne den Block `events`** (Kopie aus einer älteren Version). Erwartet: Standardwerte; ein vorhandener, falscher Wert bricht mit Feldname ab. → Task 5

## File Structure

| Datei | Verantwortung |
|---|---|
| `src/Test-WorkerPerfSources.ps1` | neue Prüfungen der Ereignisprotokolle, Druckertreiber und Warteschlangenzähler |
| `src/events.json` (neu) | Protokolle, Quellen, Kennungen → Gruppe, Art, strukturierte Felder; wichtige Dienste, Druckprozesse, allgemeine Systemmodule, Fehlercodes |
| `src/WorkerPerf.EventConfig.ps1` (neu) | `events.json` laden und prüfen, Rohereignis → Datensatz, Einstellungen aus `thresholds.json` |
| `src/WorkerPerf.Common.ps1` | Formatversion 3, lesbare Formate, Kopfzeilen der neuen Dateien, Rolle `Drucken` |
| `src/WorkerPerf.Capture.ps1` | Zeilen der neuen Dateien, Sitzung über die PID ergänzen |
| `src/Start-WorkerPerfCapture.ps1` | `-EventLookbackDays`, Rückblick und Treiberliste beim Start, Warteschlangen je regulärem Schnappschuss |
| `src/WorkerPerf.Sources.Simulation.ps1` | neue Schnittstelle, zusätzliche Szenen, `expected.json` |
| `src/WorkerPerf.Sources.Windows.ps1` | neue Schnittstelle (zuerst leer, in Task 10 vollständig) |
| `src/WorkerPerf.Events.ps1` (neu) | Ereignisdateien lesen, Sitzungen zuordnen, Vorfälle, Muster, Text, Rückblick, Druckzustand, Ausgabe für die Berichtsdaten |
| `src/WorkerPerf.Load.ps1`, `src/WorkerPerf.Findings.ps1`, `src/New-WorkerPerfReport.ps1` | nur Verdrahtung |
| `src/thresholds.json`, `src/roles.json`, `src/texts.de.json` | Block `events`, Rolle `Drucken` und Feld `modules`, Texte |
| `src/report-template.html` | Anzeige im heutigen Bericht |
| `tests/Events.Tests.ps1` (neu), bestehende Testdateien | Tests |

Reihenfolge: Task 1 liefert das erweiterte Prüfskript; danach läuft es beim Auftraggeber auf dem Zielserver. Die Tasks 2–9 warten nicht darauf. Task 10 setzt das Prüfergebnis voraus.

---

### Task 1: Prüfskript – Ereignisprotokolle und Drucken

**Files:**
- Modify: `src/Test-WorkerPerfSources.ps1` (Katalog ab Zeile 1218, Ereignisprüfung Zeilen 1057–1101, `SchemaVersion` Zeile 1356), `docs/vda-probe/README.md`, `.gitignore` (letzte Zeile), `README.md` (Abschnitt „Datenschutz", Satz „darf die Datei unter `docs/vda-probe/` abgelegt werden")
- Test: `tests/Sources.Tests.ps1`

**Interfaces:**
- Produces (Task 10 liest das Ergebnis):
  - Prüfungen `events.application`, `events.system`, `events.printservice`, `events.smbclient`, `events.profileservice`, `events.session` (neu) und `events.defender`, `events.applocker` (bisher) laufen alle über `Invoke-ProbeEventsCheck`. Katalogfelder: `Logs` (Protokollnamen), `Providers` (Namen oder Muster mit `*`, leer = alle), `Levels` (leer = alle), `EventIds` (leer = alle).
  - `Get-ProbeEventFieldNames([string]$Xml) -> string[]`: Namen der Datenfelder eines Ereignisses: `EventData/Data/@Name`, für unbenannte Felder `#0`, `#1` …, die Kindelemente unter `UserData/*` mit ihrem lokalen Namen, `binary` wenn `EventData/Binary` vorhanden ist.
  - `Get-ProbeEventSummary([object[]]$Events) -> object[]`: je Quelle und Kennung `[ordered]@{ Provider; Id; Count; Fields = string[] }` (Felder des ersten Ereignisses), sortiert nach Quelle, Kennung.
  - `Data` einer Ereignisprüfung: `[ordered]@{ Days = 7; MaxEvents; Logs = @( [ordered]@{ Log; Exists; Enabled; Readable; Capped; Error; Ids = <Get-ProbeEventSummary> } ) }`.
  - `print.drivers`: `Get-ProbeDriverSummary([object[]]$Drivers, $IsolationGroups) -> ordered` mit `Count`, `ByManufacturer` (Hersteller → Anzahl), `ByType` (`3`/`4`/`unbekannt` → Anzahl), `ByIsolation` (`none`/`shared`/`isolated`/`unbekannt` → Anzahl), `PropertyNames` (Eigenschaften von `MSFT_PrinterDriver`), `IsolationSource`. Quellen: `Get-CimInstance -Namespace root/StandardCimv2 -ClassName MSFT_PrinterDriver`, Wert `PrintDriverIsolationGroups` unter `HKLM:\SYSTEM\CurrentControlSet\Control\Print` (Gruppen durch `\\` getrennt, Treiber einer Gruppe durch `\`; erste Gruppe läuft im Druckdienst = `none`, zweite = `shared`, weitere = `isolated`), dazu die Namen (nicht die Werte) der Registrierungswerte unter dem Schlüssel eines Treibers.
  - `print.queues`: `Invoke-ProbePerfCheck` mit `Perf = @{ Category = 'Print Queue'; Counters = @('Jobs', 'Job Errors', 'Not Ready Errors'); Instances = 'total'; MaxInstances = 0 }` – nur `_Total`, damit kein Druckername im Ergebnis steht.
  - `SchemaVersion` des Ergebnisses: 3.

| Check-Id | Logs | Providers | Levels | EventIds |
|---|---|---|---|---|
| `events.application` | `Application` | `Application Error`, `Application Hang`, `.NET Runtime`, `Windows Error Reporting`, `Microsoft-Windows-User Profiles Service`, `Citrix*` | – | – |
| `events.system` | `System` | `Service Control Manager`, `disk`, `Ntfs`, `Microsoft-Windows-Ntfs`, `volmgr`, `storvsc`, `Microsoft-Windows-Resource-Exhaustion-Detector`, `Citrix*` | 1, 2, 3 | – |
| `events.printservice` | `Microsoft-Windows-PrintService/Admin`, `Microsoft-Windows-PrintService/Operational` | – | – | – |
| `events.smbclient` | `Microsoft-Windows-SMBClient/Connectivity`, `Microsoft-Windows-SMBClient/Operational` | – | 1, 2, 3 | – |
| `events.profileservice` | `Microsoft-Windows-User Profile Service/Operational` | – | 1, 2, 3 | – |
| `events.session` | `Microsoft-Windows-TerminalServices-LocalSessionManager/Operational` | – | – | 21, 23, 24, 25 |
| `events.defender` | wie bisher | – | – | 1000, 1001, 1002, 2000 |
| `events.applocker` | wie bisher | – | – | 8004, 8007 |

Muster mit `*` werden über `Get-WinEvent -ListProvider` in Namen aufgelöst. Ausgegeben werden nur Anzahlen, Kennungen, Quellen- und Feldnamen; keine Meldungstexte, keine Feldwerte, keine Treiber- oder Druckernamen. Alles läuft weiterhin durch die eine Maskierung am Ende.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (in `tests/Sources.Tests.ps1`; die drei neuen Funktionsnamen in die Liste der Hilfsfunktionen in `BeforeAll` aufnehmen)

```powershell
It 'listet die Pruefungen ohne Systemzugriff' {
    $Checks.Id | Should -Be @('system', 'process.snapshot', 'sessions.wts', 'services.map', 'perf.cpu', 'perf.queue', 'perf.steal', 'perf.memory',
        'perf.disk.total', 'perf.network', 'perf.volumes', 'perf.shares', 'perf.input.session', 'perf.input.process', 'perf.ica',
        'profile.volumes', 'events.defender', 'events.applocker', 'events.application', 'events.system', 'events.printservice',
        'events.smbclient', 'events.profileservice', 'events.session', 'print.drivers', 'print.queues', 'security.products', 'user.processes', 'endpoints')
}
Describe 'Ereignisse und Drucken im Pruefskript' {
    It 'nennt die Namen der Datenfelder, nie ihre Werte' {
        $x = "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><System><Provider Name='Application Error'/><EventID>1000</EventID></System>" +
             "<EventData><Data Name='AppName'>geheim.exe</Data><Data Name='ModuleName'>geheim.dll</Data></EventData></Event>"
        Get-ProbeEventFieldNames $x | Should -Be @('AppName', 'ModuleName')
        Get-ProbeEventFieldNames ($x -replace " Name='\w+'", '') | Should -Be @('#0', '#1')
        $u = "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><UserData><EventXML xmlns='x'><User>KLINIK\mueller</User><SessionID>3</SessionID></EventXML></UserData></Event>"
        Get-ProbeEventFieldNames $u | Should -Be @('User', 'SessionID')
    }
    It 'zaehlt je Quelle und Kennung ohne Meldungstext' {
        $ev = foreach ($k in 1..3) { $o = [pscustomobject]@{ ProviderName = 'Application Error'; Id = 1000; Message = 'geheimer Text' }
            $o | Add-Member ScriptMethod ToXml { "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><EventData><Data Name='AppName'>geheim.exe</Data></EventData></Event>" }; $o }
        $s = @(Get-ProbeEventSummary @($ev))
        $s.Count | Should -Be 1; $s[0].Provider | Should -Be 'Application Error'; $s[0].Id | Should -Be 1000; $s[0].Count | Should -Be 3; $s[0].Fields | Should -Be @('AppName')
        ($s | ConvertTo-Json -Depth 5) | Should -Not -Match 'geheim'
    }
    It 'fasst Druckertreiber nach Hersteller, Bauart und Isolierung zusammen, ohne Treibernamen' {
        $d = @([pscustomobject]@{ Name = 'Treiber A'; Manufacturer = 'HP'; MajorVersion = 3 }, [pscustomobject]@{ Name = 'Treiber B'; Manufacturer = 'HP'; MajorVersion = 4 },
               [pscustomobject]@{ Name = 'Treiber C'; Manufacturer = 'Kyocera'; MajorVersion = 3 })
        $r = Get-ProbeDriverSummary $d 'Treiber A\\Treiber B\\Treiber C'
        $r.Count | Should -Be 3; $r.ByManufacturer['HP'] | Should -Be 2; $r.ByType['3'] | Should -Be 2; $r.ByType['4'] | Should -Be 1
        $r.ByIsolation['none'] | Should -Be 1; $r.ByIsolation['shared'] | Should -Be 1; $r.ByIsolation['isolated'] | Should -Be 1
        ($r | ConvertTo-Json -Depth 5) | Should -Not -Match 'Treiber'
    }
}
```

Die Prüfung im Ablauf mit nachgestellten Quellen (`'schreibt eine Datei ohne Namen …'`) ändert eine Aussage: `$r.SchemaVersion | Should -Be 3` statt `2`, weil sich der Aufbau der Ereignisprüfungen ändert.

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Sources.Tests.ps1 -Output Minimal"`
Expected: FAIL, `Get-ProbeEventFieldNames` nicht definiert und die Liste der Prüfungen weicht ab

- [ ] **Step 3: Prüfungen umsetzen**

`Get-ProbeEventCounts` wird zu `Get-ProbeEventLog([string]$Log, [string[]]$Providers, [int[]]$Levels, [int[]]$Ids)` mit der Struktur aus den Interfaces; `Get-WinEvent -FilterHashtable` mit `StartTime` = jetzt minus 7 Tage und höchstens `$script:ProbeMaxEvents` Ereignissen je Protokoll; ein nicht vorhandenes oder abgeschaltetes Protokoll wird mit `Exists`/`Enabled` gemeldet, nicht eingeschaltet. `Invoke-ProbePrintDriversCheck($Ctx, $Check)` ruft die CIM-Klasse und den Registrierungswert und gibt `Get-ProbeDriverSummary` als `Data`. `.gitignore`: Zeile `vda-probe_*.json` und den Kommentar ersetzen („Ergebnisse des Prüfskripts werden nicht eingecheckt"); README und `docs/vda-probe/README.md` entsprechend, dazu in `docs/vda-probe/README.md` ein Absatz zu den neuen Prüfungen und zur Dauer.

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/Test-WorkerPerfSources.ps1 tests/Sources.Tests.ps1 docs/vda-probe/README.md README.md .gitignore
git commit -m "Probe event logs, printer drivers and print queue counters"
```

**Danach:** Der Auftraggeber führt das Prüfskript während des Betriebs auf dem Zielserver aus und lädt das Ergebnis in die Sitzung hoch. Es wird nicht eingecheckt.

---

### Task 2: `events.json` und Umsetzung der Rohereignisse

**Files:**
- Create: `src/events.json`, `src/WorkerPerf.EventConfig.ps1`, `tests/Events.Tests.ps1`

**Interfaces:**
- Produces:
  - `Read-WorkerPerfEventConfig([string]$Path) -> hashtable` `@{ Logs = [ordered] Id -> @{ Id; Names = string[]; Lookback = bool }; Entries = object[]; ImportantServices; SystemModules; PrintProcesses; PrintServices = string[]; ErrorCodes = hashtable (Code → Text) }`. Fehler: `throw "events.json: Eintrag <n> (<provider> <ids>): Feld '<feld>' <Grund>."` mit `n` ab 1.
  - `Resolve-WorkerPerfEventEntry($Config, [string]$LogId, [string]$Provider, [int]$EventId) -> Eintrag | $null` (Quelle ohne Rücksicht auf Groß- und Kleinschreibung).
  - `ConvertFrom-WorkerPerfEventXml([string]$Xml) -> @{ Provider; EventId; Level; Named = Hashtable (Name → Wert, Schreibweise egal); Positional = string[]; Binary = string }`; liest `EventData/Data` und die Kindelemente von `UserData/*`.
  - `ConvertTo-WorkerPerfEventRecord($Entry, $Parsed, [datetime]$Time, [string]$Message) -> pscustomobject` mit `Time, Log, Source, EventId, Level, Group, Kind, App, AppVersion, Module, ModuleVersion, Code, Pid, SessionId, User, Printer, Driver, Service, Object, Text`. Ein Feldverweis ist ein Datenname, `#n` (Position ab 0) oder `binary:utf16` (Binärteil als UTF-16LE-Text). Fehlende Felder sind `''`, `Pid` und `SessionId` sind `[int]` oder `$null` (`0x1f2c` und `8012` werden gelesen). `User` ohne Domänenteil (`KLINIK\mueller` → `mueller`). `Code` über `Format-WorkerPerfErrorCode`. `Text` über `Get-WorkerPerfEventText`.
  - `Format-WorkerPerfErrorCode([string]$Code) -> string`: Hexadezimalwert als `0x` plus acht Kleinbuchstaben (`c0000005`, `0xC0000005`, `3221225477` → `0xc0000005`); anderer Text unverändert.
  - `Get-WorkerPerfEventText([string]$Text) -> string`: erste Zeile, höchstens 300 Zeichen.
- Aufbau von `src/events.json`:

```json
{
  "logs": [ { "id": "application", "names": ["Application"], "lookback": true }, … ],
  "events": [ { "log": "application", "provider": "Application Error", "ids": [1000], "group": "app", "kind": "crash",
                "fields": { "app": "AppName", "appVersion": "AppVersion", "module": "ModuleName", "moduleVersion": "ModuleVersion", "code": "ExceptionCode", "pid": "ProcessId" } }, … ],
  "importantServices": ["Spooler", "ctxProfile", "BrokerAgent", "CitrixPrintManagerService"],
  "printProcesses": ["spoolsv.exe", "PrintIsolationHost.exe"],
  "printServices": ["Spooler"],
  "systemModules": ["ntdll.dll", "KERNELBASE.dll", "kernel32.dll", "ucrtbase.dll", "msvcrt.dll", "combase.dll", "user32.dll", "clr.dll", "coreclr.dll"],
  "errorCodes": [ { "code": "0xc0000005", "text": "Zugriffsverletzung" }, … ]
}
```

  - Erlaubte Gruppen: `app`, `service`, `storage`, `memory`, `fileserver`, `profile`, `print`, `session`, `security`. Erlaubte Arten: `crash`, `hang`, `app-detail`, `service`, `print`, `profileerror`, `system`, `logon`, `logoff`, `disconnect`, `reconnect`, `scan-start`, `scan-end`, `signature-update`, `applocker-block`, `info`. Erlaubte Feldschlüssel: `app`, `appVersion`, `module`, `moduleVersion`, `code`, `pid`, `session`, `user`, `printer`, `driver`, `service`, `object`. Pflichtfelder je Eintrag: `log` (bekannte Id), `provider`, `ids` (mindestens eine), `group`, `kind`; `fields` darf fehlen. Doppelte Kombination aus Protokoll, Quelle und Kennung ist ein Fehler.
  - Protokolle: `application` (`Application`), `system` (`System`), `printservice` (`Microsoft-Windows-PrintService/Admin`), `smbclient` (`Microsoft-Windows-SMBClient/Connectivity`), `profileservice` (`Microsoft-Windows-User Profile Service/Operational`), `session` (`Microsoft-Windows-TerminalServices-LocalSessionManager/Operational`, `lookback: false`), `defender` (`Microsoft-Windows-Windows Defender/Operational`), `applocker` (`Microsoft-Windows-AppLocker/EXE and DLL`, `Microsoft-Windows-AppLocker/MSI and Script`).
  - Einträge, Stand vor dem Prüfergebnis: `Application Error` 1000 crash; `Application Hang` 1002 hang (`app: "#0"`, `appVersion: "#1"`, `pid: "#2"`); `.NET Runtime` 1026 und `Windows Error Reporting` 1001 `app-detail`; `Microsoft-Windows-User Profiles Service` 1500, 1502, 1508, 1511, 1515, 1533 profile/profileerror; `Service Control Manager` 7031, 7034 service/service (`service: "binary:utf16"`); `disk` 7, 11, 51, 153 und `Ntfs` 55, 98, 137, 140 storage/system (`object: "#0"`); `Microsoft-Windows-Resource-Exhaustion-Detector` 2004 memory/system; `Microsoft-Windows-PrintService` 372, 808, 6161 print/print; `Microsoft-Windows-SMBClient` 30803, 30804, 30805, 30806, 30807 fileserver/system (`object: "ServerName"`); `Microsoft-Windows-TerminalServices-LocalSessionManager` 21 logon, 23 logoff, 24 disconnect, 25 reconnect (`user: "User"`, `session: "SessionID"`); Defender 1000 scan-start, 1001/1002 scan-end, 2000 signature-update und AppLocker 8004/8007 applocker-block in der Gruppe `security` (Quellen `Microsoft-Windows-Windows Defender`, `Microsoft-Windows-AppLocker`).
  - Fehlercodes: `0xc0000005` Zugriffsverletzung, `0xc00000fd` Stapelüberlauf, `0xc0000017` Speicheranforderung fehlgeschlagen, `0xc0000409` Pufferüberlauf erkannt, Programm vom System beendet, `0xc0000374` Heap beschädigt, `0xe0434352` unbehandelte .NET-Ausnahme, `0x80000003` Haltepunkt erreicht (Programmfehler), `0xc0000135` benötigte DLL nicht gefunden, `0xc0000142` Initialisierung einer DLL fehlgeschlagen, `AppHangB1` wegen Nichtreagierens beendet.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/Events.Tests.ps1`)

```powershell
BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.EventConfig.ps1')
    $script:Cfg = Read-WorkerPerfEventConfig (Join-Path $PSScriptRoot '../src/events.json')
    function New-Xml([string]$Provider, [int]$Id, [string]$Data, [string]$User = '') {
        "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><System><Provider Name='$Provider'/><EventID>$Id</EventID><Level>2</Level></System>$Data$User</Event>"
    }
}
Describe 'events.json' {
    It 'fuehrt jede Kennung zu Gruppe und Art' {
        foreach ($e in $Cfg.Entries) { foreach ($id in $e.ids) {
            $r = Resolve-WorkerPerfEventEntry $Cfg $e.log $e.provider $id
            $r.group | Should -Be $e.group; $r.kind | Should -Be $e.kind } }
        (Resolve-WorkerPerfEventEntry $Cfg 'application' 'application error' 1000).kind | Should -Be 'crash'
        Resolve-WorkerPerfEventEntry $Cfg 'application' 'Application Error' 1001 | Should -BeNullOrEmpty
        (Resolve-WorkerPerfEventEntry $Cfg 'defender' 'Microsoft-Windows-Windows Defender' 1002).kind | Should -Be 'scan-end'
        $Cfg.Logs['session'].Lookback | Should -BeFalse; $Cfg.ErrorCodes['0xc0000005'] | Should -Be 'Zugriffsverletzung'
    }
    It 'nennt Eintrag und Feld eines Fehlers' -TestCases @(
        @{ Json = '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"P","ids":[1],"group":"app","kind":"absturz"}]}'; Msg = "*Eintrag 1 (P 1)*Feld 'kind'*" }
        @{ Json = '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"b","provider":"P","ids":[1],"group":"app","kind":"crash"}]}'; Msg = "*Eintrag 1 (P 1)*Feld 'log'*" }
        @{ Json = '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"P","ids":[1],"group":"app","kind":"crash","fields":{"modul":"M"}}]}'; Msg = "*Eintrag 1 (P 1)*Feld 'fields.modul'*" }
    ) {
        $f = Join-Path $TestDrive 'e.json'; [IO.File]::WriteAllText($f, $Json)
        { Read-WorkerPerfEventConfig $f } | Should -Throw $Msg
    }
}
Describe 'Rohereignis -> Datensatz' {
    It 'liest die strukturierten Felder aus den Datenfeldern, nicht aus dem Meldungstext' {
        $x = New-Xml 'Application Error' 1000 "<EventData><Data Name='AppName'>EXCEL.EXE</Data><Data Name='AppVersion'>16.0.1</Data><Data Name='ModuleName'>vbe7.dll</Data><Data Name='ModuleVersion'>7.1</Data><Data Name='ExceptionCode'>c0000005</Data><Data Name='ProcessId'>0x1f2c</Data></EventData>"
        $p = ConvertFrom-WorkerPerfEventXml $x
        $r = ConvertTo-WorkerPerfEventRecord (Resolve-WorkerPerfEventEntry $Cfg 'application' $p.Provider $p.EventId) $p ([datetime]'2026-01-15 08:00') "Name der fehlerhaften Anwendung: WORD.EXE`r`nweiter"
        $r.App | Should -Be 'EXCEL.EXE'; $r.Module | Should -Be 'vbe7.dll'; $r.Code | Should -Be '0xc0000005'; $r.Pid | Should -Be 8012
        $r.Group | Should -Be 'app'; $r.Kind | Should -Be 'crash'; $r.Level | Should -Be 2; $r.Text | Should -Be 'Name der fehlerhaften Anwendung: WORD.EXE'
    }
    It 'liest unbenannte Felder nach Position und Benutzer aus UserData' {
        $h = ConvertFrom-WorkerPerfEventXml (New-Xml 'Application Hang' 1002 '<EventData><Data>WINWORD.EXE</Data><Data>16.0</Data><Data>1a2c</Data></EventData>')
        (ConvertTo-WorkerPerfEventRecord (Resolve-WorkerPerfEventEntry $Cfg 'application' $h.Provider 1002) $h ([datetime]::Now) '').App | Should -Be 'WINWORD.EXE'
        $s = ConvertFrom-WorkerPerfEventXml (New-Xml 'Microsoft-Windows-TerminalServices-LocalSessionManager' 21 '' "<UserData><EventXML xmlns='x'><User>KLINIK\mueller</User><SessionID>3</SessionID></EventXML></UserData>")
        $r = ConvertTo-WorkerPerfEventRecord (Resolve-WorkerPerfEventEntry $Cfg 'session' $s.Provider 21) $s ([datetime]::Now) ''
        $r.User | Should -Be 'mueller'; $r.SessionId | Should -Be 3; $r.Kind | Should -Be 'logon'
    }
    It 'schreibt ein Ereignis mit fehlenden Feldern mit leeren Werten' {                        # Review Focus 1
        $p = ConvertFrom-WorkerPerfEventXml (New-Xml 'Application Error' 1000 '<EventData><Data>nur ein Wert</Data></EventData>')
        $r = ConvertTo-WorkerPerfEventRecord (Resolve-WorkerPerfEventEntry $Cfg 'application' $p.Provider 1000) $p ([datetime]::Now) $null
        $r.App | Should -Be ''; $r.Pid | Should -BeNullOrEmpty; $r.Kind | Should -Be 'crash'; $r.Text | Should -Be ''
    }
    It 'vereinheitlicht Fehlercodes und kuerzt Texte auf 300 Zeichen' {
        Format-WorkerPerfErrorCode 'C0000005' | Should -Be '0xc0000005'; Format-WorkerPerfErrorCode '3221225477' | Should -Be '0xc0000005'
        Format-WorkerPerfErrorCode 'AppHangB1' | Should -Be 'AppHangB1'
        (Get-WorkerPerfEventText ('x' * 400)).Length | Should -Be 300
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Events.Tests.ps1 -Output Minimal"`
Expected: FAIL, Datei `WorkerPerf.EventConfig.ps1` fehlt

- [ ] **Step 3: `src/events.json` und `src/WorkerPerf.EventConfig.ps1` mit den Signaturen der Interfaces anlegen**

XML über `[xml]` mit `XmlNamespaceManager` lesen (Präfix für `http://schemas.microsoft.com/win/2004/08/events/event`); `UserData` über `LocalName`, weil der Namensraum je Quelle wechselt. Die Datei definiert nur Funktionen.

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/events.json src/WorkerPerf.EventConfig.ps1 tests/Events.Tests.ps1
git commit -m "Add event catalogue and conversion of raw events to records"
```

---

### Task 3: Datenformat 3 und Collector

**Files:**
- Modify: `src/WorkerPerf.Common.ps1:5-22` (Version, Kopfzeilen), `src/WorkerPerf.Capture.ps1` (neue Zeilenfunktionen), `src/Start-WorkerPerfCapture.ps1` (Parameter, Start, regulärer Schnappschuss Zeilen 336–347, `$sourceNames` Zeile 186, `$meta`), `src/WorkerPerf.Sources.Simulation.ps1` und `src/WorkerPerf.Sources.Windows.ps1` (neue Funktionen der Schnittstelle, zunächst leer), `src/WorkerPerf.Load.ps1:111-120` (Formatprüfung) und `:763-773` (Ereignisse lesen), `src/texts.de.json`
- Create: `src/WorkerPerf.Events.ps1` (nur Lesefunktionen)
- Test: `tests/Capture.Tests.ps1`, `tests/Collector.Tests.ps1`, `tests/Common.Tests.ps1`, `tests/Load.Tests.ps1`, `tests/LoadHelpers.ps1`

**Interfaces:**
- Consumes: Datensatz aus Task 2 (`ConvertTo-WorkerPerfEventRecord`).
- Produces:
  - `$script:WorkerPerfFormatVersion = 3`; `$script:WorkerPerfReadableFormats = @(2, 3)`.
  - Kopfzeilen: `events.csv` und `events_before.csv` = `Timestamp,Log,Source,EventId,Level,Group,Kind,App,AppVersion,Module,ModuleVersion,Code,Pid,SessionId,User,Printer,Driver,Service,Object,Text`; `printdrivers.csv` = `Name,Manufacturer,Version,Type,Isolation,Files`; `printqueues.csv` = `Timestamp,Queue,Jobs,JobErrors,NotReadyErrors`. Reihenfolge in `$script:WorkerPerfHeaders`: `events_before.csv` direkt nach `events.csv`, die beiden Druckdateien am Ende (16 Dateien).
  - `ConvertTo-WorkerPerfEventRow($Event) -> string` (Spalten wie die Kopfzeile, fehlende Felder leer); `ConvertTo-WorkerPerfPrintDriverRow($Driver) -> string` (`Files` mit `;` verbunden, `Isolation` `none|shared|isolated|`); `ConvertTo-WorkerPerfPrintQueueRow($Queue, [datetime]$Time) -> string`.
  - `Complete-WorkerPerfEventSession -Events [object[]] -Processes [object[]] -Sessions [object[]]` → die Ereignisse; leere `SessionId` aus dem Prozess mit derselben `Pid` im Schnappschuss, leerer `User` aus der Sitzung mit dieser `SessionId`.
  - Neue Funktionen beider Quellen: `Get-WorkerPerfEventsBefore -Days [int] -Until [datetime] -> @{ Events = object[]; Capped = string[] }`, `Get-WorkerPerfPrintDrivers -> object[]` (`Name, Manufacturer, Version, Type, Isolation, Files`), `Get-WorkerPerfPrintQueues -> object[]` (`Queue, Jobs, JobErrors, NotReadyErrors`; Fehlerzähler als fortlaufende Rohwerte). In dieser Task liefern beide Quellen leere Ergebnisse; die Windows-Quelle meldet `Sources['print.drivers']` und `Sources['print.queues']` mit `Available = $false`, `Detail = 'noch nicht umgesetzt'`.
  - Collector: `[ValidateRange(0, 90)][int]$EventLookbackDays = 7`. Beim Start nach `Save-Meta`: Rückblick bis zur Startzeit nach `events_before.csv`, Treiberliste nach `printdrivers.csv`. Bei jedem regulären Schnappschuss: Ereignisse wie bisher, ergänzt über `Complete-WorkerPerfEventSession` mit dem letzten gelungenen Schnappschuss, und Warteschlangen nach `printqueues.csv`. Quellenschlüssel für Fehler: `eventsbefore`, `printdrivers`, `printqueues`. `meta.json` neu: `EventLookbackDays`, `LookbackCapped` (Protokoll-Ids).
  - `src/WorkerPerf.Events.ps1`: `Read-WorkerPerfEventCsv([string]$Path, [string]$FileName)` → Datensätze als Hashtables mit `TimeMs` und allen Spalten von Format 3 (eine im Kopf fehlende Spalte ist `''`, Zahlenspalten `Pid`, `SessionId`, `EventId`, `Level` als `[int]`, leer = -1), sortiert nach Zeit, bei Gleichstand nach Position; leere `Group` bei Arten `scan-start`, `scan-end`, `signature-update`, `applocker-block` wird `security`. `Read-WorkerPerfPrintDrivers([string]$Path)` → `@{ Name; Manufacturer; Version; Type = [int] (0 = unbekannt); Isolation; Files = string[] }`. `Read-WorkerPerfPrintQueues([string]$Path, [long]$FromMs, [long]$ToMs)` → `@{ TimeMs; Queue; Jobs; JobErrors; NotReadyErrors }`.
  - Modell aus `Import-WorkerPerfRun` neu: `Events` mit den neuen Feldern, `EventsBefore`, `PrintDrivers`, `PrintQueues`; `Meta['EventLookbackDays']`, `Meta['LookbackCapped']`. Meldung bei anderem Format: `"Die Aufzeichnung '<Pfad>' hat das Format <v>; diese Version von WorkerPerf liest die Formate 2 und 3."`
  - `texts.de.json`: `source.events.application` „Ereignisprotokoll Anwendung", `source.events.system` „Ereignisprotokoll System", `source.events.printservice` „Ereignisprotokoll Druckdienst", `source.events.smbclient` „Ereignisprotokoll SMB-Client", `source.events.profileservice` „Ereignisprotokoll Benutzerprofildienst", `source.events.session` „Ereignisprotokoll Sitzungsverwaltung", `source.print.drivers` „Druckertreiber", `source.print.queues` „Zähler der Druckwarteschlangen", `sourcecall.eventsbefore` „Ereignisse vor der Messung", `sourcecall.printdrivers` „Druckertreiber", `sourcecall.printqueues` „Druckwarteschlangen".
- `tests/LoadHelpers.ps1`: `Write-TestRun` schreibt `events.csv` mit der Kopfzeile von Format 2 (`Timestamp,Source,EventId,Kind,Text`), passend zu `"SchemaVersion":2` in seinem `meta.json`. Damit prüfen die bestehenden Ladetests weiter das alte Format; keine ihrer Aussagen ändert sich.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben**

```powershell
# tests/Capture.Tests.ps1
It 'schreibt Ereigniszeilen in der Spaltenfolge der Kopfzeile' {
    $e = [pscustomobject]@{ Time = [datetime]'2026-01-15T08:00:00'; Log = 'application'; Source = 'Application Error'; EventId = 1000; Level = 2; Group = 'app'; Kind = 'crash'
        App = 'EXCEL.EXE'; Module = 'vbe7.dll'; Code = '0xc0000005'; Pid = 812; SessionId = 3; User = 'user002'; Text = 'a, "b"' }
    $f = Split-WorkerPerfCsvLine (ConvertTo-WorkerPerfEventRow $e)
    $f.Count | Should -Be 20; $f[1] | Should -Be 'application'; $f[7] | Should -Be 'EXCEL.EXE'; $f[12] | Should -Be '812'; $f[19] | Should -Be 'a, "b"'; $f[8] | Should -Be ''
}
It 'ergaenzt Sitzung und Benutzer ueber die PID des letzten Schnappschusses' {                # Review Focus 4
    $procs = @([pscustomobject]@{ ProcessId = 812; SessionId = 3 }, [pscustomobject]@{ ProcessId = 900; SessionId = 0 })
    $sess = @([pscustomobject]@{ SessionId = 3; User = 'user002' }, [pscustomobject]@{ SessionId = 0; User = '' })
    $ev = @([pscustomobject]@{ Pid = 812; SessionId = $null; User = '' }, [pscustomobject]@{ Pid = 900; SessionId = $null; User = '' },
            [pscustomobject]@{ Pid = 4711; SessionId = $null; User = '' }, [pscustomobject]@{ Pid = 812; SessionId = 5; User = 'anders' })
    $r = @(Complete-WorkerPerfEventSession -Events $ev -Processes $procs -Sessions $sess)
    $r[0].SessionId | Should -Be 3; $r[0].User | Should -Be 'user002'; $r[1].SessionId | Should -Be 0; $r[1].User | Should -Be ''
    $r[2].SessionId | Should -BeNullOrEmpty; $r[3].SessionId | Should -Be 5; $r[3].User | Should -Be 'anders'
}
# tests/Common.Tests.ps1 – Aussage geaendert: 16 statt 13 Dateien, weil das Format drei Dateien dazubekommt
It 'kennt die sechzehn Dateien mit ihren Kopfzeilen' {
    $WorkerPerfHeaders.Count | Should -Be 16; $WorkerPerfFormatVersion | Should -Be 3
    $WorkerPerfHeaders['events.csv'].Split(',').Count | Should -Be 20; $WorkerPerfHeaders['events_before.csv'] | Should -Be $WorkerPerfHeaders['events.csv']
    $WorkerPerfHeaders['printqueues.csv'] | Should -Be 'Timestamp,Queue,Jobs,JobErrors,NotReadyErrors'
}
# tests/Load.Tests.ps1 – Aussage geaendert: Format 3 wird gelesen, Format 4 abgelehnt
It 'lehnt eine andere Formatversion ab und duldet eine fehlende' {
    $dir = Write-TestRun 'ver' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }; $meta = Join-Path $dir 'meta.json'
    $text = [IO.File]::ReadAllText($meta)
    [IO.File]::WriteAllText($meta, $text.Replace('"SchemaVersion":2,', '"SchemaVersion":4,'))
    { Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles } | Should -Throw '*Format 4*Formate 2 und 3*'
    [IO.File]::WriteAllText($meta, $text.Replace('"SchemaVersion":2,', ''))
    (Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles).Tick.N | Should -Be 8
}
It 'liest Ereignisse im Format 2 und 3, den Rueckblick und die Druckdateien' {
    $old = Import-TestRun 'ev2' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'events.csv' = @("$(Get-Ts 5),Defender,1000,scan-start,Scan") }
    $old.Events[0].Group | Should -Be 'security'; $old.Events[0].App | Should -Be ''; $old.Events[0].Pid | Should -Be -1
    @($old.EventsBefore).Count | Should -Be 0; @($old.PrintDrivers).Count | Should -Be 0
    $dir = Write-TestRun 'ev3' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }
    [IO.File]::WriteAllLines((Join-Path $dir 'events.csv'), @($WorkerPerfHeaders['events.csv'], "$(Get-Ts 5),application,Application Error,1000,2,app,crash,EXCEL.EXE,16.0,vbe7.dll,7.1,0xc0000005,812,3,user002,,,,,Absturz"))
    [IO.File]::WriteAllLines((Join-Path $dir 'events_before.csv'), @($WorkerPerfHeaders['events.csv'], "$($Base.AddDays(-2).ToString('o')),application,Application Error,1000,2,app,crash,EXCEL.EXE,,,,,,,user002,,,,,x"))
    [IO.File]::WriteAllLines((Join-Path $dir 'printdrivers.csv'), @($WorkerPerfHeaders['printdrivers.csv'], 'Sim PCL 6,HP,61.1.0.0,3,none,hpsimgr.dll;hpsimui.dll'))
    $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles
    $m.Events[0].Module | Should -Be 'vbe7.dll'; $m.Events[0].SessionId | Should -Be 3; @($m.EventsBefore).Count | Should -Be 1
    $m.PrintDrivers[0].Type | Should -Be 3; $m.PrintDrivers[0].Files | Should -Be @('hpsimgr.dll', 'hpsimui.dll')
}
# tests/Collector.Tests.ps1 – Aussage geaendert in 'fuehrt meta.json': SchemaVersion 3 statt 2 (neues Format)
It 'fuehrt meta.json' {
    $Meta.SchemaVersion | Should -Be 3; $Meta.EventLookbackDays | Should -Be 7; @($Meta.LookbackCapped).Count | Should -Be 0
    # die uebrigen Aussagen bleiben
}
It 'liest ohne Rueckblick nichts vor dem Start' {                                                 # Review Focus 3
    $run = (& (Join-Path $PSScriptRoot '../src/Start-WorkerPerfCapture.ps1') -Simulate -DurationMinutes 60 -EventLookbackDays 0 -OutputPath (Join-Path $TestDrive 'nolb') 6>$null) | Select-Object -Last 1
    @(Get-Content (Join-Path $run 'events_before.csv')).Count | Should -Be 1
    (Get-Content (Join-Path $run 'meta.json') -Raw | ConvertFrom-Json).EventLookbackDays | Should -Be 0
}
```

`tests/LoadHelpers.ps1` erhält die Kopfzeile von Format 2 für `events.csv` (siehe Interfaces).

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`
Expected: FAIL in Capture, Common, Load und Collector (Funktionen fehlen, Version 2)

- [ ] **Step 3: Format, Zeilen, Collector, leere Quellenfunktionen und Lesefunktionen mit den Signaturen der Interfaces umsetzen**

`Import-WorkerPerfRun` ersetzt die Zeilen 763–773 durch `Read-WorkerPerfEventCsv` und füllt die drei neuen Modellfelder; `src/New-WorkerPerfReport.ps1` und `tests/LoadHelpers.ps1` binden `WorkerPerf.EventConfig.ps1` und `WorkerPerf.Events.ps1` ein. Der Rückblick wird mit `-Until $startTime` gelesen; Ereignisse der Messzeit beginnen wie bisher nach `$startTime`. Die drei bisherigen Ereignisse der Simulation erhalten die neuen Felder (`Log` `defender`/`applocker`, `Source` mit den Quellennamen aus `events.json`, `Group` `security`).

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src tests
git commit -m "Write capture format 3 with structured events, lookback and print files"
```

---

### Task 4: Simulation – zusätzliche Szenen

**Files:**
- Modify: `src/WorkerPerf.Sources.Simulation.ps1` (`$script:WorkerPerfSimEvents` Zeile 249, `Get-WorkerPerfEvents`, die Funktionen aus Task 3, `Get-WorkerPerfExpected`, `Sources`)
- Test: `tests/Simulation.Tests.ps1`, `tests/Collector.Tests.ps1`

**Interfaces:**
- Consumes: Schnittstelle aus Task 3.
- Produces – Szenen (Sekunden nach dem Start; Sitzungs-ID = Benutzernummer + 1); alle Ereignisse mit `Source` und `Log` laut `events.json`:

| Sekunde | Ereignis | Erwartete Muster |
|---|---|---|
| 1100 | `Application Error` 1000: `chrome.exe` von user008 (Sitzung 9, PID aus `$pidOf['9|chrome.exe']`), Modul `chrome.dll`, Code `0xc0000017` | `resource`, `overlap` (Arbeitsspeicher-Engpass 900–1131 s) |
| 1300, 1340 | Sitzungsverwaltung 23 (Abmelden) und 21 (Anmelden) von user014, Sitzung 15 | – |
| 1345 | `Microsoft-Windows-User Profiles Service` 1511 (temporäres Profil) für user014 | keines |
| 2100, 2160, 2220 | `Application Error` 1000: `OUTLOOK.EXE` von user010, user011, user012 (Sitzungen 11–13), Modul `olmapi32.dll`, Code `0xc0000005` | `manyusers` |
| 2200, 2230 | Sitzungsverwaltung 24 (Trennen) und 25 (Wiederverbinden) von user022, Sitzung 23 | – |
| 2600 | `Application Error` 1000: `spoolsv.exe`, Sitzung 0, Modul `hpsimgr.dll`, Code `0xc0000005` | `printdriver` |

  - Rückblick (`Get-WorkerPerfEventsBefore`, Zeiten relativ zum Start; Ereignisse älter als `-Days` entfallen; `Capped` leer): `nexus.exe` von user004 um −259200, −258600, −258000 s, Modul `nxreport.dll` (Muster `oneuser`); `EXCEL.EXE` von user001 um −432000 s und `WINWORD.EXE` von user002 um −431000 s, beide Modul `simaddin.dll` (je ein Vorfall mit `sharedmodule`).
  - Treiberliste: `HP Universal Printing PCL 6 (Sim)`, HP, Typ 3, `none`, Dateien `hpsimgr.dll`, `hpsimui.dll`; `Microsoft IPP Class Driver`, Microsoft, Typ 4, `shared`, `mxdwdrv.dll`; `Kyocera Sim KX`, Kyocera, Typ 3, `isolated`, `kxsim.dll`.
  - Warteschlangen `PRN-EG-01` und `PRN-OG-02`: `Jobs` 0, für `PRN-EG-01` von 2590 bis 2700 s 3; `JobErrors` von `PRN-EG-01` ab 2600 s um 1 höher; `NotReadyErrors` 0.
  - `Sources`: `events.<id>` für jede Protokoll-Id von `events.json`, `print.drivers`, `print.queues`, alle verfügbar.
  - `expected.json`: jede Zeile erhält `Kind`, `Patterns` (`string[]`), `Before` (`bool`), `App`, `Driver`, `Count`, `Users`; bei den acht bisherigen `Kind = $null`, `Patterns = @()`, `Before = $false`. Neue Zeilen mit `Type = 'ereignis'`, `Lead = $null`, `Chronic = $false`, `Affected = 0`: `crash.memory`, `profile.logon`, `crash.manyusers`, `print.spooler` (`Kind = 'print'`, `Driver = 'HP Universal Printing PCL 6 (Sim)'`), `before.shared.excel`, `before.shared.word`, `before.oneuser` (`Before = $true`). `StartMs`/`EndMs` = erstes und letztes Ereignis. Sortiert nach `StartMs`.
  - Die Kennzahlen der Messung bleiben unverändert: keine neue Sitzung, kein neuer Prozess, keine geänderte Last; die Simulation führt user014 durchgehend als aktive Sitzung 15.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben**

```powershell
# tests/Simulation.Tests.ps1 – Aussagen geaendert in 'liefert Ereignisse seit einem Zeitpunkt' und 'beschreibt das Soll-Ergebnis', weil das Drehbuch Szenen dazubekommt
It 'liefert Ereignisse seit einem Zeitpunkt' {
    Set-SimTime 31; @(Get-WorkerPerfEvents -Since $Start | Where-Object Group -eq 'security').Kind | Should -Be @('scan-start', 'scan-end', 'applocker-block')
    @(Get-WorkerPerfEvents -Since $Start.AddMinutes(28)).Kind | Should -Be @('applocker-block')
    Set-SimTime 60; $ev = @(Get-WorkerPerfEvents -Since $Start)
    @($ev | Where-Object Kind -eq 'crash').App | Should -Be @('chrome.exe', 'OUTLOOK.EXE', 'OUTLOOK.EXE', 'OUTLOOK.EXE', 'spoolsv.exe')
    ($ev | Where-Object App -eq 'spoolsv.exe').Module | Should -Be 'hpsimgr.dll'
    @($ev | Where-Object Group -eq 'session').Kind | Should -Be @('logoff', 'logon', 'disconnect', 'reconnect')
}
It 'liefert Rueckblick, Treiber und Warteschlangen' {
    $b = Get-WorkerPerfEventsBefore -Days 7 -Until $Start
    @($b.Events).Count | Should -Be 5; @($b.Capped).Count | Should -Be 0
    @((Get-WorkerPerfEventsBefore -Days 4 -Until $Start).Events).Count | Should -Be 3
    @(Get-WorkerPerfPrintDrivers).Manufacturer | Should -Be @('HP', 'Microsoft', 'Kyocera')
    Set-SimTime 43.5; (Get-WorkerPerfPrintQueues | Where-Object Queue -eq 'PRN-EG-01').Jobs | Should -Be 3
}
It 'beschreibt das Soll-Ergebnis' {
    $e = @(Get-WorkerPerfExpected)
    @($e | Where-Object Type -ne 'ereignis').Key | Should -Be @('homeoffice', 'cpu', 'memory', 'disk', 'share', 'profile', 'backend', 'hang')
    @($e | Where-Object Type -eq 'ereignis').Count | Should -Be 7
    ($e | Where-Object Key -eq 'crash.memory').Patterns | Should -Be @('resource', 'overlap')
    ($e | Where-Object Key -eq 'profile.logon').Patterns.Count | Should -Be 0
    # die uebrigen Aussagen bleiben
}
# tests/Collector.Tests.ps1 – Aussagen geaendert: neue Ereignisse und Zeilen im Soll-Ergebnis
It 'legt Proben, Ereignisse und Citrix-Werte ab' {
    @(Import-Csv (Join-Path $Run 'events.csv') | Where-Object Group -eq 'security').Kind | Should -Be @('scan-start', 'scan-end', 'applocker-block')
    @(Import-Csv (Join-Path $Run 'events.csv')).Count | Should -Be 13
    @(Import-Csv (Join-Path $Run 'events_before.csv')).Count | Should -Be 5; @(Import-Csv (Join-Path $Run 'printdrivers.csv')).Count | Should -Be 3
    @(Import-Csv (Join-Path $Run 'printqueues.csv')).Count | Should -Be (240 * 2)
    ((Import-Csv (Join-Path $Run 'events.csv')) | Where-Object App -eq 'chrome.exe').User | Should -Be 'user008'
    # Proben und Citrix wie bisher
}
It 'legt das Soll-Ergebnis ab' { @($Exp | Where-Object Type -ne 'ereignis').Count | Should -Be 8; $Exp[1].Key | Should -Be 'cpu' }
```

Die Zeile `$Exp[1].Key` bleibt gültig, weil die Rückblick-Zeilen nach `StartMs` vorn stehen würden: `Get-WorkerPerfExpected` sortiert die Zeilen mit `Before` deshalb ans Ende.

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Simulation.Tests.ps1,tests/Collector.Tests.ps1 -Output Minimal"`
Expected: FAIL, keine Absturzereignisse

- [ ] **Step 3: Szenen, Rückblick, Treiber, Warteschlangen und Soll-Ergebnis umsetzen** (Ereignisse als Datensätze mit allen Feldern von `ConvertTo-WorkerPerfEventRecord`; ein interner Helfer `New-WorkerPerfSimEvent` hält das Drehbuch kurz)

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`
Expected: `Failed: 0` – auch `tests/Report.Tests.ps1` bleibt grün, weil der Bericht Ereignisvorfälle erst ab Task 8 bildet

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Sources.Simulation.ps1 tests/Simulation.Tests.ps1 tests/Collector.Tests.ps1
git commit -m "Add crash, print, profile, session and lookback scenes to the simulation"
```

---

### Task 5: Auswertung – Ereignisvorfälle bilden

**Files:**
- Modify: `src/WorkerPerf.Events.ps1`, `src/WorkerPerf.EventConfig.ps1`, `src/thresholds.json` (neuer Block `events` nach der Liste)
- Test: `tests/Events.Tests.ps1`

**Interfaces:**
- Consumes: Datensätze aus `Read-WorkerPerfEventCsv`, Modell aus `Import-WorkerPerfRun` (`Sessions` mit `Sid`, `User`, `FirstP`, `LastP`; `Snap.TimeMs`), `Read-WorkerPerfEventConfig`.
- Produces:
  - `thresholds.json`: `"events": { "eventGroupMinutes": 30, "resourceMinutes": 5, "afterhangMinutes": 2, "companionMinutes": 2, "manyUsers": 3, "oneUserEvents": 3 }`. `Read-WorkerPerfEventSettings([string]$Path) -> @{ GroupMinutes; ResourceMinutes; AfterhangMinutes; CompanionMinutes; ManyUsers; OneUserEvents }`; fehlender Block oder fehlendes Feld = Standardwert; ein Wert, der keine positive Zahl ist: `throw "Schwellwert 'events': Feld '<feld>' ..."`. `Read-WorkerPerfThresholds` übergeht den Block.
  - `Set-WorkerPerfEventSessions -Events [object[]] -Model` setzt `SessionIndex` je Datensatz: Sitzung mit gleicher `Sid`, die zur Zeit des Ereignisses lebte, sonst die mit gleichem Benutzer, sonst -1.
  - `Get-WorkerPerfEventIncidentKind($Event, $Config) -> string | $null`: `crash`, `hang`, `service`, `print`, `profileerror`, `system` nach der Art; `crash`/`hang` eines Prozesses aus `PrintProcesses` und `service` eines Dienstes aus `PrintServices` werden `print`; andere Arten liefern `$null`.
  - `New-WorkerPerfEventIncidents -Events [object[]] -Config -Settings -Drivers [object[]] -FirstId [int] [-Before]` → Vorfälle (Hashtables): `Id, Kind, Key, Group, StartMs, EndMs, Count, Events (höchstens 50, die ersten), Users (string[], Reihenfolge des Auftretens), Sessions (int[] Sitzungsindizes), InSession, Severity, Versions, Modules (@{ Name; Count }, nach Anzahl absteigend), SameModule, Codes (@{ Code; Text; Count }), App, Service, Driver, Printer, Source, Before, Patterns = @(), Overlap = @(), Companions = @()`.
  - Schlüssel: `crash`/`hang` die Anwendung; `service` der Dienst; `print` der Treiber, sonst der Treiber, zu dessen Dateien das Modul gehört, sonst der Drucker, sonst die Quelle; `profileerror` die Quelle; `system` Gruppe und `Object`. Vergleich ohne Rücksicht auf Groß- und Kleinschreibung.
  - Zusammenfassen: je Art und Schlüssel nach Zeit; ein neuer Vorfall beginnt, wenn der Abstand zum vorigen Ereignis `GroupMinutes` überschreitet.
  - Ein Vorfall entsteht bei `crash`/`hang`, wenn ein Ereignis in einer Benutzersitzung liegt (`SessionId` > 0, oder ohne Sitzung ein Benutzer außer `SYSTEM`, `LOCAL SERVICE`, `NETWORK SERVICE`) oder die Gruppe mindestens zwei Ereignisse hat; bei `service`, wenn der Dienst in `ImportantServices` steht oder mindestens zwei Ereignisse vorliegen; bei `print`, `profileerror`, `system` immer. `Severity` 2 bei `InSession`, sonst 1. Nummern ab `FirstId` nach `StartMs`, dann Art, dann Schlüssel.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/Events.Tests.ps1`; Datensätze über einen Helfer `New-Ev` mit allen Feldern, Zeiten in Minuten ab `$T0`. Helfer und `$script:`-Werte stehen im `BeforeAll` am Anfang der Datei, damit alle `Describe`-Blöcke sie sehen; unten sind sie der Lesbarkeit halber beim ersten Gebrauch gezeigt)

```powershell
Describe 'Ereignisvorfaelle' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/WorkerPerf.Events.ps1')
        $script:Set = Read-WorkerPerfEventSettings (Join-Path $PSScriptRoot '../src/thresholds.json'); $script:T0 = 1700000000000
        function New-Ev([double]$Min, [string]$Kind = 'crash', [string]$App = 'EXCEL.EXE', [int]$Sid = 3, [string]$User = 'user002', [string]$Module = 'vbe7.dll', [hashtable]$More = @{}) {
            $e = @{ TimeMs = [long]($T0 + $Min * 60000); Log = 'application'; Source = 'Application Error'; EventId = 1000; Level = 2; Group = 'app'; Kind = $Kind
                App = $App; AppVersion = '16.0'; Module = $Module; ModuleVersion = ''; Code = '0xc0000005'; Pid = 812; SessionId = $Sid; SessionIndex = $Sid; User = $User
                Printer = ''; Driver = ''; Service = ''; Object = ''; Text = '' }
            foreach ($k in $More.Keys) { $e[$k] = $More[$k] }; $e
        }
        function Get-Inc { param([object[]]$Events, [switch]$Before) , @(New-WorkerPerfEventIncidents -Events $Events -Config $Cfg -Settings $Set -Drivers @(
            @{ Name = 'Sim PCL 6'; Manufacturer = 'HP'; Files = @('hpsimgr.dll') }) -FirstId 9 -Before:$Before) }
    }
    It 'liest die Abstaende aus den Schwellen' { $Set.GroupMinutes | Should -Be 30; $Set.ResourceMinutes | Should -Be 5; $Set.ManyUsers | Should -Be 3 }
    It 'nimmt ohne Block Standardwerte und nennt ein falsches Feld' {                           # Review Focus 5
        $f = Join-Path $TestDrive 't.json'; [IO.File]::WriteAllText($f, '{"thresholds":[]}'); (Read-WorkerPerfEventSettings $f).GroupMinutes | Should -Be 30
        [IO.File]::WriteAllText($f, '{"thresholds":[],"events":{"eventGroupMinutes":"halb"}}'); { Read-WorkerPerfEventSettings $f } | Should -Throw "*'eventGroupMinutes'*"
    }
    It 'fasst bis 30 Minuten Abstand zusammen' {
        $i = Get-Inc @((New-Ev 0), (New-Ev 30), (New-Ev 61))
        $i.Count | Should -Be 2; $i[0].Count | Should -Be 2; $i[0].Id | Should -Be 9; $i[0].EndMs - $i[0].StartMs | Should -Be 1800000
    }
    It 'bildet den Schluessel je Art' {
        $i = Get-Inc @((New-Ev 0), (New-Ev 1 -App 'WINWORD.EXE'), (New-Ev 2 'service' '' 0 '' '' @{ Service = 'Spooler2'; Group = 'service' }), (New-Ev 3 'service' '' 0 '' '' @{ Service = 'spooler2'; Group = 'service' }),
            (New-Ev 4 'system' '' 0 '' '' @{ Group = 'storage'; Object = 'D:' }), (New-Ev 5 'system' '' 0 '' '' @{ Group = 'storage'; Object = 'E:' }))
        @($i | ForEach-Object { $_.Kind + ':' + $_.Key }) | Should -Be @('crash:EXCEL.EXE', 'crash:WINWORD.EXE', 'service:Spooler2', 'system:storage|D:', 'system:storage|E:')
    }
    It 'macht einen einzelnen Absturz in einer Sitzung zum Vorfall, einen Hintergrundprozess erst bei Wiederholung' {
        (Get-Inc @(New-Ev 0)).Count | Should -Be 1; (Get-Inc @(New-Ev 0))[0].InSession | Should -BeTrue; (Get-Inc @(New-Ev 0))[0].Severity | Should -Be 2
        (Get-Inc @(New-Ev 0 -Sid 0 -User 'SYSTEM')).Count | Should -Be 0
        $bg = Get-Inc @((New-Ev 0 -Sid 0 -User ''), (New-Ev 10 -Sid 0 -User '')); $bg.Count | Should -Be 1; $bg[0].InSession | Should -BeFalse; $bg[0].Severity | Should -Be 1
        (Get-Inc @(New-Ev 0 'service' '' 0 '' '' @{ Service = 'Spooler2'; Group = 'service' })).Count | Should -Be 0
        (Get-Inc @(New-Ev 0 'service' '' 0 '' '' @{ Service = 'BrokerAgent'; Group = 'service' })).Count | Should -Be 1
    }
    It 'zaehlt einen Absturz der Druckwarteschlange als Druckproblem mit dem Treiber als Schluessel' {
        $i = Get-Inc @(New-Ev 0 -App 'spoolsv.exe' -Sid 0 -User '' -Module 'hpsimgr.dll'); $i[0].Kind | Should -Be 'print'; $i[0].Key | Should -Be 'Sim PCL 6'
    }
    It 'nennt Anzahl, Benutzer, Versionen, Module und Fehlercodes' {
        $i = (Get-Inc @((New-Ev 0), (New-Ev 1 -Sid 4 -User 'user003'), (New-Ev 2 -Module 'mso.dll')))[0]
        $i.Users | Should -Be @('user002', 'user003'); $i.Sessions | Should -Be @(3, 4); $i.SameModule | Should -BeFalse
        $i.Modules[0].Name | Should -Be 'vbe7.dll'; $i.Modules[0].Count | Should -Be 2; $i.Codes[0].Text | Should -Be 'Zugriffsverletzung'; $i.Versions | Should -Be @('16.0')
    }
    It 'haelt einen Vorfall mit vielen Ereignissen klein' {                                    # Review Focus 2
        $i = Get-Inc @(1..500 | ForEach-Object { New-Ev ($_ / 100) -Sid 0 -User '' -App 'dienst.exe' })
        $i.Count | Should -Be 1; $i[0].Count | Should -Be 500; @($i[0].Events).Count | Should -Be 50
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Events.Tests.ps1 -Output Minimal"`
Expected: FAIL, `Read-WorkerPerfEventSettings` nicht definiert

- [ ] **Step 3: Einstellungen, Sitzungszuordnung, Art, Schlüssel und Zusammenfassen mit den Signaturen der Interfaces umsetzen**

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Events.ps1 src/WorkerPerf.EventConfig.ps1 src/thresholds.json tests/Events.Tests.ps1
git commit -m "Group events into crash, hang, service, print, profile and system incidents"
```

---

### Task 6: Auswertung – Muster und Klartext

**Files:**
- Modify: `src/WorkerPerf.Events.ps1`, `src/WorkerPerf.Common.ps1` (`Read-WorkerPerfRoles`: optionales Feld `modules`), `src/roles.json`, `src/texts.de.json`
- Test: `tests/Events.Tests.ps1`

**Interfaces:**
- Consumes: Vorfälle aus Task 5; Leistungsvorfälle aus `Join-WorkerPerfIncidents` (`Id, StartMs, EndMs`); `Model.Tick.TimeMs`, `Model.Tick.Signal['mem.used']`, `['mem.commit']`; Schwellen `crit`.
- Produces:
  - Rollen: optionales Feld `modules` (Muster wie `processes`, Standard `@()`); in `roles.json` für Microsoft Defender `MpOav.dll`, `MpClient.dll`, für Arctic Wolf Aurora `CyMemDef*.dll`, Hinweis „Module ungeprüft".
  - `Add-WorkerPerfEventPatterns -Incidents [object[]] -AllEvents [object[]] -Model -Thresholds -Settings -Config -Roles -Drivers [object[]] -PerfIncidents [object[]] [-Before]` setzt je Vorfall `Patterns` = Liste von `@{ Id; Detail }` in der festen Reihenfolge `resource, afterhang, sharedmodule, printdriver, securitymodule, manyusers, oneuser, companion, overlap`, dazu `Overlap` (int[]) und `Companions`; jeder Leistungsvorfall erhält `EventIncidents` (int[], auch leer). Mit `-Before` nur `afterhang, sharedmodule, printdriver, securitymodule, manyusers, oneuser, companion`; `-Model` und `-PerfIncidents` dürfen dann `$null` sein.
  - Prüfungen (Abstände aus `Settings`):

| Muster | trifft zu, wenn | `Detail` |
|---|---|---|
| `resource` | für ein Ereignis zur Zeit t: ein Takt in (t − `ResourceMinutes`, t] mit `mem.used` oder `mem.commit` ≥ `crit`, oder ein Ereignis der Gruppe `memory` in [t − `ResourceMinutes`, t] | `@{ SignalId; Peak }` oder `@{ WarningMs }` |
| `afterhang` | `hang` derselben Anwendung in derselben Sitzung (ohne Sitzung: derselbe Benutzer) 0 bis `AfterhangMinutes` vor einem `crash` | `@{ HangMs }` |
| `sharedmodule` | ein Modul des Vorfalls, das nicht in `SystemModules` steht, ist bei mindestens zwei verschiedenen Anwendungen in `AllEvents` abgestürzt | `@{ Module; Apps }` |
| `printdriver` | ein Modul ist eine Datei eines Treibers | `@{ Module; Driver }` |
| `securitymodule` | ein Modul passt zu `modules` einer Rolle `Sicherheit` | `@{ Module; Product }` |
| `manyusers` | `crash`/`hang` mit mindestens `ManyUsers` Benutzern | `@{ Users }` |
| `oneuser` | genau ein Benutzer und mindestens `OneUserEvents` Ereignisse | `@{ User; Count }` |
| `companion` | Ereignis der Gruppen `storage`, `fileserver`, `profile`, `security`, das nicht zum Vorfall gehört, höchstens `CompanionMinutes` vor oder nach einem Ereignis des Vorfalls | `@{ Events }` (höchstens 10) |
| `overlap` | ein Leistungsvorfall überlappt `StartMs`–`EndMs` | `@{ Incidents }` |

  - `Get-WorkerPerfEventIncidentText -Incident -Model -Texts -Config -OffsetMinutes [int] -> string`: Kopf je Art, Zusätze, dann die Aussage jedes Musters; ohne Muster „Kein Muster erkannt." Zeit: `HH:mm:ss` bei einem Ereignis, sonst `HH:mm:ss–HH:mm:ss` (Ortszeit des Servers wie `Format-WorkerPerfClock`).
  - Neue Schlüssel in `texts.de.json` (genau diese Texte):

```json
"event.crash": "{0}: Absturz von {1} ({2}).", "event.hang": "{0}: {1} reagierte nicht und wurde beendet ({2}).",
"event.service": "{0}: Dienst {1} unerwartet beendet ({2}).", "event.print": "{0}: Druckproblem – {1} ({2}).",
"event.profileerror": "{0}: Profilproblem – {1} ({2}).", "event.system": "{0}: Systemfehler – {1} ({2}).",
"event.count.one": "1-mal", "event.count.many": "{0}-mal", "event.users": " Benutzer: {0}.", "event.nouser": " Ohne Benutzersitzung.",
"event.module.same": " Fehlerhaftes Modul: {0}, immer dasselbe.", "event.module.mixed": " Fehlerhafte Module: {0}.",
"event.code": " Fehlercode: {0}.", "event.versions": " Versionen: {0}.",
"pattern.resource": " Wahrscheinlich Folge des Speichermangels.", "pattern.afterhang": " Wurde nach Nichtreagieren beendet.",
"pattern.sharedmodule": " Ursache liegt wahrscheinlich im Modul {0} (betrifft {1}).", "pattern.printdriver": " Das Modul {0} gehört zum Druckertreiber {1}.",
"pattern.securitymodule": " Das Modul {0} gehört zur Schutzsoftware {1}.", "pattern.manyusers": " {0} Benutzer betroffen: spricht für Installation oder Update.",
"pattern.oneuser": " Nur {0} betroffen, {1}-mal: spricht für Profil oder Daten dieses Benutzers.", "pattern.companion": " Zeitnah: {0}.",
"pattern.overlap": " Zeitgleich mit Vorfall {0}.", "pattern.none": " Kein Muster erkannt."
```

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (Helfer aus Task 5; ein kleines Modell `New-PatternModel` mit `Tick.TimeMs` je Minute und `Tick.Signal['mem.used']`, `['mem.commit']`; neue Helfer und Werte ebenfalls ins `BeforeAll` am Dateianfang)

```powershell
Describe 'Muster' {
    BeforeAll {
        $script:Th = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json'); $script:Roles = Read-WorkerPerfRoles (Join-Path $PSScriptRoot '../src/roles.json')
        $script:Drv = @(@{ Name = 'Sim PCL 6'; Manufacturer = 'HP'; Files = @('hpsimgr.dll') })
        function New-PatternModel([double[]]$MemUsed) { @{ Tick = @{ TimeMs = [long[]]@(0..($MemUsed.Count - 1) | ForEach-Object { $T0 + $_ * 60000 }); Signal = @{ 'mem.used' = $MemUsed; 'mem.commit' = [double[]]@($MemUsed | ForEach-Object { 50.0 }) } } }
        function Get-Pat([object[]]$Events, $Model = (New-PatternModel (@(50) * 60)), [object[]]$Perf = @(), [switch]$Before) {
            $inc = Get-Inc $Events -Before:$Before
            Add-WorkerPerfEventPatterns -Incidents $inc -AllEvents $Events -Model $Model -Thresholds $Th -Settings $Set -Config $Cfg -Roles $Roles -Drivers $Drv -PerfIncidents $Perf -Before:$Before
            , @($inc | ForEach-Object { , @($_.Patterns | ForEach-Object { $_.Id }) })
        }
    }
    It 'resource: Speicher ueber kritisch in den 5 Minuten davor, nicht 6 Minuten davor' {
        (Get-Pat @(New-Ev 10) (New-PatternModel (@(50) * 6 + @(95) + @(50) * 53)))[0] | Should -Contain 'resource'     # Takt 6 = 4 min vor dem Absturz
        (Get-Pat @(New-Ev 10) (New-PatternModel (@(50) * 4 + @(95) + @(50) * 55)))[0] | Should -Not -Contain 'resource'  # Takt 4 = 6 min davor
        (Get-Pat @((New-Ev 8 'system' '' 0 '' '' @{ Group = 'memory' }), (New-Ev 10)))[1] | Should -Contain 'resource'
    }
    It 'afterhang: Haenger derselben Anwendung in derselben Sitzung hoechstens 2 Minuten vorher' {
        (Get-Pat @((New-Ev 8 'hang'), (New-Ev 10)) | Select-Object -Last 1) | Should -Contain 'afterhang'
        (Get-Pat @((New-Ev 7 'hang'), (New-Ev 10)) | Select-Object -Last 1) | Should -Not -Contain 'afterhang'
        (Get-Pat @((New-Ev 9 'hang' -Sid 4 -User 'user003'), (New-Ev 10)) | Select-Object -Last 1) | Should -Not -Contain 'afterhang'
    }
    It 'sharedmodule: zwei Anwendungen im selben Modul, kein Systemmodul' {
        $p = Get-Pat @((New-Ev 0 -Module 'simaddin.dll'), (New-Ev 1 -App 'WINWORD.EXE' -Module 'simaddin.dll')); $p[0] | Should -Contain 'sharedmodule'; $p[1] | Should -Contain 'sharedmodule'
        (Get-Pat @((New-Ev 0 -Module 'ntdll.dll'), (New-Ev 1 -App 'WINWORD.EXE' -Module 'NTDLL.dll')))[0] | Should -Not -Contain 'sharedmodule'
    }
    It 'printdriver und securitymodule nach Treiberliste und Rollen' {
        (Get-Pat @(New-Ev 0 -Module 'HPSIMGR.DLL'))[0] | Should -Contain 'printdriver'
        (Get-Pat @(New-Ev 0 -Module 'MpOav.dll'))[0] | Should -Be @('securitymodule')
    }
    It 'manyusers ab drei Benutzern, oneuser ab drei Ereignissen eines Benutzers' {
        (Get-Pat @((New-Ev 0), (New-Ev 1 -Sid 4 -User 'u3'), (New-Ev 2 -Sid 5 -User 'u4')))[0] | Should -Be @('manyusers')
        (Get-Pat @((New-Ev 0), (New-Ev 1 -Sid 4 -User 'u3')))[0].Count | Should -Be 0
        (Get-Pat @((New-Ev 0), (New-Ev 1), (New-Ev 2)))[0] | Should -Be @('oneuser')
    }
    It 'companion mit Uhrzeit, overlap mit gegenseitigem Verweis' {
        $perf = @(@{ Id = 1; StartMs = $T0 + 9 * 60000; EndMs = $T0 + 11 * 60000 })
        $p = Get-Pat @((New-Ev 8.5 'system' '' 0 '' '' @{ Group = 'storage'; Object = 'D:' }), (New-Ev 10)) -Perf $perf
        $p[1] | Should -Be @('companion', 'overlap'); $perf[0].EventIncidents | Should -Be @(10)
    }
    It 'nennt mehrere Muster zugleich und sagt es, wenn keines zutrifft' {
        $evs = @((New-Ev 0 -Module 'simaddin.dll'), (New-Ev 1 -Module 'simaddin.dll'), (New-Ev 2 -Module 'simaddin.dll'), (New-Ev 3 -App 'WINWORD.EXE' -Module 'simaddin.dll'))
        $inc = Get-Inc $evs
        Add-WorkerPerfEventPatterns -Incidents $inc -AllEvents $evs -Model (New-PatternModel (@(50) * 60)) -Thresholds $Th -Settings $Set -Config $Cfg -Roles $Roles -Drivers $Drv -PerfIncidents @()
        $texts = Read-WorkerPerfTexts (Join-Path $PSScriptRoot '../src/texts.de.json')
        $t = Get-WorkerPerfEventIncidentText -Incident $inc[0] -Model $null -Texts $texts -Config $Cfg -OffsetMinutes 0
        $t | Should -Match '^\d\d:\d\d:\d\d–\d\d:\d\d:\d\d: Absturz von EXCEL\.EXE \(3-mal\)\. Benutzer: user002\. Fehlerhaftes Modul: simaddin\.dll, immer dasselbe\. Fehlercode: 0xc0000005 \(Zugriffsverletzung\)\.'
        $t | Should -Match 'Ursache liegt wahrscheinlich im Modul simaddin\.dll \(betrifft EXCEL\.EXE, WINWORD\.EXE\)\. Nur user002 betroffen, 3-mal: spricht für Profil oder Daten dieses Benutzers\.$'
        $pe = @(New-Ev 0 'profileerror' '' 3 'user002' '' @{ Group = 'profile'; Source = 'Microsoft-Windows-User Profiles Service' }); $one = Get-Inc $pe
        Add-WorkerPerfEventPatterns -Incidents $one -AllEvents $pe -Model (New-PatternModel (@(50) * 60)) -Thresholds $Th -Settings $Set -Config $Cfg -Roles $Roles -Drivers $Drv -PerfIncidents @()
        (Get-WorkerPerfEventIncidentText -Incident $one[0] -Model $null -Texts $texts -Config $Cfg -OffsetMinutes 0) | Should -Match 'Kein Muster erkannt\.$'
    }
    It 'prueft im Rueckblick nur Muster ohne Messwerte' {
        $perf = @(@{ Id = 1; StartMs = $T0; EndMs = $T0 + 60000 })
        (Get-Pat @((New-Ev 0), (New-Ev 1), (New-Ev 2)) (New-PatternModel (@(95) * 60)) $perf -Before)[0] | Should -Be @('oneuser')
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Events.Tests.ps1 -Output Minimal"`
Expected: FAIL, `Add-WorkerPerfEventPatterns` nicht definiert

- [ ] **Step 3: Muster, Rollenfeld `modules` und Klartext mit den Signaturen der Interfaces umsetzen**

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Events.ps1 src/WorkerPerf.Common.ps1 src/roles.json src/texts.de.json tests/Events.Tests.ps1
git commit -m "Match event incidents against measurement patterns and describe them"
```

---

### Task 7: Auswertung – Rückblick und Druckzustand

**Files:**
- Modify: `src/WorkerPerf.Events.ps1`, `src/WorkerPerf.Common.ps1` (`$script:WorkerPerfRoleNames` um `Drucken`), `src/roles.json`
- Test: `tests/Events.Tests.ps1`

**Interfaces:**
- Consumes: Tasks 5 und 6; Modell (`EventsBefore`, `PrintDrivers`, `PrintQueues`, `Proc`, `Tick.TimeMs`, `Meta`).
- Produces:
  - Rollen in `roles.json`: `Drucken` / „Druckdienst" (`spoolsv.exe`, `PrintIsolationHost.exe`, `splwow64.exe`; Dienst `Spooler`), `Drucken` / „Citrix-Druckverwaltung" (`cpsvc.exe`; Hinweis „ungeprüft"), vor dem Eintrag „Citrix VDA".
  - `Get-WorkerPerfLookback -Model -Config -Settings -Roles -FirstId [int] -ReportedMs [object] -> @{ Days; FromMs; Capped = string[]; EventCount; Incidents; PerDay = @(@{ Day = 'yyyy-MM-dd'; Count }); Near = object[] }`. Berücksichtigt nur Ereignisse von `EventsBefore` vor dem ersten Takt; Vorfälle über `New-WorkerPerfEventIncidents -Before` und `Add-WorkerPerfEventPatterns -Before` (Treiber aus `Model.PrintDrivers`, fehlend = leer); `PerDay` zählt Ereignisse mit Vorfallsart je Tag in Ortszeit des Servers (`Meta.OffsetMinutes`), aufsteigend; `Near` sind alle Ereignisse in ±15 min um `ReportedMs`, nur wenn `ReportedMs` vor dem ersten Takt liegt.
  - `Get-WorkerPerfPrintState -Model -EventIncidents [object[]] -> @{ Drivers; Queues; Processes }`: `Drivers` je Treiber `@{ Name; Manufacturer; Version; Type; Isolation; Isolated = (Isolation -eq 'isolated'); Files; Involved }` (`Involved`: Schlüssel eines `print`-Vorfalls oder Treiber eines Musters `printdriver`); `Queues` je Warteschlange `@{ Name; MaxJobs; JobErrors; NotReadyErrors }` – Fehler als Summe der positiven Zuwächse der fortlaufenden Zähler; `Processes` je Prozess der Rolle `Drucken` `@{ K; Name; CpuMaxPct; WsMaxMB }`.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben**

```powershell
Describe 'Rueckblick und Druckzustand' {
    BeforeAll {
        function New-LbModel([object[]]$Before) { @{ EventsBefore = $Before; Tick = @{ TimeMs = [long[]]@($T0, $T0 + 60000) }; Meta = @{ OffsetMinutes = 60; EventLookbackDays = 7; LookbackCapped = @('system') }; Sessions = @() } }
    }
    It 'trennt den Rueckblick von der Messzeit und zaehlt je Tag' {                               # Review Focus 3
        $m = New-LbModel @((New-Ev (-3 * 1440)), (New-Ev (-3 * 1440 + 10)), (New-Ev (-3 * 1440 + 20)), (New-Ev (-1440) -App 'WINWORD.EXE'), (New-Ev 0))
        $l = Get-WorkerPerfLookback -Model $m -Config $Cfg -Settings $Set -Roles $Roles -FirstId 20 -ReportedMs $null
        $l.EventCount | Should -Be 4; @($l.Incidents).Count | Should -Be 2; $l.Incidents[0].Before | Should -BeTrue; $l.Incidents[0].Id | Should -Be 20
        @($l.Incidents[0].Patterns | ForEach-Object Id) | Should -Be @('oneuser'); @($l.PerDay).Count | Should -Be 2; $l.PerDay[0].Count | Should -Be 3
        $l.Capped | Should -Be @('system'); $l.Days | Should -Be 7
    }
    It 'liefert Ereignisse um eine gemeldete Zeit vor der Messung' {
        $m = New-LbModel @((New-Ev -100), (New-Ev -80), (New-Ev -40))
        @((Get-WorkerPerfLookback -Model $m -Config $Cfg -Settings $Set -Roles $Roles -FirstId 1 -ReportedMs ($T0 - 90 * 60000)).Near).Count | Should -Be 2
        @((Get-WorkerPerfLookback -Model $m -Config $Cfg -Settings $Set -Roles $Roles -FirstId 1 -ReportedMs ($T0 + 60000)).Near).Count | Should -Be 0
    }
    It 'liefert den Druckzustand' {
        $m = @{ PrintDrivers = @(@{ Name = 'Sim PCL 6'; Manufacturer = 'HP'; Version = '61'; Type = 3; Isolation = 'none'; Files = @('hpsimgr.dll') }, @{ Name = 'Sim KX'; Manufacturer = 'Kyocera'; Version = '8'; Type = 3; Isolation = 'isolated'; Files = @('kx.dll') })
            PrintQueues = @(@{ TimeMs = $T0; Queue = 'Q1'; Jobs = 0; JobErrors = 5; NotReadyErrors = 0 }, @{ TimeMs = $T0 + 15000; Queue = 'Q1'; Jobs = 3; JobErrors = 6; NotReadyErrors = 0 },
                            @{ TimeMs = $T0 + 30000; Queue = 'Q1'; Jobs = 1; JobErrors = 0; NotReadyErrors = 0 }, @{ TimeMs = $T0 + 45000; Queue = 'Q1'; Jobs = 0; JobErrors = 2; NotReadyErrors = 0 })
            Proc = @(@{ K = 0; Name = 'spoolsv.exe'; Role = 'Drucken'; CpuMaxPct = 1.5; WsMaxKB = 40960 }, @{ K = 1; Name = 'EXCEL.EXE'; Role = ''; CpuMaxPct = 9; WsMaxKB = 1 }) }
        $s = Get-WorkerPerfPrintState -Model $m -EventIncidents @(@{ Kind = 'print'; Key = 'Sim PCL 6'; Patterns = @() })
        ($s.Drivers | Where-Object Name -eq 'Sim PCL 6').Involved | Should -BeTrue; ($s.Drivers | Where-Object Name -eq 'Sim KX').Isolated | Should -BeTrue
        $s.Queues[0].MaxJobs | Should -Be 3; $s.Queues[0].JobErrors | Should -Be 3                  # 5 -> 6 (+1), Neustart auf 0, 0 -> 2 (+2)
        @($s.Processes).Name | Should -Be @('spoolsv.exe'); $s.Processes[0].WsMaxMB | Should -Be 40
    }
}
```

Dazu in `tests/Common.Tests.ps1`: `(Resolve-WorkerPerfRole $Roles 'spoolsv.exe' 'Spooler' 0).Role | Should -Be 'Drucken'`.

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Events.Tests.ps1,tests/Common.Tests.ps1 -Output Minimal"`
Expected: FAIL, `Get-WorkerPerfLookback` nicht definiert

- [ ] **Step 3: Rückblick, Druckzustand und Rolle mit den Signaturen der Interfaces umsetzen**

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Events.ps1 src/WorkerPerf.Common.ps1 src/roles.json tests/Events.Tests.ps1 tests/Common.Tests.ps1
git commit -m "Summarise the days before the capture and the print state"
```

---

### Task 8: Berichtsdaten

**Files:**
- Modify: `src/New-WorkerPerfReport.ps1` (nach Zeile 292 die Auswertung, Zeilen 499–503 Ereignisse, Sitzungen Zeilen 554–565, Vorfälle Zeilen 708–717, Prozessauswahl Zeilen 749–751, `$data` Zeile 819), `src/WorkerPerf.Findings.ps1` (eine Zeile in `Add-WorkerPerfIncidentDetail`: Ereignisse im Fenster ohne die Gruppen `app`, `service`, `session`), `src/WorkerPerf.Events.ps1` (Ausgabefunktionen), `tests/TestHelpers.ps1` (`New-TestReports`)
- Test: `tests/Report.Tests.ps1`

**Interfaces:**
- Consumes: Tasks 5–7.
- Produces – Berichtsdaten (das Format für Task 9 und die beiden Folgepläne):
  - `ConvertTo-WorkerPerfEventOut($Event) -> ordered` `{ t, log, source, id, level, group, kind, app, module, code, s, user, printer, driver, service, object, text }` (`s` = Sitzungsindex oder -1); ersetzt `ConvertTo-EventEntry`.
  - `ConvertTo-WorkerPerfEventIncidentOut -Incident -Text [string] -Focus [bool] -Near [bool] -> ordered`: alle Schlüssel eines heutigen Vorfalls mit neutralen Werten (`type = 'ereignis'`, `chronic = $false`, `lead = $null`, `resources = @()`, `signals`, `affected`, `delayProcs`, `endpoints`, `ica`, `chronicContext` = `@()`, `contributors = {}`, `main`, `cause`, `companion` = `$null`, `security = { products: [], totalPct: null }`, `scanActive = $false`, `eventIncidents = @()`), `events` = Ereignisse des Vorfalls, dazu `event = { kind, key, count, users, sessions, inSession, versions, modules [{name, count}], sameModule, codes [{code, text, count}], app, service, driver, printer, source, before, patterns [{id, text, detail}], overlap, companions [{t, group, source, id, kind}] }`. `patterns[].text` ist die Aussage aus `texts.de.json` ohne führendes Leerzeichen; `detail` ist `Detail` aus Task 6 mit kleingeschriebenen Schlüsseln (`signalId`, `peak`, `warningMs`, `hangMs`, `module`, `apps`, `driver`, `product`, `users`, `user`, `count`, `incidents`; `events` als Ereignisse in der neuen Form).
  - `incidents`: erst die Leistungsvorfälle wie bisher, jeder mit `eventIncidents` (int[]), dann die Ereignisvorfälle der Messzeit; Ids fortlaufend (`FirstId` = Zahl der Leistungsvorfälle + 1). `focus`: ein Sitzungsindex oder Benutzer des Vorfalls gehört zu `-FocusUser`; `nearReported` mit dem Umkreis von 15 min wie bisher.
  - `before = { days, from, capped, eventCount, perDay [{day, count}], incidents [...], near [Ereignisse] }`; Ids nach den Ereignisvorfällen.
  - `print = { drivers [{name, manufacturer, version, type, isolation, isolated, files, involved}], queues [{name, maxJobs, jobErrors, notReadyErrors}], processes [{k, name, cpuMax, wsStartMB, wsEndMB, wsMaxMB}] }`; Prozesse der Rolle `Drucken` kommen immer in `procs`; `wsStartMB`/`wsEndMB` aus ihrer Reihe, gerundet auf ganze MB.
  - `events`: alle Ereignisse der Messzeit in der neuen Form; `sessions[].events`: Positionen in `events` der Gruppe `session` dieser Sitzung.
  - `noFinding` bleibt `incOut.Count -eq 0`.
- `New-TestReports`: `report-none.html` entsteht aus einer Kopie ohne `events.csv` und `events_before.csv` (`Copy-SimRun … @('events.csv', 'events_before.csv')`), weil der Bericht ohne Befund sonst die Ereignisvorfälle zeigte; alle Aussagen über diesen Bericht bleiben.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/Report.Tests.ps1`)

```powershell
# Aussage geaendert in 'findet genau die Vorfaelle des Drehbuchs': der Vergleich laeuft ueber die Zeilen der Messzeit,
# weil expected.json jetzt auch den Rueckblick nennt
$D.incidents.Count | Should -Be @($Exp | Where-Object { -not $_.Before }).Count
foreach ($e in @($Exp | Where-Object { -not $_.Before })) { … }                                  # Rest unveraendert

Describe 'Ereignisvorfaelle im Bericht' {
    It 'bildet die Ereignisvorfaelle und Muster des Drehbuchs' {
        foreach ($e in @($Exp | Where-Object { $_.Type -eq 'ereignis' })) {
            $pool = if ($e.Before) { $D.before.incidents } else { $D.incidents }
            $hit = @($pool | Where-Object { $_.type -eq 'ereignis' -and $_.event.kind -eq $e.Kind -and [Math]::Abs($_.start - $e.StartMs) -le 20000 })
            $hit.Count | Should -Be 1 -Because $e.Key
            @($hit[0].event.patterns | ForEach-Object { $_.id }) | Should -Be @($e.Patterns) -Because $e.Key
        }
    }
    It 'nennt Anwendung, Modul, Benutzer und die Aussagen der Muster' {
        $i = $D.incidents | Where-Object { $_.event -and $_.event.app -eq 'OUTLOOK.EXE' }
        $i.event.count | Should -Be 3; $i.event.users | Should -Be @('user010', 'user011', 'user012'); $i.event.sameModule | Should -BeTrue
        $i.text | Should -Match 'Absturz von OUTLOOK\.EXE \(3-mal\)\..*olmapi32\.dll, immer dasselbe.*3 Benutzer betroffen: spricht für Installation oder Update\.'
        $m = $D.incidents | Where-Object { $_.event -and $_.event.app -eq 'chrome.exe' }
        $mem = $D.incidents | Where-Object lead -eq 'memory'
        $m.event.overlap | Should -Be @($mem.id); $mem.eventIncidents | Should -Be @($m.id); $m.text | Should -Match 'Wahrscheinlich Folge des Speichermangels\.'
        ($D.incidents | Where-Object { $_.event -and $_.event.kind -eq 'profileerror' }).text | Should -Match 'Kein Muster erkannt\.$'
    }
    It 'liefert Rueckblick, Druckzustand und Sitzungsereignisse' {
        $D.before.days | Should -Be 7; $D.before.eventCount | Should -Be 5; ($D.before.perDay | Measure-Object count -Sum).Sum | Should -Be 5
        ($D.print.drivers | Where-Object involved).name | Should -Be 'HP Universal Printing PCL 6 (Sim)'
        ($D.print.queues | Where-Object name -eq 'PRN-EG-01').maxJobs | Should -Be 3; ($D.print.queues | Where-Object name -eq 'PRN-EG-01').jobErrors | Should -Be 1
        @($D.print.processes).name | Should -Contain 'spoolsv.exe'
        $s = $D.sessions | Where-Object user -eq 'user014'; @($s.events | ForEach-Object { $D.events[$_].kind }) | Should -Be @('logoff', 'logon')
        ($D.events | Where-Object app -eq 'chrome.exe').user | Should -Be 'user008'
    }
    It 'laesst die acht Leistungsvorfaelle mit und ohne die neuen Ereignisse gleich' {
        $dir = Copy-SimRun $R.Run (Join-Path $TestDrive 'onlysec') @('events_before.csv')
        $f = Join-Path $dir 'events.csv'; $lines = [IO.File]::ReadAllLines($f)
        [IO.File]::WriteAllLines($f, @($lines[0]) + @($lines | Select-Object -Skip 1 | Where-Object { (Split-WorkerPerfCsvLine $_)[5] -eq 'security' }))
        $out = Join-Path $TestDrive 'onlysec.html'; [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $dir -OutFile $out -RoleFile (Join-Path $TestDrive 'r/roles.sim.json') 6>$null)
        $strip = { param($i) $c = $i.PSObject.Copy(); $c.PSObject.Properties.Remove('eventIncidents'); $c.PSObject.Properties.Remove('events'); $c | ConvertTo-Json -Depth 8 }
        $a = @($D.incidents | Where-Object type -ne 'ereignis'); $b = @((Get-ReportData $out).incidents)
        $b.Count | Should -Be 8; for ($k = 0; $k -lt 8; $k++) { & $strip $a[$k] | Should -Be (& $strip $b[$k]) }
    }
    It 'wertet eine Aufzeichnung im Format 2 weiter aus' {
        $dir = Copy-SimRun $R.Run (Join-Path $TestDrive 'v2') @('events_before.csv', 'printdrivers.csv', 'printqueues.csv')
        $meta = Join-Path $dir 'meta.json'; [IO.File]::WriteAllText($meta, ([IO.File]::ReadAllText($meta) -replace '"SchemaVersion":\s*3', '"SchemaVersion": 2'))
        $f = Join-Path $dir 'events.csv'
        $rows = @([IO.File]::ReadAllLines($f) | Select-Object -Skip 1 | ForEach-Object { $x = Split-WorkerPerfCsvLine $_; if ($x[5] -eq 'security') { '{0},{1},{2},{3},{4}' -f $x[0], $x[2], $x[3], $x[6], $x[19] } })
        [IO.File]::WriteAllLines($f, @('Timestamp,Source,EventId,Kind,Text') + $rows)
        $out = Join-Path $TestDrive 'v2.html'; [void](& (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $dir -OutFile $out 6>$null)
        $d2 = Get-ReportData $out; @($d2.incidents | Where-Object type -eq 'ereignis').Count | Should -Be 0; @($d2.incidents).Count | Should -Be 8
        @($d2.before.incidents).Count | Should -Be 0; @($d2.print.drivers).Count | Should -Be 0
    }
}
```

`Split-WorkerPerfCsvLine` steht dem Test über `. (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1')` in `BeforeAll` zur Verfügung.

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Report.Tests.ps1 -Output Minimal"`
Expected: FAIL, keine Ereignisvorfälle in den Berichtsdaten

- [ ] **Step 3: Auswertung verdrahten und die Daten mit den Ausgabefunktionen der Interfaces schreiben**

Reihenfolge im Berichtsskript: `Read-WorkerPerfEventConfig` (`src/events.json` neben dem Skript), `Read-WorkerPerfEventSettings $ThresholdFile`, `Set-WorkerPerfEventSessions`, `New-WorkerPerfEventIncidents`, `Add-WorkerPerfEventPatterns`, `Get-WorkerPerfLookback`, `Get-WorkerPerfPrintState`, Texte über `Get-WorkerPerfEventIncidentText`.

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`, danach die Browserprüfungen (Global Constraints)
Expected: `Failed: 0`; die Browserprüfungen dürfen hier noch an den neuen Vorfällen scheitern (Task 9)

- [ ] **Step 5: Commit**

```bash
git add src/New-WorkerPerfReport.ps1 src/WorkerPerf.Findings.ps1 src/WorkerPerf.Events.ps1 tests/TestHelpers.ps1 tests/Report.Tests.ps1
git commit -m "Put event incidents, lookback and print state into the report data"
```

---

### Task 9: Anzeige im heutigen Bericht, README, Demo-Seite

**Files:**
- Modify: `src/report-template.html` (Kopfsatz der Befunde ab Zeile 1041, Zeitleiste `drawTimeline` Zeile 1118, Vorfallsliste und `renderDetail` ab Zeile 1196, Sitzungsansicht `showSession` Zeile 929, neue Blöcke im Reiter Befunde), `tests/report-browser.js`, `README.md` (Abschnitte „Ablauf", „Der Bericht", „Datenformat", „Datenquellen"), `pages/index.html`

**Interfaces:**
- Consumes: Berichtsdaten aus Task 8.
- Produces – Bezeichner (plan 3 übernimmt sie):
  - Vorfallsliste: Ereignisvorfälle als `.incident.type-ereignis[data-id]` mit `.text` (der Satz), `.badge` (Symbol und Wort der Schwere) und im aufgeklappten `.detail` `.patterns li` (eine Zeile je Muster, sonst „Kein Muster erkannt"), `.evlist` (Ereignisse des Vorfalls) und Verweisen `.lnk[data-incident]` auf überlappende Vorfälle; Leistungsvorfälle zeigen ihre `eventIncidents` ebenso.
  - Zeitleiste: Ereignisvorfälle als `.mark.type-ereignis` in der Zeile „Vorfälle"; Ereignisse je Gruppe in eigener Zeile (`.tl-row[data-group]`, Beschriftung aus einer Tabelle `GROUP_WORD`: Anwendungen, Dienste, Datenträger, Speicher, Dateiserver, Profile, Drucken, Sitzungen, Schutzsoftware) als `.event[data-group][data-kind]`; Legende nennt die Gruppen.
  - `#before` (Karte im Reiter Befunde, nur wenn `before.eventCount` > 0 oder `before.capped` nicht leer): Überschrift „Vor der Messung", Hinweis „Für diese Zeit liegen keine Messwerte vor.", Balken je Tag (`.day`), Liste der Rückblick-Vorfälle (`.incident` wie oben), Hinweis auf unvollständige Protokolle, Ereignisse um die gemeldete Zeit.
  - `#print` (Karte „Drucken", nur mit Treibern oder Warteschlangen): Tabellen `#tPrintDrivers` (Name, Hersteller, Version, Bauart „Typ 3"/„Typ 4", Isolierung, beteiligt) und `#tPrintQueues` (Warteschlange, höchste Zahl wartender Aufträge, Auftragsfehler, „nicht bereit"), Prozesse der Rolle Drucken mit Höchstwerten und Arbeitsspeicher am Anfang, am Ende und höchstens.
  - Sitzungsansicht: `.sess-events` mit den Sitzungsereignissen (Zeit, Art).

- [ ] **Step 1: Die Browserprüfung erweitern** (`tests/report-browser.js`, neue Funktion, in der Schleife nach `checkFinalFix` aufrufen; keine bestehende Aussage ändert sich)

```js
async function checkEvents(browser, dir, scheme) {                 // Ereignisse, Abstuerze, Drucken
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme);
  const ev = D.incidents.filter((i) => i.type === 'ereignis');
  ok(ev.length === 4 && await page.locator('#incidents .incident.type-ereignis').count() === ev.length, 'Ereignisvorfaelle in der Liste');
  ok(await page.locator('#timeline .mark.type-ereignis').count() === ev.length, 'Ereignisvorfaelle in der Zeitleiste');
  for (const g of ['app', 'session', 'security', 'profile']) ok(await page.locator(`#timeline .tl-row[data-group="${g}"] .event`).count() === D.events.filter((e) => e.group === g).length, 'Ereigniszeile ' + g);
  const many = ev.find((i) => i.event.app === 'OUTLOOK.EXE');
  const entry = await openIncident(page, many.id);
  ok((await entry.locator('.detail .patterns').innerText()).includes('spricht für Installation oder Update'), 'Aussage des Musters');
  const prof = ev.find((i) => i.event.kind === 'profileerror');
  ok((await (await openIncident(page, prof.id)).locator('.detail .patterns').innerText()).includes('Kein Muster erkannt'), 'kein Muster');
  ok((await page.locator('#before').innerText()).includes('Für diese Zeit liegen keine Messwerte vor.'), 'Vor der Messung mit Hinweis');
  ok(await page.locator('#before .day').count() === D.before.perDay.length && await page.locator('#before .incident').count() === D.before.incidents.length, 'Rueckblick je Tag und Vorfall');
  ok(await page.locator('#tPrintDrivers tbody tr').count() === 3 && (await page.locator('#tPrintQueues').innerText()).includes('PRN-EG-01'), 'Tabelle Drucken');
  await page.click('nav button[data-tab=sessions]');
  const s14 = D.sessions.find((s) => s.user === 'user014');
  await page.click(`#tSessions tbody tr[data-id="${s14.i}"]`);
  ok(await page.locator('#dSessions .sess-events li').count() === 2, 'Sitzungsereignisse bei der Sitzung');
  ok(page.errors.length === 0, 'Skriptfehler: ' + page.errors.join(' | '));
  await page.close();
}
```

- [ ] **Step 2: Prüfung ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/New-TestReports.ps1 -OutDir /tmp/wp-reports && node tests/report-browser.js /tmp/wp-reports`
Expected: `AssertionError: Ereignisvorfaelle in der Liste` (oder schon eine bestehende Prüfung, weil `renderDetail` den Typ `ereignis` nicht kennt)

- [ ] **Step 3: Anzeige bauen**

Kopfsatz der Befunde: zusätzliche Art „Vorfall aus Ereignissen"/„Vorfälle aus Ereignissen". `renderDetail` erhält einen Zweig für `type === 'ereignis'` (Kopfzeile mit Anzahl, Zeitspanne, Benutzern, Modul; dann Muster, Ereignisse, Verweise); `markLabel` liefert für Ereignisvorfälle das Wort der Art (Absturz, Hänger, Dienst, Drucken, Profil, System). Alle Texte der Seite für Gruppen und Arten stehen in einer Tabelle am Anfang des Skriptteils, wie `TYPE_WORD`.

- [ ] **Step 4: Prüfungen ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"` und die Browserprüfungen
Expected: `Failed: 0` und `browser checks passed: <n>`

- [ ] **Step 5: Seite ansehen** – Bildschirmfotos des Reiters Befunde (hell und dunkel) mit aufgeklapptem Absturz, `#before` und `#print`; Zeitleiste auf überlappende Zeilen und abgeschnittene Beschriftungen prüfen; Mängel beheben, Step 4 wiederholen.

- [ ] **Step 6: README und Demo-Seite**

README: Parameter `-EventLookbackDays`; Format 3 mit den neuen Spalten und Dateien, „liest die Formate 2 und 3"; Tabelle der Ereignisquellen nach Abschnitt 3 der Spezifikation mit `events.json` als Ort der Liste; Vorfallsarten und Muster mit ihren Aussagen; Blöcke „Vor der Messung" und „Drucken"; Demo-Beschreibung „acht Leistungsvorfälle und vier Vorfälle aus Ereignissen". Demo neu erzeugen:

```powershell
$run = .\src\Start-WorkerPerfCapture.ps1 -Simulate -DurationMinutes 60 -OutputPath .\demo
.\src\New-WorkerPerfReport.ps1 -Path $run -OutFile .\pages\index.html
```

- [ ] **Step 7: Commit**

```bash
git add src/report-template.html tests/report-browser.js README.md pages/index.html
git commit -m "Show event incidents, the days before the capture and printing in the report"
```

---

### Task 10: Windows-Datenquelle – Ereignisse, Treiberliste, Warteschlangen

**Voraussetzung:** Das Ergebnis des erweiterten Prüfskripts (Task 1) vom Zielserver liegt in der Sitzung vor (hochgeladen, nicht eingecheckt). Ohne dieses Ergebnis wird die Task nicht begonnen.

**Files:**
- Modify: `src/WorkerPerf.Sources.Windows.ps1` (`$script:WorkerPerfWinEventLogs` Zeilen 366–371, `ConvertTo-WorkerPerfEventKind` Zeilen 877–887 und `Get-WorkerPerfEventText` Zeilen 889–898 entfallen, Ereignisteil in `Initialize-WorkerPerfSource` Zeilen 1187–1200, `Get-WorkerPerfEvents` Zeilen 1327–1365, die leeren Funktionen aus Task 3), `src/Start-WorkerPerfCapture.ps1` (Konfiguration an die Quelle übergeben), `src/WorkerPerf.Sources.Simulation.ps1` (Parameter annehmen), `src/events.json`, `tests/WindowsStandIns.ps1`, `README.md` (Abschnitt „Datenquellen")
- Test: `tests/WindowsSource.Tests.ps1`

**Interfaces:**
- Consumes: Tasks 2 und 3.
- Produces:
  - `Initialize-WorkerPerfSource` beider Quellen erhält `[object]$EventConfig = $null`; der Collector übergibt `Read-WorkerPerfEventConfig (Join-Path $PSScriptRoot 'events.json')`. Die Windows-Quelle liest je Protokoll aus `events.json` (Einträge gruppiert, höchstens 23 Kennungen je Abfrage), meldet `Sources['events.<id>']` je Protokoll-Id (Detail: gelesene Protokollnamen bzw. „Protokoll nicht vorhanden oder abgeschaltet").
  - `Get-WorkerPerfEvents` und `Get-WorkerPerfEventsBefore` lesen `$ev.ToXml()` und setzen Datensätze über `ConvertFrom-WorkerPerfEventXml`, `Resolve-WorkerPerfEventEntry` und `ConvertTo-WorkerPerfEventRecord`; höchstens 200 je Protokoll und Abruf wie bisher, im Rückblick höchstens `$script:WorkerPerfWinLookbackMax = 2000` je Protokoll (bei Erreichen Protokoll-Id in `Capped`); Protokolle mit `lookback: false` werden im Rückblick nicht gelesen.
  - `Get-WorkerPerfPrintDrivers`: `Get-CimInstance -Namespace root/StandardCimv2 -ClassName MSFT_PrinterDriver`; Helfer ohne Windows-Aufruf `ConvertFrom-WorkerPerfDriverVersion([uint64]$Value) -> string` (vier 16-Bit-Teile, `a.b.c.d`) und `ConvertFrom-WorkerPerfIsolationGroups([string]$Value) -> hashtable` (Treibername → `none`/`shared`/`isolated`); Dateien = Dateinamen ohne Pfad aus Treiber-, Konfigurations-, Daten- und abhängigen Dateien, ohne Doppelte.
  - `Get-WorkerPerfPrintQueues`: Kategorie `Print Queue`, Zähler `Jobs`, `Job Errors`, `Not Ready Errors`, alle Instanzen außer `_Total`, Rohwerte über `Read-WorkerPerfWinCategory` und `Get-WorkerPerfWinInstantValue`.

- [ ] **Step 1: Prüfergebnis einarbeiten**

Aus dem Ergebnis lesen und in `src/events.json` übernehmen: je `events.*`-Prüfung, welche Protokolle existieren und eingeschaltet sind; welche Kennungen der Quellen `Citrix*` in den Protokollen `Application` und `System` vorkamen (Citrix-Druckverwaltung → Gruppe `print`, Profilverwaltung → Gruppe `profile`, mit Art und Feldern) und welche Feldnamen jede Kennung hat (benannt → Datenname, unbenannt → `#n`; bei `Service Control Manager` zeigt das Vorhandensein von `binary`, ob `binary:utf16` den Dienstnamen liefert, sonst `#0`, dann stehen in `importantServices` die Anzeigenamen in der Sprache des Servers und der README sagt das). Aus `print.drivers`: Eigenschaftsnamen von `MSFT_PrinterDriver` (`Manufacturer`, `MajorVersion`, `DriverVersion`, Dateieigenschaften) und ob `PrintDriverIsolationGroups` vorhanden ist; fehlt es, bleibt `Isolation` leer und der README nennt den Grund. Aus `print.queues`: ob die Kategorie mit den drei Zählern besteht. Keine Kennung, kein Name und kein Wert aus dem Ergebnis gelangt in Tests oder Repository außer den Quellen-, Kennungs- und Feldnamen in `events.json`. **Abbruchbedingung:** Liefert `ToXml()` für `Application Error` 1000 keine Datenfelder, diese Task anhalten und den Plan überarbeiten.

- [ ] **Step 2: Die fehlschlagenden Tests schreiben**

Die Platzhalter in `tests/WindowsStandIns.ps1` erhalten: Ereignisse mit `ProviderName`, `Id`, `TimeCreated`, `Message`, `LogName` und einer Methode `ToXml()` (erfundene Werte), eine Liste `$script:WinFake.Drivers` für `MSFT_PrinterDriver`, `$script:WinFake.IsolationGroups`, die Kategorie `Print Queue` in `Perf` und `$script:WinFake.Logs` mit allen Protokollen aus `events.json`.

```powershell
# Aussage ersetzt: 'bildet Ereigniskennungen auf Arten ab' prueft jetzt die Zuordnung ueber events.json, weil die feste Zuordnung dorthin umzieht
It 'liefert Ereignisse mit strukturierten Feldern ueber events.json' {
    [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null)
    $ev = @(Get-WorkerPerfEvents -Since ([datetime]::Now.AddMinutes(-5)))
    @($ev | Where-Object Group -eq 'security').Kind | Should -Be @('scan-start', 'scan-end')
    $c = $ev | Where-Object Kind -eq 'crash'; $c.App | Should -Be 'EXCEL.EXE'; $c.Module | Should -Be 'vbe7.dll'; $c.Pid | Should -Be 7964; $c.Log | Should -Be 'application'
}
# Aussage geaendert: 300 statt 200 Zeichen (Abschnitt 4.1 der Spezifikation); die Funktion liegt jetzt in WorkerPerf.EventConfig.ps1
It 'kuerzt Ereignistexte auf die erste Zeile und 300 Zeichen' { (Get-WorkerPerfEventText ('x' * 400)).Length | Should -Be 300 }
It 'liest den Rueckblick ohne Sitzungsprotokoll und vermerkt die Obergrenze' {
    [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null)
    $script:WinFake.ManyEvents = 2500
    $b = Get-WorkerPerfEventsBefore -Days 7 -Until ([datetime]::Now)
    $b.Capped | Should -Contain 'defender'; @($b.Events | Where-Object Log -eq 'defender').Count | Should -Be 2000
    @($b.Events | Where-Object Group -eq 'session').Count | Should -Be 0
}
It 'meldet ein fehlendes Protokoll als nicht verfuegbar und liest die anderen' {
    $script:WinFake.Logs = @($script:WinFake.Logs | Where-Object { $_ -ne 'Microsoft-Windows-PrintService/Admin' })
    $info = Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null
    $info.Sources['events.printservice'].Available | Should -BeFalse; $info.Sources['events.application'].Available | Should -BeTrue
    @(Get-WorkerPerfEvents -Since ([datetime]::Now.AddMinutes(-5)) 3>$null).Count | Should -BeGreaterThan 0
}
It 'liefert Treiberliste und Warteschlangen' {
    [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null)
    $d = @(Get-WorkerPerfPrintDrivers); $d.Count | Should -Be 2
    ($d | Where-Object Name -eq 'Sim PCL 6').Isolation | Should -Be 'none'; ($d | Where-Object Name -eq 'Sim PCL 6').Type | Should -Be 3
    ($d | Where-Object Name -eq 'Sim PCL 6').Files | Should -Be @('hpsimgr.dll', 'hpsimui.dll')
    ConvertFrom-WorkerPerfDriverVersion ([uint64]((61 -shl 48) + (1 -shl 32) + 2)) | Should -Be '61.1.0.2'
    $q = @(Get-WorkerPerfPrintQueues); $q.Queue | Should -Be @('PRN-TEST-01'); $q[0].JobErrors | Should -Be 4
}
```

`$Cfg` liest die Testdatei in `BeforeAll` über `Read-WorkerPerfEventConfig`; die Datei bindet dafür `WorkerPerf.EventConfig.ps1` ein. Der bestehende Durchlauf des Collectors mit der Windows-Quelle prüft zusätzlich `@(Import-Csv (Join-Path $Run 'printdrivers.csv')).Count | Should -Be 2`.

- [ ] **Step 3: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/WindowsSource.Tests.ps1 -Output Minimal"`
Expected: FAIL, keine Absturzereignisse und leere Treiberliste

- [ ] **Step 4: Windows-Quelle umstellen** mit den Signaturen der Interfaces; die feste Ereignistabelle und `ConvertTo-WorkerPerfEventKind` entfallen.

- [ ] **Step 5: Tests ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`
Expected: `Failed: 0`

- [ ] **Step 6: README nachziehen** – Tabelle „Datenquellen" um Ereignisprotokolle, Treiberliste und Warteschlangen mit dem Stand „nach Prüfergebnis, auf einem echten Server noch nicht gelaufen".

- [ ] **Step 7: Commit**

```bash
git add src/WorkerPerf.Sources.Windows.ps1 src/WorkerPerf.Sources.Simulation.ps1 src/Start-WorkerPerfCapture.ps1 src/events.json tests/WindowsStandIns.ps1 tests/WindowsSource.Tests.ps1 README.md
git commit -m "Read events, printer drivers and print queues on Windows from the event catalogue"
```

---

## Nach dem Plan

Beim Auftraggeber, auf dem Zielserver: eine Kurzmessung mit Rückblick; geprüft wird, dass keine Warnung zu einem Protokoll kommt, das laut Prüfskript vorhanden ist, und wie groß `events_before.csv` und `events.csv` werden (Abschnitt 10 der Spezifikation). Ob 30 Minuten und die Abstände der Muster passen, zeigt die erste reale Auswertung; die Werte stehen in `thresholds.json`.

## Self-Review

- **Spec coverage:** Abschnitt 3 → Tasks 1, 2, 10; 4.1 → Tasks 2, 3, 10; 4.2 → Tasks 3, 7, 10; 4.3 → Tasks 3, 7, 10; 4.4 → Tasks 3, 10; 5.1/5.2 → Task 5; 5.3/5.4 → Tasks 2, 6; 5.5 → Tasks 6, 8 (Belege über die Zeile in `Add-WorkerPerfIncidentDetail`); 5.6 → Task 7; 5.7 → Tasks 7, 8; 6 → Task 4; 7 → Task 9; 8 → Tests der Tasks 2–10; 9 → Reihenfolge der Tasks.
- **Step scan:** Jeder Code-Schritt nennt Datei und Signatur; Funktionskörper stehen nicht im Plan; Texte, die die Spezifikation festlegt, stehen wörtlich in Task 6.
- **Type consistency:** `Read-WorkerPerfEventCsv` (Task 3) liefert die Felder von `ConvertTo-WorkerPerfEventRecord` (Task 2) plus `TimeMs`; `SessionIndex` setzt erst `Set-WorkerPerfEventSessions` (Task 5); `Patterns` ist überall eine Liste von `@{ Id; Detail }`, in den Berichtsdaten `[{id, text, detail}]`; `EventIncidents` (Modell) ↔ `eventIncidents` (Daten).
- **Review Focus:** alle fünf Zeilen haben ihren Test in der genannten Task.
- **Proportion:** Codeblöcke sind Tests und die festgelegten Texte; die Spezifikation hat 176 Zeilen, der Plan bleibt bei den Entscheidungen.
