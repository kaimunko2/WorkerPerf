#Requires -Version 5.1
# WorkerPerf sizing library: the catalogue of the size of the server (sizing.de.json), the class of every incident,
# the figures over several recordings and the data of the sizing report.
# Defines functions only. Callers dot-source WorkerPerf.Common.ps1 first (and the analysis libraries for the analysis).
# Lists are plain pipeline output: callers wrap calls in @(...).

# ---------------------------------------------------------------------------------------------
# Catalogue
# ---------------------------------------------------------------------------------------------

# classes in the order of their precedence (the VMware host first: it devalues every other recommendation)
$script:WorkerPerfSizingClassOrder = @('host', 'singlecore', 'app', 'oneoff', 'capacity', 'mem.capacity', 'mem.commit', 'mem.app', 'mem.used', 'undecidable')

# class -> the placeholders its texts (reason, direction) may use
$script:WorkerPerfSizingPlaceholders = @{
    'host'         = @('steal', 'stealWarn')
    'singlecore'   = @('app', 'cores', 'coreMax', 'coreBusyPct', 'cpu', 'cpuCrit')
    'app'          = @('app', 'share', 'appSharePct')
    'oneoff'       = @('app', 'role')
    'capacity'     = @('cpu', 'queue', 'target', 'cpuCrit', 'queueWarn')
    'mem.capacity' = @('commitGB', 'ramGB', 'pagesOut')
    'mem.commit'   = @('commit', 'commitCrit', 'pagesOut')
    'mem.app'      = @('app', 'share', 'growthGB')
    'mem.used'     = @('used')
    'undecidable'  = @('missing')
}

# text key -> the placeholders its template may use (every key is required; 'assumptions' is a list of sentences)
$script:WorkerPerfSizingTextPlaceholders = [ordered]@{
    'line' = @('labels', 'reason'); 'unchecked' = @('label', 'missing'); 'contradiction' = @('label')
    'result.recurring' = @('resource', 'class', 'count', 'total', 'load', 'sessions')
    'result.once' = @('resource', 'class', 'count', 'total', 'load', 'sessions'); 'result.none' = @('total', 'load', 'sessions')
    'resource.cpu' = @(); 'resource.memory' = @()
    'cpu.host' = @(); 'cpu.enough' = @('load', 'target'); 'cpu.range' = @('low', 'high', 'cores', 'target', 'load')
    'cpu.rangeOne' = @('low', 'cores', 'target', 'load'); 'cpu.scaleOut' = @('sessions', 'target', 'load'); 'cpu.other' = @('cause')
    'cpu.otherNone' = @(); 'cpu.noMainTime' = @()
    'mem.more' = @('target', 'ram', 'commit', 'pct'); 'mem.pagefile' = @(); 'mem.app' = @(); 'mem.enough' = @()
    'hint.hostOnce' = @('count', 'total'); 'hint.singlecoreToo' = @(); 'hint.scaleOutToo' = @('scaleOut'); 'hint.numa' = @()
    'hint.hostCheck' = @(); 'hint.sizeChanged' = @('sizes'); 'hint.lowMeasure' = @('runs', 'hours', 'minRuns', 'minHours')
    'hint.commitAboveRam' = @(); 'hint.memPerSession' = @(); 'hint.powerPlan' = @('value')
    'assumptions' = @(); 'pilot' = @(); 'reliability' = @('runs', 'hours', 'main'); 'usersNote' = @()
    'copy.head' = @('server', 'result'); 'copy.recommendation' = @('resource', 'text'); 'copy.assumptions' = @('list')
    'reason.cpu' = @('load', 'peak', 'target', 'causes'); 'reason.memory' = @('commit', 'ram', 'causes'); 'reason.host' = @('count', 'total')
    'reason.singlecore' = @('count', 'total'); 'reason.recurring' = @('list'); 'reason.noRecurring' = @(); 'recurring.item' = @('class', 'count', 'total')
    'dir.cpu.range' = @(); 'dir.cpu.scaleOut' = @(); 'rec.cpu' = @(); 'rec.memory' = @(); 'rec.host' = @(); 'rec.singlecore' = @()
    'size.item' = @('cores', 'ram')
}

$script:WorkerPerfSizingParts = @('version', 'sources', 'thresholds', 'limits', 'classes', 'levels', 'grades', 'users', 'signals', 'missing', 'evidence', 'texts')
$script:WorkerPerfSizingThresholdNames = @('coreBusyPct', 'sustainedPct', 'singleCoreMaxCores', 'appSharePct', 'leakGrowthPct', 'pagesOutLowPerSec',
    'pagesOutSharePct', 'recurringPct', 'minRecordings', 'minMainHours', 'mainSessionPct', 'scalingLow', 'scalingHigh', 'vcpuScaleOut', 'vcpuMax',
    'memTargetPct', 'memStepGB')
$script:WorkerPerfSizingLimitNames = @('target', 'cpuCrit', 'queueWarn', 'stealWarn', 'commitCrit')
$script:WorkerPerfSizingSignalNames = @('cpu.coreMax', 'cpu.coreBusy', 'cpu.perf', 'cpu.utility', 'mem.pagesout')
$script:WorkerPerfSizingMissingNames = @('cpu.coreMax', 'cpu.steal', 'mem.pagesout', 'processes', 'contradiction')

function Stop-WorkerPerfSizing([string]$Path, [string]$Part, [string]$Id, [string]$Field, [string]$Reason) {
    # "Katalog '<path>': <part> <id>: <field> <reason>."
    $where = $Part
    if ($Id -ne '') { $where = "$Part $Id" }
    $what = $Reason
    if ($Field -ne '') { $what = "$Field $Reason" }
    throw "Katalog '$Path': ${where}: $what."
}

function Get-WorkerPerfSizingNames($Object) {
    # the member names of a JSON object in their order ('' list for anything else)
    if ($null -eq $Object -or $Object -isnot [System.Management.Automation.PSCustomObject]) { return }
    foreach ($p in $Object.PSObject.Properties) { [string]$p.Name }
}

function Get-WorkerPerfSizingObject([string]$Path, $Parent, [string]$Part, [string]$Id, [string]$Name, [string[]]$Members) {
    # the member $Name of $Parent as a JSON object with exactly the members $Members (when given)
    $o = Get-WorkerPerfField $Parent $Name
    $label = $Name
    if ($Id -eq '' -and $Part -eq $Name) { $label = '' }
    if ($null -eq $o -or $o -isnot [System.Management.Automation.PSCustomObject]) { Stop-WorkerPerfSizing $Path $Part $Id $label 'fehlt oder ist kein Objekt' }
    if ($null -ne $Members -and $Members.Count -gt 0) { Test-WorkerPerfSizingMembers $Path $Part $Id $o $Members }
    return $o
}

function Test-WorkerPerfSizingMembers([string]$Path, [string]$Part, [string]$Id, $Object, [string[]]$Members) {
    $names = @(Get-WorkerPerfSizingNames $Object)
    foreach ($m in $Members) { if ($names -cnotcontains $m) { Stop-WorkerPerfSizing $Path $Part $Id $m 'fehlt' } }
    foreach ($n in $names) { if ($Members -cnotcontains $n) { Stop-WorkerPerfSizing $Path $Part $Id $n 'ist unbekannt' } }
}

function Get-WorkerPerfSizingText([string]$Path, [string]$Part, [string]$Id, $Object, [string]$Field) {
    $v = Get-WorkerPerfField $Object $Field
    if ($v -isnot [string] -or [string]::IsNullOrWhiteSpace($v)) { Stop-WorkerPerfSizing $Path $Part $Id $Field 'fehlt oder ist leer' }
    return [string]$v
}

function Get-WorkerPerfSizingNumber([string]$Path, [string]$Part, [string]$Id, $Object, [string]$Field) {
    $v = Get-WorkerPerfField $Object $Field
    if ($null -eq $v -or $v -is [string] -or $v -is [bool] -or $v -is [array] -or $v -is [System.Management.Automation.PSCustomObject]) {
        Stop-WorkerPerfSizing $Path $Part $Id $Field 'ist keine Zahl'
    }
    return [double]$v
}

function Test-WorkerPerfSizingPlaceholders([string]$Path, [string]$Part, [string]$Id, [string]$Field, [string]$Text, [string[]]$Allowed) {
    foreach ($m in [regex]::Matches($Text, '\{([^{}]*)\}')) {
        if ($Allowed -cnotcontains $m.Groups[1].Value) { Stop-WorkerPerfSizing $Path $Part $Id $Field ("nennt den unbekannten Platzhalter " + $m.Value) }
    }
}

function Get-WorkerPerfSizingSourceList([string]$Path, [string]$Part, [string]$Id, $Object, [string]$Kind, $Sources) {
    # the member sources as a list of known source ids; vendor and practice need at least one
    $raw = Get-WorkerPerfField $Object 'sources'
    if ($null -eq $raw) { $raw = @() }
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($s in @($raw)) {
        if ($s -isnot [string] -or -not $Sources.Contains([string]$s)) { Stop-WorkerPerfSizing $Path $Part $Id 'sources' ("nennt die unbekannte Quelle '" + [string]$s + "'") }
        $list.Add([string]$s)
    }
    if (($Kind -eq 'vendor' -or $Kind -eq 'practice') -and $list.Count -eq 0) { Stop-WorkerPerfSizing $Path $Part $Id 'sources' 'fehlt: eine Herstellerangabe oder Praxisquelle braucht mindestens eine Quelle' }
    return , [string[]]$list.ToArray()
}

function Get-WorkerPerfSizingKind([string]$Path, [string]$Part, [string]$Id, $Object, [string[]]$Allowed) {
    $k = Get-WorkerPerfField $Object 'kind'
    if ($k -isnot [string] -or $Allowed -cnotcontains $k) { Stop-WorkerPerfSizing $Path $Part $Id 'kind' ("ist keine der Arten " + ($Allowed -join ', ')) }
    return [string]$k
}

