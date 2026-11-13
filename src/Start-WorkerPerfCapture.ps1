#Requires -Version 5.1
<#
.SYNOPSIS
    Records performance and resource usage of a Citrix multi-session VDA (terminal server worker)
    down to individual sessions and processes.

.DESCRIPTION
    Measures in two cadences and writes a run folder in capture format 3:

      fast cadence (-FastIntervalSeconds, default 2 s): host signals, volumes, file shares and
          input delay per session and per process (ticks.csv, volumes.csv, shares.csv,
          inputdelay.csv, inputdelay_proc.csv)
      snapshots (-IntervalSeconds, default 15 s): processes, sessions and Citrix metrics
          (snapshots.csv, processes.csv, procinfo.csv, procend.csv, sessions.csv, citrix.csv),
          with each regular snapshot also endpoint probes (probes.csv), events up to 5 s before the read
          (events.csv; one more read without that lag when the capture ends) and the counters of the print
          queues (printqueues.csv, a row only when a value changes)

    At the start the events of the last -EventLookbackDays days go to events_before.csv and the
    installed print drivers to printdrivers.csv. Before the first tick the health picture of the
    server is read once (health.json: facts about the machine, no rating; -Skip Zustand leaves it out).

    While a trigger signal of thresholds.json is over its threshold (and -BurstHoldSeconds
    afterwards) snapshots are taken every -BurstIntervalSeconds. Every 20th regular snapshot
    is a keyframe that lists every process; the others only list active processes.

    The run folder also holds a copy of thresholds.json, a copy of the application list (apps.json,
    without -Skip Zustand) and meta.json (host facts, settings, end reason); in the simulation
    additionally expected.json (the expected analysis result).

    Stop the capture with Ctrl+C, by -DurationMinutes, by -MaxSizeMB, or by creating a file
    named 'stop.flag' inside the run folder. Analyse the result with New-WorkerPerfReport.ps1.

    -Skip leaves out single measurement categories: the collector makes none of their calls, and their
    files are missing from the run folder (meta.json lists the categories in Skip).

    -HealthOnly is a quick run: it reads only the health picture (health.json), the events before the start
    (events_before.csv) and the print driver list (printdrivers.csv), writes them with apps.json and meta.json
    (EndReason 'healthonly') and ends, without any measurement.

    A call of the data source that fails does not end the capture: the tick or snapshot is
    skipped, one warning per source is shown, and meta.json counts the failures per source
    (SourceErrors). If the capture itself ends on an error, meta.json says so (EndReason
    'error', EndMessage).

.PARAMETER OutputPath
    Base folder. A sub folder <COMPUTER>_<yyyyMMdd-HHmmss> is created per capture. Together with -Skip a bare
    category name (Rueckblick) stops the start: it is a value of -Skip given with a blank instead of a comma; a folder
    of that name is given as a path (.\Rueckblick).

.PARAMETER FastIntervalSeconds
    Fast cadence for host signals and input delay (1-60 s, default 2).

.PARAMETER IntervalSeconds
    Regular snapshot interval for processes and sessions (5-3600 s, default 15).

.PARAMETER BurstIntervalSeconds
    Minimum snapshot interval while a trigger signal is over its threshold (default 5).
    Snapshots are taken on fast ticks: with the defaults (2 s ticks) every third tick, 6 s.

.PARAMETER BurstHoldSeconds
    How long dense snapshots continue after the last trigger (default 60).

.PARAMETER DurationMinutes
    Stop automatically after this time. 0 = run until stopped. -Simulate needs at least 60.

.PARAMETER MaxSizeMB
    Stop when the run folder reaches this size (default 500).

.PARAMETER ThresholdFile
    Thresholds and trigger signals. Default: thresholds.json next to this script.

.PARAMETER EndpointFile
    Endpoints for the connect probes. Default: endpoints.json next to this script; without
    this file no probes are made (see endpoints.example.json).

.PARAMETER AppsFile
    Application list for the health picture (area Anwendungen). Default: apps.json next to this script.

.PARAMETER IncludeCommandLine
    Also store process command lines (may contain sensitive data such as file names or URLs). Without Prozesse
    (-Skip Prozesse) no command line is recorded and meta.json says IncludeCommandLine false.

.PARAMETER NoCitrix
    Skip the Citrix ICA/EUEM WMI metrics. Same as -Skip Citrix.

.PARAMETER CitrixMetricFilter
    Regular expression selecting which numeric Citrix WMI properties are recorded.

.PARAMETER EventLookbackDays
    At the start, read the events of this many days before the start into events_before.csv
    (0-90, default 7; 0 = no lookback, the same as -Skip Rueckblick). Where a log reaches the cap
    of the lookback, meta.json names it (LookbackCapped).

.PARAMETER Skip
    Measurement categories to leave out, as a list or comma separated, case does not matter:
      Prozesse      processes, services and input delay per process (processes.csv, procinfo.csv,
                    procend.csv, inputdelay_proc.csv)
      Laufwerke     volumes, file shares and the map of the profile containers (volumes.csv, shares.csv)
      Citrix        Citrix ICA/EUEM metrics (citrix.csv)
      Ereignisse    events during the capture (events.csv)
      Rueckblick    events before the start (events_before.csv)
      Drucken       print drivers and print queues (printdrivers.csv, printqueues.csv)
      Gegenstellen  endpoint probes (probes.csv)
      Zustand       the health picture of the server, read once at the start (health.json)
    The base is always measured: host signals, input delay per session, snapshots and sessions
    (ticks.csv, inputdelay.csv, snapshots.csv, sessions.csv, meta.json, thresholds.json).

