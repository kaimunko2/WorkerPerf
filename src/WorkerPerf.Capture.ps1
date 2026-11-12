#Requires -Version 5.1
# WorkerPerf capture logic: turns a process list into compact CSV rows (library, definitions only).
# Requires WorkerPerf.Common.ps1 to be loaded first (Format-WorkerPerfCsvText).

function New-WorkerPerfProcessState {
    # NextKey: next process number K. Procs: process key -> booked counters.
    return @{ NextKey = 0; Procs = @{} }
}

function Get-WorkerPerfProcessRows {
    param($State, [AllowEmptyCollection()][object[]]$Processes, [int]$P, [datetime]$PrevTime, [switch]$Keyframe,
          [hashtable]$Services = @{}, [switch]$IncludeCommandLine)

    $rows = [System.Collections.Generic.List[string]]::new()
    $info = [System.Collections.Generic.List[string]]::new()
    $ended = [System.Collections.Generic.List[string]]::new()
    $total = 0
    $cpuMsTotal = 0.0
    $seen = @{}
    $baseline = ($P -lt 0)

    foreach ($proc in @($Processes)) {
        if ($null -eq $proc) { continue }
        $total++
        $created = $proc.CreationDate
        $hasDate = ($created -is [datetime])
        $ticks = $(if ($hasDate) { $created.Ticks } else { 0 })
        $key = '{0}|{1}' -f $proc.ProcessId, $ticks
        $seen[$key] = $true

        $cpu = [double]$proc.KernelModeTime + [double]$proc.UserModeTime
        $rd = [double]$proc.ReadTransferCount
        $wr = [double]$proc.WriteTransferCount
        $ops = [double]$proc.ReadOperationCount + [double]$proc.WriteOperationCount
        $wsKB = [Math]::Floor([double]$proc.WorkingSetSize / 1024.0)

        $entry = $null
        if ($State.Procs.ContainsKey($key)) { $entry = $State.Procs[$key] }
        if ($null -eq $entry) {
            # Unknown process: if it started after the previous snapshot, all it used so far counts.
            $isNew = ($hasDate -and ($created -gt $PrevTime))
            $entry = @{ K = -1; Cpu = $(if ($isNew) { 0.0 } else { $cpu }); Rd = $(if ($isNew) { 0.0 } else { $rd })
                Wr = $(if ($isNew) { 0.0 } else { $wr }); Ops = $(if ($isNew) { 0.0 } else { $ops })
                Ws = $(if ($isNew) { 0.0 } else { $wsKB }) }
            $State.Procs[$key] = $entry
        }
        if ($baseline) { continue }

        $dCpuMs = [Math]::Floor(([double]($cpu - $entry.Cpu)) / 10000.0)
        $dRd = [double]($rd - $entry.Rd)
        $dWr = [double]($wr - $entry.Wr)
        $dOps = [double]($ops - $entry.Ops)
        if ($dCpuMs -lt 0) { $dCpuMs = 0.0 }
        if ($dRd -lt 0) { $dRd = 0.0 }
        if ($dWr -lt 0) { $dWr = 0.0 }
        if ($dOps -lt 0) { $dOps = 0.0 }

        $write = ($Keyframe.IsPresent -or $entry.K -lt 0 -or $dCpuMs -ge 1 -or $dRd -gt 0 -or $dWr -gt 0 -or ([Math]::Abs($wsKB - $entry.Ws) -ge 1024))
        if (-not $write) { continue }

        if ($entry.K -lt 0) {
            $entry.K = [int]$State.NextKey
            $State.NextKey = [int]$State.NextKey + 1
            $startText = $(if ($hasDate) { $created.ToString('o') } else { '' })
            $svc = ''
            if ($Services.ContainsKey([int]$proc.ProcessId)) { $svc = [string]$Services[[int]$proc.ProcessId] }
            $cmd = $(if ($IncludeCommandLine) { Format-WorkerPerfCsvText ([string]$proc.CommandLine) } else { '' })
            $info.Add([string]::Concat($entry.K, ',', $proc.ProcessId, ',', $proc.ParentProcessId, ',',
                    (Format-WorkerPerfCsvText ([string]$proc.Name)), ',', $proc.SessionId, ',', $startText, ',',
                    (Format-WorkerPerfCsvText ([string]$proc.ExecutablePath)), ',', (Format-WorkerPerfCsvText $svc), ',', $cmd))
        }

        # Book only what is written, so rounding and skipped rows lose nothing.
        $entry.Cpu = $entry.Cpu + $dCpuMs * 10000.0
        $entry.Rd = $entry.Rd + $dRd
        $entry.Wr = $entry.Wr + $dWr
        $entry.Ops = $entry.Ops + $dOps
        $entry.Ws = $wsKB
        $cpuMsTotal += $dCpuMs

        $rows.Add([string]::Concat($P, ',', $entry.K, ',', [long]$dCpuMs, ',', [long]$wsKB, ',',
                [long]([Math]::Floor([double]$proc.PrivatePageCount / 1024.0)), ',', [long]$dRd, ',', [long]$dWr, ',', [long]$dOps, ',',
                $proc.HandleCount, ',', $proc.ThreadCount))
    }

    if (-not $baseline) {
        $gone = @($State.Procs.Keys | Where-Object { -not $seen.ContainsKey($_) })
        $goneK = [System.Collections.Generic.List[int]]::new()
        foreach ($g in $gone) {
            if ($State.Procs[$g].K -ge 0) { $goneK.Add([int]$State.Procs[$g].K) }
            $State.Procs.Remove($g)
        }
        $goneK.Sort()
        foreach ($k in $goneK) { $ended.Add([string]::Concat($P, ',', $k)) }
    }
    else {
        foreach ($g in @($State.Procs.Keys | Where-Object { -not $seen.ContainsKey($_) })) { $State.Procs.Remove($g) }
    }

    return @{ Rows = [string[]]$rows.ToArray(); Info = [string[]]$info.ToArray(); Ended = [string[]]$ended.ToArray()
        Total = [int]$total; CpuMs = [double]$cpuMsTotal }
}

