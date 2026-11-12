#Requires -Version 5.1
# WorkerPerf analysis library: reads the event and print files of a capture (definitions only).
# Requires WorkerPerf.Common.ps1 (headers) and WorkerPerf.Load.ps1 (Read-WorkerPerfCsvFile, ConvertTo-WorkerPerfTimestamp).
# Each file is read by its own header line (Read-WorkerPerfCsvFile -OwnHeader): a file of an older format has fewer
# columns. -Skipped receives the number of rows left out because they have fewer fields than that header.
# Read-WorkerPerfEventCsv, Read-WorkerPerfPrintDrivers and Read-WorkerPerfPrintQueues emit plain pipeline output: wrap calls in @(...).

$script:WorkerPerfEventNumberColumns = @('EventId', 'Level', 'Pid', 'SessionId')
# Format 2 wrote no group: these kinds were all of the security group.
$script:WorkerPerfSecurityKinds = @('scan-start', 'scan-end', 'signature-update', 'applocker-block')

function Read-WorkerPerfEventCsv([string]$Path, [string]$FileName, [ref]$Skipped) {
    # Events of events.csv or events_before.csv in format 2 or 3 as hashtables with TimeMs and every column of format 3:
    # a column the file lacks is '', the number columns are [int] (empty or unreadable = -1). Sorted by time, on equal
    # times by position in the file (a scan-start and scan-end in the same millisecond must keep their order to pair).
    $csv = Read-WorkerPerfCsvFile $Path $FileName -OwnHeader
    if ($null -ne $Skipped) { $Skipped.Value = [int]$csv.Skipped }
    $col = $csv.Col
    $names = $script:WorkerPerfHeaders['events.csv'].Split(',')
    $list = New-Object System.Collections.Generic.List[object]
    if (-not $col.ContainsKey('Timestamp')) { return }
    $cTs = [int]$col['Timestamp']
    foreach ($f in $csv.Rows) {
        $dto = ConvertTo-WorkerPerfTimestamp $f[$cTs]
        if ($null -eq $dto) { continue }
        $e = @{ TimeMs = $dto.ToUnixTimeMilliseconds() }
        foreach ($n in $names) {
            $text = ''
            if ($col.ContainsKey($n)) { $text = $f[[int]$col[$n]] }
            if ($script:WorkerPerfEventNumberColumns -contains $n) {
                $v = 0
                if (-not [int]::TryParse($text, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { $v = -1 }
                $e[$n] = $v
            }
            else { $e[$n] = $text }
        }
        if ($e['Group'] -eq '' -and $script:WorkerPerfSecurityKinds -contains $e['Kind']) { $e['Group'] = 'security' }
        $list.Add($e)
    }
    $arr = $list.ToArray()
    if ($arr.Length -eq 0) { return }
    $order = @(0..($arr.Length - 1) | Sort-Object -Property @{ Expression = { $arr[$_].TimeMs } }, @{ Expression = { $_ } })
    foreach ($ix in $order) { $arr[$ix] }
}

function Read-WorkerPerfPrintDrivers([string]$Path, [ref]$Skipped) {
    # printdrivers.csv: @{ Name; Manufacturer; Version; Type = [int] (0 = unknown); Isolation; Files = string[] }.
    # Files is split at ';' (the writer joins the file names with it; Windows driver file names carry none).
    $csv = Read-WorkerPerfCsvFile $Path 'printdrivers.csv' -OwnHeader
    if ($null -ne $Skipped) { $Skipped.Value = [int]$csv.Skipped }
    $col = $csv.Col
    foreach ($k in 'Name', 'Manufacturer', 'Version', 'Type', 'Isolation', 'Files') { if (-not $col.ContainsKey($k)) { return } }
    foreach ($f in $csv.Rows) {
        $type = 0
        if (-not [int]::TryParse($f[[int]$col['Type']], [ref]$type)) { $type = 0 }
        $files = [string[]]@($f[[int]$col['Files']].Split(';') | Where-Object { $_.Length -gt 0 })
        @{ Name = $f[[int]$col['Name']]; Manufacturer = $f[[int]$col['Manufacturer']]; Version = $f[[int]$col['Version']]; Type = $type
            Isolation = $f[[int]$col['Isolation']]; Files = $files }
    }
}

function Read-WorkerPerfPrintQueues([string]$Path, [long]$FromMs, [long]$ToMs, [ref]$Skipped) {
    # printqueues.csv rows with FromMs <= TimeMs <= ToMs: @{ TimeMs; Queue; Jobs; JobErrors; NotReadyErrors } (counters as
    # [double], NaN when unreadable; the error counters are running raw values).
    $csv = Read-WorkerPerfCsvFile $Path 'printqueues.csv' -OwnHeader
    if ($null -ne $Skipped) { $Skipped.Value = [int]$csv.Skipped }
    $col = $csv.Col
    foreach ($k in 'Timestamp', 'Queue', 'Jobs', 'JobErrors', 'NotReadyErrors') { if (-not $col.ContainsKey($k)) { return } }
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $style = [Globalization.NumberStyles]::Float
    foreach ($f in $csv.Rows) {
        $dto = ConvertTo-WorkerPerfTimestamp $f[[int]$col['Timestamp']]
        if ($null -eq $dto) { continue }
        $ms = $dto.ToUnixTimeMilliseconds()
        if ($ms -lt $FromMs -or $ms -gt $ToMs) { continue }
        $q = @{ TimeMs = $ms; Queue = $f[[int]$col['Queue']] }
        foreach ($k in 'Jobs', 'JobErrors', 'NotReadyErrors') {
            $v = [double]::NaN
            if (-not [double]::TryParse($f[[int]$col[$k]], $style, $inv, [ref]$v)) { $v = [double]::NaN }
            $q[$k] = $v
        }
        $q
    }
}

# ---- incidents from events ----
# Set-WorkerPerfEventSessions, Get-WorkerPerfEventIncidentKind and New-WorkerPerfEventIncidents need WorkerPerf.EventConfig.ps1
# (Format-WorkerPerfErrorCode). New-WorkerPerfEventIncidents emits plain pipeline output: wrap calls in @(...).

$script:WorkerPerfIncidentEventKinds = @('crash', 'hang', 'service', 'print', 'profileerror', 'system')
$script:WorkerPerfIncidentEventLimit = 50

function Test-WorkerPerfEventPersonUser([string]$User, $Config) {
    # $true for an account name that may be a person: not empty and, without its domain, matching none of the patterns
    # in nonPersonAccounts of events.json (service, virtual and computer accounts).
    if ([string]::IsNullOrEmpty($User)) { return $false }
    $name = $User.Substring($User.LastIndexOf('\') + 1)
    if ($name.Length -eq 0) { return $false }
    foreach ($p in @($Config.NonPersonAccounts)) { if ($name -like $p) { return $false } }
    return $true
}

function Test-WorkerPerfEventInSession($Event, $Config) {
    # In a user session: a session number above 0, or without a session number an account that may be a person.
    # Session 0 holds the services, whichever account a service runs as.
    if ([int]$Event.SessionId -gt 0) { return $true }
    return ([int]$Event.SessionId -lt 0 -and (Test-WorkerPerfEventPersonUser ([string]$Event.User) $Config))
}

function Get-WorkerPerfEventAffectedUser($Event, $Config) {
    # The person affected by a record: the owner of its session when Set-WorkerPerfEventSessions found one, else the
    # record's own account when it may be a person, else ''. A virtual account (DWM-3) or SYSTEM in a user session thus
    # names the session's user.
    if ($Event.ContainsKey('SessionUser')) {
        $su = [string]$Event.SessionUser
        if (Test-WorkerPerfEventPersonUser $su $Config) { return $su }
    }
    $u = [string]$Event.User
    if (Test-WorkerPerfEventPersonUser $u $Config) { return $u }
    return ''
}

function Get-WorkerPerfLeafName([string]$Name) {
    # File name of a path ('C:\x\spoolsv.exe' -> 'spoolsv.exe').
    $i = $Name.LastIndexOfAny([char[]]@('\', '/'))
    if ($i -ge 0) { return $Name.Substring($i + 1) }
    return $Name
}

function Set-WorkerPerfEventSessions {
    # Sets SessionIndex and SessionUser on every record: the model's session with the same session number that was alive
    # at the event's time, else the session of the same user alive at that time, else -1 and ''. An event of session 0
    # (the services) gets no session, whatever its account, and an account that is no person is never matched by name.
    # Events from before the capture thus never get a session of the capture. A session counts as alive from the
    # snapshot before its first one to the snapshot after its last one, exclusive (one snapshot interval at the ends of
    # the capture): a session that ended with the crash is gone from the next snapshot. SessionUser is the session's
    # user; a record without user takes it as User as well.
    param([object[]]$Events, $Model, $Config)
    $times = [long[]]@($Model.Snap.TimeMs)
    $n = $times.Length
    $intervalMs = [long]0
    $sec = Get-WorkerPerfField $Model.Meta 'IntervalSeconds'
    if ($null -ne $sec) { $intervalMs = [long]([double]$sec * 1000) }
    $bySid = @{}
    $byUser = @{}
    foreach ($s in @($Model.Sessions)) {
        $a = [int]$s.FirstP; $b = [int]$s.LastP
        if ($a -lt 0 -or $b -lt $a -or $b -ge $n -or [int]$s.Sid -le 0) { continue }
        $lo = $(if ($a -gt 0) { $times[$a - 1] } else { $times[0] - $intervalMs })
        $hi = $(if ($b -lt $n - 1) { $times[$b + 1] } else { $times[$n - 1] + $intervalMs })
        $span = @{ Session = $s; From = $times[$a]; To = $times[$b]; Lo = $lo; Hi = $hi }
        $sid = [int]$s.Sid
        if (-not $bySid.ContainsKey($sid)) { $bySid[$sid] = New-Object System.Collections.Generic.List[object] }
        $bySid[$sid].Add($span)
        $u = ([string]$s.User).ToLowerInvariant()
        if ($u.Length -gt 0) {
            if (-not $byUser.ContainsKey($u)) { $byUser[$u] = New-Object System.Collections.Generic.List[object] }
            $byUser[$u].Add($span)
        }
    }
    # Among the sessions alive at the time: the smallest distance to the session's own snapshots, then the lowest index
    # (candidates are in index order, so the first of equals wins).
    $pick = {
        param($List, [long]$T)
        $best = $null; $bestDist = [long]0
        foreach ($c in $List) {
            if (-not ($T -gt $c.Lo -and $T -lt $c.Hi)) { continue }
            $dist = [long]0
            if ($T -lt $c.From) { $dist = $c.From - $T } elseif ($T -gt $c.To) { $dist = $T - $c.To }
            if ($null -eq $best -or $dist -lt $bestDist) { $best = $c; $bestDist = $dist }
        }
        return $best
    }
    foreach ($e in $Events) {
        $e['SessionIndex'] = -1
        $e['SessionUser'] = ''
        $sid = [int]$e.SessionId
        if ($sid -eq 0) { continue }
        $t = [long]$e.TimeMs
        $found = $null
        if ($sid -gt 0 -and $bySid.ContainsKey($sid)) { $found = & $pick $bySid[$sid] $t }
        $user = [string]$e.User
        if ($null -eq $found -and (Test-WorkerPerfEventPersonUser $user $Config)) {
            $key = $user.Substring($user.LastIndexOf('\') + 1).ToLowerInvariant()
            if ($byUser.ContainsKey($key)) { $found = & $pick $byUser[$key] $t }
        }
        if ($null -eq $found) { continue }
        $e['SessionIndex'] = [int]$found.Session.Index
        $e['SessionUser'] = [string]$found.Session.User
        if ($user.Length -eq 0) { $e['User'] = [string]$found.Session.User }
    }
}

function Get-WorkerPerfEventIncidentKind($Event, $Config) {
    # Incident kind of a record, or $null for kinds that form no incident. A crash or hang of a print process and the
    # failure of a print service count as print problems.
    $kind = [string]$Event.Kind
    if ($script:WorkerPerfIncidentEventKinds -cnotcontains $kind) { return $null }
    if (($kind -eq 'crash' -or $kind -eq 'hang') -and @($Config.PrintProcesses) -contains (Get-WorkerPerfLeafName ([string]$Event.App))) { return 'print' }
    if ($kind -eq 'service' -and @($Config.PrintServices) -contains [string]$Event.Service) { return 'print' }
    return $kind
}

function Get-WorkerPerfListedDriverName([string]$Name, [object[]]$Drivers) {
    # The driver list's spelling of a driver name (matched without regard to case), else the name as given.
    foreach ($d in $Drivers) { if ([string]::Equals([string]$d.Name, $Name, [StringComparison]::OrdinalIgnoreCase)) { return [string]$d.Name } }
    return $Name
}

function Get-WorkerPerfModuleDriver([string]$Module, [object[]]$Drivers) {
    # Name of the first driver of the list whose files hold the module, or ''.
    if ($Module.Length -eq 0) { return '' }
    $leaf = Get-WorkerPerfLeafName $Module
    foreach ($d in $Drivers) { if (@($d.Files) -contains $leaf) { return [string]$d.Name } }
    return ''
}

function Get-WorkerPerfEventIncidentKey($Event, [string]$Kind, [object[]]$Drivers) {
    # @{ Key; Driver }: the grouping key of a record (compared without regard to case) and, for a print problem, its driver.
    $driver = ''
    if ($Kind -eq 'crash' -or $Kind -eq 'hang') { $key = [string]$Event.App }
    elseif ($Kind -eq 'service') { $key = [string]$Event.Service }
    elseif ($Kind -eq 'profileerror') { $key = [string]$Event.Source }
    elseif ($Kind -eq 'system') { $key = [string]$Event.Group + '|' + [string]$Event.Object }
    else {
        # print: the driver, else the driver whose files hold the faulting module, else the printer, else the source
        $driver = Get-WorkerPerfListedDriverName ([string]$Event.Driver) $Drivers
        if ($driver.Length -eq 0) { $driver = Get-WorkerPerfModuleDriver ([string]$Event.Module) $Drivers }
        $key = $driver
        if ($key.Length -eq 0) { $key = [string]$Event.Printer }
        if ($key.Length -eq 0) { $key = [string]$Event.Source }
    }
    return @{ Key = $key; Driver = $driver }
}

function Get-WorkerPerfCountedValues([System.Collections.Generic.List[object]]$Records, [string]$Field, [bool]$IsCode) {
    # Distinct non-empty values of a field without regard to case: @{ Value; Count; First }, by count descending, then
    # by first appearance. The first spelling is kept.
    $index = @{}
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($r in $Records) {
        $v = [string]$r[$Field]
        if ($IsCode) { $v = Format-WorkerPerfErrorCode $v }
        if ($v.Length -eq 0) { continue }
        $k = $v.ToLowerInvariant()
        if ($index.ContainsKey($k)) { $index[$k].Count++; continue }
        $item = @{ Value = $v; Count = 1; First = $list.Count }
        $index[$k] = $item
        $list.Add($item)
    }
    $list.ToArray() | Sort-Object -Property @{ Expression = { $_.Count }; Descending = $true }, @{ Expression = { $_.First } }
}

function Get-WorkerPerfFirstValue([System.Collections.Generic.List[object]]$Records, [string]$Field) {
    foreach ($r in $Records) { $v = [string]$r[$Field]; if ($v.Length -gt 0) { return $v } }
    return ''
}

function New-WorkerPerfEventIncidents {
    # Incidents from event records: records of the same incident kind and key (without regard to case) in time order
    # form one incident while the gap to the previous record is at most GroupMinutes. A crash or hang becomes an incident
    # when one record lies in a user session or the group has two records or more; a service failure when the service
    # is an important one or it failed twice or more; print, profile and system problems always. Numbered from FirstId
    # by start, kind and key. Events keeps the first 50 records; Count counts all.
    param([object[]]$Events, $Config, $Settings, [object[]]$Drivers, [int]$FirstId, [switch]$Before)
    if ($null -eq $Drivers) { $Drivers = @() }
    $gapMs = [double]$Settings.GroupMinutes * 60000
    # records with their kind and key, in time order (stable on equal times by input position)
    $tagged = New-Object System.Collections.Generic.List[object]
    $pos = 0
    foreach ($e in @($Events)) {
        $pos++
        if ($null -eq $e) { continue }
        $kind = Get-WorkerPerfEventIncidentKind $e $Config
        if ($null -eq $kind) { continue }
        $k = Get-WorkerPerfEventIncidentKey $e $kind $Drivers
        # a print problem from a crash or hang of a print process, or from the stop of a print service
        $origin = ''
        if ($kind -eq 'print') {
            if ($e.Kind -eq 'crash' -or $e.Kind -eq 'hang') { $origin = 'process' } elseif ($e.Kind -eq 'service') { $origin = 'service' }
        }
        $tagged.Add(@{ Event = $e; Kind = $kind; Key = $k.Key; Driver = $k.Driver; Pos = $pos; Origin = $origin; Group = $kind + "`n" + $k.Key.ToLowerInvariant() })
    }
    if ($tagged.Count -eq 0) { return }
    $sorted = @($tagged.ToArray() | Sort-Object -Property @{ Expression = { [long]$_.Event.TimeMs } }, @{ Expression = { $_.Pos } })
    # One outage of the print spooler is one incident: the stop of a print service at most GroupMinutes from a crash of
    # a print process takes that crash's key (the nearest crash, the earlier one on equal distance), so it joins the
    # crash's incident; the record keeps its own kind.
    $crashes = @($sorted | Where-Object { $_.Origin -eq 'process' })
    if ($crashes.Count -gt 0) {
        $j = -1
        foreach ($t in $sorted) {
            if ($t.Origin -ne 'service') { continue }
            $ms = [long]$t.Event.TimeMs
            while ($j + 1 -lt $crashes.Count -and [long]$crashes[$j + 1].Event.TimeMs -le $ms) { $j++ }
            $best = $null; $bestDist = [double]::PositiveInfinity
            if ($j -ge 0) { $best = $crashes[$j]; $bestDist = $ms - [long]$best.Event.TimeMs }
            if ($j + 1 -lt $crashes.Count -and ([long]$crashes[$j + 1].Event.TimeMs - $ms) -lt $bestDist) {
                $best = $crashes[$j + 1]; $bestDist = [long]$best.Event.TimeMs - $ms
            }
            if ($null -ne $best -and $bestDist -le $gapMs) { $t.Key = $best.Key; $t.Driver = $best.Driver; $t.Group = $best.Group }
        }
    }
    # groups in order of their first record; each group is split at gaps over GroupMinutes
    $groups = @{}
    $order = New-Object System.Collections.Generic.List[string]
    foreach ($t in $sorted) {
        if (-not $groups.ContainsKey($t.Group)) { $groups[$t.Group] = New-Object System.Collections.Generic.List[object]; $order.Add($t.Group) }
        $groups[$t.Group].Add($t)
    }
    $runs = New-Object System.Collections.Generic.List[object]
    foreach ($g in $order) {
        $cur = $null; $last = [long]0
        foreach ($t in $groups[$g]) {
            $ms = [long]$t.Event.TimeMs
            if ($null -eq $cur -or ($ms - $last) -gt $gapMs) { $cur = New-Object System.Collections.Generic.List[object]; $runs.Add($cur) }
            $cur.Add($t); $last = $ms
        }
    }
    $incidents = New-Object System.Collections.Generic.List[object]
    foreach ($run in $runs) {
        $first = $run[0]
        $kind = $first.Kind
        $records = New-Object System.Collections.Generic.List[object]
        foreach ($t in $run) { $records.Add($t.Event) }
        $inSession = $false
        foreach ($r in $records) { if (Test-WorkerPerfEventInSession $r $Config) { $inSession = $true; break } }
        $service = Get-WorkerPerfFirstValue $records 'Service'
        $keep = $true
        if ($kind -eq 'crash' -or $kind -eq 'hang') { $keep = ($inSession -or $records.Count -ge 2) }
        elseif ($kind -eq 'service') { $keep = (@($Config.ImportantServices) -contains $service -or $records.Count -ge 2) }
        if (-not $keep) { continue }

        $users = New-Object System.Collections.Generic.List[string]
        $seenUsers = @{}
        $sessions = New-Object System.Collections.Generic.List[int]
        foreach ($r in $records) {
            $u = Get-WorkerPerfEventAffectedUser $r $Config
            if ($u.Length -gt 0 -and -not $seenUsers.ContainsKey($u.ToLowerInvariant())) { $seenUsers[$u.ToLowerInvariant()] = $true; $users.Add($u) }
            $si = -1
            if ($r.ContainsKey('SessionIndex')) { $si = [int]$r.SessionIndex }
            if ($si -ge 0 -and -not $sessions.Contains($si)) { $sessions.Add($si) }
        }
        $versions = New-Object System.Collections.Generic.List[string]
        foreach ($v in @(Get-WorkerPerfCountedValues $records 'AppVersion' $false | Sort-Object -Property @{ Expression = { $_.First } })) { $versions.Add($v.Value) }
        $modules = @(Get-WorkerPerfCountedValues $records 'Module' $false | ForEach-Object { @{ Name = $_.Value; Count = $_.Count } })
        $codes = @(Get-WorkerPerfCountedValues $records 'Code' $true | ForEach-Object {
                $text = ''
                if ($Config.ErrorCodes.ContainsKey($_.Value)) { $text = [string]$Config.ErrorCodes[$_.Value] }
                @{ Code = $_.Value; Text = $text; Count = $_.Count }
            })
        $driver = ''
        foreach ($t in $run) { if ($t.Driver.Length -gt 0) { $driver = $t.Driver; break } }
        if ($driver.Length -eq 0) { $driver = Get-WorkerPerfFirstValue $records 'Driver' }
        # at most 50 records: the first 49 and the last, so the kept list spans the whole incident
        $kept = New-Object System.Collections.Generic.List[object]
        $truncated = ($records.Count -gt $script:WorkerPerfIncidentEventLimit)
        if ($truncated) {
            for ($x = 0; $x -lt $script:WorkerPerfIncidentEventLimit - 1; $x++) { $kept.Add($records[$x]) }
            $kept.Add($records[$records.Count - 1])
        }
        else { $kept.AddRange($records) }
        $incidents.Add(@{
                Id = 0; Kind = $kind; Key = $first.Key; Group = $(if ($kind -eq 'print') { 'print' } else { [string]$first.Event.Group })
                StartMs = [long]$records[0].TimeMs; EndMs = [long]$records[$records.Count - 1].TimeMs; Count = $records.Count
                Events = $kept.ToArray(); EventsTruncated = $truncated; Users = [string[]]$users.ToArray(); Sessions = [int[]]$sessions.ToArray()
                InSession = $inSession; Severity = $(if ($inSession) { 2 } else { 1 })
                Versions = [string[]]$versions.ToArray(); Modules = $modules; SameModule = ($modules.Count -eq 1 -and $modules[0].Count -eq $records.Count)
                Codes = $codes; App = (Get-WorkerPerfFirstValue $records 'App'); Service = $service; Driver = $driver
                Printer = (Get-WorkerPerfFirstValue $records 'Printer'); Source = (Get-WorkerPerfFirstValue $records 'Source'); Before = [bool]$Before
                Patterns = @(); Overlap = @(); Companions = @()
                SortKey = $first.Key.ToLowerInvariant()
            })
    }
    # Ordinal order, so the numbering does not depend on the culture of the machine that writes the report. Start, kind
    # and lower-case key are unique: equal kind and key with the same start would be the same incident.
    $incidents.Sort([Comparison[object]] {
            param($a, $b)
            if ($a.StartMs -ne $b.StartMs) { return $a.StartMs.CompareTo($b.StartMs) }
            $c = [string]::CompareOrdinal($a.Kind, $b.Kind)
            if ($c -ne 0) { return $c }
            return [string]::CompareOrdinal($a.SortKey, $b.SortKey)
        })
    $id = $FirstId
    foreach ($inc in $incidents) {
        $inc.Remove('SortKey')
        $inc.Id = $id; $id++
        $inc
    }
}
