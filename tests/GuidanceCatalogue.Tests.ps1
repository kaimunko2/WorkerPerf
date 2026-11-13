BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Events.ps1')
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Findings.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Guidance.ps1')
    $script:Texts = Read-WorkerPerfTexts (Join-Path $PSScriptRoot '../src/texts.de.json')
    $script:CatalogueFile = Join-Path $PSScriptRoot '../src/guidance.de.json'
    $script:SourcesFile = Join-Path $PSScriptRoot '../docs/guidance/quellen.md'
    $script:PrintVendors = @('Microsoft', 'Citrix', 'HP', 'Kyocera', 'Brother')
    # the source of a print element that is the report's own guidance, not a vendor's recommendation (ruling P3-R35)
    $script:OwnSource = 'WorkerPerf: Hinweis zur Auswertung'
    # conditions that only name a gap (ruling P3-R36)
    $script:GapCondition = { param($n) $n -like 'unmeasured.*' -or $n -like 'skipped.*' -or $n -in 'cause.notmeasured', 'pattern.unchecked', 'incident.unverified' }

    function New-Inc([hashtable]$Over = @{}) {
        # every key of an incident entry with neutral values (2 minutes from 10 min after the capture start), overwritten by
        # the given ones; a given event gets every key of an event with neutral values first (as in tests/Guidance.Tests.ps1)
        $inc = @{ id = 1; type = 'umfeld'; chronic = $false; severity = 2; start = [long](1e12 + 600000); end = [long](1e12 + 720000); durSec = 120.0
            lead = $null; resources = @(); text = ''; focus = $false; nearReported = $false; scanActive = $false; events = @(); signals = @(); affected = @()
            main = $null; cause = $null; unverified = $false; contributors = @{}; delayProcs = @(); endpoints = @(); ica = @()
            security = @{ products = @(); totalPct = 0 }; companion = $null; chronicContext = @(); eventIncidents = @(); event = $null }
        foreach ($k in $Over.Keys) { $inc[$k] = $Over[$k] }
        if ($null -ne $inc.event) {
            $ev = @{ kind = ''; key = ''; group = ''; count = 1; eventsTruncated = $false; users = @(); sessions = @(); inSession = $false; sessionUnknown = $false
                noUserSession = $false; versions = @(); modules = @(); moduleEvents = 0; sameModule = $false; codes = @(); app = ''; service = ''; driver = ''
                printer = ''; source = ''; before = $false; patterns = @(); unchecked = @(); overlap = @(); companions = @() }
            foreach ($k in $inc.event.Keys) { $ev[$k] = $inc.event[$k] }
            $inc.event = $ev
        }
        $inc
    }
    function New-Ctx {
        @{ Data = @{ apps = @(@{ i = 0; name = 'EXCEL.EXE'; role = '' }, @{ i = 1; name = 'MsMpEng.exe'; role = 'Sicherheit' }, @{ i = 2; name = 'fachapp.exe'; role = 'Hauptanwendung' })
                sessions = @(); sollIst = @(); unmeasured = @{ input = $false; worker = @() }; skipped = @()
                print = @{ drivers = @(@{ name = 'Sim PCL 6'; manufacturer = 'HP'; type = 3; isolation = 'none' }); queues = @(@{ name = 'Q1'; maxJobs = 3; jobErrors = 1; notReadyErrors = 0 }) }
                meta = @{ computer = 'SIM-VDA01'; offsetMin = 60; endReason = 'duration'; start = 1e12; end = 1e12 + 3600000 } }
            Thresholds = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json'); OffsetMinutes = 60; Texts = $script:Texts }
    }
    function New-Sig([string]$Id, [string]$Resource, [string]$Label, [double]$Peak, [string]$Unit, [string]$Ideal) {
        @{ id = $Id; label = $Label; resource = $Resource; peak = $Peak; unit = $Unit; ideal = $Ideal; severity = 2; start = [long](1e12 + 600000); end = [long](1e12 + 720000) }
    }
    function New-Engpass([string]$Lead, [hashtable]$Over = @{}) {
        # a bottleneck of a worker resource with a named main cause (EXCEL.EXE of user003) and two affected sessions
        $sig = @{ cpu = (New-Sig 'cpu.host' 'cpu' 'CPU-Auslastung' 97 '%' 'unter 75 %'); memory = (New-Sig 'mem.used' 'memory' 'RAM-Auslastung' 93 '%' 'unter 75 %')
            disk = (New-Sig 'disk.latency' 'disk' 'Laufwerk D:' 62 'ms' 'unter 10 ms'); share = (New-Sig 'smb.latency' 'share' 'Freigabe \\sim-fs\daten' 82 'ms' 'unter 10 ms')
            profile = (New-Sig 'disk.latency' 'profile' 'Profilcontainer von user003 (\\sim-fs\profile$)' 46 'ms' 'unter 10 ms') }
        $inc = @{ type = 'engpass'; lead = $Lead; cause = @{ kind = 'main' }; main = @{ app = 'EXCEL.EXE'; a = 0; user = 'user003'; sharePct = 62; baselinePct = 4 }
            affected = @(@{ s = 1 }, @{ s = 2 }); signals = @($sig[$Lead]) }
        foreach ($k in $Over.Keys) { $inc[$k] = $Over[$k] }
        New-Inc $inc
    }
    function Get-Guide($Incident, $Context = $null) {
        # the guidance of an incident as the report script will build it: facts, then the catalogue entry filled
        if ($null -eq $Context) { $Context = New-Ctx }
        $facts = Get-WorkerPerfGuidanceFacts -Incident $Incident -Context $Context -Catalogue $script:Real
        New-WorkerPerfGuidance -Catalogue $script:Real -Facts $facts -Incident $Incident -Texts $script:Texts
    }
    function Get-GuideTexts($Guide) {
        # every text of a guidance that the page or the copy text shows
        @($Guide.title, $Guide.meaning, $Guide.impact, $Guide.userView, $Guide.short) +
            @(foreach ($e in @($Guide.checks) + @($Guide.remedies) + @($Guide.contacts)) { foreach ($k in @($e.Keys)) { if ($null -ne $e[$k]) { [string]$e[$k] } } })
    }
    function Get-Elements($Catalogue) {
        # every check, remedy and contact of the catalogue: position ('print.remedies[2]'), conditions, source, texts
        foreach ($s in $script:WorkerPerfSituations) {
            foreach ($list in 'checks', 'remedies', 'contacts') {
                $elements = @($Catalogue.situations.$s.$list)
                for ($k = 0; $k -lt $elements.Count; $k++) {
                    $el = $elements[$k]
                    $when = @(); if ($el.PSObject.Properties['when']) { $when = @($el.when) }
                    $source = ''; if ($el.PSObject.Properties['source']) { $source = [string]$el.source }
                    $texts = @(foreach ($f in 'text', 'where', 'sign', 'precondition') { if ($el.PSObject.Properties[$f]) { [string]$el.$f } })
                    [pscustomobject]@{ Situation = $s; List = $list; Position = "$s.$list[$k]"; When = $when; Source = $source; Texts = $texts }
                }
            }
        }
    }
    function Get-Placeholders([string]$Text) { @([regex]::Matches($Text, '\{([A-Za-z0-9]+)\}') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique) }
    function Get-Positions([string]$Text) { @([regex]::Matches($Text, '`([a-z.]+\.(?:checks|remedies|contacts)\[\d+\])`') | ForEach-Object { $_.Groups[1].Value }) }
    function Get-SourceRows([string]$Path) {
        # the rows of the tables of adopted sources in docs/guidance/quellen.md: vendor (heading '## <vendor>', also the
        # section 'WorkerPerf' of the report's own notes), title (first cell), the catalogue positions the row adopts (the
        # first cell after the title that names positions) and the positions its remaining cells (the note) speak about
        $vendor = ''
        foreach ($line in [IO.File]::ReadAllLines($Path)) {
            $m = [regex]::Match($line, '^##\s+(.+?)\s*$')
            if ($m.Success) { $vendor = $m.Groups[1].Value; continue }
            if (@($script:PrintVendors + 'WorkerPerf') -cnotcontains $vendor -or $line -notmatch '^\|') { continue }
            $cells = @($line.Trim('|') -split '\|')
            $positions = @(); $noted = @()
            for ($k = 1; $k -lt $cells.Count; $k++) {
                $found = @(Get-Positions $cells[$k])
                if ($positions.Count -eq 0) { $positions = $found } else { $noted += $found }
            }
            if ($positions.Count -eq 0) { continue }
            [pscustomobject]@{ Vendor = $vendor; Title = $cells[0].Trim(); Positions = $positions; Noted = $noted; Line = $line }
        }
    }
}