# ---- Burst control, scheduling, guards, fast cadence rows and writers ----

function New-WorkerPerfBurstState {
    # Signals: signal id -> @{ Armed; Start } for signals that are currently over their threshold.
    # A signal without an entry is armed. HasTrigger/LastTrigger: time of the latest trigger of any signal.
    return @{ Signals = @{}; HasTrigger = $false; LastTrigger = [datetime]::MinValue }
}

function Update-WorkerPerfBurstState {
    param($State, [datetime]$Now, [AllowEmptyCollection()][string[]]$BadSignals, [int]$HoldSeconds = 60, [int]$MaxEpisodeSeconds = 300)

    $bad = @{}
    foreach ($id in @($BadSignals)) { if (-not [string]::IsNullOrEmpty($id)) { $bad[$id] = $true } }

    # A signal that is no longer bad is armed again.
    foreach ($id in @($State.Signals.Keys)) {
        if (-not $bad.ContainsKey($id)) { $State.Signals.Remove($id) }
    }

    $triggered = $false
    foreach ($id in $bad.Keys) {
        if (-not $State.Signals.ContainsKey($id)) {
            # Armed: a new episode begins.
            $State.Signals[$id] = @{ Armed = $false; Start = $Now }
            $triggered = $true
        }
        elseif (($Now - $State.Signals[$id].Start).TotalSeconds -le $MaxEpisodeSeconds) {
            $triggered = $true
        }
    }
    if ($triggered) {
        $State.HasTrigger = $true
        $State.LastTrigger = $Now
    }
    if (-not $State.HasTrigger) { return $false }
    return [bool](($Now - $State.LastTrigger).TotalSeconds -le $HoldSeconds)
}

