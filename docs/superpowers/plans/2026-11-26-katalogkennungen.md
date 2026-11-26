# Feste Kennungen im Katalog der Anleitung – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Der Quellennachweis nennt Schritte des Katalogs der Anleitung über feste Kennungen statt über ihre Position, sodass ein neuer oder verschobener Schritt keinen Verweis mehr verschiebt.

**Architecture:** Ein Schritt in `src/guidance.de.json` darf ein Feld `id` tragen (`<Situation>.<Stichwort>`); der Lader prüft es, verlangt es aber nicht. Ein einmaliges Skript trägt die Kennungen der 213 Schritte mit Quelle ein und ersetzt die 215 Positionsverweise in `docs/guidance/quellen.md`. Der Katalogtest vergleicht Nachweis und Katalog danach über die Kennung.

**Tech Stack:** Windows PowerShell 5.1 (Laufzeit), JSON, Markdown. Tests: PowerShell 7 mit Pester 5.

**Spec:** `docs/superpowers/specs/2026-11-26-katalogkennungen-design.md` (bindend).

## Global Constraints

- **Form der Kennung:** `<Situation>.<Stichwort>`; die Situation ist die des Schritts; das Stichwort besteht aus Kleinbuchstaben `a–z`, Ziffern und Bindestrichen, beginnt und endet nicht mit einem Bindestrich, höchstens 40 Zeichen. Regulärer Ausdruck des Stichworts: `^[a-z0-9]+(-[a-z0-9]+)*$`.
- **Eindeutig** im ganzen Katalog (über alle Situationen und die drei Listen `checks`, `remedies`, `contacts`).
- **Freiwillig im Lader:** ein Schritt ohne `id` bleibt gültig; ein Katalog des Kunden ohne Kennungen lädt wie bisher.
- **Pflicht im mitgelieferten Katalog** für jeden Schritt mit Quelle (ein Test, nicht der Lader).
- **Reihenfolge:** unverändert. Kein Schritt wird verschoben; `git diff` des Katalogs zeigt nur eingefügte Zeilen `"id": …`.
- **Formatierung des Katalogs bleibt:** die Kennung wird als Text eingefügt, die Datei nicht neu geschrieben.
- **Bericht:** `$script:WorkerPerfGuidanceOutputFields` bekommt `id` nicht; `tests/MaskCensus.json` ändert sich nicht.
- **Windows PowerShell 5.1**, `src/*.ps1` reines ASCII; Fehlermeldungen des Laders deutsch ohne Umlaute, wie die bestehenden.
- **Tests gezielt:** `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/<Datei>`; die ganze Suite einmal am Ende. `tests/GuidanceCatalogue.Tests.ps1` braucht rund acht Minuten.
- **Commits:** englisch, im Imperativ, ein Commit je Task, mit den Attributionszeilen der Sitzung.
- **Übergabe:** am Ende `docs/superpowers/uebergabe.md` aktualisieren (Abschnitt 2: der Punkt zu den Indexverweisen entfällt).

## Review Focus

1. **Ein Katalog des Kunden ohne jede Kennung** lädt und ergibt denselben Bericht wie bisher. → Task 1
2. **Dieselbe Kennung an zwei Schritten**, auch in verschiedenen Listen derselben Situation: der Lader lehnt ab und nennt Situation, Liste und Kennung. → Task 1
3. **Kennung mit der Situation eines anderen Eintrags** (`memory.x` an einem Schritt von `cpu`): abgelehnt. → Task 1
4. **Ein umgestellter Katalog** (zwei Schritte mit Quelle in einer Liste vertauscht): der Vergleich Nachweis ↔ Katalog bleibt grün. → Task 2
5. **Ein neuer Schritt mit Quelle ohne Kennung** im mitgelieferten Katalog: der Test nennt den Schritt mit seinen ersten Worten. → Task 2

## File Structure

| Datei | Verantwortung |
|---|---|
| `src/WorkerPerf.Guidance.ps1` | `Read-WorkerPerfGuidance`: Feld `id` annehmen und prüfen |
| `src/guidance.de.json` | 213 Kennungen an den Schritten mit Quelle |
| `docs/guidance/quellen.md` | Verweise über Kennungen; Absatz, der die Form erklärt |
| `tests/Guidance.Tests.ps1` | Tests des Laders |
| `tests/GuidanceCatalogue.Tests.ps1` | Vergleich über Kennungen; Pflicht je Schritt mit Quelle |
| `README.md` | Abschnitt „Der Katalog der Anleitung“: das Feld `id` |
| `docs/superpowers/uebergabe.md` | Stand |

