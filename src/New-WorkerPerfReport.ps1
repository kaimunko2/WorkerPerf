#Requires -Version 5.1
<#
.SYNOPSIS
    Builds a self-contained, offline HTML report from a WorkerPerf capture folder.

.DESCRIPTION
    Reads the CSV files written by Start-WorkerPerfCapture.ps1 and aggregates them for the
    measurement period by host, by user session, by application (process name) and by
    individual process. The result is a single HTML file without external dependencies.

    Runs on Windows PowerShell 5.1 and PowerShell 7 (any platform) - the analysis does not
    have to happen on the VDA itself.

.PARAMETER Path
    Capture folder (contains meta.json, system.csv, ...).

.PARAMETER OutFile
    Target file. Default: <Path>\report.html

.PARAMETER TopProcesses
    Number of individual processes (by CPU time and by peak memory each) kept in the report.

.PARAMETER From
    Only analyse samples at or after this time.

.PARAMETER To
    Only analyse samples at or before this time.

.EXAMPLE
    .\New-WorkerPerfReport.ps1 -Path D:\WorkerPerf\VDA01_20260101-080000

.EXAMPLE
    .\New-WorkerPerfReport.ps1 -Path .\run -From '2026-01-01 09:00' -To '2026-01-01 11:30'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)][string]$Path,
    [string]$OutFile,
    [ValidateRange(10, 2000)][int]$TopProcesses = 150,
    [datetime]$From = [datetime]::MinValue,
    [datetime]$To = [datetime]::MaxValue
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture
$MaxBuckets = 400

#region ---------- helpers ----------------------------------------------------------------

function Split-CsvLine([string]$Line) {
    if ($Line.IndexOf('"') -lt 0) { return , $Line.Split(',') }
    $out = New-Object System.Collections.Generic.List[string]
    $sb = New-Object System.Text.StringBuilder
    $inQ = $false
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $c = $Line[$i]
        if ($inQ) {
            if ($c -eq '"') {
                if ($i + 1 -lt $Line.Length -and $Line[$i + 1] -eq '"') { [void]$sb.Append('"'); $i++ } else { $inQ = $false }
            }
            else { [void]$sb.Append($c) }
        }
        elseif ($c -eq '"') { $inQ = $true }
        elseif ($c -eq ',') { $out.Add($sb.ToString()); [void]$sb.Clear() }
        else { [void]$sb.Append($c) }
    }
    $out.Add($sb.ToString())
    return , $out.ToArray()
}

function Read-CsvRows([string]$File, [scriptblock]$OnRow) {
    # Streams a CSV file; calls $OnRow with the field array of every data row.
    if (-not (Test-Path -LiteralPath $File)) { return }
    $reader = New-Object System.IO.StreamReader ($File, [Text.Encoding]::UTF8)
    try {
        [void]$reader.ReadLine()
        while ($null -ne ($line = $reader.ReadLine())) {
            if ($line.Length -eq 0) { continue }
            & $OnRow (Split-CsvLine $line)
        }
    }
    finally { $reader.Dispose() }
}

function ConvertTo-Number([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return [double]::NaN }
    return [double]::Parse($Text, $inv)
}

function ConvertTo-EpochMs([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return $null }
    return [DateTimeOffset]::Parse($Text, $inv).ToUnixTimeMilliseconds()
}

function Format-JsonNumber([double]$Value, [int]$Decimals) {
    if ([double]::IsNaN($Value) -or [double]::IsInfinity($Value)) { return 'null' }
    return [Math]::Round($Value, $Decimals).ToString($inv)
}

