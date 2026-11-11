# WorkerPerf

Zeichnet Performance und Ressourcenverbrauch eines Citrix-Terminalserver-Workers
(Citrix DaaS / CVAD Multi-Session VDA, Shared Desktop) auf und wertet sie für einen
Messzeitraum aus – für den Host insgesamt und heruntergebrochen auf einzelne
**Benutzersitzungen**, **Anwendungen** und **Prozesse**.

- Keine Installation, keine Module, kein Agent: zwei PowerShell-Skripte (ab Windows PowerShell 5.1).
- Sprachneutral: liest CIM-Rohdatenklassen und die WTS-API statt lokalisierter Leistungsindikatoren,
  funktioniert also auf deutschen und englischen Systemen gleich.
- Ergebnis ist ein einzelner, offline nutzbarer HTML-Bericht ohne externe Abhängigkeiten.

> **Stand:** erster lauffähiger Entwurf. Die gesamte Kette ist mit simulierten Daten getestet
> (`-Simulate`). Die Windows-Datenquellen (CIM, WTS-API, Citrix-WMI) wurden noch **nicht** auf
> einem echten VDA ausgeführt – siehe [Offene Punkte](#offene-punkte).

## Ablauf

```text
VDA (Worker)                                   beliebiger Rechner
Start-WorkerPerfCapture.ps1  ──►  CSV-Ordner  ──►  New-WorkerPerfReport.ps1  ──►  report.html
```

### 1. Aufzeichnen (auf dem VDA, mit erhöhten Rechten)

Der Collector misst in zwei Takten: Alle 2 Sekunden erfasst er die Host-Signale (CPU, Speicher,
Datenträger, Freigaben, Netzwerk) und die Eingabeverzögerung je Sitzung und Prozess. Alle 15 Sekunden
nimmt er einen Schnappschuss der Prozesse, Sitzungen und Citrix-Werte, prüft die Gegenstellen und liest
die Ereignisse – solange ein Auslöser-Signal über seiner Schwelle liegt (und 60 Sekunden danach) sogar alle 5 Sekunden.

```powershell
# Messung über vier Stunden
.\src\Start-WorkerPerfCapture.ps1 -OutputPath D:\WorkerPerf -DurationMinutes 240
```

Beenden: automatisch nach `-DurationMinutes`, mit `Strg+C`, beim Erreichen von `-MaxSizeMB`, bei
weniger als 200 MB freiem Speicherplatz oder durch Anlegen einer Datei `stop.flag` im
Aufzeichnungsordner (praktisch bei geplanten Aufgaben). Den Grund vermerkt `meta.json` (`EndReason`).

Gegenstellen für die Verbindungsproben (Datenbank, Proxy, Dateiserver …) stehen in
`src\endpoints.json`; als Vorlage dient `src\endpoints.example.json`. Fehlt die Datei, entfallen die Proben.

Als geplante Aufgabe unter SYSTEM (sieht alle Prozesse aller Sitzungen):

```powershell
$action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\WorkerPerf\src\Start-WorkerPerfCapture.ps1 -OutputPath D:\WorkerPerf -DurationMinutes 600'
$trigger = New-ScheduledTaskTrigger -Daily -At 07:00
Register-ScheduledTask -TaskName 'WorkerPerf' -Action $action -Trigger $trigger -User 'SYSTEM' -RunLevel Highest
```

| Parameter | Bedeutung |
|---|---|
| `-OutputPath` | Basisordner; je Lauf entsteht `<COMPUTER>_<yyyyMMdd-HHmmss>`. Standard: `%ProgramData%\WorkerPerf` |
| `-FastIntervalSeconds` | schneller Takt für Host-Signale und Eingabeverzögerung, 1–60 s, Standard 2 s |
| `-IntervalSeconds` | Abstand der regulären Schnappschüsse (Prozesse, Sitzungen), 5–3600 s, Standard 15 s |
| `-BurstIntervalSeconds` | Abstand der Schnappschüsse, solange ein Auslöser-Signal über der Schwelle liegt, Standard 5 s |
| `-BurstHoldSeconds` | so lange nach dem letzten Auslöser bleibt die Verdichtung aktiv, Standard 60 s |
| `-DurationMinutes` | Laufzeit; 0 = bis zum manuellen Stopp |
| `-MaxSizeMB` | Höchstgröße des Aufzeichnungsordners, Standard 500 MB |
| `-ThresholdFile` | Schwellwerte und Auslöser-Signale, Standard `thresholds.json` neben dem Skript |
| `-EndpointFile` | Gegenstellen für die Proben, Standard `endpoints.json` neben dem Skript; fehlt sie, gibt es keine Proben |
| `-IncludeCommandLine` | Befehlszeilen der Prozesse mitschreiben (können sensible Daten enthalten) |
| `-NoCitrix` | Citrix-ICA/EUEM-Messwerte nicht erfassen |
| `-CitrixMetricFilter` | Regex, welche numerischen Citrix-WMI-Eigenschaften erfasst werden |
| `-Simulate` | spielt ein 60-minütiges Drehbuch mit acht Vorfällen ab statt das lokale System zu messen (läuft auch unter Linux/macOS, verlangt `-DurationMinutes 60` oder mehr) |

> Die Windows-Datenquelle des neuen Formats wird noch fertiggestellt; bis dahin läuft der Collector nur mit `-Simulate`.

### 2. Auswerten (auf dem VDA oder einem anderen Rechner)

```powershell
.\src\New-WorkerPerfReport.ps1 -Path D:\WorkerPerf\VDA01_20260101-070000
# nur einen Ausschnitt bewerten:
.\src\New-WorkerPerfReport.ps1 -Path .\VDA01_20260101-070000 -From '2026-01-01 09:00' -To '2026-01-01 11:30'
# Meldung eines Benutzers: seine Vorfälle und die um die gemeldete Uhrzeit hervorheben
.\src\New-WorkerPerfReport.ps1 -Path .\VDA01_20260101-070000 -FocusUser 'CONTOSO\mmuster' -ReportedTime '2026-01-01 10:15'
```

Erzeugt `report.html` im Aufzeichnungsordner (oder `-OutFile`). Die Auswertung bewertet jede Messreihe
gegen die Schwellwerte, fasst die Befunde zu Vorfällen zusammen (Engpass auf dem Worker, Verzögerung
ohne Engpass, Umfeld, Dauerzustand), nennt Betroffene und Verursacher im Klartext und stellt alle
Messwerte dem Soll gegenüber. Findet sie nichts, sagt der Bericht das ausdrücklich.

| Parameter | Bedeutung |
|---|---|
| `-Path` | Aufzeichnungsordner |
| `-OutFile` | Zieldatei, Standard `<Path>\report.html` |
| `-From`, `-To` | nur Messungen in diesem Zeitraum bewerten |
| `-ThresholdFile` | Schwellwerte, Standard `thresholds.json` neben dem Skript |
| `-RoleFile` | Rollen (Hauptanwendung, Sicherheit, Profil, Citrix, System), Standard `roles.json` neben dem Skript |
| `-FocusUser` | gemeldeter Benutzer als `Benutzer` oder `Domäne\Benutzer` (Groß-/Kleinschreibung egal); unbekannte Namen brechen nicht ab |
| `-ReportedTime` | gemeldete Uhrzeit in der Ortszeit des gemessenen Servers; Vorfälle bis 15 Minuten davor oder danach werden hervorgehoben |
| `-TopProcesses` | Zahl der Einzelprozesse je Rangliste (CPU-Zeit, Spitzenspeicher), Standard 150 |

Schwellwerte und Rollen werden erst bei der Auswertung gelesen. Eine Messung lässt sich deshalb
jederzeit mit geänderten Dateien neu auswerten, etwa nachdem die Prozessnamen der Hauptanwendung in
`roles.json` eingetragen sind.

### Ohne VDA ausprobieren

```powershell
$run = .\src\Start-WorkerPerfCapture.ps1 -Simulate -DurationMinutes 60 -OutputPath .\demo
.\src\New-WorkerPerfReport.ps1 -Path $run
```

Die Simulation legt zusätzlich `expected.json` ab: die Vorfälle, die die Auswertung finden soll.

## Der Bericht

| Reiter | Inhalt |
|---|---|
| **Befunde** (Startreiter) | ein Satz mit der Zahl der Vorfälle je Typ, Zeitleiste, Vorfallsliste, Soll-Ist-Tabelle, Grenzen der Aussage, Messqualität |
| **Übersicht** | Kennzahlen (CPU Ø/P95/Max, RAM, Sitzungen, IOPS, ICA Round Trip), CPU und RAM gestapelt nach Sitzung oder Anwendung, Host-Verläufe für CPU, Speicher, Datenträger, Netzwerk, Sitzungszahl |
| **Sitzungen** | je Sitzung: Benutzer, Client, Dauer, Aktiv-Anteil, CPU-Anteil/-Zeit/Ø/P95/Max, RAM, Commit, I/O, ICA RTT. Detail: Verläufe, Anwendungen und Prozesse der Sitzung, Citrix-Messwerte |
| **Anwendungen** | je Prozessname über alle Sitzungen: Instanzen, CPU, RAM gesamt und je Instanz, I/O. Detail: Verläufe und betroffene Sitzungen |
| **Prozesse** | die ressourcenintensivsten Einzelprozesse mit Verlauf (CPU, Working Set), Handles, Threads |

Alle Tabellen sind sortier- und filterbar; Zeiten erscheinen in der Ortszeit des gemessenen Servers.

Der Reiter **Befunde** beantwortet die Frage aus der Meldung von oben nach unten:

- **Zeitleiste:** ein Balken über die ganze Messung. Jeder Vorfall ist eine Markierung von Beginn bis Ende
  mit Symbol und Farbe der Schwere (`▲ auffällig`, `◆ kritisch`); überlappende Vorfälle liegen in eigenen
  Zeilen. Dauerzustände stehen als schmale Linie darunter, Defender- und AppLocker-Ereignisse als kleine
  Striche (Text im Tooltip), die gemeldete Uhrzeit als senkrechte Linie. Ein Klick auf eine Markierung
  öffnet den Vorfall und stellt alle Diagramme auf sein Zeitfenster mit Rand.
- **Vorfallstypen:** *Engpass* – eine Ressource des Workers (CPU, Arbeitsspeicher, Datenträger, Freigabe,
  Profilcontainer) lag über dem Soll und Benutzer spürten es. *Verzögerung ohne Engpass* – Benutzer warteten,
  ohne dass der Worker ausgelastet war; die Ursache liegt in der Anwendung oder dahinter (Datenbank, Proxy,
  Netz). *Umfeld* – auffällig ist die Strecke zum Benutzer oder eine Gegenstelle, nicht der Worker.
- **Vorfallsliste:** je Vorfall Schwere, Typ und ein Absatz im Klartext. Ein Klick auf den Text klappt die
  Belege auf: Betroffene mit ihrer höchsten Eingabeverzögerung, Hauptverursacher, Verlauf der beteiligten
  Messwerte, je Ressource die Ranglisten der Prozesse, Anwendungen und Sitzungen mit Anteil und Normalwert,
  Prozesse mit der höchsten Eingabeverzögerung, Gegenstellen, ICA Round Trip, Anteil der Schutzprodukte,
  Ereignisse und Dauerzustände im Hintergrund. Ein Klick auf einen Benutzer, eine Anwendung oder einen
  Prozess öffnet ihn im jeweiligen Reiter.
- **Fokus:** mit `-FocusUser` und `-ReportedTime` nennt der Kopf den Benutzer und die gemeldete Uhrzeit;
  Vorfälle des Benutzers stehen zuerst, Vorfälle bis 15 Minuten um die gemeldete Uhrzeit sind gekennzeichnet.
- **Soll-Ist-Tabelle:** je Messwert Soll, Bewertung, Ø, P95, Maximum, die Zeitanteile normal / auffällig /
  kritisch als Balken und in Zahlen, die am stärksten betroffene Instanz und die Herkunft des Sollwerts mit
  Link auf die Quelle. Nicht gemessene Werte stehen mit `○ nicht gemessen` und dem Grund darin.
- Ohne Vorfall sagt der Reiter ausdrücklich „Keine Schwelle wurde überschritten." und listet die gemessenen
  und die nicht gemessenen Werte.

### Lesehilfe zu den Messwerten

- **CPU %** ist immer auf die gesamte Host-Kapazität bezogen (alle logischen CPUs = 100 %).
  Die Werte aller Prozesse summieren sich damit zur Host-Auslastung.
- **CPU-Zeit s** sind tatsächlich verbrauchte CPU-Sekunden; **CPU-Anteil %** ist der Anteil an der
  von allen Prozessen zusammen verbrauchten CPU-Zeit.
- **RAM** ist die Summe der Working Sets. Gemeinsam genutzte Seiten (DLLs) werden dabei mehrfach
  gezählt – die Summe über alle Sitzungen kann über dem physisch belegten Speicher liegen.
  **Commit** (Private Bytes) ist die belastbarere Größe für Sizing-Fragen.
- **I/O** umfasst alle Lese-/Schreibvorgänge eines Prozesses (Datei, Netzwerk, Geräte).
- **Eingabeverzögerung** ist die Zeit, die eine Eingabe des Benutzers (Taste, Maus) wartet, bis die Anwendung
  sie verarbeitet – die Messgröße für „alles war zäh". Prozesse, die als SYSTEM laufen, sind nicht enthalten.
- **Dauerzustand** ist ein Befund, der länger als 15 Minuten anhält, etwa eine dauerhaft langsame Netzstrecke
  eines Benutzers. Er steht als eigener Vorfall am Ende der Liste und bei jedem Vorfall, in dessen Zeitraum er
  fortbesteht, als Hintergrund.
- **Begleiter** ist ein Schutzprodukt (etwa Microsoft Defender), das in einem Vorfall einen spürbaren Anteil der
  Last trägt, weil es die Dateien des eigentlichen Verursachers prüft. Der Bericht nennt dann auch den größten
  I/O-Erzeuger im Fenster; meist hilft ein Scan-Ausschluss.
- **Normalwert** („sonst … %") ist der Anteil desselben Prozesses, derselben Anwendung oder Sitzung außerhalb
  der Vorfälle (Dauerzustände ausgenommen); ohne solche Messungen steht ein Strich. Ein hoher Anteil mit
  niedrigem Normalwert zeigt einen Ausreißer, ein hoher Anteil mit gleich hohem Normalwert einen gewohnten
  Großverbraucher.
- Prozesse, die zwischen zwei Messungen starten *und* enden, werden nicht erfasst. Ein Prozess,
  der im Intervall startet, bekommt seine bis dahin verbrauchte CPU-Zeit diesem Intervall zugerechnet.

## Datenformat

Je Lauf ein Ordner mit (Format 2):

| Datei | Zeilen | Inhalt |
|---|---|---|
| `meta.json` | – | Host, Betriebssystem, CPUs, RAM, Takte, Start/Ende, Endegrund, Collector-PID, Gegenstellen, verfügbare Datenquellen |
| `thresholds.json` | – | Kopie der Schwellwerte, mit denen aufgezeichnet wurde |
| `ticks.csv` | je Takt | CPU %, Warteschlange, entzogene CPU-Zeit, Speicher, Commit, Paging, Datenträger, Netzwerk, Verdichtung |
| `volumes.csv` | je Takt × Laufwerk | Antwortzeiten, Operationen und Durchsatz je Laufwerk und Profilcontainer |
| `shares.csv` | je Takt × Freigabe | Antwortzeiten, Operationen und Durchsatz je SMB-Freigabe |
| `inputdelay.csv` | je Takt × Sitzung | höchste Eingabeverzögerung der Sitzung |
| `inputdelay_proc.csv` | je Takt × Prozess | Eingabeverzögerung je Prozess (ab 50 ms) |
| `snapshots.csv` | je Schnappschuss | Nummer `P`, Takt `T`, Art (`K` Stützpunkt, `R` regulär, `B` verdichtet), Sitzungs- und Prozesszahl |
| `sessions.csv` | je Schnappschuss × Sitzung | Benutzer, Domäne, Zustand, Client, Anmeldezeit, Leerlauf |
| `procinfo.csv` | je Prozessinstanz | Schlüssel `K`, PID, Name, Sitzung, Startzeit, Pfad, Dienste, optional Befehlszeile |
| `processes.csv` | je Schnappschuss × geändertem Prozess | CPU-ms, Working Set, Private Bytes, I/O im Intervall, Handles, Threads; im Stützpunkt alle Prozesse |
| `procend.csv` | je beendetem Prozess | Schnappschuss und Schlüssel `K` |
| `citrix.csv` | je Schnappschuss × Sitzung × Messwert | Citrix-WMI-Werte (z. B. `RoundtripTime`) |
| `probes.csv` | je Probe | Verbindungszeit oder Fehler je Gegenstelle |
| `events.csv` | je Ereignis | Defender-Scans, AppLocker-Sperren und andere relevante Ereignisse |

`T` ist die laufende Nummer des Takts, `P` die des Schnappschusses, `K` verweist auf `procinfo.csv`.
Die CSVs lassen sich auch direkt in Excel, Power BI o. ä. weiterverwenden.

**Größenordnung:** Die simulierte Stunde (25 Sitzungen, rund 280 Prozesse) belegt etwa 5 MB;
Prozesszeilen entstehen nur für Prozesse, die sich seit dem letzten Schnappschuss verändert haben.

## Datenquellen

| Bereich | Quelle |
|---|---|
| Prozesse | `Win32_Process` (Kernel-/User-Zeit, Working Set, Private Bytes, I/O-Zähler, Sitzungs-ID) |
| Sitzungen | WTS-API (`WTSEnumerateSessions`, `WTSQuerySessionInformation`) |
| Host | `Win32_PerfRawData_PerfOS_Processor/_Memory/_System`, `..._PerfDisk_PhysicalDisk`, `..._Tcpip_NetworkInterface` |
| Citrix | `root\citrix\euem:Citrix_Euem_RoundTrip` und `Win32_PerfFormattedData_*ICASession*`, sofern vorhanden |

Fehlt eine Quelle (z. B. beschädigte Leistungsindikatoren), läuft die Aufzeichnung mit einer
Warnung weiter; die Host-CPU wird dann aus der Summe der Prozesse berechnet.

## Datenschutz

Die Aufzeichnung enthält personenbezogene Daten (Benutzernamen, Clientnamen, genutzte Anwendungen
und Zeiten, optional Befehlszeilen). Vor dem Einsatz Zweck, Aufbewahrung und ggf. die Beteiligung
von Betriebsrat/Datenschutz klären und die Ausgabeordner entsprechend schützen.

## Offene Punkte

- [ ] Erster Lauf auf einem echten Multi-Session-VDA (Windows Server 2019/2022, PowerShell 5.1)
- [ ] Citrix-WMI-Klassen und Eigenschaftsnamen am realen System prüfen (aktuell generisch per Filter erfasst)
- [ ] Messaufwand des Collectors bei > 1.500 Prozessen messen (`CollectMs` in `system.csv`)
- [ ] Privates Working Set je Prozess als zusätzliche Speichergröße
- [ ] Vergleich mehrerer Worker / mehrerer Läufe in einem Bericht
- [ ] Kurzlebige Prozesse über ETW/Prozess-Auditing erfassen
