# Maskierung im Bericht – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `New-WorkerPerfReport.ps1 -Mask Personen|Alles [-MaskMapFile <Pfad>]` erzeugt aus derselben Aufzeichnung einen Bericht, in dem Benutzer und Clients (und bei `Alles` Server, Freigaben, Domänen, Adressen und Drucker) durch nummerierte Ersatznamen ersetzt sind; ohne `-Mask` bleibt alles wie bisher.

**Architecture:** Eine neue Datei `src/WorkerPerf.Mask.ps1` sammelt die Namen aus der vollständigen Aufzeichnung (unabhängig von `-From`/`-To`, in fester Reihenfolge des ersten Auftretens), baut daraus eine Ersetzung und wendet sie in genau einem Durchgang auf die fertigen Berichtsdaten an – jeden Text, jeden Schlüssel, jeden Eigenschaftsnamen –, unmittelbar bevor das Berichtsskript sie schreibt. Die Auswertung davor arbeitet mit den echten Namen. Die Maskierung des Prüfskripts (`Hide-WorkerPerfMaskedText` und Verwandte in `src/Test-WorkerPerfSources.ps1`) bleibt unverändert: das Prüfskript ist mit Absicht eine eigenständige Datei und ersetzt durch Platzhalter wie `<user>`; die Berichtsmaskierung ist eine eigene Umsetzung mit nummerierten Ersatznamen. Beide werden nicht zusammengelegt.

**Tech Stack:** Windows PowerShell 5.1 (Laufzeit), .NET-Regex, HTML/JavaScript ohne Bibliotheken. Tests: PowerShell 7 mit Pester 5, Node.js mit Playwright.

**Spec:** `docs/superpowers/specs/2026-11-11-maskierung-design.md`. Setzt `docs/superpowers/plans/2026-11-11-ereignisse-abstuerze-drucken.md` voraus (Felder `User`, `Printer`, `Object` in `events.csv`/`events_before.csv`, `printqueues.csv`, Berichtsdaten `before`, `print`).

## Global Constraints

- **Windows PowerShell 5.1:** jede `src/*.ps1` beginnt mit `#Requires -Version 5.1`, ist reines ASCII (Umlaute nur in JSON-Textdateien und `src/report-template.html`), ohne PowerShell-7-Syntax und ohne API, die es nur unter .NET Core gibt; eingebettetes C# auf Stand C# 5. `tests/Compat.Tests.ps1` erzwingt einen Teil davon.
- **Tests unter Linux:** PowerShell 7, Pester 5, Node/Playwright; Windows-Aufrufe dünn und über `tests/WindowsStandIns.ps1` getestet. Alle Tests: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`. Browserprüfungen: `pwsh -NoProfile -File tests/New-TestReports.ps1 -OutDir /tmp/wp-reports && node tests/report-browser.js /tmp/wp-reports`, Erfolg: `browser checks passed: <n>`.
- **Listen:** Funktionen, die Listen liefern, geben schlichte Pipeline-Ausgabe; Aufrufer schreiben `@(...)`.
- **Bericht:** eine einzelne HTML-Datei ohne externe Anfragen, ohne eingebundene Bibliotheken oder Schriften; Status als Symbol und Wort; deutsche Texte (auch die Ersatznamen „Benutzer 01" …) aus `src/texts.de.json`, nicht aus dem Code.
- **Collector:** bekommt keinen Maskierungsparameter, liest nur und ändert nichts am Server; die Aufzeichnung enthält immer die echten Namen und wird von der Auswertung nie verändert.
- **Öffentliches Repository:** keine Daten eines echten Servers; Tests verwenden erfundene Namen; Aufzeichnungen, Berichte, Zuordnungsdateien und Prüfergebnisse werden nicht eingecheckt (`.gitignore`: `*.html`, `*.csv` sind schon ausgeschlossen; Zuordnungsdateien heißen in den Tests `*.maskmap.json` und kommen dazu).
- **Bestand:** die acht Leistungsvorfälle der simulierten Stunde und alle bestehenden Tests bleiben grün, außer eine Task nennt genau, welche Aussage sich ändert und warum.
- **TDD:** jede Task schreibt zuerst den fehlschlagenden Test.
- **Commits:** englisch, im Imperativ, ein Commit je Task; keine Modellnamen in Code, Kommentaren oder Dokumenten.
- **Werte der Spezifikation:** Stufen genau `Personen` und `Alles`; Ersatznamen `Benutzer 01`, `Client 01`, `Server 01`, `Freigabe 01`, `Domäne 01`, `Adresse 01`, `Drucker 01` (zweistellig, ab 100 dreistellig); längere Namen vor kürzeren, nur ganze Namen, ohne Rücksicht auf Groß- und Kleinschreibung; Meldungstexte von Ereignissen und Befehlszeilen entfallen in jeder Stufe.

## Review Focus

Jede Zeile ist durch einen Test in der genannten Task abgesichert (`# Review Focus n`).

