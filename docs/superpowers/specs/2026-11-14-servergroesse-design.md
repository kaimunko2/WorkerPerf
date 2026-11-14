# Größe des Servers – Entwurf

Stand 14.11.2026. Baustein nach dem Zustandsbild. Phase 1: mehrere Aufzeichnungen **desselben** Servers. Phase 2
(eigener Baustein, nicht Teil dieses Entwurfs): Aufzeichnungen **verschiedener** Server derselben Umgebung
nebeneinander. Dieser Entwurf baut Phase 1 so, dass Phase 2 ohne Umbau des Datenmodells möglich ist.

## 1. Ziel und Warum

Meldet ein Benutzer, der Server sei langsam, und zeigt der Bericht einen CPU- oder Arbeitsspeicher-Engpass, muss der
Administrator entscheiden: Ist das ein Fehler oder Sonderfall einer Anwendung, ein einmaliges Ereignis, ein Problem
des VMware-Hosts, zu wenig Leistung je Kern, oder ist der Server schlicht zu klein? Die Antwort bestimmt, ob er
Ressourcen ändert und welche: mehr Kerne helfen nicht, wenn eine Anwendung nur einen Kern nutzt; mehr vCPUs schaden,
wenn der Host die Rechenzeit nicht liefert; mehr Arbeitsspeicher hilft nicht gegen ein Speicherleck.

Der Baustein liefert:

1. **Ursache je Engpass** im normalen Bericht: jeder CPU- und Arbeitsspeicher-Vorfall wird einer Ursachenklasse
   zugeordnet (Abschnitt 4), mit Begründung aus den Messwerten.
2. **Größenbericht** aus mehreren Aufzeichnungen desselben Servers (z. B. fünf Arbeitstage): wiederkehrend oder
   einmalig, typische Spitzenlast, und eine Empfehlung als **Richtung mit gekennzeichneter Hochrechnung**
   (Entscheidung des Kunden: Variante 2), z. B. „Bei der gemessenen Spitzenlast käme der Server mit 10 statt 8 vCPU
   unter 75 % – Hochrechnung unter der Annahme, dass die Last gleichmäßig mitwächst."

## 2. Ziele, Nicht-Ziele, Anti-Ziele

**Ziele**
- Ursachenklasse je CPU-/RAM-Vorfall mit nachvollziehbarer Begründung (Messwerte, Schwellen, Quelle).
- Unterscheidung „mehr Kerne" gegen „schnellere Kerne" (Leistung je Kern) anhand von Messwerten.
- Ein Berichtsvorgang über mehrere Aufzeichnungen; Empfehlung mit Hochrechnung, Annahmen und Grenzen sichtbar.
- Jede Regel mit Quelle (Hersteller, Praxisquelle oder ausdrücklich Faustregel des Katalogs), wie im Katalog des
  geführten Berichts und des Zustandsbilds.
- Datenmodell, das jede Aufzeichnung mit ihrem Server führt (Grundlage für Phase 2).