function Read-WorkerPerfSizing([string]$Path, $Thresholds) {
    # Reads the catalogue of the size of the server and checks every part; the first error stops with a message that
    # names part, id and field. A member the loader does not know is rejected. Thresholds: Read-WorkerPerfThresholds;
    # the limits of cpu.host, cpu.queue, cpu.steal and mem.commit come from there only (one set of thresholds).
    # Returns: Version; Sources (id -> Title, Url, Date, Kind); Thresholds (name -> Value, Default, Unit, Label, Kind,
    # Sources); Limits (name -> Value, Signal, Level, Label); Classes (ordered by precedence, id -> Id, Resource, Label,
    # Reason, Direction, Kind, Sources); Levels; Grades (Word, Symbol); Users (Label, PerVcpu); Signals (Label, Note,
    # Sources); Missing; Evidence; Texts (key -> template, 'assumptions' a list).
    $cat = ConvertFrom-WorkerPerfJsonFile $Path
    if ($null -eq $cat -or $cat -isnot [System.Management.Automation.PSCustomObject]) { throw "Katalog '$Path' ist kein JSON-Objekt." }
    $names = @(Get-WorkerPerfSizingNames $cat)
    foreach ($p in $script:WorkerPerfSizingParts) { if ($names -cnotcontains $p) { Stop-WorkerPerfSizing $Path $p '' '' 'fehlt' } }
    foreach ($n in $names) { if ($script:WorkerPerfSizingParts -cnotcontains $n) { Stop-WorkerPerfSizing $Path $n '' '' 'ist unbekannt' } }
    $version = Get-WorkerPerfField $cat 'version'
    if ($version -isnot [string] -or $version -notmatch '^\d{4}-\d{2}-\d{2}$') { Stop-WorkerPerfSizing $Path 'version' '' '' 'ist kein Datum der Form JJJJ-MM-TT' }

    # sources
    $sources = [ordered]@{}
    $rawSources = Get-WorkerPerfSizingObject $Path $cat 'sources' '' 'sources' @()
    foreach ($id in @(Get-WorkerPerfSizingNames $rawSources)) {
        $s = Get-WorkerPerfSizingObject $Path $rawSources 'sources' '' $id @()
        Test-WorkerPerfSizingMembers $Path 'sources' $id $s @('title', 'url', 'date', 'kind')
        $title = Get-WorkerPerfSizingText $Path 'sources' $id $s 'title'
        $url = Get-WorkerPerfField $s 'url'
        if ($url -isnot [string] -or $url -notmatch '^https://\S+$') { Stop-WorkerPerfSizing $Path 'sources' $id 'url' 'fehlt oder beginnt nicht mit https://' }
        $date = Get-WorkerPerfField $s 'date'
        if ($date -isnot [string] -or $date -notmatch '^\d{4}-\d{2}-\d{2}$') { Stop-WorkerPerfSizing $Path 'sources' $id 'date' 'ist kein Datum der Form JJJJ-MM-TT' }
        $kind = Get-WorkerPerfSizingKind $Path 'sources' $id $s @('vendor', 'practice')
        $sources[$id] = @{ Title = $title; Url = [string]$url; Date = [string]$date; Kind = $kind }
    }

    # own thresholds
    $own = [ordered]@{}
    $rawTh = Get-WorkerPerfSizingObject $Path $cat 'thresholds' '' 'thresholds' @()
    foreach ($n in @(Get-WorkerPerfSizingNames $rawTh)) {
        if ($null -ne $Thresholds -and $Thresholds.Contains($n)) { Stop-WorkerPerfSizing $Path 'thresholds' $n '' 'traegt eine Kennung aus thresholds.json; diese Schwelle steht nur dort' }
        if ($script:WorkerPerfSizingThresholdNames -cnotcontains $n) { Stop-WorkerPerfSizing $Path 'thresholds' $n '' 'ist unbekannt' }
    }
    foreach ($n in $script:WorkerPerfSizingThresholdNames) {
        $t = Get-WorkerPerfField $rawTh $n
        if ($null -eq $t -or $t -isnot [System.Management.Automation.PSCustomObject]) { Stop-WorkerPerfSizing $Path 'thresholds' $n '' 'fehlt' }
        Test-WorkerPerfSizingMembers $Path 'thresholds' $n $t @('value', 'default', 'unit', 'label', 'kind', 'sources')
        $kind = Get-WorkerPerfSizingKind $Path 'thresholds' $n $t @('vendor', 'practice', 'rule')
        $own[$n] = @{
            Value = (Get-WorkerPerfSizingNumber $Path 'thresholds' $n $t 'value'); Default = (Get-WorkerPerfSizingNumber $Path 'thresholds' $n $t 'default')
            Unit = (Get-WorkerPerfSizingText $Path 'thresholds' $n $t 'unit'); Label = (Get-WorkerPerfSizingText $Path 'thresholds' $n $t 'label')
            Kind = $kind; Sources = (Get-WorkerPerfSizingSourceList $Path 'thresholds' $n $t $kind $sources)
        }
        $v = [double]$own[$n].Value
        if ($v -le 0) { Stop-WorkerPerfSizing $Path 'thresholds' $n 'value' 'muss groesser als 0 sein' }
        if ($n -eq 'coreBusyPct' -and ($v -lt 50 -or $v -gt 100)) { Stop-WorkerPerfSizing $Path 'thresholds' $n 'value' 'muss zwischen 50 und 100 liegen' }
        if ($n -like '*Pct' -and $v -gt 100) { Stop-WorkerPerfSizing $Path 'thresholds' $n 'value' 'muss zwischen 0 und 100 liegen' }
        if (($n -eq 'scalingLow' -or $n -eq 'scalingHigh') -and ($v -le 1 -or $v -ge 2)) { Stop-WorkerPerfSizing $Path 'thresholds' $n 'value' 'muss ueber 1 und unter 2 liegen' }
        if ($n -eq 'singleCoreMaxCores' -and $v -lt 1) { Stop-WorkerPerfSizing $Path 'thresholds' $n 'value' 'muss mindestens 1 sein' }
    }
    if ($own['scalingLow'].Value -ge $own['scalingHigh'].Value) { Stop-WorkerPerfSizing $Path 'thresholds' 'scalingLow' 'value' 'muss unter scalingHigh liegen' }
    if ($own['vcpuScaleOut'].Value -ge $own['vcpuMax'].Value) { Stop-WorkerPerfSizing $Path 'thresholds' 'vcpuScaleOut' 'value' 'muss unter vcpuMax liegen' }

    # limits: resolved from thresholds.json
    $limits = [ordered]@{}
    $rawLimits = Get-WorkerPerfSizingObject $Path $cat 'limits' '' 'limits' $script:WorkerPerfSizingLimitNames
    foreach ($n in $script:WorkerPerfSizingLimitNames) {
        $l = Get-WorkerPerfSizingObject $Path $rawLimits 'limits' '' $n @()
        Test-WorkerPerfSizingMembers $Path 'limits' $n $l @('signal', 'level', 'label')
        $signal = Get-WorkerPerfField $l 'signal'
        if ($signal -isnot [string] -or $null -eq $Thresholds -or -not $Thresholds.Contains($signal)) { Stop-WorkerPerfSizing $Path 'limits' $n 'signal' 'nennt kein Signal aus thresholds.json' }
        $level = Get-WorkerPerfField $l 'level'
        if ($level -isnot [string] -or @('warn', 'crit') -cnotcontains $level) { Stop-WorkerPerfSizing $Path 'limits' $n 'level' 'ist weder warn noch crit' }
        $limits[$n] = @{ Value = [double]$Thresholds[$signal].$level; Signal = [string]$signal; Level = [string]$level; Label = (Get-WorkerPerfSizingText $Path 'limits' $n $l 'label') }
    }

    # classes
    $classes = [ordered]@{}
    $rawClasses = Get-WorkerPerfField $cat 'classes'
    if ($null -eq $rawClasses -or $rawClasses -isnot [array]) { Stop-WorkerPerfSizing $Path 'classes' '' '' 'fehlt oder ist keine Liste' }
    $ids = @(foreach ($c in $rawClasses) { [string](Get-WorkerPerfField $c 'id') })
    if (($ids -join '|') -cne ($script:WorkerPerfSizingClassOrder -join '|')) {
        Stop-WorkerPerfSizing $Path 'classes' '' '' ("Reihenfolge oder Bestand weicht ab; erwartet: " + ($script:WorkerPerfSizingClassOrder -join ', '))
    }
    foreach ($c in $rawClasses) {
        $id = [string]$c.id
        Test-WorkerPerfSizingMembers $Path 'classes' $id $c @('id', 'resource', 'label', 'reason', 'direction', 'kind', 'sources')
        $res = Get-WorkerPerfField $c 'resource'
        if ($res -isnot [string] -or @('cpu', 'memory', 'any') -cnotcontains $res) { Stop-WorkerPerfSizing $Path 'classes' $id 'resource' 'ist weder cpu, memory noch any' }
        $kind = Get-WorkerPerfSizingKind $Path 'classes' $id $c @('vendor', 'practice', 'rule')
        $reason = Get-WorkerPerfSizingText $Path 'classes' $id $c 'reason'
        $direction = Get-WorkerPerfSizingText $Path 'classes' $id $c 'direction'
        Test-WorkerPerfSizingPlaceholders $Path 'classes' $id 'reason' $reason $script:WorkerPerfSizingPlaceholders[$id]
        Test-WorkerPerfSizingPlaceholders $Path 'classes' $id 'direction' $direction $script:WorkerPerfSizingPlaceholders[$id]
        $classes[$id] = @{
            Id = $id; Resource = [string]$res; Label = (Get-WorkerPerfSizingText $Path 'classes' $id $c 'label'); Reason = $reason; Direction = $direction
            Kind = $kind; Sources = (Get-WorkerPerfSizingSourceList $Path 'classes' $id $c $kind $sources)
        }
    }

    # levels, grades, users
    $rawLevels = Get-WorkerPerfSizingObject $Path $cat 'levels' '' 'levels' @('clear', 'tight')
    $levels = @{ clear = (Get-WorkerPerfSizingText $Path 'levels' '' $rawLevels 'clear'); tight = (Get-WorkerPerfSizingText $Path 'levels' '' $rawLevels 'tight') }
    $grades = [ordered]@{}
    $rawGrades = Get-WorkerPerfSizingObject $Path $cat 'grades' '' 'grades' @('act', 'check', 'ok')
    foreach ($g in 'act', 'check', 'ok') {
        $o = Get-WorkerPerfSizingObject $Path $rawGrades 'grades' '' $g @()
        Test-WorkerPerfSizingMembers $Path 'grades' $g $o @('word', 'symbol')
        $grades[$g] = @{ Word = (Get-WorkerPerfSizingText $Path 'grades' $g $o 'word'); Symbol = (Get-WorkerPerfSizingText $Path 'grades' $g $o 'symbol') }
    }
    $users = [ordered]@{}
    $rawUsers = Get-WorkerPerfSizingObject $Path $cat 'users' '' 'users' @('light', 'medium', 'heavy', 'power')
    foreach ($u in 'light', 'medium', 'heavy', 'power') {
        $o = Get-WorkerPerfSizingObject $Path $rawUsers 'users' '' $u @()
        Test-WorkerPerfSizingMembers $Path 'users' $u $o @('label', 'perVcpu')
        $per = Get-WorkerPerfSizingNumber $Path 'users' $u $o 'perVcpu'
        if ($per -le 0) { Stop-WorkerPerfSizing $Path 'users' $u 'perVcpu' 'muss groesser als 0 sein' }
        $users[$u] = @{ Label = (Get-WorkerPerfSizingText $Path 'users' $u $o 'label'); PerVcpu = $per }
    }

    # signals, missing, evidence
    $signals = [ordered]@{}
    $rawSignals = Get-WorkerPerfSizingObject $Path $cat 'signals' '' 'signals' $script:WorkerPerfSizingSignalNames
    foreach ($n in $script:WorkerPerfSizingSignalNames) {
        $o = Get-WorkerPerfSizingObject $Path $rawSignals 'signals' '' $n @()
        Test-WorkerPerfSizingMembers $Path 'signals' $n $o @('label', 'note', 'sources')
        $signals[$n] = @{ Label = (Get-WorkerPerfSizingText $Path 'signals' $n $o 'label'); Note = (Get-WorkerPerfSizingText $Path 'signals' $n $o 'note')
            Sources = (Get-WorkerPerfSizingSourceList $Path 'signals' $n $o 'rule' $sources) }
    }
    $missing = [ordered]@{}
    $rawMissing = Get-WorkerPerfSizingObject $Path $cat 'missing' '' 'missing' $script:WorkerPerfSizingMissingNames
    foreach ($n in $script:WorkerPerfSizingMissingNames) { $missing[$n] = Get-WorkerPerfSizingText $Path 'missing' '' $rawMissing $n }
    $evidence = [ordered]@{}
    $rawEvidence = Get-WorkerPerfSizingObject $Path $cat 'evidence' '' 'evidence' @()
    foreach ($n in @(Get-WorkerPerfSizingNames $rawEvidence)) { $evidence[$n] = Get-WorkerPerfSizingText $Path 'evidence' '' $rawEvidence $n }

    # texts
    $texts = [ordered]@{}
    $rawTexts = Get-WorkerPerfSizingObject $Path $cat 'texts' '' 'texts' @()
    $textNames = @(Get-WorkerPerfSizingNames $rawTexts)
    foreach ($k in $script:WorkerPerfSizingTextPlaceholders.Keys) { if ($textNames -cnotcontains $k) { Stop-WorkerPerfSizing $Path 'texts' $k '' 'fehlt' } }
    foreach ($k in $textNames) {
        if (-not $script:WorkerPerfSizingTextPlaceholders.Contains($k)) { Stop-WorkerPerfSizing $Path 'texts' $k '' 'ist unbekannt' }
        $v = Get-WorkerPerfField $rawTexts $k
        if ($k -eq 'assumptions') {
            if ($v -isnot [array] -or @($v).Count -eq 0) { Stop-WorkerPerfSizing $Path 'texts' $k '' 'ist keine Liste von Saetzen' }
            foreach ($line in $v) { if ($line -isnot [string] -or [string]::IsNullOrWhiteSpace($line)) { Stop-WorkerPerfSizing $Path 'texts' $k '' 'enthaelt einen leeren Eintrag' } }
            $texts[$k] = [string[]]@($v)
            continue
        }
        if ($v -isnot [string] -or [string]::IsNullOrWhiteSpace($v)) { Stop-WorkerPerfSizing $Path 'texts' $k '' 'fehlt oder ist leer' }
        Test-WorkerPerfSizingPlaceholders $Path 'texts' $k '' ([string]$v) $script:WorkerPerfSizingTextPlaceholders[$k]
        $texts[$k] = [string]$v
    }

    return @{
        Version = [string]$version; Sources = $sources; Thresholds = $own; Limits = $limits; Classes = $classes; Levels = $levels
        Grades = $grades; Users = $users; Signals = $signals; Missing = $missing; Evidence = $evidence; Texts = $texts
    }
}

