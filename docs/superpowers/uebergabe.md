# Übergabe an die nächste Sitzung (Stand 26.11.2026, nach dem Baustein „Größe des Servers“)

Diese Datei ersetzt die Historie der bisherigen Sitzung. Die lokalen Arbeitsordner unter `.superpowers/` sind nicht im
Repository und fehlen in einer neuen Sitzung. Alles Nötige steht hier, im Plan und im Entwurf.

## 1. Stand

- Entwicklungsbranch dieser Sitzung: `claude/eloquent-cori-yzz28w` (ausgehend von `bfaab24`). `main` steht weiter auf
  `bfaab24`; auf `main` geht es erst nach dem OK des Benutzers.
- **Fertig auf dem Entwicklungsbranch (26.11.2026):**
  - die Punkte 1–3 aus Lauf 3 (Präfix `*1`, Speichermangel als ein chronischer Vorfall, Burst begrenzt);
  - der Baustein „Größe des Servers“, Tasks 1–12 des Plans `docs/superpowers/plans/2026-11-14-servergroesse.md`:
    Katalog `src/sizing.de.json`, fünf neue Messwerte, Einordnung je Vorfall im normalen Bericht, Größenbericht
    `src/New-WorkerPerfSizingReport.ps1` mit eigener Seite, Prüfskript, README, Demo-Seiten;
  - eine Gesamtprüfung durch einen Reviewer und eine Korrekturrunde (sieben Befunde behoben).
- **Offen:** Task 13 des Plans, der erste echte Lauf auf dem Test-Server (Schritt des Benutzers). Er klärt die offenen
  Punkte aus Abschnitt 10 des Entwurfs: Instanznamen von „Processor Information“, Werte von `% Processor Performance`
  und `% Processor Utility` in der VMware-VM, Laufzeit des Lesens bei vielen vCPUs.

## 2. Offene Punkte

Regeln, die von Plan oder Entwurf abweichen (Entscheidungen dieser Sitzung; am echten Lauf zu prüfen):

- **Speichermangel:** Befunde desselben Speichersignals mit Lücken bis 5 Minuten bilden eine Kette; länger als
  15 Minuten und in mindestens der Hälfte der Zeit über der Schwelle wird daraus ein chronischer Vorfall.
- **Burst:** ein Auslöser wird erst wieder scharf, wenn er 5 Minuten lang keinen bestätigten schlechten Takt hatte.
- **VMware-Host:** entzogene CPU-Zeit zählt für einen Vorfall ab drei Takten **und** 10 % seiner Takte (`hostSharePct`).
- **Leistung je Kern** wird bei breiter Last über dem Ziel nicht gefragt; dann gilt „Kapazität“.
- **Größenwechsel:** Last und Hochrechnung stammen nur aus den Aufzeichnungen mit der letzten Größe.
- Das Satzfeld der Einordnung heißt in den Berichtsdaten `advice` (`direction` ist ein Schlüsselwortfeld).
- Die zwei Schritte der Einordnung stehen am Ende von `checks` in `guidance.de.json` und werden durch die Reihungsregel
  nach vorn gestellt (sonst verschieben sich die Indexverweise in `docs/guidance/quellen.md`).

Kleinigkeiten, gesammelt und nicht umgesetzt:

- Reihung der Anleitung (P3-R75) bei Vorfällen, die es vorher in keinem Testbericht gab: bei einem CPU-Vorfall durch
  einen Scan und bei einem Speicher-Vorfall steht je ein Element einer Praxisquelle vor einem Herstellerschritt.
- Ein kurzer kritischer Commit-Befund innerhalb eines chronischen RAM-Zustands bildet keinen eigenen Vorfall mehr.
- Belege im Größenbericht zeigen Rohwerte (`highPerformance`, `True`).
- Mit ein oder zwei Aufzeichnungen ist jeder Vorfall „wiederkehrend“; die Begründung der CPU nennt auch Speicherklassen.
- Der Collector braucht auch für den Schnelllauf einen gültigen Katalog `sizing.de.json`.
- Ein Katalog mit genau einer Annahme wird abgelehnt.
- Stufe „deutlich“ der Kapazität zählt verstreute Takte; zwei Schleifen in `tests/Sizing.Tests.ps1` können leer laufen.
- Weiter offen aus Lauf 3: Obergrenze für die Ereignisabfrage; Zwischenspeicher für Stammdaten der Prozesse.
- `src/*.html`-Vorlagen und Demo-Seiten brauchen eine Ausnahme in `.gitignore` (Regel `*.html`).

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
  - Entwickeln und pushen auf dem Branch, den die Sitzung vorgibt (zuletzt `claude/eloquent-cori-yzz28w`).
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
