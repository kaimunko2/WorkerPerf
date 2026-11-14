# Größe des Servers – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Jeder CPU- und Arbeitsspeicher-Vorfall des normalen Berichts bekommt eine begründete Ursachenklasse, und ein eigener Größenbericht über mehrere Aufzeichnungen desselben Servers zeigt wiederkehrende Engpässe und eine als Schätzung gekennzeichnete Hochrechnung der Größe.

**Architecture:** Der Collector zeichnet fünf neue Grundwerte je Takt auf (stärkster logischer Prozessor, Zahl voller logischer Prozessoren, `% Processor Performance`, `% Processor Utility`, `Pages Output/sec`) und hält die Kern-Schwelle in `meta.json` fest. `src/WorkerPerf.Sizing.ps1` lädt und prüft den Katalog `src/sizing.de.json`, ordnet jeden Vorfall aus Fakten seines Fensters einer oder mehreren Klassen zu, rechnet über mehrere Aufzeichnungen (Hauptzeit, wiederkehrend, Hochrechnung) und bildet die Berichtsdaten des Größenberichts; der normale Bericht übernimmt nur die Einordnung, `src/New-WorkerPerfSizingReport.ps1` schreibt mit `src/sizing-template.html` eine eigene Seite. Lader, Befunde, Vorfälle und Kataloge bleiben, wie sie sind, und werden je Aufzeichnung mit denselben Funktionen aufgerufen.

**Tech Stack:** Windows PowerShell 5.1 (Laufzeit), HTML/CSS/JavaScript ohne Bibliotheken. Tests: PowerShell 7 mit Pester 5, Node.js mit Playwright.

**Spec:** `docs/superpowers/specs/2026-11-14-servergroesse-design.md` (bindend). Belege: `.superpowers/sdd/zustandsbild-prep/research-sizing.md` (SZ-01 bis SZ-47; dazu VM-08 und VM-10 aus `research-vmware.md`, ST-02 aus `research-stalhood.md`). Baut auf: der Linie des Zustandsbilds (`docs/superpowers/plans/2026-11-13-zustandsbild.md`, Zweig `wt/health-win`), **nachdem sie in den Entwicklungszweig zusammengeführt ist**: der Plan nimmt ihre Dateien an (`src/New-WorkerPerfReport.ps1` mit `New-ReportBefore`, `Add-ReportIncidentGuide`, `Add-ReportCopyTexts`, `Complete-Report`; `src/WorkerPerf.Health.ps1`; `Model.HealthState`; `Invoke-SimHealthOnly`) und die Seite des Entwicklungszweigs (`src/report-template.html` mit `renderIncident`, `incEntry`, `renderTiles`; `tests/report-browser.js` mit `PER_SCHEME`, `ONCE`, `--scheme`, `--only` und den Ausfuhren `contrast`, `paletteCheck`).

## Global Constraints

- **Windows PowerShell 5.1:** jede `src/*.ps1` beginnt mit `#Requires -Version 5.1`, ist reines ASCII (Umlaute nur in JSON-Dateien und HTML-Vorlagen), ohne PowerShell-7-Syntax und ohne API, die es nur unter .NET Core gibt. `tests/Compat.Tests.ps1` prüft neue Dateien unter `src/` automatisch.
- **Tests unter Linux:** PowerShell 7, Pester 5, Node/Playwright. Eine Datei: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/<Datei>`; alle: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`; mehrere: `pwsh -NoProfile -Command "& ./tests/Invoke-Tests.ps1 -Path tests/<A>, tests/<B>"`. Browser: `pwsh -NoProfile -File tests/New-TestReports.ps1 -OutDir <workspace>/scratch/wp-reports`, dann `node tests/report-browser.js <workspace>/scratch/wp-reports --scheme light` und `… --scheme dark` (bei der Zeitgrenze von zehn Minuten der helle Teil mit `--only PER_SCHEME` und `--only ONCE`); Erfolg: letzte Zeile `browser checks passed: <n>`, Rückgabewert 0.
- **Temporäre Pfade:** nur unter `<workspace>/scratch/` (`<workspace>` = Arbeitsordner der Ausführung unter `.superpowers/sdd/`), nie unter `/tmp`.
- **Listen:** Funktionen, die Listen liefern, geben schlichte Pipeline-Ausgabe; Aufrufer schreiben `@(...)`.
- **Wortregel:** in jedem Text für Benutzer heißt die gemessene Maschine „Server“, nie „Worker“ oder „Host“. „Host“ steht nur für den Hypervisor und dann als „VMware-Host“ (die Klasse 1 des Entwurfs heißt in Texten „VMware-Host“); `checkWording` in `tests/report-browser.js` gilt auch für die neue Seite.
- **Deutsche Texte in JSON:** Sätze, Bezeichnungen, Wörter der Statusmarken und Vorlagen der Hochrechnung stehen in `src/sizing.de.json` (bzw. `src/texts.de.json`, `src/guidance.de.json`), nicht im PowerShell-Code; die Seiten enthalten nur Beschriftungen ihrer Bedienelemente und Überschriften.
- **Ein Satz Schwellen (Entwurf 2, 5.2):** `cpu.host`, `cpu.queue`, `cpu.steal`, `mem.commit` kommen nur aus `thresholds.json`; `src/sizing.de.json` verweist auf sie und führt nur eigene Werte (Kern-Schwelle, Anteil des Hauptverursachers, Mindestmesszeit …). Der Lader lehnt eine Katalogschwelle ab, die eine Kennung aus `thresholds.json` trägt.
- **Jede Regel mit Quelle und Art:** jede Klasse, jede eigene Schwelle und jede Hochrechnung nennt ihre Art (`vendor` „Herstellerangabe“, `practice` „Praxisquelle“, `rule` „Faustregel des Katalogs“) und ihre Quellen als Kennungen (SZ-, VM-, ST-) mit Titel, Adresse und Datum aus der Recherche; jede Quelle steht mit Datum in `docs/guidance/quellen.md`.
- **Kennzeichnung (Entwurf 6.3):** jede Zahl der Hochrechnung trägt das Wort „Schätzung“ und die vier Annahmen (gleiche Last je Sitzung; Skalierung 1,5- bis 1,9-fach je Verdopplung; der VMware-Host liefert die zusätzliche Rechenzeit; Hyper-Threading nicht eingerechnet) und den Satz „Vor einem Umbau mit einem Pilot oder Lasttest bestätigen.“ Keine feste Zielgröße als Vorgabe, keine lineare Hochrechnung nach oben (nur die Sitzungszahl bei gleicher Größe wird linear nach unten gerechnet).
- **Zielumgebung:** eine Richtung, die eine Einstellung ändert (Energiesparplan, Auslagerungsdatei), nennt den Ort nach der Regel „Zielumgebung“ in `docs/guidance/quellen.md` (Master-Image bzw. Richtlinie).
- **Maskierung:** jedes Textfeld, das eine Task Berichtsdaten hinzufügt, steht in derselben Task im Bestand (`tests/MaskCensus.json` für den normalen Bericht, `tests/SizingMaskCensus.json` für den Größenbericht) und, wo es ein Schlüsselwort ist, in `$script:WorkerPerfMaskKeywordFields`. Der Größenbericht wird mit `-Mask` wie der normale Bericht maskiert.
- **Öffentliches Repository:** Tests, Beispiele und Simulation verwenden nur erfundene Namen (`SIM-VDA01`, `user001` …, `simcalc.exe`); keine Daten eines echten Servers werden eingecheckt.
- **Der Collector liest nur;** die neuen Zähler werden nur gelesen.
- **Bestand:** alle bestehenden Tests bleiben grün, außer eine Task nennt genau, welche Aussage sich ändert und warum.
- **TDD:** jede Task schreibt zuerst den fehlschlagenden Test.
- **Commits:** englisch, im Imperativ, ein Commit je Task. Jede Commit-Nachricht endet mit den zwei Zeilen
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` und `Claude-Session: https://claude.ai/code/session_01TebhPvsTuNpmYXDmJ3hXkB`; sonst steht nirgends ein Modellname (Code, Kommentare, Dokumente, Katalog).

## Review Focus

Jede Zeile ist durch einen Test in der genannten Task abgesichert (im Testcode mit `# Review Focus n` bzw. `// Review Focus n` markiert).

1. **Ein Server, dessen Zähler anders heißen oder fehlen:** `% Processor Utility` oder `Pages Output/sec` gibt es nicht, oder die Instanzen von „Processor Information“ heißen `0,_Total` und `_Total` nebeneinander. Erwartet: `cpu.host` wird weiter gemessen, eine Gesamtinstanz zählt nie als Kern, die fehlenden Werte stehen in `Sources` als nicht verfügbar mit Grund, und die Einordnung sagt, welche Unterscheidung ohne sie nicht möglich ist. → Tasks 2, 5
2. **Gemischte Aufzeichnungen:** eine ältere Aufzeichnung ohne die neuen Spalten neben neuen, und eine Größe, die zwischen den Tagen wechselt (8 → 10 vCPU). Erwartet: der Größenbericht entsteht, die alte Aufzeichnung zählt für Last und Klassen, soweit ihre Werte reichen, der Kopf nennt den Wechsel, die Hochrechnung geht von der letzten Aufzeichnung aus. → Tasks 3, 8, 9
3. **Die Liste der Aufzeichnungen ist ungewöhnlich:** dieselbe Aufzeichnung zweimal, nur Schnellläufe, Pfade in beliebiger Reihenfolge, derselbe Servername in anderer Schreibweise. Erwartet: doppelt → klare Ablehnung; nur Schnellläufe → Ablehnung „keine Messung“; Reihenfolge nach Beginn; `SIM-VDA01` und `sim-vda01` sind derselbe Server. → Tasks 8, 9
4. **Eine Aufzeichnung ohne Sitzungen** (Server über Nacht leer, Spitze 0 Sitzungen) oder ganz ohne Hauptzeit. Erwartet: sie trägt keine Hauptzeit bei, die anderen bestimmen L; gibt es gar keine Hauptzeit, steht keine Spanne, sondern der Satz, dass ohne Hauptzeit nicht hochgerechnet wird. → Task 8
5. **Grenzwerte der Hochrechnung:** L knapp über T (75,1 %), ungerade vCPU-Zahl (7), untere und obere Grenze gleich. Erwartet: aufgerundet auf eine gerade Zahl (7 vCPU, L 75,1 → 8), eine Spanne aus einer Zahl wird als eine Zahl gezeigt („etwa 8 statt 7 vCPU“), nie „8 bis 8“. → Tasks 8, 10

## File Structure

| Datei | Verantwortung |
|---|---|
| `src/sizing.de.json` (neu) | Katalog: Quellen, eigene Schwellen mit Art und Quelle, Verweise auf `thresholds.json`, zehn Klassen, Stufen, Statusmarken, Nutzerklassen, Signale, Texte und Vorlagen |
| `src/WorkerPerf.Sizing.ps1` (neu) | Katalog laden und prüfen; Auswertung je Aufzeichnung (`Get-WorkerPerfRunAnalysis`); Fakten und Klassen je Vorfall; Hauptzeit, Kennzahlen je Aufzeichnung, Prüfung „derselbe Server“, Achse, wiederkehrend, Hochrechnung, Empfehlungen; Berichtsdaten und Kopiertext des Größenberichts |
| `src/WorkerPerf.Page.ps1` (neu) | JSON-Schreiber und Schreiben einer Seite über eine temporäre Datei (aus `src/New-WorkerPerfReport.ps1` herausgelöst, von beiden Berichtsskripten genutzt) |
| `src/New-WorkerPerfSizingReport.ps1` (neu) | Größenbericht: Parameter, Prüfungen vorab, Auswertung je Aufzeichnung, Maskierung, Schreiben |
| `src/sizing-template.html` (neu) | Seite des Größenberichts |
| `src/WorkerPerf.Common.ps1` | Kopfzeile von `ticks.csv` mit fünf optionalen Spalten, neue Signale, Rollenname `Wartung` |
| `src/WorkerPerf.Capture.ps1` | Zeile des Takts mit den fünf Werten |
| `src/Start-WorkerPerfCapture.ps1` | Kern-Schwelle aus dem Katalog, `meta.json` `CoreBusyPct`, `-SimulateScenario`, `-SimulateDay` |
| `src/WorkerPerf.Sources.Windows.ps1` | optionale Zähler, Kern-Kennzahlen, neue Quellen in `Sources` |
| `src/WorkerPerf.Sources.Simulation.ps1` | die fünf Werte, Drehbücher `Ursachen` und `Tag`, Soll-Klassen |
| `src/WorkerPerf.Load.ps1` | optionale Spalten, neue Signale, `Meta.CoreBusyPct`, `Model.Measured` |
| `src/WorkerPerf.Guidance.ps1`, `src/guidance.de.json` | Bedingungen `class.host`, `class.singlecore`, je ein Schritt dazu, Zeile „Einordnung“ im Kopiertext |
| `src/New-WorkerPerfReport.ps1` | `-SizingFile`, Einordnung je Vorfall, neue Reihen, Teil `sizing` der Berichtsdaten |
| `src/report-template.html` | Zeile „Einordnung“ in der Vorfallsansicht und in der Vorfallsspalte, drei Kacheln |
| `src/WorkerPerf.Mask.ps1` | Namen mehrerer Aufzeichnungen in einer Maske, neue Schlüsselwortfelder |
| `src/Test-WorkerPerfSources.ps1` | neue Zähler im Prüflauf |
| `src/roles.json`, `src/texts.de.json` | Rolle `Wartung`; Bezeichnungen der neuen Quellen |
| `docs/guidance/quellen.md` | Abschnitt „Größe des Servers“ mit allen Quellen des Katalogs |
| `tests/Sizing.Tests.ps1`, `tests/SizingReport.Tests.ps1`, `tests/SizingMaskCensus.json` (neu) | Katalog, Einordnung, Hochrechnung; Skript; Bestand der Felder |
| bestehende Tests, `tests/TestHelpers.ps1`, `tests/WindowsStandIns.ps1`, `tests/report-browser.js`, `tests/MaskCensus.json` | angepasst bzw. ergänzt |
| `README.md`, `pages/index.html`, `pages/groesse.html` (neu) | Beschreibung, Demo |

## Reihenfolge und Parallelität

Task 1 zuerst (Katalog, den alle späteren lesen). Danach in Reihe 2 → 3 → 4 → 5. Task 6 und Task 8 brauchen Task 5 und können nebeneinander laufen; Task 7 nach 6; Task 9 nach 6 und 8; Task 10 nach 9. Task 11 (Prüfskript) braucht nur Task 2 und darf jederzeit danach laufen; sie teilt `src/texts.de.json` mit Task 2 (neue Zeilen am Ende). Task 12 nach allen; Task 13 ist der Schritt des Auftraggebers.

## Entscheidungen, die dieser Plan trifft

Wo der Entwurf etwas offenlässt oder dem Code widerspricht, entscheidet der Plan; jede Entscheidung mit dem, was es kostet, wenn sie falsch ist.

