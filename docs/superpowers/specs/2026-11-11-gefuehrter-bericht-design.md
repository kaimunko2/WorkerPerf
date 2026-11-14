# Geführter Bericht und Expertenansicht – Entwurf

Stand: 11.11.2026. Baut auf `2026-11-10-engpassanalyse-design.md` auf und ersetzt dort den Abschnitt zum Aufbau der Berichtsseite. Wird nach `2026-11-11-ereignisse-abstuerze-drucken-design.md` und `2026-11-11-maskierung-design.md` umgesetzt und setzt deren Daten voraus: Vorfälle aus Ereignissen mit ihren Mustern, den Rückblick, den Druckzustand und die Maskierung.

## 1. Ziel

Ein Windows-Administrator ohne tiefe Systemkenntnisse soll mit dem Bericht ein gemeldetes Performance-Problem selbst eingrenzen können. Der Bericht führt ihn in dieser Rangfolge:

1. **Handeln:** Zu jedem Vorfall stehen konkrete Prüfschritte und, als Vorschlag gekennzeichnet, übliche Abhilfe.
2. **Weitergeben:** Jeder Vorfall und die ganze Messung lassen sich als kurzer Text in ein Ticket oder eine E-Mail kopieren.
3. **Verstehen:** Jeder Vorfall ist in Alltagssprache erklärt und in Benutzersicht eingeordnet.

Zugleich wird der Bericht übersichtlicher und zeitgemäß gestaltet: eine geführte Ansicht als Standard und eine Expertenansicht für die Tiefe.

Erfolgskriterien:

- Ein Administrator findet nach dem Öffnen ohne Scrollen heraus, ob Handlungsbedarf besteht, und ist mit einem Klick beim ersten Prüfschritt des wichtigsten Vorfalls.
- Keine Empfehlung erscheint, die die Messung nicht stützt.
- Alle heutigen Inhalte des Berichts bleiben erreichbar.

## 2. Abgrenzung

Unverändert bleiben: Collector, Datenformat, Datenquellen, die Erkennung von Befunden, Vorfällen und Verursachern, Schwellen und Rollen. Vorhandene Aufzeichnungen lassen sich mit dem neuen Bericht erneut auswerten.

Unverändert bleiben auch die technischen Leitplanken der Seite: eine einzelne HTML-Datei, keine nachgeladenen Inhalte, keine eingebundenen Schriften oder Bibliotheken, Systemschrift, nutzbar offline und von einer Freigabe, Skripte kompatibel zu Windows PowerShell 5.1 und rein in ASCII.

Nicht Teil dieses Vorhabens: eine Druckansicht, eine eigene Ausgabe für Hersteller, kopierbare Befehle in den Handlungsschritten, volle Bedienbarkeit der Expertenansicht auf dem Handy.

## 3. Aufbau und Navigation

Eine Datei, zwei Ansichten. Ein Umschalter „Geführt | Experte" sitzt oben rechts. Der Bericht öffnet in der geführten Ansicht; die zuletzt gewählte Ansicht merkt er sich für diese Datei im Browser.

### 3.1 Geführte Ansicht

Drei Ebenen:

1. **Lagebild** (Startseite)
   - Ein farbiges Band nennt den Gesamtzustand in einem Satz und fünf Kennzahlen: Engpässe auf dem Server, Verzögerungen von außen, Abstürze und Fehler (Vorfälle aus Ereignissen), Dauerzustände, Minuten mit spürbarer Störung. Das ist die Gesamtdauer der Zeitfenster aller Vorfälle, die keine Dauerzustände sind; überlappende Fenster zählen einmal.
   - Die Bandfarbe folgt dem Zustand: rot bei mindestens einem Engpass, einer kritischen Verzögerung oder einem Vorfall aus Ereignissen in einer Benutzersitzung, gelb bei bloßen Auffälligkeiten und Dauerzuständen, grün ohne Vorfall. Der Zustand steht zusätzlich als Symbol und Wort im Band.
   - Knöpfe im Band: „Wichtigsten Vorfall öffnen", „Zusammenfassung kopieren".
   - Unter dem Band stehen Hinweise zur Messung, wenn sie die Aussage einschränken: fehlende Messwerte, nicht regulär oder mit Fehler beendete Aufzeichnung.
   - Darunter die Zeitleiste der Messung; eine Markierung öffnet ihren Vorfall.
