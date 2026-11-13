# Quellen der Druckempfehlungen

Der Katalog `src/guidance.de.json` enthält Empfehlungen zum Drucken auf Citrix- und Terminalservern: die Elemente der
Situation `print` und in anderen Situationen die Elemente mit einer Bedingung `pattern.printdriver` oder `driver.*`.
Jedes dieser Elemente nennt im Feld `source` den Hersteller und den Titel des Dokuments, aus dem es stammt; der
Bericht zeigt die Quelle beim Element. Diese Datei weist je Hersteller nach, welches Dokument welches Element stützt,
und nennt die Empfehlungen, die gefunden, aber nicht aufgenommen wurden, mit dem Grund.

Ein Element der Situation `print`, das keine Empfehlung eines Herstellers ist, sondern ein Hinweis des Berichts
selbst, trägt die Quelle „WorkerPerf: Hinweis zur Auswertung“; der Abschnitt „WorkerPerf“ führt diese Elemente auf.
Der Abschnitt „Auf dem Zielsystem zu bestätigen“ am Ende nennt die Bezeichnungen von Windows, Citrix und VMware im
ganzen Katalog, die hier nicht geprüft werden konnten.

Eine Stelle wie `print.remedies[2]` bezeichnet Situation, Liste und Position im Katalog, gezählt ab 0:
`print.remedies[2]` ist der dritte Abhilfevorschlag der Situation `print`. Stand: Katalog `version` 2026-11-13.

## Wie die Quellen geprüft wurden

- Recherchiert wurde am 13.11.2026 nur in der eigenen Dokumentation der fünf Hersteller (Microsoft Learn,
  docs.citrix.com und die Support- und Dokumentseiten von HP, Kyocera und Brother). Seiten Dritter, Foren und
  Suchtreffer ohne geöffnete Seite zählen nicht als Quelle.
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
steht und dass hier keine Stelle steht, die der Katalog nicht hat.

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
| Drivers policy settings | <https://docs.citrix.com/us/en/citrix-virtual-apps-desktops/current-release/policies/reference/ica-policy-settings/printing-policy-settings/drivers-policy-settings.html> | 2026-11-13 | `print.checks[17]` Richtlinie zur Verwendung des Universaltreibers | Aktuelle Fassung der Produktdokumentation. |
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
| I'm using Windows Vista, Windows 7, Windows 8 or Windows 10 and a network connected Brother machine. The following errors "Error - Sent to Printer", "Sent to Printer" or "Deleting - Printing" appear in the PC Print Queue. | <https://support.brother.com/g/b/faqend.aspx?c=us_ot&lang=en&prod=mfc6490cw_all&faqid=faq00002440_000> | 2026-11-13 | `print.checks[21]` stehende Aufträge an Brother-Geräten<br>`print.remedies[14]` Dienst „Druckwarteschlange“ nach Brother zurücksetzen | Seite vom 14.02.2023; sie gilt für Windows Vista bis 10 und Geräte mit Netzwerkanschluss; beide Elemente sagen das. Der Hinweis, dass die Aufträge aller Benutzer des Servers verloren gehen, stammt nicht von Brother, ebenso wenig die Voraussetzungen, dass sich die Aufträge nicht einzeln löschen lassen und die Benutzer informiert sind. |
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

## WorkerPerf

Eigene Hinweise der Auswertung. Diese Elemente der Situation `print` stammen von keinem Hersteller: Sie führen zu
dem, was der Bericht bei der Ursache des Vorfalls nennt (die Muster), oder sagen, was nicht gemessen oder nicht
geprüft wurde und wie sich das nachholen lässt. Weil in der Situation `print` jedes Element eine Quelle nennt,
tragen sie die Quelle „WorkerPerf: Hinweis zur Auswertung“. Keines ist als Empfehlung eines Herstellers formuliert,
und keines nennt einen Hersteller.

| Titel | Übernommene Elemente | Hinweis |
|---|---|---|
| Hinweis zur Auswertung | `print.checks[3]` Muster „Speichermangel“: Speichermangel als Ursache prüfen<br>`print.checks[4]` Muster „Modul der Schutzsoftware“: deren Meldungen ansehen<br>`print.checks[5]` Muster „ein Benutzer“: Drucker und Profil dieses Benutzers prüfen<br>`print.checks[6]` Muster „zeitgleich mit einem Leistungsvorfall“: auch dessen Anleitung ansehen<br>`print.checks[7]` Muster „zeitnahes Ereignis“: das Ereignis prüfen<br>`print.checks[23]` Druckproblem vor der Messung: Wiederkehr prüfen<br>`print.checks[25]` Drucken nicht gemessen: von Hand prüfen, nächste Messung mit Drucken<br>`print.checks[26]` Muster nicht geprüft: von Hand eingrenzen | Dieselben Hinweise stehen in den anderen Situationen aus Ereignissen ohne Quelle; dort verlangt der Katalog keine. |

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

