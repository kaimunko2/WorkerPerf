# Maskierung im Bericht – Entwurf

Stand: 11.11.2026. Wird nach `2026-11-11-ereignisse-abstuerze-drucken-design.md` und vor `2026-11-11-gefuehrter-bericht-design.md` umgesetzt.

## 1. Ziel

Für die interne Analyse im vertraulichen Rahmen sind die echten Namen wertvoll; für die Weitergabe sollen sie sich ersetzen lassen. Aus derselben Aufzeichnung entstehen deshalb wahlweise ein vollständiger oder ein maskierter Bericht.

Erfolgskriterien:

- Ohne Parameter bleibt der Bericht wie bisher unmaskiert.
- Ein maskierter Bericht enthält keinen der Namen, die seine Stufe ersetzt, und zeigt dieselben Zahlen, Vorfälle und dieselbe Rangfolge wie der unmaskierte.
- Die Aufzeichnung wird nie verändert.

## 2. Bedienung

Parameter am Auswertungsskript:

- `-Mask Personen` ersetzt Benutzer- und Clientnamen.
- `-Mask Alles` ersetzt zusätzlich Server, Freigaben, Domänen, IP-Adressen und Druckernamen.
- `-MaskMapFile <Pfad>` schreibt die Zuordnung der Ersatznamen in eine getrennte Datei. Ohne diesen Parameter entsteht keine solche Datei.

Der Collector erhält keinen solchen Parameter; die Aufzeichnung enthält immer die echten Namen.

## 3. Was ersetzt wird

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

Der Dateiname des Berichts enthält bei `-Mask Alles` nicht den Namen des Workers.

## 4. Regeln

- **Durchgehend gleich:** Derselbe Name erhält im ganzen Bericht denselben Ersatz, unabhängig von Groß- und Kleinschreibung.
- **Stabil je Aufzeichnung:** Die Ersatznamen werden aus der vollständigen Aufzeichnung in fester Reihenfolge vergeben (Reihenfolge des ersten Auftretens), nicht aus dem gewählten Zeitausschnitt. Zwei maskierte Berichte derselben Aufzeichnung, auch ein Ausschnitt und der Gesamtbericht, verwenden dieselben Ersatznamen.
- **Nicht umkehrbar aus dem Bericht:** Der Bericht enthält keine Zuordnungstabelle und keine aus den Namen abgeleiteten Werte.
- **Eine Stelle:** Maskiert wird an genau einer Stelle, auf den fertigen Berichtsdaten unmittelbar vor dem Schreiben, für jeden Text, jeden Schlüssel und jeden Eigenschaftsnamen. Die Auswertung davor arbeitet mit den echten Namen.
- **Längste zuerst, ganze Namen:** Namen werden als ganze Namen ersetzt, längere vor kürzeren, damit ein kurzer Name keinen längeren zerschneidet.
- **Sichtbar:** Der Kopf des Berichts nennt die Stufe der Maskierung; die Berichtsdaten tragen sie als Feld.

## 5. Woher die Namen kommen

Die Liste der zu ersetzenden Namen entsteht aus den Feldern der Aufzeichnung, die Namen führen: Benutzer und Clients der Sitzungen; Benutzer in Ereignissen; Computername der Aufzeichnung; Server aus Freigaben, Containerpfaden und Gegenstellen; Domänen aus Sitzungen und Pfaden; Drucker aus Warteschlangen und Ereignissen. Dazu kommen feste Muster für Konten-SIDs, UNC-Server und IP-Adressen. Gegenstellen behalten ihre Bezeichnung (etwa „Oracle-Listener"); ihr Hostname wird bei `-Mask Alles` ersetzt.

## 6. Verhältnis zu anderen Teilen

- **Kopierknopf des geführten Berichts:** Sein Schalter „ohne Namen" nutzt dieselben Ersatznamen der Stufe `Alles`. In einem bereits maskierten Bericht entfällt der Schalter.
- **Prüfskript:** bleibt unverändert; es maskiert weiterhin immer.

## 7. Grenzen

- Ein Name in einem Feld, das die Auswertung nicht als Namen kennt, bleibt stehen. Deshalb entfallen Meldungstexte und Befehlszeilen in maskierten Berichten ganz.
- Aus dem Zusammenhang kann eine Person erkennbar bleiben, etwa als einziger Benutzer einer Anwendung. Das README weist darauf hin.
- Vor der Weitergabe ist der Bericht einmal durchzusehen.

## 8. Tests

- Der maskierte Bericht der simulierten Stunde enthält in keiner Stufe einen der Namen, die laut Tabelle zu ersetzen sind; geprüft über alle Texte, Schlüssel und Eigenschaftsnamen der Berichtsdaten und über die fertige HTML-Datei.
- Was laut Tabelle bleibt, steht unverändert da.
- Gleicher Name, gleicher Ersatz; zwei Läufe ergeben dieselben Ersatznamen; ein Zeitausschnitt und der Gesamtbericht stimmen überein.
- Ein kurzer Name, der Teil eines längeren ist, zerschneidet ihn nicht.
- Zahlen, Vorfälle, Muster und Rangfolge sind in maskiertem und unmaskiertem Bericht identisch.
- Die Zuordnungsdatei entsteht nur mit `-MaskMapFile` und enthält alle vergebenen Ersatznamen.
- Ohne `-Mask` ist der Bericht bytegleich zum bisherigen.

## 9. Offene Punkte

- Ob weitere Felder realer Aufzeichnungen Namen enthalten (etwa Beschreibungen von Diensten oder Druckerstandorte), zeigt die erste reale Aufzeichnung; die Liste aus Abschnitt 5 wird dann ergänzt.