1. **Ein Benutzer heißt wie ein Programm oder ein Programm enthält seinen Namen** (Benutzer `excel`, Anwendung `EXCEL.EXE`; Gegenstelle „Oracle-Listener", Benutzer `oracle`). Erwartet: Anwendungs-, Prozess-, Dienst-, Treiber- und Gegenstellennamen bleiben lesbar, der Benutzer wird trotzdem ersetzt, wo er als Benutzer steht. → Task 2
2. **Derselbe Benutzer in anderer Schreibweise oder mit Domäne** (`MUELLER`, `KLINIK\mueller`, Profilordner `mueller.KLINIK`, `mueller_UPM_local`). Erwartet: überall derselbe Ersatz, der Pfad bleibt sonst erhalten. → Task 2
3. **Leere oder fehlende Namen in der Aufzeichnung** (Sitzung 0 ohne Benutzer, Ereignis ohne Drucker). Erwartet: kein leerer Name in der Liste, der Bericht entsteht. → Task 1
4. **Zwei Schlüssel werden nach dem Ersetzen gleich** (`user1` und `User1` als Schlüssel desselben Objekts). Erwartet: beide bleiben getrennt erhalten. → Task 2
5. **Großer Bericht** (die simulierte Stunde, rund 8 MB). Erwartet: die Maskierung verdoppelt die Laufzeit des Berichts nicht; ein Durchgang mit einem einzigen zusammengesetzten Muster. → Task 3

## File Structure

| Datei | Verantwortung |
|---|---|
| `src/WorkerPerf.Mask.ps1` (neu) | Namen aus der Aufzeichnung sammeln, Ersetzung bauen, Texte und Berichtsdaten maskieren, freie Texte leeren, Zuordnungsdatei schreiben |
| `src/New-WorkerPerfReport.ps1` | Parameter `-Mask`, `-MaskMapFile`; der eine Durchgang vor dem Schreiben |
| `src/texts.de.json` | Ersatznamen und Hinweistexte |
| `src/report-template.html` | Hinweis auf die Stufe im Kopf |
| `README.md`, `.gitignore` | Bedienung, Grenzen, Durchsicht vor der Weitergabe |
| `tests/Mask.Tests.ps1` (neu), `tests/report-browser.js`, `tests/TestHelpers.ps1` | Tests |

---

### Task 1: Namen aus der vollständigen Aufzeichnung

**Files:**
- Create: `src/WorkerPerf.Mask.ps1`, `tests/Mask.Tests.ps1`
- Modify: `src/texts.de.json`

**Interfaces:**
- Consumes: `Open-WorkerPerfCsvReader`, `Split-WorkerPerfCsvLine`, `ConvertFrom-WorkerPerfJsonFile` (`WorkerPerf.Common.ps1`/`WorkerPerf.Load.ps1`); `Read-WorkerPerfEventCsv`, `Read-WorkerPerfPrintDrivers` (`WorkerPerf.Events.ps1`).
- Produces:
  - `New-WorkerPerfMask -Path [string] -Level ('Personen'|'Alles') -Texts [hashtable] -> hashtable` `@{ Level; Entries = object[] (@{ Kind; Name; Replacement }); Protected = string[]; Lookup; Regex }`. `Lookup` bildet den kleingeschriebenen Namen auf den Ersatz ab; `Regex` ist das zusammengesetzte Muster für Task 2 (in Task 1 nur angelegt).
  - Arten und Stufe: `user`, `client`, `sid` in beiden Stufen; `server`, `share`, `domain`, `address`, `printer` nur in `Alles`. Ersatz aus `Texts['mask.<kind>']` mit der laufenden Nummer der Art.
  - Quellen in dieser Reihenfolge, je Datei zeilenweise (die ganze Datei, kein Zeitausschnitt): (1) `meta.json`: `Computer` → server; `Endpoints[].Host` → address bei IPv4, sonst server. (2) `sessions.csv`: `User` → user, `Domain` → domain, `ClientName` → client. (3) `shares.csv`: `Share` → share, sein Server → server. (4) `volumes.csv`: `Backing` → share und server. (5) `probes.csv`: `Host` wie (1). (6) `events.csv`, dann `events_before.csv`: `User` → user (ohne Domänenteil), `Printer` → printer, `Object` bei Gruppe `fileserver` → server. (7) `printqueues.csv`: `Queue` → printer. (8) feste Muster in `procinfo.csv` (`Path`), `volumes.csv` (`Volume`, `Backing`), `sessions.csv` (`WinStation`) und den Textfeldern von (6): Konten-SID `S-1-5-21-\d+-\d+-\d+-\d+` → sid, UNC-Server `\\<server>\` → server, IPv4 → address.
  - Ein Name zählt einmal (ohne Rücksicht auf Groß- und Kleinschreibung), in der Schreibweise seines ersten Auftretens; leere und nur aus Leerzeichen bestehende Namen werden übergangen; ein Name, der schon einer Art zugeordnet ist, bekommt keine zweite.
  - `Protected`: Namen, die stehen bleiben müssen, auch wenn ein ersetzter Name in ihnen vorkommt: `procinfo.csv` `Name`, die Dienste aus `Services`, aus Ereignissen `App`, `Module`, `Service`, `Driver`, aus `printdrivers.csv` `Name` und `Manufacturer`, aus `meta.json` `Endpoints[].Name` und `.Role`, die `label`-Werte von `roles.json` (Parameter `-RoleLabels [string[]]`, Standard `@()`).
  - `texts.de.json`: `"mask.user": "Benutzer {0:00}", "mask.client": "Client {0:00}", "mask.sid": "Konto {0:00}", "mask.server": "Server {0:00}", "mask.share": "Freigabe {0:00}", "mask.domain": "Domäne {0:00}", "mask.address": "Adresse {0:00}", "mask.printer": "Drucker {0:00}", "mask.other": "(Name entfernt)", "mask.level.Personen": "Personen maskiert", "mask.level.Alles": "alle Namen maskiert"`.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (`tests/Mask.Tests.ps1`; die kleine Aufzeichnung über `Write-TestRun` aus `tests/LoadHelpers.ps1`, mit erfundenen Namen)

```powershell
BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadHelpers.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Mask.ps1')
    $script:Texts = Read-WorkerPerfTexts (Join-Path $PSScriptRoot '../src/texts.de.json')
    $sess = @('0,0,,,Disconnected,Services,,,', '0,2,mueller,KLINIK,Active,ICA-1,WS-0001,,0', '0,3,MUELLER,KLINIK,Active,ICA-2,WS-0002,,0', '1,4,mu,KLINIK,Active,ICA-3,WS-0003,,0')
    $script:Run = Write-TestRun 'mask' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'sessions.csv' = $sess
        'shares.csv' = @('0,\\fs01\daten,1,1,5,5,1,1'); 'volumes.csv' = @('0,C:\Users\mueller_UPM_local\UpmTempMount,profile,2,\\fs02\upm$,1,1,5,5,1,1,0')
        'probes.csv' = @('0,DB,Datenbank,10.1.2.3,1521,4,'); 'procinfo.csv' = @('0,100,1,EXCEL.EXE,2,,C:\Users\anna\S-1-5-21-1-2-3-1108\x.exe,,') }
    [IO.File]::WriteAllLines((Join-Path $Run 'printqueues.csv'), @('Timestamp,Queue,Jobs,JobErrors,NotReadyErrors', "$(Get-Ts 5),PRN-EG-01,0,0,0"))
    function Get-Entries([string]$Level) { , @((New-WorkerPerfMask -Path $Run -Level $Level -Texts $Texts).Entries | ForEach-Object { '{0}:{1}={2}' -f $_.Kind, $_.Name, $_.Replacement }) }
}
Describe 'Namen der Aufzeichnung' {
    It 'vergibt Ersatznamen je Art in der Reihenfolge des ersten Auftretens' {
        Get-Entries 'Alles' | Should -Be @('server:T1=Server 01', 'server:h=Server 02', 'user:mueller=Benutzer 01', 'domain:KLINIK=Domäne 01', 'client:WS-0001=Client 01',
            'client:WS-0002=Client 02', 'user:mu=Benutzer 02', 'client:WS-0003=Client 03', 'share:\\fs01\daten=Freigabe 01', 'server:fs01=Server 03',
            'share:\\fs02\upm$=Freigabe 02', 'server:fs02=Server 04', 'address:10.1.2.3=Adresse 01', 'printer:PRN-EG-01=Drucker 01', 'sid:S-1-5-21-1-2-3-1108=Konto 01')
    }
    It 'ersetzt bei Personen nur Benutzer, Clients und Konten' {
        Get-Entries 'Personen' | Should -Be @('user:mueller=Benutzer 01', 'client:WS-0001=Client 01', 'client:WS-0002=Client 02', 'user:mu=Benutzer 02', 'client:WS-0003=Client 03', 'sid:S-1-5-21-1-2-3-1108=Konto 01')
    }
    It 'nimmt keinen leeren Namen auf und kennt die geschuetzten Namen' {                     # Review Focus 3
        $m = New-WorkerPerfMask -Path $Run -Level 'Alles' -Texts $Texts
        @($m.Entries | Where-Object { [string]::IsNullOrWhiteSpace($_.Name) }).Count | Should -Be 0
        $m.Protected | Should -Contain 'EXCEL.EXE'; $m.Protected | Should -Contain 'DB'
    }
}
```

`T1` und `h` sind `Computer` und `Endpoints[].Host` des `meta.json`, das `Write-TestRun` schreibt.

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Mask.Tests.ps1 -Output Minimal"`
Expected: FAIL, Datei `WorkerPerf.Mask.ps1` fehlt

