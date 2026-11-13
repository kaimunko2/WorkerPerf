#Requires -Version 5.1
# Guidance catalogue (guidance.de.json) and application list (apps.json): loading and checking; the situation, conditions
# and placeholder values of an incident and its guidance; the ranking of the incidents, the groups after the cards and the situation summary
# (Lagebild) of the capture; the plain-text summaries to copy. Dot-source this file; it only defines variables and
# functions and runs nothing. It needs WorkerPerf.Common.ps1 (ConvertFrom-WorkerPerfJsonFile, Read-WorkerPerfThresholds,
# Get-WorkerPerfField, Test-WorkerPerfSkipDetail, $script:WorkerPerfRoleNames, $script:WorkerPerfCategories),
# WorkerPerf.Events.ps1 ($script:WorkerPerfPatternOrder, Format-WorkerPerfEventDate, Test-WorkerPerfAccountPattern,
# Get-WorkerPerfUncheckedStatements, Join-WorkerPerfTextList) and WorkerPerf.Findings.ps1 (Format-WorkerPerfTextNumber,
# Format-WorkerPerfValue, Format-WorkerPerfClock, Get-WorkerPerfMeasureText); the version without names of a copy text
# needs WorkerPerf.Mask.ps1 (Hide-WorkerPerfReportText). Words come from the texts (texts.de.json) and the catalogue.

$script:WorkerPerfSituations = @('cpu', 'memory', 'disk', 'share', 'profile', 'delay.many', 'delay.single', 'chronic.network', 'chronic.resource',
    'crash', 'hang', 'service', 'print', 'profileerror', 'system', 'fallback')
# spec 5.5 names the first 14; module, driver and count are needed by the event situations, the rest by the Lagebild,
# the hints and the head of the copy text; skipped carries the labels of skipped categories, parts the joined parts of
# the red and the yellow sentence of the Lagebild
$script:WorkerPerfGuidancePlaceholders = @('user', 'app', 'share', 'baseline', 'value', 'target', 'from', 'to', 'duration', 'affected', 'resource',
    'endpoint', 'endpointValue', 'security', 'module', 'driver', 'count', 'server', 'date', 'signals', 'message', 'bottlenecks', 'delays',
    'events', 'chronic', 'minutes', 'incidents', 'skipped', 'parts')
# conditions without a variable part (spec 5.4 and the additions of the measurement categories); lead.<resource> names the
# lead resource of a bottleneck, so that the one entry for a chronic state can speak about the resource it is
$script:WorkerPerfGuidanceConditions = @('cause.app', 'cause.security', 'cause.none', 'cause.nodata', 'cause.notmeasured', 'scan',
    'companion.security', 'endpoint.slow', 'event.applocker', 'event.defender', 'affected.many', 'affected.one', 'affected.unknown', 'chronic',
    'lead.cpu', 'lead.memory', 'lead.disk', 'lead.share', 'lead.profile',
    'pattern.none', 'pattern.unchecked', 'driver.v3', 'driver.v4', 'driver.shared', 'driver.isolated', 'spooler.crash', 'queue.stuck', 'before',
    'incident.unverified')
# conditions that only name a gap, something the capture did not measure or the report did not check: these names and
# every unmeasured.<signal> and skipped.<category>
$script:WorkerPerfGuidanceGapConditions = @('cause.notmeasured', 'pattern.unchecked', 'incident.unverified')
$script:WorkerPerfGuidanceGapPrefixes = @('unmeasured.', 'skipped.')
# conditions that only name a coincidence in time with another incident: something the report found, but it says nothing
# about cause and effect
$script:WorkerPerfGuidanceCoincidenceConditions = @('pattern.overlap')
# catalogue parts and the keys each text part must have, in the order they are checked
$script:WorkerPerfGuidanceParts = @('version', 'terms', 'vendors', 'userView', 'lagebild', 'hints', 'copy', 'fallbackNote', 'situations')
$script:WorkerPerfGuidancePartKeys = [ordered]@{
    'userView' = @('many', 'one', 'none', 'unknown', 'chronic', 'eventMany', 'eventOne', 'eventNone', 'before')
    'lagebild' = @('red', 'yellow', 'green', 'greenSkipped', 'partBottlenecks', 'partDelays', 'partEvents', 'partChronic', 'partSeparator', 'notMeasured')
    'hints'    = @('unmeasured', 'skipped', 'notFinished', 'error', 'errorNoMessage', 'stopped')
    'copy'     = @('head', 'summaryHead', 'measure', 'cause', 'affected', 'checks', 'remedies', 'contact', 'maxChecks', 'maxRemedies', 'moreChecks', 'moreCheck',
        'moreRemedies', 'moreRemedy')
}
# the keys of these parts that hold a number, not a text: how many checks and remedies a copy text carries (ruling P3-R59)
$script:WorkerPerfGuidancePartNumbers = @('copy.maxChecks', 'copy.maxRemedies')
# the placeholders a text of these parts may hold (ruling P3-R26, the contract with the catalogue): '<part>.<key>', else
# '<part>.*' for every other key of the part; copy.cause, copy.checks, copy.remedies and copy.contact are labels. The red
# and the yellow sentence hold no count themselves: each count stands in its part (lagebild.part*), so that the part of
# a category that was not measured can be left out (ruling P3-R49)
$script:WorkerPerfGuidanceTextPlaceholders = @{
    'copy.head' = @('server', 'date'); 'copy.summaryHead' = @('server', 'date', 'from', 'to'); 'copy.measure' = @('value', 'target')
    'copy.affected' = @('affected'); 'copy.moreChecks' = @('count'); 'copy.moreRemedies' = @('count'); 'copy.*' = @()
    'userView.unknown' = @('duration', 'from', 'to'); 'userView.*' = @('affected', 'duration', 'from', 'to', 'count')
    'lagebild.red' = @('parts', 'minutes', 'incidents')
    'lagebild.yellow' = @('parts', 'minutes', 'incidents')
    'lagebild.partBottlenecks' = @('bottlenecks'); 'lagebild.partDelays' = @('delays'); 'lagebild.partEvents' = @('events'); 'lagebild.partChronic' = @('chronic')
    'lagebild.greenSkipped' = @('skipped'); 'lagebild.notMeasured' = @('skipped'); 'lagebild.*' = @()
    'hints.unmeasured' = @('signals'); 'hints.skipped' = @('skipped'); 'hints.error' = @('message'); 'hints.*' = @()
}
# list of a situation -> required text fields of its elements
$script:WorkerPerfGuidanceItemFields = [ordered]@{
    'checks'   = @('text', 'where', 'sign')
    'remedies' = @('text', 'precondition')
    'contacts' = @('text')
}
# placeholders every incident has a value for: the only ones meaning and impact of a situation and the fallbackNote may
# hold (title and short hold none), so these texts never vanish for want of a value
$script:WorkerPerfGuidanceAlwaysValues = @('from', 'to', 'duration', 'server', 'date')
$script:WorkerPerfGuidanceThresholdFile = Join-Path $PSScriptRoot 'thresholds.json'

function Stop-WorkerPerfGuidance([string]$Path, [string]$Entry, [string]$Item, [string]$Field, [string]$Reason) {
    # Katalog '<Pfad>': Eintrag '<Eintrag>', <Element>: Feld '<Feld>' <Grund>.  (element and field are optional)
    $at = "Katalog '$Path': Eintrag '$Entry'"
    if ($Item) { $at += ", $Item" }
    if ($Field) { throw "${at}: Feld '$Field' $Reason." }
    throw "$at $Reason."
}

function Test-WorkerPerfGuidanceObject($Value) {
    return ($null -ne $Value -and $Value -is [System.Management.Automation.PSCustomObject])
}

function Get-WorkerPerfGuidanceMember($Object, [string]$Name) {
    # The property of a JSON object (also one holding an empty or one-element list, which a plain return would unroll),
    # or $null when it is missing.
    if (-not (Test-WorkerPerfGuidanceObject $Object)) { return $null }
    return $Object.PSObject.Properties[$Name]
}

function Test-WorkerPerfGuidanceText([string]$Path, [string]$Entry, [string]$Item, [string]$Field, [string]$Text) {
    # Braces only as a placeholder {name} (letters and digits) with a known name; any other brace is an error.
    $placeholder = '\{([A-Za-z0-9]+)\}'
    foreach ($m in [regex]::Matches($Text, $placeholder)) {
        if ($script:WorkerPerfGuidancePlaceholders -cnotcontains $m.Groups[1].Value) {
            Stop-WorkerPerfGuidance $Path $Entry $Item $Field "enthaelt den unbekannten Platzhalter '$($m.Value)'"
        }
    }
    if (([regex]::Replace($Text, $placeholder, '')).IndexOfAny([char[]]'{}') -ge 0) {
        Stop-WorkerPerfGuidance $Path $Entry $Item $Field 'enthaelt eine geschweifte Klammer ohne Platzhalter'
    }
}

function Assert-WorkerPerfGuidanceString([string]$Path, [string]$Entry, [string]$Item, [string]$Field, $Value) {
    if ($Value -isnot [string]) { Stop-WorkerPerfGuidance $Path $Entry $Item $Field 'ist kein Text' }
    if ([string]::IsNullOrWhiteSpace($Value)) { Stop-WorkerPerfGuidance $Path $Entry $Item $Field 'ist leer' }
    Test-WorkerPerfGuidanceText $Path $Entry $Item $Field $Value
}

function Test-WorkerPerfGuidanceCount($Value) {
    # Whether a value of the catalogue is a whole number from 1 on (a JSON number without fraction; no text, no list).
    return (($Value -is [int] -or $Value -is [long]) -and $Value -ge 1)
}

function Assert-WorkerPerfGuidanceField([string]$Path, [string]$Entry, [string]$Item, $Object, [string]$Field) {
    # A required text field of an object.
    $p = Get-WorkerPerfGuidanceMember $Object $Field
    if ($null -eq $p) { Stop-WorkerPerfGuidance $Path $Entry $Item $Field 'fehlt' }
    Assert-WorkerPerfGuidanceString $Path $Entry $Item $Field $p.Value
}

function Test-WorkerPerfGuidanceCondition([string]$Name, $Catalogue, [string[]]$Signals = $null, $Apps = $null) {
    # Whether a condition name is known (spec 5.4). Signals: the ids of thresholds.json; read from there when not given.
    # Apps: the application list (Read-WorkerPerfApps); without it no app.<key> is known.
    if ($script:WorkerPerfGuidanceConditions -ccontains $Name) { return $true }
    $dot = $Name.IndexOf('.')
    if ($dot -lt 1 -or $dot -eq $Name.Length - 1) { return $false }
    $kind = $Name.Substring(0, $dot); $rest = $Name.Substring($dot + 1)
    switch -CaseSensitive ($kind) {
        'role' { return ($script:WorkerPerfRoleNames -ccontains $rest) }
        'app' { return (@(Get-WorkerPerfGuidanceAppKeys $Apps) -ccontains $rest) }
        'skipped' { return (@($script:WorkerPerfCategories.Keys) -ccontains $rest) }
        'pattern' {
            if ($null -eq (Get-Variable -Name 'WorkerPerfPatternOrder' -Scope Script -ErrorAction SilentlyContinue)) {
                throw "Bedingung '$Name': die Muster fehlen; WorkerPerf.Events.ps1 muss vor dem Pruefen des Katalogs geladen sein."
            }
            return ($script:WorkerPerfPatternOrder -ccontains $rest)
        }
        'unmeasured' {
            if ($null -eq $Signals) { $Signals = [string[]]@((Read-WorkerPerfThresholds $script:WorkerPerfGuidanceThresholdFile).Keys) }
            return ($rest -ceq 'input.session' -or $Signals -ccontains $rest)
        }
        'driver' {
            if (-not $rest.StartsWith('vendor.', [StringComparison]::Ordinal)) { return $false }
            $key = $rest.Substring(7)
            $vendors = Get-WorkerPerfGuidanceMember $Catalogue 'vendors'
            if ($null -eq $vendors) { return $false }
            foreach ($v in @($vendors.Value)) {
                $k = Get-WorkerPerfGuidanceMember $v 'key'
                if ($null -ne $k -and [string]$k.Value -ceq $key) { return $true }
            }
            return $false
        }
    }
    return $false
}

