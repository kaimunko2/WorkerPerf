# Zustandsbild des Workers – Entwurf

Stand: 12.11.2026. Wird nach `2026-11-12-messkategorien-design.md` und nach `2026-11-11-gefuehrter-bericht-design.md` umgesetzt; baut auf `2026-11-11-ereignisse-abstuerze-drucken-design.md` (Rückblick, Treiberliste) und `2026-11-11-maskierung-design.md` auf.

## 1. Ziel

Die Messung zeigt, was während eines Vorfalls geschieht. Dauerzustände wie ein unübersichtlicher Treiberbestand, doppelt prüfende Schutzprodukte oder eine knappe Größe erkennt man auch ohne Vorfall. Das Zustandsbild liest solche Zustände einmal beim Start, bewertet sie gegen die Empfehlungen der Hersteller und erklärt sie so, dass ein Windows-Administrator ohne tiefe Systemkenntnis damit arbeiten kann.

Erfolgskriterien:

- Jede Messung enthält ein Zustandsbild, sofern es nicht abgewählt wurde; ein Schnelllauf liefert es ohne Messung.
- Jede Prüfung nennt Befund, Einstufung, Erklärung, Vorschläge zum Vorgehen und die Quelle der Empfehlung.
- Ein Vorfall verweist auf die Prüfungen, die zu seiner Art passen.
- Das Lesen ändert nichts am Server und dauert zusammen unter einer Minute.

## 2. Bedienung

- **Mit jeder Messung:** Der Collector liest das Zustandsbild einmal beim Start, vor dem ersten Messtakt. Abwählbar mit `-Skip Zustand`.
- **Schnelllauf:** `Start-WorkerPerfCapture.ps1 -HealthOnly` liest nur das Zustandsbild und den Rückblick und beendet sich. Der Rückblick gehört dazu, weil das Ereignisbild der letzten Tage ein Bereich des Zustandsbilds ist. Das Ergebnis ist eine Aufzeichnung ohne Messreihen. `-HealthOnly` zusammen mit `-Skip Zustand` wird abgelehnt.
- **Auswertung:** Das Auswertungsskript wird wie bisher aufgerufen. Aus einer vollständigen Aufzeichnung entsteht der bekannte Bericht mit dem Bereich „Zustand des Workers". Aus einem Schnelllauf entsteht ein Zustandsbericht ohne Vorfälle und Diagramme. `-Mask` wirkt auf beide gleich.
- **Rechte:** Vorausgesetzt werden Administratorrechte, wie für die Messung. Ohne sie sind einzelne Prüfungen „nicht prüfbar".

## 3. Daten

### 3.1 Grundsatz

Die Aufzeichnung speichert Fakten, keine Bewertung. Der Collector schreibt die gelesenen Werte in `health.json`; die Einstufung entsteht bei der Auswertung aus dem Katalog. Eine alte Aufzeichnung lässt sich so mit einem verbesserten Katalog neu auswerten, und ein späterer Vergleich zweier Läufe vergleicht Fakten.

### 3.2 Bereiche und Quellen

| Bereich | Was gelesen wird |
|---|---|
| Größe und Reserve | Prozessoren, Arbeitsspeicher, Auslagerungsdatei, zugesagter Speicher, Zahl der Benutzersitzungen; VMware Tools; Netzwerk- und Speicheradapter der VM |
| Betrieb | letzter Start, Merker für ausstehenden Neustart, Datum des letzten installierten Updates, aktiver Energiesparplan, Belegung der Laufwerke |
| Sitzungen | Sitzungen mit Zustand und Trennzeitpunkt, Richtlinien für Zeitlimits bei Leerlauf und Trennung, lokale Profile ohne angemeldeten Benutzer |
| Citrix VDA | installierte Version, Dienste, Registrierung am Controller, Transportart der Sitzungen, druckbezogene Citrix-Richtlinien |
| Profilverwaltung | Version, Einstellungen aus Richtlinie und Registrierung, eingebundene Container mit Größe, Belegung und Obergrenze, Zahl der Container je Benutzer |
| Drucken | Treiberliste aus der Aufzeichnung (Typ, Hersteller, wirksame Isolierung), Isolierungsrichtlinie, Universaltreiber, Zahl der Warteschlangen, Zustand des Betriebsprotokolls des Druckdienstes |
| Sicherheitsprodukte | Status und Ausschlüsse von Microsoft Defender, geladene Filtertreiber, erkannte Produkte aus der Rollenliste, Umfang der AppLocker-Regeln |
| Netz und Dateiserver | SMB-Einstellungen des Workers, bestehende SMB-Verbindungen mit Protokollstand, Signierung und Verschlüsselung, DNS-Server, Netzwerkadapter, Zeitquelle |
| Ereignisbild | Zählungen aus dem Rückblick (Abstürze, Hänger, Dienst-, Datenträger-, Druck- und Dateiserver-Ereignisse je Tag), Größe und ältester Eintrag je Protokoll |
| Wartung in der Arbeitszeit | geplante Aufgaben mit Zeitplan, Zeitpläne für Scans und Updates, Zustand des Suchdienstes |