function Get-WorkerPerfTriggerSignals {
    param($Sample, $Thresholds, [int]$LogicalProcessors, [double]$PhysicalMemoryMB)

    $host_ = Get-WorkerPerfHostSignals -Tick $Sample -LogicalProcessors $LogicalProcessors -PhysicalMemoryMB $PhysicalMemoryMB
    $maxOf = {
        param($Items, [string[]]$Fields, [double]$MinOps)
        $max = [double]::NaN
        foreach ($item in @($Items)) {
            if ($null -eq $item) { continue }
            if ($MinOps -gt 0 -and (([double]$item.ReadOps + [double]$item.WriteOps) -lt $MinOps)) { continue }
            foreach ($f in $Fields) {
                $v = $item.$f
                if ($null -eq $v) { continue }
                $d = [double]$v
                if ([double]::IsNaN($d)) { continue }
                if ([double]::IsNaN($max) -or $d -gt $max) { $max = $d }
            }
        }
        return $max
    }

    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($id in @($Thresholds.Keys)) {
        $th = $Thresholds[$id]
        if (-not [bool]$th.trigger) { continue }
        $value = [double]::NaN
        if ($host_.ContainsKey($id)) { $value = [double]$host_[$id] }
        elseif ($id -eq 'input.session') { $value = & $maxOf $Sample.InputSessions @('DelayMs') 0 }
        elseif ($id -eq 'disk.latency') { $value = & $maxOf $Sample.Volumes @('ReadLatMs', 'WriteLatMs') ([double]$th.minOps) }
        elseif ($id -eq 'smb.latency') { $value = & $maxOf $Sample.Shares @('ReadLatMs', 'WriteLatMs') ([double]$th.minOps) }
        $status = Get-WorkerPerfStatus $value $th
        if ($null -ne $status -and $status -ge 1) { $result.Add([string]$id) }
    }
    return [string[]]$result.ToArray()
}

function Get-WorkerPerfSnapshotDue {
    param([datetime]$Now, [datetime]$NextRegular, [datetime]$LastSnapshot, [bool]$BurstActive, [int]$BurstIntervalSeconds = 5)

    if ($Now -ge $NextRegular) { return 'regular' }
    if ($BurstActive -and (($Now - $LastSnapshot).TotalSeconds -ge $BurstIntervalSeconds)) { return 'burst' }
    return 'none'
}

function Get-WorkerPerfNextTick {
    param([datetime]$Scheduled, [datetime]$Now, [double]$IntervalSeconds)

    $next = $Scheduled.AddSeconds($IntervalSeconds)
    if ($next -gt $Now) { return @{ Next = $next; Skipped = 0 } }
    $k = [int][Math]::Floor(($Now - $Scheduled).TotalSeconds / $IntervalSeconds) + 1
    return @{ Next = $Scheduled.AddSeconds($k * $IntervalSeconds); Skipped = [int]($k - 1) }
}

function Test-WorkerPerfGuard {
    param([double]$FreeMB, [double]$SizeMB, [double]$MaxSizeMB, [ValidateSet('start', 'run')][string]$Phase)

    if ($FreeMB -lt 200) { return 'diskspace' }
    if ($Phase -eq 'start' -and $FreeMB -lt 1024) {
        Write-Warning ('Nur noch {0} MB Speicherplatz frei (unter 1024 MB).' -f [Math]::Round($FreeMB))
    }
    if ($SizeMB -ge $MaxSizeMB) { return 'maxsize' }
    return $null
}

