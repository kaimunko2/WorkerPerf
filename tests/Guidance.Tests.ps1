BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Events.ps1')
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Guidance.ps1')
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