- [ ] **Step 3: `New-WorkerPerfMask` mit der Signatur der Interfaces umsetzen** (Dateien zeilenweise über `Open-WorkerPerfCsvReader`, Spalten über den Kopf der Datei; eine fehlende Datei ist leer)

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Mask.ps1 src/texts.de.json tests/Mask.Tests.ps1
git commit -m "Collect the names of a capture for report masking"
```

---

### Task 2: Texte und Berichtsdaten maskieren

**Files:**
- Modify: `src/WorkerPerf.Mask.ps1`
- Test: `tests/Mask.Tests.ps1`

**Interfaces:**
- Consumes: `New-WorkerPerfMask` (Task 1).
- Produces:
  - `Hide-WorkerPerfReportText([string]$Text, $Mask) -> string`: ein Durchgang mit `$Mask.Regex` – alle Namen, nach Länge absteigend, als `(?<![\p{L}\p{N}])(Name1|Name2|…)(?![\p{L}\p{N}])` mit `IgnoreCase` und `CultureInvariant`; ein Treffer wird übergangen, wenn das Wort um ihn herum (begrenzt durch Leerraum und `\ / ( ) [ ] , ; : " ' < > | =`) einem Namen aus `Protected` gleicht. Danach die festen Muster aus Task 1 für Treffer, die nicht in `Lookup` stehen: Ersatz `Texts['mask.other']` (ohne Nummer, nicht umkehrbar). `$null` bleibt `$null`.
  - `Protect-WorkerPerfReportData($Data, $Mask) -> object`: neue Struktur; `IDictionary` → `[ordered]` mit maskierten Schlüsseln (werden zwei Schlüssel gleich, erhält der spätere ` (2)`, ` (3)` …), Listen → Arrays mit maskierten Elementen, `pscustomobject` → `[ordered]` mit maskierten Eigenschaftsnamen und Werten, `string` → `Hide-WorkerPerfReportText`, `StringBuilder` unverändert (vorgefertigte Zahlenreihen aus `New-JsonSeries`/`New-JsonIntegers`), alles andere unverändert.
  - `Clear-WorkerPerfReportFreeText($Data)`: setzt `text` auf `''` in `events[]`, `incidents[].events[]`, `before.near[]`, `before.incidents[].events[]`; `procs[].cmd` auf `''`; `quality.sourceErrors[].firstMessage` und `meta.endMessage` auf `''` (Meldungstexte, deren Namen die Auswertung nicht kennt). Ein Feld, das `$null` ist, bleibt `$null`, damit Aufbau und Zahl der Felder gleich bleiben.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben**