Die genaue Liste der Werte je Bereich steht im Umsetzungsplan. Maßgeblich ist: Jeder Wert wird aus einer Quelle gelesen, die Windows oder das Produkt dokumentiert.

### 3.3 Robustheit

- Jeder Bereich wird für sich gelesen; ein Fehler in einem Bereich stoppt die anderen nicht.
- Jeder Wert hat einen Zustand: gelesen, nicht vorhanden, oder nicht lesbar mit Grund (fehlende Rechte, Produkt nicht installiert, Zeitlimit).
- Jeder Bereich hat ein Zeitlimit; die Dauer je Bereich und gesamt steht in `health.json`.
- Das Lesen findet vor dem ersten Messtakt statt und geht nicht in die Messwerte ein.

### 3.4 Was nicht gelesen wird

Keine Inhalte von Benutzerdateien, Postfächern oder Profilen; keine Kennwörter, Schlüssel oder Zertifikate; nichts aus dem Active Directory und nichts von anderen Servern. Es wird nichts geändert, gestartet oder beendet, und es werden keine Verbindungen zu anderen Servern aufgebaut.

### 3.5 Format

- `health.json` trägt eine eigene Formatnummer, den Lesezeitpunkt und je Bereich die Werte mit Zustand.
- Die Datei enthält Pfade, Server- und Freigabenamen unverändert, wie die übrige Aufzeichnung.
- Aufzeichnungen ohne die Datei bleiben lesbar; der Bericht zeigt „Zustandsbild nicht erfasst".
- Die Simulation liefert ein erfundenes Zustandsbild mit mehreren auffälligen Werten.

## 4. Bewertung

### 4.1 Katalog

Die Bewertung steht in `src/health.de.json`, getrennt vom Code. Je Prüfung:

| Teil | Inhalt |
|---|---|
| Kennung, Bereich, Titel | zum Beispiel Drucken – „Treiber im Spooler-Prozess" |
| Werte | die Fakten aus `health.json`, die die Prüfung braucht |
| Regeln | Bedingungen für „prüfen" und für „handeln"; Schwellen als Zahlen |
| Was bedeutet das? | zwei bis drei Sätze in einfacher Sprache: warum der Punkt für Geschwindigkeit oder Stabilität zählt |
| Was tun? | Prüfschritte und übliche Abhilfen als Vorschläge, im Stil des geführten Berichts, ohne kopierbare Befehle |
| Quelle | Hersteller, Titel, Adresse, Datum der Prüfung |
| Art | „Empfehlung des Herstellers", „Empfehlung aus der Praxis" oder „Faustregel" |
| Bezug | Arten und Muster von Vorfällen, zu denen die Prüfung passt |

Die Bedingungen nutzen dieselbe Schreibweise wie der Katalog des geführten Berichts. Die Befundsätze mit eingesetzten Zahlen stehen ebenfalls im Katalog.

### 4.2 Einstufungen

- **In Ordnung:** entspricht der Empfehlung.
- **Prüfen:** weicht von einer Empfehlung ab oder überschreitet eine Faustregel.
- **Handeln:** nur in zwei Fällen. Entweder ist eine harte Grenze erreicht (etwa ein fast volles Laufwerk oder ein fast voller Container), oder ein Dauerzustand trifft mit beobachteten Ereignissen zusammen (etwa nicht isolierte Treiber und Abstürze des Druckdienstes im Rückblick).
- **Nicht prüfbar:** ein benötigter Wert ließ sich nicht lesen; der Grund steht dabei.

Jeder Bereich trägt die Einstufung seiner auffälligsten Prüfung; „nicht prüfbar" allein macht einen Bereich nicht auffällig, wird aber gezählt. Eine Gesamtnote oder Punktzahl gibt es nicht.

### 4.3 Regeln für den Katalog

