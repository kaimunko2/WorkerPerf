# Quellen-Prüfskript für den VDA

`Test-WorkerPerfSources.ps1` prüft auf einem Citrix-Server, welche Datenquellen WorkerPerf dort nutzen kann: Leistungsindikatoren, Sitzungen, Prozesse, Dienste, Profilcontainer, Ereignisprotokolle, Druckertreiber und Druckwarteschlangen und die Erreichbarkeit von Gegenstellen.
Das Ergebnis entscheidet, welche Zählernamen und Berechnungen die Aufzeichnung verwendet; das Skript liest nur und ändert nichts am System.

## Aufruf

1. `Test-WorkerPerfSources.ps1` als einzelne Datei auf den Server kopieren, z. B. nach `C:\Temp`.
2. Eine PowerShell-Konsole **mit erhöhten Rechten** („Als Administrator ausführen“) öffnen und ausführen:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-WorkerPerfSources.ps1 -OutFile C:\Temp
   ```

3. **Während das Skript läuft**, etwa 40 Sekunden lang in einer Benutzersitzung auf dem Server tippen oder Fenster bewegen. Nur so liefert die Messung der Eingabeverzögerung aussagekräftige Werte. Das Skript meldet sich mit „Bitte jetzt in einer Benutzersitzung tippen …“, sobald dieser Teil beginnt.

Der gesamte Lauf dauert einige Minuten; geschätzt sind zwei bis sechs Minuten. Auf einem Windows-Server gemessen ist der Lauf mit den Prüfungen der Ereignisse und des Druckens noch nicht. 40 Sekunden entfallen auf die Eingabeverzögerung, je eine Sekunde auf zwölf Zählergruppen, dazu kommen drei Prozessabfragen, die Liste der Leistungsklassen, die Druckertreiber und die Ereignisprotokolle. Aus jedem Ereignisprotokoll werden von den Ereignissen der letzten sieben Tage höchstens 1.000 gelesen, ohne Meldungstexte; das Muster `Citrix*` wird einmal je Lauf aufgelöst. Die Protokolle brauchen trotzdem die meiste Zeit nach der Eingabeverzögerung: Eine Abfrage mit wenigen Treffern durchsucht das ganze Protokoll, und das Anwendungs- und das Systemprotokoll werden, wenn viele Citrix-Quellen hineinschreiben, in mehreren Abfragen gelesen. Auf einem großen Protokoll ist mit bis zu etwa einer Minute je Protokoll zu rechnen. Während des Lesens zeigt die Konsole je Protokoll eine Zeile mit seinem Namen und der Zahl der bisher gelesenen Ereignisse; solange sie weiterzählt oder neue Zeilen erscheinen, bitte nicht abbrechen. Jede CIM-Abfrage endet spätestens nach 30 Sekunden; für das Lesen der Leistungsindikatoren, der Ereignisprotokolle, der Registrierung und der Sitzungen gibt es kein Zeitlimit.

### Ereignisse und Drucken

Für die spätere Aufzeichnung von Abstürzen, Dienst-, Datenträger-, Profil-, SMB- und Druckfehlern und von Sitzungsereignissen zählt das Skript in den Protokollen Anwendung, System, Druckdienst (Admin, Operational), SMB-Client (Connectivity, Operational), Benutzerprofildienst und Sitzungsverwaltung der Terminaldienste, dazu wie bisher Defender und AppLocker, die Ereignisse der letzten sieben Tage: je Protokoll, ob es vorhanden, eingeschaltet und lesbar ist, und je Quelle und Kennung die Anzahl und die **Namen** der Datenfelder des neuesten Ereignisses. Meldungstexte und Feldwerte werden nicht ausgegeben. Ein Protokoll, das fehlt oder abgeschaltet ist, wird gemeldet und nicht eingeschaltet. Von den Quellen, die über das Muster `Citrix*` gefunden werden, liest das Skript nur die, die in das jeweilige Protokoll schreiben und deren Meldungs- oder Ressourcendatei im Ordner `Citrix` direkt unter den Programmordnern liegt (`%ProgramFiles%\Citrix\` oder `%ProgramFiles(x86)%\Citrix\`). Alle anderen werden nur gezählt (`ProvidersDropped`, `ProvidersNotLinked`), nicht abgefragt und nicht genannt: Eine Quelle, die vor Ort angelegt wurde, kann den Namen der Einrichtung tragen. Dabei geht auch eine echte Citrix-Quelle verloren, deren Meldungsdatei woanders liegt. Die Quellen, die das Skript fest mit Namen kennt, sind davon nicht berührt. Ein Datensatz, der sich nicht lesen lässt, wird gezählt (`RecordErrors`) und übersprungen; die übrigen Ereignisse des Protokolls bleiben erhalten. Die Obergrenze von 1.000 gilt je Protokoll über alle Abfragen nacheinander: `Chunks` nennt die Zahl der Abfragen, `ChunksNotRead` die, die wegen der Obergrenze nicht mehr gelesen wurden, und `OldestUtc` die Zeit des ältesten gelesenen Ereignisses, also bis wann die Zahlen zurückreichen.

Bei den Druckertreibern zählt es Treiber je Hersteller, Bauart (Typ 3 oder 4) und Isolierung (laut `PrintDriverIsolationGroups`), liest die Richtlinien `PrintDriverIsolationExecutionPolicy` und `PrintDriverIsolationOverrideCompat` als Zahl und zählt, wie viele Treiber welches Bit von `PrinterDriverAttributes` tragen, darunter „mit Isolierung verträglich“ (`0x4`). Daraus und aus den Gruppen und Richtlinien zählt es je Treiber die wirksame Betriebsart nach Microsofts Entscheidungsweg (`ByEffectiveIsolation`: `none`, `shared`, `isolated`, `unbekannt`), ebenfalls nur als Anzahl. Es nennt die Eigenschaften von `MSFT_PrinterDriver` und die Namen der Registrierungswerte unter den Treiberschlüsseln, aber keine Treiber- und keine Druckernamen. Von den Zählern der Druckwarteschlangen wird nur die Summe aller Warteschlangen gelesen, dazu die Zahl der Warteschlangen, damit kein Druckername im Ergebnis steht.

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

In der JSON-Datei sind Namen maskiert, auch der des Servers (er steht weder im Dateinamen noch im Inhalt; mehrere Server lassen sich am Zeitstempel der Datei unterscheiden). In allen Texten werden ersetzt:

| Name | Ersatz | Woran das Skript ihn erkennt |
|---|---|---|
| Benutzernamen | `<user>` | Sitzungen (WTS), Ordner der Benutzerprofile, angemeldeter Benutzer; außerdem ohne Liste der Name neben einer Konten-SID (`<sid>_name`, `name_<sid>`) und in Containerdateien (`Profile_name.vhdx`, `ODFC_name.vhdx`) |
| Domänennamen | `<domain>` | Domäne jeder Sitzung, `USERDOMAIN`, `USERDNSDOMAIN`, Zusatz an Profilordnern, mehrteiliger DNS-Anteil eines Servernamens; neben einem Benutzernamen auch unbekannte (`<user>.<domain>`, `<domain>\<user>`, `<user>@<domain>`) |
| Clientnamen | `<client>` | Clientname jeder Sitzung |
| Name des Servers | `<server>` | Computername und Hostname |
| Servernamen | `<server>` | jeder Pfad der Form `\\server\…`, `\\?\UNC\server\…`, `\??\UNC\server\…`, `\Device\Mup\server\…` oder `\Device\LanmanRedirector\…\server\…`; die so gefundenen Server, die Server der SMB-Freigaben und die Hosts der Datei für `-EndpointFile` werden auch in freiem Text ersetzt |
| Konten-SIDs | `<sid>` | Muster `S-1-5-21-…` (Domänenkonten) und `S-1-12-1-…` (Entra-ID-Konten); bekannte SIDs wie `S-1-5-18` bleiben stehen |

Die Prüfungen behalten ihre Texte zunächst unverändert; maskiert wird das Ergebnis einmal als Ganzes, nach der letzten Prüfung und mit allen Namen, die bis dahin bekannt sind. Sitzungen kommen und gehen, während das Skript läuft: Es liest sie deshalb beim Start, nach jeder Prüfung und vor dem Maskieren noch einmal, die Profilordner beim Start und vor dem Maskieren. Wer sich während des Laufs anmeldet, wird so ebenfalls maskiert. Eine Lücke bleibt: Wer sich innerhalb einer einzelnen Prüfung an- und wieder abmeldet und dessen Profilordner beim Abmelden gelöscht wird, steht in keiner Liste; für ihn greifen nur die festen Muster der Tabelle. Die längsten Prüfungen sind die der Eingabeverzögerung (mit den Standardwerten 40 Sekunden), die der Ereignisprotokolle und, bei vielen Containern, die der Profilcontainer. Hostnamen und Adressen der Gegenstellen werden nicht ausgegeben.

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
- Firmen- oder Organisationsnamen in den Angaben zu Diensten, Prozessen und Herstellern (auch der Druckertreiber),
- Namen von Ereignisquellen (`Providers`, `Provider` in `Ids`): Aus dem Anwendungs- und dem Systemprotokoll nennt das Skript nur fest bekannte Quellen und solche aus einem Citrix-Ordner; die übrigen Protokolle (Druckdienst, SMB-Client, Profildienst, Sitzungen, Defender, AppLocker) liest es ohne Auswahl der Quelle, dort schreiben gewöhnlich nur Windows-Quellen,
- Namen in einer Bezeichnung, die Sie selbst in der Datei für `-EndpointFile` vergeben haben.

Bitte die Datei deshalb vor der Weitergabe in einem Editor durchsehen und nach bekannten Benutzer- und Servernamen sowie nach `S-1-5-21-` suchen. Findet sich nichts, kann die Datei zur Auswertung zurückgegeben werden. Sie wird außerhalb des Repositorys übergeben und nicht eingecheckt: Das Repository ist öffentlich, und `.gitignore` schließt `vda-probe_*.json` aus. Findet sich doch ein Name, bitte die Stelle mit zurückmelden: Dann fehlt dem Skript eine Regel.

Die Prüfungen der Ereignisprotokolle in dieser Form, der Druckertreiber und der Druckwarteschlangen sind bisher nur mit nachgestellten Quellen getestet; auf einem Windows-Server sind sie noch nicht gelaufen.