function Format-JsonString([string]$Text) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($c in $Text.ToCharArray()) {
        $code = [int]$c
        if ($c -eq '"') { [void]$sb.Append('\"') }
        elseif ($c -eq '\') { [void]$sb.Append('\\') }
        elseif ($code -lt 32 -or $c -eq '<' -or $c -eq '>' -or $c -eq '&' -or $code -eq 0x2028 -or $code -eq 0x2029) { [void]$sb.Append('\u' + $code.ToString('x4')) }
        else { [void]$sb.Append($c) }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function ConvertTo-JsonText($Value, [System.Text.StringBuilder]$Sb) {
    # Small, fast JSON writer. A StringBuilder value is inserted verbatim (pre-rendered series).
    if ($null -eq $Value) { [void]$Sb.Append('null'); return }
    if ($Value -is [System.Text.StringBuilder]) { [void]$Sb.Append($Value.ToString()); return }
    if ($Value -is [string]) { [void]$Sb.Append((Format-JsonString $Value)); return }
    if ($Value -is [bool]) { [void]$Sb.Append($(if ($Value) { 'true' } else { 'false' })); return }
    if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) { [void]$Sb.Append((Format-JsonNumber ([double]$Value) 3)); return }
    if ($Value -is [ValueType]) { [void]$Sb.Append(([IConvertible]$Value).ToString($inv)); return }
    if ($Value -is [System.Collections.IDictionary]) {
        [void]$Sb.Append('{')
        $first = $true
        foreach ($k in $Value.Keys) {
            if (-not $first) { [void]$Sb.Append(',') }
            $first = $false
            [void]$Sb.Append((Format-JsonString ([string]$k))).Append(':')
            ConvertTo-JsonText $Value[$k] $Sb
        }
        [void]$Sb.Append('}')
        return
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        [void]$Sb.Append('[')
        $first = $true
        foreach ($v in $Value) {
            if (-not $first) { [void]$Sb.Append(',') }
            $first = $false
            ConvertTo-JsonText $v $Sb
        }
        [void]$Sb.Append(']')
        return
    }
    [void]$Sb.Append((Format-JsonString ([string]$Value)))
}

function Get-Stats([double[]]$Values) {
    # avg / 95th percentile / max of the given values (NaN values must be removed by the caller)
    if ($Values.Length -eq 0) { return @{ Avg = [double]::NaN; P95 = [double]::NaN; Max = [double]::NaN } }
    $sorted = [double[]]$Values.Clone()
    [Array]::Sort($sorted)
    $sum = 0.0
    foreach ($v in $sorted) { $sum += $v }
    $idx = [int][Math]::Ceiling(0.95 * $sorted.Length) - 1
    if ($idx -lt 0) { $idx = 0 }
    return @{ Avg = $sum / $sorted.Length; P95 = $sorted[$idx]; Max = $sorted[$sorted.Length - 1] }
}

function Get-BucketSeries([double[]]$Values, [int]$Decimals, [switch]$UseMax) {
    # Reduces a per-sample array (NaN = no data) to $nB buckets; returns JSON text.
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('[')
    for ($b = 0; $b -lt $nB; $b++) {
        $from = $b * $per; $to = [Math]::Min($nS, $from + $per)
        $sum = 0.0; $cnt = 0; $max = [double]::NegativeInfinity
        for ($i = $from; $i -lt $to; $i++) {
            $v = $Values[$i]
            if ($v -ne $v) { continue }     # NaN
            $sum += $v; $cnt++
            if ($v -gt $max) { $max = $v }
        }
        if ($b -gt 0) { [void]$sb.Append(',') }
        if ($cnt -eq 0) { [void]$sb.Append('null') }
        elseif ($UseMax) { [void]$sb.Append([Math]::Round($max, $Decimals).ToString($inv)) }
        else { [void]$sb.Append([Math]::Round($sum / $cnt, $Decimals).ToString($inv)) }
    }
    [void]$sb.Append(']')
    return $sb
}

function New-NaNArray([int]$Length) {
    $a = New-Object double[] $Length
    for ($i = 0; $i -lt $Length; $i++) { $a[$i] = [double]::NaN }
    return , $a
}

function New-Entity {
    # Per-sample accumulators of a group of processes (a session or an application).
    return @{
        CpuMs = (New-Object double[] $nS); Ws = (New-Object double[] $nS); Priv = (New-Object double[] $nS)
        Io = (New-Object double[] $nS); N = (New-Object int[] $nS)
    }
}

function Get-EntitySummary($Entity) {
    # Turns the per-sample accumulators into statistics and bucket series.
    $cpuPct = New-NaNArray $nS; $wsMB = New-NaNArray $nS; $privMB = New-NaNArray $nS; $ioKBs = New-NaNArray $nS
    $present = 0; $cpuMs = 0.0; $io = 0.0; $nSum = 0; $nMax = 0
    $cpuL = New-Object System.Collections.Generic.List[double]
    $wsL = New-Object System.Collections.Generic.List[double]
    $privL = New-Object System.Collections.Generic.List[double]
    for ($i = 0; $i -lt $nS; $i++) {
        $n = $Entity.N[$i]
        if ($n -eq 0) { continue }
        $present++; $nSum += $n
        if ($n -gt $nMax) { $nMax = $n }
        $cpuMs += $Entity.CpuMs[$i]; $io += $Entity.Io[$i]
        $pct = $Entity.CpuMs[$i] / $capMs[$i] * 100.0
        $cpuPct[$i] = $pct; $cpuL.Add($pct)
        $wsMB[$i] = $Entity.Ws[$i] / 1024.0; $wsL.Add($wsMB[$i])
        $privMB[$i] = $Entity.Priv[$i] / 1024.0; $privL.Add($privMB[$i])
        $ioKBs[$i] = $Entity.Io[$i] / 1024.0 / $elapsed[$i]
    }
    $c = Get-Stats $cpuL.ToArray(); $w = Get-Stats $wsL.ToArray(); $p = Get-Stats $privL.ToArray()
    return @{
        Present = $present; CpuSec = $cpuMs / 1000.0; IoMB = $io / 1MB
        CpuAvg = $c.Avg; CpuP95 = $c.P95; CpuMax = $c.Max
        WsAvg = $w.Avg; WsMax = $w.Max; PrivAvg = $p.Avg; PrivMax = $p.Max
        NAvg = $(if ($present) { $nSum / $present } else { 0 }); NMax = $nMax
        SeriesCpu = (Get-BucketSeries $cpuPct 2); SeriesWs = (Get-BucketSeries $wsMB 0); SeriesIo = (Get-BucketSeries $ioKBs 0)
    }
}

#endregion

#region ---------- load: meta + system ----------------------------------------------------

$Path = (Resolve-Path -LiteralPath $Path).Path
if (-not $OutFile) { $OutFile = Join-Path $Path 'report.html' }
$templateFile = Join-Path $PSScriptRoot 'report-template.html'
if (-not (Test-Path -LiteralPath $templateFile)) { throw "Vorlage nicht gefunden: $templateFile" }
foreach ($f in 'meta.json', 'system.csv', 'procinfo.csv', 'processes.csv') {
    if (-not (Test-Path -LiteralPath (Join-Path $Path $f))) { throw "Datei fehlt im Aufzeichnungsordner: $f" }
}

$timer = [Diagnostics.Stopwatch]::StartNew()
$meta = Get-Content -LiteralPath (Join-Path $Path 'meta.json') -Raw | ConvertFrom-Json
$cores = [int]$meta.LogicalProcessors
if ($cores -lt 1) { $cores = 1 }

Write-Host 'Lese system.csv ...'
$sysRows = New-Object System.Collections.Generic.List[object]
$fromMs = $(if ($From -gt [datetime]::MinValue) { ([DateTimeOffset]$From).ToUnixTimeMilliseconds() } else { [long]::MinValue })
$toMs = $(if ($To -lt [datetime]::MaxValue) { ([DateTimeOffset]$To).ToUnixTimeMilliseconds() } else { [long]::MaxValue })
$sysHeader = (Get-Content -LiteralPath (Join-Path $Path 'system.csv') -TotalCount 1).Split(',')
$offsetMin = 0; $offsetKnown = $false
Read-CsvRows (Join-Path $Path 'system.csv') {
    param($f)
    if ($f.Length -lt $sysHeader.Length) { return }     # truncated last line of an aborted capture
    $dto = [DateTimeOffset]::Parse($f[1], $inv)
    $ms = $dto.ToUnixTimeMilliseconds()
    if ($ms -lt $fromMs -or $ms -gt $toMs) { return }
    if (-not $script:offsetKnown) { $script:offsetMin = [int]$dto.Offset.TotalMinutes; $script:offsetKnown = $true }
    $row = @{ Ms = $ms }
    for ($i = 0; $i -lt $sysHeader.Length; $i++) { if ($i -ne 1) { $row[$sysHeader[$i]] = ConvertTo-Number $f[$i] } }
    $sysRows.Add($row)
}
$nS = $sysRows.Count
if ($nS -lt 1) { throw 'Keine Messungen im gewaehlten Zeitraum gefunden.' }

# sample number in the files -> position in the analysed range
$firstSample = [int]$sysRows[0].S
$lastSample = [int]$sysRows[$nS - 1].S
$posOf = New-Object int[] ($lastSample - $firstSample + 1)
for ($i = 0; $i -lt $posOf.Length; $i++) { $posOf[$i] = -1 }
$elapsed = New-Object double[] $nS      # seconds covered by each sample
$capMs = New-Object double[] $nS        # CPU capacity of the host within the sample in ms
$totalSec = 0.0
for ($i = 0; $i -lt $nS; $i++) {
    $r = $sysRows[$i]
    $posOf[[int]$r.S - $firstSample] = $i
    $e = $r.ElapsedSec
    if ($e -ne $e -or $e -le 0) { $e = [double]$meta.IntervalSeconds }
    $elapsed[$i] = $e; $capMs[$i] = $e * 1000.0 * $cores; $totalSec += $e
}
$per = [int][Math]::Ceiling($nS / $MaxBuckets)
$nB = [int][Math]::Ceiling($nS / $per)

function Get-SystemColumn([string]$Name, [double]$Scale = 1.0) {
    $a = New-Object double[] $nS
    for ($i = 0; $i -lt $nS; $i++) { $a[$i] = $sysRows[$i][$Name] * $Scale }
    return , $a
}
function Get-CleanStats([double[]]$Values) {
    $l = New-Object System.Collections.Generic.List[double]
    foreach ($v in $Values) { if ($v -eq $v) { $l.Add($v) } }
    return Get-Stats $l.ToArray()
}

$ramMB = [double]$meta.PhysicalMemoryMB
$sysCpu = Get-SystemColumn 'CpuPct'
$sysAvail = Get-SystemColumn 'MemAvailMB'
$sysUsedGB = New-Object double[] $nS
for ($i = 0; $i -lt $nS; $i++) { $sysUsedGB[$i] = ($ramMB - $sysAvail[$i]) / 1024.0 }
$sysCommitGB = Get-SystemColumn 'MemCommittedMB' (1 / 1024.0)
$sysDiskR = Get-SystemColumn 'DiskReadBps' (1 / 1MB)
$sysDiskW = Get-SystemColumn 'DiskWriteBps' (1 / 1MB)
$sysIopsR = Get-SystemColumn 'DiskReadIops'
$sysIopsW = Get-SystemColumn 'DiskWriteIops'
$sysNetR = Get-SystemColumn 'NetRecvBps' (8 / 1e6)
$sysNetS = Get-SystemColumn 'NetSentBps' (8 / 1e6)
$sysSess = Get-SystemColumn 'Sessions'
$sysActive = Get-SystemColumn 'ActiveSessions'
$sysProcs = Get-SystemColumn 'Processes'
$sysQueue = Get-SystemColumn 'ProcQueue'
$sysCommitLimit = Get-SystemColumn 'MemCommitLimitMB' (1 / 1024.0)

$tSeries = New-Object System.Text.StringBuilder
[void]$tSeries.Append('[')
for ($b = 0; $b -lt $nB; $b++) {
    if ($b -gt 0) { [void]$tSeries.Append(',') }
    [void]$tSeries.Append(([long]$sysRows[$b * $per].Ms).ToString($inv))
}
[void]$tSeries.Append(']')

#endregion

#region ---------- load: sessions ---------------------------------------------------------

Write-Host 'Lese sessions.csv ...'
$sessions = New-Object System.Collections.Generic.List[object]    # session entities
$sessMap = @{}        # "<pos>|<sessionId>" -> session entity
$curBySid = @{}       # sessionId -> entity currently using that id

function New-SessionEntity([int]$Sid) {
    $e = New-Entity
    $e.Index = $sessions.Count; $e.Sid = $Sid; $e.User = ''; $e.Domain = ''; $e.Client = ''; $e.Logon = $null
    $e.FirstPos = -1; $e.LastPos = -1; $e.ActiveN = 0; $e.SeenN = 0; $e.IdleMax = [double]::NaN
    $e.Rtt = $null
    $sessions.Add($e)
    return $e
}

Read-CsvRows (Join-Path $Path 'sessions.csv') {
    param($f)
    if ($f.Length -lt 9) { return }
    $s = [int]$f[0] - $firstSample
    if ($s -lt 0 -or $s -ge $posOf.Length) { return }
    $pos = $posOf[$s]
    if ($pos -lt 0) { return }
    $sid = [int]$f[1]; $user = $f[2]
    $e = $curBySid[$sid]
    # A session id is reused after logoff: start a new entity when the id was gone for a
    # sample or when a different user owns it now. Session 0 (services) is always one entity.
    if ($null -ne $e -and $sid -ne 0) {
        if ($e.LastPos -lt $pos - 1) { $e = $null }
        elseif ($user -and $e.User -and ($user -ne $e.User -or $f[3] -ne $e.Domain)) { $e = $null }
    }
    if ($null -eq $e) { $e = New-SessionEntity $sid; $curBySid[$sid] = $e }
    if ($user) { $e.User = $user; $e.Domain = $f[3] }
    if ($f[6]) { $e.Client = $f[6] }
    if ($f[7] -and $null -eq $e.Logon) { $e.Logon = ConvertTo-EpochMs $f[7] }
    if ($e.FirstPos -lt 0) { $e.FirstPos = $pos }
    $e.LastPos = $pos; $e.SeenN++
    if ($f[4] -eq 'Active') { $e.ActiveN++ }
    $idle = ConvertTo-Number $f[8]
    if ($idle -eq $idle -and -not ($e.IdleMax -ge $idle)) { $e.IdleMax = $idle }
    $sessMap["$pos|$sid"] = $e
}

#endregion

#region ---------- load: process catalogue ------------------------------------------------

Write-Host 'Lese procinfo.csv ...'
$procInfo = New-Object System.Collections.Generic.List[object]
Read-CsvRows (Join-Path $Path 'procinfo.csv') {
    param($f)
    if ($f.Length -lt 7) { return }
    $k = [int]$f[0]
    while ($procInfo.Count -le $k) { $procInfo.Add($null) }
    $procInfo[$k] = @{ K = $k; Pid = [int]$f[1]; Name = $f[3]; Sid = [int]$f[4]; Start = $f[5]; Path = $f[6]; Cmd = $(if ($f.Length -gt 7) { $f[7] } else { '' }) }
}
$nK = $procInfo.Count

$apps = New-Object System.Collections.Generic.List[object]
$appByName = @{}
$procAgg = New-Object object[] $nK      # per process: accumulators (see index constants)
$procSess = New-Object object[] $nK     # per process: session entity
$procApp = New-Object object[] $nK      # per process: application entity
$procPair = New-Object object[] $nK     # per process: session x application record
$pairs = @{}                            # "<sessionIndex>|<appIndex>" -> record
# procAgg indices
$A_CPU = 0; $A_CPUMAX = 1; $A_WSSUM = 2; $A_WSMAX = 3; $A_PRIVMAX = 4; $A_IO = 5; $A_N = 6; $A_FIRST = 7; $A_LAST = 8; $A_HANDLES = 9; $A_THREADS = 10

#endregion

#region ---------- pass 1: aggregate all process samples ----------------------------------

Write-Host 'Lese processes.csv (Durchlauf 1/2) ...'
$reader = New-Object System.IO.StreamReader ((Join-Path $Path 'processes.csv'), [Text.Encoding]::UTF8)
$rowCount = 0
$totalCpuMs = 0.0
$posLen = $posOf.Length
try {
    [void]$reader.ReadLine()
    while ($null -ne ($line = $reader.ReadLine())) {
        $f = $line.Split(',')
        if ($f.Length -lt 10) { continue }
        $s = [int]$f[0] - $firstSample
        if ($s -lt 0 -or $s -ge $posLen) { continue }
        $pos = $posOf[$s]
        if ($pos -lt 0) { continue }
        $k = [int]$f[1]
        if ($k -ge $nK) { continue }
        $cpu = [double]$f[2]; $ws = [double]$f[3]; $priv = [double]$f[4]
        $io = [double]$f[5] + [double]$f[6]
        $rowCount++

        $a = $procAgg[$k]
        if ($null -eq $a) {
            # first row of this process: resolve its session, application and pair once
            $info = $procInfo[$k]
            if ($null -eq $info) { continue }
            $a = New-Object double[] 11
            $a[$A_FIRST] = $pos
            $procAgg[$k] = $a

            $se = $sessMap["$pos|$($info.Sid)"]
            if ($null -eq $se) {
                $se = $curBySid["orphan$($info.Sid)"]
                if ($null -eq $se) { $se = New-SessionEntity $info.Sid; $curBySid["orphan$($info.Sid)"] = $se }
            }
            $procSess[$k] = $se

            $appKey = $info.Name.ToLowerInvariant()
            $ae = $appByName[$appKey]
            if ($null -eq $ae) {
                $ae = New-Entity
                $ae.Index = $apps.Count; $ae.Name = $info.Name; $ae.Instances = 0; $ae.Path = $info.Path
                $apps.Add($ae); $appByName[$appKey] = $ae
            }
            $ae.Instances++
            $procApp[$k] = $ae

            $pairKey = "$($se.Index)|$($ae.Index)"
            $pr = $pairs[$pairKey]
            if ($null -eq $pr) {
                # cpuMs, wsSum, io, instances, current pos, ws at current pos, max ws
                $pr = @{ S = $se.Index; A = $ae.Index; V = (New-Object double[] 7) }
                $pr.V[4] = -1
                $pairs[$pairKey] = $pr
            }
            $pr.V[3]++
            $procPair[$k] = $pr
        }

        $a[$A_CPU] += $cpu
        $pct = $cpu / $capMs[$pos] * 100.0
        if ($pct -gt $a[$A_CPUMAX]) { $a[$A_CPUMAX] = $pct }
        $a[$A_WSSUM] += $ws
        if ($ws -gt $a[$A_WSMAX]) { $a[$A_WSMAX] = $ws }
        if ($priv -gt $a[$A_PRIVMAX]) { $a[$A_PRIVMAX] = $priv }
        $a[$A_IO] += $io
        $a[$A_N]++
        $a[$A_LAST] = $pos
        $h = [double]$f[8]; if ($h -gt $a[$A_HANDLES]) { $a[$A_HANDLES] = $h }
        $t = [double]$f[9]; if ($t -gt $a[$A_THREADS]) { $a[$A_THREADS] = $t }

        $e = $procSess[$k]
        $e.CpuMs[$pos] += $cpu; $e.Ws[$pos] += $ws; $e.Priv[$pos] += $priv; $e.Io[$pos] += $io; $e.N[$pos]++
        $e = $procApp[$k]
        $e.CpuMs[$pos] += $cpu; $e.Ws[$pos] += $ws; $e.Priv[$pos] += $priv; $e.Io[$pos] += $io; $e.N[$pos]++

        $v = $procPair[$k].V
        $v[0] += $cpu; $v[1] += $ws; $v[2] += $io
        if ($v[4] -ne $pos) {
            if ($v[5] -gt $v[6]) { $v[6] = $v[5] }
            $v[4] = $pos; $v[5] = 0
        }
        $v[5] += $ws
        $totalCpuMs += $cpu

        if ($rowCount % 500000 -eq 0) { Write-Host ("  {0:n0} Zeilen ..." -f $rowCount) }
    }
}
finally { $reader.Dispose() }
foreach ($pr in $pairs.Values) { if ($pr.V[5] -gt $pr.V[6]) { $pr.V[6] = $pr.V[5] } }
if ($totalCpuMs -le 0) { $totalCpuMs = 1 }

#endregion

#region ---------- citrix metrics ---------------------------------------------------------

$ctxAgg = @{}       # "<source>|<sessionIndex or instance>|<metric>" -> record
$hasRtt = $false
if (Test-Path -LiteralPath (Join-Path $Path 'citrix.csv')) {
    Write-Host 'Lese citrix.csv ...'
    Read-CsvRows (Join-Path $Path 'citrix.csv') {
        param($f)
        if ($f.Length -lt 6) { return }
        $s = [int]$f[0] - $firstSample
        if ($s -lt 0 -or $s -ge $posOf.Length) { return }
        $pos = $posOf[$s]
        if ($pos -lt 0) { return }
        $val = ConvertTo-Number $f[5]
        if ($val -ne $val) { return }
        $se = $null
        if ($f[2]) { $se = $sessMap["$pos|$($f[2])"] }
        $who = $(if ($null -ne $se) { "s$($se.Index)" } else { "i$($f[3])" })
        $key = "$($f[1])|$who|$($f[4])"
        $r = $ctxAgg[$key]
        if ($null -eq $r) {
            $r = @{ Source = $f[1]; Session = $(if ($null -ne $se) { $se.Index } else { $null }); Instance = $f[3]; Metric = $f[4]; Sum = 0.0; N = 0; Max = [double]::NegativeInfinity }
            $ctxAgg[$key] = $r
        }
        $r.Sum += $val; $r.N++
        if ($val -gt $r.Max) { $r.Max = $val }
        # the first round trip metric of a session is also kept as a time series
        if ($null -ne $se -and $f[4] -match 'Round') {
            if ($null -eq $se.Rtt) { $se.Rtt = New-NaNArray $nS; $se.RttMetric = $f[4] }
            if ($se.RttMetric -eq $f[4]) { $se.Rtt[$pos] = $val; $script:hasRtt = $true }
        }
    }
}

#endregion

#region ---------- summarise --------------------------------------------------------------

Write-Host 'Berechne Kennzahlen ...'
$sessOut = New-Object System.Collections.Generic.List[object]
foreach ($e in $sessions) {
    $sum = Get-EntitySummary $e
    if ($sum.Present -eq 0 -and $e.SeenN -eq 0) { continue }
    $first = $e.FirstPos; $last = $e.LastPos
    for ($i = 0; $i -lt $nS; $i++) { if ($e.N[$i] -gt 0) { if ($first -lt 0 -or $i -lt $first) { $first = $i }; break } }
    for ($i = $nS - 1; $i -ge 0; $i--) { if ($e.N[$i] -gt 0) { if ($i -gt $last) { $last = $i }; break } }
    $durSec = 0.0
    for ($i = $first; $i -le $last; $i++) { $durSec += $elapsed[$i] }
    $o = [ordered]@{
        i = $e.Index; id = $e.Sid; user = $e.User; domain = $e.Domain; client = $e.Client; logon = $e.Logon
        first = [long]$sysRows[$first].Ms; last = [long]$sysRows[$last].Ms; durMin = $durSec / 60.0
        activePct = $(if ($e.SeenN) { 100.0 * $e.ActiveN / $e.SeenN } else { $null })
        idleMaxMin = $(if ($e.IdleMax -eq $e.IdleMax) { $e.IdleMax / 60.0 } else { $null })
        cpuSec = $sum.CpuSec; cpuShare = 100.0 * $sum.CpuSec * 1000.0 / $totalCpuMs
        cpuAvg = $sum.CpuAvg; cpuP95 = $sum.CpuP95; cpuMax = $sum.CpuMax
        wsAvg = $sum.WsAvg; wsMax = $sum.WsMax; privAvg = $sum.PrivAvg; privMax = $sum.PrivMax
        ioMB = $sum.IoMB; procsAvg = $sum.NAvg; procsMax = $sum.NMax
        rttAvg = $null; rttP95 = $null; rttMax = $null
        cpu = $sum.SeriesCpu; ws = $sum.SeriesWs; io = $sum.SeriesIo; rtt = $null
    }
    if ($null -ne $e.Rtt) {
        $st = Get-CleanStats $e.Rtt
        $o.rttAvg = $st.Avg; $o.rttP95 = $st.P95; $o.rttMax = $st.Max
        $o.rtt = Get-BucketSeries $e.Rtt 0
    }
    $e.Present = $sum.Present
    $sessOut.Add($o)
}

$appOut = New-Object System.Collections.Generic.List[object]
$appSessions = @{}
foreach ($pr in $pairs.Values) { $appSessions[$pr.A] = 1 + [int]$appSessions[$pr.A] }
foreach ($e in $apps) {
    $sum = Get-EntitySummary $e
    $appOut.Add([ordered]@{
            i = $e.Index; name = $e.Name; path = $e.Path; inst = $e.Instances; sess = [int]$appSessions[$e.Index]
            instAvg = $sum.NAvg; instMax = $sum.NMax
            cpuSec = $sum.CpuSec; cpuShare = 100.0 * $sum.CpuSec * 1000.0 / $totalCpuMs
            cpuAvg = $sum.CpuAvg; cpuP95 = $sum.CpuP95; cpuMax = $sum.CpuMax
            wsAvg = $sum.WsAvg; wsMax = $sum.WsMax; privMax = $sum.PrivMax
            wsPerInst = $(if ($sum.NAvg -gt 0) { $sum.WsAvg / $sum.NAvg } else { $null })
            ioMB = $sum.IoMB
            cpu = $sum.SeriesCpu; ws = $sum.SeriesWs
        })
}

$pairOut = New-Object System.Collections.Generic.List[object]
foreach ($pr in $pairs.Values) {
    $present = $sessions[$pr.S].Present
    if ($present -lt 1) { $present = 1 }
    $pairOut.Add([ordered]@{
            s = $pr.S; a = $pr.A; inst = [int]$pr.V[3]; cpuSec = $pr.V[0] / 1000.0
            wsAvg = $pr.V[1] / 1024.0 / $present; wsMax = $pr.V[6] / 1024.0; ioMB = $pr.V[2] / 1MB
        })
}

# ---- choose the individual processes kept in the report ----
$allK = New-Object System.Collections.Generic.List[int]
for ($k = 0; $k -lt $nK; $k++) { if ($null -ne $procAgg[$k]) { $allK.Add($k) } }
$selected = @{}
foreach ($k in ($allK | Sort-Object { $procAgg[$_][$A_CPU] } -Descending | Select-Object -First $TopProcesses)) { $selected[$k] = $true }
foreach ($k in ($allK | Sort-Object { $procAgg[$_][$A_WSMAX] } -Descending | Select-Object -First $TopProcesses)) { $selected[$k] = $true }
foreach ($k in ($allK | Sort-Object { $procAgg[$_][$A_IO] } -Descending | Select-Object -First ([int]($TopProcesses / 3)))) { $selected[$k] = $true }
# ... plus the heaviest processes of every session, so each session detail view is meaningful
foreach ($g in ($allK | Group-Object { $procSess[$_].Index })) {
    foreach ($k in ($g.Group | Sort-Object { $procAgg[$_][$A_CPU] } -Descending | Select-Object -First 8)) { $selected[$k] = $true }
    foreach ($k in ($g.Group | Sort-Object { $procAgg[$_][$A_WSMAX] } -Descending | Select-Object -First 5)) { $selected[$k] = $true }
}

#endregion

#region ---------- pass 2: time series of the selected processes --------------------------

Write-Host "Lese processes.csv (Durchlauf 2/2, $($selected.Count) Prozesse) ..."
$series = @{}       # K -> @{ Cpu = double[nB]; Ws = double[nB]; Cap = double[nB]; N = int[nB] }
foreach ($k in $selected.Keys) { $series[$k] = @{ Cpu = (New-Object double[] $nB); Ws = (New-Object double[] $nB); Cap = (New-Object double[] $nB); N = (New-Object int[] $nB) } }
$isSel = New-Object bool[] $nK
foreach ($k in $selected.Keys) { $isSel[$k] = $true }
$reader = New-Object System.IO.StreamReader ((Join-Path $Path 'processes.csv'), [Text.Encoding]::UTF8)
try {
    [void]$reader.ReadLine()
    while ($null -ne ($line = $reader.ReadLine())) {
        # cheap pre-check of the key before splitting the whole line
        $c1 = $line.IndexOf(',')
        if ($c1 -lt 0) { continue }
        $c2 = $line.IndexOf(',', $c1 + 1)
        if ($c2 -lt 0) { continue }
        $k = [int]$line.Substring($c1 + 1, $c2 - $c1 - 1)
        if ($k -ge $nK -or -not $isSel[$k]) { continue }
        $f = $line.Split(',')
        if ($f.Length -lt 10) { continue }
        $s = [int]$f[0] - $firstSample
        if ($s -lt 0 -or $s -ge $posLen) { continue }
        $pos = $posOf[$s]
        if ($pos -lt 0) { continue }
        $b = [int][Math]::Floor($pos / $per)
        $sr = $series[$k]
        $sr.Cpu[$b] += [double]$f[2]; $sr.Ws[$b] += [double]$f[3]; $sr.Cap[$b] += $capMs[$pos]; $sr.N[$b]++
    }
}
finally { $reader.Dispose() }

$procOut = New-Object System.Collections.Generic.List[object]
foreach ($k in $selected.Keys) {
    $a = $procAgg[$k]; $info = $procInfo[$k]; $sr = $series[$k]
    $b0 = [int][Math]::Floor($a[$A_FIRST] / $per); $b1 = [int][Math]::Floor($a[$A_LAST] / $per)
    $sc = New-Object System.Text.StringBuilder; $sw = New-Object System.Text.StringBuilder
    [void]$sc.Append('['); [void]$sw.Append('[')
    for ($b = $b0; $b -le $b1; $b++) {
        if ($b -gt $b0) { [void]$sc.Append(','); [void]$sw.Append(',') }
        if ($sr.N[$b] -eq 0) { [void]$sc.Append('null'); [void]$sw.Append('null') }
        else {
            [void]$sc.Append([Math]::Round($sr.Cpu[$b] / $sr.Cap[$b] * 100.0, 2).ToString($inv))
            [void]$sw.Append([Math]::Round($sr.Ws[$b] / $sr.N[$b] / 1024.0, 0).ToString($inv))
        }
    }
    [void]$sc.Append(']'); [void]$sw.Append(']')
    $lifeSec = 0.0
    for ($i = [int]$a[$A_FIRST]; $i -le [int]$a[$A_LAST]; $i++) { $lifeSec += $elapsed[$i] }
    $procOut.Add([ordered]@{
            k = $k; pid = $info.Pid; name = $info.Name; s = $procSess[$k].Index; a = $procApp[$k].Index
            start = (ConvertTo-EpochMs $info.Start); path = $info.Path; cmd = $info.Cmd
            first = [long]$sysRows[[int]$a[$A_FIRST]].Ms; last = [long]$sysRows[[int]$a[$A_LAST]].Ms
            cpuSec = $a[$A_CPU] / 1000.0; cpuAvg = $a[$A_CPU] / ($lifeSec * 1000.0 * $cores) * 100.0; cpuMax = $a[$A_CPUMAX]
            wsAvg = $a[$A_WSSUM] / $a[$A_N] / 1024.0; wsMax = $a[$A_WSMAX] / 1024.0; privMax = $a[$A_PRIVMAX] / 1024.0
            ioMB = $a[$A_IO] / 1MB; handles = [int]$a[$A_HANDLES]; threads = [int]$a[$A_THREADS]
            o = $b0; cpu = $sc; ws = $sw
        })
}

$ctxOut = New-Object System.Collections.Generic.List[object]
foreach ($r in $ctxAgg.Values) {
    $ctxOut.Add([ordered]@{ source = $r.Source; s = $r.Session; instance = $r.Instance; metric = $r.Metric; avg = $r.Sum / $r.N; max = $r.Max; n = $r.N })
}

#endregion

#region ---------- write report -----------------------------------------------------------

$cpuSt = Get-CleanStats $sysCpu; $usedSt = Get-CleanStats $sysUsedGB; $commitSt = Get-CleanStats $sysCommitGB
$sessSt = Get-CleanStats $sysSess; $procSt = Get-CleanStats $sysProcs; $queueSt = Get-CleanStats $sysQueue
$iops = New-Object double[] $nS
for ($i = 0; $i -lt $nS; $i++) { $iops[$i] = $sysIopsR[$i] + $sysIopsW[$i] }
$iopsSt = Get-CleanStats $iops
$limitSt = Get-CleanStats $sysCommitLimit

$data = [ordered]@{
    meta     = [ordered]@{
        computer = [string]$meta.Computer; os = [string]$meta.OS; cores = $cores; ramGB = $ramMB / 1024.0
        intervalSec = [double]$meta.IntervalSeconds; simulated = [bool]$meta.Simulated
        start = [long]$sysRows[0].Ms; end = [long]$sysRows[$nS - 1].Ms; offsetMin = $offsetMin
        samples = $nS; bucketSec = $per * [double]$meta.IntervalSeconds; durationMin = $totalSec / 60.0
        processRows = $rowCount; processCount = $allK.Count; procsListed = $selected.Count
        totalCpuSec = $totalCpuMs / 1000.0; hasRtt = $hasRtt
        generated = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
    }
    stats    = [ordered]@{
        cpuAvg = $cpuSt.Avg; cpuP95 = $cpuSt.P95; cpuMax = $cpuSt.Max
        usedAvg = $usedSt.Avg; usedMax = $usedSt.Max; commitMax = $commitSt.Max; commitLimit = $limitSt.Max
        sessAvg = $sessSt.Avg; sessMax = $sessSt.Max; procAvg = $procSt.Avg; procMax = $procSt.Max
        queueAvg = $queueSt.Avg; queueMax = $queueSt.Max; iopsAvg = $iopsSt.Avg; iopsP95 = $iopsSt.P95
    }
    t        = $tSeries
    system   = [ordered]@{
        cpu = (Get-BucketSeries $sysCpu 1); cpuMax = (Get-BucketSeries $sysCpu 1 -UseMax)
        usedGB = (Get-BucketSeries $sysUsedGB 2); commitGB = (Get-BucketSeries $sysCommitGB 2)
        diskR = (Get-BucketSeries $sysDiskR 2); diskW = (Get-BucketSeries $sysDiskW 2)
        iopsR = (Get-BucketSeries $sysIopsR 0); iopsW = (Get-BucketSeries $sysIopsW 0)
        netR = (Get-BucketSeries $sysNetR 2); netS = (Get-BucketSeries $sysNetS 2)
        sessions = (Get-BucketSeries $sysSess 1); active = (Get-BucketSeries $sysActive 1)
        queue = (Get-BucketSeries $sysQueue 1)
    }
    sessions = $sessOut
    apps     = $appOut
    pairs    = $pairOut
    procs    = $procOut
    citrix   = $ctxOut
}

Write-Host 'Schreibe Bericht ...'
$json = New-Object System.Text.StringBuilder
ConvertTo-JsonText $data $json
$template = [IO.File]::ReadAllText($templateFile, [Text.Encoding]::UTF8)
$marker = '/*__WORKERPERF_DATA__*/null'
if ($template.IndexOf($marker) -lt 0) { throw 'Die Berichtsvorlage enthaelt keinen Datenplatzhalter.' }
$html = $template.Replace($marker, $json.ToString())
$OutFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
[IO.File]::WriteAllText($OutFile, $html, (New-Object System.Text.UTF8Encoding $false))

$timer.Stop()
Write-Host ("Bericht erstellt in {0:n1} s: {1}" -f $timer.Elapsed.TotalSeconds, $OutFile)
Write-Host ("  {0:n0} Messungen, {1:n0} Prozesszeilen, {2} Sitzungen, {3} Anwendungen" -f $nS, $rowCount, $sessOut.Count, $appOut.Count)
Get-Item -LiteralPath $OutFile

#endregion
