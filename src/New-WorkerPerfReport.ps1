#Requires -Version 5.1
<#
.SYNOPSIS
    Builds a self-contained, offline HTML report from a WorkerPerf capture folder (format 2).

.DESCRIPTION
    Reads the capture with Import-WorkerPerfRun, rates every measurement series against the
    thresholds, groups the findings into incidents, attributes them to sessions, applications
    and processes and writes one HTML file that embeds all data as JSON.

    Thresholds and roles are read at analysis time: a capture can be re-evaluated with changed
    files. Runs on Windows PowerShell 5.1 and PowerShell 7 (any platform).

.PARAMETER Path
    Capture folder (contains meta.json, ticks.csv, snapshots.csv, ...).

.PARAMETER OutFile
    Target file. Default: <Path>\report.html

.PARAMETER From
    Only analyse measurements at or after this time, as local time of the measured server
    (like -ReportedTime and every time the report shows).

.PARAMETER To
    Only analyse measurements at or before this time, as local time of the measured server.

.PARAMETER ThresholdFile
    Threshold file. Default: thresholds.json next to this script.

.PARAMETER RoleFile
    Role file. Default: roles.json next to this script.

.PARAMETER FocusUser
    User who reported the problem (User or Domain\User, case-insensitive).

.PARAMETER ReportedTime
    Reported time of the problem, as local time of the measured server. Before the capture it selects the events of
    the days before within 15 minutes (each at the local time of its own day).

.PARAMETER TopProcesses
    Number of individual processes (by CPU time and by peak memory each) kept in the report.

.PARAMETER Mask
    Replaces names in the report (the capture itself is never changed). Personen: users, clients and account SIDs.
    Alles: also servers (the worker included), shares, domains, addresses and printers. In both levels the message
    texts of events and the command lines are left out. The replacement names are taken from the whole capture, so
    every report of one capture, with or without -From/-To, uses the same ones. With Alles the file name of -OutFile
    must not name the worker. A -FocusUser that the capture does not name is shown as "(Name entfernt)". The console
    names the replacement names of names that equal a word of the report (their sentences are garbled).

.PARAMETER MaskMapFile
    Only with -Mask: writes the real names and their replacement names to this JSON file (UTF-8), after the report was
    written. The file holds the real names: keep it with you and do not pass it on with the report. Its folder must
    exist, and it must not name an existing file in the capture folder (both checked before the run).

.EXAMPLE
    .\New-WorkerPerfReport.ps1 -Path D:\WorkerPerf\VDA01_20260101-080000

.EXAMPLE
    .\New-WorkerPerfReport.ps1 -Path .\run -OutFile .\bericht.html -Mask Alles -MaskMapFile .\bericht.maskmap.json

.EXAMPLE
    .\New-WorkerPerfReport.ps1 -Path .\run -FocusUser 'CONTOSO\mmuster' -ReportedTime '2026-01-01 10:15'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)][string]$Path,
    [string]$OutFile,
    [datetime]$From = [datetime]::MinValue,
    [datetime]$To = [datetime]::MaxValue,
    [string]$ThresholdFile,
    [string]$RoleFile,
    [string]$FocusUser,
    [datetime]$ReportedTime,
    [ValidateRange(10, 2000)][int]$TopProcesses = 150,
    [ValidateSet('Personen', 'Alles')][string]$Mask,
    [string]$MaskMapFile
)

# Where AppLocker or WDAC puts the console into ConstrainedLanguage, .NET types fail with errors that do not name
# the cause. This check uses nothing that the restricted mode forbids.
$languageMode = "$($ExecutionContext.SessionState.LanguageMode)"
if ($languageMode -ne 'FullLanguage') {
    throw "WorkerPerf benoetigt den PowerShell-Sprachmodus FullLanguage; aktiv ist $languageMode. AppLocker oder WDAC schraenkt diese Konsole ein: bitte eine uneingeschraenkte administrative Konsole verwenden."
}

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture
$nan = [double]::NaN

. (Join-Path $PSScriptRoot 'WorkerPerf.Common.ps1')
. (Join-Path $PSScriptRoot 'WorkerPerf.EventConfig.ps1')
. (Join-Path $PSScriptRoot 'WorkerPerf.Events.ps1')
. (Join-Path $PSScriptRoot 'WorkerPerf.Load.ps1')
. (Join-Path $PSScriptRoot 'WorkerPerf.Findings.ps1')
# the masking only in a masked run: without -Mask the report does not depend on it. The level in the spelling of the
# set (ValidateSet takes any case), as the report data carries it.
if ($Mask) {
    if ($Mask -eq 'Alles') { $Mask = 'Alles' } else { $Mask = 'Personen' }
    . (Join-Path $PSScriptRoot 'WorkerPerf.Mask.ps1')
}

#region ---------- helpers ----------------------------------------------------------------

$script:JsonSpecial = New-Object System.Text.RegularExpressions.Regex ('[\x00-\x1f"\\<>&\u2028\u2029]', [System.Text.RegularExpressions.RegexOptions]::Compiled)

