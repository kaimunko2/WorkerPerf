# WorkerPerf: Engpassanalyse nach Störungsmeldung – Design

Stand: 10.11.2026 · Status: Entwurf zur Durchsicht

## 1. Ziel

Ein Anwender meldet Performance-Probleme in seiner Citrix-Sitzung. Ein Administrator startet
daraufhin gezielt eine Messung auf einem ausgewählten Worker (produktiv oder Test-Worker) und
erhält aus den Daten eine belastbare Aussage:

- **Gab es einen Engpass**, und bei welcher Ressource (CPU, Arbeitsspeicher, Datenträger,
  Dateiserver, Netzstrecke)?
- **Wer war betroffen** (welche Sitzungen haben es gespürt)?
- **Wer oder was hat ihn ausgelöst** (Benutzer, Anwendung, Prozess)?
- **Wie weit liegt der Worker vom Soll-Zustand entfernt** (Vergleich mit gängigen Richtwerten)?

Erfolgskriterien:

1. Für die Beschwerdebilder „zähes Arbeiten", „kurze Hänger" und „langsame Anwendungen/Dateizugriffe"
   liefert der Bericht ohne manuelles Suchen eine Liste von Vorfällen mit Ressource, Betroffenen
   und Verursachern.
2. Eine Messung über 8 Stunden auf einem Worker mit 1.500 Prozessen bleibt unter 100 MB.
3. Wurde nichts gefunden, sagt der Bericht das ausdrücklich und weist aus, was gemessen werden
   konnte und was nicht.
4. Jeder Messwert im Bericht ist gegen einen Soll-Bereich mit ausgewiesener Herkunft bewertet.

## 2. Rahmenbedingungen

- Zielsystem: Windows Server 2022 Multi-Session-VDA auf VMware, Windows PowerShell 5.1.
- Einsatz: gesteuert auf einzelnen Workern, Start direkt auf dem Worker (RDP/Konsole), Dauer
  typischerweise mehrere Stunden. Kein Dauerbetrieb in der Fläche.
- Weiterhin keine Installation, keine Module, sprachneutrale Datenquellen.
- Fokus bleibt: Ressourcen des Servers, ihre Nutzung, Engpässe und deren Verursacher.
- Umgebung des Auftraggebers: Citrix Profile Management mit Containerprofil, Microsoft Defender,
  Arctic Wolf Aurora Endpoint Protection, AppLocker, FortiGate als Proxy und Firewall für externe
  Zugriffe, Hauptanwendung Nexus KIS mit Oracle-Client und Oracle-Datenbank. Abschnitt 12
  beschreibt, wie der Entwurf darauf eingeht.

### Nicht enthalten

Fernsteuerung vom Admin-Arbeitsplatz, Dauerbetrieb und Langzeitspeicherung, Tiefenaufzeichnung
per ETW/WPR, Anmeldedauer, Vergleich mehrerer Worker oder Läufe, Rückwärtskompatibilität zum
bisherigen Datenformat (es existieren nur simulierte Aufzeichnungen). Ebenfalls nicht messbar
vom Worker aus und daher nicht enthalten: Abfragezeiten in der Oracle-Datenbank, die Verarbeitung
innerhalb der FortiGate, der Aufwand einzelner AppLocker-Regelprüfungen.

## 3. Ausgangslage und Lücken

Die bestehende Lösung tastet alle 15 s Host, Sitzungen und alle Prozesse ab und zeigt den
Verbrauch je Sitzung, Anwendung und Prozess. Für die Störungsanalyse fehlt:

| Lücke | Folge |
|---|---|
| Gemessen wird Verbrauch, nicht Wirkung | Hohe Last ist nicht von spürbarer Störung unterscheidbar |
| Ein Takt von 15 s | Hänger von wenigen Sekunden gehen im Mittelwert unter |
| Keine Antwortzeiten | Langsame Datenträger und Dateiserver sind unsichtbar |
| Bericht ohne Schlussfolgerung | Engpässe müssen von Hand in Kurven gesucht werden |
| Kein Soll-Zustand | Werte sind nicht einzuordnen |

## 4. Messstrategie

### 4.1 Zwei Takte

