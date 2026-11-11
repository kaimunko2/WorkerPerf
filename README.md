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
```

Erzeugt `report.html` im Aufzeichnungsordner (oder `-OutFile`).

### Ohne VDA ausprobieren

```powershell
$run = .\src\Start-WorkerPerfCapture.ps1 -Simulate -DurationMinutes 60 -OutputPath .\demo
.\src\New-WorkerPerfReport.ps1 -Path $run
```

Die Simulation legt zusätzlich `expected.json` ab: die Vorfälle, die die Auswertung finden soll.

## Der Bericht

| Reiter | Inhalt |
|---|---|
| **Übersicht** | Kennzahlen (CPU Ø/P95/Max, RAM, Sitzungen, IOPS, ICA Round Trip), CPU und RAM gestapelt nach Sitzung oder Anwendung, Host-Verläufe für CPU, Speicher, Datenträger, Netzwerk, Sitzungszahl |
| **Sitzungen** | je Sitzung: Benutzer, Client, Dauer, Aktiv-Anteil, CPU-Anteil/-Zeit/Ø/P95/Max, RAM, Commit, I/O, ICA RTT. Detail: Verläufe, Anwendungen und Prozesse der Sitzung, Citrix-Messwerte |
| **Anwendungen** | je Prozessname über alle Sitzungen: Instanzen, CPU, RAM gesamt und je Instanz, I/O. Detail: Verläufe und betroffene Sitzungen |
| **Prozesse** | die ressourcenintensivsten Einzelprozesse mit Verlauf (CPU, Working Set), Handles, Threads |

Alle Tabellen sind sortier- und filterbar; Zeiten erscheinen in der Ortszeit des gemessenen Servers.

### Lesehilfe zu den Messwerten

- **CPU %** ist immer auf die gesamte Host-Kapazität bezogen (alle logischen CPUs = 100 %).
  Die Werte aller Prozesse summieren sich damit zur Host-Auslastung.
- **CPU-Zeit s** sind tatsächlich verbrauchte CPU-Sekunden; **CPU-Anteil %** ist der Anteil an der
  von allen Prozessen zusammen verbrauchten CPU-Zeit.
- **RAM** ist die Summe der Working Sets. Gemeinsam genutzte Seiten (DLLs) werden dabei mehrfach
  gezählt – die Summe über alle Sitzungen kann über dem physisch belegten Speicher liegen.
  **Commit** (Private Bytes) ist die belastbarere Größe für Sizing-Fragen.
- **I/O** umfasst alle Lese-/Schreibvorgänge eines Prozesses (Datei, Netzwerk, Geräte).
- Prozesse, die zwischen zwei Messungen starten *und* enden, werden nicht erfasst. Ein Prozess,
  der im Intervall startet, bekommt seine bis dahin verbrauchte CPU-Zeit diesem Intervall zugerechnet.

## Datenformat

Je Lauf ein Ordner mit:

| Datei | Zeilen | Inhalt |
|---|---|---|
| `meta.json` | – | Host, Betriebssystem, CPUs, RAM, Intervall, Start/Ende |
| `system.csv` | je Messung | CPU %, Warteschlange, Speicher, Paging, Datenträger, Netzwerk, Sitzungs- und Prozesszahl |
| `sessions.csv` | je Messung × Sitzung | Benutzer, Domäne, Zustand, Client, Anmeldezeit, Leerlauf |
| `procinfo.csv` | je Prozessinstanz | Schlüssel `K`, PID, Name, Sitzung, Startzeit, Pfad, optional Befehlszeile |
| `processes.csv` | je Messung × Prozess | CPU-ms, Working Set, Private Bytes, I/O-Bytes und -Operationen im Intervall, Handles, Threads |
| `citrix.csv` | je Messung × Sitzung × Messwert | Citrix-WMI-Werte (z. B. `RoundtripTime`) |

`S` ist die laufende Nummer der Messung, `K` verweist auf `procinfo.csv`. Die CSVs lassen sich
auch direkt in Excel, Power BI o. ä. weiterverwenden.

**Größenordnung:** ca. 45 Byte je Prozess und Messung. 1.500 Prozesse × 15 s × 8 h ≈ 2,9 Mio. Zeilen
≈ 130 MB. Die Auswertung verarbeitet grob 15.000–20.000 Zeilen pro Sekunde.

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