# ---------------------------------------------------------------------------------------------
# Class of an incident (the cause of a CPU or memory bottleneck)
# ---------------------------------------------------------------------------------------------

function Get-WorkerPerfPercentile([double[]]$Values, [double]$Pct) {
    # nearest rank: sorted, index ceil(Pct / 100 * n) - 1; NaN is passed over; NaN without a value
    $list = New-Object System.Collections.Generic.List[double]
    foreach ($v in @($Values)) { if (-not [double]::IsNaN($v)) { $list.Add($v) } }
    if ($list.Count -eq 0) { return [double]::NaN }
    $a = $list.ToArray(); [Array]::Sort($a)
    $i = [int][Math]::Ceiling($Pct / 100.0 * $a.Length) - 1
    if ($i -lt 0) { $i = 0 }
    if ($i -ge $a.Length) { $i = $a.Length - 1 }
    return $a[$i]
}

function Format-WorkerPerfSizingNumber($Value, [int]$Decimals = 1) {
    # a number for a German text: decimal comma, no trailing zeros; '' for nothing
    if ($null -eq $Value) { return '' }
    $d = [double]$Value
    if ([double]::IsNaN($d) -or [double]::IsInfinity($d)) { return '' }
    $format = '0'
    if ($Decimals -gt 0) { $format = '0.' + ('#' * $Decimals) }
    return [Math]::Round($d, $Decimals, [MidpointRounding]::AwayFromZero).ToString($format, [Globalization.CultureInfo]::InvariantCulture).Replace('.', ',')
}

function Get-WorkerPerfIncidentFacts($Incident, $Model, $Thresholds, $Sizing) {
    # What the window of an incident says, as far as the classes need it (one table of processes per measure and
    # incident). Cpu, Memory: the incident has a finding of that resource; Delay: an input delay without a bottleneck.
    # MinTicks: signal -> minTicks of thresholds.json ("lasting" is a value over its limit in that many ticks).
    # StealMeasured/Ticks/Max; CpuP95, CpuMax, OverTargetTicks, ClearTicks (CPU critical and the queue per CPU over its
    # limit in the same tick), QueueMax; CoreMaxMeasured, CoreMaxHighPct (share of ticks with the strongest logical
    # processor busy), CoreMaxP95; Processes (process data exist for the window); TopProcess: Name, Cores (median of the
    # cores per snapshot), BandPct (share of snapshots in which it used about one core), without the collector; TopApp:
    # App, Role, RoleLabel, SharePct of the largest application in one session of the CPU used; Scan; PagesOutMeasured,
    # PagesOutPct (share of ticks over the low value), PagesOutMax; CommitOverRamTicks, CommitCritTicks, CommitMax (%),
    # CommittedMaxMB, RamMB; MemTop: App, SharePct, GrowthMB (the application in one session that grew most when its
    # growth reaches the leak value, else the largest); UsedMax (%).
    $nan = [double]::NaN
    $lim = $Sizing.Limits; $own = $Sizing.Thresholds
    $findings = @($Incident.Findings)
    $facts = @{
        Cpu = (@($findings | Where-Object { $_.Resource -eq 'cpu' }).Count -gt 0)
        Memory = (@($findings | Where-Object { $_.Resource -eq 'memory' }).Count -gt 0)
        Delay = ([string]$Incident.Type -eq 'ohne-engpass')
        MinTicks = @{}
    }
    foreach ($id in 'cpu.steal', 'cpu.host', 'mem.commit') {
        $facts.MinTicks[$id] = 3
        if ($null -ne $Thresholds -and $Thresholds.Contains($id)) { $facts.MinTicks[$id] = [int]$Thresholds[$id].minTicks }
    }
    $ticks = @(Get-WorkerPerfWindowTicks $Model ([long]$Incident.StartMs) ([long]$Incident.EndMs))
    $sig = $Model.Tick.Signal
    $pick = {
        param([double[]]$Series)
        $out = New-Object double[] $ticks.Count
        for ($i = 0; $i -lt $ticks.Count; $i++) { $out[$i] = $Series[$ticks[$i]] }
        , $out
    }
    $stat = {
        # count of values, count at or over the limit, the maximum
        param([double[]]$Values, [double]$Limit)
        $n = 0; $over = 0; $max = $nan
        foreach ($v in $Values) {
            if ([double]::IsNaN($v)) { continue }
            $n++
            if ($v -ge $Limit) { $over++ }
            if ([double]::IsNaN($max) -or $v -gt $max) { $max = $v }
        }
        @{ N = $n; Over = $over; Max = $max }
    }
    $available = { param([string]$Id) (-not $Model.Sources.ContainsKey($Id)) -or [bool]$Model.Sources[$Id].Available }

    # VMware host
    $steal = & $stat (& $pick $sig['cpu.steal']) ([double]$lim.stealWarn.Value)
    $facts.StealMeasured = ((& $available 'cpu.steal') -and $steal.N -gt 0)
    $facts.StealTicks = $steal.Over; $facts.StealMax = $steal.Max

    # CPU and queue
    $cpu = & $pick $sig['cpu.host']; $queue = & $pick $sig['cpu.queue']
    $cpuStat = & $stat $cpu ([double]$lim.target.Value)
    $facts.CpuP95 = Get-WorkerPerfPercentile $cpu 95; $facts.CpuMax = $cpuStat.Max; $facts.OverTargetTicks = $cpuStat.Over
    $facts.QueueMax = (& $stat $queue 0).Max
    $clear = 0
    for ($i = 0; $i -lt $ticks.Count; $i++) { if ($cpu[$i] -ge [double]$lim.cpuCrit.Value -and $queue[$i] -ge [double]$lim.queueWarn.Value) { $clear++ } }
    $facts.ClearTicks = $clear

    # strongest logical processor
    $coreMax = & $pick $sig['cpu.coreMax']
    $coreStat = & $stat $coreMax ([double]$own.coreBusyPct.Value)
    $facts.CoreMaxMeasured = ([bool]$Model.Measured['cpu.coreMax'] -and $coreStat.N -gt 0)
    $facts.CoreMaxHighPct = 0.0
    if ($coreStat.N -gt 0) { $facts.CoreMaxHighPct = 100.0 * $coreStat.Over / $coreStat.N }
    $facts.CoreMaxP95 = Get-WorkerPerfPercentile $coreMax 95

    # processes: the one with the most CPU time, and the largest application in one session
    $snaps = [int[]]@(Get-WorkerPerfWindowSnaps $Model ([long]$Incident.StartMs) ([long]$Incident.EndMs))
    $rows = $Model.Rows; $proc = @($Model.Proc)
    $cpuOf = @{}
    foreach ($p in $snaps) {
        for ($r = [int]$rows.Start[$p]; $r -lt [int]$rows.Start[$p + 1]; $r++) {
            $k = [int]$rows.K[$r]
            if ($k -lt 0 -or $k -ge $proc.Count -or $null -eq $proc[$k]) { continue }
            if (-not $cpuOf.ContainsKey($k)) { $cpuOf[$k] = 0.0 }
            $cpuOf[$k] += [double]$rows.CpuMs[$r]
        }
    }
    $facts.Processes = (@($Model.Skip) -notcontains 'Prozesse' -and $cpuOf.Count -gt 0)
    $facts.TopProcess = $null; $facts.TopApp = $null; $facts.MemTop = $null
    if ($facts.Processes) {
        $top = -1
        foreach ($k in $cpuOf.Keys) {
            if ([bool]$proc[$k].IsCollector) { continue }
            if ($top -lt 0 -or $cpuOf[$k] -gt $cpuOf[$top] -or ($cpuOf[$k] -eq $cpuOf[$top] -and $k -lt $top)) { $top = $k }
        }
        if ($top -ge 0 -and $cpuOf[$top] -gt 0) {
            $low = [double]$own.coreBusyPct.Value / 100.0; $high = [double]$own.singleCoreMaxCores.Value
            $perSnap = New-Object System.Collections.Generic.List[double]
            $inBand = 0
            foreach ($p in $snaps) {
                $ms = 0.0
                for ($r = [int]$rows.Start[$p]; $r -lt [int]$rows.Start[$p + 1]; $r++) { if ([int]$rows.K[$r] -eq $top) { $ms += [double]$rows.CpuMs[$r] } }
                $sec = [double]$Model.Snap.ElapsedSec[$p]
                $coresUsed = 0.0
                if ($sec -gt 0) { $coresUsed = $ms / ($sec * 1000.0) }
                $perSnap.Add($coresUsed)
                if ($coresUsed -ge $low -and $coresUsed -le $high) { $inBand++ }
            }
            $facts.TopProcess = @{ Name = [string]$proc[$top].Name; Cores = (Get-WorkerPerfPercentile $perSnap.ToArray() 50); BandPct = (100.0 * $inBand / $perSnap.Count) }
        }
        $cpuTable = @(Get-WorkerPerfShareTable -Model $Model -Measure 'cpu' -WindowSnaps $snaps -BaseSnaps ([int[]]@()) -SessionFilter ([int[]]@()) -Cache @{})
        $apps = @(Group-WorkerPerfShareTable -Model $Model -Table $cpuTable -By 'app-in-session')
        if ($apps.Count -gt 0) {
            $a = $apps[0]; $role = ''; $roleLabel = ''
            foreach ($x in @($Model.Apps)) { if ([int]$x.Index -eq [int]$a.AppIndex) { $role = [string]$x.Role; $roleLabel = [string]$x.RoleLabel } }
            $facts.TopApp = @{ App = [string]$a.Name; Role = $role; RoleLabel = $roleLabel; SharePct = [double]$a.Share }
        }
        if ($facts.Memory) {
            $memTable = @(Get-WorkerPerfShareTable -Model $Model -Measure 'memory' -WindowSnaps $snaps -BaseSnaps ([int[]]@()) -SessionFilter ([int[]]@()) -Cache @{})
            $memApps = @(Group-WorkerPerfShareTable -Model $Model -Table $memTable -By 'app-in-session')
            if ($memApps.Count -gt 0) {
                $pickApp = $memApps[0]
                $grown = @($memApps | Sort-Object -Property @{ Expression = { [double]$_.Growth }; Descending = $true }, @{ Expression = { $_.Name } })[0]
                if ([double]$grown.Growth -ge ([double]$own.leakGrowthPct.Value / 100.0 * [double]$Model.Meta.RamMB)) { $pickApp = $grown }
                $facts.MemTop = @{ App = [string]$pickApp.Name; SharePct = [double]$pickApp.Share; GrowthMB = [double]$pickApp.Growth }
            }
        }
    }
    $facts.Scan = $false
    foreach ($sc in @($Model.Scans)) { if ([long]$sc.StartMs -le [long]$Incident.EndMs -and [long]$sc.EndMs -ge [long]$Incident.StartMs) { $facts.Scan = $true; break } }

    # memory
    $pagesOut = & $stat (& $pick $sig['mem.pagesout']) ([double]$own.pagesOutLowPerSec.Value)
    $facts.PagesOutMeasured = ([bool]$Model.Measured['mem.pagesout'] -and $pagesOut.N -gt 0)
    $facts.PagesOutPct = 0.0
    if ($pagesOut.N -gt 0) { $facts.PagesOutPct = 100.0 * $pagesOut.Over / $pagesOut.N }
    $facts.PagesOutMax = $pagesOut.Max
    $ramMb = [double]$Model.Meta.RamMB
    $committed = & $pick $Model.Tick.Raw['MemCommittedMB']
    $overRam = 0
    foreach ($v in $committed) { if (-not [double]::IsNaN($v) -and $ramMb -gt 0 -and $v -gt $ramMb) { $overRam++ } }
    $commitStat = & $stat (& $pick $sig['mem.commit']) ([double]$lim.commitCrit.Value)
    $facts.CommitOverRamTicks = $overRam; $facts.CommitCritTicks = $commitStat.Over; $facts.CommitMax = $commitStat.Max
    $facts.CommittedMaxMB = (& $stat $committed 0).Max; $facts.RamMB = $ramMb
    $facts.UsedMax = (& $stat (& $pick $sig['mem.used']) 0).Max
    return $facts
}

