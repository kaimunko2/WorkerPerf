BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.EventConfig.ps1')
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Events.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Load.ps1')
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Findings.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Guidance.ps1')
    # the masking for the version without names of the copy texts (Hide-WorkerPerfReportText, New-WorkerPerfMask)
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Mask.ps1')
    function New-Inc([hashtable]$Over = @{}) {
        # every key of an incident entry with neutral values (2 minutes from 10 min after the capture start), overwritten by
        # the given ones; a given event gets every key of an event with neutral values first
        $inc = @{ id = 1; type = 'umfeld'; chronic = $false; severity = 2; start = [long](1e12 + 600000); end = [long](1e12 + 720000); durSec = 120.0
            lead = $null; resources = @(); text = ''; causeText = ''; focus = $false; nearReported = $false; scanActive = $false; events = @(); signals = @(); affected = @()
            main = $null; cause = $null; unverified = $false; contributors = @{}; delayProcs = @(); endpoints = @(); ica = @()
            security = @{ products = @(); totalPct = 0 }; companion = $null; chronicContext = @(); eventIncidents = @(); event = $null }
        foreach ($k in $Over.Keys) { $inc[$k] = $Over[$k] }
        if ($null -ne $inc.event) {
            $ev = @{ kind = ''; key = ''; group = ''; count = 0; eventsTruncated = $false; users = @(); sessions = @(); inSession = $false; sessionUnknown = $false
                noUserSession = $false; versions = @(); modules = @(); moduleEvents = 0; sameModule = $false; codes = @(); app = ''; service = ''; driver = ''
                printer = ''; source = ''; before = $false; patterns = @(); unchecked = @(); overlap = @(); companions = @() }
            foreach ($k in $inc.event.Keys) { $ev[$k] = $inc.event[$k] }
            $inc.event = $ev
        }
        $inc
    }
    function Get-Lines([string]$Text) { , @($Text -split "`r`n") }
    # a copy text with its line breaks and indents as single spaces (the unwrapped paragraphs, joined)
    function Join-Copy([string]$Text) { $Text -replace "`r`n\s*", ' ' }
    function New-Ctx {
        @{ Data = @{ apps = @(@{ i = 0; name = 'EXCEL.EXE'; role = '' }, @{ i = 1; name = 'MsMpEng.exe'; role = 'Sicherheit' }); sessions = @(); sollIst = @()
                unmeasured = @{ input = $false; worker = @() }; skipped = @()
                print = @{ drivers = @(@{ name = 'Sim PCL 6'; manufacturer = 'HP'; type = 3; isolation = 'none' }); queues = @(@{ name = 'Q1'; maxJobs = 3; jobErrors = 1; notReadyErrors = 0 }) }
                meta = @{ computer = 'SIM-VDA01'; offsetMin = 60; endReason = 'duration'; start = 1e12; end = 1e12 + 3600000 } }
            Thresholds = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json'); OffsetMinutes = 60; Texts = $script:Texts }
    }
    function New-Catalogue([scriptblock]$Change = {}) {
        # a complete small catalogue: every situation with one check, one remedy and one contact without condition
        $c = @{
            version      = '2026-11-11'
            terms        = @{ 'Working Set' = 'Arbeitsspeicher, den ein Programm gerade belegt.' }
            vendors      = @(@{ key = 'HP'; match = @('HP*', 'Hewlett*') }, @{ key = 'Kyocera'; match = @('Kyocera*') }, @{ key = 'Brother'; match = @('Brother*') },
                @{ key = 'Microsoft'; match = @('Microsoft*') }, @{ key = 'Citrix'; match = @('Citrix*') })
            userView     = @{ many = '{affected} Sitzungen waren betroffen.'; one = '{affected} Sitzung war betroffen.'; none = 'Niemand war betroffen.'; unknown = 'Unbekannt.'
                chronic = 'Dauerzustand.'; eventMany = 'Viele.'; eventOne = 'Einer.'; eventNone = 'Keiner.'; before = 'Vor der Messung.' }
            # the red and the yellow sentence are joined from parts; one that was not measured is left out (ruling P3-R49)
            lagebild     = @{ red = 'Rot: {parts}.'; yellow = 'Gelb: {parts}.'; green = 'Keine Störung erkannt.'; greenSkipped = 'Keine Störung erkannt; nicht erfasst: {skipped}.'
                partBottlenecks = '{bottlenecks} Engpaesse'; partDelays = '{delays} Verzoegerungen'; partEvents = '{events} Ereignisse'; partChronic = '{chronic} Dauerzustaende'
                partSeparator = ', '; notMeasured = 'Nicht gemessen: {skipped}.' }
            hints        = @{ unmeasured = 'Nicht gemessen: {signals}.'; skipped = 'Abgeschaltet: {skipped}.'; notFinished = 'Nicht beendet.'; error = 'Fehler: {message}'
                errorNoMessage = 'Fehler.'; stopped = 'Angehalten.' }
            # the placeholders of ruling P3-R26 only
            copy         = @{ head = 'WorkerPerf {server}, {date}'; summaryHead = 'WorkerPerf {server}, {date}, {from} bis {to}'; measure = 'Messwert: {value}, Soll {target}'
                cause = 'Verursacher:'; affected = 'Betroffen: {affected}'; checks = 'Empfohlene Pruefschritte:'; remedies = 'Moegliche Abhilfe (Vorschlag):'; contact = 'Ansprechpartner:'
                # a copy text carries the first steps only and says how many more the report has (ruling P3-R59)
                maxChecks = 5; maxRemedies = 3; moreChecks = 'Weitere {count} Pruefschritte im Bericht.'; moreCheck = 'Ein weiterer Pruefschritt im Bericht.'
                moreRemedies = 'Weitere {count} Vorschlaege im Bericht.'; moreRemedy = 'Ein weiterer Vorschlag im Bericht.' }
            fallbackNote = 'Keine spezifische Anleitung.'
            situations   = @{}
        }
        foreach ($s in $script:WorkerPerfSituations) {
            $c.situations[$s] = @{ title = "Titel $s"; meaning = 'Von {from} bis {to}.'; impact = 'Langsam.'; short = $s.ToUpperInvariant()
                checks = @(@{ text = 'Pruefen'; where = 'Ort'; sign = 'Merkmal'; source = 'Hersteller, Titel' })
                remedies = @(@{ text = 'Abhelfen'; precondition = 'Voraussetzung'; when = @(); source = 'Hersteller, Titel' })
                contacts = @(@{ text = 'Kontakt' }) }
        }
        $c.situations.cpu.short = 'CPU'
        $c.situations.print.contacts[0].source = 'Hersteller, Titel'
        . $Change
        $file = Join-Path $TestDrive ('guidance-' + [guid]::NewGuid().ToString('N') + '.json')
        [IO.File]::WriteAllText($file, ($c | ConvertTo-Json -Depth 10), [Text.Encoding]::UTF8)
        $file
    }
    $script:Cat = Read-WorkerPerfGuidance (New-Catalogue); $script:Texts = Read-WorkerPerfTexts (Join-Path $PSScriptRoot '../src/texts.de.json')
}
Describe 'Katalog laden und pruefen' {
    It 'liest einen vollstaendigen Katalog' { (Read-WorkerPerfGuidance (New-Catalogue)).situations.cpu.short | Should -Be 'CPU' }
    It 'nennt Eintrag und Feld eines Fehlers' -TestCases @(
        @{ Change = { $c.situations.cpu.Remove('impact') }; Msg = "*Eintrag 'cpu'*Feld 'impact'*" }
        @{ Change = { $c.situations.cpu.checks[0].when = @('cause.irgendwas') }; Msg = "*Eintrag 'cpu', checks``[0``]*Feld 'when'*cause.irgendwas*" }
        @{ Change = { $c.situations.disk.remedies[0].text = 'Laufwerk {laufwerk} pruefen' }; Msg = "*Eintrag 'disk', remedies``[0``]*Feld 'text'*{laufwerk}*" }
        @{ Change = { $c.situations.print.remedies[0].Remove('source') }; Msg = "*Eintrag 'print', remedies``[0``]*Feld 'source'*" }
        @{ Change = { $c.situations.crash.checks += @{ text = 't'; where = 'w'; sign = 's'; when = @('pattern.printdriver') } }; Msg = "*Eintrag 'crash', checks``[1``]*Feld 'source'*" }
        @{ Change = { $c.situations.Remove('hang') }; Msg = "*Eintrag 'hang'*fehlt*" }
        @{ Change = { $c.situations['cpu.neu'] = $c.situations.cpu }; Msg = "*Eintrag 'cpu.neu'*unbekannt*" }
        @{ Change = { $c.hints.Remove('skipped') }; Msg = "Katalog '*': Eintrag 'hints': Feld 'skipped' fehlt." }
        @{ Change = { $c.Remove('fallbackNote') }; Msg = "Katalog '*': Eintrag 'fallbackNote' fehlt." }
        @{ Change = { $c.lagebild.red = 'Rot wegen {farbe}' }; Msg = "*Eintrag 'lagebild': Feld 'red'*{farbe}*" }
        @{ Change = { $c.terms['Working Set'] = 'Belegt von {programm}' }; Msg = "*Eintrag 'terms': Feld 'Working Set'*{programm}*" }
        @{ Change = { $c.situations.memory.checks[0].when = @('cause.app') }; Msg = "*Eintrag 'memory': Feld 'checks'*ohne Bedingung*" }
        @{ Change = { $c.situations.share.contacts[0].when = @('driver.vendor.Acme') }; Msg = "*Eintrag 'share', contacts``[0``]*Feld 'when'*driver.vendor.Acme*" }
        # source on contacts (ruling P3-R13)
        @{ Change = { $c.situations.print.contacts += @{ text = 'Druckerbetreuung'; when = @('spooler.crash') } }; Msg = "*Eintrag 'print', contacts``[1``]*Feld 'source'*" }
        @{ Change = { $c.situations.print.contacts[0].Remove('source') }; Msg = "*Eintrag 'print', contacts``[0``]*Feld 'source'*" }
        @{ Change = { $c.situations.cpu.contacts += @{ text = 'Treiberbetreuung'; when = @('driver.v4') } }; Msg = "*Eintrag 'cpu', contacts``[1``]*Feld 'source'*" }
        # braces only as a placeholder (ruling P3-R14)
        @{ Change = { $c.situations.cpu.checks[0].text = 'Pruefen {{user}}' }; Msg = "*Eintrag 'cpu', checks``[0``]: Feld 'text' enthaelt eine geschweifte Klammer ohne Platzhalter*" }
        @{ Change = { $c.hints.error = 'Fehler { bei {message}' }; Msg = "*Eintrag 'hints': Feld 'error' enthaelt eine geschweifte Klammer ohne Platzhalter*" }
        @{ Change = { $c.copy.head = 'WorkerPerf {} {server}' }; Msg = "*Eintrag 'copy': Feld 'head' enthaelt eine geschweifte Klammer ohne Platzhalter*" }
        @{ Change = { $c.fallbackNote = 'Siehe }' }; Msg = "*Eintrag 'fallbackNote' enthaelt eine geschweifte Klammer ohne Platzhalter*" }
        # vendors: unique key (ordinal), non-empty match
        @{ Change = { $c.vendors += @{ key = 'HP'; match = @('Hewlett Packard*') } }; Msg = "*Eintrag 'vendors', vendors``[5``]: Feld 'key' ist doppelt*" }
        @{ Change = { $c.vendors[1].match = @() }; Msg = "*Eintrag 'vendors', vendors``[1``]: Feld 'match'*" }
        # source through a driver.* condition, not only pattern.printdriver
        @{ Change = { $c.situations.cpu.remedies += @{ text = 't'; precondition = 'p'; when = @('driver.v3') } }; Msg = "*Eintrag 'cpu', remedies``[1``]: Feld 'source' fehlt*" }
        @{ Change = { $c.situations.crash.checks += @{ text = 't'; where = 'w'; sign = 's'; when = @('driver.vendor.HP') } }; Msg = "*Eintrag 'crash', checks``[1``]: Feld 'source' fehlt*" }
        # unknown placeholders in the text parts
        @{ Change = { $c.userView.one = '{nutzer} war betroffen.' }; Msg = "*Eintrag 'userView': Feld 'one'*unbekannten Platzhalter '{nutzer}'*" }
        @{ Change = { $c.hints.stopped = 'Angehalten um {uhrzeit}.' }; Msg = "*Eintrag 'hints': Feld 'stopped'*unbekannten Platzhalter '{uhrzeit}'*" }
        @{ Change = { $c.copy.contact = 'Ansprechpartner: {person}' }; Msg = "*Eintrag 'copy': Feld 'contact'*unbekannten Platzhalter '{person}'*" }
        @{ Change = { $c.fallbackNote = 'Keine Anleitung fuer {situation}.' }; Msg = "*Eintrag 'fallbackNote'*unbekannten Platzhalter '{situation}'*" }
        @{ Change = { $c.terms['Handle'] = 'Verweis auf {objekt}' }; Msg = "*Eintrag 'terms': Feld 'Handle'*unbekannten Platzhalter '{objekt}'*" }
        # type checks
        @{ Change = { $c.situations.cpu.checks = @{ text = 'Pruefen'; where = 'Ort'; sign = 'Merkmal' } }; Msg = "*Eintrag 'cpu': Feld 'checks' ist keine Liste*" }
        @{ Change = { $c.situations.cpu.contacts = @{ text = 'Kontakt' } }; Msg = "*Eintrag 'cpu': Feld 'contacts' ist keine Liste*" }
        @{ Change = { $c.situations.cpu.checks[0].when = 'cause.app' }; Msg = "*Eintrag 'cpu', checks``[0``]: Feld 'when' ist keine Liste*" }
        @{ Change = { $c.situations.cpu.title = 5 }; Msg = "*Eintrag 'cpu': Feld 'title' ist kein Text*" }
        @{ Change = { $c.copy.head = $null }; Msg = "*Eintrag 'copy': Feld 'head' ist kein Text*" }
        @{ Change = { $c.situations.memory.remedies[0].precondition = 3 }; Msg = "*Eintrag 'memory', remedies``[0``]: Feld 'precondition' ist kein Text*" }
        @{ Change = { $c.situations.cpu = 'CPU' }; Msg = "*Eintrag 'cpu' ist kein Objekt*" }
        @{ Change = { $c.situations.cpu.checks = @() }; Msg = "*Eintrag 'cpu': Feld 'checks' braucht mindestens einen Pruefschritt ohne Bedingung*" }
        # a vendor pattern that is no valid wildcard pattern fails at loading, not at the first print incident
        @{ Change = { $c.vendors[1].match = @('Kyocera*', 'HP [') }; Msg = "Katalog '*': Eintrag 'vendors', vendors``[1``]: Feld 'match' enthaelt das ungueltige Muster 'HP ``['." }
        # title and short hold no placeholder; meaning and impact only values every incident has (ruling P3-R19)
        @{ Change = { $c.situations.disk.title = 'Laufwerk {resource} langsam' }; Msg = "Katalog '*': Eintrag 'disk': Feld 'title' darf keinen Platzhalter enthalten ('{resource}')." }
        @{ Change = { $c.situations.cpu.short = 'CPU {server}' }; Msg = "Katalog '*': Eintrag 'cpu': Feld 'short' darf keinen Platzhalter enthalten ('{server}')." }
        @{ Change = { $c.situations.crash.meaning = '{app} stuerzte ab.' }; Msg = "Katalog '*': Eintrag 'crash': Feld 'meaning' enthaelt den Platzhalter '{app}', den nicht jeder Vorfall hat." }
        @{ Change = { $c.situations.fallback.impact = 'Am {date} fuer {user} langsam.' }; Msg = "Katalog '*': Eintrag 'fallback': Feld 'impact' enthaelt den Platzhalter '{user}', den nicht jeder Vorfall hat." }
        # the fallback meaning starts with fallbackNote: the same rule (ruling P3-R19 extended)
        @{ Change = { $c.fallbackNote = 'Keine Anleitung fuer {app} am {date}.' }; Msg = "Katalog '*': Eintrag 'fallbackNote' enthaelt den Platzhalter '{app}', den nicht jeder Vorfall hat." }
        # other wordings of the impact (fix round 4, B2): a list of objects, each with a text like impact and at least one known condition
        @{ Change = { $c.situations.cpu.impactVariants = @{ when = @('scan'); text = 'Anders.' } }; Msg = "Katalog '*': Eintrag 'cpu': Feld 'impactVariants' ist keine Liste." }
        @{ Change = { $c.situations.cpu.impactVariants = @('Anders.', 'Noch anders.') }; Msg = "Katalog '*': Eintrag 'cpu', impactVariants``[0``] ist kein Objekt." }
        @{ Change = { $c.situations.cpu.impactVariants = @(@{ when = @('scan'); text = 'Anders.' }, @{ when = @('scan') }) }; Msg = "Katalog '*': Eintrag 'cpu', impactVariants``[1``]: Feld 'text' fehlt." }
        @{ Change = { $c.situations.cpu.impactVariants = @(@{ when = @('scan'); text = ' ' }, @{ when = @('scan'); text = 'x' }) }; Msg = "Katalog '*': Eintrag 'cpu', impactVariants``[0``]: Feld 'text' ist leer." }
        @{ Change = { $c.situations.cpu.impactVariants = @(@{ when = @('scan'); text = 5 }, @{ when = @('scan'); text = 'x' }) }; Msg = "Katalog '*': Eintrag 'cpu', impactVariants``[0``]: Feld 'text' ist kein Text." }
        @{ Change = { $c.situations.disk.impactVariants = @(@{ when = @('scan'); text = 'Langsam fuer {user}.' }, @{ when = @('scan'); text = 'x' }) }
            Msg = "Katalog '*': Eintrag 'disk', impactVariants``[0``]: Feld 'text' enthaelt den Platzhalter '{user}', den nicht jeder Vorfall hat." }
        @{ Change = { $c.situations.disk.impactVariants = @(@{ when = @('scan'); text = 'Langsam {heute}.' }, @{ when = @('scan'); text = 'x' }) }
            Msg = "Katalog '*': Eintrag 'disk', impactVariants``[0``]: Feld 'text' enthaelt den unbekannten Platzhalter '{heute}'." }
        @{ Change = { $c.situations.cpu.impactVariants = @(@{ text = 'Anders.' }, @{ when = @('scan'); text = 'x' }) }; Msg = "Katalog '*': Eintrag 'cpu', impactVariants``[0``]: Feld 'when' fehlt." }
        @{ Change = { $c.situations.cpu.impactVariants = @(@{ when = @(); text = 'Anders.' }, @{ when = @('scan'); text = 'x' }) }; Msg = "Katalog '*': Eintrag 'cpu', impactVariants``[0``]: Feld 'when' ist keine Liste mit Bedingungen." }
        @{ Change = { $c.situations.cpu.impactVariants = @(@{ when = 'scan'; text = 'Anders.' }, @{ when = @('scan'); text = 'x' }) }; Msg = "Katalog '*': Eintrag 'cpu', impactVariants``[0``]: Feld 'when' ist keine Liste mit Bedingungen." }
        @{ Change = { $c.situations.cpu.impactVariants = @(@{ when = @('scan', 'unmeasured.eingabe'); text = 'Anders.' }, @{ when = @('scan'); text = 'x' }) }
            Msg = "Katalog '*': Eintrag 'cpu', impactVariants``[0``]: Feld 'when' enthaelt die unbekannte Bedingung 'unmeasured.eingabe'." }
    ) { { Read-WorkerPerfGuidance (New-Catalogue $Change) } | Should -Throw $Msg }
    It 'erlaubt in Bedeutung und Wirkung die Werte, die jeder Vorfall hat' {
        $cat = Read-WorkerPerfGuidance (New-Catalogue { $c.situations.cpu.meaning = 'Am {date} von {from} bis {to} ({duration}) auf {server}.'; $c.situations.cpu.impact = '{server}: {duration} langsam.' })
        $cat.situations.cpu.impact | Should -Be '{server}: {duration} langsam.'
        (Read-WorkerPerfGuidance (New-Catalogue { $c.fallbackNote = 'Keine Anleitung ({from} bis {to}, {duration}) auf {server} am {date}.' })).fallbackNote |
            Should -Be 'Keine Anleitung ({from} bis {to}, {duration}) auf {server} am {date}.'
        $script:WorkerPerfGuidanceAlwaysValues | Should -Be @('from', 'to', 'duration', 'server', 'date')
    }
    It 'verlangt den Schluessel <Key> im Teil <Part>' -TestCases @(
        @(foreach ($k in 'many', 'one', 'none', 'unknown', 'chronic', 'eventMany', 'eventOne', 'eventNone', 'before') { @{ Part = 'userView'; Key = $k } })
        @(foreach ($k in 'red', 'yellow', 'green', 'greenSkipped', 'partBottlenecks', 'partDelays', 'partEvents', 'partChronic', 'partSeparator', 'notMeasured') { @{ Part = 'lagebild'; Key = $k } })
        @(foreach ($k in 'unmeasured', 'skipped', 'notFinished', 'error', 'errorNoMessage', 'stopped') { @{ Part = 'hints'; Key = $k } })
        @(foreach ($k in 'head', 'summaryHead', 'measure', 'cause', 'affected', 'checks', 'remedies', 'contact', 'maxChecks', 'maxRemedies', 'moreChecks', 'moreCheck', 'moreRemedies', 'moreRemedy') { @{ Part = 'copy'; Key = $k } })
    ) { { Read-WorkerPerfGuidance (New-Catalogue { $c[$Part].Remove($Key) }) } | Should -Throw "Katalog '*': Eintrag '$Part': Feld '$Key' fehlt." }
    It 'erlaubt in <Part>.<Key> nur die Platzhalter der Tabelle, nicht <Text>' -TestCases @(           # ruling P3-R26
        @{ Part = 'copy'; Key = 'head'; Text = '{affected}' }; @{ Part = 'copy'; Key = 'summaryHead'; Text = '{incidents}' }; @{ Part = 'copy'; Key = 'measure'; Text = '{app}' }
        @{ Part = 'copy'; Key = 'affected'; Text = '{user}' }; @{ Part = 'copy'; Key = 'cause'; Text = '{app}' }; @{ Part = 'copy'; Key = 'checks'; Text = '{server}' }
        @{ Part = 'copy'; Key = 'remedies'; Text = '{date}' }; @{ Part = 'copy'; Key = 'contact'; Text = '{server}' }
        @{ Part = 'userView'; Key = 'one'; Text = '{user}' }; @{ Part = 'userView'; Key = 'eventMany'; Text = '{app}' }; @{ Part = 'userView'; Key = 'unknown'; Text = '{affected}' }
        @{ Part = 'lagebild'; Key = 'red'; Text = '{server}' }; @{ Part = 'lagebild'; Key = 'yellow'; Text = '{skipped}' }; @{ Part = 'lagebild'; Key = 'green'; Text = '{minutes}' }
        @{ Part = 'lagebild'; Key = 'greenSkipped'; Text = '{incidents}' }
        # a count stands in its part only, so that a part that was not measured can be left out (ruling P3-R49)
        @{ Part = 'lagebild'; Key = 'red'; Text = '{events}' }; @{ Part = 'lagebild'; Key = 'yellow'; Text = '{chronic}' }; @{ Part = 'lagebild'; Key = 'red'; Text = '{bottlenecks}' }
        @{ Part = 'lagebild'; Key = 'yellow'; Text = '{delays}' }; @{ Part = 'lagebild'; Key = 'partEvents'; Text = '{chronic}' }; @{ Part = 'lagebild'; Key = 'partBottlenecks'; Text = '{minutes}' }
        @{ Part = 'lagebild'; Key = 'partDelays'; Text = '{parts}' }; @{ Part = 'lagebild'; Key = 'partChronic'; Text = '{events}' }; @{ Part = 'lagebild'; Key = 'partSeparator'; Text = '{parts}' }
        @{ Part = 'lagebild'; Key = 'notMeasured'; Text = '{signals}' }; @{ Part = 'lagebild'; Key = 'green'; Text = '{parts}' }
        @{ Part = 'copy'; Key = 'moreChecks'; Text = '{server}' }; @{ Part = 'copy'; Key = 'moreCheck'; Text = '{count}' }; @{ Part = 'copy'; Key = 'moreRemedies'; Text = '{affected}' }
        @{ Part = 'copy'; Key = 'moreRemedy'; Text = '{count}' }
        @{ Part = 'hints'; Key = 'unmeasured'; Text = '{skipped}' }; @{ Part = 'hints'; Key = 'skipped'; Text = '{signals}' }; @{ Part = 'hints'; Key = 'error'; Text = '{server}' }
        @{ Part = 'hints'; Key = 'errorNoMessage'; Text = '{message}' }; @{ Part = 'hints'; Key = 'notFinished'; Text = '{message}' }; @{ Part = 'hints'; Key = 'stopped'; Text = '{date}' }
    ) {
        { Read-WorkerPerfGuidance (New-Catalogue { $c[$Part][$Key] = "Text mit $Text." }) } |
            Should -Throw "Katalog '*': Eintrag '$Part': Feld '$Key' enthaelt den Platzhalter '$Text', der in diesem Text nicht erlaubt ist."
    }
    It 'nimmt jeden Platzhalter der Tabelle an' {                                                     # ruling P3-R26
        $cat = Read-WorkerPerfGuidance (New-Catalogue {
                $c.copy.head = '{server} {date}'; $c.copy.summaryHead = '{server} {date} {from} {to}'; $c.copy.measure = '{value} {target}'; $c.copy.affected = '{affected}'
                foreach ($k in @($c.userView.Keys)) { $c.userView[$k] = '{duration} {from} {to}' + $(if ($k -ne 'unknown') { ' {affected} {count}' }) }
                $c.lagebild.red = '{parts} {minutes} {incidents}'; $c.lagebild.yellow = $c.lagebild.red; $c.lagebild.greenSkipped = '{skipped}'; $c.lagebild.notMeasured = '{skipped}'
                $c.lagebild.partBottlenecks = '{bottlenecks}'; $c.lagebild.partDelays = '{delays}'; $c.lagebild.partEvents = '{events}'; $c.lagebild.partChronic = '{chronic}'
                $c.copy.moreChecks = '{count}'; $c.copy.moreRemedies = '{count}'
                $c.hints.unmeasured = '{signals}'; $c.hints.skipped = '{skipped}'; $c.hints.error = '{message}' })
        $cat.userView.one | Should -Be '{duration} {from} {to} {affected} {count}'
        $script:WorkerPerfGuidanceTextPlaceholders['lagebild.red'] | Should -Be @('parts', 'minutes', 'incidents')
        $script:WorkerPerfGuidanceTextPlaceholders['lagebild.yellow'] | Should -Be @('parts', 'minutes', 'incidents')
        $script:WorkerPerfGuidanceTextPlaceholders['copy.summaryHead'] | Should -Be @('server', 'date', 'from', 'to')
        $script:WorkerPerfGuidanceTextPlaceholders['userView.*'] | Should -Be @('affected', 'duration', 'from', 'to', 'count')
    }
    It 'verlangt fuer copy.<Key> eine ganze Zahl ab 1, nicht <Name>' -TestCases @(                      # ruling P3-R59
        @(foreach ($k in 'maxChecks', 'maxRemedies') {
                @{ Key = $k; Name = '0'; Value = 0 }; @{ Key = $k; Name = '-1'; Value = -1 }; @{ Key = $k; Name = '2,5'; Value = 2.5 }; @{ Key = $k; Name = 'den Text 5'; Value = '5' }
                @{ Key = $k; Name = 'wahr'; Value = $true }; @{ Key = $k; Name = 'nichts'; Value = $null }; @{ Key = $k; Name = 'eine Liste'; Value = @(5) }
            })
    ) {
        { Read-WorkerPerfGuidance (New-Catalogue { $c.copy[$Key] = $Value }) } | Should -Throw "Katalog '*': Eintrag 'copy': Feld '$Key' ist keine ganze Zahl ab 1."
    }
    It 'nimmt die Hoechstzahlen des Kopiertexts als Zahlen an' {                                       # ruling P3-R59
        $cat = Read-WorkerPerfGuidance (New-Catalogue { $c.copy.maxChecks = 1; $c.copy.maxRemedies = 12 })
        $cat.copy.maxChecks | Should -Be 1; $cat.copy.maxRemedies | Should -Be 12
        $cat.copy.maxChecks -is [string] | Should -BeFalse
        $script:WorkerPerfGuidancePartNumbers | Should -Be @('copy.maxChecks', 'copy.maxRemedies')
    }
    It 'verlangt das Feld <Field> <Where>' -TestCases @(
        @(foreach ($f in 'title', 'meaning', 'short', 'checks', 'remedies', 'contacts') { @{ Field = $f; Where = 'der Situation'; List = ''; Msg = "*Eintrag 'cpu': Feld '$f' fehlt." } })
        @{ Field = 'where'; Where = 'eines Pruefschritts'; List = 'checks'; Msg = "*Eintrag 'cpu', checks``[0``]: Feld 'where' fehlt." }
        @{ Field = 'sign'; Where = 'eines Pruefschritts'; List = 'checks'; Msg = "*Eintrag 'cpu', checks``[0``]: Feld 'sign' fehlt." }
        @{ Field = 'precondition'; Where = 'einer Abhilfe'; List = 'remedies'; Msg = "*Eintrag 'cpu', remedies``[0``]: Feld 'precondition' fehlt." }
        @{ Field = 'text'; Where = 'eines Kontakts'; List = 'contacts'; Msg = "*Eintrag 'cpu', contacts``[0``]: Feld 'text' fehlt." }
    ) {
        $change = if ($List) { { $c.situations.cpu[$List][0].Remove($Field) } } else { { $c.situations.cpu.Remove($Field) } }
        { Read-WorkerPerfGuidance (New-Catalogue $change) } | Should -Throw $Msg
    }
    It 'vergleicht Herstellerschluessel nach Gross- und Kleinschreibung' {
        $cat = Read-WorkerPerfGuidance (New-Catalogue { $c.vendors += @{ key = 'hp'; match = @('hp-sim*') } })
        @($cat.vendors).Count | Should -Be 6
        Test-WorkerPerfGuidanceCondition 'driver.vendor.hp' $cat | Should -BeTrue
    }
    It 'meldet klar, wenn WorkerPerf.Events.ps1 nicht geladen ist' {
        $src = Join-Path $PSScriptRoot '../src'
        $probe = "Set-StrictMode -Version 2; . '$src/WorkerPerf.Common.ps1'; . '$src/WorkerPerf.Guidance.ps1'; " +
            "try { Test-WorkerPerfGuidanceCondition 'pattern.resource' `$null | Out-Null; 'kein Fehler' } catch { `$_.Exception.Message }"
        $out = @(& (Get-Process -Id $PID).Path -NoProfile -NonInteractive -Command $probe 2>&1)
        $out[-1] | Should -BeLike '*pattern.resource*WorkerPerf.Events.ps1*'
        $out[-1] | Should -Not -BeLike '*has not been set*'
    }
    It 'nennt die Datei in der Meldung' {
        $file = New-Catalogue { $c.situations.cpu.Remove('impact') }
        { Read-WorkerPerfGuidance $file } | Should -Throw ([WildcardPattern]::Escape("Katalog '$file': Eintrag 'cpu': Feld 'impact' fehlt."))
    }
    It 'nimmt Bedingungen und Quellen an, die die Regeln erlauben' {
        $cat = Read-WorkerPerfGuidance (New-Catalogue {
                $c.situations.crash.checks += @{ text = 'Treiber {driver} pruefen'; where = 'w'; sign = 's'; when = @('pattern.printdriver', 'driver.vendor.HP'); source = 'HP, Titel' }
                $c.situations.cpu.remedies += @{ text = '{app} mit {value} statt {target}'; precondition = 'p'; when = @('cause.app', 'role.Hauptanwendung') }
                $c.situations.print.contacts += @{ text = 'Druckerbetreuung'; when = @('spooler.crash'); source = 'Hersteller, Titel' }
                $c.situations.cpu.contacts += @{ text = 'Treiber {driver}'; when = @('driver.v4'); source = 'Hersteller, Titel' } })
        @($cat.situations.crash.checks).Count | Should -Be 2
        @($cat.situations.print.contacts).Count | Should -Be 2
        @($cat.situations.cpu.remedies)[1].when | Should -Be @('cause.app', 'role.Hauptanwendung')
    }
    It 'kennt die Bedingungen der Spezifikation' {
        foreach ($n in 'cause.app', 'cause.security', 'cause.none', 'cause.nodata', 'scan', 'companion.security', 'role.Sicherheit', 'role.Drucken', 'endpoint.slow', 'event.applocker',
            'event.defender', 'unmeasured.disk.latency', 'unmeasured.input.session', 'affected.many', 'affected.one', 'affected.unknown', 'chronic', 'pattern.resource', 'pattern.overlap',
            'pattern.none', 'driver.v3', 'driver.v4', 'driver.shared', 'driver.isolated', 'driver.vendor.HP', 'spooler.crash', 'queue.stuck', 'before',
            'cause.notmeasured', 'skipped.Prozesse', 'skipped.Ereignisse', 'pattern.unchecked', 'incident.unverified',
            'lead.cpu', 'lead.memory', 'lead.disk', 'lead.share', 'lead.profile') {
            Test-WorkerPerfGuidanceCondition $n (Read-WorkerPerfGuidance (New-Catalogue)) | Should -BeTrue -Because $n
        }
        # only the five resources of the worker lead a bottleneck (ruling P3-R37)
        foreach ($n in 'lead.network', 'lead.input', 'lead.endpoint', 'lead.', 'lead', 'lead.CPU') { Test-WorkerPerfGuidanceCondition $n $Cat | Should -BeFalse -Because $n }
        Test-WorkerPerfGuidanceCondition 'driver.vendor.Acme' (Read-WorkerPerfGuidance (New-Catalogue)) | Should -BeFalse
        Test-WorkerPerfGuidanceCondition 'role.Chef' (Read-WorkerPerfGuidance (New-Catalogue)) | Should -BeFalse
        Test-WorkerPerfGuidanceCondition 'skipped.Netz' $Cat | Should -BeFalse
    }
    It 'kennt genau die neun Muster des Abgleichs' {
        foreach ($p in 'resource', 'afterhang', 'sharedmodule', 'printdriver', 'securitymodule', 'manyusers', 'oneuser', 'companion', 'overlap') {
            Test-WorkerPerfGuidanceCondition "pattern.$p" $Cat | Should -BeTrue -Because $p
        }
        $script:WorkerPerfPatternOrder | Should -Be @('resource', 'afterhang', 'sharedmodule', 'printdriver', 'securitymodule', 'manyusers', 'oneuser', 'companion', 'overlap')
        foreach ($n in 'pattern.irgendwas', 'unmeasured.cpu.irgendwas', 'cause', 'role.', 'irgendwas') { Test-WorkerPerfGuidanceCondition $n $Cat | Should -BeFalse -Because $n }
    }
}
Describe 'Anwendungsliste und Anwendungsbedingung' {                                                    # ruling P3-R42 (revised)
    BeforeAll {
        function New-AppsFile([scriptblock]$Change = {}) {
            # a small application list: two applications, one with a wildcard pattern
            $a = @{ version = '2026-11-13'; apps = @(@{ key = 'edge'; label = 'Sim Browser'; processes = @('simedge.exe') }
                    @{ key = 'office'; label = 'Sim Office'; processes = @('EXCEL.EXE', 'WINWORD*.EXE') }) }
            . $Change
            $file = Join-Path $TestDrive ('apps-' + [guid]::NewGuid().ToString('N') + '.json')
            [IO.File]::WriteAllText($file, ($a | ConvertTo-Json -Depth 6), [Text.Encoding]::UTF8)
            $file
        }
        $script:Apps = Read-WorkerPerfApps (New-AppsFile)
        $script:AppCheck = { param($when, $source) $el = @{ text = 't'; where = 'w'; sign = 's'; when = $when }; if ($source) { $el.source = $source }; $el }
    }
    It 'liest eine Anwendungsliste und laesst weitere Felder einer Anwendung stehen' {
        $list = Read-WorkerPerfApps (New-AppsFile { $a.apps[0].installed = @{ kind = 'file'; path = 'C:\Sim\simedge.exe' }; $a.apps[0].probes = @(@{ id = 'p1' }) })
        $list.version | Should -Be '2026-11-13'
        @($list.apps | ForEach-Object { $_.key }) | Should -Be @('edge', 'office')
        $list.apps[1].label | Should -Be 'Sim Office'; @($list.apps[1].processes) | Should -Be @('EXCEL.EXE', 'WINWORD*.EXE')
        $list.apps[0].installed.kind | Should -Be 'file'; @($list.apps[0].probes).Count | Should -Be 1
        # a list without applications is a list
        @((Read-WorkerPerfApps (New-AppsFile { $a.apps = @() })).apps).Count | Should -Be 0
    }
    It 'nennt Anwendung und Feld eines Fehlers der Anwendungsliste' -TestCases @(
        @{ Change = { $a.Remove('version') }; Msg = "Anwendungsliste '*': Feld 'version' fehlt." }
        @{ Change = { $a.version = ' ' }; Msg = "Anwendungsliste '*': Feld 'version' ist leer." }
        @{ Change = { $a.version = 7 }; Msg = "Anwendungsliste '*': Feld 'version' ist kein Text." }
        @{ Change = { $a.Remove('apps') }; Msg = "Anwendungsliste '*': Feld 'apps' fehlt." }
        @{ Change = { $a.apps = 'edge' }; Msg = "Anwendungsliste '*': Feld 'apps' ist keine Liste." }
        @{ Change = { $a.apps = @('edge', 'office') }; Msg = "Anwendungsliste '*': Anwendung apps``[0``] ist kein Objekt." }
        @{ Change = { $a.apps[1].Remove('key') }; Msg = "Anwendungsliste '*': Anwendung apps``[1``]: Feld 'key' fehlt." }
        @{ Change = { $a.apps[0].key = 'sim edge' }; Msg = "Anwendungsliste '*': Anwendung 'sim edge': Feld 'key' darf nur Buchstaben und Ziffern enthalten." }
        @{ Change = { $a.apps[0].key = 'web.view' }; Msg = "Anwendungsliste '*': Anwendung 'web.view': Feld 'key' darf nur Buchstaben und Ziffern enthalten." }
        @{ Change = { $a.apps[1].key = 'edge' }; Msg = "Anwendungsliste '*': Anwendung 'edge': Feld 'key' ist doppelt." }
        @{ Change = { $a.apps[0].Remove('label') }; Msg = "Anwendungsliste '*': Anwendung 'edge': Feld 'label' fehlt." }
        @{ Change = { $a.apps[1].label = '' }; Msg = "Anwendungsliste '*': Anwendung 'office': Feld 'label' ist leer." }
        @{ Change = { $a.apps[0].Remove('processes') }; Msg = "Anwendungsliste '*': Anwendung 'edge': Feld 'processes' fehlt." }
        @{ Change = { $a.apps[0].processes = @() }; Msg = "Anwendungsliste '*': Anwendung 'edge': Feld 'processes' ist keine Liste mit Mustern." }
        @{ Change = { $a.apps[0].processes = 'simedge.exe' }; Msg = "Anwendungsliste '*': Anwendung 'edge': Feld 'processes' ist keine Liste mit Mustern." }
        @{ Change = { $a.apps[1].processes = @('EXCEL.EXE', ' ') }; Msg = "Anwendungsliste '*': Anwendung 'office': Feld 'processes' enthaelt ein leeres Muster." }
        @{ Change = { $a.apps[0].processes = @('sim[') }; Msg = "Anwendungsliste '*': Anwendung 'edge': Feld 'processes' enthaelt das ungueltige Muster 'sim``['." }
        # a process pattern in one application only, whatever its case
        @{ Change = { $a.apps[1].processes = @('EXCEL.EXE', 'SIMEDGE.exe') }; Msg = "Anwendungsliste '*': Anwendung 'office': Feld 'processes' enthaelt das Muster 'SIMEDGE.exe', das schon bei der Anwendung 'edge' steht." }
        @{ Change = { $a.apps[1].processes = @('EXCEL.EXE', 'excel.exe') }; Msg = "Anwendungsliste '*': Anwendung 'office': Feld 'processes' enthaelt das Muster 'excel.exe', das schon bei der Anwendung 'office' steht." }
    ) { { Read-WorkerPerfApps (New-AppsFile $Change) } | Should -Throw $Msg }
    It 'nennt die Datei, wenn sie fehlt oder kein Objekt ist' {
        { Read-WorkerPerfApps (Join-Path $TestDrive 'fehlt.json') } | Should -Throw "*fehlt.json*"
        $file = Join-Path $TestDrive 'apps-list.json'; [IO.File]::WriteAllText($file, '[1, 2]')
        { Read-WorkerPerfApps $file } | Should -Throw ([WildcardPattern]::Escape("Anwendungsliste '$file' ist kein JSON-Objekt."))
    }
    It 'fuehrt in src die Standardanwendungen der Zielumgebung' {
        $real = Read-WorkerPerfApps (Join-Path $PSScriptRoot '../src/apps.json')
        # Aussage angepasst (fix round 3 of Task 6, ruling P3-R57): Outlook is an application of its own, last in the list
        @($real.apps | ForEach-Object { $_.key }) | Should -Be @('edge', 'webview2', 'office', 'teams', 'printaurus', 'outlook')
        @(($real.apps | Where-Object key -eq 'office').processes) | Should -Contain 'EXCEL.EXE'
        @(($real.apps | Where-Object key -eq 'office').processes) | Should -Not -Contain 'OUTLOOK.EXE'
        @(($real.apps | Where-Object key -eq 'outlook').processes) | Should -Be @('OUTLOOK.EXE')
        @(($real.apps | Where-Object key -eq 'edge').processes) | Should -Be @('msedge.exe')
        @(($real.apps | Where-Object key -eq 'webview2').processes) | Should -Be @('msedgewebview2.exe')
        @(($real.apps | Where-Object key -eq 'teams').processes) | Should -Contain 'ms-teams.exe'
        @(($real.apps | Where-Object key -eq 'printaurus').processes) | Should -Be @('PtSmartSpreadClient.exe')
        foreach ($app in $real.apps) { $app.label | Should -Not -BeNullOrEmpty -Because $app.key }
    }
    It 'kennt eine Anwendungsbedingung nur mit einer Anwendungsliste, die den Schluessel hat' {
        foreach ($n in 'app.edge', 'app.office') { Test-WorkerPerfGuidanceCondition $n $Cat $null $Apps | Should -BeTrue -Because $n }
        foreach ($n in 'app.teams', 'app.Edge', 'app.', 'app', 'app.edge.x') { Test-WorkerPerfGuidanceCondition $n $Cat $null $Apps | Should -BeFalse -Because $n }
        # without a list no application is known
        Test-WorkerPerfGuidanceCondition 'app.edge' $Cat | Should -BeFalse
        Test-WorkerPerfGuidanceCondition 'app.edge' $Cat $null (Read-WorkerPerfApps (New-AppsFile { $a.apps = @() })) | Should -BeFalse
    }
    It 'nimmt einen Katalog mit einer Anwendungsbedingung nur mit der Anwendungsliste an' {
        $file = New-Catalogue { $c.situations.cpu.checks += (& $AppCheck @('cause.app', 'app.edge') 'Hersteller: Titel') }
        @((Read-WorkerPerfGuidance $file -Apps $Apps).situations.cpu.checks).Count | Should -Be 2
        { Read-WorkerPerfGuidance $file } | Should -Throw "Katalog '*': Eintrag 'cpu', checks``[1``]: Feld 'when' enthaelt die Bedingung 'app.edge', aber es ist keine Anwendungsliste angegeben (apps.json)."
        # a key the list does not have is an unknown condition
        { Read-WorkerPerfGuidance (New-Catalogue { $c.situations.cpu.remedies += @{ text = 't'; precondition = 'p'; when = @('app.teams'); source = 'Hersteller: Titel' } }) -Apps $Apps } |
            Should -Throw "*Eintrag 'cpu', remedies``[1``]: Feld 'when' enthaelt die unbekannte Bedingung 'app.teams'."
        # a catalogue without such a condition needs no list
        (Read-WorkerPerfGuidance (New-Catalogue)).situations.cpu.short | Should -Be 'CPU'
    }
    It 'verlangt die Quelle fuer jedes Element mit einer Anwendungsbedingung' {
        { Read-WorkerPerfGuidance (New-Catalogue { $c.situations.cpu.checks += (& $AppCheck @('cause.app', 'app.office') $null) }) -Apps $Apps } |
            Should -Throw "*Eintrag 'cpu', checks``[1``]: Feld 'source' fehlt*"
        { Read-WorkerPerfGuidance (New-Catalogue { $c.situations.crash.contacts += @{ text = 'Betreuung'; when = @('app.edge') } }) -Apps $Apps } |
            Should -Throw "*Eintrag 'crash', contacts``[1``]: Feld 'source' fehlt*"
    }
    It 'nennt die Standardanwendung des Verursachers direkt nach der Rolle' {
        $list = Read-WorkerPerfApps (New-AppsFile { $a.apps += @{ key = 'schutz'; label = 'Sim Schutz'; processes = @('MsMp*.exe') } })
        $ctx = New-Ctx; $ctx.Apps = $list
        $engpass = { param($main) New-Inc @{ type = 'engpass'; lead = 'cpu'; cause = @{ kind = 'main' }; main = $main; affected = @(@{ s = 1 }, @{ s = 2 }); scanActive = $true
                companion = @{ label = 'Microsoft Defender' }; endpoints = @(@{ name = 'DB'; maxMs = 340; failed = $false }) } }
        # the main cause of a performance incident, without regard to case
        (Get-WorkerPerfGuidanceFacts -Incident (& $engpass @{ app = 'excel.exe'; a = 0; user = 'user003'; sharePct = 62; baselinePct = 4 }) -Context $ctx -Catalogue $Cat).Conditions |
            Should -Be @('cause.app', 'scan', 'companion.security', 'app.office', 'endpoint.slow', 'affected.many', 'lead.cpu')
        (Get-WorkerPerfGuidanceFacts -Incident (& $engpass @{ app = 'WINWORD64.EXE'; a = 7; user = 'user003'; sharePct = 62; baselinePct = 4 }) -Context $ctx -Catalogue $Cat).Conditions |
            Should -Contain 'app.office'
        # after the role
        (Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu'; cause = @{ kind = 'main' }; main = @{ app = 'MsMpEng.exe'; a = 1; user = 'SYSTEM'; sharePct = 30; baselinePct = 2 } }) -Context $ctx -Catalogue $Cat).Conditions |
            Should -Be @('cause.app', 'role.Sicherheit', 'app.schutz', 'lead.cpu')
        # the application of an event incident, also when the record names a path
        (Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'crash'; app = 'msmpeng.EXE'; sessions = @(3) } }) -Context $ctx -Catalogue $Cat).Conditions |
            Should -Be @('role.Sicherheit', 'app.schutz', 'affected.one', 'pattern.none')
        (Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'hang'; app = 'C:\Sim\simedge.exe' } }) -Context $ctx -Catalogue $Cat).Conditions |
            Should -Be @('app.edge', 'pattern.none')
        # another application, no application, a cause that is no named application: no condition
        foreach ($inc in @(
                (& $engpass @{ app = 'nexus.exe'; a = 5; user = 'user003'; sharePct = 62; baselinePct = 4 })
                (New-Inc @{ type = 'engpass'; lead = 'cpu'; cause = @{ kind = 'none' }; main = @{ app = 'EXCEL.EXE'; a = 0; user = 'user003'; sharePct = 6; baselinePct = 4 } })
                (New-Inc @{ type = 'engpass'; lead = 'cpu'; cause = @{ kind = 'security'; other = @{ app = 'EXCEL.EXE'; user = 'user003' } } })
                (New-Inc @{ type = 'ereignis'; event = @{ kind = 'service'; service = 'SimSvc' } })
                (New-Inc @{ type = 'ohne-engpass'; affected = @(@{ s = 1 }) }))) {
            @((Get-WorkerPerfGuidanceFacts -Incident $inc -Context $ctx -Catalogue $Cat).Conditions | Where-Object { $_ -like 'app.*' }) | Should -Be @()
        }
        # without a list in the context no application condition holds
        @((Get-WorkerPerfGuidanceFacts -Incident (& $engpass @{ app = 'EXCEL.EXE'; a = 0; user = 'user003'; sharePct = 62; baselinePct = 4 }) -Context (New-Ctx) -Catalogue $Cat).Conditions | Where-Object { $_ -like 'app.*' }) | Should -Be @()
    }
    It 'zeigt ein Element mit Anwendungsbedingung nur bei dieser Anwendung' {
        $cat = Read-WorkerPerfGuidance (New-Catalogue { $c.situations.cpu.checks += (& $AppCheck @('cause.app', 'app.office') 'Hersteller: Titel') }) -Apps $Apps
        $ctx = New-Ctx; $ctx.Apps = $Apps
        $shown = { param($app) $i = New-Inc @{ type = 'engpass'; lead = 'cpu'; cause = @{ kind = 'main' }; main = @{ app = $app; a = 0; user = 'user003'; sharePct = 62; baselinePct = 4 } }
            @((New-WorkerPerfGuidance -Catalogue $cat -Facts (Get-WorkerPerfGuidanceFacts -Incident $i -Context $ctx -Catalogue $cat) -Incident $i -Texts $Texts).checks | ForEach-Object { $_.text }) }
        & $shown 'EXCEL.EXE' | Should -Be @('t', 'Pruefen')
        & $shown 'simedge.exe' | Should -Be @('Pruefen')
    }
}
Describe 'Situation und Bedingungen' {
    It 'ordnet jede erzeugbare Situation genau einer Kennung zu' -TestCases @(
        @{ I = @{ type = 'engpass'; lead = 'cpu' }; S = 'cpu' }; @{ I = @{ type = 'engpass'; lead = 'profile' }; S = 'profile' }
        @{ I = @{ type = 'ohne-engpass'; affected = @(@{ s = 1 }, @{ s = 2 }) }; S = 'delay.many' }; @{ I = @{ type = 'ohne-engpass'; affected = @(@{ s = 1 }) }; S = 'delay.single' }
        @{ I = @{ type = 'umfeld'; chronic = $true; signals = @(@{ resource = 'network' }) }; S = 'chronic.network' }; @{ I = @{ type = 'engpass'; chronic = $true; lead = 'memory' }; S = 'chronic.resource' }
        @{ I = @{ type = 'ereignis'; event = @{ kind = 'print' } }; S = 'print' }; @{ I = @{ type = 'umfeld'; signals = @(@{ resource = 'endpoint' }) }; S = 'fallback' }
    ) { Get-WorkerPerfSituation (New-Inc $I) | Should -Be $S }
    It 'ordnet die Ereignisart <S> ihrer Situation zu' -TestCases @(
        @{ I = @{ type = 'ereignis'; event = @{ kind = 'crash' } }; S = 'crash' }; @{ I = @{ type = 'ereignis'; event = @{ kind = 'hang' } }; S = 'hang' }
        @{ I = @{ type = 'ereignis'; event = @{ kind = 'service' } }; S = 'service' }; @{ I = @{ type = 'ereignis'; event = @{ kind = 'print' } }; S = 'print' }
        @{ I = @{ type = 'ereignis'; event = @{ kind = 'profileerror' } }; S = 'profileerror' }; @{ I = @{ type = 'ereignis'; event = @{ kind = 'system' } }; S = 'system' }
    ) { Get-WorkerPerfSituation (New-Inc $I) | Should -Be $S }
    It 'gibt allem anderen den Auffang-Eintrag' -TestCases @(
        @{ I = @{ type = 'umfeld'; chronic = $true; signals = @(@{ resource = 'endpoint' }) }; S = 'fallback' }
        @{ I = @{ type = 'ohne-engpass'; chronic = $true }; S = 'fallback' }; @{ I = @{ type = 'engpass'; lead = $null }; S = 'fallback' }
        @{ I = @{ type = 'ereignis'; event = @{ kind = 'logon' } }; S = 'fallback' }; @{ I = @{ type = 'ereignis' }; S = 'fallback' }
        @{ I = @{ type = 'ohne-engpass' }; S = 'delay.single' }; @{ I = @{ type = 'ereignis'; event = @{ kind = 'crash' } }; S = 'crash' }
        @{ I = @{ type = 'irgendwas' }; S = 'fallback' }
    ) { Get-WorkerPerfSituation (New-Inc $I) | Should -Be $S }
    It 'leitet die Bedingungen eines Engpasses ab' {
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu'; cause = @{ kind = 'main' }; main = @{ app = 'EXCEL.EXE'; a = 0; user = 'user003'; sharePct = 62; baselinePct = 4 }
            affected = @(@{ s = 1 }, @{ s = 2 }); scanActive = $true; companion = @{ label = 'Microsoft Defender' }; endpoints = @(@{ name = 'DB'; maxMs = 340; failed = $false }) }) -Context (New-Ctx) -Catalogue $Cat
        $f.Conditions | Should -Be @('cause.app', 'scan', 'companion.security', 'endpoint.slow', 'affected.many', 'lead.cpu')
        $f.Values.app | Should -Be 'EXCEL.EXE'; $f.Values.share | Should -Be '62 %'; $f.Values.baseline | Should -Be '4 %'; $f.Values.security | Should -Be 'Microsoft Defender'
        $f.Values.ContainsKey('module') | Should -BeFalse
    }
    It 'leitet Treiber, Hersteller und Druckwarteschlange eines Druckproblems ab' {
        $i = New-Inc @{ type = 'ereignis'; event = @{ kind = 'print'; key = 'Sim PCL 6'; app = 'spoolsv.exe'; sessions = @(); before = $false; count = 1
            patterns = @(@{ id = 'printdriver'; detail = @{ module = 'hpsimgr.dll'; driver = 'Sim PCL 6' } }); modules = @(@{ name = 'hpsimgr.dll'; count = 1 }) }
            events = @(@{ app = 'spoolsv.exe'; service = ''; kind = 'crash'; log = 'application' }) }
        $f = Get-WorkerPerfGuidanceFacts -Incident $i -Context (New-Ctx) -Catalogue $Cat
        $f.Conditions | Should -Be @('pattern.printdriver', 'driver.v3', 'driver.shared', 'driver.vendor.HP', 'spooler.crash', 'queue.stuck')
        $f.Values.driver | Should -Be 'Sim PCL 6'; $f.Values.module | Should -Be 'hpsimgr.dll'
    }
    It 'sagt kein Muster und unbekannte Betroffene' {
        (Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'profileerror'; patterns = @(); sessions = @(1); before = $true } }) -Context (New-Ctx) -Catalogue $Cat).Conditions |
            Should -Be @('affected.one', 'pattern.none', 'before')
        $ctx = New-Ctx; $ctx.Data.unmeasured.input = $true; $ctx.Data.sollIst = @(@{ id = 'input.session'; measured = $false })
        (Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu'; cause = @{ kind = 'nodata' } }) -Context $ctx -Catalogue $Cat).Conditions |
            Should -Be @('cause.nodata', 'unmeasured.input.session', 'affected.unknown', 'lead.cpu')
    }
    It 'nennt die Bauart <Type> und die Isolation <Isolation> des Treibers' -TestCases @(
        @{ Type = 3; Isolation = 'none'; Want = @('driver.v3', 'driver.shared') }; @{ Type = 3; Isolation = 'shared'; Want = @('driver.v3', 'driver.shared') }
        @{ Type = 4; Isolation = 'isolated'; Want = @('driver.v4', 'driver.isolated') }; @{ Type = 4; Isolation = ''; Want = @('driver.v4') }
        @{ Type = 0; Isolation = ''; Want = @() }
    ) {
        $ctx = New-Ctx; $ctx.Data.print.drivers = @(@{ name = 'Sim PCL 6'; manufacturer = 'Acme'; type = $Type; isolation = $Isolation }); $ctx.Data.print.queues = @()
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'print'; driver = 'Sim PCL 6'; key = 'Sim PCL 6' } }) -Context $ctx -Catalogue $Cat
        @($f.Conditions | Where-Object { $_.StartsWith('driver.') }) | Should -Be $Want
        $f.Values.driver | Should -Be 'Sim PCL 6'
    }
    It 'findet den Treiber ueber event.driver oder event.key und den Hersteller ueber jedes Muster' {
        $ctx = New-Ctx; $ctx.Data.print.drivers = @(@{ name = 'Sim PCL 6'; manufacturer = 'HP'; type = 3; isolation = 'none' },
            @{ name = 'Sim Universal'; manufacturer = 'Hewlett-Packard'; type = 4; isolation = 'isolated' })
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'crash'; app = 'EXCEL.EXE'; key = 'EXCEL.EXE'; driver = 'sim universal' } }) -Context $ctx -Catalogue $Cat
        @($f.Conditions | Where-Object { $_.StartsWith('driver.') }) | Should -Be @('driver.v4', 'driver.isolated', 'driver.vendor.HP')
        $f.Values.driver | Should -Be 'Sim Universal'
        $f.Conditions | Should -Not -Contain 'spooler.crash'; $f.Conditions | Should -Not -Contain 'queue.stuck'
        # a printdriver pattern naming a driver the list does not hold: the name, but no type, isolation or vendor
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'print'; key = 'Sim PCL 6'; patterns = @(@{ id = 'printdriver'; detail = @{ module = 'x.dll'; driver = 'Fremd' } }) } }) -Context $ctx -Catalogue $Cat
        $f.Values.driver | Should -Be 'Fremd'; @($f.Conditions | Where-Object { $_.StartsWith('driver.') }).Count | Should -Be 0
        # a printdriver pattern without a single driver falls back to event.key
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'print'; key = 'Sim PCL 6'; patterns = @(@{ id = 'printdriver'; detail = @{ module = 'x.dll'; driver = '' } }) } }) -Context $ctx -Catalogue $Cat
        $f.Values.driver | Should -Be 'Sim PCL 6'; $f.Conditions | Should -Contain 'driver.v3'
        # no driver at all
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'crash'; app = 'EXCEL.EXE'; key = 'EXCEL.EXE' } }) -Context $ctx -Catalogue $Cat
        $f.Values.ContainsKey('driver') | Should -BeFalse
    }
    It 'erkennt den Ausfall der Druckwarteschlange auch am Dienst und nur bei einem Druckproblem' {
        $ctx = New-Ctx; $ctx.Data.print.queues = @(@{ name = 'Q1'; maxJobs = 3; jobErrors = 0; notReadyErrors = 0 }, @{ name = 'Q2'; maxJobs = $null; jobErrors = $null; notReadyErrors = $null })
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'print' }; events = @(@{ kind = 'service'; service = 'Spooler' }) }) -Context $ctx -Catalogue $Cat
        $f.Conditions | Should -Contain 'spooler.crash'; $f.Conditions | Should -Not -Contain 'queue.stuck'
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'print' }; events = @(@{ kind = 'crash'; app = 'PrintIsolationHost.exe' }) }) -Context $ctx -Catalogue $Cat
        $f.Conditions | Should -Contain 'spooler.crash'
        $ctx.Data.print.queues[1].notReadyErrors = 2
        (Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'print' } }) -Context $ctx -Catalogue $Cat).Conditions | Should -Contain 'queue.stuck'
        (Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'crash'; app = 'spoolsv.exe' }; events = @(@{ kind = 'crash'; app = 'spoolsv.exe' }) }) -Context $ctx -Catalogue $Cat).Conditions |
            Should -Not -Contain 'spooler.crash'
    }
    It 'nennt die Ursache <Kind>' -TestCases @(
        @{ Kind = 'main'; Want = 'cause.app' }; @{ Kind = 'security'; Want = 'cause.security' }; @{ Kind = 'none'; Want = 'cause.none' }
        @{ Kind = 'nodata'; Want = 'cause.nodata' }; @{ Kind = 'notmeasured'; Want = 'cause.notmeasured' }
    ) {
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu'; cause = @{ kind = $Kind } }) -Context (New-Ctx) -Catalogue $Cat
        @($f.Conditions | Where-Object { $_.StartsWith('cause.') }) | Should -Be @($Want)
    }
    It 'nennt bei Schutzsoftware als Ursache den anderen Verbraucher und keine Werte ohne gemessene Prozesse' {
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu'; cause = @{ kind = 'security'; security = @{ label = 'Die Schutzsoftware'; sharePct = 40 }
                    other = @{ app = 'EXCEL.EXE'; a = 0; user = 'user007'; sharePct = 12.34; baselinePct = 0.5 } }; companion = $null }) -Context (New-Ctx) -Catalogue $Cat
        $f.Conditions | Should -Be @('cause.security', 'lead.cpu')
        $f.Values.security | Should -Be 'Die Schutzsoftware'; $f.Values.app | Should -Be 'EXCEL.EXE'; $f.Values.user | Should -Be 'user007'
        $f.Values.share | Should -Be '12 %'; $f.Values.baseline | Should -Be '0,5 %'
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu'; cause = @{ kind = 'notmeasured' } }) -Context (New-Ctx) -Catalogue $Cat
        foreach ($k in 'app', 'user', 'share', 'baseline', 'security') { $f.Values.ContainsKey($k) | Should -BeFalse -Because $k }
    }
    It 'nennt die Rolle der Anwendung' {
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu'; cause = @{ kind = 'main' }; main = @{ app = 'MsMpEng.exe'; a = 1; user = 'SYSTEM'; sharePct = 30; baselinePct = 2 } }) -Context (New-Ctx) -Catalogue $Cat
        $f.Conditions | Should -Be @('cause.app', 'role.Sicherheit', 'lead.cpu')
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'crash'; app = 'msmpeng.EXE'; sessions = @(3) } }) -Context (New-Ctx) -Catalogue $Cat
        $f.Conditions | Should -Be @('role.Sicherheit', 'affected.one', 'pattern.none')
        # not in apps (always so with Prozesse skipped), or without a role: no role condition
        $ctx = New-Ctx; $ctx.Data.apps = @()
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu'; cause = @{ kind = 'main' }; main = @{ app = 'MsMpEng.exe'; a = 1; user = 'SYSTEM'; sharePct = 30; baselinePct = 2 } }) -Context $ctx -Catalogue $Cat
        $f.Conditions | Should -Be @('cause.app', 'lead.cpu')
        (Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'crash'; app = 'EXCEL.EXE' } }) -Context (New-Ctx) -Catalogue $Cat).Conditions | Should -Be @('pattern.none')
    }
    It 'nennt Gegenstellen, AppLocker und Defender im Fenster' {
        $i = New-Inc @{ type = 'ohne-engpass'; affected = @(@{ s = 1 }); endpoints = @(@{ name = 'DB'; maxMs = 49; failed = $false }, @{ name = 'Web'; maxMs = 0; failed = $true })
            events = @(@{ kind = 'applocker-block'; log = 'applocker' }, @{ kind = 'scan-start'; log = 'defender' }, @{ kind = 'info' }) }
        $f = Get-WorkerPerfGuidanceFacts -Incident $i -Context (New-Ctx) -Catalogue $Cat
        $f.Conditions | Should -Be @('endpoint.slow', 'event.applocker', 'event.defender', 'affected.one')
        $f.Values.endpoint | Should -Be 'Web'
        $i = New-Inc @{ type = 'ohne-engpass'; endpoints = @(@{ name = 'DB'; maxMs = 49; failed = $false }, @{ name = 'Web'; maxMs = 8; failed = $false }) }
        $f = Get-WorkerPerfGuidanceFacts -Incident $i -Context (New-Ctx) -Catalogue $Cat
        $f.Conditions | Should -Be @()
        $f.Values.endpoint | Should -Be 'DB'; $f.Values.endpointValue | Should -Be '49 ms'
        # a probe that only failed has no maxMs in the report data: the endpoint, but no value
        $i = New-Inc @{ type = 'ohne-engpass'; endpoints = @(@{ name = 'DB'; maxMs = 30; failed = $false }, @{ name = 'Web'; maxMs = $null; failed = $true }) }
        $f = Get-WorkerPerfGuidanceFacts -Incident $i -Context (New-Ctx) -Catalogue $Cat
        $f.Conditions | Should -Be @('endpoint.slow')
        $f.Values.endpoint | Should -Be 'Web'; $f.Values.ContainsKey('endpointValue') | Should -BeFalse
    }
    It 'liest den Kontext ohne Schwellen, ohne Texte und als Objekt' {
        $i = New-Inc @{ type = 'ohne-engpass'; endpoints = @(@{ name = 'DB'; maxMs = 340; failed = $false }, @{ name = 'Web'; maxMs = $null; failed = $true }) }
        $ctx = New-Ctx; $ctx.Remove('Thresholds'); $ctx.Remove('Texts')
        $f = Get-WorkerPerfGuidanceFacts -Incident $i -Context $ctx -Catalogue $Cat
        $f.Conditions | Should -Be @('endpoint.slow'); $f.Values.from | Should -Be '02:56'; $f.Values.ContainsKey('duration') | Should -BeFalse
        # only the slow one without a threshold to compare with
        $i.endpoints = @(@{ name = 'DB'; maxMs = 340; failed = $false })
        (Get-WorkerPerfGuidanceFacts -Incident $i -Context ([pscustomobject]$ctx) -Catalogue $Cat).Conditions | Should -Be @()
        $f = Get-WorkerPerfGuidanceFacts -Incident $i -Context ([pscustomobject](New-Ctx)) -Catalogue $Cat
        $f.Conditions | Should -Be @('endpoint.slow'); $f.Values.duration | Should -Be '2 Minuten'
    }
    It 'nennt nicht gemessene Signale, abgeschaltete Kategorien, Dauerzustand und unbestaetigte Verzoegerung in ihrer Reihenfolge' {
        $ctx = New-Ctx; $ctx.Data.sollIst = @(@{ id = 'cpu.host'; measured = $true }, @{ id = 'disk.latency'; measured = $false }, @{ id = 'input.session'; measured = $false })
        $ctx.Data.skipped = @(@{ id = 'Laufwerke'; label = 'Laufwerke'; text = ''; places = @() }, @{ id = 'Ereignisse'; label = 'Ereignisse'; text = ''; places = @() })
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ohne-engpass'; unverified = $true; chronic = $true; affected = @(@{ s = 1 }, @{ s = 2 }, @{ s = 4 }) }) -Context $ctx -Catalogue $Cat
        $f.Conditions | Should -Be @('unmeasured.disk.latency', 'unmeasured.input.session', 'skipped.Laufwerke', 'skipped.Ereignisse', 'affected.many', 'chronic', 'incident.unverified')
        $f.Values.affected | Should -Be '3'
        foreach ($n in $f.Conditions) { Test-WorkerPerfGuidanceCondition $n $Cat | Should -BeTrue -Because $n }
    }
    It 'nennt die fuehrende Ressource <Lead> eines Engpasses direkt nach dem Dauerzustand' -TestCases @(      # ruling P3-R37
        @{ Lead = 'cpu' }; @{ Lead = 'memory' }; @{ Lead = 'disk' }; @{ Lead = 'share' }; @{ Lead = 'profile' }
    ) {
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'engpass'; lead = $Lead; affected = @(@{ s = 1 }) }) -Context (New-Ctx) -Catalogue $Cat
        $f.Situation | Should -Be $Lead; $f.Conditions | Should -Be @('affected.one', "lead.$Lead")
        # a chronic state of that resource: after 'chronic', before 'incident.unverified'
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'engpass'; lead = $Lead; chronic = $true; unverified = $true; cause = @{ kind = 'none' } }) -Context (New-Ctx) -Catalogue $Cat
        $f.Situation | Should -Be 'chronic.resource'; $f.Conditions | Should -Be @('cause.none', 'chronic', "lead.$Lead", 'incident.unverified')
        foreach ($n in $f.Conditions) { Test-WorkerPerfGuidanceCondition $n $Cat | Should -BeTrue -Because $n }
    }
    It 'nennt keine fuehrende Ressource ausserhalb eines Engpasses und fuer keine andere Ressource' {         # ruling P3-R37
        foreach ($i in @{ type = 'ohne-engpass'; lead = 'cpu' }, @{ type = 'umfeld'; lead = 'disk'; chronic = $true }, @{ type = 'ereignis'; lead = 'memory'; event = @{ kind = 'crash' } },
            @{ type = 'engpass'; lead = $null }, @{ type = 'engpass'; lead = 'network' }, @{ type = 'engpass'; lead = 'input'; chronic = $true }, @{ type = 'engpass'; lead = 'CPU' }) {
            $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc $i) -Context (New-Ctx) -Catalogue $Cat
            @($f.Conditions | Where-Object { $_ -like 'lead.*' }) | Should -Be @() -Because ($i.type + ' ' + $i.lead)
        }
    }
    It 'nennt die Muster eines Ereignisvorfalls und nicht gepruefte Muster' {
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'crash'; sessions = @(1, 2)
                    patterns = @(@{ id = 'resource'; detail = @{} }, @{ id = 'overlap'; detail = @{} }); unchecked = @(@{ id = 'printdriver'; category = 'Drucken' }) } }) -Context (New-Ctx) -Catalogue $Cat
        $f.Conditions | Should -Be @('affected.many', 'pattern.resource', 'pattern.overlap', 'pattern.unchecked')
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'crash'; sessions = @(1); unchecked = @(@{ id = 'overlap'; category = 'Laufwerke' }) } }) -Context (New-Ctx) -Catalogue $Cat
        $f.Conditions | Should -Be @('affected.one', 'pattern.unchecked')
    }
    It 'bestimmt die Betroffenen eines Ereignisvorfalls' -TestCases @(
        @{ Over = @{ sessions = @(); sessionUnknown = $true }; Want = @('affected.unknown') }
        @{ Over = @{ sessions = @(); unchecked = @(@{ id = 'users'; category = 'Ereignisse' }) }; Want = @('affected.unknown', 'pattern.unchecked') }
        @{ Over = @{ sessions = @(); noUserSession = $true }; Want = @() }
        @{ Over = @{ sessions = @() }; Want = @() }
        @{ Over = @{ sessions = @(5, 6); sessionUnknown = $true }; Want = @('affected.many') }
    ) {
        $evt = @{ kind = 'crash'; patterns = @(@{ id = 'oneuser'; detail = @{} }) }; foreach ($k in $Over.Keys) { $evt[$k] = $Over[$k] }
        $ctx = New-Ctx; $ctx.Data.unmeasured.input = $true
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = $evt }) -Context $ctx -Catalogue $Cat
        @($f.Conditions | Where-Object { $_ -ne 'pattern.oneuser' }) | Should -Be $Want
    }
    It 'liest Berichtsdaten mit fehlenden Schluesseln und als geordnete Woerterbuecher' {
        # an older report: no unverified, no event.unchecked, no skipped; events[] without empty keys
        $i = [ordered]@{ id = 3; type = 'ereignis'; chronic = $false; start = [long](1e12 + 600000); end = [long](1e12 + 600000); signals = @(); affected = @()
            events = @([ordered]@{ t = 1; kind = 'crash'; s = -1; text = '' }); endpoints = @(); main = $null; cause = $null; companion = $null; scanActive = $false
            event = [ordered]@{ kind = 'print'; key = 'Sim PCL 6'; count = 2; sessions = [int[]]@(); before = $false; patterns = @(); modules = @(); app = '' } }
        $ctx = New-Ctx; $ctx.Data.Remove('skipped'); $ctx.Data.print.queues = @()
        $f = Get-WorkerPerfGuidanceFacts -Incident $i -Context $ctx -Catalogue $Cat
        $f.Situation | Should -Be 'print'
        $f.Conditions | Should -Be @('pattern.none', 'driver.v3', 'driver.shared', 'driver.vendor.HP')
        $f.Values.count | Should -Be '2'; $f.Values.ContainsKey('duration') | Should -BeFalse
        # a bare performance incident
        $f = Get-WorkerPerfGuidanceFacts -Incident ([ordered]@{ type = 'ohne-engpass'; start = [long]1e12; end = [long](1e12 + 1000) }) -Context $ctx -Catalogue $Cat
        $f.Situation | Should -Be 'delay.single'; $f.Conditions | Should -Be @()
    }
}
Describe 'Platzhalterwerte' {
    It 'nennt Messwert, Soll, Zeiten, Ressource, Server und Datum' {
        $i = New-Inc @{ type = 'engpass'; lead = 'disk'; affected = @(@{ s = 1 })
            signals = @(@{ id = 'disk.latency'; label = 'Latenz C:'; resource = 'disk'; peak = 48.25; unit = 'ms'; ideal = 'unter 20 ms'; severity = 2; start = [long](1e12 + 610000); end = [long](1e12 + 700000) }
                @{ id = 'disk.latency'; label = 'Latenz D:'; resource = 'disk'; peak = 99; unit = 'ms'; ideal = 'unter 20 ms'; severity = 1; start = [long](1e12 + 600000); end = [long](1e12 + 700000) }
                @{ id = 'cpu.host'; label = 'CPU-Auslastung'; resource = 'cpu'; peak = 99; unit = '%'; ideal = 'unter 75 %'; severity = 2; start = [long](1e12 + 600000); end = [long](1e12 + 700000) }
                @{ id = 'disk.queue'; label = 'Warteschlange C:'; resource = 'disk'; peak = 7; unit = ''; ideal = 'bis 2'; severity = 2; start = [long](1e12 + 650000); end = [long](1e12 + 700000) }) }
        $f = Get-WorkerPerfGuidanceFacts -Incident $i -Context (New-Ctx) -Catalogue $Cat
        $f.Situation | Should -Be 'disk'
        $f.Values.value | Should -Be '48 ms'; $f.Values.target | Should -Be 'unter 20 ms'; $f.Values.resource | Should -Be 'Latenz C:'
        # 1e12 ms is 2001-09-09 01:46:40 UTC; start 10 min later, one hour offset
        $f.Values.from | Should -Be '02:56'; $f.Values.to | Should -Be '02:58'; $f.Values.duration | Should -Be '2 Minuten'
        $f.Values.date | Should -Be '09.09.2001'; $f.Values.server | Should -Be 'SIM-VDA01'; $f.Values.affected | Should -Be '1'
        foreach ($k in 'user', 'app', 'share', 'baseline', 'security', 'endpoint', 'endpointValue', 'module', 'driver', 'count') { $f.Values.ContainsKey($k) | Should -BeFalse -Because $k }
        @($f.Values.Keys | Where-Object { $script:WorkerPerfGuidancePlaceholders -cnotcontains $_ }).Count | Should -Be 0
    }
    It 'nennt keine Ressource bei <Lead> und den Wert ohne Einheit' -TestCases @(@{ Lead = 'cpu' }, @{ Lead = 'memory' }) {
        $i = New-Inc @{ type = 'engpass'; lead = $Lead; signals = @(@{ id = 'x'; label = 'Etwas'; resource = $Lead; peak = 3.25; unit = ''; ideal = ''; severity = 2; start = [long]1e12; end = [long]1e12 }) }
        $f = Get-WorkerPerfGuidanceFacts -Incident $i -Context (New-Ctx) -Catalogue $Cat
        $f.Values.value | Should -Be '3,3'; $f.Values.ContainsKey('target') | Should -BeFalse; $f.Values.ContainsKey('resource') | Should -BeFalse
    }
    It 'nimmt das Eingabesignal einer Verzoegerung und das Netzsignal eines Dauerzustands' {
        $sig = @(@{ id = 'cpu.host'; label = 'CPU'; resource = 'cpu'; peak = 80; unit = '%'; ideal = 'unter 75 %'; severity = 2; start = [long]1e12; end = [long]1e12 }
            @{ id = 'input.session'; label = 'Eingabe'; resource = 'input'; peak = 1500; unit = 'ms'; ideal = 'unter 500 ms'; severity = 1; start = [long]1e12; end = [long]1e12 }
            @{ id = 'ica.rtt'; label = 'ICA'; resource = 'network'; peak = 250; unit = 'ms'; ideal = 'unter 150 ms'; severity = 1; start = [long]1e12; end = [long]1e12 })
        (Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ohne-engpass'; signals = $sig }) -Context (New-Ctx) -Catalogue $Cat).Values.value | Should -Be '1500 ms'
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'umfeld'; chronic = $true; signals = $sig }) -Context (New-Ctx) -Catalogue $Cat
        $f.Situation | Should -Be 'chronic.network'; $f.Values.value | Should -Be '250 ms'; $f.Values.target | Should -Be 'unter 150 ms'
        $f.Conditions | Should -Be @('chronic')
    }
    It 'schreibt die Dauer <Sec> s als <Want>' -TestCases @(
        @{ Sec = 45; Want = '45 Sekunden' }; @{ Sec = 1; Want = '1 Sekunde' }; @{ Sec = 2.5; Want = '2,5 Sekunden' }; @{ Sec = 59.6; Want = '1 Minute' }
        @{ Sec = 120; Want = '2 Minuten' }; @{ Sec = 228; Want = '3,8 Minuten' }; @{ Sec = 3570; Want = '1 Stunde' }
        @{ Sec = 36000; Want = '10 Stunden' }
        # the boundaries of the units (fix round 1, item 7)
        @{ Sec = 59.4; Want = '59 Sekunden' }; @{ Sec = 59.5; Want = '1 Minute' }; @{ Sec = 60; Want = '1 Minute' }; @{ Sec = 90; Want = '1,5 Minuten' }
        @{ Sec = 3599; Want = '1 Stunde' }; @{ Sec = 3600; Want = '1 Stunde' }; @{ Sec = 5400; Want = '1,5 Stunden' }
    ) {
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ start = [long]1e12; end = [long](1e12 + $Sec * 1000) }) -Context (New-Ctx) -Catalogue $Cat
        $f.Values.duration | Should -Be $Want
        $f.Values.duration | Should -Not -Match '^60 '
    }
    It 'schreibt keine Dauer ohne Dauer und nimmt die Einheiten aus den Texten' {
        (Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ start = [long]1e12; end = [long]1e12 }) -Context (New-Ctx) -Catalogue $Cat).Values.ContainsKey('duration') | Should -BeFalse
        $ctx = New-Ctx; $ctx.Texts = $script:Texts.Clone(); $ctx.Texts['duration.minutes'] = 'min'; $ctx.Texts['duration.hour'] = 'h'
        (Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ start = [long]1e12; end = [long](1e12 + 228000) }) -Context $ctx -Catalogue $Cat).Values.duration | Should -Be '3,8 min'
        (Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ start = [long]1e12; end = [long](1e12 + 3600000) }) -Context $ctx -Catalogue $Cat).Values.duration | Should -Be '1 h'
        foreach ($k in 'duration.second', 'duration.seconds', 'duration.minute', 'duration.minutes', 'duration.hour', 'duration.hours') { $script:Texts.ContainsKey($k) | Should -BeTrue -Because $k }
    }
    It 'nennt Modul, Zahl und Betroffene eines Ereignisvorfalls' {
        $i = New-Inc @{ type = 'ereignis'; start = [long]1e12; end = [long]1e12; event = @{ kind = 'crash'; app = 'EXCEL.EXE'; count = 4; sessions = @(1, 2, 3)
                modules = @(@{ name = 'a.dll'; count = 1 }, @{ name = 'b.dll'; count = 3 }, @{ name = 'c.dll'; count = 3 }) } }
        $f = Get-WorkerPerfGuidanceFacts -Incident $i -Context (New-Ctx) -Catalogue $Cat
        $f.Values.module | Should -Be 'b.dll'; $f.Values.count | Should -Be '4'; $f.Values.affected | Should -Be '3'
        $f.Values.from | Should -Be '02:46'; $f.Values.to | Should -Be '02:46'; $f.Values.ContainsKey('duration') | Should -BeFalse
        # unknown sessions: no number
        $i = New-Inc @{ type = 'ereignis'; event = @{ kind = 'crash'; sessionUnknown = $true } }
        (Get-WorkerPerfGuidanceFacts -Incident $i -Context (New-Ctx) -Catalogue $Cat).Values.ContainsKey('affected') | Should -BeFalse
    }
    It 'nennt Anwendung und Benutzer eines Ereignisvorfalls' {
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'crash'; app = 'EXCEL.EXE'; users = @('user004'); sessions = @(2) } }) -Context (New-Ctx) -Catalogue $Cat
        $f.Values.app | Should -Be 'EXCEL.EXE'; $f.Values.user | Should -Be 'user004'
        foreach ($k in 'share', 'baseline') { $f.Values.ContainsKey($k) | Should -BeFalse -Because $k }
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'crash'; app = 'EXCEL.EXE'; users = @('user004', 'user005', 'user006'); sessions = @(2, 3, 4) } }) -Context (New-Ctx) -Catalogue $Cat
        $f.Values.app | Should -Be 'EXCEL.EXE'; $f.Values.ContainsKey('user') | Should -BeFalse
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'print'; app = 'spoolsv.exe'; key = 'Sim PCL 6'; noUserSession = $true } }) -Context (New-Ctx) -Catalogue $Cat
        $f.Values.app | Should -Be 'spoolsv.exe'; $f.Values.ContainsKey('user') | Should -BeFalse
        foreach ($k in 'share', 'baseline') { $f.Values.ContainsKey($k) | Should -BeFalse -Because $k }
        (Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'system' } }) -Context (New-Ctx) -Catalogue $Cat).Values.ContainsKey('app') | Should -BeFalse
    }
    It 'nennt bei einem Vorfall vor der Messung ohne Sitzungen keine Zahl der Betroffenen' {
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'crash'; app = 'EXCEL.EXE'; users = @('user004'); sessions = @(); before = $true } }) -Context (New-Ctx) -Catalogue $Cat
        $f.Values.ContainsKey('affected') | Should -BeFalse; $f.Values.user | Should -Be 'user004'
        $f.Conditions | Should -Be @('pattern.none', 'before')
        # during the capture an incident without sessions keeps its 0
        (Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'print'; noUserSession = $true } }) -Context (New-Ctx) -Catalogue $Cat).Values.affected | Should -Be '0'
    }
    It 'nimmt die Ortszeit eines Ereignisvorfalls aus seinen Aufzeichnungen' {
        # capture offset 60; the lookback reaches back over the end of daylight-saving time: first record +120, last +60
        $start = (New-Object DateTimeOffset 2001, 9, 8, 22, 30, 0, ([TimeSpan]::Zero)).ToUnixTimeMilliseconds(); $end = $start + 7200000
        # the last record has an offset of its own (0) that differs from the capture's (60): 'to' must take the record's
        $rec = @([ordered]@{ t = $start; offsetMin = 120; kind = 'crash'; s = -1; text = '' }, [ordered]@{ t = $end; offsetMin = 0; kind = 'crash'; s = -1; text = '' })
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; start = $start; end = $end; events = $rec; event = @{ kind = 'crash'; before = $true } }) -Context (New-Ctx) -Catalogue $Cat
        $f.Values.from | Should -Be '00:30'; $f.Values.date | Should -Be '09.09.2001'; $f.Values.to | Should -Be '00:30'
        # records without their own offset: the capture's
        $rec = @([ordered]@{ t = $start; kind = 'crash'; s = -1; text = '' })
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; start = $start; end = $end; events = $rec; event = @{ kind = 'crash'; before = $true } }) -Context (New-Ctx) -Catalogue $Cat
        $f.Values.from | Should -Be '23:30'; $f.Values.date | Should -Be '08.09.2001'; $f.Values.to | Should -Be '01:30'
    }
}
Describe 'Anleitung zusammenstellen' {
    BeforeAll {
        $script:Cat2 = Read-WorkerPerfGuidance (New-Catalogue { $c.situations.cpu.checks = @(
            @{ text = 'Allgemein'; where = 'w'; sign = 's' }
            @{ text = '{app} von {user} pruefen'; where = 'Task-Manager'; sign = 'hoher Anteil'; when = @('cause.app') }
            @{ text = 'Scan von {security}'; where = 'w'; sign = 's'; when = @('scan', 'companion.security') }
            @{ text = 'Gegenstelle {endpoint}'; where = 'w'; sign = 's' }) })
    }
    It 'waehlt genau die gestuetzten Elemente, bedingte zuerst' {
        $g = New-WorkerPerfGuidance -Catalogue $Cat2 -Facts @{ Situation = 'cpu'; Conditions = @('cause.app', 'scan'); Values = @{ app = 'EXCEL.EXE'; user = 'user003'; security = 'X' } } -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu' }) -Texts $Texts
        @($g.checks.text) | Should -Be @('EXCEL.EXE von user003 pruefen', 'Allgemein')                  # 'scan' allein reicht nicht; {endpoint} fehlt
        $g.fallback | Should -BeFalse; $g.tech | Should -Be 'Engpass · CPU'
    }
    It 'zeigt ohne zutreffende Bedingung nur die allgemeinen Elemente' {
        @((New-WorkerPerfGuidance -Catalogue $Cat2 -Facts @{ Situation = 'cpu'; Conditions = @(); Values = @{} } -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu' }) -Texts $Texts).checks.text) | Should -Be @('Allgemein')
    }
    It 'nimmt den Auffang-Eintrag mit sichtbarem Hinweis' {
        $g = New-WorkerPerfGuidance -Catalogue $Cat2 -Facts @{ Situation = 'fallback'; Conditions = @(); Values = @{} } -Incident (New-Inc @{ type = 'umfeld' }) -Texts $Texts
        $g.fallback | Should -BeTrue; $g.meaning | Should -BeLike ($Cat2.fallbackNote + '*')
    }
    It 'setzt Werte mit Klammern und HTML woertlich ein' {                                         # Review Focus 1
        Format-WorkerPerfGuidanceText '{app} von {user}' @{ app = '{user}.exe'; user = '<b>x</b>' } | Should -BeExactly '{user}.exe von <b>x</b>'
        Format-WorkerPerfGuidanceText '{app} von {user}' @{ app = 'a' } | Should -BeNullOrEmpty
    }
    It 'laesst einen Text ohne Platzhalter unveraendert und behandelt einen leeren Wert als fehlend' {
        Format-WorkerPerfGuidanceText 'Ohne Platzhalter.' @{} | Should -BeExactly 'Ohne Platzhalter.'
        Format-WorkerPerfGuidanceText 'Von {from} bis {to}.' @{ from = '10:00'; to = '10:05' } | Should -BeExactly 'Von 10:00 bis 10:05.'
        Format-WorkerPerfGuidanceText '{app} lief' @{ app = '' } | Should -BeNullOrEmpty
        Format-WorkerPerfGuidanceText '{app} lief' @{ app = $null } | Should -BeNullOrEmpty
        Format-WorkerPerfGuidanceText '{app} und {app}' @{ app = '$1 & $0' } | Should -BeExactly '$1 & $0 und $1 & $0'
    }
    It 'nimmt den Auffang-Eintrag fuer eine Situation, die der Katalog nicht hat' {
        $g = New-WorkerPerfGuidance -Catalogue $Cat2 -Facts @{ Situation = 'irgendwas'; Conditions = @(); Values = @{ from = '10:00'; to = '10:05' } } -Incident (New-Inc @{ type = 'umfeld' }) -Texts $Texts
        $g.fallback | Should -BeTrue; $g.situation | Should -Be 'fallback'; $g.title | Should -Be 'Titel fallback'
        $g.meaning | Should -BeExactly 'Keine spezifische Anleitung. Von 10:00 bis 10:05.'
        $g.tech | Should -Be 'Umfeld'
        # a known situation is no fallback, and its meaning has no note
        $g = New-WorkerPerfGuidance -Catalogue $Cat2 -Facts @{ Situation = 'memory'; Conditions = @(); Values = @{ from = '10:00'; to = '10:05' } } -Incident (New-Inc @{ type = 'engpass'; lead = 'memory' }) -Texts $Texts
        $g.fallback | Should -BeFalse; $g.situation | Should -Be 'memory'; $g.meaning | Should -BeExactly 'Von 10:00 bis 10:05.'
    }
    It 'nimmt fuer die Wirkung die erste andere Fassung, deren Bedingungen alle gelten, sonst die Wirkung selbst' {   # fix round 4, B2 (ruling P3-R65)
        $cat4 = Read-WorkerPerfGuidance (New-Catalogue {
                $c.terms['Eingabeverzoegerung'] = 'Wartezeit einer Eingabe.'
                $c.situations.cpu.impact = 'Eingaben reagierten verzoegert.'
                $c.situations.cpu.impactVariants = @(
                    @{ when = @('unmeasured.input.session', 'chronic'); text = 'Dauerhaft, nicht gemessen ab {from}.' }
                    @{ when = @('unmeasured.input.session'); text = 'Eingaben koennen verzoegert reagiert haben; die Eingabeverzoegerung wurde nicht gemessen.' }
                    @{ when = @('scan'); text = 'Beim Scan auf {server}.' })
                # a one-element list arrives as a list too
                $c.situations.disk.impactVariants = @(, @{ when = @('unmeasured.input.session'); text = 'Nicht gemessen.' }) })
        $cat4.situations.cpu.impact | Should -Be 'Eingaben reagierten verzoegert.'; @($cat4.situations.cpu.impactVariants).Count | Should -Be 3
        $inc = New-Inc @{ type = 'engpass'; lead = 'cpu' }
        $vals = @{ from = '10:00'; to = '10:05'; server = 'SIM-VDA01' }
        $impact = { param([string[]]$Conditions, [string]$Situation = 'cpu', $Values = $vals)
            (New-WorkerPerfGuidance -Catalogue $cat4 -Facts @{ Situation = $Situation; Conditions = $Conditions; Values = $Values } -Incident $inc -Texts $Texts) }
        (& $impact @()).impact | Should -BeExactly 'Eingaben reagierten verzoegert.'
        (& $impact @('cause.app', 'affected.unknown')).impact | Should -BeExactly 'Eingaben reagierten verzoegert.'
        (& $impact @('cause.app', 'unmeasured.input.session')).impact | Should -BeExactly 'Eingaben koennen verzoegert reagiert haben; die Eingabeverzoegerung wurde nicht gemessen.'
        # every condition of a variant must hold; the first variant that fits wins
        (& $impact @('chronic')).impact | Should -BeExactly 'Eingaben reagierten verzoegert.'
        (& $impact @('chronic', 'unmeasured.input.session', 'scan')).impact | Should -BeExactly 'Dauerhaft, nicht gemessen ab 10:00.'
        (& $impact @('scan', 'unmeasured.input.session')).impact | Should -BeExactly 'Eingaben koennen verzoegert reagiert haben; die Eingabeverzoegerung wurde nicht gemessen.'
        (& $impact @('scan')).impact | Should -BeExactly 'Beim Scan auf SIM-VDA01.'
        # the condition is compared exactly, and a variant whose placeholder has no value gives way to the next one that fits
        (& $impact @('Unmeasured.Input.Session')).impact | Should -BeExactly 'Eingaben reagierten verzoegert.'
        (& $impact @('scan') 'cpu' @{ from = '10:00'; to = '10:05' }).impact | Should -BeExactly 'Eingaben reagierten verzoegert.'
        # the glossary follows the wording shown
        (& $impact @('unmeasured.input.session')).terms | Should -Contain 'Eingabeverzoegerung'; (& $impact @()).terms | Should -Not -Contain 'Eingabeverzoegerung'
        # another situation: its own variants, or none
        (& $impact @('unmeasured.input.session') 'disk').impact | Should -BeExactly 'Nicht gemessen.'; (& $impact @('unmeasured.input.session') 'memory').impact | Should -BeExactly 'Langsam.'
        # the copy text carries the wording of the guidance
        $g = & $impact @('unmeasured.input.session')
        $p = @(Get-WorkerPerfCopyParagraphs -Incident $inc -Guide $g -Data (New-Ctx).Data -Catalogue $cat4 -Texts $Texts)
        $p | Should -Contain 'Eingaben koennen verzoegert reagiert haben; die Eingabeverzoegerung wurde nicht gemessen.'; $p | Should -Not -Contain 'Eingaben reagierten verzoegert.'
    }
    It 'fuellt Titel, Wirkung und Kuerzel und gibt jedem Element alle Felder' {
        $cat3 = Read-WorkerPerfGuidance (New-Catalogue {
                $c.situations.disk.title = 'Laufwerk langsam'; $c.situations.disk.short = 'DISK'; $c.situations.disk.impact = 'Langsam auf {server}.'
                $c.situations.disk.remedies = @(@{ text = 'Ausschluss fuer {app}'; precondition = 'Wenn {security} scannt'; when = @('scan'); source = 'Hersteller {security}' }
                    @{ text = 'Abhelfen'; precondition = 'Voraussetzung' })
                $c.situations.disk.contacts = @(@{ text = 'Betreuung von {app}' }, @{ text = 'Betreuung {endpoint}' }) })
        $vals = @{ resource = 'Latenz C:'; app = 'EXCEL.EXE'; security = 'Die Schutzsoftware'; from = '10:00'; to = '10:05'; server = 'SIM-VDA01' }
        $g = New-WorkerPerfGuidance -Catalogue $cat3 -Facts @{ Situation = 'disk'; Conditions = @('scan'); Values = $vals } -Incident (New-Inc @{ type = 'engpass'; lead = 'disk' }) -Texts $Texts
        $g.title | Should -Be 'Laufwerk langsam'; $g.impact | Should -Be 'Langsam auf SIM-VDA01.'; $g.short | Should -Be 'DISK'; $g.tech | Should -Be 'Engpass · Datenträger'
        @($g.Keys) | Should -Be @('situation', 'fallback', 'title', 'tech', 'meaning', 'impact', 'userView', 'checks', 'remedies', 'contacts', 'short', 'terms', 'conditions')
        @($g.checks[0].Keys) | Should -Be @('text', 'where', 'sign', 'source')
        $g.checks[0].source | Should -Be 'Hersteller, Titel'
        @($g.remedies.text) | Should -Be @('Ausschluss fuer EXCEL.EXE', 'Abhelfen')
        $g.remedies[0].precondition | Should -Be 'Wenn Die Schutzsoftware scannt'; $g.remedies[0].source | Should -Be 'Hersteller Die Schutzsoftware'
        $g.remedies[1].Contains('source') | Should -BeTrue; $g.remedies[1].source | Should -BeNullOrEmpty
        @($g.contacts.text) | Should -Be @('Betreuung von EXCEL.EXE')
        @($g.contacts[0].Keys) | Should -Be @('text', 'source')
        $g.contacts[0].Contains('source') | Should -BeTrue; $null -eq $g.contacts[0].source | Should -BeTrue
        $g.conditions | Should -Be @('scan')
        # no element survives: empty lists, not null
        $g = New-WorkerPerfGuidance -Catalogue $cat3 -Facts @{ Situation = 'disk'; Conditions = @(); Values = @{} } -Incident (New-Inc @{ type = 'engpass'; lead = 'disk' }) -Texts $Texts
        , $g.contacts | Should -BeOfType [object[]]; $g.contacts.Count | Should -Be 0
        $g.conditions.Count | Should -Be 0; $g.title | Should -Be 'Laufwerk langsam'
    }
    It 'gibt die Quelle eines Kontakts weiter' {                                                      # ruling P3-R21
        $g = New-WorkerPerfGuidance -Catalogue $Cat -Facts @{ Situation = 'print'; Conditions = @(); Values = @{} } -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'print' } }) -Texts $Texts
        @($g.contacts.text) | Should -Be @('Kontakt'); $g.contacts[0].source | Should -Be 'Hersteller, Titel'
    }
    It 'gibt einer Auffang-Bedeutung ohne fuellbaren Text $null' {
        $cat = Read-WorkerPerfGuidance (New-Catalogue { $c.fallbackNote = 'Keine Anleitung fuer {server}.' })
        $g = New-WorkerPerfGuidance -Catalogue $cat -Facts @{ Situation = 'fallback'; Conditions = @(); Values = @{} } -Incident (New-Inc @{ type = 'umfeld' }) -Texts $Texts
        $g.fallback | Should -BeTrue; $null -eq $g.meaning | Should -BeTrue
        $g = New-WorkerPerfGuidance -Catalogue $cat -Facts @{ Situation = 'fallback'; Conditions = @(); Values = @{ server = 'SIM-VDA01' } } -Incident (New-Inc @{ type = 'umfeld' }) -Texts $Texts
        $g.meaning | Should -BeExactly 'Keine Anleitung fuer SIM-VDA01.'
    }
    It 'laesst ein Element fallen, dessen Ort oder Quelle nicht gefuellt werden kann, und haelt die Reihenfolge je Gruppe' {
        $cat5 = Read-WorkerPerfGuidance (New-Catalogue { $c.situations.cpu.checks = @(
                    @{ text = 'Erst allgemein'; where = 'w'; sign = 's' }
                    @{ text = 'Erst bedingt'; where = 'w'; sign = 's'; when = @('cause.app') }
                    @{ text = 'Dann allgemein'; where = 'w'; sign = 's' }
                    @{ text = 'Ort fehlt'; where = 'Bei {endpoint}'; sign = 's' }
                    @{ text = 'Dann bedingt'; where = 'w'; sign = 's'; when = @('scan') }
                    @{ text = 'Quelle fehlt'; where = 'w'; sign = 's'; source = 'Hersteller {driver}' }) })
        $g = New-WorkerPerfGuidance -Catalogue $cat5 -Facts @{ Situation = 'cpu'; Conditions = @('cause.app', 'scan'); Values = @{} } -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu' }) -Texts $Texts
        @($g.checks.text) | Should -Be @('Erst bedingt', 'Dann bedingt', 'Erst allgemein', 'Dann allgemein')
        # with the values both come back
        $g = New-WorkerPerfGuidance -Catalogue $cat5 -Facts @{ Situation = 'cpu'; Conditions = @(); Values = @{ endpoint = 'DB'; driver = 'Sim PCL 6' } } -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu' }) -Texts $Texts
        @($g.checks.text) | Should -Be @('Erst allgemein', 'Dann allgemein', 'Ort fehlt', 'Quelle fehlt')
        $g.checks[2].where | Should -Be 'Bei DB'; $g.checks[3].source | Should -Be 'Hersteller Sim PCL 6'
    }
    It 'stellt Elemente, deren Bedingungen nur eine Luecke nennen, hinter die allgemeinen' {            # ruling P3-R36
        $cat8 = Read-WorkerPerfGuidance (New-Catalogue {
                $c.situations.cpu.checks = @(
                    @{ text = 'Luecke Prozesse'; where = 'w'; sign = 's'; when = @('skipped.Prozesse') }
                    @{ text = 'Allgemein 1'; where = 'w'; sign = 's' }
                    @{ text = 'Luecke Ursache'; where = 'w'; sign = 's'; when = @('cause.notmeasured') }
                    @{ text = 'Bedingt 1'; where = 'w'; sign = 's'; when = @('cause.app') }
                    @{ text = 'Luecke Signal und Muster'; where = 'w'; sign = 's'; when = @('unmeasured.input.session', 'pattern.unchecked') }
                    @{ text = 'Bedingt mit Luecke'; where = 'w'; sign = 's'; when = @('skipped.Prozesse', 'affected.unknown') }
                    @{ text = 'Allgemein 2'; where = 'w'; sign = 's' }
                    @{ text = 'Luecke unbestaetigt'; where = 'w'; sign = 's'; when = @('incident.unverified') }
                    @{ text = 'Bedingt 2'; where = 'w'; sign = 's'; when = @('scan', 'cause.app') })
                $c.situations.cpu.remedies = @(@{ text = 'Luecke'; precondition = 'p'; when = @('unmeasured.probe.connect') }, @{ text = 'Allgemein'; precondition = 'p' },
                    @{ text = 'Bedingt'; precondition = 'p'; when = @('endpoint.slow') })
                $c.situations.cpu.contacts = @(@{ text = 'Luecke'; when = @('skipped.Gegenstellen') }, @{ text = 'Allgemein' }, @{ text = 'Bedingt'; when = @('lead.cpu') }) })
        $all = @('cause.app', 'cause.notmeasured', 'scan', 'endpoint.slow', 'unmeasured.input.session', 'unmeasured.probe.connect', 'skipped.Prozesse', 'skipped.Gegenstellen',
            'affected.unknown', 'lead.cpu', 'incident.unverified', 'pattern.unchecked')
        $g = New-WorkerPerfGuidance -Catalogue $cat8 -Facts @{ Situation = 'cpu'; Conditions = $all; Values = @{} } -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu' }) -Texts $Texts
        # three groups, file order within each: a condition that names more than a gap, then no condition, then gaps only
        @($g.checks.text) | Should -Be @('Bedingt 1', 'Bedingt mit Luecke', 'Bedingt 2', 'Allgemein 1', 'Allgemein 2',
            'Luecke Prozesse', 'Luecke Ursache', 'Luecke Signal und Muster', 'Luecke unbestaetigt')
        @($g.remedies.text) | Should -Be @('Bedingt', 'Allgemein', 'Luecke')
        @($g.contacts.text) | Should -Be @('Bedingt', 'Allgemein', 'Luecke')
        @(Get-WorkerPerfGuidanceItems $cat8.situations.cpu 'remedies' $all @{} | ForEach-Object { $_.text }) | Should -Be @('Bedingt', 'Allgemein', 'Luecke')
        # only the gaps: the general elements lead
        $g = New-WorkerPerfGuidance -Catalogue $cat8 -Facts @{ Situation = 'cpu'; Conditions = @('skipped.Prozesse', 'incident.unverified'); Values = @{} } -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu' }) -Texts $Texts
        @($g.checks.text) | Should -Be @('Allgemein 1', 'Allgemein 2', 'Luecke Prozesse', 'Luecke unbestaetigt')
    }
    It 'zaehlt genau die Bedingungen <Name> als Luecke' -TestCases @(                                    # ruling P3-R36
        @{ Name = 'unmeasured.cpu.steal'; Gap = $true }; @{ Name = 'unmeasured.input.session'; Gap = $true }; @{ Name = 'skipped.Drucken'; Gap = $true }
        @{ Name = 'cause.notmeasured'; Gap = $true }; @{ Name = 'pattern.unchecked'; Gap = $true }; @{ Name = 'incident.unverified'; Gap = $true }
        @{ Name = 'cause.nodata'; Gap = $false }; @{ Name = 'cause.none'; Gap = $false }; @{ Name = 'affected.unknown'; Gap = $false }; @{ Name = 'pattern.none'; Gap = $false }
        @{ Name = 'before'; Gap = $false }; @{ Name = 'lead.disk'; Gap = $false }; @{ Name = 'scan'; Gap = $false }
    ) {
        $cat9 = Read-WorkerPerfGuidance (New-Catalogue { $c.situations.cpu.checks = @(@{ text = 'Bedingt'; where = 'w'; sign = 's'; when = @($Name) }, @{ text = 'Allgemein'; where = 'w'; sign = 's' }) })
        $g = New-WorkerPerfGuidance -Catalogue $cat9 -Facts @{ Situation = 'cpu'; Conditions = @($Name); Values = @{} } -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu' }) -Texts $Texts
        @($g.checks.text) | Should -Be $(if ($Gap) { @('Allgemein', 'Bedingt') } else { @('Bedingt', 'Allgemein') })
    }
    It 'stellt Elemente, die nur ein zeitliches Zusammentreffen nennen, hinter die allgemeinen' {      # fix round 1, item B4
        $cat10 = Read-WorkerPerfGuidance (New-Catalogue {
                $c.situations.crash.checks = @(
                    @{ text = 'Zusammentreffen'; where = 'w'; sign = 's'; when = @('pattern.overlap') }
                    @{ text = 'Muster'; where = 'w'; sign = 's'; when = @('pattern.resource') }
                    @{ text = 'Allgemein 1'; where = 'w'; sign = 's' }
                    @{ text = 'Luecke'; where = 'w'; sign = 's'; when = @('pattern.unchecked') }
                    @{ text = 'Zusammentreffen mit Muster'; where = 'w'; sign = 's'; when = @('pattern.overlap', 'pattern.companion') }
                    @{ text = 'Zusammentreffen mit Luecke'; where = 'w'; sign = 's'; when = @('skipped.Drucken', 'pattern.overlap') }
                    @{ text = 'Allgemein 2'; where = 'w'; sign = 's' })
                $c.situations.crash.remedies = @(@{ text = 'Zusammentreffen'; precondition = 'p'; when = @('pattern.overlap') }, @{ text = 'Allgemein'; precondition = 'p' },
                    @{ text = 'Muster'; precondition = 'p'; when = @('pattern.resource') })
                $c.situations.crash.contacts = @(@{ text = 'Zusammentreffen'; when = @('pattern.overlap') }, @{ text = 'Allgemein' }) })
        $inc = New-Inc @{ type = 'ereignis'; event = @{ kind = 'crash' } }
        # the coincidence is the only pattern: the general elements lead, it is never the first thing to do
        $g = New-WorkerPerfGuidance -Catalogue $cat10 -Facts @{ Situation = 'crash'; Conditions = @('pattern.overlap'); Values = @{} } -Incident $inc -Texts $Texts
        @($g.checks.text) | Should -Be @('Allgemein 1', 'Allgemein 2', 'Zusammentreffen')
        @($g.remedies.text) | Should -Be @('Allgemein', 'Zusammentreffen')
        @($g.contacts.text) | Should -Be @('Allgemein', 'Zusammentreffen')
        # with patterns that say more and with gaps: those patterns, the general elements, then coincidence and gaps in file order;
        # a condition that says more keeps an element in front, whatever else its 'when' names
        $all = @('skipped.Drucken', 'pattern.resource', 'pattern.companion', 'pattern.overlap', 'pattern.unchecked')
        $g = New-WorkerPerfGuidance -Catalogue $cat10 -Facts @{ Situation = 'crash'; Conditions = $all; Values = @{} } -Incident $inc -Texts $Texts
        @($g.checks.text) | Should -Be @('Muster', 'Zusammentreffen mit Muster', 'Allgemein 1', 'Allgemein 2', 'Zusammentreffen', 'Luecke', 'Zusammentreffen mit Luecke')
        @($g.remedies.text) | Should -Be @('Muster', 'Allgemein', 'Zusammentreffen')
    }
    It 'stellt von den Mustern nur das Zusammentreffen mit einem Leistungsvorfall hinter die allgemeinen Elemente (<Name>)' -TestCases @(      # fix round 1, item B4
        @{ Name = 'pattern.overlap'; Late = $true }; @{ Name = 'pattern.companion'; Late = $false }; @{ Name = 'pattern.resource'; Late = $false }
        @{ Name = 'pattern.afterhang'; Late = $false }; @{ Name = 'pattern.sharedmodule'; Late = $false }; @{ Name = 'pattern.printdriver'; Late = $false }
        @{ Name = 'pattern.securitymodule'; Late = $false }; @{ Name = 'pattern.manyusers'; Late = $false }; @{ Name = 'pattern.oneuser'; Late = $false }
        @{ Name = 'pattern.none'; Late = $false }
    ) {
        $cat11 = Read-WorkerPerfGuidance (New-Catalogue { $c.situations.crash.checks = @(@{ text = 'Bedingt'; where = 'w'; sign = 's'; when = @($Name); source = 'Hersteller, Titel' },
                    @{ text = 'Allgemein'; where = 'w'; sign = 's' }) })
        $g = New-WorkerPerfGuidance -Catalogue $cat11 -Facts @{ Situation = 'crash'; Conditions = @($Name); Values = @{} } -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'crash' } }) -Texts $Texts
        @($g.checks.text) | Should -Be $(if ($Late) { @('Allgemein', 'Bedingt') } else { @('Bedingt', 'Allgemein') })
        # a coincidence is something the report found: it is not a gap
        Test-WorkerPerfGuidanceGapCondition $Name | Should -BeFalse
        Test-WorkerPerfGuidanceTrailingCondition $Name | Should -Be $Late
    }
    It 'zaehlt jede Luecke und das Zusammentreffen zu den Bedingungen, die ein Element nicht nach vorn stellen' {      # ruling P3-R36, item B4
        foreach ($n in 'unmeasured.cpu.steal', 'skipped.Drucken', 'cause.notmeasured', 'pattern.unchecked', 'incident.unverified', 'pattern.overlap') {
            Test-WorkerPerfGuidanceTrailingCondition $n | Should -BeTrue -Because $n
        }
        foreach ($n in 'cause.app', 'cause.none', 'affected.unknown', 'before', 'scan', 'lead.cpu', 'spooler.crash', 'driver.vendor.HP', 'role.Drucken') {
            Test-WorkerPerfGuidanceTrailingCondition $n | Should -BeFalse -Because $n
        }
    }
    It 'gibt die Elemente als schlichte Pipeline-Ausgabe und haelt die Listen der Anleitung als Feld' {
        $one = @(Get-WorkerPerfGuidanceItems $Cat2.situations.cpu 'checks' @() @{})
        $one.Count | Should -Be 1; $one[0] | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
        @(Get-WorkerPerfGuidanceItems $Cat2.situations.cpu 'checks' @('cause.app') @{ app = 'a'; user = 'u' }).Count | Should -Be 2
        $g = New-WorkerPerfGuidance -Catalogue $Cat2 -Facts @{ Situation = 'cpu'; Conditions = @(); Values = @{} } -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu' }) -Texts $Texts
        , $g.checks | Should -BeOfType [object[]]; $g.checks.Count | Should -Be 1; $g.checks[0].text | Should -Be 'Allgemein'
        , $g.contacts | Should -BeOfType [object[]]; $g.contacts.Count | Should -Be 1; $g.contacts[0].text | Should -Be 'Kontakt'
        $g = New-WorkerPerfGuidance -Catalogue $Cat2 -Facts @{ Situation = 'cpu'; Conditions = @('scan'); Values = @{} } -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu' }) -Texts $Texts
        $g.conditions.GetType().IsArray | Should -BeTrue; $g.conditions.Count | Should -Be 1
    }
    It 'nimmt die Werte auch als geordnetes Woerterbuch' {
        $hash = @{ app = 'EXCEL.EXE'; user = 'user003'; security = 'X'; from = '10:00'; to = '10:05'; affected = '3' }
        $ord = [ordered]@{}; foreach ($k in 'to', 'from', 'affected', 'user', 'app', 'security') { $ord[$k] = $hash[$k] }
        $facts = @{ Situation = 'cpu'; Conditions = @('cause.app', 'affected.many'); Values = $hash }
        $a = New-WorkerPerfGuidance -Catalogue $Cat2 -Facts $facts -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu' }) -Texts $Texts
        $facts.Values = $ord
        $b = New-WorkerPerfGuidance -Catalogue $Cat2 -Facts $facts -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu' }) -Texts $Texts
        @($b.checks.text) | Should -Be @('EXCEL.EXE von user003 pruefen', 'Allgemein'); $b.userView | Should -Be '3 Sitzungen waren betroffen.'
        ($b | ConvertTo-Json -Depth 6) | Should -BeExactly ($a | ConvertTo-Json -Depth 6)
    }
    It 'nennt die Fachbezeichnung <Want>' -TestCases @(
        @{ I = @{ type = 'engpass'; lead = 'profile' }; Want = 'Engpass · Profilcontainer' }
        @{ I = @{ type = 'engpass'; lead = 'memory'; chronic = $true }; Want = 'Dauerzustand · Engpass · Arbeitsspeicher' }
        @{ I = @{ type = 'ohne-engpass' }; Want = 'Verzögerung ohne Engpass' }
        @{ I = @{ type = 'ohne-engpass'; unverified = $true }; Want = 'Verzögerung ohne erkannten Engpass' }
        @{ I = @{ type = 'umfeld'; chronic = $true }; Want = 'Dauerzustand · Umfeld' }
        @{ I = @{ type = 'ereignis'; event = @{ kind = 'print' } }; Want = 'Vorfall aus Ereignissen · Druckproblem' }
        @{ I = @{ type = 'ereignis'; event = @{ kind = 'profileerror' } }; Want = 'Vorfall aus Ereignissen · Profilproblem' }
        @{ I = @{ type = 'ereignis'; event = @{ kind = 'logon' } }; Want = 'Vorfall aus Ereignissen' }
    ) {
        (New-WorkerPerfGuidance -Catalogue $Cat -Facts @{ Situation = 'fallback'; Conditions = @(); Values = @{} } -Incident (New-Inc $I) -Texts $Texts).tech | Should -Be $Want
    }
    It 'liest die Fachbezeichnung aus den Texten' {
        foreach ($k in 'type.engpass', 'type.ohne-engpass', 'type.ohne-engpass.unverified', 'type.umfeld', 'type.ereignis', 'type.chronic',
            'kind.crash', 'kind.hang', 'kind.service', 'kind.print', 'kind.profileerror', 'kind.system', 'tech.separator') { $Texts.ContainsKey($k) | Should -BeTrue -Because $k }
        $Texts['tech.separator'] | Should -BeExactly ' · '
        $t = $Texts.Clone(); $t['type.engpass'] = 'ENG'; $t['resource.cpu'] = 'PROZ'
        (New-WorkerPerfGuidance -Catalogue $Cat -Facts @{ Situation = 'cpu'; Conditions = @(); Values = @{} } -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu' }) -Texts $t).tech | Should -Be 'ENG · PROZ'
        $t['tech.separator'] = ' / '
        (New-WorkerPerfGuidance -Catalogue $Cat -Facts @{ Situation = 'cpu'; Conditions = @(); Values = @{} } -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu' }) -Texts $t).tech | Should -Be 'ENG / PROZ'
    }
    It 'waehlt die Benutzersicht <Want>' -TestCases @(
        @{ I = @{ type = 'engpass'; lead = 'cpu' }; C = @('affected.many'); V = @{ affected = '4' }; Want = '4 Sitzungen waren betroffen.' }
        @{ I = @{ type = 'engpass'; lead = 'cpu' }; C = @('affected.one'); V = @{ affected = '1' }; Want = '1 Sitzung war betroffen.' }
        @{ I = @{ type = 'engpass'; lead = 'cpu' }; C = @(); V = @{}; Want = 'Niemand war betroffen.' }
        @{ I = @{ type = 'engpass'; lead = 'cpu' }; C = @('affected.unknown'); V = @{}; Want = 'Unbekannt.' }
        @{ I = @{ type = 'engpass'; lead = 'cpu'; chronic = $true }; C = @('affected.many', 'chronic'); V = @{ affected = '4' }; Want = 'Dauerzustand.' }
        @{ I = @{ type = 'ereignis'; event = @{ kind = 'crash' } }; C = @('affected.many'); V = @{ affected = '2' }; Want = 'Viele.' }
        @{ I = @{ type = 'ereignis'; event = @{ kind = 'crash' } }; C = @('affected.one'); V = @{}; Want = 'Einer.' }
        @{ I = @{ type = 'ereignis'; event = @{ kind = 'crash' } }; C = @('affected.unknown'); V = @{}; Want = 'Unbekannt.' }
        @{ I = @{ type = 'ereignis'; event = @{ kind = 'crash' } }; C = @(); V = @{}; Want = 'Keiner.' }
        @{ I = @{ type = 'ereignis'; event = @{ kind = 'crash'; before = $true } }; C = @('affected.one', 'before'); V = @{}; Want = 'Vor der Messung.' }
        # a text whose placeholders cannot be filled: userView.unknown
        @{ I = @{ type = 'engpass'; lead = 'cpu' }; C = @('affected.many'); V = @{}; Want = 'Unbekannt.' }
        @{ I = @{ type = 'engpass'; lead = 'cpu' }; C = @('affected.one'); V = @{ user = 'user003' }; Want = 'Unbekannt.' }
    ) {
        (New-WorkerPerfGuidance -Catalogue $Cat -Facts @{ Situation = 'cpu'; Conditions = $C; Values = $V } -Incident (New-Inc $I) -Texts $Texts).userView | Should -Be $Want
    }
    It 'nennt die Fachbegriffe, die in einem Text vorkommen, in der Reihenfolge des Katalogs' {
        $cat4 = Read-WorkerPerfGuidance (New-Catalogue {
                $c.terms = [ordered]@{ 'Working Set' = 'Belegter Speicher.'; 'Handle' = 'Verweis.'; 'Paging' = 'Auslagern.'; 'Spooler' = 'Druckdienst.'; 'Latenz' = 'Antwortzeit.' }
                $c.situations.memory.meaning = 'Das paging nahm zu.'
                $c.situations.memory.checks = @(@{ text = 'Pruefen'; where = 'Spalte WORKING SET'; sign = 's' }, @{ text = 'Handle von {app}'; where = 'w'; sign = 's' })
                $c.situations.memory.remedies = @(@{ text = 'Latenz senken'; precondition = 'p'; when = @('scan') }) })
        $g = New-WorkerPerfGuidance -Catalogue $cat4 -Facts @{ Situation = 'memory'; Conditions = @(); Values = @{} } -Incident (New-Inc @{ type = 'engpass'; lead = 'memory' }) -Texts $Texts
        # 'Handle' only in a dropped check, 'Latenz' only in a remedy whose condition does not hold
        $g.terms | Should -Be @('Working Set', 'Paging')
        $g = New-WorkerPerfGuidance -Catalogue $cat4 -Facts @{ Situation = 'cpu'; Conditions = @(); Values = @{} } -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu' }) -Texts $Texts
        , $g.terms | Should -BeOfType [object[]]; $g.terms.Count | Should -Be 0
    }
    It 'findet einen Fachbegriff am Wortanfang der Vorlagen, nicht im Wort und nicht in eingesetzten Werten' {     # ruling P3-R20
        $cat6 = Read-WorkerPerfGuidance (New-Catalogue {
                $c.terms = [ordered]@{ 'Profilcontainer' = 'a'; 'Modul' = 'b'; 'RAM' = 'c'; 'C++' = 'd'; 'Kerberos' = 'e'; 'Working Set' = 'f'; 'Gerät' = 'g' }
                $c.situations.profile.meaning = 'Der Profilcontainers wuchs von {from} bis {to}.'
                $c.situations.profile.checks = @(@{ text = 'Programm {app} pruefen'; where = 'Modulname'; sign = 'Die C++-Laufzeit fehlt' }
                    @{ text = 'Arbeitsspeicher (working-set) von {user}'; where = 'w'; sign = 's'; when = @('cause.app') }) })
        $vals = @{ app = 'Kerberos RAM Gerät.exe'; user = 'Working Set'; from = '10:00'; to = '10:05' }
        $g = New-WorkerPerfGuidance -Catalogue $cat6 -Facts @{ Situation = 'profile'; Conditions = @('cause.app'); Values = $vals } -Incident (New-Inc @{ type = 'engpass'; lead = 'profile' }) -Texts $Texts
        # both checks are shown: the one inserting 'Working Set' too (its condition holds)
        @($g.checks.text) | Should -Be @('Arbeitsspeicher (working-set) von Working Set', 'Programm Kerberos RAM Gerät.exe pruefen')
        # inflected and compound forms found; RAM inside "Programm" and the terms only in inserted values not
        $g.terms | Should -Be @('Profilcontainer', 'Modul', 'C++')
        # a term is a word start in a placeholder-free template, ignoring case, also with a space and a non-ASCII letter
        $cat7 = Read-WorkerPerfGuidance (New-Catalogue {
                $c.terms = [ordered]@{ 'Working Set' = 'f'; 'Gerät' = 'g'; 'Set' = 'h' }
                $c.situations.memory.meaning = 'Das WORKING SET und die gerätetreiber.' })
        (New-WorkerPerfGuidance -Catalogue $cat7 -Facts @{ Situation = 'memory'; Conditions = @(); Values = @{} } -Incident (New-Inc @{ type = 'engpass'; lead = 'memory' }) -Texts $Texts).terms |
            Should -Be @('Working Set', 'Gerät', 'Set')
    }
}
Describe 'Rangfolge, Gruppen, Lagebild' {
    BeforeAll {
        function New-R([int]$Id, [string]$Type, [int]$Sessions, [double]$DurSec, [double]$StartSec, [int]$Sev = 2, [switch]$Chronic) {
            New-Inc @{ id = $Id; type = $Type; severity = $Sev; chronic = [bool]$Chronic; start = [long](1e12 + $StartSec * 1000); end = [long](1e12 + ($StartSec + $DurSec) * 1000)
                affected = @(1..$Sessions | Where-Object { $Sessions -gt 0 } | ForEach-Object { @{ s = $_ } }); event = @{ sessions = @(); inSession = $false; key = '' } }
        }
        function New-Ev([int]$Id, [int]$Sessions, [double]$StartSec, [hashtable]$EventFields = @{}) {
            # an event incident without duration; Sessions numbers in event.sessions
            $i = New-R $Id 'ereignis' 0 0 $StartSec
            $i.event.kind = 'crash'; $i.event.sessions = @(1..$Sessions | Where-Object { $Sessions -gt 0 })
            foreach ($k in $EventFields.Keys) { $i.event[$k] = $EventFields[$k] }
            $i
        }
    }
    It 'ordnet Engpaesse, kritische Verzoegerungen und Ereignisse vor Dauerzustaenden, dann nach Sitzungen, Dauer, Beginn' {
        $list = @((New-R 1 'umfeld' 9 600 0 -Chronic), (New-R 2 'engpass' 1 60 100), (New-R 3 'ohne-engpass' 8 90 200), (New-R 4 'ohne-engpass' 9 90 50 -Sev 1),
                  (New-R 5 'engpass' 1 90 300), (New-R 6 'engpass' 1 60 50))
        Get-WorkerPerfIncidentRanking -Incidents $list | Should -Be @(3, 5, 6, 2, 4, 1)
    }
    It 'zaehlt die Sitzungen eines Ereignisvorfalls, ordnet gleiche Werte nach Id und gibt eine leere Rangfolge ohne Vorfall' {
        $list = @((New-R 9 'engpass' 1 60 100), (New-Ev 8 2 500), (New-R 4 'engpass' 1 60 100), (New-R 7 'umfeld' 3 60 0), (New-R 6 'engpass' 2 60 0 -Chronic))
        @(Get-WorkerPerfIncidentRanking -Incidents $list) | Should -Be @(8, 4, 9, 7, 6)
        @(Get-WorkerPerfIncidentRanking -Incidents @()).Count | Should -Be 0
        @(Get-WorkerPerfIncidentRanking -Incidents @((New-R 5 'engpass' 1 60 0))) | Should -Be @(5)
    }
    It 'stellt einen Ereignisvorfall mit unbekannter Zuordnung zu Sitzungen unter die uebrigen seiner Stufe' {       # addition a)
        $list = @((New-Ev 1 3 0 @{ sessionUnknown = $true }), (New-Ev 2 2 0 @{ unchecked = @(@{ id = 'users'; category = 'Ereignisse' }) }), (New-R 3 'engpass' 0 10 900),
                  (New-Ev 4 1 0 @{ unchecked = @(@{ id = 'overlap'; category = 'Laufwerke' }) }), (New-R 5 'umfeld' 0 10 0), (New-R 6 'engpass' 4 60 0 -Chronic))
        @(Get-WorkerPerfIncidentRanking -Incidents $list) | Should -Be @(4, 3, 1, 2, 5, 6)
    }
    It 'fasst nach den zehn Karten gleiche Situation und gleichen Verursacher zusammen' {
        $list = @(1..14 | ForEach-Object { $i = New-R $_ 'engpass' 1 60 ($_ * 100); $i.main = @{ app = $(if ($_ -le 12) { 'EXCEL.EXE' } else { 'WINWORD.EXE' }); user = 'user003' }; $i.guide = @{ situation = 'cpu'; title = 'CPU ausgelastet' }; $i })
        $g = @(Get-WorkerPerfIncidentGroups -Incidents $list -Order (1..14) -Cards 10 -OffsetMinutes 0 -Texts $Texts)
        $g.Count | Should -Be 2; $g[0].ids | Should -Be @(11, 12); $g[0].label | Should -Be '2-mal CPU ausgelastet durch EXCEL.EXE von user003'
    }
    It 'fasst Vorfaelle ohne Verursacher und Ereignisvorfaelle nach ihrem Schluessel zusammen und benennt einzelne mit Titel und Uhrzeit' {   # addition f)
        $list = @(
            (New-R 1 'engpass' 1 60 0)                                                                    # a card
            $(foreach ($n in 2..4) { $i = New-R $n 'engpass' 1 60 ($n * 100); $i.cause = @{ kind = @('none', 'nodata', 'notmeasured')[$n - 2] }
                    # a main of its own each: only the cause kind can put them in one group
                    $i.main = @{ app = 'X{0}.EXE' -f $n; user = 'user00' + $n }; $i.guide = @{ situation = 'cpu'; title = 'CPU ausgelastet' }; $i })
            $(foreach ($n in 5, 6) { $i = New-Ev $n 1 ($n * 100) @{ key = 'EXCEL.EXE' }; $i.guide = @{ situation = 'crash'; title = 'Programm abgestuerzt' }; $i })
            $(& { $i = New-Ev 7 1 700 @{ key = 'WINWORD.EXE' }; $i.guide = @{ situation = 'crash'; title = 'Programm abgestuerzt' }; $i })
            $(& { $i = New-R 8 'engpass' 1 60 800; $i.main = @{ app = 'EXCEL.EXE'; user = 'user003' }; $i.guide = @{ situation = 'memory'; title = 'Speicher knapp' }; $i })
            $(& { $i = New-R 9 'engpass' 1 60 900; $i.main = @{ app = 'EXCEL.EXE' }; $i.guide = @{ situation = 'memory'; title = 'Speicher knapp' }; $i }))
        $list[0].guide = @{ situation = 'cpu'; title = 'CPU ausgelastet' }
        $g = @(Get-WorkerPerfIncidentGroups -Incidents $list -Order @(1, 8, 2, 5, 3, 7, 6, 4, 9) -Cards 1 -OffsetMinutes 0 -Texts $Texts)
        @($g | ForEach-Object { , @($_.ids) }) | ForEach-Object { $_ -join ',' } | Should -Be @('8', '2,3,4', '5,6', '7', '9')
        @($g.situation) | Should -Be @('memory', 'cpu', 'crash', 'crash', 'memory')
        # 1e12 ms is 01:46:40 UTC; without an offset the clock time is UTC, with one the server's
        @($g.label) | Should -Be @('Speicher knapp, 02:00', '3-mal CPU ausgelastet', '2-mal Programm abgestuerzt durch EXCEL.EXE', 'Programm abgestuerzt, 01:58', 'Speicher knapp, 02:01')
        @(Get-WorkerPerfIncidentGroups -Incidents $list -Order @(1, 8, 2, 5, 3, 7, 6, 4, 9) -Cards 1 -OffsetMinutes 60 -Texts $Texts)[0].label | Should -Be 'Speicher knapp, 03:00'
        # all on cards, or no incident: no group
        @(Get-WorkerPerfIncidentGroups -Incidents $list -Order @(1, 8, 2, 5, 3, 7, 6, 4, 9) -Cards 10 -OffsetMinutes 0 -Texts $Texts).Count | Should -Be 0
        @(Get-WorkerPerfIncidentGroups -Incidents @() -Order @() -Cards 10 -OffsetMinutes 0 -Texts $Texts).Count | Should -Be 0
        $one = @(Get-WorkerPerfIncidentGroups -Incidents $list -Order @(1, 8, 2, 5, 3, 7, 6, 4, 9) -Cards 8 -OffsetMinutes 0 -Texts $Texts)
        $one.Count | Should -Be 1; , $one[0].ids | Should -BeOfType [object[]]; $one[0].ids | Should -Be @(9); @($one[0].Keys) | Should -Be @('label', 'situation', 'ids')
    }
    It 'nimmt ein doppeltes Id der Rangfolge einmal und die Woerter der Bezeichnung aus den Texten' {    # carried c1, c4
        $list = @(1..4 | ForEach-Object { $i = New-R $_ 'engpass' 1 60 ($_ * 100); $i.main = @{ app = 'EXCEL.EXE'; user = 'user003' }; $i.guide = @{ situation = 'cpu'; title = 'CPU ausgelastet' }; $i })
        $g = @(Get-WorkerPerfIncidentGroups -Incidents $list -Order @(1, 2, 2, 3, 1, 3) -Cards 1 -OffsetMinutes 0 -Texts $Texts)
        $g.Count | Should -Be 1; $g[0].ids | Should -Be @(2, 3); $g[0].label | Should -Be '2-mal CPU ausgelastet durch EXCEL.EXE von user003'
        $t = $Texts.Clone(); $t['group.times'] = '{0}x {1}'; $t['group.by'] = ' wegen {0}'; $t['group.of'] = ' bei {0}'; $t['group.at'] = '{0} um {1}'
        @(Get-WorkerPerfIncidentGroups -Incidents $list -Order @(1, 2, 3) -Cards 1 -OffsetMinutes 0 -Texts $t)[0].label | Should -Be '2x CPU ausgelastet wegen EXCEL.EXE bei user003'
        @(Get-WorkerPerfIncidentGroups -Incidents $list -Order @(1, 2, 3, 4) -Cards 3 -OffsetMinutes 0 -Texts $t)[0].label | Should -Be 'CPU ausgelastet um 01:53'
    }
    It 'bildet Zustand und Kennzahlen; ueberlappende Fenster zaehlen einmal, ein Ereignis ohne Dauer mit 0' {   # Review Focus 5
        # the event without duration lies outside every other window: it adds nothing (not a lead or lag of its own)
        $e = New-R 7 'ereignis' 0 0 600; $e.event.inSession = $true
        $l = Get-WorkerPerfLagebild -Incidents @((New-R 2 'engpass' 1 120 0), (New-R 3 'ohne-engpass' 2 120 60), $e, (New-R 1 'umfeld' 1 3600 0 -Chronic)) -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts
        $l.state | Should -Be 'red'; $l.word | Should -Be 'kritisch'; $l.kpis.bottlenecks | Should -Be 1; $l.kpis.delays | Should -Be 1; $l.kpis.events | Should -Be 1
        $l.kpis.chronic | Should -Be 1; $l.kpis.minutes | Should -Be 3; $l.top | Should -Be 3                     # die kritische Verzoegerung mit zwei Sitzungen steht vorn
        (Get-WorkerPerfLagebild -Incidents @((New-R 1 'umfeld' 1 3600 0 -Chronic)) -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts).state | Should -Be 'yellow'
        $g = Get-WorkerPerfLagebild -Incidents @() -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts; $g.state | Should -Be 'green'; $g.sentence | Should -Be 'Keine Störung erkannt.'
    }
    It 'gibt Symbol, Wort und Satz je Zustand und alle Felder' {
        $l = Get-WorkerPerfLagebild -Incidents @((New-R 2 'engpass' 1 120 0), (New-R 3 'ohne-engpass' 2 120 600)) -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts
        @($l.Keys) | Should -Be @('state', 'symbol', 'word', 'sentence', 'kpis', 'hints', 'top')
        @($l.kpis.Keys) | Should -Be @('bottlenecks', 'delays', 'delaysUnverified', 'events', 'chronic', 'minutes')
        $l.symbol | Should -Be ([string][char]0x25C6); $l.sentence | Should -Be 'Rot: 1 Engpaesse, 1 Verzoegerungen, 0 Ereignisse, 0 Dauerzustaende.'; $l.kpis.minutes | Should -Be 4; $l.kpis.minutes | Should -BeOfType [double]
        , $l.hints | Should -BeOfType [string[]]; $l.hints.Count | Should -Be 0
        # yellow: a delay of severity 1, an event outside a session, a chronic bottleneck
        $ev = New-Ev 4 0 10; $ev.severity = 1
        $y = Get-WorkerPerfLagebild -Incidents @((New-R 1 'ohne-engpass' 1 90 0 -Sev 1), $ev, (New-R 5 'engpass' 3 600 0 -Chronic), (New-R 6 'umfeld' 1 30 100)) -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts
        $y.state | Should -Be 'yellow'; $y.symbol | Should -Be ([string][char]0x25B2); $y.word | Should -Be ('auff' + [char]0xE4 + 'llig'); $y.sentence | Should -Be 'Gelb: 2 Verzoegerungen, 1 Ereignisse, 1 Dauerzustaende.'    # no bottleneck part: there is none in this state
        $y.kpis.bottlenecks | Should -Be 0; $y.kpis.delays | Should -Be 2; $y.kpis.events | Should -Be 1; $y.kpis.chronic | Should -Be 1; $y.kpis.minutes | Should -Be 2
        $y.top | Should -Be 4                                                                     # an event incident stands in the first class
        $g = Get-WorkerPerfLagebild -Incidents @() -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts
        $g.symbol | Should -Be ([string][char]0x25CF); $g.word | Should -Be 'normal'; $null -eq $g.top | Should -BeTrue; $g.kpis.minutes | Should -Be 0
        # minutes on one decimal
        (Get-WorkerPerfLagebild -Incidents @((New-R 2 'engpass' 1 77 0)) -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts).kpis.minutes | Should -Be 1.3
    }
    It 'zaehlt die Verzoegerungen ohne erkannten Engpass' {                                           # addition d)
        $a = New-R 1 'ohne-engpass' 1 60 0; $a.unverified = $true
        $b = New-R 2 'umfeld' 1 60 100; $b.unverified = $true
        $c2 = New-R 3 'ohne-engpass' 1 60 200 -Chronic; $c2.unverified = $true
        $l = Get-WorkerPerfLagebild -Incidents @($a, $b, $c2, (New-R 4 'ohne-engpass' 1 60 300)) -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts
        $l.kpis.delays | Should -Be 3; $l.kpis.delaysUnverified | Should -Be 2
    }
    It 'nennt im gruenen Zustand ohne Ereignisse den Vorbehalt' {                                     # addition c)
        # the events count as not measured by the place of the report data, as for the key figure of the page (places 'events')
        $ctx = New-Ctx; $ctx.Data.skipped = @([ordered]@{ id = 'Laufwerke'; label = 'Laufwerke'; text = ''; places = @('volumes') }, [ordered]@{ id = 'Ereignisse'; label = 'Ereignisse'; text = ''; places = @('events', 'sessions.events') })
        (Get-WorkerPerfLagebild -Incidents @() -Data $ctx.Data -Catalogue $Cat -Texts $Texts).sentence | Should -Be 'Keine Störung erkannt; nicht erfasst: Laufwerke, Ereignisse.'
        $ctx.Data.skipped = @([ordered]@{ id = 'Laufwerke'; label = 'Laufwerke'; text = ''; places = @() })
        (Get-WorkerPerfLagebild -Incidents @() -Data $ctx.Data -Catalogue $Cat -Texts $Texts).sentence | Should -Be 'Keine Störung erkannt.'
    }
    It 'laesst im roten und gelben Satz den Teil einer nicht gemessenen Kategorie weg und nennt den Vorbehalt' {   # ruling P3-R49
        # the skipped entries as the report data carry them: the places of the category table
        $skip = { param([string[]]$Ids) @(foreach ($id in $Ids) { [ordered]@{ id = $id; label = $id; text = ''; places = [string[]]@($script:WorkerPerfCategories[$id].Places) } }) }
        $say = { param($Incidents, [string[]]$Ids) $ctx = New-Ctx; $ctx.Data.skipped = @(& $skip $Ids); Get-WorkerPerfLagebild -Incidents $Incidents -Data $ctx.Data -Catalogue $Cat -Texts $Texts }
        $red = @((New-R 2 'engpass' 1 120 0), (New-R 3 'ohne-engpass' 2 120 600))
        # everything measured: every part, also one that counts nothing
        (& $say $red @()).sentence | Should -Be 'Rot: 1 Engpaesse, 1 Verzoegerungen, 0 Ereignisse, 0 Dauerzustaende.'
        # without events: no "0 Ereignisse", and the reservation; the key figure stays (the page writes "nicht gemessen" there)
        $l = & $say $red @('Ereignisse')
        $l.sentence | Should -Be 'Rot: 1 Engpaesse, 1 Verzoegerungen, 0 Dauerzustaende. Nicht gemessen: Ereignisse.'
        $l.kpis.events | Should -Be 0; $l.kpis.chronic | Should -Be 0; @($l.kpis.Keys) | Should -Be @('bottlenecks', 'delays', 'delaysUnverified', 'events', 'chronic', 'minutes')
        $l.hints | Should -Be @('Abgeschaltet: Ereignisse.')
        # without Citrix a chronic state of the connection cannot be found: no "0 Dauerzustaende"
        (& $say $red @('Citrix')).sentence | Should -Be 'Rot: 1 Engpaesse, 1 Verzoegerungen, 0 Ereignisse. Nicht gemessen: Citrix.'
        # both: the reservation names every category left out, as the green sentence does
        (& $say $red @('Prozesse', 'Citrix', 'Ereignisse')).sentence | Should -Be 'Rot: 1 Engpaesse, 1 Verzoegerungen. Nicht gemessen: Prozesse, Citrix, Ereignisse.'
        (& $say $red $script:WorkerPerfCategories.Keys).sentence | Should -Match '^Rot: 1 Engpaesse, 1 Verzoegerungen\. Nicht gemessen: Prozesse, Laufwerke, Citrix, Ereignisse, Rueckblick, Drucken, Gegenstellen, Zustand\.$'
        # a category no part depends on: the sentence of a complete capture
        (& $say $red @('Prozesse', 'Laufwerke', 'Rueckblick', 'Drucken', 'Gegenstellen')).sentence | Should -Be 'Rot: 1 Engpaesse, 1 Verzoegerungen, 0 Ereignisse, 0 Dauerzustaende.'
        # a real count stays, although its category was left out: a chronic bottleneck without Citrix, an event incident
        (& $say ($red + (New-R 5 'engpass' 3 600 0 -Chronic)) @('Citrix')).sentence | Should -Be 'Rot: 1 Engpaesse, 1 Verzoegerungen, 0 Ereignisse, 1 Dauerzustaende.'
        (& $say ($red + (New-Ev 7 0 900)) @('Ereignisse')).sentence | Should -Be 'Rot: 1 Engpaesse, 1 Verzoegerungen, 1 Ereignisse, 0 Dauerzustaende.'
        (& $say ($red + (New-Ev 7 0 900)) @('Ereignisse', 'Citrix')).sentence | Should -Be 'Rot: 1 Engpaesse, 1 Verzoegerungen, 1 Ereignisse. Nicht gemessen: Ereignisse, Citrix.'
        # yellow: the same rule
        $yellow = @((New-R 1 'ohne-engpass' 1 90 0 -Sev 1))
        (& $say $yellow @()).sentence | Should -Be 'Gelb: 1 Verzoegerungen, 0 Ereignisse, 0 Dauerzustaende.'
        (& $say $yellow @('Ereignisse')).sentence | Should -Be 'Gelb: 1 Verzoegerungen, 0 Dauerzustaende. Nicht gemessen: Ereignisse.'
        (& $say $yellow @('Citrix', 'Ereignisse')).sentence | Should -Be 'Gelb: 1 Verzoegerungen. Nicht gemessen: Citrix, Ereignisse.'
        # the place decides, not the name of the category
        $ctx = New-Ctx; $ctx.Data.skipped = @([ordered]@{ id = 'Ereignisse'; label = 'Ereignisse'; text = ''; places = @() })
        (Get-WorkerPerfLagebild -Incidents $red -Data $ctx.Data -Catalogue $Cat -Texts $Texts).sentence | Should -Be 'Rot: 1 Engpaesse, 1 Verzoegerungen, 0 Ereignisse, 0 Dauerzustaende.'
        $script:WorkerPerfLagebildParts | ForEach-Object { $_.Place } | Should -Be @('', '', 'events', 'citrix')
        # fix round 4, C2: the placeholder of a part's count stands under Value; no key shares its name with a property of the table
        $script:WorkerPerfLagebildParts | ForEach-Object { $_.Value } | Should -Be @('bottlenecks', 'delays', 'events', 'chronic')
        foreach ($part in $script:WorkerPerfLagebildParts) {
            @($part.Keys | Sort-Object) | Should -Be @('Key', 'Place', 'States', 'Value')
            foreach ($k in $part.Keys) { [hashtable].GetProperty($k) | Should -BeNullOrEmpty -Because "Schluessel $k" }
            # the value is the placeholder the part's text of the catalogue may hold
            $script:WorkerPerfGuidanceTextPlaceholders['lagebild.' + $part.Key] | Should -Be @($part.Value)
        }
        # the summary to copy carries the same sentence
        $l = & $say $red @('Ereignisse'); $ctx = New-Ctx; $ctx.Data.skipped = @(& $skip @('Ereignisse'))
        $p = @(Get-WorkerPerfCopySummaryParagraphs -Incidents @() -Order @() -Lagebild $l -Data $ctx.Data -Catalogue $Cat -Texts $Texts)
        $p[1] | Should -Be ($l.symbol + ' ' + $l.word + ': Rot: 1 Engpaesse, 1 Verzoegerungen, 0 Dauerzustaende. Nicht gemessen: Ereignisse.')
    }
    It 'gibt die Hinweise zur Messung in ihrer Reihenfolge' {                                          # addition b)
        $ctx = New-Ctx
        $ctx.Data.sollIst = @([ordered]@{ id = 'cpu.host'; label = 'CPU'; measured = $true; detail = '' }
            [ordered]@{ id = 'disk.latency'; label = 'Latenz'; measured = $false; detail = (Get-WorkerPerfSkipDetail @('Laufwerke')) }
            [ordered]@{ id = 'ica.rtt'; label = 'ICA Round Trip'; measured = $false; detail = 'Zaehler fehlt' }
            [ordered]@{ id = 'input.session'; label = 'Eingabeverzoegerung'; measured = $false; detail = '' })
        $ctx.Data.skipped = @([ordered]@{ id = 'Laufwerke'; label = 'Laufwerke'; text = ''; places = @() }, [ordered]@{ id = 'Drucken'; label = 'Drucken'; text = ''; places = @() })
        $ctx.Data.meta.endReason = 'error'; $ctx.Data.meta.endMessage = 'Platte voll'
        $l = Get-WorkerPerfLagebild -Incidents @() -Data $ctx.Data -Catalogue $Cat -Texts $Texts
        # what was left out on purpose before what could not be measured (ruling P3-R28)
        $l.hints | Should -Be @('Abgeschaltet: Laufwerke, Drucken.', 'Nicht gemessen: ICA Round Trip, Eingabeverzoegerung.', 'Fehler: Platte voll')
        $ctx.Data.meta.endMessage = ''
        (Get-WorkerPerfLagebild -Incidents @() -Data $ctx.Data -Catalogue $Cat -Texts $Texts).hints[-1] | Should -Be 'Fehler.'
        $ctx.Data.meta.Remove('endMessage')
        (Get-WorkerPerfLagebild -Incidents @() -Data $ctx.Data -Catalogue $Cat -Texts $Texts).hints[-1] | Should -Be 'Fehler.'
        # only skipped signals missing: no unmeasured hint
        $ctx = New-Ctx; $ctx.Data.sollIst = @([ordered]@{ id = 'disk.latency'; label = 'Latenz'; measured = $false; detail = (Get-WorkerPerfSkipDetail @('Laufwerke')) })
        $ctx.Data.skipped = @([ordered]@{ id = 'Laufwerke'; label = 'Laufwerke'; text = ''; places = @() })
        (Get-WorkerPerfLagebild -Incidents @() -Data $ctx.Data -Catalogue $Cat -Texts $Texts).hints | Should -Be @('Abgeschaltet: Laufwerke.')
    }
    It 'nennt eine nicht gemessene Zeile ohne Beschriftung mit ihrer Kennung' {                       # carried c6
        $ctx = New-Ctx; $ctx.Data.sollIst = @([ordered]@{ id = 'x.signal'; measured = $false; detail = 'Zaehler fehlt' }, [ordered]@{ id = 'y.signal'; label = ''; measured = $false; detail = '' })
        (Get-WorkerPerfLagebild -Incidents @() -Data $ctx.Data -Catalogue $Cat -Texts $Texts).hints | Should -Be @('Nicht gemessen: x.signal, y.signal.')
    }
    It 'wird rot durch <Name> allein' -TestCases @(                                                  # carried c7
        @{ Name = 'einen Ereignisvorfall in einer Sitzung'; Make = { $e = New-Ev 1 1 0; $e.event.inSession = $true; $e }; Want = 'red' }
        @{ Name = 'eine kritische Verzoegerung'; Make = { New-R 1 'ohne-engpass' 1 60 0 -Sev 2 }; Want = 'red' }
        @{ Name = 'nichts: Ereignisvorfall ausserhalb einer Sitzung'; Make = { New-Ev 1 0 0 }; Want = 'yellow' }
        @{ Name = 'nichts: Verzoegerung der Stufe 1'; Make = { New-R 1 'ohne-engpass' 1 60 0 -Sev 1 }; Want = 'yellow' }
    ) {
        (Get-WorkerPerfLagebild -Incidents @(& $Make) -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts).state | Should -Be $Want
    }
    It 'nimmt Zustandswort und Symbol aus den Texten und verlangt sie' {                              # carried c1
        $t = $Texts.Clone(); $t['state.red.word'] = 'ROT'; $t['state.red.symbol'] = '#'; $t['state.green.word'] = 'GRUEN'
        $l = Get-WorkerPerfLagebild -Incidents @((New-R 2 'engpass' 1 60 0)) -Data (New-Ctx).Data -Catalogue $Cat -Texts $t
        $l.word | Should -Be 'ROT'; $l.symbol | Should -Be '#'
        (Get-WorkerPerfLagebild -Incidents @() -Data (New-Ctx).Data -Catalogue $Cat -Texts $t).word | Should -Be 'GRUEN'
        $Texts['state.red.symbol'] | Should -Be ([string][char]0x25C6); $Texts['state.yellow.symbol'] | Should -Be ([string][char]0x25B2); $Texts['state.green.symbol'] | Should -Be ([string][char]0x25CF)
        $Texts['state.red.word'] | Should -Be 'kritisch'; $Texts['state.yellow.word'] | Should -Be ('auff' + [char]0xE4 + 'llig'); $Texts['state.green.word'] | Should -Be 'normal'
        $t.Remove('state.yellow.word')
        { Get-WorkerPerfLagebild -Incidents @((New-R 2 'umfeld' 1 60 0)) -Data (New-Ctx).Data -Catalogue $Cat -Texts $t } | Should -Throw "*'state.yellow.word'*"
        foreach ($f in 'Get-WorkerPerfLagebild', 'Get-WorkerPerfIncidentGroups') {
            @((Get-Command $f).Parameters['Texts'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count | Should -Be 1 -Because $f
        }
        @((Get-Command Get-WorkerPerfIncidentGroups).Parameters['OffsetMinutes'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count | Should -Be 1   # carried c3
    }
    It 'haelt deutsche Woerter und Zustandssymbole aus dem Code' {                                    # carried c1, ruling P3-R27
        $src = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../src/WorkerPerf.Guidance.ps1'))
        foreach ($p in '0x25C6', '0x25B2', '0x25CF', '0x00E4', '0x2013', "'kritisch'", "'normal'", '-mal', "' durch '", "' von '") { $src.Contains($p) | Should -BeFalse -Because $p }
    }
    It 'nennt im Fehler den Teil des Katalogs, dessen Text sie fuellt' {                             # carried c5
        { Format-WorkerPerfGuidancePart $Cat 'hints' 'error' @{} } | Should -Throw "Catalogue text 'hints.error' has no value for the placeholder '{message}'."
        { Format-WorkerPerfGuidancePart $Cat 'copy' 'fehlt' @{} } | Should -Throw "Catalogue text 'copy.fehlt' is missing."
    }
    It 'nennt fuer das Ende <Name> die Hinweise <Want>' -TestCases @(
        @{ Name = 'duration'; Reason = 'duration'; Want = @() }; @{ Name = 'interrupted'; Reason = 'interrupted'; Want = @() }; @{ Name = 'stopflag'; Reason = 'stopflag'; Want = @() }
        @{ Name = 'diskspace'; Reason = 'diskspace'; Want = @('Angehalten.') }; @{ Name = 'maxsize'; Reason = 'maxsize'; Want = @('Angehalten.') }
        @{ Name = '(leer)'; Reason = ''; Want = @('Nicht beendet.') }; @{ Name = '(null)'; Reason = $null; Want = @('Nicht beendet.') }; @{ Name = '(fehlt)'; Reason = '-'; Want = @('Nicht beendet.') }
    ) {                                                                                                # rulings P3-R5, P3-R6
        $ctx = New-Ctx
        if ($Reason -eq '-') { $ctx.Data.meta.Remove('endReason') } else { $ctx.Data.meta.endReason = $Reason }
        $h = (Get-WorkerPerfLagebild -Incidents @() -Data $ctx.Data -Catalogue $Cat -Texts $Texts).hints
        , $h | Should -BeOfType [string[]]; @($h) | Should -Be $Want
    }
    It 'fuellt Satz und Hinweise mit den Platzhaltern des Lagebilds und meldet einen fehlenden Wert' {   # addition e)
        $cat = Read-WorkerPerfGuidance (New-Catalogue { $c.lagebild.red = '{incidents} Vorfaelle: {parts}, {minutes} min.'; $c.lagebild.partSeparator = '/'
                $c.lagebild.partBottlenecks = '{bottlenecks}'; $c.lagebild.partDelays = '{delays}'; $c.lagebild.partEvents = '{events}'; $c.lagebild.partChronic = '{chronic}' })
        $ctx = New-Ctx
        $l = Get-WorkerPerfLagebild -Incidents @((New-R 2 'engpass' 1 77 0), (New-R 3 'umfeld' 1 3600 0 -Chronic)) -Data $ctx.Data -Catalogue $cat -Texts $Texts
        $l.sentence | Should -Be '2 Vorfaelle: 1/0/0/1, 1,3 min.'
        # texts the loader rejects (ruling P3-R26), set after loading: a value the summary does not have stops it
        $cat.lagebild.red = '{incidents} Vorfaelle auf {server} am {date}.'; $cat.lagebild.yellow = 'Gelb auf {server}, {skipped}.'; $cat.hints.notFinished = 'Auf {server} nicht beendet ({message}).'
        (Get-WorkerPerfLagebild -Incidents @((New-R 2 'engpass' 1 77 0)) -Data $ctx.Data -Catalogue $cat -Texts $Texts).sentence | Should -Be '1 Vorfaelle auf SIM-VDA01 am 09.09.2001.'
        { Get-WorkerPerfLagebild -Incidents @((New-R 3 'umfeld' 1 3600 0 -Chronic)) -Data $ctx.Data -Catalogue $cat -Texts $Texts } | Should -Throw "*'lagebild.yellow'*'{skipped}'*"
        $ctx.Data.meta.endReason = ''
        { Get-WorkerPerfLagebild -Incidents @() -Data $ctx.Data -Catalogue $cat -Texts $Texts } | Should -Throw "*'hints.notFinished'*'{message}'*"
        $ctx = New-Ctx; $ctx.Data.meta.computer = ''
        { Get-WorkerPerfLagebild -Incidents @((New-R 2 'engpass' 1 77 0)) -Data $ctx.Data -Catalogue $cat -Texts $Texts } | Should -Throw "*'lagebild.red'*'{server}'*"
    }
}
Describe 'Kopiertexte' {
    BeforeAll {
        # a recorded run with a person's name, for a real mask of level Alles (as tests/Mask.Tests.ps1 builds one)
        . (Join-Path $PSScriptRoot 'LoadHelpers.ps1')
        $copyRun = Write-TestRun 'copy-mask' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'sessions.csv' = @('0,2,schoenberger,TESTDOM,Active,ICA-1,WS-0042,,0')
            'procinfo.csv' = @('0,100,1,EXCEL.EXE,2,,C:\Program Files\x.exe,,') }
        $script:CopyMask = New-WorkerPerfMask -Path $copyRun -Level 'Alles' -Texts $Texts
        function New-CpuInc {
            New-Inc @{ id = 2; type = 'engpass'; lead = 'cpu'; start = 1e12; end = 1e12 + 120000; affected = @(@{ s = 0 }, @{ s = 1 })
                signals = @(@{ id = 'cpu.host'; resource = 'cpu'; peak = 99.5; unit = '%'; ideal = 'unter 75 %'; severity = 2 })
                main = @{ app = 'EXCEL.EXE'; user = 'user003'; sharePct = 62; baselinePct = 4 }; cause = @{ kind = 'main'; measure = 'cpu' }
                causeText = 'Hauptverursacher: EXCEL.EXE in der Sitzung von user003 mit 62 % der CPU-Zeit (sonst 4 %).' }
        }
        function New-CopyGuide($Incident, $Ctx = (New-Ctx)) {
            New-WorkerPerfGuidance -Catalogue $Cat -Facts (Get-WorkerPerfGuidanceFacts -Incident $Incident -Context $Ctx -Catalogue $Cat) -Incident $Incident -Texts $Texts
        }
    }
    It 'haelt 78 Zeichen ein und verliert nichts, auch bei langen Namen' {                         # Review Focus 4
        $long = '\\' + ('s' * 60) + '\' + ('f' * 60)
        $t = Format-WorkerPerfCopyLines @("1. Freigabe $long pruefen und die Antwortzeit mit dem Soll vergleichen", '- kurz')
        @($t -split "`r`n" | Where-Object { $_.Length -gt 78 }).Count | Should -Be 0
        ($t -replace "`r`n\s*", '') | Should -Match ([regex]::Escape($long)); ($t -split "`r`n")[1] | Should -Match '^   '
    }
    It 'stimmt inhaltlich mit der Vorfallsansicht ueberein' {
        $i = New-CpuInc
        $g = New-WorkerPerfGuidance -Catalogue $Cat -Facts (Get-WorkerPerfGuidanceFacts -Incident $i -Context (New-Ctx) -Catalogue $Cat) -Incident $i -Texts $Texts
        # -Texts: the cause sentence and the words of the steps come from texts.de.json (ruling P3-R27 for Lagebild and groups)
        $t = New-WorkerPerfCopyText -Incident $i -Guide $g -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts
        # '100 %', not the plan's '99,5 %': the value as the guidance's facts write it (Format-WorkerPerfValue, whole from 10 on; ruling P3-R1)
        foreach ($part in $g.title, $g.impact, $g.checks[0].text, 'EXCEL.EXE', '100 %', 'unter 75 %', $Cat.copy.checks) { ($t -replace "`r`n\s*", ' ') | Should -Match ([regex]::Escape($part)) }
        if (@($g.remedies).Count) { $t | Should -Match ([regex]::Escape($Cat.copy.remedies)) }
    }
    It 'bricht mit CR LF um, rueckt zweistellige Nummern ein und zaehlt Zeichen' {                   # addition e)
        $words = @(1..30 | ForEach-Object { 'Wort{0:00}' -f $_ }) -join ' '
        $t = Format-WorkerPerfCopyLines @("10. $words", '', "- $words", ([string][char]0xE4 * 78), "Kopf $words")
        $lines = Get-Lines $t
        ($t -replace "`r`n", '').Contains("`n") | Should -BeFalse; ($t -replace "`r`n", '').Contains("`r") | Should -BeFalse
        @($lines | Where-Object { $_.Length -gt 78 }).Count | Should -Be 0
        $lines[0] | Should -Match '^10\. Wort01 '; $lines[1] | Should -Match '^    Wort\d\d'; $lines[1] | Should -Not -Match '^     '
        $empty = [array]::IndexOf($lines, ''); $empty | Should -BeGreaterThan 1
        $lines[$empty + 1] | Should -Match '^- Wort01'; $lines[$empty + 2] | Should -Match '^  Wort\d\d'
        $umlaut = @($lines | Where-Object { $_ -match '^\p{L}+$' -and $_[0] -eq [char]0xE4 }); $umlaut.Count | Should -Be 1; $umlaut[0].Length | Should -Be 78
        $last = @($lines | Where-Object { $_ -like 'Kopf *' })[0]; $lines[[array]::IndexOf($lines, $last) + 1] | Should -Match '^Wort'
        (Join-Copy $t).Contains($words) | Should -BeTrue
        # a word longer than the width on a line of its own, and another width
        $t = Format-WorkerPerfCopyLines @(('x' * 100) + ' y') -Width 40
        (Get-Lines $t) | Should -Be @(('x' * 40), ('x' * 40), (('x' * 20) + ' y'))
        # a number and its unit stay on one line
        $t = Format-WorkerPerfCopyLines @(('x' * 74) + ' 63 % der CPU-Zeit (sonst 4 %).', ('y' * 73) + ' 225 ms, Soll')
        @((Get-Lines $t) | Where-Object { $_ -match '^(%|ms)' }).Count | Should -Be 0; (Get-Lines $t) | Should -Contain '63 % der CPU-Zeit (sonst 4 %).'
        Format-WorkerPerfCopyLines @() | Should -BeExactly ''
    }
    It 'laesst eine Zahl beim Wort davor und ein Listenzeichen nie allein' {                            # ruling P3-R33
        # a bare number (with punctuation) stays with the word before it: no continuation line starts like a step
        $t = Format-WorkerPerfCopyLines @(('x' * 70) + ' Vorfall 3. Nicht geprueft.', ('y' * 59) + ' Kollegen Benutzer 03 mit 63 % der CPU-Zeit.', ('z' * 71) + ' Werte 12, 13')
        $lines = Get-Lines $t
        @($lines | Where-Object { $_.Length -gt 78 }).Count | Should -Be 0
        @($lines | Where-Object { $_ -match '^\s*\d' }).Count | Should -Be 0
        $lines | Should -Contain 'Vorfall 3. Nicht geprueft.'; $lines | Should -Contain 'Benutzer 03 mit 63 % der CPU-Zeit.'; $lines | Should -Contain 'Werte 12, 13'
        (Join-Copy $t).Contains('Kollegen Benutzer 03 mit 63 % der CPU-Zeit.') | Should -BeTrue
        # a joined group is only formed while it fits on a line: a word that fills the line keeps its number off it
        # rather than being split hard, and a unit that does not fit with the group takes its number to the next line
        (Get-Lines (Format-WorkerPerfCopyLines @(('x' * 77) + ' 3. Ende'))) | Should -Be @(('x' * 77), '3. Ende')
        (Get-Lines (Format-WorkerPerfCopyLines @(('w' * 74) + ' 63 % Ende'))) | Should -Be @(('w' * 74), '63 % Ende')
        (Get-Lines (Format-WorkerPerfCopyLines @(('v' * 72) + ' 63 % Ende'))) | Should -Be @((('v' * 72) + ' 63 %'), 'Ende')
        # a label with a word longer than the rest of the line: the word is split on the label's line
        $long = 'p' * 90
        $lines = Get-Lines (Format-WorkerPerfCopyLines @("1. $long Ende", ('- \\' + ('s' * 80))))
        $lines | Should -Be @(('1. ' + ('p' * 75)), ('   ' + ('p' * 15) + ' Ende'), ('- \\' + ('s' * 74)), ('  ' + ('s' * 6)))
        @($lines | Where-Object { $_.Length -gt 78 }).Count | Should -Be 0
        Format-WorkerPerfCopyLines @("Zeile`r`nmit`nUmbruch") | Should -BeExactly 'Zeile mit Umbruch'
    }
    It 'setzt den Text eines Vorfalls aus Absaetzen in fester Reihenfolge zusammen' {
        $i = New-CpuInc; $g = New-CopyGuide $i
        $p = @(Get-WorkerPerfCopyParagraphs -Incident $i -Guide $g -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts)
        $dash = [string][char]0x2013
        $p | Should -Be @('WorkerPerf SIM-VDA01, 09.09.2001', "02:46${dash}02:48 (2 Minuten): Titel cpu (Engpass · CPU)", '2 Sitzungen waren betroffen.', 'Langsam.', 'Messwert: 100 %, Soll unter 75 %'
            'Verursacher: Hauptverursacher: EXCEL.EXE in der Sitzung von user003 mit 62 % der CPU-Zeit (sonst 4 %).', 'Betroffen: 2', ''
            'Empfohlene Pruefschritte:', "1. Pruefen ${dash} Ort; erkennbar an Merkmal", '', 'Moegliche Abhilfe (Vorschlag):', '- Wenn Voraussetzung: Abhelfen', '', 'Ansprechpartner:', '- Kontakt')
        $t = New-WorkerPerfCopyText -Incident $i -Guide $g -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts
        $t | Should -BeExactly (Format-WorkerPerfCopyLines $p)
        # the users of the affected sessions
        $ctx = New-Ctx; $ctx.Data.sessions = @(@{ i = 0; id = 2; user = 'user001' }, @{ i = 1; id = 3; user = 'user002' })
        @(Get-WorkerPerfCopyParagraphs -Incident $i -Guide $g -Data $ctx.Data -Catalogue $Cat -Texts $Texts) | Should -Contain 'Betroffen: 2 (user001, user002)'
        # without remedies and contacts: neither label
        $g.remedies = @(); $g.contacts = @()
        $p = @(Get-WorkerPerfCopyParagraphs -Incident $i -Guide $g -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts)
        $p[-1] | Should -Be "1. Pruefen ${dash} Ort; erkennbar an Merkmal"; $p | Should -Not -Contain $Cat.copy.remedies
        # a chronic state without affected sessions names none, as its sentence (Get-WorkerPerfIncidentText) does
        $i = New-Inc @{ type = 'umfeld'; chronic = $true; start = 1e12; end = 1e12 + 3600000; signals = @(@{ id = 'ica.rtt'; resource = 'network'; peak = 225; unit = 'ms'; ideal = 'unter 150 ms'; severity = 1 }) }
        $p = @(Get-WorkerPerfCopyParagraphs -Incident $i -Guide (New-CopyGuide $i) -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts)
        @($p | Where-Object { $_ -like 'Betroffen*' }).Count | Should -Be 0; $p | Should -Contain 'Messwert: 225 ms, Soll unter 150 ms'
        $i.chronic = $false
        @(Get-WorkerPerfCopyParagraphs -Incident $i -Guide (New-CopyGuide $i) -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts) | Should -Contain 'Betroffen: 0'
    }
    It 'nimmt hoechstens fuenf Pruefschritte und drei Vorschlaege in den Kopiertext und sagt, wie viele weitere im Bericht stehen' {   # ruling P3-R59
        $i = New-CpuInc; $g = New-CopyGuide $i; $dash = [string][char]0x2013
        $steps = { param([int]$Checks, [int]$Remedies, [int]$Contacts)
            $g.checks = @(1..$Checks | ForEach-Object { [ordered]@{ text = "Schritt $_"; where = 'Ort'; sign = 'Merkmal'; source = $null } })
            $g.remedies = @(1..$Remedies | ForEach-Object { [ordered]@{ text = "Abhilfe $_"; precondition = 'Voraussetzung'; source = $null } })
            $g.contacts = @(1..$Contacts | ForEach-Object { [ordered]@{ text = "Kontakt $_"; source = $null } }) }
        $tail = { param($Catalogue = $Cat) $p = @(Get-WorkerPerfCopyParagraphs -Incident $i -Guide $g -Data (New-Ctx).Data -Catalogue $Catalogue -Texts $Texts); @($p[([array]::IndexOf($p, $Cat.copy.checks) - 1)..($p.Count - 1)]) }
        # seven checks, five remedies, four contacts: the first five and three in the guide's order, one line after each shortened block, every contact
        & $steps 7 5 4
        & $tail | Should -Be @('', 'Empfohlene Pruefschritte:', "1. Schritt 1 ${dash} Ort; erkennbar an Merkmal", "2. Schritt 2 ${dash} Ort; erkennbar an Merkmal", "3. Schritt 3 ${dash} Ort; erkennbar an Merkmal",
            "4. Schritt 4 ${dash} Ort; erkennbar an Merkmal", "5. Schritt 5 ${dash} Ort; erkennbar an Merkmal", 'Weitere 2 Pruefschritte im Bericht.', '', 'Moegliche Abhilfe (Vorschlag):',
            '- Wenn Voraussetzung: Abhilfe 1', '- Wenn Voraussetzung: Abhilfe 2', '- Wenn Voraussetzung: Abhilfe 3', 'Weitere 2 Vorschlaege im Bericht.', '', 'Ansprechpartner:',
            '- Kontakt 1', '- Kontakt 2', '- Kontakt 3', '- Kontakt 4')
        # the guide itself stays complete: the report shows every step
        @($g.checks).Count | Should -Be 7; @($g.remedies).Count | Should -Be 5
        # one step more than the text carries: the singular
        & $steps 6 4 1
        $p = @(& $tail); $p | Should -Contain 'Ein weiterer Pruefschritt im Bericht.'; $p | Should -Contain 'Ein weiterer Vorschlag im Bericht.'
        @($p | Where-Object { $_ -match '^Weitere ' }) | Should -Be @()
        # as many steps as the text carries, or fewer: no such line
        foreach ($n in @(5, 3), @(1, 1)) {
            & $steps $n[0] $n[1] 1
            $p = @(& $tail); @($p | Where-Object { $_ -match 'im Bericht\.$' }) | Should -Be @() -Because "$($n[0]) und $($n[1])"
            @($p | Where-Object { $_ -match '^\d+\. ' }).Count | Should -Be $n[0]; @($p | Where-Object { $_ -match '^- Wenn ' }).Count | Should -Be $n[1]
        }
        # the numbers are the catalogue's
        & $steps 7 5 1
        $small = Read-WorkerPerfGuidance (New-Catalogue { $c.copy.maxChecks = 2; $c.copy.maxRemedies = 1 })
        $p = @(& $tail $small)
        @($p | Where-Object { $_ -match '^\d+\. ' }).Count | Should -Be 2; @($p | Where-Object { $_ -match '^- Wenn ' }).Count | Should -Be 1
        $p | Should -Contain 'Weitere 5 Pruefschritte im Bericht.'; $p | Should -Contain 'Weitere 4 Vorschlaege im Bericht.'
        # the wrapped text, with and without names: the same steps, the line on its own line without indent
        foreach ($mask in $null, $CopyMask) {
            $lines = Get-Lines (New-WorkerPerfCopyText -Incident $i -Guide $g -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts -Mask $mask)
            @($lines | Where-Object { $_ -match '^\d+\. ' }).Count | Should -Be 5; @($lines | Where-Object { $_ -match '^- Wenn ' }).Count | Should -Be 3
            $lines | Should -Contain 'Weitere 2 Pruefschritte im Bericht.'; $lines | Should -Contain 'Weitere 2 Vorschlaege im Bericht.'
            [array]::IndexOf($lines, 'Weitere 2 Pruefschritte im Bericht.') | Should -Be ([array]::IndexOf($lines, "5. Schritt 5 ${dash} Ort; erkennbar an Merkmal") + 1)
        }
        # the summary of the capture names no steps and no such line
        $i.guide = $g
        $l = Get-WorkerPerfLagebild -Incidents @($i) -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts
        @(Get-WorkerPerfCopySummaryParagraphs -Incidents @($i) -Order @(2) -Lagebild $l -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts | Where-Object { $_ -match 'im Bericht\.$|Schritt \d' }) | Should -Be @()
        # a catalogue changed after loading: a number that is none stops with the name of the value
        $small.copy.maxChecks = 0
        { Get-WorkerPerfCopyParagraphs -Incident $i -Guide $g -Data (New-Ctx).Data -Catalogue $small -Texts $Texts } | Should -Throw "Catalogue value 'copy.maxChecks' is no whole number from 1 on."
    }
    It 'nimmt den Verursacher aus dem Teil des Vorfallssatzes und laesst die Zeile ohne ihn weg' {     # ruling P3-R30
        $i = New-Inc @{ type = 'ohne-engpass'; start = 1e12; end = 1e12 + 60000; causeText = ' Die Ursache liegt außerhalb des Servers. Gegenstelle Oracle-Listener: 348 ms. ' }
        $p = @(Get-WorkerPerfCopyParagraphs -Incident $i -Guide (New-CopyGuide $i) -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts)
        $p | Should -Contain 'Verursacher: Die Ursache liegt außerhalb des Servers. Gegenstelle Oracle-Listener: 348 ms.'
        $i.causeText = ''
        @(Get-WorkerPerfCopyParagraphs -Incident $i -Guide (New-CopyGuide $i) -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts | Where-Object { $_ -like 'Verursacher*' }).Count | Should -Be 0
        # the second wording of the cause is gone: the copy text has no function of its own for it
        foreach ($f in 'Get-WorkerPerfCopyCause', 'Get-WorkerPerfCopyShare', 'Get-WorkerPerfCopySessionUser') { Get-Command $f -ErrorAction SilentlyContinue | Should -BeNullOrEmpty -Because $f }
    }
    It 'sagt bei einer Verzoegerung ohne erkannten Engpass den Typ und bei unbekannten Betroffenen den Satz des Katalogs' {   # additions c), d)
        $ctx = New-Ctx; $ctx.Data.unmeasured.input = $true; $ctx.Data.unmeasured.worker = @('Latenz der Laufwerke')
        $i = New-Inc @{ type = 'ohne-engpass'; unverified = $true; start = 1e12; end = 1e12 + 60000 }
        $p = @(Get-WorkerPerfCopyParagraphs -Incident $i -Guide (New-CopyGuide $i $ctx) -Data $ctx.Data -Catalogue $Cat -Texts $Texts)
        $p[1] | Should -BeLike '*(Verzögerung ohne erkannten Engpass)'
        $p[2] | Should -Be $Cat.userView.unknown                                                  # the user's view says it, once
        @($p | Where-Object { $_ -eq $Cat.userView.unknown }).Count | Should -Be 1
        @($p | Where-Object { $_ -like 'Betroffen:*' }).Count | Should -Be 0                      # ruling P3-R32
        @($p | Where-Object { $_ -like 'Messwert:*' }).Count | Should -Be 0                       # no measured value: no measure line
    }
    It 'nennt bei einem Ereignisvorfall Anwendung, Muster und Betroffene' {                           # addition c), rulings P3-R30, P3-R32
        $ev = @{ kind = 'crash'; app = 'EXCEL.EXE'; sessions = @(1, 2); users = @('user004', 'user005')
            patterns = @(@{ id = 'resource'; text = 'Wahrscheinlich Folge des Speichermangels.'; detail = @{} }) }
        $detail = 'Absturz von EXCEL.EXE (2-mal). Benutzer: user004, user005. Fehlerhaftes Modul: mso.dll, immer dasselbe. Fehlercode: 0xc0000005. Wahrscheinlich Folge des Speichermangels.'
        $i = New-Inc @{ type = 'ereignis'; start = 1e12; end = 1e12; event = $ev; causeText = $detail }
        $p = @(Get-WorkerPerfCopyParagraphs -Incident $i -Guide (New-CopyGuide $i) -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts)
        $p[1] | Should -Be '02:46: Titel crash (Vorfall aus Ereignissen · Anwendungsabsturz)'          # no duration: the time alone
        $p[2] | Should -Be 'Viele.'                                                                # the user's view after the title line
        $p | Should -Contain "Verursacher: $detail"
        $p | Should -Contain 'Betroffen: 2 (user004, user005)'
        @($p | Where-Object { $_ -like 'Messwert:*' }).Count | Should -Be 0
        # without a user session: the incident's own sentence says so (causeText), once; no affected line, not "Betroffen: 0"
        $sp = New-Inc @{ type = 'ereignis'; start = 1e12; end = 1e12; event = @{ kind = 'print'; app = 'spoolsv.exe'; noUserSession = $true }; causeText = 'Druckproblem. Ohne Benutzersitzung.' }
        $p = @(Get-WorkerPerfCopyParagraphs -Incident $sp -Guide (New-CopyGuide $sp) -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts)
        $p | Should -Contain 'Verursacher: Druckproblem. Ohne Benutzersitzung.'
        @($p | Where-Object { $_ -like '*Ohne Benutzersitzung*' }).Count | Should -Be 1; @($p | Where-Object { $_ -like 'Betroffen*' }).Count | Should -Be 0
        # before the capture: the date before the time, the user's view of the catalogue and no affected line (ruling P3-R17)
        $ev.sessions = @(); $ev.users = @('user004'); $ev.before = $true
        $dash = [string][char]0x2013
        $i = New-Inc @{ type = 'ereignis'; start = 1e12; end = 1e12 + 3600000; event = $ev; causeText = 'Kein Muster erkannt.' }
        $p = @(Get-WorkerPerfCopyParagraphs -Incident $i -Guide (New-CopyGuide $i) -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts)
        $p[1] | Should -Be "09.09.2001 02:46${dash}03:46 (1 Stunde): Titel crash (Vorfall aus Ereignissen · Anwendungsabsturz)"
        $p[2] | Should -Be $Cat.userView.before
        $p | Should -Contain 'Verursacher: Kein Muster erkannt.'; @($p | Where-Object { $_ -like 'Betroffen*' }).Count | Should -Be 0
        # the affected sessions cannot be determined: the user's view says so, no affected line
        $u = New-Inc @{ type = 'ereignis'; start = 1e12; end = 1e12; event = @{ kind = 'crash'; app = 'x.exe'; sessionUnknown = $true } }
        $p = @(Get-WorkerPerfCopyParagraphs -Incident $u -Guide (New-CopyGuide $u) -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts)
        $p[2] | Should -Be $Cat.userView.unknown; @($p | Where-Object { $_ -like 'Betroffen*' }).Count | Should -Be 0
    }
    It 'nimmt Zeitspanne und Form der Titelzeile aus den Texten' {                                    # item 5 of fix round 1
        $t = $Texts.Clone(); $t['copy.span'] = '{0} bis {1}'; $t['copy.duration'] = '{0} [{1}]'; $t['copy.title'] = '{0} | {1}'; $t['copy.tech'] = '{0} <{1}>'; $t['copy.dated'] = '{0}/{1}'
        $i = New-CpuInc; $g = New-CopyGuide $i
        (@(Get-WorkerPerfCopyParagraphs -Incident $i -Guide $g -Data (New-Ctx).Data -Catalogue $Cat -Texts $t))[1] | Should -Be '02:46 bis 02:48 [2 Minuten] | Titel cpu <Engpass · CPU>'
        $b = New-Inc @{ type = 'ereignis'; start = 1e12; end = 1e12; event = @{ kind = 'crash'; app = 'x.exe'; before = $true } }
        (@(Get-WorkerPerfCopyParagraphs -Incident $b -Guide (New-CopyGuide $b) -Data (New-Ctx).Data -Catalogue $Cat -Texts $t))[1] | Should -Be '09.09.2001/02:46 | Titel crash <Vorfall aus Ereignissen · Anwendungsabsturz>'
        $t.Remove('copy.span')
        { Get-WorkerPerfCopyParagraphs -Incident $i -Guide $g -Data (New-Ctx).Data -Catalogue $Cat -Texts $t } | Should -Throw "*'copy.span'*"
    }
    It 'fasst die Messung zusammen: Kopf, Lagebild mit Hinweisen, Vorfaelle in Rangfolge' {
        $ctx = New-Ctx; $ctx.Data.skipped = @([ordered]@{ id = 'Laufwerke'; label = 'Laufwerke'; text = ''; places = @() })
        $ctx.Data.sollIst = @([ordered]@{ id = 'ica.rtt'; label = 'ICA Round Trip'; measured = $false; detail = 'Zaehler fehlt' })
        $a = New-CpuInc; $a.guide = New-CopyGuide $a $ctx
        $b = New-Inc @{ id = 5; type = 'ereignis'; start = 1e12 + 300000; end = 1e12 + 300000; event = @{ kind = 'crash'; app = 'EXCEL.EXE'; sessions = @(1, 2, 3) } }; $b.guide = New-CopyGuide $b $ctx
        $l = Get-WorkerPerfLagebild -Incidents @($a, $b) -Data $ctx.Data -Catalogue $Cat -Texts $Texts
        $p = @(Get-WorkerPerfCopySummaryParagraphs -Incidents @($a, $b) -Order @(5, 2, 5) -Lagebild $l -Data $ctx.Data -Catalogue $Cat -Texts $Texts)
        $dash = [string][char]0x2013
        $p | Should -Be @('WorkerPerf SIM-VDA01, 09.09.2001, 02:46 bis 03:46', ([string][char]0x25C6 + ' kritisch: Rot: 1 Engpaesse, 0 Verzoegerungen, 1 Ereignisse, 0 Dauerzustaende.'), 'Abgeschaltet: Laufwerke.', 'Nicht gemessen: ICA Round Trip.', ''
            '- 02:51: Titel crash (Vorfall aus Ereignissen · Anwendungsabsturz). Langsam.', "- 02:46${dash}02:48 (2 Minuten): Titel cpu (Engpass · CPU). Langsam.")
        $t = New-WorkerPerfCopySummary -Incidents @($a, $b) -Order @(5, 2) -Lagebild $l -Data $ctx.Data -Catalogue $Cat -Texts $Texts
        $t | Should -BeExactly (Format-WorkerPerfCopyLines $p)
        # the incidents before the capture in a block of their own, oldest first (ruling P3-R31)
        $old = @(foreach ($n in @(@{ id = 13; at = 1e12 - 86400000 }, @{ id = 12; at = 1e12 - 2 * 86400000 })) {
                $x = New-Inc @{ id = $n.id; type = 'ereignis'; start = $n.at; end = $n.at; event = @{ kind = 'crash'; app = 'x.exe'; before = $true } }; $x.guide = New-CopyGuide $x $ctx; $x })
        $q = @(Get-WorkerPerfCopySummaryParagraphs -Incidents @($a, $b) -Order @(5, 2) -Lagebild $l -Data $ctx.Data -Catalogue $Cat -Texts $Texts -Before $old)
        $q[0..6] | Should -Be $p
        $q[7..10] | Should -Be @('', 'Vor der Messung (für diese Zeit liegen keine Messwerte vor):',
            '- 07.09.2001 02:46: Titel crash (Vorfall aus Ereignissen · Anwendungsabsturz)', '- 08.09.2001 02:46: Titel crash (Vorfall aus Ereignissen · Anwendungsabsturz)')
        $q.Count | Should -Be 11
        New-WorkerPerfCopySummary -Incidents @($a, $b) -Order @(5, 2) -Lagebild $l -Data $ctx.Data -Catalogue $Cat -Texts $Texts -Before $old | Should -BeExactly (Format-WorkerPerfCopyLines $q)
        @(Get-WorkerPerfCopySummaryParagraphs -Incidents @($a, $b) -Order @(5, 2) -Lagebild $l -Data $ctx.Data -Catalogue $Cat -Texts $Texts -Before @()) | Should -Be $p
        { Get-WorkerPerfCopySummaryParagraphs -Incidents @($a) -Order @(9) -Lagebild $l -Data $ctx.Data -Catalogue $Cat -Texts $Texts } | Should -Throw '*9*'
    }
    It 'ersetzt Namen vor dem Umbruch, auch einen, den der Umbruch teilen wuerde' {                 # addition a), ruling P3-R9
        # the name starts at column 75 of a word longer than the line: the wrapper would cut it
        $path = 'C:\' + ('a' * 66) + '\schoenberger\x.dat'
        $plain = Format-WorkerPerfCopyLines @("Pfad $path")
        (Get-Lines $plain) | ForEach-Object { $_ | Should -Not -Match 'schoenberger' }                # split by the wrapper
        $anon = Format-WorkerPerfCopyLines @(ConvertTo-WorkerPerfAnonymousText "Pfad $path" $CopyMask)
        foreach ($part in 'schoenberger', 'schoen', 'berger') { $anon | Should -Not -Match $part }
        (Join-Copy $anon) | Should -Match 'Benutzer 01'; @((Get-Lines $anon) | Where-Object { $_.Length -gt 78 }).Count | Should -Be 0
        ConvertTo-WorkerPerfAnonymousText 'Sitzung von schoenberger an WS-0042' $CopyMask | Should -Be 'Sitzung von Benutzer 01 an Client 01'
        # the copy text with -Mask: every paragraph is masked before wrapping
        $i = New-CpuInc; $i.main.user = 'schoenberger'; $i.causeText = $i.causeText.Replace('user003', 'schoenberger'); $g = New-CopyGuide $i; $g.impact = "Pfad $path"
        $t = New-WorkerPerfCopyText -Incident $i -Guide $g -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts
        (Join-Copy $t) | Should -Match 'Sitzung von schoenberger'
        $t = New-WorkerPerfCopyText -Incident $i -Guide $g -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts -Mask $CopyMask
        foreach ($part in 'schoenberger', 'schoen', 'berger') { $t | Should -Not -Match $part }
        (Join-Copy $t) | Should -Match 'Sitzung von Benutzer 01'; (Join-Copy $t) | Should -Match 'EXCEL\.EXE'
        @((Get-Lines $t) | Where-Object { $_.Length -gt 78 }).Count | Should -Be 0
        $s = New-WorkerPerfCopySummary -Incidents @() -Order @() -Lagebild (Get-WorkerPerfLagebild -Incidents @() -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts) -Data (New-Ctx).Data -Catalogue $Cat -Texts $Texts -Mask $CopyMask
        $s | Should -Match '^WorkerPerf SIM-VDA01'                                                   # the mask of another run knows no SIM-VDA01
    }
}
Describe 'Situation und Bedingungen der simulierten Stunde' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        # one recorded hour and the report data as the report script builds them (dot-sourced in a child scope, which keeps
        # $data); the names below are not used by the report script
        $guideSimRun = Invoke-SimCapture (Join-Path $TestDrive 'sim')
        $guideSimRoles = New-SimRoleFile (Join-Path $TestDrive 'roles.sim.json')
        $guideSimReport = Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1'
        $script:SimData = & { $null = . $guideSimReport -Path $guideSimRun -OutFile (Join-Path $TestDrive 'report.html') -RoleFile $guideSimRoles 6>$null; $data }
        $script:SimCtx = @{ Data = $SimData; Thresholds = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json'); OffsetMinutes = [int]$SimData.meta.offsetMin; Texts = $script:Texts }
        $script:SimIncidents = @(@($SimData.incidents) + @($SimData.before.incidents))
        $script:SimFacts = @{}
        foreach ($inc in $SimIncidents) { $SimFacts[[int]$inc.id] = Get-WorkerPerfGuidanceFacts -Incident $inc -Context $SimCtx -Catalogue $Cat }
    }
    It 'leitet fuer jeden Vorfall eine bekannte Situation und nur bekannte Bedingungen ab' {
        $SimIncidents.Count | Should -Be 16
        $SimFacts.Count | Should -Be 16
        foreach ($id in $SimFacts.Keys) {
            $f = $SimFacts[$id]
            $script:WorkerPerfSituations | Should -Contain $f.Situation -Because "Vorfall $id"
            foreach ($n in $f.Conditions) { Test-WorkerPerfGuidanceCondition $n $Cat | Should -BeTrue -Because "Vorfall ${id}: $n" }
            @($f.Values.Keys | Where-Object { $script:WorkerPerfGuidancePlaceholders -cnotcontains $_ }) | Should -Be @() -Because "Vorfall $id"
        }
    }
    It 'ordnet die Vorfaelle der simulierten Stunde ihren Situationen zu' {
        $got = @(foreach ($id in 1..16) { '{0}:{1}' -f $id, $SimFacts[$id].Situation })
        $got | Should -Be @('1:chronic.network', '2:cpu', '3:memory', '4:disk', '5:share', '6:profile', '7:delay.many', '8:delay.single', '9:profileerror',
            '10:crash', '11:crash', '12:print', '13:crash', '14:crash', '15:crash', '16:crash')
    }
    It 'nennt fuer Datentraeger und Druck die Tatsachen der simulierten Stunde' {
        $SimFacts[4].Conditions | Should -Contain 'scan'; $SimFacts[4].Conditions | Should -Contain 'companion.security'; $SimFacts[4].Values.security | Should -Be 'Microsoft Defender'
        $SimFacts[12].Conditions | Should -Contain 'pattern.printdriver'; $SimFacts[12].Conditions | Should -Contain 'spooler.crash'
        $SimFacts[12].Conditions | Should -Contain 'role.Drucken'; $SimFacts[12].Values.driver | Should -Be 'HP Universal Printing PCL 6 (Sim)'
        $SimFacts[16].Conditions | Should -Contain 'affected.unknown'; $SimFacts[16].Conditions | Should -Contain 'before'
        foreach ($id in 2..6) { $SimFacts[$id].Conditions | Should -Contain 'cause.app' -Because "Vorfall $id"; $SimFacts[$id].Values.Keys | Should -Contain 'app' }
        # the bottlenecks name their resource, nothing else does (ruling P3-R37)
        foreach ($id in 2..6) { @($SimFacts[$id].Conditions | Where-Object { $_ -like 'lead.*' }) | Should -Be @('lead.' + $SimFacts[$id].Situation) -Because "Vorfall $id" }
        foreach ($id in @(1) + 7..16) { @($SimFacts[$id].Conditions | Where-Object { $_ -like 'lead.*' }) | Should -Be @() -Because "Vorfall $id" }
        # lookback crashes: the application and their one user, no number of affected sessions (P3-R16, P3-R17)
        foreach ($id in 13..15) { $SimFacts[$id].Values.ContainsKey('affected') | Should -BeFalse -Because "Vorfall $id"; $SimFacts[$id].Values.Keys | Should -Contain 'app' -Because "Vorfall $id" }
    }
    It 'stellt fuer jeden Vorfall der simulierten Stunde eine Anleitung zusammen' {
        foreach ($inc in $SimIncidents) {
            $id = [int]$inc.id
            $g = New-WorkerPerfGuidance -Catalogue $Cat -Facts $SimFacts[$id] -Incident $inc -Texts $Texts
            $g.fallback | Should -Be ($SimFacts[$id].Situation -eq 'fallback') -Because "Vorfall $id"
            $g.situation | Should -Be $SimFacts[$id].Situation -Because "Vorfall $id"
            foreach ($k in 'title', 'tech', 'meaning', 'userView') { [string]$g[$k] | Should -Not -BeNullOrEmpty -Because "Vorfall ${id}: $k" }
            @($g.checks).Count | Should -BeGreaterThan 0 -Because "Vorfall $id"
            $g.conditions | Should -Be $SimFacts[$id].Conditions -Because "Vorfall $id"
        }
    }
    It 'ordnet die zwoelf Vorfaelle der Messung, fasst die nach zehn Karten zusammen und bildet das Lagebild' {
        # the capture's incidents only (not before.incidents), each a copy with its guidance as the report script will add it
        $capture = @(foreach ($inc in @($SimData.incidents)) {
                $copy = [ordered]@{}
                if ($inc -is [System.Collections.IDictionary]) { foreach ($k in $inc.Keys) { $copy[$k] = $inc[$k] } }
                else { foreach ($p in $inc.PSObject.Properties) { $copy[$p.Name] = $p.Value } }
                $copy['guide'] = New-WorkerPerfGuidance -Catalogue $Cat -Facts $SimFacts[[int]$inc.id] -Incident $inc -Texts $Texts
                $copy
            })
        $capture.Count | Should -Be 12
        # the incidents of section E of the fact check, by type, lead and kind of event
        $find = {
            param([scriptblock]$Where)
            $hit = @($capture | Where-Object $Where)
            $hit.Count | Should -Be 1
            [int]$hit[0].id
        }
        $backend = & $find { $_.type -eq 'ohne-engpass' -and @($_.affected).Count -ge 2 }
        $cpu = & $find { $_.type -eq 'engpass' -and $_.lead -eq 'cpu' }
        $memory = & $find { $_.type -eq 'engpass' -and $_.lead -eq 'memory' }
        $manyUsers = & $find { $_.type -eq 'ereignis' -and $_.event.kind -eq 'crash' -and @($_.event.patterns | Where-Object { $_.id -eq 'manyusers' }).Count -gt 0 }
        $spooler = & $find { $_.type -eq 'ereignis' -and $_.event.kind -eq 'print' }
        $homeOffice = & $find { $_.type -eq 'umfeld' -and [bool]$_.chronic }
        $order = @(Get-WorkerPerfIncidentRanking -Incidents $capture)
        $order.Count | Should -Be 12
        $order[0..3] | Should -Be @($backend, $cpu, $memory, $manyUsers)
        $order[10..11] | Should -Be @($spooler, $homeOffice)
        @(Get-WorkerPerfIncidentGroups -Incidents $capture -Order $order -Cards 10 -OffsetMinutes $SimCtx.OffsetMinutes -Texts $Texts).Count | Should -Be 2
        $l = Get-WorkerPerfLagebild -Incidents @($SimData.incidents) -Data $SimData -Catalogue $Cat -Texts $Texts
        $l.kpis.bottlenecks | Should -Be 5; $l.kpis.delays | Should -Be 2; $l.kpis.events | Should -Be 4; $l.kpis.chronic | Should -Be 1
        $l.kpis.minutes | Should -Be 12.9
        $l.state | Should -Be 'red'; $l.top | Should -Be $backend
    }
    It 'schreibt fuer jeden Vorfall und fuer die Messung Kopiertexte mit und ohne Namen' {
        # the mask of level Alles of the same recording, with the arguments the report script passes
        $roles = @(Read-WorkerPerfRoles $guideSimRoles)
        $mask = New-WorkerPerfMask -Path $guideSimRun -Level 'Alles' -Texts $Texts -RoleLabels @($roles | ForEach-Object { [string]$_.label }) `
            -EventConfig (Read-WorkerPerfEventConfig (Join-Path $PSScriptRoot '../src/events.json'))
        $names = @($mask.Entries | Where-Object { @('user', 'client', 'server', 'share', 'domain') -contains [string]$_.Kind } | ForEach-Object { [string]$_.Name })
        foreach ($n in 'SIM-VDA01', 'user003', 'CONTOSO') { $names | Should -Contain $n }
        @($mask.Entries | Where-Object { $_.Kind -eq 'client' }).Count | Should -BeGreaterThan 0
        @($mask.Entries | Where-Object { $_.Kind -eq 'share' }).Count | Should -BeGreaterThan 0
        $apps = @(@($SimData.apps) | ForEach-Object { [string]$_.name } | Where-Object { $_ })
        $check = {
            param([string]$Plain, [string]$Anon, [string[]]$Titles, [string]$What)
            foreach ($t in $Plain, $Anon) {
                @(($t -split "`r`n") | Where-Object { $_.Length -gt 78 }) | Should -Be @() -Because $What
                foreach ($title in $Titles) { ($t -replace "`r`n\s*", ' ').Contains($title) | Should -BeTrue -Because "$What, $title" }
            }
            foreach ($n in $names) {
                $Anon -match ('(?i)(?<![\p{L}\p{N}_])' + [regex]::Escape($n) + '(?![\p{L}\p{N}_])') | Should -BeFalse -Because "$What nennt $n"
            }
            foreach ($a in $apps) { if ($Plain.Contains($a)) { $Anon.Contains($a) | Should -BeTrue -Because "$What, $a" } }
        }
        $userNames = @($mask.Entries | Where-Object { $_.Kind -eq 'user' } | ForEach-Object { [string]$_.Name })
        $hits = 0
        foreach ($inc in $SimIncidents) {
            $id = [int]$inc.id
            $g = New-WorkerPerfGuidance -Catalogue $Cat -Facts $SimFacts[$id] -Incident $inc -Texts $Texts
            $plain = New-WorkerPerfCopyText -Incident $inc -Guide $g -Data $SimData -Catalogue $Cat -Texts $Texts
            $anon = New-WorkerPerfCopyText -Incident $inc -Guide $g -Data $SimData -Catalogue $Cat -Texts $Texts -Mask $mask
            & $check $plain $anon @($g.title) "Vorfall $id"
            $plain | Should -Match 'SIM-VDA01' -Because "Vorfall $id"
            # the cause part is the incident's own sentence (ruling P3-R30): part of text, printed whole in the copy text
            [string]$inc.causeText | Should -Not -BeNullOrEmpty -Because "Vorfall $id"
            ([string]$inc.text).Contains([string]$inc.causeText) | Should -BeTrue -Because "Vorfall $id"
            (Join-Copy $plain).Contains([string]$inc.causeText) | Should -BeTrue -Because "Vorfall $id"
            (Join-Copy $plain).Contains([string]$g.userView) | Should -BeTrue -Because "Vorfall $id"
            if (@($userNames | Where-Object { $plain -match ('(?i)(?<![\p{L}\p{N}_])' + [regex]::Escape($_) + '(?![\p{L}\p{N}_])') }).Count -gt 0) { $hits++ }
        }
        $hits | Should -BeGreaterThan 5                                                            # the plain texts do name users
        # what the reviews found missing: the endpoint of the backend delay, the session of the chronic network state, the
        # application, module and error code of a crash (from the report data, not from the simulation's script)
        $copyOf = { param($Inc) Join-Copy (New-WorkerPerfCopyText -Incident $Inc -Guide (New-WorkerPerfGuidance -Catalogue $Cat -Facts $SimFacts[[int]$Inc.id] -Incident $Inc -Texts $Texts) -Data $SimData -Catalogue $Cat -Texts $Texts) }
        $backend = @($SimData.incidents | Where-Object { $_.type -eq 'ohne-engpass' -and @($_.endpoints | Where-Object { [double]$_.maxMs -ge 50 }).Count -gt 0 })
        $backend.Count | Should -BeGreaterThan 0
        foreach ($inc in $backend) { foreach ($e in @($inc.endpoints | Where-Object { [double]$_.maxMs -ge 50 })) { (& $copyOf $inc) | Should -Match ('Gegenstelle ' + [regex]::Escape([string]$e.name) + ': \d+ ms') } }
        $net = @($SimData.incidents | Where-Object { $_.type -eq 'umfeld' -and $_.chronic })[0]
        $who = @($SimData.sessions | Where-Object { [int]$_.i -eq [int]@($net.signals | Where-Object { $_.resource -eq 'network' })[0].s })[0].user
        $who | Should -Match '^user\d+$'; (& $copyOf $net) | Should -Match ('Netzstrecke von ' + [regex]::Escape($who))
        $crashes = @($SimIncidents | Where-Object { $_.type -eq 'ereignis' -and $_.event.kind -eq 'crash' -and $_.event.app -and @($_.event.modules).Count -gt 0 -and @($_.event.codes).Count -gt 0 -and $_.event.modules[0].name -notmatch '(?i)^(unknown|stackhash)' })
        $crashes.Count | Should -BeGreaterThan 3
        foreach ($inc in $crashes) {
            $c = & $copyOf $inc
            foreach ($part in [string]$inc.event.app, [string]$inc.event.modules[0].name, [string]$inc.event.codes[0].code) { $c.Contains($part) | Should -BeTrue -Because "Vorfall $($inc.id): $part" }
        }
        # the spooler crash outside user sessions says "Ohne Benutzersitzung." exactly once (in its cause part)
        $spooler = @($SimData.incidents | Where-Object { $_.type -eq 'ereignis' -and $_.event.kind -eq 'print' -and [bool]$_.event.noUserSession })
        $spooler.Count | Should -Be 1
        $c = & $copyOf $spooler[0]
        ([regex]::Matches($c, [regex]::Escape($Texts['event.nouser'].Trim()))).Count | Should -Be 1
        $c | Should -Not -Match 'Betroffen'
        # causeText directly after text in every incident entry of the report data, capture and lookback
        foreach ($inc in $SimIncidents) {
            $keys = @(if ($inc -is [System.Collections.IDictionary]) { $inc.Keys } else { $inc.PSObject.Properties.Name })
            $keys[[array]::IndexOf($keys, 'text') + 1] | Should -Be 'causeText' -Because "Vorfall $($inc.id)"
        }
        @($SimData.before.incidents).Count | Should -BeGreaterThan 0
        # a lookback incident: its date before the time in the title line
        foreach ($inc in @($SimData.before.incidents)) { ((& $copyOf $inc) -split ' ')[3] | Should -Match '^\d\d\.\d\d\.\d{4}$' -Because "Vorfall $($inc.id)" }
        $capture = @(foreach ($inc in @($SimData.incidents)) {
                $copy = [ordered]@{}
                if ($inc -is [System.Collections.IDictionary]) { foreach ($k in $inc.Keys) { $copy[$k] = $inc[$k] } }
                else { foreach ($p in $inc.PSObject.Properties) { $copy[$p.Name] = $p.Value } }
                $copy['guide'] = New-WorkerPerfGuidance -Catalogue $Cat -Facts $SimFacts[[int]$inc.id] -Incident $inc -Texts $Texts
                $copy
            })
        $order = @(Get-WorkerPerfIncidentRanking -Incidents $capture)
        $l = Get-WorkerPerfLagebild -Incidents @($SimData.incidents) -Data $SimData -Catalogue $Cat -Texts $Texts
        $before = @(foreach ($inc in @($SimData.before.incidents)) {
                $copy = [ordered]@{}
                if ($inc -is [System.Collections.IDictionary]) { foreach ($k in $inc.Keys) { $copy[$k] = $inc[$k] } }
                else { foreach ($p in $inc.PSObject.Properties) { $copy[$p.Name] = $p.Value } }
                $copy['guide'] = New-WorkerPerfGuidance -Catalogue $Cat -Facts $SimFacts[[int]$inc.id] -Incident $inc -Texts $Texts
                $copy
            })
        $before.Count | Should -Be 4
        $plain = New-WorkerPerfCopySummary -Incidents $capture -Order $order -Lagebild $l -Data $SimData -Catalogue $Cat -Texts $Texts -Before $before
        $anon = New-WorkerPerfCopySummary -Incidents $capture -Order $order -Lagebild $l -Data $SimData -Catalogue $Cat -Texts $Texts -Mask $mask -Before $before
        & $check $plain $anon @($capture | ForEach-Object { [string]$_.guide.title }) 'Zusammenfassung'
        $plain | Should -Match 'SIM-VDA01'
        # the lookback incidents after the capture's, under their heading, one line each
        $lines = @($plain -split "`r`n")
        $at = [array]::IndexOf($lines, $Texts['copy.before']); $at | Should -BeGreaterThan 12
        @($lines[($at + 1)..($lines.Count - 1)] | Where-Object { $_ -match '^- \d\d\.\d\d\.\d{4} \d\d:\d\d' }).Count | Should -Be 4
    }
}
