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
            $context.Add(@{ IncidentId = [int]$c.Id; SignalId = $cf.SignalId; Label = $cf.Label; Severity = [int]$cf.Severity; Explains = $explains; Resource = [string]$cf.Resource })
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

# ---------------------------------------------------------------------------------------------
# Incident details (who was affected, who contributed) and plain-language text
# ---------------------------------------------------------------------------------------------

# Minimum share (%) of a security process in a contributor ranking to count as a companion
$script:WorkerPerfCompanionMinPct = 10

function Format-WorkerPerfNumber([double]$Value) {
    # German number: below 10 one decimal unless whole, else whole; decimal comma, independent of the installed culture.
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $r = [Math]::Round($Value, 1, [MidpointRounding]::AwayFromZero)
    if ([Math]::Abs($Value) -lt 10) {
        if ($r -eq [Math]::Floor($r)) { return $r.ToString('0', $inv) }
        return $r.ToString('0.0', $inv).Replace('.', ',')
    }
    return ([Math]::Round($Value, 0, [MidpointRounding]::AwayFromZero)).ToString('0', $inv)
}

function Format-WorkerPerfValue([double]$Value, [string]$Unit) {
    $n = Format-WorkerPerfNumber $Value
    if ($Unit -ne '') { return ($n + ' ' + $Unit) }
    return $n
}