function Get-WorkerPerfIncidentClasses([hashtable]$Facts, $Sizing) {
    # The classes of an incident from its facts, in the order of precedence: Classes = @(@{ Id; Level; Values }) (Level
    # only for capacity: clear or tight; Values: the placeholder values of the texts), Unchecked = @(@{ Id; Missing })
    # for a class that cannot be told (Missing: the measurements that lack, none for contradicting values).
    # A class is asked only where its incident allows it: host and singlecore with a CPU finding or an input delay
    # without a bottleneck, app, oneoff and capacity with a CPU finding, the memory classes with a memory finding.
    $own = $Sizing.Thresholds; $lim = $Sizing.Limits
    $fmt = { param($v, [int]$d = 1) Format-WorkerPerfSizingNumber $v $d }
    $classes = [ordered]@{}; $unchecked = [ordered]@{}
    $sustained = [double]$own.sustainedPct.Value
    $cpuLike = ([bool]$Facts.Cpu -or [bool]$Facts.Delay)

    if ($cpuLike) {
        # 1 VMware host
        if (-not $Facts.StealMeasured) { $unchecked['host'] = [string[]]@('cpu.steal') }
        elseif ([int]$Facts.StealTicks -ge [int]$Facts.MinTicks['cpu.steal']) {
            $classes['host'] = @{ Id = 'host'; Level = $null; Values = @{ steal = (& $fmt $Facts.StealMax); stealWarn = (& $fmt $lim.stealWarn.Value) } }
        }
        # 2 performance per core
        if (-not $Facts.Processes) { $unchecked['singlecore'] = [string[]]@('processes') }
        elseif ($null -ne $Facts.TopProcess -and [double]$Facts.TopProcess.BandPct -ge $sustained) {
            if (-not $Facts.CoreMaxMeasured) { $unchecked['singlecore'] = [string[]]@('cpu.coreMax') }
            elseif ([double]$Facts.CoreMaxHighPct -lt $sustained) { $unchecked['singlecore'] = [string[]]@() }
            elseif ([double]$Facts.CpuP95 -lt [double]$lim.cpuCrit.Value) {
                $classes['singlecore'] = @{ Id = 'singlecore'; Level = $null; Values = @{
                        app = [string]$Facts.TopProcess.Name; cores = (& $fmt $Facts.TopProcess.Cores); coreMax = (& $fmt $Facts.CoreMaxP95)
                        coreBusyPct = (& $fmt $own.coreBusyPct.Value); cpu = (& $fmt $Facts.CpuP95); cpuCrit = (& $fmt $lim.cpuCrit.Value) } }
            }
        }
    }
    if ($Facts.Cpu) {
        $top = $Facts.TopApp
        # 4 one-off (asked before 3: a scan is no "clear up the application")
        if ($null -ne $top -and [double]$top.SharePct -ge $script:WorkerPerfSizingMinSharePct -and
            ([string]$top.Role -eq 'Wartung' -or ([string]$top.Role -eq 'Sicherheit' -and [bool]$Facts.Scan))) {
            $role = [string]$top.RoleLabel
            if ($role -eq '') { $role = [string]$top.Role }
            $classes['oneoff'] = @{ Id = 'oneoff'; Level = $null; Values = @{ app = [string]$top.App; role = $role } }
        }
        # 3 application
        if (-not $classes.Contains('singlecore') -and -not $classes.Contains('oneoff') -and -not $unchecked.Contains('singlecore') -and
            $null -ne $top -and [double]$top.SharePct -ge [double]$own.appSharePct.Value) {
            $classes['app'] = @{ Id = 'app'; Level = $null; Values = @{ app = [string]$top.App; share = (& $fmt $top.SharePct 0); appSharePct = (& $fmt $own.appSharePct.Value) } }
        }
        # 5 capacity: broad load over the target
        if (-not $classes.Contains('singlecore') -and -not $classes.Contains('app') -and -not $classes.Contains('oneoff') -and -not $unchecked.Contains('singlecore') -and
            [int]$Facts.OverTargetTicks -ge [int]$Facts.MinTicks['cpu.host']) {
            $level = 'tight'
            if ([int]$Facts.ClearTicks -ge [int]$Facts.MinTicks['cpu.host']) { $level = 'clear' }
            $classes['capacity'] = @{ Id = 'capacity'; Level = $level; Values = @{
                    cpu = (& $fmt $Facts.CpuP95); queue = (& $fmt $Facts.QueueMax); target = (& $fmt $lim.target.Value)
                    cpuCrit = (& $fmt $lim.cpuCrit.Value); queueWarn = (& $fmt $lim.queueWarn.Value) } }
        }
    }
    if ($Facts.Memory) {
        $minCommit = [int]$Facts.MinTicks['mem.commit']
        $paging = ([double]$Facts.PagesOutPct -gt [double]$own.pagesOutSharePct.Value)
        $mt = $Facts.MemTop
        # 8 application (asked first: capacity is a broad load)
        if (-not $Facts.Processes) { $unchecked['mem.app'] = [string[]]@('processes') }
        elseif ($null -ne $mt -and ([double]$mt.SharePct -ge [double]$own.appSharePct.Value -or
                [double]$mt.GrowthMB -ge ([double]$own.leakGrowthPct.Value / 100.0 * [double]$Facts.RamMB))) {
            $classes['mem.app'] = @{ Id = 'mem.app'; Level = $null; Values = @{ app = [string]$mt.App; share = (& $fmt $mt.SharePct 0); growthGB = (& $fmt ([double]$mt.GrowthMB / 1024.0)) } }
        }
        # 6 capacity
        if (-not $classes.Contains('mem.app') -and [int]$Facts.CommitOverRamTicks -ge $minCommit) {
            if (-not $Facts.PagesOutMeasured) { $unchecked['mem.capacity'] = [string[]]@('mem.pagesout') }
            elseif ($paging) {
                $classes['mem.capacity'] = @{ Id = 'mem.capacity'; Level = $null; Values = @{
                        commitGB = (& $fmt ([double]$Facts.CommittedMaxMB / 1024.0)); ramGB = (& $fmt ([double]$Facts.RamMB / 1024.0)); pagesOut = (& $fmt $Facts.PagesOutMax 0) } }
            }
        }
        # 7 commit limit
        if ([int]$Facts.CommitCritTicks -ge $minCommit) {
            if (-not $Facts.PagesOutMeasured) { $unchecked['mem.commit'] = [string[]]@('mem.pagesout') }
            elseif (-not $paging) {
                $classes['mem.commit'] = @{ Id = 'mem.commit'; Level = $null; Values = @{
                        commit = (& $fmt $Facts.CommitMax); commitCrit = (& $fmt $lim.commitCrit.Value); pagesOut = (& $fmt $Facts.PagesOutMax 0) } }
            }
        }
        # 9 used, no shortage
        if (-not $classes.Contains('mem.capacity') -and -not $classes.Contains('mem.commit') -and -not $classes.Contains('mem.app') -and
            -not $unchecked.Contains('mem.capacity') -and -not $unchecked.Contains('mem.commit') -and -not $unchecked.Contains('mem.app')) {
            $classes['mem.used'] = @{ Id = 'mem.used'; Level = $null; Values = @{ used = (& $fmt $Facts.UsedMax) } }
        }
    }
    # 10 undecidable: no class, and at least one could not be told
    if ($classes.Count -eq 0 -and $unchecked.Count -gt 0) {
        $names = New-Object System.Collections.Generic.List[string]
        foreach ($id in $unchecked.Keys) {
            $miss = @($unchecked[$id])
            if ($miss.Count -eq 0) { $miss = @('contradiction') }
            foreach ($m in $miss) { $label = [string]$Sizing.Missing[$m]; if (-not $names.Contains($label)) { $names.Add($label) } }
        }
        $classes['undecidable'] = @{ Id = 'undecidable'; Level = $null; Values = @{ missing = ($names.ToArray() -join ', ') } }
    }
    $outClasses = @(foreach ($id in $script:WorkerPerfSizingClassOrder) { if ($classes.Contains($id)) { $classes[$id] } })
    $outUnchecked = @(foreach ($id in $script:WorkerPerfSizingClassOrder) { if ($unchecked.Contains($id)) { @{ Id = $id; Missing = [string[]]@($unchecked[$id]) } } })
    return @{ Classes = [object[]]$outClasses; Unchecked = [object[]]$outUnchecked }
}

# Minimum share (%) of the largest application for the class one-off (as $WorkerPerfMinSharePct of the incident details)
$script:WorkerPerfSizingMinSharePct = 10

function Add-WorkerPerfIncidentClasses {
    # Sets Classes and Unchecked at every performance incident (empty lists where no class is asked).
    param([AllowEmptyCollection()][object[]]$Incidents, $Model, $Thresholds, $Sizing)
    foreach ($inc in @($Incidents)) {
        $facts = Get-WorkerPerfIncidentFacts $inc $Model $Thresholds $Sizing
        $r = Get-WorkerPerfIncidentClasses $facts $Sizing
        $inc['Classes'] = [object[]]@($r.Classes); $inc['Unchecked'] = [object[]]@($r.Unchecked)
    }
}

function Expand-WorkerPerfSizingText([string]$Template, $Values) {
    # replaces {name} by the value of that name; a placeholder without a value stays
    if ($null -eq $Values) { return $Template }
    $text = $Template
    foreach ($k in @($Values.Keys)) { $text = $text.Replace('{' + [string]$k + '}', [string]$Values[$k]) }
    return $text
}

