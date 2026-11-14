# Größe des Servers – Entwurf

Stand 14.11.2026. Baustein nach dem Zustandsbild.

- **Phase 1** (dieser Entwurf): mehrere Aufzeichnungen **desselben** Servers.
- **Phase 2** (eigener Baustein, nicht Teil dieses Entwurfs): Aufzeichnungen **verschiedener** Server derselben Umgebung
  nebeneinander, z. B. ein gut und ein schlecht laufender Server.

Phase 1 wird so gebaut, dass Phase 2 ohne Umbau des Datenmodells möglich ist.

Belege: `.superpowers/sdd/zustandsbild-prep/research-sizing.md`. Die Einträge SZ-01 bis SZ-47 werden hier mit ihrer Kennung
genannt; dazu kommen die dort zitierten älteren Einträge (VM-08, VM-10, ST-02, MS-RDSH …).

## 1. Ziel und Warum

Ein Benutzer meldet, der Server sei langsam, und der Bericht zeigt einen CPU- oder Arbeitsspeicher-Engpass. Dann muss
der Administrator entscheiden, woran es liegt:

- Fehler oder Sonderfall einer Anwendung,
- einmaliges Ereignis,
- Problem des VMware-Hosts,
- zu wenig Leistung je Kern,
- oder der Server ist schlicht zu klein.

Die Antwort bestimmt, ob er Ressourcen ändert und welche:

- Mehr Kerne helfen nicht, wenn eine Anwendung nur einen Kern nutzt (SZ-13…16).
- Mehr vCPUs helfen nicht, wenn der Host die Rechenzeit nicht liefert. VMware nennt dafür nie „mehr vCPU“, eher weniger
  (SZ-21, SZ-20).
- Mehr Arbeitsspeicher hilft nicht gegen ein Speicherleck.

Der Baustein liefert:

1. **Ursache je Engpass** im normalen Bericht: Jeder CPU- und Arbeitsspeicher-Vorfall bekommt eine Ursachenklasse
   (Abschnitt 5), begründet mit Messwerten.
2. **Größenbericht** aus mehreren Aufzeichnungen desselben Servers, z. B. fünf Arbeitstage. Er zeigt:
   - ob ein Engpass wiederkehrt oder einmalig war,
   - die typische Spitzenlast,
   - eine Empfehlung als **Richtung mit gekennzeichneter Hochrechnung** (Entscheidung des Kunden: Variante 2), z. B.
     „Bei der gemessenen Last käme der Server mit etwa 10 bis 12 statt 8 vCPU unter 75 %. Das ist eine Schätzung, nicht
     gemessen; vor einem Umbau mit einem Pilot bestätigen.“

## 2. Ziele, Nicht-Ziele, Anti-Ziele

**Ziele**

- Ursachenklasse je CPU- und Arbeitsspeicher-Vorfall, nachvollziehbar begründet mit Messwerten, Schwellen und Quelle.
- Unterscheidung „mehr Kerne“ gegen „schnellere Kerne“ (Leistung je Kern) anhand von Messwerten.
- Ein Berichtsvorgang über mehrere Aufzeichnungen. Die Empfehlung zeigt ihre Hochrechnung, die Annahmen und die Grenzen.
- Jede Regel mit Quelle und Art: Herstellerangabe, Praxisquelle oder ausdrücklich Faustregel des Katalogs. Das gilt wie in
  den Katalogen des geführten Berichts und des Zustandsbilds.
- Ein Datenmodell, das jede Aufzeichnung mit ihrem Server führt. Das ist die Grundlage für Phase 2.

**Nicht-Ziele**

- Feste Zielgrößen wie „10 vCPU, 48 GB“ als Vorgabe. Der Kunde hat diese Form ausgeschlossen (Variante 3).
- Aufzeichnungen verschiedener Server in einem Bericht. Das ist Phase 2.
- Messung auf dem VMware-Host (vCenter-Zähler wie Ready, Co-Stop, Host-Auslastung). Der Bericht nennt, wo dort nachzusehen
  ist und welche Werte auffällig wären (SZ-20, SZ-26).
