# Zustandsbild des Workers – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Jede Aufzeichnung enthält ein einmal beim Start gelesenes Zustandsbild des Workers (`health.json`, elf Bereiche), ein Schnelllauf (`-HealthOnly`) liefert es ohne Messung, und der Bericht bewertet es gegen einen Katalog mit Befund, Einstufung, Erklärung, Vorgehen und Quelle je Prüfung und verweist aus den Vorfällen darauf.

**Architecture:** Der Collector ruft einmal `Get-WorkerPerfHealth` der Datenquelle und schreibt Fakten mit einem Zustand je Wert in `health.json`; bewertet wird erst bei der Auswertung. `src/WorkerPerf.Health.ps1` lädt und prüft `src/health.de.json`, bildet aus `health.json`, Rückblick und Treiberliste die Fakten, wertet die Regeln aus und legt das Ergebnis als Abschnitt `health` in die Berichtsdaten; die Seite rendert nur. Zwei Listen sind die eine Quelle für das, was gelesen wird: die Werteliste `$script:WorkerPerfHealthValues` in `src/WorkerPerf.Common.ps1` für alle elf Bereiche (im Bereich „Anwendungen" der eine Wert `apps.probes`) und die Anwendungsliste `src/apps.json` für dessen Proben: der Bereich wächst ohne Codeänderung um Anwendungen.

**Tech Stack:** Windows PowerShell 5.1 (Laufzeit), HTML/CSS/JavaScript ohne Bibliotheken. Tests: PowerShell 7 mit Pester 5, Node.js mit Playwright.

**Spec:** `docs/superpowers/specs/2026-11-12-zustandsbild-design.md` (Stand mit den Ergänzungen vom 13.11.2026: elf Bereiche, 3.2a Anwendungsliste, Art „Empfehlung aus der Praxis", 4.3 mit der Ausnahme des Auftraggebers zum Energiesparplan und den weiteren Praxisquellen, 4.4 Zielumgebung mit WEM und PrinTaurus SmartSpread). Baut auf: `docs/superpowers/plans/2026-11-12-messkategorien.md` (Kategorie `Zustand`, `-Skip`), `docs/superpowers/plans/2026-11-11-ereignisse-abstuerze-drucken.md` (Rückblick, Treiberliste), `docs/superpowers/plans/2026-11-11-maskierung.md` (Namenssammlung, Bestand, Markertest), `docs/superpowers/plans/2026-11-11-gefuehrter-bericht.md` (Katalogschreibweise, Kopiertexte, Seite, `src/apps.json` mit `key`, `label`, `processes` und ihr Leser `Read-WorkerPerfApps` in `src/WorkerPerf.Guidance.ps1`, der Parameter `-AppsFile` des Berichtsskripts; Teil B dieses Plans beginnt nach dessen Task 7 und der Korrekturrunde 2 seines Task 6, Teil C nach dessen Task 11).

## Global Constraints

- **Windows PowerShell 5.1:** jede `src/*.ps1` beginnt mit `#Requires -Version 5.1`, ist reines ASCII (Umlaute nur in JSON-Textdateien und `src/report-template.html`), ohne PowerShell-7-Syntax und ohne API, die es nur unter .NET Core gibt; eingebettetes C# auf Stand C# 5. `tests/Compat.Tests.ps1` erzwingt einen Teil davon und prüft neue Dateien unter `src/` automatisch.
- **Tests unter Linux:** PowerShell 7, Pester 5, Node/Playwright. Windows-Aufrufe bleiben dünn und werden über Platzhalter getestet (`tests/WindowsStandIns.ps1`). Alle Tests: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`; eine Datei: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/<Datei>`; mehrere Dateien: `pwsh -NoProfile -Command "& ./tests/Invoke-Tests.ps1 -Path tests/<A>, tests/<B>"` (mit `-File` kommt eine Liste nicht als Liste an). Browserprüfungen: `pwsh -NoProfile -File tests/New-TestReports.ps1 -OutDir <workspace>/scratch/wp-reports && node tests/report-browser.js <workspace>/scratch/wp-reports`, Erfolg: `browser checks passed: <n>`, Rückgabewert 0.
- **Temporäre Pfade:** nur unter `<workspace>/scratch/` (`<workspace>` = Arbeitsordner der Ausführung dieses Plans unter `.superpowers/sdd/`), nie unter `/tmp`.
- **Listen:** Funktionen, die Listen liefern, geben schlichte Pipeline-Ausgabe; Aufrufer schreiben `@(...)`.
- **Bericht:** eine einzelne HTML-Datei, keine nachgeladenen Inhalte, keine eingebundenen Bibliotheken oder Schriften. Jede Einstufung steht als Symbol und Wort (`◆ Handeln`, `▲ Prüfen`, `● In Ordnung`, `○ Nicht prüfbar`), ebenso das Ergebnis „Trifft nicht zu" (`– Trifft nicht zu`), nie nur als Farbe. Deutsche Texte stehen in JSON-Dateien (`src/health.de.json`, `src/texts.de.json`, Bezeichnungen in `src/apps.json`), nicht im PowerShell-Code; die Seite enthält nur Beschriftungen ihrer Bedienelemente. Auswahl, Einstufung, Zusammenfassung, Kopiertexte und jeder Satz über das Zustandsbild entstehen im Auswertungsskript.
- **Der Collector liest nur.** Beim Lesen des Zustandsbilds wird nichts geändert, gestartet, beendet oder angesprochen (Entwurf 3.4): kein COM-Objekt, das einen Dienst starten kann (der Windows-Update-Agent wird nicht benutzt), kein externes Programm (`w32tm.exe`, `powercfg.exe`, `fltmc.exe`, `VMwareToolboxCmd.exe`, `cscript.exe`), kein Cmdlet eines Fachmoduls (Defender, SmbShare, ScheduledTasks, AppLocker, PrintManagement, NetAdapter, DnsClient, Storage, Appx), kein `Win32_Product`, keine Verbindung zu einem anderen Rechner. Gelesen wird über `Get-CimInstance` (lokal), die Registrierung (nur lesend, nur `HKLM`), `Get-WinEvent -ListLog`, den Ereignisleser der Quelle, P/Invoke, Dateiversionen und das lokale Objekt `Schedule.Service` der Aufgabenplanung. Nicht gelesen werden Inhalte von Benutzerdateien, Einstellungen je Benutzer (`HKCU`, geladene Benutzerzweige), Kennwörter, Schlüssel, Zertifikate, Dienstkonten, Befehlszeilen von Prozessen. `src/apps.json` beschreibt Werte nur über fünf feste Lesearten; nichts aus der Datei wird ausgeführt.
- **Unter einer Minute:** Das Lesen hat ein Zeitlimit je Bereich (10 s) und gesamt (60 s) und liegt vor dem ersten Messtakt; es geht nicht in die Messwerte ein.
- **Fakten, keine Bewertung:** `health.json` enthält gelesene Werte mit Zustand, keine Einstufung, keine Schwelle und keinen deutschen Text: der Grund eines Werts (`rights`, `notInstalled`, `timeout`, `error`) und das Kennwort eines Bereichs (`budget`, `noReader`, `notRead`, `notInFile`) stehen als Kennwort da, nur die Meldung einer Ausnahme steht so da, wie Windows sie liefert. Bewertet wird bei der Auswertung aus dem Katalog.
- **Keine Prüfung ohne Quelle:** jede Prüfung des Katalogs nennt Quelle (Hersteller oder Praxisquelle), Titel, Adresse (bei „Empfehlung des Herstellers" und „Empfehlung aus der Praxis" Pflicht) und Datum; jede Quelle steht mit Datum in `docs/guidance/quellen.md`. Praxisquellen sind die der geltenden Liste in `docs/guidance/quellen.md` (Entwurf 4.3: dreizehn; die Prüfungen der ersten Fassung stützen sich nur auf BIS-F und carlstalhood.com, weil nur ihre Recherchen eine Quellenprüfung je Eintrag haben). Eine Prüfung aus einer Praxisquelle heißt nie „Empfehlung des Herstellers"; widerspricht die Praxisquelle dem Hersteller, gilt der Hersteller, und der Katalog nennt den Widerspruch. Ausnahmen legt der Auftraggeber fest; der Katalog führt sie im Teil `precedence` mit Begründung und nennt den Widerspruch weiter (festgelegt: der Energiesparplan). Ein Wert aus einer nicht dokumentierten Lesequelle (in den Tabellen „nicht dokumentiert") ist Rohwert und nie Grundlage einer Prüfung, auch keiner Faustregel; der Lader des Katalogs lehnt eine solche Prüfung ab.
- **Zielumgebung (Entwurf 4.4):** der Katalog gilt für nicht persistente, über MCS bereitgestellte Multi-Session-Worker. Jeder Schritt von „Was tun?", der eine Einstellung ändert, nennt das Master-Image oder die Richtlinie als Ort; kein Schritt schlägt eine Änderung am einzelnen Worker vor. Empfehlungen, die nur für Provisioning Services, persistente Maschinen oder Single-Session-Desktops gelten, stehen nicht im Katalog. Der Katalog bleibt allgemein formuliert und nennt keine Systeme des Auftraggebers. Das Zuordnungswerkzeug für Drucker nennt er mit dem Produktnamen des Herstellers (PrinTaurus SmartSpread, AKI GmbH: Entwurf 4.4, Entscheidung R1); was er dazu sagt, stammt aus der Dokumentation des Herstellers, nie von einem echten Server.
- **Ein scheiternder Aufruf der Quelle** beendet die Aufzeichnung nicht: ein Bereich, der scheitert, steht mit Grund in `health.json`; scheitert der ganze Aufruf, wird wie bisher einmal gewarnt und in `meta.json` (`SourceErrors`) vermerkt.
- **Maskierung:** jedes Textfeld, das eine Task den Berichtsdaten hinzufügt, steht in derselben Task in `tests/MaskCensus.json` und, wo es Schlüsselwort oder freier Servertext ist, in den Listen am Anfang von `src/WorkerPerf.Mask.ps1`; ein Feld, das einen Servernamen oder freien Text tragen kann, bekommt einen Marker im Markertest von `tests/Mask.Tests.ps1`.
- **Öffentliches Repository:** keine Daten eines echten Servers; Tests und Simulation verwenden erfundene Namen; Aufzeichnungen, Berichte und das Ergebnis des ersten echten Laufs werden nicht eingecheckt (`health.json` steht ab Task 8 in `.gitignore`).
- **Bestand:** die Vorfälle der simulierten Stunde und alle bestehenden Tests bleiben grün, außer eine Task nennt genau, welche Aussage sich ändert und warum. Das Prüfskript `src/Test-WorkerPerfSources.ps1` bleibt unverändert.
- **TDD:** jede Task schreibt zuerst den fehlschlagenden Test.
- **Commits:** englisch, im Imperativ, ein Commit je Task; keine Modellnamen in Code, Kommentaren oder Dokumenten.

## Review Focus

Jede Zeile ist durch einen Test in der genannten Task abgesichert (im Testcode mit `# Review Focus n` bzw. `// Review Focus n` markiert).

1. **Ein Bereich scheitert oder hängt beim Lesen** (Zugriff verweigert, ein WMI-Anbieter antwortet nicht, die Aufgabenplanung braucht lange). Erwartet: die übrigen Bereiche werden gelesen, der Bereich steht mit Grund in `health.json`, das Lesen endet am Zeitlimit, die Messung beginnt; im Bericht sind genau die Prüfungen dieses Bereichs „nicht prüfbar" mit dem Grund, und der Bereich gilt deshalb allein nicht als auffällig. → Tasks 1a, 1b, 4, 5, 6, 7, 8, 13
2. **Eine Aufzeichnung von vor dem Zustandsbild** (keine `health.json`, kein `Zustand` in `Skip`). Erwartet: der Bericht entsteht und sagt „Zustandsbild nicht erfasst"; es steht weder „nicht gemessen (-Skip Zustand)" noch eine Einstufung da, kein Vorfall verweist auf eine Prüfung. → Tasks 10, 13, 16, 18
3. **Etwas ist nicht da: ein Produkt oder eine Anwendung der Anwendungsliste ist nicht installiert, eine Richtlinie ist nicht gesetzt** (kein Defender, kein WEM-Agent, kein Teams auf diesem Worker, kein Wert in der Registrierung). Erwartet: die Prüfung hat das Ergebnis „trifft nicht zu" mit dem Grund, zählt in keiner Zahl des Bereichs und macht ihn nicht auffällig; die Anwendung steht im Bereich als „nicht installiert"; „nicht gesetzt" wird als das gewertet, was es ist. Nichts davon wird „nicht prüfbar", und es steht keine erfundene Zahl da. → Tasks 1b, 3, 4, 5, 6, 7, 13, 14b, 14c
4. **Freier Servertext und neue Namen im maskierten Bericht** (Name und Befehl einer geplanten Aufgabe, Ausschlusspfad, Richtlinienwert mit Druckerpfad, ein Anwendungswert mit Pfad oder Updatequelle, Fehlermeldung eines Bereichs, Controller, WEM-Server, Zeitquelle, IPv6-Adresse eines DNS-Servers). Erwartet: nichts davon steht im maskierten Bericht oder in einem Kopiertext ohne Namen. → Tasks 15, 16, 18, 19
5. **Ein Schnelllauf wird ausgewertet, auch ohne Rückblick und Treiberliste** (`-HealthOnly`, `-HealthOnly -Skip Rueckblick,Drucken`). Erwartet: der Zustandsbericht entsteht ohne Fehler, sagt „Zustandsbericht ohne Messung" und nirgends „keine Vorfälle"; „handeln" aus einem Dauerzustand mit Ereignis entsteht ohne gelesene Ereignisse nicht, die Prüfung bleibt „prüfen" mit dem Hinweis; die Prüfungen, die Rückblick oder Treiberliste brauchen, sind „nicht prüfbar" mit dem Grund, und ihr Bereich wird dadurch nicht auffällig. → Tasks 10, 13, 17, 20

Zwei Fälle gehören bewusst nicht zu den fünf. Eine fehlerhafte `src/apps.json` (unbekannte Leseart, Pfad außerhalb von `HKLM`, fehlendes Feld) trifft nur den, der die Liste erweitert, und sie scheitert laut: der Collector lehnt sie beim Start ab, bevor ein Ordner angelegt ist, mit Anwendung und Probe in der Meldung (Tasks 1b, 2, 8, 11). Eine Anwendung der Liste, die nicht installiert ist, trifft dagegen jeden Worker ohne diese Anwendung; sie ist deshalb Teil von Zeile 3. Eine geänderte Schwelle steht sichtbar im Kopf des Berichts und ist in den Tasks 11, 16 und 18 geprüft.

## File Structure

| Datei | Verantwortung |
|---|---|
| `src/WorkerPerf.Common.ps1` | Kategorie `Zustand` aktiv; Format von `health.json` (elf Bereiche, Zustände, Werteliste, Bausteine für Wert, Bereich und Kopf); Anwendungsliste für das Zustandsbild lesen und prüfen (`Read-WorkerPerfHealthApps`), Zeilen der Proben bilden; Rollen mit `filters` |
| `src/apps.json` (aus dem geführten Bericht: `key`, `label`, `processes` für fünf Anwendungen; hier bei Edge, Office und Teams um `installed` und `probes` ergänzt) | je Standardanwendung: Kennung, Bezeichnung, Prozesse, Erkennung der Installation, Proben |
| `src/WorkerPerf.Capture.ps1` | `health.json` schreiben, Konsolenzeile, Schreiber nur für genannte Dateien |
| `src/Start-WorkerPerfCapture.ps1` | Aufruf vor dem ersten Takt, `-Skip Zustand`, `-HealthOnly`, `-AppsFile`, Kopie von `apps.json` in die Aufzeichnung, Hilfe |
| `src/WorkerPerf.Sources.Simulation.ps1` | erfundenes Zustandsbild mit auffälligen Werten, erfundener Stand der Anwendungen |
| `src/WorkerPerf.Sources.Windows.ps1` | Gerüst mit Zeitlimit je Bereich, dünne Windows-Aufrufe, Leser der elf Bereiche |
| `src/WorkerPerf.Load.ps1` | `Model.Health`, `Model.HealthState`, `Model.Recorded`, `Model.EventsAll`, Modell eines Schnelllaufs |
| `src/WorkerPerf.Health.ps1` (neu) | Katalog laden und prüfen; Fakten bilden; Regeln, Einstufung, Ergebnis je Bereich; Rohwerte; Verweise der Vorfälle; Kopf- und Kopiertexte |
| `src/health.de.json` (neu) | Katalog: Bereiche, Einstufungen, Schwellen, Bezeichnungen der Werte, Texte, Prüfungen |
| `src/roles.json` | Filtertreiber je Schutzprodukt (Feld `filters`; die Einträge selbst pflegt der geführte Bericht) |
| `src/texts.de.json` | Texte der Kategorie und der Quelle |
| `src/WorkerPerf.Mask.ps1` | Namen aus `health.json`; Listen der Schlüsselwort- und Freitextfelder; Profilordner, die keiner Person gehören |
| `src/New-WorkerPerfReport.ps1` | `-HealthFile`, der vorhandene Parameter `-AppsFile` auch für das Zustandsbild, Abschnitt `health`, Verweis je Vorfall, kurzer Weg für den Schnelllauf |
| `src/report-template.html` | Zeile „Zustand des Workers" mit elf Kacheln, Bereichsansicht, Abschnitt im Vorfall, Reiter der Expertenansicht, Zustandsbericht |
| `docs/guidance/quellen.md` | Nachweis der Quellen des Katalogs mit Datum; die Praxisquellen mit dem Stand ihrer Recherche, je recherchierter Praxisquelle ein eigener Abschnitt; die Ausnahme „Praxisquelle vor Hersteller" |
| `tests/Health.Tests.ps1` (neu), `tests/WindowsHealth.Tests.ps1` (neu), `tests/HealthOnly.Tests.ps1` (neu) | Katalog und Bewertung; Windows-Leser über Platzhalter; Schnelllauf |
| `tests/WindowsStandIns.ps1`, `tests/TestHelpers.ps1`, `tests/MaskCensus.json`, `tests/report-browser.js` und die bestehenden `*.Tests.ps1` | Platzhalter, Helfer (darunter die Anwendungsliste der Tests mit einer vierten, erfundenen Anwendung mit Proben), Bestand, Browserprüfungen, angepasste Aussagen |
| `.gitignore` | `health.json` und `health.json.tmp` bleiben außerhalb des Repositorys |
| `README.md`, `pages/index.html` | Beschreibung, Demo |

## Reihenfolge und Parallelität

| Teil | Tasks | Voraussetzung | Dateien, die auch der Plan „Geführter Bericht" ändert |
|---|---|---|---|
| A | 1a–14c | Tasks 1a, 1b und 4–6 keine; die Tasks 2, 3 und 7 und alles ab Task 8: der Commit des geführten Berichts, der `src/apps.json` und ihren Leser anlegt (Korrekturrunde 2 seines Task 6, „Add the application list and the app condition to the guidance"), ist in den Worktree geholt; Task 12 dazu der Commit derselben Runde, der `src/roles.json` ergänzt („List WEM and the printer mapping client in the roles"). Teil A läuft in einem eigenen Git-Worktree neben dem geführten Bericht. | `src/apps.json` (Task 2: je Anwendung zwei neue Felder, `key`, `label`, `processes` bleiben unberührt), `tests/MaskCensus.json` (Task 2: acht Zeilen, weil der geführte Bericht die Liste als `appList` in die Berichtsdaten legt), `src/roles.json` (Task 12: das Feld `filters` an zwei Einträgen), `src/texts.de.json` (Task 8), `tests/TestHelpers.ps1` (Tasks 2, 8, 9), `tests/Skip.Tests.ps1` (Tasks 8, 9), `tests/Mask.Tests.ps1` (Task 8: eine Zeile), `docs/guidance/quellen.md` (Tasks 14a–14c). Jede dieser Änderungen ist ein eigener, zusammenhängender Block (neue Zeilen bzw. neue Funktionen am Ende), damit das Zusammenführen ohne Handarbeit gelingt. |
| B | 15–17 | Task 7 des geführten Berichts und die drei Commits der Korrekturrunde 2 seines Task 6 sind im Hauptstrang (die Runde ändert `src/New-WorkerPerfReport.ps1`, `tests/Report.Tests.ps1` und `tests/MaskCensus.json`, also die Dateien von Task 16); Teil A ist zusammengeführt | `src/New-WorkerPerfReport.ps1`, `src/WorkerPerf.Mask.ps1`, `tests/MaskCensus.json`, `tests/Report.Tests.ps1`, `tests/Mask.Tests.ps1`, `tests/TestHelpers.ps1` |
| C | 18–20 | Task 11 des geführten Berichts ist im Hauptstrang | `src/report-template.html`, `tests/report-browser.js` |
| D | 21–22 | Task 12 des geführten Berichts ist im Hauptstrang (Task 21); Task 22 ist der Schritt des Auftraggebers | `README.md`, `pages/index.html` |

In Teil A fasst keine Task `src/New-WorkerPerfReport.ps1`, `src/WorkerPerf.Guidance.ps1`, `src/guidance.de.json`, `src/report-template.html`, `tests/report-browser.js`, `tests/Report.Tests.ps1`, `tests/Guidance.Tests.ps1`, `tests/GuidanceCatalogue.Tests.ps1`, `README.md` oder `pages/index.html` an; in `tests/MaskCensus.json` trägt nur Task 2 ihre acht Zeilen ein. Bis Teil D sagt das README noch „geplant"; das ist für die Dauer der Umsetzung hingenommen.

Zwei Tasks sind geteilt, damit ein Prüfer jedes Stück für sich annehmen kann: Task 1 in 1a (Format und Werteliste) und 1b (Anwendungsliste lesen), Task 14 in 14a, 14b und 14c (Inhalt des Katalogs). Wo der Plan „Task 1" oder „Task 14" ohne Buchstaben nennt, sind alle Teile gemeint.

## Entscheidungen, die dieser Plan trifft

Der Entwurf überlässt dem Plan die Werte je Bereich und lässt einige Fragen offen. Die Entscheidungen (Abschnitte A bis S der Vorarbeit; wo ein späterer Abschnitt einem früheren widerspricht, gilt der spätere) stehen hier gruppiert, jede mit dem, was es kostet, wenn sie falsch ist. Der Auftraggeber sieht sie mit dem Plan.

**Einhängepunkt, Format, Collector (A)**

- **Die Kategorie `Zustand` wird aktiv** mit `Files = @('health.json')`, `Sources = @('health')`; die Texte `skip.label.Zustand`, `skip.text.Zustand` und die Abfrage im Collector legt dieser Plan an (Anhang des Entwurfs). `Places` bleibt bis Task 20 leer, weil die Stelle der Seite erst dann existiert; bis dahin deckt keine Browserprüfung `report-skip-zustand.html` ab (P6). *Wenn falsch:* eine Tabellenzeile und zwei Texte.
- **Eine Quellfunktion `Get-WorkerPerfHealth`** in beiden Quellen; der Collector ruft sie einmal nach der Treiberliste und vor dem Beginn der Taktplanung. *Wenn falsch:* die Aufrufstelle ist eine Zeile; ein langsames Lesen verzögert nur den Start.
- **`health.json`:** Formatnummer 1, Lesezeitpunkt, Dauer, die elf Bereiche in fester Reihenfolge (`size`, `operation`, `sessions`, `vda`, `profile`, `print`, `security`, `network`, `events`, `maintenance`, `apps`), je Bereich Status, Dauer, Fehler und Werte, je Wert Zustand, Grund und Inhalt (Aufbau, Kennwörter und ein Beispiel stehen in Task 1a). Listen sind Listen von Objekten, auch mit einem oder keinem Eintrag. Zeitpunkte in `Values` sind Zahlen (Millisekunden seit 1970, UTC): `ConvertFrom-Json` wandelt unter PowerShell 7 einen ISO-Text in eine Zeit ohne ihren Offset. `ReadAt` und `StartTime` liest der Lader deshalb als Text aus der Datei. Eine Zahl, die nicht endlich ist (`NaN`, unendlich), wird nicht gespeichert: Windows PowerShell 5.1 schriebe sie als ungültiges JSON. *Wenn falsch:* ein geändertes Format bekommt die Nummer 2; der Lader liest dann beide Nummern, damit sich jede ältere Aufzeichnung weiter auswerten lässt (Entwurf 3.1), und meldet nur eine Nummer, die er nicht kennt, als „nicht lesbar".
- **Zeitlimit kooperativ:** Stoppuhr je Bereich (10 s) und gesamt (60 s); jeder CIM-Aufruf bekommt den Rest als Zeitlimit (mindestens 1 s), auch die wiederverwendete Abfrage der Profilcontainer; vor jedem Wert und vor jeder Probe einer Anwendung wird das Limit geprüft, die übrigen heißen `unreadable`/`timeout`. Keine Runspaces, keine Jobs. Eine gemeinsame Abfrage, die in einem Bereich am Zeitlimit endet, versucht der nächste Bereich, der sie braucht, mit seinem eigenen Limit noch einmal: ein hängender Aufruf macht so nicht die Werte aller Bereiche unlesbar. *Wenn falsch:* ein Aufruf ohne eigenes Zeitlimit (Registrierung, WTS, Aufgabenplanung), der hängt, hält den Start auf; der erste echte Lauf zeigt die Dauer je Bereich.
- **Ein gescheiterter Bereich steht nur in `health.json`;** `SourceErrors` und eine Warnung gibt es nur, wenn der ganze Aufruf wirft. *Wenn falsch:* ein Administrator übersieht einen gescheiterten Bereich auf der Konsole; die Konsolenzeile nennt deshalb die unvollständigen Bereiche.

**Schnelllauf (B)**

- **`-HealthOnly`** liest Zustandsbild, Rückblick und Treiberliste, schreibt `meta.json` und endet; `-Skip Rueckblick` und `-Skip Drucken` gelten; mit `-Skip Zustand` und mit den Parametern der Messung (die Liste steht in Task 9) wird er abgelehnt; `-AppsFile` gilt. Mit `-Simulate` braucht er keine Dauer und schreibt kein `expected.json`. *Wenn falsch:* eine Ablehnung zu viel; sie nennt die Parameter.
- **`meta.json`** bekommt `HealthOnly` (immer geschrieben) und den Endgrund `healthonly`; `SchemaVersion` bleibt 3. Die Quelle wird im Schnelllauf ohne die Kategorien der Messung initialisiert; `Skip` in `meta.json` nennt nur, was der Aufrufer weggelassen hat. *Wenn falsch:* ein Feld mehr in `meta.json`; alte Aufzeichnungen haben es nicht und gelten als Messung.
- **Der Lader** gibt für einen Schnelllauf ein Modell ohne Messreihen zurück; der Offset der Serverzeit kommt aus `StartTime`. **Das Berichtsskript** nimmt für ihn einen eigenen kurzen Weg (Kopf, Zustandsbild, Rückblick, Treiberliste, Weggelassenes) und lehnt `-From`, `-To`, `-FocusUser`, `-ReportedTime`, `-TopProcesses` ab. *Wenn falsch:* der kurze Weg ist eine Funktion; der Messweg bleibt unberührt.

**Lader und Zustände (C)**

- **`Model.HealthState`:** `read`; `skipped` (`Zustand` in `Skip`; die Datei wird dann nicht gelesen, auch wenn sie da ist); `notRecorded` (Datei fehlt und `Zustand` steht nicht in `Skip`: jede Aufzeichnung von vor diesem Baustein); `unreadable` (Datei beschädigt oder anderes Format: eine Warnung). Scheitert das Lesen beim Start als Ganzes, gibt es ebenfalls keine Datei: es bleibt bei `notRecorded` (Entwurf 3.5: ohne die Datei „Zustandsbild nicht erfasst"), der Satz im Bericht nennt dann das gescheiterte Lesen. *Wenn falsch:* eine alte Aufzeichnung würde als „nicht gemessen" oder als geprüft dargestellt; Review Focus 2 hält die Regel fest.
- **Der Lader merkt sich, was die Bewertung zum Einordnen braucht:** `Model.Recorded` (ob `events_before.csv` und `printdrivers.csv` in der Aufzeichnung stehen) und `Model.EventsAll` (die Ereignisse der ganzen Messung, auch außerhalb von `-From` und `-To`). *Wenn falsch:* zwei Felder im Modell, die sonst niemand liest.

**Fakten und ihre Herkunft (D, P2, P3, P7)**

- **Die Werteliste** steht im Abschnitt „Werte, Fakten und Prüfungen je Bereich". Regel: dokumentierte Quellen. Als „nicht dokumentiert" markiert sind: die Merker für einen ausstehenden Neustart aus Komponentenwartung und Windows Update, der Registrierungsschlüssel und der Dienst der VMware Tools, die Rohwerte unter `HKLM\SOFTWARE\Policies\Citrix` und `…\UserProfileManager`, der Umfang der AppLocker-Regeln aus `…\SrpV2` (nur Zahlen, keine Regelinhalte: P3) und in der Anwendungsliste vier Proben (`apps.office.version`, `apps.office.platform`, `apps.office.updatesEnabled`, `apps.edge.updateService`). Sie werden aufgezeichnet und als Rohwert gezeigt. D1 gilt streng (P2): auf einem solchen Wert steht keine Prüfung, auch keine Faustregel; die Werteliste und die Anwendungsliste tragen dafür das Merkmal „nicht dokumentiert", und der Lader des Katalogs lehnt eine Prüfung ab, die einen solchen Wert nennt. *Wenn falsch:* ein Neustart, den nur Komponentenwartung oder Windows Update verlangen, oder ein 32-Bit-Office bleibt bis zur Anpassungsrunde ohne Prüfung; die Rohwerte zeigen es.
- **Was die spätere Recherche dokumentiert belegt, kommt mit seiner Quelle zurück (P2):** Stand der VMware Tools (Version aus dem Uninstall-Eintrag gegen die Mindestversion von VMware), der Ballon-Treiber (`vmmemctl` über `Win32_SystemDriver`), die Art des Netzwerk- und des Speicheradapters, Receive Side Scaling am Adapter. Jede dieser Prüfungen trägt die Art „Empfehlung des Herstellers" mit dem VMware-Dokument. *Wenn falsch:* der Name des Treibers oder des Uninstall-Eintrags weicht ab; dann ist die Prüfung auf einer VMware-VM „prüfen", obwohl alles in Ordnung ist, und Task 22 berichtigt das Muster.
- **Nicht gelesen in der ersten Fassung** (Abschnitt „Nach dem ersten echten Lauf"): Transportart der Sitzungen, ob der VDA gerade registriert ist, letzte erfolgreiche Zeitsynchronisation, Ballon- und Limit-Zähler von VMware (ihre Zählernamen stehen in keinem geöffneten VMware-Dokument), Prüfungen auf Citrix- und Profilverwaltungsrichtlinien, die wirksame WEM-Konfiguration (sie liegt im Agent-Cache, dessen Format nicht dokumentiert ist). Der Katalog hat darauf keine Prüfung; die Bereichsansicht sagt, was nicht abgedeckt ist. *Wenn falsch:* eine Lücke, die der Bericht benennt.
- **Zeitlimits der Sitzungen (P7)** kommen aus der dokumentierten Klasse `Win32_TSSessionSetting`; scheitert die lokale Abfrage, ist der Wert „nicht lesbar" und die Prüfungen darauf „nicht prüfbar" bis zur Anpassungsrunde. Zeitgeber aus einer Citrix-Richtlinie sieht die erste Fassung nicht; die Texte der zwei Prüfungen sagen das. *Wenn falsch:* eine Prüfung meldet „prüfen", obwohl ein Citrix-Limit gesetzt ist.
- **Wiederverwenden statt zweimal lesen:** die beim Initialisieren gelesenen Objekte `Win32_ComputerSystem` und `Win32_OperatingSystem`, die WTS-Hülle (um Verbindungs- und Trennzeitpunkt ergänzt), `Get-WorkerPerfProfileDisks` (um Größen ergänzt), die Isolierungsrichtlinie des Treiberlesers, das Objekt von `Get-WinEvent -ListLog`. Eine Abfrage von `Win32_Service`, der Sitzungen, von `Win32_SystemDriver` und von `MSFT_MpPreference` je Aufruf, für alle Bereiche und für die Proben der Anwendungen. *Wenn falsch:* nur Lesedauer.
- **Fakten der Auswertung** (nicht in `health.json`): die Treiberliste aus `printdrivers.csv`, die Zählungen aus dem Rückblick, erkannte Schutzprodukte aus `roles.json` gegen die aufgezeichneten Dienste und Filtertreiber. Ist `Drucken` oder `Rueckblick` weggelassen, fehlt die Datei oder ist ihr Lesen gescheitert, sind diese Fakten „nicht lesbar" mit dem Grund, und die Prüfungen, deren Regel `check` sie braucht, „nicht prüfbar". Braucht nur die Regel `act` den Rückblick (eine Bedingung `event`), bleibt die Prüfung bei „prüfen" mit dem Hinweis, dass Ereignisse nicht geprüft sind (P5). *Wenn falsch:* eine Prüfung steht bei „prüfen", wo „nicht prüfbar" erwartet wird; es ändert sich eine Zeile der Einstufung.
- **Abgeleitete Fakten** (Anteile, Zählungen, „in der Arbeitszeit", „VMware-VM") bildet die Auswertung aus den gelesenen Werten nach festen Regeln im Code; der Katalog vergleicht nur einzelne Zahlen, Texte und Ja/Nein-Werte. Für Anwendungen gibt es keine abgeleiteten Fakten: ihre Prüfungen vergleichen die Proben selbst, damit eine neue Anwendung ohne Code auskommt. *Wenn falsch:* eine Ableitung ist eine Funktion mit Test; eine alte Aufzeichnung wird mit der berichtigten Ableitung neu ausgewertet.
- **Größe und ältester Eintrag je Ereignisprotokoll** liest der Bereich `events` des Zustandsbilds (Kategorie `Zustand`), nicht der Rückblick, und zwar für die Protokolle, die der Ereigniskatalog liest (acht Namen). *Wenn falsch:* mit `-Skip Rueckblick` stehen Größe und Alter der Protokolle trotzdem im Bericht, mit `-Skip Zustand` fehlen sie; verschoben wäre es ein Leser und eine Tabellenzeile.

**Katalog und Einstufung (E, J, P1, P4, P5, P9)**

- **`src/health.de.json`:** `version`, `areas` (elf Kennungen in fester Reihenfolge, `label`, `notCovered`), `grades` (Wort und Symbol für die vier Einstufungen und für das Ergebnis `na` „Trifft nicht zu"), `thresholds` (benannte Zahlen mit `value`, `default`, `unit`, `label`), `values` (Bezeichnung jedes festen Fakts; die Bezeichnung eines Anwendungswerts steht in `src/apps.json`), `copy` (Texte), `precedence` (die Ausnahmen, in denen nach Festlegung des Auftraggebers die Praxisquelle vor dem Hersteller gilt), `checks` (Aufbau und Prüfungen des Laders: Task 11). Felder einer Liste zeigt die Rohwertanzeige mit ihrem Feldnamen aus `health.json`. *Wenn falsch:* ein Teil mehr oder weniger im Katalog; der Lader und sein Test nennen jeden Teil einmal.
- **Drei Arten (J2, S1):** `vendor` „Empfehlung des Herstellers", `practice` „Empfehlung aus der Praxis" (Quelle ist eine Praxisquelle der geltenden Liste in `docs/guidance/quellen.md`, mit Titel, Adresse und Datum wie eine Herstellerquelle), `rule` „Faustregel". Der Lader verlangt eine Adresse für `vendor` und `practice`. Eine Empfehlung der Praxisquellen, die das Herstellerdokument nach der Quellenprüfung der Recherche selbst ausspricht, ist `vendor` mit dem Herstellerdokument (WEM-Cache, VMXNET3, Updates von Edge). Widerspricht die Praxisquelle dem Hersteller, ist die Linie des Herstellers die Regel, und `meaning` nennt den Widerspruch; das betrifft `network.rss` (VMware verlangt RSS eingeschaltet; BIS-F schaltet es beim Versiegeln global ab; vom Auftraggeber am 13.11. bestätigt: Q3). *Wenn falsch:* eine Prüfung trägt die falsche Art; es ändert sich ein Wort und ein Eintrag der Liste im Test von Task 14a.
- **Vorrang der Praxisquelle, wo der Auftraggeber ihn festlegt (Entwurf 4.3, Q1, Q2):** der Katalog hat den Teil `precedence`, eine Liste von `{ check, winner: "practice", reason }`. Eine dort genannte Prüfung nimmt ihre Regel aus der Praxisquelle und trägt die Art `practice`; ihr `meaning` nennt weiter, was der Hersteller sagt. Der Lader lehnt einen Eintrag ab, dessen Prüfung es nicht gibt oder nicht die Art `practice` hat. Erste Ausnahme ist der Energiesparplan: `operation.powerPlan` meldet „prüfen", wenn der Plan nicht „Höchstleistung" ist (Stalhood, BIS-F); `meaning` nennt die Vorgabe „Ausbalanciert" von Microsoft und dass VMware „Höchstleistung" nennt, solange Latenzprobleme untersucht werden; `reason` trägt die Begründung des Auftraggebers (die Praxisquellen beziehen sich auf Citrix-Terminalserver und Betriebserfahrung, die Herstellerdokumentation nicht). *Wenn falsch:* ein Eintrag der Liste und die Regel einer Prüfung; bis dahin steht auf jedem Worker mit „Ausbalanciert" ein „prüfen".
- **Weitere Praxisquellen (S1–S3):** der Auftraggeber hat elf weitere Praxisquellen übernommen (Entwurf 4.3). Der Nachweis führt alle dreizehn mit dem Stand ihrer Recherche. Die Prüfungen der ersten Fassung stützen sich nur auf BIS-F und carlstalhood.com: nur diese Recherchen haben eine Quellenprüfung je Eintrag. Die Recherchen der übrigen (`research-px-<key>.md`) entstehen noch; was sie stützen, kommt als Änderung des Katalogs nach der Regel „Feste Listen" im Abschnitt „Inhalt des Katalogs". Wo zwei Praxisquellen einander widersprechen, nennt der Katalog beide Sichten und ergreift keine Partei, solange kein Herstellerdokument und nicht der Auftraggeber entscheidet (S3). *Wenn falsch:* eine Prüfung aus einer weiteren Praxisquelle fehlt bis zur nächsten Durchsicht des Katalogs.
- **Eine Bedingung** ist `{ "value": "<Fakt>", "op": "gt|ge|lt|le|eq|ne|in|contains|exists|absent", "than": Zahl, Text, Liste oder "@Schwelle", "hard": true }` oder `{ "event": "<Art oder Art.Gruppe>", "min": n, "days": d }`; alle Bedingungen einer Liste müssen gelten. *Wenn falsch:* eine Regel lässt sich nicht ausdrücken (ein „oder" braucht einen abgeleiteten Fakt oder zwei Prüfungen); ein Operator ist eine Zeile im Vergleich und ein Eintrag in der Liste der Operatoren.
- **Auswertung einer Bedingung in vier Werten:** wahr, falsch, „trifft nicht zu" (der Fakt ist `absent` mit `notInstalled` oder `notInUse`: das gilt für jeden Operator, auch für `exists` und `absent`), unbekannt (der Fakt ist `unreadable`). Für einen Fakt, der ohne Grund `absent` ist („nicht gesetzt", „nicht vorhanden"), ist Gleichheit entschieden: `exists`, `eq`, `in` und `contains` sind falsch, `absent` und `ne` sind wahr; nur die Größenvergleiche (`gt`, `ge`, `lt`, `le`) sind unbekannt. Eine falsche Bedingung macht die Regel falsch, sonst eine nicht zutreffende die Regel nicht zutreffend, sonst eine unbekannte die Regel unbekannt. *Wenn falsch:* eine Prüfung wird „nicht prüfbar", wo sie „in Ordnung" sein sollte; der Katalog schreibt dann `exists` vor den Vergleich.
- **Einstufungen und das Ergebnis „trifft nicht zu" (P4):** `act`, wenn die Regel `act` wahr ist; sonst `check`, wenn `check` wahr ist; sonst `na`, wenn `check` nicht zutrifft; sonst `unknown`, wenn `check` unbekannt ist; sonst `ok`. Eine Prüfung mit dem Ergebnis `na` ist nicht eingestuft und wird nicht gezählt: die Zahlen eines Bereichs kennen nur `ok`, `check`, `act`, `unknown`; sie steht in der Bereichsansicht unter den eingestuften Prüfungen und in der Tabelle der Expertenansicht, mit dem Grund. Dasselbe Ergebnis haben die Prüfungen einer Anwendung, die nicht installiert ist, und die Prüfungen zur Druckerzuordnung über Citrix-Richtlinien, wo diese Zuordnung nicht in Gebrauch ist. Eine Regel `act` gilt nur mit einer Bedingung `hard` oder einer Bedingung `event`; der Lader lehnt jede andere ab. Ein Bereich trägt die Einstufung seiner auffälligsten Prüfung; `unknown` allein macht ihn nicht auffällig, wird aber gezählt. Keine Gesamtnote. *Wenn falsch:* ein Feld der Berichtsdaten und eine Stelle der Seite ändern sich; der Katalog bleibt.
- **Eine Bedingung `event` (P1)** zählt die Ereignisse dieser Art im Rückblick der letzten `days` Tage und, bei einer Messung, die Ereignisse der ganzen Messung, unabhängig von `-From` und `-To`: der Dauerzustand trifft beobachtete Ereignisse, wo immer sie beobachtet wurden; der simulierte Rückblick bleibt, wie er ist. Sie ist wahr, sobald die gezählten Ereignisse `min` erreichen; sonst falsch, wenn der Rückblick gelesen wurde; sonst unbekannt. Ein Rückblick, der kürzer ist als `days`, zählt mit dem, was er hat. Ist die Bedingung unbekannt, bleibt die Prüfung bei `check` mit dem Hinweis `copy.eventsUnchecked` (P5). *Wenn falsch:* eine Prüfung wird „handeln" aus einem Ereignis der Messung, das keinen Dauerzustand belegt; die Zählung ist eine Funktion (`Get-WorkerPerfHealthEventCount`).
- **Schwellen (P9):** eine Schwelle, deren `value` von `default` abweicht, steht im Kopf des Berichts. Die Schwellen ohne Zahl eines Herstellers sind Vorschläge; sie stehen in der Tabelle „Schwellen des Katalogs" und werden dem Auftraggeber mit dem Katalog vorgelegt. Drei Zahlen stammen aus der Praxisquelle (60 Tage für das Alter der Updates, 8 Prozessoren und 24 GB für die Größe eines Workers). *Wenn falsch:* eine Zahl im Katalog; der Kopf des Berichts nennt jede Abweichung vom ausgelieferten Stand.
- **Der Lader des Katalogs lehnt ab,** mit Prüfung und Feld in der Meldung: fehlende oder leere `source`, `kind`, `title`, `meaning`, `findings`, ein `todo` ohne Schritt; unbekannte Fakten, Bereiche, Schwellen, Operatoren, Ereignisarten, `relates`; eine Regel `act` ohne harte Grenze oder Ereignis; einen Platzhalter, der kein Fakt aus `values` und keine Schwelle ist; `kind` `vendor` oder `practice` ohne `source.url`; einen Listenwert in einer Bedingung oder einem Platzhalter; freien Servertext in einem Platzhalter oder mit einem anderen Operator als `exists` und `absent`; einen Fakt ohne dokumentierte Lesequelle; eine Prüfung auf eine Anwendung, die nicht in der Anwendungsliste steht; einen Eintrag in `precedence` für eine Prüfung, die es nicht gibt oder die nicht die Art `practice` hat. *Wenn falsch:* ein Katalog, den der Auftraggeber geändert hat, wird abgelehnt, obwohl er gemeint war; die Meldung nennt Prüfung und Feld.
- **Inhalt:** aus den Recherchen der Vorarbeit, jede Empfehlung nur so weit, wie ihre Quellenprüfung sie stützt („supported", oder „partly" nach der dort genannten Kürzung; nie „unsupported" oder nicht erreichbar); jede Quelle wird beim Schreiben erneut geöffnet und mit Datum in `docs/guidance/quellen.md` eingetragen. Der Auftraggeber liest den Katalog, bevor der Baustein als fertig gilt; die Durchsicht hält die folgenden Tasks nicht auf. *Wenn falsch:* eine Empfehlung ist falsch belegt; der Nachweis in `docs/guidance/quellen.md` und die Durchsicht des Auftraggebers sind die Kontrolle.
- **Verweis im Vorfall:** ein Vorfall nennt die Prüfungen, deren `relates` seine Situation oder eines seiner Muster enthält und deren Einstufung `check` oder `act` ist. Wortlaut „kann beitragen". *Wenn falsch:* ein Vorfall zeigt zu viele oder zu wenige Prüfungen; es ändert sich nur `relates` im Katalog, kein Code.

**Zielumgebung und Ereignisprotokolle (K, L)**

- **Der Katalog nimmt die Zielumgebung an (K1, K4):** kein dokumentierter lokaler Wert nennt die Art der Bereitstellung; gelesen wird der eine dokumentierte Wert `vda.persistentDataLocation` (Rohwert), einen Fakt `vda.provisioning` gibt es nicht. Der Text `copy.environment` sagt im Kopf des Zustandsbilds, dass die Prüfungen von nicht persistenten, über MCS bereitgestellten Multi-Session-Workern ausgehen. Empfehlungen nur für Provisioning Services (Schreibcache, Auslagerungsdatei kleiner als das Cache-Laufwerk, Geister-NICs), persistente Maschinen oder Single-Session-Desktops sind nicht im Katalog. *Wenn falsch:* auf einem Worker anderer Art passt ein Vorschlag nicht; der Kopf nennt die Annahme.
- **Ort der Änderung (K2):** jeder Schritt, der eine Einstellung ändert, nennt in `where` das Master-Image oder die Richtlinie. Ein Test hält es für die Prüfungen fest, deren Abhilfe eine Einstellung ist. *Wenn falsch:* ein Vorschlag nennt den falschen Ort; es ändert sich Text.
- **Grenze „letzter Start" (K3):** die Prüfungen, deren Fakten auf einem nicht persistenten Worker nur bis zum letzten Start zurückreichen (`events.crashes`, `events.storage`, `events.fileserver`, `events.coverage`, `events.sinceBoot`, `sessions.unloadedProfiles`, `sessions.tempProfiles`), führen `operation.lastBoot` in `values` und nennen ihn in ihrem Befund als Grenze. `operation.updateAge` spricht vom Stand des Abbilds. Für die dritte Gruppe des Entwurfs, die Dateien auf dem Systemlaufwerk, hat der Katalog keine Prüfung, die etwas über ihren Verlauf sagt: `operation.diskFree` ist ein Augenblickswert (der freie Platz beim Lesen) und führt den letzten Start nicht; `size.commitHeadroom` nennt den Höchststand „seit dem Start" in Worten, wie Windows ihn auf jeder Maschine zählt. Beide stehen deshalb nicht in der Liste. *Wenn falsch:* ein Satz mehr oder weniger im Befund.
- **Protokolle reichen nur bis zum letzten Start (L1, L2):** der abgeleitete Fakt `events.sinceBootOnly` sagt, ob kein gelesenes Protokoll vor den letzten Start zurückreicht; die Prüfung `events.sinceBoot` stellt es fest (Art „Empfehlung aus der Praxis": BIS-F verlegt die Ereignisprotokolle auf den Cache-Datenträger, wenn für MCS ein MCSIO-Cache-Datenträger eingerichtet ist; dass sie damit einen Neustart überstehen, ist eine Folgerung des Katalogs und im Text so gekennzeichnet), nie „handeln". `events.coverage` meldet eine Lücke nur, wenn sie nicht schon der letzte Start erklärt. Bereichsansicht und Zustandsbericht sagen über den Zählungen je Tag, ab wann die Protokolle reichen (`eventsReachText`). *Wenn falsch:* ein Abbild, das alte Einträge mitbringt, gilt als „reicht zurück", obwohl die Tage dazwischen fehlen; der Satz nennt deshalb auch den letzten Start.

**WEM und Druckerzuordnung (M, R)**

- **WEM-Agent im Bereich `vda` (M2):** gelesen werden die Dienste (über ihre dokumentierten Anzeigenamen), die Version (Dateiversion des Dienstprogramms), der WEM-Server aus der Richtlinie, der abweichende Ort des Agent-Cache und der Wartewert `GpNetworkStartTimeoutPolicyValue`. Drei Prüfungen stützen sich auf die Citrix-Dokumentation (Dienste, Cache an beständigem Ort, Wartewert), eine auf die Praxisquelle (Ausschlüsse des Virenschutzes). *Wenn falsch:* die Anzeigenamen weichen ab; dann gilt der Agent als nicht installiert und seine Prüfungen als „trifft nicht zu".
- **Zuordnung über Citrix-Richtlinien (M3):** der abgeleitete Fakt `print.citrixMapping` zeigt, ob Citrix Drucker zuordnen kann: er ist „nicht in Gebrauch" (`absent`/`notInUse`), wenn der Dienst „Citrix Print Manager Service" fehlt oder nicht läuft; läuft er, gilt die Zuordnung als möglich. Eine Prüfung zur Zuordnung über Citrix-Richtlinien (automatisch erstellte Client-Drucker, Sitzungsdrucker) führt diesen Fakt als erste Bedingung und hat sonst das Ergebnis „trifft nicht zu". In der ersten Fassung trägt keine Prüfung des Katalogs diese Bedingung: die Prüfungen auf Citrix-Druckrichtlinien sind zurückgestellt, weil die Wertnamen nicht dokumentiert sind (D1). Der Mechanismus ist gebaut und mit einer Prüfung getestet, die nur im Test steht. *Wenn falsch:* ein Worker mit laufendem Citrix-Druckdienst, auf dem das Zuordnungswerkzeug die Drucker verbindet, gilt als „Zuordnung möglich" (Offene Punkte 2).
- **Das Zuordnungswerkzeug ist genannt und wird gelesen, soweit sein Hersteller es dokumentiert (R1, R2):** die Drucker ordnet PrinTaurus SmartSpread (AKI GmbH) zu (Entwurf 4.4); der Auftraggeber hat den Produktnamen freigegeben (R1 ersetzt M1). Öffentlich dokumentiert sind nur die Release Notes 6.2 und 6.4 des Herstellers. Daraus entstehen ein Wert (`print.mappingClientVersion`: die Version des SmartSpread Client aus seinem Uninstall-Eintrag) und eine Prüfung (`print.mappingClientSupported`: der Hersteller hat alle Versionen unter 6.2 zum 31.12.2025 abgekündigt). Wie und wann der Client zuordnet, wo er Konfiguration und Protokolle ablegt und ob die Citrix-Druckrichtlinien abgeschaltet sein sollen, sagt keine öffentliche Seite des Herstellers: dazu gibt es weder Wert noch Prüfung, und `notCovered` des Bereichs sagt es. Die Einträge der Rollenliste und der Anwendungsliste (`printaurus`) pflegt der geführte Bericht. *Wenn falsch:* der Uninstall-Eintrag heißt anders, als der Name des Installationspakets erwarten lässt; dann gilt der Client als nicht installiert und die Prüfung als „trifft nicht zu", bis Task 22 das Muster berichtigt.

**Anwendungen (N, O)**

- **Elfter Bereich `apps`, Anwendungsliste `src/apps.json` (O1, O2):** je Anwendung `key`, `label`, `processes` (aus dem geführten Bericht), dazu `installed` (eine Probe ohne Kennung) und `probes`. Fünf Lesearten, keine anderen: `registryValue` (Pfad unter `HKLM` und Wertname), `registryKey` (vorhanden, Zahl der Werte oder Unterschlüssel), `service` (Zustand, Startart), `scheduledTask` (vorhanden, eingeschaltet, letzter und nächster Lauf), `file` (vorhanden, Dateiversion). Jede Probe liefert genau einen Fakt `apps.<key>.<id>`; das Feld `read` wählt, welche Angabe der Leseart er trägt. `names: true` kennzeichnet einen Registrierungswert, der Namen tragen kann; er wird wie freier Servertext behandelt. Der Collector liest die Datei beim Start (`-AppsFile`, Vorgabe neben dem Skript), lehnt eine fehlerhafte Datei ab, bevor er etwas anlegt, und kopiert sie in die Aufzeichnung. *Wenn falsch:* ein Feld der Datei heißt anders; es ändern sich `Read-WorkerPerfHealthApps` (Task 1b) und sein Test.
- **Eine Erweiterung der Leseart `file` (Offene Punkte 1):** ein Pfad darf in genau einem Ordnernamen ein `*` tragen. Ohne sie ist das neue Teams nicht erkennbar: Microsoft dokumentiert es nur unter einem Ordner, dessen Name die Version enthält. *Wenn falsch:* die Erweiterung entfällt, und Teams braucht eine sechste Leseart oder gilt als nicht erkennbar.
- **Nicht installiert (O3, P4):** `apps.<key>.installed` kommt aus der Probe `installed`; ist die Anwendung nicht installiert, werden ihre Proben nicht gelesen, ihre Prüfungen haben das Ergebnis „trifft nicht zu" und zählen nicht, und der Bereich nennt sie „nicht installiert". `health.json` trägt im Bereich `apps` eine Liste mit einer Zeile je Probe (das Feld `App` nennt die Anwendung). Das weicht im Aufbau von O3 ab, das eine Liste von Anwendungen mit ihren Proben vorsieht: die Werteliste kennt nur Listen von Objekten mit festen Feldern, und Maskierung und Rohwertanzeige arbeiten darauf. *Wenn falsch:* soll der Aufbau geschachtelt sein, bekommt das Format die Nummer 2; erzeugt eine nicht installierte Anwendung „nicht prüfbar", hält Review Focus 3 dagegen.
- **Der Katalog kennt die Anwendungen aus der Datei (O4):** die Fakten `apps.<key>.<id>` entstehen aus der Anwendungsliste neben dem Berichtsskript (dessen Parameter `-AppsFile`); eine Prüfung des Bereichs `apps` nennt Werte genau einer Anwendung; eine Prüfung auf eine Anwendung oder Probe, die nicht in der Liste steht, wird beim Laden abgelehnt. Eine Aufzeichnung, deren Anwendungsliste eine Probe noch nicht hatte, liefert dafür „nicht prüfbar". *Wenn falsch:* Katalog und Anwendungsliste müssen zusammen geändert werden; die Meldung nennt Prüfung und Wert.
- **Eine Datei, zwei Leser (O5):** der geführte Bericht hat `src/apps.json` angelegt (fünf Anwendungen: `edge`, `webview2`, `office`, `teams`, `printaurus`) und liest sie mit `Read-WorkerPerfApps` in `src/WorkerPerf.Guidance.ps1` für seine Bedingung `app.<key>`; weitere Felder einer Anwendung lässt dieser Leser stehen. Dieser Plan ergänzt `installed` und `probes` und liest die Datei mit einer eigenen Funktion `Read-WorkerPerfHealthApps` in `src/WorkerPerf.Common.ps1`, weil der Collector `src/WorkerPerf.Guidance.ps1` nicht einbindet. Beide Leser verlangen `key`, `label` und `processes` gleich (dieselbe Regel für `key`, dieselbe Form der Meldungen); die Regeln für die Prozessmuster prüft nur der Leser des geführten Berichts. Eine Anwendung ohne `installed` liest das Zustandsbild nicht. Der geführte Bericht legt die Liste, wie sie in der Datei steht, als `appList` in die Berichtsdaten; Task 2 ordnet deshalb die neuen Felder im Bestand der Maskierung ein. *Wenn falsch:* die zwei Leser laufen auseinander; nach dem Abschluss beider Bausteine lassen sie sich in `src/WorkerPerf.Common.ps1` zusammenlegen (Offene Punkte 5).
- **Erste Anwendungen (N1, O6):** `edge`, `office`, `teams` mit den Proben aus Task 2; nur maschinenweite, dokumentierte Orte. Einstellungen je Benutzer (`HKCU`) werden nicht gelesen. Die Citrix-Seite der Teams-Optimierung (zwei Dienste) steht im Bereich `vda`. Die zwei weiteren Anwendungen der Datei bleiben ohne `installed`: die WebView2-Runtime liest das Zustandsbild als Probe von Edge und von Teams, den Client des Zuordnungswerkzeugs im Bereich `print` (sein Installationsordner ist nicht dokumentiert, eine Probe `file` hätte keinen belegten Pfad). *Wenn falsch:* eine Probe zeigt auf den falschen Ort; sie steht dann als „nicht gesetzt" da, und Task 22 berichtigt die Datei ohne Code.

**Berichtsdaten und Maskierung (F, P8)**

- **Abschnitt `health`** der Berichtsdaten und `health[]` je Vorfall; Kopiertexte je Prüfung und Bereich mit `Format-WorkerPerfCopyLines` und der Maske wie im geführten Bericht. Jeder Satz, den die Seite zeigt, steht in den Daten, auch die Zeile einer Kachel, der Vermerk eines nicht gelesenen Bereichs, der Zustand eines Rohwerts und der Satz zur Zielumgebung. *Wenn falsch:* ein Feld mehr oder weniger in den Berichtsdaten; Bestand und Seite folgen.
- **Namen:** `New-WorkerPerfMask` liest `health.json` als weiteren Schritt nach den bisherigen (die bisherigen Nummern bleiben). Freier Servertext (Name und Befehl einer geplanten Aufgabe, Ausschlusspfade von Defender, Rohwerte der Citrix- und Profilverwaltungsrichtlinien, Anwendungswerte mit `names: true`, die Fehlermeldung eines Bereichs) steht in eigenen Feldern, die ein maskierter Bericht leert. Der Profilordner `Administrator` gilt nicht als Person (P8). *Wenn falsch:* ein Name steht im maskierten Bericht; der Markertest und die Prüfung „kein Name aus `health.json`" halten dagegen.

**Seite (G, P6)**

- **Geführte Ansicht:** Zeile `#healthRow` zwischen `#hints` und `#timeline` mit elf Kacheln; Bereichsansicht `#area[data-area]` ersetzt die Startseite wie die Vorfallsansicht (Adressteil `a=<Bereich>`); Abschnitt `.iv-health` „Dazu im Zustandsbild" nach `.iv-todo`. **Expertenansicht:** neunter Reiter `health`. **Kopf:** Lesezeitpunkt, Dauer, geänderte Schwellen, Zahl der nicht prüfbaren Prüfungen. **Zustandsbericht:** „Zustandsbericht ohne Messung", Zeile, Bereichsansichten, Rückblick; nirgends „keine Vorfälle"; der Rückblick heißt dort „vor dem Lesen", nicht „vor der Messung". *Wenn falsch:* eine Stelle der Seite liegt anders, als der Auftraggeber sie erwartet; die Berichtsdaten ändern sich nicht.

**Simulation und Tests (H, O7)**

- **Die Simulation** liefert ein erfundenes Zustandsbild: nicht isolierter Treiber (mit dem Absturz des Druckdienstes der simulierten Stunde: `act`), ein Profilcontainer bei 96 % (`act`, harte Grenze), eine geplante Aufgabe in der Arbeitszeit, ein ausstehender Neustart, Abstürze an mehreren Tagen des Rückblicks, der Hintergrundmodus von Edge eingeschaltet und die automatische Aktualisierung von Teams nicht abgeschaltet (`check`), verborgene Ausschlüsse (`unknown`), Office installiert und in Ordnung, der Rest in Ordnung. Der Energiesparplan des simulierten Workers ist „Höchstleistung" (die Ausnahme des Auftraggebers ist dort erfüllt; den Plan „Ausbalanciert" prüft ein eigener Test in Task 14a). Die Anwendungsliste der Tests nennt eine vierte, erfundene Anwendung mit Proben (neben Edge, Office und Teams), die auf dem simulierten Worker nicht installiert ist. Dauern sind 0. *Wenn falsch:* die Demo zeigt eine Lage, die der Auftraggeber so nicht sehen will; das Drehbuch ist eine Tabelle.
- **Windows-Lesungen** sind dünn und laufen in den Tests über Platzhalter; neu sind Platzhalter für die Registrierung und für jede neue Windows-Schnittstelle; jeder Platzhalter kann seinen Aufruf verzögern, damit das Zeitlimit greift. Die neue C#-Hilfsklasse wird in den Tests übersetzt, das Zerlegen des Filterpuffers ist eine reine Funktion mit Test. *Wenn falsch:* ein Lesefehler zeigt sich erst auf dem Worker; der erste echte Lauf (Task 22) ist deshalb Teil des Bausteins.

**Reihenfolge (I, P10)**

- **Vier Teile** wie im Abschnitt „Reihenfolge und Parallelität". Gegenüber dem ersten Entwurf sind Format (1a), Lesen der Anwendungsliste (1b) und Simulation (3) getrennt, die Proben der Anwendungsliste (2) und ihr Windows-Leser (7) sind eigene Tasks, und der Inhalt des Katalogs ist auf drei Tasks verteilt (14a bis 14c): ein Prüfer kann ein Stück annehmen und ein anderes zurückweisen. *Wenn falsch:* zwei Tasks werden zusammen geprüft.

## Werte, Fakten und Prüfungen je Bereich

Dieser Abschnitt ist die Liste, die der Entwurf (3.2) dem Plan überlässt. Er gilt für die Tasks 1a bis 7 (Werte), 12 (abgeleitete Fakten), 13 und 14a bis 14c (Prüfungen). Die Texte der Prüfungen entstehen in den Tasks 14a bis 14c, nicht hier.

**Lesart der Wertetabellen.** *Kennung* = Schlüssel in `Values` des Bereichs und Kennung des Fakts im Katalog. *Typ*: `number`, `bool`, `text`, `time` (Millisekunden seit 1970, UTC; 0 = unbekannt), `value` (Zahl, Ja/Nein oder Text ohne Namen: der Wert einer Probe einer Anwendung), `list` (Liste von Objekten mit den genannten Feldern; immer eine Liste, auch mit einem oder keinem Eintrag). Ein Zusatz hinter `text` sagt, welche Namen der Wert trägt und wie die Maskierung ihn nimmt: `:host` (Server oder Adresse), `:hosts` (mehrere, durch Leerzeichen getrennt), `:share` (`\\server\freigabe`), `:path` (Pfad; Server, Freigabe und Benutzerordner darin), `:user` (Konto einer Sitzung), `:domain`, `:client`, `:address` (IPv4 oder IPv6), `:protected` (Dienst-, Treiber-, Produktname: bleibt stehen), `:free` (freier Servertext: wird in einem maskierten Bericht geleert). *Zustände*: ohne Angabe `read`, bei einem Lesefehler `unreadable` mit `rights`, `timeout` oder `error`; genannt ist, wann ein Wert `absent` ist. „Gemeinsame Abfrage" = einmal je Aufruf für alle Bereiche. *Dokument* = Titel des Dokuments, das die Lesequelle beschreibt; seine Adresse trägt Task 14c in `docs/guidance/quellen.md` ein. „**nicht dokumentiert**" heißt: der Wert wird aufgezeichnet und als Rohwert gezeigt, keine Prüfung stützt sich auf ihn (D1, P2); in der Werteliste trägt er `Documented = $false`, und der Lader des Katalogs lehnt eine Prüfung ab, die ihn nennt. Wo ein Name (eines Dienstes, Treibers oder Uninstall-Eintrags) aus einem Herstellerdokument stammt, die Schreibweise auf dem Worker aber erst der erste echte Lauf bestätigt, steht das in der Spalte „Dokument".

**Lesart der abgeleiteten Fakten.** Sie entstehen bei der Auswertung (Task 12), stehen nicht in `health.json` und haben denselben Aufbau `State`, `Reason`, `Value`. Ist ein Wert, aus dem ein Fakt gebildet wird, `unreadable`, ist der Fakt `unreadable` mit demselben Grund; ist er `absent`, ist der Fakt `absent` mit demselben Grund, sofern die Regel nichts anderes sagt. Zahlen sind auf eine Nachkommastelle gerundet (`[MidpointRounding]::AwayFromZero`). `ReadAt` ist der Lesezeitpunkt. Gründe eines Fakts sind die vier eines gelesenen Werts (`rights`, `notInstalled`, `timeout`, `error`) und, nur bei Fakten der Auswertung, `notRecorded` (die Datei fehlt in der Aufzeichnung), `skipped:<Kategorie>` (die Kategorie ist weggelassen) und `notInUse`. `notInstalled` („das Produkt ist auf diesem Worker nicht da", bei abgeleiteten Fakten auch: „der Worker ist keine VMware-VM") steht auch bei gelesenen Werten in `health.json`; `notInUse` („die Zuordnung über Citrix-Richtlinien ist nicht in Gebrauch") gibt es nur bei abgeleiteten Fakten. Beide stehen immer mit dem Zustand `absent` und machen eine Prüfung, die den Fakt in einer Bedingung nennt, zu „trifft nicht zu".

**Lesart der Prüfungen.** *Regel* nennt die Bedingungen für „prüfen" und, wo vorhanden, für „handeln"; „vorhanden und" steht für eine vorangestellte Bedingung `exists`. *Art*: `vendor` = „Empfehlung des Herstellers", `practice` = „Empfehlung aus der Praxis" (eine Praxisquelle der geltenden Liste, in der ersten Fassung BIS-F oder carlstalhood.com; die Klammer nennt die Seite), `rule` = „Faustregel". Eine Empfehlung der Praxisquellen ist nur aufgenommen, wo ihre Quellenprüfung sie stützt; was dort gestrichen wurde, steht nicht in der Regel. *Bezug*: Situationen des geführten Berichts (`$script:WorkerPerfSituations`) und Muster (`pattern.<id>`). Schwellen mit `@` stehen in der Tabelle am Ende des Abschnitts.

### Größe und Reserve (`size`)

| Kennung | Was | Typ, Einheit | Lesequelle | Dokument | Zustände |
|---|---|---|---|---|---|
| `size.cpuLogical` | logische Prozessoren | number | `Win32_ComputerSystem.NumberOfLogicalProcessors` (das beim Initialisieren gelesene Objekt) | Win32_ComputerSystem class | |
| `size.cpuSockets` | Prozessorsockel | number | `.NumberOfProcessors` desselben Objekts | Win32_ComputerSystem class | |
| `size.memTotalMB` | Arbeitsspeicher | number, MB | `.TotalPhysicalMemory` / 1048576, gerundet | Win32_ComputerSystem class | |
| `size.commitTotalMB` | zugesagter Speicher beim Lesen | number, MB | P/Invoke `psapi.dll` `GetPerformanceInfo`: `CommitTotal` × `PageSize` | GetPerformanceInfo function; PERFORMANCE_INFORMATION structure | |
| `size.commitLimitMB` | Zusagegrenze | number, MB | `CommitLimit` × `PageSize` | GetPerformanceInfo function; PERFORMANCE_INFORMATION structure | |
| `size.commitPeakMB` | Höchststand der Zusage seit dem Start | number, MB | `CommitPeak` × `PageSize` | GetPerformanceInfo function; PERFORMANCE_INFORMATION structure | |
| `size.pagefiles` | Auslagerungsdateien | list: `Path` text:path, `AllocatedMB` number, `PeakUsageMB` number, `Temporary` bool | `Win32_PageFileUsage`: `Name`, `AllocatedBaseSize`, `PeakUsage`, `TempPageFile` | Win32_PageFileUsage class | leere Liste = keine Datei |
| `size.pagefileManaged` | Auslagerungsdatei vom System verwaltet | bool | `Win32_ComputerSystem.AutomaticManagedPagefile` | Win32_ComputerSystem class | |
| `size.hypervisor` | läuft unter einem Hypervisor | bool | `.HypervisorPresent` | Win32_ComputerSystem class | |
| `size.model` | Hersteller und Modell | text | `.Manufacturer` und `.Model`, mit Leerzeichen verbunden | Win32_ComputerSystem class | |
| `size.vmtoolsPresent` | VMware Tools vorhanden | bool | Registrierung: Schlüssel `HKLM\SOFTWARE\VMware, Inc.\VMware Tools` vorhanden | **nicht dokumentiert** | |
| `size.vmtoolsService` | Zustand des Dienstes `VMTools` | text | `Win32_Service.State` (gemeinsame Abfrage) | Win32_Service class; Dienstname **nicht dokumentiert** | `absent`/`notInstalled` ohne den Dienst |
| `size.vmtoolsVersion` | Version der VMware Tools | text | Registrierung `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*` und `HKLM\SOFTWARE\WOW6432Node\…\Uninstall\*`: Eintrag mit `DisplayName` „VMware Tools", Wert `DisplayVersion` (gemeinsame Abfrage) | Windows Installer Properties for the Uninstall Registry Key | `absent`/`notInstalled` ohne Eintrag |
| `size.netAdapters` | Netzwerkadapter | list: `Name` text, `Service` text, `SpeedMbit` number, `Enabled` bool | `Win32_NetworkAdapter` mit `PhysicalAdapter = TRUE`: `Name`, `ServiceName`, `Speed` / 1000000, `NetEnabled` | Win32_NetworkAdapter class | |
| `size.storageControllers` | Speicheradapter | list: `Name` text, `Driver` text | `Win32_SCSIController`: `Name`, `DriverName` | Win32_SCSIController class | |
| `size.balloonDriver` | Zustand des Ballon-Treibers der VMware Tools | text | `Win32_SystemDriver` mit `Name = 'vmmemctl'`: `State` (gemeinsame Abfrage der Systemtreiber) | Win32_SystemDriver class; Memory Balloon Driver (VMware: nennt den Treiber `vmmemctl`; dass der Treiberdienst so heißt, bestätigt der erste echte Lauf) | `absent`/`notInstalled` ohne den Treiber |

Nicht gelesen: MAC-Adressen, Verbindungsnamen der Adapter, `InstallPath` der VMware Tools; die Zähler der VMware Tools für Ballon, Host-Auslagerung, Grenzen und Reservierung (ihre Namen stehen in keinem geöffneten VMware-Dokument); `VMwareToolboxCmd.exe` (ein Programm wird nicht gestartet).

| Abgeleiteter Fakt | Typ | Regel |
|---|---|---|
| `size.commitPeakPct` | number, % | 100 × `size.commitPeakMB` / `size.commitLimitMB` |
| `size.commitNowPct` | number, % | 100 × `size.commitTotalMB` / `size.commitLimitMB` |
| `size.pagefileCount` | number | Einträge von `size.pagefiles` mit `Temporary` = falsch |
| `size.memPerSessionMB` | number, MB | `size.memTotalMB` / `sessions.userCount`; `absent`, wenn keine Benutzersitzung besteht |
| `size.sessionsPerCpu` | number | `sessions.userCount` / `size.cpuLogical` |
| `size.commitOfRamPct` | number, % | 100 × `size.commitTotalMB` / `size.memTotalMB` |
| `size.vmware` | bool | `size.model` beginnt mit „VMware" |
| `size.vmtoolsMajor` | number | die Zahl vor dem ersten Punkt von `size.vmtoolsVersion`; 0, wenn `size.vmware` ja ist und der Eintrag fehlt; `absent`/`notInstalled`, wenn `size.vmware` nein ist |
| `size.balloonRunning` | bool | `size.balloonDriver` = `Running`; nein, wenn `size.vmware` ja ist und der Treiber fehlt; `absent`/`notInstalled`, wenn `size.vmware` nein ist |
| `size.otherNetAdapters` | number | Einträge von `size.netAdapters` mit `Enabled` = wahr, deren `Name` nicht „vmxnet3" enthält (ohne Rücksicht auf Groß- und Kleinschreibung); `absent`/`notInstalled`, wenn `size.vmware` nein ist |
| `size.lsiControllers` | number | Einträge von `size.storageControllers`, deren `Driver` mit `LSI_` beginnt; `absent`/`notInstalled`, wenn `size.vmware` nein ist |

| Prüfung | Fakten | Regel | Art | Bezug |
|---|---|---|---|---|
| `size.commitHeadroom` | `size.commitPeakPct`, `size.commitNowPct` | prüfen: `commitPeakPct` ≥ `@commitPeakPct`; handeln: `commitNowPct` ≥ `@commitNowPct` (harte Grenze) | rule | memory, crash, hang |
| `size.pagefilePresent` | `size.pagefileCount` | prüfen: = 0 | vendor (Microsoft: How to determine the appropriate page file size for 64-bit versions of Windows) | crash, memory |
| `size.memoryPerSession` | `size.memPerSessionMB` | prüfen: vorhanden und < `@memPerSessionMB` | rule (Beleg für die Größenordnung: Microsoft nennt für Edge auf VDI 1 GB je Benutzer, Microsoft Edge for Virtual desktop infrastructure (VDI)) | memory, delay.many |
| `size.cpuPerSession` | `size.sessionsPerCpu` | prüfen: > `@sessionsPerCpu` | rule | cpu, delay.many |
| `size.commitAboveRam` | `size.commitOfRamPct` | prüfen: > 100 | practice (Stalhood: Citrix Health Check) | memory, disk, delay.many |
| `size.workerCpu` | `size.cpuLogical` | prüfen: < `@workerCpuMin` | practice (Stalhood: Citrix Virtual Delivery Agent (VDA) 2411) | cpu, delay.many |
| `size.workerMemory` | `size.memTotalMB` | prüfen: < `@workerMemMinMB` | practice (Stalhood: Citrix Virtual Delivery Agent (VDA) 2411) | memory, delay.many |
| `size.vmTools` | `size.vmtoolsMajor`, `size.vmtoolsVersion` | prüfen: `vmtoolsMajor` < 12 (fehlende Tools zählen als 0) | vendor (VMware: VMware Tools Lifecycle Management; für Windows Server 2022 „for best performance" ab 12.0.0) | system, crash |
| `size.balloonDriver` | `size.balloonRunning` | prüfen: = nein | vendor (VMware: Solutions for Memory Performance Problems) | memory |
| `size.netAdapterType` | `size.otherNetAdapters` | prüfen: > 0 | vendor (VMware: Poor network performance or high network latency on Windows virtual machines; Stalhood nennt dasselbe) | share, delay.many |
| `size.storageController` | `size.lsiControllers` | prüfen: > 0 (Hinweis, nie „handeln") | vendor (VMware: SCSI, SATA, and NVMe Storage Controller Conditions, Limitations, and Compatibility) | disk, profile |

Nicht aufgenommen aus den Recherchen (Grund in `docs/guidance/quellen.md`, Tabelle „Nicht aufgenommen"): Auslagerungsdatei mindestens RAM minus Reservierung (die Reservierung ist lokal nur über nicht dokumentierte Zähler lesbar), CPU-Hot-Add und vNUMA (im Gast nicht lesbar), Bereitschaftszeit (Host-Zähler), Auslagerungsdatei fest eingestellt (BIS-F: nur auf Wunsch, ohne Begründung in der Quelle), Schreibcache und Geister-NICs (nur Provisioning Services).

### Betrieb (`operation`)

| Kennung | Was | Typ, Einheit | Lesequelle | Dokument | Zustände |
|---|---|---|---|---|---|
| `operation.lastBoot` | letzter Start | time | `Win32_OperatingSystem.LastBootUpTime` (das beim Initialisieren gelesene Objekt) | Win32_OperatingSystem class | |
| `operation.pendingRename` | ausstehende Umbenennungen beim Neustart, Anzahl der Paare | number | Registrierung `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager`, Wert `PendingFileRenameOperations` (Zahl der Einträge / 2; ohne den Wert 0). Die Pfade werden nicht gespeichert. | MoveFileExA function | |
| `operation.pendingServicing` | Komponentenwartung wartet auf einen Neustart | bool | Registrierung: Schlüssel `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending` vorhanden | **nicht dokumentiert** | |
| `operation.pendingUpdate` | Windows Update wartet auf einen Neustart | bool | Registrierung: Schlüssel `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired` vorhanden | **nicht dokumentiert** | |
| `operation.lastUpdate` | jüngstes Installationsdatum eines Updates | time | `Win32_QuickFixEngineering.InstalledOn`, der jüngste lesbare Wert: ein `DateTime` wird übernommen, ein Text nur im Format `M/d/yyyy` gelesen (`ParseExact`, invariante Kultur); jedes andere Format zählt als nicht lesbar, der Eintrag wird übergangen | Win32_QuickFixEngineering class | `absent` ohne lesbares Datum |
| `operation.lastUpdateId` | Kennung dieses Updates | text | `.HotFixID` desselben Eintrags | Win32_QuickFixEngineering class | `absent` ohne lesbares Datum |
| `operation.powerPlan` | aktiver Energiesparplan | text: `balanced`, `highPerformance`, `powerSaver`, `other` | P/Invoke `powrprof.dll` `PowerGetActiveScheme`; Zuordnung über die dokumentierten GUIDs (`381b4222-f694-41f0-9685-ff5bb260df2e` balanced, `8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c` highPerformance, `a1841308-3541-4fab-bc81-f71556f20b4a` powerSaver) | PowerGetActiveScheme function; Power Policy Settings | |
| `operation.volumes` | lokale Laufwerke | list: `Drive` text, `SizeGB` number, `FreeGB` number, `FileSystem` text, `System` bool, `PageFile` bool (leer = unbekannt) | `Win32_LogicalDisk` mit `DriveType = 3`: `DeviceID`, `Size`, `FreeSpace`, `FileSystem`; `System` aus `Win32_OperatingSystem.SystemDrive`; `PageFile`, wenn ein Pfad aus `size.pagefiles` auf dem Laufwerk liegt. Gelesen wird zuerst `Win32_LogicalDisk`; lässt sich die Liste der Auslagerungsdateien nicht lesen, bleibt der Wert gelesen und `PageFile` ist leer | Win32_LogicalDisk class; Win32_OperatingSystem class | |

Nicht gelesen: der Windows-Update-Agent (`Microsoft.Update.*`), Bezeichnungen der Laufwerke, Volumes ohne Laufwerksbuchstaben (Profilcontainer gehören zum Bereich Profilverwaltung).

| Abgeleiteter Fakt | Typ | Regel |
|---|---|---|
| `operation.uptimeDays` | number, Tage | (`ReadAt` − `operation.lastBoot`) in Tagen |
| `operation.updateAgeDays` | number, Tage | (`ReadAt` − `operation.lastUpdate`) in ganzen Tagen |
| `operation.minFreeGB` | number, GB | kleinstes `FreeGB` der Laufwerke mit `System` = wahr oder `PageFile` = wahr (ein Laufwerk mit unbekanntem `PageFile` zählt nur über `System`); `absent` ohne ein solches Laufwerk |

| Prüfung | Fakten | Regel | Art | Bezug |
|---|---|---|---|---|
| `operation.pendingRestart` | `operation.pendingRename` | prüfen: > 0 | rule | crash, hang, service, system |
| `operation.uptime` | `operation.uptimeDays` | prüfen: > `@uptimeDays` | practice (Stalhood: Citrix Health Check: Multi-Session-VDAs regelmäßig neu starten; die Quelle nennt keine Zahl, die Schwelle ist ein Vorschlag) | memory, hang |
| `operation.updateAge` | `operation.updateAgeDays` | prüfen: vorhanden und > `@updateAgeDays` (der Befund spricht vom Stand des Abbilds) | practice (Stalhood: Citrix Health Check: höchstens 60 Tage) | system, crash |
| `operation.powerPlan` | `operation.powerPlan` | prüfen: ≠ `highPerformance`. Ausnahme des Auftraggebers (Entwurf 4.3, Q2): hier gilt die Praxisquelle vor dem Hersteller; der Katalog führt die Prüfung in `precedence` mit seiner Begründung, und `meaning` nennt weiter die Vorgabe „Ausbalanciert" von Microsoft und dass VMware „Höchstleistung" nennt, solange Latenzprobleme untersucht werden | practice (Stalhood: Citrix Health Check, „Power management is set to High Performance"; BIS-F stellt beim Versiegeln denselben Plan ein) | cpu, delay.many |
| `operation.diskFree` | `operation.minFreeGB` | prüfen: vorhanden und < `@diskFreeGB`; handeln: vorhanden und < `@diskFreeHardGB` (harte Grenze) | rule | disk, memory, crash, profileerror |

Nicht aufgenommen: Zeitgeber für Schlaf und Ruhezustand des aktiven Plans (Stalhood nennt „no sleep timers", ordnet diese Einstellungen auf seiner Seite zu den Gruppenrichtlinien aber eher virtuellen Desktops als Sitzungshosts zu; die Werteliste liest sie nicht).

### Sitzungen (`sessions`)

| Kennung | Was | Typ, Einheit | Lesequelle | Dokument | Zustände |
|---|---|---|---|---|---|
| `sessions.list` | Sitzungen beim Lesen | list: `Id` number, `State` text, `WinStation` text:path, `User` text:user, `Domain` text:domain, `Client` text:client, `LogonTime` time, `ConnectTime` time, `DisconnectTime` time, `IdleMinutes` number (−1 = unbekannt) | WTS-Hülle der Quelle (`WTSEnumerateSessionsW`, `WTSQuerySessionInformationW` mit `WTSSessionInfo`), um `ConnectTime` und `DisconnectTime` ergänzt (gemeinsame Abfrage) | WTSINFOW structure; WTS_INFO_CLASS enumeration; WTS_CONNECTSTATE_CLASS enumeration | `unreadable`/`error`, wenn die Abfrage scheitert oder der in der Konsole geladene Typ die neuen Felder nicht hat |
| `sessions.limits` | wirksame Zeitlimits je Listener | list: `Terminal` text, `IdleLimitMin` number, `DisconnectedLimitMin` number, `ActiveLimitMin` number (je 0 = unbegrenzt), `BrokenAction` number, `FromPolicy` bool | CIM `root\CIMv2\TerminalServices` `Win32_TSSessionSetting`: `TerminalName`, `IdleSessionLimit`, `DisconnectedSessionLimit`, `ActiveSessionLimit` (ms / 60000), `BrokenConnectionAction`, `PolicySourceDisconnectedSessionLimit` = 1 | Win32_TSSessionSetting class | `unreadable`/`rights`, wenn der Namespace die lokale Abfrage ablehnt (das Dokument verlangt Packet Privacy; der erste echte Lauf zeigt es) |
| `sessions.localProfiles` | lokale Profile | list: `Path` text:path, `Loaded` bool, `Special` bool, `LastUse` time, `Temporary` bool | `Win32_UserProfile`: `LocalPath`, `Loaded`, `Special`, `LastUseTime`, `Status` (ein Bitfeld: Bit 1 gesetzt = temporär, geprüft mit `-band 1`) | Win32_UserProfile class | |

Nicht gelesen: Größe der Profilordner, SIDs der Profile, Client-Adressen, Richtlinienwerte der Benutzer.

| Abgeleiteter Fakt | Typ | Regel |
|---|---|---|
| `sessions.userCount` | number | Einträge von `sessions.list` mit `User` |
| `sessions.disconnectedCount` | number | davon mit `State` = `Disconnected` |
| `sessions.disconnectedOldestHours` | number, Stunden | größtes (`ReadAt` − `DisconnectTime`) der getrennten Benutzersitzungen mit bekanntem Trennzeitpunkt; 0 ohne eine solche |
| `sessions.disconnectLimitMin` | number, Minuten | kleinstes `DisconnectedLimitMin` > 0 aus `sessions.limits`; `absent`, wenn kein Listener ein Limit hat |
| `sessions.idleLimitMin` | number, Minuten | kleinstes `IdleLimitMin` > 0 aus `sessions.limits`; `absent`, wenn kein Listener ein Limit hat |
| `sessions.unloadedProfiles` | number | Einträge von `sessions.localProfiles` mit `Loaded` = falsch und `Special` = falsch |
| `sessions.tempProfiles` | number | Einträge mit `Temporary` = wahr |

| Prüfung | Fakten | Regel | Art | Bezug |
|---|---|---|---|---|
| `sessions.disconnectLimit` | `sessions.disconnectLimitMin` | prüfen: nicht vorhanden (`absent`); der Text sagt, dass ein Zeitgeber aus einer Citrix-Richtlinie nicht gesehen wird (P7) | practice (Stalhood: Group Policy Computer Settings for VDAs; Citrix Health Check: Zeitlimits setzen, Größenordnung drei Stunden) | memory, cpu |
| `sessions.idleLimit` | `sessions.idleLimitMin` | prüfen: nicht vorhanden (`absent`); derselbe Vorbehalt | practice (Stalhood: Group Policy Computer Settings for VDAs; Citrix Health Check) | memory, cpu |
| `sessions.disconnectedOld` | `sessions.disconnectedOldestHours` | prüfen: > `@disconnectedHours` | rule | memory, profile |
| `sessions.unloadedProfiles` | `sessions.unloadedProfiles`, `operation.lastBoot` | prüfen: `unloadedProfiles` > `@unloadedProfiles`; der Befund nennt den letzten Start als Grenze (K3) | rule | disk, profile, profileerror |
| `sessions.tempProfiles` | `sessions.tempProfiles`, `operation.lastBoot` | prüfen: `tempProfiles` > 0; handeln: > 0 und Ereignis `profileerror` mindestens 1 in 7 Tagen; der Befund nennt den letzten Start als Grenze (K3) | rule | profileerror, profile |

### Citrix VDA (`vda`)

| Kennung | Was | Typ, Einheit | Lesequelle | Dokument | Zustände |
|---|---|---|---|---|---|
| `vda.version` | installierte Version | text | Uninstall-Einträge (gemeinsame Abfrage wie `size.vmtoolsVersion`): `DisplayName` wie `Citrix*Virtual Delivery Agent*`, Wert `DisplayVersion` | Windows Installer Properties for the Uninstall Registry Key (das Muster des Namens ist eine Annahme; der erste echte Lauf bestätigt es) | `absent`/`notInstalled` ohne Eintrag |
| `vda.services` | Citrix-Dienste | list: `Name` text:protected, `State` text, `StartMode` text | `Win32_Service` (gemeinsame Abfrage): Dienste, deren `PathName` einen Ordner `\Citrix\` enthält | Win32_Service class | leere Liste ohne Citrix-Dienst |
| `vda.desktopService` | Zustand des Dienstes „Citrix Desktop Service" | text | derselbe Bestand: Dienst mit dem Anzeigenamen (`DisplayName`) „Citrix Desktop Service" | Win32_Service class; CTX133769 VDA Registration Failure with Event ID: 1001 (nennt den Dienst mit diesem Namen) | `absent`/`notInstalled` ohne den Dienst |
| `vda.controllers` | Controllerliste | list: `Entry` text:host, `Kind` text (`fqdn`, `short`, `ip`), `From` text (`policy`, `registry`) | Registrierung `HKLM\SOFTWARE\Policies\Citrix\VirtualDesktopAgent`, Wert `ListOfDDCs`; ist er leer oder fehlt er: `HKLM\SOFTWARE\Citrix\VirtualDesktopAgent` (auch `WOW6432Node`), Wert `ListOfDDCs`; an Leerzeichen und Kommas geteilt. Keine Namensauflösung. | VDA registration (Citrix Virtual Apps and Desktops 2203 LTSR) | leere Liste ohne Wert |
| `vda.listOfSids` | `ListOfSIDs` von Hand gesetzt | bool | Wert `ListOfSIDs` derselben Schlüssel vorhanden und nicht leer (der Inhalt wird nicht gespeichert) | VDA registration | |
| `vda.farmGuid` | Registrierung über die OU (`FarmGUID`) | bool | Wert `FarmGUID` vorhanden und nicht leer (der Inhalt wird nicht gespeichert) | VDA registration | |
| `vda.policyRaw` | Rohwerte der Citrix-Richtlinien | list: `Key` text, `Name` text, `Value` text:free | Registrierung `HKLM\SOFTWARE\Policies\Citrix` rekursiv, ohne die Unterschlüssel `UserProfileManager`, `UserProfileManagerHDX`, `VirtualDesktopAgent`; höchstens 2000 Werte, Tiefe 6 | Schlüssel: CTX557768; Wertnamen **nicht dokumentiert** | leere Liste ohne den Schlüssel |
| `vda.persistentDataLocation` | beständiger Datenort, den die Bereitstellung dem VDA nennt | text:path | CIM `root\Citrix\DesktopInformation` `Citrix_VirtualDesktopInfo.PersistentDataLocation` | VDA registration (nennt Klasse und Eigenschaft) | `absent`/`notInstalled` ohne den Namespace; `absent`, wenn leer |
| `vda.wemService` | Zustand des Dienstes des WEM-Agenten | text | derselbe Bestand: Dienst mit dem Anzeigenamen „Citrix WEM Agent Host Service" oder „Norskale Agent Host Service" | Win32_Service class; Agent (install and configure) – Workspace Environment Management | `absent`/`notInstalled` ohne den Dienst; dann sind alle Werte `vda.wem*` `absent`/`notInstalled` |
| `vda.wemServices` | die Dienste, die der WEM-Agent braucht | list: `Name` text:protected, `State` text, `StartMode` text | derselbe Bestand: die vorhandenen Dienste mit den Anzeigenamen „Citrix WEM Agent Host Service" (oder „Norskale Agent Host Service"), „Citrix WEM User Logon Service" (oder „Citrix WEM Agent User Logon Service") und „System Event Notification Service"; `Name` ist der Anzeigename | WEM health check tool; Agent (install and configure) | |
| `vda.wemVersion` | Version des WEM-Agenten | text | Dateiversion des Programms des Agent-Dienstes (Pfad aus `PathName` über `Get-WorkerPerfServiceExe`, Version über `Get-WorkerPerfFileVersion`) | View log files (Workspace Environment Management: nennt `Citrix.Wem.Agent.Service.exe`) | `absent`, wenn die Datei fehlt |
| `vda.wemServer` | WEM-Server aus der Richtlinie | text:host | Registrierung `HKLM\SOFTWARE\Policies\Norskale\Agent Host`, Wert `BrokerSvcName` | CTX238676 How to properly bind WEM agent machines with WEM broker server on a first time setup | `absent` ohne den Wert |
| `vda.wemCacheLocation` | abweichender Ort des Agent-Cache | text:path | Registrierung `HKLM\SYSTEM\CurrentControlSet\Control\Norskale\Agent Host`, Wert `AgentCacheAlternateLocation` | Agent (install and configure) | `absent`, wenn der Wert fehlt oder leer ist (der Cache liegt dann im Programmordner) |
| `vda.wemGpNetworkTimeout` | Wartewert auf das Netz beim Start | number, s | Registrierung `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon`, Wert `GpNetworkStartTimeoutPolicyValue` | Agent (install and configure), Abschnitt System settings | `absent` ohne den Wert |
| `vda.teamsService` | Zustand des Dienstes „Citrix HDX Teams Redirection Service" | text | derselbe Bestand: Dienst, dessen `PathName` `-g TeamsSvcs` enthält | Monitor, troubleshoot, and support Microsoft Teams (Citrix) | `absent`/`notInstalled` ohne den Dienst |
| `vda.webSocketService` | Zustand des Dienstes „Citrix HDX HTML5 Video Redirection Service" | text | derselbe Bestand: Dienst, dessen `PathName` `WebSocketService.exe` enthält | Monitor, troubleshoot, and support Microsoft Teams (Citrix) | `absent`/`notInstalled` ohne den Dienst |

Nicht gelesen: Transportart der Sitzungen, Registrierungszustand, Ereignistexte der Registrierung, Client-Adressen; die Art der Bereitstellung (kein dokumentierter lokaler Wert nennt sie: K4); vom WEM-Agenten die wirksame Konfiguration und der Inhalt des Cache (Format nicht dokumentiert), seine Protokolle und Berichte; von der Teams-Optimierung alles je Benutzer (`HKCU`, Dateien im Profil) und die Richtlinie „Virtual channel allow list" (Registrierungsort nicht dokumentiert).

| Abgeleiteter Fakt | Typ | Regel |
|---|---|---|
| `vda.stoppedAutoServices` | number | Einträge von `vda.services` mit `StartMode` = `Auto` und `State` ≠ `Running` |
| `vda.controllerCount` | number | Einträge von `vda.controllers` |
| `vda.controllersNotFqdn` | number | davon mit `Kind` ≠ `fqdn` |
| `vda.wemServicesNotReady` | number | Zahl der drei Gruppen aus `$script:WorkerPerfHealthWemServices` (Agent-Dienst, Anmeldedienst, System Event Notification Service), für die `vda.wemServices` keinen Dienst mit einem ihrer Anzeigenamen nennt oder deren Dienst nicht `State` = `Running` und `StartMode` = `Auto` hat; `absent`/`notInstalled`, wenn `vda.wemService` es ist |

| Prüfung | Fakten | Regel | Art | Bezug |
|---|---|---|---|---|
| `vda.services` | `vda.stoppedAutoServices`, `vda.desktopService` | prüfen: `stoppedAutoServices` > 0; handeln: `desktopService` ≠ `Running` und Ereignis `service` mindestens 1 in 7 Tagen | rule | service, delay.many |
| `vda.controllerCount` | `vda.controllerCount`, `vda.farmGuid` | prüfen: `farmGuid` = nein und `controllerCount` = 1 | vendor (Citrix: VDA registration) | service, delay.many |
| `vda.controllerNotFqdn` | `vda.controllersNotFqdn` | prüfen: > 0 | vendor (Citrix: VDA registration) | delay.many |
| `vda.listOfSids` | `vda.listOfSids` | prüfen: = ja | vendor (Citrix: VDA registration) | service |
| `vda.wemServices` | `vda.wemServicesNotReady` | prüfen: > 0 | vendor (Citrix: WEM health check tool) | service, delay.many, profileerror |
| `vda.wemCache` | `vda.wemService`, `vda.wemCacheLocation` | prüfen: `wemService` vorhanden und `wemCacheLocation` nicht vorhanden (der Cache liegt im Programmordner, auf einem nicht persistenten Worker kein beständiger Ort); der Text nennt, dass der Agent des WEM-Dienstes ab 2408.1.0.1 den beständigen Ort selbst findet | vendor (Citrix: Agent (install and configure), Prerequisites; BIS-F nennt dasselbe) | delay.many, system |
| `vda.wemGpTimeout` | `vda.wemGpNetworkTimeout` | prüfen: vorhanden und < 30 | vendor (Citrix: Agent (install and configure), System settings) | delay.many, system |

Nicht aufgenommen: WEM-Server als vollständiger Name in der Richtlinie (laut Quellenprüfung kein Pflichtwert), CPU- und Speicheroptimierung von WEM (Einstellungen lokal nicht lesbar), „Launch agent on reconnection" (nicht belegt), Prüfungen auf die zwei Citrix-Dienste der Teams-Umleitung (sie gehören zur abgekündigten WebRTC-Optimierung; die Zustände stehen als Rohwerte da), VDA-Version für Teams (die Stufe des kumulativen Updates ist aus der Versionsnummer nicht sicher ablesbar).

### Profilverwaltung (`profile`)

| Kennung | Was | Typ, Einheit | Lesequelle | Dokument | Zustände |
|---|---|---|---|---|---|
| `profile.service` | Zustand des Dienstes der Profilverwaltung | text | `Win32_Service` (gemeinsame Abfrage): Dienst, dessen Programm `UserProfileManager.exe` heißt (Pfad des Programms aus `PathName` über `Get-WorkerPerfServiceExe`: `PathName` steht bei einem Pfad mit Leerzeichen in Anführungszeichen und kann Argumente tragen) | Win32_Service class; Advanced troubleshooting checklist (Profile Management) | `absent`/`notInstalled` ohne den Dienst |
| `profile.version` | Version | text | Dateiversion von `UserProfileManager.exe` (`[System.Diagnostics.FileVersionInfo]`, Pfad über `Get-WorkerPerfServiceExe`) | Advanced troubleshooting checklist (Profile Management) | `absent`/`notInstalled` ohne den Dienst |
| `profile.policyGpo` | Rohwerte aus Gruppenrichtlinie oder WEM | list: `Key` text, `Name` text, `Value` text:free | Registrierung `HKLM\SOFTWARE\Policies\Citrix\UserProfileManager` rekursiv (höchstens 2000 Werte) | Schlüssel: CTX288248 Registry locations for Citrix Profile Management; Lage der Werte **nicht dokumentiert** | leere Liste ohne den Schlüssel |
| `profile.policyStudio` | Rohwerte aus Citrix Studio | list: `Key` text, `Name` text, `Value` text:free | Registrierung `HKLM\SOFTWARE\Policies\Citrix\UserProfileManagerHDX` rekursiv | Schlüssel: CTX288248 Registry locations for Citrix Profile Management; Lage der Werte **nicht dokumentiert** | leere Liste ohne den Schlüssel |
| `profile.containers` | eingebundene Container | list: `Location` text:path, `Mount` text:path, `Owner` text:user, `SessionId` number (−1 = unbekannt), `SizeGB` number, `AllocatedGB` number, `VolumeSizeGB` number, `VolumeFreeGB` number, `UsedPct` number | `Get-WorkerPerfProfileDisks -WithSize -TimeoutSec <Rest des Bereichslimits>`: `MSFT_Disk` mit `BusType = 15` (`Location`, `Size`, `AllocatedSize`), `MSFT_Partition` (`AccessPaths`), `MSFT_Volume` (`Path`, `Size`, `SizeRemaining`), verbunden über den Volume-Pfad; `Owner` über `Resolve-WorkerPerfProfileOwner` und die Sitzungen; `UsedPct` = 100 × (`Size` − `SizeRemaining`) / `Size` des Volumes. Die Datei auf der Freigabe wird nicht geöffnet. | MSFT_Disk class; MSFT_Partition class; MSFT_Volume class | leere Liste ohne Container |

Nicht gelesen: `UPMSettings.ini` im Benutzerspeicher, die INI-Datei im Installationsordner, das Konfigurationsprotokoll, Inhalte der Container.

| Abgeleiteter Fakt | Typ | Regel |
|---|---|---|
| `profile.containerCount` | number | Einträge von `profile.containers` |
| `profile.containerMaxUsedPct` | number, % | größtes `UsedPct`; `absent` ohne Container |
| `profile.maxContainersPerUser` | number | größte Zahl von Containern mit demselben `Owner`; `absent`, wenn kein Besitzer bekannt ist |

| Prüfung | Fakten | Regel | Art | Bezug |
|---|---|---|---|---|
| `profile.containerFull` | `profile.containerMaxUsedPct` | prüfen: vorhanden und ≥ `@containerUsedPct`; handeln: vorhanden und ≥ `@containerUsedHardPct` (harte Grenze) | rule (90 % ist die Auslöseschwelle der automatischen Erweiterung laut Citrix: Profile Management policy descriptions and defaults) | profile, profileerror, disk |
| `profile.containersPerUser` | `profile.maxContainersPerUser` | prüfen: vorhanden und > `@containersPerUser` | rule | profile, disk |
| `profile.serviceStopped` | `profile.service` | prüfen: ≠ `Running`; handeln: ≠ `Running` und Ereignis `profileerror` mindestens 1 in 7 Tagen | rule | profileerror, profile, service |

### Drucken (`print`)

| Kennung | Was | Typ, Einheit | Lesequelle | Dokument | Zustände |
|---|---|---|---|---|---|
| `print.isolationExecution` | Richtlinie zur Treiberisolierung (0 = Isolierung aus) | number | Registrierung `HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers`, Wert `PrintDriverIsolationExecutionPolicy` (der Leser `Get-WorkerPerfPrintIsolationPolicy` des Treiberlesers; dessen Ergebnis wird wiederverwendet, wenn die Treiberliste gelesen wurde) | Printer driver isolation (Wirkung); Policy CSP - ADMX_Printing (Schlüssel und Wertname) | `absent` ohne Richtlinie |
| `print.isolationOverride` | Richtlinie „alle Treiber geteilt" | number | derselbe Schlüssel, Wert `PrintDriverIsolationOverrideCompat` | Printer driver isolation (Wirkung); Policy CSP - ADMX_Printing (Schlüssel und Wertname) | `absent` ohne Richtlinie |
| `print.queueCount` | Zahl der Warteschlangen | number | Zählergruppe `Print Queue`: Instanzen ohne `_Total` (die geöffnete Kategorie der Quelle; ohne `Drucken` öffnet der Leser sie selbst) | Zählergruppe wie für `printqueues.csv` | `absent` ohne die Zählergruppe |
| `print.spooler` | Zustand des Dienstes `Spooler` | text | `Win32_Service.State` (gemeinsame Abfrage) | Win32_Service class | `absent`/`notInstalled` ohne den Dienst |
| `print.spoolerStartMode` | Starttyp des Dienstes | text | `Win32_Service.StartMode` | Win32_Service class | `absent`/`notInstalled` ohne den Dienst |
| `print.citrixPrintService` | Zustand des Dienstes „Citrix Print Manager Service" | text | `Win32_Service` (gemeinsame Abfrage): Dienst mit dem Anzeigenamen „Citrix Print Manager Service" | Win32_Service class; Printing policy settings (Citrix: „Citrix Print Manager service (CpSvc.exe)") | `absent`/`notInstalled` ohne den Dienst |
| `print.operationalLog` | Betriebsprotokoll `Microsoft-Windows-PrintService/Operational` eingeschaltet | bool | `Get-WinEvent -ListLog`: `IsEnabled` | Get-WinEvent (PowerShell 5.1); EventLogConfiguration class | `absent` ohne das Protokoll; jeder andere Fehler der Abfrage `unreadable` |
| `print.mappingClientVersion` | Version des Clients des Zuordnungswerkzeugs (PrinTaurus SmartSpread Client) | text | Uninstall-Einträge (gemeinsame Abfrage wie `size.vmtoolsVersion`): `DisplayName` wie `*SmartSpread Client*`, Wert `DisplayVersion` | Windows Installer Properties for the Uninstall Registry Key; Release Notes PrinTaurus 6.2, Kapitel 4 „Dienst- und Dateiversionen" (AKI: nennt das Installationspaket „PrinTaurus SmartSpread Client x64.msi" mit der Version 6.2.1; dass der Uninstall-Eintrag so heißt und diese Zählung trägt, bestätigt der erste echte Lauf) | `absent`/`notInstalled` ohne Eintrag |

Nicht gelesen: vom Zuordnungswerkzeug alles außer der Version seines Clients (wie und wann er zuordnet, seine Regeln, seine Konfiguration, sein Protokoll und der Ort seines Programms stehen auf keiner öffentlichen Seite des Herstellers; die Regeln liegen zentral, nicht auf dem Worker); die Prozesse der Sitzungen.

Fakten der Auswertung. Die fünf Treiberfakten kommen aus `printdrivers.csv` (Kategorie `Drucken`); sie sind `unreadable` mit dem Grund `skipped:Drucken`, wenn die Kategorie weggelassen ist, mit `notRecorded`, wenn die Datei in der Aufzeichnung fehlt, und mit `error`, wenn `SourceErrors` den Eintrag `printdrivers` hat. `print.queuesPerSession` und `print.mappingClientRelease` entstehen aus `health.json`.

| Abgeleiteter Fakt | Typ | Regel |
|---|---|---|
| `print.driverCount` | number | Treiber der Liste |
| `print.driversInSpooler` | number | Treiber mit `Isolation` = `none` |
| `print.driversV2` | number | Treiber mit `Type` = 2 |
| `print.vendorDrivers` | number | Treiber, deren `Manufacturer` weder mit „Microsoft" noch mit „Citrix" beginnt |
| `print.citrixDrivers` | number | Treiber, deren `Manufacturer` mit „Citrix" beginnt (die Universaltreiber von Citrix; ohne Prüfung) |
| `print.queuesPerSession` | number | `print.queueCount` / max(1, `sessions.userCount`) |
| `print.citrixMapping` | bool | ja, wenn `print.citrixPrintService` = `Running` ist (Citrix kann Drucker zuordnen); `absent`/`notInUse`, wenn der Dienst fehlt oder nicht läuft; `unreadable`, wenn der Dienst es ist |
| `print.mappingClientRelease` | number | Hauptversion × 100 + Nebenversion von `print.mappingClientVersion` („6.2.1" ergibt 602); `unreadable`/`error`, wenn der Text nicht mit zwei durch einen Punkt getrennten Zahlen beginnt |

**Zuordnung über Citrix-Richtlinien (M3).** Eine Prüfung, die voraussetzt, dass Citrix die Drucker zuordnet (automatisch erstellte Client-Drucker, Sitzungsdrucker), nennt `print.citrixMapping` in `values` und beginnt ihre Regel mit der Bedingung `print.citrixMapping` = ja; ist der Fakt `absent`/`notInUse`, hat sie das Ergebnis „trifft nicht zu" mit dem Grund `copy.reasonNotInUse`, zählt nicht, und der Rohwert `print.citrixMapping` zeigt „nicht zutreffend". In der ersten Fassung hat der Katalog keine solche Prüfung (die Wertnamen der Citrix-Druckrichtlinien sind nicht dokumentiert); die ersten sechs Prüfungen unten gelten unabhängig davon, wer die Drucker zuordnet; die siebte gilt dem Client des Zuordnungswerkzeugs und trifft ohne ihn nicht zu. Der Fakt zeigt in der ersten Fassung nur, ob Citrix zuordnen *kann*: ob es das bei laufendem Dienst auch tut, ist aus dokumentierten Quellen nicht lesbar (Offene Punkte 2).

| Prüfung | Fakten | Regel | Art | Bezug |
|---|---|---|---|---|
| `print.driversInSpooler` | `print.driversInSpooler` | prüfen: > 0; handeln: > 0 und Ereignis `print` mindestens 1 in 7 Tagen | vendor (Microsoft: Printer Driver Isolation) | print, pattern.printdriver |
| `print.isolationOff` | `print.isolationExecution` | prüfen: vorhanden und = 0; handeln: vorhanden und = 0 und Ereignis `print` mindestens 1 in 7 Tagen | rule | print |
| `print.driverCount` | `print.vendorDrivers` | prüfen: > `@printDrivers` | rule (Beleg ohne Zahl: Citrix, Printing best practices) | print, delay.single |
| `print.kernelModeV2` | `print.driversV2` | prüfen: > 0 | vendor (Citrix: Printing best practices) | print, system |
| `print.spoolerStopped` | `print.spooler` | prüfen: ≠ `Running` | rule | print, service |
| `print.queueCount` | `print.queuesPerSession` | prüfen: > `@queuesPerSession` | rule | print, delay.single |
| `print.mappingClientSupported` | `print.mappingClientRelease`, `print.mappingClientVersion` | prüfen: `mappingClientRelease` < 602 (eine Version unter 6.2; ohne den Client „trifft nicht zu") | vendor (AKI: Release Notes PrinTaurus 6.4, Kapitel 1 „Abkündigung PrinTaurus Versionen < 6.2") | print, system |

Nicht aufgenommen aus der Dokumentation des Zuordnungswerkzeugs: die Voraussetzung .NET Framework 4.7.2 für den Client ab 6.2 (ein Wert außerhalb des Bereichs, den sonst keine Prüfung braucht: Offene Punkte 6); gleiche Release-Version aller Komponenten und der Hinweis, dass lokale IPP-Warteschlangen in Citrix- und Terminalserver-Umgebungen nicht unterstützt sind (auf dem Worker nicht lesbar; beides steht als Hinweis in `meaning` und `todo` von `print.mappingClientSupported`, mit den Kürzungen der Quellenprüfung); doppelte Warteschlangen vor 6.4, Standarddrucker und das Verhalten beim Wiederverbinden (Hinweise zu Vorfällen: sie stehen im Katalog des geführten Berichts); der Prozess des Clients, das Ereignisprotokoll und die Einstellung `StrictlyMatchingClientNames` (Ort nicht dokumentiert).

### Sicherheitsprodukte (`security`)

| Kennung | Was | Typ, Einheit | Lesequelle | Dokument | Zustände |
|---|---|---|---|---|---|
| `security.services` | alle Dienste | list: `Name` text:protected, `State` text, `StartMode` text | `Win32_Service` (gemeinsame Abfrage: `Name`, `DisplayName`, `State`, `StartMode`, `PathName`; gespeichert werden die drei Felder) | Win32_Service class | |
| `security.defenderService` | Zustand des Dienstes `WinDefend` | text | derselbe Bestand | Microsoft Defender Antivirus on Windows Server | `absent`/`notInstalled` ohne den Dienst; dann sind alle Werte `security.defender*` und `maintenance.scan*` `absent`/`notInstalled`, und die Defender-Klassen werden nicht abgefragt |
| `security.defenderMode` | Betriebsart (`Normal`, `Passive`, `EDR Block Mode`, …) | text | CIM `root\Microsoft\Windows\Defender` `MSFT_MpComputerStatus.AMRunningMode` | Get-MpComputerStatus; Microsoft Defender Antivirus compatibility with other security products | |
| `security.defenderRealTime` | Echtzeitschutz aktiv | bool | `.RealTimeProtectionEnabled` | Get-MpComputerStatus | |
| `security.defenderTamper` | Manipulationsschutz aktiv | bool | `.IsTamperProtected` | Protect security settings with tamper protection | |
| `security.defenderSignatureAgeDays` | Alter der Signaturen | number, Tage | `.AntivirusSignatureAge` | Get-MpComputerStatus | |
| `security.defenderSignaturesOutOfDate` | Defender hält die Signaturen für veraltet | bool | `.DefenderSignaturesOutOfDate` | Get-MpComputerStatus | `absent`, wenn die Eigenschaft fehlt |
| `security.defenderVersion` | Version der Plattform | text | `.AMProductVersion` | Get-MpComputerStatus | |
| `security.defenderExclusionPaths` | ausgeschlossene Pfade | list: `Path` text:free | CIM `MSFT_MpPreference.ExclusionPath` (gemeinsame Abfrage) | Set-MpPreference | `unreadable`/`rights`, wenn ein Eintrag mit „N/A" beginnt (Defender verbirgt die Liste) |
| `security.defenderExclusionProcesses` | Prozessausschlüsse | list: `Path` text:free | `.ExclusionProcess` | Set-MpPreference; Configure exclusions for files opened by processes | `unreadable`/`rights`, wenn ein Eintrag mit „N/A" beginnt |
| `security.defenderExclusionExtensions` | ausgeschlossene Endungen | list: `Extension` text | `.ExclusionExtension` | Set-MpPreference | `unreadable`/`rights`, wenn ein Eintrag mit „N/A" beginnt |
| `security.defenderSharedSignatures` | Pfad gemeinsamer Signaturen | text:path | `.SharedSignaturesPath` | Set-MpPreference | `absent`, wenn leer |
| `security.defenderNetworkProtection` | Netzwerkschutz (0 aus, 1 blockieren, 2 überwachen) | number | `.EnableNetworkProtection` | Set-MpPreference | `absent`, wenn die Eigenschaft fehlt |
| `security.defenderForcePassive` | passive Betriebsart erzwungen | number | Registrierung `HKLM\SOFTWARE\Policies\Microsoft\Windows Advanced Threat Protection`, Wert `ForceDefenderPassiveMode` | Microsoft Defender Antivirus on Windows Server | `absent` ohne den Wert |
| `security.mdeOnboarding` | Anbindung an Defender for Endpoint (1 = angebunden) | number | Registrierung `HKLM\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status`, Wert `OnboardingState` | Onboard Windows devices using Configuration Manager; Troubleshoot Microsoft Defender for Endpoint onboarding issues | `absent` ohne den Wert |
| `security.mdeService` | Zustand des Dienstes `Sense` | text | `Win32_Service` (gemeinsame Abfrage) | Troubleshoot Microsoft Defender for Endpoint onboarding issues | `absent`/`notInstalled` ohne den Dienst |
| `security.filters` | geladene Dateisystem-Filtertreiber | list: `Name` text:protected, `Altitude` text, `Instances` number, `Legacy` bool | P/Invoke `fltlib.dll` `FilterFindFirst`, `FilterFindNext`, `FilterFindClose` mit `FilterAggregateStandardInformation` | FilterFindFirst function; FilterFindNext function; FILTER_AGGREGATE_STANDARD_INFORMATION structure | `unreadable`/`rights` ohne Administratorrechte |
| `security.applockerService` | Zustand des Dienstes `AppIDSvc` | text | `Win32_Service` (gemeinsame Abfrage) | Win32_Service class | `absent`/`notInstalled` ohne den Dienst |
| `security.applockerCollections` | Umfang der AppLocker-Regeln | list: `Collection` text, `Enforcement` number (leer = nicht gesetzt), `Rules` number | Registrierung `HKLM\SOFTWARE\Policies\Microsoft\Windows\SrpV2\<Exe, Msi, Script, Dll, Appx>`: Wert `EnforcementMode`, Zahl der Unterschlüssel. Der Inhalt der Regeln wird nicht gelesen. | **nicht dokumentiert** (Rohwert nach P3: nur Zahlen, keine Regelinhalte) | leere Liste ohne den Schlüssel |

Nicht gelesen: Proxy-Werte, `ComputerID`, `OrgId`, `senseGuid`, Listen des Ordnerzugriffsschutzes, Regelinhalte von AppLocker, das Windows-Sicherheitscenter (auf Servern nicht unterstützt), Prozesse und installierte Programme: ein Produkt der Rollenliste ohne Dienst und ohne Filtertreiber (etwa die Fachanwendung) erkennt das Zustandsbild nicht.

Fakten der Auswertung: Schutzprodukte aus `src/roles.json` (Rolle `Sicherheit`) gegen `security.services` und `security.filters`. `roles.json` erhält je Eintrag die optionale Liste `filters` (Namensmuster wie `processes`): „Microsoft Defender" `WdFilter`; „Arctic Wolf Aurora Endpoint Protection" `CyProtectDrv*`, `CyOptics`. Andere Einträge bekommen keine Filter: gezählt werden nur Einträge der Rolle `Sicherheit`.

| Abgeleiteter Fakt | Typ | Regel |
|---|---|---|
| `security.products` | text | Bezeichnungen der Einträge der Rolle `Sicherheit` mit einem laufenden Dienst oder einem geladenen Filter, in der Reihenfolge der Rollenliste, mit „, " verbunden; `absent`, wenn keiner |
| `security.otherFilterProducts` | number | Einträge der Rolle `Sicherheit` mit einem geladenen Filter aus ihrer Liste `filters`, ohne den Eintrag, dessen Liste `WdFilter` nennt |
| `security.mdeOnboarded` | bool | `security.mdeOnboarding` gelesen und = 1; sonst nein (auch wenn der Wert fehlt) |
| `security.citrixExclusionsMissing` | number | Zahl der Namen aus `$script:WorkerPerfHealthCitrixProcesses` (`UserProfileManager.exe`, `BrokerAgent.exe`, `CtxSvcHost.exe`), die in keinem Eintrag von `security.defenderExclusionProcesses` als Dateiname vorkommen; `absent`/`notInstalled`, wenn `vda.version` es ist; `unreadable`, wenn die Ausschlüsse es sind |
| `security.wemExclusionsMissing` | number | 0, wenn ein Eintrag von `security.defenderExclusionPaths` den Ordner `Workspace Environment Management Agent` nennt; sonst die Zahl der Namen aus `$script:WorkerPerfHealthWemProcesses` (`Citrix.Wem.Agent.Service.exe`, `VUEMUIAgent.exe`, `AgentCacheUtility.exe`), die in keinem Eintrag von `security.defenderExclusionProcesses` als Dateiname vorkommen. Davor gilt: `absent`/`notInstalled`, wenn `vda.wemService` es ist; sonst `unreadable`, wenn eine der zwei Ausschlusslisten es ist; eine Liste, die nicht vorhanden ist, zählt als leer |

| Prüfung | Fakten | Regel | Art | Bezug |
|---|---|---|---|---|
| `security.twoScanners` | `security.defenderMode`, `security.defenderRealTime`, `security.otherFilterProducts` | prüfen: `defenderMode` = `Normal` und `defenderRealTime` = ja und `otherFilterProducts` > 0 | vendor (Microsoft: Microsoft Defender Antivirus compatibility with other security products) | cpu, disk, hang, pattern.securitymodule |
| `security.passiveWithoutMde` | `security.defenderMode`, `security.mdeOnboarded` | prüfen: `defenderMode` = `Passive` und `mdeOnboarded` = nein | vendor (Microsoft: Microsoft Defender Antivirus compatibility with other security products) | system |
| `security.signatureAge` | `security.defenderMode`, `security.defenderSignatureAgeDays` | prüfen: `defenderMode` = `Normal` und `defenderSignatureAgeDays` > `@signatureAgeDays` | rule | system |
| `security.citrixExclusions` | `security.defenderMode`, `security.citrixExclusionsMissing` | prüfen: `defenderMode` = `Normal` und `citrixExclusionsMissing` > 0 | vendor (Citrix: Endpoint Security, Antivirus, and Antimalware Best Practices) | cpu, profile, hang |
| `security.wemExclusions` | `security.defenderMode`, `security.wemExclusionsMissing` | prüfen: `defenderMode` = `Normal` und `wemExclusionsMissing` > 0 | practice (Stalhood: Workspace Environment Management (WEM) 2411) | cpu, disk, delay.many |
| `security.networkProtection` | `security.defenderMode`, `security.defenderNetworkProtection` | prüfen: `defenderMode` = `Normal` und `defenderNetworkProtection` = 1; der Text nennt den Vorbehalt (eine Schutzfunktion, die Entscheidung liegt beim Sicherheitsteam) | practice (Stalhood: Citrix Virtual Delivery Agent (VDA) 2411; der dort genannte Citrix-Artikel ließ sich nicht öffnen) | hang, system |

Nicht aufgenommen: Ausschlüsse für Auslagerungsdatei und Ereignisprotokolle (das zugrunde liegende Citrix-Dokument ließ sich nicht öffnen, und ein Abgleich von Pfaden mit freiem Servertext gehört nicht in die erste Fassung), Treiber der NSX Guest Introspection (nur eine Ableitung der Quelle).

### Netz und Dateiserver (`network`)

| Kennung | Was | Typ, Einheit | Lesequelle | Dokument | Zustände |
|---|---|---|---|---|---|
| `network.domainMember` | Mitglied einer Domäne | bool | `Win32_ComputerSystem.PartOfDomain` (das beim Initialisieren gelesene Objekt) | Win32_ComputerSystem class | |
| `network.smbRequireSigning` | Client verlangt Signierung | bool | CIM `root\Microsoft\Windows\SMB` `MSFT_SmbClientConfiguration.RequireSecuritySignature` | Get-SmbClientConfiguration; Overview of Server Message Block signing in Windows | |
| `network.smbDirectoryCache` | Größe des Verzeichniscaches | number | `.DirectoryCacheEntriesMax` | Get-SmbClientConfiguration | |
| `network.smbFileInfoCache` | Größe des Dateiinfo-Caches | number | `.FileInfoCacheEntriesMax` | Get-SmbClientConfiguration | |
| `network.smbFileNotFoundCache` | Größe des Caches „Datei nicht gefunden" | number | `.FileNotFoundCacheEntriesMax` | Get-SmbClientConfiguration | |
| `network.smb1` | Starttyp des SMBv1-Clients | text | `Win32_SystemDriver` mit `Name = 'mrxsmb10'`: `StartMode` | Detect, enable, and disable SMBv1, SMBv2, and SMBv3 in Windows; Win32_SystemDriver class | `absent` ohne den Treiber (der Normalfall) |
| `network.smbConnections` | bestehende SMB-Verbindungen, zusammengefasst | list: `Share` text:share, `Dialect` text, `Signed` bool, `Encrypted` bool, `Connections` number | CIM `root\Microsoft\Windows\SMB` `MSFT_SmbConnection`: `ServerName`, `ShareName`, `Dialect`, `Signed`, `Encrypted`; je `\\Server\Freigabe` und Dialekt eine Zeile mit der Zahl der Verbindungen. Konten werden nicht gespeichert. | Get-SmbConnection (die Eigenschaft `Signed` zeigt die geöffnete Seite nicht; fehlt sie, bleibt das Feld leer) | leere Liste ohne Verbindung |
| `network.dnsServers` | DNS-Server je Schnittstelle | list: `Interface` number, `Address` text:address | `Win32_NetworkAdapterConfiguration` mit `IPEnabled = TRUE`: `Index`, `DNSServerSearchOrder` | Win32_NetworkAdapterConfiguration class | leere Liste ohne Eintrag |
| `network.rss` | Receive Side Scaling je Adapter | list: `Description` text, `Enabled` bool | CIM `root\StandardCimv2` `MSFT_NetAdapterRssSettingData`: `InterfaceDescription`, `Enabled`. Der Verbindungsname des Adapters wird nicht gespeichert. | Get-NetAdapterRss; MSFT_NetAdapterRssSettingData class | leere Liste ohne Adapter mit RSS |
| `network.timeType` | Art der Zeitsynchronisation (`NT5DS`, `NTP`, `NoSync`, `AllSync`) | text | Registrierung `HKLM\SOFTWARE\Policies\Microsoft\W32Time\Parameters`, Wert `Type`; fehlt er: `HKLM\SYSTEM\CurrentControlSet\Services\W32Time\Parameters`, Wert `Type` | Windows Time Service Tools and Settings | `absent` ohne den Wert |
| `network.timeServers` | Zeitquellen | text:hosts | Wert `NtpServer` desselben Schlüssels, ohne die Merker hinter dem Komma | Windows Time Service Tools and Settings | `absent` ohne den Wert |
| `network.timeService` | Zustand des Dienstes `W32Time` | text | `Win32_Service` (gemeinsame Abfrage) | Win32_Service class | `absent`/`notInstalled` ohne den Dienst |

Nicht gelesen: `w32tm /query`, verbundene Laufwerke, IP-Adressen des Workers, Proxy-Einstellungen, Namensauflösung.

| Abgeleiteter Fakt | Typ | Regel |
|---|---|---|
| `network.smbOldDialects` | number | Summe von `Connections` der Zeilen, deren `Dialect` mit einer Zahl kleiner 3 beginnt |
| `network.dnsServersMin` | number | kleinste Zahl von DNS-Servern einer Schnittstelle mit mindestens einem; `absent` ohne eine solche |
| `network.dnsPublic` | number | Adressen außerhalb der privaten Bereiche (IPv4 nicht 10/8, 172.16/12, 192.168/16, 169.254/16, 127/8; IPv6 nicht fc00::/7, fe80::/10, ::1) |
| `network.timeFromDomain` | bool | `network.timeType` ist `NT5DS` oder `AllSync` |
| `network.rssOff` | number | Einträge von `network.rss`, deren `Description` „vmxnet3" enthält und deren `Enabled` falsch ist; `absent`/`notInstalled`, wenn `size.vmware` nein ist |

| Prüfung | Fakten | Regel | Art | Bezug |
|---|---|---|---|---|
| `network.smb1` | `network.smb1` | prüfen: vorhanden und ≠ `Disabled` | vendor (Microsoft: Detect, enable, and disable SMBv1, SMBv2, and SMBv3 in Windows) | share |
| `network.smbOldDialect` | `network.smbOldDialects` | prüfen: > 0; handeln: > 0 und Ereignis `system.fileserver` mindestens 1 in 7 Tagen | rule | share, profile, profileerror |
| `network.dnsCount` | `network.dnsServersMin` | prüfen: vorhanden und < 2 | vendor (Microsoft: Best practices for DNS client settings in Windows Server) | profileerror, share |
| `network.dnsPublic` | `network.dnsPublic` | prüfen: > 0 | rule | profileerror |
| `network.timeSource` | `network.domainMember`, `network.timeFromDomain` | prüfen: `domainMember` = ja und `timeFromDomain` = nein | rule | system, profileerror |
| `network.rss` | `network.rssOff` | prüfen: > 0. Widerspruch, den `meaning` nennt: BIS-F schaltet RSS beim Versiegeln global ab (so sein Code und seine Seite „System Optimizations"; seine Versionshinweise nennen das Gegenteil); es gilt die Linie von VMware (Q3) | vendor (VMware: Poor network performance or high network latency on Windows virtual machines) | share, profile, delay.many |

Nicht aufgenommen: die Netzwerkeinstellungen von BIS-F (TCP-Offload, UDP FastSend, Endpunktfaktor, ARP-Zeit: die Herstellerdokumente dazu ließen sich nicht öffnen, die Schritte laufen in BIS-F nur unter Bedingungen), der periodische Zeitabgleich der VMware Tools (nur über ein Programm lesbar), die NTP-Werte von VMware (gelten nicht für Domänenmitglieder mit `NT5DS`), Zeitsprünge im Systemprotokoll (Anbieter und Kennung nicht belegt).

### Ereignisbild (`events`)

| Kennung | Was | Typ, Einheit | Lesequelle | Dokument | Zustände |
|---|---|---|---|---|---|
| `events.logs` | die Protokolle, die der Ereigniskatalog liest (`Get-WorkerPerfEventReadLogs`: sieben Protokolle mit acht Namen), je Name | list: `Log` text, `Present` bool, `Enabled` bool, `MaxSizeMB` number, `FileSizeMB` number, `Records` number, `Mode` text (`Circular`, `AutoBackup`, `Retain`: der Name von `LogMode`, nicht seine Zahl), `Full` bool, `Oldest` time | das Objekt von `Get-WinEvent -ListLog` (beim Initialisieren je Protokoll geholt und aufbewahrt; sonst hier gelesen): `IsEnabled`, `MaximumSizeInBytes`, `FileSize`, `RecordCount`, `LogMode`, `IsLogFull`; `Oldest` = Zeit des ersten Eintrags eines `EventLogReader` in aufsteigender Richtung (die Meldung wird nicht formatiert) | Get-WinEvent (PowerShell 5.1); EventLogConfiguration class; EventLogReader class | ein fehlendes Protokoll hat `Present` = falsch und sonst leere Felder; jeder andere Fehler der Abfrage eines Protokolls macht den Wert `unreadable` |

Fakten der Auswertung aus dem Rückblick (`events_before.csv`, Kategorie `Rueckblick`). Gezählt werden die Ereignisse von `CaptureStartMs` − `EventLookbackDays` Tage bis `CaptureStartMs`. Der Rückblick gilt als gelesen, wenn `Rueckblick` nicht weggelassen ist, `EventLookbackDays` größer 0 ist, die Datei in der Aufzeichnung steht und entweder ein Ereignis gelesen wurde oder `SourceErrors` keinen Eintrag `eventsbefore` oder `eventsbefore.<Protokoll>` hat. Sonst sind `events.crashDays`, `events.storageCount`, `events.fileserverDays` und `events.perDay` `unreadable`: mit `skipped:Rueckblick` (weggelassen oder 0 Tage), `notRecorded` (keine Angabe `EventLookbackDays` oder keine Datei) oder `error` (das Lesen ist gescheitert). Die Art eines Ereignisses bestimmt `Get-WorkerPerfEventIncidentKind` (ein Absturz des Druckdienstes zählt als `print`); `storage` und `fileserver` sind die Art `system` mit dieser Gruppe. Der Tag ist der Ortstag des Servers.

| Abgeleiteter Fakt | Typ | Regel |
|---|---|---|
| `events.lookbackDays` | number, Tage | `EventLookbackDays` aus `meta.json`; 0 ohne die Angabe (immer gelesen) |
| `events.crashDays` | number | Tage des Rückblicks mit mindestens einem Ereignis der Art `crash` |
| `events.storageCount` | number | Ereignisse der Art `system` mit der Gruppe `storage` |
| `events.fileserverDays` | number | Tage mit mindestens einem Ereignis der Art `system` mit der Gruppe `fileserver` |
| `events.perDay` | list: `Day` text, `Crash`, `Hang`, `Service`, `Storage`, `Print`, `Fileserver`, `Profileerror` number | Zählung je Tag und Art, Tage aufsteigend, nur Tage mit einem Ereignis |
| `events.coverageGapDays` | number, Tage | max(0, `events.lookbackDays` − ganze Tage zwischen dem jüngsten `Oldest` der vorhandenen, eingeschalteten Protokolle mit Rückblick und `ReadAt`); 0, wenn kein solches Protokoll einen Eintrag hat |
| `events.retainLogs` | number | Protokolle mit `Mode` = `Retain` |
| `events.fullLogs` | number | davon mit `Full` = wahr |
| `events.disabledLogs` | number | Protokolle mit `Present` = wahr und `Enabled` = falsch |
| `events.reachFrom` | time | das jüngste `Oldest` der vorhandenen, eingeschalteten Protokolle mit einem Eintrag: ab hier reichen alle gelesenen Protokolle; `absent`, wenn keines einen Eintrag hat |
| `events.sinceBootOnly` | bool | ja, wenn kein vorhandenes, eingeschaltetes Protokoll einen Eintrag hat, der mehr als zehn Minuten vor `operation.lastBoot` liegt, und mindestens eines einen Eintrag hat; sonst nein; `unreadable`, wenn `events.logs` oder `operation.lastBoot` es ist |

| Prüfung | Fakten | Regel | Art | Bezug |
|---|---|---|---|---|
| `events.crashes` | `events.crashDays`, `operation.lastBoot` | prüfen: `crashDays` ≥ `@eventDays`; der Befund nennt den letzten Start als Grenze (K3) | rule | crash |
| `events.storage` | `events.storageCount`, `operation.lastBoot` | prüfen: `storageCount` ≥ 1; der Befund nennt den letzten Start als Grenze (K3) | rule | disk, system |
| `events.fileserver` | `events.fileserverDays`, `operation.lastBoot` | prüfen: `fileserverDays` ≥ `@eventDays`; der Befund nennt den letzten Start als Grenze (K3) | rule | share, profile |
| `events.sinceBoot` | `events.sinceBootOnly`, `operation.lastBoot`, `events.lookbackDays` | prüfen: `sinceBootOnly` = ja; nie „handeln" (L1). `meaning` sagt, dass BIS-F die Protokolle nur verlegt, wenn für MCS ein MCSIO-Cache-Datenträger eingerichtet ist (VDA ab 1903, Richtlinie „Configure Citrix MCS Device"), und kennzeichnet „überstehen so einen Neustart" als Folgerung des Katalogs; `todo` nennt die BIS-F-Richtlinie bzw. das Master-Image als Ort und eine zentrale Sammlung der Protokolle als Alternative ohne Beleg einer Quelle | practice (BIS-F: `BISF.psm1`, Funktionen `Use-MCSConfig` und `Move-EvtLogs`; Hilfetext `POL_MCSCfg_Help` der Richtlinienvorlage `BaseImageScriptFramework.adml`) | system |
| `events.coverage` | `events.coverageGapDays`, `events.sinceBootOnly`, `operation.lastBoot` | prüfen: `coverageGapDays` > 0 und `sinceBootOnly` = nein (eine Lücke, die nicht schon der letzte Start erklärt) | rule | system |
| `events.retainFull` | `events.retainLogs`, `events.fullLogs` | prüfen: `retainLogs` > 0; handeln: `fullLogs` > 0 (harte Grenze) | rule | system |
| `events.logDisabled` | `events.disabledLogs` | prüfen: > 0 | rule | print, share, profileerror |

### Wartung in der Arbeitszeit (`maintenance`)

| Kennung | Was | Typ, Einheit | Lesequelle | Dokument | Zustände |
|---|---|---|---|---|---|
| `maintenance.tasks` | geplante Aufgaben außerhalb des Ordners `\Microsoft\` | list: `Path` text:free, `Enabled` bool, `State` text, `NextRun` time, `LastRun` time, `Triggers` text (Wörter `event`, `time`, `daily`, `weekly`, `monthly`, `idle`, `registration`, `boot`, `logon`, `session`, `other`, mit „, " verbunden), `RepeatMinutes` number (0 = keine Wiederholung), `Action` text:free | lokales Objekt `Schedule.Service` (`Connect()` ohne Servernamen, `GetFolder`, `GetFolders`, `GetTasks(1)`): `Path`, `Enabled`, `State`, `NextRunTime`, `LastRunTime`, `Definition.Triggers` (`Type`, `Repetition.Interval`), `Definition.Actions` (Pfad des ersten Programms). Nicht gespeichert: Argumente, Autor, Konten. | TaskService.Connect; ITaskFolder::GetTasks; Trigger Types; TASK_TRIGGER_TYPE2 enumeration | |
| `maintenance.taskCount` | Zahl aller Aufgaben (mit `\Microsoft\`) | number | dieselbe Aufzählung | TaskService.Connect; ITaskFolder::GetTasks | |
| `maintenance.scanDay` | Tag des geplanten Defender-Scans (0 täglich, 1–7 Sonntag bis Samstag, 8 nie) | number | `MSFT_MpPreference.ScanScheduleDay` (gemeinsame Abfrage) | Set-MpPreference | `absent`/`notInstalled` ohne Defender |
| `maintenance.scanTime` | Startzeit des geplanten Scans | text (`HH:mm`) | `.ScanScheduleTime` (`TimeSpan` oder `DateTime`, je nach Fassung der Plattform; gespeichert als `HH:mm`) | Set-MpPreference | `absent`/`notInstalled` ohne Defender |
| `maintenance.quickScanTime` | Startzeit des täglichen Schnellscans | text (`HH:mm`) | `.ScanScheduleQuickScanTime` | Set-MpPreference | `absent`/`notInstalled` ohne Defender |
| `maintenance.scanType` | Art des geplanten Scans (1 schnell, 2 vollständig) | number | `.ScanParameters` | Set-MpPreference | `absent`/`notInstalled` ohne Defender |
| `maintenance.scanRandomize` | zufälliger Startzeitpunkt | bool | `.RandomizeScheduleTaskTimes` | Set-MpPreference | `absent`/`notInstalled` ohne Defender |
| `maintenance.scanCpuLoad` | Ziel-CPU-Anteil eines Scans | number, % | `.ScanAvgCPULoadFactor` | Set-MpPreference | `absent`/`notInstalled` ohne Defender |
| `maintenance.updateOptions` | Richtlinie automatische Updates (`AUOptions`) | number | Registrierung `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU`, Wert `AUOptions` | Manage additional Windows Update settings | `absent` ohne Richtlinie |
| `maintenance.updateDay` | Installationstag (0 täglich, 1–7 Sonntag bis Samstag) | number | Wert `ScheduledInstallDay` | Manage additional Windows Update settings | `absent` ohne Richtlinie |
| `maintenance.updateHour` | Installationsstunde | number | Wert `ScheduledInstallTime` | Manage additional Windows Update settings | `absent` ohne Richtlinie |
| `maintenance.updateNoRebootWithUsers` | kein Neustart bei angemeldeten Benutzern | number | Wert `NoAutoRebootWithLoggedOnUsers` | Manage device restarts after updates | `absent` ohne Richtlinie |
| `maintenance.searchService` | Zustand des Suchdienstes `WSearch` | text | `Win32_Service` (gemeinsame Abfrage) | Win32_Service class | `absent`/`notInstalled` ohne den Dienst |
| `maintenance.updateService` | Startart des Dienstes Windows Update (`wuauserv`) | text | `Win32_Service.StartMode` (gemeinsame Abfrage) | Win32_Service class; Manage additional Windows Update settings | `absent`/`notInstalled` ohne den Dienst |

Die Arbeitszeit ist Montag bis Freitag von `@workStartHour` bis `@workEndHour` Uhr (Ortszeit des Servers, Offset aus `ReadAt`).

| Abgeleiteter Fakt | Typ | Regel |
|---|---|---|
| `maintenance.tasksInWorkHours` | number | eingeschaltete Aufgaben, deren `NextRun` in der Arbeitszeit liegt oder deren `RepeatMinutes` > 0 ist |
| `maintenance.sessionTriggerTasks` | number | eingeschaltete Aufgaben, deren `Triggers` `idle`, `logon` oder `session` nennt |
| `maintenance.scanInWorkHours` | bool | `scanDay` ist 0 oder 2–6 und `scanTime` liegt in der Arbeitszeit; nein bei `scanDay` = 8; ohne Defender `absent`/`notInstalled` |
| `maintenance.updateInWorkHours` | bool | `updateOptions` = 4 und `updateDay` ist 0 oder 2–6 und `updateHour` liegt in der Arbeitszeit; nein, wenn die Richtlinie fehlt |

| Prüfung | Fakten | Regel | Art | Bezug |
|---|---|---|---|---|
| `maintenance.tasksInWorkHours` | `maintenance.tasksInWorkHours` | prüfen: > 0 | rule | cpu, disk |
| `maintenance.sessionTriggerTasks` | `maintenance.sessionTriggerTasks` | prüfen: > 0 | vendor (Microsoft: Performance Tuning Remote Desktop Session Hosts) | delay.single, profile |
| `maintenance.defenderScanInWorkHours` | `maintenance.scanInWorkHours` | prüfen: = ja | rule | cpu, disk |
| `maintenance.defenderFullScan` | `maintenance.scanDay`, `maintenance.scanType` | prüfen: `scanDay` ≠ 8 und `scanType` = 2 | vendor (Microsoft: Configure Microsoft Defender Antivirus on a remote desktop or virtual desktop infrastructure environment) | cpu, disk |
| `maintenance.defenderRandomize` | `size.hypervisor`, `maintenance.scanRandomize` | prüfen: `hypervisor` = ja und `scanRandomize` = nein | vendor (Microsoft: Set-MpPreference) | cpu, disk |
| `maintenance.updateInstallInWorkHours` | `maintenance.updateInWorkHours` | prüfen: = ja | rule | system, hang |
| `maintenance.updateServiceEnabled` | `maintenance.updateService` | prüfen: ≠ `Disabled` (Begründung des Katalogs, nicht der Quelle: auf einem nicht persistenten Worker kommen Updates über das Master-Image, Entwurf 4.4; BIS-F nennt keinen Zweck) | practice (BIS-F: System Optimizations: „Set Windows Update Service to Disabled") | cpu, disk, system |

Nicht aufgenommen: die Aufgabe `sihclient` (in BIS-F nur als Titel einer Änderung belegt), Citrix Optimizer und .NET-Vorkompilierung (Schritte des Versiegelns, am laufenden Worker nicht lesbar), der Suchdienst für die Outlook-Suche (hängt an Werten der Profilverwaltung, deren Lage nicht dokumentiert ist).

### Anwendungen (`apps`)

Der Bereich hat in `health.json` einen einzigen Wert; was er liest, steht nicht in der Werteliste, sondern in `src/apps.json` (Entwurf 3.2a).

| Kennung | Was | Typ, Einheit | Lesequelle | Dokument | Zustände |
|---|---|---|---|---|---|
| `apps.probes` | je Anwendung der Anwendungsliste, die `installed` nennt, eine Zeile für die Installation und eine Zeile je Probe | list: `App` text (Kennung der Anwendung), `Id` text (Kennung der Probe; `installed` für die Installation), `Kind` text, `Read` text, `State` text (`read`, `absent`, `unreadable`), `Reason` text, `Value` value, `Names` text:free (der Wert einer Probe mit `names: true`; `Value` ist dann leer) | die Proben aus `src/apps.json` über die fünf Lesearten der Tabelle unten | je Probe das Dokument der Tabellen unten | leere Liste ohne Anwendung mit `installed` |

**Lesearten.** Jede Probe liefert genau einen Fakt; `read` wählt die Angabe (die erste ist die Vorgabe).

| `kind` | Pflichtfelder | `read` und Typ des Fakts | „nicht vorhanden" (`absent` ohne Grund) | Windows-Aufruf |
|---|---|---|---|---|
| `registryValue` | `path` (beginnt mit `HKLM\`), `name`, `names` (ja/nein) | der Wert: `value` (Zahl bei `REG_DWORD`/`REG_QWORD`, sonst Text; mehrere Zeichenketten mit „; " verbunden; Binärwert als „binaer, n Byte"); mit `names: true` `text:free` | Schlüssel oder Wert fehlt („nicht gesetzt") | `Get-WorkerPerfRegistryValues` |
| `registryKey` | `path` (beginnt mit `HKLM\`) | `exists` (bool), `valueCount`, `subKeyCount` (number) | bei den Zählungen: Schlüssel fehlt | `Get-WorkerPerfRegistryValues` |
| `service` | genau eines von `name` (Dienstname) und `displayName` (Anzeigename) | `state` (text), `startMode` (text) | Dienst fehlt | gemeinsame Abfrage `Win32_Service` |
| `scheduledTask` | `path` (beginnt mit `\`) | `enabled` (bool), `exists` (bool), `lastRun`, `nextRun` (time) | außer bei `exists`: Aufgabe fehlt | `Get-WorkerPerfTaskInfo` (`Schedule.Service`, `GetFolder`, `GetTask`) |
| `file` | `path` (lokaler Pfad `X:\…`; in genau einem Ordnernamen darf ein `*` stehen) | `version` (text), `exists` (bool; gilt auch für einen Ordner) | bei `version`: Datei fehlt | `Get-WorkerPerfFileProbe` |

`installed` ist eine Probe ohne `id`, `read`, `names` und `label`: installiert heißt, der Wert, der Schlüssel, der Dienst, die Aufgabe oder die Datei ist vorhanden. Wahlfrei je Probe: `label` (Bezeichnung für die Rohwertanzeige; Vorgabe ist `id`) und `documented` (Vorgabe ja; `false` kennzeichnet eine Lesequelle ohne Herstellerdokument). Andere Felder und andere Lesearten lehnt `Read-WorkerPerfHealthApps` ab.

**Fakten.** Je Anwendung mit `installed`: `apps.<key>.installed` (bool) und je Probe `apps.<key>.<id>` mit dem Typ aus der Tabelle. Ist die Anwendung nicht installiert, sind ihre Proben `absent`/`notInstalled` und werden nicht gelesen; lässt sich die Installation nicht lesen, sind sie `unreadable` mit demselben Grund. Abgeleitete Fakten gibt es in diesem Bereich nicht.

**Proben der ausgelieferten Anwendungsliste** (Task 2 schreibt sie in `src/apps.json`; nur maschinenweite Orte, nichts je Benutzer; die zwei weiteren Anwendungen der Datei, `webview2` und `printaurus`, bleiben ohne `installed` und ohne Proben). Spalte „Stütze": die Kennung des Fakts in der Recherche und ihr Prüfergebnis dort.

`edge` – „Microsoft Edge", `installed`: `file` `C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`

| `id` | Was | Leseart, Ort, `read` | `names` | Dokument | Stütze |
|---|---|---|---|---|---|
| `version` | Version von Edge | `file`, derselbe Pfad, `version` | – | Microsoft Edge stops responding or doesn't start | EDGE-F01 supported |
| `webview2Version` | Version der WebView2-Runtime | `registryValue` `HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}`, `pv` | nein | Distribute your app and the WebView2 Runtime | EDGE-F03 supported |
| `updateDefault` | Update-Vorgabe für alle Kanäle (0 = aus) | `registryValue` `HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate`, `UpdateDefault` | nein | Microsoft Edge - Update policies | EDGE-F28 supported |
| `updateStable` | Update-Vorgabe für Edge selbst (0 = aus) | derselbe Schlüssel, `Update{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}` | nein | Microsoft Edge - Update policies | EDGE-F29 supported |
| `updateWebView2` | Update-Vorgabe für die WebView2-Runtime (0 = aus) | derselbe Schlüssel, `Update{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}` | nein | Microsoft Edge - Update policies | EDGE-F30 supported |
| `updateCheckMinutes` | Prüfabstand des Updaters in Minuten | derselbe Schlüssel, `AutoUpdateCheckPeriodMinutes` | nein | Microsoft Edge - Update policies | EDGE-F31 supported |
| `startupBoost` | Startup boost | `registryValue` `HKLM\SOFTWARE\Policies\Microsoft\Edge`, `StartupBoostEnabled` | nein | StartupBoostEnabled (Microsoft Edge - Policies) | EDGE-F06 supported |
| `backgroundMode` | Hintergrundmodus | derselbe Schlüssel, `BackgroundModeEnabled` | nein | BackgroundModeEnabled | EDGE-F07 supported |
| `sleepingTabs` | schlafende Tabs | derselbe Schlüssel, `SleepingTabsEnabled` | nein | SleepingTabsEnabled | EDGE-F08 supported |
| `autoDiscard` | Verwerfen schlafender Tabs | derselbe Schlüssel, `AutoDiscardSleepingTabsEnabled` | nein | AutoDiscardSleepingTabsEnabled | EDGE-F10 supported |
| `roamingProfile` | On-Premises-Sync | derselbe Schlüssel, `RoamingProfileSupportEnabled` | nein | RoamingProfileSupportEnabled | EDGE-F18 supported |
| `userDataDir` | Ordner der Benutzerdaten | derselbe Schlüssel, `UserDataDir` | ja | UserDataDir | EDGE-F17 supported |
| `diskCacheDir` | Ordner des Datenträgercaches | derselbe Schlüssel, `DiskCacheDir` | ja | DiskCacheDir | EDGE-F16 supported |
| `forcedExtensions` | Zahl der zwangsinstallierten Erweiterungen | `registryKey` `HKLM\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist`, `valueCount` | – | ExtensionInstallForcelist | EDGE-F27 supported (nur die Zahl; die Einträge können Adressen tragen) |
| `updateService` | Startart des Update-Dienstes | `service` `name` `edgeupdate`, `startMode` | – | **nicht dokumentiert** für Windows Server (der Name steht nur auf einer Seite für Windows IoT Enterprise); `documented: false` | EDGE-F36 partly |

`office` – „Microsoft Office", `installed`: `registryKey` `HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration`

| `id` | Was | Leseart, Ort, `read` | `names` | Dokument | Stütze |
|---|---|---|---|---|---|
| `updateChannel` | wirksamer Updatekanal (Adresse des Kanals) | `registryValue`, derselbe Schlüssel, `UpdateChannel` | nein | Set the Microsoft 365 apps update channel using the settings catalog in Microsoft Intune | F-OFC-02 supported |
| `updateUrl` | Updatequelle aus der Installation | derselbe Schlüssel, `UpdateUrl` | ja | Change the Microsoft 365 Apps update channel for devices in your organization | F-OFC-04 supported |
| `policyUpdatePath` | Updatequelle aus der Richtlinie | `registryValue` `HKLM\SOFTWARE\Policies\Microsoft\office\16.0\Common\officeupdate`, `UpdatePath` | ja | Change the Microsoft 365 Apps update channel for devices in your organization | F-OFC-13 supported |
| `policyUpdateBranch` | Updatekanal aus der Richtlinie | derselbe Schlüssel, `UpdateBranch` | nein | Change the Microsoft 365 Apps update channel for devices in your organization | F-OFC-13 supported |
| `hideUpdateNotifications` | Update-Hinweise ausgeblendet | derselbe Schlüssel, `hideupdatenotifications` | nein | Install Office on a custom VHD image (Azure Virtual Desktop) | F-OFC-13 supported |
| `hideEnableDisableUpdates` | Schalter für Updates ausgeblendet | derselbe Schlüssel, `hideenabledisableupdates` | nein | Install Office on a custom VHD image (Azure Virtual Desktop) | F-OFC-13 supported |
| `updateTask` | Aufgabe für automatische Updates eingeschaltet | `scheduledTask` `\Microsoft\Office\Office Automatic Updates 2.0`, `enabled` | – | Update Office LTSC 2024 | F-OFC-17 supported |
| `perUserCatalog` | Suchkatalog je Benutzer (Windows Search) | `registryValue` `HKLM\SOFTWARE\Microsoft\Windows Search`, `EnablePerUserCatalog` | nein | Enable native Outlook search experience (Citrix Profile Management) | F-OFC-30 supported |
| `outlookAddins` | maschinenweit eingetragene Outlook-Add-ins | `registryKey` `HKLM\SOFTWARE\Microsoft\Office\Outlook\Addins`, `subKeyCount` | – | Registry entries for VSTO Add-ins | F-OFC-21 supported |
| `outlookAddinsWow` | dasselbe in der 32-Bit-Sicht | `registryKey` `HKLM\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins`, `subKeyCount` | – | Registry entries for VSTO Add-ins | F-OFC-21 supported |
| `version` | Stand von Office | `registryValue` `HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration`, `VersionToReport` | nein | **nicht dokumentiert** (der Name steht nur als Eigenschaft einer Inventarklasse); `documented: false` | F-OFC-05 partly |
| `platform` | 32 oder 64 Bit | derselbe Schlüssel, `Platform` | nein | **nicht dokumentiert**; `documented: false` | F-OFC-07 partly |
| `updatesEnabled` | automatische Updates laut Installation | derselbe Schlüssel, `UpdatesEnabled` | nein | **nicht dokumentiert**; `documented: false` | F-OFC-08 partly |

`teams` – „Microsoft Teams", `installed`: `file` `C:\Program Files\WindowsApps\MSTeams_*_x64__8wekyb3d8bbwe\ms-teams.exe` (Microsoft dokumentiert den Ordner als `MSTeams_[version]_[arch]__8wekyb3d8bbwe`; das `*` steht für die Version)

| `id` | Was | Leseart, Ort, `read` | `names` | Dokument | Stütze |
|---|---|---|---|---|---|
| `version` | Version des neuen Teams | `file`, derselbe Pfad, `version` (bei mehreren Ordnern die höchste) | – | Install Teams for Virtualized Desktop Infrastructure (VDI); Include or exclude Teams from antivirus or DLP applications | TEAMS-F03 supported |
| `disableAutoUpdate` | automatische Aktualisierung abgeschaltet | `registryValue` `HKLM\SOFTWARE\Microsoft\Teams`, `disableAutoUpdate` | nein | Install Teams for Virtualized Desktop Infrastructure (VDI) | TEAMS-F04 supported |
| `disableFallback` | Rückfallmodus (0 oder nicht gesetzt = an, 1 = aus, 2 = nur Audio) | derselbe Schlüssel, `DisableFallback` | nein | Install Teams for Virtualized Desktop Infrastructure (VDI) | TEAMS-F05 supported |
| `maxFps` | Bildrate der Bildschirmfreigabe vom Worker | `registryValue` `HKLM\SOFTWARE\Microsoft\Teams\VMSS`, `MaxFPS` | nein | New VDI solution for Teams | TEAMS-F06 supported |
| `meetingAddin` | Besprechungs-Add-in maschinenweit vorhanden | `file` `C:\Program Files (x86)\Microsoft\TeamsMeetingAdd-in`, `exists` | – | Install Teams for Virtualized Desktop Infrastructure (VDI) | TEAMS-F12 supported |
| `classicTeams` | klassisches Teams noch vorhanden | `file` `C:\Program Files (x86)\Microsoft\Teams\current\Teams.exe`, `exists` | – | Optimization for Microsoft Teams (Citrix, klassisches Teams) | TEAMS-F13 supported |
| `webview2Version` | Version der WebView2-Runtime | wie `edge`, `webview2Version` | nein | Distribute your app and the WebView2 Runtime | EDGE-F03 supported |

Nicht gelesen: alles je Benutzer (`HKCU`, geladene Benutzerzweige, Dateien im Profil: Cached Mode von Outlook, Add-ins je Benutzer, Autostart und Verbindungsstand von Teams, Benutzerrichtlinien von Edge); Aufgaben des Edge-Updaters (ihre Namen stehen in keinem Herstellerdokument); der Click-to-Run-Dienst (Name nicht dokumentiert); der Aktivierungsstand von Office (nur über ein Programm lesbar); `Get-AppxPackage` (Cmdlet eines Fachmoduls).

| Prüfung | Fakten | Regel | Art | Bezug |
|---|---|---|---|---|
| `apps.edgeAutoUpdate` | `apps.edge.updateStable`, `apps.edge.updateDefault` | prüfen: `updateStable` ≠ 0 und `updateDefault` ≠ 0 (keine der beiden Richtlinien schaltet die Updates ab; „nicht gesetzt" zählt als ungleich 0). Der seltene Fall „allgemein aus, für Edge ausdrücklich an" bleibt in Ordnung; die Rohwerte zeigen ihn. | vendor (Microsoft: Microsoft Edge for Virtual desktop infrastructure (VDI); Stalhood nennt dasselbe) | cpu, disk, system |
| `apps.edgeUpdateCheckOff` | `apps.edge.updateCheckMinutes` | prüfen: = 0 | vendor (Microsoft: Microsoft Edge - Update policies) | service, system |
| `apps.edgeWebView2Update` | `apps.edge.updateWebView2` | prüfen: = 0; der Text nennt, dass dann das Abbild die aktuelle Runtime tragen muss | vendor (Microsoft: Microsoft Edge - Update policies) | crash, hang |
| `apps.edgeStartupBoost` | `apps.edge.startupBoost` | prüfen: ≠ 0 (eingeschaltet oder nicht gesetzt) | rule (Microsoft beschreibt nur das Verhalten: StartupBoostEnabled) | memory |
| `apps.edgeBackgroundMode` | `apps.edge.backgroundMode` | prüfen: = 1 | vendor (Microsoft: Fix high CPU or memory usage in Microsoft Edge) | cpu |
| `apps.edgeSleepingTabs` | `apps.edge.sleepingTabs` | prüfen: = 0 | vendor (Microsoft: Fix high CPU or memory usage in Microsoft Edge; SleepingTabsEnabled) | cpu, memory |
| `apps.edgeAutoDiscard` | `apps.edge.autoDiscard` | prüfen: = 0 | vendor (Microsoft: AutoDiscardSleepingTabsEnabled) | memory |
| `apps.edgeRoamingProfile` | `apps.edge.roamingProfile` | prüfen: = 1 | vendor (Microsoft: On-premises sync for Active Directory (AD) users) | profile, profileerror, hang |
| `apps.edgeUserDataDir` | `apps.edge.userDataDir` | prüfen: vorhanden (der Ordner der Benutzerdaten ist per Richtlinie verlegt; der Befund nennt den Pfad nicht und lässt nachsehen, wohin er zeigt: liegt er auf einer Freigabe, gilt das nach Microsoft als nicht unterstützt; ein lokaler Pfad ist es nicht) | rule (Beleg im Text: Microsoft Edge for Virtual desktop infrastructure (VDI); ob der Pfad lokal ist, kann die Regel nicht unterscheiden, weil der Wert freier Servertext ist) | profile, profileerror, share |
| `apps.officeUpdateUi` | `apps.office.hideEnableDisableUpdates` | prüfen: ≠ 1 | rule (übertragen von Microsofts Vorgabe für Microsoft 365 Apps auf Sitzungshosts: Install Office on a custom VHD image (Azure Virtual Desktop); für Office LTSC gibt es keine eigene Seite) | system |
| `apps.teamsAutoUpdate` | `apps.teams.disableAutoUpdate` | prüfen: ≠ 1 | vendor (Microsoft: Install Teams for Virtualized Desktop Infrastructure (VDI)) | cpu, disk |
| `apps.teamsFallback` | `apps.teams.disableFallback` | prüfen: ≠ 1 und ≠ 2 (ohne Optimierung laufen Audio und Video auf dem Worker); der Text nennt es als Entscheidung des Betreibers | vendor (Microsoft: Install Teams for Virtualized Desktop Infrastructure (VDI)) | cpu |
| `apps.teamsWebView2` | `apps.teams.webview2Version` | prüfen: nicht vorhanden | vendor (Microsoft: Install Teams for Virtualized Desktop Infrastructure (VDI)) | crash, hang |

Nicht aufgenommen: automatische Updates von Office (der Wert der Installation und der Richtlinienname sind nicht dokumentiert; die Aufgabe allein belegt nichts), 64-Bit-Office (Wert nicht dokumentiert), Updatekanal von Office LTSC (die Kennung des Kanals steht in keinem geöffneten Dokument), Größe je Benutzer für Edge (steht als Beleg bei `size.memoryPerSession`), Erweiterungen, Grafikbeschleunigung, Cachegröße (Beschreibungen ohne Empfehlung oder ohne lokal prüfbare Erwartung), Ausschlüsse und AppLocker-Regeln für Teams und WebView2 (Regelinhalte werden nicht gelesen), Windows-Build und Updates für Teams (Leseweg nicht dokumentiert).

### Schwellen des Katalogs

Alle Schwellen ohne Zahl eines Herstellers sind Vorschläge (P9); der Auftraggeber sieht die Tabelle mit dem Katalog.

| Name | Wert | Einheit | Verwendet von | Herkunft der Zahl |
|---|---|---|---|---|
| `commitPeakPct` | 90 | % | `size.commitHeadroom` | Vorschlag |
| `commitNowPct` | 98 | % | `size.commitHeadroom` | Vorschlag |
| `memPerSessionMB` | 1024 | MB | `size.memoryPerSession` | Vorschlag; Microsoft nennt für Edge auf VDI 1 GB je Benutzer |
| `sessionsPerCpu` | 8 | Sitzungen | `size.cpuPerSession` | Vorschlag |
| `workerCpuMin` | 8 | Prozessoren | `size.workerCpu` | Stalhood (Praxisquelle) |
| `workerMemMinMB` | 24576 | MB | `size.workerMemory` | Stalhood (Praxisquelle) |
| `uptimeDays` | 30 | Tage | `operation.uptime` | Vorschlag |
| `updateAgeDays` | 60 | Tage | `operation.updateAge` | Stalhood (Praxisquelle) |
| `diskFreeGB` | 10 | GB | `operation.diskFree` | Vorschlag |
| `diskFreeHardGB` | 2 | GB | `operation.diskFree` | Vorschlag |
| `disconnectedHours` | 24 | Stunden | `sessions.disconnectedOld` | Vorschlag |
| `unloadedProfiles` | 20 | Profile | `sessions.unloadedProfiles` | Vorschlag |
| `containerUsedPct` | 90 | % | `profile.containerFull` | Citrix: Auslöseschwelle der automatischen Erweiterung |
| `containerUsedHardPct` | 95 | % | `profile.containerFull` | Vorschlag |
| `containersPerUser` | 3 | Container | `profile.containersPerUser` | Vorschlag |
| `printDrivers` | 20 | Treiber | `print.driverCount` | Vorschlag |
| `queuesPerSession` | 10 | Warteschlangen | `print.queueCount` | Vorschlag |
| `signatureAgeDays` | 2 | Tage | `security.signatureAge` | Vorschlag |
| `eventDays` | 3 | Tage | `events.crashes`, `events.fileserver` | Vorschlag |
| `workStartHour` | 7 | Uhr | Arbeitszeit (Ableitungen `maintenance.*`) | Vorschlag |
| `workEndHour` | 18 | Uhr | Arbeitszeit | Vorschlag |

Feste Zahlen in Regeln (keine Schwellen, weil sie aus dem Herstellerdokument stammen): 12 (Hauptversion der VMware Tools), 30 (Wartewert des WEM-Agenten in Sekunden), 602 (Version 6.2 des Clients des Zuordnungswerkzeugs).

Zusammen: 103 gelesene Werte, 61 abgeleitete Fakten (164 feste Fakten), dazu 38 Fakten aus der ausgelieferten Anwendungsliste (16 Edge, 14 Office, 8 Teams; zusammen 202 Fakten); 77 Prüfungen (33 „Empfehlung des Herstellers", 12 „Empfehlung aus der Praxis", 32 „Faustregel"), 21 Schwellen.

| Bereich | Werte | abgeleitete Fakten | Prüfungen (Hersteller / Praxis / Faustregel) |
|---|---|---|---|
| `size` | 16 | 11 | 11 (5 / 3 / 3) |
| `operation` | 8 | 3 | 5 (0 / 3 / 2) |
| `sessions` | 3 | 7 | 5 (0 / 2 / 3) |
| `vda` | 16 | 4 | 7 (6 / 0 / 1) |
| `profile` | 5 | 3 | 3 (0 / 0 / 3) |
| `print` | 8 | 8 | 7 (3 / 0 / 4) |
| `security` | 19 | 5 | 6 (3 / 2 / 1) |
| `network` | 12 | 5 | 6 (3 / 0 / 3) |
| `events` | 1 | 11 | 7 (0 / 1 / 6) |
| `maintenance` | 14 | 4 | 7 (3 / 1 / 3) |
| `apps` | 1 (dazu 38 Fakten der Anwendungsliste) | 0 | 13 (10 / 0 / 3) |

---

## Teil A – neben dem geführten Bericht (Tasks 1a–14c)

### Task 1a: Format und Werteliste

**Files:**
- Modify: `src/WorkerPerf.Common.ps1` (neuer Block hinter `$script:WorkerPerfSkipDetailPattern`)
- Test: `tests/Common.Tests.ps1`
- Mit dem geführten Bericht geteilt: keine. Nicht anfassen: die Zeile `Zustand` der Kategorietabelle und `src/Start-WorkerPerfCapture.ps1` (Task 8), `src/WorkerPerf.Guidance.ps1`.

**Interfaces:**
- Consumes: `$script:WorkerPerfCategories`, `Get-WorkerPerfField`.
- Produces (`src/WorkerPerf.Common.ps1`):
  - `$script:WorkerPerfHealthFormatVersion = 1`; `$script:WorkerPerfHealthAreas = @('size', 'operation', 'sessions', 'vda', 'profile', 'print', 'security', 'network', 'events', 'maintenance', 'apps')`; `$script:WorkerPerfHealthAreaErrors = @('budget', 'noReader', 'notRead', 'notInFile')` (die Kennwörter, die `Error` eines Bereichs tragen kann: Gesamtlimit erreicht, kein Leser, nicht gelesen, nicht in der Datei).
  - `$script:WorkerPerfHealthValues`: geordnet, Kennung → `@{ Area; Type; Unit; Fields; Documented }`, genau die 103 Werte der Tabellen oben in deren Reihenfolge. `Type` wie in den Tabellen (`number`, `bool`, `time`, `list`, `text`, `text:<namen>`); `Unit` die Einheit oder `''`; `Fields` nur bei `list`: geordnet, Feldname → Typ des Felds in derselben Schreibweise (nur dort kommt auch `value` vor: `apps.probes`, Feld `Value`); `Documented` ist `$false` für die acht Werte, deren Zeile „nicht dokumentiert" sagt (`size.vmtoolsPresent`, `size.vmtoolsService`, `operation.pendingServicing`, `operation.pendingUpdate`, `vda.policyRaw`, `profile.policyGpo`, `profile.policyStudio`, `security.applockerCollections`), sonst `$true`.
  - `New-WorkerPerfHealthValue([string]$State, [string]$Reason = '', $Value = $null) -> [ordered]@{ State; Reason; Value }`; ein Zustand außerhalb `read`, `absent`, `unreadable` oder ein Grund außerhalb `''`, `rights`, `notInstalled`, `timeout`, `error` wirft. Ein Inhalt, der eine nicht endliche Zahl ist (`NaN`, plus oder minus unendlich), wird nicht gespeichert: der Wert ist dann `unreadable` mit `error` und ohne Inhalt.
  - `Complete-WorkerPerfHealthArea([string]$Area, [System.Collections.IDictionary]$Values, [double]$DurationMs, [string]$ErrorText = '', [bool]$TimedOut = $false) -> [ordered]@{ Status; DurationMs; Error; Values }`: `Error` = `$ErrorText` (leer, ein Kennwort aus `$script:WorkerPerfHealthAreaErrors` oder die Meldung einer Ausnahme); `Values` in der Reihenfolge der Werteliste; ein gelesener Wert vom Typ `list` wird als Array abgelegt (`[object[]]@(…)`, auch mit einem oder keinem Eintrag), und ein Feld eines Listeneintrags, das eine nicht endliche Zahl trägt, wird `$null`; ein Wert des Bereichs, der in `$Values` fehlt, wird `unreadable` mit `timeout` (bei `$TimedOut`) oder `error`; eine Kennung, die nicht zum Bereich gehört, wirft mit der Kennung in der Meldung. `Status`: `failed`, wenn kein Wert `read` oder `absent` ist; sonst `partial`, wenn einer `unreadable` ist; sonst `read`.
  - `New-WorkerPerfHealth([datetime]$ReadAt, [double]$DurationMs, [System.Collections.IDictionary]$Areas) -> [ordered]@{ FormatVersion; ReadAt; DurationMs; Areas }`: `ReadAt` als `ToString('o')` mit der invarianten Kultur; `Areas` geordnet nach `$script:WorkerPerfHealthAreas`; ein Bereich, der fehlt, wird mit `Complete-WorkerPerfHealthArea <id> @{} 0 'notRead'` ergänzt.
  - `ConvertTo-WorkerPerfHealthTime([datetime]$Time) -> long`: Millisekunden seit 1970 (UTC); `[datetime]::MinValue` ergibt 0.
  - `$script:WorkerPerfHealthWemServices`: die drei Dienste, die der WEM-Agent braucht, je als Liste ihrer dokumentierten Anzeigenamen: `@(@('Citrix WEM Agent Host Service', 'Norskale Agent Host Service'), @('Citrix WEM User Logon Service', 'Citrix WEM Agent User Logon Service'), @('System Event Notification Service'))`. Der Windows-Leser (Task 5) und die Ableitung `vda.wemServicesNotReady` (Task 12) arbeiten aus dieser Liste; die erste Gruppe ist der Agent-Dienst.
- Produces (Format `health.json`, wie es Task 8 schreibt; die Zeilen des Bereichs `apps` bildet Task 1b):

```json
{ "FormatVersion": 1, "ReadAt": "2026-11-13T08:00:00.0000000+01:00", "DurationMs": 4210,
  "Areas": { "size": { "Status": "read", "DurationMs": 312, "Error": "",
      "Values": { "size.cpuLogical": { "State": "read", "Reason": "", "Value": 8 },
                  "size.pagefiles": { "State": "read", "Reason": "", "Value": [ { "Path": "C:\\pagefile.sys", "AllocatedMB": 32768, "PeakUsageMB": 5200, "Temporary": false } ] },
                  "size.vmtoolsService": { "State": "absent", "Reason": "notInstalled", "Value": null } } },
    "operation": { "Status": "partial", "DurationMs": 95, "Error": "", "Values": { "operation.volumes": { "State": "unreadable", "Reason": "rights", "Value": null } } },
    "apps": { "Status": "read", "DurationMs": 40, "Error": "",
      "Values": { "apps.probes": { "State": "read", "Reason": "", "Value": [
        { "App": "edge", "Id": "installed", "Kind": "file", "Read": "exists", "State": "read", "Reason": "", "Value": true, "Names": null },
        { "App": "edge", "Id": "backgroundMode", "Kind": "registryValue", "Read": "value", "State": "read", "Reason": "", "Value": 1, "Names": null },
        { "App": "edge", "Id": "userDataDir", "Kind": "registryValue", "Read": "value", "State": "absent", "Reason": "", "Value": null, "Names": null },
        { "App": "teams", "Id": "installed", "Kind": "file", "Read": "exists", "State": "read", "Reason": "", "Value": false, "Names": null },
        { "App": "teams", "Id": "disableAutoUpdate", "Kind": "registryValue", "Read": "value", "State": "absent", "Reason": "notInstalled", "Value": null, "Names": null } ] } } } } }
```

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/Common.Tests.ps1`)

```powershell
Describe 'Zustandsbild: Format und Werteliste' {
    It 'fuehrt elf Bereiche in fester Reihenfolge und jeden Wert bei genau einem Bereich' {
        $WorkerPerfHealthFormatVersion | Should -Be 1
        $WorkerPerfHealthAreas | Should -Be @('size', 'operation', 'sessions', 'vda', 'profile', 'print', 'security', 'network', 'events', 'maintenance', 'apps')
        $count = @{}
        foreach ($id in $WorkerPerfHealthValues.Keys) {
            $v = $WorkerPerfHealthValues[$id]; $id | Should -BeLike ($v.Area + '.*'); $count[$v.Area] = 1 + [int]$count[$v.Area]
            $v.Type | Should -Match '^(number|bool|time|list|text(:(host|hosts|share|path|user|client|domain|address|protected|free))?)$' -Because $id
            if ($v.Type -eq 'list') {
                @($v.Fields.Keys).Count | Should -BeGreaterThan 0 -Because $id
                foreach ($t in $v.Fields.Values) { $t | Should -Match '^(number|bool|time|value|text(:(host|hosts|share|path|user|client|domain|address|protected|free))?)$' -Because $id }
            }
        }
        $want = @{ size = 16; operation = 8; sessions = 3; vda = 16; profile = 5; print = 8; security = 19; network = 12; events = 1; maintenance = 14; apps = 1 }
        foreach ($a in $WorkerPerfHealthAreas) { $count[$a] | Should -Be $want[$a] -Because $a }
        @($WorkerPerfHealthValues.Keys).Count | Should -Be 103
        $WorkerPerfHealthValues['vda.controllers'].Fields['Entry'] | Should -Be 'text:host'; $WorkerPerfHealthValues['maintenance.tasks'].Fields['Path'] | Should -Be 'text:free'
        $WorkerPerfHealthValues['vda.wemServer'].Type | Should -Be 'text:host'; $WorkerPerfHealthValues['vda.wemCacheLocation'].Type | Should -Be 'text:path'
        @($WorkerPerfHealthValues['operation.volumes'].Fields.Keys) | Should -Be @('Drive', 'SizeGB', 'FreeGB', 'FileSystem', 'System', 'PageFile')
        @($WorkerPerfHealthValues['apps.probes'].Fields.Keys) | Should -Be @('App', 'Id', 'Kind', 'Read', 'State', 'Reason', 'Value', 'Names')
        $WorkerPerfHealthValues['apps.probes'].Fields['Value'] | Should -Be 'value'; $WorkerPerfHealthValues['apps.probes'].Fields['Names'] | Should -Be 'text:free'
        $WorkerPerfHealthValues['operation.lastBoot'].Type | Should -Be 'time'; $WorkerPerfHealthValues['print.mappingClientVersion'].Type | Should -Be 'text'; $WorkerPerfHealthValues['size.memTotalMB'].Unit | Should -Be 'MB'
        @($WorkerPerfHealthValues.Keys | Where-Object { -not $WorkerPerfHealthValues[$_].Documented }) | Should -Be @('size.vmtoolsPresent', 'size.vmtoolsService',
            'operation.pendingServicing', 'operation.pendingUpdate', 'vda.policyRaw', 'profile.policyGpo', 'profile.policyStudio', 'security.applockerCollections')
    }
    It 'ergaenzt einen Bereich um die nicht gelesenen Werte und stuft ihn ein' {   # Review Focus 1
        $a = Complete-WorkerPerfHealthArea 'events' @{ 'events.logs' = (New-WorkerPerfHealthValue 'read' '' @()) } 12.5
        $a.Status | Should -Be 'read'; $a.DurationMs | Should -Be 12.5; $a.Error | Should -Be ''
        $p = Complete-WorkerPerfHealthArea 'print' @{ 'print.queueCount' = (New-WorkerPerfHealthValue 'read' '' 2); 'print.spooler' = (New-WorkerPerfHealthValue 'absent' 'notInstalled') } 10 '' $true
        $p.Status | Should -Be 'partial'
        @($p.Values.Keys) | Should -Be @('print.isolationExecution', 'print.isolationOverride', 'print.queueCount', 'print.spooler', 'print.spoolerStartMode', 'print.citrixPrintService', 'print.operationalLog', 'print.mappingClientVersion')
        $p.Values['print.operationalLog'].State | Should -Be 'unreadable'; $p.Values['print.operationalLog'].Reason | Should -Be 'timeout'
        $f = Complete-WorkerPerfHealthArea 'vda' @{} 3 'Zugriff verweigert'
        $f.Status | Should -Be 'failed'; $f.Error | Should -Be 'Zugriff verweigert'; $f.Values['vda.version'].Reason | Should -Be 'error'
        { Complete-WorkerPerfHealthArea 'vda' @{ 'print.spooler' = (New-WorkerPerfHealthValue 'read' '' 'Running') } 1 } | Should -Throw '*print.spooler*'
        { New-WorkerPerfHealthValue 'gelesen' } | Should -Throw; { New-WorkerPerfHealthValue 'unreadable' 'kaputt' } | Should -Throw
    }
    It 'laesst eine Liste eine Liste sein, auch mit einem oder keinem Eintrag' {
        $one = Complete-WorkerPerfHealthArea 'size' @{ 'size.pagefiles' = (New-WorkerPerfHealthValue 'read' '' ([ordered]@{ Path = 'C:\pagefile.sys'; AllocatedMB = 1 }))
            'size.netAdapters' = (New-WorkerPerfHealthValue 'read' '' @()) } 1
        ($one.Values['size.pagefiles'].Value -is [array]) | Should -BeTrue; @($one.Values['size.pagefiles'].Value).Count | Should -Be 1
        ($one.Values['size.netAdapters'].Value -is [array]) | Should -BeTrue; @($one.Values['size.netAdapters'].Value).Count | Should -Be 0
        ($one | ConvertTo-Json -Depth 10 -Compress) | Should -Match '"size\.pagefiles":\{"State":"read","Reason":"","Value":\[\{"Path"'
    }
    It 'schreibt den Kopf des Zustandsbilds und fuellt fehlende Bereiche' {
        $at = [datetime]::SpecifyKind([datetime]'2026-01-15T08:00:00', [DateTimeKind]::Local)
        $h = New-WorkerPerfHealth $at 4210 @{ events = (Complete-WorkerPerfHealthArea 'events' @{ 'events.logs' = (New-WorkerPerfHealthValue 'read' '' @()) } 5) }
        $h.FormatVersion | Should -Be 1; $h.DurationMs | Should -Be 4210; $h.ReadAt | Should -Match '^2026-01-15T08:00:00\.0000000[+-]\d\d:\d\d$'
        @($h.Areas.Keys) | Should -Be $WorkerPerfHealthAreas; $h.Areas['size'].Status | Should -Be 'failed'; $h.Areas['size'].Error | Should -Be 'notRead'; $h.Areas['events'].Status | Should -Be 'read'
        $h.Areas['apps'].Values['apps.probes'].State | Should -Be 'unreadable'
        $WorkerPerfHealthAreaErrors | Should -Be @('budget', 'noReader', 'notRead', 'notInFile')
        @($WorkerPerfHealthWemServices).Count | Should -Be 3; $WorkerPerfHealthWemServices[0] | Should -Be @('Citrix WEM Agent Host Service', 'Norskale Agent Host Service'); $WorkerPerfHealthWemServices[2] | Should -Be @('System Event Notification Service')
        ConvertTo-WorkerPerfHealthTime ([datetime]::new(1970, 1, 2, 0, 0, 0, [DateTimeKind]::Utc)) | Should -Be 86400000; ConvertTo-WorkerPerfHealthTime ([datetime]::MinValue) | Should -Be 0
    }
    It 'speichert keine Zahl, die nicht endlich ist' {
        # Windows PowerShell 5.1 schriebe NaN und Infinity ohne Anfuehrungszeichen: die ganze Datei waere kein gueltiges JSON
        (New-WorkerPerfHealthValue 'read' '' ([double]::NaN)).State | Should -Be 'unreadable'; (New-WorkerPerfHealthValue 'read' '' ([double]::NaN)).Reason | Should -Be 'error'
        (New-WorkerPerfHealthValue 'read' '' ([double]::PositiveInfinity)).Value | Should -BeNullOrEmpty; (New-WorkerPerfHealthValue 'read' '' 96.5).Value | Should -Be 96.5
        $a = Complete-WorkerPerfHealthArea 'profile' @{ 'profile.containers' = (New-WorkerPerfHealthValue 'read' '' @([ordered]@{ Location = '\\fs01\profile$\a.vhdx'; UsedPct = [double]::NaN })) } 1
        $a.Values['profile.containers'].State | Should -Be 'read'; $a.Values['profile.containers'].Value[0].UsedPct | Should -BeNullOrEmpty
        ($a | ConvertTo-Json -Depth 10) | Should -Not -Match 'NaN|Infinity'
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Common.Tests.ps1`
Expected: FAIL, `$WorkerPerfHealthAreas` ist leer

- [ ] **Step 3: Format, Werteliste und Bausteine in `src/WorkerPerf.Common.ps1` mit den Signaturen der Interfaces umsetzen**

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Common.ps1 tests/Common.Tests.ps1
git commit -m "Define the health picture format and its value list"
```

---

### Task 1b: Anwendungsliste für das Zustandsbild lesen

**Files:**
- Modify: `src/WorkerPerf.Common.ps1` (neuer Block hinter dem aus Task 1a)
- Test: `tests/Common.Tests.ps1`
- Mit dem geführten Bericht geteilt: keine. Nicht anfassen: `Read-WorkerPerfApps` und `Stop-WorkerPerfApps` in `src/WorkerPerf.Guidance.ps1` und ihre Tests in `tests/Guidance.Tests.ps1` (der Leser des geführten Berichts bleibt, wie er ist: er liefert das Listenobjekt mit `apps` und `version` für die Bedingung `app.<key>`); `src/apps.json` (Task 2).

**Interfaces:**
- Consumes: Task 1a (`ConvertTo-WorkerPerfHealthTime`); `ConvertFrom-WorkerPerfJsonFile`, `Get-WorkerPerfField`. Zum Vergleich, nicht zum Aufruf: `Read-WorkerPerfApps([string]$Path)` in `src/WorkerPerf.Guidance.ps1` (seine Regel für `key` und die Form seiner Meldungen). Der Collector bindet `src/WorkerPerf.Guidance.ps1` nicht ein; deshalb steht der Leser des Zustandsbilds in `src/WorkerPerf.Common.ps1` und trägt einen eigenen Namen. Eine zweite Funktion `Read-WorkerPerfApps` gäbe es je nach Reihenfolge des Einbindens in zwei Fassungen mit verschiedenem Rückgabewert.
- Produces (`src/WorkerPerf.Common.ps1`):
  - `$script:WorkerPerfAppProbeKinds`: geordnet, Leseart → Liste der erlaubten `read`, die erste ist die Vorgabe: `registryValue` (`value`), `registryKey` (`exists`, `valueCount`, `subKeyCount`), `service` (`state`, `startMode`), `scheduledTask` (`enabled`, `exists`, `lastRun`, `nextRun`), `file` (`version`, `exists`).
  - `Read-WorkerPerfHealthApps([string]$Path) -> object[]`: liest und prüft die Anwendungsliste; je Anwendung `[ordered]@{ key; label; processes (string[]); installed ($null oder eine Probe ohne id); probes (Probe[]) }`, je Probe `[ordered]@{ id; kind; read; path; name; displayName; names; label; documented }` mit eingesetzten Vorgaben (`read` = erste Angabe der Leseart, `names` falsch, `label` = `id`, `documented` wahr; nicht benötigte Ortsfelder leer). Fehler werfen mit einer dieser Meldungen, in der Form des Lesers des geführten Berichts: `Anwendungsliste '<Pfad>' fehlt.`; `Anwendungsliste '<Pfad>': <Grund>.` (kein gültiges JSON); `Anwendungsliste '<Pfad>': Feld '<feld>' <Grund>.`; `Anwendungsliste '<Pfad>': Anwendung '<key>': Feld '<feld>' <Grund>.` (für eine Anwendung ohne brauchbaren `key` steht `Anwendung apps[<i>]`); `Anwendungsliste '<Pfad>': Anwendung '<key>': Probe '<id>': <Grund>.` (für `installed` steht `Probe 'installed'`). Geprüft wird:
    - Datei: gültiges JSON mit `version` (Text) und `apps` (Liste, auch leer).
    - Anwendung: `key` (`^[A-Za-z0-9]+$`, einmalig; dieselbe Regel wie im Leser des geführten Berichts), `label` (nicht leer), `processes` (mindestens ein Name); `installed` und `probes` sind wahlfrei, `probes` ohne `installed` wird abgelehnt. Eine Anwendung ohne `installed` bleibt in der Liste (der geführte Bericht nutzt ihre `processes`); das Zustandsbild liest sie nicht. Die Regeln für die Muster in `processes` (gültiges Muster, jedes Muster nur bei einer Anwendung) prüft nur `Read-WorkerPerfApps` des geführten Berichts; hier genügt eine Liste mit mindestens einem Text.
    - Probe: `id` (`^[a-z][A-Za-z0-9]*$`, einmalig je Anwendung, nicht `installed`); `kind` aus `$script:WorkerPerfAppProbeKinds`; `read`, wenn angegeben, aus der Liste der Leseart; die Pflichtfelder der Leseart (Tabelle „Lesearten"): `path` einer Registrierungsprobe beginnt mit `HKLM\` (ohne Rücksicht auf Groß- und Kleinschreibung), `path` einer Aufgabe mit `\`, `path` einer Datei ist ein lokaler absoluter Pfad (`^[A-Za-z]:\\`), ohne `..`, mit höchstens einem `*`, und das `*` steht nicht im letzten Teil; `service` nennt genau eines von `name` und `displayName`; `names` ist bei `registryValue` Pflicht (Wahrheitswert) und bei den anderen Lesearten nicht erlaubt; jedes Feld außer `id`, `kind`, `read`, `path`, `name`, `displayName`, `names`, `label`, `documented` wird abgelehnt (`Feld '<name>' ist unbekannt`).
  - `Get-WorkerPerfAppFactType($Probe) -> string`: der Typ des Fakts einer Probe nach der Tabelle „Lesearten" (`value`, `text:free`, `bool`, `number`, `text`, `time`).
  - `Get-WorkerPerfAppRows -Apps <object[]> -Read <hashtable> [-FailReason <scriptblock>] [-Expired <scriptblock>] -> ordered[]`: die Zeilen des Werts `apps.probes` (`[ordered]@{ App; Id; Kind; Read; State; Reason; Value; Names }`), je Anwendung mit `installed` zuerst die Zeile `installed`, dann die Proben in der Reihenfolge der Datei. `-Read` nennt je Leseart einen Scriptblock der Quelle, der `$null` liefert, wenn es das Gesuchte nicht gibt, und sonst eine Tabelle: `registryValue` `{ param($Path, $Name) }` → `@{ Value }`; `registryKey` `{ param($Path) }` → `@{ ValueCount; SubKeyCount }`; `service` `{ param($Name, $DisplayName) }` → `@{ State; StartMode }`; `scheduledTask` `{ param($Path) }` → `@{ Enabled; LastRun; NextRun }` (`datetime`, `MinValue` = keiner); `file` `{ param($Path) }` → `@{ Version }` (Text, `''` ohne Version). Regeln:
    - Zeile `installed`: `read` mit `Value` wahr oder falsch.
    - Ist die Anwendung nicht installiert, wird keine ihrer Proben gelesen: jede Zeile ist `absent` mit `notInstalled`. Scheitert das Lesen von `installed`, ist jede Zeile der Anwendung `unreadable` mit dessen Grund.
    - Eine Probe, deren Leser `$null` liefert, ist `absent` ohne Grund; bei `read` = `exists` ist sie `read` mit `Value` falsch.
    - Wert einer gelesenen Probe: `registryValue` eine Zahl (bei einer Ganzzahl) oder Text (eine Liste von Zeichenketten mit „; " verbunden, ein Bytefeld als `binaer, <n> Byte`), mit `names` im Feld `Names` statt `Value`; `valueCount`, `subKeyCount` Zahlen; `state`, `startMode`, `version` Text; `enabled`, `exists` Wahrheitswerte; `lastRun`, `nextRun` über `ConvertTo-WorkerPerfHealthTime`.
    - Wirft ein Leser, ist die Zeile `unreadable` mit dem Grund, den `-FailReason` für den Fehler liefert (`{ param($ErrorRecord) }` → `rights`, `timeout` oder `error`; Vorgabe `error`). Liefert `-Expired` vor einer Zeile wahr, werden sie und alle folgenden `unreadable` mit `timeout`, ohne dass ein Leser läuft.
- Produces (Format `src/apps.json`; `key`, `label`, `processes` stammen aus dem geführten Bericht):

```json
{ "version": "2026-11-13",
  "apps": [ { "key": "edge", "label": "Microsoft Edge", "processes": ["msedge.exe"],
      "installed": { "kind": "file", "path": "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe" },
      "probes": [ { "id": "version", "kind": "file", "path": "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe" },
                  { "id": "backgroundMode", "kind": "registryValue", "path": "HKLM\\SOFTWARE\\Policies\\Microsoft\\Edge", "name": "BackgroundModeEnabled", "names": false, "label": "Hintergrundmodus" },
                  { "id": "updateService", "kind": "service", "name": "edgeupdate", "read": "startMode", "documented": false } ] } ] }
```

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/Common.Tests.ps1`)

```powershell
Describe 'Anwendungsliste lesen und pruefen' {
    BeforeAll {
        function New-AppFile([scriptblock]$Change = {}) {
            # eine kleine gueltige Liste als Hashtable in $a; . $Change aendert sie; liefert den Pfad der geschriebenen Datei
            $a = [ordered]@{ version = '2026-11-13'; apps = @(
                [ordered]@{ key = 'alpha'; label = 'Alpha'; processes = @('alpha.exe'); installed = [ordered]@{ kind = 'file'; path = 'C:\Program Files\Alpha\alpha.exe' }
                    probes = @([ordered]@{ id = 'version'; kind = 'file'; path = 'C:\Program Files\Alpha\alpha.exe' }
                        [ordered]@{ id = 'mode'; kind = 'registryValue'; path = 'HKLM\SOFTWARE\Alpha'; name = 'Mode'; names = $false; label = 'Betriebsart' }
                        [ordered]@{ id = 'dataPath'; kind = 'registryValue'; path = 'HKLM\SOFTWARE\Alpha'; name = 'DataPath'; names = $true }
                        [ordered]@{ id = 'plugins'; kind = 'registryKey'; path = 'HKLM\SOFTWARE\Alpha\Plugins'; read = 'subKeyCount' }
                        [ordered]@{ id = 'service'; kind = 'service'; displayName = 'Alpha Dienst'; read = 'startMode'; documented = $false }
                        [ordered]@{ id = 'task'; kind = 'scheduledTask'; path = '\Alpha\Update' }
                        [ordered]@{ id = 'nextUpdate'; kind = 'scheduledTask'; path = '\Alpha\Update'; read = 'nextRun' }
                        [ordered]@{ id = 'addin'; kind = 'file'; path = 'C:\Program Files\Alpha_*\addin'; read = 'exists' }) }
                [ordered]@{ key = 'beta'; label = 'Beta'; processes = @('beta.exe') }) }          # ohne installed: nur fuer den gefuehrten Bericht
            . $Change
            $file = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.json'); [IO.File]::WriteAllText($file, (ConvertTo-Json -InputObject $a -Depth 8)); $file
        }
        function New-Reader([hashtable]$Missing = @{}) {
            # Leser, die alles vorfinden ausser dem, was $Missing nennt (Leseart -> Pfad oder Name)
            @{ registryValue = { param($Path, $Name) if ($Missing['registryValue'] -eq $Name) { return $null }; @{ Value = $(if ($Name -eq 'DataPath') { '\\fs01\alpha$' } else { 3 }) } }.GetNewClosure()
               registryKey = { param($Path) @{ ValueCount = 2; SubKeyCount = 5 } }
               service = { param($Name, $DisplayName) if ($Missing['service'] -eq $DisplayName) { return $null }; @{ State = 'Running'; StartMode = 'Auto' } }.GetNewClosure()
               scheduledTask = { param($Path) if ($Missing['scheduledTask'] -eq $Path) { return $null }; @{ Enabled = $true; LastRun = [datetime]::MinValue; NextRun = [datetime]::new(1970, 1, 2, 0, 0, 0, [DateTimeKind]::Utc) } }.GetNewClosure()
               file = { param($Path) if ($Missing['file'] -and $Path -like $Missing['file']) { return $null }; @{ Version = $(if ($Path -like '*addin') { '' } else { '1.2.3' }) } }.GetNewClosure() }
        }
    }
    It 'liest die Liste und setzt die Vorgaben ein' {
        $apps = @(Read-WorkerPerfHealthApps (New-AppFile)); @($apps.key) | Should -Be @('alpha', 'beta')
        $a = $apps[0]; $a.label | Should -Be 'Alpha'; @($a.processes) | Should -Be @('alpha.exe'); $a.installed.kind | Should -Be 'file'; @($a.probes.id) | Should -Be @('version', 'mode', 'dataPath', 'plugins', 'service', 'task', 'nextUpdate', 'addin')
        @($a.probes.read) | Should -Be @('version', 'value', 'value', 'subKeyCount', 'startMode', 'enabled', 'nextRun', 'exists')
        @($a.probes.label) | Should -Be @('version', 'Betriebsart', 'dataPath', 'plugins', 'service', 'task', 'nextUpdate', 'addin')
        @($a.probes | ForEach-Object { Get-WorkerPerfAppFactType $_ }) | Should -Be @('text', 'value', 'text:free', 'number', 'text', 'bool', 'time', 'bool')
        @($a.probes | Where-Object { -not $_.documented }).id | Should -Be @('service'); $apps[1].installed | Should -BeNullOrEmpty; @($apps[1].probes).Count | Should -Be 0
        @(Read-WorkerPerfHealthApps (New-AppFile { $a.apps = @() })).Count | Should -Be 0
    }
    It 'lehnt eine fehlerhafte Liste mit Anwendung und Probe in der Meldung ab' -TestCases @(
        @{ Change = { $a.apps[0].probes[1].path = 'HKCU\SOFTWARE\Alpha' }; Msg = "*Anwendung 'alpha': Probe 'mode':*HKLM*" }
        @{ Change = { $a.apps[0].probes[1].kind = 'command' }; Msg = "*Anwendung 'alpha': Probe 'mode':*command*" }                       # keine andere Leseart, nichts wird ausgefuehrt
        @{ Change = { $a.apps[0].probes[1].Remove('name') }; Msg = "*Anwendung 'alpha': Probe 'mode':*name*" }
        @{ Change = { $a.apps[0].probes[1].Remove('names') }; Msg = "*Anwendung 'alpha': Probe 'mode':*names*" }
        @{ Change = { $a.apps[0].probes[0].names = $true }; Msg = "*Anwendung 'alpha': Probe 'version':*names*" }
        @{ Change = { $a.apps[0].probes[3].read = 'size' }; Msg = "*Anwendung 'alpha': Probe 'plugins':*read*size*" }
        @{ Change = { $a.apps[0].probes[4].name = 'AlphaSvc' }; Msg = "*Anwendung 'alpha': Probe 'service':*name*displayName*" }
        @{ Change = { $a.apps[0].probes[5].path = 'Alpha\Update' }; Msg = "*Anwendung 'alpha': Probe 'task':*path*" }
        @{ Change = { $a.apps[0].probes[0].path = '\\fs01\alpha\alpha.exe' }; Msg = "*Anwendung 'alpha': Probe 'version':*path*" }
        @{ Change = { $a.apps[0].probes[0].path = 'C:\Program Files\*\Alpha_*\alpha.exe' }; Msg = "*Anwendung 'alpha': Probe 'version':*path*" }
        @{ Change = { $a.apps[0].probes[0].path = 'C:\Program Files\Alpha\*.exe' }; Msg = "*Anwendung 'alpha': Probe 'version':*path*" }
        @{ Change = { $a.apps[0].probes[0].command = 'alpha.exe /version' }; Msg = "*Anwendung 'alpha': Probe 'version':*command*unbekannt*" }
        @{ Change = { $a.apps[0].probes[1].id = 'version' }; Msg = "*Anwendung 'alpha': Probe 'version':*doppelt*" }
        @{ Change = { $a.apps[0].probes[1].id = 'installed' }; Msg = "*Anwendung 'alpha': Probe 'installed':*" }
        @{ Change = { $a.apps[0].installed.path = 'HKLM\SOFTWARE\Alpha' }; Msg = "*Anwendung 'alpha': Probe 'installed':*path*" }
        @{ Change = { $a.apps[1].probes = @([ordered]@{ id = 'x'; kind = 'file'; path = 'C:\x.exe' }) }; Msg = "*Anwendung 'beta': Feld 'probes'*installed*" }
        @{ Change = { $a.apps[1].key = 'alpha' }; Msg = "*Anwendung 'alpha': Feld 'key'*doppelt*" }
        @{ Change = { $a.apps[1].key = 'Beta App' }; Msg = "*Anwendung 'Beta App': Feld 'key'*" }
        @{ Change = { $a.apps[1].processes = @() }; Msg = "*Anwendung 'beta': Feld 'processes'*" }
        @{ Change = { $a.Remove('apps') }; Msg = "Anwendungsliste '*': *apps*" }
    ) { { Read-WorkerPerfHealthApps (New-AppFile $Change) } | Should -Throw $Msg }
    It 'meldet eine fehlende oder kaputte Datei' {
        { Read-WorkerPerfHealthApps (Join-Path $TestDrive 'gibtesnicht.json') } | Should -Throw "Anwendungsliste '*gibtesnicht.json' fehlt."
        $bad = Join-Path $TestDrive 'bad.json'; [IO.File]::WriteAllText($bad, '{ kein json'); { Read-WorkerPerfHealthApps $bad } | Should -Throw "Anwendungsliste '*bad.json': *"
    }
    It 'bildet je Probe eine Zeile mit Zustand und Wert' {
        $apps = @(Read-WorkerPerfHealthApps (New-AppFile)); $rows = @(Get-WorkerPerfAppRows -Apps $apps -Read (New-Reader))
        @($rows.App | Select-Object -Unique) | Should -Be @('alpha'); @($rows.Id) | Should -Be @('installed', 'version', 'mode', 'dataPath', 'plugins', 'service', 'task', 'nextUpdate', 'addin')
        $r = @{}; foreach ($x in $rows) { $r[$x.Id] = $x }; foreach ($x in $rows) { $x.State | Should -Be 'read' -Because $x.Id; @($x.Keys) | Should -Be @('App', 'Id', 'Kind', 'Read', 'State', 'Reason', 'Value', 'Names') }
        $r.installed.Value | Should -BeTrue; $r.installed.Read | Should -Be 'exists'; $r.version.Value | Should -Be '1.2.3'; $r.mode.Value | Should -Be 3; $r.mode.Names | Should -BeNullOrEmpty
        $r.dataPath.Value | Should -BeNullOrEmpty; $r.dataPath.Names | Should -Be '\\fs01\alpha$'; $r.plugins.Value | Should -Be 5; $r.service.Value | Should -Be 'Auto'
        $r.task.Value | Should -BeTrue; $r.nextUpdate.Value | Should -Be 86400000; $r.addin.Value | Should -BeTrue
    }
    It 'nennt nicht gesetzt, nicht installiert und nicht lesbar beim Namen' {   # Review Focus 3
        $apps = @(Read-WorkerPerfHealthApps (New-AppFile))
        $r = @{}; foreach ($x in @(Get-WorkerPerfAppRows -Apps $apps -Read (New-Reader @{ registryValue = 'Mode'; scheduledTask = '\Alpha\Update'; file = '*addin' }))) { $r[$x.Id] = $x }
        $r.mode.State | Should -Be 'absent'; $r.mode.Reason | Should -Be ''; $r.task.State | Should -Be 'absent'; $r.nextUpdate.State | Should -Be 'absent'
        $r.addin.State | Should -Be 'read'; $r.addin.Value | Should -BeFalse                                   # exists: gelesen, nein
        $calls = [ref]0; $read = New-Reader @{ file = '*alpha.exe' }; $inner = $read.registryValue
        $read.registryValue = { param($Path, $Name) $calls.Value++; & $inner $Path $Name }.GetNewClosure()
        $rows = @(Get-WorkerPerfAppRows -Apps $apps -Read $read)
        $rows[0].Value | Should -BeFalse; @($rows | Select-Object -Skip 1 | Where-Object { $_.State -ne 'absent' -or $_.Reason -ne 'notInstalled' }).Count | Should -Be 0
        $calls.Value | Should -Be 0                                                                              # nicht installiert: keine Probe wird gelesen
        $read = New-Reader; $read.service = { throw 'Zugriff verweigert' }
        $rows = @(Get-WorkerPerfAppRows -Apps $apps -Read $read -FailReason { param($e) 'rights' })
        ($rows | Where-Object Id -eq 'service').State | Should -Be 'unreadable'; ($rows | Where-Object Id -eq 'service').Reason | Should -Be 'rights'; ($rows | Where-Object Id -eq 'task').State | Should -Be 'read'
        $read = New-Reader; $read.file = { throw 'kaputt' }
        $rows = @(Get-WorkerPerfAppRows -Apps $apps -Read $read); @($rows | Where-Object { $_.State -ne 'unreadable' -or $_.Reason -ne 'error' }).Count | Should -Be 0
        $n = [ref]0; $rows = @(Get-WorkerPerfAppRows -Apps $apps -Read (New-Reader) -Expired { $n.Value++; $n.Value -gt 3 }.GetNewClosure())
        @($rows | Where-Object State -eq 'read').Count | Should -Be 3; @($rows | Where-Object Reason -eq 'timeout').Count | Should -Be 6      # Review Focus 1
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Common.Tests.ps1`
Expected: FAIL, `Read-WorkerPerfHealthApps` ist nicht definiert

- [ ] **Step 3: `$script:WorkerPerfAppProbeKinds`, `Read-WorkerPerfHealthApps`, `Get-WorkerPerfAppFactType` und `Get-WorkerPerfAppRows` umsetzen**

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0` (die Tests des geführten Berichts zu `Read-WorkerPerfApps` bleiben grün: die Funktion ist unberührt)

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Common.ps1 tests/Common.Tests.ps1
git commit -m "Read and check the application list for the health picture"
```

---

### Task 2: Anwendungsliste – Proben für Edge, Office und Teams

**Files:**
- Modify: `src/apps.json` (bei Edge, Office und Teams die Felder `installed` und `probes`), `tests/TestHelpers.ps1` (neue Funktion am Ende), `tests/MaskCensus.json` (acht Zeilen hinter `appList.apps[].processes[]`)
- Test: `tests/Common.Tests.ps1`
- Mit dem geführten Bericht geteilt: `src/apps.json` (die Datei und ihre Felder `key`, `label`, `processes` gehören dem geführten Bericht; diese Task ändert sie nicht und fügt nur die zwei neuen Felder an), `tests/TestHelpers.ps1`, `tests/MaskCensus.json` (der geführte Bericht legt die Anwendungsliste, wie sie in der Datei steht, als `appList` in die Berichtsdaten; mit den neuen Feldern entstehen dort neue Textfelder, die der Bestand der Maskierung kennen muss). Nicht anfassen: `src/New-WorkerPerfReport.ps1`, `src/WorkerPerf.Mask.ps1` (die Schlüsselwortfelder `kind` und `id` stehen dort schon), `src/guidance.de.json`, `src/WorkerPerf.Guidance.ps1`, `tests/Guidance.Tests.ps1`, `tests/GuidanceCatalogue.Tests.ps1`.

**Voraussetzung:** `src/apps.json`, ihr Leser `Read-WorkerPerfApps` und das Feld `appList` der Berichtsdaten liegen im Worktree vor (Commit „Add the application list and the app condition to the guidance" der Korrekturrunde 2 von Task 6 des geführten Berichts). Fehlen sie, wird der Hauptstrang in den Worktree geholt; diese Task legt keine zweite Fassung der Datei an.

**Interfaces:**
- Consumes: Task 1b (`Read-WorkerPerfHealthApps`); die Tabellen „Proben der ausgelieferten Anwendungsliste" im Abschnitt „Anwendungen (`apps`)".
- Produces:
  - `src/apps.json`: die Anwendungen `edge`, `office`, `teams` tragen `installed` und `probes` genau nach den Tabellen (Kennung, Leseart, Ort, `read`, `names`, `documented: false` bei den vier gekennzeichneten Proben; `read` steht nur da, wo es von der Vorgabe abweicht). Jede Probe hat ein `label` in Alltagssprache (die Spalte „Was" der Tabelle). Die zwei weiteren Anwendungen der Datei (`webview2`, `printaurus`) und jede, die der geführte Bericht später dort einträgt, bleiben ohne `installed`.
  - `New-TestAppFile([string]$Dir) -> string` (`tests/TestHelpers.ps1`): schreibt `<Dir>/apps.test.json` mit dem Inhalt von `src/apps.json` und einer weiteren, erfundenen Anwendung am Ende (im Plan „die vierte Anwendung": die vierte mit Proben) und liefert den Pfad: `key` `simapp`, `label` „Sim-Fachanwendung", `processes` `simapp.exe`, `installed` `file` `C:\Program Files\SimApp\simapp.exe`, `probes`: `version` (`file`, derselbe Pfad), `cacheMode` (`registryValue` `HKLM\SOFTWARE\SimApp`, `CacheMode`, `names` falsch, `label` „Cache-Betriebsart"), `dataPath` (`registryValue` `HKLM\SOFTWARE\SimApp`, `DataPath`, `names` wahr).
  - `tests/MaskCensus.json`: `appList.apps[].installed.kind`, `appList.apps[].probes[].id` und `appList.apps[].probes[].kind` → `keyword` (die Feldnamen `kind` und `id` stehen schon in `$script:WorkerPerfMaskKeywordFields`); `appList.apps[].installed.path`, `appList.apps[].probes[].path`, `appList.apps[].probes[].name`, `appList.apps[].probes[].label` und `appList.apps[].probes[].read` → `composed` (Texte der ausgelieferten Datei, keine Namen eines Servers).

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/Common.Tests.ps1`)

```powershell
Describe 'Anwendungsliste in src' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        $script:AppFile = Join-Path $PSScriptRoot '../src/apps.json'; $script:Apps = @{}; foreach ($a in @(Read-WorkerPerfHealthApps $AppFile)) { $Apps[$a.key] = $a }
    }
    It 'beschreibt Edge, Office und Teams mit den Proben des Plans' {
        @($Apps.edge.probes.id) | Should -Be @('version', 'webview2Version', 'updateDefault', 'updateStable', 'updateWebView2', 'updateCheckMinutes', 'startupBoost', 'backgroundMode',
            'sleepingTabs', 'autoDiscard', 'roamingProfile', 'userDataDir', 'diskCacheDir', 'forcedExtensions', 'updateService')
        @($Apps.office.probes.id) | Should -Be @('updateChannel', 'updateUrl', 'policyUpdatePath', 'policyUpdateBranch', 'hideUpdateNotifications', 'hideEnableDisableUpdates', 'updateTask',
            'perUserCatalog', 'outlookAddins', 'outlookAddinsWow', 'version', 'platform', 'updatesEnabled')
        @($Apps.teams.probes.id) | Should -Be @('version', 'disableAutoUpdate', 'disableFallback', 'maxFps', 'meetingAddin', 'classicTeams', 'webview2Version')
        $Apps.edge.installed.kind | Should -Be 'file'; $Apps.edge.installed.path | Should -Be 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
        $Apps.office.installed.kind | Should -Be 'registryKey'; $Apps.office.installed.path | Should -Be 'HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
        $Apps.teams.installed.path | Should -Be 'C:\Program Files\WindowsApps\MSTeams_*_x64__8wekyb3d8bbwe\ms-teams.exe'
        $p = @{}; foreach ($k in 'edge', 'office', 'teams') { foreach ($x in $Apps[$k].probes) { $p["$k.$($x.id)"] = $x } }
        $p['edge.backgroundMode'].path | Should -Be 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; $p['edge.backgroundMode'].name | Should -Be 'BackgroundModeEnabled'
        $p['edge.updateStable'].name | Should -Be 'Update{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}'; $p['edge.forcedExtensions'].read | Should -Be 'valueCount'; $p['edge.updateService'].read | Should -Be 'startMode'
        $p['office.updateTask'].path | Should -Be '\Microsoft\Office\Office Automatic Updates 2.0'; $p['office.outlookAddins'].read | Should -Be 'subKeyCount'
        $p['teams.disableAutoUpdate'].path | Should -Be 'HKLM\SOFTWARE\Microsoft\Teams'; $p['teams.meetingAddin'].read | Should -Be 'exists'
        @($p.Keys | Where-Object { $p[$_].names } | Sort-Object) | Should -Be @('edge.diskCacheDir', 'edge.userDataDir', 'office.policyUpdatePath', 'office.updateUrl')
        @($p.Keys | Where-Object { -not $p[$_].documented } | Sort-Object) | Should -Be @('edge.updateService', 'office.platform', 'office.updatesEnabled', 'office.version')
        foreach ($k in $p.Keys) { $p[$k].label | Should -Not -Be $p[$k].id -Because $k }                         # jede Probe hat eine Bezeichnung
        foreach ($k in 'edge', 'office', 'teams') { @($Apps[$k].processes).Count | Should -BeGreaterThan 0 -Because $k }
        @($Apps.Keys | Where-Object { $Apps[$_].installed } | Sort-Object) | Should -Be @('edge', 'office', 'teams')      # die weiteren Anwendungen der Datei liest das Zustandsbild nicht
        (Get-Content $AppFile -Raw) | Should -Not -Match 'HKCU|HKEY_CURRENT_USER|HKEY_USERS'                    # nichts je Benutzer
    }
    It 'liefert den Tests eine Liste mit einer vierten, erfundenen Anwendung' {
        $t = @(Read-WorkerPerfHealthApps (New-TestAppFile $TestDrive)); $t[-1].key | Should -Be 'simapp'; $t[-1].label | Should -Be 'Sim-Fachanwendung'
        @($t[-1].probes.id) | Should -Be @('version', 'cacheMode', 'dataPath'); $t[-1].probes[2].names | Should -BeTrue; $t.Count | Should -Be (@(Read-WorkerPerfHealthApps $AppFile).Count + 1)
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Common.Tests.ps1`
Expected: FAIL, die Anwendungen haben keine Proben bzw. `New-TestAppFile` ist nicht definiert

- [ ] **Step 3: `installed` und `probes` der drei Anwendungen nach den Tabellen in `src/apps.json` eintragen; `New-TestAppFile` anlegen; die acht Felder in `tests/MaskCensus.json` einordnen** (ohne die acht Zeilen meldet der bestehende Test „ordnet jedes Textfeld der Berichtsdaten im Bestand tests/MaskCensus.json ein" in `tests/Mask.Tests.ps1` jedes neue Feld mit `neues Textfeld appList.apps[]… : in tests/MaskCensus.json einordnen`; er ist der Test für diesen Teil)

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0` (die Tests des geführten Berichts zu `app.<key>` und zu `appList` bleiben grün: `key`, `label`, `processes` sind unverändert, und `Read-WorkerPerfApps` lässt die zwei neuen Felder stehen)

- [ ] **Step 5: Commit**

```bash
git add src/apps.json tests/TestHelpers.ps1 tests/MaskCensus.json tests/Common.Tests.ps1
git commit -m "Describe the probes of Edge, Office and Teams in the application list"
```

---

### Task 3: Simuliertes Zustandsbild

**Files:**
- Modify: `src/WorkerPerf.Sources.Simulation.ps1` (`Initialize-WorkerPerfSource`; neue Funktion hinter `Get-WorkerPerfPrintQueues`)
- Test: `tests/Simulation.Tests.ps1`
- Mit dem geführten Bericht geteilt: keine. Nicht anfassen: `src/Start-WorkerPerfCapture.ps1` (Task 8), die Szenen und der Rückblick der Simulation.

**Interfaces:**
- Consumes: Tasks 1a, 1b und 2; `Test-WorkerPerfSimMeasured`, `Add-WorkerPerfSimRead`, `$script:WorkerPerfSimStart`, `$script:WorkerPerfSimNow`, `$script:WorkerPerfSimSessions`, `$script:WorkerPerfSimDomain`, `$script:WorkerPerfSimServices` (PID → Dienstnamen, mit `;` getrennt), `Get-WorkerPerfEventReadLogs` über den Ereigniskatalog, den `Initialize-WorkerPerfSource` liest (er wird dafür in einer Skriptvariablen aufbewahrt).
- Produces:
  - `Initialize-WorkerPerfSource … [-Apps <object[]>]`: die Anwendungsliste (`Read-WorkerPerfHealthApps`) für den Bereich `apps`; ohne den Parameter ist sie leer. Der Aufruf setzt auch `$script:WorkerPerfSimAppState` neu: der Stand der Anwendungen auf dem simulierten Worker, `@{ Values (Registrierungspfad mit `HKLM\` + '|' + Wertname → Wert); Keys (Pfad → @{ ValueCount; SubKeyCount }); Services (Dienstname → @{ State; StartMode; DisplayName }); Tasks (Pfad → @{ Enabled; LastRun; NextRun }); Files (Pfad → Version, `''` für einen Ordner) }` mit dem Inhalt des Drehbuchs. Ein Schlüssel, unter dem `Values` einen Wert nennt, gilt als vorhanden; ein Dateipfad mit `*` trifft über `-like` (bei mehreren Treffern die höchste Version).
  - `Get-WorkerPerfHealth -> ordered | $null`: `$null` ohne Lesezählung, wenn `Zustand` weggelassen ist; sonst zählt es `Add-WorkerPerfSimRead 'health'` und liefert `New-WorkerPerfHealth $script:WorkerPerfSimNow 0 <Bereiche>` mit dem Drehbuch unten (jeder Bereich über `Complete-WorkerPerfHealthArea` mit der Dauer 0). Der Bereich `apps` entsteht über `Get-WorkerPerfAppRows` mit fünf Lesern auf `$script:WorkerPerfSimAppState`: die Simulation kennt keine Anwendung beim Namen, eine Anwendung der Liste, die der Stand nicht kennt, ist nicht installiert.

**Drehbuch des simulierten Zustandsbilds** (`s` = `$script:WorkerPerfSimStart`; die Tabelle nennt jeden der 103 Werte ohne das Präfix seines Bereichs; ein Wert ist `read` mit dem genannten Inhalt, wo kein anderer Zustand dasteht; Zeitpunkte über `ConvertTo-WorkerPerfHealthTime`):

| Bereich | Werte |
|---|---|
| `size` | `cpuLogical` 8, `cpuSockets` 2, `memTotalMB` 65536, `commitTotalMB` 38000, `commitLimitMB` 98304, `commitPeakMB` 61000, `pagefiles` eine Datei (`C:\pagefile.sys`, 32768, 5200, nicht temporär), `pagefileManaged` falsch, `hypervisor` wahr, `model` „VMware, Inc. VMware7,1", `vmtoolsPresent` wahr, `vmtoolsService` `Running`, `vmtoolsVersion` „12.3.5", `netAdapters` ein Adapter („vmxnet3 Ethernet Adapter", `vmxnet3ndis6`, 10000, wahr), `storageControllers` einer („VMware PVSCSI Controller", `pvscsi`), `balloonDriver` `Running` |
| `operation` | `lastBoot` s − 3 Tage, `pendingRename` **2**, `pendingServicing` falsch, `pendingUpdate` falsch, `lastUpdate` s − 20 Tage, `lastUpdateId` „KB5099999", `powerPlan` `highPerformance`, `volumes` `C:` (100, 38, NTFS, System, PageFile) und `D:` (200, 150, NTFS) |
| `sessions` | `list`: Sitzung 0 (`Disconnected`, `Services`, ohne Benutzer) und die 25 Sitzungen aus `$script:WorkerPerfSimSessions` (`Active`, Benutzer, Domäne `CONTOSO`, Client, WinStation, `LogonTime` wie im Schnappschuss, `ConnectTime` = `LogonTime`, `DisconnectTime` 0, `IdleMinutes` 0); `limits`: `ICA-CGP` und `RDP-Tcp` mit `DisconnectedLimitMin` 240, `IdleLimitMin` 180, `ActiveLimitMin` 0, `FromPolicy` wahr; `localProfiles`: `C:\Users\user001` … `C:\Users\user025` (geladen, `LastUse` s), `C:\Users\user026` (nicht geladen, `LastUse` s − 10 Tage) und `C:\Users\Administrator` (nicht geladen, `LastUse` s − 40 Tage), keines `Special`, keines temporär |
| `vda` | `version` „2203.0.4000", `services`: `BrokerAgent`, `PorticaService`, `CitrixHealthMon`, `ctxProfile`, `CpSvc` (`Running`, `Auto`), `desktopService` `Running`, `controllers`: `ddc01.sim.local`, `ddc02.sim.local` (`fqdn`, `policy`), `listOfSids` falsch, `farmGuid` falsch, `policyRaw`: (`ICAPolicies`, `SimSitzungslimit`, „1") und (`ICAPolicies`, `SimDruckerzuweisung`, `\\prn01\Etage2`), `persistentDataLocation` `D:\PersistentData`, `wemService` `Running`, `wemServices`: „Citrix WEM Agent Host Service", „Citrix WEM User Logon Service", „System Event Notification Service" (je `Running`, `Auto`), `wemVersion` „2407.1.0.1", `wemServer` `wem01.sim.local`, `wemCacheLocation` `D:\WEMCache`, `wemGpNetworkTimeout` 120, `teamsService` `Running`, `webSocketService` `Running` |
| `profile` | `service` `Running`, `version` „2203.0.4000", `policyGpo`: (``, `ServiceActive`, „1") und (``, `PathToUserStore`, `\\fs01\profile$\%USERNAME%.%USERDOMAIN%`), `policyStudio` leer, `containers`: je Sitzung einer (`Location` `\\fs01\profile$\<user>.CONTOSO\Win2022\ProfileContainer.vhdx`, `Mount` `C:\Users\<user>_UPM_local\UpmTempMount`, `Owner` der Benutzer, `SessionId` die Sitzung, `SizeGB` 50, `AllocatedGB` 20, `VolumeSizeGB` 50, `VolumeFreeGB` 30, `UsedPct` 40); der Container von `user009` hat `AllocatedGB` 48, `VolumeFreeGB` 2, `UsedPct` **96** |
| `print` | `isolationExecution` und `isolationOverride` `absent` ohne Grund, `queueCount` 2, `spooler` `Running`, `spoolerStartMode` `Auto`, `citrixPrintService` `Running`, `operationalLog` falsch, `mappingClientVersion` „6.4.1" |
| `security` | `services`: je Dienstname aus `$script:WorkerPerfSimServices` (an `;` geteilt, in der Reihenfolge der PIDs) ein Eintrag (`Running`, `Auto`; nur `wuauserv` ist `Stopped`, `Disabled`, passend zu `maintenance.updateService`) und dazu `Sense` (`Running`, `Manual`), `W32Time`, `VMTools` und `CpSvc` (`Running`, `Auto`; der Dienst hinter `print.citrixPrintService`); `defenderService` `Running`, `defenderMode` `Normal`, `defenderRealTime` wahr, `defenderTamper` wahr, `defenderSignatureAgeDays` 1, `defenderSignaturesOutOfDate` falsch, `defenderVersion` „4.18.24090.11"; `defenderExclusionPaths`, `defenderExclusionProcesses`, `defenderExclusionExtensions` **`unreadable` mit `rights`**; `defenderSharedSignatures` `\\fs01\defsig$`, `defenderNetworkProtection` 0, `defenderForcePassive` `absent` ohne Grund; `mdeOnboarding` 1, `mdeService` `Running`; `filters`: (`WdFilter`, „328010", 4), (`upmjit`, „182400", 26), (`FileInfo`, „45000", 5), keiner `Legacy`; `applockerService` `Running`; `applockerCollections`: (`Exe`, 1, 12), (`Msi`, 1, 4), (`Script`, 1, 6) |
| `network` | `domainMember` wahr, `smbRequireSigning` falsch, `smbDirectoryCache` 16, `smbFileInfoCache` 64, `smbFileNotFoundCache` 128, `smb1` `absent` ohne Grund, `smbConnections`: (`\\fs01\daten`, „3.1.1", signiert, nicht verschlüsselt, 25) und (`\\fs01\profile$`, „3.1.1", signiert, nicht verschlüsselt, 25), `dnsServers`: Schnittstelle 4 mit `10.20.0.10`, `10.20.0.11`, `fd00:20::10`, `rss`: („vmxnet3 Ethernet Adapter", wahr), `timeType` `NT5DS`, `timeServers` „zeit01.sim.local 10.20.0.20", `timeService` `Running` |
| `events` | `logs`: je Name der Protokolle aus `Get-WorkerPerfEventReadLogs` (acht Namen) ein Eintrag mit `Present` wahr, `Enabled` wahr, `MaxSizeMB` 20, `FileSizeMB` 12, `Records` 30000, `Mode` `Circular`, `Full` falsch, `Oldest` s − 30 Tage |
| `maintenance` | `tasks`: (`\Sim\Inventarlauf`, eingeschaltet, `Ready`, `NextRun` = der nächste Tag nach s um 10:00 Ortszeit, der kein Samstag oder Sonntag ist, `LastRun` s − 22 Stunden, `daily`, 0, `C:\Tools\inventar.exe`) und (`\Sim\Nachtsicherung`, eingeschaltet, `Ready`, `NextRun` = der Tag nach s um 02:00, `LastRun` s − 6 Stunden, `daily`, 0, `C:\Tools\sicherung.cmd`); `taskCount` 162; `scanDay` 0, `scanTime` „02:00", `quickScanTime` „02:00", `scanType` 1, `scanRandomize` wahr, `scanCpuLoad` 50; `updateOptions`, `updateDay`, `updateHour`, `updateNoRebootWithUsers` `absent` ohne Grund; `searchService` `absent` mit `notInstalled`; `updateService` `Disabled` |
| `apps` | `probes`: die Zeilen aus `Get-WorkerPerfAppRows` für die übergebene Anwendungsliste gegen den Stand der nächsten Tabelle |

**Stand der Anwendungen auf dem simulierten Worker** (`$script:WorkerPerfSimAppState`; was hier nicht steht, gibt es nicht):

| Teil | Inhalt |
|---|---|
| `Files` | `C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe` → „130.0.2849.80"; `C:\Program Files\WindowsApps\MSTeams_24277.3502.3161.3007_x64__8wekyb3d8bbwe\ms-teams.exe` → „24277.3502.3161.3007"; `C:\Program Files (x86)\Microsoft\TeamsMeetingAdd-in` → `''` |
| `Values` | `HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}`: `pv` „130.0.2849.80"; `HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate`: `UpdateDefault` 0; `HKLM\SOFTWARE\Policies\Microsoft\Edge`: `StartupBoostEnabled` 0, `BackgroundModeEnabled` **1**; `HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration`: `UpdateChannel` „http://officecdn.microsoft.com/pr/00000000-0000-0000-0000-000000000000", `UpdateUrl` `\\fs01\office$\updates`, `VersionToReport` „16.0.17932.20162", `Platform` „x64", `UpdatesEnabled` „False"; `HKLM\SOFTWARE\Policies\Microsoft\office\16.0\Common\officeupdate`: `hideupdatenotifications` 1, `hideenabledisableupdates` 1; `HKLM\SOFTWARE\Microsoft\Teams`: `DisableFallback` 2 (**kein** `disableAutoUpdate`) |
| `Keys` | `HKLM\SOFTWARE\Microsoft\Office\Outlook\Addins`: 0 Werte, 3 Unterschlüssel |
| `Services` | `edgeupdate` (`Stopped`, `Manual`, „Microsoft Edge Update Service (edgeupdate)") |
| `Tasks` | `\Microsoft\Office\Office Automatic Updates 2.0` (nicht eingeschaltet, kein letzter und kein nächster Lauf) |

Damit ist auf dem simulierten Worker Edge installiert mit einem auffälligen Wert (Hintergrundmodus an), Teams installiert mit einem auffälligen Wert (automatische Aktualisierung nicht abgeschaltet), Office installiert und in Ordnung, und die vierte Anwendung der Testliste nicht installiert.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/Simulation.Tests.ps1`, neuer Block; außerdem im Block der Lesezählung: `Invoke-SimReads` ruft zusätzlich `Get-WorkerPerfHealth`, `$ReadKeys` erhält `Zustand = @('health')`, die Liste von `-ForEach` und die Liste „ohne alle Kategorien" erhalten `'Zustand'`)

```powershell
Describe 'Simuliertes Zustandsbild' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1'); $script:TestApps = @(Read-WorkerPerfHealthApps (New-TestAppFile $TestDrive))
        [void](Initialize-WorkerPerfSource -StartTime $Start -Apps $TestApps); $script:H = Get-WorkerPerfHealth
        function Get-V([string]$Id) { $H.Areas[$WorkerPerfHealthValues[$Id].Area].Values[$Id] }
        function Get-Row([string]$App, [string]$Id) { (Get-V 'apps.probes').Value | Where-Object { $_.App -eq $App -and $_.Id -eq $Id } }
    }
    AfterAll { [void](Initialize-WorkerPerfSource -StartTime $Start) }
    It 'liefert elf Bereiche mit jedem Wert der Liste und der Dauer 0' {
        $H.FormatVersion | Should -Be 1; $H.DurationMs | Should -Be 0; @($H.Areas.Keys) | Should -Be $WorkerPerfHealthAreas
        foreach ($id in $WorkerPerfHealthValues.Keys) { $H.Areas[$WorkerPerfHealthValues[$id].Area].Values.Contains($id) | Should -BeTrue -Because $id }
        @($H.Areas.Keys | Where-Object { $H.Areas[$_].Status -ne 'read' }) | Should -Be @('security'); $H.Areas['security'].Status | Should -Be 'partial'
        ($H | ConvertTo-Json -Depth 10 | ConvertFrom-Json).Areas.profile.Values.'profile.containers'.Value.Count | Should -Be 25
    }
    It 'traegt die auffaelligen Werte des Drehbuchs' {
        (Get-V 'operation.pendingRename').Value | Should -Be 2; (Get-V 'operation.pendingServicing').Value | Should -BeFalse
        $full = @((Get-V 'profile.containers').Value | Where-Object { $_.UsedPct -ge 95 }); $full.Count | Should -Be 1; $full[0].Owner | Should -Be 'user009'; $full[0].UsedPct | Should -Be 96
        (Get-V 'security.defenderExclusionPaths').State | Should -Be 'unreadable'; (Get-V 'security.defenderExclusionPaths').Reason | Should -Be 'rights'
        $task = (Get-V 'maintenance.tasks').Value | Where-Object Path -eq '\Sim\Inventarlauf'
        $next = [DateTimeOffset]::FromUnixTimeMilliseconds($task.NextRun).LocalDateTime; $next.Hour | Should -Be 10; $next.DayOfWeek | Should -Not -BeIn 'Saturday', 'Sunday'
        (Get-V 'size.memTotalMB').Value | Should -Be 65536; @((Get-V 'sessions.list').Value | Where-Object { $_.User }).Count | Should -Be 25
        @((Get-V 'vda.controllers').Value.Entry) | Should -Be @('ddc01.sim.local', 'ddc02.sim.local')
        @((Get-V 'network.dnsServers').Value.Address) | Should -Be @('10.20.0.10', '10.20.0.11', 'fd00:20::10')
        (Get-V 'maintenance.searchService').State | Should -Be 'absent'; (Get-V 'maintenance.searchService').Reason | Should -Be 'notInstalled'
        (Get-V 'print.isolationExecution').State | Should -Be 'absent'; (Get-V 'print.isolationExecution').Reason | Should -Be ''
        (Get-V 'operation.lastBoot').Value | Should -Be (ConvertTo-WorkerPerfHealthTime $Start.AddDays(-3))
        (Get-V 'network.timeServers').Value | Should -Be 'zeit01.sim.local 10.20.0.20'; (Get-V 'security.defenderSharedSignatures').Value | Should -Be '\\fs01\defsig$'
        @((Get-V 'events.logs').Value).Count | Should -Be 8; @((Get-V 'vda.services').Value.Name) | Should -Be @('BrokerAgent', 'PorticaService', 'CitrixHealthMon', 'ctxProfile', 'CpSvc')
        @((Get-V 'sessions.localProfiles').Value.Path)[-1] | Should -Be 'C:\Users\Administrator'; ((Get-V 'security.services').Value | Where-Object Name -eq 'RpcSs').State | Should -Be 'Running'
        (Get-V 'vda.wemServer').Value | Should -Be 'wem01.sim.local'; (Get-V 'vda.wemCacheLocation').Value | Should -Be 'D:\WEMCache'; @((Get-V 'vda.wemServices').Value).Count | Should -Be 3
        (Get-V 'size.balloonDriver').Value | Should -Be 'Running'; (Get-V 'print.citrixPrintService').Value | Should -Be 'Running'; (Get-V 'maintenance.updateService').Value | Should -Be 'Disabled'
        (Get-V 'network.rss').Value[0].Enabled | Should -BeTrue; ((Get-V 'sessions.limits').Value | Select-Object -First 1).IdleLimitMin | Should -Be 180
        (Get-V 'operation.powerPlan').Value | Should -Be 'highPerformance'; (Get-V 'print.mappingClientVersion').Value | Should -Be '6.4.1'
        $wu = (Get-V 'security.services').Value | Where-Object Name -eq 'wuauserv'; $wu.State | Should -Be 'Stopped'; $wu.StartMode | Should -Be 'Disabled'      # das Drehbuch widerspricht sich nicht
        ((Get-V 'security.services').Value | Where-Object Name -eq 'CpSvc').State | Should -Be 'Running'
    }
    It 'liest die Anwendungen der Liste: zwei auffaellig, eine in Ordnung, eine nicht installiert' {   # Review Focus 3
        $rows = @((Get-V 'apps.probes').Value); $rows.Count | Should -Be 42                                    # 16 Edge, 14 Office, 8 Teams, 4 simapp
        foreach ($k in 'edge', 'office', 'teams') { (Get-Row $k 'installed').Value | Should -BeTrue -Because $k }
        (Get-Row 'edge' 'backgroundMode').Value | Should -Be 1; (Get-Row 'edge' 'version').Value | Should -Be '130.0.2849.80'; (Get-Row 'edge' 'updateDefault').Value | Should -Be 0
        (Get-Row 'edge' 'userDataDir').State | Should -Be 'absent'; (Get-Row 'edge' 'userDataDir').Reason | Should -Be ''; (Get-Row 'edge' 'updateService').Value | Should -Be 'Manual'
        (Get-Row 'teams' 'disableAutoUpdate').State | Should -Be 'absent'; (Get-Row 'teams' 'disableFallback').Value | Should -Be 2
        (Get-Row 'teams' 'version').Value | Should -Be '24277.3502.3161.3007'; (Get-Row 'teams' 'meetingAddin').Value | Should -BeTrue; (Get-Row 'teams' 'classicTeams').Value | Should -BeFalse
        (Get-Row 'office' 'hideEnableDisableUpdates').Value | Should -Be 1; (Get-Row 'office' 'updateTask').Value | Should -BeFalse; (Get-Row 'office' 'outlookAddins').Value | Should -Be 3
        (Get-Row 'office' 'outlookAddinsWow').State | Should -Be 'absent'; (Get-Row 'office' 'updateUrl').Names | Should -Be '\\fs01\office$\updates'; (Get-Row 'office' 'updateUrl').Value | Should -BeNullOrEmpty
        (Get-Row 'simapp' 'installed').Value | Should -BeFalse
        foreach ($id in 'version', 'cacheMode', 'dataPath') { (Get-Row 'simapp' $id).State | Should -Be 'absent' -Because $id; (Get-Row 'simapp' $id).Reason | Should -Be 'notInstalled' -Because $id }
        $H.Areas['apps'].Status | Should -Be 'read'
        # ohne Anwendungsliste: der Bereich ist gelesen und leer
        [void](Initialize-WorkerPerfSource -StartTime $Start); @((Get-WorkerPerfHealth).Areas['apps'].Values['apps.probes'].Value).Count | Should -Be 0
    }
    It 'liest ohne Zustand nichts' {
        [void](Initialize-WorkerPerfSource -StartTime $Start -Skip Zustand); Get-WorkerPerfHealth | Should -BeNullOrEmpty; [int]$script:WorkerPerfSimReads['health'] | Should -Be 0
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Simulation.Tests.ps1`
Expected: FAIL, `Get-WorkerPerfHealth` ist nicht definiert

- [ ] **Step 3: `-Apps`, den Stand der Anwendungen und `Get-WorkerPerfHealth` der Simulation nach den zwei Tabellen umsetzen**

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Sources.Simulation.ps1 tests/Simulation.Tests.ps1
git commit -m "Simulate a health picture with conspicuous values and three applications"
```

---

### Task 4: Windows – Gerüst mit Zeitlimit, Platzhalter, Bereiche Größe, Betrieb, Ereignisbild

**Files:**
- Modify: `src/WorkerPerf.Sources.Windows.ps1`, `tests/WindowsStandIns.ps1`
- Create: `tests/WindowsHealth.Tests.ps1`
- Mit dem geführten Bericht geteilt: keine. Nicht anfassen: `src/Test-WorkerPerfSources.ps1`, `src/Start-WorkerPerfCapture.ps1`.

**Interfaces:**
- Consumes: Task 1a; `$script:WinState`, `Test-WorkerPerfWinMeasured`, `Get-WorkerPerfNow`, `Open-WorkerPerfRegistryKey`, `Get-WorkerPerfErrorClass`, `Get-WorkerPerfErrorText`, `Get-WorkerPerfField`, `Get-WinEvent -ListLog` wie in `Initialize-WorkerPerfSource`, `Get-WorkerPerfEventReadLogs` (die Protokolle des Katalogs mit ihren Namen).
- Produces (`src/WorkerPerf.Sources.Windows.ps1`):
  - `Initialize-WorkerPerfSource` bewahrt im Zustand auf: `ComputerSystem`, `OperatingSystem` (die zwei gelesenen CIM-Objekte) und `LogInfo` (Protokollname → das Objekt von `Get-WinEvent -ListLog`, soweit es dort geholt wird) und `Apps` (die Anwendungsliste aus dem neuen Parameter `-Apps <object[]>`, wie `Read-WorkerPerfHealthApps` sie liefert; Vorgabe leer). Sonst ändert sich an ihr nichts.
  - `$script:WorkerPerfWinHealthAreaBudgetSec = 10`, `$script:WorkerPerfWinHealthTotalBudgetSec = 60`.
  - `$script:WorkerPerfWinHealthReaders`: geordnet, Bereich → Name der Leserfunktion; in dieser Task `size`, `operation`, `events` (Tasks 5, 6 und 7 tragen die übrigen ein).
  - `Get-WorkerPerfHealth -> ordered | $null`: `$null` ohne einen Windows-Aufruf, wenn `Zustand` weggelassen ist. Sonst je Bereich in der Reihenfolge von `$script:WorkerPerfHealthAreas`: ist das Gesamtlimit erreicht, `Complete-WorkerPerfHealthArea <id> @{} 0 'budget' $true`; hat der Bereich keinen Leser, `… 'noReader'`; sonst ein Kontext `@{ Area; State; Clock (laufende Stoppuhr); BudgetMs (das kleinere aus Bereichslimit und Rest des Gesamtlimits); Shared (eine Tabelle für den ganzen Aufruf); Values ([ordered]) }`, der Leser in `try`/`catch` (eine Ausnahme des Lesers wird zum `ErrorText`, die schon gesetzten Werte bleiben; `PipelineStoppedException` geht weiter), danach `Complete-WorkerPerfHealthArea` mit der Stoppuhrzeit und `TimedOut`, wenn das Limit des Bereichs erreicht ist. Ergebnis: `New-WorkerPerfHealth (Get-WorkerPerfNow) <gesamte Stoppuhrzeit> <Bereiche>`.
  - `Set-WorkerPerfWinHealthValue($Ctx, [string]$Id, [scriptblock]$Read)`: ist das Limit des Bereichs erreicht, wird der Wert `unreadable`/`timeout` und `$Read` nicht ausgeführt. Sonst wird alles, was `$Read` liefert, mit `@(…)` aufgefangen. Ein Wertsatz ist nur ein einzelnes Ergebnis, das ein geordnetes Wörterbuch mit genau den Schlüsseln `State`, `Reason`, `Value` ist (es stammt von `New-WorkerPerfHealthValue`; ein Listeneintrag mit einem Feld `State` ist keiner); er wird unverändert übernommen. Sonst entscheidet der Typ des Werts in `$script:WorkerPerfHealthValues`: bei `list` ist der Wert `read` mit allen Ergebnissen als Array (kein Ergebnis = leere Liste, ein Ergebnis = Liste mit einem Eintrag); bei jedem anderen Typ ist kein Ergebnis `absent` ohne Grund und ein Ergebnis `read`. Eine Ausnahme → `unreadable` mit dem Grund aus `Get-WorkerPerfWinHealthFailReason($Ctx, $ErrorRecord) -> 'rights' | 'timeout' | 'error'` (eine eigene Funktion, weil der Leser der Anwendungen in Task 7 sie ebenfalls braucht): `rights`, wenn die Ausnahme ohne die Hüllen von PowerShell (wie in `Get-WorkerPerfErrorClass`) eine `UnauthorizedAccessException` oder `SecurityException` ist, das HRESULT `0x80070005` oder `0x80041003` trägt, eine Eigenschaft `NativeErrorCode` mit dem Text `AccessDenied` hat (so meldet `Get-CimInstance` verweigerten Zugriff: `CimException`) oder eine `Win32Exception` mit `NativeErrorCode` 5 ist; sonst mit `timeout`, wenn das Limit danach erreicht ist; sonst `error`. Für eine Ausnahme, die `Get-WorkerPerfWinHealthShared` aus einem früheren Bereich weiterreicht, liefert sie den dort gemerkten Grund.
  - `Get-WorkerPerfWinHealthCim($Ctx, [string]$ClassName, [string]$Namespace = 'root\cimv2', [string]$Filter = '', [string[]]$Property = @()) -> object[]`: `Get-CimInstance … -OperationTimeoutSec <Rest des Limits in ganzen Sekunden, mindestens 1> -ErrorAction Stop`.
  - `Get-WorkerPerfWinHealthShared($Ctx, [string]$Key, [scriptblock]$Read)`: führt `$Read` je Aufruf von `Get-WorkerPerfHealth` einmal aus und gibt jedem weiteren Aufrufer dasselbe Ergebnis. Wirft `$Read`, merkt sie sich die Ausnahme, deren Grund (`Get-WorkerPerfWinHealthFailReason` im Bereich, in dem sie fiel) und diesen Bereich, und wirft sie weiter. Ein späterer Aufrufer im selben Bereich bekommt dieselbe Ausnahme. Ein Aufrufer in einem anderen Bereich bekommt sie ebenfalls, wenn der gemerkte Grund `rights` oder `error` ist; ist er `timeout`, führt sie `$Read` einmal neu aus (der Bereich hat sein eigenes Limit) und merkt sich das neue Ergebnis. So macht ein Aufruf, der im Bereich `size` am Zeitlimit endet, nicht die Dienstwerte aller folgenden Bereiche unlesbar, und fehlende Rechte tragen in jedem Bereich den Grund `rights`.
  - `Get-WorkerPerfWinHealthLog($Ctx, [string]$Name) -> object | $null`: das Objekt von `Get-WinEvent -ListLog` für ein Protokoll: das beim Initialisieren aufbewahrte (`LogInfo`), sonst jetzt gelesen (`-ErrorAction Stop`). `$null` nur, wenn es das Protokoll nicht gibt: die Kennung des Fehlers (`FullyQualifiedErrorId`) beginnt mit `NoMatchingLogsFound`, oder die Ausnahme ist eine `EventLogNotFoundException`. Jeder andere Fehler geht weiter und wird in `Set-WorkerPerfWinHealthValue` zu `unreadable`. Der Leser des Ereignisbilds (diese Task) und der Leser des Bereichs Drucken (Task 6, `print.operationalLog`) fragen ein Protokoll nur über diese Funktion ab.
  - Dünne Windows-Aufrufe, jeder mit einem Platzhalter: `Get-WorkerPerfRegistryValues([string]$SubKey) -> $null | @{ Values = [ordered] Name → Wert; SubKeys = string[] }` (unter `HKLM`, nur lesend, über `Open-WorkerPerfRegistryKey`; `$null`, wenn der Schlüssel fehlt); `Get-WorkerPerfPerformanceInfo -> @{ CommitTotalMB; CommitLimitMB; CommitPeakMB }`; `Get-WorkerPerfActivePowerScheme -> string` (GUID in Kleinbuchstaben); `Get-WorkerPerfLogOldestTime([string]$LogName) -> datetime | $null`.
  - `$script:WorkerPerfHealthNativeSource` (C# 5) mit der Klasse `WorkerPerf.HealthNative` und ihren öffentlichen Methoden `GetCommit() -> long[]` (zugesagt, Grenze, Höchststand in Byte, aus `GetPerformanceInfo`) und `GetActivePowerScheme() -> Guid` (`PowerGetActiveScheme` mit `LocalFree`); ein gescheiterter Aufruf wirft eine `Win32Exception` mit dem Fehlercode. `Register-WorkerPerfHealthType` übersetzt die Klasse einmal je Prozess (`'WorkerPerf.HealthNative' -as [type]`), beim ersten Gebrauch; scheitert das Übersetzen, sind die Werte, die es brauchen, `unreadable`/`error`.
  - `ConvertTo-WorkerPerfLogInfo($Info) -> [ordered]@{ Enabled; MaxSizeMB; FileSizeMB; Records; Mode; Full }` (rein; aus dem Objekt von `Get-WinEvent -ListLog`; `Mode` ist `[string]$Info.LogMode`, der Name der Aufzählung und nicht ihre Zahl; ein Feld, das dem Objekt fehlt, ist `$null`).
  - Leser `Read-WorkerPerfWinHealthSize`, `Read-WorkerPerfWinHealthOperation`, `Read-WorkerPerfWinHealthEvents` (Parameter `$Ctx`), die jeden Wert ihres Bereichs in der Reihenfolge der Tabelle über `Set-WorkerPerfWinHealthValue` setzen. Jeder gespeicherte Wert ist eine Zahl, ein Wahrheitswert, ein Text oder eine Liste geordneter Wörterbücher daraus: eine Aufzählung wird zu ihrem Namen, ein Zeitpunkt über `ConvertTo-WorkerPerfHealthTime` zur Zahl, eine Tageszeit zu `HH:mm` (`ConvertTo-Json` schriebe eine Aufzählung als Zahl). `operation.volumes` liest zuerst `Win32_LogicalDisk` und fragt erst danach `Shared['pagefiles']`; scheitert die gemeinsame Abfrage, bleibt der Wert gelesen, und `PageFile` jedes Laufwerks ist `$null`. Gemeinsame Abfragen dieser Bereiche: `Shared['services']` (`Win32_Service` ohne Filter mit `Name`, `DisplayName`, `State`, `StartMode`, `PathName`), `Shared['uninstall']` (Einträge beider Uninstall-Schlüssel mit `DisplayName`, `DisplayVersion`), `Shared['pagefiles']`, `Shared['systemdrivers']` (`Win32_SystemDriver` mit dem Filter `Name = 'vmmemctl' OR Name = 'mrxsmb10'` und den Eigenschaften `Name`, `State`, `StartMode`; jeder Leser wählt seinen Treiber am Namen: `size.balloonDriver` hier, `network.smb1` in Task 6).
- Produces (`tests/WindowsStandIns.ps1`): `$script:WinFake` erhält `Registry` (Unterschlüssel → geordnete Tabelle Name → Wert, ohne Rücksicht auf Groß- und Kleinschreibung; `SubKeys` eines Schlüssels bildet der Platzhalter aus den Schlüsseln von `Registry`, die direkt unter ihm liegen), `RegistryFail` und `CimFail` (Schlüssel bzw. Klasse → Ausnahme, die der Platzhalter wirft), `Cim` (Klasse → Objekte), `Delay` (Aufrufschlüssel → Millisekunden: jeder Platzhalter, der einen Aufruf zählt, wartet davor so lange; `Add-WinStandInCall` erledigt das für alle Schlüssel außer `cim:…`, bei denen `Get-CimInstance` selbst wartet, siehe unten), `DelayOnce` (wie `Delay`, gilt aber nur für den nächsten Aufruf mit diesem Schlüssel; der Platzhalter entfernt den Eintrag, sobald er gewartet hat), `Services`, `PerformanceInfo`, `PowerScheme`, `LogInfo`, `LogOldest`, `LogFail` (Protokollname → Ausnahme, die `Get-WinEvent -ListLog` für ihn wirft). `New-WinStandInDenied([string]$Kind) -> Exception` liefert verweigerten Zugriff in der Form, in der Windows ihn meldet: `cim` eine Ausnahme der Testklasse `WinStandInCimException` mit der Eigenschaft `NativeErrorCode` = `AccessDenied`, `win32` eine `System.ComponentModel.Win32Exception` mit dem Code 5. Platzhalter: `Get-WorkerPerfRegistryValues` (Zähler `registry:<Unterschlüssel>`), `Get-WorkerPerfPerformanceInfo` (`native:perfinfo`), `Get-WorkerPerfActivePowerScheme` (`native:power`), `Get-WorkerPerfLogOldestTime` (`winevent:oldest`); `Get-CimInstance` wartet `Delay['cim:<Klasse>']` bzw. `DelayOnce['cim:<Klasse>']`, aber höchstens `-OperationTimeoutSec` Sekunden, und wirft dann eine `System.TimeoutException` (das Zeitlimit eines CIM-Aufrufs greift so wie unter Windows); danach wirft er `CimFail[<Klasse>]`, wenn gesetzt; er liefert `Win32_Service` ohne Filter aus `Services` (jeder Dienst dort trägt alle sechs Eigenschaften `Name`, `DisplayName`, `State`, `StartMode`, `PathName`, `ProcessId`, auch wenn eine leer ist: die Leser laufen unter `Set-StrictMode -Version 2`, und der Zugriff auf eine fehlende Eigenschaft wirft) und mit dem Filter `ProcessId > 0` (der bisherige Aufruf von `Get-WorkerPerfServices`) wie bisher genau `RpcSs` und `Spooler`, ergänzt `Win32_ComputerSystem` und `Win32_OperatingSystem` um die Eigenschaften der Wertetabellen und nimmt jede andere Klasse aus `Cim` (fehlt sie dort, wirft er wie bisher); `Get-WinEvent -ListLog` liefert zusätzlich `MaximumSizeInBytes`, `FileSize`, `RecordCount`, `LogMode`, `IsLogFull` aus `LogInfo`; `LogMode` ist ein Wert der Testaufzählung `WinStandInLogMode` (`Circular`, `AutoBackup`, `Retain`), weil Windows hier eine Aufzählung liefert. Ein fehlendes Protokoll meldet er mit der Fehlerkennung `NoMatchingLogsFound` (Meldung wie bisher), ein Protokoll in `LogFail` mit dessen Ausnahme.

Vorgaben der Platzhalter nach `Reset-WinStandIns` (erfundene Werte, auf die sich die Tests stützen):

| Platzhalter | Vorgabe |
|---|---|
| `Win32_ComputerSystem` | zusätzlich `NumberOfProcessors` 2, `AutomaticManagedPagefile` falsch, `HypervisorPresent` wahr, `Manufacturer` „VMware, Inc.", `Model` „VMware7,1", `PartOfDomain` wahr |
| `Win32_OperatingSystem` | zusätzlich `LastBootUpTime` jetzt − 2 Tage, `SystemDrive` „C:" |
| `PerformanceInfo` | `CommitTotalMB` 36864, `CommitLimitMB` 81920, `CommitPeakMB` 60000 |
| `PowerScheme` | `381b4222-f694-41f0-9685-ff5bb260df2e` |
| `Cim['Win32_PageFileUsage']` | (`C:\pagefile.sys`, `AllocatedBaseSize` 16384, `PeakUsage` 2100, `TempPageFile` falsch) |
| `Cim['Win32_NetworkAdapter']` | („vmxnet3 Ethernet Adapter", `ServiceName` `vmxnet3ndis6`, `Speed` 10000000000, `NetEnabled` wahr) |
| `Cim['Win32_SCSIController']` | („VMware PVSCSI Controller", `DriverName` `pvscsi`) |
| `Cim['Win32_SystemDriver']` | (`vmmemctl`, `State` `Running`, `StartMode` `System`); der Platzhalter liefert die Liste ohne Rücksicht auf den Filter |
| `Cim['Win32_QuickFixEngineering']` | (`KB5000001`, `InstalledOn` `[datetime]'2026-09-10'`) und (`KB5000002`, `[datetime]'2026-10-14'`) |
| `Cim['Win32_LogicalDisk']` | (`C:`, 100 GB, 8 GB frei, NTFS) und (`D:`, 200 GB, 150 GB frei, NTFS), Größen in Byte |
| `Services` | `RpcSs` (900), `Spooler` (0) wie bisher, dazu `State`/`StartMode` `Running`/`Auto`; weiter `VMTools`, `WinDefend`, `Sense`, `AppIDSvc`, `W32Time` (`Running`), `BrokerAgent` (`Running`, `Auto`, `DisplayName` „Citrix Desktop Service", `PathName` `"C:\Program Files\Citrix\Virtual Desktop Agent\BrokerAgent.exe"`), `ctxProfile` (`Running`, `Auto`, `PathName` `"C:\Program Files\Citrix\User Profile Manager\UserProfileManager.exe"`), alle mit `ProcessId` 0. Die zwei Pfade stehen mit ihren Anführungszeichen da: so trägt Windows `PathName` ein, wenn der Pfad Leerzeichen enthält. `DisplayName` ist sonst gleich `Name`, `PathName` sonst `''`; kein `WSearch` |
| `Registry` | `SOFTWARE\VMware, Inc.\VMware Tools` (vorhanden); `SYSTEM\CurrentControlSet\Control\Session Manager` mit `PendingFileRenameOperations` aus vier Einträgen (zwei Paare); `SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired` (vorhanden); `SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall` mit den Unterschlüsseln `{A1}` (`DisplayName` „VMware Tools", `DisplayVersion` „12.3.5.22544099") und `{B2}` (`DisplayName` „Citrix Virtual Apps and Desktops 7 2203 LTSR CU4 - Virtual Delivery Agent", `DisplayVersion` „2203.0.4000.4033") und `{C3}` (`DisplayName` „PrinTaurus SmartSpread Client", `DisplayVersion` „6.2.1"; gelesen ab Task 6) |
| `LogInfo`, `LogOldest` | je vorhandenem Protokoll `MaximumSizeInBytes` 20971520, `FileSize` 12582912, `RecordCount` 30000, `LogMode` `[WinStandInLogMode]::Circular`, `IsLogFull` falsch; ältester Eintrag jetzt − 30 Tage |

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/WindowsHealth.Tests.ps1`)

```powershell
BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.EventConfig.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Sources.Windows.ps1')
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Capture.ps1'); . (Join-Path $PSScriptRoot 'WindowsStandIns.ps1')
    $script:Cfg = Read-WorkerPerfEventConfig (Join-Path $PSScriptRoot '../src/events.json')
    function Read-Health([string[]]$Skip = @(), [object[]]$Apps = @()) { [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg -Skip $Skip -Apps $Apps 3>$null); Get-WorkerPerfHealth 3>$null }
    function Get-V($H, [string]$Id) { $H.Areas[$WorkerPerfHealthValues[$Id].Area].Values[$Id] }
}
Describe 'Zustandsbild unter Windows: Geruest, Groesse, Betrieb, Ereignisbild' {
    BeforeEach { Reset-WinStandIns }
    It 'liest die drei Bereiche mit den Werten der Platzhalter' {
        $h = Read-Health
        @($h.Areas.Keys) | Should -Be $WorkerPerfHealthAreas; $h.FormatVersion | Should -Be 1; $h.DurationMs | Should -BeGreaterOrEqual 0
        foreach ($a in 'size', 'operation', 'events') { $h.Areas[$a].Status | Should -Be 'read' -Because $a }
        (Get-V $h 'size.cpuLogical').Value | Should -Be 6; (Get-V $h 'size.cpuSockets').Value | Should -Be 2; (Get-V $h 'size.memTotalMB').Value | Should -Be 59392
        (Get-V $h 'size.commitPeakMB').Value | Should -Be 60000; (Get-V $h 'size.pagefiles').Value[0].AllocatedMB | Should -Be 16384; (Get-V $h 'size.pagefiles').Value[0].Path | Should -Be 'C:\pagefile.sys'
        ((Get-V $h 'size.pagefiles').Value -is [array]) | Should -BeTrue                                 # eine Datei: trotzdem eine Liste
        (Get-V $h 'size.model').Value | Should -Be 'VMware, Inc. VMware7,1'; (Get-V $h 'size.hypervisor').Value | Should -BeTrue; (Get-V $h 'size.vmtoolsPresent').Value | Should -BeTrue
        (Get-V $h 'size.vmtoolsService').Value | Should -Be 'Running'; (Get-V $h 'size.vmtoolsVersion').Value | Should -Be '12.3.5.22544099'
        (Get-V $h 'size.netAdapters').Value[0].SpeedMbit | Should -Be 10000; (Get-V $h 'size.storageControllers').Value[0].Driver | Should -Be 'pvscsi'; (Get-V $h 'size.balloonDriver').Value | Should -Be 'Running'
        (Get-V $h 'operation.pendingRename').Value | Should -Be 2; (Get-V $h 'operation.pendingUpdate').Value | Should -BeTrue; (Get-V $h 'operation.pendingServicing').Value | Should -BeFalse
        (Get-V $h 'operation.lastUpdateId').Value | Should -Be 'KB5000002'; (Get-V $h 'operation.lastUpdate').Value | Should -Be (ConvertTo-WorkerPerfHealthTime ([datetime]'2026-10-14'))
        (Get-V $h 'operation.powerPlan').Value | Should -Be 'balanced'
        $c = (Get-V $h 'operation.volumes').Value | Where-Object Drive -eq 'C:'; $c.FreeGB | Should -Be 8; $c.SizeGB | Should -Be 100; $c.System | Should -BeTrue; $c.PageFile | Should -BeTrue
        ((Get-V $h 'operation.volumes').Value | Where-Object Drive -eq 'D:').PageFile | Should -BeFalse
        $logs = (Get-V $h 'events.logs').Value; @($logs).Count | Should -Be 8                          # die Protokolle, die der Katalog liest
        $log = $logs | Where-Object Log -eq 'Application'; $log.Present | Should -BeTrue; $log.Enabled | Should -BeTrue; $log.MaxSizeMB | Should -Be 20; $log.FileSizeMB | Should -Be 12; $log.Mode | Should -Be 'Circular'; $log.Mode | Should -BeOfType [string]
        ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - $log.Oldest) / 86400000 | Should -BeGreaterThan 29.9
    }
    It 'laesst die anderen Werte und Bereiche stehen, wenn ein Aufruf scheitert oder haengt' {   # Review Focus 1
        $script:WinFake.CimFail['Win32_LogicalDisk'] = New-WinStandInDenied 'cim'
        $script:WinFake.Delay['cim:Win32_PageFileUsage'] = 5000; $script:WorkerPerfWinHealthAreaBudgetSec = 1
        try { $h = Read-Health } finally { $script:WorkerPerfWinHealthAreaBudgetSec = 10 }
        (Get-V $h 'operation.volumes').State | Should -Be 'unreadable'; (Get-V $h 'operation.volumes').Reason | Should -Be 'rights'
        (Get-V $h 'operation.powerPlan').State | Should -Be 'read'; $h.Areas['operation'].Status | Should -Be 'partial'; $h.Areas['operation'].Error | Should -Be ''
        # Groesse: die Abfrage der Auslagerungsdatei bekommt den Rest des Limits als Zeitlimit und endet daran; was davor gelesen wurde, bleibt
        (Get-V $h 'size.cpuLogical').State | Should -Be 'read'; (Get-V $h 'size.pagefiles').Reason | Should -Be 'timeout'; (Get-V $h 'size.storageControllers').Reason | Should -Be 'timeout'
        $h.Areas['size'].Status | Should -Be 'partial'; $h.Areas['size'].DurationMs | Should -BeLessThan 3000      # nicht die 5 s des haengenden Aufrufs
        $script:WinFake.Calls.Keys | Should -Not -Contain 'cim:Win32_SCSIController'          # nach dem Limit kein Aufruf mehr
        $h.Areas['events'].Status | Should -Be 'read'
    }
    It 'endet am Gesamtlimit und nennt die uebrigen Bereiche nicht gelesen' {
        $script:WinFake.Delay['cim:Win32_PageFileUsage'] = 5000; $script:WorkerPerfWinHealthTotalBudgetSec = 0.5
        try { $h = Read-Health } finally { $script:WorkerPerfWinHealthTotalBudgetSec = 60 }
        $h.Areas['operation'].Status | Should -Be 'failed'; $h.Areas['operation'].Error | Should -Be 'budget'; (Get-V $h 'operation.lastBoot').Reason | Should -Be 'timeout'
        $script:WinFake.Calls.Keys | Should -Not -Contain 'cim:Win32_LogicalDisk'
    }
    It 'liest die Laufwerke auch, wenn die Liste der Auslagerungsdateien nicht lesbar ist' {   # Review Focus 1
        $script:WinFake.Delay['cim:Win32_PageFileUsage'] = 5000; $script:WorkerPerfWinHealthAreaBudgetSec = 1
        try { $h = Read-Health } finally { $script:WorkerPerfWinHealthAreaBudgetSec = 10 }
        (Get-V $h 'size.pagefiles').Reason | Should -Be 'timeout'
        $c = (Get-V $h 'operation.volumes').Value | Where-Object Drive -eq 'C:'; (Get-V $h 'operation.volumes').State | Should -Be 'read'
        $c.PageFile | Should -BeNullOrEmpty; $c.System | Should -BeTrue; $c.FreeGB | Should -Be 8      # eine Nebenangabe fehlt, der freie Platz bleibt pruefbar
        $h.Areas['operation'].Status | Should -Be 'read'
    }
    It 'ordnet ein Ergebnis nach dem Typ des Werts ein und erkennt verweigerten Zugriff in jeder Form' {
        $ctx = @{ Area = 'vda'; State = $null; Clock = [System.Diagnostics.Stopwatch]::StartNew(); BudgetMs = 10000; Shared = @{}; Values = [ordered]@{} }
        Set-WorkerPerfWinHealthValue $ctx 'vda.controllers' { }                                                               # Liste ohne Ergebnis: gelesen, leer
        Set-WorkerPerfWinHealthValue $ctx 'vda.services' { [ordered]@{ Name = 'X'; State = 'Running'; StartMode = 'Auto' } }   # ein Eintrag mit einem Feld State ist kein Wertsatz
        Set-WorkerPerfWinHealthValue $ctx 'vda.policyRaw' { New-WorkerPerfHealthValue 'unreadable' 'rights' }
        Set-WorkerPerfWinHealthValue $ctx 'vda.version' { }
        Set-WorkerPerfWinHealthValue $ctx 'vda.desktopService' { 'Running' }
        Set-WorkerPerfWinHealthValue $ctx 'vda.listOfSids' { throw (New-WinStandInDenied 'win32') }
        Set-WorkerPerfWinHealthValue $ctx 'vda.farmGuid' { throw (New-WinStandInDenied 'cim') }
        $v = $ctx.Values
        $v['vda.controllers'].State | Should -Be 'read'; ($v['vda.controllers'].Value -is [array]) | Should -BeTrue; @($v['vda.controllers'].Value).Count | Should -Be 0
        $v['vda.services'].State | Should -Be 'read'; ($v['vda.services'].Value -is [array]) | Should -BeTrue; $v['vda.services'].Value[0].State | Should -Be 'Running'
        $v['vda.policyRaw'].State | Should -Be 'unreadable'; $v['vda.policyRaw'].Reason | Should -Be 'rights'
        $v['vda.version'].State | Should -Be 'absent'; $v['vda.version'].Reason | Should -Be ''; $v['vda.desktopService'].Value | Should -Be 'Running'
        $v['vda.listOfSids'].Reason | Should -Be 'rights'; $v['vda.farmGuid'].Reason | Should -Be 'rights'
        $ctx.Values.Clear(); Set-WorkerPerfWinHealthValue $ctx 'vda.farmGuid' { throw 'kaputt' }; $ctx.Values['vda.farmGuid'].Reason | Should -Be 'error'
    }
    It 'uebersetzt die Hilfsklasse' {
        Register-WorkerPerfHealthType; $t = 'WorkerPerf.HealthNative' -as [type]
        $t | Should -Not -BeNullOrEmpty; foreach ($m in 'GetCommit', 'GetActivePowerScheme') { $t.GetMethod($m) | Should -Not -BeNullOrEmpty -Because $m }
    }
    It 'liest das Datum eines Updates nur in einer Form, die es sicher kennt' {
        $qfe = { param($id, $on) [pscustomobject]@{ HotFixID = $id; InstalledOn = $on } }
        $script:WinFake.Cim['Win32_QuickFixEngineering'] = @((& $qfe 'KB1' '10/14/2026'), (& $qfe 'KB2' '14.10.2026'), (& $qfe 'KB3' '1d9a3c'), (& $qfe 'KB4' ''))
        $h = Read-Health; (Get-V $h 'operation.lastUpdateId').Value | Should -Be 'KB1'; (Get-V $h 'operation.lastUpdate').Value | Should -Be (ConvertTo-WorkerPerfHealthTime ([datetime]'2026-10-14'))
        $script:WinFake.Cim['Win32_QuickFixEngineering'] = @((& $qfe 'KB2' '14.10.2026'), (& $qfe 'KB3' '1d9a3c'))
        $h = Read-Health; (Get-V $h 'operation.lastUpdate').State | Should -Be 'absent'; (Get-V $h 'operation.lastUpdateId').State | Should -Be 'absent'
    }
    It 'meldet einen Bereich ohne Leser und einen Leser, der wirft, als nicht gelesen' {
        $keep = $script:WorkerPerfWinHealthReaders
        function Read-TestThrows($Ctx) { Set-WorkerPerfWinHealthValue $Ctx 'operation.pendingRename' { 3 }; throw 'Testfehler im Leser' }
        $script:WorkerPerfWinHealthReaders = [ordered]@{ size = $keep['size']; operation = 'Read-TestThrows' }
        try { $h = Read-Health } finally { $script:WorkerPerfWinHealthReaders = $keep }
        $h.Areas['size'].Status | Should -Be 'read'; $h.Areas['events'].Status | Should -Be 'failed'; $h.Areas['events'].Error | Should -Be 'noReader'
        $h.Areas['operation'].Status | Should -Be 'partial'; $h.Areas['operation'].Error | Should -Be 'Testfehler im Leser'; (Get-V $h 'operation.pendingRename').Value | Should -Be 3
    }
    It 'liest ohne Zustand nichts' {
        Read-Health @('Zustand') | Should -BeNullOrEmpty
        @($script:WinFake.Calls.Keys | Where-Object { $_ -match '^registry:(?!print)|^native:|Win32_PageFileUsage|Win32_LogicalDisk|winevent:oldest' }) | Should -BeNullOrEmpty
    }
    It 'unterscheidet nicht vorhanden, nicht installiert und nicht lesbar' {   # Review Focus 3
        $script:WinFake.Registry.Remove('SOFTWARE\VMware, Inc.\VMware Tools'); $script:WinFake.Registry.Remove('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{A1}')
        $script:WinFake.Services = @($script:WinFake.Services | Where-Object Name -ne 'VMTools'); $script:WinFake.Cim['Win32_QuickFixEngineering'] = @(); $script:WinFake.Cim['Win32_SystemDriver'] = @()
        $script:WinFake.RegistryFail['SYSTEM\CurrentControlSet\Control\Session Manager'] = New-Object System.Security.SecurityException 'kein Zugriff'
        $script:WinFake.Logs = @($script:WinFake.Logs | Where-Object { $_ -ne 'Microsoft-Windows-SMBClient/Connectivity' })
        $h = Read-Health
        (Get-V $h 'size.vmtoolsPresent').Value | Should -BeFalse; (Get-V $h 'size.vmtoolsService').State | Should -Be 'absent'; (Get-V $h 'size.vmtoolsService').Reason | Should -Be 'notInstalled'
        (Get-V $h 'size.vmtoolsVersion').Reason | Should -Be 'notInstalled'; (Get-V $h 'size.balloonDriver').Reason | Should -Be 'notInstalled'; (Get-V $h 'operation.lastUpdate').State | Should -Be 'absent'; (Get-V $h 'operation.lastUpdate').Reason | Should -Be ''
        (Get-V $h 'operation.pendingRename').State | Should -Be 'unreadable'; (Get-V $h 'operation.pendingRename').Reason | Should -Be 'rights'
        $smb = (Get-V $h 'events.logs').Value | Where-Object Log -eq 'Microsoft-Windows-SMBClient/Connectivity'; $smb.Present | Should -BeFalse; $smb.Enabled | Should -BeNullOrEmpty
        # ein Protokoll, das sich nicht abfragen laesst, ist nicht lesbar, nicht "nicht vorhanden"
        $script:WinFake.LogFail['System'] = New-Object System.UnauthorizedAccessException 'Zugriff verweigert'
        $h = Read-Health; (Get-V $h 'events.logs').State | Should -Be 'unreadable'; (Get-V $h 'events.logs').Reason | Should -Be 'rights'; $h.Areas['events'].Status | Should -Be 'failed'
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/WindowsHealth.Tests.ps1`
Expected: FAIL, `Get-WorkerPerfHealth` ist nicht definiert

- [ ] **Step 3: Platzhalter in `tests/WindowsStandIns.ps1` nach den Interfaces und der Tabelle der Vorgaben ergänzen**

- [ ] **Step 4: Gerüst, dünne Aufrufe und die drei Leser in `src/WorkerPerf.Sources.Windows.ps1` umsetzen** (C#-Signaturen nach den Dokumenten der Wertetabellen: `GetPerformanceInfo(out PERFORMANCE_INFORMATION, int cb)` aus `psapi.dll` mit `SetLastError`; die Struktur hat `cb` als `uint`, dann zehn Felder vom Typ `UIntPtr` (`CommitTotal`, `CommitLimit`, `CommitPeak`, `PhysicalTotal`, `PhysicalAvailable`, `SystemCache`, `KernelTotal`, `KernelPaged`, `KernelNonpaged`, `PageSize`: `SIZE_T`, nicht `int`) und drei `uint`; `cb` = `Marshal.SizeOf`. `PowerGetActiveScheme(IntPtr, out IntPtr)` aus `powrprof.dll` gibt den Fehlercode zurück (0 = Erfolg); `Get-WorkerPerfLogOldestTime` über `EventLogReader` mit `EventLogQuery(<Name>, PathType.LogName)` in aufsteigender Richtung, einen Eintrag lesen, `TimeCreated`, beide Objekte freigeben)

- [ ] **Step 5: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0` (die bestehenden Tests der Windows-Quelle bleiben grün: die Platzhalter liefern für die bisherigen Aufrufe dieselben Werte)

- [ ] **Step 6: Commit**

```bash
git add src/WorkerPerf.Sources.Windows.ps1 tests/WindowsStandIns.ps1 tests/WindowsHealth.Tests.ps1
git commit -m "Read size, operation and event log state of the worker within a time budget"
```

---

### Task 5: Windows – Bereiche Sitzungen, Citrix VDA, Profilverwaltung

**Files:**
- Modify: `src/WorkerPerf.Sources.Windows.ps1`, `tests/WindowsStandIns.ps1`
- Test: `tests/WindowsHealth.Tests.ps1`
- Mit dem geführten Bericht geteilt: keine. Nicht anfassen: `src/Test-WorkerPerfSources.ps1`; das Verhalten von `Get-WorkerPerfProfileDisks` ohne den neuen Schalter.

**Interfaces:**
- Consumes: Task 4; `$script:WorkerPerfWtsSource`, `$script:WtsAvailable`, `[WorkerPerf.Wts]::GetSessions()`, `Write-WarningOnce`, `Get-WorkerPerfProfileDisks`, `$script:WorkerPerfWinStorageTimeoutSec`, `Resolve-WorkerPerfProfileOwner`, `New-WorkerPerfUserIndex`.
- Produces:
  - `WorkerPerf.WtsSession` erhält `public DateTime ConnectTime;` und `public DateTime DisconnectTime;` (`DateTime.MinValue` = unbekannt), gesetzt aus `WTSINFO.ConnectTime` und `WTSINFO.DisconnectTime`, wenn der Wert größer 0 ist.
  - `Get-WorkerPerfHealthSessions -> object[]` (dünn, mit Platzhalter): die Sitzungen aus `[WorkerPerf.Wts]::GetSessions()`. Anders als `Get-WinSessionRaw` wirft sie, statt leer zurückzukommen: wenn die WTS-Hülle nicht verfügbar ist, wenn `GetSessions()` scheitert, und wenn dem geladenen Typ `WorkerPerf.WtsSession` das Feld `DisconnectTime` fehlt (`Add-Type` lädt einen Typ nur einmal je Prozess: in einer Konsole, in der schon eine ältere Fassung lief, fehlen die neuen Felder; dazu einmal die Warnung `Sitzungsabfrage veraltet: bitte eine neue Konsole starten`). Der Platzhalter zählt `wts`, wirft `$script:WinFake.SessionsFail`, wenn gesetzt, und liefert sonst `$script:WinFake.Sessions`; ein Sitzungsobjekt des Platzhalters ohne die neuen Felder hat unbekannte Zeitpunkte (0).
  - `Get-WorkerPerfProfileDisks [-WithSize] [-TimeoutSec <int>]`: `-TimeoutSec` ist das Zeitlimit jeder ihrer Abfragen (Vorgabe `$script:WorkerPerfWinStorageTimeoutSec`, wie bisher); der Leser des Zustandsbilds übergibt den Rest des Bereichslimits in ganzen Sekunden, mindestens 1. Jeder Datensatz trägt zusätzlich `SizeBytes` und `AllocatedBytes` (`MSFT_Disk.Size`, `.AllocatedSize`); mit `-WithSize` jede Partition `VolumeSizeBytes` und `VolumeFreeBytes` aus einer Abfrage von `MSFT_Volume` (`Path`, `Size`, `SizeRemaining`), verbunden über den Volume-Pfad (`\\?\Volume{…}\`) in `AccessPaths`. Ohne den Schalter wird `MSFT_Volume` nicht abgefragt.
  - `Get-WorkerPerfFileVersion([string]$Path) -> string | $null` (dünn; `[System.Diagnostics.FileVersionInfo]::GetVersionInfo`, `ProductVersion`; `$null`, wenn die Datei fehlt); Platzhalter aus `$script:WinFake.FileVersions`, Zähler `file:version`.
  - `Get-WorkerPerfServiceExe([string]$PathName) -> string` (rein): der Pfad des Programms aus `Win32_Service.PathName`. Beginnt der Text mit einem Anführungszeichen, ist es der Teil bis zum nächsten Anführungszeichen; sonst der Teil bis einschließlich des ersten `.exe` (ohne Rücksicht auf Groß- und Kleinschreibung), und ohne `.exe` der ganze Text; `''` bleibt `''`. Jeder Leser, der einen Dienst an seinem Programm erkennt (`profile.service`) oder dessen Dateiversion liest (`profile.version`, `vda.wemVersion`), nimmt den Pfad von hier.
  - `ConvertTo-WorkerPerfControllerKind([string]$Entry) -> 'ip' | 'fqdn' | 'short'` (rein: eine IPv4- oder IPv6-Adresse `ip`, ein Name mit Punkt `fqdn`, sonst `short`).
  - `Get-WorkerPerfRegistryTree([string]$SubKey, [string[]]$Without = @(), [int]$MaxValues = 2000, [int]$MaxDepth = 6) -> @{ Key; Name; Value }[]` über `Get-WorkerPerfRegistryValues`: `Key` relativ zu `$SubKey` (`''` für den Schlüssel selbst), Werte als Text (mehrere Zeichenketten mit „; " verbunden, Binärwerte als „binaer, n Byte"); Unterschlüssel, deren Name in `$Without` steht, werden auf der obersten Ebene übergangen.
  - Leser `Read-WorkerPerfWinHealthSessions`, `Read-WorkerPerfWinHealthVda`, `Read-WorkerPerfWinHealthProfile`, eingetragen in `$script:WorkerPerfWinHealthReaders`; gemeinsame Abfrage `Shared['sessions']` (`Get-WorkerPerfHealthSessions`). Der Leser des VDA liest auch den WEM-Agenten und die Dienste der Teams-Umleitung aus `Shared['services']` (Auswahl über `DisplayName` bzw. `PathName` wie in der Wertetabelle, der Pfad eines Programms über `Get-WorkerPerfServiceExe`, die Anzeigenamen der drei WEM-Dienste aus `$script:WorkerPerfHealthWemServices`; ohne den Agent-Dienst sind alle Werte `vda.wem*` `absent`/`notInstalled`, und ihre Registrierungswerte werden nicht gelesen) und `vda.persistentDataLocation` über `Get-WorkerPerfWinHealthCim $Ctx 'Citrix_VirtualDesktopInfo' 'root\Citrix\DesktopInformation'`: meldet der Aufruf einen fehlenden Namespace (`NativeErrorCode` mit dem Text `InvalidNamespace` oder das HRESULT `0x8004100E`), ist der Wert `absent`/`notInstalled`; jeder andere Fehler bleibt ein Fehler. Scheitert sie, ist `sessions.list` `unreadable`, und der Leser der Profilverwaltung liest die Container trotzdem: `Owner` bleibt leer, `SessionId` −1.
- Produces (Platzhalter, Vorgaben): `Cim['Win32_TSSessionSetting']`: `RDP-Tcp` und `ICA-CGP`, alle Limits 0, `BrokenConnectionAction` 0, `PolicySourceDisconnectedSessionLimit` 0. `Cim['Win32_UserProfile']`: (`C:\Users\mueller`, geladen, `LastUseTime` jetzt, `Status` 0), (`C:\Users\gast`, nicht geladen, jetzt − 40 Tage, 0), (`C:\Users\TEMP`, nicht geladen, jetzt − 2 Tage, `Status` 9: das Feld ist ein Bitfeld, hier temporär und beschädigt), (`C:\Windows\ServiceProfiles\NetworkService`, geladen, `Special` wahr). Die Platten aus `Add-WinStandInDisk` tragen `Size` 53687091200 und `AllocatedSize` 21474836480; `MSFT_Volume` liefert je Platte den Volume-Pfad mit `Size` 53687091200 und `SizeRemaining` 2147483648 (mueller) bzw. 32212254720 (gast). `Registry`: `SOFTWARE\Policies\Citrix\VirtualDesktopAgent` (`ListOfDDCs` „ddc01.klinik.example ddc02"); `SOFTWARE\Citrix\VirtualDesktopAgent` (`ListOfDDCs` „10.1.1.5", `ListOfSIDs` „S-1-5-21-1-2-3-1001"); `SOFTWARE\Policies\Citrix` mit den Unterschlüsseln `VirtualDesktopAgent`, `UserProfileManager`, `ICAPolicies`; `…\ICAPolicies` (`SimRichtlinie` 1, `SimDrucker` `\\prn01\Etage2`); `…\UserProfileManager` (`PathToUserStore` `\\fs01\upm$\%USERNAME%.%USERDOMAIN%`, `ServiceActive` 1). `FileVersions`: `C:\Program Files\Citrix\User Profile Manager\UserProfileManager.exe` → „22.3.0.4000"; `C:\Program Files (x86)\Citrix\Workspace Environment Management Agent\Citrix.Wem.Agent.Service.exe` → „2407.1.0.1". Weitere Dienste in `Services`, in dieser Reihenfolge hinter `ctxProfile`, alle `Running`, `Auto`, `ProcessId` 0, wo nichts anderes steht: `WemAgentSvc` (`DisplayName` „Citrix WEM Agent Host Service", `PathName` `"C:\Program Files (x86)\Citrix\Workspace Environment Management Agent\Citrix.Wem.Agent.Service.exe"`, in Anführungszeichen), `WemLogonSvc` („Citrix WEM User Logon Service", `PathName` im selben Ordner `Citrix.Wem.Agent.LogonService.exe`), `CtxTeamsSvc` („Citrix HDX Teams Redirection Service", `PathName` `"C:\Program Files (x86)\Citrix\System32\CtxSvcHost.exe" -g TeamsSvcs`), `CtxHdxWebSocketService` („Citrix HDX HTML5 Video Redirection Service", `PathName` `"C:\Program Files (x86)\Citrix\System32\WebSocketService.exe" /service`), `CpSvc` („Citrix Print Manager Service", `PathName` `C:\Program Files\Citrix\System32\CpSvc.exe`; gebraucht ab Task 6), `SENS` („System Event Notification Service"), `wuauserv` („Windows Update", `Stopped`, `Manual`; gebraucht ab Task 6). Die Kurznamen dieser Citrix-Dienste sind erfunden: gelesen wird über Anzeigename und Pfad. `Cim['Citrix_VirtualDesktopInfo']`: ein Objekt mit `PersistentDataLocation` `D:\PersistentData`; fehlt die Klasse in `Cim`, wirft der Platzhalter `New-WinStandInMissingNamespace` (neu: eine Ausnahme der Testklasse `WinStandInCimException` mit `NativeErrorCode` = `InvalidNamespace`). `Registry` zusätzlich: `SOFTWARE\Policies\Norskale\Agent Host` (`BrokerSvcName` „wem01.klinik.example"); `SYSTEM\CurrentControlSet\Control\Norskale\Agent Host` (`AgentCacheAlternateLocation` `D:\WEMCache`); `SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon` (`GpNetworkStartTimeoutPolicyValue` 120).

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/WindowsHealth.Tests.ps1`, neuer Block)

```powershell
Describe 'Zustandsbild unter Windows: Sitzungen, Citrix VDA, Profilverwaltung' {
    BeforeEach { Reset-WinStandIns }
    It 'liest Sitzungen mit Trennzeitpunkt, Zeitlimits und lokale Profile' {
        $script:WinFake.Sessions.Add([pscustomobject]@{ SessionId = 3; State = 'Disconnected'; WinStation = ''; User = 'gast'; Domain = 'KLINIK'; ClientName = 'WS-0002'
                LogonTime = [datetime]::Now.AddHours(-30); IdleSec = 7200; ConnectTime = [datetime]::Now.AddHours(-30); DisconnectTime = [datetime]::Now.AddHours(-26) })
        $h = Read-Health; $h.Areas['sessions'].Status | Should -Be 'read'
        $s = (Get-V $h 'sessions.list').Value; @($s).Count | Should -Be 3
        $g = $s | Where-Object User -eq 'gast'; $g.State | Should -Be 'Disconnected'; $g.Client | Should -Be 'WS-0002'; $g.Domain | Should -Be 'KLINIK'; $g.IdleMinutes | Should -Be 120
        ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - $g.DisconnectTime) / 3600000 | Should -BeGreaterThan 25.9
        ($s | Where-Object User -eq 'mueller').DisconnectTime | Should -Be 0           # ein Sitzungsobjekt ohne das Feld: unbekannt
        ((Get-V $h 'sessions.limits').Value | Where-Object Terminal -eq 'ICA-CGP').DisconnectedLimitMin | Should -Be 0
        $script:WinFake.Cim['Win32_TSSessionSetting'][1].DisconnectedSessionLimit = 14400000; $script:WinFake.Cim['Win32_TSSessionSetting'][1].PolicySourceDisconnectedSessionLimit = 1
        $l = (Get-V (Read-Health) 'sessions.limits').Value | Where-Object Terminal -eq 'ICA-CGP'; $l.DisconnectedLimitMin | Should -Be 240; $l.FromPolicy | Should -BeTrue
        $p = (Get-V $h 'sessions.localProfiles').Value; @($p).Count | Should -Be 4
        @(($p | Where-Object { -not $_.Loaded -and -not $_.Special }).Path) | Should -Be @('C:\Users\gast', 'C:\Users\TEMP'); ($p | Where-Object Path -eq 'C:\Users\TEMP').Temporary | Should -BeTrue
        $script:WinFake.CimFail['Win32_TSSessionSetting'] = New-WinStandInDenied 'cim'
        $h = Read-Health; (Get-V $h 'sessions.limits').Reason | Should -Be 'rights'; (Get-V $h 'sessions.list').State | Should -Be 'read'; $h.Areas['sessions'].Status | Should -Be 'partial'
    }
    It 'liest Version, Dienste und Controllerliste des VDA; die Richtlinie geht vor' {
        $h = Read-Health; $h.Areas['vda'].Status | Should -Be 'read'
        (Get-V $h 'vda.version').Value | Should -Be '2203.0.4000.4033'; (Get-V $h 'vda.desktopService').Value | Should -Be 'Running'
        @((Get-V $h 'vda.services').Value.Name) | Should -Be @('BrokerAgent', 'ctxProfile', 'WemAgentSvc', 'WemLogonSvc', 'CtxTeamsSvc', 'CtxHdxWebSocketService', 'CpSvc')
        $c = (Get-V $h 'vda.controllers').Value; @($c.Entry) | Should -Be @('ddc01.klinik.example', 'ddc02'); @($c.Kind) | Should -Be @('fqdn', 'short'); @($c.From | Select-Object -Unique) | Should -Be @('policy')
        (Get-V $h 'vda.listOfSids').Value | Should -BeTrue; (Get-V $h 'vda.farmGuid').Value | Should -BeFalse
        $raw = (Get-V $h 'vda.policyRaw').Value; ($raw | Where-Object Name -eq 'SimDrucker').Value | Should -Be '\\prn01\Etage2'; ($raw | Where-Object Name -eq 'SimDrucker').Key | Should -Be 'ICAPolicies'
        @($raw | Where-Object { $_.Key -match 'UserProfileManager|VirtualDesktopAgent' }).Count | Should -Be 0
        ($h | ConvertTo-Json -Depth 12) | Should -Not -Match 'S-1-5-21-1-2-3-1001'                # der Inhalt von ListOfSIDs wird nicht gespeichert
        $script:WinFake.Registry.Remove('SOFTWARE\Policies\Citrix\VirtualDesktopAgent')
        $c = (Get-V (Read-Health) 'vda.controllers').Value; @($c.Entry) | Should -Be @('10.1.1.5'); $c[0].Kind | Should -Be 'ip'; $c[0].From | Should -Be 'registry'
        ConvertTo-WorkerPerfControllerKind 'fd00::5' | Should -Be 'ip'
    }
    It 'nennt einen Worker ohne VDA und ohne Profilverwaltung nicht installiert' {   # Review Focus 3
        $script:WinFake.Services = @($script:WinFake.Services | Where-Object { $_.PathName -notmatch 'Citrix' }); $script:WinFake.Cim.Remove('Citrix_VirtualDesktopInfo')
        foreach ($k in @($script:WinFake.Registry.Keys | Where-Object { $_ -match 'Citrix|\{B2\}' })) { $script:WinFake.Registry.Remove($k) }
        $script:WinFake.Disks.Clear()
        $h = Read-Health
        foreach ($id in 'vda.version', 'vda.desktopService', 'profile.service', 'profile.version', 'vda.persistentDataLocation', 'vda.wemService', 'vda.wemServices', 'vda.wemVersion', 'vda.wemServer',
            'vda.wemCacheLocation', 'vda.wemGpNetworkTimeout', 'vda.teamsService', 'vda.webSocketService') { (Get-V $h $id).State | Should -Be 'absent' -Because $id; (Get-V $h $id).Reason | Should -Be 'notInstalled' -Because $id }
        foreach ($id in 'vda.controllers', 'vda.services', 'vda.policyRaw', 'profile.containers', 'profile.policyGpo') { (Get-V $h $id).State | Should -Be 'read' -Because $id; @((Get-V $h $id).Value).Count | Should -Be 0 -Because $id }
        $h.Areas['vda'].Status | Should -Be 'read'; $h.Areas['profile'].Status | Should -Be 'read'
    }
    It 'liest den WEM-Agenten, die Dienste der Teams-Umleitung und den bestaendigen Datenort' {
        $h = Read-Health
        (Get-V $h 'vda.wemService').Value | Should -Be 'Running'; (Get-V $h 'vda.wemVersion').Value | Should -Be '2407.1.0.1'
        @((Get-V $h 'vda.wemServices').Value.Name) | Should -Be @('Citrix WEM Agent Host Service', 'Citrix WEM User Logon Service', 'System Event Notification Service')
        @((Get-V $h 'vda.wemServices').Value.StartMode | Select-Object -Unique) | Should -Be @('Auto')
        (Get-V $h 'vda.wemServer').Value | Should -Be 'wem01.klinik.example'; (Get-V $h 'vda.wemCacheLocation').Value | Should -Be 'D:\WEMCache'; (Get-V $h 'vda.wemGpNetworkTimeout').Value | Should -Be 120
        (Get-V $h 'vda.teamsService').Value | Should -Be 'Running'; (Get-V $h 'vda.webSocketService').Value | Should -Be 'Running'; (Get-V $h 'vda.persistentDataLocation').Value | Should -Be 'D:\PersistentData'
        # der fruehere Anzeigename zaehlt; ein leerer Cache-Ort heisst: nicht gesetzt
        ($script:WinFake.Services | Where-Object Name -eq 'WemAgentSvc').DisplayName = 'Norskale Agent Host Service'
        $script:WinFake.Registry['SYSTEM\CurrentControlSet\Control\Norskale\Agent Host']['AgentCacheAlternateLocation'] = ''
        $h = Read-Health; (Get-V $h 'vda.wemService').Value | Should -Be 'Running'; @((Get-V $h 'vda.wemServices').Value.Name)[0] | Should -Be 'Norskale Agent Host Service'
        (Get-V $h 'vda.wemCacheLocation').State | Should -Be 'absent'; (Get-V $h 'vda.wemCacheLocation').Reason | Should -Be ''
        # ein Worker mit VDA, aber ohne WEM-Agent                                                     # Review Focus 3
        $script:WinFake.Services = @($script:WinFake.Services | Where-Object { $_.Name -notlike 'Wem*' })
        $h = Read-Health; foreach ($id in 'vda.wemService', 'vda.wemServices', 'vda.wemCacheLocation', 'vda.wemGpNetworkTimeout') { (Get-V $h $id).Reason | Should -Be 'notInstalled' -Because $id }
        $script:WinFake.Calls.Keys | Should -Not -Contain 'registry:SOFTWARE\Policies\Norskale\Agent Host'
        (Get-V $h 'vda.version').State | Should -Be 'read'; $h.Areas['vda'].Status | Should -Be 'read'
    }
    It 'findet das Programm eines Dienstes auch in Anfuehrungszeichen und mit Argumenten' {
        Get-WorkerPerfServiceExe '"C:\Program Files\Citrix\User Profile Manager\UserProfileManager.exe" /svc' | Should -Be 'C:\Program Files\Citrix\User Profile Manager\UserProfileManager.exe'
        Get-WorkerPerfServiceExe 'C:\Windows\System32\svchost.exe -k netsvcs -p' | Should -Be 'C:\Windows\System32\svchost.exe'
        Get-WorkerPerfServiceExe 'C:\Program Files\Citrix\System32\CpSvc.exe' | Should -Be 'C:\Program Files\Citrix\System32\CpSvc.exe'; Get-WorkerPerfServiceExe '' | Should -Be ''
        ($script:WinFake.Services | Where-Object Name -eq 'ctxProfile').PathName | Should -BeLike '"*UserProfileManager.exe"'      # der Platzhalter traegt die Form von Windows
        $h = Read-Health; (Get-V $h 'profile.service').Value | Should -Be 'Running'; (Get-V $h 'profile.version').Value | Should -Be '22.3.0.4000'; (Get-V $h 'vda.wemVersion').Value | Should -Be '2407.1.0.1'
        ($script:WinFake.Services | Where-Object Name -eq 'ctxProfile').PathName = '"C:\Program Files\Citrix\User Profile Manager\UserProfileManager.exe" /service'
        (Get-V (Read-Health) 'profile.version').Value | Should -Be '22.3.0.4000'
    }
    It 'liest eine gemeinsame Abfrage neu, die im Bereich davor am Zeitlimit endete, und reicht fehlende Rechte weiter' {   # Review Focus 1
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null); $before = [int]$script:WinFake.Calls['cim:Win32_Service']
        $script:WinFake.DelayOnce['cim:Win32_Service'] = 5000; $script:WorkerPerfWinHealthAreaBudgetSec = 1
        try { $h = Get-WorkerPerfHealth 3>$null } finally { $script:WorkerPerfWinHealthAreaBudgetSec = 10 }
        (Get-V $h 'size.vmtoolsService').State | Should -Be 'unreadable'; (Get-V $h 'size.vmtoolsService').Reason | Should -Be 'timeout'
        (Get-V $h 'vda.services').State | Should -Be 'read'; (Get-V $h 'vda.desktopService').Value | Should -Be 'Running'; (Get-V $h 'profile.service').Value | Should -Be 'Running'
        [int]$script:WinFake.Calls['cim:Win32_Service'] - $before | Should -Be 2                       # ein zweiter Versuch im naechsten Bereich, der die Dienste braucht, danach keiner mehr
        Reset-WinStandIns; [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null); $before = [int]$script:WinFake.Calls['cim:Win32_Service']
        $script:WinFake.CimFail['Win32_Service'] = New-WinStandInDenied 'cim'; $h = Get-WorkerPerfHealth 3>$null
        foreach ($id in 'size.vmtoolsService', 'vda.services', 'profile.service') { (Get-V $h $id).State | Should -Be 'unreadable' -Because $id; (Get-V $h $id).Reason | Should -Be 'rights' -Because $id }
        [int]$script:WinFake.Calls['cim:Win32_Service'] - $before | Should -Be 1                       # fehlende Rechte: kein zweiter Versuch
    }
    It 'liest Container mit Groesse, Belegung und Besitzer' {
        $h = Read-Health; $c = (Get-V $h 'profile.containers').Value; @($c).Count | Should -Be 2
        $m = $c | Where-Object Owner -eq 'mueller'; $m.Location | Should -Be '\\fs01\upm$\mueller.KLINIK\Win2022\UPM_Profile\ProfileContainer_RW.vhdx'
        $m.Mount | Should -Be 'C:\Users\mueller_UPM_local\UpmTempMount'; $m.SessionId | Should -Be 2; $m.SizeGB | Should -Be 50; $m.AllocatedGB | Should -Be 20; $m.VolumeFreeGB | Should -Be 2; $m.UsedPct | Should -Be 96
        $g = $c | Where-Object { $_.Location -like '*gast*' }; $g.Owner | Should -Be ''; $g.SessionId | Should -Be -1; $g.UsedPct | Should -Be 40
        (Get-V $h 'profile.service').Value | Should -Be 'Running'; (Get-V $h 'profile.version').Value | Should -Be '22.3.0.4000'
        @((Get-V $h 'profile.policyGpo').Value.Name | Sort-Object) | Should -Be @('PathToUserStore', 'ServiceActive'); @((Get-V $h 'profile.policyStudio').Value).Count | Should -Be 0
        # die Schnappschuesse fragen die Volumes weiter nicht ab
        Reset-WinStandIns; [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg -Skip Zustand 3>$null); [void](Get-WorkerPerfSnapshot -Kind K)
        $script:WinFake.Calls.Keys | Should -Not -Contain 'cim:MSFT_Volume'
        Reset-WinStandIns; $script:WinFake.FailStorage = $true
        $h = Read-Health; (Get-V $h 'profile.containers').State | Should -Be 'unreadable'; (Get-V $h 'profile.service').State | Should -Be 'read'
    }
    It 'meldet eine gescheiterte Sitzungsabfrage und haelt das Zeitlimit auch in der Abfrage der Container ein' {   # Review Focus 1
        $script:WinFake.SessionsFail = New-Object System.InvalidOperationException 'WTS antwortet nicht'
        $h = Read-Health; (Get-V $h 'sessions.list').State | Should -Be 'unreadable'; (Get-V $h 'sessions.list').Reason | Should -Be 'error'; $h.Areas['sessions'].Status | Should -Be 'partial'
        $c = @((Get-V $h 'profile.containers').Value); $c.Count | Should -Be 2                    # keine Sitzungen heisst nicht: keine Container
        @($c | Where-Object { $_.Owner -ne '' }).Count | Should -Be 0; @($c | Where-Object { $_.SessionId -ne -1 }).Count | Should -Be 0
        Reset-WinStandIns; $script:WinFake.Delay['cim:MSFT_Volume'] = 5000; $script:WorkerPerfWinHealthAreaBudgetSec = 1
        try { $h = Read-Health } finally { $script:WorkerPerfWinHealthAreaBudgetSec = 10 }
        (Get-V $h 'profile.containers').State | Should -Be 'unreadable'; (Get-V $h 'profile.containers').Reason | Should -Be 'timeout'; (Get-V $h 'profile.service').State | Should -Be 'read'
        $h.Areas['profile'].Status | Should -Be 'partial'; $h.Areas['profile'].DurationMs | Should -BeLessThan 3000; $h.Areas['vda'].Status | Should -Be 'read'
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/WindowsHealth.Tests.ps1`
Expected: FAIL, der Bereich `sessions` hat den Zustand `failed` (`noReader`)

- [ ] **Step 3: Platzhalter ergänzen; WTS-Hülle, `Get-WorkerPerfHealthSessions`, `Get-WorkerPerfProfileDisks -WithSize -TimeoutSec`, die dünnen und reinen Helfer und die drei Leser umsetzen**

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Sources.Windows.ps1 tests/WindowsStandIns.ps1 tests/WindowsHealth.Tests.ps1
git commit -m "Read sessions, Citrix VDA and profile management state of the worker"
```

---

### Task 6: Windows – Bereiche Drucken, Sicherheitsprodukte, Netz, Wartung

**Files:**
- Modify: `src/WorkerPerf.Sources.Windows.ps1`, `tests/WindowsStandIns.ps1`
- Test: `tests/WindowsHealth.Tests.ps1`
- Mit dem geführten Bericht geteilt: keine. Nicht anfassen: `src/roles.json` (Task 12), `src/events.json`, `src/apps.json`.

**Interfaces:**
- Consumes: Tasks 4 und 5 (darunter `Get-WorkerPerfWinHealthLog`, `New-WinStandInDenied`, `Register-WorkerPerfHealthType`); `Get-WorkerPerfPrintIsolationPolicy`, `Get-WorkerPerfPrintDrivers`, `$script:WorkerPerfWinPrintQueueCategory`, `$script:WorkerPerfWinPrintQueueCounters`, `Open-WorkerPerfWinCategory`, `Read-WorkerPerfWinCategory`, `Get-WorkerPerfWinInstantValues`, `ConvertTo-WorkerPerfPrintQueueRows`.
- Produces:
  - `Get-WorkerPerfPrintDrivers` legt die Richtlinie im Zustand ab (`PrintIsolationPolicy`), aber nur, wenn ihr Lesen gelungen ist: nach einem Lesefehler (die Funktion warnt dann nur und rechnet mit einer leeren Richtlinie weiter) bleibt der Zustand ohne den Eintrag. Der Leser des Bereichs `print` nimmt die Richtlinie von dort und ruft `Get-WorkerPerfPrintIsolationPolicy` selbst, wenn sie fehlt; ein Lesefehler wird so in `print.isolationExecution` und `print.isolationOverride` „nicht lesbar" und nicht „nicht gesetzt".
  - Dünne Windows-Aufrufe mit Platzhalter: `Get-WorkerPerfFilterRaw -> @{ Name; Altitude; Instances; Legacy }[]` (holt mit `[WorkerPerf.HealthNative]::GetFilterBuffers() -> byte[][]` die Puffer von `FilterFindFirst` und `FilterFindNext` und zerlegt jeden mit `ConvertFrom-WorkerPerfFilterBuffer`; Zähler `native:filters`; Platzhalter aus `$script:WinFake.Filters`, Ausnahme aus `FiltersFail`); `Get-WorkerPerfTaskRaw -> @{ Count; Tasks = @{ Path; Enabled; State; NextRun; LastRun; TriggerTypes (int[]); RepeatMinutes; Action }[] }` (`Schedule.Service`; `Tasks` nur außerhalb `\Microsoft\`; `NextRun`/`LastRun` als `datetime`, wie die Aufgabenplanung sie liefert („kein Lauf" ist dort der 30.12.1899, nicht `MinValue`); jedes COM-Objekt wird freigegeben; Zähler `com:tasks`; Platzhalter aus `$script:WinFake.Tasks`).
  - `ConvertTo-WorkerPerfTriggerWords([int[]]$Types) -> string` (rein; 0 `event`, 1 `time`, 2 `daily`, 3 `weekly`, 4 und 5 `monthly`, 6 `idle`, 7 `registration`, 8 `boot`, 9 `logon`, 11 `session`, sonst `other`; jedes Wort einmal, in der Reihenfolge des Auftretens, mit „, " verbunden).
  - `ConvertTo-WorkerPerfTaskTime([datetime]$Time) -> datetime` (rein): ein Zeitpunkt vor dem 02.01.1900 wird `[datetime]::MinValue`, jeder andere bleibt. Die Aufgabenplanung meldet „kein letzter Lauf" und „kein nächster Lauf" als 30.12.1899; ohne die Umsetzung stünde dieses Datum in Rohwerten und Kopiertexten.
  - `ConvertFrom-WorkerPerfFilterBuffer([byte[]]$Buffer) -> @{ Name; Altitude; Instances; Legacy }[]` (rein): die Einträge `FILTER_AGGREGATE_STANDARD_INFORMATION` eines Puffers, über `NextEntryOffset` verkettet; `Flags` 1 = Minifilter (mit `NumberOfInstances`), 2 = alter Filter (`Legacy` wahr, `Instances` 0); Name und Höhe als UTF-16 aus Offset (ab dem Anfang des Eintrags) und Länge in Byte, nicht nullterminiert; ein leerer Puffer gibt nichts.
  - Leser `Read-WorkerPerfWinHealthPrint`, `…Security`, `…Network`, `…Maintenance`, eingetragen in `$script:WorkerPerfWinHealthReaders` (danach hat jeder Bereich außer `apps` einen Leser; der folgt in Task 7). Der Leser des Bereichs `print` setzt `print.mappingClientVersion` aus `Shared['uninstall']` (Task 4), wie der Leser der Größe `size.vmtoolsVersion`. Der Leser des Bereichs `maintenance` führt `NextRun` und `LastRun` jeder Aufgabe über `ConvertTo-WorkerPerfTaskTime` und dann über `ConvertTo-WorkerPerfHealthTime`. Gemeinsame Abfrage `Shared['mppreference']` (`MSFT_MpPreference`, nur wenn der Dienst `WinDefend` vorhanden ist).
- Produces (Platzhalter, Vorgaben): `Filters`: (`WdFilter`, „328010", 4), (`upmjit`, „182400", 2), (`FileInfo`, „45000", 5), keiner `Legacy`. `Tasks`: `Count` 150; (`\Sim\Inventarlauf`, eingeschaltet, `Ready`, `NextRun` morgen 10:00, `TriggerTypes` 2, `RepeatMinutes` 0, `Action` `C:\Tools\inventar.exe`) und (`\Sim\Anmeldeskript`, eingeschaltet, `Ready`, `NextRun` `[datetime]'1899-12-30'` wie von der Aufgabenplanung, `TriggerTypes` 9, 0, `C:\Tools\logon.cmd`); `LastRun` beider Aufgaben `[datetime]'1899-12-30'`. `IsolationPolicyFail` (neu): eine Ausnahme, die der Platzhalter von `Get-WorkerPerfPrintIsolationPolicy` wirft, wenn sie gesetzt ist. `Cim['MSFT_MpComputerStatus']`: `AMRunningMode` `Normal`, `RealTimeProtectionEnabled` wahr, `IsTamperProtected` wahr, `AntivirusSignatureAge` 1, `DefenderSignaturesOutOfDate` falsch, `AMProductVersion` „4.18.24090.11". `Cim['MSFT_MpPreference']`: `ExclusionPath` (`C:\Program Files\Citrix`), `ExclusionProcess` (`C:\Program Files\Citrix\User Profile Manager\UserProfileManager.exe`), `ExclusionExtension` (`.vhdx`), `SharedSignaturesPath` leer, `ScanScheduleDay` 0, `ScanScheduleTime` und `ScanScheduleQuickScanTime` 02:00 (`TimeSpan`), `ScanParameters` 1, `RandomizeScheduleTaskTimes` wahr, `ScanAvgCPULoadFactor` 50, `EnableNetworkProtection` 0. `Cim['MSFT_SmbClientConfiguration']`: `RequireSecuritySignature` falsch, Caches 16, 64, 128. `Cim['MSFT_SmbConnection']`: zweimal (`fs01`, `upm$`, „3.1.1", signiert, nicht verschlüsselt, `UserName` `KLINIK\mueller` bzw. `KLINIK\gast`) und einmal (`alt01`, `archiv`, „2.1", nicht signiert). `Cim['Win32_SystemDriver']` bleibt bei der Vorgabe aus Task 4 (nur `vmmemctl`, kein `mrxsmb10`). `Cim['Win32_NetworkAdapterConfiguration']`: (`Index` 4, `DNSServerSearchOrder` `10.1.0.10`). `Cim['MSFT_NetAdapterRssSettingData']`: (`Name` „Ethernet0", `InterfaceDescription` „vmxnet3 Ethernet Adapter", `Enabled` wahr). `Registry`: `SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status` (`OnboardingState` 1); `SYSTEM\CurrentControlSet\Services\W32Time\Parameters` (`Type` „NTP", `NtpServer` „zeit01.klinik.example,0x8 10.1.0.20,0x8"); `SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU` (`AUOptions` 4, `ScheduledInstallDay` 0, `ScheduledInstallTime` 10, `NoAutoRebootWithLoggedOnUsers` 0); `SOFTWARE\Policies\Microsoft\Windows\SrpV2` mit den Unterschlüsseln `Exe` (`EnforcementMode` 1, drei Unterschlüssel) und `Dll` (`EnforcementMode` 1, ein Unterschlüssel).

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/WindowsHealth.Tests.ps1`, neuer Block)

```powershell
Describe 'Zustandsbild unter Windows: Drucken, Sicherheitsprodukte, Netz, Wartung' {
    BeforeEach { Reset-WinStandIns }
    It 'liest den Bereich Drucken auch ohne die Kategorie Drucken' {
        $script:WinFake.Logs += 'Microsoft-Windows-PrintService/Operational'; $script:WinFake.DisabledLogs += 'Microsoft-Windows-PrintService/Operational'
        foreach ($skip in @(), @('Drucken')) {
            $h = Read-Health $skip; $h.Areas['print'].Status | Should -Be 'read' -Because "$skip"
            (Get-V $h 'print.isolationExecution').Value | Should -Be 1; (Get-V $h 'print.isolationOverride').State | Should -Be 'absent'
            (Get-V $h 'print.queueCount').Value | Should -Be 1; (Get-V $h 'print.spooler').Value | Should -Be 'Running'; (Get-V $h 'print.spoolerStartMode').Value | Should -Be 'Auto'
            (Get-V $h 'print.operationalLog').Value | Should -BeFalse; (Get-V $h 'print.citrixPrintService').Value | Should -Be 'Running'; (Get-V $h 'print.mappingClientVersion').Value | Should -Be '6.2.1'
        }
        $script:WinFake.Logs = @($script:WinFake.Logs | Where-Object { $_ -ne 'Microsoft-Windows-PrintService/Operational' })
        (Get-V (Read-Health) 'print.operationalLog').State | Should -Be 'absent'
        $script:WinFake.Registry.Remove('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{C3}')                  # Review Focus 3: kein Client des Zuordnungswerkzeugs
        $m = Get-V (Read-Health) 'print.mappingClientVersion'; $m.State | Should -Be 'absent'; $m.Reason | Should -Be 'notInstalled'
    }
    It 'nennt die Richtlinie der Treiberisolierung nicht lesbar, wenn schon der Treiberleser sie nicht lesen konnte' {
        $script:WinFake.IsolationPolicyFail = New-Object System.Security.SecurityException 'kein Zugriff'
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null); [void]@(Get-WorkerPerfPrintDrivers 3>$null); $h = Get-WorkerPerfHealth 3>$null
        foreach ($id in 'print.isolationExecution', 'print.isolationOverride') { (Get-V $h $id).State | Should -Be 'unreadable' -Because $id; (Get-V $h $id).Reason | Should -Be 'rights' -Because $id }
        (Get-V $h 'print.spooler').State | Should -Be 'read'
    }
    It 'liest Defender, Filtertreiber, Dienste und AppLocker' {
        $h = Read-Health; $h.Areas['security'].Status | Should -Be 'read'
        (Get-V $h 'security.defenderMode').Value | Should -Be 'Normal'; (Get-V $h 'security.defenderSignatureAgeDays').Value | Should -Be 1; (Get-V $h 'security.defenderService').Value | Should -Be 'Running'
        (Get-V $h 'security.defenderExclusionProcesses').Value[0].Path | Should -Be 'C:\Program Files\Citrix\User Profile Manager\UserProfileManager.exe'
        (Get-V $h 'security.defenderExclusionExtensions').Value[0].Extension | Should -Be '.vhdx'; (Get-V $h 'security.defenderSharedSignatures').State | Should -Be 'absent'
        (Get-V $h 'security.mdeOnboarding').Value | Should -Be 1; (Get-V $h 'security.mdeService').Value | Should -Be 'Running'; (Get-V $h 'security.defenderForcePassive').State | Should -Be 'absent'
        @((Get-V $h 'security.filters').Value.Name) | Should -Be @('WdFilter', 'upmjit', 'FileInfo'); (Get-V $h 'security.filters').Value[0].Altitude | Should -Be '328010'
        @((Get-V $h 'security.services').Value).Count | Should -Be @($script:WinFake.Services).Count; ((Get-V $h 'security.services').Value | Where-Object Name -eq 'WinDefend').State | Should -Be 'Running'
        @((Get-V $h 'security.applockerCollections').Value.Collection) | Should -Be @('Exe', 'Dll')
        $dll = (Get-V $h 'security.applockerCollections').Value | Where-Object Collection -eq 'Dll'; $dll.Enforcement | Should -Be 1; $dll.Rules | Should -Be 1
        (Get-V $h 'security.defenderNetworkProtection').Value | Should -Be 0
    }
    It 'nennt verborgene Ausschluesse nicht lesbar und einen fehlenden Defender nicht installiert' {   # Review Focus 3
        $script:WinFake.Cim['MSFT_MpPreference'][0].ExclusionPath = @('N/A: Must be an administrator to view exclusions')
        $h = Read-Health; (Get-V $h 'security.defenderExclusionPaths').State | Should -Be 'unreadable'; (Get-V $h 'security.defenderExclusionPaths').Reason | Should -Be 'rights'
        (Get-V $h 'security.defenderExclusionProcesses').State | Should -Be 'read'; $h.Areas['security'].Status | Should -Be 'partial'
        $script:WinFake.FiltersFail = New-Object System.UnauthorizedAccessException 'Zugriff verweigert'
        (Get-V (Read-Health) 'security.filters').Reason | Should -Be 'rights'
        Reset-WinStandIns; $script:WinFake.Services = @($script:WinFake.Services | Where-Object Name -ne 'WinDefend')
        $h = Read-Health
        foreach ($id in 'security.defenderService', 'security.defenderMode', 'security.defenderExclusionPaths', 'maintenance.scanDay', 'maintenance.scanRandomize') {
            (Get-V $h $id).State | Should -Be 'absent' -Because $id; (Get-V $h $id).Reason | Should -Be 'notInstalled' -Because $id }
        @($script:WinFake.Calls.Keys | Where-Object { $_ -match 'MSFT_Mp' }) | Should -BeNullOrEmpty; (Get-V $h 'security.filters').State | Should -Be 'read'
    }
    It 'liest SMB, DNS und Zeitquelle und fasst die Verbindungen zusammen' {
        $h = Read-Health; $h.Areas['network'].Status | Should -Be 'read'
        $c = (Get-V $h 'network.smbConnections').Value; @($c).Count | Should -Be 2
        ($c | Where-Object Share -eq '\\fs01\upm$').Connections | Should -Be 2; ($c | Where-Object Share -eq '\\alt01\archiv').Dialect | Should -Be '2.1'; ($c | Where-Object Share -eq '\\alt01\archiv').Signed | Should -BeFalse
        (Get-V $h 'network.smb1').State | Should -Be 'absent'; (Get-V $h 'network.smb1').Reason | Should -Be ''
        (Get-V $h 'network.smbDirectoryCache').Value | Should -Be 16; (Get-V $h 'network.smbRequireSigning').Value | Should -BeFalse; (Get-V $h 'network.domainMember').Value | Should -BeTrue
        @((Get-V $h 'network.dnsServers').Value.Address) | Should -Be @('10.1.0.10'); (Get-V $h 'network.dnsServers').Value[0].Interface | Should -Be 4
        (Get-V $h 'network.timeType').Value | Should -Be 'NTP'; (Get-V $h 'network.timeServers').Value | Should -Be 'zeit01.klinik.example 10.1.0.20'; (Get-V $h 'network.timeService').Value | Should -Be 'Running'
        $rss = @((Get-V $h 'network.rss').Value); $rss.Count | Should -Be 1; $rss[0].Description | Should -Be 'vmxnet3 Ethernet Adapter'; $rss[0].Enabled | Should -BeTrue
        ($h | ConvertTo-Json -Depth 12) | Should -Not -Match 'Ethernet0'                                 # der Verbindungsname eines Adapters wird nicht gespeichert
        ($h | ConvertTo-Json -Depth 12) | Should -Not -Match 'KLINIK\\\\(mueller|gast)"'              # das Konto einer Verbindung wird nicht gespeichert
        $script:WinFake.Cim['Win32_SystemDriver'] = @([pscustomobject]@{ Name = 'mrxsmb10'; State = 'Running'; StartMode = 'Auto' })
        (Get-V (Read-Health) 'network.smb1').Value | Should -Be 'Auto'
    }
    It 'liest geplante Aufgaben, Scan- und Update-Zeitplaene' {
        $h = Read-Health; $h.Areas['maintenance'].Status | Should -Be 'read'
        $t = (Get-V $h 'maintenance.tasks').Value; @($t.Path) | Should -Be @('\Sim\Inventarlauf', '\Sim\Anmeldeskript')
        $t[0].Triggers | Should -Be 'daily'; $t[1].Triggers | Should -Be 'logon'; $t[1].NextRun | Should -Be 0; $t[0].Action | Should -Be 'C:\Tools\inventar.exe'
        [DateTimeOffset]::FromUnixTimeMilliseconds($t[0].NextRun).LocalDateTime.Hour | Should -Be 10
        (Get-V $h 'maintenance.taskCount').Value | Should -Be 150; ConvertTo-WorkerPerfTriggerWords @(9, 6, 9, 42) | Should -Be 'logon, idle, other'
        ConvertTo-WorkerPerfTaskTime ([datetime]'1899-12-30') | Should -Be ([datetime]::MinValue); ConvertTo-WorkerPerfTaskTime ([datetime]'2026-11-13T10:00:00') | Should -Be ([datetime]'2026-11-13T10:00:00')
        $t[0].LastRun | Should -Be 0; $t[1].LastRun | Should -Be 0                                    # der 30.12.1899 der Aufgabenplanung heisst: kein Lauf
        (Get-V $h 'maintenance.scanDay').Value | Should -Be 0; (Get-V $h 'maintenance.scanTime').Value | Should -Be '02:00'; (Get-V $h 'maintenance.scanRandomize').Value | Should -BeTrue
        (Get-V $h 'maintenance.updateOptions').Value | Should -Be 4; (Get-V $h 'maintenance.updateHour').Value | Should -Be 10
        (Get-V $h 'maintenance.searchService').State | Should -Be 'absent'; (Get-V $h 'maintenance.searchService').Reason | Should -Be 'notInstalled'
        (Get-V $h 'maintenance.updateService').Value | Should -Be 'Manual'
        $script:WinFake.Registry.Remove('SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU')
        (Get-V (Read-Health) 'maintenance.updateOptions').State | Should -Be 'absent'; (Get-V (Read-Health) 'maintenance.updateOptions').Reason | Should -Be ''
    }
    It 'liest Dienste, Sitzungen und Defender-Einstellungen fuer alle Bereiche einmal und die Richtlinie des Treiberlesers nicht noch einmal' {
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null); [void]@(Get-WorkerPerfPrintDrivers)
        $before = $script:WinFake.Calls.Clone(); $h = Get-WorkerPerfHealth
        foreach ($k in 'cim:Win32_Service', 'cim:Win32_SystemDriver', 'wts', 'cim:MSFT_MpPreference', 'cim:MSFT_MpComputerStatus', 'com:tasks', 'native:filters') { [int]$script:WinFake.Calls[$k] - [int]$before[$k] | Should -Be 1 -Because $k }
        [int]$script:WinFake.Calls['registry:print'] - [int]$before['registry:print'] | Should -Be 0
        @($h.Areas.Keys | Where-Object { $h.Areas[$_].Status -ne 'read' }) | Should -Be @('apps'); $h.DurationMs | Should -BeLessThan 60000      # apps hat bis Task 7 keinen Leser
        ($h.Areas.Values | ForEach-Object { $_.DurationMs } | Measure-Object -Sum).Sum | Should -BeLessOrEqual ($h.DurationMs + 1)
    }
    It 'haelt das Zeitlimit auch bei einem langsamen Aufruf ohne eigenes Zeitlimit ein' {   # Review Focus 1
        $script:WinFake.Delay['com:tasks'] = 1500; $script:WorkerPerfWinHealthAreaBudgetSec = 1
        try { $h = Read-Health } finally { $script:WorkerPerfWinHealthAreaBudgetSec = 10 }
        (Get-V $h 'maintenance.tasks').State | Should -Be 'read'                                 # der Aufruf lief schon; sein Ergebnis bleibt
        foreach ($id in 'maintenance.taskCount', 'maintenance.scanDay', 'maintenance.searchService') {
            (Get-V $h $id).State | Should -Be 'unreadable' -Because $id; (Get-V $h $id).Reason | Should -Be 'timeout' -Because $id }
        $h.Areas['maintenance'].Status | Should -Be 'partial'; foreach ($a in 'security', 'network', 'events') { $h.Areas[$a].Status | Should -Be 'read' -Because $a }
    }
    It 'speichert nur Zahlen, Wahrheitswerte, Texte und Listen daraus' {
        $script:WinFake.Cim['MSFT_MpPreference'][0].ScanScheduleQuickScanTime = [datetime]'2026-01-01T03:30:00'       # je nach Fassung der Plattform Zeitspanne oder Zeitpunkt
        $h = Read-Health; $bad = New-Object System.Collections.Generic.List[string]
        $plain = { param($x) $null -eq $x -or $x -is [string] -or $x -is [decimal] -or $x.GetType().IsPrimitive }
        foreach ($id in $WorkerPerfHealthValues.Keys) {
            $v = Get-V $h $id; if ($v.State -ne 'read') { continue }
            if ($WorkerPerfHealthValues[$id].Type -ne 'list') { if (-not (& $plain $v.Value)) { $bad.Add($id) }; continue }
            if ($v.Value -isnot [array]) { $bad.Add($id); continue }
            foreach ($item in $v.Value) { foreach ($k in @($item.Keys)) { if (-not (& $plain $item[$k])) { $bad.Add("$id.$k") } } }
        }
        $bad | Should -BeNullOrEmpty                                                             # keine Aufzaehlung, kein DateTime, keine Zeitspanne
        (Get-V $h 'maintenance.scanTime').Value | Should -Be '02:00'; (Get-V $h 'maintenance.quickScanTime').Value | Should -Be '03:30'
    }
    It 'zerlegt den Puffer der Filterabfrage und uebersetzt die Filterabfrage' {
        function New-FilterEntry([string]$Name, [string]$Altitude, [int]$Instances, [bool]$Legacy, [bool]$Last) {
            # FILTER_AGGREGATE_STANDARD_INFORMATION: NextEntryOffset (Byte 0), Flags (4: 1 Minifilter, 2 alter Filter). Minifilter: Flags (8), FrameID (12),
            # NumberOfInstances (16), dann je 2 Byte Namenslaenge, Namensoffset, Hoehenlaenge, Hoehenoffset (ab 20). Alter Filter: Flags (8), dieselben vier (ab 12).
            $n = [Text.Encoding]::Unicode.GetBytes($Name); $a = [Text.Encoding]::Unicode.GetBytes($Altitude); $head = $(if ($Legacy) { 20 } else { 28 })
            $size = [int]([Math]::Ceiling(($head + $n.Length + $a.Length) / 8) * 8) + 8; $b = New-Object byte[] $size
            for ($i = $head + $n.Length + $a.Length; $i -lt $size; $i++) { $b[$i] = 0x41 }                     # hinter den Zeichenketten steht keine Null
            $at = $(if ($Legacy) { 12 } else { 20 })
            [BitConverter]::GetBytes([uint32]$(if ($Last) { 0 } else { $size })).CopyTo($b, 0); [BitConverter]::GetBytes([uint32]$(if ($Legacy) { 2 } else { 1 })).CopyTo($b, 4)
            if (-not $Legacy) { [BitConverter]::GetBytes([uint32]$Instances).CopyTo($b, 16) }
            [BitConverter]::GetBytes([uint16]$n.Length).CopyTo($b, $at); [BitConverter]::GetBytes([uint16]$head).CopyTo($b, $at + 2)
            [BitConverter]::GetBytes([uint16]$a.Length).CopyTo($b, $at + 4); [BitConverter]::GetBytes([uint16]($head + $n.Length)).CopyTo($b, $at + 6)
            $n.CopyTo($b, $head); $a.CopyTo($b, $head + $n.Length); , $b
        }
        $buf = [byte[]]((New-FilterEntry 'WdFilter' '328010' 4 $false $false) + (New-FilterEntry 'upmAction' '265650.5' 2 $false $false) + (New-FilterEntry 'AltFilter' '45000' 0 $true $true))
        $f = @(ConvertFrom-WorkerPerfFilterBuffer $buf)
        @($f.Name) | Should -Be @('WdFilter', 'upmAction', 'AltFilter'); @($f.Altitude) | Should -Be @('328010', '265650.5', '45000')
        @($f.Instances) | Should -Be @(4, 2, 0); @($f.Legacy) | Should -Be @($false, $false, $true)
        @(ConvertFrom-WorkerPerfFilterBuffer ([byte[]]@())).Count | Should -Be 0
        Register-WorkerPerfHealthType; ('WorkerPerf.HealthNative' -as [type]).GetMethod('GetFilterBuffers') | Should -Not -BeNullOrEmpty
    }
    It 'enthaelt keinen Aufruf, der etwas aendert, startet oder einen anderen Rechner anspricht' {
        $src = Get-Content (Join-Path $PSScriptRoot '../src/WorkerPerf.Sources.Windows.ps1') -Raw
        foreach ($bad in 'Microsoft\.Update\.', 'w32tm', 'powercfg', 'fltmc', 'Win32_Product\b', 'Get-MpPreference', 'Get-MpComputerStatus', 'Get-SmbConnection', 'Get-ScheduledTask',
            'Get-AppLockerPolicy', 'Get-Printer\b', 'Get-AppxPackage', 'Get-NetAdapterRss', 'Get-ScheduledTaskInfo', 'VMwareToolboxCmd', 'cscript', 'HKEY_USERS', 'HKCU', 'Start-Process', 'Start-Service', 'Invoke-CimMethod', '-ComputerName', 'New-CimSession') { $src | Should -Not -Match $bad -Because $bad }
        # nichts wird geschrieben, geloescht, angehalten oder ausgefuehrt (Entwurf 3.4)
        foreach ($bad in 'CreateSubKey', 'SetValue', 'DeleteValue', 'DeleteSubKey', 'OpenSubKey\([^)]*\$true', 'Set-ItemProperty', 'New-ItemProperty', 'Remove-ItemProperty', 'Remove-Item\b',
            'Stop-Service', 'Set-Service', 'Stop-Process', '\.Run\(') { $src | Should -Not -Match $bad -Because $bad }
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/WindowsHealth.Tests.ps1`
Expected: FAIL, der Bereich `print` hat den Zustand `failed` (`noReader`)

- [ ] **Step 3: Platzhalter ergänzen; die dünnen Aufrufe, `ConvertTo-WorkerPerfTriggerWords`, `ConvertFrom-WorkerPerfFilterBuffer` und die vier Leser umsetzen** (C#: `FilterFindFirst(int, IntPtr, int, out int, out IntPtr)`, `FilterFindNext`, `FilterFindClose` aus `fltlib.dll` mit der Informationsklasse `FilterAggregateStandardInformation`; die Funktionen geben ein HRESULT zurück und werfen nicht: `0x80070103` (keine weiteren Einträge) beendet die Liste, `0x8007007A` (Puffer zu klein) wiederholt den Aufruf mit der gemeldeten Größe, jedes andere wird mit `Marshal.ThrowExceptionForHR` zur Ausnahme, damit verweigerter Zugriff als `rights` erkannt wird; `GetFilterBuffers` gibt je Aufruf den gefüllten Teil des Puffers zurück und schließt das Suchhandle in `finally`)

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Sources.Windows.ps1 tests/WindowsStandIns.ps1 tests/WindowsHealth.Tests.ps1
git commit -m "Read printing, security products, network and maintenance state of the worker"
```

---

### Task 7: Windows – Bereich Anwendungen

**Files:**
- Modify: `src/WorkerPerf.Sources.Windows.ps1`, `tests/WindowsStandIns.ps1`
- Test: `tests/WindowsHealth.Tests.ps1`
- Mit dem geführten Bericht geteilt: keine. Nicht anfassen: `src/apps.json` (Task 2), `src/WorkerPerf.Common.ps1` (der Leser kennt keine Anwendung beim Namen: was er liest, steht in der Anwendungsliste), `src/Test-WorkerPerfSources.ps1`.

**Interfaces:**
- Consumes: Task 1b (`Get-WorkerPerfAppRows`), Task 2 (`src/apps.json`, `New-TestAppFile`), Task 4 (`Set-WorkerPerfWinHealthValue`, `Get-WorkerPerfWinHealthFailReason`, `Get-WorkerPerfWinHealthShared`, `Get-WorkerPerfRegistryValues`, `Shared['services']`, der Zustand `Apps`), Task 5 (`Get-WorkerPerfFileVersion`), Task 6 (`ConvertTo-WorkerPerfTaskTime`).
- Produces:
  - Dünne Windows-Aufrufe mit Platzhalter:
    - `Get-WorkerPerfTaskInfo([string]$Path) -> $null | @{ Enabled; LastRun; NextRun }`: eine Aufgabe über ihren vollen Pfad (lokales Objekt `Schedule.Service`, `Connect()` ohne Servernamen, `GetFolder(<Ordner>)`, `GetTask(<Name>)`; `LastRun`/`NextRun` als `datetime`, wie die Aufgabenplanung sie liefert); `$null`, wenn Ordner oder Aufgabe fehlt (HRESULT `0x80070002` oder `0x80070003`); jedes COM-Objekt wird freigegeben. Zähler `com:task`; Platzhalter aus `$script:WinFake.TaskByPath` (Pfad → Tabelle).
    - `Get-WorkerPerfFileProbe([string]$Path) -> $null | @{ Version }`: eine Datei oder ein Ordner. Ein `*` in einem Ordnernamen wird über die Aufzählung des Ordners davor aufgelöst (`[System.IO.Directory]::GetDirectories(<Ordner>, <Muster>)`), dahinter folgt der Rest des Pfads; gibt es mehrere Treffer, zählt der mit der höchsten Version (verglichen als `[version]`; lässt sich eine nicht so lesen, der letzte nach dem Namen). `Version` ist `Get-WorkerPerfFileVersion` der Datei, `''` für einen Ordner oder eine Datei ohne Versionsangabe; `$null`, wenn nichts da ist. Zähler `file:probe`; Platzhalter aus `$script:WinFake.FileVersions` (Schlüssel über `-like`), Ausnahme aus `$script:WinFake.FileProbeFail` (Pfadmuster → Ausnahme).
  - Leser `Read-WorkerPerfWinHealthApps($Ctx)`, eingetragen in `$script:WorkerPerfWinHealthReaders` (danach hat jeder der elf Bereiche einen Leser): setzt `apps.probes` über `Set-WorkerPerfWinHealthValue` mit den Zeilen aus `Get-WorkerPerfAppRows -Apps <Apps des Zustands> -Read <fünf Leser> -FailReason { param($e) Get-WorkerPerfWinHealthFailReason $Ctx $e } -Expired { <Limit des Bereichs erreicht> }`. Die fünf Leser:
    - `registryValue`, `registryKey`: `Get-WorkerPerfRegistryValues` mit dem Pfad ohne `HKLM\`, je Schlüssel einmal je Aufruf von `Get-WorkerPerfHealth` (`Get-WorkerPerfWinHealthShared $Ctx "registry:<Schlüssel>"`); `ValueCount` = Zahl der Werte, `SubKeyCount` = Zahl der Unterschlüssel; Wertnamen ohne Rücksicht auf Groß- und Kleinschreibung.
    - `service`: aus `Shared['services']` der Dienst mit diesem `Name` bzw. `DisplayName` (ohne Rücksicht auf Groß- und Kleinschreibung).
    - `scheduledTask`: `Get-WorkerPerfTaskInfo`, `LastRun` und `NextRun` über `ConvertTo-WorkerPerfTaskTime` (der 30.12.1899 der Aufgabenplanung wird `MinValue`, also „kein Lauf"); `file`: `Get-WorkerPerfFileProbe`.
- Produces (Platzhalter, Vorgaben nach `Reset-WinStandIns`): `FileVersions` zusätzlich: `C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe` → „130.0.2849.80"; `C:\Program Files\WindowsApps\MSTeams_24193.1805.3040.8975_x64__8wekyb3d8bbwe\ms-teams.exe` → „24193.1805.3040.8975" und `C:\Program Files\WindowsApps\MSTeams_24277.3502.3161.3007_x64__8wekyb3d8bbwe\ms-teams.exe` → „24277.3502.3161.3007" (zwei Ordner); `C:\Program Files (x86)\Microsoft\TeamsMeetingAdd-in` → `''`. `Registry` zusätzlich: `SOFTWARE\Microsoft\Office\ClickToRun\Configuration` (`UpdateChannel` „http://officecdn.microsoft.com/pr/00000000-0000-0000-0000-000000000000", `UpdateUrl` `\\fs01\office$\updates`, `VersionToReport` „16.0.17932.20162", `Platform` „x64", `UpdatesEnabled` „False"); `SOFTWARE\Policies\Microsoft\office\16.0\Common\officeupdate` (`hideenabledisableupdates` 1); `SOFTWARE\Policies\Microsoft\Edge` (`StartupBoostEnabled` 0, `SleepingTabsEnabled` 0, `UserDataDir` `\\fs01\edge$\daten`); `SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist` (`1` „abcdefghijklmnopabcdefghijklmnop", `2` „ponmlkjihgfedcbaponmlkjihgfedcba;https://intern.klinik.example/ext"); `SOFTWARE\Policies\Microsoft\EdgeUpdate` (`UpdateDefault` 0); `SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}` (`pv` „130.0.2849.80"); `SOFTWARE\Microsoft\Teams` (`disableAutoUpdate` 1); `SOFTWARE\Microsoft\Office\Outlook\Addins` mit den Unterschlüsseln `Sim.Addin1` und `Sim.Addin2`. `TaskByPath`: `\Microsoft\Office\Office Automatic Updates 2.0` (`Enabled` wahr, `LastRun` jetzt − 1 Tag, `NextRun` morgen 03:00). `Services` zusätzlich: `edgeupdate` (`Stopped`, `Manual`).

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/WindowsHealth.Tests.ps1`, neuer Block; im Test aus Task 6 „liest Dienste, Sitzungen und Defender-Einstellungen …" wird `Should -Be @('apps')` wieder zu `Should -BeNullOrEmpty`)

```powershell
Describe 'Zustandsbild unter Windows: Anwendungen' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        $script:Apps = @(Read-WorkerPerfHealthApps (Join-Path $PSScriptRoot '../src/apps.json')); $script:TestApps = @(Read-WorkerPerfHealthApps (New-TestAppFile $TestDrive))
        function Get-Row($H, [string]$App, [string]$Id) { (Get-V $H 'apps.probes').Value | Where-Object { $_.App -eq $App -and $_.Id -eq $Id } }
    }
    BeforeEach { Reset-WinStandIns }
    It 'liest die Proben der ausgelieferten Anwendungsliste' {
        $h = Read-Health @() $Apps; $h.Areas['apps'].Status | Should -Be 'read'; @((Get-V $h 'apps.probes').Value).Count | Should -Be 38
        foreach ($k in 'edge', 'office', 'teams') { (Get-Row $h $k 'installed').Value | Should -BeTrue -Because $k }
        (Get-Row $h 'edge' 'version').Value | Should -Be '130.0.2849.80'; (Get-Row $h 'edge' 'webview2Version').Value | Should -Be '130.0.2849.80'
        (Get-Row $h 'edge' 'updateDefault').Value | Should -Be 0; (Get-Row $h 'edge' 'sleepingTabs').Value | Should -Be 0; (Get-Row $h 'edge' 'backgroundMode').State | Should -Be 'absent'
        (Get-Row $h 'edge' 'backgroundMode').Reason | Should -Be ''                                            # nicht gesetzt ist nicht "nicht lesbar"
        (Get-Row $h 'edge' 'userDataDir').Names | Should -Be '\\fs01\edge$\daten'; (Get-Row $h 'edge' 'userDataDir').Value | Should -BeNullOrEmpty
        (Get-Row $h 'edge' 'forcedExtensions').Value | Should -Be 2; (Get-Row $h 'edge' 'updateService').Value | Should -Be 'Manual'
        ($h | ConvertTo-Json -Depth 12) | Should -Not -Match 'intern\.klinik\.example'                          # von den Erweiterungen nur die Zahl
        (Get-Row $h 'office' 'updateTask').Value | Should -BeTrue; (Get-Row $h 'office' 'hideEnableDisableUpdates').Value | Should -Be 1; (Get-Row $h 'office' 'hideUpdateNotifications').State | Should -Be 'absent'
        (Get-Row $h 'office' 'outlookAddins').Value | Should -Be 2; (Get-Row $h 'office' 'outlookAddinsWow').State | Should -Be 'absent'; (Get-Row $h 'office' 'platform').Value | Should -Be 'x64'
        (Get-Row $h 'office' 'updateUrl').Names | Should -Be '\\fs01\office$\updates'
        (Get-Row $h 'teams' 'version').Value | Should -Be '24277.3502.3161.3007'                                 # zwei Ordner: die hoechste Version
        (Get-Row $h 'teams' 'disableAutoUpdate').Value | Should -Be 1; (Get-Row $h 'teams' 'disableFallback').State | Should -Be 'absent'
        (Get-Row $h 'teams' 'meetingAddin').Value | Should -BeTrue; (Get-Row $h 'teams' 'classicTeams').Value | Should -BeFalse
        [int]$script:WinFake.Calls['registry:SOFTWARE\Policies\Microsoft\Edge'] | Should -Be 1                   # sieben Proben, ein Lesen des Schluessels
    }
    It 'liest eine nicht installierte Anwendung nicht und nennt sie nicht installiert' {   # Review Focus 3
        foreach ($k in @($script:WinFake.FileVersions.Keys | Where-Object { $_ -like '*MSTeams_*' })) { $script:WinFake.FileVersions.Remove($k) }
        $h = Read-Health @() $Apps
        (Get-Row $h 'teams' 'installed').State | Should -Be 'read'; (Get-Row $h 'teams' 'installed').Value | Should -BeFalse
        foreach ($id in 'version', 'disableAutoUpdate', 'disableFallback', 'maxFps', 'meetingAddin', 'classicTeams', 'webview2Version') {
            (Get-Row $h 'teams' $id).State | Should -Be 'absent' -Because $id; (Get-Row $h 'teams' $id).Reason | Should -Be 'notInstalled' -Because $id }
        $script:WinFake.Calls.Keys | Should -Not -Contain 'registry:SOFTWARE\Microsoft\Teams'
        (Get-Row $h 'edge' 'installed').Value | Should -BeTrue; $h.Areas['apps'].Status | Should -Be 'read'
        @((Get-V (Read-Health) 'apps.probes').Value).Count | Should -Be 0                                       # ohne Anwendungsliste: gelesen und leer
    }
    It 'liest eine vierte Anwendung, die nur in einer Testdatei beschrieben ist, ohne Aenderung am Code' {
        $h = Read-Health @() $TestApps; (Get-Row $h 'simapp' 'installed').Value | Should -BeFalse; (Get-Row $h 'simapp' 'cacheMode').Reason | Should -Be 'notInstalled'
        $script:WinFake.FileVersions['C:\Program Files\SimApp\simapp.exe'] = '4.2.0'
        $script:WinFake.Registry['SOFTWARE\SimApp'] = [ordered]@{ CacheMode = 2; DataPath = '\\fs01\simapp$\daten' }
        $h = Read-Health @() $TestApps; @((Get-V $h 'apps.probes').Value).Count | Should -Be 42
        (Get-Row $h 'simapp' 'installed').Value | Should -BeTrue; (Get-Row $h 'simapp' 'version').Value | Should -Be '4.2.0'; (Get-Row $h 'simapp' 'cacheMode').Value | Should -Be 2
        (Get-Row $h 'simapp' 'dataPath').Names | Should -Be '\\fs01\simapp$\daten'; (Get-Row $h 'simapp' 'dataPath').Value | Should -BeNullOrEmpty
        (Get-Content (Join-Path $PSScriptRoot '../src/WorkerPerf.Sources.Windows.ps1') -Raw) | Should -Not -Match 'msedge|MSTeams|ClickToRun|SimApp'      # der Leser kennt keine Anwendung
    }
    It 'laesst die anderen Proben stehen, wenn eine scheitert, und haelt das Zeitlimit ein' {   # Review Focus 1
        $script:WinFake.RegistryFail['SOFTWARE\Policies\Microsoft\Edge'] = New-Object System.Security.SecurityException 'kein Zugriff'
        $h = Read-Health @() $Apps
        (Get-Row $h 'edge' 'sleepingTabs').State | Should -Be 'unreadable'; (Get-Row $h 'edge' 'sleepingTabs').Reason | Should -Be 'rights'
        (Get-Row $h 'edge' 'updateDefault').State | Should -Be 'read'; (Get-Row $h 'office' 'updateTask').State | Should -Be 'read'; $h.Areas['apps'].Status | Should -Be 'read'
        Reset-WinStandIns; $script:WinFake.FileProbeFail['*msedge.exe'] = New-Object System.UnauthorizedAccessException 'Zugriff verweigert'
        $h = Read-Health @() $Apps; @((Get-V $h 'apps.probes').Value | Where-Object { $_.App -eq 'edge' -and ($_.State -ne 'unreadable' -or $_.Reason -ne 'rights') }).Count | Should -Be 0
        (Get-Row $h 'office' 'installed').Value | Should -BeTrue                                               # die Installation einer Anwendung nicht lesbar: die anderen bleiben
        Reset-WinStandIns; $script:WinFake.Delay['registry:SOFTWARE\Policies\Microsoft\EdgeUpdate'] = 1500; $script:WorkerPerfWinHealthAreaBudgetSec = 1
        try { $h = Read-Health @() $Apps } finally { $script:WorkerPerfWinHealthAreaBudgetSec = 10 }
        (Get-Row $h 'edge' 'version').State | Should -Be 'read'; (Get-Row $h 'edge' 'updateDefault').State | Should -Be 'read'       # der Aufruf lief schon
        (Get-Row $h 'edge' 'startupBoost').Reason | Should -Be 'timeout'; (Get-Row $h 'teams' 'installed').Reason | Should -Be 'timeout'
        $script:WinFake.Calls.Keys | Should -Not -Contain 'registry:SOFTWARE\Microsoft\Teams'; $h.Areas['events'].Status | Should -Be 'read'
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/WindowsHealth.Tests.ps1`
Expected: FAIL, der Bereich `apps` hat den Zustand `failed` (`noReader`)

- [ ] **Step 3: Platzhalter ergänzen; `Get-WorkerPerfTaskInfo`, `Get-WorkerPerfFileProbe` und den Leser umsetzen**

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Sources.Windows.ps1 tests/WindowsStandIns.ps1 tests/WindowsHealth.Tests.ps1
git commit -m "Read the applications of the application list through five fixed probe kinds"
```

---

### Task 8: Collector – Kategorie aktiv, `health.json` schreiben, `-Skip Zustand`

**Files:**
- Modify: `src/WorkerPerf.Common.ps1` (Zeile `Zustand` und ihr Kommentar), `src/WorkerPerf.Capture.ps1`, `src/Start-WorkerPerfCapture.ps1` (Aufruf, `$sourceNames`, `-AppsFile` mit Lesen und Kopie der Anwendungsliste, Hilfe), `src/WorkerPerf.Sources.Simulation.ps1` und `src/WorkerPerf.Sources.Windows.ps1` (Eintrag `health` in `Sources`), `src/texts.de.json`, `tests/TestHelpers.ps1` (`New-SkipRuns`), `.gitignore` (zwei Zeilen)
- Test: `tests/Capture.Tests.ps1`, `tests/Skip.Tests.ps1`, `tests/Common.Tests.ps1`, `tests/Load.Tests.ps1`, `tests/Mask.Tests.ps1`
- Mit dem geführten Bericht geteilt: `src/texts.de.json` (vier neue Schlüssel in eigenen Zeilen hinter `skip.text.Gegenstellen`), `tests/TestHelpers.ps1` (eine Zeile in `New-SkipRuns`), `tests/Skip.Tests.ps1`, `tests/Mask.Tests.ps1` (eine Zeile im Test 'Vermerk einer weggelassenen Kategorie'; Task 7 des geführten Berichts ändert dieselbe Datei an anderen Stellen). Nicht anfassen: `tests/report-browser.js`, `src/report-template.html`, `README.md` (die Seite zeigt eine weggelassene Kategorie `Zustand` schon heute in der Kopfzeile; ihre Stelle folgt in Task 20, das README in Task 21).

**Interfaces:**
- Consumes: Tasks 1–7 (darunter `Read-WorkerPerfHealthApps` und der Parameter `-Apps` beider Quellen); `Save-WorkerPerfMeta` (Vorbild), `Register-SourceError`, `Set-WorkerPerfSkippedSources`.
- Produces:
  - Tabellenzeile `'Zustand' = @{ Files = @('health.json'); Sources = @('health'); Places = @(); Active = $true }`. `Files` darf damit eine Datei nennen, die keine CSV-Datei ist; die Schreiber entstehen weiter nur aus `$script:WorkerPerfHeaders`.
  - `Save-WorkerPerfHealth -Path <Datei> -Health <Zustandsbild>` (`src/WorkerPerf.Capture.ps1`): `ConvertTo-Json -InputObject $Health -Depth 10`, UTF-8 ohne BOM, erst `<Datei>.tmp`, dann löschen und verschieben wie `Save-WorkerPerfMeta`.
  - `Format-WorkerPerfHealthLine($Health) -> string` (`src/WorkerPerf.Capture.ps1`): `Zustandsbild: <n> Bereiche gelesen, <m> unvollstaendig (<Kennungen mit Komma>), <s> s`; ohne unvollständigen Bereich `Zustandsbild: 11 Bereiche gelesen, <s> s`. „Gelesen" ist `Status` = `read`; `<s>` sind Sekunden mit einer Nachkommastelle und Punkt.
  - Parameter `[string]$AppsFile` des Collectors (derselbe Name wie am Berichtsskript; Vorgabe `apps.json` neben dem Skript; Hilfe: `Application list for the health picture (area Anwendungen). Default: apps.json next to this script.`). Nur wenn `Zustand` nicht weggelassen ist: `Read-WorkerPerfHealthApps $AppsFile` direkt nach dem Lesen der Schwellen und bevor der Ordner der Aufzeichnung angelegt wird (eine fehlende oder fehlerhafte Liste bricht mit ihrer Meldung ab, nichts ist angelegt); die Liste geht als `-Apps` an `Initialize-WorkerPerfSource`; die Datei wird wie `thresholds.json` als `apps.json` in den Ordner der Aufzeichnung kopiert. Mit `-Skip Zustand` wird sie weder gelesen noch kopiert.
  - Collector, nach der Treiberliste und vor `$scheduleStart`: nur wenn `$leftOut -notcontains 'Zustand'`: `Get-WorkerPerfHealth` in `try`; ein Ergebnis wird mit `Save-WorkerPerfHealth` nach `<Lauf>\health.json` geschrieben und `Format-WorkerPerfHealthLine` mit `Write-Host` ausgegeben; `catch { Register-SourceError 'health' $_ }`. `$sourceNames` erhält `health = 'Zustandsbild'`.
  - `Initialize-WorkerPerfSource` beider Quellen trägt `Sources['health'] = @{ Available = $true; Detail = … }` ein, wenn `Zustand` nicht weggelassen ist (Simulation `'Simulation'`, Windows `'einmal beim Start gelesen'`).
  - Texte: `skip.label.Zustand` „Zustandsbild", `skip.text.Zustand` „Das Zustandsbild des Workers wurde bei dieser Messung nicht gelesen.", `source.health` „Zustandsbild des Workers", `sourcecall.health` „Zustandsbild lesen".
  - Hilfe: die Zeile `Zustand` unter `-Skip` lautet `Zustand       the health picture of the worker, read once at the start (health.json)`.
  - `New-SkipRuns` (`tests/TestHelpers.ps1`): zusätzlich der Lauf `Zustand` (`-Skip Zustand`) nach den sieben Kategorien und vor `Alle`; `Alle` bleibt bei den sieben (Task 20 nimmt `Zustand` dazu, wenn die Seite die Stelle hat). `New-SkipReports` schreibt damit `report-skip-zustand.html`.
  - `.gitignore`: unter den Dateien einer Aufzeichnung die Zeilen `health.json` und `health.json.tmp` (die Datei trägt Server-, Freigabe- und Kontennamen unverändert; der Katalog `src/health.de.json` ist davon nicht betroffen).

Aussagen bestehender Tests, die sich mit der Aktivierung ändern (Entwurf, Anhang Punkt 3):
- `tests/Common.Tests.ps1`: `Resolve-WorkerPerfSkip @('Drucken,citrix', ' Zustand ', '')` ergibt `@('Citrix', 'Drucken', 'Zustand')`; keine Kategorie ist mehr inaktiv (`Should -BeNullOrEmpty` statt `@('Zustand')`); neu: `$WorkerPerfCategories.Zustand.Files | Should -Be @('health.json')`, `.Sources | Should -Be @('health')`.
- `tests/Skip.Tests.ps1`: die Startmeldungen enden auf `…, Gegenstellen, Zustand`; der Lauf mit `-EventLookbackDays 0 -Skip 'rueckblick,RUECKBLICK', 'Zustand'` verliert den Wert `'Zustand'` und die zwei Aussagen dazu („angenommen, ohne Wirkung" gilt nicht mehr); die Tabellen erhalten `$Files.Zustand = @('health.json')`, `$Ids.Zustand = @('health')`, `$Places.Zustand = @()`; die Schleife über die Läufe und die beiden `-ForEach`-Listen erhalten `'Zustand'`; die Liste der werfenden Funktionen im Test „ruft die Quelle für eine weggelassene Kategorie nicht auf" erhält `Get-WorkerPerfHealth`, und dieser Lauf lässt zusätzlich `Zustand` weg.
- `tests/Load.Tests.ps1`: `"Skip":["rueckblick","Netz","Zustand","Prozesse"]` ergibt `@('Prozesse', 'Rueckblick', 'Zustand')`; `Get-WorkerPerfRecordedSkip @($null, 5, '', 'Zustand')` ergibt `@('Zustand')`.
- `tests/Mask.Tests.ps1`: `'abgeschaltet (-Skip Zustand)'` wandert aus der Liste der Texte, die geleert werden, in die Liste der gültigen Vermerke.
- Wo ein bestehender Test die Dateien eines Aufzeichnungsordners aufzählt (`tests/Skip.Tests.ps1`, `tests/Capture.Tests.ps1`), kommt `apps.json` dazu, außer im Lauf mit `-Skip Zustand` und im Lauf `Alle` ab Task 20. `apps.json` ist wie `thresholds.json` eine Kopie der Einstellungen und steht nicht in `Files` der Kategorie.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (die geänderten Aussagen oben im selben Schritt)

`tests/Capture.Tests.ps1`:

```powershell
Describe 'Zustandsbild schreiben' {
    It 'schreibt geschachtelte Werte vollstaendig, ueber eine temporaere Datei, und fasst das Lesen in einer Zeile zusammen' {
        $v = @{ 'profile.containers' = (New-WorkerPerfHealthValue 'read' '' @([ordered]@{ Location = '\\fs01\profile$\a.vhdx'; UsedPct = 96.5 })) }
        $h = New-WorkerPerfHealth ([datetime]::Now) 4210 @{ profile = (Complete-WorkerPerfHealthArea 'profile' $v 5) }
        $file = Join-Path $TestDrive 'health.json'; Save-WorkerPerfHealth -Path $file -Health $h; Save-WorkerPerfHealth -Path $file -Health $h
        $j = Get-Content $file -Raw | ConvertFrom-Json
        $j.Areas.profile.Values.'profile.containers'.Value[0].UsedPct | Should -Be 96.5; $j.Areas.profile.Values.'profile.containers'.Value[0].Location | Should -Be '\\fs01\profile$\a.vhdx'
        [IO.File]::ReadAllBytes($file)[0] | Should -Be ([byte][char]'{'); Test-Path ($file + '.tmp') | Should -BeFalse
        Format-WorkerPerfHealthLine $h | Should -Be 'Zustandsbild: 0 Bereiche gelesen, 11 unvollstaendig (size, operation, sessions, vda, profile, print, security, network, events, maintenance, apps), 4.2 s'
        $all = @{}; foreach ($a in $WorkerPerfHealthAreas) { $vals = @{}; foreach ($id in @($WorkerPerfHealthValues.Keys | Where-Object { $WorkerPerfHealthValues[$_].Area -eq $a })) { $vals[$id] = New-WorkerPerfHealthValue 'absent' }
            $all[$a] = Complete-WorkerPerfHealthArea $a $vals 1 }
        Format-WorkerPerfHealthLine (New-WorkerPerfHealth ([datetime]::Now) 0 $all) | Should -Be 'Zustandsbild: 11 Bereiche gelesen, 0.0 s'
    }
}
```

`tests/Skip.Tests.ps1`:

```powershell
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
        @($D.Zustand.skipped.id) | Should -Be @('Zustand'); $D.Zustand.skipped[0].text | Should -Be 'Das Zustandsbild des Workers wurde bei dieser Messung nicht gelesen.'
    }
    It 'liest die Anwendungsliste beim Start, kopiert sie und lehnt eine fehlerhafte ab, bevor etwas angelegt ist' {
        $shipped = Join-Path $PSScriptRoot '../src/apps.json'
        (Get-Content (Join-Path $Runs.Voll 'apps.json') -Raw) | Should -Be (Get-Content $shipped -Raw); Test-Path (Join-Path $Runs.Zustand 'apps.json') | Should -BeFalse
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
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "& ./tests/Invoke-Tests.ps1 -Path tests/Capture.Tests.ps1, tests/Skip.Tests.ps1, tests/Common.Tests.ps1, tests/Load.Tests.ps1, tests/Mask.Tests.ps1"`
Expected: FAIL in jeder der fünf Dateien: `Save-WorkerPerfHealth` ist nicht definiert (`tests/Capture.Tests.ps1`); `health.json` fehlt und die Startmeldung nennt `Zustand` nicht (`tests/Skip.Tests.ps1`); `Resolve-WorkerPerfSkip` liefert `Zustand` nicht und die Kategorie gilt noch als inaktiv (`tests/Common.Tests.ps1`); `Zustand` fehlt in der gelesenen Liste (`tests/Load.Tests.ps1`); der Vermerk `abgeschaltet (-Skip Zustand)` wird noch geleert (`tests/Mask.Tests.ps1`)

- [ ] **Step 3: Tabellenzeile, Texte, `Save-WorkerPerfHealth`, `Format-WorkerPerfHealthLine`, den Aufruf im Collector mit `-AppsFile` und der Kopie der Anwendungsliste, die Einträge `health` der Quellen, die Hilfe, den Lauf `Zustand` in `New-SkipRuns` und die zwei Zeilen in `.gitignore` umsetzen**

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1` und die Browserprüfungen (die Seite ist unverändert und bleibt grün); danach `git check-ignore -q irgendwo/health.json && git check-ignore -q irgendwo/health.json.tmp && ! git check-ignore -q src/health.de.json; echo $?`
Expected: `Failed: 0`, `browser checks passed: <n>`, `0`

- [ ] **Step 5: Commit**

```bash
git add .gitignore src/WorkerPerf.Common.ps1 src/WorkerPerf.Capture.ps1 src/Start-WorkerPerfCapture.ps1 src/WorkerPerf.Sources.Simulation.ps1 src/WorkerPerf.Sources.Windows.ps1 src/texts.de.json tests/TestHelpers.ps1 tests/Capture.Tests.ps1 tests/Skip.Tests.ps1 tests/Common.Tests.ps1 tests/Load.Tests.ps1 tests/Mask.Tests.ps1
git commit -m "Record the health picture at the start of every capture"
```

---

### Task 9: Collector – Schnelllauf `-HealthOnly`

**Files:**
- Modify: `src/Start-WorkerPerfCapture.ps1`, `src/WorkerPerf.Capture.ps1` (`New-WorkerPerfWriters`), `tests/TestHelpers.ps1` (neue Funktion am Ende)
- Create: `tests/HealthOnly.Tests.ps1`
- Test: `tests/Skip.Tests.ps1` (Feldliste von `meta.json`)
- Mit dem geführten Bericht geteilt: `tests/TestHelpers.ps1`, `tests/Skip.Tests.ps1`. Nicht anfassen: `src/WorkerPerf.Load.ps1` (Task 10), `src/New-WorkerPerfReport.ps1` (Task 17).

**Interfaces:**
- Consumes: Task 8; `New-TestAppFile` (Task 2).
- Produces:
  - Parameter `[switch]$HealthOnly` mit Hilfe („reads only the health picture, the lookback and the print driver list and ends; no measurement").
  - Ablehnungen direkt nach `Resolve-WorkerPerfSkip`, bevor etwas angelegt wird: mit `Zustand` in `$leftOut`: `-HealthOnly und -Skip Zustand schliessen sich aus: der Schnelllauf besteht aus dem Zustandsbild.`; mit einem der Parameter `FastIntervalSeconds`, `IntervalSeconds`, `BurstIntervalSeconds`, `BurstHoldSeconds`, `DurationMinutes`, `MaxSizeMB`, `ThresholdFile`, `EndpointFile`, `IncludeCommandLine`, `NoCitrix`, `CitrixMetricFilter` in `$PSBoundParameters`: `-HealthOnly liest nur das Zustandsbild, den Rueckblick und die Treiberliste; nicht zusammen mit: <die angegebenen, in dieser Reihenfolge, als -Name mit Komma>.`
  - Ablauf mit `-HealthOnly`: keine Schwellen- und Gegenstellendatei (die Anwendungsliste wird gelesen und kopiert wie in der Messung; `-AppsFile` gilt und steht nicht unter den abgelehnten Parametern); mit `-Simulate` keine Prüfung der Dauer; `Initialize-WorkerPerfSource -Skip` = `$leftOut` und dazu `Prozesse`, `Laufwerke`, `Citrix`, `Ereignisse`, `Gegenstellen`; `New-WorkerPerfWriters -Only @('events_before.csv', 'printdrivers.csv')`; keine Kopie von `thresholds.json`; Konsole `WorkerPerf-Schnelllauf laeuft: <Ordner>`, `Gelesen wird: Zustandsbild, Rueckblick, Treiberliste` (ohne die weggelassenen) und `Nicht gelesen (-Skip): <Liste oder keine>`; Rückblick, Treiberliste und Zustandsbild wie in der Messung; danach `$endReason = 'healthonly'`. Grundmessung, Planung, Schleife und Nachlauf der Proben laufen nur ohne `-HealthOnly`. Im Abschluss kein `expected.json`; letzte Zeile `Schnelllauf beendet: <Ordner>`; ausgegeben wird der Ordner wie bisher.
  - `meta.json`: neues Feld `HealthOnly` (boolesch, immer geschrieben) hinter `Simulated`; im Schnelllauf `Skip` = `$leftOut`, `Ticks` und `Snapshots` 0, `EndReason` `healthonly`; `SchemaVersion` bleibt 3.
  - `New-WorkerPerfWriters -RunDir -Skip [-Only <string[]>]`: mit `-Only` entstehen nur die genannten Dateien (ohne die weggelassener Kategorien).
  - `Invoke-SimHealthOnly([string]$OutDir, [hashtable]$Extra = @{}, [string]$ConsoleFile = '')` (`tests/TestHelpers.ps1`): wie `Invoke-SimCapture`, ruft `-Simulate -HealthOnly -OutputPath $OutDir @Extra`; liefert den Aufzeichnungsordner.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/HealthOnly.Tests.ps1`; dazu in `tests/Skip.Tests.ps1` die Feldliste des vollen Laufs um `'HealthOnly'` hinter `'Simulated'` und die Aussage `$m.HealthOnly | Should -BeFalse` ergänzen)

```powershell
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
    }
    It 'ruft die Quelle fuer nichts auf, was zur Messung gehoert' {
        $throwing = (@('Get-WorkerPerfFastSample', 'Get-WorkerPerfSnapshot', 'Get-WorkerPerfServices', 'Get-WorkerPerfEvents', 'Get-WorkerPerfPrintQueues', 'Start-WorkerPerfProbes',
                'Receive-WorkerPerfProbes', 'Wait-WorkerPerfTick') | ForEach-Object { "function $_ { throw 'Testaufruf $_' }" }) -join "`n"
        $run = (& (New-PatchedSource (Join-Path $TestDrive 'srcho') $throwing) -Simulate -HealthOnly -OutputPath (Join-Path $TestDrive 'ho2') 6>$null 3>$null) | Select-Object -Last 1
        (Get-Meta $run).EndReason | Should -Be 'healthonly'; @((Get-Meta $run).SourceErrors.PSObject.Properties).Count | Should -Be 0
    }
    It 'beachtet -Skip Rueckblick und -Skip Drucken' {
        $run = Invoke-SimHealthOnly (Join-Path $TestDrive 'ho3') @{ Skip = @('Drucken', 'Rueckblick') }
        @(Get-ChildItem $run | ForEach-Object Name | Sort-Object) | Should -Be @('apps.json', 'health.json', 'meta.json'); @((Get-Meta $run).Skip) | Should -Be @('Rueckblick', 'Drucken')
    }
    It 'lehnt -Skip Zustand und die Parameter der Messung ab, bevor etwas angelegt wird' {
        $dir = Join-Path $TestDrive 'no'
        { & $Capture -Simulate -HealthOnly -Skip Zustand -OutputPath $dir 6>$null } | Should -Throw '-HealthOnly und -Skip Zustand schliessen sich aus*'
        { & $Capture -Simulate -HealthOnly -DurationMinutes 60 -IntervalSeconds 30 -OutputPath $dir 6>$null } | Should -Throw '*nicht zusammen mit: -IntervalSeconds, -DurationMinutes.'
        { & $Capture -Simulate -HealthOnly -NoCitrix -OutputPath $dir 6>$null } | Should -Throw '*nicht zusammen mit: -NoCitrix.'
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
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/HealthOnly.Tests.ps1`
Expected: FAIL, `Invoke-SimHealthOnly` ist nicht definiert bzw. der Parameter `HealthOnly` ist unbekannt

- [ ] **Step 3: `-HealthOnly`, `New-WorkerPerfWriters -Only`, das Feld `HealthOnly` und `Invoke-SimHealthOnly` umsetzen**

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/Start-WorkerPerfCapture.ps1 src/WorkerPerf.Capture.ps1 tests/TestHelpers.ps1 tests/HealthOnly.Tests.ps1 tests/Skip.Tests.ps1
git commit -m "Add a quick run that reads only the health picture, the lookback and the driver list"
```

---

### Task 10: Lader – `Model.Health`, `Model.HealthState`, Modell eines Schnelllaufs

**Files:**
- Modify: `src/WorkerPerf.Load.ps1`
- Test: `tests/Load.Tests.ps1`
- Mit dem geführten Bericht geteilt: keine. Nicht anfassen: `src/New-WorkerPerfReport.ps1`.

**Interfaces:**
- Consumes: Task 1a (Format, `Complete-WorkerPerfHealthArea`), Task 8 (Kategorie aktiv), Task 9 (`HealthOnly`); `Get-WorkerPerfRecordedSkip`, `Test-WorkerPerfRunFile`, `ConvertTo-WorkerPerfTimestamp`, `Read-WorkerPerfEventCsv`, `Read-WorkerPerfPrintDrivers`.
- Produces:
  - `Get-WorkerPerfJsonTimeText([string]$JsonText, [string]$Name) -> DateTimeOffset | $null`: der Zeitpunkt eines Felds oberster Ebene aus dem Text der Datei (`"<Name>"\s*:\s*"…"`), mit seinem Offset.
  - `Read-WorkerPerfHealthFile([string]$File) -> @{ State; Health; Message }`: `State` `read` mit `Health = @{ FormatVersion; ReadAtMs; OffsetMinutes; DurationMs; Areas }` oder `unreadable` mit `Message`: `kein gueltiges JSON`, `Format <n> unbekannt` (bei `FormatVersion` ungleich 1) oder `Areas fehlt`. `Areas` geordnet nach `$script:WorkerPerfHealthAreas`, je Bereich über `Complete-WorkerPerfHealthArea` aus den Werten der Datei (`Status` neu gebildet, `DurationMs` und `Error` aus der Datei); ein Bereich, den die Datei nicht nennt, mit dem Kennwort `notInFile`; eine Kennung, die die Werteliste nicht kennt oder bei einem anderen Bereich führt, und ein Wert mit unbekanntem `State` oder `Reason` werden übergangen (der Wert ist dann `unreadable`/`error`; die Datei bleibt lesbar). Werte sind Zahlen, Texte, Wahrheitswerte oder Arrays geordneter Wörterbücher, nie `pscustomobject`; ein Wert vom Typ `list` ist immer ein Array (auch die Zeilen von `apps.probes`). Die Kopie `apps.json` der Aufzeichnung liest der Lader nicht: sie hält fest, womit gelesen wurde; die Auswertung nimmt die Anwendungsliste neben dem Berichtsskript (Task 11).
  - `Import-WorkerPerfRun`: `Meta['HealthOnly']` (boolesch; fehlt das Feld: falsch); `Health` und `HealthState` im Modell: `skipped`, wenn `Skip` `Zustand` nennt (die Datei wird nicht gelesen); sonst `notRecorded`, wenn `health.json` fehlt; sonst das Ergebnis von `Read-WorkerPerfHealthFile` (bei `unreadable` eine Warnung `health.json ist nicht lesbar (<Message>); der Bericht zeigt kein Zustandsbild.`). Neu im Modell jeder Aufzeichnung: `Recorded = @{ EventsBefore; PrintDrivers }` (wahr, wenn die Datei in der Aufzeichnung steht und nicht weggelassen ist: `Test-WorkerPerfRunFile`) und `EventsAll` (alle Ereignisse aus `events.csv` nach Zeit, auch die außerhalb von `-From` und `-To`; `Events` bleibt der Ausschnitt).
  - Schnelllauf (`HealthOnly` wahr): `-From` oder `-To` wirft `Die Aufzeichnung ist ein Schnelllauf ohne Messung; -From und -To gelten nicht.` Sonst ein Modell mit denselben Schlüsseln wie das einer Messung: `Tick.N` und `Snap.N` 0, alle Reihen und Listen leer (typisierte leere Arrays), `Rows.K` leer, `MainApp` `$null`, `TotalCpuMs` 0, `EventsOutsideCut` 0; gelesen werden nur `EventsBefore` und `PrintDrivers` (mit `Unreadable.EventsBefore`, `Unreadable.PrintDrivers` und `Recorded`), `EventsAll` ist leer; `CaptureStartMs` und `CaptureEndMs` = `StartTime`; `Meta.OffsetMinutes` = Offset von `StartTime` aus dem Text von `meta.json`. Ticks und Schnappschüsse werden nicht verlangt.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/Load.Tests.ps1`)

```powershell
Describe 'Import-WorkerPerfRun: Zustandsbild' {
    It 'liest health.json in das Modell' {
        $dir = Write-TestRun 'h1' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }
        [IO.File]::WriteAllText((Join-Path $dir 'health.json'), '{"FormatVersion":1,"ReadAt":"2026-01-15T07:59:50.0000000+02:00","DurationMs":1200,"Areas":{"operation":{"Status":"partial","DurationMs":300,"Error":"","Values":{' +
            '"operation.pendingRename":{"State":"read","Reason":"","Value":2},"operation.lastBoot":{"State":"unreadable","Reason":"rights","Value":null},"operation.unbekannt":{"State":"read","Reason":"","Value":1},' +
            '"operation.pendingUpdate":{"State":"gelesen","Reason":"","Value":true},' +
            '"print.spooler":{"State":"read","Reason":"","Value":"Running"},' +
            '"operation.volumes":{"State":"read","Reason":"","Value":[{"Drive":"C:","SizeGB":100,"FreeGB":8.5,"FileSystem":"NTFS","System":true,"PageFile":true}]}}}}}')
        $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles
        $m.HealthState | Should -Be 'read'; $m.Health.DurationMs | Should -Be 1200; $m.Health.OffsetMinutes | Should -Be 120
        $m.Health.ReadAtMs | Should -Be ([DateTimeOffset]'2026-01-15T07:59:50+02:00').ToUnixTimeMilliseconds()
        $o = $m.Health.Areas['operation']; $o.Status | Should -Be 'partial'; $o.DurationMs | Should -Be 300; $o.Values['operation.pendingRename'].Value | Should -Be 2
        $o.Values['operation.lastBoot'].Reason | Should -Be 'rights'; $o.Values.Contains('operation.unbekannt') | Should -BeFalse; $o.Values['operation.powerPlan'].State | Should -Be 'unreadable'
        $o.Values['operation.pendingUpdate'].State | Should -Be 'unreadable'; $o.Values['operation.pendingUpdate'].Reason | Should -Be 'error'      # ein Zustand, den das Format nicht kennt
        $o.Values.Contains('print.spooler') | Should -BeFalse; $m.Health.Areas['print'].Values['print.spooler'].State | Should -Be 'unreadable'      # eine Kennung unter dem falschen Bereich wird uebergangen, die Datei bleibt lesbar
        $vol = @($o.Values['operation.volumes'].Value); $vol[0] | Should -BeOfType [System.Collections.IDictionary]; $vol[0]['FreeGB'] | Should -Be 8.5; $vol[0]['System'] | Should -BeTrue
        @($m.Health.Areas.Keys) | Should -Be $WorkerPerfHealthAreas; $m.Health.Areas['size'].Status | Should -Be 'failed'; $m.Health.Areas['size'].Error | Should -Be 'notInFile'
        $m.Meta.HealthOnly | Should -BeFalse; $m.Recorded.EventsBefore | Should -BeFalse; $m.Recorded.PrintDrivers | Should -BeFalse     # Format 2: beide Dateien gibt es nicht
    }
    It 'unterscheidet nicht erfasst, weggelassen und nicht lesbar' {   # Review Focus 2
        $dir = Write-TestRun 'h2' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }; $meta = Join-Path $dir 'meta.json'; $file = Join-Path $dir 'health.json'
        $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles
        $m.HealthState | Should -Be 'notRecorded'; $m.Health | Should -BeNullOrEmpty; @($m.Skip) | Should -Not -Contain 'Zustand'
        [IO.File]::WriteAllText($file, '{"FormatVersion":2,"Areas":{}}')
        $w = @(Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $w.Count | Should -Be 1; $w[0].Message | Should -Match 'health\.json'; $w[0].Message | Should -Match 'Format 2'
        (Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles 3>$null).HealthState | Should -Be 'unreadable'
        [IO.File]::WriteAllText($file, '{ kein json'); (Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles 3>$null).HealthState | Should -Be 'unreadable'
        # Skip gewinnt gegen die Datei: eine lesbare Datei wird nicht gelesen
        [IO.File]::WriteAllText($file, '{"FormatVersion":1,"ReadAt":"2026-01-15T07:59:50.0000000+01:00","DurationMs":1,"Areas":{}}')
        [IO.File]::WriteAllText($meta, [IO.File]::ReadAllText($meta).Replace('"Simulated":false,', '"Simulated":false,"Skip":["Zustand"],'))
        $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles
        $m.HealthState | Should -Be 'skipped'; $m.Health | Should -BeNullOrEmpty; $m.Sources['health'].Detail | Should -Be 'abgeschaltet (-Skip Zustand)'
    }
    It 'liest einen Schnelllauf ohne Takte und Schnappschuesse' {   # Review Focus 5
        $dir = Join-Path $TestDrive 'ho'; [void](New-Item -ItemType Directory $dir); $meta = Join-Path $dir 'meta.json'
        [IO.File]::WriteAllText($meta, '{"SchemaVersion":3,"Computer":"T1","OS":"x","LogicalProcessors":4,"PhysicalMemoryMB":16384,"FastIntervalSeconds":2,"IntervalSeconds":15,' +
            '"StartTime":"2026-01-15T08:00:00.0000000+02:00","EndTime":"2026-01-15T08:00:05.0000000+02:00","EndReason":"healthonly","Ticks":0,"Snapshots":0,"Simulated":false,"HealthOnly":true,"EventLookbackDays":7,"Skip":[],"Sources":{}}')
        [IO.File]::WriteAllLines((Join-Path $dir 'events_before.csv'), [string[]]@($WorkerPerfHeaders['events_before.csv'], ('2026-01-14T09:00:00.0000000+02:00,application,Application Error,1000,2,app,crash,EXCEL.EXE' + (',' * 12) + 'x')))
        [IO.File]::WriteAllLines((Join-Path $dir 'printdrivers.csv'), [string[]]@($WorkerPerfHeaders['printdrivers.csv'], 'Sim PCL 6,HP,1.0,3,none,a.dll'))
        [IO.File]::WriteAllText((Join-Path $dir 'health.json'), '{"FormatVersion":1,"ReadAt":"2026-01-15T08:00:01.0000000+02:00","DurationMs":900,"Areas":{}}')
        $m = Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles
        $m.Meta.HealthOnly | Should -BeTrue; $m.Tick.N | Should -Be 0; $m.Snap.N | Should -Be 0; $m.Meta.OffsetMinutes | Should -Be 120; $m.HealthState | Should -Be 'read'
        $m.CaptureStartMs | Should -Be ([DateTimeOffset]'2026-01-15T08:00:00+02:00').ToUnixTimeMilliseconds()
        @($m.EventsBefore).Count | Should -Be 1; @($m.PrintDrivers).Count | Should -Be 1; @($m.Events).Count | Should -Be 0; @($m.Sessions).Count | Should -Be 0; $m.Rows.K.Length | Should -Be 0
        $m.Recorded.EventsBefore | Should -BeTrue; $m.Recorded.PrintDrivers | Should -BeTrue; @($m.EventsAll).Count | Should -Be 0
        { Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles -From ([datetime]'2026-01-15T08:00:00') } | Should -Throw '*Schnelllauf*-From*'
        # ohne das Feld bleibt eine Aufzeichnung ohne Takte ein Fehler
        [IO.File]::WriteAllText($meta, [IO.File]::ReadAllText($meta).Replace('"HealthOnly":true,', ''))
        { Import-WorkerPerfRun -Path $dir -Thresholds $Th -Roles $Roles } | Should -Throw '*keine Messung*'
    }
    It 'haelt die Ereignisse der ganzen Messung neben dem Ausschnitt' {
        $ev = @("$(Get-Ts 3),Sim,1,crash,a", "$(Get-Ts 13),Sim,1,crash,b")
        $m = Import-TestRun 'hcut' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'events.csv' = $ev } @{ From = $Base.AddSeconds(9).DateTime }
        @($m.Events).Count | Should -Be 1; @($m.EventsAll).Count | Should -Be 2; $m.EventsOutsideCut | Should -Be 1
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Load.Tests.ps1`
Expected: FAIL, das Modell hat kein Feld `HealthState`

- [ ] **Step 3: `Get-WorkerPerfJsonTimeText`, `Read-WorkerPerfHealthFile` und die Ergänzungen von `Import-WorkerPerfRun` umsetzen** (der Zweig des Schnelllaufs steht nach dem Lesen von `Sources` und `SourceErrors` und vor dem Lesen der Takte)

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Load.ps1 tests/Load.Tests.ps1
git commit -m "Load the health picture and captures of a quick run into the model"
```

---

### Task 11: Katalog laden und prüfen

**Files:**
- Create: `src/WorkerPerf.Health.ps1`, `tests/Health.Tests.ps1`
- Mit dem geführten Bericht geteilt: keine. Nicht anfassen: `src/WorkerPerf.Guidance.ps1` (nur gelesen: `$script:WorkerPerfSituations`), `src/New-WorkerPerfReport.ps1`.

**Interfaces:**
- Consumes: Task 1a (`$script:WorkerPerfHealthAreas`, `$script:WorkerPerfHealthValues`), Task 1b (`Read-WorkerPerfHealthApps`, `Get-WorkerPerfAppFactType`), Task 2 (`New-TestAppFile`); `ConvertFrom-WorkerPerfJsonFile`, `Get-WorkerPerfField`; `$script:WorkerPerfSituations` (`src/WorkerPerf.Guidance.ps1`), `$script:WorkerPerfPatternOrder` (`src/WorkerPerf.Events.ps1`). Fehlt eine der beiden Listen beim Laden des Katalogs, wirft der Lader mit dem Namen der Datei, die vorher eingebunden sein muss.
- Produces (`src/WorkerPerf.Health.ps1`, beginnt mit `#Requires -Version 5.1`, definiert nur Variablen und Funktionen):
  - Aufbau des Katalogs (JSON):

```json
{ "version": "2026-11-13",
  "areas": [ { "id": "size", "label": "Größe und Reserve", "notCovered": "…" } ],
  "grades": { "ok": { "word": "In Ordnung", "symbol": "●" }, "check": { "word": "Prüfen", "symbol": "▲" }, "act": { "word": "Handeln", "symbol": "◆" }, "unknown": { "word": "Nicht prüfbar", "symbol": "○" }, "na": { "word": "Trifft nicht zu", "symbol": "–" } },
  "thresholds": { "diskFreeGB": { "value": 10, "default": 10, "unit": "GB", "label": "Freier Platz auf System- und Auslagerungslaufwerk" } },
  "values": { "operation.minFreeGB": "Kleinster freier Platz auf System- und Auslagerungslaufwerk" },
  "copy": { "title": "Zustand des Workers", "summary": "{act} zum Handeln, {check} zum Prüfen, {ok} in Ordnung" },
  "precedence": [ { "check": "operation.powerPlan", "winner": "practice", "reason": "…" } ],
  "checks": [ { "id": "operation.diskFree", "area": "operation", "title": "Freier Platz auf den Laufwerken", "values": ["operation.minFreeGB"],
      "rules": { "check": [ { "value": "operation.minFreeGB", "op": "exists" }, { "value": "operation.minFreeGB", "op": "lt", "than": "@diskFreeGB" } ],
                 "act":   [ { "value": "operation.minFreeGB", "op": "exists" }, { "value": "operation.minFreeGB", "op": "lt", "than": "@diskFreeHardGB", "hard": true } ] },
      "findings": { "ok": "…", "check": "Nur {operation.minFreeGB} GB frei (Schwelle {@diskFreeGB} GB).", "act": "…", "unknown": "Nicht prüfbar: {reason}." },
      "meaning": "…", "todo": [ { "text": "…", "where": "…", "sign": "…" } ],
      "source": { "vendor": "Microsoft", "title": "…", "url": "https://…", "date": "2026-11-13" }, "kind": "rule", "relates": ["disk", "memory"] } ] }
```

  - `$script:WorkerPerfHealthGrades = @('ok', 'check', 'act', 'unknown')` (die vier Einstufungen; `na` „trifft nicht zu" ist ein Ergebnis, keine Einstufung); `$script:WorkerPerfHealthKinds = @('vendor', 'practice', 'rule')`; `$script:WorkerPerfHealthOps = @('gt', 'ge', 'lt', 'le', 'eq', 'ne', 'in', 'contains', 'exists', 'absent')`; `$script:WorkerPerfHealthEventKinds = @('crash', 'hang', 'service', 'print', 'profileerror', 'system', 'system.storage', 'system.fileserver')`; `$script:WorkerPerfHealthRequiredThresholds = @('workStartHour', 'workEndHour')`.
  - `$script:WorkerPerfHealthDerived`: geordnet, Kennung → `@{ Area; Type; Unit }`, genau die 61 abgeleiteten Fakten der Tabellen oben (`Type` `number`, `bool`, `text`, `time` oder `list`; `events.perDay` ist `list`, `events.reachFrom` ist `time`).
  - `Get-WorkerPerfHealthFactTable([object[]]$Apps = @()) -> [ordered]` Kennung → `@{ Area; Type; Unit; Fields; Derived; Documented; Label }`: die Werteliste (103), dann die abgeleiteten Fakten (61; `Documented` wahr), dann je Anwendung aus `$Apps`, die `installed` nennt, in der Reihenfolge der Liste: `apps.<key>.installed` (`bool`) und je Probe `apps.<key>.<id>` (`Area` `apps`, `Type` aus `Get-WorkerPerfAppFactType`, `Documented` aus der Probe). `Label` ist bei festen Fakten leer (ihre Bezeichnung steht in `values` des Katalogs); bei `apps.<key>.installed` die Bezeichnung der Anwendung, bei einer Probe „<Bezeichnung der Anwendung> – <label der Probe>".
  - `$script:WorkerPerfHealthCopyKeys` (Pflichttexte von `copy`) mit den Platzhaltern, die ein Text tragen darf: `title`, `healthOnlyHead`, `notRecorded`, `notRecordedFailed`, `unreadable`, `readAt` (`date`, `time`, `seconds`), `summary` (`act`, `check`, `ok`), `areaOne`, `areaMany` (`n`), `countsAct`, `countsCheck`, `countsUnknown` (je `n`), `areaPartial`, `areaFailed`, `areaReasonBudget`, `areaReasonNoReader`, `areaReasonNotRead`, `areaReasonNotInFile`, `unknownOne`, `unknownMany` (`n`), `changed` (`list`), `changedItem` (`label`, `value`, `default`, `unit`), `notApplicable` (`reason`), `eventsUnchecked`, `incidentNote`, `noValue`, `yes`, `no`, `reasonRights`, `reasonNotInstalled` (`label`), `reasonNotInUse` (`label`), `reasonAppNotInstalled` (`app`), `reasonTimeout`, `reasonError`, `reasonAbsent`, `reasonSkipped` (`category`), `reasonNotRecorded`, `kindVendor`, `kindPractice`, `kindRule`, `environment`, `eventsReach` (`from`, `boot`), `appInstalled` (`app`), `appNotInstalled` (`app`), `appUnknown` (`app`, `reason`), `appInstalledLabel`, `valueSet`, `valueNotSet`, `stateRead`, `stateAbsent`, `stateUnreadable` (`reason`), `stateNotApplicable` (`reason`), `copyHead` (`server`, `date`), `copyCheckTitle` (`area`, `title`, `grade`), `copyAreaTitle` (`area`, `grade`), `copyAreaItem` (`title`, `grade`, `finding`), `copyMeaning`, `copyTodo`, `copyStep` (`n`, `text`, `where`, `sign`), `copySource` (`kind`, `vendor`, `title`, `date`), `copyOk` (`n`).
  - `Read-WorkerPerfHealthCatalogue([string]$Path, [object[]]$Apps = @()) -> pscustomobject`: der Katalog wie gelesen, dazu die Eigenschaft `appList` (= `$Apps`, die Anwendungsliste aus `Read-WorkerPerfHealthApps`): aus ihr kennt der Lader die Fakten der Anwendungen, und die Tasks 12 und 13 nehmen sie von dort. Prüft und meldet `Katalog '<Pfad>': Pruefung '<id>': Feld '<feld>' <Grund>.` bzw. `Katalog '<Pfad>': Teil '<teil>' <Grund>.`:
    - Teile `version`, `areas`, `grades`, `thresholds`, `values`, `copy`, `precedence`, `checks`; `areas` genau die elf Kennungen in ihrer Reihenfolge mit `label`; `grades` die vier Einstufungen und `na` mit `word` und `symbol`; jede Schwelle mit Zahlen `value` und `default` und mit `unit`, `label`; die Schwellen aus `$script:WorkerPerfHealthRequiredThresholds` vorhanden; `values` mit einer Bezeichnung für jeden der 164 festen Fakten und ohne andere Kennung (die Bezeichnung eines Anwendungswerts steht in der Anwendungsliste); `copy` mit jedem Pflichttext und nur dessen Platzhaltern.
    - je Prüfung, in dieser Reihenfolge (die erste Verletzung wird gemeldet): `id` (einmalig), `area` (bekannt), `title`, `meaning`, `values` (bekannte Fakten aus `Get-WorkerPerfHealthFactTable $Apps`; keiner ohne dokumentierte Lesequelle: `'<Fakt>' hat keine dokumentierte Lesequelle`; eine Prüfung des Bereichs `apps` nennt nur Fakten `apps.<key>.…` (sonst `'<Fakt>' ist kein Wert einer Anwendung`) und nur die einer Anwendung (sonst `nennt Werte von mehr als einer Anwendung`); eine Prüfung eines anderen Bereichs nennt keinen: `'<Fakt>' gehoert in den Bereich apps`; steht die Anwendung nicht in `$Apps`: `Anwendung '<key>' steht nicht in der Anwendungsliste`), `rules` mit mindestens einer der Listen `check`, `act` (geprüft wird `check` vor `act`); `findings.ok` und `findings.unknown`, dazu `findings.check` bzw. `findings.act` für jede vorhandene Regel; `todo` mit mindestens einem Schritt (je Schritt `text`, `where`, `sign`); `source` mit `vendor`, `title`, `date` und bei `kind` `vendor` und `practice` mit `url`; `kind` aus `$script:WorkerPerfHealthKinds`; `relates` (Einträge aus `$script:WorkerPerfSituations` oder `pattern.<id>` mit einer Kennung aus `$script:WorkerPerfPatternOrder`). Kein Text darf leer sein: `title`, `meaning`, jeder Satz von `findings`, jedes Feld eines Schritts von `todo`.
    - je Bedingung: entweder `value` (ein Fakt aus `values` der Prüfung, kein Listenwert; ein Fakt vom Typ `text:free` nur mit `exists` oder `absent`), `op` (bekannt), `than` (Zahl, Text, Liste oder `@<Schwelle>` einer bekannten Schwelle; entfällt bei `exists` und `absent`) und optional `hard`; oder `event` (bekannte Art), `min`, `days` (Zahlen ≥ 1). Eine Regel `act` ohne Bedingung mit `hard` und ohne Bedingung `event` wird abgelehnt.
    - Platzhalter in `findings`: `{<Fakt>}` nur für Fakten aus `values` der Prüfung (kein Listenwert, kein `text:free`), `{@<Schwelle>}` für bekannte Schwellen, `{reason}` nur in `findings.unknown`; `findings.unknown` muss `{reason}` enthalten (der Grund steht immer dabei).
    - Teil `precedence`, geprüft nach den Prüfungen (Entwurf 4.3: die Ausnahmen des Auftraggebers): eine Liste, auch leer. Je Eintrag: `check` nennt eine Prüfung des Katalogs (sonst `Katalog '<Pfad>': Teil 'precedence': Pruefung '<id>' unbekannt.`), jede höchstens einmal; `winner` ist `practice` (ein anderer Wert: `… Teil 'precedence': Pruefung '<id>': Feld 'winner' …`); `reason` ist nicht leer (`… Feld 'reason' ist leer.`); die genannte Prüfung hat `kind` `practice` (sonst `… Teil 'precedence': Pruefung '<id>' hat nicht die Art 'practice'.`). Eine Prüfung der Art `practice`, die nicht in `precedence` steht, widerspricht keinem Hersteller oder folgt ihm.
  - `Get-WorkerPerfHealthChangedThresholds($Catalogue) -> [ordered]@{ id; label; value; default; unit }[]`: die Schwellen, deren `value` von `default` abweicht, in der Reihenfolge des Katalogs.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/Health.Tests.ps1`)

```powershell
BeforeAll {
    Set-StrictMode -Version 2
    foreach ($f in 'Common', 'EventConfig', 'Events', 'Findings', 'Guidance', 'Load', 'Health') { . (Join-Path $PSScriptRoot "../src/WorkerPerf.$f.ps1") }
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1'); $script:TestApps = @(Read-WorkerPerfHealthApps (New-TestAppFile $TestDrive))      # Edge, Office, Teams und die erfundene simapp
    $script:ToApp = { param($Fact, $Op, $Than)
        # macht die erste Pruefung des kleinen Katalogs zu einer Pruefung des Bereichs apps auf einen Fakt
        $c.checks[0].id = 'apps.simCache'; $c.checks[0].area = 'apps'; $c.checks[0].values = @($Fact)
        $c.checks[0].rules = @{ check = @(@{ value = $Fact; op = $Op; than = $Than }) }
        $c.checks[0].findings = @{ ok = 'in Ordnung'; check = 'auffaellig'; unknown = '{reason}' } }
    function New-HealthCatalogue([scriptblock]$Change = {}) {
        # ein vollstaendiger kleiner Katalog als Hashtable in $c; . $Change aendert ihn; liefert den Pfad der geschriebenen Datei
        $todo = @(@{ text = 't'; where = 'w'; sign = 's' })
        $c = [ordered]@{ version = '2026-11-13'
            areas = @($WorkerPerfHealthAreas | ForEach-Object { [ordered]@{ id = $_; label = "Bereich $_"; notCovered = "Nicht abgedeckt in $_" } })
            grades = [ordered]@{ ok = @{ word = 'In Ordnung'; symbol = [string][char]0x25CF }; check = @{ word = 'Prüfen'; symbol = [string][char]0x25B2 }
                act = @{ word = 'Handeln'; symbol = [string][char]0x25C6 }; unknown = @{ word = 'Nicht prüfbar'; symbol = [string][char]0x25CB }; na = @{ word = 'Trifft nicht zu'; symbol = [string][char]0x2013 } }
            thresholds = [ordered]@{ diskFreeGB = @{ value = 10; default = 10; unit = 'GB'; label = 'Freier Platz' }; diskFreeHardGB = @{ value = 2; default = 2; unit = 'GB'; label = 'Freier Platz, harte Grenze' }
                workStartHour = @{ value = 7; default = 7; unit = 'Uhr'; label = 'Beginn der Arbeitszeit' }; workEndHour = @{ value = 18; default = 18; unit = 'Uhr'; label = 'Ende der Arbeitszeit' } }
            values = [ordered]@{}; copy = [ordered]@{}; precedence = @()
            checks = @(
                [ordered]@{ id = 'operation.diskFree'; area = 'operation'; title = 'Freier Platz'; values = @('operation.minFreeGB')
                    rules = @{ check = @(@{ value = 'operation.minFreeGB'; op = 'lt'; than = '@diskFreeGB' }); act = @(@{ value = 'operation.minFreeGB'; op = 'lt'; than = '@diskFreeHardGB'; hard = $true }) }
                    findings = @{ ok = '{operation.minFreeGB} GB frei.'; check = 'Nur {operation.minFreeGB} GB frei (Schwelle {@diskFreeGB} GB).'; act = 'Nur {operation.minFreeGB} GB frei.'; unknown = 'Nicht prüfbar: {reason}.' }
                    meaning = 'm'; todo = $todo; source = @{ vendor = 'Microsoft'; title = 'Seite'; url = ''; date = '2026-11-13' }; kind = 'rule'; relates = @('disk', 'crash') }
                [ordered]@{ id = 'print.driversInSpooler'; area = 'print'; title = 'Treiber im Spooler-Prozess'; values = @('print.driversInSpooler')
                    rules = @{ check = @(@{ value = 'print.driversInSpooler'; op = 'gt'; than = 0 }); act = @(@{ value = 'print.driversInSpooler'; op = 'gt'; than = 0 }, @{ event = 'print'; min = 1; days = 7 }) }
                    findings = @{ ok = 'Kein Treiber im Spooler.'; check = '{print.driversInSpooler} Treiber im Spooler.'; act = '{print.driversInSpooler} Treiber im Spooler, Druckereignisse.'; unknown = '{reason}' }
                    meaning = 'm'; todo = $todo; source = @{ vendor = 'Microsoft'; title = 'Printer Driver Isolation'; url = 'https://learn.microsoft.com/x'; date = '2026-11-13' }
                    kind = 'vendor'; relates = @('print', 'pattern.printdriver') }) }
        foreach ($id in (Get-WorkerPerfHealthFactTable).Keys) { $c.values[$id] = "Wert $id" }
        foreach ($k in $WorkerPerfHealthCopyKeys.Keys) { $c.copy[$k] = "Text $k" }
        $c.copy.yes = 'ja'; $c.copy.no = 'nein'; $c.copy.noValue = '–'; $c.copy.reasonSkipped = '{category} nicht erfasst'; $c.copy.notApplicable = 'Trifft nicht zu: {reason}.'
        $c.copy.reasonNotInstalled = '{label} fehlt'; $c.copy.reasonNotInUse = '{label} nicht in Gebrauch'; $c.copy.reasonAppNotInstalled = '{app} ist nicht installiert'
        $c.copy.summary = '{act} zum Handeln, {check} zum Prüfen, {ok} in Ordnung'; $c.copy.areaOne = '1 Bereich'; $c.copy.areaMany = '{n} Bereiche'
        $c.copy.countsAct = '{n} zum Handeln'; $c.copy.countsCheck = '{n} zum Prüfen'; $c.copy.countsUnknown = '{n} nicht prüfbar'
        $c.copy.copyCheckTitle = '{area} – {title}: {grade}'; $c.copy.copyAreaTitle = '{area}: {grade}'; $c.copy.copyAreaItem = '- {title}: {grade}. {finding}'
        . $Change
        $file = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.json'); [IO.File]::WriteAllText($file, (ConvertTo-Json -InputObject $c -Depth 12)); $file
    }
}
Describe 'Katalog des Zustandsbilds laden und pruefen' {
    It 'liest einen vollstaendigen Katalog und kennt jeden Fakt' {
        $c = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue)
        @($c.checks).Count | Should -Be 2; $c.thresholds.diskFreeGB.value | Should -Be 10; $c.areas[0].id | Should -Be 'size'; $c.grades.act.word | Should -Be 'Handeln'
        $t = Get-WorkerPerfHealthFactTable; @($t.Keys).Count | Should -Be 164; @($WorkerPerfHealthDerived.Keys).Count | Should -Be 61
        $ta = Get-WorkerPerfHealthFactTable $TestApps; @($ta.Keys).Count | Should -Be 206                         # 164 feste, 38 der ausgelieferten Liste, 4 der simapp
        $ta['apps.edge.installed'].Area | Should -Be 'apps'; $ta['apps.edge.installed'].Type | Should -Be 'bool'; $ta['apps.edge.backgroundMode'].Type | Should -Be 'value'
        $ta['apps.edge.userDataDir'].Type | Should -Be 'text:free'; $ta['apps.office.updateTask'].Type | Should -Be 'bool'; $ta['apps.office.platform'].Documented | Should -BeFalse
        $ta['apps.simapp.cacheMode'].Label | Should -Be 'Sim-Fachanwendung – Cache-Betriebsart'; $ta['apps.simapp.installed'].Label | Should -Be 'Sim-Fachanwendung'; $t['size.cpuLogical'].Label | Should -Be ''
        $t['events.reachFrom'].Type | Should -Be 'time'; $t['operation.pendingUpdate'].Documented | Should -BeFalse; $t['operation.minFreeGB'].Documented | Should -BeTrue
        $t['size.cpuLogical'].Derived | Should -BeFalse; $t['operation.minFreeGB'].Derived | Should -BeTrue; $t['operation.minFreeGB'].Unit | Should -Be 'GB'; $t['events.perDay'].Type | Should -Be 'list'
    }
    It 'nennt Pruefung und Feld eines Fehlers' -TestCases @(
        @{ Change = { $c.checks[0].Remove('source') }; Msg = "*Pruefung 'operation.diskFree'*Feld 'source'*" }
        @{ Change = { $c.checks[0].Remove('kind') }; Msg = "*Pruefung 'operation.diskFree'*Feld 'kind'*" }
        @{ Change = { $c.checks[0].meaning = '' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'meaning'*" }
        @{ Change = { $c.checks[0].title = '' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'title'*" }
        @{ Change = { $c.checks[0].findings.Remove('unknown') }; Msg = "*Pruefung 'operation.diskFree'*Feld 'findings'*unknown*" }
        @{ Change = { $c.checks[0].findings.Remove('act') }; Msg = "*Pruefung 'operation.diskFree'*Feld 'findings'*act*" }
        @{ Change = { $c.checks[0].values = @('operation.gibtEsNicht') }; Msg = "*Pruefung 'operation.diskFree'*Feld 'values'*operation.gibtEsNicht*" }
        @{ Change = { $c.checks[0].area = 'wetter' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'area'*wetter*" }
        @{ Change = { $c.checks[0].rules.check[0].than = '@nix' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'rules'*@nix*" }
        @{ Change = { $c.checks[0].rules.check[0].op = 'like' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'rules'*like*" }
        @{ Change = { $c.checks[0].rules.check[0].value = 'size.cpuLogical' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'rules'*size.cpuLogical*values*" }
        @{ Change = { $c.checks[0].rules.act[0].Remove('hard') }; Msg = "*Pruefung 'operation.diskFree'*Feld 'rules'*act*harte Grenze*Ereignis*" }
        @{ Change = { $c.checks[1].rules.act[1].event = 'wetter' }; Msg = "*Pruefung 'print.driversInSpooler'*Feld 'rules'*wetter*" }
        @{ Change = { $c.checks[0].relates = @('disk', 'pattern.nix') }; Msg = "*Pruefung 'operation.diskFree'*Feld 'relates'*pattern.nix*" }
        @{ Change = { $c.checks[0].findings.check = '{size.cpuLogical} frei' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'findings'*{size.cpuLogical}*" }
        @{ Change = { $c.checks[0].findings.ok = '{reason}' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'findings'*{reason}*" }
        @{ Change = { $c.checks[0].findings.unknown = 'Nicht prüfbar.' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'findings'*unknown*{reason}*" }
        @{ Change = { $c.checks[1].source.url = '' }; Msg = "*Pruefung 'print.driversInSpooler'*Feld 'source'*url*" }
        @{ Change = { $c.checks[0].kind = 'practice' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'source'*url*" }                         # eine Praxisquelle braucht ihre Adresse
        @{ Change = { $c.checks[0].kind = 'praxis' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'kind'*praxis*" }
        @{ Change = { $c.checks[0].values = @('operation.minFreeGB', 'operation.pendingUpdate') }; Msg = "*Pruefung 'operation.diskFree'*Feld 'values'*operation.pendingUpdate*dokumentierte Lesequelle*" }
        @{ Change = { $c.grades.Remove('na') }; Msg = "*Teil 'grades'*na*" }
        @{ Change = { $c.checks[0].todo[0].Remove('sign') }; Msg = "*Pruefung 'operation.diskFree'*Feld 'todo'*sign*" }
        @{ Change = { $c.checks[0].todo = @() }; Msg = "*Pruefung 'operation.diskFree'*Feld 'todo'*" }                                    # ohne Vorschlag zum Vorgehen
        @{ Change = { $c.checks[0].findings.check = '' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'findings'*check*" }
        @{ Change = { $c.checks[1].id = 'operation.diskFree' }; Msg = "*Pruefung 'operation.diskFree'*doppelt*" }
        @{ Change = { $c.checks[0].values = @('operation.volumes'); $c.checks[0].rules.check[0].value = 'operation.volumes' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'rules'*operation.volumes*Liste*" }
        @{ Change = { $c.thresholds.diskFreeGB.value = 'viel' }; Msg = "*Teil 'thresholds'*diskFreeGB*" }
        @{ Change = { $c.thresholds.Remove('workEndHour') }; Msg = "*Teil 'thresholds'*workEndHour*" }
        @{ Change = { $c.values.Remove('size.cpuLogical') }; Msg = "*Teil 'values'*size.cpuLogical*" }
        @{ Change = { $c.areas = @($c.areas | Select-Object -Skip 1) }; Msg = "*Teil 'areas'*" }
        @{ Change = { $c.copy.Remove('notRecorded') }; Msg = "*Teil 'copy'*notRecorded*" }
        @{ Change = { $c.copy.summary = '{act} und {wetter}' }; Msg = "*Teil 'copy'*summary*{wetter}*" }
        @{ Change = { $c.Remove('precedence') }; Msg = "*Teil 'precedence'*" }
        @{ Change = { $c.precedence = @(@{ check = 'operation.gibtEsNicht'; winner = 'practice'; reason = 'Betriebserfahrung' }) }; Msg = "*Teil 'precedence'*Pruefung 'operation.gibtEsNicht' unbekannt*" }      # ein Eintrag fuer eine Pruefung, die es nicht gibt
        @{ Change = { $c.precedence = @(@{ check = 'operation.diskFree'; winner = 'practice'; reason = 'Betriebserfahrung' }) }; Msg = "*Teil 'precedence'*Pruefung 'operation.diskFree'*practice*" }                  # die Pruefung ist eine Faustregel
        @{ Change = { $c.precedence = @(@{ check = 'print.driversInSpooler'; winner = 'vendor'; reason = 'r' }) }; Msg = "*Teil 'precedence'*Pruefung 'print.driversInSpooler'*winner*" }
        @{ Change = { $c.checks[0].kind = 'practice'; $c.checks[0].source.url = 'https://www.carlstalhood.com/citrix-health-check/'; $c.precedence = @(@{ check = 'operation.diskFree'; winner = 'practice'; reason = '' }) }; Msg = "*Teil 'precedence'*Pruefung 'operation.diskFree'*reason*" }
    ) { { Read-WorkerPerfHealthCatalogue (New-HealthCatalogue $Change) } | Should -Throw $Msg }
    It 'nimmt eine Praxisquelle mit Adresse an' {
        $c = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { $c.checks[0].kind = 'practice'; $c.checks[0].source = @{ vendor = 'Carl Stalhood'; title = 'Citrix Health Check'; url = 'https://www.carlstalhood.com/citrix-health-check/'; date = '2026-11-13' } })
        $c.checks[0].kind | Should -Be 'practice'; $WorkerPerfHealthKinds | Should -Be @('vendor', 'practice', 'rule'); @($c.precedence).Count | Should -Be 0
        # die Ausnahme des Auftraggebers: dieselbe Pruefung mit einem Eintrag in precedence
        $c = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { $c.checks[0].kind = 'practice'; $c.checks[0].source = @{ vendor = 'Carl Stalhood'; title = 'Citrix Health Check'; url = 'https://www.carlstalhood.com/citrix-health-check/'; date = '2026-11-13' }
            $c.precedence = @(@{ check = 'operation.diskFree'; winner = 'practice'; reason = 'Die Praxisquellen beziehen sich auf Citrix-Terminalserver.' }) })
        @($c.precedence).Count | Should -Be 1; $c.precedence[0].check | Should -Be 'operation.diskFree'; $c.precedence[0].winner | Should -Be 'practice'
    }
    It 'kennt die Fakten der Anwendungen aus der Anwendungsliste' {
        $c = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { & $ToApp 'apps.simapp.cacheMode' 'eq' 2 }) $TestApps
        $c.checks[0].id | Should -Be 'apps.simCache'; @($c.appList).Count | Should -Be $TestApps.Count
        { Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { & $ToApp 'apps.simapp.dataPath' 'exists' $null }) $TestApps } | Should -Not -Throw     # freier Text: nur vorhanden oder nicht
        # dieselbe Pruefung ohne die Anwendung in der Liste: abgelehnt
        { Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { & $ToApp 'apps.simapp.cacheMode' 'eq' 2 }) @($TestApps | Where-Object key -ne 'simapp') } |
            Should -Throw "*Pruefung 'apps.simCache'*Feld 'values'*Anwendung 'simapp' steht nicht in der Anwendungsliste*"
    }
    It 'lehnt eine fehlerhafte Pruefung des Bereichs apps ab' -TestCases @(
        @{ Change = { & $ToApp 'apps.simapp.gibtEsNicht' 'eq' 2 }; Msg = "*Pruefung 'apps.simCache'*Feld 'values'*apps.simapp.gibtEsNicht*" }
        @{ Change = { & $ToApp 'apps.office.platform' 'eq' 'x86' }; Msg = "*Pruefung 'apps.simCache'*Feld 'values'*apps.office.platform*dokumentierte Lesequelle*" }
        @{ Change = { & $ToApp 'apps.simapp.cacheMode' 'eq' 2; $c.checks[0].values = @('apps.simapp.cacheMode', 'apps.edge.backgroundMode') }; Msg = "*Pruefung 'apps.simCache'*Feld 'values'*mehr als einer Anwendung*" }
        @{ Change = { & $ToApp 'apps.simapp.cacheMode' 'eq' 2; $c.checks[0].values = @('apps.simapp.cacheMode', 'size.cpuLogical') }; Msg = "*Pruefung 'apps.simCache'*Feld 'values'*size.cpuLogical*" }
        @{ Change = { $c.checks[0].values = @('operation.minFreeGB', 'apps.simapp.cacheMode') }; Msg = "*Pruefung 'operation.diskFree'*Feld 'values'*apps.simapp.cacheMode*Bereich apps*" }
        @{ Change = { & $ToApp 'apps.simapp.dataPath' 'eq' 'x' }; Msg = "*Pruefung 'apps.simCache'*Feld 'rules'*apps.simapp.dataPath*exists*" }
        @{ Change = { & $ToApp 'apps.simapp.dataPath' 'exists' $null; $c.checks[0].findings.check = 'Pfad {apps.simapp.dataPath}' }; Msg = "*Pruefung 'apps.simCache'*Feld 'findings'*{apps.simapp.dataPath}*" }
    ) { { Read-WorkerPerfHealthCatalogue (New-HealthCatalogue $Change) $TestApps } | Should -Throw $Msg }
    It 'nennt die geaenderten Schwellen' {
        $c = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { $c.thresholds.diskFreeGB.value = 25 })
        $ch = @(Get-WorkerPerfHealthChangedThresholds $c); $ch.Count | Should -Be 1
        $ch[0].id | Should -Be 'diskFreeGB'; $ch[0].value | Should -Be 25; $ch[0].default | Should -Be 10; $ch[0].unit | Should -Be 'GB'; $ch[0].label | Should -Be 'Freier Platz'
    }
}
```

`$WorkerPerfHealthCopyKeys` ist geordnet: Schlüssel → Liste der erlaubten Platzhalter.

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Health.Tests.ps1`
Expected: FAIL, Datei `WorkerPerf.Health.ps1` fehlt

- [ ] **Step 3: Listen, `Get-WorkerPerfHealthFactTable`, `Read-WorkerPerfHealthCatalogue` und `Get-WorkerPerfHealthChangedThresholds` mit den Signaturen der Interfaces umsetzen** (die Prüfung von `values` einer Prüfung steht vor der ihrer Regeln und Befundsätze: ein unbekannter oder nicht dokumentierter Fakt wird am Feld `values` gemeldet)

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Health.ps1 tests/Health.Tests.ps1
git commit -m "Load and validate the health catalogue"
```

---

### Task 12: Fakten bilden

**Files:**
- Modify: `src/WorkerPerf.Health.ps1`, `src/roles.json` (Liste `filters`), `src/WorkerPerf.Common.ps1` (`Read-WorkerPerfRoles`: `filters` mit Vorgabe leer)
- Test: `tests/Health.Tests.ps1`
- Mit dem geführten Bericht geteilt: `src/roles.json` (die Korrekturrunde 2 von Task 6 des geführten Berichts trägt dort die Einträge für WEM und für den Client des Zuordnungswerkzeugs ein, Commit „List WEM and the printer mapping client in the roles"; er ist vorher in den Worktree geholt. Diese Task fügt nur an zwei bestehenden Einträgen das Feld `filters` an). Nicht anfassen: `src/WorkerPerf.Events.ps1`, `src/WorkerPerf.Guidance.ps1`, `src/New-WorkerPerfReport.ps1`, die übrigen Felder und Einträge von `src/roles.json` und die Tests, die sie festschreiben.

**Interfaces:**
- Consumes: Tasks 10 und 11; aus dem Modell `Health`, `HealthState`, `Skip`, `Meta` (`EventLookbackDays`, `HealthOnly`, `OffsetMinutes`), `CaptureStartMs`, `EventsBefore`, `EventsAll`, `PrintDrivers`, `Recorded`, `SourceErrors` (Einträge mit `Source`); `Get-WorkerPerfEventIncidentKind`, `Get-WorkerPerfEventOffset`, `Get-WorkerPerfEventReadLogs`, `Read-WorkerPerfRoles`.
- Produces:
  - `Read-WorkerPerfRoles` setzt `filters` (Liste von Namensmustern, Vorgabe leer); `src/roles.json` nennt die Filter der Tabelle im Abschnitt Sicherheitsprodukte.
  - `$script:WorkerPerfHealthCitrixProcesses = @('UserProfileManager.exe', 'BrokerAgent.exe', 'CtxSvcHost.exe')`; `$script:WorkerPerfHealthWemProcesses = @('Citrix.Wem.Agent.Service.exe', 'VUEMUIAgent.exe', 'AgentCacheUtility.exe')`.
  - `New-WorkerPerfHealthFact([string]$State, [string]$Reason = '', $Value = $null) -> [ordered]@{ State; Reason; Value }`: wie `New-WorkerPerfHealthValue`, erlaubt als Grund zusätzlich `notRecorded`, `notInUse` und `skipped:<Kategorie>` (ein Name aus `$script:WorkerPerfCategories`); jeder andere Grund wirft. Abgeleitete Fakten entstehen nur über diese Funktion (`New-WorkerPerfHealthValue` kennt diese Gründe nicht: sie kommen in `health.json` nicht vor).
  - `Get-WorkerPerfHealthMissingReason -Model -What <'lookback' | 'drivers'> -> string`: leer, wenn die Quelle gelesen wurde, sonst der Grund. `lookback`: `skipped:Rueckblick`, wenn `Skip` `Rueckblick` nennt oder `EventLookbackDays` 0 ist; `notRecorded`, wenn `Meta` keine Angabe `EventLookbackDays` hat oder `Recorded.EventsBefore` falsch ist; `error`, wenn `EventsBefore` leer ist und `SourceErrors` einen Eintrag `eventsbefore` oder `eventsbefore.<Protokoll>` hat. `drivers`: `skipped:Drucken`, wenn `Skip` `Drucken` nennt; `notRecorded`, wenn `Recorded.PrintDrivers` falsch ist; `error`, wenn `SourceErrors` den Eintrag `printdrivers` hat.
  - `Get-WorkerPerfHealthFacts -Model -Catalogue -EventConfig -Roles -> [ordered]` Kennung → Fakt, für jeden Fakt von `Get-WorkerPerfHealthFactTable $Catalogue.appList` in dessen Reihenfolge (164 feste Fakten, danach die der Anwendungsliste): die gelesenen Werte unverändert, die abgeleiteten nach den Regeln der Tabellen oben, die Fakten der Anwendungen aus den Zeilen von `apps.probes` (Zustand, Grund und Wert der Zeile mit derselben Anwendung und Kennung; `Names` statt `Value`, wo die Probe `names` trägt). Ist `apps.probes` nicht gelesen, sind alle Fakten der Anwendungen `unreadable` mit dessen Grund (`error`, wo er leer ist); hat die Aufzeichnung für eine Probe der Liste keine Zeile (sie wurde mit einer anderen Anwendungsliste gelesen), ist der Fakt `unreadable` mit `notRecorded`. Ist `size.model` nicht gelesen, haben `size.vmware` und die Fakten, die davon abhängen, dessen Zustand. Die fünf Treiberfakten und die vier Fakten des Rückblicks sind `unreadable` mit dem Grund aus `Get-WorkerPerfHealthMissingReason`, wenn er nicht leer ist. Die Arbeitszeit kommt aus den Schwellen `workStartHour` und `workEndHour` des Katalogs.
  - `Get-WorkerPerfHealthEventCount -Model -EventConfig -Kind -Days -> @{ Known; Count }`: Ereignisse der Art (`<Art>` nach `Get-WorkerPerfEventIncidentKind`, oder `system.<Gruppe>`) im Rückblick ab `CaptureStartMs` − `Days` Tage und in den Ereignissen der ganzen Messung (`EventsAll`, unabhängig von `-From` und `-To`). Der Rückblick zählt, wenn `Get-WorkerPerfHealthMissingReason … 'lookback'` leer ist; die Messung, wenn sie kein Schnelllauf ist und `Ereignisse` nicht weggelassen ist. `Count` ist die Summe aus beiden, soweit sie zählen; `Known` ist wahr, wenn der Rückblick zählt (ein Rückblick, der kürzer ist als `Days`, zählt mit dem, was er hat).

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/Health.Tests.ps1`; die Helfer stehen im `BeforeAll` am Dateianfang)

```powershell
    # in BeforeAll am Dateianfang:
    $script:ReadMs = ([DateTimeOffset]'2026-01-15T08:00:00+01:00').ToUnixTimeMilliseconds()          # ein Donnerstag
    $script:Cfg = Read-WorkerPerfEventConfig (Join-Path $PSScriptRoot '../src/events.json'); $script:Roles = @(Read-WorkerPerfRoles (Join-Path $PSScriptRoot '../src/roles.json'))
    $script:Texts = Read-WorkerPerfTexts (Join-Path $PSScriptRoot '../src/texts.de.json'); $script:Cat = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue)
    function New-HealthModel([hashtable]$Values = @{}, [hashtable]$With = @{}) {
        # Model mit einem Zustandsbild: die genannten Werte gelesen (oder als New-WorkerPerfHealthValue uebergeben), alle anderen nicht vorhanden;
        # Rueckblick und Treiberliste gelesen und leer
        $areas = [ordered]@{}
        foreach ($a in $WorkerPerfHealthAreas) {
            $v = @{}
            foreach ($id in @($WorkerPerfHealthValues.Keys | Where-Object { $WorkerPerfHealthValues[$_].Area -eq $a })) {
                if (-not $Values.ContainsKey($id)) { $v[$id] = New-WorkerPerfHealthValue 'absent'; continue }
                $x = $Values[$id]; $v[$id] = $(if ($x -is [System.Collections.IDictionary] -and $x.Contains('State')) { $x } else { New-WorkerPerfHealthValue 'read' '' $x })
            }
            $areas[$a] = Complete-WorkerPerfHealthArea $a $v 1
        }
        $m = @{ Health = @{ FormatVersion = 1; ReadAtMs = $ReadMs; OffsetMinutes = 60; DurationMs = 10; Areas = $areas }; HealthState = 'read'; Skip = [string[]]@()
            Meta = @{ EventLookbackDays = 7; HealthOnly = $false; OffsetMinutes = 60; Computer = 'T1' }; CaptureStartMs = $ReadMs + 5000; EventsBefore = @(); EventsAll = @(); PrintDrivers = @()
            Recorded = @{ EventsBefore = $true; PrintDrivers = $true }; SourceErrors = @() }
        foreach ($k in $With.Keys) { $m[$k] = $With[$k] }; $m
    }
    function New-Ev([double]$DaysBefore, [string]$Kind, [string]$Group = 'app', [string]$App = '') {
        @{ TimeMs = $ReadMs - [long]($DaysBefore * 86400000); OffsetMinutes = 60; Kind = $Kind; Group = $Group; App = $App; Service = ''; Log = 'application' } }
    function New-SourceError([string]$Source) { @{ Source = $Source; Count = 1; FirstMs = $null; FirstMessage = 'Testfehler' } }
    function Get-Facts([hashtable]$Values = @{}, [hashtable]$With = @{}, $Roles = $script:Roles) { Get-WorkerPerfHealthFacts -Model (New-HealthModel $Values $With) -Catalogue $Cat -EventConfig $Cfg -Roles $Roles }

Describe 'Fakten des Zustandsbilds' {
    It 'bildet die abgeleiteten Fakten aus den gelesenen Werten' {
        $f = Get-Facts @{ 'size.commitTotalMB' = 38000; 'size.commitLimitMB' = 98304; 'size.commitPeakMB' = 61000; 'size.memTotalMB' = 65536; 'size.cpuLogical' = 8
            'size.pagefiles' = @(@{ Path = 'C:\pagefile.sys'; AllocatedMB = 32768; PeakUsageMB = 5200; Temporary = $false }, @{ Path = 'D:\temp.sys'; AllocatedMB = 1; PeakUsageMB = 1; Temporary = $true })
            'operation.lastBoot' = $ReadMs - 3 * 86400000; 'operation.lastUpdate' = $ReadMs - 20 * 86400000
            'operation.volumes' = @(@{ Drive = 'C:'; SizeGB = 100; FreeGB = 38; System = $true; PageFile = $true }, @{ Drive = 'D:'; SizeGB = 200; FreeGB = 5; System = $false; PageFile = $false })
            'sessions.list' = @(@{ Id = 0; State = 'Disconnected'; User = ''; DisconnectTime = 0 }) + @(2..25 | ForEach-Object { @{ Id = $_; State = 'Active'; User = "user$_"; DisconnectTime = 0 } }) +
                @(@{ Id = 30; State = 'Disconnected'; User = 'gast'; DisconnectTime = $ReadMs - 26 * 3600000 })
            'sessions.limits' = @(@{ Terminal = 'RDP-Tcp'; DisconnectedLimitMin = 0; IdleLimitMin = 0 }, @{ Terminal = 'ICA-CGP'; DisconnectedLimitMin = 240; IdleLimitMin = 180 })
            'size.model' = 'VMware, Inc. VMware7,1'; 'size.vmtoolsVersion' = '11.3.5'; 'size.balloonDriver' = 'Stopped'
            'size.netAdapters' = @(@{ Name = 'vmxnet3 Ethernet Adapter'; Enabled = $true }, @{ Name = 'Intel(R) 82574L Gigabit Network Connection'; Enabled = $true }, @{ Name = 'Alt'; Enabled = $false })
            'size.storageControllers' = @(@{ Name = 'LSI Adapter, SAS 3000 series'; Driver = 'LSI_SAS' }, @{ Name = 'VMware PVSCSI Controller'; Driver = 'pvscsi' })
            'network.rss' = @(@{ Description = 'vmxnet3 Ethernet Adapter'; Enabled = $false }, @{ Description = 'Intel(R) 82574L'; Enabled = $false })
            'vda.wemService' = 'Running'; 'print.citrixPrintService' = 'Running'
            'vda.wemServices' = @(@{ Name = 'Citrix WEM Agent Host Service'; State = 'Running'; StartMode = 'Auto' }, @{ Name = 'Citrix WEM User Logon Service'; State = 'Stopped'; StartMode = 'Auto' })
            'sessions.localProfiles' = @(@{ Path = 'C:\Users\a'; Loaded = $true; Special = $false; Temporary = $false }, @{ Path = 'C:\Users\b'; Loaded = $false; Special = $false; Temporary = $true })
            'vda.services' = @(@{ Name = 'BrokerAgent'; State = 'Running'; StartMode = 'Auto' }, @{ Name = 'SimDienst'; State = 'Stopped'; StartMode = 'Auto' }, @{ Name = 'SimHand'; State = 'Stopped'; StartMode = 'Manual' })
            'vda.controllers' = @(@{ Entry = 'ddc01.sim.local'; Kind = 'fqdn'; From = 'policy' }, @{ Entry = 'ddc02'; Kind = 'short'; From = 'policy' })
            'profile.containers' = @(@{ Owner = 'user9'; UsedPct = 96 }, @{ Owner = 'user9'; UsedPct = 40 }, @{ Owner = ''; UsedPct = 10 })
            'print.queueCount' = 50; 'print.mappingClientVersion' = '6.2.1'
            'network.dnsServers' = @(@{ Interface = 4; Address = '10.20.0.10' }, @{ Interface = 4; Address = '8.8.8.8' }, @{ Interface = 7; Address = 'fd00:20::10' })
            'network.smbConnections' = @(@{ Share = '\\fs01\daten'; Dialect = '3.1.1'; Connections = 25 }, @{ Share = '\\alt01\archiv'; Dialect = '2.1'; Connections = 3 }); 'network.timeType' = 'NTP' }
        $val = { param($id) $f[$id].State | Should -Be 'read' -Because $id; $f[$id].Value }
        & $val 'size.commitPeakPct' | Should -Be 62.1; & $val 'size.commitNowPct' | Should -Be 38.7; & $val 'size.pagefileCount' | Should -Be 1
        & $val 'sessions.userCount' | Should -Be 25; & $val 'size.memPerSessionMB' | Should -Be 2621.4; & $val 'size.sessionsPerCpu' | Should -Be 3.1
        & $val 'operation.uptimeDays' | Should -Be 3; & $val 'operation.updateAgeDays' | Should -Be 20; & $val 'operation.minFreeGB' | Should -Be 38
        & $val 'sessions.disconnectedCount' | Should -Be 1; & $val 'sessions.disconnectedOldestHours' | Should -Be 26; & $val 'sessions.disconnectLimitMin' | Should -Be 240
        & $val 'sessions.unloadedProfiles' | Should -Be 1; & $val 'sessions.tempProfiles' | Should -Be 1
        & $val 'vda.stoppedAutoServices' | Should -Be 1; & $val 'vda.controllerCount' | Should -Be 2; & $val 'vda.controllersNotFqdn' | Should -Be 1
        & $val 'profile.containerCount' | Should -Be 3; & $val 'profile.containerMaxUsedPct' | Should -Be 96; & $val 'profile.maxContainersPerUser' | Should -Be 2
        & $val 'print.queuesPerSession' | Should -Be 2; & $val 'print.mappingClientRelease' | Should -Be 602
        & $val 'network.dnsServersMin' | Should -Be 1; & $val 'network.dnsPublic' | Should -Be 1; & $val 'network.smbOldDialects' | Should -Be 3; & $val 'network.timeFromDomain' | Should -BeFalse
        & $val 'size.commitOfRamPct' | Should -Be 58; & $val 'size.vmware' | Should -BeTrue; & $val 'size.vmtoolsMajor' | Should -Be 11; & $val 'size.balloonRunning' | Should -BeFalse
        & $val 'size.otherNetAdapters' | Should -Be 1; & $val 'size.lsiControllers' | Should -Be 1; & $val 'network.rssOff' | Should -Be 1; & $val 'sessions.idleLimitMin' | Should -Be 180
        & $val 'vda.wemServicesNotReady' | Should -Be 2; & $val 'print.citrixMapping' | Should -BeTrue      # der Anmeldedienst steht, der dritte Dienst fehlt in der Liste
        $f['size.cpuLogical'].Value | Should -Be 8; @($f.Keys).Count | Should -Be 164                       # gelesene Werte sind selbst Fakten
    }
    It 'gibt den Zustand der Eingangswerte weiter und nennt nichts Zaehlbares nicht vorhanden' {
        $f = Get-Facts @{ 'size.commitLimitMB' = 98304; 'size.commitPeakMB' = (New-WorkerPerfHealthValue 'unreadable' 'rights'); 'profile.containers' = @(); 'sessions.list' = @(); 'size.memTotalMB' = 65536
            'sessions.limits' = @(@{ Terminal = 'RDP-Tcp'; DisconnectedLimitMin = 0 }); 'vda.version' = (New-WorkerPerfHealthValue 'absent' 'notInstalled') }
        $f['size.commitPeakPct'].State | Should -Be 'unreadable'; $f['size.commitPeakPct'].Reason | Should -Be 'rights'
        $f['profile.containerMaxUsedPct'].State | Should -Be 'absent'; $f['profile.containerMaxUsedPct'].Reason | Should -Be ''; $f['profile.containerCount'].Value | Should -Be 0
        $f['size.memPerSessionMB'].State | Should -Be 'absent'; $f['sessions.disconnectedOldestHours'].Value | Should -Be 0; $f['sessions.disconnectLimitMin'].State | Should -Be 'absent'
        $f['security.citrixExclusionsMissing'].State | Should -Be 'absent'; $f['security.citrixExclusionsMissing'].Reason | Should -Be 'notInstalled'
        { New-WorkerPerfHealthFact 'unreadable' 'skipped:Drucken' } | Should -Not -Throw; { New-WorkerPerfHealthFact 'unreadable' 'notRecorded' } | Should -Not -Throw
        { New-WorkerPerfHealthFact 'unreadable' 'skipped:Wetter' } | Should -Throw; { New-WorkerPerfHealthValue 'unreadable' 'notRecorded' } | Should -Throw     # health.json kennt diese Gruende nicht
        { New-WorkerPerfHealthFact 'absent' 'notInUse' } | Should -Not -Throw; { New-WorkerPerfHealthValue 'absent' 'notInUse' } | Should -Throw
    }
    It 'nennt nicht zutreffend, was auf diesem Worker nicht gilt' {   # Review Focus 3
        $na = { param($f, $id, $reason) $f[$id].State | Should -Be 'absent' -Because $id; $f[$id].Reason | Should -Be $reason -Because $id }
        $f = Get-Facts @{ 'size.model' = 'Microsoft Corporation Virtual Machine'; 'size.vmtoolsVersion' = (New-WorkerPerfHealthValue 'absent' 'notInstalled'); 'size.netAdapters' = @(@{ Name = 'Microsoft Hyper-V Network Adapter'; Enabled = $true })
            'network.rss' = @(@{ Description = 'Microsoft Hyper-V Network Adapter'; Enabled = $false }); 'vda.wemService' = (New-WorkerPerfHealthValue 'absent' 'notInstalled'); 'vda.version' = '2203'
            'print.citrixPrintService' = 'Stopped'; 'security.defenderExclusionProcesses' = @() }
        $f['size.vmware'].Value | Should -BeFalse                                                              # keine VMware-VM: die VMware-Pruefungen treffen nicht zu
        foreach ($id in 'size.vmtoolsMajor', 'size.balloonRunning', 'size.otherNetAdapters', 'size.lsiControllers', 'network.rssOff', 'vda.wemServicesNotReady', 'security.wemExclusionsMissing') { & $na $f $id 'notInstalled' }
        & $na $f 'print.citrixMapping' 'notInUse'                                                               # der Citrix-Druckdienst laeuft nicht
        & $na (Get-Facts @{ 'print.citrixPrintService' = (New-WorkerPerfHealthValue 'absent' 'notInstalled') }) 'print.citrixMapping' 'notInUse'
        & $na (Get-Facts @{ 'print.mappingClientVersion' = (New-WorkerPerfHealthValue 'absent' 'notInstalled') }) 'print.mappingClientRelease' 'notInstalled'      # kein Client des Zuordnungswerkzeugs
        (Get-Facts @{ 'print.mappingClientVersion' = '5.9.3' })['print.mappingClientRelease'].Value | Should -Be 509; (Get-Facts @{ 'print.mappingClientVersion' = '6.10' })['print.mappingClientRelease'].Value | Should -Be 610
        $x = (Get-Facts @{ 'print.mappingClientVersion' = 'unbekannt' })['print.mappingClientRelease']; $x.State | Should -Be 'unreadable'; $x.Reason | Should -Be 'error'
        (Get-Facts @{ 'print.citrixPrintService' = (New-WorkerPerfHealthValue 'unreadable' 'rights') })['print.citrixMapping'].State | Should -Be 'unreadable'
        # eine VMware-VM ohne Tools und ohne Ballon-Treiber: gelesen, 0 und nein
        $v = Get-Facts @{ 'size.model' = 'VMware, Inc. VMware7,1'; 'size.vmtoolsVersion' = (New-WorkerPerfHealthValue 'absent' 'notInstalled'); 'size.balloonDriver' = (New-WorkerPerfHealthValue 'absent' 'notInstalled') }
        $v['size.vmtoolsMajor'].State | Should -Be 'read'; $v['size.vmtoolsMajor'].Value | Should -Be 0; $v['size.balloonRunning'].Value | Should -BeFalse
        # WEM: der Ordner des Agenten ist ausgenommen, oder seine Prozesse fehlen in der Liste
        $w = @{ 'vda.wemService' = 'Running'; 'security.defenderExclusionProcesses' = @(@{ Path = 'C:\Program Files (x86)\Citrix\Workspace Environment Management Agent\VUEMUIAgent.exe' }) }
        (Get-Facts ($w + @{ 'security.defenderExclusionPaths' = @() }))['security.wemExclusionsMissing'].Value | Should -Be 2
        (Get-Facts ($w + @{ 'security.defenderExclusionPaths' = @(@{ Path = 'C:\Program Files (x86)\Citrix\Workspace Environment Management Agent' }) }))['security.wemExclusionsMissing'].Value | Should -Be 0
        (Get-Facts ($w + @{ 'security.defenderExclusionPaths' = (New-WorkerPerfHealthValue 'unreadable' 'rights') }))['security.wemExclusionsMissing'].State | Should -Be 'unreadable'
    }
    It 'bildet die Fakten der Anwendungen aus den Zeilen der Proben' {
        $cat = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue) $TestApps
        $row = { param($app, $id, $state, $reason, $value, $names) [ordered]@{ App = $app; Id = $id; Kind = 'registryValue'; Read = 'value'; State = $state; Reason = $reason; Value = $value; Names = $names } }
        $rows = @((& $row 'edge' 'installed' 'read' '' $true $null), (& $row 'edge' 'backgroundMode' 'read' '' 1 $null), (& $row 'edge' 'userDataDir' 'read' '' $null '\\fs01\edge$'),
            (& $row 'edge' 'sleepingTabs' 'absent' '' $null $null), (& $row 'simapp' 'installed' 'read' '' $false $null), (& $row 'simapp' 'cacheMode' 'absent' 'notInstalled' $null $null))
        $f = Get-WorkerPerfHealthFacts -Model (New-HealthModel @{ 'apps.probes' = $rows }) -Catalogue $cat -EventConfig $Cfg -Roles $Roles
        @($f.Keys).Count | Should -Be 206; @($f.Keys)[164] | Should -BeLike 'apps.*'
        $f['apps.edge.installed'].Value | Should -BeTrue; $f['apps.edge.backgroundMode'].Value | Should -Be 1; $f['apps.edge.userDataDir'].Value | Should -Be '\\fs01\edge$'
        $f['apps.edge.sleepingTabs'].State | Should -Be 'absent'; $f['apps.edge.sleepingTabs'].Reason | Should -Be ''
        $f['apps.simapp.installed'].Value | Should -BeFalse; $f['apps.simapp.cacheMode'].State | Should -Be 'absent'; $f['apps.simapp.cacheMode'].Reason | Should -Be 'notInstalled'
        $f['apps.edge.autoDiscard'].State | Should -Be 'unreadable'; $f['apps.edge.autoDiscard'].Reason | Should -Be 'notRecorded'      # die Aufzeichnung hat fuer diese Probe keine Zeile
        $f['apps.office.installed'].Reason | Should -Be 'notRecorded'
        $u = Get-WorkerPerfHealthFacts -Model (New-HealthModel @{ 'apps.probes' = (New-WorkerPerfHealthValue 'unreadable' 'timeout') }) -Catalogue $cat -EventConfig $Cfg -Roles $Roles
        $u['apps.edge.installed'].State | Should -Be 'unreadable'; $u['apps.edge.installed'].Reason | Should -Be 'timeout'
    }
    It 'zaehlt Treiber und Ereignisse aus der Aufzeichnung' {
        $drv = @(@{ Name = 'A'; Manufacturer = 'HP'; Type = 3; Isolation = 'none' }, @{ Name = 'B'; Manufacturer = 'Microsoft'; Type = 4; Isolation = 'shared' }, @{ Name = 'C'; Manufacturer = 'Alt'; Type = 2; Isolation = 'none' },
            @{ Name = 'D'; Manufacturer = 'Citrix Systems, Inc.'; Type = 3; Isolation = 'shared' })
        $ev = @((New-Ev 1 'crash' 'app' 'EXCEL.EXE'), (New-Ev 1.1 'crash' 'app' 'EXCEL.EXE'), (New-Ev 2 'crash' 'app' 'spoolsv.exe'), (New-Ev 3 'system' 'storage'), (New-Ev 9 'crash' 'app' 'x.exe'))
        $f = Get-Facts @{} @{ PrintDrivers = $drv; EventsBefore = $ev }
        $f['print.driverCount'].Value | Should -Be 4; $f['print.driversInSpooler'].Value | Should -Be 2; $f['print.driversV2'].Value | Should -Be 1
        $f['print.vendorDrivers'].Value | Should -Be 2; $f['print.citrixDrivers'].Value | Should -Be 1
        # gezaehlt wird ab CaptureStartMs minus EventLookbackDays: der Absturz von vor neun Tagen zaehlt nicht
        $f['events.crashDays'].Value | Should -Be 1; $f['events.storageCount'].Value | Should -Be 1; $f['events.fileserverDays'].Value | Should -Be 0; $f['events.lookbackDays'].Value | Should -Be 7
        $days = @($f['events.perDay'].Value); $days.Count | Should -Be 3; $days[2].Day | Should -Be '2026-01-14'; $days[2].Crash | Should -Be 2; $days[1].Print | Should -Be 1; $days[0].Storage | Should -Be 1
        (Get-WorkerPerfHealthEventCount -Model (New-HealthModel @{} @{ EventsBefore = $ev }) -EventConfig $Cfg -Kind 'print' -Days 7).Count | Should -Be 1
        (Get-WorkerPerfHealthEventCount -Model (New-HealthModel @{} @{ EventsBefore = $ev }) -EventConfig $Cfg -Kind 'system.storage' -Days 2).Count | Should -Be 0
        # die Ereignisse der ganzen Messung zaehlen mit (EventsAll, nicht der Ausschnitt Events); ohne Ereignisse zaehlt nur der Rueckblick
        $cap = @((New-Ev -0.01 'crash' 'app' 'spoolsv.exe'))
        $n = Get-WorkerPerfHealthEventCount -Model (New-HealthModel @{} @{ EventsAll = $cap; Events = @() }) -EventConfig $Cfg -Kind 'print' -Days 7; $n.Count | Should -Be 1; $n.Known | Should -BeTrue
        (Get-WorkerPerfHealthEventCount -Model (New-HealthModel @{} @{ EventsAll = $cap; Skip = [string[]]@('Ereignisse') }) -EventConfig $Cfg -Kind 'print' -Days 7).Count | Should -Be 0
    }
    It 'nennt den Grund, wenn Treiberliste oder Rueckblick nicht gelesen wurden' {   # Review Focus 5
        $s = Get-Facts @{} @{ Skip = [string[]]@('Rueckblick', 'Drucken'); Meta = @{ EventLookbackDays = 0; HealthOnly = $false; OffsetMinutes = 60; Computer = 'T1' } }
        $s['print.driversInSpooler'].State | Should -Be 'unreadable'; $s['print.driversInSpooler'].Reason | Should -Be 'skipped:Drucken'
        $s['events.crashDays'].State | Should -Be 'unreadable'; $s['events.crashDays'].Reason | Should -Be 'skipped:Rueckblick'; $s['events.lookbackDays'].Value | Should -Be 0
        $nr = Get-Facts @{} @{ Recorded = @{ EventsBefore = $false; PrintDrivers = $false } }                       # die Dateien fehlen in der Aufzeichnung
        $nr['events.crashDays'].Reason | Should -Be 'notRecorded'; $nr['events.perDay'].State | Should -Be 'unreadable'; $nr['print.driverCount'].Reason | Should -Be 'notRecorded'
        $bad = Get-Facts @{} @{ SourceErrors = @((New-SourceError 'eventsbefore.system'), (New-SourceError 'printdrivers')) }   # das Lesen ist gescheitert
        $bad['events.crashDays'].State | Should -Be 'unreadable'; $bad['events.crashDays'].Reason | Should -Be 'error'; $bad['print.driversInSpooler'].Reason | Should -Be 'error'
        $bad['events.lookbackDays'].Value | Should -Be 7
        $part = Get-Facts @{} @{ EventsBefore = @((New-Ev 1 'crash' 'app' 'EXCEL.EXE')); SourceErrors = @((New-SourceError 'eventsbefore.system')) }
        $part['events.crashDays'].State | Should -Be 'read'; $part['events.crashDays'].Value | Should -Be 1            # ein Protokoll scheiterte, die anderen wurden gelesen
        (Get-WorkerPerfHealthEventCount -Model (New-HealthModel @{} @{ Recorded = @{ EventsBefore = $false; PrintDrivers = $true } }) -EventConfig $Cfg -Kind 'print' -Days 7).Known | Should -BeFalse
        Get-WorkerPerfHealthMissingReason -Model (New-HealthModel) -What 'lookback' | Should -Be ''; Get-WorkerPerfHealthMissingReason -Model (New-HealthModel) -What 'drivers' | Should -Be ''
    }
    It 'bildet das Ereignisbild der Protokolle' {
        $log = { param($name, $mode, $full, $enabled, $oldestDays) @{ Log = $name; Present = $true; Enabled = $enabled; MaxSizeMB = 20; FileSizeMB = 20; Records = 1; Mode = $mode; Full = $full; Oldest = $ReadMs - [long]($oldestDays * 86400000) } }
        $f = Get-Facts @{ 'events.logs' = @((& $log 'Application' 'Circular' $false $true 3.5), (& $log 'System' 'Retain' $true $true 30), (& $log 'Microsoft-Windows-PrintService/Admin' 'Circular' $false $false 30)
                @{ Log = 'Microsoft-Windows-SMBClient/Connectivity'; Present = $false }) }
        $f['events.coverageGapDays'].Value | Should -Be 4; $f['events.retainLogs'].Value | Should -Be 1; $f['events.fullLogs'].Value | Should -Be 1; $f['events.disabledLogs'].Value | Should -Be 1
        $f['events.reachFrom'].Value | Should -Be ($ReadMs - [long](3.5 * 86400000))                         # ab hier reichen alle eingeschalteten Protokolle
        # reichen die Protokolle nur bis zum letzten Start? (das abgeschaltete und das fehlende Protokoll zaehlen nicht)
        $since = { param($bootDays, $oldestDays) (Get-Facts @{ 'operation.lastBoot' = $ReadMs - [long]($bootDays * 86400000)
                'events.logs' = @((& $log 'Application' 'Circular' $false $true $oldestDays), (& $log 'System' 'Circular' $false $true ($oldestDays - 0.1)), (& $log 'Microsoft-Windows-PrintService/Admin' 'Circular' $false $false 30)) })['events.sinceBootOnly'] }
        (& $since 2 1.9).Value | Should -BeTrue; (& $since 2 2.003).Value | Should -BeTrue                    # bis zehn Minuten vor dem Start zaehlt als "seit dem Start"
        (& $since 2 2.5).Value | Should -BeFalse; (& $since 2 30).Value | Should -BeFalse
        $f['events.sinceBootOnly'].State | Should -Be 'absent'                                                # ohne gelesenen letzten Start
        (Get-Facts @{ 'operation.lastBoot' = $ReadMs - 86400000; 'events.logs' = @(@{ Log = 'Application'; Present = $true; Enabled = $true; Oldest = 0 }) })['events.sinceBootOnly'].Value | Should -BeFalse   # kein Eintrag
    }
    It 'erkennt Schutzprodukte der Rollenliste an Diensten und Filtertreibern' {
        @(($Roles | Where-Object label -eq 'Microsoft Defender').filters) | Should -Be @('WdFilter'); @(($Roles | Where-Object label -eq 'AppLocker').filters).Count | Should -Be 0
        $f = Get-Facts @{ 'security.services' = @(@{ Name = 'WinDefend'; State = 'Running'; StartMode = 'Auto' }, @{ Name = 'CylanceSvc'; State = 'Running'; StartMode = 'Auto' }, @{ Name = 'AppIDSvc'; State = 'Stopped'; StartMode = 'Manual' })
            'security.filters' = @(@{ Name = 'WdFilter'; Altitude = '328010' }, @{ Name = 'CyProtectDrv64'; Altitude = '388510' }); 'security.mdeOnboarding' = 1; 'vda.version' = '2203'
            'security.defenderExclusionProcesses' = @(@{ Path = 'C:\Program Files\Citrix\User Profile Manager\UserProfileManager.exe' }) }
        $f['security.otherFilterProducts'].Value | Should -Be 1; $f['security.products'].Value | Should -Be 'Microsoft Defender, Arctic Wolf Aurora Endpoint Protection'
        $f['security.mdeOnboarded'].Value | Should -BeTrue; $f['security.citrixExclusionsMissing'].Value | Should -Be 2
        (Get-Facts @{})['security.mdeOnboarded'].Value | Should -BeFalse
    }
    It 'erkennt Aufgaben, Scans und Updates in der Arbeitszeit des Servers' {
        $t = { param($path, $on, $hours, $trig, $rep) @{ Path = $path; Enabled = $on; State = 'Ready'; NextRun = $(if ($null -eq $hours) { 0 } else { $ReadMs + [long]($hours * 3600000) }); LastRun = 0; Triggers = $trig; RepeatMinutes = $rep; Action = 'x.exe' } }
        $tasks = @((& $t '\A' $true 2 'daily' 0), (& $t '\B' $true 18 'daily' 0), (& $t '\C' $false 2 'daily' 0), (& $t '\D' $true 50 'weekly' 0), (& $t '\E' $true $null 'logon, idle' 0), (& $t '\F' $true 18 'time' 15))
        # A: Donnerstag 10:00; B: Freitag 02:00; C: abgeschaltet; D: Samstag 10:00; E: ohne naechsten Lauf, Anmeldung; F: Freitag 02:00, wiederholt sich alle 15 Minuten
        $f = Get-Facts @{ 'maintenance.tasks' = $tasks; 'maintenance.scanDay' = 0; 'maintenance.scanTime' = '12:30'; 'maintenance.updateOptions' = 4; 'maintenance.updateDay' = 7; 'maintenance.updateHour' = 10 }
        $f['maintenance.tasksInWorkHours'].Value | Should -Be 2; $f['maintenance.sessionTriggerTasks'].Value | Should -Be 1
        $f['maintenance.scanInWorkHours'].Value | Should -BeTrue; $f['maintenance.updateInWorkHours'].Value | Should -BeFalse           # Tag 7 ist Samstag
        (Get-Facts @{ 'maintenance.scanDay' = 8; 'maintenance.scanTime' = '12:30' })['maintenance.scanInWorkHours'].Value | Should -BeFalse
        (Get-Facts @{})['maintenance.updateInWorkHours'].Value | Should -BeFalse                                                        # keine Richtlinie
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Health.Tests.ps1`
Expected: FAIL, `Get-WorkerPerfHealthFacts` ist nicht definiert

- [ ] **Step 3: `filters` in `Read-WorkerPerfRoles` und `src/roles.json` ergänzen**

- [ ] **Step 4: `New-WorkerPerfHealthFact`, `Get-WorkerPerfHealthMissingReason`, `Get-WorkerPerfHealthFacts` und `Get-WorkerPerfHealthEventCount` mit den Signaturen der Interfaces und den Regeln der Tabellen umsetzen**

- [ ] **Step 5: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 6: Commit**

```bash
git add src/WorkerPerf.Health.ps1 src/WorkerPerf.Common.ps1 src/roles.json tests/Health.Tests.ps1
git commit -m "Derive health facts from the recorded values"
```

---

### Task 13: Bewertung

**Files:**
- Modify: `src/WorkerPerf.Health.ps1`
- Test: `tests/Health.Tests.ps1`
- Mit dem geführten Bericht geteilt: keine. Nicht anfassen: `src/WorkerPerf.Events.ps1`, `src/WorkerPerf.Guidance.ps1`, `src/New-WorkerPerfReport.ps1`.

**Interfaces:**
- Consumes: Tasks 11 und 12; `$script:WorkerPerfHealthAreaErrors` (Task 1a); `Format-WorkerPerfTextNumber`; die Texte `skip.label.<Kategorie>`; aus dem Modell zusätzlich `Meta.Computer`.
- Produces:
  - `Test-WorkerPerfHealthRule -Conditions -Facts -Model -EventConfig -Catalogue -> @{ Result; Reason; EventsUnknown }`: `Result` `true`, `false`, `na` oder `unknown` nach der Regel der vier Werte (Abschnitt Entscheidungen); `Reason` der Grund des ersten Fakts, der die Regel unbekannt oder nicht zutreffend macht; `EventsUnknown`, wenn eine Bedingung `event` unbekannt ist. Eine Bedingung `event` ist wahr, wenn `Count` ≥ `min` ist, sonst falsch, wenn `Known` wahr ist, sonst unbekannt (`Get-WorkerPerfHealthEventCount`). Vergleiche: Zahlen als Zahlen, Texte ohne Rücksicht auf Groß- und Kleinschreibung; `in` gegen eine Liste, `contains` als Teiltext; `@<Schwelle>` nimmt `value` der Schwelle.
  - `Format-WorkerPerfHealthFact($Fact, [string]$Type, [string]$Unit, $Catalogue, [int]$OffsetMinutes) -> string`: Zahl über `Format-WorkerPerfTextNumber` mit Einheit; Wahrheitswert `copy.yes`/`copy.no`; Zeit `dd.MM.yyyy HH:mm` in der Ortszeit des Servers (0 → `copy.noValue`); ein Fakt, der nicht gelesen ist, `copy.noValue`; ein Fakt vom Typ `value` (der Wert einer Probe einer Anwendung) nach der Art seines Werts: Zahl, Wahrheitswert oder Text, wie er ist.
  - `Get-WorkerPerfHealthResult -Model -Catalogue -EventConfig -Roles -Texts -> [ordered]`:
    - `state` (= `Model.HealthState`); bei `notRecorded` und `unreadable` dazu `text`: `copy.notRecorded` bzw. `copy.unreadable`; hat bei `notRecorded` `Model.SourceErrors` einen Eintrag `health` (das Lesen ist beim Start gescheitert), stattdessen `copy.notRecordedFailed`. Bei `skipped` ist `text` leer. Dann sind `areas` und `raw` leer, und es gibt kein `summary`.
    - bei `read`: `readAt` (ms), `offsetMin` (= `Model.Health.OffsetMinutes`, der Offset der Serverzeit zum Lesezeitpunkt), `durationMs`, `catalogueVersion`, `grades`, `areas`, `summary`, `changed`, `unknownCount`, `raw`, dazu `environmentText` (`copy.environment`: der Satz, dass der Katalog von nicht persistenten, über MCS bereitgestellten Multi-Session-Workern ausgeht) und `eventsReachText` (`copy.eventsReach` mit `{from}` = `events.reachFrom` und `{boot}` = `operation.lastBoot`, beide als `dd.MM.yyyy HH:mm` in der Ortszeit des Servers; `copy.noValue`, wo der Fakt nicht gelesen ist).
    - Was aus dem Katalog in das Ergebnis geht (`grades`, je Prüfung `source` und `todo[]`), ist als geordnetes Wörterbuch bzw. Array kopiert, nie ein `pscustomobject`: der JSON-Schreiber des Berichts schriebe ein solches Objekt als einen einzigen Text.
    - `areas[]`: `[ordered]@{ id; label; grade; status; statusText; error; notCovered; intro; apps; counts = [ordered]@{ act; check; unknown; ok }; countsText; checks }`. `intro` ist leer außer im Bereich `events`: dort `eventsReachText`. `apps` ist leer außer im Bereich `apps`: je Anwendung der Anwendungsliste (`$Catalogue.appList`), die `installed` nennt, `[ordered]@{ key; label; state; text }` mit `state` `installed`, `notInstalled` oder `unknown` (der Fakt `apps.<key>.installed` ist nicht gelesen) und `text` aus `copy.appInstalled`, `copy.appNotInstalled` bzw. `copy.appUnknown` (mit dem Text des Grunds). `grade` = die schlechteste Einstufung der Prüfungen aus `act`, `check`, sonst `ok`. `statusText` ist leer bei `status` `read`, sonst `copy.areaPartial` bzw. `copy.areaFailed`; trägt `Error` der Datei ein Kennwort aus `$script:WorkerPerfHealthAreaErrors`, folgt nach einem Leerzeichen dessen Text (`copy.areaReasonBudget`, `copy.areaReasonNoReader`, `copy.areaReasonNotRead`, `copy.areaReasonNotInFile`). `error` ist `Error` der Datei, wenn es kein Kennwort ist (die Meldung von Windows), sonst leer. `countsText` nennt die Prüfungen, die nicht in Ordnung sind: `copy.countsAct`, `copy.countsCheck`, `copy.countsUnknown` für jede Zahl über 0, mit „, " verbunden; leer, wenn alle in Ordnung sind. `checks` geordnet nach `act`, `check`, `unknown`, `ok`, `na`, darin in der Reihenfolge des Katalogs. Eine Prüfung mit dem Ergebnis `na` zählt in keiner Zahl des Bereichs und nicht in `unknownCount`.
    - `checks[]`: `[ordered]@{ id; title; grade; app; finding; why; note; value; meaning; todo; source; kind; kindLabel; relates }`. `grade` ist eine der vier Einstufungen oder `na`; `app` ist bei einer Prüfung des Bereichs `apps` die Kennung ihrer Anwendung, sonst leer. `finding` aus `findings.<grade>` mit eingesetzten Fakten und Schwellen. Das Ergebnis `na` entsteht auf zwei Wegen, beide mit `finding` = `copy.notApplicable` (`{reason}` = `why`): (a) die Anwendung der Prüfung ist nicht installiert (`apps.<key>.installed` ist gelesen und falsch): `why` = `copy.reasonAppNotInstalled`, keine Regel wird ausgewertet; (b) die Regel `check` trifft nicht zu: `why` = `copy.reasonNotInstalled` bzw. `copy.reasonNotInUse` mit der Bezeichnung des Fakts, der sie nicht zutreffend macht. Ist `apps.<key>.installed` nicht lesbar, ist die Prüfung `unknown` mit dessen Grund. `why` bei `unknown`: der Text des Grunds (`copy.reasonRights`, `reasonTimeout`, `reasonError`, `reasonAbsent`, `reasonNotRecorded`, `reasonSkipped` mit `skip.label.<Kategorie>` aus den Texten), in `findings.unknown` als `{reason}`; `note` = `copy.eventsUnchecked`, wenn die Einstufung `check` ist und die Regel `act` wegen nicht gelesener Ereignisse unbekannt blieb, sonst leer; `value` = „<Bezeichnung>: <Wert>" je Fakt aus `values`, mit „; " verbunden; `kindLabel` = `copy.kindVendor`, `copy.kindPractice` bzw. `copy.kindRule`. Für einen Fakt vom Typ `text:free` nennt `value` statt des Werts `copy.valueSet` bzw. `copy.valueNotSet`: der Wert selbst steht nur in den Rohwerten.
    - `summary`: `[ordered]@{ act; check; ok; text }` (Zahl der Bereiche je Einstufung; `text` aus `copy.summary`, `{act}` als `copy.areaOne` bzw. `copy.areaMany`); `unknownCount` = Zahl der Prüfungen mit `unknown`; `changed` = `Get-WorkerPerfHealthChangedThresholds`.
    - `raw[]`: je Fakt von `Get-WorkerPerfHealthFactTable $Catalogue.appList` `[ordered]@{ area; id; label; derived; state; stateText; reason; text; free; items }`. `label` aus `values` des Katalogs, bei einem Anwendungswert aus der Faktentabelle (`Label`; bei `apps.<key>.installed` „<Bezeichnung der Anwendung> – " und `copy.appInstalledLabel`). `stateText`: `copy.stateRead`, `copy.stateAbsent`, `copy.stateUnreadable` (mit dem Text des Grunds) oder, bei `absent` mit `notInstalled` oder `notInUse`, `copy.stateNotApplicable` (mit dem Text des Grunds: so zeigt die Rohwertanzeige „nicht zutreffend"). Ein einzelner Wert: `text` der formatierte Wert, bei `text:free` stattdessen `free`; eine Liste: `items[]` mit `text` („Feld: Wert" je Feld ohne `:free`, mit „; " verbunden) und `free` (ebenso die Felder mit `:free`); nicht gelesene Werte haben leere Texte.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/Health.Tests.ps1`; die weiteren Helfer stehen im `BeforeAll` am Dateianfang hinter denen aus Task 12)

```powershell
    # in BeforeAll am Dateianfang:
    function Get-Check([hashtable]$Values, [hashtable]$With = @{}, [string]$Id = 'operation.diskFree', $Catalogue = $script:Cat) {
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel $Values $With) -Catalogue $Catalogue -EventConfig $Cfg -Roles $Roles -Texts $Texts
        @($r.areas | ForEach-Object { $_.checks }) | Where-Object id -eq $Id }
    $script:NoLookback = @{ Skip = [string[]]@('Ereignisse', 'Rueckblick'); Meta = @{ EventLookbackDays = 0; HealthOnly = $false; OffsetMinutes = 60; Computer = 'T1' } }
    $script:HpNone = @(@{ Name = 'A'; Manufacturer = 'HP'; Type = 3; Isolation = 'none' })
    function Get-Vol([double]$Free) { @{ 'operation.volumes' = @(@{ Drive = 'C:'; SizeGB = 100; FreeGB = $Free; FileSystem = 'NTFS'; System = $true; PageFile = $true }) } }

Describe 'Bewertung' {
    It 'stuft <Grade> ein bei <Free> GB frei' -TestCases @(
        @{ Free = 38; Grade = 'ok'; Finding = '38 GB frei.' }
        @{ Free = 8.5; Grade = 'check'; Finding = 'Nur 8,5 GB frei (Schwelle 10 GB).' }
        @{ Free = 1.5; Grade = 'act'; Finding = 'Nur 1,5 GB frei.' }
    ) { $c = Get-Check (Get-Vol $Free); $c.grade | Should -Be $Grade; $c.finding | Should -Be $Finding; $c.app | Should -Be ''; $c.why | Should -Be ''; $c.value | Should -Match '^Wert operation\.minFreeGB: ' }
    It 'nennt nicht pruefbar mit dem Grund' {   # Review Focus 1
        $c = Get-Check @{ 'operation.volumes' = (New-WorkerPerfHealthValue 'unreadable' 'rights') }
        $c.grade | Should -Be 'unknown'; $c.why | Should -Be 'Text reasonRights'; $c.finding | Should -Be 'Nicht prüfbar: Text reasonRights.'
        (Get-Check @{} @{ Skip = [string[]]@('Drucken') } 'print.driversInSpooler').why | Should -Be 'Drucken nicht erfasst'
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel @{} @{ Skip = [string[]]@('Drucken') }) -Catalogue $Cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        $o = $r.areas | Where-Object id -eq 'operation'; $o.status | Should -Be 'read'; $o.checks[0].grade | Should -Be 'unknown'; $o.checks[0].why | Should -Be 'Text reasonAbsent'
        $o.grade | Should -Be 'ok'; $o.counts.unknown | Should -Be 1                                                    # nicht pruefbar allein macht den Bereich nicht auffaellig
    }
    It 'nennt den Grund eines nicht gelesenen Bereichs mit dem Text des Katalogs' {   # Review Focus 1
        $m = New-HealthModel
        $m.Health.Areas['operation'] = Complete-WorkerPerfHealthArea 'operation' @{} 0 'budget' $true
        $m.Health.Areas['print'] = Complete-WorkerPerfHealthArea 'print' @{ 'print.queueCount' = (New-WorkerPerfHealthValue 'read' '' 2) } 3 'Zugriff verweigert'
        $r = Get-WorkerPerfHealthResult -Model $m -Catalogue $Cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        $o = $r.areas | Where-Object id -eq 'operation'; $o.status | Should -Be 'failed'; $o.statusText | Should -Be 'Text areaFailed Text areaReasonBudget'; $o.error | Should -Be ''
        $o.checks[0].grade | Should -Be 'unknown'; $o.checks[0].why | Should -Be 'Text reasonTimeout'; $o.grade | Should -Be 'ok'; $o.countsText | Should -Be '1 nicht prüfbar'
        $p = $r.areas | Where-Object id -eq 'print'; $p.status | Should -Be 'partial'; $p.statusText | Should -Be 'Text areaPartial'; $p.error | Should -Be 'Zugriff verweigert'
        ($r.areas | Where-Object id -eq 'size').statusText | Should -Be ''; ($r.areas | Where-Object id -eq 'size').countsText | Should -Be ''
    }
    It 'macht handeln nur mit harter Grenze oder mit Dauerzustand und Ereignis' {
        (Get-Check @{} @{ PrintDrivers = $HpNone } 'print.driversInSpooler').grade | Should -Be 'check'
        (Get-Check @{} @{ PrintDrivers = $HpNone; EventsBefore = @((New-Ev 2 'crash' 'app' 'spoolsv.exe')) } 'print.driversInSpooler').grade | Should -Be 'act'
        (Get-Check @{} @{ PrintDrivers = $HpNone; EventsBefore = @((New-Ev 2 'crash' 'app' 'EXCEL.EXE')) } 'print.driversInSpooler').grade | Should -Be 'check'      # ein anderes Ereignis zaehlt nicht
        (Get-Check @{} @{ PrintDrivers = $HpNone; EventsBefore = @((New-Ev 8 'crash' 'app' 'spoolsv.exe')) } 'print.driversInSpooler').grade | Should -Be 'check'    # aelter als sieben Tage
        (Get-Check @{} @{ PrintDrivers = $HpNone; EventsAll = @((New-Ev -0.01 'crash' 'app' 'spoolsv.exe')); Events = @() } 'print.driversInSpooler').grade | Should -Be 'act'   # Ereignis der Messung, auch ausserhalb von -From und -To
        (Get-Check @{} @{ PrintDrivers = @(); EventsBefore = @((New-Ev 2 'crash' 'app' 'spoolsv.exe')) } 'print.driversInSpooler').grade | Should -Be 'ok'           # Ereignis ohne Dauerzustand
    }
    It 'bleibt bei pruefen und sagt es, wenn die Ereignisse nicht gelesen wurden' {   # Review Focus 5
        $c = Get-Check @{} (@{ PrintDrivers = $HpNone } + $NoLookback) 'print.driversInSpooler'
        $c.grade | Should -Be 'check'; $c.note | Should -Be 'Text eventsUnchecked'
        (Get-Check @{} @{ PrintDrivers = $HpNone } 'print.driversInSpooler').note | Should -Be ''
        (Get-Check @{} (@{ PrintDrivers = @() } + $NoLookback) 'print.driversInSpooler').grade | Should -Be 'ok'
        # ein Schnelllauf ohne Rueckblick, und eine Aufzeichnung, in der die Datei des Rueckblicks fehlt: dieselbe Lage
        $ho = @{ PrintDrivers = $HpNone; Skip = [string[]]@('Rueckblick'); Meta = @{ EventLookbackDays = 0; HealthOnly = $true; OffsetMinutes = 60; Computer = 'T1' } }
        (Get-Check @{} $ho 'print.driversInSpooler').note | Should -Be 'Text eventsUnchecked'
        (Get-Check @{} @{ PrintDrivers = $HpNone; Recorded = @{ EventsBefore = $false; PrintDrivers = $true } } 'print.driversInSpooler').note | Should -Be 'Text eventsUnchecked'
    }
    It 'wertet nicht gesetzt als Wert und ein fehlendes Produkt als nicht zutreffend' {   # Review Focus 3
        $cat = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue {
            $c.checks[0].id = 'print.isolationOff'; $c.checks[0].area = 'print'; $c.checks[0].values = @('print.isolationExecution')
            $c.checks[0].rules = @{ check = @(@{ value = 'print.isolationExecution'; op = 'exists' }, @{ value = 'print.isolationExecution'; op = 'eq'; than = 0 }) }
            $c.checks[0].findings = @{ ok = 'Isolierung nicht abgeschaltet.'; check = 'Isolierung abgeschaltet.'; unknown = '{reason}' }
            $c.checks[1].id = 'security.signatureAge'; $c.checks[1].area = 'security'; $c.checks[1].values = @('security.defenderSignatureAgeDays'); $c.checks[1].kind = 'rule'; $c.checks[1].relates = @('system')
            $c.checks[1].rules = @{ check = @(@{ value = 'security.defenderSignatureAgeDays'; op = 'gt'; than = 2 }) }
            $c.checks[1].findings = @{ ok = 'Signaturen {security.defenderSignatureAgeDays} Tage alt.'; check = 'alt'; unknown = '{reason}' } })
        (Get-Check @{} @{} 'print.isolationOff' $cat).grade | Should -Be 'ok'                                          # der Wert fehlt: keine Richtlinie
        (Get-Check @{ 'print.isolationExecution' = 0 } @{} 'print.isolationOff' $cat).grade | Should -Be 'check'
        (Get-Check @{ 'print.isolationExecution' = 1 } @{} 'print.isolationOff' $cat).grade | Should -Be 'ok'
        (Get-Check @{ 'print.isolationExecution' = (New-WorkerPerfHealthValue 'unreadable' 'error') } @{} 'print.isolationOff' $cat).grade | Should -Be 'unknown'
        $n = Get-Check @{ 'security.defenderSignatureAgeDays' = (New-WorkerPerfHealthValue 'absent' 'notInstalled') } @{} 'security.signatureAge' $cat
        $n.grade | Should -Be 'na'; $n.why | Should -Be 'Wert security.defenderSignatureAgeDays fehlt'; $n.finding | Should -Be 'Trifft nicht zu: Wert security.defenderSignatureAgeDays fehlt.'
        (Get-Check @{} @{} 'security.signatureAge' $cat).grade | Should -Be 'unknown'                                   # fehlt ohne Grund bei einem Vergleich: nicht pruefbar
        (Get-Check @{ 'security.defenderSignatureAgeDays' = 1 } @{} 'security.signatureAge' $cat).finding | Should -Be 'Signaturen 1 Tage alt.'
        # trifft nicht zu wird nicht gezaehlt und macht den Bereich nicht auffaellig
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel @{ 'security.defenderSignatureAgeDays' = (New-WorkerPerfHealthValue 'absent' 'notInstalled') }) -Catalogue $cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        $s = $r.areas | Where-Object id -eq 'security'; $s.grade | Should -Be 'ok'; $s.countsText | Should -Be ''; $s.checks[0].grade | Should -Be 'na'
        ($s.counts.act + $s.counts.check + $s.counts.unknown + $s.counts.ok) | Should -Be 0; $r.unknownCount | Should -Be 0
        ($r.raw | Where-Object id -eq 'security.defenderSignatureAgeDays').stateText | Should -Be 'Text stateNotApplicable'
    }
    It 'entscheidet Gleichheit auch fuer einen nicht gesetzten Wert und laesst Groessenvergleiche offen' {
        $f = Get-Facts @{ 'print.isolationExecution' = 0; 'security.defenderSignatureAgeDays' = (New-WorkerPerfHealthValue 'absent' 'notInstalled'); 'operation.pendingRename' = (New-WorkerPerfHealthValue 'unreadable' 'rights') }
        $t = { param($id, $op, $than) (Test-WorkerPerfHealthRule -Conditions @(@{ value = $id; op = $op; than = $than }) -Facts $f -Model (New-HealthModel) -EventConfig $Cfg -Catalogue $Cat).Result }
        # nicht gesetzt (absent ohne Grund): print.isolationOverride
        & $t 'print.isolationOverride' 'exists' $null | Should -Be 'false'; & $t 'print.isolationOverride' 'absent' $null | Should -Be 'true'
        & $t 'print.isolationOverride' 'eq' 0 | Should -Be 'false'; & $t 'print.isolationOverride' 'ne' 0 | Should -Be 'true'; & $t 'print.isolationOverride' 'in' @(0, 1) | Should -Be 'false'
        & $t 'print.isolationOverride' 'lt' 1 | Should -Be 'unknown'; & $t 'print.isolationOverride' 'ge' 1 | Should -Be 'unknown'
        # nicht installiert: trifft nicht zu, mit jedem Operator; nicht lesbar: unbekannt, mit jedem Operator
        foreach ($op in 'exists', 'absent', 'eq', 'ne', 'gt') { & $t 'security.defenderSignatureAgeDays' $op 1 | Should -Be 'na' -Because $op; & $t 'operation.pendingRename' $op 1 | Should -Be 'unknown' -Because $op }
        & $t 'print.isolationExecution' 'eq' 0 | Should -Be 'true'; & $t 'print.isolationExecution' 'ne' 0 | Should -Be 'false'; & $t 'print.isolationExecution' 'exists' $null | Should -Be 'true'
    }
    It 'stuft die Pruefungen einer Anwendung ein und zaehlt eine nicht installierte nicht' {   # Review Focus 3
        $cat = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue {
            $c.checks[0].id = 'apps.edgeBackgroundMode'; $c.checks[0].area = 'apps'; $c.checks[0].values = @('apps.edge.backgroundMode')
            $c.checks[0].rules = @{ check = @(@{ value = 'apps.edge.backgroundMode'; op = 'eq'; than = 1 }) }
            $c.checks[0].findings = @{ ok = 'Hintergrundmodus aus.'; check = 'Hintergrundmodus an ({apps.edge.backgroundMode}).'; unknown = 'Nicht prüfbar: {reason}.' }
            $c.checks[1].id = 'apps.simCache'; $c.checks[1].area = 'apps'; $c.checks[1].values = @('apps.simapp.cacheMode', 'apps.simapp.dataPath'); $c.checks[1].kind = 'rule'; $c.checks[1].relates = @('disk')
            $c.checks[1].rules = @{ check = @(@{ value = 'apps.simapp.cacheMode'; op = 'ne'; than = 2 }, @{ value = 'apps.simapp.dataPath'; op = 'exists' }) }
            $c.checks[1].findings = @{ ok = 'Cache in Ordnung.'; check = 'Cache-Betriebsart {apps.simapp.cacheMode}.'; unknown = 'Nicht prüfbar: {reason}.' } }) $TestApps
        $row = { param($app, $id, $state, $reason, $value, $names) [ordered]@{ App = $app; Id = $id; Kind = 'registryValue'; Read = 'value'; State = $state; Reason = $reason; Value = $value; Names = $names } }
        $edge = @((& $row 'edge' 'installed' 'read' '' $true $null), (& $row 'edge' 'backgroundMode' 'read' '' 1 $null))
        $res = { param($sim) Get-WorkerPerfHealthResult -Model (New-HealthModel @{ 'apps.probes' = @($edge + $sim) }) -Catalogue $cat -EventConfig $Cfg -Roles $Roles -Texts $Texts }
        $get = { param($r, $id) ($r.areas | Where-Object id -eq 'apps').checks | Where-Object id -eq $id }
        # die vierte Anwendung ist nicht installiert
        $r = & $res @((& $row 'simapp' 'installed' 'read' '' $false $null), (& $row 'simapp' 'cacheMode' 'absent' 'notInstalled' $null $null), (& $row 'simapp' 'dataPath' 'absent' 'notInstalled' $null $null))
        $a = $r.areas | Where-Object id -eq 'apps'; @($a.checks.id) | Should -Be @('apps.edgeBackgroundMode', 'apps.simCache'); @($a.checks.grade) | Should -Be @('check', 'na')
        $a.checks[0].finding | Should -Be 'Hintergrundmodus an (1).'; $a.checks[0].app | Should -Be 'edge'; $a.checks[1].app | Should -Be 'simapp'
        $a.checks[1].why | Should -Be 'Sim-Fachanwendung ist nicht installiert'; $a.checks[1].finding | Should -Be 'Trifft nicht zu: Sim-Fachanwendung ist nicht installiert.'
        $a.grade | Should -Be 'check'; $a.countsText | Should -Be '1 zum Prüfen'; $a.counts.ok | Should -Be 0; $a.counts.unknown | Should -Be 0; $r.summary.check | Should -Be 1
        @($a.apps.key) | Should -Be @($TestApps | Where-Object { $_.installed } | ForEach-Object key); ($a.apps | Where-Object key -eq 'edge').state | Should -Be 'installed'; ($a.apps | Where-Object key -eq 'simapp').state | Should -Be 'notInstalled'
        ($a.apps | Where-Object key -eq 'simapp').text | Should -Be 'Text appNotInstalled'; ($a.apps | Where-Object key -eq 'office').state | Should -Be 'unknown'       # die Aufzeichnung hat keine Zeile fuer Office
        @(($r.areas | Where-Object id -eq 'size').apps).Count | Should -Be 0
        # dieselbe Anwendung installiert: bewertet, ohne dass der Code sie kennt; der Pfad steht nur in den Rohwerten
        $r = & $res @((& $row 'simapp' 'installed' 'read' '' $true $null), (& $row 'simapp' 'cacheMode' 'read' '' 1 $null), (& $row 'simapp' 'dataPath' 'read' '' $null '\\fs01\simapp$'))
        $s = & $get $r 'apps.simCache'; $s.grade | Should -Be 'check'; $s.finding | Should -Be 'Cache-Betriebsart 1.'
        $s.value | Should -Be 'Sim-Fachanwendung – Cache-Betriebsart: 1; Sim-Fachanwendung – dataPath: Text valueSet'; ($s | ConvertTo-Json -Depth 6) | Should -Not -Match 'fs01'
        $raw = $r.raw | Where-Object id -eq 'apps.simapp.dataPath'; $raw.free | Should -Be '\\fs01\simapp$'; $raw.text | Should -Be ''; $raw.label | Should -Be 'Sim-Fachanwendung – dataPath'; $raw.area | Should -Be 'apps'
        ($r.raw | Where-Object id -eq 'apps.simapp.installed').label | Should -Be 'Sim-Fachanwendung – Text appInstalledLabel'; @($r.raw).Count | Should -Be 206
        (& $get (& $res @((& $row 'simapp' 'installed' 'read' '' $true $null), (& $row 'simapp' 'cacheMode' 'read' '' 2 $null), (& $row 'simapp' 'dataPath' 'read' '' $null 'D:\x'))) 'apps.simCache').grade | Should -Be 'ok'
        (& $get (& $res @((& $row 'simapp' 'installed' 'read' '' $true $null), (& $row 'simapp' 'cacheMode' 'absent' '' $null $null), (& $row 'simapp' 'dataPath' 'read' '' $null 'D:\x'))) 'apps.simCache').grade | Should -Be 'check'   # nicht gesetzt ist ungleich 2
        # die Installation laesst sich nicht lesen: nicht pruefbar mit dem Grund
        $u = & $get (& $res @((& $row 'simapp' 'installed' 'unreadable' 'rights' $null $null), (& $row 'simapp' 'cacheMode' 'unreadable' 'rights' $null $null))) 'apps.simCache'
        $u.grade | Should -Be 'unknown'; $u.why | Should -Be 'Text reasonRights'
    }
    It 'bewertet eine Pruefung zur Zuordnung ueber Citrix-Richtlinien nur, wo Citrix zuordnen kann' {   # Review Focus 3
        $cat = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue {
            $c.checks[0].id = 'print.citrixQueues'; $c.checks[0].area = 'print'; $c.checks[0].values = @('print.citrixMapping', 'print.queuesPerSession')
            $c.checks[0].rules = @{ check = @(@{ value = 'print.citrixMapping'; op = 'eq'; than = $true }, @{ value = 'print.queuesPerSession'; op = 'gt'; than = 10 }) }
            $c.checks[0].findings = @{ ok = 'in Ordnung'; check = '{print.queuesPerSession} Warteschlangen je Sitzung'; unknown = '{reason}' } })
        $v = @{ 'print.queueCount' = 50; 'sessions.list' = @(@{ Id = 2; State = 'Active'; User = 'a'; DisconnectTime = 0 }) }
        (Get-Check ($v + @{ 'print.citrixPrintService' = 'Running' }) @{} 'print.citrixQueues' $cat).grade | Should -Be 'check'
        $n = Get-Check ($v + @{ 'print.citrixPrintService' = 'Stopped' }) @{} 'print.citrixQueues' $cat
        $n.grade | Should -Be 'na'; $n.why | Should -Be 'Wert print.citrixMapping nicht in Gebrauch'
        (Get-Check ($v + @{ 'print.citrixPrintService' = (New-WorkerPerfHealthValue 'absent' 'notInstalled') }) @{} 'print.citrixQueues' $cat).grade | Should -Be 'na'
        (Get-Check ($v + @{ 'print.citrixPrintService' = (New-WorkerPerfHealthValue 'unreadable' 'rights') }) @{} 'print.citrixQueues' $cat).grade | Should -Be 'unknown'
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel ($v + @{ 'print.citrixPrintService' = 'Stopped' })) -Catalogue $cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        ($r.raw | Where-Object id -eq 'print.citrixMapping').stateText | Should -Be 'Text stateNotApplicable'; ($r.areas | Where-Object id -eq 'print').grade | Should -Be 'ok'
    }
    It 'sagt, ab wann die Protokolle reichen' {
        $cat = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { $c.copy.eventsReach = 'Die Protokolle reichen bis {from} zurück; letzter Start {boot}.' })
        $logs = @(@{ Log = 'Application'; Present = $true; Enabled = $true; Oldest = $ReadMs - 129600000 }, @{ Log = 'System'; Present = $true; Enabled = $true; Oldest = $ReadMs - 30 * 86400000 })
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel @{ 'events.logs' = $logs; 'operation.lastBoot' = $ReadMs - 2 * 86400000 }) -Catalogue $cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        $r.eventsReachText | Should -Be 'Die Protokolle reichen bis 13.01.2026 20:00 zurück; letzter Start 13.01.2026 08:00.'
        ($r.areas | Where-Object id -eq 'events').intro | Should -Be $r.eventsReachText; ($r.areas | Where-Object id -eq 'size').intro | Should -Be ''
        (Get-WorkerPerfHealthResult -Model (New-HealthModel) -Catalogue $cat -EventConfig $Cfg -Roles $Roles -Texts $Texts).eventsReachText | Should -Be 'Die Protokolle reichen bis – zurück; letzter Start –.'
    }
    It 'gibt jedem Bereich die Einstufung seiner auffaelligsten Pruefung und zaehlt die Bereiche' {
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel (Get-Vol 1.5) @{ PrintDrivers = $HpNone }) -Catalogue $Cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        @($r.areas.id) | Should -Be $WorkerPerfHealthAreas; @($r.areas.label)[0] | Should -Be 'Bereich size'
        ($r.areas | Where-Object id -eq 'operation').grade | Should -Be 'act'; ($r.areas | Where-Object id -eq 'print').grade | Should -Be 'check'
        ($r.areas | Where-Object id -eq 'operation').countsText | Should -Be '1 zum Handeln'; ($r.areas | Where-Object id -eq 'print').countsText | Should -Be '1 zum Prüfen'
        ($r.areas | Where-Object id -eq 'size').grade | Should -Be 'ok'; @(($r.areas | Where-Object id -eq 'size').checks).Count | Should -Be 0
        $r.summary.act | Should -Be 1; $r.summary.check | Should -Be 1; $r.summary.ok | Should -Be 9; $r.summary.text | Should -Be '1 Bereich zum Handeln, 1 zum Prüfen, 9 in Ordnung'
        $r.unknownCount | Should -Be 0; $r.state | Should -Be 'read'; $r.readAt | Should -Be $ReadMs; $r.offsetMin | Should -Be 60; $r.durationMs | Should -Be 10
        @($r.changed).Count | Should -Be 0; $r.catalogueVersion | Should -Be '2026-11-13'
        $c = ($r.areas | Where-Object id -eq 'print').checks[0]; $c.kind | Should -Be 'vendor'; $c.kindLabel | Should -Be 'Text kindVendor'; $c.source.url | Should -Be 'https://learn.microsoft.com/x'
        @($c.relates) | Should -Be @('print', 'pattern.printdriver'); $c.todo[0].where | Should -Be 'w'; ($r.areas | Where-Object id -eq 'print').notCovered | Should -Be 'Nicht abgedeckt in print'
        # was aus dem Katalog kommt, ist Woerterbuch oder Array, nie pscustomobject (der JSON-Schreiber des Berichts schriebe es als Text)
        foreach ($o in $c.source, $c.todo[0], $r.grades, $r.grades.act) { ($o -is [System.Collections.IDictionary]) | Should -BeTrue }
        $r.grades.act.word | Should -Be 'Handeln'; $r.grades.na.word | Should -Be 'Trifft nicht zu'; $r.environmentText | Should -Be 'Text environment'
    }
    It 'liefert ohne gelesenes Zustandsbild nur den Zustand' {   # Review Focus 2
        foreach ($s in 'notRecorded', 'skipped', 'unreadable') {
            $r = Get-WorkerPerfHealthResult -Model (New-HealthModel @{} @{ Health = $null; HealthState = $s }) -Catalogue $Cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
            $r.state | Should -Be $s; @($r.areas).Count | Should -Be 0; @($r.raw).Count | Should -Be 0; $r.Contains('summary') | Should -BeFalse
            $r.text | Should -Be @{ notRecorded = 'Text notRecorded'; skipped = ''; unreadable = 'Text unreadable' }[$s]
        }
        # das Lesen ist beim Start gescheitert: ebenfalls keine Datei, aber der Satz sagt es
        $failed = New-HealthModel @{} @{ Health = $null; HealthState = 'notRecorded'; SourceErrors = @((New-SourceError 'health')) }
        (Get-WorkerPerfHealthResult -Model $failed -Catalogue $Cat -EventConfig $Cfg -Roles $Roles -Texts $Texts).text | Should -Be 'Text notRecordedFailed'
    }
    It 'listet jeden Fakt als Rohwert und trennt freien Servertext' {
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel @{ 'size.memTotalMB' = 65536; 'operation.lastBoot' = $ReadMs - 2 * 86400000
            'maintenance.tasks' = @(@{ Path = '\Sim\Inventarlauf'; Enabled = $true; State = 'Ready'; NextRun = $ReadMs + 7200000; LastRun = 0; Triggers = 'daily'; RepeatMinutes = 0; Action = 'C:\Tools\inventar.exe' })
            'vda.controllers' = @(@{ Entry = 'ddc01.sim.local'; Kind = 'fqdn'; From = 'policy' }); 'security.defenderSharedSignatures' = '\\fs01\defender$' }) -Catalogue $Cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        $raw = { param($id) $r.raw | Where-Object id -eq $id }
        (& $raw 'size.memTotalMB').text | Should -Be '65536 MB'; (& $raw 'size.memTotalMB').label | Should -Be 'Wert size.memTotalMB'; (& $raw 'size.memTotalMB').area | Should -Be 'size'; (& $raw 'size.memTotalMB').derived | Should -BeFalse
        (& $raw 'operation.lastBoot').text | Should -Be '13.01.2026 08:00'; (& $raw 'operation.uptimeDays').text | Should -Be '2 Tage'; (& $raw 'operation.uptimeDays').derived | Should -BeTrue
        $t = (& $raw 'maintenance.tasks').items[0]; $t.free | Should -Be 'Path: \Sim\Inventarlauf; Action: C:\Tools\inventar.exe'
        $t.text | Should -Be 'Enabled: ja; State: Ready; NextRun: 15.01.2026 10:00; LastRun: –; Triggers: daily; RepeatMinutes: 0'
        (& $raw 'vda.controllers').items[0].text | Should -Be 'Entry: ddc01.sim.local; Kind: fqdn; From: policy'; (& $raw 'vda.controllers').items[0].free | Should -Be ''
        (& $raw 'security.defenderSharedSignatures').text | Should -Be '\\fs01\defender$'; (& $raw 'size.cpuLogical').state | Should -Be 'absent'; (& $raw 'size.cpuLogical').text | Should -Be ''
        (& $raw 'size.cpuLogical').stateText | Should -Be 'Text stateAbsent'; (& $raw 'size.memTotalMB').stateText | Should -Be 'Text stateRead'
        @($r.raw).Count | Should -Be 164
    }
}
```

Die Einheit von `operation.uptimeDays` in `$script:WorkerPerfHealthDerived` ist `Tage`.

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Health.Tests.ps1`
Expected: FAIL, `Get-WorkerPerfHealthResult` ist nicht definiert

- [ ] **Step 3: Regeln, Einstufung, Ergebnis je Bereich und Rohwerte mit den Signaturen der Interfaces umsetzen**

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Health.ps1 tests/Health.Tests.ps1
git commit -m "Grade the checks of the catalogue"
```

---

### Inhalt des Katalogs (gilt für die Tasks 14a, 14b und 14c)

Der Katalog entsteht in drei Tasks, jede mit eigenem Testlauf und eigenem Commit: 14a legt das Gerüst an und schreibt die Prüfungen der Bereiche `size` bis `profile` (31), 14b die der Bereiche `print` bis `maintenance` (33), 14c die des Bereichs `apps` (13), die Tabellen „Lesequellen" und „Nicht aufgenommen" und die Prüfung gegen die simulierte Stunde. Für alle drei gilt dieser Abschnitt.

**Recherchen** unter `.superpowers/sdd/zustandsbild-prep/`, je mit Dokumenten, Zitaten und dem Abschnitt „Source check": `research-base.md`, `research-citrix.md`, `research-security.md`, `research-net-print-events.md`, `research-vmware.md`, `research-wem.md`, `research-edge.md`, `research-office.md`, `research-teams.md`, `research-printmapping.md` (Hersteller) und `research-bisf.md`, `research-stalhood.md` (Praxis). Aus `research-printmapping.md` stützen `pt.client.installed` den Wert `print.mappingClientVersion` und `pt.rec.supported-version` die Prüfung `print.mappingClientSupported`; `pt.rec.same-release` und `pt.rec.no-ipp-on-terminalserver` stehen als Hinweise in deren Text, mit den Kürzungen ihrer Quellenprüfung. Die Recherchen der weiteren Praxisquellen (`research-px-<key>.md`; beim Schreiben dieses Plans liegen die zu GO-EUC, James Kindon und James Rankin vor) haben noch keinen Abschnitt „Source check" und werden nicht verwendet, bis sie ihn haben.

- **Bereiche:** `label` wie im Entwurf 3.2 („Größe und Reserve", „Betrieb", „Sitzungen", „Citrix VDA", „Profilverwaltung", „Drucken", „Sicherheitsprodukte", „Netz und Dateiserver", „Ereignisbild", „Wartung in der Arbeitszeit", „Anwendungen"); `notCovered` nennt je Bereich in einem Satz, was die erste Fassung nicht liest (Abschnitt „Nach dem ersten echten Lauf" und die Zeilen „Nicht gelesen" der Tabellen); beim Bereich `security` auch, dass ein Produkt der Rollenliste ohne Dienst und ohne Filtertreiber nicht erkannt wird (Entwurf 9); beim Bereich `print`, dass vom Zuordnungswerkzeug (PrinTaurus SmartSpread) nur die Version des Clients gelesen wird, nicht seine Regeln und nicht der Ablauf der Zuordnung bei der Anmeldung, und dass die Citrix-Druckrichtlinien nicht geprüft sind; beim Bereich `apps`, dass Einstellungen je Benutzer nicht gelesen werden.
- **Feste Texte von `copy`** (spätere Tests verlangen sie wörtlich): `title` „Zustand des Workers"; `notRecorded` „Zustandsbild nicht erfasst."; `notRecordedFailed` beginnt mit „Zustandsbild nicht erfasst" und sagt, dass das Lesen beim Start gescheitert ist; `unreadable` „Zustandsbild nicht lesbar."; `healthOnlyHead` „Zustandsbericht ohne Messung"; `summary` „{act} zum Handeln, {check} zum Prüfen, {ok} in Ordnung"; `areaOne` „1 Bereich"; `areaMany` „{n} Bereiche"; `countsAct` „{n} zum Handeln"; `countsCheck` „{n} zum Prüfen"; `countsUnknown` „{n} nicht prüfbar"; `reasonSkipped` „{category} nicht erfasst (-Skip)"; `incidentNote` sagt „können … beitragen", nie „Ursache"; `yes` „ja"; `no` „nein"; `noValue` „–"; `copyCheckTitle` „{area} – {title}: {grade}"; `copyAreaTitle` „{area}: {grade}"; `copyAreaItem` „- {title}: {grade}. {finding}"; `kindVendor` „Empfehlung des Herstellers"; `kindPractice` „Empfehlung aus der Praxis"; `kindRule` „Faustregel"; `notApplicable` „Trifft nicht zu: {reason}."; `reasonAppNotInstalled` „{app} ist nicht installiert"; `appNotInstalled` „{app}: nicht installiert"; `stateNotApplicable` beginnt mit „nicht zutreffend"; `environment` „Der Katalog geht von nicht persistenten, über Machine Creation Services bereitgestellten Multi-Session-Workern aus."; `eventsReach` nennt `{from}` und `{boot}` („Die gelesenen Ereignisprotokolle reichen bis {from} zurück; letzter Start des Workers: {boot}."). In `grades` hat `na` das Wort „Trifft nicht zu" und das Symbol „–". Die übrigen Texte von `copy` sind frei formuliert.
- **Je Prüfung:** Titel in Alltagssprache; Befundsätze mit den eingesetzten Zahlen; „Was bedeutet das?" in zwei bis drei Sätzen ohne Fachjargon: warum der Punkt für Geschwindigkeit oder Stabilität zählt; „Was tun?" als Prüfschritte und übliche Abhilfen mit „was, wo, woran erkennbar", als Vorschlag formuliert, ohne kopierbare Befehle; Quelle mit Hersteller oder Praxisquelle, Titel, Adresse und dem Datum, an dem sie für diese Task geöffnet wurde. Der Katalog nennt keine Systeme des Auftraggebers; das Zuordnungswerkzeug nennt er mit dem Produktnamen des Herstellers (R1).
- **Regeln und Art** genau nach den Tabellen. Eine Prüfung der Art `vendor` stützt ihren Satz auf die Aussage des genannten Dokuments, und zwar nur so weit, wie der Abschnitt „Source check" der Recherche sie stützt (was dort zu streichen ist, steht nicht im Text). Wo zwei Praxisquellen einander widersprechen, nennt `meaning` beide Sichten und ergreift keine Partei (S3).
- **Praxisquellen (Entwurf 4.3):** bei `kind` `practice` ist `source.vendor` der Name einer Praxisquelle aus der Tabelle „Praxisquellen" des Nachweises, deren Stand `recherchiert` ist (in der ersten Fassung „BIS-F" oder „Carl Stalhood"), `source.title` der Titel der Seite, `source.url` ihre Adresse. Kein Text einer solchen Prüfung nennt sie eine Empfehlung des Herstellers. Wo die Praxisquelle dem Hersteller widerspricht, gilt der Hersteller, und `meaning` nennt den Widerspruch: `network.rss` (BIS-F schaltet RSS beim Versiegeln global ab, so sein Code und seine Seite „System Optimizations"; seine Versionshinweise nennen das Gegenteil; VMware verlangt es eingeschaltet). Praxisquellen sind teils sichtbar älter als Windows Server 2022: `meaning` sagt das, wo die Quellenprüfung es vermerkt.
- **Ausnahme des Auftraggebers (Entwurf 4.3, Q1, Q2):** `precedence` enthält genau einen Eintrag: `check` `operation.powerPlan`, `winner` `practice`, `reason` mit der Begründung des Auftraggebers („Die Praxisquellen beziehen sich ausdrücklich auf Citrix-Terminalserver und Betriebserfahrung, die Herstellerdokumentation nicht."). Die Prüfung nennt als Quelle Carl Stalhood („Citrix Health Check"); ihr `meaning` nennt BIS-F als zweite Praxisquelle, die Vorgabe „Ausbalanciert" von Microsoft und dass VMware „Höchstleistung" nennt, solange Latenzprobleme untersucht werden. Kein Satz verspricht einen messbaren Gewinn.
- **Zielumgebung (Entwurf 4.4):** jeder Schritt, der eine Einstellung ändert, nennt in `where` das Master-Image oder die Richtlinie („bei nicht persistenten Workern im Master-Image", „in der Gruppenrichtlinie", „in der Citrix-Richtlinie", „in der WEM-Konfiguration"); kein Schritt schlägt eine Änderung am einzelnen Worker vor. Die sieben Prüfungen mit `operation.lastBoot` in `values` nennen in ihren Befundsätzen `{operation.lastBoot}` als Grenze („seit dem letzten Start am …"). `operation.updateAge` spricht vom Stand des Abbilds. `events.sinceBoot` sagt, dass Rückblick und Ereignisbild auf diesem Worker nur bis zum letzten Start reichen; es nennt, was BIS-F vorsieht, mit dessen Voraussetzung (die Ereignisprotokolle auf dem Cache-Datenträger, wenn für MCS ein MCSIO-Cache-Datenträger eingerichtet ist), kennzeichnet „überstehen so einen Neustart" als Folgerung des Katalogs und hat keine Regel `act`.
- **Lesequellen:** jedes Dokument der Spalte „Dokument" wird für die Tabelle „Lesequellen" des Nachweises geöffnet (Task 14c). Lässt sich eines nicht öffnen oder beschreibt es die Quelle nicht, steht die Zeile dort als „nicht dokumentiert", und der Wert bekäme in der Werteliste bzw. die Probe in `src/apps.json` das Merkmal „nicht dokumentiert"; eine Prüfung, die diesen Wert nennt, müsste in den Abschnitt „Nach dem ersten echten Lauf" wandern (D1; der Lader lehnte sie sonst ab). Das ist eine Änderung der festen Listen: es gilt der letzte Punkt.
- **Vorbehalte aus den Recherchen stehen im Text:** `security.citrixExclusions` (Citrix verlangt Abstimmung mit dem Sicherheitsteam), `security.networkProtection` (eine Schutzfunktion; die Entscheidung liegt beim Sicherheitsteam), `sessions.disconnectLimit` und `sessions.idleLimit` (ein Limit aus einer Citrix-Richtlinie sieht die erste Fassung nicht), `events.crashes` (zeigt Häufung, keine Ursache), `network.dnsPublic` (eine öffentliche Adresse kann gewollt sein), `vda.wemCache` (der Agent des WEM-Dienstes findet den beständigen Ort ab 2408.1.0.1 selbst), `size.storageController` (nur ein Hinweis für E/A-starke Last), `maintenance.updateServiceEnabled` (BIS-F nennt keinen Zweck; die Begründung ist die des Katalogs), `print.mappingClientSupported` (die Version des Clients ist die des Abbilds; als Hinweise des Herstellers, je mit ihrer Einschränkung: zum Update auf 6.4 sollen alle Komponenten dieselbe Release-Version tragen, und lokale IPP-Warteschlangen sind in Version 6.4 für Citrix- und Terminalserver-Umgebungen nicht unterstützt; beides ist auf dem Worker nicht lesbar), `apps.edgeUserDataDir` (nicht unterstützt ist nach Microsoft nur ein umgeleiteter Ordner, etwa auf einer Freigabe; die Prüfung lässt nachsehen, wohin der Pfad zeigt), `apps.edgeWebView2Update` (auf nicht persistenten Workern muss dann das Abbild die aktuelle Runtime tragen), `apps.teamsFallback` (eine Entscheidung des Betreibers), `apps.officeUpdateUi` (übertragen von Microsofts Vorgabe für Microsoft 365 Apps).
- **Nachweis** in `docs/guidance/quellen.md`, Abschnitt `## Zustandsbild` am Ende der Datei (Unterabschnitte mit `###`; die Tests lesen nur diesen Abschnitt, damit sie nicht an Abschnitten des geführten Berichts bestehen):
  - eine Tabelle „Praxisquellen" mit den dreizehn Praxisquellen des Entwurfs 4.3 und dem Stand ihrer Recherche für das Zustandsbild, je Quelle eine Zeile genau in der Form `| <Name> | <Adresse> | <Stand> |` (eine Adresse je Zeile, mit `https://`, ohne Leerzeichen) mit dem Stand `recherchiert` oder `offen`. Namen: BIS-F, Carl Stalhood, GO-EUC, James Kindon, James Rankin, Thomas Kötzing, Manuel Winkel, Kasper Johansen, Aaron Parker, Trentent Tye, John Billekens, Guy Leech, Benny Tritsch; Adressen wie im Entwurf 4.3 und in `source-candidates.md` der Vorarbeit. `recherchiert` sind in der ersten Fassung BIS-F und Carl Stalhood;
  - je recherchierter Praxisquelle ein eigener Unterabschnitt („Quellen aus der Praxis: BIS-F", „Quellen aus der Praxis: carlstalhood.com") mit Titel, Adresse, Abrufdatum, Stand der Seite und den Prüfungen, die sich darauf stützen;
  - ein Unterabschnitt „Ausnahmen: Praxisquelle vor Hersteller" mit dem Energiesparplan, der Begründung des Auftraggebers und dem, was Microsoft und VMware sagen;
  - eine Tabelle der Herstellerquellen (Microsoft, Citrix, VMware, AKI) mit Hersteller, Titel, Adresse, Abrufdatum und den Prüfungen, die sich darauf stützen;
  - in Task 14c: eine Tabelle „Lesequellen" mit dem Dokument je Wert der Wertetabellen und je Probe der Anwendungsliste (Titel, Adresse, Abrufdatum; „nicht dokumentiert", wo die Tabelle es sagt) und eine Tabelle „Nicht aufgenommen" mit den Kandidaten der Recherchen, die keine Prüfung wurden, und dem Grund (die Zeilen „Nicht aufgenommen" der Tabellen oben, dazu alles, was nur für Provisioning Services, persistente Maschinen oder Single-Session-Desktops gilt).
  Die Datei enthält keine Daten des Auftraggebers.
- **Feste Listen:** die Kennungen, Arten und Zahlen der Prüfungen sind in diesem Plan festgelegt, und spätere Tasks stützen sich darauf: die Listen und Zählungen der Tests in 14a bis 14c (31, 64, 77; 33, 12 und 32), das Drehbuch der simulierten Stunde (2 Bereiche zum Handeln, 4 zum Prüfen, 5 in Ordnung; Schnelllauf 1, 5, 5), in Task 16 die Zahl 105 der Kopierfelder und die Verweise `incidents[].health`, die Einstufungen in den Tasks 17 bis 19. Ergibt das Nachschlagen, dass eine Prüfung eine andere Art braucht, entfällt oder dazukommt (ein Dokument lässt sich nicht öffnen oder trägt die Aussage nicht; eine Lesequelle ist nicht dokumentiert; eine Recherche einer weiteren Praxisquelle stützt eine neue Prüfung), ändert der Implementierer keine dieser Listen selbst: er hält vor dem Commit an und meldet den Befund dem Controller. Die betroffenen Erwartungen werden dann in einer Änderung dieses Plans gemeinsam nachgezogen.

---

### Task 14a: Katalog – Gerüst und die Prüfungen der Bereiche Größe bis Profilverwaltung

**Files:**
- Create: `src/health.de.json`
- Modify: `docs/guidance/quellen.md` (neuer Abschnitt `## Zustandsbild` am Ende der bestehenden Datei)
- Test: `tests/Health.Tests.ps1`
- Mit dem geführten Bericht geteilt: `docs/guidance/quellen.md` (sie stammt aus Task 6 des geführten Berichts und wird dort noch überarbeitet; der Abschnitt „Zustandsbild" kommt als eigener Block ans Ende, beim Zusammenführen bleiben beide Teile stehen). Nicht anfassen: `src/guidance.de.json`, `src/apps.json` (eine Probe, die sich beim Nachschlagen als falsch erweist, wird in einem eigenen Commit zu Task 2 berichtigt).

**Interfaces:**
- Consumes: Tasks 2 und 9–13 (darunter `Get-Check`, `New-HealthModel` aus den Tests der Tasks 12 und 13); der Abschnitt „Inhalt des Katalogs"; die Tabellen des Abschnitts „Werte, Fakten und Prüfungen je Bereich".
- Produces: `src/health.de.json` mit den elf Bereichen (`label`, `notCovered`), den vier Einstufungen und dem Ergebnis `na`, den 21 Schwellen, den Bezeichnungen der 164 festen Fakten, allen Texten aus `$script:WorkerPerfHealthCopyKeys`, dem Teil `precedence` mit dem einen Eintrag und den 31 Prüfungen der Bereiche `size`, `operation`, `sessions`, `vda`, `profile` in der Reihenfolge der Tabellen; im Nachweis die Tabelle „Praxisquellen", die Unterabschnitte der zwei recherchierten Praxisquellen, der Unterabschnitt „Ausnahmen: Praxisquelle vor Hersteller" und die Tabelle der Herstellerquellen, je mit den Zeilen dieser 31 Prüfungen. Ab hier ist die Datei der Standard für `-HealthFile`.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/Health.Tests.ps1`)

```powershell
Describe 'Katalog in src' {
    BeforeAll {
        $script:CatFile = Join-Path $PSScriptRoot '../src/health.de.json'; $script:Apps = @(Read-WorkerPerfHealthApps (Join-Path $PSScriptRoot '../src/apps.json'))
        $script:Real = Read-WorkerPerfHealthCatalogue $CatFile $Apps
        # nur der Abschnitt des Zustandsbilds im Nachweis: bis zur naechsten Ueberschrift derselben Ebene
        $script:Proof = [regex]::Match((Get-Content (Join-Path $PSScriptRoot '../docs/guidance/quellen.md') -Raw), '(?ms)^## Zustandsbild\s*$(.*?)(?=^## |\z)').Groups[1].Value
        # die Pruefungen des Plans je Bereich; Task 14b ergaenzt print bis maintenance, Task 14c apps
        $script:PlanChecks = [ordered]@{
            size = @('size.commitHeadroom', 'size.pagefilePresent', 'size.memoryPerSession', 'size.cpuPerSession', 'size.commitAboveRam', 'size.workerCpu', 'size.workerMemory',
                'size.vmTools', 'size.balloonDriver', 'size.netAdapterType', 'size.storageController')
            operation = @('operation.pendingRestart', 'operation.uptime', 'operation.updateAge', 'operation.powerPlan', 'operation.diskFree')
            sessions = @('sessions.disconnectLimit', 'sessions.idleLimit', 'sessions.disconnectedOld', 'sessions.unloadedProfiles', 'sessions.tempProfiles')
            vda = @('vda.services', 'vda.controllerCount', 'vda.controllerNotFqdn', 'vda.listOfSids', 'vda.wemServices', 'vda.wemCache', 'vda.wemGpTimeout')
            profile = @('profile.containerFull', 'profile.containersPerUser', 'profile.serviceStopped') }
        # die Art jeder Pruefung des ganzen Plans; was in keiner der zwei Listen steht, ist eine Faustregel
        $script:Vendor = @('size.pagefilePresent', 'size.vmTools', 'size.balloonDriver', 'size.netAdapterType', 'size.storageController',
            'vda.controllerCount', 'vda.controllerNotFqdn', 'vda.listOfSids', 'vda.wemServices', 'vda.wemCache', 'vda.wemGpTimeout',
            'print.driversInSpooler', 'print.kernelModeV2', 'print.mappingClientSupported',
            'security.twoScanners', 'security.passiveWithoutMde', 'security.citrixExclusions', 'network.smb1', 'network.dnsCount', 'network.rss',
            'maintenance.sessionTriggerTasks', 'maintenance.defenderFullScan', 'maintenance.defenderRandomize',
            'apps.edgeAutoUpdate', 'apps.edgeUpdateCheckOff', 'apps.edgeWebView2Update', 'apps.edgeBackgroundMode', 'apps.edgeSleepingTabs', 'apps.edgeAutoDiscard', 'apps.edgeRoamingProfile',
            'apps.teamsAutoUpdate', 'apps.teamsFallback', 'apps.teamsWebView2')
        $script:Practice = @('size.commitAboveRam', 'size.workerCpu', 'size.workerMemory', 'operation.uptime', 'operation.updateAge', 'operation.powerPlan', 'sessions.disconnectLimit', 'sessions.idleLimit',
            'security.wemExclusions', 'security.networkProtection', 'events.sinceBoot', 'maintenance.updateServiceEnabled')
        $script:K3 = @('events.crashes', 'events.storage', 'events.fileserver', 'events.coverage', 'events.sinceBoot', 'sessions.unloadedProfiles', 'sessions.tempProfiles')
        $script:PracticeSources = @('BIS-F', 'Carl Stalhood', 'GO-EUC', 'James Kindon', 'James Rankin', 'Thomas Kötzing', 'Manuel Winkel', 'Kasper Johansen', 'Aaron Parker', 'Trentent Tye',
            'John Billekens', 'Guy Leech', 'Benny Tritsch')
    }
    It 'enthaelt genau die Pruefungen des Plans mit Bereich, Art und Schwellen' {
        @($Real.checks.id) | Should -Be @($PlanChecks.Values | ForEach-Object { $_ })
        @($Real.checks).Count | Should -Be 31; $Vendor.Count | Should -Be 33; $Practice.Count | Should -Be 12       # Task 14b: 64 Pruefungen, Task 14c: 77
        foreach ($c in $Real.checks) {
            $c.id | Should -BeLike ($c.area + '.*')
            $c.kind | Should -Be $(if ($Vendor -contains $c.id) { 'vendor' } elseif ($Practice -contains $c.id) { 'practice' } else { 'rule' }) -Because $c.id
        }
        $want = [ordered]@{ commitPeakPct = 90; commitNowPct = 98; memPerSessionMB = 1024; sessionsPerCpu = 8; workerCpuMin = 8; workerMemMinMB = 24576; uptimeDays = 30; updateAgeDays = 60; diskFreeGB = 10; diskFreeHardGB = 2
            disconnectedHours = 24; unloadedProfiles = 20; containerUsedPct = 90; containerUsedHardPct = 95; containersPerUser = 3; printDrivers = 20; queuesPerSession = 10; signatureAgeDays = 2; eventDays = 3; workStartHour = 7; workEndHour = 18 }
        @($Real.thresholds.PSObject.Properties.Name) | Should -Be @($want.Keys)
        foreach ($k in $want.Keys) { $Real.thresholds.$k.value | Should -Be $want[$k] -Because $k; $Real.thresholds.$k.default | Should -Be $want[$k] -Because $k }
        @(Get-WorkerPerfHealthChangedThresholds $Real).Count | Should -Be 0
    }
    It 'fuehrt die Ausnahme des Auftraggebers: beim Energiesparplan gilt die Praxisquelle vor dem Hersteller' {
        @($Real.precedence).Count | Should -Be 1; $Real.precedence[0].check | Should -Be 'operation.powerPlan'; $Real.precedence[0].winner | Should -Be 'practice'
        $Real.precedence[0].reason | Should -Match 'Terminalserver'
        $c = $Real.checks | Where-Object id -eq 'operation.powerPlan'; $c.kind | Should -Be 'practice'; $c.source.vendor | Should -Be 'Carl Stalhood'
        foreach ($w in 'Microsoft', 'Ausbalanciert', 'VMware', 'BIS-F') { $c.meaning | Should -Match $w -Because $w }      # der Widerspruch bleibt genannt
        (Get-Check @{ 'operation.powerPlan' = 'balanced' } @{} 'operation.powerPlan' $Real).grade | Should -Be 'check'
        (Get-Check @{ 'operation.powerPlan' = 'powerSaver' } @{} 'operation.powerPlan' $Real).grade | Should -Be 'check'
        (Get-Check @{ 'operation.powerPlan' = 'highPerformance' } @{} 'operation.powerPlan' $Real).grade | Should -Be 'ok'
        $Proof | Should -Match 'Ausnahmen: Praxisquelle vor Hersteller'
    }
    It 'traegt die Texte, auf die sich Bericht und Seite stuetzen, und zu jeder Pruefung einen Vorschlag' {
        $want = [ordered]@{ title = 'Zustand des Workers'; notRecorded = 'Zustandsbild nicht erfasst.'; unreadable = 'Zustandsbild nicht lesbar.'; healthOnlyHead = 'Zustandsbericht ohne Messung'
            summary = '{act} zum Handeln, {check} zum Prüfen, {ok} in Ordnung'; areaOne = '1 Bereich'; areaMany = '{n} Bereiche'
            countsAct = '{n} zum Handeln'; countsCheck = '{n} zum Prüfen'; countsUnknown = '{n} nicht prüfbar'; reasonSkipped = '{category} nicht erfasst (-Skip)'
            yes = 'ja'; no = 'nein'; noValue = '–'; copyCheckTitle = '{area} – {title}: {grade}'; copyAreaTitle = '{area}: {grade}'; copyAreaItem = '- {title}: {grade}. {finding}'
            kindVendor = 'Empfehlung des Herstellers'; kindPractice = 'Empfehlung aus der Praxis'; kindRule = 'Faustregel'; notApplicable = 'Trifft nicht zu: {reason}.'
            reasonAppNotInstalled = '{app} ist nicht installiert'; appNotInstalled = '{app}: nicht installiert'
            environment = 'Der Katalog geht von nicht persistenten, über Machine Creation Services bereitgestellten Multi-Session-Workern aus.' }
        foreach ($k in $want.Keys) { $Real.copy.$k | Should -Be $want[$k] -Because $k }
        $Real.copy.notRecordedFailed | Should -BeLike 'Zustandsbild nicht erfasst*'; $Real.copy.stateNotApplicable | Should -BeLike 'nicht zutreffend*'
        $Real.copy.eventsReach | Should -Match '\{from\}'; $Real.copy.eventsReach | Should -Match '\{boot\}'; $Real.grades.na.word | Should -Be 'Trifft nicht zu'
        @($Real.areas.label) | Should -Be @('Größe und Reserve', 'Betrieb', 'Sitzungen', 'Citrix VDA', 'Profilverwaltung', 'Drucken', 'Sicherheitsprodukte', 'Netz und Dateiserver', 'Ereignisbild', 'Wartung in der Arbeitszeit', 'Anwendungen')
        foreach ($a in $Real.areas) { [string]$a.notCovered | Should -Not -BeNullOrEmpty -Because $a.id }
        foreach ($c in $Real.checks) { @($c.todo).Count | Should -BeGreaterThan 0 -Because $c.id }
    }
    It 'nennt keine kopierbaren Befehle und keine Ursachen' {
        foreach ($c in $Real.checks) {
            foreach ($t in $c.todo) { "$($t.text) $($t.where) $($t.sign)" | Should -Not -Match '(?i)(\b(Set|New|Remove|Stop|Restart|Disable|Enable)-[A-Z]\w+|reg(\.exe)? add|powercfg|wevtutil|sc(\.exe)? (stop|config)|net stop)' -Because $c.id }
            foreach ($f in $c.findings.PSObject.Properties) { $f.Value | Should -Not -Match 'ist die Ursache|verursacht den' -Because $c.id }
        }
        $Real.copy.incidentNote | Should -Match 'beitragen'
    }
    It 'nennt Praxisquellen als Praxisquellen, aus der Liste des Nachweises' {
        # die Tabelle "Praxisquellen" des Nachweises: | Name | Adresse | recherchiert oder offen |
        $px = @{}; foreach ($m in [regex]::Matches($Proof, '(?m)^\| (?<n>[^|]+?) \| (?<u>https?://\S+) \| (?<s>recherchiert|offen) \|\s*$')) { $px[$m.Groups['n'].Value] = $m.Groups['s'].Value }
        $px.Count | Should -Be 13; foreach ($n in $PracticeSources) { $px.ContainsKey($n) | Should -BeTrue -Because $n }
        @($px.Keys | Where-Object { $px[$_] -eq 'recherchiert' } | Sort-Object) | Should -Be @('BIS-F', 'Carl Stalhood')
        foreach ($c in @($Real.checks | Where-Object kind -eq 'practice')) {
            $px[[string]$c.source.vendor] | Should -Be 'recherchiert' -Because $c.id; $c.source.url | Should -Match '^https://' -Because $c.id
            "$($c.title) $($c.meaning) $(@($c.findings.PSObject.Properties.Value) -join ' ')" | Should -Not -Match 'Empfehlung des Herstellers|Hersteller empfiehlt' -Because $c.id
        }
        foreach ($c in @($Real.checks | Where-Object kind -eq 'vendor')) { $px.ContainsKey([string]$c.source.vendor) | Should -BeFalse -Because $c.id; $c.source.url | Should -Match '^https://' -Because $c.id }
        $Proof | Should -Match 'Quellen aus der Praxis: BIS-F'; $Proof | Should -Match 'Quellen aus der Praxis: carlstalhood\.com'
    }
    It 'nennt das Master-Image oder die Richtlinie als Ort der Aenderung und den letzten Start als Grenze' {
        # Pruefungen ohne Einstellung im Master-Image oder in einer Richtlinie: ihre Schritte lassen nachsehen oder aufraeumen, oder die Abhilfe liegt im Neustartplan der Bereitstellungsgruppe
        $look = @('size.commitHeadroom', 'size.commitAboveRam', 'operation.pendingRestart', 'operation.uptime', 'operation.diskFree', 'sessions.disconnectedOld', 'sessions.unloadedProfiles', 'sessions.tempProfiles',
            'profile.containerFull', 'profile.containersPerUser', 'events.crashes', 'events.storage', 'events.fileserver', 'events.coverage', 'network.smbOldDialect')
        foreach ($c in $Real.checks) {
            foreach ($t in $c.todo) { "$($t.text) $($t.where)" | Should -Not -Match '(?i)auf diesem Worker (ändern|einstellen|setzen)|am einzelnen Worker (ändern|einstellen|setzen)' -Because $c.id }
            if ($look -notcontains $c.id) { @($c.todo | Where-Object { $_.where -match 'Master-Image|Richtlinie|WEM-Konfiguration' }).Count | Should -BeGreaterThan 0 -Because $c.id }
        }
        foreach ($id in @($K3 | Where-Object { @($Real.checks.id) -contains $_ })) {      # in Task 14a die zwei der Sitzungen, ab Task 14b alle sieben
            $c = $Real.checks | Where-Object id -eq $id; @($c.values) | Should -Contain 'operation.lastBoot' -Because $id
            $c.findings.check | Should -Match '\{operation\.lastBoot\}' -Because $id
        }
        ($Real.checks | Where-Object id -eq 'operation.updateAge').findings.check | Should -Match 'Abbild'
        (Get-Content $CatFile -Raw) | Should -Not -Match 'Provisioning Services|\bPVS\b'                              # nichts, was nur fuer Provisioning Services gilt
    }
    It 'stuetzt keine Pruefung auf einen Wert ohne dokumentierte Lesequelle' {
        $t = Get-WorkerPerfHealthFactTable $Apps; @($t.Keys).Count | Should -Be 202
        foreach ($c in $Real.checks) { foreach ($v in $c.values) { $t[$v].Documented | Should -BeTrue -Because "$($c.id): $v" } }
        @($Real.values.PSObject.Properties.Name).Count | Should -Be 164
    }
    It 'fuehrt die Quelle jeder Pruefung im Nachweis' {
        foreach ($c in $Real.checks) {
            $Proof | Should -Match ([regex]::Escape($c.source.title)) -Because $c.id; $c.source.date | Should -Match '^\d{4}-\d\d-\d\d$' -Because $c.id
            if ($c.source.url) { $Proof | Should -Match ([regex]::Escape($c.source.url)) -Because $c.id }
        }
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Health.Tests.ps1`
Expected: FAIL, `src/health.de.json` fehlt

- [ ] **Step 3: Quellen öffnen, Gerüst, die 31 Prüfungen und ihren Teil des Nachweises schreiben** (jede Quelle zuerst öffnen und mit Datum eintragen, dann die Texte der Prüfungen, die sich darauf stützen; für jede Prüfung den Abschnitt „Source check" ihrer Recherche lesen und nur schreiben, was er stützt; bei einer Abweichung von den festen Listen anhalten und melden)

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/health.de.json docs/guidance/quellen.md tests/Health.Tests.ps1
git commit -m "Add the health catalogue with the checks on size, operation, sessions, VDA and profiles"
```

---

### Task 14b: Katalog – die Prüfungen der Bereiche Drucken bis Wartung

**Files:**
- Modify: `src/health.de.json`, `docs/guidance/quellen.md` (Abschnitt `## Zustandsbild`)
- Test: `tests/Health.Tests.ps1`
- Mit dem geführten Bericht geteilt: `docs/guidance/quellen.md` (nur der eigene Abschnitt). Nicht anfassen: `src/guidance.de.json`, `src/apps.json`, `src/roles.json`; die 31 Prüfungen aus Task 14a.

**Interfaces:**
- Consumes: Task 14a (`$PlanChecks`, `$Vendor`, `$Practice`, `$K3`, `$Proof` im `BeforeAll` von `'Katalog in src'`); der Abschnitt „Inhalt des Katalogs"; die Tabellen der Bereiche `print`, `security`, `network`, `events`, `maintenance`.
- Produces: in `src/health.de.json` die 33 Prüfungen dieser fünf Bereiche hinter denen aus Task 14a, in der Reihenfolge der Tabellen (zusammen 64); im Nachweis ihre Zeilen, darunter die Quelle des Herstellers AKI.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/Health.Tests.ps1`: im `BeforeAll` von `'Katalog in src'` erhält `$PlanChecks` die fünf Einträge unten hinter `profile`; im Test `'enthaelt genau die Pruefungen des Plans …'` wird aus `Should -Be 31` `Should -Be 64`; dazu der neue Test)

```powershell
            # in BeforeAll, hinter dem Eintrag profile von $PlanChecks:
            print = @('print.driversInSpooler', 'print.isolationOff', 'print.driverCount', 'print.kernelModeV2', 'print.spoolerStopped', 'print.queueCount', 'print.mappingClientSupported')
            security = @('security.twoScanners', 'security.passiveWithoutMde', 'security.signatureAge', 'security.citrixExclusions', 'security.wemExclusions', 'security.networkProtection')
            network = @('network.smb1', 'network.smbOldDialect', 'network.dnsCount', 'network.dnsPublic', 'network.timeSource', 'network.rss')
            events = @('events.crashes', 'events.storage', 'events.fileserver', 'events.sinceBoot', 'events.coverage', 'events.retainFull', 'events.logDisabled')
            maintenance = @('maintenance.tasksInWorkHours', 'maintenance.sessionTriggerTasks', 'maintenance.defenderScanInWorkHours', 'maintenance.defenderFullScan', 'maintenance.defenderRandomize',
                'maintenance.updateInstallInWorkHours', 'maintenance.updateServiceEnabled')

    It 'nennt bei RSS und beim Ereignisbild, was die Praxisquelle sagt, und beim Zuordnungswerkzeug dessen Hersteller' {
        $rss = $Real.checks | Where-Object id -eq 'network.rss'; $rss.kind | Should -Be 'vendor'; $rss.meaning | Should -Match 'BIS-F'      # der Hersteller gilt, der Widerspruch ist genannt
        @($Real.precedence.check) | Should -Not -Contain 'network.rss'
        $e = $Real.checks | Where-Object id -eq 'events.sinceBoot'; @($e.rules.PSObject.Properties.Name) | Should -Be @('check')              # nie handeln
        $e.source.vendor | Should -Be 'BIS-F'; $e.source.url | Should -Match 'BISF\.psm1'; $e.meaning | Should -Match 'MCSIO'                  # die Voraussetzung der Quelle steht dabei
        foreach ($id in $K3) { @($Real.checks.id) | Should -Contain $id }
        $m = $Real.checks | Where-Object id -eq 'print.mappingClientSupported'; $m.kind | Should -Be 'vendor'; $m.source.vendor | Should -Be 'AKI'; $m.source.url | Should -Match '^https://www\.aki-gmbh\.com/'
        (Get-Check @{ 'print.mappingClientVersion' = '6.1.4' } @{} 'print.mappingClientSupported' $Real).grade | Should -Be 'check'
        (Get-Check @{ 'print.mappingClientVersion' = '6.4.1' } @{} 'print.mappingClientSupported' $Real).grade | Should -Be 'ok'
        (Get-Check @{ 'print.mappingClientVersion' = (New-WorkerPerfHealthValue 'absent' 'notInstalled') } @{} 'print.mappingClientSupported' $Real).grade | Should -Be 'na'      # Review Focus 3
        ($Real.areas | Where-Object id -eq 'print').notCovered | Should -Match 'PrinTaurus'
        ($Real.checks | Where-Object id -eq 'maintenance.updateServiceEnabled').source.vendor | Should -Be 'BIS-F'
    }
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Health.Tests.ps1`
Expected: FAIL, der Katalog hat 31 statt 64 Prüfungen

- [ ] **Step 3: Quellen öffnen, die 33 Prüfungen und ihren Teil des Nachweises schreiben** (wie Task 14a, Step 3)

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/health.de.json docs/guidance/quellen.md tests/Health.Tests.ps1
git commit -m "Add the health checks on printing, security products, network, events and maintenance"
```

---

### Task 14c: Katalog – die Prüfungen der Anwendungen, Lesequellen, Durchsicht

**Files:**
- Modify: `src/health.de.json`, `docs/guidance/quellen.md` (Abschnitt `## Zustandsbild`)
- Test: `tests/Health.Tests.ps1`
- Mit dem geführten Bericht geteilt: `docs/guidance/quellen.md` (nur der eigene Abschnitt). Nicht anfassen: `src/guidance.de.json`, `src/apps.json`; die 64 Prüfungen aus den Tasks 14a und 14b.

**Interfaces:**
- Consumes: Tasks 14a und 14b; Task 2 (`New-TestAppFile`), Task 9 (`Invoke-SimHealthOnly`), `Invoke-SimCapture`, `New-PatchedSource` (`tests/TestHelpers.ps1`); der Abschnitt „Inhalt des Katalogs"; die Tabellen des Bereichs `apps` und das Drehbuch aus Task 3.
- Produces: in `src/health.de.json` die 13 Prüfungen des Bereichs `apps` am Ende (zusammen 77); im Nachweis ihre Zeilen, die Tabelle „Lesequellen" und die Tabelle „Nicht aufgenommen".

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/Health.Tests.ps1`: im `BeforeAll` von `'Katalog in src'` erhält `$PlanChecks` den Eintrag unten hinter `maintenance`; aus `Should -Be 64` wird `Should -Be 77`; dazu der neue Block)

```powershell
            # in BeforeAll von 'Katalog in src', hinter dem Eintrag maintenance von $PlanChecks:
            apps = @('apps.edgeAutoUpdate', 'apps.edgeUpdateCheckOff', 'apps.edgeWebView2Update', 'apps.edgeStartupBoost', 'apps.edgeBackgroundMode', 'apps.edgeSleepingTabs', 'apps.edgeAutoDiscard',
                'apps.edgeRoamingProfile', 'apps.edgeUserDataDir', 'apps.officeUpdateUi', 'apps.teamsAutoUpdate', 'apps.teamsFallback', 'apps.teamsWebView2')

Describe 'Katalog in src: simulierte Stunde, Schnelllauf, weitere Anwendung, Nachweis' {
    BeforeAll {
        $script:CatFile = Join-Path $PSScriptRoot '../src/health.de.json'; $script:Apps = @(Read-WorkerPerfHealthApps (Join-Path $PSScriptRoot '../src/apps.json'))
        $script:Real = Read-WorkerPerfHealthCatalogue $CatFile $Apps; $script:Th = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json')
        $script:Proof = [regex]::Match((Get-Content (Join-Path $PSScriptRoot '../docs/guidance/quellen.md') -Raw), '(?ms)^## Zustandsbild\s*$(.*?)(?=^## |\z)').Groups[1].Value
        $script:SimRun = Invoke-SimCapture (Join-Path $TestDrive 'sim'); $script:SimHo = Invoke-SimHealthOnly (Join-Path $TestDrive 'ho')
        function Get-SimResult([string]$Run, $Catalogue = $script:Real) { Get-WorkerPerfHealthResult -Model (Import-WorkerPerfRun -Path $Run -Thresholds $Th -Roles $Roles) -Catalogue $Catalogue -EventConfig $Cfg -Roles $Roles -Texts $Texts }
        function Get-Grades($Result) { $g = @{}; foreach ($a in $Result.areas) { foreach ($c in $a.checks) { $g[$c.id] = $c.grade } }; $g }
    }
    It 'bewertet die simulierte Stunde wie im Drehbuch' {
        $r = Get-SimResult $SimRun; $g = Get-Grades $r; $g.Count | Should -Be 77
        @($g.Keys | Where-Object { $g[$_] -eq 'act' } | Sort-Object) | Should -Be @('print.driversInSpooler', 'profile.containerFull')
        @($g.Keys | Where-Object { $g[$_] -eq 'check' } | Sort-Object) | Should -Be @('apps.edgeBackgroundMode', 'apps.teamsAutoUpdate', 'events.crashes', 'maintenance.tasksInWorkHours', 'operation.pendingRestart')
        @($g.Keys | Where-Object { $g[$_] -eq 'unknown' } | Sort-Object) | Should -Be @('security.citrixExclusions', 'security.wemExclusions')
        @($g.Keys | Where-Object { $g[$_] -eq 'na' }).Count | Should -Be 0
        $g['operation.powerPlan'] | Should -Be 'ok'; $g['print.mappingClientSupported'] | Should -Be 'ok'       # Hoechstleistung; Client 6.4.1
        @($r.areas.grade) | Should -Be @('ok', 'check', 'ok', 'ok', 'act', 'act', 'ok', 'ok', 'check', 'check', 'check')
        $r.summary.text | Should -Be '2 Bereiche zum Handeln, 4 zum Prüfen, 5 in Ordnung'; $r.unknownCount | Should -Be 2
        ($r.areas | Where-Object id -eq 'profile').checks[0].finding | Should -Match '96'
        $apps = $r.areas | Where-Object id -eq 'apps'; @($apps.apps.state | Select-Object -Unique) | Should -Be @('installed'); @($apps.apps.key | Sort-Object) | Should -Be @('edge', 'office', 'teams')
        @($apps.checks | Where-Object { $_.app -eq 'office' }).grade | Should -Be @('ok')                              # Office: installiert und in Ordnung
        @($r.areas | ForEach-Object { $_.checks } | Where-Object { -not $_.finding }).Count | Should -Be 0
        $r.environmentText | Should -Match 'nicht persistent'; ($r.areas | Where-Object id -eq 'events').intro | Should -Match '\d\d\.\d\d\.\d{4}'
    }
    It 'bewertet den simulierten Schnelllauf ohne die Ereignisse der Messung' {
        $r = Get-SimResult $SimHo; $g = Get-Grades $r
        $g['print.driversInSpooler'] | Should -Be 'check'; $g['profile.containerFull'] | Should -Be 'act'; $r.summary.text | Should -Be '1 Bereich zum Handeln, 5 zum Prüfen, 5 in Ordnung'
    }
    It 'bewertet eine vierte Anwendung, die nur in Testdateien beschrieben ist, ohne Aenderung am Code' {   # Review Focus 3; Entwurf 3.2a
        $appFile = New-TestAppFile $TestDrive; $j = Get-Content $CatFile -Raw | ConvertFrom-Json
        $j.checks += [pscustomobject]@{ id = 'apps.simCache'; area = 'apps'; title = 'Cache der Sim-Fachanwendung'; values = @('apps.simapp.cacheMode')
            rules = @{ check = @(@{ value = 'apps.simapp.cacheMode'; op = 'ne'; than = 2 }) }
            findings = @{ ok = 'Cache-Betriebsart in Ordnung.'; check = 'Cache-Betriebsart {apps.simapp.cacheMode}.'; unknown = 'Nicht prüfbar: {reason}.' }; meaning = 'Erfundene Prüfung.'
            todo = @(@{ text = 'Betriebsart prüfen'; where = 'im Master-Image'; sign = 'Wert 2' }); source = @{ vendor = 'Test'; title = 'Test'; url = ''; date = '2026-11-13' }; kind = 'rule'; relates = @('disk') }
        $catFile = Join-Path $TestDrive 'health.test.json'; [IO.File]::WriteAllText($catFile, ($j | ConvertTo-Json -Depth 12))
        $cat = Read-WorkerPerfHealthCatalogue $catFile @(Read-WorkerPerfHealthApps $appFile)
        { Read-WorkerPerfHealthCatalogue $catFile $Apps } | Should -Throw "*Pruefung 'apps.simCache'*Anwendung 'simapp' steht nicht in der Anwendungsliste*"
        # auf dem simulierten Worker ist sie nicht installiert: trifft nicht zu, zaehlt nicht
        $r = Get-SimResult (Invoke-SimHealthOnly (Join-Path $TestDrive 'ho-app') @{ AppsFile = $appFile }) $cat; $a = $r.areas | Where-Object id -eq 'apps'
        $a.checks[-1].id | Should -Be 'apps.simCache'; $a.checks[-1].grade | Should -Be 'na'; $a.checks[-1].why | Should -Be 'Sim-Fachanwendung ist nicht installiert'
        ($a.apps | Where-Object key -eq 'simapp').text | Should -Be 'Sim-Fachanwendung: nicht installiert'; $a.countsText | Should -Be '2 zum Prüfen'; $r.summary.text | Should -Be '1 Bereich zum Handeln, 5 zum Prüfen, 5 in Ordnung'
        # derselbe Worker mit der Anwendung: nur sein Stand aendert sich, kein Code des Bausteins
        $patch = "`$script:SimHealthInner = `${function:Get-WorkerPerfHealth}`nfunction Get-WorkerPerfHealth {`n" +
            "    `$script:WorkerPerfSimAppState.Files['C:\Program Files\SimApp\simapp.exe'] = '4.2.0'; `$script:WorkerPerfSimAppState.Values['HKLM\SOFTWARE\SimApp|CacheMode'] = 1`n    & `$script:SimHealthInner }"
        $run = (& (New-PatchedSource (Join-Path $TestDrive 'srcapp') $patch) -Simulate -HealthOnly -AppsFile $appFile -OutputPath (Join-Path $TestDrive 'ho-app2') 6>$null 3>$null) | Select-Object -Last 1
        $a = (Get-SimResult $run $cat).areas | Where-Object id -eq 'apps'; $c = $a.checks | Where-Object id -eq 'apps.simCache'
        $c.grade | Should -Be 'check'; $c.finding | Should -Be 'Cache-Betriebsart 1.'; $c.app | Should -Be 'simapp'; $a.countsText | Should -Be '3 zum Prüfen'; ($a.apps | Where-Object key -eq 'simapp').state | Should -Be 'installed'
    }
    It 'fuehrt im Nachweis die Lesequellen und was nicht aufgenommen wurde' {
        $Proof | Should -Match 'Lesequellen'; $Proof | Should -Match 'Nicht aufgenommen'
        foreach ($title in 'Win32_ComputerSystem class', 'GetPerformanceInfo function', 'Windows Installer Properties for the Uninstall Registry Key', 'Microsoft Edge - Update policies') { $Proof | Should -Match ([regex]::Escape($title)) -Because $title }
        ($Real.checks | Where-Object id -eq 'apps.edgeUserDataDir').kind | Should -Be 'rule'                       # ob der Pfad lokal ist, kann die Regel nicht unterscheiden
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Health.Tests.ps1`
Expected: FAIL, der Katalog hat 64 statt 77 Prüfungen

- [ ] **Step 3: Quellen öffnen, die 13 Prüfungen, die Tabellen „Lesequellen" und „Nicht aufgenommen" schreiben** (wie Task 14a, Step 3; für „Lesequellen" jedes Dokument der Spalte „Dokument" der Wertetabellen und der Tabellen der Proben öffnen)

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/health.de.json docs/guidance/quellen.md tests/Health.Tests.ps1
git commit -m "Add the health checks on applications and complete the record of sources"
```

- [ ] **Step 6: Durchsicht durch den Auftraggeber anstoßen** – `src/health.de.json`, `src/apps.json` und den Abschnitt „Zustandsbild" von `docs/guidance/quellen.md` dem Auftraggeber zur fachlichen Durchsicht vorlegen, zusammen mit der Tabelle „Schwellen des Katalogs" (welche Zahlen Vorschläge sind), der Liste der Prüfungen aus Praxisquellen und der Ausnahme zum Energiesparplan. Die Durchsicht hält die folgenden Tasks nicht auf; Änderungswünsche werden in einem eigenen Commit `Revise the health catalogue after review` umgesetzt (Tests aus Step 1 der Tasks 14a bis 14c grün). Der Baustein gilt erst nach der Durchsicht und nach Task 22 als fertig.

---

## Teil B – nach Task 7 und der Korrekturrunde 2 von Task 6 des geführten Berichts (Tasks 15–17)

Voraussetzung: Teil A ist in den Hauptstrang zusammengeführt; `src/New-WorkerPerfReport.ps1` bindet `src/WorkerPerf.Guidance.ps1` ein und legt `guide`, `rank`, `copy` je Vorfall und `print.involvedFrom` an (Task 7 des geführten Berichts) und hat den Parameter `-AppsFile`, liest die Anwendungsliste mit `Read-WorkerPerfApps` und legt sie als `appList` in die Berichtsdaten (Korrekturrunde 2 von Task 6 des geführten Berichts; ihre drei Commits ändern dieselben Dateien wie Task 16 und sind vorher im Hauptstrang).

### Task 15: Maskierung – Namen aus `health.json`

**Files:**
- Modify: `src/WorkerPerf.Mask.ps1` (`New-WorkerPerfMask` und eine neue Funktion davor; `$script:WorkerPerfMaskProfileFolders`; Kopfkommentar)
- Test: `tests/Mask.Tests.ps1`
- Nicht anfassen: die drei Feldlisten am Anfang von `src/WorkerPerf.Mask.ps1` (Freitextfelder, Wörterbücher mit Datenschlüsseln, Schlüsselwortfelder) und `tests/MaskCensus.json` (Task 16), `src/New-WorkerPerfReport.ps1`.

**Interfaces:**
- Consumes: `$script:WorkerPerfHealthValues` (Typzusätze je Wert und Feld), `ConvertFrom-WorkerPerfJsonFile`, `Add-WorkerPerfMaskHost`, `Add-WorkerPerfMaskUncName`, `Add-WorkerPerfMaskAccount`, `Add-WorkerPerfMaskName`, `Add-WorkerPerfMaskPatternNames`, `Add-WorkerPerfMaskProtected`, `$script:WorkerPerfMaskPathFieldPatterns`.
- Produces: `Add-WorkerPerfMaskHealthNames($State, [string]$Path)`: liest `<Path>\health.json`, wenn sie da ist (eine Datei, die sich nicht lesen lässt, gibt nichts), und geht die Werteliste in ihrer Reihenfolge durch, je gelesenem Wert und je Feld eines Listeneintrags in der Reihenfolge der Felder: `:host` → `Add-WorkerPerfMaskHost`, außer der Eintrag ist eine IPv6-Adresse (er enthält einen Doppelpunkt, und `[ipaddress]::TryParse` nimmt ihn an): dann `Add-WorkerPerfMaskName` mit der Art `address`, weil `Add-WorkerPerfMaskHost` nur eine IPv4-Adresse als Adresse erkennt und eine IPv6-Adresse sonst „Server NN" hieße; `:hosts` → je Teil zwischen Leerzeichen dasselbe; `:share` → `Add-WorkerPerfMaskUncName … 'share'`; `:path` → `Add-WorkerPerfMaskPatternNames` mit `$script:WorkerPerfMaskPathFieldPatterns`; `:user` → `Add-WorkerPerfMaskAccount <Wert> <Feld Domain desselben Eintrags oder ''> $false`; `:domain`, `:client`, `:address` → `Add-WorkerPerfMaskName` mit dieser Art (eine IPv6-Adresse ist damit eine Adresse wie eine IPv4-Adresse); `:protected` → `Add-WorkerPerfMaskProtected`; `:free` und `value` → nichts (ein Anwendungswert, der Namen tragen kann, steht nach `names: true` der Anwendungsliste im Feld `Names` vom Typ `text:free`). `New-WorkerPerfMask` ruft sie als Schritt (9) nach Schritt (8), vor dem Block der Namen, die bleiben, und damit vor der Vergabe der Nummern. `$script:WorkerPerfMaskProfileFolders` erhält `Administrator` und `Administrator.*`: der Profilordner des eingebauten Kontos gehört keiner Person, steht aber auf fast jedem Worker in `sessions.localProfiles`; als Name gesammelt, würde das Wort „Administrator" in jedem Text des maskierten Berichts ersetzt.

Aussagen bestehender Tests, die sich ändern: die erwartete Liste in `'enthaelt keinen Namen der Aufzeichnung ausser in einem geschuetzten Wort'` endet zusätzlich auf die vierzehn Einträge des Tests unten; `$Sim.MaskP.Entries.Count` ist 51 statt 50 (ein Benutzer mehr).

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/Mask.Tests.ps1`, im Block `'Maskierte Berichtsdaten der simulierten Stunde'`)

```powershell
        It 'sammelt die Namen aus health.json nach allen anderen und laesst die bisherigen Nummern stehen' {   # Review Focus 4
            $e = @($Sim.Mask.Entries | ForEach-Object { '{0}:{1}={2}' -f $_.Kind, $_.Name, $_.Replacement })
            $e[-14..-1] | Should -Be @('user:user026=Benutzer 26', 'server:ddc01.sim.local=Server 05', 'server:ddc01=Server 05', 'server:ddc02.sim.local=Server 06', 'server:ddc02=Server 06',
                'server:wem01.sim.local=Server 07', 'server:wem01=Server 07',
                'share:\\fs01\defsig$=Freigabe 03', 'address:10.20.0.10=Adresse 01', 'address:10.20.0.11=Adresse 02', 'address:fd00:20::10=Adresse 03',
                'server:zeit01.sim.local=Server 08', 'server:zeit01=Server 08', 'address:10.20.0.20=Adresse 04')
            $e[0] | Should -Be 'server:SIM-VDA01=Server 01'; $e | Should -Contain 'share:\\fs01\profile$=Freigabe 02'; @($e | Where-Object { $_ -like 'share:*' }).Count | Should -Be 3
            @($Sim.Mask.Entries | Where-Object Name -eq 'Administrator').Count | Should -Be 0                  # der Ordner des eingebauten Kontos ist keine Person
            foreach ($p in 'WdFilter', 'upmjit', 'BrokerAgent', 'WinDefend', 'Citrix WEM Agent Host Service') { $Sim.Mask.Protected | Should -Contain $p }
            Hide-WorkerPerfReportText 'DNS fd00:20::10 und 10.20.0.10, Controller ddc01.sim.local, WEM wem01.sim.local, Zeit zeit01.sim.local, Profil C:\Users\user026, als Administrator anmelden' $Sim.Mask |
                Should -Be 'DNS Adresse 03 und Adresse 01, Controller Server 05, WEM Server 07, Zeit Server 08, Profil C:\Users\Benutzer 26, als Administrator anmelden'
            @($Sim.MaskP.Entries | Where-Object Kind -eq 'user').Count | Should -Be 26
        }
        It 'sammelt aus freiem Servertext nichts und uebersteht eine fehlende oder beschaedigte Datei' {
            $run = Copy-SimRun $SimRun (Join-Path $TestDrive 'maskhealth'); $f = Join-Path $run 'health.json'
            $names = { @((New-WorkerPerfMask -Path $run -Level 'Alles' -Texts $Texts).Entries | ForEach-Object Name) }
            & $names | Should -Not -Contain 'prn01'                                    # steht nur in einem Richtlinienwert (freier Text)
            @(& $names | Where-Object { $_ -match 'office\$' }).Count | Should -Be 0   # die Updatequelle von Office steht nur in einem Anwendungswert mit names: true (freier Text)
            [IO.File]::WriteAllText($f, [IO.File]::ReadAllText($f).Replace('ddc02.sim.local', 'fd00:20::5'))             # ein Controller, der als IPv6-Adresse eingetragen ist
            $v6 = (New-WorkerPerfMask -Path $run -Level 'Alles' -Texts $Texts).Entries | Where-Object Name -eq 'fd00:20::5'; $v6.Kind | Should -Be 'address'; $v6.Replacement | Should -Match '^Adresse \d\d$'
            [IO.File]::WriteAllText($f, '{ kein json'); $broken = @(& $names); $broken | Should -Not -Contain 'ddc01.sim.local'; $broken | Should -Contain 'user001'
            Remove-Item $f; @(& $names).Count | Should -Be $broken.Count
        }
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Mask.Tests.ps1`
Expected: FAIL, die letzten Einträge der Maske sind Drucker, keine Adressen

- [ ] **Step 3: `Add-WorkerPerfMaskHealthNames` umsetzen und in `New-WorkerPerfMask` aufrufen; `Administrator` in die Liste der Profilordner ohne Person aufnehmen**

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1` und die Browserprüfungen
Expected: `Failed: 0`, `browser checks passed: <n>`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Mask.ps1 tests/Mask.Tests.ps1
git commit -m "Collect the names of the health picture for masking"
```

---

### Task 16: Berichtsdaten – Abschnitt `health`, Verweis im Vorfall, Kopiertexte, Bestand

**Files:**
- Modify: `src/New-WorkerPerfReport.ps1` (Hilfe und `param`, Einbinden, Aufbau der Daten vor dem Maskieren), `src/WorkerPerf.Health.ps1`, `src/WorkerPerf.Mask.ps1` (nur die Listen der Freitext- und Schlüsselwortfelder), `tests/MaskCensus.json`
- Test: `tests/Report.Tests.ps1`, `tests/Mask.Tests.ps1` (Markertest, Namenslisten), `tests/Health.Tests.ps1`
- Nicht anfassen: `src/report-template.html`, `tests/report-browser.js` (Teil C; die Seite ignoriert das neue Feld bis dahin).

**Interfaces:**
- Consumes: Tasks 10–15; aus dem geführten Bericht der Parameter `-AppsFile` des Berichtsskripts mit dem Aufruf `Read-WorkerPerfApps $AppsFile` (Korrekturrunde 2 seines Task 6), `incidents[].guide.situation`, `incidents[].event.patterns[].id`, `Format-WorkerPerfCopyLines`, `ConvertTo-WorkerPerfAnonymousText` und die Maske der Stufe `Alles`, die das Berichtsskript für die Kopiertexte der Vorfälle bildet.
- Produces:
  - Parameter `[string]$HealthFile` (Standard `health.de.json` neben dem Skript). Einen zweiten Parameter für die Anwendungsliste gibt es nicht: das Berichtsskript hat seit dem geführten Bericht `-AppsFile` (Standard `apps.json` neben dem Skript) und liest die Datei dort mit `Read-WorkerPerfApps` für die Bedingung `app.<key>`. Direkt danach liest `Read-WorkerPerfHealthApps $AppsFile` dieselbe Datei für das Zustandsbild (die Anwendungen mit `installed` und `probes`), und die Liste geht an `Read-WorkerPerfHealthCatalogue $HealthFile <Liste>`; beides vor dem Lesen der Aufzeichnung. Eine fehlerhafte Anwendungsliste bricht mit der Meldung des Lesers ab, der den Fehler zuerst bemerkt (der des geführten Berichts läuft zuerst), ein fehlerhafter Katalog mit der Meldung aus Task 11. Die Hilfe von `-AppsFile` nennt zusätzlich das Zustandsbild. Die Kopie `apps.json` in der Aufzeichnung wird nicht gelesen. `src/WorkerPerf.Health.ps1` wird nach `src/WorkerPerf.Guidance.ps1` eingebunden.
  - `Get-WorkerPerfHealthIncidentChecks -Result -Situation <string> -Patterns <string[]> -> string[]`: die Kennungen der Prüfungen mit Einstufung `check` oder `act`, deren `relates` die Situation oder `pattern.<id>` eines der Muster enthält, in der festen Reihenfolge der Bereiche und darin in der Reihenfolge von `areas[].checks` (auffällige zuerst); leer, wenn `state` nicht `read` ist.
  - `Add-WorkerPerfHealthReportTexts -Result -Catalogue -Server <string> [-AnonymousMask <Maske>]` ergänzt bei `state` `read`: `title` (`copy.title`), `headline` (`copy.readAt` mit Datum `dd.MM.yyyy` und Uhrzeit `HH:mm:ss` des Lesezeitpunkts in der Ortszeit des Servers, gebildet aus `readAt` und `offsetMin` des Ergebnisses, und Sekunden mit einer Nachkommastelle und Komma), `unknownText` (`copy.unknownOne` bzw. `copy.unknownMany`; leer bei 0), `changedText` (`copy.changed` mit den Schwellen als `copy.changedItem`, mit „, " verbunden; leer ohne Abweichung), `incidentNote` (`copy.incidentNote`) und je Bereich und je Prüfung `copy = [ordered]@{ named; anonymous }`. Bei den anderen Zuständen nur `title`.
    - Kopiertext einer Prüfung (über `Format-WorkerPerfCopyLines`): `copy.copyHead` (Server und Datum des Lesezeitpunkts), dann `copy.copyCheckTitle` (Bezeichnung des Bereichs, Titel, Wort der Einstufung), der Befund (und `note`), `copy.copyMeaning` mit `meaning`, `copy.copyTodo` mit den nummerierten Schritten (je Schritt `copy.copyStep`), `copy.copySource`.
    - Kopiertext eines Bereichs: `copy.copyHead`, `copy.copyAreaTitle` (Bezeichnung, Wort der Einstufung), je Prüfung mit `act`, `check` oder `unknown` `copy.copyAreaItem` (Titel, Wort, Befund; eine Prüfung mit dem Ergebnis `na` steht nicht im Kopiertext des Bereichs), `copy.copyOk` mit der Zahl der Prüfungen in Ordnung, `notCovered`. Kein Satzteil dieser Texte steht im PowerShell-Code.
    - `anonymous` = `ConvertTo-WorkerPerfAnonymousText named <Maske>`; ohne `-AnonymousMask` (maskierter Bericht) `$null`. Von der Maske braucht die Funktion nichts als diesen Aufruf (ein Test des geführten Berichts ersetzt die Maske durch eine leere).
  - Berichtsdaten: neues Feld `health` (das Ergebnis aus Task 13 mit diesen Texten); jeder Eintrag von `incidents` und `before.incidents` erhält `health` (`string[]`, auch leer). Alles entsteht vor dem Maskieren; `-Mask` maskiert es mit den übrigen Daten.
  - Bestand und Listen (jedes Textfeld der neuen Daten):

| Pfad | Klasse | Liste in `src/WorkerPerf.Mask.ps1` |
|---|---|---|
| `health.state` | keyword | `health.state` |
| `health.catalogueVersion` | keyword | `health.catalogueVersion` |
| `health.title`, `health.text`, `health.headline`, `health.unknownText`, `health.changedText`, `health.incidentNote`, `health.environmentText`, `health.eventsReachText`, `health.summary.text` | composed | |
| `health.grades.<ok, check, act, unknown, na>.word`, `.symbol` | composed | |
| `health.changed[].id`, `health.changed[].unit` | keyword | (`id`, `unit` stehen schon dort) |
| `health.changed[].label` | composed | |
| `health.areas[].id`, `.status` | keyword | (schon dort) |
| `health.areas[].grade`, `health.areas[].checks[].grade` | keyword | `grade` |
| `health.areas[].label`, `.statusText`, `.countsText`, `.notCovered`, `.intro`, `.copy.named`, `.copy.anonymous` | composed | |
| `health.areas[].apps[].key` | keyword | (`apps.key` steht seit dem geführten Bericht dort) |
| `health.areas[].apps[].state` | keyword | `apps.state` |
| `health.areas[].apps[].label`, `.text` | composed (die Bezeichnung stammt aus `src/apps.json`, nicht vom Server) | |
| `health.areas[].checks[].app` | keyword | `checks.app` |
| `health.areas[].error` | copied | `health.areas[].error` |
| `health.areas[].checks[].id`, `.kind`, `.source.url` | keyword | (schon dort) |
| `health.areas[].checks[].source.date` | keyword | `source.date` |
| `health.areas[].checks[].relates[]` | keyword | `checks.relates` |
| `health.areas[].checks[].title`, `.finding`, `.why`, `.note`, `.value`, `.meaning`, `.kindLabel`, `.todo[].text`, `.todo[].where`, `.todo[].sign`, `.source.vendor`, `.source.title`, `.copy.named`, `.copy.anonymous` | composed | |
| `health.raw[].id` | keyword | (schon dort) |
| `health.raw[].area`, `.state`, `.reason` | keyword | `raw.area`, `raw.state`, `raw.reason` |
| `health.raw[].label`, `health.raw[].stateText` | composed | |
| `health.raw[].text`, `health.raw[].items[].text` | name | |
| `health.raw[].free`, `health.raw[].items[].free` | copied | `health.raw[].free`, `health.raw[].items[].free` |
| `incidents[].health[]`, `before.incidents[].health[]` | keyword | `incidents.health` |

  - Markertest (`New-CanaryRun` in `tests/Mask.Tests.ps1`): setzt in `health.json` der Kopie über die Werteliste einen eigenen Marker in jedes Feld, das freien Servertext oder einen Servernamen tragen kann, und merkt sich die gesetzten Marker (`$script:CanaryHealth = @{ Free = string[]; Names = string[] }`). Je Wert und je Listenfeld mit einem der folgenden Typzusätze (bei einer Liste im ersten Eintrag; ein Wert, der nicht gelesen ist, und eine leere Liste werden durch einen gelesenen Wert mit einem Eintrag ersetzt, dessen übrige Felder leer sind; bei `apps.probes` in der ersten Zeile, deren Feld `Names` gefüllt ist: nur der Wert einer Probe mit `names: true` erreicht den Bericht): `:free` → `CANARYH<nn>`; `:host` und `:hosts` → `kanari<nn>.sim.local`; `:share` → `\\kanari<nn>\frei`; `:path` → `\\kanari<nn>\frei\ordner`. `<nn>` zählt je Marker hoch. Dazu der erste leere `Error` eines Bereichs: `Fehler CANARYHER`. Fehlt danach ein Marker in der Datei, wirft er wie bisher.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben**

`tests/Report.Tests.ps1` (im `BeforeAll` zusätzlich `$script:ReportScript = Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1'; $script:RoleFile = Join-Path (Split-Path $R.Report) 'roles.sim.json'`):

```powershell
Describe 'Zustandsbild in den Berichtsdaten' {
    It 'traegt Zustand, Bereiche, Zusammenfassung und Kopfangaben' {
        $h = $D.health; $h.state | Should -Be 'read'; @($h.areas.id) | Should -Be $WorkerPerfHealthAreas
        @($h.areas.grade) | Should -Be @('ok', 'check', 'ok', 'ok', 'act', 'act', 'ok', 'ok', 'check', 'check', 'check')
        $h.summary.text | Should -Be '2 Bereiche zum Handeln, 4 zum Prüfen, 5 in Ordnung'; $h.unknownCount | Should -Be 2; @($h.changed).Count | Should -Be 0; $h.changedText | Should -Be ''
        $h.readAt | Should -BeLessOrEqual $D.meta.start; $h.durationMs | Should -Be 0; $h.title | Should -Be 'Zustand des Workers'; $h.headline | Should -Match '\d\d\.\d\d\.\d{4}'; $h.unknownText | Should -Match '2'
        $h.environmentText | Should -Match 'nicht persistent'; $h.eventsReachText | Should -Match '\d\d\.\d\d\.\d{4}'; ($h.areas | Where-Object id -eq 'events').intro | Should -Be $h.eventsReachText
        $apps = $h.areas | Where-Object id -eq 'apps'; @($apps.apps.key | Sort-Object) | Should -Be @('edge', 'office', 'teams'); @($apps.apps.state | Select-Object -Unique) | Should -Be @('installed')
        @($apps.checks | Where-Object grade -eq 'check').id | Should -Be @('apps.edgeBackgroundMode', 'apps.teamsAutoUpdate'); ($apps.checks | Where-Object id -eq 'apps.edgeBackgroundMode').app | Should -Be 'edge'
        ($h.raw | Where-Object id -eq 'apps.office.updateUrl').free | Should -Be '\\fs01\office$\updates'; ($h.raw | Where-Object id -eq 'apps.edge.backgroundMode').label | Should -BeLike 'Microsoft Edge – *'
        ($h.raw | Where-Object id -eq 'maintenance.searchService').stateText | Should -BeLike 'nicht zutreffend*'
        $c = ($h.areas | Where-Object id -eq 'print').checks[0]; $c.id | Should -Be 'print.driversInSpooler'; $c.grade | Should -Be 'act'; $c.kind | Should -Be 'vendor'; $c.source.url | Should -Match '^https://'
        foreach ($f in 'title', 'finding', 'meaning', 'kindLabel', 'value') { [string]$c.$f | Should -Not -BeNullOrEmpty -Because $f }; @($c.todo).Count | Should -BeGreaterThan 0
        $h.grades.act.word | Should -Be 'Handeln'; $h.grades.na.word | Should -Be 'Trifft nicht zu'; @($h.raw).Count | Should -Be 202; $h.offsetMin | Should -Be $D.meta.offsetMin
        ($h.areas | Where-Object id -eq 'profile').countsText | Should -Be '1 zum Handeln'; ($h.areas | Where-Object id -eq 'size').countsText | Should -Be ''
        ($h.areas | Where-Object id -eq 'security').statusText | Should -Not -BeNullOrEmpty; ($h.areas | Where-Object id -eq 'size').statusText | Should -Be ''      # Sicherheitsprodukte: teilweise gelesen
    }
    It 'verweist beim Absturz des Druckdienstes auf die Treiberpruefung' {
        $p = $D.incidents | Where-Object { $_.type -eq 'ereignis' -and $_.event.kind -eq 'print' }
        @($p.health) | Should -Be @('print.driversInSpooler')
        @(($D.incidents | Where-Object lead -eq 'cpu').health) | Should -Be @('maintenance.tasksInWorkHours', 'apps.edgeBackgroundMode', 'apps.teamsAutoUpdate')
        @(($D.incidents | Where-Object lead -eq 'memory').health).Count | Should -Be 0                    # passt keine Pruefung, entfaellt der Abschnitt
        $all = @{}; foreach ($a in $D.health.areas) { foreach ($c in $a.checks) { $all[$c.id] = $c } }
        foreach ($i in @($D.incidents) + @($D.before.incidents)) {
            $i.PSObject.Properties.Name | Should -Contain 'health'
            foreach ($id in @($i.health)) { $all[$id].grade | Should -BeIn 'check', 'act'; ($all[$id].relates -contains $i.guide.situation -or @($i.event.patterns | ForEach-Object { 'pattern.' + $_.id } | Where-Object { $all[$id].relates -contains $_ }).Count -gt 0) | Should -BeTrue }
        }
        $D.health.incidentNote | Should -Match 'beitragen'; $D.health.incidentNote | Should -Not -Match 'Ursache'
    }
    It 'liefert Kopiertexte je Pruefung und Bereich, mit und ohne Namen' {
        $a = $D.health.areas | Where-Object id -eq 'profile'; $c = $a.checks[0]; $c.id | Should -Be 'profile.containerFull'
        @($c.copy.named -split "`r`n" | Where-Object { $_.Length -gt 78 }).Count | Should -Be 0
        foreach ($part in $c.title, $c.finding, $c.todo[0].text, $c.source.title, 'Handeln') { ($c.copy.named -replace "`r`n\s*", ' ') | Should -Match ([regex]::Escape($part)) }
        $c.copy.named | Should -Match 'SIM-VDA01'; $c.copy.anonymous | Should -Not -Match 'SIM-VDA01|user0\d\d|fs01'; $c.copy.anonymous | Should -Match 'Handeln'
        ($a.copy.named -replace "`r`n\s*", ' ') | Should -Match ([regex]::Escape($c.title)); $a.copy.anonymous | Should -Not -Match 'SIM-VDA01'
    }
    It 'maskiert das Zustandsbild und leert freien Servertext' {   # Review Focus 4
        $m = (Get-ReportData $R.Masked).health; $json = $m | ConvertTo-Json -Depth 12
        foreach ($n in 'user0\d\d', 'SIM-VDA01', 'CONTOSO', 'fs01', 'ddc0\d', 'wem01', 'zeit01', 'defsig', 'office\$', '10\.20\.0\.\d\d', 'fd00:20::10', 'Inventarlauf', 'inventar\.exe', 'prn01', 'USERNAME') { $json | Should -Not -Match $n -Because $n }
        ($m.raw | Where-Object id -eq 'apps.office.updateUrl').free | Should -Be ''; ($m.areas | Where-Object id -eq 'apps').apps[0].label | Should -Be ($D.health.areas | Where-Object id -eq 'apps').apps[0].label     # die Bezeichnung einer Anwendung bleibt
        @($m.areas.grade) | Should -Be @($D.health.areas.grade); $m.areas[0].checks[0].copy.anonymous | Should -BeNullOrEmpty; $m.areas[0].checks[0].copy.named | Should -Not -BeNullOrEmpty
        ($m.raw | Where-Object id -eq 'maintenance.tasks').items[0].free | Should -Be ''; (($D.health.raw | Where-Object id -eq 'maintenance.tasks').items.free -join ' ') | Should -Match 'Inventarlauf'
        ($m.raw | Where-Object id -eq 'vda.controllers').items[0].text | Should -Match 'Server \d\d'; ($m.raw | Where-Object id -eq 'network.dnsServers').items[2].text | Should -Match 'Adresse 03'
    }
    It 'sagt bei einer Aufzeichnung von vor dem Zustandsbild nicht erfasst' {   # Review Focus 2
        $old = Copy-SimRun $R.Run (Join-Path $TestDrive 'old') @('health.json'); $f = Join-Path $TestDrive 'old.html'
        [void](& $ReportScript -Path $old -OutFile $f -RoleFile $RoleFile 6>$null); $o = Get-ReportData $f
        $o.health.state | Should -Be 'notRecorded'; $o.health.text | Should -Be 'Zustandsbild nicht erfasst.'; $o.health.title | Should -Be 'Zustand des Workers'; @($o.health.areas).Count | Should -Be 0
        @($o.skipped.id) | Should -Not -Contain 'Zustand'; @($o.incidents | Where-Object { @($_.health).Count -gt 0 }).Count | Should -Be 0; @($o.incidents).Count | Should -Be @($D.incidents).Count
    }
    It 'nennt eine geaenderte Schwelle und bricht bei einem fehlerhaften Katalog mit Pruefung und Feld ab' {
        $j = Get-Content (Join-Path $PSScriptRoot '../src/health.de.json') -Raw | ConvertFrom-Json; $j.thresholds.containerUsedHardPct.value = 99
        $alt = Join-Path $TestDrive 'h.json'; [IO.File]::WriteAllText($alt, ($j | ConvertTo-Json -Depth 12)); $f = Join-Path $TestDrive 'alt.html'
        [void](& $ReportScript -Path $R.Run -OutFile $f -RoleFile $RoleFile -HealthFile $alt 6>$null); $a = (Get-ReportData $f).health
        @($a.changed.id) | Should -Be @('containerUsedHardPct'); $a.changed[0].value | Should -Be 99; $a.changed[0].default | Should -Be 95; $a.changedText | Should -Match '99'
        (($a.areas | Where-Object id -eq 'profile').checks | Where-Object id -eq 'profile.containerFull').grade | Should -Be 'check'           # 96 % liegt unter 99 %
        $j.checks[0].PSObject.Properties.Remove('source'); [IO.File]::WriteAllText($alt, ($j | ConvertTo-Json -Depth 12))
        { & $ReportScript -Path $R.Run -OutFile $f -RoleFile $RoleFile -HealthFile $alt 6>$null } | Should -Throw "*Pruefung 'size.commitHeadroom'*Feld 'source'*"
    }
}
```

`tests/Mask.Tests.ps1`: `New-CanaryRun` setzt die Marker der Interfaces. Der Markertest verlangt im unmaskierten Bericht zusätzlich jeden Marker aus `$CanaryHealth.Free` und `$CanaryHealth.Names` und `CANARYHER`; die Prüfung „nirgends `CANARY`" der maskierten Berichte beider Stufen bleibt, wie sie ist (sie deckt den freien Servertext); neu: der Bericht der Stufe `Alles` enthält nirgends `kanari` (Servernamen ersetzt nur diese Stufe). `$script:Persons` erhält `user026`; `$script:Others` erhält `ddc0\d`, `wem01`, `zeit01`, `defsig`, `office\$`, `10\.20\.0\.\d\d`, `fd00:20::10`, `Inventarlauf`, `prn01`.

Aussage eines Tests aus Task 7 des geführten Berichts, die sich ändert: `'bleibt ohne -Mask bytegleich zum Bericht ohne Maskierungscode, bis auf die Fassungen ohne Namen'` zählt die Felder `"anonymous":"` im unmaskierten Bericht der simulierten Stunde; die Zahl steigt um 88 (77 Prüfungen und 11 Bereiche; von 17 auf 105; nennt der Test nach den Runden des geführten Berichts einen anderen Ausgangswert als 17, gilt dieser Wert plus 88).

`tests/Health.Tests.ps1`:

```powershell
Describe 'Texte und Verweise fuer den Bericht' {
    It 'waehlt je Vorfall die auffaelligen Pruefungen mit passendem Bezug' {
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel (Get-Vol 1.5) @{ PrintDrivers = $HpNone }) -Catalogue $Cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        Get-WorkerPerfHealthIncidentChecks -Result $r -Situation 'disk' -Patterns @() | Should -Be @('operation.diskFree')
        Get-WorkerPerfHealthIncidentChecks -Result $r -Situation 'crash' -Patterns @('printdriver') | Should -Be @('operation.diskFree', 'print.driversInSpooler')
        @(Get-WorkerPerfHealthIncidentChecks -Result $r -Situation 'cpu' -Patterns @('overlap')).Count | Should -Be 0
        $ok = Get-WorkerPerfHealthResult -Model (New-HealthModel (Get-Vol 38)) -Catalogue $Cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        @(Get-WorkerPerfHealthIncidentChecks -Result $ok -Situation 'disk' -Patterns @()).Count | Should -Be 0             # in Ordnung und nicht pruefbar verweisen nicht
        $none = Get-WorkerPerfHealthResult -Model (New-HealthModel @{} @{ Health = $null; HealthState = 'notRecorded' }) -Catalogue $Cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        @(Get-WorkerPerfHealthIncidentChecks -Result $none -Situation 'disk' -Patterns @()).Count | Should -Be 0
    }
    It 'bildet Kopf- und Kopiertexte' {
        $cat = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { $c.copy.copyHead = 'WorkerPerf {server}, Zustandsbild vom {date}'; $c.copy.readAt = 'Gelesen am {date} um {time} ({seconds} s)'
            $c.copy.unknownMany = '{n} Prüfungen nicht prüfbar'; $c.copy.copyStep = '{n}. {text} – {where}; erkennbar an {sign}'; $c.copy.changed = 'Geändert: {list}'; $c.copy.changedItem = '{label} {value} {unit} (ausgeliefert {default} {unit})'; $c.thresholds.diskFreeGB.value = 25 })
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel (Get-Vol 1.5) @{ Skip = [string[]]@('Drucken') }) -Catalogue $cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        Add-WorkerPerfHealthReportTexts -Result $r -Catalogue $cat -Server 'T1'
        $r.headline | Should -Be 'Gelesen am 15.01.2026 um 08:00:00 (0,0 s)'; $r.changedText | Should -Be 'Geändert: Freier Platz 25 GB (ausgeliefert 10 GB)'; $r.unknownText | Should -Be 'Text unknownOne'
        $c = ($r.areas | Where-Object id -eq 'operation').checks[0]; $lines = $c.copy.named -split "`r`n"
        $lines[0] | Should -Be 'WorkerPerf T1, Zustandsbild vom 15.01.2026'; $lines[1] | Should -Be 'Bereich operation – Freier Platz: Handeln'; $c.copy.named | Should -Match '1\. t – w; erkennbar an s'
        $c.copy.anonymous | Should -BeNullOrEmpty; @($lines | Where-Object { $_.Length -gt 78 }).Count | Should -Be 0
        ($r.areas | Where-Object id -eq 'operation').copy.named | Should -Match '- Freier Platz: Handeln\. Nur 1,5 GB frei\.'
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "& ./tests/Invoke-Tests.ps1 -Path tests/Report.Tests.ps1, tests/Health.Tests.ps1"`
Expected: FAIL, die Berichtsdaten haben kein Feld `health`

- [ ] **Step 3: `Get-WorkerPerfHealthIncidentChecks` und `Add-WorkerPerfHealthReportTexts` umsetzen**

- [ ] **Step 4: `-HealthFile`, das Lesen der Anwendungsliste für das Zustandsbild über den vorhandenen Parameter `-AppsFile`, den Abschnitt `health` und `health[]` je Vorfall in das Berichtsskript einbauen; die Listen in `src/WorkerPerf.Mask.ps1` und `tests/MaskCensus.json` nach der Tabelle ergänzen; `New-CanaryRun` erweitern**

- [ ] **Step 5: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1` und die Browserprüfungen (die Seite ist unverändert und bleibt grün)
Expected: `Failed: 0`, `browser checks passed: <n>`

- [ ] **Step 6: Commit**

```bash
git add src/New-WorkerPerfReport.ps1 src/WorkerPerf.Health.ps1 src/WorkerPerf.Mask.ps1 tests/MaskCensus.json tests/Report.Tests.ps1 tests/Mask.Tests.ps1 tests/Health.Tests.ps1
git commit -m "Put the graded health picture and its incident references into the report data"
```

---

### Task 17: Zustandsbericht aus dem Schnelllauf (Berichtsdaten)

**Files:**
- Modify: `src/New-WorkerPerfReport.ps1`, `tests/TestHelpers.ps1` (`New-TestReports`), `tests/MaskCensus.json` (ein Feld)
- Test: `tests/HealthOnly.Tests.ps1`
- Nicht anfassen: `src/report-template.html`, `tests/report-browser.js` (Task 20 passt die Seite an; bis dahin wird ein Zustandsbericht nur als Daten geprüft).

**Interfaces:**
- Consumes: Tasks 9, 10, 16; `New-TestAppFile` (Task 2).
- Produces:
  - Im Berichtsskript werden drei Stücke zu Funktionen im Hilfsbereich, ohne Änderung ihres Inhalts, damit beide Wege sie rufen: der Aufbau von `before` (heute der Block, der `$beforeOut` bildet, einschließlich der Felder des geführten Berichts je Rückblick-Vorfall), der Aufbau der Treiberliste von `print`, und der Abschluss (Maskieren, Schreiben über die temporäre Datei, Zuordnungsdatei, Zeilen der Konsole).
  - Kurzer Weg direkt nach `Import-WorkerPerfRun`, wenn `Meta.HealthOnly` wahr ist: sind `-FocusUser`, `-ReportedTime` oder `-TopProcesses` angegeben, wirft er `Die Aufzeichnung ist ein Schnelllauf ohne Messung; nicht zusammen mit: <-Name, …>.` (`-From` und `-To` lehnt der Lader ab). Er bildet die Berichtsdaten mit genau den Feldern `meta`, `quality`, `health`, `before`, `print`, `skipped`, ruft den Abschluss und endet; Befunde, Vorfälle, Reihen, Lagebild und `noFinding` entstehen nicht.
    - `meta`: `computer`, `os`, `cores`, `ramGB`, `start` und `end` (beide `CaptureStartMs`), `offsetMin`, `durationMin` 0, `ticks` 0, `snapshots` 0, `simulated`, `endReason`, `endMessage`, `healthOnly` wahr, `reportKind` (`copy.healthOnlyHead`), `generated`; mit `-Mask` wie bisher `mask`.
    - `quality`: `unreadable` (`eventsBefore`, `printDrivers`), `sourceErrors`, `sources`.
    - `health` wie in Task 16 (`-HealthFile` und `-AppsFile` gelten auf beiden Wegen); `before` wie im Messweg; `print` = `drivers` wie im Messweg, `queues` und `processes` leer, `involvedFrom` = `lookback`, wenn der Rückblick gelesen oder teilweise gelesen wurde, sonst `none` (eine Messung, aus der Vorfälle stammen könnten, gibt es nicht; die Regel des Messwegs ergäbe `both`); `skipped` wie im Messweg.
  - Im Messweg erhält `meta` das Feld `healthOnly` (falsch).
  - Konsole des kurzen Wegs: `Zustandsbericht erstellt in <s> s: <Datei>` und `  <summary.text>`; bei `-Mask` die Zeilen der Maskierung wie bisher.
  - `tests/MaskCensus.json`: `meta.reportKind` → `composed`.
  - `New-TestReports` (`tests/TestHelpers.ps1`): zusätzlich `HealthRun` (ein Lauf von `Invoke-SimHealthOnly` unter `<OutDir>/health`), `Health` (`report-health.html`) und `HealthMasked` (`report-health-masked.html`, `-Mask Alles`).

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/HealthOnly.Tests.ps1`, neuer Block)

```powershell
Describe 'Zustandsbericht aus dem Schnelllauf' {
    BeforeAll {
        $script:ReportScript = Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1'; $script:Html = Join-Path $TestDrive 'ho.html'
        $script:Out = @(& $ReportScript -Path $Run -OutFile $Html 6>&1); $script:H = Get-ReportData $Html
    }
    It 'entsteht ohne Fehler und traegt nur Kopf, Zustandsbild, Rueckblick, Treiberliste und Weggelassenes' {
        @($H.PSObject.Properties.Name) | Should -Be @('meta', 'quality', 'health', 'before', 'print', 'skipped')
        $H.meta.healthOnly | Should -BeTrue; $H.meta.endReason | Should -Be 'healthonly'; $H.meta.reportKind | Should -Be 'Zustandsbericht ohne Messung'; $H.meta.computer | Should -Be 'SIM-VDA01'
        $H.meta.ticks | Should -Be 0; $H.meta.start | Should -Be $H.meta.end; $H.meta.start | Should -BeGreaterThan 0
        $H.health.state | Should -Be 'read'; $H.health.summary.text | Should -Be '1 Bereich zum Handeln, 5 zum Prüfen, 5 in Ordnung'; @($H.health.raw).Count | Should -Be 202
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
        @($a.checks | Where-Object { $_.app -eq 'simapp' }).Count | Should -Be 0; $a.countsText | Should -Be '2 zum Prüfen'      # der ausgelieferte Katalog hat keine Pruefung fuer sie
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
        Test-Path (Join-Path $TestDrive 'x.html') | Should -BeFalse
    }
}
```

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/HealthOnly.Tests.ps1`
Expected: FAIL, das Berichtsskript wirft in der Auswertung der Messreihen bzw. die Daten haben andere Felder

- [ ] **Step 3: Die drei Stücke des Berichtsskripts zu Funktionen machen** (danach alle Tests ausführen: `Failed: 0`, die Berichte der Messung sind unverändert)

- [ ] **Step 4: Den kurzen Weg, `meta.healthOnly` und die Berichte in `New-TestReports` umsetzen**

- [ ] **Step 5: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1` und die Browserprüfungen
Expected: `Failed: 0`, `browser checks passed: <n>`

- [ ] **Step 6: Commit**

```bash
git add src/New-WorkerPerfReport.ps1 tests/TestHelpers.ps1 tests/MaskCensus.json tests/HealthOnly.Tests.ps1
git commit -m "Build the health report of a quick run on a short path of its own"
```

---

## Teil C – nach Task 11 des geführten Berichts (Tasks 18–20)

### Gestaltung der Seite: Zustandsbild (gilt für die Tasks 18, 19 und 20)

Die Seite nutzt die Bausteine des geführten Berichts (`.status` mit Symbol und Wort, `.btn`, `.card`, `table()`, `copyText(text, button)`, `notMeasured(place)`, `isWebUrl`, `esc`). Jede Einstufung zeigt Symbol und Wort aus `health.grades`; die Farbe folgt der Einstufung (`act` wie kritisch, `check` wie auffällig, `ok` wie normal, `unknown` wie nicht gemessen). Jeder Text der Daten wird als Text eingesetzt, nie als HTML.

**Kopfleiste** (beide Ansichten): neben `#maskInfo` und `#skipInfo` der Hinweis `#healthInfo` mit `health.headline`; mit `health.changedText` und `health.unknownText` je ein weiterer Teil, durch „ · " getrennt. Bei `health.state` `notRecorded` oder `unreadable` steht dort `health.text`; bei `skipped` entfällt `#healthInfo` (`#skipInfo` nennt die Kategorie).

**Geführte Ansicht:** zwischen `#hints` und `#timeline` die Zeile `#healthRow` als Karte mit der Überschrift `health.title`. Bei `state` `read`: darunter `#healthSummary` (`health.summary.text`), der Satz `#healthEnv` (`health.environmentText`: die angenommene Zielumgebung) und elf Kacheln `.htile[data-area][data-grade]` in der Reihenfolge von `health.areas` (ab 900 px sechs je Zeile, darunter drei bzw. zwei, bei 400 px eine Spalte): Bezeichnung des Bereichs, Statuskennzeichen und die Zeile `countsText` aus den Daten (etwa „1 zum Handeln, 2 zum Prüfen, 1 nicht prüfbar"; sie entfällt, wenn sie leer ist). Jede Kachel ist ein Knopf (Tab, Enter) und öffnet die Bereichsansicht. Bei `notRecorded` und `unreadable` zeigt die Zeile nur `health.text`, ohne Kacheln. Bei `skipped` zeigt sie den Hinweis `notMeasured('health')`.

**Bereichsansicht `#area[data-area]`** (ersetzt Band, Zeile, Karten und Listen wie die Vorfallsansicht; Zurück, Esc und `#areaBack` stellen sie wieder her; Adressteil `a=<Bereich>`, ein unbekannter Bereich in der Adresse öffnet das Lagebild): Kopf mit Bezeichnung (`.av-title`), Statuskennzeichen und, wenn `statusText` nicht leer ist, dem Hinweis `.av-status` mit `statusText` und, wo vorhanden, `error` aus den Daten (die Seite bildet keinen dieser Sätze selbst); Knöpfe `#areaCopy` „Bereich kopieren" und `#areaBack` „Zurück zum Lagebild". Unter dem Kopf steht, wo `intro` nicht leer ist, der Satz `.av-intro` (im Bereich „Ereignisbild": ab wann die Protokolle reichen) und, wo `apps` nicht leer ist, die Liste `.av-apps` mit einer Zeile `.av-app[data-app][data-state]` je Anwendung (`text` aus den Daten: so steht eine nicht installierte Anwendung als „nicht installiert" im Bereich). Darunter je Prüfung in der Reihenfolge der Daten ein Block `.hcheck[data-check][data-grade]`: Titel (`.hc-title`) mit Statuskennzeichen, Befund (`.hc-finding`; bei `unknown` der Satz mit dem Grund, bei `note` der Hinweis darunter), „Was bedeutet das?" (`.hc-meaning`), „Was tun?" (`ol.hc-todo`, je Schritt Text fett, darunter „Wo:" und „Woran erkennbar:"), die Quelle (`.hc-source`: `kindLabel`, Hersteller, Titel als Verweis, wenn `isWebUrl(url)`, Datum) und der Knopf `.hc-copy` „Kopieren". Prüfungen in Ordnung sind eingeklappt (`details.hcheck`), die übrigen eingestuften offen. Prüfungen mit dem Ergebnis `na` stehen am Ende (die Daten ordnen sie so), eingeklappt, mit Symbol und Wort aus `health.grades.na` und dem Satz mit dem Grund; sie zählen in keiner Zeile einer Kachel. Am Ende `.area-notcovered` mit `notCovered`. Kopiert wird `copy.named`, mit gesetztem Schalter `#anonSwitch` `copy.anonymous`; im maskierten Bericht gibt es den Schalter nicht. `window.WP` erhält `openArea(id, checkId)` und `closeArea()`.

**Vorfallsansicht:** nach `.iv-todo` der Abschnitt `section.iv-health` „Dazu im Zustandsbild", nur wenn `incident.health` nicht leer ist: der Satz `health.incidentNote`, darunter je Prüfung eine Zeile `.ivh-item[data-check]` mit Statuskennzeichen, Titel, Befund und dem Knopf `.ivh-open` „Im Zustandsbild öffnen" (`WP.openArea(<Bereich>, <Prüfung>)`, die Prüfung wird in den sichtbaren Bereich geholt).

**Expertenansicht:** neunter Reiter `health` „Zustand" in `#xtabs`, Bereich `#xt-health`: der Hinweis `#healthNote` (`health.headline` und der Satz, dass der gewählte Zeitraum hier nicht wirkt), die Filter `#hfGrade` (alle, Handeln, Prüfen, Nicht prüfbar, In Ordnung, Trifft nicht zu; die Wörter aus `health.grades`) und `#hfArea` (alle, je Bereich), die Tabelle `#tHealth` mit den Spalten Bereich, Prüfung, Wert, Einstufung, Art, Quelle (jede Prüfung eine Zeile `tr[data-check]`), darunter `details#healthRaw` „Gelesene Werte" mit der Tabelle `#tHealthRaw` (Bereich, Wert, Zustand, Inhalt; der Zustand ist `stateText` aus den Daten, etwa „nicht zutreffend" mit dem Grund; Listen als Zeilen untereinander; ein geleerter freier Text zeigt den Hinweis der Maskierung wie die übrigen geleerten Felder). Bei `state` ungleich `read` steht im Bereich nur `health.text` bzw. der Hinweis `notMeasured('health')`.

**Zustandsbericht** (`meta.healthOnly`): `body[data-mode="health"]`; in der Kopfleiste `#reportKind` mit `meta.reportKind` vor dem Servernamen, als Zeitangabe der Lesezeitpunkt. Die geführte Ansicht zeigt `#healthRow`, die Bereichsansicht und `#beforeG`; Band, Hinweise, Zeitleiste, Karten, weitere Vorfälle, `#measured` und `#qualityG` gibt es nicht. Die Expertenansicht zeigt nur `#xtabs` mit den Reitern `print`, `before`, `health` (in dieser Reihenfolge, `health` gewählt); Zeitraumleiste, Vorfallsspalte, Kacheln und Diagramme gibt es nicht. Die Seite prüft `meta.healthOnly`, bevor sie ein Feld der Messung liest. Der Rückblick bezieht sich im Zustandsbericht auf das Lesen: seine Überschrift heißt in der geführten Ansicht „Rückblick – die Tage vor dem Lesen" und im Reiter `before` „Vor dem Lesen", jeder Satz, den die Seite selbst über den Rückblick und die Treiberliste bildet, sagt „vor dem Lesen", wo der Bericht einer Messung „vor der Messung" oder „während der Messung" sagt (diese Sätze stehen seit dem Plan Ereignisse in der Seite; Task 20 nennt sie einzeln und gibt ihnen dort eine zweite Fassung), und ein Rückblick ohne Vorfall zeigt keine leere Vorfallsliste (kein „keine"). Über den Zählungen je Tag steht in `#beforeG` der Satz `.before-reach` mit `health.eventsReachText`: ab wann die Ereignisprotokolle reichen (auf einem nicht persistenten Worker nur bis zum letzten Start). Texte, die aus den Daten kommen, bleiben, wie sie sind: die Schritte der Anleitung eines Rückblick-Vorfalls (`guide` aus `src/guidance.de.json`, in der Vorfallsansicht unter `.iv-todo`; ihr Feld `sign` sagt „… auch während der Messung") und `skip.text.Rueckblick` aus `src/texts.de.json` (Offene Punkte 9).

---

### Task 18: Seite – Zeile „Zustand des Workers", Bereichsansicht, Kopf

**Files:**
- Modify: `src/report-template.html`, `tests/report-browser.js`
- Nicht anfassen: `src/New-WorkerPerfReport.ps1`, `src/WorkerPerf.Health.ps1` (die Seite rendert nur).

**Interfaces:**
- Consumes: Berichtsdaten aus Task 16; die Gestaltung oben; aus dem geführten Bericht `#hints`, `#timeline`, `#band`, `#anonSwitch`, `copyText`, die Adresse (`v`, `i`, `t0`, `t1`), `WP.openIncident`, `WP.closeIncident`, `open`, `patched`, `ok` in `tests/report-browser.js`.
- Produces: `#healthInfo`, `#healthRow` mit `#healthSummary`, `#healthEnv` und `.htile`, `#area` mit `.av-intro`, `.av-apps`, `.hcheck`, `#areaCopy`, `#areaBack`; `WP.openArea(id, checkId)`, `WP.closeArea()`; Adressteil `a=<Bereich>` (`history.pushState` beim Öffnen und Schließen, `popstate` stellt wieder her; `i` und `a` schließen einander aus). Ein Bericht ohne Feld `health` (ältere Berichtsdaten) verhält sich wie `state` `notRecorded` ohne Text.

- [ ] **Step 1: Die fehlschlagenden Prüfungen schreiben** (neue Funktion `checkHealth`, in der Schleife nach `checkGuided` aufrufen)

```js
async function checkHealth(browser, dir, scheme) {
  const ctx = await browser.newContext({ viewport: { width: 1400, height: 900 }, colorScheme: scheme });
  await ctx.addInitScript(() => { window.__copied = []; Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: (t) => { window.__copied.push(t); return Promise.resolve(); } } }); });
  const page = await ctx.newPage(); page.errors = []; page.on('pageerror', (e) => page.errors.push(e.message));
  await page.goto('file://' + path.join(dir, 'report.html'));
  const D = await page.evaluate(() => JSON.parse(document.getElementById('wp-data').textContent)), H = D.health;
  ok(await page.evaluate(() => { const r = document.querySelector('#healthRow'), h = document.querySelector('#hints'), t = document.querySelector('#timeline');
    return !!r && (!h || !!(h.compareDocumentPosition(r) & 4)) && !!(r.compareDocumentPosition(t) & 4); }), 'Zeile Zustand des Workers zwischen Hinweisen und Zeitleiste');
  ok((await page.locator('#healthRow').innerText()).includes(H.title) && (await page.locator('#healthSummary').innerText()) === H.summary.text, 'Ueberschrift und Zusammenfassung');
  const tiles = page.locator('#healthRow .htile');
  ok(await tiles.count() === 11 && JSON.stringify(await tiles.evaluateAll((e) => e.map((x) => x.dataset.area))) === JSON.stringify(H.areas.map((a) => a.id)), 'elf Kacheln in fester Reihenfolge');
  ok((await page.locator('#healthEnv').innerText()) === H.environmentText, 'die Zeile nennt die angenommene Zielumgebung');
  for (const a of H.areas) {
    const t = page.locator(`#healthRow .htile[data-area="${a.id}"]`), g = H.grades[a.grade];
    ok(await t.getAttribute('data-grade') === a.grade && (await t.locator('.status').innerText()).includes(g.symbol) && (await t.locator('.status').innerText()).includes(g.word) && (await t.innerText()).includes(a.label) && (await t.innerText()).includes(a.countsText), 'Kachel ' + a.id + ' mit Symbol, Wort und der Zeile der Zahlen');
  }
  const info = await page.locator('#healthInfo').innerText();
  ok(info.includes(H.headline) && info.includes(H.unknownText), 'Kopf nennt Lesezeitpunkt, Dauer und die nicht pruefbaren Pruefungen');
  const prof = H.areas.find((a) => a.id === 'profile'), c0 = prof.checks[0], av = page.locator('#area');
  await page.click('#healthRow .htile[data-area="profile"]');
  ok(await av.isVisible() && await av.getAttribute('data-area') === 'profile' && !(await page.locator('#band').isVisible()) && !(await page.locator('#healthRow').isVisible()), 'Bereichsansicht ersetzt die Startseite');
  ok(JSON.stringify(await av.locator('.hcheck').evaluateAll((e) => e.map((x) => x.dataset.check))) === JSON.stringify(prof.checks.map((c) => c.id)), 'Pruefungen des Bereichs, auffaellige zuerst');
  const el = av.locator(`.hcheck[data-check="${c0.id}"]`);
  ok(await el.getAttribute('data-grade') === 'act' && (await el.locator('.hc-title .status').innerText()).includes(H.grades.act.word), 'Einstufung als Symbol und Wort');
  ok((await el.locator('.hc-finding').innerText()).includes(c0.finding) && (await el.locator('.hc-meaning').innerText()).includes(c0.meaning), 'Befund und Bedeutung');
  const src = await el.locator('.hc-source').innerText();
  ok(await el.locator('.hc-todo li').count() === c0.todo.length && src.includes(c0.source.title) && src.includes(c0.kindLabel) && src.includes(c0.source.vendor), 'Vorgehen und Quelle mit Art');
  ok((await page.evaluate(() => location.hash)).includes('a=profile'), 'Adresse haelt den Bereich');
  await el.locator('.hc-copy').click();
  ok(await page.evaluate(() => window.__copied.at(-1)) === c0.copy.named, 'Pruefung kopieren');
  await page.keyboard.press('Escape');
  ok(!(await av.isVisible()) && await page.locator('#band').isVisible(), 'Esc schliesst die Bereichsansicht');
  await page.check('#anonSwitch'); await page.click('#healthRow .htile[data-area="profile"]'); await page.click('#areaCopy');
  ok(await page.evaluate(() => window.__copied.at(-1)) === prof.copy.anonymous, 'Bereich kopieren ohne Namen');
  await page.goBack();
  ok(!(await av.isVisible()), 'Zurueck schliesst die Bereichsansicht');
  await page.click('#healthRow .htile[data-area="security"]');
  const sec = H.areas.find((a) => a.id === 'security'), unk = sec.checks.find((c) => c.grade === 'unknown');
  ok((await av.locator(`.hcheck[data-check="${unk.id}"] .hc-finding`).innerText()).includes(unk.why) && (await av.locator(`.hcheck[data-check="${unk.id}"] .status`).first().innerText()).includes(H.grades.unknown.word), 'nicht pruefbar nennt den Grund');   // Review Focus 1
  ok((await av.locator('.area-notcovered').innerText()).includes(sec.notCovered), 'der Bereich sagt, was er nicht abdeckt');
  ok(sec.statusText.length > 0 && (await av.locator('.av-status').innerText()).includes(sec.statusText), 'ein teilweise gelesener Bereich sagt es mit dem Satz aus den Daten');
  await page.keyboard.press('Escape'); await page.click('#healthRow .htile[data-area="apps"]');
  const apps = H.areas.find((a) => a.id === 'apps');
  ok(JSON.stringify(await av.locator('.av-apps .av-app').evaluateAll((e) => e.map((x) => x.dataset.app + ':' + x.dataset.state))) === JSON.stringify(apps.apps.map((x) => x.key + ':' + x.state)) && (await av.locator('.av-apps').innerText()).includes(apps.apps[0].text), 'Bereich Anwendungen nennt jede Anwendung mit ihrem Zustand');
  await page.keyboard.press('Escape'); await page.click('#healthRow .htile[data-area="events"]');
  ok((await av.locator('.av-intro').innerText()).includes(H.eventsReachText) && await page.locator('#area .av-apps').count() === 0, 'Ereignisbild sagt, ab wann die Protokolle reichen');
  ok(page.errors.length === 0, 'Skriptfehler: ' + page.errors.join(' | '));
  await ctx.close();
  const b = await browser.newPage({ colorScheme: scheme }); b.errors = []; b.on('pageerror', (e) => b.errors.push(e.message));
  await b.goto('file://' + path.join(dir, 'report.html') + '#v=guided&a=print');
  ok(await b.locator('#area').getAttribute('data-area') === 'print', 'Lesezeichen oeffnet den Bereich');
  await b.goto('file://' + path.join(dir, 'report.html') + '#v=guided&a=wetter'); await b.reload();
  ok(await b.locator('#band').isVisible() && !(await b.locator('#area').isVisible()) && b.errors.length === 0, 'unbekannter Bereich im Lesezeichen');
  await b.close();
  const old = await open(browser, patched(dir, 'report.html', 'report-nohealth.html', (J) => { J.health = { state: 'notRecorded', title: J.health.title, text: 'Zustandsbild nicht erfasst.' }; for (const i of J.incidents) i.health = []; }), scheme);   // Review Focus 2
  ok((await old.page.locator('#healthRow').innerText()).includes('Zustandsbild nicht erfasst.') && await old.page.locator('#healthRow .htile').count() === 0, 'alte Aufzeichnung: nicht erfasst, keine Kacheln');
  ok(await old.page.locator('.notmeasured[data-place="health"]').count() === 0 && (await old.page.locator('#healthInfo').innerText()).includes('Zustandsbild nicht erfasst.') && old.page.errors.length === 0, 'alte Aufzeichnung: nicht als weggelassen gemeldet');
  await old.page.close();
  const none = await open(browser, patched(dir, 'report.html', 'report-healthless.html', (J) => { delete J.health; for (const i of J.incidents) delete i.health; }), scheme);
  ok(await none.page.locator('#healthRow .htile').count() === 0 && none.page.errors.length === 0, 'Berichtsdaten ohne das Feld: kein Skriptfehler');
  await none.page.close();
  const na = await open(browser, patched(dir, 'report.html', 'report-health-na.html', (J) => { const a = J.health.areas.find((x) => x.id === 'apps'), c = a.checks[a.checks.length - 1];
    c.grade = 'na'; c.why = 'Sim-Fachanwendung ist nicht installiert'; c.finding = 'Trifft nicht zu: Sim-Fachanwendung ist nicht installiert.';
    a.apps.push({ key: 'simapp', label: 'Sim-Fachanwendung', state: 'notInstalled', text: 'Sim-Fachanwendung: nicht installiert' }); }), scheme);   // Review Focus 3
  const naArea = na.D.health.areas.find((x) => x.id === 'apps'), naTile = na.page.locator('#healthRow .htile[data-area="apps"]');
  ok(await naTile.getAttribute('data-grade') === naArea.grade && (await naTile.innerText()).includes(naArea.countsText) && !(await naTile.innerText()).includes(na.D.health.grades.na.word), 'trifft nicht zu: aendert weder Einstufung noch Zahlen der Kachel');
  await naTile.click();
  const last = na.page.locator('#area .hcheck').last();
  ok(await last.getAttribute('data-grade') === 'na' && (await last.locator('.status').first().innerText()).includes(na.D.health.grades.na.word) && (await last.innerText()).includes('Sim-Fachanwendung ist nicht installiert'), 'trifft nicht zu: unter den eingestuften Pruefungen, mit Wort und Grund');
  ok((await na.page.locator('#area .av-app[data-app="simapp"]').innerText()).includes('nicht installiert') && await na.page.locator('#area .av-app[data-app="simapp"]').getAttribute('data-state') === 'notInstalled' && na.page.errors.length === 0, 'eine nicht installierte Anwendung steht im Bereich');
  await na.page.close();
  const ch = await open(browser, patched(dir, 'report.html', 'report-health-changed.html', (J) => { J.health.changedText = 'Schwellen weichen vom ausgelieferten Stand ab: Freier Platz 25 GB (ausgeliefert 10 GB)'; }), scheme);
  ok((await ch.page.locator('#healthInfo').innerText()).includes('Schwellen weichen vom ausgelieferten Stand ab'), 'Kopf vermerkt geaenderte Schwellen');
  await ch.page.close();
  const m = await open(browser, path.join(dir, 'report-masked.html'), scheme);
  await m.page.click('#healthRow .htile[data-area="profile"]');
  ok(!/user0\d\d|SIM-VDA01|CONTOSO|fs01/.test(await m.page.locator('#area').innerText()) && await m.page.locator('#anonSwitch').count() === 0 && await m.page.locator('#area .hc-copy').count() > 0, 'maskiert: keine Namen in der Bereichsansicht');   // Review Focus 4
  await m.page.close();
  for (const hash of ['', '#v=guided&a=security']) {
    const n = await browser.newPage({ viewport: { width: 400, height: 800 }, colorScheme: scheme }); await n.goto('file://' + path.join(dir, 'report.html') + hash);
    ok(await n.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), 'schmale Breite ohne seitliches Scrollen: Zustandsbild ' + hash);
    await n.close();
  }
}
```

- [ ] **Step 2: Prüfung ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/New-TestReports.ps1 -OutDir <workspace>/scratch/wp-reports && node tests/report-browser.js <workspace>/scratch/wp-reports`
Expected: `AssertionError: Zeile Zustand des Workers zwischen Hinweisen und Zeitleiste`

- [ ] **Step 3: Kopfhinweis, Zeile, Kacheln, Bereichsansicht, Adresse und Kopieren nach der Gestaltung bauen**

- [ ] **Step 4: Prüfungen ausführen**

Run: wie Step 2 und `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `browser checks passed: <n>`, `Failed: 0`

- [ ] **Step 5: Seite ansehen** – Bildschirmfotos unter `<workspace>/scratch`: Startseite bei 1400 × 900 (Band, Zeile und erster Knopf ohne Scrollen sichtbar), Bereichsansicht „Profilverwaltung" und „Sicherheitsprodukte", Bereichsansicht „Anwendungen" mit einer nicht installierten Anwendung (`report-health-na.html`), Startseite bei 400 px; Mängel beheben, Step 4 wiederholen.

- [ ] **Step 6: Commit**

```bash
git add src/report-template.html tests/report-browser.js
git commit -m "Show the health picture as a row of area tiles with an area view"
```

---

### Task 19: Seite – Verweis im Vorfall und Reiter der Expertenansicht

**Files:**
- Modify: `src/report-template.html`, `tests/report-browser.js`
- Nicht anfassen: `src/New-WorkerPerfReport.ps1`, `src/WorkerPerf.Health.ps1`; `src/WorkerPerf.Common.ps1` und die Stelle `health` der Kategorie (Task 20).

**Interfaces:**
- Consumes: Task 18; Berichtsdaten aus Task 16; aus dem geführten Bericht `#incident` mit seinen Abschnitten, `#xtabs`, `showExpert`, `WP.openIncident`, `WP.setZoom`.
- Produces: `section.iv-health` nach der Gestaltung; `#xtabs button[data-tab=health]` mit `#xt-health`, `#healthNote`, `#hfGrade`, `#hfArea`, `#tHealth`, `details#healthRaw`, `#tHealthRaw`.

Umstellung bestehender Prüfungen (jede Aussage bleibt, nur ihr Wert ändert sich):
- `'Abschnitte in fester Reihenfolge'` (`checkIncidentView`, Vorfall `cpu`): die Reihenfolge ist `iv-what`, `iv-cause`, `iv-todo`, `iv-health`, `iv-affected`, `iv-evidence`, weil der CPU-Vorfall der simulierten Stunde auf `maintenance.tasksInWorkHours` verweist.
- Die Zahl der Reiter in `#xtabs` ist neun statt acht.

- [ ] **Step 1: Die fehlschlagenden Prüfungen schreiben** (neue Funktion `checkHealthLinks`, in der Schleife nach `checkHealth`; die Umstellungen oben im selben Schritt)

```js
async function checkHealthLinks(browser, dir, scheme) {
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme);
  const pr = D.incidents.find((i) => i.type === 'ereignis' && i.event.kind === 'print');
  await page.evaluate((id) => window.WP.openIncident(id), pr.id);
  const sec = page.locator('#incident .iv-health');
  ok(await sec.isVisible() && (await sec.innerText()).includes('Dazu im Zustandsbild') && (await sec.innerText()).includes(D.health.incidentNote), 'Abschnitt Dazu im Zustandsbild');
  ok(JSON.stringify(await sec.locator('.ivh-item').evaluateAll((e) => e.map((x) => x.dataset.check))) === JSON.stringify(pr.health) && pr.health.includes('print.driversInSpooler'), 'Treiberpruefung beim Absturz des Druckdienstes');
  const order = await page.locator('#incident').locator('section, details').evaluateAll((els) => els.map((e) => e.className.split(' ').find((c) => c.startsWith('iv-'))));
  ok(JSON.stringify(order.filter(Boolean)) === JSON.stringify(['iv-what', 'iv-cause', 'iv-todo', 'iv-health', 'iv-affected', 'iv-evidence']), 'Abschnitt steht nach Was ist zu tun');
  ok(!/ist die Ursache|verursacht/.test(await sec.innerText()) && (await sec.locator('.ivh-item .status').first().innerText()).includes(D.health.grades.act.word), 'Formulierung kann beitragen, Einstufung als Symbol und Wort');
  await sec.locator('.ivh-item .ivh-open').first().click();
  ok(await page.locator('#area').getAttribute('data-area') === 'print' && await page.locator('#area .hcheck[data-check="print.driversInSpooler"]').isVisible(), 'Verweis oeffnet die Pruefung im Bereich');
  const mem = D.incidents.find((i) => i.lead === 'memory');
  await page.evaluate((id) => window.WP.openIncident(id), mem.id);
  ok(await page.locator('#incident .iv-health').count() === 0, 'passt keine Pruefung, entfaellt der Abschnitt');
  await showExpert(page);
  ok(await page.locator('#xtabs button[data-tab]').count() === 9, 'neun Reiter');
  await page.click('#xtabs button[data-tab=health]');
  const all = D.health.areas.flatMap((a) => a.checks);
  ok(await page.locator('#tHealth tbody tr').count() === all.length && (await page.locator('#healthNote').innerText()).includes(D.health.headline), 'Tabelle aller Pruefungen mit dem Lesezeitpunkt');
  const row = await page.locator('#tHealth tbody tr[data-check="profile.containerFull"]').innerText(), cf = all.find((c) => c.id === 'profile.containerFull');
  ok(row.includes(cf.title) && row.includes(cf.value) && row.includes(D.health.grades.act.word) && row.includes(cf.kindLabel) && row.includes(cf.source.title), 'Zeile mit Bereich, Pruefung, Wert, Einstufung, Art, Quelle');
  await page.selectOption('#hfGrade', 'act');
  ok(await page.locator('#tHealth tbody tr').count() === all.filter((c) => c.grade === 'act').length, 'Filter nach Einstufung');
  await page.selectOption('#hfGrade', 'na');
  ok(await page.locator('#tHealth tbody tr').count() === all.filter((c) => c.grade === 'na').length && await page.locator('#hfGrade option').count() === 6, 'Filter kennt auch trifft nicht zu');
  await page.selectOption('#hfGrade', ''); await page.selectOption('#hfArea', 'print');
  ok(await page.locator('#tHealth tbody tr').count() === D.health.areas.find((a) => a.id === 'print').checks.length, 'Filter nach Bereich');
  await page.selectOption('#hfArea', '');
  const cpu = D.incidents.find((i) => i.lead === 'cpu');
  await page.evaluate(([a, b]) => window.WP.setZoom(a, b), [cpu.start, cpu.end]);
  ok(await page.locator('#tHealth tbody tr').count() === all.length, 'der Zeitraum wirkt nicht auf das Zustandsbild');
  await page.click('#healthRaw summary');
  ok(await page.locator('#tHealthRaw tbody tr').count() >= D.health.raw.length && (await page.locator('#tHealthRaw').innerText()).includes('Inventarlauf'), 'Rohwerte, auch ohne Pruefung im Katalog');
  const ws = D.health.raw.find((x) => x.id === 'maintenance.searchService');
  ok(ws.stateText.startsWith('nicht zutreffend') && (await page.locator('#tHealthRaw').innerText()).includes(ws.stateText), 'Rohwert eines nicht vorhandenen Produkts: nicht zutreffend');
  ok(page.errors.length === 0, 'Skriptfehler: ' + page.errors.join(' | '));
  await page.close();
  const m = await open(browser, path.join(dir, 'report-masked.html'), scheme);
  await showExpert(m.page); await m.page.click('#xtabs button[data-tab=health]'); await m.page.click('#healthRaw summary');
  ok(!/user0\d\d|SIM-VDA01|CONTOSO|ddc0\d|wem01|zeit01|office\$|Inventarlauf|fd00:20::10/.test(await m.page.locator('#xt-health').innerText()), 'maskiert: keine Namen und kein freier Text in den Rohwerten');   // Review Focus 4
  await m.page.close();
}
```

- [ ] **Step 2: Prüfung ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/New-TestReports.ps1 -OutDir <workspace>/scratch/wp-reports && node tests/report-browser.js <workspace>/scratch/wp-reports`
Expected: `AssertionError: Abschnitt Dazu im Zustandsbild`

- [ ] **Step 3: Abschnitt im Vorfall und Reiter `health` nach der Gestaltung bauen**

- [ ] **Step 4: Prüfungen ausführen**

Run: wie Step 2 und `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `browser checks passed: <n>`, `Failed: 0`

- [ ] **Step 5: Seite ansehen** – Vorfallsansicht des Absturzes des Druckdienstes, Reiter „Zustand" mit aufgeklappten Rohwerten in beiden Farbschemata; auf Tabellenbreite und überlange Rohwerte achten; Mängel beheben, Step 4 wiederholen.

- [ ] **Step 6: Commit**

```bash
git add src/report-template.html tests/report-browser.js
git commit -m "Link incidents to health checks and add the expert tab of the health picture"
```

---

### Task 20: Seite – Zustandsbericht und „nicht gemessen" bei `-Skip Zustand`

**Files:**
- Modify: `src/report-template.html`, `tests/report-browser.js`, `src/WorkerPerf.Common.ps1` (`Places` der Zeile `Zustand`), `tests/TestHelpers.ps1` (`New-SkipRuns`: `Alle` mit `Zustand`), `tests/Skip.Tests.ps1`, `tests/Common.Tests.ps1`
- Nicht anfassen: `src/New-WorkerPerfReport.ps1`, `src/WorkerPerf.Health.ps1`.

**Interfaces:**
- Consumes: Tasks 18 und 19; Berichtsdaten der Tasks 16 und 17; die Berichte `report-health.html`, `report-health-masked.html`, `report-skip-zustand.html`; aus dem geführten Bericht `showExpert`, `open`, `patched`, `checkSkip`, `SKIP_LOCATIONS`, `END_REASON`.
- Produces:
  - Zustandsbericht: `body[data-mode="health"]`, `#reportKind`; `END_REASON` erhält `healthonly` („Schnelllauf ohne Messung"); der Rückblick und die Treiberliste sprechen vom Lesen (Gestaltung). Eine zweite Fassung für `meta.healthOnly` bekommen genau diese Sätze der Seite, jeweils mit „vor dem Lesen" statt „vor der Messung": der Hinweis zu den Mustern eines Rückblick-Vorfalls („Für die Tage vor der Messung gelten nur die Muster, die keine Messwerte brauchen."), die Sätze des leeren, fehlenden oder nicht gelesenen Rückblicks („Für die Tage vor der Messung liegt keine Ereignisdatei vor …", „… wurden keine Ereignisse gelesen …", „In den gelesenen Protokollen stehen für … vor der Messung keine Ereignisse …", „Am Tag vor der Messung …", „In den … Tagen vor der Messung …"), die Überschrift „Vorfälle vor der Messung" (ihre Zeile „keine" entfällt im Zustandsbericht mit der leeren Liste), die zwei Sätze zur Beteiligung eines Treibers („nur aus den Vorfällen vor der Messung; …" und „nur aus den Vorfällen während der Messung; …": im Zustandsbericht steht nur „aus den Vorfällen vor dem Lesen") und der Zusatz „(vor der Messung)" bzw. „(während der Messung)" in der Spalte der Beteiligung. Die Tabelle der Warteschlangen und der Abschnitt „Ereignisprotokolle während der Messung" erscheinen im Zustandsbericht nicht. Kein Text aus `src/texts.de.json` oder `src/guidance.de.json` wird geändert.
  - Kategorie `Zustand`: `Places = @('health')`; die Seite zeigt den Hinweis `notMeasured('health')` in `#healthRow` und in `#xt-health`; `SKIP_LOCATIONS` erhält `health` mit diesen zwei Stellen in der Form, die die Tabelle seit Task 10 des geführten Berichts hat; `checkSkip` prüft zusätzlich `report-skip-zustand.html`; in `New-SkipRuns` wird `Zustand` der achte Eintrag von `$names` (die eigene Zeile für den Lauf `Zustand` aus Task 8 entfällt), der Lauf `Alle` lässt damit auch `Zustand` weg.

Umstellung bestehender Tests (jede Aussage bleibt, nur ihr Wert ändert sich):
- `tests/Skip.Tests.ps1`: `$Names` hat acht Einträge (mit `Zustand`), `$Places.Zustand = @('health')`; der Lauf `Alle` hat `Skip` = die acht Namen und keine `health.json`. `tests/Common.Tests.ps1`: `$WorkerPerfCategories.Zustand.Places | Should -Be @('health')`.

- [ ] **Step 1: Die fehlschlagenden Prüfungen schreiben** (neue Funktionen `checkHealthOnly` und `checkHealthSkip`, in der Schleife nach `checkHealthLinks`; die Umstellungen oben im selben Schritt)

```js
async function checkHealthOnly(browser, dir, scheme) {
  // sichtbarer Text der Seite ohne die Schritte der Anleitung eines Vorfalls (.iv-todo): sie kommen aus den Daten des gefuehrten Berichts, geprueft werden die Saetze der Seite
  const text = (p) => p.evaluate(() => { const steps = [...document.querySelectorAll('.iv-todo')], was = steps.map((e) => e.style.display); steps.forEach((e) => { e.style.display = 'none'; });
    const t = document.body.innerText; steps.forEach((e, i) => { e.style.display = was[i]; }); return t; });
  const { page, D } = await open(browser, path.join(dir, 'report-health.html'), scheme);
  ok(await page.evaluate(() => document.body.dataset.mode) === 'health' && (await page.locator('#reportKind').innerText()) === 'Zustandsbericht ohne Messung', 'Kopf: Zustandsbericht ohne Messung');
  ok(await page.locator('#healthRow .htile').count() === 11 && (await page.locator('#healthSummary').innerText()) === D.health.summary.text && await page.locator('#beforeG').isVisible(), 'Zeile und Rueckblick');
  ok((await page.locator('#beforeG .before-reach').innerText()).includes(D.health.eventsReachText), 'der Rueckblick sagt, ab wann die Protokolle reichen');
  for (const sel of ['#band', '#timeline', '#cards', '#more', '#measured', '#incList', '#tiles', '#rangeBar', '#chCpu', '#tSessions']) ok(!(await page.locator(sel).first().isVisible()), 'Zustandsbericht ohne ' + sel);
  ok(!/keine Vorf|Kein Vorfall|Keine Störung/i.test(await text(page)), 'nirgends keine Vorfaelle');   // Review Focus 5
  ok(!/vor der Messung|während der Messung/i.test(await text(page)) && /vor dem Lesen/i.test(await page.locator('#beforeG').innerText()), 'der Rueckblick spricht vom Lesen, nicht von einer Messung');
  await page.click('#healthRow .htile[data-area="profile"]');
  ok(await page.locator('#area .hcheck').count() === D.health.areas.find((a) => a.id === 'profile').checks.length, 'Bereichsansicht im Zustandsbericht');
  await page.keyboard.press('Escape');
  await showExpert(page);
  ok(JSON.stringify(await page.locator('#xtabs button[data-tab]').evaluateAll((e) => e.filter((x) => x.offsetParent !== null).map((x) => x.dataset.tab))) === JSON.stringify(['print', 'before', 'health']), 'Expertenansicht nur mit Drucken, Rueckblick und Zustand');
  ok(await page.locator('#tHealth tbody tr').count() === D.health.areas.flatMap((a) => a.checks).length, 'Tabelle der Pruefungen im Zustandsbericht');
  for (const tab of ['print', 'before']) {
    await page.click(`#xtabs button[data-tab=${tab}]`);
    ok(!/keine Vorf|Kein Vorfall|Keine Störung|vor der Messung|während der Messung/i.test(await text(page)), 'Expertenansicht, Reiter ' + tab + ': weder keine Vorfaelle noch Messung');
  }
  ok(page.errors.length === 0, 'Skriptfehler: ' + page.errors.join(' | '));
  await page.close();
  // ein Rueckblick ohne Ereignisse: sein Satz steht da, aber weder "keine Vorfaelle" noch "vor der Messung"
  const empty = await open(browser, patched(dir, 'report-health.html', 'report-health-empty.html', (J) => { J.before.incidents = []; J.before.near = []; J.before.perDay = []; J.before.eventCount = 0; J.before.incidentEventCount = 0; }), scheme);
  ok(await empty.page.locator('#beforeG').isVisible() && !/keine Vorf|Kein Vorfall|Keine Störung|vor der Messung/i.test(await text(empty.page)) && empty.page.errors.length === 0, 'leerer Rueckblick im Zustandsbericht');   // Review Focus 5
  await showExpert(empty.page); await empty.page.click('#xtabs button[data-tab=before]');
  ok(!/keine Vorf|Kein Vorfall|Keine Störung|vor der Messung/i.test(await text(empty.page)) && /vor dem Lesen/i.test(await text(empty.page)), 'leerer Rueckblick in der Expertenansicht');
  await empty.page.close();
  const m = await open(browser, path.join(dir, 'report-health-masked.html'), scheme);
  ok(!/user0\d\d|SIM-VDA01|CONTOSO/.test(await text(m.page)) && m.page.errors.length === 0, 'maskierter Zustandsbericht ohne Namen');
  await m.page.close();
  const n = await browser.newPage({ viewport: { width: 400, height: 800 }, colorScheme: scheme }); await n.goto('file://' + path.join(dir, 'report-health.html'));
  ok(await n.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), 'Zustandsbericht bei schmaler Breite ohne seitliches Scrollen');
  await n.close();
}
async function checkHealthSkip(browser, dir, scheme) {
  const s = await open(browser, path.join(dir, 'report-skip-zustand.html'), scheme);
  ok(await s.page.locator('#healthRow .notmeasured[data-place="health"]').count() === 1 && await s.page.locator('#healthRow .htile').count() === 0 && await s.page.locator('#healthInfo').count() === 0, '-Skip Zustand: nicht gemessen statt Kacheln');
  ok((await s.page.locator('#healthRow').innerText()).includes(s.D.skipped[0].text + ' (-Skip Zustand)'), '-Skip Zustand: Grund steht da');
  await showExpert(s.page); await s.page.click('#xtabs button[data-tab=health]');
  ok(await s.page.locator('#xt-health .notmeasured[data-place="health"]').count() === 1 && await s.page.locator('#tHealth tbody tr').count() === 0 && s.page.errors.length === 0, '-Skip Zustand: der Reiter nennt nicht gemessen');
  await s.page.close();
}
```

- [ ] **Step 2: Prüfung ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/New-TestReports.ps1 -OutDir <workspace>/scratch/wp-reports && node tests/report-browser.js <workspace>/scratch/wp-reports`
Expected: `AssertionError: Kopf: Zustandsbericht ohne Messung`

- [ ] **Step 3: Zustandsbericht und die Stelle `health` nach der Gestaltung bauen; `Places`, `New-SkipRuns`, `SKIP_LOCATIONS`, `checkSkip` und die genannten Tests anpassen**

- [ ] **Step 4: Prüfungen ausführen**

Run: wie Step 2 und `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `browser checks passed: <n>`, `Failed: 0`

- [ ] **Step 5: Seite ansehen** – Zustandsbericht in beiden Ansichten und bei 400 px, mit und ohne Vorfälle im Rückblick; Bericht mit `-Skip Zustand`; Mängel beheben, Step 4 wiederholen.

- [ ] **Step 6: Commit**

```bash
git add src/report-template.html tests/report-browser.js src/WorkerPerf.Common.ps1 tests/TestHelpers.ps1 tests/Skip.Tests.ps1 tests/Common.Tests.ps1
git commit -m "Show the health-only report and mark a skipped health picture as not measured"
```

---

## Teil D – Abschluss (Tasks 21–22)

### Task 21: README, Hilfe und Demo-Seite

**Files:**
- Modify: `README.md`, `pages/index.html`, `src/New-WorkerPerfReport.ps1` (nur die Hilfe), `src/Start-WorkerPerfCapture.ps1` (nur die Hilfe)
- Nicht anfassen: der Code beider Skripte.

**Interfaces:**
- Consumes: der fertige Baustein.
- Produces: README mit einem Abschnitt „Zustandsbild": was es liest (die elf Bereiche, je ein Satz) und was nicht (Entwurf 3.4, auch: nichts je Benutzer); die angenommene Zielumgebung (nicht persistent, MCS, Multi-Session) und was daraus folgt (Änderungen im Master-Image oder in der Richtlinie; Ereignisprotokolle reichen nur bis zum letzten Start); die Anwendungsliste `src/apps.json` (Aufbau, die fünf Lesearten, wie eine Anwendung ergänzt wird: Eintrag in der Liste und Prüfungen im Katalog, ohne Codeänderung; `-AppsFile` an beiden Skripten); die drei Arten einer Prüfung („Empfehlung des Herstellers", „Empfehlung aus der Praxis", „Faustregel"), die Ausnahme, in der nach Festlegung des Auftraggebers die Praxisquelle vor dem Hersteller gilt (Energiesparplan), und das Ergebnis „trifft nicht zu"; `-HealthOnly` mit Beispiel und der Liste der Parameter, die er ablehnt; `-Skip Zustand`; die vier Einstufungen und wann „handeln" entsteht; „nicht prüfbar" mit Grund und „Zustandsbild nicht erfasst" bei älteren Aufzeichnungen; der Katalog `src/health.de.json` mit `-HealthFile`, Schwellen und dem Vermerk geänderter Schwellen im Kopf; `docs/guidance/quellen.md`; Maskierung des Zustandsbilds; die Grenzen aus Entwurf 9, darunter: ein Produkt der Rollenliste ohne Dienst und ohne Filtertreiber (die Fachanwendung) erkennt das Zustandsbild nicht. Die Tabelle der Kategorien nennt `Zustand` ohne „(geplant)", und der Satz, `Zustand` wirke noch nicht, entfällt. Die Hilfe beider Skripte nennt `health.json`, `-HealthOnly`, `-HealthFile` und `-AppsFile`. Die Demo-Seite ist aus der Simulation neu erzeugt.

- [ ] **Step 1: Prüfen, dass README und Demo veraltet sind**

Run: `pwsh -NoProfile -Command "(Select-String -Path README.md -Pattern '(geplant)' -SimpleMatch -Quiet); (Select-String -Path pages/index.html -Pattern 'healthRow' -SimpleMatch -Quiet)"`
Expected: `True`, `False`

- [ ] **Step 2: README und die Hilfe schreiben**

- [ ] **Step 3: Demo neu erzeugen**

```powershell
$run = .\src\Start-WorkerPerfCapture.ps1 -Simulate -DurationMinutes 60 -OutputPath .\demo
.\src\New-WorkerPerfReport.ps1 -Path $run -OutFile .\pages\index.html
```

- [ ] **Step 4: Prüfen**

Run: Step 1 erneut, danach `pwsh -NoProfile -File tests/Invoke-Tests.ps1` und die Browserprüfungen
Expected: `False`, `True`, `Failed: 0`, `browser checks passed: <n>`

- [ ] **Step 5: Commit**

```bash
git add README.md pages/index.html src/New-WorkerPerfReport.ps1 src/Start-WorkerPerfCapture.ps1
git commit -m "Describe the health picture and the quick run, rebuild the demo page"
```

---

### Task 22: Erster echter Lauf auf dem Test-Worker und Anpassungsrunde

Diese Task ist der Schritt des Auftraggebers (Entwurf 8). Sie hat keinen Test vorab: ihr Ergebnis sind Befunde vom Test-Worker, aus denen genau eine Anpassungsrunde mit eigenen Tests entsteht. Nichts von dem, was der Lauf liefert, kommt in das Repository.

**Files:**
- Modify (Anpassungsrunde, je nach Befund): `src/apps.json`, `src/WorkerPerf.Sources.Windows.ps1`, `tests/WindowsStandIns.ps1`, `tests/WindowsHealth.Tests.ps1`, `src/WorkerPerf.Common.ps1` (Werteliste), `src/WorkerPerf.Load.ps1` (nur bei einer neuen Formatnummer), `src/WorkerPerf.Health.ps1`, `src/health.de.json`, `docs/guidance/quellen.md`, `tests/Load.Tests.ps1`, `tests/Health.Tests.ps1`
- Nicht anfassen: das Ergebnis des Laufs bleibt außerhalb des Repositorys; in Tests und Platzhalter kommen nur erfundene Werte in der Form der beobachteten.

- [ ] **Step 1: Schnelllauf auf dem Test-Worker** (Auftraggeber, in einer neuen administrativen Konsole: eine Konsole, in der schon eine ältere Fassung lief, kennt die neuen Felder der Sitzungsabfrage nicht)

```powershell
.\Start-WorkerPerfCapture.ps1 -HealthOnly -OutputPath D:\WorkerPerf
```

Festhalten: die Konsolenzeile `Zustandsbild: …` (Bereiche, Sekunden) und ob eine Warnung erscheint.

- [ ] **Step 2: Zustandsbericht erzeugen und das Ergebnis übergeben** (Auftraggeber) – `.\New-WorkerPerfReport.ps1 -Path <Ordner>`; der Ordner der Aufzeichnung wird in die Sitzung hochgeladen, nicht in das Repository.

- [ ] **Step 3: Auswerten** – je Bereich `Status`, `DurationMs` und `Error` aus `health.json`; je Wert der Liste Zustand und Grund. Die Fragen, die der Lauf beantwortet:

| Frage | Woran abzulesen |
|---|---|
| Bleibt das Lesen unter einer Minute, auch mit vielen Containern und Aufgaben? | `DurationMs` gesamt und je Bereich (`profile`, `maintenance`, `sessions`) |
| Lässt sich `Win32_TSSessionSetting` lokal ohne Packet Privacy lesen? | `sessions.limits` (`read` oder `unreadable`/`rights`) |
| Wo liegen die Citrix-Richtlinien, und wie heißen die Werte der Zeitgeber und der Druckrichtlinien? Tragen Schlüssel- oder Wertnamen Namen des Auftraggebers (dann werden `Key` und `Name` freier Servertext)? | `vda.policyRaw` |
| Wo liegen die Werte der Profilverwaltung (Wurzel oder Unterschlüssel), und welcher Zweig ist gefüllt? | `profile.policyGpo`, `profile.policyStudio` |
| Liefert `MSFT_Disk.Location` den Pfad des Containers, und stimmen Größe und Belegung? | `profile.containers` |
| Trifft das Muster des VDA-Eintrags, und wie heißen die Citrix-Dienste wirklich? | `vda.version`, `vda.services`, `vda.desktopService` |
| Sind die Defender-Klassen lesbar, und zeigt Defender die Ausschlüsse? | `security.defender*` |
| Liefert `FilterFindFirst` die Filter, und welche Produkte der Rollenliste haben welchen Filter? | `security.filters` |
| Stimmen die AppLocker-Zahlen aus `SrpV2` mit der Richtlinie überein (dann kann die Prüfung auf DLL-Regeln folgen)? | `security.applockerCollections` |
| Heißt der Dienst der VMware Tools `VMTools`, stimmt die Version aus dem Uninstall-Eintrag, und heißt der Treiberdienst des Ballon-Treibers `vmmemctl`? Melden sich Netzwerk- und Speicheradapter mit den erwarteten Namen (`vmxnet3`, `pvscsi`, `LSI_…`)? | `size.vmtools*`, `size.balloonDriver`, `size.netAdapters`, `size.storageControllers` |
| Ist die Klasse für RSS lokal lesbar, und trägt `InterfaceDescription` den Adaptertyp? | `network.rss` |
| Was trägt `PersistentDataLocation` auf einem über MCS bereitgestellten Worker (dann kann daraus ein Fakt zur Bereitstellung werden)? | `vda.persistentDataLocation` |
| Tragen die WEM-Dienste die dokumentierten Anzeigenamen, wo liegt der Agent-Cache, und welche Werte stehen unter `…\Norskale\Agent Host`? | `vda.wem*` |
| Reichen die Protokolle nur bis zum letzten Start, und bringt das Abbild ältere Einträge mit? | `events.logs` (`Oldest`) gegen `operation.lastBoot`; Prüfung `events.sinceBoot` |
| Läuft der Citrix-Druckdienst, obwohl PrinTaurus SmartSpread die Drucker zuordnet, und welche Werte der Citrix-Druckrichtlinien stehen in den Rohwerten (dann kann `print.citrixMapping` genau werden)? | `print.citrixPrintService`, `vda.policyRaw` |
| Heißt der Uninstall-Eintrag des SmartSpread Client so, wie das Muster erwartet, und trägt `DisplayVersion` die Zählung der Releases (6.x)? | `print.mappingClientVersion` (`absent`/`notInstalled`, obwohl der Client installiert ist; oder eine Zahl, die nicht zur Release-Zählung passt) |
| Lässt sich der Ordner `WindowsApps` als Administrator aufzählen, sodass Teams erkannt wird? Stimmen die Orte der Proben von Edge, Office und Teams, und welche stehen als „nicht gesetzt" da, obwohl die Einstellung gesetzt ist? | `apps.probes` (Zeilen `installed` und alle Zeilen mit `absent`) |
| Tragen die nicht dokumentierten Werte von Office (`VersionToReport`, `Platform`, `UpdatesEnabled`) und der Dienst `edgeupdate` das Erwartete (dann können ihre Prüfungen folgen)? | `apps.office.*`, `apps.edge.updateService` |
| Meldet `Get-WinEvent -ListLog` ein fehlendes Protokoll mit der Kennung `NoMatchingLogsFound`? | `events.logs` (`Present`), `print.operationalLog` |
| In welcher Form liefert `Win32_QuickFixEngineering` das Installationsdatum? | `operation.lastUpdate` (`absent`, obwohl Updates installiert sind) |
| Sieht ein Administrator die SMB-Verbindungen aller Sitzungen, und gibt es die Eigenschaft `Signed`? | `network.smbConnections` gegen die Freigaben der Messung |
| Sind die Merker für einen ausstehenden Neustart plausibel (dann zählen Komponentenwartung und Windows Update in der Prüfung mit)? | `operation.pending*` |
| Welche Prüfungen sind „nicht prüfbar", und aus welchem Grund? | Zustandsbericht, Kopf und Bereichsansichten |

- [ ] **Step 4: Anpassungsrunde** – für jeden Befund, der einen Leseweg oder eine Prüfung ändert: zuerst der fehlschlagende Test (Platzhalter mit erfundenen Werten in der beobachteten Form), dann die Änderung; Prüfungen aus dem Abschnitt „Nach dem ersten echten Lauf", deren Quelle der Lauf bestätigt hat, kommen mit Quelle in den Katalog und in `docs/guidance/quellen.md`. Ändert sich die Bedeutung eines gespeicherten Werts, bekommt das Format die Nummer 2; `Read-WorkerPerfHealthFile` liest dann beide Nummern (ein Wert, dessen Bedeutung sich geändert hat, wird aus einer Datei der Nummer 1 als `unreadable`/`error` übernommen), mit einem Test, der eine Datei der Nummer 1 liest: die Aufzeichnungen des ersten echten Laufs bleiben auswertbar (Entwurf 3.1).

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1` und die Browserprüfungen
Expected: `Failed: 0`, `browser checks passed: <n>`

- [ ] **Step 5: Commit**

```bash
git add src/apps.json src/WorkerPerf.Sources.Windows.ps1 src/WorkerPerf.Common.ps1 src/WorkerPerf.Load.ps1 src/WorkerPerf.Health.ps1 src/health.de.json docs/guidance/quellen.md tests/WindowsStandIns.ps1 tests/WindowsHealth.Tests.ps1 tests/Load.Tests.ps1 tests/Health.Tests.ps1    # nur die Dateien, die die Runde geändert hat
git commit -m "Adjust health reads and catalogue to the first run on a worker"
```

- [ ] **Step 6: Abnahme** – der Auftraggeber wiederholt den Schnelllauf, liest den Zustandsbericht und bestätigt die Durchsicht des Katalogs (Task 14c, Step 6). Erst damit gilt der Baustein als fertig.

---

## Nach dem ersten echten Lauf (nicht Teil der ersten Fassung)

Diese Werte und Prüfungen sind zurückgestellt, weil ihre lokale Lesequelle nicht dokumentiert oder nicht bestätigt ist. Die Bereichsansicht nennt sie unter „nicht abgedeckt"; der Katalog hat darauf keine Prüfung.

| Bereich | Zurückgestellt | Grund |
|---|---|---|
| Größe und Reserve | Ballon-, Auslagerungs-, Grenz- und Reservierungszähler der VMware Tools; Auslagerungsdatei gegen RAM minus Reservierung; CPU-Hot-Add und vNUMA; Prüfung „Dienst der VMware Tools läuft" | die Zählernamen stehen in keinem geöffneten VMware-Dokument; Hot-Add ist im Gast nicht lesbar; der Dienstname der VMware Tools ist nicht dokumentiert (der Wert wird als Rohwert aufgezeichnet) |
| Betrieb | Neustartmerker aus Komponentenwartung und Windows Update als Teil der Prüfung „ausstehender Neustart" | Lesequelle nicht dokumentiert (D1); beide Merker werden als Rohwerte aufgezeichnet |
| Sitzungen | Zeitlimits aus der Windows-Richtlinie in der Registrierung; Zeitgeber aus Citrix-Richtlinien; Prüfung „Zeitlimits an zwei Stellen gesetzt" | Richtlinienseite nicht geöffnet; Citrix-Wertnamen nicht dokumentiert |
| Citrix VDA | Transportart der Sitzungen; ob der VDA gerade registriert ist; Prüfungen auf Sitzungsrichtlinien; veraltete Richtlinienschlüssel; ein Fakt zur Art der Bereitstellung; vom WEM-Agenten die wirksame Konfiguration (CPU- und Speicheroptimierung), das Alter des Cache und seine Ereignisse; die Richtlinie „Virtual channel allow list" für Teams | keine dokumentierte lokale Quelle; Wertnamen nicht dokumentiert; was `PersistentDataLocation` auf einem MCS-Worker trägt, zeigt der Lauf; Format des Agent-Cache und Name seines Ereignisprotokolls nicht dokumentiert |
| Profilverwaltung | Prüfungen auf einzelne Einstellungen (lokale Profile löschen, Active Write Back, Streaming, Ausschlüsse, Protokollierung, Erweiterungsgrenze); Einstellungen an mehreren Orten; Art eines Containers | Lage der Werte nicht dokumentiert; Rohwerte werden aufgezeichnet. Die Empfehlungen von Stalhood dazu sind recherchiert und kommen mit der Anpassungsrunde als „Empfehlung aus der Praxis" |
| Drucken | Prüfungen auf Citrix-Druckrichtlinien (Universaltreiber, automatische Installation von Treibern, Warten auf Drucker), jede mit der Bedingung `print.citrixMapping`; die genaue Erkennung, ob Citrix-Richtlinien Drucker zuordnen; vom Zuordnungswerkzeug PrinTaurus SmartSpread alles außer der Version seines Clients (Ablauf und Dauer der Zuordnung bei der Anmeldung, Regeln, Konfiguration, Protokoll, Prozess je Sitzung) und die Voraussetzung .NET Framework 4.7.2; Prüfung „Universaltreiber vorhanden"; fremde Anschlussmonitore; Rückstau im Spool-Ordner | Wertnamen der Citrix-Richtlinien nicht dokumentiert; die öffentlichen Seiten des Herstellers AKI (Release Notes 6.2 und 6.4) beschreiben Ablauf, Ablageorte und Protokoll des Clients nicht, und seine Installationsanleitung ist nicht veröffentlicht: liegt sie als Datei vor, können Werte und Prüfungen der Art „Empfehlung des Herstellers" folgen; die .NET-Voraussetzung ist eine Frage an den Controller (Offene Punkte 6); `printdrivers.csv` hat kein Feld für die Treiberattribute |
| Sicherheitsprodukte | Prüfung auf DLL-Regeln von AppLocker; zu weit gefasste Ausschlüsse; Ausschlüsse für Auslagerungsdatei und Ereignisprotokolle; gemeinsame Signaturen für VDI; Zahl der Filtertreiber; Erkennen der Fachanwendung | Lesequelle `SrpV2` nicht dokumentiert (P3); kein Leistungsbezug bzw. Vorbehalte der Quelle; die Rollenliste nennt für die Fachanwendung keinen Dienst |
| Netz und Dateiserver | letzte erfolgreiche Zeitsynchronisation; periodischer Zeitabgleich der VMware Tools; SMB-Caches als Prüfung; RSS global | nur über ein Programm lesbar; Empfehlung gilt laut Quelle für Windows 10 und 11 |
| Ereignisbild | Größe der Protokolle als Prüfung; Ort der Protokolldateien gegen den beständigen Datenort | keine Herstellerzahl; ob ein Laufwerk einen Neustart übersteht, sagt kein dokumentierter lokaler Wert |
| Wartung in der Arbeitszeit | Fenster der automatischen Wartung; Suchdienst und Outlook-Suchindex der Profilverwaltung; Aufgaben des Edge-Updaters als Prüfung | Registrierungsort nicht dokumentiert; hängt an den Werten der Profilverwaltung; Aufgabennamen nicht dokumentiert |
| Anwendungen | automatische Updates von Office (Wert der Installation, Richtlinie); 32- oder 64-Bit-Office; Updatekanal von Office LTSC; Windows-Build und Updates für Teams; Prüfungen auf das klassische Teams und das Besprechungs-Add-in | die Werte sind nicht dokumentiert oder die Quelle gibt keine prüfbare Erwartung; die Rohwerte stehen in der Anwendungsliste (`documented: false`) und zeigen, was der Worker trägt |

## Self-Review

- **Spec coverage:** 1 (Ziel, Erfolgskriterien) → Tasks 8, 9, 11 (jede Prüfung mit Vorgehen und Quelle), 13, 14, 16; 2 (Bedienung) → Tasks 8, 9, 17, 21; 3.1 → Tasks 1a, 12, 22 (eine ältere Formatnummer bleibt lesbar); 3.2 (elf Bereiche) → Abschnitt „Werte, Fakten und Prüfungen je Bereich", Tasks 1–7; 3.2a (Anwendungsliste: fünf Lesearten, keine Befehle, nichts je Benutzer, Ablehnung beim Start, „nicht installiert", eine Datei für beide Bausteine, Erweiterung ohne Code) → Tasks 1b, 2, 7, 8, 11, 13 und die Tests mit der vierten Anwendung in den Tasks 7, 9, 14c, 17; 3.3 → Tasks 1a, 1b, 4 (Zustand je Wert, Zeitlimit, Dauer; eine gemeinsame Abfrage, die am Zeitlimit endet, trifft nur ihren Bereich), 5 bis 7 (Zeitlimit auch im wiederverwendeten Leser, im Aufruf ohne eigenes Zeitlimit und zwischen den Proben), 8 (vor dem ersten Takt); 3.4 → Global Constraints, Task 6 (Prüfung der Quelle auf verbotene und schreibende Aufrufe), Task 2 (kein `HKCU` in der Anwendungsliste), Zeilen „Nicht gelesen"; 3.5 → Tasks 1a, 3, 8, 10; 4.1 (drei Arten) → Tasks 11, 14a–14c; 4.2 → Tasks 12, 13; 4.3 (Praxisquellen und ihre geltende Liste, Widerspruch, die Ausnahme des Auftraggebers im Teil `precedence`, Nachweis, Ablehnung, Schwellen) → Tasks 11, 14a–14c, 16 und 18 (geänderte Schwellen im Kopf); 4.4 (Zielumgebung, Ort der Änderung, letzter Start, WEM, PrinTaurus SmartSpread, Zuordnung über Citrix-Richtlinien nur, wo sie genutzt wird) → Wertetabellen `vda`, `print`, `events`, Tasks 5, 6, 12, 13, 14a–14c, 18, 20; 5.1 (elf Kacheln) → Tasks 16, 18, 19; 5.2 → Task 19; 5.3 → Tasks 17, 20; 5.4 → Tasks 16, 18; 5.5 → Tasks 18, 20 (400 px); 6 → Tasks 8 (Kategorie), 12 und 13 (abhängige Prüfungen „nicht prüfbar"), 15, 16 (Maskierung); das Prüfskript bleibt unverändert (Global Constraints); 7 → die Tests der Tasks 1–20; 8 → Task 22; 9 → Katalogtexte und README (Tasks 14a–14c, 21); 11 → Task 22; Anhang Punkt 1 → Task 8 (eigene Abfrage statt Schreiber), Punkt 2 → Task 10, Punkt 3 → Tasks 8 und 20, Punkt 4 → Tasks 8 (Hilfe) und 21 (README).
- **Decisions coverage:** A1–A6 → Tasks 1a, 4, 8; B1–B4 → Tasks 9, 10, 17; C1–C2 → Task 10; D1–D5 → Wertetabellen, Tasks 4–6, 12 (D1 streng nach P2: Merkmal `Documented`, Ablehnung im Lader, Tasks 1a, 11, 14a); E1–E7 → Tasks 11–14, 16; F1–F2 → Tasks 15, 16; G1–G4 → Tasks 18–20; H1–H2 → Tasks 3, 4; I1–I3 → Abschnitt „Reihenfolge und Parallelität"; J1–J3 → Tasks 11 (Art `practice`, Adresse Pflicht), 14a–14c (Prüfungen aus BIS-F und Stalhood, Widersprüche, eigene Abschnitte im Nachweis), 16 und 18 (Bezeichnung der Art in den Daten und auf der Seite); K1–K4 → Global Constraints, Tasks 14a–14c (Ort der Änderung, letzter Start, nichts nur für Provisioning Services), Wert `vda.persistentDataLocation` und `copy.environment` (Tasks 5, 13, 18); L1–L2 → Fakten `events.sinceBootOnly`, `events.reachFrom` (Task 12), Prüfung `events.sinceBoot` mit der richtigen Quelle und ihrer Voraussetzung (Task 14b), `eventsReachText` (Tasks 13, 18, 20); M2–M3 → Werte `vda.wem*` (Task 5), Prüfungen (Tasks 14a, 14b), `print.citrixMapping` und das Ergebnis `na` (Tasks 12, 13); M1 ist durch R1 ersetzt; N1–N2, O1–O7 → Tasks 1b, 2, 3, 7, 8, 11–14c (O3 mit der genannten Abweichung im Aufbau, O5 mit zwei Lesern); P1 → Task 12 (`Get-WorkerPerfHealthEventCount`); P2 → wie D1, dazu die VMware-Prüfungen mit Quelle; P3 → Wert `security.applockerCollections` ohne Prüfung; P4 → Task 13 und die Seite (Tasks 18, 19); P5 → Tasks 12, 13; P6 → Tasks 8 und 20; P7 → Wert `sessions.limits`, Texte in Task 14a; P8 → Task 15; P9 → Tabelle „Schwellen des Katalogs", Task 14c Step 6; P10 → Tasks 1a, 1b, 2, 3, 7 und 14a bis 14c als eigene Tasks; Q1–Q2 → Teil `precedence` im Lader (Task 11), sein Eintrag für den Energiesparplan und der Test mit „Ausbalanciert" (Task 14a); Q3 → `network.rss` nach dem Hersteller, der Text nennt BIS-F (Task 14b); R1–R2 → Wert `print.mappingClientVersion` (Tasks 1a, 4, 6), Fakt `print.mappingClientRelease` (Task 12), Prüfung `print.mappingClientSupported` und `notCovered` des Bereichs (Task 14b), Abschnitt „Nach dem ersten echten Lauf"; S1–S3 → Tabelle „Praxisquellen" des Nachweises mit ihrem Test (Task 14a), Regel „Feste Listen" für Prüfungen aus den weiteren Recherchen (Abschnitt „Inhalt des Katalogs").
- **Recherchen:** verwendet ist jede Empfehlung nur mit dem Urteil ihres Abschnitts „Source check": „supported", oder „partly" mit der dort genannten Kürzung (die Regel der Tabelle enthält nur den gestützten Teil); „unsupported" und nicht erreichbare Quellen stehen unter „Nicht aufgenommen". Aus `research-printmapping.md` sind `pt.client.installed` und `pt.rec.supported-version` verwendet, `pt.rec.same-release` und `pt.rec.no-ipp-on-terminalserver` als Hinweise mit ihren Kürzungen. Die Recherchen `research-px-<key>.md` der weiteren Praxisquellen haben noch keine Quellenprüfung je Eintrag und sind nicht verwendet. Die Vorarbeit nennt in J3 eine Datei `research-community.md`; vorhanden und verwendet sind `research-bisf.md` und `research-stalhood.md`.
- **Step scan:** jeder Code-Schritt nennt Datei und Signatur; die Tests enthalten die Werte des Entwurfs, der Entscheidungen und des Drehbuchs; Funktionskörper fehlen; die Gestaltung beschreibt Bereiche, Inhalte und Verhalten statt Code; jeder Befehl für mehrere Testdateien steht in der Form, die eine Liste übergibt.
- **Type consistency:** `New-WorkerPerfHealthValue`, `Complete-WorkerPerfHealthArea`, `New-WorkerPerfHealth` (Task 1a) werden in den Tasks 3–8, 10, 12 und 13 mit denselben Feldern benutzt; `Read-WorkerPerfHealthApps` (Task 1b) in den Tasks 2, 3, 7, 8, 11, 14a, 14c, 16 und 17, überall unter diesem Namen (`Read-WorkerPerfApps` ist die Funktion des geführten Berichts; nur das Berichtsskript ruft beide); der Parameter `-AppsFile` am Collector (Task 8, 9) und am Berichtsskript (aus dem geführten Bericht; Tasks 16, 17); `Get-WorkerPerfAppRows` mit den fünf Lesern (Task 1b) in den Tasks 3 und 7; die Zeilenfelder `App`, `Id`, `Kind`, `Read`, `State`, `Reason`, `Value`, `Names` in den Tasks 1b, 3, 7, 12, 13; `New-TestAppFile` (Task 2) in den Tasks 3, 7, 9, 11, 14c, 17; die Kennwörter `budget`, `noReader`, `notRead`, `notInFile` (Task 1a) in den Tasks 4, 10 und 13; `$script:WorkerPerfHealthValues` mit `Documented` in den Tasks 1a, 3–7, 10, 11, 12, 15 und 16 (Markertest); `New-WinStandInDenied`, `Delay`, `LogFail` (Task 4) in den Tasks 5–7; `Get-WorkerPerfWinHealthFailReason` (Task 4) in Task 7; `Get-WorkerPerfWinHealthShared` mit dem zweiten Versuch nach einem Zeitlimit und `DelayOnce` (Task 4) in Task 5; `Get-WorkerPerfServiceExe` (Task 5) überall, wo ein Dienst an seinem Programm erkannt wird; `ConvertTo-WorkerPerfTaskTime` (Task 6) in Task 7; `WorkerPerf.HealthNative` mit `GetCommit`, `GetActivePowerScheme` (Task 4) und `GetFilterBuffers` (Task 6); `Model.Health` (`ReadAtMs`, `OffsetMinutes`, `Areas`), `Model.Recorded`, `Model.EventsAll` aus Task 10 in den Tasks 12 und 13; `Get-WorkerPerfHealthFactTable([object[]]$Apps)` und `appList` des Katalogs (Task 11) in den Tasks 12–14c; der Teil `precedence` (Task 11) in Task 14a; `$PlanChecks`, `$Vendor`, `$Practice`, `$K3`, `$Proof` (Task 14a) in den Tasks 14b und 14c; `New-WorkerPerfHealthFact` mit `notInUse`, `Get-WorkerPerfHealthMissingReason`, `Get-WorkerPerfHealthFacts`, `Get-WorkerPerfHealthEventCount` (Task 12) in Task 13; das Ergebnis aus Task 13 (`offsetMin`, `environmentText`, `eventsReachText`, `areas[]` mit `statusText`, `countsText`, `intro`, `apps[]` und `checks[]` mit `grade` einschließlich `na`, `app`, `why`; `raw[]` mit `stateText`; `summary`) unverändert in den Tasks 16–20; die Texte `copyCheckTitle`, `copyAreaTitle`, `copyAreaItem`, `countsAct`, `countsCheck`, `countsUnknown`, `areaPartial`, `areaFailed`, `areaReason…`, `notRecordedFailed`, `kindPractice`, `notApplicable`, `reasonAppNotInstalled`, `appNotInstalled`, `stateNotApplicable`, `environment`, `eventsReach` (Task 11) in den Tasks 13, 14a und 16; `health.grades`, `headline`, `unknownText`, `changedText`, `incidentNote`, `copy` aus Task 16 in den Tasks 18–20; `Invoke-SimHealthOnly` (Task 9) in den Tasks 14c und 17; `WP.openArea` (Task 18) in Task 19. Zahlen an jeder Stelle gleich: 11 Bereiche, 103 Werte, 61 abgeleitete Fakten, 164 feste Fakten, 38 Fakten der ausgelieferten Anwendungsliste (202), 206 mit der vierten Anwendung der Tests, 77 Prüfungen (33, 12 und 32; je Task 31, 33 und 13), 21 Schwellen, 105 Kopierfelder im unmaskierten Bericht; simulierte Stunde: 2 Bereiche zum Handeln, 4 zum Prüfen, 5 in Ordnung, 2 Prüfungen nicht prüfbar; simulierter Schnelllauf: 1, 5 und 5.
- **Review Focus:** fünf Zeilen, je mindestens ein markierter Test in den genannten Tasks; die zwei bewusst nicht aufgenommenen Fälle sind begründet.
- **Proportion:** der Plan ist länger als die Vorpläne, weil der Entwurf ihm die Wertelisten überlässt (elf Bereiche, drei Tabellen der Anwendungsliste); die Codeblöcke sind Tests.
- **Umfang und Laufzeit:** 22 Nummern in 25 Tasks (A 1a–14c, B 15–17, C 18–20, D 21–22); geteilt sind Task 1 (Format, Anwendungsliste) und Task 14 (Katalog in drei Stücken). Kosten in der Testlaufzeit: drei zusätzliche simulierte Stunden (der Lauf `Zustand` und der Lauf mit scheiterndem Lesen in `tests/Skip.Tests.ps1`, eine Stunde in `tests/Health.Tests.ps1`), je etwa 20 s; dazu sechs Schnellläufe (Tasks 9, 14c, 17), die kaum Zeit kosten; die Tests mit einem Zeitlimit warten je ein bis zwei Sekunden.
- **Zweite Überarbeitung:** eingearbeitet sind die Entscheidungen Q (Vorrang der Praxisquelle beim Energiesparplan), R (Name und Dokumentation des Zuordnungswerkzeugs) und S (weitere Praxisquellen) und der Stand des geführten Berichts nach der Korrekturrunde 2 seines Task 6 (`Read-WorkerPerfApps`, `-AppsFile`, `appList`, Einträge der Rollenliste). Was sich gegenüber der vorigen Fassung geändert hat, steht je Befund in `revision2-notes.md` der Vorarbeit.

## Offene Punkte für den Auftraggeber und den Controller

Worüber die Abschnitte P, Q und R der Entscheidungen schon entschieden haben (Ereignisse der Messung, D1 streng, AppLocker, „trifft nicht zu", Rückblick in der Regel `act`, `Places`, Zeitlimits, Ordner `Administrator`, Schwellen, Teilung von Tasks, Vorrang der Praxisquelle beim Energiesparplan, RSS nach dem Hersteller, Name des Zuordnungswerkzeugs), ist eingearbeitet und steht hier nicht mehr.

**Wo eine Entscheidung so, wie sie geschrieben ist, nicht aufgeht**

1. **Teams ist mit den fünf Lesearten nur über einen Pfad mit Platzhalter erkennbar (O2, O6, Entwurf 3.2a).** Das neue Teams ist ein MSIX-Paket. Microsoft dokumentiert als lokale Belege den Ordner `C:\Program Files\WindowsApps\MSTeams_[version]_[arch]__8wekyb3d8bbwe` (der Name enthält die Version) und `Get-AppxPackage` (ein Cmdlet eines Fachmoduls, nach A6 ausgeschlossen und keine der fünf Lesearten). Ein fester Pfad, ein Registrierungswert, ein Dienst oder eine Aufgabe, die „Teams ist installiert" zeigen, sind nicht dokumentiert. Der Plan hält an den fünf Lesearten fest und erlaubt der Leseart `file` ein `*` in genau einem Ordnernamen; das ist eine Erweiterung gegenüber O2. Zwei Unsicherheiten bleiben: ob sich `WindowsApps` mit Administratorrechten aufzählen lässt (zeigt der erste echte Lauf; sonst ist Teams „nicht prüfbar" mit dem Grund „fehlende Rechte"), und dass ein Platzhalter die Liste etwas mächtiger macht. Alternativen: eine sechste Leseart „Paket" über die dokumentierte Windows-Schnittstelle der Paketverwaltung (genauer, aber gegen den Wortlaut von O2 und Entwurf 3.2a), oder Teams ohne Erkennung der Installation führen (dann zählen seine Prüfungen auf jedem Worker). Vorschlag: so lassen, wie der Plan es macht, und nach dem ersten echten Lauf entscheiden.
2. **Ob Citrix-Richtlinien Drucker zuordnen, ist aus dokumentierten Quellen nicht lesbar (M3).** Die Wertnamen der Citrix-Druckrichtlinien und das Namensschema automatisch erstellter Drucker stehen in keinem geöffneten Citrix-Dokument (D1, P2), und die öffentlichen Seiten des Herstellers von PrinTaurus SmartSpread sagen nicht, ob die Citrix-Druckrichtlinien abgeschaltet sein sollen. Dokumentiert ist nur der Dienst „Citrix Print Manager Service". Der Plan bildet daraus `print.citrixMapping`: läuft der Dienst nicht, ist die Zuordnung „nicht in Gebrauch"; läuft er, gilt sie als möglich. Auf einem Worker, auf dem der Dienst läuft und PrinTaurus die Drucker verbindet, würde eine spätere Prüfung auf Citrix-Druckrichtlinien also bewertet. In der ersten Fassung hat das keine Folge, weil der Katalog keine solche Prüfung hat. Für die Anpassungsrunde hilft eines von beidem: die Rohwerte der Citrix-Richtlinien aus dem ersten echten Lauf (dann wird der Fakt genau), oder die Installationsanleitung von PrinTaurus als Datei (die Release Notes 6.4 verweisen auf sie, veröffentlicht ist sie nicht; dann können Werte und Prüfungen zum Ablauf der Zuordnung folgen). Frage an den Auftraggeber: Läuft auf den Workern der Citrix-Druckdienst, sind die Citrix-Richtlinien für Client- und Sitzungsdrucker abgeschaltet, und liegt die Installationsanleitung von PrinTaurus vor?
3. **Für Office bleibt nach P2 nur eine schwache Prüfung (O6 gegen P2).** O6 nennt für Office die Click-to-Run-Konfiguration, die Updateeinstellungen und die Aufgaben. Die Werte, auf die es ankommt (`UpdatesEnabled`, `Platform`, `VersionToReport`, der Richtlinienname für automatische Updates), stehen in keinem Herstellerdokument als Registrierungswerte; nach P2 sind sie Rohwerte. Übrig ist `apps.officeUpdateUi` (Faustregel, übertragen von Microsofts Vorgabe für Microsoft 365 Apps). Die Rohwerte stehen im Bericht. Vorschlag: so lassen; nach dem ersten echten Lauf entscheidet der Auftraggeber, ob die im Lauf bestätigten Werte Prüfungen tragen dürfen („automatische Updates von Office nicht abgeschaltet", „32-Bit-Office").
4. **Eine Regel aus UND-Bedingungen bildet den Vorrang zweier Richtlinien nicht genau ab (E2).** `apps.edgeAutoUpdate` meldet „prüfen", wenn weder die allgemeine noch die Edge-eigene Update-Richtlinie die Updates abschaltet. Der Fall „allgemein abgeschaltet, für Edge ausdrücklich eingeschaltet" bleibt „in Ordnung", obwohl Edge sich dann aktualisiert. Genau wäre es nur mit einem „oder" im Katalog oder mit einem abgeleiteten Fakt im Code (dann aber nicht mehr ohne Codeänderung erweiterbar). Vorschlag: hinnehmen; die Rohwerte zeigen den Fall.

**Fragen an den Controller**

5. **`src/apps.json` hat zwei Leser (O5).** `Read-WorkerPerfApps` in `src/WorkerPerf.Guidance.ps1` ist gebaut (geführter Bericht: liefert das Listenobjekt für `app.<key>`); dieser Plan legt `Read-WorkerPerfHealthApps` in `src/WorkerPerf.Common.ps1` an (liefert die Anwendungen mit ihren Proben, auch im Collector, der `Guidance` nicht einbindet). Beide prüfen `key`, `label` und `processes` gleich; die Regeln für die Prozessmuster prüft nur der erste. Eine Datei, deren Muster der geführte Bericht ablehnt, nimmt der Collector also an, und erst die Auswertung lehnt sie ab. Frage: sollen die zwei Leser nach dem Abschluss beider Bausteine in `src/WorkerPerf.Common.ps1` zusammengelegt werden? Das ist eine kleine Task, die `src/WorkerPerf.Guidance.ps1` und `tests/Guidance.Tests.ps1` ändert und deshalb nicht in Teil A liegt.
6. **Die .NET-Voraussetzung des SmartSpread Client ist nicht aufgenommen (R2).** Der Hersteller verlangt ab 6.2 das .NET Framework 4.7.2 (Release Notes 6.2; in der Recherche „partly"). Die Prüfung bräuchte einen eigenen Wert (`HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full`, `Release`; von Microsoft dokumentiert), den sonst nichts braucht. Frage: aufnehmen (ein Wert, eine Prüfung der Art „Empfehlung des Herstellers", je ein Test in den Tasks 6 und 14b; die Zahlen der festen Listen steigen um eins) oder weglassen?
7. **Die elf weiteren Praxisquellen tragen in der ersten Fassung keine Prüfung (S1, S2).** Der Nachweis führt sie mit dem Stand „offen". Ihre Recherchen entstehen: `research-px-goeuc.md`, `research-px-kindon.md` und `research-px-rankin.md` liegen vor, noch ohne Quellenprüfung je Eintrag. Frage: sollen ihre Kandidaten vor der Abnahme in den Katalog (dann als Änderung dieses Plans nach der Regel „Feste Listen": Listen und Zahlen der Tasks 14a–14c und 16–19 ändern sich) oder mit der Anpassungsrunde nach dem ersten echten Lauf? Ein Eintrag berührt die Ausnahme des Auftraggebers: GO-EUC hat für „Höchstleistung" gegenüber „Ausbalanciert" nur einen geringen Gewinn gemessen (Eintrag GOEUC-04: Windows 11, ein Benutzer; noch ohne Quellenprüfung). Nach S3 nennt der Katalog dann beide Sichten; die Festlegung des Auftraggebers (Q2) bleibt die Regel.
8. **Der simulierte Worker hat den Energiesparplan „Höchstleistung".** So bleiben die Einstufungen der simulierten Stunde und die Zahlen der Tasks 14c und 16 bis 19, wie sie waren; die Ausnahme selbst prüft Task 14a mit „Ausbalanciert". Soll die Demo die Abweichung zeigen (`balanced` im Drehbuch von Task 3), kommt `operation.powerPlan` in die Liste „prüfen" (Task 14c) und in die Verweise des CPU-Vorfalls (Task 16); Bereichsnoten und Zusammenfassung bleiben gleich.
9. **Zwei Texte aus den Daten sprechen im Zustandsbericht von einer Messung, die es dort nicht gibt.** `skip.text.Rueckblick` („Ereignisse der Tage vor der Messung wurden nicht erfasst.", Baustein Messkategorien) erscheint bei weggelassenem Rückblick; das Feld `sign` von sechs Schritten des geführten Berichts für Rückblick-Vorfälle sagt „… auch während der Messung" (`src/guidance.de.json`). Beide gehören anderen Bausteinen und bleiben in diesem Plan unverändert; Task 20 gibt nur den Sätzen der Seite eine zweite Fassung und prüft nur sie. Frage: soll der Katalog des geführten Berichts für den Schnelllauf eine eigene Fassung dieser `sign`-Texte bekommen?
10. **Der Auftrag zu dieser Überarbeitung nannte noch M1** (das Zuordnungswerkzeug wird im Plan nicht genannt). Der Plan folgt der späteren Entscheidung R1 und dem Entwurf 4.4: er nennt PrinTaurus SmartSpread, AKI und die Namen aus den Release Notes (Client, Installationspaket). Soll der Plan beim allgemeinen Wort bleiben, ändern sich nur Texte; die Kennungen (`print.mappingClient…`) sind allgemein gehalten.

**Zur Kenntnis**

11. **Teil A ist nicht ganz unabhängig vom geführten Bericht (I1).** Die Tasks 2, 3 und 7 und alles ab Task 8 brauchen den Commit, der `src/apps.json` und ihren Leser anlegt (die Tasks 3 und 7 lesen die Datei in ihren Tests über `New-TestAppFile` aus Task 2); Task 12 braucht den Commit, der die Rollenliste ergänzt; Task 2 trägt acht Zeilen in `tests/MaskCensus.json` ein, weil der geführte Bericht die Anwendungsliste in die Berichtsdaten legt. Die Tasks 1a, 1b und 4 bis 6 können vorher beginnen.
12. **Zwei Schwellen kommen jetzt aus der Praxisquelle (P9).** `updateAgeDays` ist 60 statt 45 Tage (Stalhood), und zwei neue Prüfungen melden einen Worker mit weniger als 8 Prozessoren oder 24 GB als „prüfen". Auf bewusst kleiner geschnittenen Workern ist das ein Dauerhinweis; die Schwellen stehen im Katalog und lassen sich ändern.
13. **Ein Fund der Recherche, der keine Prüfung wurde:** die Microsoft-Seite zu Teams auf VDI nennt für Windows Server 2022 ein Ende der Unterstützung von Teams im Oktober 2026. Der Windows-Build ist über die geöffneten Dokumente nicht als lokaler Lesewert belegt, deshalb prüft der Katalog das nicht; der Auftraggeber sollte die Angabe kennen.
14. **Die Rohwertanzeige zeigt die Anwendungswerte zweimal:** als Liste `apps.probes` (wie aufgezeichnet) und als einzelne Fakten `apps.<key>.<id>` (wie bewertet). Das ist gewollt einfach gehalten; soll die Liste dort entfallen, ändern sich eine Zeile in Task 13 und die Zahl 202.
15. **Der kurze Weg des Berichtsskripts (B4)** verlangt wie bisher, drei Stücke von `src/New-WorkerPerfReport.ps1` zu Funktionen zu machen (Task 17, Step 3), an einer Datei, die Task 7 des geführten Berichts zuvor ändert; Task 17 beginnt deshalb erst danach und prüft den Umbau mit der ganzen Suite, bevor der kurze Weg entsteht.
