# Quellen der Druckempfehlungen

Der Katalog `src/guidance.de.json` enthält Empfehlungen zum Drucken auf Citrix- und Terminalservern: die Elemente der
Situation `print` und in anderen Situationen die Elemente mit einer Bedingung `pattern.printdriver` oder `driver.*`.
Jedes dieser Elemente nennt im Feld `source` den Hersteller und den Titel des Dokuments, aus dem es stammt; der
Bericht zeigt die Quelle beim Element. Diese Datei weist je Hersteller nach, welches Dokument welches Element stützt,
und nennt die Empfehlungen, die gefunden, aber nicht aufgenommen wurden, mit dem Grund.

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
eines Vorschlags zutrifft, entscheidet, wer den Bericht liest. Namen von Richtlinien und Einstellungen stehen im
Katalog englisch, wie die Quelle sie nennt; die deutschen Bezeichnungen der Oberflächen sind nicht aus einer Quelle
belegt.

Wer ein Element des Katalogs ändert, verschiebt oder ergänzt, passt diese Datei an: Der Test
`tests/GuidanceCatalogue.Tests.ps1` prüft, dass jedes Element mit Quelle hier an seiner Stelle unter seinem Dokument
steht und dass hier keine Stelle steht, die der Katalog nicht hat.

## Microsoft

