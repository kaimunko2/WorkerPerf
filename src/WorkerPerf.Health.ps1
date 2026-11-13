#Requires -Version 5.1
# Catalogue of the health picture (health.de.json): the facts it can rate (the read values, the derived facts and the
# facts of the applications), loading and checking the catalogue, the thresholds that differ from their default.
# Dot-source this file; it only defines variables and functions and runs nothing. It needs WorkerPerf.Common.ps1
# ($script:WorkerPerfHealthAreas, $script:WorkerPerfHealthValues, Get-WorkerPerfAppFactType, ConvertFrom-WorkerPerfJsonFile,
# Get-WorkerPerfField), WorkerPerf.Guidance.ps1 ($script:WorkerPerfSituations) and WorkerPerf.Events.ps1
# ($script:WorkerPerfPatternOrder).

# the four grades of a check; 'na' ("does not apply") is a result, not a grade
$script:WorkerPerfHealthGrades = @('ok', 'check', 'act', 'unknown')
$script:WorkerPerfHealthKinds = @('vendor', 'practice', 'rule')
$script:WorkerPerfHealthOps = @('gt', 'ge', 'lt', 'le', 'eq', 'ne', 'in', 'contains', 'exists', 'absent')
$script:WorkerPerfHealthEventKinds = @('crash', 'hang', 'service', 'print', 'profileerror', 'system', 'system.storage', 'system.fileserver')
$script:WorkerPerfHealthRequiredThresholds = @('workStartHour', 'workEndHour')
# the parts of the catalogue, in the order they are checked
$script:WorkerPerfHealthCatalogueParts = @('version', 'areas', 'grades', 'thresholds', 'values', 'copy', 'precedence', 'checks')

# The members the loader reads, per object of the catalogue; names are compared exactly and any other name is rejected.
$script:WorkerPerfHealthCatalogueFields = [ordered]@{
    area = @('id', 'label', 'notCovered'); grade = @('word', 'symbol'); threshold = @('value', 'default', 'unit', 'label')
    check = @('id', 'area', 'title', 'values', 'rules', 'findings', 'meaning', 'todo', 'source', 'kind', 'relates')
    rules = @('check', 'act'); findings = @('ok', 'check', 'act', 'unknown'); step = @('text', 'where', 'sign')
    source = @('vendor', 'title', 'url', 'date'); precedence = @('check', 'winner', 'reason')
    valueCondition = @('value', 'op', 'than', 'hard'); eventCondition = @('event', 'min', 'days')
}

# Ruling ZB-R25, the type table: what a condition may compare, per type of its fact: type -> operator -> the kinds of
# 'than' it takes (none: no 'than'; threshold: '@<name>'; numbers, texts: a list for 'in'). Every text:<name> except
# text:free counts as text; a list is never compared. time takes exists and absent only: the plan's checks compare a
# time as a derived number of days or hours (operation.uptimeDays, operation.updateAgeDays), never directly.
$script:WorkerPerfHealthOpTable = & {
    $none = @('none'); $numberOrThreshold = @('number', 'threshold')
    [ordered]@{
        'number'    = [ordered]@{ 'gt' = $numberOrThreshold; 'ge' = $numberOrThreshold; 'lt' = $numberOrThreshold; 'le' = $numberOrThreshold
            'eq' = $numberOrThreshold; 'ne' = $numberOrThreshold; 'in' = @('numbers'); 'exists' = $none; 'absent' = $none }
        'bool'      = [ordered]@{ 'eq' = @('bool'); 'ne' = @('bool'); 'exists' = $none; 'absent' = $none }
        'text'      = [ordered]@{ 'eq' = @('text'); 'ne' = @('text'); 'contains' = @('text'); 'in' = @('texts'); 'exists' = $none; 'absent' = $none }
        'text:free' = [ordered]@{ 'exists' = $none; 'absent' = $none }
        'time'      = [ordered]@{ 'exists' = $none; 'absent' = $none }
        'value'     = [ordered]@{ 'gt' = $numberOrThreshold; 'ge' = $numberOrThreshold; 'lt' = $numberOrThreshold; 'le' = $numberOrThreshold
            'eq' = @('number', 'threshold', 'bool', 'text'); 'ne' = @('number', 'threshold', 'bool', 'text'); 'in' = @('numbers', 'texts')
            'contains' = @('number', 'text'); 'exists' = $none; 'absent' = $none }
    }
}
# the kinds of 'than' as the loader's messages name them
$script:WorkerPerfHealthThanKindWords = @{ none = 'ohne Vergleichswert'; number = 'Zahl'; threshold = 'Schwelle'; bool = 'Ja/Nein-Wert'
    text = 'Text'; numbers = 'Liste von Zahlen'; texts = 'Liste von Texten' }

# The derived facts (formed by the evaluation, not in health.json), in the order of the plan's tables:
# id -> Area, Type, Unit, Fields (only for a list: field name -> type).
$script:WorkerPerfHealthDerived = & {
    $rows = @(
        @('size.commitPeakPct', 'number', '%'), @('size.commitNowPct', 'number', '%'), @('size.pagefileCount', 'number'),
        @('size.memPerSessionMB', 'number', 'MB'), @('size.sessionsPerCpu', 'number'), @('size.commitOfRamPct', 'number', '%'),
        @('size.vmware', 'bool'), @('size.vmtoolsMajor', 'number'), @('size.balloonRunning', 'bool'), @('size.otherNetAdapters', 'number'),
        @('size.lsiControllers', 'number'),

        @('operation.uptimeDays', 'number', 'Tage'), @('operation.updateAgeDays', 'number', 'Tage'), @('operation.minFreeGB', 'number', 'GB'),

        @('sessions.userCount', 'number'), @('sessions.disconnectedCount', 'number'), @('sessions.disconnectedOldestHours', 'number', 'Stunden'),
        @('sessions.disconnectLimitMin', 'number', 'Minuten'), @('sessions.idleLimitMin', 'number', 'Minuten'),
        @('sessions.unloadedProfiles', 'number'), @('sessions.tempProfiles', 'number'),

        @('vda.stoppedAutoServices', 'number'), @('vda.controllerCount', 'number'), @('vda.controllersNotFqdn', 'number'),
        @('vda.wemServicesNotReady', 'number'),

        @('profile.containerCount', 'number'), @('profile.containerMaxUsedPct', 'number', '%'), @('profile.maxContainersPerUser', 'number'),

        @('print.driverCount', 'number'), @('print.driversInSpooler', 'number'), @('print.driversV2', 'number'), @('print.vendorDrivers', 'number'),
        @('print.citrixDrivers', 'number'), @('print.queuesPerSession', 'number'), @('print.citrixMapping', 'bool'),
        @('print.mappingClientRelease', 'number'),

        @('security.products', 'text'), @('security.otherFilterProducts', 'number'), @('security.mdeOnboarded', 'bool'),
        @('security.citrixExclusionsMissing', 'number'), @('security.wemExclusionsMissing', 'number'),

        @('network.smbOldDialects', 'number'), @('network.dnsServersMin', 'number'), @('network.dnsPublic', 'number'),
        @('network.timeFromDomain', 'bool'), @('network.rssOff', 'number'),

        @('events.lookbackDays', 'number', 'Tage'), @('events.crashDays', 'number'), @('events.storageCount', 'number'),
        @('events.fileserverDays', 'number'),
        @('events.perDay', 'list', '', 'Day=text, Crash=number, Hang=number, Service=number, Storage=number, Print=number, Fileserver=number, Profileerror=number'),
        @('events.coverageGapDays', 'number', 'Tage'), @('events.retainLogs', 'number'), @('events.fullLogs', 'number'),
        @('events.disabledLogs', 'number'), @('events.reachFrom', 'time'), @('events.sinceBootOnly', 'bool'),

        @('maintenance.tasksInWorkHours', 'number'), @('maintenance.sessionTriggerTasks', 'number'), @('maintenance.scanInWorkHours', 'bool'),
        @('maintenance.updateInWorkHours', 'bool')
    )
    $list = [ordered]@{}
    foreach ($row in $rows) {
        $fields = $null
        if ($row.Count -gt 3) {
            $fields = [ordered]@{}
            foreach ($pair in ($row[3] -split ', ')) { $nameAndType = $pair -split '=', 2; $fields[$nameAndType[0]] = $nameAndType[1] }
        }
        $unit = ''; if ($row.Count -gt 2) { $unit = $row[2] }
        $list[$row[0]] = @{ Area = $row[0].Split('.')[0]; Type = $row[1]; Unit = $unit; Fields = $fields }
    }
    $list
}

