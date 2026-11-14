#Requires -Version 5.1
# WorkerPerf analysis library: reads a capture folder into an in-memory model and derives measurement series.
# Defines functions only. Callers dot-source WorkerPerf.Common.ps1 and WorkerPerf.Events.ps1 as well.
# The model is a hashtable; its lists are arrays. Get-WorkerPerfSeries emits plain pipeline output: wrap calls in @(...).

# Capture files (full path -> $true) that the loader reads as missing: the files of the categories that the field Skip of
# the capture's meta.json names (Import-WorkerPerfRun sets them), so a capture whose Skip contradicts its files gives the
# report of its Skip (MK-R20). The collector never writes such a file.
$script:WorkerPerfLeftOutFiles = @{}
function Test-WorkerPerfRunFile([string]$Full) {
    return ((Test-Path -LiteralPath $Full) -and -not $script:WorkerPerfLeftOutFiles.ContainsKey($Full))
}

function Open-WorkerPerfCsvReader {
    # Opens one capture file for reading line by line and reads its header line.
    # Returns @{ Col = column name -> index; Need = number of columns of the format; Reader = StreamReader, or $null for a
    # missing file }. The caller disposes Reader: it calls this as the first statement inside its try and disposes in finally. Callers split each non-empty line with Split(',') when it holds no quote,
    # else with Split-WorkerPerfCsvLine, and skip rows with fewer than Need fields (as Read-WorkerPerfCsvFile does).
    # -OwnHeader: Col holds only the columns of the file's own header and Need is its width, for a file whose columns
    # differ between formats (events.csv of format 2 has 5, of format 3 has 20); a missing file then has no columns.
    param([string]$Path, [string]$FileName, [switch]$OwnHeader)
    $col = @{}
    $need = 0
    if (-not $OwnHeader) {
        $canon = $script:WorkerPerfHeaders[$FileName].Split(',')
        for ($i = 0; $i -lt $canon.Length; $i++) { $col[$canon[$i]] = $i }
        $need = $canon.Length
    }
    $full = Join-Path $Path $FileName
    if (-not (Test-WorkerPerfRunFile $full)) { return @{ Col = $col; Need = $need; Reader = $null } }
    $stream = [IO.File]::Open($full, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $reader = $null
    try {
        $reader = New-Object System.IO.StreamReader($stream, [Text.Encoding]::UTF8)
        $header = $reader.ReadLine()
        if ($null -ne $header -and $header.Length -gt 0) {
            $names = $header.Split(',')
            for ($i = 0; $i -lt $names.Length; $i++) { $col[$names[$i].Trim()] = $i }
            if ($OwnHeader) { $need = $names.Length }
        }
    }
    catch {
        # close what was opened here; the reader owns the stream once it exists
        if ($null -ne $reader) { $reader.Dispose() } else { $stream.Dispose() }
        throw
    }
    return @{ Col = $col; Need = $need; Reader = $reader }
}

function Read-WorkerPerfCsvFile {
    # Reads one capture file. Returns @{ Col = column name -> index; Rows = List[string[]]; Skipped = number of rows left out }.
    # A missing file counts as an empty one; rows with fewer fields than the format has columns are skipped (and counted).
    # -OwnHeader: by the file's own header (see Open-WorkerPerfCsvReader).
    param([string]$Path, [string]$FileName, [switch]$OwnHeader)
    $rows = New-Object System.Collections.Generic.List[string[]]
    $skipped = 0
    $reader = $null
    try {
        $csv = Open-WorkerPerfCsvReader $Path $FileName -OwnHeader:$OwnHeader
        $reader = $csv.Reader; $need = $csv.Need
        while ($null -ne $reader -and $null -ne ($line = $reader.ReadLine())) {
            if ($line.Length -eq 0) { continue }
            if ($line.IndexOf('"') -lt 0) { $f = $line.Split(',') } else { $f = [string[]]@(Split-WorkerPerfCsvLine $line) }
            if ($f.Length -ge $need) { $rows.Add($f) } else { $skipped++ }
        }
    }
    finally { if ($null -ne $reader) { $reader.Dispose() } }
    return @{ Col = $csv.Col; Rows = $rows; Skipped = $skipped }
}

function ConvertTo-WorkerPerfTimestamp([string]$Text) {
    # DateTimeOffset or $null.
    $dto = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse($Text, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$dto)) { return $dto }
    return $null
}

