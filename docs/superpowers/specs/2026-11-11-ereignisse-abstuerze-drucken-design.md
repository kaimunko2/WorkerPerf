# Ereignisse, Abstürze und Drucken – Entwurf

Stand: 11.11.2026. Erweitert `2026-11-10-engpassanalyse-design.md`. Wird vor `2026-11-11-maskierung-design.md` und `2026-11-11-gefuehrter-bericht-design.md` umgesetzt.

## 1. Ziel

WorkerPerf erkennt heute Engpässe aus Messwerten. Hinzu kommen Störungen, die sich im Ereignisprotokoll zeigen: Abstürze und Hänger von Anwendungen, ausgefallene Dienste, Druckprobleme, Profilfehler und Systemfehler. Sie werden als eigene Vorfälle geführt, nach Anwendung zusammengefasst und mit der Messung abgeglichen, damit der Bericht Hinweise auf die Ursache geben kann.

Erfolgskriterien:

- Ein Absturz in einer Benutzersitzung erscheint als Vorfall mit Anwendung, Modul, Benutzer und den zutreffenden Mustern.
- Der Bericht nennt eine Ursache nur, wenn ein Muster sie stützt, und formuliert vorsichtig.
- Ereignisse aus den Tagen vor der Messung sind sichtbar und nach Mustern zusammengefasst.
- Der Collector liest nur und ändert keine Einstellung des Servers.

## 2. Abgrenzung

- Keine Auswertung von Speicherabbildern.
- Kein Protokoll einzelner Druckaufträge; ausgeschaltete Windows-Protokolle werden nicht eingeschaltet.
- Die Erkennung der Leistungsvorfälle bleibt unverändert; die acht Vorfälle der simulierten Stunde bleiben, wie sie sind.
- Empfehlungen (auch zum Drucken) gehören in den Katalog des geführten Berichts; diese Spezifikation liefert die Tatsachen dafür.
- Skripte bleiben kompatibel zu Windows PowerShell 5.1 und rein in ASCII.

## 3. Ereignisquellen

| Gruppe | Inhalt | Windows-Protokoll |
|---|---|---|
| `app` | Absturz, Hänger, .NET-Laufzeitfehler, Fehlerberichte | Anwendung |
| `service` | unerwartet beendete oder neu gestartete Dienste | System |
| `storage` | Datenträger-, Dateisystem- und Controllerfehler | System |
| `memory` | Warnung vor knappem virtuellem Speicher | System, Ressourcenerschöpfung |
| `fileserver` | Verbindungsabbrüche und Zeitüberschreitungen | SMB-Client |
| `profile` | Fehler beim Laden und Entladen von Profilen, Meldungen der Citrix-Profilverwaltung | Anwendung, Benutzerprofildienst |
| `print` | Fehler des Druckdienstes, Treiberfehler, fehlgeschlagene Aufträge, Citrix-Druckverwaltung | Druckdienst (Verwaltung), Anwendung, System |
| `session` | Anmelden, Abmelden, Trennen, Wiederverbinden | Terminaldienste (Sitzungsverwaltung) |
| `security` | Defender und AppLocker | wie bisher |

Die Liste der Protokolle, Quellen und Kennungen steht in `src/events.json`: je Eintrag Protokoll, Quelle, Kennung, Gruppe, Art, und welche strukturierten Felder aus dem Ereignis zu lesen sind. Sie lässt sich ergänzen, ohne Code zu ändern. Die bisherige feste Zuordnung für Defender und AppLocker zieht dorthin um. Welche Kennungen der Citrix-Druckverwaltung und der Profilverwaltung auf dem Zielserver entstehen, bestimmt das Prüfskript (Abschnitt 9, Schritt 1).

## 4. Aufzeichnung

### 4.1 Ereignisse der Messzeit

Gelesen wie bisher bei jedem Schnappschuss, mit Obergrenze je Abruf. Je Ereignis werden gespeichert:

- Zeit, Protokoll, Quelle, Kennung, Stufe, Gruppe, Art
- wo vorhanden: Anwendung und Version, fehlerhaftes Modul und Version, Fehlercode, Prozess-ID, Sitzung, Benutzer, Drucker, Treiber, Dienst
- Meldungstext, gekürzt auf die erste Zeile und 300 Zeichen