| Takt | Standard | Inhalt |
|---|---|---|
| **Schnell** | 2 s (`-FastIntervalSeconds`) | Engpass-Signale des Hosts, Antwortzeiten je Laufwerk und Freigabe, Eingabeverzögerung je Sitzung und je Prozess |
| **Langsam** | 15 s (`-IntervalSeconds`) | Prozess-Schnappschuss (CPU-Zeit, Speicher, I/O je Prozess) und Sitzungsliste |

Prozesswerte sind fortlaufende Zähler. Auch im langsamen Takt wird jede verbrauchte
CPU-Millisekunde und jedes I/O-Byte dem richtigen Prozess zugerechnet; nur der Zeitpunkt ist
auf den Abstand der Schnappschüsse genau.

### 4.2 Verdichtung bei Auffälligkeit

Überschreitet im schnellen Takt ein als Auslöser markiertes Signal seine Schwelle „auffällig",
wechselt der Collector in den Verdichtungsmodus: Prozess-Schnappschüsse alle 5 s
(`-BurstIntervalSeconds`), bis 60 s (`-BurstHoldSeconds`) lang kein Auslöser mehr anliegt.
Auslöser im Auslieferungszustand: Eingabeverzögerung, CPU-Auslastung, verfügbarer Speicher,
Datenträger- und Freigabe-Antwortzeit. Die Schwellen kommen aus der Schwellwert-Datei (Abschnitt 6).

### 4.3 Nur aktive Prozesse schreiben

Eine Prozesszeile wird nur geschrieben, wenn der Prozess seit dem letzten Schnappschuss
CPU-Zeit oder I/O verbraucht hat, sein Working Set sich um mindestens 1 MB geändert hat oder
er neu ist. Damit die Auswertung ruhende Prozesse korrekt fortführen kann:

- Das Ende eines Prozesses wird ausdrücklich vermerkt.
- Jeder 20. reguläre Schnappschuss (etwa alle 5 Minuten) ist ein vollständiger Stützpunkt mit
  allen Prozessen. Zeitausschnitte (`-From`/`-To`) beginnen am vorhergehenden Stützpunkt.

### 4.4 Schutz vor Überlast und Platzmangel

- Dauert eine Messung länger als ihr Takt, entfällt der nächste Takt; nachgeholt wird nichts.
  Die Messdauer jedes Takts wird mitgeschrieben.
- Beim Start wird der freie Speicherplatz geprüft (Warnung unter 1 GB, Abbruch unter 200 MB).
- `-MaxSizeMB` (Standard 500) beendet die Messung sauber, wenn der Aufzeichnungsordner die
  Grenze erreicht.

### 4.5 Erwartete Datenmenge (Schätzung, nicht gemessen)

Bei 1.500 Prozessen, davon etwa 30 % je Intervall aktiv: rund 30 MB für 4 Stunden, rund 60 MB
für 8 Stunden. Die tatsächliche Größe wird beim ersten realen Lauf ermittelt.

## 5. Signale

Jeder Engpass hat ein Erkennungssignal (schneller Takt) und eine Zuordnung zum Verursacher.

| Engpass | Erkennungssignal | Zuordnung zum Verursacher |
|---|---|---|
| Spürbare Verzögerung | Eingabeverzögerung je Sitzung (Maximum im Intervall) | Eingabeverzögerung je Prozess; zeitgleiche Engpässe unten |
| CPU | Auslastung, Prozessor-Warteschlange je CPU, vom Hypervisor entzogene CPU-Zeit | CPU-Zeit je Prozess, Anwendung, Sitzung |
| Arbeitsspeicher | belegter und verfügbarer Speicher, Commit-Auslastung, von Datenträger gelesene Seiten pro Sekunde | Working Set und dessen Zuwachs je Prozess |
| Datenträger | Lese-/Schreib-Antwortzeit und Warteschlange je Laufwerk | I/O-Menge je Prozess |
| Dateiserver/Profil | Lese-/Schreib-Antwortzeit je SMB-Freigabe | I/O-Menge je Prozess; die Freigabe benennt den Server |
| Netzstrecke zum Benutzer | ICA Round Trip und Netzwerklatenz je Sitzung | betrifft die Sitzung, nicht den Worker |

Grenzen, die im Bericht stehen müssen:

- Bei Datenträger und Dateiserver ist sichtbar, **dass** ein Ziel langsam antwortet und **welche**
  Prozesse viel I/O erzeugen, nicht aber, welcher Prozess auf welche Datei wartet.