2. **Vorfallskarten**, die wichtigsten zuerst. Reihenfolge: Engpässe, kritische Verzögerungen und Vorfälle aus Ereignissen vor Dauerzuständen; darin nach Zahl der betroffenen Sitzungen, dann nach Dauer, dann nach Uhrzeit. Eine Karte zeigt: Einordnung in Benutzersicht, Uhrzeit und Dauer, Titel in Alltagssprache, einen Satz zur Wirkung, Verursacher oder Hinweis, den ersten Schritt, die Knöpfe „Öffnen" und „Kopieren" sowie ein Kürzel der betroffenen Ressource.
3. **Vorfallsansicht** (Abschnitt 4), erreichbar über Karte oder Zeitleiste, mit „Zurück zum Lagebild" und „Nächster Vorfall".

Unter den Karten folgen eingeklappt „Was wurde gemessen, was nicht" und „Messqualität" mit den heutigen Inhalten.

### 3.2 Expertenansicht

Sie enthält die heutigen Inhalte der Reiter Übersicht, Sitzungen, Anwendungen und Prozesse sowie die Soll-Ist-Tabelle und die Messqualität:

- **Vorfallsspalte** links mit allen Vorfällen (Status, Zeit, Art, Verursacher). Ein Klick setzt den Zeitraum auf den Vorfall mit Vor- und Nachlauf und hebt ihn in allen Diagrammen hervor. Jeder Eintrag führt auch in seine geführte Vorfallsansicht.
- **Zeitraumleiste** oben: zeigt immer den geltenden Zeitraum und einen Knopf „Gesamte Messung".
- **Kacheln** je Messwert: Maximum, Status als Symbol und Wort, Zeitanteil über dem Soll, bezogen auf den geltenden Zeitraum.
- **Diagramme** mit gemeinsamer Zeitachse, aufteilbar nach Host, Sitzung oder Anwendung.
- **Tabellenbereich** mit den Reitern Soll-Ist, Sitzungen, Anwendungen, Prozesse, Messqualität.

**Ein gemeinsamer Zeitraum.** Er wird gesetzt durch Klick auf einen Vorfall, durch Ziehen in einem Diagramm oder durch „Gesamte Messung". Diagramme, Kacheln, Soll-Ist und alle Tabellen beziehen sich immer auf denselben Zeitraum. Wer im Zeitraum nicht aktiv war, erscheint nicht in den Tabellen. Stützen sich Tabellenwerte auf weniger als drei Schnappschüsse, steht die Zahl der Schnappschüsse dabei.

### 3.3 Verbindung der Ansichten

Aus der Vorfallsansicht führt „In der Expertenansicht zeigen" in die Expertenansicht mit dem Zeitraum dieses Vorfalls. Die Adresse der Seite hält Ansicht, Vorfall und Zeitraum fest; die Zurück-Taste des Browsers führt innerhalb des Berichts zurück, und ein Lesezeichen öffnet dieselbe Stelle.

### 3.4 Was entfällt

Die fünf Reiter in ihrer heutigen Form. Kein Inhalt entfällt.

## 4. Vorfallsansicht

Immer dieselben Abschnitte in derselben Reihenfolge. Dauerzustände nutzen dieselbe Seite; Abschnitt 1 sagt dann, dass der Zustand über die ganze Messung oder einen großen Teil anhielt.