# The texts of copy (all required) -> the placeholders each may hold.
$script:WorkerPerfHealthCopyKeys = [ordered]@{
    title = @(); healthOnlyHead = @(); notRecorded = @(); notRecordedFailed = @(); unreadable = @()
    readAt = @('date', 'time', 'seconds'); summary = @('act', 'check', 'ok'); areaOne = @(); areaMany = @('n')
    countsAct = @('n'); countsCheck = @('n'); countsUnknown = @('n')
    areaPartial = @(); areaFailed = @(); areaReasonBudget = @(); areaReasonNoReader = @(); areaReasonNotRead = @(); areaReasonNotInFile = @()
    unknownOne = @(); unknownMany = @('n'); changed = @('list'); changedItem = @('label', 'value', 'default', 'unit')
    notApplicable = @('reason'); eventsUnchecked = @(); incidentNote = @(); noValue = @(); yes = @(); no = @(); reasonRights = @()
    reasonNotInstalled = @('label'); reasonNotInUse = @('label'); reasonAppNotInstalled = @('app'); reasonTimeout = @(); reasonError = @()
    reasonAbsent = @(); reasonSkipped = @('category'); reasonNotRecorded = @(); kindVendor = @(); kindPractice = @(); kindRule = @()
    environment = @(); eventsReach = @('from', 'boot'); appInstalled = @('app'); appNotInstalled = @('app'); appUnknown = @('app', 'reason')
    appInstalledLabel = @(); valueSet = @(); valueNotSet = @(); stateRead = @(); stateAbsent = @(); stateUnreadable = @('reason')
    stateNotApplicable = @('reason'); copyHead = @('server', 'date'); copyCheckTitle = @('area', 'title', 'grade'); copyAreaTitle = @('area', 'grade')
    copyAreaItem = @('title', 'grade', 'finding'); copyMeaning = @(); copyTodo = @(); copyStep = @('n', 'text', 'where', 'sign')
    copySource = @('kind', 'vendor', 'title', 'date'); copyOk = @('n')
}

function Get-WorkerPerfHealthFactTable([object[]]$Apps = @()) {
    # Every fact the catalogue can name: the read values, then the derived facts, then per application of $Apps
    # (Read-WorkerPerfHealthApps) that names installed, in the order of the list, apps.<key>.installed and one fact per
    # probe. id -> @{ Area; Type; Unit; Fields; Derived; Documented; Label }; Label is empty for the fixed facts (their
    # label is in values of the catalogue).
    $table = [ordered]@{}
    foreach ($id in $script:WorkerPerfHealthValues.Keys) {
        $v = $script:WorkerPerfHealthValues[$id]
        $table[$id] = @{ Area = $v.Area; Type = $v.Type; Unit = $v.Unit; Fields = $v.Fields; Derived = $false; Documented = [bool]$v.Documented; Label = '' }
    }
    foreach ($id in $script:WorkerPerfHealthDerived.Keys) {
        $v = $script:WorkerPerfHealthDerived[$id]
        $table[$id] = @{ Area = $v.Area; Type = $v.Type; Unit = $v.Unit; Fields = $v.Fields; Derived = $true; Documented = $true; Label = '' }
    }
    $dash = ' ' + [string][char]0x2013 + ' '
    foreach ($app in @($Apps)) {
        $installed = Get-WorkerPerfField $app 'installed'
        if ($null -eq $installed) { continue }
        $key = [string](Get-WorkerPerfField $app 'key'); $label = [string](Get-WorkerPerfField $app 'label')
        $table["apps.$key.installed"] = @{ Area = 'apps'; Type = 'bool'; Unit = ''; Fields = $null; Derived = $false
            Documented = [bool](Get-WorkerPerfField $installed 'documented'); Label = $label }
        foreach ($probe in @(Get-WorkerPerfField $app 'probes')) {
            if ($null -eq $probe) { continue }
            $table["apps.$key." + [string](Get-WorkerPerfField $probe 'id')] = @{ Area = 'apps'; Type = (Get-WorkerPerfAppFactType $probe); Unit = ''
                Fields = $null; Derived = $false; Documented = [bool](Get-WorkerPerfField $probe 'documented')
                Label = $label + $dash + [string](Get-WorkerPerfField $probe 'label') }
        }
    }
    return $table
}

function Stop-WorkerPerfHealthCatalogue([string]$Path, [string]$Part, [string]$Check, [string]$Field, [string]$Reason) {
    # Katalog '<Pfad>'[: Teil '<Teil>'][: Pruefung '<Kennung>'][: Feld '<Feld>'] <Grund>.
    $at = "Katalog '$Path'"
    if ($Part) { $at += ": Teil '$Part'" }
    if ($Check) { $at += ": Pruefung '$Check'" }
    if ($Field) { throw "${at}: Feld '$Field' $Reason." }
    throw "$at $Reason."
}

function Get-WorkerPerfHealthCatalogueMember($Object, [string]$Name) {
    # The property of a JSON object (also one holding an empty or one-element list), or $null when it is missing.
    # Names are compared ordinally.
    if ($null -eq $Object -or $Object -isnot [System.Management.Automation.PSCustomObject]) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $p.Name -cne $Name) { return $null }
    return $p
}

function Test-WorkerPerfHealthCatalogueObject($Value) {
    return ($null -ne $Value -and $Value -is [System.Management.Automation.PSCustomObject])
}

function Test-WorkerPerfHealthCatalogueText($Value) {
    # A text that is not empty.
    return ($Value -is [string] -and -not [string]::IsNullOrWhiteSpace($Value))
}

function Test-WorkerPerfHealthCatalogueNumber($Value) {
    # A finite JSON number (not a boolean, not a text).
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [decimal] -or $Value -is [int16] -or $Value -is [byte]) { return $true }
    if ($Value -is [double] -or $Value -is [single]) { return -not ([double]::IsNaN($Value) -or [double]::IsInfinity($Value)) }
    return $false
}

function Test-WorkerPerfHealthCatalogueDate($Value) {
    # A date of the catalogue's form YYYY-MM-DD, as a text. PowerShell 7 reads a JSON text with a time of day as a
    # DateTime; such a value never has this form, so both shells reject it alike.
    if ($Value -isnot [string] -or $Value -cnotmatch '^\d{4}-\d{2}-\d{2}\z') { return $false }
    $parsed = [datetime]::MinValue
    return [datetime]::TryParseExact($Value, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed)
}

