# Quellen der Empfehlungen im Katalog

Der Katalog `src/guidance.de.json` enthält Empfehlungen zum Drucken auf Citrix- und Terminalservern: die Elemente der
Situation `print` und in anderen Situationen die Elemente mit einer Bedingung `pattern.printdriver` oder `driver.*`.
Jedes dieser Elemente nennt im Feld `source` den Hersteller und den Titel des Dokuments, aus dem es stammt; der
Bericht zeigt die Quelle beim Element. Diese Datei weist je Hersteller nach, welches Dokument welches Element stützt,
und nennt die Empfehlungen, die gefunden, aber nicht aufgenommen wurden, mit dem Grund.

Seit dem 13.11.2026 tragen auch Elemente anderer Situationen eine Quelle: die Schritte zu den Standardanwendungen aus
`src/apps.json` (Bedingung `app.<Anwendung>`: Microsoft Edge, Microsoft Edge WebView2, Microsoft Office, Microsoft
Teams, PrinTaurus SmartSpread Client, Microsoft Outlook), die Schritte zu Citrix Workspace Environment Management und
die Empfehlungen aus zwölf Quellen der Praxis (Abschnitt „Quellen aus der Praxis“: Carl Stalhood und BIS-F, seit der
Entscheidung des Auftraggebers vom 13.11.2026 zehn weitere). Ein Element aus einer Quelle der Praxis nennt in
`source` die Quelle mit dem Zusatz „Empfehlung aus der Praxis“ und ist nie als Empfehlung eines Herstellers formuliert.
Die Abschnitte dazu stehen nach den Druckerherstellern; der Abschnitt „Ausnahmen: Praxisquelle vor Hersteller“ nennt, wo
nach Entscheidung des Auftraggebers eine Quelle der Praxis vor dem Hersteller gilt.

## Zielumgebung

Der Katalog ist für eine Umgebung geschrieben, die sich allgemein so beschreiben lässt: Server mit mehreren Sitzungen
(Windows Server 2022, Citrix VDA), ausschließlich über Machine Creation Services bereitgestellt und nicht persistent.
Ein solcher Server entsteht bei jedem Neustart neu aus dem Master-Image; was auf ihm selbst geändert wurde, ist danach
verloren, auch seine Ereignisprotokolle. Die Benutzerumgebung richtet Citrix Workspace Environment Management ein. Die
Drucker ordnen nicht die Citrix-Richtlinien zu, sondern PrinTaurus, die Drucklösung der AKI GmbH; auf dem Server ist
dafür der PrinTaurus SmartSpread Client installiert. Beides ist eine Angabe des Auftraggebers vom 13.11.2026, keine
Aussage einer gelesenen Seite. Daraus folgen drei Regeln des Katalogs:

- Ein Vorschlag, der eine Einstellung ändert (Treiber, Richtlinie, Registrierung, Scan-Ausschluss, Dienst,
  installierte Software), nennt den Ort der Änderung mit einer von zwei festen Wendungen:
  „bei nicht persistenten Servern im Master-Image, danach die Server neu bereitstellen“ oder, wo die Änderung selbst
  eine Richtlinie ist, „eine Richtlinie wirkt auch auf nicht persistente Server“. Einen Scan-Ausschluss, eine Ausnahme
  oder einen Zeitplan der Schutzsoftware setzt ihre zentrale Verwaltung oder eine Richtlinie, sonst das Master-Image;
  eine korrigierte Version der Schutzsoftware gehört ins Master-Image (Abhilfe „Ausnahme oder korrigierte Version der
  Schutzsoftware …“ der Situation `crash`). Ein Schritt, dessen Wirkung ein Neustart des Servers aufhebt (einen
  Treiber am Server entfernen), sagt „am Server selbst nur bis zum Neustart wirksam“. Wer den Spool-Ordner leert,
  liest, dass auch ein Neustart ihn auf den Stand des Master-Image zurücksetzt (Abhilfe „Spool-Ordner von Hand
  leeren …“ der Situation `print`, Abhilfe „Dienst „Druckwarteschlange“ zurücksetzen, wie Brother es beschreibt …“
  der Situation `print`). Wer einen Prozess beendet oder eine Anwendung neu starten lässt, liest, dass das nur wirkt,
  bis die Anwendung wieder startet (von selbst nach der nächsten Anmeldung oder dem nächsten Neustart des Servers)
  oder den Arbeitsspeicher wieder belegt (Abhilfe „‹Anwendung› vom Benutzer schließen lassen …“ der Situation `cpu`,
  Abhilfe „‹Anwendung› schließen und neu starten lassen …“ der Situation `memory`). Diese Zusätze stammen nicht vom
  Hersteller des jeweiligen Elements.
- Die Schritte zu einem Vorfall aus der Zeit vor der Messung sagen, dass die Ereignisprotokolle auf solchen Servern
  nur bis zum letzten Neustart zurückreichen.
- Schritte zur Zuordnung der Drucker setzen keine Citrix-Richtlinien voraus; wo ein Schritt von ihnen abhängt, sagt er
  es („Wenn die Drucker über Citrix-Richtlinien zugeordnet werden: …“ oder in der Voraussetzung).

Namen von Systemen des Auftraggebers stehen weder im Katalog noch in dieser Datei.

Ein Element der Situation `print`, das keine Empfehlung eines Herstellers ist, sondern ein Hinweis des Berichts
selbst, trägt die Quelle „WorkerPerf: Hinweis zur Auswertung“; der Abschnitt „WorkerPerf“ führt diese Elemente auf.
Der Abschnitt „Auf dem Zielsystem zu bestätigen“ am Ende nennt die Bezeichnungen von Windows, Citrix und VMware im
ganzen Katalog, die hier nicht geprüft werden konnten.

Eine Stelle wie `print.remedies[2]` bezeichnet Situation, Liste und Position im Katalog, gezählt ab 0:
`print.remedies[2]` ist der dritte Abhilfevorschlag der Situation `print`. Stand: Katalog `version` 2026-11-13.
Der Abschnitt „Zielumgebung“, der Abschnitt „Auf dem Zielsystem zu bestätigen“ und die Hinweise in den Tabellen nennen
ein Element nicht mit seiner Stelle, sondern mit der Liste, seinen ersten Worten in Anführungszeichen und der Situation
(Abhilfe „…“ der Situation `print`): Diese Angabe stimmt auch dann noch, wenn Elemente hinzukommen. In den Tabellen und
in solchen Anfangsworten steht für einen Platzhalter des Katalogs sein Name in einfachen Winkeln:
‹Anwendung› für `{app}`, ‹Benutzer› für `{user}`, ‹Treiber› für `{driver}`, ‹Gegenstelle› für `{endpoint}`.

## Wie die Quellen geprüft wurden

- Recherchiert wurde am 13.11.2026 für die Druckempfehlungen nur in der eigenen Dokumentation der fünf Hersteller
  (Microsoft Learn, docs.citrix.com und die Support- und Dokumentseiten von HP, Kyocera und Brother), für die
  Standardanwendungen, Workspace Environment Management und PrinTaurus in der Dokumentation von Microsoft, Citrix und
  AKI, und in den beiden Quellen der Praxis. Seiten Dritter, Foren und Suchtreffer ohne geöffnete Seite zählen nicht
  als Quelle.
- Jede Seite wurde nach der Recherche ein zweites Mal geöffnet und das Zitat mit dem Text der Seite verglichen. Was
  die Seite nicht stützt, ist gestrichen; die Spalte „Hinweis“ nennt Einschränkungen, die die Seite selbst macht.
- Eine Empfehlung, deren Quelle nicht erreichbar war, ist nicht aufgenommen. Jeder Abschnitt nennt am Ende, welche
  Quellen nicht erreichbar waren.
- Ein Hersteller, für den sich zu einer Frage nichts fand, hat dazu kein Element; der Katalog füllt solche Lücken
  nicht aus eigenem Wissen.
- Die zehn weiteren Quellen aus der Praxis wurden am 13.11.2026 recherchiert. Zu jedem Eintrag der Recherche gibt es
  eine Quellenprüfung: Die Seite wurde ein zweites Mal geöffnet, und der Eintrag gilt als gestützt, als teilweise
  gestützt (dann nur mit der genannten Korrektur) oder als nicht gestützt (dann nicht verwendet). Aus den Einträgen
  entstand eine Auswahl, die Kandidat für Kandidat angefochten wurde; die Kennungen der Auswahl (PXG-…) stehen in der
  Spalte „Hinweis“.
- Eine Aussage einer dieser Quellen, die ein vorhandenes Element nur stützt oder verfeinert, ist kein neues Element.
  Sie steht als ein Satz mit dem Namen der Quelle im Element („nach …“); das Element behält seine Quelle. Der
  Abschnitt der Praxisquelle führt das Element unter „Stützt bestehende Elemente“ mit der Zeile „auch gestützt
  durch“, Titel, Adresse und Datum des Dokuments.
- Eine Zahl aus einer Quelle der Praxis steht im Katalog nur mit ihren Bedingungen und ihrem Jahr. Sie ist ein
  Messwert der Quelle unter deren Bedingungen und nie ein Sollwert für die Server der Zielumgebung.
- Ein Element aus der Praxis steht in seiner Situation hinter den Elementen der Hersteller und den eigenen Schritten
  derselben Bedingung. In keinem Vorfall der simulierten Stunde verdrängt es einen Schritt aus den ersten fünf
  Prüfschritten oder den ersten drei Vorschlägen; ein Test hält das fest.

Die Empfehlungen sind Vorschläge. Der Bericht zeigt ein Element nur, wenn die Messung seine Bedingung stützt
(etwa: ein Treiber dieses Herstellers war beteiligt, die Druckwarteschlange ist ausgefallen); ob die Voraussetzung
eines Vorschlags zutrifft, entscheidet, wer den Bericht liest. Die Quelle eines Elements stützt, was zu tun ist. Wo
im Bericht nachzusehen ist, und Vorsichtsmaßnahmen in einer Voraussetzung (Wartungsfenster, Test auf einem Testserver,
Zustimmung der Verantwortlichen für die Sicherheit, Benutzer informieren) stammen nicht vom Hersteller; die Spalte
„Hinweis“ sagt es je Dokument. Eine Einschränkung, die eine Seite selbst macht (Betriebssystem, Art des Anschlusses),
steht im Element. Namen von Richtlinien und Einstellungen stehen im Katalog englisch, wie die Quelle sie nennt; die
deutschen Bezeichnungen der Oberflächen sind nicht aus einer Quelle belegt.

Wer ein Element des Katalogs ändert, verschiebt oder ergänzt, passt diese Datei an: Der Test
`tests/GuidanceCatalogue.Tests.ps1` prüft, dass jedes Element mit Quelle hier an seiner Stelle unter seinem Dokument
steht und dass hier keine Stelle steht, die der Katalog nicht hat. In den Abschnitten ab „AKI“ bis zur letzten Quelle
aus der Praxis steht bei
jeder Stelle der Anfang des Elementtexts: bis zum ersten Doppelpunkt, Semikolon oder zur ersten öffnenden Klammer
nach dem zwanzigsten Zeichen, höchstens 110 Zeichen (ein längerer Anfang endet nach 107 Zeichen mit „…“); steht ein
Schritt für jedes Office-Programm ein zweites Mal für Outlook im Katalog, folgt „(für Outlook)“. Der Test vergleicht
auch das mit dem Katalog.

## Quellen aus der Praxis

Zwölf Quellen aus der Praxis dürfen Elemente des Katalogs tragen oder stützen (Entscheidungen des Auftraggebers vom
13.11.2026). Keine von ihnen ist die Dokumentation eines Herstellers. Widerspricht eine von ihnen dem Hersteller, gilt
der Hersteller; die einzige Ausnahme nennt der Abschnitt „Ausnahmen: Praxisquelle vor Hersteller“. Jede Quelle hat
weiter unten einen eigenen Abschnitt mit ihren Dokumenten, den Belegstellen und dem, was sie begrenzt.

- **Carl Stalhood**: Anleitungen zu Citrix, <https://www.carlstalhood.com/>
- **BIS-F**: Base Image Script Framework, Skripte zum Versiegeln eines Master-Image, <https://github.com/EUCweb/BIS-F>
- **GO-EUC**: gemessene Vergleiche von Einstellungen und Versionen in Laborumgebungen, <https://www.go-euc.com/>
- **James Kindon**: Blog zu Workspace Environment Management und Citrix Profilverwaltung, <https://jkindon.com/>
- **James Rankin**: Blog mit Messreihen zur Dauer der Anmeldung, <https://james-rankin.com/>
- **Thomas Kötzing**: Blog zu Drucken, Anmeldung und Profilen unter Citrix, <https://koetzingit.de/>
- **Manuel Winkel**: Blog deyda.net, für einzelne Themen (Teams, WEM, Beobachtungen aus Projekten),
  <https://www.deyda.net/>
- **Aaron Parker**: Blog stealthpuppy.com, für einzelne Themen (Größe und Inhalt von Profilcontainern),
  <https://stealthpuppy.com/>
- **Trentent Tye**: Blog mit Messungen zu langsamen Anmeldungen, nur unter seiner eigenen Adresse
  <https://trentent.github.io/>
- **John Billekens**: Sammlung der Scan-Ausschlüsse der Hersteller, für einzelne Themen, <https://ave.j81.nl/>
- **Guy Leech**: Blog und Skripte zur Fehlersuche, für einzelne Themen, <https://guyrleech.wordpress.com/>
- **Benny Tritsch**: Methodik zur Messung der Benutzererfahrung (EUC Score), für einzelne Themen,
  <https://drtritsch.com/>
- **Kasper Johansen**: ebenfalls übernommen, aber nicht mehr erreichbar, nicht verwendet (Recherche vom 13.11.2026:
  unter der früheren Adresse steht kein Blog mehr); der Katalog enthält nichts aus dieser Quelle

## Microsoft

Microsoft dokumentiert nichts Eigenes zum Citrix-Universaltreiber, zum Citrix Universal Print Server oder zur Treiberzuordnung von Citrix und trifft keine Aussage, ob Treiber der Bauart Typ 3 oder Typ 4 auf Terminalservern stabiler sind. Kein Element hängt deshalb an der Bedingung `driver.vendor.Microsoft`.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| Policy CSP - ADMX_Printing | <https://learn.microsoft.com/windows/client-management/mdm/policy-csp-admx-printing> | 2026-11-13 | `crash.checks[3]` Richtlinie zur Isolierung der Treiber von Anwendungen<br>`print.checks[9]` Wirkung der Isolierung bei isoliertem Treiber<br>`print.checks[10]` Richtlinie zur Treiberisolierung nicht abgeschaltet<br>`print.remedies[2]` Isolierung per Richtlinie für alle Treiber erzwingen | Die Seite nennt als Betriebssysteme Windows 10 und 11, nicht Windows Server 2022; jedes der vier Elemente sagt das (die Abhilfe in ihrer Voraussetzung). Die Richtlinien zur Treiberisolierung gelten laut Seite nur für Treiber, die die Druckwarteschlange lädt; „Isolate print drivers from applications“ wirkt nur bei Anwendungen, die die Isolierung unterstützen, und erst nach deren Neustart. Datenwerte der Registrierung nennt die Seite nicht. Die Prozessnamen PrintIsolationHost.exe und spoolsv.exe im Prüfschritt „Einordnen, was abgestürzt ist …“ der Situation `print` stammen aus der Auswertung (Liste der Druckprozesse), nicht von der Seite; die Voraussetzung „auf einem Testserver geprüft“ der Abhilfe „Richtlinie „Override print driver execution compatibility setting reported by print driver“ aktivieren …“ der Situation `print` stammt nicht von Microsoft. |
| Printer driver isolation | <https://learn.microsoft.com/windows-hardware/drivers/print/printer-driver-isolation> | 2026-11-13 | `print.checks[8]` Isolierung des beteiligten Treibers ansehen<br>`print.remedies[0]` fehlerhaften Treiber isoliert betreiben | Dokumentation für Treiberentwickler. Sie sagt, dass sich der Modus in der Druckverwaltung je Treiber einstellen lässt, nennt die Stelle dort aber nicht genauer (siehe „Auf dem Zielsystem zu bestätigen“) und spricht nicht von Typ 3 oder Typ 4. Die Voraussetzung der Abhilfe „Treiber ‹Treiber› in einem eigenen Prozess laufen lassen …“ der Situation `print` folgt dem Satz der Seite: Der Treiber ist in einem eigenen Prozess lauffähig, verursacht häufig Fehler oder verliert Arbeitsspeicher und stört damit andere Treiber im selben Prozess. „Zuerst auf einem Testserver geprüft“ stammt nicht von Microsoft. |
| Troubleshooting scenarios for printing | <https://learn.microsoft.com/troubleshoot/windows-server/printing/troubleshoot-printing-scenarios> | 2026-11-13 | `print.checks[2]` Treiber oder Warteschlange als Auslöser feststellen<br>`print.checks[15]` Spool-Ordner und Dienstabhängigkeit nach Absturz<br>`print.checks[20]` hängende Aufträge auf Treiber oder Warteschlange eingrenzen<br>`print.remedies[12]` Treiber aktualisieren oder generischen Treiber verwenden | Microsoft beschreibt die Schritte zu fehlgeschlagenen Aufträgen „auf dem Clientcomputer“. Zur Abhängigkeit des Dienstes nennt die Seite als Standard nur RpcSs. Ob ein Windows Server 2022 ohne Druckproblem weitere Einträge hat, ist hier nicht geprüft; der Prüfschritt „Spool-Ordner und Abhängigkeiten des Dienstes „Druckwarteschlange“ prüfen …“ der Situation `print` verlangt deshalb den Vergleich mit einem solchen Server (siehe „Auf dem Zielsystem zu bestätigen“). |
| Troubleshoot printing issues caused by Print Spooler service not running | <https://learn.microsoft.com/troubleshoot/windows-server/printing/print-spooler-service-not-running> | 2026-11-13 | `print.checks[11]` Treiber und Druckkomponenten aktuell<br>`print.remedies[11]` Spool-Ordner vom Scan ausnehmen | Die Seite sagt „Create exclusions for the spool folder“; Dateiendungen nennt sie dabei nicht. Als Anlass nennt sie Schutzsoftware, die Dateien blockiert, die der Dienst braucht; die Abhilfe „Spool-Ordner in der Schutzsoftware vom Scan ausnehmen …“ der Situation `print` verlangt deshalb eine Meldung der Schutzsoftware. Die Zustimmung der Verantwortlichen für die Sicherheit stammt nicht von Microsoft. |

### Belegstellen

- **Policy CSP - ADMX_Printing**
  - „When print drivers are loaded in an isolated process (or isolated processes), a print driver failure won't cause the print spooler service to fail. If you enable or don't configure this policy setting, the print spooler will execute print drivers in an isolated process by default.“
  - „This policy setting determines whether the print spooler will override the Driver Isolation compatibility reported by the print driver. This enables executing print drivers in an isolated process, even if the driver doesn't report compatibility. If you enable this policy setting, the print spooler isolates all print drivers that don't explicitly opt out of Driver Isolation.“
  - „Determines if print driver components are isolated from applications instead of normally loading them into applications. Isolating print drivers greatly reduces the risk of a print driver failure causing an application crash. Not all applications support driver isolation.“
- **Printer driver isolation**
  - „Ideally, a printer driver is able to run in shared mode. [...] A driver might need to run in isolated mode if it can run in a process separate from the spooler process, but has difficulty sharing the process with other drivers. For example, [...] the driver might fault frequently or have a memory leak that interferes with the operation of other drivers that run in the same process.“
  - „By default, if the INF file that installs a printer driver does not indicate that the driver supports driver isolation, the printer class installer configures the driver to run in the spooler process. [...] An administrator can override these configuration settings and specify, for each driver, whether to run the driver in the spooler process or in an isolated process.“
- **Troubleshooting scenarios for printing**
  - „Move any old files that are in the Spool folder to see whether the issue still occurs. Corrupted files in the Spool folder can cause Print Spooler service problems.“
  - „If application stopped responding, determine which print driver or print queue reproduces issue. [...] Narrow down the issue to learn which driver is the cause.“
  - „Update the printer driver to the latest version from the OEM. However, if the driver that's in use is already the latest version, try switching to a generic in-box driver.“
- **Troubleshoot printing issues caused by Print Spooler service not running**
  - „Anti-virus software can sometimes interfere with the Print Spooler service. Ensure the anti-virus software isn't blocking any files needed by the Print Spooler service. Create exclusions for the spool folder.“
  - „Ensure all relevant drivers are up to date. Outdated drivers and print components might cause the Print Spooler service to stop responding.“

### Nicht aufgenommen

| Empfehlung | Grund |
|---|---|
| Richtlinie „Use Remote Desktop Easy Print printer driver first“ und der Ausweichtreiber des Remotedesktop-Sitzungshosts | Quelle veraltet oder nur für ein anderes Produkt (gilt für die Druckerumleitung über RDP; Drucker in Citrix-Sitzungen legt der VDA an) |
| Prüfungen zu Easy Print für Azure Virtual Desktop und Windows 365 | Quelle veraltet oder nur für ein anderes Produkt |
| Einen gemeinsamen Treiber (Easy Print) statt passender Treiber je Drucker verwenden, um die Druckwarteschlange zu entlasten (Performance Tuning Remote Desktop Session Hosts) | Quelle veraltet oder nur für ein anderes Produkt (die Seite beschränkt die Aussage auf RDP Easy Print) |
| Installation von Druckern mit Kernelmodus-Treibern verbieten | Quelle veraltet oder nur für ein anderes Produkt (der Text bezieht sich auf Windows XP und Server 2003) |
| Ende der Wartung für Treiber von Drittanbietern, Microsoft-IPP-Klassentreiber und geschützter Druckmodus von Windows | Quelle veraltet oder nur für ein anderes Produkt (gilt laut Microsoft ab Windows 11 und Windows Server 2025) |
| „Cannot add a printer in Citrix Virtual Apps on Windows Server 2019“ | Quelle veraltet oder nur für ein anderes Produkt (nur Windows Server 2019) |
| Point-and-Print-Beschränkungen abschalten, um Ereignisse zum Treiberdownload zu vermeiden | setzt eine Änderung voraus, die die Messung nicht stützt (sicherheitsrelevante Richtlinie ohne Bezug zu den gemessenen Vorfällen) |
| Nicht genutzte Druckertreiber mit Remove-PrinterDriver entfernen | keine Herstellerquelle gefunden (Microsoft dokumentiert das Cmdlet, aber keine Empfehlung dazu für Sitzungshosts; die Empfehlung von Citrix steht im Abschnitt Citrix) |
| Wahl zwischen Typ 3 und Typ 4 wegen der Stabilität auf Sitzungshosts | keine Herstellerquelle gefunden (die Seiten zu Typ 4 beschreiben nur das Modell für Entwickler) |
| Fehlerüberwachung (Auditing) für Drucker einschalten | setzt eine Änderung voraus, die die Messung nicht stützt |
| Monitore, Druckprozessoren und Druckanbieter von Drittanbietern entfernen | setzt eine Änderung voraus, die die Messung nicht stützt (Microsoft nennt den Schritt nur für langsames Drucken oder falsche Ausgabe; beides erfasst die Messung nicht) |
| Prüfen, ob eine Gruppenrichtlinie den Dienst „Druckwarteschlange“ deaktiviert, und nach Fehlern beim Start des lokalen Druckanbieters suchen | setzt eine Änderung voraus, die die Messung nicht stützt (gilt für einen Dienst, der nicht startet; die Messung erfasst Abstürze und unerwartetes Beenden) |

Nicht erreichbar: techcommunity.microsoft.com (Beiträge der Produktgruppen, etwa zur Treiberisolierung); von dort ist nichts übernommen.

## Citrix

Die erreichbare Produktdokumentation von Citrix sagt nichts zur Treiberisolierung und nichts Verwertbares zu Typ 3 und Typ 4; die Wissensdatenbank (CTX-Artikel) war nicht lesbar. Kein Element hängt an `driver.vendor.Citrix`: Zum Fall, dass der Citrix-Universaltreiber selbst beteiligt ist, fand sich keine Aussage.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| Best practices | <https://docs.citrix.com/us/en/citrix-virtual-apps-desktops/current-release/printing/troubleshooting/best-practices.html> | 2026-11-13 | `crash.remedies[3]` Treiber sauber erneuern statt überinstallieren<br>`print.remedies[3]` Universaltreiber als Regel, ungenutzte Treiber entfernen<br>`print.remedies[5]` Treiber sauber erneuern statt überinstallieren<br>`print.remedies[13]` alte und hängende Aufträge regelmäßig löschen | Aktuelle Fassung der Produktdokumentation. Den Neustart nennt Citrix; das Wartungsfenster dafür in der Voraussetzung der Abhilfe „Treiber ‹Treiber› nicht über die vorhandene Version aktualisieren, sondern sauber erneuern …“ der Situation `crash` und der Abhilfe „Treiber ‹Treiber› nicht über die vorhandene Version aktualisieren, sondern sauber erneuern …“ der Situation `print` stammt nicht von Citrix, ebenso wenig das Wartungsfenster für das Entfernen nicht mehr benötigter Treiber in der Abhilfe „Citrix-Universaltreiber als Regel verwenden und nicht mehr benötigte Druckertreiber deinstallieren …“ der Situation `print`. |
| Troubleshooting | <https://docs.citrix.com/us/en/citrix-virtual-apps-desktops/current-release/printing/troubleshooting.html> | 2026-11-13 | `print.checks[0]` Dienst läuft wieder, sonst starten<br>`print.checks[1]` fehlerhaftes Modul dem Treiber zuordnen<br>`print.checks[26]` Citrix Print Manager Service läuft<br>`print.remedies[1]` Treiber entfernen, mit Universaltreiber oder Microsoft-Treiber testen<br>`print.remedies[10]` Spool-Ordner von Hand leeren | Die Zuordnung des fehlerhaften Moduls zu einem Treiber stammt aus der Messung; die Seite sagt nur, dass das Modul festzustellen ist. Den Neustart des Dienstes nennt die Seite als Schritt vor dem Leeren von Hand („If restarting fails …“); wo der Zustand des Dienstes steht, ist ein eigener Hinweis. Das Leeren von Hand nennt sie nur für Abstürze der Druckwarteschlange. Der Hinweis, dass die Aufträge aller Benutzer des Servers verloren gehen, stammt nicht von Citrix, ebenso wenig die Voraussetzungen „Benutzer informiert“ (Abhilfe „Spool-Ordner von Hand leeren …“ der Situation `print`) und „Wartungsfenster“ (Abhilfe „Treiber ‹Treiber› entfernen …“ der Situation `print`). |
| Maintain the printing environment | <https://docs.citrix.com/us/en/citrix-virtual-apps-desktops/2503/printing/printing-maintain-environment.html> | 2026-11-13 | `crash.remedies[2]` Treiber über die Treiberzuordnung ersetzen oder sperren<br>`print.remedies[4]` Treiber über die Treiberzuordnung ersetzen oder sperren | Seite der Version 2503. |
| Best practices, security considerations, and default operations | <https://docs.citrix.com/us/en/citrix-virtual-apps-desktops/2503/printing/printing-best-practices.html> | 2026-11-13 | `crash.contacts[0]` Hersteller nach der Zertifizierung für Terminalserver fragen<br>`print.contacts[0]` Hersteller nach der Zertifizierung für Terminalserver fragen | Seite der Version 2503; sie verwendet noch die Bezeichnung „Terminal Services“. |
| Drivers policy settings | <https://docs.citrix.com/us/en/citrix-virtual-apps-desktops/current-release/policies/reference/ica-policy-settings/printing-policy-settings/drivers-policy-settings.html> | 2026-11-13 | `print.checks[17]` Richtlinie zur Verwendung des Universaltreibers | Aktuelle Fassung der Produktdokumentation. Das Element beginnt mit „Wenn die Drucker über Citrix-Richtlinien zugeordnet werden“: In der Zielumgebung ordnet ein Zuordnungswerkzeug die Drucker zu. |
| Network Printers (on the VDA) | <https://docs.citrix.com/us/en/citrix-virtual-apps-desktops/current-release/printing/configuration/network-printers.html> | 2026-11-13 | `print.checks[18]` Herkunft der Drucker (Windows-Druckserver oder Universal Print Server) | Aktuelle Fassung der Produktdokumentation. |

### Belegstellen

- **Best practices**
  - „Employ Universal Print Driver (UPD): Use UPD as the primary driver strategy to minimize driver count and conflicts.“
  - „Minimize Driver Footprint: Install the fewest possible number of printer drivers on VDA images.“
  - „Clean Up Unused Drivers: Regularly remove drivers that are no longer needed.“
  - „Manage Driver Updates Carefully: Avoid in-place updates; prefer a clean uninstall, reboot, and reinstall process.“
  - „Purge Old Print Jobs: Periodically clear stuck or old jobs from print queues.“
- **Troubleshooting**
  - „Identify the faulting process/module using Windows Event Logs (Application log often shows spooler crashes).“
  - „Identify and remove the problematic printer driver. Clean removal may require registry edits. Test with the Citrix UPD or a generic Microsoft driver.“
  - „If restarting fails or the issue repeats, try to clear the print queue manually (Stop Spooler service, delete files in C:\Windows\System32\spool\PRINTERS, Start Spooler service).“
  - „CpSvc.exe not running or crashed“
- **Maintain the printing environment**
  - „If the Citrix Universal print driver is not an option for all scenarios, map printer drivers to minimize the amount of drivers installed on Multi-session OS machines.“
  - „Allow or prevent printers to be created with a specified driver“
  - „Substitute good printer drivers for outdated or corrupted drivers“
  - „testing the behavior of the printers in detail after mapping drivers, since some printer functionality can be available only with a specific driver“
- **Best practices, security considerations, and default operations**
  - „In general, all of the Microsoft-supplied printer drivers are tested with Terminal Services and guaranteed to work with Citrix. However, before using a third-party printer driver, consult your printer driver vendor so that the driver is certified for Terminal Services by the Windows Hardware Quality Labs (WHQL) program. Citrix does not certify printer drivers.“
- **Drivers policy settings**
  - „By default, universal printing is used only if the requested driver is unavailable.“
  - „Use universal printing only Specifies that no standard model-specific drivers are used. Only universal print drivers are used to create printers.“
- **Network Printers (on the VDA)**
  - „If the printer is hosted on a standard Windows Print Server, the corresponding native printer driver must be installed on the VDA. If the printer is hosted on a Citrix Universal Print Server (UPS), the connection can use either the native driver or the Citrix UPD.“

### Nicht aufgenommen

| Empfehlung | Grund |
|---|---|
| Richtlinie „Automatic installation of in-box printer drivers“ abschalten | Quelle veraltet oder nur für ein anderes Produkt (wirkt laut Citrix ab Windows 8 nicht mehr und wird von aktuellen VDAs nicht unterstützt) |
| Kernelmodus-Treiber der Version 2 vermeiden | Quelle veraltet oder nur für ein anderes Produkt |
| Aussagen zur Unterstützung von Typ 3 und Typ 4 (CTX223749) | keine Herstellerquelle gefunden (der Artikel der Wissensdatenbank war nicht lesbar) |
| Modi der Treiberisolierung und der Hinweis, dass Isolierung einen fehlerhaften Treiber nicht repariert (CTX136332) | keine Herstellerquelle gefunden (der Artikel der Wissensdatenbank war nicht lesbar) |
| Netzwerkwege für Druckdaten (direkte Verbindung zum Druckserver, Bandbreitengrenzen, Lastverteilung des Universal Print Server) und der Universal Print Server für das Drucken über Weitverkehrsstrecken | setzt eine Änderung voraus, die die Messung nicht stützt (betrifft Geschwindigkeit und Netzwege, nicht Abstürze, hängende Aufträge oder Treiber) |
| Treiber mit dem Werkzeug StressPrinters testen (CTX109374); Prüfung der Mindestversion mitgelieferter Treiber (CTX132102) | keine Herstellerquelle gefunden (die Artikel der Wissensdatenbank waren nicht lesbar) |
| Verwaiste Drucker- und Druckprozessor-Einträge aus der Registrierung des Servers entfernen, wenn der Citrix Print Manager Service abstürzt oder hängt | setzt eine Änderung voraus, die die Messung nicht stützt (Eingriff in die Registrierung; die Messung zeigt nicht, ob verwaiste Einträge vorliegen; aufgenommen ist nur der Prüfschritt, ob der Dienst läuft) |

Nicht erreichbar: die Wissensdatenbank support.citrix.com (alle CTX-Artikel; die Seiten liefern ohne Skript keinen Text) und Citrix Tech Zone auf community.citrix.com. Von dort ist nichts übernommen.

## HP

