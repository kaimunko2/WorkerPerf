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
> - Was die laufende Messung den Worker selbst kostet und woran man es ablesen kann:
>   [Auswirkung der Messung auf den Worker](#auswirkung-der-messung-auf-den-worker).
> - Auswertung, Befund-Logik und Bericht sind fertig und mit der Simulation getestet; mit ihr lässt sich die ganze
>   Kette [ohne VDA ausprobieren](#ohne-vda-ausprobieren).
> - **Ereignisse, Abstürze und Drucken:** Auswertung und Bericht sind fertig und mit der Simulation getestet
>   ([Vorfälle aus Ereignissen](#vorfälle-aus-ereignissen)). Die Windows-Datenquelle liest alle Protokolle aus
>   `events.json`, den Rückblick, die Treiberliste und die Zähler der Druckwarteschlangen. **Auf einem echten Server
>   ist dieser Teil noch nicht gelaufen**; getestet ist er unter Linux mit nachgestellten Windows-Aufrufen.
> - **Maskierte Berichte:** Die Auswertung kann Namen im Bericht durch Ersatznamen wie „Benutzer 01" ersetzen
>   (`-Mask Personen` oder `-Mask Alles`, siehe [Bericht maskiert weitergeben](#bericht-maskiert-weitergeben)).
>   Das ist fertig und mit der Simulation getestet; **unter Windows PowerShell 5.1 auf einem Server ist es noch
>   nicht gelaufen.**
> - **Demo ansehen:** [Bericht einer simulierten Stunde mit acht Leistungsvorfällen und vier Vorfällen aus
>   Ereignissen](https://kaimunko2.github.io/WorkerPerf/) (GitHub Pages; Einrichtung siehe [Demo-Bericht](#demo-bericht)).

Zeichnet Performance und Ressourcenverbrauch eines Citrix-Terminalserver-Workers
(Citrix DaaS / CVAD Multi-Session VDA, Shared Desktop) auf und wertet sie für einen
Messzeitraum aus: Der Bericht nennt Engpässe als **Vorfälle**, ihren Hauptverursacher bis auf
Sitzung, Anwendung und Prozess, die betroffenen Sitzungen und den Vergleich mit dem Soll. Dazu kommen Störungen
aus den Windows-Ereignisprotokollen – Abstürze und Hänger von Anwendungen, ausgefallene Dienste, Druckprobleme,
Profil- und Systemfehler – als eigene Vorfälle mit Hinweisen auf die Ursache, die Tage vor der Messung und der
Zustand des Druckens.

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

**Ereignisse und Drucken:** Bei jedem regulären Schnappschuss liest der Collector die neuen Ereignisse der
Protokolle aus `src\events.json` (mit einer Obergrenze je Abruf) und die Zähler der Druckwarteschlangen. Je
Ereignis speichert er Zeit, Protokoll, Quelle, Kennung, Stufe, Gruppe und Art, wo vorhanden Anwendung und Version,
fehlerhaftes Modul und Version, Fehlercode, Prozess, Sitzung, Benutzer, Drucker, Treiber und Dienst, und die erste
Zeile des Meldungstexts (höchstens 300 Zeichen). Die Felder kommen aus den Datenfeldern des Ereignisses, nicht aus
dem übersetzten Text. Beim Start liest er einmalig die Ereignisse der letzten `-EventLookbackDays` Tage (ohne
Sitzungsereignisse) in `events_before.csv` und die installierten Druckertreiber in `printdrivers.csv`. Erreicht ein
Protokoll beim Rückblick die Obergrenze, vermerkt `meta.json` das (`LookbackCapped`), und der Bericht sagt, dass der
Rückblick für dieses Protokoll unvollständig ist. Der Collector schaltet dafür kein Protokoll ein und ändert keine
Einstellung. **Stand:** Die Windows-Datenquelle liest das alles; auf einem echten Server ist sie dafür noch nicht
gelaufen (siehe [Datenquellen](#datenquellen)).

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
| `-EventLookbackDays` | beim Start die Ereignisse so vieler Tage vor dem Start in `events_before.csv` lesen, 0–90, Standard 7; 0 schaltet den Rückblick ab |
| `-Simulate` | spielt ein 60-minütiges Drehbuch mit acht Leistungsvorfällen und vier Vorfällen aus Ereignissen ab statt das lokale System zu messen, mit einem simulierten Rückblick über sieben Tage, Treiberliste und Warteschlangen (läuft auch unter Linux/macOS, verlangt `-DurationMinutes 60` oder mehr) |

### 2. Auswerten (am besten auf einem anderen Rechner)

```powershell
.\src\New-WorkerPerfReport.ps1 -Path D:\WorkerPerf\VDA01_20260101-070000
# nur einen Ausschnitt bewerten:
.\src\New-WorkerPerfReport.ps1 -Path .\VDA01_20260101-070000 -From '2026-01-01 09:00' -To '2026-01-01 11:30'
# Meldung eines Benutzers: seine Vorfälle und die um die gemeldete Uhrzeit hervorheben
.\src\New-WorkerPerfReport.ps1 -Path .\VDA01_20260101-070000 -FocusUser 'CONTOSO\mmuster' -ReportedTime '2026-01-01 10:15'
# Benutzer und Clients im Bericht ersetzen:
.\src\New-WorkerPerfReport.ps1 -Path .\VDA01_20260101-070000 -Mask Personen
# auch Server, Freigaben, Domänen, Adressen und Drucker ersetzen, Bericht außerhalb des Aufzeichnungsordners ablegen:
.\src\New-WorkerPerfReport.ps1 -Path .\VDA01_20260101-070000 -Mask Alles -OutFile D:\Weitergabe\bericht.html
# dazu die Zuordnung der Ersatznamen zu den echten Namen behalten (nicht weitergeben):
.\src\New-WorkerPerfReport.ps1 -Path .\VDA01_20260101-070000 -Mask Alles -OutFile D:\Weitergabe\bericht.html -MaskMapFile D:\WorkerPerf\bericht.maskmap.json
```

Erzeugt `report.html` im Aufzeichnungsordner (oder `-OutFile`). Die Auswertung bewertet jede Messreihe
gegen die Schwellwerte, fasst die Befunde zu Vorfällen zusammen (Engpass auf dem Worker, Verzögerung
ohne Engpass, Umfeld, Dauerzustand), nennt Betroffene und Verursacher im Klartext und stellt alle
Messwerte dem Soll gegenüber. Aus den Ereignissen bildet sie Vorfälle aus Ereignissen und gleicht sie mit der
Messung ab (siehe [Vorfälle aus Ereignissen](#vorfälle-aus-ereignissen)). Findet sie nichts, sagt der Bericht das
ausdrücklich.

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
| `-RoleFile` | Rollen (Hauptanwendung, Sicherheit, Profil, Citrix, System, Drucken), Standard `roles.json` neben dem Skript |
| `-FocusUser` | gemeldeter Benutzer als `Benutzer` oder `Domäne\Benutzer` (Groß-/Kleinschreibung egal); unbekannte Namen brechen nicht ab |
| `-ReportedTime` | gemeldete Uhrzeit in der Ortszeit des gemessenen Servers; Vorfälle bis 15 Minuten davor oder danach werden hervorgehoben. Liegt sie vor Beginn der Messung, nennt der Block „Vor der Messung" die Ereignisse bis 15 Minuten um diese Uhrzeit |
| `-TopProcesses` | Zahl der Einzelprozesse je Rangliste (CPU-Zeit, Spitzenspeicher), Standard 150 |
| `-Mask` | Namen im Bericht ersetzen: `Personen` (Benutzer und Clients) oder `Alles` (auch Server, Freigaben, Domänen, Adressen, Drucker); siehe [Bericht maskiert weitergeben](#bericht-maskiert-weitergeben) |
| `-MaskMapFile` | nur mit `-Mask`: schreibt die Zuordnung der Ersatznamen zu den echten Namen in diese Datei; ohne den Parameter entsteht keine solche Datei |

Schwellwerte, Rollen und die Liste der Ereignisse (`events.json`) werden erst bei der Auswertung gelesen. Eine
Messung lässt sich deshalb jederzeit mit geänderten Dateien neu auswerten, etwa nachdem die Prozessnamen der
Hauptanwendung in `roles.json` eingetragen sind.

### Bericht maskiert weitergeben

Soll ein Bericht an jemanden gehen, der die Namen nicht sehen soll (zum Beispiel an einen Dienstleister), ersetzt
die Auswertung mit `-Mask` bestimmte Arten von Namen durch Ersatznamen. Es gibt zwei Stufen:

- `-Mask Personen` ersetzt die Namen von Benutzern und Clients, auch in Pfaden und Sitzungsnamen, und die
  Konten-SIDs.
- `-Mask Alles` ersetzt zusätzlich die Namen von Servern, Freigaben, Domänen, Adressen und Druckern.

Andere Namen und Angaben bleiben stehen (siehe Tabelle und „Grenzen" weiter unten).

| | `-Mask Personen` | `-Mask Alles` |
|---|---|---|
| Benutzernamen | Benutzer 01, 02 … | ebenso |
| Clientnamen | Client 01, 02 … | ebenso |
| Benutzer in Pfaden und Instanznamen (Profilordner, Containerpfade, Sitzungsnamen) | ersetzt | ebenso |
| Konten-SIDs | ersetzt | ebenso |
| Server- und Computernamen, auch der Worker selbst | bleiben | Server 01, 02 … |
| Freigaben | bleiben | Freigabe 01, 02 … |
| Domänen | bleiben | Domäne 01 … |
| IP-Adressen | bleiben | Adresse 01 … |
| Namen von Druckern und Warteschlangen | bleiben | Drucker 01 … |
| Anwendungs-, Prozess-, Dienst-, Treiber- und Druckermodellnamen | bleiben | bleiben |
| Meldungstext von Ereignissen | entfällt; Art und Quelle bleiben | ebenso |
| Befehlszeilen, falls aufgezeichnet | entfallen | entfallen |

Ein maskierter Bericht nennt die Stufe oben auf der Seite, unter der Überschrift, zum Beispiel „Maskiert: alle Namen
(Benutzer, Clients, Server, Freigaben, Domänen, Adressen, Drucker ersetzt)". Der Hinweis erscheint auch im Ausdruck.
Fehlt er, ist der Bericht nicht maskiert.

**So wird ersetzt:**

- Derselbe Name hat überall im Bericht denselben Ersatznamen. Ersetzt werden nur ganze Namen, ohne Rücksicht auf
  Groß- und Kleinschreibung.
- Alle Berichte einer Aufzeichnung verwenden dieselben Ersatznamen: der ganze Bericht ebenso wie Ausschnitte mit
  `-From` und `-To`. Für eine andere Aufzeichnung gelten andere Ersatznamen.
- Ein Ordnername unter `<Laufwerk>:\Users\` gilt als Benutzername, auf jedem Laufwerk und auch für Konten ohne
  Sitzung in der Messung. Legt Windows einen zweiten Ordner für denselben Benutzer an (`name.DOMÄNE`,
  `name.DOMÄNE.001` oder `name.001`), gehört er zum Benutzer `name` und erhält dessen Ersatznamen; der Zusatz bleibt
  bei `-Mask Personen` stehen, bei `-Mask Alles` wird die Domäne darin ersetzt. Keine Benutzer sind die Ordner von
  Windows selbst (`Public`, `Default`, `Default User`, `All Users`), das vorübergehende Profil (`TEMP`,
  `TEMP.<Domäne>`), die Konten der Einrichtung (`defaultuser0` …), die Ordner von IIS-Anwendungspools
  (`DefaultAppPool`, `.NET v4.5` …) und Konten, die keine Person sind (`SYSTEM` und die anderen Konten aus
  `events.json`).
- Ein vollständiger Hostname wie `fs01.sim.local` und sein erster Teil `fs01` sind derselbe Server und erhalten bei
  `-Mask Alles` denselben Ersatznamen; der Rest (`sim.local`) gilt als Domäne. Ausgenommen ist ein erster Teil, der
  ein Wort des Berichts ist (etwa `proxy`) oder schon als Name anderer Art vorkommt (etwa als Domäne).
- Die Bezeichnungen, die Sie selbst vergeben (die Namen und Rollen der Gegenstellen in `endpoints.json`, die
  Bezeichnungen der Rollen in `roles.json`), schützen keinen Server, keine Freigabe, Domäne, Adresse und keinen
  Drucker: bei `-Mask Alles` wird ein solcher Name darin überall ersetzt, wo er nicht an Buchstaben oder Ziffern
  grenzt. Aus „Dateiserver fs01", „Dateiserver-fs01", „fs01 (Dateiserver)" und „FS01/Profile" wird jeweils
  „Server 02"; heißt der Host `oracle.sim.local`, wird aus „Oracle-Listener" „Server 03-Listener". Einen Benutzer-
  oder Clientnamen ersetzen sie nur, wo er darin als eigenes Wort steht; ein Benutzer `oracle` bleibt in
  „Oracle-Listener" stehen.
- Ein Personenname geht einem Produktnamen vor. Heißt ein Benutzer wie ein Programm, ein Dienst oder ein Hersteller
  (zum Beispiel `hp`), wird dieses Wort dort ersetzt, wo es allein steht. Mehrteilige Produktnamen, etwa der Name
  eines Druckertreibers, bleiben stehen.
- Meldungstexte von Ereignissen, Befehlszeilen und die Fehlermeldungen fehlgeschlagener Abfragen entfallen im
  maskierten Bericht. Sie können Namen enthalten, die die Auswertung nicht kennt. Art und Quelle der Ereignisse
  bleiben; wo sonst die Meldung stünde, steht „Meldung entfernt (maskiert)".
- Ein mit `-FocusUser` gemeldeter Benutzer, den die Aufzeichnung nicht kennt (Tippfehler, andere Schreibweise, ein
  anderer Worker), erscheint im maskierten Bericht als „(Name entfernt)". Ein gefundener Benutzer erhält seinen
  Ersatznamen.
- Die Aufzeichnung selbst wird nie verändert und enthält immer die echten Namen. Die Maskierung betrifft nur den
  Bericht. Aus derselben Aufzeichnung lässt sich jederzeit auch ein Bericht ohne Maskierung erstellen.

**Wohin mit den Dateien:**

- Bei `-Mask Alles` immer `-OutFile` angeben und eine Datei außerhalb des Aufzeichnungsordners wählen. Der Grund:
  Ohne `-OutFile` landet der Bericht im Aufzeichnungsordner. Dessen Name enthält den Namen des Workers, und die
  Konsole zeigt diesen Pfad an. Auch der Dateiname selbst darf den Worker nicht nennen; sonst bricht die Auswertung
  mit einer Meldung ab.
- Die Ordner für `-OutFile` und `-MaskMapFile` müssen schon vorhanden sein; die Auswertung legt sie nicht an und
  bricht vor der Auswertung mit einer Meldung ab, wenn einer fehlt. `-MaskMapFile` darf keine vorhandene Datei im
  Aufzeichnungsordner nennen: die Aufzeichnung wird nie verändert.
- `-MaskMapFile` schreibt eine Zuordnungsdatei: welcher Ersatzname zu welchem echten Namen gehört. Damit lassen sich
  Rückfragen zum Bericht beantworten („Wer ist Benutzer 07?"). Die Datei enthält die echten Namen. Sie gehört nicht
  zum weitergegebenen Bericht: getrennt aufbewahren und nicht weitergeben. Sie entsteht nur, wenn der Parameter
  angegeben ist. Git schließt Dateien `*.maskmap.json` aus.

**Grenzen:**

- Ein Name in einem Feld, das die Auswertung nicht als Namen kennt, bleibt stehen. Deshalb entfallen Meldungstexte
  und Befehlszeilen ganz.
- Heißt ein Benutzer (bei `-Mask Alles` auch ein Server, eine Freigabe oder ein Drucker) wie ein Wort, das der Bericht
  selbst verwendet, etwa `soll`, `zeit`, `ms` oder `hp`, wird dieses Wort überall ersetzt, auch in den Sätzen des
  Berichts: aus „Soll unter 75 %" wird „Benutzer 15 unter 75 %". Solche Sätze sind entstellt, und wer den Wortlaut
  des Berichts kennt, kann den Namen erraten. Einheiten (`ms`, `%`) und Verweise auf Dokumentation bleiben stehen.
  Die Auswertung nennt dann auf der Konsole die betroffenen Ersatznamen, nie die echten Namen, zum Beispiel
  „Hinweis: 2 Namen gleichen Woertern des Berichts (Benutzer 01, Benutzer 15) …"; diese Stellen besonders sorgfältig
  durchsehen. Ebenso wird bei `-Mask Alles` eine Warteschlange, die genau wie ihr Druckertreiber heißt (so legt
  Windows sie an), auch in der Liste der Treiber ersetzt.
- Ein Benutzer- oder Clientname, der in einer eigenen Bezeichnung nur Teil eines längeren Wortes ist, bleibt dort
  stehen: in „Oracle-Listener" ein Benutzer `oracle`. Heißen ein Benutzer und ein Server gleich, gilt der Name als
  Benutzer.
- Benutzer ohne Sitzung in der Messung erkennt die Auswertung nur in Ordnern unter `<Laufwerk>:\Users\`, in Pfaden
  der Citrix-Profilverwaltung (`…_UPM_local`), in FSLogix-Ordnern (`<SID>_<Name>`, `<Name>_<SID>`), in
  ICA-Sitzungsnamen und in den Konten der Ereignisse. In anderen Pfaden bleibt ihr Name stehen, etwa im
  Basisordner auf einer Freigabe (`\\fs01\home$\petra.klein\…`) oder in einem Gerätepfad.
- Eine IP-Adresse wird nur ersetzt, wenn sie als Host vorkommt (Gegenstelle, Verbindungsprobe, Dateiserver,
  UNC-Pfad) oder in einem Text der Aufzeichnung selbst. Steht sie nur in einem Pfad oder in einem Text des
  Berichts, bleibt sie stehen: dort lässt sie sich nicht sicher von einer Versionsnummer wie `8.2.0.114`
  unterscheiden. Eine IPv6-Adresse als Host wird als Server ersetzt („Server 03"), nicht als „Adresse".
- Andere Texte Ihrer eigenen Konfiguration, etwa die Hinweise in `thresholds.json`, sind keine Namen und bleiben,
  wie sie geschrieben sind; ein Name darin wird nur ersetzt, wenn er auch in der Aufzeichnung vorkommt.
- Ein Name, der mit dem türkischen großen I mit Punkt (`İ`) geschrieben ist, gilt nicht als derselbe Name wie seine
  Schreibweise mit kleinem `i`; die zweite Schreibweise bleibt dann stehen. Das betrifft nur Umgebungen, in denen
  solche Namen vorkommen.
- Aus dem Zusammenhang kann eine Person erkennbar bleiben, etwa als einziger Benutzer einer Anwendung oder durch die
  Uhrzeit ihrer Anmeldung.
- Deshalb den maskierten Bericht vor der Weitergabe einmal durchsehen.

Das Quellen-Prüfskript maskiert sein Ergebnis weiterhin immer, unabhängig von `-Mask`, und auf eigene Weise: mit
Platzhaltern wie `<user>` und `<server>` statt nummerierter Ersatznamen (siehe
[docs/vda-probe/README.md](docs/vda-probe/README.md#ergebnis-zurückgeben)). Der [Demo-Bericht](#demo-bericht) ist
nicht maskiert; er enthält nur die erfundenen Namen der Simulation.

### Ohne VDA ausprobieren

```powershell
$run = .\src\Start-WorkerPerfCapture.ps1 -Simulate -DurationMinutes 60 -OutputPath .\demo
.\src\New-WorkerPerfReport.ps1 -Path $run
```

Die Simulation legt zusätzlich `expected.json` ab: die Vorfälle und Muster, die die Auswertung finden soll.

## Auswirkung der Messung auf den Worker

Der Collector ist ein einzelner Prozess `powershell.exe`, der nur liest und in den Ausgabeordner schreibt. Was er auf
einem Windows-Worker kostet, ist **noch nicht gemessen**, weil die Windows-Datenquelle noch nicht auf einem echten
Server gelaufen ist. Dieser Abschnitt beschreibt, was der Collector wann tut, was das Prüfskript auf dem geprüften VDA
(6 vCPUs, 11 Sitzungen, rund 800 Prozesse) dazu gemessen hat, und woran man die Last während einer Messung abliest.
Zahlen ohne Messung sind als Schätzung gekennzeichnet.

### Was der Collector wann tut

| Wann | Was | Umfang auf dem geprüften VDA |
|---|---|---|
| jeder schnelle Takt (Standard 2 s) | je eine Lesung von zehn Leistungsindikator-Kategorien über .NET: `Processor Information`, `System`, `VM Processor`, `Memory`, `PhysicalDisk`, `Network Interface`, `LogicalDisk`, `SMB Client Shares`, `User Input Delay per Session`, `User Input Delay per Process` | rund 760 Instanzen der Eingabeverzögerung je Prozess, 27 Laufwerke (`LogicalDisk`), 11 Freigaben; die übrigen Kategorien haben nur wenige Instanzen |
| jeder Schnappschuss (Standard 15 s) | Prozessliste über CIM (`Win32_Process`), Sitzungen über die WTS-Schnittstelle, ICA-Zähler (`ICA Session`, eine Lesung) und Citrix-EUEM-Werte (CIM), Schreiben der geänderten Prozesse | `Win32_Process` für 800 Prozesse: 0,39–0,41 s je Abfrage |
| jeder reguläre Schnappschuss zusätzlich | die Ereignisprotokolle aus `events.json` seit dem letzten Abruf (eine Abfrage je Protokollname, mit dem mitgelieferten Katalog neun; je Quelle eine Auswahl mit höchstens 23 Kennungen; höchstens die ältesten 200 Ereignisse je Protokoll, die übrigen werden nur gezählt), die Zähler der Druckwarteschlangen (eine Lesung); Verbindungsproben, nur mit `endpoints.json` | Dauer der Ereignisabfragen nicht gemessen |
| jeder Stützpunkt (jeder 20. reguläre Schnappschuss, Standard alle 5 min) | Dienstliste (`Win32_Service`); Abfrage der Profilcontainer (`MSFT_Disk`, `MSFT_Partition`, je höchstens 10 s), ebenso beim ersten regulären Schnappschuss, nachdem ein neues Laufwerk eingehängt wurde (meist bei einer Anmeldung) | `Win32_Service`: 0,29 s |
| Verdichtung | solange ein Auslöser-Signal über seiner Schwelle liegt und 60 s danach: Schnappschüsse alle 6 s statt alle 15 s, je Signal höchstens 5 Minuten am Stück | – |

Alles läuft nacheinander in einer Schleife: Ein Schnappschuss entsteht innerhalb eines schnellen Takts. Dauert er
länger als der Takt, fällt der nächste Takt aus (er wird nicht nachgeholt).

### Welche Last das bedeutet

- **CPU:** Die Arbeit verteilt sich auf den Collector selbst (`powershell.exe`), den WMI-Anbieterhost
  (`WmiPrvSE.exe`, er beantwortet die CIM-Abfragen) und die Anbieter der Leistungsindikatoren.
  *Schätzung für den geprüften VDA:* Ein Schnappschuss dauerte dort 0,4 s. Selbst wenn diese 0,4 s vollständig
  einen Kern belegten, wären das alle 15 s 2,7 % eines Kerns, auf 6 vCPUs also **rund 0,4 % des Hosts**; während
  einer Verdichtung (alle 6 s) 6,7 % eines Kerns, **rund 1,1 % des Hosts**. Hinzu kommt der schnelle Takt. Was er
  unter Windows PowerShell 5.1 kostet, ist **nicht gemessen**; die erste Kurzmessung zeigt es (siehe unten).
- **Arbeitsspeicher:** ein PowerShell-Prozess. Seine Größe ist nicht gemessen; der Bericht führt ihn in der
  Prozessliste als Collector, mit Working Set und CPU-Zeit.
- **Datenträger:** Die Dateien werden fortlaufend angehängt. Die simulierte Stunde (25 Sitzungen, rund 280
  Prozesse) belegt etwa 5 MB; ob 8 Stunden mit vielen Prozessen unter 100 MB bleiben, ist offen
  (siehe [Offene Punkte](#offene-punkte)).
- **Netzwerk:** keine Last, außer den optionalen Verbindungsproben (ein TCP-Verbindungsaufbau je Gegenstelle alle
  15 s, ohne Daten).

### Was die Messung über ihre eigenen Kosten aufzeichnet

Der Bericht zeigt im Block **„Messqualität"**:

| Angabe im Bericht | woraus sie berechnet wird |
|---|---|
| Verspätete oder ausgelassene Takte | Takte, deren Abstand zum vorigen Takt mehr als das 1,5-Fache des schnellen Takts beträgt (`ElapsedSec` in `ticks.csv`) |
| Messdauer je Takt (Ø, Max) | Dauer der Lesung aller Leistungsindikatoren eines Takts (`CollectMs` in `ticks.csv`) |
| je Schnappschuss (Ø, Max) | Dauer eines Schnappschusses von der Abfrage bis zum Schreiben der Zeilen, am Stützpunkt mit der Dienstliste und der Abfrage der Profilcontainer (`CollectMs` in `snapshots.csv`); Proben und Ereignisse zählen nicht mit |
| Verdichtung | Dauer, Zahl der Takte und der zusätzlichen Schnappschüsse und ihr gemessener Abstand |
| WorkerPerf selbst … % der CPU-Zeit (Spitze … % des Hosts) | CPU-Zeit des Collector-Prozesses (PID in `meta.json`) als Anteil an der CPU-Zeit **aller aufgezeichneten Prozesse**, nicht an der Kapazität des Hosts; die Spitze ist der höchste Anteil an der Host-Kapazität in einem Schnappschuss-Intervall. Die Arbeit von `WmiPrvSE.exe` für den Collector ist darin nicht enthalten; sie steht in der Prozessliste bei `WmiPrvSE.exe` |
| Übersprungene unlesbare Zeilen | nur, wenn `ticks.csv`, `snapshots.csv`, `events.csv`, `events_before.csv`, `printdrivers.csv` oder `printqueues.csv` unlesbare Zeilen enthalten; `ticks.csv` und `snapshots.csv` stehen dann immer, die übrigen Dateien nur mit übersprungenen Zeilen |
| Rückblick unvollständig | nur, wenn ein Protokoll beim Rückblick die Obergrenze erreichte (`LookbackCapped` in `meta.json`) |
| Fehlgeschlagene Abfragen während der Aufzeichnung | je Quelle Anzahl, Zeitpunkt und Meldung des ersten Fehlers (`SourceErrors` in `meta.json`) |
| Tabelle der Quellen | welche Quellen beim Start verfügbar waren, mit Hinweis |

### Orientierungswerte

Startwerte bis zur ersten echten Messung. Maßgeblich ist der schnelle Takt (Standard 2 s): Ein Schnappschuss läuft
innerhalb der Schleife, also entscheidet seine Dauer im Vergleich zum Takt, ob Takte ausfallen.

| Angabe in „Messqualität" | unkritisch | beobachten | Messung anpassen |
|---|---|---|---|
| je Schnappschuss, Max | unter der Hälfte des Takts (unter 1 s) | bis zum Takt (1–2 s) | über dem Takt (über 2 s): dann fällt mindestens ein Takt aus |
| Messdauer je Takt, Ø | unter 10 % des Takts (unter 200 ms) | 10–25 % (200–500 ms) | über 25 % (über 500 ms): der Collector ist dann ein Viertel der Zeit beschäftigt |
| Verspätete oder ausgelassene Takte, Anteil an allen Takten | unter 1 % | 1–5 % | über 5 % |
| WorkerPerf selbst, Spitze in % des Hosts | unter 2 % | 2–5 % | über 5 % |
| Fehlgeschlagene Abfragen | keine | einzelne | dieselbe Quelle wiederholt |

### Was bei welcher Stufe zu tun ist

- **unkritisch:** nichts; die Messung kann über Stunden laufen.
- **beobachten:** die Messung weiterlaufen lassen und die Angaben nach einer Stunde erneut ansehen; bei
  Messungen über viele Stunden die erste Maßnahme unten erwägen.
- **Messung anpassen:** neu starten mit einer oder mehreren dieser Änderungen. Jede kostet Aussagekraft:

| Änderung | spart | kostet |
|---|---|---|
| `-IntervalSeconds 30` | die Hälfte der Schnappschüsse | gröbere Zuordnung zu Prozessen; kurzlebige Prozesse fehlen öfter |
| `-BurstIntervalSeconds 10`, `-BurstHoldSeconds 30` | Schnappschüsse während der Vorfälle | weniger Einzelheiten zum Verursacher genau dann, wenn es zählt |
| `-NoCitrix` | ICA- und EUEM-Abfragen | ICA Round Trip und Latenz „nicht gemessen" |
| `-CitrixMetricFilter 'Latency\|Round'` | Zeilen in `citrix.csv` | keine Bandbreiten je Sitzung |
| `-FastIntervalSeconds 3` oder `5` | ein Drittel bzw. drei Fünftel der Zählerlesungen | gröbere Zeitauflösung; kurze Spitzen erscheinen gemittelt |
| `-IncludeCommandLine` weglassen (Standard) | Befehlszeilen in der Prozessabfrage | – |
| keine `endpoints.json` | die Verbindungsproben | keine Aussage über Gegenstellen |

Den Ausgabeordner auf ein lokales Datenlaufwerk legen, nicht auf eine Freigabe und nicht in das Benutzerprofil
oder einen Profilcontainer: Sonst gehen die eigenen Schreibzugriffe über das Netz und verfälschen die gemessenen
Antwortzeiten von Freigabe oder Profil. Schon eingebaut sind: Höchstgröße `-MaxSizeMB` (Standard 500 MB), Abbruch
unter 200 MB freiem Speicherplatz (Warnung beim Start unter 1 GB), Ende über eine Datei `stop.flag` im
Ausgabeordner und über `-DurationMinutes`.

### Nebenwirkungen

- Die Skripte lesen nur; sie ändern keine Einstellungen.
- Microsoft Defender prüft die Dateien, die der Collector schreibt. Eine Ausnahme für den Ausgabeordner ist möglich,
  aber nicht nötig; die Entscheidung liegt beim Betreiber.
- Die CIM-Abfragen laufen im WMI-Anbieterhost (`WmiPrvSE.exe`) und erscheinen dort in Prozessliste und CPU-Zeit.
- Für die WTS-Schnittstelle und die Verbindungsproben übersetzt PowerShell beim Start kleine C#-Klassen (Add-Type);
  dabei entstehen kurz temporäre Dateien im Temp-Ordner des Benutzers.
- Es wird nichts installiert, kein Dienst und keine Aufgabe eingerichtet; nach dem Ende läuft nichts weiter.

### Empfehlung für den ersten Einsatz

Zuerst eine Kurzmessung von 10 Minuten auf dem Test-Worker mit angemeldeten Benutzern, in einer administrativen
Konsole (`-DurationMinutes 10`), danach den Bericht erstellen und den Block „Messqualität" mit der Tabelle oben
vergleichen. Erst dann eine Messung über mehrere Stunden starten.

## Demo-Bericht

**[➜ Demo-Bericht öffnen](https://kaimunko2.github.io/WorkerPerf/)** – der Bericht einer simulierten Stunde auf dem
erfundenen Worker `SIM-VDA01`: acht Leistungsvorfälle (CPU, Arbeitsspeicher, Datenträger, Dateiserver,
Profilcontainer, zwei Verzögerungen ohne Engpass auf dem Worker, ein Dauerzustand der Netzstrecke eines Benutzers)
und vier Vorfälle aus Ereignissen (eine Anwendung stürzt bei drei Benutzern im selben Modul ab, ein Absturz
unmittelbar nach dem Arbeitsspeicher-Engpass, ein Ausfall der Druckwarteschlange in einem Treibermodul, ein
Profilfehler bei einer Anmeldung), dazu sieben simulierte Tage vor der Messung und der Zustand des Druckens. Alle
Namen und Werte stammen aus der Simulation; echte Messdaten enthält die Seite nicht.

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
| **Befunde** (Startreiter) | ein Satz mit der Zahl der Vorfälle je Typ, Zeitleiste, Vorfallsliste, „Vor der Messung", „Drucken", Soll-Ist-Tabelle, Grenzen der Aussage, Messqualität |
| **Übersicht** | je Messwert eine Kachel mit Maximum, Ø, P95 und Bewertung gegen das Soll, CPU und RAM gestapelt nach Sitzung oder Anwendung, Host-Verläufe für CPU, Speicher, Eingabeverzögerung, Datenträger, Freigaben, Gegenstellen, Netzwerk, Sitzungszahl |
| **Sitzungen** | je Sitzung: Benutzer, Client, Dauer, Aktiv-Anteil, CPU-Anteil/-Zeit/Ø/P95/Max, RAM, Commit, I/O, ICA RTT. Detail: Sitzungsereignisse (Anmeldung, Abmeldung, Trennen, Wiederverbinden) mit Uhrzeit, Verläufe, Anwendungen und Prozesse der Sitzung, Citrix-Messwerte |
| **Anwendungen** | je Prozessname über alle Sitzungen: Instanzen, CPU, RAM gesamt und je Instanz, I/O. Detail: Verläufe und betroffene Sitzungen |
| **Prozesse** | die ressourcenintensivsten Einzelprozesse mit Verlauf (CPU, Working Set), Handles, Threads |

Alle Tabellen sind sortier- und filterbar; Zeiten erscheinen in der Ortszeit des gemessenen Servers. Ein Ereignis
erscheint in der Ortszeit seines eigenen Zeitstempels; liegt zwischen einem Tag vor der Messung und der Messung
eine Umstellung auf Sommer- oder Winterzeit, zeigt der Bericht beide jeweils in ihrer eigenen Ortszeit.

Der Reiter **Befunde** beantwortet die Frage aus der Meldung von oben nach unten:

- **Zeitleiste:** ein Balken über die ganze Messung. Jeder Vorfall ist eine Markierung von Beginn bis Ende
  mit Symbol und Farbe der Schwere (`▲ auffällig`, `◆ kritisch`); überlappende Vorfälle liegen in eigenen
  Zeilen. Neben der Markierung eines Vorfalls aus Ereignissen steht das Wort seiner Art (Absturz, Hänger, Dienst,
  Drucken, Profil, System); ein Vorfall aus einem einzigen Ereignis ist eine schmale Markierung an seinem Zeitpunkt.
  Dauerzustände stehen als schmale Linie darunter, Ereignisse als kleine Striche in einer Zeile je Gruppe
  (Anwendungen, Dienste, Datenträger, Speicher, Dateiserver, Profile, Drucken, Sitzungen, Schutzsoftware; Zeit und
  Text im Tooltip, die Uhrzeit dort in der Ortszeit des Ereignisses), die gemeldete Uhrzeit als senkrechte Linie. Ein Klick auf eine Markierung öffnet den Vorfall
  und stellt alle Diagramme auf sein Zeitfenster mit Rand. Unter der Zeitleiste stehen die Ereignisse auch als
  Liste (die ersten 200). Wertet der Bericht nur einen Ausschnitt aus (`-From`, `-To`), sagt er, wie viele Ereignisse der
  Aufzeichnung außerhalb liegen.
- **Vorfallstypen:** *Engpass* – eine Ressource des Workers (CPU, Arbeitsspeicher, Datenträger, Freigabe,
  Profilcontainer) lag über dem Soll und Benutzer spürten es. *Verzögerung ohne Engpass* – Benutzer warteten,
  ohne dass der Worker ausgelastet war; die Ursache liegt in der Anwendung oder dahinter (Datenbank, Proxy,
  Netz). *Umfeld* – auffällig ist die Strecke zum Benutzer oder eine Gegenstelle, nicht der Worker.
  *Vorfall aus Ereignissen* – ein Absturz, Hänger, Dienstausfall, Druck-, Profil- oder Systemfehler aus den
  Ereignisprotokollen (siehe [Vorfälle aus Ereignissen](#vorfälle-aus-ereignissen)).
- **Vorfallsliste:** je Vorfall Schwere, Typ und ein Absatz im Klartext. Ein Klick auf den Text klappt die
  Belege auf: Betroffene mit ihrer höchsten Eingabeverzögerung, Hauptverursacher, Verlauf der beteiligten
  Messwerte, je Ressource die Ranglisten der Prozesse, Anwendungen und Sitzungen mit Anteil und Normalwert,
  Prozesse mit der höchsten Eingabeverzögerung, Gegenstellen, ICA Round Trip, Anteil der Schutzprodukte,
  Ereignisse und Dauerzustände im Hintergrund. Vorfälle im Umfeld und Dauerzustände zeigen nur Belege ihrer
  eigenen Befunde (eigene Sitzung, eigene Gegenstelle), keine Ereignisse des Zeitraums. Ein Leistungsvorfall
  verweist auf die Vorfälle aus Ereignissen in seinem Zeitraum. Ein Vorfall aus Ereignissen zeigt aufgeklappt Anzahl,
  Zeitraum, Benutzer und Sitzungen, Anwendung und Version, fehlerhafte Module und Fehlercodes, die zutreffenden
  Muster (oder „Kein Muster erkannt"), seine Ereignisse und die zeitgleichen Leistungsvorfälle; bei mehr als 50
  Ereignissen stehen die ersten 49 und das letzte in der Liste, und der Bericht sagt das. Ein Klick auf einen
  Benutzer, eine Anwendung, einen Prozess oder einen Vorfall öffnet ihn.
- **Fokus:** mit `-FocusUser` und `-ReportedTime` nennt der Kopf den Benutzer und die gemeldete Uhrzeit;
  Vorfälle des Benutzers stehen zuerst, Vorfälle bis 15 Minuten um die gemeldete Uhrzeit sind gekennzeichnet. Liegt
  die gemeldete Uhrzeit in der Aufzeichnung, aber außerhalb des mit `-From`/`-To` gewählten Zeitraums, sagt der Kopf
  das und, wenn der Zeitraum Ereignisse der Aufzeichnung auslässt, wie viele.
- **Vor der Messung:** die Ereignisse der Tage vor dem Start, mit dem Hinweis „Für diese Zeit liegen keine
  Messwerte vor." Der Block nennt zwei Zahlen: alle Ereignisse aus diesen Tagen und davon die mit einer Vorfallsart
  (Absturz, Hänger, Dienst, Drucken, Profil, System); die Balken je Tag zählen die zweiten. Darunter stehen die
  Vorfälle dieser Tage mit Datum und Mustern, ein Hinweis, wenn der Rückblick eines Protokolls an die Obergrenze
  stieß, und mit `-ReportedTime` vor Beginn der Messung die Ereignisse bis 15 Minuten um diese Uhrzeit, wenn es
  solche gibt. Der Block sagt, was gelesen wurde: War der Rückblick abgeschaltet (`-EventLookbackDays 0`), steht nur
  das da; fehlt die Datei `events_before.csv`, sagt er das; konnte der Rückblick nicht gelesen werden, weil die
  Ereignisquellen nicht verfügbar waren (so heute unter Windows), ebenso, jeweils ohne Zahlen. Waren nur einige
  Protokolle verfügbar, nennt er die gelesenen und die nicht gelesenen, und Zahlen, Balken und Vorfälle gelten nur
  für die gelesenen. Wurden alle Protokolle gelesen und enthalten sie keine Ereignisse, sagt der Block, dass in
  diesen Tagen keine Ereignisse der erfassten Arten in den Protokollen stehen. Aufzeichnungen im Format 2 haben keinen Rückblick; dort
  erscheint der Block nur mit Ereignissen um eine gemeldete Uhrzeit vor der Messung.
- **Drucken:** die Druckertreiber mit Hersteller, Version, Bauart (Typ 3 oder Typ 4), Isolierung und ob sie an
  einem Vorfall beteiligt waren („beteiligt" oder, wenn das fehlerhafte Modul zu mehreren Treibern gehört,
  „möglicherweise beteiligt"); die Druckwarteschlangen mit der höchsten Zahl wartender Aufträge und dem Zuwachs der
  Auftrags- und „nicht bereit"-Fehler während der Messung; die Prozesse der Rolle „Drucken" mit CPU-Höchstwert und
  Arbeitsspeicher am Anfang, am Ende und höchstens, ohne Bewertung. Wurde ein Druckprozess neu gestartet, steht er
  in einer Zeile: Anfang des ersten, Ende des letzten Prozesses. Der Block erscheint nur mit Treibern oder
  Warteschlangen.
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
  Collectors, übersprungene unlesbare Zeilen (auch der Ereignis- und Druckdateien), ein unvollständiger Rückblick
  und fehlgeschlagene Abfragen der Datenquelle. Der Kopf des Berichts sagt, wenn eine Aufzeichnung nicht regulär
  oder mit einem Fehler endete.

### Vorfälle aus Ereignissen

Die Auswertung bildet aus den Ereignissen eigene Vorfälle:

| Art | entsteht, wenn |
|---|---|
| Anwendungsabsturz | eine Anwendung stürzt in einer Benutzersitzung ab; ein einzelner Absturz genügt |
| Anwendungshänger | eine Anwendung reagierte in einer Benutzersitzung nicht und wurde beendet |
| Dienstausfall | ein wichtiger Dienst endete unerwartet (Liste in `events.json`), oder ein beliebiger Dienst mindestens zweimal |
| Druckproblem | Treiberfehler, fehlgeschlagene Aufträge oder Ausfall der Druckwarteschlange; ein Absturz der Druckwarteschlange zählt hierher |
| Profilproblem | ein Profil ließ sich nicht laden oder entladen, oder die Profilverwaltung meldet Fehler |
| Systemfehler | Datenträger- oder Dateisystemfehler, Speichermangel-Warnung, Verbindungsabbruch zum Dateiserver |

Abstürze und Hänger von Prozessen ohne Benutzersitzung sind Ereignisse in der Zeitleiste; ab dem zweiten Mal
derselben Anwendung bilden sie einen Vorfall. Konten, die keine Person sind, gelten dabei nie als Benutzer: System-
und Dienstkonten wie `SYSTEM`, `DWM-1` oder Computerkonten `NAME$` (`nonPersonAccounts` in `events.json`) und die
Konten virtueller Domänen wie `NT SERVICE\MSSQLSERVER` oder `IIS APPPOOL\DefaultAppPool` (`nonPersonDomains`).
Ereignisse derselben Art und desselben Schlüssels (Anwendung, Dienst, Treiber oder Drucker, Quelle, betroffenes
Laufwerk oder Server) gehören zu einem Vorfall, solange zwischen zwei aufeinanderfolgenden höchstens 30 Minuten liegen
(`eventGroupMinutes` in `thresholds.json`). Ein Vorfall nennt Anzahl, Zeitraum, Benutzer, Versionen der Anwendung,
fehlerhafte Module mit Anzahl und ob es immer dasselbe war, und die Fehlercodes mit einer Erklärung in
Alltagssprache. In einer Benutzersitzung gilt er als `◆ kritisch`, sonst als `▲ auffällig`. Sitzungsereignisse
bilden keine Vorfälle; sie stehen in der Zeitleiste und bei der Sitzung.

Für jeden Vorfall prüft die Auswertung diese Muster und nennt alle, die zutreffen:

| Muster | trifft zu, wenn | Aussage im Bericht |
|---|---|---|
| Speichermangel | Arbeitsspeicher oder zugesagter Speicher lag in den 5 Minuten vor einem Ereignis über der kritischen Schwelle, oder Windows warnte im selben Zeitraum vor Speichermangel | „Wahrscheinlich Folge des Speichermangels." |
| nach Hänger | dieselbe Anwendung hing in derselben Sitzung höchstens 2 Minuten vor dem Absturz | „Wurde nach Nichtreagieren beendet." |
| gemeinsames Modul | mindestens zwei verschiedene Anwendungen stürzen im selben Modul ab, und das Modul ist kein allgemeines Systemmodul (Liste in `events.json`) | „Ursache liegt wahrscheinlich im Modul … (betrifft …)." |
| Druckertreiber | das fehlerhafte Modul ist eine Datei eines installierten Druckertreibers | „Das Modul … gehört zum Druckertreiber …"; gehört es zu mehreren Treibern, sagt der Bericht, dass nicht bestimmbar ist, welcher beteiligt war |
| Schutzsoftware | das fehlerhafte Modul gehört laut `roles.json` zur Schutzsoftware | „Das Modul … gehört zur Schutzsoftware …" |
| viele Benutzer | mindestens drei Benutzer, dieselbe Anwendung | „… Benutzer betroffen: spricht für Installation oder Update." |
| ein Benutzer | ein Benutzer, mindestens drei Ereignisse | „Nur … betroffen, …-mal: spricht für Profil oder Daten dieses Benutzers." |
| zeitnah | ein Datenträger-, Dateiserver-, Profil- oder Schutzsoftware-Ereignis höchstens 2 Minuten vor oder nach einem Ereignis des Vorfalls | „Zeitnah: …" mit Uhrzeit |
| zeitgleich | ein Leistungsvorfall überlappt den Zeitraum | „Zeitgleich mit Vorfall …"; beide Vorfälle verweisen aufeinander |

Trifft kein Muster zu, sagt der Bericht „Kein Muster erkannt." und nennt keine Ursache. **Die Muster sind Hinweise,
kein Beweis:** Sie zeigen, was in den Daten zusammentrifft, und formulieren vorsichtig („wahrscheinlich",
„spricht für"); die Auswertung wählt unter mehreren zutreffenden Mustern keines aus. Für die Tage vor der Messung
gelten nur die Muster ohne Messwerte (alle außer Speichermangel und zeitgleich). Die Zeitabstände stehen in
`thresholds.json`, die Listen der Protokolle, Kennungen, wichtigen Dienste, Systemmodule und Fehlercodes in
`events.json`.

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

Je Lauf ein Ordner mit (Format 3):

| Datei | Zeilen | Inhalt |
|---|---|---|
| `meta.json` | – | Formatversion, Host, Betriebssystem, CPUs, RAM, Takte, Start/Ende, Endegrund (`EndReason`, bei `error` mit `EndMessage`), Collector-PID, Gegenstellen, verfügbare Datenquellen, Fehler der Datenquelle je Quelle (`SourceErrors`), Tage des Rückblicks (`EventLookbackDays`) und die Protokolle, deren Rückblick unvollständig ist (`LookbackCapped`), und je Protokoll die Zähler `EventReadCounts` (`SkippedRecords`: nicht lesbare Datensätze, `UnformattedMessages`: Meldungstexte, die sich nicht formatieren ließen, `DroppedEvents`: Ereignisse über der Obergrenze eines Abrufs) |
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
| `events.csv` | je Ereignis der Messzeit | `Timestamp`, `Log`, `Source`, `EventId`, `Level`, `Group`, `Kind`, `App`, `AppVersion`, `Module`, `ModuleVersion`, `Code`, `Pid`, `SessionId`, `User`, `Printer`, `Driver`, `Service`, `Object`, `Text` (erste Zeile, höchstens 300 Zeichen) |
| `events_before.csv` | je Ereignis der Tage vor der Messung | dieselben Spalten wie `events.csv`; ohne Sitzungsereignisse |
| `printdrivers.csv` | je Druckertreiber, einmal beim Start | `Name`, `Manufacturer`, `Version`, `Type` (3 oder 4), `Isolation` (`none`, `shared`, `isolated`), `Files` (nur Dateinamen, mit `;` getrennt) |
| `printqueues.csv` | je regulärem Schnappschuss × Warteschlange | `Timestamp`, `Queue`, wartende Aufträge (`Jobs`), Zählerstände der Auftragsfehler (`JobErrors`) und der „nicht bereit"-Fehler (`NotReadyErrors`) |

`T` ist die laufende Nummer des Takts, `P` die des Schnappschusses, `K` verweist auf `procinfo.csv`.
Die CSVs lassen sich auch direkt in Excel, Power BI o. ä. weiterverwenden. Die Auswertung liest die Formate 2 und 3
und nennt bei einem anderen die gelesenen Versionen. Aufzeichnungen im Format 2 bleiben damit auswertbar: Ihre
`events.csv` hat nur die Spalten Zeit, Quelle, Kennung, Art und Text; die neuen Spalten gelten dort als leer, und es
gibt keinen Rückblick, keine Treiberliste und keine Warteschlangen. Defender- und AppLocker-Ereignisse erscheinen
wie bisher.

**Größenordnung:** Die simulierte Stunde (25 Sitzungen, rund 280 Prozesse) belegt etwa 5 MB;
Prozesszeilen entstehen nur für Prozesse, die sich seit dem letzten Schnappschuss verändert haben.

## Datenquellen

| Bereich | Quelle | Stand |
|---|---|---|
| Alle Signale | Simulation: festes 60-Minuten-Drehbuch mit acht Leistungsvorfällen und vier Vorfällen aus Ereignissen, dazu Sitzungs- und Defender-/AppLocker-Ereignisse, ein Rückblick über sieben Tage mit drei Vorfällen, Treiberliste und Warteschlangen (`-Simulate`) | vorhanden, in den Tests geprüft |
| Verfügbarkeit der Quellen auf einem VDA | Quellen-Prüfskript `Test-WorkerPerfSources.ps1` | auf einem VDA gelaufen (Windows Server 2022, de-DE, VMware, Citrix), zweimal: mit angemeldeten Benutzern und fast leer |
| Windows-Datenquelle des Collectors | `src/WorkerPerf.Sources.Windows.ps1`, Quellen in der Tabelle unten | geschrieben; unter Linux mit nachgestellten Windows-Aufrufen getestet, **auf einem echten Server noch nicht gelaufen** |
| Ereignisprotokolle, Rückblick, Druckertreiber, Druckwarteschlangen | Windows-Datenquelle, Quellen in der Tabelle unten | nach Prüfergebnis, auf einem echten Server noch nicht gelaufen |

Die Windows-Datenquelle liest die Leistungsindikatoren über die .NET-Schnittstelle
`System.Diagnostics.PerformanceCounterCategory` mit den **englischen** Namen. Das funktioniert unabhängig von
der Sprache der Oberfläche; auf dem geprüften deutschen VDA lieferte dieser Weg für jede Kategorie Werte. Die
Werte des schnellen Takts entstehen aus zwei Lesungen im Abstand eines Takts (`CounterSample.Calculate`); die
Zähler der Kategorie `ICA Session` sind Momentanwerte und werden einmal je Schnappschuss gelesen.

| Signal | Quelle (Kategorie / Zähler, Klasse) | Ergebnis des Prüfskripts |
|---|---|---|
| CPU-Auslastung | `Processor Information` / `% Processor Time`, Instanz `_Total` | vorhanden |
| Prozessor-Warteschlange | `System` / `Processor Queue Length` | vorhanden |
| Entzogene CPU-Zeit | `VM Processor` / `CPU stolen time` (VMware Tools), einzige Instanz `_Total` | vorhanden; Zählertyp `Timer100Ns`, der Rohwert wächst aber wie Millisekunden. Der Collector rechnet ihn als Millisekunden entzogener Zeit je Sekunde Laufzeit in Prozent um und teilt `_Total` durch die Zahl der logischen Prozessoren (Prozent je vCPU). Einheit und Bezug sind nicht bestätigt (siehe Offene Punkte) |
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
| Ereignisprotokolle | die Protokolle, Quellen und Kennungen aus `events.json` (Tabelle unten) über `EventLogReader` (wie das Prüfskript): je Protokollname eine strukturierte XML-Abfrage, darin je Quelle eine Auswahl mit ihren Kennungen (höchstens 23 je Auswahl) oder ihren Ebenen und den Zeitgrenzen als UTC-Zeitpunkte (`Get-WinEvent -FilterHashtable` würde die Zeitgrenzen als Ortszeit lesen); die Felder aus `ToXml()`, der Meldungstext aus `FormatDescription()`, der Benutzer aus den Datenfeldern, sonst aus dem Konto im Systemteil des Ereignisses | nach Prüfergebnis, auf einem echten Server noch nicht gelaufen. Ein vorhandenes, aber abgeschaltetes Protokoll meldet der Collector wie ein fehlendes als „Protokoll nicht vorhanden oder abgeschaltet"; er schaltet es nicht ein. Scheitert die Abfrage eines vorhandenen Protokolls oder schlagen drei Datensätze in Folge fehl, endet das Lesen dieses Protokolls; das steht einmal mit der Fehlerklasse in `meta.json` (`SourceErrors`) und auf der Konsole. Ein einzelner nicht lesbarer Datensatz wird übersprungen, ein nicht formatierbarer Meldungstext bleibt leer; beides zählt `EventReadCounts` |
| Rückblick | dieselben Abfragen über `-EventLookbackDays` Tage, ohne Sitzungsprotokoll, die neuesten höchstens 2000 Ereignisse je Protokoll; ein Zeitbudget von 60 s, geprüft vor jedem Protokoll und zwischen seinen Datensätzen. Überschreiten kann es nur, was zwischen zwei Prüfungen liegt: das Öffnen einer Abfrage und das Lesen und Formatieren eines Datensatzes. Ein Protokoll, das die Obergrenze erreicht, nicht lesbar war oder wegen des Budgets nicht zu Ende gelesen wurde, gilt im Bericht als unvollständig | nach Prüfergebnis, auf einem echten Server noch nicht gelaufen |
| Druckertreiber | `root/StandardCimv2` / `MSFT_PrinterDriver` (`Name`, `Manufacturer`, `MajorVersion`, `DriverVersion`, Treiber-, Konfigurations-, Daten- und abhängige Dateien); Isolierung aus `PrintDriverIsolationGroups`, sonst aus den Richtlinien `PrintDriverIsolationExecutionPolicy` und `PrintDriverIsolationOverrideCompat` und dem Attribut 0x4 (`PrinterDriverAttributes`) im Registrierungsschlüssel des Treibers | nach Prüfergebnis, auf einem echten Server noch nicht gelaufen. Die Isolierung ist die wirksame, wie Windows sie ableitet (dieselbe Regel wie im Prüfskript); ohne gesetzten Wert `PrintDriverIsolationGroups` entscheiden Richtlinie und Attribut. Lässt sich das Attribut nicht lesen und entscheiden die Richtlinien nicht, bleibt `Isolation` leer |
| Druckwarteschlangen | `Print Queue` / `Jobs`, `Job Errors`, `Not Ready Errors` (Momentanwerte), alle Instanzen außer `_Total` | nach Prüfergebnis, auf einem echten Server noch nicht gelaufen |
| Verbindungsproben | TCP-Verbindungsaufbau zu den Gegenstellen aus `endpoints.json`, Zeitlimit 2 s | nicht geprüft (beim Prüflauf keine Datei mit Gegenstellen) |

**Ereignisquellen.** Die Liste der Protokolle, Quellen und Kennungen steht in `src/events.json`: je Eintrag
Protokoll, Quelle, Kennungen, Gruppe, Art und welche Datenfelder des Ereignisses zu lesen sind. Sie lässt sich
ergänzen, ohne Code zu ändern. Die Windows-Datenquelle, die Auswertung und die Simulation lesen sie. Ein Datenfeld
ist ein Name, eine Position (`#0` für das erste Datenfeld) oder `binary:utf16`, oder eine Liste davon: der erste
Eintrag mit einem Wert gilt. So liest `Application Error` 1000 die benannten Felder, wo Windows sie benennt, und
sonst die klassischen Positionen. Statt Kennungen kann ein Eintrag `"ids": "*"` mit `"levels"` (`critical`,
`error`, `warning`, `information`) nennen: dann gilt jedes Ereignis der Quelle auf diesen Ebenen; ein Eintrag mit
Kennungen geht vor. Der Dienstname von `Service Control Manager` kommt aus dem Binärteil des Ereignisses
(`binary:utf16`), ist also der Kurzname des Dienstes in jeder Sprache; `importantServices` nennt deshalb Kurznamen.

| Gruppe | Inhalt | Windows-Protokoll |
|---|---|---|
| Anwendungen (`app`) | Absturz, Hänger, .NET-Laufzeitfehler, Fehlerberichte | Anwendung |
| Dienste (`service`) | unerwartet beendete oder neu gestartete Dienste | System |
| Datenträger (`storage`) | Datenträger-, Dateisystem- und Controllerfehler | System |
| Speicher (`memory`) | Warnung vor knappem virtuellem Speicher | System, Ressourcenerschöpfung |
| Dateiserver (`fileserver`) | Verbindungsabbrüche und Zeitüberschreitungen | SMB-Client |
| Profile (`profile`) | Fehler beim Laden und Entladen von Profilen, Meldungen der Citrix-Profilverwaltung | Anwendung, Benutzerprofildienst |
| Drucken (`print`) | Fehler des Druckdienstes, Treiberfehler, fehlgeschlagene Aufträge, Citrix-Druckverwaltung | Druckdienst (Verwaltung), Anwendung, System |
| Sitzungen (`session`) | Anmelden, Abmelden, Trennen, Wiederverbinden | Terminaldienste (Sitzungsverwaltung) |
| Schutzsoftware (`security`) | Defender und AppLocker | Defender, AppLocker |

Die Profilverwaltung von Citrix (`Citrix Profile Management`) liest der Collector nach Ebene, Fehler und
Warnungen (siehe Offene Punkte). Für die Citrix-Druckverwaltung steht keine Quelle in `events.json`. Vom
Druckdienst liest er die fehlgeschlagene Treiberinstallation (215) als Druckfehler und die fehlgeschlagenen
Treiberimporte (600, 601) als eigene Art ohne Vorfall, beide mit dem Treibernamen; Wechsel des Standarddruckers und
Meldungen ohne bekannte Felder bleiben draußen.

Auf dem geprüften VDA fehlte keine der Quellen. Fehlt eine Kategorie, Klasse oder ein Protokoll auf einem
anderen Worker, meldet der Collector das Signal beim Start als nicht verfügbar (`meta.json`, `Sources`); es
erscheint im Bericht als „nicht gemessen". Die CIM-Klassen `Win32_PerfRawData_*` nutzt der Collector nicht; für
`VM Processor` gab es auf dem VDA keine.

**Schneller Takt 2 s und Eingabeverzögerung:** `Max Input Delay` ist ein fortlaufender Zähler (`AverageCount64`).
Im Prüfergebnis wuchs sein Basiswert bei Abfragen im Abstand von 1 s und von 2 s jeweils um genau eins, und jeder
berechnete Wert war der Zuwachs des Rohwerts. Daraus folgt – als Schluss aus dieser Rechnung, nicht gemessen –,
dass eine Abfrage alle 2 s die höchste Verzögerung seit der vorigen Abfrage liefert, also das Maximum beider
Sekunden; ein 2-s-Abstand mit zwei verschiedenen Spitzen kam im Prüfergebnis nicht vor. Der Standard von
`-FastIntervalSeconds` bleibt deshalb 2 s; die erste echte Messung soll das bestätigen (siehe Offene Punkte). Liest ein zweites Programm denselben Zähler gleichzeitig (etwa die Leistungsüberwachung),
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
Ein Bericht enthält dieselben Namen wie die Aufzeichnung. Für die Weitergabe ersetzt `-Mask` die Namen der
gewählten Stufe durch Ersatznamen; was stehen bleibt und wo die Grenzen liegen, steht unter
[Bericht maskiert weitergeben](#bericht-maskiert-weitergeben). Die Aufzeichnung selbst behält die echten Namen.
Die Zuordnungsdatei aus `-MaskMapFile` enthält ebenfalls die echten Namen und bleibt beim Ersteller;
`.gitignore` schließt `*.maskmap.json` aus.
Im Ergebnis des Prüfskripts sind Benutzer-, Domänen-, Client- und Servernamen sowie Konten-SIDs maskiert.
Namen in freiem Text kann das Skript nicht sicher erkennen; die Datei wird deshalb nach einer Durchsicht
([docs/vda-probe/README.md](docs/vda-probe/README.md#vor-der-weitergabe-durchsehen)) außerhalb des Repositorys
übergeben und nicht eingecheckt (`.gitignore` schließt `vda-probe_*.json` aus).

## Offene Punkte

- **Windows-Datenquelle auf einem echten Server:** noch nicht gelaufen. Erster Schritt ist eine Kurzmessung
  (`Start-WorkerPerfCapture.ps1 -DurationMinutes 10` in einer administrativen Konsole auf einem Worker mit
  angemeldeten Benutzern, danach `New-WorkerPerfReport.ps1`). Zu prüfen: keine Warnungen zu Quellen, die laut
  Prüfskript vorhanden sind; Werte in jeder Spalte von `ticks.csv`; Profilcontainer in `volumes.csv` mit
  Sitzung; ICA-Werte in `citrix.csv` mit Sitzung; die Messdauer je Takt (`CollectMs`) deutlich unter 2 s.
- **Ereignisse, Rückblick und Drucken unter Windows:** geschrieben, auf einem echten Server noch nicht gelaufen.
  Bei der ersten Kurzmessung mit Rückblick prüfen: keine Warnung zu einem Protokoll, das laut Prüfskript vorhanden
  ist; wie groß `events_before.csv` und `events.csv` werden; wie lange der Rückblick vor dem ersten Takt dauert
  (das Budget von 60 s plus das Lesen eines Datensatzes, das beim Erreichen des Budgets läuft; danach gilt der Rest
  als unvollständig).
- **Abfrage der Ereignisprotokolle von Hand prüfen:** Ob eine Auswahl mit 23 Kennungen (und damit bis zu 31 der
  laut Dokumentation erlaubten 32 Ausdrücke) auf einem Server angenommen wird, ist nicht geprüft. Erster Schritt:
  eine Abfrage von Hand, `Get-WinEvent -FilterXml ([xml](New-WorkerPerfEventQueryXml …))` für Anwendung und System mit
  einem Zeitfenster um ein bekanntes Ereignis; sie muss dieses Ereignis liefern, ohne die Meldung, die Abfrage sei
  ungültig. Danach prüfen, dass die Ereignisse der Stunde vor dem Start in `events_before.csv` stehen.
- **Zeiger der Ereignisse:** Der Collector liest Ereignisse bis zur Zeit des Abrufs; ein Ereignis, das das
  Ereignisprotokoll erst nach dem Abruf festschreibt, aber mit einer früheren Zeit stempelt, fehlt in `events.csv`.
- **Kennungen der Citrix-Profilverwaltung:** Der Collector liest sie nach Ebene (Fehler und Warnungen), weil die
  Bedeutung der einzelnen Kennungen noch nicht bekannt ist. Die erste echte Aufzeichnung zeigt, welche davon
  Routinemeldungen sind und in `events.json` ausgenommen werden sollten (ein Eintrag mit diesen Kennungen und der
  Art `info` geht dem Eintrag nach Ebene vor). Diese Ereignisse teilen sich die Obergrenzen des Anwendungsprotokolls
  (200 je Abruf, 2000 im Rückblick) mit Abstürzen, Hängern und Profilfehlern: sind ihre Warnungen häufig, verdrängen
  sie im Rückblick ältere Ereignisse der anderen Quellen, und das Anwendungsprotokoll gilt dann als unvollständig.
- **Fehlgeschlagene Treiberimporte (Druckdienst 600 und 601):** Sie können bei jeder Anmeldung entstehen, wenn der
  Treiber eines Clientdruckers nicht importiert werden kann, und sind dann ein Dauerzustand, kein Vorfall. Der
  Collector zeichnet sie auf (Art `driver-import`, mit dem Treibernamen); der Bericht nennt sie in der
  Ereignisliste als „Treiberimport fehlgeschlagen", bildet aus ihnen aber keinen Druckvorfall und nennt ihretwegen
  keinen Treiber „beteiligt". Wie häufig sie sind, soll eine spätere Auswertung des Zustands des Workers bewerten.
- **Benannte Startzeit bei `Application Error` 1000:** Der Name `ProcessCreationTime`, den `events.json` vor der
  Position `#9` nennt, ist nicht geprüft; ein Server mit unbenannten Feldern liest die Position.
- **Benutzer aus dem Konto des Ereignisses:** Ereignisse ohne Benutzer in den Datenfeldern (Absturz, Profilfehler)
  bekommen das Konto aus dem Systemteil des Ereignisses. Die Konten SYSTEM, LOCAL SERVICE und NETWORK SERVICE
  erkennt der Collector an ihrer SID; andere SIDs übersetzt Windows, je SID einmal und höchstens 1 s lang, nach
  einer Zeitüberschreitung 10 Minuten lang nicht. Ob die Ereignisse diese SID tragen, zeigt die erste Aufzeichnung.
- **Maskierung unter Windows PowerShell 5.1:** `-Mask` und `-MaskMapFile` sind nur unter PowerShell 7 mit der
  Simulation getestet. Bei der ersten echten Auswertung einmal mit `-Mask Alles` auswerten, den Bericht durchsehen
  und prüfen, dass kein echter Benutzer-, Client- oder Servername mehr darin steht.
- **Kosten des schnellen Takts unter Windows PowerShell 5.1:** nicht gemessen. Gemessen ist nur die Prozessabfrage
  des Prüfskripts (0,4 s für 800 Prozesse). Die Kurzmessung zeigt die Dauer je Takt und je Schnappschuss im Block
  „Messqualität" (siehe [Auswirkung der Messung auf den Worker](#auswirkung-der-messung-auf-den-worker)).
- **Einheit der entzogenen CPU-Zeit:** Der Collector liest den Rohwert von `VM Processor` / `CPU stolen time`
  als Millisekunden der ganzen VM und teilt durch die Zahl der vCPUs; der Zählertyp `Timer100Ns` würde 100 ns
  bedeuten, was Werte im Bereich von Millionstel Prozent ergäbe. Bestätigen oder widerlegen lässt sich das bei
  der ersten Messung: dieselbe Stunde im vCenter ansehen (Leistungsdiagramm der VM, „Bereitschaft" in
  Millisekunden je Intervall oder in Prozent, je vCPU). Stimmt `StealPct` in `ticks.csv` in der Größenordnung mit
  der Bereitschaft je vCPU überein, ist die Annahme richtig; liegt es um den Faktor der vCPU-Zahl darüber oder
  darunter, ist der Bezug (ganze VM oder je vCPU) falsch; weicht es um Größenordnungen ab, die Einheit.
- **Eingabeverzögerung bei 2 s:** dass eine Abfrage alle 2 s das Maximum beider Sekunden liefert, ist aus dem
  Basiswert des Zählers geschlossen, nicht gemessen. Bei der ersten Messung in einer Sitzung tippen und in
  `inputdelay.csv` prüfen, dass kurze Spitzen erscheinen; laufen gleichzeitig die Leistungsüberwachung oder ein
  anderes Werkzeug mit diesem Zähler, sieht der Collector Mittelwerte zweier Spitzen.
- **Zuordnung der ICA-Werte zur Sitzung:** über den Namen der WinStation (`ICA-CGP 2` gegen `ICA-CGP#2`),
  sonst über den Benutzernamen, wenn er nur eine Sitzung hat. Die Schreibweise der WinStation-Namen hat das
  Prüfskript nicht erfasst.
- **Rollen:** In `roles.json` sind für Arctic Wolf Aurora der Dienst und Prozess `CylanceSvc` eingetragen, für
  Nexus KIS die Anwendung und der Prozess ihres Dienstes (unter `processes`, weil der Kurzname des Dienstes nicht
  bekannt ist). Der Oracle-Client hat keinen eigenen Prozess; er läuft in der Anwendung, die ihn nutzt.
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