Microsoft dokumentiert nichts Eigenes zum Citrix-Universaltreiber, zum Citrix Universal Print Server oder zur Treiberzuordnung von Citrix und trifft keine Aussage, ob Treiber der Bauart Typ 3 oder Typ 4 auf Terminalservern stabiler sind. Kein Element hängt deshalb an der Bedingung `driver.vendor.Microsoft`.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| Policy CSP - ADMX_Printing | <https://learn.microsoft.com/windows/client-management/mdm/policy-csp-admx-printing> | 2026-11-13 | `crash.checks[4]` Richtlinie zur Isolierung der Treiber von Anwendungen<br>`print.checks[3]` Wirkung der Isolierung bei isoliertem Treiber<br>`print.checks[4]` Richtlinie zur Treiberisolierung nicht abgeschaltet<br>`print.remedies[2]` Isolierung per Richtlinie für alle Treiber erzwingen | Die Seite nennt als Betriebssysteme Windows 10 und 11, nicht Windows Server 2022. Die Richtlinien zur Treiberisolierung gelten laut Seite nur für Treiber, die die Druckwarteschlange lädt; „Isolate print drivers from applications“ wirkt nur bei Anwendungen, die die Isolierung unterstützen, und erst nach deren Neustart. Datenwerte der Registrierung nennt die Seite nicht. |
| Printer driver isolation | <https://learn.microsoft.com/windows-hardware/drivers/print/printer-driver-isolation> | 2026-11-13 | `print.checks[2]` Isolierung des beteiligten Treibers ansehen<br>`print.remedies[1]` fehlerhaften Treiber isoliert betreiben | Dokumentation für Treiberentwickler. Sie sagt, dass sich der Modus in der Druckverwaltung je Treiber einstellen lässt, nennt die Stelle dort aber nicht genauer und spricht nicht von Typ 3 oder Typ 4. |
| Troubleshooting scenarios for printing | <https://learn.microsoft.com/troubleshoot/windows-server/printing/troubleshoot-printing-scenarios> | 2026-11-13 | `print.checks[1]` Treiber oder Warteschlange als Auslöser feststellen<br>`print.checks[10]` Spool-Ordner und Dienstabhängigkeit nach Absturz<br>`print.checks[14]` hängende Aufträge auf Treiber oder Warteschlange eingrenzen<br>`print.checks[21]` ohne gemessene Treiberliste von Hand eingrenzen<br>`print.checks[22]` bei nicht geprüftem Muster von Hand eingrenzen<br>`print.checks[23]` Druckproblem vor der Messung: Wiederkehr prüfen<br>`print.remedies[12]` Treiber aktualisieren oder generischen Treiber verwenden | Microsoft beschreibt die Schritte zu fehlgeschlagenen Aufträgen „auf dem Clientcomputer“. Die Elemente für nicht gemessene Treiber, nicht geprüfte Muster und Vorfälle vor der Messung wenden denselben Schritt (Treiber oder Druckwarteschlange eingrenzen) auf diese Fälle an. |
| Troubleshoot printing issues caused by Print Spooler service not running | <https://learn.microsoft.com/troubleshoot/windows-server/printing/print-spooler-service-not-running> | 2026-11-13 | `print.checks[5]` Treiber und Druckkomponenten aktuell<br>`print.remedies[11]` Spool-Ordner vom Scan ausnehmen | Die Seite sagt „Create exclusions for the spool folder“; Dateiendungen nennt sie dabei nicht. |

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
| Best practices | <https://docs.citrix.com/us/en/citrix-virtual-apps-desktops/current-release/printing/troubleshooting/best-practices.html> | 2026-11-13 | `crash.remedies[3]` Treiber sauber erneuern statt überinstallieren<br>`print.remedies[4]` Universaltreiber als Hauptstrategie, ungenutzte Treiber entfernen<br>`print.remedies[6]` Treiber sauber erneuern statt überinstallieren<br>`print.remedies[13]` alte und hängende Aufträge regelmäßig löschen | Aktuelle Fassung der Produktdokumentation. |
| Troubleshooting | <https://docs.citrix.com/us/en/citrix-virtual-apps-desktops/current-release/printing/troubleshooting.html> | 2026-11-13 | `print.checks[0]` fehlerhaftes Modul dem Treiber zuordnen<br>`print.checks[24]` Citrix Print Manager Service läuft<br>`print.remedies[0]` Treiber entfernen, mit Universaltreiber oder Microsoft-Treiber testen<br>`print.remedies[10]` Druckwarteschlange von Hand leeren | Die Zuordnung des fehlerhaften Moduls zu einem Treiber stammt aus der Messung; die Seite sagt nur, dass das Modul festzustellen ist. Das Leeren der Druckwarteschlange von Hand nennt sie nur für Abstürze der Druckwarteschlange. |
| Maintain the printing environment | <https://docs.citrix.com/us/en/citrix-virtual-apps-desktops/2503/printing/printing-maintain-environment.html> | 2026-11-13 | `crash.remedies[2]` Treiber über die Treiberzuordnung ersetzen oder sperren<br>`print.remedies[5]` Treiber über die Treiberzuordnung ersetzen oder sperren | Seite der Version 2503. |
| Best practices, security considerations, and default operations | <https://docs.citrix.com/us/en/citrix-virtual-apps-desktops/2503/printing/printing-best-practices.html> | 2026-11-13 | `crash.contacts[0]` Hersteller nach der Zertifizierung für Terminalserver fragen<br>`print.contacts[0]` Hersteller nach der Zertifizierung für Terminalserver fragen | Seite der Version 2503; sie verwendet noch die Bezeichnung „Terminal Services“. |
| Drivers policy settings | <https://docs.citrix.com/us/en/citrix-virtual-apps-desktops/current-release/policies/reference/ica-policy-settings/printing-policy-settings/drivers-policy-settings.html> | 2026-11-13 | `print.checks[12]` Richtlinie zur Verwendung des Universaltreibers | Aktuelle Fassung der Produktdokumentation. |
| Network Printers (on the VDA) | <https://docs.citrix.com/us/en/citrix-virtual-apps-desktops/current-release/printing/configuration/network-printers.html> | 2026-11-13 | `print.checks[13]` Herkunft der Drucker (Windows-Druckserver oder Universal Print Server) | Aktuelle Fassung der Produktdokumentation. |

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
| HP Print and Scan Devices Supported in Citrix Virtual Apps and Virtual Desktops Environments | <https://kaas.hpcloud.hp.com/pdf-public/pdf_6290906_en-US-1.pdf> | 2026-11-13 | `print.remedies[3]` HP-Treiber der Version 4.x ersetzen<br>`print.remedies[8]` hostbasierte HP-Treiber nicht auf dem Server<br>`print.remedies[15]` HP Universal Print Driver im Traditional Mode | Technical white paper, Rev. 39, Juni 2023; enthält viel Altbestand (XenApp, 32-Bit-Pfade). Zur Treiberversion 4.x ist nur die Empfehlung zum Ersetzen übernommen. |
| System Administrator's Guide For the HP V3 Universal Print Driver (PCL 6/PS) and the HP Print Administrator's Resource Kit (PARK) | <https://kaas.hpcloud.hp.com/pdf-public/pdf_8951296_en-US-1.pdf> | 2026-11-13 | `print.checks[15]` SNMP-Einstellungen und WSD-Anschluss bei HP<br>`print.checks[17]` Eingrenzung nach HP (zugeordneter Treiber, außerhalb der Sitzung, neue Warteschlange)<br>`print.remedies[7]` Treiberwahl nach Endgerät (Citrix-Universaltreiber oder HP Universal Print Driver)<br>`print.remedies[9]` Reihenfolge beim Entfernen des HP Universal Print Driver<br>`print.contacts[1]` Angaben für den Support von HP | Edition 11, Mai 2026. Die Reihenfolge beim Entfernen beschreibt HP für den HP Universal Print Driver. |
| HP Universal Print Driver Release Notes | <https://kaas.hpcloud.hp.com/pdf-public/pdf_8592592_en-US-1.pdf> | 2026-11-13 | `crash.checks[5]` Version des HP Universal Print Driver mit den Versionshinweisen vergleichen<br>`print.checks[6]` Version des HP Universal Print Driver mit den Versionshinweisen vergleichen | Edition 19, Juni 2026 (HP UPD 8.2.0). |
| HP Smart Universal Printing Driver - User Guide | <https://kaas.hpcloud.hp.com/pdf-public/pdf_1263018_en-US-1.pdf> | 2026-11-13 | `print.checks[18]` HP-Treiber Typ 4 auf verbundenen Rechnern vorab bereitgestellt | Edition 11.0, Februar 2025. |