function Format-WorkerPerfClock([long]$Ms, [int]$OffsetMinutes) {
    $t = [DateTimeOffset]::FromUnixTimeMilliseconds($Ms).UtcDateTime.AddMinutes($OffsetMinutes)
    return $t.ToString('HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-WorkerPerfThresholdField($Thresholds, [string]$Id, [string]$Field) {
    if ($Thresholds.Contains($Id)) { return [string]$Thresholds[$Id].$Field }
    return ''
}

function Get-WorkerPerfWindowTicks($Model, [long]$StartMs, [long]$EndMs) {
    # tick positions with StartMs < TimeMs <= EndMs
    $found = New-Object System.Collections.Generic.List[int]
    $t = $Model.Tick.TimeMs
    for ($i = 0; $i -lt $t.Length; $i++) { if ($t[$i] -gt $StartMs -and $t[$i] -le $EndMs) { $found.Add($i) } }
    $found.ToArray()
}

function Get-WorkerPerfWindowSnaps($Model, [long]$StartMs, [long]$EndMs) {
    # snapshot positions with TimeMs > StartMs and TimeMs - ElapsedSec * 1000 < EndMs
    $found = New-Object System.Collections.Generic.List[int]
    $t = $Model.Snap.TimeMs; $e = $Model.Snap.ElapsedSec
    for ($i = 0; $i -lt $t.Length; $i++) {
        if ($t[$i] -gt $StartMs -and ($t[$i] - [double]$e[$i] * 1000) -lt $EndMs) { $found.Add($i) }
    }
    $found.ToArray()
}

function Get-WorkerPerfMemoryStates {
    # Carries the working set (KB) of every process forward over the sparse rows. Returns copies of the state at the
    # snapshots in $Keep (masked to the process' lifetime) and the sum of the states over the snapshots in $Sum.
    param($Model, [int[]]$Keep, [int[]]$Sum)
    $proc = @($Model.Proc); $nK = $proc.Count
    $rows = $Model.Rows
    $keepSet = @{}; foreach ($p in $Keep) { $keepSet[$p] = $true }
    $sumSet = @{}; foreach ($p in $Sum) { $sumSet[$p] = $true }
    $last = -1
    foreach ($p in $Keep) { if ($p -gt $last) { $last = $p } }
    foreach ($p in $Sum) { if ($p -gt $last) { $last = $p } }
    $ws = New-Object double[] $nK
    $sums = New-Object double[] $nK
    $kept = @{}
    for ($p = 0; $p -le $last; $p++) {
        for ($r = [int]$rows.Start[$p]; $r -lt [int]$rows.Start[$p + 1]; $r++) {
            $k = [int]$rows.K[$r]
            if ($k -ge 0 -and $k -lt $nK) { $ws[$k] = [double]$rows.WsKB[$r] }
        }
        $isKeep = $keepSet.ContainsKey($p); $isSum = $sumSet.ContainsKey($p)
        if (-not ($isKeep -or $isSum)) { continue }
        $copy = New-Object double[] $nK
        for ($k = 0; $k -lt $nK; $k++) {
            $pr = $proc[$k]
            if ($null -eq $pr) { continue }
            if ($p -ge [int]$pr.FirstP -and $p -le [int]$pr.LastP) { $copy[$k] = $ws[$k] }
        }
        if ($isKeep) { $kept[$p] = $copy }
        if ($isSum) { for ($k = 0; $k -lt $nK; $k++) { $sums[$k] += $copy[$k] } }
    }
    return @{ States = $kept; Sums = $sums }
}

function Get-WorkerPerfShareTable {
    # One record per living process of the selected sessions: window value, share (%) of the window total,
    # baseline share (%) over the baseline snapshots ($null without any) and, for memory, the growth in MB.
    param($Model, [string]$Measure, [int[]]$WindowSnaps, [int[]]$BaseSnaps, [int[]]$SessionFilter, [hashtable]$Cache)
    $proc = @($Model.Proc); $nK = $proc.Count
    $rows = $Model.Rows
    $keys = New-Object System.Collections.Generic.List[int]
    for ($k = 0; $k -lt $nK; $k++) {
        if ($null -eq $proc[$k]) { continue }
        if ($SessionFilter.Count -gt 0 -and ($SessionFilter -notcontains [int]$proc[$k].SessionIndex)) { continue }
        $keys.Add($k)
    }
    $val = New-Object double[] $nK; $grow = New-Object double[] $nK
    $baseVal = New-Object double[] $nK; $baseTotal = 0.0; $hasBase = ($BaseSnaps.Count -gt 0)
    if ($Measure -eq 'memory') {
        if ($WindowSnaps.Count -gt 0) {
            $first = $WindowSnaps[0]; $lastP = $WindowSnaps[$WindowSnaps.Count - 1]
            $before = $first - 1; if ($before -lt 0) { $before = $first }
            $need = @($before, $lastP)
            $res = Get-WorkerPerfMemoryStates -Model $Model -Keep $need -Sum @()
            $sNow = $res.States[$lastP]; $sBefore = $res.States[$before]
            foreach ($k in $keys) { $val[$k] = $sNow[$k]; $grow[$k] = ($sNow[$k] - $sBefore[$k]) / 1024.0 }
        }
        if ($hasBase) {
            if (-not $Cache.ContainsKey('memBase')) { $Cache['memBase'] = (Get-WorkerPerfMemoryStates -Model $Model -Keep @() -Sum $BaseSnaps).Sums }
            $sums = $Cache['memBase']
            foreach ($k in $keys) { $baseVal[$k] = $sums[$k] / $BaseSnaps.Count }
            if (-not $Cache.ContainsKey('memTotal')) {
                $tot = 0.0
                foreach ($p in $BaseSnaps) {
                    foreach ($s in @($Model.Sessions)) { $v = [double]$s.Ws[$p]; if (-not [double]::IsNaN($v)) { $tot += $v } }
                }
                $Cache['memTotal'] = $tot / $BaseSnaps.Count
            }
            $baseTotal = $Cache['memTotal']
        }
    }
    else {
        $col = 'CpuMs'; if ($Measure -eq 'io') { $col = 'Io' }
        $a = $rows[$col]
        foreach ($p in $WindowSnaps) {
            for ($r = [int]$rows.Start[$p]; $r -lt [int]$rows.Start[$p + 1]; $r++) {
                $k = [int]$rows.K[$r]
                if ($k -ge 0 -and $k -lt $nK) { $val[$k] += [double]$a[$r] }
            }
        }
        if ($hasBase) {
            $ck = 'base' + $col
            if (-not $Cache.ContainsKey($ck)) {
                $sums = New-Object double[] $nK
                foreach ($p in $BaseSnaps) {
                    for ($r = [int]$rows.Start[$p]; $r -lt [int]$rows.Start[$p + 1]; $r++) {
                        $k = [int]$rows.K[$r]
                        if ($k -ge 0 -and $k -lt $nK) { $sums[$k] += [double]$a[$r] }
                    }
                }
                $Cache[$ck] = $sums
            }
            $sums = $Cache[$ck]
            foreach ($k in $keys) { $baseVal[$k] = $sums[$k]; $baseTotal += $sums[$k] }
        }
    }
    $total = 0.0
    foreach ($k in $keys) { $total += $val[$k] }
    $table = New-Object System.Collections.Generic.List[object]
    foreach ($k in $keys) {
        $share = 0.0; if ($total -gt 0) { $share = 100.0 * $val[$k] / $total }
        $base = $null; if ($hasBase -and $baseTotal -gt 0) { $base = 100.0 * $baseVal[$k] / $baseTotal }
        $g = $null; if ($Measure -eq 'memory') { $g = $grow[$k] }
        $table.Add(@{ K = $k; Value = $val[$k]; Share = $share; Base = $base; Growth = $g })
    }
    $table.ToArray()
}

function Get-WorkerPerfSessionRecord($Model, [int]$SessionIndex) {
    foreach ($s in @($Model.Sessions)) { if ([int]$s.Index -eq $SessionIndex) { return $s } }
    return $null
}

function Get-WorkerPerfUserName($Model, [int]$SessionIndex) {
    $s = Get-WorkerPerfSessionRecord $Model $SessionIndex
    if ($null -eq $s) { return '' }
    return [string]$s.User
}

function Get-WorkerPerfAppName($Model, [int]$AppIndex, $Proc) {
    foreach ($a in @($Model.Apps)) { if ([int]$a.Index -eq $AppIndex) { return [string]$a.Name } }
    return [string]$Proc.Name
}

function Group-WorkerPerfShareTable {
    # Sums the table by 'app-in-session', 'app' or 'session'; sorted by share descending, then name.
    param($Model, $Table, [string]$By, [bool]$SkipSecurity = $false)
    $groups = @{}
    foreach ($e in $Table) {
        $pr = $Model.Proc[$e.K]
        if ($SkipSecurity -and [string]$pr.Role -eq 'Sicherheit') { continue }
        if ($e.Value -le 0) { continue }
        $key = ''
        if ($By -eq 'app') { $key = [string]$pr.AppIndex }
        elseif ($By -eq 'session') { $key = [string]$pr.SessionIndex }
        else { $key = [string]$pr.AppIndex + '|' + [string]$pr.SessionIndex }
        if (-not $groups.ContainsKey($key)) {
            $name = Get-WorkerPerfAppName $Model ([int]$pr.AppIndex) $pr
            if ($By -eq 'session') { $name = Get-WorkerPerfUserName $Model ([int]$pr.SessionIndex) }
            $groups[$key] = @{ Name = $name; AppIndex = [int]$pr.AppIndex; SessionIndex = [int]$pr.SessionIndex; Share = 0.0; Base = $null; Growth = $null; Value = 0.0 }
        }
        $g = $groups[$key]
        $g.Share += $e.Share; $g.Value += $e.Value
        if ($null -ne $e.Base) { if ($null -eq $g.Base) { $g.Base = 0.0 }; $g.Base += $e.Base }
        if ($null -ne $e.Growth) { if ($null -eq $g.Growth) { $g.Growth = 0.0 }; $g.Growth += $e.Growth }
    }
    $sorted = @($groups.Values | Sort-Object -Property @{ Expression = { $_.Share }; Descending = $true }, @{ Expression = { $_.Name } }, @{ Expression = { $_.SessionIndex } }, @{ Expression = { $_.AppIndex } })
    $sorted
}

function Format-WorkerPerfRound($Value) {
    if ($null -eq $Value) { return $null }
    return [Math]::Round([double]$Value, 1, [MidpointRounding]::AwayFromZero)
}

function New-WorkerPerfRanking {
    param($Model, [string]$Measure, $Table)
    $take = 5
    $procSorted = @($Table | Where-Object { $_.Value -gt 0 } | Sort-Object -Property @{ Expression = { $_.Share }; Descending = $true }, @{ Expression = { [string]$Model.Proc[$_.K].Name } }, @{ Expression = { $_.K } })
    $procs = New-Object System.Collections.Generic.List[object]
    foreach ($e in @($procSorted | Select-Object -First $take)) {
        $pr = $Model.Proc[$e.K]
        $procs.Add(@{
            K = [int]$e.K; Name = [string]$pr.Name; Pid = [int]$pr.Pid; SessionIndex = [int]$pr.SessionIndex
            SharePct = (Format-WorkerPerfRound $e.Share); BaselinePct = (Format-WorkerPerfRound $e.Base); GrowthMB = (Format-WorkerPerfRound $e.Growth)
            Role = [string]$pr.Role; RoleLabel = [string]$pr.RoleLabel; IsCollector = [bool]$pr.IsCollector
        })
    }
    $main = $null
    $mains = @(Group-WorkerPerfShareTable -Model $Model -Table $Table -By 'app-in-session' -SkipSecurity $true)
    if ($mains.Count -gt 0) {
        $g = $mains[0]
        $main = @{
            App = $g.Name; AppIndex = $g.AppIndex; SessionIndex = $g.SessionIndex; User = (Get-WorkerPerfUserName $Model $g.SessionIndex)
            SharePct = (Format-WorkerPerfRound $g.Share); BaselinePct = (Format-WorkerPerfRound $g.Base); GrowthMB = (Format-WorkerPerfRound $g.Growth)
        }
    }
    $apps = New-Object System.Collections.Generic.List[object]
    foreach ($g in @(@(Group-WorkerPerfShareTable -Model $Model -Table $Table -By 'app') | Select-Object -First $take)) {
        $apps.Add(@{ AppIndex = $g.AppIndex; Name = $g.Name; SharePct = (Format-WorkerPerfRound $g.Share); BaselinePct = (Format-WorkerPerfRound $g.Base) })
    }
    $sess = New-Object System.Collections.Generic.List[object]
    foreach ($g in @(@(Group-WorkerPerfShareTable -Model $Model -Table $Table -By 'session') | Select-Object -First $take)) {
        $sess.Add(@{ SessionIndex = $g.SessionIndex; User = $g.Name; SharePct = (Format-WorkerPerfRound $g.Share); BaselinePct = (Format-WorkerPerfRound $g.Base) })
    }
    return @{ Measure = $Measure; Main = $main; Processes = $procs.ToArray(); Apps = $apps.ToArray(); Sessions = $sess.ToArray() }
}

function Add-WorkerPerfIncidentDetail {
    param([AllowEmptyCollection()][object[]]$Incidents, $Model, $Thresholds)
    if (@($Incidents).Count -eq 0) { return }
    $workerOrder = @('cpu', 'memory', 'disk', 'share', 'profile')
    $measureOf = @{ cpu = 'cpu'; memory = 'memory'; disk = 'io'; share = 'io'; profile = 'io' }
    $pad = 15000L
    $cache = @{}

    # baseline snapshots: outside every incident that is not a chronic state
    $inIncident = @{}
    foreach ($inc in @($Incidents)) {
        if ($inc.Chronic) { continue }
        foreach ($p in @(Get-WorkerPerfWindowSnaps $Model ([long]$inc.StartMs) ([long]$inc.EndMs))) { $inIncident[$p] = $true }
    }
    $baseList = New-Object System.Collections.Generic.List[int]
    for ($p = 0; $p -lt $Model.Snap.TimeMs.Length; $p++) { if (-not $inIncident.ContainsKey($p)) { $baseList.Add($p) } }
    $baseSnaps = $baseList.ToArray()

    # ticks inside a non-chronic incident do not count for chronic incidents
    $shortTicks = @{}
    foreach ($inc in @($Incidents)) {
        if ($inc.Chronic) { continue }
        foreach ($i in @(Get-WorkerPerfWindowTicks $Model ([long]$inc.StartMs) ([long]$inc.EndMs))) { $shortTicks[$i] = $true }
    }

    $inputTh = $null; if ($Thresholds.Contains('input.session')) { $inputTh = $Thresholds['input.session'] }
    $icaWarn = [double]::NaN; if ($Thresholds.Contains('ica.rtt')) { $icaWarn = [double]$Thresholds['ica.rtt'].warn }

    foreach ($inc in @($Incidents)) {
        $start = [long]$inc.StartMs; $end = [long]$inc.EndMs
        $ticks = @(Get-WorkerPerfWindowTicks $Model $start $end)
        $snaps = @(Get-WorkerPerfWindowSnaps $Model $start $end)
        $wideSnaps = @(Get-WorkerPerfWindowSnaps $Model ($start - $pad) ($end + $pad))

        # affected sessions: input delay at or above the "auffaellig" threshold
        $affected = New-Object System.Collections.Generic.List[object]
        $ownSessions = $null
        if ($inc.Type -eq 'umfeld') {
            $ownSessions = @(@($inc.Findings) | Where-Object { $_.Scope -eq 'session' } | ForEach-Object { [int]$_.SessionIndex })
        }
        if ($null -ne $inputTh) {
            foreach ($s in @($Model.Sessions)) {
                if ($null -ne $ownSessions -and $ownSessions -notcontains [int]$s.Index) { continue }
                $peak = [double]::NaN
                foreach ($i in $ticks) {
                    if ($inc.Chronic -and $shortTicks.ContainsKey($i)) { continue }
                    $v = [double]$s.Input[$i]
                    $st = Get-WorkerPerfStatus $v $inputTh
                    if ($null -ne $st -and $st -ge 1 -and ([double]::IsNaN($peak) -or $v -gt $peak)) { $peak = $v }
                }
                if (-not [double]::IsNaN($peak)) { $affected.Add(@{ SessionIndex = [int]$s.Index; PeakMs = $peak }) }
            }
        }
        $inc['Affected'] = @($affected.ToArray() | Sort-Object -Property @{ Expression = { $_.PeakMs }; Descending = $true }, @{ Expression = { $_.SessionIndex } })

        # contributors per worker resource (the lead resource is ranked too when it only comes from a chronic state)
        $resources = New-Object System.Collections.Generic.List[string]
        foreach ($r in @($inc.Resources)) { if ($workerOrder -contains $r -and -not $resources.Contains([string]$r)) { $resources.Add([string]$r) } }
        if ($null -ne $inc.Lead -and $workerOrder -contains $inc.Lead -and -not $resources.Contains([string]$inc.Lead)) { $resources.Add([string]$inc.Lead) }
        $tables = @{}
        $getTable = {
            param([string]$Resource)
            if (-not $tables.ContainsKey($Resource)) {
                $filter = @()
                if ($Resource -eq 'profile') {
                    $ids = @(@($inc.Findings) | Where-Object { $_.Resource -eq 'profile' } | ForEach-Object { [int]$_.SessionIndex } | Sort-Object -Unique)
                    if ($ids -notcontains -1) { $filter = [int[]]$ids }
                }
                $tables[$Resource] = @(Get-WorkerPerfShareTable -Model $Model -Measure $measureOf[$Resource] -WindowSnaps ([int[]]$snaps) -BaseSnaps $baseSnaps -SessionFilter ([int[]]$filter) -Cache $cache)
            }
            $tables[$Resource]
        }
        $contrib = @{}
        foreach ($r in $resources) {
            $tbl = @(& $getTable $r)
            $contrib[$r] = New-WorkerPerfRanking -Model $Model -Measure $measureOf[$r] -Table $tbl
        }
        $inc['Contributors'] = $contrib

        # security software: share of the lead measure (cpu without a worker resource)
        $leadRes = 'cpu'; if ($null -ne $inc.Lead -and $workerOrder -contains $inc.Lead) { $leadRes = [string]$inc.Lead }
        $leadTable = @(& $getTable $leadRes)
        $prod = @{}
        foreach ($e in $leadTable) {
            $pr = $Model.Proc[$e.K]
            if ([string]$pr.Role -ne 'Sicherheit') { continue }
            $label = [string]$pr.RoleLabel
            if (-not $prod.ContainsKey($label)) { $prod[$label] = 0.0 }
            $prod[$label] += $e.Share
        }
        $products = New-Object System.Collections.Generic.List[object]
        $totalPct = 0.0
        foreach ($label in @($prod.Keys | Sort-Object -Property @{ Expression = { $prod[$_] }; Descending = $true }, @{ Expression = { $_ } })) {
            $products.Add(@{ Label = $label; SharePct = (Format-WorkerPerfRound $prod[$label]) }); $totalPct += $prod[$label]
        }
        $inc['Security'] = @{ Products = $products.ToArray(); TotalPct = (Format-WorkerPerfRound $totalPct) }

        # companion: a security process among the contributors, plus the biggest I/O producer
        $companion = $null
        $companionOrder = @(@($resources | Where-Object { $_ -eq $inc.Lead }) + @($resources | Where-Object { $_ -ne $inc.Lead }))
        foreach ($r in $companionOrder) {
            $sec = @($contrib[$r].Processes | Where-Object { $_.Role -eq 'Sicherheit' -and $_.SharePct -ge $script:WorkerPerfCompanionMinPct })
            if ($sec.Count -eq 0) { continue }
            $byLabel = @{}
            foreach ($x in $sec) { if (-not $byLabel.ContainsKey($x.RoleLabel)) { $byLabel[$x.RoleLabel] = 0.0 }; $byLabel[$x.RoleLabel] += $x.SharePct }
            $label = @($byLabel.Keys | Sort-Object -Property @{ Expression = { $byLabel[$_] }; Descending = $true }, @{ Expression = { $_ } })[0]
            $ioTable = @(Get-WorkerPerfShareTable -Model $Model -Measure 'io' -WindowSnaps ([int[]]$snaps) -BaseSnaps @() -SessionFilter @() -Cache @{})
            $topIo = @(Group-WorkerPerfShareTable -Model $Model -Table $ioTable -By 'app-in-session' -SkipSecurity $true)
            $topApp = ''; $topUser = ''; $topSession = -1
            if ($topIo.Count -gt 0) { $topApp = $topIo[0].Name; $topSession = $topIo[0].SessionIndex; $topUser = Get-WorkerPerfUserName $Model $topSession }
            $companion = @{ Label = [string]$label; SharePct = (Format-WorkerPerfRound $byLabel[$label]); Resource = $r; TopIoApp = $topApp; TopIoUser = $topUser; TopIoSessionIndex = $topSession }
            break
        }
        $inc['Companion'] = $companion

        # processes with the highest input delay in the window, summed per process
        $delay = @{}
        $ip = $Model.InputProc
        $nIp = @($ip.TickPos).Count
        $tickSet = @{}; foreach ($i in $ticks) { $tickSet[$i] = $true }
        for ($j = 0; $j -lt $nIp; $j++) {
            if (-not $tickSet.ContainsKey([int]$ip.TickPos[$j])) { continue }
            $d = [double]$ip.DelayMs[$j]
            if ([double]::IsNaN($d)) { continue }
            $k = [int]$ip.K[$j]
            $key = 'k' + $k
            if ($k -lt 0) { $key = 'p' + [string]$ip.Pid[$j] + '|' + [string]$ip.Name[$j] + '|' + [string]$ip.SessionIndex[$j] }
            if (-not $delay.ContainsKey($key) -or $d -gt $delay[$key].MaxMs) {
                $role = ''
                if ($k -ge 0 -and $k -lt @($Model.Proc).Count -and $null -ne $Model.Proc[$k]) { $role = [string]$Model.Proc[$k].Role }
                $delay[$key] = @{ Name = [string]$ip.Name[$j]; Pid = [int]$ip.Pid[$j]; K = $k; SessionIndex = [int]$ip.SessionIndex[$j]; MaxMs = $d; Role = $role }
            }
        }
        $inc['DelayProcesses'] = @(@($delay.Values | Sort-Object -Property @{ Expression = { $_.MaxMs }; Descending = $true }, @{ Expression = { $_.Name } }, @{ Expression = { $_.Pid } }, @{ Expression = { $_.K } }, @{ Expression = { $_.SessionIndex } }) | Select-Object -First 5)

        # endpoint probes and ICA round trip in the widened window
        $endpoints = New-Object System.Collections.Generic.List[object]
        foreach ($pb in @($Model.Probes)) {
            $max = $null; $failed = $false
            foreach ($p in $wideSnaps) {
                if (-not [string]::IsNullOrEmpty([string]$pb.Error[$p])) { $failed = $true; continue }
                $v = [double]$pb.Ms[$p]
                if (-not [double]::IsNaN($v) -and ($null -eq $max -or $v -gt $max)) { $max = $v }
            }
            if ($failed -or $null -ne $max) { $endpoints.Add(@{ Name = [string]$pb.Name; Role = [string]$pb.Role; MaxMs = $max; Failed = $failed }) }
        }
        $inc['Endpoints'] = @($endpoints.ToArray() | Sort-Object -Property @{ Expression = { $_.Failed }; Descending = $true }, @{ Expression = { if ($null -eq $_.MaxMs) { -1.0 } else { $_.MaxMs } }; Descending = $true }, @{ Expression = { $_.Name } })
        $ica = New-Object System.Collections.Generic.List[object]
        if (-not [double]::IsNaN($icaWarn)) {
            foreach ($s in @($Model.Sessions)) {
                $max = [double]::NaN
                foreach ($p in $wideSnaps) {
                    $v = [double]$s.Rtt[$p]
                    if (-not [double]::IsNaN($v) -and $v -ge $icaWarn -and ([double]::IsNaN($max) -or $v -gt $max)) { $max = $v }
                }
                if (-not [double]::IsNaN($max)) { $ica.Add(@{ SessionIndex = [int]$s.Index; MaxMs = $max }) }
            }
        }
        $inc['Ica'] = @($ica.ToArray() | Sort-Object -Property @{ Expression = { $_.MaxMs }; Descending = $true }, @{ Expression = { $_.SessionIndex } })

        # events and scans in the window
        $inc['Events'] = @(@($Model.Events) | Where-Object { [long]$_.TimeMs -ge $start -and [long]$_.TimeMs -le $end })
        $scan = $false
        foreach ($sc in @($Model.Scans)) { if ([long]$sc.StartMs -le $end -and [long]$sc.EndMs -ge $start) { $scan = $true; break } }
        $inc['ScanActive'] = $scan
    }
}

function Get-WorkerPerfLeadFinding($Incident) {
    # highest severity (then earliest start) among the findings of the lead resource; without a lead, among all findings
    $pool = @($Incident.Findings)
    if ($null -ne $Incident.Lead) {
        $sel = @($pool | Where-Object { $_.Resource -eq $Incident.Lead })
        if ($sel.Count -gt 0) { $pool = $sel }
    }
    elseif ($Incident.Type -eq 'ohne-engpass') {
        $sel = @($pool | Where-Object { $_.Resource -eq 'input' })
        if ($sel.Count -gt 0) { $pool = $sel }
    }
    else {
        $sel = @($pool | Where-Object { $_.Resource -eq 'network' -or $_.Resource -eq 'endpoint' })
        if ($sel.Count -gt 0) { $pool = $sel }
    }
    if ($pool.Count -eq 0) { return $null }
    return @($pool | Sort-Object -Property @{ Expression = { [int]$_.Severity }; Descending = $true }, @{ Expression = { $_.StartMs } })[0]
}

function Get-WorkerPerfIncidentText {
    param($Incident, $Model, $Thresholds, [hashtable]$Texts)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $fmt = { param([string]$Key, [object[]]$A) [string]::Format($inv, $Texts[$Key], $A) }
    $userText = {
        param([int]$SessionIndex, [string]$User)
        if ($User -ne '') { return $User }
        $s = Get-WorkerPerfSessionRecord $Model $SessionIndex
        if ($null -ne $s -and [int]$s.Sid -eq 0) { return $Texts['user.system'] }
        return $Texts['user.unknown']
    }
    $off = [int]$Model.Meta.OffsetMinutes
    $t0 = Format-WorkerPerfClock ([long]$Incident.StartMs) $off
    $t1 = Format-WorkerPerfClock ([long]$Incident.EndMs) $off
    $lead = Get-WorkerPerfLeadFinding $Incident
    $unit = ''; $ideal = ''; $label = ''
    if ($null -ne $lead) {
        $unit = Get-WorkerPerfThresholdField $Thresholds ([string]$lead.SignalId) 'unit'
        $ideal = Get-WorkerPerfThresholdField $Thresholds ([string]$lead.SignalId) 'ideal'
        $label = [string]$lead.Label
        if ($lead.Resource -eq 'input' -or $lead.Resource -eq 'network') { $label = Get-WorkerPerfThresholdField $Thresholds ([string]$lead.SignalId) 'label' }
    }
    $text = ''
    $affectedCount = @($Incident.Affected).Count
    $affectedText = $Texts['affected.none']
    if ($affectedCount -eq 1) { $affectedText = $Texts['affected.one'] }
    elseif ($affectedCount -gt 1) { $affectedText = & $fmt 'affected.many' @($affectedCount) }
    elseif ($Incident.Chronic) { $affectedText = '' }

    $headLabel = ''
    $ctxItem = {
        param($Entry)
        $thLabel = Get-WorkerPerfThresholdField $Thresholds ([string]$Entry.SignalId) 'label'
        if ($thLabel -eq '' -or [string]$Entry.Label -eq '' -or [string]$Entry.Label -eq $thLabel) { if ($thLabel -eq '') { return [string]$Entry.Label }; return $thLabel }
        return (& $fmt 'chronic.item' @($thLabel, [string]$Entry.Label))
    }
    if ($Incident.Type -eq 'engpass' -and $null -ne $lead) {
        $peak = Format-WorkerPerfValue ([double]$lead.PeakValue) $unit
        $ownLead = $false
        if ($null -ne $Incident.Lead) { $ownLead = (@(@($Incident.Findings) | Where-Object { $_.Resource -eq $Incident.Lead }).Count -gt 0) }
        if ($null -ne $Incident.Lead -and -not $ownLead) {
            # the lead resource comes from a chronic state only: name that state in the head
            $expl = @(@($Incident.ChronicContext) | Where-Object { $_.Explains })
            $match = @($expl | Where-Object { $_ -is [hashtable] -and $_.ContainsKey('Resource') -and $_['Resource'] -eq $Incident.Lead })
            if ($match.Count -eq 0) { $match = $expl }
            if ($match.Count -gt 0) { $headLabel = & $ctxItem @($match | Sort-Object -Property @{ Expression = { [int]$_.Severity }; Descending = $true })[0] }
            $text = & $fmt 'engpass.chronic' @($t0, $t1, $Texts['resource.' + [string]$Incident.Lead], $headLabel, $label, $peak, $ideal)
        }
        else {
            $text = & $fmt 'engpass' @($t0, $t1, $Texts['resource.' + [string]$lead.Resource], $label, $peak, $ideal)
        }
        $text += $affectedText
        $rank = $null
        if ($null -ne $Incident.Lead -and $Incident.Contributors.ContainsKey([string]$Incident.Lead)) { $rank = $Incident.Contributors[[string]$Incident.Lead] }
        if ($null -ne $rank -and $null -ne $rank.Main) {
            $m = $rank.Main
            $who = & $userText ([int]$m.SessionIndex) ([string]$m.User)
            $measure = $Texts['measure.' + [string]$rank.Measure]
            if ($null -eq $m.BaselinePct) { $text += & $fmt 'main.nobase' @($m.App, $who, (Format-WorkerPerfNumber $m.SharePct), $measure) }
            else { $text += & $fmt 'main' @($m.App, $who, (Format-WorkerPerfNumber $m.SharePct), $measure, (Format-WorkerPerfNumber $m.BaselinePct)) }
        }
        $c = $Incident.Companion
        if ($null -ne $c) {
            $cm = $Texts['measure.' + [string]$Incident.Contributors[[string]$c.Resource].Measure]
            $who = & $userText ([int]$c.TopIoSessionIndex) ([string]$c.TopIoUser)
            $text += & $fmt 'companion' @($c.Label, (Format-WorkerPerfNumber $c.SharePct), $cm, $c.TopIoApp, $who)
        }
    }
    elseif ($Incident.Type -eq 'ohne-engpass' -and $null -ne $lead) {
        $text = & $fmt 'ohne' @($t0, $t1, (Format-WorkerPerfValue ([double]$lead.PeakValue) $unit), $ideal)
        $text += $affectedText
        $dp = @($Incident.DelayProcesses)
        if ($dp.Count -gt 0) {
            $who = & $userText ([int]$dp[0].SessionIndex) (Get-WorkerPerfUserName $Model ([int]$dp[0].SessionIndex))
            $text += & $fmt 'ohne.process' @($dp[0].Name, $who)
        }
        $text += $Texts['ohne.cause']
        $probeUnit = Get-WorkerPerfThresholdField $Thresholds 'probe.connect' 'unit'
        foreach ($e in @($Incident.Endpoints)) {
            if ($e.Failed) { $text += & $fmt 'endpoint.context' @($e.Name, $Texts['probe.error']) }
            elseif ($null -ne $e.MaxMs -and $e.MaxMs -ge 50) { $text += & $fmt 'endpoint.context' @($e.Name, (Format-WorkerPerfValue ([double]$e.MaxMs) $probeUnit)) }
        }
    }
    elseif ($null -ne $lead) {
        if ($lead.Resource -eq 'endpoint') {
            $pk = $Texts['probe.error']
            if (-not [double]::IsNaN([double]$lead.PeakValue) -and -not [double]::IsInfinity([double]$lead.PeakValue)) { $pk = Format-WorkerPerfValue ([double]$lead.PeakValue) $unit }
            $text = & $fmt 'umfeld.endpoint' @($t0, $t1, $lead.Instance, $pk)
        }
        else {
            $who = & $userText ([int]$lead.SessionIndex) (Get-WorkerPerfUserName $Model ([int]$lead.SessionIndex))
            $text = & $fmt 'umfeld.network' @($t0, $t1, $who, $label, (Format-WorkerPerfValue ([double]$lead.PeakValue) $unit), $ideal)
        }
    }
    if ($Incident.Chronic) { $text = $Texts['chronic.prefix'] + $text }
    $ctx = @(@($Incident.ChronicContext) | ForEach-Object { & $ctxItem $_ } | Where-Object { $headLabel -eq '' -or $_ -ne $headLabel })
    if ($ctx.Count -gt 0) { $text += & $fmt 'chronic.context' @(($ctx -join ', ')) }
    return $text
}
