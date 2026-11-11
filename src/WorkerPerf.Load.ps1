#Requires -Version 5.1
# WorkerPerf analysis library: reads a capture folder into an in-memory model and derives measurement series.
# Defines functions only. Callers dot-source WorkerPerf.Common.ps1 as well.
# The model is a hashtable; its lists are arrays. Get-WorkerPerfSeries emits plain pipeline output: wrap calls in @(...).

function Read-WorkerPerfCsvFile {
    # Reads one capture file. Returns @{ Col = column name -> index; Rows = List[string[]] }.
    # A missing file counts as an empty one; rows with fewer fields than the format has columns are skipped.
    param([string]$Path, [string]$FileName)
    $col = @{}
    $canon = $script:WorkerPerfHeaders[$FileName].Split(',')
    for ($i = 0; $i -lt $canon.Length; $i++) { $col[$canon[$i]] = $i }
    $rows = New-Object System.Collections.Generic.List[string[]]
    $full = Join-Path $Path $FileName
    if (-not (Test-Path -LiteralPath $full)) { return @{ Col = $col; Rows = $rows } }
    $need = $canon.Length
    $stream = [IO.File]::Open($full, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $reader = New-Object System.IO.StreamReader($stream, [Text.Encoding]::UTF8)
    try {
        $header = $reader.ReadLine()
        if ($null -ne $header -and $header.Length -gt 0) {
            $names = $header.Split(',')
            for ($i = 0; $i -lt $names.Length; $i++) { $col[$names[$i].Trim()] = $i }
        }
        while ($null -ne ($line = $reader.ReadLine())) {
            if ($line.Length -eq 0) { continue }
            if ($line.IndexOf('"') -lt 0) { $f = $line.Split(',') } else { $f = [string[]]@(Split-WorkerPerfCsvLine $line) }
            if ($f.Length -ge $need) { $rows.Add($f) }
        }
    }
    finally { $reader.Dispose() }
    return @{ Col = $col; Rows = $rows }
}

function ConvertTo-WorkerPerfTimestamp([string]$Text) {
    # DateTimeOffset or $null.
    $dto = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse($Text, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$dto)) { return $dto }
    return $null
}

