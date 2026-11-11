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
