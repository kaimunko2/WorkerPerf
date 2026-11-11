#Requires -Version 5.1
# WorkerPerf analysis library: findings per signal and target/actual comparison.
# Defines functions only. Callers dot-source WorkerPerf.Common.ps1 as well (Get-WorkerPerfStatus).
# Series, findings and rows are hashtables. Functions emit plain pipeline output: callers wrap calls in @(...).

function Get-WorkerPerfPointStatus($Series, [int]$Index, $Threshold) {
    # Status (0/1/2) of one measurement point, or $null when it cannot be rated
    # (NaN, or fewer operations than the threshold's minOps).
    $minOps = [double]$Threshold.minOps
    if ($minOps -gt 0 -and $null -ne $Series['Ops']) {
        if ([double]$Series['Ops'][$Index] -lt $minOps) { return $null }
    }
    return (Get-WorkerPerfStatus ([double]$Series['Value'][$Index]) $Threshold)
}

function Test-WorkerPerfWorse([double]$A, [double]$B, $Threshold) {
    # $true when value A is worse than value B for the threshold's direction
    if ([string]$Threshold.direction -eq 'low') { return ($A -lt $B) }
    return ($A -gt $B)
}

function Get-WorkerPerfFindings {
    param([AllowEmptyCollection()][object[]]$Series, $Thresholds, [int]$BridgeSeconds = 10)
    $found = New-Object System.Collections.Generic.List[object]
    foreach ($s in @($Series)) {
        $id = [string]$s['Id']
        if (-not $Thresholds.Contains($id)) { continue }
        $th = $Thresholds[$id]
        $minTicks = [int]$th.minTicks
        $n = $s['Value'].Length
        $bad = New-Object System.Collections.Generic.List[int]
        $status = @{}
        for ($i = 0; $i -lt $n; $i++) {
            $st = Get-WorkerPerfPointStatus $s $i $th
            if ($null -ne $st -and $st -ge 1) { $bad.Add($i); $status[$i] = [int]$st }
        }
        $group = New-Object System.Collections.Generic.List[int]
        for ($k = 0; $k -le $bad.Count; $k++) {
            $idx = -1
            if ($k -lt $bad.Count) { $idx = $bad[$k] }
            if ($group.Count -gt 0) {
                $last = $group[$group.Count - 1]
                $joins = ($idx -ge 0) -and (($idx -eq $last + 1) -or (($s['TimeMs'][$idx] - $s['TimeMs'][$last]) -le ($BridgeSeconds * 1000)))
                if (-not $joins) {
                    if ($group.Count -ge $minTicks) {
                        $first = $group[0]
                        $sev = 1; $peakIdx = $first
                        foreach ($g in $group) {
                            if ($status[$g] -gt $sev) { $sev = $status[$g] }
                            if (Test-WorkerPerfWorse ([double]$s['Value'][$g]) ([double]$s['Value'][$peakIdx]) $th) { $peakIdx = $g }
                        }
                        $found.Add(@{
                            SignalId = $id; Resource = $s['Resource']; Instance = $s['Instance']; Label = $s['Label']
                            Scope = $s['Scope']; SessionIndex = $s['SessionIndex']
                            StartMs = [long]($s['TimeMs'][$first] - [long][Math]::Round([double]$s['ElapsedSec'][$first] * 1000))
                            EndMs = [long]$s['TimeMs'][$last]
                            Severity = $sev; PeakValue = [double]$s['Value'][$peakIdx]; PeakTimeMs = [long]$s['TimeMs'][$peakIdx]
                            BadPoints = $group.Count
                        })
                    }
                    $group.Clear()
                }
            }
            if ($idx -ge 0) { $group.Add($idx) }
        }
    }
    $sorted = @($found.ToArray() | Sort-Object -Property @{ Expression = { $_.StartMs } }, @{ Expression = { $_.SignalId } }, @{ Expression = { $_.Instance } })
    $sorted
}