function ConvertTo-WorkerPerfDouble([string]$Text) {
    # Invariant number or NaN.
    $v = [double]::NaN
    if ($Text.Length -gt 0 -and -not [double]::TryParse($Text, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { $v = [double]::NaN }
    return $v
}

function New-WorkerPerfNanArray([int]$Length) {
    $a = New-Object double[] $Length
    for ($i = 0; $i -lt $Length; $i++) { $a[$i] = [double]::NaN }
    return , $a
}

function Get-WorkerPerfMaxIgnoringNaN([double]$A, [double]$B) {
    if ([double]::IsNaN($A)) { return $B }
    if ([double]::IsNaN($B)) { return $A }
    if ($B -gt $A) { return $B }
    return $A
}

function Set-WorkerPerfUniqueLabels($Items) {
    # Labels must be unique per signal: a repeated label gets " [2]", " [3]", ...
    $seen = @{}
    foreach ($it in $Items) {
        $base = [string]$it['Label']
        if (-not $seen.ContainsKey($base)) { $seen[$base] = 1; continue }
        $n = [int]$seen[$base] + 1
        while ($seen.ContainsKey("$base [$n]")) { $n++ }
        $seen[$base] = $n
        $it['Label'] = "$base [$n]"
        $seen[$it['Label']] = 1
    }
}

function Import-WorkerPerfRun {
    param([string]$Path, [datetime]$From = [datetime]::MinValue, [datetime]$To = [datetime]::MaxValue, $Thresholds, [object[]]$Roles)
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $numStyle = [Globalization.NumberStyles]::Float
    $nan = [double]::NaN

    $metaPath = Join-Path $Path 'meta.json'
    if (-not (Test-Path -LiteralPath $metaPath)) { throw "Ordner '$Path' enthaelt keine Aufzeichnung (meta.json fehlt)." }
    $metaJson = ConvertFrom-WorkerPerfJsonFile $metaPath
    $meta = @{}
    foreach ($p in $metaJson.PSObject.Properties) { $meta[$p.Name] = $p.Value }
    foreach ($k in 'SchemaVersion', 'Computer', 'OS', 'LogicalProcessors', 'PhysicalMemoryMB', 'FastIntervalSeconds', 'IntervalSeconds', 'StartTime', 'EndTime', 'EndReason', 'CollectorPid', 'Simulated', 'Endpoints') {
        if (-not $meta.ContainsKey($k)) { $meta[$k] = $null }
    }
    $cores = 0; $ramMb = 0.0; $fastSec = 2.0; $snapSec = 15.0
    if ($null -ne $meta['LogicalProcessors']) { $cores = [int]$meta['LogicalProcessors'] }
    if ($null -ne $meta['PhysicalMemoryMB']) { $ramMb = [double]$meta['PhysicalMemoryMB'] }
    if ($null -ne $meta['FastIntervalSeconds']) { $fastSec = [double]$meta['FastIntervalSeconds'] }
    if ($null -ne $meta['IntervalSeconds']) { $snapSec = [double]$meta['IntervalSeconds'] }

    $sources = @{}
    $srcObj = Get-WorkerPerfField $metaJson 'Sources'
    if ($null -ne $srcObj) {
        foreach ($p in $srcObj.PSObject.Properties) {
            $avail = Get-WorkerPerfField $p.Value 'Available'
            $detail = Get-WorkerPerfField $p.Value 'Detail'
            $d = ''
            if ($null -ne $detail) { $d = [string]$detail }
            $sources[$p.Name] = @{ Available = ($null -ne $avail -and [bool]$avail); Detail = $d }
        }
    }

    # time range (local times of this machine) as epoch milliseconds
    $fromMs = [long]::MinValue; $toMs = [long]::MaxValue
    if ($From -gt [datetime]::MinValue) { $fromMs = [DateTimeOffset]::new($From).ToUnixTimeMilliseconds() }
    if ($To -lt [datetime]::MaxValue) { $toMs = [DateTimeOffset]::new($To).ToUnixTimeMilliseconds() }

    #region ticks
    $csv = Read-WorkerPerfCsvFile $Path 'ticks.csv'
    $col = $csv.Col
    $numNames = New-Object System.Collections.Generic.List[string]
    foreach ($name in $script:WorkerPerfHeaders['ticks.csv'].Split(',')) { if ($name -ne 'T' -and $name -ne 'Timestamp') { $numNames.Add($name) } }
    $numIdx = New-Object int[] $numNames.Count
    $numLists = New-Object object[] $numNames.Count
    for ($i = 0; $i -lt $numNames.Count; $i++) { $numIdx[$i] = [int]$col[$numNames[$i]]; $numLists[$i] = New-Object System.Collections.Generic.List[double] }
    $tickT = New-Object System.Collections.Generic.List[int]
    $tickMs = New-Object System.Collections.Generic.List[long]
    $cT = [int]$col['T']; $cTs = [int]$col['Timestamp']
    $offsetMinutes = 0.0; $haveOffset = $false
    foreach ($f in $csv.Rows) {
        $t = 0
        if (-not [int]::TryParse($f[$cT], [ref]$t)) { continue }
        $dto = ConvertTo-WorkerPerfTimestamp $f[$cTs]
        if ($null -eq $dto) { continue }
        $ms = $dto.ToUnixTimeMilliseconds()
        if ($ms -lt $fromMs -or $ms -gt $toMs) { continue }
        if (-not $haveOffset) { $offsetMinutes = $dto.Offset.TotalMinutes; $haveOffset = $true }
        $tickT.Add($t); $tickMs.Add($ms)
        for ($i = 0; $i -lt $numIdx.Length; $i++) {
            $v = $nan
            $txt = $f[$numIdx[$i]]
            if ($txt.Length -gt 0 -and -not [double]::TryParse($txt, $numStyle, $inv, [ref]$v)) { $v = $nan }
            $numLists[$i].Add($v)
        }
    }
    $nT = $tickT.Count
    if ($nT -eq 0) { throw "Die Aufzeichnung enthaelt im gewaehlten Zeitraum keine Messung (ticks.csv ohne lesbare Takte)." }
    $raw = @{}
    for ($i = 0; $i -lt $numNames.Count; $i++) { $raw[$numNames[$i]] = $numLists[$i].ToArray() }
    $tickTArr = $tickT.ToArray()
    $tickMsArr = $tickMs.ToArray()
    $burst = New-Object bool[] $nT
    for ($i = 0; $i -lt $nT; $i++) { $burst[$i] = ($raw['Burst'][$i] -gt 0) }
    $tickPosByT = @{}
    for ($i = 0; $i -lt $nT; $i++) { $tickPosByT[$tickTArr[$i]] = $i }

    $signalIds = 'cpu.host', 'cpu.queue', 'cpu.steal', 'mem.used', 'mem.commit', 'mem.pagesin'
    $signal = @{}
    foreach ($id in $signalIds) { $signal[$id] = New-Object double[] $nT }
    for ($i = 0; $i -lt $nT; $i++) {
        $row = @{
            CpuPct = $raw['CpuPct'][$i]; ProcQueue = $raw['ProcQueue'][$i]; StealPct = $raw['StealPct'][$i]
            MemAvailMB = $raw['MemAvailMB'][$i]; MemCommittedMB = $raw['MemCommittedMB'][$i]
            MemCommitLimitMB = $raw['MemCommitLimitMB'][$i]; PagesInPerSec = $raw['PagesInPerSec'][$i]
        }
        $sig = Get-WorkerPerfHostSignals -Tick $row -LogicalProcessors $cores -PhysicalMemoryMB $ramMb
        foreach ($id in $signalIds) { $signal[$id][$i] = [double]$sig[$id] }
    }
    #endregion

    #region snapshots
    $csv = Read-WorkerPerfCsvFile $Path 'snapshots.csv'
    $col = $csv.Col
    $snapPos = @{}                     # P -> snapshot position
    $snapP = New-Object System.Collections.Generic.List[int]
    $snapTL = New-Object System.Collections.Generic.List[int]
    $snapMsL = New-Object System.Collections.Generic.List[long]
    $snapKind = New-Object System.Collections.Generic.List[string]
    $snapNum = @{}
    foreach ($name in 'ElapsedSec', 'Sessions', 'ActiveSessions', 'Processes', 'RowsWritten', 'CollectMs') { $snapNum[$name] = New-Object System.Collections.Generic.List[double] }
    foreach ($f in $csv.Rows) {
        $p = 0; $t = 0
        if (-not [int]::TryParse($f[[int]$col['P']], [ref]$p)) { continue }
        if (-not [int]::TryParse($f[[int]$col['T']], [ref]$t)) { continue }
        $dto = ConvertTo-WorkerPerfTimestamp $f[[int]$col['Timestamp']]
        if ($null -eq $dto) { continue }
        $ms = $dto.ToUnixTimeMilliseconds()
        if ($ms -lt $fromMs -or $ms -gt $toMs) { continue }
        $snapPos[$p] = $snapP.Count
        $snapP.Add($p); $snapTL.Add($t); $snapMsL.Add($ms); $snapKind.Add($f[[int]$col['Kind']])
        foreach ($name in $snapNum.Keys) { $snapNum[$name].Add((ConvertTo-WorkerPerfDouble $f[[int]$col[$name]])) }
    }
    $nP = $snapP.Count
    if ($nP -eq 0) { throw "Die Aufzeichnung enthaelt im gewaehlten Zeitraum keinen Schnappschuss (snapshots.csv ohne lesbare Zeilen)." }
    $snapT = $snapTL.ToArray()
    $snapMs = $snapMsL.ToArray()
    $snapTickPos = New-Object int[] $nP
    for ($i = 0; $i -lt $nP; $i++) {
        $pos = -1
        if ($tickPosByT.ContainsKey($snapT[$i])) { $pos = [int]$tickPosByT[$snapT[$i]] }
        else {
            $ix = [Array]::BinarySearch($tickTArr, [int]$snapT[$i])
            if ($ix -lt 0) { $ix = -bnot $ix }
            if ($ix -ge $nT) { $ix = $nT - 1 }
            $pos = $ix
        }
        $snapTickPos[$i] = $pos
    }
    # first snapshot at or after each tick
    $firstSnapAt = New-Object int[] $nT
    $j = 0
    for ($tp = 0; $tp -lt $nT; $tp++) {
        while ($j -lt $nP -and $snapTickPos[$j] -lt $tp) { $j++ }
        $firstSnapAt[$tp] = $j
    }
    #endregion

    #region sessions
    $sessions = New-Object System.Collections.Generic.List[object]
    $sessBySnap = New-Object object[] $nP        # snapshot position -> (session id -> session)
    $curBySid = @{}
    $orphans = @{}
    $newSession = {
        param([int]$Sid)
        $e = @{
            Index = $sessions.Count; Sid = $Sid; User = ''; Domain = ''; Client = ''; Logon = $null; Label = ''
            FirstP = -1; LastP = -1; SeenN = 0; ActiveN = 0; IdleMaxSec = [double]::NaN
            Input = (New-Object double[] $nT); Rtt = (New-WorkerPerfNanArray $nP); Latency = (New-WorkerPerfNanArray $nP)
            ProfileVolume = -1
        }
        $sessions.Add($e)
        return $e
    }
    $csv = Read-WorkerPerfCsvFile $Path 'sessions.csv'
    $col = $csv.Col
    $cP = [int]$col['P']; $cSid = [int]$col['SessionId']; $cUser = [int]$col['User']; $cDom = [int]$col['Domain']
    $cState = [int]$col['State']; $cClient = [int]$col['ClientName']; $cLogon = [int]$col['LogonTime']; $cIdle = [int]$col['IdleSec']
    foreach ($f in $csv.Rows) {
        $p = 0; $sid = 0
        if (-not [int]::TryParse($f[$cP], [ref]$p) -or -not [int]::TryParse($f[$cSid], [ref]$sid)) { continue }
        if (-not $snapPos.ContainsKey($p)) { continue }
        $pos = [int]$snapPos[$p]
        $user = $f[$cUser]
        $e = $null
        if ($curBySid.ContainsKey($sid)) { $e = $curBySid[$sid] }
        # A session id is reused after logoff: a new session starts when the id was missing for a snapshot
        # or when a different user owns it now. Session 0 (services) is always one session.
        if ($null -ne $e -and $sid -ne 0) {
            if ($e.LastP -lt $pos - 1) { $e = $null }
            elseif ($user.Length -gt 0 -and $e.User.Length -gt 0 -and ($user -ne $e.User -or $f[$cDom] -ne $e.Domain)) { $e = $null }
        }
        if ($null -eq $e) { $e = & $newSession $sid; $curBySid[$sid] = $e }
        if ($user.Length -gt 0) { $e.User = $user; $e.Domain = $f[$cDom] }
        if ($f[$cClient].Length -gt 0) { $e.Client = $f[$cClient] }
        if ($f[$cLogon].Length -gt 0 -and $null -eq $e.Logon) {
            $ld = ConvertTo-WorkerPerfTimestamp $f[$cLogon]
            if ($null -ne $ld) { $e.Logon = $ld.ToUnixTimeMilliseconds() }
        }
        if ($e.FirstP -lt 0) { $e.FirstP = $pos }
        $e.LastP = $pos; $e.SeenN++
        if ($f[$cState] -eq 'Active') { $e.ActiveN++ }
        $idle = ConvertTo-WorkerPerfDouble $f[$cIdle]
        if (-not [double]::IsNaN($idle) -and $idle -ge 0 -and -not ($e.IdleMaxSec -ge $idle)) { $e.IdleMaxSec = $idle }
        if ($null -eq $sessBySnap[$pos]) { $sessBySnap[$pos] = @{} }
        $sessBySnap[$pos][$sid] = $e
    }
    # Session of a row stamped with tick position $tp: first snapshot at or after the tick, else the one before,
    # else a stand-in session for the id.
    $resolveSession = {
        param([int]$TickPos, [int]$Sid)
        $s = $firstSnapAt[$TickPos]
        if ($s -lt $nP) {
            $h = $sessBySnap[$s]
            if ($null -ne $h -and $h.ContainsKey($Sid)) { return $h[$Sid] }
        }
        if ($s - 1 -ge 0) {
            $h = $sessBySnap[$s - 1]
            if ($null -ne $h -and $h.ContainsKey($Sid)) { return $h[$Sid] }
        }
        if (-not $orphans.ContainsKey($Sid)) { $orphans[$Sid] = & $newSession $Sid }
        return $orphans[$Sid]
    }
    #endregion

    #region input delay
    $csv = Read-WorkerPerfCsvFile $Path 'inputdelay.csv'
    $col = $csv.Col
    $cT = [int]$col['T']; $cSid = [int]$col['SessionId']; $cDelay = [int]$col['DelayMs']
    foreach ($f in $csv.Rows) {
        $t = 0; $sid = 0
        if (-not [int]::TryParse($f[$cT], [ref]$t) -or -not [int]::TryParse($f[$cSid], [ref]$sid)) { continue }
        if (-not $tickPosByT.ContainsKey($t)) { continue }
        $d = ConvertTo-WorkerPerfDouble $f[$cDelay]
        if ([double]::IsNaN($d)) { continue }
        $tp = [int]$tickPosByT[$t]
        $e = & $resolveSession $tp $sid
        if ($d -gt $e.Input[$tp]) { $e.Input[$tp] = $d }
    }

    $mainPatterns = New-Object System.Collections.Generic.List[string]
    $mainLabels = New-Object System.Collections.Generic.List[string]
    foreach ($r in @($Roles)) {
        if ($null -eq $r -or [string](Get-WorkerPerfField $r 'role') -ne 'Hauptanwendung') { continue }
        $pats = @(Get-WorkerPerfField $r 'processes' | Where-Object { $null -ne $_ -and [string]$_ -ne '' })
        if ($pats.Count -eq 0) { continue }
        foreach ($pt in $pats) { $mainPatterns.Add([string]$pt) }
        $mainLabels.Add([string](Get-WorkerPerfField $r 'label'))
    }
    $mainApp = $null
    $mainDelay = $null
    if ($mainPatterns.Count -gt 0) { $mainDelay = New-Object double[] $nT }
    $mainByName = @{}

    $csv = Read-WorkerPerfCsvFile $Path 'inputdelay_proc.csv'
    $col = $csv.Col
    $cT = [int]$col['T']; $cSid = [int]$col['SessionId']; $cPid = [int]$col['Pid']; $cName = [int]$col['Name']; $cDelay = [int]$col['DelayMs']
    $ipTick = New-Object System.Collections.Generic.List[int]
    $ipSess = New-Object System.Collections.Generic.List[int]
    $ipPid = New-Object System.Collections.Generic.List[int]
    $ipName = New-Object System.Collections.Generic.List[string]
    $ipDelay = New-Object System.Collections.Generic.List[double]
    foreach ($f in $csv.Rows) {
        $t = 0; $sid = 0; $procId = 0
        if (-not [int]::TryParse($f[$cT], [ref]$t) -or -not [int]::TryParse($f[$cSid], [ref]$sid)) { continue }
        if (-not $tickPosByT.ContainsKey($t)) { continue }
        $d = ConvertTo-WorkerPerfDouble $f[$cDelay]
        if ([double]::IsNaN($d)) { continue }
        if (-not [int]::TryParse($f[$cPid], [ref]$procId)) { $procId = -1 }
        $tp = [int]$tickPosByT[$t]
        $e = & $resolveSession $tp $sid
        $name = $f[$cName]
        $ipTick.Add($tp); $ipSess.Add([int]$e.Index); $ipPid.Add($procId); $ipName.Add($name); $ipDelay.Add($d)
        if ($null -ne $mainDelay) {
            if (-not $mainByName.ContainsKey($name)) {
                $hit = $false
                foreach ($pt in $mainPatterns) { if ($name -like $pt) { $hit = $true; break } }
                $mainByName[$name] = $hit
            }
            if ($mainByName[$name] -and $d -gt $mainDelay[$tp]) { $mainDelay[$tp] = $d }
        }
    }
    if ($null -ne $mainDelay) { $mainApp = @{ Label = ($mainLabels.ToArray() -join ' / '); Delay = $mainDelay } }
    #endregion

    #region volumes and shares
    $volumes = New-Object System.Collections.Generic.List[object]
    $volByKey = @{}
    $csv = Read-WorkerPerfCsvFile $Path 'volumes.csv'
    $col = $csv.Col
    $cT = [int]$col['T']; $cVol = [int]$col['Volume']; $cKind = [int]$col['Kind']; $cSid = [int]$col['SessionId']; $cBack = [int]$col['Backing']
    $cRl = [int]$col['ReadLatMs']; $cWl = [int]$col['WriteLatMs']; $cRo = [int]$col['ReadOps']; $cWo = [int]$col['WriteOps']
    foreach ($f in $csv.Rows) {
        $t = 0
        if (-not [int]::TryParse($f[$cT], [ref]$t)) { continue }
        if (-not $tickPosByT.ContainsKey($t)) { continue }
        $tp = [int]$tickPosByT[$t]
        $sessIdx = -1
        $sid = 0
        if ($f[$cSid].Length -gt 0 -and [int]::TryParse($f[$cSid], [ref]$sid)) { $sessIdx = [int]((& $resolveSession $tp $sid).Index) }
        $key = $f[$cVol] + '|' + $f[$cKind] + '|' + $sessIdx
        $v = $volByKey[$key]
        if ($null -eq $v) {
            $v = @{
                Name = $f[$cVol]; Kind = $f[$cKind]; SessionIndex = $sessIdx; Backing = ''; Label = ''
                ReadMs = (New-WorkerPerfNanArray $nT); WriteMs = (New-WorkerPerfNanArray $nT); Latency = (New-WorkerPerfNanArray $nT)
                Ops = (New-Object double[] $nT)
            }
            $volByKey[$key] = $v; $volumes.Add($v)
        }
        if ($v.Backing.Length -eq 0 -and $f[$cBack].Length -gt 0) { $v.Backing = $f[$cBack] }
        $rl = $nan; $wl = $nan; $ro = 0.0; $wo = 0.0
        $txt = $f[$cRl]; if ($txt.Length -gt 0 -and -not [double]::TryParse($txt, $numStyle, $inv, [ref]$rl)) { $rl = $nan }
        $txt = $f[$cWl]; if ($txt.Length -gt 0 -and -not [double]::TryParse($txt, $numStyle, $inv, [ref]$wl)) { $wl = $nan }
        $txt = $f[$cRo]; if ($txt.Length -gt 0 -and -not [double]::TryParse($txt, $numStyle, $inv, [ref]$ro)) { $ro = 0.0 }
        $txt = $f[$cWo]; if ($txt.Length -gt 0 -and -not [double]::TryParse($txt, $numStyle, $inv, [ref]$wo)) { $wo = 0.0 }
        if ([double]::IsNaN($ro)) { $ro = 0.0 }
        if ([double]::IsNaN($wo)) { $wo = 0.0 }
        $v.ReadMs[$tp] = $rl; $v.WriteMs[$tp] = $wl
        $v.Latency[$tp] = Get-WorkerPerfMaxIgnoringNaN $rl $wl
        $v.Ops[$tp] = $ro + $wo
    }

    $shares = New-Object System.Collections.Generic.List[object]
    $shareByName = @{}
    $csv = Read-WorkerPerfCsvFile $Path 'shares.csv'
    $col = $csv.Col
    $cT = [int]$col['T']; $cSh = [int]$col['Share']
    $cRl = [int]$col['ReadLatMs']; $cWl = [int]$col['WriteLatMs']; $cRo = [int]$col['ReadOps']; $cWo = [int]$col['WriteOps']
    foreach ($f in $csv.Rows) {
        $t = 0
        if (-not [int]::TryParse($f[$cT], [ref]$t)) { continue }
        if (-not $tickPosByT.ContainsKey($t)) { continue }
        $tp = [int]$tickPosByT[$t]
        $s = $shareByName[$f[$cSh]]
        if ($null -eq $s) {
            $s = @{
                Name = $f[$cSh]; Label = ''
                ReadMs = (New-WorkerPerfNanArray $nT); WriteMs = (New-WorkerPerfNanArray $nT); Latency = (New-WorkerPerfNanArray $nT)
                Ops = (New-Object double[] $nT)
            }
            $shareByName[$f[$cSh]] = $s; $shares.Add($s)
        }
        $rl = $nan; $wl = $nan; $ro = 0.0; $wo = 0.0
        $txt = $f[$cRl]; if ($txt.Length -gt 0 -and -not [double]::TryParse($txt, $numStyle, $inv, [ref]$rl)) { $rl = $nan }
        $txt = $f[$cWl]; if ($txt.Length -gt 0 -and -not [double]::TryParse($txt, $numStyle, $inv, [ref]$wl)) { $wl = $nan }
        $txt = $f[$cRo]; if ($txt.Length -gt 0 -and -not [double]::TryParse($txt, $numStyle, $inv, [ref]$ro)) { $ro = 0.0 }
        $txt = $f[$cWo]; if ($txt.Length -gt 0 -and -not [double]::TryParse($txt, $numStyle, $inv, [ref]$wo)) { $wo = 0.0 }
        if ([double]::IsNaN($ro)) { $ro = 0.0 }
        if ([double]::IsNaN($wo)) { $wo = 0.0 }
        $s.ReadMs[$tp] = $rl; $s.WriteMs[$tp] = $wl
        $s.Latency[$tp] = Get-WorkerPerfMaxIgnoringNaN $rl $wl
        $s.Ops[$tp] = $ro + $wo
    }
    #endregion

    #region probes, citrix, events
    $probes = New-Object System.Collections.Generic.List[object]
    $probeByName = @{}
    $csv = Read-WorkerPerfCsvFile $Path 'probes.csv'
    $col = $csv.Col
    $cT = [int]$col['T']; $cName = [int]$col['Name']; $cRole = [int]$col['Role']; $cHost = [int]$col['Host']; $cPort = [int]$col['Port']
    $cMs = [int]$col['ConnectMs']; $cErr = [int]$col['Error']
    foreach ($f in $csv.Rows) {
        $t = 0
        if (-not [int]::TryParse($f[$cT], [ref]$t)) { continue }
        if ($t -lt $tickTArr[0] -or $t -gt $tickTArr[$nT - 1]) { continue }     # outside the selected range
        $sp = [Array]::BinarySearch($snapT, [int]$t)
        if ($sp -lt 0) { $sp = -bnot $sp }
        if ($sp -ge $nP) { continue }
        $pr = $probeByName[$f[$cName]]
        if ($null -eq $pr) {
            $port = 0
            if (-not [int]::TryParse($f[$cPort], [ref]$port)) { $port = 0 }
            $pr = @{ Name = $f[$cName]; Role = $f[$cRole]; Host = $f[$cHost]; Port = $port; Ms = (New-WorkerPerfNanArray $nP); Error = (New-Object string[] $nP) }
            for ($i = 0; $i -lt $nP; $i++) { $pr.Error[$i] = '' }
            $probeByName[$f[$cName]] = $pr; $probes.Add($pr)
        }
        $ms = ConvertTo-WorkerPerfDouble $f[$cMs]
        if ([double]::IsNaN($ms)) {
            if ($f[$cErr].Length -eq 0) { continue }
            $ms = [double]::PositiveInfinity
            $pr.Error[$sp] = $f[$cErr]
        }
        if ([double]::IsNaN($pr.Ms[$sp]) -or $ms -gt $pr.Ms[$sp]) { $pr.Ms[$sp] = $ms }
    }

    $citrixAgg = @{}
    $citrixOrder = New-Object System.Collections.Generic.List[string]
    $ctxTmp = @{}      # session index -> RoundtripTime and the three latency metrics per snapshot
    $latencyMetrics = 'NetworkLatency', 'Latency - Last Recorded', 'LatencyLastRecorded'
    $csv = Read-WorkerPerfCsvFile $Path 'citrix.csv'
    $col = $csv.Col
    $cT = [int]$col['T']; $cSrc = [int]$col['Source']; $cSid = [int]$col['SessionId']; $cInst = [int]$col['Instance']
    $cMetric = [int]$col['Metric']; $cVal = [int]$col['Value']
    foreach ($f in $csv.Rows) {
        $t = 0
        if (-not [int]::TryParse($f[$cT], [ref]$t)) { continue }
        $val = ConvertTo-WorkerPerfDouble $f[$cVal]
        if ([double]::IsNaN($val)) { continue }
        if ($t -lt $tickTArr[0] -or $t -gt $tickTArr[$nT - 1]) { continue }     # outside the selected range
        $sp = [Array]::BinarySearch($snapT, [int]$t)
        if ($sp -lt 0) { $sp = -bnot $sp }
        if ($sp -ge $nP) { continue }
        $sessIdx = -1
        $sid = 0
        if ($f[$cSid].Length -gt 0 -and [int]::TryParse($f[$cSid], [ref]$sid)) {
            $h = $sessBySnap[$sp]
            if ($null -eq $h -or -not $h.ContainsKey($sid)) { continue }
            $sessIdx = [int]$h[$sid].Index
        }
        $metric = $f[$cMetric]
        $key = $f[$cSrc] + '|' + $sessIdx + '|' + $f[$cInst] + '|' + $metric
        $a = $citrixAgg[$key]
        if ($null -eq $a) {
            $a = @{ Source = $f[$cSrc]; SessionIndex = $sessIdx; Instance = $f[$cInst]; Metric = $metric; Sum = 0.0; Max = $nan; N = 0 }
            $citrixAgg[$key] = $a; $citrixOrder.Add($key)
        }
        $a.Sum += $val; $a.N++
        if ([double]::IsNaN($a.Max) -or $val -gt $a.Max) { $a.Max = $val }
        if ($sessIdx -ge 0) {
            $slot = -1
            if ($metric -eq 'RoundtripTime') { $slot = 0 }
            else { $li = [array]::IndexOf($latencyMetrics, $metric); if ($li -ge 0) { $slot = $li + 1 } }
            if ($slot -ge 0) {
                if (-not $ctxTmp.ContainsKey($sessIdx)) { $ctxTmp[$sessIdx] = @((New-WorkerPerfNanArray $nP), (New-WorkerPerfNanArray $nP), (New-WorkerPerfNanArray $nP), (New-WorkerPerfNanArray $nP)) }
                $arr = $ctxTmp[$sessIdx][$slot]
                if ([double]::IsNaN($arr[$sp])) { $arr[$sp] = $val }
            }
        }
    }
    $citrix = New-Object System.Collections.Generic.List[object]
    foreach ($key in $citrixOrder) {
        $a = $citrixAgg[$key]
        $citrix.Add(@{ Source = $a.Source; SessionIndex = $a.SessionIndex; Instance = $a.Instance; Metric = $a.Metric; Avg = ($a.Sum / $a.N); Max = $a.Max; N = $a.N })
    }
    foreach ($si in $ctxTmp.Keys) {
        $s = $sessions[[int]$si]
        $tmp = $ctxTmp[$si]
        for ($p = 0; $p -lt $nP; $p++) {
            $s.Rtt[$p] = $tmp[0][$p]
            $lat = $nan
            for ($m = 1; $m -le 3; $m++) { if ([double]::IsNaN($lat)) { $lat = $tmp[$m][$p] } }
            $s.Latency[$p] = $lat
        }
    }

    $allEvents = New-Object System.Collections.Generic.List[object]
    $csv = Read-WorkerPerfCsvFile $Path 'events.csv'
    $col = $csv.Col
    $cTs = [int]$col['Timestamp']; $cSrc = [int]$col['Source']; $cId = [int]$col['EventId']; $cKind = [int]$col['Kind']; $cText = [int]$col['Text']
    foreach ($f in $csv.Rows) {
        $dto = ConvertTo-WorkerPerfTimestamp $f[$cTs]
        if ($null -eq $dto) { continue }
        $id = 0
        if (-not [int]::TryParse($f[$cId], [ref]$id)) { $id = 0 }
        $allEvents.Add(@{ TimeMs = $dto.ToUnixTimeMilliseconds(); Source = $f[$cSrc]; EventId = $id; Kind = $f[$cKind]; Text = $f[$cText] })
    }
    $sortedEvents = @($allEvents.ToArray() | Sort-Object -Property @{ Expression = { $_.TimeMs } })
    $events = New-Object System.Collections.Generic.List[object]
    foreach ($e in $sortedEvents) { if ($e.TimeMs -ge $fromMs -and $e.TimeMs -le $toMs) { $events.Add($e) } }
    # scans: paired scan-start / scan-end over the whole file; an open scan lasts until the end of the measurement
    $scans = New-Object System.Collections.Generic.List[object]
    $openStart = $null
    $measureEnd = [long]$tickMsArr[$nT - 1]
    foreach ($e in $sortedEvents) {
        if ($e.Kind -eq 'scan-start') { if ($null -eq $openStart) { $openStart = [long]$e.TimeMs } }
        elseif ($e.Kind -eq 'scan-end' -and $null -ne $openStart) {
            $scans.Add(@{ StartMs = $openStart; EndMs = [long]$e.TimeMs }); $openStart = $null
        }
    }
    if ($null -ne $openStart) { $scans.Add(@{ StartMs = $openStart; EndMs = [Math]::Max($openStart, $measureEnd) }) }
    $scanList = New-Object System.Collections.Generic.List[object]
    foreach ($s in $scans) { if ($s.EndMs -ge $fromMs -and $s.StartMs -le $toMs) { $scanList.Add($s) } }
    #endregion

    #region labels and links
    foreach ($s in $sessions) {
        if ($s.User.Length -gt 0) { $s.Label = $s.User + ' (#' + $s.Sid + ')' }
        elseif ($s.Sid -eq 0) { $s.Label = 'Dienste/System' }
        else { $s.Label = 'Sitzung ' + $s.Sid }
    }
    Set-WorkerPerfUniqueLabels $sessions
    for ($i = 0; $i -lt $volumes.Count; $i++) {
        $v = $volumes[$i]
        if ($v.Kind -eq 'profile') {
            $user = ''
            if ($v.SessionIndex -ge 0) { $user = [string]$sessions[$v.SessionIndex].User }
            if ($user.Length -gt 0) { $v.Label = 'Profilcontainer von ' + $user + ' (' + $v.Backing + ')' }
            else { $v.Label = 'Profilcontainer (Benutzer unbekannt) ' + $v.Name }
            if ($v.SessionIndex -ge 0 -and $sessions[$v.SessionIndex].ProfileVolume -lt 0) { $sessions[$v.SessionIndex].ProfileVolume = $i }
        }
        else { $v.Label = 'Laufwerk ' + $v.Name }
    }
    Set-WorkerPerfUniqueLabels $volumes
    foreach ($s in $shares) { $s.Label = 'Freigabe ' + $s.Name }
    Set-WorkerPerfUniqueLabels $shares
    foreach ($pr in $probes) { $pr.Label = $pr.Name }
    #endregion

    $meta['Cores'] = $cores; $meta['RamMB'] = $ramMb; $meta['OffsetMinutes'] = $offsetMinutes
    $meta['FastSec'] = $fastSec; $meta['SnapSec'] = $snapSec
    $kinds = $snapKind.ToArray()
    return @{
        Meta = $meta
        Sources = $sources
        Tick = @{
            N = $nT; TimeMs = $tickMsArr; ElapsedSec = $raw['ElapsedSec']; Burst = $burst; CollectMs = $raw['CollectMs']
            Raw = $raw; Signal = $signal
        }
        Snap = @{
            N = $nP; TimeMs = $snapMs; ElapsedSec = $snapNum['ElapsedSec'].ToArray(); Kind = $kinds; TickPos = $snapTickPos
            Sessions = $snapNum['Sessions'].ToArray(); ActiveSessions = $snapNum['ActiveSessions'].ToArray()
            Processes = $snapNum['Processes'].ToArray(); RowsWritten = $snapNum['RowsWritten'].ToArray(); CollectMs = $snapNum['CollectMs'].ToArray()
        }
        Sessions = $sessions.ToArray()
        Volumes = $volumes.ToArray()
        Shares = $shares.ToArray()
        Probes = $probes.ToArray()
        Events = $events.ToArray()
        Scans = $scanList.ToArray()
        InputProc = @{ TickPos = $ipTick.ToArray(); SessionIndex = $ipSess.ToArray(); Pid = $ipPid.ToArray(); Name = $ipName.ToArray(); DelayMs = $ipDelay.ToArray() }
        MainApp = $mainApp
        Citrix = $citrix.ToArray()
    }
}

function Test-WorkerPerfSeriesRateable([double[]]$Value, $Ops, [double]$MinOps) {
    # $true when at least one point has a value (and enough operations when the threshold asks for them).
    for ($i = 0; $i -lt $Value.Length; $i++) {
        if ([double]::IsNaN($Value[$i])) { continue }
        if ($MinOps -gt 0 -and $null -ne $Ops -and $Ops[$i] -lt $MinOps) { continue }
        return $true
    }
    return $false
}

function Get-WorkerPerfSeries {
    param($Model, $Thresholds)
    $list = New-Object System.Collections.Generic.List[object]
    $tick = $Model.Tick
    $snap = $Model.Snap
    $labelOf = {
        param([string]$Id)
        if ($null -ne $Thresholds -and $Thresholds.Contains($Id)) { return [string]$Thresholds[$Id].label }
        return $Id
    }
    $minOpsOf = {
        param([string]$Id)
        if ($null -ne $Thresholds -and $Thresholds.Contains($Id)) { return [double]$Thresholds[$Id].minOps }
        return 0.0
    }
    $add = {
        param($Id, $Resource, $Scope, $Instance, $Label, $SessionIndex, $TimeMs, $ElapsedSec, $Value, $Ops)
        $list.Add(@{
            Id = $Id; Resource = $Resource; Scope = $Scope; Instance = $Instance; Label = $Label; SessionIndex = $SessionIndex
            TimeMs = $TimeMs; ElapsedSec = $ElapsedSec; Value = $Value; Ops = $Ops
        })
    }
    # keeps only the snapshot points with a value; ElapsedSec is the distance to the previous kept point
    $addSparse = {
        param($Id, $Resource, $Scope, $Instance, $Label, $SessionIndex, [double[]]$PerSnap)
        $times = New-Object System.Collections.Generic.List[long]
        $elapsed = New-Object System.Collections.Generic.List[double]
        $vals = New-Object System.Collections.Generic.List[double]
        for ($p = 0; $p -lt $snap.N; $p++) {
            if ([double]::IsNaN($PerSnap[$p])) { continue }
            if ($times.Count -eq 0) { $elapsed.Add([double]$snap.ElapsedSec[$p]) }
            else { $elapsed.Add(([long]$snap.TimeMs[$p] - $times[$times.Count - 1]) / 1000.0) }
            $times.Add([long]$snap.TimeMs[$p]); $vals.Add($PerSnap[$p])
        }
        if ($vals.Count -eq 0) { return }
        & $add $Id $Resource $Scope $Instance $Label $SessionIndex $times.ToArray() $elapsed.ToArray() $vals.ToArray() $null
    }

    $hostResource = @{ 'cpu.host' = 'cpu'; 'cpu.queue' = 'cpu'; 'cpu.steal' = 'cpu'; 'mem.used' = 'memory'; 'mem.commit' = 'memory'; 'mem.pagesin' = 'memory' }
    foreach ($id in 'cpu.host', 'cpu.queue', 'cpu.steal', 'mem.used', 'mem.commit', 'mem.pagesin') {
        $v = [double[]]$tick.Signal[$id]
        if (-not (Test-WorkerPerfSeriesRateable $v $null 0)) { continue }
        & $add $id $hostResource[$id] 'global' '' (& $labelOf $id) -1 $tick.TimeMs $tick.ElapsedSec $v $null
    }

    foreach ($s in $Model.Sessions) {
        $has = $false
        foreach ($x in $s.Input) { if ($x -gt 0) { $has = $true; break } }
        if ($has) { & $add 'input.session' 'input' 'session' $s.Label $s.Label $s.Index $tick.TimeMs $tick.ElapsedSec $s.Input $null }
    }

    $diskMin = & $minOpsOf 'disk.latency'
    foreach ($v in $Model.Volumes) {
        if (-not (Test-WorkerPerfSeriesRateable $v.Latency $v.Ops $diskMin)) { continue }
        $resource = 'disk'; $scope = 'global'
        if ($v.Kind -eq 'profile') { $resource = 'profile'; $scope = 'session' }
        & $add 'disk.latency' $resource $scope $v.Name $v.Label $v.SessionIndex $tick.TimeMs $tick.ElapsedSec $v.Latency $v.Ops
    }

    $smbMin = & $minOpsOf 'smb.latency'
    foreach ($sh in $Model.Shares) {
        if (-not (Test-WorkerPerfSeriesRateable $sh.Latency $sh.Ops $smbMin)) { continue }
        & $add 'smb.latency' 'share' 'global' $sh.Name $sh.Label -1 $tick.TimeMs $tick.ElapsedSec $sh.Latency $sh.Ops
    }

    foreach ($s in $Model.Sessions) {
        & $addSparse 'ica.rtt' 'network' 'session' $s.Label $s.Label $s.Index $s.Rtt
        & $addSparse 'ica.latency' 'network' 'session' $s.Label $s.Label $s.Index $s.Latency
    }
    foreach ($pr in $Model.Probes) {
        & $addSparse 'probe.connect' 'endpoint' 'global' $pr.Name $pr.Label -1 $pr.Ms
    }
    $list.ToArray()
}