### Belegstellen

- **HP Print and Scan Devices Supported in Citrix Virtual Apps and Virtual Desktops Environments**
  - „Installing the HP UPD in Dynamic Mode on the Citrix server is not supported. This is due to a design limitation in the Windows operating system which limits a print queue to be assigned to one port at a time, so multiple users would compete for the single port bound to the HP UPD queue if installed in Dynamic Mode.“
  - „Version 4.x.x.x print drivers have an issue unloading hpbmini.dll, which will probably cause a spooler crash when the server has a heavy load of connected users. [...] For HP print driver version 4.x.x.x, HP strongly recommends upgrading to the 60.x.x.x or 61.x.x.x driver versions available on www.hp.com. If one is not available, then use the HP UPD.“
  - „HP does not recommend installing host-based LaserJet drivers on the Citrix server. However, the devices might function by using the Citrix UPD on the Citrix server the HP host-based driver installed on the client.“
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
- **HP Smart Universal Printing Driver - User Guide**
  - „Version 4 drivers are not downloaded from the print server. You must prestage the driver on the client, or use the Microsoft-enhanced Point and Print driver.“

### Nicht aufgenommen

| Empfehlung | Grund |
|---|---|
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

Nicht erreichbar: h10032.www1.hp.com, h20331.www2.hp.com und h20195.www2.hp.com sowie die Dokumentseiten auf support.hp.com. Alle Dokumente oben stammen von kaas.hpcloud.hp.com.

## Kyocera