function ConvertTo-WorkerPerfFastRows {
    param($Sample, [int]$T, [double]$ElapsedSec, [bool]$Burst, [double]$CollectMs)

    # Runs every fast tick: no function or scriptblock call per value. Each row is a list of values and a list of
    # format codes: a code >= 0 formats a number like Format-WorkerPerfNumber with that many decimals, -1 formats
    # a text like Format-WorkerPerfCsvText, -2 takes the value as it is.
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $burstFlag = $(if ($Burst) { 1 } else { 0 })
    $time = $Sample.Time.ToString('o', $inv)

    $pending = [System.Collections.Generic.List[object]]::new()      # @(target, values, codes)
    $volumes = [System.Collections.Generic.List[string]]::new()
    $shares = [System.Collections.Generic.List[string]]::new()
    $sessions = [System.Collections.Generic.List[string]]::new()
    $procs = [System.Collections.Generic.List[string]]::new()
    $tickRow = [System.Collections.Generic.List[string]]::new()

    $pending.Add(@($tickRow, @(
                $T, $time, $ElapsedSec, $Sample.CpuPct, $Sample.ProcQueue, $Sample.StealPct, $Sample.MemAvailMB, $Sample.MemCommittedMB,
                $Sample.MemCommitLimitMB, $Sample.PagesInPerSec, $Sample.DiskReadBps, $Sample.DiskWriteBps, $Sample.DiskReadIops,
                $Sample.DiskWriteIops, $Sample.DiskQueue, $Sample.NetRecvBps, $Sample.NetSentBps, $burstFlag, $CollectMs),
            [int[]]@(-2, -2, 3, 2, 0, 3, 0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 0, -2, 0)))

    $volCodes = [int[]]@(-2, -1, -1, 0, -1, 2, 2, 0, 0, 0, 0, 0)
    foreach ($v in @($Sample.Volumes)) {
        if ($null -eq $v) { continue }
        if (([double]$v.ReadOps + [double]$v.WriteOps) -le 0) { continue }
        $pending.Add(@($volumes, @($T, $v.Volume, $v.Kind, $v.SessionId, $v.Backing, $v.ReadLatMs, $v.WriteLatMs,
                    $v.ReadOps, $v.WriteOps, $v.ReadBps, $v.WriteBps, $v.Queue), $volCodes))
    }

    $shareCodes = [int[]]@(-2, -1, 2, 2, 0, 0, 0, 0)
    foreach ($s in @($Sample.Shares)) {
        if ($null -eq $s) { continue }
        if (([double]$s.ReadOps + [double]$s.WriteOps) -le 0) { continue }
        $pending.Add(@($shares, @($T, $s.Share, $s.ReadLatMs, $s.WriteLatMs, $s.ReadOps, $s.WriteOps, $s.ReadBps, $s.WriteBps), $shareCodes))
    }

    $sessionCodes = [int[]]@(-2, 0, 0)
    foreach ($i in @($Sample.InputSessions)) {
        if ($null -eq $i -or $null -eq $i.DelayMs) { continue }
        if ([double]$i.DelayMs -le 0) { continue }
        $pending.Add(@($sessions, @($T, $i.SessionId, $i.DelayMs), $sessionCodes))
    }

    $procCodes = [int[]]@(-2, 0, 0, -1, 0)
    foreach ($p in @($Sample.InputProcesses)) {
        if ($null -eq $p -or $null -eq $p.DelayMs) { continue }
        if ([double]$p.DelayMs -lt 50) { continue }
        $pending.Add(@($procs, @($T, $p.SessionId, $p.Pid, $p.Name, $p.DelayMs), $procCodes))
    }

    $quoteChars = [char[]]@(',', '"')
    foreach ($row in $pending) {
        $values = $row[1]; $codes = $row[2]
        $n = $values.Length
        $parts = [string[]]::new($n)
        for ($k = 0; $k -lt $n; $k++) {
            $x = $values[$k]
            $code = $codes[$k]
            if ($code -ge 0) {
                $text = ''
                if ($null -ne $x) {
                    $d = [double]$x
                    if (-not ([double]::IsNaN($d) -or [double]::IsInfinity($d))) { $text = [Math]::Round($d, $code).ToString($inv) }
                }
                $parts[$k] = $text
            }
            elseif ($code -eq -1) {
                $text = [string]$x
                if ($text.Length -gt 0) {
                    $text = $text.Replace("`r", ' ').Replace("`n", ' ')
                    if ($text.IndexOfAny($quoteChars) -ge 0) { $text = '"' + $text.Replace('"', '""') + '"' }
                }
                $parts[$k] = $text
            }
            else { $parts[$k] = [string]$x }
        }
        $row[0].Add([string]::Join(',', $parts))
    }

    return @{ Tick = [string]$tickRow[0]; Volumes = [string[]]$volumes.ToArray(); Shares = [string[]]$shares.ToArray()
        InputSessions = [string[]]$sessions.ToArray(); InputProcesses = [string[]]$procs.ToArray() }
}