function Get-WorkerPerfHealthCatalogueNames($Object) {
    # The property names of a JSON object, in their order.
    if (-not (Test-WorkerPerfHealthCatalogueObject $Object)) { return , @() }
    return , [string[]]@($Object.PSObject.Properties | ForEach-Object { $_.Name })
}

function Get-WorkerPerfHealthUnknownName($Object, [string[]]$Allowed) {
    # The first property name of a JSON object that is not one of $Allowed (compared exactly), or $null.
    foreach ($n in (Get-WorkerPerfHealthCatalogueNames $Object)) { if ($Allowed -cnotcontains $n) { return $n } }
    return $null
}

function Get-WorkerPerfHealthPlaceholders([string]$Text) {
    # The names inside braces of a text and whether a brace stands outside a placeholder.
    $names = @(foreach ($m in [regex]::Matches($Text, '\{([^{}]*)\}')) { $m.Groups[1].Value })
    $stray = ([regex]::Replace($Text, '\{([^{}]*)\}', '')).IndexOfAny([char[]]'{}') -ge 0
    return @{ Names = [string[]]$names; Stray = $stray }
}

function Get-WorkerPerfHealthThanKind($Than) {
    # The kind of a comparison value as the type table names it (none, bool, threshold, number, text, numbers, texts),
    # or what no condition takes: emptyList, mixedList (numbers and texts), badList, other.
    if ($null -eq $Than) { return 'none' }
    if ($Than -is [bool]) { return 'bool' }
    if ($Than -is [array]) {
        $items = @($Than); $numbers = 0; $texts = 0
        if ($items.Count -eq 0) { return 'emptyList' }
        foreach ($item in $items) {
            if (Test-WorkerPerfHealthCatalogueNumber $item) { $numbers++ } elseif ($item -is [string]) { $texts++ }
        }
        if ($numbers -eq $items.Count) { return 'numbers' }
        if ($texts -eq $items.Count) { return 'texts' }
        if ($numbers + $texts -eq $items.Count) { return 'mixedList' }
        return 'badList'
    }
    if ($Than -is [string]) { if ($Than.StartsWith('@', [StringComparison]::Ordinal)) { return 'threshold' }; return 'text' }
    if (Test-WorkerPerfHealthCatalogueNumber $Than) { return 'number' }
    return 'other'
}

function Get-WorkerPerfHealthOpType([string]$Type) {
    # The row of the type table for a fact type: every text:<name> except text:free is a text.
    if ($Type.StartsWith('text:', [StringComparison]::Ordinal) -and $Type -cne 'text:free') { return 'text' }
    return $Type
}

function Get-WorkerPerfHealthOpRule([string]$OpType) {
    # The row of the type table as one sentence, e.g. "eq, ne mit Ja/Nein-Wert; exists, absent ohne Vergleichswert".
    $row = $script:WorkerPerfHealthOpTable[$OpType]
    $groups = [ordered]@{}
    foreach ($op in $row.Keys) {
        $kinds = @($row[$op])
        $words = 'ohne Vergleichswert'
        if ($kinds -cnotcontains 'none') { $words = 'mit ' + (@(foreach ($k in $kinds) { $script:WorkerPerfHealthThanKindWords[$k] }) -join ' oder ') }
        if (-not $groups.Contains($words)) { $groups[$words] = New-Object 'System.Collections.Generic.List[string]' }
        $groups[$words].Add($op)
    }
    return (@(foreach ($w in $groups.Keys) { ($groups[$w] -join ', ') + ' ' + $w }) -join '; ')
}

function Test-WorkerPerfHealthCondition {
    # Checks condition $Index (counted from 1) of rule $Rule, notes the thresholds it names in $Ctx.UsedThresholds and
    # gives it every member of the returned shape. Returns whether it is a hard limit or an event condition.
    param($Ctx, [string]$Id, [string]$Rule, [int]$Index, $Condition, [string[]]$CheckValues)
    $path = $Ctx.Path
    $where = "Regel '$Rule', Bedingung ${Index}:"
    $stop = { param($Reason) Stop-WorkerPerfHealthCatalogue $path '' $Id 'rules' "$where $Reason" }
    if (-not (Test-WorkerPerfHealthCatalogueObject $Condition)) { & $stop 'ist kein Objekt' }
    $names = Get-WorkerPerfHealthCatalogueNames $Condition
    $hasValue = $names -ccontains 'value'; $hasEvent = $names -ccontains 'event'
    if ($hasValue -eq $hasEvent) { & $stop "braucht genau eines der Felder 'value' und 'event'" }
    $allowed = $script:WorkerPerfHealthCatalogueFields['valueCondition']
    if ($hasEvent) { $allowed = $script:WorkerPerfHealthCatalogueFields['eventCondition'] }
    $unknown = Get-WorkerPerfHealthUnknownName $Condition $allowed
    if ($null -ne $unknown) { & $stop "enthaelt das Feld '$unknown', das hier nicht gilt (erlaubt: $($allowed -join ', '))" }

    if ($hasEvent) {
        $kind = (Get-WorkerPerfHealthCatalogueMember $Condition 'event').Value
        if ($kind -isnot [string] -or $script:WorkerPerfHealthEventKinds -cnotcontains $kind) {
            & $stop "nennt die unbekannte Ereignisart '$kind' (erlaubt: $($script:WorkerPerfHealthEventKinds -join ', '))"
        }
        foreach ($f in 'min', 'days') {
            $m = Get-WorkerPerfHealthCatalogueMember $Condition $f
            if ($null -eq $m -or -not (Test-WorkerPerfHealthCatalogueNumber $m.Value) -or [double]$m.Value -lt 1 -or [double]$m.Value -ne [math]::Floor([double]$m.Value)) {
                & $stop "braucht in '$f' eine ganze Zahl ab 1"
            }
        }
        foreach ($f in 'value', 'op', 'than') { Set-WorkerPerfDefault $Condition $f $null }
        Set-WorkerPerfDefault $Condition 'hard' $false
        return $true
    }

    $fact = (Get-WorkerPerfHealthCatalogueMember $Condition 'value').Value
    if ($fact -isnot [string] -or $CheckValues -cnotcontains $fact) { & $stop "nennt den Fakt '$fact', der nicht in 'values' der Pruefung steht" }
    $type = [string]$Ctx.Facts[$fact].Type
    if ($type -ceq 'list') { & $stop "nennt den Listenwert '$fact'; eine Bedingung vergleicht keine Liste" }
    $m = Get-WorkerPerfHealthCatalogueMember $Condition 'op'
    $op = $null; if ($null -ne $m) { $op = $m.Value }
    if ($op -isnot [string] -or $script:WorkerPerfHealthOps -cnotcontains $op) {
        & $stop "nennt den unbekannten Operator '$op' (erlaubt: $($script:WorkerPerfHealthOps -join ', '))"
    }

    # the comparison value by its shape, then against the type table (ruling ZB-R25)
    $m = Get-WorkerPerfHealthCatalogueMember $Condition 'than'
    $than = $null; if ($null -ne $m) { $than = $m.Value }
    $thanKind = Get-WorkerPerfHealthThanKind $than
    if ($thanKind -ceq 'emptyList') { & $stop "nennt in 'than' eine leere Liste" }
    if ($thanKind -ceq 'mixedList') { & $stop "nennt in 'than' eine Liste, die Zahlen und Texte mischt" }
    if ($thanKind -ceq 'badList') { & $stop "nennt in der Liste von 'than' einen Eintrag, der weder Zahl noch Text ist" }
    if ($thanKind -ceq 'other') { & $stop "nennt in 'than' weder Zahl, Text, Ja/Nein-Wert, Liste noch Schwelle" }
    if ($thanKind -ceq 'threshold') {
        $threshold = $than.Substring(1)
        if ($Ctx.Thresholds -cnotcontains $threshold) { & $stop "nennt die unbekannte Schwelle '$than'" }
        $null = $Ctx.UsedThresholds.Add($threshold)
    }
    $opType = Get-WorkerPerfHealthOpType $type
    if (-not $script:WorkerPerfHealthOpTable.Contains($opType)) { & $stop "nennt den Fakt '$fact' vom Typ '$type', fuer den keine Bedingung gilt" }
    $kinds = $script:WorkerPerfHealthOpTable[$opType][$op]
    if ($null -eq $kinds) {
        & $stop "vergleicht '$fact' (Typ '$type') mit '$op'; erlaubt bei diesem Typ: $(Get-WorkerPerfHealthOpRule $opType)"
    }
    $kinds = @($kinds)
    if ($kinds -ccontains 'none' -and $thanKind -cne 'none') { & $stop "braucht bei '$op' kein 'than'" }
    if ($kinds -cnotcontains 'none' -and $thanKind -ceq 'none') { & $stop "braucht bei '$op' einen Vergleichswert in 'than'" }
    if ($kinds -cnotcontains $thanKind) {
        & $stop "vergleicht '$fact' (Typ '$type') mit '$op' und $($script:WorkerPerfHealthThanKindWords[$thanKind]); erlaubt bei diesem Typ: $(Get-WorkerPerfHealthOpRule $opType)"
    }

    $m = Get-WorkerPerfHealthCatalogueMember $Condition 'hard'
    if ($null -ne $m -and $m.Value -isnot [bool]) { & $stop "nennt in 'hard' keinen Wahrheitswert" }
    $hard = ($null -ne $m -and $m.Value)
    Set-WorkerPerfDefault $Condition 'than' $null
    Set-WorkerPerfDefault $Condition 'hard' $false
    foreach ($f in 'event', 'min', 'days') { Set-WorkerPerfDefault $Condition $f $null }
    return [bool]$hard
}