Kyocera veröffentlicht keine Aussage zu einer Citrix-Zertifizierung, zur Treiberisolierung oder zu Abstürzen der Druckwarteschlange durch seine Treiber. Alle Elemente dieses Abschnitts hängen an `driver.vendor.Kyocera`.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| KX DRIVER INSTALLER Release Notes (KYOCERA Document Solutions America, Inc.) | <https://www.kyoceradocumentsolutions.us/content/dam/download-center-americas-cf/us/drivers/drivers/KX_Driver_Read_Me_pdf.download.pdf> | 2026-11-13 | `crash.remedies[4]` KPDL- oder PCL-Uni-Treiber statt KX-Treiber<br>`print.checks[7]` vollständiger KX-Treiber auf dem Server<br>`print.remedies[16]` KPDL- oder PCL-Uni-Treiber statt KX-Treiber<br>`print.remedies[17]` KX-Treiber erst deinstallieren, dann neu installieren<br>`print.contacts[2]` Helpdesk von Kyocera bei Einsatz des KX-Treibers | Das Dokument trägt kein Datum. |
| Class leading performance with the KYOCERA V4 KX DRIVER. (data sheet) | <https://www.kyoceradocumentsolutions.us/content/dam/download-center-americas-cf/us/drivers/drivers/KYOCERA_V4_KX_Driver_Datasheet_pdf.download.pdf> | 2026-11-13 | `print.checks[19]` KX-Treiber Typ 3 und Typ 4 vergleichen (Typ 3 beteiligt)<br>`print.checks[20]` KX-Treiber Typ 3 und Typ 4 vergleichen (Typ 4 beteiligt) | Datenblatt von 2019. |
| Release Notes April 29, 2025 (DVD Contents) | <https://dam.kyoceradocumentsolutions.com/content/dam/gdam_dc/dc_global/document/manual/product_086/Readme_EN_202505.pdf> | 2026-11-13 | `print.remedies[18]` Kyocera-Treiber mit KmUninstall.exe entfernen | Die Seite nennt den Weg zum Deinstallationsprogramm, aber keinen weiteren Weg, verbliebene Treiber zu entfernen. |

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

Brother dokumentiert wenig, das sich auf Citrix oder Terminalserver bezieht, und nichts zu Typ 3 und Typ 4, zur Treiberisolierung oder zum Zusammenspiel mit dem Citrix-Universaltreiber. Alle Elemente dieses Abschnitts hängen an `driver.vendor.Brother`; die Seiten sind überwiegend für Arbeitsplatzrechner geschrieben, die Spalte „Hinweis“ sagt das je Seite.

| Titel | Adresse | Abruf | Übernommene Elemente | Hinweis |
|---|---|---|---|---|
| Citrix® Compatible Device List | <https://support.brother.com/g/b/oscontents.aspx?c=us_ot&lang=en&ossid=40> | 2026-11-13 | `crash.checks[6]` Modell in der Citrix-Liste von Brother nachschlagen<br>`print.checks[8]` Modell in der Citrix-Liste von Brother nachschlagen | Die Liste nennt Modelle mit dem Status „Available“, aber weder ein Citrix-Produkt noch eine Version. |
| What is a "Generic PCL Driver"? | <https://support.brother.com/g/b/faqend.aspx?c=us&faqid=faq00000324_000&lang=en&prod=hl8050n_all> | 2026-11-13 | `print.checks[9]` Generic-PCL-Treiber von Brother (Stand 2014) | Seite vom 26.08.2014 mit dem Vermerk „Model discontinued. This page is no longer updated.“; sie nennt Citrix MetaFrame, Windows Terminal Server, Windows NT 4.0 und Windows 2000. Im Katalog steht die Empfehlung deshalb nur mit diesem Vorbehalt und als Prüfschritt, nicht als Abhilfe. |
| "User Intervention Required" when attempting to print | <https://help.brother-usa.com/app/answers/detail/a_id/145904/~/user-intervention-required-when-attempting-to-print> | 2026-11-13 | `print.checks[11]` Dienst auf „Automatisch“ und gestartet | Die Seite nennt Windows XP bis Windows 10, nicht Windows Server. |
| I'm using Windows Vista, Windows 7, Windows 8 or Windows 10 and a network connected Brother machine. The following errors "Error - Sent to Printer", "Sent to Printer" or "Deleting - Printing" appear in the PC Print Queue. | <https://support.brother.com/g/b/faqend.aspx?c=us_ot&lang=en&prod=mfc6490cw_all&faqid=faq00002440_000> | 2026-11-13 | `print.checks[16]` stehende Aufträge an Brother-Geräten<br>`print.remedies[14]` Druckwarteschlange nach Brother zurücksetzen | Seite vom 14.02.2023; sie gilt für Windows Vista bis 10 und Geräte im Netz. Der Hinweis, dass die Aufträge aller Benutzer des Servers verloren gehen, stammt nicht von Brother. |
| Use the Universal Printer Driver for BR-Script. (PostScript language emulation) | <https://support.brother.com/g/b/faqend.aspx?c=ca&lang=en&prod=hl4570cdw_all&faqid=faq00002993_000> | 2026-11-13 | `print.remedies[19]` Brother Universal Printer Driver als gemeinsamer Treiber | Seite vom 29.03.2017. Die Liste der Betriebssysteme (help.brother-usa.com, Antwort 67181) endet bei Windows Server 2016; zu Terminalservern oder Citrix sagt die Seite nichts. |
| Uninstall the Brother Software and Drivers (Windows) | <https://support.brother.com/g/b/faqend.aspx?c=us_ot&lang=en&prod=hll2370dw_us&faqid=faq00000071_010> | 2026-11-13 | `print.remedies[20]` Brother-Treiber vollständig entfernen | Seite vom 02.04.2026; sie nennt Windows 7 bis 11. Das „Uninstall Tool“ gibt es laut Seite nicht für jedes Betriebssystem. |