function Get-WorkerPerfClassOut($Incident, $Sizing) {
    # The classes of an incident as texts of the catalogue: Line (the line "Einordnung: ...", '' without a class and
    # without an unsettled one), Classes = @([ordered]@{ id; level; label; reason; advice; sources }) (advice: the direction
    # of the class, what helps; not named direction, which is a keyword field of the report data),
    # Unchecked = @([ordered]@{ id; missing; text }).
    $classes = New-Object System.Collections.Generic.List[object]
    $labels = New-Object System.Collections.Generic.List[string]
    $reasons = New-Object System.Collections.Generic.List[string]
    foreach ($c in @(Get-WorkerPerfField $Incident 'Classes')) {
        if ($null -eq $c) { continue }
        $def = $Sizing.Classes[[string]$c.Id]
        $label = [string]$def.Label
        if ($null -ne $c.Level -and [string]$c.Level -ne '') { $label = '{0} ({1})' -f $def.Label, $Sizing.Levels[[string]$c.Level] }
        $reason = Expand-WorkerPerfSizingText ([string]$def.Reason) $c.Values
        $classes.Add([ordered]@{
                id = [string]$c.Id; level = $(if ($null -ne $c.Level) { [string]$c.Level } else { $null }); label = $label; reason = $reason
                advice = (Expand-WorkerPerfSizingText ([string]$def.Direction) $c.Values); sources = [string[]]@($def.Sources)
            })
        $labels.Add($label); $reasons.Add($reason)
    }
    $unchecked = New-Object System.Collections.Generic.List[object]
    $notes = New-Object System.Collections.Generic.List[string]
    foreach ($u in @(Get-WorkerPerfField $Incident 'Unchecked')) {
        if ($null -eq $u) { continue }
        $label = [string]$Sizing.Classes[[string]$u.Id].Label
        $missing = [string[]]@($u.Missing)
        if ($missing.Count -eq 0) { $text = Expand-WorkerPerfSizingText ([string]$Sizing.Texts['contradiction']) @{ label = $label } }
        else { $text = Expand-WorkerPerfSizingText ([string]$Sizing.Texts['unchecked']) @{ label = $label; missing = (@($missing | ForEach-Object { [string]$Sizing.Missing[$_] }) -join ', ') } }
        $unchecked.Add([ordered]@{ id = [string]$u.Id; missing = $missing; text = $text })
        $notes.Add($text)
    }
    $line = ''
    if ($classes.Count -gt 0) {
        $line = Expand-WorkerPerfSizingText ([string]$Sizing.Texts['line']) @{ labels = ($labels.ToArray() -join ', '); reason = ($reasons.ToArray() -join ' ') }
        if ($notes.Count -gt 0) { $line = $line + ' ' + ($notes.ToArray() -join '; ') + '.' }
    }
    return @{ Line = $line; Classes = [object[]]$classes.ToArray(); Unchecked = [object[]]$unchecked.ToArray() }
}

function Get-WorkerPerfRunAnalysis {
    # One recording, evaluated as the normal report does it (the same calls in the same order), with the class of every
    # incident: @{ Model; Series; Findings; Incidents }. A quick run has no measurement: empty lists.
    param([string]$Path, [datetime]$From = [datetime]::MinValue, [datetime]$To = [datetime]::MaxValue, $Thresholds, [object[]]$Roles, $Sizing)
    $model = Import-WorkerPerfRun -Path $Path -From $From -To $To -Thresholds $Thresholds -Roles $Roles
    if ([bool]$model.Meta['HealthOnly']) { return @{ Model = $model; Series = [object[]]@(); Findings = [object[]]@(); Incidents = [object[]]@() } }
    $series = @(Get-WorkerPerfSeries $model $Thresholds)
    $findings = @(Get-WorkerPerfFindings -Series $series -Thresholds $Thresholds)
    $incidents = @(Join-WorkerPerfIncidents -Findings $findings)
    Add-WorkerPerfIncidentDetail -Incidents $incidents -Model $model -Thresholds $Thresholds
    Add-WorkerPerfIncidentClasses -Incidents $incidents -Model $model -Thresholds $Thresholds -Sizing $Sizing
    return @{ Model = $model; Series = [object[]]$series; Findings = [object[]]$findings; Incidents = [object[]]$incidents }
}

# ---------------------------------------------------------------------------------------------
# Several recordings of one server: main time, figures per recording, recurring causes, projection
# ---------------------------------------------------------------------------------------------

function Get-WorkerPerfRunServer([string]$Path) {
    # The head of a recording from its meta.json only: @{ Path; Server; StartMs; OffsetMinutes; HealthOnly }.
    $metaPath = Join-Path $Path 'meta.json'
    if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) { throw "Die Aufzeichnung '$Path' hat keine meta.json; ist es ein Aufzeichnungsordner?" }
    $meta = ConvertFrom-WorkerPerfJsonFile $metaPath
    $startMs = [long]0; $offset = 0.0
    # the start as text (ConvertFrom-Json would turn it into a local time and lose the offset of the server)
    $raw = [regex]::Match([IO.File]::ReadAllText($metaPath, [Text.Encoding]::UTF8), '"StartTime"\s*:\s*"([^"]+)"')
    $text = ''
    if ($raw.Success) { $text = $raw.Groups[1].Value }
    $dto = [DateTimeOffset]::MinValue
    if ($text -ne '' -and [DateTimeOffset]::TryParse($text, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$dto)) {
        $startMs = $dto.ToUnixTimeMilliseconds(); $offset = $dto.Offset.TotalMinutes
    }
    $quick = Get-WorkerPerfField $meta 'HealthOnly'
    return @{ Path = $Path; Server = [string](Get-WorkerPerfField $meta 'Computer'); StartMs = $startMs; OffsetMinutes = $offset; HealthOnly = ($quick -is [bool] -and $quick) }
}

function Assert-WorkerPerfSameServer([object[]]$Runs) {
    # The one place that decides what "the same server" is (phase 1: the computer name, without regard to case). A later
    # comparison of several servers replaces this check.
    $list = @($Runs)
    if ($list.Count -eq 0) { return }
    $first = [string]$list[0].Server
    foreach ($r in $list) {
        if ([string]::Compare([string]$r.Server, $first, [StringComparison]::OrdinalIgnoreCase) -ne 0) {
            throw ("Die Aufzeichnung '{0}' stammt vom Server '{1}', die erste von '{2}'. Der Groessenbericht vergleicht nur Aufzeichnungen desselben Servers; der Vergleich verschiedener Server ist ein spaeterer Baustein." -f $r.Path, $r.Server, $first)
        }
    }
}

function Get-WorkerPerfTickSessions($Model) {
    # the number of sessions of every tick: that of the last snapshot at or before the tick, before the first one the first's
    $n = [int]$Model.Tick.N
    $out = New-Object double[] $n
    $sessions = @($Model.Snap.Sessions); $pos = @($Model.Snap.TickPos)
    if ($sessions.Count -eq 0) { return , $out }
    $p = 0
    for ($i = 0; $i -lt $n; $i++) {
        while ($p + 1 -lt $sessions.Count -and [int]$pos[$p + 1] -le $i) { $p++ }
        $v = [double]$sessions[$p]
        if ([double]::IsNaN($v)) { $v = 0.0 }
        $out[$i] = $v
    }
    return , $out
}

function Get-WorkerPerfMainTicks($Model, [double]$SessionPct) {
    # Main time: the ticks with at least SessionPct % of the highest number of sessions of the recording (no calendar
    # needed: it fits day work and shifts). A recording without sessions has none.
    $perTick = Get-WorkerPerfTickSessions $Model
    $peak = 0.0
    foreach ($v in $perTick) { if ($v -gt $peak) { $peak = $v } }
    if ($peak -le 0) { return }
    $need = $peak * $SessionPct / 100.0
    for ($i = 0; $i -lt $perTick.Length; $i++) { if ($perTick[$i] -ge $need) { $i } }
}

function Get-WorkerPerfSizingRun {
    # The figures of one recording for the sizing report, from its analysis (Get-WorkerPerfRunAnalysis): Path; Server;
    # StartMs; EndMs; DurationMin; EndReason; HealthOnly; Cores; RamMB; MainTicks (count); MainHours; Cpu @{ Peak; P95 };
    # Queue @{ Peak; P95 } (per CPU); Commit @{ PeakMB; P95MB; PeakPctRam }; SessionsPeak; MainCpu and MainSessions (the
    # values of the main time, tick by tick); CommitMaxMainMB; Classes (id -> number of incidents); Bottlenecks
    # @(@{ Id; StartMs; EndMs; Lead; ClassIds; App }); Health (the values of the health picture the catalogue names as
    # evidence, id -> value, or $null). A quick run has the head fields and Health only.
    param($Analysis, [string]$Path, $Sizing)
    $model = $Analysis.Model; $meta = $model.Meta
    $health = $null
    if ($null -ne $model.Health) {
        $health = [ordered]@{}
        foreach ($id in $Sizing.Evidence.Keys) {
            if (-not $script:WorkerPerfHealthValues.Contains($id)) { continue }
            $area = Get-WorkerPerfField (Get-WorkerPerfField $model.Health 'Areas') ([string]$script:WorkerPerfHealthValues[$id].Area)
            $entry = Get-WorkerPerfField (Get-WorkerPerfField $area 'Values') $id
            if ($null -ne $entry -and [string](Get-WorkerPerfField $entry 'State') -eq 'read') { $health[$id] = Get-WorkerPerfField $entry 'Value' }
        }
    }
    $head = Get-WorkerPerfRunServer $Path
    $run = @{
        Path = $Path; Server = [string]$meta['Computer']; StartMs = [long]$head.StartMs; EndMs = [long]$head.StartMs; DurationMin = 0.0
        OffsetMinutes = [double]$head.OffsetMinutes
        EndReason = [string]$meta['EndReason']; HealthOnly = [bool]$meta['HealthOnly']; Cores = [int]$meta['Cores']; RamMB = [double]$meta['RamMB']; Health = $health
    }
    if ($run.HealthOnly) {
        # the size of a quick run comes from its health picture
        if ($null -ne $health) {
            if ($null -ne $health['size.cpuLogical']) { $run.Cores = [int]$health['size.cpuLogical'] }
            if ($null -ne $health['size.memTotalMB']) { $run.RamMB = [double]$health['size.memTotalMB'] }
        }
        return $run
    }
    if ($null -ne $model.CaptureStartMs) { $run.StartMs = [long]$model.CaptureStartMs }
    if ($null -ne $model.CaptureEndMs) { $run.EndMs = [long]$model.CaptureEndMs }
    $run.DurationMin = ($run.EndMs - $run.StartMs) / 60000.0
    $sig = $model.Tick.Signal
    $max = { param([double[]]$Values) $m = [double]::NaN; foreach ($v in $Values) { if (-not [double]::IsNaN($v) -and ([double]::IsNaN($m) -or $v -gt $m)) { $m = $v } }; $m }
    $run.Cpu = @{ Peak = (& $max $sig['cpu.host']); P95 = (Get-WorkerPerfPercentile $sig['cpu.host'] 95) }
    $run.Queue = @{ Peak = (& $max $sig['cpu.queue']); P95 = (Get-WorkerPerfPercentile $sig['cpu.queue'] 95) }
    $committed = [double[]]$model.Tick.Raw['MemCommittedMB']
    $commitPeak = & $max $committed
    $pctRam = [double]::NaN
    if ($run.RamMB -gt 0 -and -not [double]::IsNaN($commitPeak)) { $pctRam = 100.0 * $commitPeak / $run.RamMB }
    $run.Commit = @{ PeakMB = $commitPeak; P95MB = (Get-WorkerPerfPercentile $committed 95); PeakPctRam = $pctRam }
    $perTick = Get-WorkerPerfTickSessions $model
    $run.SessionsPeak = [int](& $max $perTick)
    if ($run.SessionsPeak -lt 0) { $run.SessionsPeak = 0 }
    $main = [int[]]@(Get-WorkerPerfMainTicks $model ([double]$Sizing.Thresholds.mainSessionPct.Value))
    $mainCpu = New-Object double[] $main.Length; $mainSessions = New-Object double[] $main.Length
    $seconds = 0.0; $commitMain = [double]::NaN
    for ($k = 0; $k -lt $main.Length; $k++) {
        $i = $main[$k]
        $mainCpu[$k] = $sig['cpu.host'][$i]; $mainSessions[$k] = $perTick[$i]
        $e = [double]$model.Tick.ElapsedSec[$i]
        if (-not [double]::IsNaN($e) -and $e -gt 0) { $seconds += $e }
        $c = $committed[$i]
        if (-not [double]::IsNaN($c) -and ([double]::IsNaN($commitMain) -or $c -gt $commitMain)) { $commitMain = $c }
    }
    $run.MainTicks = $main.Length; $run.MainHours = $seconds / 3600.0; $run.MainCpu = $mainCpu; $run.MainSessions = $mainSessions; $run.CommitMaxMainMB = $commitMain
    $classes = @{}
    $bottlenecks = New-Object System.Collections.Generic.List[object]
    foreach ($inc in @($Analysis.Incidents)) {
        $ids = [string[]]@(@(Get-WorkerPerfField $inc 'Classes') | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.Id })
        if ($ids.Count -eq 0) { continue }
        foreach ($id in $ids) { if ($classes.ContainsKey($id)) { $classes[$id]++ } else { $classes[$id] = 1 } }
        $app = ''
        foreach ($c in @($inc.Classes)) { if ($app -eq '' -and $null -ne $c.Values -and $c.Values.ContainsKey('app')) { $app = [string]$c.Values['app'] } }
        $bottlenecks.Add(@{ Id = [int]$inc.Id; StartMs = [long]$inc.StartMs; EndMs = [long]$inc.EndMs; Lead = [string]$inc.Lead; ClassIds = $ids; App = $app })
    }
    $run.Classes = $classes; $run.Bottlenecks = [object[]]$bottlenecks.ToArray()
    return $run
}

