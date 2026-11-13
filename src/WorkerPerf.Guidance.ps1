#Requires -Version 5.1
# Guidance catalogue (guidance.de.json): loading and checking. Dot-source this file; it only defines variables and
# functions and runs nothing. It needs WorkerPerf.Common.ps1 (ConvertFrom-WorkerPerfJsonFile, Read-WorkerPerfThresholds,
# $script:WorkerPerfRoleNames, $script:WorkerPerfCategories) and WorkerPerf.Events.ps1 ($script:WorkerPerfPatternOrder).

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
