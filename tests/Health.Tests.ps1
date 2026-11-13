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
        $f['size.cpuLogical'].Value | Should -Be 8; @($f.Keys).Count | Should -Be 164                       # gelesene Werte sind selbst Fakten
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
        @($f.Keys).Count | Should -Be 206; @($f.Keys)[164] | Should -BeLike 'apps.*'
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
        (Get-Facts @{})['maintenance.updateInWorkHours'].Value | Should -BeFalse                                                        # keine Richtlinie
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
        ($r.raw | Where-Object id -eq 'apps.simapp.installed').label | Should -Be 'Sim-Fachanwendung – Text appInstalledLabel'; @($r.raw).Count | Should -Be 206
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
        @($r.raw).Count | Should -Be 164
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
        $out[0] | Should -Be 'Nur 8,5 GB frei (Schwelle 10 GB).|Wert operation.minFreeGB: 8,5 GB|13.01.2026 08:00|1235 MB'
        $out[1] | Should -Be $out[0]
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
        @($r.raw).Count | Should -Be 206; @($r.areas).Count | Should -Be 11; ($r.raw | Where-Object id -eq 'operation.volumes').state | Should -Be 'read'
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