.PARAMETER HealthOnly
    Reads only the health picture, the lookback and the print driver list and ends; no measurement. With it apply
    -OutputPath, -AppsFile, -EventLookbackDays and -Skip: -Skip Rueckblick and -Skip Drucken shorten the run, the other
    categories are accepted and have no effect. -Skip Zustand and the parameters of the measurement (-FastIntervalSeconds,
    -IntervalSeconds, -BurstIntervalSeconds, -BurstHoldSeconds, -DurationMinutes, -MaxSizeMB, -ThresholdFile,
    -EndpointFile, -IncludeCommandLine, -NoCitrix, -CitrixMetricFilter) are refused. When the health picture could not be
    read or written, the last line says so: Schnelllauf beendet ohne Zustandsbild.

.PARAMETER Simulate
    Replay the scripted 60-minute scenario instead of reading the local system (no waiting
    between ticks, runs on any platform). Used for demos and tests.

.EXAMPLE
    .\Start-WorkerPerfCapture.ps1 -OutputPath D:\WorkerPerf -DurationMinutes 240

.EXAMPLE
    .\Start-WorkerPerfCapture.ps1 -Simulate -DurationMinutes 60 -OutputPath .\demo

.EXAMPLE
    .\Start-WorkerPerfCapture.ps1 -HealthOnly -OutputPath D:\WorkerPerf
#>
[CmdletBinding()]
param(
    [string]$OutputPath,
    [ValidateRange(1, 60)][int]$FastIntervalSeconds = 2,
    [ValidateRange(5, 3600)][int]$IntervalSeconds = 15,
    [ValidateRange(1, 3600)][int]$BurstIntervalSeconds = 5,
    [ValidateRange(0, 86400)][int]$BurstHoldSeconds = 60,
    [ValidateRange(0, 100000)][double]$DurationMinutes = 0,
    [ValidateRange(1, 1000000)][double]$MaxSizeMB = 500,
    [string]$ThresholdFile,
    [string]$EndpointFile,
    [string]$AppsFile,
    [switch]$IncludeCommandLine,
    [switch]$NoCitrix,
    [string]$CitrixMetricFilter = 'Latency|Round|Bandwidth|FramesPerSecond|Fps',
    [ValidateRange(0, 90)][int]$EventLookbackDays = 7,
    [string[]]$Skip = @(),
    [switch]$Simulate,
    [switch]$HealthOnly
)

# Where AppLocker or WDAC puts the console into ConstrainedLanguage, .NET types and Add-Type fail with errors that
# do not name the cause. This check uses nothing that the restricted mode forbids.
$languageMode = "$($ExecutionContext.SessionState.LanguageMode)"
if ($languageMode -ne 'FullLanguage') {
    throw "WorkerPerf benoetigt den PowerShell-Sprachmodus FullLanguage; aktiv ist $languageMode. AppLocker oder WDAC schraenkt diese Konsole ein: bitte eine uneingeschraenkte administrative Konsole verwenden."
}

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

#region ---------- setup ------------------------------------------------------------------