- Die Eingabeverzögerung enthält laut Microsoft keine Prozesse, die als SYSTEM laufen.
- Entzogene CPU-Zeit ist nur verfügbar, wenn die VMware Tools den Zähler bereitstellen.

### Datenquellen

| Signal | Quelle | Status |
|---|---|---|
| Prozesse, Sitzungen, Host-CPU/Speicher/Datenträger/Netz | `Win32_Process`, WTS-API; Leistungsindikatoren `Processor Information`, `System`, `Memory`, `PhysicalDisk`, `Network Interface` über `PerformanceCounterCategory` mit englischen Namen | geprüft (VDA, Server 2022, de-DE): vorhanden, .NET-Weg liefert Werte |
| Eingabeverzögerung | Leistungsindikatoren „User Input Delay per Session" / „per Process", Zähler `Max Input Delay` | geprüft: vorhanden; Typ `AverageCount64`, Basiswert +1 je Abfrage bei 1 s und 2 s Abstand; daraus geschlossen (nicht gemessen): eine Abfrage alle 2 s liefert den Höchstwert seit der vorigen Abfrage |
| Antwortzeit je Laufwerk | `LogicalDisk` (Avg. Disk sec/Read, /Write, Typ `AverageTimer32`) | geprüft: vorhanden, Werte in Sekunden |
| Antwortzeit je Freigabe | Leistungsindikator „SMB Client Shares" (Avg. sec/Read, /Write) | geprüft: vorhanden; Instanzen `\server\share` mit einem Schrägstrich |
| Entzogene CPU-Zeit | VMware-Tools-Leistungsindikator „VM Processor" / `CPU stolen time` | geprüft: vorhanden (nur .NET, keine CIM-Klasse), einzige Instanz `_Total`; Typ `Timer100Ns`, der Rohwert wird als Millisekunden der ganzen VM gelesen und je vCPU umgerechnet; Einheit und Bezug nicht bestätigt |
| ICA Round Trip, Latenz | `root\citrix\euem` `Citrix_Euem_RoundTrip`; Leistungsindikator „ICA Session" (`Latency - Last Recorded`) | geprüft: Klasse und Kategorie vorhanden; Instanzen `<WinStation> (<Benutzer>)`, Summe lokalisiert |

Das Quellen-Prüfskript (Abschnitt 9.1) hat diese Quellen auf einem echten VDA geprüft. Dass die
Eingabeverzögerung bei einem Abfragetakt von 2 s das Maximum des ganzen Intervalls liefert, ist aus
dem Basiswert des Zählers geschlossen; die erste echte Messung soll es bestätigen. Bestätigt sie es
nicht, wird der schnelle Takt auf 1 s gesetzt. Ebenso bestätigt sie Einheit und Bezug der entzogenen
CPU-Zeit (Vergleich mit der CPU-Bereitschaft der VM im vCenter).

## 6. Schwellwerte und Soll-Zustand

Eine Datei `src/thresholds.json` ist die einzige Quelle für Soll-Anzeige, Befunde und
Verdichtungs-Auslöser. Je Messwert:

```json
{
  "id": "cpu.host",
  "label": "CPU-Auslastung",
  "unit": "%",
  "direction": "high",
  "warn": 75,
  "crit": 90,
  "ideal": "unter 75 %",
  "minTicks": 3,
  "trigger": true,
  "origin": "Herstellerangabe",
  "source": "Citrix DaaS Monitor, vordefinierte Schwellen",
  "url": "https://docs.citrix.com/en-us/citrix-daas/monitor/site-analytics/thresholds"
}
```

`origin` ist `Herstellerangabe`, `Faustregel` oder `eigene Annahme`. Die Startwerte:

| Messwert | auffällig | kritisch | Herkunft |
|---|---|---|---|
| CPU-Auslastung Host | 75 % | 90 % | Herstellerangabe (Citrix DaaS Monitor) |
| Prozessor-Warteschlange je CPU | 2 | 5 | Herstellerangabe (Microsoft) |
| Entzogene CPU-Zeit je vCPU | 5 % | 10 % | Faustregel (VMware-Umfeld) |
| RAM-Auslastung | 75 % | 90 % | Herstellerangabe (Citrix DaaS Monitor) |
| Commit-Auslastung | 80 % | 90 % | Herstellerangabe (Microsoft) / kritisch: eigene Annahme |
| Von Datenträger gelesene Seiten/s | 10 | 100 | Faustregel (Microsoft, älter) / kritisch: eigene Annahme |
| Eingabeverzögerung | 150 ms | 500 ms | Herstellerangabe (Microsoft AVD Insights) |
| Datenträger-Antwortzeit | 10 ms | 20 ms | Herstellerangabe (Microsoft) |
| Freigabe-Antwortzeit (SMB) | 10 ms | 20 ms | eigene Annahme (wie Datenträger) |
| ICA Round Trip | 150 ms | 300 ms | Herstellerangabe (Citrix) |
| ICA-Netzwerklatenz | 150 ms | 250 ms | Herstellerangabe (Citrix DaaS Monitor) |

Die Citrix-Werte stammen aus Suchtreffern zur Citrix-Dokumentation, nicht aus deren Volltext,
und sind vor produktiver Nutzung gegenzuprüfen. Alle Werte sind Startwerte und nach den ersten
realen Messungen nachzustellen.

Der Collector kopiert die verwendete Datei in den Aufzeichnungsordner. Der Bericht verwendet
standardmäßig die aktuelle Datei neben dem Skript (oder `-ThresholdFile`), sodass eine Messung
mit geänderten Schwellen beliebig oft neu ausgewertet werden kann.

Benutzer je vCPU wird als Information angezeigt, aber nicht bewertet.

## 7. Befund-Logik

Eigene Datei `src/WorkerPerf.Findings.ps1`, vom Berichtsskript eingebunden, ohne Dateizugriffe:
Eingabe sind Messreihen und Schwellen, Ausgabe sind Vorfälle.

1. **Bewerten:** Jeder Messpunkt jedes Signals erhält den Status normal, auffällig oder kritisch.
   Signale je Instanz (Sitzung, Laufwerk, Freigabe) werden je Instanz bewertet.
2. **Befund:** eine Folge von mindestens `minTicks` Messpunkten mit Status ab „auffällig";
   Lücken bis 10 s werden überbrückt. Für die Eingabeverzögerung gilt `minTicks` 1, damit auch
   ein einzelner Hänger zählt; für alle anderen 3. Schwere = schlechtester Status.
3. **Vorfall:** Befunde verschiedener Signale, die sich zeitlich überlappen oder höchstens 10 s
   auseinanderliegen, bilden einen Vorfall. Ein Vorfall nennt alle beteiligten Ressourcen; die
   führende ist die mit dem frühesten Beginn.
4. **Betroffene:** Sitzungen, deren Eingabeverzögerung im Vorfallsfenster mindestens „auffällig" war.
5. **Verursacher:** je beteiligter Ressource die fünf größten Beitragenden im Fenster
   (Prozess, Anwendung, Sitzung), gemessen an CPU-Zeit (CPU), Working Set und Zuwachs (Speicher)
   oder I/O-Menge (Datenträger, Freigabe). Zu jedem der **Normalwert**: sein Anteil in der
   übrigen Messung außerhalb aller Vorfälle.
6. **Klartext:** ein Satz je Vorfall aus festen Bausteinen, z. B. „10:41:30–10:43:10: CPU-Engpass
   (Spitze 97 %, Soll unter 75 %). Betroffen: 6 Sitzungen. Hauptverursacher: EXCEL.EXE in der
   Sitzung von user017 mit 41 % der CPU-Zeit (sonst 2 %)."

Der Collector selbst wird als Prozess miterfasst; sein Anteil wird im Bericht gesondert
ausgewiesen und in der Verursacherliste gekennzeichnet.

## 8. Bericht

Neue Startseite **Befunde**; die Reiter Übersicht, Sitzungen, Anwendungen, Prozesse bleiben.

- **Zeitleiste** über die gesamte Messung mit allen Vorfällen als Markierungen, eingefärbt nach
  Schwere, zusätzlich mit Symbol und Text. Ein Klick stellt alle Diagramme auf das Zeitfenster
  ein; „Gesamter Zeitraum" setzt zurück.
- **Vorfallsliste:** Zeitraum, Dauer, Ressourcen, Schwere, Zahl der Betroffenen, Klartext.
  Aufgeklappt: Betroffene, Verursacher mit Normalwert, Verlauf der beteiligten Signale im Fenster.
