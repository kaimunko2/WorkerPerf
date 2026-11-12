# Messkategorien – Entwurf

Stand: 12.11.2026. Unabhängig von den übrigen Entwürfen umsetzbar; Voraussetzung ist `2026-11-11-ereignisse-abstuerze-drucken-design.md` (Datenformat 3). Der Entwurf `2026-11-12-zustandsbild-design.md` baut hierauf auf.

## 1. Ziel

Der Collector misst im Standard alles. Wer den Messaufwand oder die Startzeit verringern will, lässt einzelne Kategorien bewusst weg. Der Bericht sagt bei jeder weggelassenen Kategorie, dass sie nicht gemessen wurde.

Erfolgskriterien:

- Ohne Angabe läuft der vollständige Mess- und Prüflauf wie bisher.
- Eine weggelassene Kategorie verursacht auf dem Server keine Abfragen.
- Im Bericht steht an jeder Stelle, die von einer weggelassenen Kategorie abhängt, „nicht gemessen" mit dem Grund. Nichts davon zählt als unauffällig.
- Die Basis lässt sich nicht abschalten.

## 2. Warum die Auswahl an der Messung sitzt

Nur dort spart sie etwas: Was der Collector nicht liest, belastet den Server nicht. Eine Auswahl im Auswertungsskript würde nur ausblenden, was schon gemessen wurde. Zum Ein- und Ausblenden dient die Filterung des Berichts.

Der Preis: Was nicht gemessen wurde, lässt sich nicht nachholen. Der Standard bleibt deshalb der vollständige Lauf.

## 3. Bedienung

Parameter am Collector: `-Skip <Kategorie>[,<Kategorie>…]`.

```
.\Start-WorkerPerfCapture.ps1 -DurationMinutes 10 -Skip Prozesse,Rueckblick
```

| Wert | Kategorie | Kosten | Beim Weglassen fehlt |
|---|---|---|---|
| `Prozesse` | Prozess-Schnappschüsse, Eingabeverzögerung je Prozess | am höchsten; wächst mit der Zahl der Prozesse | Verursacher eines Vorfalls, Zuordnung von Abstürzen zu Sitzungen, Rollen |
| `Laufwerke` | Antwortzeiten je Laufwerk, Profilcontainer und Freigabe | mittel; wächst mit der Zahl der Container | Antwortzeiten je Laufwerk, Container und Freigabe |
| `Citrix` | ICA-Werte je Sitzung | mittel; wächst mit der Zahl der Sitzungen | ICA-Latenz und Laufzeit je Sitzung |
| `Ereignisse` | Ereignisse während der Messung | klein je Takt | Abstürze, Hänger, Dienst-, Druck-, Profil- und Dateiserver-Ereignisse im Messzeitraum, Sitzungsereignisse |
| `Rueckblick` | Ereignisse der Tage vor der Messung | einmalig beim Start | der Abschnitt „Vor der Messung" |
| `Drucken` | Treiberliste, Zähler der Warteschlangen | einmalig, dazu kleine Zähler je Takt | Druckzustand, Treiberbezug bei Druckvorfällen |
| `Gegenstellen` | Verbindungsaufbau zu den konfigurierten Zielen | klein je Takt | Erreichbarkeit und Antwortzeit der Ziele |
| `Zustand` | das Zustandsbild (eigener Entwurf) | einmalig beim Start | der Bereich „Zustand des Workers" |

Regeln:

- **Basis:** CPU, Wartezeit der VM, Arbeitsspeicher, Datenträger gesamt, Netzwerk, Sitzungen und die Eingabeverzögerung je Sitzung laufen immer. Ohne sie werden keine Vorfälle erkannt, und sie sind der billigste Teil. Die Eingabeverzögerung je Sitzung gehört dazu, weil sie das Signal dafür ist, was Benutzer spüren.
- **Vorhandene Schalter:** `-NoCitrix` entspricht `-Skip Citrix`, `-EventLookbackDays 0` entspricht `-Skip Rueckblick`. Beide bleiben gültig; beide Schreibweisen zusammen sind erlaubt.
- **Werte:** ohne Rücksicht auf Groß- und Kleinschreibung; ein unbekannter Wert bricht den Start mit einer Meldung ab, die die gültigen Werte nennt. Doppelte Werte zählen einmal.
- **Wert `Zustand`:** wird schon mit diesem Entwurf angenommen; solange das Zustandsbild nicht gebaut ist, hat er keine Wirkung.
- **Beim Start** schreibt der Collector auf die Konsole, welche Kategorien er misst und welche nicht.

## 4. Aufzeichnung