- Planung künftiger Benutzerzahlen über die gemessene Last hinaus. Es gibt kein Wachstumsmodell.

**Anti-Ziele** (das wäre ein Fehlschlag, auch wenn es technisch läuft)

- Eine Empfehlung „mehr vCPU“, obwohl der Host Rechenzeit entzieht oder eine Anwendung nur einen Kern nutzt.
- Eine Hochrechnung ohne Kennzeichnung oder ohne Annahmen.
- Eine lineare Hochrechnung. Doppelt so viele Kerne tragen nicht doppelt so viele Benutzer (SZ-42).
- Eine Empfehlung aus einer einzigen kurzen Aufzeichnung, die so tut, als sei sie belastbar.
- Ein zweiter, abweichender Satz von Schwellen neben `thresholds.json` und den Katalogen.

## 3. Ansätze

**Wo die Auswertung über mehrere Aufzeichnungen sitzt**

| | Ansatz | Abwägung |
|---|---|---|
| A | Der normale Bericht nimmt mehrere Aufzeichnungen an | Ein einziges Skript, aber die heutige Seite (eine Zeitachse, Vorfälle, Bereiche) passt nicht zu mehreren Tagen mit Lücken; großer Umbau |
| **B** | **Eigener Größenbericht `New-WorkerPerfSizingReport.ps1 -Path tag1,tag2,…`; der normale Bericht bekommt nur die Ursachenklasse** | Der normale Bericht bleibt, wie er ist; eine schlanke eigene Seite; dieselbe Auswertung je Aufzeichnung. **Gewählt (Kunde: „Variante B“).** |
| C | Mehrere Aufzeichnungen nur verdichtet als Tabelle in der Konsole | Billig, aber ohne Erklärung, Quellen und Kopiertext |

**Form der Empfehlung**

| | Form | |
|---|---|---|
| 1 | Nur die Richtung („mehr CPU nötig“) | zu wenig für eine Entscheidung |
| **2** | **Richtung plus gekennzeichnete Hochrechnung** | **Gewählt (Kunde: „Variante 2“)** |
| 3 | Feste Zielgröße | täuscht Genauigkeit vor; ausgeschlossen |

## 4. Daten

### 4.1 Neue Messwerte in der Aufzeichnung

Der Collector liest heute schon die Leistungsindikator-Gruppe „Processor Information“ für die Gesamtauslastung
(`cpu.host`). Aus derselben Gruppe kommen im schnellen Takt dazu:

| Signal | Inhalt | Zweck | Grundlage |
|---|---|---|---|
| `cpu.coreMax` | Auslastung des am stärksten belasteten logischen Prozessors (%) | ein Kern voll, die anderen frei | SZ-13 |
| `cpu.coreBusy` | Zahl der logischen Prozessoren über der Kern-Schwelle (Katalog, Vorschlag 90 %) | wie viele Kerne gleichzeitig voll sind | SZ-47 (90 %) |
| `cpu.perf` | `% Processor Performance` (_Total) | Leistungsanteil gegenüber Nennleistung | SZ-01, SZ-02 |
| `cpu.utility` | `% Processor Utility` (_Total) | geleistete Arbeit gegenüber Nenntakt | SZ-01, SZ-09 |

Dazu kommt aus der Gruppe „Memory“:

| Signal | Inhalt | Zweck | Grundlage |
|---|---|---|---|
| `mem.pagesout` | `Pages Output/sec` | entscheidet, ob ein hoher zugesicherter Speicher wirklich fehlt | SZ-35 |

Die Werte je Kern werden nicht einzeln gespeichert, um die Datenmenge klein zu halten. Gespeichert werden nur die
Verdichtungen je Takt.