- **Soll-Ist-Tabelle:** je Messwert Idealbereich, Mittelwert, P95, Maximum, Zeitanteil in normal /
  auffällig / kritisch, Herkunft mit Link. Nicht gemessene Werte stehen als „nicht gemessen".
- **Bänder in den Diagrammen:** Linien für „auffällig" und „kritisch".
- **Kacheln** zeigen den Status gegenüber dem Soll.
- **Fokus:** `-FocusUser` und `-ReportedTime` beim Erzeugen des Berichts. Die Sitzung des
  Benutzers wird hervorgehoben, die Uhrzeit in der Zeitleiste markiert, Vorfälle mit diesem
  Benutzer als Betroffenem stehen vorn; Vorfälle im Umkreis von 15 Minuten um die Uhrzeit
  werden gekennzeichnet.
- **Kein Befund:** ausdrückliche Aussage samt Liste der gemessenen und nicht gemessenen Signale.
- **Messqualität:** ausgelassene Takte, Messdauer, Anteil des Collectors, Zeiten im
  Verdichtungsmodus.

## 9. Bausteine

### 9.1 Quellen-Prüfskript `src/Test-WorkerPerfSources.ps1` (neu, erster Schritt)

Listet auf einem Worker je Signal aus Abschnitt 5, ob die Quelle existiert, den gefundenen
Klassen- und Eigenschaftsnamen und einen Beispielwert; misst die Dauer eines
Prozess-Schnappschusses. Ausgabe als Text und als JSON-Datei zum Zurückschicken. Ändert nichts
am System.

### 9.2 Collector `src/Start-WorkerPerfCapture.ps1` (erweitert)

Zwei Takte, Verdichtung, Aktiv-Filter, Schutzmechanismen. Dateien im Aufzeichnungsordner:

| Datei | Zeile je | Inhalt |
|---|---|---|
| `meta.json` | – | Host, Einstellungen, Formatversion 2, verfügbare Quellen |
| `thresholds.json` | – | Kopie der verwendeten Schwellen |
| `ticks.csv` | schnellem Takt `T` | Zeit, Host-Signale, Messdauer, Verdichtungsmodus |
| `volumes.csv` | `T` × Laufwerk | Lese-/Schreib-Antwortzeit, Warteschlange, Durchsatz |
| `shares.csv` | `T` × Freigabe | Lese-/Schreib-Antwortzeit, Durchsatz |
| `inputdelay.csv` | `T` × Sitzung | maximale Eingabeverzögerung |
| `inputdelay_proc.csv` | `T` × Prozess, nur ab 50 ms | Eingabeverzögerung je Prozess |
| `citrix.csv` | `T` × Sitzung × Messwert | ICA-Werte |
| `probes.csv` | Probe × Gegenstelle | Dauer des Verbindungsaufbaus oder Fehler |
| `events.csv` | Ereignis | Zeit, Quelle, Kennung, Kurztext (Defender, AppLocker) |
| `snapshots.csv` | Prozess-Schnappschuss `P` | zugehöriges `T`, abgedeckte Sekunden, Art (regulär, Verdichtung, Stützpunkt) |
| `sessions.csv` | `P` × Sitzung | Benutzer, Zustand, Client, Leerlauf |
| `procinfo.csv` | Prozessinstanz `K` | PID, Name, Sitzung, Start, Pfad, Dienstnamen bei `svchost.exe`, optional Befehlszeile |
| `processes.csv` | `P` × aktivem Prozess | CPU-ms, Working Set, Private Bytes, I/O, Handles, Threads |
| `procend.csv` | beendetem Prozess | `P`, `K` |

### 9.3 Befund-Logik `src/WorkerPerf.Findings.ps1` (neu) – Abschnitt 7.

### 9.4 Berichtsskript und Vorlage (erweitert) – Abschnitt 8. Das Berichtsskript liest das neue
Format, führt ruhende Prozesse fort, ruft die Befund-Logik auf und bettet Vorfälle, Soll-Ist-Daten
und die fein aufgelösten Signale ein.

### 9.5 Simulation (erweitert)