. (Join-Path $PSScriptRoot 'WorkerPerf.Common.ps1')
# the categories left out (resolved from -Skip, -NoCitrix and -EventLookbackDays), before anything is read or
# created (an unknown value stops the start here)
$leftOut = @(Resolve-WorkerPerfSkip $Skip ([bool]$NoCitrix) $EventLookbackDays)
# The quick run consists of the health picture and takes none of the settings of the measurement: refused here, before
# anything is created.
if ($HealthOnly) {
    if ($leftOut -contains 'Zustand') { throw '-HealthOnly und -Skip Zustand schliessen sich aus: der Schnelllauf besteht aus dem Zustandsbild.' }
    $measurementOnly = @(@('FastIntervalSeconds', 'IntervalSeconds', 'BurstIntervalSeconds', 'BurstHoldSeconds', 'DurationMinutes', 'MaxSizeMB', 'ThresholdFile',
            'EndpointFile', 'IncludeCommandLine', 'NoCitrix', 'CitrixMetricFilter') | Where-Object { $PSBoundParameters.ContainsKey($_) })
    if ($measurementOnly.Count -gt 0) {
        throw ('-HealthOnly liest nur das Zustandsbild, den Rueckblick und die Treiberliste; nicht zusammen mit: {0}.' -f ((@($measurementOnly) | ForEach-Object { '-' + $_ }) -join ', '))
    }
}
# -Skip Prozesse Rueckblick (a blank instead of a comma) binds the second value to the first positional parameter,
# -OutputPath: stop before anything is created. A folder of that name can still be given as a path (.\Rueckblick).
if ($PSBoundParameters.ContainsKey('Skip') -and $PSBoundParameters.ContainsKey('OutputPath') -and @($script:WorkerPerfCategories.Keys) -contains $OutputPath) {
    $given = @(@($Skip) | Where-Object { $null -ne $_ } | ForEach-Object { ([string]$_).Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    throw ("-OutputPath '{0}' ist der Name einer Kategorie: die Werte von -Skip mit Komma trennen (-Skip {1})." -f $OutputPath, ((@($given) + $OutputPath) -join ','))
}
# command lines come from the process snapshots: without Prozesse none is recorded, and meta.json says so
$withCommandLine = ([bool]$IncludeCommandLine -and $leftOut -notcontains 'Prozesse')
. (Join-Path $PSScriptRoot 'WorkerPerf.Capture.ps1')
. (Join-Path $PSScriptRoot 'WorkerPerf.EventConfig.ps1')
if ($Simulate) {
    if (-not $HealthOnly -and $DurationMinutes -lt 60) { throw '-Simulate erfordert -DurationMinutes von mindestens 60 (das Drehbuch dauert 60 Minuten).' }
    . (Join-Path $PSScriptRoot 'WorkerPerf.Sources.Simulation.ps1')
}
else {
    if (-not (Test-WorkerPerfWindows)) { throw 'Die Aufzeichnung realer Daten ist nur unter Windows moeglich. Fuer Testdaten -Simulate verwenden.' }
    . (Join-Path $PSScriptRoot 'WorkerPerf.Sources.Windows.ps1')
}

if (-not $ThresholdFile) { $ThresholdFile = Join-Path $PSScriptRoot 'thresholds.json' }
if (-not $EndpointFile) { $EndpointFile = Join-Path $PSScriptRoot 'endpoints.json' }
if (-not $AppsFile) { $AppsFile = Join-Path $PSScriptRoot 'apps.json' }
# A relative path is meant from the PowerShell location; the .NET file calls that read these files resolve it from the
# process folder, which Set-Location does not move. Resolved once, so reading and copying use the same file. While the
# location is on another provider (Env:, HKLM:), a relative path is meant from the file system location.
function Resolve-InputFile([string]$Path) {
    if ((Get-Location).Provider.Name -ne 'FileSystem' -and -not [IO.Path]::IsPathRooted($Path) -and -not $Path.Contains(':')) {
        $Path = Join-Path (Get-Location -PSProvider FileSystem).ProviderPath $Path
    }
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}
$ThresholdFile = Resolve-InputFile $ThresholdFile
$EndpointFile = Resolve-InputFile $EndpointFile
$AppsFile = Resolve-InputFile $AppsFile
if (-not $OutputPath) {
    $OutputPath = $(if ($env:ProgramData) { Join-Path $env:ProgramData 'WorkerPerf' } else { Join-Path (Get-Location).Path 'WorkerPerfData' })
}

$inv = [Globalization.CultureInfo]::InvariantCulture
# the quick run reads neither thresholds nor endpoints
$thresholds = $null
if (-not $HealthOnly) { $thresholds = Read-WorkerPerfThresholds $ThresholdFile }
# the application list of the health picture: a missing or faulty list stops the start here, before anything is created
$healthApps = @()
if ($leftOut -notcontains 'Zustand') { $healthApps = @(Read-WorkerPerfHealthApps $AppsFile) }
$endpoints = @()
if (-not $HealthOnly -and $leftOut -notcontains 'Gegenstellen') { $endpoints = @(Read-WorkerPerfEndpoints $EndpointFile) }
# the event catalogue: which logs, providers and ids the source reads and how it reads their fields
$eventConfig = Read-WorkerPerfEventConfig (Join-Path $PSScriptRoot 'events.json')

# The quick run passes the categories of the measurement as left out as well, so the source opens none of them.
$sourceSkip = @($leftOut)
if ($HealthOnly) { $sourceSkip = @($leftOut) + @(@('Prozesse', 'Laufwerke', 'Citrix', 'Ereignisse', 'Gegenstellen') | Where-Object { $leftOut -notcontains $_ }) }
# -HealthOnly only in the quick run: the source then opens no performance counter and lists no measured signal in Sources
$quickArgs = @{}
if ($HealthOnly) { $quickArgs['HealthOnly'] = $true }
$source = Initialize-WorkerPerfSource -StartTime (Get-Date) -Endpoints $endpoints -CitrixMetricFilter $CitrixMetricFilter `
    -IncludeCommandLine:$withCommandLine -Skip $sourceSkip -EventConfig $eventConfig -Apps $healthApps @quickArgs
$cores = [int]$source.LogicalProcessors
$ramMB = [double]$source.PhysicalMemoryMB

$startTime = Get-WorkerPerfNow
$runDir = Join-Path $OutputPath ('{0}_{1}' -f $source.Computer, $startTime.ToString('yyyyMMdd-HHmmss', $inv))
[void](New-Item -ItemType Directory -Path $runDir -Force)
# ProviderPath: for a UNC folder .Path is provider-qualified (Microsoft.PowerShell.Core\FileSystem::\\...), which the
# .NET file calls below do not accept
$runDir = (Resolve-Path -LiteralPath $runDir).ProviderPath
$stopFlag = Join-Path $runDir 'stop.flag'

$guard = Test-WorkerPerfGuard -FreeMB (Get-WorkerPerfFreeSpaceMB -Path $runDir) -SizeMB 0 -MaxSizeMB $MaxSizeMB -Phase start
if ($guard) { throw "Aufzeichnung nicht gestartet: zu wenig freier Speicherplatz unter $runDir (unter 200 MB)." }

# A writer that does not exist (its category left out) means: the calls behind it are not made, no row is written.
# The quick run writes only the lookback and the driver list.
if ($HealthOnly) { $writers = New-WorkerPerfWriters -RunDir $runDir -Skip $leftOut -Only @('events_before.csv', 'printdrivers.csv') }
else { $writers = New-WorkerPerfWriters -RunDir $runDir -Skip $leftOut }
$wTicks = $writers['ticks.csv']; $wVolumes = $writers['volumes.csv']; $wShares = $writers['shares.csv']
$wInput = $writers['inputdelay.csv']; $wInputProc = $writers['inputdelay_proc.csv']; $wCitrix = $writers['citrix.csv']
$wProbes = $writers['probes.csv']; $wEvents = $writers['events.csv']; $wSnaps = $writers['snapshots.csv']
$wSessions = $writers['sessions.csv']; $wInfo = $writers['procinfo.csv']; $wProcs = $writers['processes.csv']
$wEnded = $writers['procend.csv']
$wEventsBefore = $writers['events_before.csv']; $wDrivers = $writers['printdrivers.csv']; $wQueues = $writers['printqueues.csv']
$fastWriters = @(@($wTicks, $wVolumes, $wShares, $wInput, $wInputProc) | Where-Object { $null -ne $_ })
$withProcesses = ($leftOut -notcontains 'Prozesse')
$allWriters = @($writers.Values)

$utf8 = New-Object System.Text.UTF8Encoding $false
$meta = [ordered]@{
    SchemaVersion        = $script:WorkerPerfFormatVersion
    Computer             = $source.Computer
    OS                   = $source.OS
    LogicalProcessors    = $cores
    PhysicalMemoryMB     = $source.PhysicalMemoryMB
    FastIntervalSeconds  = $FastIntervalSeconds
    IntervalSeconds      = $IntervalSeconds
    BurstIntervalSeconds = $BurstIntervalSeconds
    BurstHoldSeconds     = $BurstHoldSeconds
    MaxSizeMB            = $MaxSizeMB
    StartTime            = $startTime.ToString('o', $inv)
    EndTime              = $null
    EndReason            = $null
    EndMessage           = $null
    Ticks                = 0
    Snapshots            = 0
    SkippedTicks         = 0
    Simulated            = [bool]$Simulate
    HealthOnly           = [bool]$HealthOnly
    IncludeCommandLine   = $withCommandLine
    EventLookbackDays    = $(if ($leftOut -contains 'Rueckblick') { 0 } else { $EventLookbackDays })
    LookbackCapped       = @()
    EventReadCounts      = [ordered]@{}
    LookbackReadCounts   = [ordered]@{}
    Skip                 = $leftOut
    CollectorPid         = $source.CollectorPid
    Endpoints            = @(if ($leftOut -notcontains 'Gegenstellen') { @($source.Endpoints) })
    Sources              = $source.Sources
    SourceErrors         = [ordered]@{}
}
Set-WorkerPerfSkippedSources -Sources $meta.Sources -Skip $leftOut -EventLogIds @(@(Get-WorkerPerfEventReadLogs $eventConfig) | ForEach-Object { [string]$_.Id })
function Save-Meta {
    Save-WorkerPerfMeta -Path (Join-Path $runDir 'meta.json') -Meta $meta
}

# A failing call of the data source: counted per source in meta.json, one warning per source, the capture goes on.
$sourceNames = @{ fast = 'schneller Takt'; snapshot = 'Prozess-Schnappschuss'; services = 'Dienste'; probes = 'Antwortzeit-Proben'
    events = 'Ereignisprotokoll'; diskspace = 'freier Speicherplatz'; eventsbefore = 'Ereignisse vor der Messung'
    printdrivers = 'Druckertreiber'; printqueues = 'Druckwarteschlangen'; health = 'Zustandsbild' }
function Register-SourceError([string]$Source, $ErrorRecord) {
    # Ctrl+C is not a failure of the source
    if ($ErrorRecord.Exception -is [System.Management.Automation.PipelineStoppedException]) { throw $ErrorRecord.Exception }
    Register-SourceMessage $Source ([string]$ErrorRecord.Exception.Message)
}
function Register-SourceMessage([string]$Source, [string]$message) {
    # A log the source could not read is booked as '<call>.<log id>' (one entry per log); during the capture its entry in
    # Sources is marked as well (ReadFailed), so the report does not keep showing it as read without a trace.
    $name = $sourceNames[$Source]
    $cut = $Source.IndexOf([char]'.')
    if ($null -eq $name -and $cut -gt 0) { $name = '{0} ({1})' -f $sourceNames[$Source.Substring(0, $cut)], $Source.Substring($cut + 1) }
    if ($null -eq $name) { $name = $Source }
    if ($cut -gt 0 -and $Source.Substring(0, $cut) -eq 'events' -and $meta.Sources.Contains($Source)) {
        $entry = $meta.Sources[$Source]
        if ($entry -is [System.Collections.IDictionary] -and -not $entry.Contains('ReadFailed')) { $entry['ReadFailed'] = $true }
    }
    if (Add-WorkerPerfSourceError -Errors $meta.SourceErrors -Source $Source -Time (Get-WorkerPerfNow) -Message $message) {
        # the quick run has no capture that goes on
        if ($HealthOnly) { Write-Warning ("Datenquelle '{0}' meldet einen Fehler; der Schnelllauf liest den Rest: {1}" -f $name, $message) }
        else { Write-Warning ("Datenquelle '{0}' meldet einen Fehler; die Aufzeichnung laeuft weiter, weitere Fehler dieser Quelle werden nur gezaehlt: {1}" -f $name, $message) }
        # saved at once, so the failure is on record even if the capture is killed later
        try { Save-Meta } catch { Write-Verbose $_.Exception.Message }
    }
}

#endregion

#region ---------- capture loop -----------------------------------------------------------

# Failures the source reports without stopping its call (a log that could not be read), once each.
# With them the counters of the event reads (records skipped, messages not formatted, events over the cap; numbers).
function Register-SourceFailures {
    try { foreach ($f in @(Receive-WorkerPerfSourceErrors)) { if ($null -ne $f) { Register-SourceMessage ([string]$f.Source) ([string]$f.Message) } } }
    catch { Write-Verbose $_.Exception.Message }
    # the counters belong to the reads of the capture: without Ereignisse they stay empty
    if ($null -ne $wEvents) { try { $meta.EventReadCounts = Get-WorkerPerfEventCounts } catch { Write-Verbose $_.Exception.Message } }
}

function Write-WorkerPerfProbeRows([object[]]$Results, [int]$T) {
    foreach ($r in $Results) {
        if ($null -eq $r) { continue }
        $wProbes.WriteLine((ConvertTo-WorkerPerfProbeRow -Result $r -T $T))
    }
}

if ($HealthOnly) {
    Write-Host "WorkerPerf-Schnelllauf laeuft: $runDir"
    $reads = @('Zustandsbild')
    if ($leftOut -notcontains 'Rueckblick') { $reads += 'Rueckblick' }
    if ($leftOut -notcontains 'Drucken') { $reads += 'Treiberliste' }
    Write-Host ('Gelesen wird: ' + ($reads -join ', '))
    Write-Host ('Nicht gelesen (-Skip): ' + $(if ($leftOut.Count -gt 0) { $leftOut -join ', ' } else { 'keine' }))
}
else {
    Write-Host "WorkerPerf-Aufzeichnung laeuft: $runDir"
    Write-Host ('Gemessen: ' + ((@('Basis') + @(@($script:WorkerPerfCategories.Keys) | Where-Object { $script:WorkerPerfCategories[$_].Active -and $leftOut -notcontains $_ })) -join ', '))
    Write-Host ('Nicht gemessen (-Skip): ' + $(if ($leftOut.Count -gt 0) { $leftOut -join ', ' } else { 'keine' }))
    if ($IncludeCommandLine -and -not $withCommandLine) { Write-Host 'Befehlszeilen werden nicht aufgezeichnet: Prozesse ist weggelassen (-Skip Prozesse).' }
    Write-Host ("Schneller Takt {0} s, Schnappschuss alle {1} s{2}. Beenden mit Strg+C oder Datei 'stop.flag' im Ausgabeordner." -f `
            $FastIntervalSeconds, $IntervalSeconds, $(if ($DurationMinutes -gt 0) { ", Dauer $DurationMinutes min" } else { '' }))
}

