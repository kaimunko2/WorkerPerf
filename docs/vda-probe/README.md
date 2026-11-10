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

Der gesamte Lauf dauert etwa eine Minute. Am Ende zeigt die Konsole eine Tabelle mit allen Prüfungen und den Pfad der Ergebnisdatei `WorkerPerf-Quellen_<COMPUTER>_<Datum-Uhrzeit>.json`.

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

## Weitere Parameter

| Parameter | Bedeutung |
|---|---|
| `-OutFile` | Ordner oder `.json`-Datei für das Ergebnis; Standard ist der aktuelle Ordner |
| `-InputSeconds` | Anzahl der Proben im Abstand 1 s für die Eingabeverzögerung (Standard 20); danach folgen halb so viele im Abstand 2 s |
| `-ListChecks` | listet nur die Prüfungen auf, ohne das System abzufragen |

## Ergebnis zurückgeben

Die JSON-Datei enthält außer dem Computernamen keine Namen: Benutzernamen werden durch `<user>`, Servernamen in UNC-Pfaden durch `<server>` ersetzt, Hostnamen der Gegenstellen werden nicht ausgegeben. Bitte die Datei zur Auswertung zurückgeben.