`-Simulate` erzeugt ein festes Drehbuch mit bekannten Vorfällen: CPU-Engpass durch einen
bestimmten Prozess, Speicherdruck durch einen wachsenden Prozess, langsames Laufwerk, langsame
Freigabe, langsamer Profilcontainer eines Benutzers, Datenträgerlast mit Schutzsoftware als
Begleiter, Verzögerung der Hauptanwendung ohne Engpass auf dem Worker bei gleichzeitig träger
Gegenstelle, ein einzelner kurzer Hänger einer Sitzung, dazwischen ruhige Phasen. Zeitpunkt,
Ressource und Verursacher jedes Vorfalls stehen als Soll-Ergebnis in einer Datei im
Aufzeichnungsordner.

## 10. Fehlerverhalten

| Situation | Verhalten |
|---|---|
| Datenquelle fehlt oder liefert Fehler | einmalige Warnung, Messung läuft weiter, Signal gilt als „nicht gemessen" und wird nicht bewertet |
| Takt wird überschritten | nächster Takt entfällt, im Bericht unter Messqualität sichtbar |
| Speicherplatz knapp oder Obergrenze erreicht | sauberes Ende, `meta.json` nennt den Grund |
| Abbruch mit Strg+C oder `stop.flag` | wie bisher, Dateien bleiben auswertbar |
| Abgeschnittene letzte Zeile | wird bei der Auswertung übersprungen |
| Schwellwert-, Rollen- oder Gegenstellen-Datei fehlerhaft | Abbruch mit Angabe des fehlerhaften Eintrags |
| Gegenstelle nicht erreichbar | Probe wird als Fehler mit Dauer bis zum Abbruch (höchstens 2 s) vermerkt, Messung läuft weiter |
| Ereignisprotokoll nicht lesbar | einmalige Warnung, keine Ereignismarkierungen |

## 11. Test

- **Befund-Logik (Pester):** je Regel aus Abschnitt 7 Tests mit kleinen, handgebauten Messreihen:
  Schwellen, `minTicks`, Lückenüberbrückung, Zusammenfassen zu Vorfällen, Verursacher-Rangfolge,
  Normalwert, keine Meldung in ruhigen Reihen, nicht gemessene Signale, Befundtyp „Verzögerung
  ohne Engpass auf dem Worker", Schutzsoftware als Begleiter, Rollen-Zuordnung.
- **Durchlauf:** Simulation → Bericht; geprüft wird, dass genau die Vorfälle des Drehbuchs mit
  richtiger Ressource und richtigem Hauptverursacher gefunden werden und die Datenmenge der
  Simulation im erwarteten Rahmen liegt.
- **Bericht im Browser:** lädt ohne Skriptfehler in hellem und dunklem Schema; Zeitleiste,
  Hineinzoomen, Soll-Ist-Tabelle und Fokus funktionieren.
- **Nicht durch Tests abgedeckt:** die Windows-Datenquellen. Sie gelten erst nach einem Lauf des
  Prüfskripts und einer Kurzmessung auf einem echten VDA als geprüft.

## 12. Bezug zur Umgebung des Auftraggebers

### 12.1 Befundtyp „Verzögerung ohne Engpass auf dem Worker"

Ist die Eingabeverzögerung einer Sitzung mindestens „auffällig", während im selben Fenster kein
Ressourcensignal des Workers (CPU, Warteschlange, entzogene CPU-Zeit, Speicher, Datenträger,
Freigaben, Profilcontainer dieser Sitzung) auffällig ist, entsteht ein Vorfall dieses Typs. Er
nennt die Prozesse mit der höchsten Eingabeverzögerung und, soweit vorhanden, die Antwortzeit-Proben
und den ICA Round Trip im selben Fenster. Der Klartext sagt ausdrücklich, dass die Ursache
außerhalb des Workers oder in der Anwendung selbst zu suchen ist (Datenbank, Proxy, Netz).

### 12.2 Antwortzeit-Proben

Optionale Datei `src/endpoints.json` mit benannten Gegenstellen (Name, Host, Port, Rolle), z. B.
Oracle-Listener, FortiGate-Proxy, Dateiserver. Der Collector misst im langsamen Takt die Dauer
des TCP-Verbindungsaufbaus je Gegenstelle, mit 2 s Zeitlimit, außerhalb des schnellen Takts.
Schwellen (eigene Annahme): auffällig ab 50 ms, kritisch ab 200 ms oder bei Fehler. Die Probe
zeigt, ob Strecke oder Gegenstelle träge erreichbar sind; sie misst keine Abfrage- oder
Verarbeitungszeiten. Ohne Datei entfällt die Messung.

