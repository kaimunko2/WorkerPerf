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

function Get-WorkerPerfHealthCatalogueNames($Object) {
    # The property names of a JSON object, in their order.
    if (-not (Test-WorkerPerfHealthCatalogueObject $Object)) { return , @() }
    return , [string[]]@($Object.PSObject.Properties | ForEach-Object { $_.Name })
}

function Get-WorkerPerfHealthPlaceholders([string]$Text) {
    # The names inside braces of a text and whether a brace stands outside a placeholder.
    $names = @(foreach ($m in [regex]::Matches($Text, '\{([^{}]*)\}')) { $m.Groups[1].Value })
    $stray = ([regex]::Replace($Text, '\{([^{}]*)\}', '')).IndexOfAny([char[]]'{}') -ge 0
    return @{ Names = [string[]]$names; Stray = $stray }
}

function Test-WorkerPerfHealthCondition {
    # Checks condition $Index (counted from 1) of rule $Rule; returns whether it is a hard limit or an event condition.
    param([string]$Path, [string]$Id, [string]$Rule, [int]$Index, $Condition, [string[]]$CheckValues, $Facts, $Thresholds)
    $where = "Regel '$Rule', Bedingung ${Index}:"
    $stop = { param($Reason) Stop-WorkerPerfHealthCatalogue $Path '' $Id 'rules' "$where $Reason" }
    if (-not (Test-WorkerPerfHealthCatalogueObject $Condition)) { & $stop 'ist kein Objekt' }
    $names = Get-WorkerPerfHealthCatalogueNames $Condition
    $hasValue = $names -ccontains 'value'; $hasEvent = $names -ccontains 'event'
    if ($hasValue -eq $hasEvent) { & $stop "braucht genau eines der Felder 'value' und 'event'" }
    $allowed = @('value', 'op', 'than', 'hard')
    if ($hasEvent) { $allowed = @('event', 'min', 'days') }
    foreach ($n in $names) { if ($allowed -cnotcontains $n) { & $stop "enthaelt das Feld '$n', das hier nicht gilt (erlaubt: $($allowed -join ', '))" } }

    if ($hasEvent) {
        $kind = $Condition.event
        if ($kind -isnot [string] -or $script:WorkerPerfHealthEventKinds -cnotcontains $kind) {
            & $stop "nennt die unbekannte Ereignisart '$kind' (erlaubt: $($script:WorkerPerfHealthEventKinds -join ', '))"
        }
        foreach ($f in 'min', 'days') {
            $m = Get-WorkerPerfHealthCatalogueMember $Condition $f
            if ($null -eq $m -or -not (Test-WorkerPerfHealthCatalogueNumber $m.Value) -or [double]$m.Value -lt 1 -or [double]$m.Value -ne [math]::Floor([double]$m.Value)) {
                & $stop "braucht in '$f' eine ganze Zahl ab 1"
            }
        }
        return $true
    }

    $fact = $Condition.value
    if ($fact -isnot [string] -or $CheckValues -cnotcontains $fact) { & $stop "nennt den Fakt '$fact', der nicht in 'values' der Pruefung steht" }
    $type = [string]$Facts[$fact].Type
    if ($type -eq 'list') { & $stop "nennt den Listenwert '$fact'; eine Bedingung vergleicht keine Liste" }
    $m = Get-WorkerPerfHealthCatalogueMember $Condition 'op'
    $op = $null; if ($null -ne $m) { $op = $m.Value }
    if ($op -isnot [string] -or $script:WorkerPerfHealthOps -cnotcontains $op) {
        & $stop "nennt den unbekannten Operator '$op' (erlaubt: $($script:WorkerPerfHealthOps -join ', '))"
    }
    if ($type -eq 'text:free' -and @('exists', 'absent') -cnotcontains $op) {
        & $stop "vergleicht den freien Servertext '$fact' mit '$op'; erlaubt sind nur 'exists' und 'absent'"
    }
    $m = Get-WorkerPerfHealthCatalogueMember $Condition 'than'
    $than = $null; if ($null -ne $m) { $than = $m.Value }
    if (@('exists', 'absent') -ccontains $op) {
        if ($null -ne $than) { & $stop "braucht bei '$op' kein 'than'" }
    }
    elseif ($null -eq $than) { & $stop "braucht bei '$op' einen Vergleichswert in 'than'" }
    elseif ($than -is [bool]) {
        if (@('eq', 'ne') -cnotcontains $op) { & $stop "vergleicht '$fact' mit einem Ja/Nein-Wert und '$op' (erlaubt: eq, ne)" }
    }
    elseif ($than -is [array]) {
        if ($op -cne 'in') { & $stop "nennt in 'than' eine Liste; sie gilt nur mit 'in'" }
        $items = @($than)
        if ($items.Count -eq 0) { & $stop "nennt in 'than' eine leere Liste" }
        foreach ($item in $items) {
            if (-not ((Test-WorkerPerfHealthCatalogueNumber $item) -or $item -is [string])) { & $stop "nennt in der Liste von 'than' einen Eintrag, der weder Zahl noch Text ist" }
        }
    }
    elseif ($than -is [string] -and $than.StartsWith('@')) {
        if ($Thresholds -cnotcontains $than.Substring(1)) { & $stop "nennt die unbekannte Schwelle '$than'" }
        if (@('in', 'contains') -ccontains $op) { & $stop "vergleicht mit der Schwelle '$than' und '$op' (erlaubt: gt, ge, lt, le, eq, ne)" }
    }
    elseif ((Test-WorkerPerfHealthCatalogueNumber $than) -or $than -is [string]) {
        if ($op -ceq 'in') { & $stop "braucht bei 'in' eine Liste in 'than'" }
        if (@('gt', 'ge', 'lt', 'le') -ccontains $op -and -not (Test-WorkerPerfHealthCatalogueNumber $than)) { & $stop "braucht bei '$op' eine Zahl oder eine Schwelle in 'than'" }
    }
    else { & $stop "nennt in 'than' weder Zahl, Text, Ja/Nein-Wert, Liste noch Schwelle" }
    $m = Get-WorkerPerfHealthCatalogueMember $Condition 'hard'
    if ($null -ne $m -and $m.Value -isnot [bool]) { & $stop "nennt in 'hard' keinen Wahrheitswert" }
    return ($null -ne $m -and $m.Value -eq $true)
}

