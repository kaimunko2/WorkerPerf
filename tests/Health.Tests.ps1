BeforeAll {
    Set-StrictMode -Version 2
    foreach ($f in 'Common', 'EventConfig', 'Events', 'Findings', 'Guidance', 'Load', 'Health') { . (Join-Path $PSScriptRoot "../src/WorkerPerf.$f.ps1") }
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1'); $script:TestApps = @(Read-WorkerPerfHealthApps (New-TestAppFile $TestDrive))      # Edge, Office, Teams und die erfundene simapp
    $script:ToApp = { param($Fact, $Op, $Than)
        # macht die erste Pruefung des kleinen Katalogs zu einer Pruefung des Bereichs apps auf einen Fakt
        $c.checks[0].id = 'apps.simCache'; $c.checks[0].area = 'apps'; $c.checks[0].values = @($Fact)
        $c.checks[0].rules = @{ check = @(@{ value = $Fact; op = $Op; than = $Than }) }
        $c.checks[0].findings = @{ ok = 'in Ordnung'; check = 'auffaellig'; unknown = '{reason}' }
        $c.thresholds.Remove('diskFreeGB'); $c.thresholds.Remove('diskFreeHardGB') }                    # sonst nutzt keine Regel diese Schwellen
    function New-HealthCatalogue([scriptblock]$Change = {}) {
        # ein vollstaendiger kleiner Katalog als Hashtable in $c; . $Change aendert ihn; liefert den Pfad der geschriebenen Datei
        $todo = @(@{ text = 't'; where = 'w'; sign = 's' })
        $c = [ordered]@{ version = '2026-11-13'
            areas = @($WorkerPerfHealthAreas | ForEach-Object { [ordered]@{ id = $_; label = "Bereich $_"; notCovered = "Nicht abgedeckt in $_" } })
            grades = [ordered]@{ ok = @{ word = 'In Ordnung'; symbol = [string][char]0x25CF }; check = @{ word = 'Prüfen'; symbol = [string][char]0x25B2 }
                act = @{ word = 'Handeln'; symbol = [string][char]0x25C6 }; unknown = @{ word = 'Nicht prüfbar'; symbol = [string][char]0x25CB }; na = @{ word = 'Trifft nicht zu'; symbol = [string][char]0x2013 } }
            thresholds = [ordered]@{ diskFreeGB = @{ value = 10; default = 10; unit = 'GB'; label = 'Freier Platz' }; diskFreeHardGB = @{ value = 2; default = 2; unit = 'GB'; label = 'Freier Platz, harte Grenze' }
                workStartHour = @{ value = 7; default = 7; unit = 'Uhr'; label = 'Beginn der Arbeitszeit' }; workEndHour = @{ value = 18; default = 18; unit = 'Uhr'; label = 'Ende der Arbeitszeit' } }
            values = [ordered]@{}; copy = [ordered]@{}; precedence = @()
            checks = @(
                [ordered]@{ id = 'operation.diskFree'; area = 'operation'; title = 'Freier Platz'; values = @('operation.minFreeGB')
                    rules = @{ check = @(@{ value = 'operation.minFreeGB'; op = 'lt'; than = '@diskFreeGB' }); act = @(@{ value = 'operation.minFreeGB'; op = 'lt'; than = '@diskFreeHardGB'; hard = $true }) }
                    findings = @{ ok = '{operation.minFreeGB} GB frei.'; check = 'Nur {operation.minFreeGB} GB frei (Schwelle {@diskFreeGB} GB).'; act = 'Nur {operation.minFreeGB} GB frei.'; unknown = 'Nicht prüfbar: {reason}.' }
                    meaning = 'm'; todo = $todo; source = @{ vendor = 'Microsoft'; title = 'Seite'; url = ''; date = '2026-11-13' }; kind = 'rule'; relates = @('disk', 'crash') }
                [ordered]@{ id = 'print.driversInSpooler'; area = 'print'; title = 'Treiber im Spooler-Prozess'; values = @('print.driversInSpooler')
                    rules = @{ check = @(@{ value = 'print.driversInSpooler'; op = 'gt'; than = 0 }); act = @(@{ value = 'print.driversInSpooler'; op = 'gt'; than = 0 }, @{ event = 'print'; min = 1; days = 7 }) }
                    findings = @{ ok = 'Kein Treiber im Spooler.'; check = '{print.driversInSpooler} Treiber im Spooler.'; act = '{print.driversInSpooler} Treiber im Spooler, Druckereignisse.'; unknown = '{reason}' }
                    meaning = 'm'; todo = $todo; source = @{ vendor = 'Microsoft'; title = 'Printer Driver Isolation'; url = 'https://learn.microsoft.com/x'; date = '2026-11-13' }
                    kind = 'vendor'; relates = @('print', 'pattern.printdriver') }) }
        foreach ($id in (Get-WorkerPerfHealthFactTable).Keys) { $c.values[$id] = "Wert $id" }
        foreach ($k in $WorkerPerfHealthCopyKeys.Keys) { $c.copy[$k] = "Text $k" }
        $c.copy.yes = 'ja'; $c.copy.no = 'nein'; $c.copy.noValue = '–'; $c.copy.reasonSkipped = '{category} nicht erfasst'; $c.copy.notApplicable = 'Trifft nicht zu: {reason}.'
        $c.copy.reasonNotInstalled = '{label} fehlt'; $c.copy.reasonNotInUse = '{label} nicht in Gebrauch'; $c.copy.reasonAppNotInstalled = '{app} ist nicht installiert'
        $c.copy.summary = '{act} zum Handeln, {check} zum Prüfen, {ok} in Ordnung'; $c.copy.areaOne = '1 Bereich'; $c.copy.areaMany = '{n} Bereiche'
        $c.copy.countsAct = '{n} zum Handeln'; $c.copy.countsCheck = '{n} zum Prüfen'; $c.copy.countsUnknown = '{n} nicht prüfbar'
        $c.copy.copyCheckTitle = '{area} – {title}: {grade}'; $c.copy.copyAreaTitle = '{area}: {grade}'; $c.copy.copyAreaItem = '- {title}: {grade}. {finding}'
        . $Change
        $file = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.json'); [IO.File]::WriteAllText($file, (ConvertTo-Json -InputObject $c -Depth 12)); $file
    }
}
Describe 'Katalog des Zustandsbilds laden und pruefen' {
    It 'liest einen vollstaendigen Katalog und kennt jeden Fakt' {
        $c = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue)
        @($c.checks).Count | Should -Be 2; $c.thresholds.diskFreeGB.value | Should -Be 10; $c.areas[0].id | Should -Be 'size'; $c.grades.act.word | Should -Be 'Handeln'
        $t = Get-WorkerPerfHealthFactTable; @($t.Keys).Count | Should -Be 164; @($WorkerPerfHealthDerived.Keys).Count | Should -Be 61
        $ta = Get-WorkerPerfHealthFactTable $TestApps; @($ta.Keys).Count | Should -Be 206                         # 164 feste, 38 der ausgelieferten Liste, 4 der simapp
        $ta['apps.edge.installed'].Area | Should -Be 'apps'; $ta['apps.edge.installed'].Type | Should -Be 'bool'; $ta['apps.edge.backgroundMode'].Type | Should -Be 'value'
        $ta['apps.edge.userDataDir'].Type | Should -Be 'text:free'; $ta['apps.office.updateTask'].Type | Should -Be 'bool'; $ta['apps.office.platform'].Documented | Should -BeFalse
        $ta['apps.simapp.cacheMode'].Label | Should -Be 'Sim-Fachanwendung – Cache-Betriebsart'; $ta['apps.simapp.installed'].Label | Should -Be 'Sim-Fachanwendung'; $t['size.cpuLogical'].Label | Should -Be ''
        $t['events.reachFrom'].Type | Should -Be 'time'; $t['operation.pendingUpdate'].Documented | Should -BeFalse; $t['operation.minFreeGB'].Documented | Should -BeTrue
        $t['size.cpuLogical'].Derived | Should -BeFalse; $t['operation.minFreeGB'].Derived | Should -BeTrue; $t['operation.minFreeGB'].Unit | Should -Be 'GB'; $t['events.perDay'].Type | Should -Be 'list'
    }
    It 'nennt Pruefung und Feld eines Fehlers' -TestCases @(
        @{ Change = { $c.checks[0].Remove('source') }; Msg = "*Pruefung 'operation.diskFree'*Feld 'source'*" }
        @{ Change = { $c.checks[0].Remove('kind') }; Msg = "*Pruefung 'operation.diskFree'*Feld 'kind'*" }
        @{ Change = { $c.checks[0].meaning = '' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'meaning'*" }
        @{ Change = { $c.checks[0].title = '' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'title'*" }
        @{ Change = { $c.checks[0].findings.Remove('unknown') }; Msg = "*Pruefung 'operation.diskFree'*Feld 'findings'*unknown*" }
        @{ Change = { $c.checks[0].findings.Remove('act') }; Msg = "*Pruefung 'operation.diskFree'*Feld 'findings'*act*" }
        @{ Change = { $c.checks[0].values = @('operation.gibtEsNicht') }; Msg = "*Pruefung 'operation.diskFree'*Feld 'values'*operation.gibtEsNicht*" }
        @{ Change = { $c.checks[0].area = 'wetter' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'area'*wetter*" }
        @{ Change = { $c.checks[0].rules.check[0].than = '@nix' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'rules'*@nix*" }
        @{ Change = { $c.checks[0].rules.check[0].op = 'like' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'rules'*like*" }
        @{ Change = { $c.checks[0].rules.check[0].value = 'size.cpuLogical' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'rules'*size.cpuLogical*values*" }
        @{ Change = { $c.checks[0].rules.act[0].Remove('hard') }; Msg = "*Pruefung 'operation.diskFree'*Feld 'rules'*act*harte Grenze*Ereignis*" }
        @{ Change = { $c.checks[1].rules.act[1].event = 'wetter' }; Msg = "*Pruefung 'print.driversInSpooler'*Feld 'rules'*wetter*" }
        @{ Change = { $c.checks[0].relates = @('disk', 'pattern.nix') }; Msg = "*Pruefung 'operation.diskFree'*Feld 'relates'*pattern.nix*" }
        @{ Change = { $c.checks[0].findings.check = '{size.cpuLogical} frei' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'findings'*{size.cpuLogical}*" }
        @{ Change = { $c.checks[0].findings.ok = '{reason}' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'findings'*{reason}*" }
        @{ Change = { $c.checks[0].findings.unknown = 'Nicht prüfbar.' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'findings'*unknown*{reason}*" }
        @{ Change = { $c.checks[1].source.url = '' }; Msg = "*Pruefung 'print.driversInSpooler'*Feld 'source'*url*" }
        @{ Change = { $c.checks[0].kind = 'practice' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'source'*url*" }                         # eine Praxisquelle braucht ihre Adresse
        @{ Change = { $c.checks[0].kind = 'praxis' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'kind'*praxis*" }
        @{ Change = { $c.checks[0].values = @('operation.minFreeGB', 'operation.pendingUpdate') }; Msg = "*Pruefung 'operation.diskFree'*Feld 'values'*operation.pendingUpdate*dokumentierte Lesequelle*" }
        @{ Change = { $c.grades.Remove('na') }; Msg = "*Teil 'grades'*na*" }
        @{ Change = { $c.checks[0].todo[0].Remove('sign') }; Msg = "*Pruefung 'operation.diskFree'*Feld 'todo'*sign*" }
        @{ Change = { $c.checks[0].todo = @() }; Msg = "*Pruefung 'operation.diskFree'*Feld 'todo' ist keine Liste mit mindestens einem Schritt*" }                                    # ohne Vorschlag zum Vorgehen
        @{ Change = { $c.checks[0].findings.check = '' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'findings'*check*" }
        @{ Change = { $c.checks[1].id = 'operation.diskFree' }; Msg = "*Pruefung 'operation.diskFree'*doppelt*" }
        @{ Change = { $c.checks[0].values = @('operation.volumes'); $c.checks[0].rules.check[0].value = 'operation.volumes' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'rules'*operation.volumes*Liste*" }
        @{ Change = { $c.thresholds.diskFreeGB.value = 'viel' }; Msg = "*Teil 'thresholds'*diskFreeGB*" }
        @{ Change = { $c.thresholds.Remove('workEndHour') }; Msg = "*Teil 'thresholds'*workEndHour*" }
        @{ Change = { $c.values.Remove('size.cpuLogical') }; Msg = "*Teil 'values'*size.cpuLogical*" }
        @{ Change = { $c.areas = @($c.areas | Select-Object -Skip 1) }; Msg = "*Teil 'areas' nennt nicht die elf Bereiche in ihrer Reihenfolge*" }
        @{ Change = { $c.copy.Remove('notRecorded') }; Msg = "*Teil 'copy'*notRecorded*" }
        @{ Change = { $c.copy.summary = '{act} und {wetter}' }; Msg = "*Teil 'copy'*summary*{wetter}*" }
        @{ Change = { $c.Remove('precedence') }; Msg = "*Teil 'precedence' fehlt*" }
        @{ Change = { $c.precedence = @(@{ check = 'operation.gibtEsNicht'; winner = 'practice'; reason = 'Betriebserfahrung' }) }; Msg = "*Teil 'precedence'*Pruefung 'operation.gibtEsNicht' unbekannt*" }      # ein Eintrag fuer eine Pruefung, die es nicht gibt
        @{ Change = { $c.precedence = @(@{ check = 'operation.diskFree'; winner = 'practice'; reason = 'Betriebserfahrung' }) }; Msg = "*Teil 'precedence'*Pruefung 'operation.diskFree'*practice*" }                  # die Pruefung ist eine Faustregel
        @{ Change = { $c.precedence = @(@{ check = 'print.driversInSpooler'; winner = 'vendor'; reason = 'r' }) }; Msg = "*Teil 'precedence'*Pruefung 'print.driversInSpooler'*winner*" }
        @{ Change = { $c.checks[0].kind = 'practice'; $c.checks[0].source.url = 'https://www.carlstalhood.com/citrix-health-check/'; $c.precedence = @(@{ check = 'operation.diskFree'; winner = 'practice'; reason = '' }) }; Msg = "*Teil 'precedence'*Pruefung 'operation.diskFree'*reason*" }
    ) { { Read-WorkerPerfHealthCatalogue (New-HealthCatalogue $Change) } | Should -Throw $Msg }
    It 'nimmt eine Praxisquelle mit Adresse an' {
        $c = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { $c.checks[0].kind = 'practice'; $c.checks[0].source = @{ vendor = 'Carl Stalhood'; title = 'Citrix Health Check'; url = 'https://www.carlstalhood.com/citrix-health-check/'; date = '2026-11-13' } })
        $c.checks[0].kind | Should -Be 'practice'; $WorkerPerfHealthKinds | Should -Be @('vendor', 'practice', 'rule'); @($c.precedence).Count | Should -Be 0
        # die Ausnahme des Auftraggebers: dieselbe Pruefung mit einem Eintrag in precedence
        $c = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { $c.checks[0].kind = 'practice'; $c.checks[0].source = @{ vendor = 'Carl Stalhood'; title = 'Citrix Health Check'; url = 'https://www.carlstalhood.com/citrix-health-check/'; date = '2026-11-13' }
            $c.precedence = @(@{ check = 'operation.diskFree'; winner = 'practice'; reason = 'Die Praxisquellen beziehen sich auf Citrix-Terminalserver.' }) })
        @($c.precedence).Count | Should -Be 1; $c.precedence[0].check | Should -Be 'operation.diskFree'; $c.precedence[0].winner | Should -Be 'practice'
    }
    It 'kennt die Fakten der Anwendungen aus der Anwendungsliste' {
        $c = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { & $ToApp 'apps.simapp.cacheMode' 'eq' 2 }) $TestApps
        $c.checks[0].id | Should -Be 'apps.simCache'; @($c.appList).Count | Should -Be $TestApps.Count
        { Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { & $ToApp 'apps.simapp.dataPath' 'exists' $null }) $TestApps } | Should -Not -Throw     # freier Text: nur vorhanden oder nicht
        # dieselbe Pruefung ohne die Anwendung in der Liste: abgelehnt
        { Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { & $ToApp 'apps.simapp.cacheMode' 'eq' 2 }) @($TestApps | Where-Object key -ne 'simapp') } |
            Should -Throw "*Pruefung 'apps.simCache'*Feld 'values'*Anwendung 'simapp' steht nicht in der Anwendungsliste*"
    }
    It 'lehnt eine fehlerhafte Pruefung des Bereichs apps ab' -TestCases @(
        @{ Change = { & $ToApp 'apps.simapp.gibtEsNicht' 'eq' 2 }; Msg = "*Pruefung 'apps.simCache'*Feld 'values'*apps.simapp.gibtEsNicht*" }
        @{ Change = { & $ToApp 'apps.office.platform' 'eq' 'x86' }; Msg = "*Pruefung 'apps.simCache'*Feld 'values'*apps.office.platform*dokumentierte Lesequelle*" }
        @{ Change = { & $ToApp 'apps.simapp.cacheMode' 'eq' 2; $c.checks[0].values = @('apps.simapp.cacheMode', 'apps.edge.backgroundMode') }; Msg = "*Pruefung 'apps.simCache'*Feld 'values'*mehr als einer Anwendung*" }
        @{ Change = { & $ToApp 'apps.simapp.cacheMode' 'eq' 2; $c.checks[0].values = @('apps.simapp.cacheMode', 'size.cpuLogical') }; Msg = "*Pruefung 'apps.simCache'*Feld 'values'*size.cpuLogical*" }
        @{ Change = { $c.checks[0].values = @('operation.minFreeGB', 'apps.simapp.cacheMode') }; Msg = "*Pruefung 'operation.diskFree'*Feld 'values'*apps.simapp.cacheMode*Bereich apps*" }
        @{ Change = { & $ToApp 'apps.simapp.dataPath' 'eq' 'x' }; Msg = "*Pruefung 'apps.simCache'*Feld 'rules'*apps.simapp.dataPath*exists*" }
        @{ Change = { & $ToApp 'apps.simapp.dataPath' 'exists' $null; $c.checks[0].findings.check = 'Pfad {apps.simapp.dataPath}' }; Msg = "*Pruefung 'apps.simCache'*Feld 'findings'*{apps.simapp.dataPath}*" }
    ) { { Read-WorkerPerfHealthCatalogue (New-HealthCatalogue $Change) $TestApps } | Should -Throw $Msg }
    It 'vergleicht einen Ja/Nein-Wert nur mit eq und ne' {
        # Ruling ZB-R14: than may be a boolean, compared only with eq and ne
        $ToBool = { param($Op) $c.checks[0].values = @('operation.minFreeGB', 'size.pagefileManaged')
            $c.checks[0].rules.check = @(@{ value = 'size.pagefileManaged'; op = $Op; than = $true }) }
        $c = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { & $ToBool 'eq' })
        $c.checks[0].rules.check[0].than | Should -BeTrue
        { Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { & $ToBool 'lt' }) } | Should -Throw "*Pruefung 'operation.diskFree'*Feld 'rules'*size.pagefileManaged*eq*ne*"
    }
    It 'vergleicht einen Fakt nur so, wie sein Typ es erlaubt' -TestCases @(
        # Ruling ZB-R25: Operator und than passen zum Typ des Fakts (eine Tabelle)
        @{ Fact = 'size.model'; Op = 'lt'; Than = 5; Msg = "*Pruefung 'operation.diskFree'*Feld 'rules' Regel 'check', Bedingung 1: vergleicht 'size.model' (Typ 'text') mit 'lt'; erlaubt bei diesem Typ: eq, ne, contains mit Text; in mit Liste von Texten; exists, absent ohne Vergleichswert." }
        @{ Fact = 'size.cpuLogical'; Op = 'contains'; Than = 5; Msg = "*Pruefung 'operation.diskFree'*Feld 'rules'*vergleicht 'size.cpuLogical' (Typ 'number') mit 'contains'; erlaubt bei diesem Typ: gt, ge, lt, le, eq, ne mit Zahl oder Schwelle; in mit Liste von Zahlen; exists, absent ohne Vergleichswert." }
        @{ Fact = 'size.cpuLogical'; Op = 'eq'; Than = $true; Msg = "*Pruefung 'operation.diskFree'*Feld 'rules'*vergleicht 'size.cpuLogical' (Typ 'number') mit 'eq' und Ja/Nein-Wert; erlaubt bei diesem Typ: gt, ge*" }
        @{ Fact = 'size.cpuLogical'; Op = 'eq'; Than = 'acht'; Msg = "*Pruefung 'operation.diskFree'*Feld 'rules'*vergleicht 'size.cpuLogical' (Typ 'number') mit 'eq' und Text; erlaubt*" }
        @{ Fact = 'size.cpuLogical'; Op = 'in'; Than = @('a', 'b'); Msg = "*Pruefung 'operation.diskFree'*Feld 'rules'*vergleicht 'size.cpuLogical' (Typ 'number') mit 'in' und Liste von Texten; erlaubt*" }
        @{ Fact = 'size.pagefileManaged'; Op = 'eq'; Than = '@diskFreeGB'; Msg = "*Pruefung 'operation.diskFree'*Feld 'rules'*vergleicht 'size.pagefileManaged' (Typ 'bool') mit 'eq' und Schwelle; erlaubt bei diesem Typ: eq, ne mit Ja/Nein-Wert; exists, absent ohne Vergleichswert." }
        @{ Fact = 'operation.powerPlan'; Op = 'eq'; Than = '@diskFreeGB'; Msg = "*Pruefung 'operation.diskFree'*Feld 'rules'*vergleicht 'operation.powerPlan' (Typ 'text') mit 'eq' und Schwelle*" }
        @{ Fact = 'operation.lastBoot'; Op = 'gt'; Than = 5; Msg = "*Pruefung 'operation.diskFree'*Feld 'rules'*vergleicht 'operation.lastBoot' (Typ 'time') mit 'gt'; erlaubt bei diesem Typ: exists, absent ohne Vergleichswert." }
        @{ Fact = 'vda.wemCacheLocation'; Op = 'lt'; Than = 5; Msg = "*Pruefung 'operation.diskFree'*Feld 'rules'*vergleicht 'vda.wemCacheLocation' (Typ 'text:path') mit 'lt'; erlaubt bei diesem Typ: eq, ne, contains mit Text*" }
    ) {
        { Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { $c.checks[0].values = @('operation.minFreeGB', $Fact); $c.checks[0].rules.check = @(@{ value = $Fact; op = $Op; than = $Than }) }) } | Should -Throw $Msg
    }
    It 'nimmt jede Bedingungsform der geplanten Pruefungen an' -TestCases @(
        # die Formen der Pruefungstabellen des Plans (Zahl, Ja/Nein, Text, Pfad, freier Text, Zeit, Wert einer Probe), dazu in und contains
        @{ Fact = 'size.cpuLogical'; Op = 'gt'; Than = 0 }, @{ Fact = 'size.cpuLogical'; Op = 'ge'; Than = '@diskFreeGB' }, @{ Fact = 'size.cpuLogical'; Op = 'lt'; Than = 12 }
        @{ Fact = 'size.cpuLogical'; Op = 'le'; Than = 1.5 }, @{ Fact = 'size.cpuLogical'; Op = 'eq'; Than = 1 }, @{ Fact = 'size.cpuLogical'; Op = 'ne'; Than = 8 }
        @{ Fact = 'size.cpuLogical'; Op = 'in'; Than = @(1, 2) }, @{ Fact = 'size.cpuLogical'; Op = 'exists'; Than = $null }, @{ Fact = 'sessions.disconnectLimitMin'; Op = 'absent'; Than = $null }
        @{ Fact = 'size.pagefileManaged'; Op = 'eq'; Than = $true }, @{ Fact = 'size.pagefileManaged'; Op = 'ne'; Than = $false }
        @{ Fact = 'operation.powerPlan'; Op = 'ne'; Than = 'highPerformance' }, @{ Fact = 'security.defenderMode'; Op = 'eq'; Than = 'Normal' }
        @{ Fact = 'operation.powerPlan'; Op = 'contains'; Than = 'high' }, @{ Fact = 'operation.powerPlan'; Op = 'in'; Than = @('balanced', 'other') }
        @{ Fact = 'vda.wemService'; Op = 'exists'; Than = $null }, @{ Fact = 'vda.wemCacheLocation'; Op = 'absent'; Than = $null }, @{ Fact = 'vda.wemCacheLocation'; Op = 'contains'; Than = 'Program Files' }
        @{ Fact = 'operation.lastBoot'; Op = 'exists'; Than = $null }
    ) {
        $c = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { $c.checks[0].values = @('operation.minFreeGB', $Fact); $c.checks[0].rules.check = @(@{ value = $Fact; op = $Op; than = $Than }) })
        $c.checks[0].rules.check[0].op | Should -Be $Op
    }
    It 'vergleicht den Wert einer Probe mit jedem Operator' -TestCases @(
        @{ Op = 'gt'; Than = 1 }, @{ Op = 'le'; Than = '@workEndHour' }, @{ Op = 'eq'; Than = 0 }, @{ Op = 'ne'; Than = 1 }, @{ Op = 'eq'; Than = $true }, @{ Op = 'ne'; Than = 'aus' }
        @{ Op = 'in'; Than = @(1, 2) }, @{ Op = 'in'; Than = @('a', 'b') }, @{ Op = 'contains'; Than = 'x' }, @{ Op = 'exists'; Than = $null }, @{ Op = 'absent'; Than = $null }
    ) {
        { Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { & $ToApp 'apps.simapp.cacheMode' $Op $Than }) $TestApps } | Should -Not -Throw
    }
    It 'lehnt ein unbekanntes Feld in jedem Teil ab' -TestCases @(
        @{ Change = { $c.checks[0].source.Remove('url'); $c.checks[0].source.adress = 'https://example.org/seite' }; Msg = "*Pruefung 'operation.diskFree': Feld 'source' nennt das unbekannte Feld 'adress' (erlaubt: vendor, title, url, date).*" }
        @{ Change = { $c.checks[0].rule = $c.checks[0].rules }; Msg = "*Pruefung 'operation.diskFree': Feld 'rule' ist unbekannt (erlaubt: id, area, *" }
        @{ Change = { $c.thresholds.diskFreeGB.dfault = 10 }; Msg = "*Teil 'thresholds' nennt bei der Schwelle 'diskFreeGB' das unbekannte Feld 'dfault'*" }
        @{ Change = { $c.checks[0].todo = @(@{ text = 't'; where = 'w'; sing = 's' }) }; Msg = "*Pruefung 'operation.diskFree': Feld 'todo' Schritt 1: nennt das unbekannte Feld 'sing'*" }
        @{ Change = { $c.checks[0].kind = 'practice'; $c.checks[0].source.url = 'https://www.carlstalhood.com/citrix-health-check/'; $c.precedence = @(@{ check = 'operation.diskFree'; winner = 'practice'; reasn = 'Betriebserfahrung' }) }; Msg = "*Teil 'precedence': Pruefung 'operation.diskFree': Feld 'reasn' ist unbekannt*" }
        @{ Change = { $c.areas[0].lable = 'x' }; Msg = "*Teil 'areas' nennt beim Bereich 'size' das unbekannte Feld 'lable'*" }
        @{ Change = { $c.grades.ok.wort = 'x' }; Msg = "*Teil 'grades' nennt bei 'ok' das unbekannte Feld 'wort'*" }
        @{ Change = { $c.checks[0].findings.warn = 'x' }; Msg = "*Pruefung 'operation.diskFree': Feld 'findings' nennt den unbekannten Satz 'warn'*" }
        @{ Change = { $c.copy.titel = 'x' }; Msg = "*Teil 'copy' nennt den unbekannten Text 'titel'*" }
        @{ Change = { $c.extra = 1 }; Msg = "*Teil 'extra' ist unbekannt*" }
        @{ Change = { $c.checks[0].rules.check[0].thann = 1 }; Msg = "*Feld 'rules' Regel 'check', Bedingung 1: enthaelt das Feld 'thann', das hier nicht gilt*" }
        # Namen gelten nur in genau dieser Schreibweise
        @{ Change = { $c.grades.ok = @{ Word = 'In Ordnung'; symbol = 'o' } }; Msg = "*Teil 'grades' nennt bei 'ok' das unbekannte Feld 'Word'*" }
        @{ Change = { $c.areas[0] = [ordered]@{ id = 'size'; Label = 'Groesse'; notCovered = '' } }; Msg = "*Teil 'areas' nennt beim Bereich 'size' das unbekannte Feld 'Label'*" }
        @{ Change = { $c.thresholds.diskFreeGB = @{ value = 10; default = 10; unit = 'GB'; Label = 'Freier Platz' } }; Msg = "*Schwelle 'diskFreeGB' das unbekannte Feld 'Label'*" }
        @{ Change = { $c.checks[0].Remove('title'); $c.checks[0].Title = 'Freier Platz' }; Msg = "*Pruefung 'operation.diskFree': Feld 'Title' ist unbekannt*" }
    ) { { Read-WorkerPerfHealthCatalogue (New-HealthCatalogue $Change) } | Should -Throw $Msg }
    It 'lehnt Unstimmigkeiten zwischen den Teilen ab' -TestCases @(
        @{ Change = { $c.checks[0].rules.check[0] = @{ value = 'operation.minFreeGB'; op = 'in'; than = @(1, 'a') } }; Msg = "*Feld 'rules' Regel 'check', Bedingung 1: nennt in 'than' eine Liste, die Zahlen und Texte mischt*" }
        @{ Change = { $c.thresholds.spare = @{ value = 1; default = 1; unit = ''; label = 'Reserve' } }; Msg = "*Teil 'thresholds' nennt die Schwelle 'spare', die weder eine Regel noch ein Befundsatz nutzt*" }
        @{ Change = { $c.checks[0].rules.Remove('act') }; Msg = "*Pruefung 'operation.diskFree': Feld 'findings' nennt den Satz 'act', aber die Pruefung hat keine Regel 'act'*" }
        @{ Change = { $c.checks[1].rules.Remove('check') }; Msg = "*Pruefung 'print.driversInSpooler': Feld 'findings' nennt den Satz 'check', aber die Pruefung hat keine Regel 'check'*" }
        @{ Change = { $c.checks[0].values = @('operation.minFreeGB', 'operation.minFreeGB') }; Msg = "*Feld 'values' nennt 'operation.minFreeGB' mehr als einmal*" }
        @{ Change = { $c.checks[1].id = 'operation.DiskFree' }; Msg = "*Pruefung 'operation.DiskFree': Feld 'id' unterscheidet sich von der Pruefung 'operation.diskFree' nur in Gross- und Kleinschreibung*" }
        @{ Change = { $c.areas[0].id = 'Size' }; Msg = "*Teil 'areas' nennt nicht die elf Bereiche in ihrer Reihenfolge*" }
        @{ Change = { $c.checks[0].area = 'Operation' }; Msg = "*Feld 'area' nennt den unbekannten Bereich 'Operation'*" }
    ) { { Read-WorkerPerfHealthCatalogue (New-HealthCatalogue $Change) } | Should -Throw $Msg }
    It 'lehnt zwei Schwellen ab, die sich nur in der Schreibweise unterscheiden' {
        # schon das Lesen der Datei scheitert (ConvertFrom-Json beider Shells lehnt solche Schluessel ab)
        $file = New-HealthCatalogue
        [IO.File]::WriteAllText($file, [IO.File]::ReadAllText($file).Replace('"diskFreeHardGB":', '"DiskFreeGB":'))
        { Read-WorkerPerfHealthCatalogue $file } | Should -Throw "Datei '$file' ist nicht lesbar oder kein gueltiges JSON:*"
    }
    It 'prueft die uebrigen Regeln des Laders' -TestCases @(
        @{ Change = { $c.checks[1].rules.act[1].value = 'print.driversInSpooler' }; Msg = "*Pruefung 'print.driversInSpooler': Feld 'rules' Regel 'act', Bedingung 2: braucht genau eines der Felder 'value' und 'event'*" }
        @{ Change = { $c.checks[1].rules.act[1].min = 0 }; Msg = "*Regel 'act', Bedingung 2: braucht in 'min' eine ganze Zahl ab 1*" }
        @{ Change = { $c.checks[1].rules.act[1].days = 1.5 }; Msg = "*Regel 'act', Bedingung 2: braucht in 'days' eine ganze Zahl ab 1*" }
        @{ Change = { $c.checks[0].rules.check[0] = @{ value = 'operation.minFreeGB'; op = 'exists'; than = 1 } }; Msg = "*Regel 'check', Bedingung 1: braucht bei 'exists' kein 'than'*" }
        @{ Change = { $c.checks[0].rules.check[0] = @{ value = 'operation.minFreeGB'; op = 'absent'; than = 'x' } }; Msg = "*Regel 'check', Bedingung 1: braucht bei 'absent' kein 'than'*" }
        @{ Change = { $c.checks[0].findings.check = 'Schwelle {@unbekannt}' }; Msg = "*Feld 'findings' Satz 'check' enthaelt den Platzhalter '{@unbekannt}' einer unbekannten Schwelle*" }
        @{ Change = { $c.checks[0].values = @('operation.minFreeGB', 'operation.volumes'); $c.checks[0].findings.ok = 'Laufwerke {operation.volumes}' }; Msg = "*Feld 'findings' Satz 'ok' enthaelt den Platzhalter '{operation.volumes}' eines Listenwerts*" }
        @{ Change = { $c.checks[0].kind = 'practice'; $c.checks[0].source.url = 'https://www.carlstalhood.com/citrix-health-check/'
                $c.precedence = @(@{ check = 'operation.diskFree'; winner = 'practice'; reason = 'r' }, @{ check = 'operation.diskFree'; winner = 'practice'; reason = 'r' }) }; Msg = "*Teil 'precedence': Pruefung 'operation.diskFree' steht mehr als einmal in der Liste*" }
        @{ Change = { $c.checks[0].relates = @('disk', 'wetter') }; Msg = "*Feld 'relates' nennt den unbekannten Bezug 'wetter'*" }
        @{ Change = { $c.checks[0].rules.warn = @(@{ value = 'operation.minFreeGB'; op = 'exists' }) }; Msg = "*Feld 'rules' nennt die unbekannte Regel 'warn'*" }
        @{ Change = { $c.checks[0].rules = @{} }; Msg = "*Feld 'rules' braucht mindestens eine der Regeln 'check' und 'act'*" }
        @{ Change = { $c.checks[0].findings.ok = '{operation.minFreeGB} GB frei }' }; Msg = "*Feld 'findings' Satz 'ok' enthaelt eine geschweifte Klammer ohne Platzhalter*" }
        @{ Change = { $c.copy.title = 'Zustand {' }; Msg = "*Teil 'copy' Text 'title' enthaelt eine geschweifte Klammer ohne Platzhalter*" }
        # ein Datum hat auf beiden Shells dieselbe Form und dieselbe Meldung (PowerShell 7 liest '…T10:00:00' als DateTime)
        @{ Change = { $c.version = '2026-11-13T10:00:00' }; Msg = "Katalog '*': Teil 'version' ist kein Datum der Form JJJJ-MM-TT." }
        @{ Change = { $c.version = 'Fassung 1' }; Msg = "Katalog '*': Teil 'version' ist kein Datum der Form JJJJ-MM-TT." }
        @{ Change = { $c.version = '2026-02-30' }; Msg = "Katalog '*': Teil 'version' ist kein Datum der Form JJJJ-MM-TT." }
        @{ Change = { $c.checks[0].source.date = '2026-11-13T10:00:00' }; Msg = "Katalog '*': Pruefung 'operation.diskFree': Feld 'source' 'date' ist kein Datum der Form JJJJ-MM-TT." }
        @{ Change = { $c.checks[0].source.date = '13.11.2026' }; Msg = "Katalog '*': Pruefung 'operation.diskFree': Feld 'source' 'date' ist kein Datum der Form JJJJ-MM-TT." }
    ) { { Read-WorkerPerfHealthCatalogue (New-HealthCatalogue $Change) } | Should -Throw $Msg }
    It 'verlangt die Listen der vorher eingebundenen Dateien' -TestCases @(
        @{ Files = @('Common', 'Events', 'Health'); Msg = "Katalog 'k.json': die Situationen fehlen; WorkerPerf.Guidance.ps1 muss vor dem Laden des Katalogs eingebunden sein." }
        @{ Files = @('Common', 'Guidance', 'Health'); Msg = "Katalog 'k.json': die Muster fehlen; WorkerPerf.Events.ps1 muss vor dem Laden des Katalogs eingebunden sein." }
    ) {
        # ein frischer Prozess, der eine der beiden Dateien nicht einbindet
        $run = Join-Path $TestDrive 'guard.ps1'
        $lines = @('Set-StrictMode -Version 2') + @($Files | ForEach-Object { ". '" + (Join-Path $PSScriptRoot "../src/WorkerPerf.$_.ps1") + "'" }) +
            @('try { Read-WorkerPerfHealthCatalogue ''k.json''; ''kein Fehler'' } catch { $_.Exception.Message }')
        [IO.File]::WriteAllText($run, ($lines -join "`n"))
        $out = @(& (Get-Process -Id $PID).Path -NoProfile -File $run)
        $out[-1] | Should -BeExactly $Msg
    }
    It 'liefert jedes Feld auch ohne Angabe im Katalog' {
        $c = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue {
                $c.checks[0].rules = @{ check = @(@{ value = 'operation.minFreeGB'; op = 'exists' }, @{ value = 'operation.minFreeGB'; op = 'lt'; than = '@diskFreeGB' }) }
                $c.checks[0].findings.Remove('act'); $c.checks[0].source.Remove('url'); $c.checks[0].relates = @('disk'); $c.thresholds.Remove('diskFreeHardGB')
                $c.checks[1].rules.Remove('check'); $c.checks[1].findings.Remove('check') })
        $k = $c.checks[0]
        $k.rules.act -is [array] | Should -BeTrue; $k.rules.act.Count | Should -Be 0; $k.findings.act | Should -BeExactly ''; $k.source.url | Should -BeExactly ''
        $k.rules.check[0].than | Should -BeNullOrEmpty; $k.rules.check[0].hard | Should -BeExactly $false; $k.rules.check[0].event | Should -BeNullOrEmpty
        $k.rules.check[0].min | Should -BeNullOrEmpty; $k.rules.check[0].days | Should -BeNullOrEmpty; $k.rules.check[1].than | Should -Be '@diskFreeGB'
        $k.values -is [array] | Should -BeTrue; $k.values.Count | Should -Be 1; $k.relates -is [array] | Should -BeTrue; $k.relates.Count | Should -Be 1
        $k.todo -is [array] | Should -BeTrue; $k.todo.Count | Should -Be 1
        $p = $c.checks[1]
        $p.rules.check -is [array] | Should -BeTrue; $p.rules.check.Count | Should -Be 0; $p.findings.check | Should -BeExactly ''
        $p.rules.act[0].hard | Should -BeExactly $false; $p.rules.act[0].event | Should -BeNullOrEmpty
        $p.rules.act[1].event | Should -Be 'print'; $p.rules.act[1].value | Should -BeNullOrEmpty; $p.rules.act[1].op | Should -BeNullOrEmpty
        $p.rules.act[1].than | Should -BeNullOrEmpty; $p.rules.act[1].hard | Should -BeExactly $false; $p.rules.act[1].days | Should -Be 7
        $c.precedence -is [array] | Should -BeTrue; $c.precedence.Count | Should -Be 0; $c.appList -is [array] | Should -BeTrue
        $c.checks -is [array] | Should -BeTrue; $c.areas -is [array] | Should -BeTrue
    }
    It 'nennt die geaenderten Schwellen' {
        $c = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { $c.thresholds.diskFreeGB.value = 25 })
        $ch = @(Get-WorkerPerfHealthChangedThresholds $c); $ch.Count | Should -Be 1
        $ch[0].id | Should -Be 'diskFreeGB'; $ch[0].value | Should -Be 25; $ch[0].default | Should -Be 10; $ch[0].unit | Should -Be 'GB'; $ch[0].label | Should -Be 'Freier Platz'
    }
}