HP sagt in seinen aktuellen Dokumenten nichts zur Treiberisolierung unter Windows Server 2022 und nennt keine Obergrenze für die Zahl der Treiber oder Druckwarteschlangen je Server. Alle Elemente dieses Abschnitts hängen an `driver.vendor.HP`.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| HP Print and Scan Devices Supported in Citrix Virtual Apps and Virtual Desktops Environments | <https://kaas.hpcloud.hp.com/pdf-public/pdf_6290906_en-US-1.pdf> | 2026-11-13 | `print.remedies[7]` hostbasierte HP-Treiber nicht auf dem Server<br>`print.remedies[16]` HP Universal Print Driver im Traditional Mode | Technical white paper, Rev. 39, Juni 2023; enthält viel Altbestand (XenApp, 32-Bit-Pfade). Dass die Clientdrucker über den Citrix-Universaltreiber bedient werden können, nennt HP als Möglichkeit („might function“, „An alternative is“); die Abhilfe „Hostbasierte HP-Treiber nicht auf dem Server betreiben …“ der Situation `print` sagt es ebenso. Das Wartungsfenster in dessen Voraussetzung stammt nicht von HP. |
| System Administrator's Guide For the HP V3 Universal Print Driver (PCL 6/PS) and the HP Print Administrator's Resource Kit (PARK) | <https://kaas.hpcloud.hp.com/pdf-public/pdf_8951296_en-US-1.pdf> | 2026-11-13 | `print.checks[21]` SNMP-Einstellungen und WSD-Anschluss beim HP Universal Print Driver<br>`print.checks[24]` Eingrenzung nach HP (zugeordneter Treiber, außerhalb der Sitzung, sauberes Testsystem)<br>`print.remedies[6]` Treiberwahl nach Endgerät (Citrix-Universaltreiber oder HP Universal Print Driver)<br>`print.remedies[8]` Reihenfolge beim Entfernen des HP Universal Print Driver<br>`print.remedies[9]` Dienst neu starten, wenn Windows den Treiber als in Gebrauch meldet<br>`print.contacts[1]` Angaben für den Support von HP | Edition 11, Mai 2026. Die Aussagen zum Status „Offline“ bei falschen SNMP-Einstellungen und zum WSD-Anschluss macht HP für den HP Universal Print Driver; der Prüfschritt „Bei Druckwarteschlangen mit dem HP Universal Print Driver und dem Status „Offline“ den Anschluss prüfen …“ der Situation `print` beschränkt sich darauf. Die Reihenfolge beim Entfernen beschreibt HP für den HP Universal Print Driver. Das Wartungsfenster (Abhilfe „HP Universal Print Driver in der Reihenfolge von HP entfernen …“ der Situation `print`, Abhilfe „Dienst „Druckwarteschlange“ anhalten und wieder starten …“ der Situation `print`) und der Hinweis, dass beim Neustart des Dienstes alle Benutzer kurz nicht drucken können und laufende Aufträge verloren gehen können, stammen nicht von HP. |
| HP Universal Print Driver Release Notes | <https://kaas.hpcloud.hp.com/pdf-public/pdf_8592592_en-US-1.pdf> | 2026-11-13 | `crash.checks[4]` Version des HP Universal Print Driver mit den Versionshinweisen vergleichen<br>`print.checks[12]` Version des HP Universal Print Driver mit den Versionshinweisen vergleichen | Edition 19, Juni 2026 (HP UPD 8.2.0). |

### Belegstellen

- **HP Print and Scan Devices Supported in Citrix Virtual Apps and Virtual Desktops Environments**
  - „Installing the HP UPD in Dynamic Mode on the Citrix server is not supported. This is due to a design limitation in the Windows operating system which limits a print queue to be assigned to one port at a time, so multiple users would compete for the single port bound to the HP UPD queue if installed in Dynamic Mode.“
  - „HP does not recommend installing host-based LaserJet drivers on the Citrix server. However, the devices might function by using the Citrix UPD on the Citrix server the HP host-based driver installed on the client.“
  - „HP does not recommend the use of host-based printers in Citrix environments. [...] An alternative is to use the Citrix UPD to print to a host-based client printer.“
- **System Administrator's Guide For the HP V3 Universal Print Driver (PCL 6/PS) and the HP Print Administrator's Resource Kit (PARK)**
  - „Table 5-3 „Comparing HP and Citrix UPD Drivers“: Citrix UPD „Better choice for Windows clients“; HP UPD „Better choice for non-Windows clients or thin clients““
  - „However, if the Microsoft SNMP stack utilized between the Microsoft spooler and printer are incorrectly configured (i.e. SNMP name mismatch or enabled on one side but not the other) the HP UPD printer object may show the status “Offline.”“
  - „WSD is only supported in Traditional mode. [...] You can only use it for direct connect – it does not support print servers, terminal server, or Citrix.“
  - „1. Delete all printers that use the HP UPD. 2. In the Printers dialog, highlight a print queue, and then select Print server properties. 3. Select the Drivers tab. 4. Select the HP UPD driver(s) to be uninstalled and click Remove. NOTE: If Windows displays an error message that the driver is in use, stop and restart the print spooler“
  - „If client printers, what driver is mapped to the client for auto-creation (Citrix UPD; HP UPD; HP model specific driver)?“
  - „Does the same issue exist outside of a Terminal Server session?“
  - „Reducing complexity to isolate variables. A simple test is to install the HP UPD driver downloaded from www.hp.com/go/upd using the default installation options onto a clean system.“
- **HP Universal Print Driver Release Notes**
  - „printing behavior that has been documented as fixed in the HP UPD release notes“

### Nicht aufgenommen

| Empfehlung | Grund |
|---|---|
| HP-Treiber der Version 4.x.x.x durch die Version 60.x.x.x oder 61.x.x.x ersetzen, sonst durch den HP Universal Print Driver; laut HP bringt die Version 4.x.x.x die Druckwarteschlange unter Last wahrscheinlich zum Absturz (HP Print and Scan Devices Supported in Citrix Virtual Apps and Virtual Desktops Environments) | Quelle veraltet oder nur für ein anderes Produkt (die Version 4.x.x.x ist eine alte Treibergeneration; gemeint ist die Versionsnummer, nicht die Bauart Typ 4) |
| Treiber der Bauart Typ 4 werden nicht vom Druckserver heruntergeladen und sind vorab bereitzustellen (HP Smart Universal Printing Driver - User Guide, Edition 11.0, Februar 2025) | setzt eine Änderung voraus, die die Messung nicht stützt (der beteiligte Treiber ist auf dem Server schon installiert; ob er auf anderen Rechnern fehlt, sieht die Messung nicht) |
| Treiberisolierung mit dem HP Universal Print Driver (FAQ „Microsoft Driver Isolation Mode“) | keine Herstellerquelle gefunden (nur auf nicht erreichbaren Seiten von HP und bei Dritten; gilt zudem nur für Windows 7 und Server 2008 R2) |
| Umgehung für alte Treiber: hpbmini.dll und hpcdmc32.dll umbenennen und die Registrierung des Treibers ändern | Quelle veraltet oder nur für ein anderes Produkt (32-Bit-Pfade alter Server; aufgenommen ist nur die Empfehlung, die Treiberversion zu ersetzen) |
| Absturz oder Hängen des Citrix Universal Print Server unter hoher Drucklast mit dem HP Universal Print Driver | Quelle veraltet oder nur für ein anderes Produkt (behoben seit HP UPD 6.2) |
| In den Versionshinweisen genannte Abstürze der Druckwarteschlange mit HP UPD 5.x | Quelle veraltet oder nur für ein anderes Produkt (alte Versionen auf Windows Server 2008) |
| Beim Test mit Citrix StressPrinters einen gültigen automatisch angelegten Anschluss verwenden | setzt eine Änderung voraus, die die Messung nicht stützt (Verfahren für einen Lasttest) |
| HP Universal Print Driver im Dynamic Mode auf den Endgeräten, in der Sitzung der Citrix-Universaltreiber | setzt eine Änderung voraus, die die Messung nicht stützt (Einrichtung der Endgeräte, die die Messung auf dem Server nicht sieht) |
| HP-Clientdrucker über die Treiberzuordnung von Citrix auf den HP Universal Print Driver abbilden; Ausweichtreiber für Remotedesktopdienste | setzt eine Änderung voraus, die die Messung nicht stützt (die Messung zeigt nicht, welche Treiber durch automatisch angelegte Clientdrucker auf den Server kamen; die Treiberwahl nach Endgerät ist aufgenommen) |
| Dauer des automatischen Anlegens von Druckern (2 bis 10 Sekunden) | setzt eine Änderung voraus, die die Messung nicht stützt (die Messung erfasst die Dauer je Drucker nicht) |
| Wachstum der Registrierung unter HKCU durch Treiber 61.071 und HP UPD 5.x | Quelle veraltet oder nur für ein anderes Produkt (behobene Fehler alter Versionen) |
| Statusmeldungen (Status Notification Pop-ups) gibt es nur bis HP UPD 6.4.1 | setzt eine Änderung voraus, die die Messung nicht stützt (die Messung erfasst Statusmeldungen nicht) |
| Bidirektionale Kommunikation zu Clientdruckern wird in Citrix-Umgebungen nicht unterstützt (Standardwerte bei USB-Druckern) | setzt eine Änderung voraus, die die Messung nicht stützt (betrifft angezeigte Druckereigenschaften, die die Messung nicht erfasst; der Hinweis zum WSD-Anschluss ist aufgenommen) |
| HP Smart Universal Printing Driver der Bauart Typ 3: HP führt ihn für Server nur bis Windows Server 2022, neuere Ausgaben gibt es nur als Typ 4 (HP Smart Universal Print Driver Release Notes) | setzt eine Änderung voraus, die die Messung nicht stützt (Hinweis für die Planung; die Messung unterscheidet den HP Smart Universal Printing Driver nicht vom HP Universal Print Driver, der immer Typ 3 ist) |
| Ältere Leitfäden zum HP Universal Print Driver (5.3) und Whitepaper von 2008 und 2010 | keine Herstellerquelle gefunden (nur bei Dritten oder auf nicht erreichbaren Seiten von HP; durch die gelesenen aktuellen Dokumente ersetzt) |