**Nicht-Ziele**
- Feste Zielgrößen („10 vCPU, 48 GB") als Vorgabe (vom Kunden ausgeschlossen, Variante 3).
- Aufzeichnungen verschiedener Server in einem Bericht (Phase 2).
- Messung auf dem VMware-Host (vCenter-Zähler); der Bericht nennt, wo dort nachzusehen ist.
- Planung künftiger Benutzerzahlen über die gemessene Last hinaus (kein Wachstumsmodell).

**Anti-Ziele** (wäre ein Fehlschlag, auch wenn es technisch läuft)
- Eine Empfehlung „mehr vCPU", obwohl der Host Rechenzeit entzieht oder eine Anwendung nur einen Kern nutzt.
- Eine Hochrechnung ohne Kennzeichnung oder ohne Annahmen.
- Eine Empfehlung aus einer einzigen kurzen Aufzeichnung, die so tut, als sei sie belastbar.
- Ein zweiter, abweichender Satz von Schwellen neben `thresholds.json` und den Katalogen.

## 3. Daten

### 3.1 Neue Messwerte in der Aufzeichnung

Aus der Leistungsindikator-Gruppe „Processor Information", die der Collector heute schon für die Gesamtauslastung
liest (`cpu.host`), kommen im schnellen Takt dazu:

| Signal | Inhalt | Zweck |
|---|---|---|
| `cpu.coreMax` | Auslastung des am stärksten belasteten Kerns (%) | ein Kern voll, die anderen frei |
| `cpu.coreBusy` | Zahl der Kerne über der Kern-Schwelle (Katalog, Vorschlag 90 %) | wie viele Kerne gleichzeitig voll sind |
| `cpu.perf` | Leistungsanteil des Prozessors (`% Processor Performance`, _Total) | laufen die Kerne mit voller Leistung |

Die Werte je Kern werden nicht einzeln gespeichert (Datenmenge), nur diese drei Verdichtungen je Takt. Ob und wie
`% Processor Performance` in einer VMware-VM aussagekräftig ist, klärt die Recherche (`research-sizing.md`) und der
erste echte Lauf; ist er dort nicht verlässlich, entfällt `cpu.perf` als Grundlage einer Ursache und bleibt Anzeige.

Die neuen Signale gehören zur Grundmessung (keine neue Kategorie für `-Skip`). Eine ältere Aufzeichnung ohne sie wird
weiter gelesen; die Einordnung sagt dann, welche Unterscheidung ohne diese Werte nicht möglich ist.

### 3.2 Was schon da ist und genutzt wird

Gesamt-CPU, Prozessor-Warteschlange je CPU, entzogene CPU-Zeit je vCPU (`cpu.steal`), Arbeitsspeicher (belegt,
zugesichert, Seiteneinlagerungen), Eingabeverzögerung, Prozess-Schnappschüsse mit CPU je Prozess, Sitzungen, Anzahl
logischer Prozessoren und RAM (Kopf), Vorfälle mit Hauptverursacher, Ereignisse (Abstürze, Rückblick), Zustandsbild
(vCPU-Zahl, Energiesparplan, VMware-Werte).

### 3.3 Der Server einer Aufzeichnung

Jede Aufzeichnung führt in `meta.json` den Computernamen (heute schon) und eine stabile Kennung des Servers für den
Vergleich mehrerer Aufzeichnungen. Bei MCS-Servern mit nicht persistenten Abbildern kann der Name bei Neubereitstellung
gleich bleiben, während die Maschine eine andere ist; maßgeblich für „derselbe Server" ist der Computername (Entscheidung
des Entwurfs: Name genügt für Phase 1; ein abweichender Name führt zur klaren Meldung, Abschnitt 5.1).

## 4. Ursache je Engpass (normaler Bericht)

### 4.1 Klassen

| Klasse | Erkennbar an (Beispiele; Schwellen im Katalog) | Was hilft (Richtung) |
|---|---|---|
| Host | entzogene CPU-Zeit je vCPU über der Schwelle während des Vorfalls | VMware-Host prüfen lassen; **keine** zusätzlichen vCPUs |
| Leistung je Kern | Hauptverursacher läuft dauerhaft bei etwa einem vollen Kern (≈ 100/N % der Server-CPU), `cpu.coreMax` hoch, Gesamtauslastung moderat | schnellere Kerne, Energieverwaltung (Gast, Host, BIOS), Hersteller der Anwendung; mehr Kerne helfen nicht |
| Gedrosselte Kerne | `cpu.perf` unter der Schwelle bei hoher Last | Energiesparplan/Host-Energierichtlinie prüfen |
| Anwendung | ein Prozess oder eine Anwendung trägt den Großteil der Last, nicht das Muster „Leistung je Kern" | Anwendung, Aufgabe oder Benutzer klären; keine Größenänderung |
| Einmalig | Engpass durch einen geplanten oder seltenen Vorgang (Virenscan, Update, geplante Aufgabe) | Zeitplan; keine Größenänderung |
| Kapazität | Last breit über viele Sitzungen, Warteschlange je CPU hoch, kein Host-Entzug | mehr vCPU oder mehr Server (Hochrechnung im Größenbericht) |
| Arbeitsspeicher: Kapazität | zugesichert nahe/über RAM, Seiteneinlagerungen, Last breit | mehr RAM oder weniger Sitzungen |
| Arbeitsspeicher: Anwendung | ein Prozess wächst stetig oder trägt den Großteil | Anwendung klären (Speicherleck?) |
| Nicht entscheidbar | Werte fehlen oder widersprechen sich | sagt, welche Messung fehlt |

Ein Vorfall kann mehrere Klassen tragen (z. B. Host **und** Kapazität); die Rangfolge der Darstellung folgt der
Tabelle (Host zuerst, weil er jede andere Empfehlung entwertet).

### 4.2 Regeln