---

### Task 1: Lader nimmt die Kennung an und prüft sie

**Files:**
- Modify: `src/WorkerPerf.Guidance.ps1` (die Prüfung der Elemente von `checks`, `remedies`, `contacts` in `Read-WorkerPerfGuidance`; dort, wo `precondition` geprüft wird)
- Test: `tests/Guidance.Tests.ps1` (Describe „Katalog laden und pruefen“)

**Interfaces:**
- Produces: nach dem Laden trägt ein Schritt mit Kennung das Feld `id` (Text); ein Schritt ohne Kennung hat das Feld nicht oder leer – Aufrufer lesen es mit `Get-WorkerPerfField $el 'id'`. Fehlermeldung über `Stop-WorkerPerfGuidance $Path <Situation> <Liste[n]> 'id' <Grund>` mit den Gründen `hat nicht die Form <Situation>.<stichwort>`, `nennt eine andere Situation`, `ist doppelt vorhanden (<erste Stelle>)`.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (mit `New-Catalogue` der Datei, das einen kleinen gültigen Katalog nach `$TestDrive` schreibt; `$Change` ändert ihn vor dem Schreiben)

```powershell
It 'nimmt eine Kennung an einem Schritt an und laesst Schritte ohne Kennung gueltig' {          # Review Focus 1
    $c = Read-WorkerPerfGuidance (New-Catalogue { $j.situations.cpu.checks[0] | Add-Member id 'cpu.prozess-pruefen' })
    $c.situations.cpu.checks[0].id | Should -Be 'cpu.prozess-pruefen'
    { Read-WorkerPerfGuidance (New-Catalogue {}) } | Should -Not -Throw
}
It 'lehnt eine fehlerhafte Kennung ab: <Name>' -TestCases @(
    @{ Name = 'Grossbuchstabe'; Id = 'cpu.Prozess'; Message = '*cpu*checks*id*Form*' }
    @{ Name = 'Umlaut'; Id = 'cpu.prüfen'; Message = '*id*Form*' }
    @{ Name = 'ohne Stichwort'; Id = 'cpu.'; Message = '*id*Form*' }
    @{ Name = 'Bindestrich am Ende'; Id = 'cpu.prozess-'; Message = '*id*Form*' }
    @{ Name = '41 Zeichen'; Id = 'cpu.' + ('a' * 41); Message = '*id*Form*' }
    @{ Name = 'andere Situation'; Id = 'memory.prozess'; Message = '*cpu*id*andere Situation*' }      # Review Focus 3
    @{ Name = 'kein Text'; Id = 7; Message = '*id*' }
) { { Read-WorkerPerfGuidance (New-Catalogue { $j.situations.cpu.checks[0] | Add-Member id $Id }) } | Should -Throw $Message }
It 'lehnt dieselbe Kennung an zwei Schritten ab, auch in verschiedenen Listen' {                  # Review Focus 2
    { Read-WorkerPerfGuidance (New-Catalogue { $j.situations.cpu.checks[0] | Add-Member id 'cpu.a'; $j.situations.cpu.remedies[0] | Add-Member id 'cpu.a' }) } |
        Should -Throw '*cpu*remedies*id*doppelt*'
}
It 'gibt die Kennung nicht in die Anleitung eines Vorfalls' {
    $WorkerPerfGuidanceOutputFields.checks | Should -Not -Contain 'id'; $WorkerPerfGuidanceOutputFields.remedies | Should -Not -Contain 'id'
}
```