- **Format bleibt 3, fünf optionale Spalten am Ende von `ticks.csv`** (`CoreMaxPct,CoresBusy,PerfPct,UtilityPct,PagesOutPerSec`). Der Lader verlangt nur die Pflichtspalten davor; fehlt einer Zeile oder der Datei eine optionale Spalte, ist der Wert leer. So lesen auch ältere WorkerPerf-Fassungen neue Aufzeichnungen weiter. *Wenn falsch:* Formatnummer 4 und eine Zeile im Lader.
- **Optionale Zähler je Gruppe:** die neuen Zähler stehen als `Optional` an den Gruppen `cpu` und `memory`; fehlt einer, bleibt die Gruppe (und `cpu.host`) verfügbar, nur das neue Signal steht in `Sources` als nicht verfügbar. Die Kern-Kennzahlen kommen aus den Instanzen von `% Processor Time`, die schon gelesen werden; eine Instanz mit dem Bestandteil `_Total` ist eine Gesamtinstanz (Entwurf 4.1). *Wenn falsch:* der erste echte Lauf (Task 13) zeigt andere Namen; die Erkennung ist eine Funktion.
- **Die Kern-Schwelle liest der Collector aus `src/sizing.de.json`** (`thresholds.coreBusyPct`, über den vollen Lader) und schreibt sie als `CoreBusyPct` in `meta.json`; die Einordnung vergleicht Prozesse und `cpu.coreMax` mit dem Wert des Katalogs zur Zeit der Auswertung, die Kachel „Kerne voll“ nennt den aufgezeichneten Wert. *Wenn falsch:* ein Wert mehr im Kopf der Seite.
- **Mehrere Klassen:** Klasse 1 (VMware-Host) steht neben jeder anderen (Entwurf 5.1, Schlussabsatz „Host und Kapazität“, „Host zuerst, weil er jede andere Empfehlung entwertet“); „Kapazität“ heißt daher „keine der Klassen 2 bis 4, breite Last über dem Ziel“, und das „der Host entzieht keine Rechenzeit“ ihrer Beschreibung wird über die Reihenfolge in 6.3 abgedeckt (Host wiederkehrend → keine Spanne). „Anwendung“ schließt neben „Leistung je Kern“ auch „Einmalig“ aus (ein Virenscan ist kein „Anwendung klären“). „Arbeitsspeicher: Kapazität“ schließt „Arbeitsspeicher: Anwendung“ aus (breit verteilte Last). *Wenn falsch:* eine Bedingung in `Get-WorkerPerfIncidentClasses` und ihre Tests.
- **Hauptverursacher für die Einordnung:** für „Leistung je Kern“ der einzelne Prozess mit der meisten CPU-Zeit im Fenster (ohne den Collector), für „Anwendung“ und „Einmalig“ die größte Anwendung in einer Sitzung aus `Group-WorkerPerfShareTable -By 'app-in-session'`; so gilt beides auch für Vorfälle ohne Engpass, die keine Rangliste haben. *Wenn falsch:* eine Auswahl in `Get-WorkerPerfIncidentFacts`.
- **„Anhaltend“ und „während des Vorfalls“:** ein Wert über einer Schwelle zählt, wenn er in mindestens `minTicks` Takten des Fensters darüber liegt (`minTicks` des Signals aus `thresholds.json`, heute 3); die Prozess- und Kernmuster gelten bei mindestens `sustainedPct` = 80 % der Schnappschüsse bzw. Takte; ausgelagerte Seiten gelten als anhaltend bei mehr als `pagesOutSharePct` = 50 % der Takte über `pagesOutLowPerSec` = 10 je s (SZ-35 „low or zero most of the time“). Alle drei sind Faustregeln des Katalogs. *Wenn falsch:* Werte im Katalog.
- **„Einmalig“ braucht eine Rolle:** `roles.json` kennt Scanner (Rolle `Sicherheit`), aber keine Updates oder Bereitstellungen (Widerspruch zum Entwurf 5.1, „die Rollenliste kennt diese Prozesse schon“). Der Plan legt die Rolle `Wartung` an (Eintrag „Windows Update“: `TiWorker.exe`, `TrustedInstaller.exe`, `MoUsoCoreWorker.exe`, Vermerk „ungeprüft“). „Einmalig“ heißt: Rolle `Wartung`, oder Rolle `Sicherheit` und ein Scan überlappt das Fenster (`Model.Scans`). *Wenn falsch:* ein Eintrag der Rollenliste.
- **Kapazität verlangt Last über dem Ziel:** ein CPU-Vorfall nur aus der Warteschlange bei niedriger CPU (SZ-18: dann kein CPU-Mangel) bekommt keine Klasse. *Wenn falsch:* eine Bedingung.
- **L gleich T gilt als „Größe reicht“:** der Entwurf sagt „L liegt unter T“; bei L = T ergäbe die Formel genau die heutige Größe. *Wenn falsch:* `-le` statt `-lt` und ein Test.
- **„Spitzenlast“ im Ergebnissatz ist L** (P95 der Hauptzeit, „typische Spitzenlast“, Entwurf 1.2) mit der höchsten Sitzungszahl aller Aufzeichnungen; die Spitze steht in den Kennzahlen daneben. Der Satz sagt „in 4 von 5 Aufzeichnungen“, nicht „an Tagen“: eine Aufzeichnung muss kein Tag sein. *Wenn falsch:* eine Vorlage im Katalog.
- **„Wiederkehrend“** zählt Aufzeichnungen mit Messung, in denen die Klasse an mindestens einem Vorfall steht; wiederkehrend bei Anteil ≥ `recurringPct` = 50 %. Ein Schnelllauf zählt nie mit.
- **„Derselbe Server“** vergleicht `meta.json` `Computer` ohne Rücksicht auf die Schreibweise (Windows-Namen sind es auch), in einer einzigen Funktion `Assert-WorkerPerfSameServer`.
- **Die Parameter `-GuidanceFile` und `-AppsFile` des Größenberichts** werden vorab geprüft wie im normalen Bericht und in den Befehl je Aufzeichnung übernommen, damit dieser Befehl denselben Bericht erzeugt; der Größenbericht selbst zeigt keine Anleitung.
- **Der Schritt einer Klasse mit eigener Richtung** steht in `src/guidance.de.json` als Prüfschritt mit der Bedingung `class.host` bzw. `class.singlecore` am Anfang von `checks` der Situationen `cpu`, `delay.many`, `delay.single`; über die Regel P3-R75 (`Get-WorkerPerfGuidanceItems`) steht er in der ersten Gruppe, dort durch seinen Platz in der Datei vorne. Die Richtung der Klasse selbst steht im Katalog der Größe. *Wenn falsch:* Elemente im Katalog der Anleitung.
- **JSON-Schreiber herausgelöst:** `Format-JsonString`, `Format-JsonNumber`, `ConvertTo-JsonText` ziehen nach `src/WorkerPerf.Page.ps1`; der normale Bericht bleibt bytegleich (der bestehende Test „bleibt ohne -Mask bytegleich“ sichert es).
- **Statusmarken des Größenberichts:** `◆ Handeln` (eine Empfehlung mit Änderung: Spanne, mehr RAM, VMware-Host klären), `▲ Prüfen` (Ursache klären, Auslagerungsdatei, wenig Messzeit hebt nichts an), `● In Ordnung` (Größe reicht). Die Seite folgt wie der Bericht nicht dem Farbschema des Systems.

## Teil A – Messwerte und Einordnung (Tasks 1–7)

### Task 1: Katalog `src/sizing.de.json` und sein Lader

**Files:**
- Create: `src/sizing.de.json`, `src/WorkerPerf.Sizing.ps1`, `tests/Sizing.Tests.ps1`
- Modify: `docs/guidance/quellen.md` (neuer Abschnitt „Größe des Servers“ am Ende)

**Interfaces:**
- Consumes: `Read-WorkerPerfThresholds` (Hashtable Kennung → Schwelle mit `warn`, `crit`, `minTicks`, `unit`, `label`).
- Produces:
  - `$script:WorkerPerfSizingClassOrder = @('host','singlecore','app','oneoff','capacity','mem.capacity','mem.commit','mem.app','mem.used','undecidable')` (Vorrang, Entwurf 5.1).
  - `$script:WorkerPerfSizingPlaceholders` (Klasse → erlaubte Platzhalter ihrer Texte): `host` `steal`, `stealWarn`; `singlecore` `app`, `cores`, `coreMax`, `coreBusyPct`, `cpu`, `cpuCrit`; `app` `app`, `share`, `appSharePct`; `oneoff` `app`, `role`; `capacity` `cpu`, `queue`, `target`, `cpuCrit`, `queueWarn`; `mem.capacity` `commitGB`, `ramGB`, `pagesOut`; `mem.commit` `commit`, `commitCrit`, `pagesOut`; `mem.app` `app`, `share`, `growthGB`; `mem.used` `used`; `undecidable` `missing`.
  - `Read-WorkerPerfSizing([string]$Path, $Thresholds) -> catalogue` mit:
    `Version` (Text `YYYY-MM-DD`);
    `Sources` (geordnet, Kennung → `@{ Title; Url; Date; Kind }`, Kind `vendor`|`practice`);
    `Thresholds` (Name → `@{ Value; Default; Unit; Label; Kind; Sources = [string[]] }`);
    `Limits` (Name → `@{ Value; Signal; Level; Label }`, aufgelöst aus `thresholds.json`: `target` = `cpu.host`.`warn`, `cpuCrit` = `cpu.host`.`crit`, `queueWarn` = `cpu.queue`.`warn`, `stealWarn` = `cpu.steal`.`warn`, `commitCrit` = `mem.commit`.`crit`);
    `Classes` (geordnet nach `$WorkerPerfSizingClassOrder`, Kennung → `@{ Id; Resource ('cpu'|'memory'|'any'); Label; Reason; Direction; Kind; Sources }`);
    `Levels` (`clear` „deutlich“, `tight` „knapp“); `Grades` (`act`, `check`, `ok` je `@{ Word; Symbol }`); `Users` (`light`, `medium`, `heavy`, `power` je `@{ Label; PerVcpu }`); `Signals` (die fünf neuen Signalkennungen je `@{ Label; Note; Sources }`); `Missing` (Messung → Bezeichnung: `cpu.coreMax` „stärkster logischer Prozessor“, `cpu.steal` „entzogene CPU-Zeit (VMware Tools)“, `mem.pagesout` „ausgelagerte Seiten“, `processes` „Prozessdaten“); `Evidence` (Wertkennung des Zustandsbilds → Bezeichnung); `Texts` (Schlüssel → Vorlage, Liste in Step 3).
  - Fehlermeldung des Laders: `Katalog '<Pfad>': <Teil> <Kennung>: <Feld> <Grund>.`

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/Sizing.Tests.ps1`, Teil „Katalog“; `BeforeAll` lädt `WorkerPerf.Common.ps1`, `WorkerPerf.Sizing.ps1`, `$Th = Read-WorkerPerfThresholds src/thresholds.json`; `New-BadCatalogue([scriptblock]$Change)` liest den Katalog nach `$j` (JSON-Objekt), führt `$Change` im selben Bereich aus und schreibt die geänderte Kopie nach `$TestDrive`; liefert ihren Pfad)

```powershell
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
        $t.sustainedPct.Value | Should -Be 80; $t.pagesOutLowPerSec.Value | Should -Be 10; $t.pagesOutSharePct.Value | Should -Be 50
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
        @{ Name = 'Kern-Schwelle ausserhalb 50 bis 100'; Change = { $j.thresholds.coreBusyPct.value = 40 }; Message = '*thresholds coreBusyPct: value*' }
        @{ Name = 'Verweis auf ein Signal, das thresholds.json nicht kennt'; Change = { $j.limits.target.signal = 'cpu.unbekannt' }; Message = '*limits target: signal*' }
    ) { { Read-WorkerPerfSizing (New-BadCatalogue $Change) $Th } | Should -Throw $Message }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Sizing.Tests.ps1`
Expected: FAIL, `Read-WorkerPerfSizing` ist nicht definiert

- [ ] **Step 3: `src/sizing.de.json` schreiben**

Teile: `version` (`2026-11-14`), `sources`, `thresholds`, `limits` (`{ signal, level, label }`), `classes` (Liste `{ id, resource, label, reason, direction, kind, sources }`), `levels`, `grades` (`act` „Handeln“ `◆`, `check` „Prüfen“ `▲`, `ok` „In Ordnung“ `●`), `users`, `signals`, `missing`, `evidence` (`operation.powerPlan` „Energiesparplan“, `size.cpuLogical` „Logische Prozessoren“, `size.memTotalMB` „Arbeitsspeicher (MB)“, `size.hypervisor` „Virtuelle Maschine“, `size.vmtoolsVersion` „VMware Tools“), `texts`.

Quellen (Titel wie auf der Seite, Adresse, Datum aus `research-sizing.md` „Pages opened“ bzw. den älteren Recherchen):

| Kennung | Titel | Adresse | Datum | Art |
|---|---|---|---|---|
| SZ-01 | CPU usage exceeds 100% in Task Manager and Performance Monitor if Intel Turbo Boost is active | https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/cpu-usage-exceeds-100 | 2026-02-12 | vendor |
| SZ-03 | Power and performance tuning | https://learn.microsoft.com/en-us/windows-server/administration/performance-tuning/hardware/power/power-performance-tuning | 2017-10-16 | vendor |
| SZ-07 | Windows Guest OS reports incorrect CPU clock speed after vMotion | https://knowledge.broadcom.com/external/article/429912 | 2026-02-18 | vendor |
| SZ-13 | Collecting Performance Data | https://learn.microsoft.com/en-us/windows/win32/perfctrs/collecting-performance-data | 2025-07-14 | vendor |
| SZ-14, SZ-38 | Scenario guide: Troubleshoot performance problems in Windows | https://learn.microsoft.com/en-us/troubleshoot/windows-server/performance/troubleshoot-performance-problems-in-windows | 2026-02-12 | vendor |
| SZ-15 | Solutions for Consistently High CPU Usage | https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/vsphere-monitoring-and-performance/monitoring-inventory-objects/troubleshoot-and-enhance-performance/cpu-performance-solutions.html | 2026-10-28 | vendor |
| SZ-16, SZ-18 | System-Level Bottlenecks | https://learn.microsoft.com/en-us/biztalk/technical-guides/system-level-bottlenecks | 2017-06-29 | vendor |
| SZ-20, SZ-21, SZ-22, VM-08, VM-10 | Rightsizing virtual machines on ESXi 8.0: vCPU, memory, and CPU topology guidance | https://knowledge.broadcom.com/external/article/438023 | 2026-09-14 | vendor |
| SZ-23 | Hyperthreading with vSphere | https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/vsphere-resource-management/hyperthreading.html | 2026-10-28 | vendor |
| SZ-24 | Host Power Management Policies in ESXi | https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/vsphere-resource-management/host-power-management-policies.html | 2026-10-28 | vendor |
| SZ-25 | Application on Virtual Machine runs slower than expected | https://knowledge.broadcom.com/external/article?legacyId=1018206 | 2025-07-27 | vendor |
| SZ-26 | ESXi host CPU usage appears high in vCenter default charts due to Turbo Boost and Hyperthreading counter behavior | https://knowledge.broadcom.com/external/article/431027 | 2026-10-30 | vendor |
| SZ-35 | RAM, virtual memory, pagefile, and memory management in Windows | https://learn.microsoft.com/en-us/troubleshoot/windows-server/performance/ram-virtual-memory-pagefile-management | 2026-02-12 | vendor |
| SZ-36 | Introduction to page files | https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/introduction-to-the-page-file | 2026-02-12 | vendor |
| SZ-39 | Performance Tuning Remote Desktop Session Hosts | https://learn.microsoft.com/en-us/windows-server/administration/performance-tuning/role/remote-desktop/session-hosts | 2019-10-22 | vendor |
| SZ-42, SZ-43, SZ-44, SZ-46 | Session host virtual machine sizing guidelines for Azure Virtual Desktop and Remote Desktop Services | https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/session-host-virtual-machine-sizing-guidelines | 2025-07-23 | vendor |
| SZ-45 | Troubleshoot issues using Performance Monitor | https://learn.microsoft.com/en-us/troubleshoot/windows-server/support-tools/troubleshoot-issues-performance-monitor | 2026-02-12 | vendor |
| SZ-47 | Detecting bottlenecks in a virtualized environment | https://learn.microsoft.com/en-us/windows-server/administration/performance-tuning/role/hyper-v-server/detecting-virtualized-environment-bottlenecks | 2017-10-16 | vendor |
| ST-02 | Citrix Health Check (Carl Stalhood) | https://www.carlstalhood.com/citrix-health-check/ | 2024-02-28 | practice |

Jede Kennung ist ein eigener Eintrag (mehrere Kennungen einer Zeile teilen Titel, Adresse, Datum).

Klassen (Art, Quellen; Texte frei innerhalb der Platzhalter, Richtung nach Entwurf 5.1):
`host` vendor SZ-21, SZ-20, SZ-26, VM-08 – Richtung „VMware-Host prüfen lassen (CPU Ready, Co-Stop, Auslastung des VMware-Hosts); keine zusätzlichen vCPU, eher weniger, wenn Co-Stop hoch ist“;
`singlecore` vendor SZ-13, SZ-14, SZ-15, SZ-16, SZ-03, SZ-24 – „schnellere Kerne; Energiesparplan im Master-Image und Energierichtlinie des VMware-Hosts prüfen; Hersteller der Anwendung fragen; mehr vCPU helfen dieser Anwendung nicht“;
`app` rule – „Anwendung, Aufgabe oder Benutzer klären; keine Größenänderung“; `oneoff` rule – „Zeitplan ändern; keine Größenänderung“;
`capacity` vendor SZ-18, SZ-47, VM-08 – „mehr vCPU oder mehr Server (Hochrechnung im Größenbericht)“;
`mem.capacity` vendor SZ-35, SZ-38, SZ-39 – „mehr Arbeitsspeicher oder weniger Sitzungen je Server“; `mem.commit` vendor SZ-36 – „Auslagerungsdatei vergrößern oder vom System verwalten lassen (im Master-Image); mehr Arbeitsspeicher ist dafür nicht nötig“; `mem.app` rule – „Anwendung klären, Verdacht auf Speicherleck“; `mem.used` vendor SZ-35 – „nichts nötig: Windows nutzt freien Speicher, ein Mangel zeigt sich erst am Auslagern“; `undecidable` rule – Grund nennt `{missing}`.

Eigene Schwellen (`kind`, `sources`): `coreBusyPct` 90 % rule [SZ-47]; `sustainedPct` 80 % rule; `singleCoreMaxCores` 1.2 Prozessoren rule [SZ-14]; `appSharePct` 50 % rule; `leakGrowthPct` 10 % des RAM rule; `pagesOutLowPerSec` 10 je s rule [SZ-35]; `pagesOutSharePct` 50 % rule [SZ-35]; `recurringPct` 50 % rule; `minRecordings` 3 rule; `minMainHours` 12 h rule; `mainSessionPct` 50 % rule; `scalingLow` 1.5 vendor [SZ-42]; `scalingHigh` 1.9 vendor [SZ-42]; `vcpuScaleOut` 16 vendor [SZ-43]; `vcpuMax` 24 vendor [SZ-43]; `memTargetPct` 80 % rule; `memStepGB` 4 GB rule.

`signals`: `cpu.coreMax` „Stärkster Kern“, `cpu.coreBusy` „Kerne voll“, `cpu.perf` „Leistungsanteil“ (Note: „Anzeige ohne Bewertung: ob der Wert in einer VMware-VM etwas bedeutet, belegt keine Herstellerseite; der im Server angezeigte Takt ist nach vMotion veraltet“, Quellen SZ-01, SZ-07), `cpu.utility` „Geleistete Arbeit“ (dieselbe Note), `mem.pagesout` „Ausgelagerte Seiten“.

`texts` (Schlüssel, die Tasks 5, 8 und 9 benutzen; feste Wortlaute aus dem Entwurf in Anführungszeichen): `line` („Einordnung: {labels}“ und ein Satz Begründung), `unchecked` („Nicht unterscheidbar: {label} (fehlt: {missing})“), `contradiction` („Nicht unterscheidbar: {label} (die Messwerte widersprechen sich)“), `result.recurring` („Wiederkehrender {resource} aus {class} in {count} von {total} Aufzeichnungen; typische Spitzenlast {load} % bei {sessions} Sitzungen.“), `result.once`, `result.none`, `resource.cpu` „CPU-Engpass“, `resource.memory` „Arbeitsspeicher-Engpass“, `cpu.host` („Erst den VMware-Host klären; mehr vCPU verschärfen das.“), `cpu.enough` („Die Größe reicht für die gemessene Last.“), `cpu.range` („Schätzung, nicht gemessen: Bei der gemessenen Last käme der Server mit etwa {low} bis {high} statt {cores} vCPU unter {target} %.“), `cpu.rangeOne` (dieselbe Aussage mit „etwa {low} statt {cores} vCPU“), `cpu.scaleOut` („Schätzung, nicht gemessen: Bei gleicher Größe trägt der Server etwa {sessions} Sitzungen unter {target} %; mehr Server statt größerer Server.“), `cpu.other` („Last über dem Ziel, aber nicht aus breiter Last; erst {cause} klären.“), `cpu.otherNone` (Last über dem Ziel ohne wiederkehrende Ursache; erst die einzelnen Engpässe klären), `cpu.noMainTime` (keine Hauptzeit, keine Hochrechnung), `mem.more` („Schätzung, nicht gemessen: …“ mit `{target}`, `{ram}`, `{commit}`, `{pct}`), `mem.pagefile`, `mem.app`, `mem.enough`, `hint.hostOnce`, `hint.singlecoreToo`, `hint.scaleOutToo` (mehr Server statt größerer Server, SZ-43), `hint.numa` (nicht mehr vCPU als der VMware-Host physische Kerne; in einen NUMA-Knoten passen; Kernzahl im Server nicht sichtbar, SZ-22), `hint.hostCheck` (CPU Ready je vCPU über 5 % Warnung, über 10 % handeln; Co-Stop anhaltend über 0 % prüfen (KB 431027), über 3 % je vCPU zu viele vCPU (KB 438023); Auslastung des VMware-Hosts anhaltend über 70–80 %), `hint.sizeChanged`, `hint.lowMeasure` („wenig Messzeit“ …), `hint.commitAboveRam` (ST-02 als Praxisregel neben Microsoft), `hint.memPerSession` (SZ-39), `hint.powerPlan` (Energiesparplan laut Zustandsbild: `{value}`), `assumptions` (Liste der vier Annahmen), `pilot` („Vor einem Umbau mit einem Pilot oder Lasttest bestätigen.“), `reliability` (`{runs}`, `{hours}`, `{main}`), `usersNote` („Einordnung, keine Bewertung: die Art der Nutzer ist nicht bekannt.“), `copy.head`, `copy.recommendation`.

- [ ] **Step 4: `Read-WorkerPerfSizing` in `src/WorkerPerf.Sizing.ps1` umsetzen** – liest mit `ConvertFrom-WorkerPerfJsonFile`, prüft jeden Teil, unbekannte Mitglieder werden abgelehnt (wie `Read-WorkerPerfHealthCatalogue`); jede Liste ist ein Array; Grenzen: `coreBusyPct` 50–100, Anteile 0–100, `scalingLow` < `scalingHigh` (beide > 1 und < 2), `vcpuScaleOut` < `vcpuMax`; `vendor`/`practice` verlangen mindestens eine Quelle, jede Quelle eine Adresse `https://` und ein Datum `YYYY-MM-DD`; Platzhalter `{name}` nur aus `$WorkerPerfSizingPlaceholders` bzw. der Liste der Vorlage.