function Format-JsonString([string]$Text) {
    if ($null -eq $Text) { return 'null' }
    if (-not $script:JsonSpecial.IsMatch($Text)) { return '"' + $Text + '"' }
    $sb = New-Object System.Text.StringBuilder ($Text.Length + 16)
    [void]$sb.Append('"')
    foreach ($c in $Text.ToCharArray()) {
        $code = [int]$c
        if ($c -eq '"') { [void]$sb.Append('\"') }
        elseif ($c -eq '\') { [void]$sb.Append('\\') }
        elseif ($code -lt 32 -or $c -eq '<' -or $c -eq '>' -or $c -eq '&' -or $code -eq 0x2028 -or $code -eq 0x2029) { [void]$sb.Append('\u' + $code.ToString('x4', $inv)) }
        else { [void]$sb.Append($c) }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Format-JsonNumber([double]$Value, [int]$Decimals) {
    if ([double]::IsNaN($Value) -or [double]::IsInfinity($Value)) { return 'null' }
    return [Math]::Round($Value, $Decimals).ToString($inv)
}

function ConvertTo-JsonText($Value, [System.IO.TextWriter]$Out) {
    # Small JSON writer for ordered records, writing to $Out. A StringBuilder value is inserted verbatim (pre-rendered series).
    if ($null -eq $Value) { $Out.Write('null'); return }
    if ($Value -is [System.Text.StringBuilder]) { $Out.Write($Value.ToString()); return }
    if ($Value -is [string]) { $Out.Write((Format-JsonString $Value)); return }
    if ($Value -is [bool]) { if ($Value) { $Out.Write('true') } else { $Out.Write('false') }; return }
    if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) { $Out.Write((Format-JsonNumber ([double]$Value) 3)); return }
    if ($Value -is [ValueType]) { $Out.Write(([IConvertible]$Value).ToString($inv)); return }
    if ($Value -is [System.Collections.IDictionary]) {
        $Out.Write('{')
        $first = $true
        foreach ($k in $Value.Keys) {
            if (-not $first) { $Out.Write(',') }
            $first = $false
            # plain keys, strings without special characters and whole numbers are written here, without a call per
            # value (one record per event: the writer runs this loop hundreds of thousands of times)
            $ks = [string]$k
            if ($script:JsonSpecial.IsMatch($ks)) { $Out.Write((Format-JsonString $ks)); $Out.Write(':') } else { $Out.Write('"' + $ks + '":') }
            $v = $Value[$k]
            if ($v -is [string] -and -not $script:JsonSpecial.IsMatch($v)) { $Out.Write('"' + $v + '"') }
            elseif ($v -is [int] -or $v -is [long]) { $Out.Write($v.ToString($inv)) }
            else { ConvertTo-JsonText $v $Out }
        }
        $Out.Write('}')
        return
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $Out.Write('[')
        $first = $true
        foreach ($v in $Value) {
            if (-not $first) { $Out.Write(',') }
            $first = $false
            ConvertTo-JsonText $v $Out
        }
        $Out.Write(']')
        return
    }
    $Out.Write((Format-JsonString ([string]$Value)))
}

function New-JsonSeries([double[]]$Values, [int]$Decimals, [int]$Start = 0, [int]$End = -1) {
    # JSON array of $Values[$Start..$End], rounded; NaN and infinity become null.
    if ($End -lt 0) { $End = $Values.Length - 1 }
    $sb = New-Object System.Text.StringBuilder (($End - $Start + 1) * 6 + 2)
    [void]$sb.Append('[')
    $pinf = [double]::PositiveInfinity; $ninf = [double]::NegativeInfinity
    for ($i = $Start; $i -le $End; $i++) {
        if ($i -gt $Start) { [void]$sb.Append(',') }
        $v = $Values[$i]
        if ($v -ne $v -or $v -eq $pinf -or $v -eq $ninf) { [void]$sb.Append('null') }
        else { [void]$sb.Append([Math]::Round($v, $Decimals).ToString($inv)) }
    }
    [void]$sb.Append(']')
    return $sb
}

function New-JsonIntegers($Values) {
    # JSON array of integer values (int[] or long[]).
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('[')
    $first = $true
    foreach ($v in $Values) {
        if (-not $first) { [void]$sb.Append(',') }
        $first = $false
        [void]$sb.Append(([long]$v).ToString($inv))
    }
    [void]$sb.Append(']')
    return $sb
}

function Get-Round($Value, [int]$Decimals) {
    # Rounded number, or $null for $null, NaN and infinity.
    if ($null -eq $Value) { return $null }
    $d = [double]$Value
    if ([double]::IsNaN($d) -or [double]::IsInfinity($d)) { return $null }
    return [Math]::Round($d, $Decimals)
}

function Get-Stats([double[]]$Values) {
    # avg / 95th percentile / max of the given values (NaN values must be removed by the caller)
    if ($Values.Length -eq 0) { return @{ Avg = $nan; P95 = $nan; Max = $nan } }
    $sorted = [double[]]$Values.Clone()
    [Array]::Sort($sorted)
    $sum = 0.0
    foreach ($v in $sorted) { $sum += $v }
    $idx = [int][Math]::Ceiling(0.95 * $sorted.Length) - 1
    if ($idx -lt 0) { $idx = 0 }
    return @{ Avg = $sum / $sorted.Length; P95 = $sorted[$idx]; Max = $sorted[$sorted.Length - 1] }
}

function Get-CleanStats([double[]]$Values) {
    $l = New-Object System.Collections.Generic.List[double]
    foreach ($v in $Values) { if ($v -eq $v -and -not [double]::IsInfinity($v)) { $l.Add($v) } }
    return Get-Stats $l.ToArray()
}

function Get-MetaValue([string]$Name) {
    # Optional meta.json field: $null when missing.
    return (Get-WorkerPerfField $model.Meta $Name)
}

function Get-EntitySummary($Entity) {
    # Statistics and snapshot-grid series of a group of processes (a session or an application), taken over the
    # snapshots in which the group had at least one living process.
    $cpuPct = New-WorkerPerfNanArray $nP; $wsMB = New-WorkerPerfNanArray $nP; $ioKBs = New-WorkerPerfNanArray $nP
    $present = 0; $cpuMs = 0.0; $io = 0.0; $nSum = 0; $nMax = 0
    $cpuL = New-Object System.Collections.Generic.List[double]
    $wsL = New-Object System.Collections.Generic.List[double]
    $privL = New-Object System.Collections.Generic.List[double]
    $n = $Entity.N; $cpuA = $Entity.CpuMs; $wsA = $Entity.Ws; $privA = $Entity.Priv; $ioA = $Entity.Io
    for ($i = 0; $i -lt $nP; $i++) {
        $cpuMs += $cpuA[$i]; $io += $ioA[$i]
        $c = $n[$i]
        if ($c -le 0) { continue }
        $present++; $nSum += $c
        if ($c -gt $nMax) { $nMax = $c }
        $pct = $cpuA[$i] * $capFactor[$i]
        $cpuPct[$i] = $pct; if ($pct -eq $pct) { $cpuL.Add($pct) }
        $wsMB[$i] = $wsA[$i] / 1024.0; $wsL.Add($wsMB[$i])
        $privL.Add($privA[$i] / 1024.0)
        if ($snapSecArr[$i] -gt 0) { $ioKBs[$i] = $ioA[$i] / 1024.0 / $snapSecArr[$i] }
    }
    $c = Get-Stats $cpuL.ToArray(); $w = Get-Stats $wsL.ToArray(); $p = Get-Stats $privL.ToArray()
    $nAvg = 0.0
    if ($present -gt 0) { $nAvg = $nSum / $present }
    return @{
        Present = $present; CpuMs = $cpuMs; IoBytes = $io
        CpuAvg = $c.Avg; CpuP95 = $c.P95; CpuMax = $c.Max
        WsAvg = $w.Avg; WsMax = $w.Max; PrivAvg = $p.Avg; PrivMax = $p.Max
        NAvg = $nAvg; NMax = $nMax
        Cpu = $cpuPct; Ws = $wsMB; Io = $ioKBs
    }
}

function Get-TopIndices([double[]]$Keys, [int[]]$Items, [int]$Count) {
    # The $Count items with the largest keys.
    $k = [double[]]$Keys.Clone(); $it = [int[]]$Items.Clone()
    [Array]::Sort($k, $it)
    $out = New-Object System.Collections.Generic.List[int]
    for ($i = $it.Length - 1; $i -ge 0 -and $out.Count -lt $Count; $i--) { $out.Add($it[$i]) }
    return , $out.ToArray()
}

#endregion

#region ---------- inputs -----------------------------------------------------------------

$timer = [Diagnostics.Stopwatch]::StartNew()
if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "Aufzeichnungsordner '$Path' nicht gefunden." }
$Path = (Resolve-Path -LiteralPath $Path).Path
if (-not $OutFile) { $OutFile = Join-Path $Path 'report.html' }
if (-not $ThresholdFile) { $ThresholdFile = Join-Path $PSScriptRoot 'thresholds.json' }
if (-not $RoleFile) { $RoleFile = Join-Path $PSScriptRoot 'roles.json' }
$templateFile = Join-Path $PSScriptRoot 'report-template.html'
if (-not (Test-Path -LiteralPath $templateFile)) { throw "Vorlage nicht gefunden: $templateFile" }
$OutFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
$outDir = Split-Path -Parent $OutFile
if ($outDir -and -not (Test-Path -LiteralPath $outDir -PathType Container)) { throw "Ausgabeordner '$outDir' nicht gefunden." }
if ($MaskMapFile) {
    if (-not $Mask) { throw '-MaskMapFile setzt -Mask voraus.' }
    $MaskMapFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($MaskMapFile)
    if ([string]::Equals([IO.Path]::GetFullPath($MaskMapFile), [IO.Path]::GetFullPath($OutFile), [StringComparison]::OrdinalIgnoreCase)) {
        throw '-MaskMapFile darf nicht die Berichtsdatei sein.'
    }
    # checked before the run, which writes the map only at its end; the capture is never changed, so the map must not
    # overwrite one of its files
    $maskMapDir = Split-Path -Parent $MaskMapFile
    if ($maskMapDir -and -not (Test-Path -LiteralPath $maskMapDir -PathType Container)) { throw "Ordner der Zuordnungsdatei '$maskMapDir' nicht gefunden." }
    $maskMapFull = [IO.Path]::GetFullPath($MaskMapFile)
    $maskCapture = [IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/')) + [IO.Path]::DirectorySeparatorChar
    if ([IO.File]::Exists($maskMapFull) -and $maskMapFull.StartsWith($maskCapture, [StringComparison]::OrdinalIgnoreCase)) {
        throw "-MaskMapFile nennt die Datei '$maskMapFull' der Aufzeichnung; die Aufzeichnung wird nie veraendert: bitte eine Datei ausserhalb des Aufzeichnungsordners waehlen."
    }
}
if ($Mask -eq 'Alles') {
    # the worker's name as meta.json gives it (as the reader takes it: meta.json, else the temporary file of the collector)
    $maskMetaPath = Join-Path $Path 'meta.json'
    if (-not (Test-Path -LiteralPath $maskMetaPath) -and (Test-Path -LiteralPath ($maskMetaPath + '.tmp'))) { $maskMetaPath = $maskMetaPath + '.tmp' }
    if (Test-Path -LiteralPath $maskMetaPath) {
        $maskWorker = [string](Get-WorkerPerfField (ConvertFrom-WorkerPerfJsonFile $maskMetaPath) 'Computer')
        if ($maskWorker -and (Split-Path -Leaf $OutFile).IndexOf($maskWorker, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw "Der Dateiname des Berichts nennt den Worker; bei -Mask Alles bitte einen anderen Namen waehlen."
        }
    }
}

$thresholds = Read-WorkerPerfThresholds $ThresholdFile
$roles = @(Read-WorkerPerfRoles $RoleFile)
$texts = Read-WorkerPerfTexts (Join-Path $PSScriptRoot 'texts.de.json')

Write-Host 'Lese Aufzeichnung ...'
$model = Import-WorkerPerfRun -Path $Path -From $From -To $To -Thresholds $thresholds -Roles $roles
$loadSec = $timer.Elapsed.TotalSeconds

Write-Host 'Bewerte Messwerte ...'
$series = @(Get-WorkerPerfSeries $model $thresholds)
$findings = @(Get-WorkerPerfFindings -Series $series -Thresholds $thresholds)
$incidents = @(Join-WorkerPerfIncidents -Findings $findings)
Add-WorkerPerfIncidentDetail -Incidents $incidents -Model $model -Thresholds $thresholds
# one result for the status of tiles and table rows (from the findings) and for what the texts call "nicht gemessen"
$sollIst = @(Get-WorkerPerfSollIst -Series $series -Thresholds $thresholds -Sources $model.Sources -Findings $findings)
$unmeasured = Get-WorkerPerfUnmeasured -SollIst $sollIst

#endregion

#region ---------- common values ----------------------------------------------------------

$tick = $model.Tick; $snap = $model.Snap
$nT = [int]$tick.N; $nP = [int]$snap.N
$cores = [int]$model.Meta.Cores
$offsetMin = [double]$model.Meta.OffsetMinutes
$fastSec = [double]$model.Meta.FastSec
$snapSecArr = [double[]]$snap.ElapsedSec
$capFactor = New-Object double[] $nP          # CPU ms -> % of the host capacity in the snapshot
for ($i = 0; $i -lt $nP; $i++) {
    $capMs = $snapSecArr[$i] * 1000.0 * $cores
    if ($capMs -gt 0) { $capFactor[$i] = 100.0 / $capMs } else { $capFactor[$i] = $nan }
}
$totalCpuMs = [double]$model.TotalCpuMs
$cpuShareBase = $totalCpuMs
if ($cpuShareBase -le 0) { $cpuShareBase = 1.0 }
$sessions = @($model.Sessions)
$procAll = @($model.Proc)
$validK = New-Object System.Collections.Generic.List[int]
for ($k = 0; $k -lt $procAll.Count; $k++) { if ($null -ne $procAll[$k]) { $validK.Add($k) } }

# focus: sessions of the reported user, reported time as epoch milliseconds
$focusSessions = New-Object System.Collections.Generic.List[int]
$focusUserOut = $null
if ($FocusUser) {
    $focusUserOut = $FocusUser
    foreach ($s in $sessions) {
        $u = [string]$s.User
        if ($u -eq '') { continue }
        if ($u -ieq $FocusUser -or ([string]$s.Domain + '\' + $u) -ieq $FocusUser) { $focusSessions.Add([int]$s.Index) }
    }
}
$reportedMs = $null
$reportedWallMs = $null
if ($PSBoundParameters.ContainsKey('ReportedTime')) {
    # wall-clock fields are the server's local time: read them as UTC and shift by the server's offset
    $wall = [DateTime]::SpecifyKind($ReportedTime, [DateTimeKind]::Utc)
    $reportedWallMs = (New-Object DateTimeOffset ($wall)).ToUnixTimeMilliseconds()
    $reportedMs = $reportedWallMs - [long][Math]::Round($offsetMin * 60000.0)
}
$focusRadiusMs = 15L * 60000L

# the user names of the focus sessions (found as User or Domain\User like above), for event records without a session
$focusNames = @{}
foreach ($s in $sessions) { if ($focusSessions.Contains([int]$s.Index)) { $focusNames[([string]$s.User).ToLowerInvariant()] = $true } }

function Test-FocusUser([string]$User) {
    # An event's account is the reported user when the reported user was found in a session and the account names the
    # same user: as User (events name no domain), or as Domain\User equal to -FocusUser.
    if ($focusNames.Count -eq 0 -or [string]::IsNullOrEmpty($User)) { return $false }
    $i = $User.LastIndexOf([char]'\')
    if ($i -ge 0) { return ($User -ieq $FocusUser) }
    return $focusNames.ContainsKey($User.ToLowerInvariant())
}

#endregion

#region ---------- events: incidents, lookback, print state -------------------------------

# Event incidents of the capture are numbered after the performance incidents, those of the lookback after them.
# Every record is matched against the reported time in UTC with the offset of its own day, that is against its own
# local time (Test-WorkerPerfEventNearWall); an ambiguous clock time at the end of daylight saving time meets the
# records of both readings, and without a daylight-saving change this is the reported time of the focus.
$eventConfig = Read-WorkerPerfEventConfig (Join-Path $PSScriptRoot 'events.json')
$eventSettings = Read-WorkerPerfEventSettings $ThresholdFile
$eventOffset = [int][Math]::Round($offsetMin)
$events = @($model.Events)
$printDrivers = @(@($model.PrintDrivers) | Where-Object { $null -ne $_ })
Set-WorkerPerfEventSessions -Events $events -Model $model -Config $eventConfig
$eventIncidents = @(New-WorkerPerfEventIncidents -Events $events -Config $eventConfig -Settings $eventSettings -Drivers $printDrivers -FirstId ($incidents.Count + 1))
Add-WorkerPerfEventPatterns -Incidents $eventIncidents -AllEvents $events -Model $model -Thresholds $thresholds -Settings $eventSettings -Config $eventConfig `
    -Roles $roles -Drivers $printDrivers -PerfIncidents $incidents
$lookback = Get-WorkerPerfLookback -Model $model -Config $eventConfig -Settings $eventSettings -Roles $roles -FirstId ($incidents.Count + $eventIncidents.Count + 1) -ReportedWallMs $reportedWallMs
$beforeIncidents = @($lookback.Incidents)
$printState = Get-WorkerPerfPrintState -Model $model -EventIncidents (@($eventIncidents) + @($beforeIncidents))

function ConvertTo-EventIncidentEntry($Incident) {
    # focus: with sessions, a session of the incident is a focus session (as for performance incidents); without
    # sessions (no session matched, the lookback), a person of the incident is the reported user. Near: the reported
    # clock time within 15 minutes of the incident's span in local time.
    $focus = $false
    $own = @($Incident.Sessions)
    if ($own.Count -gt 0) { foreach ($si in $own) { if ($focusSessions.Contains([int]$si)) { $focus = $true } } }
    else { foreach ($u in @($Incident.Users)) { if (Test-FocusUser ([string]$u)) { $focus = $true } } }
    $near = $false
    if ($null -ne $reportedWallMs) { $near = Test-WorkerPerfIncidentNearWall $Incident $reportedWallMs $eventOffset }
    $text = [string](Get-WorkerPerfEventIncidentText -Incident $Incident -Model $model -Texts $texts -Config $eventConfig -OffsetMinutes $eventOffset)
    return (ConvertTo-WorkerPerfEventIncidentOut -Incident $Incident -Text $text -Focus $focus -Near $near -Texts $texts -OffsetMinutes $eventOffset)
}

#endregion

#region ---------- meta, quality, thresholds ----------------------------------------------

Write-Host 'Berechne Kennzahlen ...'
# highest number of concurrent user sessions (session 0 excluded)
$userDelta = New-Object int[] ($nP + 1)
foreach ($s in $sessions) {
    if ([int]$s.Sid -eq 0 -or [int]$s.FirstP -lt 0) { continue }
    $userDelta[[int]$s.FirstP]++; $userDelta[[int]$s.LastP + 1]--
}
$cur = 0; $maxUsers = 0
for ($i = 0; $i -lt $nP; $i++) { $cur += $userDelta[$i]; if ($cur -gt $maxUsers) { $maxUsers = $cur } }
$usersPerCore = $null
if ($cores -gt 0) { $usersPerCore = [Math]::Round($maxUsers / [double]$cores, 3) }

$durationSec = 0.0
foreach ($e in $tick.ElapsedSec) { if ($e -eq $e) { $durationSec += $e } }

$simulated = Get-MetaValue 'Simulated'
if ($null -ne $simulated) { $simulated = [bool]$simulated }
$endReason = Get-MetaValue 'EndReason'
if ($null -ne $endReason) { $endReason = [string]$endReason }
$endMessage = Get-MetaValue 'EndMessage'
if ($null -ne $endMessage) { $endMessage = [string]$endMessage }
$ramGB = $null
if ([double]$model.Meta.RamMB -gt 0) { $ramGB = [Math]::Round([double]$model.Meta.RamMB / 1024.0, 1) }

$focusOut = [ordered]@{ user = $focusUserOut; found = ($focusSessions.Count -gt 0); sessions = $focusSessions.ToArray(); reportedMs = $reportedMs }
$meta = [ordered]@{
    computer = (Get-MetaValue 'Computer'); os = (Get-MetaValue 'OS'); cores = $cores; ramGB = $ramGB
    start = [long]$tick.TimeMs[0]; end = [long]$tick.TimeMs[$nT - 1]; offsetMin = $offsetMin
    fastSec = $fastSec; snapSec = [double]$model.Meta.SnapSec; durationMin = [Math]::Round($durationSec / 60.0, 2)
    ticks = $nT; snapshots = $nP; simulated = $simulated; endReason = $endReason; endMessage = $endMessage; usersPerCore = $usersPerCore
    processRows = $model.Rows.K.Length; processCount = $validK.Count; totalCpuSec = [Math]::Round($totalCpuMs / 1000.0, 1)
    generated = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    focus = $focusOut
}

$skippedTicks = 0
foreach ($e in $tick.ElapsedSec) { if ($e -gt 1.5 * $fastSec) { $skippedTicks++ } }
$tickMsSt = Get-CleanStats ([double[]]$tick.CollectMs)
$snapMsSt = Get-CleanStats ([double[]]$snap.CollectMs)
# burst mode: its duration from the tick flags; the spacing of the burst snapshots as measured (median)
$burstSnapshots = 0
$burstGaps = New-Object System.Collections.Generic.List[double]
for ($i = 0; $i -lt $nP; $i++) {
    if ($snap.Kind[$i] -ne 'B') { continue }
    $burstSnapshots++
    if ($snapSecArr[$i] -gt 0) { $burstGaps.Add($snapSecArr[$i]) }
}
$burstSnapSec = $null
if ($burstGaps.Count -gt 0) { $g = $burstGaps.ToArray(); [Array]::Sort($g); $burstSnapSec = [Math]::Round($g[[int][Math]::Floor(($g.Length - 1) / 2)], 1) }
$burstTicks = 0; $burstTickSec = 0.0
for ($i = 0; $i -lt $nT; $i++) {
    if (-not $tick.Burst[$i]) { continue }
    $burstTicks++
    $e = $tick.ElapsedSec[$i]
    if ($e -gt 0) { $burstTickSec += $e }
}
$collectorMs = 0.0; $collectorMax = $null
foreach ($k in $validK) {
    $pr = $procAll[$k]
    if (-not $pr.IsCollector) { continue }
    $collectorMs += [double]$pr.CpuMs
    if ($null -eq $collectorMax -or [double]$pr.CpuMaxPct -gt $collectorMax) { $collectorMax = [double]$pr.CpuMaxPct }
}
$collectorPct = $null
if ($totalCpuMs -gt 0) { $collectorPct = [Math]::Round(100.0 * $collectorMs / $totalCpuMs, 2) }
$burstSec = Get-MetaValue 'BurstIntervalSeconds'
if ($null -ne $burstSec) { $burstSec = [double]$burstSec }

$thOrder = @($thresholds.Keys)
$sourceIds = @($model.Sources.Keys | Sort-Object -Property @{ Expression = { $ix = [array]::IndexOf($thOrder, $_); if ($ix -lt 0) { 1000 } else { $ix } } }, @{ Expression = { $_ } })
$sourcesOut = New-Object System.Collections.Generic.List[object]
foreach ($id in $sourceIds) {
    $src = $model.Sources[$id]
    # signals take the threshold's label, other sources their text; an unknown id stays as it is
    $label = [string]$id
    if ($thresholds.Contains($id)) { $label = [string]$thresholds[$id].label }
    elseif ($texts.ContainsKey('source.' + $id)) { $label = $texts['source.' + $id] }
    $sourcesOut.Add([ordered]@{ id = [string]$id; label = $label; available = [bool]$src.Available; detail = [string]$src.Detail
            readFailed = [bool](Get-WorkerPerfField $src 'ReadFailed'); lookbackRead = [bool](Get-WorkerPerfField $src 'LookbackRead') })
}
# failed source calls of the capture: the source's text, else its key; a log booked on its own ('events.<log id>',
# 'eventsbefore.<log id>', M13) by the call's text and the log's
$sourceErrorsOut = New-Object System.Collections.Generic.List[object]
foreach ($e in @($model.SourceErrors | Sort-Object -Property @{ Expression = { $_.Source } })) {
    $label = [string]$e.Source
    $cut = $label.IndexOf([char]'.')
    if ($texts.ContainsKey('sourcecall.' + $label)) { $label = $texts['sourcecall.' + $label] }
    elseif ($cut -gt 0 -and $texts.ContainsKey('source.events.' + $label.Substring($cut + 1))) {
        $call = $label.Substring(0, $cut); $log = $texts['source.events.' + $label.Substring($cut + 1)]
        if ($call -eq 'events') { $label = $log }
        elseif ($texts.ContainsKey('sourcecall.' + $call)) { $label = $texts['sourcecall.' + $call] + ' ' + [char]0x2013 + ' ' + $log }
    }
    $sourceErrorsOut.Add([ordered]@{ source = [string]$e.Source; label = $label; count = [int]$e.Count; firstMs = $e.FirstMs; firstMessage = [string]$e.FirstMessage })
}
# the counters of the event reads per log (I5): only logs with a number above zero, numbers and the log's label
function ConvertTo-ReadCountsOut($Counts, [switch]$WithDropped) {
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($id in @($Counts.Keys)) {
        $c = $Counts[$id]
        $dropped = $(if ($WithDropped) { [long]$c.Dropped } else { [long]0 })
        if ($dropped -le 0 -and [long]$c.Skipped -le 0 -and [long]$c.Unformatted -le 0) { continue }
        $label = [string]$id
        if ($texts.ContainsKey('source.events.' + $id)) { $label = [string]$texts['source.events.' + $id] }
        $row = [ordered]@{ log = [string]$id; label = $label }
        if ($WithDropped) { $row['dropped'] = $dropped }
        $row['skipped'] = [long]$c.Skipped; $row['unformatted'] = [long]$c.Unformatted
        $list.Add($row)
    }
    return , $list.ToArray()
}
# EventReadCounts counts the lookback and the capture together, LookbackReadCounts the lookback alone: the capture's own
# counters are the difference per log and counter, never below zero (a capture without LookbackReadCounts keeps its own).
# Without Ereignisse the capture read no events: no counter of the capture is shown (skipped names the reason).
$captureReads = [ordered]@{}
if (@($model.Skip) -notcontains 'Ereignisse') {
    $lookbackReads = $model.Meta['LookbackReadCounts']
    foreach ($id in @($model.Meta['EventReadCounts'].Keys)) {
        $c = $model.Meta['EventReadCounts'][$id]; $own = @{}
        foreach ($k in 'Dropped', 'Skipped', 'Unformatted') {
            $n = [long]$c[$k]
            if ($lookbackReads.Contains($id)) { $n = [Math]::Max([long]0, $n - [long]$lookbackReads[$id][$k]) }
            $own[$k] = $n
        }
        $captureReads[$id] = $own
    }
}
$eventReadsOut = ConvertTo-ReadCountsOut $captureReads -WithDropped
$quality = [ordered]@{
    skippedTicks = $skippedTicks
    tickMsAvg = (Get-Round $tickMsSt.Avg 1); tickMsMax = (Get-Round $tickMsSt.Max 1)
    snapMsAvg = (Get-Round $snapMsSt.Avg 1); snapMsMax = (Get-Round $snapMsSt.Max 1)
    burstSec = $burstSec; burstSnapshots = $burstSnapshots; burstSnapSec = $burstSnapSec
    burstTicks = $burstTicks; burstMin = [Math]::Round($burstTickSec / 60.0, 2)
    collectorCpuPct = $collectorPct; collectorCpuMaxPct = (Get-Round $collectorMax 2)
    unreadable = [ordered]@{ ticks = [int]$model.Unreadable.Ticks; snapshots = [int]$model.Unreadable.Snapshots
        events = [int]$model.Unreadable.Events; eventsBefore = [int]$model.Unreadable.EventsBefore
        printDrivers = [int]$model.Unreadable.PrintDrivers; printQueues = [int]$model.Unreadable.PrintQueues }
    sourceErrors = $sourceErrorsOut.ToArray()
    sources = $sourcesOut.ToArray()
    eventReads = $eventReadsOut
}

$thresholdsOut = New-Object System.Collections.Generic.List[object]
foreach ($th in $thresholds.Values) {
    $thresholdsOut.Add([ordered]@{
            id = [string]$th.id; label = [string]$th.label; unit = [string]$th.unit; warn = [double]$th.warn; crit = [double]$th.crit
            ideal = [string]$th.ideal; origin = [string]$th.origin; source = [string]$th.source; url = [string]$th.url; note = [string]$th.note
            direction = [string]$th.direction
        })
}

#endregion

#region ---------- host series, volumes, shares, probes, events ---------------------------

$raw = $tick.Raw; $sig = $tick.Signal
$memUsedGB = New-Object double[] $nT; $commitGB = New-Object double[] $nT; $burst = New-Object double[] $nT
$diskR = New-Object double[] $nT; $diskW = New-Object double[] $nT; $netR = New-Object double[] $nT; $netS = New-Object double[] $nT
$inputMax = New-Object double[] $nT
$ramMb = [double]$model.Meta.RamMB
for ($i = 0; $i -lt $nT; $i++) {
    if ($ramMb -gt 0) { $memUsedGB[$i] = ($ramMb - $raw['MemAvailMB'][$i]) / 1024.0 } else { $memUsedGB[$i] = $nan }
    $commitGB[$i] = $raw['MemCommittedMB'][$i] / 1024.0
    $diskR[$i] = $raw['DiskReadBps'][$i] / 1024.0; $diskW[$i] = $raw['DiskWriteBps'][$i] / 1024.0
    $netR[$i] = $raw['NetRecvBps'][$i] / 1024.0; $netS[$i] = $raw['NetSentBps'][$i] / 1024.0
    if ($tick.Burst[$i]) { $burst[$i] = 1 }
}
foreach ($s in $sessions) {
    $in = $s.Input
    for ($i = 0; $i -lt $nT; $i++) { if ($in[$i] -gt $inputMax[$i]) { $inputMax[$i] = $in[$i] } }
}
$hostOut = [ordered]@{
    cpu = (New-JsonSeries $sig['cpu.host'] 2); queue = (New-JsonSeries $sig['cpu.queue'] 2); steal = (New-JsonSeries $sig['cpu.steal'] 2)
    memUsedPct = (New-JsonSeries $sig['mem.used'] 1); memUsedGB = (New-JsonSeries $memUsedGB 2)
    commitPct = (New-JsonSeries $sig['mem.commit'] 1); commitGB = (New-JsonSeries $commitGB 2); pagesIn = (New-JsonSeries $sig['mem.pagesin'] 1)
    inputMax = (New-JsonSeries $inputMax 1)
    diskR = (New-JsonSeries $diskR 1); diskW = (New-JsonSeries $diskW 1)
    iopsR = (New-JsonSeries $raw['DiskReadIops'] 1); iopsW = (New-JsonSeries $raw['DiskWriteIops'] 1)
    netR = (New-JsonSeries $netR 1); netS = (New-JsonSeries $netS 1); burst = (New-JsonSeries $burst 0)
    sessions = (New-JsonSeries ([double[]]$snap.Sessions) 0); active = (New-JsonSeries ([double[]]$snap.ActiveSessions) 0)
    procs = (New-JsonSeries ([double[]]$snap.Processes) 0)
}

function New-IoEntry($Item) {
    # tick positions with a row (a latency or operations), with latency and operations
    $t = New-Object System.Collections.Generic.List[int]
    $ms = New-Object System.Collections.Generic.List[double]
    $ops = New-Object System.Collections.Generic.List[double]
    $rd = $Item.ReadMs; $wr = $Item.WriteMs; $lat = $Item.Latency; $op = $Item.Ops
    for ($i = 0; $i -lt $nT; $i++) {
        if ($rd[$i] -ne $rd[$i] -and $wr[$i] -ne $wr[$i] -and -not ($op[$i] -gt 0)) { continue }
        $t.Add($i); $ms.Add($lat[$i]); $ops.Add($op[$i])
    }
    return @{ T = (New-JsonIntegers $t); Ms = (New-JsonSeries $ms.ToArray() 1); Ops = (New-JsonSeries $ops.ToArray() 1) }
}
$volumesOut = New-Object System.Collections.Generic.List[object]
foreach ($v in @($model.Volumes)) {
    $io = New-IoEntry $v
    $volumesOut.Add([ordered]@{ name = [string]$v.Name; label = [string]$v.Label; kind = [string]$v.Kind; s = [int]$v.SessionIndex; backing = [string]$v.Backing; t = $io.T; ms = $io.Ms; ops = $io.Ops })
}
$sharesOut = New-Object System.Collections.Generic.List[object]
foreach ($v in @($model.Shares)) {
    $io = New-IoEntry $v
    $sharesOut.Add([ordered]@{ name = [string]$v.Name; label = [string]$v.Label; t = $io.T; ms = $io.Ms; ops = $io.Ops })
}
$probesOut = New-Object System.Collections.Generic.List[object]
foreach ($pb in @($model.Probes)) {
    $failed = New-Object bool[] $nP
    for ($i = 0; $i -lt $nP; $i++) { $failed[$i] = -not [string]::IsNullOrEmpty([string]$pb.Error[$i]) }
    $probesOut.Add([ordered]@{ name = [string]$pb.Name; role = [string]$pb.Role; host = [string]$pb.Host; port = [int]$pb.Port; ms = (New-JsonSeries ([double[]]$pb.Ms) 1); failed = $failed })
}
$mainAppOut = $null
if ($null -ne $model.MainApp) {
    $t = New-Object System.Collections.Generic.List[int]; $ms = New-Object System.Collections.Generic.List[double]
    $d = $model.MainApp.Delay
    for ($i = 0; $i -lt $nT; $i++) { if ($d[$i] -gt 0) { $t.Add($i); $ms.Add($d[$i]) } }
    # status like every tile: from the findings the delay series of the main application forms under the input-delay threshold
    $mainStatus = 0
    if ($thresholds.Contains('input.session')) {
        $mainSeries = @{ Id = 'input.session'; Resource = 'input'; Scope = 'global'; Instance = ''; Label = [string]$model.MainApp.Label; SessionIndex = -1
            TimeMs = $tick.TimeMs; ElapsedSec = $tick.ElapsedSec; Value = $d; Ops = $null }
        foreach ($f in @(Get-WorkerPerfFindings -Series @($mainSeries) -Thresholds $thresholds)) { if ([int]$f.Severity -gt $mainStatus) { $mainStatus = [int]$f.Severity } }
    }
    $mainAppOut = [ordered]@{ label = [string]$model.MainApp.Label; status = $mainStatus; t = (New-JsonIntegers $t); ms = (New-JsonSeries $ms.ToArray() 1) }
}
# every event of the capture; the session events of each session as positions in this list
$eventsOut = New-Object System.Collections.Generic.List[object]
$sessionEvents = @{}
foreach ($e in $events) {
    $si = [int](Get-WorkerPerfField $e 'SessionIndex')
    if ([string]$e.Group -eq 'session' -and $si -ge 0) {
        if (-not $sessionEvents.ContainsKey($si)) { $sessionEvents[$si] = New-Object System.Collections.Generic.List[int] }
        $sessionEvents[$si].Add($eventsOut.Count)
    }
    $eventsOut.Add((ConvertTo-WorkerPerfEventOut $e $eventOffset))
}

#endregion

#region ---------- sessions, applications, pairs ------------------------------------------

$inputTh = $null
if ($thresholds.Contains('input.session')) { $inputTh = $thresholds['input.session'] }
$sessOut = New-Object System.Collections.Generic.List[object]
foreach ($s in $sessions) {
    $sum = Get-EntitySummary $s
    $firstP = [int]$s.FirstP; $lastP = [int]$s.LastP
    for ($i = 0; $i -lt $nP; $i++) { if ($s.N[$i] -gt 0) { if ($firstP -lt 0 -or $i -lt $firstP) { $firstP = $i }; break } }
    for ($i = $nP - 1; $i -ge 0; $i--) { if ($s.N[$i] -gt 0) { if ($i -gt $lastP) { $lastP = $i }; break } }
    $first = $null; $last = $null; $durMin = $null
    if ($firstP -ge 0) {
        $first = [long]$snap.TimeMs[$firstP]; $last = [long]$snap.TimeMs[$lastP]
        $durSec = 0.0
        for ($i = $firstP; $i -le $lastP; $i++) { $durSec += $snapSecArr[$i] }
        $durMin = [Math]::Round($durSec / 60.0, 2)
    }
    # input delay: rows with a value; the share of "auffaellig" ticks is taken over the session's lifetime
    $in = $s.Input
    $inT = New-Object System.Collections.Generic.List[int]; $inMs = New-Object System.Collections.Generic.List[double]
    for ($i = 0; $i -lt $nT; $i++) { if ($in[$i] -gt 0) { $inT.Add($i); $inMs.Add($in[$i]) } }
    $inSt = Get-Stats $inMs.ToArray()
    $inWarnPct = $null
    if ($null -ne $inputTh) {
        $t0 = 0; $t1 = $nT - 1
        if ($firstP -ge 0) {
            if ($firstP -gt 0) { $t0 = [int]$snap.TickPos[$firstP - 1] + 1 }
            $t1 = [int]$snap.TickPos[$lastP]
        }
        $warnN = 0; $allN = 0
        if ($firstP -ge 0) {
            for ($i = $t0; $i -le $t1; $i++) { $allN++; if ($in[$i] -ge [double]$inputTh.warn) { $warnN++ } }
        }
        else {
            foreach ($v in $inMs) { $allN++; if ($v -ge [double]$inputTh.warn) { $warnN++ } }
        }
        if ($allN -gt 0) { $inWarnPct = [Math]::Round(100.0 * $warnN / $allN, 1) }
    }
    $rttSt = Get-CleanStats ([double[]]$s.Rtt)
    $activePct = $null
    if ([int]$s.SeenN -gt 0) { $activePct = [Math]::Round(100.0 * [int]$s.ActiveN / [int]$s.SeenN, 1) }
    $idleMaxMin = $null
    if ([double]$s.IdleMaxSec -eq [double]$s.IdleMaxSec) { $idleMaxMin = [Math]::Round([double]$s.IdleMaxSec / 60.0, 1) }
    $profileVolume = $null
    if ([int]$s.ProfileVolume -ge 0) { $profileVolume = [int]$s.ProfileVolume }
    $logon = $null
    if ($null -ne $s.Logon) { $logon = [long]$s.Logon }
    $ownEvents = [int[]]@()
    if ($sessionEvents.ContainsKey([int]$s.Index)) { $ownEvents = $sessionEvents[[int]$s.Index].ToArray() }
    $sessOut.Add([ordered]@{
            i = [int]$s.Index; id = [int]$s.Sid; user = [string]$s.User; domain = [string]$s.Domain; client = [string]$s.Client; logon = $logon
            first = $first; last = $last; durMin = $durMin; activePct = $activePct; idleMaxMin = $idleMaxMin
            cpuSec = [Math]::Round($sum.CpuMs / 1000.0, 1); cpuShare = [Math]::Round(100.0 * $sum.CpuMs / $cpuShareBase, 2)
            cpuAvg = (Get-Round $sum.CpuAvg 2); cpuP95 = (Get-Round $sum.CpuP95 2); cpuMax = (Get-Round $sum.CpuMax 2)
            wsAvg = (Get-Round $sum.WsAvg 0); wsMax = (Get-Round $sum.WsMax 0); privAvg = (Get-Round $sum.PrivAvg 0); privMax = (Get-Round $sum.PrivMax 0)
            ioMB = [Math]::Round($sum.IoBytes / 1MB, 1); procsAvg = [Math]::Round($sum.NAvg, 1); procsMax = $sum.NMax
            rttAvg = (Get-Round $rttSt.Avg 1); rttP95 = (Get-Round $rttSt.P95 1); rttMax = (Get-Round $rttSt.Max 1)
            inP95 = (Get-Round $inSt.P95 1); inMax = (Get-Round $inSt.Max 1); inWarnPct = $inWarnPct; profileVolume = $profileVolume
            cpu = (New-JsonSeries $sum.Cpu 2); ws = (New-JsonSeries $sum.Ws 0); io = (New-JsonSeries $sum.Io 1); rtt = (New-JsonSeries ([double[]]$s.Rtt) 1)
            inT = (New-JsonIntegers $inT); inMs = (New-JsonSeries $inMs.ToArray() 1); events = $ownEvents
        })
}

$pairKeys = @($model.Pairs.Keys | Sort-Object -Property @{ Expression = { [int]$model.Pairs[$_].S } }, @{ Expression = { [int]$model.Pairs[$_].A } })
$appSessions = @{}
$pairsOut = New-Object System.Collections.Generic.List[object]
foreach ($key in $pairKeys) {
    $pr = $model.Pairs[$key]
    $a = [int]$pr.A
    if ($appSessions.ContainsKey($a)) { $appSessions[$a]++ } else { $appSessions[$a] = 1 }
    $wsAvg = 0.0
    if ([int]$pr.Snaps -gt 0) { $wsAvg = [double]$pr.WsSumKB / [int]$pr.Snaps / 1024.0 }
    $pairsOut.Add([ordered]@{
            s = [int]$pr.S; a = $a; inst = [int]$pr.Instances; cpuSec = [Math]::Round([double]$pr.CpuMs / 1000.0, 1)
            wsAvg = [Math]::Round($wsAvg, 0); wsMax = [Math]::Round([double]$pr.WsMaxKB / 1024.0, 0); ioMB = [Math]::Round([double]$pr.IoBytes / 1MB, 1)
        })
}

$appsOut = New-Object System.Collections.Generic.List[object]
foreach ($a in @($model.Apps)) {
    $sum = Get-EntitySummary $a
    $cpuShare = 100.0 * $sum.CpuMs / $cpuShareBase
    $wsMax = $sum.WsMax
    $withSeries = ($cpuShare -ge 0.1) -or ($wsMax -ge 50)
    $wsPerInst = $null
    if ($sum.NAvg -gt 0) { $wsPerInst = Get-Round ($sum.WsAvg / $sum.NAvg) 0 }
    $sessCount = 0
    if ($appSessions.ContainsKey([int]$a.Index)) { $sessCount = [int]$appSessions[[int]$a.Index] }
    $cpuS = $null; $wsS = $null
    if ($withSeries) { $cpuS = New-JsonSeries $sum.Cpu 2; $wsS = New-JsonSeries $sum.Ws 0 }
    $appsOut.Add([ordered]@{
            i = [int]$a.Index; name = [string]$a.Name; role = [string]$a.Role; roleLabel = [string]$a.RoleLabel; path = [string]$a.Path
            inst = [int]$a.Instances; sess = $sessCount; instAvg = [Math]::Round($sum.NAvg, 1); instMax = $sum.NMax
            cpuSec = [Math]::Round($sum.CpuMs / 1000.0, 1); cpuShare = [Math]::Round($cpuShare, 2)
            cpuAvg = (Get-Round $sum.CpuAvg 2); cpuP95 = (Get-Round $sum.CpuP95 2); cpuMax = (Get-Round $sum.CpuMax 2)
            wsAvg = (Get-Round $sum.WsAvg 0); wsMax = (Get-Round $wsMax 0); privMax = (Get-Round $sum.PrivMax 0); wsPerInst = $wsPerInst
            ioMB = [Math]::Round($sum.IoBytes / 1MB, 1); cpu = $cpuS; ws = $wsS
        })
}

#endregion

#region ---------- incidents --------------------------------------------------------------

$workerOrder = @('cpu', 'memory', 'disk', 'share', 'profile')
function ConvertTo-MainEntry($Main, [string]$Resource) {
    if ($null -eq $Main) { return $null }
    return [ordered]@{
        resource = $Resource; app = [string]$Main.App; a = [int]$Main.AppIndex; s = [int]$Main.SessionIndex; user = [string]$Main.User
        sharePct = (Get-Round $Main.SharePct 1); baselinePct = (Get-Round $Main.BaselinePct 1); growthMB = (Get-Round $Main.GrowthMB 1)
    }
}
$rankedK = @{}
$incOut = New-Object System.Collections.Generic.List[object]
foreach ($inc in $incidents) {
    $start = [long]$inc.StartMs; $end = [long]$inc.EndMs
    $signals = New-Object System.Collections.Generic.List[object]
    $own = @{}
    foreach ($f in @($inc.Findings)) {
        $sid = [string]$f.SignalId
        $unit = ''; $ideal = ''
        if ($thresholds.Contains($sid)) { $unit = [string]$thresholds[$sid].unit; $ideal = [string]$thresholds[$sid].ideal }
        if ([string]$f.Scope -eq 'session') { $own[[int]$f.SessionIndex] = $true }
        $signals.Add([ordered]@{
                id = $sid; label = [string]$f.Label; resource = [string]$f.Resource; instance = [string]$f.Instance; s = [int]$f.SessionIndex
                peak = (Get-Round $f.PeakValue 2); unit = $unit; ideal = $ideal; severity = [int]$f.Severity; start = [long]$f.StartMs; end = [long]$f.EndMs
            })
    }
    $affected = New-Object System.Collections.Generic.List[object]
    $focus = $false
    foreach ($x in @($inc.Affected)) {
        $affected.Add([ordered]@{ s = [int]$x.SessionIndex; peakMs = (Get-Round $x.PeakMs 1) })
        if ($focusSessions.Contains([int]$x.SessionIndex)) { $focus = $true }
    }
    foreach ($si in $own.Keys) { if ($focusSessions.Contains([int]$si)) { $focus = $true } }
    $near = $false
    if ($null -ne $reportedMs) { $near = ($reportedMs -ge ($start - $focusRadiusMs) -and $reportedMs -le ($end + $focusRadiusMs)) }

    $contrib = [ordered]@{}
    $main = $null
    $resKeys = @($inc.Contributors.Keys | Sort-Object -Property @{ Expression = { $ix = [array]::IndexOf($workerOrder, $_); if ($ix -lt 0) { 1000 } else { $ix } } }, @{ Expression = { $_ } })
    foreach ($r in $resKeys) {
        $rank = $inc.Contributors[$r]
        $procs = New-Object System.Collections.Generic.List[object]
        foreach ($p in @($rank.Processes)) {
            $rankedK[[int]$p.K] = $true
            $procs.Add([ordered]@{
                    k = [int]$p.K; name = [string]$p.Name; pid = [int]$p.Pid; s = [int]$p.SessionIndex
                    sharePct = (Get-Round $p.SharePct 1); baselinePct = (Get-Round $p.BaselinePct 1); growthMB = (Get-Round $p.GrowthMB 1)
                    role = [string]$p.Role; roleLabel = [string]$p.RoleLabel; isCollector = [bool]$p.IsCollector
                })
        }
        $apps = New-Object System.Collections.Generic.List[object]
        foreach ($p in @($rank.Apps)) { $apps.Add([ordered]@{ a = [int]$p.AppIndex; name = [string]$p.Name; sharePct = (Get-Round $p.SharePct 1); baselinePct = (Get-Round $p.BaselinePct 1) }) }
        $sess = New-Object System.Collections.Generic.List[object]
        foreach ($p in @($rank.Sessions)) { $sess.Add([ordered]@{ s = [int]$p.SessionIndex; user = [string]$p.User; sharePct = (Get-Round $p.SharePct 1); baselinePct = (Get-Round $p.BaselinePct 1) }) }
        $contrib[[string]$r] = [ordered]@{ measure = [string]$rank.Measure; scope = [string]$rank.Scope; procs = $procs.ToArray(); apps = $apps.ToArray(); sessions = $sess.ToArray() }
    }
    # what the text says about the cause of an 'engpass', for the page: main (the main cause) only when the text names one
    $cause = $null
    if ($null -ne $inc.Cause) {
        $c = $inc.Cause
        $causeSec = $null; $causeOther = $null
        if ([string]$c.Kind -eq 'main') { $main = ConvertTo-MainEntry $c.Main ([string]$c.Resource) }
        elseif ([string]$c.Kind -eq 'security') {
            $causeSec = [ordered]@{ label = [string]$c.Security.Label; sharePct = (Get-Round $c.Security.SharePct 1) }
            $causeOther = ConvertTo-MainEntry $c.Main ([string]$c.Resource)
        }
        $cause = [ordered]@{
            kind = [string]$c.Kind; resource = [string]$c.Resource; measure = [string]$c.Measure; scope = [string]$c.Scope
            minSharePct = [double]$c.MinSharePct; scan = [bool]$c.Scan; security = $causeSec; other = $causeOther
        }
    }
    $delayProcs = New-Object System.Collections.Generic.List[object]
    foreach ($p in @($inc.DelayProcesses)) {
        if ([int]$p.K -ge 0) { $rankedK[[int]$p.K] = $true }
        $delayProcs.Add([ordered]@{ name = [string]$p.Name; pid = [int]$p.Pid; k = [int]$p.K; s = [int]$p.SessionIndex; maxMs = (Get-Round $p.MaxMs 1); role = [string]$p.Role })
    }
    $endpoints = New-Object System.Collections.Generic.List[object]
    foreach ($p in @($inc.Endpoints)) { $endpoints.Add([ordered]@{ name = [string]$p.Name; role = [string]$p.Role; maxMs = (Get-Round $p.MaxMs 1); failed = [bool]$p.Failed }) }
    $ica = New-Object System.Collections.Generic.List[object]
    foreach ($p in @($inc.Ica)) { $ica.Add([ordered]@{ s = [int]$p.SessionIndex; maxMs = (Get-Round $p.MaxMs 1) }) }
    $products = New-Object System.Collections.Generic.List[object]
    foreach ($p in @($inc.Security.Products)) { $products.Add([ordered]@{ label = [string]$p.Label; sharePct = (Get-Round $p.SharePct 1) }) }
    $companion = $null
    if ($null -ne $inc.Companion) {
        $c = $inc.Companion
        $companion = [ordered]@{
            label = [string]$c.Label; sharePct = (Get-Round $c.SharePct 1); resource = [string]$c.Resource
            topIoApp = [string]$c.TopIoApp; topIoUser = [string]$c.TopIoUser; topIoS = [int]$c.TopIoSessionIndex
        }
    }
    $context = New-Object System.Collections.Generic.List[object]
    foreach ($c in @($inc.ChronicContext)) {
        $context.Add([ordered]@{
                incidentId = [int]$c.IncidentId; signalId = [string]$c.SignalId; label = [string]$c.Label; severity = [int]$c.Severity
                explains = [bool]$c.Explains; resource = [string](Get-WorkerPerfField $c 'Resource')
            })
    }
    $incEvents = New-Object System.Collections.Generic.List[object]
    foreach ($e in @($inc.Events)) { $incEvents.Add((ConvertTo-WorkerPerfEventOut $e $eventOffset)) }
    $lead = $null
    if ($null -ne $inc.Lead) { $lead = [string]$inc.Lead }
    # the event incidents of the capture that overlap this one (set by Add-WorkerPerfEventPatterns)
    $eventRefs = [int[]]@()
    $refs = Get-WorkerPerfField $inc 'EventIncidents'
    if ($null -ne $refs) { $eventRefs = [int[]]@($refs) }
    $incOut.Add([ordered]@{
            id = [int]$inc.Id; type = [string]$inc.Type; chronic = [bool]$inc.Chronic; severity = [int]$inc.Severity
            start = $start; end = $end; durSec = [Math]::Round(($end - $start) / 1000.0, 1); lead = $lead; resources = [string[]]@($inc.Resources)
            text = [string](Get-WorkerPerfIncidentText -Incident $inc -Model $model -Thresholds $thresholds -Texts $texts -Unmeasured $unmeasured)
            focus = $focus; nearReported = $near; scanActive = [bool]$inc.ScanActive; events = $incEvents.ToArray()
            signals = $signals.ToArray(); affected = $affected.ToArray(); main = $main; cause = $cause; contributors = $contrib
            delayProcs = $delayProcs.ToArray(); endpoints = $endpoints.ToArray(); ica = $ica.ToArray()
            security = [ordered]@{ products = $products.ToArray(); totalPct = (Get-Round $inc.Security.TotalPct 1) }
            companion = $companion; chronicContext = $context.ToArray()
            eventIncidents = $eventRefs; event = $null
        })
}
foreach ($inc in $eventIncidents) { $incOut.Add((ConvertTo-EventIncidentEntry $inc)) }

#endregion

#region ---------- processes --------------------------------------------------------------

$selected = @{}
if ($validK.Count -gt 0) {
    $ks = $validK.ToArray()
    $cpuKey = New-Object double[] $ks.Length; $wsKey = New-Object double[] $ks.Length; $ioKey = New-Object double[] $ks.Length
    for ($i = 0; $i -lt $ks.Length; $i++) {
        $pr = $procAll[$ks[$i]]
        $cpuKey[$i] = [double]$pr.CpuMs; $wsKey[$i] = [double]$pr.WsMaxKB; $ioKey[$i] = [double]$pr.IoBytes
    }
    foreach ($k in (Get-TopIndices $cpuKey $ks $TopProcesses)) { $selected[$k] = $true }
    foreach ($k in (Get-TopIndices $wsKey $ks $TopProcesses)) { $selected[$k] = $true }
    foreach ($k in (Get-TopIndices $ioKey $ks ([int]($TopProcesses / 3)))) { $selected[$k] = $true }
    # the heaviest processes of every session, so each session detail view is meaningful
    $bySession = @{}
    for ($i = 0; $i -lt $ks.Length; $i++) {
        $si = [int]$procAll[$ks[$i]].SessionIndex
        if (-not $bySession.ContainsKey($si)) { $bySession[$si] = New-Object System.Collections.Generic.List[int] }
        $bySession[$si].Add($i)
    }
    foreach ($list in $bySession.Values) {
        $pos = $list.ToArray()
        $sk = New-Object int[] $pos.Length; $sc = New-Object double[] $pos.Length; $sw = New-Object double[] $pos.Length
        for ($j = 0; $j -lt $pos.Length; $j++) { $sk[$j] = $ks[$pos[$j]]; $sc[$j] = $cpuKey[$pos[$j]]; $sw[$j] = $wsKey[$pos[$j]] }
        foreach ($k in (Get-TopIndices $sc $sk 8)) { $selected[$k] = $true }
        foreach ($k in (Get-TopIndices $sw $sk 5)) { $selected[$k] = $true }
    }
    # every process named in an incident ranking, and the collector itself
    foreach ($k in $rankedK.Keys) { if ($k -ge 0 -and $k -lt $procAll.Count -and $null -ne $procAll[$k]) { $selected[[int]$k] = $true } }
    foreach ($k in $ks) { if ($procAll[$k].IsCollector) { $selected[$k] = $true } }
    # the print processes, for the print state
    foreach ($p in @($printState.Processes)) { $selected[[int]$p.K] = $true }
}
$selK = [int[]]@($selected.Keys | Sort-Object)

# per-snapshot CPU and carried-forward working set of the selected processes from the process rows
$isSel = New-Object bool[] ($procAll.Count + 1)
$pCpu = @{}; $pWs = @{}
foreach ($k in $selK) { $isSel[$k] = $true; $pCpu[$k] = New-Object double[] $nP; $pWs[$k] = New-WorkerPerfNanArray $nP }
$rows = $model.Rows
$rStart = $rows.Start; $rK = $rows.K; $rCpu = $rows.CpuMs; $rWs = $rows.WsKB
# the working set carried over a -From cut holds at the first snapshot for processes without a row there
$carried = $model.Carried
for ($i = 0; $i -lt $carried.K.Length; $i++) {
    $k = [int]$carried.K[$i]
    if ($k -ge 0 -and $isSel[$k]) { $pWs[$k][0] = [double]$carried.WsKB[$i] }
}
for ($p = 0; $p -lt $nP; $p++) {
    for ($r = $rStart[$p]; $r -lt $rStart[$p + 1]; $r++) {
        $k = $rK[$r]
        if ($k -lt 0 -or -not $isSel[$k]) { continue }
        $pCpu[$k][$p] += $rCpu[$r]; $pWs[$k][$p] = $rWs[$r]
    }
}
$printWs = @{}
foreach ($p in @($printState.Processes)) { $printWs[[int]$p.K] = $null }
$procOut = New-Object System.Collections.Generic.List[object]
foreach ($k in $selK) {
    $pr = $procAll[$k]
    $f0 = [int]$pr.FirstP; $f1 = [int]$pr.LastP
    $cpuA = $pCpu[$k]; $wsA = $pWs[$k]
    $carry = $nan; $lifeSec = 0.0
    for ($p = $f0; $p -le $f1; $p++) {
        $cpuA[$p] = $cpuA[$p] * $capFactor[$p]
        if ($wsA[$p] -eq $wsA[$p]) { $carry = $wsA[$p] / 1024.0 }
        $wsA[$p] = $carry
        $lifeSec += $snapSecArr[$p]
    }
    if ($printWs.ContainsKey($k)) {
        # working set of a print process at its first and last snapshot with a value (MB, as in its series)
        $wsFirst = $null; $wsLast = $null
        for ($p = $f0; $p -le $f1; $p++) { if ($wsA[$p] -eq $wsA[$p]) { if ($null -eq $wsFirst) { $wsFirst = [Math]::Round($wsA[$p]) }; $wsLast = [Math]::Round($wsA[$p]) } }
        $printWs[$k] = @{ Start = $wsFirst; End = $wsLast }
    }
    $cpuAvg = $null
    if ($lifeSec -gt 0 -and $cores -gt 0) { $cpuAvg = [Math]::Round([double]$pr.CpuMs / ($lifeSec * 1000.0 * $cores) * 100.0, 2) }
    $startMs = $null
    if ($null -ne $pr.StartMs) { $startMs = [long]$pr.StartMs }
    $procOut.Add([ordered]@{
            k = $k; pid = [int]$pr.Pid; name = [string]$pr.Name; role = [string]$pr.Role; roleLabel = [string]$pr.RoleLabel; services = [string]$pr.Services
            s = [int]$pr.SessionIndex; a = [int]$pr.AppIndex; start = $startMs; path = [string]$pr.Path; cmd = [string]$pr.Cmd
            first = [long]$snap.TimeMs[$f0]; last = [long]$snap.TimeMs[$f1]
            cpuSec = [Math]::Round([double]$pr.CpuMs / 1000.0, 1); cpuAvg = $cpuAvg; cpuMax = (Get-Round $pr.CpuMaxPct 2)
            wsAvg = (Get-Round ([double]$pr.WsAvgKB / 1024.0) 0); wsMax = (Get-Round ([double]$pr.WsMaxKB / 1024.0) 0); privMax = (Get-Round ([double]$pr.PrivMaxKB / 1024.0) 0)
            ioMB = [Math]::Round([double]$pr.IoBytes / 1MB, 1); handles = [int]$pr.Handles; threads = [int]$pr.Threads; isCollector = [bool]$pr.IsCollector
            o = $f0; cpu = (New-JsonSeries $cpuA 2 $f0 $f1); ws = (New-JsonSeries $wsA 0 $f0 $f1)
        })
}

#endregion

#region ---------- citrix, target comparison ----------------------------------------------

$citrixOut = New-Object System.Collections.Generic.List[object]
foreach ($c in @($model.Citrix)) {
    $citrixOut.Add([ordered]@{
            source = [string]$c.Source; s = [int]$c.SessionIndex; instance = [string]$c.Instance; metric = [string]$c.Metric
            avg = (Get-Round $c.Avg 2); max = (Get-Round $c.Max 2); n = [int]$c.N
        })
}
$sollOut = New-Object System.Collections.Generic.List[object]
foreach ($row in $sollIst) {
    $detail = ''
    if (-not $row.Measured) { $detail = [string]$row.Detail }
    $sollOut.Add([ordered]@{
            id = [string]$row.Id; label = [string]$row.Label; unit = [string]$row.Unit; ideal = [string]$row.Ideal
            warn = [double]$row.Warn; crit = [double]$row.Crit; origin = [string]$row.Origin; source = [string]$row.Source; url = [string]$row.Url; note = [string]$row.Note
            measured = [bool]$row.Measured; detail = $detail; status = [int]$row.Status; exceeded = [bool]$row.Exceeded
            avg = (Get-Round $row.Avg 2); p95 = (Get-Round $row.P95 2); max = (Get-Round $row.Max 2)
            pctNormal = (Get-Round $row.PctNormal 1); pctWarn = (Get-Round $row.PctWarn 1); pctCrit = (Get-Round $row.PctCrit 1)
            worstInstance = [string]$row.WorstInstance
        })
}

#endregion

#region ---------- lookback, print state ---------------------------------------------------

$beforeIncOut = New-Object System.Collections.Generic.List[object]
foreach ($inc in $beforeIncidents) { $beforeIncOut.Add((ConvertTo-EventIncidentEntry $inc)) }
# near: the lookback events within 15 minutes of a reported time before the capture, then the events of the capture
# within the same radius (nearCapture: their positions in events)
$nearOut = New-Object System.Collections.Generic.List[object]
foreach ($e in @($lookback.Near)) { $nearOut.Add((ConvertTo-WorkerPerfEventOut $e $eventOffset)) }
$nearCapture = New-Object System.Collections.Generic.List[int]
$captureStartMs = [long]$tick.TimeMs[0]
if ($null -ne $model.CaptureStartMs) { $captureStartMs = [long]$model.CaptureStartMs }
if ($null -ne $reportedWallMs -and $reportedWallMs -lt $captureStartMs + [long]$eventOffset * 60000L) {
    for ($i = 0; $i -lt $events.Count; $i++) {
        if (Test-WorkerPerfEventNearWall $events[$i] $reportedWallMs $eventOffset) { $nearOut.Add($eventsOut[$i]); $nearCapture.Add($i) }
    }
}
$perDayOut = New-Object System.Collections.Generic.List[object]
$incidentEventCount = 0
foreach ($d in @($lookback.PerDay)) { $perDayOut.Add([ordered]@{ day = [string]$d.Day; count = [int]$d.Count; partial = [bool]$d.Partial }); $incidentEventCount += [int]$d.Count }
# per log the oldest event read (M5), and what the lookback skipped per log (I5, LookbackReadCounts of newer captures)
$oldestOut = @(@($lookback.Oldest) | Where-Object { $null -ne $_ } | ForEach-Object { [ordered]@{ log = [string]$_.Log; t = [long]$_.TimeMs } })
$lookbackReadsOut = @()
if (@($model.Skip) -notcontains 'Rueckblick') { $lookbackReadsOut = ConvertTo-ReadCountsOut $model.Meta['LookbackReadCounts'] }
# What the page may say about the lookback (status):
#   notRecorded  the capture has no lookback setting (format 2)
#   off          -EventLookbackDays 0 or -Skip Rueckblick
#   missingFile  events_before.csv is missing
#   unavailable  nothing was read: the lookback read failed (SourceErrors 'eventsbefore'), the capture's Sources do not
#                list every log of events.json that has a lookback (the source does not read the lookback; the Windows
#                source of today lists only Defender and AppLocker), or list none of them as available
#   partial      every lookback log is listed, some as not available: only the available ones were read
#   read         every lookback log is listed and available; the lookback may hold no events
# A lookback that holds events is partial or read, by the same per-log rule (read when the Sources say nothing more).
# logs: every log of events.json with a lookback, in its order, with the label of its source and whether it was read.
$lookbackLogs = @(@(Get-WorkerPerfEventReadLogs $eventConfig) | Where-Object { $_.Lookback })
$logsOut = New-Object System.Collections.Generic.List[object]
$listedCount = 0
foreach ($l in $lookbackLogs) {
    $sid = 'events.' + $l.Id
    $avail = $false
    # a switched-off log is not available for the capture, but its events were read for the lookback (M14)
    if ($model.Sources.ContainsKey($sid)) { $listedCount++; $avail = ([bool]$model.Sources[$sid].Available -or [bool](Get-WorkerPerfField $model.Sources[$sid] 'LookbackRead')) }
    $label = [string]$l.Id
    if ($texts.ContainsKey('source.' + $sid)) { $label = [string]$texts['source.' + $sid] }
    $logsOut.Add([ordered]@{ id = [string]$l.Id; label = $label; available = $avail })
}
$usableCount = @($logsOut | Where-Object { $_.available }).Count
$allListed = ($listedCount -eq $lookbackLogs.Count)
$lookbackStatus = 'read'
$metaDays = Get-WorkerPerfField $model.Meta 'EventLookbackDays'
if ($null -eq $metaDays) { $lookbackStatus = 'notRecorded' }
elseif ([int]$metaDays -le 0 -or @($model.Skip) -contains 'Rueckblick') { $lookbackStatus = 'off' }
elseif ([int]$lookback.EventCount -gt 0) {
    if ($allListed -and $usableCount -gt 0 -and $usableCount -lt $lookbackLogs.Count) { $lookbackStatus = 'partial' }
}
elseif (-not (Test-Path -LiteralPath (Join-Path $Path 'events_before.csv'))) { $lookbackStatus = 'missingFile' }
else {
    $failed = @($model.SourceErrors | Where-Object { $_.Source -eq 'eventsbefore' -or $_.Source -like 'eventsbefore.*' })
    if ($failed.Count -gt 0 -or -not $allListed -or $usableCount -eq 0) { $lookbackStatus = 'unavailable' }
    elseif ($usableCount -lt $lookbackLogs.Count) { $lookbackStatus = 'partial' }
}
$captureEndMs = [long]$tick.TimeMs[$tick.TimeMs.Count - 1]
if ($null -ne $model.CaptureEndMs) { $captureEndMs = [long]$model.CaptureEndMs }
$beforeOut = [ordered]@{
    days = [int]$lookback.Days; from = [long]$lookback.FromMs; capped = [string[]]@($lookback.Capped)
    eventCount = [int]$lookback.EventCount; incidentEventCount = $incidentEventCount; perDay = $perDayOut.ToArray()
    incidents = $beforeIncOut.ToArray(); near = $nearOut.ToArray(); nearCapture = $nearCapture.ToArray()
    captureStart = $captureStartMs; status = $lookbackStatus; logs = $logsOut.ToArray(); captureEnd = $captureEndMs
    oldest = $oldestOut; readCounts = $lookbackReadsOut
}

$driversOut = New-Object System.Collections.Generic.List[object]
foreach ($d in @($printState.Drivers)) {
    $driversOut.Add([ordered]@{
            name = [string]$d.Name; manufacturer = [string]$d.Manufacturer; version = [string]$d.Version; type = [int]$d.Type; isolation = [string]$d.Isolation
            isolated = [bool]$d.Isolated; files = [string[]]@($d.Files); involved = [bool]$d.Involved; possiblyInvolved = [bool]$d.PossiblyInvolved
        })
}
$queuesOut = New-Object System.Collections.Generic.List[object]
foreach ($q in @($printState.Queues)) {
    $queuesOut.Add([ordered]@{ name = [string]$q.Name; maxJobs = (Get-Round $q.MaxJobs 0); jobErrors = (Get-Round $q.JobErrors 0); notReadyErrors = (Get-Round $q.NotReadyErrors 0) })
}
$printProcsOut = New-Object System.Collections.Generic.List[object]
foreach ($p in @($printState.Processes)) {
    $ws = $printWs[[int]$p.K]
    $wsStart = $null; $wsEnd = $null
    if ($null -ne $ws) { $wsStart = $ws.Start; $wsEnd = $ws.End }
    $printProcsOut.Add([ordered]@{ k = [int]$p.K; name = [string]$p.Name; cpuMax = (Get-Round $p.CpuMaxPct 2); wsStartMB = $wsStart; wsEndMB = $wsEnd; wsMaxMB = (Get-Round $p.WsMaxMB 1) })
}
$printOut = [ordered]@{ drivers = $driversOut.ToArray(); queues = $queuesOut.ToArray(); processes = $printProcsOut.ToArray() }

#endregion

#region ---------- write report -----------------------------------------------------------

$snapKindText = [string]::Join('', [string[]]@($snap.Kind))
$data = [ordered]@{
    meta = $meta; quality = $quality; thresholds = $thresholdsOut.ToArray()
    tickT = (New-JsonIntegers $tick.TimeMs); snapT = (New-JsonIntegers $snap.TimeMs); snapKind = $snapKindText
    host = $hostOut; volumes = $volumesOut.ToArray(); shares = $sharesOut.ToArray(); probes = $probesOut.ToArray()
    mainApp = $mainAppOut; events = $eventsOut.ToArray()
    sessions = $sessOut.ToArray(); apps = $appsOut.ToArray(); pairs = $pairsOut.ToArray(); procs = $procOut.ToArray()
    citrix = $citrixOut.ToArray(); sollIst = $sollOut.ToArray(); incidents = $incOut.ToArray()
    unmeasured = [ordered]@{ input = [bool]$unmeasured.Input; worker = [string[]]@($unmeasured.Worker) }
    noFinding = ($incOut.Count -eq 0)
    before = $beforeOut; print = $printOut; eventsOutsideCut = [int]$model.EventsOutsideCut
    # the categories -Skip left out, with their reason and the places of the page that depend on them (last field)
    skipped = @(Get-WorkerPerfSkippedOut -Skip $model.Skip -Texts $texts)
}

$maskObj = $null
if ($Mask) {
    # The free texts go first, in place: nothing of the uncleared data is written anywhere after this. The names come
    # from the whole capture (not the cut), built once. The level is set on the masked result, so that no replacement
    # can touch it.
    Write-Host 'Maskiere Namen ...'
    Clear-WorkerPerfReportFreeText $data
    $maskObj = New-WorkerPerfMask -Path $Path -Level $Mask -Texts $texts -RoleLabels @($roles | ForEach-Object { [string]$_.label }) -EventConfig $eventConfig
    # a reported user typed by the caller that is no name of the capture is removed (P2-R11); one the capture names (a
    # session in the cut or anywhere in the capture) is replaced like every name
    if ($null -ne $focusOut.user -and -not $focusOut.found -and -not (Test-WorkerPerfMaskKnownAccount $maskObj ([string]$focusOut.user))) {
        $focusOut.user = [string]$texts['mask.other']
    }
    $data = Protect-WorkerPerfReportData $data $maskObj
    $data['meta']['mask'] = $Mask
    # names equal to a word of the report garble its sentences and can be guessed from them (P2-R12): named by their
    # replacement, never by the real name
    $maskWords = @(Get-WorkerPerfMaskVocabularyHits -Mask $maskObj -Texts $texts -Units @($thresholds.Values | ForEach-Object { [string]$_.unit }))
}

Write-Host 'Schreibe Bericht ...'
$template = [IO.File]::ReadAllText($templateFile, [Text.Encoding]::UTF8)
$marker = '<script id="wp-data" type="application/json">null</script>'
$at = $template.IndexOf($marker)
if ($at -lt 0) { throw 'Die Berichtsvorlage enthaelt keinen Datenplatzhalter.' }
$open = '<script id="wp-data" type="application/json">'
# The JSON is written straight into the file (UTF-8 without BOM) in place of the placeholder's 'null', so the report is
# never held in memory as a whole. It goes to a temporary file next to the target first; only when it is complete is an
# existing target deleted and the temporary file moved onto its name. An error while writing, or a target that cannot
# be deleted (read-only, locked), leaves the previous report as it was. Only an error between the delete and the move
# leaves no report. The temporary file is removed on any error. No File.Replace: some file systems used for reports
# (FAT/exFAT, some SMB/NAS and DFS shares) do not support it.
$tmpFile = $OutFile + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
try {
    $writer = New-Object System.IO.StreamWriter($tmpFile, $false, (New-Object System.Text.UTF8Encoding $false), 65536)
    try {
        $writer.Write($template.Substring(0, $at + $open.Length))
        ConvertTo-JsonText $data $writer
        $writer.Write($template.Substring($at + $open.Length + 4))
    }
    finally { $writer.Dispose() }
    if ([IO.File]::Exists($OutFile)) { [IO.File]::Delete($OutFile) }
    [IO.File]::Move($tmpFile, $OutFile)
}
catch {
    if ([IO.File]::Exists($tmpFile)) { Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue }
    throw
}
# the map only once the report is complete; a failure here leaves the report as written
if ($MaskMapFile) {
    try { Save-WorkerPerfMaskMap -Mask $maskObj -Path $MaskMapFile }
    catch { throw ("Bericht geschrieben ({0}), die Zuordnungsdatei '{1}' aber nicht: {2}" -f $OutFile, $MaskMapFile, $_.Exception.Message) }
}

$timer.Stop()
Write-Host ("Bericht erstellt in {0} s (davon Einlesen {1} s): {2}" -f $timer.Elapsed.TotalSeconds.ToString('0.0', $inv), $loadSec.ToString('0.0', $inv), $OutFile)
Write-Host ("  {0} Takte, {1} Schnappschuesse, {2} Vorfaelle, {3} Sitzungen, {4} Prozesse im Bericht" -f $nT, $nP, $incOut.Count, $sessOut.Count, $procOut.Count)
if ($Mask) {
    Write-Host ("  maskiert (Stufe {0}): {1} Namen ersetzt" -f $Mask, @($maskObj.Entries).Count)
    if ($maskWords.Count -eq 1) {
        Write-Host ("  Hinweis: 1 Name gleicht einem Wort des Berichts ({0}); Saetze mit diesem Wort sind im maskierten Bericht entstellt und koennen den Namen verraten." -f $maskWords[0])
    }
    elseif ($maskWords.Count -gt 1) {
        Write-Host ("  Hinweis: {0} Namen gleichen Woertern des Berichts ({1}); Saetze mit diesen Woertern sind im maskierten Bericht entstellt und koennen den Namen verraten." -f $maskWords.Count, [string]::Join(', ', [string[]]$maskWords))
    }
    if ($MaskMapFile) { Write-Host ("  Zuordnung der Ersatznamen: {0}" -f $MaskMapFile) }
}
Get-Item -LiteralPath $OutFile

#endregion