function Get-WorkerPerfSollIst {
    param([AllowEmptyCollection()][object[]]$Series, $Thresholds, [hashtable]$Sources = @{})
    foreach ($th in $Thresholds.Values) {
        $id = [string]$th.id
        $mine = @(@($Series) | Where-Object { $_['Id'] -eq $id })
        $detail = ''
        if ($Sources.ContainsKey($id)) {
            $src = $Sources[$id]
            if ($src -is [hashtable] -and $src.ContainsKey('Detail') -and $null -ne $src['Detail']) { $detail = [string]$src['Detail'] }
        }
        # worst rateable value per measurement time over all instances
        $perTime = @{}
        $instBad = @{}; $instPeak = @{}
        foreach ($s in $mine) {
            $label = [string]$s['Label']
            if (-not $instBad.ContainsKey($label)) { $instBad[$label] = 0; $instPeak[$label] = [double]::NaN }
            for ($i = 0; $i -lt $s['Value'].Length; $i++) {
                $st = Get-WorkerPerfPointStatus $s $i $th
                if ($null -eq $st) { continue }
                $v = [double]$s['Value'][$i]
                $t = [long]$s['TimeMs'][$i]
                if (-not $perTime.ContainsKey($t) -or (Test-WorkerPerfWorse $v $perTime[$t] $th)) { $perTime[$t] = $v }
                if ($st -ge 1) {
                    $instBad[$label] = $instBad[$label] + 1
                    if ([double]::IsNaN($instPeak[$label]) -or (Test-WorkerPerfWorse $v $instPeak[$label] $th)) { $instPeak[$label] = $v }
                }
            }
        }
        $row = @{
            Id = $id; Label = $th.label; Unit = $th.unit; Ideal = $th.ideal; Warn = $th.warn; Crit = $th.crit
            Origin = $th.origin; Source = $th.source; Url = $th.url; Note = $th.note
            Measured = ($perTime.Count -gt 0); Detail = $detail
            Avg = $null; P95 = $null; Max = $null; PctNormal = $null; PctWarn = $null; PctCrit = $null; WorstInstance = ''
        }
        if ($perTime.Count -gt 0) {
            $vals = [double[]]@($perTime.Values)
            $sorted = [double[]]$vals.Clone()
            [Array]::Sort($sorted)
            $sum = 0.0
            foreach ($v in $sorted) { $sum += $v }
            $p = [int][Math]::Ceiling(0.95 * $sorted.Length) - 1
            if ($p -lt 0) { $p = 0 }
            $c = @(0, 0, 0)
            foreach ($v in $vals) { $c[[int](Get-WorkerPerfStatus $v $th)]++ }
            $row.Avg = $sum / $sorted.Length; $row.P95 = $sorted[$p]; $row.Max = $sorted[$sorted.Length - 1]
            $row.PctNormal = 100.0 * $c[0] / $vals.Length; $row.PctWarn = 100.0 * $c[1] / $vals.Length; $row.PctCrit = 100.0 * $c[2] / $vals.Length
            if ($mine.Count -gt 1) {
                $best = $null
                foreach ($label in $instBad.Keys) {
                    $take = $false
                    if ($null -eq $best) { $take = $true }
                    elseif ($instBad[$label] -gt $instBad[$best]) { $take = $true }
                    elseif ($instBad[$label] -eq $instBad[$best] -and -not [double]::IsNaN($instPeak[$label]) -and
                            ([double]::IsNaN($instPeak[$best]) -or (Test-WorkerPerfWorse $instPeak[$label] $instPeak[$best] $th))) { $take = $true }
                    if ($take) { $best = $label }
                }
                $row.WorstInstance = [string]$best
            }
        }
        $row
    }
}