## Zustandsbild

Der Katalog `src/health.de.json` bewertet das Zustandsbild des Servers. Jede Prüfung nennt im Feld `source` eine
Quelle mit Titel, Adresse und Datum und im Feld `kind` ihre Art: „Empfehlung des Herstellers“ (`vendor`), „Empfehlung
aus der Praxis“ (`practice`) oder „Faustregel“ (`rule`). Dieser Abschnitt weist die Quellen nach. Er enthält bisher
die Prüfungen der Bereiche Größe und Reserve, Betrieb, Sitzungen, Citrix VDA und Profilverwaltung; die übrigen
Bereiche folgen. Stand: Katalog `version` 2026-11-13.

Wie die Quellen geprüft wurden:

- Jede Quelle wurde am 13.11.2026 für diesen Katalog geöffnet und die Aussage, auf die sich eine Prüfung stützt, mit
  dem Text der Seite verglichen. Übernommen ist nur, was die Seite selbst sagt; eine Zahl aus einer Messung steht im
  Katalog mit den Bedingungen der Messung.
- Das Datum im Katalog ist der Stand, den die Seite selbst nennt (bei Microsoft Learn „Last updated on“, bei
  docs.citrix.com „Last published“, bei techdocs.broadcom.com „Last Updated“, bei einem Blog das Datum des Beitrags).
  Nennt eine Seite keinen Stand, steht das Datum des Abrufs da.
- Eine Prüfung aus einer Praxisquelle heißt nie „Empfehlung des Herstellers“. Widerspricht eine Praxisquelle dem
  Hersteller, gilt der Hersteller, und der Katalog nennt den Widerspruch. Die Ausnahmen legt der Auftraggeber fest;
  sie stehen unten.
- Der Katalog gilt für nicht persistente Multi-Session-Server, die über Machine Creation Services bereitgestellt
  werden. Empfehlungen, die nur für andere Bereitstellungsarten, persistente Maschinen oder Einzelplatz-Desktops
  gelten, sind nicht aufgenommen.

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
`practice` tragen in den fünf Bereichen dieses Abschnitts nur Prüfungen, deren Quelle carlstalhood.com ist; BIS-F
und sieben weitere Praxisquellen stehen als zweite Quelle im Text einzelner Prüfungen (unten: „auch gestützt
durch“). Von Trentent Tye, John Billekens und Benny Tritsch stützt sich in diesen fünf Bereichen keine Prüfung.

### Quellen aus der Praxis: BIS-F

Base Image Script Framework (BIS-F), ein Werkzeug zum Versiegeln von Abbildern. Die Quelle ist für Windows Server
2022 sichtbar älter: Dokumentation „7.1912“ (Dezember 2019 bis Januar 2020), die Liste der Betriebssysteme endet bei
Windows Server 2019. Der Katalog kennzeichnet sie deshalb als ältere Praxis.

| Titel | Adresse | Stand der Seite | Abruf | Prüfungen |
|---|---|---|---|---|
| 97_PrepBISF_PRE_BaseImage.ps1 (Skript im Quelltext von BIS-F) | https://raw.githubusercontent.com/EUCweb/BIS-F/master/Framework/SubCall/Preparation/97_PrepBISF_PRE_BaseImage.ps1 | letzter Eintrag der Historie im Skript: 22.11.2020 | 2026-11-13 | `operation.powerPlan` (zweite Praxisquelle im Text: BIS-F stellt beim Versiegeln den Plan „High Performance“ ein, ohne Bedingung) |
| Configure Citrix Workspace Environment Agent (WEM) | https://eucweb.com/docs/bisf-7-1912/gpo-configuration/citrix/configure-citrix-workspace-environment-agent-wem | Dokumentation 7.1912 | 2026-11-13 | `vda.wemCache` (im Text: BIS-F bietet an, den Cache des WEM-Agenten auf den beständigen Datenträger zu legen; für MCS setzt das einen VDA ab 1903 mit MCSIO voraus) |