function Test-WorkerPerfHealthCheckValues($Ctx, [string]$Id, [string]$Area, $Check) {
    # values of a check: known facts with a documented source, each once. In the area apps only facts of one application
    # of the list (the application is checked before the fact); in any other area no fact of an application.
    $path = $Ctx.Path
    $m = Get-WorkerPerfHealthCatalogueMember $Check 'values'
    if ($null -eq $m) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'values' 'fehlt' }
    if ($m.Value -isnot [array] -or @($m.Value).Count -eq 0) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'values' 'ist keine Liste mit mindestens einem Fakt' }
    $values = @($m.Value)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $appOfCheck = ''
    foreach ($fact in $values) {
        if (-not (Test-WorkerPerfHealthCatalogueText $fact)) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'values' 'enthaelt einen Eintrag, der kein Text ist oder leer ist' }
        if (-not $seen.Add($fact)) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'values' "nennt '$fact' mehr als einmal" }
        $isAppFact = $fact.StartsWith('apps.', [StringComparison]::Ordinal)
        if ($Area -ceq 'apps') {
            $parts = $fact.Split('.')
            if (-not $isAppFact -or $parts.Count -ne 3) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'values' "'$fact' ist kein Wert einer Anwendung" }
            $key = $parts[1]
            if ($Ctx.AppKeys -cnotcontains $key) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'values' "Anwendung '$key' steht nicht in der Anwendungsliste ('$fact')" }
            if ($appOfCheck -and $appOfCheck -cne $key) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'values' "nennt Werte von mehr als einer Anwendung ('$appOfCheck', '$key')" }
            $appOfCheck = $key
        }
        elseif ($isAppFact) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'values' "'$fact' gehoert in den Bereich apps" }
        if (-not $Ctx.FactIds.Contains($fact)) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'values' "nennt den unbekannten Fakt '$fact'" }
        if (-not $Ctx.Facts[$fact].Documented) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'values' "'$fact' hat keine dokumentierte Lesequelle" }
    }
    return , [string[]]$values
}

function Test-WorkerPerfHealthRules($Ctx, [string]$Id, $Check, [string[]]$CheckValues) {
    # rules: at least one of check and act (check is checked first), each a list of conditions; act needs a hard limit
    # or an event condition. An absent rule becomes an empty list. Returns the names of the rules the catalogue gives.
    $path = $Ctx.Path
    $m = Get-WorkerPerfHealthCatalogueMember $Check 'rules'
    if ($null -eq $m) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'rules' 'fehlt' }
    $rules = $m.Value
    if (-not (Test-WorkerPerfHealthCatalogueObject $rules)) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'rules' 'ist kein Objekt' }
    $ruleNames = Get-WorkerPerfHealthCatalogueNames $rules
    $unknown = Get-WorkerPerfHealthUnknownName $rules $script:WorkerPerfHealthCatalogueFields['rules']
    if ($null -ne $unknown) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'rules' "nennt die unbekannte Regel '$unknown' (erlaubt: check, act)" }
    if ($ruleNames.Count -eq 0) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'rules' "braucht mindestens eine der Regeln 'check' und 'act'" }
    foreach ($rule in 'check', 'act') {
        if ($ruleNames -cnotcontains $rule) {
            Add-Member -InputObject $rules -MemberType NoteProperty -Name $rule -Value ([object[]]@())
            continue
        }
        $list = (Get-WorkerPerfHealthCatalogueMember $rules $rule).Value
        if ($list -isnot [array] -or @($list).Count -eq 0) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'rules' "Regel '$rule' ist keine Liste mit mindestens einer Bedingung" }
        $conditions = @($list)
        $hardOrEvent = $false
        for ($i = 0; $i -lt $conditions.Count; $i++) {
            if (Test-WorkerPerfHealthCondition $Ctx $Id $rule ($i + 1) $conditions[$i] $CheckValues) { $hardOrEvent = $true }
        }
        if ($rule -ceq 'act' -and -not $hardOrEvent) {
            Stop-WorkerPerfHealthCatalogue $path '' $Id 'rules' "Regel 'act' braucht eine Bedingung mit 'hard': true (harte Grenze) oder eine Bedingung 'event' (Ereignis)"
        }
    }
    return , [string[]]$ruleNames
}