### 12.3 Profilcontainer (Citrix Profile Management)

Containerprofile sind eingebundene virtuelle Datenträger, die auf einer SMB-Freigabe liegen.
Der Collector kennzeichnet diese Laufwerke als Profilcontainer und ordnet sie Benutzer und
Sitzung zu; `volumes.csv` erhält dafür die Spalten Art und Sitzung. Im Bericht erscheint die
Antwortzeit des eigenen Profilcontainers in der Sitzungsansicht, und ein Befund auf einem
Profilcontainer nennt den Benutzer und die dahinterliegende Freigabe. Wie sich die Zuordnung
Laufwerk → Benutzer zuverlässig auslesen lässt, ist ungeprüft und Aufgabe des Prüfskripts;
gelingt sie nicht, werden die Laufwerke als „Profilcontainer (Benutzer unbekannt)" geführt.

### 12.4 Rollen

Datei `src/roles.json` ordnet Prozessnamen (bei `svchost.exe` auch Dienstnamen) einer Rolle zu:
Hauptanwendung, Sicherheit, Profil, Citrix, System. Auslieferungszustand:

| Rolle | Einträge | Status |
|---|---|---|
| Sicherheit | Microsoft Defender (`MsMpEng.exe`, `NisSrv.exe`, `MpDefenderCoreService.exe`); Arctic Wolf Aurora Endpoint Protection; AppLocker-Dienst (`AppIDSvc`) | Aurora-Prozessnamen unbekannt, per Prüfskript zu ermitteln |
| Profil | Citrix Profile Management (`UserProfileManager.exe`) | Name ungeprüft |
| Hauptanwendung | Nexus KIS und Oracle-Client | Prozessnamen vom Auftraggeber oder per Prüfskript |
| Citrix | VDA-Dienste und Sitzungskomponenten | ungeprüft |

Wirkung im Bericht:

- **Schutzsoftware als Begleiter:** Echtzeitschutz erzeugt Last überwiegend als Folge fremder
  Dateizugriffe. Steht ein Prozess der Rolle Sicherheit unter den Verursachern eines Vorfalls,
  wird er als Begleiter neben dem größten I/O-Erzeuger im selben Fenster ausgewiesen, mit
  Hinweis auf Scan-Ausschlüsse. Da zwei Schutzprodukte im Einsatz sind, weist der Bericht ihre
  Anteile getrennt und als Summe aus.
- **Hauptanwendung:** eigene Kachel und eigener Verlauf der Eingabeverzögerung der
  Hauptanwendung über alle Sitzungen.
- Tabellen lassen sich nach Rolle filtern.

### 12.5 Ereignisse in der Zeitleiste

Der Collector liest im langsamen Takt neue Einträge aus dem Windows-Ereignisprotokoll und
schreibt sie nach `events.csv`: Start und Ende von Defender-Scans, Defender-Signatur-Updates,
AppLocker-Blockierungen. Der Bericht zeigt sie als Markierungen in der Zeitleiste und nennt
Ereignisse, die in ein Vorfallsfenster fallen, im Vorfall. Protokollnamen und Ereigniskennungen
sind ungeprüft und Aufgabe des Prüfskripts. Für Arctic Wolf Aurora ist keine Ereignisquelle
vorgesehen, solange keine bekannt ist.

### 12.6 Erweiterung des Prüfskripts

Zusätzlich zu Abschnitt 9.1 ermittelt das Prüfskript: eingebundene Profilcontainer und ihre
Zuordnung zu Benutzern, laufende Prozesse und Dienste der Schutzprodukte, die Prozesse der
Hauptanwendung in einer Benutzersitzung, die genannten Ereignisprotokolle, sowie die
Erreichbarkeit der in `endpoints.json` eingetragenen Gegenstellen.

## 13. Reihenfolge

1. Quellen-Prüfskript; Lauf auf einem echten VDA durch den Auftraggeber; Namen und
   Berechnungen in dieser Spezifikation nachziehen.
2. Schwellwert- und Rollen-Datei, Befund-Logik mit Tests.
3. Collector: neues Format, zwei Takte, Verdichtung, Schutzmechanismen, Proben, Ereignisse,
   Profilcontainer, Simulation mit Drehbuch.