Describe 'Katalog in src' {
    BeforeAll {
        $script:Real = Read-WorkerPerfGuidance $script:CatalogueFile
        $script:Elements = @(Get-Elements $script:Real)
    }
    It 'hat fuer jede erzeugbare Situation einen vollstaendigen Eintrag' {
        foreach ($s in $WorkerPerfSituations) { $Real.situations.$s | Should -Not -BeNullOrEmpty -Because $s; @($Real.situations.$s.checks).Count | Should -BeGreaterThan 0 -Because $s }
    }
    It 'nennt fuer jedes Druckelement eine Quelle und Herstellerelemente nur mit Herstellerbedingung' {
        $print = @($Real.situations.print.checks) + @($Real.situations.print.remedies) + @($Real.situations.print.contacts)
        foreach ($e in $print) { [string]$e.source | Should -Not -BeNullOrEmpty -Because $e.text }
        foreach ($v in 'HP', 'Kyocera', 'Brother') {
            foreach ($e in @($print | Where-Object { $_.source -like "$v*" })) { @($e.when) | Should -Contain "driver.vendor.$v" -Because $e.text }
        }
        # in every situation: a source names one of the five vendors or is exactly the report's own note (ruling P3-R35),
        # and an element sourced from a printer vendor hangs on that vendor's driver
        @($Elements | Where-Object { $_.Source -ceq $OwnSource }).Count | Should -BeGreaterThan 0
        foreach ($e in @($Elements | Where-Object { $_.Source })) {
            if ($e.Source -ceq $OwnSource) { $e.Situation | Should -Be 'print' -Because $e.Position; continue }
            $vendor = ($e.Source -split ': ', 2)[0]
            $PrintVendors | Should -Contain $vendor -Because $e.Position
            ($e.Source -split ': ', 2)[1] | Should -Not -BeNullOrEmpty -Because $e.Position
            if ($vendor -in 'HP', 'Kyocera', 'Brother') { $e.When | Should -Contain "driver.vendor.$vendor" -Because $e.Position }
        }
    }
    It 'zeigt herstellerspezifische Elemente nur beim passenden Hersteller' {
        $base = @{ type = 'ereignis'; event = @{ kind = 'print'; key = 'Sim PCL 6'; app = 'spoolsv.exe'; sessions = @(); before = $false; count = 1; patterns = @(); modules = @() }
            events = @(@{ app = 'spoolsv.exe'; service = ''; kind = 'crash'; log = 'application' }) }
        foreach ($v in @(@('HP', 'Kyocera'), @('Kyocera', 'HP'))) {
            $ctx = New-Ctx; $ctx.Data.print.drivers[0].manufacturer = $v[0]
            $i = New-Inc $base; $g = New-WorkerPerfGuidance -Catalogue $Real -Facts (Get-WorkerPerfGuidanceFacts -Incident $i -Context $ctx -Catalogue $Real) -Incident $i -Texts $Texts
            $all = @($g.checks) + @($g.remedies)
            @($all | Where-Object { $_.source -like "$($v[1])*" }).Count | Should -Be 0 -Because $v[0]
        }
    }
    It 'zeigt beim Treiber von <Maker> Elemente von <Vendor> und von keinem anderen Druckerhersteller' -ForEach @(
        @{ Maker = 'HP'; Vendor = 'HP' }; @{ Maker = 'Hewlett-Packard'; Vendor = 'HP' }; @{ Maker = 'KYOCERA Document Solutions Inc.'; Vendor = 'Kyocera' }
        @{ Maker = 'Brother'; Vendor = 'Brother' }
    ) {
        $ctx = New-Ctx; $ctx.Data.print.drivers[0].manufacturer = $Maker
        $g = Get-Guide (New-Inc @{ type = 'ereignis'; event = @{ kind = 'print'; key = 'Sim PCL 6'; app = 'spoolsv.exe' }; events = @(@{ app = 'spoolsv.exe'; kind = 'crash'; log = 'application' }) }) $ctx
        $g.conditions | Should -Contain "driver.vendor.$Vendor"
        $all = @($g.checks) + @($g.remedies) + @($g.contacts)
        @($all | Where-Object { $_.source -like "${Vendor}: *" }).Count | Should -BeGreaterThan 0
        foreach ($other in @('HP', 'Kyocera', 'Brother') | Where-Object { $_ -ne $Vendor }) { @($all | Where-Object { $_.source -like "${other}: *" }).Count | Should -Be 0 -Because $other }
        foreach ($e in $all) { [string]$e.source | Should -Not -BeNullOrEmpty -Because $e.text }
    }
    It 'zeigt ohne bekannten Hersteller nur Elemente von Microsoft und Citrix' {
        $ctx = New-Ctx; $ctx.Data.print.drivers[0].manufacturer = 'Acme Printing'
        $g = Get-Guide (New-Inc @{ type = 'ereignis'; event = @{ kind = 'print'; key = 'Sim PCL 6'; app = 'spoolsv.exe' }; events = @(@{ app = 'spoolsv.exe'; kind = 'crash'; log = 'application' }) }) $ctx
        $all = @($g.checks) + @($g.remedies) + @($g.contacts)
        $all.Count | Should -BeGreaterThan 0
        @($all | ForEach-Object { ($_.source -split ': ', 2)[0] } | Sort-Object -Unique | Where-Object { $_ -notin 'Microsoft', 'Citrix', 'WorkerPerf' }) | Should -Be @()
    }
    It 'stellt fuer einen Vorfall der Situation <S> eine vollstaendige Anleitung zusammen' -ForEach @(
        @{ S = 'cpu'; I = @{ type = 'engpass'; lead = 'cpu'; cause = @{ kind = 'main' }; main = @{ app = 'EXCEL.EXE'; a = 0; user = 'user003'; sharePct = 62; baselinePct = 4 }; affected = @(@{ s = 1 }, @{ s = 2 }) } }
        @{ S = 'memory'; I = @{ type = 'engpass'; lead = 'memory'; cause = @{ kind = 'none' }; affected = @(@{ s = 1 }) } }
        @{ S = 'disk'; I = @{ type = 'engpass'; lead = 'disk'; cause = @{ kind = 'security'; security = @{ label = 'Die Schutzsoftware'; sharePct = 40 } }; scanActive = $true } }
        @{ S = 'share'; I = @{ type = 'engpass'; lead = 'share'; cause = @{ kind = 'nodata' } } }
        @{ S = 'profile'; I = @{ type = 'engpass'; lead = 'profile'; cause = @{ kind = 'notmeasured' } } }
        @{ S = 'delay.many'; I = @{ type = 'ohne-engpass'; affected = @(@{ s = 1 }, @{ s = 2 }, @{ s = 3 }) } }
        @{ S = 'delay.single'; I = @{ type = 'ohne-engpass'; affected = @(@{ s = 1 }); unverified = $true } }
        @{ S = 'chronic.network'; I = @{ type = 'umfeld'; chronic = $true; end = [long](1e12 + 4200000); signals = @(@{ id = 'ica.rtt'; label = 'user020 (#21)'; resource = 'network'; peak = 225; unit = 'ms'; ideal = 'unter 150 ms'; severity = 1; start = [long]1e12; end = [long]1e12 }) } }
        @{ S = 'chronic.resource'; I = @{ type = 'engpass'; chronic = $true; lead = 'memory'; end = [long](1e12 + 4200000); cause = @{ kind = 'none' } } }
        @{ S = 'crash'; I = @{ type = 'ereignis'; start = [long]1e12; end = [long]1e12; event = @{ kind = 'crash'; app = 'EXCEL.EXE'; users = @('user004'); sessions = @(2); modules = @(@{ name = 'sim.dll'; count = 1 }) } } }
        @{ S = 'hang'; I = @{ type = 'ereignis'; start = [long]1e12; end = [long]1e12; event = @{ kind = 'hang'; app = 'EXCEL.EXE'; users = @('user004', 'user005'); sessions = @(2, 3); count = 2 } } }
        @{ S = 'service'; I = @{ type = 'ereignis'; start = [long]1e12; end = [long]1e12; event = @{ kind = 'service'; service = 'SimDienst'; noUserSession = $true; count = 2 } } }
        @{ S = 'print'; I = @{ type = 'ereignis'; start = [long]1e12; end = [long]1e12; event = @{ kind = 'print'; key = 'Microsoft-Windows-PrintService'; source = 'Microsoft-Windows-PrintService'; noUserSession = $true } } }
        @{ S = 'profileerror'; I = @{ type = 'ereignis'; start = [long]1e12; end = [long]1e12; event = @{ kind = 'profileerror'; users = @('user014'); sessions = @(14) } } }
        @{ S = 'system'; I = @{ type = 'ereignis'; start = [long]1e12; end = [long]1e12; event = @{ kind = 'system'; key = 'storage|D:' } } }
        @{ S = 'fallback'; I = @{ type = 'umfeld'; signals = @(@{ id = 'probe.connect'; label = 'Sim-Gegenstelle'; resource = 'endpoint'; peak = 300; unit = 'ms'; ideal = 'unter 50 ms'; severity = 2; start = [long]1e12; end = [long]1e12 }) } }
    ) {
        $g = Get-Guide (New-Inc $I)
        $g.situation | Should -Be $S; $g.fallback | Should -Be ($S -eq 'fallback')
        $g.title | Should -Be $Real.situations.$S.title
        foreach ($k in 'title', 'tech', 'meaning', 'impact', 'userView', 'short') { [string]$g[$k] | Should -Not -BeNullOrEmpty -Because $k }
        @($g.checks).Count | Should -BeGreaterThan 0
        foreach ($c in $g.checks) { foreach ($k in 'text', 'where', 'sign') { [string]$c[$k] | Should -Not -BeNullOrEmpty -Because "$k von '$($c.text)'" } }
        foreach ($m in $g.remedies) { foreach ($k in 'text', 'precondition') { [string]$m[$k] | Should -Not -BeNullOrEmpty -Because "$k von '$($m.text)'" } }
        # no text with a gap or a placeholder left over
        foreach ($t in (Get-GuideTexts $g)) { $t | Should -Not -Match '[{}]' }
        if ($S -eq 'fallback') { $g.meaning | Should -BeLike ($Real.fallbackNote + '*') }
    }
    It 'fuellt Bedeutung und Wirkung der Situation <S> auch fuer einen Vorfall ohne Dauer' -ForEach @(
        @{ S = 'crash' }; @{ S = 'hang' }; @{ S = 'service' }; @{ S = 'print' }; @{ S = 'profileerror' }; @{ S = 'system' }; @{ S = 'fallback' }
    ) {
        # an incident from a single event has no duration: its texts must not depend on one
        foreach ($f in 'meaning', 'impact') { $Real.situations.$S.$f | Should -Not -Match '\{duration\}' -Because $f }
        $Real.fallbackNote | Should -Not -Match '\{duration\}'
    }
    It 'nennt bei <S> im ersten Pruefschritt Anwendung und Benutzer des Hauptverursachers' -ForEach @(
        @{ S = 'cpu' }; @{ S = 'memory' }; @{ S = 'disk' }; @{ S = 'share' }; @{ S = 'profile' }
    ) {
        # the first check of the file that hangs on cause.app alone names both
        $first = @($Real.situations.$S.checks | Where-Object { $_.PSObject.Properties['when'] -and (@($_.when) -join ',') -eq 'cause.app' })[0]
        $first | Should -Not -BeNullOrEmpty
        $first.text | Should -Match '\{app\}'; $first.text | Should -Match '\{user\}'
        @(Get-Placeholders ($first.text + $first.where + $first.sign) | Where-Object { $_ -notin 'app', 'user', 'from', 'to' }) | Should -Be @()
        # and it is the first step of an incident with a named main cause, also beside a scan and a companion
        $g = Get-Guide (New-Engpass $S)
        $g.checks[0].text | Should -Match 'EXCEL\.EXE'; $g.checks[0].text | Should -Match 'user003'
        $g = Get-Guide (New-Engpass $S @{ scanActive = $true; companion = @{ label = 'Microsoft Defender' }; endpoints = @(@{ name = 'Sim-DB'; maxMs = 340; failed = $false })
                events = @(@{ kind = 'applocker-block'; log = 'applocker' }, @{ kind = 'scan-start'; log = 'defender' }) })
        $g.checks[0].text | Should -Match 'EXCEL\.EXE'; $g.checks[0].text | Should -Match 'user003'
        # without a baseline the first step stays
        $g = Get-Guide (New-Engpass $S @{ main = @{ app = 'EXCEL.EXE'; a = 0; user = 'user003'; sharePct = 62; baselinePct = $null } })
        $g.checks[0].text | Should -Match 'EXCEL\.EXE'
    }
    It 'erklaert die unvermeidbaren Fachbegriffe und fuehrt keinen Begriff, den kein Text verwendet' {
        $names = @($Real.terms.PSObject.Properties | ForEach-Object { $_.Name })
        foreach ($n in 'Working Set', 'Eingabeverzögerung', 'Profilcontainer', 'Dauerzustand', 'Druckwarteschlange', 'Treiberisolierung', 'Modul', 'Fehlercode') { $names | Should -Contain $n }
        # the templates the glossary is searched in: texts of the situations and the user's view (as New-WorkerPerfGuidance does)
        $templates = @($Elements | ForEach-Object { $_.Texts }) + @($WorkerPerfSituations | ForEach-Object { $Real.situations.$_.title; $Real.situations.$_.meaning; $Real.situations.$_.impact }) +
            @($Real.userView.PSObject.Properties | ForEach-Object { $_.Value }) + @($Real.fallbackNote)
        $haystack = [regex]::Replace(($templates -join "`n"), '\{\w+\}', "`n")
        foreach ($n in $names) { [regex]::IsMatch($haystack, '(?<![\p{L}\p{N}])' + [regex]::Escape($n), 'IgnoreCase, CultureInvariant') | Should -BeTrue -Because $n }
        # an explanation is one or two plain sentences without a placeholder
        foreach ($p in $Real.terms.PSObject.Properties) { $p.Value | Should -Not -Match '[{}]' -Because $p.Name; $p.Value | Should -Match '\.$' -Because $p.Name }
    }
    It 'listet in einer Anleitung die Fachbegriffe ihrer Texte' {
        $g = Get-Guide (New-Engpass 'memory')
        $g.terms | Should -Contain 'Working Set'
        $g = Get-Guide (New-Inc @{ type = 'ereignis'; event = @{ kind = 'crash'; app = 'EXCEL.EXE'; sessions = @(2); modules = @(@{ name = 'sim.dll'; count = 1 }) } })
        $g.terms | Should -Contain 'Modul'; $g.terms | Should -Contain 'Fehlercode'
    }
    It 'haelt in den Texten ausserhalb der Situationen die vereinbarten Platzhalter ein' {                       # ruling P3-R26
        $allowed = @{ 'copy.head' = @('server', 'date'); 'copy.summaryHead' = @('server', 'date', 'from', 'to'); 'copy.measure' = @('value', 'target'); 'copy.affected' = @('affected')
            'copy.cause' = @(); 'copy.checks' = @(); 'copy.remedies' = @(); 'copy.contact' = @()
            'lagebild.red' = @('bottlenecks', 'delays', 'events', 'chronic', 'minutes', 'incidents'); 'lagebild.yellow' = @('bottlenecks', 'delays', 'events', 'chronic', 'minutes', 'incidents')
            'lagebild.green' = @(); 'lagebild.greenSkipped' = @('skipped'); 'hints.unmeasured' = @('signals'); 'hints.skipped' = @('skipped'); 'hints.error' = @('message')
            'hints.errorNoMessage' = @(); 'hints.notFinished' = @(); 'hints.stopped' = @(); 'userView.unknown' = @('duration', 'from', 'to') }
        foreach ($k in 'many', 'one', 'none', 'chronic', 'eventMany', 'eventOne', 'eventNone', 'before') { $allowed["userView.$k"] = @('affected', 'duration', 'from', 'to', 'count') }
        foreach ($part in 'copy', 'lagebild', 'hints', 'userView') {
            foreach ($p in $Real.$part.PSObject.Properties) {
                $name = "$part.$($p.Name)"
                $allowed.ContainsKey($name) | Should -BeTrue -Because $name
                @(Get-Placeholders $p.Value | Where-Object { $allowed[$name] -cnotcontains $_ }) | Should -Be @() -Because $name
            }
        }
        $Real.lagebild.green | Should -BeExactly 'Keine Störung erkannt.'
        # what the green sentence with skipped events must say
        $Real.lagebild.greenSkipped | Should -Match '\{skipped\}'; $Real.lagebild.greenSkipped | Should -Match 'gemessenen'; $Real.lagebild.greenSkipped | Should -Match 'Ereignissen'
        $Real.hints.unmeasured | Should -Match '\{signals\}'; $Real.hints.skipped | Should -Match '\{skipped\}'; $Real.hints.error | Should -Match '\{message\}'
        $Real.copy.measure | Should -Match '\{value\}'; $Real.copy.measure | Should -Match '\{target\}'; $Real.copy.affected | Should -Match '\{affected\}'
        $Real.copy.head | Should -Match '\{server\}'; $Real.copy.head | Should -Match '\{date\}'
    }
    It 'waehlt die Benutzersicht ohne Luecke, auch ohne Dauer und ohne Zahl der Betroffenen' {
        # a text that cannot be filled falls back to userView.unknown, which therefore needs no value at all
        Get-Placeholders $Real.userView.unknown | Should -Be @()
        # an event incident has no duration when it holds one event; one from before the capture has no number of sessions
        foreach ($k in 'eventMany', 'eventOne', 'eventNone', 'before') { Get-Placeholders $Real.userView.$k | Should -Not -Contain 'duration' -Because $k }
        Get-Placeholders $Real.userView.before | Should -Not -Contain 'affected'
        (Get-Guide (New-Engpass 'cpu')).userView | Should -Match '2 Sitzungen'
        (Get-Guide (New-Inc @{ type = 'ereignis'; start = [long]1e12; end = [long]1e12; event = @{ kind = 'crash'; app = 'EXCEL.EXE'; users = @('user004'); before = $true; count = 3 } })).userView |
            Should -Be (Format-WorkerPerfGuidanceText $Real.userView.before @{ count = '3' })
        (Get-Guide (New-Inc @{ type = 'ereignis'; start = [long]1e12; end = [long]1e12; event = @{ kind = 'crash'; app = 'EXCEL.EXE'; sessionUnknown = $true } })).userView | Should -Be $Real.userView.unknown
    }
    It 'sagt bei nicht Gemessenem und nicht Geprueftem das auch, nie "keine"' {
        $notMeasured = @($Elements | Where-Object { @($_.When | Where-Object { & $GapCondition $_ }).Count -gt 0 })
        $notMeasured.Count | Should -BeGreaterThan 0
        foreach ($e in $notMeasured) {
            # the gap is said once per incident: the step that only repeats the capture names the switch instead
            ($e.Texts -join ' ') | Should -Match 'nicht gemessen|Nicht gemessen|nicht geprüft|Nicht geprüft|ohne „-Skip \p{L}+“ wiederholen' -Because $e.Position
            ($e.Texts -join ' ') | Should -Not -Match '(?i)\bkein(e|en|em|er|es)?\b' -Because $e.Position
        }
        # every situation with such elements says the gap in at least one of them, per condition
        foreach ($group in @($notMeasured | Group-Object { $_.Situation + ' ' + (@($_.When | Where-Object { & $GapCondition $_ }) -join '+') })) {
            @($group.Group | Where-Object { ($_.Texts -join ' ') -match 'nicht gemessen|nicht geprüft' }).Count | Should -BeGreaterThan 0 -Because $group.Name
        }
    }
    It 'hat die Varianten fuer nicht Gemessenes, wo ein Schritt davon abhaengt' {
        function Test-Has([string]$Situation, [scriptblock]$Filter) { @($Elements | Where-Object { $_.Situation -eq $Situation } | Where-Object { @($_.When | Where-Object $Filter).Count -gt 0 }).Count -gt 0 }
        foreach ($s in $WorkerPerfSituations) {
            # a step that relies on the cause or a role: processes not recorded
            if (Test-Has $s { $_ -eq 'cause.app' -or $_ -like 'role.*' }) { (Test-Has $s { $_ -in 'cause.notmeasured', 'skipped.Prozesse' }) | Should -BeTrue -Because "$s Prozesse" }
            # a step that relies on events in the window: events not recorded
            if (Test-Has $s { $_ -in 'scan', 'event.applocker', 'event.defender' }) { (Test-Has $s { $_ -eq 'skipped.Ereignisse' }) | Should -BeTrue -Because "$s Ereignisse" }
            # a step that relies on a pattern: pattern not checked
            if (Test-Has $s { $_ -like 'pattern.*' -and $_ -ne 'pattern.unchecked' }) { (Test-Has $s { $_ -eq 'pattern.unchecked' }) | Should -BeTrue -Because "$s Muster" }
        }
        foreach ($s in 'cpu', 'memory', 'disk', 'share', 'profile', 'chronic.resource') { foreach ($c in 'cause.app', 'cause.security', 'cause.none', 'cause.nodata', 'cause.notmeasured') { (Test-Has $s { $_ -eq $c }.GetNewClosure()) | Should -BeTrue -Because "$s $c" } }
        foreach ($s in 'delay.many', 'delay.single') { (Test-Has $s { $_ -eq 'incident.unverified' }) | Should -BeTrue -Because $s; (Test-Has $s { $_ -eq 'endpoint.slow' }) | Should -BeTrue -Because $s }
        (Test-Has 'print' { $_ -eq 'skipped.Drucken' }) | Should -BeTrue
        foreach ($c in 'driver.v3', 'driver.v4', 'driver.shared', 'driver.isolated', 'spooler.crash', 'queue.stuck', 'pattern.printdriver') { (Test-Has 'print' { $_ -eq $c }.GetNewClosure()) | Should -BeTrue -Because $c }
        (Test-Has 'crash' { $_ -eq 'pattern.printdriver' }) | Should -BeTrue
        foreach ($s in 'crash', 'hang', 'service', 'print', 'profileerror', 'system') { (Test-Has $s { $_ -eq 'before' }) | Should -BeTrue -Because "$s before" }
        foreach ($p in 'resource', 'afterhang', 'sharedmodule', 'printdriver', 'securitymodule', 'manyusers', 'oneuser', 'companion', 'overlap', 'none') { (Test-Has 'crash' { $_ -eq "pattern.$p" }.GetNewClosure()) | Should -BeTrue -Because $p }
        # the patterns a print incident can carry (ruling P3-R35) and the resources of a chronic state (ruling P3-R37)
        foreach ($p in 'printdriver', 'resource', 'securitymodule', 'oneuser', 'companion', 'overlap', 'none') { (Test-Has 'print' { $_ -eq "pattern.$p" }.GetNewClosure()) | Should -BeTrue -Because "print $p" }
        foreach ($l in 'cpu', 'memory', 'disk', 'share', 'profile') { (Test-Has 'chronic.resource' { $_ -eq "lead.$l" }.GetNewClosure()) | Should -BeTrue -Because "chronic.resource lead.$l" }
        @($Elements | Where-Object { $_.Situation -ne 'chronic.resource' -and @($_.When | Where-Object { $_ -like 'lead.*' }).Count -gt 0 }) | Should -Be @()
    }
    It 'nennt bei nicht erfassten Prozessen, was beim naechsten Mal zu messen ist' {
        $ctx = New-Ctx; $ctx.Data.skipped = @(@{ id = 'Prozesse'; label = 'Prozesse'; text = ''; places = @() }); $ctx.Data.apps = @()
        foreach ($s in 'cpu', 'memory', 'disk', 'share', 'profile') {
            $g = Get-Guide (New-Engpass $s @{ cause = @{ kind = 'notmeasured' }; main = $null }) $ctx
            $all = @($g.checks | ForEach-Object { $_.text + ' ' + $_.where + ' ' + $_.sign })
            # one step says that the cause was not measured, the next one what to record next time (the gap is said once)
            @($all | Where-Object { $_ -match 'nicht gemessen' -and $_ -match 'Prozesse' }).Count | Should -Be 1 -Because $s
            @($all | Where-Object { $_ -match 'ohne „-Skip Prozesse“ wiederholen' -and $_ -match 'Start-WorkerPerfCapture\.ps1' }).Count | Should -Be 1 -Because $s
            # nothing about a cause that was not measured
            @(Get-GuideTexts $g | Where-Object { $_ -match 'EXCEL|user003' }).Count | Should -Be 0 -Because $s
        }
    }
    It 'sagt bei einer Verzoegerung ohne erkannten Engpass, dass Laufwerke und Dateiserver nicht gemessen sind' {
        foreach ($n in 1, 3) {
            $inc = New-Inc @{ type = 'ohne-engpass'; unverified = $true; affected = @(1..$n | ForEach-Object { @{ s = $_ } }) }
            $g = Get-Guide $inc
            $hit = @($g.checks | Where-Object { ($_.text + $_.sign) -match 'nicht gemessen' -and ($_.text + $_.sign) -match 'Laufwerk' -and ($_.text + $_.sign) -match 'nicht ausgeschlossen' })
            $hit.Count | Should -BeGreaterThan 0 -Because "$n Sitzungen"
            # title and texts never claim that the server had no bottleneck
            foreach ($t in @($g.title, $g.meaning, $g.impact)) { $t | Should -Not -Match 'nicht ausgelastet' }
            @((Get-Guide (New-Inc @{ type = 'ohne-engpass'; affected = @(1..$n | ForEach-Object { @{ s = $_ } }) })).checks | Where-Object { ($_.text + $_.sign) -match 'nicht ausgeschlossen' }).Count | Should -Be 0
        }
    }
    It 'empfiehlt zum Virenscan und zur Schutzsoftware nur, was der Vorfall stuetzt' {
        $words = 'Scan|Schutzsoftware|Defender|AppLocker'
        foreach ($s in 'cpu', 'memory', 'disk', 'share', 'profile') {
            # a named application, no scan, no protection software, no event: no word about them
            @(Get-GuideTexts (Get-Guide (New-Engpass $s)) | Where-Object { $_ -match $words }) | Should -Be @() -Because $s
            # the protection software as the largest consumer during a scan: schedule and exclusions
            $g = Get-Guide (New-Engpass $s @{ cause = @{ kind = 'security'; security = @{ label = 'Die Schutzsoftware'; sharePct = 40 } }; main = $null; scanActive = $true })
            @($g.checks | Where-Object { $_.text -match 'Die Schutzsoftware' }).Count | Should -BeGreaterThan 0 -Because $s
            # a scan does not explain a memory shortage: schedule and exclusions belong to the other four resources
            $scanMatters = $s -ne 'memory'
            @(@($g.checks) + @($g.remedies) | Where-Object { ($_.text + $_['sign'] + $_['precondition']) -match 'Zeitplan' }).Count -gt 0 | Should -Be $scanMatters -Because $s
            # the scan comes first then, the exclusions second (README: schedule with a scan in the window, else exclusions)
            if ($scanMatters) { $g.checks[0].text | Should -Match 'Virenscan' -Because $s; $g.checks[1].text | Should -Match 'Die Schutzsoftware' -Because $s }
            # without a scan in the window nothing about its schedule
            $g = Get-Guide (New-Engpass $s @{ cause = @{ kind = 'security'; security = @{ label = 'Die Schutzsoftware'; sharePct = 40 } }; main = $null })
            @(@($g.checks) + @($g.remedies) | Where-Object { $_.text -match 'Zeitplan|Virenscan' }).Count | Should -Be 0 -Because $s
            @(@($g.checks) + @($g.remedies) | Where-Object { ($_.text + $_['sign'] + $_['precondition']) -match 'Ausschl' }).Count -gt 0 | Should -Be $scanMatters -Because $s
            $g.checks[0].text | Should -Match 'Die Schutzsoftware' -Because $s
        }
    }
    It 'nennt eine langsame Gegenstelle nur, wenn sie im Fenster langsam war' {
        $fast = @(@{ name = 'Sim-DB'; maxMs = 7; failed = $false }); $slow = @(@{ name = 'Sim-DB'; maxMs = 340; failed = $false }); $down = @(@{ name = 'Sim-DB'; maxMs = $null; failed = $true })
        foreach ($s in 'delay.many', 'delay.single') {
            $n = $(if ($s -eq 'delay.many') { 3 } else { 1 })
            $inc = { param($e) New-Inc @{ type = 'ohne-engpass'; affected = @(1..$n | ForEach-Object { @{ s = $_ } }); endpoints = $e } }
            @(Get-GuideTexts (Get-Guide (& $inc $fast)) | Where-Object { $_ -match 'Sim-DB' }) | Should -Be @() -Because $s
            (Get-Guide (& $inc $slow)).checks[0].text | Should -Match 'Sim-DB' -Because $s
            # an endpoint that only failed has no response time: the step still names it
            (Get-Guide (& $inc $down)).checks[0].text | Should -Match 'Sim-DB' -Because $s
        }
    }
    It 'stellt die Anleitung eines Druckproblems mit HP-Treiber in der Druckwarteschlange zusammen' {
        $inc = New-Inc @{ type = 'ereignis'; start = [long]1e12; end = [long]1e12; event = @{ kind = 'print'; key = 'Sim PCL 6'; app = 'spoolsv.exe'; driver = 'Sim PCL 6'; noUserSession = $true
                patterns = @(@{ id = 'printdriver'; detail = @{ module = 'hpsimgr.dll'; driver = 'Sim PCL 6' } }); modules = @(@{ name = 'hpsimgr.dll'; count = 1 }) }
            events = @(@{ app = 'spoolsv.exe'; kind = 'crash'; log = 'application' }) }
        $g = Get-Guide $inc
        $g.conditions | Should -Be @('pattern.printdriver', 'driver.v3', 'driver.shared', 'driver.vendor.HP', 'spooler.crash', 'queue.stuck')
        # the first step asks whether the service runs again; the step for the driver does not name the module (the
        # incident's own sentence does): the value of {module} is the most frequent module, not the one of the pattern
        $g.checks[0].text | Should -Match 'Dienst „Druckwarteschlange“ wieder läuft'; $g.checks[1].text | Should -Match 'Druckertreiber'
        @(Get-GuideTexts $g | Where-Object { $_ -match 'hpsimgr' }) | Should -Be @()
        @($g.remedies | Where-Object { $_.text -match 'Sim PCL 6' }).Count | Should -BeGreaterThan 0
        $vendors = @(@($g.checks) + @($g.remedies) + @($g.contacts) | ForEach-Object { ($_.source -split ': ', 2)[0] } | Sort-Object -Unique)
        $vendors | Should -Be @('Citrix', 'HP', 'Microsoft')
        # an isolated type 4 driver of another vendor without a crash and without stuck queues: none of those variants
        $ctx = New-Ctx; $ctx.Data.print.drivers = @(@{ name = 'Sim PCL 6'; manufacturer = 'Acme'; type = 4; isolation = 'isolated' }); $ctx.Data.print.queues = @()
        $quiet = Get-Guide (New-Inc @{ type = 'ereignis'; event = @{ kind = 'print'; key = 'Sim PCL 6'; driver = 'Sim PCL 6' } }) $ctx
        $quiet.conditions | Should -Be @('pattern.none', 'driver.v4', 'driver.isolated')
        @(@($quiet.checks) + @($quiet.remedies)).Count | Should -BeLessThan (@($g.checks) + @($g.remedies)).Count
        @(@($quiet.checks) + @($quiet.remedies) | Where-Object { $_.text -match 'hpsimgr' }).Count | Should -Be 0
    }
    It 'sagt beim Druckproblem ohne gemessene Treiber und Warteschlangen, dass der Treiberbezug nicht geprueft ist' {
        $ctx = New-Ctx; $ctx.Data.print = @{ drivers = @(); queues = @() }; $ctx.Data.skipped = @(@{ id = 'Drucken'; label = 'Drucken'; text = ''; places = @() })
        $inc = New-Inc @{ type = 'ereignis'; event = @{ kind = 'print'; key = 'Microsoft-Windows-PrintService'; app = 'spoolsv.exe'; modules = @(@{ name = 'hpsimgr.dll'; count = 1 })
                unchecked = @(@{ id = 'printdriver'; category = 'Drucken' }) }; events = @(@{ app = 'spoolsv.exe'; kind = 'crash'; log = 'application' }) }
        $g = Get-Guide $inc $ctx
        $g.conditions | Should -Contain 'skipped.Drucken'; $g.conditions | Should -Contain 'pattern.unchecked'
        @($g.checks | Where-Object { $_.text -match 'Nicht gemessen' -and $_.text -match 'Treiber' }).Count | Should -BeGreaterThan 0
        foreach ($e in @($g.checks) + @($g.remedies) + @($g.contacts)) { [string]$e.source | Should -Not -BeNullOrEmpty -Because $e.text }
    }
    It 'nennt kein System des Auftraggebers' {
        # the labels of the customer's main application and protection software stand in src/roles.json; the catalogue
        # says "die Fachanwendung" and "die Schutzsoftware" (products of Microsoft and Citrix may be named)
        $raw = [IO.File]::ReadAllText($CatalogueFile, [Text.Encoding]::UTF8)
        $roles = (ConvertFrom-WorkerPerfJsonFile (Join-Path $PSScriptRoot '../src/roles.json')).roles
        $labels = @($roles | Where-Object { $_.role -eq 'Hauptanwendung' -or ($_.role -eq 'Sicherheit' -and $_.label -notmatch '^(Microsoft|AppLocker)') } | ForEach-Object { [string]$_.label })
        $labels.Count | Should -BeGreaterThan 0
        foreach ($label in $labels) {
            $raw | Should -Not -Match ([regex]::Escape($label)) -Because $label
            $first = ($label -split '[ -]')[0]
            if ($first.Length -ge 5) { $raw | Should -Not -Match ('(?i)\b' + [regex]::Escape($first) + '\b') -Because $first }
        }
        $own = @($roles | Where-Object { $labels -contains [string]$_.label })
        foreach ($p in @($own | ForEach-Object { @($_.processes) + @($_.services) } | Where-Object { $_ -and $_ -notmatch '[*?]' })) { $raw | Should -Not -Match ([regex]::Escape($p)) -Because $p }
    }
    It 'schreibt Elemente als Stichpunkte ohne Schlusspunkt und Abhilfen so, dass sie auf "Wenn ...:" folgen' {
        foreach ($e in $Elements) {
            foreach ($t in $e.Texts) { $t | Should -Not -Match '[.:;,]\s*$' -Because $e.Position; $t | Should -Not -Match '^\s|\s$|\s{2,}' -Because $e.Position }
        }
        foreach ($s in $WorkerPerfSituations) {
            foreach ($m in @($Real.situations.$s.remedies)) {
                # "Wenn <precondition>: <text>": the precondition is a clause without its "Wenn" and starts in lower case
                # (or with a value or a name); the text starts with a noun, a name or a value, so it also follows ", dann"
                $m.precondition | Should -Not -Match '^(Wenn|Falls|Sofern)\b' -Because $m.text
                $m.precondition | Should -Not -Match ';' -Because $m.text                                     # one condition, no remark
                $m.text | Should -Not -Match ':' -Because $m.text                                             # it follows "Wenn ...:"
                $m.text | Should -MatchExactly '^(\p{Lu}|\{|„)' -Because $m.text
                $m.text | Should -Not -MatchExactly '^(Der|Die|Das|Den|Dem|Des|Ein|Eine|Einen|Einem|Einer|Bei|Im|In|Auf|Mit|Nach|Vor|Für|Wenn|Falls)\b' -Because $m.text
            }
        }
    }
    It 'beschreibt jede Situation mit Titel, Kuerzel, zwei bis drei Saetzen zur Bedeutung und einem Satz zur Wirkung' {
        $ends = '[.!?](?=\s|$)'
        $short = @{}
        foreach ($s in $WorkerPerfSituations) {
            $e = $Real.situations.$s
            $e.title | Should -Not -Match '[.:;,!?]$' -Because $s; $e.title.Length | Should -BeLessOrEqual 60 -Because $s
            $e.short | Should -Match '^\p{L}[\p{L}-]{1,11}$' -Because $s
            ([regex]::Matches($e.meaning, $ends)).Count | Should -BeIn @(2, 3) -Because "$s meaning"
            ([regex]::Matches($e.impact, $ends)).Count | Should -Be 1 -Because "$s impact"
            $e.meaning | Should -Match '\.$' -Because $s; $e.impact | Should -Match '\.$' -Because $s
            # a chronic state says first how long it lasted and that it may have lasted the whole capture (spec 4; a
            # chronic state is a finding of more than 15 minutes, so the sentence claims no more than that)
            if ($s -like 'chronic.*') { $e.meaning | Should -Match '^Über längere Zeit \(\{duration\}\), möglicherweise über die ganze Messung, ' -Because $s }
        }
        # titles tell the situations apart on cards and in groups
        @($WorkerPerfSituations | ForEach-Object { $Real.situations.$_.title } | Sort-Object -Unique).Count | Should -Be $WorkerPerfSituations.Count
    }
    It 'spricht beim Dauerzustand von <Lead> ueber diese Ressource und ueber keine andere' -ForEach @(           # ruling P3-R37
        @{ Lead = 'cpu'; Want = 'Prozessor'; Other = 'Arbeitsspeicher der virtuellen Maschine|Dateiserver|Speichersystem|Profilspeicher' }
        @{ Lead = 'memory'; Want = 'Arbeitsspeicher'; Other = 'Prozessor|Dateiserver|Speichersystem|Profilspeicher' }
        @{ Lead = 'disk'; Want = 'Speichersystem'; Other = 'Prozessor|Auslegung des Servers|Bereitstellungsgruppe|Dateiserver' }
        @{ Lead = 'share'; Want = 'Dateiserver'; Other = 'Prozessor|Auslegung des Servers|Bereitstellungsgruppe|Speichersystem unter' }
        @{ Lead = 'profile'; Want = 'Profilspeicher'; Other = 'Prozessor|Auslegung des Servers|Bereitstellungsgruppe|Speichersystem unter' }
    ) {
        $label = @{ disk = 'Laufwerk D:'; share = 'Freigabe \\sim-fs\daten'; profile = 'Profilcontainer von user003 (\\sim-fs\profile$)' }
        foreach ($kind in 'none', 'nodata', 'notmeasured') {
            $g = Get-Guide (New-Engpass $Lead @{ chronic = $true; end = [long](1e12 + 4200000); cause = @{ kind = $kind }; main = $null })
            $g.situation | Should -Be 'chronic.resource'; $g.conditions | Should -Contain "lead.$Lead"
            $steps = @(@($g.checks) + @($g.remedies) + @($g.contacts) | ForEach-Object { $_.text })
            @($steps | Where-Object { $_ -match $Want }).Count | Should -BeGreaterThan 0 -Because $kind
            @($steps | Where-Object { $_ -match $Other }) | Should -Be @() -Because $kind
            # a drive, a share and a profile container are named; the processor and the memory have no name
            if ($label.ContainsKey($Lead)) { @($g.checks | Where-Object { $_.text.Contains($label[$Lead]) }).Count | Should -Be 1 -Because $kind }
        }
        # a named cause is asked about whatever the resource
        $g = Get-Guide (New-Engpass $Lead @{ chronic = $true; end = [long](1e12 + 4200000) })
        $g.checks[0].text | Should -Match 'EXCEL\.EXE in der Sitzung von user003'
        # title, meaning and impact do not decide which resource it is
        $e = $Real.situations.'chronic.resource'
        $e.title | Should -Be 'Server dauerhaft über dem Soll'
        $e.meaning | Should -Match 'Prozessor, Arbeitsspeicher, ein Laufwerk, eine Freigabe oder ein Profilcontainer'
        $e.meaning | Should -Match 'bei Laufwerk, Freigabe und Profilcontainer antwortet der Speicher dahinter'
        $e.impact | Should -Not -Match 'Der Server reagiert'
    }
    It 'nennt in keinem Schritt ein Modul beim Namen' {                                                         # fix round 1, A2
        # the value of {module} is the most frequent module of the incident, each pattern has its own: no text uses it
        @($Elements | Where-Object { ($_.Texts -join ' ') -match '\{module\}' }) | Should -Be @()
        $inc = New-Inc @{ type = 'ereignis'; event = @{ kind = 'crash'; app = 'EXCEL.EXE'; users = @('user003'); sessions = @(3); count = 4
                modules = @(@{ name = 'KERNELBASE.dll'; count = 3 }, @{ name = 'hpsim.dll'; count = 1 })
                patterns = @(@{ id = 'sharedmodule'; detail = @{ module = 'simaddin.dll' } }, @{ id = 'printdriver'; detail = @{ module = 'hpsim.dll'; driver = 'Sim PCL 6' } },
                    @{ id = 'securitymodule'; detail = @{ module = 'simscan.dll' } }) } }
        (Get-WorkerPerfGuidanceFacts -Incident $inc -Context (New-Ctx) -Catalogue $Real).Values.module | Should -Be 'KERNELBASE.dll'
        $g = Get-Guide $inc
        foreach ($p in 'gehört zu einem installierten Druckertreiber', 'gehört zur Schutzsoftware', 'bei mehreren Anwendungen die Absturzstelle') {
            @($g.checks | Where-Object { $_.text -match $p }).Count | Should -Be 1 -Because $p
        }
        @(Get-GuideTexts $g | Where-Object { $_ -match 'KERNELBASE|hpsim|simaddin|simscan' }) | Should -Be @()
    }
    It 'schlaegt beim Begleiter bei <S> den Scan-Ausschluss fuer den groessten I/O-Erzeuger vor, nicht fuer den Hauptverursacher' -ForEach @(      # fix round 1, A3
        @{ S = 'cpu' }; @{ S = 'disk' }; @{ S = 'share' }; @{ S = 'profile' }
    ) {
        $g = Get-Guide (New-Engpass $S @{ companion = @{ label = 'Microsoft Defender'; sharePct = 25 } })
        $about = @(@($g.checks) + @($g.remedies) | Where-Object { ($_.text + $_['sign'] + $_['precondition']) -match 'Ausschl|untersucht' })
        $about.Count | Should -Be 2
        foreach ($e in $about) {
            ($e.text + $e['where'] + $e['sign'] + $e['precondition']) | Should -Not -Match 'EXCEL|user003'
            ($e.text + $e['where']) | Should -Match 'größte[rn] I/O-Erzeuger'
        }
        foreach ($e in @($Elements | Where-Object { $_.When -contains 'companion.security' })) { ($e.Texts -join ' ') | Should -Not -Match '\{app\}|\{user\}' -Because $e.Position }
    }
    It 'beschreibt beim Arbeitsspeicher und beim Prozessor, was gemessen wurde' {                                 # fix round 1, A4
        foreach ($s in 'memory', 'cpu') { $Real.situations.$s.meaning | Should -Match '^Ab \{from\} Uhr lag die Auslastung .{10,30} \{duration\} lang über dem Soll\. ' -Because $s }
        $Real.situations.memory.meaning | Should -Not -Match 'vollständig belegt'; $Real.situations.cpu.meaning | Should -Not -Match 'warten mussten'
        $g = Get-Guide (New-Engpass 'memory' @{ cause = @{ kind = 'none' }; main = $null })
        @($g.checks | Where-Object { $_.text -match 'tatsächlich ausgelagert' -and $_.where -match 'Von Datenträger gelesene Seiten' }).Count | Should -Be 1
        @($g.checks | Where-Object { $_.sign -match 'nahe am Arbeitsspeicher' }) | Should -Be @()
    }
    It 'schlaegt die Isolierung eines Treibers nur nach einem Test und vor dem Entfernen des Treibers vor' {       # fix round 1, A5
        $remedies = @($Real.situations.print.remedies)
        $iso = @($remedies | Where-Object { $_.text -match 'Isolierung „isoliert“' })
        $iso.Count | Should -Be 1
        # the condition of the source: able to run in a process of its own, faults or leaks, disturbs other drivers there
        $iso[0].precondition | Should -Match 'in einem eigenen Prozess lauffähig'; $iso[0].precondition | Should -Match 'andere Treiber im selben Prozess stört'
        $iso[0].precondition | Should -Match 'zuerst auf einem Testserver geprüft'; $iso[0].precondition | Should -Not -Match 'Druckwarteschlange'
        $texts = @($remedies | ForEach-Object { $_.text })
        $remove = @($texts | Where-Object { $_ -match '^Treiber \{driver\} entfernen' }); $remove.Count | Should -Be 1
        [array]::IndexOf($texts, $iso[0].text) | Should -BeLessThan ([array]::IndexOf($texts, $remove[0]))
    }
    It 'nennt fuer die Dienstabhaengigkeit und den HP-Anschluss nur, was die Quelle traegt' {                     # fix round 1, A6, A7
        $spool = @($Real.situations.print.checks | Where-Object { $_.where -match 'DependOnService' })
        $spool.Count | Should -Be 1
        $spool[0].sign | Should -Not -Match 'neben RpcSs'; $spool[0].sign | Should -Match 'den ein Server ohne Druckproblem nicht hat'
        $hp = @($Real.situations.print.checks | Where-Object { $_.text -match 'SNMP' })
        $hp.Count | Should -Be 1
        $hp[0].text | Should -Match 'mit dem HP Universal Print Driver und dem Status „Offline“'; $hp[0].text | Should -Not -Match 'Fehlern'
        $hp[0].sign | Should -Match 'für den HP Universal Print Driver laut HP'
        @($hp[0].when) | Should -Be @('queue.stuck', 'driver.vendor.HP')
    }
    It 'formuliert die eigenen Hinweise der Auswertung nicht als Empfehlung eines Herstellers' {                  # ruling P3-R35
        $own = @($Elements | Where-Object { $_.Source -ceq $OwnSource })
        foreach ($e in $own) { ($e.Texts -join ' ') | Should -Not -MatchExactly 'Microsoft|Citrix|HP|Kyocera|Brother|\blaut\b|empfiehlt|empfohlen|Empfehlung' -Because $e.Position }
        # no vendor's page stands for a case it does not name: not measured, not checked, before the capture, the patterns
        $ownCases = 'skipped.Drucken', 'pattern.unchecked', 'before', 'pattern.resource', 'pattern.companion', 'pattern.overlap', 'pattern.oneuser', 'pattern.securitymodule'
        foreach ($e in @($Elements | Where-Object { $_.Situation -eq 'print' -and @($_.When | Where-Object { $_ -in $ownCases }).Count -gt 0 })) {
            $e.Source | Should -BeExactly $OwnSource -Because $e.Position
        }
        # a print failure with every pattern of its own: five notes, each with the own source
        $inc = New-Inc @{ type = 'ereignis'; event = @{ kind = 'print'; key = 'Sim PCL 6'; app = 'spoolsv.exe'; users = @('user003'); sessions = @(3); count = 3
                patterns = @(@{ id = 'resource'; detail = @{} }, @{ id = 'securitymodule'; detail = @{} }, @{ id = 'oneuser'; detail = @{} }, @{ id = 'companion'; detail = @{} },
                    @{ id = 'overlap'; detail = @{} }) }; events = @(@{ app = 'spoolsv.exe'; kind = 'crash'; log = 'application' }) }
        $g = Get-Guide $inc
        $notes = @($g.checks | Where-Object { $_.source -ceq $OwnSource })
        $notes.Count | Should -Be 5
        @($notes | Where-Object { $_.text -match 'user003' }).Count | Should -Be 1
        @($notes | Where-Object { $_.text -match 'Leistungsvorfalls: auch dessen Anleitung ansehen' }).Count | Should -Be 1
        # the service comes first, the coincidence in time after the patterns that say more
        $g.checks[0].text | Should -Match 'Dienst „Druckwarteschlange“ wieder läuft'
        $order = @($notes | ForEach-Object { $_.text.Substring(0, 12) })
        [array]::IndexOf($order, 'Der Druckfeh') | Should -BeGreaterThan ([array]::IndexOf($order, 'Speichermang'))
    }
    It 'stellt bei <S> das Zusammentreffen mit einem Leistungsvorfall hinter die Muster, die mehr sagen' -ForEach @(      # fix round 1, B4
        @{ S = 'crash' }; @{ S = 'hang' }; @{ S = 'service' }; @{ S = 'print' }; @{ S = 'profileerror' }; @{ S = 'system' }
    ) {
        $checks = @($Real.situations.$S.checks)
        $when = @($checks | ForEach-Object { if ($_.PSObject.Properties['when']) { @($_.when) -join ',' } else { '' } })
        $at = [array]::IndexOf($when, 'pattern.overlap'); $at | Should -BeGreaterThan -1
        $checks[$at].text | Should -Match 'auch dessen Anleitung ansehen, beide können dieselbe Ursache haben$'
        $checks[$at].text | Should -Not -Match 'zuerst'
        foreach ($p in 'resource', 'afterhang', 'sharedmodule', 'printdriver', 'securitymodule', 'manyusers', 'oneuser') {
            $k = [array]::IndexOf($when, "pattern.$p")
            if ($k -ge 0) { $k | Should -BeLessThan $at -Because $p }
        }
    }
    It 'stellt die Schritte zu nicht Gemessenem hinter die allgemeinen und sagt eine Luecke einmal' {             # ruling P3-R36
        $ctx = New-Ctx; $ctx.Data.skipped = @(@{ id = 'Prozesse'; label = 'Prozesse'; text = ''; places = @() }); $ctx.Data.apps = @()
        foreach ($s in 'cpu', 'memory', 'disk', 'share', 'profile') {
            $g = Get-Guide (New-Engpass $s @{ cause = @{ kind = 'notmeasured' }; main = $null }) $ctx
            $general = @($Real.situations.$s.checks | Where-Object { -not $_.PSObject.Properties['when'] } | ForEach-Object { $_.text })
            $g.checks[0].text | Should -Be $general[0] -Because $s
            @(@($g.checks) + @($g.remedies) | Where-Object { $_.text -match 'nicht gemessen' }).Count | Should -Be 1 -Because $s
            # the two steps for the cause that was not measured are the last ones
            $last = @($g.checks | Select-Object -Last 2 | ForEach-Object { $_.text })
            $last[0] | Should -Match 'der Verursacher wurde nicht gemessen' -Because $s; $last[1] | Should -Match 'ohne „-Skip Prozesse“ wiederholen' -Because $s
        }
        # a delay whose bottleneck check was incomplete and whose endpoints were not measured: two gaps, each said once
        $ctx = New-Ctx; $ctx.Data.sollIst = @(@{ id = 'probe.connect'; measured = $false })
        $ctx.Data.skipped = @(@{ id = 'Laufwerke'; label = 'Laufwerke'; text = ''; places = @() }, @{ id = 'Gegenstellen'; label = 'Gegenstellen'; text = ''; places = @() })
        foreach ($n in 1, 3) {
            $g = Get-Guide (New-Inc @{ type = 'ohne-engpass'; unverified = $true; affected = @(1..$n | ForEach-Object { @{ s = $_ } }) }) $ctx
            $g.checks[0].text | Should -Match '^Feststellen, in welcher Anwendung' -Because "$n Sitzungen"
            $texts = @(@($g.checks) + @($g.remedies) | ForEach-Object { $_.text })
            @($texts | Where-Object { $_ -match 'Antwortzeit der Gegenstellen wurde nicht gemessen' }).Count | Should -Be 1 -Because "$n Sitzungen"
            @($texts | Where-Object { $_ -match 'nicht gemessen' }).Count | Should -Be 2 -Because "$n Sitzungen"
            # the remedy that fills the gap comes after the general remedies
            if ($n -eq 1) { $g.remedies[-1].text | Should -Match 'ohne „-Skip Gegenstellen“ wiederholen' }
        }
    }
    It 'nennt bei Abhilfen, die alle Benutzer treffen, das Wartungsfenster oder was verloren geht' {              # fix round 1, B4
        $disruptive = 'entfernen|deinstallieren|Server neu starten|anhalten|zurücksetzen|Spool-Ordner von Hand leeren|Sitzung.*beenden|chkdsk'
        $care = 'Wartungsfenster|Benutzer des Servers informiert|Rücksprache|gesichert'
        $hit = @($Elements | Where-Object { $_.List -eq 'remedies' -and $_.Texts[0] -match $disruptive })
        $hit.Count | Should -BeGreaterThan 10
        foreach ($e in $hit) { ($e.Texts -join ' ') | Should -Match $care -Because $e.Position }
        # what all users lose is said where a remedy empties the spool folder or restarts the service
        foreach ($e in @($Elements | Where-Object { $_.List -eq 'remedies' -and $_.Texts[0] -match 'Dienst „Druckwarteschlange“ (anhalten|zurücksetzen)' })) {
            $e.Texts[0] | Should -Match 'aller Benutzer des Servers verloren|alle Benutzer des Servers kurz nicht drucken' -Because $e.Position
        }
    }
    It 'schickt niemanden zur Betreuung einer Gegenstelle, bevor deren eigene Messwerte verglichen sind' {         # fix round 1, B4
        foreach ($e in @($Elements | Where-Object { $_.List -eq 'checks' -and $_.When -contains 'endpoint.slow' -and $_.Texts[0] -match 'Betreuung' })) {
            $e.Texts[0] | Should -Match 'zuerst ihre Antwortzeit vor und nach dem Vorfall vergleichen, dann' -Because $e.Position
        }
        $Real.situations.fallback.checks[2].text | Should -Match 'mit dem Rest der Messung vergleichen, dann'
    }
    It 'nennt eine Zeitspanne so, dass sie auch bei gleichem Beginn und Ende stimmt' {                             # fix round 1, B7
        @($Elements | Where-Object { ($_.Texts -join ' ') -match 'zwischen \{from\} und \{to\}|von \{from\} bis \{to\}' }) | Should -Be @()
        # incidents of two seconds inside one minute, with every element that names a time
        $ctx = New-Ctx; $ctx.Data.sollIst = @(@{ id = 'probe.connect'; measured = $false }, @{ id = 'input.session'; measured = $false })
        $ctx.Data.skipped = @(@{ id = 'Ereignisse'; label = 'Ereignisse'; text = ''; places = @() }, @{ id = 'Laufwerke'; label = 'Laufwerke'; text = ''; places = @() })
        $short = @{ start = [long](1e12 + 600000); end = [long](1e12 + 602000) }
        $slow = @(@{ name = 'Sim-DB'; maxMs = 340; failed = $false })
        $cases = @(
            (New-Inc (@{ type = 'ohne-engpass'; unverified = $true; scanActive = $true; affected = @(@{ s = 1 }); endpoints = $slow } + $short))
            (New-Inc (@{ type = 'ohne-engpass'; unverified = $true; scanActive = $true; affected = @(@{ s = 1 }, @{ s = 2 }); endpoints = $slow } + $short))
        ) + @(foreach ($s in 'cpu', 'memory', 'disk', 'share', 'profile') { New-Engpass $s (@{ scanActive = $true } + $short) })
        $times = 0
        foreach ($inc in $cases) {
            $g = Get-Guide $inc $ctx
            foreach ($t in (Get-GuideTexts $g)) {
                $t | Should -Not -Match '(\d\d:\d\d) (und|bis) \1' -Because $g.situation
                if ($t -match '02:56') { $times++ }
            }
        }
        $times | Should -BeGreaterThan 15
    }
}

