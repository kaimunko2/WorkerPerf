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