function Test-WorkerPerfGuidanceItem([string]$Path, [string]$Situation, [string]$ListName, [int]$Index, $Element, $Catalogue, [string[]]$Signals, $Apps = $null) {
    # One check, remedy or contact; returns whether it has a condition.
    $item = "$ListName[$Index]"
    if (-not (Test-WorkerPerfGuidanceObject $Element)) { Stop-WorkerPerfGuidance $Path $Situation $item '' 'ist kein Objekt' }
    foreach ($f in $script:WorkerPerfGuidanceItemFields[$ListName]) { Assert-WorkerPerfGuidanceField $Path $Situation $item $Element $f }
    $conditions = @()
    $when = Get-WorkerPerfGuidanceMember $Element 'when'
    if ($null -ne $when) {
        if ($when.Value -isnot [array]) { Stop-WorkerPerfGuidance $Path $Situation $item 'when' 'ist keine Liste' }
        $conditions = @($when.Value)
        foreach ($n in $conditions) {
            # a catalogue that names an application needs the application list
            if ($n -is [string] -and $null -eq $Apps -and $n.StartsWith('app.', [StringComparison]::Ordinal)) {
                Stop-WorkerPerfGuidance $Path $Situation $item 'when' "enthaelt die Bedingung '$n', aber es ist keine Anwendungsliste angegeben (apps.json)"
            }
            if ($n -isnot [string] -or -not (Test-WorkerPerfGuidanceCondition $n $Catalogue $Signals $Apps)) {
                Stop-WorkerPerfGuidance $Path $Situation $item 'when' "enthaelt die unbekannte Bedingung '$n'"
            }
        }
    }
    # spec 5.7: every print element (check, remedy, contact) names its source, and so does every element for a driver
    # or for a standard application
    $needsSource = $Situation -eq 'print' -or @($conditions | Where-Object { $_ -ceq 'pattern.printdriver' -or
            $_.StartsWith('driver.', [StringComparison]::Ordinal) -or $_.StartsWith('app.', [StringComparison]::Ordinal) }).Count -gt 0
    $source = Get-WorkerPerfGuidanceMember $Element 'source'
    if ($null -ne $source) { Assert-WorkerPerfGuidanceString $Path $Situation $item 'source' $source.Value }
    elseif ($needsSource) { Stop-WorkerPerfGuidance $Path $Situation $item 'source' 'fehlt (Pflicht fuer Druckempfehlungen und fuer Elemente zu einer Standardanwendung)' }
    return ($conditions.Count -gt 0)
}

function Assert-WorkerPerfGuidanceAlwaysValues([string]$Path, [string]$Entry, [string]$Field, [string]$Text) {
    # A text that must never vanish holds only placeholders every incident has a value for.
    foreach ($m in [regex]::Matches($Text, '\{([A-Za-z0-9]+)\}')) {
        if ($script:WorkerPerfGuidanceAlwaysValues -cnotcontains $m.Groups[1].Value) {
            Stop-WorkerPerfGuidance $Path $Entry '' $Field "enthaelt den Platzhalter '$($m.Value)', den nicht jeder Vorfall hat"
        }
    }
}

function Test-WorkerPerfGuidanceImpactVariants([string]$Path, [string]$Name, $Entry, $Catalogue, [string[]]$Signals, $Apps = $null) {
    # impactVariants (optional): other wordings of the impact of a situation, each with the conditions (when, at least
    # one) under which it replaces impact, so that the sentence does not state as a fact what the capture did not
    # measure. Like impact, a variant only uses values every incident has.
    $variants = Get-WorkerPerfGuidanceMember $Entry 'impactVariants'
    if ($null -eq $variants) { return }
    if ($variants.Value -isnot [array]) { Stop-WorkerPerfGuidance $Path $Name '' 'impactVariants' 'ist keine Liste' }
    $list = @($variants.Value)
    for ($i = 0; $i -lt $list.Count; $i++) {
        $item = "impactVariants[$i]"
        if (-not (Test-WorkerPerfGuidanceObject $list[$i])) { Stop-WorkerPerfGuidance $Path $Name $item '' 'ist kein Objekt' }
        Assert-WorkerPerfGuidanceField $Path $Name $item $list[$i] 'text'
        foreach ($m in [regex]::Matches($list[$i].text, '\{([A-Za-z0-9]+)\}')) {
            if ($script:WorkerPerfGuidanceAlwaysValues -cnotcontains $m.Groups[1].Value) {
                Stop-WorkerPerfGuidance $Path $Name $item 'text' "enthaelt den Platzhalter '$($m.Value)', den nicht jeder Vorfall hat"
            }
        }
        $when = Get-WorkerPerfGuidanceMember $list[$i] 'when'
        if ($null -eq $when) { Stop-WorkerPerfGuidance $Path $Name $item 'when' 'fehlt' }
        if ($when.Value -isnot [array] -or @($when.Value).Count -eq 0) { Stop-WorkerPerfGuidance $Path $Name $item 'when' 'ist keine Liste mit Bedingungen' }
        foreach ($n in @($when.Value)) {
            if ($n -isnot [string] -or -not (Test-WorkerPerfGuidanceCondition $n $Catalogue $Signals $Apps)) {
                Stop-WorkerPerfGuidance $Path $Name $item 'when' "enthaelt die unbekannte Bedingung '$n'"
            }
        }
    }
}

function Test-WorkerPerfGuidanceSituation([string]$Path, [string]$Name, $Entry, $Catalogue, [string[]]$Signals, $Apps = $null) {
    if (-not (Test-WorkerPerfGuidanceObject $Entry)) { Stop-WorkerPerfGuidance $Path $Name '' '' 'ist kein Objekt' }
    foreach ($f in 'title', 'meaning', 'impact', 'short') { Assert-WorkerPerfGuidanceField $Path $Name '' $Entry $f }
    # title and short are constant; meaning and impact only use values every incident has
    foreach ($f in 'title', 'short') {
        $m = [regex]::Match($Entry.$f, '\{[A-Za-z0-9]+\}')
        if ($m.Success) { Stop-WorkerPerfGuidance $Path $Name '' $f "darf keinen Platzhalter enthalten ('$($m.Value)')" }
    }
    foreach ($f in 'meaning', 'impact') { Assert-WorkerPerfGuidanceAlwaysValues $Path $Name $f $Entry.$f }
    Test-WorkerPerfGuidanceImpactVariants $Path $Name $Entry $Catalogue $Signals $Apps
    foreach ($list in $script:WorkerPerfGuidanceItemFields.Keys) {
        $p = Get-WorkerPerfGuidanceMember $Entry $list
        if ($null -eq $p) { Stop-WorkerPerfGuidance $Path $Name '' $list 'fehlt' }
        if ($p.Value -isnot [array]) { Stop-WorkerPerfGuidance $Path $Name '' $list 'ist keine Liste' }
        $elements = @($p.Value)
        $general = 0
        for ($i = 0; $i -lt $elements.Count; $i++) {
            if (-not (Test-WorkerPerfGuidanceItem $Path $Name $list $i $elements[$i] $Catalogue $Signals $Apps)) { $general++ }
        }
        if ($list -eq 'checks' -and $general -eq 0) { Stop-WorkerPerfGuidance $Path $Name '' 'checks' 'braucht mindestens einen Pruefschritt ohne Bedingung' }
    }
}

function Test-WorkerPerfGuidanceWildcard([string]$Pattern) {
    # Whether a vendor pattern is a valid wildcard pattern, with the options Test-WorkerPerfAccountPattern matches it with
    # (an invalid one such as 'HP [' only fails when it is matched).
    $opt = [System.Management.Automation.WildcardOptions]::IgnoreCase -bor [System.Management.Automation.WildcardOptions]::CultureInvariant
    try { $null = (New-Object System.Management.Automation.WildcardPattern $Pattern, $opt).IsMatch(''); return $true }
    catch { return $false }
}

function Read-WorkerPerfGuidance([string]$Path, $Apps = $null) {
    # Reads the guidance catalogue and checks structure, required fields, conditions and placeholders (spec 5.6).
    # Returns the catalogue as read; the first error stops with a message that names entry and field. Apps: the
    # application list (Read-WorkerPerfApps), whose keys are the conditions app.<key>; a catalogue that uses such a
    # condition is refused without it.
    $cat = ConvertFrom-WorkerPerfJsonFile $Path
    if (-not (Test-WorkerPerfGuidanceObject $cat)) { throw "Katalog '$Path' ist kein JSON-Objekt." }
    foreach ($part in $script:WorkerPerfGuidanceParts) {
        if ($null -eq (Get-WorkerPerfGuidanceMember $cat $part)) { Stop-WorkerPerfGuidance $Path $part '' '' 'fehlt' }
    }
    foreach ($part in 'version', 'fallbackNote') { Assert-WorkerPerfGuidanceString $Path $part '' '' $cat.$part }
    # the fallback meaning starts with the note: like meaning and impact, it must never vanish for want of a value
    Assert-WorkerPerfGuidanceAlwaysValues $Path 'fallbackNote' '' $cat.fallbackNote

    if (-not (Test-WorkerPerfGuidanceObject $cat.terms)) { Stop-WorkerPerfGuidance $Path 'terms' '' '' 'ist kein Objekt' }
    foreach ($p in $cat.terms.PSObject.Properties) { Assert-WorkerPerfGuidanceString $Path 'terms' '' $p.Name $p.Value }

    foreach ($part in $script:WorkerPerfGuidancePartKeys.Keys) {
        $o = $cat.$part
        if (-not (Test-WorkerPerfGuidanceObject $o)) { Stop-WorkerPerfGuidance $Path $part '' '' 'ist kein Objekt' }
        foreach ($k in $script:WorkerPerfGuidancePartKeys[$part]) {
            if ($null -eq (Get-WorkerPerfGuidanceMember $o $k)) { Stop-WorkerPerfGuidance $Path $part '' $k 'fehlt' }
        }
        foreach ($p in $o.PSObject.Properties) {
            if ($script:WorkerPerfGuidancePartNumbers -ccontains ($part + '.' + $p.Name)) {
                if (-not (Test-WorkerPerfGuidanceCount $p.Value)) { Stop-WorkerPerfGuidance $Path $part '' $p.Name 'ist keine ganze Zahl ab 1' }
                continue
            }
            Assert-WorkerPerfGuidanceString $Path $part '' $p.Name $p.Value
            $allowed = $script:WorkerPerfGuidanceTextPlaceholders[$part + '.' + $p.Name]
            if ($null -eq $allowed) { $allowed = $script:WorkerPerfGuidanceTextPlaceholders[$part + '.*'] }
            foreach ($m in [regex]::Matches($p.Value, '\{([A-Za-z0-9]+)\}')) {
                if (@($allowed) -cnotcontains $m.Groups[1].Value) {
                    Stop-WorkerPerfGuidance $Path $part '' $p.Name "enthaelt den Platzhalter '$($m.Value)', der in diesem Text nicht erlaubt ist"
                }
            }
        }
    }

    $vendors = (Get-WorkerPerfGuidanceMember $cat 'vendors').Value
    if ($vendors -isnot [array]) { Stop-WorkerPerfGuidance $Path 'vendors' '' '' 'ist keine Liste' }
    # ordinal, like the condition driver.vendor.<key>
    $keys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $vendorList = @($vendors)
    for ($i = 0; $i -lt $vendorList.Count; $i++) {
        $v = $vendorList[$i]; $item = "vendors[$i]"
        if (-not (Test-WorkerPerfGuidanceObject $v)) { Stop-WorkerPerfGuidance $Path 'vendors' $item '' 'ist kein Objekt' }
        Assert-WorkerPerfGuidanceField $Path 'vendors' $item $v 'key'
        if (-not $keys.Add($v.key)) { Stop-WorkerPerfGuidance $Path 'vendors' $item 'key' "ist doppelt ('$($v.key)')" }
        $match = Get-WorkerPerfGuidanceMember $v 'match'
        if ($null -eq $match) { Stop-WorkerPerfGuidance $Path 'vendors' $item 'match' 'fehlt' }
        if ($match.Value -isnot [array] -or @($match.Value).Count -eq 0) { Stop-WorkerPerfGuidance $Path 'vendors' $item 'match' 'ist keine Liste mit Mustern' }
        foreach ($m in @($match.Value)) {
            if ($m -isnot [string] -or [string]::IsNullOrWhiteSpace($m)) { Stop-WorkerPerfGuidance $Path 'vendors' $item 'match' 'enthaelt ein leeres Muster' }
            if (-not (Test-WorkerPerfGuidanceWildcard $m)) { Stop-WorkerPerfGuidance $Path 'vendors' $item 'match' "enthaelt das ungueltige Muster '$m'" }
        }
    }

    $situations = $cat.situations
    if (-not (Test-WorkerPerfGuidanceObject $situations)) { Stop-WorkerPerfGuidance $Path 'situations' '' '' 'ist kein Objekt' }
    foreach ($p in $situations.PSObject.Properties) {
        if ($script:WorkerPerfSituations -cnotcontains $p.Name) { Stop-WorkerPerfGuidance $Path $p.Name '' '' 'ist unbekannt' }
    }
    foreach ($s in $script:WorkerPerfSituations) {
        if ($null -eq (Get-WorkerPerfGuidanceMember $situations $s)) { Stop-WorkerPerfGuidance $Path $s '' '' 'fehlt' }
    }
    # the signal ids once per call
    $signals = [string[]]@((Read-WorkerPerfThresholds $script:WorkerPerfGuidanceThresholdFile).Keys)
    foreach ($s in $script:WorkerPerfSituations) { Test-WorkerPerfGuidanceSituation $Path $s $situations.$s $cat $signals $Apps }
    return $cat
}

# ---------- the application list (apps.json): standard applications and the name patterns of their processes ----------

function Stop-WorkerPerfApps([string]$Path, [string]$App, [string]$Field, [string]$Reason) {
    # Anwendungsliste '<Pfad>': Anwendung <Anwendung>: Feld '<Feld>' <Grund>.  (application and field are optional)
    $at = "Anwendungsliste '$Path'"
    if ($App) { $at += ": Anwendung $App" }
    if ($Field) { throw "${at}: Feld '$Field' $Reason." }
    throw "$at $Reason."
}

