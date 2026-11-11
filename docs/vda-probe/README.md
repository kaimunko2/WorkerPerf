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

Der gesamte Lauf dauert einige Minuten; auf einem Windows-Server ist er noch nicht gemessen, zu rechnen ist mit zwei bis fünf Minuten: 40 Sekunden entfallen auf die Eingabeverzögerung, je eine Sekunde auf elf Zählergruppen, dazu kommen drei Prozessabfragen, die Liste der Leistungsklassen und die Ereignisprotokolle. Jede CIM-Abfrage endet spätestens nach 30 Sekunden; für das Lesen der Leistungsindikatoren, der Ereignisprotokolle und der Sitzungen gibt es kein Zeitlimit. Aus den Ereignisprotokollen der letzten sieben Tage werden je Protokoll höchstens 1.000 Einträge gezählt.

Nach der letzten Prüfung meldet die Konsole „Namen werden erneut gelesen, das Ergebnis wird maskiert und geschrieben ...“. Das dauert noch einige Sekunden; bitte in dieser Zeit nicht abbrechen. Danach zeigt die Konsole eine Tabelle mit allen Prüfungen und den Pfad der Ergebnisdatei `vda-probe_<Datum-Uhrzeit>.json`.

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

In der JSON-Datei sind Namen maskiert, auch der des Workers (er steht weder im Dateinamen noch im Inhalt; mehrere Worker lassen sich am Zeitstempel der Datei unterscheiden). In allen Texten werden ersetzt:

| Name | Ersatz | Woran das Skript ihn erkennt |
|---|---|---|
| Benutzernamen | `<user>` | Sitzungen (WTS), Ordner der Benutzerprofile, angemeldeter Benutzer; außerdem ohne Liste der Name neben einer Konten-SID (`<sid>_name`, `name_<sid>`) und in Containerdateien (`Profile_name.vhdx`, `ODFC_name.vhdx`) |
| Domänennamen | `<domain>` | Domäne jeder Sitzung, `USERDOMAIN`, `USERDNSDOMAIN`, Zusatz an Profilordnern, DNS-Anteil eines Servernamens; neben einem Benutzernamen auch unbekannte (`<user>.<domain>`, `<domain>\<user>`, `<user>@<domain>`) |
| Clientnamen | `<client>` | Clientname jeder Sitzung |
| Name des Workers | `<server>` | Computername und Hostname |
| Servernamen | `<server>` | jeder Pfad der Form `\\server\…`, `\\?\UNC\server\…`, `\??\UNC\server\…`, `\Device\Mup\server\…` oder `\Device\LanmanRedirector\…\server\…`; die so gefundenen Server, die Server der SMB-Freigaben und die Hosts der Datei für `-EndpointFile` werden auch in freiem Text ersetzt |
| Konten-SIDs | `<sid>` | Muster `S-1-5-21-…` (Domänenkonten) und `S-1-12-1-…` (Entra-ID-Konten); bekannte SIDs wie `S-1-5-18` bleiben stehen |

Die Prüfungen behalten ihre Texte zunächst unverändert; maskiert wird das Ergebnis einmal als Ganzes, nach der letzten Prüfung und mit allen Namen, die bis dahin bekannt sind. Sitzungen kommen und gehen, während das Skript läuft: Es liest sie deshalb beim Start, nach jeder Prüfung und vor dem Maskieren noch einmal, die Profilordner beim Start und vor dem Maskieren. Wer sich während des Laufs anmeldet, wird so ebenfalls maskiert. Eine Lücke bleibt: Wer sich innerhalb einer einzelnen Prüfung an- und wieder abmeldet (die längste dauert 40 Sekunden) und dessen Profilordner beim Abmelden gelöscht wird, steht in keiner Liste; für ihn greifen nur die festen Muster der Tabelle. Hostnamen und Adressen der Gegenstellen werden nicht ausgegeben.

Das Skript schreibt keine Datei und bricht mit einer Meldung ab,

- wenn weder die WTS-Schnittstelle noch die Benutzerprofile lesbar sind, oder
- wenn eine aktive Sitzung keinen Benutzernamen liefert, beim Start oder beim erneuten Lesen vor dem Maskieren. Das geschieht vor allem in einer Konsole ohne erhöhte Rechte; dann das Skript in einer administrativen Konsole erneut starten.

Ohne die Namen könnte es sie nicht maskieren.

### Vor der Weitergabe durchsehen

Die Maskierung ersetzt die Namen, die das Skript aus seinen Quellen kennt, und die festen Muster der Tabelle. **Nicht erkennen kann sie:**

- Servernamen oder IP-Adressen in freiem Text, wenn derselbe Server im Ergebnis in keinem UNC-Pfad vorkommt,
- UNC-Pfade in anderer Schreibweise (`//server/freigabe`, `file://server/…`),
- Anzeigenamen von Personen („Müller, Hans“),
- einen Benutzernamen, der ohne Unterstrich an einer SID hängt oder in einem Ordnernamen anderer Bauart steht, solange der Benutzer in keiner Liste ist,
- Firmen- oder Organisationsnamen in den Angaben zu Diensten, Prozessen und Herstellern,
- Namen in einer Bezeichnung, die Sie selbst in der Datei für `-EndpointFile` vergeben haben.

Bitte die Datei deshalb vor der Weitergabe und vor dem Einchecken in einem Editor durchsehen und nach bekannten Benutzer- und Servernamen sowie nach `S-1-5-21-` suchen. Findet sich nichts, kann die Datei zur Auswertung zurückgegeben und in diesem Ordner (`docs/vda-probe/`) abgelegt werden. Findet sich doch ein Name, bitte die Stelle mit zurückmelden: Dann fehlt dem Skript eine Regel.

Das Skript ist bisher nur mit nachgestellten Quellen getestet; auf einem Windows-Server ist es noch nicht gelaufen.