function Test-WorkerPerfHealthFindings($Ctx, [string]$Id, $Check, [string[]]$RuleNames, [string[]]$CheckValues) {
    # findings: ok and unknown, check and act exactly for the rules the check has; placeholders only facts of values
    # (no list, no free server text), known thresholds and {reason} (only in unknown, and always there). A sentence
    # without its rule is missing in the catalogue and becomes ''.
    $path = $Ctx.Path
    $m = Get-WorkerPerfHealthCatalogueMember $Check 'findings'
    if ($null -eq $m) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'findings' 'fehlt' }
    $findings = $m.Value
    if (-not (Test-WorkerPerfHealthCatalogueObject $findings)) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'findings' 'ist kein Objekt' }
    $findingNames = Get-WorkerPerfHealthCatalogueNames $findings
    $unknown = Get-WorkerPerfHealthUnknownName $findings $script:WorkerPerfHealthCatalogueFields['findings']
    if ($null -ne $unknown) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'findings' "nennt den unbekannten Satz '$unknown' (erlaubt: ok, check, act, unknown)" }
    foreach ($s in $script:WorkerPerfHealthCatalogueFields['findings']) {
        $required = @('ok', 'unknown') -ccontains $s -or $RuleNames -ccontains $s
        if ($findingNames -cnotcontains $s) {
            if ($required) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'findings' "braucht den Satz '$s'" }
            Add-Member -InputObject $findings -MemberType NoteProperty -Name $s -Value ''
            continue
        }
        if (-not $required) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'findings' "nennt den Satz '$s', aber die Pruefung hat keine Regel '$s'" }
        $text = (Get-WorkerPerfHealthCatalogueMember $findings $s).Value
        if ($text -isnot [string]) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'findings' "Satz '$s' ist kein Text" }
        if ([string]::IsNullOrWhiteSpace($text)) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'findings' "Satz '$s' ist leer" }
        $ph = Get-WorkerPerfHealthPlaceholders $text
        if ($ph.Stray) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'findings' "Satz '$s' enthaelt eine geschweifte Klammer ohne Platzhalter" }
        foreach ($name in $ph.Names) {
            $shown = '{' + $name + '}'
            if ($name -ceq 'reason') {
                if ($s -cne 'unknown') { Stop-WorkerPerfHealthCatalogue $path '' $Id 'findings' "Satz '$s' enthaelt den Platzhalter '$shown', der nur in 'unknown' steht" }
            }
            elseif ($name.StartsWith('@', [StringComparison]::Ordinal)) {
                if ($Ctx.Thresholds -cnotcontains $name.Substring(1)) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'findings' "Satz '$s' enthaelt den Platzhalter '$shown' einer unbekannten Schwelle" }
                $null = $Ctx.UsedThresholds.Add($name.Substring(1))
            }
            elseif ($CheckValues -cnotcontains $name) {
                Stop-WorkerPerfHealthCatalogue $path '' $Id 'findings' "Satz '$s' enthaelt den Platzhalter '$shown', der kein Fakt aus 'values' der Pruefung ist"
            }
            elseif ($Ctx.Facts[$name].Type -ceq 'list') { Stop-WorkerPerfHealthCatalogue $path '' $Id 'findings' "Satz '$s' enthaelt den Platzhalter '$shown' eines Listenwerts" }
            elseif ($Ctx.Facts[$name].Type -ceq 'text:free') { Stop-WorkerPerfHealthCatalogue $path '' $Id 'findings' "Satz '$s' enthaelt den Platzhalter '$shown' eines freien Servertexts" }
        }
        if ($s -ceq 'unknown' -and $ph.Names -cnotcontains 'reason') { Stop-WorkerPerfHealthCatalogue $path '' $Id 'findings' "Satz 'unknown' enthaelt den Platzhalter '{reason}' nicht" }
    }
}

function Test-WorkerPerfHealthTodo($Ctx, [string]$Id, $Check) {
    # todo: at least one step, each with text, where and sign and nothing else.
    $path = $Ctx.Path
    $m = Get-WorkerPerfHealthCatalogueMember $Check 'todo'
    if ($null -eq $m) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'todo' 'fehlt' }
    if ($m.Value -isnot [array] -or @($m.Value).Count -eq 0) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'todo' 'ist keine Liste mit mindestens einem Schritt' }
    $steps = @($m.Value)
    $allowed = $script:WorkerPerfHealthCatalogueFields['step']
    for ($i = 0; $i -lt $steps.Count; $i++) {
        $step = $steps[$i]; $n = $i + 1
        if (-not (Test-WorkerPerfHealthCatalogueObject $step)) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'todo' "Schritt $n ist kein Objekt" }
        $unknown = Get-WorkerPerfHealthUnknownName $step $allowed
        if ($null -ne $unknown) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'todo' "Schritt ${n}: nennt das unbekannte Feld '$unknown' (erlaubt: $($allowed -join ', '))" }
        foreach ($f in $allowed) {
            $sm = Get-WorkerPerfHealthCatalogueMember $step $f
            if ($null -eq $sm) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'todo' "Schritt ${n}: '$f' fehlt" }
            if (-not (Test-WorkerPerfHealthCatalogueText $sm.Value)) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'todo' "Schritt ${n}: '$f' ist kein Text oder leer" }
        }
    }
}

function Test-WorkerPerfHealthSource($Ctx, [string]$Id, $Check) {
    # source: vendor, title, date (YYYY-MM-DD), url (an address, required for the kinds vendor and practice; '' when
    # not given), nothing else. The kind itself is checked after the source.
    $path = $Ctx.Path
    $km = Get-WorkerPerfHealthCatalogueMember $Check 'kind'
    $kind = ''; if ($null -ne $km -and $km.Value -is [string]) { $kind = $km.Value }
    $m = Get-WorkerPerfHealthCatalogueMember $Check 'source'
    if ($null -eq $m) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'source' 'fehlt' }
    $source = $m.Value
    if (-not (Test-WorkerPerfHealthCatalogueObject $source)) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'source' 'ist kein Objekt' }
    $allowed = $script:WorkerPerfHealthCatalogueFields['source']
    $unknown = Get-WorkerPerfHealthUnknownName $source $allowed
    if ($null -ne $unknown) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'source' "nennt das unbekannte Feld '$unknown' (erlaubt: $($allowed -join ', '))" }
    foreach ($f in 'vendor', 'title') {
        $sm = Get-WorkerPerfHealthCatalogueMember $source $f
        if ($null -eq $sm -or -not (Test-WorkerPerfHealthCatalogueText $sm.Value)) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'source' "'$f' fehlt, ist kein Text oder leer" }
    }
    $dm = Get-WorkerPerfHealthCatalogueMember $source 'date'
    if ($null -eq $dm) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'source' "'date' fehlt" }
    if (-not (Test-WorkerPerfHealthCatalogueDate $dm.Value)) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'source' "'date' ist kein Datum der Form JJJJ-MM-TT" }
    $um = Get-WorkerPerfHealthCatalogueMember $source 'url'
    if ($null -ne $um -and $um.Value -isnot [string]) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'source' "'url' ist kein Text" }
    if (@('vendor', 'practice') -ccontains $kind) {
        if ($null -eq $um -or [string]::IsNullOrWhiteSpace($um.Value)) { Stop-WorkerPerfHealthCatalogue $path '' $Id 'source' "'url' fehlt oder ist leer (Pflicht bei der Art '$kind')" }
        if ($um.Value -cnotmatch '^https?://\S+\z') { Stop-WorkerPerfHealthCatalogue $path '' $Id 'source' "'url' ist keine Adresse (http:// oder https://)" }
    }
    Set-WorkerPerfDefault $source 'url' ''
}

