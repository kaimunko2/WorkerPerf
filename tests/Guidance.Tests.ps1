BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Events.ps1')
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Findings.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Guidance.ps1')
    function New-Inc([hashtable]$Over = @{}) {
        # every key of an incident entry with neutral values (2 minutes from 10 min after the capture start), overwritten by
        # the given ones; a given event gets every key of an event with neutral values first
        $inc = @{ id = 1; type = 'umfeld'; chronic = $false; severity = 2; start = [long](1e12 + 600000); end = [long](1e12 + 720000); durSec = 120.0
            lead = $null; resources = @(); text = ''; focus = $false; nearReported = $false; scanActive = $false; events = @(); signals = @(); affected = @()
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
            userView     = @{ many = '{affected} Sitzungen waren betroffen.'; one = '{user} war betroffen.'; none = 'Niemand war betroffen.'; unknown = 'Unbekannt.'
                chronic = 'Dauerzustand.'; eventMany = 'Viele.'; eventOne = 'Einer.'; eventNone = 'Keiner.'; before = 'Vor der Messung.' }
            lagebild     = @{ red = '{bottlenecks} Engpaesse.'; yellow = '{delays} Verzoegerungen.'; green = 'Keine Stoerung erkannt.'; greenSkipped = 'Keine Stoerung erkannt; nicht gemessen: {skipped}.' }
            hints        = @{ unmeasured = 'Nicht gemessen: {signals}.'; skipped = 'Abgeschaltet: {skipped}.'; notFinished = 'Nicht beendet.'; error = 'Fehler: {message}'
                errorNoMessage = 'Fehler.'; stopped = 'Angehalten.' }
            copy         = @{ head = 'WorkerPerf {server}, {date}'; summaryHead = '{incidents} Vorfaelle'; measure = 'Messung: {minutes} Minuten'; cause = 'Ursache: {app}'
                affected = 'Betroffen: {affected}'; checks = 'Empfohlene Pruefschritte:'; remedies = 'Moegliche Abhilfe (Vorschlag):'; contact = 'Ansprechpartner:' }
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
    ) { { Read-WorkerPerfGuidance (New-Catalogue $Change) } | Should -Throw $Msg }
    It 'verlangt den Schluessel <Key> im Teil <Part>' -TestCases @(
        @(foreach ($k in 'many', 'one', 'none', 'unknown', 'chronic', 'eventMany', 'eventOne', 'eventNone', 'before') { @{ Part = 'userView'; Key = $k } })
        @(foreach ($k in 'red', 'yellow', 'green', 'greenSkipped') { @{ Part = 'lagebild'; Key = $k } })
        @(foreach ($k in 'unmeasured', 'skipped', 'notFinished', 'error', 'errorNoMessage', 'stopped') { @{ Part = 'hints'; Key = $k } })
        @(foreach ($k in 'head', 'summaryHead', 'measure', 'cause', 'affected', 'checks', 'remedies', 'contact') { @{ Part = 'copy'; Key = $k } })
    ) { { Read-WorkerPerfGuidance (New-Catalogue { $c[$Part].Remove($Key) }) } | Should -Throw "Katalog '*': Eintrag '$Part': Feld '$Key' fehlt." }
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
            'cause.notmeasured', 'skipped.Prozesse', 'skipped.Ereignisse', 'pattern.unchecked', 'incident.unverified') {
            Test-WorkerPerfGuidanceCondition $n (Read-WorkerPerfGuidance (New-Catalogue)) | Should -BeTrue -Because $n
        }
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
        $f.Conditions | Should -Be @('cause.app', 'scan', 'companion.security', 'endpoint.slow', 'affected.many')
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
            Should -Be @('cause.nodata', 'unmeasured.input.session', 'affected.unknown')
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
        $f.Conditions | Should -Be @('cause.security')
        $f.Values.security | Should -Be 'Die Schutzsoftware'; $f.Values.app | Should -Be 'EXCEL.EXE'; $f.Values.user | Should -Be 'user007'
        $f.Values.share | Should -Be '12 %'; $f.Values.baseline | Should -Be '0,5 %'
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu'; cause = @{ kind = 'notmeasured' } }) -Context (New-Ctx) -Catalogue $Cat
        foreach ($k in 'app', 'user', 'share', 'baseline', 'security') { $f.Values.ContainsKey($k) | Should -BeFalse -Because $k }
    }
    It 'nennt die Rolle der Anwendung' {
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu'; cause = @{ kind = 'main' }; main = @{ app = 'MsMpEng.exe'; a = 1; user = 'SYSTEM'; sharePct = 30; baselinePct = 2 } }) -Context (New-Ctx) -Catalogue $Cat
        $f.Conditions | Should -Be @('cause.app', 'role.Sicherheit')
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; event = @{ kind = 'crash'; app = 'msmpeng.EXE'; sessions = @(3) } }) -Context (New-Ctx) -Catalogue $Cat
        $f.Conditions | Should -Be @('role.Sicherheit', 'affected.one', 'pattern.none')
        # not in apps (always so with Prozesse skipped), or without a role: no role condition
        $ctx = New-Ctx; $ctx.Data.apps = @()
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'engpass'; lead = 'cpu'; cause = @{ kind = 'main' }; main = @{ app = 'MsMpEng.exe'; a = 1; user = 'SYSTEM'; sharePct = 30; baselinePct = 2 } }) -Context $ctx -Catalogue $Cat
        $f.Conditions | Should -Be @('cause.app')
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
        $rec = @([ordered]@{ t = $start; offsetMin = 120; kind = 'crash'; s = -1; text = '' }, [ordered]@{ t = $end; offsetMin = 60; kind = 'crash'; s = -1; text = '' })
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; start = $start; end = $end; events = $rec; event = @{ kind = 'crash'; before = $true } }) -Context (New-Ctx) -Catalogue $Cat
        $f.Values.from | Should -Be '00:30'; $f.Values.date | Should -Be '09.09.2001'; $f.Values.to | Should -Be '01:30'
        # records without their own offset: the capture's
        $rec = @([ordered]@{ t = $start; kind = 'crash'; s = -1; text = '' })
        $f = Get-WorkerPerfGuidanceFacts -Incident (New-Inc @{ type = 'ereignis'; start = $start; end = $end; events = $rec; event = @{ kind = 'crash'; before = $true } }) -Context (New-Ctx) -Catalogue $Cat
        $f.Values.from | Should -Be '23:30'; $f.Values.date | Should -Be '08.09.2001'; $f.Values.to | Should -Be '01:30'
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
        # lookback crashes: the application and their one user, no number of affected sessions (P3-R16, P3-R17)
        foreach ($id in 13..15) { $SimFacts[$id].Values.ContainsKey('affected') | Should -BeFalse -Because "Vorfall $id"; $SimFacts[$id].Values.Keys | Should -Contain 'app' -Because "Vorfall $id" }
    }
}