- Keine Prüfung ohne Quelle. Fehlt eine Herstellerempfehlung und eine Empfehlung aus der Praxis, heißt die Art „Faustregel" und die Formulierung bleibt vorsichtig.
- Neben den Quellen der Hersteller dienen zwei Quellen aus der Praxis als Grundlage (ergänzt am 13.11.2026 auf Wunsch des Auftraggebers): die Empfehlungen des Base Image Script Framework (BIS-F) und die Anleitungen von Carl Stalhood (carlstalhood.com). Eine Prüfung, die sich darauf stützt, trägt die Art „Empfehlung aus der Praxis" und nennt ihre Quelle wie eine Herstellerquelle mit Titel, Adresse und Datum. Sie wird nie als Empfehlung des Herstellers bezeichnet. Widerspricht eine Quelle aus der Praxis dem Hersteller, gilt der Hersteller; der Katalog nennt den Widerspruch.
- Jede Quelle wird beim Schreiben nachgeschlagen und mit Datum in `docs/guidance/quellen.md` vermerkt.
- Der Auftraggeber liest den Katalog vor der Freigabe einmal durch.
- Eine Schwelle lässt sich im Katalog ändern; der Bericht vermerkt im Kopf, dass Schwellen vom ausgelieferten Stand abweichen.
- Ein Katalogeintrag, dem Quelle, Art oder Texte fehlen oder der einen unbekannten Wert verlangt, wird beim Laden mit einer verständlichen Meldung abgelehnt.

## 5. Darstellung

### 5.1 Geführte Ansicht

- **Zeile „Zustand des Workers"** auf der Startseite unter dem Lagebild: die zehn Bereiche als Kacheln mit ihrer Einstufung in fester Reihenfolge, darüber eine Zusammenfassung („1 Bereich zum Handeln, 4 zum Prüfen, 5 in Ordnung").
- **Bereichsansicht:** die Prüfungen des Bereichs, auffällige zuerst, je Prüfung Befund, Einstufung, „Was bedeutet das?", „Was tun?", Quelle.
- **Verweis im Vorfall:** fester Abschnitt „Dazu im Zustandsbild" mit den Prüfungen, deren Bezug zur Art oder zu einem Muster des Vorfalls passt und die nicht „in Ordnung" sind. Formulierung: „kann beitragen", nie „ist die Ursache". Passt keine, entfällt der Abschnitt.
- **Text kopieren:** Jede Prüfung und jeder Bereich hat den Kopierknopf des geführten Berichts mit dem Schalter „ohne Namen".

### 5.2 Expertenansicht

- Eine Tabelle aller Prüfungen: Bereich, Prüfung, Wert, Einstufung, Art, Quelle; filterbar nach Einstufung und Bereich.
- Darunter die gelesenen Rohwerte, auch solche ohne Prüfung im Katalog.
- Der gemeinsame Zeitbereich wirkt auf das Zustandsbild nicht; ein Hinweis nennt den Lesezeitpunkt.

### 5.3 Zustandsbericht aus dem Schnelllauf

Kopf, Zeile „Zustand des Workers", Bereichsansichten, Rückblick. Im Kopf steht „Zustandsbericht ohne Messung". Vorfälle, Diagramme und Sitzungstabellen entfallen; es steht nirgends „keine Vorfälle".

### 5.4 Kopf

Lesezeitpunkt und Dauer des Zustandsbilds; Hinweis auf geänderte Schwellen; Zahl der nicht prüfbaren Prüfungen.

### 5.5 Geräte

Gebaut für den PC; auf dem Telefon lesbar und ohne waagerechtes Scrollen.

## 6. Verhältnis zu anderen Teilen

- **Messkategorien:** `Zustand` ist eine Kategorie; der Schnelllauf ist der Lauf ohne Messreihen.
- **Ereignisse und Drucken:** Das Ereignisbild nutzt den Rückblick, der Bereich Drucken die Treiberliste. Sind diese Kategorien abgewählt, sind die abhängigen Prüfungen „nicht prüfbar".
- **Maskierung:** Die Namenssammlung liest `health.json` mit. Werte, die Namen tragen (Pfade, Server, Freigaben, Konten), werden nach den Stufen der Maskierung ersetzt; die Feldliste und der Markertest der Maskierung werden um die neuen Felder ergänzt.
- **Prüfskript:** bleibt unverändert.

## 7. Tests

- Bewertung: jede Einstufung einzeln, auch „nicht prüfbar"; „handeln" entsteht nur bei harter Grenze oder bei Dauerzustand mit Ereignis.
- Katalog: fehlerhafte Einträge werden abgelehnt; eine geänderte Schwelle erscheint im Kopf.
- Lesen unter Windows über die Platzhalter mit erfundenen Werten: ein fehlgeschlagener Bereich stoppt die anderen nicht; das Zeitlimit greift.
- Schnelllauf: Aufzeichnung ohne Messreihen; der Zustandsbericht entsteht ohne Fehler.
- Verweis im Vorfall: die simulierte Stunde zeigt beim Absturz des Druckdienstes die Treiberprüfung.
- Maskierung: kein Name aus `health.json` steht im maskierten Bericht.
- Alte Aufzeichnungen ohne `health.json` bleiben lesbar.
- Seite: Kacheln, Bereichsansicht, Verweis, Kopiertext, schmale Breite, beide Farbschemata.