Sitzung und Benutzer ergänzt der Collector, soweit sie sich aus dem Ereignis oder über die Prozess-ID aus dem letzten Schnappschuss zuordnen lassen; sonst bleiben die Felder leer. Die strukturierten Felder werden aus den Datenfeldern des Ereignisses gelesen, nicht aus dem übersetzten Meldungstext, damit die Zuordnung von der Sprache des Systems unabhängig ist.

`events.csv` erhält dafür zusätzliche Spalten. Das Datenformat bekommt eine neue Versionsnummer; die Auswertung liest das bisherige Format weiter und behandelt die neuen Spalten dort als leer.

### 4.2 Rückblick

Beim Start liest der Collector einmalig die Ereignisse der letzten Tage in eine eigene Datei `events_before.csv`, mit denselben Spalten. Parameter `-EventLookbackDays`, Standard 7, 0 schaltet ab. Je Protokoll gilt eine Obergrenze; wird sie erreicht, vermerkt `meta.json`, für welches Protokoll der Rückblick unvollständig ist. Sitzungsereignisse werden im Rückblick nicht gelesen.

### 4.3 Drucken

- **Treiberliste** beim Start in `printdrivers.csv`: Name, Hersteller, Version, Bauart (Typ 3 oder Typ 4), ob isoliert, Treiberdateien (nur Dateinamen).
- **Zähler je Druckwarteschlange** bei jedem regulären Schnappschuss in `printqueues.csv`: wartende Aufträge, Auftragsfehler, „nicht bereit"-Fehler.
- Die **Last der Druckprozesse** steckt in den Prozessdaten; `src/roles.json` erhält eine Rolle „Drucken" für die Druckwarteschlange, ihre Hilfsprozesse und die Citrix-Druckverwaltung.

### 4.4 Belastung und Schutz

- Ein nicht vorhandenes oder nicht lesbares Protokoll erzeugt eine einmalige Warnung; die Messung läuft weiter, und die Quelle gilt als nicht verfügbar.
- Der Collector schaltet nichts ein und ändert keine Einstellung.
- Die zusätzlichen Abfragen laufen im Schnappschuss, nicht im schnellen Takt. Ihre Dauer zählt zur Messdauer je Schnappschuss; die Orientierungsstufen im README gelten unverändert.

## 5. Auswertung

### 5.1 Neue Vorfallsarten

| Art | Entsteht, wenn |
|---|---|
| `crash` Anwendungsabsturz | Absturz in einer Benutzersitzung; ein einzelner genügt |
| `hang` Anwendungshänger | Anwendung reagierte nicht und wurde beendet, in einer Benutzersitzung |
| `service` Dienstausfall | ein wichtiger Dienst endete unerwartet (Druckwarteschlange, Citrix-Dienste, Profilverwaltung; Liste in `events.json`), oder ein beliebiger Dienst mindestens zweimal |
| `print` Druckproblem | Treiberfehler, fehlgeschlagene Aufträge oder Ausfall der Druckwarteschlange |
| `profileerror` Profilproblem | Profil ließ sich nicht laden oder entladen, oder die Profilverwaltung meldet Fehler |
| `system` Systemfehler | Datenträger- oder Dateisystemfehler, Speichermangel-Warnung, Verbindungsabbruch zum Dateiserver |

Abstürze und Hänger von Prozessen ohne Benutzersitzung sind Ereignisse in der Zeitleiste; ab der zweiten Wiederholung derselben Anwendung bilden sie einen Vorfall. Ein Absturz der Druckwarteschlange zählt als `print`, nicht als `crash`.

### 5.2 Zusammenfassen

Ereignisse derselben Art und desselben Schlüssels bilden einen Vorfall, wenn zwischen zwei aufeinanderfolgenden höchstens 30 Minuten liegen (Einstellung `eventGroupMinutes`, in den Schwellen). Schlüssel: bei `crash` und `hang` die Anwendung; bei `service` der Dienst; bei `print` der Treiber, sonst der Drucker, sonst die Quelle; bei `profileerror` die Quelle; bei `system` die Gruppe und das betroffene Objekt (Laufwerk, Server).

Ein Vorfall nennt: Anzahl, Zeitspanne, betroffene Benutzer und Sitzungen, Versionen der Anwendung, fehlerhafte Module mit Anzahl und der Angabe, ob es immer dasselbe war, Fehlercodes.

### 5.3 Abgleich mit der Messung