function Group-WorkerPerfSizingRuns([object[]]$Runs, [ValidateSet('time')][string]$Axis = 'time') {
    # The recordings along an axis. Axis time: one group per server (phase 1: one), its recordings by their start. A later
    # axis "server" groups the other way round without another data format.
    $groups = [ordered]@{}
    foreach ($r in @($Runs)) {
        $key = ([string]$r.Server).ToUpperInvariant()
        if (-not $groups.Contains($key)) { $groups[$key] = New-Object System.Collections.Generic.List[object] }
        $groups[$key].Add($r)
    }
    foreach ($key in $groups.Keys) {
        @{ Key = $key; Runs = [object[]]@($groups[$key].ToArray() | Sort-Object -Property @{ Expression = { [long]$_.StartMs } }, @{ Expression = { [string]$_.Path } }) }
    }
}

function Get-WorkerPerfCpuNeed([int]$Cores, [double]$Load, [double]$Target, [double]$Factor) {
    # Not linear: twice the cores carry Factor times the load (1.5 to 1.9), so the size for the load is
    # Cores * (Load / Target) ^ (1 / log2(Factor)).
    return $Cores * [Math]::Pow($Load / $Target, 1.0 / [Math]::Log($Factor, 2))
}

function Get-WorkerPerfEvenUp([double]$Value) {
    # up to an even number of vCPU (a value that is even but for rounding noise stays)
    return [int](2 * [Math]::Ceiling([Math]::Round($Value, 6) / 2))
}

function Get-WorkerPerfCpuRange([int]$Cores, [double]$Load, [double]$Target, $Sizing) {
    # the range of the estimate: Low with the better scaling, High with the worse one
    return @{
        Low = (Get-WorkerPerfEvenUp (Get-WorkerPerfCpuNeed $Cores $Load $Target ([double]$Sizing.Thresholds.scalingHigh.Value)))
        High = (Get-WorkerPerfEvenUp (Get-WorkerPerfCpuNeed $Cores $Load $Target ([double]$Sizing.Thresholds.scalingLow.Value)))
    }
}

function Get-WorkerPerfCpuDecision {
    # What the report says about the CPU, in this order: no main time -> noMainTime; the VMware host recurring -> host
    # (no number of vCPU: more vCPU make it worse); the load at or under the target -> enough; capacity recurring ->
    # range (over the limit per server: scaleOut with the sessions the server carries at its size, counted down
    # linearly); else other, with the first recurring cause of singlecore, app, oneoff ('' without one).
    # Returns @{ Kind; Low; High; Sessions; Cause; Hints } (ids only, no texts).
    param([AllowEmptyCollection()][string[]]$Recurring = @(), [AllowEmptyCollection()][string[]]$Seen = @(), [double]$Load, [double]$Target, [int]$Cores,
        [int]$SessionsPeak, [bool]$HasMainTime, $Sizing)
    $d = @{ Kind = ''; Low = $null; High = $null; Sessions = $null; Cause = ''; Hints = [string[]]@() }
    $hints = New-Object System.Collections.Generic.List[string]
    $hostOnce = (@($Seen) -contains 'host' -and @($Recurring) -notcontains 'host')
    if (-not $HasMainTime -or [double]::IsNaN($Load)) { $d.Kind = 'noMainTime'; return $d }
    if (@($Recurring) -contains 'host') { $d.Kind = 'host'; $d.Hints = [string[]]@('hostCheck'); return $d }
    if ($hostOnce) { $hints.Add('hostOnce') }
    if ($Load -le $Target) { $d.Kind = 'enough'; $d.Hints = [string[]]$hints.ToArray(); return $d }
    if (@($Recurring) -contains 'capacity') {
        $range = Get-WorkerPerfCpuRange $Cores $Load $Target $Sizing
        if ($range.High -gt [double]$Sizing.Thresholds.vcpuMax.Value) {
            $d.Kind = 'scaleOut'; $d.Sessions = [int][Math]::Floor($SessionsPeak * $Target / $Load)
        }
        else {
            $d.Kind = 'range'; $d.Low = [int]$range.Low; $d.High = [int]$range.High
            if ($range.High -gt [double]$Sizing.Thresholds.vcpuScaleOut.Value) { $hints.Add('scaleOutToo') }
            $hints.Add('numa')
        }
        if (@($Recurring) -contains 'singlecore') { $hints.Add('singlecoreToo') }
        $d.Hints = [string[]]$hints.ToArray()
        return $d
    }
    $d.Kind = 'other'
    foreach ($c in 'singlecore', 'app', 'oneoff') { if ($d.Cause -eq '' -and @($Recurring) -contains $c) { $d.Cause = $c } }
    $d.Hints = [string[]]$hints.ToArray()
    return $d
}

function Get-WorkerPerfRamTarget([double]$CommitMB, $Sizing) {
    # RAM (GB) so that the committed memory is at most memTargetPct of it, up to a full step
    $step = [double]$Sizing.Thresholds.memStepGB.Value
    $gb = $CommitMB / ([double]$Sizing.Thresholds.memTargetPct.Value / 100.0) / 1024.0
    return [int]($step * [Math]::Ceiling([Math]::Round($gb / $step, 6)))
}

function Get-WorkerPerfMemoryDecision {
    # What the report says about the memory: more RAM only with a recurring shortage (lasting page output); the commit
    # limit alone means the page file; a recurring single application means that application; else enough.
    # Returns @{ Kind ('more' | 'pagefile' | 'app' | 'enough'); TargetGB; Hints }.
    param([AllowEmptyCollection()][string[]]$Recurring = @(), [double]$CommitMaxMB, [double]$RamMB, $Sizing)
    $d = @{ Kind = 'enough'; TargetGB = $null; Hints = [string[]]@() }
    if (@($Recurring) -contains 'mem.capacity') {
        $d.Kind = 'more'; $d.TargetGB = Get-WorkerPerfRamTarget $CommitMaxMB $Sizing; $d.Hints = [string[]]@('memPerSession', 'commitAboveRam')
    }
    elseif (@($Recurring) -contains 'mem.commit') { $d.Kind = 'pagefile' }
    elseif (@($Recurring) -contains 'mem.app') { $d.Kind = 'app' }
    elseif (-not [double]::IsNaN($CommitMaxMB) -and $CommitMaxMB -gt $RamMB) { $d.Hints = [string[]]@('commitAboveRam') }
    return $d
}

# classes that are no bottleneck of their own in the result sentence (memory in use is no shortage; undecidable names a gap)
$script:WorkerPerfSizingNoResultClasses = @('mem.used', 'undecidable')