**Entscheidung des Entwurfs zu `cpu.perf` und `cpu.utility`:** Kein Hersteller sagt, ob diese Zähler in einer VMware-VM
etwas bedeuten (SZ-12, nicht belegt). Es gibt nur Warnungen: Der angezeigte Takt im Gast ist nach vMotion veraltet
(SZ-07, SZ-08). Die beiden Werte werden deshalb gemessen und **angezeigt**, tragen aber **keine** Ursachenklasse. Der
erste echte Lauf zeigt, ob sie im Gast mehr als 100 % oder einen festen Wert liefern (Abschnitt 10). Eine eigene Klasse
„gedrosselte Kerne“ entfällt. An ihre Stelle tritt ein Hinweis in der Klasse „Leistung je Kern“: Energiesparplan
(Zustandsbild) und Energierichtlinie des Hosts prüfen (SZ-03, SZ-24, SZ-25).

Die Kern-Schwelle für `cpu.coreBusy` wird beim Aufzeichnen angewandt. Ihr Wert steht deshalb in `meta.json` der
Aufzeichnung.

Die neuen Signale gehören zur Grundmessung, es gibt also keine neue Kategorie für `-Skip`. Eine ältere Aufzeichnung ohne
sie wird weiter gelesen. Die Einordnung sagt dann, welche Unterscheidung ohne diese Werte nicht möglich ist.

Die Namen der Instanzen von „Processor Information“ (z. B. „0,0“, „0,_Total“, „_Total“) belegt keine geöffnete Seite
(SZ-11). Der Collector erkennt Gesamtinstanzen am Bestandteil `_Total` und wertet alle übrigen als einzelne logische
Prozessoren. Der Prüflauf auf dem Server bestätigt die Namen, wie bei den bisherigen Zählern.

### 4.2 Was schon da ist und genutzt wird

- CPU: Gesamt-CPU, Prozessor-Warteschlange je CPU, entzogene CPU-Zeit je vCPU (`cpu.steal`, VMware Tools).
- Arbeitsspeicher: belegt, zugesichert, Commit-Grenze, Seiteneinlagerungen.
- Eingabeverzögerung.
- Prozess-Schnappschüsse mit CPU je Prozess.
- Sitzungen.
- Anzahl logischer Prozessoren und RAM (Kopf der Aufzeichnung).
- Vorfälle mit Hauptverursacher.
- Ereignisse: Abstürze, Rückblick.
- Zustandsbild: vCPU-Zahl, Energiesparplan, VMware-Werte.

### 4.3 Der Server einer Aufzeichnung

Jede Aufzeichnung führt in `meta.json` heute schon den Computernamen. Für „derselbe Server“ ist in Phase 1 der
Computername maßgeblich (Entscheidung des Entwurfs). Bei MCS mit nicht persistentem Abbild bleibt der Name bei einer
Neubereitstellung gleich; das ist für die Größe derselbe Server. Ein abweichender Name führt zu einer klaren Meldung
(Abschnitt 6.1). Die Prüfung sitzt an einer einzigen Stelle, die Phase 2 ersetzt.

## 5. Ursache je Engpass (normaler Bericht)

### 5.1 Klassen

**Welche Vorfälle eine Klasse bekommen** (Entscheidung des Entwurfs):

- Vorfälle mit einem CPU- oder Arbeitsspeicher-Befund als Auslöser.
- Vorfälle mit Eingabeverzögerung ohne Engpass (`ohne-engpass`). Hier kann nur „Leistung je Kern“ oder „Host“ greifen;
  sonst bleibt der Vorfall ohne Klasse.

Begründung: Ein voller Kern auf 8 vCPU sind nur etwa 12,5 % Gesamt-CPU und lösen keinen CPU-Vorfall aus. Er zeigt sich
als Verzögerung ohne Engpass. Die Bildung der Vorfälle bleibt unverändert; es gibt keinen neuen Auslöser.

Die Schwellen der Klassen stehen im Katalog. Die Klassen in der Reihenfolge ihres Vorrangs:

1. **Host**
   - Erkennbar an: entzogene CPU-Zeit je vCPU (`cpu.steal`) über „auffällig“ aus `thresholds.json` (5 %) während des
     Vorfalls.
   - Was hilft (Richtung): VMware-Host prüfen lassen (Ready, Co-Stop, Host-Auslastung, Werte aus SZ-20/SZ-26). **Keine**
     zusätzlichen vCPUs; eher weniger, wenn Co-Stop hoch ist.
   - Grundlage: SZ-21, SZ-20, SZ-26, VM-08.