- [ ] **Step 5: `docs/guidance/quellen.md` ergänzen** – Abschnitt „Größe des Servers (`src/sizing.de.json`)“: je Kennung Titel, Adresse, Datum, Art, wofür sie im Katalog steht; die Faustregeln des Katalogs mit ihrem Wert; die zwei aufgelösten Widersprüche aus Entwurf 5.1 (Commit über RAM: ST-02 gegen SZ-35; Co-Stop: KB 431027 gegen KB 438023).

- [ ] **Step 6: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Sizing.Tests.ps1`, danach `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Compat.Tests.ps1`
Expected: `Failed: 0` in beiden

- [ ] **Step 7: Commit**

```bash
git add src/sizing.de.json src/WorkerPerf.Sizing.ps1 tests/Sizing.Tests.ps1 docs/guidance/quellen.md
git commit -m "Add the sizing catalogue with its sources and a loader that checks it" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TebhPvsTuNpmYXDmJ3hXkB"
```

---

### Task 2: Neue Messwerte aufzeichnen (Format, Collector, Windows-Quelle)

**Files:**
- Modify: `src/WorkerPerf.Common.ps1` (Kopfzeile `ticks.csv`, `$script:WorkerPerfTickOptionalColumns`, `$script:WorkerPerfSizingSignalIds`, `Get-WorkerPerfHostSignals`), `src/WorkerPerf.Capture.ps1` (`ConvertTo-WorkerPerfFastRows`), `src/Start-WorkerPerfCapture.ps1`, `src/WorkerPerf.Sources.Windows.ps1`, `src/WorkerPerf.Sources.Simulation.ps1` (nur der Parameter `-CoreBusyPct` und die fünf Felder als `$null`), `src/texts.de.json`
- Test: `tests/Common.Tests.ps1`, `tests/Capture.Tests.ps1`, `tests/WindowsSource.Tests.ps1`, `tests/Collector.Tests.ps1`, `tests/WindowsStandIns.ps1`

**Interfaces:**
- Consumes: Task 1 `Read-WorkerPerfSizing`.
- Produces:
  - Kopfzeile `ticks.csv`: `T,Timestamp,ElapsedSec,CpuPct,ProcQueue,StealPct,MemAvailMB,MemCommittedMB,MemCommitLimitMB,PagesInPerSec,DiskReadBps,DiskWriteBps,DiskReadIops,DiskWriteIops,DiskQueue,NetRecvBps,NetSentBps,Burst,CollectMs,CoreMaxPct,CoresBusy,PerfPct,UtilityPct,PagesOutPerSec`; `$script:WorkerPerfTickOptionalColumns = @('CoreMaxPct','CoresBusy','PerfPct','UtilityPct','PagesOutPerSec')` (immer am Ende); `$script:WorkerPerfFormatVersion` bleibt 3.
  - `$script:WorkerPerfSizingSignalIds = @('cpu.coreMax','cpu.coreBusy','cpu.perf','cpu.utility','mem.pagesout')`; `Get-WorkerPerfHostSignals` liefert zusätzlich diese fünf (`CoreMaxPct`, `CoresBusy`, `PerfPct`, `UtilityPct`, `PagesOutPerSec`, NaN wenn leer).
  - Schnelle Probe beider Quellen: Felder `CoreMaxPct`, `CoresBusy`, `PerfPct`, `UtilityPct`, `PagesOutPerSec` (Zahl oder `$null`).
  - `Initialize-WorkerPerfSource … [double]$CoreBusyPct = 90` in beiden Quellen.
  - Windows: Gruppe `cpu` = `@{ Category = 'Processor Information'; Counters = @('% Processor Time'); Optional = @('% Processor Performance', '% Processor Utility'); Mode = 'Calculate' }`, Gruppe `memory` mit `Optional = @('Pages Output/sec')`; `Test-WorkerPerfProcessorTotal([string]$Name) -> bool` (Name enthält `_Total`); `Get-WorkerPerfCoreStats($Instances, [double]$CoreBusyPct) -> @{ CoreMaxPct; CoresBusy }` (über die Instanzen ohne Gesamtinstanz; beide `$null` ohne eine solche); `ConvertTo-WorkerPerfWinFastSample … [double]$CoreBusyPct = 90`; `Sources` mit `cpu.coreMax`, `cpu.coreBusy` (wie `cpu.host`), `cpu.perf`, `cpu.utility`, `mem.pagesout` (verfügbar, wenn Gruppe und Zähler da sind; sonst `Detail` `<Kategorie>: <Grund des Zählers>`).
  - `meta.json` `CoreBusyPct` (Zahl, Wert des Katalogs; auch im Schnelllauf).
  - `src/texts.de.json`: `source.cpu.coreMax` „Stärkster logischer Prozessor“, `source.cpu.coreBusy` „Logische Prozessoren über der Kern-Schwelle“, `source.cpu.perf` „Leistungsanteil (% Processor Performance)“, `source.cpu.utility` „Geleistete Arbeit (% Processor Utility)“, `source.mem.pagesout` „Ausgelagerte Seiten (Pages Output/sec)“.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben**

```powershell
# tests/Common.Tests.ps1 (Aussage geaendert: die Kopfzeile hat 24 statt 19 Spalten, Entwurf 4.1)
It 'fuehrt die fuenf neuen Spalten am Ende von ticks.csv' {
    $h = $WorkerPerfHeaders['ticks.csv'].Split(','); $h.Count | Should -Be 24
    $h[-5..-1] | Should -Be $WorkerPerfTickOptionalColumns
}
It 'leitet die neuen Signale aus dem Takt ab' {
    $s = Get-WorkerPerfHostSignals ([pscustomobject]@{ CpuPct = 40; CoreMaxPct = 97.5; CoresBusy = 1; PerfPct = 104; UtilityPct = 41.6; PagesOutPerSec = 12 }) 8 65536
    $s['cpu.coreMax'] | Should -Be 97.5; $s['cpu.coreBusy'] | Should -Be 1; $s['cpu.perf'] | Should -Be 104; $s['cpu.utility'] | Should -Be 41.6; $s['mem.pagesout'] | Should -Be 12
    [double]::IsNaN((Get-WorkerPerfHostSignals ([pscustomobject]@{ CpuPct = 40 }) 8 65536)['cpu.coreMax']) | Should -BeTrue
}
# tests/Capture.Tests.ps1
It 'schreibt die fuenf Werte am Ende der Zeile des Takts' {
    $r = ConvertTo-WorkerPerfFastRows -Sample (New-TestSample @{ CoreMaxPct = 97.54; CoresBusy = 1; PerfPct = 104.0; UtilityPct = 41.63; PagesOutPerSec = 12.0 }) -T 3 -ElapsedSec 2 -Burst $false -CollectMs 5
    $r.Tick | Should -Match ',5,97\.5,1,104,41\.6,12$'
    (ConvertTo-WorkerPerfFastRows -Sample (New-TestSample @{}) -T 3 -ElapsedSec 2 -Burst $false -CollectMs 5).Tick | Should -Match ',5,,,,,$'
}
# tests/WindowsSource.Tests.ps1
It 'bildet stärksten Kern und volle Kerne ohne Gesamtinstanzen' {                    # Review Focus 1
    $c = Get-WorkerPerfCoreStats @{ '0,0' = 95.0; '0,1' = 10.0; '0,_Total' = 52.5; '_Total' = 52.5 } 90
    $c.CoreMaxPct | Should -Be 95; $c.CoresBusy | Should -Be 1
    (Get-WorkerPerfCoreStats @{ '0,0' = 90.0; '0,1' = 89.9 } 90).CoresBusy | Should -Be 1
    $n = Get-WorkerPerfCoreStats @{ '_Total' = 40.0; '0,_Total' = 40.0 } 90; $n.CoreMaxPct | Should -BeNullOrEmpty; $n.CoresBusy | Should -BeNullOrEmpty
    Test-WorkerPerfProcessorTotal '0,_Total' | Should -BeTrue; Test-WorkerPerfProcessorTotal '1,7' | Should -BeFalse
}
It 'liest Leistungsanteil, geleistete Arbeit und ausgelagerte Seiten' {
    $v = @{ cpu = @{ '% Processor Time' = @{ '_Total' = 40.0; '0,0' = 97.0 }; '% Processor Performance' = @{ '_Total' = 104.0 }; '% Processor Utility' = @{ '_Total' = 41.6 } }
            memory = @{ 'Available Bytes' = @{ '' = 1GB }; 'Committed Bytes' = @{ '' = 2GB }; 'Commit Limit' = @{ '' = 4GB }; 'Pages Input/sec' = @{ '' = 1.0 }; 'Pages Output/sec' = @{ '' = 12.0 } } }
    $s = ConvertTo-WorkerPerfWinFastSample -Values $v -ElapsedSec 2 -Time ([datetime]'2026-01-15 08:00') -ProfileMap $null -LogicalProcessors 8 -CoreBusyPct 90
    $s.CpuPct | Should -Be 40; $s.CoreMaxPct | Should -Be 97; $s.CoresBusy | Should -Be 1; $s.PerfPct | Should -Be 104; $s.UtilityPct | Should -Be 41.6; $s.PagesOutPerSec | Should -Be 12
}
It 'misst die CPU weiter, wenn ein neuer Zaehler fehlt' {                            # Review Focus 1
    # Platzhalter: $WinFake.Perf['Processor Information'] ohne '% Processor Utility', $WinFake.Perf['Memory'] ohne 'Pages Output/sec'
    $src = Initialize-WorkerPerfSource -StartTime (Get-Date) -CoreBusyPct 90
    $src.Sources['cpu.host'].Available | Should -BeTrue; $src.Sources['cpu.coreMax'].Available | Should -BeTrue; $src.Sources['cpu.perf'].Available | Should -BeTrue
    $src.Sources['cpu.utility'].Available | Should -BeFalse; $src.Sources['cpu.utility'].Detail | Should -Match "Processor Information: Zaehler '% Processor Utility' fehlt"
    $src.Sources['mem.pagesout'].Available | Should -BeFalse; $src.Sources['mem.used'].Available | Should -BeTrue
    [void](Get-WorkerPerfFastSample); $s = Get-WorkerPerfFastSample
    $s.UtilityPct | Should -BeNullOrEmpty; $s.PagesOutPerSec | Should -BeNullOrEmpty; $s.CpuPct | Should -Not -BeNullOrEmpty
}
# tests/Collector.Tests.ps1
It 'schreibt die Kern-Schwelle in meta.json und die neue Kopfzeile' {
    $run = Invoke-SimCapture (Join-Path $TestDrive 'kern')
    (Get-Content (Join-Path $run 'meta.json') -Raw | ConvertFrom-Json).CoreBusyPct | Should -Be 90
    (Get-Content (Join-Path $run 'ticks.csv') -TotalCount 1) | Should -Be $WorkerPerfHeaders['ticks.csv']
}
It 'startet nicht mit einem fehlerhaften Katalog der Groesse' {
    # Kopie von src nach $TestDrive/badsrc mit thresholds.coreBusyPct.value = 40 in sizing.de.json
    { & (Join-Path $TestDrive 'badsrc/Start-WorkerPerfCapture.ps1') -Simulate -DurationMinutes 1 -OutputPath (Join-Path $TestDrive 'bad') } | Should -Throw '*sizing.de.json*coreBusyPct*'
    Test-Path (Join-Path $TestDrive 'bad') | Should -BeFalse
}
```

`New-TestSample([hashtable]$Change)` (in `tests/Capture.Tests.ps1`) ist eine schnelle Probe mit allen bisherigen Feldern, wie die bestehenden Tests von `ConvertTo-WorkerPerfFastRows` sie bauen, und den genannten Feldern; die Kopie von `src` für den fehlerhaften Katalog legt der Test wie `New-PatchedSource` an.

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "& ./tests/Invoke-Tests.ps1 -Path tests/Common.Tests.ps1, tests/Capture.Tests.ps1, tests/WindowsSource.Tests.ps1, tests/Collector.Tests.ps1"`
Expected: FAIL (Kopfzeile hat 19 Spalten, `Get-WorkerPerfCoreStats` fehlt)

- [ ] **Step 3: Format und Signale in `src/WorkerPerf.Common.ps1`, Zeile in `src/WorkerPerf.Capture.ps1`** – Formatcodes der fünf Werte `1, 0, 1, 1, 1`.

- [ ] **Step 4: Windows-Quelle** – `Initialize-WorkerPerfSource` prüft `Counters` wie bisher (Gruppe verfügbar oder nicht) und `Optional` einzeln (`$state.Optional[<Gruppe>] = [string[]]` der vorhandenen); `Get-WorkerPerfFastSample` berechnet `Counters` + vorhandene `Optional`; `ConvertTo-WorkerPerfWinFastSample` bildet die fünf Felder (`% Processor Performance`/`% Processor Utility` aus `_Total`, `Pages Output/sec` `first`, Kern-Kennzahlen aus den Instanzen von `% Processor Time` über `Get-WorkerPerfCoreStats`). Kein weiteres Lesen der Kategorie: `Read-WorkerPerfWinCategory` liest die ganze Kategorie schon.

- [ ] **Step 5: Collector** – vor jedem Lesen und vor dem Anlegen des Ordners: `. WorkerPerf.Sizing.ps1`, `$sizing = Read-WorkerPerfSizing (Join-Path $PSScriptRoot 'sizing.de.json') $thresholds`; `-CoreBusyPct $sizing.Thresholds.coreBusyPct.Value` an `Initialize-WorkerPerfSource`; `CoreBusyPct` in `meta.json` nach `PhysicalMemoryMB`. Simulation: Parameter angenommen, die fünf Felder `$null` (Werte folgen in Task 4).

- [ ] **Step 6: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0` (Aussagen, die die Liste der Quellen oder die Kopfzeile wörtlich nennen, bekommen die neuen Einträge; jede solche Änderung im Test mit `# Aussage geaendert (Groesse Task 2)`)

- [ ] **Step 7: Commit**

```bash
git add src/WorkerPerf.Common.ps1 src/WorkerPerf.Capture.ps1 src/Start-WorkerPerfCapture.ps1 src/WorkerPerf.Sources.Windows.ps1 src/WorkerPerf.Sources.Simulation.ps1 src/texts.de.json tests/
git commit -m "Record the strongest core, the busy cores, the frequency counters and page output" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TebhPvsTuNpmYXDmJ3hXkB"
```

---

### Task 3: Lader – optionale Spalten, neue Signale, ältere Aufzeichnungen

**Files:**
- Modify: `src/WorkerPerf.Load.ps1` (`Open-WorkerPerfCsvReader`, `Read-WorkerPerfCsvFile`, `Import-WorkerPerfRun`)
- Test: `tests/Load.Tests.ps1`, `tests/TestHelpers.ps1` (`New-OldCaptureCopy`)

