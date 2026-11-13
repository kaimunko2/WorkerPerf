# Quellen der Empfehlungen im Katalog

Der Katalog `src/guidance.de.json` enthält Empfehlungen zum Drucken auf Citrix- und Terminalservern: die Elemente der
Situation `print` und in anderen Situationen die Elemente mit einer Bedingung `pattern.printdriver` oder `driver.*`.
Jedes dieser Elemente nennt im Feld `source` den Hersteller und den Titel des Dokuments, aus dem es stammt; der
Bericht zeigt die Quelle beim Element. Diese Datei weist je Hersteller nach, welches Dokument welches Element stützt,
und nennt die Empfehlungen, die gefunden, aber nicht aufgenommen wurden, mit dem Grund.

Seit dem 13.11.2026 tragen auch Elemente anderer Situationen eine Quelle: die Schritte zu den Standardanwendungen aus
`src/apps.json` (Bedingung `app.<Anwendung>`: Microsoft Edge, Microsoft Edge WebView2, Microsoft Office, Microsoft
Teams, PrinTaurus SmartSpread Client, Microsoft Outlook), die Schritte zu Citrix Workspace Environment Management und die Empfehlungen
aus zwei Quellen der Praxis (Carl Stalhood, BIS-F). Ein Element aus einer Quelle der Praxis nennt in `source` die
Quelle mit dem Zusatz „Empfehlung aus der Praxis“ und ist nie als Empfehlung eines Herstellers formuliert. Die
Abschnitte dazu stehen nach den Druckerherstellern; der Abschnitt „Ausnahmen: Praxisquelle vor Hersteller“ nennt, wo
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
Der Abschnitt „Zielumgebung“ nennt ein Element nicht mit seiner Stelle, sondern mit der Liste, seinen ersten Worten in
Anführungszeichen und der Situation (Abhilfe „…“ der Situation `print`): Diese Angabe stimmt auch dann noch, wenn
Elemente hinzukommen. In den Tabellen und in solchen Anfangsworten steht für einen Platzhalter des Katalogs sein Name
in einfachen Winkeln: ‹Anwendung› für `{app}`, ‹Benutzer› für `{user}`.

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
steht und dass hier keine Stelle steht, die der Katalog nicht hat. In den Abschnitten ab „AKI“ bis „BIS-F“ steht bei
jeder Stelle der Anfang des Elementtexts: bis zum ersten Doppelpunkt, Semikolon oder zur ersten öffnenden Klammer
nach dem zwanzigsten Zeichen, höchstens 110 Zeichen (ein längerer Anfang endet nach 107 Zeichen mit „…“); steht ein
Schritt für jedes Office-Programm ein zweites Mal für Outlook im Katalog, folgt „(für Outlook)“. Der Test vergleicht
auch das mit dem Katalog.

## Microsoft