### Quellen aus der Praxis: carlstalhood.com

Anleitungen von Carl Stalhood. Die Seiten decken Citrix Virtual Apps and Desktops bis 2411 ab; die Seite zu den
Gruppenrichtlinien ist älter und nennt Windows Server 2022 nur am Rand.

| Titel | Adresse | Stand der Seite | Abruf | Prüfungen |
|---|---|---|---|---|
| Citrix Virtual Delivery Agent (VDA) 2411 | https://www.carlstalhood.com/virtual-delivery-agent-vda-cr/ | 2024-12-04 | 2026-11-13 | `size.workerCpu`, `size.workerCpuMax` (8 vCPU für Sitzungshosts mit Windows Server 2022, 2019 oder 2016), `size.workerMemory` (24 bis 48 GB; mit einem Schreibcache im Arbeitsspeicher mehr) |
| Citrix Health Check | https://www.carlstalhood.com/citrix-health-check/ | 2024-02-28 | 2026-11-13 | `size.commitAboveRam` (Arbeitsspeicher der virtuellen Maschine mindestens so groß wie der zugesagte Speicher), `operation.uptime` (Sitzungshosts regelmäßig neu starten; die Seite nennt keine Zahl, die Schwelle ist ein Vorschlag des Katalogs), `operation.updateAge` (letzte Installation eines Updates höchstens 60 Tage alt), `operation.powerPlan` („Power management is set to High Performance with no sleep timers“) |
| Group Policy Computer Settings for VDAs | https://www.carlstalhood.com/group-policy-objects-vda-computer-settings/ | 2023-11-03 | 2026-11-13 | `sessions.disconnectLimit`, `sessions.idleLimit` (Zeitlimits per Gruppenrichtlinie, „3 hours or similar“: eine Größenordnung, keine Schwelle; die Prüfliste „Citrix Health Check“ nennt die Zeitlimits ebenfalls) |

Nicht übernommen aus diesen Seiten, weil die Gegenprüfung es nicht trägt: beim zugesagten Speicher der Höchststand
seit dem Start und eine Mindestlaufzeit (stehen nicht auf der Seite); bei den Zeitlimits die Aussage, sie gehörten
nur in die Gruppenrichtlinie von Microsoft (neuere Seiten von Stalhood nennen den Zeitgeber der Citrix-Richtlinie als
gleichwertigen Weg); beim Energiesparplan die Zeitgeber für Schlaf und Ruhezustand (das Zustandsbild liest sie nicht).

### Weitere Praxisquellen als zweite Quelle

Der Katalog führt je Prüfung eine Quelle im Feld `source`. Wo eine weitere Praxisquelle dieselbe Prüfung stützt,
steht ihre Aussage im Text der Prüfung, mit dem Namen der Quelle und, bei einer Messung, mit deren Bedingungen. Die
Art der Prüfung ändert sich dadurch nicht. Abruf aller Seiten: 2026-11-13.

