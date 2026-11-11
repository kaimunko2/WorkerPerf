# Quellen-Prüfskript für den VDA

`Test-WorkerPerfSources.ps1` prüft auf einem Citrix-Worker, welche Datenquellen WorkerPerf dort nutzen kann: Leistungsindikatoren, Sitzungen, Prozesse, Dienste, Profilcontainer, Ereignisprotokolle und die Erreichbarkeit von Gegenstellen.
Das Ergebnis entscheidet, welche Zählernamen und Berechnungen die Aufzeichnung verwendet; das Skript liest nur und ändert nichts am System.

## Aufruf

1. `Test-WorkerPerfSources.ps1` als einzelne Datei auf den Worker kopieren, z. B. nach `C:\Temp`.
2. Eine PowerShell-Konsole **mit erhöhten Rechten** („Als Administrator ausführen“) öffnen und ausführen:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-WorkerPerfSources.ps1 -OutFile C:\Temp
   ```

3. **Während das Skript läuft**, etwa 40 Sekunden lang in einer Benutzersitzung auf dem Worker tippen oder Fenster bewegen. Nur so liefert die Messung der Eingabeverzögerung aussagekräftige Werte. Das Skript meldet sich mit „Bitte jetzt in einer Benutzersitzung tippen …“, sobald dieser Teil beginnt.

Der gesamte Lauf dauert zwei bis drei Minuten, auf einem ausgelasteten Worker auch länger: 40 Sekunden entfallen auf die Eingabeverzögerung, je eine Sekunde auf elf Zählergruppen, dazu kommen drei Prozessabfragen, die Liste der Leistungsklassen und die Ereignisprotokolle. Jede einzelne Systemabfrage endet spätestens nach 30 Sekunden; aus den Ereignisprotokollen der letzten sieben Tage werden je Protokoll höchstens 1.000 Einträge gezählt. Am Ende zeigt die Konsole eine Tabelle mit allen Prüfungen und den Pfad der Ergebnisdatei `vda-probe_<Datum-Uhrzeit>.json`.

### AppLocker und eingeschränkter Sprachmodus

Das Skript braucht den PowerShell-Sprachmodus `FullLanguage`. Wo AppLocker oder WDAC eine Konsole in den Modus `ConstrainedLanguage` versetzt, bricht es gleich zu Beginn mit einer Meldung ab, die den aktiven Modus nennt, statt später an unverständlichen Fehlern zu scheitern. Abhilfe: eine uneingeschränkte administrative Konsole verwenden (unter den AppLocker-Standardregeln ist das die Konsole „Als Administrator ausführen“) oder das Skript an einem Ort ablegen, den die Skriptregeln zulassen. Welcher Modus aktiv ist, zeigt `$ExecutionContext.SessionState.LanguageMode`. Dieselbe Prüfung machen später auch die Aufzeichnung und die Auswertung.

## Optional: Gegenstellen prüfen

Mit `-EndpointFile` misst das Skript zusätzlich die Dauer des TCP-Verbindungsaufbaus zu benannten Gegenstellen (Zeitlimit 2 s). Die Datei wird nach dem Muster von `endpoints.example.json` angelegt:

```json
{
  "endpoints": [
    { "name": "Oracle-Listener", "host": "ora-db.example.local", "port": 1521, "role": "Datenbank" }
  ]
}
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-WorkerPerfSources.ps1 -OutFile C:\Temp -EndpointFile C:\Temp\endpoints.json
```

Im Ergebnis steht je Gegenstelle nur ihre Position in der Datei, die Bezeichnung (`name`), die Rolle, der Port und die gemessene Zeit, bei einem Fehler eine Klasse: `dns` (Name nicht auflösbar), `refused` (Verbindung abgelehnt), `timeout` (keine Antwort in 2 s) oder `other`. Hostnamen und Adressen werden nicht ausgegeben; die Bezeichnung sollte deshalb selbst keinen Servernamen enthalten.

Ohne `-EndpointFile` steht die Prüfung der Gegenstellen in der Tabelle mit dem Status „uebersprungen“: Es wurde keine `endpoints.json` übergeben, ein Fehler ist das nicht.

## Weitere Parameter

| Parameter | Bedeutung |
|---|---|
| `-OutFile` | Ordner oder `.json`-Datei für das Ergebnis; Standard ist der aktuelle Ordner |
| `-InputSeconds` | Anzahl der Proben im Abstand 1 s für die Eingabeverzögerung (Standard 20); danach folgen halb so viele im Abstand 2 s |
| `-ListChecks` | listet nur die Prüfungen auf, ohne das System abzufragen |

## Ergebnis zurückgeben

Die JSON-Datei enthält keine Namen, auch nicht den des Workers (weder im Dateinamen noch im Inhalt; mehrere Worker lassen sich am Zeitstempel der Datei unterscheiden). In allen Texten werden ersetzt:

| Name | Ersatz | Quelle der Namen |
|---|---|---|
| Benutzernamen | `<user>` | Sitzungen (WTS), Ordner der Benutzerprofile, angemeldeter Benutzer |
| Domänennamen | `<domain>` | Domäne jeder Sitzung, `USERDOMAIN`, `USERDNSDOMAIN`, Zusatz an Profilordnern; neben einem Benutzernamen auch unbekannte (`<user>.<domain>`, `<domain>\<user>`, `<user>@<domain>`) |
| Clientnamen | `<client>` | Clientname jeder Sitzung |
| Name des Workers | `<server>` | Computername und Hostname |
| Servernamen in UNC-Pfaden | `<server>` | jeder Pfad der Form `\\server\…` |

Hostnamen und Adressen der Gegenstellen werden nicht ausgegeben. Vor dem Schreiben läuft die Ersetzung noch einmal über jeden Text des Ergebnisses. Bitte die Datei zur Auswertung zurückgeben; sie kann in diesem Ordner (`docs/vda-probe/`) abgelegt werden.

Das Skript schreibt keine Datei und bricht mit einer Meldung ab, wenn es die Benutzernamen nicht vollständig ermitteln kann: wenn weder die WTS-Schnittstelle noch die Benutzerprofile lesbar sind, oder wenn eine aktive Sitzung keinen Benutzernamen liefert und die Benutzerprofile als zweite Quelle fehlen. Ohne die Namen könnte es sie nicht maskieren.