$endReason = $null
$endMessage = $null
# Without health.json the quick run has nothing: why, in one sentence without server data (the class of the error), for
# the console and meta.json (EndMessage)
$noHealth = ''
$tickCount = 0
$snapCount = 0
$regularCount = 0
$skipped = 0
$eventsReady = $false
try {
    if (-not $HealthOnly) { [void](Copy-Item -LiteralPath $ThresholdFile -Destination (Join-Path $runDir 'thresholds.json')) }
    # the application list as given, so that the report rates with the list the health picture was read with
    if ($leftOut -notcontains 'Zustand') { [void](Copy-Item -LiteralPath $AppsFile -Destination (Join-Path $runDir 'apps.json')) }
    Save-Meta

    # Lookback up to the start: events after the start belong to the measurement (its reads begin after the start),
    # so a source that returns later ones does not count them twice. Compared in UTC.
    if ($null -ne $wEventsBefore) {
        try {
            $before = Get-WorkerPerfEventsBefore -Days $EventLookbackDays -Until $startTime
            foreach ($ev in @(Select-WorkerPerfEventsInWindow -Events @($before.Events) -Until $startTime)) {
                $wEventsBefore.WriteLine((ConvertTo-WorkerPerfEventRow $ev))
            }
            $meta.LookbackCapped = @(@($before.Capped) | Where-Object { -not [string]::IsNullOrEmpty([string]$_) } | ForEach-Object { [string]$_ })
            if ($meta.LookbackCapped.Count -gt 0) { Save-Meta }
        }
        catch { Register-SourceError 'eventsbefore' $_ }
        Register-SourceFailures
        # the counters as they stand after the lookback: what the lookback skipped (the report names it at the lookback)
        try { $meta.LookbackReadCounts = Get-WorkerPerfEventCounts } catch { Write-Verbose $_.Exception.Message }
        $wEventsBefore.Flush()
    }
    if ($null -ne $wDrivers) {
        try { foreach ($d in @(Get-WorkerPerfPrintDrivers)) { if ($null -ne $d) { $wDrivers.WriteLine((ConvertTo-WorkerPerfPrintDriverRow $d)) } } }
        catch { Register-SourceError 'printdrivers' $_ }
        $wDrivers.Flush()
    }
    # The health picture, read once before the first tick. It may carry names of servers, shares and accounts: it goes
    # only into the run folder, the console line names areas and seconds.
    if ($leftOut -notcontains 'Zustand') {
        $healthStep = 'read'
        try {
            $health = Get-WorkerPerfHealth
            if ($null -ne $health) {
                $healthStep = 'write'
                Save-WorkerPerfHealth -Path (Join-Path $runDir 'health.json') -Health $health
                $healthStep = 'line'
                Write-Host (Format-WorkerPerfHealthLine $health)
            }
            else { $noHealth = 'Die Datenquelle hat kein Zustandsbild geliefert.' }
        }
        catch {
            if ($healthStep -eq 'line') {
                # health.json is written; only the console line failed: nothing is missing (Ctrl+C still ends the run)
                if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { throw }
                Write-Warning ('Zustandsbild: ' + $_.Exception.Message)
            }
            else {
                Register-SourceError 'health' $_
                if ($healthStep -eq 'write') { $noHealth = 'health.json konnte nicht geschrieben werden ({0}).' -f $_.Exception.GetType().Name }
                else { $noHealth = 'Das Lesen des Zustandsbilds ist gescheitert ({0}).' -f $_.Exception.GetType().Name }
            }
        }
    }
    # The quick run ends here: baseline, schedule, loop and the tail of the probes belong to the measurement.
    if ($HealthOnly) {
        $endReason = 'healthonly'
        if ($noHealth) { $endMessage = $noHealth }
    }
    else {
        # The schedule starts after the start reads, so a slow lookback skips no tick and shortens no measurement; the
        # event cursor stays at the start time, so no event between the two is lost.
        $scheduleStart = Get-WorkerPerfNow

        # Baseline: one fast sample to establish the cumulative counters, one snapshot to book every process.
        $prevSample = Get-WorkerPerfFastSample
        # Without Prozesse no service map, no process rows and no memory of processes (events then find no session through
        # their process id).
        $services = $null; $procState = $null; $procMemory = $null
        if ($withProcesses) { $services = Get-WorkerPerfServices; $procState = New-WorkerPerfProcessState }
        $base = Get-WorkerPerfSnapshot -Kind K
        if ($withProcesses) {
            [void](Get-WorkerPerfProcessRows -State $procState -Processes @($base.Processes) -P -1 -PrevTime $base.Time -Services $services `
                    -IncludeCommandLine:$withCommandLine)
        }
        $prevSnapTime = [datetime]$base.Time
        # The session of an event is found through its process id: in the processes of the recent snapshots (a crashed
        # process is gone from the snapshot after its crash), and the user in the last snapshot that succeeded.
        $lastSnap = $base
        if ($withProcesses) {
            $procMemory = New-WorkerPerfProcessMemory -KeepSeconds ([Math]::Max(600, 3 * $IntervalSeconds))
            Update-WorkerPerfProcessMemory -Memory $procMemory -Processes @($base.Processes) -Time ([datetime]$base.Time)
        }
        # an event is logged at most one regular interval after the last snapshot that saw its process (plus slack)
        $eventGapSeconds = 2 * $IntervalSeconds + 5

        # Scheduling and durations are computed in UTC, so a step of the local clock (end of daylight saving time) neither
        # stalls the capture nor distorts ElapsedSec. The source keeps its own local times: they go to the files, to
        # Wait-WorkerPerfTick, to Get-WorkerPerfEvents and to the comparison with the start time of a process.
        $prevSampleUtc = ConvertTo-WorkerPerfUtc ([datetime]$prevSample.Time)
        $prevSnapUtc = ConvertTo-WorkerPerfUtc $prevSnapTime
        $lastSnapTryUtc = $prevSnapUtc
        $startUtc = ConvertTo-WorkerPerfUtc $scheduleStart
        $burstState = New-WorkerPerfBurstState
        $endAt = $(if ($DurationMinutes -gt 0) { $startUtc.AddMinutes($DurationMinutes) } else { [datetime]::MaxValue })
        $scheduled = $startUtc.AddSeconds($FastIntervalSeconds)
        $nextRegular = $startUtc.AddSeconds($IntervalSeconds)
        $lastEvents = $startTime
        $probeT = 0
        $sw = New-Object System.Diagnostics.Stopwatch
        # the last row written per print queue (its values without the time): a queue gets a row at its first appearance
        # and when a value changes (M6)
        $queueLast = @{}

        # The events since the cursor up to Until: Windows makes an event visible up to about a second after its time stamp,
        # so the regular reads end EventLagSeconds before now and the cursor moves to that bound (P1-R34); the read at the
        # end of the capture runs without that lag. Run with '.' in this scope.
        $eventLagSeconds = 5
        $readEvents = {
            param([datetime]$Until)
            if ((ConvertTo-WorkerPerfUtc $Until) -gt (ConvertTo-WorkerPerfUtc $lastEvents)) {
                try {
                    $newEvents = @(Select-WorkerPerfEventsInWindow -Events @(Get-WorkerPerfEvents -Since $lastEvents) -After $lastEvents -Until $Until)
                    if ($newEvents.Count -gt 0) {
                        $known = @()
                        if ($null -ne $procMemory) { $known = @(Get-WorkerPerfProcessMemoryEntries $procMemory) }
                        foreach ($ev in @(Complete-WorkerPerfEventSession -Events $newEvents -Processes $known `
                                    -Sessions @($lastSnap.Sessions) -MaxGapSeconds $eventGapSeconds)) {
                            $wEvents.WriteLine((ConvertTo-WorkerPerfEventRow $ev))
                        }
                    }
                    $lastEvents = $Until
                }
                catch { Register-SourceError 'events' $_ }
            }
            Register-SourceFailures
        }
        # The reads of the regular slot besides the snapshot: events since the cursor and the print queue counters. Run
        # with '.' in this scope. With a snapshot their time counts toward its measured duration (CollectMs).
        $readSlot = {
            if ($null -ne $wEvents) { . $readEvents ((Get-WorkerPerfNow).AddSeconds(-$eventLagSeconds)) }
            if ($null -ne $wQueues) {
                try {
                    $queueTime = Get-WorkerPerfNow
                    foreach ($q in @(Get-WorkerPerfPrintQueues)) {
                        if ($null -eq $q) { continue }
                        $row = ConvertTo-WorkerPerfPrintQueueRow $q $queueTime
                        $name = [string](Get-WorkerPerfField $q 'Queue')
                        $values = $row.Substring($row.IndexOf([char]',') + 1)
                        if ($queueLast.ContainsKey($name) -and $queueLast[$name] -eq $values) { continue }
                        $queueLast[$name] = $values
                        $wQueues.WriteLine($row)
                    }
                }
                catch { Register-SourceError 'printqueues' $_ }
            }
        }
        $eventsReady = $true

        while ($true) {
            if ($scheduled -gt $endAt) { $endReason = 'duration'; break }
            if (Wait-WorkerPerfTick -Until $scheduled.ToLocalTime() -StopFlagPath $stopFlag) { $endReason = 'stopflag'; break }

            # ---- fast cadence ----
            # A fast sample that fails is skipped: no row for this tick (the next one covers the longer interval), and the
            # snapshot that was due waits for the next tick.
            $sample = $null
            $sw.Restart()
            try { $sample = Get-WorkerPerfFastSample } catch { Register-SourceError 'fast' $_ }
            $sw.Stop()
            if ($null -ne $sample) {
                $T = $tickCount
                $now = ([datetime]$sample.Time).ToUniversalTime()       # as ConvertTo-WorkerPerfUtc, without a call per tick
                $bad = @(Get-WorkerPerfTriggerSignals -Sample $sample -Thresholds $thresholds -LogicalProcessors $cores -PhysicalMemoryMB $ramMB)
                $burstActive = Update-WorkerPerfBurstState -State $burstState -Now $now -BadSignals $bad -HoldSeconds $BurstHoldSeconds
                $rows = ConvertTo-WorkerPerfFastRows -Sample $sample -T $T -ElapsedSec ($now - $prevSampleUtc).TotalSeconds -Burst $burstActive `
                    -CollectMs $sw.Elapsed.TotalMilliseconds
                $wTicks.WriteLine($rows.Tick)
                if ($null -ne $wVolumes) { foreach ($line in $rows.Volumes) { $wVolumes.WriteLine($line) } }
                if ($null -ne $wShares) { foreach ($line in $rows.Shares) { $wShares.WriteLine($line) } }
                foreach ($line in $rows.InputSessions) { $wInput.WriteLine($line) }
                if ($null -ne $wInputProc) { foreach ($line in $rows.InputProcesses) { $wInputProc.WriteLine($line) } }
                foreach ($w in $fastWriters) { $w.Flush() }
                $prevSampleUtc = $now
                $tickCount++

                # Probe results carry the tick in which the probes were started.
                if ($null -ne $wProbes) {
                    $probeResults = @()
                    try { $probeResults = @(Receive-WorkerPerfProbes) } catch { Register-SourceError 'probes' $_ }
                    Write-WorkerPerfProbeRows $probeResults $probeT
                }

                # ---- snapshot ----
                # No burst snapshots before the first regular one: that one must be a keyframe.
                $due = Get-WorkerPerfSnapshotDue -Now $now -NextRegular $nextRegular -LastSnapshot $lastSnapTryUtc `
                    -BurstActive ($burstActive -and $regularCount -gt 0) -BurstIntervalSeconds $BurstIntervalSeconds
                if ($due -ne 'none') {
                    $regular = ($due -eq 'regular')
                    $keyframe = ($regular -and ($regularCount % 20) -eq 0)
                    $kind = $(if ($keyframe) { 'K' } elseif ($regular) { 'R' } else { 'B' })
                    $sw.Restart()
                    # A snapshot that fails is skipped; the next one comes at its usual time (a failed keyframe is made up
                    # for by the next regular snapshot). The service map of the last keyframe stays in use when its query fails.
                    if ($keyframe -and $withProcesses) { try { $services = Get-WorkerPerfServices } catch { Register-SourceError 'services' $_ } }
                    $snap = $null
                    try { $snap = Get-WorkerPerfSnapshot -Kind $kind } catch { Register-SourceError 'snapshot' $_ }
                    $lastSnapTryUtc = $now
                    if ($null -ne $snap) {
                        $P = $snapCount
                        # without Prozesse the columns Processes and RowsWritten of snapshots.csv stay empty
                        $procTotal = ''; $procWritten = ''
                        if ($withProcesses) {
                            $res = Get-WorkerPerfProcessRows -State $procState -Processes @($snap.Processes) -P $P -PrevTime $prevSnapTime `
                                -Keyframe:$keyframe -Services $services -IncludeCommandLine:$withCommandLine
                            foreach ($line in $res.Info) { $wInfo.WriteLine($line) }
                            foreach ($line in $res.Rows) { $wProcs.WriteLine($line) }
                            foreach ($line in $res.Ended) { $wEnded.WriteLine($line) }
                            $procTotal = $res.Total; $procWritten = $res.Rows.Count
                        }

                        $userSessions = 0; $activeSessions = 0
                        foreach ($s in @($snap.Sessions)) {
                            if ($null -eq $s) { continue }
                            if (-not [string]::IsNullOrEmpty([string]$s.User)) {
                                $userSessions++
                                if ([string]$s.State -eq 'Active') { $activeSessions++ }
                            }
                            $logon = ''
                            if ($s.LogonTime -is [datetime] -and $s.LogonTime -gt [datetime]::MinValue) { $logon = $s.LogonTime.ToString('o', $inv) }
                            $idle = ''
                            if ($null -ne $s.IdleSec -and [double]$s.IdleSec -ge 0) { $idle = Format-WorkerPerfNumber $s.IdleSec 0 }
                            $wSessions.WriteLine([string]::Concat($P, ',', $s.SessionId, ',', (Format-WorkerPerfCsvText ([string]$s.User)), ',',
                                    (Format-WorkerPerfCsvText ([string]$s.Domain)), ',', (Format-WorkerPerfCsvText ([string]$s.State)), ',',
                                    (Format-WorkerPerfCsvText ([string]$s.WinStation)), ',', (Format-WorkerPerfCsvText ([string]$s.ClientName)), ',', $logon, ',', $idle))
                        }
                        foreach ($c in @($snap.Citrix)) {
                            if ($null -eq $c -or $null -eq $wCitrix) { continue }
                            $wCitrix.WriteLine([string]::Concat($T, ',', (Format-WorkerPerfCsvText ([string]$c.Source)), ',', (Format-WorkerPerfCsvText ([string]$c.SessionId)), ',',
                                    (Format-WorkerPerfCsvText ([string]$c.Instance)), ',', (Format-WorkerPerfCsvText ([string]$c.Metric)), ',', (Format-WorkerPerfNumber $c.Value 2)))
                        }

                        $snapTime = [datetime]$snap.Time
                        $snapUtc = $snapTime.ToUniversalTime()
                        $lastSnap = $snap
                        if ($withProcesses) { Update-WorkerPerfProcessMemory -Memory $procMemory -Processes @($snap.Processes) -Time $snapTime }
                        if ($regular) { . $readSlot }
                        $sw.Stop()
                        $wSnaps.WriteLine([string]::Concat($P, ',', $T, ',', $snapTime.ToString('o', $inv), ',', (Format-WorkerPerfNumber ($snapUtc - $prevSnapUtc).TotalSeconds 3), ',',
                                $kind, ',', $userSessions, ',', $activeSessions, ',', $procTotal, ',', $procWritten, ',', (Format-WorkerPerfNumber $sw.Elapsed.TotalMilliseconds 0)))
                        $prevSnapTime = $snapTime
                        $prevSnapUtc = $snapUtc
                        $snapCount++
                        if ($regular) { $regularCount++ }
                    }

                    if ($regular) {
                        # probes, events and print queues belong to the regular slot, with or without its snapshot (with it,
                        # the events and queues were read above, inside its measured duration)
                        if ($null -eq $snap) { . $readSlot }
                        if ($null -ne $wProbes) { try { Start-WorkerPerfProbes; $probeT = $T } catch { Register-SourceError 'probes' $_ } }
                        $nextRegular = (Get-WorkerPerfNextTick -Scheduled $nextRegular -Now $now -IntervalSeconds $IntervalSeconds).Next
                    }
                    foreach ($w in $allWriters) { $w.Flush() }

                    if ($regular) {
                        # Folder size from the open streams; the other files (meta.json, thresholds.json) are small.
                        $bytes = 0.0
                        foreach ($w in $allWriters) { $bytes += [double]$w.BaseStream.Length }
                        # without a reading of the free space only the size limit is checked
                        $freeMB = [double]::MaxValue
                        try { $freeMB = [double](Get-WorkerPerfFreeSpaceMB -Path $runDir) } catch { Register-SourceError 'diskspace' $_ }
                        $guard = Test-WorkerPerfGuard -FreeMB $freeMB -SizeMB ($bytes / 1MB) -MaxSizeMB $MaxSizeMB -Phase run
                        if ($guard) {
                            $endReason = $guard
                            Write-Warning $(if ($guard -eq 'maxsize') { "Aufzeichnung beendet: Ordnergroesse $MaxSizeMB MB erreicht." } else { 'Aufzeichnung beendet: weniger als 200 MB Speicherplatz frei.' })
                            break
                        }
                    }
                }
            }

            $next = Get-WorkerPerfNextTick -Scheduled $scheduled -Now (Get-WorkerPerfNow).ToUniversalTime() -IntervalSeconds $FastIntervalSeconds
            $skipped += $next.Skipped
            $scheduled = $next.Next
        }

        # Give the probes started last one more fast tick so that their results are not lost. The wait exists only for the
        # probes: without Gegenstellen the capture ends one fast interval earlier, on purpose.
        if ($null -ne $wProbes) {
            [void](Wait-WorkerPerfTick -Until (ConvertTo-WorkerPerfUtc (Get-WorkerPerfNow)).AddSeconds($FastIntervalSeconds).ToLocalTime() -StopFlagPath '')
            $probeResults = @()
            try { $probeResults = @(Receive-WorkerPerfProbes) } catch { Register-SourceError 'probes' $_ }
            Write-WorkerPerfProbeRows $probeResults $probeT
        }
    }
}
catch {
    # Ctrl+C is no error of the capture: the cleanup below records it as 'interrupted'.
    if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { throw }
    $endReason = 'error'
    $endMessage = [string]$_.Exception.Message
    Write-Warning "Aufzeichnung mit Fehler beendet: $endMessage"
    throw
}
finally {
    # The cleanup must not replace the error that ended the capture: each step is guarded, its failure is reported
    # as a warning after the message above, and the original error leaves the script.
    $problems = New-Object System.Collections.Generic.List[string]
    # One last read of the events, without lag, before the files are closed: however the capture ends (its duration,
    # stop.flag, a limit, an error, Ctrl+C as far as the cleanup runs), the events of its last seconds are in it (P1-R34).
    if ($eventsReady -and $null -ne $wEvents) {
        try { . $readEvents (Get-WorkerPerfNow); $wEvents.Flush() }
        catch {
            # a second Ctrl+C stops this read too; that is no failure to report
            if ($_.Exception -isnot [System.Management.Automation.PipelineStoppedException]) { $problems.Add('letzter Abruf der Ereignisse fehlgeschlagen: ' + $_.Exception.Message) }
        }
    }
    foreach ($w in $allWriters) { try { $w.Dispose() } catch { Write-Verbose $_.Exception.Message } }
    if (-not $endReason) { $endReason = 'interrupted' }
    try {
        $meta.EndTime = (Get-WorkerPerfNow).ToString('o', $inv)
        $meta.EndReason = $endReason
        $meta.EndMessage = $endMessage
        $meta.Ticks = $tickCount
        $meta.Snapshots = $snapCount
        $meta.SkippedTicks = $skipped
        Save-Meta
    }
    catch { $problems.Add('meta.json konnte nicht abgeschlossen werden: ' + $_.Exception.Message) }
    if ($Simulate -and -not $HealthOnly) {
        try {
            $expected = @(Get-WorkerPerfExpected)
            [IO.File]::WriteAllText((Join-Path $runDir 'expected.json'), (ConvertTo-Json -InputObject $expected -Depth 4), $utf8)
        }
        catch { $problems.Add('expected.json konnte nicht geschrieben werden: ' + $_.Exception.Message) }
    }
    if (Test-Path -LiteralPath $stopFlag) { Remove-Item -LiteralPath $stopFlag -Force -ErrorAction SilentlyContinue }
    foreach ($p in $problems) { Write-Warning "Abschluss der Aufzeichnung unvollstaendig: $p" }
    if ($HealthOnly) {
        # the end reason as in the capture's last line when the quick run did not end by itself
        if ($endReason -ne 'healthonly') { Write-Host "Schnelllauf beendet ($endReason): $runDir" }
        elseif ($noHealth) {
            Write-Warning $noHealth
            Write-Host "Schnelllauf beendet ohne Zustandsbild: $runDir"
        }
        else { Write-Host "Schnelllauf beendet: $runDir" }
    }
    else { Write-Host "Aufzeichnung beendet ($endReason): $tickCount Takte, $snapCount Schnappschuesse in $runDir" }
}

#endregion

# Emit the run folder so callers can pipe it into New-WorkerPerfReport.ps1
$runDir
