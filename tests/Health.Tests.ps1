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
    $script:ReadMs = ([DateTimeOffset]'2026-01-15T08:00:00+01:00').ToUnixTimeMilliseconds()          # ein Donnerstag
    $script:Cfg = Read-WorkerPerfEventConfig (Join-Path $PSScriptRoot '../src/events.json'); $script:Roles = @(Read-WorkerPerfRoles (Join-Path $PSScriptRoot '../src/roles.json'))
    $script:Texts = Read-WorkerPerfTexts (Join-Path $PSScriptRoot '../src/texts.de.json'); $script:Cat = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue)
    function New-HealthModel([hashtable]$Values = @{}, [hashtable]$With = @{}) {
        # Model mit einem Zustandsbild: die genannten Werte gelesen (oder als New-WorkerPerfHealthValue uebergeben), alle anderen nicht vorhanden;
        # Rueckblick und Treiberliste gelesen und leer
        $areas = [ordered]@{}
        foreach ($a in $WorkerPerfHealthAreas) {
            $v = @{}
            foreach ($id in @($WorkerPerfHealthValues.Keys | Where-Object { $WorkerPerfHealthValues[$_].Area -eq $a })) {
                if (-not $Values.ContainsKey($id)) { $v[$id] = New-WorkerPerfHealthValue 'absent'; continue }
                $x = $Values[$id]; $v[$id] = $(if ($x -is [System.Collections.IDictionary] -and $x.Contains('State')) { $x } else { New-WorkerPerfHealthValue 'read' '' $x })
            }
            $areas[$a] = Complete-WorkerPerfHealthArea $a $v 1
        }
        $m = @{ Health = @{ FormatVersion = 1; ReadAtMs = $ReadMs; OffsetMinutes = 60; DurationMs = 10; Areas = $areas }; HealthState = 'read'; Skip = [string[]]@()
            Meta = @{ EventLookbackDays = 7; HealthOnly = $false; OffsetMinutes = 60; Computer = 'T1' }; CaptureStartMs = $ReadMs + 5000; EventsBefore = @(); EventsAll = @(); PrintDrivers = @()
            Recorded = @{ EventsBefore = $true; PrintDrivers = $true }; SourceErrors = @() }
        foreach ($k in $With.Keys) { $m[$k] = $With[$k] }; $m
    }
    function New-Ev([double]$DaysBefore, [string]$Kind, [string]$Group = 'app', [string]$App = '') {
        @{ TimeMs = $ReadMs - [long]($DaysBefore * 86400000); OffsetMinutes = 60; Kind = $Kind; Group = $Group; App = $App; Service = ''; Log = 'application' } }
    function New-SourceError([string]$Source) { @{ Source = $Source; Count = 1; FirstMs = $null; FirstMessage = 'Testfehler' } }
    function Get-Facts([hashtable]$Values = @{}, [hashtable]$With = @{}, $Roles = $script:Roles) { Get-WorkerPerfHealthFacts -Model (New-HealthModel $Values $With) -Catalogue $Cat -EventConfig $Cfg -Roles $Roles }
    # ein Eintrag von health.json, wie ihn eine andere Fassung schreiben koennte: State, Reason und Value ungeprueft
    function New-Raw($Value, [string]$State = 'read', [string]$Reason = '') { [ordered]@{ State = $State; Reason = $Reason; Value = $Value } }
    function New-RawModel([hashtable]$Raw, [hashtable]$Values = @{}, [hashtable]$With = @{}) {
        # wie New-HealthModel, die Eintraege in $Raw aber an Complete-WorkerPerfHealthArea vorbei unveraendert im Bereich
        $m = New-HealthModel $Values $With
        foreach ($id in $Raw.Keys) { $m.Health.Areas[$WorkerPerfHealthValues[$id].Area].Values[$id] = $Raw[$id] }; $m
    }
    function Get-RawFacts([hashtable]$Raw, [hashtable]$Values = @{}, [hashtable]$With = @{}) { Get-WorkerPerfHealthFacts -Model (New-RawModel $Raw $Values $With) -Catalogue $Cat -EventConfig $Cfg -Roles $script:Roles }
    function Get-Check([hashtable]$Values, [hashtable]$With = @{}, [string]$Id = 'operation.diskFree', $Catalogue = $script:Cat) {
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel $Values $With) -Catalogue $Catalogue -EventConfig $Cfg -Roles $Roles -Texts $Texts
        @($r.areas | ForEach-Object { $_.checks }) | Where-Object id -eq $Id }
    $script:NoLookback = @{ Skip = [string[]]@('Ereignisse', 'Rueckblick'); Meta = @{ EventLookbackDays = 0; HealthOnly = $false; OffsetMinutes = 60; Computer = 'T1' } }
    $script:HpNone = @(@{ Name = 'A'; Manufacturer = 'HP'; Type = 3; Isolation = 'none' })
    function Get-Vol([double]$Free) { @{ 'operation.volumes' = @(@{ Drive = 'C:'; SizeGB = 100; FreeGB = $Free; FileSystem = 'NTFS'; System = $true; PageFile = $true }) } }
}
Describe 'Katalog des Zustandsbilds laden und pruefen' {
    It 'liest einen vollstaendigen Katalog und kennt jeden Fakt' {
        $c = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue)
        @($c.checks).Count | Should -Be 2; $c.thresholds.diskFreeGB.value | Should -Be 10; $c.areas[0].id | Should -Be 'size'; $c.grades.act.word | Should -Be 'Handeln'
        $t = Get-WorkerPerfHealthFactTable; @($t.Keys).Count | Should -Be 168; @($WorkerPerfHealthDerived.Keys).Count | Should -Be 62
        $ta = Get-WorkerPerfHealthFactTable $TestApps; @($ta.Keys).Count | Should -Be 210                         # 168 feste, 38 der ausgelieferten Liste, 4 der simapp
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
        # der Wert einer Probe ist eine Zahl (DWORD) oder ein Text, nie ein Ja/Nein-Wert: ein Vergleich damit waere immer falsch
        @{ Change = { & $ToApp 'apps.simapp.cacheMode' 'eq' $true }; Msg = "*Pruefung 'apps.simCache'*Feld 'rules' Regel 'check', Bedingung 1: vergleicht 'apps.simapp.cacheMode' (Typ 'value') mit 'eq' und Ja/Nein-Wert; erlaubt bei diesem Typ: *" }
        @{ Change = { & $ToApp 'apps.simapp.cacheMode' 'ne' $false }; Msg = "*Pruefung 'apps.simCache'*Feld 'rules'*vergleicht 'apps.simapp.cacheMode' (Typ 'value') mit 'ne' und Ja/Nein-Wert; erlaubt*" }
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
        @{ Op = 'gt'; Than = 1 }, @{ Op = 'le'; Than = '@workEndHour' }, @{ Op = 'eq'; Than = 0 }, @{ Op = 'ne'; Than = 1 }, @{ Op = 'eq'; Than = 'an' }, @{ Op = 'ne'; Than = 'aus' }
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
    It 'nimmt den Teil units mit der Einzahl einer Einheit an und liefert ihn auch ohne Angabe' {
        # units ist freiwillig: Mehrzahl -> Einzahl, nur fuer Einheiten der Werte
        $c = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { $c.units = [ordered]@{ Tage = 'Tag'; Stunden = 'Stunde'; Minuten = 'Minute' } })
        $c.units.Tage | Should -Be 'Tag'; $c.units.Stunden | Should -Be 'Stunde'; @($c.units.PSObject.Properties.Name) | Should -Be @('Tage', 'Stunden', 'Minuten')
        $none = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue)
        ($null -ne $none.units) | Should -BeTrue; @($none.units.PSObject.Properties).Count | Should -Be 0
        $WorkerPerfHealthOptionalParts | Should -Be @('units', 'legends'); $WorkerPerfHealthCatalogueParts | Should -Not -Contain 'units'
    }
    It 'lehnt einen fehlerhaften Teil units ab' -TestCases @(
        @{ Change = { $c.units = @{ Wochen = 'Woche' } }; Msg = "Katalog '*': Teil 'units' nennt die unbekannte Einheit 'Wochen' (Einheiten der Werte: MB, s, Tage, Minuten, %, GB, Stunden)." }
        @{ Change = { $c.units = @{ tage = 'Tag' } }; Msg = "*Teil 'units' nennt die unbekannte Einheit 'tage'*" }                            # Namen gelten nur in genau dieser Schreibweise
        @{ Change = { $c.units = @{ Prozessoren = 'Prozessor' } }; Msg = "*Teil 'units' nennt die unbekannte Einheit 'Prozessoren'*" }        # die Einheit einer Schwelle, nicht eines Werts
        @{ Change = { $c.units = @{ Tage = '' } }; Msg = "Katalog '*': Teil 'units' nennt fuer die Einheit 'Tage' keinen Text." }
        @{ Change = { $c.units = @{ Tage = 1 } }; Msg = "*Teil 'units' nennt fuer die Einheit 'Tage' keinen Text*" }
        @{ Change = { $c.units = @('Tag') }; Msg = "Katalog '*': Teil 'units' ist kein Objekt." }
        @{ Change = { $c.units = 'Tag' }; Msg = "*Teil 'units' ist kein Objekt*" }
        @{ Change = { $c.unit = @{ Tage = 'Tag' } }; Msg = "*Teil 'unit' ist unbekannt*" }
    ) { { Read-WorkerPerfHealthCatalogue (New-HealthCatalogue $Change) } | Should -Throw $Msg }
    It 'nimmt den Teil legends mit der Legende eines Werts an und liefert ihn auch ohne Angabe' {            # Entscheidung ZB-R49
        # legends ist freiwillig: Kennung eines Werts oder Fakts -> kurze Legende seiner Kennwoerter; die Bezeichnung in values bleibt ein schlichter Name
        $c = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { $c.legends = [ordered]@{ 'print.spooler' = 'Running = läuft, Stopped = beendet'; 'print.queuesPerSession' = 'je Sitzung' } })
        $c.legends.'print.spooler' | Should -Be 'Running = läuft, Stopped = beendet'
        @($c.legends.PSObject.Properties.Name) | Should -Be @('print.spooler', 'print.queuesPerSession')        # ein gelesener Wert und ein abgeleiteter Fakt
        $none = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue)
        ($null -ne $none.legends) | Should -BeTrue; @($none.legends.PSObject.Properties).Count | Should -Be 0
        $WorkerPerfHealthOptionalParts | Should -Be @('units', 'legends'); $WorkerPerfHealthCatalogueParts | Should -Not -Contain 'legends'
        # der Fakt einer Anwendung ist bekannt, wenn die Anwendungsliste ihn kennt
        (Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { $c.legends = @{ 'apps.simapp.cacheMode' = '2 = aus' } }) $TestApps).legends.'apps.simapp.cacheMode' | Should -Be '2 = aus'
    }
    It 'lehnt einen fehlerhaften Teil legends ab' -TestCases @(
        @{ Change = { $c.legends = @{ 'print.nichtda' = 'x' } }; Msg = "Katalog '*': Teil 'legends' nennt die unbekannte Kennung 'print.nichtda' (erlaubt sind die Kennungen der Werte und Fakten)." }
        @{ Change = { $c.legends = @{ 'Print.Spooler' = 'x' } }; Msg = "*Teil 'legends' nennt die unbekannte Kennung 'Print.Spooler'*" }               # Kennungen gelten nur in genau dieser Schreibweise
        @{ Change = { $c.legends = @{ 'apps.simapp.cacheMode' = 'x' } }; Msg = "*Teil 'legends' nennt die unbekannte Kennung 'apps.simapp.cacheMode'*" }  # ohne Anwendungsliste kennt der Katalog den Fakt nicht
        @{ Change = { $c.legends = @{ 'diskFreeGB' = 'x' } }; Msg = "*Teil 'legends' nennt die unbekannte Kennung 'diskFreeGB'*" }                      # eine Schwelle ist kein Wert
        @{ Change = { $c.legends = @{ 'print.spooler' = '' } }; Msg = "Katalog '*': Teil 'legends' nennt fuer 'print.spooler' keinen Text." }
        @{ Change = { $c.legends = @{ 'print.spooler' = '  ' } }; Msg = "*Teil 'legends' nennt fuer 'print.spooler' keinen Text*" }
        @{ Change = { $c.legends = @{ 'print.spooler' = 1 } }; Msg = "*Teil 'legends' nennt fuer 'print.spooler' keinen Text*" }
        @{ Change = { $c.legends = @{ 'print.spooler' = @{ text = 'x' } } }; Msg = "*Teil 'legends' nennt fuer 'print.spooler' keinen Text*" }          # kein Feld unter einer Legende
        @{ Change = { $c.legends = @('x') }; Msg = "Katalog '*': Teil 'legends' ist kein Objekt." }
        @{ Change = { $c.legends = 'x' }; Msg = "*Teil 'legends' ist kein Objekt*" }
        @{ Change = { $c.legend = @{ 'print.spooler' = 'x' } }; Msg = "*Teil 'legend' ist unbekannt*" }
    ) { { Read-WorkerPerfHealthCatalogue (New-HealthCatalogue $Change) } | Should -Throw $Msg }
}
Describe 'Fakten des Zustandsbilds' {
    It 'bildet die abgeleiteten Fakten aus den gelesenen Werten' {
        $f = Get-Facts @{ 'size.commitTotalMB' = 38000; 'size.commitLimitMB' = 98304; 'size.commitPeakMB' = 61000; 'size.memTotalMB' = 65536; 'size.cpuLogical' = 8
            'size.pagefiles' = @(@{ Path = 'C:\pagefile.sys'; AllocatedMB = 32768; PeakUsageMB = 5200; Temporary = $false }, @{ Path = 'D:\temp.sys'; AllocatedMB = 1; PeakUsageMB = 1; Temporary = $true })
            'operation.lastBoot' = $ReadMs - 3 * 86400000; 'operation.lastUpdate' = $ReadMs - 20 * 86400000
            'operation.volumes' = @(@{ Drive = 'C:'; SizeGB = 100; FreeGB = 38; System = $true; PageFile = $true }, @{ Drive = 'D:'; SizeGB = 200; FreeGB = 5; System = $false; PageFile = $false })
            'sessions.list' = @(@{ Id = 0; State = 'Disconnected'; User = ''; DisconnectTime = 0 }) + @(2..25 | ForEach-Object { @{ Id = $_; State = 'Active'; User = "user$_"; DisconnectTime = 0 } }) +
                @(@{ Id = 30; State = 'Disconnected'; User = 'gast'; DisconnectTime = $ReadMs - 26 * 3600000 })
            'sessions.limits' = @(@{ Terminal = 'RDP-Tcp'; DisconnectedLimitMin = 0; IdleLimitMin = 0 }, @{ Terminal = 'ICA-CGP'; DisconnectedLimitMin = 240; IdleLimitMin = 180 })
            'size.model' = 'VMware, Inc. VMware7,1'; 'size.vmtoolsVersion' = '11.3.5'; 'size.balloonDriver' = 'Stopped'
            'size.netAdapters' = @(@{ Name = 'vmxnet3 Ethernet Adapter'; Enabled = $true }, @{ Name = 'Intel(R) 82574L Gigabit Network Connection'; Enabled = $true }, @{ Name = 'Alt'; Enabled = $false })
            'size.storageControllers' = @(@{ Name = 'LSI Adapter, SAS 3000 series'; Driver = 'LSI_SAS' }, @{ Name = 'VMware PVSCSI Controller'; Driver = 'pvscsi' })
            'network.rss' = @(@{ Description = 'vmxnet3 Ethernet Adapter'; Enabled = $false }, @{ Description = 'Intel(R) 82574L'; Enabled = $false })
            'vda.wemService' = 'Running'; 'print.citrixPrintService' = 'Running'
            'vda.wemServices' = @(@{ Name = 'Citrix WEM Agent Host Service'; State = 'Running'; StartMode = 'Auto' }, @{ Name = 'Citrix WEM User Logon Service'; State = 'Stopped'; StartMode = 'Auto' })
            'sessions.localProfiles' = @(@{ Path = 'C:\Users\a'; Loaded = $true; Special = $false; Temporary = $false }, @{ Path = 'C:\Users\b'; Loaded = $false; Special = $false; Temporary = $true })
            'vda.services' = @(@{ Name = 'BrokerAgent'; State = 'Running'; StartMode = 'Auto' }, @{ Name = 'SimDienst'; State = 'Stopped'; StartMode = 'Auto' }, @{ Name = 'SimHand'; State = 'Stopped'; StartMode = 'Manual' })
            'vda.controllers' = @(@{ Entry = 'ddc01.sim.local'; Kind = 'fqdn'; From = 'policy' }, @{ Entry = 'ddc02'; Kind = 'short'; From = 'policy' })
            'profile.containers' = @(@{ Owner = 'user9'; UsedPct = 96 }, @{ Owner = 'user9'; UsedPct = 40 }, @{ Owner = ''; UsedPct = 10 })
            'print.queueCount' = 50; 'print.mappingClientVersion' = '6.2.1'
            'network.dnsServers' = @(@{ Interface = 4; Address = '10.20.0.10' }, @{ Interface = 4; Address = '8.8.8.8' }, @{ Interface = 7; Address = 'fd00:20::10' })
            'network.smbConnections' = @(@{ Share = '\\fs01\daten'; Dialect = '3.1.1'; Connections = 25 }, @{ Share = '\\alt01\archiv'; Dialect = '2.1'; Connections = 3 }); 'network.timeType' = 'NTP' }
        $val = { param($id) $f[$id].State | Should -Be 'read' -Because $id; $f[$id].Value }
        & $val 'size.commitPeakPct' | Should -Be 62.1; & $val 'size.commitNowPct' | Should -Be 38.7; & $val 'size.pagefileCount' | Should -Be 1
        & $val 'sessions.userCount' | Should -Be 25; & $val 'size.memPerSessionMB' | Should -Be 2621.4; & $val 'size.sessionsPerCpu' | Should -Be 3.1
        & $val 'operation.uptimeDays' | Should -Be 3; & $val 'operation.updateAgeDays' | Should -Be 20; & $val 'operation.minFreeGB' | Should -Be 38
        & $val 'sessions.disconnectedCount' | Should -Be 1; & $val 'sessions.disconnectedOldestHours' | Should -Be 26; & $val 'sessions.disconnectLimitMin' | Should -Be 240
        & $val 'sessions.unloadedProfiles' | Should -Be 1; & $val 'sessions.tempProfiles' | Should -Be 1
        & $val 'vda.stoppedAutoServices' | Should -Be 1; & $val 'vda.controllerCount' | Should -Be 2; & $val 'vda.controllersNotFqdn' | Should -Be 1
        & $val 'profile.containerCount' | Should -Be 3; & $val 'profile.containerMaxUsedPct' | Should -Be 96; & $val 'profile.maxContainersPerUser' | Should -Be 2
        & $val 'print.queuesPerSession' | Should -Be 2; & $val 'print.mappingClientRelease' | Should -Be 602
        & $val 'network.dnsServersMin' | Should -Be 1; & $val 'network.dnsPublic' | Should -Be 1; & $val 'network.smbOldDialects' | Should -Be 3; & $val 'network.timeFromDomain' | Should -BeFalse
        & $val 'size.commitOfRamPct' | Should -Be 58; & $val 'size.vmware' | Should -BeTrue; & $val 'size.vmtoolsMajor' | Should -Be 11; & $val 'size.balloonRunning' | Should -BeFalse
        & $val 'size.otherNetAdapters' | Should -Be 1; & $val 'size.lsiControllers' | Should -Be 1; & $val 'network.rssOff' | Should -Be 1; & $val 'sessions.idleLimitMin' | Should -Be 180
        & $val 'vda.wemServicesNotReady' | Should -Be 2; & $val 'print.citrixMapping' | Should -BeTrue      # der Anmeldedienst steht, der dritte Dienst fehlt in der Liste
        $f['size.cpuLogical'].Value | Should -Be 8; @($f.Keys).Count | Should -Be 168                       # gelesene Werte sind selbst Fakten
    }
    It 'findet den Windows-Dienst des WEM-Agenten am Dienstnamen SENS' {   # ZB-R34
        $citrix = @(@{ Name = 'Citrix WEM Agent Host Service'; State = 'Running'; StartMode = 'Auto' }, @{ Name = 'Citrix WEM User Logon Service'; State = 'Running'; StartMode = 'Auto' })
        $count = { param($Third) (Get-Facts @{ 'vda.wemService' = 'Running'; 'vda.wemServices' = @($citrix + @($Third)) })['vda.wemServicesNotReady'].Value }
        & $count @{ Name = 'SENS'; State = 'Running'; StartMode = 'Auto' } | Should -Be 0
        & $count @{ Name = 'sens'; State = 'Running'; StartMode = 'Auto' } | Should -Be 0                # Namen ohne Ruecksicht auf Gross- und Kleinschreibung
        # eine alte Aufzeichnung mit dem englischen Anzeigenamen: kein Name der Gruppe, der Dienst gilt als fehlend
        & $count @{ Name = 'System Event Notification Service'; State = 'Running'; StartMode = 'Auto' } | Should -Be 1
        & $count @{ Name = 'SENS'; State = 'Stopped'; StartMode = 'Auto' } | Should -Be 1
    }
    It 'gibt den Zustand der Eingangswerte weiter und nennt nichts Zaehlbares nicht vorhanden' {
        $f = Get-Facts @{ 'size.commitLimitMB' = 98304; 'size.commitPeakMB' = (New-WorkerPerfHealthValue 'unreadable' 'rights'); 'profile.containers' = @(); 'sessions.list' = @(); 'size.memTotalMB' = 65536
            'sessions.limits' = @(@{ Terminal = 'RDP-Tcp'; DisconnectedLimitMin = 0 }); 'vda.version' = (New-WorkerPerfHealthValue 'absent' 'notInstalled') }
        $f['size.commitPeakPct'].State | Should -Be 'unreadable'; $f['size.commitPeakPct'].Reason | Should -Be 'rights'
        $f['profile.containerMaxUsedPct'].State | Should -Be 'absent'; $f['profile.containerMaxUsedPct'].Reason | Should -Be ''; $f['profile.containerCount'].Value | Should -Be 0
        $f['size.memPerSessionMB'].State | Should -Be 'absent'; $f['sessions.disconnectedOldestHours'].Value | Should -Be 0; $f['sessions.disconnectLimitMin'].State | Should -Be 'absent'
        $f['security.citrixExclusionsMissing'].State | Should -Be 'absent'; $f['security.citrixExclusionsMissing'].Reason | Should -Be 'notInstalled'
        { New-WorkerPerfHealthFact 'unreadable' 'skipped:Drucken' } | Should -Not -Throw; { New-WorkerPerfHealthFact 'unreadable' 'notRecorded' } | Should -Not -Throw
        { New-WorkerPerfHealthFact 'unreadable' 'skipped:Wetter' } | Should -Throw; { New-WorkerPerfHealthValue 'unreadable' 'notRecorded' } | Should -Throw     # health.json kennt diese Gruende nicht
        { New-WorkerPerfHealthFact 'absent' 'notInUse' } | Should -Not -Throw; { New-WorkerPerfHealthValue 'absent' 'notInUse' } | Should -Throw
    }
    It 'nennt nicht zutreffend, was auf diesem Worker nicht gilt' {   # Review Focus 3
        $na = { param($f, $id, $reason) $f[$id].State | Should -Be 'absent' -Because $id; $f[$id].Reason | Should -Be $reason -Because $id }
        $f = Get-Facts @{ 'size.model' = 'Microsoft Corporation Virtual Machine'; 'size.vmtoolsVersion' = (New-WorkerPerfHealthValue 'absent' 'notInstalled'); 'size.netAdapters' = @(@{ Name = 'Microsoft Hyper-V Network Adapter'; Enabled = $true })
            'network.rss' = @(@{ Description = 'Microsoft Hyper-V Network Adapter'; Enabled = $false }); 'vda.wemService' = (New-WorkerPerfHealthValue 'absent' 'notInstalled'); 'vda.version' = '2203'
            'print.citrixPrintService' = 'Stopped'; 'security.defenderExclusionProcesses' = @() }
        $f['size.vmware'].Value | Should -BeFalse                                                              # keine VMware-VM: die VMware-Pruefungen treffen nicht zu
        foreach ($id in 'size.vmtoolsMajor', 'size.balloonRunning', 'size.otherNetAdapters', 'size.lsiControllers', 'network.rssOff', 'vda.wemServicesNotReady', 'security.wemExclusionsMissing') { & $na $f $id 'notInstalled' }
        & $na $f 'print.citrixMapping' 'notInUse'                                                               # der Citrix-Druckdienst laeuft nicht
        & $na (Get-Facts @{ 'print.citrixPrintService' = (New-WorkerPerfHealthValue 'absent' 'notInstalled') }) 'print.citrixMapping' 'notInUse'
        & $na (Get-Facts @{ 'print.mappingClientVersion' = (New-WorkerPerfHealthValue 'absent' 'notInstalled') }) 'print.mappingClientRelease' 'notInstalled'      # kein Client des Zuordnungswerkzeugs
        (Get-Facts @{ 'print.mappingClientVersion' = '5.9.3' })['print.mappingClientRelease'].Value | Should -Be 509; (Get-Facts @{ 'print.mappingClientVersion' = '6.10' })['print.mappingClientRelease'].Value | Should -Be 610
        $x = (Get-Facts @{ 'print.mappingClientVersion' = 'unbekannt' })['print.mappingClientRelease']; $x.State | Should -Be 'unreadable'; $x.Reason | Should -Be 'error'
        (Get-Facts @{ 'print.citrixPrintService' = (New-WorkerPerfHealthValue 'unreadable' 'rights') })['print.citrixMapping'].State | Should -Be 'unreadable'
        # eine VMware-VM ohne Tools und ohne Ballon-Treiber: gelesen, 0 und nein
        $v = Get-Facts @{ 'size.model' = 'VMware, Inc. VMware7,1'; 'size.vmtoolsVersion' = (New-WorkerPerfHealthValue 'absent' 'notInstalled'); 'size.balloonDriver' = (New-WorkerPerfHealthValue 'absent' 'notInstalled') }
        $v['size.vmtoolsMajor'].State | Should -Be 'read'; $v['size.vmtoolsMajor'].Value | Should -Be 0; $v['size.balloonRunning'].Value | Should -BeFalse
        # WEM: der Ordner des Agenten ist ausgenommen, oder seine Prozesse fehlen in der Liste
        $w = @{ 'vda.wemService' = 'Running'; 'security.defenderExclusionProcesses' = @(@{ Path = 'C:\Program Files (x86)\Citrix\Workspace Environment Management Agent\VUEMUIAgent.exe' }) }
        (Get-Facts ($w + @{ 'security.defenderExclusionPaths' = @() }))['security.wemExclusionsMissing'].Value | Should -Be 2
        (Get-Facts ($w + @{ 'security.defenderExclusionPaths' = @(@{ Path = 'C:\Program Files (x86)\Citrix\Workspace Environment Management Agent' }) }))['security.wemExclusionsMissing'].Value | Should -Be 0
        (Get-Facts ($w + @{ 'security.defenderExclusionPaths' = (New-WorkerPerfHealthValue 'unreadable' 'rights') }))['security.wemExclusionsMissing'].State | Should -Be 'unreadable'
    }
    It 'bildet die Fakten der Anwendungen aus den Zeilen der Proben' {
        $cat = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue) $TestApps
        $row = { param($app, $id, $state, $reason, $value, $names) [ordered]@{ App = $app; Id = $id; Kind = 'registryValue'; Read = 'value'; State = $state; Reason = $reason; Value = $value; Names = $names } }
        $rows = @((& $row 'edge' 'installed' 'read' '' $true $null), (& $row 'edge' 'backgroundMode' 'read' '' 1 $null), (& $row 'edge' 'userDataDir' 'read' '' $null '\\fs01\edge$'),
            (& $row 'edge' 'sleepingTabs' 'absent' '' $null $null), (& $row 'simapp' 'installed' 'read' '' $false $null), (& $row 'simapp' 'cacheMode' 'absent' 'notInstalled' $null $null))
        $f = Get-WorkerPerfHealthFacts -Model (New-HealthModel @{ 'apps.probes' = $rows }) -Catalogue $cat -EventConfig $Cfg -Roles $Roles
        @($f.Keys).Count | Should -Be 210; @($f.Keys)[168] | Should -BeLike 'apps.*'
        $f['apps.edge.installed'].Value | Should -BeTrue; $f['apps.edge.backgroundMode'].Value | Should -Be 1; $f['apps.edge.userDataDir'].Value | Should -Be '\\fs01\edge$'
        $f['apps.edge.sleepingTabs'].State | Should -Be 'absent'; $f['apps.edge.sleepingTabs'].Reason | Should -Be ''
        $f['apps.simapp.installed'].Value | Should -BeFalse; $f['apps.simapp.cacheMode'].State | Should -Be 'absent'; $f['apps.simapp.cacheMode'].Reason | Should -Be 'notInstalled'
        $f['apps.edge.autoDiscard'].State | Should -Be 'unreadable'; $f['apps.edge.autoDiscard'].Reason | Should -Be 'notRecorded'      # die Aufzeichnung hat fuer diese Probe keine Zeile
        $f['apps.office.installed'].Reason | Should -Be 'notRecorded'
        $u = Get-WorkerPerfHealthFacts -Model (New-HealthModel @{ 'apps.probes' = (New-WorkerPerfHealthValue 'unreadable' 'timeout') }) -Catalogue $cat -EventConfig $Cfg -Roles $Roles
        $u['apps.edge.installed'].State | Should -Be 'unreadable'; $u['apps.edge.installed'].Reason | Should -Be 'timeout'
    }
    It 'zaehlt Treiber und Ereignisse aus der Aufzeichnung' {
        $drv = @(@{ Name = 'A'; Manufacturer = 'HP'; Type = 3; Isolation = 'none' }, @{ Name = 'B'; Manufacturer = 'Microsoft'; Type = 4; Isolation = 'shared' }, @{ Name = 'C'; Manufacturer = 'Alt'; Type = 2; Isolation = 'none' },
            @{ Name = 'D'; Manufacturer = 'Citrix Systems, Inc.'; Type = 3; Isolation = 'shared' })
        $ev = @((New-Ev 1 'crash' 'app' 'EXCEL.EXE'), (New-Ev 1.1 'crash' 'app' 'EXCEL.EXE'), (New-Ev 2 'crash' 'app' 'spoolsv.exe'), (New-Ev 3 'system' 'storage'), (New-Ev 9 'crash' 'app' 'x.exe'))
        $f = Get-Facts @{} @{ PrintDrivers = $drv; EventsBefore = $ev }
        $f['print.driverCount'].Value | Should -Be 4; $f['print.driversInSpooler'].Value | Should -Be 2; $f['print.driversV2'].Value | Should -Be 1
        $f['print.vendorDrivers'].Value | Should -Be 2; $f['print.citrixDrivers'].Value | Should -Be 1
        # gezaehlt wird ab CaptureStartMs minus EventLookbackDays: der Absturz von vor neun Tagen zaehlt nicht
        $f['events.crashDays'].Value | Should -Be 1; $f['events.storageCount'].Value | Should -Be 1; $f['events.fileserverDays'].Value | Should -Be 0; $f['events.lookbackDays'].Value | Should -Be 7
        $days = @($f['events.perDay'].Value); $days.Count | Should -Be 3; $days[2].Day | Should -Be '2026-01-14'; $days[2].Crash | Should -Be 2; $days[1].Print | Should -Be 1; $days[0].Storage | Should -Be 1
        (Get-WorkerPerfHealthEventCount -Model (New-HealthModel @{} @{ EventsBefore = $ev }) -EventConfig $Cfg -Kind 'print' -Days 7).Count | Should -Be 1
        (Get-WorkerPerfHealthEventCount -Model (New-HealthModel @{} @{ EventsBefore = $ev }) -EventConfig $Cfg -Kind 'system.storage' -Days 2).Count | Should -Be 0
        # die Ereignisse der ganzen Messung zaehlen mit (EventsAll, nicht der Ausschnitt Events); ohne Ereignisse zaehlt nur der Rueckblick
        $cap = @((New-Ev -0.01 'crash' 'app' 'spoolsv.exe'))
        $n = Get-WorkerPerfHealthEventCount -Model (New-HealthModel @{} @{ EventsAll = $cap; Events = @() }) -EventConfig $Cfg -Kind 'print' -Days 7; $n.Count | Should -Be 1; $n.Known | Should -BeTrue
        (Get-WorkerPerfHealthEventCount -Model (New-HealthModel @{} @{ EventsAll = $cap; Skip = [string[]]@('Ereignisse') }) -EventConfig $Cfg -Kind 'print' -Days 7).Count | Should -Be 0
    }
    It 'nennt den Grund, wenn Treiberliste oder Rueckblick nicht gelesen wurden' {   # Review Focus 5
        $s = Get-Facts @{} @{ Skip = [string[]]@('Rueckblick', 'Drucken'); Meta = @{ EventLookbackDays = 0; HealthOnly = $false; OffsetMinutes = 60; Computer = 'T1' } }
        $s['print.driversInSpooler'].State | Should -Be 'unreadable'; $s['print.driversInSpooler'].Reason | Should -Be 'skipped:Drucken'
        $s['events.crashDays'].State | Should -Be 'unreadable'; $s['events.crashDays'].Reason | Should -Be 'skipped:Rueckblick'; $s['events.lookbackDays'].Value | Should -Be 0
        $nr = Get-Facts @{} @{ Recorded = @{ EventsBefore = $false; PrintDrivers = $false } }                       # die Dateien fehlen in der Aufzeichnung
        $nr['events.crashDays'].Reason | Should -Be 'notRecorded'; $nr['events.perDay'].State | Should -Be 'unreadable'; $nr['print.driverCount'].Reason | Should -Be 'notRecorded'
        $bad = Get-Facts @{} @{ SourceErrors = @((New-SourceError 'eventsbefore.system'), (New-SourceError 'printdrivers')) }   # das Lesen ist gescheitert
        $bad['events.crashDays'].State | Should -Be 'unreadable'; $bad['events.crashDays'].Reason | Should -Be 'error'; $bad['print.driversInSpooler'].Reason | Should -Be 'error'
        $bad['events.lookbackDays'].Value | Should -Be 7
        $part = Get-Facts @{} @{ EventsBefore = @((New-Ev 1 'crash' 'app' 'EXCEL.EXE')); SourceErrors = @((New-SourceError 'eventsbefore.system')) }
        $part['events.crashDays'].State | Should -Be 'read'; $part['events.crashDays'].Value | Should -Be 1            # ein Protokoll scheiterte, die anderen wurden gelesen
        (Get-WorkerPerfHealthEventCount -Model (New-HealthModel @{} @{ Recorded = @{ EventsBefore = $false; PrintDrivers = $true } }) -EventConfig $Cfg -Kind 'print' -Days 7).Known | Should -BeFalse
        Get-WorkerPerfHealthMissingReason -Model (New-HealthModel) -What 'lookback' | Should -Be ''; Get-WorkerPerfHealthMissingReason -Model (New-HealthModel) -What 'drivers' | Should -Be ''
    }
    It 'bildet das Ereignisbild der Protokolle' {
        $log = { param($name, $mode, $full, $enabled, $oldestDays) @{ Log = $name; Present = $true; Enabled = $enabled; MaxSizeMB = 20; FileSizeMB = 20; Records = 1; Mode = $mode; Full = $full; Oldest = $ReadMs - [long]($oldestDays * 86400000) } }
        $f = Get-Facts @{ 'events.logs' = @((& $log 'Application' 'Circular' $false $true 3.5), (& $log 'System' 'Retain' $true $true 30), (& $log 'Microsoft-Windows-PrintService/Admin' 'Circular' $false $false 30)
                @{ Log = 'Microsoft-Windows-SMBClient/Connectivity'; Present = $false }) }
        $f['events.coverageGapDays'].Value | Should -Be 4; $f['events.retainLogs'].Value | Should -Be 1; $f['events.fullLogs'].Value | Should -Be 1; $f['events.disabledLogs'].Value | Should -Be 1
        $f['events.reachFrom'].Value | Should -Be ($ReadMs - [long](3.5 * 86400000))                         # ab hier reichen alle eingeschalteten Protokolle
        # reichen die Protokolle nur bis zum letzten Start? (das abgeschaltete und das fehlende Protokoll zaehlen nicht)
        $since = { param($bootDays, $oldestDays) (Get-Facts @{ 'operation.lastBoot' = $ReadMs - [long]($bootDays * 86400000)
                'events.logs' = @((& $log 'Application' 'Circular' $false $true $oldestDays), (& $log 'System' 'Circular' $false $true ($oldestDays - 0.1)), (& $log 'Microsoft-Windows-PrintService/Admin' 'Circular' $false $false 30)) })['events.sinceBootOnly'] }
        (& $since 2 1.9).Value | Should -BeTrue; (& $since 2 2.003).Value | Should -BeTrue                    # bis zehn Minuten vor dem Start zaehlt als "seit dem Start"
        (& $since 2 2.5).Value | Should -BeFalse; (& $since 2 30).Value | Should -BeFalse
        $f['events.sinceBootOnly'].State | Should -Be 'absent'                                                # ohne gelesenen letzten Start
        (Get-Facts @{ 'operation.lastBoot' = $ReadMs - 86400000; 'events.logs' = @(@{ Log = 'Application'; Present = $true; Enabled = $true; Oldest = 0 }) })['events.sinceBootOnly'].Value | Should -BeFalse   # kein Eintrag
    }
    It 'erkennt Schutzprodukte der Rollenliste an Diensten und Filtertreibern' {
        @(($Roles | Where-Object label -eq 'Microsoft Defender').filters) | Should -Be @('WdFilter'); @(($Roles | Where-Object label -eq 'AppLocker').filters).Count | Should -Be 0
        $f = Get-Facts @{ 'security.services' = @(@{ Name = 'WinDefend'; State = 'Running'; StartMode = 'Auto' }, @{ Name = 'CylanceSvc'; State = 'Running'; StartMode = 'Auto' }, @{ Name = 'AppIDSvc'; State = 'Stopped'; StartMode = 'Manual' })
            'security.filters' = @(@{ Name = 'WdFilter'; Altitude = '328010' }, @{ Name = 'CyProtectDrv64'; Altitude = '388510' }); 'security.mdeOnboarding' = 1; 'vda.version' = '2203'
            'security.defenderExclusionProcesses' = @(@{ Path = 'C:\Program Files\Citrix\User Profile Manager\UserProfileManager.exe' }) }
        $f['security.otherFilterProducts'].Value | Should -Be 1; $f['security.products'].Value | Should -Be 'Microsoft Defender, Arctic Wolf Aurora Endpoint Protection'
        $f['security.mdeOnboarded'].Value | Should -BeTrue; $f['security.citrixExclusionsMissing'].Value | Should -Be 2
        (Get-Facts @{})['security.mdeOnboarded'].Value | Should -BeFalse
    }
    It 'erkennt Aufgaben, Scans und Updates in der Arbeitszeit des Servers' {
        $t = { param($path, $on, $hours, $trig, $rep) @{ Path = $path; Enabled = $on; State = 'Ready'; NextRun = $(if ($null -eq $hours) { 0 } else { $ReadMs + [long]($hours * 3600000) }); LastRun = 0; Triggers = $trig; RepeatMinutes = $rep; Action = 'x.exe' } }
        $tasks = @((& $t '\A' $true 2 'daily' 0), (& $t '\B' $true 18 'daily' 0), (& $t '\C' $false 2 'daily' 0), (& $t '\D' $true 50 'weekly' 0), (& $t '\E' $true $null 'logon, idle' 0), (& $t '\F' $true 18 'time' 15))
        # A: Donnerstag 10:00; B: Freitag 02:00; C: abgeschaltet; D: Samstag 10:00; E: ohne naechsten Lauf, Anmeldung; F: Freitag 02:00, wiederholt sich alle 15 Minuten
        $f = Get-Facts @{ 'maintenance.tasks' = $tasks; 'maintenance.scanDay' = 0; 'maintenance.scanTime' = '12:30'; 'maintenance.updateOptions' = 4; 'maintenance.updateDay' = 7; 'maintenance.updateHour' = 10 }
        $f['maintenance.tasksInWorkHours'].Value | Should -Be 2; $f['maintenance.sessionTriggerTasks'].Value | Should -Be 1
        $f['maintenance.scanInWorkHours'].Value | Should -BeTrue; $f['maintenance.updateInWorkHours'].Value | Should -BeFalse           # Tag 7 ist Samstag
        (Get-Facts @{ 'maintenance.scanDay' = 8; 'maintenance.scanTime' = '12:30' })['maintenance.scanInWorkHours'].Value | Should -BeFalse
        (Get-Facts @{})['maintenance.updateInWorkHours'].State | Should -Be 'absent'                                                    # keine Richtlinie: nicht pruefbar (Task 14s)
    }
    It 'nennt ohne gelesenes Zustandsbild jeden gelesenen Wert nicht lesbar und folgt dem Modell des Servers' {
        foreach ($case in @(@('skipped', 'skipped:Zustand'), @('notRecorded', 'notRecorded'), @('unreadable', 'error'))) {
            $f = Get-Facts @{} @{ HealthState = $case[0]; Health = $null }
            $f['size.cpuLogical'].State | Should -Be 'unreadable'; $f['size.cpuLogical'].Reason | Should -Be $case[1]
            $f['size.commitPeakPct'].Reason | Should -Be $case[1]; $f['events.lookbackDays'].Value | Should -Be 7
        }
        Get-WorkerPerfHealthMissingReason -Model (New-HealthModel @{} @{ Meta = @{ OffsetMinutes = 60 } }) -What 'lookback' | Should -Be 'notRecorded'
        $u = Get-Facts @{ 'size.model' = (New-WorkerPerfHealthValue 'unreadable' 'timeout') }
        foreach ($id in 'size.vmware', 'size.vmtoolsMajor', 'size.balloonRunning', 'size.lsiControllers', 'network.rssOff') { $u[$id].State | Should -Be 'unreadable' -Because $id; $u[$id].Reason | Should -Be 'timeout' -Because $id }
    }
    It 'macht aus einem Wert, dessen Inhalt nicht zu seinem Typ passt, nur dessen Fakten nicht lesbar' {   # ZB-R27, Korrektur 1
        $err = { param($f, $id) $f[$id].State | Should -Be 'unreadable' -Because $id; $f[$id].Reason | Should -Be 'error' -Because $id }
        $good = @{ 'size.cpuLogical' = 8; 'size.commitTotalMB' = 38000; 'size.memTotalMB' = 65536; 'size.model' = 'VMware, Inc. VMware7,1'
            'vda.controllers' = @(@{ Entry = 'ddc01.sim.local'; Kind = 'fqdn'; From = 'policy' }); 'maintenance.scanTime' = '12:30' }
        # Zahlen, ein Ja/Nein-Wert und eine Zeit als Text, eine Zeit mit Bruchteil, eine Liste als Text: kein Abbruch, nur deren Fakten nicht lesbar
        $f = Get-RawFacts @{ 'security.mdeOnboarding' = (New-Raw 'x'); 'maintenance.updateOptions' = (New-Raw '4'); 'maintenance.scanDay' = (New-Raw 'Montag')
            'size.hypervisor' = (New-Raw 'ja'); 'operation.lastBoot' = (New-Raw 1.5); 'size.netAdapters' = (New-Raw 'vmxnet3') } $good
        foreach ($id in 'security.mdeOnboarding', 'security.mdeOnboarded', 'maintenance.updateOptions', 'maintenance.updateInWorkHours', 'maintenance.scanDay',
            'maintenance.scanInWorkHours', 'size.hypervisor', 'operation.lastBoot', 'operation.uptimeDays', 'size.netAdapters', 'size.otherNetAdapters') { & $err $f $id }
        $f['size.cpuLogical'].Value | Should -Be 8; $f['size.commitOfRamPct'].Value | Should -Be 58; $f['vda.controllerCount'].Value | Should -Be 1; $f['size.vmware'].Value | Should -BeTrue
        $f['size.lsiControllers'].State | Should -Be 'absent'
        # eine Liste aus Texten statt Eintraegen, ein Feld mit falschem Typ
        $l = Get-RawFacts @{ 'vda.controllers' = (New-Raw @('ddc01', 'ddc02')); 'size.pagefiles' = (New-Raw @(@{ Path = 'C:\pagefile.sys'; AllocatedMB = 1; PeakUsageMB = 1; Temporary = 'nein' })) } $good
        foreach ($id in 'vda.controllers', 'vda.controllerCount', 'vda.controllersNotFqdn', 'size.pagefiles', 'size.pagefileCount') { & $err $l $id }
        # ein Eintrag ohne ein Feld, das eine Regel liest: nur die Fakten, die das Feld lesen
        $p = Get-Facts ($good + @{ 'sessions.localProfiles' = @(@{ Path = 'C:\Users\a'; Loaded = $false; Special = $false }) })
        & $err $p 'sessions.tempProfiles'; $p['sessions.unloadedProfiles'].Value | Should -Be 1; $p['sessions.localProfiles'].State | Should -Be 'read'
        $q = Get-Facts ($good + @{ 'size.pagefiles' = @(@{ Path = 'C:\pagefile.sys'; AllocatedMB = 1; PeakUsageMB = 1 }) })      # die Regel scheitert, die Fakten danach entstehen
        & $err $q 'size.pagefileCount'; $q['size.commitOfRamPct'].Value | Should -Be 58; $q['size.vmware'].Value | Should -BeTrue; $q['size.lsiControllers'].State | Should -Be 'absent'
        # Zahlen kommen als Int32, Int64, Double oder Decimal
        foreach ($n in @([int]38000, [long]38000, [double]38000, [decimal]38000)) {
            $x = Get-RawFacts @{ 'size.commitTotalMB' = (New-Raw $n) } @{ 'size.memTotalMB' = 65536 }; $x['size.commitOfRamPct'].Value | Should -Be 58 -Because $n.GetType().Name }
        (Get-RawFacts @{ 'operation.lastBoot' = (New-Raw ([double]($ReadMs - 3 * 86400000))) })['operation.uptimeDays'].Value | Should -Be 3
        # ein Lesezeitpunkt, der keine Zahl ist: nur die Fakten, die ihn brauchen
        $m = New-HealthModel ($good + @{ 'operation.lastBoot' = $ReadMs - 86400000 }); $m.Health.ReadAtMs = 'gestern'
        $t = Get-WorkerPerfHealthFacts -Model $m -Catalogue $Cat -EventConfig $Cfg -Roles $Roles
        & $err $t 'operation.uptimeDays'; $t['size.commitOfRamPct'].Value | Should -Be 58
        # dasselbe nach ConvertTo-Json und ConvertFrom-Json
        $j = New-RawModel @{ 'security.mdeOnboarding' = (New-Raw 'x'); 'maintenance.scanDay' = (New-Raw 'Montag'); 'size.netAdapters' = (New-Raw 'vmxnet3') } $good
        $fj = Get-WorkerPerfHealthFacts -Model (ConvertTo-Json -InputObject $j -Depth 12 | ConvertFrom-Json) -Catalogue $Cat -EventConfig $Cfg -Roles $Roles
        foreach ($id in 'security.mdeOnboarded', 'maintenance.scanInWorkHours', 'size.otherNetAdapters') { & $err $fj $id }
        $fj['size.commitOfRamPct'].Value | Should -Be 58; $fj['vda.controllerCount'].Value | Should -Be 1
    }
    It 'zaehlt eine gelesene Liste ohne Inhalt nicht und prueft Zustand und Grund jedes gelesenen Werts' {   # Korrektur 2
        $err = { param($f, $id) $f[$id].State | Should -Be 'unreadable' -Because $id; $f[$id].Reason | Should -Be 'error' -Because $id }
        $f = Get-RawFacts @{ 'vda.controllers' = (New-Raw $null); 'profile.containers' = (New-Raw ([ordered]@{ Owner = 'user9'; UsedPct = 96 }))
            'size.cpuLogical' = (New-Raw 8 'bogus'); 'size.memTotalMB' = (New-Raw 65536 'read' 'vielleicht'); 'size.commitTotalMB' = (New-Raw 38000 'read' 'notRecorded') }
        foreach ($id in 'vda.controllers', 'vda.controllerCount', 'vda.controllersNotFqdn', 'size.cpuLogical', 'size.memTotalMB', 'size.commitTotalMB', 'size.commitOfRamPct') { & $err $f $id }
        ($f['profile.containers'].Value -is [object[]]) | Should -BeTrue; $f['profile.containerCount'].Value | Should -Be 1; $f['profile.containerMaxUsedPct'].Value | Should -Be 96
    }
    It 'nennt die Luecke und den Rueckblick seit dem Start nicht lesbar, wenn ein Protokoll keinen bekannten aeltesten Eintrag hat' {   # Korrektur 3
        $log = { param($name, $oldest) @{ Log = $name; Present = $true; Enabled = $true; MaxSizeMB = 20; FileSizeMB = 20; Records = 1; Mode = 'Circular'; Full = $false; Oldest = $oldest } }
        $f = Get-Facts @{ 'operation.lastBoot' = $ReadMs - 86400000; 'events.logs' = @((& $log 'Application' $null), (& $log 'System' ($ReadMs - 30 * 86400000))) }
        foreach ($id in 'events.coverageGapDays', 'events.sinceBootOnly') { $f[$id].State | Should -Be 'unreadable' -Because $id; $f[$id].Reason | Should -Be 'error' -Because $id }
        $f['events.retainLogs'].Value | Should -Be 0
        $z = Get-Facts @{ 'operation.lastBoot' = $ReadMs - 86400000; 'events.logs' = @((& $log 'Application' 0)) }          # Oldest 0: das Protokoll hat keinen Eintrag
        $z['events.coverageGapDays'].Value | Should -Be 0; $z['events.sinceBootOnly'].Value | Should -BeFalse
    }
    It 'nennt den Rueckblick ohne Beginn der Aufzeichnung nicht lesbar' {   # Korrektur 4
        $m = New-HealthModel @{} @{ EventsBefore = @((New-Ev 1 'crash' 'app' 'EXCEL.EXE')) }; $m.Remove('CaptureStartMs')
        $f = Get-WorkerPerfHealthFacts -Model $m -Catalogue $Cat -EventConfig $Cfg -Roles $Roles
        foreach ($id in 'events.crashDays', 'events.storageCount', 'events.fileserverDays', 'events.perDay') { $f[$id].State | Should -Be 'unreadable' -Because $id; $f[$id].Reason | Should -Be 'error' -Because $id }
        (Get-WorkerPerfHealthEventCount -Model $m -EventConfig $Cfg -Kind 'crash' -Days 7).Known | Should -BeFalse
        (Get-Facts @{} @{ EventsBefore = @((New-Ev 1 'crash' 'app' 'EXCEL.EXE')); CaptureStartMs = $null })['events.crashDays'].Reason | Should -Be 'error'
    }
    It 'rundet je Fakt, wie der Plan es sagt' {   # Korrektur 5
        $f = Get-Facts @{ 'operation.lastBoot' = $ReadMs - [long](19.6 * 86400000); 'operation.lastUpdate' = $ReadMs - [long](19.6 * 86400000)
            'sessions.list' = @(@{ Id = 3; State = 'Disconnected'; User = 'gast'; DisconnectTime = $ReadMs - [long](26.5 * 3600000) })
            'size.commitPeakMB' = 1; 'size.commitTotalMB' = 9; 'size.commitLimitMB' = 400 }
        $f['operation.uptimeDays'].Value | Should -Be 19.6                     # "in Tagen": eine Nachkommastelle
        $f['operation.updateAgeDays'].Value | Should -Be 19                    # "in ganzen Tagen": abgerundet
        $f['sessions.disconnectedOldestHours'].Value | Should -Be 26.5
        # 0,25 % und 2,25 % liegen genau auf der Mitte: der Plan rundet von null weg (AwayFromZero), nicht zur geraden Ziffer
        $f['size.commitPeakPct'].Value | Should -Be 0.3; $f['size.commitNowPct'].Value | Should -Be 2.3
    }
}
Describe 'Bewertung' {
    It 'stuft <Grade> ein bei <Free> GB frei' -TestCases @(
        @{ Free = 38; Grade = 'ok'; Finding = '38 GB frei.' }
        @{ Free = 8.5; Grade = 'check'; Finding = 'Nur 8,5 GB frei (Schwelle 10 GB).' }
        @{ Free = 1.5; Grade = 'act'; Finding = 'Nur 1,5 GB frei.' }
    ) { $c = Get-Check (Get-Vol $Free); $c.grade | Should -Be $Grade; $c.finding | Should -Be $Finding; $c.app | Should -Be ''; $c.why | Should -Be ''; $c.value | Should -Match '^Wert operation\.minFreeGB: ' }
    It 'nennt nicht pruefbar mit dem Grund' {   # Review Focus 1
        $c = Get-Check @{ 'operation.volumes' = (New-WorkerPerfHealthValue 'unreadable' 'rights') }
        $c.grade | Should -Be 'unknown'; $c.why | Should -Be 'Text reasonRights'; $c.finding | Should -Be 'Nicht prüfbar: Text reasonRights.'
        (Get-Check @{} @{ Skip = [string[]]@('Drucken') } 'print.driversInSpooler').why | Should -Be 'Drucken nicht erfasst'
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel @{} @{ Skip = [string[]]@('Drucken') }) -Catalogue $Cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        $o = $r.areas | Where-Object id -eq 'operation'; $o.status | Should -Be 'read'; $o.checks[0].grade | Should -Be 'unknown'; $o.checks[0].why | Should -Be 'Text reasonAbsent'
        $o.grade | Should -Be 'ok'; $o.counts.unknown | Should -Be 1                                                    # nicht pruefbar allein macht den Bereich nicht auffaellig
    }
    It 'nennt den Grund eines nicht gelesenen Bereichs mit dem Text des Katalogs' {   # Review Focus 1
        $m = New-HealthModel
        $m.Health.Areas['operation'] = Complete-WorkerPerfHealthArea 'operation' @{} 0 'budget' $true
        $m.Health.Areas['print'] = Complete-WorkerPerfHealthArea 'print' @{ 'print.queueCount' = (New-WorkerPerfHealthValue 'read' '' 2) } 3 'Zugriff verweigert'
        $r = Get-WorkerPerfHealthResult -Model $m -Catalogue $Cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        $o = $r.areas | Where-Object id -eq 'operation'; $o.status | Should -Be 'failed'; $o.statusText | Should -Be 'Text areaFailed Text areaReasonBudget'; $o.error | Should -Be ''
        $o.checks[0].grade | Should -Be 'unknown'; $o.checks[0].why | Should -Be 'Text reasonTimeout'; $o.grade | Should -Be 'ok'; $o.countsText | Should -Be '1 nicht prüfbar'
        $p = $r.areas | Where-Object id -eq 'print'; $p.status | Should -Be 'partial'; $p.statusText | Should -Be 'Text areaPartial'; $p.error | Should -Be 'Zugriff verweigert'
        ($r.areas | Where-Object id -eq 'size').statusText | Should -Be ''; ($r.areas | Where-Object id -eq 'size').countsText | Should -Be ''
    }
    It 'macht handeln nur mit harter Grenze oder mit Dauerzustand und Ereignis' {
        (Get-Check @{} @{ PrintDrivers = $HpNone } 'print.driversInSpooler').grade | Should -Be 'check'
        (Get-Check @{} @{ PrintDrivers = $HpNone; EventsBefore = @((New-Ev 2 'crash' 'app' 'spoolsv.exe')) } 'print.driversInSpooler').grade | Should -Be 'act'
        (Get-Check @{} @{ PrintDrivers = $HpNone; EventsBefore = @((New-Ev 2 'crash' 'app' 'EXCEL.EXE')) } 'print.driversInSpooler').grade | Should -Be 'check'      # ein anderes Ereignis zaehlt nicht
        (Get-Check @{} @{ PrintDrivers = $HpNone; EventsBefore = @((New-Ev 8 'crash' 'app' 'spoolsv.exe')) } 'print.driversInSpooler').grade | Should -Be 'check'    # aelter als sieben Tage
        (Get-Check @{} @{ PrintDrivers = $HpNone; EventsAll = @((New-Ev -0.01 'crash' 'app' 'spoolsv.exe')); Events = @() } 'print.driversInSpooler').grade | Should -Be 'act'   # Ereignis der Messung, auch ausserhalb von -From und -To
        (Get-Check @{} @{ PrintDrivers = @(); EventsBefore = @((New-Ev 2 'crash' 'app' 'spoolsv.exe')) } 'print.driversInSpooler').grade | Should -Be 'ok'           # Ereignis ohne Dauerzustand
    }
    It 'bleibt bei pruefen und sagt es, wenn die Ereignisse nicht gelesen wurden' {   # Review Focus 5
        $c = Get-Check @{} (@{ PrintDrivers = $HpNone } + $NoLookback) 'print.driversInSpooler'
        $c.grade | Should -Be 'check'; $c.note | Should -Be 'Text eventsUnchecked'
        (Get-Check @{} @{ PrintDrivers = $HpNone } 'print.driversInSpooler').note | Should -Be ''
        (Get-Check @{} (@{ PrintDrivers = @() } + $NoLookback) 'print.driversInSpooler').grade | Should -Be 'ok'
        # ein Schnelllauf ohne Rueckblick, und eine Aufzeichnung, in der die Datei des Rueckblicks fehlt: dieselbe Lage
        $ho = @{ PrintDrivers = $HpNone; Skip = [string[]]@('Rueckblick'); Meta = @{ EventLookbackDays = 0; HealthOnly = $true; OffsetMinutes = 60; Computer = 'T1' } }
        (Get-Check @{} $ho 'print.driversInSpooler').note | Should -Be 'Text eventsUnchecked'
        (Get-Check @{} @{ PrintDrivers = $HpNone; Recorded = @{ EventsBefore = $false; PrintDrivers = $true } } 'print.driversInSpooler').note | Should -Be 'Text eventsUnchecked'
    }
    It 'wertet nicht gesetzt als Wert und ein fehlendes Produkt als nicht zutreffend' {   # Review Focus 3
        $cat = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue {
            $c.checks[0].id = 'print.isolationOff'; $c.checks[0].area = 'print'; $c.checks[0].values = @('print.isolationExecution')
            $c.checks[0].rules = @{ check = @(@{ value = 'print.isolationExecution'; op = 'exists' }, @{ value = 'print.isolationExecution'; op = 'eq'; than = 0 }) }
            $c.checks[0].findings = @{ ok = 'Isolierung nicht abgeschaltet.'; check = 'Isolierung abgeschaltet.'; unknown = '{reason}' }
            $c.checks[1].id = 'security.signatureAge'; $c.checks[1].area = 'security'; $c.checks[1].values = @('security.defenderSignatureAgeDays'); $c.checks[1].kind = 'rule'; $c.checks[1].relates = @('system')
            $c.checks[1].rules = @{ check = @(@{ value = 'security.defenderSignatureAgeDays'; op = 'gt'; than = 2 }) }
            $c.checks[1].findings = @{ ok = 'Signaturen {security.defenderSignatureAgeDays} Tage alt.'; check = 'alt'; unknown = '{reason}' }
            $c.thresholds.Remove('diskFreeGB'); $c.thresholds.Remove('diskFreeHardGB') })                    # sonst nutzt keine Regel diese Schwellen
        (Get-Check @{} @{} 'print.isolationOff' $cat).grade | Should -Be 'ok'                                          # der Wert fehlt: keine Richtlinie
        (Get-Check @{ 'print.isolationExecution' = 0 } @{} 'print.isolationOff' $cat).grade | Should -Be 'check'
        (Get-Check @{ 'print.isolationExecution' = 1 } @{} 'print.isolationOff' $cat).grade | Should -Be 'ok'
        (Get-Check @{ 'print.isolationExecution' = (New-WorkerPerfHealthValue 'unreadable' 'error') } @{} 'print.isolationOff' $cat).grade | Should -Be 'unknown'
        $n = Get-Check @{ 'security.defenderSignatureAgeDays' = (New-WorkerPerfHealthValue 'absent' 'notInstalled') } @{} 'security.signatureAge' $cat
        $n.grade | Should -Be 'na'; $n.why | Should -Be 'Wert security.defenderSignatureAgeDays fehlt'; $n.finding | Should -Be 'Trifft nicht zu: Wert security.defenderSignatureAgeDays fehlt.'
        (Get-Check @{} @{} 'security.signatureAge' $cat).grade | Should -Be 'unknown'                                   # fehlt ohne Grund bei einem Vergleich: nicht pruefbar
        (Get-Check @{ 'security.defenderSignatureAgeDays' = 1 } @{} 'security.signatureAge' $cat).finding | Should -Be 'Signaturen 1 Tage alt.'
        # trifft nicht zu wird nicht gezaehlt und macht den Bereich nicht auffaellig
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel @{ 'security.defenderSignatureAgeDays' = (New-WorkerPerfHealthValue 'absent' 'notInstalled') }) -Catalogue $cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        $s = $r.areas | Where-Object id -eq 'security'; $s.grade | Should -Be 'ok'; $s.countsText | Should -Be ''; $s.checks[0].grade | Should -Be 'na'
        ($s.counts.act + $s.counts.check + $s.counts.unknown + $s.counts.ok) | Should -Be 0; $r.unknownCount | Should -Be 0
        ($r.raw | Where-Object id -eq 'security.defenderSignatureAgeDays').stateText | Should -Be 'Text stateNotApplicable'
    }
    It 'entscheidet Gleichheit auch fuer einen nicht gesetzten Wert und laesst Groessenvergleiche offen' {
        $f = Get-Facts @{ 'print.isolationExecution' = 0; 'security.defenderSignatureAgeDays' = (New-WorkerPerfHealthValue 'absent' 'notInstalled'); 'operation.pendingRename' = (New-WorkerPerfHealthValue 'unreadable' 'rights') }
        $t = { param($id, $op, $than) (Test-WorkerPerfHealthRule -Conditions @(@{ value = $id; op = $op; than = $than }) -Facts $f -Model (New-HealthModel) -EventConfig $Cfg -Catalogue $Cat).Result }
        # nicht gesetzt (absent ohne Grund): print.isolationOverride
        & $t 'print.isolationOverride' 'exists' $null | Should -Be 'false'; & $t 'print.isolationOverride' 'absent' $null | Should -Be 'true'
        & $t 'print.isolationOverride' 'eq' 0 | Should -Be 'false'; & $t 'print.isolationOverride' 'ne' 0 | Should -Be 'true'; & $t 'print.isolationOverride' 'in' @(0, 1) | Should -Be 'false'
        & $t 'print.isolationOverride' 'lt' 1 | Should -Be 'unknown'; & $t 'print.isolationOverride' 'ge' 1 | Should -Be 'unknown'
        # nicht installiert: trifft nicht zu, mit jedem Operator; nicht lesbar: unbekannt, mit jedem Operator
        foreach ($op in 'exists', 'absent', 'eq', 'ne', 'gt') { & $t 'security.defenderSignatureAgeDays' $op 1 | Should -Be 'na' -Because $op; & $t 'operation.pendingRename' $op 1 | Should -Be 'unknown' -Because $op }
        & $t 'print.isolationExecution' 'eq' 0 | Should -Be 'true'; & $t 'print.isolationExecution' 'ne' 0 | Should -Be 'false'; & $t 'print.isolationExecution' 'exists' $null | Should -Be 'true'
    }
    It 'stuft die Pruefungen einer Anwendung ein und zaehlt eine nicht installierte nicht' {   # Review Focus 3
        $cat = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue {
            $c.checks[0].id = 'apps.edgeBackgroundMode'; $c.checks[0].area = 'apps'; $c.checks[0].values = @('apps.edge.backgroundMode')
            $c.checks[0].rules = @{ check = @(@{ value = 'apps.edge.backgroundMode'; op = 'eq'; than = 1 }) }
            $c.checks[0].findings = @{ ok = 'Hintergrundmodus aus.'; check = 'Hintergrundmodus an ({apps.edge.backgroundMode}).'; unknown = 'Nicht prüfbar: {reason}.' }
            $c.checks[1].id = 'apps.simCache'; $c.checks[1].area = 'apps'; $c.checks[1].values = @('apps.simapp.cacheMode', 'apps.simapp.dataPath'); $c.checks[1].kind = 'rule'; $c.checks[1].relates = @('disk')
            $c.checks[1].rules = @{ check = @(@{ value = 'apps.simapp.cacheMode'; op = 'ne'; than = 2 }, @{ value = 'apps.simapp.dataPath'; op = 'exists' }) }
            $c.checks[1].findings = @{ ok = 'Cache in Ordnung.'; check = 'Cache-Betriebsart {apps.simapp.cacheMode}.'; unknown = 'Nicht prüfbar: {reason}.' }
            $c.thresholds.Remove('diskFreeGB'); $c.thresholds.Remove('diskFreeHardGB') }) $TestApps
        $row = { param($app, $id, $state, $reason, $value, $names) [ordered]@{ App = $app; Id = $id; Kind = 'registryValue'; Read = 'value'; State = $state; Reason = $reason; Value = $value; Names = $names } }
        $edge = @((& $row 'edge' 'installed' 'read' '' $true $null), (& $row 'edge' 'backgroundMode' 'read' '' 1 $null))
        $res = { param($sim) Get-WorkerPerfHealthResult -Model (New-HealthModel @{ 'apps.probes' = @($edge + $sim) }) -Catalogue $cat -EventConfig $Cfg -Roles $Roles -Texts $Texts }
        $get = { param($r, $id) ($r.areas | Where-Object id -eq 'apps').checks | Where-Object id -eq $id }
        # die vierte Anwendung ist nicht installiert
        $r = & $res @((& $row 'simapp' 'installed' 'read' '' $false $null), (& $row 'simapp' 'cacheMode' 'absent' 'notInstalled' $null $null), (& $row 'simapp' 'dataPath' 'absent' 'notInstalled' $null $null))
        $a = $r.areas | Where-Object id -eq 'apps'; @($a.checks.id) | Should -Be @('apps.edgeBackgroundMode', 'apps.simCache'); @($a.checks.grade) | Should -Be @('check', 'na')
        $a.checks[0].finding | Should -Be 'Hintergrundmodus an (1).'; $a.checks[0].app | Should -Be 'edge'; $a.checks[1].app | Should -Be 'simapp'
        $a.checks[1].why | Should -Be 'Sim-Fachanwendung ist nicht installiert'; $a.checks[1].finding | Should -Be 'Trifft nicht zu: Sim-Fachanwendung ist nicht installiert.'
        $a.grade | Should -Be 'check'; $a.countsText | Should -Be '1 zum Prüfen'; $a.counts.ok | Should -Be 0; $a.counts.unknown | Should -Be 0; $r.summary.check | Should -Be 1
        @($a.apps.key) | Should -Be @($TestApps | Where-Object { $_.installed } | ForEach-Object key); ($a.apps | Where-Object key -eq 'edge').state | Should -Be 'installed'; ($a.apps | Where-Object key -eq 'simapp').state | Should -Be 'notInstalled'
        ($a.apps | Where-Object key -eq 'simapp').text | Should -Be 'Text appNotInstalled'; ($a.apps | Where-Object key -eq 'office').state | Should -Be 'unknown'       # die Aufzeichnung hat keine Zeile fuer Office
        @(($r.areas | Where-Object id -eq 'size').apps).Count | Should -Be 0
        # dieselbe Anwendung installiert: bewertet, ohne dass der Code sie kennt; der Pfad steht nur in den Rohwerten
        $r = & $res @((& $row 'simapp' 'installed' 'read' '' $true $null), (& $row 'simapp' 'cacheMode' 'read' '' 1 $null), (& $row 'simapp' 'dataPath' 'read' '' $null '\\fs01\simapp$'))
        $s = & $get $r 'apps.simCache'; $s.grade | Should -Be 'check'; $s.finding | Should -Be 'Cache-Betriebsart 1.'
        $s.value | Should -Be 'Sim-Fachanwendung – Cache-Betriebsart: 1; Sim-Fachanwendung – Datenordner der Sim-Fachanwendung: Text valueSet'; ($s | ConvertTo-Json -Depth 6) | Should -Not -Match 'fs01'
        $raw = $r.raw | Where-Object id -eq 'apps.simapp.dataPath'; $raw.free | Should -Be '\\fs01\simapp$'; $raw.text | Should -Be ''; $raw.label | Should -Be 'Sim-Fachanwendung – Datenordner der Sim-Fachanwendung'; $raw.area | Should -Be 'apps'
        ($r.raw | Where-Object id -eq 'apps.simapp.installed').label | Should -Be 'Sim-Fachanwendung – Text appInstalledLabel'; @($r.raw).Count | Should -Be 210
        (& $get (& $res @((& $row 'simapp' 'installed' 'read' '' $true $null), (& $row 'simapp' 'cacheMode' 'read' '' 2 $null), (& $row 'simapp' 'dataPath' 'read' '' $null 'D:\x'))) 'apps.simCache').grade | Should -Be 'ok'
        (& $get (& $res @((& $row 'simapp' 'installed' 'read' '' $true $null), (& $row 'simapp' 'cacheMode' 'absent' '' $null $null), (& $row 'simapp' 'dataPath' 'read' '' $null 'D:\x'))) 'apps.simCache').grade | Should -Be 'check'   # nicht gesetzt ist ungleich 2
        # die Installation laesst sich nicht lesen: nicht pruefbar mit dem Grund
        $u = & $get (& $res @((& $row 'simapp' 'installed' 'unreadable' 'rights' $null $null), (& $row 'simapp' 'cacheMode' 'unreadable' 'rights' $null $null))) 'apps.simCache'
        $u.grade | Should -Be 'unknown'; $u.why | Should -Be 'Text reasonRights'
    }
    It 'bewertet eine Pruefung zur Zuordnung ueber Citrix-Richtlinien nur, wo Citrix zuordnen kann' {   # Review Focus 3
        $cat = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue {
            $c.checks[0].id = 'print.citrixQueues'; $c.checks[0].area = 'print'; $c.checks[0].values = @('print.citrixMapping', 'print.queuesPerSession')
            $c.checks[0].rules = @{ check = @(@{ value = 'print.citrixMapping'; op = 'eq'; than = $true }, @{ value = 'print.queuesPerSession'; op = 'gt'; than = 10 }) }
            $c.checks[0].findings = @{ ok = 'in Ordnung'; check = '{print.queuesPerSession} Warteschlangen je Sitzung'; unknown = '{reason}' }
            $c.thresholds.Remove('diskFreeGB'); $c.thresholds.Remove('diskFreeHardGB') })
        $v = @{ 'print.queueCount' = 50; 'sessions.list' = @(@{ Id = 2; State = 'Active'; User = 'a'; DisconnectTime = 0 }) }
        (Get-Check ($v + @{ 'print.citrixPrintService' = 'Running' }) @{} 'print.citrixQueues' $cat).grade | Should -Be 'check'
        $n = Get-Check ($v + @{ 'print.citrixPrintService' = 'Stopped' }) @{} 'print.citrixQueues' $cat
        $n.grade | Should -Be 'na'; $n.why | Should -Be 'Wert print.citrixMapping nicht in Gebrauch'
        (Get-Check ($v + @{ 'print.citrixPrintService' = (New-WorkerPerfHealthValue 'absent' 'notInstalled') }) @{} 'print.citrixQueues' $cat).grade | Should -Be 'na'
        (Get-Check ($v + @{ 'print.citrixPrintService' = (New-WorkerPerfHealthValue 'unreadable' 'rights') }) @{} 'print.citrixQueues' $cat).grade | Should -Be 'unknown'
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel ($v + @{ 'print.citrixPrintService' = 'Stopped' })) -Catalogue $cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        ($r.raw | Where-Object id -eq 'print.citrixMapping').stateText | Should -Be 'Text stateNotApplicable'; ($r.areas | Where-Object id -eq 'print').grade | Should -Be 'ok'
    }
    It 'sagt, ab wann die Protokolle reichen' {
        $cat = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { $c.copy.eventsReach = 'Die Protokolle reichen bis {from} zurück; letzter Start {boot}.' })
        $logs = @(@{ Log = 'Application'; Present = $true; Enabled = $true; Oldest = $ReadMs - 129600000 }, @{ Log = 'System'; Present = $true; Enabled = $true; Oldest = $ReadMs - 30 * 86400000 })
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel @{ 'events.logs' = $logs; 'operation.lastBoot' = $ReadMs - 2 * 86400000 }) -Catalogue $cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        $r.eventsReachText | Should -Be 'Die Protokolle reichen bis 13.01.2026 20:00 zurück; letzter Start 13.01.2026 08:00.'
        ($r.areas | Where-Object id -eq 'events').intro | Should -Be $r.eventsReachText; ($r.areas | Where-Object id -eq 'size').intro | Should -Be ''
        (Get-WorkerPerfHealthResult -Model (New-HealthModel) -Catalogue $cat -EventConfig $Cfg -Roles $Roles -Texts $Texts).eventsReachText | Should -Be 'Die Protokolle reichen bis – zurück; letzter Start –.'
    }
    It 'gibt jedem Bereich die Einstufung seiner auffaelligsten Pruefung und zaehlt die Bereiche' {
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel (Get-Vol 1.5) @{ PrintDrivers = $HpNone }) -Catalogue $Cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        @($r.areas.id) | Should -Be $WorkerPerfHealthAreas; @($r.areas.label)[0] | Should -Be 'Bereich size'
        ($r.areas | Where-Object id -eq 'operation').grade | Should -Be 'act'; ($r.areas | Where-Object id -eq 'print').grade | Should -Be 'check'
        ($r.areas | Where-Object id -eq 'operation').countsText | Should -Be '1 zum Handeln'; ($r.areas | Where-Object id -eq 'print').countsText | Should -Be '1 zum Prüfen'
        ($r.areas | Where-Object id -eq 'size').grade | Should -Be 'ok'; @(($r.areas | Where-Object id -eq 'size').checks).Count | Should -Be 0
        $r.summary.act | Should -Be 1; $r.summary.check | Should -Be 1; $r.summary.ok | Should -Be 9; $r.summary.text | Should -Be '1 Bereich zum Handeln, 1 zum Prüfen, 9 in Ordnung'
        $r.unknownCount | Should -Be 0; $r.state | Should -Be 'read'; $r.readAt | Should -Be $ReadMs; $r.offsetMin | Should -Be 60; $r.durationMs | Should -Be 10
        @($r.changed).Count | Should -Be 0; $r.catalogueVersion | Should -Be '2026-11-13'
        $c = ($r.areas | Where-Object id -eq 'print').checks[0]; $c.kind | Should -Be 'vendor'; $c.kindLabel | Should -Be 'Text kindVendor'; $c.source.url | Should -Be 'https://learn.microsoft.com/x'
        @($c.relates) | Should -Be @('print', 'pattern.printdriver'); $c.todo[0].where | Should -Be 'w'; ($r.areas | Where-Object id -eq 'print').notCovered | Should -Be 'Nicht abgedeckt in print'
        # was aus dem Katalog kommt, ist Woerterbuch oder Array, nie pscustomobject (der JSON-Schreiber des Berichts schriebe es als Text)
        foreach ($o in $c.source, $c.todo[0], $r.grades, $r.grades.act) { ($o -is [System.Collections.IDictionary]) | Should -BeTrue }
        $r.grades.act.word | Should -Be 'Handeln'; $r.grades.na.word | Should -Be 'Trifft nicht zu'; $r.environmentText | Should -Be 'Text environment'
    }
    It 'liefert ohne gelesenes Zustandsbild nur den Zustand' {   # Review Focus 2
        foreach ($s in 'notRecorded', 'skipped', 'unreadable') {
            $r = Get-WorkerPerfHealthResult -Model (New-HealthModel @{} @{ Health = $null; HealthState = $s }) -Catalogue $Cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
            $r.state | Should -Be $s; @($r.areas).Count | Should -Be 0; @($r.raw).Count | Should -Be 0; $r.Contains('summary') | Should -BeFalse
            $r.text | Should -Be @{ notRecorded = 'Text notRecorded'; skipped = ''; unreadable = 'Text unreadable' }[$s]
        }
        # das Lesen ist beim Start gescheitert: ebenfalls keine Datei, aber der Satz sagt es
        $failed = New-HealthModel @{} @{ Health = $null; HealthState = 'notRecorded'; SourceErrors = @((New-SourceError 'health')) }
        (Get-WorkerPerfHealthResult -Model $failed -Catalogue $Cat -EventConfig $Cfg -Roles $Roles -Texts $Texts).text | Should -Be 'Text notRecordedFailed'
    }
    It 'listet jeden Fakt als Rohwert und trennt freien Servertext' {
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel @{ 'size.memTotalMB' = 65536; 'operation.lastBoot' = $ReadMs - 2 * 86400000
            'maintenance.tasks' = @(@{ Path = '\Sim\Inventarlauf'; Enabled = $true; State = 'Ready'; NextRun = $ReadMs + 7200000; LastRun = 0; Triggers = 'daily'; RepeatMinutes = 0; Action = 'C:\Tools\inventar.exe' })
            'vda.controllers' = @(@{ Entry = 'ddc01.sim.local'; Kind = 'fqdn'; From = 'policy' }); 'security.defenderSharedSignatures' = '\\fs01\defender$' }) -Catalogue $Cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        $raw = { param($id) $r.raw | Where-Object id -eq $id }
        (& $raw 'size.memTotalMB').text | Should -Be '65536 MB'; (& $raw 'size.memTotalMB').label | Should -Be 'Wert size.memTotalMB'; (& $raw 'size.memTotalMB').area | Should -Be 'size'; (& $raw 'size.memTotalMB').derived | Should -BeFalse
        (& $raw 'operation.lastBoot').text | Should -Be '13.01.2026 08:00'; (& $raw 'operation.uptimeDays').text | Should -Be '2 Tage'; (& $raw 'operation.uptimeDays').derived | Should -BeTrue
        $t = (& $raw 'maintenance.tasks').items[0]; $t.free | Should -Be 'Path: \Sim\Inventarlauf; Action: C:\Tools\inventar.exe'
        $t.text | Should -Be 'Enabled: ja; State: Ready; NextRun: 15.01.2026 10:00; LastRun: –; Triggers: daily; RepeatMinutes: 0'
        (& $raw 'vda.controllers').items[0].text | Should -Be 'Entry: ddc01.sim.local; Kind: fqdn; From: policy'; (& $raw 'vda.controllers').items[0].free | Should -Be ''
        (& $raw 'security.defenderSharedSignatures').text | Should -Be '\\fs01\defender$'; (& $raw 'size.cpuLogical').state | Should -Be 'absent'; (& $raw 'size.cpuLogical').text | Should -Be ''
        (& $raw 'size.cpuLogical').stateText | Should -Be 'Text stateAbsent'; (& $raw 'size.memTotalMB').stateText | Should -Be 'Text stateRead'
        @($r.raw).Count | Should -Be 168
    }
    It 'macht eine Pruefung, deren Bewertung scheitert, nicht pruefbar und bewertet die anderen' {   # ZB-R27, Zusatz b
        $cat = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue)
        $cat.checks[0].rules.check[0].op = 'kaputt'                                                       # ein Fehler nach dem Laden
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel (Get-Vol 1.5) @{ PrintDrivers = $HpNone }) -Catalogue $cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        $o = ($r.areas | Where-Object id -eq 'operation').checks[0]
        $o.grade | Should -Be 'unknown'; $o.why | Should -Be 'Text reasonError'; $o.finding | Should -Be 'Nicht prüfbar: Text reasonError.'
        ($r.areas | Where-Object id -eq 'print').checks[0].grade | Should -Be 'check'; $r.unknownCount | Should -Be 1
    }
}
Describe 'Bewertung: Regeln im Einzelnen' {
    BeforeAll {
        # die Zuordnung ueber Citrix-Richtlinien (M3) als Pruefung des Tests; die Warteschlangen je Sitzung als zweite Bedingung
        $script:CitrixCat = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue {
            $c.checks[0].id = 'print.citrixQueues'; $c.checks[0].area = 'print'; $c.checks[0].values = @('print.citrixMapping', 'print.queuesPerSession')
            $c.checks[0].rules = @{ check = @(@{ value = 'print.citrixMapping'; op = 'eq'; than = $true }, @{ value = 'print.queuesPerSession'; op = 'gt'; than = 10 }) }
            $c.checks[0].findings = @{ ok = 'in Ordnung'; check = '{print.queuesPerSession} Warteschlangen je Sitzung'; unknown = '{reason}' }
            $c.thresholds.Remove('diskFreeGB'); $c.thresholds.Remove('diskFreeHardGB') })
        $script:OneSession = @{ 'sessions.list' = @(@{ Id = 2; State = 'Active'; User = 'a'; DisconnectTime = 0 }) }
        function Test-Rule($Facts, [object[]]$Conditions) { (Test-WorkerPerfHealthRule -Conditions $Conditions -Facts $Facts -Model (New-HealthModel) -EventConfig $Cfg -Catalogue $Cat).Result }
    }
    It 'laesst eine nicht zutreffende Bedingung vor einer falschen entscheiden' {   # ZB-R30
        # die Zuordnung ist nicht in Gebrauch, die Warteschlangen liegen unter der Grenze: trifft nicht zu, nicht in Ordnung
        $v = $OneSession + @{ 'print.queueCount' = 5; 'print.citrixPrintService' = 'Stopped' }
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel $v) -Catalogue $CitrixCat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        $p = $r.areas | Where-Object id -eq 'print'; $n = $p.checks | Where-Object id -eq 'print.citrixQueues'
        $n.grade | Should -Be 'na'; $n.why | Should -Be 'Wert print.citrixMapping nicht in Gebrauch'; $n.finding | Should -Be 'Trifft nicht zu: Wert print.citrixMapping nicht in Gebrauch.'
        # gezaehlt wird nur die zweite Pruefung des Bereichs (Treiber im Spooler, in Ordnung)
        $p.counts.ok | Should -Be 1; ($p.counts.act + $p.counts.check + $p.counts.unknown) | Should -Be 0; $p.countsText | Should -Be ''; $p.grade | Should -Be 'ok'; $r.unknownCount | Should -Be 0
        @($p.checks.id) | Should -Be @('print.driversInSpooler', 'print.citrixQueues')                                  # na steht zuletzt
        # die Zuordnung ist moeglich: dieselben Warteschlangen sind in Ordnung
        (Get-Check ($OneSession + @{ 'print.queueCount' = 5; 'print.citrixPrintService' = 'Running' }) @{} 'print.citrixQueues' $CitrixCat).grade | Should -Be 'ok'
        # ein Produkt, das nicht installiert ist, mit einer zweiten Bedingung, die falsch ist: trifft nicht zu
        $f = Get-Facts @{ 'security.defenderSignatureAgeDays' = (New-WorkerPerfHealthValue 'absent' 'notInstalled'); 'size.cpuLogical' = 4 }
        Test-Rule $f @(@{ value = 'size.cpuLogical'; op = 'gt'; than = 8 }, @{ value = 'security.defenderSignatureAgeDays'; op = 'gt'; than = 2 }) | Should -Be 'na'
        $x = Test-WorkerPerfHealthRule -Conditions @(@{ value = 'size.cpuLogical'; op = 'gt'; than = 8 }, @{ value = 'security.defenderSignatureAgeDays'; op = 'gt'; than = 2 }) -Facts $f -Model (New-HealthModel) -EventConfig $Cfg -Catalogue $Cat
        $x.Reason | Should -Be 'notInstalled'; $x.Fact | Should -Be 'security.defenderSignatureAgeDays'
        # eine falsche und eine unbekannte Bedingung: falsch, die Pruefung bleibt in Ordnung
        $u = Get-Facts @{ 'size.cpuLogical' = 4; 'operation.pendingRename' = (New-WorkerPerfHealthValue 'unreadable' 'rights') }
        Test-Rule $u @(@{ value = 'size.cpuLogical'; op = 'gt'; than = 8 }, @{ value = 'operation.pendingRename'; op = 'eq'; than = $true }) | Should -Be 'false'
        $q = Get-Check ($OneSession + @{ 'print.queueCount' = 5; 'print.citrixPrintService' = (New-WorkerPerfHealthValue 'unreadable' 'rights') }) @{} 'print.citrixQueues' $CitrixCat
        $q.grade | Should -Be 'ok'
    }
    It 'entscheidet einen Wert genau auf der Grenze nach dem Operator' {
        $f = Get-Facts @{ 'size.cpuLogical' = 4 }
        Test-Rule $f @(@{ value = 'size.cpuLogical'; op = 'lt'; than = 4 }) | Should -Be 'false'
        Test-Rule $f @(@{ value = 'size.cpuLogical'; op = 'le'; than = 4 }) | Should -Be 'true'
        Test-Rule $f @(@{ value = 'size.cpuLogical'; op = 'gt'; than = 4 }) | Should -Be 'false'
        Test-Rule $f @(@{ value = 'size.cpuLogical'; op = 'ge'; than = 4 }) | Should -Be 'true'
        # dieselben Grenzen ueber eine Schwelle: genau 10 GB frei ist in Ordnung, genau 2 GB ist pruefen, nicht handeln
        (Get-Check (Get-Vol 10)).grade | Should -Be 'ok'; (Get-Check (Get-Vol 2)).grade | Should -Be 'check'
    }
    It 'vergleicht mit in, contains und Texten ohne Ruecksicht auf Gross- und Kleinschreibung' {
        $f = Get-Facts @{ 'size.cpuLogical' = 4; 'print.citrixPrintService' = 'Running' }
        Test-Rule $f @(@{ value = 'size.cpuLogical'; op = 'in'; than = @(2, 4) }) | Should -Be 'true'
        Test-Rule $f @(@{ value = 'size.cpuLogical'; op = 'in'; than = @(2, 8) }) | Should -Be 'false'
        Test-Rule $f @(@{ value = 'print.citrixPrintService'; op = 'in'; than = @('stopped', 'RUNNING') }) | Should -Be 'true'
        Test-Rule $f @(@{ value = 'print.citrixPrintService'; op = 'in'; than = @('stopped', 'paused') }) | Should -Be 'false'
        Test-Rule $f @(@{ value = 'print.citrixPrintService'; op = 'contains'; than = 'UNN' }) | Should -Be 'true'
        Test-Rule $f @(@{ value = 'print.citrixPrintService'; op = 'contains'; than = 'stop' }) | Should -Be 'false'
        Test-Rule $f @(@{ value = 'print.citrixPrintService'; op = 'eq'; than = 'RUNNING' }) | Should -Be 'true'
        Test-Rule $f @(@{ value = 'print.citrixPrintService'; op = 'ne'; than = 'running' }) | Should -Be 'false'
    }
    It 'vergleicht eine ganze Zahl mit einem Vergleichswert mit Nachkommastellen als Zahl' {
        $f = Get-Facts @{ 'size.memTotalMB' = [long]5 }
        $f['size.memTotalMB'].Value | Should -BeOfType [long]
        Test-Rule $f @(@{ value = 'size.memTotalMB'; op = 'eq'; than = [double]5 }) | Should -Be 'true'
        Test-Rule $f @(@{ value = 'size.memTotalMB'; op = 'gt'; than = 4.5 }) | Should -Be 'true'
        Test-Rule $f @(@{ value = 'size.memTotalMB'; op = 'lt'; than = 5.5 }) | Should -Be 'true'
        Test-Rule $f @(@{ value = 'size.memTotalMB'; op = 'ge'; than = 5.5 }) | Should -Be 'false'
    }
    It 'ordnet nicht pruefbar vor in Ordnung ein, in der Reihenfolge des Katalogs je Einstufung' {
        $cat = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue {
            $c.checks[0].id = 'print.queues'; $c.checks[0].area = 'print'; $c.checks[0].values = @('print.queueCount')
            $c.checks[0].rules = @{ check = @(@{ value = 'print.queueCount'; op = 'gt'; than = 100 }) }
            $c.checks[0].findings = @{ ok = 'in Ordnung'; check = 'viele'; unknown = '{reason}' }
            $c.thresholds.Remove('diskFreeGB'); $c.thresholds.Remove('diskFreeHardGB') })
        # die Treiberliste ist nicht aufgezeichnet: die zweite Pruefung ist nicht pruefbar und steht vor der ersten
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel @{ 'print.queueCount' = 5 } @{ Recorded = @{ EventsBefore = $true; PrintDrivers = $false } }) -Catalogue $cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        $p = $r.areas | Where-Object id -eq 'print'
        @($p.checks.id) | Should -Be @('print.driversInSpooler', 'print.queues'); @($p.checks.grade) | Should -Be @('unknown', 'ok')
        $p.checks[0].why | Should -Be 'Text reasonNotRecorded'; $p.checks[0].finding | Should -Be 'Text reasonNotRecorded'
    }
    It 'nimmt fuer die Zeiten den Offset des Zustandsbilds' {
        $m = New-HealthModel @{ 'operation.lastBoot' = $ReadMs - 2 * 86400000 }; $m.Health.OffsetMinutes = 120; $m.Meta.OffsetMinutes = 0
        $cat = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { $c.copy.eventsReach = 'bis {from}, Start {boot}' })
        $r = Get-WorkerPerfHealthResult -Model $m -Catalogue $cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        $r.offsetMin | Should -Be 120; ($r.raw | Where-Object id -eq 'operation.lastBoot').text | Should -Be '13.01.2026 09:00'; $r.eventsReachText | Should -Be 'bis –, Start 13.01.2026 09:00'
    }
    It 'liefert unter en-US und de-DE dieselben Texte' {
        $old = [Threading.Thread]::CurrentThread.CurrentCulture
        $out = foreach ($cul in 'en-US', 'de-DE') {
            [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo($cul)
            try {
                $r = Get-WorkerPerfHealthResult -Model (New-HealthModel ((Get-Vol 8.5) + @{ 'operation.lastBoot' = $ReadMs - 2 * 86400000; 'size.memTotalMB' = 1234.5 })) -Catalogue $Cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
                $c = ($r.areas | Where-Object id -eq 'operation').checks[0]
                $c.finding + '|' + $c.value + '|' + ($r.raw | Where-Object id -eq 'operation.lastBoot').text + '|' + ($r.raw | Where-Object id -eq 'size.memTotalMB').text
            }
            finally { [Threading.Thread]::CurrentThread.CurrentCulture = $old }
        }
        # 1234,5 bleibt 1234,5: eine Zahl steht so genau da, wie sie verglichen wird (frueher ab 10 auf ganze Zahlen gerundet: 1235)
        $out[0] | Should -Be 'Nur 8,5 GB frei (Schwelle 10 GB).|Wert operation.minFreeGB: 8,5 GB|13.01.2026 08:00|1234,5 MB'
        $out[1] | Should -Be $out[0]
    }
    It 'zeigt eine Zahl so genau, wie die Regel sie vergleicht' {
        # ein Fakt ist ganz oder auf eine Nachkommastelle gerundet, eine Schwelle steht, wie der Katalog sie schreibt: nichts wird weiter gerundet
        foreach ($case in @(@(30.4, '30,4'), @(30, '30'), @(100.4, '100,4'), @(100, '100'), @(24.3, '24,3'), @(9.96, '9,96'), @(1234.5, '1234,5'), @(24576, '24576'), @(0.3, '0,3'),
                @(0.125, '0,125'), @(8, '8'), @(0, '0'), @(-0.0000001, '0'), @(2.5000001, '2,5'), @(-1.5, '-1,5'))) {
            Format-WorkerPerfHealthNumber $case[0] | Should -BeExactly $case[1] -Because "$($case[0])"
        }
        # 30,4 Tage gegen die Schwelle 30: der Befund nennt 30,4 und widerspricht seiner Regel nicht; genau 30 ist nicht mehr als 30
        $cat = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue {
            $c.thresholds.uptimeDays = @{ value = 30; default = 30; unit = 'Tage'; label = 'Laufzeit' }; $c.thresholds.halfDays = @{ value = 0.5; default = 0.5; unit = 'Tage'; label = 'halber Tag' }
            $c.checks[0].id = 'operation.uptime'; $c.checks[0].values = @('operation.uptimeDays', 'size.commitOfRamPct')
            $c.checks[0].rules = @{ check = @(@{ value = 'operation.uptimeDays'; op = 'gt'; than = '@uptimeDays' }); act = @(@{ value = 'size.commitOfRamPct'; op = 'gt'; than = 100; hard = $true }) }
            $c.checks[0].findings = @{ ok = 'Laufzeit in Tagen: {operation.uptimeDays} (Schwelle {@uptimeDays}, halbe Schwelle {@halfDays}).'; check = 'Laufzeit in Tagen: {operation.uptimeDays}, mehr als {@uptimeDays}.'
                act = 'Zugesagt sind {size.commitOfRamPct} % des Arbeitsspeichers, mehr als 100 %.'; unknown = '{reason}' }
            $c.thresholds.Remove('diskFreeGB'); $c.thresholds.Remove('diskFreeHardGB') })
        $ram = @{ 'size.memTotalMB' = 10000; 'size.commitTotalMB' = 5000 }
        $x = Get-Check ($ram + @{ 'operation.lastBoot' = $ReadMs - [long](30.4 * 86400000) }) @{} 'operation.uptime' $cat
        $x.grade | Should -Be 'check'; $x.finding | Should -BeExactly 'Laufzeit in Tagen: 30,4, mehr als 30.'; $x.value | Should -Match 'Wert operation\.uptimeDays: 30,4 Tage'
        $x = Get-Check ($ram + @{ 'operation.lastBoot' = $ReadMs - 30 * 86400000L }) @{} 'operation.uptime' $cat
        $x.grade | Should -Be 'ok'; $x.finding | Should -BeExactly 'Laufzeit in Tagen: 30 (Schwelle 30, halbe Schwelle 0,5).'
        # 100,4 % gegen 100: der Befund nennt 100,4; genau 100 % ist nicht mehr als 100 %
        $x = Get-Check @{ 'size.memTotalMB' = 10000; 'size.commitTotalMB' = 10040; 'operation.lastBoot' = $ReadMs - 86400000L } @{} 'operation.uptime' $cat
        $x.grade | Should -Be 'act'; $x.finding | Should -BeExactly 'Zugesagt sind 100,4 % des Arbeitsspeichers, mehr als 100 %.'
        $x = Get-Check @{ 'size.memTotalMB' = 10000; 'size.commitTotalMB' = 10000; 'operation.lastBoot' = $ReadMs - 86400000L } @{} 'operation.uptime' $cat
        $x.grade | Should -Be 'ok'; $x.value | Should -Match 'Wert size\.commitOfRamPct: 100 %'
    }
    It 'nennt die Einheit eines Werts in der Einzahl, wenn er genau 1 ist' {
        # ($toUptime, nicht $change: so heisst der Parameter von New-HealthCatalogue)
        $toUptime = { $c.checks[0].id = 'operation.uptime'; $c.checks[0].values = @('operation.uptimeDays', 'sessions.disconnectedOldestHours', 'sessions.disconnectLimitMin', 'operation.minFreeGB')
            $c.checks[0].rules = @{ check = @(@{ value = 'operation.uptimeDays'; op = 'gt'; than = 30 }) }
            $c.checks[0].findings = @{ ok = 'Laufzeit in Tagen: {operation.uptimeDays}.'; check = 'lange'; unknown = '{reason}' }
            $c.thresholds.Remove('diskFreeGB'); $c.thresholds.Remove('diskFreeHardGB') }
        $with = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { . $toUptime; $c.units = [ordered]@{ Tage = 'Tag'; Stunden = 'Stunde'; Minuten = 'Minute' } })
        $one = (Get-Vol 1) + @{ 'operation.lastBoot' = $ReadMs - 86400000L; 'sessions.limits' = @(@{ Terminal = 'ICA-CGP'; IdleLimitMin = 0; DisconnectedLimitMin = 1; ActiveLimitMin = 0; BrokenAction = 0; FromPolicy = $true })
            'sessions.list' = @(@{ Id = 3; State = 'Disconnected'; User = 'gast'; DisconnectTime = $ReadMs - 3600000L }) }
        $x = Get-Check $one @{} 'operation.uptime' $with
        $x.value | Should -BeExactly 'Wert operation.uptimeDays: 1 Tag; Wert sessions.disconnectedOldestHours: 1 Stunde; Wert sessions.disconnectLimitMin: 1 Minute; Wert operation.minFreeGB: 1 GB'
        $x.finding | Should -BeExactly 'Laufzeit in Tagen: 1.'                                                            # im Befundsatz steht die Zahl ohne Einheit
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel $one) -Catalogue $with -EventConfig $Cfg -Roles $Roles -Texts $Texts
        ($r.raw | Where-Object id -eq 'operation.uptimeDays').text | Should -BeExactly '1 Tag'; ($r.raw | Where-Object id -eq 'sessions.disconnectLimitMin').text | Should -BeExactly '1 Minute'
        # jede andere Zahl bleibt in der Mehrzahl, auch 1,5, 0 und 2
        $more = (Get-Vol 1) + @{ 'operation.lastBoot' = $ReadMs - [long](1.5 * 86400000); 'sessions.list' = @(); 'sessions.limits' = @(@{ Terminal = 'ICA-CGP'; IdleLimitMin = 0; DisconnectedLimitMin = 2; ActiveLimitMin = 0; BrokenAction = 0; FromPolicy = $true }) }
        (Get-Check $more @{} 'operation.uptime' $with).value | Should -BeExactly 'Wert operation.uptimeDays: 1,5 Tage; Wert sessions.disconnectedOldestHours: 0 Stunden; Wert sessions.disconnectLimitMin: 2 Minuten; Wert operation.minFreeGB: 1 GB'
        # ohne den Teil units bleibt die Einheit, wie die Wertetabelle sie nennt
        $without = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue $toUptime)
        (Get-Check $one @{} 'operation.uptime' $without).value | Should -BeLike 'Wert operation.uptimeDays: 1 Tage; *'
    }
    It 'setzt eine Zeit und einen Ja/Nein-Wert in den Befund ein' {
        $cat = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue {
            $c.checks[0].id = 'security.realTime'; $c.checks[0].area = 'security'; $c.checks[0].values = @('security.defenderRealTime', 'operation.lastBoot')
            $c.checks[0].rules = @{ check = @(@{ value = 'security.defenderRealTime'; op = 'eq'; than = $false }) }
            $c.checks[0].findings = @{ ok = 'Echtzeitschutz {security.defenderRealTime}'; check = 'Echtzeitschutz {security.defenderRealTime} seit {operation.lastBoot}'; unknown = '{reason}' }
            $c.thresholds.Remove('diskFreeGB'); $c.thresholds.Remove('diskFreeHardGB') })
        $x = Get-Check @{ 'security.defenderRealTime' = $false; 'operation.lastBoot' = $ReadMs - 2 * 86400000 } @{} 'security.realTime' $cat
        $x.grade | Should -Be 'check'; $x.finding | Should -Be 'Echtzeitschutz nein seit 13.01.2026 08:00'
        (Get-Check @{ 'security.defenderRealTime' = $true } @{} 'security.realTime' $cat).finding | Should -Be 'Echtzeitschutz ja'
    }
    It 'zaehlt mehrere Bereiche zum Handeln mit areaMany' {
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel (Get-Vol 1.5) @{ PrintDrivers = $HpNone; EventsBefore = @((New-Ev 2 'crash' 'app' 'spoolsv.exe')) }) -Catalogue $Cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        $r.summary.act | Should -Be 2; $r.summary.text | Should -Be '2 Bereiche zum Handeln, 0 zum Prüfen, 9 in Ordnung'
        (Get-WorkerPerfHealthResult -Model (New-HealthModel (Get-Vol 38)) -Catalogue $Cat -EventConfig $Cfg -Roles $Roles -Texts $Texts).summary.text | Should -Be '0 Bereiche zum Handeln, 0 zum Prüfen, 11 in Ordnung'
    }
    It 'nennt die Gruende noReader, notRead und notInFile eines Bereichs' {
        $m = New-HealthModel
        $m.Health.Areas['operation'] = Complete-WorkerPerfHealthArea 'operation' @{} 0 'noReader' $true
        $m.Health.Areas['print'] = Complete-WorkerPerfHealthArea 'print' @{} 0 'notRead' $true
        $m.Health.Areas.Remove('vda')
        $r = Get-WorkerPerfHealthResult -Model $m -Catalogue $Cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        $o = $r.areas | Where-Object id -eq 'operation'; $o.status | Should -Be 'failed'; $o.statusText | Should -Be 'Text areaFailed Text areaReasonNoReader'; $o.error | Should -Be ''
        $p = $r.areas | Where-Object id -eq 'print'; $p.statusText | Should -Be 'Text areaFailed Text areaReasonNotRead'; $p.error | Should -Be ''
        $v = $r.areas | Where-Object id -eq 'vda'; $v.status | Should -Be 'failed'; $v.statusText | Should -Be 'Text areaFailed Text areaReasonNotInFile'; $v.error | Should -Be ''
    }
    It 'nennt die Anwendungen mit ihren Texten, auch eine ohne Zeile in der Aufzeichnung' {
        $cat = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue {
            $c.copy.appInstalled = '{app}: installiert'; $c.copy.appUnknown = '{app}: unbekannt ({reason})'; $c.copy.valueNotSet = 'nicht gesetzt'
            & $ToApp 'apps.simapp.dataPath' 'exists' $null }) $TestApps
        $row = { param($app, $id, $state, $value, $names) [ordered]@{ App = $app; Id = $id; Kind = 'registryValue'; Read = 'value'; State = $state; Reason = ''; Value = $value; Names = $names } }
        $probes = @((& $row 'edge' 'installed' 'read' $true $null), (& $row 'simapp' 'installed' 'read' $true $null), (& $row 'simapp' 'dataPath' 'absent' $null $null))
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel @{ 'apps.probes' = $probes }) -Catalogue $cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        $a = $r.areas | Where-Object id -eq 'apps'
        ($a.apps | Where-Object key -eq 'edge').text | Should -Be ('{0}: installiert' -f ($TestApps | Where-Object key -eq 'edge').label)
        ($a.apps | Where-Object key -eq 'office').state | Should -Be 'unknown'; ($a.apps | Where-Object key -eq 'office').text | Should -Be ('{0}: unbekannt (Text reasonNotRecorded)' -f ($TestApps | Where-Object key -eq 'office').label)
        # freier Text, nicht gesetzt: der Wert der Pruefung sagt es
        $s = $a.checks | Where-Object id -eq 'apps.simCache'; $s.grade | Should -Be 'ok'; $s.value | Should -Be 'Sim-Fachanwendung – Datenordner der Sim-Fachanwendung: nicht gesetzt'
    }
    It 'macht einen Fakt, der kein Faktdatensatz ist, nur fuer seine Pruefung, seinen Rohwert und seine Anwendung nicht pruefbar' {   # ZB-R27
        $cat = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue {
            $c.checks[1].id = 'apps.simCache'; $c.checks[1].area = 'apps'; $c.checks[1].values = @('apps.simapp.cacheMode'); $c.checks[1].relates = @('disk')
            $c.checks[1].rules = @{ check = @(@{ value = 'apps.simapp.cacheMode'; op = 'eq'; than = 2 }) }
            $c.checks[1].findings = @{ ok = 'in Ordnung'; check = 'auffaellig'; unknown = 'Nicht prüfbar: {reason}.' } }) $TestApps
        $script:Injected = Get-WorkerPerfHealthFacts -Model (New-HealthModel ((Get-Vol 1.5) + @{ 'apps.probes' = @() })) -Catalogue $cat -EventConfig $Cfg -Roles $Roles
        $script:Injected['operation.minFreeGB'] = 'kein Datensatz'; $script:Injected['apps.simapp.installed'] = 'kein Datensatz'
        Mock Get-WorkerPerfHealthFacts { $script:Injected }
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel) -Catalogue $cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        $d1 = ($r.areas | Where-Object id -eq 'operation').checks[0]; $d1.grade | Should -Be 'unknown'; $d1.why | Should -Be 'Text reasonError'; $d1.finding | Should -Be 'Nicht prüfbar: Text reasonError.'
        $s = ($r.areas | Where-Object id -eq 'apps').checks[0]; $s.id | Should -Be 'apps.simCache'; $s.grade | Should -Be 'unknown'; $s.why | Should -Be 'Text reasonError'; $s.app | Should -Be 'simapp'
        $sa = ($r.areas | Where-Object id -eq 'apps').apps | Where-Object key -eq 'simapp'; $sa.state | Should -Be 'unknown'
        ($r.areas | Where-Object id -eq 'apps').apps | Where-Object key -eq 'edge' | ForEach-Object state | Should -Be 'unknown'   # keine Zeile: nicht aufgezeichnet
        foreach ($id in 'operation.minFreeGB', 'apps.simapp.installed') {
            $e = $r.raw | Where-Object id -eq $id; $e.state | Should -Be 'unreadable' -Because $id; $e.reason | Should -Be 'error' -Because $id; $e.stateText | Should -Be 'Text stateUnreadable' -Because $id; $e.text | Should -Be ''
        }
        @($r.raw).Count | Should -Be 210; @($r.areas).Count | Should -Be 11; ($r.raw | Where-Object id -eq 'operation.volumes').state | Should -Be 'read'
    }
    It 'zeigt einen Rohwert, dessen Formatierung scheitert, als nicht lesbar' {
        # eine Zeit ausserhalb dessen, was ein Datum fassen kann: der Rohwert und der Satz zur Reichweite der Protokolle scheitern nicht
        $script:Injected = Get-Facts @{ 'operation.lastBoot' = $ReadMs - 2 * 86400000 }
        $script:Injected['operation.lastBoot'] = New-WorkerPerfHealthFact 'read' '' ([double]1e18)
        Mock Get-WorkerPerfHealthFacts { $script:Injected }
        $cat = Read-WorkerPerfHealthCatalogue (New-HealthCatalogue { $c.copy.eventsReach = 'bis {from}, Start {boot}' })
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel) -Catalogue $cat -EventConfig $Cfg -Roles $Roles -Texts $Texts
        $e = $r.raw | Where-Object id -eq 'operation.lastBoot'
        $e.state | Should -Be 'unreadable'; $e.reason | Should -Be 'error'; $e.stateText | Should -Be 'Text stateUnreadable'; $e.text | Should -Be ''
        $r.eventsReachText | Should -Be 'bis –, Start –'
    }
}
Describe 'Katalog in src' {
    BeforeAll {
        $script:CatFile = Join-Path $PSScriptRoot '../src/health.de.json'; $script:Apps = @(Read-WorkerPerfHealthApps (Join-Path $PSScriptRoot '../src/apps.json'))
        $script:Real = Read-WorkerPerfHealthCatalogue $CatFile $Apps
        # nur der Abschnitt des Zustandsbilds im Nachweis: bis zur naechsten Ueberschrift derselben Ebene
        $script:Proof = [regex]::Match((Get-Content (Join-Path $PSScriptRoot '../docs/guidance/quellen.md') -Raw), '(?ms)^## Zustandsbild\s*$(.*?)(?=^## |\z)').Groups[1].Value
        # der Nachweis ist bei 120 Zeichen umbrochen: fuer woertliche Titel, Adressen und Zitate derselbe Text mit einem Leerzeichen statt jedes Umbruchs
        $script:ProofFlat = $Proof -replace '\s+', ' '
        # die Pruefungen des Plans je Bereich; Task 14b ergaenzt print bis maintenance, Task 14c apps.
        # size.workerCpuMax kommt aus den weiteren Praxisquellen (PXH-01, Entscheidungen ZB-R3, ZB-R8)
        $script:PlanChecks = [ordered]@{
            size = @('size.commitHeadroom', 'size.pagefilePresent', 'size.memoryPerSession', 'size.cpuPerSession', 'size.commitAboveRam', 'size.workerCpu', 'size.workerCpuMax', 'size.workerMemory',
                'size.vmTools', 'size.balloonDriver', 'size.netAdapterType', 'size.storageController')
            operation = @('operation.pendingRestart', 'operation.uptime', 'operation.updateAge', 'operation.powerPlan', 'operation.diskFree')
            sessions = @('sessions.disconnectLimit', 'sessions.idleLimit', 'sessions.disconnectedOld', 'sessions.unloadedProfiles', 'sessions.tempProfiles')
            vda = @('vda.services', 'vda.controllerCount', 'vda.controllerNotFqdn', 'vda.listOfSids', 'vda.wemServices', 'vda.wemCache', 'vda.wemGpTimeout')
            profile = @('profile.containerFull', 'profile.containersPerUser', 'profile.serviceStopped')
            # print.operationalLogOff kommt aus den weiteren Praxisquellen (PXH-02) und steht vor der Pruefung des Zuordnungswerkzeugs
            print = @('print.driversInSpooler', 'print.isolationOff', 'print.driverCount', 'print.kernelModeV2', 'print.spoolerStopped', 'print.queueCount', 'print.operationalLogOff', 'print.mappingClientSupported')
            security = @('security.twoScanners', 'security.passiveWithoutMde', 'security.signatureAge', 'security.citrixExclusions', 'security.wemExclusions', 'security.networkProtection')
            network = @('network.smb1', 'network.smbOldDialect', 'network.dnsCount', 'network.dnsPublic', 'network.timeSource', 'network.rss')
            events = @('events.crashes', 'events.storage', 'events.fileserver', 'events.sinceBoot', 'events.coverage', 'events.retainFull', 'events.logDisabled')
            maintenance = @('maintenance.tasksInWorkHours', 'maintenance.sessionTriggerTasks', 'maintenance.defenderScanInWorkHours', 'maintenance.defenderFullScan', 'maintenance.defenderRandomize',
                'maintenance.updateInstallInWorkHours', 'maintenance.updateServiceEnabled')
            # apps.teamsClassic kommt aus den weiteren Praxisquellen (PXH-03) und steht am Ende
            apps = @('apps.edgeAutoUpdate', 'apps.edgeUpdateCheckOff', 'apps.edgeWebView2Update', 'apps.edgeStartupBoost', 'apps.edgeBackgroundMode', 'apps.edgeSleepingTabs', 'apps.edgeAutoDiscard',
                'apps.edgeRoamingProfile', 'apps.edgeUserDataDir', 'apps.officeUpdateUi', 'apps.teamsAutoUpdate', 'apps.teamsFallback', 'apps.teamsWebView2', 'apps.teamsClassic') }
        # die Art jeder Pruefung des ganzen Plans; was in keiner der zwei Listen steht, ist eine Faustregel.
        # maintenance.defenderFullScan ist seit Task 14b eine Faustregel: die Seite von Microsoft, die der Plan nennt, spricht sich nicht gegen einen vollstaendigen Scan aus.
        # security.wemExclusions stuetzt sich seit der Korrekturrunde 1 von Task 14b auf den Artikel von Citrix (Entscheidung ZB-R48)
        # print.driversInSpooler ist seit Task 14c eine Faustregel mit der Seite von Microsoft als Beleg (Entscheidung ZB-R54), apps.teamsFallback ebenso
        # (kein Hersteller nennt einen Sollwert; Quellenpruefung TEAMS-R04)
        $script:Vendor = @('size.pagefilePresent', 'size.vmTools', 'size.balloonDriver', 'size.netAdapterType', 'size.storageController',
            'vda.controllerCount', 'vda.controllerNotFqdn', 'vda.listOfSids', 'vda.wemServices', 'vda.wemCache', 'vda.wemGpTimeout',
            'print.kernelModeV2', 'print.mappingClientSupported',
            'security.twoScanners', 'security.passiveWithoutMde', 'security.citrixExclusions', 'security.wemExclusions', 'network.smb1', 'network.dnsCount', 'network.rss',
            'maintenance.sessionTriggerTasks', 'maintenance.defenderRandomize',
            'apps.edgeAutoUpdate', 'apps.edgeUpdateCheckOff', 'apps.edgeWebView2Update', 'apps.edgeBackgroundMode', 'apps.edgeSleepingTabs', 'apps.edgeAutoDiscard', 'apps.edgeRoamingProfile',
            'apps.teamsAutoUpdate', 'apps.teamsWebView2')
        # mit den drei Pruefungen aus den weiteren Praxisquellen: size.workerCpuMax (Task 14a), print.operationalLogOff (14b), apps.teamsClassic (14c)
        $script:Practice = @('size.commitAboveRam', 'size.workerCpu', 'size.workerCpuMax', 'size.workerMemory', 'operation.uptime', 'operation.updateAge', 'operation.powerPlan', 'sessions.disconnectLimit', 'sessions.idleLimit',
            'print.operationalLogOff', 'security.networkProtection', 'events.sinceBoot', 'maintenance.updateServiceEnabled', 'apps.teamsClassic')
        $script:K3 = @('events.crashes', 'events.storage', 'events.fileserver', 'events.coverage', 'events.sinceBoot', 'sessions.unloadedProfiles', 'sessions.tempProfiles')
        # zwoelf Praxisquellen (Entscheidung ZB-R7): der Blog von Kasper Johansen ist nicht mehr erreichbar und wird nicht verwendet
        $script:PracticeSources = @('BIS-F', 'Carl Stalhood', 'GO-EUC', 'James Kindon', 'James Rankin', 'Thomas Kötzing', 'Manuel Winkel', 'Aaron Parker', 'Trentent Tye',
            'John Billekens', 'Guy Leech', 'Benny Tritsch')
        # die Pruefungen dieser Task mit einer zweiten Quelle aus den weiteren Praxisquellen (Entscheidung ZB-R31) und der Name, der in ihrem Text steht
        $script:SecondSources = [ordered]@{ 'size.pagefilePresent' = 'GO-EUC'; 'operation.pendingRestart' = 'Guy Leech'; 'operation.diskFree' = 'Thomas Kötzing'
            'sessions.disconnectLimit' = 'James Rankin'; 'sessions.idleLimit' = 'James Rankin'; 'sessions.tempProfiles' = 'Thomas Kötzing'; 'vda.wemCache' = 'Manuel Winkel'
            'profile.containerFull' = 'Aaron Parker'; 'profile.containersPerUser' = 'Aaron Parker'
            'print.driversInSpooler' = 'Thomas Kötzing'; 'print.isolationOff' = 'Thomas Kötzing'; 'print.driverCount' = 'Thomas Kötzing'; 'security.signatureAge' = 'John Billekens'
            'security.citrixExclusions' = 'James Rankin'; 'security.wemExclusions' = 'Carl Stalhood'; 'maintenance.sessionTriggerTasks' = 'James Rankin'
            'apps.edgeStartupBoost' = 'Aaron Parker' }
    }
    It 'enthaelt genau die Pruefungen des Plans mit Bereich, Art und Schwellen' {
        @($Real.checks.id) | Should -Be @($PlanChecks.Values | ForEach-Object { $_ })
        @($Real.checks).Count | Should -Be 80; $Vendor.Count | Should -Be 31; $Practice.Count | Should -Be 14
        foreach ($c in $Real.checks) {
            $c.id | Should -BeLike ($c.area + '.*')
            $c.kind | Should -Be $(if ($Vendor -contains $c.id) { 'vendor' } elseif ($Practice -contains $c.id) { 'practice' } else { 'rule' }) -Because $c.id
        }
        $want = [ordered]@{ commitPeakPct = 90; commitNowPct = 98; memPerSessionMB = 1024; sessionsPerCpu = 8; workerCpuMin = 8; workerCpuMax = 8; workerMemMinMB = 24000; uptimeDays = 30; updateAgeDays = 60; diskFreeGB = 10; diskFreeHardGB = 2
            disconnectedHours = 24; unloadedProfiles = 20; containerUsedPct = 90; containerUsedHardPct = 95; containersPerUser = 3; printDrivers = 20; queuesPerSession = 10; signatureAgeDays = 2; eventDays = 3; workStartHour = 7; workEndHour = 18 }
        $want.Count | Should -Be 22
        # workerMemMinMB: Carl Stalhood nennt 24 GB (24576 MB); die Schwelle liegt knapp darunter, damit ein Server mit genau 24 GB, den Windows etwas kleiner meldet, nicht gemeldet wird
        @($Real.thresholds.PSObject.Properties.Name) | Should -Be @($want.Keys)
        foreach ($k in $want.Keys) { $Real.thresholds.$k.value | Should -Be $want[$k] -Because $k; $Real.thresholds.$k.default | Should -Be $want[$k] -Because $k }
        @(Get-WorkerPerfHealthChangedThresholds $Real).Count | Should -Be 0
    }
    It 'fuehrt die Ausnahme des Auftraggebers: beim Energiesparplan gilt die Praxisquelle vor dem Hersteller' {
        @($Real.precedence).Count | Should -Be 1; $Real.precedence[0].check | Should -Be 'operation.powerPlan'; $Real.precedence[0].winner | Should -Be 'practice'
        $Real.precedence[0].reason | Should -Match 'Terminalserver'
        $c = $Real.checks | Where-Object id -eq 'operation.powerPlan'; $c.kind | Should -Be 'practice'; $c.source.vendor | Should -Be 'Carl Stalhood'
        # der Widerspruch bleibt genannt; GO-EUC steht mit den Bedingungen seiner Messung als andere Sicht da und aendert weder Regel noch Einstufung
        foreach ($w in 'Microsoft', 'Ausbalanciert', 'VMware', 'BIS-F', 'GO-EUC', 'Windows 11', 'Azure') { $c.meaning | Should -Match $w -Because $w }
        (Get-Check @{ 'operation.powerPlan' = 'balanced' } @{} 'operation.powerPlan' $Real).grade | Should -Be 'check'
        (Get-Check @{ 'operation.powerPlan' = 'powerSaver' } @{} 'operation.powerPlan' $Real).grade | Should -Be 'check'
        (Get-Check @{ 'operation.powerPlan' = 'highPerformance' } @{} 'operation.powerPlan' $Real).grade | Should -Be 'ok'
        $Proof | Should -Match 'Ausnahmen: Praxisquelle vor Hersteller'
    }
    It 'nennt bei RSS und beim Ereignisbild, was die Praxisquelle sagt, und beim Zuordnungswerkzeug dessen Hersteller' {
        $rss = $Real.checks | Where-Object id -eq 'network.rss'; $rss.kind | Should -Be 'vendor'; $rss.meaning | Should -Match 'BIS-F'      # der Hersteller gilt, der Widerspruch ist genannt
        @($Real.precedence.check) | Should -Not -Contain 'network.rss'
        $e = $Real.checks | Where-Object id -eq 'events.sinceBoot'; @($e.rules.act).Count | Should -Be 0                                        # nie handeln
        $e.source.vendor | Should -Be 'BIS-F'; $e.source.url | Should -Match 'BISF\.psm1'; $e.meaning | Should -Match 'MCSIO'                  # die Voraussetzung der Quelle steht dabei
        $e.meaning | Should -Match 'Folgerung des Katalogs'
        foreach ($id in $K3) { @($Real.checks.id) | Should -Contain $id }
        $m = $Real.checks | Where-Object id -eq 'print.mappingClientSupported'; $m.kind | Should -Be 'vendor'; $m.source.vendor | Should -Be 'AKI'; $m.source.url | Should -Match '^https://www\.aki-gmbh\.com/'
        (Get-Check @{ 'print.mappingClientVersion' = '6.1.4' } @{} 'print.mappingClientSupported' $Real).grade | Should -Be 'check'
        (Get-Check @{ 'print.mappingClientVersion' = '6.4.1' } @{} 'print.mappingClientSupported' $Real).grade | Should -Be 'ok'
        (Get-Check @{ 'print.mappingClientVersion' = (New-WorkerPerfHealthValue 'absent' 'notInstalled') } @{} 'print.mappingClientSupported' $Real).grade | Should -Be 'na'      # Review Focus 3
        ($Real.areas | Where-Object id -eq 'print').notCovered | Should -Match 'PrinTaurus'
        ($Real.checks | Where-Object id -eq 'maintenance.updateServiceEnabled').source.vendor | Should -Be 'BIS-F'
        # der Name des Zuordnungswerkzeugs darf im Katalog stehen, sonst nichts aus der Umgebung des Auftraggebers: die Quelle ist die oeffentliche Seite des Herstellers
        $Proof | Should -Match '\| AKI \| Release Notes PrinTaurus 6\.4 \| https://www\.aki-gmbh\.com/download/47826/ \|'
    }
    It 'schreibt die Pruefungen aus den weiteren Praxisquellen und die Vorbehalte der Recherche in den Text' {                # Zusaetze d, g, j von Task 14b
        $check = @{}; foreach ($c in $Real.checks) { $check[[string]$c.id] = $c }
        # PXH-02: das Betriebsprotokoll des Druckdienstes; nie handeln, eine Voraussetzung der Fehlersuche, kein Leistungsmangel
        $log = $check['print.operationalLogOff']; $log.kind | Should -Be 'practice'; $log.source.vendor | Should -Be 'Trentent Tye'; $log.source.url | Should -Match '^https://trentent\.github\.io/'
        @($log.rules.act).Count | Should -Be 0; $log.meaning | Should -Match 'macht nichts schneller'; $log.meaning | Should -Match 'seit dem letzten Start'
        (Get-Check @{ 'print.operationalLog' = $false } @{} 'print.operationalLogOff' $Real).grade | Should -Be 'check'
        (Get-Check @{ 'print.operationalLog' = $true } @{} 'print.operationalLogOff' $Real).grade | Should -Be 'ok'
        (Get-Check @{} @{} 'print.operationalLogOff' $Real).grade | Should -Be 'ok'                                              # ohne das Protokoll: nicht gemeldet
        # Vorbehalte, die die Recherche zu einer Pruefung festhaelt
        $check['security.citrixExclusions'].meaning | Should -Match 'Sicherheitsteam'; $check['security.networkProtection'].meaning | Should -Match 'entscheidet das Sicherheitsteam'
        $check['events.crashes'].meaning | Should -Match 'Häufung, keine Ursache'; $check['network.dnsPublic'].meaning | Should -Match 'kann gewollt sein'
        $check['maintenance.updateServiceEnabled'].meaning | Should -Match 'nennt dafür keinen Zweck'; $check['maintenance.updateServiceEnabled'].meaning | Should -Match 'Begründung ist die des Katalogs'
        $mc = $check['print.mappingClientSupported']; $mc.meaning | Should -Match 'Master-Image'; $mc.meaning | Should -Match 'Release-Version'; $mc.meaning | Should -Match 'IPP'
        $check['security.wemExclusions'].meaning | Should -Match 'Microsoft rät'                                               # zwei Hersteller, zwei Sichten
        # Zusatz j: was die Quellenpruefung fuer die Wartung verlangt
        $up = $check['maintenance.updateInstallInWorkHours']; $up.meaning | Should -Match '03:00'; $up.meaning | Should -Match 'automatische Wartung'
        "$($up.meaning) $($up.findings.ok)" | Should -Match 'Ohne Richtlinie ist der Zeitpunkt der Installation nicht bekannt'
        $check['maintenance.defenderScanInWorkHours'].findings.check | Should -Match '^Der wirksame Beginn eines geplanten Scans'
        $full = $check['maintenance.defenderFullScan']; $full.kind | Should -Be 'rule'; $full.meaning | Should -Match 'schnell oder vollständig'; $full.meaning | Should -Match 'keine Empfehlung von Microsoft'
        foreach ($id in 'print.driverCount', 'print.kernelModeV2') { $check[$id].meaning | Should -Match 'nicht jede dieser Empfehlungen für jede Umgebung gilt' -Because $id }
        $Real.values.'maintenance.quickScanTime' | Should -BeExactly 'Startzeit des Schnellscans'; $Real.values.'maintenance.scanCpuLoad' | Should -BeExactly 'Höchster durchschnittlicher CPU-Anteil eines Scans'
        # die Einstufungen der neuen Bereiche an je einem Fall
        (Get-Check @{ 'security.defenderMode' = 'Normal'; 'security.defenderNetworkProtection' = 1 } @{} 'security.networkProtection' $Real).grade | Should -Be 'check'
        (Get-Check @{ 'security.defenderMode' = 'Passive'; 'security.defenderNetworkProtection' = 1 } @{} 'security.networkProtection' $Real).grade | Should -Be 'ok'
        (Get-Check @{ 'network.smb1' = 'Manual' } @{} 'network.smb1' $Real).grade | Should -Be 'check'; (Get-Check @{} @{} 'network.smb1' $Real).grade | Should -Be 'ok'
        (Get-Check @{ 'maintenance.updateService' = 'Manual' } @{} 'maintenance.updateServiceEnabled' $Real).grade | Should -Be 'check'
        (Get-Check @{ 'maintenance.updateService' = 'Disabled' } @{} 'maintenance.updateServiceEnabled' $Real).grade | Should -Be 'ok'
        (Get-Check @{ 'maintenance.scanDay' = 0; 'maintenance.scanType' = 2 } @{} 'maintenance.defenderFullScan' $Real).grade | Should -Be 'check'
        (Get-Check @{ 'maintenance.scanDay' = 8; 'maintenance.scanType' = 2 } @{} 'maintenance.defenderFullScan' $Real).grade | Should -Be 'ok'
        $x = Get-Check @{} @{ PrintDrivers = $HpNone; EventsBefore = @((New-Ev 1 'print')) } 'print.driversInSpooler' $Real
        $x.grade | Should -Be 'act'; $x.finding | Should -Match '^Druckertreiber, die ohne Isolierung im Prozess des Dienstes Druckwarteschlange \(Spooler\) laufen: 1\. Außerdem stehen'
    }
    It 'uebernimmt die Berichtigungen der Quellenpruefung an den Pruefungen von Task 14a' {                                     # Entscheidung ZB-R40
        $check = @{}; foreach ($c in $Real.checks) { $check[[string]$c.id] = $c }
        # die Seiten von Citrix stehen mit der Adresse da, die sie heute haben
        foreach ($c in $Real.checks) { $c.source.url | Should -Not -Match 'docs\.citrix\.com/en-us/' -Because $c.id }; $Proof | Should -Not -Match 'docs\.citrix\.com/en-us/'
        # vda.controllerCount: die Liste gilt auch neben der Registrierung ueber die Organisationseinheit
        @($check['vda.controllerCount'].rules.check | ForEach-Object { $_.value }) | Should -Be @('vda.controllerCount')
        (Get-Check @{ 'vda.version' = '2402'; 'vda.controllers' = @(@{ Entry = 'ddc1.sim.local'; Kind = 'fqdn'; From = 'policy' }); 'vda.farmGuid' = $true } @{} 'vda.controllerCount' $Real).grade | Should -Be 'check'
        $check['vda.controllerCount'].meaning | Should -Match 'aus seinem Cache'; $check['vda.controllerCount'].meaning | Should -Not -Match 'Vorrang|takes precedence'
        foreach ($id in 'vda.controllerCount', 'vda.controllerNotFqdn') { $check[$id].findings.check | Should -Match 'Controller-Gruppe' -Because $id }
        $check['vda.listOfSids'].meaning | Should -Match 'besonders gesicherte Umgebungen'
        $check['vda.services'].meaning | Should -Match 'CTX133769'; $check['vda.services'].meaning | Should -Match 'Folgerung des Katalogs'
        # temporaere Profile: Windows loescht sie bei der Abmeldung, gezaehlt werden die der laufenden Sitzungen
        $tp = $check['sessions.tempProfiles']; foreach ($f in 'ok', 'check', 'act') { $tp.findings.$f | Should -Match 'in den laufenden Sitzungen' -Because $f; $tp.findings.$f | Should -Not -Match 'Profile? seit dem letzten Start' -Because $f }
        $tp.findings.check | Should -Match 'löscht ein temporäres Profil bei der Abmeldung'
        foreach ($id in 'sessions.disconnectLimit', 'sessions.idleLimit') {
            $c = $check[$id]; "$($c.findings.check) $(@($c.todo | ForEach-Object { $_.text }) -join ' ')" | Should -Match 'ab VDA 2203 LTSR CU2' -Because $id
            $c.meaning | Should -Match 'gelten die Einstellungen des Benutzerkontos' -Because $id
        }
        $check['size.pagefilePresent'].meaning | Should -Match 'empfiehlt Microsoft eine eigene Datei dafür \(dedicated dump file\)'
        $check['size.memoryPerSession'].meaning | Should -Match 'aller Benutzersitzungen beim Lesen, auch der getrennten'
        $check['operation.powerPlan'].meaning | Should -Match 'wo nicht das Betriebssystem die Energieverwaltung steuert'
        $check['operation.updateAge'].meaning | Should -Match 'über die Komponentenwartung von Windows installiert'
        $check['operation.pendingRestart'].findings.check | Should -Match '^Ausstehende Umbenennungen oder Löschungen beim Neustart: '; $Real.values.'operation.pendingRename' | Should -BeExactly 'Ausstehende Umbenennungen oder Löschungen beim Neustart'
        "$($check['operation.pendingRestart'].meaning)" | Should -Not -Match 'Microsoft empfiehlt|Empfehlung von Microsoft'
        $check['profile.containersPerUser'].meaning | Should -Match 'in der Voreinstellung mehrere Sitzungen zugleich auf einen Profilcontainer zugreifen'
        $ProofFlat | Should -Match 'TotalPhysicalMemory'; $ProofFlat | Should -Match 'TASK_ENUM_FLAGS'
        # Zusaetze m, o, p, q
        (Get-Check @{ 'size.memTotalMB' = 16384 } @{} 'size.workerMemory' $Real).finding | Should -BeExactly 'Der Server hat 16384 MB Arbeitsspeicher, weniger als die Untergrenze von 24000 MB (Praxiswert: 24 GB). Das ist ein Hinweis, kein Fehler.'
        $x = Get-Check @{ 'size.memTotalMB' = 16384; 'size.commitTotalMB' = 100 } @{} 'size.commitHeadroom' $Real                    # die Zusagegrenze fehlt: nicht pruefbar
        $x.grade | Should -Be 'unknown'; ([regex]::Matches($x.finding, 'Wert')).Count | Should -Be 1 -Because $x.finding
        $starts = 'Auto = automatisch, Manual = manuell, Disabled = deaktiviert'
        foreach ($id in 'vda.services', 'vda.wemServices', 'security.services', 'print.spoolerStartMode', 'maintenance.updateService', 'network.smb1') { $Real.legends.$id | Should -Match ([regex]::Escape($starts)) -Because $id }
        foreach ($id in 'vda.services', 'vda.wemServices', 'security.services') { $Real.legends.$id | Should -Match 'Running = läuft, Stopped = beendet' -Because $id }
        $wem = $check['vda.wemServices']; $wem.meaning | Should -Match 'den Dienst SENS \(System Event Notification Service\) von Windows'
        (@($wem.todo | ForEach-Object { $_.text }) -join ' ') | Should -Match 'Dienstnamen SENS'
    }
    It 'meldet mehr und weniger Prozessoren als die Praxisquellen nennen, nie als handeln' {
        foreach ($id in 'size.workerCpu', 'size.workerCpuMax') {
            $c = $Real.checks | Where-Object id -eq $id; $c.kind | Should -Be 'practice'; $c.source.vendor | Should -Be 'Carl Stalhood'; @($c.rules.act).Count | Should -Be 0
            foreach ($w in 'Carl Stalhood', 'GO-EUC', '2019', 'Windows Server 2016') { $c.meaning | Should -Match $w -Because "$id $w" }      # beide Quellen, GO-EUC mit den Bedingungen des Tests
        }
        foreach ($case in @(@(4, 'check', 'ok'), @(8, 'ok', 'ok'), @(16, 'ok', 'check'))) {
            (Get-Check @{ 'size.cpuLogical' = $case[0] } @{} 'size.workerCpu' $Real).grade | Should -Be $case[1] -Because "$($case[0]) Prozessoren"
            (Get-Check @{ 'size.cpuLogical' = $case[0] } @{} 'size.workerCpuMax' $Real).grade | Should -Be $case[2] -Because "$($case[0]) Prozessoren"
        }
        (Get-Check @{ 'size.cpuLogical' = 16 } @{} 'size.workerCpuMax' $Real).finding | Should -BeExactly 'Logische Prozessoren des Servers: 16, mehr als der Praxiswert von 8. Das ist ein Hinweis, kein Fehler.'
    }
    It 'traegt die Texte, auf die sich Bericht und Seite stuetzen, und zu jeder Pruefung einen Vorschlag' {
        $want = [ordered]@{ title = 'Zustand des Servers'; notRecorded = 'Zustandsbild nicht erfasst.'; unreadable = 'Zustandsbild nicht lesbar.'; healthOnlyHead = 'Zustandsbericht ohne Messung'
            summary = '{act} zum Handeln, {check} zum Prüfen, {ok} in Ordnung'; areaOne = '1 Bereich'; areaMany = '{n} Bereiche'
            countsAct = '{n} zum Handeln'; countsCheck = '{n} zum Prüfen'; countsUnknown = '{n} nicht prüfbar'; reasonSkipped = '{category} nicht erfasst (-Skip)'
            yes = 'ja'; no = 'nein'; noValue = '–'; copyCheckTitle = '{area} – {title}: {grade}'; copyAreaTitle = '{area}: {grade}'; copyAreaItem = '- {title}: {grade}. {finding}'
            kindVendor = 'Empfehlung des Herstellers'; kindPractice = 'Empfehlung aus der Praxis'; kindRule = 'Faustregel'; notApplicable = 'Trifft nicht zu: {reason}.'
            reasonAppNotInstalled = '{app} ist nicht installiert'; appNotInstalled = '{app}: nicht installiert'
            environment = 'Der Katalog geht von nicht persistenten, über Machine Creation Services bereitgestellten Multi-Session-Servern aus.' }
        foreach ($k in $want.Keys) { $Real.copy.$k | Should -Be $want[$k] -Because $k }
        $Real.copy.notRecordedFailed | Should -BeLike 'Zustandsbild nicht erfasst*'; $Real.copy.stateNotApplicable | Should -BeLike 'nicht zutreffend*'
        $Real.copy.eventsReach | Should -Match '\{from\}'; $Real.copy.eventsReach | Should -Match '\{boot\}'; $Real.grades.na.word | Should -Be 'Trifft nicht zu'
        @($Real.areas.label) | Should -Be @('Größe und Reserve', 'Betrieb', 'Sitzungen', 'Citrix VDA', 'Profilverwaltung', 'Drucken', 'Sicherheitsprodukte', 'Netz und Dateiserver', 'Ereignisbild', 'Wartung in der Arbeitszeit', 'Anwendungen')
        foreach ($a in $Real.areas) { [string]$a.notCovered | Should -Not -BeNullOrEmpty -Because $a.id }
        foreach ($c in $Real.checks) { @($c.todo).Count | Should -BeGreaterThan 0 -Because $c.id }
    }
    It 'nennt die gemessene Maschine Server' {                                                          # Wortwahl des Auftraggebers (Entscheidung ZB-R24)
        # kein Wort des Katalogs beginnt mit "Worker", ausser dem Namen des Werkzeugs; Kennungen (workerCpuMin, size.workerCpu) beginnen klein
        $words = @([regex]::Matches((Get-Content $CatFile -Raw), '\bWorker\w*') | ForEach-Object { $_.Value } | Sort-Object -Unique)
        @($words | Where-Object { $_ -cne 'WorkerPerf' }) | Should -Be @()
        $Real.copy.eventsReach | Should -Match 'Start des Servers'
    }
    It 'nennt keine kopierbaren Befehle und keine Ursachen' {
        foreach ($c in $Real.checks) {
            foreach ($t in $c.todo) { "$($t.text) $($t.where) $($t.sign)" | Should -Not -Match '(?i)(\b(Set|New|Remove|Stop|Restart|Disable|Enable)-[A-Z]\w+|reg(\.exe)? add|powercfg|wevtutil|sc(\.exe)? (stop|config)|net stop)' -Because $c.id }
            foreach ($f in $c.findings.PSObject.Properties) { $f.Value | Should -Not -Match 'ist die Ursache|verursacht den' -Because $c.id }
        }
        $Real.copy.incidentNote | Should -Match 'beitragen'
    }
    It 'nennt Praxisquellen als Praxisquellen, aus der Liste des Nachweises' {
        # die Tabelle "Praxisquellen" des Nachweises: | Name | Adresse | recherchiert oder offen |
        $px = @{}; foreach ($m in [regex]::Matches($Proof, '(?m)^\| (?<n>[^|]+?) \| (?<u>https?://\S+) \| (?<s>recherchiert|offen) \|\s*$')) { $px[$m.Groups['n'].Value] = $m.Groups['s'].Value }
        $px.Count | Should -Be 12; foreach ($n in $PracticeSources) { $px.ContainsKey($n) | Should -BeTrue -Because $n }
        @($px.Keys | Where-Object { $px[$_] -eq 'recherchiert' } | Sort-Object) | Should -Be @($PracticeSources | Sort-Object)
        # die dreizehnte Quelle des Entwurfs steht ohne Adresse da; die alte Domaene von Trentent Tye kommt nicht vor
        $Proof | Should -Match '(?m)^.*Kasper Johansen.*nicht mehr erreichbar, nicht verwendet.*$'; $Proof | Should -Not -Match 'virtualwarlock|theorypc'
        foreach ($c in @($Real.checks | Where-Object kind -eq 'practice')) {
            $px[[string]$c.source.vendor] | Should -Be 'recherchiert' -Because $c.id; $c.source.url | Should -Match '^https://' -Because $c.id
            "$($c.title) $($c.meaning) $(@($c.findings.PSObject.Properties.Value) -join ' ')" | Should -Not -Match 'Empfehlung des Herstellers|Hersteller empfiehlt' -Because $c.id
        }
        foreach ($c in @($Real.checks | Where-Object kind -eq 'vendor')) { $px.ContainsKey([string]$c.source.vendor) | Should -BeFalse -Because $c.id; $c.source.url | Should -Match '^https://' -Because $c.id }
        $Proof | Should -Match 'Quellen aus der Praxis: BIS-F'; $Proof | Should -Match 'Quellen aus der Praxis: carlstalhood\.com'
    }
    It 'nennt die zweite Quelle einer Pruefung im Text und fuehrt sie im Nachweis' {                    # Entscheidung ZB-R31
        $flat = [regex]::Replace($Proof, '\r?\n  (?=\S)', ' ')                 # ein Listenpunkt des Nachweises ist bei 120 Zeichen umbrochen: seine Zeilen wieder verbinden
        foreach ($id in $SecondSources.Keys) {
            $c = $Real.checks | Where-Object id -eq $id
            "$($c.meaning) $(@($c.todo | ForEach-Object { $_.text }) -join ' ')" | Should -Match ([regex]::Escape($SecondSources[$id])) -Because $id
            # im Nachweis: eine Zeile mit der Kennung der Pruefung, "auch gestützt durch:" und einer Adresse
            $flat | Should -Match ('(?m)^.*`' + [regex]::Escape($id) + '`.*auch gestützt durch: .*https://\S+.*$') -Because $id
        }
    }
    It 'nennt das Master-Image oder die Richtlinie als Ort der Aenderung und den letzten Start als Grenze' {
        # Pruefungen ohne Einstellung im Master-Image oder in einer Richtlinie: ihre Schritte lassen nachsehen oder aufraeumen, oder die Abhilfe liegt im Neustartplan der Bereitstellungsgruppe
        $look = @('size.commitHeadroom', 'size.commitAboveRam', 'operation.pendingRestart', 'operation.uptime', 'operation.diskFree', 'sessions.disconnectedOld', 'sessions.unloadedProfiles', 'sessions.tempProfiles',
            'profile.containerFull', 'profile.containersPerUser', 'events.crashes', 'events.storage', 'events.fileserver', 'events.coverage', 'network.smbOldDialect')
        foreach ($c in $Real.checks) {
            foreach ($t in $c.todo) { "$($t.text) $($t.where)" | Should -Not -Match '(?i)auf diesem Server (ändern|einstellen|setzen)|am einzelnen Server (ändern|einstellen|setzen)' -Because $c.id }
            if ($look -notcontains $c.id) { @($c.todo | Where-Object { $_.where -match 'Master-Image|Richtlinie|WEM-Konfiguration' }).Count | Should -BeGreaterThan 0 -Because $c.id }
        }
        foreach ($id in @($K3 | Where-Object { @($Real.checks.id) -contains $_ })) {      # in Task 14a die zwei der Sitzungen, ab Task 14b alle sieben
            $c = $Real.checks | Where-Object id -eq $id; @($c.values) | Should -Contain 'operation.lastBoot' -Because $id
            $c.findings.check | Should -Match '\{operation\.lastBoot\}' -Because $id
        }
        ($Real.checks | Where-Object id -eq 'operation.updateAge').findings.check | Should -Match 'Abbild'
        (Get-Content $CatFile -Raw) | Should -Not -Match 'Provisioning Services|\bPVS\b'                              # nichts, was nur fuer Provisioning Services gilt
    }
    It 'stuetzt keine Pruefung auf einen Wert ohne dokumentierte Lesequelle' {
        $t = Get-WorkerPerfHealthFactTable $Apps; @($t.Keys).Count | Should -Be 206
        foreach ($c in $Real.checks) { foreach ($v in $c.values) { $t[$v].Documented | Should -BeTrue -Because "$($c.id): $v" } }
        @($Real.values.PSObject.Properties.Name).Count | Should -Be 168
    }
    It 'fuehrt die Quelle jeder Pruefung im Nachweis' {
        foreach ($c in $Real.checks) {
            $ProofFlat | Should -Match ([regex]::Escape($c.source.title)) -Because $c.id; $c.source.date | Should -Match '^\d{4}-\d\d-\d\d$' -Because $c.id
            if ($c.source.url) { $ProofFlat | Should -Match ([regex]::Escape($c.source.url)) -Because $c.id }
        }
    }
    It 'fuellt in jedem Befund jeden Platzhalter und nennt die Einheit im Satz' {                       # Entscheidung ZB-R15
        # ein Zustandsbild ohne gelesene Werte und eines mit auffaelligen Werten: kein Befund behaelt eine geschweifte Klammer
        $bad = @{ 'size.cpuLogical' = 16; 'size.memTotalMB' = 16384; 'size.commitTotalMB' = 30000; 'size.commitLimitMB' = 30500; 'size.commitPeakMB' = 30400; 'size.pagefiles' = @()
            'operation.lastBoot' = $ReadMs - 40 * 86400000L; 'operation.pendingRename' = 3; 'operation.lastUpdate' = $ReadMs - 90 * 86400000L; 'operation.powerPlan' = 'balanced'
            'operation.volumes' = @(@{ Drive = 'C:'; SizeGB = 100; FreeGB = 1.5; FileSystem = 'NTFS'; System = $true; PageFile = $true }); 'profile.service' = 'Stopped' }
        foreach ($values in @{}, $bad) {
            $r = Get-WorkerPerfHealthResult -Model (New-HealthModel $values) -Catalogue $Real -EventConfig $Cfg -Roles $Roles -Texts $Texts
            $checks = @($r.areas | ForEach-Object { $_.checks }); $checks.Count | Should -Be @($Real.checks).Count
            foreach ($c in $checks) { $c.finding | Should -Not -Match '[{}]' -Because $c.id; $c.finding | Should -Not -BeNullOrEmpty -Because $c.id }
        }
        (Get-Check $bad @{} 'operation.diskFree' $Real).grade | Should -Be 'act'
        (Get-Check $bad @{} 'operation.diskFree' $Real).finding | Should -Match '1,5 GB frei .*2 GB'
        (Get-Check $bad @{} 'operation.updateAge' $Real).finding | Should -BeExactly 'Alter des jüngsten Updates im Abbild in Tagen: 90, mehr als die Schwelle von 60.'
        (Get-Check $bad @{} 'size.commitHeadroom' $Real).grade | Should -Be 'act'
    }
    It 'zeigt an der Schwelle die Zahl, mit der die Regel vergleicht' {                                  # Korrekturrunde 1, C1
        # 30,4 Tage gegen 30 und 100,4 % gegen 100: der Befund nennt die Zahl mit ihrer Nachkommastelle, genau auf der Schwelle bleibt die Pruefung in Ordnung
        $x = Get-Check @{ 'operation.lastBoot' = $ReadMs - [long](30.4 * 86400000) } @{} 'operation.uptime' $Real
        $x.grade | Should -Be 'check'; $x.finding | Should -BeExactly 'Laufzeit seit dem letzten Start in Tagen: 30,4, mehr als die Schwelle von 30.'
        $x = Get-Check @{ 'operation.lastBoot' = $ReadMs - 30 * 86400000L } @{} 'operation.uptime' $Real
        $x.grade | Should -Be 'ok'; $x.finding | Should -BeExactly 'Laufzeit seit dem letzten Start in Tagen: 30 (Schwelle 30).'
        $x = Get-Check @{ 'size.memTotalMB' = 10000; 'size.commitTotalMB' = 10040 } @{} 'size.commitAboveRam' $Real
        $x.grade | Should -Be 'check'; $x.finding | Should -BeExactly 'Der zugesagte Speicher liegt beim Lesen bei 100,4 % des Arbeitsspeichers, also über dem, was der Server an Arbeitsspeicher hat.'
        $x = Get-Check @{ 'size.memTotalMB' = 10000; 'size.commitTotalMB' = 10000 } @{} 'size.commitAboveRam' $Real
        $x.grade | Should -Be 'ok'; $x.finding | Should -BeExactly 'Der zugesagte Speicher liegt beim Lesen bei 100 % des Arbeitsspeichers.'
        $x = Get-Check @{ 'sessions.list' = @(@{ Id = 3; State = 'Disconnected'; User = 'gast'; DisconnectTime = $ReadMs - [long](24.3 * 3600000) }) } @{} 'sessions.disconnectedOld' $Real
        $x.grade | Should -Be 'check'; $x.finding | Should -BeExactly 'Dauer der ältesten getrennten Sitzung in Stunden: 24,3, mehr als die Schwelle von 24.'
    }
    It 'nennt Einheiten in der Einzahl und schreibt jeden Befund so, dass er auch fuer 1 stimmt' {        # Korrekturrunde 1, C2
        @($Real.units.PSObject.Properties | ForEach-Object { $_.Name + '=' + $_.Value }) | Should -Be @('Tage=Tag', 'Stunden=Stunde', 'Minuten=Minute')
        $one = @{ 'operation.lastBoot' = $ReadMs - 86400000L; 'operation.lastUpdate' = $ReadMs - 86400000L - 3600000L
            'sessions.limits' = @(@{ Terminal = 'ICA-CGP'; IdleLimitMin = 1; DisconnectedLimitMin = 1; ActiveLimitMin = 0; BrokenAction = 0; FromPolicy = $true })
            'sessions.list' = @(@{ Id = 3; State = 'Disconnected'; User = 'gast'; DisconnectTime = $ReadMs - 3600000L }) }
        (Get-Check $one @{} 'operation.uptime' $Real).value | Should -BeExactly 'Laufzeit seit dem letzten Start: 1 Tag'
        (Get-Check $one @{} 'operation.updateAge' $Real).value | Should -BeExactly 'Alter des jüngsten Updates: 1 Tag'
        (Get-Check $one @{} 'sessions.disconnectedOld' $Real).value | Should -BeExactly 'Dauer der ältesten getrennten Sitzung: 1 Stunde'
        (Get-Check $one @{} 'sessions.disconnectLimit' $Real).value | Should -BeExactly 'Zeitlimit für getrennte Sitzungen: 1 Minute'
        (Get-Check $one @{} 'sessions.idleLimit' $Real).value | Should -BeExactly 'Zeitlimit für Sitzungen im Leerlauf: 1 Minute'
        (Get-Check $one @{} 'operation.uptime' $Real).finding | Should -BeExactly 'Laufzeit seit dem letzten Start in Tagen: 1 (Schwelle 30).'
        # kein Befundsatz stellt hinter eine eingesetzte Zahl ein Wort, das nur in der Mehrzahl stimmt (MB, GB und % haben keine Einzahl)
        $plural = '\}\s+(Tage|Tagen|Stunden|Minuten|Sekunden|Profile|Sitzungen|Benutzersitzungen|Prozessoren|logische|lokale|Dienste|Dateien|Controller\b|Treiber|Druckertreiber|Warteschlangen|Aufgaben|Protokolle|Ereignisse|Verbindungen|Adapter|Prozesse)'
        foreach ($c in $Real.checks) { foreach ($f in $c.findings.PSObject.Properties) { $f.Value | Should -Not -Match $plural -Because "$($c.id) $($f.Name)" } }
        # jede Pruefung mit lauter Einsen bewertet: kein Befund sagt "1 Tage" oder "1 Tagen"
        $ones = @{ 'size.cpuLogical' = 1; 'size.memTotalMB' = 1; 'size.commitTotalMB' = 1; 'size.commitLimitMB' = 1; 'size.commitPeakMB' = 1; 'operation.pendingRename' = 1; 'vda.wemGpNetworkTimeout' = 1 } + $one
        $r = Get-WorkerPerfHealthResult -Model (New-HealthModel $ones) -Catalogue $Real -EventConfig $Cfg -Roles $Roles -Texts $Texts
        foreach ($c in @($r.areas | ForEach-Object { $_.checks })) { $c.finding | Should -Not -Match '(?<![\d,])1 (Tage|Tagen|Stunden|Minuten|Sekunden|Profile|Sitzungen|Benutzersitzungen|Prozessoren|logische|lokale)\b' -Because $c.id }
    }
    It 'sagt nicht zutreffend so, dass es nicht wie ein Ergebnis klingt, und nennt jeden Schritt mit Ort und Merkmal' {   # Korrekturrunde 1, B1, B2
        # ein Server, der keine VMware-VM ist: die Pruefung trifft nicht zu; der Satz sagt nicht "... gibt es auf diesem Server nicht"
        $x = Get-Check @{ 'size.model' = 'Sim Corp Server 1'; 'size.netAdapters' = @() } @{} 'size.netAdapterType' $Real
        $x.grade | Should -Be 'na'
        $x.finding | Should -BeExactly ('Trifft nicht zu: der Wert „Aktive Netzwerkadapter, die nicht VMXNET3 sind“ wird auf diesem Server nicht gelesen, weil das Produkt, zu dem er gehört, nicht installiert ist ' +
            '(bei Werten zu VMware: weil der Server keine VMware-VM ist).')
        $Real.copy.reasonNotInstalled | Should -Not -Match 'gibt es'
        # eine Bezeichnung, die in diesem Satz in Anfuehrungszeichen steht, traegt selbst keine (die Werte der fuenf Bereiche dieser Task)
        foreach ($p in $Real.values.PSObject.Properties) { $p.Value | Should -Not -Match '[„“]' -Because $p.Name }
        $Real.copy.copyStep | Should -BeExactly '{n}. {text} – Wo: {where}. Woran zu erkennen: {sign}'
        # der Lader verlangt in jedem Schritt Ort und Merkmal: keiner der zwei Teile kann fehlen; kein Teil endet mit einem Punkt, der im Kopiertext doppelt staende
        foreach ($c in $Real.checks) { foreach ($t in $c.todo) { foreach ($part in $t.text, $t.where, $t.sign) { $part | Should -Not -Match '[.;:]\s*$' -Because $c.id } } }
    }
    It 'haelt die Regeln fuer die Texte ein, die die Durchsicht ergeben hat' {                              # Korrekturrunde 1, A und B
        # A1: die Messung von GO-EUC bleibt in ihrem Test; der Vorbehalt von VMware steht da
        $pp = ($Real.checks | Where-Object id -eq 'operation.powerPlan').meaning
        $pp | Should -Not -Match 'verspricht'; foreach ($w in 'In diesem Test', 'nicht Teil der Messung', 'vSphere hat GO-EUC in diesem Test nicht gemessen', 'älteren Windows-Versionen') { $pp | Should -Match $w -Because $w }
        # A2: unterstuetzt ist ein Stand erst ab dem Mindeststand; ohne VMware Tools sagt der Befund nicht, sie haetten die Hauptversion 0
        $vt = $Real.checks | Where-Object id -eq 'size.vmTools'
        $vt.meaning | Should -Match 'ab dem Mindeststand und unter 12\.0\.0'; $vt.meaning | Should -Match 'unter dem Mindeststand ist danach nicht unterstützt'; $vt.meaning | Should -Not -Match 'Ein älterer Stand ist danach unterstützt'
        $none = Get-Check @{ 'size.model' = 'VMware, Inc. VMware7,1'; 'size.vmtoolsVersion' = (New-WorkerPerfHealthValue 'absent' 'notInstalled') } @{} 'size.vmTools' $Real
        $none.grade | Should -Be 'check'; $none.finding | Should -BeLike 'Hauptversion der VMware Tools: 0 (installierte Version: –).*Eine 0 heißt: Auf dieser VMware-VM wurden keine VMware Tools gefunden.'
        # A4: eine Faustregel sagt, dass sie vom Katalog stammt
        foreach ($c in @($Real.checks | Where-Object kind -eq 'rule')) { $c.meaning | Should -Match 'Faustregel des Katalogs|Erfahrungswerte? des Katalogs' -Because $c.id }
        # B8: der Satz fuer nicht pruefbar wiederholt die Einstufung nicht
        # Zusatz s von Task 14c: der Rahmen passt zu jedem Grund, auch zu einem, der kein Fehler beim Lesen ist (perUser, ein nicht vorhandener Wert)
        foreach ($c in $Real.checks) { $c.findings.unknown | Should -BeExactly 'Ein Wert, den die Prüfung braucht, liegt nicht vor: {reason}.' -Because $c.id }
        # B5, B7: wo ein Ereignis die Pruefung zu Handeln macht, bindet der Befund die Ereignisse nicht an das Gepruefte, und die Bedeutung nennt die Grenze des Rueckblicks
        $withEvent = @($Real.checks | Where-Object { @($_.rules.act | Where-Object { $null -ne $_.event }).Count -gt 0 })
        @($withEvent.id) | Should -Be @('sessions.tempProfiles', 'vda.services', 'profile.serviceStopped', 'print.driversInSpooler', 'print.isolationOff', 'network.smbOldDialect')
        foreach ($c in $withEvent) {
            $c.findings.act | Should -Match 'Außerdem stehen im Rückblick der letzten 7 Tage oder in der Messung .*; ob sie .*, zeigt die Ereignisanzeige\.$' -Because $c.id
            $c.findings.act | Should -Not -Match 'Dazu stehen' -Because $c.id
            $c.meaning | Should -Match 'auf einem nicht persistenten Server reichen .*nur bis zum letzten Start zurück' -Because $c.id
        }
        # B3: Registrierung heisst die Windows-Registrierung oder die Registrierung des VDA; Anmeldung ist die der Benutzer
        $all = Get-Content $CatFile -Raw
        $all | Should -Not -Match '(?<!Windows-)Registrierung(?! des VDA)'; $all | Should -Not -Match 'Anmeldung des VDA|meldet den Server|meldet sich bei einem'
        # B4: der Befund zum Cache des WEM-Agenten nennt keinen Ort als gefunden
        # seit Task 14c nach research-wem-check.md (WEM-R01): auch der Agent eigener WEM-Server ab 2603
        ($Real.checks | Where-Object id -eq 'vda.wemCache').findings.check | Should -Match 'Ohne Eintrag liegt er im Programmordner des Agenten\. Der Agent des WEM-Dienstes der Citrix Cloud sucht sich ab Version 2408\.1\.0\.1 nach Citrix selbst einen beständigen Ort; für den Agenten eigener WEM-Server ab 2603 nennt Citrix Ereignisse zu einem Cache an einem beständigen Datenort\.$'
        # B6: die drei Hinweise zur Groesse sagen, dass sie Hinweise sind und eine bewusst gewaehlte Groesse bleiben kann
        foreach ($id in 'size.workerCpu', 'size.workerCpuMax', 'size.workerMemory') {
            $c = $Real.checks | Where-Object id -eq $id
            $c.findings.check | Should -Match '(Praxiswert von \{@\w+\}|Untergrenze von \{@workerMemMinMB\} MB \(Praxiswert: 24 GB\)).*Das ist ein Hinweis, kein Fehler\.$' -Because $id; $c.meaning | Should -Match 'bewusst anders gewählt, ist nichts zu ändern' -Because $id
            (@($c.todo | ForEach-Object { $_.text }) -join ' ') | Should -Not -Match 'anheben|wenn nichts dagegen spricht|wenn kein Grund dagegen spricht' -Because $id
        }
        # ein Server mit genau 24 GB, den Windows mit 24575 MB meldet, wird nicht gemeldet
        (Get-Check @{ 'size.memTotalMB' = 24575 } @{} 'size.workerMemory' $Real).grade | Should -Be 'ok'; (Get-Check @{ 'size.memTotalMB' = 16384 } @{} 'size.workerMemory' $Real).grade | Should -Be 'check'
        # B8: die gemessene Maschine heisst Server; Kennwoerter und englische Zustaende stehen mit ihrer Bedeutung da
        $all | Should -Not -Match 'Sitzungshost|Zeitgeber|nicht persistenten VDAs'
        $Real.legends.'operation.powerPlan' | Should -Match 'balanced = Ausbalanciert'; (Get-Check @{ 'operation.powerPlan' = 'balanced' } @{} 'operation.powerPlan' $Real).finding | Should -Match 'sondern balanced \(balanced = „Ausbalanciert“'
        foreach ($id in 'vda.desktopService', 'vda.wemService', 'profile.service') { $Real.legends.$id | Should -Match 'Running = läuft, Stopped = beendet' -Because $id }
        (Get-Check @{ 'profile.service' = 'Stopped' } @{} 'profile.serviceStopped' $Real).finding | Should -Match 'gelesener Zustand: Stopped; Running = läuft, Stopped = beendet'
        # B8 und Entscheidung ZB-R44 (Saetze der Bedeutung): eigener Test "schreibt eine Bedeutung in hoechstens drei Saetzen ..." fuer alle Pruefungen
        # B8: Zahlen, die eine Schwelle wiederholen, stehen nicht in Schritten
        foreach ($id in 'size.workerCpu', 'size.workerCpuMax', 'size.workerMemory', 'operation.updateAge', 'sessions.disconnectedOld') {
            (@(($Real.checks | Where-Object id -eq $id).todo | ForEach-Object { "$($_.text) $($_.sign)" }) -join ' ') | Should -Not -Match '\bacht\b|24576|zwei Monate|einem Tag' -Because $id
        }
    }
    It 'fuehrt im Nachweis die Vorbehalte der Hersteller, das Datum der Seite von Microsoft und was auf dem Zielsystem zu bestaetigen ist' {   # Korrekturrunde 1, A4, B8
        $Proof | Should -Match 'power-performance-tuning\s+\(Stand der Seite 2022-08-29, Abruf 2026-11-13\)'
        $ProofFlat | Should -Match 'not suitable for DAS environments'; $ProofFlat | Should -Match 'may increase overall performance'
        $Proof | Should -Match '(?m)^### Auf dem Zielsystem zu bestätigen$'
        $confirm = ($Proof -split '(?m)^### Auf dem Zielsystem zu bestätigen$', 2)[1]
        foreach ($w in 'Höchstleistung', 'Running', 'System Event Notification Service', 'Set time limit for disconnected sessions', 'Delete locally cached profiles on logoff', 'Wartungsmodus', '24000 MB') { ($confirm -replace '\s+', ' ') | Should -Match ([regex]::Escape($w)) -Because $w }
        $Proof | Should -Match ([regex]::Escape('| `workerMemMinMB` | 24000 MB |'))
    }
    It 'bricht den Abschnitt des Nachweises bei 120 Zeichen um und fuehrt die Schwellen und Quellen von Task 14b' {       # Zusatz r von Task 14b
        # Fliesstext und Listenpunkte: hoechstens 120 Zeichen; ein Listenpunkt geht mit zwei Leerzeichen Einzug weiter; Tabellenzeilen sind ausgenommen
        $n = 0; $inItem = $false
        foreach ($line in ($Proof -split "`r?`n")) {
            $n++
            if ($line -match '^\|') { $inItem = $false; continue }
            if ($line -notmatch '^\s*(- )?\S+$') { $line.Length | Should -BeLessOrEqual 120 -Because "Zeile $n des Abschnitts: $line" }      # eine Adresse laesst sich nicht umbrechen
            if ($line -match '^- ') { $inItem = $true } elseif ($line -eq '') { $inItem = $false } elseif ($inItem) { $line | Should -Match '^  \S' -Because "Zeile $n des Abschnitts: $line" }
        }
        foreach ($row in '| `printDrivers` | 20 Treiber |', '| `queuesPerSession` | 10 Warteschlangen |', '| `signatureAgeDays` | 2 Tage |', '| `eventDays` | 3 Tage |') { $Proof | Should -Match ([regex]::Escape($row)) -Because $row }
        foreach ($w in 'CTX696648', 'Trentent Tye', 'BISF.psm1', 'System Optimizations', 'SENS') { $ProofFlat | Should -Match ([regex]::Escape($w)) -Because $w }
        $Proof | Should -Not -Match 'die übrigen\s+Bereiche folgen'
    }
    It 'behaelt die Wortlaute, die die Korrekturrunde von Task 14a berichtigt hat' {                        # Nachpruefung von Task 14a: achtzehn Wortlaute ohne eigene Aussage
        $check = @{}; foreach ($c in $Real.checks) { $check[[string]$c.id] = $c }
        $steps = { param($id) @($check[$id].todo | ForEach-Object { $_.text }) -join ' ' }
        # 1, 2: Citrix raet nur beim Dienst des WEM-Agenten vom Neustart per Skript ab; die Folge fuer Benutzer ist als Erlaeuterung des Katalogs gekennzeichnet
        (& $steps 'vda.wemServices') | Should -Match 'den Dienst „Citrix WEM Agent Host Service“ nicht per Skript beenden oder neu starten \(Citrix rät davon ab\)'
        $check['vda.wemServices'].meaning | Should -Match 'Erläuterung des Katalogs, nicht von Citrix'
        # 3: der Vorbehalt von VMware zum direkt angeschlossenen Speicher steht im Text der Pruefung
        $check['size.storageController'].meaning | Should -Match 'nennt den Adapter für direkt angeschlossenen Speicher \(DAS\) nicht geeignet'
        # 4: Thomas Koetzing steht hinter dem, was er sagt, nicht hinter dem Zusatz zum Neustart
        (& $steps 'sessions.tempProfiles') | Should -Match 'in der Profilliste suchen \(Thomas Kötzing, 2024\), solange der Server läuft'
        # 5 bis 7: die Seite nennt keine Zahl; die Wartezeit hat ihren Preis; die Beobachtung von Manuel Winkel gilt fuer eigene WEM-Server
        $check['size.cpuPerSession'].meaning | Should -Match 'eine Zahl nennt die Seite nicht'; $check['size.cpuPerSession'].meaning | Should -Not -Match 'nennt Microsoft nicht'
        $check['vda.wemGpTimeout'].meaning | Should -Match 'Der Preis der Wartezeit ist nach Citrix, dass es länger dauern kann'
        $check['vda.wemCache'].meaning | Should -Match 'mit WEM 2507 CU1 und eigenen WEM-Servern'
        # 8: der Satz, der nicht auf der Seite von Microsoft steht, bleibt gestrichen; 14: die Faustregel sagt "meist"
        $check['operation.pendingRestart'].meaning | Should -Not -Match 'Installationen und Updates nutzen das'
        $check['operation.pendingRestart'].meaning | Should -Match 'wurde nach der Faustregel des Katalogs meist seit dem letzten Start etwas installiert oder aktualisiert'
        # 9 bis 11: die drei Saetze fuer in Ordnung, die einen Strich zeigen koennen, sagen, was er heisst, und nennen die Einheit vor der Zahl
        $check['operation.diskFree'].findings.ok | Should -Match 'in GB: \{operation\.minFreeGB\} \(Schwelle \{@diskFreeGB\}; ein Strich heißt: kein Laufwerk als System- oder Auslagerungslaufwerk erkannt\)'
        $check['size.memoryPerSession'].findings.ok | Should -Match 'in MB: \{size\.memPerSessionMB\} \(Schwelle \{@memPerSessionMB\}; ein Strich heißt: keine Benutzersitzung\)'
        $check['profile.containerFull'].findings.ok | Should -Match 'in Prozent: \{profile\.containerMaxUsedPct\} \(Schwelle \{@containerUsedPct\}; ein Strich heißt: kein Container eingebunden\)'
        # 12, 13: Titel und Befund ohne Wertung
        $check['size.commitAboveRam'].title | Should -BeExactly 'Zugesagter Speicher im Verhältnis zum Arbeitsspeicher'
        $check['size.storageController'].findings.check | Should -Match 'Das zählt nur bei E/A-starker Last und ist kein Fehler\.$'
        # 15: mehrere Container sind ein Beispiel, kein Fehlerbild
        $check['profile.containersPerUser'].meaning | Should -Match 'entstehen zum Beispiel, wenn'
        # 16, 17: Texte des Geruests
        $Real.copy.areaReasonNoReader | Should -BeExactly 'Diese Fassung der Aufzeichnung liest den Bereich nicht.'
        $Real.values.'apps.probes' | Should -BeExactly 'Gelesene Werte der Anwendungen'
        # 18: Abbild heisst nur das Master-Image
        $check['size.pagefilePresent'].meaning | Should -Match 'ein Speicherabbild \(Dump\) zu schreiben'
    }
    It 'schreibt eine Bedeutung in hoechstens drei Saetzen, mit der Wirkung fuer die Benutzer zuerst' {       # Entscheidung ZB-R44, Korrekturrunde 1 von Task 14b
        # vier Bedingungen fuer ALLE 80 Pruefungen: hoechstens drei Saetze; ausserhalb von Klammern und Anfuehrungszeichen kein Semikolon und kein Doppelpunkt
        # (eine Uhrzeit wie 03:00 ist kein Doppelpunkt des Satzbaus); hoechstens 600 Zeichen; der erste Satz beginnt nicht mit dem Namen einer Quelle.
        # Die eine Ausnahme ist der Energiesparplan: fuenf Saetze, keine Laengengrenze.
        $names = @('Microsoft', 'Citrix', 'VMware', 'AKI', 'Broadcom') + $PracticeSources
        @($Real.checks).Count | Should -Be 80
        foreach ($c in $Real.checks) {
            $m = $c.meaning.Trim(); $plain = $m
            do { $before = $plain; $plain = [regex]::Replace($plain, '\([^()]*\)', '') } while ($plain -ne $before)
            $plain = [regex]::Replace($plain, '„[^“]*“', '')
            $sentences = @([regex]::Split($plain, '(?<=[.!?])\s+') | Where-Object { $_ })
            $power = $c.id -eq 'operation.powerPlan'
            $sentences.Count | Should -BeLessOrEqual $(if ($power) { 5 } else { 3 }) -Because $c.id
            $plain | Should -Not -Match ';' -Because $c.id
            $plain | Should -Not -Match '(?<!\d):|:(?!\d)' -Because $c.id
            if (-not $power) { $m.Length | Should -BeLessOrEqual 600 -Because $c.id }
            # die Wirkung zuerst: der erste Satz beginnt mit dem Zustand, nicht mit der Quelle
            $first = ([regex]::Split($m, '(?<=[.!?])\s+(?=[A-ZÄÖÜ„0-9])'))[0]
            foreach ($n in $names) { $first | Should -Not -Match ('^(Nach |Der Hersteller |Laut )?' + [regex]::Escape($n) + '\b') -Because "$($c.id): $n" }
            $first | Should -Not -Match '^Der Wert teilt' -Because $c.id
            # ... und nicht mit der Erklaerung, was ein Wert ist oder was sich mit ihm einstellen laesst (Nachpruefung der Korrekturrunde 1 von Task 14b)
            $first | Should -Not -Match '^(Der|Die|Das) (Wert|Eintrag|Schlüssel|Einstellung|Richtlinie) \S+ (legt|teilt|gibt|bestimmt|regelt|steuert|nennt)\b' -Because $c.id
            $first | Should -Not -Match '^(Über|Mit|Durch) \S+ lässt sich\b' -Because $c.id
            # was der erste Satz sagt, stammt von einer genannten Quelle, oder er sagt, dass es die Erlaeuterung des Katalogs ist; eine Faustregel sagt es in ihrem Text
            if ($c.kind -ne 'rule') {
                $named = @($names | Where-Object { $first -match [regex]::Escape($_) }).Count -gt 0
                ($named -or $first -match 'des Katalogs') | Should -BeTrue -Because "$($c.id): $first"
            }
        }
        # die zwei Bedeutungen, die mit der Erklaerung des Werts begannen, beginnen mit dem, was der Zustand fuer die Benutzer heisst, als Erlaeuterung des Katalogs;
        # die Seite von Citrix nennt in beiden Faellen keine Wirkung, der Nachweis sagt, worauf die Erlaeuterung fusst
        $firstOf = { param($id) ([regex]::Split((($Real.checks | Where-Object id -eq $id).meaning.Trim()), '(?<=[.!?])\s+(?=[A-ZÄÖÜ„0-9])'))[0] }
        $sids = & $firstOf 'vda.listOfSids'
        # Zusatz m von Task 14c: die Kennzeichnung ist die blosse Markierung, die Begruendung steht im Nachweis
        $sids | Should -BeExactly 'Ist ein von Hand gesetzter Wert ListOfSIDs veraltet, kann die Registrierung des VDA scheitern, und der Server bekommt dann keine neuen Sitzungen (Erläuterung des Katalogs).'
        $gp = & $firstOf 'vda.wemGpTimeout'
        $gp | Should -BeExactly ('Wartet die Gruppenrichtlinie bei der Anmeldung zu kurz auf das Netz, ist der WEM-Agent womöglich noch nicht bereit, und die Umgebung des Benutzers wird dann nicht verlässlich eingerichtet ' +
            '(Erläuterung des Katalogs, nicht von Citrix).')
        # was die Bedeutungen vorher sagten, sagen sie weiter: der Name des Werts, die Vorgabe und die Empfehlung von Citrix, die Ausnahme, und was die Pruefung nicht liest
        $gpAll = ($Real.checks | Where-Object id -eq 'vda.wemGpTimeout').meaning
        # seit Task 14c (research-wem-check.md, WEM-F14, WEM-R16): die Installation kann den Wert anlegen, ein fehlender Wert ist kein Befund
        $gpAll | Should -Match 'Die Wartezeit steht im Wert GpNetworkStartTimeoutPolicyValue, für den Citrix mindestens 30 Sekunden empfiehlt'
        $gpAll | Should -Match 'die Installation des Agenten kann ihn anlegen \(Vorgabe 120 Sekunden\), und fehlt er, ist das kein Befund'
        $sidsAll = ($Real.checks | Where-Object id -eq 'vda.listOfSids').meaning
        $sidsAll | Should -Match 'Citrix rät, den Wert ohne besonderen Grund nicht zu ändern, und nennt als Ausnahme besonders gesicherte Umgebungen, in denen dann auch die automatische Aktualisierung der Liste der Delivery Controller abgeschaltet sein muss\.'
        $sidsAll | Should -Match 'Die Prüfung stellt nur fest, dass der Wert gesetzt ist, und liest seinen Inhalt nicht\.$'
        $ProofFlat | Should -Match ([regex]::Escape('„The ListofSIDs (Security IDs) identify the trusted Controllers. VDAs attempt to register only with trusted Controllers.“'))
        $ProofFlat | Should -Match ([regex]::Escape('„The previous three keys ensure that the WEM agent service starts before the Windows logon screen appears.“'))
        # der eine Satz zu den Zeitlimits je Benutzer steht in beiden Pruefungen der Zeitlimits
        foreach ($id in 'sessions.disconnectLimit', 'sessions.idleLimit') {
            ($Real.checks | Where-Object id -eq $id).meaning | Should -Match 'Wo der Listener von Windows die Zeitlimits je Benutzer gelten lässt, gelten die Einstellungen des Benutzerkontos' -Because $id }
        # was nicht mehr in die Bedeutung passt, steht im Nachweis
        foreach ($w in 'Spectre und Meltdown', 'ein Testprogramm belegte zusätzlich 2 GB', 'Differenzdatenträger', 'für große Webanwendungen und Erweiterungen mehr', 'ihn neu aufzubauen', 'Defender war nicht Teil des Tests') {
            $ProofFlat | Should -Match ([regex]::Escape($w)) -Because $w }
    }
    It 'fuehrt die Legenden im Teil legends und laesst die Bezeichnungen schlichte Namen sein' {             # Entscheidung ZB-R49
        foreach ($p in $Real.values.PSObject.Properties) { $p.Value | Should -Not -Match '=' -Because $p.Name }
        @($Real.legends.PSObject.Properties).Count | Should -Be 34
        $Real.legends.'print.spooler' | Should -BeExactly 'Running = läuft, Stopped = beendet'
        $Real.legends.'security.defenderMode' | Should -BeExactly 'Normal = aktiv, Passive = passiv'
        $Real.legends.'maintenance.scanDay' | Should -BeExactly '0 = täglich, 1 bis 7 = Sonntag bis Samstag, 8 = nie'
        $Real.values.'security.defenderMode' | Should -BeExactly 'Betriebsart von Microsoft Defender Antivirus'; $Real.values.'print.spooler' | Should -BeExactly 'Dienst Druckwarteschlange (Spooler)'
        # der Satz fuer "trifft nicht zu" nennt die Bezeichnung ohne Legende
        $na = Get-Check @{ 'security.defenderMode' = (New-WorkerPerfHealthValue 'absent' 'notInstalled') } @{} 'security.signatureAge' $Real
        $na.grade | Should -Be 'na'
        $na.finding | Should -BeExactly ('Trifft nicht zu: der Wert „Betriebsart von Microsoft Defender Antivirus“ wird auf diesem Server nicht gelesen, weil das Produkt, zu dem er gehört, nicht installiert ist ' +
            '(bei Werten zu VMware: weil der Server keine VMware-VM ist).')
        (Get-Check @{ 'print.spooler' = (New-WorkerPerfHealthValue 'unreadable' 'rights') } @{} 'print.spoolerStopped' $Real).finding | Should -Not -Match '='
        # ein Rohwert, den ein Schritt beim Namen nennt, heisst im Katalog genau so
        $labels = @($Real.values.PSObject.Properties.Value)
        foreach ($c in $Real.checks) { foreach ($t in $c.todo) { foreach ($part in $t.text, $t.where, $t.sign) {
                    foreach ($m in [regex]::Matches($part, 'Rohwerte? („[^“]+“(, | und )?)+')) { foreach ($q in [regex]::Matches($m.Value, '„([^“]+)“')) { $labels | Should -Contain $q.Groups[1].Value -Because $c.id } } } } }
    }
    It 'fuehrt mit den Schritten der Sicherheitsprodukte und des Dienstes Windows Update zu dem, was Microsoft sagt' {      # Korrekturrunde 1 von Task 14b, Punkte 1 bis 3, 12
        $check = @{}; foreach ($c in $Real.checks) { $check[[string]$c.id] = $c }
        $steps = { param($id) @($check[$id].todo | ForEach-Object { "$($_.text) | $($_.where) | $($_.sign)" }) -join ' || ' }
        # 1: das Master-Image wird nicht angebunden; die Skripte laufen beim Start jedes bereitgestellten Servers
        $p = & $steps 'security.passiveWithoutMde'
        $p | Should -Not -Match 'Anbindung im Abbild nachholen'
        $p | Should -Match 'Onboarding-Skripte liegen im Master-Image und laufen beim Start jedes bereitgestellten Servers; das Master-Image selbst wird nicht angebunden'
        $p | Should -Match 'vom Sicherheitsteam'; $ProofFlat | Should -Match ([regex]::Escape('https://learn.microsoft.com/en-us/defender-endpoint/configure-endpoints-vdi (Stand der Seite 2026-09-22)'))
        $ProofFlat | Should -Match ([regex]::Escape('Don''t onboard the primary image'))
        # 2: beide Pruefungen unterscheiden wie die Seite: mit Anbindung passiv, ohne Anbindung abschalten oder deinstallieren; keine schickt in die andere
        $t = & $steps 'security.twoScanners'
        $t | Should -Match 'sind die Server an Microsoft Defender for Endpoint angebunden: Defender Antivirus in die passive Betriebsart setzen \(Microsoft nennt dafür den Wert ForceDefenderPassiveMode\)'
        $t | Should -Match 'sind die Server nicht angebunden: Defender Antivirus von Hand abschalten oder deinstallieren'
        $p | Should -Match 'Bleiben die Server ohne Anbindung und schützt ein anderes Produkt: Defender Antivirus von Hand abschalten oder deinstallieren'
        $p | Should -Match 'Schützt kein anderes Produkt: die erzwungene passive Betriebsart zurücknehmen'
        $check['security.twoScanners'].title | Should -BeExactly 'Defender Antivirus neben einem weiteren Schutzprodukt'
        $two = Get-Check @{ 'security.defenderMode' = 'Normal'; 'security.defenderRealTime' = $true; 'security.services' = @(@{ Name = 'WinDefend'; State = 'Running'; StartMode = 'Auto' })
            'security.filters' = @(@{ Name = 'WdFilter'; Altitude = '328010' }, @{ Name = 'CyProtectDrv64'; Altitude = '388510' }) } @{} 'security.twoScanners' $Real
        $two.grade | Should -Be 'check'; $two.finding | Should -Match 'Erkannte Schutzprodukte: Microsoft Defender, Arctic Wolf Aurora Endpoint Protection \(ein Strich heißt: nicht gelesen\)\.$'
        # 3: der Dienst Windows Update wird nur abgeschaltet, wenn die Signaturen auf einem anderen Weg kommen; die Bedeutung nennt die andere Pruefung
        $u = & $steps 'maintenance.updateServiceEnabled'
        $u | Should -Match 'woher Defender Antivirus seine Signaturen bezieht: Kommen sie von Microsoft Update, braucht Defender Antivirus dafür nach Microsoft die Dienste Windows Update und BITS'
        $u | Should -Match 'Nur wenn die Server keine Updates selbst laden sollen und die Signaturen auf einem anderen Weg kommen, den Dienst im Abbild deaktivieren'
        $check['maintenance.updateServiceEnabled'].meaning | Should -Match 'ohne ihn meldet die Prüfung „Alter der Signaturen von Defender Antivirus“'
        (& $steps 'security.signatureAge') | Should -Match 'Kommen sie von Microsoft Update, braucht Defender Antivirus dafür nach Microsoft die Dienste Windows Update und BITS'
        (& $steps 'security.signatureAge') | Should -Match 'das Alter der Signaturen ist größer als die Laufzeit seit dem letzten Start'
        $ProofFlat | Should -Match ([regex]::Escape('https://learn.microsoft.com/en-us/defender-endpoint/security-intelligence-update-tshoot'))
        # 12 (ZB-R48): die Ausschluesse des WEM-Agenten stuetzen sich auf den Artikel von Citrix; Carl Stalhood bleibt im Text und steht im Nachweis als zweite Quelle
        $w = $check['security.wemExclusions']; $w.kind | Should -Be 'vendor'; $w.source.vendor | Should -Be 'Citrix'; $w.source.title | Should -Match 'CTX696648'; $w.meaning | Should -Match 'Carl Stalhood'
        foreach ($id in 'security.wemExclusions', 'security.citrixExclusions') { $check[$id].source.date | Should -Be '2026-05-25' -Because $id }
        $Proof | Should -Match '\| Citrix \| Endpoint Security, Antivirus, and Antimalware Best Practices \(CTX696648\) \| \S+ \| 2026-05-25 \|'
        @($Real.checks | Where-Object kind -eq 'vendor').Count | Should -Be 31; @($Real.checks | Where-Object kind -eq 'practice').Count | Should -Be 14; @($Real.checks | Where-Object kind -eq 'rule').Count | Should -Be 35
    }
    It 'sagt im Ereignisbild nur, was die gelesenen Protokolle hergeben' {                                   # Korrekturrunde 1 von Task 14b, Punkte 4, 5, 19
        $check = @{}; foreach ($c in $Real.checks) { $check[[string]$c.id] = $c }
        $day = 86400000L
        $logs = { param([double[]]$Days) $names = 'Application', 'System', 'Microsoft-Windows-PrintService/Admin'
            @(for ($i = 0; $i -lt $Days.Count; $i++) { @{ Log = $names[$i]; Present = $true; Enabled = $true; MaxSizeMB = 20; FileSizeMB = 1; Records = 5; Mode = 'Circular'; Full = $false; Oldest = $ReadMs - [long]($Days[$i] * $day) } }) }
        # der Server laeuft laenger als der Rueckblick, die Protokolle reichen neun Tage zurueck: der Rueckblick von sieben Tagen ist ganz abgedeckt, und seit Task 14s (ZB-R52)
        # meldet die Pruefung das nicht mehr; reichen die Protokolle nur bis zu einem Start im Rueckblick, behauptet der Befund nichts anderes
        $since = $check['events.sinceBoot']; $since.title | Should -BeExactly 'Reichweite der Ereignisprotokolle vor den letzten Start'
        (Get-Check @{ 'operation.lastBoot' = $ReadMs - 10 * $day; 'events.logs' = (& $logs 9, 9, 9) } @{} 'events.sinceBoot' $Real).grade | Should -Be 'ok'
        $x = Get-Check @{ 'operation.lastBoot' = $ReadMs - 2 * $day; 'events.logs' = (& $logs 1.9, 1.9, 1.9) } @{} 'events.sinceBoot' $Real
        $x.grade | Should -Be 'check'
        $x.finding | Should -BeExactly ('Kein gelesenes Ereignisprotokoll reicht vor den letzten Start des Servers zurück (13.01.2026 08:00). Liegt dieser Start innerhalb des Rückblicks (eingestellte Länge in Tagen: 7), ' +
            'zeigen Rückblick und Ereignisbild nur die Zeit seit dem Start. Auf einem nicht persistenten Server ohne beständiges Laufwerk ist das der Normalfall. Das ist ein Hinweis aus der Praxis, kein Fehler.')
        $since.findings.check | Should -Not -Match 'deshalb nur die Zeit seit diesem Start'; $since.meaning | Should -Not -Match 'Auf diesem Server reichen'
        $since.meaning | Should -Match '^Reichen die Ereignisprotokolle nur bis zum letzten Start, zeigen Rückblick und Ereignisbild nichts von davor'
        # der Start liegt im Rueckblick, die Protokolle reichen davor zurueck, ein ruhiges Protokoll hat seinen einzigen Eintrag vor zweieinhalb Tagen:
        # die Reichweite ist in Ordnung, die Abdeckung meldet, ohne fehlende Tage oder ein zu kleines Protokoll zu behaupten, und die Zaehlungen leugnen die Tage vor dem Start nicht
        $quiet = @{ 'operation.lastBoot' = $ReadMs - 2 * $day; 'events.logs' = (& $logs 30, 30, 2.5) }
        $crash = @{ EventsBefore = @((New-Ev 1 'crash'), (New-Ev 3 'crash'), (New-Ev 5 'crash')) }
        (Get-Check $quiet @{} 'events.sinceBoot' $Real).grade | Should -Be 'ok'
        $cov = Get-Check $quiet @{} 'events.coverage' $Real; $cov.grade | Should -Be 'check'
        $cov.finding | Should -BeExactly ('Mindestens ein ausgewertetes Ereignisprotokoll hat keinen Eintrag aus den ersten Tagen des Rückblicks (Tage ohne Eintrag: 5); der letzte Start (13.01.2026 08:00) erklärt das nicht. ' +
            'Entweder ist das Protokoll zu klein und hat ältere Einträge überschrieben, oder es hat in dieser Zeit nichts aufgezeichnet.')
        $check['events.coverage'].findings.check | Should -Not -Match 'am Anfang fehlen Tage'
        $covSteps = @($check['events.coverage'].todo | ForEach-Object { "$($_.text) $($_.sign)" }) -join ' '
        $covSteps | Should -Match 'Liegt seine Größe \(FileSizeMB\) an der Höchstgröße \(MaxSizeMB\), wurde überschrieben'; $covSteps | Should -Match 'Ein Protokoll, das seine Höchstgröße erreicht hat, vergrößern'
        $cr = Get-Check $quiet $crash 'events.crashes' $Real; $cr.grade | Should -Be 'check'
        $cr.finding | Should -BeExactly ('Tage mit Abstürzen im Rückblick: 3, die Schwelle von 3 ist erreicht. Letzter Start des Servers: 13.01.2026 08:00 (ein Strich heißt: nicht gelesen). Reichen die Ereignisprotokolle nicht vor diesen Start zurück ' +
            '(das zeigt die Prüfung „Reichweite der Ereignisprotokolle vor den letzten Start“), zählt der Rückblick nur die Zeit seither.')
        foreach ($id in 'events.crashes', 'events.storage', 'events.fileserver') { foreach ($g in 'ok', 'check') {
                $check[$id].findings.$g | Should -Not -Match 'reicht der Rückblick höchstens bis zum letzten Start zurück' -Because "$id $g"
                $check[$id].findings.$g | Should -Match 'Reichen die Ereignisprotokolle nicht vor diesen Start zurück \(das zeigt die Prüfung „Reichweite der Ereignisprotokolle vor den letzten Start“\)' -Because "$id $g" } }
        # 5: die Ereignisse heissen wie im gemessenen Teil des Berichts; "Speicher" bleibt der Arbeitsspeicher
        $check['events.storage'].title | Should -BeExactly 'Datenträgerfehler im Rückblick'; $Real.values.'events.storageCount' | Should -BeExactly 'Datenträgerfehler im Rückblick'
        $Texts['companion.system.storage'] | Should -Be 'Datenträgerfehler'; (Get-Content $CatFile -Raw) | Should -Not -Match 'Speicherereignis|Team für den Speicher\b'
        (Get-Check @{} @{ EventsBefore = @((New-Ev 1 'system' 'storage')) } 'events.storage' $Real).finding | Should -Match '^Datenträgerfehler im Rückblick \(Meldungen von Windows über Fehler oder Verzögerungen beim Zugriff auf ein Laufwerk\): 1\.'
        # 19 (ZB-R35): die drei dauerhaften Hinweise sagen im Befund, dass sie Hinweise sind
        foreach ($id in 'maintenance.updateServiceEnabled', 'print.operationalLogOff', 'events.sinceBoot') { $check[$id].findings.check | Should -Match ' Das ist ein Hinweis aus der Praxis, kein Fehler\.$' -Because $id }
    }
    It 'laesst zuerst nachsehen und nennt im Befund, was gefunden wurde' {                                    # Korrekturrunde 1 von Task 14b, Punkte 6 bis 9, 15 bis 18, 21, 22
        $check = @{}; foreach ($c in $Real.checks) { $check[[string]$c.id] = $c }
        $step = { param($id, $n) $s = @($check[$id].todo)[$n]; "$($s.text) | $($s.where) | $($s.sign)" }
        # 6: die Richtlinie, die Treiber wirklich isoliert, und erst nach einem Test
        (& $step 'print.driversInSpooler' 1) | Should -Match 'Override print driver execution compatibility setting reported by print driver.*PrintDriverIsolationOverrideCompat.*vorher auf einem Testserver prüfen'
        (& $step 'print.driversInSpooler' 1) | Should -Not -Match 'über die Richtlinie zur Treiberisolierung'
        # 7: welche Treiber gebraucht werden, zeigt die Zuordnung, nicht das Master-Image
        (& $step 'print.driverCount' 0) | Should -Match 'für welche Druckermodelle den Benutzern noch Drucker zugeordnet werden.*Zuordnungswerkzeugs \(zum Beispiel PrinTaurus SmartSpread\).*Druckserver'
        (& $step 'print.driverCount' 0) | Should -Not -Match 'Druckverwaltung im Master-Image'; (& $step 'print.driverCount' 1) | Should -Match 'nicht mehr über der Schwelle'
        (& $step 'print.driverCount' 2) | Should -Match 'auf einem Testserver mit diesem Treiber nacheinander viele Drucker anlegen und wieder löschen'
        # 8: nachsehen steht vor aendern
        (& $step 'print.mappingClientSupported' 0) | Should -Match '^Zuerst prüfen, ob der Client zum selben PrinTaurus-Release gehört wie die Komponenten auf den Druckservern'
        (& $step 'print.mappingClientSupported' 1) | Should -Match '^Den Client im Abbild auf das Release der Druckserver bringen, mindestens 6\.2'
        @($check['print.operationalLogOff'].todo).Count | Should -Be 2; (& $step 'print.operationalLogOff' 0) | Should -Match '^Nachsehen, ob das Protokoll schon im Abbild ausgeschaltet ist'
        (& $step 'print.operationalLogOff' 1) | Should -Not -Match 'Einstellung der Windows-Registrierung'
        (& $step 'operation.powerPlan' 0) | Should -Match '^Zuerst mit dem Hypervisor-Team klären.*das Betriebssystem der Hosts \(der Hypervisor\)'; (& $step 'operation.powerPlan' 1) | Should -Match '^Den Energiesparplan auf „Höchstleistung“ stellen'
        (& $step 'vda.controllerCount' 0) | Should -Match '^Nachsehen, ob der eine Eintrag eine Controller-Gruppe mit mehreren Controllern ist: Dann ist nichts zu tun'
        # 9: seit Task 14s (ZB-R50) werden der globale Schalter von Windows und die Einstellung des Netzwerkadapters gelesen
        $rss = $check['network.rss']
        foreach ($g in 'ok', 'check') { $rss.findings.$g | Should -Match 'in den Einstellungen des Netzwerkadapters abgeschaltet' -Because $g; $rss.findings.$g | Should -Not -Match 'liest das Zustandsbild nicht' -Because $g }
        $rss.meaning | Should -Match 'global in Windows und am Netzwerkadapter, und das Zustandsbild liest beide'
        (& $step 'network.rss' 0) | Should -Match 'Rohwerte „Receive Side Scaling global in Windows“'; (& $step 'network.rss' 1) | Should -Match 'dafür sorgen, dass das Versiegeln es nicht wieder abschaltet'
        # 15, 16
        (& $step 'vda.listOfSids' 0) | Should -Match 'Einstellung „Controller SIDs“ der Citrix-Richtlinie'
        foreach ($id in 'network.dnsCount', 'network.dnsPublic') { $check[$id].source.title | Should -BeExactly 'Best practices for DNS client settings in Windows Server' -Because $id }
        $ProofFlat | Should -Not -Match 'früheren Titel'; $ProofFlat | Should -Not -Match 'common-exclusion-mistakes-microsoft-defender-antivirus'
        $ProofFlat | Should -Match ([regex]::Escape('https://learn.microsoft.com/en-us/defender-endpoint/defender-endpoint-exclusions-common-mistakes'))
        $check['print.driverCount'].meaning | Should -Match 'den Citrix-Universaltreiber oder die eigenen Windows-Treiber der Drucker zu nutzen \(„Windows-native drivers“\)'
        $check['maintenance.tasksInWorkHours'].meaning | Should -Match 'Gezählt werden nach einer Festlegung des Katalogs nur Aufgaben außerhalb des Ordners \\Microsoft\\\. Die Wartungsaufgaben von Windows selbst laufen nach Microsoft erst im Leerlauf'
        $check['maintenance.sessionTriggerTasks'].meaning | Should -Not -Match 'keine geplanten Aufgaben'
        # 17, 18: der Befund nennt die gelesenen Werte, und jeder Strich und jedes Kennwort hat seine Legende im Befund
        (Get-Check @{ 'print.queueCount' = 12; 'sessions.list' = @() } @{} 'print.queueCount' $Real).finding |
            Should -BeExactly 'Druckwarteschlangen beim Lesen: 12, Benutzersitzungen: 0, Warteschlangen je Sitzung: 12, mehr als die Schwelle von 10 (ohne Sitzung steht dort die Zahl aller Warteschlangen, und die Warteschlangen des Servers selbst sind mitgezählt).'
        (Get-Check @{ 'network.domainMember' = $true; 'network.timeType' = 'NTP' } @{} 'network.timeSource' $Real).finding |
            Should -BeExactly 'Der Server ist Mitglied einer Domäne, bezieht seine Zeit aber nicht aus der Domäne (eingestellte Art: NTP; NTP = feste Zeitquellen, NoSync = kein Abgleich, ein Strich heißt: keine Art eingetragen).'
        (Get-Check @{ 'maintenance.scanDay' = 0; 'maintenance.scanTime' = '12:30' } @{} 'maintenance.defenderScanInWorkHours' $Real).finding | Should -Match 'Eingestellter Tag: 0 \(0 = täglich, 1 bis 7 = Sonntag bis Samstag, 8 = nie\); eingestellte Zeit: 12:30 Uhr; Startzeit des Schnellscans: –; Verzögerung in Minuten: –;'
        (Get-Check @{ 'maintenance.updateOptions' = 4; 'maintenance.updateDay' = 3; 'maintenance.updateHour' = 10 } @{} 'maintenance.updateInstallInWorkHours' $Real).finding | Should -Match 'eingestellter Tag 3, eingestellte Stunde 10 \(Tag: 0 = täglich, 1 bis 7 = Sonntag bis Samstag; ein Strich heißt: nicht eingestellt'
        $check['security.citrixExclusions'].findings.check | Should -Match 'zeigt der Rohwert „Ausgeschlossene Prozesse“\. Verbirgt Defender Antivirus'; (& $step 'security.citrixExclusions' 0) | Should -Match 'Rohwert „Ausgeschlossene Prozesse“'
        (Get-Check @{} @{} 'print.spoolerStopped' $Real).finding | Should -Match 'gelesener Zustand: –; Running = läuft, Stopped = beendet, ein Strich heißt: Dienst nicht gefunden'
        (Get-Check @{} @{} 'maintenance.updateServiceEnabled' $Real).finding | Should -Match 'gelesener Starttyp: –; Auto = automatisch, Manual = manuell, ein Strich heißt: Dienst nicht gefunden'
        (Get-Check @{ 'maintenance.scanType' = 2 } @{} 'maintenance.defenderFullScan' $Real).finding | Should -Match 'Tag: –; 0 = täglich, 1 bis 7 = Sonntag bis Samstag, 8 = nie; ein Strich heißt: nicht eingestellt'
        (Get-Check @{ 'network.smb1' = 'System' } @{} 'network.smb1' $Real).finding | Should -Match 'gelesener Starttyp: System; Boot und System = beim Start von Windows'
        (Get-Check @{ 'print.isolationExecution' = 1 } @{} 'print.isolationOff' $Real).finding | Should -Match 'gelesener Wert: 1; 0 = Isolierung aus, 1 = Isolierung eingeschaltet'
        # 21: Schritte, denen man folgen kann
        (& $step 'network.smb1' 0) | Should -Match 'keine solche Verbindung beim Lesen heißt nicht, dass kein Gerät SMBv1 braucht'
        (& $step 'events.sinceBoot' 0) | Should -Match 'Rohwerte „Lokale Laufwerke“ und „Beständiger Datenort der Bereitstellung“'
        (& $step 'maintenance.updateInstallInWorkHours' 1) | Should -Match 'abschalten oder aus der Arbeitszeit legen'
        # 22: Stellen im Bericht heissen wie im Bericht
        foreach ($id in 'print.driversInSpooler', 'print.driverCount', 'print.kernelModeV2') { (& $step $id 0) | Should -Match 'Expertenansicht, Reiter „Drucken“: Treiberliste' -Because $id }
        (& $step 'print.driversInSpooler' 0) | Should -Match 'Spalte „Isolierung“'
        foreach ($id in 'events.crashes', 'events.storage', 'events.fileserver') { (& $step $id 0) | Should -Match 'im Bericht der Bereich „Vor der Messung“ \(Rückblick\)' -Because $id }
        (Get-Content $CatFile -Raw) | Should -Not -Match 'im Bericht die Liste der Druckertreiber|Bericht, Rückblick|Bericht, Verlauf'
    }
    It 'nennt eine Sache mit einem Namen' {                                                                   # Korrekturrunde 1 von Task 14b, Punkt 20
        $all = Get-Content $CatFile -Raw
        # der Dienst Druckwarteschlange, die Treiber, Schutzprodukte, das Cache-Laufwerk, der Netzwerkadapter, der Server
        foreach ($w in 'Druckdienst', 'Spooler-Dienst', 'Universal Printing Driver', 'universellen Druckertreiber', 'Virenschutz', 'Schutzsoftware', 'Antivirenprodukt', 'Cache-Datenträger',
            'Netzwerkschnittstelle', '\bSchnittstelle', 'Adaptertyp', '\bRechner\b', '\bRechners\b') { $all | Should -Not -MatchExactly $w -Because $w }
        $all | Should -Match 'Dienst Druckwarteschlange \(Spooler\)'; $all | Should -Match 'im Prozess des Dienstes Druckwarteschlange'; $all | Should -Match 'HP Universal Print Driver'; $all | Should -Match 'Citrix-Universaltreiber'
        # das Produkt heisst nie nur "Defender": Microsoft Defender Antivirus oder Defender Antivirus, und Microsoft Defender for Endpoint
        $all | Should -Not -MatchExactly '(?<![A-Za-z])Defender(?! Antivirus| for Endpoint|-Portal)'
        # je Pruefung steht der Name einmal so, wie Microsoft ihn schreibt, und zwar bei der ersten Nennung im Befund oder, wo der Befund das Produkt nicht nennt, im uebrigen Text; danach "Defender Antivirus"
        foreach ($c in $Real.checks) {
            $rest = "$($c.meaning) $(@($c.todo | ForEach-Object { "$($_.text) $($_.where) $($_.sign)" }) -join ' ')"
            foreach ($g in 'ok', 'check', 'act') {
                if (-not $c.findings.$g) { continue }
                $text = "$($c.findings.$g) $rest"
                if ($text -notmatch 'Defender Antivirus') { continue }
                ([regex]::Matches($text, 'Microsoft Defender Antivirus')).Count | Should -Be 1 -Because "$($c.id) $g"
                $text.IndexOf('Microsoft Defender Antivirus') | Should -BeLessThan $text.IndexOf('Defender Antivirus') -Because "$($c.id) $g"
            }
        }
        $ProofFlat | Should -Not -Match 'Universal Printing Driver'
    }
}
Describe 'Fakten nach der Quellenpruefung (Task 14s)' {
    BeforeAll {
        $script:Real = Read-WorkerPerfHealthCatalogue (Join-Path $PSScriptRoot '../src/health.de.json') @(Read-WorkerPerfHealthApps (Join-Path $PSScriptRoot '../src/apps.json'))
        $script:Day = 86400000L
        $script:Vm = @{ 'size.model' = 'VMware, Inc. VMware7,1' }
    }
    It 'nimmt fuer den geplanten Scan den wirksamen Beginn: eingestellte Zeit plus Verzoegerung, verbreitert um das Zufallsfenster' {   # Punkt 3
        $scan = { param([hashtable]$v) (Get-Facts $v)['maintenance.scanInWorkHours'] }
        # Arbeitszeit 7 bis 18 Uhr; ohne Angabe 120 Minuten Verzoegerung und 30 Minuten Zufallsfenster je Richtung
        (& $scan @{ 'maintenance.scanDay' = 0; 'maintenance.scanTime' = '02:00' }).Value | Should -BeFalse                                   # 03:30 bis 04:30
        (& $scan @{ 'maintenance.scanDay' = 0; 'maintenance.scanTime' = '05:00' }).Value | Should -BeTrue                                    # 06:30 bis 07:30
        (& $scan @{ 'maintenance.scanDay' = 0; 'maintenance.scanTime' = '12:30'; 'maintenance.scanOffset' = 0; 'maintenance.scanRandomize' = $false }).Value | Should -BeTrue
        (& $scan @{ 'maintenance.scanDay' = 0; 'maintenance.scanTime' = '23:30' }).Value | Should -BeFalse                                   # 01:00 bis 02:00 am Tag danach
        (& $scan @{ 'maintenance.scanDay' = 0; 'maintenance.scanTime' = '16:30' }).Value | Should -BeFalse                                   # 18:00 bis 19:00: das Ende der Arbeitszeit zaehlt nicht dazu
        # das Fenster folgt dem gelesenen Wert; ohne zufaellige Startzeit wird es nicht verbreitert
        (& $scan @{ 'maintenance.scanDay' = 0; 'maintenance.scanTime' = '04:00'; 'maintenance.scanRandomize' = $false }).Value | Should -BeFalse      # genau 06:00
        (& $scan @{ 'maintenance.scanDay' = 0; 'maintenance.scanTime' = '04:00'; 'maintenance.scanRandomWindow' = 90 }).Value | Should -BeTrue           # 04:30 bis 07:30
        (& $scan @{ 'maintenance.scanDay' = 0; 'maintenance.scanTime' = '04:00'; 'maintenance.scanRandomize' = $false; 'maintenance.scanRandomWindow' = 90 }).Value | Should -BeFalse
        (& $scan @{ 'maintenance.scanDay' = 0; 'maintenance.scanTime' = '02:00'; 'maintenance.scanOffset' = 300 }).Value | Should -BeTrue                # 06:30 bis 07:30
        # der Tag des Scans: Freitag 23:30 endet am Samstag, Sonntag 23:30 mit 10 Stunden Verzoegerung beginnt am Montag um 09:30, Samstag 12:30 nie in der Arbeitszeit
        (& $scan @{ 'maintenance.scanDay' = 6; 'maintenance.scanTime' = '23:30' }).Value | Should -BeFalse
        (& $scan @{ 'maintenance.scanDay' = 1; 'maintenance.scanTime' = '23:30'; 'maintenance.scanOffset' = 600 }).Value | Should -BeTrue
        (& $scan @{ 'maintenance.scanDay' = 7; 'maintenance.scanTime' = '12:30' }).Value | Should -BeFalse
        (& $scan @{ 'maintenance.scanDay' = 2; 'maintenance.scanTime' = '00:10'; 'maintenance.scanOffset' = 0 }).Value | Should -BeFalse              # Sonntag 23:40 bis Montag 00:40
        (& $scan @{ 'maintenance.scanDay' = 8; 'maintenance.scanTime' = '12:30' }).Value | Should -BeFalse
        # die taegliche Zeit des Schnellscans zaehlt, wo sie gesetzt ist, an jedem Tag
        (& $scan @{ 'maintenance.scanDay' = 8; 'maintenance.scanTime' = '02:00'; 'maintenance.quickScanTime' = '06:00' }).Value | Should -BeTrue          # 07:30 bis 08:30
        (& $scan @{ 'maintenance.scanDay' = 0; 'maintenance.scanTime' = '02:00'; 'maintenance.quickScanTime' = '02:00' }).Value | Should -BeFalse
        # ohne gelesene Zeit des geplanten Scans: wie bisher nicht pruefbar; ein nicht lesbarer Teil des Fensters macht den Fakt nicht lesbar
        $f = & $scan @{ 'maintenance.scanDay' = 0 }; $f.State | Should -Be 'absent'; $f.Reason | Should -Be ''
        $f = & $scan @{ 'maintenance.scanDay' = 0; 'maintenance.scanTime' = '02:00'; 'maintenance.scanOffset' = (New-WorkerPerfHealthValue 'unreadable' 'timeout') }
        $f.State | Should -Be 'unreadable'; $f.Reason | Should -Be 'timeout'
        $f = & $scan @{ 'maintenance.scanDay' = (New-WorkerPerfHealthValue 'absent' 'notInstalled') }; $f.State | Should -Be 'absent'; $f.Reason | Should -Be 'notInstalled'
        # Korrekturrunde 1, Punkt 2: der Beginn wird in eine Woche zurueckgerechnet; Montag 02:00 plus zwei Wochen und 8 Stunden ist Montag 09:30 bis 10:30
        (& $scan @{ 'maintenance.scanDay' = 2; 'maintenance.scanTime' = '02:00'; 'maintenance.scanOffset' = (2 * 7 * 1440 + 480) }).Value | Should -BeTrue
        (& $scan @{ 'maintenance.scanDay' = 2; 'maintenance.scanTime' = '02:00'; 'maintenance.scanOffset' = (2 * 7 * 1440 + 480); 'maintenance.scanRandomize' = $false }).Value | Should -BeTrue
        (& $scan @{ 'maintenance.scanDay' = 1; 'maintenance.scanTime' = '02:00'; 'maintenance.scanOffset' = (3 * 7 * 1440 + 480) }).Value | Should -BeFalse      # Sonntag 09:30
        Test-WorkerPerfHealthScanWindow 7 0 (7 * 1440) @{ WorkStart = 7; WorkEnd = 18 } | Should -BeTrue                                                        # eine Woche lang: sofort
        # Korrekturrunde 1, Punkt 3: erst der Tag und der Schnellscan, dann das Fenster, und nur fuer einen Scan, den es gibt
        $bad = New-WorkerPerfHealthValue 'unreadable' 'timeout'
        foreach ($part in 'maintenance.scanOffset', 'maintenance.scanRandomize', 'maintenance.scanRandomWindow') {
            $f = & $scan @{ 'maintenance.scanDay' = 8; 'maintenance.scanTime' = '02:00'; $part = $bad }; $f.State | Should -Be 'read' -Because $part; $f.Value | Should -BeFalse -Because $part
        }
        (& $scan @{ 'maintenance.quickScanTime' = '06:00' }).Value | Should -BeTrue                                                                              # kein Tag des geplanten Scans
        $f = & $scan @{ 'maintenance.quickScanTime' = '02:00' }; $f.State | Should -Be 'read'; $f.Value | Should -BeFalse
        $f = & $scan @{ 'maintenance.scanDay' = $bad; 'maintenance.quickScanTime' = '02:00' }; $f.State | Should -Be 'unreadable'; $f.Reason | Should -Be 'timeout'
        (& $scan @{ 'maintenance.scanDay' = $bad; 'maintenance.quickScanTime' = '06:00' }).Value | Should -BeTrue
        $f = & $scan @{ 'maintenance.quickScanTime' = '06:00'; 'maintenance.scanOffset' = $bad }; $f.State | Should -Be 'unreadable'; $f.Reason | Should -Be 'timeout'
        $f = & $scan @{}; $f.State | Should -Be 'absent'; $f.Reason | Should -Be ''                                                                             # weder Tag noch Schnellscan
        $f = & $scan @{ 'maintenance.scanDay' = 8; 'maintenance.quickScanTime' = $bad }; $f.State | Should -Be 'unreadable'; $f.Reason | Should -Be 'timeout'      # Schnellscan unbekannt
        (& $scan @{ 'maintenance.scanDay' = 0; 'maintenance.scanTime' = '05:00'; 'maintenance.quickScanTime' = $bad }).Value | Should -BeTrue
        # gerendert: der Befund nennt den wirksamen Beginn
        $x = Get-Check @{ 'maintenance.scanDay' = 0; 'maintenance.scanTime' = '05:00'; 'maintenance.scanOffset' = 120 } @{} 'maintenance.defenderScanInWorkHours' $Real
        $x.grade | Should -Be 'check'; $x.finding | Should -Match 'wirksame Beginn'; $x.finding | Should -Match 'eingestellte Zeit: 05:00 Uhr'
        $x = Get-Check @{ 'maintenance.scanDay' = 0; 'maintenance.scanTime' = '02:00' } @{} 'maintenance.defenderScanInWorkHours' $Real
        $x.grade | Should -Be 'ok'; $x.finding | Should -Match 'wirksame Beginn'
    }
    It 'nennt die Zeitlimits nicht pruefbar, wo der Listener die Zeitlimits je Benutzer gelten laesst' {   # Punkt 4
        $lim = { param($terminal, $policy, $min) [ordered]@{ Terminal = $terminal; IdleLimitMin = $min; DisconnectedLimitMin = $min; ActiveLimitMin = 0; BrokenAction = 0; FromPolicy = $true; TimeLimitPolicy = $policy } }
        $f = Get-Facts @{ 'sessions.limits' = @((& $lim 'ICA-CGP' 1 240), (& $lim 'RDP-Tcp' 1 0)) }
        $f['sessions.disconnectLimitMin'].Value | Should -Be 240; $f['sessions.idleLimitMin'].Value | Should -Be 240
        # ein Listener je Benutzer macht beide Fakten nicht pruefbar, auch neben einem Listener mit einem Zeitlimit des Servers (Entscheidung ZB-R55)
        foreach ($case in @(@((& $lim 'ICA-CGP' 0 240)), @((& $lim 'ICA-CGP' 0 0)), @((& $lim 'ICA-CGP' 0 0), (& $lim 'RDP-Tcp' 1 0)),
                @((& $lim 'RDP-Tcp' 0 30), (& $lim 'ICA-CGP' 1 180)), @((& $lim 'ICA-CGP' 1 180), (& $lim 'RDP-Tcp' 0 0)))) {
            $f = Get-Facts @{ 'sessions.limits' = $case }
            foreach ($id in 'sessions.disconnectLimitMin', 'sessions.idleLimitMin') { $f[$id].State | Should -Be 'unreadable' -Because $id; $f[$id].Reason | Should -BeExactly 'perUser' -Because $id }
        }
        # ein Eintrag einer frueheren Fassung ohne das Feld: wie bisher
        (Get-Facts @{ 'sessions.limits' = @(@{ Terminal = 'ICA-CGP'; IdleLimitMin = 0; DisconnectedLimitMin = 90 }) })['sessions.disconnectLimitMin'].Value | Should -Be 90
        (Get-Facts @{ 'sessions.limits' = @(@{ Terminal = 'ICA-CGP'; IdleLimitMin = 0; DisconnectedLimitMin = 0 }) })['sessions.disconnectLimitMin'].State | Should -Be 'absent'
        # gerendert: beide Pruefungen sind im Fall je Benutzer nicht pruefbar, mit den Werten des Listeners wie bisher
        $perUser = 'Ein Wert, den die Prüfung braucht, liegt nicht vor: ein Listener lässt die Zeitlimits je Benutzer gelten; diese Einstellungen der Benutzerkonten liest das Zustandsbild nicht.'
        foreach ($id in 'sessions.disconnectLimit', 'sessions.idleLimit') {
            $x = Get-Check @{ 'sessions.limits' = @((& $lim 'ICA-CGP' 0 0)) } @{} $id $Real
            $x.grade | Should -Be 'unknown' -Because $id; $x.finding | Should -BeExactly $perUser -Because $id
            $x = Get-Check @{ 'sessions.limits' = @((& $lim 'ICA-CGP' 0 0), (& $lim 'RDP-Tcp' 1 30)) } @{} $id $Real                                  # gemischte Listener
            $x.grade | Should -Be 'unknown' -Because $id; $x.finding | Should -BeExactly $perUser -Because $id
            (Get-Check @{ 'sessions.limits' = @((& $lim 'ICA-CGP' 1 0)) } @{} $id $Real).grade | Should -Be 'check' -Because $id
            (Get-Check @{ 'sessions.limits' = @((& $lim 'ICA-CGP' 1 120)) } @{} $id $Real).grade | Should -Be 'ok' -Because $id
        }
        $Real.legends.'sessions.limits' | Should -Match 'TimeLimitPolicy: 0 = '
    }
    It 'nennt die Installation von Updates ohne Richtlinie nicht pruefbar und nimmt bei Option 4 ohne Stunde 03:00' {   # Punkt 5
        $up = { param([hashtable]$v) (Get-Facts $v)['maintenance.updateInWorkHours'] }
        $f = & $up @{}; $f.State | Should -Be 'absent'; $f.Reason | Should -Be ''                                                      # keine Richtlinie
        (& $up @{ 'maintenance.updateOptions' = 4 }).Value | Should -BeFalse                                                          # taeglich 03:00
        (& $up @{ 'maintenance.updateOptions' = 4; 'maintenance.updateDay' = 0 }).Value | Should -BeFalse
        (& $up @{ 'maintenance.updateOptions' = 4; 'maintenance.updateDay' = 0; 'maintenance.updateHour' = 3 }).Value | Should -BeFalse
        (& $up @{ 'maintenance.updateOptions' = 4; 'maintenance.updateDay' = 0; 'maintenance.updateHour' = 10 }).Value | Should -BeTrue
        (& $up @{ 'maintenance.updateOptions' = 4; 'maintenance.updateHour' = 10 }).Value | Should -BeTrue                            # ohne Tag: taeglich
        (& $up @{ 'maintenance.updateOptions' = 3; 'maintenance.updateDay' = 0; 'maintenance.updateHour' = 10 }).Value | Should -BeFalse    # nur herunterladen
        $f = & $up @{ 'maintenance.updateOptions' = (New-WorkerPerfHealthValue 'unreadable' 'rights') }; $f.State | Should -Be 'unreadable'; $f.Reason | Should -Be 'rights'
        $f = & $up @{ 'maintenance.updateOptions' = 4; 'maintenance.updateHour' = (New-WorkerPerfHealthValue 'unreadable' 'timeout') }; $f.Reason | Should -Be 'timeout'
        # gerendert
        $x = Get-Check @{} @{} 'maintenance.updateInstallInWorkHours' $Real; $x.grade | Should -Be 'ok'; $x.finding | Should -Match 'Ohne Richtlinie ist der Zeitpunkt der Installation nicht bekannt'
        (Get-Check @{ 'maintenance.updateOptions' = 4 } @{} 'maintenance.updateInstallInWorkHours' $Real).grade | Should -Be 'ok'
        (Get-Check @{ 'maintenance.updateOptions' = 4; 'maintenance.updateDay' = 0; 'maintenance.updateHour' = 10 } @{} 'maintenance.updateInstallInWorkHours' $Real).grade | Should -Be 'check'
    }
    It 'nennt RSS abgeschaltet, wenn es global oder an einem VMXNET3-Adapter aus ist, und nie in Ordnung ohne den globalen Zustand' {   # Punkt 6
        $on = @(@{ Description = 'vmxnet3 Ethernet Adapter'; Enabled = $true }); $off = @(@{ Description = 'vmxnet3 Ethernet Adapter'; Enabled = $false })
        $rss = { param([hashtable]$v) (Get-Facts ($Vm + $v))['network.rssDisabled'] }
        (& $rss @{ 'network.rss' = $on; 'network.rssGlobal' = 'enabled' }).Value | Should -BeFalse
        (& $rss @{ 'network.rss' = $on; 'network.rssGlobal' = 'disabled' }).Value | Should -BeTrue
        (& $rss @{ 'network.rss' = $off; 'network.rssGlobal' = 'enabled' }).Value | Should -BeTrue
        (& $rss @{ 'network.rss' = $off; 'network.rssGlobal' = (New-WorkerPerfHealthValue 'unreadable' 'rights') }).Value | Should -BeTrue
        $f = & $rss @{ 'network.rss' = $on; 'network.rssGlobal' = (New-WorkerPerfHealthValue 'unreadable' 'rights') }; $f.State | Should -Be 'unreadable'; $f.Reason | Should -Be 'rights'
        $f = & $rss @{ 'network.rss' = $on }; $f.State | Should -Be 'unreadable'; $f.Reason | Should -Be ''                          # die Klasse fehlt
        $f = & $rss @{ 'network.rss' = (New-WorkerPerfHealthValue 'unreadable' 'timeout'); 'network.rssGlobal' = 'enabled' }; $f.State | Should -Be 'unreadable'; $f.Reason | Should -Be 'timeout'
        (& $rss @{ 'network.rss' = (New-WorkerPerfHealthValue 'unreadable' 'timeout'); 'network.rssGlobal' = 'disabled' }).Value | Should -BeTrue
        $f = & $rss @{ 'network.rss' = $on; 'network.rssGlobal' = '2' }; $f.State | Should -Be 'unreadable'; $f.Reason | Should -Be 'error'
        $f = (Get-Facts @{ 'size.model' = 'Sim Corp Server 1'; 'network.rss' = $on; 'network.rssGlobal' = 'disabled' })['network.rssDisabled']; $f.State | Should -Be 'absent'; $f.Reason | Should -Be 'notInstalled'
        # gerendert: der Befund nennt, welche der zwei Stellen aus ist
        $g = Get-Check ($Vm + @{ 'network.rss' = $on; 'network.rssGlobal' = 'disabled' }) @{} 'network.rss' $Real
        $g.grade | Should -Be 'check'; $g.finding | Should -Match 'Globaler Schalter von Windows für RSS: disabled'; $g.finding | Should -Match 'abgeschaltet ist: 0\b'
        $a = Get-Check ($Vm + @{ 'network.rss' = $off; 'network.rssGlobal' = 'enabled' }) @{} 'network.rss' $Real
        $a.grade | Should -Be 'check'; $a.finding | Should -Match 'Globaler Schalter von Windows für RSS: enabled'; $a.finding | Should -Match 'abgeschaltet ist: 1\b'
        $ok = Get-Check ($Vm + @{ 'network.rss' = $on; 'network.rssGlobal' = 'enabled' }) @{} 'network.rss' $Real; $ok.grade | Should -Be 'ok'
        $ok.finding | Should -Match 'global in Windows eingeschaltet'; $ok.finding | Should -Not -Match 'liest das Zustandsbild nicht'
        (Get-Check ($Vm + @{ 'network.rss' = $on }) @{} 'network.rss' $Real).grade | Should -Be 'unknown'
        $c = $Real.checks | Where-Object id -eq 'network.rss'
        $c.meaning | Should -Match 'liest beide'; $c.meaning | Should -Match 'BIS-F widerspricht sich selbst'; $c.meaning | Should -Not -Match 'liest nur'
        (@($c.todo)[0].where) | Should -Match 'Rohwerte „Receive Side Scaling global in Windows“ und „Receive Side Scaling je Netzwerkadapter“'
        $Real.legends.'network.rssGlobal' | Should -BeExactly 'enabled = eingeschaltet, disabled = ausgeschaltet'
    }
    It 'nennt die Protokolle nur seit dem letzten Start, wenn dieser Start im Rueckblick liegt' {   # Punkt 7
        $logs = { param([double]$Days) @(foreach ($n in 'Application', 'System') { @{ Log = $n; Present = $true; Enabled = $true; MaxSizeMB = 20; FileSizeMB = 1; Records = 5; Mode = 'Circular'; Full = $false; Oldest = $ReadMs - [long]($Days * $Day) } }) }
        $case = { param($bootDays, $logDays) @{ 'operation.lastBoot' = $ReadMs - [long]($bootDays * $Day); 'events.logs' = (& $logs $logDays) } }
        # Rueckblick 7 Tage
        (Get-Facts (& $case 10 9))['events.sinceBootOnly'].Value | Should -BeFalse                                     # Start vor dem Rueckblick: der ganze Rueckblick ist abgedeckt
        (Get-Facts (& $case 2 1.9))['events.sinceBootOnly'].Value | Should -BeTrue
        (Get-Facts (& $case 2 5))['events.sinceBootOnly'].Value | Should -BeFalse
        (Get-Facts (& $case 10 3))['events.sinceBootOnly'].Value | Should -BeFalse                                     # der Start erklaert die Luecke nicht
        (Get-Facts (& $case 2 1.9) $NoLookback)['events.sinceBootOnly'].Value | Should -BeFalse                        # ohne Rueckblick liegt kein Start darin
        # gerendert
        $r = { param($values, $id) Get-Check $values @{} $id $Real }
        $x = & $r (& $case 10 9) 'events.sinceBoot'; $x.grade | Should -Be 'ok'
        $x.finding | Should -BeExactly ('Die gelesenen Ereignisprotokolle reichen vor den letzten Start des Servers zurück, sie haben keinen Eintrag, oder der letzte Start liegt vor dem Beginn ' +
            'des Rückblicks (letzter Start: 05.01.2026 08:00; Länge des Rückblicks in Tagen: 7; ein Strich heißt: nicht gelesen).')
        (& $r (& $case 10 9) 'events.coverage').grade | Should -Be 'ok'
        $x = & $r (& $case 2 1.9) 'events.sinceBoot'; $x.grade | Should -Be 'check'
        $x.finding | Should -BeExactly ('Kein gelesenes Ereignisprotokoll reicht vor den letzten Start des Servers zurück (13.01.2026 08:00). Liegt dieser Start innerhalb des Rückblicks (eingestellte Länge in Tagen: 7), ' +
            'zeigen Rückblick und Ereignisbild nur die Zeit seit dem Start. Auf einem nicht persistenten Server ohne beständiges Laufwerk ist das der Normalfall. Das ist ein Hinweis aus der Praxis, kein Fehler.')
        $y = & $r (& $case 2 1.9) 'events.coverage'; $y.grade | Should -Be 'ok'
        $y.finding | Should -BeExactly ('Lücke zwischen dem Beginn des Rückblicks und dem ältesten Eintrag des Protokolls, das am wenigsten weit zurückreicht, in Tagen: 6; der Rückblick reicht nur bis zum letzten Start: ja ' +
            '(letzter Start: 13.01.2026 08:00; ein Strich heißt: nicht gelesen; eine Lücke, die der letzte Start erklärt, meldet diese Prüfung nicht).')
        (& $r (& $case 2 5) 'events.sinceBoot').grade | Should -Be 'ok'
        $z = & $r (& $case 2 5) 'events.coverage'; $z.grade | Should -Be 'check'; $z.finding | Should -Match 'Tage ohne Eintrag: 2\); der letzte Start \(13\.01\.2026 08:00\) erklärt das nicht\.'
        $w = & $r (& $case 10 3) 'events.coverage'; $w.grade | Should -Be 'check'; $w.finding | Should -Match 'Tage ohne Eintrag: 4\); der letzte Start \(05\.01\.2026 08:00\) erklärt das nicht\.'
        (& $r (& $case 10 3) 'events.sinceBoot').grade | Should -Be 'ok'
        $Real.values.'events.sinceBootOnly' | Should -BeExactly 'Rückblick reicht nur bis zum letzten Start'
    }
    It 'fuehrt die neuen Werte mit schlichter Bezeichnung und die Seiten im Nachweis' {   # Punkte 3, 6, 8
        $Real.values.'maintenance.scanOffset' | Should -BeExactly 'Verzögerung geplanter Scans von Defender Antivirus'
        $Real.values.'maintenance.scanRandomWindow' | Should -BeExactly 'Zeitfenster der zufälligen Startzeit geplanter Scans'
        $Real.values.'network.rssGlobal' | Should -BeExactly 'Receive Side Scaling global in Windows'
        $Real.values.'network.rssDisabled' | Should -BeExactly 'Receive Side Scaling global oder an einem VMXNET3-Adapter abgeschaltet'
        $WorkerPerfHealthValues['maintenance.scanOffset'].Unit | Should -Be 'Minuten'; $WorkerPerfHealthValues['maintenance.scanRandomWindow'].Unit | Should -Be 'Minuten'
        $proof = ([regex]::Match((Get-Content (Join-Path $PSScriptRoot '../docs/guidance/quellen.md') -Raw), '(?ms)^## Zustandsbild\s*$(.*?)(?=^## |\z)').Groups[1].Value) -replace '\s+', ' '
        foreach ($w in 'schedule-antivirus-scans-powershell', 'msft-netoffloadglobalsetting', 'win32-tssessionsetting', 'win32-quickfixengineering', '`maintenance.scanOffset`', '`network.rssGlobal`') {
            $proof | Should -Match ([regex]::Escape($w)) -Because $w }
        $d = $Real.checks | Where-Object id -eq 'maintenance.defenderScanInWorkHours'
        $d.meaning | Should -Match 'Verzögerung'; $d.meaning | Should -Not -Match 'nicht sein genauer Beginn'; $d.meaning | Should -Not -Match 'wertet die Zeit des Schnellscans nicht aus'
        @($d.values) | Should -Contain 'maintenance.scanOffset'; @($d.values) | Should -Contain 'maintenance.scanRandomWindow'
    }
    It 'haelt im Nachweis fest, was .NET mit der Liste der Umbenennungen tut und was der erste Lauf bestaetigen muss' {   # Korrekturrunde 1, Punkte 5 und 6
        $proof = ([regex]::Match((Get-Content (Join-Path $PSScriptRoot '../docs/guidance/quellen.md') -Raw), '(?ms)^## Zustandsbild\s*$(.*?)(?=^## |\z)').Groups[1].Value) -replace '\s+', ' '
        $proof | Should -Not -Match 'nur die letzte vor dem Ende der Liste lässt \.NET weg'
        $proof | Should -Match 'nur weg, wenn der gespeicherten Liste ihr abschließendes Nullzeichen fehlt'
        $confirm = [regex]::Match($proof, '### Auf dem Zielsystem zu bestätigen(.*)$').Groups[1].Value
        foreach ($w in 'ScanScheduleQuickScanTime', '00:00', 'SchedulerRandomizationTime', 'TimeLimitPolicy', 'Computerrichtlinie', 'MSFT_NetOffloadGlobalSetting') {
            $confirm | Should -Match ([regex]::Escape($w)) -Because $w }
    }
}
Describe 'Katalog in src: simulierte Stunde, Schnelllauf, weitere Anwendung, Nachweis' {
    BeforeAll {
        $script:CatFile = Join-Path $PSScriptRoot '../src/health.de.json'; $script:Apps = @(Read-WorkerPerfHealthApps (Join-Path $PSScriptRoot '../src/apps.json'))
        $script:Real = Read-WorkerPerfHealthCatalogue $CatFile $Apps; $script:Th = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json')
        $script:Proof = [regex]::Match((Get-Content (Join-Path $PSScriptRoot '../docs/guidance/quellen.md') -Raw), '(?ms)^## Zustandsbild\s*$(.*?)(?=^## |\z)').Groups[1].Value
        $script:SimRun = Invoke-SimCapture (Join-Path $TestDrive 'sim'); $script:SimHo = Invoke-SimHealthOnly (Join-Path $TestDrive 'ho')
        function Get-SimResult([string]$Run, $Catalogue = $script:Real) { Get-WorkerPerfHealthResult -Model (Import-WorkerPerfRun -Path $Run -Thresholds $Th -Roles $Roles) -Catalogue $Catalogue -EventConfig $Cfg -Roles $Roles -Texts $Texts }
        function Get-Grades($Result) { $g = @{}; foreach ($a in $Result.areas) { foreach ($c in $a.checks) { $g[$c.id] = $c.grade } }; $g }
    }
    It 'bewertet die simulierte Stunde wie im Drehbuch' {
        $r = Get-SimResult $SimRun; $g = Get-Grades $r; $g.Count | Should -Be 80
        @($g.Keys | Where-Object { $g[$_] -eq 'act' } | Sort-Object) | Should -Be @('print.driversInSpooler', 'profile.containerFull')
        # print.operationalLogOff (PXH-02, Task 14b) ist nach dem Plan dazugekommen: die Simulation fuehrt das Betriebsprotokoll zum Drucken als ausgeschaltet
        @($g.Keys | Where-Object { $g[$_] -eq 'check' } | Sort-Object) | Should -Be @('apps.edgeBackgroundMode', 'apps.teamsAutoUpdate', 'events.crashes', 'maintenance.tasksInWorkHours', 'operation.pendingRestart', 'print.operationalLogOff')
        @($g.Keys | Where-Object { $g[$_] -eq 'unknown' } | Sort-Object) | Should -Be @('security.citrixExclusions', 'security.wemExclusions')
        @($g.Keys | Where-Object { $g[$_] -eq 'na' }).Count | Should -Be 0
        $g['operation.powerPlan'] | Should -Be 'ok'; $g['print.mappingClientSupported'] | Should -Be 'ok'       # Hoechstleistung; Client 6.4.1
        @($r.areas.grade) | Should -Be @('ok', 'check', 'ok', 'ok', 'act', 'act', 'ok', 'ok', 'check', 'check', 'check')
        $r.summary.text | Should -Be '2 Bereiche zum Handeln, 4 zum Prüfen, 5 in Ordnung'; $r.unknownCount | Should -Be 2
        ($r.areas | Where-Object id -eq 'profile').checks[0].finding | Should -Match '96'
        $apps = $r.areas | Where-Object id -eq 'apps'; @($apps.apps.state | Select-Object -Unique) | Should -Be @('installed'); @($apps.apps.key | Sort-Object) | Should -Be @('edge', 'office', 'teams')
        @($apps.checks | Where-Object { $_.app -eq 'office' }).grade | Should -Be @('ok')                              # Office: installiert und in Ordnung
        @($r.areas | ForEach-Object { $_.checks } | Where-Object { -not $_.finding }).Count | Should -Be 0
        $r.environmentText | Should -Match 'nicht persistent'; ($r.areas | Where-Object id -eq 'events').intro | Should -Match '\d\d\.\d\d\.\d{4}'
    }
    It 'bewertet den simulierten Schnelllauf ohne die Ereignisse der Messung' {
        $r = Get-SimResult $SimHo; $g = Get-Grades $r
        $g['print.driversInSpooler'] | Should -Be 'check'; $g['profile.containerFull'] | Should -Be 'act'; $r.summary.text | Should -Be '1 Bereich zum Handeln, 5 zum Prüfen, 5 in Ordnung'
    }
    It 'bewertet eine vierte Anwendung, die nur in Testdateien beschrieben ist, ohne Aenderung am Code' {   # Review Focus 3; Entwurf 3.2a
        $appFile = New-TestAppFile $TestDrive; $j = Get-Content $CatFile -Raw | ConvertFrom-Json
        $j.checks += [pscustomobject]@{ id = 'apps.simCache'; area = 'apps'; title = 'Cache der Sim-Fachanwendung'; values = @('apps.simapp.cacheMode')
            rules = @{ check = @(@{ value = 'apps.simapp.cacheMode'; op = 'ne'; than = 2 }) }
            findings = @{ ok = 'Cache-Betriebsart in Ordnung.'; check = 'Cache-Betriebsart {apps.simapp.cacheMode}.'; unknown = 'Nicht prüfbar: {reason}.' }; meaning = 'Erfundene Prüfung.'
            todo = @(@{ text = 'Betriebsart prüfen'; where = 'im Master-Image'; sign = 'Wert 2' }); source = @{ vendor = 'Test'; title = 'Test'; url = ''; date = '2026-11-13' }; kind = 'rule'; relates = @('disk') }
        $catFile = Join-Path $TestDrive 'health.test.json'; [IO.File]::WriteAllText($catFile, ($j | ConvertTo-Json -Depth 12))
        $cat = Read-WorkerPerfHealthCatalogue $catFile @(Read-WorkerPerfHealthApps $appFile)
        { Read-WorkerPerfHealthCatalogue $catFile $Apps } | Should -Throw "*Pruefung 'apps.simCache'*Anwendung 'simapp' steht nicht in der Anwendungsliste*"
        # auf dem simulierten Server ist sie nicht installiert: trifft nicht zu, zaehlt nicht
        $r = Get-SimResult (Invoke-SimHealthOnly (Join-Path $TestDrive 'ho-app') @{ AppsFile = $appFile }) $cat; $a = $r.areas | Where-Object id -eq 'apps'
        $a.checks[-1].id | Should -Be 'apps.simCache'; $a.checks[-1].grade | Should -Be 'na'; $a.checks[-1].why | Should -Be 'Sim-Fachanwendung ist nicht installiert'
        ($a.apps | Where-Object key -eq 'simapp').text | Should -Be 'Sim-Fachanwendung: nicht installiert'; $a.countsText | Should -Be '2 zum Prüfen'; $r.summary.text | Should -Be '1 Bereich zum Handeln, 5 zum Prüfen, 5 in Ordnung'
        # derselbe Server mit der Anwendung: nur sein Stand aendert sich, kein Code des Bausteins
        $patch = "`$script:SimHealthInner = `${function:Get-WorkerPerfHealth}`nfunction Get-WorkerPerfHealth {`n" +
            "    `$script:WorkerPerfSimAppState.Files['C:\Program Files\SimApp\simapp.exe'] = '4.2.0'; `$script:WorkerPerfSimAppState.Values['HKLM\SOFTWARE\SimApp|CacheMode'] = 1`n    & `$script:SimHealthInner }"
        $run = (& (New-PatchedSource (Join-Path $TestDrive 'srcapp') $patch) -Simulate -HealthOnly -AppsFile $appFile -OutputPath (Join-Path $TestDrive 'ho-app2') 6>$null 3>$null) | Select-Object -Last 1
        $a = (Get-SimResult $run $cat).areas | Where-Object id -eq 'apps'; $c = $a.checks | Where-Object id -eq 'apps.simCache'
        $c.grade | Should -Be 'check'; $c.finding | Should -Be 'Cache-Betriebsart 1.'; $c.app | Should -Be 'simapp'; $a.countsText | Should -Be '3 zum Prüfen'; ($a.apps | Where-Object key -eq 'simapp').state | Should -Be 'installed'
    }
    It 'fuehrt im Nachweis die Lesequellen und was nicht aufgenommen wurde' {
        $Proof | Should -Match 'Lesequellen'; $Proof | Should -Match 'Nicht aufgenommen'
        foreach ($title in 'Win32_ComputerSystem class', 'GetPerformanceInfo function', 'Windows Installer Properties for the Uninstall Registry Key', 'Microsoft Edge - Update policies') { $Proof | Should -Match ([regex]::Escape($title)) -Because $title }
        ($Real.checks | Where-Object id -eq 'apps.edgeUserDataDir').kind | Should -Be 'rule'                       # ob der Pfad lokal ist, kann die Regel nicht unterscheiden
    }
}
Describe 'Katalog in src: Anwendungen und Berichtigungen der Quellenpruefung (Task 14c)' {
    BeforeAll {
        $script:CatFile = Join-Path $PSScriptRoot '../src/health.de.json'; $script:Apps = @(Read-WorkerPerfHealthApps (Join-Path $PSScriptRoot '../src/apps.json'))
        $script:Real = Read-WorkerPerfHealthCatalogue $CatFile $Apps
        $script:Proof = [regex]::Match((Get-Content (Join-Path $PSScriptRoot '../docs/guidance/quellen.md') -Raw), '(?ms)^## Zustandsbild\s*$(.*?)(?=^## |\z)').Groups[1].Value
        $script:ProofFlat = $Proof -replace '\s+', ' '
        $script:Chk = @{}; foreach ($c in $Real.checks) { $script:Chk[[string]$c.id] = $c }
        # eine Zeile der Proben einer Anwendung, wie sie health.json traegt; Edge, Office und Teams installiert
        function New-AppRow([string]$App, [string]$Id, $Value, [string]$State = 'read', [string]$Kind = 'registryValue', [string]$Read = '') {
            [ordered]@{ App = $App; Id = $Id; Kind = $Kind; Read = $Read; State = $State; Reason = ''; Value = $Value; Names = $null } }
        function Get-AppCheck([string]$Id, [hashtable]$Probes = @{}, [string[]]$NotInstalled = @()) {
            # jede Probe der drei Anwendungen hat eine Zeile: gegeben gelesen, sonst nicht gesetzt; eine nicht installierte Anwendung mit notInstalled
            $rows = @(foreach ($app in @($Apps | Where-Object { $_.installed })) {
                    $a = [string]$app.key; $inst = $NotInstalled -notcontains $a
                    New-AppRow $a 'installed' $inst 'read' 'file' 'exists'
                    foreach ($p in @($app.probes)) {
                        $k = "$a.$($p.id)"
                        if (-not $inst) { $r = New-AppRow $a $p.id $null 'absent'; $r.Reason = 'notInstalled'; $r; continue }
                        if (-not $Probes.ContainsKey($k)) { New-AppRow $a $p.id $null 'absent'; continue }
                        if ($p.id -eq 'userDataDir') { $r = New-AppRow $a $p.id $null; $r.Names = $Probes[$k]; $r } else { New-AppRow $a $p.id $Probes[$k] }
                    } })
            $r = Get-WorkerPerfHealthResult -Model (New-HealthModel @{ 'apps.probes' = $rows }) -Catalogue $Real -EventConfig $Cfg -Roles $Roles -Texts $Texts
            @($r.areas | ForEach-Object { $_.checks }) | Where-Object id -eq $Id }
    }
    It 'stuft die Pruefungen der Anwendungen nach den Tabellen des Plans ein' {
        foreach ($case in @(
                @('apps.edgeAutoUpdate', @{ 'edge.updateDefault' = 0 }, 'ok'), @('apps.edgeAutoUpdate', @{}, 'check'), @('apps.edgeAutoUpdate', @{ 'edge.updateDefault' = 1 }, 'check'),
                @('apps.edgeAutoUpdate', @{ 'edge.updateStable' = 0 }, 'ok'), @('apps.edgeAutoUpdate', @{ 'edge.updateDefault' = 0; 'edge.updateStable' = 1 }, 'ok'),
                @('apps.edgeUpdateCheckOff', @{ 'edge.updateCheckMinutes' = 0 }, 'check'), @('apps.edgeUpdateCheckOff', @{}, 'ok'), @('apps.edgeUpdateCheckOff', @{ 'edge.updateCheckMinutes' = 60 }, 'ok'),
                @('apps.edgeWebView2Update', @{ 'edge.updateWebView2' = 0 }, 'check'), @('apps.edgeWebView2Update', @{}, 'ok'),
                @('apps.edgeStartupBoost', @{ 'edge.startupBoost' = 0 }, 'ok'), @('apps.edgeStartupBoost', @{ 'edge.startupBoost' = 1 }, 'check'), @('apps.edgeStartupBoost', @{}, 'check'),
                @('apps.edgeBackgroundMode', @{ 'edge.backgroundMode' = 1 }, 'check'), @('apps.edgeBackgroundMode', @{ 'edge.backgroundMode' = 0 }, 'ok'), @('apps.edgeBackgroundMode', @{}, 'ok'),
                @('apps.edgeSleepingTabs', @{ 'edge.sleepingTabs' = 0 }, 'check'), @('apps.edgeSleepingTabs', @{}, 'ok'),
                @('apps.edgeAutoDiscard', @{ 'edge.autoDiscard' = 0 }, 'check'), @('apps.edgeAutoDiscard', @{}, 'ok'),
                @('apps.edgeRoamingProfile', @{ 'edge.roamingProfile' = 1 }, 'check'), @('apps.edgeRoamingProfile', @{}, 'ok'),
                @('apps.edgeUserDataDir', @{ 'edge.userDataDir' = '\\fs01\edge$\%USERNAME%' }, 'check'), @('apps.edgeUserDataDir', @{}, 'ok'),
                @('apps.officeUpdateUi', @{ 'office.hideEnableDisableUpdates' = 1 }, 'ok'), @('apps.officeUpdateUi', @{}, 'check'), @('apps.officeUpdateUi', @{ 'office.hideEnableDisableUpdates' = 0 }, 'check'),
                @('apps.teamsAutoUpdate', @{ 'teams.disableAutoUpdate' = 1 }, 'ok'), @('apps.teamsAutoUpdate', @{}, 'check'),
                @('apps.teamsFallback', @{ 'teams.disableFallback' = 1 }, 'ok'), @('apps.teamsFallback', @{ 'teams.disableFallback' = 2 }, 'ok'),
                @('apps.teamsFallback', @{ 'teams.disableFallback' = 0 }, 'check'), @('apps.teamsFallback', @{}, 'check'),
                @('apps.teamsWebView2', @{ 'teams.webview2Version' = '130.0.2849.80' }, 'ok'), @('apps.teamsWebView2', @{}, 'check'),
                @('apps.teamsClassic', @{ 'teams.classicTeams' = $true }, 'check'), @('apps.teamsClassic', @{ 'teams.classicTeams' = $false }, 'ok'))) {
            $x = Get-AppCheck $case[0] $case[1]; $x.grade | Should -Be $case[2] -Because "$($case[0]) $(($case[1].Keys | ForEach-Object { "$_=$($case[1][$_])" }) -join ' ')"
            $x.finding | Should -Not -Match '[{}]' -Because $case[0]
        }
        # eine Anwendung, die nicht installiert ist: ihre Pruefungen treffen nicht zu
        foreach ($id in 'apps.edgeAutoUpdate', 'apps.teamsClassic', 'apps.officeUpdateUi') { (Get-AppCheck $id @{} @('edge', 'office', 'teams')).grade | Should -Be 'na' -Because $id }
        # der Pfad des verlegten Ordners ist freier Servertext und steht nicht im Befund
        (Get-AppCheck 'apps.edgeUserDataDir' @{ 'edge.userDataDir' = '\\fs01\edge$\%USERNAME%' }).finding | Should -Not -Match 'fs01'
        (Get-AppCheck 'apps.teamsWebView2').finding | Should -BeExactly 'Die WebView2-Runtime ist nicht maschinenweit installiert (HKLM); eine Installation je Benutzer liest das Zustandsbild nicht.'
        @($Chk.Keys | Where-Object { $_ -like 'apps.*' }).Count | Should -Be 14
        foreach ($c in @($Real.checks | Where-Object area -eq 'apps')) { @($c.rules.act).Count | Should -Be 0 -Because $c.id }
    }
    It 'schreibt die Texte der Anwendungen so, wie die Quellenpruefung sie traegt' {                      # Zusatz g; research-edge/office/teams-check.md
        $kind = [ordered]@{ 'apps.edgeAutoUpdate' = 'vendor'; 'apps.edgeUpdateCheckOff' = 'vendor'; 'apps.edgeWebView2Update' = 'vendor'; 'apps.edgeStartupBoost' = 'rule'
            'apps.edgeBackgroundMode' = 'vendor'; 'apps.edgeSleepingTabs' = 'vendor'; 'apps.edgeAutoDiscard' = 'vendor'; 'apps.edgeRoamingProfile' = 'vendor'; 'apps.edgeUserDataDir' = 'rule'
            'apps.officeUpdateUi' = 'rule'; 'apps.teamsAutoUpdate' = 'vendor'; 'apps.teamsFallback' = 'rule'; 'apps.teamsWebView2' = 'vendor'; 'apps.teamsClassic' = 'practice' }
        foreach ($id in $kind.Keys) { $Chk[$id].kind | Should -Be $kind[$id] -Because $id; $Chk[$id].source.url | Should -Match '^https://' -Because $id }
        # Edge: nur Microsoft, mit beiden Bedingungen der Richtlinien fuer Updates; nichts darueber, was Dienste oder Aufgaben des Updaters tun
        $au = $Chk['apps.edgeAutoUpdate']; $au.source.vendor | Should -Be 'Microsoft'; $au.source.title | Should -BeExactly 'Microsoft Edge for Virtual desktop infrastructure (VDI)'
        $au.meaning | Should -Match 'Active-Directory-Domäne'; $au.meaning | Should -Match 'Vorgabe für Edge selbst geht der Vorgabe für alle Kanäle vor'
        "$($au.meaning) $(@($au.todo | ForEach-Object { $_.text }) -join ' ')" | Should -Not -Match 'Stalhood|Dienste .*laufen|Aufgaben .*laufen'
        $Chk['apps.edgeWebView2Update'].meaning | Should -Match 'Master-Image die aktuelle Runtime'
        $sb = $Chk['apps.edgeStartupBoost']; $sb.meaning | Should -Match 'beschreibt nur'; $sb.meaning | Should -Match 'Faustregel des Katalogs'; $sb.meaning | Should -Match 'Aaron Parker \(2023'
        "$($Chk['apps.edgeSleepingTabs'].meaning) $(@($Chk['apps.edgeSleepingTabs'].todo | ForEach-Object { $_.sign }) -join ' ')" | Should -Not -Match '900|SleepingTabsTimeout'
        $ad = $Chk['apps.edgeAutoDiscard'].meaning; $ad | Should -Match 'drei Browsersitzungen'; $ad | Should -Match '12 Stunden'; $ad | Should -Match 'trägt .* wenig bei'
        $rp = $Chk['apps.edgeRoamingProfile']; "$($rp.meaning) $($rp.findings.check)" | Should -Match 'an ein Konto der Active-Directory-Domäne gebunden'; $rp.findings.check | Should -Match 'zeigt der Wert allein nicht'
        $ud = $Chk['apps.edgeUserDataDir']; $ud.meaning | Should -Match 'nicht unterstützt'; $ud.meaning | Should -Match 'Enterprise Sync'; $ud.meaning | Should -Match 'sagt Microsoft nichts'
        $ud.meaning | Should -Not -Match 'ein lokaler Pfad ist es nicht|nur ein umgeleiteter Ordner'
        # Office: ein Beispielwert von Microsoft fuer Microsoft 365 Apps, kein Rat fuer Office LTSC auf Windows Server
        $of = $Chk['apps.officeUpdateUi']; foreach ($w in 'Beispiel', 'Microsoft 365 Apps', 'Azure Virtual Desktop', 'ohne einen Grund', 'Office LTSC', 'verbirgt nur den Schalter') { $of.meaning | Should -Match ([regex]::Escape($w)) -Because $w }
        $of.meaning | Should -Not -Match 'empfiehlt'
        # Teams
        $tu = $Chk['apps.teamsAutoUpdate']; $tu.meaning | Should -Match 'Besprechungs-Add-in'; "$($tu.meaning) $($tu.findings.check)" | Should -Not -Match 'Speicherplatz|Versionen der Sitzungen'
        $fb = $Chk['apps.teamsFallback']; $fb.source.vendor | Should -Be 'Microsoft'; foreach ($w in 'nicht unterstützten Endgerät', 'nach Citrix', 'keiner der Hersteller nennt einen Sollwert', 'Faustregel des Katalogs') { $fb.meaning | Should -Match $w -Because $w }
        $fb.findings.check | Should -Match 'Entscheidung des Betreibers'
        $wv = $Chk['apps.teamsWebView2'].meaning; $wv | Should -Match 'Oktober 2026'; $wv | Should -Match 'Windows Server 2022'; $wv | Should -Match '25\.08\.2026'; $wv | Should -Not -Match 'Upgrade|planen'
        $tc = $Chk['apps.teamsClassic']; $tc.source.vendor | Should -Be 'Manuel Winkel'; $tc.source.url | Should -Match '^https://www\.deyda\.net/'; $tc.meaning | Should -Match 'maschinenweit'
        $tc.findings.ok | Should -Match 'je Benutzer'
        # Nachweis: die Zeilen der Anwendungen, Manuel Winkel als Praxisquelle, Aaron Parker als zweite Quelle
        foreach ($w in 'Quellen aus der Praxis: deyda.net', 'install-new-microsoft-teams-version-2-in-citrix', 'stealthpuppy.com/m365apps-frontline-workers', 'hdx-registry-settings', 'install-office-on-wvd-master-image') { $ProofFlat | Should -Match ([regex]::Escape($w)) -Because $w }
    }
    It 'uebernimmt die Berichtigungen der sieben Pruefdateien an den Pruefungen der Tasks 14a und 14b' {      # Zusatz h
        # Regeln: DNS nur fuer Mitglieder einer Domaene (beide Wege)
        foreach ($id in 'network.dnsCount', 'network.dnsPublic') { @($Chk[$id].values) | Should -Contain 'network.domainMember' -Because $id }
        (Get-Check @{ 'network.domainMember' = $true; 'network.dnsServers' = @(@{ Interface = 4; Address = '10.0.0.1' }) } @{} 'network.dnsCount' $Real).grade | Should -Be 'check'
        (Get-Check @{ 'network.domainMember' = $false; 'network.dnsServers' = @(@{ Interface = 4; Address = '10.0.0.1' }) } @{} 'network.dnsCount' $Real).grade | Should -Be 'ok'
        (Get-Check @{ 'network.domainMember' = $true; 'network.dnsServers' = @(@{ Interface = 4; Address = '8.8.8.8' }, @{ Interface = 4; Address = '10.0.0.1' }) } @{} 'network.dnsPublic' $Real).grade | Should -Be 'check'
        (Get-Check @{ 'network.domainMember' = $false; 'network.dnsServers' = @(@{ Interface = 4; Address = '8.8.8.8' }, @{ Interface = 4; Address = '10.0.0.1' }) } @{} 'network.dnsPublic' $Real).grade | Should -Be 'ok'
        $Chk['network.dnsCount'].meaning | Should -Match 'lokale DNS-Server'; $Chk['network.dnsCount'].meaning | Should -Match 'WAN'
        # print.driversInSpooler: Faustregel mit der Seite von Microsoft als Beleg (Entscheidung ZB-R54)
        $ds = $Chk['print.driversInSpooler']; $ds.kind | Should -Be 'rule'; $ds.source.title | Should -BeExactly 'Printer Driver Isolation'; $ds.meaning | Should -Match 'Isolierung nicht ausdrücklich unterstützt'
        (@($ds.todo | ForEach-Object { $_.text }) -join ' ') | Should -Match 'wenn der Treiber die Isolierung unterstützt'
        # events.retainFull: die Seite zu wevtutil
        $rf = $Chk['events.retainFull'].source; $rf.title | Should -BeExactly 'wevtutil'; $rf.url | Should -Be 'https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/wevtutil'; $rf.date | Should -Be '2023-02-03'
        $ProofFlat | Should -Match ([regex]::Escape('If an event log reaches its maximum size and the log retention mode is true, existing events are retained, and incoming events are discarded.'))
        # VMware
        $Chk['size.vmTools'].meaning | Should -Match 'prüft nur den Wert für Windows Server 2022'
        $Chk['size.storageController'].meaning | Should -Match 'Snapshots'
        $Chk['operation.powerPlan'].meaning | Should -Match 'eigenen Plan'
        # BIS-F
        $Chk['maintenance.updateServiceEnabled'].meaning | Should -Match 'privaten, beständigen Modus'
        $Chk['events.sinceBoot'].meaning | Should -Match 'Umleitung nicht abgeschaltet'
        # WEM
        $wc = $Chk['vda.wemCache']; $wc.findings.ok | Should -BeExactly 'Für den Cache des WEM-Agenten ist ein eigener Ort eingetragen. Ob dieser Ort einen Neustart übersteht, prüft das Zustandsbild nicht.'
        $wc.meaning | Should -Match '2603'; (@($wc.todo | ForEach-Object { "$($_.text) $($_.where)" }) -join ' ') | Should -Match 'nur mit einem Cache-Laufwerk'
        $Chk['vda.wemGpTimeout'].meaning | Should -Match 'Fehlt er, ist das kein Befund'
        $Real.values.'vda.wemServer' | Should -BeExactly 'Adresse des WEM-Servers aus der Richtlinie (Name oder IP-Adresse)'
        $ProofFlat | Should -Match 'security-guidelines-for-disabling-system-services-in-windows-server'
        # Sicherheit
        $np = $Chk['security.networkProtection']; $np.meaning | Should -Match 'überwachen'; $np.findings.check | Should -Match 'AllowNetworkProtectionOnWinServer'
        $Chk['security.signatureAge'].findings.check | Should -Match '65535'
        foreach ($id in 'security.citrixExclusions', 'security.wemExclusions') { $Chk[$id].findings.check | Should -Match 'nicht aussagekräftig' -Because $id }
        $Chk['security.twoScanners'].meaning | Should -Match 'Rollenliste'
        # Zuordnungswerkzeug
        $mc = $Chk['print.mappingClientSupported']; $mc.meaning | Should -Match '6\.2\.1'; $mc.meaning | Should -Match 'zur gleichen Release-Version gehören'
        (@($mc.todo | ForEach-Object { $_.sign }) -join ' ') | Should -Match 'gehören zum selben Release'
    }
    It 'gibt jedem Strich und Kennwort im Befund seine Legende und spricht vom wirksamen Beginn' {      # Zusaetze j, k, p, q, r
        (Get-Check @{} @{} 'size.pagefilePresent' $Real).finding | Should -Match 'ein Strich heißt'
        (Get-Check @{} @{} 'operation.powerPlan' $Real).finding | Should -Match 'ein Strich heißt'
        (Get-Check @{} @{} 'vda.controllerCount' $Real).finding | Should -Match 'ein Strich heißt'
        (Get-Check @{} @{} 'profile.serviceStopped' $Real).finding | Should -Match 'ein Strich heißt'
        foreach ($id in 'maintenance.defenderScanInWorkHours', 'maintenance.updateInstallInWorkHours') { $Chk[$id].findings.ok | Should -Match 'ein Strich heißt: nicht gesetzt oder nicht gelesen' -Because $id }
        $x = Get-Check @{ 'maintenance.updateOptions' = 4; 'maintenance.updateHour' = 10 } @{} 'maintenance.updateInstallInWorkHours' $Real
        $x.grade | Should -Be 'check'; $x.finding | Should -Match 'eingestellter Tag –, .*die Prüfung nimmt dann beim Tag jeden Tag und bei der Stunde nach Microsoft 03:00 Uhr an'
        $Chk['maintenance.defenderScanInWorkHours'].findings.check | Should -Match '8 = nie'
        foreach ($t in $Chk['maintenance.defenderScanInWorkHours'].todo) { $t.sign | Should -Match 'wirksame' }
        $Chk['network.rss'].title | Should -BeExactly 'Receive Side Scaling in Windows und am Netzwerkadapter'
        # Zusatz s: jeder Grund, einmal gerendert, liest sich im Rahmen der Pruefung
        # (perUser rendert der Test der Zeitlimits in 'Fakten nach der Quellenpruefung (Task 14s)', notRecorded der Test der Anwendungen ohne Zeile)
        foreach ($why in 'rights', 'timeout', 'error') {
            $f = (Get-Check @{ 'profile.service' = (New-WorkerPerfHealthValue 'unreadable' $why) } @{} 'profile.serviceStopped' $Real).finding
            $f | Should -Match '^Ein Wert, den die Prüfung braucht, liegt nicht vor: ' -Because $why
        }
    }
    It 'fuehrt im Nachweis Lesequellen, Nicht aufgenommenes und was auf dem Zielsystem zu bestaetigen ist' {   # Zusaetze i, l
        $Proof | Should -Match '(?m)^### Lesequellen$'; $Proof | Should -Match '(?m)^### Nicht aufgenommen$'
        foreach ($w in 'EDGE-F03 partly', 'EDGE-F28 partly', 'TEAMS-F05 partly', 'TEAMS-F12 partly', 'TEAMS-F13 partly', 'F-OFC-21 partly', 'F-OFC-30 partly', 'F-OFC-02 partly',
            'Configure Microsoft Defender Antivirus on Windows Server', 'MSFT_MpComputerStatus class', 'Exclusions in Microsoft Defender Antivirus', 'EventLogQuery.ReverseDirection', 'Policy CSP - ADMX_Printing') {
            $ProofFlat | Should -Match ([regex]::Escape($w)) -Because $w }
        $Proof | Should -Not -Match 'Betriebsprotokoll des Druckdienstes|Abstürzen des Druckdienstes'
        $confirm = (($Proof -split '(?m)^### Auf dem Zielsystem zu bestätigen$', 2)[1]) -replace '\s+', ' '
        foreach ($w in 'IPv6', 'Win32_SystemDriver', 'N/A', 'HideExclusionsFromLocalAdmins', 'EventLogNotFoundException') { $confirm | Should -Match ([regex]::Escape($w)) -Because $w }
    }
}
