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
    'copy.head' = @('server', 'result'); 'copy.recommendation' = @('resource', 'text')
}

$script:WorkerPerfSizingParts = @('version', 'sources', 'thresholds', 'limits', 'classes', 'levels', 'grades', 'users', 'signals', 'missing', 'evidence', 'texts')
$script:WorkerPerfSizingThresholdNames = @('coreBusyPct', 'sustainedPct', 'singleCoreMaxCores', 'appSharePct', 'leakGrowthPct', 'pagesOutLowPerSec',
    'pagesOutSharePct', 'recurringPct', 'minRecordings', 'minMainHours', 'mainSessionPct', 'scalingLow', 'scalingHigh', 'vcpuScaleOut', 'vcpuMax',
    'memTargetPct', 'memStepGB')
$script:WorkerPerfSizingLimitNames = @('target', 'cpuCrit', 'queueWarn', 'stealWarn', 'commitCrit')
$script:WorkerPerfSizingSignalNames = @('cpu.coreMax', 'cpu.coreBusy', 'cpu.perf', 'cpu.utility', 'mem.pagesout')
$script:WorkerPerfSizingMissingNames = @('cpu.coreMax', 'cpu.steal', 'mem.pagesout', 'processes')

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