function Group-WorkerPerfFindingsByTime {
    # Transitive grouping of findings: the next one joins while it starts at most $GapMs after the group's end.
    # Returns one list holding one list per group (the comma keeps the outer list intact).
    param([AllowEmptyCollection()][object[]]$Items, [long]$GapMs)
    $groups = New-Object System.Collections.Generic.List[object]
    $sorted = @(@($Items) | Sort-Object -Property @{ Expression = { $_.StartMs } }, @{ Expression = { $_.EndMs } })
    $cur = $null; $curEnd = 0L
    foreach ($f in $sorted) {
        if ($null -ne $cur -and $f.StartMs -le ($curEnd + $GapMs)) {
            $cur.Add($f)
            if ($f.EndMs -gt $curEnd) { $curEnd = [long]$f.EndMs }
        } else {
            $cur = New-Object System.Collections.Generic.List[object]
            $cur.Add($f)
            $curEnd = [long]$f.EndMs
            $groups.Add($cur)
        }
    }
    , $groups
}

function Join-WorkerPerfIncidents {
    param([AllowEmptyCollection()][object[]]$Findings, [int]$MergeSeconds = 10, [int]$ChronicMinutes = 15)
    $workerOrder = @('cpu', 'memory', 'disk', 'share', 'profile')
    $gapMs = [long]$MergeSeconds * 1000
    $chronicMs = [long]$ChronicMinutes * 60000
    $chronicFindings = New-Object System.Collections.Generic.List[object]
    $coreFindings = New-Object System.Collections.Generic.List[object]
    $sessionFindings = New-Object System.Collections.Generic.List[object]
    foreach ($f in @($Findings)) {
        if (($f.EndMs - $f.StartMs) -gt $chronicMs) { $chronicFindings.Add($f) }
        elseif ($f.Resource -eq 'profile' -or $f.Resource -eq 'network') { $sessionFindings.Add($f) }
        else { $coreFindings.Add($f) }
    }

    # phase 1: incidents with window and findings only
    $raw = New-Object System.Collections.Generic.List[object]
    foreach ($f in $chronicFindings) {
        $l = New-Object System.Collections.Generic.List[object]; $l.Add($f)
        $raw.Add(@{ Chronic = $true; StartMs = [long]$f.StartMs; EndMs = [long]$f.EndMs; List = $l })
    }
    $coreIncidents = New-Object System.Collections.Generic.List[object]
    $coreGroups = Group-WorkerPerfFindingsByTime -Items $coreFindings.ToArray() -GapMs $gapMs
    foreach ($g in $coreGroups) {
        $start = [long]::MaxValue; $end = [long]::MinValue
        foreach ($f in $g) {
            if ($f.StartMs -lt $start) { $start = [long]$f.StartMs }
            if ($f.EndMs -gt $end) { $end = [long]$f.EndMs }
        }
        $inc = @{ Chronic = $false; StartMs = $start; EndMs = $end; List = $g }
        $raw.Add($inc); $coreIncidents.Add($inc)
    }
    # session-bound causes: attach to the core incident with an input finding of the same session, else stand alone
    $standalone = @{}
    foreach ($f in @($sessionFindings.ToArray() | Sort-Object -Property @{ Expression = { $_.StartMs } }, @{ Expression = { $_.EndMs } })) {
        $target = $null
        foreach ($inc in @($coreIncidents.ToArray() | Sort-Object -Property @{ Expression = { $_.StartMs } })) {
            foreach ($x in $inc.List) {
                if ($x.Resource -eq 'input' -and $x.SessionIndex -eq $f.SessionIndex -and
                    $f.StartMs -le ($x.EndMs + $gapMs) -and $f.EndMs -ge ($x.StartMs - $gapMs)) { $target = $inc; break }
            }
            if ($null -ne $target) { break }
        }
        if ($null -ne $target) { $target.List.Add($f); continue }
        $key = [string]$f.SessionIndex
        if (-not $standalone.ContainsKey($key)) { $standalone[$key] = New-Object System.Collections.Generic.List[object] }
        $standalone[$key].Add($f)
    }
    foreach ($key in $standalone.Keys) {
        foreach ($g in (Group-WorkerPerfFindingsByTime -Items $standalone[$key].ToArray() -GapMs $gapMs)) {
            $start = [long]::MaxValue; $end = [long]::MinValue
            foreach ($f in $g) {
                if ($f.StartMs -lt $start) { $start = [long]$f.StartMs }
                if ($f.EndMs -gt $end) { $end = [long]$f.EndMs }
            }
            $raw.Add(@{ Chronic = $false; StartMs = $start; EndMs = $end; List = $g })
        }
    }

    # number by window (original position as final tie-break keeps the order deterministic)
    $pos = 0
    $keyed = foreach ($r in $raw) { $r['Pos'] = $pos; $pos++; $r }
    $ordered = @(@($keyed) | Sort-Object -Property @{ Expression = { $_.StartMs } }, @{ Expression = { $_.EndMs } }, @{ Expression = { $_.Pos } })

    # phase 2: classify
    $incidents = New-Object System.Collections.Generic.List[object]
    $id = 0
    foreach ($r in $ordered) { $id++; $r['Id'] = $id }
    foreach ($r in $ordered) {
        $fs = @($r.List.ToArray() | Sort-Object -Property @{ Expression = { $_.StartMs } }, @{ Expression = { $_.EndMs } })
        $severity = 0
        foreach ($f in $fs) { if ([int]$f.Severity -gt $severity) { $severity = [int]$f.Severity } }
        # chronic states overlapping the window (never the incident itself)
        $context = New-Object System.Collections.Generic.List[object]
        $explainers = New-Object System.Collections.Generic.List[object]
        foreach ($c in $ordered) {
            if (-not $c.Chronic -or $c.Id -eq $r.Id) { continue }
            if (-not ($c.StartMs -le $r.EndMs -and $c.EndMs -ge $r.StartMs)) { continue }
            $cf = $c.List[0]
            $explains = ($workerOrder -contains $cf.Resource) -and ([int]$cf.Severity -ge 2)
            $context.Add(@{ IncidentId = [int]$c.Id; SignalId = $cf.SignalId; Label = $cf.Label; Severity = [int]$cf.Severity; Explains = $explains })
            if ($explains) { $explainers.Add($cf) }
        }
        $workerFindings = @($fs | Where-Object { $workerOrder -contains $_.Resource })
        $hasInput = (@($fs | Where-Object { $_.Resource -eq 'input' }).Count -gt 0)
        $type = 'umfeld'
        if ($workerFindings.Count -gt 0 -or $explainers.Count -gt 0) { $type = 'engpass' }
        elseif ($hasInput) { $type = 'ohne-engpass' }
        $lead = $null
        $leadPool = $workerFindings
        if ($leadPool.Count -eq 0) { $leadPool = $explainers.ToArray() }
        $best = $null
        foreach ($f in $leadPool) {
            if ($null -eq $best) { $best = $f; continue }
            if ($f.StartMs -lt $best.StartMs -or ($f.StartMs -eq $best.StartMs -and [array]::IndexOf($workerOrder, $f.Resource) -lt [array]::IndexOf($workerOrder, $best.Resource))) { $best = $f }
        }
        if ($null -ne $best) { $lead = [string]$best.Resource }
        # resources except input, by earliest start (ties in canonical order)
        $resStart = @{}
        foreach ($f in $fs) {
            if ($f.Resource -eq 'input') { continue }
            if (-not $resStart.ContainsKey($f.Resource) -or $f.StartMs -lt $resStart[$f.Resource]) { $resStart[$f.Resource] = [long]$f.StartMs }
        }
        $canon = @('cpu', 'memory', 'disk', 'share', 'profile', 'network', 'endpoint')
        $resources = [string[]]@($resStart.Keys | Sort-Object -Property @{ Expression = { $resStart[$_] } }, @{ Expression = { [array]::IndexOf($canon, $_) } })
        $incidents.Add(@{
            Id = [int]$r.Id; StartMs = [long]$r.StartMs; EndMs = [long]$r.EndMs; Severity = $severity; Chronic = [bool]$r.Chronic
            Type = $type; Lead = $lead; Resources = $resources; Findings = [object[]]$fs; ChronicContext = [object[]]$context.ToArray()
        })
    }
    $incidents.ToArray()
}
