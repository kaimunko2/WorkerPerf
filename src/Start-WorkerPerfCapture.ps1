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
          with each regular snapshot also endpoint probes (probes.csv), events (events.csv) and the
          counters of the print queues (printqueues.csv)

    At the start the events of the last -EventLookbackDays days go to events_before.csv and the
    installed print drivers to printdrivers.csv.

    While a trigger signal of thresholds.json is over its threshold (and -BurstHoldSeconds
    afterwards) snapshots are taken every -BurstIntervalSeconds. Every 20th regular snapshot
    is a keyframe that lists every process; the others only list active processes.

    The run folder also holds a copy of thresholds.json and meta.json (host facts, settings,
    end reason); in the simulation additionally expected.json (the expected analysis result).

    Stop the capture with Ctrl+C, by -DurationMinutes, by -MaxSizeMB, or by creating a file
    named 'stop.flag' inside the run folder. Analyse the result with New-WorkerPerfReport.ps1.

    A call of the data source that fails does not end the capture: the tick or snapshot is
    skipped, one warning per source is shown, and meta.json counts the failures per source
    (SourceErrors). If the capture itself ends on an error, meta.json says so (EndReason
    'error', EndMessage).

.PARAMETER OutputPath
    Base folder. A sub folder <COMPUTER>_<yyyyMMdd-HHmmss> is created per capture.

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

.PARAMETER IncludeCommandLine
    Also store process command lines (may contain sensitive data such as file names or URLs).

.PARAMETER NoCitrix
    Skip the Citrix ICA/EUEM WMI metrics.

.PARAMETER CitrixMetricFilter
    Regular expression selecting which numeric Citrix WMI properties are recorded.

.PARAMETER EventLookbackDays
    At the start, read the events of this many days before the start into events_before.csv
    (0-90, default 7; 0 = no lookback). Where a log reaches the cap of the lookback, meta.json
    names it (LookbackCapped).

.PARAMETER Simulate
    Replay the scripted 60-minute scenario instead of reading the local system (no waiting
    between ticks, runs on any platform). Used for demos and tests.

.EXAMPLE
    .\Start-WorkerPerfCapture.ps1 -OutputPath D:\WorkerPerf -DurationMinutes 240

.EXAMPLE
    .\Start-WorkerPerfCapture.ps1 -Simulate -DurationMinutes 60 -OutputPath .\demo
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
    [switch]$IncludeCommandLine,
    [switch]$NoCitrix,
    [string]$CitrixMetricFilter = 'Latency|Round|Bandwidth|FramesPerSecond|Fps',
    [ValidateRange(0, 90)][int]$EventLookbackDays = 7,
    [switch]$Simulate
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
. (Join-Path $PSScriptRoot 'WorkerPerf.Capture.ps1')
if ($Simulate) {
    if ($DurationMinutes -lt 60) { throw '-Simulate erfordert -DurationMinutes von mindestens 60 (das Drehbuch dauert 60 Minuten).' }
    . (Join-Path $PSScriptRoot 'WorkerPerf.Sources.Simulation.ps1')
}
else {
    if (-not (Test-WorkerPerfWindows)) { throw 'Die Aufzeichnung realer Daten ist nur unter Windows moeglich. Fuer Testdaten -Simulate verwenden.' }
    . (Join-Path $PSScriptRoot 'WorkerPerf.EventConfig.ps1')
    . (Join-Path $PSScriptRoot 'WorkerPerf.Sources.Windows.ps1')
}

if (-not $ThresholdFile) { $ThresholdFile = Join-Path $PSScriptRoot 'thresholds.json' }
if (-not $EndpointFile) { $EndpointFile = Join-Path $PSScriptRoot 'endpoints.json' }
if (-not $OutputPath) {
    $OutputPath = $(if ($env:ProgramData) { Join-Path $env:ProgramData 'WorkerPerf' } else { Join-Path (Get-Location).Path 'WorkerPerfData' })
}

$inv = [Globalization.CultureInfo]::InvariantCulture
$thresholds = Read-WorkerPerfThresholds $ThresholdFile
$endpoints = @(Read-WorkerPerfEndpoints $EndpointFile)