function Test-WorkerPerfHealthCheck($Ctx, [int]$Index, $Check) {
    # Checks one check of the catalogue in the order of the brief (id, area, title, meaning, values, rules, findings,
    # todo, source, kind, relates); the first violation stops. Notes the id and the kind in $Ctx.
    $path = $Ctx.Path
    if (-not (Test-WorkerPerfHealthCatalogueObject $Check)) { Stop-WorkerPerfHealthCatalogue $path '' "checks[$Index]" '' 'ist kein Objekt' }
    $m = Get-WorkerPerfHealthCatalogueMember $Check 'id'
    if ($null -eq $m -or -not (Test-WorkerPerfHealthCatalogueText $m.Value)) { Stop-WorkerPerfHealthCatalogue $path '' "checks[$Index]" 'id' 'fehlt, ist kein Text oder leer' }
    $id = $m.Value
    if ($Ctx.Ids.ContainsKey($id)) {
        $other = $Ctx.Ids[$id]
        if ($other -ceq $id) { Stop-WorkerPerfHealthCatalogue $path '' $id 'id' 'ist doppelt' }
        Stop-WorkerPerfHealthCatalogue $path '' $id 'id' "unterscheidet sich von der Pruefung '$other' nur in Gross- und Kleinschreibung"
    }
    $Ctx.Ids[$id] = $id
    $allowed = $script:WorkerPerfHealthCatalogueFields['check']
    $unknown = Get-WorkerPerfHealthUnknownName $Check $allowed
    if ($null -ne $unknown) { Stop-WorkerPerfHealthCatalogue $path '' $id $unknown "ist unbekannt (erlaubt: $($allowed -join ', '))" }

    $m = Get-WorkerPerfHealthCatalogueMember $Check 'area'
    if ($null -eq $m) { Stop-WorkerPerfHealthCatalogue $path '' $id 'area' 'fehlt' }
    $area = $m.Value
    if ($area -isnot [string] -or $script:WorkerPerfHealthAreas -cnotcontains $area) { Stop-WorkerPerfHealthCatalogue $path '' $id 'area' "nennt den unbekannten Bereich '$area'" }

    foreach ($f in 'title', 'meaning') {
        $m = Get-WorkerPerfHealthCatalogueMember $Check $f
        if ($null -eq $m) { Stop-WorkerPerfHealthCatalogue $path '' $id $f 'fehlt' }
        if ($m.Value -isnot [string]) { Stop-WorkerPerfHealthCatalogue $path '' $id $f 'ist kein Text' }
        if ([string]::IsNullOrWhiteSpace($m.Value)) { Stop-WorkerPerfHealthCatalogue $path '' $id $f 'ist leer' }
    }

    $checkValues = Test-WorkerPerfHealthCheckValues $Ctx $id $area $Check
    $ruleNames = Test-WorkerPerfHealthRules $Ctx $id $Check $checkValues
    Test-WorkerPerfHealthFindings $Ctx $id $Check $ruleNames $checkValues
    Test-WorkerPerfHealthTodo $Ctx $id $Check
    Test-WorkerPerfHealthSource $Ctx $id $Check

    $km = Get-WorkerPerfHealthCatalogueMember $Check 'kind'
    if ($null -eq $km) { Stop-WorkerPerfHealthCatalogue $path '' $id 'kind' 'fehlt' }
    if ($km.Value -isnot [string] -or $script:WorkerPerfHealthKinds -cnotcontains $km.Value) {
        Stop-WorkerPerfHealthCatalogue $path '' $id 'kind' "nennt die unbekannte Art '$($km.Value)' (erlaubt: $($script:WorkerPerfHealthKinds -join ', '))"
    }
    $Ctx.Kinds[$id] = $km.Value

    # relates: situations of the guided report and pattern.<id>
    $m = Get-WorkerPerfHealthCatalogueMember $Check 'relates'
    if ($null -eq $m) { Stop-WorkerPerfHealthCatalogue $path '' $id 'relates' 'fehlt' }
    if ($m.Value -isnot [array]) { Stop-WorkerPerfHealthCatalogue $path '' $id 'relates' 'ist keine Liste' }
    foreach ($relate in @($m.Value)) {
        $known = $relate -is [string] -and ($script:WorkerPerfSituations -ccontains $relate -or
            ($relate.StartsWith('pattern.', [StringComparison]::Ordinal) -and $script:WorkerPerfPatternOrder -ccontains $relate.Substring(8)))
        if (-not $known) { Stop-WorkerPerfHealthCatalogue $path '' $id 'relates' "nennt den unbekannten Bezug '$relate'" }
    }
}

function Test-WorkerPerfHealthAreas([string]$Path, $Areas) {
    # areas: the eleven ids in their order, each with label and notCovered (a text, may be empty) and nothing else.
    $expected = $script:WorkerPerfHealthAreas -join ', '
    if ($Areas -isnot [array]) { Stop-WorkerPerfHealthCatalogue $Path 'areas' '' '' 'ist keine Liste' }
    $areaList = @($Areas)
    $ids = @(foreach ($a in $areaList) { $m = Get-WorkerPerfHealthCatalogueMember $a 'id'; if ($null -ne $m) { [string]$m.Value } else { '' } })
    if ($areaList.Count -ne $script:WorkerPerfHealthAreas.Count -or ($ids -join ', ') -cne $expected) {
        Stop-WorkerPerfHealthCatalogue $Path 'areas' '' '' "nennt nicht die elf Bereiche in ihrer Reihenfolge ($expected)"
    }
    $allowed = $script:WorkerPerfHealthCatalogueFields['area']
    for ($i = 0; $i -lt $areaList.Count; $i++) {
        $a = $areaList[$i]; $aid = $ids[$i]
        $unknown = Get-WorkerPerfHealthUnknownName $a $allowed
        if ($null -ne $unknown) { Stop-WorkerPerfHealthCatalogue $Path 'areas' '' '' "nennt beim Bereich '$aid' das unbekannte Feld '$unknown' (erlaubt: $($allowed -join ', '))" }
        $m = Get-WorkerPerfHealthCatalogueMember $a 'label'
        if ($null -eq $m -or -not (Test-WorkerPerfHealthCatalogueText $m.Value)) { Stop-WorkerPerfHealthCatalogue $Path 'areas' '' '' "nennt beim Bereich '$aid' keine Bezeichnung in 'label'" }
        $m = Get-WorkerPerfHealthCatalogueMember $a 'notCovered'
        if ($null -eq $m -or $m.Value -isnot [string]) { Stop-WorkerPerfHealthCatalogue $Path 'areas' '' '' "nennt beim Bereich '$aid' keinen Text in 'notCovered'" }
    }
}

function Test-WorkerPerfHealthGrades([string]$Path, $Grades) {
    # grades: the four grades and the result na, each with word and symbol and nothing else.
    if (-not (Test-WorkerPerfHealthCatalogueObject $Grades)) { Stop-WorkerPerfHealthCatalogue $Path 'grades' '' '' 'ist kein Objekt' }
    $gradeKeys = @($script:WorkerPerfHealthGrades) + 'na'
    $unknown = Get-WorkerPerfHealthUnknownName $Grades $gradeKeys
    if ($null -ne $unknown) { Stop-WorkerPerfHealthCatalogue $Path 'grades' '' '' "nennt die unbekannte Einstufung '$unknown'" }
    $allowed = $script:WorkerPerfHealthCatalogueFields['grade']
    foreach ($g in $gradeKeys) {
        $gm = Get-WorkerPerfHealthCatalogueMember $Grades $g
        if ($null -eq $gm) { Stop-WorkerPerfHealthCatalogue $Path 'grades' '' '' "hat keinen Eintrag '$g'" }
        if (-not (Test-WorkerPerfHealthCatalogueObject $gm.Value)) { Stop-WorkerPerfHealthCatalogue $Path 'grades' '' '' "nennt bei '$g' kein Objekt" }
        $unknown = Get-WorkerPerfHealthUnknownName $gm.Value $allowed
        if ($null -ne $unknown) { Stop-WorkerPerfHealthCatalogue $Path 'grades' '' '' "nennt bei '$g' das unbekannte Feld '$unknown' (erlaubt: $($allowed -join ', '))" }
        foreach ($f in $allowed) {
            $m = Get-WorkerPerfHealthCatalogueMember $gm.Value $f
            if ($null -eq $m -or -not (Test-WorkerPerfHealthCatalogueText $m.Value)) { Stop-WorkerPerfHealthCatalogue $Path 'grades' '' '' "nennt bei '$g' keinen Text in '$f'" }
        }
    }
}