2. **Leistung je Kern**
   - Erkennbar an:
     - Der Hauptverursacher läuft im Vorfall anhaltend bei etwa einem vollen logischen Prozessor (≥ Kern-Schwelle von
       100 / N % der Server-CPU).
     - `cpu.coreMax` ist hoch.
     - `cpu.host` liegt unter „kritisch“.
   - Was hilft (Richtung): schnellere Kerne; Energiesparplan im Gast und Energierichtlinie des Hosts prüfen; Hersteller der
     Anwendung fragen. Mehr vCPUs helfen dieser Anwendung nicht.
   - Grundlage: SZ-13, SZ-14, SZ-15, SZ-16, SZ-03, SZ-24.
3. **Anwendung**
   - Erkennbar an: Ein einzelner Prozess, also eine Anwendung in **einer** Sitzung oder ein Systemprozess, trägt den
     Großteil der Last, ohne das Muster „Leistung je Kern“. Der Anteil steht im Katalog; Vorschlag: ≥ 50 % der im Vorfall
     **genutzten** CPU.
   - Nicht gemeint: Dieselbe Anwendung verteilt über viele Sitzungen, z. B. die Hauptanwendung der Rollenliste, die alle
     Benutzer nutzen. Das ist normale Last und zählt als „Kapazität“.
   - Was hilft (Richtung): Anwendung, Aufgabe oder Benutzer klären; keine Größenänderung.
   - Grundlage: Faustregel des Katalogs.
4. **Einmalig**
   - Erkennbar an: Der Hauptverursacher ist ein geplanter oder seltener Vorgang (Virenscan, Update, Bereitstellung). Die
     Rollenliste (`roles.json`) kennt diese Prozesse schon.
   - Was hilft (Richtung): Zeitplan ändern; keine Größenänderung.
   - Grundlage: Faustregel des Katalogs.
5. **Kapazität**
   - Erkennbar an: Ein CPU-Vorfall, der keine der Klassen 1 bis 4 trägt. Die Last ist also breit über Prozesse und
     Sitzungen verteilt, und der Host entzieht keine Rechenzeit.
   - Stufe „deutlich“: Die Warteschlange je CPU liegt bei mindestens 2, bei CPU ≥ 90 % (SZ-18). Sonst gilt die Stufe
     „knapp“: Die Last liegt über dem Ziel, aber der Server arbeitet noch alles ab.
   - Was hilft (Richtung): mehr vCPU oder mehr Server (Hochrechnung im Größenbericht).
   - Grundlage: SZ-18, SZ-47, VM-08.
6. **Arbeitsspeicher: Kapazität**
   - Erkennbar an: Zugesichert über RAM **und** anhaltend ausgelagerte Seiten (`mem.pagesout`), bei breit verteilter
     Last.
   - Was hilft (Richtung): mehr RAM oder weniger Sitzungen je Server.
   - Grundlage: SZ-35, SZ-38, SZ-39.
7. **Arbeitsspeicher: Commit-Grenze**
   - Erkennbar an: Zugesichert nahe der Commit-Grenze (`mem.commit` über „kritisch“), **ohne** anhaltendes Auslagern.
   - Was hilft (Richtung): Auslagerungsdatei vergrößern oder vom System verwalten lassen; mehr RAM ist dafür nicht nötig.
   - Grundlage: SZ-36.
8. **Arbeitsspeicher: Anwendung**
   - Erkennbar an: Ein einzelner Prozess wächst über die Aufzeichnung stetig oder trägt den Großteil.
   - Was hilft (Richtung): Anwendung klären, Verdacht auf Speicherleck.
   - Grundlage: Faustregel des Katalogs.
9. **Arbeitsspeicher: genutzt, kein Mangel**
   - Erkennbar an: Ein Arbeitsspeicher-Vorfall (`mem.used` hoch), der keine der Klassen 6 bis 8 trägt.
   - Was hilft (Richtung): nichts nötig. Windows nutzt freien Speicher; ein Mangel zeigt sich erst am Auslagern.
   - Grundlage: SZ-35.
