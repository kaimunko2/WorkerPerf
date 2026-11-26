# Schreibcache von MCS, Stufe 1: Prüfschritt – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Das Prüfskript zeigt auf einem Server, ob und wo die Überlaufdatei des Schreibcaches von MCS liegt, wie voll ihr Laufwerk ist und welche Leistungsindikatoren „Citrix MCS…“ es gibt – als Grundlage für Stufe 2.

**Architecture:** Eine neue Prüfung `mcs.cache` im Katalog von `src/Test-WorkerPerfSources.ps1`. Das Lesen (Laufwerke, Kategorien) ist von der Auswertung getrennt: die Auswertung ist eine reine Funktion über nachgestellte Eingaben und unter Linux testbar. Die Ausgabe läuft wie jede andere durch die Maskierung des Skripts.

**Tech Stack:** Windows PowerShell 5.1 (Laufzeit, `System.IO.DriveInfo`, `System.Diagnostics.PerformanceCounterCategory`). Tests: PowerShell 7 mit Pester 5.

**Spec:** `docs/superpowers/specs/2026-11-26-schreibcache-design.md`, Abschnitt „Stufe 1“ (bindend).

## Global Constraints

- **Nur lesen:** die Prüfung öffnet die Datei nicht und schreibt nichts; sie liest Verzeichniseintrag (Größe) und Laufwerksdaten.
- **Dateiname:** `mcsdif.vhdx`, gesucht im Stammverzeichnis jedes Laufwerks mit `DriveType` `Fixed`, das bereit ist (`IsReady`).
- **Kategorien:** jede Kategorie von Leistungsindikatoren, deren Name mit `Citrix MCS` beginnt (ohne Beachtung der Groß- und Kleinschreibung); der Plan nennt keinen Indikatornamen fest.
- **Nichts gefunden ist kein Fehler:** die Prüfung endet ohne Ausnahme mit `Ok = $false` und einem Satz, was fehlt; das Skript läuft weiter.
- **Ein Lesefehler** (Zugriff verweigert auf die Datei, Kategorie nicht lesbar) kostet nur den betroffenen Wert; der Fehlertext steht im Ergebnis.
- **Keine Namen:** im Ergebnis stehen Laufwerksbuchstabe, Zahlen, Kategorie- und Indikatornamen; Instanznamen laufen durch `Hide-ProbeText`.
- **Windows PowerShell 5.1**, `src/*.ps1` reines ASCII; Texte des Skripts deutsch ohne Umlaute, wie die bestehenden.
- **Tests gezielt:** `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Sources.Tests.ps1`, dazu `tests/Compat.Tests.ps1`.
- **Commit:** englisch, im Imperativ, mit den Attributionszeilen der Sitzung.

## Review Focus

1. **Server ohne MCS I/O** (keine Datei, keine Kategorie): `Ok = $false`, Detail nennt beides als nicht gefunden, kein Abbruch.
2. **Datei da, ihre Größe nicht lesbar** (gesperrt): Laufwerk und freier Platz stehen trotzdem im Ergebnis, die Größe ist `$null`, der Fehlertext steht dabei.
3. **Zwei Laufwerke mit der Datei:** beide stehen im Ergebnis, nicht nur das erste.
4. **Kategorie mit Instanzen und ohne** (einzelne Werte / je Instanz): beide Formen werden gelistet; höchstens 8 Instanzen je Kategorie.
5. **Indikator, dessen Wert nicht lesbar ist:** Name steht da, Wert `$null`; die übrigen Werte bleiben.

---

### Task 1: Prüfung `mcs.cache`

**Files:**
- Modify: `src/Test-WorkerPerfSources.ps1` (neue Funktionen bei den anderen `Invoke-Probe…Check`; ein Eintrag im Katalog der Prüfungen nach `perf.volumes`)
- Modify: `README.md` (Abschnitt zum Prüfskript: eine Zeile zur neuen Prüfung)
- Test: `tests/Sources.Tests.ps1` (neues Describe „Schreibcache von MCS im Pruefskript“; die Funktionsnamen in die Liste der geladenen Funktionen am Dateianfang aufnehmen)

**Interfaces:**
- Produces:
  - `Get-ProbeMcsCacheResult([object[]]$Drives, [object[]]$Categories)` → `@{ Ok; Detail; Data }`. Reine Funktion.
    - `$Drives`: je Laufwerk `@{ Drive = 'D:'; TotalMb; FreeMb; HasFile = [bool]; FileMb (oder $null); FileError = '' }`.
    - `$Categories`: je Kategorie `@{ Category; Error = ''; Counters = @(@{ Counter; Instance (''' ohne Instanz); Value (oder $null) }) }`.
    - `Ok` = mindestens ein Laufwerk mit `HasFile`. `Data` = `[ordered]@{ CacheDrives = <Laufwerke mit Datei, je mit FreePct>; Categories = $Categories }`.
    - `Detail`: `'mcsdif.vhdx auf D: ({0} MB), frei {1} von {2} MB; {3} Kategorien Citrix MCS'` je Laufwerk mit Datei, sonst `'mcsdif.vhdx nicht gefunden; {0} Kategorien Citrix MCS'`.
  - `Read-ProbeMcsDrives` → `$Drives` (liest `[System.IO.DriveInfo]::GetDrives()`), `Read-ProbeMcsCategories` → `$Categories` (liest `[System.Diagnostics.PerformanceCounterCategory]::GetCategories()`, Rohwerte über `NextValue()` ohne Wartezeit).
  - `Invoke-ProbeMcsCacheCheck($Ctx, $Check)` → ruft die beiden Leser und `Get-ProbeMcsCacheResult`.
  - Katalogeintrag: `@{ Id = 'mcs.cache'; Signals = @(); Title = 'Schreibcache von MCS (Ueberlaufdatei und Indikatoren)'; Run = 'Invoke-ProbeMcsCacheCheck' }`.