function Test-WorkerPerfHealthThresholds([string]$Path, $Thresholds) {
    # thresholds: each with numbers value and default, texts unit and label and nothing else; the required ones present.
    # (Two names that differ only in case never get here: the JSON reader of both shells rejects such a file.)
    # Returns the names.
    if (-not (Test-WorkerPerfHealthCatalogueObject $Thresholds)) { Stop-WorkerPerfHealthCatalogue $Path 'thresholds' '' '' 'ist kein Objekt' }
    $thresholdIds = Get-WorkerPerfHealthCatalogueNames $Thresholds
    $allowed = $script:WorkerPerfHealthCatalogueFields['threshold']
    foreach ($t in $thresholdIds) {
        $entry = (Get-WorkerPerfHealthCatalogueMember $Thresholds $t).Value
        if ($t -cnotmatch '^[A-Za-z][A-Za-z0-9]*\z') { Stop-WorkerPerfHealthCatalogue $Path 'thresholds' '' '' "nennt die Schwelle '$t'; ein Name besteht nur aus Buchstaben und Ziffern" }
        if (-not (Test-WorkerPerfHealthCatalogueObject $entry)) { Stop-WorkerPerfHealthCatalogue $Path 'thresholds' '' '' "nennt bei der Schwelle '$t' kein Objekt" }
        $unknown = Get-WorkerPerfHealthUnknownName $entry $allowed
        if ($null -ne $unknown) { Stop-WorkerPerfHealthCatalogue $Path 'thresholds' '' '' "nennt bei der Schwelle '$t' das unbekannte Feld '$unknown' (erlaubt: $($allowed -join ', '))" }
        foreach ($f in 'value', 'default') {
            $tm = Get-WorkerPerfHealthCatalogueMember $entry $f
            if ($null -eq $tm -or -not (Test-WorkerPerfHealthCatalogueNumber $tm.Value)) { Stop-WorkerPerfHealthCatalogue $Path 'thresholds' '' '' "nennt bei der Schwelle '$t' keine Zahl in '$f'" }
        }
        $tm = Get-WorkerPerfHealthCatalogueMember $entry 'unit'
        if ($null -eq $tm -or $tm.Value -isnot [string]) { Stop-WorkerPerfHealthCatalogue $Path 'thresholds' '' '' "nennt bei der Schwelle '$t' keinen Text in 'unit'" }
        $tm = Get-WorkerPerfHealthCatalogueMember $entry 'label'
        if ($null -eq $tm -or -not (Test-WorkerPerfHealthCatalogueText $tm.Value)) { Stop-WorkerPerfHealthCatalogue $Path 'thresholds' '' '' "nennt bei der Schwelle '$t' keine Bezeichnung in 'label'" }
    }
    foreach ($t in $script:WorkerPerfHealthRequiredThresholds) {
        if ($thresholdIds -cnotcontains $t) { Stop-WorkerPerfHealthCatalogue $Path 'thresholds' '' '' "hat keine Schwelle '$t'" }
    }
    return , [string[]]$thresholdIds
}

function Test-WorkerPerfHealthValueLabels([string]$Path, $Labels) {
    # values: a label for each fixed fact and no other id (the label of an application's value is in the application list).
    $fixed = @(@($script:WorkerPerfHealthValues.Keys) + @($script:WorkerPerfHealthDerived.Keys))
    if (-not (Test-WorkerPerfHealthCatalogueObject $Labels)) { Stop-WorkerPerfHealthCatalogue $Path 'values' '' '' 'ist kein Objekt' }
    $unknown = Get-WorkerPerfHealthUnknownName $Labels $fixed
    if ($null -ne $unknown) { Stop-WorkerPerfHealthCatalogue $Path 'values' '' '' "nennt die unbekannte Kennung '$unknown' (die Bezeichnung eines Anwendungswerts steht in der Anwendungsliste)" }
    foreach ($id in $fixed) {
        $m = Get-WorkerPerfHealthCatalogueMember $Labels $id
        if ($null -eq $m) { Stop-WorkerPerfHealthCatalogue $Path 'values' '' '' "nennt keine Bezeichnung fuer '$id'" }
        if (-not (Test-WorkerPerfHealthCatalogueText $m.Value)) { Stop-WorkerPerfHealthCatalogue $Path 'values' '' '' "nennt fuer '$id' eine leere Bezeichnung" }
    }
}

function Test-WorkerPerfHealthCopy([string]$Path, $Copy) {
    # copy: every required text and no other, each with only its placeholders.
    if (-not (Test-WorkerPerfHealthCatalogueObject $Copy)) { Stop-WorkerPerfHealthCatalogue $Path 'copy' '' '' 'ist kein Objekt' }
    $unknown = Get-WorkerPerfHealthUnknownName $Copy ([string[]]@($script:WorkerPerfHealthCopyKeys.Keys))
    if ($null -ne $unknown) { Stop-WorkerPerfHealthCatalogue $Path 'copy' '' '' "nennt den unbekannten Text '$unknown'" }
    foreach ($k in $script:WorkerPerfHealthCopyKeys.Keys) {
        $m = Get-WorkerPerfHealthCatalogueMember $Copy $k
        if ($null -eq $m) { Stop-WorkerPerfHealthCatalogue $Path 'copy' '' '' "hat keinen Text '$k'" }
        $text = $m.Value
        if (-not (Test-WorkerPerfHealthCatalogueText $text)) { Stop-WorkerPerfHealthCatalogue $Path 'copy' '' '' "Text '$k' ist kein Text oder leer" }
        $ph = Get-WorkerPerfHealthPlaceholders $text
        if ($ph.Stray) { Stop-WorkerPerfHealthCatalogue $Path 'copy' '' '' "Text '$k' enthaelt eine geschweifte Klammer ohne Platzhalter" }
        foreach ($name in $ph.Names) {
            if (@($script:WorkerPerfHealthCopyKeys[$k]) -cnotcontains $name) {
                Stop-WorkerPerfHealthCatalogue $Path 'copy' '' '' ("Text '$k' enthaelt den Platzhalter '{" + $name + "}', der dort nicht erlaubt ist")
            }
        }
    }
}