**Interfaces:**
- Consumes: Task 2 (Kopfzeile, `$WorkerPerfTickOptionalColumns`, `$WorkerPerfSizingSignalIds`, `meta.json` `CoreBusyPct`).
- Produces:
  - `Read-WorkerPerfCsvFile([string]$Path, [string]$FileName, [switch]$OwnHeader, [string[]]$Optional = @()) -> @{ Col; Rows; Skipped; Header }`: `Need` = Breite des Formats ohne die Spalten `$Optional`; `Header` = die Namen der Kopfzeile der Datei (leer bei fehlender Datei). Eine optionale Spalte, die die Datei nicht hat, fehlt in `Col`.
  - `Import-WorkerPerfRun`: `Tick.Raw` mit den fünf Spalten, `Tick.Signal` mit `cpu.coreMax`, `cpu.coreBusy`, `cpu.perf`, `cpu.utility`, `mem.pagesout` (NaN, wo kein Wert); `Meta.CoreBusyPct` (Zahl oder `$null`); `Model.Measured` (Hashtable Signalkennung → bool: Spalte in der Kopfzeile **und** `Sources[id]` fehlt oder ist verfügbar). Im Modell eines Schnelllaufs dieselben Schlüssel, leer bzw. `$false`.
  - `New-OldCaptureCopy([string]$Run, [string]$OutDir) -> string` (Testhelfer): Kopie mit `ticks.csv` ohne die fünf Spalten (Kopfzeile und Zeilen), `meta.json` ohne `CoreBusyPct` und ohne die fünf Einträge in `Sources`.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/Load.Tests.ps1`; `New-TickLine` schreibt weiter 19 Felder, `Write-TestRun` die neue Kopfzeile)

```powershell
Describe 'Import-WorkerPerfRun: neue Signale' {
    It 'liest Zeilen ohne die optionalen Felder und laesst die neuen Signale leer' {
        $m = Import-TestRun 'g1' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }
        $m.Tick.N | Should -Be 8; $m.Unreadable.Ticks | Should -Be 0
        [double]::IsNaN($m.Tick.Signal['cpu.coreMax'][0]) | Should -BeTrue; $m.Measured['cpu.coreMax'] | Should -BeTrue      # Spalte in der Kopfzeile, keine Quelle dagegen
        $m.Meta.CoreBusyPct | Should -BeNullOrEmpty
    }
    It 'liest die fuenf Werte und die Kern-Schwelle' {
        $lines = @(0..7 | ForEach-Object { (New-TickLine $_) + ',97.5,1,104,41.6,12' })
        $dir = Write-TestRun 'g2' @{ 'ticks.csv' = $lines; 'snapshots.csv' = $SnapLines }; $mf = Join-Path $dir 'meta.json'
        [IO.File]::WriteAllText($mf, [IO.File]::ReadAllText($mf).Replace('"Simulated":false,', '"Simulated":false,"CoreBusyPct":90,'))
        $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles
        $m.Tick.Signal['cpu.coreMax'][3] | Should -Be 97.5; $m.Tick.Signal['cpu.coreBusy'][3] | Should -Be 1; $m.Tick.Signal['mem.pagesout'][3] | Should -Be 12
        $m.Meta.CoreBusyPct | Should -Be 90
    }
    It 'liest eine aeltere Aufzeichnung ohne die Spalten ganz' {                       # Review Focus 2
        $dir = Write-TestRun 'g3' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }; $tf = Join-Path $dir 'ticks.csv'
        $old = $WorkerPerfHeaders['ticks.csv'].Substring(0, $WorkerPerfHeaders['ticks.csv'].IndexOf(',CoreMaxPct'))
        [IO.File]::WriteAllLines($tf, [string[]](@($old) + @($Ticks)))
        $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles
        $m.Tick.N | Should -Be 8; $m.Unreadable.Ticks | Should -Be 0
        foreach ($id in $WorkerPerfSizingSignalIds) { $m.Measured[$id] | Should -BeFalse -Because $id }
        $m.Tick.Signal['cpu.host'][0] | Should -Be 50
    }
    It 'nimmt ein Signal einer nicht verfuegbaren Quelle als nicht gemessen' {
        $dir = Write-TestRun 'g4' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }; $mf = Join-Path $dir 'meta.json'
        [IO.File]::WriteAllText($mf, [IO.File]::ReadAllText($mf).Replace('"Sources":{', '"Sources":{"cpu.utility":{"Available":false,"Detail":"x"},'))
        $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles
        $m.Measured['cpu.utility'] | Should -BeFalse; $m.Measured['cpu.perf'] | Should -BeTrue
    }
    It 'haelt im Modell eines Schnelllaufs dieselben Schluessel' {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        $m = Import-WorkerPerfRun -Path (Invoke-SimHealthOnly (Join-Path $TestDrive 'q')) -Thresholds $Th -Roles $Roles
        @($m.Tick.Signal['cpu.coreMax']).Count | Should -Be 0; $m.Measured['cpu.coreMax'] | Should -BeFalse
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Load.Tests.ps1`
Expected: FAIL, das Modell hat kein Feld `Measured`

- [ ] **Step 3: Umsetzen** – `Import-WorkerPerfRun` liest `ticks.csv` mit `-Optional $WorkerPerfTickOptionalColumns`; eine Spalte, die in `Col` fehlt, hat den Index -1; ein Index ab der Länge der Zeile ergibt NaN (Wächter in der Leseschleife, ohne Aufruf je Wert). `CoreBusyPct` wie `LogicalProcessors` in die Liste der Meta-Felder.

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Load.ps1 tests/Load.Tests.ps1 tests/TestHelpers.ps1
git commit -m "Read the new per-tick values and keep older captures readable" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TebhPvsTuNpmYXDmJ3hXkB"
```

---

### Task 4: Simulation – die neuen Werte, Drehbücher „Ursachen“ und „Tag“

**Files:**
- Modify: `src/WorkerPerf.Sources.Simulation.ps1`, `src/Start-WorkerPerfCapture.ps1` (`-SimulateScenario`, `-SimulateDay`, nur Weitergabe), `tests/TestHelpers.ps1` (`New-SizingRuns`)
- Test: `tests/Simulation.Tests.ps1`, `tests/Collector.Tests.ps1`

**Interfaces:**
- Consumes: Task 2 (Felder der schnellen Probe, `-CoreBusyPct`).
- Produces:
  - Simulation `Initialize-WorkerPerfSource … [ValidateSet('Stunde','Ursachen','Tag')][string]$Scenario = 'Stunde', [ValidateRange(1,5)][int]$Day = 1`; Collector `-SimulateScenario <Stunde|Ursachen|Tag>`, `-SimulateDay <1..5>`; ohne `-Simulate` wirft der Collector `-SimulateScenario und -SimulateDay gelten nur mit -Simulate.` vor jedem Lesen.
  - Die fünf Werte in jedem Drehbuch; `$script:WorkerPerfSimSignalIds` mit den fünf neuen Kennungen (alle verfügbar). Neue Rauschschlüssel 315 bis 319; die bisherigen bleiben, damit die Werte der Stunde gleich bleiben.
  - `Get-WorkerPerfExpected`: jede Zeile eines Leistungsvorfalls hat `Classes` (`[string[]]`, in der Reihenfolge des Vorrangs).
  - `New-SizingRuns([string]$OutDir) -> [ordered]@{ Days = [string[]] (Tag 1 bis 5); Quick = <Schnelllauf> }` (Testhelfer; alle `SIM-VDA01`).

**Drehbücher** (alle 8 vCPU, 64 GB, `SIM-VDA01`, 60 Minuten; Fenster in Sekunden nach dem Start, Fenster A–B gilt für A < t ≤ B):

| Drehbuch | Fenster | Inhalt | Soll-Klassen |
|---|---|---|---|
| Stunde | wie bisher; dazu `CoreMaxPct` = min(99,5; 1,5 × CpuPct + 5 × Rauschen), `CoresBusy` 4 im Fenster `cpu`, sonst 0; `PerfPct` 98–102; `UtilityPct` = CpuPct × PerfPct / 100; `PagesOutPerSec` 0–3 | Vorfälle unverändert | `cpu` `app`; `memory` `mem.app`; alle anderen leer |
| Ursachen `host` | 300–420 | 25 Sitzungen je `nexus.exe` +0,18 Kerne (CPU ≈ 81 %), `StealPct` 12–14, Warteschlange je CPU unter 2 | `host`, `capacity` (Stufe `tight`) |
| Ursachen `singlecore` | 900–1020 | `simcalc.exe` in der Sitzung von `user010` bei 1,0 Kern; `CoreMaxPct` 99–100, `CoresBusy` 1, CPU ≈ 37 %; Eingabeverzögerung dieser Sitzung 800–1200 ms | `singlecore` (Vorfall ohne Engpass) |
| Ursachen `capacity` | 1500–1620 | `nexus.exe` +0,24 Kerne je Sitzung, CPU ≥ 95 %, Warteschlange 24 (3 je CPU) | `capacity` (Stufe `clear`) |
| Ursachen `scan` | 2100–2220 | `MsMpEng.exe` +5 Kerne (CPU ≈ 87 %), Defender-Ereignis 1000 bei 2100 und 1001 bei 2220 | `oneoff` |
| Ursachen `memleak` | 2700–2900 | `simleak.exe` (`user012`) wächst auf 20 GB, RAM-Auslastung bis 88 %, zugesichert unter RAM, kein Auslagern | `mem.app` |
| Ursachen `memcapacity` | 3000–3200 | jede Sitzung +1,2 GB, zugesichert 70 GB (über 64 GB RAM, 71 % der Grenze), RAM 95 %, `PagesOutPerSec` 300–340 ab 3030 | `mem.capacity` |
| Ursachen `commit` | 3300–3480 | `simreserve.exe` (Sitzung 0) sagt 50 GB zu ohne Arbeitssatz: zugesichert 92 % der Grenze, RAM 60 %, `PagesOutPerSec` unter 5 | `mem.commit` |
| Tag d (1–5) | ganze Stunde | Beginn = Start + (d − 1) Tage; Sitzungen `user001`…`user031`, jede mit `nexus.exe`: 6 zu Beginn, je eine mehr alle 40 s ab Minute 2 bis 31 (Minute 18), 31 bis Minute 42, dann zurück auf 6 bis Minute 58; CPU = 1,2 + 0,2 × Sitzungen Kerne (bei 31: 92,5 %), an Tag 5 0,15 je Sitzung (unter 75 %); Warteschlange 24 bei CPU ≥ 90 % an den Tagen 1–4; Tag 3 zusätzlich `StealPct` 12 in Minute 25–28; zugesichert 40 GB + 0,5 GB je Sitzung | Tage 1–4: jeder CPU-Vorfall der Spitze (die Befunde dauern länger als 15 Minuten, es sind Dauerzustände) `capacity`; an Tag 3 dazu der Vorfall der entzogenen CPU-Zeit in Minute 25–28 mit `host`, `capacity`; Tag 5: kein Vorfall |

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/Simulation.Tests.ps1`; `Get-SimSample([string]$Scenario, [double]$Sec, [int]$Day = 1)` initialisiert die Quelle mit dem Drehbuch und liefert die schnelle Probe zur Sekunde)

```powershell
Describe 'Simulation: Drehbuecher der Groesse' {
    It 'spielt die Szenen der Ursachen' {
        $h = Get-SimSample Ursachen 360; $h.StealPct | Should -BeGreaterOrEqual 12; $h.CpuPct | Should -BeGreaterOrEqual 75
        $s = Get-SimSample Ursachen 960; $s.CoreMaxPct | Should -BeGreaterOrEqual 99; $s.CoresBusy | Should -Be 1; $s.CpuPct | Should -BeLessThan 50
        $c = Get-SimSample Ursachen 1560; $c.CpuPct | Should -BeGreaterOrEqual 90; ($c.ProcQueue / 8) | Should -BeGreaterOrEqual 2
        $m = Get-SimSample Ursachen 3100; $m.MemCommittedMB | Should -BeGreaterThan 65536; $m.PagesOutPerSec | Should -BeGreaterOrEqual 300
        $k = Get-SimSample Ursachen 3400; ($k.MemCommittedMB / $k.MemCommitLimitMB) | Should -BeGreaterOrEqual 0.92; $k.PagesOutPerSec | Should -BeLessThan 5
        (100 * (1 - $k.MemAvailMB / 65536)) | Should -BeLessThan 75
    }
    It 'meldet den Scan als Defender-Ereignisse 1000 und 1001' {
        $ev = @(Get-SimEvents Ursachen) | Where-Object { $_.Source -like '*Defender*' }
        @($ev | Where-Object EventId -eq 1000).Count | Should -Be 1; @($ev | Where-Object EventId -eq 1001).Count | Should -Be 1
    }
    It 'laesst die Sitzungen eines Tags steigen und fallen' {
        (Get-SimSnapshot Tag 30).Sessions.Count | Should -Be 6; (Get-SimSnapshot Tag 1800).Sessions.Count | Should -Be 31; (Get-SimSnapshot Tag 3570).Sessions.Count | Should -Be 6
        (Get-SimSample Tag 1800 -Day 5).CpuPct | Should -BeLessThan 75; (Get-SimSample Tag 1800 -Day 2).CpuPct | Should -BeGreaterOrEqual 90
        (Get-SimSample Tag 1600 -Day 3).StealPct | Should -BeGreaterOrEqual 12; (Get-SimSample Tag 1600 -Day 2).StealPct | Should -BeLessThan 1
    }
    It 'beschreibt die Soll-Klassen' {
        (Get-SimExpected Stunde | Where-Object Key -eq 'cpu').Classes | Should -Be @('app')
        (Get-SimExpected Stunde | Where-Object Key -eq 'memory').Classes | Should -Be @('mem.app')
        (Get-SimExpected Ursachen | Where-Object Key -eq 'host').Classes | Should -Be @('host', 'capacity')
        (Get-SimExpected Ursachen | Where-Object Key -eq 'commit').Classes | Should -Be @('mem.commit')
    }
    It 'laesst die simulierte Stunde unveraendert' {
        # dieselben Werte wie vor diesem Baustein an fuenf festen Sekunden
        foreach ($sec in 10, 360, 1000, 2000, 3000) {
            $o = Get-SimSample Stunde $sec
            foreach ($f in 'CpuPct', 'MemAvailMB', 'StealPct', 'PagesInPerSec') { $o.$f | Should -Be $StundeBefore[$sec][$f] -Because "$f bei $sec s" }
        }
    }
}
# tests/Collector.Tests.ps1
It 'lehnt -SimulateScenario ohne -Simulate ab' { { & $Capture -SimulateScenario Tag -OutputPath (Join-Path $TestDrive 'x') } | Should -Throw '*nur mit -Simulate*' }
It 'legt Tage eines Servers mit verschiedenem Beginn an' {
    $r = New-SizingRuns (Join-Path $TestDrive 'size'); @($r.Days).Count | Should -Be 5
    $m = @($r.Days | ForEach-Object { Get-Content (Join-Path $_ 'meta.json') -Raw | ConvertFrom-Json })
    @($m.Computer | Sort-Object -Unique) | Should -Be @('SIM-VDA01')
    ([DateTimeOffset]$m[1].StartTime - [DateTimeOffset]$m[0].StartTime).TotalDays | Should -BeGreaterOrEqual 0.99
}
```

Hilfen im `BeforeAll`: `Get-SimSample([string]$Scenario, [double]$Sec, [int]$Day = 1)` initialisiert die Quelle mit dem Drehbuch, stellt die virtuelle Uhr auf die Sekunde und liefert die schnelle Probe; `Get-SimSnapshot` ebenso den Schnappschuss; `Get-SimEvents([string]$Scenario)` die Ereignisse der ganzen Stunde; `Get-SimExpected([string]$Scenario)` das Soll. `$StundeBefore` ist eine Tabelle Sekunde → `@{ CpuPct; MemAvailMB; StealPct; PagesInPerSec }`, deren Zahlen Step 2 aus dem unveränderten Stand abliest und in den Test schreibt.

- [ ] **Step 2: Werte der Stunde festhalten, Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Simulation.Tests.ps1`
Expected: FAIL, `Initialize-WorkerPerfSource` kennt `-Scenario` nicht

- [ ] **Step 3: Drehbücher umsetzen** – je Drehbuch eine Tabelle der Fenster wie `$script:WorkerPerfSimWindows` (`$script:WorkerPerfSimCauseWindows`), Sitzungen des Tags mit Anmelde- und Abmeldezeit, Prozesse mit `Add-WorkerPerfSimExtra`; die Stunde bleibt der Weg ohne Parameter.

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Sources.Simulation.ps1 src/Start-WorkerPerfCapture.ps1 tests/
git commit -m "Simulate the new values, one scene per cause and five working days of one server" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TebhPvsTuNpmYXDmJ3hXkB"
```

---

### Task 5: Einordnung je Vorfall

**Files:**
- Modify: `src/WorkerPerf.Sizing.ps1`, `src/roles.json` (Rolle `Wartung`), `src/WorkerPerf.Common.ps1` (`$script:WorkerPerfRoleNames` + `'Wartung'`)
- Test: `tests/Sizing.Tests.ps1`

**Interfaces:**
- Consumes: Task 1 (Katalog), Task 3 (`Model.Measured`, neue Signale), Task 4 (Drehbücher, `Classes` im Soll); `Get-WorkerPerfSeries`, `Get-WorkerPerfFindings`, `Join-WorkerPerfIncidents`, `Add-WorkerPerfIncidentDetail`, `Get-WorkerPerfWindowTicks`, `Get-WorkerPerfWindowSnaps`, `Get-WorkerPerfShareTable`, `Group-WorkerPerfShareTable`.
- Produces:
  - `Get-WorkerPerfPercentile([double[]]$Values, [double]$Pct) -> double` (nächster Rang: sortiert, Index ⌈Pct/100 · n⌉ − 1; NaN übergangen; leer → NaN).
  - `Get-WorkerPerfIncidentFacts($Incident, $Model, $Thresholds, $Sizing) -> hashtable` mit: `Cpu`, `Memory`, `Delay` (bool: CPU-Befund, Arbeitsspeicher-Befund, Typ `ohne-engpass`); `MinTicks` (Signal → `minTicks`); `StealMeasured`, `StealTicks` (Takte ≥ `stealWarn`), `StealMax`; `CpuP95`, `CpuMax`, `OverTargetTicks` (≥ `target`), `ClearTicks` (CPU ≥ `cpuCrit` und Warteschlange je CPU ≥ `queueWarn` im selben Takt), `QueueMax`; `CoreMaxMeasured`, `CoreMaxHighPct` (Anteil der Takte mit `cpu.coreMax` ≥ `coreBusyPct`), `CoreMaxP95`; `Processes` (bool: ein Prozess lebte in den Schnappschüssen des Fensters und `Prozesse` ist nicht weggelassen); `TopProcess` (`@{ Name; Cores (Median der Kerne je Schnappschuss = CpuMs / (ElapsedSec·1000)); BandPct (Anteil der Schnappschüsse mit Kernen in [coreBusyPct/100, singleCoreMaxCores]) }` oder `$null`, ohne den Collector); `TopApp` (`@{ App; Role; RoleLabel; SharePct }` der größten Anwendung in einer Sitzung an der genutzten CPU, oder `$null`); `Scan` (bool, `Model.Scans` überlappt); `PagesOutMeasured`, `PagesOutPct` (Anteil der Takte ≥ `pagesOutLowPerSec`), `PagesOutMax`; `CommitOverRamTicks` (zugesichert > RAM), `CommitCritTicks` (`mem.commit` ≥ `commitCrit`), `CommitMax`, `CommittedMaxMB`, `RamMB`; `MemTop` (`@{ App; SharePct; GrowthMB }` oder `$null`); `UsedMax`.
  - `Get-WorkerPerfIncidentClasses([hashtable]$Facts, $Sizing) -> @{ Classes = @(@{ Id; Level; Values }); Unchecked = @(@{ Id; Missing = [string[]] }) }` – Klassen in der Reihenfolge des Vorrangs; `Level` nur bei `capacity` (`clear`|`tight`); `Values` = die Platzhalterwerte für die Texte; `Missing` leer bei einem Widerspruch.
  - `Add-WorkerPerfIncidentClasses -Incidents <object[]> -Model -Thresholds -Sizing` setzt an jedem Leistungsvorfall `Classes`, `Unchecked` (leer, wo keine Klasse in Frage kommt).
  - `Get-WorkerPerfClassOut($Incident, $Sizing) -> @{ Line; Classes = @([ordered]@{ id; level; label; reason; direction; sources }); Unchecked = @([ordered]@{ id; missing; text }) }` – die Texte aus den Vorlagen; `Line` = `''` ohne Klasse und ohne ungeklärte.
  - `Get-WorkerPerfRunAnalysis -Path <string> [-From] [-To] -Thresholds -Roles -Sizing -> @{ Model; Series; Findings; Incidents }` (Schnelllauf: leere Listen); dieselben Aufrufe in derselben Reihenfolge wie im normalen Bericht, dazu `Add-WorkerPerfIncidentClasses`.

**Regeln** (Entwurf 5.1; eine Klasse kommt nur in Frage, wo ihr Vorfall sie zulässt: `host` und `singlecore` bei `Cpu` oder `Delay`, `app`/`oneoff`/`capacity` bei `Cpu`, die vier Speicherklassen bei `Memory`):
- `host`: `StealTicks` ≥ `MinTicks['cpu.steal']`. Ungemessen → ungeklärt `cpu.steal`.
- `singlecore`: `TopProcess.BandPct` ≥ `sustainedPct` **und** `CoreMaxHighPct` ≥ `sustainedPct` **und** `CpuP95` < `cpuCrit`. Prozessmuster da, `cpu.coreMax` nicht gemessen → ungeklärt `cpu.coreMax`; Prozessmuster da, `CoreMaxHighPct` < `sustainedPct` → ungeklärt (Widerspruch). Ohne Prozessdaten → ungeklärt `processes`.
- `oneoff`: `TopApp.SharePct` ≥ `$WorkerPerfMinSharePct` und (`TopApp.Role` = `Wartung` oder (`Sicherheit` und `Scan`)).
- `app`: nicht `singlecore`, nicht `oneoff`, Prozessmuster nicht ungeklärt, `TopApp.SharePct` ≥ `appSharePct`.
- `capacity`: keine von `singlecore`, `app`, `oneoff`, keine davon ungeklärt, `OverTargetTicks` ≥ `MinTicks['cpu.host']`; `Level` `clear` bei `ClearTicks` ≥ `MinTicks['cpu.host']`, sonst `tight`.
- `mem.app`: `MemTop.SharePct` ≥ `appSharePct` oder `MemTop.GrowthMB` ≥ `leakGrowthPct` % von `RamMB`.
- `mem.capacity`: nicht `mem.app`, `CommitOverRamTicks` ≥ `MinTicks['mem.commit']`, `PagesOutPct` > `pagesOutSharePct`.
- `mem.commit`: `CommitCritTicks` ≥ `MinTicks['mem.commit']`, `PagesOutPct` ≤ `pagesOutSharePct`.
- `mem.used`: keine von `mem.capacity`, `mem.commit`, `mem.app` und keine davon ungeklärt.
- `undecidable`: der Vorfall kommt für eine Klasse in Frage, trägt keine, und mindestens eine ist ungeklärt; `Values.missing` nennt die Bezeichnungen aus `Sizing.Missing`.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/Sizing.Tests.ps1`, Teil „Einordnung“; `New-Facts([hashtable]$Change)` liefert Fakten eines ruhigen CPU-Vorfalls auf 8 vCPU mit den genannten Änderungen: `Cpu` wahr, `Memory` und `Delay` falsch, alles gemessen (`StealMeasured`, `CoreMaxMeasured`, `PagesOutMeasured`, `Processes` wahr), `MinTicks` 3 je Signal, alle Zählungen und Anteile 0, `CpuP95` 50, `RamMB` 65536, `TopProcess` `@{ Name = 'quiet.exe'; Cores = 0.2; BandPct = 0 }`, `TopApp` und `MemTop` `$null`, `Scan` falsch; `Classes-Of($Facts)` = `@((Get-WorkerPerfIncidentClasses $Facts $Sz).Classes.Id)`)