function ConvertTo-WorkerPerfCachedDouble([System.Collections.Hashtable]$Cache, [string]$Text) {
    # Parses an invariant number (NaN for an empty or unreadable text), stores it in $Cache under the text and returns it.
    # Callers look the text up in $Cache first and call this only on a miss.
    $v = [double]::NaN
    if ($Text.Length -gt 0 -and -not [double]::TryParse($Text, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { $v = [double]::NaN }
    $Cache[$Text] = $v
    return $v
}

function Format-WorkerPerfWallClock([long]$Ticks) {
    # Clock time (ticks of a DateTime, no time zone) as dd.MM.yyyy HH:mm:ss for messages.
    return (New-Object DateTime ($Ticks)).ToString('dd.MM.yyyy HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
}

function New-WorkerPerfNanArray([int]$Length) {
    $a = New-Object double[] $Length
    for ($i = 0; $i -lt $Length; $i++) { $a[$i] = [double]::NaN }
    return , $a
}

function Set-WorkerPerfUniqueLabels($Items) {
    # Labels must be unique per signal: a repeated label gets " [2]", " [3]", ...
    $seen = @{}
    foreach ($it in $Items) {
        $base = [string]$it['Label']
        if (-not $seen.ContainsKey($base)) { $seen[$base] = 1; continue }
        $n = [int]$seen[$base] + 1
        while ($seen.ContainsKey("$base [$n]")) { $n++ }
        $seen[$base] = $n
        $it['Label'] = "$base [$n]"
        $seen[$it['Label']] = 1
    }
}

function ConvertTo-WorkerPerfReadCounts($Value) {
    # EventReadCounts of meta.json (log id -> SkippedRecords, UnformattedMessages, DroppedEvents) as ordered log id ->
    # @{ Dropped; Skipped; Unformatted } ([long], 0 when missing or no number); anything else gives an empty map.
    $out = [ordered]@{}
    if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) { return $out }
    foreach ($p in $Value.PSObject.Properties) {
        if ($null -eq $p.Value -or $p.Value -is [string] -or $p.Value -is [ValueType]) { continue }
        $c = @{}
        foreach ($pair in @(@('Dropped', 'DroppedEvents'), @('Skipped', 'SkippedRecords'), @('Unformatted', 'UnformattedMessages'))) {
            $n = [long]0
            if (-not [long]::TryParse([string](Get-WorkerPerfField $p.Value $pair[1]), [ref]$n) -or $n -lt 0) { $n = 0 }
            $c[$pair[0]] = $n
        }
        $out[[string]$p.Name] = $c
    }
    return $out
}

function Get-WorkerPerfJsonTimeText([string]$JsonText, [string]$Name) {
    # The time of a top-level field ("<Name>": "...") read from the text of a JSON file, as DateTimeOffset with the
    # offset the text names; $null when the field is missing or no time. Read from the text because PowerShell 7 turns
    # such a text into a DateTime in the offset of the reading machine, Windows PowerShell 5.1 does not.
    if ([string]::IsNullOrEmpty($JsonText)) { return $null }
    $found = [regex]::Matches($JsonText, '"' + [regex]::Escape($Name) + '"\s*:\s*"([^"\\]*)"')
    if ($found.Count -eq 0) { return $null }
    # depth of each match: count the braces and brackets outside strings up to its position (1 = top level)
    $depth = 0; $inString = $false; $pos = 0
    foreach ($m in $found) {
        for (; $pos -lt $m.Index; $pos++) {
            $c = $JsonText[$pos]
            if ($inString) {
                if ($c -eq '\') { $pos++ } elseif ($c -eq '"') { $inString = $false }
            }
            elseif ($c -eq '"') { $inString = $true }
            elseif ($c -eq '{' -or $c -eq '[') { $depth++ }
            elseif ($c -eq '}' -or $c -eq ']') { $depth-- }
        }
        if ($inString -or $depth -ne 1) { continue }
        return (ConvertTo-WorkerPerfTimestamp $m.Groups[1].Value)
    }
    return $null
}

function ConvertFrom-WorkerPerfHealthJsonText([string]$Text) {
    # The parsed JSON text with every object as an ordered table and every array as [object[]], at any depth; throws on
    # invalid JSON. Every string of the text gets a leading U+0001 before parsing, which is removed again afterwards: so
    # neither PowerShell 7 (ISO times) nor Windows PowerShell 5.1 ("\/Date(...)\/") turns a text into a DateTime, and a
    # text arrives as the same text on both shells.
    $marked = [regex]::Replace($Text, '"((?:[^"\\]|\\.)*)"', '"\u0001${1}"')
    $parsed = $marked | ConvertFrom-Json
    return , (ConvertTo-WorkerPerfHealthJsonValue $parsed)
}

function ConvertTo-WorkerPerfHealthJsonValue($Value) {
    # See ConvertFrom-WorkerPerfHealthJsonText: removes the marks and replaces pscustomobjects by ordered tables.
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) {
        if ($Value.Length -gt 0 -and $Value[0] -eq [char]1) { return $Value.Substring(1) }
        return $Value
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $out = [ordered]@{}
        foreach ($p in $Value.PSObject.Properties) { $out[(ConvertTo-WorkerPerfHealthJsonValue $p.Name)] = ConvertTo-WorkerPerfHealthJsonValue $p.Value }
        return $out
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $out = [ordered]@{}
        foreach ($k in @($Value.Keys)) { $out[(ConvertTo-WorkerPerfHealthJsonValue ([string]$k))] = ConvertTo-WorkerPerfHealthJsonValue $Value[$k] }
        return $out
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $items = @(foreach ($item in $Value) { , (ConvertTo-WorkerPerfHealthJsonValue $item) })
        return , ([object[]]$items)
    }
    return (ConvertTo-WorkerPerfHealthJsonNumber $Value)
}

function ConvertTo-WorkerPerfHealthJsonNumber($Value) {
    # A number of health.json the same on both shells (Windows PowerShell 5.1 parses Int32 and Decimal where PowerShell 7
    # parses Int64, Double and BigInteger): an integral number as [long], every other number as [double]; an integral
    # number outside the range of [long] or a number that is not finite becomes NaN (its value is then unreadable, a
    # field of a list entry $null). Anything that is no number is returned as it is. Never throws.
    $typeName = $Value.GetType().FullName
    $integral = @('System.Byte', 'System.SByte', 'System.Int16', 'System.UInt16', 'System.Int32', 'System.UInt32', 'System.Int64', 'System.UInt64', 'System.Numerics.BigInteger')
    $floating = @('System.Single', 'System.Double', 'System.Decimal')
    try {
        if ($integral -contains $typeName) { return [long]$Value }
        if ($floating -notcontains $typeName) { return $Value }
        if ($typeName -eq 'System.Decimal') {
            if ([Math]::Floor([decimal]$Value) -ne [decimal]$Value) { return [double]$Value }
            return [long]$Value
        }
        $number = [double]$Value
        if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) { return [double]::NaN }
        if ([Math]::Floor($number) -ne $number) { return $number }
        # 2^63 is the smallest double above the range of [long]
        if ($number -ge 9223372036854775808.0 -or $number -lt -9223372036854775808.0) { return [double]::NaN }
        return [long]$number
    }
    catch [System.Management.Automation.PipelineStoppedException] { throw }
    catch { return [double]::NaN }
}

function Test-WorkerPerfHealthContent([string]$Type, $Value) {
    # $true when the content of a value of health.json, as ConvertFrom-WorkerPerfHealthJsonText returns it (numbers as
    # [long] or [double]), fits the type of the value list (ZB-R27): number, bool, time (a [long]: a finite number without
    # fraction within the range of [long]), text*, list (an array of records, or one record). $null fits every type here
    # (a read list without content is caught by Complete-WorkerPerfHealthArea). Never throws.
    if ($null -eq $Value) { return $true }
    $isNumber = ($Value -is [long] -or $Value -is [double])
    if ($Type -eq 'number') { return $isNumber }
    if ($Type -eq 'bool') { return ($Value -is [bool]) }
    if ($Type -eq 'time') { return ($Value -is [long]) }
    if ($Type -eq 'list') {
        if ($Value -is [System.Collections.IDictionary]) { return $true }
        if ($Value -isnot [object[]]) { return $false }
        foreach ($item in $Value) { if ($item -isnot [System.Collections.IDictionary]) { return $false } }
        return $true
    }
    if ($Type.StartsWith('text')) { return ($Value -is [string]) }
    return $false
}

function Read-WorkerPerfHealthFile([string]$File) {
    # health.json as @{ State = 'read'; Health = @{ FormatVersion; ReadAtMs; OffsetMinutes; DurationMs; Areas }; Message = '' }
    # or @{ State = 'unreadable'; Health = $null; Message }. Areas in the order of WorkerPerfHealthAreas, each built by
    # Complete-WorkerPerfHealthArea from the values of the file (Status anew, DurationMs and Error from the file); an
    # area the file does not name (or that is no object) is failed with 'notInFile'. A value under an id the value list
    # does not know or that belongs to another area, with an unknown State or Reason, or whose content does not fit its
    # type is passed over (it is then unreadable with error); the file stays readable.
    $unreadable = { param([string]$Message) @{ State = 'unreadable'; Health = $null; Message = $Message } }
    try { $text = [IO.File]::ReadAllText($File, [Text.Encoding]::UTF8) }
    catch { return (& $unreadable $_.Exception.Message) }
    # only an object is a health picture; checked on the text, because PowerShell 7 unrolls a one-element array into its
    # object and Windows PowerShell 5.1 does not
    if ($text -notmatch '^\s*\{') { return (& $unreadable 'kein gueltiges JSON') }
    try { $root = ConvertFrom-WorkerPerfHealthJsonText $text }
    catch { return (& $unreadable 'kein gueltiges JSON') }
    if ($root -isnot [System.Collections.IDictionary]) { return (& $unreadable 'kein gueltiges JSON') }
    $version = $null; if ($root.Contains('FormatVersion')) { $version = $root['FormatVersion'] }
    if ($null -eq $version -or -not (Test-WorkerPerfHealthContent 'number' $version) -or $version -ne $script:WorkerPerfHealthFormatVersion) {
        return (& $unreadable (('Format ' + [string]$version + ' unbekannt') -replace '  ', ' '))
    }
    if (-not $root.Contains('Areas') -or $root['Areas'] -isnot [System.Collections.IDictionary]) { return (& $unreadable 'Areas fehlt') }
    # without the read time the ages of the health picture cannot be formed
    $readAt = Get-WorkerPerfJsonTimeText $text 'ReadAt'
    if ($null -eq $readAt) { return (& $unreadable 'ReadAt fehlt') }
    $fileAreas = $root['Areas']
    # ids and area names compared with case, like Complete-WorkerPerfHealthArea (the tables of the parsed text are not)
    $knownIds = @($script:WorkerPerfHealthValues.Keys)
    $areas = [ordered]@{}
    foreach ($area in $script:WorkerPerfHealthAreas) {
        $given = $null
        foreach ($key in @($fileAreas.Keys)) { if ($key -ceq $area) { $given = $fileAreas[$key] } }
        if ($given -isnot [System.Collections.IDictionary]) { $areas[$area] = Complete-WorkerPerfHealthArea $area @{} 0 'notInFile'; continue }
        $duration = 0.0
        if ($given.Contains('DurationMs') -and (Test-WorkerPerfHealthContent 'number' $given['DurationMs']) -and $null -ne $given['DurationMs'] -and -not [double]::IsNaN([double]$given['DurationMs'])) { $duration = [double]$given['DurationMs'] }
        $errorText = ''; if ($given.Contains('Error') -and $given['Error'] -is [string]) { $errorText = $given['Error'] }
        $values = @{}
        if ($given.Contains('Values') -and $given['Values'] -is [System.Collections.IDictionary]) {
            $fileValues = $given['Values']
            foreach ($id in @($fileValues.Keys)) {
                # a value that cannot be taken over costs that value (it is then unreadable with error), never the file
                try {
                    if ($knownIds -cnotcontains $id -or $script:WorkerPerfHealthValues[$id].Area -cne $area) { continue }
                    $entry = $fileValues[$id]
                    if ($entry -isnot [System.Collections.IDictionary]) { continue }
                    $state = $null; if ($entry.Contains('State')) { $state = $entry['State'] }
                    $reason = ''; if ($entry.Contains('Reason')) { $reason = $entry['Reason'] }
                    if ($state -isnot [string] -or @('read', 'absent', 'unreadable') -cnotcontains $state) { continue }
                    if ($reason -isnot [string] -or @('', 'rights', 'notInstalled', 'timeout', 'error') -cnotcontains $reason) { continue }
                    $content = $null; if ($entry.Contains('Value')) { $content = $entry['Value'] }
                    $type = $script:WorkerPerfHealthValues[$id].Type
                    if (-not (Test-WorkerPerfHealthContent $type $content)) { continue }
                    # a list read as one record is a list of one
                    if ($type -eq 'list' -and $content -is [System.Collections.IDictionary]) { $content = [object[]]@(, $content) }
                    $values[$id] = [ordered]@{ State = $state; Reason = $reason; Value = $content }
                }
                catch [System.Management.Automation.PipelineStoppedException] { throw }
                catch { $values.Remove($id) }
            }
        }
        $areas[$area] = Complete-WorkerPerfHealthArea $area $values $duration $errorText
    }
    $readAtMs = $readAt.ToUnixTimeMilliseconds(); $offset = $readAt.Offset.TotalMinutes
    $duration = 0.0
    if ($root.Contains('DurationMs') -and $null -ne $root['DurationMs'] -and (Test-WorkerPerfHealthContent 'number' $root['DurationMs']) -and -not [double]::IsNaN([double]$root['DurationMs'])) { $duration = [double]$root['DurationMs'] }
    return @{ State = 'read'; Message = ''
        Health = @{ FormatVersion = $script:WorkerPerfHealthFormatVersion; ReadAtMs = $readAtMs; OffsetMinutes = $offset; DurationMs = $duration; Areas = $areas } }
}

function Import-WorkerPerfRun {
    # -From / -To: local time of the measured server (the clock time the tick timestamps carry), like every time the
    # report shows; the Kind of the values is ignored.
    param([string]$Path, [datetime]$From = [datetime]::MinValue, [datetime]$To = [datetime]::MaxValue, $Thresholds, [object[]]$Roles)
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $numStyle = [Globalization.NumberStyles]::Float
    $nan = [double]::NaN

    $metaPath = Join-Path $Path 'meta.json'
    # the collector replaces meta.json by delete and move: after a kill between the two only the complete temporary file exists
    if (-not (Test-Path -LiteralPath $metaPath) -and (Test-Path -LiteralPath ($metaPath + '.tmp'))) { $metaPath = $metaPath + '.tmp' }
    if (-not (Test-Path -LiteralPath $metaPath)) { throw "Ordner '$Path' enthaelt keine Aufzeichnung (meta.json fehlt)." }
    $metaJson = ConvertFrom-WorkerPerfJsonFile $metaPath
    $meta = @{}
    foreach ($p in $metaJson.PSObject.Properties) { $meta[$p.Name] = $p.Value }
    foreach ($k in 'SchemaVersion', 'Computer', 'OS', 'LogicalProcessors', 'PhysicalMemoryMB', 'FastIntervalSeconds', 'IntervalSeconds', 'StartTime', 'EndTime', 'EndReason', 'EndMessage', 'CollectorPid', 'Simulated', 'Endpoints', 'EventLookbackDays') {
        if (-not $meta.ContainsKey($k)) { $meta[$k] = $null }
    }
    # format 3: the logs whose lookback reached its cap (absent in format 2)
    $capped = @()
    if ($meta.ContainsKey('LookbackCapped')) { $capped = @($meta['LookbackCapped'] | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ }) }
    $meta['LookbackCapped'] = [string[]]$capped
    # format 3: the counters of the event reads per log (EventReadCounts: the whole capture; LookbackReadCounts: after the
    # lookback, newer captures only), as ordered log id -> @{ Dropped; Skipped; Unformatted } (I5); missing = none
    foreach ($k in 'EventReadCounts', 'LookbackReadCounts') { $meta[$k] = ConvertTo-WorkerPerfReadCounts (Get-WorkerPerfField $metaJson $k) }
    # the categories -Skip left out (format 3 with -Skip); a capture from before has no field: everything was measured
    $recordedSkip = [string[]]@(Get-WorkerPerfRecordedSkip (Get-WorkerPerfField $metaJson 'Skip'))
    foreach ($cat in @($script:WorkerPerfCategories.Keys)) {
        foreach ($f in @($script:WorkerPerfCategories[$cat].Files)) {
            $full = Join-Path $Path $f
            if ($recordedSkip -contains $cat) { $script:WorkerPerfLeftOutFiles[$full] = $true } else { $script:WorkerPerfLeftOutFiles.Remove($full) }
        }
    }
    # a capture in another format is not read; a missing field is tolerated (hand-written or damaged meta.json)
    if ($null -ne $meta['SchemaVersion']) {
        $ver = 0.0
        $verText = [string]$meta['SchemaVersion']
        if (-not [double]::TryParse($verText, $numStyle, $inv, [ref]$ver) -or $script:WorkerPerfReadableFormats -notcontains $ver) {
            $last = $script:WorkerPerfReadableFormats[$script:WorkerPerfReadableFormats.Count - 1]
            $others = @($script:WorkerPerfReadableFormats | Select-Object -First ($script:WorkerPerfReadableFormats.Count - 1))
            throw "Die Aufzeichnung '$Path' hat das Format $verText; diese Version von WorkerPerf liest die Formate $($others -join ', ') und $last."
        }
    }
    $cores = 0; $ramMb = 0.0; $fastSec = 2.0; $snapSec = 15.0
    if ($null -ne $meta['LogicalProcessors']) { $cores = [int]$meta['LogicalProcessors'] }
    if ($null -ne $meta['PhysicalMemoryMB']) { $ramMb = [double]$meta['PhysicalMemoryMB'] }
    if ($null -ne $meta['FastIntervalSeconds']) { $fastSec = [double]$meta['FastIntervalSeconds'] }
    if ($null -ne $meta['IntervalSeconds']) { $snapSec = [double]$meta['IntervalSeconds'] }

    $sources = @{}
    $srcObj = Get-WorkerPerfField $metaJson 'Sources'
    if ($null -ne $srcObj) {
        foreach ($p in $srcObj.PSObject.Properties) {
            $avail = Get-WorkerPerfField $p.Value 'Available'
            $detail = Get-WorkerPerfField $p.Value 'Detail'
            $d = ''
            if ($null -ne $detail) { $d = [string]$detail }
            # optional marks (newer captures): ReadFailed, a log the capture could not read at least once (M13); LookbackRead,
            # a switched-off log whose events the lookback read (M14)
            $failed = Get-WorkerPerfField $p.Value 'ReadFailed'; $lbRead = Get-WorkerPerfField $p.Value 'LookbackRead'
            $sources[$p.Name] = @{ Available = ($null -ne $avail -and [bool]$avail); Detail = $d; ReadFailed = ($true -eq $failed); LookbackRead = ($true -eq $lbRead) }
        }
    }
    # the sources of a category that Skip names, as the collector notes them (a capture whose Skip contradicts its
    # files, MK-R20; for a capture of the collector this changes nothing)
    if ($recordedSkip.Length -gt 0) {
        Set-WorkerPerfSkippedSources -Sources $sources -Skip $recordedSkip
        foreach ($id in @($sources.Keys)) { foreach ($k in 'ReadFailed', 'LookbackRead') { if (-not $sources[$id].ContainsKey($k)) { $sources[$id][$k] = $false } } }
    }

    # failed source calls of the capture (optional field SourceErrors: source -> Count, FirstTime, FirstMessage); missing = none
    $sourceErrors = New-Object System.Collections.Generic.List[object]
    $errObj = Get-WorkerPerfField $metaJson 'SourceErrors'
    if ($null -ne $errObj -and $errObj -isnot [string] -and $errObj -isnot [ValueType]) {
        foreach ($p in $errObj.PSObject.Properties) {
            $count = 0
            if (-not [int]::TryParse([string](Get-WorkerPerfField $p.Value 'Count'), [ref]$count) -or $count -lt 1) { continue }
            # PowerShell 7 hands a time in a JSON text over as DateTime, Windows PowerShell 5.1 as text
            $firstMs = $null
            $first = Get-WorkerPerfField $p.Value 'FirstTime'
            if ($first -is [datetime]) { $firstMs = (New-Object DateTimeOffset ($first)).ToUnixTimeMilliseconds() }
            else {
                $ft = ConvertTo-WorkerPerfTimestamp ([string]$first)
                if ($null -ne $ft) { $firstMs = $ft.ToUnixTimeMilliseconds() }
            }
            $sourceErrors.Add(@{ Source = [string]$p.Name; Count = $count; FirstMs = $firstMs; FirstMessage = [string](Get-WorkerPerfField $p.Value 'FirstMessage') })
        }
    }

    # the health picture: left out by Skip (the file is not read), not recorded (no health.json; a health.json.tmp is
    # never read in its place), or the result of reading the file
    $health = $null; $healthState = 'notRecorded'
    $healthFile = Join-Path $Path 'health.json'
    if ($recordedSkip -contains 'Zustand') { $healthState = 'skipped' }
    elseif (Test-WorkerPerfRunFile $healthFile) {
        $read = Read-WorkerPerfHealthFile $healthFile
        $healthState = $read.State; $health = $read.Health
        if ($read.State -eq 'unreadable') { Write-Warning ('health.json ist nicht lesbar ({0}); der Bericht zeigt kein Zustandsbild.' -f $read.Message) }
    }
    # whether the lookback and the driver list are in the capture (and not left out by Skip)
    $recorded = @{ EventsBefore = (Test-WorkerPerfRunFile (Join-Path $Path 'events_before.csv')); PrintDrivers = (Test-WorkerPerfRunFile (Join-Path $Path 'printdrivers.csv')) }
    # a quick run only when the field is the boolean true (a text such as "false" or a number is not)
    $healthOnly = Get-WorkerPerfField $metaJson 'HealthOnly'
    $meta['HealthOnly'] = ($healthOnly -is [bool] -and $healthOnly)

    # time range: clock time of the measured server. A tick is in the range when its own clock time (timestamp with
    # its own offset) is; the limits as epoch milliseconds for the other files follow from the ticks in the range.
    $hasFrom = ($From -gt [datetime]::MinValue); $hasTo = ($To -lt [datetime]::MaxValue)
    if ($meta['HealthOnly']) {
        # A quick run holds only the health picture, the lookback and the driver list: a model with the keys of a
        # measurement, its series and lists empty.
        if ($hasFrom -or $hasTo) { throw 'Die Aufzeichnung ist ein Schnelllauf ohne Messung; -From und -To gelten nicht.' }
        $start = Get-WorkerPerfJsonTimeText ([IO.File]::ReadAllText($metaPath, [Text.Encoding]::UTF8)) 'StartTime'
        $startMs = $null; $offsetMinutes = 0.0
        if ($null -ne $start) { $startMs = $start.ToUnixTimeMilliseconds(); $offsetMinutes = $start.Offset.TotalMinutes }
        $skipBefore = 0; $skipDrivers = 0
        $eventsBefore = @(Read-WorkerPerfEventCsv $Path 'events_before.csv' ([ref]$skipBefore))
        $printDrivers = @(Read-WorkerPerfPrintDrivers $Path ([ref]$skipDrivers))
        $raw = @{}
        foreach ($name in $script:WorkerPerfHeaders['ticks.csv'].Split(',')) { if ($name -ne 'T' -and $name -ne 'Timestamp') { $raw[$name] = [double[]]@() } }
        $signal = @{}
        foreach ($id in 'cpu.host', 'cpu.queue', 'cpu.steal', 'mem.used', 'mem.commit', 'mem.pagesin') { $signal[$id] = [double[]]@() }
        $meta['Cores'] = $cores; $meta['RamMB'] = $ramMb; $meta['OffsetMinutes'] = $offsetMinutes
        $meta['FastSec'] = $fastSec; $meta['SnapSec'] = $snapSec
        return @{
            Meta = $meta
            Skip = $recordedSkip
            Sources = $sources
            Tick = @{ N = 0; TimeMs = [long[]]@(); ElapsedSec = [double[]]@(); Burst = [bool[]]@(); CollectMs = [double[]]@(); Raw = $raw; Signal = $signal }
            Snap = @{
                N = 0; TimeMs = [long[]]@(); ElapsedSec = [double[]]@(); Kind = [string[]]@(); TickPos = [int[]]@()
                Sessions = [double[]]@(); ActiveSessions = [double[]]@(); Processes = [double[]]@(); RowsWritten = [double[]]@(); CollectMs = [double[]]@()
            }
            Sessions = [object[]]@()
            Volumes = [object[]]@()
            Shares = [object[]]@()
            Probes = [object[]]@()
            Events = [object[]]@()
            EventsAll = [object[]]@()
            EventsOutsideCut = 0
            CaptureStartMs = $startMs
            CaptureEndMs = $startMs
            EventsBefore = $eventsBefore
            PrintDrivers = $printDrivers
            PrintQueues = [object[]]@()
            Scans = [object[]]@()
            InputProc = @{ TickPos = [int[]]@(); SessionIndex = [int[]]@(); Pid = [int[]]@(); Name = [string[]]@(); DelayMs = [double[]]@(); K = [int[]]@() }
            Apps = [object[]]@()
            Proc = [object[]]@()
            Pairs = @{}
            Rows = @{ Start = [int[]]@(0); K = [int[]]@(); CpuMs = [double[]]@(); Io = [double[]]@(); WsKB = [double[]]@() }
            Carried = @{ K = [int[]]@(); WsKB = [double[]]@() }
            Unreadable = @{ Ticks = 0; Snapshots = 0; Events = 0; EventsBefore = $skipBefore; PrintDrivers = $skipDrivers; PrintQueues = 0 }
            SourceErrors = $sourceErrors.ToArray()
            TotalCpuMs = 0.0
            MainApp = $null
            Citrix = [object[]]@()
            Health = $health
            HealthState = $healthState
            Recorded = $recorded
        }
    }
    $fromTicks = [long]::MinValue; $toTicks = [long]::MaxValue
    if ($hasFrom) { $fromTicks = $From.Ticks }
    if ($hasTo) { $toTicks = $To.Ticks }
    if ($fromTicks -gt $toTicks) { throw '-From liegt nach -To.' }

    #region ticks
    $csv = Read-WorkerPerfCsvFile $Path 'ticks.csv'
    $col = $csv.Col
    $numNames = New-Object System.Collections.Generic.List[string]
    foreach ($name in $script:WorkerPerfHeaders['ticks.csv'].Split(',')) { if ($name -ne 'T' -and $name -ne 'Timestamp') { $numNames.Add($name) } }
    $numIdx = New-Object int[] $numNames.Count
    $numLists = New-Object object[] $numNames.Count
    for ($i = 0; $i -lt $numNames.Count; $i++) { $numIdx[$i] = [int]$col[$numNames[$i]]; $numLists[$i] = New-Object System.Collections.Generic.List[double] }
    $tickT = New-Object System.Collections.Generic.List[int]
    $tickMs = New-Object System.Collections.Generic.List[long]
    $cT = [int]$col['T']; $cTs = [int]$col['Timestamp']; $cEl = [int]$col['ElapsedSec']
    $offsetMinutes = 0.0; $haveOffset = $false; $lastOffsetMinutes = 0.0
    $badTicks = [int]$csv.Skipped                 # unreadable rows of ticks.csv: too few fields, or no readable number, time or duration
    $firstWall = [long]::MinValue; $lastWall = [long]::MinValue      # clock time of the first and last readable tick of the file
    $captureStartMs = $null                                          # the first readable tick of the file, whatever -From says
    $lastDto = $null                                                 # the last readable tick of the file, whatever -To says
    $numRef = [ref]0.0
    foreach ($f in $csv.Rows) {
        $t = 0
        if (-not [int]::TryParse($f[$cT], [ref]$t)) { $badTicks++; continue }
        $dto = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse($f[$cTs], $inv, [Globalization.DateTimeStyles]::None, [ref]$dto)) { $badTicks++; continue }
        # a tick without a readable, finite duration does not exist for the model (like a row with too few fields)
        if (-not [double]::TryParse($f[$cEl], $numStyle, $inv, $numRef) -or [double]::IsNaN($numRef.Value) -or [double]::IsInfinity($numRef.Value)) { $badTicks++; continue }
        $wall = $dto.Ticks
        if ($firstWall -eq [long]::MinValue) { $firstWall = $wall; $captureStartMs = $dto.ToUnixTimeMilliseconds() }
        $lastWall = $wall; $lastDto = $dto
        if ($wall -lt $fromTicks -or $wall -gt $toTicks) { continue }
        $ms = $dto.ToUnixTimeMilliseconds()
        $lastOffsetMinutes = $dto.Offset.TotalMinutes
        if (-not $haveOffset) { $offsetMinutes = $lastOffsetMinutes; $haveOffset = $true }
        $tickT.Add($t); $tickMs.Add($ms)
        for ($i = 0; $i -lt $numIdx.Length; $i++) {
            # NaN when empty or unreadable; one reused reference costs less than [ref]$v per value
            $v = $nan
            $txt = $f[$numIdx[$i]]
            if ($txt.Length -gt 0 -and [double]::TryParse($txt, $numStyle, $inv, $numRef)) { $v = $numRef.Value }
            $numLists[$i].Add($v)
        }
    }
    $nT = $tickT.Count
    if ($nT -eq 0) {
        if ($firstWall -eq [long]::MinValue) { throw "Die Aufzeichnung enthaelt keine Messung (ticks.csv ohne lesbare Takte)." }
        $range = ''
        if ($hasFrom -and $hasTo) { $range = (Format-WorkerPerfWallClock $fromTicks) + ' bis ' + (Format-WorkerPerfWallClock $toTicks) }
        elseif ($hasFrom) { $range = 'ab ' + (Format-WorkerPerfWallClock $fromTicks) }
        else { $range = 'bis ' + (Format-WorkerPerfWallClock $toTicks) }
        $own = (Format-WorkerPerfWallClock $firstWall) + ' bis ' + (Format-WorkerPerfWallClock $lastWall) + ', Ortszeit des Servers'
        if ($fromTicks -gt $lastWall -or $toTicks -lt $firstWall) { throw "Der Zeitraum $range liegt ausserhalb der Aufzeichnung ($own)." }
        throw "Im Zeitraum $range liegt kein Takt der Aufzeichnung ($own)."
    }
    # the limits as epoch milliseconds (snapshots, events, scans): clock time minus the offset of the first / last tick in the range
    $fromMs = [long]::MinValue; $toMs = [long]::MaxValue
    if ($hasFrom) { $fromMs = (New-Object DateTimeOffset ([DateTime]::SpecifyKind($From, [DateTimeKind]::Utc))).ToUnixTimeMilliseconds() - [long][Math]::Round($offsetMinutes * 60000.0) }
    if ($hasTo) { $toMs = (New-Object DateTimeOffset ([DateTime]::SpecifyKind($To, [DateTimeKind]::Utc))).ToUnixTimeMilliseconds() - [long][Math]::Round($lastOffsetMinutes * 60000.0) }
    $raw = @{}
    for ($i = 0; $i -lt $numNames.Count; $i++) { $raw[$numNames[$i]] = $numLists[$i].ToArray() }
    $tickTArr = $tickT.ToArray()
    $tickMsArr = $tickMs.ToArray()
    $burst = New-Object bool[] $nT
    for ($i = 0; $i -lt $nT; $i++) { $burst[$i] = ($raw['Burst'][$i] -gt 0) }
    $tickPosByT = @{}
    for ($i = 0; $i -lt $nT; $i++) { $tickPosByT[$tickTArr[$i]] = $i }

    $signalIds = 'cpu.host', 'cpu.queue', 'cpu.steal', 'mem.used', 'mem.commit', 'mem.pagesin'
    $signal = @{}
    foreach ($id in $signalIds) { $signal[$id] = New-Object double[] $nT }
    # host signals per tick, computed as in Get-WorkerPerfHostSignals
    $rCpu = $raw['CpuPct']; $rQueue = $raw['ProcQueue']; $rSteal = $raw['StealPct']; $rAvail = $raw['MemAvailMB']
    $rCommitted = $raw['MemCommittedMB']; $rLimit = $raw['MemCommitLimitMB']; $rPagesIn = $raw['PagesInPerSec']
    $sCpu = $signal['cpu.host']; $sQueue = $signal['cpu.queue']; $sSteal = $signal['cpu.steal']
    $sUsed = $signal['mem.used']; $sCommit = $signal['mem.commit']; $sPagesIn = $signal['mem.pagesin']
    for ($i = 0; $i -lt $nT; $i++) {
        $queuePerCpu = $nan
        if ($cores -gt 0) { $queuePerCpu = $rQueue[$i] / $cores }
        $used = $nan
        if ($ramMb -gt 0) { $used = 100 * (1 - $rAvail[$i] / $ramMb) }
        $commit = $nan
        $limit = $rLimit[$i]
        if ($limit -gt 0) { $commit = 100 * $rCommitted[$i] / $limit }
        $sCpu[$i] = $rCpu[$i]; $sQueue[$i] = $queuePerCpu; $sSteal[$i] = $rSteal[$i]
        $sUsed[$i] = $used; $sCommit[$i] = $commit; $sPagesIn[$i] = $rPagesIn[$i]
    }
    #endregion

    #region snapshots
    $csv = Read-WorkerPerfCsvFile $Path 'snapshots.csv'
    $col = $csv.Col
    $snapPos = @{}                     # P -> snapshot position
    $snapP = New-Object System.Collections.Generic.List[int]
    $snapTL = New-Object System.Collections.Generic.List[int]
    $snapMsL = New-Object System.Collections.Generic.List[long]
    $snapKind = New-Object System.Collections.Generic.List[string]
    $snapNum = @{}
    $preP = New-Object System.Collections.Generic.List[int]          # snapshots before -From: they only build process state
    $preKind = New-Object System.Collections.Generic.List[string]
    foreach ($name in 'ElapsedSec', 'Sessions', 'ActiveSessions', 'Processes', 'RowsWritten', 'CollectMs') { $snapNum[$name] = New-Object System.Collections.Generic.List[double] }
    $badSnaps = [int]$csv.Skipped                 # unreadable rows of snapshots.csv, counted like the ticks
    # the process counts of a snapshot belong to Prozesse: without it they are empty (also where Skip contradicts the file)
    $blankSnap = @(); if ($recordedSkip -contains 'Prozesse') { $blankSnap = @('Processes', 'RowsWritten') }
    foreach ($f in $csv.Rows) {
        $p = 0; $t = 0
        if (-not [int]::TryParse($f[[int]$col['P']], [ref]$p)) { $badSnaps++; continue }
        if (-not [int]::TryParse($f[[int]$col['T']], [ref]$t)) { $badSnaps++; continue }
        $dto = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse($f[[int]$col['Timestamp']], $inv, [Globalization.DateTimeStyles]::None, [ref]$dto)) { $badSnaps++; continue }
        # a snapshot without a readable, finite duration is skipped like one with an unreadable time; its process rows
        # are then dropped as rows of a P without snapshot line
        if (-not [double]::TryParse($f[[int]$col['ElapsedSec']], $numStyle, $inv, $numRef) -or [double]::IsNaN($numRef.Value) -or [double]::IsInfinity($numRef.Value)) { $badSnaps++; continue }
        $ms = $dto.ToUnixTimeMilliseconds()
        if ($ms -lt $fromMs) { $preP.Add($p); $preKind.Add($f[[int]$col['Kind']]); continue }
        if ($ms -gt $toMs) { continue }
        $snapPos[$p] = $snapP.Count
        $snapP.Add($p); $snapTL.Add($t); $snapMsL.Add($ms); $snapKind.Add($f[[int]$col['Kind']])
        foreach ($name in $snapNum.Keys) {
            $v = $nan
            $txt = $f[[int]$col[$name]]
            if ($txt.Length -gt 0 -and $blankSnap -notcontains $name -and [double]::TryParse($txt, $numStyle, $inv, $numRef)) { $v = $numRef.Value }
            $snapNum[$name].Add($v)
        }
    }
    $nP = $snapP.Count
    if ($nP -eq 0) { throw "Die Aufzeichnung enthaelt im gewaehlten Zeitraum keinen Schnappschuss (snapshots.csv ohne lesbare Zeilen)." }
    $snapT = $snapTL.ToArray()
    $snapMs = $snapMsL.ToArray()
    $snapTickPos = New-Object int[] $nP
    for ($i = 0; $i -lt $nP; $i++) {
        $pos = -1
        if ($tickPosByT.ContainsKey($snapT[$i])) { $pos = [int]$tickPosByT[$snapT[$i]] }
        else {
            $ix = [Array]::BinarySearch($tickTArr, [int]$snapT[$i])
            if ($ix -lt 0) { $ix = -bnot $ix }
            if ($ix -ge $nT) { $ix = $nT - 1 }
            $pos = $ix
        }
        $snapTickPos[$i] = $pos
    }
    # first snapshot at or after each tick
    $firstSnapAt = New-Object int[] $nT
    $j = 0
    for ($tp = 0; $tp -lt $nT; $tp++) {
        while ($j -lt $nP -and $snapTickPos[$j] -lt $tp) { $j++ }
        $firstSnapAt[$tp] = $j
    }
    #endregion

    #region sessions
    $sessions = New-Object System.Collections.Generic.List[object]
    $sessBySnap = New-Object object[] $nP        # snapshot position -> (session id -> session)
    $curBySid = @{}
    $orphans = @{}
    $newSession = {
        param([int]$Sid)
        $e = @{
            Index = $sessions.Count; Sid = $Sid; User = ''; Domain = ''; Client = ''; Logon = $null; Label = ''
            FirstP = -1; LastP = -1; SeenN = 0; ActiveN = 0; IdleMaxSec = [double]::NaN
            Input = (New-Object double[] $nT); Rtt = (New-WorkerPerfNanArray $nP); Latency = (New-WorkerPerfNanArray $nP)
            ProfileVolume = -1
            CpuMs = (New-Object double[] $nP); Ws = (New-Object double[] $nP); Priv = (New-Object double[] $nP); Io = (New-Object double[] $nP)
            N = (New-Object int[] $nP)
        }
        $sessions.Add($e)
        return $e
    }
    $reader = $null      # opened first thing inside try, so that finally always closes it
    try {
        $csv = Open-WorkerPerfCsvReader $Path 'sessions.csv'
        $reader = $csv.Reader; $need = $csv.Need
        $col = $csv.Col
        $cP = [int]$col['P']; $cSid = [int]$col['SessionId']; $cUser = [int]$col['User']; $cDom = [int]$col['Domain']
        $cState = [int]$col['State']; $cClient = [int]$col['ClientName']; $cLogon = [int]$col['LogonTime']; $cIdle = [int]$col['IdleSec']
        while ($null -ne $reader) {
            $line = $reader.ReadLine()
            if ($null -eq $line) { break }
            if ($line.Length -eq 0) { continue }
            if ($line.IndexOf('"') -lt 0) { $f = $line.Split(',') } else { $f = [string[]]@(Split-WorkerPerfCsvLine $line) }
            if ($f.Length -lt $need) { continue }
            $p = 0; $sid = 0
            if (-not [int]::TryParse($f[$cP], [ref]$p) -or -not [int]::TryParse($f[$cSid], [ref]$sid)) { continue }
            if (-not $snapPos.ContainsKey($p)) { continue }
            $pos = [int]$snapPos[$p]
            $user = $f[$cUser]
            $e = $null
            if ($curBySid.ContainsKey($sid)) { $e = $curBySid[$sid] }
            # A session id is reused after logoff: a new session starts when the id was missing for a snapshot
            # or when a different user owns it now. Session 0 (services) is always one session.
            if ($null -ne $e -and $sid -ne 0) {
                if ($e.LastP -lt $pos - 1) { $e = $null }
                elseif ($user.Length -gt 0 -and $e.User.Length -gt 0 -and ($user -ne $e.User -or $f[$cDom] -ne $e.Domain)) { $e = $null }
            }
            if ($null -eq $e) { $e = & $newSession $sid; $curBySid[$sid] = $e }
            if ($user.Length -gt 0) { $e.User = $user; $e.Domain = $f[$cDom] }
            if ($f[$cClient].Length -gt 0) { $e.Client = $f[$cClient] }
            if ($f[$cLogon].Length -gt 0 -and $null -eq $e.Logon) {
                $ld = ConvertTo-WorkerPerfTimestamp $f[$cLogon]
                if ($null -ne $ld) { $e.Logon = $ld.ToUnixTimeMilliseconds() }
            }
            if ($e.FirstP -lt 0) { $e.FirstP = $pos }
            $e.LastP = $pos; $e.SeenN++
            if ($f[$cState] -eq 'Active') { $e.ActiveN++ }
            $idle = $nan
            $txt = $f[$cIdle]; if ($txt.Length -gt 0 -and [double]::TryParse($txt, $numStyle, $inv, $numRef)) { $idle = $numRef.Value }
            if (-not [double]::IsNaN($idle) -and $idle -ge 0 -and -not ($e.IdleMaxSec -ge $idle)) { $e.IdleMaxSec = $idle }
            if ($null -eq $sessBySnap[$pos]) { $sessBySnap[$pos] = @{} }
            $sessBySnap[$pos][$sid] = $e
        }
    }
    finally { if ($null -ne $reader) { $reader.Dispose() } }
    # Session of a row stamped with tick position $tp: first snapshot at or after the tick, else the one before,
    # else a stand-in session for the id.
    $resolveSession = {
        param([int]$TickPos, [int]$Sid)
        $s = $firstSnapAt[$TickPos]
        if ($s -lt $nP) {
            $h = $sessBySnap[$s]
            if ($null -ne $h -and $h.ContainsKey($Sid)) { return $h[$Sid] }
        }
        if ($s - 1 -ge 0) {
            $h = $sessBySnap[$s - 1]
            if ($null -ne $h -and $h.ContainsKey($Sid)) { return $h[$Sid] }
        }
        if (-not $orphans.ContainsKey($Sid)) { $orphans[$Sid] = & $newSession $Sid }
        return $orphans[$Sid]
    }
    # The answer depends only on the snapshot position $firstSnapAt[$TickPos] and the id, and stays the same once given
    # (an orphan is created on the first call). Rows look it up here: snapshot position -> (session id text -> session).
    $sessionAt = New-Object object[] ($nP + 1)
    # Parsed numbers by text (invariant culture; NaN for an empty or unreadable text): the capture repeats few
    # distinct texts, and a lookup costs far less than [double]::TryParse in PowerShell.
    $numByText = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
    #endregion

    #region input delay
    $reader = $null      # opened first thing inside try, so that finally always closes it
    try {
        $csv = Open-WorkerPerfCsvReader $Path 'inputdelay.csv'
        $reader = $csv.Reader; $need = $csv.Need
        $col = $csv.Col
        $cT = [int]$col['T']; $cSid = [int]$col['SessionId']; $cDelay = [int]$col['DelayMs']
        $lastT = $null; $tp = -1; $bySid = $null
        while ($null -ne $reader) {
            $line = $reader.ReadLine()
            if ($null -eq $line) { break }
            if ($line.Length -eq 0) { continue }
            if ($line.IndexOf('"') -lt 0) { $f = $line.Split(',') } else { $f = [string[]]@(Split-WorkerPerfCsvLine $line) }
            if ($f.Length -lt $need) { continue }
            # T is parsed again only when its text changes (-1: unreadable or out of range); rows grouped by T make this
            # cache hit, rows in any order give the same result
            $tText = $f[$cT]
            if (-not [string]::Equals($tText, $lastT)) {
                $lastT = $tText; $tp = -1; $t = 0
                if ([int]::TryParse($tText, [ref]$t) -and $tickPosByT.ContainsKey($t)) {
                    $tp = [int]$tickPosByT[$t]
                    $bySid = $sessionAt[$firstSnapAt[$tp]]
                    if ($null -eq $bySid) { $bySid = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal); $sessionAt[$firstSnapAt[$tp]] = $bySid }
                }
            }
            if ($tp -lt 0) { continue }
            $txt = $f[$cDelay]
            $d = $numByText[$txt]
            if ($null -eq $d) { $d = ConvertTo-WorkerPerfCachedDouble $numByText $txt }
            if ([double]::IsNaN($d)) { continue }
            $sidText = $f[$cSid]
            $e = $bySid[$sidText]
            if ($null -eq $e) {
                $sid = 0
                if (-not [int]::TryParse($sidText, [ref]$sid)) { continue }
                $e = & $resolveSession $tp $sid; $bySid[$sidText] = $e
            }
            $input_ = $e.Input
            if ($d -gt $input_[$tp]) { $input_[$tp] = $d }
        }
    }
    finally { if ($null -ne $reader) { $reader.Dispose() } }

    $mainPatterns = New-Object System.Collections.Generic.List[string]
    $mainLabels = New-Object System.Collections.Generic.List[string]
    foreach ($r in @($Roles)) {
        if ($null -eq $r -or [string](Get-WorkerPerfField $r 'role') -ne 'Hauptanwendung') { continue }
        $pats = @(Get-WorkerPerfField $r 'processes' | Where-Object { $null -ne $_ -and [string]$_ -ne '' })
        if ($pats.Count -eq 0) { continue }
        foreach ($pt in $pats) { $mainPatterns.Add([string]$pt) }
        $mainLabels.Add([string](Get-WorkerPerfField $r 'label'))
    }
    $mainApp = $null
    $mainDelay = $null
    if ($mainPatterns.Count -gt 0) { $mainDelay = New-Object double[] $nT }
    $mainByName = @{}

    $reader = $null      # opened first thing inside try, so that finally always closes it
    try {
        $csv = Open-WorkerPerfCsvReader $Path 'inputdelay_proc.csv'
        $reader = $csv.Reader; $need = $csv.Need
        $col = $csv.Col
        $cT = [int]$col['T']; $cSid = [int]$col['SessionId']; $cPid = [int]$col['Pid']; $cName = [int]$col['Name']; $cDelay = [int]$col['DelayMs']
        $ipTick = New-Object System.Collections.Generic.List[int]
        $ipSess = New-Object System.Collections.Generic.List[int]
        $ipPid = New-Object System.Collections.Generic.List[int]
        $ipName = New-Object System.Collections.Generic.List[string]
        $ipDelay = New-Object System.Collections.Generic.List[double]
        $lastT = $null; $tp = -1; $bySid = $null
        while ($null -ne $reader) {
            $line = $reader.ReadLine()
            if ($null -eq $line) { break }
            if ($line.Length -eq 0) { continue }
            if ($line.IndexOf('"') -lt 0) { $f = $line.Split(',') } else { $f = [string[]]@(Split-WorkerPerfCsvLine $line) }
            if ($f.Length -lt $need) { continue }
            $tText = $f[$cT]
            if (-not [string]::Equals($tText, $lastT)) {
                $lastT = $tText; $tp = -1; $t = 0
                if ([int]::TryParse($tText, [ref]$t) -and $tickPosByT.ContainsKey($t)) {
                    $tp = [int]$tickPosByT[$t]
                    $bySid = $sessionAt[$firstSnapAt[$tp]]
                    if ($null -eq $bySid) { $bySid = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal); $sessionAt[$firstSnapAt[$tp]] = $bySid }
                }
            }
            if ($tp -lt 0) { continue }
            $txt = $f[$cDelay]
            $d = $numByText[$txt]
            if ($null -eq $d) { $d = ConvertTo-WorkerPerfCachedDouble $numByText $txt }
            if ([double]::IsNaN($d)) { continue }
            $sidText = $f[$cSid]
            $e = $bySid[$sidText]
            if ($null -eq $e) {
                $sid = 0
                if (-not [int]::TryParse($sidText, [ref]$sid)) { continue }
                $e = & $resolveSession $tp $sid; $bySid[$sidText] = $e
            }
            $procId = 0
            if (-not [int]::TryParse($f[$cPid], [ref]$procId)) { $procId = -1 }
            $name = $f[$cName]
            $ipTick.Add($tp); $ipSess.Add([int]$e.Index); $ipPid.Add($procId); $ipName.Add($name); $ipDelay.Add($d)
            if ($null -ne $mainDelay) {
                if (-not $mainByName.ContainsKey($name)) {
                    $hit = $false
                    foreach ($pt in $mainPatterns) { if ($name -like $pt) { $hit = $true; break } }
                    $mainByName[$name] = $hit
                }
                if ($mainByName[$name] -and $d -gt $mainDelay[$tp]) { $mainDelay[$tp] = $d }
            }
        }
    }
    finally { if ($null -ne $reader) { $reader.Dispose() } }
    if ($null -ne $mainDelay) { $mainApp = @{ Label = ($mainLabels.ToArray() -join ' / '); Delay = $mainDelay } }
    #endregion

    #region volumes and shares
    $volumes = New-Object System.Collections.Generic.List[object]
    $volByKey = @{}
    $volAt = New-Object object[] ($nP + 1)      # snapshot position -> (volume|kind|session id text -> volume)
    $lastT = $null; $tp = -1; $bySid = $null; $volAtSnap = $null
    $reader = $null      # opened first thing inside try, so that finally always closes it
    try {
        $csv = Open-WorkerPerfCsvReader $Path 'volumes.csv'
        $reader = $csv.Reader; $need = $csv.Need
        $col = $csv.Col
        $cT = [int]$col['T']; $cVol = [int]$col['Volume']; $cKind = [int]$col['Kind']; $cSid = [int]$col['SessionId']; $cBack = [int]$col['Backing']
        $cRl = [int]$col['ReadLatMs']; $cWl = [int]$col['WriteLatMs']; $cRo = [int]$col['ReadOps']; $cWo = [int]$col['WriteOps']
        while ($null -ne $reader) {
            $line = $reader.ReadLine()
            if ($null -eq $line) { break }
            if ($line.Length -eq 0) { continue }
            if ($line.IndexOf('"') -lt 0) { $f = $line.Split(',') } else { $f = [string[]]@(Split-WorkerPerfCsvLine $line) }
            if ($f.Length -lt $need) { continue }
            $tText = $f[$cT]
            if (-not [string]::Equals($tText, $lastT)) {
                $lastT = $tText; $tp = -1; $t = 0
                if ([int]::TryParse($tText, [ref]$t) -and $tickPosByT.ContainsKey($t)) {
                    $tp = [int]$tickPosByT[$t]
                    $snapOfTick = $firstSnapAt[$tp]
                    $bySid = $sessionAt[$snapOfTick]
                    if ($null -eq $bySid) { $bySid = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal); $sessionAt[$snapOfTick] = $bySid }
                    $volAtSnap = $volAt[$snapOfTick]
                    if ($null -eq $volAtSnap) { $volAtSnap = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal); $volAt[$snapOfTick] = $volAtSnap }
                }
            }
            if ($tp -lt 0) { continue }
            # the volume of a row: one lookup per snapshot position, volume, kind and session id text
            $atKey = [string]::Concat($f[$cVol], '|', $f[$cKind], '|', $f[$cSid])
            $v = $volAtSnap[$atKey]
            if ($null -eq $v) {
                $sessIdx = -1
                $sidText = $f[$cSid]
                if ($sidText.Length -gt 0) {
                    $e = $bySid[$sidText]
                    if ($null -eq $e) {
                        $sid = 0
                        if ([int]::TryParse($sidText, [ref]$sid)) { $e = & $resolveSession $tp $sid; $bySid[$sidText] = $e }
                    }
                    if ($null -ne $e) { $sessIdx = [int]$e.Index }
                }
                $key = $f[$cVol] + '|' + $f[$cKind] + '|' + $sessIdx
                $v = $volByKey[$key]
                if ($null -eq $v) {
                    $v = @{
                        Name = $f[$cVol]; Kind = $f[$cKind]; SessionIndex = $sessIdx; Backing = ''; Label = ''
                        ReadMs = (New-WorkerPerfNanArray $nT); WriteMs = (New-WorkerPerfNanArray $nT); Latency = (New-WorkerPerfNanArray $nT)
                        Ops = (New-Object double[] $nT)
                    }
                    $volByKey[$key] = $v; $volumes.Add($v)
                }
                $volAtSnap[$atKey] = $v
            }
            if ($v.Backing.Length -eq 0 -and $f[$cBack].Length -gt 0) { $v.Backing = $f[$cBack] }
            # latencies NaN and operations 0 when empty or unreadable
            $txt = $f[$cRl]; $rl = $numByText[$txt]
            if ($null -eq $rl) { $rl = ConvertTo-WorkerPerfCachedDouble $numByText $txt }
            $txt = $f[$cWl]; $wl = $numByText[$txt]
            if ($null -eq $wl) { $wl = ConvertTo-WorkerPerfCachedDouble $numByText $txt }
            $txt = $f[$cRo]; $ro = $numByText[$txt]
            if ($null -eq $ro) { $ro = ConvertTo-WorkerPerfCachedDouble $numByText $txt }
            $txt = $f[$cWo]; $wo = $numByText[$txt]
            if ($null -eq $wo) { $wo = ConvertTo-WorkerPerfCachedDouble $numByText $txt }
            if ([double]::IsNaN($ro)) { $ro = 0.0 }
            if ([double]::IsNaN($wo)) { $wo = 0.0 }
            $v.ReadMs[$tp] = $rl; $v.WriteMs[$tp] = $wl
            # latency: the larger of the two, ignoring NaN
            $lat = $rl
            if ([double]::IsNaN($rl)) { $lat = $wl } elseif (-not [double]::IsNaN($wl) -and $wl -gt $rl) { $lat = $wl }
            $v.Latency[$tp] = $lat
            $v.Ops[$tp] = $ro + $wo
        }
    }
    finally { if ($null -ne $reader) { $reader.Dispose() } }

    $shares = New-Object System.Collections.Generic.List[object]
    $shareByName = @{}
    $reader = $null      # opened first thing inside try, so that finally always closes it
    try {
        $csv = Open-WorkerPerfCsvReader $Path 'shares.csv'
        $reader = $csv.Reader; $need = $csv.Need
        $col = $csv.Col
        $cT = [int]$col['T']; $cSh = [int]$col['Share']
        $cRl = [int]$col['ReadLatMs']; $cWl = [int]$col['WriteLatMs']; $cRo = [int]$col['ReadOps']; $cWo = [int]$col['WriteOps']
        $lastT = $null; $tp = -1
        while ($null -ne $reader) {
            $line = $reader.ReadLine()
            if ($null -eq $line) { break }
            if ($line.Length -eq 0) { continue }
            if ($line.IndexOf('"') -lt 0) { $f = $line.Split(',') } else { $f = [string[]]@(Split-WorkerPerfCsvLine $line) }
            if ($f.Length -lt $need) { continue }
            $tText = $f[$cT]
            if (-not [string]::Equals($tText, $lastT)) {
                $lastT = $tText; $tp = -1; $t = 0
                if ([int]::TryParse($tText, [ref]$t) -and $tickPosByT.ContainsKey($t)) { $tp = [int]$tickPosByT[$t] }
            }
            if ($tp -lt 0) { continue }
            $s = $shareByName[$f[$cSh]]
            if ($null -eq $s) {
                $s = @{
                    Name = $f[$cSh]; Label = ''
                    ReadMs = (New-WorkerPerfNanArray $nT); WriteMs = (New-WorkerPerfNanArray $nT); Latency = (New-WorkerPerfNanArray $nT)
                    Ops = (New-Object double[] $nT)
                }
                $shareByName[$f[$cSh]] = $s; $shares.Add($s)
            }
            # latencies NaN and operations 0 when empty or unreadable
            $txt = $f[$cRl]; $rl = $numByText[$txt]
            if ($null -eq $rl) { $rl = ConvertTo-WorkerPerfCachedDouble $numByText $txt }
            $txt = $f[$cWl]; $wl = $numByText[$txt]
            if ($null -eq $wl) { $wl = ConvertTo-WorkerPerfCachedDouble $numByText $txt }
            $txt = $f[$cRo]; $ro = $numByText[$txt]
            if ($null -eq $ro) { $ro = ConvertTo-WorkerPerfCachedDouble $numByText $txt }
            $txt = $f[$cWo]; $wo = $numByText[$txt]
            if ($null -eq $wo) { $wo = ConvertTo-WorkerPerfCachedDouble $numByText $txt }
            if ([double]::IsNaN($ro)) { $ro = 0.0 }
            if ([double]::IsNaN($wo)) { $wo = 0.0 }
            $s.ReadMs[$tp] = $rl; $s.WriteMs[$tp] = $wl
            # latency: the larger of the two, ignoring NaN
            $lat = $rl
            if ([double]::IsNaN($rl)) { $lat = $wl } elseif (-not [double]::IsNaN($wl) -and $wl -gt $rl) { $lat = $wl }
            $s.Latency[$tp] = $lat
            $s.Ops[$tp] = $ro + $wo
        }
    }
    finally { if ($null -ne $reader) { $reader.Dispose() } }
    #endregion

    #region probes, citrix, events
    $probes = New-Object System.Collections.Generic.List[object]
    $probeByName = @{}
    $reader = $null      # opened first thing inside try, so that finally always closes it
    try {
        $csv = Open-WorkerPerfCsvReader $Path 'probes.csv'
        $reader = $csv.Reader; $need = $csv.Need
        $col = $csv.Col
        $cT = [int]$col['T']; $cName = [int]$col['Name']; $cRole = [int]$col['Role']; $cHost = [int]$col['Host']; $cPort = [int]$col['Port']
        $cMs = [int]$col['ConnectMs']; $cErr = [int]$col['Error']
        while ($null -ne $reader) {
            $line = $reader.ReadLine()
            if ($null -eq $line) { break }
            if ($line.Length -eq 0) { continue }
            if ($line.IndexOf('"') -lt 0) { $f = $line.Split(',') } else { $f = [string[]]@(Split-WorkerPerfCsvLine $line) }
            if ($f.Length -lt $need) { continue }
            $t = 0
            if (-not [int]::TryParse($f[$cT], [ref]$t)) { continue }
            if ($t -lt $tickTArr[0] -or $t -gt $tickTArr[$nT - 1]) { continue }     # outside the selected range
            $sp = [Array]::BinarySearch($snapT, [int]$t)
            if ($sp -lt 0) { $sp = -bnot $sp }
            if ($sp -ge $nP) { continue }
            $pr = $probeByName[$f[$cName]]
            if ($null -eq $pr) {
                $port = 0
                if (-not [int]::TryParse($f[$cPort], [ref]$port)) { $port = 0 }
                $pr = @{ Name = $f[$cName]; Role = $f[$cRole]; Host = $f[$cHost]; Port = $port; Ms = (New-WorkerPerfNanArray $nP); Error = (New-Object string[] $nP) }
                for ($i = 0; $i -lt $nP; $i++) { $pr.Error[$i] = '' }
                $probeByName[$f[$cName]] = $pr; $probes.Add($pr)
            }
            $ms = $nan
            $txt = $f[$cMs]; if ($txt.Length -gt 0 -and -not [double]::TryParse($txt, $numStyle, $inv, [ref]$ms)) { $ms = $nan }
            # a row with an error is a failed probe, with or without the duration until the abort
            if ($f[$cErr].Length -gt 0) {
                $ms = [double]::PositiveInfinity
                $pr.Error[$sp] = $f[$cErr]
            }
            elseif ([double]::IsNaN($ms)) { continue }
            if ([double]::IsNaN($pr.Ms[$sp]) -or $ms -gt $pr.Ms[$sp]) { $pr.Ms[$sp] = $ms }
        }
    }
    finally { if ($null -ne $reader) { $reader.Dispose() } }

    $citrixAgg = @{}
    $citrixOrder = New-Object System.Collections.Generic.List[string]
    $ctxTmp = @{}      # session index -> RoundtripTime and the three latency metrics per snapshot
    $latencyMetrics = 'NetworkLatency', 'Latency - Last Recorded', 'LatencyLastRecorded'
    $reader = $null      # opened first thing inside try, so that finally always closes it
    try {
        $csv = Open-WorkerPerfCsvReader $Path 'citrix.csv'
        $reader = $csv.Reader; $need = $csv.Need
        $col = $csv.Col
        $cT = [int]$col['T']; $cSrc = [int]$col['Source']; $cSid = [int]$col['SessionId']; $cInst = [int]$col['Instance']
        $cMetric = [int]$col['Metric']; $cVal = [int]$col['Value']
        $lastT = $null; $sp = -1
        while ($null -ne $reader) {
            $line = $reader.ReadLine()
            if ($null -eq $line) { break }
            if ($line.Length -eq 0) { continue }
            if ($line.IndexOf('"') -lt 0) { $f = $line.Split(',') } else { $f = [string[]]@(Split-WorkerPerfCsvLine $line) }
            if ($f.Length -lt $need) { continue }
            # the snapshot position is found again only when the T text changes (-1: unreadable or outside the range);
            # rows grouped by T make this cache hit, rows in any order give the same result
            $tText = $f[$cT]
            if (-not [string]::Equals($tText, $lastT)) {
                $lastT = $tText; $sp = -1; $t = 0
                if ([int]::TryParse($tText, [ref]$t) -and $t -ge $tickTArr[0] -and $t -le $tickTArr[$nT - 1]) {
                    $sp = [Array]::BinarySearch($snapT, [int]$t)
                    if ($sp -lt 0) { $sp = -bnot $sp }
                    if ($sp -ge $nP) { $sp = -1 }
                }
            }
            if ($sp -lt 0) { continue }
            $txt = $f[$cVal]
            $val = $numByText[$txt]
            if ($null -eq $val) { $val = ConvertTo-WorkerPerfCachedDouble $numByText $txt }
            if ([double]::IsNaN($val)) { continue }
            $sessIdx = -1
            $sid = 0
            if ($f[$cSid].Length -gt 0 -and [int]::TryParse($f[$cSid], [ref]$sid)) {
                $h = $sessBySnap[$sp]
                if ($null -eq $h -or -not $h.ContainsKey($sid)) { continue }
                $sessIdx = [int]$h[$sid].Index
            }
            $metric = $f[$cMetric]
            $key = $f[$cSrc] + '|' + $sessIdx + '|' + $f[$cInst] + '|' + $metric
            $a = $citrixAgg[$key]
            if ($null -eq $a) {
                $a = @{ Source = $f[$cSrc]; SessionIndex = $sessIdx; Instance = $f[$cInst]; Metric = $metric; Sum = 0.0; Max = $nan; N = 0 }
                $citrixAgg[$key] = $a; $citrixOrder.Add($key)
            }
            $a.Sum += $val; $a.N++
            if ([double]::IsNaN($a.Max) -or $val -gt $a.Max) { $a.Max = $val }
            if ($sessIdx -ge 0) {
                $slot = -1
                if ($metric -eq 'RoundtripTime') { $slot = 0 }
                else { $li = [array]::IndexOf($latencyMetrics, $metric); if ($li -ge 0) { $slot = $li + 1 } }
                if ($slot -ge 0) {
                    if (-not $ctxTmp.ContainsKey($sessIdx)) { $ctxTmp[$sessIdx] = @((New-WorkerPerfNanArray $nP), (New-WorkerPerfNanArray $nP), (New-WorkerPerfNanArray $nP), (New-WorkerPerfNanArray $nP)) }
                    $arr = $ctxTmp[$sessIdx][$slot]
                    if ([double]::IsNaN($arr[$sp])) { $arr[$sp] = $val }
                }
            }
        }
    }
    finally { if ($null -ne $reader) { $reader.Dispose() } }
    $citrix = New-Object System.Collections.Generic.List[object]
    foreach ($key in $citrixOrder) {
        $a = $citrixAgg[$key]
        $citrix.Add(@{ Source = $a.Source; SessionIndex = $a.SessionIndex; Instance = $a.Instance; Metric = $a.Metric; Avg = ($a.Sum / $a.N); Max = $a.Max; N = $a.N })
    }
    foreach ($si in $ctxTmp.Keys) {
        $s = $sessions[[int]$si]
        $tmp = $ctxTmp[$si]
        for ($p = 0; $p -lt $nP; $p++) {
            $s.Rtt[$p] = $tmp[0][$p]
            $lat = $nan
            for ($m = 1; $m -le 3; $m++) { if ([double]::IsNaN($lat)) { $lat = $tmp[$m][$p] } }
            $s.Latency[$p] = $lat
        }
    }

    # format 2 or 3, by time and then by position in the file (see Read-WorkerPerfEventCsv)
    $skipEvents = 0; $skipBefore = 0; $skipDrivers = 0; $skipQueues = 0
    $sortedEvents = @(Read-WorkerPerfEventCsv $Path 'events.csv' ([ref]$skipEvents))
    $eventsBefore = @(Read-WorkerPerfEventCsv $Path 'events_before.csv' ([ref]$skipBefore))
    $printDrivers = @(Read-WorkerPerfPrintDrivers $Path ([ref]$skipDrivers))
    $printQueues = @(Read-WorkerPerfPrintQueues $Path $fromMs $toMs ([ref]$skipQueues))
    $events = New-Object System.Collections.Generic.List[object]
    foreach ($e in $sortedEvents) { if ($e.TimeMs -ge $fromMs -and $e.TimeMs -le $toMs) { $events.Add($e) } }
    # scans: paired scan-start / scan-end over the whole file; an open scan lasts until the end of the measurement
    $scans = New-Object System.Collections.Generic.List[object]
    $openStart = $null
    $measureEnd = [long]$tickMsArr[$nT - 1]
    foreach ($e in $sortedEvents) {
        if ($e.Kind -eq 'scan-start') { if ($null -eq $openStart) { $openStart = [long]$e.TimeMs } }
        elseif ($e.Kind -eq 'scan-end' -and $null -ne $openStart) {
            $scans.Add(@{ StartMs = $openStart; EndMs = [long]$e.TimeMs }); $openStart = $null
        }
    }
    if ($null -ne $openStart) { $scans.Add(@{ StartMs = $openStart; EndMs = [Math]::Max($openStart, $measureEnd) }) }
    $scanList = New-Object System.Collections.Generic.List[object]
    foreach ($s in $scans) { if ($s.EndMs -ge $fromMs -and $s.StartMs -le $toMs) { $scanList.Add($s) } }
    #endregion

    #region processes
    # procinfo: one line per process number K; the first line for a K wins, a line with unreadable numbers is skipped
    $csv = Read-WorkerPerfCsvFile $Path 'procinfo.csv'
    $col = $csv.Col
    $cK = [int]$col['K']; $cPid = [int]$col['Pid']; $cName = [int]$col['Name']; $cSid = [int]$col['SessionId']; $cStart = [int]$col['StartTime']
    $cPath = [int]$col['Path']; $cSvc = [int]$col['Services']; $cCmd = [int]$col['CommandLine']
    $infoRows = New-Object System.Collections.Generic.List[object]
    $nK = 0
    foreach ($f in $csv.Rows) {
        $k = 0; $procId = 0; $sid = 0
        if (-not [int]::TryParse($f[$cK], [ref]$k) -or -not [int]::TryParse($f[$cPid], [ref]$procId) -or -not [int]::TryParse($f[$cSid], [ref]$sid)) { continue }
        if ($k -lt 0) { continue }
        $infoRows.Add(@($k, $procId, $sid, $f))
        if ($k + 1 -gt $nK) { $nK = $k + 1 }
    }
    $known = New-Object bool[] $nK
    $iPid = New-Object int[] $nK; $iSid = New-Object int[] $nK; $iName = New-Object string[] $nK; $iStart = New-Object object[] $nK
    $iPath = New-Object string[] $nK; $iSvc = New-Object string[] $nK; $iCmd = New-Object string[] $nK
    foreach ($r in $infoRows) {
        $k = [int]$r[0]
        if ($known[$k]) { continue }
        $f = $r[3]
        $known[$k] = $true; $iPid[$k] = [int]$r[1]; $iSid[$k] = [int]$r[2]; $iName[$k] = $f[$cName]
        $iPath[$k] = $f[$cPath]; $iSvc[$k] = $f[$cSvc]; $iCmd[$k] = $f[$cCmd]
        $sd = ConvertTo-WorkerPerfTimestamp $f[$cStart]
        if ($null -ne $sd) { $iStart[$k] = $sd.ToUnixTimeMilliseconds() }
    }

    $endByP = @{}                      # P -> process numbers that ended at that snapshot
    $csv = Read-WorkerPerfCsvFile $Path 'procend.csv'
    $col = $csv.Col
    $cP = [int]$col['P']; $cK = [int]$col['K']
    foreach ($f in $csv.Rows) {
        $p = 0; $k = 0
        if (-not [int]::TryParse($f[$cP], [ref]$p) -or -not [int]::TryParse($f[$cK], [ref]$k)) { continue }
        if ($k -lt 0 -or $k -ge $nK) { continue }
        if (-not $endByP.ContainsKey($p)) { $endByP[$p] = New-Object System.Collections.Generic.List[int] }
        $endByP[$p].Add($k)
    }

    # Snapshots to read: from the last keyframe not after the first snapshot of the range (rows before the range only
    # build the carried-forward state) through the last snapshot of the range. $seqPos is -1 for the snapshots before the range.
    $preFrom = 0
    if ($snapKind[0] -eq 'K') { $preFrom = $preP.Count }
    else { for ($i = $preP.Count - 1; $i -ge 0; $i--) { if ($preKind[$i] -eq 'K') { $preFrom = $i; break } } }
    $seqN = $preP.Count - $preFrom + $nP
    $seqP = New-Object int[] $seqN; $seqPos = New-Object int[] $seqN; $seqKey = New-Object bool[] $seqN
    for ($i = $preFrom; $i -lt $preP.Count; $i++) { $j = $i - $preFrom; $seqP[$j] = $preP[$i]; $seqPos[$j] = -1; $seqKey[$j] = ($preKind[$i] -eq 'K') }
    for ($i = 0; $i -lt $nP; $i++) { $j = $preP.Count - $preFrom + $i; $seqP[$j] = $snapP[$i]; $seqPos[$j] = $i; $seqKey[$j] = ($snapKind[$i] -eq 'K') }

    # CPU share of the host capacity per snapshot (ElapsedSec * 1000 * Cores), as a factor for CPU milliseconds
    $pctPerMs = New-Object double[] $nP
    for ($i = 0; $i -lt $nP; $i++) {
        $capMs = $snapNum['ElapsedSec'][$i] * 1000.0 * $cores
        if ($capMs -gt 0) { $pctPerMs[$i] = 100.0 / $capMs }
    }

    # per-process state, indexed by K. State: 0 = not seen yet, 1 = alive, 2 = ended.
    $pState = New-Object int[] $nK; $pLastJ = New-Object int[] $nK
    $pWs = New-Object double[] $nK; $pPriv = New-Object double[] $nK
    $pSess = New-Object int[] $nK; $pApp = New-Object int[] $nK; $pPair = New-Object int[] $nK
    for ($k = 0; $k -lt $nK; $k++) { $pSess[$k] = -1 }
    $pFirst = New-Object int[] $nK; $pLast = New-Object int[] $nK; $pWsSince = New-Object int[] $nK
    $pCpu = New-Object double[] $nK; $pCpuMax = New-Object double[] $nK; $pIo = New-Object double[] $nK
    $pWsMax = New-Object double[] $nK; $pWsSum = New-Object double[] $nK; $pPrivMax = New-Object double[] $nK
    $pHandles = New-Object int[] $nK; $pThreads = New-Object int[] $nK
    $pRole = New-Object string[] $nK; $pRoleLabel = New-Object string[] $nK
    $alive = New-Object System.Collections.Generic.List[int]
    # running sums per session index (orphan sessions can still be added), application index and session x application pair
    $maxS = $sessions.Count + $nK + 1
    $sWs = New-Object double[] $maxS; $sPriv = New-Object double[] $maxS; $sN = New-Object int[] $maxS
    $sCpuA = New-Object object[] $maxS; $sIoA = New-Object object[] $maxS; $sWsA = New-Object object[] $maxS; $sPrivA = New-Object object[] $maxS; $sNA = New-Object object[] $maxS
    $usedSess = New-Object System.Collections.Generic.List[int]
    $apps = New-Object System.Collections.Generic.List[object]
    $appByName = @{}
    $aWs = New-Object double[] ($nK + 1); $aPriv = New-Object double[] ($nK + 1); $aN = New-Object int[] ($nK + 1)
    $aCpuA = New-Object object[] ($nK + 1); $aIoA = New-Object object[] ($nK + 1); $aWsA = New-Object object[] ($nK + 1); $aPrivA = New-Object object[] ($nK + 1); $aNA = New-Object object[] ($nK + 1)
    $pairKeys = New-Object System.Collections.Generic.List[string]
    $pairByKey = @{}
    # pair working set: Cur holds from position Since on; Sum and Max cover the positions before Since
    $prS = New-Object int[] ($nK + 1); $prA = New-Object int[] ($nK + 1); $prInst = New-Object int[] ($nK + 1)
    $prCpu = New-Object double[] ($nK + 1); $prIo = New-Object double[] ($nK + 1)
    $prCur = New-Object double[] ($nK + 1); $prSince = New-Object int[] ($nK + 1); $prSum = New-Object double[] ($nK + 1); $prMax = New-Object double[] ($nK + 1)
    $prAlive = New-Object int[] ($nK + 1); $prSnaps = New-Object int[] ($nK + 1)      # living processes; positions with at least one
    $rowStart = New-Object int[] ($nP + 1)
    $rowK = New-Object System.Collections.Generic.List[int]
    $rowCpu = New-Object System.Collections.Generic.List[double]
    $rowIo = New-Object System.Collections.Generic.List[double]
    $rowWs = New-Object System.Collections.Generic.List[double]
    $totalCpuMs = 0.0
    # state carried over a -From cut: processes alive at position 0 without a row there, with their working set (KB)
    $carriedK = New-Object System.Collections.Generic.List[int]
    $carriedWs = New-Object System.Collections.Generic.List[double]

    # Called once per process when it first counts in the range (position $Pos): links session, application and pair
    # and adds its current state to their sums. $Carried: the state from before the range holds at $Pos (no row there).
    $attachProcess = {
        param([int]$K, [int]$Pos, [bool]$Carried)
        $sid = $iSid[$K]
        $h = $sessBySnap[$Pos]
        if ($null -ne $h -and $h.ContainsKey($sid)) { $si = [int]$h[$sid].Index }
        else { $si = [int](& $resolveSession $snapTickPos[$Pos] $sid).Index }
        if ($null -eq $sCpuA[$si]) {
            $e = $sessions[$si]
            $sCpuA[$si] = $e.CpuMs; $sIoA[$si] = $e.Io; $sWsA[$si] = $e.Ws; $sPrivA[$si] = $e.Priv; $sNA[$si] = $e.N
            $usedSess.Add($si)
        }
        $name = [string]$iName[$K]
        $appKey = $name.ToLowerInvariant()
        if ($appByName.ContainsKey($appKey)) { $ai = [int]$appByName[$appKey] }
        else {
            $ai = $apps.Count
            $ar = Resolve-WorkerPerfRole $Roles $name '' $sid
            $a = @{
                Index = $ai; Name = $name; Role = $ar.Role; RoleLabel = $ar.Label; Path = [string]$iPath[$K]; Instances = 0
                CpuMs = (New-Object double[] $nP); Ws = (New-Object double[] $nP); Priv = (New-Object double[] $nP); Io = (New-Object double[] $nP)
                N = (New-Object int[] $nP)
            }
            $apps.Add($a); $appByName[$appKey] = $ai
            $aCpuA[$ai] = $a.CpuMs; $aIoA[$ai] = $a.Io; $aWsA[$ai] = $a.Ws; $aPrivA[$ai] = $a.Priv; $aNA[$ai] = $a.N
        }
        $apps[$ai].Instances++
        $pairKey = [string]$si + '|' + $ai
        if ($pairByKey.ContainsKey($pairKey)) { $pi = [int]$pairByKey[$pairKey] }
        else {
            $pi = $pairKeys.Count
            $pairKeys.Add($pairKey); $pairByKey[$pairKey] = $pi
            $prS[$pi] = $si; $prA[$pi] = $ai; $prSince[$pi] = $Pos
        }
        $prInst[$pi]++
        $pr = Resolve-WorkerPerfRole $Roles $name ([string]$iSvc[$K]) $sid
        $pRole[$K] = $pr.Role; $pRoleLabel[$K] = $pr.Label
        $pSess[$K] = $si; $pApp[$K] = $ai; $pPair[$K] = $pi
        $pFirst[$K] = $Pos; $pWsSince[$K] = $Pos
        if ($Carried) { $pWsMax[$K] = $pWs[$K]; $pPrivMax[$K] = $pPriv[$K] }
        $sWs[$si] += $pWs[$K]; $sPriv[$si] += $pPriv[$K]; $sN[$si]++
        $aWs[$ai] += $pWs[$K]; $aPriv[$ai] += $pPriv[$K]; $aN[$ai]++
        if ($prSince[$pi] -lt $Pos) {
            $prSum[$pi] += $prCur[$pi] * ($Pos - $prSince[$pi])
            if ($prAlive[$pi] -gt 0) { $prSnaps[$pi] += $Pos - $prSince[$pi] }
            if ($prCur[$pi] -gt $prMax[$pi]) { $prMax[$pi] = $prCur[$pi] }
            $prSince[$pi] = $Pos
        }
        $prCur[$pi] += $pWs[$K]; $prAlive[$pi]++
    }
    # Called once per process when it ends at snapshot position $Pos (not counted there; -1 before the range).
    $endProcess = {
        param([int]$K, [int]$Pos)
        if ($pState[$K] -ne 1) { return }
        $pState[$K] = 2
        if ($pSess[$K] -lt 0) { return }
        $si = $pSess[$K]; $ai = $pApp[$K]; $pi = $pPair[$K]
        $sWs[$si] -= $pWs[$K]; $sPriv[$si] -= $pPriv[$K]; $sN[$si]--
        $aWs[$ai] -= $pWs[$K]; $aPriv[$ai] -= $pPriv[$K]; $aN[$ai]--
        if ($prSince[$pi] -lt $Pos) {
            $prSum[$pi] += $prCur[$pi] * ($Pos - $prSince[$pi])
            if ($prAlive[$pi] -gt 0) { $prSnaps[$pi] += $Pos - $prSince[$pi] }
            if ($prCur[$pi] -gt $prMax[$pi]) { $prMax[$pi] = $prCur[$pi] }
            $prSince[$pi] = $Pos
        }
        $prCur[$pi] -= $pWs[$K]; $prAlive[$pi]--
        $pWsSum[$K] += $pWs[$K] * ($Pos - $pWsSince[$K])
        $pLast[$K] = $Pos - 1
    }

    # One pass over processes.csv (sorted by P). Snapshot j begins with its ended lines and ends, at a keyframe, by ending
    # every living process without a row, then writes the session and application sums of its position.
    # This loop is the hot spot of the analysis: no function call and no pipeline per row.
    $j = 0
    if ($endByP.ContainsKey($seqP[0])) { foreach ($k in $endByP[$seqP[0]]) { & $endProcess $k $seqPos[0] } }
    $full = Join-Path $Path 'processes.csv'
    $reader = $null
    if (Test-WorkerPerfRunFile $full) {
        $stream = [IO.File]::Open($full, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $reader = New-Object System.IO.StreamReader($stream, [Text.Encoding]::UTF8)
    }
    try {
        # column positions from the header line, like Read-WorkerPerfCsvFile
        $col = @{}
        $canon = $script:WorkerPerfHeaders['processes.csv'].Split(',')
        for ($i = 0; $i -lt $canon.Length; $i++) { $col[$canon[$i]] = $i }
        $header = $null
        if ($null -ne $reader) { $header = $reader.ReadLine() }
        if ($null -ne $header -and $header.Length -gt 0) {
            $names = $header.Split(',')
            for ($i = 0; $i -lt $names.Length; $i++) { $col[$names[$i].Trim()] = $i }
        }
        $need = $canon.Length
        $cP = [int]$col['P']; $cK = [int]$col['K']; $cCpu = [int]$col['CpuMs']; $cWs = [int]$col['WsKB']; $cPriv = [int]$col['PrivKB']
        $cRd = [int]$col['ReadBytes']; $cWr = [int]$col['WriteBytes']; $cHandles = [int]$col['Handles']; $cThreads = [int]$col['Threads']
        $rowP = 0
        while ($true) {
            $line = $null
            if ($null -ne $reader) { $line = $reader.ReadLine() }
            if ($null -eq $line) { $rowP = [int]::MaxValue }
            else {
                $f = $line.Split(',')
                if ($f.Length -lt $need -or -not [int]::TryParse($f[$cP], [ref]$rowP)) { continue }
            }
            while ($j -lt $seqN -and $seqP[$j] -lt $rowP) {
                # end of snapshot j
                $pos = $seqPos[$j]
                if ($seqKey[$j]) {
                    foreach ($k in $alive) { if ($pState[$k] -eq 1 -and $pLastJ[$k] -ne $j) { & $endProcess $k $pos } }
                    $still = New-Object System.Collections.Generic.List[int]
                    foreach ($k in $alive) { if ($pState[$k] -eq 1) { $still.Add($k) } }
                    $alive = $still
                }
                if ($pos -eq 0) {
                    foreach ($k in $alive) {
                        if ($pState[$k] -eq 1 -and $pSess[$k] -lt 0) { & $attachProcess $k 0 $true; $carriedK.Add($k); $carriedWs.Add($pWs[$k]) }
                    }
                }
                if ($pos -ge 0) {
                    foreach ($si in $usedSess) { $sWsA[$si][$pos] = $sWs[$si]; $sPrivA[$si][$pos] = $sPriv[$si]; $sNA[$si][$pos] = $sN[$si] }
                    for ($ai = 0; $ai -lt $apps.Count; $ai++) { $aWsA[$ai][$pos] = $aWs[$ai]; $aPrivA[$ai][$pos] = $aPriv[$ai]; $aNA[$ai][$pos] = $aN[$ai] }
                    $rowStart[$pos + 1] = $rowK.Count
                }
                # begin of snapshot j + 1
                $j++
                if ($j -lt $seqN -and $endByP.ContainsKey($seqP[$j])) { foreach ($k in $endByP[$seqP[$j]]) { & $endProcess $k $seqPos[$j] } }
            }
            if ($j -ge $seqN) { break }
            if ($seqP[$j] -ne $rowP) { continue }          # before the first snapshot read, or a P without snapshot line
            $k = 0
            if (-not [int]::TryParse($f[$cK], [ref]$k) -or $k -lt 0 -or $k -ge $nK) { continue }
            if (-not $known[$k] -or $pState[$k] -eq 2) { continue }
            try {
                $cpu = [double]$f[$cCpu]; $ws = [double]$f[$cWs]; $priv = [double]$f[$cPriv]; $io = [double]$f[$cRd] + [double]$f[$cWr]
                $pHandles[$k] = [int]$f[$cHandles]; $pThreads[$k] = [int]$f[$cThreads]
            }
            catch { continue }
            if ($pState[$k] -eq 0) { $pState[$k] = 1; $alive.Add($k) }
            $pLastJ[$k] = $j
            $pos = $seqPos[$j]
            if ($pos -lt 0) { $pWs[$k] = $ws; $pPriv[$k] = $priv; continue }
            if ($pSess[$k] -lt 0) { & $attachProcess $k $pos $false }
            $si = $pSess[$k]; $ai = $pApp[$k]; $pi = $pPair[$k]
            $dWs = $ws - $pWs[$k]; $dPriv = $priv - $pPriv[$k]
            $sWs[$si] += $dWs; $sPriv[$si] += $dPriv; $aWs[$ai] += $dWs; $aPriv[$ai] += $dPriv
            if ($dWs -ne 0) {
                if ($prSince[$pi] -lt $pos) {
                    $prSum[$pi] += $prCur[$pi] * ($pos - $prSince[$pi])
                    if ($prAlive[$pi] -gt 0) { $prSnaps[$pi] += $pos - $prSince[$pi] }
                    if ($prCur[$pi] -gt $prMax[$pi]) { $prMax[$pi] = $prCur[$pi] }
                    $prSince[$pi] = $pos
                }
                $prCur[$pi] += $dWs
                $pWsSum[$k] += $pWs[$k] * ($pos - $pWsSince[$k]); $pWsSince[$k] = $pos
                $pWs[$k] = $ws
            }
            if ($ws -gt $pWsMax[$k]) { $pWsMax[$k] = $ws }
            $pPriv[$k] = $priv
            if ($priv -gt $pPrivMax[$k]) { $pPrivMax[$k] = $priv }
            $pCpu[$k] += $cpu; $pIo[$k] += $io
            $pct = $cpu * $pctPerMs[$pos]
            if ($pct -gt $pCpuMax[$k]) { $pCpuMax[$k] = $pct }
            $sCpuA[$si][$pos] += $cpu; $sIoA[$si][$pos] += $io; $aCpuA[$ai][$pos] += $cpu; $aIoA[$ai][$pos] += $io
            $prCpu[$pi] += $cpu; $prIo[$pi] += $io
            $rowK.Add($k); $rowCpu.Add($cpu); $rowIo.Add($io); $rowWs.Add($ws)
            $totalCpuMs += $cpu
        }
    }
    finally { if ($null -ne $reader) { $reader.Dispose() } }

    $collectorPid = -1
    if ($null -ne $meta['CollectorPid']) {
        $cp = 0
        if ([int]::TryParse([string]$meta['CollectorPid'], [ref]$cp)) { $collectorPid = $cp }
    }
    $procs = New-Object object[] $nK
    $kByPid = @{}
    for ($k = 0; $k -lt $nK; $k++) {
        if ($pSess[$k] -lt 0) { continue }              # unknown or not alive in the range
        if ($pState[$k] -eq 1) { $pWsSum[$k] += $pWs[$k] * ($nP - $pWsSince[$k]); $pLast[$k] = $nP - 1 }
        $span = $pLast[$k] - $pFirst[$k] + 1
        $procs[$k] = @{
            K = $k; Pid = $iPid[$k]; Name = $iName[$k]; Sid = $iSid[$k]; StartMs = $iStart[$k]; Path = $iPath[$k]; Services = $iSvc[$k]; Cmd = $iCmd[$k]
            SessionIndex = $pSess[$k]; AppIndex = $pApp[$k]; Role = $pRole[$k]; RoleLabel = $pRoleLabel[$k]; IsCollector = ($iPid[$k] -eq $collectorPid)
            FirstP = $pFirst[$k]; LastP = $pLast[$k]; CpuMs = $pCpu[$k]; CpuMaxPct = $pCpuMax[$k]; WsMaxKB = $pWsMax[$k]; WsAvgKB = ($pWsSum[$k] / $span)
            PrivMaxKB = $pPrivMax[$k]; IoBytes = $pIo[$k]; Handles = $pHandles[$k]; Threads = $pThreads[$k]
        }
        if (-not $kByPid.ContainsKey($iPid[$k])) { $kByPid[$iPid[$k]] = New-Object System.Collections.Generic.List[int] }
        $kByPid[$iPid[$k]].Add($k)
    }
    $pairs = @{}
    for ($pi = 0; $pi -lt $pairKeys.Count; $pi++) {
        if ($prSince[$pi] -lt $nP) {
            $prSum[$pi] += $prCur[$pi] * ($nP - $prSince[$pi])
            if ($prAlive[$pi] -gt 0) { $prSnaps[$pi] += $nP - $prSince[$pi] }
            if ($prCur[$pi] -gt $prMax[$pi]) { $prMax[$pi] = $prCur[$pi] }
        }
        $pairs[$pairKeys[$pi]] = @{ S = $prS[$pi]; A = $prA[$pi]; Instances = $prInst[$pi]; CpuMs = $prCpu[$pi]; IoBytes = $prIo[$pi]; WsSumKB = $prSum[$pi]; WsMaxKB = $prMax[$pi]; Snaps = $prSnaps[$pi] }
    }

    # input delay per process: the process that had the PID at the snapshot of the tick
    $ipTickArr = $ipTick.ToArray(); $ipPidArr = $ipPid.ToArray()
    $ipK = New-Object int[] $ipTickArr.Length
    for ($i = 0; $i -lt $ipK.Length; $i++) {
        $ipK[$i] = -1
        if (-not $kByPid.ContainsKey($ipPidArr[$i])) { continue }
        $sp = $firstSnapAt[$ipTickArr[$i]]
        if ($sp -ge $nP) { $sp = $nP - 1 }
        foreach ($k in $kByPid[$ipPidArr[$i]]) { if ($pFirst[$k] -le $sp -and $pLast[$k] -ge $sp) { $ipK[$i] = $k; break } }
    }
    #endregion

    #region labels and links
    foreach ($s in $sessions) {
        if ($s.User.Length -gt 0) { $s.Label = $s.User + ' (#' + $s.Sid + ')' }
        elseif ($s.Sid -eq 0) { $s.Label = 'Dienste/System' }
        else { $s.Label = 'Sitzung ' + $s.Sid }
    }
    Set-WorkerPerfUniqueLabels $sessions
    for ($i = 0; $i -lt $volumes.Count; $i++) {
        $v = $volumes[$i]
        if ($v.Kind -eq 'profile') {
            $user = ''
            if ($v.SessionIndex -ge 0) { $user = [string]$sessions[$v.SessionIndex].User }
            if ($user.Length -gt 0) { $v.Label = 'Profilcontainer von ' + $user + ' (' + $v.Backing + ')' }
            else { $v.Label = 'Profilcontainer (Benutzer unbekannt) ' + $v.Name }
            if ($v.SessionIndex -ge 0 -and $sessions[$v.SessionIndex].ProfileVolume -lt 0) { $sessions[$v.SessionIndex].ProfileVolume = $i }
        }
        else { $v.Label = 'Laufwerk ' + $v.Name }
    }
    Set-WorkerPerfUniqueLabels $volumes
    foreach ($s in $shares) { $s.Label = 'Freigabe ' + $s.Name }
    Set-WorkerPerfUniqueLabels $shares
    foreach ($pr in $probes) { $pr.Label = $pr.Name }
    #endregion

    $meta['Cores'] = $cores; $meta['RamMB'] = $ramMb; $meta['OffsetMinutes'] = $offsetMinutes
    $meta['FastSec'] = $fastSec; $meta['SnapSec'] = $snapSec
    $kinds = $snapKind.ToArray()
    return @{
        Meta = $meta
        Skip = $recordedSkip
        Sources = $sources
        Tick = @{
            N = $nT; TimeMs = $tickMsArr; ElapsedSec = $raw['ElapsedSec']; Burst = $burst; CollectMs = $raw['CollectMs']
            Raw = $raw; Signal = $signal
        }
        Snap = @{
            N = $nP; TimeMs = $snapMs; ElapsedSec = $snapNum['ElapsedSec'].ToArray(); Kind = $kinds; TickPos = $snapTickPos
            Sessions = $snapNum['Sessions'].ToArray(); ActiveSessions = $snapNum['ActiveSessions'].ToArray()
            Processes = $snapNum['Processes'].ToArray(); RowsWritten = $snapNum['RowsWritten'].ToArray(); CollectMs = $snapNum['CollectMs'].ToArray()
        }
        Sessions = $sessions.ToArray()
        Volumes = $volumes.ToArray()
        Shares = $shares.ToArray()
        Probes = $probes.ToArray()
        Events = $events.ToArray()
        EventsAll = [object[]]$sortedEvents
        EventsOutsideCut = $sortedEvents.Count - $events.Count
        CaptureStartMs = $captureStartMs
        CaptureEndMs = $(if ($null -ne $lastDto) { $lastDto.ToUnixTimeMilliseconds() } else { $null })
        EventsBefore = $eventsBefore
        PrintDrivers = $printDrivers
        PrintQueues = $printQueues
        Scans = $scanList.ToArray()
        InputProc = @{ TickPos = $ipTickArr; SessionIndex = $ipSess.ToArray(); Pid = $ipPidArr; Name = $ipName.ToArray(); DelayMs = $ipDelay.ToArray(); K = $ipK }
        Apps = $apps.ToArray()
        Proc = $procs
        Pairs = $pairs
        Rows = @{ Start = $rowStart; K = $rowK.ToArray(); CpuMs = $rowCpu.ToArray(); Io = $rowIo.ToArray(); WsKB = $rowWs.ToArray() }
        Carried = @{ K = $carriedK.ToArray(); WsKB = $carriedWs.ToArray() }
        Unreadable = @{ Ticks = $badTicks; Snapshots = $badSnaps; Events = $skipEvents; EventsBefore = $skipBefore; PrintDrivers = $skipDrivers; PrintQueues = $skipQueues }
        SourceErrors = $sourceErrors.ToArray()
        TotalCpuMs = $totalCpuMs
        MainApp = $mainApp
        Citrix = $citrix.ToArray()
        Health = $health
        HealthState = $healthState
        Recorded = $recorded
    }
}