### Belegstellen

- **Citrix® Compatible Device List**
  - „This information pertains to the compatibility status and operational verification under the environmental conditions set by Brother Industries, Ltd., and does not imply a comprehensive "guarantee of operation."“
- **What is a "Generic PCL Driver"?**
  - „For users of Citrix® MetaFrame®, Windows Terminal Server environments and other Windows NT 4.0® and Windows 2000 network shared environments, we recommend the use of our Brother Generic Drivers. These drivers can be used on any Brother monochrome laser printer/multi-function product that supports PCL5e or PCL6.“
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
| Bei „Receiving Data“ auf der Anzeige des Geräts: Originaltreiber von Brother und Anschlusstyp (WSD) prüfen | Quelle veraltet oder nur für ein anderes Produkt (gilt nur für Tintengeräte der Reihe MFC-J; das Merkmal ist die Anzeige am Gerät, die die Messung nicht erfasst) |
| Seite „Citrix Presentation Server (Citrix MetaFrame)“ mit dem Generic-PCL-Treiber | Quelle veraltet oder nur für ein anderes Produkt (die Seite ist zurückgezogen) |
| Entwicklerseiten „Printing in the Citrix Environment“ und „Compatibility with Citrix XenApp 7.6“ | Quelle veraltet oder nur für ein anderes Produkt (mobile Drucker auf XenApp 7.6 und Windows Server 2012 R2) |
| Kapitel zum Druckertreiber im Benutzerhandbuch des HL-2030 | Quelle veraltet oder nur für ein anderes Produkt (Handbuch für Windows 95 bis XP) |
| Drucken in einer Umgebung mit freigegebenen Druckern: Treiber des Client-Betriebssystems zuerst auf dem Server installieren | Quelle veraltet oder nur für ein anderes Produkt (für Etikettendrucker an einem Druckserver) |
| Statusmonitor von Brother ausblenden | keine Herstellerquelle gefunden (Brother sagt nichts zum Statusmonitor auf Terminalservern) |
| Erklärung zur Unterstützung von Universal Print | Quelle veraltet oder nur für ein anderes Produkt (betrifft den Cloud-Dienst von Microsoft) |
| Typ 3 und Typ 4, Treiberisolierung, Zusammenspiel mit dem Citrix-Universaltreiber | keine Herstellerquelle gefunden |

Nicht erreichbar: download.brother.com (unter anderem der „Universal Printer Driver Guide“); die Treiberlisten je Modell für Windows Server 2022 auf support.brother.com ließen sich nicht auslesen. Ob Brother einen Treiber für Windows Server 2022 anbietet, ist deshalb je Modell auf der Download-Seite zu prüfen.
