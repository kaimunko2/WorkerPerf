#Requires -Version 5.1
# Guidance catalogue (guidance.de.json): loading and checking; the situation, conditions and placeholder values of an
# incident and its guidance; the ranking of the incidents, the groups after the cards and the situation summary
# (Lagebild) of the capture. Dot-source this file; it only defines variables and functions and runs nothing. It needs
# WorkerPerf.Common.ps1 (ConvertFrom-WorkerPerfJsonFile, Read-WorkerPerfThresholds, Get-WorkerPerfField, Test-WorkerPerfSkipDetail,
# $script:WorkerPerfRoleNames, $script:WorkerPerfCategories), WorkerPerf.Events.ps1 ($script:WorkerPerfPatternOrder,
# Format-WorkerPerfEventDate, Test-WorkerPerfAccountPattern) and WorkerPerf.Findings.ps1 (Format-WorkerPerfTextNumber,
# Format-WorkerPerfValue, Format-WorkerPerfClock). The unit words of a duration come from the texts (texts.de.json).

$script:WorkerPerfSituations = @('cpu', 'memory', 'disk', 'share', 'profile', 'delay.many', 'delay.single', 'chronic.network', 'chronic.resource',
    'crash', 'hang', 'service', 'print', 'profileerror', 'system', 'fallback')
# spec 5.5 names the first 14; module, driver and count are needed by the event situations, the rest by the Lagebild,
# the hints and the head of the copy text; skipped carries the labels of skipped categories
$script:WorkerPerfGuidancePlaceholders = @('user', 'app', 'share', 'baseline', 'value', 'target', 'from', 'to', 'duration', 'affected', 'resource',
    'endpoint', 'endpointValue', 'security', 'module', 'driver', 'count', 'server', 'date', 'signals', 'message', 'bottlenecks', 'delays',
    'events', 'chronic', 'minutes', 'incidents', 'skipped')
# conditions without a variable part (spec 5.4 and the additions of the measurement categories)
$script:WorkerPerfGuidanceConditions = @('cause.app', 'cause.security', 'cause.none', 'cause.nodata', 'cause.notmeasured', 'scan',
    'companion.security', 'endpoint.slow', 'event.applocker', 'event.defender', 'affected.many', 'affected.one', 'affected.unknown', 'chronic',
    'pattern.none', 'pattern.unchecked', 'driver.v3', 'driver.v4', 'driver.shared', 'driver.isolated', 'spooler.crash', 'queue.stuck', 'before',
    'incident.unverified')