Nicht erreichbar: h10032.www1.hp.com, h20331.www2.hp.com und h20195.www2.hp.com sowie die Dokumentseiten auf support.hp.com. Alle Dokumente oben stammen von kaas.hpcloud.hp.com, auch der „HP Smart Universal Printing Driver - User Guide“ (<https://kaas.hpcloud.hp.com/pdf-public/pdf_1263018_en-US-1.pdf>), aus dem nichts übernommen ist.

## Kyocera

Kyocera veröffentlicht keine Aussage zu einer Citrix-Zertifizierung, zur Treiberisolierung oder zu Abstürzen der Druckwarteschlange durch seine Treiber. Alle Elemente dieses Abschnitts hängen an `driver.vendor.Kyocera`.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| KX DRIVER INSTALLER Release Notes (KYOCERA Document Solutions America, Inc.) | <https://www.kyoceradocumentsolutions.us/content/dam/download-center-americas-cf/us/drivers/drivers/KX_Driver_Read_Me_pdf.download.pdf> | 2026-11-13 | `crash.remedies[4]` KPDL- oder PCL-Uni-Treiber statt KX-Treiber<br>`print.checks[13]` vollständiger KX-Treiber auf dem Server<br>`print.remedies[17]` KPDL- oder PCL-Uni-Treiber statt KX-Treiber<br>`print.remedies[18]` KX-Treiber erst deinstallieren, dann neu installieren<br>`print.contacts[2]` Support von Kyocera (Help Desk) bei Einsatz des KX-Treibers | Das Dokument trägt kein Datum. Das Wartungsfenster in der Voraussetzung der Abhilfe „KX-Treiber nicht mit dem Installationsprogramm über die vorhandene Version aktualisieren …“ der Situation `print` stammt nicht von Kyocera. |
| Class leading performance with the KYOCERA V4 KX DRIVER. (data sheet) | <https://www.kyoceradocumentsolutions.us/content/dam/download-center-americas-cf/us/drivers/drivers/KYOCERA_V4_KX_Driver_Datasheet_pdf.download.pdf> | 2026-11-13 | `print.remedies[20]` Funktionsumfang vergleichen, bevor von Typ 3 auf Typ 4 gewechselt wird<br>`print.remedies[21]` Funktionsumfang vergleichen, bevor von Typ 4 auf Typ 3 gewechselt wird | Datenblatt von 2019. Es vergleicht den Funktionsumfang; mit einem Druckfehler hat das nichts zu tun. Beide Elemente stehen deshalb als Abhilfe unter der Voraussetzung, dass ein Wechsel der Bauart erwogen wird. |
| Release Notes April 29, 2025 (DVD Contents) | <https://dam.kyoceradocumentsolutions.com/content/dam/gdam_dc/dc_global/document/manual/product_086/Readme_EN_202505.pdf> | 2026-11-13 | `print.remedies[19]` Kyocera-Treiber mit KmUninstall.exe entfernen | Die Seite nennt den Weg zum Deinstallationsprogramm, aber keinen weiteren Weg, verbliebene Treiber zu entfernen. Das Wartungsfenster in der Voraussetzung stammt nicht von Kyocera. |

### Belegstellen

- **KX DRIVER INSTALLER Release Notes (KYOCERA Document Solutions America, Inc.)**
  - „In Citrix and Terminal Server Environments, Kyocera recommends using our KPDL or PCL Uni Drivers. These Drivers are a better fit for Thin Client Environments because of their smaller size. If you feel that your Users need the KX Driver, or you plan to upgrade an existing KX Driver version, please contact our Help Desk for assistance implementing the installation.“
  - „The ability to use the Installer to upgrade a Driver in a Print Server Environment has been eliminated.“
- **Class leading performance with the KYOCERA V4 KX DRIVER. (data sheet)**
  - „+ Conforms to Microsoft’s V4 architecture + Supports PCL6 and XPS as PDL + Collaborates with KYOCERA Print Center + Does NOT replace the current KX Driver (V3 architecture)“
- **Release Notes April 29, 2025 (DVD Contents)**
  - „Uninstalling a driver installed from a web package. Solution: The web package installer does not place an uninstall link in the Windows start menu. Please run KmUninstall.exe manually from \Program Files\Kyocera.“
  - „In some cases, alternative drivers cannot be deleted by Uninstaller.“

### Nicht aufgenommen

| Empfehlung | Grund |
|---|---|
| Komponenten des KX-Treibers nur am Server aktualisieren, und nur ohne Freigabe und ohne aktive Verbindungen (Printer Driver User Guide TASKalfa MZ4000i) | Quelle veraltet oder nur für ein anderes Produkt (Handbuch eines einzelnen Modells; betrifft nur die Funktion zum Aktualisieren der Komponenten) |
| Bidirektionale Unterstützung am Anschluss abschalten, weil Citrix den SNMPv3-Verkehr des KX-Treibers nicht richtig weiterleitet | Quelle veraltet oder nur für ein anderes Produkt (die Quelle nennt Citrix 4.3 und KX DRIVER v7.x) |
| Fehlermeldung beim Drucken über den „KX DRIVER for Universal Printing“ in Citrix-Sitzungen (umbenannter Anschluss) | Quelle veraltet oder nur für ein anderes Produkt (Eintrag nur bis zu den Versionshinweisen von 2023; als Abhilfe nennt Kyocera nur Easy Print unter Windows Server 2012) |
| Anschlüsse nach einer Aktualisierung des Kyocera-Universaltreibers kontrollieren (der Anschlussname ändert sich) | setzt eine Änderung voraus, die die Messung nicht stützt (die Messung zeigt nicht, ob der Treiber aktualisiert wurde) |
| Dienst KDService starten, wenn der Status Monitor nicht erscheint | setzt eine Änderung voraus, die die Messung nicht stützt (die Messung erfasst den Status Monitor nicht; die Quelle beschränkt das auf den Druck direkt nach dem Einschalten des Rechners) |
| Easy Print der Terminaldienste als Ausweg beim Anschlussproblem des Universaltreibers | Quelle veraltet oder nur für ein anderes Produkt (Windows Server 2012; nicht der Druckweg des Citrix VDA) |
| Status Monitor steht in Server-Client-Umgebungen am Client nicht zur Verfügung | Quelle veraltet oder nur für ein anderes Produkt (Dokument von 2015 für Windows Server 2000 bis 2012) |
| Treiber mit „Driver Deleter“ oder über die Druckservereigenschaften nach einem Neustart entfernen | Quelle veraltet oder nur für ein anderes Produkt (Versionshinweise von 2009) |
| Funktionen des „Optional Components Wizard“ fehlen auf Terminalservern | keine Herstellerquelle gefunden (nur eine Einschränkung des Funktionsumfangs, ohne Bezug zu den gemessenen Vorfällen) |
| Geschützter Druckmodus von Windows entfernt die Kyocera-Treiber | Quelle veraltet oder nur für ein anderes Produkt (betrifft Arbeitsplätze mit Windows 11 24H2) |
| Umstieg auf Microsoft Universal Print | setzt eine Änderung voraus, die die Messung nicht stützt (Wechsel der Druckarchitektur) |
| Version des KX-Treibers auf dem Citrix-Server muss zu der des Clients passen | keine Herstellerquelle gefunden (das Dokument liegt auf einer nicht erreichbaren Seite von Kyocera) |
| Sicherheitslücke im Installationsprogramm des KX-Treibers | keine Herstellerquelle gefunden (die Seite von Kyocera war nicht erreichbar) |
| Eintrag „KX Driver for Universal Printing“ im Verzeichnis Citrix Ready | keine Herstellerquelle gefunden (steht nicht auf einer Seite von Kyocera) |
| Treiberisolierung und Abstürze der Druckwarteschlange durch Kyocera-Treiber | keine Herstellerquelle gefunden |

Nicht erreichbar: www.kyoceradocumentsolutions.com, die Länderseiten für Großbritannien und die Niederlande und downloads.kyoceradocumentsolutions.com.au. Von dort ist nichts übernommen.

## Brother

Brother dokumentiert wenig, das sich auf Citrix oder Terminalserver bezieht, und nichts zu Typ 3 und Typ 4, zur Treiberisolierung oder zum Zusammenspiel mit dem Citrix-Universaltreiber. Alle Elemente dieses Abschnitts hängen an `driver.vendor.Brother`; die Seiten sind überwiegend für Arbeitsplatzrechner geschrieben, die Spalte „Hinweis“ und das Element selbst sagen das je Seite.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| Citrix® Compatible Device List | <https://support.brother.com/g/b/oscontents.aspx?c=us_ot&lang=en&ossid=40> | 2026-11-13 | `crash.checks[5]` Modell in der Citrix-Liste von Brother nachschlagen<br>`print.checks[14]` Modell in der Citrix-Liste von Brother nachschlagen | Die Liste nennt Modelle mit dem Status „Available“, aber weder ein Citrix-Produkt noch eine Version. Dass zu einem Modell, das fehlt, keine Aussage von Brother zu Citrix vorliegt, ist eine Feststellung des Katalogs, kein Satz von Brother. |
| "User Intervention Required" when attempting to print | <https://help.brother-usa.com/app/answers/detail/a_id/145904/~/user-intervention-required-when-attempting-to-print> | 2026-11-13 | `print.checks[16]` Dienst auf „Automatisch“ und startbar | Die Seite nennt Windows XP bis Windows 10, nicht Windows Server; das Element sagt das. |
| I'm using Windows Vista, Windows 7, Windows 8 or Windows 10 and a network connected Brother machine. The following errors "Error - Sent to Printer", "Sent to Printer" or "Deleting - Printing" appear in the PC Print Queue. | <https://support.brother.com/g/b/faqend.aspx?c=us_ot&lang=en&prod=mfc6490cw_all&faqid=faq00002440_000> | 2026-11-13 | `print.checks[22]` stehende Aufträge an Brother-Geräten<br>`print.remedies[14]` Dienst „Druckwarteschlange“ nach Brother zurücksetzen | Seite vom 14.02.2023; sie gilt für Windows Vista bis 10 und Geräte mit Netzwerkanschluss; beide Elemente sagen das. Der Hinweis, dass die Aufträge aller Benutzer des Servers verloren gehen, stammt nicht von Brother, ebenso wenig die Voraussetzungen, dass sich die Aufträge nicht einzeln löschen lassen und die Benutzer informiert sind. Der Zusatz zum Neustart nicht persistenter Server stammt ebenfalls nicht von Brother (siehe „Zielumgebung“). |
| Use the Universal Printer Driver for BR-Script. (PostScript language emulation) | <https://support.brother.com/g/b/faqend.aspx?c=ca&lang=en&prod=hl4570cdw_all&faqid=faq00002993_000> | 2026-11-13 | `print.remedies[22]` Brother Universal Printer Driver als gemeinsamer Treiber | Seite vom 29.03.2017. Die Liste der Betriebssysteme (help.brother-usa.com, Antwort 67181) endet bei Windows Server 2016; zu Terminalservern oder Citrix sagt die Seite nichts. |
| Uninstall the Brother Software and Drivers (Windows) | <https://support.brother.com/g/b/faqend.aspx?c=us_ot&lang=en&prod=hll2370dw_us&faqid=faq00000071_010> | 2026-11-13 | `print.remedies[23]` Brother-Treiber vollständig entfernen | Seite vom 02.04.2026; sie nennt Windows 7 bis 11. Das „Uninstall Tool“ gibt es laut Seite nicht für jedes Betriebssystem. Das Wartungsfenster in der Voraussetzung stammt nicht von Brother. |

### Belegstellen

- **Citrix® Compatible Device List**
  - „This information pertains to the compatibility status and operational verification under the environmental conditions set by Brother Industries, Ltd., and does not imply a comprehensive "guarantee of operation."“
- **"User Intervention Required" when attempting to print**
  - „Make sure that the Startup Type is set to Automatic . [...] If you are unable to start the Print Spooler service, then there is a problem with your computer or a conflict with another driver. Contact your computer manufacturer or System Admin for support.“
- **I'm using Windows Vista, Windows 7, Windows 8 or Windows 10 and a network connected Brother machine. The following errors "Error - Sent to Printer", "Sent to Printer" or "Deleting - Printing" appear in the PC Print Queue.**
  - „Enter net stop spooler and press Enter. Confirm the Print Spooler Service was stopped. Open the PRINTERS folder. [...] Delete all files then close the folder. Return to Command Prompt . Enter net start spooler and press Enter.“
- **Use the Universal Printer Driver for BR-Script. (PostScript language emulation)**
  - „The Brother Universal Printer Driver is a printer driver for use with Brother machines on your network. You can search for available Brother machines on your network and print documents without installing separate printer drivers. The Brother Universal Printer Driver only supports machines connected to your network.“
- **Uninstall the Brother Software and Drivers (Windows)**
  - „The Uninstall Tool is useful if you want to uninstall the driver which you installed using the Brother CD, Full Driver & Software Package, Add Printer Wizard or Found New Hardware Wizard. You can also completely remove drivers that failed to install.“

### Nicht aufgenommen

| Empfehlung | Grund |
|---|---|
| „Generic PCL“-Treiber von Brother für Citrix MetaFrame und Windows Terminal Server verwenden (What is a "Generic PCL Driver"?, <https://support.brother.com/g/b/faqend.aspx?c=us&faqid=faq00000324_000&lang=en&prod=hl8050n_all>) | Quelle veraltet oder nur für ein anderes Produkt (Seite vom 26.08.2014 mit dem Vermerk „Model discontinued. This page is no longer updated.“; sie nennt Citrix MetaFrame, Windows NT 4.0 und Windows 2000) |
| Bei „Receiving Data“ auf der Anzeige des Geräts: Originaltreiber von Brother und Anschlusstyp (WSD) prüfen | Quelle veraltet oder nur für ein anderes Produkt (gilt nur für Tintengeräte der Reihe MFC-J; das Merkmal ist die Anzeige am Gerät, die die Messung nicht erfasst) |
| Seite „Citrix Presentation Server (Citrix MetaFrame)“ mit dem Generic-PCL-Treiber | Quelle veraltet oder nur für ein anderes Produkt (die Seite ist zurückgezogen) |
| Entwicklerseiten „Printing in the Citrix Environment“ und „Compatibility with Citrix XenApp 7.6“ | Quelle veraltet oder nur für ein anderes Produkt (mobile Drucker auf XenApp 7.6 und Windows Server 2012 R2) |
| Kapitel zum Druckertreiber im Benutzerhandbuch des HL-2030 | Quelle veraltet oder nur für ein anderes Produkt (Handbuch für Windows 95 bis XP) |
| Drucken in einer Umgebung mit freigegebenen Druckern: Treiber des Client-Betriebssystems zuerst auf dem Server installieren | Quelle veraltet oder nur für ein anderes Produkt (für Etikettendrucker an einem Druckserver) |
| Statusmonitor von Brother ausblenden | keine Herstellerquelle gefunden (Brother sagt nichts zum Statusmonitor auf Terminalservern) |
| Erklärung zur Unterstützung von Universal Print | Quelle veraltet oder nur für ein anderes Produkt (betrifft den Cloud-Dienst von Microsoft) |
| Typ 3 und Typ 4, Treiberisolierung, Zusammenspiel mit dem Citrix-Universaltreiber | keine Herstellerquelle gefunden |

Nicht erreichbar: download.brother.com (unter anderem der „Universal Printer Driver Guide“); die Treiberlisten je Modell für Windows Server 2022 auf support.brother.com ließen sich nicht auslesen. Ob Brother einen Treiber für Windows Server 2022 anbietet, ist deshalb je Modell auf der Download-Seite zu prüfen.

## AKI

Die AKI GmbH ist der Hersteller der Drucklösung PrinTaurus. Dass die Zielumgebung mit ihr die Drucker zuordnet und dass ihr PrinTaurus SmartSpread Client auf dem Server installiert ist, ist eine Angabe des Auftraggebers vom 13.11.2026, keine Aussage einer gelesenen Seite. Nach welchen Regeln PrinTaurus die Drucker zuordnet und wie der Client in den Sitzungen läuft, sagt keine gelesene Seite; der Katalog und sein Glossar sagen dazu nichts. Die Website des Herstellers enthält kein öffentliches Handbuch; technische Aussagen stehen nur in den Release Notes 6.2 und 6.4. Elemente zu einem Absturz oder Hänger des Clients hängen an der Bedingung `app.printaurus`; die übrigen stehen als allgemeine Elemente in der Situation `print` und nennen in ihrer Voraussetzung die Version, für die die Release Notes die Aussage machen. In `vendors` steht AKI nicht: die Liste ist für Hersteller von Druckertreibern.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| Release Notes 6.2 deutsch | <https://www.aki-gmbh.com/download/45927/> | 2026-11-13 | `crash.checks[31]` Version des .NET Framework prüfen<br>`print.checks[30]` Bei falschem Standarddrucker, doppelt angezeigten Druckern oder falschen Druckern nach einem Wechsel des En … | Release Notes PrinTaurus 6.2, Version 11 vom 28.03.2022. Kapitel 2 nennt .NET Framework 4.7.2 für die SmartSpread Clients; den Registrierungswert Release und die Zahl 461808 nennt Microsoft („How to determine which .NET Framework versions are installed“). Kapitel 3 nennt den behobenen Fehler beim erzwungenen Standarddrucker, die bekannte Einschränkung (doppelte Anzeige) und als Änderung, dass die Zuordnungen bei einem Wechsel des Endgeräts ohne Neuanmeldung passend gesetzt werden; ob ältere Versionen das nicht taten, sagt AKI nicht, und der Prüfschritt „Bei falschem Standarddrucker, doppelt angezeigten Druckern oder falschen Druckern …“ der Situation `print` sagt es auch nicht. |
| Release Notes PrinTaurus 6.4 | <https://www.aki-gmbh.com/download/47826/> | 2026-11-13 | `crash.checks[32]` Version des PrinTaurus SmartSpread Client mit der Version der übrigen PrinTaurus-Komponenten vergleichen<br>`crash.remedies[12]` PrinTaurus auf eine Version bringen, die AKI noch unterstützt<br>`crash.contacts[3]` Support von AKI: mit Version des SmartSpread Client, Uhrzeit, fehlerhaftem Modul und Fehlercode aus den Bel …<br>`hang.checks[19]` Version des PrinTaurus SmartSpread Client mit der Version der übrigen PrinTaurus-Komponenten vergleichen<br>`print.remedies[24]` PrinTaurus SmartSpread Client und die übrigen PrinTaurus-Komponenten auf denselben Release-Stand bringen, b …<br>`print.remedies[25]` Lokale IPP-Druckerwarteschlangen von PrinTaurus SmartSpread den Benutzern dieses Servers nicht zuweisen | Release Notes PrinTaurus 6.4, Version 3 vom 16.02.2025. Die Regel „alle Komponenten im selben Release“ steht unter den Hinweisen zum Update auf 6.4; die Elemente beschränken sie darauf. Dass die Version unter „Programme und Features“ dieser Release-Stand ist, sagt AKI nicht. Die Release Notes nennen support@aki-gmbh.com; welche Angaben der Support braucht, ist ein eigener Hinweis. Der Zusatz zum Master-Image stammt nicht von AKI. |

### Belegstellen

- **Release Notes 6.2 deutsch**
  - „.NET Framework Mit dieser Version ist das .NET Framework 4.7.2 erforderlich für • Druckserver • Rechner, auf dem die PrinTaurus GUI installiert wird • SmartSpread Webserver • SmartSpread Clients“
  - „Bei der Verwendung von unterschiedlichen Drucker- und Freigabenamen für eine Queue wurde der erzwungene Standarddrucker den Clients nicht korrekt zugewiesen. Dies wurde behoben. (Known issue: die entsprechende Queue wird seitens Windows doppelt dargestellt.)“
  - „Bei Wechsel des (Thin-)Clients ohne Neuanmeldung am Terminalserver werden die Zuordnungen passend zum Client gesetzt.“
- **Release Notes PrinTaurus 6.4**
  - „Prüfen Sie die Systemvoraussetzungen der einzelnen Komponenten! Alle Software-Komponenten sollten zur gleichen Release-Version gehören! Die aktuellen Dateiversionen finden Sie in den Release Notes, die bei Ihnen eingesetzten Versionen in den Landschaftsinformationen der PrinTaurus GUI.“
  - „Zum 31. Dezember 2025 kündigen wir alle PrinTaurus Versionen < 6.2. ab.“
  - „Das Feature ist in dieser Version nur für Fat Clients verfügbar. In Citrix- oder Terminalserver-Umgebungen wird es nicht unterstützt.“
  - „PrinTaurus SmartSpread Client: Behebung von Bugs, die zu doppelter Anzeige von Queues führten, und Optimierung der Anzeige von Queues, wenn Queuename und Freigabename nicht identisch sind.“

### Nicht aufgenommen

| Empfehlung | Grund |
|---|---|
| Wie und wann der Client die Drucker zuordnet (Anmeldung, Wiederverbindung, Regeln), Treiber auf dem gemessenen Server, Hinweise zu Master-Image und nicht persistenten Servern, Dauer und Protokoll der Zuordnung, Verhältnis zu den Druckrichtlinien von Citrix | keine Herstellerquelle gefunden (die Installationsanleitung ist nicht veröffentlicht; der allgemeine Schritt zur Zuordnung ist ein eigener Hinweis, siehe Abschnitt WorkerPerf) |
| Aliasnamen für Verbunde: Hochverfügbarkeit entfällt, Wartungsmodus abgeschaltet (Release Notes 6.4) | setzt eine Änderung voraus, die die Messung nicht stützt (Einrichtung der Druckserver, auf dem gemessenen Server nicht sichtbar) |
| Hochverfügbarkeit der Drucker-Mappings über Master- und Backup-Server (Produktseite) | setzt eine Änderung voraus, die die Messung nicht stützt (die Seite spricht von Client-PCs und nennt weder SmartSpread noch Terminalserver) |
| Verzögerungen beim Speichern vieler IPP-Anschlüsse, CleanJob, TLS-Einstellungen, SAP-Anbindung und weitere Komponenten der Druckserver | Quelle veraltet oder nur für ein anderes Produkt (Komponenten der Druckserver, nicht des gemessenen Servers) |

Nicht erreichbar: die Seiten „FAQ“ und „Service & Support“ des Herstellers (HTTP 404), www.printaurus.com und die bei Kyocera liegende Broschüre zur Hochverfügbarkeit. Von dort ist nichts übernommen.

## Citrix – Workspace Environment Management

In der Zielumgebung richtet Citrix Workspace Environment Management (WEM) die Benutzerumgebung ein. Die Elemente nennen WEM als möglichen Beteiligten an einem Prozessor- oder Arbeitsspeicher-Engpass: Der CPU-Spitzenschutz senkt die Priorität eines Prozesses, die Speicheroptimierung gibt Arbeitsspeicher untätiger Prozesse frei. Die wirksamen Einstellungen von WEM sind auf dem Server nicht dokumentiert lesbar; die Schritte verweisen deshalb auf das Ereignisprotokoll des Agenten und auf die WEM-Konsole.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| CPU Management (WEM current release) | <https://docs.citrix.com/us/en/workspace-environment-management/current-release/user-interface-description/system-optimization/cpu-management.html> | 2026-11-13 | `cpu.remedies[2]` CPU-Spitzenschutz von Citrix Workspace Environment Management einschalten oder seine Messzeit anpassen | Citrix sagt, der Schutz sei nicht dafür gedacht, die Gesamtlast zu senken, und rät, die Messzeit so zu wählen, dass andere Benutzer desselben Servers nicht leiden. Eine Regel, wann ein Prozess auszunehmen ist, nennt die Seite nicht. Die Einstellung liegt in der WEM-Konsole, nicht auf dem Server; ein Zusatz zum Master-Image entfällt deshalb. |
| Memory Management (WEM current release) | <https://docs.citrix.com/us/en/workspace-environment-management/current-release/user-interface-description/system-optimization/memory-management.html> | 2026-11-13 | `memory.remedies[5]` Leerlaufgrenze der Speicheroptimierung von Citrix Workspace Environment Management prüfen | Standard der Leerlaufgrenze laut Seite 1 %. Dass Anwendungen nach einer Pause träge reagieren, steht nicht auf der Seite: Es ist die Voraussetzung, unter der der Katalog den Schritt vorschlägt. |
| Agent event logs (WEM current release) | <https://docs.citrix.com/us/en/workspace-environment-management/current-release/reference/agent-event-logs.html> | 2026-11-13 | `cpu.checks[13]` Im Ereignisprotokoll des WEM-Agenten nachsehen, ob der CPU-Spitzenschutz von Citrix Workspace Environment M …<br>`memory.checks[12]` Im Ereignisprotokoll des WEM-Agenten nachsehen, ob die Speicheroptimierung von Citrix Workspace Environment … | Die Seite nennt die Ereignisse 7001 und 7002 (CPU-Spitzenschutz) und 8001 bis 8003 (Speicheroptimierung). Die Bezeichnung des Protokolls „WEM Agent Service“ stammt von den Seiten „CPU Management“ und „System optimization“; den genauen Namen des Protokolls dokumentiert Citrix nicht (siehe „Auf dem Zielsystem zu bestätigen“). Was die Speicheroptimierung mit dem Arbeitsspeicher untätiger Prozesse tut, steht auf der Seite „Memory Management“. |

### Belegstellen

- **CPU Management (WEM current release)**
  - „CPU spike protection is not designed to reduce overall CPU usage. It is designed to reduce the impact on user experience by processes that consume an excessive percentage of CPU Usage.“
  - „We recommend that you experiment with the sample time to decide the optimal value for your environment that does not affect other users logged on to the same VDA.“
- **Memory Management (WEM current release)**
  - „The default is 1%. We recommend that you do not use a value greater than 5%. Otherwise, a process being actively used can be mistaken for idle, causing its memory to be released.“

### Nicht aufgenommen

| Empfehlung | Grund |
|---|---|
| Agent-Cache an einem beständigen Ort, benötigte Dienste auf „Automatisch“, Agent nicht per Skript starten oder anhalten, Einstellungen der Anmeldung (SyncForegroundPolicy, GpNetworkStartTimeoutPolicyValue), VUEMAppCmd, Cache-Aktualisierung | beschreibt einen Zustand des Servers, keinen Schritt zu einem Vorfall (gehört zum Zustandsbild) |
| Virenschutz vom CPU-Spitzenschutz ausnehmen und ihm niedrige I/O-Priorität geben | setzt eine Änderung voraus, die die Messung nicht stützt (die Einstellungen von WEM sind auf dem Server nicht lesbar) |
| CPU-Begrenzung (Clamping) nur für Ausnahmen, Optimierung getrennter Sitzungen, Citrix Optimizer bei jedem Neustart, schnelles Abmelden, asynchrone Verarbeitung von Druckern und Laufwerken | setzt eine Änderung voraus, die die Messung nicht stützt (Erklärungen ohne Merkmal, das die Messung zeigt) |
| Intelligente CPU-Optimierung startet Prozesse mit hoher Priorität (CTX233218) | Quelle veraltet oder nur für ein anderes Produkt (Artikel ohne Datum mit der Wortwahl der alten Konsole; die aktuelle Seite sagt das nicht) |
| „Launch agent on reconnection“ eingeschaltet lassen | keine Herstellerquelle gefunden (das Zitat steht auf der Seite unter einer anderen Einstellung) |
| CPU-Spitzenschutz für das klassische Teams (Seite „Optimization for Microsoft Teams (Classic)“) | Quelle veraltet oder nur für ein anderes Produkt (für das neue Teams nicht dokumentiert; der allgemeine Vorschlag zum CPU-Spitzenschutz ist aufgenommen) |

Für die Verzögerung ohne Engpass ist kein Element zu WEM aufgenommen: Keine der gelesenen Seiten verbindet eine Einstellung von WEM mit einem Merkmal, das die Messung dort zeigt.

## Microsoft – Edge und WebView2

Microsoft Edge ist in der Zielumgebung der einzige Browser; die WebView2-Runtime (msedgewebview2.exe) nutzen Teams und Office für ihre Web-Oberflächen. Die Elemente hängen an den Bedingungen `app.edge` und `app.webview2` aus `src/apps.json`.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| Fix high CPU or memory usage in Microsoft Edge | <https://learn.microsoft.com/en-us/troubleshoot/microsoft-edge/performance/edge-high-cpu-memory> | 2026-11-13 | `cpu.checks[3]` Im Browser-Task-Manager von Microsoft Edge nachsehen, welcher Tab, welche Erweiterung oder welcher Hilfspro …<br>`cpu.checks[4]` Klären, ob der Benutzer Videos, WebGL- oder Canvas-Inhalte im Browser nutzte<br>`cpu.remedies[3]` Erweiterungen von Microsoft Edge abschalten und einzeln wieder einschalten, bis die verursachende gefunden ist<br>`cpu.remedies[4]` Schlafende Tabs in Microsoft Edge einschalten<br>`cpu.remedies[5]` Weiterlaufen von Erweiterungen und Apps im Hintergrund nach dem Schließen von Microsoft Edge abschalten<br>`memory.checks[3]` Im Browser-Task-Manager von Microsoft Edge nachsehen, welcher Tab oder welche Erweiterung den Arbeitsspeich … | Stand der Seite 2026-06-03. Die Namen der Richtlinien SleepingTabsEnabled und BackgroundModeEnabled stehen auf den Richtlinienseiten von Microsoft Edge. Eine Schwelle für die Zeit bis zum Schlafen nennt der Katalog nicht (Microsoft nennt 900 Sekunden nur als Standard). Dass Edge ohne Grafikkarte in Software rendert, sagt die Seite nicht; der Prüfschritt „Klären, ob der Benutzer Videos, WebGL- oder Canvas-Inhalte im Browser nutzte …“ der Situation `cpu` fragt deshalb nur nach den Inhalten. |
| Microsoft Edge for Virtual desktop infrastructure (VDI) | <https://learn.microsoft.com/en-us/deployedge/edge-for-virtualized-desktop-infrastructure> | 2026-11-13 | `memory.checks[4]` Arbeitsspeicher je Benutzer mit der Angabe von Microsoft für Edge auf VDI vergleichen<br>`profile.checks[5]` Prüfen, ob Richtlinien die Benutzerdaten oder den Cache von Microsoft Edge auf eine Freigabe legen | Stand 2026-11-03. Die Seite spricht allgemein von „VDI“, nicht von Servern mit mehreren Sitzungen. Ob Daten in einem Profilcontainer als umgeleitet oder geroamt gelten, sagt Microsoft nicht; das Element zu den Benutzerdaten sagt das. |
| Microsoft Edge stops responding or doesn't start | <https://learn.microsoft.com/en-us/troubleshoot/microsoft-edge/performance/edge-crashes-fails-to-launch> | 2026-11-13 | `crash.checks[19]` Die von Microsoft genannten häufigen Ursachen prüfen<br>`hang.checks[12]` Die von Microsoft genannten häufigen Ursachen prüfen | Stand 2026-06-03. Die Seite nennt Ereignisse der Quelle „Application Error“ zu msedge.exe; eine Ereignisnummer nennt sie nicht. |
| Enable Process Isolation (ProcessIsolationEnabled) | <https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/processisolationenabled> | 2026-11-13 | `crash.checks[20]` Einstellung „Process Isolation“ von Microsoft Edge feststellen | Ab Microsoft Edge 151; ohne Richtlinie wird die Funktion laut Microsoft schrittweise eingeführt. Komponenten von Citrix nennt Microsoft nicht. |
| Configure auto discard sleeping tabs (AutoDiscardSleepingTabsEnabled) | <https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/autodiscardsleepingtabsenabled> | 2026-11-13 | `memory.remedies[2]` Automatisches Verwerfen schlafender Tabs in Microsoft Edge nicht abschalten | Ab Microsoft Edge 120; ohne Richtlinie ist das Verwerfen eingeschaltet. |
| Set limit on megabytes of memory a single Microsoft Edge instance can use (TotalMemoryLimitMb) | <https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/totalmemorylimitmb> | 2026-11-13 | `memory.remedies[3]` Speichergrenze je Instanz von Microsoft Edge setzen | Ab Microsoft Edge 80. Microsoft beschreibt die Richtlinie, empfiehlt sie aber nicht; Werte unter 1024 werden auf 1024 aufgerundet. |
| Microsoft Edge - Update policies | <https://learn.microsoft.com/en-us/deployedge/microsoft-edge-update-policies> | 2026-11-13 | `crash.checks[21]` Version der WebView2-Runtime feststellen<br>`crash.remedies[8]` WebView2-Runtime auf den aktuellen Stand bringen | Abschnitt „Update (WebView)“, Microsoft Edge Update ab 1.3.127.1. Für nicht persistente Maschinen nennt Microsoft auf der Seite zu Edge für VDI als bewährtes Vorgehen, automatische Updates abzuschalten und über das Master-Image zu aktualisieren: Der Stand der Runtime ist dann der des Master-Image, und beide Elemente sagen das. |
| WebView2 end-user FAQ | <https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/end-user-faq> | 2026-11-13 | `cpu.checks[6]` Feststellen, welche Anwendung ‹Anwendung› nutzt<br>`memory.checks[6]` Feststellen, welche Anwendung ‹Anwendung› nutzt | Seite von 2023. Teams und Outlook nennt Microsoft als Beispiele für Anwendungen, die WebView2 nutzen; „in den meisten Fällen“ bezieht sich auf die Art der Nutzung von WebView2. |
| Enterprise management of WebView2 | <https://learn.microsoft.com/en-us/deployedge/webview2-enterprise> | 2026-11-13 | `cpu.checks[7]` Einordnen, welche Einstellungen auf ‹Anwendung› wirken | Abschnitt „Browser policies vs. WebView2 policies“. |
| Prevent security tools from blocking WebView2 apps | <https://learn.microsoft.com/en-us/deployedge/webview2-security-tools> | 2026-11-13 | `cpu.remedies[7]` Gezielte Scan-Ausschlüsse für die Programmdateien der WebView2-Runtime und ihren Benutzerdatenordner prüfen<br>`crash.checks[22]` Prüfen, ob AppLocker die WebView2-Runtime oder die Anwendung blockiert, die sie nutzt<br>`crash.checks[23]` Prüfen, ob Software Module in die Prozesse von WebView2 lädt<br>`hang.checks[13]` Prüfen, ob AppLocker die WebView2-Runtime oder die Anwendung blockiert, die sie nutzt | Den Herausgeber, für den eine Regel gelten soll, nennt die Seite nicht. Die Zustimmung der Verantwortlichen für die Sicherheit und der Ort der Änderung stammen nicht von Microsoft. |

### Belegstellen

- **Fix high CPU or memory usage in Microsoft Edge**
  - „One or more msedge.exe processes consistently use a large share of CPU power while the browser is idle. [...] To find the responsible tab, extension, subframe, or utility process, sort by CPU or Memory.“
  - „Extensions can cause high CPU usage. [...] If usage returns to normal, turn extensions back on one at a time to find the one that causes the problem.“
  - „If Edge continues to use excessive CPU after you close all windows, background processes are still running. [...] Turn off Continue running background extensions and apps when Microsoft Edge is closed.“
  - „Software rendering of video, WebGL, and canvas content increases CPU usage.“
- **Microsoft Edge for Virtual desktop infrastructure (VDI)**
  - „The following minimum requirements are recommended for deploying Microsoft Edge on a VDI environment: [...] RAM – 1 GB per User [...] Large and complex web applications and extensions need more memory and processing capability“
  - „Redirecting or roaming any UDF content is not supported and should be avoided, as it can cause reliability and performance issues related with many state-preserving files, databases, and caches.“
- **Microsoft Edge stops responding or doesn't start**
  - „The article describes common causes, such as leftover background processes, graphics driver problems, a corrupted user profile, and a broken installation.“
- **Enable Process Isolation (ProcessIsolationEnabled)**
  - „Enabling Process Isolation may cause incompatibilities with third party applications that rely on being able to inject or tamper with Microsoft Edge's processes, such as antivirus, screen reader or window manager applications.“
- **Configure auto discard sleeping tabs (AutoDiscardSleepingTabsEnabled)**
  - „Auto discard reduces memory usage by discarding inactive background tabs. When the user switches back to a discarded tab, the tab is reloaded. By default, auto discard is turned on.“
- **Set limit on megabytes of memory a single Microsoft Edge instance can use (TotalMemoryLimitMb)**
  - „If you enable this policy, the browser starts to discard tabs to save memory once the limitation is exceeded. However, there's no guarantee that the browser is always running under the limit.“
- **Microsoft Edge - Update policies**
  - „Automatic updates are enabled by default. Disabling automatic updates for the WebView2 Runtime might cause compatibility issues with applications that depend on this component.“
- **WebView2 end-user FAQ**
  - „In most cases, any extra memory or CPU usage is due to how WebView2 is being used, not WebView2 itself. If the application is rendering non-optimized web content, then the WebView2 control might consume more resources.“
- **Enterprise management of WebView2**
  - „Browser policies are separate from WebView2 policies. Policies for Microsoft Edge don't apply to the WebView2 Runtime and WebView2 apps.“
- **Prevent security tools from blocking WebView2 apps**
  - „AppLocker deny rules; policies that explicitly block execution. [...] Allowlist the WebView2 Runtime (msedgewebview2.exe) and host executables.“
  - „Dynamic-link library (DLL) injection into renderer or Graphics Processing Unit (GPU) processes breaks Chromium's sandboxing model, and commonly causes renderer crashes.“
  - „Slow startup due to deep real-time scanning of the WebView2 Runtime and the user data folder (UDF). [...] Configure scoped exclusions for WebView2 Runtime binaries and user data folder (UDF); avoid broad exclusions.“

### Nicht aufgenommen

| Empfehlung | Grund |
|---|---|
| 2 bis 4 Prozessorkerne je Benutzer für Edge auf VDI | setzt eine Änderung voraus, die die Messung nicht stützt (die Angabe gilt für VDI allgemein und ist auf Servern mit mehreren Sitzungen kaum erreichbar; die Angabe zum Arbeitsspeicher ist aufgenommen) |
| Automatische Updates auf nicht persistenten Maschinen abschalten, Prüfabstand des Updaters, Erststart-Erlebnis ausblenden, Startup boost, On-Premises-Sync, Ordner für Cache und Benutzerdaten nicht auf die Wurzel eines Laufwerks | beschreibt einen Zustand des Servers, keinen Schritt zu einem Vorfall (gehört zum Zustandsbild) |
| Eigene Cachegröße (DiskCacheSize) entfernen | setzt eine Änderung voraus, die die Messung nicht stützt |
| msedge.exe nicht vom Citrix-Hooking ausnehmen (CTX695046) | widerspricht einer anderen Herstellerquelle (Microsoft nennt für ältere Versionen von Citrix das Abschalten der Hooks als Umgehung; der Artikel von Citrix behandelt nur Virtual Loopback) |
| Citrix-Richtlinien, die das Darstellen sehr großer HTML-Tabellen bremsen | setzt eine Änderung voraus, die die Messung nicht stützt (eine Verzögerung ohne Engpass nennt keine Anwendung als Verursacher; die Bedingung `app.edge` gilt dort nicht) |
| Berechtigungen des Ordners der WebView2-Runtime, Freigabe von msedgewebview2.exe für die Teams-Optimierung vor VDA 2402 | Quelle veraltet oder nur für ein anderes Produkt |

## Citrix – Browser und Teams

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| Browser content redirection (CVAD 2402 LTSR) | <https://docs.citrix.com/en-us/citrix-virtual-apps-desktops/2402-ltsr/multimedia/browser-content-redirection.html> | 2026-11-13 | `cpu.remedies[6]` Browser Content Redirection von Citrix für die betroffenen Seiten prüfen | Seite der Version 2402 LTSR. Laut Citrix muss die HTML5-Videoumleitung abgeschaltet sein, wenn die Umleitung genutzt wird. |
| Optimization for Microsoft Teams (New) | <https://docs.citrix.com/us/en/citrix-virtual-apps-desktops/current-release/multimedia/opt-ms-teams-new.html> | 2026-11-13 | `cpu.checks[10]` Prüfen, ob Teams in der Sitzung von ‹Benutzer› mit Medienoptimierung lief<br>`memory.checks[9]` Prüfen, ob Teams in der Sitzung von ‹Benutzer› mit Medienoptimierung lief | Abschnitt „Interoperability and roaming“. Wo Teams den Stand der Optimierung anzeigt, nennt diese Seite nicht (siehe „Auf dem Zielsystem zu bestätigen“). |
| Optimization for Microsoft Teams (Classic) | <https://docs.citrix.com/us/en/citrix-virtual-apps-desktops/current-release/multimedia/opt-ms-teams.html> | 2026-11-13 | `memory.checks[11]` Größe des Servers für Teams einordnen<br>`disk.checks[4]` Bedarf von Teams an Datenträgerzugriffen einordnen | Messung von Citrix mit dem klassischen Teams unter Windows Server 2019 (Version 2106), ohne Medien; beide Elemente sagen, dass es eine Messung mit dem klassischen Teams ist. Die Angabe „512 bis 1024 MB je Benutzer“ der Seite meint Speicherplatz, nicht Arbeitsspeicher, und ist nicht übernommen. |
| Enable roaming for the new Microsoft Teams (Profile Management) | <https://docs.citrix.com/us/en/profile-management/current-release/how-to/enable-new-teams-roaming.html> | 2026-11-13 | `profile.checks[4]` Ausschlussliste des Profilcontainers auf Ordner von Teams prüfen | Abschnitt „Required settings for the container-based profile solution“. Microsoft nennt für nicht persistente Umgebungen eine eigene Ausschlussliste; für den Profilcontainer von Citrix gilt die Aussage von Citrix. |

### Belegstellen

- **Browser content redirection (CVAD 2402 LTSR)**
  - „Client fetch client render scenario offloads all the network, CPU and RAM usage from Citrix VDA to the client and is the most optimal way to configure Browser content redirection“
- **Optimization for Microsoft Teams (New)**
  - „If the New VDI solution for Teams fails, Teams falls back directly to standard audio/video redirection rather than to WebRTC. A Teams app restart is required to re-run the selection and choose the optimization that fits.“
- **Optimization for Microsoft Teams (Classic)**
  - „40% scalability impact with Microsoft Teams Workload (81 users), when compared to Baseline (137 users).“
  - „20% extra memory required with Microsoft Teams Workload, when compared to Baseline.“
  - „~50% increase in IOPS write, ~100% increase in IOPS reads. Microsoft Teams can have a significant impact in an environment with slower storage.“
- **Enable roaming for the new Microsoft Teams (Profile Management)**
  - „Don't follow Microsoft's recommendations to exclude folders. Ensure that no folders under AppData\Local\Packages\MSTeams_8wekyb3d8bbwe are in the container exclusion list.“

## Microsoft – Office

In der Zielumgebung ist Office LTSC 2024 installiert. Die Elemente hängen an zwei Bedingungen aus `src/apps.json`: `app.office` für Word, Excel, PowerPoint, OneNote und Access, `app.outlook` für Outlook. Schritte, die nur für Outlook gelten, stehen nur unter `app.outlook`. Schritte, die für jedes Office-Programm gelten (Add-ins, 32 oder 64 Bit, Stand der Aktualisierung), stehen zweimal im Katalog, wortgleich unter `app.office` und unter `app.outlook`, weil ein Prozess nur zu einer Anwendung der Liste gehört; in den Tabellen stehen deshalb beide Stellen. Mehrere Seiten sind für Microsoft 365 Apps oder für Outlook 2016 geschrieben; die Spalte „Hinweis“ und das Element sagen das.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| Performance recommendations for Microsoft 365 Apps on Windows 10 | <https://learn.microsoft.com/en-us/microsoft-365-apps/best-practices/performance-recommendations> | 2026-11-13 | `cpu.checks[8]` Add-ins von ‹Anwendung› prüfen<br>`cpu.checks[9]` Add-ins von ‹Anwendung› prüfen (für Outlook)<br>`cpu.remedies[8]` Add-ins von ‹Anwendung›, die nicht gebraucht werden, entfernen und die übrigen aktuell halten<br>`cpu.remedies[9]` Add-ins von ‹Anwendung›, die nicht gebraucht werden, entfernen und die übrigen aktuell halten (für Outlook)<br>`memory.checks[7]` Add-ins von ‹Anwendung› prüfen<br>`memory.checks[8]` Add-ins von ‹Anwendung› prüfen (für Outlook)<br>`crash.checks[24]` Add-ins von ‹Anwendung› als Ursache prüfen<br>`crash.checks[27]` Add-ins von ‹Anwendung› als Ursache prüfen (für Outlook) | Die Seite gilt für Microsoft 365 Apps unter Windows 10; zu Office LTSC 2024 sagt Microsoft nur, dass Add-ins früherer Versionen voraussichtlich funktionieren. Die Prüfschritte sagen, wofür Microsoft den Test beschreibt. Die Rücksprache mit den Benutzern und der Ort der Änderung stammen nicht von Microsoft. |
| Add-ins are user re-enabled after being disabled by Office programs | <https://learn.microsoft.com/en-us/troubleshoot/outlook/performance/add-ins-are-user-re-enabled-after-being-disabled> | 2026-11-13 | `hang.checks[14]` Nachsehen, ob Office ein Add-in von Outlook wegen langsamer Ausführung abgeschaltet hat und wie lange die A … | Die Seite nennt die Ereignisse 45 und 59 im Protokoll „Anwendung“. |
| You may experience application pauses if you have a large Outlook data file | <https://learn.microsoft.com/en-us/troubleshoot/outlook/performance/application-pauses-if-you-have-large-data-file> | 2026-11-13 | `profile.checks[3]` Größe der OST-Datei von Outlook und Zahl der Elemente je Ordner prüfen<br>`profile.remedies[1]` Lokale Postfachdaten von Outlook verkleinern<br>`hang.checks[15]` Größe der OST-Datei von Outlook bei den betroffenen Benutzern prüfen | Die Zahlen zu Elementen je Ordner stehen auf der Seite „Outlook performance issues in a Cached Exchange Mode .ost or .pst file“. Die Werte der Richtlinie für den Zeitraum des Cache-Modus sind auf keiner gelesenen Seite belegt; der Katalog nennt deshalb keinen Wert. |
| Limits to using personal folders files over LAN and WAN links | <https://learn.microsoft.com/en-us/troubleshoot/outlook/data-files/limits-using-pst-files-over-lan-wan> | 2026-11-13 | `share.checks[2]` Prüfen, ob PST- oder OST-Dateien von Outlook direkt auf einer Freigabe liegen | Microsoft nennt als Bedingungen eine Verbindung mit hoher Bandbreite und geringer Latenz und ein Outlook je Datei. |
| Outlook not responding error or Outlook freezes when you open a file or send mail | <https://learn.microsoft.com/en-us/troubleshoot/outlook/performance/outlook-not-responding-error-or-outlook-freezes> | 2026-11-13 | `hang.checks[16]` Prüfen, ob der Ordner AppData auf eine Freigabe umgeleitet ist und ob die Schutzsoftware ein Add-in oder ei … | Die Seite nennt beide Ursachen getrennt; das Element fasst sie zusammen. |
| Plan and configure Cached Exchange Mode in Outlook 2016 for Windows | <https://learn.microsoft.com/en-us/microsoft-365-apps/outlook/configuration/cached-exchange-mode> | 2026-11-13 | `disk.checks[3]` Einordnen, ob die Last vom Cache-Modus von Outlook kommt | Für Outlook 2016 geschrieben; ob die Aussage für Outlook LTSC 2024 gilt, sagt die Seite nicht. Das Element sagt das. |
| Overview of Office LTSC 2024 | <https://learn.microsoft.com/en-us/office/ltsc/2024/overview> | 2026-11-13 | `crash.checks[25]` Feststellen, ob Office als 32-Bit- oder 64-Bit-Version installiert ist<br>`crash.checks[28]` Feststellen, ob Office als 32-Bit- oder 64-Bit-Version installiert ist (für Outlook) | Dass die 64-Bit-Version mehr Arbeitsspeicher nutzen kann, steht nicht auf der Seite und ist nicht übernommen. |
| Update Office LTSC 2024 | <https://learn.microsoft.com/en-us/office/ltsc/2024/update> | 2026-11-13 | `crash.remedies[9]` Office auf den aktuellen Stand bringen<br>`crash.remedies[10]` Office auf den aktuellen Stand bringen (für Outlook) | Wie alt eine Version sein darf, sagt Microsoft nicht. Der Zusatz zum Master-Image stammt nicht von Microsoft. |

### Belegstellen

- **Performance recommendations for Microsoft 365 Apps on Windows 10**
  - „Add-ins are one of the most common causes of poor app performance, especially at larger organizations.“
- **Add-ins are user re-enabled after being disabled by Office programs**
  - „However, if an add-in causes performance issues in an Office program, an Event ID: 59 is added to the Application Event log.“
- **You may experience application pauses if you have a large Outlook data file**
  - „More than 10 GB: When the .ost file reaches this size, short pauses begin to occur on most hardware.“
- **Limits to using personal folders files over LAN and WAN links**
  - „Microsoft will not assist in troubleshooting slow performance due to networked.pst or .ost files.“
- **Outlook not responding error or Outlook freezes when you open a file or send mail**
  - „Outlook stores certain data, such as email signatures and the spelling checker dictionary, in the AppData folder. If the network is performing slowly, Outlook must wait for read and write operations to the AppData directory to finish.“
  - „If your antivirus software includes integration with Outlook, you may experience performance issues.“
- **Plan and configure Cached Exchange Mode in Outlook 2016 for Windows**
  - „When you configure a computer running RDS to use Cached Exchange Mode, be sure to consider the additional storage space and disk I/O that are required for multiple client accesses.“
- **Overview of Office LTSC 2024**
  - „Office LTSC 2024 is available in both 32-bit and 64-bit versions. We recommend 64-bit on devices with 4 GB or more of memory. However, you should assess application compatibility and other factors that might require the use of the 32-bit version.“
- **Update Office LTSC 2024**
  - „To minimize the size of the updates that need to be downloaded, we recommend keeping Office up to date.“

### Nicht aufgenommen

| Empfehlung | Grund |
|---|---|
| Lizenzierung, Update-Kanal, Rearm vor dem Erstellen des Abbilds, Updates nur über das Master-Image | beschreibt einen Zustand des Servers, keinen Schritt zu einem Vorfall (gehört zum Zustandsbild) |
| Outlook-Suche: Suchindex, Windows-Suchdienst, EnablePerUserCatalog, Standard-Suchbereich | setzt eine Änderung voraus, die die Messung nicht stützt (Verursacher wäre der Suchdienst, keine Office-Anwendung; die Seiten von Citrix nennen Outlook LTSC 2024 nicht, die Seite von Microsoft zu RDSH und VDI ist für Office 2016 geschrieben) |
| Outlook im Cache-Modus mit Profilcontainer als Leistungsgewinn | beschreibt einen Zustand des Servers, keinen Schritt zu einem Vorfall (die Quelle nennt FSLogix) |
| Zeiten, ab denen Start und Öffnen bedenklich sind (Outlook über 20 Sekunden, Word, Excel und PowerPoint über 10 Sekunden) | setzt eine Änderung voraus, die die Messung nicht stützt (die Messung erfasst keine Startdauer; eine Verzögerung ohne Engpass nennt keine Anwendung als Verursacher) |

## Microsoft – Teams

In der Zielumgebung läuft der neue Teams-Client mit Medienoptimierung: Audio, Video und Bildschirmfreigabe werden auf dem Endgerät verarbeitet. Die Elemente hängen an der Bedingung `app.teams`; der erste Schritt zu Teams fragt immer, ob die Sitzung optimiert lief (Quelle: Citrix, Abschnitt „Citrix – Browser und Teams“).

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| Install Teams for Virtualized Desktop Infrastructure (VDI) | <https://learn.microsoft.com/en-us/microsoftteams/teams-client-vdi-requirements-deploy> | 2026-11-13 | `cpu.checks[5]` Prüfen, ob der Benutzer Microsoft Teams im Browser statt im Teams-Client nutzte<br>`cpu.remedies[10]` Rückfall von Teams in die nicht optimierte Verarbeitung abschalten oder auf Audio begrenzen<br>`memory.remedies[4]` Rückfall von Teams in die nicht optimierte Verarbeitung abschalten oder auf Audio begrenzen<br>`crash.checks[30]` Stand der Unterstützung von Teams auf dem Betriebssystem des Servers einordnen | Stand 2026-08-25. DisableFallback gilt ab Teams 24257; ob der Rückfall abgeschaltet wird, überlässt Microsoft dem Betreiber. Dieselbe Seite nennt Oktober 2026 als Ende der Unterstützung auf Windows Server 2022 und führt Windows Server 2022 in der Tabelle der Anforderungen weiter; der Prüfschritt „Stand der Unterstützung von Teams auf dem Betriebssystem des Servers einordnen …“ der Situation `crash` nennt beides. Der Zusatz zum Master-Image stammt nicht von Microsoft. |
| New VDI solution for Teams | <https://learn.microsoft.com/en-us/microsoftteams/vdi-2> | 2026-11-13 | `cpu.checks[11]` Klären, ob der Benutzer an einer Großveranstaltung<br>`cpu.checks[12]` Klären, ob der Benutzer seinen Bildschirm geteilt hat<br>`cpu.remedies[11]` Bildrate der vom Server kodierten Bildschirmfreigabe begrenzen<br>`memory.checks[10]` Klären, ob der Benutzer an einer Großveranstaltung | Stand 2026-11-12. Die Messwerte von Microsoft zur Bildschirmfreigabe stammen von einer virtuellen Maschine mit einem Benutzer und vier Prozessoren; der Katalog nennt deshalb keine Zahl. Die vom Server kodierte Bildschirmfreigabe ist für Windows-Endgeräte laut Seite in der Vorschau. |
| Include or exclude Teams from antivirus or DLP applications | <https://learn.microsoft.com/en-us/troubleshoot/microsoftteams/teams-administration/include-exclude-teams-from-antivirus-dlp> | 2026-11-13 | `crash.checks[29]` Prüfen, ob Schutz-, Überwachungs- oder DLP-Software in Teams eingreift<br>`crash.remedies[11]` Prozesse von Teams in der Schutzsoftware ausnehmen, wie Microsoft sie nennt<br>`hang.checks[18]` Prüfen, ob Schutz-, Überwachungs- oder DLP-Software in Teams eingreift | Stand 2026-11-09. Microsoft spricht von Schutzsoftware anderer Hersteller; die Elemente sagen das. Die Zustimmung der Verantwortlichen für die Sicherheit stammt nicht von Microsoft. |

### Belegstellen

- **Install Teams for Virtualized Desktop Infrastructure (VDI)**
  - „To disable fallback mode, set the value to 1. To enable audio only, set the value to 2. If the value isn't present or is set to 0 (zero), fallback mode is enabled.“
  - „Teams for Web isn't supported in VDI environments, so performance and reliability may be negatively impacted if used in VDI.“
  - „End-of-support dates for Windows Server 2019 and Windows Server 2022 are October 2025 and October 2026 respectively.“
- **New VDI solution for Teams**
  - „Attendees joining these types of events aren't optimized (WebRTC or SlimCore), hence they default to server-side rendering, incurring in high resource consumption on the virtual desktop (mostly CPU, RAM, and virtual channel bandwidth).“
  - „If the user clicks on the "optimize" button in the sharing toolbar (intended for sharing videos), Teams attempts to ramp up to 15 fps and a higher CPU impact is expected. Capping MaxFPS somewhere between 5-10 can help reduce impact in this scenario.“
- **Include or exclude Teams from antivirus or DLP applications**
  - „These tools can degrade Teams client performance and also cause the app to exit unexpectedly.“

### Nicht aufgenommen

| Empfehlung | Grund |
|---|---|
| Unterstützte Versionen des VDA, Freigabeliste der virtuellen Kanäle, Dienste der Teams-Umleitung, Proxy-Ausnahme, Bereitstellung im Master-Image, Auto-Update, Besprechungs-Add-in, Autostart | beschreibt einen Zustand des Servers, keinen Schritt zu einem Vorfall (gehört zum Zustandsbild) |
| Ausschlussliste von Microsoft für die Zwischenspeicher von Teams | widerspricht einer anderen Herstellerquelle (für den Profilcontainer von Citrix rät Citrix, ihr ohne lokale Zwischenspeicherung nicht zu folgen; die Aussage von Citrix ist aufgenommen) |
| AppLocker: Herausgeberregeln für Teams | Quelle veraltet oder nur für ein anderes Produkt (Seite von 2024 für das klassische Teams) |
| Windows-Updates gegen Fehler bei der Registrierung von Teams | Quelle veraltet oder nur für ein anderes Produkt (der Abschnitt gilt für FSLogix) |
| Abkündigung der WebRTC-Optimierung, geringere CPU-Last ab VDA 2511 | setzt eine Änderung voraus, die die Messung nicht stützt (Hinweise für die Planung) |

## Carl Stalhood (Empfehlung aus der Praxis)

Die Anleitungen von Carl Stalhood (carlstalhood.com) sind eine Quelle aus der Praxis, keine Dokumentation eines Herstellers. Jedes Element aus dieser Quelle nennt sie in `source` mit dem Zusatz „Empfehlung aus der Praxis“ und ist im Text als Empfehlung aus der Praxis oder als Aussage der Praxisquelle formuliert, nie als Empfehlung des Herstellers. Die Seiten beschreiben Citrix-Versionen bis 2411; neuere deckt keine von ihnen ab.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| Citrix Virtual Delivery Agent (VDA) 2411 | <https://www.carlstalhood.com/virtual-delivery-agent-vda-cr/> | 2026-11-13 | `cpu.checks[25]` Ausschlüsse der Schutzsoftware mit der Empfehlung aus der Praxis vergleichen<br>`cpu.checks[30]` Zahl der Prozessoren der virtuellen Maschine mit der Empfehlung aus der Praxis vergleichen<br>`memory.checks[17]` Arbeitsspeicher der virtuellen Maschine mit der Empfehlung aus der Praxis vergleichen<br>`disk.checks[9]` Ausschlüsse der Schutzsoftware mit der Empfehlung aus der Praxis vergleichen | Stand der Seite 4.12.2024. Die Größe (8 vCPU, 24 bis 48 GB) nennt die Seite für Windows Server 2016 bis 2022 als Server mit mehreren Sitzungen. Die Liste der Ausschlüsse gibt die Seite als Inhalt eines Beitrags von Citrix wieder, der nicht mehr erreichbar war; sie steht deshalb hier und nicht unter Citrix. Den Ausschluss des WEM-Agenten nennt die Seite „Workspace Environment Management (WEM) 2411“ derselben Quelle. |
| Citrix Health Check | <https://www.carlstalhood.com/citrix-health-check/> | 2026-11-13 | `cpu.checks[31]` Energiesparplan des Servers feststellen<br>`memory.remedies[7]` Arbeitsspeicher der virtuellen Maschine mindestens so groß wählen wie den zugesagten Speicher<br>`delay.many.checks[12]` Energiesparplan des Servers feststellen<br>`delay.single.checks[10]` Energiesparplan des Servers feststellen | Stand der Seite 28.2.2024 (Prüfliste). Zum Energiesparplan siehe „Ausnahmen: Praxisquelle vor Hersteller“. Die Aussage zum zugesagten Speicher ist ein Punkt der Prüfliste ohne Zahl. |
| Citrix Profile Management 2411 | <https://www.carlstalhood.com/citrix-profile-management/> | 2026-11-13 | `share.remedies[1]` Active Write Back der Citrix Profilverwaltung abschalten<br>`profile.checks[13]` Ausschlusslisten der Citrix Profilverwaltung mit der Empfehlung aus der Praxis vergleichen<br>`profile.remedies[6]` Einstellungen der Citrix Profilverwaltung für schnelle Anmeldungen prüfen | Stand der Seite 8.2.2025. Die Empfehlung zu Streaming und Profilcontainer schreibt die Seite Citrix zu (CTX463658); der Artikel war nicht lesbar, deshalb steht sie hier und nicht unter Citrix. Die Prüfung der Ausschlüsse bei der Anmeldung („Logon Exclusion Check“) nennt die Seite nur als Möglichkeit und ist nicht übernommen; die Ausschlüsse für das klassische Teams ebenfalls nicht. |
| Group Policy Computer Settings for VDAs | <https://www.carlstalhood.com/group-policy-objects-vda-computer-settings/> | 2026-11-13 | `memory.remedies[8]` Zeitlimit für getrennte und für untätige Sitzungen per Richtlinie setzen | Stand der Seite 3.11.2023. „3 hours or similar“ ist eine Größenordnung. Dass die Zeitlimits nur an einer der beiden Stellen (Microsoft-Richtlinie oder Citrix-Richtlinie) gesetzt sein sollen, sagt auch Citrix („Session limits policy settings“); der Katalog nennt beide Stellen als Möglichkeit. |

### Belegstellen

- **Citrix Virtual Delivery Agent (VDA) 2411**
  - „For Windows Server 2022, 2019, or 2016 RDSH, give the virtual machine 8 vCPU, and 24-48 GB of RAM“
  - „Exclude the pagefile(s) from being scanned [...] Exclude Windows event logs from being scanned“
- **Citrix Health Check**
  - „Power management is set to High Performance with no sleep timers.“
  - „Allocated VM Memory matches or exceeds memory Committed Bytes – Hypervisor monitoring can’t show actual VM memory usage.“
- **Citrix Profile Management 2411**
  - „Disable Active write back. This feature places additional load on the file server and is only needed if users login to multiple machines concurrently and need mid-session changes to be saved, or if users never log off from their sessions. Note: if you don’t disable this, then it is enabled by default.“
  - „For fastest logons, Citrix recommends Profile streaming + Enable profile streaming for folders + Accelerate folder mirroring all enabled, or only enable Profile Container for the entire user profile.“
  - „Under the File system node in the Group Policy Editor, enable the setting Enable Default Exclusion List – directories.“
- **Group Policy Computer Settings for VDAs**
  - „Set a time limit for active but idle Terminal Services sessions = enabled, 3 hours or similar [...] Set time limit for disconnected sessions = enabled, 3 hours or similar“

### Nicht aufgenommen

| Empfehlung | Grund |
|---|---|
| Virtuelle Hardware unter vSphere, Updates und Neustarts, Lizenzierung der Remotedesktopdienste, Zeitgrenzen des VDA, WEM-Agent auf den lastverteilten Namen, Protokoll der Profilverwaltung, maschinenweite Installation von Teams und OneDrive, Selbstaktualisierer abschalten | beschreibt einen Zustand des Servers, keinen Schritt zu einem Vorfall (gehört zum Zustandsbild) |
| Schreibcache und Auslagerungsdatei bei Citrix Provisioning, Ereignisprotokolle auf beständigem Laufwerk bei Provisioning | gilt nur für Citrix Provisioning; die Server der Zielumgebung werden über Machine Creation Services bereitgestellt |
| AppData nicht auf eine Freigabe umleiten | der Hersteller sagt es für Outlook selbst (Microsoft, aufgenommen unter Office); für andere Anwendungen steht es seit dem 13.11.2026 bei einem Engpass an der Freigabe mit benanntem Verursacher, aus der Quelle James Kindon |
| Netzwerkschutz von Microsoft Defender abschalten | setzt eine Änderung voraus, die die Messung nicht stützt (Schutzfunktion; die Messung erfasst keine unterbrochenen Sitzungen) |
| Drucken: keine direkten Verbindungen zu Druckservern, Citrix Universal Print Server | setzt eine Änderung voraus, die die Messung nicht stützt (in der Zielumgebung ordnet PrinTaurus SmartSpread die Drucker zu) |
| Anmeldeverzögerungen aus Windows-Richtlinien, hängende Sitzungen veröffentlichter Anwendungen, lokale Profile löschen | setzt eine Änderung voraus, die die Messung nicht stützt (der Bericht hat keine Situation für die Dauer der Anmeldung) |

## BIS-F (Empfehlung aus der Praxis)

Das Base Image Script Framework (BIS-F) ist eine Sammlung von Skripten, die ein Master-Image vor dem Versiegeln vorbereiten: eine Quelle aus der Praxis, keine Dokumentation eines Herstellers. Was BIS-F einstellt, steht in seinen Skripten; die Dokumentation beschreibt den Stand 7.1912 (Windows Server bis 2019). Jedes Element nennt die Quelle mit dem Zusatz „Empfehlung aus der Praxis“.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| 97_PrepBISF_PRE_BaseImage.ps1 | <https://raw.githubusercontent.com/EUCweb/BIS-F/master/Framework/SubCall/Preparation/97_PrepBISF_PRE_BaseImage.ps1> | 2026-11-13 | `cpu.remedies[18]` Energiesparplan „Höchstleistung“ einstellen<br>`delay.many.remedies[2]` Energiesparplan „Höchstleistung“ einstellen<br>`delay.single.remedies[3]` Energiesparplan „Höchstleistung“ einstellen | Skript des Zweigs „master“; BIS-F stellt den Plan beim Versiegeln ohne Bedingung ein. Der Vorschlag steht nur unter der Ausnahme des Auftraggebers (siehe „Ausnahmen: Praxisquelle vor Hersteller“); das Element nennt die Sicht von Microsoft und VMware. |

### Belegstellen

- **97_PrepBISF_PRE_BaseImage.ps1**
  - „Description = "Set Power Saving Scheme to High Performance";“ mit dem Befehl „powercfg.exe [...] -s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c“

### Nicht aufgenommen

| Empfehlung | Grund |
|---|---|
| Receive Side Scaling abschalten | widerspricht einer anderen Herstellerquelle (bei Microsoft ist es standardmäßig eingeschaltet; hier gilt nach Entscheidung des Auftraggebers der Hersteller, und BIS-F widerspricht sich in Skript und Versionshinweisen selbst) |
| Ereignisprotokolle und Spool-Ordner auf einen beständigen Cache-Datenträger legen | beschreibt einen Zustand des Servers, keinen Schritt zu einem Vorfall (gehört zum Zustandsbild; setzt einen beständigen Datenträger voraus, den die Zielumgebung nicht hat) |
| Windows-Update-Dienst im Abbild abschalten, Netzwerkeinstellungen (Task-Offload, UDP, ARP), Auslagerungsdatei fest einstellen, Leistungsindikatoren neu aufbauen, .NET vorkompilieren, Citrix Optimizer, Reihenfolge der Dienste beim Start | beschreibt einen Zustand des Master-Image, keinen Schritt zu einem Vorfall (gehört zum Zustandsbild; die Quelle ist für Windows Server 2022 sichtbar älter) |
| Einstellungen für Citrix Provisioning (Schreibcache) | gilt nur für Citrix Provisioning |

## GO-EUC (Empfehlung aus der Praxis)

GO-EUC (go-euc.com) ist eine Quelle aus der Praxis, keine Dokumentation eines Herstellers: eine Stiftung, die Einstellungen und Versionen im Labor unter gleicher Last vergleicht und zu jedem Artikel Last, Hardware, Versionen und Zahl der Läufe nennt. Grenzen der Quelle: Die Zahlen gelten für die Testbedingungen des jeweiligen Artikels und sein Jahr (2019 bis 2026). In den meisten Tests war die Schutzsoftware abgeschaltet; viele Tests liefen auf Windows 10 oder 11 mit einer Sitzung je Maschine, auf anderer Virtualisierung als vSphere oder ohne Citrix. Die Stiftung wird von Sponsoren getragen, darunter der Hersteller ihres Lastwerkzeugs. Der Katalog nennt ihre Zahlen deshalb nur mit Bedingungen und Jahr und nie als Sollwert.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| VMware vSphere CPU topology effects on VDI performance: NUMA vNUMA and CPU scheduling | <https://www.go-euc.com/vmware-vsphere-cpu-topology-effects-on-vdi-performance-numa-vnuma-and-cpu-scheduling/> | 2026-11-13 | `delay.many.checks[16]` Prüfen lassen, ob der VMware-Host dem Server Rechenzeit entzogen hat | Stand 20.3.2026 (PXG-01, PXG-58). Labortest: Windows 11 mit einer Sitzung, 4 vCPU, ESXi 8.0.3, Schutzsoftware abgeschaltet. Die Stufen des Artikels für CPU-Latenz und Co-Stop sind seine eigene Einteilung und stehen nicht im Katalog; für die CPU-Bereitschaft verweist der Artikel selbst auf VMware. |
| Impact of sizing RDSH VMs | <https://www.go-euc.com/impact-of-sizing-rdsh-vms/> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Stand 27.2.2019 (PXG-04). Test: Windows Server 2016, ESXi 6.7 U1, zwei Prozessoren mit je 14 Kernen, Schutz gegen Prozessorlücken abgeschaltet. Die Untergrenze von 4 vCPU stammt nicht aus dem Artikel und ist nicht übernommen. |
| Citrix Policy Templates | <https://www.go-euc.com/citrix-policy-templates/> | 2026-11-13 | `cpu.checks[17]` ‹Anwendung› gehört zu den Citrix-Komponenten des Servers | Stand 20.8.2019 (PXG-06). Test: Windows 10 1809, VDA 1811. Die gemessenen Werte gelten für eine Vorlage mit Videocodec für den ganzen Bildschirm und stehen nicht im Katalog; „alles auf der Voreinstellung lassen“ ist der Rat der Quelle, nicht von Citrix. |
| The real impact of Citrix MCSIO | <https://www.go-euc.com/the-real-impact-of-citrix-mcsio/> | 2026-11-13 | `memory.checks[20]` Wenn der Maschinenkatalog MCS I/O nutzt<br>`chronic.resource.checks[8]` Wenn der Maschinenkatalog MCS I/O nutzt | Stand 31.3.2020 (PXG-22, PXG-26). Test: Windows 10 in einer einzelnen Maschine, VDA 1906.2. Dass der Cache Teil des Arbeitsspeichers der Maschine ist, schreibt auch Citrix („Create machine catalogs“). „Cache verkleinern“ ist nicht übernommen. |

### Stützt bestehende Elemente

Diese Elemente behalten ihre Quelle; ein Satz im Element nennt die Praxisquelle („nach …“ oder mit ihrem Namen).

- Prüfschritt „Prüfen, ob der VMware-Host dem Server Rechenzeit entzogen hat …“ der Situation `cpu` – auch gestützt durch: „VMware vSphere CPU topology effects on VDI performance: NUMA vNUMA and CPU scheduling“, <https://www.go-euc.com/vmware-vsphere-cpu-topology-effects-on-vdi-performance-numa-vnuma-and-cpu-scheduling/>, 2026-03-20 (PXG-01)
- Prüfschritt „Kein einzelner Verursacher: Auslegung des Servers für den Prozessor prüfen …“ der Situation `chronic.resource` – auch gestützt durch: „VMware vSphere CPU topology effects on VDI performance: NUMA vNUMA and CPU scheduling“, <https://www.go-euc.com/vmware-vsphere-cpu-topology-effects-on-vdi-performance-numa-vnuma-and-cpu-scheduling/>, 2026-03-20 (PXG-58)
- Abhilfe „Sitzungen gleichmäßiger auf die Server verteilen oder dem Server mehr Prozessoren …“ der Situation `cpu` – auch gestützt durch: „Impact of sizing RDSH VMs“, <https://www.go-euc.com/impact-of-sizing-rdsh-vms/>, 2019-02-27 (PXG-04)
- Abhilfe „Kapazität anpassen (weniger Sitzungen je Server, zusätzliche Server oder mehr Prozessoren …“ der Situation `chronic.resource` – auch gestützt durch: „Impact of sizing RDSH VMs“, <https://www.go-euc.com/impact-of-sizing-rdsh-vms/>, 2019-02-27 (PXG-04)
- Prüfschritt „Wenn der Maschinenkatalog MCS I/O nutzt …“ der Situation `disk` – auch gestützt durch: „The real impact of Citrix MCSIO“, <https://www.go-euc.com/the-real-impact-of-citrix-mcsio/>, 2020-03-31 (PXG-26)

### Belegstellen

- **VMware vSphere CPU topology effects on VDI performance: NUMA vNUMA and CPU scheduling**
  - „Based on this study, maintaining CPU Ready below ~5% per VM corresponds to a stable EUX score of ~7.5, aligning with VMware best practices for predictable end-user experience in higher-density VDI environments.“
  - „Adjusting CPU topology in small desktops did not produce measurable differences in EUX scores under typical workloads.“
- **Impact of sizing RDSH VMs**
  - „With other hardware specifications, the advice is to start with half the number of cores of the physical CPU per VM with a maximum of 8 vCPUs per VM. The total number of vCPUs should be equal to the total of number of hyperthreaded cores.“
- **Citrix Policy Templates**
  - „As per best practice, if you don't need to delivery 3D of CAD workloads, keep everything at default if you use a VDA 7.18 or later and let the system decide.“
- **The real impact of Citrix MCSIO**
  - „This memory is claimed by the MCSIO driver and will not be available for the operating system.“

### Nicht aufgenommen

| Empfehlung | Grund |
|---|---|
| Aufgaben „Office Feature Updates“ prüfen und im Master-Image abschalten, wenn SDXHelper.exe viel schreibt (PXG-24, PXG-25) | braucht eine Bedingung, die der Katalog nicht hat (SDXHelper.exe steht nicht in der Anwendungsliste; Microsoft rät für Microsoft 365 Apps außerdem vom Abschalten ab) |
| Sicherheitsvorgaben, nach denen sich der VDA nicht registriert oder zweimal nach dem Kennwort fragt | beschreibt keinen Vorfall, den der Bericht erfasst |
| Bildrate von HDX auf 30 Bilder je Sekunde begrenzen | beschreibt keinen Vorfall, den der Bericht erfasst (eine feste Einstellung erklärt keine zeitlich begrenzte Verzögerung) |
| Werbeblocker im Browser gegen Prozessorlast (PXG-14) | die Quelle stützt die Empfehlung nicht oder nur mit geringem Gewicht (Chrome, 2019; die Messung zeigt nicht, dass Werbung die Ursache ist) |
| Stufen für CPU-Latenz und Co-Stop als Erkennungszeichen; Untergrenze von 4 vCPU; Cache von MCS I/O verkleinern | die Quelle stützt die Empfehlung nicht oder nur mit geringem Gewicht |

## James Kindon (Empfehlung aus der Praxis)

Der Blog von James Kindon (jkindon.com) ist eine Quelle aus der Praxis, keine Dokumentation eines Herstellers: Erfahrung aus Projekten mit Workspace Environment Management und der Citrix Profilverwaltung. Grenzen der Quelle: Die jüngsten Beiträge mit eigenem Inhalt stammen von 2023; Beiträge von 2017 bis 2021 hat der Autor zum Teil selbst überholt, sie stehen hier nur mit ihrem Datum. Der Autor arbeitet seit etwa 2022 für einen Hersteller von Virtualisierung und testet meist auf dessen Plattform oder in Azure, nicht auf vSphere mit Machine Creation Services. Zahlen nennt er fast nur in einem einzelnen Kundenfall von 2022 (Windows Server 2016, FSLogix); der Katalog nennt daraus keine Zahl.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| The not-so-hidden tax of granular group based application presentation with Citrix WEM | <https://jkindon.com/not-so-hidden-tax-citrix-wem/> | 2026-11-13 | `cpu.checks[18]` ‹Anwendung› gehört zu den Citrix-Komponenten des Servers<br>`cpu.remedies[12]` Zuweisungen von WEM an einzelne Gruppen verringern | Stand 30.10.2022 (PXG-07, PXG-08). Ein Kundenfall: Windows Server 2016, CVAD 1912 LTSR, FSLogix, zwei Domänen. Die Zeiten des Falls stehen nicht im Katalog; die Spitze von 100 % auf 70 % galt dem Hypervisor, nicht einem Server. |
| WEM Advanced Guidance 2023 | <https://jkindon.com/wem-advanced-guidance-2023/> | 2026-11-13 | `memory.remedies[9]` Optimierung für getrennte Sitzungen von Citrix Workspace Environment Management einschalten | Stand 30.5.2023 (PXG-11, PXG-18, PXG-19). Zur Speicheroptimierung nennt das Element beide Sichten der Praxis (Kindon, Winkel); die Grenze von Citrix (höchstens 5 %) bleibt die Regel. |
| Citrix Session Management Policies | <https://jkindon.com/citrix-session-management-policies/> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Stand 9.8.2021 (PXG-20). Die Aussage des Beitrags, die Zeitgeber von Citrix gälten nicht für Server mit mehreren Sitzungen, ist nicht übernommen. |
| Stop Redirecting AppData. It's no longer the 80's | <https://jkindon.com/stop-redirecting-appdata/> | 2026-11-13 | `share.remedies[2]` AppData und Startmenü aus der Ordnerumleitung nehmen und im Profilcontainer lassen, wie die Praxisquelle | Stand 5.10.2023 (PXG-30, PXG-31). Die Einstufung einzelner Ordner als Pflicht oder Empfehlung ist nicht übernommen. |
| The Evolution of Citrix Profile Management | <https://jkindon.com/the-evolution-of-citrix-profile-management/> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Stand 12.4.2025 (PXG-32, PXG-33). Der Beitrag gibt großteils Versionshinweise von Citrix wieder; übernommen ist nur die eigene Einschätzung zu Active Write Back. |
| WEM Advanced Guidance Part 2 - User Interaction | <https://jkindon.com/wem-advanced-guidance-part-2-user-interaction/> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Stand 4.1.2018 (PXG-70), geschrieben für WEM 4.x. |
| Citrix UPM and FSLogix Containers | <https://jkindon.com/citrix-upm-and-fslogix-containers/> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Stand 16.9.2021 mit Vorwort von 2023 (PXG-76). Die Zahl „99 %“ gilt FSLogix und ist nicht übernommen. |

### Stützt bestehende Elemente

Diese Elemente behalten ihre Quelle; ein Satz im Element nennt die Praxisquelle („nach …“ oder mit ihrem Namen).

- Abhilfe „CPU-Spitzenschutz von Citrix Workspace Environment Management einschalten oder seine …“ der Situation `cpu` – auch gestützt durch: „WEM Advanced Guidance 2023“, <https://jkindon.com/wem-advanced-guidance-2023/>, 2023-05-30 (PXG-11)
- Abhilfe „Leerlaufgrenze der Speicheroptimierung von Citrix Workspace Environment Management prüfen …“ der Situation `memory` – auch gestützt durch: „WEM Advanced Guidance 2023“, <https://jkindon.com/wem-advanced-guidance-2023/>, 2023-05-30 (PXG-19)
- Abhilfe „Zeitlimit für getrennte und für untätige Sitzungen per Richtlinie setzen …“ der Situation `memory` – auch gestützt durch: „Citrix Session Management Policies“, <https://jkindon.com/citrix-session-management-policies/>, 2021-08-09 (PXG-20)
- Prüfschritt „Klären, welche Dateien ‹Anwendung› in der Sitzung von ‹Benutzer› ab …“ der Situation `share` – auch gestützt durch: „Stop Redirecting AppData. It's no longer the 80's“, <https://jkindon.com/stop-redirecting-appdata/>, 2023-10-05 (PXG-30)
- Abhilfe „Active Write Back der Citrix Profilverwaltung abschalten …“ der Situation `share` – auch gestützt durch: „The Evolution of Citrix Profile Management“, <https://jkindon.com/the-evolution-of-citrix-profile-management/>, 2025-04-12 (PXG-32/33)
- Prüfschritt „Bei falschem Standarddrucker, doppelt angezeigten Druckern oder falschen Druckern nach …“ der Situation `print` – auch gestützt durch: „WEM Advanced Guidance Part 2 - User Interaction“, <https://jkindon.com/wem-advanced-guidance-part-2-user-interaction/>, 2018-01-04 (PXG-70)
- Kontakt „Betreuung des Dateiservers mit dem Profilspeicher, wenn der Speicher zur Zeit des Fehlers …“ der Situation `profileerror` – auch gestützt durch: „Citrix UPM and FSLogix Containers“, <https://jkindon.com/citrix-upm-and-fslogix-containers/>, 2021-09-16 (PXG-76)

### Belegstellen

- **The not-so-hidden tax of granular group based application presentation with Citrix WEM**
  - „25-30 users per session host, all hitting hundreds of group assignments would flatline the server almost full time (logons + background WEM refreshing)“
- **WEM Advanced Guidance 2023**
  - „Luckily, this is now automatic, and you should be allowing WEM to dynamically figure this out using the Auto Prevent CPU Spikes setting.“
  - „Multi-Session Optimization is quite a handy addition to the stack, allowing you to apply optimizations only when sessions are in a disconnected state.“
  - „At its core, Memory Management is forcing the paging of idle memory to disk. This is aggressive and can be extremely punishing on your disk configurations. In 99% of deployments I have done in the field, I do not enable Memory Management.“
- **Stop Redirecting AppData. It's no longer the 80's**
  - „In this day and age, AppData redirection is significantly frowned upon and is a key component of badly performing environments.“
- **The Evolution of Citrix Profile Management**
  - „Active write back is a silent killer in many environments, it can very quickly knock file servers off their perch and into a pitt of doom.“
- **WEM Advanced Guidance Part 2 - User Interaction**
  - „choose an assignment process for Printers and stick with it. Mixing assignment tools will only result in frustration and unexpected results.“
- **Citrix UPM and FSLogix Containers**
  - „User sessions will completely die, and recovery can become a nightmare with the loss of file services hosting containers“

### Nicht aufgenommen

| Empfehlung | Grund |
|---|---|
| Ereignis 2 der Windows-Suche (Search-ProfileNotify) | gilt nur für ein anderes Produkt oder eine ältere Version; die Quelle sagt nicht, was sich überträgt (Windows Server 2019) |
| Ordnerumleitung per Benutzerrichtlinie erzwingt synchrone Verarbeitung | braucht eine Bedingung, die der Katalog nicht hat (der Bericht hat keine Situation für die Dauer der Anmeldung) |
| Zwischenspeicher des WEM-Agenten und „Offline Mode“ bei ausgefallenem Dienst (PXG-66) | braucht eine Bedingung, die der Katalog nicht hat (kein Dienstname als Bedingung; die Quelle stellt den Bezug zum Ausfall nicht her) |
| Prüfschritt zum WEM-Agenten auch beim Dauerzustand; AppData-Umleitung auch beim Profilcontainer und bei einer langsamen Gegenstelle | steht nur dort, wo die Messung den Schritt stützt (Engpass am Prozessor oder an der Freigabe mit benanntem Verursacher) |
| Zeitgeber von Citrix gälten nicht für Server mit mehreren Sitzungen (2021) | widerspricht dem Hersteller; hier gilt der Hersteller |

## James Rankin (Empfehlung aus der Praxis)

Der Blog von James Rankin (james-rankin.com) ist eine Quelle aus der Praxis, keine Dokumentation eines Herstellers: Messreihen zur Dauer der Anmeldung, die je einen Einfluss einzeln verändern. Grenzen der Quelle: Jede Messung stammt aus dem Labor des Autors mit Windows Server 2019 oder Windows 10, meist mit FSLogix oder dateibasierten Profilen, einem Benutzer und wenigen Anmeldungen je Test; die Schutzsoftware war in den Ausgangsmessungen abgeschaltet, Microsoft Defender wurde nie getestet. Nichts davon ist auf Windows Server 2022 oder mit Profilcontainern der Citrix Profilverwaltung unter Last gemessen. Die Reihe zur Anmeldung nennt einen Sponsor, dessen Werkzeug die Zahlen liefert. Der letzte hier verwendete Beitrag ist von 2023.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| The ultimate guide to Windows logon time optimizations, part #10 | <https://james-rankin.com/features/the-ultimate-guide-to-windows-logon-time-optimizations-part-10/> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Stand 19.11.2021 (PXG-17). Test: Windows Server 2019, dateibasierte Profile, andere Schutzsoftware als Microsoft Defender. Die Aussage zu Containern ist nicht übernommen. |
| Windows session timeouts on Citrix – a brief guide | <https://james-rankin.com/articles/windows-session-timeouts-on-citrix-a-brief-guide/> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Stand 8.3.2023 (PXG-20). Die Beispielwerte (je 2 Stunden) sind Beispiele und stehen nicht im Katalog. |
| The ultimate guide to Windows logon time optimizations, part #5 | <https://james-rankin.com/features/the-ultimate-guide-to-windows-logon-optimizations-part-5/> | 2026-11-13 | `share.remedies[7]` Drosselung der Bandbreite des SMB-Clients abschalten erwägen<br>`chronic.resource.remedies[3]` Drosselung der Bandbreite des SMB-Clients abschalten erwägen<br>`chronic.resource.remedies[4]` Drosselung der Bandbreite des SMB-Clients abschalten erwägen | Stand 24.6.2021 (PXG-36). Ein Labor, ein Dateiserver, FSLogix; die 12 statt 17 Sekunden entstanden zusammen mit Änderungen am Dateiserver, im selben Satz stieg das Laden des Profils von 0,12 auf 0,8 Sekunden. Microsoft nennt den Wert in „Optimizing Windows configuration for VDI desktops“ für Windows 10 und 11 („Consider setting this value to 1“), nicht für Windows Server 2022. |
| QuickPost – Citrix UPM VHD compaction feature | <https://james-rankin.com/articles/quickpost-citrix-upm-vhd-compaction-feature/> | 2026-11-13 | `profile.remedies[7]` Verkleinern der Profilcontainer bei der Abmeldung einschalten<br>`chronic.resource.remedies[5]` Verkleinern der Profilcontainer bei der Abmeldung einschalten | Stand 29.3.2023 (PXG-37, PXG-38), Profilverwaltung ab 2303. „Gigabytes an Leerraum“ und der Starttyp des Dienstes sind nicht übernommen. |
| The ultimate guide to Windows logon time optimizations – part #4 | <https://james-rankin.com/features/the-ultimate-guide-to-windows-logon-optimizations-part-4/> | 2026-11-13 | `delay.many.checks[13]` Wenn die Benutzer im Explorer, in einem Dateidialog oder bei der Anmeldung warteten<br>`delay.single.checks[12]` Wenn der Benutzer im Explorer, in einem Dateidialog oder bei der Anmeldung wartete | Stand 17.1.2021 (PXG-47). Test: Windows 10, Laufwerkszuordnungen über Group Policy Preferences, sechs nicht erreichbare Ziele. |
| (Reasons not to be) using network drives on Citrix Virtual Apps and Desktops | <https://james-rankin.com/articles/reasons-not-to-be-using-network-drives-on-citrix-virtual-apps-and-desktops/> | 2026-11-13 | `share.remedies[3]` Laufwerkszuordnung dort löschen oder berichtigen, wo sie festgelegt ist<br>`delay.many.remedies[3]` Laufwerkszuordnung dort löschen oder berichtigen, wo sie festgelegt ist<br>`delay.single.remedies[4]` Laufwerkszuordnung dort löschen oder berichtigen, wo sie festgelegt ist | Stand 16.10.2020 (PXG-48). Der Rat, ganz auf Laufwerksbuchstaben zu verzichten, ist im Element als Meinung der Quelle bezeichnet. |
| Citrix XenApp, XenDesktop and Folder Redirection – the last word | <https://james-rankin.com/articles/citrix-xenapp-xendesktop-and-folder-redirection-the-last-word/> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Stand 22.11.2018 (PXG-31): die andere Sicht dazu, was umgeleitet bleiben darf. |
| QuickPost – getting started with Citrix UPM Containers | <https://james-rankin.com/articles/quickpost-getting-started-with-citrix-upm-containers/> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Stand 8.9.2023 (PXG-37). |

### Stützt bestehende Elemente

Diese Elemente behalten ihre Quelle; ein Satz im Element nennt die Praxisquelle („nach …“ oder mit ihrem Namen).

- Abhilfe „Scan-Ausschlüsse ergänzen, die für Terminalserver üblich sind und die die Hersteller der …“ der Situation `cpu` – auch gestützt durch: „The ultimate guide to Windows logon time optimizations, part #10“, <https://james-rankin.com/features/the-ultimate-guide-to-windows-logon-time-optimizations-part-10/>, 2021-11-19 (PXG-17)
- Abhilfe „Scan-Ausschlüsse ergänzen, die für Terminalserver üblich sind und die die Hersteller der …“ der Situation `disk` – auch gestützt durch: „The ultimate guide to Windows logon time optimizations, part #10“, <https://james-rankin.com/features/the-ultimate-guide-to-windows-logon-time-optimizations-part-10/>, 2021-11-19 (PXG-17)
- Abhilfe „Scan-Ausschlüsse ergänzen, die für Terminalserver üblich sind und die die Hersteller der …“ der Situation `share` – auch gestützt durch: „The ultimate guide to Windows logon time optimizations, part #10“, <https://james-rankin.com/features/the-ultimate-guide-to-windows-logon-time-optimizations-part-10/>, 2021-11-19 (PXG-17)
- Abhilfe „Scan-Ausschlüsse ergänzen, die für Terminalserver üblich sind und die die Hersteller der …“ der Situation `profile` – auch gestützt durch: „The ultimate guide to Windows logon time optimizations, part #10“, <https://james-rankin.com/features/the-ultimate-guide-to-windows-logon-time-optimizations-part-10/>, 2021-11-19 (PXG-17)
- Abhilfe „Zeitlimit für getrennte und für untätige Sitzungen per Richtlinie setzen …“ der Situation `memory` – auch gestützt durch: „Windows session timeouts on Citrix – a brief guide“, <https://james-rankin.com/articles/windows-session-timeouts-on-citrix-a-brief-guide/>, 2023-03-08 (PXG-20)
- Prüfschritt „‹Anwendung› gehört zur Citrix Profilverwaltung …“ der Situation `profile` – auch gestützt durch: „QuickPost – Citrix UPM VHD compaction feature“, <https://james-rankin.com/articles/quickpost-citrix-upm-vhd-compaction-feature/>, 2023-03-29 (PXG-37)
- Prüfschritt „‹Anwendung› gehört zur Citrix Profilverwaltung …“ der Situation `share` – auch gestützt durch: „QuickPost – Citrix UPM VHD compaction feature“, <https://james-rankin.com/articles/quickpost-citrix-upm-vhd-compaction-feature/>, 2023-03-29 (PXG-37)
- Prüfschritt „‹Anwendung› gehört zur Citrix Profilverwaltung …“ der Situation `disk` – auch gestützt durch: „QuickPost – Citrix UPM VHD compaction feature“, <https://james-rankin.com/articles/quickpost-citrix-upm-vhd-compaction-feature/>, 2023-03-29 (PXG-37)
- Abhilfe „AppData und Startmenü aus der Ordnerumleitung nehmen und im Profilcontainer lassen, wie …“ der Situation `share` – auch gestützt durch: „Citrix XenApp, XenDesktop and Folder Redirection – the last word“, <https://james-rankin.com/articles/citrix-xenapp-xendesktop-and-folder-redirection-the-last-word/>, 2018-11-22 (PXG-31)
- Prüfschritt „‹Anwendung› gehört zur Citrix Profilverwaltung …“ der Situation `profile` – auch gestützt durch: „QuickPost – getting started with Citrix UPM Containers“, <https://james-rankin.com/articles/quickpost-getting-started-with-citrix-upm-containers/>, 2023-09-08 (PXG-37)
- Prüfschritt „‹Anwendung› gehört zur Citrix Profilverwaltung …“ der Situation `share` – auch gestützt durch: „QuickPost – getting started with Citrix UPM Containers“, <https://james-rankin.com/articles/quickpost-getting-started-with-citrix-upm-containers/>, 2023-09-08 (PXG-37)
- Prüfschritt „‹Anwendung› gehört zur Citrix Profilverwaltung …“ der Situation `disk` – auch gestützt durch: „QuickPost – getting started with Citrix UPM Containers“, <https://james-rankin.com/articles/quickpost-getting-started-with-citrix-upm-containers/>, 2023-09-08 (PXG-37)

### Belegstellen

- **The ultimate guide to Windows logon time optimizations, part #10**
  - „Quite a marked increase – over 40 seconds for Server 2019, and nearly 32 seconds more for Windows 10.“
- **Windows session timeouts on Citrix – a brief guide**
  - „Do yourself a favour and don't use the settings on the AD user objects, stick to policy.“
- **The ultimate guide to Windows logon time optimizations, part #5**
  - „average logon time is down from 17 seconds to 12 seconds“
- **QuickPost – Citrix UPM VHD compaction feature**
  - „if you wish to use the defragmentation feature, then the Windows service "Optimize drives" (also known as "defragsvc" ) needs to be running. Some optimization tools turn it off.“
- **The ultimate guide to Windows logon time optimizations – part #4**
  - „At 200.34 seconds for 6 inaccessible mappings, that's a timeout of about 33 seconds per mapping“
- **Citrix XenApp, XenDesktop and Folder Redirection – the last word**
  - „Avoid the performance impact of redirection on folders like Desktop, Start Menu and AppData“
- **QuickPost – getting started with Citrix UPM Containers**
  - „UPM by default uses a diff disk and then merges it back into the base VHDX at logoff.“

### Nicht aufgenommen

| Empfehlung | Grund |
|---|---|
| Werte am Dateiserver für SMB | liegen außerhalb des gemessenen Servers; Sache der Betreuung des Dateiservers |
| Laufwerksbuchstaben ganz durch Ordnerumleitung oder Verknüpfungen ersetzen | Meinung der Quelle; im Element nur als solche genannt |
| Beispielwerte für Zeitlimits (je 2 Stunden) als Vorgabe; „Gigabytes an Leerraum“ im Container | die Quelle stützt die Empfehlung nicht oder nur mit geringem Gewicht |

## Thomas Kötzing (Empfehlung aus der Praxis)

Der Blog von Thomas Kötzing (koetzingit.de) ist eine Quelle aus der Praxis, keine Dokumentation eines Herstellers: Erfahrung aus Kundenprojekten, am stärksten zum Drucken und zu Anmeldung und Profilen unter Citrix. Grenzen der Quelle: Die meisten Beiträge enthalten keine Messung. Die Regeln zum Drucken stammen im Kern von 2011 (Ausgabe 2017) und wurden für XenApp auf Windows Server 2008 R2 geschrieben; übertragbar sind die Richtlinien von Microsoft, nicht die Regeln für Clientdrucker. Mehrere Beiträge von 2025 und 2026 sind Meinungsbeiträge an Citrix; wo einer der Voreinstellung von Citrix widerspricht (EDT abschalten), gilt Citrix, und das Element nennt die andere Sicht nur als solche.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| Hören Sie auf die Serverleistung zu optimieren! Optimieren Sie die Benutzersitzungen | <https://koetzingit.de/blog/2018/03/06/hoeren-sie-auf-server-zu-optimieren-optimieren-sie-die-benutzer-sitzungen/> | 2026-11-13 | `memory.checks[19]` Programme ansehen, die in jeder Sitzung von selbst starten | Stand 6.3.2018 (PXG-21). Die Zahlen stammen aus einer einzelnen Durchsicht von 2018 und sind kein Sollwert. |
| Citrix Maschinenerstellungsdienste (MCS) -Skript zum Auslesen des RAM- und Disk-Cache | <https://koetzingit.de/blog/2024/03/18/citrix-maschinenerstellungsdienste-mcs-skript-zum-auslesen-des-ram-und-disk-cache/> | 2026-11-13 | `disk.checks[20]` Wenn der Maschinenkatalog MCS I/O nutzt | Stand 18.3.2024 (PXG-26, mit PXG-27). Der Beitrag nennt auch den geänderten Namen der Leistungsindikatoren („Citrix MCS“). |
| Citrix: Wir brauchen einen Infrastruktur-Monitor – für Speichersysteme Plus! | <https://koetzingit.de/blog/2025/09/08/citrix-wir-brauchen-einen-infrastruktur-monitor-fuer-speichersysteme-plus/> | 2026-11-13 | `share.contacts[2]` Betreuung des Speichersystems unter dem Dateiserver, wenn auf dem Server keine Ursache zu finden ist | Stand 8.9.2025 (PXG-35). Ein Kundenfall, ohne Messung. |
| Häufige Anmeldeprobleme und deren Lösung! | <https://koetzingit.de/blog/2020/11/30/haeufige-anmeldeprobleme-und-deren-loesung/> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Stand 30.11.2020 (PXG-47). |
| Einfache Fehleranalyse der Dauer von Gruppenrichtlinien während der Anmeldung | <https://koetzingit.de/blog/2017/04/24/einfache-fehleranalyse-der-dauer-von-gruppenrichtlinien-waehrend-der-anmeldung/> | 2026-11-13 | `delay.many.checks[14]` Wenn die Verzögerung in Anmeldungen oder eine Aktualisierung der Gruppenrichtlinien fiel | Stand 24.4.2017 (PXG-49). Die Faustwerte stammen aus der Zeit von Windows Server 2012 R2 und 2016; „über 1000 ms“ nennt der Beitrag als Anlass, näher hinzusehen, nicht als Grenze. Dass mit WEM weniger Benutzerrichtlinien anfallen, ist eine Anmerkung des Katalogs und steht nicht im Element. |
| Die zehn Regeln zum Drucken unter Citrix | <https://koetzingit.de/blog/2017/02/08/die-zehn-regeln-zum-drucken-unter-citrix/> | 2026-11-13 | `print.checks[19]` Prüfen, ob das Treiberpaket von ‹Treiber› einen eigenen Druckmonitor installiert hat | Stand 8.2.2017 (PXG-68, PXG-69). „Druckaufträge immer auf dem Server aufbereiten“ aus demselben Beitrag ist nicht übernommen. |
| Citrix, es ist an der Zeit, drei HDX-Dinge zu beheben! | <https://koetzingit.de/blog/2025/08/04/citrix-es-ist-an-der-zeit-drei-hdx-dinge-zu-beheben/> | 2026-11-13 | `chronic.network.checks[5]` Feststellen, über welchen Transport die Sitzung des Benutzers läuft | Stand 4.8.2025 (PXG-57). Meinungsbeitrag ohne Messung; er widerspricht der Voreinstellung von Citrix. Das Element ist ein Schritt zum Nachsehen und kein Vorschlag, EDT abzuschalten. |
| Ein echter Kunden-Support-Fall, gelöst mit Hilfe von KI! | <https://koetzingit.de/blog/2025/05/27/ein-echter-kunden-support-fall-geloest-mit-hilfe-von-ki/> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Stand 27.5.2025 (PXG-67). Ein Kundenfall; die Auswertung mit einem KI-Werkzeug ist nicht Teil des Hinweises. |
| Citrix UPM wie FSLogix nutzen – nur besser! | <https://koetzingit.de/blog/2026/02/24/citrix-upm-wie-fslogix-nutzen-nur-besser/> | 2026-11-13 | `profileerror.remedies[1]` „Automatically reattach VHDX disks“ der Citrix Profilverwaltung einschalten<br>`profileerror.remedies[3]` Zurückschreiben aus mehreren Sitzungen für Profilcontainer in der Citrix Profilverwaltung einschalten und d … | Stand 24.2.2026 (PXG-77, PXG-78). Der Vergleich mit FSLogix ist Meinung und nicht übernommen. Die Namen der Einstellungen nennt auch Citrix in den Richtlinien der Profilverwaltung. |
| Powershell-Skript zum Löschen von temporären Benutzerprofilen | <https://koetzingit.de/blog/2024/09/10/powershell-skript-zum-loeschen-von-temporaeren-benutzerprofilen/> | 2026-11-13 | `profileerror.remedies[4]` Server in den Wartungsmodus setzen und neu starten, sobald er leer ist, damit er mit einer sauberen Profill … | Stand 10.9.2024 (PXG-79). Das Löschen des Eintrags am Server ist durch den Neustart und das Master-Image ersetzt (Regel der Zielumgebung). |

### Stützt bestehende Elemente

Diese Elemente behalten ihre Quelle; ein Satz im Element nennt die Praxisquelle („nach …“ oder mit ihrem Namen).

- Prüfschritt „Wenn die Benutzer im Explorer, in einem Dateidialog oder bei der Anmeldung …“ der Situation `delay.many` – auch gestützt durch: „Häufige Anmeldeprobleme und deren Lösung!“, <https://koetzingit.de/blog/2020/11/30/haeufige-anmeldeprobleme-und-deren-loesung/>, 2020-11-30 (PXG-47)
- Prüfschritt „Wenn der Benutzer im Explorer, in einem Dateidialog oder bei der Anmeldung …“ der Situation `delay.single` – auch gestützt durch: „Häufige Anmeldeprobleme und deren Lösung!“, <https://koetzingit.de/blog/2020/11/30/haeufige-anmeldeprobleme-und-deren-loesung/>, 2020-11-30 (PXG-47)
- Prüfschritt „Gruppenrichtlinie zur Treiberisolierung …“ der Situation `print` – auch gestützt durch: „Die zehn Regeln zum Drucken unter Citrix“, <https://koetzingit.de/blog/2017/02/08/die-zehn-regeln-zum-drucken-unter-citrix/>, 2017-02-08 (PXG-68)
- Prüfschritt „Kein Muster erkannt: feststellen, welcher Treiber oder welche Druckwarteschlange das …“ der Situation `print` – auch gestützt durch: „Ein echter Kunden-Support-Fall, gelöst mit Hilfe von KI!“, <https://koetzingit.de/blog/2025/05/27/ein-echter-kunden-support-fall-geloest-mit-hilfe-von-ki/>, 2025-05-27 (PXG-67)

### Belegstellen

- **Hören Sie auf die Serverleistung zu optimieren! Optimieren Sie die Benutzersitzungen**
  - „Oft müssen nur die RUN Keys (32/64bit) bereinigt werden.“
- **Citrix Maschinenerstellungsdienste (MCS) -Skript zum Auslesen des RAM- und Disk-Cache**
  - „Da die Cache-Disk (mcsdif.vhdx) eine dynamische Disk ist, schrumpft (compact) diese aber nicht von allein auf null, sondern behält immer den max. Wert.“
- **Citrix: Wir brauchen einen Infrastruktur-Monitor – für Speichersysteme Plus!**
  - „Bei einem Kunden von mir traten nach der Einführung einer neuen Antiviren-Software auf Speicherebene erhebliche Sitzungsprobleme auf. Tausende von Sitzungen waren davon betroffen.“
- **Häufige Anmeldeprobleme und deren Lösung!**
  - „Wer Netzwerkfreigaben oder Netzwerkdrucker via Gruppenrichtlinie verbindet kann Verzögerungen von 30 Sekunden bei der Anmeldung bekommen. Dies passiert immer dann, wenn die Netzwerkressource nicht mehr verfügbar ist.“
- **Einfache Fehleranalyse der Dauer von Gruppenrichtlinien während der Anmeldung**
  - „Das bedeutet alles was mehr als 1.000ms Zeit benötigt könnte interessant sein weiter zu untersuchen.“
  - „Maximum GPO Satz sollte nicht mehr sein als ca. 7-9 Sekunden“
- **Die zehn Regeln zum Drucken unter Citrix**
  - „Verwenden Sie keine Dritthersteller-Druckertreiber mit Druckermonitoren. Suchen Sie nach Treibern ohne Monitore oder deaktivieren bzw. entfernen Sie diese.“
  - „Aktivierung der Druckerisolierung per GPO, damit der Druckerdienst erst gar nicht abstürzt.“
- **Citrix, es ist an der Zeit, drei HDX-Dinge zu beheben!**
  - „Setzen Sie HDX Adaptive Transport auf ‚Off‘.“
- **Ein echter Kunden-Support-Fall, gelöst mit Hilfe von KI!**
  - „Das Eventlog lieferte kaum Hinweise, lediglich dass splwow64.exe eine Ausnahme ausgelöst hatte.“
- **Citrix UPM wie FSLogix nutzen – nur besser!**
  - „Mit der Funktion ‚Automatically reattach VHDX disks‘ überwacht der UPM-Dienst aktiv den Container-Status.“
  - „In Non-Persistent-Umgebungen dauert die Anmeldung ein paar Sekunden länger (Cache Hydration).“
  - „UPM trackt diese Änderungen aktiv und synchronisiert sie zurück in das Hauptprofil, sobald der Lock freigegeben wird oder die Sitzung endet.“
- **Powershell-Skript zum Löschen von temporären Benutzerprofilen**
  - „Ursache sind BAK Einträge für den Benutzer in der ProfileList in der Registrierung des Servers.“

### Nicht aufgenommen

| Empfehlung | Grund |
|---|---|
| Windows-Suche hält Dateien, sodass der Container nicht getrennt werden kann | gilt nur für ein anderes Produkt oder eine ältere Version; die Quelle sagt nicht, was sich überträgt (FSLogix 2021, Profilverwaltung 7.18) |
| Druckserver am selben Standort wie die Server, weil Office Drucker über das Netz abfragt (PXG-54) | braucht eine Bedingung, die der Katalog nicht hat (bei einer Verzögerung kennt der Bericht die Anwendung nicht als Bedingung) |
| Druckaufträge immer auf dem Server aufbereiten | Wirkung auf Druckwarteschlangen eines Druckservers, die ein Zuordnungswerkzeug zuordnet, ist nicht beschrieben |
| HDX Adaptive Transport auf „Off“ stellen | widerspricht dem Hersteller; hier gilt der Hersteller; das Element nennt die Sicht der Quelle, schlägt sie aber nicht vor |
| Programme aus den Run-Schlüsseln auch beim Prozessor; Druckmonitor auch beim Absturz einer Anwendung | steht nur in der Situation, zu der die Quelle Zahlen oder einen Fall nennt |

## Manuel Winkel (Empfehlung aus der Praxis)

Der Blog deyda.net von Manuel Winkel ist eine Quelle aus der Praxis, keine Dokumentation eines Herstellers: der Blog eines Beratungsunternehmens für Citrix. Der Auftraggeber hat ihn für einzelne Themen übernommen. Grenzen der Quelle: Der Blog veröffentlicht keine Messungen und keine Testbedingungen. Die Reihe „Finding in the Wild“ (2026) besteht aus kurzen Beiträgen, oft aus einem einzelnen Kundenfall, die Fehlerkennungen von Citrix ohne Verweis nennen; die Seiten von Citrix dazu waren von hier nicht zu öffnen. Der Katalog schreibt deshalb „nach der Praxisquelle behoben“ und lässt die Version in den Versionshinweisen von Citrix gegenlesen. Die Beiträge zu WEM sind von 2022 (Stand WEM 2206). Im Titel der Reihe steht im Original ein senkrechter Strich; hier steht dafür ein Gedankenstrich.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| Finding in the Wild – When Citrix Suddenly Sends Every User to the Same VDA | <https://www.deyda.net/index.php/en/2026/10/24/finding-in-the-wild-when-citrix-suddenly-sends-every-user-to-the-same-vda/> | 2026-11-13 | `cpu.checks[32]` Trägt der Server deutlich mehr Sitzungen als die anderen Server derselben Bereitstellungsgruppe, während di …<br>`memory.checks[18]` Trägt der Server deutlich mehr Sitzungen als die anderen Server derselben Bereitstellungsgruppe, während di …<br>`chronic.resource.checks[4]` Trägt der Server deutlich mehr Sitzungen als die anderen Server derselben Bereitstellungsgruppe, während di …<br>`chronic.resource.checks[5]` Trägt der Server deutlich mehr Sitzungen als die anderen Server derselben Bereitstellungsgruppe, während di … | Stand 24.10.2026, geändert 11.11.2026 (PXG-03). Ein einzelner Kundenfall. Die Fehlerkennung und die Version nennt der Beitrag ohne Verweis auf Citrix. |
| Finding in the Wild – When Citrix Director Itself Becomes a Performance Problem | <https://www.deyda.net/index.php/en/2026/10/19/finding-in-the-wild-when-citrix-director-itself-becomes-a-performance-problem/> | 2026-11-13 | `cpu.checks[16]` ‹Anwendung› gehört zu den Citrix-Komponenten des Servers | Stand 19.10.2026, geändert 11.11.2026 (PXG-05). Der Beitrag nennt den Prozess nicht; die Bedingung (Verursacher der Rolle Citrix) ist vorläufig und wird nach der ersten echten Messung überprüft. |
| WEM Administration Console – Part 2 (System Optimization, Policies & Profiles and Security) | <https://www.deyda.net/index.php/en/2022/08/29/wem-administration-console-part-2-system-optimization-policies-profiles-and-security-2/> | 2026-11-13 | `cpu.checks[20]` In Workspace Environment Management prüfen, ob einem Prozess, vor allem ‹Anwendung›, die Priorität „Realtim … | Stand 29.8.2022, geändert 18.8.2026, Text zu WEM 2206 (PXG-10, PXG-19). Die Formel zur CPU-Begrenzung aus demselben Beitrag ist nicht übernommen. |
| Finding in the Wild – Microsoft Teams SlimCore – Where Are the Error Codes? | <https://www.deyda.net/index.php/en/2026/10/21/finding-in-the-wild-microsoft-teams-slimcore-where-are-the-error-codes/> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Stand 21.10.2026, geändert 11.11.2026 (PXG-13). Die Fehlercodes stammen von Microsoft („Troubleshooting the VDI 2.0 solution for Teams“); dass nicht optimierte Medien den Prozessor des Servers belasten, sagt der Beitrag nicht. |
| Finding in the Wild – Citrix WEM – When One User Blocks Other Users' Applications | <https://www.deyda.net/index.php/en/2026/11/03/finding-in-the-wild-citrix-wem-when-one-user-blocks-other-users-applications/> | 2026-11-13 | `delay.many.remedies[1]` „Rule Enforcement Mode“ von WEM Application Security von „Overwrite“ auf „Merge“ stellen, wie die Praxisquelle<br>`delay.single.remedies[1]` „Rule Enforcement Mode“ von WEM Application Security von „Overwrite“ auf „Merge“ stellen, wie die Praxisquelle | Stand 3.11.2026, geändert 11.11.2026 (PXG-45, PXG-46). |
| Finding in the Wild – MCSIO Cache Disk Exists, but Stays Empty | <https://www.deyda.net/index.php/en/2026/09/22/finding-in-the-wild-mcsio-cache-disk-exists-but-stays-empty/> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Stand 22.9.2026, geändert 11.11.2026 (PXG-27 in PXG-26). |
| Optimization of VMs by NUMA | <https://www.deyda.net/index.php/en/2018/11/07/optimization-of-vms-by-numa/> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Stand 7.11.2018, geändert 18.8.2026 (PXG-58). Die Zahl zur Überbuchung beruht auf nicht veröffentlichten Tests und ist nicht übernommen. |
| Finding in the Wild – Citrix CVAD 2603 – Check the MCSIO Driver | <https://www.deyda.net/index.php/en/2026/08/27/finding-in-the-wild-citrix-cvad-2603-check-the-mcsio-driver/> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Stand 27.8.2026, geändert 12.11.2026 (PXG-27 in PXG-26). |

### Stützt bestehende Elemente

Diese Elemente behalten ihre Quelle; ein Satz im Element nennt die Praxisquelle („nach …“ oder mit ihrem Namen).

- Abhilfe „Leerlaufgrenze der Speicheroptimierung von Citrix Workspace Environment Management prüfen …“ der Situation `memory` – auch gestützt durch: „WEM Administration Console – Part 2 (System Optimization, Policies & Profiles and Security)“, <https://www.deyda.net/index.php/en/2022/08/29/wem-administration-console-part-2-system-optimization-policies-profiles-and-security-2/>, 2022-08-29 (PXG-19)
- Prüfschritt „Prüfen, ob Teams in der Sitzung von ‹Benutzer› mit Medienoptimierung …“ der Situation `cpu` – auch gestützt durch: „Finding in the Wild – Microsoft Teams SlimCore – Where Are the Error Codes?“, <https://www.deyda.net/index.php/en/2026/10/21/finding-in-the-wild-microsoft-teams-slimcore-where-are-the-error-codes/>, 2026-10-21 (PXG-13)
- Prüfschritt „Prüfen, ob Teams in der Sitzung von ‹Benutzer› mit Medienoptimierung …“ der Situation `memory` – auch gestützt durch: „Finding in the Wild – Microsoft Teams SlimCore – Where Are the Error Codes?“, <https://www.deyda.net/index.php/en/2026/10/21/finding-in-the-wild-microsoft-teams-slimcore-where-are-the-error-codes/>, 2026-10-21 (PXG-13)
- Prüfschritt „Im Zeitraum hat AppLocker eine Ausführung …“ der Situation `delay.many` – auch gestützt durch: „Finding in the Wild – Citrix WEM – When One User Blocks Other Users' Applications“, <https://www.deyda.net/index.php/en/2026/11/03/finding-in-the-wild-citrix-wem-when-one-user-blocks-other-users-applications/>, 2026-11-03 (PXG-45)
- Prüfschritt „Im Zeitraum hat AppLocker eine Ausführung …“ der Situation `delay.single` – auch gestützt durch: „Finding in the Wild – Citrix WEM – When One User Blocks Other Users' Applications“, <https://www.deyda.net/index.php/en/2026/11/03/finding-in-the-wild-citrix-wem-when-one-user-blocks-other-users-applications/>, 2026-11-03 (PXG-45)
- Prüfschritt „Wenn der Maschinenkatalog MCS I/O nutzt …“ der Situation `disk` – auch gestützt durch: „Finding in the Wild – MCSIO Cache Disk Exists, but Stays Empty“, <https://www.deyda.net/index.php/en/2026/09/22/finding-in-the-wild-mcsio-cache-disk-exists-but-stays-empty/>, 2026-09-22 (PXG-26)
- Prüfschritt „Kein einzelner Verursacher: Auslegung des Servers für den Prozessor prüfen …“ der Situation `chronic.resource` – auch gestützt durch: „Optimization of VMs by NUMA“, <https://www.deyda.net/index.php/en/2018/11/07/optimization-of-vms-by-numa/>, 2018-11-07 (PXG-58)
- Prüfschritt „Wenn der Maschinenkatalog MCS I/O nutzt …“ der Situation `disk` – auch gestützt durch: „Finding in the Wild – Citrix CVAD 2603 – Check the MCSIO Driver“, <https://www.deyda.net/index.php/en/2026/08/27/finding-in-the-wild-citrix-cvad-2603-check-the-mcsio-driver/>, 2026-08-27 (PXG-26)

### Belegstellen

- **Finding in the Wild – When Citrix Suddenly Sends Every User to the Same VDA**
  - „During initialization of the Citrix Group Policy Client-Side Extension (CseEngine), determining the VDA's FQDN may fail. This can prevent load indexes from being reported correctly. Citrix resolved the issue in CVAD 2507 LTSR CU2.“
- **Finding in the Wild – When Citrix Director Itself Becomes a Performance Problem**
  - „In certain Citrix Virtual Apps and Desktops environments, CPU utilization on the VDA can rise considerably when the Session Performance view in Citrix Director is opened and left open.“
- **WEM Administration Console – Part 2 (System Optimization, Policies & Profiles and Security)**
  - „Realtime should not be defined. This can lead to malfunctions in the system.“
  - „The default value is 1% (recommendation is 3%)“
- **Finding in the Wild – Microsoft Teams SlimCore – Where Are the Error Codes?**
  - „2003 / 16026: Citrix Virtual Channel Allow List blocks MSTEAMS, MSTEAM1 or MSTEAM2.“
- **Finding in the Wild – Citrix WEM – When One User Blocks Other Users' Applications**
  - „If enforcement mode Overwrite is enabled in WEM, another user's logon can replace the existing AppLocker policy.“
  - „In WEM Application Security, change Rule Enforcement Mode from Overwrite to Merge.“
- **Optimization of VMs by NUMA**
  - „Newer hardware has fewer NUMA nodes per socket, so the sweet spot (4-8 vCPU) has moved up“

### Nicht aufgenommen

| Empfehlung | Grund |
|---|---|
| Teams Meeting Add-in in 32 oder 64 Bit; bereitgestelltes, aber nicht registriertes Teams | beschreibt keinen Vorfall, den der Bericht erfasst |
| „In CVAD 2507 LTSR CU1 oder CU2 behoben“ als Tatsache | die Seite von Citrix mit den behobenen Fehlern war nicht zu öffnen; das Element schreibt „nach der Praxisquelle“ |
| Überbuchung der Prozessoren mit dem Faktor 2,0; Formel zur CPU-Begrenzung in WEM | die Quelle stützt die Empfehlung nicht oder nur mit geringem Gewicht (nicht veröffentlichte Tests) |

## Aaron Parker (Empfehlung aus der Praxis)

Der Blog stealthpuppy.com von Aaron Parker ist eine Quelle aus der Praxis, keine Dokumentation eines Herstellers: Erfahrung dazu, was Profilcontainer wachsen lässt, und eine gepflegte Liste von Ausschlüssen. Der Auftraggeber hat ihn für einzelne Themen übernommen. Grenzen der Quelle: Alles ist für FSLogix geschrieben; übertragbar auf die Profilcontainer der Citrix Profilverwaltung sind die Pfade und die Gründe, nicht die Mechanismen. Die Kernbeiträge sind von 2019 (Windows Server 2016 und 2019), der Test zur Ordnerumleitung von 2014 (Windows 7 und Windows Server 2008 R2); es gibt keine kontrollierten Messungen, die Zahlen sind Einzelbeobachtungen und stehen nicht im Katalog. Der Autor arbeitet für einen Hersteller von Verwaltungssoftware für Azure Virtual Desktop.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| Support Frontline Workers on Shared Virtual Desktops | <https://stealthpuppy.com/m365apps-frontline-workers/> | 2026-11-13 | `memory.checks[5]` Prüfen, ob der Schnellstart von Microsoft Edge eingeschaltet ist | Stand 9.4.2023 (PXG-23). Belegstelle: „If you’re concerned about CPU and RAM consumption, this may be a trade-off for an improved user experience.“ Der Autor schaltet den Schnellstart für seinen Zweck ein; das Element nennt deshalb eine Abwägung, keinen Rat zum Abschalten. |
| Profile Cleanup - FSLogix docs | <https://stealthpuppy.com/fslogix/profilecleanup/> | 2026-11-13 | `disk.checks[12]` Prüfen, ob bei der Anmeldung ein Skript das Benutzerprofil aufräumt | Seite ohne Datum (PXG-28). Für FSLogix geschrieben; das Skript wirkt auf das eingebundene Profil, das gilt ebenso für die Citrix Profilverwaltung. |
| A Practical Guide to FSLogix Containers Capacity Planning and Maintenance | <https://stealthpuppy.com/fslogix-containers-capacity/> | 2026-11-13 | `disk.remedies[5]` Aufräumen des Benutzerprofils von der Anmeldung auf die Abmeldung oder in eine zeitlich gestaffelte Aufgabe …<br>`profile.remedies[2]` Cache-Ordner von Microsoft Edge vom Profilcontainer ausnehmen<br>`profileerror.checks[11]` Wenn der Profilcontainer voll oder fast voll ist | Stand 23.4.2019 (PXG-29, PXG-40, PXG-41 bis PXG-44, PXG-59, PXG-81). Für FSLogix geschrieben; die Anfangsgröße und die Voreinstellung von 30 GB gelten FSLogix und sind nicht übernommen. |
| Visualizing the Impact of Folder Redirection - Logon and Application Launch | <https://stealthpuppy.com/visualizing-impact-folder-redirection-logon/> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Stand 6.11.2014 (PXG-30). Die Zeiten des Tests (Windows 7, Windows Server 2008 R2) sind nicht übernommen, nur die Richtung. |
| Redirections.csv (ConvertTo-RedirectionsXml) | <https://raw.githubusercontent.com/aaronparker/FSLogix/main/Redirections/Redirections.csv> | 2026-11-13 | `profile.checks[6]` Prüfen, ob der Cache-Ordner von Microsoft Edge vom Profilcontainer ausgenommen ist | Liste ohne Datum (PXG-39). Für FSLogix gepflegt und ausdrücklich nicht abschließend; übernommen ist nur die Zeile zum Cache von Edge. Die Zeilen mit Warnung (Code Cache und ähnliche) sind nicht übernommen. |

### Stützt bestehende Elemente

Diese Elemente behalten ihre Quelle; ein Satz im Element nennt die Praxisquelle („nach …“ oder mit ihrem Namen).

- Abhilfe „Lokale Postfachdaten von Outlook verkleinern …“ der Situation `profile` – auch gestützt durch: „A Practical Guide to FSLogix Containers Capacity Planning and Maintenance“, <https://stealthpuppy.com/fslogix-containers-capacity/>, 2019-04-23 (PXG-41/42)
- Prüfschritt „Größe der Daten von ‹Anwendung› im betroffenen Profilcontainer prüfen …“ der Situation `profile` – auch gestützt durch: „A Practical Guide to FSLogix Containers Capacity Planning and Maintenance“, <https://stealthpuppy.com/fslogix-containers-capacity/>, 2019-04-23 (PXG-43)
- Abhilfe „Datenmenge von ‹Anwendung› im Profil verkleinern, zum Beispiel den Zwischenspeicher begrenzen …“ der Situation `profile` – auch gestützt durch: „A Practical Guide to FSLogix Containers Capacity Planning and Maintenance“, <https://stealthpuppy.com/fslogix-containers-capacity/>, 2019-04-23 (PXG-44)
- Prüfschritt „Größe dieses Profilcontainers prüfen und seine Antwortzeit mit der anderer Profilcontainer …“ der Situation `chronic.resource` – auch gestützt durch: „A Practical Guide to FSLogix Containers Capacity Planning and Maintenance“, <https://stealthpuppy.com/fslogix-containers-capacity/>, 2019-04-23 (PXG-59)
- Prüfschritt „Klären, welche Dateien ‹Anwendung› in der Sitzung von ‹Benutzer› ab …“ der Situation `share` – auch gestützt durch: „Visualizing the Impact of Folder Redirection - Logon and Application Launch“, <https://stealthpuppy.com/visualizing-impact-folder-redirection-logon/>, 2014-11-06 (PXG-30)

### Belegstellen

- **Profile Cleanup - FSLogix docs**
  - „A logon script - the script can be run to prune the user profile during login; however, consider potential login storms and impacts on IO and CPU“
- **A Practical Guide to FSLogix Containers Capacity Planning and Maintenance**
  - „To prune the profile, run the script as a logoff action. A word of caution - this script is unsupported“
  - „Adding redirections after identifying profile locations that consume large amounts of capacity won't remove those locations from existing Profile Containers.“
  - „Start with lowest amount possible and work up depending on user requirements. 3-months is common; however, some users live in Outlook and may need a larger cache.“
  - „The number of applications built on Electron or other platforms that install into the user profile is increasing.“
  - „The container will then grow as it is used, but it does not actively reduce in size unless the disk is compacted.“
  - „If the container fills, applications will not handle the lack of available space gracefully.“
- **Visualizing the Impact of Folder Redirection - Logon and Application Launch**
  - „In this scenario, we've traded slower performance over the session for improved logon speed.“
- **Redirections.csv (ConvertTo-RedirectionsXml)**
  - „Exclude,0,AppData\Local\Microsoft\Edge\User Data\Default\Cache,Microsoft Edge cache,…“

### Nicht aufgenommen

| Empfehlung | Grund |
|---|---|
| Eigener Pfad des Containers je Betriebssystem | in der Zielumgebung gibt es nur ein Betriebssystem der Server |
| Ordner des neuen Teams vom Container ausnehmen (PXG-55) | widerspricht dem Hersteller; hier gilt der Hersteller (Citrix: „Enable roaming for the new Microsoft Teams“, schon im Katalog) |
| Aufgaben „Office Feature Updates“, Zeilen mit Warnung in der Liste der Ausschlüsse (Code Cache und ähnliche) | die Quelle stützt die Empfehlung nicht oder nur mit geringem Gewicht |
| Schnellstart von Edge auch beim Prozessor; Ort der Installation als eigener Schritt | als Satz im vorhandenen Element oder nur in der Situation mit der stärkeren Stütze aufgenommen |

## Trentent Tye (Empfehlung aus der Praxis)

Der Blog von Trentent Tye ist eine Quelle aus der Praxis, keine Dokumentation eines Herstellers: eigene Messungen eines Citrix-Administrators dazu, warum Anmeldungen und Sitzungen langsam werden. Der Auftraggeber hat ihn für einzelne Themen übernommen; verwendet wird nur seine eigene Seite trentent.github.io. Grenzen der Quelle: Jede Messung stammt von XenApp 6.5 oder 7.x auf Windows Server 2008 R2 (eine auf 2016), der letzte hier verwendete Beitrag ist von 2019. Übertragbar ist der Mechanismus, nicht die Zahl; die Zahlen stehen im Katalog nur mit Jahr und Umgebung. Viele Beiträge werben für ein Überwachungswerkzeug, für dessen Hersteller der Autor später arbeitete; ob die Schutzsoftware bei den Tests lief, sagt kein Beitrag.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| ControlUp - Dissecting Logon Times a step further (invalid Home Directory impact) | <https://trentent.github.io/2016/09/07/controlup-dissecting-logon-times-a-step-further-invalid-home-directory-impact/> | 2026-11-13 | `share.checks[5]` Prüfen, ob ‹Gegenstelle› das Basisverzeichnis von Benutzern trägt | Stand 8.9.2016 (PXG-34, PXG-48). Labor mit Windows Server 2008 R2; die gemessenen Sekunden stehen nicht im Katalog. Die Aussage, dafür gebe es keine Abhilfe per Richtlinie, ist nicht übernommen. |
| Group Policy - Monolithic vs Functional Design and Performance Evaluation | <https://trentent.github.io/2018/04/09/group-policy-monolithic-vs-functional-design-and-performance-evaluation/> | 2026-11-13 | `delay.many.contacts[3]` Betreuung der Gruppenrichtlinien, wenn deren Verarbeitung lange dauerte | Stand 9.4.2018 (PXG-49, PXG-50). Labor mit Netzsimulator, nur Richtlinien der Registrierung; die Laborwerte stehen nicht im Katalog. |
| Help! My Citrix application is running slow (Meditech, Citrix, Imprivata) | <https://trentent.github.io/2015/12/19/help-my-citrix-application-is-running-slow-meditech-citrix-imprivata/> | 2026-11-13 | `delay.single.checks[11]` Prüfen, ob die Anwendung, in der der Benutzer wartete, über längere Zeit etwa einen ganzen Prozessor belegte | Stand 19.12.2015 (PXG-53). Ein Fall unter XenApp 6.5 auf einer Maschine mit vier Kernen; die Werte des Falls stehen nicht im Katalog. Die Bedingung der Auswahl (benannter Verursacher) kann bei einer Verzögerung nie zutreffen; das Element steht deshalb ohne Bedingung und nennt die Anwendung nicht mit Namen. |
| ControlUp - Dissecting Logon Times a step further (Printer loading) | <https://trentent.github.io/2016/08/31/controlup-dissecting-logon-times-a-step-further-printer-loading/> | 2026-11-13 | `print.checks[23]` Prüfen, ob die Druckwarteschlangen der Druckserver, die das Zuordnungswerkzeug den Benutzern zuordnet, noch …<br>`print.remedies[15]` Druckwarteschlangen, deren Druckserver es nicht mehr gibt oder der umgezogen ist, aus den Regeln des Zuordn … | Stand 31.8.2016 (PXG-71, PXG-72). XenApp 6.5 auf Windows Server 2008 R2. Dass Windows Server 2022 oder das Zuordnungswerkzeug Drucker nacheinander zuordnen, sagt das Element nicht. |
| Printers and their impact on logon duration | <https://trentent.github.io/2019/03/05/printers-and-their-impact-on-logon-duration/> | 2026-11-13 | `print.remedies[26]` Protokoll „Microsoft-Windows-PrintService/Operational“ einschalten und so groß wählen, dass es die Zeit zwi … | Stand 5.3.2019 (PXG-74). Der Beitrag schaltet das Protokoll ein, um Anmeldezeit Druckern zuzuordnen; ob das Protokoll in der Zielumgebung schon läuft, sieht die Messung nicht. |

### Stützt bestehende Elemente

Diese Elemente behalten ihre Quelle; ein Satz im Element nennt die Praxisquelle („nach …“ oder mit ihrem Namen).

- Abhilfe „Laufwerkszuordnung dort löschen oder berichtigen, wo sie festgelegt ist …“ der Situation `share` – auch gestützt durch: „ControlUp - Dissecting Logon Times a step further (invalid Home Directory impact)“, <https://trentent.github.io/2016/09/07/controlup-dissecting-logon-times-a-step-further-invalid-home-directory-impact/>, 2016-09-08 (PXG-48)
- Abhilfe „Laufwerkszuordnung dort löschen oder berichtigen, wo sie festgelegt ist …“ der Situation `delay.many` – auch gestützt durch: „ControlUp - Dissecting Logon Times a step further (invalid Home Directory impact)“, <https://trentent.github.io/2016/09/07/controlup-dissecting-logon-times-a-step-further-invalid-home-directory-impact/>, 2016-09-08 (PXG-48)
- Abhilfe „Laufwerkszuordnung dort löschen oder berichtigen, wo sie festgelegt ist …“ der Situation `delay.single` – auch gestützt durch: „ControlUp - Dissecting Logon Times a step further (invalid Home Directory impact)“, <https://trentent.github.io/2016/09/07/controlup-dissecting-logon-times-a-step-further-invalid-home-directory-impact/>, 2016-09-08 (PXG-48)
- Prüfschritt „Wenn die Verzögerung in Anmeldungen oder eine Aktualisierung der Gruppenrichtlinien …“ der Situation `delay.many` – auch gestützt durch: „Group Policy - Monolithic vs Functional Design and Performance Evaluation“, <https://trentent.github.io/2018/04/09/group-policy-monolithic-vs-functional-design-and-performance-evaluation/>, 2018-04-09 (PXG-49)

### Belegstellen

- **ControlUp - Dissecting Logon Times a step further (invalid Home Directory impact)**
  - „Since our user has a home directory the preference is to 'always wait for the network to be initialized before logging the user on'.“
- **Group Policy - Monolithic vs Functional Design and Performance Evaluation**
  - „Going from 0ms to 10ms increased the length of time to process a functional design by 15 times! The monolithic design, on the other hand, was barely impacted.“
  - „The goal should be to minimize them to as few as possible.“
- **Help! My Citrix application is running slow (Meditech, Citrix, Imprivata)**
  - „This is a 4 core box, so ~25% equals one full core for a single threaded application.“
- **ControlUp - Dissecting Logon Times a step further (Printer loading)**
  - „All my printers were local except for the 'Generic / Text Only' which was a network printer where I powered off the server. It hung the longest at 5.9 seconds, but I've seen 'non-existant' network mapped printers hang for 150 seconds or so“

### Nicht aufgenommen

| Empfehlung | Grund |
|---|---|
| Dauer je Drucker aus den Ereignissen 306 und 300 des Druckprotokolls ablesen (PXG-73) | gilt nur für ein anderes Produkt oder eine ältere Version; die Quelle sagt nicht, was sich überträgt (das Skript von 2016 misst von Citrix angelegte Sitzungsdrucker, nicht Druckwarteschlangen eines Druckservers) |
| Zeitüberschreitung im Netz verkürzen (InitialRto, MinRto) | setzt eine Änderung voraus, die die Messung nicht stützt |
| Auslastung im Server zeigt die Last des Hosts nicht (Test von 2018 zu Prozessorlücken) | gilt nur für ein anderes Produkt oder eine ältere Version; die Quelle sagt nicht, was sich überträgt; die Aussage ruht auf VMware |
| Gastbeitrag des Autors auf der Seite von Citrix (2020) | verwendet wird nur die eigene Seite des Autors |

## John Billekens (Empfehlung aus der Praxis)

Die Sammlung ave.j81.nl von John Billekens ist eine Quelle aus der Praxis, keine Dokumentation eines Herstellers: Sie trägt die Listen der Scan-Ausschlüsse der Hersteller zusammen, je Zeile mit Verweis auf das Dokument des Herstellers. Der Auftraggeber hat sie für einzelne Themen übernommen. Grenzen der Quelle: Fast nichts darin ist eine eigene Aussage, und sie enthält keine Messung. Sie hat mindestens einen Fehler gegen ihre eigene Quelle und führt einen veralteten Eintrag als aktuell (Stand der Seiten: geprüft am 28.10.2026); jeder Eintrag ist deshalb gegen das Dokument des Herstellers zu lesen. Sie unterscheidet nicht zwischen Microsoft Defender und anderer Schutzsoftware.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| Citrix Workspace Environment Management Infrastructure Service Agent · AV exclusions | <https://ave.j81.nl/items/citrix-workspace-environment-management-infrastructure-service-agent/> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Seite geprüft am 28.10.2026 (PXG-09). Die Liste der Prozesse stammt von Citrix („Endpoint Security, Antivirus, and Antimalware Best Practices“); eigen ist der Hinweis auf den Installationsordner. |
| Citrix · AV exclusions | <https://ave.j81.nl/vendors/citrix/> | 2026-11-13 | `cpu.remedies[14]` Signaturen der Schutzsoftware im Master-Image aktuell halten, damit jeder Server nach seinem Start nur eine …<br>`disk.remedies[2]` Signaturen der Schutzsoftware im Master-Image aktuell halten, damit jeder Server nach seinem Start nur eine … | Seite ohne Datum (PXG-16). „Mindestens monatlich“ ist die Angabe der Sammlung; Citrix nennt im genannten Leitfaden das regelmäßige Aktualisieren des Master-Image ohne Abstand. |
| Citrix Virtual Apps and Desktops VDA (Multi Session) · AV exclusions | <https://ave.j81.nl/items/citrix-virtual-apps-and-desktops-vda-multi-session/> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Seite geprüft am 28.10.2026 (PXG-17). Die Zeile zu picaSvc2.exe gilt nach Citrix nur für Maschinen mit einer Sitzung und ist nicht übernommen. |
| Microsoft Office Outlook · AV exclusions | <https://ave.j81.nl/items/microsoft-office-outlook/> | 2026-11-13 | `crash.checks[26]` Prüfen, ob die Datendateien von Outlook mit den Endungen .ost und .pst von der Echtzeitprüfung ausgenommen …<br>`hang.checks[17]` Prüfen, ob die Datendateien von Outlook mit den Endungen .ost und .pst von der Echtzeitprüfung ausgenommen … | Seite geprüft am 28.10.2026 (PXG-64). Den Grund nennt Microsoft („Plan an Outlook deployment“, Abschnitt zur Schutzsoftware): beschädigte Daten. |
| Microsoft Teams v2 · AV exclusions | <https://ave.j81.nl/items/microsoft-teams-v2/> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Seite geprüft am 28.10.2026 (PXG-65). Die Liste der Prozesse stammt von Microsoft; ms-teams_modulehost.exe steht dort nicht und ist nicht übernommen. |
| Microsoft Windows Server Print Server · AV exclusions | <https://ave.j81.nl/items/microsoft-windows-server-print-server/> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Seite geprüft am 28.10.2026 (PXG-75). Die enge Liste stammt von Microsoft („Microsoft Defender Antivirus exclusions on Windows Server“, Rolle Druckserver); die Zeile der Sammlung zum ganzen Ordner System32\spool ist nicht übernommen. |

### Stützt bestehende Elemente

Diese Elemente behalten ihre Quelle; ein Satz im Element nennt die Praxisquelle („nach …“ oder mit ihrem Namen).

- Prüfschritt „Ausschlüsse der Schutzsoftware mit der Empfehlung aus der Praxis …“ der Situation `cpu` – auch gestützt durch: „Citrix Workspace Environment Management Infrastructure Service Agent · AV exclusions“, <https://ave.j81.nl/items/citrix-workspace-environment-management-infrastructure-service-agent/>, geprüft 2026-10-28 (PXG-09)
- Prüfschritt „Ausschlüsse der Schutzsoftware mit der Empfehlung aus der Praxis …“ der Situation `disk` – auch gestützt durch: „Citrix Workspace Environment Management Infrastructure Service Agent · AV exclusions“, <https://ave.j81.nl/items/citrix-workspace-environment-management-infrastructure-service-agent/>, geprüft 2026-10-28 (PXG-09)
- Abhilfe „Scan-Ausschlüsse ergänzen, die für Terminalserver üblich sind und die die Hersteller der …“ der Situation `cpu` – auch gestützt durch: „Citrix Virtual Apps and Desktops VDA (Multi Session) · AV exclusions“, <https://ave.j81.nl/items/citrix-virtual-apps-and-desktops-vda-multi-session/>, geprüft 2026-10-28 (PXG-17)
- Abhilfe „Scan-Ausschlüsse ergänzen, die für Terminalserver üblich sind und die die Hersteller der …“ der Situation `disk` – auch gestützt durch: „Citrix Virtual Apps and Desktops VDA (Multi Session) · AV exclusions“, <https://ave.j81.nl/items/citrix-virtual-apps-and-desktops-vda-multi-session/>, geprüft 2026-10-28 (PXG-17)
- Abhilfe „Scan-Ausschlüsse ergänzen, die für Terminalserver üblich sind und die die Hersteller der …“ der Situation `share` – auch gestützt durch: „Citrix Virtual Apps and Desktops VDA (Multi Session) · AV exclusions“, <https://ave.j81.nl/items/citrix-virtual-apps-and-desktops-vda-multi-session/>, geprüft 2026-10-28 (PXG-17)
- Abhilfe „Scan-Ausschlüsse ergänzen, die für Terminalserver üblich sind und die die Hersteller der …“ der Situation `profile` – auch gestützt durch: „Citrix Virtual Apps and Desktops VDA (Multi Session) · AV exclusions“, <https://ave.j81.nl/items/citrix-virtual-apps-and-desktops-vda-multi-session/>, geprüft 2026-10-28 (PXG-17)
- Abhilfe „Prozesse von Teams in der Schutzsoftware ausnehmen, wie Microsoft sie nennt …“ der Situation `crash` – auch gestützt durch: „Microsoft Teams v2 · AV exclusions“, <https://ave.j81.nl/items/microsoft-teams-v2/>, geprüft 2026-10-28 (PXG-65)
- Abhilfe „Spool-Ordner in der Schutzsoftware vom Scan ausnehmen …“ der Situation `print` – auch gestützt durch: „Microsoft Windows Server Print Server · AV exclusions“, <https://ave.j81.nl/items/microsoft-windows-server-print-server/>, geprüft 2026-10-28 (PXG-75)

### Belegstellen

- **Citrix Workspace Environment Management Infrastructure Service Agent · AV exclusions**
  - „Make sure to check the installation directory before configuring antivirus exclusions.“
- **Citrix · AV exclusions**
  - „update a master image or vDisk at least once a month“
- **Citrix Virtual Apps and Desktops VDA (Multi Session) · AV exclusions**
  - „%ProgramFiles%\Citrix\HDX\bin\CtxSvcHost.exe [...] CVAD 2112+“
- **Microsoft Office Outlook · AV exclusions**
  - „*.ost [...] If not configured, corruption can occur.“

### Nicht aufgenommen

| Empfehlung | Grund |
|---|---|
| Windows den Standarddrucker verwalten lassen | steht nicht in der Sammlung der Scan-Ausschlüsse, für die die Quelle übernommen ist, und ist für Windows 10 geschrieben |
| Ausschluss von picaSvc2.exe auf Servern mit mehreren Sitzungen; ganzer Ordner System32\spool; ms-teams_modulehost.exe; upmjit.sys | widerspricht dem Hersteller; hier gilt der Hersteller oder der Hersteller nennt den Eintrag nicht |
| Liste der Prozesse und Dateien des VDA als eigenes Element | die Liste stammt von Citrix; die Sammlung steht als Verweis im vorhandenen Vorschlag zu den Scan-Ausschlüssen |

## Guy Leech (Empfehlung aus der Praxis)

Blog und Skripte von Guy Leech sind eine Quelle aus der Praxis, keine Dokumentation eines Herstellers: das Arbeitstagebuch eines Beraters zur Fehlersuche. Der Auftraggeber hat sie für einzelne Themen übernommen. Grenzen der Quelle: Die Beiträge stammen meist von 2014 bis 2019 und beschreiben XenApp 6.5 und 7.x auf Windows Server 2008 R2 und 2012 R2; nichts ist auf Windows Server 2022, mit Machine Creation Services oder mit WEM gemessen. Zahlen gibt es nur als Einzelwerte aus einem Fall. Der Wert der Quelle liegt in der Methode (wo man nachsieht); Ereignisnummern und Registrierungswerte aus seinen Skripten sind auf einem deutschen Windows Server 2022 zu bestätigen.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| The Taming of the Print Server | <https://guyrleech.wordpress.com/2016/02/23/the-taming-of-the-print-server/> | 2026-11-13 | `cpu.checks[21]` Prüfen, ob die Sitzung von ‹Benutzer› im Zeitraum getrennt war | Stand 23.2.2016 (PXG-10, PXG-11, PXG-12). Der Fall ist ein Druckserver mit vier vCPU und über 600 Druckern; „oder High“ bei der Priorität und „getrennte Sitzungen zeigen fast keine CPU“ sind nicht übernommen. |
| Memory Control Script – Capping Leaky Processes | <https://guyrleech.wordpress.com/2018/04/16/memory-control-script-capping-leaky-processes/> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Stand 16.4.2018 (PXG-19). Dass harte Grenzen im Task-Manager nicht sichtbar sind, gilt allgemein für Working-Set-Grenzen und ist nicht auf WEM übertragen. |
| The Curious Case of the Slowly Populating Start Menu | <https://guyrleech.wordpress.com/2016/02/10/the-curious-case-of-the-slowly-populating-start-menu/> | 2026-11-13 | `delay.many.checks[15]` Wenn Anwendungen beim Start der Sitzung oder beim ersten Zugriff aufs Web warteten<br>`delay.single.checks[13]` Wenn Anwendungen beim Start der Sitzung oder beim ersten Zugriff aufs Web warteten | Stand 10.2.2016 (PXG-51). Ein protokollierter Fall unter XenApp 7.7. Das Abschalten per WEM oder Gruppenrichtlinie ist die Umsetzung des Katalogs; der Autor nutzte ein Anmeldeskript. |
| Finding Zombie Processes | <https://guyrleech.wordpress.com/2018/11/02/finding-zombie-processes/> | 2026-11-13 | `chronic.resource.checks[9]` Nach Prozessen suchen, die in Sitzungen zurückgeblieben sind, die es nicht mehr gibt | Stand 2.11.2018 (PXG-60). |
| Find loaded modules.ps1 | <https://raw.githubusercontent.com/guyrleech/Microsoft/master/Find%20loaded%20modules.ps1> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Skript vom 24.10.2019 (PXG-62). Process Explorer als Werkzeug ist die Wahl des Katalogs. |
| Reasons for Reboots – Part 1 | <https://guyrleech.wordpress.com/2014/06/24/reasons-for-reboots-part-1/> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Stand 24.6.2014 (PXG-63). Was ein ausstehender Neustart in einem versiegelten Master-Image bewirkt, ist eine Folgerung des Katalogs und steht nicht im Element. |
| Showing Current & Historical User Sessions | <https://guyrleech.wordpress.com/2018/05/17/showing-current-historical-user-sessions/> | 2026-11-13 | `profileerror.checks[10]` Im Protokoll des Benutzerprofildiensts die Anmeldungen und Abmeldungen des Benutzers nachlesen | Stand 17.5.2018 (PXG-80). Die Lesart „Ereignis 1 ohne Ereignis 4“ folgt aus der Paarung im Skript; dass eine solche Sitzung das Profil noch halten kann, ist die Lesart des Katalogs und so bezeichnet. |
| Get files modified since boot.ps1 | <https://raw.githubusercontent.com/guyrleech/Microsoft/master/Get%20files%20modified%20since%20boot.ps1> | 2026-11-13 | `system.checks[6]` Wenn das Laufwerk aus einem Datenträger- oder Dateisystemfehler das Systemlaufwerk oder der Cache-Datenträg … | Skript ohne Datum (PXG-82). Für einen anderen Bereitstellungsweg geschrieben; die Übertragung auf Machine Creation Services ist die des Katalogs, keine Aussage von Citrix. |
| Guide to my GitHub Scripts | <https://guyrleech.wordpress.com/2018/10/15/guide-to-my-github-scripts/> | 2026-11-13 | – (stützt nur vorhandene Elemente, siehe unten) | Stand 15.10.2018 (PXG-83). Die Ereignisanzeige als Werkzeug ist die Wahl des Katalogs; die Quelle nutzt ihr Skript. |

### Stützt bestehende Elemente

Diese Elemente behalten ihre Quelle; ein Satz im Element nennt die Praxisquelle („nach …“ oder mit ihrem Namen).

- Abhilfe „CPU-Spitzenschutz von Citrix Workspace Environment Management einschalten oder seine …“ der Situation `cpu` – auch gestützt durch: „The Taming of the Print Server“, <https://guyrleech.wordpress.com/2016/02/23/the-taming-of-the-print-server/>, 2016-02-23 (PXG-11)
- Prüfschritt „In Workspace Environment Management prüfen, ob einem Prozess, vor allem ‹Anwendung›, die …“ der Situation `cpu` – auch gestützt durch: „The Taming of the Print Server“, <https://guyrleech.wordpress.com/2016/02/23/the-taming-of-the-print-server/>, 2016-02-23 (PXG-10)
- Abhilfe „Leerlaufgrenze der Speicheroptimierung von Citrix Workspace Environment Management prüfen …“ der Situation `memory` – auch gestützt durch: „Memory Control Script – Capping Leaky Processes“, <https://guyrleech.wordpress.com/2018/04/16/memory-control-script-capping-leaky-processes/>, 2018-04-16 (PXG-19)
- Prüfschritt „Dasselbe Modul war bei mehreren Anwendungen die Absturzstelle …“ der Situation `crash` – auch gestützt durch: „Find loaded modules.ps1“, <https://raw.githubusercontent.com/guyrleech/Microsoft/master/Find%20loaded%20modules.ps1>, 2019-10-24 (PXG-62)
- Prüfschritt „Mehrere Benutzer sind betroffen …“ der Situation `crash` – auch gestützt durch: „Reasons for Reboots – Part 1“, <https://guyrleech.wordpress.com/2014/06/24/reasons-for-reboots-part-1/>, 2014-06-24 (PXG-63)
- Prüfschritt „Zeitraum des Vorfalls in der Expertenansicht …“ der Situation `fallback` – auch gestützt durch: „Guide to my GitHub Scripts“, <https://guyrleech.wordpress.com/2018/10/15/guide-to-my-github-scripts/>, 2018-10-15 (PXG-83)

### Belegstellen

- **The Taming of the Print Server**
  - „I would strongly recommend that you never use the "RealTime" priority as that could cause severe resource shortages if the process granted it is CPU hungry.“
  - „it was mostly being consumed by four explorer processes for four different users who were actually disconnected (in some cases, for many days).“
  - „we shouldn't mess with operating system processes as it can cause deadlocks and similar catastrophic issues.“
- **Memory Control Script – Capping Leaky Processes**
  - „Once implemented, check that hard page fault rates are not impacting performance because the limit you have imposed is too low.“
- **The Curious Case of the Slowly Populating Start Menu**
  - „turned out to be caused by "Automatically Detect Settings" in Internet Properties being ticked“
- **Finding Zombie Processes**
  - „I have had some success in looking for processes whose session id is for a session that no longer exists or which have no threads or open handles“
- **Find loaded modules.ps1**
  - „Designed to help spot processes hooked by 3rd party software like Citrix, Ivanti, Lakeside, etc. Shows module versions so can also be used to play spot the difference between processes.“
- **Reasons for Reboots – Part 1**
  - „I always check PendingFileRenameOperations after an installation even if the installer hasn't requested a reboot.“
- **Showing Current & Historical User Sessions**
  - „The results are obtained from the User Profile Service operational event log“
- **Get files modified since boot.ps1**
  - „a direct correlation between cache used and sizes of files written cannot be calculated by this script since the write cache works at the file system block level“
- **Guide to my GitHub Scripts**
  - „event aggregator.ps1 – retrieve all events from the 300+ event logs on one or more computers and show in sortable/filterable gridview and/or write to csv.“

### Nicht aufgenommen

| Empfehlung | Grund |
|---|---|
| Überwachung von Prozessstart und Prozessende einschalten | die Abstürze kommen schon aus Ereignissen, die den Prozess nennen; die Änderung ist eine Sicherheitsrichtlinie |
| Wiederkehr zur selben Minute der Stunde deutet auf eine geplante Aufgabe (PXG-15) | braucht eine Bedingung, die der Katalog nicht hat; der Rat ist die Lesart der Recherche, kein Zitat |
| Zurückgebliebene Prozesse auch beim einzelnen Speichermangel; Ansicht des Kerns mit einem Debugger | steht nur beim Dauerzustand des Arbeitsspeichers; der Debugger ist kein Schritt für den Bericht |

## Benny Tritsch (Empfehlung aus der Praxis)

Die Beiträge von Benny Tritsch (drtritsch.com, EUC Score) sind eine Quelle aus der Praxis, keine Dokumentation eines Herstellers: Methodik dazu, wie man die Erfahrung der Benutzer misst und Erscheinungen im Bild einordnet. Der Auftraggeber hat sie für einzelne Themen übernommen. Grenzen der Quelle: Sie nennt für keinen Messwert eine Schwelle und gibt keine Einstellung für einen Citrix-Server vor; sie sagt, worauf man sieht, nie ab wann ein Wert schlecht ist. Fast alle Messungen (2023 bis 2026) liefen in Azure auf Windows 11 mit einer Sitzung je Maschine; der einzige Test mit HDX (2025) nennt die Art der Sitzung nicht. EUC Score ist das eigene Produkt des Autors.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| DEX4DaaS - DEX Quality Criteria for DaaS Environments | <https://drtritsch.com/2024/05/25/DEX4DaaS.html> | 2026-11-13 | `delay.many.checks[6]` In Citrix Director die Laufzeit im Netz der betroffenen Sitzungen im Zeitraum nachsehen<br>`delay.single.checks[6]` In Citrix Director die Laufzeit im Netz der betroffenen Sitzung im Zeitraum nachsehen | Stand 25.5.2024 (PXG-52, PXG-61). Methodik ohne Zahlen. Dass der Zähler von Windows nur den Anteil des Servers misst, ist nicht die Aussage der Quelle. |
| A Guide to Common VDI Screen Artifacts and What They Mean | <https://drtritsch.com/2026/03/31/Common-VDI-Screen-Artifacts.html> | 2026-11-13 | `chronic.network.checks[4]` Den Benutzer fragen, wie die Störung aussah | Stand 31.3.2026 (PXG-56). Der Satz zum Test von 2025 stammt aus „Citrix CVAD Performance on Azure [2025]“ (<https://eucscore.com/results/2025-citrix-azure-hdxvsrdp.html>, Test vom 19. und 20.11.2025: VDA 2507 LTSR, Workspace-App 2508, Windows 11 Enterprise, Art der Sitzung nicht genannt); er gilt für diesen Test, nicht für HDX allgemein. |

### Stützt bestehende Elemente

Diese Elemente behalten ihre Quelle; ein Satz im Element nennt die Praxisquelle („nach …“ oder mit ihrem Namen).

- Prüfschritt „In Citrix Director die Netzwerklatenz der betroffenen Sitzung mit dem ICA Round Trip …“ der Situation `chronic.network` – auch gestützt durch: „DEX4DaaS - DEX Quality Criteria for DaaS Environments“, <https://drtritsch.com/2024/05/25/DEX4DaaS.html>, 2024-05-25 (PXG-52)
- Prüfschritt „Prüfen, was ‹Anwendung› in der Sitzung von ‹Benutzer› dauerhaft …“ der Situation `chronic.resource` – auch gestützt durch: „DEX4DaaS - DEX Quality Criteria for DaaS Environments“, <https://drtritsch.com/2024/05/25/DEX4DaaS.html>, 2024-05-25 (PXG-61)

### Belegstellen

- **DEX4DaaS - DEX Quality Criteria for DaaS Environments**
  - „In case of a remote desktop connection, the network's round-trip time (RTT) may play a significant role for the user input delay.“
  - „Endurance: An endurance test simulates the behavior of a system under a sustained load from several hours to several days. This helps bring to light memory leaks and buffer overflows.“
- **A Guide to Common VDI Screen Artifacts and What They Mean**
  - „Frame Freezing: [...] Network latency or jitter causes new frames to arrive late or out of order.“

### Nicht aufgenommen

| Empfehlung | Grund |
|---|---|
| Laute Nachbarn auf demselben Host als Bedeutung des Engpasses (PXG-02) | die Quelle stützt die Empfehlung nicht oder nur mit geringem Gewicht (Azure Virtual Desktop mit Windows 11, zum Teil unter Verschwiegenheit; keine Aussage zur Dichte zulässig) |
| Grenzwerte für Latenz („gut unter …“) | die Quelle nennt keine Schwelle |
| Frage nach dem Aussehen der Störung auch bei einer Verzögerung auf dem Server | die Eingabeverzögerung auf dem Server ist keine Erscheinung im Bild |

## Ausnahmen: Praxisquelle vor Hersteller

Widerspricht eine Quelle aus der Praxis dem Hersteller, gilt der Hersteller, und der Text nennt die andere Sicht. Ausnahmen legt der Auftraggeber fest. Festgelegt ist eine:

- **Energiesparplan.** Die Praxisquellen stellen für Citrix-Server den Plan „Höchstleistung“ ein (Carl Stalhood, Citrix Health Check: „Power management is set to High Performance with no sleep timers“; BIS-F beim Versiegeln des Master-Image). Microsoft liefert Windows Server mit dem Plan „Ausbalanciert“ aus und nennt ihn als empfohlene Vorgabe für allgemeine Last („Overview about power and performance tuning for the Windows Server“, <https://learn.microsoft.com/en-us/windows-server/administration/performance-tuning/hardware/power/power-performance-tuning>, Abruf 2026-11-13). VMware rät, bei der Suche nach der Ursache von Leistungs- und Latenzproblemen in virtuellen Maschinen den Plan „Höchstleistung“ zu wählen („Poor network performance or high network latency on Windows virtual machines“, <https://knowledge.broadcom.com/external/article/310350>, Abruf 2026-11-13). Hier gelten die Praxisquellen. Begründung des Auftraggebers: Die Praxisquellen beziehen sich auf Citrix-Terminalserver und auf Betriebserfahrung, die Dokumentation der Hersteller nicht. Die Elemente dazu (ein Prüfschritt mit der Quelle Carl Stalhood, ein Abhilfevorschlag mit der Quelle BIS-F, in den Situationen `cpu`, `delay.many` und `delay.single`) nennen alle drei Sichten.

Keine Ausnahme ist Receive Side Scaling: BIS-F schaltet es ab, bei Microsoft ist es standardmäßig eingeschaltet; hier gilt der Hersteller, und der Katalog enthält dazu kein Element.

## WorkerPerf

Eigene Hinweise der Auswertung. Diese Elemente der Situation `print` stammen von keinem Hersteller: Sie führen zu
dem, was der Bericht bei der Ursache des Vorfalls nennt (die Muster), oder sagen, was nicht gemessen oder nicht
geprüft wurde und wie sich das nachholen lässt, oder was aus der Zielumgebung folgt (Zuordnung der Drucker durch
ein Zuordnungswerkzeug, Reichweite des Rückblicks). Weil in der Situation `print` jedes Element eine Quelle nennt,
tragen sie die Quelle „WorkerPerf: Hinweis zur Auswertung“. Keines ist als Empfehlung eines Herstellers formuliert,
und keines nennt einen Hersteller.

| Titel | Übernommene Elemente | Hinweis |
|---|---|---|
| Hinweis zur Auswertung | `print.checks[3]` Muster „Speichermangel“: Speichermangel als Ursache prüfen<br>`print.checks[4]` Muster „Modul der Schutzsoftware“: deren Meldungen ansehen<br>`print.checks[5]` Muster „ein Benutzer“: Drucker und Profil dieses Benutzers prüfen<br>`print.checks[6]` Muster „zeitgleich mit einem Leistungsvorfall“: auch dessen Anleitung ansehen<br>`print.checks[7]` Muster „zeitnahes Ereignis“: das Ereignis prüfen<br>`print.checks[25]` Druckproblem vor der Messung: Wiederkehr prüfen<br>`print.checks[27]` Drucken nicht gemessen: von Hand prüfen, nächste Messung mit Drucken<br>`print.checks[28]` Muster nicht geprüft: von Hand eingrenzen<br>`print.checks[29]` Zuordnung der Drucker durch ein Zuordnungswerkzeug bei Anmeldung und Wiederverbindung<br>`print.checks[31]` Vorfall vor der Messung: Reichweite des Rückblicks auf nicht persistenten Servern | Dieselben Hinweise stehen in den anderen Situationen aus Ereignissen ohne Quelle; dort verlangt der Katalog keine. Der Schritt zur Zuordnung der Drucker nennt kein Produkt: Wie PrinTaurus SmartSpread zuordnet, dokumentiert sein Hersteller nicht öffentlich (siehe Abschnitt AKI). |

## Auf dem Zielsystem zu bestätigen

Der Katalog nennt Werkzeuge, Einstellungen und Bezeichnungen von Windows, Citrix und VMware so, wie sie nach bestem
Wissen auf einem deutschen Windows Server 2022 mit Citrix VDA heißen. Geprüft werden konnte das hier nicht. Die
folgenden Angaben sind beim Test auf dem Zielsystem zu bestätigen; stimmt eine nicht, wird der Text im Katalog
angepasst.

- **Abhängigkeit des Dienstes „Druckwarteschlange“** (Prüfschritt „Spool-Ordner und Abhängigkeiten des Dienstes
  „Druckwarteschlange“ prüfen …“ der Situation `print`): Microsoft nennt als Standard für den Wert DependOnService nur
  RpcSs. Ob ein Windows Server 2022 ohne Druckproblem weitere Einträge hat (vermutet wird http), zeigt `sc qc spooler`
  auf einem solchen Server. Der Prüfschritt nennt deshalb als Merkmal nur einen Eintrag, den ein Server ohne
  Druckproblem nicht hat.
- **Drei Gruppenrichtlinien zum Drucken** (Prüfschritt „Ein fehlerhaftes Modul gehört zu einem installierten
  Druckertreiber …“ der Situation `crash`, Prüfschritt „Gruppenrichtlinie zur Treiberisolierung prüfen …“ der Situation
  `print`, Abhilfe „Richtlinie „Override print driver execution compatibility setting reported by print driver“
  aktivieren …“ der Situation `print`): Der Katalog nennt sie englisch wie die Quelle („Isolate print drivers from
  applications“, „Execute print drivers in isolated processes“, „Override print driver execution compatibility setting
  reported by print driver“). Zu bestätigen sind ihre deutschen Anzeigenamen unter Computerkonfiguration >
  Administrative Vorlagen > Drucker und, dass sie auf Windows Server 2022 gelten (die Seite von Microsoft nennt Windows
  10 und 11). Eindeutig sind die Registrierungswerte ApplicationDriverIsolation, PrintDriverIsolationExecutionPolicy und
  PrintDriverIsolationOverrideCompat.
- **Treiberisolierung in der Druckverwaltung** (Prüfschritt „Treiberisolierung von ‹Treiber› prüfen …“ der Situation
  `print`, Abhilfe „Treiber ‹Treiber› in einem eigenen Prozess laufen lassen …“ der Situation `print`): die Stelle
  (Knoten „Treiber“, Kontextmenü des Treibers) und die Bezeichnung des Befehls und seiner Werte. Der Bericht nennt die
  Werte „keine“, „gemeinsam“ und „isoliert“.
- **Ereignisanzeige:** der Kanal „Betriebsbereit“ (englisch „Operational“) unter Anwendungs- und Dienstprotokolle >
  Microsoft > Windows > Windows Defender; die Pfade zu AppLocker und zu SMBClient (Connectivity); die Protokolle
  „Anwendung“ und „System“; die Quellen „Application Error“, „Service Control Manager“, „User Profiles Service“ und
  „Citrix Profile Management“.
- **Task-Manager und Ressourcenmonitor:** die Registerkarten „Benutzer“ und „Details“, die Spalten „CPU“ und
  „Arbeitsspeicher“, der Status „Getrennt“; im Ressourcenmonitor die Registerkarten „Datenträger“ und „Netzwerk“,
  die Bereiche „Prozesse mit Datenträgeraktivität“ und „Prozesse mit Netzwerkaktivität“, die Spalten „Lesen“ und
  „Schreiben“.
- **Dienste und Drucker:** in der Dienste-Konsole der Status „Wird ausgeführt“, der Starttyp „Automatisch“ und die
  Registerkarte „Wiederherstellung“ mit „Keine Aktion durchführen“; in den Druckservereigenschaften die Registerkarte
  „Treiber“; in den Druckereigenschaften Anschlüsse > Anschluss konfigurieren mit „SNMP-Status aktiviert“; „Programme
  und Features“.
- **Profile:** der Wortlaut „temporäres Profil“ in den Meldungen von Windows; der Ordner TEMP unter C:\Users und
  die Einträge mit der Endung .bak unter ProfileList; der Ordner %SystemRoot%\System32\Logfiles\UserProfileManager
  mit dem Protokoll der Citrix Profilverwaltung.
- **Citrix:** die Richtlinien „Universal print driver usage“ und „Printer driver mapping and compatibility“ mit
  ihren Werten (englisch wie in der Quelle); „Profil zurücksetzen“ in Citrix Director; „CPU Spikes Protection“ in
  Citrix Workspace Environment Management; der Dienst „Citrix Print Manager Service“ (CpSvc.exe).
- **VMware:** die CPU-Bereitschaft („Ready“) im Leistungsdiagramm der virtuellen Maschine im vCenter.
- **Standardanwendungen (`src/apps.json`):** die Prozessnamen der Office-Anwendungen (WINWORD.EXE, EXCEL.EXE,
  OUTLOOK.EXE, POWERPNT.EXE, ONENOTE.EXE, MSACCESS.EXE) stehen auf keiner der gelesenen Seiten von Microsoft; belegt
  sind msedge.exe, msedgewebview2.exe, ms-teams.exe und PtSmartSpreadClient.exe. Zu bestätigen sind auch der
  Anzeigename des PrinTaurus SmartSpread Client unter „Programme und Features“ und die deutschen Bezeichnungen in
  Microsoft Edge (Browser-Task-Manager, schlafende Tabs) und in Outlook (Datendateien, Exchange-Cache-Modus).
- **Workspace Environment Management:** der Name des Ereignisprotokolls des Agenten in der Ereignisanzeige („WEM
  Agent Service“, in älteren Texten „Norskale Agent Service“) und die Prozessnamen des Agenten in `src/roles.json`;
  die Kurznamen seiner Dienste dokumentiert Citrix nicht.
- **Teams:** wo der Teams-Client den Stand der VDI-Optimierung anzeigt und wie der Text dort lautet (Microsoft nennt
  für die neue VDI-Lösung „Citrix SlimCore Media Optimized“).
- **Energiesparplan:** die deutschen Namen der Pläne („Höchstleistung“, „Ausbalanciert“) und die Ausgabe von
  „powercfg /getactivescheme“ auf dem Zielsystem.

## Zustandsbild

Der Katalog `src/health.de.json` bewertet das Zustandsbild des Servers. Jede Prüfung nennt im Feld `source` eine Quelle
mit Titel, Adresse und Datum und im Feld `kind` ihre Art: „Empfehlung des Herstellers“ (`vendor`), „Empfehlung aus der
Praxis“ (`practice`) oder „Faustregel“ (`rule`). Dieser Abschnitt weist die Quellen nach. Er enthält die Prüfungen der
Bereiche Größe und Reserve, Betrieb, Sitzungen, Citrix VDA, Profilverwaltung, Drucken, Sicherheitsprodukte, Netz und
Dateiserver, Ereignisbild und Wartung in der Arbeitszeit; der Bereich Anwendungen folgt. Stand: Katalog `version`
2026-11-14.

Wie die Quellen geprüft wurden:

- Jede Quelle wurde am 13. oder 14.11.2026 für diesen Katalog geöffnet und die Aussage, auf die sich eine Prüfung
  stützt, mit dem Text der Seite verglichen. Übernommen ist nur, was die Seite selbst sagt; eine Zahl aus einer Messung
  steht im Katalog mit den Bedingungen der Messung.
- Das Datum im Katalog ist der Stand, den die Seite selbst nennt (bei Microsoft Learn „Last updated on“, bei
  docs.citrix.com „Last published“, bei techdocs.broadcom.com „Last Updated“, bei einem Blog das Datum des Beitrags).
  Nennt eine Seite keinen Stand, steht das Datum des Abrufs da.
- Die Seiten von Citrix unter docs.citrix.com stehen mit der Adresse da, die sie am 14.11.2026 haben: Die früheren
  Adressen mit `/en-us/` leiten heute auf `/us/en/` weiter (derselbe Pfad).
- Eine Prüfung aus einer Praxisquelle heißt nie „Empfehlung des Herstellers“. Widerspricht eine Praxisquelle dem
  Hersteller, gilt der Hersteller, und der Katalog nennt den Widerspruch. Die Ausnahmen legt der Auftraggeber fest; sie
  stehen unten.
- Der Katalog gilt für nicht persistente Multi-Session-Server, die über Machine Creation Services bereitgestellt werden.
  Empfehlungen, die nur für andere Bereitstellungsarten, persistente Maschinen oder Einzelplatz-Desktops gelten, sind
  nicht aufgenommen.

### Praxisquellen

Die geltende Liste der Praxisquellen. Eine weitere Quelle kommt nur mit Zustimmung des Auftraggebers hinzu.

| Name | Adresse | Stand der Recherche |
|---|---|---|
| BIS-F | https://eucweb.com/ | recherchiert |
| Carl Stalhood | https://www.carlstalhood.com/ | recherchiert |
| GO-EUC | https://www.go-euc.com/ | recherchiert |
| James Kindon | https://jkindon.com/ | recherchiert |
| James Rankin | https://james-rankin.com/ | recherchiert |
| Thomas Kötzing | https://koetzingit.de/ | recherchiert |
| Manuel Winkel | https://www.deyda.net/ | recherchiert |
| Aaron Parker | https://stealthpuppy.com/ | recherchiert |
| Trentent Tye | https://trentent.github.io/ | recherchiert |
| John Billekens | https://ave.j81.nl/ | recherchiert |
| Guy Leech | https://guyrleech.wordpress.com/ | recherchiert |
| Benny Tritsch | https://eucscore.com/ | recherchiert |

Kasper Johansen stand ebenfalls auf der Liste des Auftraggebers: Sein Blog ist nicht mehr erreichbar, nicht verwendet.

Alle zwölf Quellen wurden am 13.11.2026 recherchiert, jeder Eintrag mit einer Gegenprüfung an der Seite. Die Art
`practice` tragen Prüfungen, deren Quelle carlstalhood.com, BIS-F oder Trentent Tye ist. Acht weitere Praxisquellen
stehen als zweite Quelle im Text einzelner Prüfungen (unten: „auch gestützt durch“). Von Benny Tritsch stützt sich in
den zehn Bereichen dieses Abschnitts keine Prüfung.

### Quellen aus der Praxis: BIS-F

Base Image Script Framework (BIS-F), ein Werkzeug zum Versiegeln von Abbildern. Die Quelle ist für Windows Server 2022
sichtbar älter: Dokumentation „7.1912“ (Dezember 2019 bis Januar 2020), die Liste der Betriebssysteme endet bei Windows
Server 2019. Der Katalog kennzeichnet sie deshalb als ältere Praxis.

| Titel | Adresse | Stand der Seite | Abruf | Prüfungen |
|---|---|---|---|---|
| 97_PrepBISF_PRE_BaseImage.ps1 (Skript im Quelltext von BIS-F) | https://raw.githubusercontent.com/EUCweb/BIS-F/master/Framework/SubCall/Preparation/97_PrepBISF_PRE_BaseImage.ps1 | letzter Eintrag der Historie im Skript: 22.11.2020 | 2026-11-13 | `operation.powerPlan` (zweite Praxisquelle im Text: BIS-F stellt beim Versiegeln den Plan „High Performance“ ein, ohne Bedingung) |
| Configure Citrix Workspace Environment Agent (WEM) | https://eucweb.com/docs/bisf-7-1912/gpo-configuration/citrix/configure-citrix-workspace-environment-agent-wem | Dokumentation 7.1912 | 2026-11-13 | `vda.wemCache` (im Vorschlag zum Vorgehen: BIS-F bietet eine eigene Richtlinie an, die den Cache des WEM-Agenten auf den beständigen Datenträger legt; für MCS setzt das einen VDA ab 1903 mit Speicheroptimierung (MCSIO) voraus) |
| BISF.psm1 (Quelltext von BIS-F, Funktionen Use-BISFMCSConfig und Move-BISFEvtLogs) | https://raw.githubusercontent.com/EUCweb/BIS-F/master/Framework/SubCall/Global/BISF.psm1 | Quelltext ohne Datum | 2026-11-14 | `events.sinceBoot` (BIS-F verlegt die Ereignisprotokolle auf den Cache-Datenträger, für MCS nur mit einem VDA ab 1903 und der Richtlinie „Configure Citrix MCS Device“; dass sie so einen Neustart überstehen, ist eine Folgerung des Katalogs) |
| BaseImageScriptFramework.adml (Hilfetexte der Richtlinienvorlage, Text `POL_MCSCfg_Help`) | https://raw.githubusercontent.com/EUCweb/BIS-F/master/ADMX/en-US/BaseImageScriptFramework.adml | Quelltext ohne Datum | 2026-11-14 | `events.sinceBoot` („With a configured MCSIO Disk the event logs and spool directory is redirected to the persistent drive“) |
| System Optimizations | https://eucweb.com/docs/bisf-7-1912/system-optimizations | 2020-01-08 | 2026-11-14 | `maintenance.updateServiceEnabled` („Set Windows Update Service to Disabled“; die Seite nennt keinen Zweck, die Begründung im Text der Prüfung ist die des Katalogs); `network.rss` (der Schritt „Disable Receive Side Scaling (RSS)“: BIS-F widerspricht hier VMware, es gilt der Hersteller) |
| 7.1912.0 (Versionshinweise) | https://eucweb.com/docs/bis-f-release-notes/7-x-all-version/7-1912-0 | Dokumentation 7.1912 | 2026-11-14 | `network.rss` (die Versionshinweise nennen „Removed the disabling of Receive Side Scaling“; Skript und Seite „System Optimizations“ führen den Schritt weiter) |

### Quellen aus der Praxis: carlstalhood.com

Anleitungen von Carl Stalhood. Die Seiten decken Citrix Virtual Apps and Desktops bis 2411 ab; die Seite zu den
Gruppenrichtlinien ist älter und nennt Windows Server 2022 nur am Rand.

| Titel | Adresse | Stand der Seite | Abruf | Prüfungen |
|---|---|---|---|---|
| Citrix Virtual Delivery Agent (VDA) 2411 | https://www.carlstalhood.com/virtual-delivery-agent-vda-cr/ | 2024-12-04 | 2026-11-13 | `size.workerCpu`, `size.workerCpuMax` (8 vCPU für Multi-Session-Server mit Windows Server 2022, 2019 oder 2016), `size.workerMemory` (24 bis 48 GB; mit einem Schreibcache im Arbeitsspeicher mehr; die Schwelle des Katalogs liegt mit 24000 MB knapp unter 24 GB, siehe „Schwellen“), `security.networkProtection` („Disable Network protection and configure Citrix’s antivirus exclusions“; Stalhood nennt als Quelle den Citrix-Artikel CTX319676, der sich nicht öffnen ließ; der Netzwerkschutz ist eine Schutzfunktion, die Entscheidung liegt beim Sicherheitsteam) |
| Citrix Health Check | https://www.carlstalhood.com/citrix-health-check/ | 2024-02-28 | 2026-11-13 | `size.commitAboveRam` (Arbeitsspeicher der virtuellen Maschine mindestens so groß wie der zugesagte Speicher), `operation.uptime` (Multi-Session-Server regelmäßig neu starten; die Seite nennt keine Zahl, die Schwelle ist ein Vorschlag des Katalogs), `operation.updateAge` (letzte Installation eines Updates höchstens 60 Tage alt), `operation.powerPlan` („Power management is set to High Performance with no sleep timers“) |
| Group Policy Computer Settings for VDAs | https://www.carlstalhood.com/group-policy-objects-vda-computer-settings/ | 2023-11-03 | 2026-11-13 | `sessions.disconnectLimit`, `sessions.idleLimit` (Zeitlimits per Gruppenrichtlinie, „3 hours or similar“: eine Größenordnung, keine Schwelle; die Prüfliste „Citrix Health Check“ nennt die Zeitlimits ebenfalls) |
| Workspace Environment Management (WEM) 2411 | https://www.carlstalhood.com/workspace-environment-management/ | 2024-12-07 | 2026-11-14 | `security.wemExclusions` (der Programmordner des WEM-Agenten oder seine Prozesse „must be excluded from Antivirus scanning“) |

Nicht übernommen aus diesen Seiten, weil die Gegenprüfung es nicht trägt: beim zugesagten Speicher der Höchststand seit
dem Start und eine Mindestlaufzeit (stehen nicht auf der Seite); bei den Zeitlimits die Aussage, sie gehörten nur in die
Gruppenrichtlinie von Microsoft (neuere Seiten von Stalhood nennen die Sitzungs-Timer der Citrix-Richtlinie als
gleichwertigen Weg); beim Energiesparplan die Zeiten bis zu Standby und Ruhezustand (das Zustandsbild liest sie nicht).

### Quellen aus der Praxis: trentent.github.io

Beiträge von Trentent Tye. Der Beitrag ist von 2019 und zeigt die Auswertung für Drucker, die Citrix anlegt, und für
direkt verbundene Drucker.

| Titel | Adresse | Stand der Seite | Abruf | Prüfungen |
|---|---|---|---|---|
| Printers and their impact on logon duration | https://trentent.github.io/2019/03/05/printers-and-their-impact-on-logon-duration/ | 2019-03-05 | 2026-11-14 | `print.operationalLogOff` (das Betriebsprotokoll des Druckdienstes ist eine der vier Protokollierungen, die seine Auswertung der Anmeldedauer auf dem Server braucht: „additional logging is required on the Citrix server side“; eine Größe des Protokolls und Ereigniskennungen sind nicht übernommen) |

### Weitere Praxisquellen als zweite Quelle

Der Katalog führt je Prüfung eine Quelle im Feld `source`. Wo eine weitere Praxisquelle dieselbe Prüfung stützt, steht
ihre Aussage im Text der Prüfung, mit dem Namen der Quelle und, bei einer Messung, mit deren Bedingungen. Die Art der
Prüfung ändert sich dadurch nicht. Abruf der Seiten: 2026-11-13, für die Prüfungen der Bereiche Drucken bis Wartung in
der Arbeitszeit 2026-11-14.

- `size.workerCpu`, `size.workerCpuMax` – auch gestützt durch: GO-EUC, „Impact of sizing RDSH VMs“,
  https://www.go-euc.com/impact-of-sizing-rdsh-vms/, 2019-02-27. Lasttest von 2019 mit Windows Server 2016 unter ESXi
  6.7 U1 auf zwei Xeon E5-2680 v4, Schutzmaßnahmen gegen Spectre und Meltdown abgeschaltet; die genauen Zahlen sind für
  heutige Prozessoren nicht belegt. Die Empfehlung „höchstens 8 vCPU je Maschine“ und die Regel zur Summe der vCPU eines
  Hosts sind Rat der Autoren, kein Messwert.
- `size.pagefilePresent` – auch gestützt durch: GO-EUC, „Page file sizing for virtualized environments“,
  https://www.go-euc.com/page-file-sizing-for-virtualized-environments/, 2019-12-03. Test von 2019 mit Windows 10 1803
  (eine Sitzung je Maschine), 2 vCPU und 4 GB, MCS 1906.1; übernommen ist nur die Beobachtung, dass die Maschinen ohne
  Auslagerungsdatei unter Speicherdruck abstürzten. Der Rat zur Größe der Datei ist nicht übernommen; dass die Größe der
  Datei in diesem Test keinen messbaren Unterschied machte, steht nur hier, nicht im Text der Prüfung.
- `operation.pendingRestart` – auch gestützt durch: Guy Leech, „Reasons for Reboots – Part 1“,
  https://guyrleech.wordpress.com/2014/06/24/reasons-for-reboots-part-1/, 2014-06-24. Aus der Zeit von Windows 7 und
  Windows Server 2008 R2; steht nur im Vorschlag zum Vorgehen (im Abbild nach jeder Installation prüfen). Der
  Mechanismus selbst ist der von Microsoft dokumentierte.
- `operation.diskFree` – auch gestützt durch: Thomas Kötzing, „Citrix Maschinenerstellungsdienste (MCS) – Skript zum
  Auslesen des RAM- und Disk-Cache“,
  https://koetzingit.de/blog/2024/03/18/citrix-maschinenerstellungsdienste-mcs-skript-zum-auslesen-des-ram-und-disk-cache/,
  2024-03-18. Gilt nur, wo MCS mit Speicheroptimierung eingerichtet ist; der Text der Prüfung sagt das.
- `sessions.disconnectLimit` – auch gestützt durch: James Rankin, „Windows session timeouts on Citrix – a brief guide“,
  https://james-rankin.com/articles/windows-session-timeouts-on-citrix-a-brief-guide/, 2023-03-08 (Richtlinie statt
  Benutzerobjekt; zwei Stunden als sein Beispiel für einfache Benutzer); James Kindon, „Citrix Session Management
  Policies“, https://jkindon.com/citrix-session-management-policies/, 2021-08-09 (die Werte am Benutzerobjekt greifen
  nur, wo nichts anderes gesetzt ist); Guy Leech, „The Taming of the Print Server“,
  https://guyrleech.wordpress.com/2016/02/23/the-taming-of-the-print-server/, 2016-02-23 (nur als Beispiel und nur hier,
  nicht im Text der Prüfung: ein Druckserver mit vier Prozessoren, auf dem über Tage getrennte Verwaltungssitzungen den
  größten Teil der Rechenleistung banden; kein Multi-Session-Server).
- `sessions.idleLimit` – auch gestützt durch: James Rankin, „Windows session timeouts on Citrix – a brief guide“,
  https://james-rankin.com/articles/windows-session-timeouts-on-citrix-a-brief-guide/, 2023-03-08; James Kindon, „Citrix
  Session Management Policies“, https://jkindon.com/citrix-session-management-policies/, 2021-08-09. Das Beispiel von
  Guy Leech ist hier nicht verwendet: Es handelt von getrennten Sitzungen.
- `sessions.tempProfiles` – auch gestützt durch: Thomas Kötzing, „Powershell-Skript zum Löschen von temporären
  Benutzerprofilen“,
  https://koetzingit.de/blog/2024/09/10/powershell-skript-zum-loeschen-von-temporaeren-benutzerprofilen/, 2024-09-10.
  Gezeigt mit FSLogix; die Profilliste gehört zu Windows. Das Löschen von Einträgen auf dem laufenden Server ist nicht
  als Abhilfe übernommen.
- `vda.wemCache` – auch gestützt durch: Manuel Winkel, „Finding in the Wild | Sometimes Old Citrix Problems Simply
  Return“,
  https://www.deyda.net/index.php/en/2026/09/26/finding-in-the-wild-sometimes-old-citrix-problems-simply-return/,
  2026-09-26 (eigene Beobachtung mit WEM 2507 CU1 und eigenen WEM-Servern auf nicht persistenten VDAs: Der Cache wurde
  beim Start nicht aufgebaut, geholfen hat, ihn neu aufzubauen; keine öffentliche Fehlernummer von Citrix); James
  Kindon, „The why does it of Citrix WEM Cache“, https://jkindon.com/the-why-does-it-of-citrix-wem-cache/, 2020-10-15
  (nur als Vorgeschichte und nur hier, nicht im Text der Prüfung: Agenten vor Version 2012 übersprangen beim Start den
  ersten Abgleich, wenn schon ein Cache da war; aktuelle Agenten verwerfen nach Citrix auf bereitgestellten Maschinen
  die Cache-Dateien, die aus dem Abbild stammen).
- `profile.containerFull` – auch gestützt durch: Aaron Parker, „A Practical Guide to FSLogix Containers Capacity
  Planning and Maintenance“, https://stealthpuppy.com/fslogix-containers-capacity/, 2019-04-23. Geschrieben für FSLogix;
  übernommen sind nur die Folge eines vollen Containers und der Rat, die Größe nicht knapper zu begrenzen als nötig.
  Keine Zahl des Katalogs stammt von dort.
- `profile.containersPerUser` – auch gestützt durch: Aaron Parker, „A Practical Guide to FSLogix Containers Capacity
  Planning and Maintenance“, https://stealthpuppy.com/fslogix-containers-capacity/, 2019-04-23 (zusätzlicher
  Speicherplatz bei gleichzeitigen Sitzungen; für FSLogix); James Rankin, „QuickPost – getting started with Citrix UPM
  Containers“, https://james-rankin.com/articles/quickpost-getting-started-with-citrix-upm-containers/, 2023-09-08 (die
  Citrix Profilverwaltung schreibt einen Differenzdatenträger und führt ihn bei der Abmeldung zurück).