function ConvertTo-WorkerPerfProbeRow {
    # One line of probes.csv. A failed probe keeps its duration until the abort next to the error.
    param($Result, [int]$T)
    return [string]::Concat($T, ',', (Format-WorkerPerfCsvText ([string]$Result.Name)), ',', (Format-WorkerPerfCsvText ([string]$Result.Role)), ',',
        (Format-WorkerPerfCsvText ([string]$Result.Host)), ',', [string]$Result.Port, ',', (Format-WorkerPerfNumber $Result.ConnectMs 1), ',',
        (Format-WorkerPerfCsvText ([string]$Result.Error)))
}

function ConvertTo-WorkerPerfUtc([datetime]$Time) {
    # The capture loop schedules and measures durations in UTC: the local clock steps back at the end of daylight
    # saving time. Times written to the files stay local times of the source.
    if ($Time.Kind -eq [DateTimeKind]::Utc) { return $Time }
    return $Time.ToUniversalTime()
}

function Add-WorkerPerfSourceError {
    # Counts a failed call of a data source. $Errors (ordered): source -> Count, FirstTime, FirstMessage.
    # Returns $true for the first failure of the source: the caller warns once and goes on.
    param($Errors, [string]$Source, [datetime]$Time, [string]$Message)
    if ($Errors.Contains($Source)) {
        $Errors[$Source].Count = [int]$Errors[$Source].Count + 1
        return $false
    }
    $Errors[$Source] = [ordered]@{ Count = 1; FirstTime = $Time.ToString('o', [Globalization.CultureInfo]::InvariantCulture); FirstMessage = $Message }
    return $true
}

function Save-WorkerPerfMeta {
    # Writes meta.json to a temporary file next to it and moves that over the target (delete and move, as the report
    # file is written): a kill during the write leaves the previous meta.json, never a half-written one. The loader
    # reads the temporary file when the kill fell between delete and move.
    param([string]$Path, $Meta)
    $tmp = $Path + '.tmp'
    [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $Meta -Depth 6), (New-Object System.Text.UTF8Encoding $false))
    if ([IO.File]::Exists($Path)) { [IO.File]::Delete($Path) }
    [IO.File]::Move($tmp, $Path)
}

