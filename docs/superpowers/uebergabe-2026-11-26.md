# Übergabe an die nächste Sitzung (Stand 26.11.2026)

Diese Datei ersetzt die Historie der bisherigen Sitzung. Die lokalen Arbeitsordner unter `.superpowers/` sind nicht im
Repository und fehlen in einer neuen Sitzung. Alles Nötige steht hier, im Plan und im Entwurf.

## 1. Stand

- Branch `claude/funny-albattani-se6v8z` und `main` stehen beide auf `bfaab24`.
- **Fertig und auf main:**
  - Engpassanalyse, Ereignisse/Abstürze/Drucken, Maskierung, geführter Bericht, Messkategorien (`-Skip`) und Zustandsbild;
  - Korrekturen aus den echten Läufen 1–3: Speicher-Fehlalarme, Zuordnung der Sitzungen, weniger Last durch den
    Collector, Stufen der Eingabeverzögerung, klarere Texte des Zustandsbilds.
- **Pausiert:** Baustein „Größe des Servers“. Weiter erst, wenn der Benutzer ausdrücklich „weiter“ sagt.
  - Entwurf: `docs/superpowers/specs/2026-11-14-servergroesse-design.md` (freigegeben am 14.11.)
  - Plan: `docs/superpowers/plans/2026-11-14-servergroesse.md` (13 Tasks, freigegeben am 14.11.)
  - Der Plan wurde gegen `fabf520` geschrieben. Bis `bfaab24` haben sich 21 Dateien geändert. Vor Task 1 prüfen, ob
    Literale im Plan (Zählwerte in Tests, Funktionsnamen) noch stimmen, und Abweichungen als Entscheidung festhalten.
  - Noch keine Task umgesetzt. Die Vorabprüfung des Plans wurde nie fertig (Ausgabelimit).

## 2. Punkte aus Lauf 3 (1–3 am 26.11. freigegeben: vor dem Baustein umsetzen)

1. **Präfix in `operation.pendingRenameTop`.**
   - Einträge der Liste PendingFileRenameOperations beginnen mit `*1` vor `\??\`.
   - `Format-WorkerPerfPendingRenameTop` (`src/WorkerPerf.Sources.Windows.ps1`) entfernt es nicht. Die Anzeige lautet dann `*1\??\C:\Windows (152)`.
2. **Dauerhafter Speichermangel als ein Vorfall.**
   - Bei anhaltendem Druck zerfällt er heute in viele kurze kritische Vorfälle (im echten 3-h-Lauf 79).
   - Ziel: ein zusammenhängender, „chronischer“ Vorfall.
3. **Burst begrenzen, solange ein Auslöser dauerhaft hoch bleibt.**
   - Im 3-h-Lauf war der Burst-Modus in 54 % der Takte aktiv.
   - Die Last durch die Messung stieg dabei auf etwa 3 %.
4. Später, nicht dringend:
   - Obergrenze für die Ereignisabfrage;
   - Zwischenspeicher für Stammdaten der Prozesse (Win32_Process).

## 3. Arbeitsweise (Ergebnis der Kostendiagnose vom 26.11.)

Die bisherige Sitzung kostete etwa 3 350 USD. Die Treiber waren:
- eine einzige Sitzung über 16 Tage mit Kontexten von 470 k bis 900 k Tokens;
- je Task Umsetzer, Prüfer, Nachprüfer, Abschlussprüfung und Korrekturwellen;
- 171 komplette Testläufe.

Ab jetzt gilt:

- **Eine Sitzung je Baustein.** Am Ende wird diese Übergabedatei aktualisiert und eingecheckt.
- **Plan selbst abarbeiten** (`superpowers:executing-plans`, Ausführung „Native“), ohne Umsetzer-Unteragent je Task.
- **Prüfung:**
  - Am Ende eines Plans prüft genau ein Reviewer den ganzen Branch, auf dem stärksten verfügbaren Modell.
  - Danach gibt es eine Korrekturrunde, nur für wichtige Befunde. Kleinigkeiten werden gesammelt und dem Benutzer genannt.
- **Unteragenten** nur, wenn sie wirklich parallel nützen. Ein Workflow hat höchstens 5 Agenten. Umsetzer und Prüfer laufen auf dem mittleren Modell.
- **Tests gezielt:**
  - nur die betroffenen Pester-Dateien: `pwsh -NoProfile -File tests/Invoke-Tests.ps1 -Path tests/X.Tests.ps1`;
  - nur die betroffenen Browser-Prüfungen: `node tests/report-browser.js <dir> --scheme light --only <Funktionen>`;
  - die komplette Suite nur einmal, vor dem Wechsel auf main.
- **Screenshots** nur auf Wunsch, mit `deviceScaleFactor: 1`.
- **Große Ausgaben** (Testprotokolle, Diffs, Berichte) in Dateien umleiten. Daraus nur die nötigen Zeilen lesen.

## 4. Feste Regeln

- **Sprache:** Antworten auf Deutsch, kurz und einfach. Der Benutzer arbeitet in der iOS-App.
- **Statusübersicht:** Jede Antwort endet mit einem Codeblock.
  - Er zeigt den Gesamtstatus der Pläne und Tasks als Balken mit ✔/⏳/○/⏸/⚠ und die geschätzte Restzeit.
  - Längere Erklärtexte entfallen.
- **Git:**
  - Entwickeln und pushen auf `claude/funny-albattani-se6v8z`.
  - Auf `main` nur nach ausdrücklichem OK des Benutzers für genau diesen Stand.
  - Kein Pull Request ohne Auftrag.
- **Commits:** englisch, im Imperativ. Sie enden mit den Zeilen, die die Sitzung als Attribution vorgibt. Kein Modellname in Code, Kommentaren oder Dokumenten.
- **Öffentliches Repository:**
  - keine echten Server-, Kunden-, Benutzer- oder Freigabenamen;
  - echte Aufzeichnungen nur im Scratchpad, nie im Repository;
  - erlaubt sind die Produktnamen in `src/roles.json` und PrinTaurus;
  - die E-Mail des Benutzers wird nie an externe Dienste gegeben.
- **Wortregel:** Die gemessene Maschine heißt „Server“. „Host“ steht nur als „VMware-Host“ oder „Virtualisierungshost“.
- **Technik:**
  - Ziel ist Windows PowerShell 5.1, `src/*.ps1` reines ASCII.
  - Tests laufen unter Linux mit PowerShell 7 und Pester 5, die Browser-Prüfungen mit Node/Playwright.
  - Die weiteren Global Constraints stehen im Plan.