4. Berichtsskript und Vorlage.
5. Kurzmessung auf einem echten VDA, Schwellen und Datenmenge nachstellen.

Schritt 2 hängt nicht von Schritt 1 ab und kann parallel beginnen.

## 14. Nachträge aus der Planung

Beim Ausarbeiten des Umsetzungsplans wurden Lücken geschlossen. Die folgenden Regeln ergänzen
die Abschnitte oben und gehen ihnen im Zweifel vor.

1. **Dauerzustand (zu 7).** Ein Befund, der länger als 15 Minuten ununterbrochen anliegt, ist ein
   Dauerzustand. Er bildet einen eigenen Vorfall und wird nicht mit anderen Befunden
   zusammengefasst – sonst würde etwa eine den ganzen Tag erhöhte RAM-Auslastung alle übrigen
   Vorfälle zu einem einzigen verschmelzen. Überlappende Dauerzustände nennt ein Vorfall als
   Begleitumstand. Als Erklärung im Sinne von Abschnitt 12.1 zählt ein Dauerzustand nur in der
   Stufe „kritisch".
2. **Verdichtung ist begrenzt (zu 4.2).** Je Auslöser-Signal dauert eine Verdichtung höchstens
   5 Minuten. Danach löst dasselbe Signal erst wieder aus, nachdem es einmal unter die Schwelle
   gefallen ist.
3. **Sitzungsbezogene Signale (zu 7).** Profilcontainer und ICA-Werte gehören zu einer Sitzung.
   Sie werden einem Vorfall nur zugeordnet, wenn dieselbe Sitzung darin eine Eingabeverzögerung
   hat; andernfalls bilden sie einen eigenen Vorfall für diese Sitzung. Vorfälle ohne
   Eingabeverzögerung und ohne Worker-Ressource (nur Netzstrecke oder Gegenstelle) heißen
   „Umfeld".
4. **Mindestaktivität (zu 6).** Antwortzeiten von Laufwerken und Freigaben werden nur bewertet,
   wenn im Messpunkt mindestens 5 Lese- oder Schreibvorgänge stattfanden (`minOps` in der
   Schwellwert-Datei). Ein einzelner langsamer Zugriff auf ein ruhendes Laufwerk ist kein Befund.
   Schwellwert-Einträge dürfen außerdem `note` tragen (Freitext zur Herkunft).
5. **Hauptverursacher (zu 7).** Der im Klartext genannte Hauptverursacher ist die Anwendung in
   einer Sitzung mit dem größten Anteil; Prozesse der Rolle Sicherheit sind davon ausgenommen
   und erscheinen als Begleiter.
6. **Sparsame Dateien (zu 9.2).** `volumes.csv` und `shares.csv` enthalten nur Zeilen für
   Instanzen mit Zugriffen im Takt, `inputdelay.csv` nur Zeilen mit Verzögerung über 0.
   ICA-Werte und Antwortzeit-Proben werden mit den Prozess-Schnappschüssen gelesen und unter
   deren `T` abgelegt. `volumes.csv` führt zusätzlich die Spalte `Backing` mit der Freigabe
   hinter einem Profilcontainer.
7. **Zugriff auf Leistungsindikatoren (zu 5).** Vorgesehen ist die .NET-Schnittstelle für
   Leistungsindikatoren mit englischen Namen statt einzelner CIM-Klassen. Das erspart die
   unbekannten Klassennamen und die eigene Berechnung aus Rohwerten. Das Prüfskript testet beide
   Wege; die Entscheidung fällt mit seinem Ergebnis.
8. **Textbausteine und Dateien (zu 7 und 9).** Die Textbausteine des Klartexts stehen in
   `src/texts.de.json`, weil Skripte für Windows PowerShell 5.1 nur ASCII enthalten dürfen.
   Gemeinsamer Code liegt in `src/WorkerPerf.*.ps1`. Die Gegenstellen-Datei wird als
   `src/endpoints.example.json` ausgeliefert und vom Anwender als `endpoints.json` angelegt.
9. **Simulation (zu 9.5).** Das Drehbuch ist 60 Minuten lang; die Simulation verlangt
   mindestens diese Dauer.
10. **Datenschutz beim Prüfskript (zu 9.1).** Das Ergebnis des Prüfskripts enthält keine
    Benutzer-, Client- oder Servernamen; Pfade werden entsprechend maskiert.