function Test-WorkerPerfSeriesRateable([double[]]$Value, $Ops, [double]$MinOps) {
    # $true when at least one point has a value (and enough operations when the threshold asks for them).
    for ($i = 0; $i -lt $Value.Length; $i++) {
        if ([double]::IsNaN($Value[$i])) { continue }
        if ($MinOps -gt 0 -and $null -ne $Ops -and $Ops[$i] -lt $MinOps) { continue }
        return $true
    }
    return $false
}

function Get-WorkerPerfSeries {
    param($Model, $Thresholds)
    $list = New-Object System.Collections.Generic.List[object]
    $tick = $Model.Tick
    $snap = $Model.Snap
    $labelOf = {
        param([string]$Id)
        if ($null -ne $Thresholds -and $Thresholds.Contains($Id)) { return [string]$Thresholds[$Id].label }
        return $Id
    }
    $minOpsOf = {
        param([string]$Id)
        if ($null -ne $Thresholds -and $Thresholds.Contains($Id)) { return [double]$Thresholds[$Id].minOps }
        return 0.0
    }
    $add = {
        param($Id, $Resource, $Scope, $Instance, $Label, $SessionIndex, $TimeMs, $ElapsedSec, $Value, $Ops)
        $list.Add(@{
            Id = $Id; Resource = $Resource; Scope = $Scope; Instance = $Instance; Label = $Label; SessionIndex = $SessionIndex
            TimeMs = $TimeMs; ElapsedSec = $ElapsedSec; Value = $Value; Ops = $Ops
        })
    }
    # keeps only the snapshot points with a value; ElapsedSec is the distance to the previous kept point
    $addSparse = {
        param($Id, $Resource, $Scope, $Instance, $Label, $SessionIndex, [double[]]$PerSnap)
        $times = New-Object System.Collections.Generic.List[long]
        $elapsed = New-Object System.Collections.Generic.List[double]
        $vals = New-Object System.Collections.Generic.List[double]
        for ($p = 0; $p -lt $snap.N; $p++) {
            if ([double]::IsNaN($PerSnap[$p])) { continue }
            if ($times.Count -eq 0) { $elapsed.Add([double]$snap.ElapsedSec[$p]) }
            else { $elapsed.Add(([long]$snap.TimeMs[$p] - $times[$times.Count - 1]) / 1000.0) }
            $times.Add([long]$snap.TimeMs[$p]); $vals.Add($PerSnap[$p])
        }
        if ($vals.Count -eq 0) { return }
        & $add $Id $Resource $Scope $Instance $Label $SessionIndex $times.ToArray() $elapsed.ToArray() $vals.ToArray() $null
    }

    $hostResource = @{ 'cpu.host' = 'cpu'; 'cpu.queue' = 'cpu'; 'cpu.steal' = 'cpu'; 'mem.used' = 'memory'; 'mem.commit' = 'memory'; 'mem.pagesin' = 'memory' }
    foreach ($id in 'cpu.host', 'cpu.queue', 'cpu.steal', 'mem.used', 'mem.commit', 'mem.pagesin') {
        $v = [double[]]$tick.Signal[$id]
        if (-not (Test-WorkerPerfSeriesRateable $v $null 0)) { continue }
        & $add $id $hostResource[$id] 'global' '' (& $labelOf $id) -1 $tick.TimeMs $tick.ElapsedSec $v $null
    }

    foreach ($s in $Model.Sessions) {
        $has = $false
        foreach ($x in $s.Input) { if ($x -gt 0) { $has = $true; break } }
        if ($has) { & $add 'input.session' 'input' 'session' $s.Label $s.Label $s.Index $tick.TimeMs $tick.ElapsedSec $s.Input $null }
    }

    $diskMin = & $minOpsOf 'disk.latency'
    foreach ($v in $Model.Volumes) {
        if (-not (Test-WorkerPerfSeriesRateable $v.Latency $v.Ops $diskMin)) { continue }
        $resource = 'disk'; $scope = 'global'
        if ($v.Kind -eq 'profile') { $resource = 'profile'; $scope = 'session' }
        & $add 'disk.latency' $resource $scope $v.Name $v.Label $v.SessionIndex $tick.TimeMs $tick.ElapsedSec $v.Latency $v.Ops
    }

    $smbMin = & $minOpsOf 'smb.latency'
    foreach ($sh in $Model.Shares) {
        if (-not (Test-WorkerPerfSeriesRateable $sh.Latency $sh.Ops $smbMin)) { continue }
        & $add 'smb.latency' 'share' 'global' $sh.Name $sh.Label -1 $tick.TimeMs $tick.ElapsedSec $sh.Latency $sh.Ops
    }

    foreach ($s in $Model.Sessions) {
        & $addSparse 'ica.rtt' 'network' 'session' $s.Label $s.Label $s.Index $s.Rtt
        & $addSparse 'ica.latency' 'network' 'session' $s.Label $s.Label $s.Index $s.Latency
    }
    foreach ($pr in $Model.Probes) {
        & $addSparse 'probe.connect' 'endpoint' 'global' $pr.Name $pr.Label -1 $pr.Ms
    }
    $list.ToArray()
}