function Test-WorkerPerfHealthPrecedence($Ctx, $Precedence) {
    # precedence (checked after the checks): the exceptions of the client, in which the practice source wins over the
    # vendor. A list, also empty; each entry names a check of kind practice once, winner practice and a reason.
    $path = $Ctx.Path
    if ($Precedence -isnot [array]) { Stop-WorkerPerfHealthCatalogue $path 'precedence' '' '' 'ist keine Liste' }
    $named = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $allowed = $script:WorkerPerfHealthCatalogueFields['precedence']
    $entries = @($Precedence)
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $entry = $entries[$i]
        if (-not (Test-WorkerPerfHealthCatalogueObject $entry)) { Stop-WorkerPerfHealthCatalogue $path 'precedence' '' '' "Eintrag $($i + 1) ist kein Objekt" }
        $cm = Get-WorkerPerfHealthCatalogueMember $entry 'check'
        if ($null -eq $cm -or -not (Test-WorkerPerfHealthCatalogueText $cm.Value)) { Stop-WorkerPerfHealthCatalogue $path 'precedence' '' '' "Eintrag $($i + 1) nennt keine Pruefung in 'check'" }
        $id = $cm.Value
        $unknown = Get-WorkerPerfHealthUnknownName $entry $allowed
        if ($null -ne $unknown) { Stop-WorkerPerfHealthCatalogue $path 'precedence' $id $unknown "ist unbekannt (erlaubt: $($allowed -join ', '))" }
        if (-not $Ctx.Kinds.ContainsKey($id)) { Stop-WorkerPerfHealthCatalogue $path 'precedence' $id '' 'unbekannt' }
        if (-not $named.Add($id)) { Stop-WorkerPerfHealthCatalogue $path 'precedence' $id '' 'steht mehr als einmal in der Liste' }
        $wm = Get-WorkerPerfHealthCatalogueMember $entry 'winner'
        if ($null -eq $wm) { Stop-WorkerPerfHealthCatalogue $path 'precedence' $id 'winner' 'fehlt' }
        if ($wm.Value -isnot [string] -or $wm.Value -cne 'practice') { Stop-WorkerPerfHealthCatalogue $path 'precedence' $id 'winner' "nennt '$($wm.Value)'; erlaubt ist nur 'practice'" }
        $rm = Get-WorkerPerfHealthCatalogueMember $entry 'reason'
        if ($null -eq $rm) { Stop-WorkerPerfHealthCatalogue $path 'precedence' $id 'reason' 'fehlt' }
        if (-not (Test-WorkerPerfHealthCatalogueText $rm.Value)) { Stop-WorkerPerfHealthCatalogue $path 'precedence' $id 'reason' 'ist leer' }
        if ($Ctx.Kinds[$id] -cne 'practice') { Stop-WorkerPerfHealthCatalogue $path 'precedence' $id '' "hat nicht die Art 'practice'" }
    }
}

function Read-WorkerPerfHealthCatalogue([string]$Path, [object[]]$Apps = @()) {
    # Reads the catalogue of the health picture and checks every part (a faulty catalogue never rates silently).
    # Apps: the application list (Read-WorkerPerfHealthApps); the facts of its applications are known to the checks
    # of the area apps. The first error stops with a message that names part, or check and field. Every member name
    # is compared exactly; a member the loader does not know is rejected.
    # Returns the catalogue as read, with every optional member set, so that dot access works under StrictMode 2
    # (every list is an array, also with one entry or none):
    #   version      text YYYY-MM-DD
    #   areas[]      id, label, notCovered
    #   grades       ok, check, act, unknown, na: each word, symbol
    #   thresholds   <name>: value, default, unit, label
    #   values       <fact>: label
    #   copy         <key>: text
    #   precedence[] check, winner, reason
    #   checks[]     id, area, title, meaning, kind, values[], relates[],
    #                rules: check[], act[] (a rule the catalogue does not give is an empty list), each condition with
    #                  value, op, than, hard, event, min, days: a value condition has event, min, days $null, than $null
    #                  with exists and absent, hard $false when not given; an event condition has value, op, than $null
    #                  and hard $false,
    #                findings: ok, check, act, unknown ('' for check or act without their rule),
    #                todo[]: text, where, sign, source: vendor, title, url ('' when not given), date
    #   appList      = $Apps
    if ($null -eq (Get-Variable -Name 'WorkerPerfSituations' -Scope Script -ErrorAction SilentlyContinue)) {
        throw "Katalog '$Path': die Situationen fehlen; WorkerPerf.Guidance.ps1 muss vor dem Laden des Katalogs eingebunden sein."
    }
    if ($null -eq (Get-Variable -Name 'WorkerPerfPatternOrder' -Scope Script -ErrorAction SilentlyContinue)) {
        throw "Katalog '$Path': die Muster fehlen; WorkerPerf.Events.ps1 muss vor dem Laden des Katalogs eingebunden sein."
    }
    if ($null -eq $Apps) { $Apps = @() }
    $cat = ConvertFrom-WorkerPerfJsonFile $Path
    if (-not (Test-WorkerPerfHealthCatalogueObject $cat)) { throw "Katalog '$Path' ist kein JSON-Objekt." }
    $partNames = Get-WorkerPerfHealthCatalogueNames $cat
    foreach ($part in $script:WorkerPerfHealthCatalogueParts) {
        if ($partNames -cnotcontains $part) { Stop-WorkerPerfHealthCatalogue $Path $part '' '' 'fehlt' }
    }
    $unknown = Get-WorkerPerfHealthUnknownName $cat $script:WorkerPerfHealthCatalogueParts
    if ($null -ne $unknown) { Stop-WorkerPerfHealthCatalogue $Path $unknown '' '' 'ist unbekannt' }
    if (-not (Test-WorkerPerfHealthCatalogueDate (Get-WorkerPerfHealthCatalogueMember $cat 'version').Value)) { Stop-WorkerPerfHealthCatalogue $Path 'version' '' '' 'ist kein Datum der Form JJJJ-MM-TT' }
    Test-WorkerPerfHealthAreas $Path (Get-WorkerPerfHealthCatalogueMember $cat 'areas').Value
    Test-WorkerPerfHealthGrades $Path (Get-WorkerPerfHealthCatalogueMember $cat 'grades').Value
    $thresholdIds = Test-WorkerPerfHealthThresholds $Path (Get-WorkerPerfHealthCatalogueMember $cat 'thresholds').Value
    Test-WorkerPerfHealthValueLabels $Path (Get-WorkerPerfHealthCatalogueMember $cat 'values').Value
    Test-WorkerPerfHealthCopy $Path (Get-WorkerPerfHealthCatalogueMember $cat 'copy').Value

    $facts = Get-WorkerPerfHealthFactTable $Apps
    $factIds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($k in $facts.Keys) { $null = $factIds.Add($k) }
    $ctx = @{ Path = $Path; Facts = $facts; FactIds = $factIds; Thresholds = [string[]]$thresholdIds
        AppKeys = [string[]]@(foreach ($app in $Apps) { [string](Get-WorkerPerfField $app 'key') })
        UsedThresholds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        Ids = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
        Kinds = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal) }

    $checks = (Get-WorkerPerfHealthCatalogueMember $cat 'checks').Value
    if ($checks -isnot [array]) { Stop-WorkerPerfHealthCatalogue $Path 'checks' '' '' 'ist keine Liste' }
    $checkList = @($checks)
    for ($i = 0; $i -lt $checkList.Count; $i++) { Test-WorkerPerfHealthCheck $ctx $i $checkList[$i] }
    Test-WorkerPerfHealthPrecedence $ctx (Get-WorkerPerfHealthCatalogueMember $cat 'precedence').Value

    # a threshold that nothing uses is a typo or a leftover
    foreach ($t in $thresholdIds) {
        if (-not $ctx.UsedThresholds.Contains($t) -and $script:WorkerPerfHealthRequiredThresholds -cnotcontains $t) {
            Stop-WorkerPerfHealthCatalogue $Path 'thresholds' '' '' "nennt die Schwelle '$t', die weder eine Regel noch ein Befundsatz nutzt"
        }
    }

    Add-Member -InputObject $cat -MemberType NoteProperty -Name 'appList' -Value ([object[]]@($Apps))
    return $cat
}

function Get-WorkerPerfHealthChangedThresholds($Catalogue) {
    # The thresholds whose value differs from their default, in the order of the catalogue:
    # [ordered]@{ id; label; value; default; unit } each. Plain pipeline output (the caller writes @(...)).
    foreach ($p in @((Get-WorkerPerfField $Catalogue 'thresholds').PSObject.Properties)) {
        $t = $p.Value
        if ([double]$t.value -ne [double]$t.default) {
            [ordered]@{ id = $p.Name; label = $t.label; value = $t.value; default = $t.default; unit = $t.unit }
        }
    }
}
