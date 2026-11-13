# Geführter Bericht und Expertenansicht – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Der Bericht öffnet in einer hellen, geführten Ansicht (Lagebild, Vorfallskarten, Vorfallsansicht mit Prüfschritten und Kopiertext) und bietet eine dunkle, dichte Expertenansicht mit einem gemeinsamen Zeitraum für Diagramme, Kacheln und Tabellen; Erklärungen und Anleitungen kommen aus einem prüfbaren Katalog.

**Architecture:** `src/guidance.de.json` enthält alle Erklärungen und Handlungsanleitungen. Eine neue Datei `src/WorkerPerf.Guidance.ps1` lädt und prüft den Katalog, bestimmt je Vorfall Situation, Bedingungen und Platzhalterwerte, stellt die Anleitung zusammen, ordnet die Vorfälle, bildet Lagebild und Kopiertexte. Sie arbeitet auf den fertigen Vorfallseinträgen der Berichtsdaten (dem Format, das `New-WorkerPerfReport.ps1` heute schreibt, plus den Feldern aus den beiden Vorplänen) und legt ihre Ergebnisse als neue Felder daneben. Die Seite liest nur die Berichtsdaten und rendert; sie wird in Schritten umgebaut, die jeweils eine funktionierende Seite hinterlassen, und die bestehenden Browserprüfungen werden Aussage für Aussage auf den neuen Aufbau umgestellt.

**Tech Stack:** Windows PowerShell 5.1 (Laufzeit), HTML/CSS/JavaScript ohne Bibliotheken, Systemschrift. Tests: PowerShell 7 mit Pester 5, Node.js mit Playwright.

**Spec:** `docs/superpowers/specs/2026-11-11-gefuehrter-bericht-design.md`. Setzt voraus: `docs/superpowers/plans/2026-11-11-ereignisse-abstuerze-drucken.md` (Ereignisvorfälle mit `event.patterns[].detail`, `before`, `print`) und `docs/superpowers/plans/2026-11-11-maskierung.md` (`New-WorkerPerfMask`, `Hide-WorkerPerfReportText`, `meta.mask`).

## Global Constraints

- **Windows PowerShell 5.1:** jede `src/*.ps1` beginnt mit `#Requires -Version 5.1`, ist reines ASCII (Umlaute nur in JSON-Textdateien und `src/report-template.html`), ohne PowerShell-7-Syntax und ohne API, die es nur unter .NET Core gibt; eingebettetes C# auf Stand C# 5. `tests/Compat.Tests.ps1` erzwingt einen Teil davon.
- **Tests unter Linux:** PowerShell 7, Pester 5, Node/Playwright; Windows-Aufrufe dünn und über `tests/WindowsStandIns.ps1` getestet. Alle Tests: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`. Browserprüfungen: `pwsh -NoProfile -File tests/New-TestReports.ps1 -OutDir /tmp/wp-reports && node tests/report-browser.js /tmp/wp-reports`, Erfolg: `browser checks passed: <n>`, Rückgabewert 0.
- **Listen:** Funktionen, die Listen liefern, geben schlichte Pipeline-Ausgabe; Aufrufer schreiben `@(...)`.
- **Bericht:** eine einzelne HTML-Datei, keine nachgeladenen Inhalte, keine eingebundenen Bibliotheken oder Schriften, Systemschrift, nutzbar offline und von einer Freigabe (`file://`). Status immer als Symbol und Wort (`◆ kritisch`, `▲ auffällig`, `● normal`, `○ nicht gemessen`), nie nur als Farbe. Deutsche Texte aus JSON-Dateien (`guidance.de.json`, `texts.de.json`), nicht aus dem PowerShell-Code; die Seite enthält nur Beschriftungen ihrer Bedienelemente.
- **Seite rendert nur:** Auswahl der Anleitung, Rangfolge, Lagebild und Kopiertexte entstehen im Auswertungsskript.
- **Collector liest nur;** dieser Plan ändert weder Collector, Datenformat, Datenquellen noch die Erkennung von Befunden, Vorfällen und Verursachern, Schwellen oder Rollen. Ein Aufruf der Quelle, der scheitert, wird wie bisher übersprungen, einmal gewarnt und in `meta.json` vermerkt.
- **Öffentliches Repository:** keine Daten eines echten Servers; Tests mit erfundenen Namen; Aufzeichnungen, Berichte, Prüfergebnisse werden nicht eingecheckt. Der Katalog nennt keine Systeme des Auftraggebers mit Namen („die Fachanwendung", „die Schutzsoftware").
- **Bestand:** die acht Leistungsvorfälle der simulierten Stunde und alle bestehenden Tests bleiben grün; Browserprüfungen werden umgestellt, nicht gestrichen – jede Task nennt, welche Aussage wohin wandert.
- **TDD:** jede Task schreibt zuerst den fehlschlagenden Test.
- **Commits:** englisch, im Imperativ, ein Commit je Task; keine Modellnamen in Code, Kommentaren oder Dokumenten.
- **Werte der Spezifikation:** zehn Vorfallskarten, danach kompakte Liste; Kopiertext reiner Text mit höchstens 78 Zeichen je Zeile; Bewegungen unter 250 ms und keine bei „Bewegung reduzieren"; Hinweis auf die Zahl der Schnappschüsse unter drei; Zielgerät PC, bei schmaler Breite eine Spalte ohne seitliches Scrollen der Seite.

## Review Focus

Jede Zeile ist durch einen Test in der genannten Task abgesichert (`# Review Focus n` bzw. `// Review Focus n`).

1. **Ein Platzhalterwert enthält geschweifte Klammern oder HTML** (Anwendung `{x}.exe`, Benutzer `<b>`). Erwartet: der Wert steht wörtlich da, wird nicht erneut ersetzt und auf der Seite nicht als HTML gedeutet. → Tasks 3, 9
2. **Ein Lesezeichen verweist auf einen Vorfall oder Zeitraum, den es nicht gibt** (Bericht mit anderen Schwellen neu erzeugt, Adresse von Hand gekürzt). Erwartet: die Seite öffnet das Lagebild bzw. die ganze Messung, ohne Skriptfehler. → Task 11
3. **Der Browser verweigert den Speicher** (`localStorage` wirft, etwa bei gesperrten Website-Daten). Erwartet: die Seite öffnet in der geführten Ansicht und funktioniert. → Task 11
4. **Sehr lange Namen im Kopiertext** (Pfad oder Freigabe mit 120 Zeichen ohne Leerzeichen). Erwartet: keine Zeile über 78 Zeichen, nichts geht verloren. → Task 5
5. **Ein Ereignisvorfall ohne Dauer am Rand der Messung** (ein Absturz im letzten Takt). Erwartet: „In der Expertenansicht zeigen" setzt einen gültigen Zeitraum mit Vor- und Nachlauf; die Minuten im Lagebild zählen ihn mit 0. → Tasks 4, 10

## File Structure

| Datei | Verantwortung |
|---|---|
| `src/guidance.de.json` (neu) | Situationen, Begriffe, Hersteller, Texte für Lagebild, Benutzersicht, Hinweise und Kopiertext |
| `src/WorkerPerf.Guidance.ps1` (neu) | Katalog laden und prüfen; Situation, Bedingungen, Platzhalter; Anleitung; Rangfolge, Gruppen, Lagebild; Kopiertexte |
| `docs/guidance/quellen.md` (neu) | Nachweis der Recherche der Druckempfehlungen: übernommen und weggelassen |
| `src/New-WorkerPerfReport.ps1` | `-GuidanceFile`, neue Felder der Berichtsdaten |
| `src/texts.de.json` | Fachbezeichnungen der Vorfallstypen und -arten |
| `src/report-template.html` | zwei Ansichten, Vorfallsansicht, gemeinsamer Zeitraum, Adresse |
| `tests/Guidance.Tests.ps1` (neu), `tests/Report.Tests.ps1`, `tests/report-browser.js`, `tests/TestHelpers.ps1` | Tests |
| `README.md`, `pages/index.html` | Beschreibung und Demo |

---

## Ergänzungen aus dem Plan Messkategorien (gelten für die genannten Tasks)

Der Plan `docs/superpowers/plans/2026-11-12-messkategorien.md` ist nach diesem Plan geschrieben und vor ihm umgesetzt worden. Die Berichtsdaten tragen seitdem, was bei der Messung weggelassen wurde (`-Skip`). Dieser Abschnitt ergänzt die Tasks; wo er einer Task widerspricht, gilt er. Grundregel aus `docs/superpowers/specs/2026-11-12-messkategorien-design.md`, Abschnitt 5: Nichts aus einer weggelassenen Kategorie zählt als unauffällig, als null oder als „keine"; Texte und Kopiertexte sagen „nicht gemessen" mit dem Grund, bei Mustern „nicht geprüft".

**Neue Berichtsdaten (Stand nach dem Plan Messkategorien):**