10. **Nicht entscheidbar**
   - Erkennbar an: Werte fehlen (ältere Aufzeichnung, `-Skip`) oder widersprechen sich.
   - Was hilft: Der Bericht sagt, welche Messung fehlt.

Ein Vorfall kann mehrere Klassen tragen, z. B. Host **und** Kapazität, und zählt im Größenbericht für jede davon.
Sie stehen in dieser Reihenfolge, Host zuerst,
weil er jede andere Empfehlung entwertet (SZ-21, SZ-47: erst den Host ausschließen, dann prüfen, ob die Last mehr vCPUs
nutzen kann).

Die Widersprüche der Quellen werden so aufgelöst:

- **Commit über RAM:** ST-02 (Stalhood) sagt: RAM mindestens so groß wie die zugesicherten Bytes. SZ-35 (Microsoft) sagt:
  Commit über RAM ist erst mit anhaltendem Auslagern ein Mangel. Die Klasse folgt Microsoft. ST-02 erscheint als Hinweis
  im Größenbericht.
- **Co-Stop:** Für Co-Stop gibt es zwei Schwellen, über 0 % anhaltend (KB 431027) und über 3 % je vCPU (KB 438023). Der
  Bericht misst Co-Stop nicht und nennt beide Werte als Hinweis für den Host.

### 5.2 Regeln als Katalog

Die Regeln stehen als Daten in einem Katalog `src/sizing.de.json`. Er folgt denselben Grundsätzen wie
`guidance.de.json` und `health.de.json`:

- jede Regel mit Quelle (SZ-, VM-, ST-Kennung mit Adresse) und Art: Hersteller, Praxis oder Faustregel des Katalogs;
- Schwellen als benannte Werte;
- geprüft beim Laden.

Wo eine Schwelle in `thresholds.json` steht (cpu.host, cpu.queue, cpu.steal, mem.commit), nimmt der Katalog **diese**;
er führt keine eigene. Eigene Werte (Kern-Schwelle, Anteil des Hauptverursachers, Mindestmesszeit) sind Faustregeln des
Katalogs, wo keine Quelle eine Zahl nennt.

Die Einordnung nutzt die Daten, die der Bericht ohnehin bildet (Vorfälle mit Beteiligten, Signale im Fenster des
Vorfalls), und die neuen Signale aus 4.1.

### 5.3 Darstellung im normalen Bericht

- **Vorfallsansicht:** eine Zeile „Einordnung: Leistung je Kern“ mit der Begründung in einem Satz und den Zahlen, die sie
  tragen. Die Anleitung des Vorfalls bleibt. Klassen mit eigener Richtung (Host, Leistung je Kern) bringen einen Schritt
  mit, der in die Anleitung eingereiht wird (nach den Regeln P3-R75 des geführten Berichts).
- **Kopiertext:** die Einordnung als eigene Zeile.
- **Expertenansicht:** neue Kacheln „stärkster Kern“, „Kerne voll“ und „Leistungsanteil“ (Letztere als Anzeige ohne
  Bewertung); die Einordnung je Eintrag der Vorfallsspalte.

## 6. Größenbericht

### 6.1 Bedienung

`New-WorkerPerfSizingReport.ps1 -Path <Aufzeichnung1>, <Aufzeichnung2>, … [-OutFile] [-Mask Alles|Personen]
[-MaskMapFile] [-SizingFile] [-ThresholdFile] [-GuidanceFile] [-AppsFile] [-RoleFile]`

- Mindestens eine Aufzeichnung ist nötig; sinnvoll sind mehrere Arbeitstage.
- Unter der Mindestmesszeit des Katalogs (Vorschlag: drei Aufzeichnungen und zusammen zwölf Stunden Hauptzeit (6.3)) entsteht
  der Bericht trotzdem. Jede Empfehlung trägt dann den Hinweis „wenig Messzeit“.
