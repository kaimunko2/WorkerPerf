#Requires -Version 5.1
# Guidance catalogue (guidance.de.json): loading and checking, and the situation, conditions and placeholder values of
# an incident. Dot-source this file; it only defines variables and functions and runs nothing. It needs
# WorkerPerf.Common.ps1 (ConvertFrom-WorkerPerfJsonFile, Read-WorkerPerfThresholds, Get-WorkerPerfField,
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

function Test-WorkerPerfGuidanceSituation([string]$Path, [string]$Name, $Entry, $Catalogue, [string[]]$Signals) {
    if (-not (Test-WorkerPerfGuidanceObject $Entry)) { Stop-WorkerPerfGuidance $Path $Name '' '' 'ist kein Objekt' }
    foreach ($f in 'title', 'meaning', 'impact', 'short') { Assert-WorkerPerfGuidanceField $Path $Name '' $Entry $f }
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