**Kopf:** Titel in Alltagssprache, darunter klein die Fachbezeichnung; Zeit, Dauer, Einordnung in Benutzersicht („spürbar für 4 Sitzungen, 3,8 Minuten"); Knöpfe „Zusammenfassung kopieren", „In der Expertenansicht zeigen", „Zurück", „Nächster Vorfall".

1. **Was war los:** zwei bis drei Sätze, was passiert ist und was die Benutzer davon merkten; daneben ein kleines Diagramm des auslösenden Messwerts mit Soll-Linie.
2. **Wer oder was hat es verursacht:** Hauptverursacher mit Anwendung, Benutzer, Anteil und üblichem Wert; Begleiter; die Aussage „kein einzelner Hauptverursacher", wo sie gilt; bei Verzögerungen ohne Engpass der Hinweis, dass die Ursache außerhalb liegt, und was dafür spricht.
3. **Was ist zu tun:** nummerierte Prüfschritte, die naheliegendsten zuerst, jeweils mit „was, wo, woran erkennbar"; abgesetzt „Mögliche Abhilfe" als Vorschlag, jeweils mit ihrer Bedingung („Wenn …, dann …"); wo sinnvoll „An wen wenden".
4. **Wer war betroffen:** betroffene Sitzungen mit Benutzer, Client und höchster Verzögerung; ist die Eingabeverzögerung nicht gemessen, steht dort, dass die Betroffenen nicht bestimmbar sind.
5. **Belege** (eingeklappt): Messwerte, beteiligte Prozesse, Ereignisse, Werte der Gegenstellen, der heutige Fachsatz des Vorfalls, und was nicht gemessen wurde.

Unvermeidbare Fachbegriffe sind unterlegt und erklären sich beim Antippen oder Überfahren. Die Begriffe und Erklärungen stehen im Katalog (Abschnitt 5).

## 5. Katalog und Auswahlregeln

### 5.1 Datei

`src/guidance.de.json`, neben Schwellen, Rollen und Texten. Sie enthält alle Erklärungen und Handlungsanleitungen des Berichts; im Code steht davon nichts. Über einen Parameter `-GuidanceFile` des Auswertungsskripts lässt sich eine eigene Datei angeben. Die verwendete Fassung wird wie die Schwellen in die Berichtsdaten übernommen.

### 5.2 Situationen

Eine Situation ist die Art des Vorfalls plus die führende Ressource. Zum Start:

| Kennung | Situation |
|---|---|
| `cpu` | CPU-Engpass |
| `memory` | Arbeitsspeicher-Engpass |
| `disk` | Datenträger-Engpass (lokales Laufwerk) |
| `share` | Dateiserver-Engpass (Freigabe) |
| `profile` | Profilcontainer-Engpass |
| `delay.many` | Verzögerung ohne Engpass, mehrere Sitzungen |
| `delay.single` | Verzögerung ohne Engpass, eine Sitzung oder Anwendung |
| `chronic.network` | Dauerzustand der Netzstrecke eines Benutzers |
| `chronic.resource` | Dauerzustand einer Server-Ressource |
| `crash` | Anwendungsabsturz |
| `hang` | Anwendungshänger |
| `service` | Dienstausfall |
| `print` | Druckproblem |
| `profileerror` | Profilproblem |
| `system` | Systemfehler (Datenträger, Speichermangel, Verbindungsabbruch) |
| `fallback` | Auffang-Eintrag |

Jede Situation, die die Auswertung erzeugen kann, wird genau einer Kennung zugeordnet; was nicht zuzuordnen ist, erhält `fallback`.

### 5.3 Inhalt eines Eintrags

- `title`: Titel in Alltagssprache
- `meaning`: „Was war los", zwei bis drei Sätze
- `impact`: Wirkung auf die Benutzer, ein Satz
- `checks`: Prüfschritte, je mit Text, Ort und Erkennungsmerkmal, optional mit Bedingung
- `remedies`: Abhilfevorschläge, je mit ihrer Voraussetzung in Worten, optional mit Bedingung
- `contact`: an wen wenden, optional mit Bedingung
- `short`: Kürzel der Ressource für die Karte

Dazu ein gemeinsamer Abschnitt `terms` mit Fachbegriffen und ihren Erklärungen.

Ergänzt während der Umsetzung: Ein Eintrag kann im freiwilligen Feld `impactVariants` andere Fassungen der Wirkung angeben, jede mit einer Liste von Bedingungen (`when`, mindestens eine, Bedingungen nach Abschnitt 5.4) und einem Text (`text`). Eine Variante wird gebraucht, wo `impact` sonst etwas als Tatsache sagen würde, was die Messung nicht gemessen hat, etwa eine Verzögerung der Eingaben, obwohl die Eingabeverzögerung nicht gemessen wurde (`unmeasured.input.session`). Die Auswertung nimmt die erste Variante in der Reihenfolge der Datei, deren Bedingungen alle zutreffen; trifft keine zu, gilt `impact`. Wie `impact` enthält eine Variante nur Platzhalter, für die jeder Vorfall einen Wert hat; die Prüfung der Datei verlangt das. Aus derselben Durchsicht stammt eine Regel für den Satz eines Vorfalls aus Ereignissen: „immer dasselbe“ sagt er von einem fehlerhaften Modul nur, wenn mehr als ein Ereignis das Modul nennt; ein einzelnes Ereignis nennt nur sein Modul.

### 5.4 Bedingungen

Schritte, Vorschläge und Kontakte können an Bedingungen hängen. Eine Bedingung ist eine benannte Tatsache, die das Auswertungsskript aus dem Vorfall ableitet:

| Bedingung | Gilt, wenn |
|---|---|
| `cause.app` | ein Hauptverursacher ist benannt und keine Schutzsoftware |
| `cause.security` | Schutzsoftware ist größter Verbraucher |
| `cause.none` | kein einzelner Hauptverursacher |
| `cause.nodata` | keine Prozessdaten im Fenster |
| `scan` | im Fenster lief ein Virenscan |
| `companion.security` | Schutzsoftware ist Begleiter |
| `role.<Rolle>` | der Verursacher gehört laut Rollenliste zu dieser Rolle |
| `app.<Anwendung>` | der Verursacher (bei Ereignisvorfällen die betroffene Anwendung) gehört zu dieser Standardanwendung aus `src/apps.json` (ergänzt am 13.11.2026; zum Start Microsoft Edge, Microsoft Office, Microsoft Teams) |
| `endpoint.slow` | eine Gegenstelle antwortete im Fenster über ihrer Schwelle |
| `event.applocker`, `event.defender` | ein solches Ereignis liegt im Fenster |
| `unmeasured.<Signal>` | dieses Signal war nicht gemessen |
| `affected.many`, `affected.one`, `affected.unknown` | Zahl der betroffenen Sitzungen |
| `chronic` | der Vorfall ist ein Dauerzustand |
| `pattern.<Muster>` | dieses Muster des Abgleichs trifft zu (`resource`, `afterhang`, `sharedmodule`, `printdriver`, `securitymodule`, `manyusers`, `oneuser`, `companion`, `overlap`) |
| `pattern.none` | kein Muster trifft zu |
| `driver.v3`, `driver.v4` | Bauart des beteiligten Druckertreibers |
| `driver.shared`, `driver.isolated` | der beteiligte Druckertreiber läuft nicht isoliert bzw. isoliert |
| `driver.vendor.<Hersteller>` | Hersteller des beteiligten Druckertreibers |
| `spooler.crash` | die Druckwarteschlange ist ausgefallen |
| `queue.stuck` | Aufträge blieben hängen oder Drucker waren „nicht bereit" |
| `before` | der Vorfall stammt aus dem Rückblick vor der Messung |

Ein Element ohne Bedingung gilt immer. Ein Element mit Bedingung erscheint nur, wenn sie zutrifft; mehrere Bedingungen eines Elements müssen alle zutreffen. Elemente mit zutreffender Bedingung stehen vor denen ohne Bedingung, sonst gilt die Reihenfolge der Datei.

### 5.5 Platzhalter

Texte können Platzhalter enthalten: Benutzer, Anwendung, Anteil, üblicher Wert, Messwert mit Einheit, Soll, Uhrzeit von und bis, Dauer, Zahl der betroffenen Sitzungen, Name der Ressource (Laufwerk, Freigabe), Name und Wert der Gegenstelle, Name der Schutzsoftware. Fehlt der Wert eines Platzhalters im Vorfall, entfällt das ganze Element; der Bericht zeigt keinen Text mit Lücke.

### 5.6 Regeln

- **Ehrlichkeit:** Der Bericht empfiehlt nichts, was die Messung nicht stützt. Trifft keine Bedingung zu, erscheinen nur die allgemeinen Elemente der Situation.
- **Auffang:** Der Eintrag `fallback` erklärt, dass keine spezifische Anleitung vorliegt, und nennt nur allgemeine Prüfschritte.
- **Prüfung der Datei:** Beim Laden werden Aufbau, Pflichtfelder, bekannte Bedingungen und bekannte Platzhalter geprüft. Ein Fehler bricht die Auswertung mit einer Meldung ab, die Eintrag und Feld nennt.

### 5.7 Druckempfehlungen

Die Situation `print` und die Varianten zu `pattern.printdriver` enthalten die Empfehlungen zum Drucken in Citrix-Umgebungen von Microsoft, Citrix, HP, Kyocera und Brother. Sie werden für den Katalog recherchiert. Jedes Element nennt in einem Feld `source` den Hersteller und den Titel der Quelle; der Bericht zeigt die Quelle beim Element. Eine Empfehlung ohne belegbare Quelle wird nicht aufgenommen. Herstellerspezifische Elemente hängen an `driver.vendor.<Hersteller>` und erscheinen nur, wenn ein Treiber dieses Herstellers beteiligt war.

Ergänzt am 13.11.2026 auf Wunsch des Auftraggebers: Neben den Quellen der Hersteller dürfen in allen Situationen Empfehlungen aus zwei Quellen der Praxis aufgenommen werden, dem Base Image Script Framework (BIS-F) und den Anleitungen von Carl Stalhood (carlstalhood.com). Ein solches Element nennt in `source` die Quelle mit dem Zusatz „Empfehlung aus der Praxis" und den Titel, wird nie als Empfehlung des Herstellers formuliert und steht mit Adresse und Abrufdatum im Nachweis `docs/guidance/quellen.md`. Widerspricht eine Quelle aus der Praxis dem Hersteller, gilt der Hersteller. Ausnahmen legt der Auftraggeber fest (festgelegt am 13.11.2026: beim Energiesparplan gelten die Praxisquellen). Am 13.11.2026 hat der Auftraggeber nach Sichtung einer Kandidatenliste weitere Praxisquellen übernommen: GO-EUC (go-euc.com), James Kindon (jkindon.com), James Rankin (james-rankin.com), Thomas Kötzing (koetzingit.de) und, für einzelne Themen, Manuel Winkel (deyda.net), Aaron Parker (stealthpuppy.com), Trentent Tye (trentent.github.io), John Billekens (ave.j81.nl), Guy Leech und Benny Tritsch (EUC Score). Für sie gelten dieselben Regeln. Der ebenfalls übernommene Blog von Kasper Johansen ist nicht mehr erreichbar (Recherche vom 13.11.2026: unter seiner früheren Adresse steht kein Blog mehr); er wird nicht verwendet und steht ohne Adresse im Nachweis. Verwendbar sind damit zehn dieser Quellen, mit BIS-F und Carl Stalhood zwölf Praxisquellen. Die geltende Liste der Praxisquellen steht in `docs/guidance/quellen.md`; eine Quelle kommt nur mit Zustimmung des Auftraggebers hinzu.

### 5.8 Inhalt

Die Texte entstehen auf Grundlage der Herstellerempfehlungen von Microsoft und Citrix und der Eigenheiten der Zielumgebung (Citrix-Profilcontainer, Schutzsoftware, AppLocker, Proxy, Fachanwendung mit Datenbank; seit 13.11.2026 festgehalten: ausschließlich über Machine Creation Services bereitgestellte, nicht persistente Shared-Session-Worker, deren Ereignisprotokolle einen Neustart nicht überdauern; die Benutzerumgebung wird mit Citrix Workspace Environment Management eingerichtet, die Drucker ordnet PrinTaurus SmartSpread (AKI GmbH) zu, nicht die Citrix-Richtlinien). Vorschläge, die eine Einstellung ändern, nennen deshalb das Master-Image oder die Richtlinie als Ort der Änderung. Der fertige Katalog wird dem Auftraggeber vor der Übernahme gesondert zur fachlichen Durchsicht vorgelegt. Nach den ersten realen Messungen wird er einmal nachgeschärft.

Sprachregel (Auftraggeber, 13.11.2026): In allen Texten, die der Bericht zeigt oder zum Kopieren anbietet, heißt die gemessene Maschine durchgehend „Server“, nicht „Worker“. Das gilt für die Texte des Katalogs, die Sätze der Auswertung, die Beschriftungen der Seite und die Kopiertexte; der Name des Werkzeugs (WorkerPerf) und Kennungen im Code bleiben.

## 6. Zusammenfassung zum Kopieren

- **Je Vorfall:** Knopf „Kopieren" auf der Karte und in der Vorfallsansicht.
- **Für die Messung:** Knopf „Zusammenfassung kopieren" im Lagebild: Kopf mit Server und Zeitraum, Lagebild in einem Satz, danach alle Vorfälle in Kurzform.

Format: reiner Text ohne Formatierung, Zeilen höchstens 78 Zeichen. Ein Vorfall enthält: Kopfzeile mit Server und Datum, Zeit und Dauer mit Titel, Wirkung, Messwert mit Soll, Verursacher oder Hinweis, Betroffene, empfohlene Prüfschritte, mögliche Abhilfe als Vorschlag. Der Text stimmt inhaltlich mit der Vorfallsansicht überein.

**Schalter „ohne Namen":** Der Text nutzt die Ersatznamen der Maskierung in der Stufe `Alles` (siehe `2026-11-11-maskierung-design.md`), also dieselben wie ein maskierter Bericht derselben Aufzeichnung. Anwendungsnamen bleiben.

Das Auswertungsskript setzt beide Fassungen zusammen und legt sie in die Berichtsdaten.

**Kopieren im Browser:** erst über die Zwischenablage-Schnittstelle, sonst über den älteren Kopierbefehl; schlägt beides fehl, öffnet sich ein Feld mit dem bereits markierten Text. Nach Erfolg bestätigt der Knopf kurz mit „Kopiert".

## 7. Gestaltung und Dynamik

- **Zwei Erscheinungsbilder:** geführte Ansicht hell und großzügig mit farbigem Lagebild-Band und Karten; Expertenansicht dunkel und dicht. Beide nutzen dieselben Bausteine (Statuskennzeichen, Knöpfe, Karten, Diagramme, Tabellen) und unterscheiden sich in Farben und Abständen.
- **Status** steht immer als Symbol und Wort (◆ kritisch, ▲ auffällig, ● normal), nie nur als Farbe.
- **Bewegung:** Überblenden beim Wechsel der Ebenen; Gleiten von Diagrammen und Kacheln bei geändertem Zeitraum; gegenseitiges Hervorheben von Vorfall und Zeitfenster; Fadenkreuz mit Uhrzeit, Wert und Status in Diagrammen; Bestätigung an Knöpfen. Bewegungen dauern unter 250 ms und entfallen, wenn das Betriebssystem „Bewegung reduzieren" meldet.
- **Bedienung:** alles mit der Tastatur erreichbar, sichtbarer Fokus, Esc schließt die Vorfallsansicht.
- **Diagramme:** selbst gezeichnet wie bisher; eine Achse je Diagramm; Soll-Bereich und Schwelle einheitlich dargestellt; dünne Linien, zurückhaltendes Raster. Die Farben der aufgeteilten Diagramme werden rechnerisch auf Unterscheidbarkeit geprüft, auch bei Farbfehlsichtigkeit, für beide Erscheinungsbilder.
- **Geräte:** Zielgerät ist der PC. Bei schmaler Breite stehen alle Bereiche in einer Spalte, ohne seitliches Scrollen der Seite; breite Tabellen scrollen in sich.

## 8. Sonderfälle

- **Kein Vorfall:** grünes Band „Keine Störung erkannt"; darunter, was gemessen wurde und was nicht, und einzelne Überschreitungen ohne Befund. Mit `-ReportedTime` zeigt der Bericht zusätzlich die Messwerte um die gemeldete Zeit.
- **Viele Vorfälle:** Die Startseite zeigt die zehn wichtigsten als Karten, die übrigen als kompakte Liste. Vorfälle derselben Situation mit demselben Verursacher werden in der Liste zusammengefasst angeboten („6-mal CPU-Engpass durch … von …") und lassen sich aufklappen.
- **Unvollständige Messung:** Hinweise stehen direkt unter dem Band (Abschnitt 3.1).
- **Katalog ohne passenden Eintrag:** Auffang-Eintrag mit sichtbarem Hinweis.
- **Kurzer Zeitraum in der Expertenansicht:** Angabe der Zahl der Schnappschüsse (Abschnitt 3.2).
- **Vorfälle vor der Messung:** Der Rückblick erscheint in der geführten Ansicht als eigener Bereich „Vor der Messung" unter den Karten, mit denselben Karten und derselben Vorfallsansicht. Abschnitt 1 der Vorfallsansicht sagt dort, dass für diese Zeit keine Messwerte vorliegen; das Diagramm entfällt. Diese Vorfälle zählen nicht in die Kennzahlen des Bands. In der Expertenansicht stehen sie in einem eigenen Reiter.
- **Maskierter Bericht:** Alle Texte der Anleitung und der Kopiertexte entstehen vor der Maskierung und werden mit den übrigen Berichtsdaten maskiert; der Schalter „ohne Namen" entfällt dann.

## 9. Bausteine

| Baustein | Aufgabe | Schnittstelle |
|---|---|---|
| `src/guidance.de.json` | Texte und Handlungsanleitungen | Aufbau nach Abschnitt 5 |
| Katalog laden und prüfen | liest und prüft die Datei | liefert den Katalog oder eine Fehlermeldung mit Eintrag und Feld |
| Situation und Bedingungen bestimmen | leitet aus einem Vorfall Kennung und Tatsachen ab | Vorfall → Kennung, Liste der Bedingungen, Werte der Platzhalter |
| Anleitung zusammenstellen | wählt und füllt die Elemente | Katalog, Kennung, Bedingungen, Werte → fertige Anleitung |
| Rangfolge und Lagebild | ordnet die Vorfälle, bildet Kennzahlen und Zustand | Vorfälle → Reihenfolge, Lagebild |
| Kopiertexte | bildet beide Fassungen je Vorfall und für die Messung | Anleitung, Vorfall → Text mit und ohne Namen |
| Berichtsdaten | nimmt Anleitung, Lagebild, Rangfolge und Texte auf | neue Felder neben den bisherigen |
| Berichtsseite | zeigt beide Ansichten aus denselben Daten | liest nur die Berichtsdaten |

Die Auswahl der Anleitung, die Rangfolge und die Kopiertexte entstehen im Auswertungsskript, nicht in der Seite. Die neuen Funktionen liegen in einer eigenen Skriptdatei neben `WorkerPerf.Findings.ps1`.

## 10. Tests

- **Auswahlregeln:** je Situation und Bedingung genau die erwarteten Elemente; nicht gestützte Elemente erscheinen nicht; ein Element mit fehlendem Platzhalterwert entfällt.
- **Katalog:** jeder Eintrag vollständig; jede Bedingung und jeder Platzhalter bekannt; jede erzeugbare Situation hat einen Eintrag; fehlerhafte Datei ergibt die Meldung mit Eintrag und Feld.
- **Simulierte Stunde:** für alle Vorfälle, die acht Leistungsvorfälle und die Vorfälle aus Ereignissen, stehen Kennung, Titel, Wirkung, erster Schritt, Rangfolge und Kopiertext fest; das Lagebild nennt die erwarteten Kennzahlen.
- **Druckempfehlungen:** jedes Element der Situation `print` trägt eine Quelle; herstellerspezifische Elemente erscheinen nur beim passenden Hersteller.
- **Kopiertext:** die Fassung ohne Namen enthält keinen Benutzer-, Client-, Server- oder Freigabenamen der Messung; Zeilenlänge eingehalten.
- **Seite im Browser:** Umschalten der Ansichten; Öffnen eines Vorfalls über Karte und Zeitleiste; gemeinsamer Zeitraum über Diagramme, Kacheln und Tabellen; Zurück-Taste; Adresse; Kopieren mit beiden Wegen und dem Ausweichfeld; Tastaturbedienung; schmale Breite ohne seitliches Scrollen; kein Vorfall; viele Vorfälle.
- **Bestand:** die bisherigen Tests bleiben grün; die Browser-Prüfungen werden auf den neuen Aufbau umgestellt, ohne eine Aussage fallen zu lassen.

## 11. Reihenfolge der Umsetzung

1. Katalog, Auswahlregeln, Rangfolge, Lagebild und Kopiertexte im Auswertungsskript. Danach Durchsicht des Katalogs durch den Auftraggeber.
2. Geführte Ansicht: Lagebild, Karten, Vorfallsansicht, Kopieren.
3. Expertenansicht mit gemeinsamem Zeitraum.
4. Übergänge, Tastatur, Adresse, schmale Breite.
5. README und Demo-Seite.

## 12. Offene Punkte

- Die Texte des Katalogs sind erst an realen Aufzeichnungen zu bewerten.
- Die Schwelle, ab der eine Gegenstelle als langsam gilt, kommt aus den bestehenden Schwellen; ob sie für die Bedingung `endpoint.slow` passt, zeigt die erste reale Messung.