function Read-WorkerPerfApps([string]$Path) {
    # Reads the application list and checks it: version; apps, each with key (letters and digits, once), label and
    # processes (name patterns with wildcards, at least one, each in one application only, compared without regard to
    # case). Further properties of an application are left as they are. Returns the list as read; the first error
    # stops with a message that names application and field.
    $list = ConvertFrom-WorkerPerfJsonFile $Path
    if (-not (Test-WorkerPerfGuidanceObject $list)) { Stop-WorkerPerfApps $Path '' '' 'ist kein JSON-Objekt' }
    $version = Get-WorkerPerfGuidanceMember $list 'version'
    if ($null -eq $version) { Stop-WorkerPerfApps $Path '' 'version' 'fehlt' }
    if ($version.Value -isnot [string]) { Stop-WorkerPerfApps $Path '' 'version' 'ist kein Text' }
    if ([string]::IsNullOrWhiteSpace($version.Value)) { Stop-WorkerPerfApps $Path '' 'version' 'ist leer' }
    $apps = Get-WorkerPerfGuidanceMember $list 'apps'
    if ($null -eq $apps) { Stop-WorkerPerfApps $Path '' 'apps' 'fehlt' }
    if ($apps.Value -isnot [array]) { Stop-WorkerPerfApps $Path '' 'apps' 'ist keine Liste' }
    # ordinal, like the condition app.<key>
    $keys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    # pattern (lower case) -> key of the application that has it
    $owners = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
    $entries = @($apps.Value)
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $app = $entries[$i]; $name = "apps[$i]"
        if (-not (Test-WorkerPerfGuidanceObject $app)) { Stop-WorkerPerfApps $Path $name '' 'ist kein Objekt' }
        $key = Get-WorkerPerfGuidanceMember $app 'key'
        if ($null -eq $key) { Stop-WorkerPerfApps $Path $name 'key' 'fehlt' }
        if ($key.Value -isnot [string]) { Stop-WorkerPerfApps $Path $name 'key' 'ist kein Text' }
        $name = "'" + $key.Value + "'"
        if ($key.Value -cnotmatch '^[A-Za-z0-9]+$') { Stop-WorkerPerfApps $Path $name 'key' 'darf nur Buchstaben und Ziffern enthalten' }
        if (-not $keys.Add($key.Value)) { Stop-WorkerPerfApps $Path $name 'key' 'ist doppelt' }
        $label = Get-WorkerPerfGuidanceMember $app 'label'
        if ($null -eq $label) { Stop-WorkerPerfApps $Path $name 'label' 'fehlt' }
        if ($label.Value -isnot [string]) { Stop-WorkerPerfApps $Path $name 'label' 'ist kein Text' }
        if ([string]::IsNullOrWhiteSpace($label.Value)) { Stop-WorkerPerfApps $Path $name 'label' 'ist leer' }
        $processes = Get-WorkerPerfGuidanceMember $app 'processes'
        if ($null -eq $processes) { Stop-WorkerPerfApps $Path $name 'processes' 'fehlt' }
        if ($processes.Value -isnot [array] -or @($processes.Value).Count -eq 0) { Stop-WorkerPerfApps $Path $name 'processes' 'ist keine Liste mit Mustern' }
        foreach ($p in @($processes.Value)) {
            if ($p -isnot [string] -or [string]::IsNullOrWhiteSpace($p)) { Stop-WorkerPerfApps $Path $name 'processes' 'enthaelt ein leeres Muster' }
            if (-not (Test-WorkerPerfGuidanceWildcard $p)) { Stop-WorkerPerfApps $Path $name 'processes' "enthaelt das ungueltige Muster '$p'" }
            $lower = $p.ToLowerInvariant()
            if ($owners.ContainsKey($lower)) { Stop-WorkerPerfApps $Path $name 'processes' "enthaelt das Muster '$p', das schon bei der Anwendung '$($owners[$lower])' steht" }
            $owners[$lower] = $key.Value
        }
    }
    return $list
}

function Get-WorkerPerfGuidanceAppKeys($Apps) {
    # The keys of the application list (Read-WorkerPerfApps, or the same content as dictionaries), in its order. Plain
    # pipeline output (the caller writes @(...)).
    foreach ($app in (Get-WorkerPerfGuidanceList $Apps 'apps')) {
        $key = [string](Get-WorkerPerfField $app 'key')
        if ($key) { $key }
    }
}