- `size.workerCpu`, `size.workerCpuMax` – auch gestützt durch: GO-EUC, „Impact of sizing RDSH VMs“, https://www.go-euc.com/impact-of-sizing-rdsh-vms/, 2019-02-27. Lasttest von 2019 mit Windows Server 2016 unter ESXi 6.7 U1 auf zwei Xeon E5-2680 v4, Schutzmaßnahmen gegen Spectre und Meltdown abgeschaltet; die genauen Zahlen sind für heutige Prozessoren nicht belegt. Die Empfehlung „höchstens 8 vCPU je Maschine“ und die Regel zur Summe der vCPU eines Hosts sind Rat der Autoren, kein Messwert.
- `size.pagefilePresent` – auch gestützt durch: GO-EUC, „Page file sizing for virtualized environments“, https://www.go-euc.com/page-file-sizing-for-virtualized-environments/, 2019-12-03. Test von 2019 mit Windows 10 1803 (eine Sitzung je Maschine), 2 vCPU und 4 GB, MCS 1906.1; übernommen ist nur die Beobachtung, dass die Maschinen ohne Auslagerungsdatei unter Speicherdruck abstürzten. Der Rat zur Größe der Datei ist nicht übernommen.
- `operation.pendingRestart` – auch gestützt durch: Guy Leech, „Reasons for Reboots – Part 1“, https://guyrleech.wordpress.com/2014/06/24/reasons-for-reboots-part-1/, 2014-06-24. Aus der Zeit von Windows 7 und Windows Server 2008 R2; steht nur im Vorschlag zum Vorgehen (im Abbild nach jeder Installation prüfen). Der Mechanismus selbst ist der von Microsoft dokumentierte.
- `operation.diskFree` – auch gestützt durch: Thomas Kötzing, „Citrix Maschinenerstellungsdienste (MCS) – Skript zum Auslesen des RAM- und Disk-Cache“, https://koetzingit.de/blog/2024/03/18/citrix-maschinenerstellungsdienste-mcs-skript-zum-auslesen-des-ram-und-disk-cache/, 2024-03-18. Gilt nur, wo MCS mit Speicheroptimierung eingerichtet ist; der Text der Prüfung sagt das.
- `sessions.disconnectLimit` – auch gestützt durch: James Rankin, „Windows session timeouts on Citrix – a brief guide“, https://james-rankin.com/articles/windows-session-timeouts-on-citrix-a-brief-guide/, 2023-03-08 (Richtlinie statt Benutzerobjekt; zwei Stunden als sein Beispiel für einfache Benutzer); James Kindon, „Citrix Session Management Policies“, https://jkindon.com/citrix-session-management-policies/, 2021-08-09 (die Werte am Benutzerobjekt greifen nur, wo nichts anderes gesetzt ist); Guy Leech, „The Taming of the Print Server“, https://guyrleech.wordpress.com/2016/02/23/the-taming-of-the-print-server/, 2016-02-23 (nur als Beispiel: ein Druckserver, kein Sitzungshost).
- `sessions.idleLimit` – auch gestützt durch: James Rankin, „Windows session timeouts on Citrix – a brief guide“, https://james-rankin.com/articles/windows-session-timeouts-on-citrix-a-brief-guide/, 2023-03-08; James Kindon, „Citrix Session Management Policies“, https://jkindon.com/citrix-session-management-policies/, 2021-08-09. Das Beispiel von Guy Leech ist hier nicht verwendet: Es handelt von getrennten Sitzungen.
- `sessions.tempProfiles` – auch gestützt durch: Thomas Kötzing, „Powershell-Skript zum Löschen von temporären Benutzerprofilen“, https://koetzingit.de/blog/2024/09/10/powershell-skript-zum-loeschen-von-temporaeren-benutzerprofilen/, 2024-09-10. Gezeigt mit FSLogix; die Profilliste gehört zu Windows. Das Löschen von Einträgen auf dem laufenden Server ist nicht als Abhilfe übernommen.
- `vda.wemCache` – auch gestützt durch: Manuel Winkel, „Finding in the Wild | Sometimes Old Citrix Problems Simply Return“, https://www.deyda.net/index.php/en/2026/09/26/finding-in-the-wild-sometimes-old-citrix-problems-simply-return/, 2026-09-26 (eigene Beobachtung mit WEM 2507 CU1 auf nicht persistenten VDAs, keine öffentliche Fehlernummer von Citrix); James Kindon, „The why does it of Citrix WEM Cache“, https://jkindon.com/the-why-does-it-of-citrix-wem-cache/, 2020-10-15 (nur als Vorgeschichte: gilt für Agenten vor Version 2012).
- `profile.containerFull` – auch gestützt durch: Aaron Parker, „A Practical Guide to FSLogix Containers Capacity Planning and Maintenance“, https://stealthpuppy.com/fslogix-containers-capacity/, 2019-04-23. Geschrieben für FSLogix; übernommen sind nur die Folge eines vollen Containers und der Rat, die Größe nicht knapper zu begrenzen als nötig. Keine Zahl des Katalogs stammt von dort.
- `profile.containersPerUser` – auch gestützt durch: Aaron Parker, „A Practical Guide to FSLogix Containers Capacity Planning and Maintenance“, https://stealthpuppy.com/fslogix-containers-capacity/, 2019-04-23 (zusätzlicher Speicherplatz bei gleichzeitigen Sitzungen; für FSLogix); James Rankin, „QuickPost – getting started with Citrix UPM Containers“, https://james-rankin.com/articles/quickpost-getting-started-with-citrix-upm-containers/, 2023-09-08 (die Citrix Profilverwaltung schreibt einen Differenzdatenträger und führt ihn bei der Abmeldung zurück).

### Ausnahmen: Praxisquelle vor Hersteller