```powershell
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
    It 'Leistung je Kern ohne stärksten Kern: nicht entscheidbar' {                    # Review Focus 1
        $r = Get-WorkerPerfIncidentClasses (New-Facts @{ Delay = $true; Cpu = $false; TopProcess = @{ Name = 'simcalc.exe'; Cores = 1.0; BandPct = 100 }; CoreMaxMeasured = $false }) $Sz
        $r.Classes.Id | Should -Be @('undecidable'); $r.Unchecked[0].Id | Should -Be 'singlecore'; $r.Unchecked[0].Missing | Should -Be @('cpu.coreMax')
    }
    It 'Prozess bei einem Kern, der stärkste Kern aber frei: Widerspruch' {
        $r = Get-WorkerPerfIncidentClasses (New-Facts @{ Delay = $true; Cpu = $false; TopProcess = @{ Name = 'a.exe'; Cores = 1.0; BandPct = 100 }; CoreMaxHighPct = 10 }) $Sz
        $r.Unchecked[0].Id | Should -Be 'singlecore'; @($r.Unchecked[0].Missing).Count | Should -Be 0
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
    It 'stellt den VMware-Host vor jede andere Klasse' { Classes-Of (New-Facts @{ StealTicks = 4; OverTargetTicks = 5 }) | Should -Be @('host', 'capacity') }
    It 'Arbeitsspeicher: Kapazitaet nur mit anhaltendem Auslagern' {
        $m = @{ Cpu = $false; Memory = $true; CommitOverRamTicks = 3; CommitCritTicks = 0; PagesOutPct = 50.1 }
        Classes-Of (New-Facts $m) | Should -Be @('mem.capacity')
        Classes-Of (New-Facts (Merge $m @{ PagesOutPct = 50 })) | Should -Be @('mem.used')
        Classes-Of (New-Facts (Merge $m @{ PagesOutPct = 50; CommitCritTicks = 3 })) | Should -Be @('mem.commit')      # hoher Commit ohne Auslagern: keine Kapazitaet
    }
    It 'Arbeitsspeicher: Anwendung ab 10 % des RAM Zuwachs' {
        $m = @{ Cpu = $false; Memory = $true; RamMB = 65536; MemTop = @{ App = 'simleak.exe'; SharePct = 20; GrowthMB = 6553.6 } }
        Classes-Of (New-Facts $m) | Should -Be @('mem.app')
        Classes-Of (New-Facts (Merge $m @{ MemTop = @{ App = 'simleak.exe'; SharePct = 20; GrowthMB = 6553.5 } })) | Should -Be @('mem.used')
    }
    It 'ohne Prozessdaten: nicht entscheidbar mit der fehlenden Messung' {
        $r = Get-WorkerPerfIncidentClasses (New-Facts @{ OverTargetTicks = 5; Processes = $false; TopProcess = $null; TopApp = $null }) $Sz
        $r.Classes.Id | Should -Be @('undecidable'); (Get-WorkerPerfClassOut @{ Classes = $r.Classes; Unchecked = $r.Unchecked } $Sz).Line | Should -Match 'Prozessdaten'
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
            @($inc.Classes.Id) | Should -Be @($e.Classes) -Because $e.Key
        }
    }
    It 'ordnet die simulierte Stunde ein' {
        $a = Get-WorkerPerfRunAnalysis -Path (Invoke-SimCapture (Join-Path $TestDrive 's')) -Thresholds $Th -Roles $SimRoles -Sizing $Sz
        @(($a.Incidents | Where-Object Lead -eq 'cpu').Classes.Id) | Should -Be @('app')            # EXCEL.EXE von user003, 4,8 Kerne
        @(($a.Incidents | Where-Object Lead -eq 'memory').Classes.Id) | Should -Be @('mem.app')     # ms-teams.exe waechst um ein Drittel des RAM
        foreach ($i in @($a.Incidents | Where-Object Type -eq 'ohne-engpass')) { @($i.Classes).Count | Should -Be 0 }
    }
    It 'sagt an einer aelteren Aufzeichnung, was ohne die neuen Werte nicht unterscheidbar ist' {          # Review Focus 2
        $old = New-OldCaptureCopy $Causes (Join-Path $TestDrive 'old')
        $a = Get-WorkerPerfRunAnalysis -Path $old -Thresholds $Th -Roles $SimRoles -Sizing $Sz
        $one = @($a.Incidents | Where-Object Type -eq 'ohne-engpass')[0]
        $one.Classes.Id | Should -Be @('undecidable'); $one.Unchecked[0].Missing | Should -Be @('cpu.coreMax')
        (@($a.Incidents | Where-Object { $_.Classes.Id -contains 'capacity' })).Count | Should -BeGreaterThan 0      # breite Last bleibt entscheidbar
    }
}
```

Im `BeforeAll` der Datei stehen dazu `$Sz = Read-WorkerPerfSizing … $Th` und `Merge([hashtable]$A, [hashtable]$B) -> hashtable` (Kopie von `$A`, Schlüssel von `$B` gewinnen; `$A` bleibt unverändert). Dauerzustände werden eingeordnet wie andere Vorfälle (der Spitzenvorfall eines Tags in Task 4 ist einer).

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Sizing.Tests.ps1`
Expected: FAIL, `Get-WorkerPerfIncidentClasses` ist nicht definiert

- [ ] **Step 3: Rolle `Wartung`** – `$script:WorkerPerfRoleNames` + `'Wartung'`; Eintrag in `src/roles.json`: `{ "role": "Wartung", "label": "Windows Update", "processes": ["TiWorker.exe", "TrustedInstaller.exe", "MoUsoCoreWorker.exe"], "services": [], "note": "ungeprüft; Prozesse der Windows-Updates, für die Einordnung „Einmalig“" }`.

- [ ] **Step 4: `Get-WorkerPerfPercentile`, `Get-WorkerPerfIncidentFacts`, `Get-WorkerPerfIncidentClasses`, `Add-WorkerPerfIncidentClasses`, `Get-WorkerPerfClassOut`, `Get-WorkerPerfRunAnalysis` umsetzen** (die CPU-Tabelle des Fensters über `Get-WorkerPerfShareTable -Measure cpu -BaseSnaps @()`, die Speichertabelle mit `-Measure memory`; eine Tabelle je Vorfall, nicht je Klasse).

- [ ] **Step 5: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 6: Commit**

```bash
git add src/WorkerPerf.Sizing.ps1 src/roles.json src/WorkerPerf.Common.ps1 tests/Sizing.Tests.ps1
git commit -m "Classify every CPU and memory incident by its cause" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TebhPvsTuNpmYXDmJ3hXkB"
```

---

### Task 6: Normaler Bericht – Berichtsdaten, Schritt der Anleitung, Kopiertext, Maskierung

**Files:**
- Modify: `src/New-WorkerPerfReport.ps1`, `src/WorkerPerf.Guidance.ps1`, `src/guidance.de.json`, `src/WorkerPerf.Mask.ps1` (nur `$script:WorkerPerfMaskKeywordFields`), `docs/guidance/quellen.md`
- Test: `tests/Report.Tests.ps1`, `tests/Guidance.Tests.ps1`, `tests/GuidanceCatalogue.Tests.ps1`, `tests/Mask.Tests.ps1`, `tests/MaskCensus.json`

**Interfaces:**
- Consumes: Task 5 (`Add-WorkerPerfIncidentClasses`, `Get-WorkerPerfClassOut`, `Get-WorkerPerfRunAnalysis`), Task 3 (`Model.Measured`, `Meta.CoreBusyPct`).
- Produces:
  - `New-WorkerPerfReport.ps1 -SizingFile <Pfad>` (Vorgabe `sizing.de.json` neben dem Skript; gelesen und geprüft vor der Aufzeichnung, wie `-GuidanceFile`). Nach `Add-WorkerPerfIncidentDetail` der Aufruf `Add-WorkerPerfIncidentClasses`.
  - Je Leistungsvorfall in den Berichtsdaten: `classes` (`[{ id, level, label, reason, direction, sources }]`), `unchecked` (`[{ id, missing, text }]`), `classLine` (Text, `''` ohne Einordnung). Vorfälle aus Ereignissen haben die Felder nicht.
  - `host.coreMax`, `host.coreBusy`, `host.perf`, `host.utility`, `host.pagesOut` (Reihen, Nachkommastellen 1, 0, 1, 1, 1).
  - `sizing` = `{ catalogueVersion, coreBusyPct (aus meta.json, sonst null), coreBusyNow (Katalog), measured: { coreMax, coreBusy, perf, utility, pagesOut }, signals: { <id>: { label, note, sources } }, sources: [{ id, title, url, date, kind }] }` (nur die Quellen, die eine Klasse der Berichtsdaten oder ein Signal nennt).
  - Anleitung: `$script:WorkerPerfGuidanceConditions` + `'class.host'`, `'class.singlecore'`; `Get-WorkerPerfGuidanceFacts` setzt sie aus `classes[].id`. `src/guidance.de.json`, Situationen `cpu`, `delay.many`, `delay.single`, je zwei Prüfschritte am **Anfang** von `checks` (in der ersten Gruppe von P3-R75 gilt die Reihenfolge der Datei; so steht der Schritt vor den Schritten zu `cause.*`):
    - `when ['class.host']`: Text „Beim Team von VMware prüfen lassen, ob der VMware-Host dem Server Rechenzeit entzieht, und keine zusätzlichen vCPU vergeben“; `where` „vCenter: CPU Ready und Co-Stop der VM, Auslastung des VMware-Hosts“; `sign` „CPU Ready je vCPU über 5 % (über 10 %: handeln); Co-Stop anhaltend über 0 %, über 3 % je vCPU (zu viele vCPU); Auslastung des VMware-Hosts anhaltend über 70–80 %“; `source` „Broadcom: Rightsizing virtual machines on ESXi 8.0: vCPU, memory, and CPU topology guidance“.
    - `when ['class.singlecore']`: Text „Prüfen, ob die Anwendung nur einen Kern nutzt; mehr vCPU helfen ihr dann nicht“; `where` „Task-Manager auf dem Server, Registerkarte „Leistung“, Ansicht „Logische Prozessoren““; `sign` „ein logischer Prozessor dauerhaft voll, die anderen weitgehend frei“; `source` „Microsoft: Scenario guide: Troubleshoot performance problems in Windows“.
  - Kopiertext: `Get-WorkerPerfCopyParagraphs` gibt `classLine` als eigenen Absatz direkt nach dem Absatz der Ursache aus (ohne Ursache: an dessen Stelle).
  - `$script:WorkerPerfMaskKeywordFields` + `'classes.level'`, `'classes.sources'`, `'unchecked.missing'`, `'sizing.catalogueVersion'`, `'sources.kind'`, `'sources.date'`, `'signals.sources'`. `tests/MaskCensus.json`: `incidents[].classes[].label|reason|direction`, `incidents[].unchecked[].text`, `incidents[].classLine`, `sizing.signals.*.label|note`, `sizing.sources[].title` „composed“; die übrigen „keyword“.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben**

```powershell
# tests/Report.Tests.ps1 (BeforeAll: $R = New-TestReports …; $Causes = Invoke-SimCapture … @{ SimulateScenario = 'Ursachen' } und ihr Bericht report-causes.html)
Describe 'Einordnung im Bericht' {
    It 'ordnet die Vorfaelle der simulierten Stunde ein' {
        $d = Get-ReportData $R.Report
        $cpu = $d.incidents | Where-Object lead -eq 'cpu'; $cpu.classes[0].id | Should -Be 'app'; $cpu.classLine | Should -Match '^Einordnung: Anwendung'
        ($d.incidents | Where-Object lead -eq 'memory').classes[0].id | Should -Be 'mem.app'
        ($d.incidents | Where-Object { $_.type -eq 'ohne-engpass' } | Select-Object -First 1).classLine | Should -Be ''
        @($d.host.coreMax).Count | Should -Be $d.meta.ticks; $d.sizing.coreBusyPct | Should -Be 90; $d.sizing.measured.coreMax | Should -BeTrue
    }
    It 'zeigt dieselben Klassen wie die Auswertung des Groessenberichts' {
        $a = Get-WorkerPerfRunAnalysis -Path $Causes -Thresholds $Th -Roles $SimRoles -Sizing $Sz; $d = Get-ReportData $CausesReport
        foreach ($inc in $a.Incidents) { @(($d.incidents | Where-Object id -eq $inc.Id).classes.id) | Should -Be @($inc.Classes.Id) -Because "Vorfall $($inc.Id)" }
    }
    It 'reiht den Schritt des VMware-Hosts vorne in die Anleitung ein und nennt die Einordnung im Kopiertext' {
        $h = (Get-ReportData $CausesReport).incidents | Where-Object { $_.classes.id -contains 'host' }
        $h.guide.checks[0].text | Should -Match 'VMware-Host'; $h.guide.conditions | Should -Contain 'class.host'
        $h.copy.named | Should -Match 'Einordnung: VMware-Host'; $h.copy.anonymous | Should -Match 'Einordnung: VMware-Host'
    }
    It 'entsteht an einer aelteren Aufzeichnung und sagt, was nicht gemessen ist' {                  # Review Focus 2
        $d = Get-ReportData (New-ReportOf (New-OldCaptureCopy $Causes (Join-Path $TestDrive 'old')))
        $d.sizing.measured.coreMax | Should -BeFalse; $d.sizing.coreBusyPct | Should -BeNullOrEmpty
        ($d.incidents | Where-Object { $_.classes.id -contains 'undecidable' }).unchecked[0].text | Should -Match 'Stärkster|stärkster'
    }
    It 'lehnt einen fehlerhaften Katalog der Groesse vor dem Lesen ab' { { & $Report -Path $Causes -SizingFile (New-BadSizing) } | Should -Throw '*sizing*' }
}
# tests/Guidance.Tests.ps1
It 'kennt die Bedingungen der Einordnung und setzt sie aus den Klassen' {
    Test-WorkerPerfGuidanceCondition 'class.host' $Catalogue | Should -BeTrue; Test-WorkerPerfGuidanceCondition 'class.app' $Catalogue | Should -BeFalse
    $f = Get-WorkerPerfGuidanceFacts -Incident ([ordered]@{ type = 'engpass'; lead = 'cpu'; classes = @(@{ id = 'singlecore' }) }) -Context $Ctx -Catalogue $Catalogue
    $f.Conditions | Should -Contain 'class.singlecore'; $f.Conditions | Should -Not -Contain 'class.host'
}
```

Hilfen im `BeforeAll` von `tests/Report.Tests.ps1`: `$Sz` (Katalog), `$SimRoles` (`Read-WorkerPerfRoles` der Rollendatei der Simulation), `$CausesReport` (Bericht der Aufzeichnung `$Causes` mit derselben Rollendatei), `New-ReportOf([string]$Run) -> string` (Bericht einer Aufzeichnung nach `$TestDrive`), `New-BadSizing -> string` (Kopie des Katalogs mit `coreBusyPct` 40).

`tests/Mask.Tests.ps1`: der Bestandstest (P2-R15) scheitert, bis die neuen Felder in `tests/MaskCensus.json` stehen; dazu „Maskierter Bericht der simulierten Stunde“: `classLine` und `classes[].reason` enthalten keinen Benutzer der Aufzeichnung (Prozessnamen bleiben).

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "& ./tests/Invoke-Tests.ps1 -Path tests/Report.Tests.ps1, tests/Guidance.Tests.ps1, tests/Mask.Tests.ps1"`
Expected: FAIL, die Berichtsdaten haben kein Feld `classes`