- `print.driversInSpooler` – auch gestützt durch: Thomas Kötzing, „Die zehn Regeln zum Drucken unter Citrix“,
  https://koetzingit.de/blog/2017/02/08/die-zehn-regeln-zum-drucken-unter-citrix/, 2017-02-08 (Treiber von
  Drittherstellern isoliert betreiben, genannt für den HP Universal Printing Driver; die Angabe „mindestens Version 5.x“
  ist überholt und nicht übernommen); Thomas Kötzing, „Ein echter Kunden-Support-Fall, gelöst mit Hilfe von KI!“,
  https://koetzingit.de/blog/2025/05/27/ein-echter-kunden-support-fall-geloest-mit-hilfe-von-ki/, 2025-05-27 (ein Fall
  mit wiederholten Abstürzen des Druckdienstes und einem Treiber von Konica Minolta von 2021: empfohlen sind ein neuerer
  64-Bit-Treiber und die Isolierung per Gruppenrichtlinie; übernommen sind die Empfehlungen, kein Ergebnis, und nicht
  die Erklärung des Beitrags zu 32-Bit-Treibern).
- `print.isolationOff` – auch gestützt durch: dieselben zwei Beiträge von Thomas Kötzing,
  https://koetzingit.de/blog/2017/02/08/die-zehn-regeln-zum-drucken-unter-citrix/, 2017-02-08, und
  https://koetzingit.de/blog/2025/05/27/ein-echter-kunden-support-fall-geloest-mit-hilfe-von-ki/, 2025-05-27
  („Aktivierung der Druckerisolierung per GPO, damit der Druckerdienst erst gar nicht abstürzt“). Die Art der Prüfung
  bleibt `rule`; der Name der Richtlinie „Druckertreiber in isolierten Prozessen ausführen“ stammt aus dem Beitrag von
  2017.