Der Katalog führt die Ausnahmen im Teil `precedence`. Festgelegt ist eine.

**Energiesparplan (`operation.powerPlan`).** Die Prüfung meldet „prüfen“, wenn der aktive Plan nicht „Höchstleistung“
ist. Begründung des Auftraggebers (13.11.2026): Die Praxisquellen beziehen sich ausdrücklich auf
Citrix-Terminalserver und Betriebserfahrung, die Herstellerdokumentation nicht.

- Praxisquellen: Carl Stalhood, „Citrix Health Check“ (oben); BIS-F stellt beim Versiegeln denselben Plan ein (oben).
- Microsoft, „Overview about power and performance tuning for the Windows Server“,
  https://learn.microsoft.com/en-us/windows-server/administration/performance-tuning/hardware/power/power-performance-tuning
  (Abruf 2026-11-13): „Balanced (recommended)“ ist die Vorgabe; „High Performance“ nennt die Seite für Anwendungen,
  die auf Verzögerungen empfindlich reagieren. Der Katalog nennt das im Text der Prüfung.
- VMware, „Poor network performance or high network latency on Windows virtual machines“,
  https://knowledge.broadcom.com/external/article/310350 (Abruf 2026-11-13): „High performance“ für die Zeit, in der
  Leistungsprobleme untersucht werden. Der Artikel begründet das mit Beobachtungen unter älteren Windows-Versionen.
- Andere Sicht aus der Praxis: GO-EUC, „Beyond Balanced: Benchmarking Windows 11 Power Plans“,
  https://www.go-euc.com/beyond-balanced-benchmarking-windows-11-power-plans/, 2026-09-15: nur ein geringer
  Unterschied zwischen „Balanced“ und „High performance“, für Benutzer kein spürbarer. Gemessen mit Windows 11 und
  einer Sitzung je Maschine auf Azure, Defender abgeschaltet; die Leerlaufzustände der Prozessoren waren nicht Teil
  der Messung. Der Katalog nennt die Messung mit diesen Bedingungen; sie ändert weder Regel noch Einstufung.

### Herstellerquellen

| Hersteller | Titel | Adresse | Stand der Seite | Abruf | Prüfungen |
|---|---|---|---|---|---|
| Microsoft | How to determine the appropriate page file size for 64-bit versions of Windows | https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/how-to-determine-the-appropriate-page-file-size-for-64-bit-versions-of-windows | 2026-02-12 | 2026-11-13 | `size.pagefilePresent` (`vendor`); als Beleg der Faustregeln `size.commitHeadroom` (Zusagegrenze = Arbeitsspeicher und alle Auslagerungsdateien) und `operation.diskFree` (eine vom System verwaltete Auslagerungsdatei wächst nur, solange Platz frei ist) |
| Microsoft | Microsoft Edge for Virtual desktop infrastructure (VDI) | https://learn.microsoft.com/en-us/deployedge/edge-for-virtualized-desktop-infrastructure | 2026-11-03 | 2026-11-13 | als Beleg der Faustregel `size.memoryPerSession` (1 GB Arbeitsspeicher je Benutzer für Microsoft Edge; die Seite sagt „VDI“ und nennt Multi-Session-Server nicht eigens) |
| Microsoft | Performance Tuning Remote Desktop Session Hosts | https://learn.microsoft.com/en-us/windows-server/administration/performance-tuning/role/remote-desktop/session-hosts | 2020-09-14 | 2026-11-13 | als Beleg der Faustregel `size.cpuPerSession` (Rechenleistung je Sitzung mal Zahl der Sitzungen plus Reserve; keine Zahl) |
| Microsoft | MoveFileExA function (winbase.h) | https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-movefileexa | 2023-06-01 | 2026-11-13 | als Beleg der Faustregel `operation.pendingRestart` (der Wert `PendingFileRenameOperations`) |
| VMware | VMware Tools Lifecycle Management | https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/tools/13-0-0/vmware-tools-administration/introduction-to-vmware-tools/vmware-tools-lifecyle-management.html | 2026-05-08 | 2026-11-13 | `size.vmTools` |
| VMware | Solutions for Memory Performance Problems | https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/vsphere-monitoring-and-performance/monitoring-inventory-objects/troubleshoot-and-enhance-performance/memory-performance-solutions.html | 2026-10-28 | 2026-11-13 | `size.balloonDriver` |
| VMware | Poor network performance or high network latency on Windows virtual machines | https://knowledge.broadcom.com/external/article/310350 | 2025-07-21 | 2026-11-13 | `size.netAdapterType` (der Artikel setzt VMXNET3 voraus, bevor weiter gesucht wird; eine allgemeine Pflicht nennt er nicht; die Seite „Citrix Virtual Delivery Agent (VDA) 2411“ von Carl Stalhood nennt für vSphere ebenfalls VMXNET3) |
| VMware | SCSI, SATA, and NVMe Storage Controller Conditions, Limitations, and Compatibility | https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/vsphere-virtual-machine-administration/configuring-virtual-machine-hardware/scsi-controller-configuration.html | 2026-10-28 | 2026-11-13 | `size.storageController` (nur ein Hinweis: VMware knüpft den Vorteil an E/A-starke Last) |
| Citrix | VDA registration | https://docs.citrix.com/en-us/citrix-virtual-apps-desktops/2203-ltsr/manage-deployment/vda-registration.html | 2026-11-12 | 2026-11-13 | `vda.controllerCount`, `vda.controllerNotFqdn`, `vda.listOfSids` |
| Citrix | WEM health check tool | https://docs.citrix.com/us/en/workspace-environment-management/current-release/reference/wem-health-check-tool.html | 2026-11-12 | 2026-11-13 | `vda.wemServices` |
| Citrix | Agent (install and configure) | https://docs.citrix.com/us/en/workspace-environment-management/current-release/install-and-configure/agent-host.html | 2026-11-12 | 2026-11-13 | `vda.wemCache` (Abschnitt „Prerequisites“), `vda.wemGpTimeout` (Abschnitt „System settings“) |
| Citrix | Profile Management policy descriptions and defaults | https://docs.citrix.com/en-us/profile-management/current-release/settings/descriptions-and-defaults.html | 2026-10-29 | 2026-11-13 | als Beleg der Faustregel `profile.containerFull` (90 % ist die Vorgabe für die Belegung, ab der ein Container automatisch vergrößert wird; keine Empfehlung im engen Sinn) |

