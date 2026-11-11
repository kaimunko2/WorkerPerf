# WorkerPerf

> **Stand – bitte zuerst lesen**
>
> - Die **Windows-Datenquelle** des Collectors ist geschrieben. Sie beruht auf dem Ergebnis des Quellen-Prüfskripts
>   von einem echten VDA (Windows Server 2022, deutsche Oberfläche, Citrix): welche Zähler, Klassen und Namen dort
>   vorhanden sind (siehe [Datenquellen](#datenquellen)). Getestet ist sie bisher nur unter Linux mit
>   nachgestellten Windows-Aufrufen; **auf einem echten Server ist sie noch nicht gelaufen.** Der nächste Schritt
>   ist eine Kurzmessung auf einem Worker (siehe [Offene Punkte](#offene-punkte)).
> - Das **Quellen-Prüfskript** bleibt der erste Schritt auf jedem weiteren Worker. Es liest nur, dauert einige
>   Minuten und schreibt eine JSON-Datei, in der Benutzer-, Client- und Servernamen maskiert sind; die Datei vor der
>   Weitergabe bitte durchsehen. Aufruf in einer administrativen Konsole auf dem Worker:
>
>   ```powershell
>   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-WorkerPerfSources.ps1 -OutFile C:\Temp
>   ```
>
>   Anleitung: [docs/vda-probe/README.md](docs/vda-probe/README.md).
> - Auswertung, Befund-Logik und Bericht sind fertig und mit der Simulation getestet; mit ihr lässt sich die ganze
>   Kette [ohne VDA ausprobieren](#ohne-vda-ausprobieren).
> - **Demo ansehen:** [Bericht einer simulierten Stunde mit acht Vorfällen](https://kaimunko2.github.io/WorkerPerf/)
>   (GitHub Pages; Einrichtung siehe [Demo-Bericht](#demo-bericht)).

Zeichnet Performance und Ressourcenverbrauch eines Citrix-Terminalserver-Workers
(Citrix DaaS / CVAD Multi-Session VDA, Shared Desktop) auf und wertet sie für einen
Messzeitraum aus: Der Bericht nennt Engpässe als **Vorfälle**, ihren Hauptverursacher bis auf
Sitzung, Anwendung und Prozess, die betroffenen Sitzungen und den Vergleich mit dem Soll.

- Keine Installation, keine Module, kein Agent: drei PowerShell-Skripte (ab Windows PowerShell 5.1) –
  Prüfskript, Collector und Auswertung.
- Ergebnis ist ein einzelner, offline nutzbarer HTML-Bericht ohne externe Abhängigkeiten.
- Die Skripte brauchen den PowerShell-Sprachmodus `FullLanguage`. Wo AppLocker oder WDAC die Konsole einschränkt
  (`ConstrainedLanguage`), brechen sie gleich zu Beginn mit einer Meldung ab; dann eine uneingeschränkte
  administrative Konsole verwenden.

## Ablauf

```text
VDA (Worker)                                   anderer Rechner (empfohlen)
Start-WorkerPerfCapture.ps1  ──►  CSV-Ordner  ──►  New-WorkerPerfReport.ps1  ──►  report.html
```

### 1. Aufzeichnen

> **Noch nicht auf einem echten Worker erprobt:** Die Windows-Datenquelle ist geschrieben, aber bisher nur mit
> nachgestellten Windows-Aufrufen getestet. Die erste Messung auf einem Worker sollte eine Kurzmessung von etwa
> 10 Minuten sein (siehe [Offene Punkte](#offene-punkte)).

Der Collector misst in zwei Takten: Alle 2 Sekunden erfasst er die Host-Signale (CPU, Speicher,
Datenträger, Freigaben, Netzwerk) und die Eingabeverzögerung je Sitzung und Prozess. Alle 15 Sekunden
nimmt er einen Schnappschuss der Prozesse, Sitzungen und Citrix-Werte, prüft die Gegenstellen und liest
die Ereignisse. Solange ein Auslöser-Signal über seiner Schwelle liegt (und 60 Sekunden danach, je Signal
höchstens 5 Minuten am Stück), verdichtet er die Schnappschüsse: mit den Standardwerten alle **6 Sekunden**,
denn ein Schnappschuss entsteht immer in einem schnellen Takt, also im ersten Takt nach Ablauf von
`-BurstIntervalSeconds` (5 s) – bei einem Takt von 2 s jeder dritte.

```powershell
# Messung über vier Stunden auf dem Worker, in einer administrativen Konsole
.\src\Start-WorkerPerfCapture.ps1 -OutputPath D:\WorkerPerf -DurationMinutes 240
```

Beenden: automatisch nach `-DurationMinutes`, mit `Strg+C`, beim Erreichen von `-MaxSizeMB`, bei
weniger als 200 MB freiem Speicherplatz oder durch Anlegen einer Datei `stop.flag` im
Aufzeichnungsordner. Den Grund vermerkt `meta.json` (`EndReason`); endet die Aufzeichnung an einem
Fehler, steht dort `error` mit der Meldung (`EndMessage`), und der Bericht zeigt sie im Kopf.

Liefert die Datenquelle einmal einen Fehler (etwa ein Zeitlimit unter Last), endet die Aufzeichnung nicht:
Der betroffene Takt oder Schnappschuss entfällt, die Konsole warnt einmal je Quelle, und `meta.json` zählt
die Fehler je Quelle mit Zeit und Meldung des ersten (`SourceErrors`). Der Bericht führt sie unter
„Messqualität" auf.

Gegenstellen für die Verbindungsproben (Datenbank, Proxy, Dateiserver …) stehen in
`src\endpoints.json`; als Vorlage dient `src\endpoints.example.json`. Fehlt die Datei, entfallen die Proben.

> **Geplant, noch nicht beschrieben:** der Betrieb als geplante Aufgabe unter SYSTEM. Das Rezept folgt, sobald
> der Collector auf einem Worker im Vordergrund gelaufen ist; bis dahin bitte interaktiv in einer administrativen
> Konsole messen, damit Warnungen sichtbar sind.

| Parameter | Bedeutung |
|---|---|
| `-OutputPath` | Basisordner; je Lauf entsteht `<COMPUTER>_<yyyyMMdd-HHmmss>`. Standard: `%ProgramData%\WorkerPerf` |
| `-FastIntervalSeconds` | schneller Takt für Host-Signale und Eingabeverzögerung, 1–60 s, Standard 2 s |
| `-IntervalSeconds` | Abstand der regulären Schnappschüsse (Prozesse, Sitzungen), 5–3600 s, Standard 15 s |
| `-BurstIntervalSeconds` | Mindestabstand der Schnappschüsse, solange ein Auslöser-Signal über der Schwelle liegt, Standard 5 s; wirksam wird der nächste schnelle Takt, mit den Standardwerten also 6 s |
| `-BurstHoldSeconds` | so lange nach dem letzten Auslöser bleibt die Verdichtung aktiv, Standard 60 s |
| `-DurationMinutes` | Laufzeit; 0 = bis zum manuellen Stopp |
| `-MaxSizeMB` | Höchstgröße des Aufzeichnungsordners, Standard 500 MB |
| `-ThresholdFile` | Schwellwerte und Auslöser-Signale, Standard `thresholds.json` neben dem Skript |
| `-EndpointFile` | Gegenstellen für die Proben, Standard `endpoints.json` neben dem Skript; fehlt sie, gibt es keine Proben |
| `-IncludeCommandLine` | Befehlszeilen der Prozesse mitschreiben (können sensible Daten enthalten) |
| `-NoCitrix` | Citrix-ICA/EUEM-Messwerte nicht erfassen |
| `-CitrixMetricFilter` | Regex, welche numerischen Citrix-WMI-Eigenschaften erfasst werden |
| `-Simulate` | spielt ein 60-minütiges Drehbuch mit acht Vorfällen ab statt das lokale System zu messen (läuft auch unter Linux/macOS, verlangt `-DurationMinutes 60` oder mehr) |

### 2. Auswerten (am besten auf einem anderen Rechner)

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

**Uhrzeiten:** `-From`, `-To` und `-ReportedTime` sind Ortszeit des gemessenen Servers – dieselbe Zeit, die der
Bericht überall anzeigt –, auch wenn der auswertende Rechner in einer anderen Zeitzone steht.

**Wo auswerten:** Lange Aufzeichnungen besser auf einem anderen Rechner als dem Worker auswerten. Die Auswertung
belegt einen Kern und für acht simulierte Stunden rund 600 MB Arbeitsspeicher (gemessen unter PowerShell 7);
unter Windows PowerShell 5.1 kann sie dafür eine Minute oder länger brauchen.

| Parameter | Bedeutung |
|---|---|
| `-Path` | Aufzeichnungsordner |
| `-OutFile` | Zieldatei, Standard `<Path>\report.html` |
| `-From`, `-To` | nur Messungen in diesem Zeitraum bewerten, als Ortszeit des gemessenen Servers; liegt der Zeitraum außerhalb der Aufzeichnung, nennt die Meldung deren Zeitraum |
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

## Demo-Bericht

**[➜ Demo-Bericht öffnen](https://kaimunko2.github.io/WorkerPerf/)** – der Bericht einer simulierten Stunde auf dem
erfundenen Worker `SIM-VDA01`: acht Vorfälle (CPU, Arbeitsspeicher, Datenträger, Dateiserver, Profilcontainer, zwei
Verzögerungen ohne Engpass auf dem Worker, ein Dauerzustand der Netzstrecke eines Benutzers). Alle Namen und Werte
stammen aus der Simulation; echte Messdaten enthält die Seite nicht.

Die Seite liegt als `pages/index.html` im Repository. Der Workflow `.github/workflows/pages.yml` veröffentlicht bei
jedem Push auf `main`, der diesen Ordner ändert, **nur den Ordner `pages/`** auf GitHub Pages – nichts sonst aus dem
Repository. Einmalig einzurichten:

1. *Settings → Pages → Build and deployment → Source*: **GitHub Actions** wählen.
2. Den Branch nach `main` übernehmen (oder den Workflow unter *Actions* von Hand starten). Danach ist die Demo unter
   <https://kaimunko2.github.io/WorkerPerf/> erreichbar.

Zu beachten: Für ein privates Repository setzt GitHub Pages einen bezahlten Plan voraus (GitHub Pro, Team oder
Enterprise), und die veröffentlichte Seite ist **öffentlich**, auch wenn das Repository privat bleibt.

Demo neu erzeugen (zum Beispiel nach Änderungen am Bericht):

```powershell
$run = .\src\Start-WorkerPerfCapture.ps1 -Simulate -DurationMinutes 60 -OutputPath .\demo
.\src\New-WorkerPerfReport.ps1 -Path $run -OutFile .\pages\index.html
```

## Der Bericht

| Reiter | Inhalt |
|---|---|
| **Befunde** (Startreiter) | ein Satz mit der Zahl der Vorfälle je Typ, Zeitleiste, Vorfallsliste, Soll-Ist-Tabelle, Grenzen der Aussage, Messqualität |
| **Übersicht** | je Messwert eine Kachel mit Maximum, Ø, P95 und Bewertung gegen das Soll, CPU und RAM gestapelt nach Sitzung oder Anwendung, Host-Verläufe für CPU, Speicher, Eingabeverzögerung, Datenträger, Freigaben, Gegenstellen, Netzwerk, Sitzungszahl |
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
  Ereignisse und Dauerzustände im Hintergrund. Vorfälle im Umfeld und Dauerzustände zeigen nur Belege ihrer
  eigenen Befunde (eigene Sitzung, eigene Gegenstelle), keine Ereignisse des Zeitraums. Ein Klick auf einen
  Benutzer, eine Anwendung oder einen Prozess öffnet ihn im jeweiligen Reiter.
- **Fokus:** mit `-FocusUser` und `-ReportedTime` nennt der Kopf den Benutzer und die gemeldete Uhrzeit;
  Vorfälle des Benutzers stehen zuerst, Vorfälle bis 15 Minuten um die gemeldete Uhrzeit sind gekennzeichnet.
- **Soll-Ist-Tabelle:** je Messwert Soll, Bewertung, Ø, P95, Maximum, die Zeitanteile normal / auffällig /
  kritisch als Balken und in Zahlen, die am stärksten betroffene Instanz und die Herkunft des Sollwerts mit
  Link auf die Quelle. Nicht gemessene Werte stehen mit `○ nicht gemessen` und dem Grund darin. Bei Messwerten
  mit mehreren Instanzen (Sitzungen, Laufwerke, Freigaben, Gegenstellen) gelten Ø, P95 und Maximum für die
  jeweils schlechteste Instanz je Zeitpunkt.
- **Bewertung von Kacheln und Tabellenzeilen:** eine Regel für Kacheln, Tabelle und Vorfälle. `◆ kritisch` oder
  `▲ auffällig` ist ein Messwert nur, wenn er einen Befund hat, also die Schwelle so lange überschritten war, wie
  `minTicks` verlangt. Einzelne Überschreitungen darunter lassen die Bewertung bei `● normal` und stehen als
  „einzelne Überschreitungen" dabei; die Zeitanteile und das Maximum zeigen sie weiterhin.
- Ohne Vorfall sagt der Reiter das ausdrücklich: „Keine Schwelle wurde überschritten." oder, wenn einzelne Werte
  über einer Schwelle lagen, ohne einen Befund zu bilden, „Kein Vorfall. Einzelne Überschreitungen ohne Befund …"
  mit Messwert und Maximum. Dazu listet er die gemessenen und die nicht gemessenen Werte.
- **Nicht gemessen:** Fehlt die Eingabeverzögerung, sagt ein Vorfall „Eingabeverzögerung nicht gemessen; betroffene
  Sitzungen sind nicht bestimmbar." Fehlt der Messwert einer Worker-Ressource, schließt eine „Verzögerung ohne
  Engpass" einen Engpass dort nicht aus und nennt die fehlenden Messwerte.
- **Messqualität:** verspätete oder ausgelassene Takte, Messdauer, Zeit im Verdichtungsmodus, Anteil des
  Collectors, übersprungene unlesbare Zeilen und fehlgeschlagene Abfragen der Datenquelle. Der Kopf des Berichts
  sagt, wenn eine Aufzeichnung nicht regulär oder mit einem Fehler endete.

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
  eines Benutzers. Er steht als eigener Vorfall am Ende der Liste und als Hintergrund bei den Vorfällen, in deren
  Zeitraum er fortbesteht (der Dauerzustand einer Sitzung nur bei Vorfällen dieser Sitzung).
- **Hauptverursacher** ist die Anwendung in einer Sitzung mit dem größten Anteil an der führenden Ressource des
  Vorfalls – genannt erst ab einem Anteil von 10 %. Erreicht ihn niemand, sagt der Bericht das („Kein einzelner
  Hauptverursacher …"). Beim Arbeitsspeicher zählt der höchste Stand des Working Set im Fenster, sodass auch ein
  Prozess genannt wird, der mit dem Vorfall endet.
- **Begleiter** ist ein Schutzprodukt (etwa Microsoft Defender), das in einem Vorfall mindestens 10 % der
  Last trägt, weil es die Dateien des eigentlichen Verursachers prüft. Der Bericht nennt dann auch den größten
  I/O-Erzeuger im Fenster; meist hilft ein Scan-Ausschluss. Hat das Schutzprodukt selbst den größten Anteil, heißt
  es **größter Verbraucher**: Lief im Fenster ein Virenscan, rät der Bericht, Zeitplan und Umfang des Scans zu
  prüfen, sonst die Scan-Ausschlüsse.
- **Normalwert** („sonst … %") ist der Anteil desselben Prozesses, derselben Anwendung oder Sitzung außerhalb
  der Vorfälle (Dauerzustände ausgenommen); ohne solche Messungen steht ein Strich. Ein hoher Anteil mit
  niedrigem Normalwert zeigt einen Ausreißer, ein hoher Anteil mit gleich hohem Normalwert einen gewohnten
  Großverbraucher.
- Prozesse, die zwischen zwei Schnappschüssen starten *und* enden, werden nicht erfasst; für einen beendeten
  Prozess fehlt der Verbrauch seit dem letzten Schnappschuss. Ein Prozess, der im Intervall startet, bekommt
  seine bis dahin verbrauchte CPU-Zeit diesem Intervall zugerechnet.
- **Schwellwerte** stehen mit Herkunft und Quelle in `src\thresholds.json`. Alle Werte sind Startwerte. Die
  Citrix-Werte (CPU- und RAM-Auslastung, ICA Round Trip, ICA-Netzwerklatenz) stammen aus Suchtreffern zur
  Citrix-Dokumentation, nicht aus deren Volltext; sie sind dort und im Bericht entsprechend gekennzeichnet und
  vor produktiver Nutzung zu prüfen.

## Datenformat

Je Lauf ein Ordner mit (Format 2):

| Datei | Zeilen | Inhalt |
|---|---|---|
| `meta.json` | – | Formatversion, Host, Betriebssystem, CPUs, RAM, Takte, Start/Ende, Endegrund (`EndReason`, bei `error` mit `EndMessage`), Collector-PID, Gegenstellen, verfügbare Datenquellen, Fehler der Datenquelle je Quelle (`SourceErrors`) |
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
| `probes.csv` | je Probe | Verbindungszeit je Gegenstelle; bei einem Fehler die Fehlerklasse und die Dauer bis zum Abbruch |
| `events.csv` | je Ereignis | Defender-Scans, AppLocker-Sperren und andere relevante Ereignisse |

`T` ist die laufende Nummer des Takts, `P` die des Schnappschusses, `K` verweist auf `procinfo.csv`.
Die CSVs lassen sich auch direkt in Excel, Power BI o. ä. weiterverwenden. Die Auswertung liest nur die
Formatversion 2 und nennt bei einer anderen beide Versionen.

**Größenordnung:** Die simulierte Stunde (25 Sitzungen, rund 280 Prozesse) belegt etwa 5 MB;
Prozesszeilen entstehen nur für Prozesse, die sich seit dem letzten Schnappschuss verändert haben.

## Datenquellen

| Bereich | Quelle | Stand |
|---|---|---|
| Alle Signale | Simulation: festes 60-Minuten-Drehbuch mit acht Vorfällen (`-Simulate`) | vorhanden, in den Tests geprüft |
| Verfügbarkeit der Quellen auf einem VDA | Quellen-Prüfskript `Test-WorkerPerfSources.ps1` | auf einem VDA gelaufen (Windows Server 2022, de-DE, VMware, Citrix), zweimal: mit angemeldeten Benutzern und fast leer |
| Windows-Datenquelle des Collectors | `src/WorkerPerf.Sources.Windows.ps1`, Quellen in der Tabelle unten | geschrieben; unter Linux mit nachgestellten Windows-Aufrufen getestet, **auf einem echten Server noch nicht gelaufen** |

Die Windows-Datenquelle liest die Leistungsindikatoren über die .NET-Schnittstelle
`System.Diagnostics.PerformanceCounterCategory` mit den **englischen** Namen. Das funktioniert unabhängig von
der Sprache der Oberfläche; auf dem geprüften deutschen VDA lieferte dieser Weg für jede Kategorie Werte. Jeder
Wert entsteht aus zwei Lesungen im Abstand eines schnellen Takts (`CounterSample.Calculate`).

| Signal | Quelle (Kategorie / Zähler, Klasse) | Ergebnis des Prüfskripts |
|---|---|---|
| CPU-Auslastung | `Processor Information` / `% Processor Time`, Instanz `_Total` | vorhanden |
| Prozessor-Warteschlange | `System` / `Processor Queue Length` | vorhanden |
| Entzogene CPU-Zeit | `VM Processor` / `CPU stolen time` (VMware Tools), Instanz `_Total` | vorhanden; Zählertyp `Timer100Ns`, der Wert wird als Prozent übernommen, wie der Zählertyp ihn definiert. Ob die VMware Tools den Rohwert in dieser Einheit liefern, ließ sich aus dem Prüfergebnis nicht entscheiden (siehe Offene Punkte) |
| Arbeitsspeicher | `Memory` / `Available Bytes`, `Committed Bytes`, `Commit Limit`, `Pages Input/sec` | vorhanden |
| Datenträger gesamt | `PhysicalDisk` / Bytes, Zugriffe und Warteschlange, Instanz `_Total` | vorhanden |
| Netzwerk | `Network Interface` / `Bytes Received/sec`, `Bytes Sent/sec`, Summe aller Adapter | vorhanden |
| Antwortzeit je Laufwerk | `LogicalDisk` / `Avg. Disk sec/Read`, `Avg. Disk sec/Write`, Zugriffe, Bytes, Warteschlange | vorhanden; eingebundene Profilcontainer erscheinen als eigene Instanz unter ihrem Einhängepfad |
| Antwortzeit je Freigabe | `SMB Client Shares` / `Avg. sec/Read`, `Avg. sec/Write`, Anfragen, Bytes | vorhanden; Instanzen heißen `\server\freigabe` mit einem Schrägstrich, `shares.csv` schreibt `\\server\freigabe` |
| Eingabeverzögerung je Sitzung | `User Input Delay per Session` / `Max Input Delay`, Instanz = Sitzungs-ID | vorhanden; Zählertyp `AverageCount64` (siehe unten) |
| Eingabeverzögerung je Prozess | `User Input Delay per Process` / `Max Input Delay`, Instanz `<Sitzung>:<PID> <Name>` | vorhanden |
| ICA-Latenz | `ICA Session` / `Latency - Last Recorded` (und weitere Zähler nach `-CitrixMetricFilter`), Instanz `<WinStation> (<Benutzer>)` | vorhanden; ohne verbundene ICA-Sitzung hat die Kategorie keine Instanzen |
| ICA Round Trip | `root\citrix\euem` / `Citrix_Euem_RoundTrip` (`RoundtripTime`, `NetworkLatency`) | Klasse vorhanden; Werte zeigte das Prüfskript nicht |
| Profilcontainer | `MSFT_Disk` mit `BusType` 15, Partitionen und Zugriffspfade | vorhanden: Citrix Profile Management, drei Container je Benutzer; Speicherort und Einhängepfad nennen beide den Benutzer |
| Prozesse, Dienste, Sitzungen | `Win32_Process`, `Win32_Service`, WTS-Schnittstelle | vorhanden; ein Prozess-Schnappschuss von 800 Prozessen dauerte etwa 0,4 s |
| Ereignisse | Protokolle `Microsoft-Windows-Windows Defender/Operational` (1000, 1001, 1002, 2000) und `Microsoft-Windows-AppLocker/EXE and DLL`, `.../MSI and Script` (8004, 8007) | lesbar |
| Verbindungsproben | TCP-Verbindungsaufbau zu den Gegenstellen aus `endpoints.json`, Zeitlimit 2 s | nicht geprüft (beim Prüflauf keine Datei mit Gegenstellen) |

Auf dem geprüften VDA fehlte keine der Quellen. Fehlt eine Kategorie, Klasse oder ein Protokoll auf einem
anderen Worker, meldet der Collector das Signal beim Start als nicht verfügbar (`meta.json`, `Sources`); es
erscheint im Bericht als „nicht gemessen". Die CIM-Klassen `Win32_PerfRawData_*` nutzt der Collector nicht; für
`VM Processor` gab es auf dem VDA keine.

**Schneller Takt 2 s und Eingabeverzögerung:** `Max Input Delay` ist ein fortlaufender Zähler (`AverageCount64`):
Der Rohwert wächst um die höchste Verzögerung seit der letzten Abfrage, der Basiswert um eins je Abfrage. Im
Prüfergebnis wuchs der Basiswert bei Abfragen im Abstand von 1 s und von 2 s jeweils um eins; der Wert einer
Abfrage alle 2 s ist also die höchste Verzögerung der ganzen 2 Sekunden. Der Standard von `-FastIntervalSeconds`
bleibt deshalb 2 s. Liest ein zweites Programm denselben Zähler gleichzeitig (etwa die Leistungsüberwachung),
teilen sich die Abfragen auf, und der Collector sieht den Mittelwert zweier Höchstwerte.

Der Collector spricht seine Datenquelle über eine feste Schnittstelle an: die Simulation (`-Simulate`) oder die
Windows-Datenquelle. Was die Aufzeichnung als verfügbar oder nicht verfügbar meldet, steht in `meta.json`
und im Bericht unter „Messqualität"; nicht verfügbare Signale erscheinen als „nicht gemessen" und werden
nicht bewertet.

## Datenschutz

Die Aufzeichnung enthält personenbezogene Daten (Benutzernamen, Clientnamen, genutzte Anwendungen
und Zeiten, optional Befehlszeilen). Vor dem Einsatz Zweck, Aufbewahrung und ggf. die Beteiligung
von Betriebsrat/Datenschutz klären und die Ausgabeordner entsprechend schützen. Aufzeichnungen und
Berichte gehören nicht ins Repository; `.gitignore` schließt Aufzeichnungsordner, CSV- und HTML-Dateien aus.
Im Ergebnis des Prüfskripts sind Benutzer-, Domänen-, Client- und Servernamen sowie Konten-SIDs maskiert.
Namen in freiem Text kann das Skript nicht sicher erkennen; nach einer Durchsicht
([docs/vda-probe/README.md](docs/vda-probe/README.md#vor-der-weitergabe-durchsehen)) darf die Datei unter
`docs/vda-probe/` abgelegt werden.

## Offene Punkte

- **Windows-Datenquelle auf einem echten Server:** noch nicht gelaufen. Erster Schritt ist eine Kurzmessung
  (`Start-WorkerPerfCapture.ps1 -DurationMinutes 10` in einer administrativen Konsole auf einem Worker mit
  angemeldeten Benutzern, danach `New-WorkerPerfReport.ps1`). Zu prüfen: keine Warnungen zu Quellen, die laut
  Prüfskript vorhanden sind; Werte in jeder Spalte von `ticks.csv`; Profilcontainer in `volumes.csv` mit
  Sitzung; ICA-Werte in `citrix.csv` mit Sitzung; die Messdauer je Takt (`CollectMs`) deutlich unter 2 s.
- **Einheit der entzogenen CPU-Zeit:** Der Zähler `VM Processor` / `CPU stolen time` meldet den Typ
  `Timer100Ns`; der Collector übernimmt den Wert so als Prozent. Auf dem geprüften VDA war er sehr klein
  (0,00015 %). Liefern die VMware Tools den Rohwert in Millisekunden statt in 100 ns, ist der wahre Wert
  10.000-mal größer. Bei der ersten Messung mit der CPU-Bereitschaft (CPU Ready) des Hypervisors vergleichen.
- **Zuordnung der ICA-Werte zur Sitzung:** über den Namen der WinStation (`ICA-CGP 2` gegen `ICA-CGP#2`),
  sonst über den Benutzernamen, wenn er nur eine Sitzung hat. Die Schreibweise der WinStation-Namen hat das
  Prüfskript nicht erfasst.
- **Rollen:** In `roles.json` sind für Arctic Wolf Aurora der Dienst und Prozess `CylanceSvc` eingetragen. Für
  Nexus KIS und den Oracle-Client zeigte das Prüfergebnis keinen eindeutigen Prozess; ihre Prozessnamen bei der
  ersten Messung mit angemeldeten Anwendern ergänzen.
- **Datenmenge:** Ob eine Messung über 8 Stunden mit vielen Prozessen (1.500) unter 100 MB bleibt, ist nicht
  geprüft; `sessions.csv` und `citrix.csv` schreiben jede Sitzung bei jedem Schnappschuss. Die Kategorie
  `ICA Session` hat rund 80 Zähler je Sitzung; mit dem Standard von `-CitrixMetricFilter` (Latenz, Round Trip,
  Bandbreite) und ohne Bandbreiten von 0 bleiben je Sitzung und Schnappschuss etwa 5 bis 10 Zeilen.
- **Eingabeverzögerung mit `minTicks` 1:** Jeder einzelne Takt ab 150 ms bildet einen Befund. Auf einem echten
  Worker kann das viele kurze Vorfälle erzeugen und Sitzungen als „betroffen" zählen, die nur einen kurzen
  Ausschlag hatten. Mit der ersten echten Aufzeichnung ansehen und `minTicks` in `thresholds.json` anpassen.
- **Speicher-Zuordnung über Working Sets:** Unter Speicherdruck verkleinert Windows die Working Sets; der
  Verursacher kann dadurch kleiner erscheinen. Private Bytes werden mit aufgezeichnet, aber noch nicht für die
  Zuordnung verwendet.
- **`direction: low`:** Schwellen, die bei kleinen Werten anschlagen, wertet die Befund-Logik aus; Markierungen
  und Soll-Linien der Seite unterstützen bisher nur `direction: high` (kein mitgelieferter Schwellwert nutzt `low`).
- **Verdichtung „alle 5 s":** Die Spezifikation nennt 5 Sekunden; tatsächlich entstehen die Schnappschüsse im
  Takt von 2 s, also alle 6 Sekunden.
- **Normalwert eines neu gestarteten Prozesses:** Er wird über Schnappschüsse gemittelt, in denen der Prozess
  noch nicht lief, und fällt dadurch zu klein aus.