function Get-WorkerPerfSizingSummary {
    # The recordings of one group (one server) together: Server; Runs (all, by start); LoadRuns (without quick runs);
    # Seen (class -> number of recordings with it); Recurring (the classes in at least recurringPct of the recordings with
    # a measurement); Load (L: P95 of the CPU over the main time of all recordings); Peak; Target; SessionsPeak;
    # CommitMaxMB (of the main time); Cores, RamMB (of the last recording with a measurement); SizeChanged; Sizes (the
    # sizes in their order); MainHours; TotalHours; LowMeasure; Cpu and Memory (the decisions); Result @{ Key
    # ('recurring' | 'once' | 'none'); Class; Resource; Count; Total }; Evidence (the newest health picture of all
    # recordings, quick runs included, or $null).
    param($Group, $Sizing)
    $runs = [object[]]@(@($Group.Runs) | Sort-Object -Property @{ Expression = { [long]$_.StartMs } })
    $load = [object[]]@($runs | Where-Object { -not [bool]$_.HealthOnly })
    $own = $Sizing.Thresholds
    $seen = [ordered]@{}; $recurring = [ordered]@{}
    foreach ($id in $script:WorkerPerfSizingClassOrder) {
        $n = @($load | Where-Object { $null -ne $_.Classes -and $_.Classes.ContainsKey($id) -and [int]$_.Classes[$id] -gt 0 }).Count
        if ($n -eq 0) { continue }
        $seen[$id] = $n
        if (100.0 * $n / $load.Count -ge [double]$own.recurringPct.Value) { $recurring[$id] = $n }
    }
    $pooled = New-Object System.Collections.Generic.List[double]
    $peak = [double]::NaN; $sessionsPeak = 0; $commitMax = [double]::NaN; $mainHours = 0.0; $totalHours = 0.0
    $sizes = New-Object System.Collections.Generic.List[object]
    foreach ($r in $load) {
        foreach ($v in @($r.MainCpu)) { $pooled.Add([double]$v) }
        $p = [double]$r.Cpu.Peak
        if (-not [double]::IsNaN($p) -and ([double]::IsNaN($peak) -or $p -gt $peak)) { $peak = $p }
        if ([int]$r.SessionsPeak -gt $sessionsPeak) { $sessionsPeak = [int]$r.SessionsPeak }
        $c = [double]$r.CommitMaxMainMB
        if (-not [double]::IsNaN($c) -and ([double]::IsNaN($commitMax) -or $c -gt $commitMax)) { $commitMax = $c }
        $mainHours += [double]$r.MainHours; $totalHours += [double]$r.DurationMin / 60.0
        if ($sizes.Count -eq 0 -or [int]$sizes[$sizes.Count - 1].Cores -ne [int]$r.Cores -or [double]$sizes[$sizes.Count - 1].RamMB -ne [double]$r.RamMB) {
            $sizes.Add(@{ Cores = [int]$r.Cores; RamMB = [double]$r.RamMB })
        }
    }
    $cores = 0; $ramMb = 0.0
    if ($load.Count -gt 0) { $cores = [int]$load[$load.Count - 1].Cores; $ramMb = [double]$load[$load.Count - 1].RamMB }
    $loadValue = Get-WorkerPerfPercentile $pooled.ToArray() 95
    $target = [double]$Sizing.Limits.target.Value
    $cpu = Get-WorkerPerfCpuDecision -Recurring ([string[]]@($recurring.Keys)) -Seen ([string[]]@($seen.Keys)) -Load $loadValue -Target $target -Cores $cores `
        -SessionsPeak $sessionsPeak -HasMainTime ($pooled.Count -gt 0) -Sizing $Sizing
    $memory = Get-WorkerPerfMemoryDecision -Recurring ([string[]]@($recurring.Keys)) -CommitMaxMB $commitMax -RamMB $ramMb -Sizing $Sizing
    $result = @{ Key = 'none'; Class = ''; Resource = ''; Count = 0; Total = $load.Count }
    foreach ($pair in @(@('recurring', $recurring), @('once', $seen))) {
        if ($result.Key -ne 'none') { break }
        foreach ($id in $pair[1].Keys) {
            if ($script:WorkerPerfSizingNoResultClasses -contains $id) { continue }
            $res = [string]$Sizing.Classes[$id].Resource
            if ($res -ne 'memory') { $res = 'cpu' }
            $result = @{ Key = $pair[0]; Class = [string]$id; Resource = $res; Count = [int]$pair[1][$id]; Total = $load.Count }
            break
        }
    }
    $evidence = $null
    foreach ($r in $runs) { if ($null -ne $r.Health) { $evidence = $r.Health } }
    $server = [string]$Group.Key
    if ($runs.Count -gt 0) { $server = [string]$runs[0].Server }
    return @{
        Server = $server; Runs = $runs; LoadRuns = $load; Seen = $seen; Recurring = $recurring
        Load = $loadValue; Peak = $peak; Target = $target; SessionsPeak = $sessionsPeak; CommitMaxMB = $commitMax; Cores = $cores; RamMB = $ramMb
        SizeChanged = ($sizes.Count -gt 1); Sizes = [object[]]$sizes.ToArray(); MainHours = $mainHours; TotalHours = $totalHours
        LowMeasure = ($load.Count -lt [double]$own.minRecordings.Value -or $mainHours -lt [double]$own.minMainHours.Value)
        Cpu = $cpu; Memory = $memory; Result = $result; Evidence = $evidence
    }
}

# ---------------------------------------------------------------------------------------------
# Report data and copy text of the sizing report
# ---------------------------------------------------------------------------------------------

function Format-WorkerPerfSizingText($Sizing, [string]$Key, $Values = $null) {
    return (Expand-WorkerPerfSizingText ([string]$Sizing.Texts[$Key]) $Values)
}

function New-WorkerPerfSizingData {
    # The report data of the sizing report from the summary of one server (Get-WorkerPerfSizingSummary). Commands: the
    # path of a recording -> the command that makes its report. Generated: Unix ms. Every sentence comes from the
    # catalogue. Fields: meta, grades, result, recommendations, runs, bottlenecks, recurring, usersPerVcpu, scatter,
    # evidence, sources and copy (set by the caller).
    param($Summary, $Sizing, [hashtable]$Commands = @{}, [long]$Generated = 0)
    $fmt = { param($v, [int]$d = 1) Format-WorkerPerfSizingNumber $v $d }
    # a value that does not exist, and the sign between two sizes (this file is ASCII)
    $dash = [string][char]0x2013; $arrow = ' ' + [char]0x2192 + ' '
    $round = { param($v, [int]$d = 1) if ($null -eq $v -or [double]::IsNaN([double]$v)) { $null } else { [Math]::Round([double]$v, $d) } }
    $own = $Sizing.Thresholds
    $runs = @($Summary.Runs); $load = @($Summary.LoadRuns); $total = $load.Count
    $usedSources = New-Object System.Collections.Generic.List[string]
    $addSources = { param($Ids) foreach ($s in @($Ids)) { if ($s -and -not $usedSources.Contains([string]$s)) { $usedSources.Add([string]$s) } } }
    $sizeText = { param($s) Format-WorkerPerfSizingText $Sizing 'size.item' @{ cores = (& $fmt $s.Cores 0); ram = (& $fmt ([double]$s.RamMB / 1024.0) 0) } }

    # ---- result sentence ----
    $loadText = $dash
    if (-not [double]::IsNaN([double]$Summary.Load)) { $loadText = & $fmt $Summary.Load }
    $res = $Summary.Result
    $resultValues = @{ total = [string]$res.Total; load = $loadText; sessions = [string]$Summary.SessionsPeak; count = [string]$res.Count }
    if ($res.Key -ne 'none') {
        $resultValues['resource'] = Format-WorkerPerfSizingText $Sizing ('resource.' + $res.Resource)
        $resultValues['class'] = [string]$Sizing.Classes[$res.Class].Label
    }
    $resultText = Format-WorkerPerfSizingText $Sizing ('result.' + $res.Key) $resultValues

    # ---- recommendations ----
    $reliability = Format-WorkerPerfSizingText $Sizing 'reliability' @{ runs = [string]$total; hours = (& $fmt $Summary.TotalHours); main = (& $fmt $Summary.MainHours) }
    if ($Summary.LowMeasure) {
        $reliability += ' ' + (Format-WorkerPerfSizingText $Sizing 'hint.lowMeasure' @{ runs = [string]$total; hours = (& $fmt $Summary.MainHours)
                minRuns = (& $fmt $own.minRecordings.Value 0); minHours = (& $fmt $own.minMainHours.Value) })
    }
    $assumptions = [string[]](@($Sizing.Texts['assumptions']) + @([string]$Sizing.Texts['pilot']))
    $recurringList = @(foreach ($id in $Summary.Recurring.Keys) {
            Format-WorkerPerfSizingText $Sizing 'recurring.item' @{ class = [string]$Sizing.Classes[$id].Label; count = [string]$Summary.Recurring[$id]; total = [string]$total } })
    $causes = Format-WorkerPerfSizingText $Sizing 'reason.noRecurring'
    if ($recurringList.Count -gt 0) { $causes = Format-WorkerPerfSizingText $Sizing 'reason.recurring' @{ list = ($recurringList -join ', ') } }
    $hintText = {
        param([string]$Id)
        $v = @{ scaleOut = (& $fmt $own.vcpuScaleOut.Value 0); total = [string]$total; count = '0' }
        if ($Summary.Seen.Contains('host')) { $v['count'] = [string]$Summary.Seen['host'] }
        Format-WorkerPerfSizingText $Sizing ('hint.' + $Id) $v
    }
    $recs = New-Object System.Collections.Generic.List[object]
    $newRec = {
        param([string]$Resource, [string]$Status, [string]$Direction, [string]$Reason, $Projection, [string[]]$Hints, [string[]]$Sources)
        & $addSources $Sources
        $assume = [string[]]@()
        if ($null -ne $Projection) { $assume = $assumptions }
        [ordered]@{ resource = $Resource; status = $Status; advice = $Direction; reason = $Reason; projection = $Projection
            assumptions = $assume; hints = [string[]]@($Hints | Where-Object { $_ }); sources = [string[]]@($Sources); reliability = $reliability }
    }

    # CPU
    $cpu = $Summary.Cpu
    $cpuReason = Format-WorkerPerfSizingText $Sizing 'reason.cpu' @{ load = $loadText; peak = (& $fmt $Summary.Peak); target = (& $fmt $Summary.Target); causes = $causes }
    $cpuHints = New-Object System.Collections.Generic.List[string]
    foreach ($h in @($cpu.Hints)) { $cpuHints.Add((& $hintText $h)) }
    if ($Summary.SizeChanged) { $cpuHints.Add((Format-WorkerPerfSizingText $Sizing 'hint.sizeChanged' @{ sizes = (@($Summary.Sizes | ForEach-Object { & $sizeText $_ }) -join $arrow) })) }
    $projection = $null; $status = 'check'; $direction = ''; $cpuSources = [string[]]@()
    $rangeValues = @{ low = [string]$cpu.Low; high = [string]$cpu.High; cores = [string]$Summary.Cores; target = (& $fmt $Summary.Target); load = $loadText; sessions = [string]$cpu.Sessions }
    switch ([string]$cpu.Kind) {
        'range' {
            $status = 'act'; $direction = Format-WorkerPerfSizingText $Sizing 'dir.cpu.range'
            $key = 'cpu.range'; if ([int]$cpu.Low -eq [int]$cpu.High) { $key = 'cpu.rangeOne' }
            $projection = [ordered]@{ kind = 'range'; low = [int]$cpu.Low; high = [int]$cpu.High; sessions = $null; unit = 'vCPU'; text = (Format-WorkerPerfSizingText $Sizing $key $rangeValues) }
            $cpuSources = [string[]](@($Sizing.Classes['capacity'].Sources) + @($own.scalingLow.Sources) + @($own.vcpuScaleOut.Sources) + @('VM-10', 'SZ-22', 'SZ-23', 'SZ-46'))
        }
        'scaleOut' {
            $status = 'act'; $direction = Format-WorkerPerfSizingText $Sizing 'dir.cpu.scaleOut'
            $projection = [ordered]@{ kind = 'scaleOut'; low = $null; high = $null; sessions = [int]$cpu.Sessions; unit = 'Sitzungen'; text = (Format-WorkerPerfSizingText $Sizing 'cpu.scaleOut' $rangeValues) }
            $cpuSources = [string[]](@($Sizing.Classes['capacity'].Sources) + @($own.vcpuMax.Sources) + @('SZ-46'))
        }
        'host' { $status = 'act'; $direction = Format-WorkerPerfSizingText $Sizing 'cpu.host'; $cpuSources = [string[]]@($Sizing.Classes['host'].Sources) }
        'enough' { $status = 'ok'; $direction = Format-WorkerPerfSizingText $Sizing 'cpu.enough' $rangeValues; $cpuSources = [string[]]@('VM-08', 'SZ-45') }
        'noMainTime' { $direction = Format-WorkerPerfSizingText $Sizing 'cpu.noMainTime' }
        default {
            if ([string]$cpu.Cause -ne '') { $direction = Format-WorkerPerfSizingText $Sizing 'cpu.other' @{ cause = [string]$Sizing.Classes[[string]$cpu.Cause].Label }; $cpuSources = [string[]]@($Sizing.Classes[[string]$cpu.Cause].Sources) }
            else { $direction = Format-WorkerPerfSizingText $Sizing 'cpu.otherNone' }
        }
    }
    $recs.Add((& $newRec 'cpu' $status $direction $cpuReason $projection $cpuHints.ToArray() $cpuSources))

    # memory
    $mem = $Summary.Memory
    $commitGB = [double]$Summary.CommitMaxMB / 1024.0; $ramGB = [double]$Summary.RamMB / 1024.0
    $commitText = $dash; if (-not [double]::IsNaN($commitGB)) { $commitText = & $fmt $commitGB }
    $memReason = Format-WorkerPerfSizingText $Sizing 'reason.memory' @{ commit = $commitText; ram = (& $fmt $ramGB 0); causes = $causes }
    $memHints = @(foreach ($h in @($mem.Hints)) { & $hintText $h })
    $projection = $null; $status = 'ok'; $direction = Format-WorkerPerfSizingText $Sizing 'mem.enough'; $memSources = [string[]]@('SZ-35')
    switch ([string]$mem.Kind) {
        'more' {
            $status = 'act'; $direction = [string]$Sizing.Classes['mem.capacity'].Direction
            $projection = [ordered]@{ kind = 'ram'; low = [int]$mem.TargetGB; high = [int]$mem.TargetGB; sessions = $null; unit = 'GB'
                text = (Format-WorkerPerfSizingText $Sizing 'mem.more' @{ target = [string]$mem.TargetGB; ram = (& $fmt $ramGB 0); commit = $commitText; pct = (& $fmt $own.memTargetPct.Value 0) }) }
            $memSources = [string[]](@($Sizing.Classes['mem.capacity'].Sources) + @('ST-02', 'SZ-46'))
        }
        'pagefile' { $status = 'check'; $direction = Format-WorkerPerfSizingText $Sizing 'mem.pagefile'; $memSources = [string[]]@($Sizing.Classes['mem.commit'].Sources) }
        'app' { $status = 'check'; $direction = Format-WorkerPerfSizingText $Sizing 'mem.app' }
    }
    if (@($mem.Hints) -contains 'commitAboveRam' -and $memSources -notcontains 'ST-02') { $memSources = [string[]](@($memSources) + @('ST-02')) }
    $recs.Add((& $newRec 'memory' $status $direction $memReason $projection $memHints $memSources))

    # the VMware host and the performance per core, where seen
    if ($Summary.Seen.Contains('host')) {
        $status = 'check'; if ($Summary.Recurring.Contains('host')) { $status = 'act' }
        $reason = Format-WorkerPerfSizingText $Sizing 'reason.host' @{ count = [string]$Summary.Seen['host']; total = [string]$total }
        $recs.Add((& $newRec 'host' $status ([string]$Sizing.Classes['host'].Direction) $reason $null @((& $hintText 'hostCheck')) ([string[]]@($Sizing.Classes['host'].Sources))))
    }
    if ($Summary.Seen.Contains('singlecore')) {
        $reason = Format-WorkerPerfSizingText $Sizing 'reason.singlecore' @{ count = [string]$Summary.Seen['singlecore']; total = [string]$total }
        $hints = @()
        if ($null -ne $Summary.Evidence -and $null -ne $Summary.Evidence['operation.powerPlan']) { $hints = @(Format-WorkerPerfSizingText $Sizing 'hint.powerPlan' @{ value = [string]$Summary.Evidence['operation.powerPlan'] }) }
        $recs.Add((& $newRec 'singlecore' 'check' ([string]$Sizing.Classes['singlecore'].Direction) $reason $null $hints ([string[]]@($Sizing.Classes['singlecore'].Sources))))
    }

    # ---- recordings, bottlenecks, recurring ----
    $runsOut = New-Object System.Collections.Generic.List[object]
    $bottlenecks = New-Object System.Collections.Generic.List[object]
    $from = $null; $to = $null; $index = 0; $duration = 0.0
    foreach ($r in $runs) {
        $index++
        $quick = [bool]$r.HealthOnly
        if (-not $quick) {
            if ($null -eq $from -or [long]$r.StartMs -lt $from) { $from = [long]$r.StartMs }
            if ($null -eq $to -or [long]$r.EndMs -gt $to) { $to = [long]$r.EndMs }
            $duration += [double]$r.DurationMin
        }
        $classIds = [string[]]@()
        if (-not $quick) { $classIds = [string[]]@($script:WorkerPerfSizingClassOrder | Where-Object { $r.Classes.ContainsKey($_) }) }
        & $addSources @($classIds | ForEach-Object { $Sizing.Classes[$_].Sources })
        $entry = [ordered]@{
            index = $index; server = [string]$r.Server; folder = [string]$r.Path; start = [long]$r.StartMs; end = [long]$r.EndMs
            durationMin = (& $round $r.DurationMin 1); endReason = [string]$r.EndReason; healthOnly = $quick
            cores = [int]$r.Cores; ramGB = (& $round ([double]$r.RamMB / 1024.0) 1); mainHours = $null; cpu = $null; queue = $null; commit = $null; sessionsPeak = $null
            command = [string]$Commands[[string]$r.Path]; classIds = $classIds
            classLabels = [string[]]@($classIds | ForEach-Object { [string]$Sizing.Classes[$_].Label }); offsetMin = [double](Get-WorkerPerfField $r 'OffsetMinutes')
        }
        if (-not $quick) {
            $entry.mainHours = & $round $r.MainHours 2
            $entry.cpu = [ordered]@{ peak = (& $round $r.Cpu.Peak 1); p95 = (& $round $r.Cpu.P95 1) }
            $entry.queue = [ordered]@{ peak = (& $round $r.Queue.Peak 2); p95 = (& $round $r.Queue.P95 2) }
            $entry.commit = [ordered]@{ peakGB = (& $round ([double]$r.Commit.PeakMB / 1024.0) 1); p95GB = (& $round ([double]$r.Commit.P95MB / 1024.0) 1); peakPct = (& $round $r.Commit.PeakPctRam 1) }
            $entry.sessionsPeak = [int]$r.SessionsPeak
            foreach ($b in @($r.Bottlenecks)) {
                $labels = @($b.ClassIds | ForEach-Object { [string]$Sizing.Classes[$_].Label }) -join ', '
                $bottlenecks.Add([ordered]@{ run = $index; id = [int]$b.Id; start = [long]$b.StartMs; end = [long]$b.EndMs; lead = [string]$b.Lead
                        classIds = [string[]]@($b.ClassIds); label = $labels; app = [string]$b.App })
            }
        }
        $runsOut.Add($entry)
    }
    $recurringOut = @(foreach ($id in $Summary.Recurring.Keys) { [ordered]@{ id = [string]$id; label = [string]$Sizing.Classes[$id].Label; count = [int]$Summary.Recurring[$id]; of = $total } })

    # ---- sessions per vCPU, scatter, evidence, sources ----
    $cores = [int]$Summary.Cores
    $perVcpu = $null; if ($cores -gt 0) { $perVcpu = [Math]::Round([double]$Summary.SessionsPeak / $cores, 2) }
    $limits = @(foreach ($u in $Sizing.Users.Keys) { [ordered]@{ id = [string]$u; label = [string]$Sizing.Users[$u].Label; perVcpu = [double]$Sizing.Users[$u].PerVcpu; sessions = [int]([double]$Sizing.Users[$u].PerVcpu * $cores) } })
    & $addSources @('SZ-43')
    $points = 0
    foreach ($r in $load) { $points += @($r.MainCpu).Count }
    $step = [int][Math]::Ceiling($points / 2000.0); if ($step -lt 1) { $step = 1 }
    $sbCpu = New-Object System.Text.StringBuilder; $sbSess = New-Object System.Text.StringBuilder
    [void]$sbCpu.Append('['); [void]$sbSess.Append('[')
    $n = 0; $written = 0
    $inv = [Globalization.CultureInfo]::InvariantCulture
    foreach ($r in $load) {
        $c = @($r.MainCpu); $s = @($r.MainSessions)
        for ($i = 0; $i -lt $c.Count; $i++) {
            if (($n++ % $step) -ne 0 -or [double]::IsNaN([double]$c[$i])) { continue }
            if ($written -gt 0) { [void]$sbCpu.Append(','); [void]$sbSess.Append(',') }
            [void]$sbCpu.Append([Math]::Round([double]$c[$i], 1).ToString($inv)); [void]$sbSess.Append([Math]::Round([double]$s[$i], 0).ToString($inv))
            $written++
        }
    }
    [void]$sbCpu.Append(']'); [void]$sbSess.Append(']')
    $evidence = New-Object System.Collections.Generic.List[object]
    if ($null -ne $Summary.Evidence) {
        foreach ($id in $Sizing.Evidence.Keys) {
            if ($null -eq $Summary.Evidence[$id]) { continue }
            $value = $Summary.Evidence[$id]
            if ($value -is [double] -or $value -is [single] -or $value -is [decimal]) { $value = & $fmt $value 1 }
            $evidence.Add([ordered]@{ id = [string]$id; label = [string]$Sizing.Evidence[$id]; value = [string]$value })
        }
    }
    $sourcesOut = @($Sizing.Sources.Keys | Where-Object { $usedSources.Contains($_) } | ForEach-Object {
            $src = $Sizing.Sources[$_]
            [ordered]@{ id = [string]$_; title = [string]$src.Title; url = [string]$src.Url; date = [string]$src.Date; kind = [string]$src.Kind } })
    $grades = [ordered]@{}
    foreach ($g in $Sizing.Grades.Keys) { $grades[$g] = [ordered]@{ word = [string]$Sizing.Grades[$g].Word; symbol = [string]$Sizing.Grades[$g].Symbol } }

    return [ordered]@{
        meta = [ordered]@{
            server = [string]$Summary.Server; axis = 'time'; from = $from; to = $to; recordings = $total; quick = ($runs.Count - $total)
            durationMin = (& $round $duration 1); mainHours = (& $round $Summary.MainHours 2); cores = $cores; ramGB = (& $round $ramGB 1)
            sizes = @($Summary.Sizes | ForEach-Object { [ordered]@{ cores = [int]$_.Cores; ramGB = (& $round ([double]$_.RamMB / 1024.0) 1) } })
            sizeChanged = [bool]$Summary.SizeChanged; lowMeasure = [bool]$Summary.LowMeasure; catalogueVersion = [string]$Sizing.Version
            target = [double]$Summary.Target; load = (& $round $Summary.Load 1); peak = (& $round $Summary.Peak 1); sessionsPeak = [int]$Summary.SessionsPeak
            generated = $Generated; mask = $null
        }
        grades = $grades
        result = [ordered]@{ text = $resultText; key = [string]$res.Key }
        recommendations = $recs.ToArray()
        runs = $runsOut.ToArray()
        bottlenecks = $bottlenecks.ToArray()
        recurring = $recurringOut
        usersPerVcpu = [ordered]@{ value = $perVcpu; sessionsPeak = [int]$Summary.SessionsPeak; cores = $cores; note = [string]$Sizing.Texts['usersNote']; limits = $limits }
        scatter = [ordered]@{ cpu = $sbCpu; sessions = $sbSess; target = [double]$Summary.Target }
        evidence = $evidence.ToArray()
        sources = $sourcesOut
        copy = [ordered]@{ named = $null; anonymous = $null }
    }
}

function Get-WorkerPerfSizingCopyParagraphs($Data, $Sizing) {
    # The copy text of the sizing report as unwrapped paragraphs: the head with the result, then per recommendation its
    # direction, its projection, the assumptions and the hints, at the end how reliable it is.
    Format-WorkerPerfSizingText $Sizing 'copy.head' @{ server = [string]$Data['meta']['server']; result = [string]$Data['result']['text'] }
    foreach ($r in @($Data['recommendations'])) {
        ''
        $text = [string]$r['advice']
        Format-WorkerPerfSizingText $Sizing 'copy.recommendation' @{ resource = (Format-WorkerPerfSizingText $Sizing ('rec.' + [string]$r['resource'])); text = $text }
        [string]$r['reason']
        if ($null -ne $r['projection']) {
            [string]$r['projection']['text']
            Format-WorkerPerfSizingText $Sizing 'copy.assumptions' @{ list = (@($r['assumptions']) -join '; ') }
        }
        foreach ($h in @($r['hints'])) { '- ' + [string]$h }
    }
    ''
    [string]@($Data['recommendations'])[0]['reliability']
}