## 8. Erster echter Lauf

Der Baustein gilt erst nach einem Schnelllauf auf dem Test-Worker als fertig. Er zeigt, welche Werte unter den vorhandenen Rechten lesbar sind, wo die Einstellungen von Citrix und der Profilverwaltung tatsächlich liegen und wie lange das Lesen dauert. Das Ergebnis wird hochgeladen, bleibt außerhalb des Repositorys und führt zu einer Anpassung von Lesewegen und Katalog.

## 9. Grenzen

- Stand zum Startzeitpunkt; Änderungen während der Messung sieht das Zustandsbild nicht.
- Es zeigt Abweichungen von Empfehlungen, keine Ursachen.
- Kein Sicherheits- oder Lizenzaudit, nicht vollständig.
- Empfehlungen ändern sich; die Quellen tragen ein Datum, der Katalog braucht gelegentlich eine Durchsicht.
- Für Arctic Wolf Aurora und Nexus KIS wird nur geprüft, was allgemein lesbar ist (Vorhandensein, Dienste, Filtertreiber).
- Nur der Worker selbst; Dateiserver, Controller, Hypervisor und Netzwerk erscheinen nur aus seiner Sicht.

## 10. Spätere Erweiterungen (nicht Teil dieses Entwurfs)

- Vergleich mit dem vorigen Lauf („seit der letzten Prüfung geändert"); das Format aus Abschnitt 3 lässt ihn zu.
- Eigene Vorgaben des Auftraggebers als zweite Bewertungsgrundlage.
- Aktive Tests (Namensauflösung, Antwortzeit zur Profilfreigabe, Zerlegung der Anmeldedauer).

## 11. Offene Punkte

- Welche Werte der Citrix-Richtlinien und der Profilverwaltung sich ohne Citrix-Werkzeuge zuverlässig lesen lassen, zeigt der erste echte Lauf.
- Ob das Ziel „unter einer Minute" auf einem Worker mit vielen Containern und geplanten Aufgaben hält, zeigt der erste echte Lauf.

## Anhang: Der Einhängepunkt `Zustand` (Stand nach dem Plan Messkategorien)

Der Plan Messkategorien hat die Kategorie `Zustand` vorbereitet: Es gibt die Zeile in `$script:WorkerPerfCategories` (`Active = $false`). Die beiden Texte (`skip.label.Zustand`, `skip.text.Zustand`) und eine Abfrage der Kategorie im Collector gibt es noch nicht; der Umsetzungsplan legt sie an (berichtigt am 13.11.2026: eine frühere Fassung dieses Anhangs nannte sie als vorhanden). Auflösung von `-Skip`, Startmeldung, Lader, Vermerk in den Quellen und die Seite nehmen eine aktive Kategorie von selbst auf. Der Umsetzungsplan für das Zustandsbild muss darüber hinaus vier Dinge regeln:

1. **Kein CSV-Schreiber.** `health.json` ist keine Datei aus `$script:WorkerPerfHeaders`. Die Regel des Collectors „fehlender Schreiber heißt kein Aufruf" trägt diese Kategorie nicht; sie braucht eine eigene Abfrage.
2. **Aufzeichnungen von vor dem Zustandsbild.** Sie haben weder `health.json` noch `Zustand` in `Skip`. Der Satz „Aufzeichnungen ohne die neue Angabe gelten als vollständig gemessen" stimmt für sie nicht. Eigene Regel: Fehlt die Datei und nennt `Skip` die Kategorie nicht, heißt das „nicht aufgezeichnet"; der Lader meldet es weder als weggelassen noch als gemessen.
3. **Tests, die das heutige Verhalten festschreiben und sich mit der Aktivierung ändern:** `tests/Common.Tests.ps1` (`' Zustand '` ergibt keinen Eintrag; die Dateien der Tabelle sind genau die CSV-Dateien außerhalb der Basis), `tests/Skip.Tests.ps1` (`$Names` mit sieben Einträgen, die Startmeldung, der Lauf „Zustand: ohne Wirkung"), `tests/Mask.Tests.ps1` (`abgeschaltet (-Skip Zustand)` muss geleert werden), `New-SkipRuns` in `tests/TestHelpers.ps1` (ein achter Lauf), `checkSkip` und `SKIP_LOCATIONS` in `tests/report-browser.js`.
4. **Hilfe und README** sagen heute, `Zustand` werde angenommen und habe noch keine Wirkung. Beides ändert sich mit der Aktivierung.
