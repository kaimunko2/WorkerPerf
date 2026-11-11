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
            [int[]]@(-2, -2, 3, 2, 0, 2, 0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 0, -2, 0)))

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