- `print.driverCount` – auch gestützt durch: Thomas Kötzing, „Die zehn Regeln zum Drucken unter Citrix“,
  https://koetzingit.de/blog/2017/02/08/die-zehn-regeln-zum-drucken-unter-citrix/, 2017-02-08 („Immer erst die nativen
  Microsoft-Druckertreiber verwenden, die mit dem Betriebssystem kommen“); Thomas Kötzing, „Citrix StressPrinters
  verstehen und nutzen“, https://koetzingit.de/blog/2007/11/20/citrix-stressprinters-verstehen-und-nutzen/, 2007-11-20
  (Treiber vor der Übernahme unter Last testen; die Messwerte von 2007 und der Name des Werkzeugs sind nicht
  übernommen). Keine Zahl des Katalogs stammt von dort.
- `security.signatureAge` – auch gestützt durch: John Billekens, „Citrix · AV exclusions“,
  https://ave.j81.nl/vendors/citrix/, ohne Datum, Abruf 2026-11-14 (seine eigene Sicht: das Abbild mindestens einmal im
  Monat aktualisieren, Signaturen beim Start und in zufälligen Abständen während der Arbeitszeit; der verzögerte Start
  der Citrix-Dienste, den er ebenfalls nennt, ist nicht übernommen). Citrix selbst nennt im Artikel CTX696648 keinen
  Abstand („Automating this process is recommended, so is updating the master image regularly with the latest
  signatures“).