```powershell
Describe 'Ersetzen' {
    BeforeAll {
        function New-TestMask([string[]]$Users, [string[]]$Protected = @()) {
            $m = New-WorkerPerfMask -Path (Write-TestRun 'leer' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }) -Level 'Personen' -Texts $Texts
            # Testzugang: dieselbe Funktion, die New-WorkerPerfMask nutzt, baut Lookup und Regex aus einer Namensliste
            Set-WorkerPerfMaskNames -Mask $m -Entries @($Users | ForEach-Object -Begin { $n = 0 } -Process { $n++; @{ Kind = 'user'; Name = $_; Replacement = 'Benutzer {0:00}' -f $n } }) -Protected $Protected
            $m
        }
    }
    It 'ersetzt ganze Namen, laengere zuerst, ohne Ruecksicht auf die Schreibweise' {
        $m = New-TestMask @('user01', 'user010', 'mu', 'mueller')
        Hide-WorkerPerfReportText 'user010 und USER01, nicht user0100' $m | Should -Be 'Benutzer 02 und Benutzer 01, nicht user0100'
        Hide-WorkerPerfReportText 'Mueller sagt mu' $m | Should -Be 'Benutzer 04 sagt Benutzer 03'
    }
    It 'ersetzt Benutzer in Pfaden und Instanznamen' {                                          # Review Focus 2
        $m = New-TestMask @('mueller')
        Hide-WorkerPerfReportText 'C:\Users\mueller_UPM_local\UpmTempMount' $m | Should -Be 'C:\Users\Benutzer 01_UPM_local\UpmTempMount'
        Hide-WorkerPerfReportText '\\fs01\upm$\Mueller.KLINIK\x.vhdx KLINIK\MUELLER' $m | Should -Be '\\fs01\upm$\Benutzer 01.KLINIK\x.vhdx KLINIK\Benutzer 01'
    }
    It 'laesst Programm- und Gegenstellennamen stehen und ersetzt den Benutzer gleichen Namens' {   # Review Focus 1
        $m = New-TestMask @('excel', 'oracle') @('EXCEL.EXE', 'Oracle-Listener')
        Hide-WorkerPerfReportText 'Hauptverursacher: EXCEL.EXE in der Sitzung von excel; Gegenstelle Oracle-Listener (oracle)' $m |
            Should -Be 'Hauptverursacher: EXCEL.EXE in der Sitzung von Benutzer 01; Gegenstelle Oracle-Listener (Benutzer 02)'
    }
    It 'entfernt unbekannte Konten-SIDs' { Hide-WorkerPerfReportText 'S-1-5-21-9-9-9-1001_x' (New-TestMask @()) | Should -Be '(Name entfernt)_x' }
    It 'maskiert Texte, Schluessel und Eigenschaftsnamen und haelt gleich gewordene Schluessel getrennt' {   # Review Focus 4
        $m = New-TestMask @('user1')
        $d = [ordered]@{ meta = [ordered]@{ user = 'user1' }; byUser = [ordered]@{ user1 = 1; User1 = 2 }; obj = [pscustomobject]@{ user1 = 'a user1' }
            series = (New-Object System.Text.StringBuilder '[1,2,null]'); n = 3.5; list = @('user1', 7) }
        $r = Protect-WorkerPerfReportData $d $m
        $r.meta.user | Should -Be 'Benutzer 01'; @($r.byUser.Keys) | Should -Be @('Benutzer 01', 'Benutzer 01 (2)'); $r.byUser['Benutzer 01 (2)'] | Should -Be 2
        $r.obj['Benutzer 01'] | Should -Be 'a Benutzer 01'; $r.series.ToString() | Should -Be '[1,2,null]'; $r.n | Should -Be 3.5; $r.list | Should -Be @('Benutzer 01', 7)
    }
    It 'leert Meldungstexte und Befehlszeilen' {
        $d = [ordered]@{ meta = [ordered]@{ endMessage = 'x' }; events = @([ordered]@{ text = 'geheim' }); procs = @([ordered]@{ cmd = 'tool.exe /u geheim' })
            incidents = @([ordered]@{ text = 'bleibt'; events = @([ordered]@{ text = 'geheim' }) }); before = [ordered]@{ near = @([ordered]@{ text = 'geheim' }); incidents = @() }
            quality = [ordered]@{ sourceErrors = @([ordered]@{ firstMessage = 'geheim' }) } }
        Clear-WorkerPerfReportFreeText $d
        ($d | ConvertTo-Json -Depth 6) | Should -Not -Match 'geheim'; $d.incidents[0].text | Should -Be 'bleibt'
    }
}
```