- [ ] **Step 3: Umsetzen** – Bericht, Anleitung, Kopiertext, Katalog der Anleitung, Schlüsselwortfelder, Bestand; in `docs/guidance/quellen.md` die zwei Dokumente der neuen Schritte im bestehenden Abschnitt des Herstellers.

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/New-WorkerPerfReport.ps1 src/WorkerPerf.Guidance.ps1 src/guidance.de.json src/WorkerPerf.Mask.ps1 docs/guidance/quellen.md tests/
git commit -m "Put the cause class into the report data, the guide and the copy text" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TebhPvsTuNpmYXDmJ3hXkB"
```

---

### Task 7: Seite des normalen Berichts – Zeile „Einordnung“ und drei Kacheln

**Files:**
- Modify: `src/report-template.html`, `tests/TestHelpers.ps1` (`New-TestReports`: `report-causes.html` aus dem Drehbuch `Ursachen`, `report-old.html` aus `New-OldCaptureCopy` der Stunde), `tests/report-browser.js`

**Interfaces:**
- Consumes: Task 6 (Felder `classes`, `unchecked`, `classLine`, `host.*`, `sizing`).
- Produces: in `renderIncident` im Abschnitt „Wer oder was hat es verursacht“ eine Zeile `<p class="classline">` mit `classLine` und je Klasse einem Verweis auf ihre Quellen (Titel aus `sizing.sources`), auch bei Vorfällen ohne Engpass (der Abschnitt entsteht dann für diese Zeile); in `incEntry` eine Zeile „Einordnung: <Bezeichnungen>“; in `renderTiles` drei Kacheln nach den bisherigen:
  - `data-info="coremax"` „Stärkster Kern“: Max und P95 im Zeitraum; Status `1` (▲ Prüfen), wenn P95 ≥ `sizing.coreBusyNow` und P95 von `host.cpu` < Soll von `cpu.host`, sonst `0`.
  - `data-info="corebusy"` „Kerne voll“: Max und P95 „von <Kerne>“, Untertitel „über <coreBusyPct> %“; Status `1`, wenn P95 = Zahl der Kerne (alle voll, SZ-47), sonst `0`.
  - `data-info="perf"` „Leistungsanteil“ (Klasse `info`, „ohne Bewertung“, ohne Statusmarke; Titel mit `sizing.signals['cpu.perf'].note` und der geleisteten Arbeit).
  - Nicht gemessen (`sizing.measured.*` falsch): Wert „–“ und „nicht gemessen (ältere Aufzeichnung oder Zähler fehlt)“.

- [ ] **Step 1: Die fehlschlagenden Prüfungen schreiben** (`tests/report-browser.js`, neue Funktion `checkClasses` in `PER_SCHEME`)

```js
async function checkClasses(browser, dir, scheme) {                // Groesse: Einordnung und Kacheln
  const { page, D } = await open(browser, path.join(dir, 'report-causes.html'), scheme);
  for (const inc of D.incidents.filter((i) => i.classLine)) {
    const v = await openIncident(page, inc.id), t = await v.locator('.iv-cause .classline').innerText();
    ok(t.startsWith('Einordnung: ') && t.includes(inc.classes.length ? inc.classes[0].label : 'Nicht'), `Vorfall ${inc.id}: Einordnung in der Vorfallsansicht: ` + t);
  }
  const host = D.incidents.find((i) => (i.classes || []).some((c) => c.id === 'host'));
  ok(host && (await (await openIncident(page, host.id)).locator('.iv-todo li').first().innerText()).includes('VMware-Host'), 'der Schritt des VMware-Hosts steht vorne');
  await showExpert(page);
  ok((await page.locator(`#incList .inc[data-id="${host.id}"]`).innerText()).includes('Einordnung: VMware-Host'), 'Einordnung in der Vorfallsspalte');
  for (const k of ['coremax', 'corebusy', 'perf']) ok(await page.locator(`#tiles .tile[data-info="${k}"]`).count() === 1, 'Kachel ' + k);
  const perf = page.locator('#tiles .tile[data-info="perf"]');
  ok((await perf.innerText()).includes('ohne Bewertung') && await perf.locator('.status').count() === 0, 'Leistungsanteil ohne Bewertung');
  ok(/(◆|▲|●) (Handeln|Prüfen|In Ordnung)/.test(await page.locator('#tiles .tile[data-info="coremax"]').innerText()), 'Statusmarke als Symbol und Wort');
  ok(page.errors.length === 0 && page.requests.every((u) => u.startsWith('file:')), 'ohne Skriptfehler und Anfragen: ' + page.errors.join(' | '));
  await page.close();
  const old = await openExpert(browser, path.join(dir, 'report-old.html'), scheme);
  ok((await old.page.locator('#tiles .tile[data-info="coremax"]').innerText()).includes('nicht gemessen'), 'aeltere Aufzeichnung: nicht gemessen');
  await old.page.close();
}
```

In `checkWording` laufen die Texte `classLine`, `classes[].reason` und `classes[].direction` aller Testberichte durch `hostWords` (kein „Host“ außer „VMware-Host“).

- [ ] **Step 2: Prüfungen ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/New-TestReports.ps1 -OutDir <workspace>/scratch/wp-reports; node tests/report-browser.js <workspace>/scratch/wp-reports --scheme light --only checkClasses,checkWording`
Expected: Fehler in `checkClasses` (keine Zeile `.classline`)

- [ ] **Step 3: Seite umsetzen** (Werte der Berichtsdaten als Text, nie als Markup; schmale Breite: die Zeile bricht um)

- [ ] **Step 4: Prüfen**

Run: `node tests/report-browser.js <workspace>/scratch/wp-reports --scheme light` und `… --scheme dark`, danach `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `browser checks passed: <n>` in beiden Teilen, `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/report-template.html tests/report-browser.js tests/TestHelpers.ps1
git commit -m "Show the cause class in the incident view and the core tiles in the expert view" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TebhPvsTuNpmYXDmJ3hXkB"
```

## Teil B – Größenbericht (Tasks 8–10)

### Task 8: Auswertung über mehrere Aufzeichnungen und Hochrechnung

**Files:**
- Modify: `src/WorkerPerf.Sizing.ps1`
- Test: `tests/Sizing.Tests.ps1`

**Interfaces:**
- Consumes: Task 1 (Katalog), Task 5 (`Get-WorkerPerfRunAnalysis`, `Get-WorkerPerfPercentile`, `Classes` je Vorfall).
- Produces:
  - `Get-WorkerPerfRunServer([string]$Path) -> @{ Path; Server; StartMs; HealthOnly }` (nur `meta.json`).
  - `Assert-WorkerPerfSameServer([object[]]$Runs)` – die eine Stelle der Prüfung (Entwurf 4.3, 6.5): vergleicht `Server` ohne Rücksicht auf die Schreibweise mit dem der ersten; sonst `throw` mit `Die Aufzeichnung '<Path>' stammt vom Server '<Server>', die erste von '<Server0>'. Der Groessenbericht vergleicht nur Aufzeichnungen desselben Servers; der Vergleich verschiedener Server ist ein spaeterer Baustein.`
  - `Get-WorkerPerfMainTicks($Model, [double]$SessionPct) -> int[]` – Takte, deren Sitzungszahl (die des letzten Schnappschusses an oder vor dem Takt, vor dem ersten der erste) mindestens `SessionPct` % der höchsten Sitzungszahl der Aufzeichnung ist; Spitze 0 → keine.
  - `Get-WorkerPerfSizingRun -Analysis -Path -Sizing -> run` mit `Path; Server; StartMs; EndMs; DurationMin; EndReason; HealthOnly; Cores; RamMB; MainTicks; MainHours; Cpu @{ Peak; P95 }; Queue @{ Peak; P95 } (je CPU); Commit @{ PeakMB; P95MB; PeakPctRam }; SessionsPeak; MainCpu [double[]]; MainSessions [double[]]; CommitMaxMainMB; Classes (Kennung → Zahl der Vorfälle); Bottlenecks @(@{ Id; StartMs; EndMs; Lead; ClassIds; App }); Health (Werte des Zustandsbilds nach `Sizing.Evidence` oder `$null`)`. Ein Schnelllauf hat nur die Kopffelder und `Health`.
  - `Group-WorkerPerfSizingRuns([object[]]$Runs, [ValidateSet('time')][string]$Axis = 'time') -> @(@{ Key; Runs })` – Achse „Zeit“: eine Gruppe je Server (Phase 1: eine), Aufzeichnungen nach `StartMs`.
  - `Get-WorkerPerfCpuNeed([int]$Cores, [double]$Load, [double]$Target, [double]$Factor) -> double` = `Cores · (Load / Target)^(1 / log2(Factor))`.
  - `Get-WorkerPerfEvenUp([double]$Value) -> int` = 2 · ⌈round(Value, 6) / 2⌉.
  - `Get-WorkerPerfCpuRange([int]$Cores, [double]$Load, [double]$Target, $Sizing) -> @{ Low; High }` (Low mit `scalingHigh`, High mit `scalingLow`).
  - `Get-WorkerPerfCpuDecision -Recurring [string[]] -Seen [string[]] -Load [double] -Target [double] -Cores [int] -SessionsPeak [int] -HasMainTime [bool] -Sizing -> @{ Kind; Low; High; Sessions; Cause; Hints = [string[]] }` – Reihenfolge (Entwurf 6.3): ohne Hauptzeit `noMainTime`; `host` wiederkehrend → `host`; Load ≤ Target → `enough`; `capacity` wiederkehrend → `range` (High > `vcpuMax` → `scaleOut` mit `Sessions` = ⌊SessionsPeak · Target / Load⌋, ohne Low/High; High > `vcpuScaleOut` → Hinweis `scaleOutToo`; `singlecore` wiederkehrend → Hinweis `singlecoreToo`; `host` gesehen, nicht wiederkehrend → `hostOnce`; immer `numa`); sonst `other` mit `Cause` = erste wiederkehrende Klasse aus `singlecore`, `app`, `oneoff` (oder `''`). Bei `host` immer Hinweis `hostCheck`.
  - `Get-WorkerPerfRamTarget([double]$CommitMB, $Sizing) -> int` = `memStepGB` · ⌈(CommitMB / (memTargetPct/100)) / 1024 / memStepGB⌉.
  - `Get-WorkerPerfMemoryDecision -Recurring [string[]] -CommitMaxMB [double] -RamMB [double] -Sizing -> @{ Kind ('more'|'pagefile'|'app'|'enough'); TargetGB; Hints }` – `mem.capacity` wiederkehrend → `more` (Hinweise `memPerSession`, `commitAboveRam`); `mem.commit` → `pagefile`; `mem.app` → `app`; sonst `enough` (Hinweis `commitAboveRam`, wenn CommitMaxMB > RamMB).
  - `Get-WorkerPerfSizingSummary -Group -Sizing -> summary` mit `Server; Runs (alle, nach Beginn); LoadRuns (ohne Schnellläufe); Recurring (Klasse → Zahl der Aufzeichnungen, nur wiederkehrende); Seen (Klasse → Zahl); Load (L, P95 der gepoolten Hauptzeit); Peak (höchste Spitze); Target; SessionsPeak; CommitMaxMB; Cores; RamMB (der letzten Aufzeichnung mit Messung); SizeChanged; Sizes; MainHours; TotalHours; LowMeasure; Cpu (Entscheidung); Memory (Entscheidung); Result @{ Key ('recurring'|'once'|'none'); Class; Resource; Count; Total }; Evidence (das neueste Zustandsbild aller Aufzeichnungen, Schnellläufe eingeschlossen)`. Wiederkehrend: Zahl / Zahl der `LoadRuns` · 100 ≥ `recurringPct`. `LowMeasure` = weniger als `minRecordings` Aufzeichnungen mit Messung oder weniger als `minMainHours` Stunden Hauptzeit.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`New-RunRecord([hashtable]$Change)` = Aufzeichnung mit Messung, 8 vCPU, 65536 MB, Server `SIM-VDA01`, vier Stunden Hauptzeit, keine Klasse)

```powershell
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
        $e = Get-WorkerPerfMemoryDecision -Recurring @() -CommitMaxMB 70000 -RamMB 65536 -Sizing $Sz; $e.Kind | Should -Be 'enough'; $e.Hints | Should -Contain 'commitAboveRam'
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
        $s.Recurring.Contains('capacity') | Should -BeTrue
        $t = Get-WorkerPerfSizingSummary -Group @{ Key = 'x'; Runs = @((New-RunRecord @{ Classes = @{ capacity = 1 } }), (New-RunRecord @{}), (New-RunRecord @{})) } -Sizing $Sz
        $t.Recurring.Contains('capacity') | Should -BeFalse; $t.Seen['capacity'] | Should -Be 1
    }
    It 'merkt wenig Messzeit unter drei Aufzeichnungen oder zwoelf Stunden Hauptzeit' {
        (Summary-Of 3 4.0).LowMeasure | Should -BeFalse; (Summary-Of 2 10.0).LowMeasure | Should -BeTrue; (Summary-Of 3 3.96).LowMeasure | Should -BeTrue
    }
    It 'nennt einen Wechsel der Groesse und rechnet von der letzten Aufzeichnung' {                 # Review Focus 2
        $s = Get-WorkerPerfSizingSummary -Group @{ Key = 'x'; Runs = @((New-RunRecord @{ StartMs = 1; Cores = 8 }), (New-RunRecord @{ StartMs = 2; Cores = 8 }), (New-RunRecord @{ StartMs = 3; Cores = 10 })) } -Sizing $Sz
        $s.SizeChanged | Should -BeTrue; $s.Cores | Should -Be 10
    }
    It 'zaehlt einen Schnelllauf nicht fuer die Last' {
        $s = Get-WorkerPerfSizingSummary -Group @{ Key = 'x'; Runs = @((New-RunRecord @{}), (New-RunRecord @{ HealthOnly = $true })) } -Sizing $Sz
        @($s.LoadRuns).Count | Should -Be 1; @($s.Runs).Count | Should -Be 2
    }
    It 'prueft denselben Server an einer Stelle, ohne Ruecksicht auf die Schreibweise' {               # Review Focus 3
        { Assert-WorkerPerfSameServer @(@{ Path = 'a'; Server = 'SIM-VDA01' }, @{ Path = 'b'; Server = 'sim-vda01' }) } | Should -Not -Throw
        { Assert-WorkerPerfSameServer @(@{ Path = 'a'; Server = 'SIM-VDA01' }, @{ Path = 'C:\x\b'; Server = 'SIM-VDA02' }) } | Should -Throw "*'C:\x\b'*SIM-VDA02*spaeterer Baustein*"
    }
    It 'ordnet die Aufzeichnungen auf der Achse Zeit nach ihrem Beginn' {                            # Review Focus 3
        $g = @(Group-WorkerPerfSizingRuns @((New-RunRecord @{ StartMs = 3 }), (New-RunRecord @{ StartMs = 1 }), (New-RunRecord @{ StartMs = 2 })) 'time')
        $g.Count | Should -Be 1; @($g[0].Runs.StartMs) | Should -Be @(1, 2, 3)
    }
}
```

`Summary-Of([int]$Runs, [double]$HoursEach)` bildet eine Zusammenfassung aus `$Runs` gleichen Aufzeichnungen mit je `$HoursEach` Stunden Hauptzeit; `New-SessionModel` ein Modell mit `Tick.N`, `Tick.ElapsedSec`, `Snap.Sessions`, `Snap.TickPos`.

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Sizing.Tests.ps1`
Expected: FAIL, `Get-WorkerPerfCpuNeed` ist nicht definiert