- Alle Aufzeichnungen müssen denselben Computernamen haben. Sonst bricht das Skript ab und nennt die abweichende
  Aufzeichnung. Es weist darauf hin, dass der Vergleich verschiedener Server ein späterer Baustein ist.
- Ein Schnelllauf (`-HealthOnly`) zählt nicht als Aufzeichnung für die Last. Sein Zustandsbild wird als Beleg genutzt.
- Jede Aufzeichnung wird mit derselben Auswertung gelesen wie im normalen Bericht: Lader, Befunde, Vorfälle, Einordnung.
- Der Größenbericht ersetzt den normalen Bericht nicht. Er nennt je Aufzeichnung den Befehl, der ihren Bericht erzeugt.

### 6.2 Inhalt

1. **Kopf:** Server, Zeitraum, Zahl der Aufzeichnungen und Gesamtdauer, vCPU und RAM je Aufzeichnung. Wechselt die Größe
   zwischen den Aufzeichnungen, steht das als Hinweis da, und die Hochrechnung geht von der Größe der letzten Aufzeichnung
   aus.
2. **Ergebnis in einem Satz** (wie das Lagebild), z. B. „Wiederkehrender CPU-Engpass aus Kapazität an 4 von 5 Tagen;
   Spitzenlast 92 % bei 31 Sitzungen.“
3. **Empfehlungen** je Ressource (CPU, Arbeitsspeicher; dazu Host und Leistung je Kern, wo erkannt). Jede Empfehlung
   enthält:
   - Richtung,
   - Begründung,
   - Hochrechnung mit Kennzeichnung,
   - Annahmen,
   - Quellen,
   - Belastbarkeit: Messzeit, Dauer der Hauptzeit, Zahl der Aufzeichnungen.
4. **Verlauf über die Aufzeichnungen:**
   - je Aufzeichnung Spitze und P95 von CPU, Warteschlange je CPU und zugesichertem Speicher, dazu die höchste
     Sitzungszahl;
   - Engpässe mit ihrer Klasse;
   - „wiederkehrend“ heißt: dieselbe Klasse in mindestens der Hälfte der Aufzeichnungen (Faustregel des Katalogs).
5. **Sitzungen je vCPU** im Vergleich mit Microsofts Obergrenzen (6/4/2/1 je vCPU für leichte, mittlere, schwere und
   Power-Nutzer, SZ-43). Das ist eine Einordnung, keine Bewertung, weil die Klasse der Nutzer unbekannt ist.
6. **Liste der Aufzeichnungen** mit Ordner, Beginn, Dauer und Ende-Grund.
7. **Quellen** der genutzten Regeln.
8. **Kopiertext** der Empfehlungen, mit und ohne Namen, wie im geführten Bericht.

### 6.3 Hochrechnung

**CPU**

- **Hauptzeit** (Entscheidung des Entwurfs): Takte, in denen mindestens halb so viele Sitzungen angemeldet sind wie
  in der Spitze derselben Aufzeichnung. Dieser Zeitraum braucht keinen Kalender. Er passt zu Tagbetrieb wie zu
  Schichtbetrieb rund um die Uhr.
- **Maßgebliche Last L:** P95 von `cpu.host` über die Hauptzeit aller Aufzeichnungen. Die Spitze steht daneben.
- **Ziel T:** Schwelle „auffällig“ von `cpu.host` in `thresholds.json`, heute 75 %. Das liegt unter VMwares Obergrenze
  von 80 % anhaltend (VM-08, SZ-45) und lässt Raum für Anmeldespitzen (SZ-44).
- **Nicht linear:** Doppelt so viele Kerne tragen das 1,5- bis 1,9-Fache (SZ-42). Mit dem Exponenten k = log₂(f) ist die
  benötigte Größe

  n₂ = n₁ · (L / T)^(1/k), für f = 1,9 (k ≈ 0,93) und f = 1,5 (k ≈ 0,58).

  Das ergibt eine Spanne, gerundet auf ganze vCPU, nach oben auf eine gerade Zahl (VM-10). Beispiel: 8 vCPU, L = 92 %,
  T = 75 % → etwa 10 bis 12 vCPU.