`Set-WorkerPerfMaskNames -Mask -Entries -Protected` ist der Teil von `New-WorkerPerfMask`, der aus der Namensliste `Entries`, `Lookup`, `Protected` und `Regex` setzt; Task 1 ruft ihn am Ende auf.

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Mask.Tests.ps1 -Output Minimal"`
Expected: FAIL, `Hide-WorkerPerfReportText` nicht definiert

- [ ] **Step 3: `Set-WorkerPerfMaskNames`, `Hide-WorkerPerfReportText`, `Protect-WorkerPerfReportData`, `Clear-WorkerPerfReportFreeText` mit den Signaturen der Interfaces umsetzen**

Ein einziges `[regex]` mit `RegexOptions.Compiled`, gebaut einmal je Maske; Texte ohne Treffer gehen über `IsMatch` ohne Ersetzung zurück. Der Auswerter des Treffers (`MatchEvaluator`) prüft das umgebende Wort gegen eine Hashtable der geschützten Namen.

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/WorkerPerf.Mask.ps1 tests/Mask.Tests.ps1
git commit -m "Replace names in report texts, keys and property names"
```

---

### Task 3: `-Mask` und `-MaskMapFile` am Berichtsskript

**Files:**
- Modify: `src/New-WorkerPerfReport.ps1` (Hilfe, `param` Zeile 50, Einbinden Zeile 77, Eingaben ab Zeile 236, `$data` und Schreiben ab Zeile 817), `tests/TestHelpers.ps1` (`New-TestReports`: zusätzlich `report-masked.html` mit `-Mask Alles`, im Ergebnis unter dem Schlüssel `Masked`), `.gitignore`
- Test: `tests/Mask.Tests.ps1`

**Interfaces:**
- Consumes: Tasks 1 und 2.
- Produces:
  - Parameter `[ValidateSet('Personen', 'Alles')][string]$Mask`, `[string]$MaskMapFile`. `-MaskMapFile` ohne `-Mask`: `throw '-MaskMapFile setzt -Mask voraus.'`; gleicher Pfad wie `-OutFile`: `throw '-MaskMapFile darf nicht die Berichtsdatei sein.'`. Bei `-Mask Alles` und einem Dateinamen von `-OutFile`, der den `Computer` aus `meta.json` enthält (Groß- und Kleinschreibung egal): `throw "Der Dateiname des Berichts nennt den Worker; bei -Mask Alles bitte einen anderen Namen waehlen."` (der Standardname `report.html` enthält ihn nicht).
  - Ablauf nur mit `-Mask`: nach dem Zusammenbau von `$data` und vor dem Schreiben `Clear-WorkerPerfReportFreeText $data`, `$data.meta['mask'] = $Mask`, `$maskObj = New-WorkerPerfMask -Path $Path -Level $Mask -Texts $texts -RoleLabels @($roles | ForEach-Object { [string]$_.label })`, `$data = Protect-WorkerPerfReportData $data $maskObj`, mit `-MaskMapFile` danach `Save-WorkerPerfMaskMap -Mask $maskObj -Path $MaskMapFile`. Ohne `-Mask` wird keine dieser Funktionen aufgerufen und kein Feld `mask` gesetzt.
  - `Save-WorkerPerfMaskMap -Mask -Path` (in `WorkerPerf.Mask.ps1`): UTF-8 ohne BOM, `{ "level": "Alles", "entries": [ { "kind", "name", "replacement" } ] }` in der Reihenfolge der Vergabe.
  - Konsolenausgabe nennt nur Zahlen und den Pfad, keine Namen.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben** (in `tests/Mask.Tests.ps1`, eigener `Describe` mit der simulierten Stunde)

```powershell
Describe 'Maskierter Bericht der simulierten Stunde' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        $script:R = New-TestReports (Join-Path $TestDrive 'r'); $script:Report = Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1'
        $script:Plain = Get-ReportData $R.Report
        function New-Masked([string]$Name, [hashtable]$Extra = @{}) { $out = Join-Path $TestDrive "$Name.html"; [void](& $Report -Path $R.Run -OutFile $out @Extra 6>$null); $out }
        function Get-Words([string]$Html) { [IO.File]::ReadAllText($Html) }
        $script:Persons = @(2..26 | ForEach-Object { 'user{0:d3}' -f ($_ - 1) }) + @('WS-\d{4}')
        $script:Others = @('SIM-VDA01', 'CONTOSO', 'fs01', 'ora01\.sim\.local', 'proxy\.sim\.local', 'PRN-EG-01', 'PRN-OG-02')
        function Get-Leaves($o) {                        # Zahlen und Wahrheitswerte in Reihenfolge; Texte zaehlen nur als Platzhalter
            if ($null -eq $o) { 'null' } elseif ($o -is [string]) { 's' } elseif ($o -is [ValueType]) { [string]$o }
            elseif ($o -is [System.Collections.IEnumerable]) { 'a'; foreach ($x in $o) { Get-Leaves $x } }
            else { 'o'; foreach ($p in $o.PSObject.Properties) { Get-Leaves $p.Value } }
        }
    }
    It 'enthaelt in keiner Stufe einen der zu ersetzenden Namen, weder in den Daten noch in der Datei' {
        $p = Get-Words (New-Masked 'p' @{ Mask = 'Personen' }); $a = Get-Words (New-Masked 'a' @{ Mask = 'Alles' })
        foreach ($n in $Persons) { $p | Should -Not -Match $n; $a | Should -Not -Match $n }
        foreach ($n in $Others) { $a | Should -Not -Match $n }
        $a | Should -Not -Match 'USER008'                                                            # Meldungstext des AppLocker-Ereignisses entfaellt
    }
    It 'laesst stehen, was laut Tabelle bleibt' {
        $p = Get-ReportData (New-Masked 'p2' @{ Mask = 'Personen' }); $a = Get-ReportData (New-Masked 'a2' @{ Mask = 'Alles' })
        $p.meta.computer | Should -Be 'SIM-VDA01'; ($p.sessions | Where-Object id -eq 2).domain | Should -Be 'CONTOSO'; @($p.shares.name) | Should -Contain '\\fs01\daten'
        $a.meta.computer | Should -Be 'Server 01'; $a.meta.mask | Should -Be 'Alles'; $p.meta.mask | Should -Be 'Personen'
        @($a.apps.name) | Should -Contain 'EXCEL.EXE'; @($a.probes.name) | Should -Contain 'Oracle-Listener'; ($a.print.drivers | Where-Object involved).name | Should -Be 'HP Universal Printing PCL 6 (Sim)'
        ($a.incidents | Where-Object lead -eq 'cpu').text | Should -Match 'Hauptverursacher: EXCEL\.EXE in der Sitzung von Benutzer \d\d '
        @($a.events | Where-Object { $_.text -ne '' }).Count | Should -Be 0; @($a.procs | Where-Object { $_.cmd -ne '' }).Count | Should -Be 0
    }
    It 'zeigt dieselben Zahlen, Vorfaelle, Muster und Rangfolge' {
        $a = Get-ReportData (New-Masked 'a3' @{ Mask = 'Alles' })
        $l1 = @(Get-Leaves $Plain); $l2 = @(Get-Leaves $a)
        $l2.Count | Should -Be ($l1.Count + 1)                                                         # das Feld meta.mask kommt dazu
        $pat = { param($d) @($d.incidents | Where-Object type -eq 'ereignis' | ForEach-Object { @($_.event.patterns.id) -join ',' }) }
        @($a.incidents.id) | Should -Be @($Plain.incidents.id); & $pat $a | Should -Be (& $pat $Plain)
        ($a.incidents | Where-Object lead -eq 'cpu').contributors.cpu.procs.k | Should -Be ($Plain.incidents | Where-Object lead -eq 'cpu').contributors.cpu.procs.k
    }
    It 'vergibt in zwei Laeufen und in einem Zeitausschnitt dieselben Ersatznamen' {
        $cpu = $Plain.incidents | Where-Object lead -eq 'cpu'
        $m1 = Join-Path $TestDrive 'm1.maskmap.json'; $m2 = Join-Path $TestDrive 'm2.maskmap.json'; $m3 = Join-Path $TestDrive 'm3.maskmap.json'
        [void](New-Masked 'r1' @{ Mask = 'Alles'; MaskMapFile = $m1 }); [void](New-Masked 'r2' @{ Mask = 'Alles'; MaskMapFile = $m2 })
        $cut = Get-ReportData (New-Masked 'r3' @{ Mask = 'Alles'; MaskMapFile = $m3; From = (Get-ServerTime $R.Run ($cpu.start - 60000)); To = (Get-ServerTime $R.Run ($cpu.end + 60000)) })
        [IO.File]::ReadAllText($m1) | Should -Be ([IO.File]::ReadAllText($m2)); [IO.File]::ReadAllText($m1) | Should -Be ([IO.File]::ReadAllText($m3))
        $full = Get-ReportData (Join-Path $TestDrive 'r1.html')
        ($cut.sessions | Where-Object id -eq 4).user | Should -Be ($full.sessions | Where-Object id -eq 4).user
    }
    It 'schreibt die Zuordnung nur mit -MaskMapFile und mit allen Ersatznamen' {
        $before = @(Get-ChildItem $TestDrive -Filter '*.maskmap.json' -Recurse).Count
        [void](New-Masked 'nomap' @{ Mask = 'Alles' }); @(Get-ChildItem $TestDrive -Filter '*.maskmap.json' -Recurse).Count | Should -Be $before
        $map = Get-Content (Join-Path $TestDrive 'm1.maskmap.json') -Raw | ConvertFrom-Json
        $map.level | Should -Be 'Alles'; @($map.entries | Where-Object kind -eq 'user').Count | Should -Be 25; @($map.entries | Where-Object kind -eq 'printer').replacement | Should -Be @('Drucker 01', 'Drucker 02')
        { New-Masked 'x' @{ MaskMapFile = (Join-Path $TestDrive 'y.maskmap.json') } } | Should -Throw '*setzt -Mask voraus*'
        { New-Masked 'SIM-VDA01-bericht' @{ Mask = 'Alles' } } | Should -Throw '*nennt den Worker*'
    }
    It 'bleibt ohne -Mask bytegleich zum Bericht ohne Maskierungscode' {
        $src = Join-Path $TestDrive 'nomask-src'; [void](New-Item -ItemType Directory $src); Copy-Item (Join-Path $PSScriptRoot '../src/*') $src
        [IO.File]::WriteAllText((Join-Path $src 'WorkerPerf.Mask.ps1'), "#Requires -Version 5.1`nfunction New-WorkerPerfMask { throw 'aufgerufen' }`nfunction Protect-WorkerPerfReportData { throw 'aufgerufen' }`nfunction Clear-WorkerPerfReportFreeText { throw 'aufgerufen' }`n")
        $a = Join-Path $TestDrive 'plain-a.html'; $b = Join-Path $TestDrive 'plain-b.html'
        [void](& $Report -Path $R.Run -OutFile $a 6>$null); [void](& (Join-Path $src 'New-WorkerPerfReport.ps1') -Path $R.Run -OutFile $b 6>$null)
        $norm = { param($f) [IO.File]::ReadAllText($f) -replace '"generated":\d+', '"generated":0' }
        & $norm $a | Should -BeExactly (& $norm $b); (Get-ReportData $a).meta.PSObject.Properties.Name | Should -Not -Contain 'mask'
    }
    It 'maskiert die simulierte Stunde, ohne die Laufzeit zu verdoppeln' {                        # Review Focus 5
        $t0 = [Diagnostics.Stopwatch]::StartNew(); [void](New-Masked 'tp'); $plain = $t0.Elapsed.TotalSeconds
        $t1 = [Diagnostics.Stopwatch]::StartNew(); [void](New-Masked 'tm' @{ Mask = 'Alles' }); $t1.Elapsed.TotalSeconds | Should -BeLessThan (2 * $plain)
    }
}
```

`.gitignore` erhält `*.maskmap.json`.

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Mask.Tests.ps1 -Output Minimal"`
Expected: FAIL, Parameter `Mask` nicht gefunden

