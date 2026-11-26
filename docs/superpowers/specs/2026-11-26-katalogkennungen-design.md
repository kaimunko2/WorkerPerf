# Feste Kennungen im Katalog der Anleitung – Entwurf (kurz)

Stand 26.11.2026. Kleine Änderung; freigegeben werden Ansatz und Entwurf zusammen.

## Ziel und Warum

`docs/guidance/quellen.md` nennt Schritte des Katalogs `src/guidance.de.json` über ihre Position
(`cpu.checks[41]`). Jeder eingefügte oder verschobene Schritt verschiebt Verweise: beim Baustein „Größe des Servers“
mussten zwei neue Schritte deshalb ans Ende der Liste, und eine eigene Reihungsregel stellt sie im Bericht nach vorn.
Künftig nennt der Nachweis eine feste Kennung je Schritt. Dann kostet ein neuer Schritt keinen Verweis mehr.

## Ziele, Nicht-Ziele, Anti-Ziele

- **Ziel:** Jeder Schritt des mitgelieferten Katalogs, der eine Quelle trägt (heute 213 von 474), hat eine Kennung;
  der Nachweis (heute 215 Verweise) und der Katalogtest arbeiten nur noch mit ihr.
- **Nicht-Ziel:** Kennungen für Schritte ohne Quelle; eine andere Reihenfolge der Schritte; die Kennung im Bericht.
- **Anti-Ziel:** Ein Katalog des Kunden (`-GuidanceFile`) ohne Kennungen wird ungültig. Eine Kennung, die sich mit dem
  Text des Schritts ändert.

## Ansätze

**Wer eine Kennung trägt**

| | Ansatz | Abwägung |
|---|---|---|
| **A** | **nur Schritte mit Quelle; im Lader freiwillig** | Der Nachweis verweist nur auf Schritte mit Quelle. Eigene Kataloge bleiben gültig. **Gewählt.** |
| B | alle Schritte, Pflicht im Lader | einheitlich, aber eigene Kataloge brechen; viele Kennungen ohne Verweis |
| C | alle Schritte, im Lader freiwillig | verträglich, aber Pflegeaufwand ohne Nutzen für den Nachweis |

**Form der Kennung**

| | Form | Abwägung |
|---|---|---|
| **1** | **sprechend: `<Situation>.<Stichwort>`**, z. B. `cpu.vmware-host-bereitschaft` | im Nachweis und in Testmeldungen lesbar; stabil bei Textänderungen; 213 Stichwörter einmalig zu vergeben. **Gewählt.** |
| 2 | laufende Nummer je Situation (`cpu-017`) | schnell, aber nichtssagend |
| 3 | aus dem Text berechnet | ändert sich mit jeder Textkorrektur |

## Entwurf

- **Katalog:** ein Schritt (Element von `checks`, `remedies`, `contacts`) darf das Feld `id` tragen.
  Form: `<Situation>.<Stichwort>`; die Situation ist die des Schritts, das Stichwort besteht aus Kleinbuchstaben,
  Ziffern und Bindestrichen (ASCII, Umlaute umschrieben), höchstens 40 Zeichen. Die Kennung ist im ganzen Katalog
  eindeutig. Sie sagt nichts über die Reihenfolge; die Reihenfolge in der Datei bestimmt weiter die im Bericht.
- **Lader (`Read-WorkerPerfGuidance`):** nimmt `id` an, prüft Form, passende Situation und Eindeutigkeit und meldet
  einen Fehler mit Situation, Liste und Kennung. Ein Schritt ohne `id` bleibt gültig.
- **Bericht:** die Kennung gehört nicht zu den Feldern eines Schritts der Anleitung (`guide.checks[]` …). Der Katalog,
  den die Berichtsdaten als Ganzes mitführen (`guidance`), enthält sie wie jedes Feld des Katalogs; der Bestand der
  Maskierung führt ihn als einen Eintrag, er ändert sich nicht.
- **Nachweis (`docs/guidance/quellen.md`):** jede Stelle `` `cpu.checks[41]` `` wird zu `` `cpu.<Stichwort>` ``. Die
  Regeln zur Schreibweise (erste Worte des Schritts hinter der Kennung, erklärte Platzhalter) bleiben.
- **Tests (`tests/GuidanceCatalogue.Tests.ps1`):** der Vergleich Nachweis ↔ Katalog läuft über die Kennung; neu:
  jeder Schritt mit Quelle im mitgelieferten Katalog hat eine Kennung. Stellen, die die Reihenfolge im fertigen
  Bericht prüfen (`checks[0]` in `tests/Guidance.Tests.ps1`, `tests/report-browser.js`), bleiben.
- **Umstellung:** ein einmaliges Skript (nicht eingecheckt) schlägt je Schritt ein Stichwort aus den ersten Worten
  vor, trägt die Kennungen in den Katalog ein, ohne dessen Formatierung zu ändern, und ersetzt die Verweise im
  Nachweis. Die Liste der 213 Kennungen wird vor dem Eintragen durchgesehen; gleiche Textanfänge in verschiedenen
  Situationen (heute 38) unterscheidet die Situation, gleiche in derselben Situation ein Zusatz.
- **Folge, im selben Zug:** die zwei Schritte der Einordnung (`class.host`, `class.singlecore`) dürfen danach an den
  Anfang ihrer Listen; die eigene Reihungsgruppe in `Get-WorkerPerfGuidanceItems` bleibt trotzdem, weil sie die
  Reihenfolge auch in einem Katalog des Kunden sichert. Entscheidung des Entwurfs: die Schritte bleiben, wo sie sind.
- **README:** der Abschnitt „Der Katalog der Anleitung“ nennt das Feld `id` und seine Regeln.

## Dem Umsetzer überlassen

Wortlaut der Stichwörter und der Fehlermeldungen; ob die Prüfung der Form eine eigene Funktion ist.