$source = Initialize-WorkerPerfSource -StartTime (Get-Date) -Endpoints $endpoints -CitrixMetricFilter $CitrixMetricFilter `
    -IncludeCommandLine:$IncludeCommandLine -NoCitrix:$NoCitrix
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

$writers = New-WorkerPerfWriters -RunDir $runDir
$wTicks = $writers['ticks.csv']; $wVolumes = $writers['volumes.csv']; $wShares = $writers['shares.csv']
$wInput = $writers['inputdelay.csv']; $wInputProc = $writers['inputdelay_proc.csv']; $wCitrix = $writers['citrix.csv']
$wProbes = $writers['probes.csv']; $wEvents = $writers['events.csv']; $wSnaps = $writers['snapshots.csv']
$wSessions = $writers['sessions.csv']; $wInfo = $writers['procinfo.csv']; $wProcs = $writers['processes.csv']
$wEnded = $writers['procend.csv']
$wEventsBefore = $writers['events_before.csv']; $wDrivers = $writers['printdrivers.csv']; $wQueues = $writers['printqueues.csv']
$fastWriters = @($wTicks, $wVolumes, $wShares, $wInput, $wInputProc)
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
    IncludeCommandLine   = [bool]$IncludeCommandLine
    EventLookbackDays    = $EventLookbackDays
    LookbackCapped       = @()
    CollectorPid         = $source.CollectorPid
    Endpoints            = @($source.Endpoints)
    Sources              = $source.Sources
    SourceErrors         = [ordered]@{}
}
function Save-Meta {
    Save-WorkerPerfMeta -Path (Join-Path $runDir 'meta.json') -Meta $meta
}

# A failing call of the data source: counted per source in meta.json, one warning per source, the capture goes on.
$sourceNames = @{ fast = 'schneller Takt'; snapshot = 'Prozess-Schnappschuss'; services = 'Dienste'; probes = 'Antwortzeit-Proben'
    events = 'Ereignisprotokoll'; diskspace = 'freier Speicherplatz'; eventsbefore = 'Ereignisse vor der Messung'
    printdrivers = 'Druckertreiber'; printqueues = 'Druckwarteschlangen' }
function Register-SourceError([string]$Source, $ErrorRecord) {
    # Ctrl+C is not a failure of the source
    if ($ErrorRecord.Exception -is [System.Management.Automation.PipelineStoppedException]) { throw $ErrorRecord.Exception }
    $message = [string]$ErrorRecord.Exception.Message
    if (Add-WorkerPerfSourceError -Errors $meta.SourceErrors -Source $Source -Time (Get-WorkerPerfNow) -Message $message) {
        Write-Warning ("Datenquelle '{0}' meldet einen Fehler; die Aufzeichnung laeuft weiter, weitere Fehler dieser Quelle werden nur gezaehlt: {1}" -f $sourceNames[$Source], $message)
        # saved at once, so the failure is on record even if the capture is killed later
        try { Save-Meta } catch { Write-Verbose $_.Exception.Message }
    }
}

#endregion

#region ---------- capture loop -----------------------------------------------------------

function Write-WorkerPerfProbeRows([object[]]$Results, [int]$T) {
    foreach ($r in $Results) {
        if ($null -eq $r) { continue }
        $wProbes.WriteLine((ConvertTo-WorkerPerfProbeRow -Result $r -T $T))
    }
}

Write-Host "WorkerPerf-Aufzeichnung laeuft: $runDir"
Write-Host ("Schneller Takt {0} s, Schnappschuss alle {1} s{2}. Beenden mit Strg+C oder Datei 'stop.flag' im Ausgabeordner." -f `
        $FastIntervalSeconds, $IntervalSeconds, $(if ($DurationMinutes -gt 0) { ", Dauer $DurationMinutes min" } else { '' }))