- **Wann eine vCPU-Spanne steht** (Entscheidung des Entwurfs), in dieser Reihenfolge geprüft:
  1. „Host“ ist wiederkehrend → **keine** Spanne. Es steht: „Erst den Host klären; mehr vCPU verschärfen das“
     (SZ-21, SZ-47).
  2. L liegt unter T → keine Spanne; „Größe reicht für die gemessene Last“.
  3. „Kapazität“ ist wiederkehrend → **Spanne**. Ist zusätzlich „Leistung je Kern“ wiederkehrend, steht beides da: die
     Spanne für die breite Last und der Hinweis, dass sie der einen Anwendung nicht hilft.
  4. Sonst (L über T, aber die wiederkehrende Ursache ist Anwendung, Einmalig oder Leistung je Kern, oder es gibt keine
     wiederkehrende Ursache) → keine Spanne. Es steht: „Last über dem Ziel, aber nicht aus breiter Last; erst <Ursache>
     klären“.

  Ein einzelner Host-Vorfall, der nicht wiederkehrt, steht als Hinweis bei der Spanne.
- **Obergrenze je VM:** Microsoft empfiehlt für Mehrbenutzer-VMs 4 bis 24 vCPU; ab etwa 16 Kernen bringt jeder weitere
  Kern wenig (SZ-43). Der Server darf nicht mehr vCPUs haben als der Host physische Kerne, und er soll in einen NUMA-Knoten
  passen (SZ-22). Die Kernzahl des Hosts ist im Gast nicht sichtbar; der Bericht nennt die Bedingung zum Prüfen.
  - Liegt die obere Grenze der Spanne über 16, empfiehlt der Bericht zusätzlich „mehr Server statt größerer Server“.
  - Liegt sie über 24, empfiehlt er nur „mehr Server“, mit der Sitzungszahl, die der Server bei gleicher Größe unter T
    trägt: Sitzungen × (T / L), linear nach unten. Das ist zulässig, weil weniger Last auf gleichen Kernen nicht unter
    dem Skalierungsverlust leidet.

**Arbeitsspeicher**

- **Bedarf:** höchster zugesicherter Speicher C der Hauptzeit, verglichen mit dem RAM.
- **Mehr RAM empfehlen:** nur bei wiederkehrender Klasse „Arbeitsspeicher: Kapazität“, also mit anhaltendem Auslagern
  (SZ-35).
- **Hochrechnung** (Entscheidung des Entwurfs): RAM so groß, dass C höchstens 80 % des RAM ist, also C ÷ 0,8; gerundet
  nach oben auf volle 4 GB. Die Auslagerungsdatei zählt nicht mit. Ihre Größe hängt von der Einstellung ab, und
  Speicher, der ausgelagert werden muss, ist genau der Mangel.
- **Commit-Grenze ohne Auslagern:** Die Empfehlung heißt „Auslagerungsdatei vergrößern oder vom System verwalten
  lassen“, nicht „mehr RAM“ (SZ-36).
- **Hinweise:** Der Speicher je Sitzung muss mit der Sitzungszahl wachsen (SZ-39). ST-02 (Stalhood) steht als Praxisregel
  daneben.

**Kennzeichnung**

Jede Zahl der Hochrechnung trägt das Wort „Schätzung“ und ihre Annahmen:

- gleiche Last je Sitzung,
- Skalierung 1,5- bis 1,9-fach je Verdopplung,
- der Host liefert die zusätzliche Rechenzeit,
- Hyper-Threading nicht eingerechnet (SZ-23).

Dazu kommt der Satz: „Vor einem Umbau mit einem Pilot oder Lasttest bestätigen“ (SZ-46).

### 6.4 Darstellung

- Eine eigene, selbstständige HTML-Seite im Stil der geführten Ansicht: hell, gleiche Statusmarken, gleiche Wortregeln
  (der gemessene Rechner heißt „Server“).