- [ ] **Step 3: Parameter, Prüfungen und den einen Durchgang mit den Signaturen der Interfaces einbauen**

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"`
Expected: `Failed: 0`

- [ ] **Step 5: Commit**

```bash
git add src/New-WorkerPerfReport.ps1 src/WorkerPerf.Mask.ps1 tests/Mask.Tests.ps1 tests/TestHelpers.ps1 .gitignore
git commit -m "Add -Mask and -MaskMapFile to the report"
```

---

### Task 4: Hinweis im Kopf des Berichts und README

**Files:**
- Modify: `src/report-template.html` (Kopfzeile, Zeilen 780–788), `tests/report-browser.js`, `README.md` (Abschnitte „2. Auswerten", „Datenschutz")

**Interfaces:**
- Consumes: `meta.mask` (Task 3), `report-masked.html` aus `New-TestReports`.
- Produces: `#maskInfo` im Kopf neben `#subtitle`, nur wenn `meta.mask` gesetzt ist: Symbol und Text „Maskiert: Personen (Benutzer und Clients ersetzt)" bzw. „Maskiert: alle Namen (Benutzer, Clients, Server, Freigaben, Domänen, Adressen, Drucker ersetzt)"; die Texte stehen als Tabelle im Skriptteil der Vorlage. Im unmaskierten Bericht fehlt das Element.