function Get-WorkerPerfGuidanceAppMatches($Apps, [string]$Process) {
    # The keys of the applications of the list with a pattern that matches a process name (wildcards, without regard to
    # case; of a path only the file name), in the order of the list. Plain pipeline output (the caller writes @(...)).
    if (-not $Process) { return }
    $leaf = $Process.Substring($Process.LastIndexOfAny([char[]]@('\', '/')) + 1)
    if (-not $leaf) { return }
    foreach ($app in (Get-WorkerPerfGuidanceList $Apps 'apps')) {
        $key = [string](Get-WorkerPerfField $app 'key')
        if (-not $key) { continue }
        if (@((Get-WorkerPerfGuidanceList $app 'processes') | Where-Object { Test-WorkerPerfAccountPattern $leaf ([string]$_) }).Count -gt 0) { $key }
    }
}

# ---------- situation, conditions and placeholder values of one incident (spec 5.2, 5.4, 5.5) ----------

$script:WorkerPerfGuidanceWorker = @('cpu', 'memory', 'disk', 'share', 'profile')
$script:WorkerPerfGuidanceEventKinds = @('crash', 'hang', 'service', 'print', 'profileerror', 'system')
# the lead resources whose signal label names the resource (drive, share, profile container)
$script:WorkerPerfGuidanceNamedResources = @('disk', 'share', 'profile')
$script:WorkerPerfGuidanceSpoolerApps = @('spoolsv.exe', 'PrintIsolationHost.exe')
# units of a duration: limit in seconds below which the unit is used, seconds per unit, text keys of singular and plural
$script:WorkerPerfGuidanceDurationUnits = @(
    @{ Below = 60; Per = 1; One = 'duration.second'; Many = 'duration.seconds' }
    @{ Below = 3600; Per = 60; One = 'duration.minute'; Many = 'duration.minutes' }
    @{ Below = [double]::PositiveInfinity; Per = 3600; One = 'duration.hour'; Many = 'duration.hours' })

function Get-WorkerPerfGuidanceList($Object, [string]$Name) {
    # A list field of report data (hashtable, ordered dictionary or JSON object) as an array; empty when missing or null.
    $v = Get-WorkerPerfField $Object $Name
    if ($null -eq $v) { return , @() }
    return , @($v)
}

function Test-WorkerPerfGuidanceSame([string]$A, [string]$B) {
    return [string]::Equals($A, $B, [StringComparison]::OrdinalIgnoreCase)
}

function Format-WorkerPerfGuidanceDuration([double]$Seconds, $Texts) {
    # The number in the smallest unit whose written number stays below the next unit (45 s, 2 min, 3,8 min, 1,5 h), and
    # the unit word of Texts (duration.*, singular for 1). The unit is chosen from the number Format-WorkerPerfTextNumber
    # writes, so a duration is never written as 60 of a unit. $null when a word is missing.
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $units = $script:WorkerPerfGuidanceDurationUnits
    for ($k = 0; $k -lt $units.Count; $k++) {
        $u = $units[$k]
        $written = Format-WorkerPerfTextNumber ($Seconds / $u.Per)
        $n = [double]::Parse($written.Replace(',', '.'), $inv)
        if ($k -lt $units.Count - 1 -and $n * $u.Per -ge $u.Below) { continue }
        $key = $u.Many
        if ($written -eq '1') { $key = $u.One }
        $word = [string](Get-WorkerPerfField $Texts $key)
        if (-not $word) { return $null }
        return ($written + ' ' + $word)
    }
}

function Get-WorkerPerfGuidanceLeadSignal($Incident) {
    # The leading signal of a report entry, chosen as Get-WorkerPerfLeadFinding chooses the finding: among the signals of
    # the lead resource (input for a delay without bottleneck, network and endpoint otherwise), the highest severity, then
    # the earliest start; all signals when none of them qualifies.
    $pool = Get-WorkerPerfGuidanceList $Incident 'signals'
    $lead = [string](Get-WorkerPerfField $Incident 'lead')
    if ($lead) { $want = @($lead) }
    elseif ([string](Get-WorkerPerfField $Incident 'type') -eq 'ohne-engpass') { $want = @('input') }
    else { $want = @('network', 'endpoint') }
    $sel = @($pool | Where-Object { $want -contains [string](Get-WorkerPerfField $_ 'resource') })
    if ($sel.Count -gt 0) { $pool = $sel }
    if ($pool.Count -eq 0) { return $null }
    return @($pool | Sort-Object -Property @{ Expression = { [int](Get-WorkerPerfField $_ 'severity') }; Descending = $true },
        @{ Expression = { [long](Get-WorkerPerfField $_ 'start') } })[0]
}

function Get-WorkerPerfSituation($Incident) {
    # The situation of an incident of the report data (spec 5.2); what cannot be assigned is 'fallback'.
    $type = [string](Get-WorkerPerfField $Incident 'type')
    if ($type -eq 'ereignis') {
        $kind = [string](Get-WorkerPerfField (Get-WorkerPerfField $Incident 'event') 'kind')
        if ($script:WorkerPerfGuidanceEventKinds -ccontains $kind) { return $kind }
        return 'fallback'
    }
    if ([bool](Get-WorkerPerfField $Incident 'chronic')) {
        if ($type -eq 'umfeld' -and @((Get-WorkerPerfGuidanceList $Incident 'signals') | Where-Object { [string](Get-WorkerPerfField $_ 'resource') -eq 'network' }).Count -gt 0) {
            return 'chronic.network'
        }
        if ($type -eq 'engpass') { return 'chronic.resource' }
        return 'fallback'
    }
    if ($type -eq 'engpass') {
        $lead = [string](Get-WorkerPerfField $Incident 'lead')
        if ($script:WorkerPerfGuidanceWorker -ccontains $lead) { return $lead }
        return 'fallback'
    }
    if ($type -eq 'ohne-engpass') {
        if ((Get-WorkerPerfGuidanceList $Incident 'affected').Count -ge 2) { return 'delay.many' }
        return 'delay.single'
    }
    return 'fallback'
}

function Get-WorkerPerfGuidanceApp($Apps, [string]$Name, $Index) {
    # The entry of Data.apps by index (main.a) or, without index, by name.
    foreach ($a in $Apps) {
        if ($null -ne $Index) { if ([string](Get-WorkerPerfField $a 'i') -eq [string]$Index) { return $a } }
        elseif ($Name -and (Test-WorkerPerfGuidanceSame ([string](Get-WorkerPerfField $a 'name')) $Name)) { return $a }
    }
    return $null
}

function Get-WorkerPerfGuidanceDriver($Event, $Print) {
    # The driver involved in an event incident: name and its entry of print.drivers (null when the list does not hold it).
    # The driver of a printdriver pattern, else the entry named by event.driver or event.key.
    $drivers = Get-WorkerPerfGuidanceList $Print 'drivers'
    $names = @()
    foreach ($p in (Get-WorkerPerfGuidanceList $Event 'patterns')) {
        if ([string](Get-WorkerPerfField $p 'id') -ne 'printdriver') { continue }
        $n = [string](Get-WorkerPerfField (Get-WorkerPerfField $p 'detail') 'driver')
        if ($n) { $names += $n; break }
    }
    $fromPattern = $names.Count -gt 0
    if (-not $fromPattern) { $names = @(@([string](Get-WorkerPerfField $Event 'driver'), [string](Get-WorkerPerfField $Event 'key')) | Where-Object { $_ }) }
    foreach ($n in $names) {
        foreach ($d in $drivers) {
            if (Test-WorkerPerfGuidanceSame ([string](Get-WorkerPerfField $d 'name')) $n) { return @{ Name = [string](Get-WorkerPerfField $d 'name'); Entry = $d } }
        }
    }
    if ($fromPattern) { return @{ Name = $names[0]; Entry = $null } }
    return $null
}

function Get-WorkerPerfGuidanceFacts($Incident, $Context, $Catalogue) {
    # Situation, conditions (spec 5.4, in the order of its table) and placeholder values (spec 5.5) of one incident of
    # the report data. Context: @{ Data; Thresholds; OffsetMinutes; Texts; Apps } (Texts from Read-WorkerPerfTexts, Apps
    # from Read-WorkerPerfApps; without Apps no condition app.<key> holds). A value the incident does not have is left out.
    $data = Get-WorkerPerfField $Context 'Data'
    $offset = [int](Get-WorkerPerfField $Context 'OffsetMinutes')
    $thresholds = Get-WorkerPerfField $Context 'Thresholds'
    $texts = Get-WorkerPerfField $Context 'Texts'
    $situation = Get-WorkerPerfSituation $Incident
    $type = [string](Get-WorkerPerfField $Incident 'type')
    $ev = Get-WorkerPerfField $Incident 'event'
    $isEvent = $type -eq 'ereignis' -and $null -ne $ev
    $cause = Get-WorkerPerfField $Incident 'cause'
    $causeKind = [string](Get-WorkerPerfField $cause 'kind')
    $main = Get-WorkerPerfField $Incident 'main'
    $companion = Get-WorkerPerfField $Incident 'companion'
    $events = Get-WorkerPerfGuidanceList $Incident 'events'
    $apps = Get-WorkerPerfGuidanceList $data 'apps'
    $print = Get-WorkerPerfField $data 'print'
    $c = New-Object System.Collections.Generic.List[string]
    $v = @{}

    # cause, scan, companion, role
    $causeCondition = @{ main = 'cause.app'; security = 'cause.security'; none = 'cause.none'; nodata = 'cause.nodata'; notmeasured = 'cause.notmeasured' }
    if ($causeCondition.ContainsKey($causeKind)) { $c.Add($causeCondition[$causeKind]) }
    if ([bool](Get-WorkerPerfField $Incident 'scanActive')) { $c.Add('scan') }
    if ($null -ne $companion) { $c.Add('companion.security') }
    $app = $null
    if ($isEvent) {
        $name = [string](Get-WorkerPerfField $ev 'app')
        if ($name) { $app = Get-WorkerPerfGuidanceApp $apps $name $null }
    }
    elseif ($causeKind -eq 'main' -and $null -ne $main -and $null -ne (Get-WorkerPerfField $main 'a')) { $app = Get-WorkerPerfGuidanceApp $apps '' (Get-WorkerPerfField $main 'a') }
    $role = [string](Get-WorkerPerfField $app 'role')
    if ($role) { $c.Add('role.' + $role) }
    # the standard application (apps.json) of the process that is the main cause, or of the event's application
    $process = ''
    if ($isEvent) { $process = [string](Get-WorkerPerfField $ev 'app') }
    elseif ($causeKind -eq 'main') { $process = [string](Get-WorkerPerfField $main 'app') }
    foreach ($key in @(Get-WorkerPerfGuidanceAppMatches (Get-WorkerPerfField $Context 'Apps') $process)) { $c.Add('app.' + $key) }

    # endpoints in the window
    $endpoints = Get-WorkerPerfGuidanceList $Incident 'endpoints'
    $warn = $null
    $connect = Get-WorkerPerfField (Get-WorkerPerfField $thresholds 'probe.connect') 'warn'
    if ($null -ne $connect) { $warn = [double]$connect }
    $slow = @($endpoints | Where-Object { [bool](Get-WorkerPerfField $_ 'failed') -or ($null -ne $warn -and [double](Get-WorkerPerfField $_ 'maxMs') -ge $warn) })
    if ($slow.Count -gt 0) { $c.Add('endpoint.slow') }

    # events in the window
    if (@($events | Where-Object { [string](Get-WorkerPerfField $_ 'kind') -eq 'applocker-block' }).Count -gt 0) { $c.Add('event.applocker') }
    if (@($events | Where-Object { [string](Get-WorkerPerfField $_ 'log') -eq 'defender' }).Count -gt 0) { $c.Add('event.defender') }

    # unmeasured signals, skipped categories
    foreach ($row in (Get-WorkerPerfGuidanceList $data 'sollIst')) {
        $m = Get-WorkerPerfField $row 'measured'
        if ($null -ne $m -and -not [bool]$m) { $c.Add('unmeasured.' + [string](Get-WorkerPerfField $row 'id')) }
    }
    foreach ($s in (Get-WorkerPerfGuidanceList $data 'skipped')) { $c.Add('skipped.' + [string](Get-WorkerPerfField $s 'id')) }

    # affected sessions
    $unchecked = Get-WorkerPerfGuidanceList $ev 'unchecked'
    if ($isEvent) {
        $n = (Get-WorkerPerfGuidanceList $ev 'sessions').Count
        $unknown = $n -eq 0 -and ([bool](Get-WorkerPerfField $ev 'sessionUnknown') -or
            @($unchecked | Where-Object { [string](Get-WorkerPerfField $_ 'id') -eq 'users' }).Count -gt 0)
    }
    else {
        $n = (Get-WorkerPerfGuidanceList $Incident 'affected').Count
        $unknown = $n -eq 0 -and [bool](Get-WorkerPerfField (Get-WorkerPerfField $data 'unmeasured') 'input')
    }
    if ($n -ge 2) { $c.Add('affected.many') }
    elseif ($n -eq 1) { $c.Add('affected.one') }
    elseif ($unknown) { $c.Add('affected.unknown') }
    # a lookback incident cannot map its users to sessions: no number then ('0' would read as nobody)
    $lookbackNoSessions = $isEvent -and $n -eq 0 -and [bool](Get-WorkerPerfField $ev 'before')
    if (-not $unknown -and -not $lookbackNoSessions) { $v['affected'] = [string]$n }

    if ([bool](Get-WorkerPerfField $Incident 'chronic')) { $c.Add('chronic') }
    # the lead resource of a bottleneck, chronic or not (the chronic state of every resource shares one situation)
    $leadResource = [string](Get-WorkerPerfField $Incident 'lead')
    if ($type -eq 'engpass' -and $script:WorkerPerfGuidanceWorker -ccontains $leadResource) { $c.Add('lead.' + $leadResource) }
    if ([bool](Get-WorkerPerfField $Incident 'unverified')) { $c.Add('incident.unverified') }

    # patterns, driver, spooler and queues of an event incident
    $driver = $null
    if ($isEvent) {
        $patterns = Get-WorkerPerfGuidanceList $ev 'patterns'
        foreach ($p in $patterns) { $c.Add('pattern.' + [string](Get-WorkerPerfField $p 'id')) }
        if ($patterns.Count -eq 0 -and $unchecked.Count -eq 0) { $c.Add('pattern.none') }
        if ($unchecked.Count -gt 0) { $c.Add('pattern.unchecked') }
        $driver = Get-WorkerPerfGuidanceDriver $ev $print
        if ($null -ne $driver -and $null -ne $driver.Entry) {
            $d = $driver.Entry
            $dt = [string](Get-WorkerPerfField $d 'type')
            if ($dt -eq '3') { $c.Add('driver.v3') } elseif ($dt -eq '4') { $c.Add('driver.v4') }
            $iso = [string](Get-WorkerPerfField $d 'isolation')
            if ($iso -eq 'none' -or $iso -eq 'shared') { $c.Add('driver.shared') } elseif ($iso -eq 'isolated') { $c.Add('driver.isolated') }
            $maker = [string](Get-WorkerPerfField $d 'manufacturer')
            if ($maker) {
                foreach ($vendor in (Get-WorkerPerfGuidanceList $Catalogue 'vendors')) {
                    $hit = @((Get-WorkerPerfGuidanceList $vendor 'match') | Where-Object { Test-WorkerPerfAccountPattern $maker ([string]$_) }).Count -gt 0
                    if ($hit) { $c.Add('driver.vendor.' + [string](Get-WorkerPerfField $vendor 'key')) }
                }
            }
        }
        if ($situation -eq 'print') {
            $spooler = @($events | Where-Object {
                    $a = [string](Get-WorkerPerfField $_ 'app')
                    @($script:WorkerPerfGuidanceSpoolerApps | Where-Object { Test-WorkerPerfGuidanceSame $_ $a }).Count -gt 0 -or
                    (Test-WorkerPerfGuidanceSame ([string](Get-WorkerPerfField $_ 'service')) 'Spooler') })
            if ($spooler.Count -gt 0) { $c.Add('spooler.crash') }
            $stuck = @((Get-WorkerPerfGuidanceList $print 'queues') | Where-Object {
                    [double](Get-WorkerPerfField $_ 'jobErrors') -gt 0 -or [double](Get-WorkerPerfField $_ 'notReadyErrors') -gt 0 })
            if ($stuck.Count -gt 0) { $c.Add('queue.stuck') }
        }
        if ([bool](Get-WorkerPerfField $ev 'before')) { $c.Add('before') }
    }

    # values: cause
    $who = $null
    if ($causeKind -eq 'main') { $who = $main } elseif ($causeKind -eq 'security') { $who = Get-WorkerPerfField $cause 'other' }
    if ($null -ne $who) {
        foreach ($k in 'user', 'app') { $t = [string](Get-WorkerPerfField $who $k); if ($t) { $v[$k] = $t } }
        $pct = Get-WorkerPerfField $who 'sharePct'; if ($null -ne $pct) { $v['share'] = (Format-WorkerPerfTextNumber ([double]$pct)) + ' %' }
        $pct = Get-WorkerPerfField $who 'baselinePct'; if ($null -ne $pct) { $v['baseline'] = (Format-WorkerPerfTextNumber ([double]$pct)) + ' %' }
    }
    $label = [string](Get-WorkerPerfField (Get-WorkerPerfField $cause 'security') 'label')
    if (-not $label) { $label = [string](Get-WorkerPerfField $companion 'label') }
    if ($label) { $v['security'] = $label }

    # values: leading signal
    $sig = Get-WorkerPerfGuidanceLeadSignal $Incident
    if ($null -ne $sig) {
        $peak = Get-WorkerPerfField $sig 'peak'
        if ($null -ne $peak) { $v['value'] = Format-WorkerPerfValue ([double]$peak) ([string](Get-WorkerPerfField $sig 'unit')) }
        $t = [string](Get-WorkerPerfField $sig 'ideal'); if ($t) { $v['target'] = $t }
        if ($script:WorkerPerfGuidanceNamedResources -ccontains [string](Get-WorkerPerfField $Incident 'lead')) {
            $t = [string](Get-WorkerPerfField $sig 'label'); if ($t) { $v['resource'] = $t }
        }
    }

    # values: time; an event incident uses the UTC offset of its first and last record (events[] keeps both), as its own
    # sentence does: a lookback can cross the end of daylight-saving time
    $startOffset = $offset; $endOffset = $offset
    if ($isEvent -and $events.Count -gt 0) {
        $o = Get-WorkerPerfField $events[0] 'offsetMin'; if ($null -ne $o) { $startOffset = [int]$o }
        $o = Get-WorkerPerfField $events[$events.Count - 1] 'offsetMin'; if ($null -ne $o) { $endOffset = [int]$o }
    }
    $start = Get-WorkerPerfField $Incident 'start'; $end = Get-WorkerPerfField $Incident 'end'
    if ($null -ne $start) {
        # 'HH:mm': the clock time of Format-WorkerPerfClock ('HH:mm:ss') without seconds
        $v['from'] = (Format-WorkerPerfClock ([long]$start) $startOffset).Substring(0, 5)
        $v['date'] = Format-WorkerPerfEventDate ([long]$start) $startOffset
    }
    if ($null -ne $end) { $v['to'] = (Format-WorkerPerfClock ([long]$end) $endOffset).Substring(0, 5) }
    if ($null -ne $start -and $null -ne $end -and [long]$end -gt [long]$start) {
        $t = Format-WorkerPerfGuidanceDuration (([long]$end - [long]$start) / 1000.0) $texts
        if ($t) { $v['duration'] = $t }
    }

    # values: slowest endpoint (a failed one first)
    if ($endpoints.Count -gt 0) {
        $e = @($endpoints | Sort-Object -Property @{ Expression = { [bool](Get-WorkerPerfField $_ 'failed') }; Descending = $true },
            @{ Expression = { [double](Get-WorkerPerfField $_ 'maxMs') }; Descending = $true })[0]
        $t = [string](Get-WorkerPerfField $e 'name')
        if ($t) {
            $v['endpoint'] = $t
            $ms = Get-WorkerPerfField $e 'maxMs'; if ($null -ne $ms) { $v['endpointValue'] = Format-WorkerPerfValue ([double]$ms) 'ms' }
        }
    }

    # values: event incident
    if ($isEvent) {
        $t = [string](Get-WorkerPerfField $ev 'app'); if ($t) { $v['app'] = $t }
        $users = Get-WorkerPerfGuidanceList $ev 'users'
        if ($users.Count -eq 1 -and [string]$users[0]) { $v['user'] = [string]$users[0] }
        $top = $null
        foreach ($m in (Get-WorkerPerfGuidanceList $ev 'modules')) { if ($null -eq $top -or [int](Get-WorkerPerfField $m 'count') -gt [int](Get-WorkerPerfField $top 'count')) { $top = $m } }
        $t = [string](Get-WorkerPerfField $top 'name'); if ($t) { $v['module'] = $t }
        if ($null -ne $driver -and $driver.Name) { $v['driver'] = $driver.Name }
        $count = Get-WorkerPerfField $ev 'count'; if ($null -ne $count) { $v['count'] = [string][int]$count }
    }
    $t = [string](Get-WorkerPerfField (Get-WorkerPerfField $data 'meta') 'computer'); if ($t) { $v['server'] = $t }

    return @{ Situation = $situation; Conditions = [string[]]$c.ToArray(); Values = $v }
}

# ---------- the guidance of one incident (spec 4, 5.3 to 5.6) ----------

# list of a situation -> fields of its elements in the guidance (source is optional in the catalogue)
$script:WorkerPerfGuidanceOutputFields = [ordered]@{
    'checks'   = @('text', 'where', 'sign', 'source')
    'remedies' = @('text', 'precondition', 'source')
    'contacts' = @('text', 'source')
}

function Format-WorkerPerfGuidanceText([string]$Template, [System.Collections.IDictionary]$Values) {
    # Replaces every placeholder {name} in one pass: an inserted value is not read again, so braces or markup in a value
    # stay as they are. $null when a placeholder has no value (or an empty one); the report shows no text with a gap.
    # most texts hold no placeholder: no evaluator for them
    if ($Template.IndexOf('{') -lt 0) { return $Template }
    $state = @{ Missing = $false }
    $evaluator = {
        param($m)
        $name = $m.Groups[1].Value
        $value = $null
        if ($null -ne $Values -and $Values.Contains($name)) { $value = [string]$Values[$name] }
        if ([string]::IsNullOrEmpty($value)) { $state.Missing = $true; return '' }
        return $value
    }
    $text = [regex]::Replace($Template, '\{(\w+)\}', [System.Text.RegularExpressions.MatchEvaluator]$evaluator)
    if ($state.Missing) { return $null }
    return $text
}

function Test-WorkerPerfGuidanceGapCondition([string]$Name) {
    # Whether a condition only names a gap: a signal that was not measured, a category left out, a cause that was not
    # measured, a pattern that was not checked, a delay whose bottleneck check was incomplete.
    if ($script:WorkerPerfGuidanceGapConditions -ccontains $Name) { return $true }
    foreach ($prefix in $script:WorkerPerfGuidanceGapPrefixes) { if ($Name.StartsWith($prefix, [StringComparison]::Ordinal)) { return $true } }
    return $false
}

function Test-WorkerPerfGuidanceTrailingCondition([string]$Name) {
    # Whether a condition gives an element no place before the general ones: it only names a gap, or only a coincidence
    # in time with another incident.
    return ((Test-WorkerPerfGuidanceGapCondition $Name) -or ($script:WorkerPerfGuidanceCoincidenceConditions -ccontains $Name))
}

function Get-WorkerPerfGuidanceItems($Entry, [string]$ListName, [string[]]$Conditions, [hashtable]$Values, $Templates) {
    # The elements of one list of a catalogue entry that the facts support: every condition of 'when' holds and every
    # text can be filled. Three groups, the order of the file within each: first the elements with a condition that
    # says more than a gap or a coincidence in time, then the general ones, last those whose conditions all name a gap
    # or a coincidence in time (what is unknown, or merely happened at the same time, is not the first thing to do).
    # Plain pipeline output (the caller writes @(...)). Templates (a List[string]) receives the templates of the texts
    # of the elements emitted (not their sources), for the glossary.
    $withCondition = New-Object System.Collections.Generic.List[object]
    $general = New-Object System.Collections.Generic.List[object]
    $trailing = New-Object System.Collections.Generic.List[object]
    $fields = $script:WorkerPerfGuidanceOutputFields[$ListName]
    foreach ($el in (Get-WorkerPerfGuidanceList $Entry $ListName)) {
        $when = Get-WorkerPerfGuidanceList $el 'when'
        $holds = $true
        foreach ($n in $when) { if ($Conditions -cnotcontains [string]$n) { $holds = $false; break } }
        if (-not $holds) { continue }
        $item = [ordered]@{}
        $used = @()
        $complete = $true
        foreach ($f in $fields) {
            $template = Get-WorkerPerfField $el $f
            if ($null -eq $template) { $item[$f] = $null; continue }
            $text = Format-WorkerPerfGuidanceText ([string]$template) $Values
            if ($null -eq $text) { $complete = $false; break }
            $item[$f] = $text
            if ($f -ne 'source') { $used += [string]$template }
        }
        if (-not $complete) { continue }
        if ($null -ne $Templates) { foreach ($t in $used) { $Templates.Add($t) } }
        if ($when.Count -eq 0) { $general.Add($item) }
        elseif (@($when | Where-Object { -not (Test-WorkerPerfGuidanceTrailingCondition ([string]$_)) }).Count -eq 0) { $trailing.Add($item) }
        else { $withCondition.Add($item) }
    }
    foreach ($item in $withCondition) { $item }
    foreach ($item in $general) { $item }
    foreach ($item in $trailing) { $item }
}

function Get-WorkerPerfGuidanceTech($Incident, $Texts) {
    # The technical name of an incident: type and lead resource or kind of event, joined with tech.separator (all words
    # from texts.de.json).
    # A delay whose bottleneck check was incomplete never reads "without bottleneck".
    $type = [string](Get-WorkerPerfField $Incident 'type')
    $parts = New-Object System.Collections.Generic.List[string]
    if ($type -ne 'ereignis' -and [bool](Get-WorkerPerfField $Incident 'chronic')) { $parts.Add([string](Get-WorkerPerfField $Texts 'type.chronic')) }
    $typeKey = 'type.' + $type
    if ($type -eq 'ohne-engpass' -and [bool](Get-WorkerPerfField $Incident 'unverified')) { $typeKey = 'type.ohne-engpass.unverified' }
    $parts.Add([string](Get-WorkerPerfField $Texts $typeKey))
    if ($type -eq 'ereignis') { $parts.Add([string](Get-WorkerPerfField $Texts ('kind.' + [string](Get-WorkerPerfField (Get-WorkerPerfField $Incident 'event') 'kind')))) }
    else {
        $lead = [string](Get-WorkerPerfField $Incident 'lead')
        if ($lead) { $parts.Add([string](Get-WorkerPerfField $Texts ('resource.' + $lead))) }
    }
    return (@($parts | Where-Object { $_ }) -join [string](Get-WorkerPerfField $Texts 'tech.separator'))
}

function Get-WorkerPerfGuidanceUserView($Catalogue, $Incident, [string[]]$Conditions, [hashtable]$Values, $Templates) {
    # The sentence of the user's view: before, chronic, then the number of affected sessions of an event or performance
    # incident. A text whose placeholders cannot be filled gives userView.unknown. Templates (a List[string]) receives
    # the template of the sentence returned.
    $isEvent = [string](Get-WorkerPerfField $Incident 'type') -eq 'ereignis'
    if ($Conditions -ccontains 'before') { $key = 'before' }
    elseif ($Conditions -ccontains 'chronic') { $key = 'chronic' }
    elseif ($Conditions -ccontains 'affected.many') { $key = if ($isEvent) { 'eventMany' } else { 'many' } }
    elseif ($Conditions -ccontains 'affected.one') { $key = if ($isEvent) { 'eventOne' } else { 'one' } }
    elseif ($Conditions -ccontains 'affected.unknown') { $key = 'unknown' }
    else { $key = if ($isEvent) { 'eventNone' } else { 'none' } }
    $views = Get-WorkerPerfField $Catalogue 'userView'
    $text = $null
    $template = Get-WorkerPerfField $views $key
    if ($null -ne $template) { $text = Format-WorkerPerfGuidanceText ([string]$template) $Values }
    if ($null -eq $text -and $key -ne 'unknown') {
        $template = Get-WorkerPerfField $views 'unknown'
        if ($null -ne $template) { $text = Format-WorkerPerfGuidanceText ([string]$template) $Values }
    }
    if ($null -ne $text -and $null -ne $Templates) { $Templates.Add([string]$template) }
    return $text
}

function New-WorkerPerfGuidance($Catalogue, $Facts, $Incident, $Texts) {
    # The guidance of one incident: the catalogue entry of its situation (the fallback entry, marked, when the catalogue
    # has none), filled with the values of the facts (Get-WorkerPerfGuidanceFacts), with only the elements the facts
    # support, its technical name (Texts: Read-WorkerPerfTexts), the user's view and the terms used in its texts. The
    # impact is the situation's impact, or the first of its impactVariants whose conditions all hold.
    $situation = [string](Get-WorkerPerfField $Facts 'Situation')
    $conditions = [string[]](Get-WorkerPerfGuidanceList $Facts 'Conditions')
    # Values: a hashtable or any other dictionary (an ordered one gives the same result)
    $given = Get-WorkerPerfField $Facts 'Values'
    $values = @{}
    if ($given -is [System.Collections.IDictionary]) { foreach ($k in $given.Keys) { $values[[string]$k] = $given[$k] } }
    $situations = Get-WorkerPerfField $Catalogue 'situations'
    $entry = $null
    if ($situation) { $entry = Get-WorkerPerfField $situations $situation }
    if ($null -eq $entry -or $situation -eq 'fallback') { $situation = 'fallback'; $entry = Get-WorkerPerfField $situations 'fallback' }
    $isFallback = $situation -eq 'fallback'

    # the templates of the texts shown (title, meaning, impact, userView, the texts of the elements), for the glossary
    $templates = New-Object System.Collections.Generic.List[string]
    $filled = @{}
    foreach ($f in 'title', 'meaning', 'impact', 'short') {
        $filled[$f] = $null
        $template = Get-WorkerPerfField $entry $f
        # the impact in the first other wording whose conditions all hold (impactVariants), else as it stands
        if ($f -eq 'impact') {
            foreach ($variant in (Get-WorkerPerfGuidanceList $entry 'impactVariants')) {
                $when = Get-WorkerPerfGuidanceList $variant 'when'
                if ($when.Count -eq 0 -or @($when | Where-Object { $conditions -cnotcontains [string]$_ }).Count -gt 0) { continue }
                $other = Get-WorkerPerfField $variant 'text'
                if ($null -ne $other -and $null -ne (Format-WorkerPerfGuidanceText ([string]$other) $values)) { $template = $other; break }
            }
        }
        if ($null -ne $template) { $filled[$f] = Format-WorkerPerfGuidanceText ([string]$template) $values }
        if ($f -ne 'short' -and $null -ne $filled[$f]) { $templates.Add([string]$template) }
    }
    if ($isFallback) {
        $template = Get-WorkerPerfField $Catalogue 'fallbackNote'
        $note = $null
        if ($null -ne $template) { $note = Format-WorkerPerfGuidanceText ([string]$template) $values }
        if ($null -ne $note) { $templates.Add([string]$template) }
        $meaning = (@($note, $filled['meaning']) | Where-Object { $_ }) -join ' '
        # one shape for "no text": $null, as for the other fields
        if ($meaning) { $filled['meaning'] = $meaning } else { $filled['meaning'] = $null }
    }

    $g = [ordered]@{
        situation  = $situation
        fallback   = $isFallback
        title      = $filled['title']
        tech       = Get-WorkerPerfGuidanceTech $Incident $Texts
        meaning    = $filled['meaning']
        impact     = $filled['impact']
        userView   = Get-WorkerPerfGuidanceUserView $Catalogue $Incident $conditions $values $templates
        checks     = @(Get-WorkerPerfGuidanceItems $entry 'checks' $conditions $values $templates)
        remedies   = @(Get-WorkerPerfGuidanceItems $entry 'remedies' $conditions $values $templates)
        contacts   = @(Get-WorkerPerfGuidanceItems $entry 'contacts' $conditions $values $templates)
        short      = $filled['short']
        terms      = @()
        conditions = $conditions
    }

    # a term is listed when it starts a word of a template shown, with any ending (German inflects and compounds), not
    # inside a word and not in an inserted value: the placeholders are taken out of the templates first (ruling P3-R20)
    $haystack = [regex]::Replace(($templates.ToArray() -join "`n"), '\{\w+\}', "`n")
    $terms = Get-WorkerPerfField $Catalogue 'terms'
    $found = New-Object System.Collections.Generic.List[string]
    if (Test-WorkerPerfGuidanceObject $terms) { $names = @($terms.PSObject.Properties | ForEach-Object { $_.Name }) }
    elseif ($terms -is [System.Collections.IDictionary]) { $names = @($terms.Keys) }
    else { $names = @() }
    $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    foreach ($n in $names) {
        if ([regex]::IsMatch($haystack, '(?<![\p{L}\p{N}])' + [regex]::Escape([string]$n), $options)) { $found.Add([string]$n) }
    }
    $g['terms'] = @($found.ToArray())
    return $g
}

# ---------- ranking, groups and the situation summary of the capture (spec 3.1, 8) ----------

# the symbol and word of a state (state.<state>.symbol / .word) and the words of a group label (group.times, group.by,
# group.of, group.at) come from the texts (texts.de.json, ruling P3-R27)
$script:WorkerPerfGuidanceNoCause = @('none', 'nodata', 'notmeasured')

function Get-WorkerPerfGuidanceWord($Texts, [string]$Key) {
    # A text of texts.de.json the guidance cannot do without; a missing or empty one stops with its key.
    $t = [string](Get-WorkerPerfField $Texts $Key)
    if (-not $t) { throw "The texts have no '$Key'." }
    return $t
}

function Format-WorkerPerfGuidanceWord($Texts, [string]$Key, [object[]]$Values) {
    # A text of texts.de.json with its numbered places {0}, {1} filled (independent of the installed culture).
    return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, (Get-WorkerPerfGuidanceWord $Texts $Key), $Values)
}

function Get-WorkerPerfGuidanceSessionCount($Incident) {
    # The number of affected sessions: event.sessions of an event incident, affected of a performance incident.
    if ([string](Get-WorkerPerfField $Incident 'type') -eq 'ereignis') { return (Get-WorkerPerfGuidanceList (Get-WorkerPerfField $Incident 'event') 'sessions').Count }
    return (Get-WorkerPerfGuidanceList $Incident 'affected').Count
}

function Get-WorkerPerfGuidanceSpan($Incident) {
    # Start and end in ms (end never before start); $null without a start or an end.
    $start = Get-WorkerPerfField $Incident 'start'; $end = Get-WorkerPerfField $Incident 'end'
    if ($null -eq $start -or $null -eq $end) { return $null }
    $s = [long]$start; $e = [long]$end
    if ($e -lt $s) { $e = $s }
    return @{ Start = $s; End = $e }
}

function Get-WorkerPerfGuidanceRankClass($Incident) {
    # 0: no chronic state and a bottleneck, a critical delay (severity 2) or an event incident; 1: the other incidents
    # without chronic state; 2: chronic states.
    if ([bool](Get-WorkerPerfField $Incident 'chronic')) { return 2 }
    $type = [string](Get-WorkerPerfField $Incident 'type')
    if ($type -eq 'engpass' -or $type -eq 'ereignis') { return 0 }
    if ($type -eq 'ohne-engpass' -and [int](Get-WorkerPerfField $Incident 'severity') -eq 2) { return 0 }
    return 1
}

function Test-WorkerPerfGuidanceSessionUnknown($Incident) {
    # Whether an event incident cannot be assigned to sessions: event.sessionUnknown, or users among the unchecked patterns.
    if ([string](Get-WorkerPerfField $Incident 'type') -ne 'ereignis') { return $false }
    $ev = Get-WorkerPerfField $Incident 'event'
    if ([bool](Get-WorkerPerfField $ev 'sessionUnknown')) { return $true }
    return (@((Get-WorkerPerfGuidanceList $ev 'unchecked') | Where-Object { [string](Get-WorkerPerfField $_ 'id') -eq 'users' }).Count -gt 0)
}

function Get-WorkerPerfIncidentRanking {
    # The ids of the incidents, most important first (spec 3.1): by class (Get-WorkerPerfGuidanceRankClass), within a
    # class an event incident without known sessions below the others, then affected sessions descending, duration
    # descending, start ascending, id ascending. Plain pipeline output (the caller writes @(...)).
    param([object[]]$Incidents = @())
    $rows = foreach ($inc in @($Incidents)) {
        if ($null -eq $inc) { continue }
        $span = Get-WorkerPerfGuidanceSpan $inc
        $dur = 0L; $start = 0L
        if ($null -ne $span) { $dur = $span.End - $span.Start; $start = $span.Start }
        elseif ($null -ne (Get-WorkerPerfField $inc 'start')) { $start = [long](Get-WorkerPerfField $inc 'start') }
        [pscustomobject]@{ Id = [int](Get-WorkerPerfField $inc 'id'); Class = (Get-WorkerPerfGuidanceRankClass $inc)
            Unknown = [int](Test-WorkerPerfGuidanceSessionUnknown $inc); Sessions = (Get-WorkerPerfGuidanceSessionCount $inc); Duration = $dur; Start = $start }
    }
    $sorted = @($rows | Sort-Object -Property @{ Expression = { $_.Class } }, @{ Expression = { $_.Unknown } },
        @{ Expression = { $_.Sessions }; Descending = $true }, @{ Expression = { $_.Duration }; Descending = $true },
        @{ Expression = { $_.Start } }, @{ Expression = { $_.Id } })
    foreach ($r in $sorted) { $r.Id }
}

function Get-WorkerPerfGuidanceCause($Incident) {
    # The cause of an incident for grouping: event.key of an event incident, main.app and main.user of a performance
    # incident; empty when the cause kind says there is no main consumer (none, nodata, notmeasured) or main is missing.
    if ([string](Get-WorkerPerfField $Incident 'type') -eq 'ereignis') {
        return @{ Key = [string](Get-WorkerPerfField (Get-WorkerPerfField $Incident 'event') 'key'); App = ''; User = '' }
    }
    $kind = [string](Get-WorkerPerfField (Get-WorkerPerfField $Incident 'cause') 'kind')
    if ($script:WorkerPerfGuidanceNoCause -contains $kind) { return @{ Key = ''; App = ''; User = '' } }
    $main = Get-WorkerPerfField $Incident 'main'
    return @{ Key = ''; App = [string](Get-WorkerPerfField $main 'app'); User = [string](Get-WorkerPerfField $main 'user') }
}

function Get-WorkerPerfIncidentGroups {
    # The incidents after the first Cards of Order (spec 8): incidents of the same situation (guide.situation) and the
    # same cause (Get-WorkerPerfGuidanceCause) form one group, in the order of their first incident; ids in rank order.
    # Label of several: the text group.times (number, guide.title) with group.by (main.app, of an event incident
    # event.key) and group.of (main.user) where the cause names them; of one: group.at (guide.title, start as HH:mm in
    # the server's time: OffsetMinutes, an event incident the offset of its first record). An id that occurs twice in Order is used once. Texts: Read-WorkerPerfTexts. Plain pipeline output (the
    # caller writes @(...)).
    param([object[]]$Incidents = @(), [int[]]$Order = @(), [int]$Cards = 10,
        [Parameter(Mandatory = $true)][int]$OffsetMinutes, [Parameter(Mandatory = $true)]$Texts)
    $byId = @{}
    foreach ($inc in @($Incidents)) { if ($null -ne $inc) { $byId[[int](Get-WorkerPerfField $inc 'id')] = $inc } }
    $groups = New-Object System.Collections.Generic.List[object]
    $index = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
    $ids = New-Object System.Collections.Generic.List[int]
    foreach ($id in @($Order)) { if (-not $ids.Contains([int]$id)) { $ids.Add([int]$id) } }
    for ($n = [Math]::Max(0, $Cards); $n -lt $ids.Count; $n++) {
        $id = [int]$ids[$n]
        if (-not $byId.ContainsKey($id)) { throw "Get-WorkerPerfIncidentGroups: id $id of the order is not among the incidents." }
        $inc = $byId[$id]
        $guide = Get-WorkerPerfField $inc 'guide'
        $situation = [string](Get-WorkerPerfField $guide 'situation')
        $cause = Get-WorkerPerfGuidanceCause $inc
        $key = $situation + "`n" + $cause.Key + "`n" + $cause.App + "`n" + $cause.User
        if (-not $index.ContainsKey($key)) {
            $g = @{ Situation = $situation; Title = [string](Get-WorkerPerfField $guide 'title'); Cause = $cause; First = $inc
                Ids = (New-Object System.Collections.Generic.List[object]) }
            $index[$key] = $g; $groups.Add($g)
        }
        $index[$key].Ids.Add($id)
    }
    foreach ($g in $groups) {
        if ($g.Ids.Count -gt 1) {
            $label = Format-WorkerPerfGuidanceWord $Texts 'group.times' @($g.Ids.Count, $g.Title)
            $by = $g.Cause.Key; if (-not $by) { $by = $g.Cause.App }
            if ($by) { $label += Format-WorkerPerfGuidanceWord $Texts 'group.by' @($by) }
            if ($g.Cause.User) { $label += Format-WorkerPerfGuidanceWord $Texts 'group.of' @($g.Cause.User) }
        }
        else {
            $label = $g.Title
            $start = Get-WorkerPerfField $g.First 'start'
            if ($null -ne $start) {
                $offset = $OffsetMinutes
                $records = Get-WorkerPerfGuidanceList $g.First 'events'
                if ([string](Get-WorkerPerfField $g.First 'type') -eq 'ereignis' -and $records.Count -gt 0) {
                    $o = Get-WorkerPerfField $records[0] 'offsetMin'; if ($null -ne $o) { $offset = [int]$o }
                }
                $label = Format-WorkerPerfGuidanceWord $Texts 'group.at' @($g.Title, (Format-WorkerPerfClock ([long]$start) $offset).Substring(0, 5))
            }
        }
        [ordered]@{ label = $label; situation = $g.Situation; ids = $g.Ids.ToArray() }
    }
}

function Format-WorkerPerfGuidancePart($Catalogue, [string]$Part, [string]$Key, [hashtable]$Values) {
    # A text of a catalogue part outside the situations (lagebild, hints, copy, userView) filled with Values; a
    # placeholder without a value is an error of the caller: it stops with the name of the text and the placeholder.
    $template = Get-WorkerPerfField (Get-WorkerPerfField $Catalogue $Part) $Key
    if ($null -eq $template) { throw "Catalogue text '$Part.$Key' is missing." }
    $text = Format-WorkerPerfGuidanceText ([string]$template) $Values
    if ($null -ne $text) { return $text }
    foreach ($m in [regex]::Matches([string]$template, '\{(\w+)\}')) {
        $name = $m.Groups[1].Value
        if (-not $Values.ContainsKey($name) -or [string]::IsNullOrEmpty([string]$Values[$name])) {
            throw "Catalogue text '$Part.$Key' has no value for the placeholder '{$name}'."
        }
    }
    throw "Catalogue text '$Part.$Key' could not be filled."
}

# The parts of the red and the yellow sentence of the Lagebild, in their order: the catalogue text (lagebild.<Key>), the
# value it names (Value: the placeholder of its count), the place of the report data whose category the count needs
# (skipped[].places: 'events' as for the key figure of the page; a chronic state of the connection needs the ICA values,
# 'citrix') and the states whose sentence lists the part (the yellow sentence says in its lead-in that there is no
# bottleneck).
$script:WorkerPerfLagebildParts = @(
    @{ Key = 'partBottlenecks'; Value = 'bottlenecks'; Place = ''; States = @('red') }
    @{ Key = 'partDelays'; Value = 'delays'; Place = ''; States = @('red', 'yellow') }
    @{ Key = 'partEvents'; Value = 'events'; Place = 'events'; States = @('red', 'yellow') }
    @{ Key = 'partChronic'; Value = 'chronic'; Place = 'citrix'; States = @('red', 'yellow') })

function Get-WorkerPerfLagebild {
    # The situation summary of the capture (spec 3.1): state with symbol and word, sentence (catalogue part lagebild),
    # key figures, hints on the capture (catalogue part hints) and the id of the most important incident. The red and
    # the yellow sentence are joined from their parts ($script:WorkerPerfLagebildParts); a part whose count is zero and
    # whose category was left out is not listed (nothing that was not measured counts as zero, ruling P3-R49), and the
    # sentence then ends with the reservation lagebild.notMeasured. A part with a real count stays.
    # Incidents: the capture's incidents only (Data.incidents). Incidents of the lookback (Data.before) count nowhere; the
    # caller does not pass them, and nothing is filtered here. Data: the report data (meta, sollIst, skipped). Texts:
    # Read-WorkerPerfTexts (symbol and word of the state).
    param([object[]]$Incidents = @(), $Data, $Catalogue, [Parameter(Mandatory = $true)]$Texts)
    $list = @(@($Incidents) | Where-Object { $null -ne $_ })
    $bottlenecks = 0; $delays = 0; $unverified = 0; $events = 0; $chronic = 0; $red = $false
    $spans = New-Object System.Collections.Generic.List[object]
    foreach ($inc in $list) {
        $type = [string](Get-WorkerPerfField $inc 'type')
        $isChronic = [bool](Get-WorkerPerfField $inc 'chronic')
        if ($type -eq 'ereignis') {
            $events++
            if ([bool](Get-WorkerPerfField (Get-WorkerPerfField $inc 'event') 'inSession')) { $red = $true }
        }
        elseif ($isChronic) { $chronic++ }
        elseif ($type -eq 'engpass') { $bottlenecks++; $red = $true }
        elseif ($type -eq 'ohne-engpass' -or $type -eq 'umfeld') {
            $delays++
            if ([bool](Get-WorkerPerfField $inc 'unverified')) { $unverified++ }
            if ($type -eq 'ohne-engpass' -and [int](Get-WorkerPerfField $inc 'severity') -eq 2) { $red = $true }
        }
        if (-not $isChronic) { $s = Get-WorkerPerfGuidanceSpan $inc; if ($null -ne $s) { $spans.Add($s) } }
    }

    # the union of the windows: overlapping windows count once, an incident without duration with 0
    $totalMs = 0L; $curStart = $null; $curEnd = $null
    foreach ($s in @($spans.ToArray() | Sort-Object -Property @{ Expression = { $_.Start } })) {
        if ($null -eq $curEnd -or $s.Start -gt $curEnd) {
            if ($null -ne $curEnd) { $totalMs += $curEnd - $curStart }
            $curStart = $s.Start; $curEnd = $s.End
        }
        elseif ($s.End -gt $curEnd) { $curEnd = $s.End }
    }
    if ($null -ne $curEnd) { $totalMs += $curEnd - $curStart }
    $minutes = [Math]::Round($totalMs / 60000.0, 1, [MidpointRounding]::AwayFromZero)

    if ($red) { $state = 'red' } elseif ($list.Count -gt 0) { $state = 'yellow' } else { $state = 'green' }

    # the values of sentence and hints
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $meta = Get-WorkerPerfField $Data 'meta'
    $v = @{ bottlenecks = [string]$bottlenecks; delays = [string]$delays; events = [string]$events; chronic = [string]$chronic
        minutes = $minutes.ToString('0.#', $inv).Replace('.', ','); incidents = [string]$list.Count }
    $t = [string](Get-WorkerPerfField $meta 'computer'); if ($t) { $v['server'] = $t }
    $start = Get-WorkerPerfField $meta 'start'
    if ($null -ne $start) { $v['date'] = Format-WorkerPerfEventDate ([long][double]$start) ([int](Get-WorkerPerfField $meta 'offsetMin')) }
    $skipped = Get-WorkerPerfGuidanceList $Data 'skipped'
    if ($skipped.Count -gt 0) { $v['skipped'] = (@($skipped | ForEach-Object { [string](Get-WorkerPerfField $_ 'label') }) -join ', ') }
    $message = [string](Get-WorkerPerfField $meta 'endMessage'); if ($message) { $v['message'] = $message }
    # a signal missing because its category was skipped is named by the skipped hint only
    $signals = New-Object System.Collections.Generic.List[string]
    foreach ($row in (Get-WorkerPerfGuidanceList $Data 'sollIst')) {
        $m = Get-WorkerPerfField $row 'measured'
        if ($null -eq $m -or [bool]$m) { continue }
        if (Test-WorkerPerfSkipDetail ([string](Get-WorkerPerfField $row 'detail'))) { continue }
        # a row without a label is named by its id: an unmeasured signal never vanishes from the hint
        $label = [string](Get-WorkerPerfField $row 'label')
        if (-not $label) { $label = [string](Get-WorkerPerfField $row 'id') }
        if ($label -and -not $signals.Contains($label)) { $signals.Add($label) }
    }
    if ($signals.Count -gt 0) { $v['signals'] = $signals.ToArray() -join ', ' }

    # the places of the report data that were not measured, as the page reads them for its key figures
    $notMeasured = New-Object System.Collections.Generic.List[string]
    foreach ($s in $skipped) { foreach ($place in (Get-WorkerPerfGuidanceList $s 'places')) { $notMeasured.Add([string]$place) } }
    $sentenceKey = $state
    $reserve = $false
    if ($state -eq 'green') { if ($notMeasured.Contains('events')) { $sentenceKey = 'greenSkipped' } }
    else {
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($part in $script:WorkerPerfLagebildParts) {
            if ($part.States -cnotcontains $state) { continue }
            if ($part.Place -and $notMeasured.Contains($part.Place) -and $v[$part.Value] -eq '0') { $reserve = $true; continue }
            $parts.Add((Format-WorkerPerfGuidancePart $Catalogue 'lagebild' $part.Key $v))
        }
        if ($parts.Count -gt 0) { $v['parts'] = $parts.ToArray() -join (Format-WorkerPerfGuidancePart $Catalogue 'lagebild' 'partSeparator' $v) }
    }
    $sentence = Format-WorkerPerfGuidancePart $Catalogue 'lagebild' $sentenceKey $v
    if ($reserve) { $sentence += ' ' + (Format-WorkerPerfGuidancePart $Catalogue 'lagebild' 'notMeasured' $v) }

    # hints: what was left out on purpose before what could not be measured (ruling P3-R28); duration, interrupted and
    # stopflag give none (ruling P3-R5)
    $hints = New-Object System.Collections.Generic.List[string]
    if ($skipped.Count -gt 0) { $hints.Add((Format-WorkerPerfGuidancePart $Catalogue 'hints' 'skipped' $v)) }
    if ($signals.Count -gt 0) { $hints.Add((Format-WorkerPerfGuidancePart $Catalogue 'hints' 'unmeasured' $v)) }
    $reason = [string](Get-WorkerPerfField $meta 'endReason')
    if (-not $reason) { $hints.Add((Format-WorkerPerfGuidancePart $Catalogue 'hints' 'notFinished' $v)) }
    elseif ($reason -eq 'error') {
        if ($message) { $hints.Add((Format-WorkerPerfGuidancePart $Catalogue 'hints' 'error' $v)) }
        else { $hints.Add((Format-WorkerPerfGuidancePart $Catalogue 'hints' 'errorNoMessage' $v)) }
    }
    elseif ($reason -eq 'diskspace' -or $reason -eq 'maxsize') { $hints.Add((Format-WorkerPerfGuidancePart $Catalogue 'hints' 'stopped' $v)) }

    $order = @(Get-WorkerPerfIncidentRanking -Incidents $list)
    $top = $null; if ($order.Count -gt 0) { $top = $order[0] }
    return [ordered]@{
        state    = $state
        symbol   = Get-WorkerPerfGuidanceWord $Texts "state.$state.symbol"
        word     = Get-WorkerPerfGuidanceWord $Texts "state.$state.word"
        sentence = $sentence
        kpis     = [ordered]@{ bottlenecks = $bottlenecks; delays = $delays; delaysUnverified = $unverified; events = $events; chronic = $chronic; minutes = $minutes }
        hints    = [string[]]$hints.ToArray()
        top      = $top
    }
}

# ---------- plain-text summaries to copy (spec 6) ----------
# The texts are built as unwrapped paragraphs first (Get-WorkerPerfCopyParagraphs, Get-WorkerPerfCopySummaryParagraphs),
# names are replaced per paragraph (-Mask), and wrapping comes last (Format-WorkerPerfCopyLines): a replacement name has
# another length, and a name the wrapper has split is no longer found (ruling P3-R9). German words come from the
# catalogue (copy.*, userView.unknown) and from texts.de.json (Texts); the cause part is the incident's own causeText,
# the part of its sentence on cause and context (ruling P3-R30).

# a paragraph that starts like this indents its continuation lines by the width of that start
$script:WorkerPerfCopyListStart = '^(\d+\. |- )'
# a number and the unit after it stay on one line ('63 %', '225 ms')
$script:WorkerPerfCopyNumber = '^[-+]?\d+(,\d+)?$'
$script:WorkerPerfCopyUnit = '^(%|ms|s|KB|MB|GB)([.,;:)]*)$'
# a bare number, with or without punctuation after it, stays with the word before it ('Vorfall 3.', 'Benutzer 03'):
# a continuation line never starts like a numbered step and a replacement name is never split (ruling P3-R33)
$script:WorkerPerfCopyBareNumber = '^[-+]?\d+(,\d+)?[.,;:!?)]*$'

function Format-WorkerPerfCopyLines([string[]]$Paragraphs, [int]$Width = 78) {
    # Wraps each paragraph at spaces to lines of at most Width characters; a word longer than the line is split hard
    # (nothing is lost). A paragraph starting with '1. ' (any number) or '- ' indents its continuation lines by the
    # width of that start, and its label never stands alone on a line; a number stays with its unit and with the word
    # before it. An empty paragraph is an empty line; line breaks inside a paragraph are spaces. Line end CR LF.
    if ($Width -lt 1) { $Width = 1 }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($paragraph in @($Paragraphs)) {
        $text = [regex]::Replace([string]$paragraph, '[\r\n\t]+', ' ')
        $m = [regex]::Match($text, $script:WorkerPerfCopyListStart)
        $pad = ''; $label = ''
        if ($m.Success -and $m.Length -lt $Width) { $pad = ' ' * $m.Length; $label = $m.Value.TrimEnd() }
        # the words to wrap: a group joined like this is only made while it fits on a line (no hard split of its own);
        # a unit that does not fit with the group of its number takes the number with it. Nothing is joined to the label.
        $room = $Width - $pad.Length
        $words = New-Object System.Collections.Generic.List[string]
        $last = ''; $lastJoined = $false
        foreach ($w in $text.Split([char[]]@(' '), [StringSplitOptions]::RemoveEmptyEntries)) {
            $n = $words.Count
            $glue = $n -gt 0 -and -not ($label -and $n -eq 1)
            $joined = $false
            if ($glue -and $w -cmatch $script:WorkerPerfCopyUnit -and $last -match $script:WorkerPerfCopyNumber) {
                if ($words[$n - 1].Length + 1 + $w.Length -le $room) { $words[$n - 1] += ' ' + $w; $joined = $true }
                elseif ($lastJoined) {
                    $words[$n - 1] = $words[$n - 1].Substring(0, $words[$n - 1].Length - $last.Length - 1)
                    $words.Add($last + ' ' + $w)
                }
                else { $words.Add($w) }
            }
            elseif ($glue -and $w -match $script:WorkerPerfCopyBareNumber -and $words[$n - 1].Length + 1 + $w.Length -le $room) { $words[$n - 1] += ' ' + $w; $joined = $true }
            else { $words.Add($w) }
            $last = $w; $lastJoined = $joined
        }
        if ($words.Count -eq 0) { $lines.Add(''); continue }
        $cur = ''; $lead = ''
        foreach ($w in $words) {
            $rest = $w
            while ($rest.Length -gt 0) {
                if ($cur.Length -eq 0) { $cur = $lead }
                if ($cur.Length -gt $lead.Length) {
                    if ($cur.Length + 1 + $rest.Length -le $Width) { $cur += ' ' + $rest; $rest = ''; continue }
                    if ($label -and $cur -ceq $label -and $Width - $cur.Length - 1 -ge 1) {
                        # the label alone with a word longer than the rest of the line: split the word on this line
                        $take = $Width - $cur.Length - 1
                        if ($take -gt 1 -and [char]::IsHighSurrogate($rest[$take - 1])) { $take-- }
                        $lines.Add($cur + ' ' + $rest.Substring(0, $take)); $rest = $rest.Substring($take); $cur = ''; $lead = $pad
                        continue
                    }
                    $lines.Add($cur); $cur = ''; $lead = $pad
                    continue
                }
                if ($cur.Length + $rest.Length -le $Width) { $cur += $rest; $rest = ''; continue }
                # a word longer than a whole line: as much as fits, never between the two halves of a surrogate pair
                $take = $Width - $cur.Length
                if ($take -gt 1 -and [char]::IsHighSurrogate($rest[$take - 1])) { $take-- }
                $lines.Add($cur + $rest.Substring(0, $take)); $rest = $rest.Substring($take); $cur = ''; $lead = $pad
            }
        }
        if ($cur.Length -gt $lead.Length) { $lines.Add($cur) }
    }
    return ($lines.ToArray() -join "`r`n")
}

function ConvertTo-WorkerPerfAnonymousText([string]$Text, $Mask) {
    # The text without names: the replacement names of the mask (New-WorkerPerfMask of level Alles of the same capture,
    # as a masked report uses them). Needs WorkerPerf.Mask.ps1.
    return (Hide-WorkerPerfReportText $Text $Mask)
}

function Get-WorkerPerfCopyFacts($Incident, $Data, $Catalogue, $Texts) {
    # The facts of the incident as the guidance has them (Get-WorkerPerfGuidanceFacts), in the server's time of the data.
    $offset = [int](Get-WorkerPerfField (Get-WorkerPerfField $Data 'meta') 'offsetMin')
    return (Get-WorkerPerfGuidanceFacts -Incident $Incident -Context @{ Data = $Data; OffsetMinutes = $offset; Texts = $Texts } -Catalogue $Catalogue)
}

function Test-WorkerPerfCopyBefore($Incident) {
    # an incident of the days before the capture (before.incidents of the report data)
    return [bool](Get-WorkerPerfField (Get-WorkerPerfField $Incident 'event') 'before')
}

function Get-WorkerPerfCopyTitleLine($Guide, [hashtable]$Values, $Texts, [bool]$WithDate = $false) {
    # Time, duration, title and technical name in the formats of the texts (copy.span, copy.duration, copy.title,
    # copy.tech): the time alone without duration, the end only when it differs; WithDate puts the date before the time
    # (copy.dated; an incident before the capture).
    $when = [string]$Values['from']
    $to = [string]$Values['to']
    if ($when -and $to -and $to -ne $when) { $when = Format-WorkerPerfGuidanceWord $Texts 'copy.span' @($when, $to) }
    if ($when -and $Values.ContainsKey('duration')) { $when = Format-WorkerPerfGuidanceWord $Texts 'copy.duration' @($when, [string]$Values['duration']) }
    if ($when -and $WithDate -and $Values['date']) { $when = Format-WorkerPerfGuidanceWord $Texts 'copy.dated' @([string]$Values['date'], $when) }
    $title = [string](Get-WorkerPerfField $Guide 'title')
    $tech = [string](Get-WorkerPerfField $Guide 'tech')
    if ($tech) { $title = Format-WorkerPerfGuidanceWord $Texts 'copy.tech' @($title, $tech) }
    if (-not $when) { return $title }
    return (Format-WorkerPerfGuidanceWord $Texts 'copy.title' @($when, $title))
}

function Get-WorkerPerfCopyAffected($Incident, $Data, $Facts, $Catalogue, $Texts) {
    # The paragraph on the affected sessions, or $null (ruling P3-R32): none when they cannot be determined (the user's
    # view says so) or not assigned (an incident before the capture without sessions) and none for a chronic state
    # without affected sessions, and none for an event incident outside user sessions (its causeText says so, ruling
    # P3-R32 as refined); else copy.affected with the number of sessions (event.sessions of an event incident, affected otherwise) and their
    # users (event.users; of the sessions in Data.sessions).
    $v = $Facts.Values
    if (@($Facts.Conditions) -ccontains 'affected.unknown' -or -not $v.ContainsKey('affected')) { return $null }
    $count = [string]$v['affected']
    $users = New-Object System.Collections.Generic.List[string]
    if ([string](Get-WorkerPerfField $Incident 'type') -eq 'ereignis') {
        $ev = Get-WorkerPerfField $Incident 'event'
        # outside user sessions the incident's own sentence (causeText) says "Ohne Benutzersitzung." already
        if ($count -eq '0' -and [bool](Get-WorkerPerfField $ev 'noUserSession')) { return $null }
        foreach ($u in (Get-WorkerPerfGuidanceList $ev 'users')) { if ([string]$u -and -not $users.Contains([string]$u)) { $users.Add([string]$u) } }
    }
    else {
        $sessions = Get-WorkerPerfGuidanceList $Data 'sessions'
        foreach ($a in (Get-WorkerPerfGuidanceList $Incident 'affected')) {
            $idx = [string](Get-WorkerPerfField $a 's')
            foreach ($s in $sessions) {
                if ([string](Get-WorkerPerfField $s 'i') -ne $idx) { continue }
                $u = [string](Get-WorkerPerfField $s 'user')
                if ($u -and -not $users.Contains($u)) { $users.Add($u) }
            }
        }
    }
    $list = ''; if ($users.Count -gt 0) { $list = Join-WorkerPerfTextList $users.ToArray() $Texts }
    # a chronic state without affected sessions says nothing about them, as the incident's sentence does
    if ($count -eq '0' -and -not $list -and [bool](Get-WorkerPerfField $Incident 'chronic')) { return $null }
    $affected = $count
    if ($list) { $affected = "$count ($list)" }
    return (Format-WorkerPerfGuidancePart $Catalogue 'copy' 'affected' @{ affected = $affected })
}

function Get-WorkerPerfCopyLimit($Catalogue, [string]$Key) {
    # How many steps of a list a copy text carries (copy.maxChecks, copy.maxRemedies of the catalogue); a value that is
    # no whole number from 1 on (a catalogue changed after loading) stops with its name.
    $n = Get-WorkerPerfField (Get-WorkerPerfField $Catalogue 'copy') $Key
    if (-not (Test-WorkerPerfGuidanceCount $n)) { throw "Catalogue value 'copy.$Key' is no whole number from 1 on." }
    return [int]$n
}

function Get-WorkerPerfCopyMore($Catalogue, [int]$Left, [string]$One, [string]$Many) {
    # The paragraph after a shortened block of a copy text: how many more steps stand in the report (catalogue texts
    # copy.<One> for one, copy.<Many> with the number); nothing when no step was left out.
    if ($Left -eq 1) { return (Format-WorkerPerfGuidancePart $Catalogue 'copy' $One @{}) }
    if ($Left -gt 1) { return (Format-WorkerPerfGuidancePart $Catalogue 'copy' $Many @{ count = [string]$Left }) }
}

function Get-WorkerPerfCopyParagraphs {
    # The paragraphs of the copy text of one incident, unwrapped: head (copy.head), time and duration with title and
    # technical name (guide.tech; the date first for an incident before the capture), the user's view (guide.userView),
    # impact, measured value with target (copy.measure, dropped without a value), cause (copy.cause and the incident's
    # causeText, the part of its sentence on cause and context), affected (Get-WorkerPerfCopyAffected), then the numbered
    # checks (copy.checks; texts copy.check), the remedies (copy.remedies; '- ' and copy.remedy) and the contacts
    # (copy.contact; '- '), each block after an empty paragraph. Of the checks and the remedies the text carries the first
    # ones only, in the guide's order (copy.maxChecks, copy.maxRemedies), and says after a shortened block how many more
    # stand in the report (copy.moreChecks, copy.moreRemedies; ruling P3-R59); it carries every contact. Guide:
    # New-WorkerPerfGuidance of the incident; Data: the report data; Texts: Read-WorkerPerfTexts. Plain pipeline output
    # (the caller writes @(...)).
    param($Incident, $Guide, $Data, $Catalogue, [Parameter(Mandatory = $true)]$Texts)
    $facts = Get-WorkerPerfCopyFacts $Incident $Data $Catalogue $Texts
    $v = $facts.Values
    Format-WorkerPerfGuidancePart $Catalogue 'copy' 'head' $v
    Get-WorkerPerfCopyTitleLine $Guide $v $Texts (Test-WorkerPerfCopyBefore $Incident)
    $view = [string](Get-WorkerPerfField $Guide 'userView'); if ($view) { $view }
    $impact = [string](Get-WorkerPerfField $Guide 'impact'); if ($impact) { $impact }
    if ($v.ContainsKey('value')) {
        $t = Format-WorkerPerfGuidanceText ([string](Get-WorkerPerfField (Get-WorkerPerfField $Catalogue 'copy') 'measure')) $v
        if ($null -ne $t) { $t }
    }
    $cause = ([string](Get-WorkerPerfField $Incident 'causeText')).Trim()
    if ($cause) { (Format-WorkerPerfGuidancePart $Catalogue 'copy' 'cause' @{}) + ' ' + $cause }
    $affected = Get-WorkerPerfCopyAffected $Incident $Data $facts $Catalogue $Texts
    if ($null -ne $affected) { $affected }
    $checks = Get-WorkerPerfGuidanceList $Guide 'checks'
    if ($checks.Count -gt 0) {
        ''
        Format-WorkerPerfGuidancePart $Catalogue 'copy' 'checks' @{}
        $shown = [Math]::Min($checks.Count, (Get-WorkerPerfCopyLimit $Catalogue 'maxChecks'))
        for ($n = 0; $n -lt $shown; $n++) {
            $c = $checks[$n]
            ('{0}. ' -f ($n + 1)) + (Format-WorkerPerfGuidanceWord $Texts 'copy.check' @([string](Get-WorkerPerfField $c 'text'), [string](Get-WorkerPerfField $c 'where'), [string](Get-WorkerPerfField $c 'sign')))
        }
        Get-WorkerPerfCopyMore $Catalogue ($checks.Count - $shown) 'moreCheck' 'moreChecks'
    }
    $remedies = Get-WorkerPerfGuidanceList $Guide 'remedies'
    if ($remedies.Count -gt 0) {
        ''
        Format-WorkerPerfGuidancePart $Catalogue 'copy' 'remedies' @{}
        $shown = [Math]::Min($remedies.Count, (Get-WorkerPerfCopyLimit $Catalogue 'maxRemedies'))
        for ($n = 0; $n -lt $shown; $n++) {
            $r = $remedies[$n]
            '- ' + (Format-WorkerPerfGuidanceWord $Texts 'copy.remedy' @([string](Get-WorkerPerfField $r 'precondition'), [string](Get-WorkerPerfField $r 'text')))
        }
        Get-WorkerPerfCopyMore $Catalogue ($remedies.Count - $shown) 'moreRemedy' 'moreRemedies'
    }
    $contacts = Get-WorkerPerfGuidanceList $Guide 'contacts'
    if ($contacts.Count -gt 0) {
        ''
        Format-WorkerPerfGuidancePart $Catalogue 'copy' 'contact' @{}
        foreach ($c in $contacts) { '- ' + [string](Get-WorkerPerfField $c 'text') }
    }
}

function Get-WorkerPerfCopySummaryParagraphs {
    # The paragraphs of the summary of the capture, unwrapped: head (copy.summaryHead: server, date, start and end of the
    # capture as HH:mm), symbol, word and sentence of the Lagebild, its hints one paragraph each, then after an empty
    # paragraph one paragraph per incident in the order of Order ('- ' time, duration, title, technical name, impact),
    # then after an empty paragraph the incidents before the capture (Before) under copy.before, oldest first ('- ' date,
    # time, title, technical name); no such block without them. Incidents: the capture's incidents, Before: the
    # incidents of before.incidents, each with its guide (guide); an id of Order used once; an id missing from Incidents
    # stops. Plain pipeline output (the caller writes @(...)).
    param([object[]]$Incidents = @(), [int[]]$Order = @(), $Lagebild, $Data, $Catalogue, [Parameter(Mandatory = $true)]$Texts, [object[]]$Before = @())
    $meta = Get-WorkerPerfField $Data 'meta'
    $offset = [int](Get-WorkerPerfField $meta 'offsetMin')
    $v = @{}
    $t = [string](Get-WorkerPerfField $meta 'computer'); if ($t) { $v['server'] = $t }
    $start = Get-WorkerPerfField $meta 'start'; $end = Get-WorkerPerfField $meta 'end'
    if ($null -ne $start) {
        $v['date'] = Format-WorkerPerfEventDate ([long][double]$start) $offset
        $v['from'] = (Format-WorkerPerfClock ([long][double]$start) $offset).Substring(0, 5)
    }
    if ($null -ne $end) { $v['to'] = (Format-WorkerPerfClock ([long][double]$end) $offset).Substring(0, 5) }
    Format-WorkerPerfGuidancePart $Catalogue 'copy' 'summaryHead' $v
    $state = (@([string](Get-WorkerPerfField $Lagebild 'symbol'), [string](Get-WorkerPerfField $Lagebild 'word')) | Where-Object { $_ }) -join ' '
    $sentence = [string](Get-WorkerPerfField $Lagebild 'sentence')
    if ($state -and $sentence) { $state + ': ' + $sentence } elseif ($state -or $sentence) { $state + $sentence }
    foreach ($h in (Get-WorkerPerfGuidanceList $Lagebild 'hints')) { if ([string]$h) { [string]$h } }
    $byId = @{}
    foreach ($inc in @($Incidents)) { if ($null -ne $inc) { $byId[[int](Get-WorkerPerfField $inc 'id')] = $inc } }
    $seen = New-Object System.Collections.Generic.List[int]
    foreach ($id in @($Order)) {
        if ($seen.Contains([int]$id)) { continue }
        if (-not $byId.ContainsKey([int]$id)) { throw "Get-WorkerPerfCopySummaryParagraphs: id $id of the order is not among the incidents." }
        if ($seen.Count -eq 0) { '' }
        $seen.Add([int]$id)
        $inc = $byId[[int]$id]
        $guide = Get-WorkerPerfField $inc 'guide'
        $line = '- ' + (Get-WorkerPerfCopyTitleLine $guide (Get-WorkerPerfCopyFacts $inc $Data $Catalogue $Texts).Values $Texts)
        $impact = [string](Get-WorkerPerfField $guide 'impact')
        if ($impact) {
            if ($line -notmatch '[.!?]$') { $line += '.' }
            $line += ' ' + $impact
        }
        $line
    }
    $earlier = @(@($Before) | Where-Object { $null -ne $_ } | Sort-Object -Property @{ Expression = { [double](Get-WorkerPerfField $_ 'start') } }, @{ Expression = { [int](Get-WorkerPerfField $_ 'id') } })
    if ($earlier.Count -gt 0) {
        ''
        Get-WorkerPerfGuidanceWord $Texts 'copy.before'
        foreach ($inc in $earlier) { '- ' + (Get-WorkerPerfCopyTitleLine (Get-WorkerPerfField $inc 'guide') (Get-WorkerPerfCopyFacts $inc $Data $Catalogue $Texts).Values $Texts $true) }
    }
}

function New-WorkerPerfCopyText {
    # The plain-text summary of one incident (spec 6): the paragraphs of Get-WorkerPerfCopyParagraphs wrapped to 78
    # characters. With -Mask (New-WorkerPerfMask of level Alles of the same capture) the version without names: every
    # paragraph is masked before wrapping.
    param($Incident, $Guide, $Data, $Catalogue, [Parameter(Mandatory = $true)]$Texts, $Mask = $null)
    $paragraphs = @(Get-WorkerPerfCopyParagraphs -Incident $Incident -Guide $Guide -Data $Data -Catalogue $Catalogue -Texts $Texts)
    if ($null -ne $Mask) { $paragraphs = @($paragraphs | ForEach-Object { ConvertTo-WorkerPerfAnonymousText $_ $Mask }) }
    return (Format-WorkerPerfCopyLines $paragraphs)
}

function New-WorkerPerfCopySummary {
    # The plain-text summary of the capture (spec 6): the paragraphs of Get-WorkerPerfCopySummaryParagraphs wrapped to 78
    # characters; with -Mask the version without names, masked per paragraph before wrapping. Before: the incidents of
    # before.incidents with their guide (may be empty).
    param([object[]]$Incidents = @(), [int[]]$Order = @(), $Lagebild, $Data, $Catalogue, [Parameter(Mandatory = $true)]$Texts, $Mask = $null, [object[]]$Before = @())
    $paragraphs = @(Get-WorkerPerfCopySummaryParagraphs -Incidents $Incidents -Order $Order -Lagebild $Lagebild -Data $Data -Catalogue $Catalogue -Texts $Texts -Before $Before)
    if ($null -ne $Mask) { $paragraphs = @($paragraphs | ForEach-Object { ConvertTo-WorkerPerfAnonymousText $_ $Mask }) }
    return (Format-WorkerPerfCopyLines $paragraphs)
}