Microsoft dokumentiert nichts Eigenes zum Citrix-Universaltreiber, zum Citrix Universal Print Server oder zur Treiberzuordnung von Citrix und trifft keine Aussage, ob Treiber der Bauart Typ 3 oder Typ 4 auf Terminalservern stabiler sind. Kein Element hängt deshalb an der Bedingung `driver.vendor.Microsoft`.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| Policy CSP - ADMX_Printing | <https://learn.microsoft.com/windows/client-management/mdm/policy-csp-admx-printing> | 2026-11-13 | `crash.checks[3]` Richtlinie zur Isolierung der Treiber von Anwendungen<br>`print.checks[9]` Wirkung der Isolierung bei isoliertem Treiber<br>`print.checks[10]` Richtlinie zur Treiberisolierung nicht abgeschaltet<br>`print.remedies[2]` Isolierung per Richtlinie für alle Treiber erzwingen | Die Seite nennt als Betriebssysteme Windows 10 und 11, nicht Windows Server 2022; jedes der vier Elemente sagt das (die Abhilfe in ihrer Voraussetzung). Die Richtlinien zur Treiberisolierung gelten laut Seite nur für Treiber, die die Druckwarteschlange lädt; „Isolate print drivers from applications“ wirkt nur bei Anwendungen, die die Isolierung unterstützen, und erst nach deren Neustart. Datenwerte der Registrierung nennt die Seite nicht. Die Prozessnamen PrintIsolationHost.exe und spoolsv.exe in `print.checks[9]` stammen aus der Auswertung (Liste der Druckprozesse), nicht von der Seite; die Voraussetzung „auf einem Testserver geprüft“ in `print.remedies[2]` stammt nicht von Microsoft. |
| Printer driver isolation | <https://learn.microsoft.com/windows-hardware/drivers/print/printer-driver-isolation> | 2026-11-13 | `print.checks[8]` Isolierung des beteiligten Treibers ansehen<br>`print.remedies[0]` fehlerhaften Treiber isoliert betreiben | Dokumentation für Treiberentwickler. Sie sagt, dass sich der Modus in der Druckverwaltung je Treiber einstellen lässt, nennt die Stelle dort aber nicht genauer (siehe „Auf dem Zielsystem zu bestätigen“) und spricht nicht von Typ 3 oder Typ 4. Die Voraussetzung von `print.remedies[0]` folgt dem Satz der Seite: Der Treiber ist in einem eigenen Prozess lauffähig, verursacht häufig Fehler oder verliert Arbeitsspeicher und stört damit andere Treiber im selben Prozess. „Zuerst auf einem Testserver geprüft“ stammt nicht von Microsoft. |
| Troubleshooting scenarios for printing | <https://learn.microsoft.com/troubleshoot/windows-server/printing/troubleshoot-printing-scenarios> | 2026-11-13 | `print.checks[2]` Treiber oder Warteschlange als Auslöser feststellen<br>`print.checks[15]` Spool-Ordner und Dienstabhängigkeit nach Absturz<br>`print.checks[19]` hängende Aufträge auf Treiber oder Warteschlange eingrenzen<br>`print.remedies[12]` Treiber aktualisieren oder generischen Treiber verwenden | Microsoft beschreibt die Schritte zu fehlgeschlagenen Aufträgen „auf dem Clientcomputer“. Zur Abhängigkeit des Dienstes nennt die Seite als Standard nur RpcSs. Ob ein Windows Server 2022 ohne Druckproblem weitere Einträge hat, ist hier nicht geprüft; `print.checks[15]` verlangt deshalb den Vergleich mit einem solchen Server (siehe „Auf dem Zielsystem zu bestätigen“). |
| Troubleshoot printing issues caused by Print Spooler service not running | <https://learn.microsoft.com/troubleshoot/windows-server/printing/print-spooler-service-not-running> | 2026-11-13 | `print.checks[11]` Treiber und Druckkomponenten aktuell<br>`print.remedies[11]` Spool-Ordner vom Scan ausnehmen | Die Seite sagt „Create exclusions for the spool folder“; Dateiendungen nennt sie dabei nicht. Als Anlass nennt sie Schutzsoftware, die Dateien blockiert, die der Dienst braucht; `print.remedies[11]` verlangt deshalb eine Meldung der Schutzsoftware. Die Zustimmung der Verantwortlichen für die Sicherheit stammt nicht von Microsoft. |

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
| Best practices | <https://docs.citrix.com/us/en/citrix-virtual-apps-desktops/current-release/printing/troubleshooting/best-practices.html> | 2026-11-13 | `crash.remedies[3]` Treiber sauber erneuern statt überinstallieren<br>`print.remedies[3]` Universaltreiber als Regel, ungenutzte Treiber entfernen<br>`print.remedies[5]` Treiber sauber erneuern statt überinstallieren<br>`print.remedies[13]` alte und hängende Aufträge regelmäßig löschen | Aktuelle Fassung der Produktdokumentation. Den Neustart nennt Citrix; das Wartungsfenster dafür in der Voraussetzung von `crash.remedies[3]` und `print.remedies[5]` stammt nicht von Citrix, ebenso wenig das Wartungsfenster für das Entfernen nicht mehr benötigter Treiber in `print.remedies[3]`. |
| Troubleshooting | <https://docs.citrix.com/us/en/citrix-virtual-apps-desktops/current-release/printing/troubleshooting.html> | 2026-11-13 | `print.checks[0]` Dienst läuft wieder, sonst starten<br>`print.checks[1]` fehlerhaftes Modul dem Treiber zuordnen<br>`print.checks[24]` Citrix Print Manager Service läuft<br>`print.remedies[1]` Treiber entfernen, mit Universaltreiber oder Microsoft-Treiber testen<br>`print.remedies[10]` Spool-Ordner von Hand leeren | Die Zuordnung des fehlerhaften Moduls zu einem Treiber stammt aus der Messung; die Seite sagt nur, dass das Modul festzustellen ist. Den Neustart des Dienstes nennt die Seite als Schritt vor dem Leeren von Hand („If restarting fails …“); wo der Zustand des Dienstes steht, ist ein eigener Hinweis. Das Leeren von Hand nennt sie nur für Abstürze der Druckwarteschlange. Der Hinweis, dass die Aufträge aller Benutzer des Servers verloren gehen, stammt nicht von Citrix, ebenso wenig die Voraussetzungen „Benutzer informiert“ (`print.remedies[10]`) und „Wartungsfenster“ (`print.remedies[1]`). |
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
| HP Print and Scan Devices Supported in Citrix Virtual Apps and Virtual Desktops Environments | <https://kaas.hpcloud.hp.com/pdf-public/pdf_6290906_en-US-1.pdf> | 2026-11-13 | `print.remedies[7]` hostbasierte HP-Treiber nicht auf dem Server<br>`print.remedies[15]` HP Universal Print Driver im Traditional Mode | Technical white paper, Rev. 39, Juni 2023; enthält viel Altbestand (XenApp, 32-Bit-Pfade). Dass die Clientdrucker über den Citrix-Universaltreiber bedient werden können, nennt HP als Möglichkeit („might function“, „An alternative is“); `print.remedies[7]` sagt es ebenso. Das Wartungsfenster in dessen Voraussetzung stammt nicht von HP. |
| System Administrator's Guide For the HP V3 Universal Print Driver (PCL 6/PS) and the HP Print Administrator's Resource Kit (PARK) | <https://kaas.hpcloud.hp.com/pdf-public/pdf_8951296_en-US-1.pdf> | 2026-11-13 | `print.checks[20]` SNMP-Einstellungen und WSD-Anschluss beim HP Universal Print Driver<br>`print.checks[22]` Eingrenzung nach HP (zugeordneter Treiber, außerhalb der Sitzung, sauberes Testsystem)<br>`print.remedies[6]` Treiberwahl nach Endgerät (Citrix-Universaltreiber oder HP Universal Print Driver)<br>`print.remedies[8]` Reihenfolge beim Entfernen des HP Universal Print Driver<br>`print.remedies[9]` Dienst neu starten, wenn Windows den Treiber als in Gebrauch meldet<br>`print.contacts[1]` Angaben für den Support von HP | Edition 11, Mai 2026. Die Aussagen zum Status „Offline“ bei falschen SNMP-Einstellungen und zum WSD-Anschluss macht HP für den HP Universal Print Driver; `print.checks[20]` beschränkt sich darauf. Die Reihenfolge beim Entfernen beschreibt HP für den HP Universal Print Driver. Das Wartungsfenster (`print.remedies[8]`, `print.remedies[9]`) und der Hinweis, dass beim Neustart des Dienstes alle Benutzer kurz nicht drucken können und laufende Aufträge verloren gehen können, stammen nicht von HP. |
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
| KX DRIVER INSTALLER Release Notes (KYOCERA Document Solutions America, Inc.) | <https://www.kyoceradocumentsolutions.us/content/dam/download-center-americas-cf/us/drivers/drivers/KX_Driver_Read_Me_pdf.download.pdf> | 2026-11-13 | `crash.remedies[4]` KPDL- oder PCL-Uni-Treiber statt KX-Treiber<br>`print.checks[13]` vollständiger KX-Treiber auf dem Server<br>`print.remedies[16]` KPDL- oder PCL-Uni-Treiber statt KX-Treiber<br>`print.remedies[17]` KX-Treiber erst deinstallieren, dann neu installieren<br>`print.contacts[2]` Support von Kyocera (Help Desk) bei Einsatz des KX-Treibers | Das Dokument trägt kein Datum. Das Wartungsfenster in der Voraussetzung von `print.remedies[17]` stammt nicht von Kyocera. |
| Class leading performance with the KYOCERA V4 KX DRIVER. (data sheet) | <https://www.kyoceradocumentsolutions.us/content/dam/download-center-americas-cf/us/drivers/drivers/KYOCERA_V4_KX_Driver_Datasheet_pdf.download.pdf> | 2026-11-13 | `print.remedies[19]` Funktionsumfang vergleichen, bevor von Typ 3 auf Typ 4 gewechselt wird<br>`print.remedies[20]` Funktionsumfang vergleichen, bevor von Typ 4 auf Typ 3 gewechselt wird | Datenblatt von 2019. Es vergleicht den Funktionsumfang; mit einem Druckfehler hat das nichts zu tun. Beide Elemente stehen deshalb als Abhilfe unter der Voraussetzung, dass ein Wechsel der Bauart erwogen wird. |
| Release Notes April 29, 2025 (DVD Contents) | <https://dam.kyoceradocumentsolutions.com/content/dam/gdam_dc/dc_global/document/manual/product_086/Readme_EN_202505.pdf> | 2026-11-13 | `print.remedies[18]` Kyocera-Treiber mit KmUninstall.exe entfernen | Die Seite nennt den Weg zum Deinstallationsprogramm, aber keinen weiteren Weg, verbliebene Treiber zu entfernen. Das Wartungsfenster in der Voraussetzung stammt nicht von Kyocera. |

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
| I'm using Windows Vista, Windows 7, Windows 8 or Windows 10 and a network connected Brother machine. The following errors "Error - Sent to Printer", "Sent to Printer" or "Deleting - Printing" appear in the PC Print Queue. | <https://support.brother.com/g/b/faqend.aspx?c=us_ot&lang=en&prod=mfc6490cw_all&faqid=faq00002440_000> | 2026-11-13 | `print.checks[21]` stehende Aufträge an Brother-Geräten<br>`print.remedies[14]` Dienst „Druckwarteschlange“ nach Brother zurücksetzen | Seite vom 14.02.2023; sie gilt für Windows Vista bis 10 und Geräte mit Netzwerkanschluss; beide Elemente sagen das. Der Hinweis, dass die Aufträge aller Benutzer des Servers verloren gehen, stammt nicht von Brother, ebenso wenig die Voraussetzungen, dass sich die Aufträge nicht einzeln löschen lassen und die Benutzer informiert sind. Der Zusatz zum Neustart nicht persistenter Server stammt ebenfalls nicht von Brother (siehe „Zielumgebung“). |
| Use the Universal Printer Driver for BR-Script. (PostScript language emulation) | <https://support.brother.com/g/b/faqend.aspx?c=ca&lang=en&prod=hl4570cdw_all&faqid=faq00002993_000> | 2026-11-13 | `print.remedies[21]` Brother Universal Printer Driver als gemeinsamer Treiber | Seite vom 29.03.2017. Die Liste der Betriebssysteme (help.brother-usa.com, Antwort 67181) endet bei Windows Server 2016; zu Terminalservern oder Citrix sagt die Seite nichts. |
| Uninstall the Brother Software and Drivers (Windows) | <https://support.brother.com/g/b/faqend.aspx?c=us_ot&lang=en&prod=hll2370dw_us&faqid=faq00000071_010> | 2026-11-13 | `print.remedies[22]` Brother-Treiber vollständig entfernen | Seite vom 02.04.2026; sie nennt Windows 7 bis 11. Das „Uninstall Tool“ gibt es laut Seite nicht für jedes Betriebssystem. Das Wartungsfenster in der Voraussetzung stammt nicht von Brother. |

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
| Release Notes 6.2 deutsch | <https://www.aki-gmbh.com/download/45927/> | 2026-11-13 | `crash.checks[30]` Version des .NET Framework prüfen<br>`print.checks[28]` Bei falschem Standarddrucker, doppelt angezeigten Druckern oder falschen Druckern nach einem Wechsel des En … | Release Notes PrinTaurus 6.2, Version 11 vom 28.03.2022. Kapitel 2 nennt .NET Framework 4.7.2 für die SmartSpread Clients; den Registrierungswert Release und die Zahl 461808 nennt Microsoft („How to determine which .NET Framework versions are installed“). Kapitel 3 nennt den behobenen Fehler beim erzwungenen Standarddrucker, die bekannte Einschränkung (doppelte Anzeige) und als Änderung, dass die Zuordnungen bei einem Wechsel des Endgeräts ohne Neuanmeldung passend gesetzt werden; ob ältere Versionen das nicht taten, sagt AKI nicht, und `print.checks[28]` sagt es auch nicht. |
| Release Notes PrinTaurus 6.4 | <https://www.aki-gmbh.com/download/47826/> | 2026-11-13 | `crash.checks[31]` Version des PrinTaurus SmartSpread Client mit der Version der übrigen PrinTaurus-Komponenten vergleichen<br>`crash.remedies[12]` PrinTaurus auf eine Version bringen, die AKI noch unterstützt<br>`crash.contacts[3]` Support von AKI: mit Version des SmartSpread Client, Uhrzeit, fehlerhaftem Modul und Fehlercode aus den Bel …<br>`hang.checks[18]` Version des PrinTaurus SmartSpread Client mit der Version der übrigen PrinTaurus-Komponenten vergleichen<br>`print.remedies[23]` PrinTaurus SmartSpread Client und die übrigen PrinTaurus-Komponenten auf denselben Release-Stand bringen, b …<br>`print.remedies[24]` Lokale IPP-Druckerwarteschlangen von PrinTaurus SmartSpread den Benutzern dieses Servers nicht zuweisen | Release Notes PrinTaurus 6.4, Version 3 vom 16.02.2025. Die Regel „alle Komponenten im selben Release“ steht unter den Hinweisen zum Update auf 6.4; die Elemente beschränken sie darauf. Dass die Version unter „Programme und Features“ dieser Release-Stand ist, sagt AKI nicht. Die Release Notes nennen support@aki-gmbh.com; welche Angaben der Support braucht, ist ein eigener Hinweis. Der Zusatz zum Master-Image stammt nicht von AKI. |

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
| Agent event logs (WEM current release) | <https://docs.citrix.com/us/en/workspace-environment-management/current-release/reference/agent-event-logs.html> | 2026-11-13 | `cpu.checks[13]` Im Ereignisprotokoll des WEM-Agenten nachsehen, ob der CPU-Spitzenschutz von Citrix Workspace Environment M …<br>`memory.checks[11]` Im Ereignisprotokoll des WEM-Agenten nachsehen, ob die Speicheroptimierung von Citrix Workspace Environment … | Die Seite nennt die Ereignisse 7001 und 7002 (CPU-Spitzenschutz) und 8001 bis 8003 (Speicheroptimierung). Die Bezeichnung des Protokolls „WEM Agent Service“ stammt von den Seiten „CPU Management“ und „System optimization“; den genauen Namen des Protokolls dokumentiert Citrix nicht (siehe „Auf dem Zielsystem zu bestätigen“). Was die Speicheroptimierung mit dem Arbeitsspeicher untätiger Prozesse tut, steht auf der Seite „Memory Management“. |

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
| Fix high CPU or memory usage in Microsoft Edge | <https://learn.microsoft.com/en-us/troubleshoot/microsoft-edge/performance/edge-high-cpu-memory> | 2026-11-13 | `cpu.checks[3]` Im Browser-Task-Manager von Microsoft Edge nachsehen, welcher Tab, welche Erweiterung oder welcher Hilfspro …<br>`cpu.checks[4]` Klären, ob der Benutzer Videos, WebGL- oder Canvas-Inhalte im Browser nutzte<br>`cpu.remedies[3]` Erweiterungen von Microsoft Edge abschalten und einzeln wieder einschalten, bis die verursachende gefunden ist<br>`cpu.remedies[4]` Schlafende Tabs in Microsoft Edge einschalten<br>`cpu.remedies[5]` Weiterlaufen von Erweiterungen und Apps im Hintergrund nach dem Schließen von Microsoft Edge abschalten<br>`memory.checks[3]` Im Browser-Task-Manager von Microsoft Edge nachsehen, welcher Tab oder welche Erweiterung den Arbeitsspeich … | Stand der Seite 2026-06-03. Die Namen der Richtlinien SleepingTabsEnabled und BackgroundModeEnabled stehen auf den Richtlinienseiten von Microsoft Edge. Eine Schwelle für die Zeit bis zum Schlafen nennt der Katalog nicht (Microsoft nennt 900 Sekunden nur als Standard). Dass Edge ohne Grafikkarte in Software rendert, sagt die Seite nicht; `cpu.checks[4]` fragt deshalb nur nach den Inhalten. |
| Microsoft Edge for Virtual desktop infrastructure (VDI) | <https://learn.microsoft.com/en-us/deployedge/edge-for-virtualized-desktop-infrastructure> | 2026-11-13 | `memory.checks[4]` Arbeitsspeicher je Benutzer mit der Angabe von Microsoft für Edge auf VDI vergleichen<br>`profile.checks[5]` Prüfen, ob Richtlinien die Benutzerdaten oder den Cache von Microsoft Edge auf eine Freigabe legen | Stand 2026-11-03. Die Seite spricht allgemein von „VDI“, nicht von Servern mit mehreren Sitzungen. Ob Daten in einem Profilcontainer als umgeleitet oder geroamt gelten, sagt Microsoft nicht; das Element zu den Benutzerdaten sagt das. |
| Microsoft Edge stops responding or doesn't start | <https://learn.microsoft.com/en-us/troubleshoot/microsoft-edge/performance/edge-crashes-fails-to-launch> | 2026-11-13 | `crash.checks[19]` Die von Microsoft genannten häufigen Ursachen prüfen<br>`hang.checks[12]` Die von Microsoft genannten häufigen Ursachen prüfen | Stand 2026-06-03. Die Seite nennt Ereignisse der Quelle „Application Error“ zu msedge.exe; eine Ereignisnummer nennt sie nicht. |
| Enable Process Isolation (ProcessIsolationEnabled) | <https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/processisolationenabled> | 2026-11-13 | `crash.checks[20]` Einstellung „Process Isolation“ von Microsoft Edge feststellen | Ab Microsoft Edge 151; ohne Richtlinie wird die Funktion laut Microsoft schrittweise eingeführt. Komponenten von Citrix nennt Microsoft nicht. |
| Configure auto discard sleeping tabs (AutoDiscardSleepingTabsEnabled) | <https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/autodiscardsleepingtabsenabled> | 2026-11-13 | `memory.remedies[2]` Automatisches Verwerfen schlafender Tabs in Microsoft Edge nicht abschalten | Ab Microsoft Edge 120; ohne Richtlinie ist das Verwerfen eingeschaltet. |
| Set limit on megabytes of memory a single Microsoft Edge instance can use (TotalMemoryLimitMb) | <https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/totalmemorylimitmb> | 2026-11-13 | `memory.remedies[3]` Speichergrenze je Instanz von Microsoft Edge setzen | Ab Microsoft Edge 80. Microsoft beschreibt die Richtlinie, empfiehlt sie aber nicht; Werte unter 1024 werden auf 1024 aufgerundet. |
| Microsoft Edge - Update policies | <https://learn.microsoft.com/en-us/deployedge/microsoft-edge-update-policies> | 2026-11-13 | `crash.checks[21]` Version der WebView2-Runtime feststellen<br>`crash.remedies[8]` WebView2-Runtime auf den aktuellen Stand bringen | Abschnitt „Update (WebView)“, Microsoft Edge Update ab 1.3.127.1. Für nicht persistente Maschinen nennt Microsoft auf der Seite zu Edge für VDI als bewährtes Vorgehen, automatische Updates abzuschalten und über das Master-Image zu aktualisieren: Der Stand der Runtime ist dann der des Master-Image, und beide Elemente sagen das. |
| WebView2 end-user FAQ | <https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/end-user-faq> | 2026-11-13 | `cpu.checks[6]` Feststellen, welche Anwendung ‹Anwendung› nutzt<br>`memory.checks[5]` Feststellen, welche Anwendung ‹Anwendung› nutzt | Seite von 2023. Teams und Outlook nennt Microsoft als Beispiele für Anwendungen, die WebView2 nutzen; „in den meisten Fällen“ bezieht sich auf die Art der Nutzung von WebView2. |
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
| Optimization for Microsoft Teams (New) | <https://docs.citrix.com/us/en/citrix-virtual-apps-desktops/current-release/multimedia/opt-ms-teams-new.html> | 2026-11-13 | `cpu.checks[10]` Prüfen, ob Teams in der Sitzung von ‹Benutzer› mit Medienoptimierung lief<br>`memory.checks[8]` Prüfen, ob Teams in der Sitzung von ‹Benutzer› mit Medienoptimierung lief | Abschnitt „Interoperability and roaming“. Wo Teams den Stand der Optimierung anzeigt, nennt diese Seite nicht (siehe „Auf dem Zielsystem zu bestätigen“). |
| Optimization for Microsoft Teams (Classic) | <https://docs.citrix.com/us/en/citrix-virtual-apps-desktops/current-release/multimedia/opt-ms-teams.html> | 2026-11-13 | `memory.checks[10]` Größe des Servers für Teams einordnen<br>`disk.checks[4]` Bedarf von Teams an Datenträgerzugriffen einordnen | Messung von Citrix mit dem klassischen Teams unter Windows Server 2019 (Version 2106), ohne Medien; beide Elemente sagen, dass es eine Messung mit dem klassischen Teams ist. Die Angabe „512 bis 1024 MB je Benutzer“ der Seite meint Speicherplatz, nicht Arbeitsspeicher, und ist nicht übernommen. |
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
| Performance recommendations for Microsoft 365 Apps on Windows 10 | <https://learn.microsoft.com/en-us/microsoft-365-apps/best-practices/performance-recommendations> | 2026-11-13 | `cpu.checks[8]` Add-ins von ‹Anwendung› prüfen<br>`cpu.checks[9]` Add-ins von ‹Anwendung› prüfen (für Outlook)<br>`cpu.remedies[8]` Add-ins von ‹Anwendung›, die nicht gebraucht werden, entfernen und die übrigen aktuell halten<br>`cpu.remedies[9]` Add-ins von ‹Anwendung›, die nicht gebraucht werden, entfernen und die übrigen aktuell halten (für Outlook)<br>`memory.checks[6]` Add-ins von ‹Anwendung› prüfen<br>`memory.checks[7]` Add-ins von ‹Anwendung› prüfen (für Outlook)<br>`crash.checks[24]` Add-ins von ‹Anwendung› als Ursache prüfen<br>`crash.checks[26]` Add-ins von ‹Anwendung› als Ursache prüfen (für Outlook) | Die Seite gilt für Microsoft 365 Apps unter Windows 10; zu Office LTSC 2024 sagt Microsoft nur, dass Add-ins früherer Versionen voraussichtlich funktionieren. Die Prüfschritte sagen, wofür Microsoft den Test beschreibt. Die Rücksprache mit den Benutzern und der Ort der Änderung stammen nicht von Microsoft. |
| Add-ins are user re-enabled after being disabled by Office programs | <https://learn.microsoft.com/en-us/troubleshoot/outlook/performance/add-ins-are-user-re-enabled-after-being-disabled> | 2026-11-13 | `hang.checks[14]` Nachsehen, ob Office ein Add-in von Outlook wegen langsamer Ausführung abgeschaltet hat und wie lange die A … | Die Seite nennt die Ereignisse 45 und 59 im Protokoll „Anwendung“. |
| You may experience application pauses if you have a large Outlook data file | <https://learn.microsoft.com/en-us/troubleshoot/outlook/performance/application-pauses-if-you-have-large-data-file> | 2026-11-13 | `profile.checks[3]` Größe der OST-Datei von Outlook und Zahl der Elemente je Ordner prüfen<br>`profile.remedies[1]` Lokale Postfachdaten von Outlook verkleinern<br>`hang.checks[15]` Größe der OST-Datei von Outlook bei den betroffenen Benutzern prüfen | Die Zahlen zu Elementen je Ordner stehen auf der Seite „Outlook performance issues in a Cached Exchange Mode .ost or .pst file“. Die Werte der Richtlinie für den Zeitraum des Cache-Modus sind auf keiner gelesenen Seite belegt; der Katalog nennt deshalb keinen Wert. |
| Limits to using personal folders files over LAN and WAN links | <https://learn.microsoft.com/en-us/troubleshoot/outlook/data-files/limits-using-pst-files-over-lan-wan> | 2026-11-13 | `share.checks[2]` Prüfen, ob PST- oder OST-Dateien von Outlook direkt auf einer Freigabe liegen | Microsoft nennt als Bedingungen eine Verbindung mit hoher Bandbreite und geringer Latenz und ein Outlook je Datei. |
| Outlook not responding error or Outlook freezes when you open a file or send mail | <https://learn.microsoft.com/en-us/troubleshoot/outlook/performance/outlook-not-responding-error-or-outlook-freezes> | 2026-11-13 | `hang.checks[16]` Prüfen, ob der Ordner AppData auf eine Freigabe umgeleitet ist und ob die Schutzsoftware ein Add-in oder ei … | Die Seite nennt beide Ursachen getrennt; das Element fasst sie zusammen. |
| Plan and configure Cached Exchange Mode in Outlook 2016 for Windows | <https://learn.microsoft.com/en-us/microsoft-365-apps/outlook/configuration/cached-exchange-mode> | 2026-11-13 | `disk.checks[3]` Einordnen, ob die Last vom Cache-Modus von Outlook kommt | Für Outlook 2016 geschrieben; ob die Aussage für Outlook LTSC 2024 gilt, sagt die Seite nicht. Das Element sagt das. |
| Overview of Office LTSC 2024 | <https://learn.microsoft.com/en-us/office/ltsc/2024/overview> | 2026-11-13 | `crash.checks[25]` Feststellen, ob Office als 32-Bit- oder 64-Bit-Version installiert ist<br>`crash.checks[27]` Feststellen, ob Office als 32-Bit- oder 64-Bit-Version installiert ist (für Outlook) | Dass die 64-Bit-Version mehr Arbeitsspeicher nutzen kann, steht nicht auf der Seite und ist nicht übernommen. |
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
| Install Teams for Virtualized Desktop Infrastructure (VDI) | <https://learn.microsoft.com/en-us/microsoftteams/teams-client-vdi-requirements-deploy> | 2026-11-13 | `cpu.checks[5]` Prüfen, ob der Benutzer Microsoft Teams im Browser statt im Teams-Client nutzte<br>`cpu.remedies[10]` Rückfall von Teams in die nicht optimierte Verarbeitung abschalten oder auf Audio begrenzen<br>`memory.remedies[4]` Rückfall von Teams in die nicht optimierte Verarbeitung abschalten oder auf Audio begrenzen<br>`crash.checks[29]` Stand der Unterstützung von Teams auf dem Betriebssystem des Servers einordnen | Stand 2026-08-25. DisableFallback gilt ab Teams 24257; ob der Rückfall abgeschaltet wird, überlässt Microsoft dem Betreiber. Dieselbe Seite nennt Oktober 2026 als Ende der Unterstützung auf Windows Server 2022 und führt Windows Server 2022 in der Tabelle der Anforderungen weiter; `crash.checks[29]` nennt beides. Der Zusatz zum Master-Image stammt nicht von Microsoft. |
| New VDI solution for Teams | <https://learn.microsoft.com/en-us/microsoftteams/vdi-2> | 2026-11-13 | `cpu.checks[11]` Klären, ob der Benutzer an einer Großveranstaltung<br>`cpu.checks[12]` Klären, ob der Benutzer seinen Bildschirm geteilt hat<br>`cpu.remedies[11]` Bildrate der vom Server kodierten Bildschirmfreigabe begrenzen<br>`memory.checks[9]` Klären, ob der Benutzer an einer Großveranstaltung | Stand 2026-11-12. Die Messwerte von Microsoft zur Bildschirmfreigabe stammen von einer virtuellen Maschine mit einem Benutzer und vier Prozessoren; der Katalog nennt deshalb keine Zahl. Die vom Server kodierte Bildschirmfreigabe ist für Windows-Endgeräte laut Seite in der Vorschau. |
| Include or exclude Teams from antivirus or DLP applications | <https://learn.microsoft.com/en-us/troubleshoot/microsoftteams/teams-administration/include-exclude-teams-from-antivirus-dlp> | 2026-11-13 | `crash.checks[28]` Prüfen, ob Schutz-, Überwachungs- oder DLP-Software in Teams eingreift<br>`crash.remedies[11]` Prozesse von Teams in der Schutzsoftware ausnehmen, wie Microsoft sie nennt<br>`hang.checks[17]` Prüfen, ob Schutz-, Überwachungs- oder DLP-Software in Teams eingreift | Stand 2026-11-09. Microsoft spricht von Schutzsoftware anderer Hersteller; die Elemente sagen das. Die Zustimmung der Verantwortlichen für die Sicherheit stammt nicht von Microsoft. |

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
| Citrix Virtual Delivery Agent (VDA) 2411 | <https://www.carlstalhood.com/virtual-delivery-agent-vda-cr/> | 2026-11-13 | `cpu.checks[20]` Ausschlüsse der Schutzsoftware mit der Empfehlung aus der Praxis vergleichen<br>`cpu.checks[25]` Zahl der Prozessoren der virtuellen Maschine mit der Empfehlung aus der Praxis vergleichen<br>`memory.checks[16]` Arbeitsspeicher der virtuellen Maschine mit der Empfehlung aus der Praxis vergleichen<br>`disk.checks[9]` Ausschlüsse der Schutzsoftware mit der Empfehlung aus der Praxis vergleichen | Stand der Seite 4.12.2024. Die Größe (8 vCPU, 24 bis 48 GB) nennt die Seite für Windows Server 2016 bis 2022 als Server mit mehreren Sitzungen. Die Liste der Ausschlüsse gibt die Seite als Inhalt eines Beitrags von Citrix wieder, der nicht mehr erreichbar war; sie steht deshalb hier und nicht unter Citrix. Den Ausschluss des WEM-Agenten nennt die Seite „Workspace Environment Management (WEM) 2411“ derselben Quelle. |
| Citrix Health Check | <https://www.carlstalhood.com/citrix-health-check/> | 2026-11-13 | `cpu.checks[26]` Energiesparplan des Servers feststellen<br>`memory.remedies[7]` Arbeitsspeicher der virtuellen Maschine mindestens so groß wählen wie den zugesagten Speicher<br>`delay.many.checks[11]` Energiesparplan des Servers feststellen<br>`delay.single.checks[9]` Energiesparplan des Servers feststellen | Stand der Seite 28.2.2024 (Prüfliste). Zum Energiesparplan siehe „Ausnahmen: Praxisquelle vor Hersteller“. Die Aussage zum zugesagten Speicher ist ein Punkt der Prüfliste ohne Zahl. |
| Citrix Profile Management 2411 | <https://www.carlstalhood.com/citrix-profile-management/> | 2026-11-13 | `share.remedies[1]` Active Write Back der Citrix Profilverwaltung abschalten<br>`profile.checks[12]` Ausschlusslisten der Citrix Profilverwaltung mit der Empfehlung aus der Praxis vergleichen<br>`profile.remedies[5]` Einstellungen der Citrix Profilverwaltung für schnelle Anmeldungen prüfen | Stand der Seite 8.2.2025. Die Empfehlung zu Streaming und Profilcontainer schreibt die Seite Citrix zu (CTX463658); der Artikel war nicht lesbar, deshalb steht sie hier und nicht unter Citrix. Die Prüfung der Ausschlüsse bei der Anmeldung („Logon Exclusion Check“) nennt die Seite nur als Möglichkeit und ist nicht übernommen; die Ausschlüsse für das klassische Teams ebenfalls nicht. |
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
| AppData nicht auf eine Freigabe umleiten | der Hersteller sagt es für Outlook selbst (Microsoft, aufgenommen unter Office); für andere Anwendungen stützt die Messung es nicht |
| Netzwerkschutz von Microsoft Defender abschalten | setzt eine Änderung voraus, die die Messung nicht stützt (Schutzfunktion; die Messung erfasst keine unterbrochenen Sitzungen) |
| Drucken: keine direkten Verbindungen zu Druckservern, Citrix Universal Print Server | setzt eine Änderung voraus, die die Messung nicht stützt (in der Zielumgebung ordnet PrinTaurus SmartSpread die Drucker zu) |
| Anmeldeverzögerungen aus Windows-Richtlinien, hängende Sitzungen veröffentlichter Anwendungen, lokale Profile löschen | setzt eine Änderung voraus, die die Messung nicht stützt (der Bericht hat keine Situation für die Dauer der Anmeldung) |