Die Regeln stehen als Daten in einem Katalog `src/sizing.de.json` (gleiche Grundsätze wie `guidance.de.json` und
`health.de.json`: jede Regel mit Quelle und Art – Hersteller, Praxisquelle oder Faustregel des Katalogs; Schwellen
als benannte Werte; geprüft beim Laden). Die Schwellen der Ursachen (z. B. „Anteil des Hauptverursachers",
„Kern-Schwelle", „Leistungsanteil") sind Vorschläge des Katalogs, wo keine Quelle eine Zahl nennt.

Die Einordnung nutzt die Daten, die der Bericht ohnehin bildet (Vorfälle mit Beteiligten, Signale im Fenster des
Vorfalls), und die neuen Signale aus 3.1.

### 4.3 Darstellung im normalen Bericht

- Vorfallsansicht: eine Zeile „Einordnung: Leistung je Kern" mit der Begründung in einem Satz und den Zahlen, die sie
  tragen; die Anleitung des Vorfalls bleibt, kann aber ergänzende Schritte der Klasse bekommen (z. B. Host prüfen).
- Kopiertext: die Einordnung als eigene Zeile.
- Expertenansicht: neue Kacheln „stärkster Kern" und „Leistungsanteil"; die Einordnung je Eintrag der Vorfallsspalte.

## 5. Größenbericht

### 5.1 Bedienung

`New-WorkerPerfSizingReport.ps1 -Path <Aufzeichnung1>, <Aufzeichnung2>, … [-OutFile] [-Mask Alles|Personen]
[-SizingFile] [-ThresholdFile] [-GuidanceFile] [-AppsFile] [-RoleFile]`

- Mindestens eine Aufzeichnung; sinnvoll sind mehrere Arbeitstage. Weniger als die im Katalog genannte Mindestzahl
  (Vorschlag: drei Aufzeichnungen oder zwölf Stunden) → der Bericht entsteht, aber jede Empfehlung trägt den Hinweis
  „wenig Messzeit".
- Alle Aufzeichnungen müssen denselben Server haben (Computername); sonst Abbruch mit Meldung, welche Aufzeichnung
  abweicht, und dem Hinweis, dass der Vergleich verschiedener Server ein späterer Baustein ist.
- Ein Schnelllauf (`-HealthOnly`) zählt nicht als Aufzeichnung für die Last; sein Zustandsbild darf genutzt werden.
- Jede Aufzeichnung wird mit derselben Auswertung gelesen wie im normalen Bericht (Lader, Befunde, Vorfälle,
  Einordnung). Der Größenbericht ersetzt den normalen Bericht nicht; er nennt je Aufzeichnung, wie man ihren Bericht
  erzeugt (Pfad und Befehl).

### 5.2 Inhalt

1. **Kopf:** Server, Zeitraum aller Aufzeichnungen, Zahl und Gesamtdauer, vCPU und RAM (je Aufzeichnung; wechselt die
   Größe zwischen den Aufzeichnungen, steht das als Hinweis und die Hochrechnung rechnet je Größe).
2. **Ergebnis in einem Satz** (wie das Lagebild), z. B. „Wiederkehrender CPU-Engpass aus Kapazität an 4 von 5 Tagen;
   Spitzenlast 92 % bei 31 Sitzungen."
3. **Empfehlungen** je Ressource (CPU, Arbeitsspeicher; dazu Host und Leistung je Kern, wo erkannt): Richtung,
   Begründung, Hochrechnung mit Kennzeichnung, Annahmen, Quellen, Belastbarkeit (Messzeit, Arbeitszeit abgedeckt,
   Zahl der Aufzeichnungen).
4. **Verlauf über die Aufzeichnungen:** je Aufzeichnung Spitze und P95 von CPU, Warteschlange, zugesichertem Speicher,
   höchste Sitzungszahl; Engpässe mit Klasse; wiederkehrend = dieselbe Klasse in mindestens der Hälfte der
   Aufzeichnungen (Vorschlag des Katalogs).
5. **Liste der Aufzeichnungen** mit Ordner, Beginn, Dauer, Ende-Grund.
6. **Quellen** der genutzten Regeln.
7. **Kopiertext** der Empfehlungen, mit und ohne Namen (wie im geführten Bericht).

### 5.3 Hochrechnung