Passt `New-Catalogue` der Datei nicht zu einem Skriptblock mit `$j`, den vorhandenen Helfer so verwenden, wie die Nachbartests es tun; die Aussagen bleiben.

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Guidance.Tests.ps1`
Expected: FAIL – der Lader lehnt das unbekannte Feld `id` ab

- [ ] **Step 3: Im Lader umsetzen** – `id` als erlaubtes, freiwilliges Feld eines Schritts; Prüfung von Typ, Form (Global Constraints), Situation und Eindeutigkeit über eine Tabelle Kennung → erste Stelle, die über alle Situationen läuft.

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Guidance.Tests.ps1`, danach `… -Path tests/Compat.Tests.ps1`
Expected: `Failed: 0` in beiden

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Guidance.ps1 tests/Guidance.Tests.ps1
git commit -m "Accept and check an optional id on a step of the guidance catalogue"
```

---

### Task 2: Kennungen eintragen, Nachweis und Katalogtest umstellen

**Files:**
- Modify: `src/guidance.de.json`, `docs/guidance/quellen.md`, `tests/GuidanceCatalogue.Tests.ps1`, `README.md` (Abschnitt „Der Katalog der Anleitung“), `docs/superpowers/uebergabe.md`
- Einmalig, nicht eingecheckt: ein Umstellungsskript im Scratch-Ordner

**Interfaces:**
- Consumes: Task 1 (der Lader nimmt `id` an).
- Produces: im Katalogtest liefert `Get-Elements` je Schritt zusätzlich `Id` (`''` ohne Kennung) und `Position` nur noch für Meldungen; `Get-Ids([string]$Text)` ersetzt `Get-Positions` und liest Kennungen in Backticks mit dem Ausdruck `` `([a-z]+(?:\.[a-z]+)?\.[a-z0-9]+(?:-[a-z0-9]+)*)` `` (Situationen wie `delay.many` haben selbst einen Punkt); die Zeilen der Tabellen (`$Rows`) tragen `Ids` statt `Positions`.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** – in `tests/GuidanceCatalogue.Tests.ps1`:

```powershell
It 'gibt jedem Schritt mit Quelle im mitgelieferten Katalog eine Kennung' {                       # Review Focus 5
    $missing = @($Sourced | Where-Object { -not $_.Id } | ForEach-Object { '{0}: {1}' -f $_.Position, $_.Texts[0].Substring(0, [Math]::Min(50, $_.Texts[0].Length)) })
    $missing | Should -BeNullOrEmpty
    @($Sourced | ForEach-Object { $_.Id } | Sort-Object -Unique).Count | Should -Be $Sourced.Count
}
It 'nennt im Nachweis keine Position mehr, nur Kennungen' {
    @([regex]::Matches($Doc, '`[a-z.]+\.(?:checks|remedies|contacts)\[\d+\]`')).Count | Should -Be 0
    @(Get-Ids $Doc | Sort-Object -Unique).Count | Should -BeGreaterOrEqual $Sourced.Count
}
It 'bleibt gruen, wenn zwei Schritte mit Quelle ihre Plaetze tauschen' {                          # Review Focus 4
    # Kopie des Katalogs mit vertauschten Schritten cpu.remedies[0] und [1]: dieselben Kennungen, dieselbe Zuordnung im Nachweis
    $swapped = Get-Elements (Get-SwappedCatalogue 'cpu' 'remedies' 0 1)
    @($swapped | Where-Object Id | ForEach-Object { $_.Id + '=' + $_.Source } | Sort-Object) | Should -Be @($Sourced | ForEach-Object { $_.Id + '=' + $_.Source } | Sort-Object)
}
```

`Get-SwappedCatalogue([string]$Situation, [string]$List, [int]$A, [int]$B)` liest den Katalog als JSON-Objekt und liefert ihn mit vertauschten Elementen.

Dazu werden die bestehenden Aussagen umgestellt (jede mit `# Aussage geaendert (Kennungen)`): alle Vergleiche über `Positions` laufen über `Ids`; die festen Positionen in den Tests (`'print.remedies[10]'`, `'print.remedies[14]'`, `'cpu.remedies[0]'`, `'memory.remedies[0]'`, `'print.remedies[2]'`, `'cpu.checks[6]'`, `'cpu.checks[7]'`, `'cpu.checks[8]'`, `'memory.checks[6]'`) werden zu den Kennungen dieser Schritte; die Regel „erste Worte hinter der Stelle“ prüft `` `<Kennung>` <erste Worte> ``. Aussagen über Texte der Katalogdatei mit ihrem Ort (`'situations.cpu.checks[0].text'`) und über die Reihenfolge in der Anleitung (`$g.checks[0]`) bleiben.

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/GuidanceCatalogue.Tests.ps1`
Expected: FAIL – kein Schritt hat eine Kennung, der Nachweis nennt Positionen

- [ ] **Step 3: Umstellungsskript schreiben und die Liste der Kennungen durchsehen**

Das Skript (Scratch, Python oder PowerShell):
1. liest den Katalog und bildet je Schritt mit Quelle ein Stichwort aus den ersten Worten des Texts: Platzhalter `{…}` entfernen, Umlaute umschreiben (ä→ae, ö→oe, ü→ue, ß→ss), Kleinbuchstaben, alles außer `a–z0–9` zu Bindestrichen, mehrfache Bindestriche zusammenziehen, Füllwörter am Anfang (`den`, `die`, `das`, `ob`, `dass`, `wenn`, `im`, `in`, `mit`) entfernen, nach höchstens 40 Zeichen an einer Wortgrenze abschneiden;
2. macht gleiche Stichwörter innerhalb einer Situation eindeutig: zuerst mit der Liste (`-abhilfe`, `-kontakt`), dann mit einer Ziffer;
3. schreibt die Zuordnung Position → Kennung in eine Datei zum Durchsehen;
4. fügt nach der Durchsicht in `src/guidance.de.json` je Schritt die Zeile `"id": "<Kennung>",` als erste Zeile des Elements ein (Texteinfügung, Einrückung des Elements) und ersetzt in `docs/guidance/quellen.md` jede Stelle `` `<Situation>.<Liste>[n]` `` durch `` `<Kennung>` ``.

Durchsicht: jede Kennung sagt, worum es im Schritt geht; nichtssagende (`pruefen`, `klaeren`) von Hand ersetzen. Die Zuordnungsdatei wird nicht eingecheckt.

- [ ] **Step 4: Umstellung ausführen und prüfen**

Run: `git diff --stat src/guidance.de.json docs/guidance/quellen.md`; `git diff src/guidance.de.json | grep '^[-+]' | grep -v '^+++\|^---' | grep -vc '^+ *"id": "'`
Expected: der Katalog hat 213 Zeilen mehr und keine weniger; der zweite Befehl gibt `0` aus (nur Zeilen mit `"id"` kamen dazu)

- [ ] **Step 5: Nachweis und README ergänzen**

- `docs/guidance/quellen.md`, Abschnitt „Wie die Quellen geprüft wurden“: ein Absatz, dass ein Schritt über seine Kennung `<Situation>.<Stichwort>` genannt wird, dass sie fest bleibt, wenn der Text oder der Platz des Schritts sich ändert, und dass sie im Katalog im Feld `id` steht.
- `README.md`, „Der Katalog der Anleitung“: das Feld `id` (freiwillig, Form, eindeutig; nötig nur für Schritte, auf die der Quellennachweis verweist; erscheint nicht in der Anleitung eines Vorfalls).
- `docs/superpowers/uebergabe.md`, Abschnitt 2: der Punkt zu den Indexverweisen und den Schritten am Ende von `checks` wird ersetzt durch „Der Nachweis verweist über Kennungen (`id`)“.

- [ ] **Step 6: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/GuidanceCatalogue.Tests.ps1`, danach `… -Path tests/Guidance.Tests.ps1` und `… -Path tests/Report.Tests.ps1`
Expected: `Failed: 0` in allen dreien (der Bericht ändert sich nicht: die Kennung steht nur im eingebetteten Katalog)

- [ ] **Step 7: Ganze Suite einmal, dann Commit**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1`
Expected: `Failed: 0`

```bash
git add src/guidance.de.json docs/guidance/quellen.md tests/GuidanceCatalogue.Tests.ps1 README.md docs/superpowers/uebergabe.md
git commit -m "Refer to the steps of the guidance catalogue by stable ids"
```

## Abgleich mit dem Entwurf

| Entwurf | Task |
|---|---|
| Feld `id`, Form, eindeutig, freiwillig | 1 |
| Kennung nicht in der Anleitung eines Vorfalls | 1 (Test), Global Constraints |
| 213 Kennungen, 215 Verweise, einmaliges Skript, Durchsicht | 2 |
| Katalogtest über Kennungen, Pflicht je Schritt mit Quelle | 2 |
| Schritte der Einordnung bleiben, Reihungsgruppe bleibt | Global Constraints (Reihenfolge unverändert) |
| README | 2 |