- `security.citrixExclusions` – auch gestützt durch: James Rankin, „The ultimate guide to Windows logon time
  optimizations, part #10“,
  https://james-rankin.com/features/the-ultimate-guide-to-windows-logon-time-optimizations-part-10/, 2021-11-19 („Quite
  a marked increase – over 40 seconds for Server 2019“; gemessen 2021 mit Windows Server 2019, einem anderen
  Schutzprodukt als Defender und dateibasierter Citrix Profilverwaltung; Defender war nicht Teil des Tests; mit
  Ausschlüssen blieb die Wirkung nach Rankin spürbar, aber deutlich kleiner).
- `security.wemExclusions` – auch gestützt durch: Citrix, „Endpoint Security, Antivirus, and Antimalware Best Practices“
  (CTX696648), Abschnitt „Workspace Environment Management“,
  https://support.citrix.com/external/article/CTX696648/endpoint-security-antivirus-and-antimalw.html, Abruf 2026-11-14
  (Citrix nennt den Programmordner des Agenten und seine Prozesse). Microsoft rät bei Defender davon ab, Programmordner
  installierter Anwendungen auszunehmen (siehe „Weitere Seiten der Hersteller“); der Text der Prüfung nennt beide
  Sichten. Die Art der Prüfung bleibt `practice` mit Carl Stalhood als Quelle, wie der Plan sie festlegt.