- [ ] **Step 1: Die Browserprüfung erweitern** (neue Funktion, in der Schleife aufrufen)

```js
async function checkMask(browser, dir, scheme) {
  const { page } = await open(browser, path.join(dir, 'report.html'), scheme);
  ok(await page.locator('#maskInfo').count() === 0, 'unmaskiert ohne Hinweis');
  await page.close();
  const m = await open(browser, path.join(dir, 'report-masked.html'), scheme);
  ok((await m.page.locator('#maskInfo').innerText()).includes('Maskiert: alle Namen'), 'Stufe im Kopf');
  ok(!(await m.page.locator('body').innerText()).match(/user0\d\d|SIM-VDA01|CONTOSO/), 'keine Namen auf der Seite');
  ok(m.page.errors.length === 0, 'Skriptfehler maskiert: ' + m.page.errors.join(' | '));
  await m.page.close();
}
```

- [ ] **Step 2: Prüfung ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/New-TestReports.ps1 -OutDir /tmp/wp-reports && node tests/report-browser.js /tmp/wp-reports`
Expected: `AssertionError: Stufe im Kopf`

- [ ] **Step 3: Hinweis in der Vorlage bauen**

- [ ] **Step 4: Prüfungen ausführen**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Minimal"` und die Browserprüfungen
Expected: `Failed: 0` und `browser checks passed: <n>`

