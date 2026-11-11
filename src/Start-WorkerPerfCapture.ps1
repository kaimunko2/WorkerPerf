#Requires -Version 5.1
<#
.SYNOPSIS
    Records performance and resource usage of a Citrix multi-session VDA (terminal server worker)
    down to individual sessions and processes.

.DESCRIPTION
    Measures in two cadences and writes a run folder in capture format 2:

      fast cadence (-FastIntervalSeconds, default 2 s): host signals, volumes, file shares and
          input delay per session and per process (ticks.csv, volumes.csv, shares.csv,
          inputdelay.csv, inputdelay_proc.csv)
      snapshots (-IntervalSeconds, default 15 s): processes, sessions and Citrix metrics
          (snapshots.csv, processes.csv, procinfo.csv, procend.csv, sessions.csv, citrix.csv),
          with each regular snapshot also endpoint probes (probes.csv) and events (events.csv)

    While a trigger signal of thresholds.json is over its threshold (and -BurstHoldSeconds
    afterwards) snapshots are taken every -BurstIntervalSeconds. Every 20th regular snapshot
    is a keyframe that lists every process; the others only list active processes.

    The run folder also holds a copy of thresholds.json and meta.json (host facts, settings,
    end reason); in the simulation additionally expected.json (the expected analysis result).

    Stop the capture with Ctrl+C, by -DurationMinutes, by -MaxSizeMB, or by creating a file
    named 'stop.flag' inside the run folder. Analyse the result with New-WorkerPerfReport.ps1.

.PARAMETER OutputPath
    Base folder. A sub folder <COMPUTER>_<yyyyMMdd-HHmmss> is created per capture.

.PARAMETER FastIntervalSeconds
    Fast cadence for host signals and input delay (1-60 s, default 2).

.PARAMETER IntervalSeconds
    Regular snapshot interval for processes and sessions (5-3600 s, default 15).

