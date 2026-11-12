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
    # the capture, but never before the first tick of the capture): a session that ended with the crash is gone from the
    # next snapshot. SessionUser is the session's user; a record without user takes it as User as well.
    param([object[]]$Events, $Model, $Config)
    $times = [long[]]@($Model.Snap.TimeMs)
    $firstTickMs = [long]::MinValue
    $tick = Get-WorkerPerfField $Model 'Tick'
    if ($null -ne $tick -and $null -ne (Get-WorkerPerfField $tick 'TimeMs')) {
        $tickMs = [long[]]$tick.TimeMs
        if ($tickMs.Length -gt 0) { $firstTickMs = $tickMs[0] }
    }
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
        if ($t -lt $firstTickMs) { continue }
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
    # by start, kind and key. Events keeps at most 50 records; Count counts all. Every record gets IncidentId: the Id of
    # its incident, or 0 (so Add-WorkerPerfEventPatterns can look at all records of an incident).
    param([object[]]$Events, $Config, $Settings, [object[]]$Drivers, [int]$FirstId, [switch]$Before)
    if ($null -eq $Drivers) { $Drivers = @() }
    $gapMs = [double]$Settings.GroupMinutes * 60000
    # records with their kind and key, in time order (stable on equal times by input position)
    $tagged = New-Object System.Collections.Generic.List[object]
    $pos = 0
    foreach ($e in @($Events)) {
        $pos++
        if ($null -eq $e) { continue }
        $e['IncidentId'] = 0
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
    # One outage of the print spooler is one incident: the stop of a print service at most GroupMinutes from a print
    # incident that holds a crash or hang of a print process joins that incident (it takes its key and driver; the record
    # keeps its own kind). The distance is measured to the incident (0 inside it, else to its first or its last record),
    # and a joined stop extends the incident for the stops after it. On equal distance the smaller key wins, then the
    # earlier incident, so the result does not depend on the input order.
    $stops = @($sorted | Where-Object { $_.Origin -eq 'service' })
    if ($stops.Count -gt 0 -and @($sorted | Where-Object { $_.Origin -eq 'process' }).Count -gt 0) {
        $printGroups = [ordered]@{}
        foreach ($t in $sorted) {
            if ($t.Kind -ne 'print' -or $t.Origin -eq 'service') { continue }
            if (-not $printGroups.Contains($t.Group)) { $printGroups[$t.Group] = New-Object System.Collections.Generic.List[object] }
            $printGroups[$t.Group].Add($t)
        }
        $spooler = New-Object System.Collections.Generic.List[object]
        foreach ($g in $printGroups.Keys) {
            $run = $null
            foreach ($t in $printGroups[$g]) {
                $ms = [long]$t.Event.TimeMs
                if ($null -eq $run -or ($ms - $run.End) -gt $gapMs) {
                    $run = @{ Group = [string]$g; Key = $t.Key; Driver = ''; Start = $ms; End = $ms; FromProcess = $false }
                    $spooler.Add($run)
                }
                $run.End = $ms
                if ($t.Origin -eq 'process') { $run.FromProcess = $true }
                if ($run.Driver.Length -eq 0) { $run.Driver = $t.Driver }
            }
        }
        $spooler = @($spooler | Where-Object { $_.FromProcess })
        foreach ($t in $stops) {
            $ms = [long]$t.Event.TimeMs
            $best = $null; $bestDist = [long]0
            foreach ($r in $spooler) {
                $dist = [long]0
                if ($ms -lt $r.Start) { $dist = $r.Start - $ms } elseif ($ms -gt $r.End) { $dist = $ms - $r.End }
                if ($dist -gt $gapMs) { continue }
                $better = ($null -eq $best -or $dist -lt $bestDist)
                if (-not $better -and $dist -eq $bestDist) {
                    $c = [string]::CompareOrdinal($r.Group, $best.Group)
                    $better = ($c -lt 0 -or ($c -eq 0 -and $r.Start -lt $best.Start))
                }
                if ($better) { $best = $r; $bestDist = $dist }
            }
            if ($null -eq $best) { continue }
            $t.Key = $best.Key; $t.Driver = $best.Driver; $t.Group = $best.Group
            if ($ms -lt $best.Start) { $best.Start = $ms }
            if ($ms -gt $best.End) { $best.End = $ms }
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
                SortKey = $first.Key.ToLowerInvariant(); Records = $records
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
        foreach ($r in $inc.Records) { $r['IncidentId'] = $inc.Id }
        $inc.Remove('Records')
        $inc
    }
}

# ---- patterns and plain text ----
# Add-WorkerPerfEventPatterns compares event incidents with the measurement and with each other (spec 5.3, 5.5);
# Get-WorkerPerfEventIncidentText needs WorkerPerf.Findings.ps1 (Format-WorkerPerfClock).

$script:WorkerPerfPatternOrder = @('resource', 'afterhang', 'sharedmodule', 'printdriver', 'securitymodule', 'manyusers', 'oneuser', 'companion', 'overlap')
# the patterns that need no measurement, for the events before the capture
$script:WorkerPerfBeforePatterns = @('afterhang', 'sharedmodule', 'printdriver', 'securitymodule', 'manyusers', 'oneuser', 'companion')
$script:WorkerPerfCompanionGroups = @('storage', 'fileserver', 'profile', 'security')
$script:WorkerPerfResourceSignals = @('mem.used', 'mem.commit')
$script:WorkerPerfCompanionLimit = 10

function Get-WorkerPerfFirstAtLeast([long[]]$Times, [long]$Ms) {
    # Index of the first element >= Ms in an ascending array; Length when there is none.
    $lo = 0; $hi = $Times.Length
    while ($lo -lt $hi) {
        $mid = ($lo + $hi) -shr 1
        if ($Times[$mid] -lt $Ms) { $lo = $mid + 1 } else { $hi = $mid }
    }
    return $lo
}

function Get-WorkerPerfEventsByTime([object[]]$Events) {
    # The records in time order (stable on equal times); a list already in order is returned as it is.
    $list = @($Events | Where-Object { $null -ne $_ })
    $ordered = $true
    for ($i = 1; $i -lt $list.Count; $i++) { if ([long]$list[$i].TimeMs -lt [long]$list[$i - 1].TimeMs) { $ordered = $false; break } }
    if ($ordered -or $list.Count -lt 2) { return , $list }
    return , @(0..($list.Count - 1) | Sort-Object -Property @{ Expression = { [long]$list[$_].TimeMs } }, @{ Expression = { $_ } } | ForEach-Object { $list[$_] })
}

function Test-WorkerPerfEventMember($Event, $Incident) {
    # $true when a record belongs to the incident (IncidentId from New-WorkerPerfEventIncidents).
    if ($Event.ContainsKey('IncidentId')) { return ([int]$Event.IncidentId -eq [int]$Incident.Id) }
    foreach ($e in @($Incident.Events)) { if ([object]::ReferenceEquals($e, $Event)) { return $true } }
    return $false
}

function Test-WorkerPerfSameSessionOrUser($A, $B, $Config) {
    # Same user session when both records have one; otherwise the same affected person.
    $sa = -1; $sb = -1
    if ($A.ContainsKey('SessionIndex')) { $sa = [int]$A.SessionIndex }
    if ($B.ContainsKey('SessionIndex')) { $sb = [int]$B.SessionIndex }
    if ($sa -ge 0 -and $sb -ge 0) { return ($sa -eq $sb) }
    $ua = Get-WorkerPerfEventAffectedUser $A $Config
    $ub = Get-WorkerPerfEventAffectedUser $B $Config
    return ($ua.Length -gt 0 -and [string]::Equals($ua, $ub, [StringComparison]::OrdinalIgnoreCase))
}

function Add-WorkerPerfEventPatterns {
    # Sets Patterns (@{ Id; Detail } in the order of $script:WorkerPerfPatternOrder), Overlap (int[]) and Companions on
    # every incident, looking at all records of an incident (also those Events leaves out) and at AllEvents (the records
    # the incidents were made from). Every performance incident gets EventIncidents (int[]). With -Before only the
    # patterns without measurement are checked and Model and PerfIncidents may be $null. A performance incident that is a
    # lasting condition (Chronic) spans the whole capture and is no overlap.
    param([object[]]$Incidents, [object[]]$AllEvents, $Model, $Thresholds, $Settings, $Config, [object[]]$Roles, [object[]]$Drivers,
        [object[]]$PerfIncidents, [switch]$Before)
    if ($null -eq $Drivers) { $Drivers = @() }
    if ($null -eq $Roles) { $Roles = @() }
    $all = Get-WorkerPerfEventsByTime @($AllEvents)
    $toMs = { param($Minutes) [long]([double]$Minutes * 60000) }
    $resourceMs = & $toMs $Settings.ResourceMinutes
    $afterhangMs = & $toMs $Settings.AfterhangMinutes
    $companionMs = & $toMs $Settings.CompanionMinutes

    # the records of each incident, the hangs, memory warnings, companion candidates and crashed modules, in time order
    $byIncident = @{}
    $hangs = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[object]
    $candidates = New-Object System.Collections.Generic.List[object]
    $crashModules = @{}
    foreach ($e in $all) {
        if ($e.ContainsKey('IncidentId') -and [int]$e.IncidentId -gt 0) {
            $id = [int]$e.IncidentId
            if (-not $byIncident.ContainsKey($id)) { $byIncident[$id] = New-Object System.Collections.Generic.List[object] }
            $byIncident[$id].Add($e)
        }
        $kind = [string]$e.Kind
        $group = [string]$e.Group
        if ($kind -eq 'hang') { $hangs.Add($e) }
        if ($group -eq 'memory') { $warnings.Add($e) }
        if ($script:WorkerPerfCompanionGroups -contains $group) { $candidates.Add($e) }
        if ($kind -eq 'crash' -and ([string]$e.Module).Length -gt 0) {
            $m = (Get-WorkerPerfLeafName ([string]$e.Module)).ToLowerInvariant()
            $app = Get-WorkerPerfLeafName ([string]$e.App)
            if ($app.Length -eq 0) { continue }
            if (-not $crashModules.ContainsKey($m)) { $crashModules[$m] = [ordered]@{} }
            if (-not $crashModules[$m].Contains($app.ToLowerInvariant())) { $crashModules[$m][$app.ToLowerInvariant()] = $app }
        }
    }
    $hangMs = [long[]]@($hangs | ForEach-Object { [long]$_.TimeMs })
    $warningMs = [long[]]@($warnings | ForEach-Object { [long]$_.TimeMs })
    $candidateMs = [long[]]@($candidates | ForEach-Object { [long]$_.TimeMs })

    # measurement: tick times and the memory signals with their critical value
    $tickMs = [long[]]@()
    $signals = New-Object System.Collections.Generic.List[object]
    if (-not $Before -and $null -ne $Model) {
        $tickMs = [long[]]$Model.Tick.TimeMs
        foreach ($sid in $script:WorkerPerfResourceSignals) {
            if (-not $Model.Tick.Signal.Contains($sid) -or $null -eq $Thresholds -or -not $Thresholds.Contains($sid)) { continue }
            $signals.Add(@{ Id = $sid; Values = [double[]]$Model.Tick.Signal[$sid]; Crit = [double]$Thresholds[$sid].crit })
        }
    }
    $perf = @()
    if (-not $Before -and $null -ne $PerfIncidents) { $perf = @($PerfIncidents | Where-Object { $null -ne $_ }) }
    $perfHits = @{}
    foreach ($p in $perf) { $perfHits[[int]$p.Id] = New-Object System.Collections.Generic.List[int] }
    $security = @($Roles | Where-Object { [string](Get-WorkerPerfField $_ 'role') -eq 'Sicherheit' })

    foreach ($inc in @($Incidents)) {
        if ($null -eq $inc) { continue }
        $members = @($inc.Events)
        if ($byIncident.ContainsKey([int]$inc.Id)) { $members = $byIncident[[int]$inc.Id].ToArray() }
        $memberMs = [long[]]@($members | ForEach-Object { [long]$_.TimeMs })
        $moduleNames = @($inc.Modules | ForEach-Object { [string]$_.Name })
        $found = @{}

        if (-not $Before) {
            # resource: memory over the critical value in a tick of (t - ResourceMinutes, t], or a memory warning in
            # [t - ResourceMinutes, t] that is not the incident itself
            foreach ($m in $members) {
                $t = [long]$m.TimeMs
                $a = Get-WorkerPerfFirstAtLeast $tickMs ($t - $resourceMs + 1)
                $b = Get-WorkerPerfFirstAtLeast $tickMs ($t + 1)
                foreach ($s in $signals) {
                    $peak = [double]::NaN
                    for ($i = $a; $i -lt $b -and $i -lt $s.Values.Length; $i++) {
                        $v = $s.Values[$i]
                        if (-not [double]::IsNaN($v) -and ([double]::IsNaN($peak) -or $v -gt $peak)) { $peak = $v }
                    }
                    if (-not [double]::IsNaN($peak) -and $peak -ge $s.Crit) { $found['resource'] = @{ SignalId = $s.Id; Peak = $peak }; break }
                }
                if ($found.ContainsKey('resource')) { break }
                $b = Get-WorkerPerfFirstAtLeast $warningMs ($t + 1)
                for ($i = $b - 1; $i -ge 0 -and $warningMs[$i] -ge $t - $resourceMs; $i--) {
                    if (-not (Test-WorkerPerfEventMember $warnings[$i] $inc)) { $found['resource'] = @{ WarningMs = $warningMs[$i] }; break }
                }
                if ($found.ContainsKey('resource')) { break }
            }
        }

        # afterhang: a hang of the same application in the same session (else of the same person) at most
        # AfterhangMinutes before a crash of the incident
        foreach ($m in $members) {
            if ([string]$m.Kind -ne 'crash') { continue }
            $t = [long]$m.TimeMs
            $app = Get-WorkerPerfLeafName ([string]$m.App)
            $b = Get-WorkerPerfFirstAtLeast $hangMs ($t + 1)
            for ($i = $b - 1; $i -ge 0 -and $hangMs[$i] -ge $t - $afterhangMs; $i--) {
                $h = $hangs[$i]
                if (-not [string]::Equals((Get-WorkerPerfLeafName ([string]$h.App)), $app, [StringComparison]::OrdinalIgnoreCase)) { continue }
                if (Test-WorkerPerfSameSessionOrUser $h $m $Config) { $found['afterhang'] = @{ HangMs = $hangMs[$i] }; break }
            }
            if ($found.ContainsKey('afterhang')) { break }
        }

        # sharedmodule: a module of the incident, no general system module, in which two applications or more crashed
        foreach ($name in $moduleNames) {
            $leaf = Get-WorkerPerfLeafName $name
            if (@($Config.SystemModules) -contains $leaf) { continue }
            $key = $leaf.ToLowerInvariant()
            if (-not $crashModules.ContainsKey($key) -or $crashModules[$key].Count -lt 2) { continue }
            $apps = [string[]]@($crashModules[$key].Values)
            [Array]::Sort($apps, [StringComparer]::OrdinalIgnoreCase)
            $found['sharedmodule'] = @{ Module = $name; Apps = $apps }
            break
        }

        # printdriver: a module that is a file of a listed driver
        foreach ($name in $moduleNames) {
            $driver = Get-WorkerPerfModuleDriver $name $Drivers
            if ($driver.Length -gt 0) { $found['printdriver'] = @{ Module = $name; Driver = $driver }; break }
        }

        # securitymodule: a module that matches the modules of a role 'Sicherheit'
        foreach ($name in $moduleNames) {
            $leaf = Get-WorkerPerfLeafName $name
            foreach ($r in $security) {
                foreach ($pattern in @(Get-WorkerPerfField $r 'modules')) {
                    if ($null -ne $pattern -and $leaf -like [string]$pattern) { $found['securitymodule'] = @{ Module = $name; Product = [string]$r.label }; break }
                }
                if ($found.ContainsKey('securitymodule')) { break }
            }
            if ($found.ContainsKey('securitymodule')) { break }
        }

        # manyusers and oneuser over the users of all records
        $users = @($inc.Users)
        if (($inc.Kind -eq 'crash' -or $inc.Kind -eq 'hang') -and $users.Count -ge [int]$Settings.ManyUsers) { $found['manyusers'] = @{ Users = $users.Count } }
        if ($users.Count -eq 1) {
            $n = 0
            foreach ($m in $members) { if ([string]::Equals((Get-WorkerPerfEventAffectedUser $m $Config), [string]$users[0], [StringComparison]::OrdinalIgnoreCase)) { $n++ } }
            if ($n -ge [int]$Settings.OneUserEvents) { $found['oneuser'] = @{ User = [string]$users[0]; Count = $n } }
        }

        # companion: storage, file server, profile and security records of other origin near a record of the incident
        $companions = New-Object System.Collections.Generic.List[object]
        if ($memberMs.Length -gt 0) {
            for ($i = Get-WorkerPerfFirstAtLeast $candidateMs ([long]$inc.StartMs - $companionMs); $i -lt $candidateMs.Length; $i++) {
                $t = $candidateMs[$i]
                if ($t -gt [long]$inc.EndMs + $companionMs) { break }
                $c = $candidates[$i]
                if (Test-WorkerPerfEventMember $c $inc) { continue }
                $j = Get-WorkerPerfFirstAtLeast $memberMs ($t - $companionMs)
                if ($j -lt $memberMs.Length -and $memberMs[$j] -le $t + $companionMs) {
                    $companions.Add($c)
                    if ($companions.Count -ge $script:WorkerPerfCompanionLimit) { break }
                }
            }
        }
        if ($companions.Count -gt 0) { $found['companion'] = @{ Events = $companions.ToArray() } }

        # overlap: performance incidents whose window meets the incident's span
        $overlap = New-Object System.Collections.Generic.List[int]
        foreach ($p in $perf) {
            if ([bool](Get-WorkerPerfField $p 'Chronic')) { continue }
            if ([long]$p.StartMs -le [long]$inc.EndMs -and [long]$p.EndMs -ge [long]$inc.StartMs) {
                $overlap.Add([int]$p.Id)
                $perfHits[[int]$p.Id].Add([int]$inc.Id)
            }
        }
        if ($overlap.Count -gt 0) { $found['overlap'] = @{ Incidents = [int[]]$overlap.ToArray() } }

        $allowed = $(if ($Before) { $script:WorkerPerfBeforePatterns } else { $script:WorkerPerfPatternOrder })
        $patterns = New-Object System.Collections.Generic.List[object]
        foreach ($id in $script:WorkerPerfPatternOrder) {
            if ($allowed -contains $id -and $found.ContainsKey($id)) { $patterns.Add(@{ Id = $id; Detail = $found[$id] }) }
        }
        $inc.Patterns = $patterns.ToArray()
        $inc.Overlap = [int[]]$overlap.ToArray()
        $inc.Companions = $companions.ToArray()
    }
    foreach ($p in $perf) { $p['EventIncidents'] = [int[]]$perfHits[[int]$p.Id].ToArray() }
}

function Get-WorkerPerfEventIncidentText {
    # One sentence for an event incident: the head of its kind with time span and count, the users, modules, error codes
    # and versions, then the statement of every pattern in their order, or "no pattern" (no cause is named then).
    # Times are the server's local time (OffsetMinutes, as Format-WorkerPerfClock). Model is not needed for the text.
    param($Incident, $Model, $Texts, $Config, [int]$OffsetMinutes)
    $inc = $Incident
    $clock = Format-WorkerPerfClock ([long]$inc.StartMs) $OffsetMinutes
    if ([long]$inc.EndMs -ne [long]$inc.StartMs) { $clock += [string][char]0x2013 + (Format-WorkerPerfClock ([long]$inc.EndMs) $OffsetMinutes) }
    $count = $(if ([int]$inc.Count -eq 1) { $Texts['event.count.one'] } else { $Texts['event.count.many'] -f [int]$inc.Count })
    $kind = [string]$inc.Kind
    $subject = ''
    switch ($kind) {
        'crash' { $subject = [string]$inc.App }
        'hang' { $subject = [string]$inc.App }
        'service' { $subject = [string]$inc.Service }
        'print' {
            foreach ($v in @($inc.Driver, $inc.Printer, $inc.App, $inc.Service, $inc.Source)) { if (([string]$v).Length -gt 0) { $subject = [string]$v; break } }
        }
        'profileerror' { $subject = [string]$inc.Source }
        default {
            $subject = [string]$inc.Source
            $object = [string](Get-WorkerPerfField $inc.Events[0] 'Object')
            if ($object.Length -gt 0) { $subject = ($subject + ' ' + $object).Trim() }
        }
    }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append(($Texts["event.$kind"] -f $clock, $subject, $count))

    $users = @($inc.Users)
    if ($users.Count -gt 0) { [void]$sb.Append(($Texts['event.users'] -f ($users -join ', '))) }
    elseif (-not [bool]$inc.InSession) { [void]$sb.Append($Texts['event.nouser']) }
    $modules = @($inc.Modules)
    if ($modules.Count -eq 1 -and [bool]$inc.SameModule) { [void]$sb.Append(($Texts['event.module.same'] -f [string]$modules[0].Name)) }
    elseif ($modules.Count -gt 0) {
        $list = @($modules | ForEach-Object { '{0} ({1})' -f [string]$_.Name, $(if ([int]$_.Count -eq 1) { $Texts['event.count.one'] } else { $Texts['event.count.many'] -f [int]$_.Count }) })
        [void]$sb.Append(($Texts['event.module.mixed'] -f ($list -join ', ')))
    }
    $codes = @($inc.Codes | ForEach-Object { if (([string]$_.Text).Length -gt 0) { '{0} ({1})' -f $_.Code, $_.Text } else { [string]$_.Code } })
    if ($codes.Count -gt 0) { [void]$sb.Append(($Texts['event.code'] -f ($codes -join ', '))) }
    $versions = @($inc.Versions)
    if ($versions.Count -gt 1) { [void]$sb.Append(($Texts['event.versions'] -f ($versions -join ', '))) }

    $patterns = @($inc.Patterns)
    foreach ($p in $patterns) {
        $d = $p.Detail
        $text = $Texts['pattern.' + $p.Id]
        switch ([string]$p.Id) {
            'sharedmodule' { $text = $text -f $d.Module, (@($d.Apps) -join ', ') }
            'printdriver' { $text = $text -f $d.Module, $d.Driver }
            'securitymodule' { $text = $text -f $d.Module, $d.Product }
            'manyusers' { $text = $text -f $d.Users }
            'oneuser' { $text = $text -f $d.User, $d.Count }
            'companion' {
                $list = @($d.Events | ForEach-Object {
                        $s = (Format-WorkerPerfClock ([long]$_.TimeMs) $OffsetMinutes) + ' ' + [string]$_.Source
                        if (([string](Get-WorkerPerfField $_ 'Object')).Length -gt 0) { $s += ' ' + [string]$_.Object }
                        $s.Trim()
                    })
                $text = $text -f ($list -join ', ')
            }
            'overlap' { $text = $text -f (@($d.Incidents) -join ', ') }
        }
        [void]$sb.Append($text)
    }
    if ($patterns.Count -eq 0) { [void]$sb.Append($Texts['pattern.none']) }
    return $sb.ToString()
}