Describe 'Katalog an der simulierten Stunde ohne Prozesse' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        $script:Real = Read-WorkerPerfGuidance $script:CatalogueFile
        # one hour recorded with -Skip Prozesse and its report data as the report script builds them (dot-sourced in a child
        # scope, which keeps $data); the names below are not used by the report script
        $catSimRun = Invoke-SimCapture (Join-Path $TestDrive 'sim') @{ Skip = @('Prozesse') }
        $catSimRoles = New-SimRoleFile (Join-Path $TestDrive 'roles.sim.json')
        $catSimReport = Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1'
        $script:SimData = & { $null = . $catSimReport -Path $catSimRun -OutFile (Join-Path $TestDrive 'report.html') -RoleFile $catSimRoles 6>$null; $data }
        $script:SimCtx = @{ Data = $SimData; Thresholds = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json'); OffsetMinutes = [int]$SimData.meta.offsetMin; Texts = $script:Texts }
        $script:UsersStep = 'Betroffene Benutzer über ihre Meldungen feststellen: Prozesse wurden nicht gemessen'
        function Get-SimGuide($Incident) { Get-Guide $Incident $script:SimCtx }
    }
    It 'sagt bei einem Vorfall vor der Messung nicht, die Benutzer seien nicht geprueft' {                         # fix round 1, A8
        $before = @($SimData.before.incidents)
        $before.Count | Should -Be 4
        # three crashes whose record names the user, one without an account: none of them is mapped through processes
        @($before | Where-Object { @($_.event.users).Count -gt 0 }).Count | Should -Be 3
        foreach ($inc in $before) {
            $g = Get-SimGuide $inc
            $g.conditions | Should -Contain 'skipped.Prozesse' -Because "Vorfall $($inc.id)"; $g.conditions | Should -Contain 'before' -Because "Vorfall $($inc.id)"
            @(Get-GuideTexts $g | Where-Object { $_ -match 'Prozesse wurden nicht gemessen|nicht geprüft' }) | Should -Be @() -Because "Vorfall $($inc.id): $($inc.text)"
            # the step for an incident before the capture starts with what to do; the user's view says that there are no values
            @($g.checks | Where-Object { $_.text -match '^Prüfen, ob der Absturz seit Beginn der Messung wieder aufgetreten ist$' }).Count | Should -Be 1 -Because "Vorfall $($inc.id)"
            @($g.checks | Where-Object { $_.text -match 'liegen keine Messwerte vor' }) | Should -Be @() -Because "Vorfall $($inc.id)"
            $g.userView | Should -Match 'liegen keine Messwerte vor'
        }
    }
    It 'sagt bei einem Absturz der Messzeit ohne zugeordnete Benutzer genau einmal, warum' {                        # fix round 1, A8
        $crashes = @($SimData.incidents | Where-Object { $_.type -eq 'ereignis' -and $_.event.kind -eq 'crash' })
        $crashes.Count | Should -Be 2
        foreach ($inc in $crashes) {
            @($inc.event.unchecked | ForEach-Object { $_.id }) | Should -Contain 'users' -Because "Vorfall $($inc.id)"
            $g = Get-SimGuide $inc
            @($g.checks | Where-Object { $_.text.StartsWith($UsersStep) }).Count | Should -Be 1 -Because "Vorfall $($inc.id)"
            @(@($g.checks) + @($g.remedies) | Where-Object { $_.text -match 'Prozesse wurden nicht gemessen' }).Count | Should -Be 1 -Because "Vorfall $($inc.id)"
            # the step that a pattern was not checked comes last and does not give the reason a second time
            $g.checks[-1].text | Should -Match 'mindestens ein Muster wurde nicht geprüft; welches und warum, steht bei der Ursache$' -Because "Vorfall $($inc.id)"
        }
    }
    It 'stellt fuer jeden Vorfall eine vollstaendige Anleitung zusammen, die Schritte zum nicht gemessenen Verursacher zuletzt' {
        $all = @(@($SimData.incidents) + @($SimData.before.incidents))
        $all.Count | Should -Be 16
        foreach ($inc in $all) {
            $g = Get-SimGuide $inc
            foreach ($k in 'title', 'tech', 'meaning', 'impact', 'userView', 'short') { [string]$g[$k] | Should -Not -BeNullOrEmpty -Because "Vorfall $($inc.id): $k" }
            @($g.checks).Count | Should -BeGreaterThan 0 -Because "Vorfall $($inc.id)"
            foreach ($t in (Get-GuideTexts $g)) { $t | Should -Not -Match '[{}]' -Because "Vorfall $($inc.id)" }
        }
        foreach ($inc in @($SimData.incidents | Where-Object { $_.type -eq 'engpass' })) {
            $g = Get-SimGuide $inc
            $g.conditions | Should -Contain 'cause.notmeasured' -Because "Vorfall $($inc.id)"; $g.conditions | Should -Contain ('lead.' + $inc.lead) -Because "Vorfall $($inc.id)"
            $g.checks[0].text | Should -Not -Match 'nicht gemessen' -Because "Vorfall $($inc.id)"
            $g.checks[-1].text | Should -Match 'ohne „-Skip Prozesse“ wiederholen' -Because "Vorfall $($inc.id)"
        }
    }
}

