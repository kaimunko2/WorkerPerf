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
    ) { { Read-WorkerPerfGuidance (New-Catalogue $Change) } | Should -Throw $Msg }
    It 'nennt die Datei in der Meldung' {
        $file = New-Catalogue { $c.situations.cpu.Remove('impact') }
        { Read-WorkerPerfGuidance $file } | Should -Throw ([WildcardPattern]::Escape("Katalog '$file': Eintrag 'cpu': Feld 'impact' fehlt."))
    }
    It 'nimmt Bedingungen und Quellen an, die die Regeln erlauben' {
        $cat = Read-WorkerPerfGuidance (New-Catalogue {
                $c.situations.crash.checks += @{ text = 'Treiber {driver} pruefen'; where = 'w'; sign = 's'; when = @('pattern.printdriver', 'driver.vendor.HP'); source = 'HP, Titel' }
                $c.situations.cpu.remedies += @{ text = '{app} mit {value} statt {target}'; precondition = 'p'; when = @('cause.app', 'role.Hauptanwendung') }
                $c.situations.print.contacts += @{ text = 'Druckerbetreuung'; when = @('spooler.crash') } })
        @($cat.situations.crash.checks).Count | Should -Be 2
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