- [ ] **Step 5: README** – Aufruf mit `-Mask Personen`, `-Mask Alles`, `-MaskMapFile`; Tabelle aus Abschnitt 3 der Spezifikation; Grenzen aus Abschnitt 7 (Namen in unbekannten Feldern, Erkennbarkeit aus dem Zusammenhang, etwa als einziger Benutzer einer Anwendung; Bericht vor der Weitergabe einmal durchsehen); die Zuordnungsdatei enthält die echten Namen und gehört nicht zum weitergegebenen Bericht; das Prüfskript maskiert weiterhin immer und auf eigene Weise.

- [ ] **Step 6: Commit**

```bash
git add src/report-template.html tests/report-browser.js README.md
git commit -m "Show the masking level in the report header and document masking"
```

---

## Self-Review

- **Spec coverage:** Abschnitt 2 → Task 3 (Parameter, kein Collector-Parameter); 3 → Tasks 1, 2 (Arten je Stufe, Meldungstexte und Befehlszeilen), Task 3 (Dateiname); 4 → Task 2 (durchgehend gleich, ganze Namen, längere zuerst), Task 1 (stabil je Aufzeichnung), Task 3 (eine Stelle, keine Zuordnung im Bericht, sichtbar als Feld), Task 4 (Kopf); 5 → Task 1; 6 → Prüfskript unverändert (Architecture); der Schalter „ohne Namen" kommt mit dem geführten Bericht und nutzt `New-WorkerPerfMask -Level Alles`; 7 → Task 4 (README); 8 → Task 3 und Task 2.
- **Step scan:** Signaturen und Werte stehen in den Interfaces; keine Funktionskörper; die Ersatznamen kommen aus `texts.de.json`.
- **Type consistency:** `New-WorkerPerfMask` liefert `Entries`, `Lookup`, `Protected`, `Regex`, `Level`; `Set-WorkerPerfMaskNames` setzt dieselben Felder; Task 3 und der Folgeplan rufen nur `New-WorkerPerfMask`, `Hide-WorkerPerfReportText`, `Protect-WorkerPerfReportData`, `Clear-WorkerPerfReportFreeText`, `Save-WorkerPerfMaskMap`.
- **Review Focus:** fünf Zeilen, je ein Test in Task 1, 2 oder 3.
- **Proportion:** die Codeblöcke sind Tests; die Spezifikation hat 80 Zeilen, die Interfaces fassen die Entscheidungen.