- `maintenance.sessionTriggerTasks` – auch gestützt durch: James Rankin, „The ultimate guide to Windows logon time
  optimizations, part #8“,
  https://james-rankin.com/features/the-ultimate-guide-to-windows-logon-time-optimizations-part-8/, 2021-09-14 („We've
  removed 4-5 seconds of logon time in each instance“; gemessen 2021 mit Windows Server 2019 und Windows 10 an sechs
  Programmen, die bei der Anmeldung starten, überwiegend Autostart-Einträge je Benutzer; als entbehrlich nennt er
  „OneNote QuickNotes, Adobe Reader and Google Chrome update tasks“). Die Zahl ist keine Schwelle.

### Ausnahmen: Praxisquelle vor Hersteller

Der Katalog führt die Ausnahmen im Teil `precedence`. Festgelegt ist eine.

**Energiesparplan (`operation.powerPlan`).** Die Prüfung meldet „prüfen“, wenn der aktive Plan nicht „Höchstleistung“
ist. Begründung des Auftraggebers (13.11.2026): Die Praxisquellen beziehen sich ausdrücklich auf Citrix-Terminalserver
und Betriebserfahrung, die Herstellerdokumentation nicht.

- Praxisquellen: Carl Stalhood, „Citrix Health Check“ (oben); BIS-F stellt beim Versiegeln denselben Plan ein (oben).
- Microsoft, „Overview about power and performance tuning for the Windows Server“,
  https://learn.microsoft.com/en-us/windows-server/administration/performance-tuning/hardware/power/power-performance-tuning
  (Stand der Seite 2022-08-29, Abruf 2026-11-13): „Balanced (recommended)“ ist die Vorgabe; „High Performance“ nennt die
  Seite für Anwendungen, die auf Verzögerungen empfindlich reagieren. Der Katalog nennt das im Text der Prüfung.
- VMware, „Poor network performance or high network latency on Windows virtual machines“,
  https://knowledge.broadcom.com/external/article/310350 (Stand der Seite 2025-07-21, Abruf 2026-11-13): „High
  performance“ für die Zeit, in der Leistungsprobleme untersucht werden. Der Artikel begründet das mit einer Beobachtung
  von Microsoft unter Windows Server 2008 und 2008 R2 und sagt nur, die Umstellung könne die Leistung erhöhen („may
  increase overall performance“); für neuere Windows-Versionen bestätigt er es nicht eigens. Der Katalog nennt diesen
  Vorbehalt im Text der Prüfung.
- Andere Sicht aus der Praxis: GO-EUC, „Beyond Balanced: Benchmarking Windows 11 Power Plans“,
  https://www.go-euc.com/beyond-balanced-benchmarking-windows-11-power-plans/, 2026-09-15: In diesem Test brachte der
  Wechsel von „Balanced“ zu „High performance“ nur einen geringen Gewinn an Leistung („a slight increase in
  performance“) und bei der gemessenen Benutzererfahrung kaum oder keinen Unterschied („minimal to no difference in the
  UX Score“). Gemessen mit Windows 11 und einer Sitzung je Maschine auf Azure, Defender abgeschaltet; die
  Leerlaufzustände der Prozessoren waren nicht Teil der Messung. Für Windows Server mit vielen Sitzungen unter vSphere
  hat GO-EUC in diesem Test nicht gemessen. Der Katalog nennt die Messung mit diesen Bedingungen und zieht daraus keinen
  Schluss für andere Umgebungen; sie ändert weder Regel noch Einstufung.

### Herstellerquellen