# catalogue parts and the keys each text part must have, in the order they are checked
$script:WorkerPerfGuidanceParts = @('version', 'terms', 'vendors', 'userView', 'lagebild', 'hints', 'copy', 'fallbackNote', 'situations')
$script:WorkerPerfGuidancePartKeys = [ordered]@{
    'userView' = @('many', 'one', 'none', 'unknown', 'chronic', 'eventMany', 'eventOne', 'eventNone', 'before')
    'lagebild' = @('red', 'yellow', 'green', 'greenSkipped')
    'hints'    = @('unmeasured', 'skipped', 'notFinished', 'error', 'errorNoMessage', 'stopped')
    'copy'     = @('head', 'summaryHead', 'measure', 'cause', 'affected', 'checks', 'remedies', 'contact')
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

function Assert-WorkerPerfGuidanceField([string]$Path, [string]$Entry, [string]$Item, $Object, [string]$Field) {
    # A required text field of an object.
    $p = Get-WorkerPerfGuidanceMember $Object $Field
    if ($null -eq $p) { Stop-WorkerPerfGuidance $Path $Entry $Item $Field 'fehlt' }
    Assert-WorkerPerfGuidanceString $Path $Entry $Item $Field $p.Value
}

function Test-WorkerPerfGuidanceCondition([string]$Name, $Catalogue, [string[]]$Signals = $null) {
    # Whether a condition name is known (spec 5.4). Signals: the ids of thresholds.json; read from there when not given.
    if ($script:WorkerPerfGuidanceConditions -ccontains $Name) { return $true }
    $dot = $Name.IndexOf('.')
    if ($dot -lt 1 -or $dot -eq $Name.Length - 1) { return $false }
    $kind = $Name.Substring(0, $dot); $rest = $Name.Substring($dot + 1)
    switch -CaseSensitive ($kind) {
        'role' { return ($script:WorkerPerfRoleNames -ccontains $rest) }
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

function Test-WorkerPerfGuidanceItem([string]$Path, [string]$Situation, [string]$ListName, [int]$Index, $Element, $Catalogue, [string[]]$Signals) {
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
            if ($n -isnot [string] -or -not (Test-WorkerPerfGuidanceCondition $n $Catalogue $Signals)) {
                Stop-WorkerPerfGuidance $Path $Situation $item 'when' "enthaelt die unbekannte Bedingung '$n'"
            }
        }
    }
    # spec 5.7: every print element (check, remedy, contact) names its source
    $needsSource = $Situation -eq 'print' -or
        @($conditions | Where-Object { $_ -ceq 'pattern.printdriver' -or $_.StartsWith('driver.', [StringComparison]::Ordinal) }).Count -gt 0
    $source = Get-WorkerPerfGuidanceMember $Element 'source'
    if ($null -ne $source) { Assert-WorkerPerfGuidanceString $Path $Situation $item 'source' $source.Value }
    elseif ($needsSource) { Stop-WorkerPerfGuidance $Path $Situation $item 'source' 'fehlt (Pflicht fuer Druckempfehlungen)' }
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

function Test-WorkerPerfGuidanceSituation([string]$Path, [string]$Name, $Entry, $Catalogue, [string[]]$Signals) {
    if (-not (Test-WorkerPerfGuidanceObject $Entry)) { Stop-WorkerPerfGuidance $Path $Name '' '' 'ist kein Objekt' }
    foreach ($f in 'title', 'meaning', 'impact', 'short') { Assert-WorkerPerfGuidanceField $Path $Name '' $Entry $f }
    # title and short are constant; meaning and impact only use values every incident has
    foreach ($f in 'title', 'short') {
        $m = [regex]::Match($Entry.$f, '\{[A-Za-z0-9]+\}')
        if ($m.Success) { Stop-WorkerPerfGuidance $Path $Name '' $f "darf keinen Platzhalter enthalten ('$($m.Value)')" }
    }
    foreach ($f in 'meaning', 'impact') { Assert-WorkerPerfGuidanceAlwaysValues $Path $Name $f $Entry.$f }
    foreach ($list in $script:WorkerPerfGuidanceItemFields.Keys) {
        $p = Get-WorkerPerfGuidanceMember $Entry $list
        if ($null -eq $p) { Stop-WorkerPerfGuidance $Path $Name '' $list 'fehlt' }
        if ($p.Value -isnot [array]) { Stop-WorkerPerfGuidance $Path $Name '' $list 'ist keine Liste' }
        $elements = @($p.Value)
        $general = 0
        for ($i = 0; $i -lt $elements.Count; $i++) {
            if (-not (Test-WorkerPerfGuidanceItem $Path $Name $list $i $elements[$i] $Catalogue $Signals)) { $general++ }
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

function Read-WorkerPerfGuidance([string]$Path) {
    # Reads the guidance catalogue and checks structure, required fields, conditions and placeholders (spec 5.6).
    # Returns the catalogue as read; the first error stops with a message that names entry and field.
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
        foreach ($p in $o.PSObject.Properties) { Assert-WorkerPerfGuidanceString $Path $part '' $p.Name $p.Value }
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
    foreach ($s in $script:WorkerPerfSituations) { Test-WorkerPerfGuidanceSituation $Path $s $situations.$s $cat $signals }
    return $cat
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
    # the report data. Context: @{ Data; Thresholds; OffsetMinutes; Texts } (Texts from Read-WorkerPerfTexts). A value
    # the incident does not have is left out.
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

function Get-WorkerPerfGuidanceItems($Entry, [string]$ListName, [string[]]$Conditions, [hashtable]$Values, $Templates) {
    # The elements of one list of a catalogue entry that the facts support: every condition of 'when' holds and every
    # text can be filled. Elements with a condition first, otherwise the order of the file. Plain pipeline output (the
    # caller writes @(...)). Templates (a List[string]) receives the templates of the texts of the elements emitted
    # (not their sources), for the glossary.
    $withCondition = New-Object System.Collections.Generic.List[object]
    $general = New-Object System.Collections.Generic.List[object]
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
        if ($when.Count -gt 0) { $withCondition.Add($item) } else { $general.Add($item) }
    }
    foreach ($item in $withCondition) { $item }
    foreach ($item in $general) { $item }
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
    # support, its technical name (Texts: Read-WorkerPerfTexts), the user's view and the terms used in its texts.
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

function Get-WorkerPerfLagebild {
    # The situation summary of the capture (spec 3.1): state with symbol and word, sentence (catalogue part lagebild),
    # key figures, hints on the capture (catalogue part hints) and the id of the most important incident.
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

    $sentenceKey = $state
    if ($state -eq 'green' -and @($skipped | Where-Object { [string](Get-WorkerPerfField $_ 'id') -ceq 'Ereignisse' }).Count -gt 0) { $sentenceKey = 'greenSkipped' }
    $sentence = Format-WorkerPerfGuidancePart $Catalogue 'lagebild' $sentenceKey $v

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
