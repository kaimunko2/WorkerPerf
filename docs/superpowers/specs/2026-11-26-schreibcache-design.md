# Schreibcache von MCS als Messwert – Entwurf

Stand: 26.11.2026. Vom Benutzer gewählt: nur MCS mit Speicheroptimierung (MCS I/O); zeigen und melden;
Vorausschau und feste Grenze; Probelauf am echten Server zuerst; Messung über Dateisystem und Leistungsindikatoren getrennt.

## Ziel

Ein Admin sieht im Bericht, wie voll der Schreibcache eines nicht persistenten Servers ist, und wird gewarnt,
bevor das Cache-Laufwerk vollläuft. Heute schickt die Anleitung ihn nur von Hand zur Datei `mcsdif.vhdx`.

## Abgrenzung

- Nur MCS I/O. PVS und MCS ohne Speicheroptimierung: der Messwert fehlt, der Bericht zeigt nichts dazu.
- Kein Einfluss auf die Einordnung anderer Vorfälle (Speicher, Laufwerk) und auf den Bericht zur Größe des Servers.

## Stufe 1: Prüfschritt (vor allem anderen)

`Test-WorkerPerfSources.ps1` bekommt die Prüfung `mcs.cache`:

- sucht `mcsdif.vhdx` im Stammverzeichnis jedes fest eingebauten lokalen Laufwerks;
- nennt Laufwerksbuchstabe, Größe der Datei, Größe und freien Platz des Laufwerks;
- listet jede Kategorie von Leistungsindikatoren, deren Name mit `Citrix MCS` beginnt, mit ihren Indikatoren,
  Instanzen und aktuellen Werten;
- findet sie nichts, steht das als Ergebnis da (kein Fehler).

Die Ausgabe läuft durch die bestehende Maskierung. Der Benutzer lässt den Schritt einmal auf einem Server mit
MCS I/O laufen; erst mit dieser Ausgabe wird Stufe 2 festgelegt (Indikatornamen, Ort der Datei).

## Stufe 2: Messwert, Anzeige, Meldung

**Messung je Takt** (nur wenn die Datei beim Start gefunden wurde):

| Wert | Quelle | Pflicht |
|---|---|---|
| Größe der Überlaufdatei (MB) | Dateisystem | ja |
| freier Platz und Größe des Cache-Laufwerks (MB) | Dateisystem | ja |
| Cache im Arbeitsspeicher (MB) | Leistungsindikator „Citrix MCS“, Name aus Stufe 1 | nein (optionaler Zähler) |

Die Werte stehen als optionale Spalten in der Aufzeichnung; alte Aufzeichnungen bleiben lesbar.

**Anzeige:** eine Kachel „Schreibcache“ (frei auf dem Cache-Laufwerk, Größe der Überlaufdatei) und eine Kurve in
der Expertenansicht. Ohne Messwert erscheint beides nicht. Ist die Überlaufdatei seit Beginn der Messung
gewachsen, steht das als Hinweis an der Kachel („Cache im Arbeitsspeicher ist übergelaufen“) – kein Vorfall.

**Meldung** (neue Schwelle `mcs.cachefree` in `thresholds.json`, Werte änderbar):

- Warnung: beim Wachstum der letzten 30 Minuten wäre das Laufwerk in weniger als 60 Minuten voll.
- Kritisch: weniger als 10 % oder weniger als 2 GB frei.
- Die Vorausschau braucht mindestens 10 Minuten Messung und ein Wachstum über 0; sonst gibt es keine Warnung.

**Anleitung:** neue Situation im Katalog mit Prüfschritten, Abhilfen und Ansprechpartner; die vorhandenen
Schritte zu `mcsdif.vhdx` verweisen darauf. Jeder Schritt mit Quelle bekommt eine Kennung (Baustein
„Kennungen im Katalog“ muss vorher umgesetzt sein).

**Simulation:** ein Drehbuch-Abschnitt, in dem die Überlaufdatei wächst und das Laufwerk knapp wird, für Tests
und Demoseite.

## Offene Punkte bis zur Ausgabe aus Stufe 1

- genaue Namen von Kategorie und Indikatoren;
- ob `mcsdif.vhdx` immer im Stammverzeichnis liegt;
- ob die Datei bei laufendem Server lesbar ist (Größe), sonst nur der freie Platz des Laufwerks.