$endReason = $null
$endMessage = $null
$tickCount = 0
$snapCount = 0
$regularCount = 0
$skipped = 0
try {
    [void](Copy-Item -LiteralPath $ThresholdFile -Destination (Join-Path $runDir 'thresholds.json'))
    Save-Meta

    # Lookback up to the start: events after the start belong to the measurement (Get-WorkerPerfEvents reads from
    # Since = start on), so a source that returns later ones does not count them twice.
    if ($EventLookbackDays -gt 0) {
        try {
            $before = Get-WorkerPerfEventsBefore -Days $EventLookbackDays -Until $startTime
            foreach ($ev in @($before.Events)) {
                $evTime = Get-WorkerPerfField $ev 'Time'
                if (-not ($evTime -is [datetime]) -or $evTime -gt $startTime) { continue }
                $wEventsBefore.WriteLine((ConvertTo-WorkerPerfEventRow $ev))
            }
            $meta.LookbackCapped = @(@($before.Capped) | Where-Object { -not [string]::IsNullOrEmpty([string]$_) } | ForEach-Object { [string]$_ })
            if ($meta.LookbackCapped.Count -gt 0) { Save-Meta }
        }
        catch { Register-SourceError 'eventsbefore' $_ }
        $wEventsBefore.Flush()
    }
    try { foreach ($d in @(Get-WorkerPerfPrintDrivers)) { if ($null -ne $d) { $wDrivers.WriteLine((ConvertTo-WorkerPerfPrintDriverRow $d)) } } }
    catch { Register-SourceError 'printdrivers' $_ }
    $wDrivers.Flush()

    # Baseline: one fast sample to establish the cumulative counters, one snapshot to book every process.
    $prevSample = Get-WorkerPerfFastSample
    $services = Get-WorkerPerfServices
    $procState = New-WorkerPerfProcessState
    $base = Get-WorkerPerfSnapshot -Kind K
    [void](Get-WorkerPerfProcessRows -State $procState -Processes @($base.Processes) -P -1 -PrevTime $base.Time -Services $services `
            -IncludeCommandLine:$IncludeCommandLine)
    $prevSnapTime = [datetime]$base.Time
    # the last snapshot that succeeded: the session of an event is found through its process id there
    $lastSnap = $base

    # Scheduling and durations are computed in UTC, so a step of the local clock (end of daylight saving time) neither
    # stalls the capture nor distorts ElapsedSec. The source keeps its own local times: they go to the files, to
    # Wait-WorkerPerfTick, to Get-WorkerPerfEvents and to the comparison with the start time of a process.
    $prevSampleUtc = ConvertTo-WorkerPerfUtc ([datetime]$prevSample.Time)
    $prevSnapUtc = ConvertTo-WorkerPerfUtc $prevSnapTime
    $lastSnapTryUtc = $prevSnapUtc
    $startUtc = ConvertTo-WorkerPerfUtc $startTime
    $burstState = New-WorkerPerfBurstState
    $endAt = $(if ($DurationMinutes -gt 0) { $startUtc.AddMinutes($DurationMinutes) } else { [datetime]::MaxValue })
    $scheduled = $startUtc.AddSeconds($FastIntervalSeconds)
    $nextRegular = $startUtc.AddSeconds($IntervalSeconds)
    $lastEvents = $startTime
    $probeT = 0
    $sw = New-Object System.Diagnostics.Stopwatch

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
            foreach ($line in $rows.Volumes) { $wVolumes.WriteLine($line) }
            foreach ($line in $rows.Shares) { $wShares.WriteLine($line) }
            foreach ($line in $rows.InputSessions) { $wInput.WriteLine($line) }
            foreach ($line in $rows.InputProcesses) { $wInputProc.WriteLine($line) }
            foreach ($w in $fastWriters) { $w.Flush() }
            $prevSampleUtc = $now
            $tickCount++

            # Probe results carry the tick in which the probes were started.
            $probeResults = @()
            try { $probeResults = @(Receive-WorkerPerfProbes) } catch { Register-SourceError 'probes' $_ }
            Write-WorkerPerfProbeRows $probeResults $probeT

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
                if ($keyframe) { try { $services = Get-WorkerPerfServices } catch { Register-SourceError 'services' $_ } }
                $snap = $null
                try { $snap = Get-WorkerPerfSnapshot -Kind $kind } catch { Register-SourceError 'snapshot' $_ }
                $lastSnapTryUtc = $now
                if ($null -ne $snap) {
                    $P = $snapCount
                    $res = Get-WorkerPerfProcessRows -State $procState -Processes @($snap.Processes) -P $P -PrevTime $prevSnapTime `
                        -Keyframe:$keyframe -Services $services -IncludeCommandLine:$IncludeCommandLine
                    foreach ($line in $res.Info) { $wInfo.WriteLine($line) }
                    foreach ($line in $res.Rows) { $wProcs.WriteLine($line) }
                    foreach ($line in $res.Ended) { $wEnded.WriteLine($line) }

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
                        if ($null -eq $c) { continue }
                        $wCitrix.WriteLine([string]::Concat($T, ',', (Format-WorkerPerfCsvText ([string]$c.Source)), ',', (Format-WorkerPerfCsvText ([string]$c.SessionId)), ',',
                                (Format-WorkerPerfCsvText ([string]$c.Instance)), ',', (Format-WorkerPerfCsvText ([string]$c.Metric)), ',', (Format-WorkerPerfNumber $c.Value 2)))
                    }

                    $snapTime = [datetime]$snap.Time
                    $snapUtc = $snapTime.ToUniversalTime()
                    $sw.Stop()
                    $wSnaps.WriteLine([string]::Concat($P, ',', $T, ',', $snapTime.ToString('o', $inv), ',', (Format-WorkerPerfNumber ($snapUtc - $prevSnapUtc).TotalSeconds 3), ',',
                            $kind, ',', $userSessions, ',', $activeSessions, ',', $res.Total, ',', $res.Rows.Count, ',', (Format-WorkerPerfNumber $sw.Elapsed.TotalMilliseconds 0)))
                    $prevSnapTime = $snapTime
                    $prevSnapUtc = $snapUtc
                    $snapCount++
                    if ($regular) { $regularCount++ }
                    $lastSnap = $snap
                }

                if ($regular) {
                    # probes and events belong to the regular slot, with or without its snapshot
                    try { Start-WorkerPerfProbes; $probeT = $T } catch { Register-SourceError 'probes' $_ }
                    $eventsUntil = Get-WorkerPerfNow
                    try {
                        $newEvents = @(Get-WorkerPerfEvents -Since $lastEvents | Where-Object { $null -ne $_ })
                        if ($newEvents.Count -gt 0) {
                            foreach ($ev in @(Complete-WorkerPerfEventSession -Events $newEvents -Processes @($lastSnap.Processes) -Sessions @($lastSnap.Sessions))) {
                                $wEvents.WriteLine((ConvertTo-WorkerPerfEventRow $ev))
                            }
                        }
                        $lastEvents = $eventsUntil
                    }
                    catch { Register-SourceError 'events' $_ }
                    try {
                        $queueTime = Get-WorkerPerfNow
                        foreach ($q in @(Get-WorkerPerfPrintQueues)) { if ($null -ne $q) { $wQueues.WriteLine((ConvertTo-WorkerPerfPrintQueueRow $q $queueTime)) } }
                    }
                    catch { Register-SourceError 'printqueues' $_ }
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

    # Give the probes started last one more fast tick so that their results are not lost.
    [void](Wait-WorkerPerfTick -Until (ConvertTo-WorkerPerfUtc (Get-WorkerPerfNow)).AddSeconds($FastIntervalSeconds).ToLocalTime() -StopFlagPath '')
    $probeResults = @()
    try { $probeResults = @(Receive-WorkerPerfProbes) } catch { Register-SourceError 'probes' $_ }
    Write-WorkerPerfProbeRows $probeResults $probeT
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
    if ($Simulate) {
        try {
            $expected = @(Get-WorkerPerfExpected)
            [IO.File]::WriteAllText((Join-Path $runDir 'expected.json'), (ConvertTo-Json -InputObject $expected -Depth 4), $utf8)
        }
        catch { $problems.Add('expected.json konnte nicht geschrieben werden: ' + $_.Exception.Message) }
    }
    if (Test-Path -LiteralPath $stopFlag) { Remove-Item -LiteralPath $stopFlag -Force -ErrorAction SilentlyContinue }
    foreach ($p in $problems) { Write-Warning "Abschluss der Aufzeichnung unvollstaendig: $p" }
    Write-Host "Aufzeichnung beendet ($endReason): $tickCount Takte, $snapCount Schnappschuesse in $runDir"
}

#endregion

# Emit the run folder so callers can pipe it into New-WorkerPerfReport.ps1
$runDir