## BIS-F (Empfehlung aus der Praxis)

Das Base Image Script Framework (BIS-F) ist eine Sammlung von Skripten, die ein Master-Image vor dem Versiegeln vorbereiten: eine Quelle aus der Praxis, keine Dokumentation eines Herstellers. Was BIS-F einstellt, steht in seinen Skripten; die Dokumentation beschreibt den Stand 7.1912 (Windows Server bis 2019). Jedes Element nennt die Quelle mit dem Zusatz „Empfehlung aus der Praxis“.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| 97_PrepBISF_PRE_BaseImage.ps1 | <https://raw.githubusercontent.com/EUCweb/BIS-F/master/Framework/SubCall/Preparation/97_PrepBISF_PRE_BaseImage.ps1> | 2026-11-13 | `cpu.remedies[16]` Energiesparplan „Höchstleistung“ einstellen<br>`delay.many.remedies[1]` Energiesparplan „Höchstleistung“ einstellen<br>`delay.single.remedies[2]` Energiesparplan „Höchstleistung“ einstellen | Skript des Zweigs „master“; BIS-F stellt den Plan beim Versiegeln ohne Bedingung ein. Der Vorschlag steht nur unter der Ausnahme des Auftraggebers (siehe „Ausnahmen: Praxisquelle vor Hersteller“); das Element nennt die Sicht von Microsoft und VMware. |

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
| Hinweis zur Auswertung | `print.checks[3]` Muster „Speichermangel“: Speichermangel als Ursache prüfen<br>`print.checks[4]` Muster „Modul der Schutzsoftware“: deren Meldungen ansehen<br>`print.checks[5]` Muster „ein Benutzer“: Drucker und Profil dieses Benutzers prüfen<br>`print.checks[6]` Muster „zeitgleich mit einem Leistungsvorfall“: auch dessen Anleitung ansehen<br>`print.checks[7]` Muster „zeitnahes Ereignis“: das Ereignis prüfen<br>`print.checks[23]` Druckproblem vor der Messung: Wiederkehr prüfen<br>`print.checks[25]` Drucken nicht gemessen: von Hand prüfen, nächste Messung mit Drucken<br>`print.checks[26]` Muster nicht geprüft: von Hand eingrenzen<br>`print.checks[27]` Zuordnung der Drucker durch ein Zuordnungswerkzeug bei Anmeldung und Wiederverbindung<br>`print.checks[29]` Vorfall vor der Messung: Reichweite des Rückblicks auf nicht persistenten Servern | Dieselben Hinweise stehen in den anderen Situationen aus Ereignissen ohne Quelle; dort verlangt der Katalog keine. Der Schritt zur Zuordnung der Drucker nennt kein Produkt: Wie PrinTaurus SmartSpread zuordnet, dokumentiert sein Hersteller nicht öffentlich (siehe Abschnitt AKI). |