- `skipped[] { id, label, text, places[] }`: die weggelassenen Kategorien mit Grund und abhängigen Stellen; leer ohne `-Skip`. Die Namen der Kategorien stehen in `$script:WorkerPerfCategories` (`src/WorkerPerf.Common.ps1`).
- `incidents[].cause.kind = "notmeasured"`: kein Verursacher ermittelt, weil `Prozesse` weggelassen ist.
- `incidents[].unverified` (nur bei `ohne-engpass`, boolesch): wahr, wenn `Laufwerke` weggelassen ist. Der Vorfall heißt dann „ohne erkannten Engpass", nie „ohne Engpass".
- `incidents[].event.unchecked[] { id, category, text }`: Muster, die nicht geprüft werden konnten. Drei Kennungen (`printdriver`, `users`, `overlap`); `overlap` kann mehrfach vorkommen, je Kategorie einmal.
- `Get-WorkerPerfUncheckedStatements` (`src/WorkerPerf.Events.ps1`) liefert die Aussagen zu `event.unchecked` in ihrer Reihenfolge; zwei oder mehr `overlap`-Einträge ergeben eine gemeinsame Aussage („Zusammentreffen mit Vorfällen der Kategorien Laufwerke, Citrix (nicht gemessen)").
- `mainApp` ist `null`, wenn `Prozesse` weggelassen ist: derselbe Wert wie ohne konfigurierte Hauptanwendung.
- `before.status = "off"` steht auch für `-Skip Rueckblick`; `quality.eventReads` und `before.readCounts` sind für eine weggelassene Kategorie leer und sagen nichts über Vollständigkeit.
- Zahlen, die nur deshalb 0 sind, weil die Kategorie fehlt: `meta.processRows`, `meta.processCount`, `meta.totalCpuSec`, `sessions[].cpuSec`, `.cpuShare`, `.ioMB`, `.procsAvg`, `incidents[].security.totalPct`; `cause.scan` ist ohne `Ereignisse` `false`; der Text der Ursache sagt dann „Ob im Fenster ein Virenscan lief, ist nicht erfasst" (`largest.scan.notmeasured`). Jeder Satz aus diesen Feldern prüft zuerst `skipped`.
- Der Lader liest die Dateien einer Kategorie nicht, die `Skip` in `meta.json` nennt, auch wenn sie im Ordner liegen. `meta.json` trägt mit `-Skip Prozesse` `IncludeCommandLine: false`.
- Sätze der heutigen Seite, die der geführte Bericht im Wortlaut übernimmt: die Kopfzeile ohne `Ereignisse` („… Vorfälle aus Ereignissen wurden nicht erfasst (-Skip Ereignisse).", mit und ohne Vorfälle), die Liste „Nicht gemessen (n)" im Zustand ohne Befund (erst die Kategorien aus `skipped`, dann die Signale), der Zusatz zum gemeldeten Benutzer („Abstürze und Hänger sind dabei nicht gezählt: …", mit nur `Prozesse` weggelassen und gemeldeter Zeit „beim Benutzer nicht gezählt"), die Treiberspalte („nein (vor der Messung)", wenn nur der Rückblick gelesen wurde; „–", wenn keine Quelle gelesen wurde) und die „Grenzen der Aussage" (Zeilen zu Laufwerken und kurzlebigen Prozessen nur, wenn die Kategorie gemessen ist).

**Task 1 (Katalog laden und prüfen):** Zu den bekannten Bedingungen und ihrem Test kommen `cause.notmeasured`, `skipped.<Kategorie>` (Name aus `$script:WorkerPerfCategories`), `pattern.unchecked` und `incident.unverified`. Die Liste `hints` kennt den Hinweis `skipped` neben `unmeasured`.

**Task 2 (Situation, Bedingungen, Platzhalterwerte):** Verbraucht zusätzlich `Data.skipped`. Abgeleitet werden `cause.notmeasured` aus `cause.kind`, `incident.unverified` aus `unverified`, `pattern.unchecked` aus nicht leerem `event.unchecked`, `skipped.<id>` je Eintrag. `pattern.none` gilt nur, wenn `event.patterns` und `event.unchecked` beide leer sind. Mit `users` in `event.unchecked` gelten `event.sessionUnknown` und `event.noUserSession` nicht, obwohl beide Felder in den Daten wahr bleiben. Die Bedingung `scan` ist ohne `Ereignisse` unbekannt, nicht falsch. `role.<R>` lässt sich ohne `Prozesse` nicht ableiten. `New-Inc` und `New-Ctx` der Tests erhalten `event.unchecked = @()`, `unverified = $false`, `skipped = @()`.

**Task 4 (Rangfolge, Gruppen, Lagebild):** Das Lagebild erhält den Hinweis `skipped` mit den `label` aus `skipped`. `unmeasured` und `skipped` nennen für Laufwerke, Citrix und Gegenstellen dieselben Signale; `skipped` hat Vorrang, `unmeasured` nennt dann nur, was aus anderem Grund fehlt. Der grüne Zustand und sein Satz sagen ohne `Ereignisse` nicht „keine Vorfälle" ohne den Vorbehalt, dass Vorfälle aus Ereignissen nicht erfasst wurden. Die Kennzahl der Verzögerungen nennt Vorfälle mit `unverified` „ohne erkannten Engpass". Rangfolge: Ein Ereignisvorfall mit `users` in `event.unchecked` oder mit unbekannter Sitzung steht unter den Leistungsvorfällen derselben Stufe.

**Task 5 (Kopiertexte):** Bei `cause.kind = notmeasured` steht im Teil zur Ursache der Satz der Kategorie. Bei Ereignisvorfällen stehen die Texte aus `event.unchecked` als „nicht geprüft", gebildet mit `Get-WorkerPerfUncheckedStatements` (keine eigene Regel „eine Zeile je Kennung": mehrere `overlap`-Einträge ergeben eine gemeinsame Aussage, die alle Kategorien nennt). Titel und Text eines Vorfalls mit `unverified` sagen „ohne erkannten Engpass". Der Satz zum gemeldeten Benutzer nennt, dass Abstürze und Hänger nicht gezählt sind, wenn `Ereignisse` oder `Prozesse` fehlt.

**Task 6 (Inhalt des Katalogs):** Varianten für `cause.notmeasured`, `skipped.*`, `pattern.unchecked` und `incident.unverified` mit den Formulierungen „nicht gemessen" und „nicht geprüft". Empfehlungen, die eine Messung voraussetzen (Virenscan im Fenster, Rollen der Prozesse, beteiligte Druckertreiber), haben eine Variante für den Fall, dass die Messung fehlt.

**Task 7 (Berichtsdaten):** Bevor der geführte Bericht sagt, es sei keine Hauptanwendung konfiguriert, prüft er `skipped[].places` auf `apps`. Die Regel der Treiberspalte „An einem Vorfall beteiligt" liegt heute nur in der Seite; die Berichtsdaten erhalten dafür `print.involvedFrom` mit einem der Werte `capture`, `lookback`, `both`, `none` (Schlüsselwort; in `tests/MaskCensus.json` und der Liste der Schlüsselwortfelder eintragen), damit Ansicht, Kopiertext und Katalogbedingungen dieselbe Regel verwenden: „nein" nur, wenn beide Quellen gelesen wurden.

**Gestaltung und Tasks 8–11 (Seite):** `#skipInfo` steht in der Kopfleiste neben `#maskInfo`. `details#measured` nennt die weggelassenen Kategorien mit ihrem `text`. Vorfallsansicht und Expertenansicht zeigen je Stelle aus `skipped[].places` den Hinweis „○ nicht gemessen" nach der Tabelle in Task 5 des Plans Messkategorien; die Hilfsfunktion der heutigen Seite, die zu einer Stelle den Hinweis liefert, wird übernommen. Die Gruppen „ohne erkannten Engpass" bleiben von „ohne Engpass" getrennt.

**Browserprüfungen (Task 8 und folgende):** `checkSkip` ruft `showExpert` wie die übrigen Prüfungen. Die Tabelle `SKIP_LOCATIONS` in `tests/report-browser.js` enthält die Selektoren der heutigen Seite und wird für die Expertenansicht neu geschrieben. `tests/New-TestReports.ps1` schreibt die Berichte mit weggelassenen Kategorien (`report-skip-*.html`, darunter die ohne Befund, die mit gemeldetem Benutzer und der einer von Hand geänderten Aufzeichnung), die auch die Prüfungen des geführten Berichts öffnen: keiner zeigt einen Skriptfehler.

**Task 12 (README und Demo-Seite):** Der Abschnitt zum geführten Bericht beschreibt, wie er „nicht gemessen" und „nicht geprüft" zeigt.

---

### Task 1: Katalog laden und prüfen

**Files:**
- Create: `src/WorkerPerf.Guidance.ps1`, `tests/Guidance.Tests.ps1`

**Interfaces:**
- Produces:
  - Aufbau des Katalogs (JSON):

```json
{
  "version": "2026-11-11",
  "terms": { "Working Set": "Arbeitsspeicher, den ein Programm gerade belegt …" },
  "vendors": [ { "key": "HP", "match": ["HP*", "Hewlett*"] }, { "key": "Kyocera", "match": ["Kyocera*"] }, { "key": "Brother", "match": ["Brother*"] },
               { "key": "Microsoft", "match": ["Microsoft*"] }, { "key": "Citrix", "match": ["Citrix*"] } ],
  "userView": { "many": "…", "one": "…", "none": "…", "unknown": "…", "chronic": "…", "eventMany": "…", "eventOne": "…", "eventNone": "…", "before": "…" },
  "lagebild": { "red": "…", "yellow": "…", "green": "Keine Störung erkannt." },
  "hints": { "unmeasured": "…", "notFinished": "…", "error": "…", "stopped": "…" },
  "copy": { "head": "WorkerPerf {server}, {date}", "summaryHead": "…", "measure": "…", "cause": "…", "affected": "…", "checks": "Empfohlene Prüfschritte:", "remedies": "Mögliche Abhilfe (Vorschlag):", "contact": "…" },
  "fallbackNote": "…",
  "situations": { "cpu": { "title": "…", "meaning": "…", "impact": "…", "short": "CPU",
      "checks":   [ { "text": "…", "where": "…", "sign": "…", "when": ["cause.app"], "source": "…" } ],
      "remedies": [ { "text": "…", "precondition": "…", "when": [], "source": "…" } ],
      "contacts": [ { "text": "…", "when": [] } ] } }
}
```

  - `$script:WorkerPerfSituations = @('cpu', 'memory', 'disk', 'share', 'profile', 'delay.many', 'delay.single', 'chronic.network', 'chronic.resource', 'crash', 'hang', 'service', 'print', 'profileerror', 'system', 'fallback')`.
  - `$script:WorkerPerfGuidancePlaceholders = @('user', 'app', 'share', 'baseline', 'value', 'target', 'from', 'to', 'duration', 'affected', 'resource', 'endpoint', 'endpointValue', 'security', 'module', 'driver', 'count', 'server', 'date', 'signals', 'message', 'bottlenecks', 'delays', 'events', 'chronic', 'minutes', 'incidents')` – die ersten 14 nennt Abschnitt 5.5 der Spezifikation, `module`, `driver`, `count` brauchen die Ereignissituationen, die übrigen Lagebild, Hinweise und Kopf des Kopiertexts.
  - `Test-WorkerPerfGuidanceCondition([string]$Name, $Catalogue) -> bool`: bekannt sind die Namen aus Abschnitt 5.4 der Spezifikation; `role.<Rolle>` mit einer Rolle aus `$script:WorkerPerfRoleNames`; `unmeasured.<Signal>` mit einer `id` aus `src/thresholds.json` oder `input.session`; `pattern.<id>` mit den neun Mustern und `pattern.none`; `driver.vendor.<key>` mit einem `key` aus `vendors`.
  - `Read-WorkerPerfGuidance([string]$Path) -> pscustomobject` (der Katalog wie gelesen). Prüft: Pflichtteile `version`, `terms`, `vendors`, `userView`, `lagebild`, `hints`, `copy`, `fallbackNote`, `situations`; je Situation `title`, `meaning`, `impact`, `short`, `checks` (mindestens einer ohne `when`), `remedies`, `contacts`; je Prüfschritt `text`, `where`, `sign`; je Abhilfe `text`, `precondition`; je Kontakt `text`; jede Bedingung bekannt; jeder Platzhalter `{name}` bekannt; `source` Pflicht für jedes Element der Situation `print` und jedes Element mit einer Bedingung `pattern.printdriver` oder `driver.*`; unbekannte Situationsnamen sind ein Fehler. Meldung: `throw "Katalog '<Pfad>': Eintrag '<Situation>', <checks[2]>: Feld '<feld>' <Grund>."` (Teil `<checks[2]>` entfällt bei Feldern der Situation selbst).

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/Guidance.Tests.ps1`; ein vollständiger kleiner Katalog als Hashtable im Test, `New-Catalogue`, der für jede Situation einen Eintrag mit je einem Prüfschritt, einer Abhilfe und einem Kontakt ohne Bedingung erzeugt und als Datei schreibt)

```powershell
BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Guidance.ps1')
    function New-Catalogue([scriptblock]$Change = {}) { <# legt den Katalog als Hashtable in $c an, ruft . $Change, schreibt ihn nach $TestDrive und liefert den Pfad #> }
    $script:Cat = Read-WorkerPerfGuidance (New-Catalogue); $script:Texts = Read-WorkerPerfTexts (Join-Path $PSScriptRoot '../src/texts.de.json')
}
Describe 'Katalog laden und pruefen' {
    It 'liest einen vollstaendigen Katalog' { (Read-WorkerPerfGuidance (New-Catalogue)).situations.cpu.short | Should -Be 'CPU' }
    It 'nennt Eintrag und Feld eines Fehlers' -TestCases @(
        @{ Change = { $c.situations.cpu.Remove('impact') }; Msg = "*Eintrag 'cpu'*Feld 'impact'*" }
        @{ Change = { $c.situations.cpu.checks[0].when = @('cause.irgendwas') }; Msg = "*Eintrag 'cpu', checks[0]*Feld 'when'*cause.irgendwas*" }
        @{ Change = { $c.situations.disk.remedies[0].text = 'Laufwerk {laufwerk} pruefen' }; Msg = "*Eintrag 'disk', remedies[0]*Feld 'text'*{laufwerk}*" }
        @{ Change = { $c.situations.print.remedies[0].Remove('source') }; Msg = "*Eintrag 'print', remedies[0]*Feld 'source'*" }
        @{ Change = { $c.situations.crash.checks += @{ text = 't'; where = 'w'; sign = 's'; when = @('pattern.printdriver') } }; Msg = "*Eintrag 'crash', checks[1]*Feld 'source'*" }
        @{ Change = { $c.situations.Remove('hang') }; Msg = "*Eintrag 'hang'*fehlt*" }
        @{ Change = { $c.situations['cpu.neu'] = $c.situations.cpu }; Msg = "*Eintrag 'cpu.neu'*unbekannt*" }
    ) { { Read-WorkerPerfGuidance (New-Catalogue $Change) } | Should -Throw $Msg }
    It 'kennt die Bedingungen der Spezifikation' {
        foreach ($n in 'cause.app', 'cause.security', 'cause.none', 'cause.nodata', 'scan', 'companion.security', 'role.Sicherheit', 'role.Drucken', 'endpoint.slow', 'event.applocker',
            'event.defender', 'unmeasured.disk.latency', 'unmeasured.input.session', 'affected.many', 'affected.one', 'affected.unknown', 'chronic', 'pattern.resource', 'pattern.overlap',
            'pattern.none', 'driver.v3', 'driver.v4', 'driver.shared', 'driver.isolated', 'driver.vendor.HP', 'spooler.crash', 'queue.stuck', 'before') {
            Test-WorkerPerfGuidanceCondition $n (Read-WorkerPerfGuidance (New-Catalogue)) | Should -BeTrue -Because $n
        }
        Test-WorkerPerfGuidanceCondition 'driver.vendor.Acme' (Read-WorkerPerfGuidance (New-Catalogue)) | Should -BeFalse
        Test-WorkerPerfGuidanceCondition 'role.Chef' (Read-WorkerPerfGuidance (New-Catalogue)) | Should -BeFalse
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Guidance.Tests.ps1 -Output Minimal"`
Expected: FAIL, Datei `WorkerPerf.Guidance.ps1` fehlt

- [ ] **Step 3: `Read-WorkerPerfGuidance` und `Test-WorkerPerfGuidanceCondition` mit den Signaturen der Interfaces umsetzen** (Lesen über `ConvertFrom-WorkerPerfJsonFile`; die Liste der Signal-Ids über `Read-WorkerPerfThresholds (Join-Path $PSScriptRoot 'thresholds.json')` einmal je Aufruf)

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Guidance.ps1 tests/Guidance.Tests.ps1
git commit -m "Load and validate the guidance catalogue"
```

---

### Task 2: Situation, Bedingungen und Platzhalterwerte

**Files:**
- Modify: `src/WorkerPerf.Guidance.ps1`
- Test: `tests/Guidance.Tests.ps1`

**Interfaces:**
- Consumes: Vorfallseinträge der Berichtsdaten (`type`, `chronic`, `severity`, `lead`, `start`, `end`, `signals[]`, `affected[]`, `main`, `cause`, `companion`, `scanActive`, `endpoints[]`, `events[]`, `event`), den Kontext `@{ Data; Thresholds; OffsetMinutes }` mit `Data.apps`, `Data.sessions`, `Data.sollIst`, `Data.unmeasured`, `Data.print`, `Data.meta`.
- Produces:
  - `Get-WorkerPerfSituation($Incident) -> string`: `ereignis` → `event.kind`; Dauerzustand vom Typ `umfeld` mit Netzbefund → `chronic.network`, Dauerzustand vom Typ `engpass` → `chronic.resource`; `engpass` → `lead` (`cpu`, `memory`, `disk`, `share`, `profile`); `ohne-engpass` → `delay.many` bei mindestens zwei betroffenen Sitzungen, sonst `delay.single`; alles andere (auch `umfeld` ohne Dauer, Dauerzustand ohne Engpass) → `fallback`.
  - `Get-WorkerPerfGuidanceFacts -Incident -Context -Catalogue -> @{ Situation; Conditions = string[]; Values = hashtable }`. Bedingungen wie Abschnitt 5.4 der Spezifikation, abgeleitet so: `cause.app`/`.security`/`.none`/`.nodata` aus `cause.kind` (`main`, `security`, `none`, `nodata`); `scan` = `scanActive`; `companion.security` = `companion` gesetzt; `role.<R>` = `apps[main.a].role` (bei Ereignisvorfällen die Rolle der Anwendung `event.app` aus `apps`); `endpoint.slow` = ein Eintrag in `endpoints` mit `failed` oder `maxMs` ≥ `warn` von `probe.connect`; `event.applocker` = ein Ereignis des Vorfalls mit Art `applocker-block`, `event.defender` = eines mit Protokoll `defender`; `unmeasured.<id>` = Zeilen von `sollIst` mit `measured = $false`; `affected.many` (≥ 2), `affected.one` (1), `affected.unknown` (keine und `unmeasured.input`), bei Ereignisvorfällen aus `event.sessions`; `chronic`; `pattern.<id>` und `pattern.none` aus `event.patterns`; beteiligter Treiber = `detail.driver` eines Musters `printdriver`, sonst der Eintrag von `print.drivers` mit `name` = `event.driver` oder `event.key`; davon `driver.v3`/`driver.v4` (`type`), `driver.isolated` (`isolation` = `isolated`), `driver.shared` (`isolation` = `shared` oder `none`), `driver.vendor.<key>` (`manufacturer` passt zu `vendors[].match`); `spooler.crash` = Situation `print` und ein Ereignis mit `app` `spoolsv.exe`/`PrintIsolationHost.exe` oder `service` `Spooler`; `queue.stuck` = eine Warteschlange mit `jobErrors` oder `notReadyErrors` > 0; `before` = `event.before`.
  - Werte (deutsche Zahlen mit Komma wie `Format-WorkerPerfTextNumber`): `user`, `app`, `share` (`62 %`), `baseline` (`4 %`) aus `main` bzw. `cause.other`; `value` (Spitze des führenden Signals mit Einheit) und `target` (`ideal`); `from`, `to` (`HH:mm`, Ortszeit des Servers); `duration` (`2 Minuten`, `3,8 Minuten`, `45 Sekunden`, `1,5 Stunden`); `affected` (Zahl); `resource` (`label` des führenden Signals bei `disk`, `share`, `profile`); `endpoint`, `endpointValue` (langsamste Gegenstelle); `security` (`cause.security.label`, sonst `companion.label`); `module` (häufigstes Modul), `driver` (beteiligter Treiber), `count` (`event.count`); `server` (`meta.computer`), `date`. Ein Wert, den der Vorfall nicht hat, fehlt in `Values`.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (Vorfälle als kleine Hashtables; im `BeforeAll` am Dateianfang die Helfer `New-Inc` – alle Schlüssel eines Vorfallseintrags mit neutralen Werten, überschrieben durch die übergebenen – und `New-Ctx` – `@{ Data = @{ apps = @(@{ i = 0; name = 'EXCEL.EXE'; role = '' }, @{ i = 1; name = 'MsMpEng.exe'; role = 'Sicherheit' }); sessions = @(); sollIst = @(); unmeasured = @{ input = $false; worker = @() }; print = @{ drivers = @(@{ name = 'Sim PCL 6'; manufacturer = 'HP'; type = 3; isolation = 'none' }); queues = @(@{ name = 'Q1'; maxJobs = 3; jobErrors = 1; notReadyErrors = 0 }) }; meta = @{ computer = 'SIM-VDA01'; offsetMin = 60; endReason = 'duration'; start = 1e12; end = 1e12 + 3600000 } }; Thresholds = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json'); OffsetMinutes = 60 }`)

```powershell
Describe 'Situation und Bedingungen' {
    It 'ordnet jede erzeugbare Situation genau einer Kennung zu' -TestCases @(
        @{ I = @{ type = 'engpass'; lead = 'cpu' }; S = 'cpu' }; @{ I = @{ type = 'engpass'; lead = 'profile' }; S = 'profile' }
        @{ I = @{ type = 'ohne-engpass'; affected = @(@{ s = 1 }, @{ s = 2 }) }; S = 'delay.many' }; @{ I = @{ type = 'ohne-engpass'; affected = @(@{ s = 1 }) }; S = 'delay.single' }
        @{ I = @{ type = 'umfeld'; chronic = $true; signals = @(@{ resource = 'network' }) }; S = 'chronic.network' }; @{ I = @{ type = 'engpass'; chronic = $true; lead = 'memory' }; S = 'chronic.resource' }
        @{ I = @{ type = 'ereignis'; event = @{ kind = 'print' } }; S = 'print' }; @{ I = @{ type = 'umfeld'; signals = @(@{ resource = 'endpoint' }) }; S = 'fallback' }
    ) { Get-WorkerPerfSituation (New-Inc $I) | Should -Be $S }
    It 'leitet die Bedingungen eines Engpasses ab' {
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu'; cause = @{ kind = 'main' }; main = @{ app = 'EXCEL.EXE'; a = 0; user = 'user003'; sharePct = 62; baselinePct = 4 }
            affected = @(@{ s = 1 }, @{ s = 2 }); scanActive = $true; companion = @{ label = 'Microsoft Defender' }; endpoints = @(@{ name = 'DB'; maxMs = 340; failed = $false }) }) -Context (New-Ctx) -Catalogue $Cat
        $f.Conditions | Should -Be @('cause.app', 'scan', 'companion.security', 'endpoint.slow', 'affected.many')
        $f.Values.app | Should -Be 'EXCEL.EXE'; $f.Values.share | Should -Be '62 %'; $f.Values.baseline | Should -Be '4 %'; $f.Values.security | Should -Be 'Microsoft Defender'
        $f.Values.ContainsKey('module') | Should -BeFalse
    }
    It 'leitet Treiber, Hersteller und Druckwarteschlange eines Druckproblems ab' {
        $i = New-Inc @{ type = 'ereignis'; event = @{ kind = 'print'; key = 'Sim PCL 6'; app = 'spoolsv.exe'; sessions = @(); before = $false; count = 1
            patterns = @(@{ id = 'printdriver'; detail = @{ module = 'hpsimgr.dll'; driver = 'Sim PCL 6' } }); modules = @(@{ name = 'hpsimgr.dll'; count = 1 }) }
            events = @(@{ app = 'spoolsv.exe'; service = ''; kind = 'crash'; log = 'application' }) }
        $f = Get-WorkerPerfGuidanceFacts -Incident $i -Context (New-Ctx) -Catalogue $Cat
        $f.Conditions | Should -Be @('pattern.printdriver', 'driver.v3', 'driver.shared', 'driver.vendor.HP', 'spooler.crash', 'queue.stuck')
        $f.Values.driver | Should -Be 'Sim PCL 6'; $f.Values.module | Should -Be 'hpsimgr.dll'
    }
    It 'sagt kein Muster und unbekannte Betroffene' {
        (Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'profileerror'; patterns = @(); sessions = @(1); before = $true } }) -Context (New-Ctx) -Catalogue $Cat).Conditions |
            Should -Be @('affected.one', 'pattern.none', 'before')
        $ctx = New-Ctx; $ctx.Data.unmeasured.input = $true; $ctx.Data.sollIst = @(@{ id = 'input.session'; measured = $false })
        (Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu'; cause = @{ kind = 'nodata' } }) -Context $ctx -Catalogue $Cat).Conditions |
            Should -Be @('cause.nodata', 'unmeasured.input.session', 'affected.unknown')
    }
}
```

Die Reihenfolge der Bedingungen in `Conditions` ist die Reihenfolge der Tabelle in Abschnitt 5.4 der Spezifikation.

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Guidance.Tests.ps1 -Output Minimal"`
Expected: FAIL, `Get-WorkerPerfSituation` nicht definiert

- [ ] **Step 3: `Get-WorkerPerfSituation` und `Get-WorkerPerfGuidanceFacts` mit den Signaturen der Interfaces umsetzen**

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Guidance.ps1 tests/Guidance.Tests.ps1
git commit -m "Derive situation, conditions and placeholder values of an incident"
```

---

### Task 3: Anleitung zusammenstellen

**Files:**
- Modify: `src/WorkerPerf.Guidance.ps1`, `src/texts.de.json`
- Test: `tests/Guidance.Tests.ps1`

**Interfaces:**
- Consumes: Tasks 1 und 2.
- Produces:
  - `Format-WorkerPerfGuidanceText([string]$Template, [hashtable]$Values) -> string | $null`: ersetzt jedes `{name}` in einem Durchgang (eingesetzte Werte werden nicht erneut gelesen); fehlt ein Wert, `$null`.
  - `New-WorkerPerfGuidance -Catalogue -Facts -Incident -Texts -> ordered` `{ situation, fallback, title, tech, meaning, impact, userView, checks [{text, where, sign, source}], remedies [{text, precondition, source}], contacts [{text}], short, terms, conditions }`. Ein Element erscheint, wenn alle Bedingungen in `when` gelten und alle seine Texte vollständig gefüllt werden können; Elemente mit erfüllter Bedingung stehen vor denen ohne, sonst Reihenfolge der Datei. Fehlt die Situation im Katalog: Eintrag `fallback`, `fallback = $true`, `meaning` beginnt mit `fallbackNote`. `tech` = Fachbezeichnung aus `texts.de.json` (`type.<type>` und `resource.<lead>` bzw. `kind.<event.kind>`, verbunden mit „ · "). `userView` aus `userView` des Katalogs (Wahl nach `affected.*`, `chronic`, Ereignisvorfall, `before`). `terms` = die Schlüssel aus `terms`, die in einem Text der Anleitung vorkommen (Groß- und Kleinschreibung egal).
  - `texts.de.json`: `type.engpass` „Engpass", `type.ohne-engpass` „Verzögerung ohne Engpass", `type.umfeld` „Umfeld", `type.ereignis` „Vorfall aus Ereignissen", `kind.crash` „Anwendungsabsturz", `kind.hang` „Anwendungshänger", `kind.service` „Dienstausfall", `kind.print` „Druckproblem", `kind.profileerror` „Profilproblem", `kind.system` „Systemfehler", `type.chronic` „Dauerzustand".

- [ ] **Step 1: Die fehlschlagenden Tests schreiben**

```powershell
Describe 'Anleitung zusammenstellen' {
    BeforeAll {
        $script:Cat2 = Read-WorkerPerfGuidance (New-Catalogue { $c.situations.cpu.checks = @(
            @{ text = 'Allgemein'; where = 'w'; sign = 's' }
            @{ text = '{app} von {user} pruefen'; where = 'Task-Manager'; sign = 'hoher Anteil'; when = @('cause.app') }
            @{ text = 'Scan von {security}'; where = 'w'; sign = 's'; when = @('scan', 'companion.security') }
            @{ text = 'Gegenstelle {endpoint}'; where = 'w'; sign = 's' }) })
    }
    It 'waehlt genau die gestuetzten Elemente, bedingte zuerst' {
        $g = New-WorkerPerfGuidance -Catalogue $Cat2 -Facts @{ Situation = 'cpu'; Conditions = @('cause.app', 'scan'); Values = @{ app = 'EXCEL.EXE'; user = 'user003'; security = 'X' } } -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu' }) -Texts $Texts
        @($g.checks.text) | Should -Be @('EXCEL.EXE von user003 pruefen', 'Allgemein')                  # 'scan' allein reicht nicht; {endpoint} fehlt
        $g.fallback | Should -BeFalse; $g.tech | Should -Be 'Engpass · CPU'
    }
    It 'zeigt ohne zutreffende Bedingung nur die allgemeinen Elemente' {
        @((New-WorkerPerfGuidance -Catalogue $Cat2 -Facts @{ Situation = 'cpu'; Conditions = @(); Values = @{} } -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu' }) -Texts $Texts).checks.text) | Should -Be @('Allgemein')
    }
    It 'nimmt den Auffang-Eintrag mit sichtbarem Hinweis' {
        $g = New-WorkerPerfGuidance -Catalogue $Cat2 -Facts @{ Situation = 'fallback'; Conditions = @(); Values = @{} } -Incident (New-Inc @{ type = 'umfeld' }) -Texts $Texts
        $g.fallback | Should -BeTrue; $g.meaning | Should -BeLike ($Cat2.fallbackNote + '*')
    }
    It 'setzt Werte mit Klammern und HTML woertlich ein' {                                         # Review Focus 1
        Format-WorkerPerfGuidanceText '{app} von {user}' @{ app = '{user}.exe'; user = '<b>x</b>' } | Should -BeExactly '{user}.exe von <b>x</b>'
        Format-WorkerPerfGuidanceText '{app} von {user}' @{ app = 'a' } | Should -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Guidance.Tests.ps1 -Output Minimal"`
Expected: FAIL, `New-WorkerPerfGuidance` nicht definiert

- [ ] **Step 3: `Format-WorkerPerfGuidanceText` und `New-WorkerPerfGuidance` umsetzen** (Ersetzen über `[regex]::Replace` mit `\{(\w+)\}` und einem Auswerter)

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Guidance.ps1 src/texts.de.json tests/Guidance.Tests.ps1
git commit -m "Assemble the guidance of an incident from the catalogue"
```

---

### Task 4: Rangfolge, Gruppen und Lagebild

**Files:**
- Modify: `src/WorkerPerf.Guidance.ps1`
- Test: `tests/Guidance.Tests.ps1`

**Interfaces:**
- Consumes: Vorfallseinträge mit `guide` (Task 3).
- Produces:
  - `Get-WorkerPerfIncidentRanking -Incidents [object[]] -> int[]` (Ids): Klasse 0 = kein Dauerzustand und (`engpass`, `ohne-engpass` mit `severity` 2, `ereignis`); Klasse 1 = übrige ohne Dauer; Klasse 2 = Dauerzustände. Innerhalb: Zahl der betroffenen Sitzungen absteigend (`affected` bzw. `event.sessions`), Dauer absteigend, Beginn aufsteigend, Id aufsteigend.
  - `Get-WorkerPerfIncidentGroups -Incidents [object[]] -Order [int[]] -Cards [int] -> object[]` für die Vorfälle nach den ersten `Cards`: `[ordered]@{ label; situation; ids }`; zusammengefasst werden Vorfälle mit gleicher Situation und gleichem Verursacher (`main.app` und `main.user`, bei Ereignisvorfällen `event.key`); `label` bei mehreren „6-mal CPU-Engpass durch EXCEL.EXE von user003" (aus `guide.title` und den Namen), sonst Titel, Uhrzeit.
  - `Get-WorkerPerfLagebild -Incidents [object[]] -Data -Catalogue -> ordered` `{ state ('red'|'yellow'|'green'), symbol, word, sentence, kpis { bottlenecks, delays, events, chronic, minutes }, hints [string], top (Id | $null) }`. `bottlenecks` = `engpass` ohne Dauer; `delays` = `ohne-engpass` und `umfeld` ohne Dauer; `events` = `ereignis` der Messzeit; `chronic` = Dauerzustände; `minutes` = Länge der Vereinigung der Fenster aller Vorfälle ohne Dauerzustand, auf eine Nachkommastelle. `red` bei einem `engpass` ohne Dauer, einem `ohne-engpass` mit `severity` 2 oder einem `ereignis` mit `event.inSession`; `yellow` bei sonstigen Vorfällen; `green` ohne Vorfall. `symbol`/`word`: `◆`/`kritisch`, `▲`/`auffällig`, `●`/`normal`. `hints`: `unmeasured` mit den Bezeichnungen der nicht gemessenen Signale, `notFinished` ohne `meta.endReason`, `error` bei `error` (mit `meta.endMessage`), `stopped` bei `diskspace` oder `maxsize`. `top` = erste Id der Rangfolge. Vorfälle aus `before` zählen nirgends mit.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben**

```powershell
Describe 'Rangfolge, Gruppen, Lagebild' {
    BeforeAll {
        function New-R([int]$Id, [string]$Type, [int]$Sessions, [double]$DurSec, [double]$StartSec, [int]$Sev = 2, [switch]$Chronic) {
            New-Inc @{ id = $Id; type = $Type; severity = $Sev; chronic = [bool]$Chronic; start = [long](1e12 + $StartSec * 1000); end = [long](1e12 + ($StartSec + $DurSec) * 1000)
                affected = @(1..$Sessions | Where-Object { $Sessions -gt 0 } | ForEach-Object { @{ s = $_ } }); event = @{ sessions = @(); inSession = $false; key = '' } }
        }
    }
    It 'ordnet Engpaesse, kritische Verzoegerungen und Ereignisse vor Dauerzustaenden, dann nach Sitzungen, Dauer, Beginn' {
        $list = @((New-R 1 'umfeld' 9 600 0 -Chronic), (New-R 2 'engpass' 1 60 100), (New-R 3 'ohne-engpass' 8 90 200), (New-R 4 'ohne-engpass' 9 90 50 -Sev 1),
                  (New-R 5 'engpass' 1 90 300), (New-R 6 'engpass' 1 60 50))
        Get-WorkerPerfIncidentRanking -Incidents $list | Should -Be @(3, 5, 6, 2, 4, 1)
    }
    It 'fasst nach den zehn Karten gleiche Situation und gleichen Verursacher zusammen' {
        $list = @(1..14 | ForEach-Object { $i = New-R $_ 'engpass' 1 60 ($_ * 100); $i.main = @{ app = $(if ($_ -le 12) { 'EXCEL.EXE' } else { 'WINWORD.EXE' }); user = 'user003' }; $i.guide = @{ situation = 'cpu'; title = 'CPU ausgelastet' }; $i })
        $g = @(Get-WorkerPerfIncidentGroups -Incidents $list -Order (1..14) -Cards 10)
        $g.Count | Should -Be 2; $g[0].ids | Should -Be @(11, 12); $g[0].label | Should -Be '2-mal CPU ausgelastet durch EXCEL.EXE von user003'
    }
    It 'bildet Zustand und Kennzahlen; ueberlappende Fenster zaehlen einmal, ein Ereignis ohne Dauer mit 0' {   # Review Focus 5
        $e = New-R 7 'ereignis' 0 0 130; $e.event.inSession = $true
        $l = Get-WorkerPerfLagebild -Incidents @((New-R 2 'engpass' 1 120 0), (New-R 3 'ohne-engpass' 2 120 60), $e, (New-R 1 'umfeld' 1 3600 0 -Chronic)) -Data (New-Ctx).Data -Catalogue $Cat
        $l.state | Should -Be 'red'; $l.word | Should -Be 'kritisch'; $l.kpis.bottlenecks | Should -Be 1; $l.kpis.delays | Should -Be 1; $l.kpis.events | Should -Be 1
        $l.kpis.chronic | Should -Be 1; $l.kpis.minutes | Should -Be 3; $l.top | Should -Be 3                     # die kritische Verzoegerung mit zwei Sitzungen steht vorn
        (Get-WorkerPerfLagebild -Incidents @((New-R 1 'umfeld' 1 3600 0 -Chronic)) -Data (New-Ctx).Data -Catalogue $Cat).state | Should -Be 'yellow'
        $g = Get-WorkerPerfLagebild -Incidents @() -Data (New-Ctx).Data -Catalogue $Cat; $g.state | Should -Be 'green'; $g.sentence | Should -Be 'Keine Störung erkannt.'
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Guidance.Tests.ps1 -Output Minimal"`
Expected: FAIL, `Get-WorkerPerfIncidentRanking` nicht definiert

- [ ] **Step 3: Rangfolge, Gruppen und Lagebild mit den Signaturen der Interfaces umsetzen**

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Guidance.ps1 tests/Guidance.Tests.ps1
git commit -m "Rank incidents, group the rest and build the situation summary"
```

---

### Task 5: Kopiertexte

**Files:**
- Modify: `src/WorkerPerf.Guidance.ps1`
- Test: `tests/Guidance.Tests.ps1`

**Interfaces:**
- Consumes: Tasks 3 und 4; aus dem Maskierungsplan `New-WorkerPerfMask -Path -Level Alles -Texts` und `Hide-WorkerPerfReportText`.
- Produces:
  - `Format-WorkerPerfCopyLines([string[]]$Paragraphs, [int]$Width = 78) -> string`: bricht an Leerzeichen um, ein Wort über `Width` wird hart getrennt; Absätze, die mit `1. ` oder `- ` beginnen, rücken Folgezeilen um die Breite dieses Anfangs ein; Zeilenende `` `r`n ``.
  - `New-WorkerPerfCopyText -Incident -Guide -Data -Catalogue -> string`: Kopf (`copy.head`: Server und Datum), Zeit und Dauer mit Titel, Wirkung (`impact`), Messwert mit Soll (`copy.measure`, entfällt ohne Messwert), Verursacher oder Hinweis (`copy.cause`, aus `main`/`cause`/`event.patterns[].text`), Betroffene (`copy.affected`), `copy.checks` mit den nummerierten Prüfschritten (`text – where; erkennbar an sign`), `copy.remedies` mit `- Wenn <precondition>: <text>`, `copy.contact`, wenn vorhanden.
  - `New-WorkerPerfCopySummary -Incidents [object[]] -Order [int[]] -Lagebild -Data -Catalogue -> string`: `copy.summaryHead` (Server, Zeitraum), der Satz des Lagebilds, danach je Vorfall in Rangfolge die Zeile mit Zeit, Dauer, Titel und die Wirkung.
  - `ConvertTo-WorkerPerfAnonymousText([string]$Text, $Mask) -> string` = `Hide-WorkerPerfReportText $Text $Mask` mit der Maske der Stufe `Alles` derselben Aufzeichnung; im maskierten Bericht wird sie nicht gerufen.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben**

```powershell
Describe 'Kopiertexte' {
    It 'haelt 78 Zeichen ein und verliert nichts, auch bei langen Namen' {                         # Review Focus 4
        $long = '\\' + ('s' * 60) + '\' + ('f' * 60)
        $t = Format-WorkerPerfCopyLines @("1. Freigabe $long pruefen und die Antwortzeit mit dem Soll vergleichen", '- kurz')
        @($t -split "`r`n" | Where-Object { $_.Length -gt 78 }).Count | Should -Be 0
        ($t -replace "`r`n\s*", '') | Should -Match ([regex]::Escape($long)); ($t -split "`r`n")[1] | Should -Match '^   '
    }
    It 'stimmt inhaltlich mit der Vorfallsansicht ueberein' {
        $i = New-Inc @{ id = 2; type = 'engpass'; lead = 'cpu'; start = 1e12; end = 1e12 + 120000; affected = @(@{ s = 0 }, @{ s = 1 })
            signals = @(@{ id = 'cpu.host'; resource = 'cpu'; peak = 99.5; unit = '%'; ideal = 'unter 75 %'; severity = 2 })
            main = @{ app = 'EXCEL.EXE'; user = 'user003'; sharePct = 62; baselinePct = 4 }; cause = @{ kind = 'main'; measure = 'cpu' } }
        $g = New-WorkerPerfGuidance -Catalogue $Cat -Facts (Get-WorkerPerfGuidanceFacts -Incident $i -Context (New-Ctx) -Catalogue $Cat) -Incident $i -Texts $Texts
        $t = New-WorkerPerfCopyText -Incident $i -Guide $g -Data (New-Ctx).Data -Catalogue $Cat
        foreach ($part in $g.title, $g.impact, $g.checks[0].text, 'EXCEL.EXE', '99,5 %', 'unter 75 %', $Cat.copy.checks) { ($t -replace "`r`n\s*", ' ') | Should -Match ([regex]::Escape($part)) }
        if (@($g.remedies).Count) { $t | Should -Match ([regex]::Escape($Cat.copy.remedies)) }
    }
}
```

Die Prüfung der Fassung ohne Namen gegen die Namen der Messung folgt in Task 7 mit der simulierten Stunde.

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Guidance.Tests.ps1 -Output Minimal"`
Expected: FAIL, `Format-WorkerPerfCopyLines` nicht definiert

- [ ] **Step 3: Kopiertexte mit den Signaturen der Interfaces umsetzen**

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Guidance.ps1 tests/Guidance.Tests.ps1
git commit -m "Build plain-text summaries of incidents and of the capture"
```

---

### Task 6: Katalog – Inhalt, Recherche der Druckempfehlungen, Durchsicht

**Files:**
- Create: `src/guidance.de.json`, `docs/guidance/quellen.md`
- Test: `tests/Guidance.Tests.ps1`

**Interfaces:**
- Consumes: Aufbau und Prüfregeln aus Task 1, Bedingungen und Platzhalter aus Task 2.
- Produces: der Katalog mit allen 16 Situationen; `src/guidance.de.json` ist ab hier der Standard für `-GuidanceFile`.

Inhalt:
- Je Situation: Titel in Alltagssprache, „Was war los" in zwei bis drei Sätzen, Wirkung in einem Satz, Kürzel; Prüfschritte mit „was, wo, woran erkennbar", die naheliegendsten zuerst; Abhilfe als Vorschlag mit Voraussetzung in Worten; Ansprechpartner, wo sinnvoll. Grundlage: Empfehlungen von Microsoft und Citrix und die Eigenheiten der Zielumgebung (Citrix-Profilcontainer, Schutzsoftware, AppLocker, Proxy, Fachanwendung mit Datenbank), ohne Namen von Systemen des Auftraggebers. Varianten über die Bedingungen aus Abschnitt 5.4, darunter `cause.security` und `scan` (Scan-Ausschlüsse, Zeitplan), `cause.none`, `cause.nodata`, `endpoint.slow` (Datenbank, Proxy), `unmeasured.*` (Hinweis, was nicht ausgeschlossen ist), `pattern.*` je Muster, `before`.
- Bei `cpu`, `memory`, `disk`, `share` und `profile` ist der erste Prüfschritt mit `when: ["cause.app"]` einer, der `{app}` und `{user}` nennt (Task 7 prüft das an der simulierten Stunde).
- `terms`: alle Fachbegriffe, die in den Texten unvermeidbar bleiben (mindestens Working Set, Eingabeverzögerung, Profilcontainer, Dauerzustand, Druckwarteschlange, Treiberisolierung, Modul, Fehlercode).
- **Druckempfehlungen** (Situation `print` und Elemente mit `pattern.printdriver`): aus der eigenen Dokumentation von Microsoft, Citrix, HP, Kyocera und Brother zum Drucken in Citrix- bzw. Remotedesktop-Umgebungen recherchiert (Microsoft Learn, docs.citrix.com, Support- und Whitepaper-Seiten der Hersteller). Jedes Element trägt `source` = „Hersteller: Titel des Dokuments". Herstellerspezifische Elemente hängen an `driver.vendor.<key>`; Varianten nach `driver.v3`/`driver.v4`, `driver.shared`/`driver.isolated`, `spooler.crash`, `queue.stuck`. Was sich nicht aus einer Quelle des Herstellers belegen lässt, wird nicht aufgenommen.
- **Nachweis** in `docs/guidance/quellen.md`: eine Tabelle je Hersteller mit Titel, Adresse, Abrufdatum, den übernommenen Elementen (Situation, Liste und Position, z. B. `print.remedies[2]`) und eine zweite Tabelle „Nicht aufgenommen" mit der Empfehlung in Kurzform und dem Grund (keine Herstellerquelle gefunden, Quelle veraltet oder nur für ein anderes Produkt, widerspricht einer anderen Herstellerquelle, setzt eine Änderung voraus, die die Messung nicht stützt). Die Datei enthält keine Daten des Auftraggebers.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben**

```powershell
Describe 'Katalog in src' {
    BeforeAll { $script:Real = Read-WorkerPerfGuidance (Join-Path $PSScriptRoot '../src/guidance.de.json') }
    It 'hat fuer jede erzeugbare Situation einen vollstaendigen Eintrag' {
        foreach ($s in $WorkerPerfSituations) { $Real.situations.$s | Should -Not -BeNullOrEmpty -Because $s; @($Real.situations.$s.checks).Count | Should -BeGreaterThan 0 -Because $s }
    }
    It 'nennt fuer jedes Druckelement eine Quelle und Herstellerelemente nur mit Herstellerbedingung' {
        $print = @($Real.situations.print.checks) + @($Real.situations.print.remedies) + @($Real.situations.print.contacts)
        foreach ($e in $print) { [string]$e.source | Should -Not -BeNullOrEmpty -Because $e.text }
        foreach ($v in 'HP', 'Kyocera', 'Brother') {
            foreach ($e in @($print | Where-Object { $_.source -like "$v*" })) { @($e.when) | Should -Contain "driver.vendor.$v" -Because $e.text }
        }
    }
    It 'zeigt herstellerspezifische Elemente nur beim passenden Hersteller' {
        $base = @{ type = 'ereignis'; event = @{ kind = 'print'; key = 'Sim PCL 6'; app = 'spoolsv.exe'; sessions = @(); before = $false; count = 1; patterns = @(); modules = @() }
            events = @(@{ app = 'spoolsv.exe'; service = ''; kind = 'crash'; log = 'application' }) }
        foreach ($v in @(@('HP', 'Kyocera'), @('Kyocera', 'HP'))) {
            $ctx = New-Ctx; $ctx.Data.print.drivers[0].manufacturer = $v[0]
            $i = New-Inc $base; $g = New-WorkerPerfGuidance -Catalogue $Real -Facts (Get-WorkerPerfGuidanceFacts -Incident $i -Context $ctx -Catalogue $Real) -Incident $i -Texts $Texts
            $all = @($g.checks) + @($g.remedies)
            @($all | Where-Object { $_.source -like "$($v[1])*" }).Count | Should -Be 0 -Because $v[0]
        }
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Guidance.Tests.ps1 -Output Minimal"`
Expected: FAIL, `src/guidance.de.json` fehlt

- [ ] **Step 3: Recherchieren, Katalog und Nachweis schreiben** (Recherche zuerst, dann Texte; jede übernommene Druckempfehlung mit Eintrag im Nachweis)

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/guidance.de.json docs/guidance/quellen.md tests/Guidance.Tests.ps1
git commit -m "Add the guidance catalogue with sourced print recommendations"
```

- [ ] **Step 6: Durchsicht durch den Auftraggeber – Haltepunkt**

`src/guidance.de.json` und `docs/guidance/quellen.md` dem Auftraggeber zur fachlichen Durchsicht vorlegen (Abschnitt 5.8 der Spezifikation) und auf seine schriftliche Freigabe warten. Änderungswünsche in derselben Task umsetzen (Tests aus Step 1 grün, eigener Commit `Revise the guidance catalogue after review`). Task 7 beginnt erst nach der Freigabe.

---

### Task 7: Berichtsdaten

**Files:**
- Modify: `src/New-WorkerPerfReport.ps1` (Hilfe und `param`, Einbinden, nach den Vorfällen und vor dem Maskieren), `tests/TestHelpers.ps1` (`New-TestReports`: zusätzlich `report-none-reported.html` = Bericht ohne Befund mit `-ReportedTime` in der Mitte der Messung, im Ergebnis unter `NoneReported`)
- Test: `tests/Report.Tests.ps1`

**Interfaces:**
- Consumes: Tasks 1–6; `Read-WorkerPerfRoles` (`$script:WorkerPerfRoleNames`).
- Produces – neue Felder der Berichtsdaten (die bisherigen bleiben):
  - Parameter `[string]$GuidanceFile` (Standard `guidance.de.json` neben dem Skript); ein Fehler im Katalog bricht vor dem Lesen der Aufzeichnung mit der Meldung aus Task 1 ab.
  - `guidance`: der Katalog wie gelesen (die verwendete Fassung, wie `thresholds`).
  - je Eintrag in `incidents` und `before.incidents`: `guide` (Task 3), `rank` (1-basiert in seiner Liste), `copy = { named, anonymous }`; `anonymous` ist `$null` im maskierten Bericht.
  - `order` (Ids nach Rang), `cards` (die ersten zehn), `more` (Gruppen aus Task 4), `lagebild` (Task 4), `copyAll = { named, anonymous }`.
  - Reihenfolge im Skript: Anleitung, Rangfolge, Lagebild und Kopiertexte entstehen vor der Maskierung; `-Mask` maskiert sie mit allen übrigen Daten.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben**

```powershell
Describe 'Gefuehrter Bericht: simulierte Stunde' {
    BeforeAll {
        $script:G = Read-WorkerPerfGuidance (Join-Path $PSScriptRoot '../src/guidance.de.json')      # Common und Guidance in BeforeAll einbinden
        function Get-ByKey([string]$Key) { $e = $Exp | Where-Object Key -eq $Key; if ($e.Type -eq 'ereignis') { $D.incidents | Where-Object { $_.type -eq 'ereignis' -and [Math]::Abs($_.start - $e.StartMs) -le 20000 } } else { Get-Hit $Key } }
        $script:Situation = @{ homeoffice = 'chronic.network'; cpu = 'cpu'; memory = 'memory'; disk = 'disk'; share = 'share'; profile = 'profile'; backend = 'delay.many'
            hang = 'delay.single'; 'crash.memory' = 'crash'; 'profile.logon' = 'profileerror'; 'crash.manyusers' = 'crash'; 'print.spooler' = 'print' }
    }
    It 'bestimmt Kennung, Titel, Wirkung und ersten Schritt jedes Vorfalls' {
        foreach ($k in $Situation.Keys) {
            $i = Get-ByKey $k; $s = $Situation[$k]
            $i.guide.situation | Should -Be $s -Because $k; $i.guide.title | Should -Be $G.situations.$s.title -Because $k
            $i.guide.impact | Should -Not -BeNullOrEmpty -Because $k; @($i.guide.checks).Count | Should -BeGreaterThan 0 -Because $k
        }
        (Get-ByKey 'cpu').guide.checks[0].text | Should -Match 'EXCEL\.EXE'                         # die gestuetzte Variante cause.app steht vorn
        @($D.before.incidents | ForEach-Object { $_.guide.conditions -contains 'before' }) | Should -Not -Contain $false
    }
    It 'ordnet die Vorfaelle' {
        $rank = @{}; foreach ($k in $Situation.Keys) { $rank[$k] = (Get-ByKey $k).rank }
        $rank.backend | Should -Be 1; $rank.cpu | Should -Be 2; $rank.memory | Should -Be 3; $rank['crash.manyusers'] | Should -Be 4
        $rank.homeoffice | Should -Be 12; $rank['print.spooler'] | Should -Be 11
        foreach ($k in 'disk', 'share', 'profile', 'hang', 'crash.memory', 'profile.logon') { $rank[$k] | Should -BeIn (5..10) -Because $k }
        @($D.order).Count | Should -Be 12; @($D.cards).Count | Should -Be 10; @($D.more).Count | Should -Be 2
    }
    It 'nennt im Lagebild die erwarteten Kennzahlen' {
        $D.lagebild.state | Should -Be 'red'; $D.lagebild.kpis.bottlenecks | Should -Be 5; $D.lagebild.kpis.delays | Should -Be 2
        $D.lagebild.kpis.events | Should -Be 4; $D.lagebild.kpis.chronic | Should -Be 1; $D.lagebild.kpis.minutes | Should -BeGreaterThan 12; $D.lagebild.kpis.minutes | Should -BeLessThan 14
        $D.lagebild.top | Should -Be (Get-ByKey 'backend').id
    }
    It 'liefert Kopiertexte mit und ohne Namen' {
        foreach ($k in $Situation.Keys) {
            $c = (Get-ByKey $k).copy
            @($c.named -split "`r`n" | Where-Object { $_.Length -gt 78 }).Count | Should -Be 0 -Because $k
            ($c.named -replace "`r`n\s*", ' ') | Should -Match ([regex]::Escape((Get-ByKey $k).guide.title)) -Because $k
            foreach ($n in @(2..26 | ForEach-Object { 'user{0:d3}' -f ($_ - 1) }) + 'WS-\d{4}', 'SIM-VDA01', 'fs01', 'CONTOSO') { $c.anonymous | Should -Not -Match $n -Because $k }
        }
        (Get-ByKey 'cpu').copy.anonymous | Should -Match 'EXCEL\.EXE'                                 # Anwendungsnamen bleiben
        $D.copyAll.named | Should -Match 'SIM-VDA01'; @($D.copyAll.named -split "`r`n" | Where-Object { $_.Length -gt 78 }).Count | Should -Be 0
    }
    It 'maskiert Anleitung und Kopiertexte im maskierten Bericht und laesst die Fassung ohne Namen weg' {
        $m = Get-ReportData $R.Masked
        $m.copyAll.anonymous | Should -BeNullOrEmpty; $m.copyAll.named | Should -Not -Match 'SIM-VDA01'; (($m.incidents | Where-Object lead -eq 'cpu').copy.named) | Should -Not -Match 'user003'
    }
    It 'bricht bei einem fehlerhaften Katalog mit Eintrag und Feld ab' {
        $bad = Join-Path $TestDrive 'g.json'; $j = Get-Content (Join-Path $PSScriptRoot '../src/guidance.de.json') -Raw | ConvertFrom-Json
        $j.situations.cpu.PSObject.Properties.Remove('impact'); [IO.File]::WriteAllText($bad, ($j | ConvertTo-Json -Depth 10))
        { & (Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1') -Path $R.Run -OutFile (Join-Path $TestDrive 'g.html') -GuidanceFile $bad 6>$null } | Should -Throw "*Eintrag 'cpu'*Feld 'impact'*"
    }
}
```

`$R.Masked` ist `report-masked.html` aus dem Maskierungsplan (`New-TestReports`).

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Report.Tests.ps1 -Output Minimal"`
Expected: FAIL, kein Feld `guide`

- [ ] **Step 3: `-GuidanceFile` und die neuen Felder mit den Funktionen der Tasks 1–5 einbauen**

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"` und die Browserprüfungen (die Seite ist unverändert und bleibt grün)
Expected: `Failed: 0`, `browser checks passed: <n>`

- [ ] **Step 5: Commit**

```bash
git add src/New-WorkerPerfReport.ps1 tests/TestHelpers.ps1 tests/Report.Tests.ps1
git commit -m "Put guidance, ranking, situation summary and copy texts into the report data"
```

---

### Gestaltung der Seite (gilt für die Tasks 8–11)

Beide Ansichten nutzen dieselben Bausteine: Statuskennzeichen (`.status` mit Symbol und Wort), Knöpfe (`.btn`, `.btn.primary`), Karten (`.card`), Diagramme (`chart()` wie heute), Tabellen (`table()` wie heute). Sie unterscheiden sich nur über Farb- und Abstandsvariablen an `body[data-view]`: `guided` hell (heller Grund, weiße Karten mit feinem Rand, großzügige Abstände 16–24 px, Schrift 15 px), `expert` dunkel (dunkelgrauer Grund, dichte Abstände 6–10 px, Schrift 13 px). Das Erscheinungsbild folgt der Ansicht, nicht dem Farbschema des Betriebssystems.

**Kopfleiste** (beide Ansichten, oben fest): links „WorkerPerf", Server, Datum und Zeitraum der Messung; bei `meta.mask` der Hinweis `#maskInfo`; rechts der Umschalter `#viewSwitch` mit zwei Knöpfen „Geführt" und „Experte" (`button[data-view]`, `aria-pressed`).

**Geführte Ansicht `#guided`** (eine Spalte, höchstens 1100 px breit, mittig):
1. **Band `#band[data-state]`** über die volle Breite, Hintergrund je Zustand als helle Tönung mit kräftigem Rand links (rot, gelb, grün): links groß das Statuskennzeichen `#bandState` (Symbol und Wort), daneben der Satz `#bandSentence` als Überschrift; darunter fünf Kennzahlen `#kpis .kpi[data-kpi]` (`bottlenecks`, `delays`, `events`, `chronic`, `minutes`; je große Zahl `.num` und Beschriftung „Engpässe auf dem Server", „Verzögerungen von außen", „Abstürze und Fehler", „Dauerzustände", „Minuten mit spürbarer Störung"), die bei schmaler Breite umbrechen; rechts unten die Knöpfe `#openTop` „Wichtigsten Vorfall öffnen" (primär; fehlt ohne Vorfall) und `#copyAll` „Zusammenfassung kopieren", daneben der Schalter `#anonSwitch` „ohne Namen" (Kontrollkästchen; fehlt im maskierten Bericht).
2. **Hinweise `#hints`** direkt unter dem Band, nur mit Inhalt: je Hinweis eine Zeile mit `▲` auf gelblichem Grund.
3. **Zeitleiste `#timeline`** (die heutige Zeitleiste mit ihren Markierungen und Zeilen je Ereignisgruppe) in einer Karte „Zeitleiste der Messung"; ein Klick auf eine Markierung öffnet ihren Vorfall.
4. **Karten `#cards`**: die Vorfälle aus `cards` als Raster (ab 900 px zwei Spalten, darunter eine). Karte `.card.inc[data-id]` mit linkem Rand in der Farbe der Schwere; oben eine Zeile mit der Einordnung in Benutzersicht (`.card-view`, z. B. „spürbar für 6 Sitzungen, 2 Minuten") links und Uhrzeit und Dauer (`.card-when`) rechts; darunter der Titel (`.card-title`, Überschrift), ein Satz zur Wirkung (`.card-impact`), eine Zeile Verursacher oder Hinweis (`.card-cause`), der erste Schritt (`.card-first`, „Erster Schritt: …"); unten links das Kürzel der Ressource (`.card-short`, kleines Etikett), rechts die Knöpfe „Öffnen" (`.card-open`) und „Kopieren" (`.card-copy`). Die ganze Karte ist kein Link; nur die Knöpfe sind bedienbar.
5. **Weitere Vorfälle `#more`**: kompakte Liste der Gruppen aus `more`, je Gruppe ein Element `.group`: bei mehreren Vorfällen ein `details.group` mit dem Label als Zusammenfassung und je Vorfall einer Zeile `.row` mit Uhrzeit, Titel und „Öffnen", sonst ein `div.group` mit einer solchen Zeile.
6. **Vor der Messung `#beforeG`**: Überschrift, der Hinweis „Für diese Zeit liegen keine Messwerte vor.", Karten der Rückblick-Vorfälle wie unter 4.
7. **Eingeklappt** `details#measured` „Was wurde gemessen, was nicht" (gemessene und nicht gemessene Werte wie heute im Hinweis ohne Befund, dazu einzelne Überschreitungen) und `details#qualityG` „Messqualität" (dieselben Inhalte wie die Messqualität der Expertenansicht).
8. **Kein Vorfall:** Band grün mit „Keine Störung erkannt", keine Karten; `#measured` ist aufgeklappt; mit `meta.focus.reportedMs` eine Karte `#aroundReported` „Um die gemeldete Zeit" mit den Verläufen von CPU, Arbeitsspeicher und Eingabeverzögerung ±15 min.

**Vorfallsansicht `#incident[data-id]`** (ersetzt Band, Karten und Listen mit Überblenden; Zurück stellt sie wieder her): Kopf mit Titel (`.iv-title`), darunter klein die Fachbezeichnung (`.iv-tech`), Zeit, Dauer und Einordnung (`.iv-meta`); Knöpfe `#ivCopy` „Zusammenfassung kopieren", `#ivExpert` „In der Expertenansicht zeigen", `#ivBack` „Zurück zum Lagebild", `#ivNext` „Nächster Vorfall" (nach Rang; fehlt beim letzten). Darunter die Abschnitte in fester Reihenfolge: (1) `.iv-what` „Was war los" mit `meaning` links und rechts (unter 900 px darunter) einem kleinen Diagramm `.iv-chart` des auslösenden Messwerts mit Soll-Linie; bei Dauerzuständen sagt der erste Satz, dass der Zustand über die ganze Messung oder einen großen Teil anhielt; bei Rückblick-Vorfällen steht dort „Für diese Zeit liegen keine Messwerte vor." und das Diagramm entfällt. (2) `.iv-cause` „Wer oder was hat es verursacht" mit den Inhalten der heutigen Ursachenbox (Hauptverursacher mit Anwendung, Benutzer, Anteil, üblichem Wert; Begleiter; „kein einzelner Hauptverursacher"; bei Verzögerung ohne Engpass der Hinweis auf eine Ursache außerhalb; bei Ereignisvorfällen die Aussagen der Muster). (3) `.iv-todo` „Was ist zu tun" mit `ol.checks` (je Schritt Text fett, darunter „Wo:" und „Woran erkennbar:"), abgesetzt `.remedies` „Mögliche Abhilfe – Vorschlag" mit „Wenn …, dann …", `.contact` „An wen wenden"; die Quelle eines Elements steht klein darunter. Bei `guide.fallback` ein sichtbarer Hinweis über den Schritten. (4) `.iv-affected` „Wer war betroffen" (Sitzungen mit Benutzer, Client, höchster Verzögerung; bei nicht gemessener Eingabeverzögerung der Satz der heutigen Seite). (5) `details.iv-evidence` „Belege" eingeklappt: Messwerte, beteiligte Prozesse und Ranglisten, Ereignisse, Gegenstellen, ICA Round Trip, der heutige Fachsatz (`incident.text`), was nicht gemessen wurde – die Inhalte des heutigen aufgeklappten Vorfalls. Begriffe aus `guide.terms` sind in den Texten unterlegt (`.term[data-term]`, Tastaturfokus möglich) und zeigen ihre Erklärung beim Überfahren, Antippen oder Fokus (`.term-pop`).

**Expertenansicht `#expert`** (volle Breite, dicht): oben unter der Kopfleiste fest die **Zeitraumleiste** `#rangeBar` mit `#rangeInfo` („Zeitraum 10:05:00–10:07:00 (2 min)") und dem Knopf `#rangeAll` „Gesamte Messung" (bei ganzer Messung deaktiviert) sowie `#rangeSnaps` („gestützt auf 2 Schnappschüsse"), nur unter drei Schnappschüssen. Darunter zwei Spalten: links die **Vorfallsspalte** `#incList` (280 px, scrollt in sich) mit je Vorfall `.inc[data-id]`: Statuskennzeichen, Uhrzeit, Art, Verursacher in einer Zeile, darunter der Link „Geführt öffnen" (`.inc-guided`); der gewählte Vorfall ist hervorgehoben. Rechts oben die **Kacheln** `#tiles .tile[data-signal][data-status]` (Maximum, Statuskennzeichen, Zeitanteil über dem Soll, alles im geltenden Zeitraum), darunter die **Diagramme** mit gemeinsamer Zeitachse (die heutigen Diagramme mit ihren Ids; gestapelte Diagramme aufteilbar „nach Host | Sitzung | Anwendung"), das Fenster des gewählten Vorfalls als getönter Bereich, darunter der **Tabellenbereich** mit Reitern `#xtabs button[data-tab]`: `sollist` Soll-Ist, `sessions` Sitzungen, `apps` Anwendungen, `procs` Prozesse, `quality` Messqualität, `events` Ereignisse, `print` Drucken, `before` Vor der Messung; Bereiche `#xt-<name>` mit den heutigen Tabellen und Ids (`#sollist`, `#tSessions`, `#tApps`, `#tProcs`, `#quality`, `#limits`, `#tEvents`, `#tPrintDrivers`, `#tPrintQueues`, `#before`). Unter 900 px eine Spalte: die Vorfallsspalte wird zu einer aufklappbaren Liste über den Kacheln.

---

### Task 8: Zwei Ansichten, Lagebild und Karten

**Files:**
- Modify: `src/report-template.html`, `tests/report-browser.js`

**Interfaces:**
- Consumes: Berichtsdaten aus Task 7; die Gestaltung oben.
- Produces: `body[data-view]`, `#viewSwitch`, `#guided` mit Band, Hinweisen, Zeitleiste, Karten, weiteren Vorfällen, Vor der Messung, `#measured`, `#qualityG`; `#expert` enthält in dieser Task die heutige Seite unverändert (Reiterleiste, Zoomleiste, Reiter mit ihren Ids) im dunklen Erscheinungsbild. `window.WP` erhält `view` (`'guided'|'expert'`) und `showView(name)`. Die Zeitleiste zieht in die geführte Ansicht; ein Klick auf eine Markierung wechselt in dieser Task in die Expertenansicht und klappt den Vorfall dort auf wie heute (Task 9 ändert das).

Umstellung der Browserprüfungen (jede Aussage bleibt, nur ihr Ort ändert sich):
- Neuer Helfer `showExpert(page)` (Klick auf `#viewSwitch button[data-view=expert]`); `checkPage`, `checkFindings`, `checkFinalFix`, `checkEvents`, `checkMask` rufen ihn nach `open` auf, bevor sie Reiter anklicken.
- `'Befunde ist der Startreiter'` → „in der Expertenansicht ist Befunde der erste Reiter".
- Die drei Aussagen zur Zeitleiste (`'eine Markierung je Vorfall'`, `'Ereignisse in der Zeitleiste'`, `'gemeldete Uhrzeit markiert'`) und die Ereigniszeilen aus `checkEvents` prüfen `#guided #timeline`; `'Klick stellt die Diagramme auf das Fenster ein'` klickt die Markierung in der geführten Ansicht und prüft danach Ansicht `expert` und `WP.zoom` wie bisher.
- `'Hinweis ohne Befund'`, `'ausdrueckliche Aussage'`, `'einzelne Ueberschreitungen genannt'` und `'keine Aussage, alles sei im Soll'` bleiben auf `#noFinding` in der Expertenansicht und gelten zusätzlich für `#measured` in der geführten.

- [ ] **Step 1: Die fehlschlagenden Prüfungen schreiben** (neue Funktion `checkGuided`, in der Schleife zuerst aufrufen; die Umstellungen oben im selben Schritt)

```js
async function checkGuided(browser, dir, scheme) {
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme);
  ok(await page.evaluate(() => document.body.dataset.view) === 'guided' && await page.locator('#guided').isVisible() && !(await page.locator('#expert').isVisible()), 'oeffnet in der gefuehrten Ansicht');
  ok(await page.locator('#band').getAttribute('data-state') === D.lagebild.state, 'Bandfarbe nach Zustand');
  ok((await page.locator('#bandState').innerText()).includes(D.lagebild.word) && (await page.locator('#bandSentence').innerText()) === D.lagebild.sentence, 'Zustand als Symbol und Wort, Satz');
  for (const k of ['bottlenecks', 'delays', 'events', 'chronic']) ok((await page.locator(`#kpis .kpi[data-kpi="${k}"] .num`).innerText()) === String(D.lagebild.kpis[k]), 'Kennzahl ' + k);
  const box = await page.locator('#openTop').boundingBox();
  ok(box && box.y + box.height <= 900, 'Handlungsbedarf und erster Klick ohne Scrollen sichtbar');
  ok(await page.locator('#cards .card.inc').count() === D.cards.length, 'zehn Karten');
  ok(await page.locator('#cards .card.inc').first().getAttribute('data-id') === String(D.order[0]), 'wichtigster Vorfall zuerst');
  const first = D.incidents.find((i) => i.id === D.order[0]);
  const card = page.locator(`#cards .card.inc[data-id="${first.id}"]`);
  ok((await card.locator('.card-title').innerText()) === first.guide.title && (await card.locator('.card-first').innerText()).includes(first.guide.checks[0].text), 'Karte mit Titel und erstem Schritt');
  ok((await card.locator('.card-short').innerText()) === first.guide.short && await card.locator('.card-open').count() === 1 && await card.locator('.card-copy').count() === 1, 'Kuerzel und Knoepfe');
  ok(await page.locator('#more > .group').count() === D.more.length, 'uebrige Vorfaelle als kompakte Liste');
  ok(await page.locator('#beforeG .card.inc').count() === D.before.incidents.length, 'Vor der Messung mit denselben Karten');
  ok((await page.locator('#qualityG').innerText()).includes('WorkerPerf'), 'Messqualitaet eingeklappt erreichbar');
  ok(page.errors.length === 0, 'Skriptfehler: ' + page.errors.join(' | '));
  await page.close();
  const n = await open(browser, path.join(dir, 'report-none.html'), scheme);
  ok(await n.page.locator('#band').getAttribute('data-state') === 'green' && (await n.page.locator('#bandSentence').innerText()) === 'Keine Störung erkannt.', 'kein Vorfall: gruenes Band');
  ok(await n.page.locator('#cards .card').count() === 0 && await n.page.locator('#openTop').count() === 0, 'kein Vorfall: keine Karten');
  await n.page.close();
  const r = await open(browser, path.join(dir, 'report-none-reported.html'), scheme);
  ok(await r.page.locator('#aroundReported svg path').count() > 0, 'kein Vorfall: Messwerte um die gemeldete Zeit');
  await r.page.close();
}
```

- [ ] **Step 2: Prüfung ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/New-TestReports.ps1 -OutDir /tmp/wp-reports && node tests/report-browser.js /tmp/wp-reports`
Expected: `AssertionError: oeffnet in der gefuehrten Ansicht`

- [ ] **Step 3: Ansichten, Band, Karten und Listen nach der Gestaltung bauen** (die heutige Seite wandert in `#expert`; die Farbvariablen hängen an `body[data-view]`)

- [ ] **Step 4: Prüfungen ausführen**

Run: wie Step 2 und `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`
Expected: `browser checks passed: <n>`, `Failed: 0`

- [ ] **Step 5: Seite ansehen** – Bildschirmfotos der geführten Ansicht bei 1400 × 900 (Band und erster Knopf ohne Scrollen), der Expertenansicht und des Berichts ohne Vorfall; Mängel beheben, Step 4 wiederholen.

- [ ] **Step 6: Commit**

```bash
git add src/report-template.html tests/report-browser.js
git commit -m "Open the report in a guided view with situation band and incident cards"
```

---

### Task 9: Vorfallsansicht und Kopieren

**Files:**
- Modify: `src/report-template.html`, `tests/report-browser.js`

**Interfaces:**
- Consumes: Task 8; `incidents[].guide`, `.copy`, `copyAll`.
- Produces: `#incident` nach der Gestaltung; `WP.openIncident(id)`, `WP.closeIncident()`; Kopieren `copyText(text, button)`: erst `navigator.clipboard.writeText`, sonst `document.execCommand('copy')` über ein verstecktes Textfeld, sonst der Dialog `#copyFallback` mit `textarea` (Text bereits markiert) und Knopf „Schließen"; nach Erfolg zeigt der Knopf etwa 1,5 s „Kopiert". `#anonSwitch` wählt `copy.anonymous` statt `copy.named`. Karten-„Öffnen", `#openTop`, Markierungen der Zeitleiste und Einträge von `#more` öffnen die Vorfallsansicht; `#ivExpert` wechselt in die Expertenansicht mit `WP.setZoom` auf das Fenster des Vorfalls mit Vor- und Nachlauf (wie `incWindow` heute) und klappt dort den Vorfall auf.

Umstellung der Browserprüfungen: `'Klick stellt die Diagramme auf das Fenster ein'` (Task 8: Markierung → Expertenansicht) prüft jetzt Markierung → `#incident[data-id]` sichtbar → `#ivExpert` → Ansicht `expert` und `WP.zoom` umschließt das Fenster wie bisher.

- [ ] **Step 1: Die fehlschlagenden Prüfungen schreiben**

```js
async function checkIncidentView(browser, dir, scheme) {
  const ctx = await browser.newContext({ viewport: { width: 1400, height: 900 }, colorScheme: scheme });
  await ctx.addInitScript(() => {                                     // die drei Wege beobachtbar machen
    window.__copied = []; window.__exec = 0;
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: (t) => { window.__copied.push(t); return Promise.resolve(); } } });
    document.execCommand = () => { window.__exec++; return true; };
  });
  const page = await ctx.newPage(); page.errors = []; page.on('pageerror', (e) => page.errors.push(e.message));
  await page.goto('file://' + path.join(dir, 'report.html'));
  const D = await page.evaluate(() => JSON.parse(document.getElementById('wp-data').textContent));
  const cpu = D.incidents.find((i) => i.lead === 'cpu');
  await page.click(`#cards .card.inc[data-id="${cpu.id}"] .card-open`);
  const iv = page.locator('#incident');
  ok(await iv.getAttribute('data-id') === String(cpu.id) && (await iv.locator('.iv-title').innerText()) === cpu.guide.title, 'Vorfallsansicht ueber die Karte');
  const order = await iv.locator('section, details').evaluateAll((els) => els.map((e) => e.className.split(' ').find((c) => c.startsWith('iv-'))));
  ok(JSON.stringify(order.filter(Boolean)) === JSON.stringify(['iv-what', 'iv-cause', 'iv-todo', 'iv-affected', 'iv-evidence']), 'Abschnitte in fester Reihenfolge');
  ok(await iv.locator('.iv-todo ol.checks li').count() === cpu.guide.checks.length && await iv.locator('.iv-chart svg path').count() > 0, 'Pruefschritte und Diagramm');
  ok(await iv.locator('.iv-affected li').count() === cpu.affected.length, 'Betroffene aufgelistet');               // aus checkFindings
  await iv.locator('details.iv-evidence summary').click();
  ok((await iv.locator('.iv-evidence .contributors').innerText()).includes('EXCEL.EXE') && (await iv.locator('.iv-evidence').innerText()).includes(cpu.text), 'Belege mit Rangliste und Fachsatz');
  if (cpu.guide.terms.length) { await iv.locator('.term').first().hover(); ok(await page.locator('.term-pop').isVisible(), 'Fachbegriff erklaert sich'); }
  await page.click('#ivCopy');
  ok(await page.evaluate(() => window.__copied.at(-1)) === cpu.copy.named && (await page.locator('#ivCopy').innerText()).includes('Kopiert'), 'Kopieren ueber die Zwischenablage');
  await page.click('#ivBack'); await page.check('#anonSwitch'); await page.click('#copyAll');
  ok(await page.evaluate(() => window.__copied.at(-1)) === D.copyAll.anonymous, 'Zusammenfassung ohne Namen');
  await page.evaluate(() => { Object.defineProperty(navigator, 'clipboard', { configurable: true, value: undefined }); });
  await page.click(`#cards .card.inc[data-id="${cpu.id}"] .card-copy`);
  ok(await page.evaluate(() => window.__exec) === 1 && (await page.locator(`#cards .card.inc[data-id="${cpu.id}"] .card-copy`).innerText()).includes('Kopiert'), 'Kopieren ueber den aelteren Befehl');
  await page.evaluate(() => { document.execCommand = () => false; });
  await page.click(`#cards .card.inc[data-id="${cpu.id}"] .card-copy`);
  ok(await page.locator('#copyFallback textarea').isVisible() && await page.evaluate(() => { const t = document.querySelector('#copyFallback textarea'); return t.selectionStart === 0 && t.selectionEnd === t.value.length; }), 'Ausweichfeld mit markiertem Text');
  await page.click('#copyFallback button');
  const mark = D.incidents.find((i) => i.lead === 'memory');
  await page.click(`#timeline .mark[data-incident="${mark.id}"]`);
  ok(await iv.getAttribute('data-id') === String(mark.id), 'Vorfallsansicht ueber die Zeitleiste');
  await page.click('#ivExpert');
  const z = await page.evaluate(() => window.WP.zoom);
  ok(await page.evaluate(() => window.WP.view) === 'expert' && z && z.t0 < mark.start && z.t1 > mark.end, 'In der Expertenansicht zeigen setzt den Zeitraum');
  ok(page.errors.length === 0, 'Skriptfehler: ' + page.errors.join(' | '));
  await ctx.close();
  const p = await open(browser, patched(dir, 'report.html', 'report-html-value.html', (J) => { const c = J.incidents.find((i) => i.lead === 'cpu'); c.guide.title = '<b>fett</b> {user}'; }), scheme);   // Review Focus 1
  await p.page.click(`#cards .card.inc[data-id="${cpu.id}"] .card-open`);
  ok((await p.page.locator('#incident .iv-title').innerText()) === '<b>fett</b> {user}' && await p.page.locator('#incident .iv-title b').count() === 0, 'Werte nicht als HTML');
  await p.page.close();
}
```

- [ ] **Step 2: Prüfung ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/New-TestReports.ps1 -OutDir /tmp/wp-reports && node tests/report-browser.js /tmp/wp-reports`
Expected: `AssertionError: Vorfallsansicht ueber die Karte`

- [ ] **Step 3: Vorfallsansicht, Begriffe und Kopieren nach der Gestaltung bauen**

- [ ] **Step 4: Prüfungen ausführen**

Run: wie Step 2 und die Pester-Tests
Expected: `browser checks passed: <n>`, `Failed: 0`

- [ ] **Step 5: Seite ansehen** – Vorfallsansicht eines Engpasses, einer Verzögerung ohne Engpass, eines Druckproblems und eines Rückblick-Vorfalls; Mängel beheben, Step 4 wiederholen.

- [ ] **Step 6: Commit**

```bash
git add src/report-template.html tests/report-browser.js
git commit -m "Add the incident view with steps, evidence and copy to clipboard"
```

---

### Task 10: Expertenansicht mit gemeinsamem Zeitraum

**Files:**
- Modify: `src/report-template.html`, `tests/report-browser.js`

**Interfaces:**
- Consumes: Tasks 8 und 9; die Reihen der Berichtsdaten (`host`, `sessions[].cpu/ws/io/inT/inMs/rtt`, `apps[].cpu/ws`, `procs[].cpu/ws/o`, `volumes`, `shares`, `probes`, `snapT`), `incidents[].signals[]` (`id`, `start`, `end`, `severity`).
- Produces: `#expert` nach der Gestaltung; die fünf Reiter der heutigen Seite entfallen, ihre Inhalte stehen in Kacheln, Diagrammen und `#xtabs`. `WP.setZoom`, `WP.resetZoom`, `WP.zoom`, `WP.onZoom` bleiben die Schnittstelle des gemeinsamen Zeitraums. Funktionen der Seite für den Zeitraum: `rangeStats(signalId, t0, t1) -> { max, avg, p95, pctNormal, pctWarn, pctCrit, status, snaps }` (Status aus den Befunden, die den Zeitraum schneiden; bei Signalen mit Instanzen die schlechteste Instanz je Zeitpunkt wie heute) und `rangeRows(kind, t0, t1)` für Sitzungen, Anwendungen und Prozesse aus ihren Schnappschussreihen. Wer im Zeitraum keinen Schnappschuss mit Last hat, fehlt in den Tabellen; Anwendungen ohne Reihe (geringe Last) fehlen bei gesetztem Zeitraum, ein Hinweis nennt ihre Zahl. `#rangeSnaps` erscheint unter drei Schnappschüssen im Zeitraum. Ein Klick auf `.inc` setzt den Zeitraum auf das Fenster des Vorfalls mit Vor- und Nachlauf (mindestens 10 s, innerhalb der Messung), hebt ihn in `#incList` (Klasse `selected`) und als getönten Bereich `.incband` in allen Diagrammen hervor.

Umstellung der Browserprüfungen:
- `'fuenf Reiter'` → `#xtabs button[data-tab]` zählt acht.
- `page.click('nav button[data-tab=<x>]')` → `page.click('#xtabs button[data-tab=<x>]')` für `sessions`, `apps`, `procs`; Aufrufe für `overview` entfallen, weil Kacheln und Diagramme immer sichtbar sind; alle Aussagen über `#chCpu` … `#chMemStack`, `.tile[data-signal]`, `#tApps`, `#tSessions`, `#dSessions`, `#tProcs` bleiben.
- `'ohne Zoom keine Ruecksetz-Schaltflaeche'` / `'Ruecksetz-Schaltflaeche sichtbar'` → `#rangeAll` ist ohne Zeitraum deaktiviert und mit Zeitraum aktiv (Abschnitt 3.2: der Knopf ist immer da); `page.click('#zoomReset')` → `page.click('#rangeAll')`.
- `'ein Eintrag je Vorfall'` → `#incList .inc` zählt `D.incidents.length`.
- Alle Aussagen über das aufgeklappte `#incidents .incident` (`.text`, `.badge`, `.detail .affected li`, `.detail .contributors`, `.detail svg path`, `.causebox`, `.detail .sigcharts .legend`, `.detail .essentials`, `.detail .patterns`, `.detail .evlist`, „Ereignisse im Fenster", `'nicht als Begleiter bezeichnet'`) wandern in die Vorfallsansicht: `openIncident(page, id)` ruft `WP.openIncident(id)` und klappt `.iv-evidence` auf; `.causebox` → `.iv-cause`, `.essentials` → `.iv-affected`, `.detail .contributors`/`.sigcharts`/`.evlist`/`.patterns` → `.iv-evidence …`, `.text` → `.iv-evidence .techtext`, `.badge` → `.iv-meta .status`.
- `#sollist`, `#quality`, `#limits`, `#sollNote`, `#tEvents`, `#eventList`, `#before`, `#tPrintDrivers`, `#tPrintQueues` werden vor der Prüfung über ihren Reiter in `#xtabs` geöffnet; die Aussagen bleiben. `'Ereignis stellt den Zoom ein'` gilt für `#tEvents` im Reiter `events`.
- `checkEvents` (Ereignisplan): `#incidents .incident.type-ereignis` → `#incList .inc.type-ereignis`; `#before` und `#tPrintDrivers`/`#tPrintQueues` nach Öffnen der Reiter `before` bzw. `print`; `.sess-events` im Reiter `sessions`. `checkMask` (Maskierungsplan) bleibt unverändert.
- `'Vorfall des Benutzers steht vorn'` → im Fokus-Bericht steht der Vorfall mit `focus` in `#incList` vorn und trägt die Kennzeichnung; `'Fokus genannt'` prüft `#focusInfo` in der Kopfleiste.

- [ ] **Step 1: Die fehlschlagenden Prüfungen schreiben** (neue Funktion `checkRange` und die Umstellungen)

```js
async function checkRange(browser, dir, scheme) {
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme);
  await showExpert(page);
  ok(await page.locator('#rangeAll').isDisabled() && (await page.locator('#rangeInfo').innerText()).startsWith('Zeitraum'), 'Zeitraumleiste zeigt immer den Zeitraum');
  const cpu = D.incidents.find((i) => i.lead === 'cpu');
  const before = await page.locator('#tSessions tbody tr').count();
  await page.click(`#incList .inc[data-id="${cpu.id}"]`);
  const z = await page.evaluate(() => window.WP.zoom);
  ok(z && z.t0 < cpu.start && z.t1 > cpu.end, 'Klick auf einen Vorfall setzt den Zeitraum');
  ok(await page.locator(`#incList .inc[data-id="${cpu.id}"].selected`).count() === 1 && await page.locator('#chCpu .incband').count() === 1, 'Vorfall und Fenster hervorgehoben');
  ok((await page.locator('.tile[data-signal="cpu.host"]').innerText()).includes('kritisch'), 'Kachel bezogen auf den Zeitraum');
  await page.click('#xtabs button[data-tab=sessions]');
  ok(await page.locator('#tSessions tbody tr').count() <= before, 'Tabellen nur mit im Zeitraum aktiven Sitzungen');
  await page.evaluate(([a]) => window.WP.setZoom(a, a + 20000), [cpu.start]);
  ok(await page.locator('#rangeSnaps').isVisible(), 'Hinweis bei weniger als drei Schnappschuessen');
  await page.click('#xtabs button[data-tab=sollist]');
  const rowMax = await page.locator('#sollist tbody tr[data-id="cpu.host"]').innerText();
  await page.click('#rangeAll');
  ok(await page.evaluate(() => window.WP.zoom === null) && (await page.locator('#sollist tbody tr[data-id="cpu.host"]').innerText()) !== rowMax, 'Soll-Ist folgt dem Zeitraum');
  const box = await page.locator('#chCpu svg').boundingBox();
  await page.mouse.move(box.x + box.width * 0.3, box.y + 40); await page.mouse.down(); await page.mouse.move(box.x + box.width * 0.5, box.y + 40); await page.mouse.up();
  ok(await page.evaluate(() => window.WP.zoom !== null), 'Ziehen im Diagramm setzt den Zeitraum');
  await page.click(`#incList .inc[data-id="${cpu.id}"] .inc-guided`);
  ok(await page.evaluate(() => window.WP.view) === 'guided' && await page.locator('#incident').getAttribute('data-id') === String(cpu.id), 'Eintrag fuehrt in die gefuehrte Vorfallsansicht');
  ok(page.errors.length === 0, 'Skriptfehler: ' + page.errors.join(' | '));
  await page.close();
  const many = await open(browser, patched(dir, 'report.html', 'report-many.html', (J) => {          // viele Vorfaelle: zehn Karten, Rest als Liste
    const c = J.incidents.find((i) => i.lead === 'cpu'), base = Math.max(...J.incidents.map((i) => i.id));
    for (let k = 1; k <= 14; k++) J.incidents.push(Object.assign({}, c, { id: base + k, rank: 100 + k }));
    J.order = J.order.concat([...Array(14).keys()].map((k) => base + k + 1)); J.cards = J.order.slice(0, 10);
    J.more = [{ label: '14-mal ' + c.guide.title, situation: 'cpu', ids: J.order.slice(10) }];
  }), scheme);
  ok(await many.page.locator('#cards .card.inc').count() === 10 && await many.page.locator('#more details.group').count() === 1, 'viele Vorfaelle');
  await many.page.click('#more details.group summary');
  ok(await many.page.locator('#more details.group .row').count() === many.D.more[0].ids.length, 'Gruppe laesst sich aufklappen');
  await many.page.close();
  const edge = await open(browser, patched(dir, 'report.html', 'report-edge.html', (J) => {          // Review Focus 5
    const e = J.incidents.find((i) => i.type === 'ereignis'); e.start = e.end = J.meta.end;
  }), scheme);
  const e = edge.D.incidents.find((i) => i.type === 'ereignis');
  await edge.page.evaluate((id) => window.WP.openIncident(id), e.id); await edge.page.click('#ivExpert');
  const ez = await edge.page.evaluate(() => window.WP.zoom);
  ok(ez && ez.t1 - ez.t0 >= 10000 && ez.t1 <= edge.D.meta.end && ez.t0 < e.start, 'Zeitraum eines Ereignisses ohne Dauer am Ende');
  await edge.page.close();
}
```

- [ ] **Step 2: Prüfung ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/New-TestReports.ps1 -OutDir /tmp/wp-reports && node tests/report-browser.js /tmp/wp-reports`
Expected: `AssertionError: Zeitraumleiste zeigt immer den Zeitraum`

- [ ] **Step 3: Expertenansicht nach der Gestaltung bauen**

- [ ] **Step 4: Prüfungen ausführen**

Run: wie Step 2 und die Pester-Tests
Expected: `browser checks passed: <n>`, `Failed: 0`

- [ ] **Step 5: Seite ansehen** – Expertenansicht ganz und mit dem CPU-Vorfall als Zeitraum, Reiter Sitzungen und Soll-Ist; auf überlappende Beschriftungen und Tabellenbreite prüfen; Mängel beheben, Step 4 wiederholen.

- [ ] **Step 6: Commit**

```bash
git add src/report-template.html tests/report-browser.js
git commit -m "Rebuild the expert view around one shared time range"
```

---

### Task 11: Übergänge, Tastatur, Adresse, schmale Breite, Farben

**Files:**
- Modify: `src/report-template.html`, `tests/report-browser.js`

**Interfaces:**
- Consumes: Tasks 8–10.
- Produces:
  - **Adresse:** Hash `#v=guided|expert&i=<id>&t0=<ms>&t1=<ms>` (fehlende Teile = Lagebild bzw. ganze Messung); `history.pushState` bei Wechsel der Ansicht, Öffnen und Schließen eines Vorfalls und abgeschlossenem Setzen des Zeitraums; `popstate` stellt den Zustand wieder her; beim Laden gilt der Hash vor der gemerkten Ansicht. Unbekannte Id oder unlesbarer Zeitraum: Lagebild bzw. ganze Messung.
  - **Gemerkte Ansicht:** `localStorage`-Schlüssel `wp-view:` + `location.pathname`, Zugriff in `try`/`catch`.
  - **Tastatur:** Umschalter, Knöpfe, Karten-Knöpfe, Einträge, Reiter und Begriffe sind mit Tab erreichbar; sichtbarer Fokus (`:focus-visible`); Esc schließt die Vorfallsansicht und den Kopierdialog; Pfeiltasten in `#xtabs` wie heute in der Reiterleiste.
  - **Bewegung:** Überblenden beim Wechsel der Ebenen, Gleiten von Diagrammen und Kacheln bei geändertem Zeitraum, gegenseitiges Hervorheben von Vorfall und Zeitfenster beim Überfahren, Bestätigung an Knöpfen; jede `transition`/`animation` höchstens 0,24 s; unter `@media (prefers-reduced-motion: reduce)` keine. Fadenkreuz in Diagrammen mit Uhrzeit, Wert und Status (Symbol und Wort).
  - **Schmale Breite:** bis 900 px eine Spalte; bei 400 px kein seitliches Scrollen der Seite; breite Tabellen scrollen in ihrem Rahmen.
  - **Farben der aufgeteilten Diagramme:** die acht Reihenfarben je Ansicht als Variablen `--s1` … `--s8`; die Prüfung rechnet für jede Ansicht je Paar den Farbabstand ΔE2000 bei normalem Sehen und nach Simulation von Protanopie, Deuteranopie und Tritanopie (Matrizen nach Machado 2009, Schwere 1,0) und verlangt mindestens 12 bzw. 6 sowie einen Kontrast jeder Farbe zum Diagrammgrund von mindestens 3:1. Die Funktionen dafür stehen in `tests/report-browser.js` (`deltaE2000`, `simulateCvd`, `contrast`); die Werte der Variablen passt die Vorlage an, bis die Prüfung besteht. Gelingt das mit acht Farben nicht, zeigen die aufgeteilten Diagramme weniger Reihen einzeln (heute sieben plus „Sonstige"); die Schwellen bleiben.

- [ ] **Step 1: Die fehlschlagenden Prüfungen schreiben**

```js
async function checkNavigation(browser, dir, scheme) {
  const file = path.join(dir, 'report.html');
  const { page, D } = await open(browser, file, scheme);
  const cpu = D.incidents.find((i) => i.lead === 'cpu');
  await page.click(`#cards .card.inc[data-id="${cpu.id}"] .card-open`);
  ok((await page.evaluate(() => location.hash)).includes('i=' + cpu.id), 'Adresse haelt den Vorfall');
  await page.click('#ivExpert');
  const h = await page.evaluate(() => location.hash);
  ok(h.includes('v=expert') && h.includes('t0=') && h.includes('t1='), 'Adresse haelt Ansicht und Zeitraum');
  await page.goBack(); ok(await page.evaluate(() => window.WP.view) === 'guided' && await page.locator('#incident').isVisible(), 'Zurueck-Taste fuehrt innerhalb des Berichts zurueck');
  await page.keyboard.press('Escape'); ok(!(await page.locator('#incident').isVisible()), 'Esc schliesst die Vorfallsansicht');
  const b = await browser.newPage({ colorScheme: scheme }); b.errors = []; b.on('pageerror', (e) => b.errors.push(e.message));
  await b.goto('file://' + file + h);
  ok(await b.evaluate(() => window.WP.view) === 'expert' && await b.evaluate(() => window.WP.zoom !== null), 'Lesezeichen oeffnet dieselbe Stelle');
  await b.goto('file://' + file + '#v=guided&i=99999&t0=abc'); await b.reload();
  ok(await b.locator('#band').isVisible() && !(await b.locator('#incident').isVisible()) && b.errors.length === 0, 'unbekannter Vorfall im Lesezeichen');          // Review Focus 2
  await b.close();
  await page.evaluate(() => { location.hash = ''; }); await page.reload();
  await page.keyboard.press('Tab'); await page.keyboard.press('Tab');
  ok(await page.evaluate(() => document.activeElement && getComputedStyle(document.activeElement).outlineStyle !== 'none'), 'sichtbarer Fokus');
  const durs = await page.evaluate(() => [...document.querySelectorAll('*')].flatMap((e) => getComputedStyle(e).transitionDuration.split(',').map(parseFloat)));
  ok(Math.max(...durs) <= 0.25, 'Bewegungen unter 250 ms');
  await page.close();
  const rm = await browser.newPage({ reducedMotion: 'reduce' }); await rm.goto('file://' + file);
  ok(await rm.evaluate(() => [...document.querySelectorAll('*')].every((e) => getComputedStyle(e).transitionDuration.split(',').every((d) => parseFloat(d) === 0))), 'keine Bewegung bei reduzierter Bewegung');
  await rm.close();
  const ls = await browser.newPage(); ls.errors = []; ls.on('pageerror', (e) => ls.errors.push(e.message));          // Review Focus 3
  await ls.addInitScript(() => { Object.defineProperty(window, 'localStorage', { get() { throw new Error('gesperrt'); } }); });
  await ls.goto('file://' + file);
  ok(await ls.locator('#guided').isVisible() && ls.errors.length === 0, 'ohne Speicher in der gefuehrten Ansicht');
  await ls.click('#viewSwitch button[data-view=expert]'); ok(await ls.locator('#expert').isVisible() && ls.errors.length === 0, 'Umschalten ohne Speicher');
  await ls.close();
  for (const view of ['guided', 'expert']) {
    const n = await browser.newPage({ viewport: { width: 400, height: 800 } }); await n.goto('file://' + file + '#v=' + view);
    ok(await n.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), 'schmale Breite ohne seitliches Scrollen: ' + view);
    await n.close();
  }
  const c = await browser.newPage(); await c.goto('file://' + file);
  for (const view of ['guided', 'expert']) {
    await c.evaluate((v) => window.WP.showView(v), view);
    const cols = await c.evaluate(() => [1, 2, 3, 4, 5, 6, 7, 8].map((k) => getComputedStyle(document.body).getPropertyValue('--s' + k).trim()));
    const bg = await c.evaluate(() => getComputedStyle(document.querySelector('.chart, .card')).backgroundColor);
    ok(paletteOk(cols, bg), 'Reihenfarben unterscheidbar, auch bei Farbfehlsichtigkeit: ' + view);
  }
  await c.close();
}
```

`paletteOk(cols, bg)` prüft die Schwellen aus den Interfaces mit `deltaE2000`, `simulateCvd` und `contrast`.

- [ ] **Step 2: Prüfung ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/New-TestReports.ps1 -OutDir /tmp/wp-reports && node tests/report-browser.js /tmp/wp-reports`
Expected: `AssertionError: Adresse haelt den Vorfall`

- [ ] **Step 3: Adresse, gemerkte Ansicht, Tastatur, Bewegung, schmale Breite und Farben umsetzen**

- [ ] **Step 4: Prüfungen ausführen**

Run: wie Step 2 und die Pester-Tests
Expected: `browser checks passed: <n>`, `Failed: 0`

- [ ] **Step 5: Seite ansehen** – beide Ansichten bei 400 px und 1400 px, die Vorfallsansicht mit Tastatur bedient; Mängel beheben, Step 4 wiederholen.

- [ ] **Step 6: Commit**

```bash
git add src/report-template.html tests/report-browser.js
git commit -m "Keep view, incident and range in the address and polish keyboard, motion and narrow layout"
```

---

### Task 12: README und Demo-Seite

**Files:**
- Modify: `README.md` (Abschnitte „Der Bericht", „Lesehilfe", „2. Auswerten", „Demo-Bericht"), `pages/index.html`

**Interfaces:**
- Consumes: der fertige Bericht.
- Produces: README beschreibt die geführte Ansicht (Lagebild mit Band und Kennzahlen, Karten, Vorfallsansicht mit ihren fünf Abschnitten, Kopieren mit und ohne Namen), die Expertenansicht (Vorfallsspalte, gemeinsamer Zeitraum, Kacheln, Diagramme, Reiter), die Adresse als Lesezeichen, den Katalog `src/guidance.de.json` mit `-GuidanceFile`, Bedingungen und Platzhaltern, die Herkunft der Druckempfehlungen (`docs/guidance/quellen.md`) und dass Empfehlungen Vorschläge sind, die die Messung stützen muss. Die Demo-Seite ist aus der Simulation neu erzeugt.

- [ ] **Step 1: Prüfen, dass die Demo veraltet ist**

Run: `pwsh -NoProfile -Command "(Select-String -Path pages/index.html -Pattern 'id=""viewSwitch""' -SimpleMatch -Quiet)"`
Expected: `False`

- [ ] **Step 2: README schreiben**

- [ ] **Step 3: Demo neu erzeugen**

```powershell
$run = .\src\Start-WorkerPerfCapture.ps1 -Simulate -DurationMinutes 60 -OutputPath .\demo
.\src\New-WorkerPerfReport.ps1 -Path $run -OutFile .\pages\index.html
```

- [ ] **Step 4: Prüfen**

Run: Step 1 erneut, danach `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"` und die Browserprüfungen
Expected: `True`, `Failed: 0`, `browser checks passed: <n>`

- [ ] **Step 5: Commit**

```bash
git add README.md pages/index.html
git commit -m "Describe the guided report and rebuild the demo page"
```

---

## Self-Review

- **Spec coverage:** 3.1 → Tasks 4, 8; 3.2 → Task 10; 3.3 → Tasks 9, 11; 3.4 → Tasks 8, 10 (Umstellung der Prüfungen); 4 → Task 9; 5.1–5.6 → Tasks 1–3, 6, 7; 5.7 → Tasks 1, 6; 5.8 → Task 6 (Haltepunkt); 6 → Tasks 5, 7, 9; 7 → Gestaltung, Tasks 8–11; 8 → Tasks 4 (viele Vorfälle, Lagebild), 8 (kein Vorfall, gemeldete Zeit), 9 (Rückblick), 10 (kurzer Zeitraum, viele Vorfälle auf der Seite), 7 (maskierter Bericht); 9 → File Structure; 10 → Tests der Tasks 1–11; 11 → Reihenfolge der Tasks.
- **Step scan:** Code-Schritte nennen Datei und Signatur; Tests enthalten die Werte der Spezifikation; die Gestaltung beschreibt Bereiche, Inhalte und Verhalten statt Code.
- **Type consistency:** `guide` (Task 3) wird in Tasks 4, 5, 7–9 mit denselben Feldern gelesen; `WP.setZoom/resetZoom/zoom/onZoom` bleiben die Schnittstelle des Zeitraums; `openIncident`, `showView`, `view` sind in Task 8/9 eingeführt und in 10/11 genutzt.
- **Review Focus:** fünf Zeilen, je ein Test in der genannten Task.
- **Proportion:** die Codeblöcke sind Tests; Funktionskörper fehlen; die Spezifikation hat 240 Zeilen.