function New-WorkerPerfWriters {
    param([string]$RunDir)

    $encoding = New-Object System.Text.UTF8Encoding($false)
    $writers = @{}
    try {
        foreach ($name in $script:WorkerPerfHeaders.Keys) {
            $stream = New-Object System.IO.FileStream((Join-Path $RunDir $name), [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
            $w = New-Object System.IO.StreamWriter($stream, $encoding)
            $w.AutoFlush = $false
            $writers[$name] = $w
            $w.WriteLine([string]$script:WorkerPerfHeaders[$name])
            $w.Flush()
        }
    }
    catch {
        foreach ($w in $writers.Values) { $w.Dispose() }
        throw
    }
    return $writers
}

# ---- Format 3: events, print drivers and print queues ----

function ConvertTo-WorkerPerfEventRow {
    # One line of events.csv or events_before.csv. $Event carries the fields of ConvertTo-WorkerPerfEventRecord; a
    # missing field (a record of an older source) or $null is written empty.
    param($Event)
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $names = $script:WorkerPerfHeaders['events.csv'].Split(',')
    $parts = [string[]]::new($names.Length)
    $time = Get-WorkerPerfField $Event 'Time'
    $parts[0] = $(if ($time -is [datetime]) { $time.ToString('o', $inv) } else { Format-WorkerPerfCsvText ([string]$time) })
    for ($i = 1; $i -lt $names.Length; $i++) {
        $v = Get-WorkerPerfField $Event $names[$i]
        if ($null -eq $v) { $parts[$i] = ''; continue }
        if ($v -is [IFormattable]) { $parts[$i] = Format-WorkerPerfCsvText ($v.ToString($null, $inv)) }
        else { $parts[$i] = Format-WorkerPerfCsvText ([string]$v) }
    }
    return [string]::Join(',', $parts)
}

function ConvertTo-WorkerPerfPrintDriverRow {
    # One line of printdrivers.csv: Files (file names only) joined with ';', Isolation none|shared|isolated or empty.
    # ';' separates the file names: the files of a Windows print driver carry no ';' in their names, so the column is
    # not quoted further (a name with ';' would be read back as two names).
    param($Driver)
    $files = @(Get-WorkerPerfField $Driver 'Files' | Where-Object { -not [string]::IsNullOrEmpty([string]$_) } | ForEach-Object { [string]$_ })
    $type = Get-WorkerPerfField $Driver 'Type'
    return [string]::Concat((Format-WorkerPerfCsvText ([string](Get-WorkerPerfField $Driver 'Name'))), ',',
        (Format-WorkerPerfCsvText ([string](Get-WorkerPerfField $Driver 'Manufacturer'))), ',',
        (Format-WorkerPerfCsvText ([string](Get-WorkerPerfField $Driver 'Version'))), ',',
        $(if ($null -eq $type) { '' } else { [string]$type }), ',',
        (Format-WorkerPerfCsvText ([string](Get-WorkerPerfField $Driver 'Isolation'))), ',',
        (Format-WorkerPerfCsvText ([string]::Join(';', [string[]]$files))))
}

function ConvertTo-WorkerPerfOptionalNumber($Value) {
    # A number as [double], or $null for $null, '' and anything that is not a number (invariant culture, or a value
    # that converts like '0x32c').
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) {
        if ($Value.Trim().Length -eq 0) { return $null }
        $d = 0.0
        if ([double]::TryParse($Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
    }
    try { $d = [double]$Value } catch { return $null }
    if ([double]::IsNaN($d) -or [double]::IsInfinity($d)) { return $null }
    return $d
}

function ConvertTo-WorkerPerfPrintQueueRow {
    # One line of printqueues.csv: the error counters are the running raw values of the queue. A counter that is not
    # a number is written empty; the row is kept.
    param($Queue, [datetime]$Time)
    return [string]::Concat($Time.ToString('o', [Globalization.CultureInfo]::InvariantCulture), ',',
        (Format-WorkerPerfCsvText ([string](Get-WorkerPerfField $Queue 'Queue'))), ',',
        (Format-WorkerPerfNumber (ConvertTo-WorkerPerfOptionalNumber (Get-WorkerPerfField $Queue 'Jobs')) 0), ',',
        (Format-WorkerPerfNumber (ConvertTo-WorkerPerfOptionalNumber (Get-WorkerPerfField $Queue 'JobErrors')) 0), ',',
        (Format-WorkerPerfNumber (ConvertTo-WorkerPerfOptionalNumber (Get-WorkerPerfField $Queue 'NotReadyErrors')) 0))
}

function Select-WorkerPerfEventsInWindow {
    # The events with After < Time <= Until (without -After: Time <= Until), compared in UTC; an event without a
    # readable time is left out. The collector uses it on both sides of the start and at every read of the
    # measurement, so an event on a boundary is written exactly once, whatever the source returns.
    param([AllowEmptyCollection()][object[]]$Events, $After = $null, [datetime]$Until)
    $untilUtc = ConvertTo-WorkerPerfUtc $Until
    $afterUtc = $null
    if ($After -is [datetime]) { $afterUtc = ConvertTo-WorkerPerfUtc $After }
    foreach ($e in @($Events)) {
        if ($null -eq $e) { continue }
        $time = Get-WorkerPerfField $e 'Time'
        if (-not ($time -is [datetime])) { continue }
        $u = ConvertTo-WorkerPerfUtc $time
        if ($u -gt $untilUtc) { continue }
        if ($null -ne $afterUtc -and $u -le $afterUtc) { continue }
        $e
    }
}

# ---- Memory of the processes seen in snapshots ----
# An application crash or hang is logged when the process dies, so the snapshot taken after it no longer lists the
# process. The collector remembers each process of every successful snapshot (pid, session id, start time, last seen)
# and forgets it 10 minutes after it was last seen; MaxEntries caps the size (the entries seen longest ago go first).

function New-WorkerPerfProcessMemory {
    param([int]$MaxEntries = 20000, [double]$KeepSeconds = 600)
    # Entries: 'pid|start ticks' -> entry; PrunedAt: when entries seen too long ago were last removed.
    return @{ Entries = @{}; MaxEntries = $MaxEntries; KeepSeconds = $KeepSeconds; PrunedAt = [datetime]::MinValue }
}

function Update-WorkerPerfProcessMemory {
    # Runs at every snapshot: a process already remembered only gets its LastSeen; old entries are removed at most
    # once a minute of server time, and whenever MaxEntries is exceeded.
    param($Memory, [AllowEmptyCollection()][object[]]$Processes, [datetime]$Time)
    $entries = $Memory.Entries
    $nowUtc = ConvertTo-WorkerPerfUtc $Time
    foreach ($p in $Processes) {
        if ($null -eq $p) { continue }
        # snapshot objects of both sources carry these properties; anything else takes the strict-mode safe path
        try { $created = $p.CreationDate; $rawId = $p.ProcessId }
        catch { $created = Get-WorkerPerfField $p 'CreationDate'; $rawId = Get-WorkerPerfField $p 'ProcessId' }
        $key = [string]$rawId + '|' + $(if ($created -is [datetime]) { $created.Ticks } else { 0 })
        $known = $entries[$key]
        if ($null -ne $known) { $known.LastSeen = $nowUtc; continue }
        $id = ConvertTo-WorkerPerfOptionalNumber $rawId
        if ($null -eq $id) { continue }
        $sid = ConvertTo-WorkerPerfOptionalNumber (Get-WorkerPerfField $p 'SessionId')
        $entries[$key] = [pscustomobject]@{ ProcessId = [long]$id; SessionId = $(if ($null -ne $sid) { [int]$sid } else { $null })
            CreationDate = $(if ($created -is [datetime]) { ConvertTo-WorkerPerfUtc $created } else { $null }); LastSeen = $nowUtc }
    }
    if (($nowUtc - $Memory.PrunedAt).TotalSeconds -ge 60 -or $entries.Count -gt [int]$Memory.MaxEntries) {
        $limit = $nowUtc.AddSeconds(-[double]$Memory.KeepSeconds)
        foreach ($k in @($entries.Keys)) { if ($entries[$k].LastSeen -lt $limit) { $entries.Remove($k) } }
        $Memory.PrunedAt = $nowUtc
    }
    if ($entries.Count -gt [int]$Memory.MaxEntries) {
        $drop = $entries.Count - [int]$Memory.MaxEntries
        foreach ($k in @($entries.Keys | Sort-Object -Property @{ Expression = { $entries[$_].LastSeen } } | Select-Object -First $drop)) { $entries.Remove($k) }
    }
}

function Get-WorkerPerfProcessMemoryEntries($Memory) {
    # The remembered processes: ProcessId, SessionId, CreationDate (UTC or $null), LastSeen (UTC).
    $Memory.Entries.Values
}

function Set-WorkerPerfRecordField($Record, [string]$Name, $Value) {
    if ($Record -is [System.Collections.IDictionary]) { $Record[$Name] = $Value; return }
    if ($null -ne $Record.PSObject.Properties[$Name]) { $Record.$Name = $Value }
    else { $Record | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Complete-WorkerPerfEventSession {
    # Fills an empty SessionId from the process with the same Pid that existed at the event's time, and an empty User
    # from the session with that SessionId. A process existed at the event's time when it started at or before it and
    # was last seen at most MaxGapSeconds before it (fields it lacks are not checked). Of several, the one started last
    # wins. A process that started after the event is not the one the event names (its PID was reused): such an event
    # keeps its empty session. A Pid or SessionId that is not a number counts as empty. Emits the events (the same
    # objects); an event that cannot be completed is emitted as it is.
    param([AllowEmptyCollection()][object[]]$Events, [AllowEmptyCollection()][object[]]$Processes, [AllowEmptyCollection()][object[]]$Sessions,
          [double]$MaxGapSeconds = 60)
    $byPid = @{}
    foreach ($p in @($Processes)) {
        if ($null -eq $p) { continue }
        $id = ConvertTo-WorkerPerfOptionalNumber (Get-WorkerPerfField $p 'ProcessId')
        if ($null -eq $id) { continue }
        $key = [long]$id
        if (-not $byPid.ContainsKey($key)) { $byPid[$key] = New-Object System.Collections.Generic.List[object] }
        $byPid[$key].Add($p)
    }
    $userOf = @{}
    foreach ($s in @($Sessions)) {
        if ($null -eq $s) { continue }
        $sid = ConvertTo-WorkerPerfOptionalNumber (Get-WorkerPerfField $s 'SessionId')
        if ($null -ne $sid) { $userOf[[long]$sid] = [string](Get-WorkerPerfField $s 'User') }
    }
    foreach ($e in @($Events)) {
        if ($null -eq $e) { continue }
        try {
            $sid = ConvertTo-WorkerPerfOptionalNumber (Get-WorkerPerfField $e 'SessionId')
            if ($null -eq $sid) {
                $evPid = ConvertTo-WorkerPerfOptionalNumber (Get-WorkerPerfField $e 'Pid')
                if ($null -ne $evPid -and $byPid.ContainsKey([long]$evPid)) {
                    $time = Get-WorkerPerfField $e 'Time'
                    $timeUtc = $(if ($time -is [datetime]) { ConvertTo-WorkerPerfUtc $time } else { $null })
                    $best = $null; $bestCreated = $null
                    foreach ($proc in $byPid[[long]$evPid]) {
                        $created = Get-WorkerPerfField $proc 'CreationDate'
                        $createdUtc = $(if ($created -is [datetime]) { ConvertTo-WorkerPerfUtc $created } else { $null })
                        $seen = Get-WorkerPerfField $proc 'LastSeen'
                        if ($null -ne $timeUtc) {
                            if ($null -ne $createdUtc -and $createdUtc -gt $timeUtc) { continue }
                            if ($seen -is [datetime] -and ((ConvertTo-WorkerPerfUtc $seen).AddSeconds($MaxGapSeconds) -lt $timeUtc)) { continue }
                        }
                        $procSid = ConvertTo-WorkerPerfOptionalNumber (Get-WorkerPerfField $proc 'SessionId')
                        if ($null -eq $procSid) { continue }
                        if ($null -eq $best -or ($null -ne $createdUtc -and ($null -eq $bestCreated -or $createdUtc -gt $bestCreated))) {
                            $best = [int]$procSid; $bestCreated = $createdUtc
                        }
                    }
                    if ($null -ne $best) {
                        $sid = $best
                        Set-WorkerPerfRecordField $e 'SessionId' $best
                    }
                }
            }
            if ($null -ne $sid -and [string]::IsNullOrEmpty([string](Get-WorkerPerfField $e 'User')) -and $userOf.ContainsKey([long]$sid)) {
                Set-WorkerPerfRecordField $e 'User' $userOf[[long]$sid]
            }
        }
        catch { Write-Verbose ('Sitzung eines Ereignisses nicht ergaenzt: ' + $_.Exception.Message) }
        $e
    }
}