- [ ] **Step 3: Funktionen umsetzen** (rein rechnend außer `Get-WorkerPerfRunServer` und `Get-WorkerPerfSizingRun`; keine Texte, nur Kennungen von Entscheidungen und Hinweisen)

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Sizing.Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Sizing.ps1 tests/Sizing.Tests.ps1
git commit -m "Add the main time, recurring causes and the marked sizing projection" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TebhPvsTuNpmYXDmJ3hXkB"
```

---

### Task 9: Skript `New-WorkerPerfSizingReport.ps1` – Berichtsdaten, Kopiertext, Maskierung

**Files:**
- Create: `src/New-WorkerPerfSizingReport.ps1`, `src/WorkerPerf.Page.ps1`, `src/sizing-template.html` (Gerüst: Titel, Platzhalter `<script id="wp-data" type="application/json">null</script>`, Ausgabe der Daten als Text; die Seite folgt in Task 10), `tests/SizingReport.Tests.ps1`, `tests/SizingMaskCensus.json`
- Modify: `src/WorkerPerf.Sizing.ps1` (Berichtsdaten, Kopiertext), `src/New-WorkerPerfReport.ps1` (JSON-Schreiber aus `WorkerPerf.Page.ps1`, `Complete-Report` schreibt über `Write-WorkerPerfPage`), `src/WorkerPerf.Mask.ps1` (`New-WorkerPerfMask -Path [string[]]`, Schlüsselwortfelder), `tests/Mask.Tests.ps1`, `tests/TestHelpers.ps1` (`New-SizingReports`)

**Interfaces:**
- Consumes: Task 8 (alle Funktionen), Task 5 (`Get-WorkerPerfRunAnalysis`, `Get-WorkerPerfClassOut`), `Format-WorkerPerfCopyLines`, `ConvertTo-WorkerPerfAnonymousText`, `Protect-WorkerPerfReportData`, `Save-WorkerPerfMaskMap`, `Read-WorkerPerfApps`, `Read-WorkerPerfGuidance`.
- Produces:
  - `src/WorkerPerf.Page.ps1`: `Format-JsonString`, `Format-JsonNumber`, `ConvertTo-JsonText` (unverändert verschoben, mit `[Globalization.CultureInfo]::InvariantCulture` statt `$inv`), `Write-WorkerPerfPage([string]$TemplateFile, $Data, [string]$OutFile)` (Platzhalter ersetzen, über eine temporäre Datei schreiben, wie bisher in `Complete-Report`).
  - `New-WorkerPerfMask -Path [string[]] …`: Aufzeichnungen in der gegebenen Reihenfolge, je Aufzeichnung die bisherigen Schritte; mit einem Pfad unverändert.
  - `New-WorkerPerfSizingData -Summary -Sizing -Commands [string[]] -Generated [long] -> [ordered]` (Berichtsdaten, Felder unten) und `Get-WorkerPerfSizingCopyParagraphs($Data, $Sizing) -> string[]`.
  - Aufruf (Entwurf 6.1): `New-WorkerPerfSizingReport.ps1 -Path <string[]> [-OutFile] [-Mask Personen|Alles] [-MaskMapFile] [-SizingFile] [-ThresholdFile] [-GuidanceFile] [-AppsFile] [-RoleFile]`. Vorgabe `-OutFile`: `<Ordner über der ersten Aufzeichnung>\groesse-<yyyyMMdd-HHmmss>.html`. Prüfungen vor jedem Auswerten, in dieser Reihenfolge: Ordner vorhanden; derselbe Ordner zweimal → `Die Aufzeichnung '<Ordner>' ist zweimal angegeben.`; Kataloge und Listen lesbar; `Assert-WorkerPerfSameServer`; mindestens eine Aufzeichnung mit Messung, sonst `Keine der Aufzeichnungen enthaelt eine Messung; ein Schnelllauf (-HealthOnly) zaehlt nicht fuer die Last.`; mit `-Mask Alles` darf der Dateiname den Server nicht nennen; `-MaskMapFile` wie im normalen Bericht. Konsole: `Groessenbericht erstellt in {0} s: {1}` und eine Zeile je Empfehlung (Ressource und Richtung).
  - Befehl je Aufzeichnung: `.\New-WorkerPerfReport.ps1 -Path '<Ordner>'`, dazu `-ThresholdFile`, `-RoleFile`, `-GuidanceFile`, `-AppsFile`, `-SizingFile`, wo sie angegeben sind.
  - Berichtsdaten: `meta { server, axis ('time'), from, to, recordings, quick, durationMin, mainHours, cores, ramGB, sizes [{ cores, ramGB }], sizeChanged, lowMeasure, catalogueVersion, target, load, peak, sessionsPeak, generated, mask }`; `grades`; `result { text, key }`; `recommendations [{ resource ('cpu'|'memory'|'host'|'singlecore'), status ('act'|'check'|'ok'), direction, reason, projection ({ kind, low, high, sessions, unit, text } oder null), assumptions [text], hints [text], sources [ids], reliability }]`; `runs [{ index, server, folder, start, end, durationMin, endReason, healthOnly, cores, ramGB, mainHours, cpu { peak, p95 }, queue { peak, p95 }, commit { peakGB, p95GB, peakPct }, sessionsPeak, command, classIds }]`; `bottlenecks [{ run, id, start, end, lead, classIds, label, app }]`; `recurring [{ id, label, count, of }]`; `usersPerVcpu { value, sessionsPeak, cores, note, limits [{ id, label, perVcpu, sessions }] }`; `scatter { cpu [], sessions [], target }` (höchstens 2000 Punkte, jeder k-te Takt der Hauptzeit); `evidence [{ id, label, value }]`; `sources [{ id, title, url, date, kind }]`; `copy { named, anonymous }`.
  - Empfehlung `cpu`: Status `act` bei `range`/`scaleOut`/`host`, `ok` bei `enough`, sonst `check`; jede `projection` hat einen Text mit „Schätzung“; jede Empfehlung mit Projektion hat die vier Annahmen und `pilot` in `assumptions`; `reliability` aus `reliability` und, bei `LowMeasure`, `hint.lowMeasure` mit „wenig Messzeit“. `host` und `singlecore` stehen nur, wo die Klasse gesehen wurde; `singlecore` nennt `hint.powerPlan` mit dem Energiesparplan aus `evidence`, wo bekannt.
  - `$script:WorkerPerfMaskKeywordFields` + `'axis'`, `'classIds'`, `'recommendations.status'`, `'projection.kind'`, `'meta.catalogueVersion'`, `'result.key'`. `tests/SizingMaskCensus.json` ordnet jedes Textfeld ein: `meta.server`, `runs[].server`, `runs[].folder`, `evidence[].value` „name“; `runs[].command`, alle Sätze und Bezeichnungen „composed“; `bottlenecks[].app` „name“ (Prozessname, durch die Maske geschützt); die übrigen „keyword“.
  - `New-SizingReports([string]$OutDir) -> @{ Runs; Report; Masked; MaskedP; Enough }` (Testhelfer: `sizing.html` aus den fünf Tagen und dem Schnelllauf, `sizing-masked.html` mit `-Mask Alles`, `sizing-personen.html` mit `-Mask Personen`, `sizing-enough.html` mit einem Katalog `minRecordings` 1, `minMainHours` 0.1).

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/SizingReport.Tests.ps1`; `BeforeAll`: `$R = New-SizingReports (Join-Path $TestDrive 'sz')`, `$D = Get-ReportData $R.Report`)

```powershell
Describe 'Groessenbericht aus fuenf Tagen und einem Schnelllauf' {
    It 'zaehlt den Schnelllauf nicht fuer die Last und nennt den Server' {
        $D.meta.server | Should -Be 'SIM-VDA01'; $D.meta.recordings | Should -Be 5; $D.meta.quick | Should -Be 1; $D.meta.axis | Should -Be 'time'
        @($D.runs).Count | Should -Be 6; @($D.runs | Where-Object healthOnly).Count | Should -Be 1
    }
    It 'findet die wiederkehrende Kapazitaet und den einmaligen VMware-Host' {
        ($D.recurring | Where-Object id -eq 'capacity').count | Should -Be 4; ($D.recurring | Where-Object id -eq 'capacity').of | Should -Be 5
        @($D.recurring | Where-Object id -eq 'host').Count | Should -Be 0
        $D.result.text | Should -Match '^Wiederkehrender CPU-Engpass aus Kapazität in 4 von 5 Aufzeichnungen; typische Spitzenlast \d+(,\d)? % bei 31 Sitzungen\.$'
    }
    It 'rechnet die Spanne mit der Formel des Entwurfs aus L und T' {
        $cpu = $D.recommendations | Where-Object resource -eq 'cpu'; $r = Get-WorkerPerfCpuRange 8 $D.meta.load 75 $Sz
        $cpu.projection.low | Should -Be $r.Low; $cpu.projection.high | Should -Be $r.High; $cpu.status | Should -Be 'act'
        $cpu.hints -join ' ' | Should -Match 'VMware-Host'
    }
    It 'kennzeichnet jede Zahl der Hochrechnung als Schaetzung mit Annahmen' {
        foreach ($r in @($D.recommendations | Where-Object { $null -ne $_.projection })) {
            $r.projection.text | Should -Match 'Schätzung'; @($r.assumptions).Count | Should -Be 5
            $r.assumptions[-1] | Should -Be 'Vor einem Umbau mit einem Pilot oder Lasttest bestätigen.'
        }
    }
    It 'sagt wenig Messzeit an jeder Empfehlung, mit genug Messzeit nicht' {
        $D.meta.lowMeasure | Should -BeTrue; foreach ($r in $D.recommendations) { $r.reliability | Should -Match 'wenig Messzeit' }
        $e = Get-ReportData $R.Enough; $e.meta.lowMeasure | Should -BeFalse; foreach ($r in $e.recommendations) { $r.reliability | Should -Not -Match 'wenig Messzeit' }
    }
    It 'nennt je Aufzeichnung den Befehl ihres Berichts' { $D.runs[0].command | Should -Be (".\New-WorkerPerfReport.ps1 -Path '{0}'" -f $R.Runs.Days[0]) }
    It 'fuehrt Sitzungen je vCPU gegen die Obergrenzen 6/4/2/1 als Einordnung' {
        $D.usersPerVcpu.sessionsPeak | Should -Be 31; @($D.usersPerVcpu.limits.perVcpu) | Should -Be @(6, 4, 2, 1); @($D.usersPerVcpu.limits.sessions) | Should -Be @(48, 32, 16, 8)
    }
    It 'gibt den Kopiertext mit und ohne Namen' { $D.copy.named | Should -Match 'SIM-VDA01'; $D.copy.anonymous | Should -Not -Match 'SIM-VDA01' }
}
Describe 'Groessenbericht: Abbrueche und Grenzfaelle' {
    It 'bricht bei verschiedenen Servern ab und nennt die Aufzeichnung' {
        $other = Copy-SimRun $R.Runs.Days[1] (Join-Path $TestDrive 'other'); $mf = Join-Path $other 'meta.json'
        [IO.File]::WriteAllText($mf, [IO.File]::ReadAllText($mf).Replace('SIM-VDA01', 'SIM-VDA02'))
        $out = Join-Path $TestDrive 'nie.html'
        { & $SizingScript -Path $R.Runs.Days[0], $other -OutFile $out } | Should -Throw "*'$other'*SIM-VDA02*spaeterer Baustein*"
        Test-Path $out | Should -BeFalse
    }
    It 'lehnt dieselbe Aufzeichnung zweimal ab' { { & $SizingScript -Path $R.Runs.Days[0], $R.Runs.Days[0] } | Should -Throw '*zweimal*' }      # Review Focus 3
    It 'lehnt nur Schnelllaeufe ab' { { & $SizingScript -Path $R.Runs.Quick } | Should -Throw '*keine Messung*' }                                  # Review Focus 3
    It 'nimmt die Aufzeichnungen in beliebiger Reihenfolge und eine aeltere dazu' {                                                              # Review Focus 2, 3
        $old = New-OldCaptureCopy $R.Runs.Days[2] (Join-Path $TestDrive 'old3')
        $f = Join-Path $TestDrive 'mix.html'; & $SizingScript -Path $R.Runs.Days[4], $old, $R.Runs.Days[0] -OutFile $f 6>$null | Out-Null
        $d = Get-ReportData $f; @($d.runs.start) | Should -Be @(@($d.runs.start) | Sort-Object); $d.meta.recordings | Should -Be 3
    }
}
Describe 'Groessenbericht maskiert' {
    It 'enthaelt bei Alles keinen Namen der Aufzeichnungen, bei Personen den Server' {
        # Kopien der fuenf Tage in den Ordner <TestDrive>/SIM-CANARY01_runs, Computer in meta.json SIM-CANARY01
        $f = New-CanarySizing -Mask Alles; $t = [IO.File]::ReadAllText($f)
        $t.Contains('SIM-CANARY01') | Should -BeFalse; (Get-ReportData $f).meta.mask | Should -Be 'Alles'
        [IO.File]::ReadAllText((New-CanarySizing -Mask Personen)).Contains('SIM-CANARY01') | Should -BeTrue
    }
    It 'ordnet jedes Textfeld der Berichtsdaten im Bestand ein' {
        $census = Get-Content (Join-Path $PSScriptRoot 'SizingMaskCensus.json') -Raw | ConvertFrom-Json
        foreach ($p in @(Get-StringFieldPaths $D)) { $census.fields.PSObject.Properties.Name | Should -Contain $p -Because $p }
    }
    It 'lehnt bei Alles einen Dateinamen mit dem Server ab' { { & $SizingScript -Path $R.Runs.Days -Mask Alles -OutFile (Join-Path $TestDrive 'SIM-VDA01.html') } | Should -Throw '*nennt den Server*' }
    It 'schreibt die Zuordnung mit -MaskMapFile' { (Get-Content (New-CanarySizing -Mask Alles -MapFile) -Raw | ConvertFrom-Json).entries.name | Should -Contain 'SIM-CANARY01' }
}
```

Hilfen im `BeforeAll`: `$SizingScript` = Pfad von `src/New-WorkerPerfSizingReport.ps1`; `$Sz` (Katalog); `New-CanarySizing -Mask <Stufe> [-MapFile] -> string` kopiert die fünf Tage nach `<TestDrive>/SIM-CANARY01_runs/`, setzt in jeder `meta.json` `Computer` auf `SIM-CANARY01`, ruft das Skript mit der Stufe (und `-MaskMapFile`) und liefert den Bericht bzw. die Zuordnungsdatei.

`tests/Mask.Tests.ps1`: `New-WorkerPerfMask -Path <a>, <b>` – die Namen von `b` folgen nach denen von `a` (eine Kopie mit einem Benutzer mehr: dessen Ersatzname hat die nächste Nummer); mit einem Pfad dieselben Ersatznamen wie bisher. `Get-StringFieldPaths` ist die Pfadbildung des bestehenden Bestandstests, in `tests/TestHelpers.ps1` gehoben.

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/SizingReport.Tests.ps1`
Expected: FAIL, das Skript fehlt

- [ ] **Step 3: JSON-Schreiber nach `src/WorkerPerf.Page.ps1`** und den normalen Bericht darauf umstellen; danach `pwsh -NoProfile -Command "& ./tests/Invoke-Tests.ps1 -Path tests/Report.Tests.ps1, tests/Mask.Tests.ps1"` → `Failed: 0` (der bytegleiche Bericht bleibt gleich).

- [ ] **Step 4: Maske über mehrere Aufzeichnungen, `New-WorkerPerfSizingData`, Kopiertext, Skript, Gerüst der Vorlage umsetzen** (Kopiertext: `copy.head`, Ergebnissatz, je Empfehlung Richtung, Hochrechnung und Annahmen; ohne Namen über `ConvertTo-WorkerPerfAnonymousText` mit einer Maske der Stufe Alles über alle Pfade; gebrochen mit `Format-WorkerPerfCopyLines`; mit `-Mask` wie im normalen Bericht erst nach dem Ersetzen)

- [ ] **Step 5: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 6: Commit**

```bash
git add src/New-WorkerPerfSizingReport.ps1 src/WorkerPerf.Page.ps1 src/sizing-template.html src/WorkerPerf.Sizing.ps1 src/New-WorkerPerfReport.ps1 src/WorkerPerf.Mask.ps1 tests/
git commit -m "Add the sizing report over several captures of one server" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TebhPvsTuNpmYXDmJ3hXkB"
```

---

### Task 10: Seite des Größenberichts

**Files:**
- Modify: `src/sizing-template.html`, `tests/TestHelpers.ps1` (`New-TestReports` ruft `New-SizingReports $OutDir`), `tests/report-browser.js`

**Interfaces:**
- Consumes: Task 9 (Berichtsdaten, `New-SizingReports`).
- Produces: eine selbstständige Seite im Stil der geführten Ansicht (hell, folgt nicht dem Farbschema des Systems), keine externen Anfragen, mit Druckansicht. Abschnitte in der Reihenfolge von Entwurf 6.2: Kopf (Server, Zeitraum, Zahl der Aufzeichnungen und Schnellläufe, Gesamtdauer, vCPU und RAM je Aufzeichnung, Hinweis bei Wechsel der Größe, Maskierungsvermerk), Ergebnis in einem Satz, Empfehlungen (je Karte: Statusmarke als Symbol und Wort, Richtung, Begründung, Hochrechnung in einem Kasten mit dem Wort „Schätzung“, Annahmen, Hinweise, Quellen als Verweise, Belastbarkeit), Verlauf (SVG-Balken je Aufzeichnung für Spitze und P95 der CPU mit der Linie T; Tabelle Spitze/P95 von CPU, Warteschlange je CPU, zugesichertem Speicher, höchste Sitzungszahl; Engpässe mit Klasse; wiederkehrende Klassen), Sitzungen gegen CPU (SVG-Punktwolke der Hauptzeit mit der Linie T), Sitzungen je vCPU (Tabelle mit dem Satz `usersNote`), Belege aus dem Zustandsbild, Liste der Aufzeichnungen (Ordner, Beginn, Dauer, Ende-Grund, Befehl mit Knopf „Befehl kopieren“), Quellen, Kopiertext (Knöpfe „Empfehlungen kopieren“ und „ohne Namen“, wie im Bericht; im maskierten Bericht nur eine Fassung). Eine Spanne mit `low` = `high` erscheint als eine Zahl.
  - Prüffunktionen in `tests/report-browser.js`: `checkSizing` (`PER_SCHEME`), `checkSizingPrint` und `checkSizingWording` (`ONCE`).

- [ ] **Step 1: Die fehlschlagenden Prüfungen schreiben**

```js
async function checkSizing(browser, dir, scheme) {                  // Groessenbericht: Lesbarkeit, Statusmarken, schmale Breite
  const { page, D } = await open(browser, path.join(dir, 'sizing.html'), scheme);
  ok(page.errors.length === 0 && page.requests.every((u) => u.startsWith('file:')), 'ohne Skriptfehler und Anfragen: ' + page.errors.join(' | '));
  ok((await page.locator('#result').innerText()).trim() === D.result.text, 'Ergebnis in einem Satz');
  const cards = page.locator('#recommendations .rec');
  ok(await cards.count() === D.recommendations.length, 'eine Karte je Empfehlung');
  for (let i = 0; i < D.recommendations.length; i++) {
    const t = await cards.nth(i).innerText(), r = D.recommendations[i];
    ok(/(◆ Handeln|▲ Prüfen|● In Ordnung)/.test(t), 'Statusmarke als Symbol und Wort: ' + r.resource);
    if (r.projection) ok(t.includes('Schätzung') && t.includes('Vor einem Umbau mit einem Pilot oder Lasttest bestätigen.'), 'Hochrechnung gekennzeichnet: ' + r.resource);
    ok(t.includes('wenig Messzeit'), 'wenig Messzeit: ' + r.resource);
  }
  ok(await page.locator('#history svg rect.bar').count() === 2 * D.runs.filter((r) => !r.healthOnly).length, 'Balken je Aufzeichnung fuer Spitze und P95');
  ok(await page.locator('#scatter svg circle').count() === D.scatter.cpu.length && await page.locator('#scatter svg line.target').count() === 1, 'Punktwolke mit der Linie des Ziels');
  ok(await page.evaluate(() => getComputedStyle(document.body).backgroundColor) === 'rgb(255, 255, 255)', 'hell auch im dunklen Schema');
  for (const sel of ['#result', '#recommendations .rec p']) {
    const c = await page.locator(sel).first().evaluate((e) => [getComputedStyle(e).color, getComputedStyle(document.body).backgroundColor]);
    ok(contrast(c[0], c[1]) >= 4.5, 'Kontrast ' + sel);
  }
  await page.setViewportSize({ width: 360, height: 800 });
  ok(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), 'schmale Breite ohne seitliches Rollen');
  await page.close();
  const e = await open(browser, path.join(dir, 'sizing-enough.html'), scheme);
  ok(!(await e.page.locator('#recommendations').innerText()).includes('wenig Messzeit'), 'genug Messzeit: kein Hinweis');
  await e.page.close();
  const m = await open(browser, path.join(dir, 'sizing-masked.html'), scheme);
  ok(!(await m.page.locator('body').innerText()).includes('SIM-VDA01') && (await m.page.locator('header').innerText()).includes('maskiert'), 'maskiert: kein Servername, Vermerk im Kopf');
  await m.page.close();
}
async function checkSizingPrint(browser, dir, scheme) {             // Groessenbericht: Druck
  const { page } = await open(browser, path.join(dir, 'sizing.html'), scheme);
  await page.emulateMedia({ media: 'print' });
  for (const id of ['result', 'recommendations', 'history', 'scatter', 'users', 'runs', 'sources']) ok(await page.locator('#' + id).isVisible(), 'im Druck sichtbar: ' + id);
  ok(!(await page.locator('button').first().isVisible()), 'Knoepfe nicht im Druck');
  await page.close();
}
async function checkSizingWording(browser, dir, scheme) {           // Groessenbericht: Wortregeln
  const src = fs.readFileSync(path.join(dir, 'sizing.html'), 'utf8'), tag = '<script id="wp-data" type="application/json">';
  const own = src.substring(0, src.indexOf(tag)) + src.substring(src.indexOf('</script>', src.indexOf(tag)));
  ok(!/(?<![A-Za-zÄÖÜäöüß])Worker(?!Perf)/.test(own) && hostWords(own).length === 0, 'Seite: nie "Worker", "Host" nur als VMware-Host');
  const { page, D } = await open(browser, path.join(dir, 'sizing.html'), scheme), shown = await page.locator('body').innerText();
  ok(hostWords(shown).length === 0 && shown.includes('Server'), 'gezeigte Texte: "Server", "Host" nur als VMware-Host: ' + hostWords(shown).join(' | '));
  await page.close();
}
```

`hostWords` wird dafür aus `checkWording` auf die oberste Ebene gehoben (unverändert). Grenzfall (Review Focus 5) in `checkSizing`: eine gepatchte Kopie (`patched(dir, 'sizing.html', 'sizing-one.html', (J) => { … projection.low = projection.high = 8 … })`) zeigt „etwa 8 statt“ und nie „8 bis 8“.

- [ ] **Step 2: Prüfungen ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/New-TestReports.ps1 -OutDir <workspace>/scratch/wp-reports; node tests/report-browser.js <workspace>/scratch/wp-reports --scheme light --only checkSizing,checkSizingPrint,checkSizingWording`
Expected: Fehler in `checkSizing` (kein `#result`)