- Keine externen Anfragen; mit Druckansicht.
- Diagramme:
  - Verlauf je Aufzeichnung: Balken je Tag für Spitze und P95.
  - Sitzungen gegen CPU: Punktwolke aus den Takten der Hauptzeit, mit der Linie des Ziels T.
- Maskierung wie im normalen Bericht.

### 6.5 Vorbereitung auf Phase 2

- Die Daten des Größenberichts sind eine Liste von Aufzeichnungen, jede mit ihrem Server.
- Die Auswertung „über die Aufzeichnungen“ fasst nach einer **Achse** zusammen. Phase 1 nutzt die Achse „Zeit“ (ein
  Server); Phase 2 fügt die Achse „Server“ hinzu, ohne das Datenformat zu ändern.
- Die Prüfung „derselbe Server“ ist eine einzelne Stelle (4.3).

## 7. Verhältnis zu anderen Teilen

- Lader, Befunde, Vorfälle und Kataloge werden unverändert genutzt. Der normale Bericht bekommt nur die Einordnung dazu
  (5.3).
- Das Zustandsbild wird genutzt, wenn es vorhanden ist (vCPU-Zahl, Energiesparplan, VMware-Werte als Belege). Nötig ist
  es nicht.
- Die neuen Signale (4.1) erweitern das Aufzeichnungsformat abwärtskompatibel.
- Der Prüflauf (Probe) bekommt die neuen Zähler, damit der erste echte Lauf ihre Namen und Werte bestätigt.

## 8. Tests

- **Simulation:** neue Szenen für jede Klasse:
  - Host-Entzug,
  - eine Anwendung auf einem Kern,
  - Kapazitätsengpass über viele Sitzungen,
  - einmaliger Scan,
  - Speicherleck einer Anwendung,
  - Speicherkapazität mit Auslagern,
  - hoher Commit ohne Auslagern (keine Klasse „Kapazität“).

  Dazu ein Mehrtageslauf: mehrere Aufzeichnungen mit wiederkehrendem und einmaligem Engpass.
- **Einordnung:** je Klasse ein Test mit den Grenzfällen der Schwellen; Vorrang Host; ältere Aufzeichnung ohne neue
  Signale.
- **Größenbericht:**
  - Hochrechnung von Hand nachgerechnet (Beispiel aus 6.3);
  - keine vCPU-Zahl bei Host oder Leistung je Kern;
  - Grenzen 16 und 24;
  - Hinweis „wenig Messzeit“;
  - Abbruch bei verschiedenen Servern;
  - Maskierung (Markertest wie bisher).
- **Seite:** Browserprüfungen wie beim geführten Bericht: Lesbarkeit, Statusmarken, schmale Breite, Druck, Wortregeln.

## 9. Grenzen

- Die Hochrechnung rechnet mit der Spanne von Microsoft (1,5- bis 1,9-fach). Reale Last kann davon abweichen, etwa durch
  Speicherbandbreite oder Grenzen der Anwendung.
- Der Host ist nur über die entzogene CPU-Zeit sichtbar. Co-Stop, Host-Auslastung und Ballooning sind es nicht.
- Eine Aufzeichnung mit wenigen Sitzungen sagt wenig über die Spitzenlast.
- Die Erkennung „Leistung je Kern“ stützt sich auf Prozess-Schnappschüsse (alle 6–15 s), nicht auf Threads, und auf
  `cpu.coreMax`. Ein Prozess, der zwischen Kernen wandert, hält trotzdem etwa einen vollen Kern.
- Für Citrix gibt es keine geöffnete Herstellerseite mit Benutzern je Kern oder vCPU je VM (SZ-31). Die Grenzen stützen
  sich auf Microsoft und VMware.

## 10. Offene Punkte für den ersten echten Lauf

- Instanznamen von „Processor Information“ auf dem Server (SZ-11).
- Liefern `% Processor Performance` und `% Processor Utility` in der VMware-VM sinnvolle Werte, also schwankend und bei
  Turbo über 100 %?
- Laufzeit des Lesens je Kern bei vielen vCPUs (Takt 2 s).