## Auf dem Zielsystem zu bestätigen

Der Katalog nennt Werkzeuge, Einstellungen und Bezeichnungen von Windows, Citrix und VMware so, wie sie nach bestem
Wissen auf einem deutschen Windows Server 2022 mit Citrix VDA heißen. Geprüft werden konnte das hier nicht. Die
folgenden Angaben sind beim Test auf dem Zielsystem zu bestätigen; stimmt eine nicht, wird der Text im Katalog
angepasst.

- **Abhängigkeit des Dienstes „Druckwarteschlange“** (`print.checks[15]`): Microsoft nennt als Standard für den Wert
  DependOnService nur RpcSs. Ob ein Windows Server 2022 ohne Druckproblem weitere Einträge hat (vermutet wird http),
  zeigt `sc qc spooler` auf einem solchen Server. Der Prüfschritt nennt deshalb als Merkmal nur einen Eintrag, den
  ein Server ohne Druckproblem nicht hat.
- **Drei Gruppenrichtlinien zum Drucken** (`crash.checks[3]`, `print.checks[10]`, `print.remedies[2]`): Der Katalog
  nennt sie englisch wie die Quelle („Isolate print drivers from applications“, „Execute print drivers in isolated
  processes“, „Override print driver execution compatibility setting reported by print driver“). Zu bestätigen sind
  ihre deutschen Anzeigenamen unter Computerkonfiguration > Administrative Vorlagen > Drucker und, dass sie auf
  Windows Server 2022 gelten (die Seite von Microsoft nennt Windows 10 und 11). Eindeutig sind die Registrierungswerte
  ApplicationDriverIsolation, PrintDriverIsolationExecutionPolicy und PrintDriverIsolationOverrideCompat.
- **Treiberisolierung in der Druckverwaltung** (`print.checks[8]`, `print.remedies[0]`): die Stelle (Knoten
  „Treiber“, Kontextmenü des Treibers) und die Bezeichnung des Befehls und seiner Werte. Der Bericht nennt die Werte
  „keine“, „gemeinsam“ und „isoliert“.
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