- `meta.json` erhält die Liste der weggelassenen Kategorien.
- Jede Quelle einer weggelassenen Kategorie steht in den Quellen der Aufzeichnung als nicht verfügbar mit dem Grund „abgeschaltet (-Skip <Wert>)". Das ist dieselbe Stelle, an der heute `-NoCitrix` vermerkt wird.
- Dateien einer weggelassenen Kategorie werden nicht angelegt. Das Datenformat bleibt 3; Aufzeichnungen ohne die neue Angabe gelten als vollständig gemessen.
- Die Schutzgrenzen des Collectors (Größe, Messdauer je Takt) gelten unverändert.

## 5. Auswertung und Bericht

- **Kopf:** nennt die weggelassenen Kategorien.
- **Vorfälle:** werden aus der Basis weiter erkannt. Fehlt die Kategorie, aus der ein Teil der Erklärung käme, steht dort der Grund, zum Beispiel beim Verursacher: „Prozesse wurden bei dieser Messung nicht erfasst."
- **Vorfälle aus weggelassenen Signalen:** Ein Vorfall, dessen auslösendes Signal zu einer weggelassenen Kategorie gehört (Antwortzeit eines Laufwerks oder einer Freigabe, ICA-Werte), erscheint nur, soweit ihn ein Signal der Basis zeigt, etwa als Eingabeverzögerung ohne erkannten Engpass. Der Grund steht dabei; der Vorfall wird nicht als „ohne Engpass" gedeutet.
- **Abschnitte:** Ein Abschnitt, dessen Kategorie fehlt, zeigt „nicht gemessen" statt einer leeren Tabelle oder „keine Auffälligkeiten".
- **Soll-Ist und Kennzahlen:** Signale einer weggelassenen Kategorie zählen weder als erfüllt noch als verletzt.
- **Muster der Ereignisvorfälle:** Ein Muster, das eine fehlende Kategorie bräuchte, wird nicht gebildet und nicht als „trifft nicht zu" gezählt.
- **Geführter Bericht:** Seine Texte und Kopiertexte übernehmen die Formulierung „nicht gemessen".

## 6. Abhängigkeiten zwischen Kategorien

- Ohne `Prozesse` lassen sich Absturzereignisse nur über das Konto im Ereignis einem Benutzer zuordnen, nicht über den Prozess einer Sitzung.
- Ohne `Ereignisse` gibt es während der Messung keine Sitzungsereignisse (Anmelden, Trennen); die Sitzungsliste der Basis bleibt.
- Ohne `Drucken` bleiben Druckereignisse sichtbar, der Bezug zu Treibern fehlt.
- `Rueckblick` und `Ereignisse` sind unabhängig voneinander.

Der Collector lehnt keine Kombination ab; der Bericht benennt, was fehlt.

## 7. Tests

- Jede Kategorie einzeln und alle zusammen weggelassen: Die Aufzeichnung ist gültig, der Bericht entsteht ohne Fehler, und die Seite zeigt keine Skriptfehler.
- Die Quelle einer weggelassenen Kategorie wird nicht aufgerufen (geprüft an der Simulation und an den Windows-Platzhaltern).
- Der Bericht zeigt je Kategorie „nicht gemessen" an den abhängigen Stellen; kein Signal der Kategorie zählt im Soll-Ist.
- Die Basis läuft bei jeder Kombination; die Zeitfenster der Vorfälle, die ein Signal der Basis zeigt, sind dieselben wie im vollständigen Lauf. Vorfälle, deren auslösendes Signal weggelassen wurde, ändern ihre Art wie in Abschnitt 5 beschrieben.
- `-NoCitrix` und `-Skip Citrix` ergeben dieselbe Aufzeichnung; ebenso `-EventLookbackDays 0` und `-Skip Rueckblick`.
- Ein unbekannter Wert wird mit den gültigen Werten in der Meldung abgelehnt.
- Ohne `-Skip` ist die Aufzeichnung der simulierten Stunde dieselbe wie bisher, bis auf die neue Angabe in `meta.json`.
- Maskierung: Die neue Angabe enthält nur Kategorienamen; die Feldliste der Maskierung wird um sie ergänzt.

## 8. Grenzen

- Wie viel eine Kategorie auf einem bestimmten Server kostet, zeigt erst die Messung dort. Das README nennt die Größenordnung und verweist auf die Messdauer je Takt im Bericht.
- Den größten Effekt hat `Prozesse`; genau diese Kategorie macht Vorfälle erklärbar. Das README rät, sie nur wegzulassen, wenn die Messung selbst spürbar stört.

## 9. Offene Punkte

- Ob eine feinere Teilung nötig ist (etwa Freigaben getrennt von Laufwerken), zeigt die erste reale Messung.