function Test-WorkerPerfHealthCheck {
    # Checks one check of the catalogue in the order of the brief; the first violation stops.
    param([string]$Path, [int]$Index, $Check, $Facts, $FactIds, [string[]]$Thresholds, [string[]]$AppKeys, $Ids)
    if (-not (Test-WorkerPerfHealthCatalogueObject $Check)) { Stop-WorkerPerfHealthCatalogue $Path '' "checks[$Index]" '' 'ist kein Objekt' }
    $m = Get-WorkerPerfHealthCatalogueMember $Check 'id'
    if ($null -eq $m -or -not (Test-WorkerPerfHealthCatalogueText $m.Value)) { Stop-WorkerPerfHealthCatalogue $Path '' "checks[$Index]" 'id' 'fehlt, ist kein Text oder leer' }
    $id = $m.Value
    if (-not $Ids.Add($id)) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'id' 'ist doppelt' }

    $m = Get-WorkerPerfHealthCatalogueMember $Check 'area'
    if ($null -eq $m) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'area' 'fehlt' }
    $area = $m.Value
    if ($area -isnot [string] -or $script:WorkerPerfHealthAreas -cnotcontains $area) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'area' "nennt den unbekannten Bereich '$area'" }

    foreach ($f in 'title', 'meaning') {
        $m = Get-WorkerPerfHealthCatalogueMember $Check $f
        if ($null -eq $m) { Stop-WorkerPerfHealthCatalogue $Path '' $id $f 'fehlt' }
        if ($m.Value -isnot [string]) { Stop-WorkerPerfHealthCatalogue $Path '' $id $f 'ist kein Text' }
        if ([string]::IsNullOrWhiteSpace($m.Value)) { Stop-WorkerPerfHealthCatalogue $Path '' $id $f 'ist leer' }
    }

    # values: the application before the fact (an application missing from the list is named as such)
    $m = Get-WorkerPerfHealthCatalogueMember $Check 'values'
    if ($null -eq $m) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'values' 'fehlt' }
    if ($m.Value -isnot [array] -or @($m.Value).Count -eq 0) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'values' 'ist keine Liste mit mindestens einem Fakt' }
    $values = @($m.Value)
    $appOfCheck = ''
    foreach ($fact in $values) {
        if (-not (Test-WorkerPerfHealthCatalogueText $fact)) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'values' 'enthaelt einen Eintrag, der kein Text ist oder leer ist' }
        $isAppFact = $fact.StartsWith('apps.', [StringComparison]::Ordinal)
        if ($area -ceq 'apps') {
            $parts = $fact.Split('.')
            if (-not $isAppFact -or $parts.Count -ne 3) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'values' "'$fact' ist kein Wert einer Anwendung" }
            $key = $parts[1]
            if ($AppKeys -cnotcontains $key) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'values' "Anwendung '$key' steht nicht in der Anwendungsliste ('$fact')" }
            if ($appOfCheck -and $appOfCheck -cne $key) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'values' "nennt Werte von mehr als einer Anwendung ('$appOfCheck', '$key')" }
            $appOfCheck = $key
        }
        elseif ($isAppFact) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'values' "'$fact' gehoert in den Bereich apps" }
        if (-not $FactIds.Contains($fact)) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'values' "nennt den unbekannten Fakt '$fact'" }
        if (-not $Facts[$fact].Documented) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'values' "'$fact' hat keine dokumentierte Lesequelle" }
    }
    $checkValues = [string[]]$values

    # rules: check before act
    $m = Get-WorkerPerfHealthCatalogueMember $Check 'rules'
    if ($null -eq $m) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'rules' 'fehlt' }
    $rules = $m.Value
    if (-not (Test-WorkerPerfHealthCatalogueObject $rules)) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'rules' 'ist kein Objekt' }
    $ruleNames = Get-WorkerPerfHealthCatalogueNames $rules
    foreach ($n in $ruleNames) { if (@('check', 'act') -cnotcontains $n) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'rules' "nennt die unbekannte Regel '$n' (erlaubt: check, act)" } }
    if ($ruleNames.Count -eq 0) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'rules' "braucht mindestens eine der Regeln 'check' und 'act'" }
    foreach ($rule in 'check', 'act') {
        if ($ruleNames -cnotcontains $rule) { continue }
        $list = (Get-WorkerPerfHealthCatalogueMember $rules $rule).Value
        if ($list -isnot [array] -or @($list).Count -eq 0) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'rules' "Regel '$rule' ist keine Liste mit mindestens einer Bedingung" }
        $conditions = @($list)
        $hardOrEvent = $false
        for ($i = 0; $i -lt $conditions.Count; $i++) {
            if (Test-WorkerPerfHealthCondition $Path $id $rule ($i + 1) $conditions[$i] $checkValues $Facts $Thresholds) { $hardOrEvent = $true }
        }
        if ($rule -ceq 'act' -and -not $hardOrEvent) {
            Stop-WorkerPerfHealthCatalogue $Path '' $id 'rules' "Regel 'act' braucht eine Bedingung mit 'hard': true (harte Grenze) oder eine Bedingung 'event' (Ereignis)"
        }
    }

    # findings: ok and unknown, check and act for each rule; placeholders only facts of values, known thresholds and
    # {reason} (only in unknown, and always there)
    $m = Get-WorkerPerfHealthCatalogueMember $Check 'findings'
    if ($null -eq $m) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'findings' 'fehlt' }
    $findings = $m.Value
    if (-not (Test-WorkerPerfHealthCatalogueObject $findings)) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'findings' 'ist kein Objekt' }
    $findingNames = Get-WorkerPerfHealthCatalogueNames $findings
    $sentences = @('ok', 'check', 'act', 'unknown')
    foreach ($n in $findingNames) { if ($sentences -cnotcontains $n) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'findings' "nennt den unbekannten Satz '$n' (erlaubt: ok, check, act, unknown)" } }
    foreach ($s in $sentences) {
        $required = @('ok', 'unknown') -ccontains $s -or $ruleNames -ccontains $s
        if ($findingNames -cnotcontains $s) {
            if ($required) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'findings' "braucht den Satz '$s'" }
            continue
        }
        $text = (Get-WorkerPerfHealthCatalogueMember $findings $s).Value
        if ($text -isnot [string]) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'findings' "Satz '$s' ist kein Text" }
        if ([string]::IsNullOrWhiteSpace($text)) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'findings' "Satz '$s' ist leer" }
        $ph = Get-WorkerPerfHealthPlaceholders $text
        if ($ph.Stray) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'findings' "Satz '$s' enthaelt eine geschweifte Klammer ohne Platzhalter" }
        foreach ($name in $ph.Names) {
            $shown = '{' + $name + '}'
            if ($name -ceq 'reason') {
                if ($s -cne 'unknown') { Stop-WorkerPerfHealthCatalogue $Path '' $id 'findings' "Satz '$s' enthaelt den Platzhalter '$shown', der nur in 'unknown' steht" }
            }
            elseif ($name.StartsWith('@')) {
                if ($Thresholds -cnotcontains $name.Substring(1)) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'findings' "Satz '$s' enthaelt den Platzhalter '$shown' einer unbekannten Schwelle" }
            }
            elseif ($checkValues -cnotcontains $name) {
                Stop-WorkerPerfHealthCatalogue $Path '' $id 'findings' "Satz '$s' enthaelt den Platzhalter '$shown', der kein Fakt aus 'values' der Pruefung ist"
            }
            elseif ($Facts[$name].Type -eq 'list') { Stop-WorkerPerfHealthCatalogue $Path '' $id 'findings' "Satz '$s' enthaelt den Platzhalter '$shown' eines Listenwerts" }
            elseif ($Facts[$name].Type -eq 'text:free') { Stop-WorkerPerfHealthCatalogue $Path '' $id 'findings' "Satz '$s' enthaelt den Platzhalter '$shown' eines freien Servertexts" }
        }
        if ($s -ceq 'unknown' -and $ph.Names -cnotcontains 'reason') { Stop-WorkerPerfHealthCatalogue $Path '' $id 'findings' "Satz 'unknown' enthaelt den Platzhalter '{reason}' nicht" }
    }

    # todo: at least one step, each with text, where and sign
    $m = Get-WorkerPerfHealthCatalogueMember $Check 'todo'
    if ($null -eq $m) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'todo' 'fehlt' }
    if ($m.Value -isnot [array] -or @($m.Value).Count -eq 0) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'todo' 'ist keine Liste mit mindestens einem Schritt' }
    $steps = @($m.Value)
    for ($i = 0; $i -lt $steps.Count; $i++) {
        $step = $steps[$i]; $n = $i + 1
        if (-not (Test-WorkerPerfHealthCatalogueObject $step)) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'todo' "Schritt $n ist kein Objekt" }
        foreach ($f in 'text', 'where', 'sign') {
            $sm = Get-WorkerPerfHealthCatalogueMember $step $f
            if ($null -eq $sm) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'todo' "Schritt ${n}: '$f' fehlt" }
            if (-not (Test-WorkerPerfHealthCatalogueText $sm.Value)) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'todo' "Schritt ${n}: '$f' ist kein Text oder leer" }
        }
    }

    # source: vendor, title, date; an address for kind vendor and practice (the kind itself is checked next)
    $km = Get-WorkerPerfHealthCatalogueMember $Check 'kind'
    $kind = ''; if ($null -ne $km -and $km.Value -is [string]) { $kind = $km.Value }
    $m = Get-WorkerPerfHealthCatalogueMember $Check 'source'
    if ($null -eq $m) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'source' 'fehlt' }
    $source = $m.Value
    if (-not (Test-WorkerPerfHealthCatalogueObject $source)) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'source' 'ist kein Objekt' }
    foreach ($f in 'vendor', 'title', 'date') {
        $sm = Get-WorkerPerfHealthCatalogueMember $source $f
        if ($null -eq $sm -or -not (Test-WorkerPerfHealthCatalogueText $sm.Value)) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'source' "'$f' fehlt, ist kein Text oder leer" }
    }
    if ($source.date -cnotmatch '^\d{4}-\d{2}-\d{2}\z') { Stop-WorkerPerfHealthCatalogue $Path '' $id 'source' "'date' ist kein Datum der Form JJJJ-MM-TT ('$($source.date)')" }
    $um = Get-WorkerPerfHealthCatalogueMember $source 'url'
    if ($null -ne $um -and $um.Value -isnot [string]) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'source' "'url' ist kein Text" }
    if (@('vendor', 'practice') -ccontains $kind) {
        if ($null -eq $um -or [string]::IsNullOrWhiteSpace($um.Value)) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'source' "'url' fehlt oder ist leer (Pflicht bei der Art '$kind')" }
        if ($um.Value -cnotmatch '^https?://\S+\z') { Stop-WorkerPerfHealthCatalogue $Path '' $id 'source' "'url' ist keine Adresse (http:// oder https://)" }
    }

    if ($null -eq $km) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'kind' 'fehlt' }
    if ($km.Value -isnot [string] -or $script:WorkerPerfHealthKinds -cnotcontains $km.Value) {
        Stop-WorkerPerfHealthCatalogue $Path '' $id 'kind' "nennt die unbekannte Art '$($km.Value)' (erlaubt: $($script:WorkerPerfHealthKinds -join ', '))"
    }

    # relates: situations of the guided report and pattern.<id>
    $m = Get-WorkerPerfHealthCatalogueMember $Check 'relates'
    if ($null -eq $m) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'relates' 'fehlt' }
    if ($m.Value -isnot [array]) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'relates' 'ist keine Liste' }
    foreach ($r in @($m.Value)) {
        $known = $r -is [string] -and ($script:WorkerPerfSituations -ccontains $r -or
            ($r.StartsWith('pattern.', [StringComparison]::Ordinal) -and $script:WorkerPerfPatternOrder -ccontains $r.Substring(8)))
        if (-not $known) { Stop-WorkerPerfHealthCatalogue $Path '' $id 'relates' "nennt den unbekannten Bezug '$r'" }
    }
    return $id
}