| Hersteller | Titel | Adresse | Stand der Seite | Abruf | Prüfungen |
|---|---|---|---|---|---|
| Microsoft | How to determine the appropriate page file size for 64-bit versions of Windows | https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/how-to-determine-the-appropriate-page-file-size-for-64-bit-versions-of-windows | 2026-02-12 | 2026-11-13 | `size.pagefilePresent` (`vendor`); als Beleg der Faustregeln `size.commitHeadroom` (Zusagegrenze = Arbeitsspeicher und alle Auslagerungsdateien) und `operation.diskFree` (eine vom System verwaltete Auslagerungsdatei wächst nur, solange Platz frei ist) |
| Microsoft | Microsoft Edge for Virtual desktop infrastructure (VDI) | https://learn.microsoft.com/en-us/deployedge/edge-for-virtualized-desktop-infrastructure | 2026-11-03 | 2026-11-13 | als Beleg der Faustregel `size.memoryPerSession` (1 GB Arbeitsspeicher je Benutzer für Microsoft Edge; die Seite sagt „VDI“ und nennt Multi-Session-Server nicht eigens) |
| Microsoft | Performance Tuning Remote Desktop Session Hosts | https://learn.microsoft.com/en-us/windows-server/administration/performance-tuning/role/remote-desktop/session-hosts | 2020-09-14 | 2026-11-13 | `maintenance.sessionTriggerTasks` (`vendor`: „it is useful to focus specifically on the tasks that are configured to run on idle, at user sign-in, or on session connect and disconnect“; die Seite lässt diese Aufgaben ansehen, sie nennt sie nicht fehlerhaft); als Beleg der Faustregel `size.cpuPerSession` (Rechenleistung je Sitzung mal Zahl der Sitzungen plus Reserve; diese Seite nennt keine Zahl) |
| Microsoft | MoveFileExA function (winbase.h) | https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-movefileexa | 2023-06-01 | 2026-11-13 | als Beleg der Faustregel `operation.pendingRestart` (die Seite beschreibt den Wert `PendingFileRenameOperations`; was ein Eintrag auf einem nicht persistenten Server bedeutet, ist die Faustregel des Katalogs und steht nicht auf der Seite) |
| VMware | VMware Tools Lifecycle Management | https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/tools/13-0-0/vmware-tools-administration/introduction-to-vmware-tools/vmware-tools-lifecyle-management.html | 2026-05-08 | 2026-11-13 | `size.vmTools` (Windows Server 2022: ab 10.3.5, für die beste Leistung ab 12.0.0; Windows Server 2025: ab 11.3.0, für die beste Leistung ab 12.5.0; die Seite führt die Angaben unter „VMware Tools support for Guest Operating Systems“, ein Stand unter dem Mindeststand ist danach nicht unterstützt) |
| VMware | Solutions for Memory Performance Problems | https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/vsphere-monitoring-and-performance/monitoring-inventory-objects/troubleshoot-and-enhance-performance/memory-performance-solutions.html | 2026-10-28 | 2026-11-13 | `size.balloonDriver` |
| VMware | Poor network performance or high network latency on Windows virtual machines | https://knowledge.broadcom.com/external/article/310350 | 2025-07-21 | 2026-11-13 | `size.netAdapterType` (der Artikel setzt VMXNET3 voraus, bevor weiter gesucht wird; eine allgemeine Pflicht nennt er nicht; die Seite „Citrix Virtual Delivery Agent (VDA) 2411“ von Carl Stalhood nennt für vSphere ebenfalls VMXNET3), `network.rss` („Ensure that RSS is enabled in the guest operating system“; „Changing the RSS settings should only be done by trained network administrators“) |
| VMware | SCSI, SATA, and NVMe Storage Controller Conditions, Limitations, and Compatibility | https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/vsphere-virtual-machine-administration/configuring-virtual-machine-hardware/scsi-controller-configuration.html | 2026-10-28 | 2026-11-13 | `size.storageController` (nur ein Hinweis: VMware knüpft den Vorteil an E/A-starke Last und nennt den Adapter für direkt angeschlossenen Speicher nicht geeignet, siehe unten) |
| Citrix | VDA registration | https://docs.citrix.com/us/en/citrix-virtual-apps-desktops/2203-ltsr/manage-deployment/vda-registration.html | 2026-11-12 | 2026-11-13 | `vda.controllerCount`, `vda.controllerNotFqdn`, `vda.listOfSids` |
| Citrix | WEM health check tool | https://docs.citrix.com/us/en/workspace-environment-management/current-release/reference/wem-health-check-tool.html | 2026-11-12 | 2026-11-13 | `vda.wemServices` |
| Citrix | Agent (install and configure) | https://docs.citrix.com/us/en/workspace-environment-management/current-release/install-and-configure/agent-host.html | 2026-11-12 | 2026-11-13 | `vda.wemCache` (Abschnitt „Prerequisites“), `vda.wemGpTimeout` (Abschnitt „System settings“) |
| Citrix | Profile Management policy descriptions and defaults | https://docs.citrix.com/us/en/profile-management/current-release/settings/descriptions-and-defaults.html | 2026-10-29 | 2026-11-13 | als Beleg der Faustregel `profile.containerFull` (90 % ist die Vorgabe für die Belegung, ab der ein Container automatisch vergrößert wird; keine Empfehlung im engen Sinn) |
| Microsoft | Printer Driver Isolation | https://learn.microsoft.com/en-us/windows-hardware/drivers/print/printer-driver-isolation | 2025-05-01 | 2026-11-14 | `print.driversInSpooler` (`vendor`: „By isolating the driver, the administrator can prevent a fault in a driver component from halting the print service“); als Beleg der Faustregel `print.isolationOff` (die Seite nennt das Abschalten der Isolierung als Mittel für die Fehlersuche: „To support troubleshooting“) |
| Citrix | Best practices, security considerations, and default operations | https://docs.citrix.com/us/en/citrix-virtual-apps-desktops/2203-ltsr/printing/printing-best-practices.html | 2026-11-12 | 2026-11-14 | `print.kernelModeV2` (`vendor`: „Try to avoid using version 2 kernel-mode drivers“); als Beleg der Faustregel `print.driverCount` („Minimize the number of printer drivers installed on Multi-session OS machines“, „Use the Universal printer driver or Windows-native drivers“; die Seite nennt keine Zahl). Die Seite schränkt selbst ein: „Some of these best practices might not apply to your Site“. Ihr Satz zur automatischen Installation mitgelieferter Treiber ist nicht übernommen (ohne Wirkung ab VDA 7.16 unter Windows Server 2012 und neuer) |
| AKI | Release Notes PrinTaurus 6.4 | https://www.aki-gmbh.com/download/47826/ | 2025-02-16 | 2026-11-14 | `print.mappingClientSupported` (Kapitel 1: „Zum 31. Dezember 2025 kündigen wir alle PrinTaurus Versionen < 6.2. ab.“; als Hinweise im Text: „Alle Software-Komponenten sollten zur gleichen Release-Version gehören!“ steht unter den Hinweisen zum Update auf 6.4; Kapitel 2: lokale IPP-Druckerwarteschlangen sind „in dieser Version nur für Fat Clients verfügbar“ und in Citrix- oder Terminalserver-Umgebungen nicht unterstützt) |
| Microsoft | Microsoft Defender Antivirus compatibility with other security products | https://learn.microsoft.com/en-us/defender-endpoint/microsoft-defender-antivirus-compatibility | 2026-08-21 | 2026-11-14 | `security.twoScanners` (auf Windows Server wechselt Defender Antivirus neben einem anderen Virenschutz nicht von selbst in die passive Betriebsart; „set Microsoft Defender Antivirus to passive mode to prevent problems caused by having multiple antivirus products installed on a server“), `security.passiveWithoutMde` („In general, Microsoft Defender Antivirus can be set to passive mode only on endpoints that are onboarded to Defender for Endpoint“) |
| Citrix | Endpoint Security, Antivirus, and Antimalware Best Practices (CTX696648) | https://support.citrix.com/external/article/CTX696648/endpoint-security-antivirus-and-antimalw.html | ohne Datum; ein Abschnitt „Updated January 2024“ | 2026-11-14 | `security.citrixExclusions` (Abschnitt „Virtual Delivery Agents“: die Prozesse UserProfileManager.exe, BrokerAgent.exe und CtxSvcHost.exe stehen dort neben weiteren; „Review these recommendations with your vendor and security team“, „confirm they exist before you create an exclusion policy“). Im Katalog trägt die Quelle das Datum des Abrufs |
| Microsoft | Detect, enable, and disable SMBv1, SMBv2, and SMBv3 in Windows | https://learn.microsoft.com/en-us/windows-server/storage/file-server/troubleshoot/detect-enable-and-disable-smbv1-v2-v3 | 2025-03-11 | 2026-11-14 | `network.smb1` („SMBv1 has significant security vulnerabilities, and we strongly encourage you not to use it“) |
| Microsoft | Recommendations for Domain Name System (DNS) client settings | https://learn.microsoft.com/en-us/troubleshoot/windows-server/networking/best-practices-for-dns-client-settings | 2026-02-12 | 2026-11-14 | `network.dnsCount` (`vendor`, Abschnitt zu Mitgliedsservern: „Configure the primary and secondary DNS client settings to point to local primary and secondary DNS servers“); als Beleg der Faustregel `network.dnsPublic` („Don't configure the client DNS settings to point to your ISP's DNS servers“; dass eine öffentliche Adresse ein solcher Server ist, ist die Annahme des Katalogs). Der Plan führt die Seite unter ihrem früheren Titel „Best practices for DNS client settings in Windows Server“ |
| Microsoft | Set-MpPreference | https://learn.microsoft.com/en-us/powershell/module/defender/set-mppreference?view=windowsserver2022-ps | 2024-03-27 | 2026-11-14 | `maintenance.defenderRandomize` („Randomized start times can distribute the impact of scanning“; der zufällige Startzeitpunkt ist die Voreinstellung) |
| Microsoft | Configure Microsoft Defender Antivirus on a remote desktop or virtual desktop infrastructure environment | https://learn.microsoft.com/en-us/defender-endpoint/deployment-vdi-microsoft-defender-antivirus | 2026-08-20 | 2026-11-14 | als Beleg der Faustregeln `maintenance.defenderFullScan` (die Seite nennt einen täglichen Schnellscan und „Run a weekly scheduled scan (quick or full)“ mit der Art „Not configured“; einen Satz gegen den vollständigen Scan enthält sie nicht, deshalb ist die Prüfung keine Empfehlung des Herstellers) und `security.signatureAge` (Signaturen erscheinen „typically published once every three to four hours“; eine Schwelle nennt Microsoft nicht) |
| Microsoft | Windows Time Service Tools and Settings | https://learn.microsoft.com/en-us/windows-server/networking/windows-time-service/windows-time-service-tools-and-settings | 2025-09-18 | 2026-11-14 | als Beleg der Faustregel `network.timeSource` („By default, a computer that's joined to a domain synchronizes time through a domain hierarchy“; die Seite beschreibt die Voreinstellung und spricht keine Empfehlung aus) |
| Microsoft | Eventlog Key | https://learn.microsoft.com/en-us/windows/win32/eventlog/eventlog-key | 2025-08-14 | 2026-11-14 | als Beleg der Faustregel `events.retainFull` („When the log file reaches its maximum size, you must clear the log manually; otherwise, new events are discarded“) |
| Microsoft | Step 4: Configure Group Policy Settings for Automatic Updates | https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/deploy/4-configure-group-policy-settings-for-automatic-updates | 2025-06-05 | 2026-11-14 | als Beleg der Faustregel `maintenance.updateInstallInWorkHours` (Option 4: „If no schedule is specified, the default schedule for all installations is every day at 3:00 AM“; „Starting with Windows 8, you can set updates to install during automatic maintenance“; ohne Richtlinie lädt und installiert Windows nach dieser Seite automatisch, der Zeitpunkt ist dann aus den gelesenen Werten nicht bekannt) |

Weitere Seiten der Hersteller, auf die sich einzelne Sätze der Texte stützen (Abruf 2026-11-13 oder 2026-11-14):

- Citrix, „What's new“ (Workspace Environment Management service),
  https://docs.citrix.com/us/en/workspace-environment-management/service/whats-new.html: Der Agent des WEM-Dienstes
  findet den beständigen Ort für seinen Cache ab Version 2408.1.0.1 selbst (`vda.wemCache`). Die Seiten für eigene
  WEM-Server enthalten diese Aussage nicht.
- Citrix, „Session limits policy settings“,
  https://docs.citrix.com/us/en/citrix-virtual-apps-desktops/2203-ltsr/policies/reference/ica-policy-settings/session-limits-policy-settings.html:
  Citrix empfiehlt, die Zeitlimits nur auf einem der beiden Wege zu setzen (`sessions.disconnectLimit`,
  `sessions.idleLimit`, im Vorschlag zum Vorgehen). Die Sitzungs-Timer für Multi-Session-Server gibt es nach dieser
  Seite erst ab VDA 2203 LTSR CU2 („Starting with the 2203 LTSR CU2 release“); der Text der zwei Prüfungen sagt das.
- Citrix, „Set up profile containers“,
  https://docs.citrix.com/us/en/profile-management/current-release/configure/citrix-profile-management-profile-container.html:
  Mit einem Container für das ganze Profil gilt „Delete locally cached profiles on logoff“ nicht mehr
  (`sessions.unloadedProfiles`, im Vorschlag zum Vorgehen; die Empfehlung der Einstellung für Terminalserver steht auf
  der Seite „Profile Management policy descriptions and defaults“).
- Citrix, „Agent (install and configure)“ (Tabelle oben), Abschnitt „Recommendations“: Den Dienst „Citrix WEM Agent Host
  Service“ nicht per Skript beenden oder neu starten; Citrix sagt das nur für diesen Dienst (`vda.wemServices`, im
  Vorschlag zum Vorgehen). Abschnitt „System settings“: Antworten die Domänencontroller langsam, kann es länger dauern,
  bis der Anmeldebildschirm erscheint; die Seite nennt das als möglichen Preis der Wartezeit, nicht als Folge eines zu
  kleinen Werts (`vda.wemGpTimeout`). Dieselbe Seite beschreibt, dass der Agent auf bereitgestellten Maschinen die
  Cache-Dateien aus dem Abbild verwirft (`vda.wemCache`).
- Citrix, „WEM health check tool“ (Tabelle oben): Die Seite sagt nur, dass der Agent die drei Dienste braucht, um wie
  erwartet zu arbeiten. Was das für die Benutzer heißt, ist im Text der Prüfung als Erläuterung des Katalogs
  gekennzeichnet (`vda.wemServices`).
- Microsoft, „Performance Tuning Remote Desktop Session Hosts“ (Tabelle oben): Eine zu kleine Auslagerungsdatei lässt
  Speicheranforderungen von Programmen und Systemteilen scheitern (`size.commitHeadroom`).
- VMware, „VMware Tools Device Drivers“,
  https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/tools/13-0-0/vmware-tools-administration/introduction-to-vmware-tools/vmware-tools-device-drivers.html
  (Stand der Seite 2026-05-08): Der Treiber zur Speichersteuerung ist für das Ballooning nötig und unter vSphere
  empfohlen (`size.balloonDriver`); die Treiber für VMXNET3 verbessern die Netzleistung (`size.netAdapterType`).
- VMware, „Add a Paravirtualized SCSI Adapter“,
  https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/vsphere-virtual-machine-administration/configuring-virtual-machine-hardware/scsi-controller-configuration/add-a-paravirtualized-scsi-adapter-in-the-nextgen-client.html:
  Der paravirtuelle SCSI-Adapter passt am besten zu E/A-starken Anwendungen, besonders in SAN-Umgebungen
  (`size.storageController`).
- VMware, „Configuring disks to use VMware Paravirtual SCSI (PVSCSI) controllers“,
  https://knowledge.broadcom.com/external/article/313507: Ein Wechsel des Adapters am Startlaufwerk ohne den Treiber
  lässt Windows nicht mehr starten (`size.storageController`, im Vorschlag zum Vorgehen). Derselbe Artikel nennt den
  Adapter für direkt angeschlossenen Speicher nicht geeignet („not suitable for DAS environments“); der Text der Prüfung
  nennt diesen Vorbehalt.
- Citrix, „VDA registration“ (Tabelle oben): Stehen ListOfDDCs und FarmGUID beide da, „ListOfDDCs is used“; deshalb
  wertet `vda.controllerCount` die Liste auch neben der Registrierung über die Organisationseinheit. Nach der ersten
  Registrierung nimmt der VDA die Liste aus dem Cache der automatischen Aktualisierung („Auto-update is enabled by
  default“), und für MCS gibt die Bereitstellung die Liste mit. Die Liste kann Controller-Gruppen enthalten, die das
  Zustandsbild als einen Eintrag zählt (`vda.controllerCount`, `vda.controllerNotFqdn`). Den Wert ListOfSIDs von Hand zu
  setzen und dann die automatische Aktualisierung abzuschalten, nennt die Seite für besonders gesicherte Umgebungen
  (`vda.listOfSids`).
- Citrix, „VDA Registration Failure with Event ID 1“ (CTX133769),
  https://support.citrix.com/external/article/CTX133769/vda-registration-failure-with-event-id-1.html: Der Dienst
  „Citrix Desktop Service“ registriert den VDA beim Delivery Controller. Dass ein Server ohne ihn keine neuen Sitzungen
  bekommt, steht dort nicht; der Text von `vda.services` nennt es als Folgerung des Katalogs.
- Citrix, „Set up profile containers“ (oben): Die Citrix Profilverwaltung lässt in der Voreinstellung mehrere Sitzungen
  zugleich auf einen Profilcontainer zugreifen, eine davon schreibend („supports concurrent access to the profile
  container by default“); mehrere Container eines Benutzers sind deshalb mit mehreren Sitzungen normal
  (`profile.containersPerUser`).
- Microsoft, „How to determine the appropriate page file size for 64-bit versions of Windows“ (Tabelle oben): Die Seite
  empfiehlt eine eigene Datei für das Speicherabbild (dedicated dump file), wenn ein Speicherabbild gewünscht ist, aber
  keine Auslagerungsdatei (`size.pagefilePresent`; das Zustandsbild liest diese Datei nicht). Dass eine vom System
  verwaltete Auslagerungsdatei wächst, wenn der zugesagte Speicher 90 % der Zusagegrenze überschreitet, nennt die Seite
  als Beispiel, bis zum Dreifachen des Arbeitsspeichers oder 4 GB und unter der Annahme, dass das Laufwerk Platz hat;
  die Schwellen von `size.commitHeadroom` sind die des Katalogs. Die Grenze „Größe des Laufwerks geteilt durch 8“ steht
  in der Tabelle für Windows 10 und Windows 11 und hat eine Ausnahme für das Speicherabbild (`operation.diskFree`; im
  Text der Prüfung steht nur, dass Microsoft genug freien Platz voraussetzt). Dass eine leere Liste der
  Auslagerungsdateien „keine Auslagerungsdatei“ heißt, ist die Lesart des Katalogs.
- Microsoft, „Overview about power and performance tuning for the Windows Server“ (oben, „Ausnahmen“): „If the operating
  system does not have control over the power management, changing the power plans in Windows will not affect system
  power and performance“ (`operation.powerPlan`, im Text und im Vorschlag zum Vorgehen).
- Microsoft, „Win32_QuickFixEngineering class“,
  https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-quickfixengineering: Die Klasse führt nur Updates,
  die über die Komponentenwartung (Component Based Servicing) installiert wurden (`operation.updateAge`).
- Microsoft, „Win32_UserProfile class“,
  https://learn.microsoft.com/en-us/previous-versions/windows/desktop/legacy/ee886409(v=vs.85): Ein temporäres Profil
  „will be deleted after the user logs off“; `sessions.tempProfiles` zählt deshalb die temporären Profile der laufenden
  Sitzungen.
- Microsoft, „Win32_TSSessionSetting class“,
  https://learn.microsoft.com/en-us/windows/win32/termserv/win32-tssessionsetting: Die Zeitlimits des Listeners gelten
  für die Benutzer nur, wenn der Listener sie vorgibt; sonst gelten die Einstellungen des Benutzerkontos
  (`sessions.disconnectLimit`, `sessions.idleLimit`). Das Zustandsbild liest diese Angabe des Listeners noch nicht.
- Microsoft, „Automatic maintenance“, https://learn.microsoft.com/en-us/windows/win32/taskschd/task-maintenence (Stand
  der Seite 2020-09-19): Wartungsaufgaben laufen, „when the machine is idle and on AC power“
  (`maintenance.tasksInWorkHours`).
- Microsoft, „Common mistakes to avoid when defining exclusions“,
  https://learn.microsoft.com/en-us/defender-endpoint/common-exclusion-mistakes-microsoft-defender-antivirus (Stand der
  Seite 2026-07-17): Unter den Ordnern, die nicht ausgenommen werden sollen, stehen „Program folders for installed apps“
  (`security.wemExclusions`).
- AKI, „Release Notes 6.2 deutsch“, https://www.aki-gmbh.com/download/45927/, Kapitel 4: Das Installationspaket heißt
  „PrinTaurus SmartSpread Client x64.msi“ und trägt in Release 6.2 die Version 6.2.1; daraus entsteht der Wert
  `print.mappingClientVersion`.

### Hinweise zu gelesenen Werten

Was die Quellenprüfung der Recherchen zu einzelnen Werten festhält, auf die sich Prüfungen stützen:

- `size.memTotalMB` liest `Win32_ComputerSystem.TotalPhysicalMemory`, also den Arbeitsspeicher, den Windows nutzen kann.
  Microsoft nennt für die Größe der eingebauten Module `Win32_PhysicalMemory.Capacity` genauer. Der Katalog bleibt beim
  nutzbaren Arbeitsspeicher, weil die Prüfungen Sitzungen und zugesagten Speicher damit vergleichen
  (`size.workerMemory`, `size.memoryPerSession`, `size.commitAboveRam`).
- `maintenance.tasks`, `maintenance.taskCount`: Die Aufzählung der Aufgaben stützt sich außer auf „TaskService.Connect“
  und „ITaskFolder::GetTasks“ auf „TASK_ENUM_FLAGS enumeration“
  (https://learn.microsoft.com/en-us/windows/win32/api/taskschd/ne-taskschd-task_enum_flags: der Wert 1 schließt
  verborgene Aufgaben ein), „RegisteredTask object“
  (https://learn.microsoft.com/en-us/windows/win32/taskschd/registeredtask: Path, Enabled, State, LastRunTime,
  NextRunTime) und „TaskFolder.GetFolders method“
  (https://learn.microsoft.com/en-us/windows/win32/taskschd/taskfolder-getfolders).
- `sessions.userCount`: Die Aufzählung der Sitzungen braucht je Sitzung das Recht, ihre Angaben abzufragen; ohne dieses
  Recht zählt das Zustandsbild zu wenig. `size.memoryPerSession` und `size.cpuPerSession` teilen durch alle
  Benutzersitzungen, auch die getrennten.
- `size.vmware` schließt aus dem Modell, das Windows meldet (beginnt mit „VMware“); `size.otherNetAdapters` und
  `size.lsiControllers` aus Namen der Adapter und Treiber. Diese Namen stammen von der Installation, nicht aus einem
  Dokument von Microsoft, und sind beim ersten Lauf zu bestätigen. Die Klasse `Win32_NetworkAdapter` nennt Microsoft
  veraltet.
- `operation.pendingRename` zählt Einträge des Werts `PendingFileRenameOperations`; die Zählung von Löschungen wird in
  einer späteren Fassung berichtigt. `operation.lastUpdate` liest heute nur ein Datumsformat; Windows kann das
  Installationsdatum nach Microsoft in weiteren Formen liefern, dann zeigt das Zustandsbild einen Strich.
- `maintenance.scanInWorkHours` vergleicht die eingestellte Zeit des geplanten Scans mit der Arbeitszeit. Ob Defender zu
  dieser Zeit einen Versatz hinzurechnet, wird noch an der Dokumentation von Microsoft geprüft; der Text von
  `maintenance.defenderScanInWorkHours` spricht deshalb von der eingestellten Zeit und nennt keinen Beginn.
- `maintenance.updateInWorkHours` ist ohne Richtlinie „nein“. Nach Microsoft lädt und installiert Windows ohne
  Richtlinie automatisch; der Text von `maintenance.updateInstallInWorkHours` sagt deshalb, dass der Zeitpunkt der
  Installation ohne Richtlinie nicht bekannt ist. Die Regel des Werts wird in einer späteren Fassung berichtigt.
- `print.mappingClientVersion`: Der Hersteller dokumentiert den Namen des Installationspakets, nicht den Eintrag unter
  den installierten Programmen; ob der Eintrag so heißt, zeigt der erste Lauf.

### Faustregeln

Eine Faustregel ist eine Prüfung, für die es weder eine Empfehlung des Herstellers noch eine aus der Praxis gibt. Ihre
Schwellen sind Vorschläge des Katalogs, und jede Faustregel sagt in ihrem Text, dass die Prüfung oder ihre Schwelle vom
Katalog stammt. Wo ein Dokument des Herstellers den Zusammenhang beschreibt, nennt die Prüfung dieses Dokument als Beleg
(Tabelle „Herstellerquellen“). Die übrigen tragen die Quelle „WorkerPerf: Erfahrungswert des Katalogs ohne
Herstellerdokument“ (Stand 2026-11-13): `sessions.disconnectedOld`, `sessions.unloadedProfiles`,
`sessions.tempProfiles`, `vda.services`, `profile.containersPerUser`, `profile.serviceStopped`, `print.spoolerStopped`,
`print.queueCount`, `network.smbOldDialect`, `events.crashes`, `events.storage`, `events.fileserver`, `events.coverage`,
`events.logDisabled`, `maintenance.tasksInWorkHours`, `maintenance.defenderScanInWorkHours`.

`maintenance.defenderFullScan` führt der Plan als Empfehlung des Herstellers. Die Seite von Microsoft, die er nennt,
enthält am 14.11.2026 keinen Satz gegen einen vollständigen Scan; die Prüfung ist deshalb eine Faustregel.

### Schwellen

Die Schwellen der zehn Bereiche mit ihrer Herkunft. Eine Schwelle lässt sich im Katalog ändern; der Bericht nennt im
Kopf jede Abweichung vom ausgelieferten Wert.

| Schwelle | Wert | Verwendet von | Herkunft der Zahl |
|---|---|---|---|
| `commitPeakPct` | 90 % | `size.commitHeadroom` | Vorschlag des Katalogs |
| `commitNowPct` | 98 % | `size.commitHeadroom` | Vorschlag des Katalogs |
| `memPerSessionMB` | 1024 MB | `size.memoryPerSession` | Vorschlag des Katalogs; Microsoft nennt für Edge 1 GB je Benutzer |
| `sessionsPerCpu` | 8 Sitzungen | `size.cpuPerSession` | Vorschlag des Katalogs |
| `workerCpuMin` | 8 Prozessoren | `size.workerCpu` | Carl Stalhood (Praxisquelle) |
| `workerCpuMax` | 8 Prozessoren | `size.workerCpuMax` | Carl Stalhood, GO-EUC (Praxisquellen) |
| `workerMemMinMB` | 24000 MB | `size.workerMemory` | Carl Stalhood (Praxisquelle) nennt 24 GB (24576 MB). Der Katalog setzt die Schwelle knapp darunter: Gelesen wird der Arbeitsspeicher, den Windows meldet, und der kann bei einer virtuellen Maschine etwas kleiner sein, als ihr zugeteilt ist. Ein Server mit genau 24 GB wird so nicht gemeldet. Der Abstand ist eine Festlegung des Katalogs. |
| `uptimeDays` | 30 Tage | `operation.uptime` | Vorschlag des Katalogs |
| `updateAgeDays` | 60 Tage | `operation.updateAge` | Carl Stalhood (Praxisquelle) |
| `diskFreeGB` | 10 GB | `operation.diskFree` | Vorschlag des Katalogs |
| `diskFreeHardGB` | 2 GB | `operation.diskFree` | Vorschlag des Katalogs |
| `disconnectedHours` | 24 Stunden | `sessions.disconnectedOld` | Vorschlag des Katalogs |
| `unloadedProfiles` | 20 Profile | `sessions.unloadedProfiles` | Vorschlag des Katalogs |
| `containerUsedPct` | 90 % | `profile.containerFull` | Citrix: Vorgabe für die automatische Vergrößerung |
| `containerUsedHardPct` | 95 % | `profile.containerFull` | Vorschlag des Katalogs |
| `containersPerUser` | 3 Container | `profile.containersPerUser` | Vorschlag des Katalogs |
| `printDrivers` | 20 Treiber | `print.driverCount` | Vorschlag des Katalogs; Citrix nennt keine Zahl |
| `queuesPerSession` | 10 Warteschlangen | `print.queueCount` | Vorschlag des Katalogs |
| `signatureAgeDays` | 2 Tage | `security.signatureAge` | Vorschlag des Katalogs |
| `eventDays` | 3 Tage | `events.crashes`, `events.fileserver` | Vorschlag des Katalogs |
| `workStartHour`, `workEndHour` | 7 und 18 Uhr | Arbeitszeit (Bereich Wartung in der Arbeitszeit) | Vorschlag des Katalogs |

Feste Zahlen in Regeln, die aus dem Dokument des Herstellers stammen und deshalb keine Schwellen sind: 12 (Hauptversion
der VMware Tools), 30 (Wartezeit der Gruppenrichtlinie auf das Netz in Sekunden), 602 (Version 6.2 des PrinTaurus
SmartSpread Client: Hauptversion mal 100 plus Nebenversion).

### Auf dem Zielsystem zu bestätigen

Der Katalog nennt Stellen und Bezeichnungen der Oberflächen von Windows, Citrix und VMware. Wo die Recherche den Namen
einer Einstellung nennt, steht er so da wie in der Quelle (englisch). Alle anderen Stellen sind allgemein umschrieben,
weil ihre deutschen Anzeigenamen hier nicht geprüft werden konnten. Die folgenden Angaben sind beim Test auf dem
Zielsystem zu bestätigen; stimmt eine nicht, wird der Text im Katalog angepasst.

- **Energiesparplan** (`operation.powerPlan`): die Namen der Pläne „Höchstleistung“, „Ausbalanciert“ und
  „Energiesparmodus“ und die Stelle „Energieoptionen“. Das Zustandsbild liest den Plan als Kennwort (highPerformance,
  balanced, powerSaver, other); die Bezeichnung des Werts erklärt die Kennwörter.
- **Zustand und Starttyp von Diensten**: Das Zustandsbild zeigt den Zustand eines Dienstes so, wie Windows ihn über die
  Schnittstelle liefert (Running, Stopped); die Bezeichnungen der Werte erklären Running als „läuft“ und Stopped als
  „beendet“. Zu bestätigen ist, welche Wörter die Dienste-Konsole eines deutschen Windows dafür zeigt (die Liste weiter
  oben nennt „Wird ausgeführt“), und der Starttyp „Automatisch“. Den Starttyp liefert Windows als Kennwort (Auto,
  Manual, Disabled, bei Treibern auch Boot und System); die Bezeichnungen der Werte erklären sie als „automatisch“,
  „manuell“ und „deaktiviert“.
- **Dienste des WEM-Agenten** (`vda.wemServices`): Der Katalog nennt den Dienst von Windows mit seinem Dienstnamen SENS
  und in Klammern englisch wie die Seite von Citrix („System Event Notification Service“). Zu bestätigen ist, unter
  welchem Anzeigenamen ein deutsches Windows diesen Dienst zeigt.
- **Zeitlimits der Sitzungen** (`sessions.disconnectLimit`, `sessions.idleLimit`): Der Katalog nennt die zwei
  Einstellungen der Gruppenrichtlinie englisch, wie Carl Stalhood sie nennt: „Set time limit for disconnected sessions“
  und „Set a time limit for active but idle Terminal Services sessions“. Zu bestätigen sind ihre deutschen Anzeigenamen
  und ihr Ort unter Computerkonfiguration > Administrative Vorlagen, ebenso die Namen der Sitzungs-Timer in den
  Citrix-Richtlinien (im Katalog: „Timer für getrennte Sitzungen“, „Timer für Sitzungen im Leerlauf“).
- **Citrix Studio** (`operation.uptime`, `vda.services`, `profile.serviceStopped`): die Stelle und die Bezeichnung des
  Zeitplans für Neustarts einer Bereitstellungsgruppe und der Wartungsmodus eines Servers; die Wörter „Maschinenkatalog“
  und „Bereitstellungsgruppe“.
- **Citrix Profilverwaltung** (`sessions.unloadedProfiles`): Der Katalog nennt die Einstellung englisch wie die Quelle
  („Delete locally cached profiles on logoff“). Zu bestätigen ist ihr deutscher Anzeigename.
- **Task-Manager** (`size.commitHeadroom`, `sessions.disconnectedOld`): die Registerkarten „Benutzer“ und „Details“ und
  der Status „Getrennt“. Den zugesagten Speicher zeigt der Task-Manager unter einer eigenen Bezeichnung (vermutet wird
  „Zugesichert“); der Katalog nennt sie nicht.
- **Auslagerungsdatei** (`size.pagefilePresent`): die Stelle „Systemeigenschaften, Einstellungen zum virtuellen
  Arbeitsspeicher“.
- **VMware Tools** (`size.balloonDriver`): die Bezeichnung der Komponente zur Speichersteuerung im Installationsprogramm
  (im Katalog: „Memory Control“).
- **Arbeitsspeicher eines Servers mit 24 GB** (`size.workerMemory`): wie viel Arbeitsspeicher Windows für eine virtuelle
  Maschine mit genau 24 GB meldet. Der Katalog nimmt an, dass der Wert knapp unter 24576 MB liegen kann, und setzt die
  Schwelle deshalb auf 24000 MB.
- **Outlook** (Bereich Anwendungen, „nicht abgedeckt“): Der Katalog nennt den Modus englisch wie die Quelle („Cached
  Exchange Mode“).
- **Drucken** (`print.driversInSpooler`, `print.isolationOff`, `print.spoolerStopped`): die Stelle „Druckverwaltung“,
  die Bezeichnung der Isolierung je Treiber und der Anzeigename des Dienstes „Druckwarteschlange“. Die Richtlinie nennt
  der Katalog deutsch, wie Thomas Kötzing sie nennt: „Druckertreiber in isolierten Prozessen ausführen“. Zu bestätigen
  ist auch, wie die Liste der Druckertreiber im Bericht Isolierung und Typ bezeichnet.
- **PrinTaurus** (`print.mappingClientSupported`): der Name des Eintrags des Clients unter den installierten Programmen
  und die Stelle „Landschaftsinformationen“ der PrinTaurus GUI (so nennt sie der Hersteller).
- **Defender Antivirus** (Bereiche Sicherheitsprodukte und Wartung in der Arbeitszeit): die Namen der Einstellungen in
  der Richtlinie (Art und Zeit des geplanten Scans, zufälliger Startzeitpunkt, Netzwerkschutz, Ausschlüsse); der Katalog
  umschreibt sie. Die Betriebsart liefert Defender als Kennwort (Normal, Passive).
- **Ereignisprotokolle** (`events.coverage`, `events.retainFull`, `events.logDisabled`, `print.operationalLogOff`): die
  Stelle „Eigenschaften des Protokolls“ in der Ereignisanzeige und die Bezeichnungen für Größe und Überschreiben; die
  Felder der Rohwerte tragen die englischen Namen der Schnittstelle (Mode, Full, Enabled, Oldest).
- **Netz** (`network.rss`, `network.timeSource`, `network.dnsCount`): die Bezeichnung der Eigenschaft für Receive Side
  Scaling in den erweiterten Eigenschaften des Adapters und die Namen der Einstellungen des Windows-Zeitdienstes in der
  Gruppenrichtlinie.