.PARAMETER BurstIntervalSeconds
    Snapshot interval while a trigger signal is over its threshold (default 5).

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
    [switch]$Simulate
)

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
    . (Join-Path $PSScriptRoot 'WorkerPerf.Sources.Windows.ps1')
}
if (-not (Get-Command -Name 'Initialize-WorkerPerfSource' -CommandType Function -ErrorAction SilentlyContinue)) {
    throw 'Die Windows-Datenquelle ist noch nicht fertiggestellt. Bis dahin ist nur die Simulation (-Simulate) moeglich.'
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
$runDir = (Resolve-Path -LiteralPath $runDir).Path
$stopFlag = Join-Path $runDir 'stop.flag'

$guard = Test-WorkerPerfGuard -FreeMB (Get-WorkerPerfFreeSpaceMB -Path $runDir) -SizeMB 0 -MaxSizeMB $MaxSizeMB -Phase start
if ($guard) { throw "Aufzeichnung nicht gestartet: zu wenig freier Speicherplatz unter $runDir (unter 200 MB)." }

$writers = New-WorkerPerfWriters -RunDir $runDir
$wTicks = $writers['ticks.csv']; $wVolumes = $writers['volumes.csv']; $wShares = $writers['shares.csv']
$wInput = $writers['inputdelay.csv']; $wInputProc = $writers['inputdelay_proc.csv']; $wCitrix = $writers['citrix.csv']
$wProbes = $writers['probes.csv']; $wEvents = $writers['events.csv']; $wSnaps = $writers['snapshots.csv']
$wSessions = $writers['sessions.csv']; $wInfo = $writers['procinfo.csv']; $wProcs = $writers['processes.csv']
$wEnded = $writers['procend.csv']
$fastWriters = @($wTicks, $wVolumes, $wShares, $wInput, $wInputProc)
$allWriters = @($writers.Values)

$utf8 = New-Object System.Text.UTF8Encoding $false
$meta = [ordered]@{
    SchemaVersion        = 2
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
    Ticks                = 0
    Snapshots            = 0
    SkippedTicks         = 0
    Simulated            = [bool]$Simulate
    IncludeCommandLine   = [bool]$IncludeCommandLine
    CollectorPid         = $source.CollectorPid
    Endpoints            = @($source.Endpoints)
    Sources              = $source.Sources
}
function Save-Meta {
    [IO.File]::WriteAllText((Join-Path $runDir 'meta.json'), (ConvertTo-Json -InputObject $meta -Depth 6), $utf8)
}

#endregion

#region ---------- capture loop -----------------------------------------------------------

function Write-WorkerPerfProbeRows([object[]]$Results, [int]$T) {
    foreach ($r in $Results) {
        if ($null -eq $r) { continue }
        $err = [string]$r.Error
        $ms = $(if ([string]::IsNullOrEmpty($err)) { Format-WorkerPerfNumber $r.ConnectMs 1 } else { '' })
        $wProbes.WriteLine([string]::Concat($T, ',', (Format-WorkerPerfCsvText ([string]$r.Name)), ',', (Format-WorkerPerfCsvText ([string]$r.Role)), ',',
                (Format-WorkerPerfCsvText ([string]$r.Host)), ',', [string]$r.Port, ',', $ms, ',', (Format-WorkerPerfCsvText $err)))
    }
}

Write-Host "WorkerPerf-Aufzeichnung laeuft: $runDir"
Write-Host ("Schneller Takt {0} s, Schnappschuss alle {1} s{2}. Beenden mit Strg+C oder Datei 'stop.flag' im Ausgabeordner." -f `
        $FastIntervalSeconds, $IntervalSeconds, $(if ($DurationMinutes -gt 0) { ", Dauer $DurationMinutes min" } else { '' }))

$endReason = $null
$tickCount = 0
$snapCount = 0
$regularCount = 0
$skipped = 0
try {
    [void](Copy-Item -LiteralPath $ThresholdFile -Destination (Join-Path $runDir 'thresholds.json'))
    Save-Meta

    # Baseline: one fast sample to establish the cumulative counters, one snapshot to book every process.
    $prevSample = Get-WorkerPerfFastSample
    $prevSampleTime = [datetime]$prevSample.Time
    $services = Get-WorkerPerfServices
    $procState = New-WorkerPerfProcessState
    $base = Get-WorkerPerfSnapshot
    [void](Get-WorkerPerfProcessRows -State $procState -Processes @($base.Processes) -P -1 -PrevTime $base.Time -Services $services `
            -IncludeCommandLine:$IncludeCommandLine)
    $prevSnapTime = [datetime]$base.Time

    $burstState = New-WorkerPerfBurstState
    $endAt = $(if ($DurationMinutes -gt 0) { $startTime.AddMinutes($DurationMinutes) } else { [datetime]::MaxValue })
    $scheduled = $startTime.AddSeconds($FastIntervalSeconds)
    $nextRegular = $startTime.AddSeconds($IntervalSeconds)
    $lastEvents = $startTime
    $probeT = 0
    $sw = New-Object System.Diagnostics.Stopwatch

    while ($true) {
        if ($scheduled -gt $endAt) { $endReason = 'duration'; break }
        if (Wait-WorkerPerfTick -Until $scheduled -StopFlagPath $stopFlag) { $endReason = 'stopflag'; break }

        # ---- fast cadence ----
        $T = $tickCount
        $sw.Restart()
        $sample = Get-WorkerPerfFastSample
        $sw.Stop()
        $now = [datetime]$sample.Time
        $bad = @(Get-WorkerPerfTriggerSignals -Sample $sample -Thresholds $thresholds -LogicalProcessors $cores -PhysicalMemoryMB $ramMB)
        $burstActive = Update-WorkerPerfBurstState -State $burstState -Now $now -BadSignals $bad -HoldSeconds $BurstHoldSeconds
        $rows = ConvertTo-WorkerPerfFastRows -Sample $sample -T $T -ElapsedSec ($now - $prevSampleTime).TotalSeconds -Burst $burstActive `
            -CollectMs $sw.Elapsed.TotalMilliseconds
        $wTicks.WriteLine($rows.Tick)
        foreach ($line in $rows.Volumes) { $wVolumes.WriteLine($line) }
        foreach ($line in $rows.Shares) { $wShares.WriteLine($line) }
        foreach ($line in $rows.InputSessions) { $wInput.WriteLine($line) }
        foreach ($line in $rows.InputProcesses) { $wInputProc.WriteLine($line) }
        foreach ($w in $fastWriters) { $w.Flush() }
        $prevSampleTime = $now
        $tickCount++

        # Probe results carry the tick in which the probes were started.
        Write-WorkerPerfProbeRows @(Receive-WorkerPerfProbes) $probeT

        # ---- snapshot ----
        # No burst snapshots before the first regular one: that one must be a keyframe.
        $due = Get-WorkerPerfSnapshotDue -Now $now -NextRegular $nextRegular -LastSnapshot $prevSnapTime `
            -BurstActive ($burstActive -and $regularCount -gt 0) -BurstIntervalSeconds $BurstIntervalSeconds
        if ($due -ne 'none') {
            $regular = ($due -eq 'regular')
            $keyframe = ($regular -and ($regularCount % 20) -eq 0)
            $sw.Restart()
            if ($keyframe) { $services = Get-WorkerPerfServices }
            $snap = Get-WorkerPerfSnapshot
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
            $kind = $(if ($keyframe) { 'K' } elseif ($regular) { 'R' } else { 'B' })
            $sw.Stop()
            $wSnaps.WriteLine([string]::Concat($P, ',', $T, ',', $snapTime.ToString('o', $inv), ',', (Format-WorkerPerfNumber ($snapTime - $prevSnapTime).TotalSeconds 3), ',',
                    $kind, ',', $userSessions, ',', $activeSessions, ',', $res.Total, ',', $res.Rows.Count, ',', (Format-WorkerPerfNumber $sw.Elapsed.TotalMilliseconds 0)))
            $prevSnapTime = $snapTime
            $snapCount++

            if ($regular) {
                $regularCount++
                Start-WorkerPerfProbes
                $probeT = $T
                $eventsUntil = Get-WorkerPerfNow
                foreach ($ev in @(Get-WorkerPerfEvents -Since $lastEvents)) {
                    if ($null -eq $ev) { continue }
                    $wEvents.WriteLine([string]::Concat(([datetime]$ev.Time).ToString('o', $inv), ',', (Format-WorkerPerfCsvText ([string]$ev.Source)), ',',
                            [string]$ev.EventId, ',', (Format-WorkerPerfCsvText ([string]$ev.Kind)), ',', (Format-WorkerPerfCsvText ([string]$ev.Text))))
                }
                $lastEvents = $eventsUntil
                $nextRegular = (Get-WorkerPerfNextTick -Scheduled $nextRegular -Now $now -IntervalSeconds $IntervalSeconds).Next
            }
            foreach ($w in $allWriters) { $w.Flush() }

            if ($regular) {
                # Folder size from the open streams; the other files (meta.json, thresholds.json) are small.
                $bytes = 0.0
                foreach ($w in $allWriters) { $bytes += [double]$w.BaseStream.Length }
                $guard = Test-WorkerPerfGuard -FreeMB (Get-WorkerPerfFreeSpaceMB -Path $runDir) -SizeMB ($bytes / 1MB) -MaxSizeMB $MaxSizeMB -Phase run
                if ($guard) {
                    $endReason = $guard
                    Write-Warning $(if ($guard -eq 'maxsize') { "Aufzeichnung beendet: Ordnergroesse $MaxSizeMB MB erreicht." } else { 'Aufzeichnung beendet: weniger als 200 MB Speicherplatz frei.' })
                    break
                }
            }
        }

        $next = Get-WorkerPerfNextTick -Scheduled $scheduled -Now (Get-WorkerPerfNow) -IntervalSeconds $FastIntervalSeconds
        $skipped += $next.Skipped
        $scheduled = $next.Next
    }

    # Give the probes started last one more fast tick so that their results are not lost.
    [void](Wait-WorkerPerfTick -Until ((Get-WorkerPerfNow).AddSeconds($FastIntervalSeconds)) -StopFlagPath '')
    Write-WorkerPerfProbeRows @(Receive-WorkerPerfProbes) $probeT
}
finally {
    foreach ($w in $allWriters) { try { $w.Dispose() } catch { Write-Verbose $_.Exception.Message } }
    if (-not $endReason) { $endReason = 'interrupted' }
    $meta.EndTime = (Get-WorkerPerfNow).ToString('o', $inv)
    $meta.EndReason = $endReason
    $meta.Ticks = $tickCount
    $meta.Snapshots = $snapCount
    $meta.SkippedTicks = $skipped
    Save-Meta
    if ($Simulate) {
        $expected = @(Get-WorkerPerfExpected)
        [IO.File]::WriteAllText((Join-Path $runDir 'expected.json'), (ConvertTo-Json -InputObject $expected -Depth 4), $utf8)
    }
    if (Test-Path -LiteralPath $stopFlag) { Remove-Item -LiteralPath $stopFlag -Force -ErrorAction SilentlyContinue }
    Write-Host "Aufzeichnung beendet ($endReason): $tickCount Takte, $snapCount Schnappschuesse in $runDir"
}

#endregion

# Emit the run folder so callers can pipe it into New-WorkerPerfReport.ps1
$runDir