function Read-WorkerPerfHealthCatalogue([string]$Path, [object[]]$Apps = @()) {
    # Reads the catalogue of the health picture and checks every part (a faulty catalogue never rates silently).
    # Apps: the application list (Read-WorkerPerfHealthApps); the facts of its applications are known to the checks
    # of the area apps. Returns the catalogue as read with the property appList (= $Apps). The first error stops with
    # a message that names part, or check and field.
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
    foreach ($n in $partNames) {
        if ($script:WorkerPerfHealthCatalogueParts -cnotcontains $n) { Stop-WorkerPerfHealthCatalogue $Path $n '' '' 'ist unbekannt' }
    }

    if (-not (Test-WorkerPerfHealthCatalogueText $cat.version)) { Stop-WorkerPerfHealthCatalogue $Path 'version' '' '' 'ist kein Text oder leer' }

    # areas: the eleven ids in their order, each with label and notCovered
    $areas = (Get-WorkerPerfHealthCatalogueMember $cat 'areas').Value
    $expected = $script:WorkerPerfHealthAreas -join ', '
    if ($areas -isnot [array]) { Stop-WorkerPerfHealthCatalogue $Path 'areas' '' '' 'ist keine Liste' }
    $areaList = @($areas)
    $ids = @(foreach ($a in $areaList) { [string](Get-WorkerPerfField $a 'id') })
    if ($areaList.Count -ne $script:WorkerPerfHealthAreas.Count -or ($ids -join ', ') -cne $expected) {
        Stop-WorkerPerfHealthCatalogue $Path 'areas' '' '' "nennt nicht die elf Bereiche in ihrer Reihenfolge ($expected)"
    }
    foreach ($a in $areaList) {
        if (-not (Test-WorkerPerfHealthCatalogueText (Get-WorkerPerfField $a 'label'))) { Stop-WorkerPerfHealthCatalogue $Path 'areas' '' '' "nennt beim Bereich '$($a.id)' keine Bezeichnung in 'label'" }
        $nc = Get-WorkerPerfHealthCatalogueMember $a 'notCovered'
        if ($null -eq $nc -or $nc.Value -isnot [string]) { Stop-WorkerPerfHealthCatalogue $Path 'areas' '' '' "nennt beim Bereich '$($a.id)' keinen Text in 'notCovered'" }
    }

    # grades: the four grades and the result na, each with word and symbol
    $grades = (Get-WorkerPerfHealthCatalogueMember $cat 'grades').Value
    if (-not (Test-WorkerPerfHealthCatalogueObject $grades)) { Stop-WorkerPerfHealthCatalogue $Path 'grades' '' '' 'ist kein Objekt' }
    $gradeKeys = @($script:WorkerPerfHealthGrades) + 'na'
    foreach ($n in (Get-WorkerPerfHealthCatalogueNames $grades)) {
        if ($gradeKeys -cnotcontains $n) { Stop-WorkerPerfHealthCatalogue $Path 'grades' '' '' "nennt die unbekannte Einstufung '$n'" }
    }
    foreach ($g in $gradeKeys) {
        $gm = Get-WorkerPerfHealthCatalogueMember $grades $g
        if ($null -eq $gm) { Stop-WorkerPerfHealthCatalogue $Path 'grades' '' '' "hat keinen Eintrag '$g'" }
        foreach ($f in 'word', 'symbol') {
            if (-not (Test-WorkerPerfHealthCatalogueText (Get-WorkerPerfField $gm.Value $f))) { Stop-WorkerPerfHealthCatalogue $Path 'grades' '' '' "nennt bei '$g' keinen Text in '$f'" }
        }
    }

    # thresholds: numbers value and default, unit and label; the required ones present
    $thresholds = (Get-WorkerPerfHealthCatalogueMember $cat 'thresholds').Value
    if (-not (Test-WorkerPerfHealthCatalogueObject $thresholds)) { Stop-WorkerPerfHealthCatalogue $Path 'thresholds' '' '' 'ist kein Objekt' }
    $thresholdIds = Get-WorkerPerfHealthCatalogueNames $thresholds
    foreach ($t in $thresholdIds) {
        $entry = $thresholds.PSObject.Properties[$t].Value
        if ($t -cnotmatch '^[A-Za-z][A-Za-z0-9]*\z') { Stop-WorkerPerfHealthCatalogue $Path 'thresholds' '' '' "nennt die Schwelle '$t'; ein Name besteht nur aus Buchstaben und Ziffern" }
        if (-not (Test-WorkerPerfHealthCatalogueObject $entry)) { Stop-WorkerPerfHealthCatalogue $Path 'thresholds' '' '' "nennt bei der Schwelle '$t' kein Objekt" }
        foreach ($f in 'value', 'default') {
            $tm = Get-WorkerPerfHealthCatalogueMember $entry $f
            if ($null -eq $tm -or -not (Test-WorkerPerfHealthCatalogueNumber $tm.Value)) { Stop-WorkerPerfHealthCatalogue $Path 'thresholds' '' '' "nennt bei der Schwelle '$t' keine Zahl in '$f'" }
        }
        $tm = Get-WorkerPerfHealthCatalogueMember $entry 'unit'
        if ($null -eq $tm -or $tm.Value -isnot [string]) { Stop-WorkerPerfHealthCatalogue $Path 'thresholds' '' '' "nennt bei der Schwelle '$t' keinen Text in 'unit'" }
        if (-not (Test-WorkerPerfHealthCatalogueText (Get-WorkerPerfField $entry 'label'))) { Stop-WorkerPerfHealthCatalogue $Path 'thresholds' '' '' "nennt bei der Schwelle '$t' keine Bezeichnung in 'label'" }
    }
    foreach ($t in $script:WorkerPerfHealthRequiredThresholds) {
        if ($thresholdIds -cnotcontains $t) { Stop-WorkerPerfHealthCatalogue $Path 'thresholds' '' '' "hat keine Schwelle '$t'" }
    }

    # values: a label for each fixed fact and no other id
    $facts = Get-WorkerPerfHealthFactTable $Apps
    $factIds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($k in $facts.Keys) { $null = $factIds.Add($k) }
    $fixed = @(@($script:WorkerPerfHealthValues.Keys) + @($script:WorkerPerfHealthDerived.Keys))
    $labels = (Get-WorkerPerfHealthCatalogueMember $cat 'values').Value
    if (-not (Test-WorkerPerfHealthCatalogueObject $labels)) { Stop-WorkerPerfHealthCatalogue $Path 'values' '' '' 'ist kein Objekt' }
    $labelIds = Get-WorkerPerfHealthCatalogueNames $labels
    foreach ($n in $labelIds) {
        if ($fixed -cnotcontains $n) { Stop-WorkerPerfHealthCatalogue $Path 'values' '' '' "nennt die unbekannte Kennung '$n' (die Bezeichnung eines Anwendungswerts steht in der Anwendungsliste)" }
    }
    foreach ($id in $fixed) {
        if ($labelIds -cnotcontains $id) { Stop-WorkerPerfHealthCatalogue $Path 'values' '' '' "nennt keine Bezeichnung fuer '$id'" }
        if (-not (Test-WorkerPerfHealthCatalogueText $labels.PSObject.Properties[$id].Value)) { Stop-WorkerPerfHealthCatalogue $Path 'values' '' '' "nennt fuer '$id' eine leere Bezeichnung" }
    }

    # copy: every required text, each with only its placeholders
    $copy = (Get-WorkerPerfHealthCatalogueMember $cat 'copy').Value
    if (-not (Test-WorkerPerfHealthCatalogueObject $copy)) { Stop-WorkerPerfHealthCatalogue $Path 'copy' '' '' 'ist kein Objekt' }
    $copyNames = Get-WorkerPerfHealthCatalogueNames $copy
    foreach ($n in $copyNames) {
        if (@($script:WorkerPerfHealthCopyKeys.Keys) -cnotcontains $n) { Stop-WorkerPerfHealthCatalogue $Path 'copy' '' '' "nennt den unbekannten Text '$n'" }
    }
    foreach ($k in $script:WorkerPerfHealthCopyKeys.Keys) {
        if ($copyNames -cnotcontains $k) { Stop-WorkerPerfHealthCatalogue $Path 'copy' '' '' "hat keinen Text '$k'" }
        $text = $copy.PSObject.Properties[$k].Value
        if (-not (Test-WorkerPerfHealthCatalogueText $text)) { Stop-WorkerPerfHealthCatalogue $Path 'copy' '' '' "Text '$k' ist kein Text oder leer" }
        $ph = Get-WorkerPerfHealthPlaceholders $text
        if ($ph.Stray) { Stop-WorkerPerfHealthCatalogue $Path 'copy' '' '' "Text '$k' enthaelt eine geschweifte Klammer ohne Platzhalter" }
        foreach ($name in $ph.Names) {
            if (@($script:WorkerPerfHealthCopyKeys[$k]) -cnotcontains $name) {
                Stop-WorkerPerfHealthCatalogue $Path 'copy' '' '' ("Text '$k' enthaelt den Platzhalter '{" + $name + "}', der dort nicht erlaubt ist")
            }
        }
    }

    # checks
    $checks = (Get-WorkerPerfHealthCatalogueMember $cat 'checks').Value
    if ($checks -isnot [array]) { Stop-WorkerPerfHealthCatalogue $Path 'checks' '' '' 'ist keine Liste' }
    $appKeys = [string[]]@(foreach ($app in $Apps) { [string](Get-WorkerPerfField $app 'key') })
    $checkIds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $checkList = @($checks)
    $kinds = @{}
    for ($i = 0; $i -lt $checkList.Count; $i++) {
        $id = Test-WorkerPerfHealthCheck $Path $i $checkList[$i] $facts $factIds ([string[]]$thresholdIds) $appKeys $checkIds
        $kinds[$id] = $checkList[$i].kind
    }

    # precedence: the exceptions of the client, in which the practice source wins over the vendor
    $precedence = (Get-WorkerPerfHealthCatalogueMember $cat 'precedence').Value
    if ($precedence -isnot [array]) { Stop-WorkerPerfHealthCatalogue $Path 'precedence' '' '' 'ist keine Liste' }
    $named = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $entries = @($precedence)
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $entry = $entries[$i]
        if (-not (Test-WorkerPerfHealthCatalogueObject $entry)) { Stop-WorkerPerfHealthCatalogue $Path 'precedence' '' '' "Eintrag $($i + 1) ist kein Objekt" }
        $cm = Get-WorkerPerfHealthCatalogueMember $entry 'check'
        if ($null -eq $cm -or -not (Test-WorkerPerfHealthCatalogueText $cm.Value)) { Stop-WorkerPerfHealthCatalogue $Path 'precedence' '' '' "Eintrag $($i + 1) nennt keine Pruefung in 'check'" }
        $id = $cm.Value
        if (-not $checkIds.Contains($id)) { Stop-WorkerPerfHealthCatalogue $Path 'precedence' $id '' 'unbekannt' }
        if (-not $named.Add($id)) { Stop-WorkerPerfHealthCatalogue $Path 'precedence' $id '' 'steht mehr als einmal in der Liste' }
        $wm = Get-WorkerPerfHealthCatalogueMember $entry 'winner'
        if ($null -eq $wm) { Stop-WorkerPerfHealthCatalogue $Path 'precedence' $id 'winner' 'fehlt' }
        if ($wm.Value -isnot [string] -or $wm.Value -cne 'practice') { Stop-WorkerPerfHealthCatalogue $Path 'precedence' $id 'winner' "nennt '$($wm.Value)'; erlaubt ist nur 'practice'" }
        $rm = Get-WorkerPerfHealthCatalogueMember $entry 'reason'
        if ($null -eq $rm) { Stop-WorkerPerfHealthCatalogue $Path 'precedence' $id 'reason' 'fehlt' }
        if (-not (Test-WorkerPerfHealthCatalogueText $rm.Value)) { Stop-WorkerPerfHealthCatalogue $Path 'precedence' $id 'reason' 'ist leer' }
        if ($kinds[$id] -cne 'practice') { Stop-WorkerPerfHealthCatalogue $Path 'precedence' $id '' "hat nicht die Art 'practice'" }
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
