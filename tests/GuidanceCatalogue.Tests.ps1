BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Events.ps1')
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Findings.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Guidance.ps1')
    $script:Texts = Read-WorkerPerfTexts (Join-Path $PSScriptRoot '../src/texts.de.json')
    $script:CatalogueFile = Join-Path $PSScriptRoot '../src/guidance.de.json'
    # the application list of the report (src/apps.json): its keys are the conditions app.<key> of the catalogue
    $script:AppList = Read-WorkerPerfApps (Join-Path $PSScriptRoot '../src/apps.json')
    $script:SourcesFile = Join-Path $PSScriptRoot '../docs/guidance/quellen.md'
    $script:PrintVendors = @('Microsoft', 'Citrix', 'HP', 'Kyocera', 'Brother')
    # the vendors a source may name (the printer vendors, the vendor of the printer mapping tool) and the sources from
    # practice, which carry their mark in the source (spec 5.7)
    # final fix wave, item 4: VMware for its sizing article
    $script:SourceVendors = $script:PrintVendors + 'AKI' + 'VMware'
    # the twelve sources from practice the customer adopted (spec 5.7): the two of round 2 and the ten of round 5
    $script:PracticeNames = @('Carl Stalhood', 'BIS-F', 'GO-EUC', 'James Kindon', 'James Rankin', 'Thomas Kötzing', 'Manuel Winkel', 'Aaron Parker', 'Trentent Tye',
        'John Billekens', 'Guy Leech', 'Benny Tritsch')
    $script:PracticeAny = '(' + (($script:PracticeNames | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')'
    $script:PracticeSource = '^' + $script:PracticeAny + ' \(Empfehlung aus der Praxis\)$'
    # the word by which a text of the catalogue attributes a statement to one of the ten sources of round 5
    $script:PracticeWords = [ordered]@{ 'GO-EUC' = 'GO-EUC'; 'Kindon' = 'James Kindon'; 'Rankin' = 'James Rankin'; 'Kötzing' = 'Thomas Kötzing'; 'Winkel' = 'Manuel Winkel'
        'Parker' = 'Aaron Parker'; 'Tye' = 'Trentent Tye'; 'Billekens' = 'John Billekens'; 'Leech' = 'Guy Leech'; 'Tritsch' = 'Benny Tritsch' }
    # where a change is made on non-persistent servers (spec 5.8): in the master image, or by a policy
    $script:InImage = 'bei nicht persistenten Servern im Master-Image, danach die Server neu bereitstellen'
    $script:ByPolicy = 'eine Richtlinie wirkt auch auf nicht persistente Server'
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
            Thresholds = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json'); OffsetMinutes = 60; Texts = $script:Texts; Apps = $script:AppList }
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
    # the measured machine is "Server" in every text the report shows or offers to copy (wording rule of the customer,
    # ruling P3-R66): the word Worker at the start of a word, also as the first part of a compound; the tool's name stays
    $script:WorkerWord = '(?<![\p{L}\p{N}])Worker(?!Perf)'
    function Get-CatalogueStrings($Node, [string]$Place) {
        # every text of the catalogue file with its place ('situations.cpu.remedies[6].text'); the keys of terms are
        # display words and count as texts. Not texts: version, vendors (keys and patterns), the conditions (when), and
        # source, which quotes the title of a document literally
        if ($Node -is [string]) { [pscustomobject]@{ Place = $Place; Text = $Node }; return }
        if ($Node -is [array]) { for ($k = 0; $k -lt $Node.Count; $k++) { Get-CatalogueStrings $Node[$k] "$Place[$k]" }; return }
        if ($Node -isnot [pscustomobject]) { return }
        foreach ($p in $Node.PSObject.Properties) {
            if ($p.Name -in 'when', 'source' -or ($Place -eq '' -and $p.Name -in 'version', 'vendors')) { continue }
            $at = $p.Name; if ($Place) { $at = "$Place.$($p.Name)" }
            if ($Place -eq 'terms') { [pscustomobject]@{ Place = "$at (Begriff)"; Text = $p.Name } }
            Get-CatalogueStrings $p.Value $at
        }
    }
    # the mark of a source from practice in the field source, and the ten further sources of round 5
    $script:PracticeMark = '(Empfehlung aus der Praxis)'
    $script:RoundFive = @($script:PracticeNames | Where-Object { $_ -notin 'Carl Stalhood', 'BIS-F' })
    $script:RoundFiveSource = '^(' + (($script:RoundFive | ForEach-Object { [regex]::Escape($_) }) -join '|') + ') \('
    function Get-BeforePractice($Items) {
        # a list of a guidance without the elements from a source of practice at its end: by the rule of the ranking
        # (ruling P3-R75) the general elements from practice follow the notes on what was not measured. Plain pipeline
        # output: the caller writes @(...)
        $list = @($Items); $n = $list.Count
        while ($n -gt 0 -and ([string]$list[$n - 1].source).Contains($script:PracticeMark)) { $n-- }
        for ($k = 0; $k -lt $n; $k++) { $list[$k] }
    }
    # final fix wave, items 4 and 7: the remedy on the SMB client came with a source of round 5 (James Rankin) and carries
    # Microsoft's page as its source since then; it stands last by ruling and was never shown before round 5, so for the
    # invariant of P3-R75 it stays an element of round 5. The other elements that changed from a source of round 5 to the
    # vendor's document are the vendor's elements now, as the record states the rule (by the source)
    $script:RoundFiveOrigin = '^Drosselung des SMB-Clients abschalten'
    function Test-RoundFive($Item) { ([string]$Item.source -match $script:RoundFiveSource) -or ([string]$Item.text -match $script:RoundFiveOrigin) }
    function Get-Displaced($Guide) {
        # ruling P3-R75: leave out the elements of the ten further sources; the first five checks and the first three
        # remedies of what remains are the first of the list, in the same order. Returns what breaks it, as text
        foreach ($pair in @(@('checks', 5), @('remedies', 3))) {
            $list = @($Guide.($pair[0])); $rest = @($list | Where-Object { -not (Test-RoundFive $_) } | Select-Object -First $pair[1])
            for ($k = 0; $k -lt $rest.Count; $k++) {
                if ([string]$list[$k].text -cne [string]$rest[$k].text) { '{0}[{1}] ist <{2}>, davor gehoert <{3}>' -f $pair[0], $k, $list[$k].text, $rest[$k].text; break }
            }
        }
    }
    function Get-OutOfView($Guide) {
        # the weaker form for incidents no test report holds: every earlier step among the first five checks and three
        # remedies of the list without the ten further sources is among the first five and three of the list itself
        foreach ($pair in @(@('checks', 5), @('remedies', 3))) {
            $list = @($Guide.($pair[0])); $top = @($list | Select-Object -First $pair[1] | ForEach-Object { [string]$_.text })
            foreach ($x in @($list | Where-Object { -not (Test-RoundFive $_) } | Select-Object -First $pair[1])) {
                if ($top -cnotcontains [string]$x.text) { '{0}: <{1}> steht nicht mehr unter den ersten {2}' -f $pair[0], $x.text, $pair[1] }
            }
        }
    }
    function Get-Statements([string]$Text) { @($Text -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    function Test-MeasuredStatement([string]$Statement) {
        # a statement that attributes a number with a unit to a source from practice
        $who = '(?<![\p{L}])(' + (($script:PracticeWords.Keys | ForEach-Object { [regex]::Escape($_) }) -join '|') + '|Praxisquelle)(?![\p{L}])'
        ($Statement -cmatch $who) -and ($Statement -cmatch '\d+(?:[.,]\d+)? ?(?:s\b|Sekunden|ms\b|%|MB\b|GB\b)')
    }
    function Get-NumberWithoutYear([string]$Text) {
        # the statements of a text that give a measured number of a source from practice without a year; the year of a
        # product (Windows Server 2019, Office 2016, Exchange 2019) is no year of a measurement
        foreach ($st in (Get-Statements $Text)) {
            if (-not (Test-MeasuredStatement $st)) { continue }
            $plain = $st -creplace '(Windows Server|Windows|Server|Office|Exchange|Outlook|Visio|Project) (19|20)\d\d( R2)?', '$1'
            if ($plain -cnotmatch '\b(19|20)\d\d\b') { $st }
        }
    }
    function Get-Placeholders([string]$Text) { @([regex]::Matches($Text, '\{([A-Za-z0-9]+)\}') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique) }
    function Get-Positions([string]$Text) { @([regex]::Matches($Text, '`([a-z.]+\.(?:checks|remedies|contacts)\[\d+\])`') | ForEach-Object { $_.Groups[1].Value }) }
    function Get-SourceRows([string]$Path) {
        # the rows of the tables of adopted sources in docs/guidance/quellen.md: vendor or source from practice (heading
        # '## <vendor>' or '## <vendor> – <topic>', also the section 'WorkerPerf' of the report's own notes), title (first
        # cell), the catalogue positions the row adopts (the first cell after the title that names positions) and the
        # positions its remaining cells (the note) speak about; a row without positions is no row of an adopted source
        $vendor = ''
        foreach ($line in [IO.File]::ReadAllLines($Path)) {
            $m = [regex]::Match($line, '^##\s+(.+?)\s*$')
            if ($m.Success) { $vendor = ($m.Groups[1].Value -split ' – ', 2)[0]; continue }
            if ($line -notmatch '^\|') { continue }
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
        $script:Real = Read-WorkerPerfGuidance $script:CatalogueFile -Apps $script:AppList
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
        # in every situation: a source names a vendor or a source from practice with its mark (spec 5.7), or is exactly
        # the report's own note (ruling P3-R35), and an element sourced from a printer vendor hangs on that vendor's driver
        @($Elements | Where-Object { $_.Source -ceq $OwnSource }).Count | Should -BeGreaterThan 0
        foreach ($e in @($Elements | Where-Object { $_.Source })) {
            if ($e.Source -ceq $OwnSource) { $e.Situation | Should -Be 'print' -Because $e.Position; continue }
            $vendor = ($e.Source -split ': ', 2)[0]
            ($SourceVendors -ccontains $vendor -or $vendor -cmatch $PracticeSource) | Should -BeTrue -Because "$($e.Position): $($e.Source)"
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
    It 'zeigt ohne bekannten Hersteller nur Elemente von Microsoft und Citrix und die zur Druckerzuordnung' {
        $ctx = New-Ctx; $ctx.Data.print.drivers[0].manufacturer = 'Acme Printing'
        $g = Get-Guide (New-Inc @{ type = 'ereignis'; event = @{ kind = 'print'; key = 'Sim PCL 6'; app = 'spoolsv.exe' }; events = @(@{ app = 'spoolsv.exe'; kind = 'crash'; log = 'application' }) }) $ctx
        $all = @($g.checks) + @($g.remedies) + @($g.contacts)
        $all.Count | Should -BeGreaterThan 0
        # Aussage angepasst (fix round 2, B5): the general steps on the mapping of printers carry the mapping tool's vendor
        # Aussage angepasst (round 5): a general step from a source of practice may stand there too; a printer vendor never
        @($all | ForEach-Object { ($_.source -split ': ', 2)[0] } | Sort-Object -Unique | Where-Object { $_ -notin 'Microsoft', 'Citrix', 'WorkerPerf', 'AKI' -and $_ -cnotmatch $PracticeSource }) | Should -Be @()
        @($all | Where-Object { $_.source -match '^(HP|Kyocera|Brother): ' }) | Should -Be @()
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
            # fix round 3 (rulings P3-R49, P3-R59): the counts stand in the parts of the red and the yellow sentence; the copy text says how many steps it left out
            'copy.maxChecks' = @(); 'copy.maxRemedies' = @(); 'copy.moreChecks' = @('count'); 'copy.moreCheck' = @(); 'copy.moreRemedies' = @('count'); 'copy.moreRemedy' = @()
            'lagebild.red' = @('parts', 'minutes', 'incidents'); 'lagebild.yellow' = @('parts', 'minutes', 'incidents')
            'lagebild.partBottlenecks' = @('bottlenecks'); 'lagebild.partDelays' = @('delays'); 'lagebild.partEvents' = @('events'); 'lagebild.partChronic' = @('chronic')
            'lagebild.partSeparator' = @(); 'lagebild.notMeasured' = @('skipped')
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
        # each part of the red and the yellow sentence names its count, both sentences their parts and the minutes
        foreach ($k in 'red', 'yellow') { $Real.lagebild.$k | Should -Match '\{parts\}' -Because $k; $Real.lagebild.$k | Should -Match '\{minutes\}' -Because $k }
        # Aussage angepasst (final fix wave, item 13): the count stands in brackets after the word, never as "{count}-mal"
        foreach ($k in 'Bottlenecks', 'Delays', 'Events', 'Chronic') { $Real.lagebild."part$k" | Should -Match ('^\S.* \(\{' + $k.ToLowerInvariant() + '\}\)$') -Because $k }
        $Real.lagebild.notMeasured | Should -Match '\{skipped\}'; $Real.copy.moreChecks | Should -Match '\{count\}'; $Real.copy.moreRemedies | Should -Match '\{count\}'
    }
    It 'baut den roten und den gelben Satz des Lagebilds aus Teilen und zaehlt nicht Gemessenes nie als null' {     # fix round 3, A1 (ruling P3-R49)
        $say = { param($Incidents, [string[]]$Skip)
            $ctx = New-Ctx; $ctx.Data.skipped = @(Get-WorkerPerfSkippedOut $Skip $Texts)
            (Get-WorkerPerfLagebild -Incidents $Incidents -Data $ctx.Data -Catalogue $Real -Texts $Texts).sentence }
        $delay = New-Inc @{ id = 2; type = 'ohne-engpass'; severity = 1; affected = @(@{ s = 1 }) }
        $crash = New-Inc @{ id = 3; type = 'ereignis'; start = [long](1e12 + 660000); end = [long](1e12 + 660000); event = @{ kind = 'crash'; app = 'simapp.exe' } }
        $chronic = New-Inc @{ id = 4; type = 'umfeld'; chronic = $true; start = [long]1e12; end = [long](1e12 + 3600000); signals = @(New-Sig 'ica.rtt' 'network' 'ICA Round Trip' 225 'ms' 'unter 150 ms') }
        $red = @((New-Engpass 'cpu'), $delay, $crash, $chronic)
        # a complete capture: each part names its count after the word (final fix wave, items 13 and 18: no "1-mal", no
        # label before the parts that would stand after the state word of the copy text as a second label)
        & $say $red @() | Should -BeExactly 'Handlungsbedarf wegen Engpass auf dem Server (1), Verzögerung (1), Absturz oder Fehler (1), Dauerzustand (1); 2 min mit spürbarer Störung.'
        & $say @($delay) @() | Should -BeExactly 'Auffälligkeiten ohne erkannten Engpass auf dem Server – Verzögerung (1), Absturz oder Fehler (0), Dauerzustand (0); 2 min mit spürbarer Störung.'
        # without events, without Citrix, without everything: no part that would count zero, and the reservation
        & $say @((New-Engpass 'cpu'), $delay, $chronic) @('Ereignisse') |
            Should -BeExactly 'Handlungsbedarf wegen Engpass auf dem Server (1), Verzögerung (1), Dauerzustand (1); 2 min mit spürbarer Störung. Nicht gemessen: Ereignisse.'
        & $say @((New-Engpass 'cpu'), $delay, $crash) @('Citrix') |
            Should -BeExactly 'Handlungsbedarf wegen Engpass auf dem Server (1), Verzögerung (1), Absturz oder Fehler (1); 2 min mit spürbarer Störung. Nicht gemessen: Citrix.'
        $all = @($script:WorkerPerfCategories.Keys | Where-Object { $script:WorkerPerfCategories[$_].Active })
        & $say @($delay) $all |
            Should -BeExactly 'Auffälligkeiten ohne erkannten Engpass auf dem Server – Verzögerung (1); 2 min mit spürbarer Störung. Nicht gemessen: Prozesse, Laufwerke, Citrix, Ereignisse, Rückblick, Drucken, Gegenstellen, Zustandsbild.'
        # a zero stands only for what was measured: without events none for crashes, without Citrix none for chronic states
        foreach ($list in @($delay), @((New-Engpass 'cpu'), $delay)) {
            & $say $list @('Ereignisse') | Should -Not -Match 'Absturz oder Fehler \(0\)'; & $say $list @('Ereignisse') | Should -Match 'Dauerzustand \(0\)'
            & $say $list @('Citrix') | Should -Not -Match 'Dauerzustand \(0\)'; & $say $list @('Citrix') | Should -Match 'Absturz oder Fehler \(0\)'
            & $say $list $all | Should -Not -Match '\(0\)'
        }
        # a category no part of the sentence depends on leaves the sentence as it is
        & $say $red @('Prozesse', 'Laufwerke', 'Rueckblick', 'Drucken', 'Gegenstellen') | Should -BeExactly (& $say $red @())
    }
    It 'schreibt eine Zahl der Benutzersicht und des Lagebilds nie als "1-mal" und setzt vor die Teile des Lagebilds keine zweite Bezeichnung' {      # final fix wave, items 13 and 18
        # every count of the catalogue's texts outside the situations stands so that 1 reads as plain German: no "{count}-mal"
        foreach ($part in 'userView', 'lagebild') { foreach ($p in $Real.$part.PSObject.Properties) { [string]$p.Value | Should -Not -Match '\}-mal' -Because "$part.$($p.Name)" } }
        # one event, one session: the user's view and the before-note say the number without "1-mal"
        $one = New-Inc @{ type = 'ereignis'; start = [long]1e12; end = [long]1e12; event = @{ kind = 'crash'; app = 'simapp.exe'; count = 1; users = @('user003'); sessions = @(3); inSession = $true } }
        $view = (Get-Guide $one).userView; $view | Should -Be 'Eine Sitzung betroffen; Zahl der Ereignisse: 1.'; $view | Should -Not -Match '1-mal'
        foreach ($k in 'eventMany', 'eventOne', 'eventNone', 'before') {
            (Format-WorkerPerfGuidancePart $Real 'userView' $k @{ affected = '2'; count = '1' }) | Should -Not -Match '\d-mal' -Because $k
        }
        # the state line of the summary of the copy text: symbol, word and the sentence; the sentence brings no label of its
        # own before its parts ("◆ kritisch: Handlungsbedarf: …" had two)
        $ctx = New-Ctx
        foreach ($list in @((New-Engpass 'cpu')), @((New-Inc @{ id = 2; type = 'ohne-engpass'; severity = 1; affected = @(@{ s = 1 }) }))) {
            $lb = Get-WorkerPerfLagebild -Incidents $list -Data $ctx.Data -Catalogue $Real -Texts $Texts
            $lb.sentence | Should -Not -Match ':' -Because $lb.state
            $state = @(Get-WorkerPerfCopySummaryParagraphs -Incidents $list -Order @($list | ForEach-Object { [int]$_.id }) -Lagebild $lb -Data $ctx.Data -Catalogue $Real -Texts $Texts)[1]
            $state | Should -BeExactly ("$($lb.symbol) $($lb.word): " + $lb.sentence)
            @([regex]::Matches($state, ':')).Count | Should -Be 1 -Because $state
        }
    }
    It 'schreibt im Kopiertext das Erkennungszeichen nach seiner Bezeichnung, nie als Satzteil nach "erkennbar an"' {      # final fix wave, item 17
        $Texts['copy.check'] | Should -BeExactly '{0}. Wo: {1}. Woran erkennbar: {2}'
        # every check of every situation, as the copy text writes it: no line reads "erkennbar an" and a capital letter
        $n = 0
        foreach ($e in @(Get-Elements $Real | Where-Object { $_.List -eq 'checks' })) {
            $line = Format-WorkerPerfGuidanceWord $Texts 'copy.check' @($e.Texts[0], $e.Texts[1], $e.Texts[2])
            $line | Should -Not -MatchExactly 'erkennbar an \p{Lu}' -Because $e.Position
            $line | Should -MatchExactly '\. Woran erkennbar: ' -Because $e.Position; $n++
        }
        $n | Should -BeGreaterThan 250
        # the sign the review quoted reads as a sentence of its own
        $sign = (@(Get-Elements $Real | Where-Object { $_.Situation -eq 'chronic.network' -and $_.Texts[0] -match '^Den Benutzer fragen, wie die Störung aussah' }))[0].Texts[2]
        (Format-WorkerPerfGuidanceWord $Texts 'copy.check' @('a', 'b', $sign)) | Should -Match ('Woran erkennbar: ' + [regex]::Escape($sign) + '$')
        # the pattern finds the old form
        (('{0} – {1}; erkennbar an {2}' -f 'a', 'b', $sign)) | Should -MatchExactly 'erkennbar an \p{Lu}'
    }
    It 'nimmt in den Kopiertext die ersten fuenf Pruefschritte und drei Vorschlaege und sagt, wie viele weitere im Bericht stehen' {      # fix round 3, A2 (ruling P3-R59)
        $Real.copy.maxChecks | Should -Be 5; $Real.copy.maxRemedies | Should -Be 3
        $Real.copy.moreChecks | Should -BeExactly 'Weitere {count} Prüfschritte stehen im Bericht.'; $Real.copy.moreCheck | Should -BeExactly 'Ein weiterer Prüfschritt steht im Bericht.'
        $Real.copy.moreRemedies | Should -BeExactly 'Weitere {count} Vorschläge stehen im Bericht.'; $Real.copy.moreRemedy | Should -BeExactly 'Ein weiterer Vorschlag steht im Bericht.'
        # the print incident with an HP driver in the spooler: the longest guidance of the catalogue
        $inc = New-Inc @{ type = 'ereignis'; start = [long]1e12; end = [long]1e12; causeText = 'Ohne Benutzersitzung.'; event = @{ kind = 'print'; key = 'Sim PCL 6'; app = 'spoolsv.exe'; driver = 'Sim PCL 6'; noUserSession = $true
                patterns = @(@{ id = 'printdriver'; detail = @{ module = 'hpsimgr.dll'; driver = 'Sim PCL 6' } }); modules = @(@{ name = 'hpsimgr.dll'; count = 1 }) }
            events = @(@{ app = 'spoolsv.exe'; kind = 'crash'; log = 'application' }) }
        $g = Get-Guide $inc
        $checks = @($g.checks).Count; $remedies = @($g.remedies).Count; $checks | Should -BeGreaterThan 10; $remedies | Should -BeGreaterThan 10
        $p = @(Get-WorkerPerfCopyParagraphs -Incident $inc -Guide $g -Data (New-Ctx).Data -Catalogue $Real -Texts $Texts)
        $numbered = @($p | Where-Object { $_ -match '^\d+\. ' }); $numbered.Count | Should -Be 5
        for ($n = 0; $n -lt 5; $n++) { $numbered[$n].StartsWith(('{0}. {1}' -f ($n + 1), $g.checks[$n].text)) | Should -BeTrue -Because "Schritt $($n + 1)" }
        $at = [array]::IndexOf($p, $Real.copy.remedies); $end = [array]::IndexOf($p, $Real.copy.contact)
        $p[$at - 2] | Should -BeExactly "Weitere $($checks - 5) Prüfschritte stehen im Bericht."; $p[$at - 3] | Should -Be $numbered[4]
        $proposals = @($p[($at + 1)..($end - 2)])
        $proposals.Count | Should -Be 4; $proposals[3] | Should -BeExactly "Weitere $($remedies - 3) Vorschläge stehen im Bericht."
        for ($n = 0; $n -lt 3; $n++) { $proposals[$n].EndsWith($g.remedies[$n].text) | Should -BeTrue -Because "Vorschlag $($n + 1)" }
        # every contact
        @($p[($end + 1)..($p.Count - 1)]).Count | Should -Be @($g.contacts).Count
        # the guidance itself is complete, and a line of the text has at most 78 characters
        @($g.checks).Count | Should -Be $checks
        @((New-WorkerPerfCopyText -Incident $inc -Guide $g -Data (New-Ctx).Data -Catalogue $Real -Texts $Texts) -split "`r`n" | Where-Object { $_.Length -gt 78 }) | Should -Be @()
        # an incident with fewer steps: no such line (a chronic state of the connection)
        $few = New-Inc @{ type = 'umfeld'; chronic = $true; start = [long]1e12; end = [long](1e12 + 3600000); signals = @(New-Sig 'ica.rtt' 'network' 'ICA Round Trip' 225 'ms' 'unter 150 ms') }
        $g = Get-Guide $few
        @($g.checks).Count | Should -BeLessOrEqual 5; @($g.remedies).Count | Should -BeLessOrEqual 3
        @(Get-WorkerPerfCopyParagraphs -Incident $few -Guide $g -Data (New-Ctx).Data -Catalogue $Real -Texts $Texts | Where-Object { $_ -match 'stehen? im Bericht\.$' }) | Should -Be @()
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
        # Aussage angepasst (fix round 2, B5): with the general steps on the mapping of printers; (round 5) the steps
        # from sources of practice stand beside them, named as such, and no other printer vendor
        @($vendors | Where-Object { $_ -cnotmatch $PracticeSource }) | Should -Be @('AKI', 'Citrix', 'HP', 'Microsoft', 'WorkerPerf')
        @($vendors | Where-Object { $_ -cmatch $PracticeSource }).Count | Should -BeGreaterThan 0
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
    It 'stellt die Verzoegerung bei <S> nicht als Tatsache hin, wenn die Eingabeverzoegerung nicht gemessen wurde' -ForEach @(      # fix round 4, B2 (ruling P3-R65)
        @{ S = 'cpu'; I = @{ type = 'engpass'; lead = 'cpu'; cause = @{ kind = 'nodata' } }; Fact = 'reagierten für die betroffenen Benutzer spürbar verzögert' }
        @{ S = 'disk'; I = @{ type = 'engpass'; lead = 'disk'; cause = @{ kind = 'nodata' } }; Fact = 'dauerten spürbar länger' }
        @{ S = 'share'; I = @{ type = 'engpass'; lead = 'share'; cause = @{ kind = 'nodata' } }; Fact = 'ließen sich nur verzögert öffnen' }
        @{ S = 'profile'; I = @{ type = 'engpass'; lead = 'profile'; cause = @{ kind = 'nodata' } }; Fact = 'reagierten träge' }
        @{ S = 'chronic.resource'; I = @{ type = 'engpass'; lead = 'cpu'; chronic = $true; cause = @{ kind = 'nodata' } }; Fact = 'reagieren für die Benutzer dauerhaft zäher' }
        @{ S = 'fallback'; I = @{ type = 'umfeld' }; Fact = 'zeigen die betroffenen Sitzungen' }
    ) {
        $inc = New-Inc $I
        # measured: the impact as it stands
        $g = Get-Guide $inc
        $g.situation | Should -Be $S; $g.conditions | Should -Not -Contain 'unmeasured.input.session'
        $g.impact | Should -BeExactly $Real.situations.$S.impact; $g.impact | Should -Match ([regex]::Escape($Fact))
        # not measured: the row of the target comparison says so, and no session can be named
        $ctx = New-Ctx; $ctx.Data.unmeasured.input = $true
        $ctx.Data.sollIst = @(@{ id = 'input.session'; label = 'Eingabeverzögerung je Sitzung'; measured = $false; detail = '' })
        $g = Get-Guide $inc $ctx
        $g.conditions | Should -Contain 'unmeasured.input.session'; $g.conditions | Should -Contain 'affected.unknown'
        $g.impact | Should -Not -Match ([regex]::Escape($Fact))
        $g.impact | Should -Match '(?i)die Eingabeverzögerung wurde nicht gemessen\.$'
        if ($S -ne 'fallback') { $g.impact | Should -Match '\b(können|kann)\b' }
        $g.impact | Should -Not -Match '\b(reagierten|dauerten|ließen|wirkten|mussten)\b'
        if ($S -ne 'chronic.resource') { $g.userView | Should -Match 'nicht bestimmbar' }
        $g.terms | Should -Contain 'Eingabeverzögerung'
        # the copy text carries the same sentence
        $p = @(Get-WorkerPerfCopyParagraphs -Incident $inc -Guide $g -Data $ctx.Data -Catalogue $Real -Texts $Texts)
        $p | Should -Contain $g.impact; $p | Should -Not -Contain $Real.situations.$S.impact
    }
    It 'hat fuer jede Wirkung, die eine Verzoegerung als Tatsache nennt, eine Fassung ohne gemessene Eingabeverzoegerung' {      # fix round 4, B2
        $with = @($WorkerPerfSituations | Where-Object { $Real.situations.$_.PSObject.Properties['impactVariants'] })
        $with | Should -Be @('cpu', 'disk', 'share', 'profile', 'chronic.resource', 'fallback')
        foreach ($s in $with) {
            $variants = @($Real.situations.$s.impactVariants); $variants.Count | Should -Be 1 -Because $s
            @($variants[0].when) | Should -Contain 'unmeasured.input.session' -Because $s
            # one sentence, like the impact, with no placeholder
            ([regex]::Matches($variants[0].text, '[.!?](?=\s|$)')).Count | Should -Be 1 -Because $s; $variants[0].text | Should -Not -Match '[{}]' -Because $s
            $variants[0].text | Should -Not -BeExactly $Real.situations.$s.impact
        }
        # the situations of a measured resource without such a variant word their impact as a likelihood already; a
        # delay without bottleneck and a slow network path are found by their own measured value
        $Real.situations.memory.impact | Should -Match '^Anwendungen können träge reagiert haben'
        foreach ($s in 'memory', 'delay.many', 'delay.single', 'chronic.network') { $Real.situations.$s.PSObject.Properties['impactVariants'] | Should -BeNullOrEmpty -Because $s }
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
        # a print failure with every pattern of its own: five notes and the general step on the mapping of printers
        # (fix round 2, B5), each with the own source
        $inc = New-Inc @{ type = 'ereignis'; event = @{ kind = 'print'; key = 'Sim PCL 6'; app = 'spoolsv.exe'; users = @('user003'); sessions = @(3); count = 3
                patterns = @(@{ id = 'resource'; detail = @{} }, @{ id = 'securitymodule'; detail = @{} }, @{ id = 'oneuser'; detail = @{} }, @{ id = 'companion'; detail = @{} },
                    @{ id = 'overlap'; detail = @{} }) }; events = @(@{ app = 'spoolsv.exe'; kind = 'crash'; log = 'application' }) }
        $g = Get-Guide $inc
        $notes = @($g.checks | Where-Object { $_.source -ceq $OwnSource })
        $notes.Count | Should -Be 6
        @($notes | Where-Object { $_.text -match '^Wenn ein Zuordnungswerkzeug die Drucker zuordnet' }).Count | Should -Be 1
        @($notes | Where-Object { $_.text -match 'user003' }).Count | Should -Be 1
        @($notes | Where-Object { $_.text -match 'Leistungsvorfalls: auch dessen Anleitung ansehen' }).Count | Should -Be 1
        # the service comes first, the coincidence in time after the patterns that say more
        $g.checks[0].text | Should -Match 'Dienst „Druckwarteschlange“ wieder läuft'
        $order = @($notes | ForEach-Object { $_.text.Substring(0, 12) })
        [array]::IndexOf($order, 'Der Druckfeh') | Should -BeGreaterThan ([array]::IndexOf($order, 'Speichermang'))
    }
    It 'stellt bei <S> das Zusammentreffen mit einem Leistungsvorfall hinter die allgemeinen Schritte und die Muster, die mehr sagen' -ForEach @(      # fix round 1, B4
        @{ S = 'crash'; First = 'Version der Anwendung und des fehlerhaften Moduls feststellen und mit dem Stand des Herstellers vergleichen' }
        @{ S = 'hang'; First = 'Betroffene Benutzer fragen, was sie taten, als die Anwendung stehen blieb' }
        @{ S = 'service'; First = 'Prüfen, ob der Dienst wieder läuft' }
        @{ S = 'print'; First = 'Prüfen, ob der Dienst „Citrix Print Manager Service“ (CpSvc.exe) läuft' }
        @{ S = 'profileerror'; First = 'Meldungstext des Profilfehlers lesen: er nennt meist den Grund' }
        @{ S = 'system'; First = 'Art und Meldungstext des Systemfehlers feststellen' }
    ) {
        $checks = @($Real.situations.$S.checks)
        $when = @($checks | ForEach-Object { if ($_.PSObject.Properties['when']) { @($_.when) -join ',' } else { '' } })
        $at = [array]::IndexOf($when, 'pattern.overlap'); $at | Should -BeGreaterThan -1
        $note = [string]$checks[$at].text
        $note | Should -Match 'auch dessen Anleitung ansehen, beide können dieselbe Ursache haben$'
        $note | Should -Not -Match 'zuerst'
        function Get-NotePlace($Incident, $Context) {
            # the checks an incident shows, the place of the note among them, and the checks of the situation that only
            # name a gap (ruling P3-R36) as this incident words them
            $facts = Get-WorkerPerfGuidanceFacts -Incident $Incident -Context $Context -Catalogue $script:Real
            $guide = New-WorkerPerfGuidance -Catalogue $script:Real -Facts $facts -Incident $Incident -Texts $script:Texts
            $shown = @($guide.checks | ForEach-Object { [string]$_.text })
            $gaps = @($checks | Where-Object { $_.PSObject.Properties['when'] -and @(@($_.when) | Where-Object { -not (& $GapCondition $_) }).Count -eq 0 } |
                    ForEach-Object { Format-WorkerPerfGuidanceText ([string]$_.text) $facts.Values } | Where-Object { $_ })
            @{ Conditions = @($guide.conditions); Values = $facts.Values; Shown = $shown; At = [array]::IndexOf($shown, $note); Gaps = $gaps }
        }
        # the coincidence in time is the only pattern and nothing else is known (for print: no crash of the spooler, no
        # driver, no queue; an application that is no standard application of src/apps.json, which has steps of its own):
        # the general steps lead in the order of the file, the note is the last step and never the first
        $ctx = New-Ctx; $ctx.Data.print = @{ drivers = @(); queues = @() }
        $only = @{ kind = $S; app = 'simapp.exe'; service = 'SimSvc'; users = @('user003'); sessions = @(3); count = 3; patterns = @(@{ id = 'overlap'; detail = @{} }) }
        $place = Get-NotePlace (New-Inc @{ type = 'ereignis'; event = $only }) $ctx
        $place.Conditions | Should -Be @('affected.one', 'pattern.overlap')
        $place.Shown[0] | Should -Match ('^' + [regex]::Escape($First))
        # round 5, fix round 1 (ruling P3-R75): a general step from a source of practice follows the notes
        $fromPractice = { param($c) $c.PSObject.Properties['source'] -and ([string]$c.source).Contains($PracticeMark) }
        $general = @($checks | Where-Object { -not $_.PSObject.Properties['when'] -and -not (& $fromPractice $_) } | ForEach-Object { [string]$_.text })
        $late = @($checks | Where-Object { -not $_.PSObject.Properties['when'] -and (& $fromPractice $_) } | ForEach-Object { [string]$_.text })
        $general.Count | Should -BeGreaterThan 0
        $place.Shown | Should -Be @($general + $note + $late)
        # with patterns that say more and with a pattern that was not checked: every other step precedes the note, only
        # the notes about a gap follow it
        $ctx = New-Ctx; $ctx.Data.skipped = @(@{ id = 'Drucken'; label = 'Drucken'; text = ''; places = @() })
        $more = @{ kind = $S; key = 'Sim PCL 6'; app = 'simapp.exe'; service = 'SimSvc'; users = @('user003'); sessions = @(3); count = 3
            patterns = @(@{ id = 'resource'; detail = @{} }, @{ id = 'oneuser'; detail = @{} }, @{ id = 'companion'; detail = @{} }, @{ id = 'overlap'; detail = @{} })
            unchecked = @(@{ id = 'printdriver'; category = 'Drucken' }) }
        $place = Get-NotePlace (New-Inc @{ type = 'ereignis'; event = $more; events = @(@{ app = 'spoolsv.exe'; kind = 'crash'; log = 'application' }) }) $ctx
        $place.At | Should -BeGreaterThan 0
        $place.At | Should -BeLessThan ($place.Shown.Count - 1)
        for ($k = 0; $k -lt $place.Shown.Count; $k++) {
            if ($k -eq $place.At) { continue }
            (($place.Gaps -ccontains $place.Shown[$k]) -or ($late -ccontains $place.Shown[$k])) | Should -Be ($k -gt $place.At) -Because "Schritt $($k + 1): $($place.Shown[$k])"
        }
        # the steps of the patterns that say more are among those before the note
        $stronger = @($checks | Where-Object { $_.PSObject.Properties['when'] -and (@($_.when) -join ',') -in 'pattern.resource', 'pattern.oneuser', 'pattern.companion' })
        $stronger.Count | Should -BeGreaterThan 0
        foreach ($el in $stronger) {
            $k = [array]::IndexOf($place.Shown, (Format-WorkerPerfGuidanceText ([string]$el.text) $place.Values))
            $k | Should -BeGreaterThan -1 -Because $el.text; $k | Should -BeLessThan $place.At -Because $el.text
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
            # (round 5, fix round 1: the last ones before the general steps from a source of practice)
            $last = @(Get-BeforePractice $g.checks | Select-Object -Last 2 | ForEach-Object { $_.text })
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
            if ($n -eq 1) { @(Get-BeforePractice $g.remedies)[-1].text | Should -Match 'ohne „-Skip Gegenstellen“ wiederholen' }
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
    It 'nennt bei jeder Abhilfe, die Treiber, Richtlinie, Registrierung oder Scan-Ausschluss aendert, den Ort der Aenderung auf nicht persistenten Servern' {      # fix round 2, B1 (spec 5.8)
        $remedies = @($Elements | Where-Object { $_.List -eq 'remedies' })
        $changing = @($remedies | Where-Object { $_.Texts[0] -match 'Treiber|Richtlinie|Registrierung|Ausschl|ausnehmen|Ausnahme' })
        $changing.Count | Should -BeGreaterThan 40
        foreach ($e in $changing) { ($e.Texts[0].Contains($InImage) -or $e.Texts[0].Contains($ByPolicy)) | Should -BeTrue -Because "$($e.Position): $($e.Texts[0])" }
        # the master image for what is installed or set on the worker; a policy needs none
        @($changing | Where-Object { $_.Texts[0].Contains($InImage) }).Count | Should -BeGreaterThan 25
        foreach ($e in @($remedies | Where-Object { $_.Texts[0] -notmatch 'Richtlinie „' -and
                    $_.Texts[0] -match '^Treiber \{driver\}|Treiber .*(installieren|entfernen|erneuern|verwenden)|Brother-Treiber|Kyocera-Treiber|HP Universal Print Driver (auf|in)' })) {
            $e.Texts[0] | Should -Match ([regex]::Escape($InImage)) -Because $e.Position
        }
        # the same for a schedule or an exclusion of the protection software and for what is installed anew
        foreach ($e in @($remedies | Where-Object { $_.Texts[0] -match '^Zeitplan der Scans|^Scan-Ausschl|auf den aktuellen Stand bringen|korrigierte Version (von|der)' })) {
            $e.Texts[0] | Should -Match ([regex]::Escape($InImage)) -Because $e.Position
        }
        # what a restart of such a worker undoes says so
        $undone = @($remedies | Where-Object { $_.Texts[0] -match '^Treiber \{driver\} entfernen|in der Reihenfolge von HP entfernen|mit KmUninstall\.exe|Brother-Treiber vollständig entfernen' })
        $undone.Count | Should -Be 4
        foreach ($e in $undone) { $e.Texts[0] | Should -Match 'am Server selbst nur bis zum Neustart wirksam; dauerhaft bei nicht persistenten Servern im Master-Image' -Because $e.Position }
        # every element that empties the spool folder, in whatever words (follow-up of fix round 2: also Brother's reset)
        $emptied = @($Elements | Where-Object { ($_.Texts -join ' ') -match '(Spool-Ordner|PRINTERS)[^;]*(löschen|leeren)|(löschen|leeren)[^;]*(Spool-Ordner|PRINTERS)' })
        @($emptied | ForEach-Object { $_.Position }) | Should -Be @('print.remedies[10]', 'print.remedies[14]')
        foreach ($e in $emptied) { $e.Texts[0] | Should -Match 'bei nicht persistenten Servern setzt auch ein Neustart den Spool-Ordner auf den Stand des Master-Image zurück$' -Because $e.Position }
        # ending a process or restarting an application lasts until it starts or fills the memory again, as a restart does
        $ended = @($remedies | Where-Object { $_.Texts[0] -match 'Prozess\b[^;]*\bbeenden' })
        @($ended | ForEach-Object { $_.Position }) | Should -Be @('cpu.remedies[0]')
        foreach ($e in $ended) { $e.Texts[0] | Should -Match 'das wirkt nur, bis die Anwendung wieder startet; startet sie von selbst, läuft sie nach der nächsten Anmeldung oder dem nächsten Neustart des Servers wieder$' -Because $e.Position }
        $restarted = @($remedies | Where-Object { $_.Texts[0] -match 'schließen und neu starten' })
        @($restarted | ForEach-Object { $_.Position }) | Should -Be @('memory.remedies[0]')
        foreach ($e in $restarted) { $e.Texts[0] | Should -Match 'wie ein Neustart des Servers nur frei, bis \{app\} ihn wieder belegt$' -Because $e.Position }
        # the terms explain both words, and a guidance with such a remedy lists them
        foreach ($n in 'Master-Image', 'Nicht persistent') { @($Real.terms.PSObject.Properties.Name) | Should -Contain $n }
        $g = Get-Guide (New-Engpass 'cpu' @{ cause = @{ kind = 'security'; security = @{ label = 'Die Schutzsoftware'; sharePct = 40 } }; main = $null })
        $g.terms | Should -Contain 'Master-Image'; $g.terms | Should -Contain 'Nicht persistent'
    }
    It 'sagt bei einem <S> vor der Messung, dass der Rueckblick auf nicht persistenten Servern nur bis zum letzten Neustart reicht' -ForEach @(      # fix round 2, B2
        @{ S = 'crash' }; @{ S = 'hang' }; @{ S = 'service' }; @{ S = 'print' }; @{ S = 'profileerror' }; @{ S = 'system' }
    ) {
        $ev = @{ kind = $S; app = 'simapp.exe'; service = 'SimSvc'; key = 'storage|D:'; users = @('user003'); count = 2 }
        $g = Get-Guide (New-Inc @{ type = 'ereignis'; start = [long]1e12; end = [long]1e12; event = ($ev + @{ before = $true }) })
        $g.conditions | Should -Contain 'before'
        $step = @($g.checks | Where-Object { $_.text -match 'bei nicht persistenten Servern beginnen die Ereignisprotokolle mit dem letzten Neustart' })
        $step.Count | Should -Be 1
        $step[0].text | Should -Match 'eines früheren Tages ist deshalb nur zu sehen, wenn der Server seither nicht neu gestartet wurde$'
        $step[0].where | Should -Match 'Vor der Messung'; $step[0].sign | Should -Match 'letzten Neustart'
        # after the step that asks whether it happened again
        $texts = @($g.checks | ForEach-Object { $_.text })
        [array]::IndexOf($texts, $step[0].text) | Should -BeGreaterThan ([array]::IndexOf($texts, @($texts | Where-Object { $_ -match 'seit Beginn der Messung wieder' })[0]))
        # an incident of the capture does not get it
        @((Get-Guide (New-Inc @{ type = 'ereignis'; start = [long]1e12; end = [long]1e12; event = $ev })).checks | Where-Object { $_.text -match 'letzten Neustart' }) | Should -Be @()
    }
    It 'zeigt bei <App> als Hauptverursacher (<S>) nach dem allgemeinen ersten Schritt die Schritte dieser Anwendung' -ForEach @(      # fix round 2, B3
        @{ S = 'cpu'; App = 'msedge.exe'; Key = 'edge'; Want = 'Browser-Task-Manager' }; @{ S = 'memory'; App = 'msedge.exe'; Key = 'edge'; Want = 'Browser-Task-Manager' }
        @{ S = 'cpu'; App = 'EXCEL.EXE'; Key = 'office'; Want = 'Add-ins von EXCEL\.EXE' }; @{ S = 'memory'; App = 'WINWORD.EXE'; Key = 'office'; Want = 'Add-ins von WINWORD\.EXE' }
        @{ S = 'cpu'; App = 'ms-teams.exe'; Key = 'teams'; Want = 'Medienoptimierung' }; @{ S = 'memory'; App = 'ms-teams.exe'; Key = 'teams'; Want = 'Medienoptimierung' }
        @{ S = 'cpu'; App = 'msedgewebview2.exe'; Key = 'webview2'; Want = 'welche Anwendung msedgewebview2\.exe nutzt' }
        # Aussage angepasst (fix round 3, B1): Outlook has its own key; the steps for every Office program stand under it a second time
        @{ S = 'profile'; App = 'OUTLOOK.EXE'; Key = 'outlook'; Want = 'OST-Datei' }; @{ S = 'share'; App = 'OUTLOOK.EXE'; Key = 'outlook'; Want = 'PST- oder OST-Dateien' }
        @{ S = 'disk'; App = 'OUTLOOK.EXE'; Key = 'outlook'; Want = 'Cache-Modus' }
        @{ S = 'cpu'; App = 'OUTLOOK.EXE'; Key = 'outlook'; Want = 'Add-ins von OUTLOOK\.EXE' }; @{ S = 'memory'; App = 'OUTLOOK.EXE'; Key = 'outlook'; Want = 'Add-ins von OUTLOOK\.EXE' }
    ) {
        $g = Get-Guide (New-Engpass $S @{ main = @{ app = $App; a = 9; user = 'user003'; sharePct = 62; baselinePct = 4 } })
        $g.conditions | Should -Contain "app.$Key"
        # the general step for a named cause stays first; the steps of the application follow it and carry their source
        $first = @($Real.situations.$S.checks | Where-Object { $_.PSObject.Properties['when'] -and (@($_.when) -join ',') -eq 'cause.app' })[0]
        $g.checks[0].text | Should -Be (Format-WorkerPerfGuidanceText $first.text @{ app = $App; user = 'user003'; from = '02:56'; to = '02:58' })
        $own = @($Real.situations.$S.checks | Where-Object { $_.PSObject.Properties['when'] -and @($_.when) -contains "app.$Key" })
        $own.Count | Should -BeGreaterThan 0
        $shown = @($g.checks | ForEach-Object { $_.text })
        $at = @($own | ForEach-Object { [array]::IndexOf($shown, (Format-WorkerPerfGuidanceText ([string]$_.text) @{ app = $App; user = 'user003'; from = '02:56'; to = '02:58' })) })
        @($at | Where-Object { $_ -lt 1 }) | Should -Be @()
        @($g.checks | Where-Object { $_.text -match $Want }).Count | Should -Be 1
        # the steps of the application stand together, directly behind the steps for every named cause
        $general = @($Real.situations.$S.checks | Where-Object { $_.PSObject.Properties['when'] -and (@($_.when) -join ',') -eq 'cause.app' -and -not $_.PSObject.Properties['source'] }).Count
        ($at | Measure-Object -Minimum).Minimum | Should -Be $general
        # no step of another standard application (a step for every Office program stands word for word under Outlook too)
        $ownTexts = @($own | ForEach-Object { [string]$_.text })
        foreach ($other in @($AppList.apps | ForEach-Object { $_.key } | Where-Object { $_ -ne $Key })) {
            foreach ($el in @($Real.situations.$S.checks | Where-Object { $_.PSObject.Properties['when'] -and @($_.when) -contains "app.$other" -and $ownTexts -cnotcontains [string]$_.text })) {
                $shown | Should -Not -Contain (Format-WorkerPerfGuidanceText ([string]$el.text) @{ app = $App; user = 'user003'; from = '02:56'; to = '02:58' })
            }
        }
        foreach ($t in (Get-GuideTexts $g)) { $t | Should -Not -Match '[{}]' }
    }
    It 'fragt bei Teams zuerst nach der Medienoptimierung und nennt Einstellungen je Benutzer als solche' {      # fix round 2, B3
        foreach ($s in 'cpu', 'memory') {
            $teams = @($Real.situations.$s.checks | Where-Object { $_.PSObject.Properties['when'] -and @($_.when) -contains 'app.teams' })
            $teams[0].text | Should -Match '^Prüfen, ob Teams in der Sitzung von \{user\} mit Medienoptimierung lief' -Because $s
            $teams[0].source | Should -Be 'Citrix: Optimization for Microsoft Teams (New)'
        }
        $g = Get-Guide (New-Engpass 'cpu' @{ main = @{ app = 'ms-teams.exe'; a = 9; user = 'user003'; sharePct = 62; baselinePct = 4 } })
        $g.terms | Should -Contain 'Medienoptimierung'
        # settings a user makes for himself are named as such
        foreach ($p in 'Erweiterungen von Microsoft Edge abschalten', 'Schlafende Tabs in Microsoft Edge einschalten', 'Add-ins von \{app\}, die nicht gebraucht werden') {
            $hit = @($Elements | Where-Object { $_.List -eq 'remedies' -and $_.Texts[0] -match $p })
            $hit.Count | Should -BeGreaterThan 0 -Because $p
            foreach ($e in $hit) { $e.Texts[0] | Should -Match 'Einstellung je Benutzer' -Because $e.Position }
        }
    }
    It 'haengt jede Anwendungsbedingung an eine Anwendung der Liste und gibt jedem dieser Elemente eine Quelle' {      # fix round 2, A4, B3
        $keys = @($AppList.apps | ForEach-Object { $_.key })
        $appElements = @($Elements | Where-Object { @($_.When | Where-Object { $_ -like 'app.*' }).Count -gt 0 })
        $appElements.Count | Should -BeGreaterThan 40
        foreach ($e in $appElements) {
            $e.Source | Should -Not -BeNullOrEmpty -Because $e.Position
            foreach ($c in @($e.When | Where-Object { $_ -like 'app.*' })) { $keys | Should -Contain $c.Substring(4) -Because $e.Position }
        }
        # every standard application has steps; the four of the customer in the situations of the processor and the memory
        foreach ($k in $keys) { @($appElements | Where-Object { $_.When -contains "app.$k" }).Count | Should -BeGreaterThan 0 -Because $k }
        foreach ($k in 'edge', 'office', 'teams', 'webview2', 'outlook') {
            foreach ($s in 'cpu', 'memory') { @($appElements | Where-Object { $_.Situation -eq $s -and $_.When -contains "app.$k" }).Count | Should -BeGreaterThan 0 -Because "$s $k" }
        }
        # a step of a performance incident for an application belongs to a named cause
        foreach ($e in @($appElements | Where-Object { $_.Situation -in 'cpu', 'memory', 'disk', 'share', 'profile' })) { $e.When | Should -Contain 'cause.app' -Because $e.Position }
        # without the list the catalogue is refused
        { Read-WorkerPerfGuidance $CatalogueFile } | Should -Throw "*aber es ist keine Anwendungsliste angegeben*"
    }
    It 'nennt Workspace Environment Management als moeglichen Beteiligten an Prozessor und Arbeitsspeicher, mit der Quelle von Citrix' {      # fix round 2, B4
        $g = Get-Guide (New-Engpass 'cpu')
        $log = @($g.checks | Where-Object { $_.text -match 'Ereignisprotokoll des WEM-Agenten' })
        $log.Count | Should -Be 1; $log[0].where | Should -Match 'WEM Agent Service, Ereignisse 7001 und 7002'; $log[0].sign | Should -Match 'Priorität eines Prozesses gesenkt'
        $log[0].source | Should -Be 'Citrix: Agent event logs (WEM current release)'
        $spike = @($g.remedies | Where-Object { $_.text -match 'CPU Spikes Protection' })
        $spike.Count | Should -Be 1; $spike[0].source | Should -Be 'Citrix: CPU Management (WEM current release)'
        $spike[0].text | Should -Match 'senkt die Priorität eines Prozesses'; $spike[0].text | Should -Match 'laut Citrix nicht dafür gedacht, die Gesamtlast zu senken'
        $g.terms | Should -Contain 'Workspace Environment Management'
        $g = Get-Guide (New-Engpass 'memory')
        $log = @($g.checks | Where-Object { $_.text -match 'Ereignisprotokoll des WEM-Agenten' })
        $log.Count | Should -Be 1; $log[0].where | Should -Match 'Ereignisse 8001 bis 8003'; $log[0].sign | Should -Match 'Arbeitsspeicher untätiger Prozesse in die Auslagerungsdatei'
        $limit = @($g.remedies | Where-Object { $_.text -match 'Leerlaufgrenze der Speicheroptimierung' })
        $limit.Count | Should -Be 1; $limit[0].source | Should -Be 'Citrix: Memory Management (WEM current release)'; $limit[0].text | Should -Match 'höchstens 5 %'
        # every element that names WEM's protection or optimisation carries a source of Citrix or of practice
        foreach ($e in @($Elements | Where-Object { ($_.Texts -join ' ') -match 'CPU-Spitzenschutz|Speicheroptimierung von Citrix|WEM-Agent\b' })) { $e.Source | Should -Match ('^(Citrix: |' + $PracticeAny + ' \(Empfehlung aus der Praxis\): )') -Because $e.Position }
        # the role Citrix covers the VDA and the WEM agent: no step calls a process of the role a part of the VDA
        # (round 5: or it says itself which process it speaks about: the graphics process of the VDA, the WEM agent)
        foreach ($e in @($Elements | Where-Object { $_.When -contains 'role.Citrix' })) {
            ($e.Texts -join ' ') | Should -Match 'VDA oder Workspace Environment Management|\{app\} ein Prozess des WEM-Agenten ist|^Wenn \{app\} der Grafikprozess des VDA ist \(ctxgfx\.exe\): |^Wenn \{app\} zum WEM-Agenten gehört' -Because $e.Position
        }
        # of the steps for a Citrix component only the first begins with the general sentence; the others name their process
        @($Elements | Where-Object { $_.When -contains 'role.Citrix' -and $_.List -eq 'checks' -and $_.Texts[0] -match '^\{app\} gehört zu den Citrix-Komponenten' }).Count | Should -Be 2
    }
    It 'setzt bei der Zuordnung der Drucker keine Citrix-Richtlinien voraus und nennt die Punkte des Herstellers des Zuordnungswerkzeugs mit ihrer Version' {      # fix round 2, B5
        $print = @($Elements | Where-Object { $_.Situation -eq 'print' })
        # a step that depends on Citrix policies or on printers created by Citrix says so
        foreach ($e in @($print | Where-Object { $_.List -eq 'checks' -and $_.Texts[0] -match 'Citrix-Richtlinie „' })) { $e.Texts[0] | Should -Match '^Wenn die Drucker über Citrix-Richtlinien zugeordnet werden: ' -Because $e.Position }
        foreach ($e in @($Elements | Where-Object { $_.List -eq 'remedies' -and $_.Texts[0] -match 'Citrix-Richtlinie „|Citrix-Universaltreiber als Regel' })) {
            $e.Texts[1] | Should -Match 'die Drucker über Citrix-Richtlinien zugeordnet werden|Citrix die Drucker anlegt' -Because $e.Position
        }
        @($print | Where-Object { ($_.Texts -join ' ') -match 'werden die Drucker in den Sitzungen nicht angelegt' }) | Should -Be @()
        # the general step on the mapping at logon and reconnect is the report's own note and names no product
        $own = @($print | Where-Object { $_.Texts[0] -match '^Wenn ein Zuordnungswerkzeug die Drucker zuordnet: ' })
        $own.Count | Should -Be 1; $own[0].Source | Should -BeExactly $OwnSource; $own[0].When | Should -Be @()
        $own[0].Texts[0] | Should -Match 'bei der Anmeldung und nach einer Wiederverbindung'; ($own[0].Texts -join ' ') | Should -Not -Match 'PrinTaurus|AKI'
        # the vendor's points: each in an element of its own source, with the version the release notes name
        $aki = @($Elements | Where-Object { $_.Source -like 'AKI: *' })
        @($aki | ForEach-Object { $_.Source } | Sort-Object -Unique) | Should -Be @('AKI: Release Notes 6.2 deutsch', 'AKI: Release Notes PrinTaurus 6.4')
        $points = @{ 'zum selben Release|denselben Release-Stand' = '6\.4'; 'doppelt angezeigten Druckern auf Version 6\.4' = 'älter als Version 6\.4'
            'Lokale IPP-Druckerwarteschlangen' = 'PrinTaurus 6\.4 im Einsatz'; 'Standarddrucker' = '6\.2' }
        foreach ($p in $points.Keys) {
            $hit = @($aki | Where-Object { $_.Situation -eq 'print' -and ($_.Texts -join ' ') -match $p })
            $hit.Count | Should -BeGreaterThan 0 -Because $p
            foreach ($e in $hit) { ($e.Texts -join ' ') | Should -Match $points[$p] -Because "$($e.Position): $p" }
        }
        foreach ($e in @($aki | Where-Object { $_.Situation -eq 'print' -and $_.List -eq 'remedies' })) { $e.Texts[1] | Should -Match '6\.[24]' -Because $e.Position }
        # outside the print situation the vendor's elements hang on its client; the list of driver vendors is not extended
        foreach ($e in @($aki | Where-Object { $_.Situation -ne 'print' })) { $e.When | Should -Contain 'app.printaurus' -Because $e.Position }
        @($Real.vendors | ForEach-Object { $_.key }) | Should -Be @('HP', 'Kyocera', 'Brother', 'Microsoft', 'Citrix')
        foreach ($kind in 'crash', 'hang') {
            $g = Get-Guide (New-Inc @{ type = 'ereignis'; start = [long]1e12; end = [long]1e12; event = @{ kind = $kind; app = 'PtSmartSpreadClient.exe'; users = @('user003'); sessions = @(3) } })
            $g.conditions | Should -Contain 'app.printaurus'
            @($g.checks | Where-Object { $_.source -like 'AKI: *' }).Count | Should -BeGreaterThan 0 -Because $kind
        }
    }
    It 'formuliert eine Empfehlung aus der Praxis nie als Empfehlung des Herstellers und nennt beim Energiesparplan die Sicht der Hersteller' {      # fix round 2, B6 (spec 5.7)
        $practice = @($Elements | Where-Object { $_.Source -match 'Empfehlung aus der Praxis' })
        $practice.Count | Should -BeGreaterThan 10
        # every one of the twelve sources has elements (round 5), and no other name carries the mark
        # Aussage angepasst (final fix wave, item 4): the collection of John Billekens only backs elements since then; every
        # statement it carried is the vendor's, and the vendor's document is the source
        @($practice | ForEach-Object { ($_.Source -split ' \(', 2)[0] } | Sort-Object -Unique) | Should -Be @($PracticeNames | Where-Object { $_ -ne 'John Billekens' } | Sort-Object)
        foreach ($e in $practice) {
            $e.Source | Should -Match ('^' + $PracticeAny + ' \(Empfehlung aus der Praxis\): .+') -Because $e.Position
            $all = $e.Texts -join ' '
            $all | Should -Match 'Empfehlung aus der Praxis|Praxisquelle' -Because $e.Position
            $all | Should -Not -Match 'laut (Microsoft|Citrix|VMware)|(Microsoft|Citrix|VMware) empfiehlt|empfiehlt (Microsoft|Citrix|VMware)' -Because $e.Position
        }
        # the power plan: the practice sources rule (the customer's exception), the text names the vendors' view
        $power = @($practice | Where-Object { ($_.Texts -join ' ') -match 'Energiesparplan' })
        @($power | ForEach-Object { $_.Situation } | Sort-Object -Unique) | Should -Be @('cpu', 'delay.many', 'delay.single')
        foreach ($e in $power) {
            $all = $e.Texts -join ' '
            $all | Should -Match '„Höchstleistung“' -Because $e.Position
            $all | Should -Match 'Microsoft liefert Windows Server mit „Ausbalanciert“ aus|Microsoft Windows Server mit „Ausbalanciert“ ausliefert' -Because $e.Position
            $all | Should -Match 'VMware .*„Höchstleistung“ bei der Suche nach der Ursache von Leistungs- und Latenzproblemen' -Because $e.Position
        }
        @($power | Where-Object { $_.List -eq 'remedies' }).Count | Should -Be 3
        foreach ($e in @($power | Where-Object { $_.List -eq 'remedies' })) { $e.Texts[0] | Should -Match ([regex]::Escape($InImage)) -Because $e.Position; $e.Source | Should -BeLike 'BIS-F *' }
        foreach ($n in 1, 3) {
            $g = Get-Guide (New-Inc @{ type = 'ohne-engpass'; affected = @(1..$n | ForEach-Object { @{ s = $_ } }) })
            @($g.checks | Where-Object { $_.text -eq 'Energiesparplan des Servers feststellen' }).Count | Should -Be 1 -Because "$n Sitzungen"
            @($g.remedies | Where-Object { $_.text -match '^Energiesparplan „Höchstleistung“ einstellen' }).Count | Should -Be 1 -Because "$n Sitzungen"
            $g.terms | Should -Contain 'Energiesparplan'
        }
        # receive-side scaling follows the vendor: the catalogue has no word about it
        @($Elements | Where-Object { ($_.Texts -join ' ') -match 'Receive Side Scaling|RSS' }) | Should -Be @()
        # nothing that only holds for Provisioning Services
        @($Elements | Where-Object { ($_.Texts -join ' ') -match 'Provisioning|PVS|Schreibcache' }) | Should -Be @()
    }
    It 'gibt jedem Element aus der Praxis eine der zwoelf Quellen mit Titel und nur Bedingungen, die der Lader kennt' {      # round 5 (rulings P3-R68, P3-R69)
        $practice = @($Elements | Where-Object { $_.Source -match 'Empfehlung aus der Praxis' })
        $practice.Count | Should -BeGreaterThan 55      # Aussage angepasst (final fix wave, item 4): 58, eleven elements carry the vendor's document now
        $signals = [string[]]@((Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json')).Keys)
        foreach ($e in $practice) {
            $name, $title = $e.Source -split ' \(Empfehlung aus der Praxis\): ', 2
            $PracticeNames | Should -Contain $name -Because $e.Position
            $title | Should -Not -BeNullOrEmpty -Because $e.Position; $title | Should -Not -Match '\|' -Because $e.Position
            foreach ($c in $e.When) { Test-WorkerPerfGuidanceCondition $c $Real $signals $AppList | Should -BeTrue -Because "$($e.Position): $c" }
            # a step of a performance incident for an application belongs to a named cause; no condition that never holds there
            if ($e.Situation -in 'delay.many', 'delay.single', 'chronic.network') { @($e.When | Where-Object { $_ -like 'cause.*' -or $_ -like 'app.*' -or $_ -like 'role.*' }) | Should -Be @() -Because $e.Position }
        }
        # each of the ten sources of this round has elements of its own
        # Aussage angepasst (final fix wave, item 4): John Billekens backs only (section „Stützt bestehende Elemente“)
        foreach ($n in @($PracticeNames | Where-Object { $_ -notin 'Carl Stalhood', 'BIS-F', 'John Billekens' })) { @($practice | Where-Object { $_.Source -like "$n (*" }).Count | Should -BeGreaterThan 0 -Because $n }
        @($practice | Where-Object { $_.Source -like 'John Billekens (*' }) | Should -Be @()
        # Kasper Johansen's blog is gone and is not used; Trentent Tye only by his own site
        @($Elements | Where-Object { ($_.Texts + $_.Source) -join ' ' -match 'Johansen|theorypc' }) | Should -Be @()
        # a measured number of a source from practice stands with its year: every statement (the part of a text between
        # two semicolons) that names one of the ten or says "Praxisquelle" and holds a number of seconds, percent or
        # megabytes also names a year, and a year that is part of a product name (Windows Server 2019) does not count
        $numbered = 0
        foreach ($e in $Elements) { foreach ($t in $e.Texts) { foreach ($missing in @(Get-NumberWithoutYear $t)) { $missing | Should -BeNullOrEmpty -Because $e.Position }; $numbered += @(Get-Statements $t | Where-Object { Test-MeasuredStatement $_ }).Count } }
        $numbered | Should -BeGreaterThan 8
        # the test fails when the year goes, and when only the version of a product is left (fix round 1, item 10)
        $with = 'die Praxisquelle James Rankin (2021, Labor mit Windows 10, Group Policy Preferences, sechs Ziele) maß beim Verbinden etwa 33 Sekunden Zeitüberschreitung je nicht erreichbarer Zuordnung'
        @($Elements | Where-Object { $_.Texts[0].Contains($with) }).Count | Should -Be 2
        @(Get-NumberWithoutYear $with) | Should -Be @()
        @(Get-NumberWithoutYear $with.Replace('(2021, Labor', '(Labor')).Count | Should -Be 1
        @(Get-NumberWithoutYear $with.Replace('(2021, Labor mit Windows 10', '(Labor mit Windows Server 2019')).Count | Should -Be 1
        @(Get-NumberWithoutYear 'nach James Rankin (Test mit Windows Server 2019 und Office 2016) dauerte die Anmeldung 40 Sekunden länger').Count | Should -Be 1
        @(Get-NumberWithoutYear 'der Schritt dauert 40 Sekunden; nach James Rankin (2021) ist das üblich') | Should -Be @()
    }
    It 'haelt die frueheren Schritte auch ohne einzelnen Verursacher und bei nicht Gemessenem in Sicht' {      # round 5, fix round 1, item 1 (ruling P3-R75)
        # incidents the test reports do not hold: without a single cause, as a chronic state, with a category left out
        $long = @{ chronic = $true; end = [long](1e12 + 4200000); cause = @{ kind = 'none' }; main = $null }
        $cases = [ordered]@{
            'Arbeitsspeicher ohne Verursacher' = (New-Engpass 'memory' @{ cause = @{ kind = 'none' }; main = $null })
            'Prozessor ohne Verursacher' = (New-Engpass 'cpu' @{ cause = @{ kind = 'none' }; main = $null })
            'Freigabe ohne Verursacher' = (New-Engpass 'share' @{ cause = @{ kind = 'none' }; main = $null })
            'Dauerzustand Prozessor' = (New-Engpass 'cpu' $long); 'Dauerzustand Arbeitsspeicher' = (New-Engpass 'memory' $long)
            'Systemfehler' = (New-Inc @{ type = 'ereignis'; event = @{ kind = 'system'; count = 1; patterns = @() } })
        }
        foreach ($name in $cases.Keys) { $g = Get-Guide $cases[$name]; @($g.checks).Count | Should -BeGreaterThan 2 -Because $name; @(Get-OutOfView $g) | Should -Be @() -Because $name }
        # where no step with a more telling condition from practice is shown, the order holds as well: the earlier steps lead
        foreach ($name in 'Arbeitsspeicher ohne Verursacher', 'Freigabe ohne Verursacher', 'Dauerzustand Prozessor', 'Systemfehler') { @(Get-Displaced (Get-Guide $cases[$name])) | Should -Be @() -Because $name }
        # with -Skip Prozesse the two notes on the cause that was not measured stand before every general step from practice
        $ctx = New-Ctx; $ctx.Data.skipped = @(@{ id = 'Prozesse'; label = 'Prozesse'; text = ''; places = @() }); $ctx.Data.apps = @()
        foreach ($s in 'cpu', 'memory', 'disk', 'share', 'profile') {
            $g = Get-Guide (New-Engpass $s @{ cause = @{ kind = 'notmeasured' }; main = $null }) $ctx
            @(Get-OutOfView $g) | Should -Be @() -Because $s
            $at = [array]::IndexOf(@($g.checks | ForEach-Object { $_.text -match 'ohne „-Skip Prozesse“ wiederholen' }), $true); $at | Should -BeGreaterThan 0 -Because $s
            for ($k = 0; $k -lt $at; $k++) { [string]$g.checks[$k].source | Should -Not -Match $RoundFiveSource -Because "$s, Schritt $($k + 1)" }
        }
        # a delay with drives and endpoints not measured: the notes on both gaps before the general steps from practice
        $ctx = New-Ctx; $ctx.Data.sollIst = @(@{ id = 'probe.connect'; measured = $false })
        $ctx.Data.skipped = @(@{ id = 'Laufwerke'; label = 'Laufwerke'; text = ''; places = @() }, @{ id = 'Gegenstellen'; label = 'Gegenstellen'; text = ''; places = @() })
        foreach ($n in 1, 3) {
            $g = Get-Guide (New-Inc @{ type = 'ohne-engpass'; unverified = $true; affected = @(1..$n | ForEach-Object { @{ s = $_ } }) }) $ctx
            @(Get-OutOfView $g) | Should -Be @() -Because "$n Sitzungen"; @(Get-Displaced $g) | Should -Be @() -Because "$n Sitzungen"
            $gapAt = @(0..(@($g.checks).Count - 1) | Where-Object { $g.checks[$_].text -match 'nicht gemessen' }); $gapAt.Count | Should -Be 2 -Because "$n Sitzungen"
            for ($k = 0; $k -lt $gapAt[-1]; $k++) { [string]$g.checks[$k].source | Should -Not -Match $RoundFiveSource -Because "$n Sitzungen, Schritt $($k + 1)" }
            @($g.checks | Where-Object { [string]$_.source -match $RoundFiveSource }).Count | Should -BeGreaterThan 1 -Because "$n Sitzungen"
        }
        # how the catalogue reaches it: the statement of the source is a sentence of the catalogue's own step
        foreach ($place in @{ S = 'memory'; Start = 'Prüfen, ob der Server mehr Sitzungen trägt als die anderen Server' },
            @{ S = 'chronic.resource'; Start = 'Auslastung des Prozessors mit den anderen Servern derselben Bereitstellungsgruppe vergleichen' },
            @{ S = 'chronic.resource'; Start = 'Auslastung des Arbeitsspeichers mit den anderen Servern derselben Bereitstellungsgruppe vergleichen' }) {
            $own = @($Real.situations.($place.S).checks | Where-Object { ([string]$_.text).StartsWith($place.Start) }); $own.Count | Should -Be 1 -Because $place.Start
            $own[0].PSObject.Properties['source'] | Should -BeNullOrEmpty -Because $place.Start
            $own[0].text | Should -Match 'die Praxisquelle Manuel Winkel \(2026\) beschreibt aus einem einzelnen Kundenfall' -Because $place.Start
        }
        @($Elements | Where-Object { $_.Situation -in 'memory', 'chronic.resource' -and $_.Texts[0] -match '^Trägt der Server deutlich mehr Sitzungen' }) | Should -Be @()
        @($Elements | Where-Object { $_.Texts[0] -match '^Programme ansehen, die in jeder Sitzung von selbst starten' }) | Should -Be @()
        # the cache of MCS I/O in the chronic state: a sentence of the catalogue's own step on the sizing of the server
        @($Elements | Where-Object { $_.Situation -eq 'chronic.resource' -and $_.Texts[0] -match '^Wenn der Maschinenkatalog MCS I/O' }) | Should -Be @()
        $sizing = @($Real.situations.'chronic.resource'.checks | Where-Object { ([string]$_.text).StartsWith('Kein einzelner Verursacher: Auslegung des Servers für den Arbeitsspeicher') }); $sizing.Count | Should -Be 1
        $sizing[0].where | Should -Match 'laut Citrix ist der Cache Teil des Arbeitsspeichers der Maschine; nach GO-EUC \(Test von 2020 mit Windows 10 und einer einzelnen Maschine\)'; $sizing[0].PSObject.Properties['source'] | Should -BeNullOrEmpty
        # the order of the file: the practice step on MCS I/O after the catalogue's general steps on the drive, the one on
        # the full drive after those of the system messages, the contact for the storage system after the main contact
        foreach ($place in @{ S = 'disk'; L = 'checks'; Own = 'Prüfen, ob die Verzögerung am Laufwerk regelmäßig auftritt'; New = 'Wenn der Maschinenkatalog MCS I/O nutzt' },
            @{ S = 'memory'; L = 'checks'; Own = 'Prüfen, ob der Speichermangel regelmäßig auftritt'; New = 'Wenn der Maschinenkatalog MCS I/O nutzt' },
            @{ S = 'system'; L = 'checks'; Own = 'Prüfen, ob dieselbe Meldung an weiteren Tagen auftrat'; New = 'Wenn der Datenträger- oder Dateisystemfehler das Systemlaufwerk' },
            @{ S = 'share'; L = 'contacts'; Own = 'Betreuung von Dateiserver und Netz'; New = 'Betreuung des Speichersystems unter dem Dateiserver' }) {
            $texts = @($Real.situations.($place.S).($place.L) | ForEach-Object { [string]$_.text })
            $a = @(0..($texts.Count - 1) | Where-Object { $texts[$_].StartsWith($place.Own) }); $b = @(0..($texts.Count - 1) | Where-Object { $texts[$_].StartsWith($place.New) })
            $a.Count | Should -Be 1 -Because $place.Own; $b.Count | Should -Be 1 -Because $place.New; $b[0] | Should -BeGreaterThan $a[0] -Because $place.New
            # Aussage angepasst (final fix wave, parked item): the step on MCS I/O of the memory stands only without a single
            # cause, with the source of Citrix; the others stay general
            if ($place.S -eq 'memory') { @($Real.situations.memory.checks[$b[0]].when) | Should -Be @('cause.none'); continue }
            $Real.situations.($place.S).($place.L)[$b[0]].PSObject.Properties['when'] | Should -BeNullOrEmpty -Because $place.New
        }
    }
    It 'nennt jede Quelle aus der Praxis im Text beim Namen und sagt, was sie maß, mit den Bedingungen der Messung' {      # round 5, fix round 1, items 2, 3, 6, 7, 9
        # the copy text prints no source: the first "Praxisquelle" of an element is followed by the name of its source
        # (item 6); in the whole catalogue no "Praxisquelle" stands without a name of the twelve after its first mention
        $name = '^ (' + (($PracticeNames | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')(?![\p{L}])'
        $said = 0
        foreach ($e in $Elements) {
            $all = $e.Texts -join ' | '; $at = $all.IndexOf('Praxisquelle'); if ($at -lt 0) { continue }
            $said++; $after = $all.Substring($at + 'Praxisquelle'.Length) -creplace '^n(?= )', ''
            $after | Should -MatchExactly $name -Because "$($e.Position): $($all.Substring($at, [Math]::Min(60, $all.Length - $at)))"
            if ($e.Source -match [regex]::Escape($PracticeMark)) { $after | Should -MatchExactly ('^ ' + [regex]::Escape(($e.Source -split ' \(', 2)[0])) -Because $e.Position }
        }
        $said | Should -BeGreaterThan 55
        $byStart = { param($s, $l, $start) $hit = @($Elements | Where-Object { $_.Situation -eq $s -and $_.List -eq $l -and $_.Texts[0].StartsWith($start) }); $hit.Count | Should -Be 1 -Because "$s $l $start"; $hit[0] }
        # item 2: what James Rankin keeps redirected
        $t = (& $byStart 'share' 'remedies' 'AppData und Startmenü aus der Ordnerumleitung nehmen').Texts[0]
        $t | Should -Match 'James Rankin \(2018\) nennt Dokumente, Bilder und ähnliche Datenordner, lässt den Desktop aber im Profilcontainer'; $t | Should -Not -Match 'nur Dokumente'
        # item 3: a measured value with its conditions in the sentence of the element
        foreach ($s in 'delay.many', 'delay.single') {
            (& $byStart $s 'checks' 'Wenn Anwendungen beim Start der Sitzung').Texts[0] | Should -Match 'Guy Leech \(2016, ein Fall mit XenApp 7\.7 und Receiver 4\.4\) fand das als Ursache einer Wartezeit von 18 bis 20 Sekunden' -Because $s
            (& $byStart $s 'checks' $(if ($s -eq 'delay.many') { 'Wenn die Benutzer im Explorer' } else { 'Wenn der Benutzer im Explorer' })).Texts[0] | Should -Match 'James Rankin \(2021, Labor mit Windows 10, Group Policy Preferences, sechs Ziele\) maß beim Verbinden etwa 33 Sekunden' -Because $s
        }
        $smb = @($Elements | Where-Object { $_.Texts[0] -match 'DisableBandwidthThrottling' }); $smb.Count | Should -Be 3
        # Aussage angepasst (final fix wave, item 15): one statement per sentence; the change on the file server a sentence of its own;
        # the measurement in the remedy under a share only (the two of the chronic state have one text, see the record)
        foreach ($e in @($smb | Where-Object { $_.Situation -eq 'share' })) { $e.Texts[0] | Should -Match 'James Rankin \(2021\) maß im Labor mit FSLogix und einem Dateiserver 12 statt 17 Sekunden Anmeldung; dabei hatte er auch den Dateiserver geändert' -Because $e.Position }
        # Aussage angepasst (final fix wave, item 14): the finding stands in the text, the field "Wo" names places only
        (& $byStart 'memory' 'checks' 'Kein einzelner Verursacher: Arbeitsspeicher je Sitzung').Texts[0] | Should -Match 'nach Thomas Kötzing \(Durchsicht eines Terminalservers von 2018\).*20 bis 25 MB je Benutzer'
        (& $byStart 'profileerror' 'remedies' '„Automatically reattach VHDX disks“').Texts[0] | Should -Match 'Thomas Kötzing \(2026\).*auf nicht persistenten Servern etwa 5 Sekunden längere Anmeldungen \(seine Angabe, keine Messreihe\)'
        (& $byStart 'memory' 'remedies' 'Leerlaufgrenze der Speicheroptimierung').Texts[0] | Should -Match 'Manuel Winkel \(2022, Stand WEM 2206\) nutzt sie mit einer Leerlaufgrenze von 3 %'
        # numbers that say nothing to do under the incident are gone from the elements (the record keeps them)
        @($Elements | Where-Object { ($_.Texts -join ' ') -match '40 Sekunden|5,9 Sekunden|150 Sekunden|500 MB|7 bis 9 Sekunden|1000 ms' }) | Should -Be @()
        # item 7: the clause without a place in WEM is gone
        $spike = (& $byStart 'cpu' 'remedies' 'CPU-Spitzenschutz von Citrix Workspace Environment Management').Texts[0]
        $spike | Should -Not -Match 'Leech|Prozesse der Benutzer herabstufen'; $spike | Should -Match 'nach James Kindon \(2023\) die Grenze von WEM selbst bestimmen lassen \(„Auto Prevent CPU Spikes“\)'
        # item 9: each source with its own reason; the vendor named for what the vendor says
        $rt = (& $byStart 'cpu' 'checks' 'In Workspace Environment Management prüfen, ob einem Prozess').Texts[0]
        $rt | Should -Match 'Manuel Winkel \(2022\) rät davon ab, weil das zu Fehlfunktionen des Systems führen kann'; $rt | Should -Match 'Guy Leech \(2016\) rät ebenfalls davon ab, weil ein rechenintensiver Prozess'
        $ms = (& $byStart 'memory' 'remedies' 'Optimierung für getrennte Sitzungen').Texts[0]
        $ms | Should -Match 'Citrix beschreibt, dass WEM dann nur bei getrennten Sitzungen eingreift'; $ms | Should -Match 'die Praxisquelle James Kindon \(2023\) nennt die Funktion nützlich'
        $scan = @($Elements | Where-Object { $_.List -eq 'remedies' -and $_.Texts[0] -match '^Scan-Ausschlüsse ergänzen, die für Terminalserver üblich sind' }); $scan.Count | Should -Be 4
        foreach ($e in $scan) { $e.Texts[0] | Should -Not -Match 'Rankin|Anmeldung' -Because $e.Position; $e.Texts[0] | Should -Match 'die Sammlung von John Billekens' -Because $e.Position }
        # Aussage angepasst (final fix wave, items 1 and 12): the WEM agent by its processes only, the source named in the text
        foreach ($s in 'cpu', 'disk') {
            $wem = (& $byStart $s 'checks' 'Ausschlüsse der Schutzsoftware mit der Empfehlung der Praxisquelle Carl Stalhood (2024) vergleichen').Texts
            $wem[0] | Should -Match 'mit WEM-Agent auch dessen Prozesse mit vollem Pfad; Microsoft führt Programmordner installierter Anwendungen unter den Ordnern, die man bei Microsoft Defender nicht ausnehmen soll$' -Because $s
            $wem[1] | Should -Not -Match 'Defender' -Because $s
        }
        # Aussage angepasst (final fix wave, item 3): three short statements; the two views of practice stand in the record
        $edt = (& $byStart 'chronic.network' 'checks' 'Feststellen, über welchen Transport')
        @(Get-Statements $edt.Texts[0]).Count | Should -Be 3
        $edt.Texts[0] | Should -Match 'die Voreinstellung von Citrix ist „Preferred“ \(EDT mit Rückfall auf TCP\) und bleibt die Regel'; $edt.Texts[0] | Should -Match 'die Betreuung des Netzes die MTU auf dieser Strecke prüfen lassen$'
        ($edt.Texts -join ' ') | Should -Not -Match 'Stalhood|Adaptive Transport|abschalten|dieses Berichts'; $edt.Texts[2] | Should -Match 'wie die Praxisquelle Thomas Kötzing \(2025\) sie beschreibt$'
        # Aussage angepasst (final fix wave, item 4): the vendor's statement under the vendor's source
        (& $byStart 'memory' 'checks' 'Wenn der Maschinenkatalog MCS I/O nutzt').Texts[0] | Should -Match 'laut Citrix ist der Cache Teil des Arbeitsspeichers der Maschine; nach der Praxisquelle GO-EUC \(Test von 2020 mit Windows 10 und einer einzelnen Maschine\)'
        foreach ($e in (& $byStart 'cpu' 'remedies' 'Sitzungen gleichmäßiger auf die Server verteilen'), (& $byStart 'chronic.resource' 'remedies' 'Kapazität anpassen (weniger Sitzungen je Server, zusätzliche Server oder mehr Prozessoren')) {
            $e.Texts[0] | Should -Match 'laut VMware soll eine virtuelle Maschine nicht mehr vCPU haben, als ihre Last nutzen kann' -Because $e.Position
            $e.Texts[0] | Should -Match 'Ausgangspunkte? aus der Praxis und kein Sollwert für diese Server' -Because $e.Position
        }
        (& $byStart 'delay.many' 'checks' 'Prüfen lassen, ob der VMware-Host').Texts[0] | Should -Match 'nach Angabe von VMware zeigt ein anhaltend hoher Wert meist einen Engpass am Host'
    }
    It 'schlaegt das Abschalten der SMB-Drosselung nur mit der Strecke als Voraussetzung vor und immer als letzten Vorschlag' {      # round 5, fix round 1, item 4; final fix wave, item 7
        $smb = @($Elements | Where-Object { $_.Texts[0] -match '^Drosselung des SMB-Clients abschalten' })
        # final fix wave, item 7: no gate on a named cause (the path to the file server has nothing to do with the cause)
        @($smb | ForEach-Object { "$($_.Situation) $($_.When -join '+')" }) | Should -Be @('share ', 'chronic.resource lead.share', 'chronic.resource lead.profile')
        foreach ($e in $smb) { $e.Source | Should -BeExactly 'Microsoft: Optimizing Windows configuration for VDI desktops' -Because $e.Position }
        foreach ($e in $smb) {
            $e.Texts[0] | Should -Match 'der SMB-Client drosselt nach Angabe von Microsoft nur auf Verbindungen mit hoher Laufzeit' -Because $e.Position
            $e.Texts[0] | Should -Match 'Microsoft rät in seiner Anleitung für VDI mit Windows 10 und 11, den Wert auf 1 zu setzen' -Because $e.Position
            $e.Texts[0] | Should -Match ([regex]::Escape($InImage)) -Because $e.Position; $e.Texts[0] | Should -Not -Match 'erwägen' -Because $e.Position
            $e.Texts[1] | Should -Match 'und die Server ihn über eine Strecke mit hoher Laufzeit erreichen \(anderer Standort, WAN\)$' -Because $e.Position
            # the last of its list in the file
            $list = @($Real.situations.($e.Situation).remedies); [int]($e.Position -replace '^.*\[(\d+)\]$', '$1') | Should -BeGreaterOrEqual ($list.Count - 2) -Because $e.Position
        }
        # shown: last, behind the remedy for the named application; without a named application last as well
        foreach ($s in 'share', 'profile') {
            foreach ($chronic in $false, $true) {
                if ($s -eq 'profile' -and -not $chronic) { continue }
                $over = @{}; if ($chronic) { $over = @{ chronic = $true; end = [long](1e12 + 4200000) } }
                $g = Get-Guide (New-Engpass $s $over)
                $at = [array]::IndexOf(@($g.remedies | ForEach-Object { $_.text -match '^Drosselung des SMB-Clients' }), $true)
                $at | Should -Be (@($g.remedies).Count - 1) -Because "$s $chronic"; $at | Should -BeGreaterThan 0 -Because "$s $chronic"
                foreach ($kind in 'none', 'nodata', 'notmeasured') {
                    $g = Get-Guide (New-Engpass $s ($over + @{ cause = @{ kind = $kind }; main = $null }))
                    $at = [array]::IndexOf(@($g.remedies | ForEach-Object { $_.text -match '^Drosselung des SMB-Clients' }), $true)
                    $at | Should -Be (@($g.remedies).Count - 1) -Because "$s $chronic $kind"
                }
            }
        }
    }
    It 'nimmt nie den Programmordner einer Anwendung vom Scan aus' {      # final fix wave, item 1
        # a statement (the part of a text between two semicolons) that names a program folder together with an exclusion
        # says that it is not to be excluded
        $folder = 'Programm(-| )?ordner|Programm- und Datenordner|Programmverzeichnis|Installationsordner|Ordner viel genutzter Anwendungen'
        $exclude = 'ausnehm|ausgenommen|Ausschluss|Ausschlüsse|ausschließ'
        $wrong = { param([string]$Text) @(Get-Statements $Text | Where-Object { $_ -match $folder -and $_ -match $exclude -and $_ -notmatch '\bnicht\b' }) }
        foreach ($e in $Elements) { foreach ($t in $e.Texts) { @(& $wrong $t) | Should -Be @() -Because $e.Position } }
        # the rule finds the wording of before
        @(& $wrong 'Scan-Ausschluss für die Programm- und Datenordner des größten I/O-Erzeugers einrichten (…)').Count | Should -Be 1
        @(& $wrong 'Echtzeitprüfung ohne Scan-Ausschluss für die Ordner viel genutzter Anwendungen').Count | Should -Be 1
        @(& $wrong 'Auslagerungsdatei und Ereignisprotokolle vom Scan ausgenommen, mit WEM-Agent auch dessen Programmordner oder Prozesse').Count | Should -Be 1
        # the exclusions for the largest I/O producer: its processes with the full path, data folders only where its vendor names
        # them, the program folder not, with Microsoft's page as the source
        # (Microsoft's own scoped exclusions for the WebView2 runtime stand under that application, as its vendor names them)
        $companion = @($Elements | Where-Object { $_.When -contains 'companion.security' -and @($_.When).Count -eq 1 -and $_.List -eq 'remedies' })
        @($companion | ForEach-Object { $_.Situation }) | Should -Be @('cpu', 'disk', 'share', 'profile')
        foreach ($e in $companion) {
            $e.Texts[0] | Should -Match '^Ausschlüsse für den größten I/O-Erzeuger so einrichten, wie sein Hersteller sie nennt, also seine Prozesse mit vollem Pfad und Datenordner nur, wo der Hersteller sie nennt' -Because $e.Position
            $e.Texts[0] | Should -Match 'den Programmordner der Anwendung nicht ausnehmen, denn Microsoft führt die Programmordner installierter Anwendungen unter den Ordnern, die man bei Microsoft Defender nicht ausnehmen soll$' -Because $e.Position
            $e.Source | Should -BeExactly 'Microsoft: Exclusions to avoid in Microsoft Defender Antivirus and Defender for Endpoint' -Because $e.Position
        }
        foreach ($e in @($Elements | Where-Object { $_.When -contains 'companion.security' -and @($_.When).Count -eq 1 -and $_.List -eq 'checks' })) { $e.Texts[2] | Should -BeExactly 'Prozess dieser Anwendung ohne Ausschluss, obwohl ihr Hersteller einen nennt' -Because $e.Position }
    }
    It 'setzt die Punkte der abschliessenden Pruefung im Katalog um' {      # final fix wave, items 2 to 16
        $byStart = { param($s, $l, $start) $hit = @($Elements | Where-Object { $_.Situation -eq $s -and $_.List -eq $l -and $_.Texts[0].StartsWith($start) }); $hit.Count | Should -Be 1 -Because "$s $l $start"; $hit[0] }
        # item 2: the end of support of Teams on Windows Server 2022 has passed; crashes and hangs say so, and no upgrade is Microsoft's advice
        foreach ($s in 'crash', 'hang') {
            $t = & $byStart $s 'checks' 'Stand der Unterstützung von Teams auf dem Betriebssystem des Servers einordnen'
            $t.When | Should -Be @('app.teams'); $t.Source | Should -BeExactly 'Microsoft: Install Teams for Virtualized Desktop Infrastructure (VDI)'
            $t.Texts[0] | Should -Match 'seit Oktober 2026 unterstützt Microsoft Teams auf Windows Server 2022 nicht mehr \(Hinweis auf der Seite zu Teams für VDI, Stand der Seite 25\.8\.2026\)'
            $t.Texts[0] | Should -Not -Match 'nennt Oktober 2026 als Ende'
        }
        @($Elements | Where-Object { ($_.Texts -join ' ') -match 'Microsoft (rät|empfiehlt)[^;]*(Wechsel|Upgrade|Server 2025)' }) | Should -Be @()
        # item 4: where the vendor's statement carries the element, the vendor's document is its source
        $vendor = [ordered]@{
            'memory checks Wenn der Maschinenkatalog MCS I/O nutzt' = 'Citrix: Create machine catalogs'; 'disk checks Wenn der Maschinenkatalog MCS I/O nutzt' = 'Citrix: Create machine catalogs'
            'cpu remedies Sitzungen gleichmäßiger auf die Server verteilen' = 'VMware: Rightsizing virtual machines on ESXi 8.0: vCPU, memory, and CPU topology guidance'
            'chronic.resource remedies Kapazität anpassen (weniger Sitzungen je Server, zusätzliche Server oder mehr Prozessoren' = 'VMware: Rightsizing virtual machines on ESXi 8.0: vCPU, memory, and CPU topology guidance'
            'delay.many checks Prüfen lassen, ob der VMware-Host' = 'VMware: Rightsizing virtual machines on ESXi 8.0: vCPU, memory, and CPU topology guidance'
            'crash checks Prüfen, ob die Datendateien von Outlook' = 'Microsoft: Planning considerations to deploy Outlook for Windows'; 'hang checks Prüfen, ob die Datendateien von Outlook' = 'Microsoft: Planning considerations to deploy Outlook for Windows'
            'cpu remedies Signaturen der Schutzsoftware im Master-Image' = 'Citrix: Endpoint Security, Antivirus, and Antimalware Best Practices'; 'disk remedies Signaturen der Schutzsoftware im Master-Image' = 'Citrix: Endpoint Security, Antivirus, and Antimalware Best Practices'
            'share remedies Active write back der Citrix Profilverwaltung' = 'Citrix: Configure active write-back' }
        foreach ($k in $vendor.Keys) { $s, $l, $start = $k -split ' ', 3; (& $byStart $s $l $start).Source | Should -BeExactly $vendor[$k] -Because $k }
        # and no source from practice carries a statement of a vendor in these words; an element without a source neither (the
        # catalogue's own step on the sizing of the server in a chronic state names Citrix in its "Wo" since round 5)
        $said = '(?<![\p{L}])(nach Angabe von (Citrix|Microsoft|VMware)|laut (Citrix|Microsoft|VMware)|(Citrix|Microsoft|VMware) (schreibt|nennt denselben Grund|rät in seinem Leitfaden))'
        foreach ($e in @($Elements | Where-Object { $_.Source -match 'Empfehlung aus der Praxis' -or (-not $_.Source -and -not $_.Texts[0].StartsWith('Kein einzelner Verursacher: Auslegung des Servers für den Arbeitsspeicher')) })) {
            ($e.Texts -join ' ') | Should -Not -Match $said -Because $e.Position
        }
        # item 5: Active write back as Citrix writes it, Citrix's own view first, Stalhood's as the other view
        $awb = & $byStart 'share' 'remedies' 'Active write back der Citrix Profilverwaltung'
        $awb.Texts[0] | Should -Match 'auf die Variante beschränken, die nur beim Sperren und Trennen der Sitzung zurückschreibt statt alle fünf Minuten'; $awb.Texts[0] | Should -Match '; Citrix empfiehlt diese Variante als bewährtes Vorgehen;'
        $awb.Texts[1] | Should -Match 'ohne die Richtlinie „Active write back on session lock and disconnection“'
        $awb.Texts[0] | Should -Match 'ist nichts eingestellt, legt die Profilverwaltung die Einstellung laut Citrix selbst fest'; $awb.Texts[0] | Should -Match 'Carl Stalhood rät, sie ganz abzuschalten'
        ($Elements | ForEach-Object { $_.Texts -join ' ' }) -join ' ' | Should -Not -MatchExactly 'Active Write Back|standardmäßig eingeschaltet'
        # item 6: every remedy that changes what the protection software or AppLocker lets through asks the security team
        # (the remedy that settles an exception with the team of the protection software itself is that agreement)
        $security = @($Elements | Where-Object { $_.List -eq 'remedies' -and $_.Texts[0] -match 'Rule Enforcement Mode|Ausschl|ausnehmen|Ausnahme' -and $_.Texts[0] -match 'Schutzsoftware|Scan|WEM Application Security|I/O-Erzeuger' -and $_.Texts[0] -notmatch 'mit deren Betreuung klären' })
        $security.Count | Should -BeGreaterThan 10
        foreach ($e in $security) { $e.Texts[1] | Should -Match 'die Verantwortlichen für die Sicherheit zustimmen' -Because $e.Position }
        # items 8 and 15: Stalhood's number as he writes it, one statement per sentence
        $cpu = (& $byStart 'cpu' 'remedies' 'Sitzungen gleichmäßiger auf die Server verteilen').Texts[0]
        $cpu | Should -Match '; Carl Stalhood gibt der virtuellen Maschine 8 vCPU;'; $cpu | Should -Not -Match 'mindestens 8'
        # item 9: the conditions of the test name Azure
        (& $byStart 'chronic.network' 'checks' 'Den Benutzer fragen, wie die Störung aussah').Texts[2] | Should -Match 'in einem Test der Praxisquelle von 2025 auf Azure \(VDA 2507 LTSR, Windows 11, Netzsimulator\)'
        # item 10: under Outlook the size of the mailbox data is one remedy, not two; the OST check says what to do above 10 GB
        @($Elements | Where-Object { $_.Situation -eq 'profile' -and $_.List -eq 'remedies' -and $_.When -contains 'app.outlook' }) | Should -Be @()
        (& $byStart 'profile' 'checks' 'Größe der OST-Datei von Outlook').Texts[0] | Should -Match '; ist die Datei größer als 10 GB, die lokalen Postfachdaten verkleinern \(archivieren'
        # item 11: the contact names the endpoint as such
        foreach ($s in 'delay.many', 'delay.single') { (& $byStart $s 'contacts' 'Betreuung der Gegenstelle {endpoint}').When | Should -Be @('endpoint.slow') }
        @($Elements | Where-Object { $_.Texts[0] -match 'Betreuung von \{endpoint\}' }) | Should -Be @()
        # item 12: a comparison with a recommendation from practice names the source and its year
        @($Elements | Where-Object { ($_.Texts -join ' ') -match 'mit der Empfehlung aus der Praxis' }) | Should -Be @()
        @($Elements | Where-Object { $_.Texts[0] -match 'mit der Empfehlung der Praxisquelle Carl Stalhood \(20\d\d\) vergleichen' }).Count | Should -Be 5
        # item 14: "Wo" names the place only
        (& $byStart 'memory' 'checks' 'Kein einzelner Verursacher: Arbeitsspeicher je Sitzung').Texts[1] | Should -Not -Match 'Kötzing|MB je Benutzer'
        (& $byStart 'chronic.network' 'checks' 'Den Benutzer fragen, wie die Störung aussah').Texts[1] | Should -BeExactly 'Rückfrage beim Benutzer'
        $print = & $byStart 'print' 'checks' 'Kein Muster erkannt: feststellen, welcher Treiber'
        $print.Texts[1] | Should -Not -Match 'Speicherabbild|Kötzing'
        # item 16: the dump of the spooler goes to the team of this server; the sleeping tabs with Microsoft's condition
        $print.Texts[0] | Should -Match 'das Speicherabbild sichert und wertet die Betreuung dieses Servers aus, bei Bedarf mit dem Hersteller des Treibers$'
        ($print.Texts -join ' ') | Should -Not -Match 'Betreuung der Druckserver'
        $tabs = (& $byStart 'memory' 'remedies' 'Automatisches Verwerfen schlafender Tabs').Texts[0]
        foreach ($w in 'drei Browsersitzungen in Folge im Hintergrund', 'mehr als 12 Stunden', 'mehr als 18 Stunden auf Geräten mit 16 GB Arbeitsspeicher oder mehr') { $tabs | Should -Match $w }
        # parked: the MCS I/O step of the memory only without a single cause
        @((& $byStart 'memory' 'checks' 'Wenn der Maschinenkatalog MCS I/O nutzt').When) | Should -Be @('cause.none')
        @((Get-Guide (New-Engpass 'memory')).checks | Where-Object { $_.text -match 'MCS I/O' }) | Should -Be @()
        @((Get-Guide (New-Engpass 'memory' @{ cause = @{ kind = 'none' }; main = $null })).checks | Where-Object { $_.text -match 'MCS I/O' }).Count | Should -Be 1
    }
    It 'fuehrt unter einer Verzoegerung laufender Sitzungen keinen Schritt zur Dauer der Anmeldung' {      # round 5, fix round 1, item 5 (ruling P3-R76)
        $delay = @($Elements | Where-Object { $_.Situation -in 'delay.many', 'delay.single' })
        @($delay | Where-Object { ($_.Texts -join ' ') -match 'Gruppenrichtlinien die Dauer|Betreuung der Gruppenrichtlinien|GroupPolicy|Domänencontroller|5324' }) | Should -Be @()
        @($delay | Where-Object { $_.Texts[0] -match '^Wenn [^:]*bei der Anmeldung' }) | Should -Be @()
        @($delay | Where-Object { $_.Texts[0] -match '^Wenn (die|der) Benutzer im Explorer oder in einem Dateidialog wartete' }).Count | Should -Be 2
        @($delay | Where-Object { $_.Texts[0] -match '^Wenn [^:]* im Explorer' }).Count | Should -Be 2
        @($Real.situations.'delay.many'.contacts).Count | Should -Be 3
    }
    It 'sagt in einem Erkennungszeichen, was zu sehen ist, nie, was zu tun ist' {      # round 5, fix round 1, item 8
        # the words by which a sign told the reader to do something (pinned): an infinitive of an action, "lassen" in any
        # compound, an instruction after "; dann". What to do stands in the text of the step or in a remedy
        # final fix wave, parked item: "lassen" as the instruction, not as a substring of a participle ("zugelassen")
        $instruction = '; dann |\(weiter prüfen\)|(?<!ge)lassen\b|\b(entfernen|abschalten|erhöhen|ansprechen|abstellen|umleiten|melden|abmelden|gegenlesen)\b'
        $signs = @(foreach ($s in $WorkerPerfSituations) { $list = @($Real.situations.$s.checks); for ($k = 0; $k -lt $list.Count; $k++) { [pscustomobject]@{ Position = "$s.checks[$k]"; Sign = [string]$list[$k].sign } } })
        $signs.Count | Should -BeGreaterThan 250
        foreach ($x in $signs) { $x.Sign | Should -Not -MatchExactly $instruction -Because $x.Position }
        # the pattern finds the instructions the signs held before this round
        foreach ($was in 'Sitzung im Status „Getrennt“ mit hohem Anteil am Prozessor; dann den Benutzer fragen und die Sitzung abmelden lassen',
            'Programme, die die Benutzer nicht brauchen; sie aus den Run-Schlüsseln entfernen', 'reicht für die Sitzungen nicht; dann mit der Citrix-Betreuung den Arbeitsspeicher im Maschinenkatalog erhöhen',
            'keine Antwort auf die automatische Erkennung; dann die Einstellung zentral abschalten', 'Modul eines anderen Produkts, dann dessen Betreuung und den Hersteller der Anwendung ansprechen',
            'in derselben Sitzung aktiv: dann deren Betreuung ansprechen', 'zu der keine Sitzung mehr besteht; das Produkt seiner Betreuung melden', 'den Schreiber im Master-Image abstellen oder umleiten',
            'blockiert; Microsoft rät, beide zuzulassen', 'Verzögerung über Minuten und wiederholt (weiter prüfen)') { $was | Should -MatchExactly $instruction }
        foreach ($fine in 'Programm in AppLocker zugelassen', 'Funktion eingeschaltet gelassen') { $fine | Should -Not -MatchExactly $instruction }
        # where the instruction went: into the text of the step, after the check
        foreach ($e in @($Elements | Where-Object { $_.Texts[0] -match '^Wenn Anwendungen beim Start der Sitzung' })) {
            $e.Texts[0] | Should -Match '; trifft es zu, die Einstellung für die Benutzer der Server zentral abschalten \(Workspace Environment Management oder Gruppenrichtlinie; eine Richtlinie wirkt auch auf nicht persistente Server\)' -Because $e.Position
        }
        @($Elements | Where-Object { $_.Texts[0] -match '; trifft es zu, |; finden sich |; gehören die Threads |; reicht der Rest |; ist es eine solche Anwendung, |; meldet der Benutzer ' }).Count | Should -BeGreaterThan 9
    }
    It 'schreibt die Schritte der Korrekturrunde so, wie die Pruefung sie vorschlug' {      # round 5, fix round 1, item 12
        $all = @($Elements | ForEach-Object { $_.Texts -join ' | ' }) -join "`n"
        $all | Should -Not -Match 'Schnellstart'; $all | Should -Match 'Startup-Boost von Microsoft Edge'
        $all | Should -Not -Match 'Lesart des Katalogs|größte Größe|Prüfprodukt|ohne Abstand|DNS: der eigene Name|EDT über UDP oder TCP|das ist ihre Meinung|Ereignisse 4016 bis 5016'
        $all | Should -Match 'das folgert diese Anleitung, nicht die Praxisquelle'; $all | Should -Match 'auf dem Server: nslookup mit dem eigenen vollständigen Namen \(FQDN\)'; $all | Should -Match '\(EDT, also UDP, oder TCP\)'
        # the Edge check says what follows from the finding
        @($Elements | Where-Object { $_.Texts[0] -match 'Startup-Boost' -and $_.Texts[0] -match 'entscheidet der Betreiber \(StartupBoostEnabled = 0 schaltet ab; eine Richtlinie wirkt auch auf nicht persistente Server\)$' }).Count | Should -Be 1
        # the step of the catalogue for an application installed in the profile is a remedy of its own, shown after the others
        $own = @($Elements | Where-Object { $_.Situation -eq 'profile' -and $_.List -eq 'remedies' -and $_.Texts[0] -match '^\{app\} für alle Benutzer installieren statt im Benutzerprofil' })
        $own.Count | Should -Be 1; $own[0].Texts[1] | Should -Be '{app} unter AppData installiert ist'; $own[0].Texts[0] | Should -Match ([regex]::Escape($InImage))
        $own[0].Texts[0] | Should -Match 'folgert diese Anleitung daraus, nicht die Praxisquelle$'
        $g = Get-Guide (New-Engpass 'profile'); $g.remedies[0].text | Should -Be 'Datenmenge von EXCEL.EXE im Profil verkleinern, zum Beispiel den Zwischenspeicher begrenzen oder ältere Daten auslagern'
        $g.remedies[-1].text | Should -Match '^EXCEL\.EXE für alle Benutzer installieren statt im Benutzerprofil'
        # where a source wrote for FSLogix, the element says so
        foreach ($e in @($Elements | Where-Object { $_.Source -like 'Aaron Parker (*' -and $_.Situation -in 'disk', 'profile', 'profileerror' })) { ($e.Texts -join ' ') | Should -Match 'FSLogix' -Because $e.Position }
        # a slow endpoint need not be a file server
        @($Elements | Where-Object { $_.Texts[0] -match '^Wenn die Gegenstelle ein Dateiserver ist: prüfen, ob \{endpoint\} das Basisverzeichnis' }).Count | Should -Be 1
    }
    It 'zeigt die Schritte zu Outlook nur bei Outlook und dort vor den allgemeinen, bei <App> (<S>) keinen' -ForEach @(      # fix round 3, B1 (ruling P3-R57)
        @(foreach ($a in 'WINWORD.EXE', 'EXCEL.EXE', 'POWERPNT.EXE', 'ONENOTE.EXE', 'MSACCESS.EXE') { foreach ($s in 'hang', 'crash', 'cpu', 'memory', 'disk', 'share', 'profile') { @{ App = $a; S = $s } } })
    ) {
        if ($S -in 'hang', 'crash') { $inc = New-Inc @{ type = 'ereignis'; start = [long]1e12; end = [long]1e12; event = @{ kind = $S; app = $App; users = @('user003'); sessions = @(3) } } }
        else { $inc = New-Engpass $S @{ main = @{ app = $App; a = 9; user = 'user003'; sharePct = 62; baselinePct = 4 } } }
        $g = Get-Guide $inc
        @($g.conditions | Where-Object { $_ -like 'app.*' }) | Should -Be @('app.office')
        @(Get-GuideTexts $g | Where-Object { $_ -match 'Outlook|OST-|PST-|Cache-Modus' }) | Should -Be @()
    }
    It 'haengt die Schritte, die nur fuer Outlook gelten, an die Anwendung Outlook und zeigt ihr auch die Schritte fuer jedes Office-Programm' {      # fix round 3, B1 (ruling P3-R57)
        # the application list: Outlook last, its process in no other application; the order of the five before it unchanged
        @($AppList.apps | ForEach-Object { $_.key }) | Should -Be @('edge', 'webview2', 'office', 'teams', 'printaurus', 'outlook')
        $outlook = @($AppList.apps | Where-Object { $_.key -eq 'outlook' })[0]
        $outlook.label | Should -BeExactly 'Microsoft Outlook'; @($outlook.processes) | Should -Be @('OUTLOOK.EXE')
        @(($AppList.apps | Where-Object { $_.key -eq 'office' }).processes) | Should -Be @('WINWORD.EXE', 'EXCEL.EXE', 'POWERPNT.EXE', 'ONENOTE.EXE', 'MSACCESS.EXE')
        @(Get-WorkerPerfGuidanceAppMatches $AppList 'outlook.exe') | Should -Be @('outlook'); @(Get-WorkerPerfGuidanceAppMatches $AppList 'C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE') | Should -Be @('office')
        $office = @($Elements | Where-Object { $_.When -contains 'app.office' }); $own = @($Elements | Where-Object { $_.When -contains 'app.outlook' })
        # no element starts with the prefix any more; none for every Office program names Outlook or its files
        @($Elements | Where-Object { $_.Texts[0] -match '^Bei Outlook' }) | Should -Be @()
        foreach ($e in $office) { ($e.Texts -join ' ') | Should -Not -Match 'Outlook|OST|PST|Postfach' -Because $e.Position }
        # the steps for Outlook alone: each names Outlook or its data file, none stands under another application
        $only = @($own | Where-Object { $t = $_.Texts[0]; @($office | Where-Object { $_.Texts[0] -ceq $t }).Count -eq 0 })
        # (round 5: the exclusion of Outlook's data files from scanning, in hang and crash; final fix wave, items 4 and 10: with
        # Microsoft's page as the source, and the remedy on the mailbox data taken into the check on the OST file)
        @($only | ForEach-Object { $_.Situation + '.' + $_.List } | Sort-Object) | Should -Be @('crash.checks', 'disk.checks', 'hang.checks', 'hang.checks', 'hang.checks', 'hang.checks', 'profile.checks', 'share.checks')
        foreach ($e in $only) { ($e.Texts -join ' ') | Should -Match 'Outlook' -Because $e.Position; $e.Source | Should -Match '^Microsoft: ' -Because $e.Position }
        # Outlook is an Office program: every step for every Office program stands a second time, word for word and with
        # its source, under Outlook, in the same list after the Office steps, and after the steps for Outlook alone
        $office.Count | Should -Be 6
        foreach ($e in $office) {
            $twin = @($own | Where-Object { $_.Situation -eq $e.Situation -and $_.List -eq $e.List -and ($_.Texts -join '|') -ceq ($e.Texts -join '|') })
            $twin.Count | Should -Be 1 -Because $e.Position
            $twin[0].Source | Should -BeExactly $e.Source -Because $e.Position
            (@($twin[0].When) -join ',') | Should -Be ((@($e.When) -join ',').Replace('app.office', 'app.outlook')) -Because $e.Position
            $index = { param($x) [int]($x.Position -replace '^.*\[(\d+)\]$', '$1') }
            (& $index $twin[0]) | Should -BeGreaterThan (& $index $e) -Because $e.Position
            foreach ($o in @($only | Where-Object { $_.Situation -eq $e.Situation -and $_.List -eq $e.List })) { (& $index $o) | Should -BeLessThan (& $index $twin[0]) -Because $o.Position }
        }
        ($own.Count - $only.Count) | Should -Be $office.Count
        # a hang of Outlook: its three steps, before every general step of the situation
        $g = Get-Guide (New-Inc @{ type = 'ereignis'; start = [long]1e12; end = [long]1e12; event = @{ kind = 'hang'; app = 'OUTLOOK.EXE'; users = @('user003'); sessions = @(3) } })
        @($g.conditions | Where-Object { $_ -like 'app.*' }) | Should -Be @('app.outlook')
        $shown = @($g.checks | ForEach-Object { $_.text })
        $general = @($Real.situations.hang.checks | Where-Object { -not $_.PSObject.Properties['when'] -or @($_.when).Count -eq 0 } | ForEach-Object { [string]$_.text })
        $firstGeneral = @($shown | ForEach-Object { [array]::IndexOf($general, $_) -ge 0 }).IndexOf($true); $firstGeneral | Should -BeGreaterThan 2
        # (round 5: the step that also needs a module of the protection software is not among them)
        $steps = @($only | Where-Object { $_.Situation -eq 'hang' -and @($_.When).Count -eq 1 }); $steps.Count | Should -Be 3
        @($g.checks | Where-Object { $_.text -match '\.ost und \.pst' }) | Should -Be @()
        foreach ($e in $steps) { $at = [array]::IndexOf($shown, $e.Texts[0]); $at | Should -BeGreaterThan -1 -Because $e.Position; $at | Should -BeLessThan $firstGeneral -Because $e.Position }
        @($g.checks | Where-Object { $_.text -match 'Add-in von Outlook wegen langsamer Ausführung' }).Count | Should -Be 1
        @($g.checks | Where-Object { $_.text -match '^Größe der OST-Datei von Outlook' }).Count | Should -Be 1
        @($g.checks | Where-Object { $_.text -match '^Prüfen, ob der Ordner AppData auf eine Freigabe umgeleitet ist' }).Count | Should -Be 1
        # a crash and a processor bottleneck of Outlook show what Word shows
        foreach ($kind in 'crash', 'cpu', 'memory') {
            $make = { param($app) if ($kind -eq 'crash') { New-Inc @{ type = 'ereignis'; start = [long]1e12; end = [long]1e12; event = @{ kind = 'crash'; app = $app; users = @('user003'); sessions = @(3) } } }
                else { New-Engpass $kind @{ main = @{ app = $app; a = 9; user = 'user003'; sharePct = 62; baselinePct = 4 } } } }
            $word = Get-Guide (& $make 'WINWORD.EXE'); $mail = Get-Guide (& $make 'OUTLOOK.EXE')
            foreach ($list in 'checks', 'remedies') {
                @($mail.$list | ForEach-Object { $_.text }) | Should -Be @($word.$list | ForEach-Object { $_.text.Replace('WINWORD.EXE', 'OUTLOOK.EXE') }) -Because "$kind $list"
            }
            @($mail.checks | Where-Object { $_.text -match 'Add-ins von OUTLOOK\.EXE' }).Count | Should -Be 1 -Because $kind
        }
    }
    It 'sagt im Glossar zum Zuordnungswerkzeug der Drucker nur, was belegt ist' {                                   # fix round 3, B2
        $term = [string]$Real.terms.PrinTaurus
        $term | Should -BeExactly 'Drucklösung der AKI GmbH, mit der in dieser Umgebung die Drucker zugeordnet werden; ihr SmartSpread Client ist auf dem Server installiert.'
        # nothing on rules of the mapping, nothing on how often or where the client runs
        $term | Should -Not -Match 'Regel|Sitzung|läuft|je Benutzer|Anmeldung'
        # the record of sources names the statement as the customer's, in the target environment and in the vendor's section
        $doc = [IO.File]::ReadAllText($SourcesFile, [Text.Encoding]::UTF8)
        foreach ($h in 'Zielumgebung', 'AKI') {
            $at = $doc.IndexOf("`n## $h`n"); $next = $doc.IndexOf("`n## ", $at + 4)
            $section = $doc.Substring($at, $next - $at)
            $section | Should -Match 'Angabe des Auftraggebers vom 13\.11\.2026' -Because $h
            $section | Should -Match 'Drucklösung' -Because $h
            $section | Should -Not -Match 'läuft dafür|nach Regeln zu' -Because $h
        }
    }
    It 'stellt kein Bezeichnungswort direkt vor seinen Platzhalter' {                                             # ruling P3-R45
        # the replacement name of a masked report starts with the word: "Server Server 01"
        $all = New-Object System.Collections.Generic.List[string]
        foreach ($e in $Elements) { foreach ($t in $e.Texts) { $all.Add($t) } }
        foreach ($s in $WorkerPerfSituations) { foreach ($f in 'title', 'meaning', 'impact') { $all.Add([string]$Real.situations.$s.$f) } }
        foreach ($s in $WorkerPerfSituations) { if ($Real.situations.$s.PSObject.Properties['impactVariants']) { foreach ($v in @($Real.situations.$s.impactVariants)) { $all.Add([string]$v.text) } } }
        foreach ($part in 'copy', 'userView', 'lagebild', 'hints') { foreach ($p in $Real.$part.PSObject.Properties) { $all.Add([string]$p.Value) } }
        $all.Add([string]$Real.fallbackNote); foreach ($p in $Real.terms.PSObject.Properties) { $all.Add([string]$p.Value) }
        $all.Count | Should -BeGreaterThan 1000
        $pattern = '(?<![\p{L}\p{N}-])(Benutzer|Server|Client|Freigabe|Drucker|Domäne)\s+[„"(]*\{(user|server|resource|endpoint|driver|app|security|module|share)\}'
        @($all | Where-Object { $_ -cmatch $pattern }) | Should -Be @()
        $Real.copy.head | Should -Be 'WorkerPerf: {server}, {date}'; $Real.copy.summaryHead | Should -Match 'Messung auf \{server\} am \{date\}'
        # the pattern finds what it is meant to find
        'Messung auf Server {server} am' | Should -MatchExactly $pattern; 'Nur Benutzer „{user}“ ist betroffen' | Should -MatchExactly $pattern
        'in der Sitzung von {user}' | Should -Not -MatchExactly $pattern; 'eines Benutzers {duration} lang' | Should -Not -MatchExactly $pattern
    }
    It 'nennt die gemessene Maschine in jedem Text des Katalogs Server, nie Worker' {                              # fix round 4, A3 (ruling P3-R66)
        $strings = @(Get-CatalogueStrings (Get-Content -LiteralPath $CatalogueFile -Raw -Encoding UTF8 | ConvertFrom-Json) '')
        $strings.Count | Should -BeGreaterThan 1200
        # every text the loader knows is among them: an element's texts, a situation's, the parts outside the situations
        $places = @($strings | ForEach-Object { $_.Place })
        foreach ($p in 'terms.Master-Image', 'terms.Master-Image (Begriff)', 'copy.head', 'userView.many', 'lagebild.red', 'hints.skipped', 'fallbackNote',
            'situations.cpu.title', 'situations.cpu.short', 'situations.cpu.meaning', 'situations.cpu.impact', 'situations.cpu.checks[0].text', 'situations.cpu.checks[0].where',
            'situations.cpu.checks[0].sign', 'situations.cpu.remedies[0].text', 'situations.cpu.remedies[0].precondition', 'situations.print.contacts[0].text',
            'situations.cpu.impactVariants[0].text') { $places | Should -Contain $p }
        @($places | Where-Object { $_ -match '\.(when|source)(\[|$)|^(version|vendors)' }) | Should -Be @()
        @($strings | Where-Object { $_.Text -cmatch $WorkerWord } | ForEach-Object { $_.Place }) | Should -Be @()
        # the fixed phrases of spec 5.8 say Server
        $InImage | Should -BeExactly 'bei nicht persistenten Servern im Master-Image, danach die Server neu bereitstellen'
        $ByPolicy | Should -BeExactly 'eine Richtlinie wirkt auch auf nicht persistente Server'
        @($strings | Where-Object { $_.Text.Contains($InImage) }).Count | Should -BeGreaterThan 40; @($strings | Where-Object { $_.Text.Contains($ByPolicy) }).Count | Should -BeGreaterThan 10
        # the pattern finds the word of its own and the first part of a compound, and leaves the tool's name
        foreach ($t in 'auf dem Worker', 'außerhalb des Workers', 'bei nicht persistenten Workern im Master-Image', 'in den gemessenen Worker-Ressourcen', '(Worker)', 'Citrix-Worker') { $t | Should -MatchExactly $WorkerWord }
        foreach ($t in 'WorkerPerf: Hinweis zur Auswertung', 'Start-WorkerPerfCapture.ps1', 'auf dem Server', 'worker') { $t | Should -Not -MatchExactly $WorkerWord }
    }
    It 'nennt die gemessene Maschine in jedem Satz der Auswertung Server, nie Worker' {                           # fix round 4, A3 (ruling P3-R66)
        $Texts.Count | Should -BeGreaterThan 190
        @($Texts.Keys | Where-Object { $Texts[$_] -cmatch $WorkerWord } | Sort-Object) | Should -Be @()
        $Texts['ohne'] | Should -Match 'ohne Engpass auf dem Server \('; $Texts['ohne.skipped'] | Should -Match 'ohne erkannten Engpass auf dem Server \('
        $Texts['umfeld.network'] | Should -Match 'Betrifft die Sitzung, nicht den Server\.$'; $Texts['ohne.cause'] | Should -Match 'außerhalb des Servers oder in der Anwendung selbst'
        # the cause of a delay without bottleneck is a likelihood, as the meaning of the incident says (fix round 4, B1; ruling P3-R63)
        $Texts['ohne.cause'] | Should -BeExactly ' Die Ursache liegt vermutlich außerhalb des Servers oder in der Anwendung selbst (Datenbank, Proxy, Netz).'
        foreach ($k in @($Texts.Keys | Where-Object { $_ -like 'ohne*' })) { if ($Texts[$k] -match 'Ursache') { $Texts[$k] | Should -Match 'vermutlich|nicht ausgeschlossen' -Because $k } }
        foreach ($s in 'delay.many', 'delay.single') { $Real.situations.$s.meaning | Should -Match 'vermutlich' -Because $s }
        $Texts['ohne.unmeasured'] | Should -Match '^ Kein Engpass in den gemessenen Ressourcen des Servers\. Nicht gemessen: '
    }
}

Describe 'Katalog an der simulierten Stunde: Reihenfolge vor den Quellen aus der Praxis' {      # round 5 (ruling P3-R69)
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        $script:Real = Read-WorkerPerfGuidance $script:CatalogueFile -Apps $script:AppList
        # the simulated hour with every category and its report data as the report script builds them (dot-sourced in a
        # child scope, which keeps $data); the names below are not used by the report script
        $pinSimRun = Invoke-SimCapture (Join-Path $TestDrive 'sim')
        $pinSimRoles = New-SimRoleFile (Join-Path $TestDrive 'roles.sim.json')
        $pinSimReport = Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1'
        $script:PinData = & { $null = . $pinSimReport -Path $pinSimRun -OutFile (Join-Path $TestDrive 'report.html') -RoleFile $pinSimRoles 6>$null; $data }
        # per incident the first words of the first five checks and the first three remedies as the catalogue gave them
        # before round 5 (commit 75c7f41), cut before a time of day: what the incident view shows unfolded and the copy
        # text carries. An element from practice may follow them; it may not take the place of one of them
        $script:Pinned = @(
            @{ Id = 1; S = 'chronic.network'; Checks = @('Feststellen, welcher Benutzer betroffen ist und von', 'Prüfen, ob andere Benutzer vom selben Standort oder', 'Netzstrecke des Benutzers über mehrere Tage ansehen'); Remedies = @('Endgerät per Kabel anschließen oder näher an den WLA', 'Netzstrecke des Standorts oder den VPN-Zugang durch') }
            @{ Id = 2; S = 'cpu'; Checks = @('Prüfen, ob EXCEL.EXE in der Sitzung von user003 noch', 'Klären, was EXCEL.EXE', 'Einordnen, ob EXCEL.EXE ein Ausreißer oder ein gewoh', 'Add-ins von EXCEL.EXE prüfen', 'Im Ereignisprotokoll des WEM-Agenten nachsehen, ob d'); Remedies = @('EXCEL.EXE vom Benutzer schließen lassen; reagiert di', 'Arbeiten mit EXCEL.EXE, die viel Rechenzeit brauchen', 'CPU-Spitzenschutz von Citrix Workspace Environment M') }
            @{ Id = 3; S = 'memory'; Checks = @('Prüfen, wie viel Arbeitsspeicher ms-teams.exe in der', 'Verlauf des Arbeitsspeichers von ms-teams.exe über d', 'Einordnen, ob ms-teams.exe ein Ausreißer oder ein ge', 'Prüfen, ob Teams in der Sitzung von user007 mit Medi', 'Klären, ob der Benutzer an einer Großveranstaltung'); Remedies = @('ms-teams.exe schließen und neu starten lassen', 'Hersteller oder Betreuung von ms-teams.exe auf den S', 'Rückfall von Teams in die nicht optimierte Verarbeit') }
            @{ Id = 4; S = 'disk'; Checks = @('Prüfen, ob robocopy.exe in der Sitzung von user011 n', 'Klären, was robocopy.exe', 'Einordnen, ob robocopy.exe ein Ausreißer oder ein ge', 'Im Zeitraum lief ein Virenscan', 'Microsoft Defender lief als Begleiter mit'); Remedies = @('Vorgänge mit robocopy.exe, die große Datenmengen bew', 'Zeitplan der Scans in eine Zeit ohne angemeldete Ben', 'Ausschlüsse für den größten I/O-Erzeuger so einricht') }
            @{ Id = 5; S = 'share'; Checks = @('Klären, welche Dateien WINWORD.EXE in der Sitzung vo', 'Einordnen, ob WINWORD.EXE ein Ausreißer oder ein gew', 'Prüfen, ob andere Server dieselbe Freigabe zur gleic', 'Auslastung des Dateiservers zur Zeit des Vorfalls pr', 'Meldungen zur Verbindung mit dem Dateiserver ansehen'); Remedies = @('Dateivorgänge von WINWORD.EXE mit großen Datenmengen') }
            @{ Id = 6; S = 'profile'; Checks = @('Klären, was OUTLOOK.EXE in der Sitzung von user009 a', 'Größe der Daten von OUTLOOK.EXE im betroffenen Profi', 'Einordnen, ob OUTLOOK.EXE ein Ausreißer oder ein gew', 'Größe der OST-Datei von Outlook und Zahl der Element', 'Prüfen, ob zur gleichen Zeit auch andere Profilconta'); Remedies = @('Datenmenge von OUTLOOK.EXE im Profil verkleinern, zu', 'Einstellungen der Citrix Profilverwaltung für schnel') }
            @{ Id = 7; S = 'delay.many'; Checks = @('Die Gegenstelle Oracle-Listener antwortete im Zeitra', 'Feststellen, in welcher Anwendung die Benutzer warte', 'Bei der Betreuung dieser Anwendung und ihrer Datenba', 'Prüfen, ob Benutzer auf anderen Servern zur gleichen', 'Netzstrecke und Proxy prüfen lassen, wenn die Anwend'); Remedies = @('Energiesparplan „Höchstleistung“ einstellen') }
            @{ Id = 8; S = 'delay.single'; Checks = @('Feststellen, in welcher Anwendung der Benutzer warte', 'Dauer und Höhe der Verzögerung einordnen', 'Prüfen, ob dieselbe Anwendung bei diesem Benutzer öf', 'Energiesparplan des Servers feststellen'); Remedies = @('Anwendung, Erweiterungen und Daten des Benutzers prü', 'Energiesparplan „Höchstleistung“ einstellen') }
            @{ Id = 9; S = 'profileerror'; Checks = @('Meldungstext des Profilfehlers lesen', 'Prüfen, ob der Benutzer mit einem temporären Profil', 'Erreichbarkeit und freien Platz des Profilspeichers', 'Prüfen, ob der Benutzer zur selben Zeit noch auf ein', 'Protokoll der Citrix Profilverwaltung zur Anmeldung'); Remedies = @('Sitzung, die das Profil noch geöffnet hält, nach Rüc') }
            @{ Id = 10; S = 'crash'; Checks = @('Speichermangel als Ursache prüfen', 'Version der Anwendung und des fehlerhaften Moduls fe', 'Betroffene Benutzer fragen, was sie unmittelbar vor', 'Prüfen, ob derselbe Absturz an weiteren Tagen auftra', 'Der Absturz fiel in den Zeitraum eines Leistungsvorf'); Remedies = @('Speichermangel beheben') }
            @{ Id = 11; S = 'crash'; Checks = @('Mehrere Benutzer sind betroffen', 'Add-ins von OUTLOOK.EXE als Ursache prüfen', 'Feststellen, ob Office als 32-Bit- oder 64-Bit-Versi', 'Version der Anwendung und des fehlerhaften Moduls fe', 'Betroffene Benutzer fragen, was sie unmittelbar vor'); Remedies = @('Änderung zurücknehmen oder die korrigierte Version v', 'Office auf den aktuellen Stand bringen') }
            @{ Id = 12; S = 'print'; Checks = @('Prüfen, ob der Dienst „Druckwarteschlange“ wieder lä', 'Ein fehlerhaftes Modul gehört zu einem installierten', 'Treiberisolierung von HP Universal Printing PCL 6', 'Gruppenrichtlinie zur Treiberisolierung prüfen', 'Stand der Druckertreiber und Druckkomponenten mit de'); Remedies = @('Treiber HP Universal Printing PCL 6', 'Treiber HP Universal Printing PCL 6', 'Richtlinie „Override print driver execution compatib') }
            @{ Id = 13; S = 'crash'; Checks = @('Dasselbe Modul war bei mehreren Anwendungen die Abst', 'Prüfen, ob der Absturz seit Beginn der Messung wiede', 'Einordnen, wie weit der Rückblick reicht', 'Add-ins von EXCEL.EXE als Ursache prüfen', 'Feststellen, ob Office als 32-Bit- oder 64-Bit-Versi'); Remedies = @('Produkt, zu dem das gemeinsame Modul gehört, aktuali', 'Office auf den aktuellen Stand bringen') }
            @{ Id = 14; S = 'crash'; Checks = @('Dasselbe Modul war bei mehreren Anwendungen die Abst', 'Prüfen, ob der Absturz seit Beginn der Messung wiede', 'Einordnen, wie weit der Rückblick reicht', 'Add-ins von WINWORD.EXE als Ursache prüfen', 'Feststellen, ob Office als 32-Bit- oder 64-Bit-Versi'); Remedies = @('Produkt, zu dem das gemeinsame Modul gehört, aktuali', 'Office auf den aktuellen Stand bringen') }
            @{ Id = 15; S = 'crash'; Checks = @('Nur user004 ist betroffen, und das wiederholt', 'Prüfen, ob der Absturz seit Beginn der Messung wiede', 'Einordnen, wie weit der Rückblick reicht', 'Version der Anwendung und des fehlerhaften Moduls fe', 'Betroffene Benutzer fragen, was sie unmittelbar vor'); Remedies = @('Einstellungen von nexus.exe für user004 zurücksetzen') }
            @{ Id = 16; S = 'crash'; Checks = @('Kein Muster erkannt', 'Prüfen, ob der Absturz seit Beginn der Messung wiede', 'Einordnen, wie weit der Rückblick reicht', 'Version der Anwendung und des fehlerhaften Moduls fe', 'Betroffene Benutzer fragen, was sie unmittelbar vor'); Remedies = @() }
        )
    }
    It 'zeigt bei jedem Vorfall der simulierten Stunde die ersten fuenf Pruefschritte und drei Vorschlaege wie vor Runde 5' {
        $all = @(@($PinData.incidents) + @($PinData.before.incidents))
        $all.Count | Should -Be $Pinned.Count
        foreach ($pin in $Pinned) {
            $inc = @($all | Where-Object { [int]$_.id -eq $pin.Id }); $inc.Count | Should -Be 1 -Because "Vorfall $($pin.Id)"
            $g = $inc[0].guide
            $g.situation | Should -Be $pin.S -Because "Vorfall $($pin.Id)"
            foreach ($list in 'Checks', 'Remedies') {
                $shown = @($g.($list.ToLowerInvariant())); $want = @($pin.$list)
                $shown.Count | Should -Not -BeLessThan $want.Count -Because "Vorfall $($pin.Id): $list"
                for ($k = 0; $k -lt $want.Count; $k++) { ([string]$shown[$k].text).StartsWith($want[$k], [StringComparison]::Ordinal) | Should -BeTrue -Because ('Vorfall {0}: {1}[{2}] ist <{3}>, erwartet wird der Anfang <{4}>' -f $pin.Id, $list, $k, $shown[$k].text, $want[$k]) }
            }
        }
    }
    It 'laesst kein Element der zehn neuen Quellen einen Schritt eines Herstellers aus den ersten fuenf und drei verdraengen' {
        # said directly: where a list was full before (five checks, three remedies), none of its places holds an element of
        # a source of round 5; where it was shorter, such an element stands only after the elements that were there
        $new = '^(' + ((@($PracticeNames | Where-Object { $_ -notin 'Carl Stalhood', 'BIS-F' }) | ForEach-Object { [regex]::Escape($_) }) -join '|') + ') \('
        $all = @(@($PinData.incidents) + @($PinData.before.incidents)); $seen = 0
        foreach ($pin in $Pinned) {
            $g = @($all | Where-Object { [int]$_.id -eq $pin.Id })[0].guide
            foreach ($list in 'Checks', 'Remedies') {
                $shown = @($g.($list.ToLowerInvariant())); $kept = @($pin.$list).Count
                for ($k = 0; $k -lt [Math]::Min($kept, $shown.Count); $k++) { [string]$shown[$k].source | Should -Not -Match $new -Because "Vorfall $($pin.Id): $list[$k]" }
                $seen += @($shown | Where-Object { [string]$_.source -match $new }).Count
            }
        }
        # the simulated hour does show elements of the new sources, after the pinned ones
        $seen | Should -BeGreaterThan 10
    }
}
Describe 'Katalog an allen Testberichten: was ein Vorfall vor den zehn weiteren Quellen zeigte, bleibt in Sicht' {      # round 5, fix round 1 (ruling P3-R75)
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        # every report the test reports hold (tests/New-TestReports.ps1): the simulated hour, the report with a reported
        # user, the cuts, the masked ones and the reports of the captures with categories left out
        $allDir = Join-Path $TestDrive 'all'
        [void](New-TestReports $allDir); [void](New-SkipReports $allDir)
        $script:AllGuides = @(foreach ($file in @(Get-ChildItem $allDir -Filter '*.html' | Sort-Object Name)) {
                $shown = Get-ReportData $file.FullName
                $list = @($shown.incidents); if ($shown.PSObject.Properties['before'] -and $shown.before.PSObject.Properties['incidents']) { $list += @($shown.before.incidents) }
                foreach ($inc in $list) { if ($inc.PSObject.Properties['guide'] -and $null -ne $inc.guide) { [pscustomobject]@{ Report = $file.Name; Id = [int]$inc.id; Guide = $inc.guide } } }
            })
    }
    It 'laesst in jedem Vorfall jedes Testberichts die ersten fuenf Pruefschritte und drei Vorschlaege ohne die zehn weiteren Quellen vorn stehen' {
        @($AllGuides | ForEach-Object { $_.Report } | Sort-Object -Unique).Count | Should -BeGreaterThan 20
        foreach ($name in 'report.html', 'report-focus.html', 'report-skip-prozesse.html', 'report-skip-laufwerke.html', 'report-skip-ereignisse.html', 'report-skip-gegenstellen.html', 'report-skip-alle.html') {
            @($AllGuides | Where-Object { $_.Report -eq $name }).Count | Should -BeGreaterThan 5 -Because $name
        }
        $AllGuides.Count | Should -BeGreaterThan 200
        $broken = @(foreach ($x in $AllGuides) { foreach ($t in @(Get-Displaced $x.Guide)) { "$($x.Report), Vorfall $($x.Id) ($($x.Guide.situation)): $t" } })
        $broken | Should -Be @()
        # the reports do show elements of the ten sources, also among the first places of a short list
        $shown = 0; $first = 0
        foreach ($x in $AllGuides) {
            $shown += @(@($x.Guide.checks) + @($x.Guide.remedies) | Where-Object { [string]$_.source -match $RoundFiveSource }).Count
            $first += @(@($x.Guide.checks | Select-Object -First 5) + @($x.Guide.remedies | Select-Object -First 3) | Where-Object { [string]$_.source -match $RoundFiveSource }).Count
        }
        $shown | Should -BeGreaterThan 300; $first | Should -BeGreaterThan 20
    }
    It 'zeigt in jedem Testbericht den Vorschlag, dessen Voraussetzung die Messung nicht sieht, als letzten' {      # item 4; final fix wave, item 7
        $seen = 0
        foreach ($x in $AllGuides) {
            $remedies = @($x.Guide.remedies)
            for ($k = 0; $k -lt $remedies.Count; $k++) {
                if ([string]$remedies[$k].text -notmatch '^Drosselung des SMB-Clients') { continue }
                # Aussage angepasst (final fix wave, item 7): no gate on a named cause; the remedy stands last and, where it is the
                # only one, carries its precondition on the path to the file server like any other
                $seen++; $k | Should -Be ($remedies.Count - 1) -Because "$($x.Report), Vorfall $($x.Id)"
            }
        }
        $seen | Should -BeGreaterThan 5
    }
}
Describe 'Katalog an der simulierten Stunde ohne Prozesse' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        $script:Real = Read-WorkerPerfGuidance $script:CatalogueFile -Apps $script:AppList
        # one hour recorded with -Skip Prozesse and its report data as the report script builds them (dot-sourced in a child
        # scope, which keeps $data); the names below are not used by the report script
        $catSimRun = Invoke-SimCapture (Join-Path $TestDrive 'sim') @{ Skip = @('Prozesse') }
        $catSimRoles = New-SimRoleFile (Join-Path $TestDrive 'roles.sim.json')
        $catSimReport = Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1'
        $script:SimData = & { $null = . $catSimReport -Path $catSimRun -OutFile (Join-Path $TestDrive 'report.html') -RoleFile $catSimRoles 6>$null; $data }
        $script:SimCtx = @{ Data = $SimData; Thresholds = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json'); OffsetMinutes = [int]$SimData.meta.offsetMin; Texts = $script:Texts; Apps = $script:AppList }
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
            @(Get-BeforePractice $g.checks)[-1].text | Should -Match 'ohne „-Skip Prozesse“ wiederholen' -Because "Vorfall $($inc.id)"
        }
    }
}

Describe 'Nachweis der Druckempfehlungen' {
    BeforeAll {
        $script:Real = Read-WorkerPerfGuidance $script:CatalogueFile -Apps $script:AppList
        $script:Sourced = @(Get-Elements $script:Real | Where-Object { $_.Source })
        $script:Rows = @(Get-SourceRows $script:SourcesFile)
        # the record's part of the guided report: the section of the health picture at its end has its own lists of
        # sources and its own tests (tests/Health.Tests.ps1)
        $all = [IO.File]::ReadAllText($script:SourcesFile, [Text.Encoding]::UTF8); $cut = $all.IndexOf("`n## Zustandsbild")
        $script:Doc = $(if ($cut -ge 0) { $all.Substring(0, $cut + 1) } else { $all })
        function Get-NamedElements([string]$Text) {
            # the elements a text of the record names by list, first words in quotation marks and situation (Abhilfe „… …“
            # der Situation `print`): the words as written, and the positions of the elements of that list whose text
            # starts with them (a placeholder in its declared form ‹…› back to the placeholder). One position: found.
            $forms = @{}; foreach ($m in [regex]::Matches($script:Doc, '‹([^›]+)› für `\{(\w+)\}`')) { $forms['‹' + $m.Groups[1].Value + '›'] = '{' + $m.Groups[2].Value + '}' }
            $lists = @{ 'Prüfschritt' = 'checks'; 'Abhilfe' = 'remedies'; 'Kontakt' = 'contacts' }
            foreach ($m in [regex]::Matches(($Text -replace '\s+', ' '), '(Prüfschritt|Abhilfe|Kontakt) „(.+?) …“ der Situation `([a-z.]+)`')) {
                $words = $m.Groups[2].Value; foreach ($f in $forms.Keys) { $words = $words.Replace($f, $forms[$f]) }
                $list = $lists[$m.Groups[1].Value]; $situation = $m.Groups[3].Value
                $elements = @($script:Real.situations.$situation.$list); $hits = @()
                for ($k = 0; $k -lt $elements.Count; $k++) { if (([string]$elements[$k].text).StartsWith($words, [StringComparison]::Ordinal)) { $hits += "$situation.$list[$k]" } }
                [pscustomobject]@{ Name = $m.Value; Words = $words; Positions = $hits }
            }
        }
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
            # a note names an element by its first words, never by its position (fix round 4, C4), and speaks only about
            # elements of its own row
            $row.Noted | Should -Be @() -Because "Hinweis zu $($row.Title)"
            foreach ($n in @(Get-NamedElements $row.Line)) {
                $n.Words | Should -Not -Match '[‹›]' -Because $n.Name
                $n.Positions.Count | Should -Be 1 -Because "$($n.Name) im Hinweis zu $($row.Title)"
                $row.Positions | Should -Contain $n.Positions[0] -Because "$($n.Name) im Hinweis zu $($row.Title)"
            }
            if ($row.Vendor -eq 'WorkerPerf') { continue }
            $row.Line | Should -Match 'https://' -Because $row.Title
            # the vendor pages added by the final fix wave were read on 14.11.2026
            $row.Line | Should -Match '2026-11-1[34]' -Because $row.Title
        }
    }
    It 'fuehrt die eigenen Hinweise der Auswertung in einem Abschnitt und sagt, was auf dem Zielsystem zu bestaetigen ist' {      # ruling P3-R35, item B5
        $own = @($Rows | Where-Object { $_.Vendor -eq 'WorkerPerf' })
        $own.Count | Should -Be 1; $own[0].Title | Should -Be 'Hinweis zur Auswertung'
        @($own[0].Positions | Sort-Object) | Should -Be @($Sourced | Where-Object { $_.Source -ceq $OwnSource } | ForEach-Object { $_.Position } | Sort-Object)
        $Doc | Should -Match '(?m)^## Auf dem Zielsystem zu bestätigen$'
        $at = $Doc.IndexOf("`n## Auf dem Zielsystem zu bestätigen`n")
        $section = $Doc.Substring($at)
        # the list names its elements by their first words, never by their position (fix round 4, C4); each is found
        @(Get-Positions $section) | Should -Be @()
        $named = @(Get-NamedElements $section); $named.Count | Should -Be 6
        foreach ($n in $named) { $n.Words | Should -Not -Match '[‹›]' -Because $n.Name; $n.Positions.Count | Should -Be 1 -Because $n.Name }
        # what the list says about them still stands in them
        $byPosition = @{}; foreach ($e in (Get-Elements $Real)) { $byPosition[$e.Position] = $e }
        $texts = @($named | ForEach-Object { $byPosition[$_.Positions[0]].Texts -join ' ' })
        $texts[0] | Should -Match 'DependOnService'
        $texts[1] | Should -Match 'Isolate print drivers from applications'; $texts[2] | Should -Match 'Execute print drivers in isolated processes'
        $texts[3] | Should -Match 'Override print driver execution compatibility setting reported by print driver'
        $texts[4] | Should -Match 'Druckverwaltung'; $texts[5] | Should -Match 'Druckverwaltung'
        @($named | ForEach-Object { $_.Positions[0] -replace '\[\d+\]$', '' }) | Should -Be @('print.checks', 'crash.checks', 'print.checks', 'print.remedies', 'print.checks', 'print.remedies')
        foreach ($word in 'DependOnService', 'Betriebsbereit', 'PrintDriverIsolationOverrideCompat', 'temporäres Profil') { $section | Should -Match ([regex]::Escape($word)) }
    }
    It 'nennt im Abschnitt Zielumgebung die Elemente mit ihren ersten Worten statt mit ihrer Stelle' {                           # fix round 3, A4
        $at = $Doc.IndexOf("`n## Zielumgebung`n"); $next = $Doc.IndexOf("`n## ", $at + 4)
        $section = $Doc.Substring($at, $next - $at) -replace '\s+', ' '
        # one position only: the example that explains what a position is
        @(Get-Positions $section | Sort-Object -Unique) | Should -Be @('print.remedies[2]')
        $forms = @{}; foreach ($m in [regex]::Matches($Doc, '‹([^›]+)› für `\{(\w+)\}`')) { $forms['‹' + $m.Groups[1].Value + '›'] = '{' + $m.Groups[2].Value + '}' }
        $lists = @{ 'Prüfschritt' = 'checks'; 'Abhilfe' = 'remedies'; 'Kontakt' = 'contacts' }
        $named = @([regex]::Matches($section, '(Prüfschritt|Abhilfe|Kontakt) „(.+?) …“ der Situation `([a-z.]+)`'))
        @($named | ForEach-Object { $_.Groups[3].Value + ': ' + $_.Groups[2].Value }) | Should -Be @('crash: Ausnahme oder korrigierte Version der Schutzsoftware', 'print: Spool-Ordner von Hand leeren',
            'print: Dienst „Druckwarteschlange“ zurücksetzen, wie Brother es beschreibt', 'cpu: ‹Anwendung› vom Benutzer schließen lassen', 'memory: ‹Anwendung› schließen und neu starten lassen')
        foreach ($m in $named) {
            # the words as the catalogue writes them: a placeholder in its declared form back to the placeholder
            $words = $m.Groups[2].Value; foreach ($f in $forms.Keys) { $words = $words.Replace($f, $forms[$f]) }
            $words | Should -Not -Match '[‹›]'
            $hit = @($Real.situations.($m.Groups[3].Value).($lists[$m.Groups[1].Value]) | Where-Object { ([string]$_.text).StartsWith($words, [StringComparison]::Ordinal) })
            $hit.Count | Should -Be 1 -Because $m.Value
        }
        # what the section says about these elements still stands in them
        $find = { param($s, $start) @($Real.situations.$s.remedies | Where-Object { ([string]$_.text).StartsWith($start, [StringComparison]::Ordinal) })[0] }
        (& $find 'crash' 'Ausnahme oder korrigierte Version der Schutzsoftware').text | Should -Match 'korrigierte Version bei nicht persistenten Servern im Master-Image'
        foreach ($start in 'Spool-Ordner von Hand leeren', 'Dienst „Druckwarteschlange“ zurücksetzen, wie Brother es beschreibt') { (& $find 'print' $start).text | Should -Match 'setzt auch ein Neustart den Spool-Ordner auf den Stand des Master-Image zurück$' }
        (& $find 'cpu' '{app} vom Benutzer schließen lassen').text | Should -Match 'das wirkt nur, bis die Anwendung wieder startet'
        (& $find 'memory' '{app} schließen und neu starten lassen').text | Should -Match 'nur frei, bis \{app\} ihn wieder belegt$'
    }
    It 'zeigt einen Platzhalter des Katalogs im Nachweis in Winkeln mit seinem erklaerten Namen, nie als Satzteil' {              # fix round 3, A5
        # the forms the record declares
        $forms = @{}; foreach ($m in [regex]::Matches($Doc, '‹([^›]+)› für `\{(\w+)\}`')) { $forms[$m.Groups[2].Value] = '‹' + $m.Groups[1].Value + '›' }
        $forms['app'] | Should -BeExactly '‹Anwendung›'; $forms['user'] | Should -BeExactly '‹Benutzer›'
        # every such form in the record is a declared one; no brace stands outside the declaration
        foreach ($m in [regex]::Matches($Doc, '‹[^›]*›')) { $forms.Values | Should -Contain $m.Value }
        @([regex]::Matches($Doc, '\{\w+\}') | ForEach-Object { $_.Value } | Sort-Object -Unique) | Should -Be @($forms.Keys | ForEach-Object { '{' + $_ + '}' } | Sort-Object)
        @([regex]::Matches($Doc, '`\{\w+\}`')).Count | Should -Be @([regex]::Matches($Doc, '\{\w+\}')).Count
        # the tables of the printer vendors carry summaries written by hand: no brace, no other form
        foreach ($row in $Rows) { $row.Line | Should -Not -Match '[{}]' -Because $row.Title }
        # the sections of the sources added later (AKI to the last source from practice) carry the first words of each element's text: up to the
        # first colon, semicolon or opening bracket after the twentieth character, at most 110 characters, and every
        # placeholder in its declared form
        $label = { param([string]$Text)
            $cut = $Text.Length
            foreach ($sep in ': ', '; ', ' (') { $k = $Text.IndexOf($sep, [StringComparison]::Ordinal); if ($k -gt 20 -and $k -lt $cut) { $cut = $k } }
            $t = [regex]::Replace($Text.Substring(0, $cut), '\{(\w+)\}', { param($m) if ($forms.ContainsKey($m.Groups[1].Value)) { $forms[$m.Groups[1].Value] } else { $m.Value } }).Replace('|', '/')
            if ($t.Length -gt 110) { $t = $t.Substring(0, 107).TrimEnd() + ' …' }
            $t }
        $byPosition = @{}; foreach ($e in (Get-Elements $Real)) { $byPosition[$e.Position] = $e }
        $from = $Doc.IndexOf("`n## AKI`n"); $to = $Doc.IndexOf("`n## Ausnahmen: Praxisquelle vor Hersteller`n"); $from | Should -BeGreaterThan 0; $to | Should -BeGreaterThan $from
        $labels = 0; $withForm = New-Object System.Collections.Generic.List[string]
        foreach ($line in @($Doc.Substring($from, $to - $from) -split "`n" | Where-Object { $_ -match '^\| ' })) {
            $cells = @($line -split ' \| ')
            if ($cells.Count -lt 5 -or $cells[3] -notmatch '^`') { continue }
            foreach ($entry in @($cells[3] -split '<br>')) {
                $m = [regex]::Match($entry, '^`([a-z.]+\.(?:checks|remedies|contacts)\[\d+\])` (.+)$'); $m.Success | Should -BeTrue -Because $entry
                $e = $byPosition[$m.Groups[1].Value]; $e | Should -Not -BeNullOrEmpty -Because $entry
                $want = & $label $e.Texts[0]
                $want | Should -Not -Match '[{}]' -Because "$($e.Position): ein Platzhalter hat im Nachweis keine erklaerte Form"
                # a step for every Office program that stands a second time for Outlook says so
                if ($e.When -contains 'app.outlook' -and @($Sourced | Where-Object { $_.When -contains 'app.office' -and $_.Texts[0] -ceq $e.Texts[0] }).Count -gt 0) { $want += ' (für Outlook)' }
                $m.Groups[2].Value | Should -BeExactly $want -Because $e.Position
                $labels++; if ($want -match '‹') { $withForm.Add($e.Position) }
            }
        }
        $labels | Should -BeGreaterThan 80
        # the labels with a placeholder today: the steps that name the application or the user in their first words
        $withForm.Count | Should -BeGreaterThan 9
        foreach ($p in 'cpu.checks[6]', 'cpu.checks[7]', 'cpu.checks[8]', 'memory.checks[6]') { $withForm | Should -Contain $p }      # memory: moved by round 5
        $Doc | Should -Match 'Add-ins von ‹Anwendung› prüfen'; $Doc | Should -Match 'in der Sitzung von ‹Benutzer› mit Medienoptimierung lief'
    }
    It 'nennt die gemessene Maschine im Nachweis Server, nie Worker' {                                                              # fix round 4, A1 (ruling P3-R66)
        # every line; of a row of a table of adopted sources not the first cell, which quotes the title of a document literally
        $lines = @($Doc -split "`n"); $hits = New-Object System.Collections.Generic.List[string]
        for ($n = 0; $n -lt $lines.Count; $n++) {
            $text = $lines[$n]
            if ($text -match '^\| .*? \| <https://') { $text = $text.Substring($text.IndexOf(' | <https://')) }
            if ($text -cmatch $WorkerWord) { $hits.Add("Zeile $($n + 1): $($lines[$n].Substring(0, [Math]::Min(80, $lines[$n].Length)))") }
        }
        $hits.ToArray() | Should -Be @()
        $Doc | Should -Match 'allgemein so beschreiben lässt: Server mit mehreren Sitzungen'
        # where a row names the print servers and the measured server, it tells them apart
        $Doc | Should -Match ([regex]::Escape('(Einrichtung der Druckserver, auf dem gemessenen Server nicht sichtbar)'))
        $Doc | Should -Match ([regex]::Escape('(Komponenten der Druckserver, nicht des gemessenen Servers)'))
    }
    It 'nennt in den Hinweisen der Tabellen die Elemente mit ihren ersten Worten und erklaert die Form' {                          # fix round 4, C4
        # the notes of the tables name eighteen elements today; the test of the rows checks each against its row
        $inNotes = @($Rows | ForEach-Object { Get-NamedElements $_.Line })
        $inNotes.Count | Should -BeGreaterThan 15
        @($inNotes | Where-Object { $_.Positions.Count -ne 1 } | ForEach-Object { $_.Name }) | Should -Be @()
        # outside the tables a position stands only where the record explains what a position is
        $prose = @($Doc -split "`n" | Where-Object { $_ -notmatch '^\|' }) -join "`n"
        @(Get-Positions $prose | Sort-Object -Unique) | Should -Be @('print.remedies[2]')
        $Doc | Should -Match 'der Abschnitt „Auf dem Zielsystem zu bestätigen“ und die Hinweise in den\s+Tabellen\s+nennen\s+ein\s+Element\s+nicht\s+mit\s+seiner\s+Stelle'
        $Doc | Should -Match '‹Treiber› für `\{driver\}`'
        # the finder finds what it is meant to find, and nothing for words no element starts with
        $found = @(Get-NamedElements 'siehe Abhilfe „Spool-Ordner von Hand leeren …“ der Situation `print` und Prüfschritt „Gibt es nicht …“ der Situation `cpu`')
        $found.Count | Should -Be 2; $found[0].Positions.Count | Should -Be 1; $found[0].Positions[0] | Should -Match '^print\.remedies\[\d+\]$'; $found[1].Positions.Count | Should -Be 0
    }
    It 'bricht den Fliesstext vor den Tabellen und die Liste am Ende nach hoechstens 120 Zeichen um' {                             # fix round 4, C3
        $lines = @($Doc -split "`n")
        $firstTable = [array]::IndexOf($lines, '## Microsoft'); $firstTable | Should -BeGreaterThan 50
        $last = [array]::IndexOf($lines, '## Auf dem Zielsystem zu bestätigen'); $last | Should -BeGreaterThan $firstTable
        $long = @(for ($n = 0; $n -lt $lines.Count; $n++) { if (($n -lt $firstTable -or $n -gt $last) -and $lines[$n].Length -gt 120) { "Zeile $($n + 1): $($lines[$n].Length) Zeichen" } })
        $long | Should -Be @()
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
    It 'fuehrt die zwoelf Quellen aus der Praxis in einer Liste mit Adresse und sagt je Quelle der Runde 5, was sie ist und was sie begrenzt' {      # round 5
        $at = $Doc.IndexOf("`n## Quellen aus der Praxis`n"); $at | Should -BeGreaterThan 0
        $next = $Doc.IndexOf("`n## ", $at + 4); $list = $Doc.Substring($at, $next - $at)
        foreach ($n in $PracticeNames) {
            $line = @($list -split "`n- " | Where-Object { $_.StartsWith("**$n**", [StringComparison]::Ordinal) }); $line.Count | Should -Be 1 -Because $n
            $line[0] | Should -Match '<https://[^>]+>' -Because $n
        }
        # Kasper Johansen: named once in the whole record, without an address, as not used
        @([regex]::Matches($Doc, 'Johansen')).Count | Should -Be 1
        $gone = @($list -split "`n- " | Where-Object { $_ -match 'Johansen' }); $gone.Count | Should -Be 1
        $gone[0] | Should -Match 'nicht mehr erreichbar, nicht verwendet'; $gone[0] | Should -Not -Match 'https?://|www\.|\.net|\.com'
        # Trentent Tye only by his own site
        $Doc | Should -Not -Match 'theorypc'
        foreach ($row in @($Rows | Where-Object { $_.Vendor -eq 'Trentent Tye (Empfehlung aus der Praxis)' })) { $row.Line | Should -Match '\| <https://trentent\.github\.io/' -Because $row.Title }
        # one section per source of this round: what it is, what limits it (year of the tests, what does not carry over)
        foreach ($n in @($PracticeNames | Where-Object { $_ -notin 'Carl Stalhood', 'BIS-F' })) {
            $from = $Doc.IndexOf("`n## $n (Empfehlung aus der Praxis)`n"); $from | Should -BeGreaterThan 0 -Because $n
            $to = $Doc.IndexOf("`n## ", $from + 4); $section = $Doc.Substring($from, $to - $from)
            $intro = ($section -split "`n\| Titel \|", 2)[0]
            $intro | Should -Match 'Quelle aus der Praxis' -Because $n
            $intro | Should -Match 'Grenzen der Quelle: ' -Because $n
            $intro | Should -Match '\b(19|20)\d\d\b' -Because $n
            # Aussage angepasst (final fix wave, item 4): John Billekens backs only; his rows name no element of their own
            if ($n -eq 'John Billekens') { $section | Should -Match 'auch gestützt durch' ; continue }
            @($Rows | Where-Object { $_.Vendor -eq "$n (Empfehlung aus der Praxis)" }).Count | Should -BeGreaterThan 0 -Because $n
        }
        # the sections of the sources from practice stand between the vendors' sections and the exception
        $Doc.IndexOf("`n## Benny Tritsch (Empfehlung aus der Praxis)`n") | Should -BeLessThan $Doc.IndexOf("`n## Ausnahmen: Praxisquelle vor Hersteller`n")
    }
    It 'nennt unter jedem Element, das eine Quelle der Runde 5 nur stuetzt, diese Quelle mit Titel, Adresse und Datum' {      # round 5 (ruling P3-R68)
        # a line "- <Liste> „<erste Worte> …“ der Situation `<s>` – auch gestützt durch: „<Titel>“, <Adresse>, <Datum>" in
        # the section of the source: the element is found, and its text names the source
        $byPosition = @{}; foreach ($e in (Get-Elements $Real)) { $byPosition[$e.Position] = $e }
        $backed = @{}; $heading = ''; $count = 0; $silent = 0
        foreach ($line in @($Doc -split "`n")) {
            $m = [regex]::Match($line, '^## (.+?) \(Empfehlung aus der Praxis\)$'); if ($m.Success) { $heading = $m.Groups[1].Value; continue }
            if ($line -match '^## ') { $heading = ''; continue }
            if ($line -notmatch 'auch gestützt durch') { continue }
            $count++
            $heading | Should -BeIn @($PracticeNames | Where-Object { $_ -notin 'Carl Stalhood', 'BIS-F' }) -Because $line
            $line | Should -Match '^- (Prüfschritt|Abhilfe|Kontakt) „.+ …“ der Situation `[a-z.]+` – auch gestützt durch: „.+“, <https://[^>]+>, .*\b(19|20)\d\d\b' -Because $line
            $named = @(Get-NamedElements $line); $named.Count | Should -Be 1 -Because $line
            $named[0].Positions.Count | Should -Be 1 -Because $line
            $e = $byPosition[$named[0].Positions[0]]
            $word = @($PracticeWords.Keys | Where-Object { $PracticeWords[$_] -eq $heading })[0]
            # fix round 1: a line that says "im Element nicht genannt" keeps a document whose sentence was taken out of the
            # element; then the element does not name the source, else it does
            $named = ($e.Texts -join ' ') -cmatch ('(?<![\p{L}])' + [regex]::Escape($word) + '(?![\p{L}])')
            if ($line -match 'im Element nicht genannt: \S') { $silent++; $named | Should -BeFalse -Because "$($e.Position) nennt $heading, die Zeile sagt das Gegenteil" }
            else { $named | Should -BeTrue -Because "$($e.Position) nennt $heading nicht" }
            # the element keeps its own source: it is not an element of this source
            $e.Source | Should -Not -BeLike "$heading (*" -Because $e.Position
            $backed["$($e.Position)|$heading"] = $true
        }
        $count | Should -BeGreaterThan 40
        $silent | Should -Be 7
        # and the other way round: a text that names one of the ten sources is an element of that source or has its line
        foreach ($e in (Get-Elements $Real)) {
            foreach ($word in $PracticeWords.Keys) {
                if (($e.Texts -join ' ') -cnotmatch ('(?<![\p{L}])' + [regex]::Escape($word) + '(?![\p{L}])')) { continue }
                $name = $PracticeWords[$word]
                ($e.Source -like "$name (*" -or $backed.ContainsKey("$($e.Position)|$name")) | Should -BeTrue -Because "$($e.Position) nennt $name, der Nachweis fuehrt es dort nicht"
            }
        }
        # an element of Citrix or Microsoft that a source from practice only backs keeps its source: as many as before round 5
        # Aussage angepasst (final fix wave, items 1, 2, 4, 5, 10): 89 then; 15 elements more carry the vendor's document
        # (four exclusions, three SMB, two Outlook, two signatures, two machine catalogues, active write back, Teams under
        # hang), one less (the Outlook remedy taken into its check), three carry VMware's
        @(Get-Elements $Real | Where-Object { $_.Source -like 'Citrix: *' -or $_.Source -like 'Microsoft: *' }).Count | Should -Be 103
        @(Get-Elements $Real | Where-Object { $_.Source -like 'VMware: *' }).Count | Should -Be 3
    }
    It 'haelt fest, was die Korrekturrunde nicht mehr als Schritt fuehrt, und was auf dem Zielsystem zu bestaetigen ist' {      # round 5, fix round 1, items 1, 2, 5, 7, 9, 11, 13
        $section = { param($n) $from = $Doc.IndexOf("`n## $n (Empfehlung aus der Praxis)`n"); $to = $Doc.IndexOf("`n## ", $from + 4); $Doc.Substring($from, $to - $from) }
        $rejected = { param($n) @(((& $section $n) -split '### Nicht aufgenommen', 2)[1] -split "`n" | Where-Object { $_ -match '^\|' }) }
        # item 5: the steps on the duration of Group Policy at logon wait for a situation of their own
        foreach ($pair in @{ N = 'Thomas Kötzing'; Id = 'PXG-49' }, @{ N = 'Trentent Tye'; Id = 'PXG-50' }) {
            $row = @(& $rejected $pair.N | Where-Object { $_ -match $pair.Id }); $row.Count | Should -Be 1 -Because $pair.Id
            $row[0] | Should -Match 'der Bericht hat keine Situation für langsame Anmeldungen' -Because $pair.Id; $row[0] | Should -Match 'er wartet auf eine solche Situation' -Because $pair.Id
            $row[0] | Should -Match '<https://[^>]+>' -Because $pair.Id
        }
        foreach ($title in 'Einfache Fehleranalyse der Dauer von Gruppenrichtlinien während der Anmeldung', 'Group Policy - Monolithic vs Functional Design and Performance Evaluation') {
            @($Rows | Where-Object { $_.Title -eq $title }) | Should -Be @() -Because $title; @($Doc -split "`n" | Where-Object { $_.StartsWith("| $title |") }) | Should -Be @() -Because $title
        }
        # item 11: why the print part of PXG-54 is not written
        $row = @(& $rejected 'Thomas Kötzing' | Where-Object { $_ -match 'PXG-54' }); $row.Count | Should -Be 1
        $row[0] | Should -Match 'Auch beim Drucken ist der Schritt nicht geschrieben: Ein Druckvorfall des Berichts ist ein Fehler des Druckdiensts, eines Treibers oder einer Druckwarteschlange'
        @(Get-Elements $Real | Where-Object { $_.Situation -eq 'print' -and @($_.When | Where-Object { $_ -like 'app.*' }).Count -gt 0 }) | Should -Be @()
        # items 7 and 9: a sentence taken out of an element stays in the record with its conditions
        $lines = @($Doc -split "`n" | Where-Object { $_ -match 'auch gestützt durch' })
        $leech = @($lines | Where-Object { $_ -match '^- Abhilfe „CPU-Spitzenschutz' -and $_ -match 'The Taming of the Print Server' }); $leech.Count | Should -Be 1
        $leech[0] | Should -Match 'Bedingung: Skript für einen Druckserver von 2016; im Element nicht genannt: '
        $rankin = @($lines | Where-Object { $_ -match '^- Abhilfe „Scan-Ausschlüsse ergänzen' -and $_ -match 'part #10' }); $rankin.Count | Should -Be 4
        foreach ($l in $rankin) { $l | Should -Match 'im Test von 2021 mit Windows Server 2019, dateibasierten Profilen und anderer Schutzsoftware als Microsoft Defender; im Element nicht genannt: ' }
        $Doc | Should -Not -Match 'ohne Microsoft Defender'
        # item 2: the title as the page writes it, in the row, the backing line and the quotes
        @([regex]::Matches($Doc, [regex]::Escape('Citrix Xenapp/XenDesktop and Folder Redirection – the last word'))).Count | Should -Be 3
        $Doc | Should -Not -Match 'Citrix XenApp, XenDesktop and Folder Redirection'
        # item 1: the rule of the ranking and the invariant are stated; the element taken into an existing step is listed
        ($Doc -replace '\s+', ' ') | Should -Match 'Ein Element ohne Bedingung, dessen Quelle den Zusatz „Empfehlung aus der Praxis“ trägt, steht hinter den allgemeinen Schritten der Hersteller und des Katalogs und hinter den Hinweisen auf nicht Gemessenes'
        ($Doc -replace '\s+', ' ') | Should -Match 'stehen die ersten fünf Prüfschritte und die ersten drei Vorschläge des Rests auch in der Liste vorn, in derselben Reihenfolge'
        @(& $rejected 'Manuel Winkel' | Where-Object { $_ -match 'PXG-03' -and $_ -match 'als Satz im vorhandenen Schritt' }).Count | Should -Be 1
        @(& $rejected 'Thomas Kötzing' | Where-Object { $_ -match 'PXG-21' -and $_ -match 'als Satz im Prüfschritt zum Arbeitsspeicher je Sitzung' }).Count | Should -Be 1
        # item 13: the names this round adds are among those to confirm on the target system
        $at = $Doc.IndexOf("`n## Auf dem Zielsystem zu bestätigen`n"); $confirm = $Doc.Substring($at) -replace '\s+', ' '
        foreach ($n in 'Ereignisse 1 und 4 im Protokoll „User Profile Service > Operational“', '„Auto Prevent CPU Spikes“', '„Multi-session optimization“', '„Rule Enforcement Mode“', '„Delete network printers at startup“',
            '„Enable VHD disk compaction“', '„Automatically reattach VHDX disks“', '„Enable local caching for profile containers“', '„Enable multi-session write-back for profile containers“', '„Session Performance“',
            'CtxSession.exe -v', '„Citrix MCS“', 'mcsdif.vhdx', 'Strg+Alt+Umschalt+1', 'vdi_debug.txt', 'PendingFileRenameOperations', 'DisableBandwidthThrottling', 'StartupBoostEnabled') {
            $confirm | Should -Match ([regex]::Escape($n)) -Because $n
        }
        $confirm | Should -Not -Match '5324|4016|4257'
    }
    It 'hat je Quelle aus der Praxis, fuer AKI, fuer WEM und fuer die Anwendungen einen Abschnitt und nennt die Ausnahme des Auftraggebers' {      # fix round 2, B8
        $headings = @([regex]::Matches($Doc, '(?m)^## (.+)$') | ForEach-Object { $_.Groups[1].Value })
        foreach ($h in 'Zielumgebung', 'AKI', 'Citrix – Workspace Environment Management', 'Microsoft – Edge und WebView2', 'Microsoft – Office', 'Microsoft – Teams',
            'Carl Stalhood (Empfehlung aus der Praxis)', 'BIS-F (Empfehlung aus der Praxis)', 'Ausnahmen: Praxisquelle vor Hersteller', 'WorkerPerf', 'Auf dem Zielsystem zu bestätigen') {
            $headings | Should -Contain $h
        }
        foreach ($n in $PracticeNames) { $headings | Should -Contain "$n (Empfehlung aus der Praxis)" }
        # every source of an element is a row of the section of its vendor or source from practice
        foreach ($source in @($Sourced | ForEach-Object { $_.Source } | Sort-Object -Unique)) {
            $vendor, $title = $source -split ': ', 2
            @($Rows | Where-Object { $_.Vendor -ceq $vendor -and $_.Title -ceq $title }).Count | Should -Be 1 -Because $source
        }
        # the sections of the new sources say what was left out
        foreach ($h in 'AKI', 'Citrix – Workspace Environment Management', 'Microsoft – Edge und WebView2', 'Microsoft – Office', 'Microsoft – Teams',
            'Carl Stalhood (Empfehlung aus der Praxis)', 'BIS-F (Empfehlung aus der Praxis)' + @($PracticeNames | ForEach-Object { "$_ (Empfehlung aus der Praxis)" })) {
            $at = $Doc.IndexOf("`n## $h`n"); $next = $Doc.IndexOf("`n## ", $at + 4)
            $section = $Doc.Substring($at, $next - $at)
            $section | Should -Match '### Nicht aufgenommen' -Because $h
            @(($section -split '### Nicht aufgenommen', 2)[1] -split "`n" | Where-Object { $_ -match '^\|' -and $_ -notmatch '^\|\s*(-+|Empfehlung)' }).Count | Should -BeGreaterThan 0 -Because $h
        }
        # the exception: the power plan, with the customer's reason and both vendors' statements
        $at = $Doc.IndexOf("`n## Ausnahmen: Praxisquelle vor Hersteller`n"); $next = $Doc.IndexOf("`n## ", $at + 4)
        $section = $Doc.Substring($at, $next - $at)
        foreach ($word in 'Energiesparplan', 'Höchstleistung', 'Ausbalanciert', 'VMware', 'Begründung des Auftraggebers', 'Citrix-Terminalserver', 'Receive Side Scaling', '2026-11-13') { $section | Should -Match ([regex]::Escape($word)) }
        @(Get-Positions $section) | Should -Be @()
        # the target environment is described generally
        $at = $Doc.IndexOf("`n## Zielumgebung`n"); $next = $Doc.IndexOf("`n## ", $at + 4)
        $section = $Doc.Substring($at, $next - $at)
        foreach ($word in 'Machine Creation Services', 'nicht persistent', 'Master-Image', 'Workspace Environment Management', 'PrinTaurus SmartSpread') { $section | Should -Match ([regex]::Escape($word)) }
        $section | Should -Match ([regex]::Escape($InImage)); $section | Should -Match ([regex]::Escape($ByPolicy))
    }
}
