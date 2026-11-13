BeforeAll {
    Set-StrictMode -Version 2
    foreach ($f in 'Common', 'EventConfig', 'Events', 'Findings', 'Guidance', 'Load', 'Health') { . (Join-Path $PSScriptRoot "../src/WorkerPerf.$f.ps1") }
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1'); $script:TestApps = @(Read-WorkerPerfHealthApps (New-TestAppFile $TestDrive))      # Edge, Office, Teams und die erfundene simapp
    $script:ToApp = { param($Fact, $Op, $Than)
        # macht die erste Pruefung des kleinen Katalogs zu einer Pruefung des Bereichs apps auf einen Fakt
        $c.checks[0].id = 'apps.simCache'; $c.checks[0].area = 'apps'; $c.checks[0].values = @($Fact)
        $c.checks[0].rules = @{ check = @(@{ value = $Fact; op = $Op; than = $Than }) }
        $c.checks[0].findings = @{ ok = 'in Ordnung'; check = 'auffaellig'; unknown = '{reason}' } }
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
        @{ Change = { $c.checks[0].todo = @() }; Msg = "*Pruefung 'operation.diskFree'*Feld 'todo'*" }                                    # ohne Vorschlag zum Vorgehen
        @{ Change = { $c.checks[0].findings.check = '' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'findings'*check*" }
        @{ Change = { $c.checks[1].id = 'operation.diskFree' }; Msg = "*Pruefung 'operation.diskFree'*doppelt*" }
        @{ Change = { $c.checks[0].values = @('operation.volumes'); $c.checks[0].rules.check[0].value = 'operation.volumes' }; Msg = "*Pruefung 'operation.diskFree'*Feld 'rules'*operation.volumes*Liste*" }
        @{ Change = { $c.thresholds.diskFreeGB.value = 'viel' }; Msg = "*Teil 'thresholds'*diskFreeGB*" }
        @{ Change = { $c.thresholds.Remove('workEndHour') }; Msg = "*Teil 'thresholds'*workEndHour*" }
        @{ Change = { $c.values.Remove('size.cpuLogical') }; Msg = "*Teil 'values'*size.cpuLogical*" }
        @{ Change = { $c.areas = @($c.areas | Select-Object -Skip 1) }; Msg = "*Teil 'areas'*" }
        @{ Change = { $c.copy.Remove('notRecorded') }; Msg = "*Teil 'copy'*notRecorded*" }
        @{ Change = { $c.copy.summary = '{act} und {wetter}' }; Msg = "*Teil 'copy'*summary*{wetter}*" }
        @{ Change = { $c.Remove('precedence') }; Msg = "*Teil 'precedence'*" }
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
    It 'nennt die geaenderten Schwellen' {
        $c = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { $c.thresholds.diskFreeGB.value = 25 })
        $ch = @(Get-WorkerPerfHealthChangedThresholds $c); $ch.Count | Should -Be 1
        $ch[0].id | Should -Be 'diskFreeGB'; $ch[0].value | Should -Be 25; $ch[0].default | Should -Be 10; $ch[0].unit | Should -Be 'GB'; $ch[0].label | Should -Be 'Freier Platz'
    }
}