Describe 'Nachweis der Druckempfehlungen' {
    BeforeAll {
        $script:Real = Read-WorkerPerfGuidance $script:CatalogueFile
        $script:Sourced = @(Get-Elements $script:Real | Where-Object { $_.Source })
        $script:Rows = @(Get-SourceRows $script:SourcesFile)
        $script:Doc = [IO.File]::ReadAllText($script:SourcesFile, [Text.Encoding]::UTF8)
    }
    It 'fuehrt jedes Element mit Quelle an seiner Stelle unter seinem Dokument' {
        $Sourced.Count | Should -BeGreaterThan 20
        $listed = @{}
        foreach ($row in $Rows) { foreach ($p in $row.Positions) { $listed[$p] = "$($row.Vendor): $($row.Title)" } }
        foreach ($e in $Sourced) {
            $listed.ContainsKey($e.Position) | Should -BeTrue -Because "$($e.Position) fehlt im Nachweis"
            $listed[$e.Position] | Should -BeExactly $e.Source -Because $e.Position
        }
    }
    It 'nennt im Nachweis keine Stelle, die der Katalog nicht hat, und keine doppelt' {
        $bySource = @{}; foreach ($e in $Sourced) { $bySource[$e.Position] = $e.Source }
        $seen = @{}
        foreach ($row in $Rows) {
            foreach ($p in $row.Positions) {
                $bySource.ContainsKey($p) | Should -BeTrue -Because "$p steht im Nachweis, aber nicht im Katalog"
                $bySource[$p] | Should -BeExactly "$($row.Vendor): $($row.Title)" -Because $p
                $seen.ContainsKey($p) | Should -BeFalse -Because "$p steht zweimal im Nachweis"; $seen[$p] = $true
            }
            # a note speaks only about elements of its own row
            foreach ($p in $row.Noted) { $row.Positions | Should -Contain $p -Because "Hinweis zu $($row.Title)" }
            if ($row.Vendor -eq 'WorkerPerf') { continue }
            $row.Line | Should -Match 'https://' -Because $row.Title
            $row.Line | Should -Match '2026-11-13' -Because $row.Title
        }
    }
    It 'fuehrt die eigenen Hinweise der Auswertung in einem Abschnitt und sagt, was auf dem Zielsystem zu bestaetigen ist' {      # ruling P3-R35, item B5
        $own = @($Rows | Where-Object { $_.Vendor -eq 'WorkerPerf' })
        $own.Count | Should -Be 1; $own[0].Title | Should -Be 'Hinweis zur Auswertung'
        @($own[0].Positions | Sort-Object) | Should -Be @($Sourced | Where-Object { $_.Source -ceq $OwnSource } | ForEach-Object { $_.Position } | Sort-Object)
        $Doc | Should -Match '(?m)^## Auf dem Zielsystem zu bestätigen$'
        $at = $Doc.IndexOf("`n## Auf dem Zielsystem zu bestätigen`n")
        $section = $Doc.Substring($at)
        # every position the list names exists in the catalogue
        $all = @(Get-Elements $Real | ForEach-Object { $_.Position })
        $named = @(Get-Positions $section); $named.Count | Should -BeGreaterThan 3
        foreach ($p in $named) { $all | Should -Contain $p }
        foreach ($word in 'DependOnService', 'Betriebsbereit', 'PrintDriverIsolationOverrideCompat', 'temporäres Profil') { $section | Should -Match ([regex]::Escape($word)) }
    }
    It 'fuehrt die veralteten Empfehlungen unter Nicht aufgenommen statt im Katalog' {                                            # ruling P3-R38
        @($Sourced | Where-Object { $_.Source -match 'Generic PCL' }) | Should -Be @()
        @(Get-Elements $Real | Where-Object { ($_.Texts -join ' ') -match '4\.x\.x\.x|MetaFrame' }) | Should -Be @()
        foreach ($v in @{ Vendor = 'Brother'; Word = 'Generic PCL' }, @{ Vendor = 'HP'; Word = '4.x.x.x' }) {
            $at = $Doc.IndexOf("`n## $($v.Vendor)`n"); $next = $Doc.IndexOf("`n## ", $at + 4)
            $rejected = @((($Doc.Substring($at, $next - $at) -split '### Nicht aufgenommen', 2)[1] -split "`n") | Where-Object { $_.Contains($v.Word) })
            $rejected.Count | Should -Be 1 -Because $v.Word
            $rejected[0] | Should -Match 'Quelle veraltet oder nur für ein anderes Produkt' -Because $v.Word
        }
    }
    It 'hat je Hersteller einen Abschnitt mit den nicht aufgenommenen Empfehlungen und ihrem Grund' {
        $reasons = 'keine Herstellerquelle gefunden', 'Quelle veraltet oder nur für ein anderes Produkt', 'widerspricht einer anderen Herstellerquelle', 'setzt eine Änderung voraus, die die Messung nicht stützt'
        foreach ($v in $PrintVendors) {
            $at = $Doc.IndexOf("`n## $v`n"); $at | Should -BeGreaterThan -1 -Because $v
            $next = $Doc.IndexOf("`n## ", $at + 4); if ($next -lt 0) { $next = $Doc.Length }
            $section = $Doc.Substring($at, $next - $at)
            $section | Should -Match '### Nicht aufgenommen' -Because $v
            $rejected = @(($section -split '### Nicht aufgenommen', 2)[1] -split "`n" | Where-Object { $_ -match '^\|' -and $_ -notmatch '^\|\s*(-+|Empfehlung)' })
            $rejected.Count | Should -BeGreaterThan 0 -Because $v
            foreach ($line in $rejected) { @($reasons | Where-Object { $line.Contains($_) }).Count | Should -BeGreaterThan 0 -Because $line }
        }
        $Doc | Should -Match 'ein zweites Mal'
    }
}