- [ ] **Step 1: Die fehlschlagenden Tests schreiben**

```powershell
Describe 'Schreibcache von MCS im Pruefskript' {
    BeforeAll {
        $drive = { param($Letter, $Has, $FileMb, $Err = '') @{ Drive = $Letter; TotalMb = 40000; FreeMb = 10000; HasFile = $Has; FileMb = $FileMb; FileError = $Err } }
        $cat = @{ Category = 'Citrix MCS Storage Driver'; Error = ''; Counters = @(@{ Counter = 'X'; Instance = ''; Value = 12.0 }, @{ Counter = 'Y'; Instance = ''; Value = $null }) }
    }
    It 'meldet einen Server ohne MCS I/O ohne Fehler' {                                           # Review Focus 1
        $r = Get-ProbeMcsCacheResult @((& $drive 'C:' $false $null)) @()
        $r.Ok | Should -BeFalse; $r.Detail | Should -Be 'mcsdif.vhdx nicht gefunden; 0 Kategorien Citrix MCS'; @($r.Data.CacheDrives).Count | Should -Be 0
    }
    It 'nennt Laufwerk, Dateigroesse und freien Platz' {
        $r = Get-ProbeMcsCacheResult @((& $drive 'C:' $false $null), (& $drive 'D:' $true 2048)) @($cat)
        $r.Ok | Should -BeTrue; $r.Detail | Should -Be 'mcsdif.vhdx auf D: (2048 MB), frei 10000 von 40000 MB; 1 Kategorien Citrix MCS'
        $r.Data.CacheDrives[0].FreePct | Should -Be 25
    }
    It 'behaelt Laufwerk und freien Platz, wenn die Dateigroesse nicht lesbar ist' {              # Review Focus 2
        $r = Get-ProbeMcsCacheResult @((& $drive 'D:' $true $null 'Zugriff verweigert')) @()
        $r.Ok | Should -BeTrue; $r.Data.CacheDrives[0].FileMb | Should -BeNullOrEmpty; $r.Data.CacheDrives[0].FileError | Should -Be 'Zugriff verweigert'
        $r.Detail | Should -BeLike 'mcsdif.vhdx auf D: (Groesse nicht lesbar), frei 10000 von 40000 MB*'
    }
    It 'nennt jedes Laufwerk mit der Datei' {                                                     # Review Focus 3
        @((Get-ProbeMcsCacheResult @((& $drive 'D:' $true 1), (& $drive 'E:' $true 2)) @()).Data.CacheDrives).Count | Should -Be 2
    }
    It 'gibt Kategorien mit lesbaren und unlesbaren Werten unveraendert weiter' {                 # Review Focus 4, 5
        $r = Get-ProbeMcsCacheResult @() @($cat)
        $r.Ok | Should -BeFalse; $r.Data.Categories[0].Counters[1].Value | Should -BeNullOrEmpty; $r.Data.Categories[0].Counters[0].Value | Should -Be 12.0
    }
    It 'steht im Katalog der Pruefungen und laeuft ohne Windows nicht in einen Abbruch' {
        (Get-Content (Join-Path $PSScriptRoot '../src/Test-WorkerPerfSources.ps1') -Raw) | Should -Match "Id = 'mcs\.cache'"
    }
}
```

Die Begrenzung auf 8 Instanzen je Kategorie und das Maskieren der Instanznamen liegen in `Read-ProbeMcsCategories`; dafür ein Test mit einer nachgestellten Kategorie, wenn der Leser die Kategorie-Objekte als Parameter nimmt (`Read-ProbeMcsCategories([object[]]$All = $null)`), sonst bleibt es eine Zeile im Review.

- [ ] **Step 2: Tests ausführen und Fehlschlag sehen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Sources.Tests.ps1`
Expected: FAIL – `Get-ProbeMcsCacheResult` ist nicht bekannt

- [ ] **Step 3: Die vier Funktionen und den Katalogeintrag umsetzen** (Signaturen und Texte aus „Interfaces“; Leser fangen Fehler je Laufwerk, je Kategorie und je Indikator ab)

- [ ] **Step 4: Tests ausführen**

Run: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/Sources.Tests.ps1`, danach `… -Path tests/Compat.Tests.ps1`
Expected: `Failed: 0` in beiden

- [ ] **Step 5: README ergänzen und Commit**

README, Abschnitt zum Prüfskript: die Prüfung `mcs.cache` zeigt Überlaufdatei, freien Platz und die Indikatoren „Citrix MCS…“; auf Servern ohne MCS I/O steht „nicht gefunden“.

```bash
git add src/Test-WorkerPerfSources.ps1 tests/Sources.Tests.ps1 README.md
git commit -m "Probe the MCS write cache file and counters in the source check"
```

## Danach

Der Benutzer lässt `Test-WorkerPerfSources.ps1` auf einem Server mit MCS I/O laufen und gibt den Abschnitt `mcs.cache` der Ausgabe zurück. Damit werden die offenen Punkte des Entwurfs geschlossen und der Plan für Stufe 2 geschrieben.