- **CPU:** Bedarf in Kern-Äquivalenten = maßgebliche Last × vCPU (maßgebliche Last: P95 der CPU über die
  Arbeitszeit aller Aufzeichnungen, Vorschlag; die Spitze wird daneben genannt). Benötigte vCPU = Bedarf ÷ Zielauslastung
  (Zielauslastung = Schwelle „auffällig" von `cpu.host` in `thresholds.json`, heute 75 %). Ausgegeben als „käme mit
  X vCPU unter 75 %". **Nicht** ausgegeben, wenn Host oder Leistung je Kern die Ursache sind; dann steht dort, warum
  mehr vCPU nicht hilft.
- **Grenze je VM:** Überschreitet die Hochrechnung die Größe, die Hersteller oder Praxisquellen je VM empfehlen
  (z. B. NUMA-Grenze, vCPU je VM aus den Praxisquellen), empfiehlt der Bericht stattdessen mehr Server bzw. weniger
  Sitzungen je Server: „bei gleicher Größe trägt der Server etwa N Sitzungen unter 75 %".
- **Arbeitsspeicher:** Bedarf = höchster zugesicherter Speicher der Arbeitszeit + Reserve (Katalog); verglichen mit
  dem RAM; Seiteneinlagerungen als Beleg.
- **Kennzeichnung:** jede Zahl der Hochrechnung steht mit „Hochrechnung" und ihren Annahmen (lineare Skalierung,
  gleiche Last je Sitzung, Hyper-Threading nicht berücksichtigt, Host liefert die Rechenzeit).

### 5.4 Darstellung

Eine eigene, selbstständige HTML-Seite im Stil der geführten Ansicht (hell, gleiche Statusmarken, gleiche
Wortregeln: der gemessene Rechner heißt „Server"), ohne externe Anfragen, mit Druckansicht. Diagramme: Verlauf je
Aufzeichnung (Balken je Tag für Spitze und P95) und Sitzungen gegen CPU (Punktwolke mit der Hochrechnungsgeraden).
Maskierung wie im normalen Bericht.

### 5.5 Vorbereitung auf Phase 2

- Die Daten des Größenberichts sind eine Liste von Aufzeichnungen, jede mit ihrem Server. Die Auswertung „über die
  Aufzeichnungen" fasst nach einer **Achse** zusammen; Phase 1 nutzt die Achse „Zeit" (ein Server). Phase 2 fügt die
  Achse „Server" hinzu, ohne das Datenformat zu ändern.
- Die Prüfung „derselbe Server" ist eine einzelne Stelle, die Phase 2 ersetzt.

## 6. Verhältnis zu anderen Teilen

- Nutzt Lader, Befunde, Vorfälle und Kataloge unverändert; ergänzt den normalen Bericht um die Einordnung (4.3).
- Nutzt das Zustandsbild, wenn vorhanden (vCPU-Zahl, Energiesparplan, VMware-Werte als Belege), braucht es nicht.
- Neue Signale (3.1) erweitern das Aufzeichnungsformat abwärtskompatibel.

## 7. Tests

- Simulation: neue Szenen für jede Klasse (Host-Entzug, eine Anwendung auf einem Kern, gedrosselte Kerne,
  Kapazitätsengpass über viele Sitzungen, einmaliger Scan, Speicherleck einer Anwendung, Speicherkapazität) und ein
  Mehrtageslauf (mehrere Aufzeichnungen mit wiederkehrendem und einmaligem Engpass).
- Einordnung: je Klasse ein Test mit den Grenzfällen der Schwellen; ältere Aufzeichnung ohne neue Signale.
- Größenbericht: Hochrechnung von Hand nachgerechnet; keine vCPU-Empfehlung bei Host oder Leistung je Kern; Hinweis
  „wenig Messzeit"; Abbruch bei verschiedenen Servern; Maskierung (Markertest wie bisher).
- Seite: Browserprüfungen wie beim geführten Bericht (Lesbarkeit, Statusmarken, schmale Breite, Druck).

## 8. Grenzen

- Die Hochrechnung ist linear; reale Last skaliert nicht immer linear (Hyper-Threading, Speicherbandbreite,
  Anwendungsgrenzen).
- Der Host ist nur über die entzogene CPU-Zeit sichtbar; Co-Stop, Speicher-Ballooning und Host-Auslastung nicht.
- Eine Aufzeichnung außerhalb der Arbeitszeit sagt wenig über die Spitzenlast.
- Die Erkennung „Leistung je Kern" stützt sich auf Prozess-Schnappschüsse (alle 6–15 s), nicht auf Threads.

## 9. Offene Punkte für den ersten echten Lauf

- Liefert `% Processor Performance` in der VMware-VM sinnvolle Werte?
- Laufzeit des Lesens je Kern bei vielen vCPUs (Takt 2 s).