Für jeden Vorfall aus Ereignissen prüft die Auswertung diese Muster und hält die zutreffenden fest:

| Muster | Prüfung | Aussage |
|---|---|---|
| `resource` | Arbeitsspeicher oder zugesagter Speicher in den 5 Minuten vor einem Ereignis über der kritischen Schwelle, oder Speichermangel-Warnung im selben Zeitraum | „wahrscheinlich Folge des Speichermangels" |
| `afterhang` | Hänger derselben Anwendung in derselben Sitzung höchstens 2 Minuten vor dem Absturz | „wurde nach Nichtreagieren beendet" |
| `sharedmodule` | mindestens zwei verschiedene Anwendungen stürzen im selben Modul ab, und das Modul ist kein allgemeines Systemmodul (Liste in `events.json`) | „Ursache liegt wahrscheinlich im Modul …" |
| `printdriver` | das fehlerhafte Modul ist eine Datei eines Treibers der Treiberliste | „das Modul gehört zum Druckertreiber …" |
| `securitymodule` | das fehlerhafte Modul gehört laut Rollenliste zur Schutzsoftware | „das Modul gehört zur Schutzsoftware …" |
| `manyusers` | mindestens drei Benutzer, dieselbe Anwendung | „spricht für Installation oder Update" |
| `oneuser` | ein Benutzer, mindestens drei Ereignisse | „spricht für Profil oder Daten dieses Benutzers" |
| `companion` | Ereignis der Gruppen `storage`, `fileserver`, `profile`, `security` höchstens 2 Minuten vor oder nach einem Ereignis des Vorfalls | wird mit Uhrzeit genannt |
| `overlap` | ein Leistungsvorfall überlappt das Zeitfenster | beide Vorfälle verweisen aufeinander |

Die Zeitabstände stehen in den Schwellen. Trifft kein Muster zu, sagt der Bericht „Kein Muster erkannt" und nennt keine Ursache. Mehrere zutreffende Muster werden alle genannt; die Auswertung wählt keines aus.

### 5.4 Fehlercodes

`events.json` enthält eine Tabelle der häufigsten Fehlercodes mit einer Erklärung in Alltagssprache (Zugriffsverletzung, Stapelüberlauf, Speicheranforderung fehlgeschlagen, wegen Nichtreagierens beendet und weitere). Unbekannte Codes erscheinen unverändert.

### 5.5 Verhältnis zu den Leistungsvorfällen

- Leistungsvorfälle entstehen wie bisher. Überlappt ein Ereignisvorfall, bleiben es zwei Vorfälle mit gegenseitigem Verweis; Ursache und Folge legt der Bericht nur über das Muster `resource` fest.
- Ereignisse der Gruppen `storage`, `fileserver`, `memory`, `profile` und `print` erscheinen zusätzlich als Belege in Leistungsvorfällen, deren Zeitfenster sie trifft.
- Sitzungsereignisse bilden keine Vorfälle. Sie erscheinen in der Zeitleiste und bei der Sitzung.

### 5.6 Rückblick

Die Ereignisse vor der Messung werden nach 5.2 zusammengefasst. Es gelten nur die Muster, die keine Messwerte brauchen: `afterhang`, `sharedmodule`, `printdriver`, `securitymodule`, `manyusers`, `oneuser`, `companion`. Die Auswertung liefert sie getrennt von den Vorfällen der Messzeit, mit Häufigkeit je Tag. Mit `-ReportedTime` vor Beginn der Messung liefert sie die Ereignisse im Umkreis von 15 Minuten um diese Zeit.

### 5.7 Druckzustand

Die Auswertung liefert je Treiber der Treiberliste: Hersteller, Version, Bauart, isoliert oder nicht, und ob er an einem Vorfall beteiligt war; je Warteschlange Höchstwert der wartenden Aufträge und Zahl der Fehler; für die Prozesse der Rolle „Drucken" Höchstwert und Verlauf von CPU und Arbeitsspeicher. Ein Anstieg des Arbeitsspeichers der Druckwarteschlange über die Messung wird als Tatsache geliefert (Wert am Anfang, am Ende, Höchstwert), nicht bewertet.

## 6. Simulation

Das Drehbuch der simulierten Stunde erhält zusätzliche Szenen, ohne die bisherigen acht Vorfälle zu verändern:

- eine Anwendung stürzt bei drei Benutzern im selben Modul ab (`manyusers`)
- ein Absturz unmittelbar nach dem Arbeitsspeicher-Engpass (`resource`, `overlap`)
- ein Ausfall der Druckwarteschlange mit einem Treibermodul (`printdriver`)
- ein Profilfehler bei einer Anmeldung
- Sitzungsereignisse zu den simulierten Sitzungen
- ein simulierter Rückblick über sieben Tage mit einem Muster `oneuser` und einem Muster `sharedmodule`
- eine Treiberliste und Zähler der Warteschlangen

`expected.json` nennt die erwarteten zusätzlichen Vorfälle und Muster.

## 7. Anzeige im heutigen Bericht

Bis der geführte Bericht steht, erscheinen die neuen Daten im heutigen Bericht:

- neue Vorfälle in der Vorfallsliste als Satz, mit Anzahl, Zeitspanne, Benutzern, Modul und den Aussagen der zutreffenden Muster
- eigene Markierungen je Gruppe in der Zeitleiste
- ein Block „Vor der Messung" mit den zusammengefassten Ereignissen des Rückblicks und dem Hinweis, dass für diese Zeit keine Messwerte vorliegen
- eine Tabelle „Drucken" mit Treiberliste und Zählern
- Sitzungsereignisse bei der Sitzung

Texte kommen wie bisher aus `src/texts.de.json`.

## 8. Tests

- **Zuordnung:** jede Kennung in `events.json` führt zu Gruppe und Art; die strukturierten Felder werden aus Beispielereignissen gelesen, unabhängig vom Meldungstext; fehlerhafte `events.json` ergibt eine Meldung mit Eintrag und Feld.
- **Zusammenfassen:** Abstand, Schlüssel je Art, Einzelabsturz in einer Sitzung, Hintergrundprozess ohne und mit Wiederholung, Absturz der Druckwarteschlange als `print`.
- **Muster:** jedes Muster trifft zu, wenn die Daten es stützen, und nicht, wenn nicht; mehrere Muster zugleich; kein Muster.
- **Rückblick:** Trennung von der Messzeit, Obergrenze mit Vermerk, nur die Muster ohne Messwerte, gemeldete Zeit vor der Messung.
- **Simulierte Stunde:** die bisherigen acht Vorfälle unverändert; die neuen Szenen ergeben genau die Vorfälle und Muster aus `expected.json`.
- **Fehlende Quellen:** fehlendes oder nicht lesbares Protokoll bricht nichts ab und erscheint als nicht gemessen; eine Aufzeichnung im bisherigen Format wird weiter ausgewertet.
- **Windows-Teile:** mit Platzhaltern für die Windows-Aufrufe, wie bei der Windows-Datenquelle.
- **Seite im Browser:** neue Vorfälle, Markierungen, Block „Vor der Messung", Tabelle „Drucken".

## 9. Reihenfolge der Umsetzung

1. **Prüfskript erweitern:** je Protokoll aus Abschnitt 3 Vorhandensein, Zahl der Ereignisse je Kennung in den letzten sieben Tagen und die Namen der Datenfelder je Kennung; Druckertreiber (Anzahl, Hersteller, Bauart, isoliert) und die Zählerkategorie der Druckwarteschlangen. Ausgegeben werden nur Anzahlen, Kennungen und Feldnamen, keine Meldungstexte und keine Feldwerte. Danach ein Lauf auf dem Zielserver während des Betriebs.
2. `events.json`, Datenformat, Simulation mit den neuen Szenen.
3. Auswertung: Zusammenfassen, Muster, neue Vorfallsarten, Rückblick, Druckzustand.
4. Windows-Datenquelle für Ereignisse, Treiberliste und Zähler, auf Grundlage des Prüfergebnisses.
5. Anzeige im heutigen Bericht, README, Demo-Seite.

## 10. Offene Punkte

- Welche Ereignisse der Citrix-Druckverwaltung und der Profilverwaltung auf dem Zielserver entstehen und wie ihre Datenfelder heißen, zeigt das Prüfskript.
- Ob 30 Minuten beim Zusammenfassen und die Abstände der Muster passen, zeigt die erste reale Auswertung.
- Die zusätzliche Datenmenge durch Sitzungsereignisse und den Rückblick ist an der ersten realen Aufzeichnung zu messen.