- [ ] **Step 3: Seite umsetzen** (Farben und Statusmarken wie die geführte Ansicht; Werte der Daten nur als Text; SVG ohne Bibliothek)

- [ ] **Step 4: Prüfen**

Run: `node tests/report-browser.js <workspace>/scratch/wp-reports --scheme light` und `… --scheme dark`, danach `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `browser checks passed: <n>` in beiden Teilen, `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/sizing-template.html tests/report-browser.js tests/TestHelpers.ps1
git commit -m "Lay out the sizing report as a page of its own with charts and print view" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TebhPvsTuNpmYXDmJ3hXkB"
```

## Teil C – Prüflauf, Beschreibung, erster echter Lauf (Tasks 11–13)

### Task 11: Prüfskript – die neuen Zähler

**Files:**
- Modify: `src/Test-WorkerPerfSources.ps1` (`$script:Catalogue`), `src/texts.de.json` (`source.perf.cpu.cores`, `source.perf.cpu.frequency`), `docs/vda-probe/README.md` (wo die Prüfungen aufgezählt sind)
- Test: `tests/Sources.Tests.ps1`

**Interfaces:**
- Consumes: Task 2 (Signalkennungen).
- Produces: zwei Prüfungen nach `perf.cpu` und eine Erweiterung (Entwurf 7, 10):
  - `@{ Id = 'perf.cpu.cores'; Signals = @('cpu.coreMax', 'cpu.coreBusy'); Title = 'CPU-Auslastung je logischem Prozessor und Namen der Instanzen'; Run = 'Invoke-ProbePerfCheck'; Perf = @{ Category = 'Processor Information'; Counters = @('% Processor Time'); Instances = 'all'; MaxInstances = 0 } }`
  - `@{ Id = 'perf.cpu.frequency'; Signals = @('cpu.perf', 'cpu.utility'); Title = 'Leistungsanteil und geleistete Arbeit der CPU'; Run = 'Invoke-ProbePerfCheck'; Perf = @{ Category = 'Processor Information'; Counters = @('% Processor Performance', '% Processor Utility'); Instances = 'all'; MaxInstances = 4 } }`
  - `perf.memory`: `Counters` + `'Pages Output/sec'`, `Signals` + `'mem.pagesout'`, Titel „Arbeitsspeicher, Zusagen, Seitenein- und -ausgaben“.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/Sources.Tests.ps1`, Aussagen geändert: zwei Prüfungen mehr)

```powershell
It 'listet die Pruefungen ohne Systemzugriff' {
    $Checks.Id | Should -Be @('system', 'process.snapshot', 'sessions.wts', 'services.map', 'perf.cpu', 'perf.cpu.cores', 'perf.cpu.frequency', 'perf.queue', 'perf.steal', 'perf.memory',
        'perf.disk.total', 'perf.network', 'perf.volumes', 'perf.shares', 'perf.input.session', 'perf.input.process', 'perf.ica',
        'profile.volumes', 'events.defender', 'events.applocker', 'events.application', 'events.system', 'events.printservice',
        'events.smbclient', 'events.profileservice', 'events.session', 'print.drivers', 'print.queues', 'security.products', 'user.processes', 'endpoints')
}
It 'deckt jedes Signal ab, auch die neuen der Groesse' {
    $covered = @($Checks | ForEach-Object { $_.Signals })
    foreach ($id in 'cpu.host', 'cpu.queue', 'cpu.steal', 'mem.used', 'mem.commit', 'mem.pagesin', 'input.session', 'disk.latency', 'smb.latency', 'ica.rtt', 'ica.latency', 'probe.connect',
        'cpu.coreMax', 'cpu.coreBusy', 'cpu.perf', 'cpu.utility', 'mem.pagesout') { $covered | Should -Contain $id }
}
It 'liest ausgelagerte Seiten in der Pruefung des Arbeitsspeichers' {
    $entry = @(Get-ProbeCatalogueEntries) | Where-Object Id -eq 'perf.memory'
    $entry.Perf.Counters | Should -Contain 'Pages Output/sec'
}
```

`Get-ProbeCatalogueEntries` ist die schon im Test vorhandene Auswertung von `$script:Catalogue` aus dem Syntaxbaum, als Funktion im `BeforeAll`.

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Sources.Tests.ps1`
Expected: FAIL, die Liste der Prüfungen ist kürzer

- [ ] **Step 3: Katalog des Prüfskripts und Texte ergänzen** (das Skript bleibt eine Datei; die Namen der Instanzen sind keine schützenswerten Namen)

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/Test-WorkerPerfSources.ps1 src/texts.de.json docs/vda-probe/README.md tests/Sources.Tests.ps1
git commit -m "Probe the per-core, frequency and page output counters" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TebhPvsTuNpmYXDmJ3hXkB"
```

---

### Task 12: README, Hilfe und Demo-Seiten

**Files:**
- Modify: `README.md`, `pages/index.html`, `src/New-WorkerPerfReport.ps1` (nur die Hilfe), `src/Start-WorkerPerfCapture.ps1` (nur die Hilfe), `src/New-WorkerPerfSizingReport.ps1` (nur die Hilfe)
- Create: `pages/groesse.html`
- Nicht anfassen: der Code der Skripte.

**Interfaces:**
- Consumes: der fertige Baustein.
- Produces: README mit einem Abschnitt „Größe des Servers“: die Frage, die er beantwortet (Entwurf 1); die zehn Klassen mit Vorrang, je ein Satz „erkennbar an“ und „was hilft“; die neuen Werte (Entwurf 4.1, ohne neue Kategorie für `-Skip`, ältere Aufzeichnungen bleiben lesbar, `CoreBusyPct` in `meta.json`); der Größenbericht mit Aufruf und Beispiel (`.\New-WorkerPerfSizingReport.ps1 -Path D:\WorkerPerf\SIM-VDA01_20260101-080000, D:\WorkerPerf\SIM-VDA01_20260102-080000, …`), den Parametern, „derselbe Server“, dem Schnelllauf als Beleg, Hauptzeit, Hochrechnung mit Formel, dem Beispiel 8 vCPU, L 92 %, T 75 % → etwa 10 bis 12 vCPU, den Grenzen 16 und 24, Arbeitsspeicher C ÷ 0,8 auf volle 4 GB, „wenig Messzeit“, Kennzeichnung und Annahmen; der Katalog `src/sizing.de.json` mit `-SizingFile`, Arten und Quellen, Verweis auf `docs/guidance/quellen.md`; Maskierung; die Grenzen aus Entwurf 9; Phase 2 als späterer Baustein. Die Hilfe des Collectors nennt die neuen Werte, `CoreBusyPct`, `-SimulateScenario` und `-SimulateDay`; die Hilfe des Berichts `-SizingFile` und die Einordnung; die Hilfe des Größenberichts jeden Parameter mit Beispiel. Die Demo-Seiten sind aus der Simulation neu erzeugt.

- [ ] **Step 1: Prüfen, dass README und Demo veraltet sind**

Run: `pwsh -NoProfile -Command "(Select-String -Path README.md -Pattern 'New-WorkerPerfSizingReport' -SimpleMatch -Quiet); (Test-Path pages/groesse.html); (Select-String -Path pages/index.html -Pattern 'classLine' -SimpleMatch -Quiet)"`
Expected: `False`, `False`, `False`

- [ ] **Step 2: README und die Hilfe schreiben** (Wortregel: „Server“; Beispiele nur mit erfundenen Namen)

- [ ] **Step 3: Demo neu erzeugen**

```powershell
$run = .\src\Start-WorkerPerfCapture.ps1 -Simulate -DurationMinutes 60 -OutputPath .\demo
.\src\New-WorkerPerfReport.ps1 -Path $run -OutFile .\pages\index.html
$days = 1..5 | ForEach-Object { .\src\Start-WorkerPerfCapture.ps1 -Simulate -SimulateScenario Tag -SimulateDay $_ -DurationMinutes 60 -OutputPath .\demo }
.\src\New-WorkerPerfSizingReport.ps1 -Path $days -OutFile .\pages\groesse.html
```

`demo/` bleibt außerhalb des Repositorys.

- [ ] **Step 4: Prüfen**

Run: Step 1 erneut, danach `pwsh -NoProfile -File tests/Invoke-Tests.ps1` und die Browserprüfungen (beide Schemata)
Expected: `True`, `True`, `True`, `Failed: 0`, `browser checks passed: <n>`

- [ ] **Step 5: Commit**

```bash
git add README.md pages/index.html pages/groesse.html src/New-WorkerPerfReport.ps1 src/Start-WorkerPerfCapture.ps1 src/New-WorkerPerfSizingReport.ps1
git commit -m "Describe the cause classes and the sizing report, rebuild the demo pages" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TebhPvsTuNpmYXDmJ3hXkB"
```

---

### Task 13: Erster echter Lauf auf dem Test-Server und Anpassungsrunde

Diese Task ist der Schritt des Auftraggebers (Entwurf 10). Sie hat keinen Test vorab: ihr Ergebnis sind Befunde vom Server, aus denen genau eine Anpassungsrunde mit eigenen Tests entsteht. Nichts von dem, was der Lauf liefert, kommt in das Repository.

**Files:**
- Modify (Anpassungsrunde, je nach Befund): `src/WorkerPerf.Sources.Windows.ps1` (Erkennung der Gesamtinstanzen), `tests/WindowsStandIns.ps1`, `tests/WindowsSource.Tests.ps1`, `src/sizing.de.json` (Werte, Notiz zu `cpu.perf`/`cpu.utility`), `docs/guidance/quellen.md`
- Nicht anfassen: das Ergebnis des Laufs; in Tests kommen nur erfundene Werte in der Form der beobachteten.

- [ ] **Step 1: Prüflauf** (Auftraggeber): `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-WorkerPerfSources.ps1 -OutFile C:\Temp`; festhalten: Ergebnis von `perf.cpu.cores` (Namen der Instanzen, SZ-11) und `perf.cpu.frequency` (Werte von `% Processor Performance` und `% Processor Utility`).
- [ ] **Step 2: Aufzeichnung über einen Arbeitstag** (Auftraggeber): `.\Start-WorkerPerfCapture.ps1 -OutputPath D:\WorkerPerf -DurationMinutes 600`; festhalten: `CollectMs` der Takte (Laufzeit des Lesens je Kern, Entwurf 10) und ob `Sources` die fünf neuen Werte als verfügbar führt.
- [ ] **Step 3: Auswerten** – die drei offenen Punkte des Entwurfs:

| Frage | Woran abzulesen | Folge |
|---|---|---|
| Heißen die Instanzen `<Gruppe>,<Nummer>`, `<Gruppe>,_Total`, `_Total`? | `perf.cpu.cores` | weicht es ab: `Test-WorkerPerfProcessorTotal` und sein Test |
| Schwanken `% Processor Performance`/`% Processor Utility` und liegen sie bei Last über 100 %, oder bleiben sie fest? | `perf.cpu.frequency`, Reihe `host.perf` des Berichts | fest: die Kachel „Leistungsanteil“ sagt „im Server ohne Aussage“ (Notiz im Katalog); eine Klasse bekommen sie in keinem Fall |
| Wie lange dauert das Lesen je Kern bei der vCPU-Zahl des Servers (Takt 2 s)? | `CollectMs`, `quality.tickMsAvg` | über 200 ms im Mittel: Befund an den Auftraggeber, keine Änderung ohne Entscheidung |

- [ ] **Step 4: Anpassungsrunde** – je Befund: erst der Test mit erfundenen Werten in der beobachteten Form, dann die Änderung; `pwsh -NoProfile -File tests/Invoke-Tests.ps1` → `Failed: 0`.
- [ ] **Step 5: Commit** (nur bei Änderungen)

```bash
git add src/ tests/ docs/guidance/quellen.md
git commit -m "Adjust the per-core reading to the first real run" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TebhPvsTuNpmYXDmJ3hXkB"
```

## Abgleich mit dem Entwurf

| Entwurf | Task |
|---|---|
| 1, 2 Ziele, Nicht-Ziele, Anti-Ziele | Global Constraints; 5 (Einordnung), 8 (keine vCPU bei Host/Leistung je Kern, nicht linear), 9 (Kennzeichnung) |
| 3 Ansatz B, Form 2 | 9, 10 (eigenes Skript und Seite); 8 (Richtung plus Hochrechnung) |
| 4.1 neue Signale, Kern-Schwelle in `meta.json`, keine neue Kategorie, ältere Aufzeichnungen, Instanzen mit `_Total` | 2, 3, 4; Prüflauf 11; Bestätigung 13 |
| 4.2 genutzte Werte, 4.3 Server einer Aufzeichnung | 5, 8 (`Get-WorkerPerfRunServer`, `Assert-WorkerPerfSameServer`) |
| 5.1 zehn Klassen, Vorrang, Vorfälle mit Klasse, Widersprüche der Quellen | 5; Quellen 1 |
| 5.2 Katalog `src/sizing.de.json`, beim Laden geprüft | 1 |
| 5.3 Vorfallsansicht, Schritt nach P3-R75, Kopiertext, Kacheln, Vorfallsspalte | 6, 7 |
| 6.1 Bedienung, Mindestmesszeit, Abbruch, Schnelllauf, Befehl je Aufzeichnung | 8, 9 |
| 6.2 Inhalt 1–8 | 9 (Daten), 10 (Seite) |
| 6.3 Hauptzeit, L, T, Formel, Beispiel 8/92/75 → 10–12, Reihenfolge, Grenzen 16/24, Arbeitsspeicher C ÷ 0,8 auf 4 GB, Kennzeichnung | 8, 9 |
| 6.4 Darstellung, Druck, Maskierung | 9, 10 |
| 6.5 Phase 2: Liste mit Server, Achse, eine Prüfstelle | 8, 9 |
| 7 Verhältnis zu anderen Teilen, Prüflauf | 5 (dieselbe Auswertung), 6, 11 |
| 8 Tests: Szenen, Mehrtageslauf, Grenzfälle, Vorrang, ältere Aufzeichnung, Hochrechnung, 16/24, wenig Messzeit, Abbruch, Maskierung, Browser | 4, 5, 8, 9, 10 |
| 9 Grenzen | 12 (README) |
| 10 offene Punkte | 13 |