Weitere Seiten der Hersteller, auf die sich einzelne Sätze der Texte stützen (Abruf 2026-11-13):

- Citrix, „What's new“ (Workspace Environment Management service),
  https://docs.citrix.com/us/en/workspace-environment-management/service/whats-new.html: Der Agent des WEM-Dienstes
  findet den beständigen Ort für seinen Cache ab Version 2408.1.0.1 selbst (`vda.wemCache`). Die Seiten für eigene
  WEM-Server enthalten diese Aussage nicht.
- Citrix, „Session limits policy settings“,
  https://docs.citrix.com/en-us/citrix-virtual-apps-desktops/2203-ltsr/policies/reference/ica-policy-settings/session-limits-policy-settings.html:
  Citrix empfiehlt, die Zeitgeber nur auf einem der beiden Wege zu setzen (`sessions.disconnectLimit`,
  `sessions.idleLimit`, im Vorschlag zum Vorgehen).
- Citrix, „Set up profile containers“,
  https://docs.citrix.com/us/en/profile-management/current-release/configure/citrix-profile-management-profile-container.html:
  Mit einem Container für das ganze Profil gilt „Delete locally cached profiles on logoff“ nicht mehr
  (`sessions.unloadedProfiles`, im Vorschlag zum Vorgehen; die Empfehlung der Einstellung für Terminalserver steht auf
  der Seite „Profile Management policy descriptions and defaults“).
- Citrix, „Agent (install and configure)“ (Tabelle oben), Abschnitt „Recommendations“: Die Dienste des WEM-Agenten
  nicht per Skript beenden oder neu starten (`vda.wemServices`, im Vorschlag zum Vorgehen). Dieselbe Seite
  beschreibt, dass der Agent auf bereitgestellten Maschinen die Cache-Dateien aus dem Abbild verwirft (`vda.wemCache`).
- Microsoft, „Performance Tuning Remote Desktop Session Hosts“ (Tabelle oben): Eine zu kleine Auslagerungsdatei
  lässt Speicheranforderungen von Programmen und Systemteilen scheitern (`size.commitHeadroom`).
- VMware, „VMware Tools Device Drivers“,
  https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/tools/13-0-0/vmware-tools-administration/introduction-to-vmware-tools/vmware-tools-device-drivers.html:
  Der Treiber zur Speichersteuerung ist für das Ballooning nötig und unter vSphere empfohlen (`size.balloonDriver`);
  die Treiber für VMXNET3 verbessern die Netzleistung (`size.netAdapterType`).
- VMware, „Add a Paravirtualized SCSI Adapter“,
  https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/vsphere-virtual-machine-administration/configuring-virtual-machine-hardware/scsi-controller-configuration/add-a-paravirtualized-scsi-adapter-in-the-nextgen-client.html:
  Der paravirtuelle SCSI-Adapter passt am besten zu E/A-starken Anwendungen, besonders in SAN-Umgebungen
  (`size.storageController`).
- VMware, „Configuring disks to use VMware Paravirtual SCSI (PVSCSI) controllers“,
  https://knowledge.broadcom.com/external/article/313507: Ein Wechsel des Adapters am Startlaufwerk ohne den Treiber
  lässt Windows nicht mehr starten (`size.storageController`, im Vorschlag zum Vorgehen).

### Faustregeln

Eine Faustregel ist eine Prüfung, für die es weder eine Empfehlung des Herstellers noch eine aus der Praxis gibt.
Ihre Schwellen sind Vorschläge des Katalogs. Wo ein Dokument des Herstellers den Zusammenhang beschreibt, nennt die
Prüfung dieses Dokument als Beleg (Tabelle „Herstellerquellen“). Die übrigen tragen die Quelle
„WorkerPerf: Erfahrungswert des Katalogs ohne Herstellerdokument“ (Stand 2026-11-13): `sessions.disconnectedOld`,
`sessions.unloadedProfiles`, `sessions.tempProfiles`, `vda.services`, `profile.containersPerUser`,
`profile.serviceStopped`.

### Schwellen

Die Schwellen der fünf Bereiche mit ihrer Herkunft. Eine Schwelle lässt sich im Katalog ändern; der Bericht nennt im
Kopf jede Abweichung vom ausgelieferten Wert.

| Schwelle | Wert | Verwendet von | Herkunft der Zahl |
|---|---|---|---|
| `commitPeakPct` | 90 % | `size.commitHeadroom` | Vorschlag des Katalogs |
| `commitNowPct` | 98 % | `size.commitHeadroom` | Vorschlag des Katalogs |
| `memPerSessionMB` | 1024 MB | `size.memoryPerSession` | Vorschlag des Katalogs; Microsoft nennt für Edge 1 GB je Benutzer |
| `sessionsPerCpu` | 8 Sitzungen | `size.cpuPerSession` | Vorschlag des Katalogs |
| `workerCpuMin` | 8 Prozessoren | `size.workerCpu` | Carl Stalhood (Praxisquelle) |
| `workerCpuMax` | 8 Prozessoren | `size.workerCpuMax` | Carl Stalhood, GO-EUC (Praxisquellen) |
| `workerMemMinMB` | 24576 MB | `size.workerMemory` | Carl Stalhood (Praxisquelle) |
| `uptimeDays` | 30 Tage | `operation.uptime` | Vorschlag des Katalogs |
| `updateAgeDays` | 60 Tage | `operation.updateAge` | Carl Stalhood (Praxisquelle) |
| `diskFreeGB` | 10 GB | `operation.diskFree` | Vorschlag des Katalogs |
| `diskFreeHardGB` | 2 GB | `operation.diskFree` | Vorschlag des Katalogs |
| `disconnectedHours` | 24 Stunden | `sessions.disconnectedOld` | Vorschlag des Katalogs |
| `unloadedProfiles` | 20 Profile | `sessions.unloadedProfiles` | Vorschlag des Katalogs |
| `containerUsedPct` | 90 % | `profile.containerFull` | Citrix: Vorgabe für die automatische Vergrößerung |
| `containerUsedHardPct` | 95 % | `profile.containerFull` | Vorschlag des Katalogs |
| `containersPerUser` | 3 Container | `profile.containersPerUser` | Vorschlag des Katalogs |
| `workStartHour`, `workEndHour` | 7 und 18 Uhr | Arbeitszeit (Bereich Wartung in der Arbeitszeit) | Vorschlag des Katalogs |

Feste Zahlen in Regeln, die aus dem Dokument des Herstellers stammen und deshalb keine Schwellen sind: 12
(Hauptversion der VMware Tools), 30 (Wartezeit der Gruppenrichtlinie auf das Netz in Sekunden).
