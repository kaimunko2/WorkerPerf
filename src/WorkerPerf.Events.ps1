#Requires -Version 5.1
# WorkerPerf analysis library: reads the event and print files of a capture (definitions only).
# Requires WorkerPerf.Common.ps1 (headers) and WorkerPerf.Load.ps1 (Read-WorkerPerfCsvFile, ConvertTo-WorkerPerfTimestamp).
# Each file is read by its own header line (Read-WorkerPerfCsvFile -OwnHeader): a file of an older format has fewer
# columns. -Skipped receives the number of rows left out because they have fewer fields than that header.
# Read-WorkerPerfEventCsv, Read-WorkerPerfPrintDrivers and Read-WorkerPerfPrintQueues emit plain pipeline output: wrap calls in @(...).

$script:WorkerPerfEventNumberColumns = @('EventId', 'Level', 'Pid', 'SessionId')
# Format 2 wrote no group: these kinds were all of the security group.
$script:WorkerPerfSecurityKinds = @('scan-start', 'scan-end', 'signature-update', 'applocker-block')

# a time stamp that names its offset: ends in 'Z' or in '+hh:mm' / '-hh:mm' (also without colon)
$script:WorkerPerfOffsetPattern = New-Object System.Text.RegularExpressions.Regex '(Z|[+-]\d\d:?\d\d)\s*$', 'IgnoreCase'

function Get-WorkerPerfEventOffset($Event, [int]$Default) {
    # The UTC offset in minutes of a record's own time stamp (OffsetMinutes from Read-WorkerPerfEventCsv), else Default.
    $o = Get-WorkerPerfField $Event 'OffsetMinutes'
    if ($null -eq $o) { return $Default }
    return [int]$o
}

function Read-WorkerPerfEventCsv([string]$Path, [string]$FileName, [ref]$Skipped) {
    # Events of events.csv or events_before.csv in format 2 or 3 as hashtables with TimeMs, OffsetMinutes (the time
    # stamp's own UTC offset, $null when it names none) and every column of format 3:
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
        # the record's own UTC offset (its local time on that day, across a daylight-saving change); $null when the
        # time stamp names none (the reader then took the machine's offset; the analysis falls back to the capture's)
        $off = $null
        if ($script:WorkerPerfOffsetPattern.IsMatch($f[$cTs])) { $off = [int]$dto.Offset.TotalMinutes }
        $e = @{ TimeMs = $dto.ToUnixTimeMilliseconds(); OffsetMinutes = $off }
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

$script:WorkerPerfAccountPatternCache = @{}

function Test-WorkerPerfAccountPattern([string]$Name, [string]$Pattern) {
    # Wildcard match without regard to case, the same under every culture (-like follows the current culture: under
    # tr-TR 'dienst' would not match 'DIENST').
    $w = $script:WorkerPerfAccountPatternCache[$Pattern]
    if ($null -eq $w) {
        $opt = [System.Management.Automation.WildcardOptions]::IgnoreCase -bor [System.Management.Automation.WildcardOptions]::CultureInvariant
        $w = New-Object System.Management.Automation.WildcardPattern $Pattern, $opt
        $script:WorkerPerfAccountPatternCache[$Pattern] = $w
    }
    return $w.IsMatch($Name)
}

function Test-WorkerPerfEventPersonUser([string]$User, $Config) {
    # $true for an account name that may be a person: not empty, without its domain matching none of the patterns in
    # nonPersonAccounts of events.json (service, virtual and computer accounts), and with a domain part matching none of
    # nonPersonDomains (NT SERVICE, Window Manager ...; a config without that list checks no domain).
    if ([string]::IsNullOrEmpty($User)) { return $false }
    $cut = $User.LastIndexOf('\')
    $name = $User.Substring($cut + 1)
    if ($name.Length -eq 0) { return $false }
    foreach ($p in @($Config.NonPersonAccounts)) { if (Test-WorkerPerfAccountPattern $name $p) { return $false } }
    if ($cut -gt 0) {
        $domain = $User.Substring(0, $cut)
        foreach ($p in @(Get-WorkerPerfField $Config 'NonPersonDomains')) { if ($null -ne $p -and (Test-WorkerPerfAccountPattern $domain $p)) { return $false } }
    }
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

function Test-WorkerPerfRealModule([string]$Module, $Config) {
    # $false for an empty module and for what Windows writes when it found none (noModules of events.json: 'unknown',
    # 'StackHash_*'); such a module names no cause.
    $leaf = Get-WorkerPerfLeafName $Module
    if ($leaf.Trim().Length -eq 0) { return $false }
    $none = Get-WorkerPerfField $Config 'NoModules'
    if ($null -eq $none) { $none = $script:WorkerPerfDefaultNoModules }
    return (-not (Test-WorkerPerfNamePattern $leaf ([string[]]@($none))))
}

function Get-WorkerPerfModuleDrivers([string]$Module, [object[]]$Drivers) {
    # Names of all drivers of the list whose files hold the module (file name without regard to case), sorted by name.
    if ($Module.Length -eq 0) { return , [string[]]@() }
    $leaf = Get-WorkerPerfLeafName $Module
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($d in $Drivers) {
        if ($null -ne $d -and @($d.Files) -contains $leaf -and -not $names.Contains([string]$d.Name)) { $names.Add([string]$d.Name) }
    }
    $arr = $names.ToArray()
    [Array]::Sort($arr, [StringComparer]::OrdinalIgnoreCase)
    return , [string[]]$arr
}

function Get-WorkerPerfModuleDriver([string]$Module, [object[]]$Drivers) {
    # Name of the one driver whose files hold the module, or '' when none or several hold it (a shared file such as
    # unidrv.dll names no single driver).
    $all = Get-WorkerPerfModuleDrivers $Module $Drivers
    if ($all.Length -eq 1) { return $all[0] }
    return ''
}

function Get-WorkerPerfEventIncidentKey($Event, [string]$Kind, [object[]]$Drivers, $Config) {
    # @{ Key; Driver }: the grouping key of a record (compared without regard to case) and, for a print problem, its driver.
    $driver = ''
    if ($Kind -eq 'crash' -or $Kind -eq 'hang') { $key = [string]$Event.App }
    elseif ($Kind -eq 'service') { $key = [string]$Event.Service }
    elseif ($Kind -eq 'profileerror') { $key = [string]$Event.Source }
    elseif ($Kind -eq 'system') { $key = [string]$Event.Group + '|' + [string]$Event.Object }
    else {
        # print: the driver, else the one driver whose files hold the faulting module (not when several hold it), else the
        # printer, else the source
        $driver = Get-WorkerPerfListedDriverName ([string]$Event.Driver) $Drivers
        if ($driver.Length -eq 0 -and (Test-WorkerPerfRealModule ([string]$Event.Module) $Config)) { $driver = Get-WorkerPerfModuleDriver ([string]$Event.Module) $Drivers }
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
    # by start, kind and key. Events keeps at most 50 records; Count counts all. ModuleEvents counts the records that can
    # name a module (crashes and records that name one); SameModule: one real module in all of them. Every record gets
    # IncidentId: the Id of its incident, or 0 (so Add-WorkerPerfEventPatterns can look at all records of an incident).
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
        $k = Get-WorkerPerfEventIncidentKey $e $kind $Drivers $Config
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
        # the records that can name a module: crashes, and any other record that names one (a service stop never does)
        $moduleEvents = 0
        foreach ($r in $records) { if ([string]$r.Kind -eq 'crash' -or ([string]$r.Module).Length -gt 0) { $moduleEvents++ } }
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
                Versions = [string[]]$versions.ToArray(); Modules = $modules; ModuleEvents = $moduleEvents; SameModule = ($modules.Count -eq 1 -and $modules[0].Count -eq $moduleEvents -and (Test-WorkerPerfRealModule ([string]$modules[0].Name) $Config))
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
# kinds of those groups that are only recorded: no companion of an incident (P1-R33, P1-R36)
$script:WorkerPerfNoCompanionKinds = @('name-resolution', 'profile-warning')
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
    $realModule = @{}
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
        if ($script:WorkerPerfCompanionGroups -contains $group -and $script:WorkerPerfNoCompanionKinds -notcontains $kind) { $candidates.Add($e) }
        if ($kind -eq 'crash' -and ([string]$e.Module).Length -gt 0) {
            $mk = ([string]$e.Module).ToLowerInvariant()
            if (-not $realModule.ContainsKey($mk)) { $realModule[$mk] = Test-WorkerPerfRealModule ([string]$e.Module) $Config }
            if (-not $realModule[$mk]) { continue }
            $m = (Get-WorkerPerfLeafName ([string]$e.Module)).ToLowerInvariant()
            $app = Get-WorkerPerfLeafName ([string]$e.App)
            if ($app.Length -eq 0) { continue }
            if (-not $crashModules.ContainsKey($m)) { $crashModules[$m] = [ordered]@{} }
            if (-not $crashModules[$m].Contains($app.ToLowerInvariant())) { $crashModules[$m][$app.ToLowerInvariant()] = $app }
        }
    }
    # Hangs by application and session ('s:<index>'), by application and person ('u:<user>') and, for hangs without a
    # session, by application and person once more ('n:<user>'), each list in time order. A crash in a session looks at
    # 's:' and 'n:', a crash without a session at 'u:': every hang in the window of such a list is a match.
    $hangIndex = @{}
    $appsWithoutSession = @{}
    $appKey = @{}
    $userOf = @{}
    # the affected person of a record, looked up once per pair of session owner and account
    $affected = {
        param($E)
        $su = ''
        if ($E.ContainsKey('SessionUser')) { $su = [string]$E.SessionUser }
        $pair = $su + '|' + [string]$E.User
        if (-not $userOf.ContainsKey($pair)) { $userOf[$pair] = (Get-WorkerPerfEventAffectedUser $E $Config).ToLowerInvariant() }
        return $userOf[$pair]
    }
    $appOf = {
        param([string]$App)
        if (-not $appKey.ContainsKey($App)) { $appKey[$App] = (Get-WorkerPerfLeafName $App).ToLowerInvariant() }
        return $appKey[$App]
    }
    foreach ($h in $hangs) {
        $app = & $appOf ([string]$h.App)
        $si = -1
        if ($h.ContainsKey('SessionIndex')) { $si = [int]$h.SessionIndex }
        $u = & $affected $h
        $keys = New-Object System.Collections.Generic.List[string]
        if ($si -ge 0) { $keys.Add($app + '|s:' + $si) }
        if ($u.Length -gt 0) { $keys.Add($app + '|u:' + $u) }
        if ($si -lt 0 -and $u.Length -gt 0) { $keys.Add($app + '|n:' + $u); $appsWithoutSession[$app] = $true }
        foreach ($k in $keys) {
            if (-not $hangIndex.ContainsKey($k)) { $hangIndex[$k] = New-Object System.Collections.Generic.List[long] }
            $hangIndex[$k].Add([long]$h.TimeMs)
        }
    }
    $hangLists = @{}
    foreach ($k in $hangIndex.Keys) { $hangLists[$k] = $hangIndex[$k].ToArray() }
    $warningMs = [long[]]@($warnings | ForEach-Object { [long]$_.TimeMs })
    # companions with equal time in a fixed order: group, kind, provider, object (ordinal), then input order
    # (the list is in time order already; only runs of equal time are sorted)
    $cand = $candidates.ToArray()
    $i = 0
    while ($i -lt $cand.Length) {
        $j = $i + 1
        while ($j -lt $cand.Length -and [long]$cand[$j].TimeMs -eq [long]$cand[$i].TimeMs) { $j++ }
        if ($j - $i -gt 1) {
            $run = New-Object System.Collections.Generic.List[object]
            for ($k = $i; $k -lt $j; $k++) { $run.Add(@{ E = $cand[$k]; Pos = $k }) }
            $run.Sort([Comparison[object]] {
                    param($x, $y)
                    $c = 0
                    foreach ($f in 'Group', 'Kind', 'Source', 'Object') { if ($c -eq 0) { $c = [string]::CompareOrdinal([string]$x.E[$f], [string]$y.E[$f]) } }
                    if ($c -eq 0) { $c = $x.Pos.CompareTo($y.Pos) }
                    return $c
                })
            for ($k = $i; $k -lt $j; $k++) { $cand[$k] = $run[$k - $i].E }
        }
        $i = $j
    }
    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($c in $cand) { $candidates.Add($c) }
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
        $moduleNames = @($inc.Modules | ForEach-Object { [string]$_.Name } | Where-Object { Test-WorkerPerfRealModule $_ $Config })
        $found = @{}

        # a memory warning is never its own cause
        if (-not $Before -and -not ($inc.Kind -eq 'system' -and [string]$inc.Group -eq 'memory')) {
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
        # AfterhangMinutes before a crash of the incident; Count says how many of the incident's crashes followed one
        $crashCount = 0; $afterCount = 0; $firstHangMs = [long]0
        foreach ($m in $members) {
            if ([string]$m.Kind -ne 'crash') { continue }
            $crashCount++
            $t = [long]$m.TimeMs
            $app = & $appOf ([string]$m.App)
            $si = -1
            if ($m.ContainsKey('SessionIndex')) { $si = [int]$m.SessionIndex }
            $k1 = ''; $k2 = ''
            if ($si -ge 0) {
                $k1 = $app + '|s:' + $si
                if ($appsWithoutSession.ContainsKey($app)) { $k2 = $app + '|n:' + (& $affected $m) }
            }
            else {
                $u = & $affected $m
                if ($u.Length -gt 0) { $k1 = $app + '|u:' + $u }
            }
            $hit = $null
            foreach ($k in $k1, $k2) {
                if ($k.Length -eq 0 -or -not $hangLists.ContainsKey($k)) { continue }
                $ms = $hangLists[$k]
                # the last hang at or before the crash
                $lo = 0; $hi = $ms.Length
                while ($lo -lt $hi) { $mid = ($lo + $hi) -shr 1; if ($ms[$mid] -le $t) { $lo = $mid + 1 } else { $hi = $mid } }
                if ($lo -gt 0 -and $ms[$lo - 1] -ge $t - $afterhangMs -and ($null -eq $hit -or $ms[$lo - 1] -gt $hit)) { $hit = $ms[$lo - 1] }
            }
            if ($null -eq $hit) { continue }
            if ($afterCount -eq 0) { $firstHangMs = [long]$hit }
            $afterCount++
        }
        if ($afterCount -gt 0) { $found['afterhang'] = @{ HangMs = $firstHangMs; Count = $afterCount; Crashes = $crashCount } }

        # sharedmodule: a module of the incident, no general system module, in which two applications or more crashed
        foreach ($name in $moduleNames) {
            $leaf = Get-WorkerPerfLeafName $name
            if (Test-WorkerPerfNamePattern $leaf ([string[]]@($Config.SystemModules))) { continue }
            $key = $leaf.ToLowerInvariant()
            if (-not $crashModules.ContainsKey($key) -or $crashModules[$key].Count -lt 2) { continue }
            $apps = [string[]]@($crashModules[$key].Values)
            [Array]::Sort($apps, [StringComparer]::OrdinalIgnoreCase)
            $found['sharedmodule'] = @{ Module = $name; Apps = $apps }
            break
        }

        # printdriver: a module that is a file of a listed driver; a file of several drivers names none of them (Driver '')
        foreach ($name in $moduleNames) {
            $names = Get-WorkerPerfModuleDrivers $name $Drivers
            if ($names.Length -eq 0) { continue }
            $one = $(if ($names.Length -eq 1) { $names[0] } else { '' })
            $found['printdriver'] = @{ Module = $name; Driver = $one; Drivers = $names }
            break
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
        $overlap.Sort()
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
    foreach ($p in $perf) { $perfHits[[int]$p.Id].Sort(); $p['EventIncidents'] = [int[]]$perfHits[[int]$p.Id].ToArray() }
}

$script:WorkerPerfTextListLimit = 10

function Join-WorkerPerfTextList([object[]]$Items, $Texts) {
    # At most 10 entries, joined with ', ', then " (+n weitere)" for the rest.
    $list = @($Items)
    if ($list.Count -le $script:WorkerPerfTextListLimit) { return ($list -join ', ') }
    $shown = ($list[0..($script:WorkerPerfTextListLimit - 1)] -join ', ')
    return $shown + ($Texts['list.more'] -f ($list.Count - $script:WorkerPerfTextListLimit))
}

function Get-WorkerPerfEventWhat($Event, $Texts) {
    # What a record says in words (companion.<kind>, for kind system companion.system.<group>), with its object;
    # an unknown kind falls back to the provider.
    $kind = [string]$Event.Kind
    $key = 'companion.' + $kind
    if ($kind -eq 'system') { $key = 'companion.system.' + [string]$Event.Group }
    $what = [string]$Event.Source
    if ($Texts.ContainsKey($key)) { $what = [string]$Texts[$key] }
    $object = [string](Get-WorkerPerfField $Event 'Object')
    if ($object.Length -gt 0) { $what = $what + ' ' + $object }
    return $what.Trim()
}

function Format-WorkerPerfEventDate([long]$Ms, [int]$OffsetMinutes) {
    # The server's local date of a time ('dd.MM.yyyy'), as Format-WorkerPerfClock gives its clock time.
    $t = [DateTimeOffset]::FromUnixTimeMilliseconds($Ms).UtcDateTime.AddMinutes($OffsetMinutes)
    return $t.ToString('dd.MM.yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Format-WorkerPerfEventSpan([long]$StartMs, [long]$EndMs, [int]$StartOffset, [int]$EndOffset, [bool]$WithDate) {
    # 'HH:mm:ss' or 'HH:mm:ss-HH:mm:ss' (en dash); with the date 'dd.MM.yyyy HH:mm:ss', a span on one day
    # 'dd.MM.yyyy HH:mm:ss-HH:mm:ss' and a span across days with both dates. Each end in the local time of its own
    # offset (a span across a daylight-saving change has two).
    $dash = [string][char]0x2013
    $from = Format-WorkerPerfClock $StartMs $StartOffset
    $to = Format-WorkerPerfClock $EndMs $EndOffset
    if ($WithDate) {
        $fromDay = Format-WorkerPerfEventDate $StartMs $StartOffset
        $toDay = Format-WorkerPerfEventDate $EndMs $EndOffset
        $from = $fromDay + ' ' + $from
        if ($toDay -ne $fromDay) { $to = $toDay + ' ' + $to }
    }
    if ($EndMs -eq $StartMs) { return $from }
    return $from + $dash + $to
}

function Get-WorkerPerfPatternStatement($Pattern, $Texts, [int]$OffsetMinutes, [bool]$WithDate, [string]$StartDay) {
    # The statement of one pattern of an event incident as the sentence says it (with its leading space). Companion
    # times use each record's own offset, else OffsetMinutes; with WithDate a companion on another day than StartDay
    # names its date.
    $d = $Pattern.Detail
    $text = $Texts['pattern.' + $Pattern.Id]
    switch ([string]$Pattern.Id) {
        'afterhang' {
            if ($d.ContainsKey('Count') -and [int]$d.Count -lt [int]$d.Crashes) { $text = $Texts['pattern.afterhang.some'] -f [int]$d.Count, [int]$d.Crashes }
        }
        'sharedmodule' { $text = $text -f $d.Module, (Join-WorkerPerfTextList @($d.Apps) $Texts) }
        'printdriver' {
            if (([string]$d.Driver).Length -gt 0) { $text = $text -f $d.Module, $d.Driver }
            else { $text = $Texts['pattern.printdriver.many'] -f $d.Module, (Join-WorkerPerfTextList @($d.Drivers) $Texts) }
        }
        'securitymodule' { $text = $text -f $d.Module, $d.Product }
        'manyusers' { $text = $text -f $d.Users }
        'oneuser' { $text = $text -f $d.User, $d.Count }
        'companion' {
            $list = @($d.Events | ForEach-Object {
                    $o = Get-WorkerPerfEventOffset $_ $OffsetMinutes
                    $at = Format-WorkerPerfClock ([long]$_.TimeMs) $o
                    if ($WithDate) {
                        $day = Format-WorkerPerfEventDate ([long]$_.TimeMs) $o
                        if ($day -ne $StartDay) { $at = $day + ' ' + $at }
                    }
                    $at + ' ' + (Get-WorkerPerfEventWhat $_ $Texts)
                })
            $text = $text -f ($list -join ', ')
        }
        'overlap' {
            $ids = @($d.Incidents)
            if ($ids.Count -gt 1) { $text = $Texts['pattern.overlap.many'] -f (Join-WorkerPerfTextList $ids $Texts) } else { $text = $text -f $ids[0] }
        }
    }
    return $text
}

function Get-WorkerPerfEventIncidentText {
    # One sentence for an event incident: the head of its kind with time span and count, the users, modules, error codes
    # and versions, then the statement of every pattern in their order, or "no pattern" (no cause is named then).
    # Times are the server's local time of each record: its own offset (OffsetMinutes of the record), else the
    # capture's (-OffsetMinutes). An incident before the capture (Before) names the date as well; a companion on
    # another day than the incident's first record names its date too. Model is not needed for the text.
    # Lists name at most 10 entries; counts are always the full numbers.
    param($Incident, $Model, $Texts, $Config, [int]$OffsetMinutes)
    $inc = $Incident
    $times = { param($n) $(if ([int]$n -eq 1) { $Texts['event.count.one'] } else { $Texts['event.count.many'] -f [int]$n }) }
    # Events keeps the first and the last record of the incident
    $kept = @($inc.Events)
    $startOffset = $OffsetMinutes; $endOffset = $OffsetMinutes
    if ($kept.Count -gt 0) { $startOffset = Get-WorkerPerfEventOffset $kept[0] $OffsetMinutes; $endOffset = Get-WorkerPerfEventOffset $kept[$kept.Count - 1] $OffsetMinutes }
    $withDate = [bool](Get-WorkerPerfField $inc 'Before')
    $clock = Format-WorkerPerfEventSpan ([long]$inc.StartMs) ([long]$inc.EndMs) $startOffset $endOffset $withDate
    $startDay = Format-WorkerPerfEventDate ([long]$inc.StartMs) $startOffset
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
            # system: the group in words and the object
            $first = @($inc.Events)[0]
            $subject = Get-WorkerPerfEventWhat @{ Kind = 'system'; Group = [string]$inc.Group; Source = [string]$inc.Source; Object = [string](Get-WorkerPerfField $first 'Object') } $Texts
        }
    }
    $sb = New-Object System.Text.StringBuilder
    # a crash or hang without an application name has a head of its own
    if (($kind -eq 'crash' -or $kind -eq 'hang') -and $subject.Length -eq 0) { [void]$sb.Append(($Texts["event.$kind.noapp"] -f $clock, (& $times $inc.Count))) }
    else { [void]$sb.Append(($Texts["event.$kind"] -f $clock, $subject, (& $times $inc.Count))) }

    $users = @($inc.Users)
    if ($users.Count -gt 0) { [void]$sb.Append(($Texts['event.users'] -f (Join-WorkerPerfTextList $users $Texts))) }
    elseif (-not [bool]$inc.InSession) { [void]$sb.Append($Texts['event.nouser']) }
    # modules: only real ones ('unknown', StackHash_* and empty name none); "n von m" counts the records that can name
    # a module (ModuleEvents; a service stop of the same outage is not among them)
    $modules = @($inc.Modules | Where-Object { Test-WorkerPerfRealModule ([string]$_.Name) $Config })
    $moduleEvents = Get-WorkerPerfField $inc 'ModuleEvents'
    if ($null -eq $moduleEvents) { $moduleEvents = $inc.Count }
    if ($modules.Count -eq 1) {
        if ([int]$modules[0].Count -ge [int]$moduleEvents) { [void]$sb.Append(($Texts['event.module.same'] -f [string]$modules[0].Name)) }
        else { [void]$sb.Append(($Texts['event.module.some'] -f [string]$modules[0].Name, [int]$modules[0].Count, [int]$moduleEvents)) }
    }
    elseif ($modules.Count -gt 1) {
        $list = @($modules | ForEach-Object { '{0} ({1})' -f [string]$_.Name, (& $times $_.Count) })
        [void]$sb.Append(($Texts['event.module.mixed'] -f (Join-WorkerPerfTextList $list $Texts)))
    }
    elseif (@($inc.Events | Where-Object { [string]$_.Kind -eq 'crash' }).Count -gt 0) { [void]$sb.Append($Texts['event.module.unknown']) }
    $codes = @($inc.Codes | ForEach-Object { if (([string]$_.Text).Length -gt 0) { '{0} ({1})' -f $_.Code, $_.Text } else { [string]$_.Code } })
    if ($codes.Count -eq 1) { [void]$sb.Append(($Texts['event.code'] -f $codes[0])) }
    elseif ($codes.Count -gt 1) { [void]$sb.Append(($Texts['event.codes'] -f (Join-WorkerPerfTextList $codes $Texts))) }
    $versions = @($inc.Versions)
    if ($versions.Count -gt 1) { [void]$sb.Append(($Texts['event.versions'] -f (Join-WorkerPerfTextList $versions $Texts))) }

    $patterns = @($inc.Patterns)
    foreach ($p in $patterns) { [void]$sb.Append((Get-WorkerPerfPatternStatement $p $Texts $OffsetMinutes $withDate $startDay)) }
    if ($patterns.Count -eq 0) { [void]$sb.Append($Texts['pattern.none']) }
    return $sb.ToString()
}

# ---- lookback and print state ----
# Get-WorkerPerfLookback summarises the events of the days before the capture (spec 5.6), Get-WorkerPerfPrintState the
# print drivers, queues and print processes of the capture (spec 5.7). Both return one hashtable.

# a reported time before the capture: the events within this many minutes of it (as the report's focus radius)
$script:WorkerPerfReportedRadiusMinutes = 15

function Get-WorkerPerfLookback {
    # The events of Model.EventsBefore before the first tick, grouped into incidents (Before, numbered from FirstId) with
    # the patterns that need no measurement. Returns @{ Days; FromMs; Capped; EventCount; Incidents; PerDay; Near }:
    # Days = Meta.EventLookbackDays (0 without), FromMs = first tick - Days, Capped = the logs whose lookback reached its
    # cap, EventCount = all events before the first tick, PerDay = @{ Day = 'yyyy-MM-dd'; Count } of the events with an
    # incident kind per day in the server's local time (ascending, days without such events left out), Near = all
    # events within 15 minutes of ReportedMs when ReportedMs lies before the first tick, in time order.
    # ReportedWallMs instead gives the reported time as the server's wall clock (its fields read as UTC): Near then holds
    # the events whose own local time lies within 15 minutes of it, when it lies before the local time of the first
    # tick. An ambiguous clock time (the repeated hour at the end of daylight saving time) thus meets the events of both
    # readings. "The first tick" is Model.CaptureStartMs when the model has it (the capture's start, whatever -From
    # says), else Tick.TimeMs[0]. The records get SessionIndex -1 and SessionUser '' (no session of the capture existed
    # then) and IncidentId.
    param($Model, $Config, $Settings, [object[]]$Roles, [int]$FirstId, [object]$ReportedMs, [object]$ReportedWallMs)
    $tickMs = [long[]]@()
    $tick = Get-WorkerPerfField $Model 'Tick'
    if ($null -ne $tick -and $null -ne (Get-WorkerPerfField $tick 'TimeMs')) { $tickMs = [long[]]$tick.TimeMs }
    $firstMs = [long]::MaxValue
    if ($tickMs.Length -gt 0) { $firstMs = $tickMs[0] }
    $captureStart = Get-WorkerPerfField $Model 'CaptureStartMs'
    if ($null -ne $captureStart) { $firstMs = [long]$captureStart }
    $meta = Get-WorkerPerfField $Model 'Meta'
    $days = 0
    $d = Get-WorkerPerfField $meta 'EventLookbackDays'
    if ($null -ne $d) { $days = [int]$d }
    $capped = [string[]]@(@(Get-WorkerPerfField $meta 'LookbackCapped') | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
    $offset = 0
    $o = Get-WorkerPerfField $meta 'OffsetMinutes'
    if ($null -ne $o) { $offset = [int][Math]::Round([double]$o) }
    $fromMs = [long]0
    if ($tickMs.Length -gt 0 -or $null -ne $captureStart) { $fromMs = $firstMs - [long]$days * 86400000L }

    $events = New-Object System.Collections.Generic.List[object]
    $before = Get-WorkerPerfEventsByTime @(Get-WorkerPerfField $Model 'EventsBefore')
    foreach ($e in $before) {
        if ([long]$e.TimeMs -ge $firstMs) { continue }
        $e['SessionIndex'] = -1
        $e['SessionUser'] = ''
        $events.Add($e)
    }
    $records = $events.ToArray()
    $drivers = @(@(Get-WorkerPerfField $Model 'PrintDrivers') | Where-Object { $null -ne $_ })
    $incidents = @(New-WorkerPerfEventIncidents -Events $records -Config $Config -Settings $Settings -Drivers $drivers -FirstId $FirstId -Before)
    if ($incidents.Count -gt 0) {
        Add-WorkerPerfEventPatterns -Incidents $incidents -AllEvents $records -Model $null -Thresholds $null -Settings $Settings -Config $Config -Roles $Roles `
            -Drivers $drivers -PerfIncidents $null -Before
    }

    # per day in the server's local time of each record (its own offset, else the capture's); sorted, because a
    # change of offset could in theory put a later record on an earlier local day
    $counts = @{}
    $dayList = New-Object System.Collections.Generic.List[string]
    foreach ($e in $records) {
        if ($null -eq (Get-WorkerPerfEventIncidentKind $e $Config)) { continue }
        $o = Get-WorkerPerfEventOffset $e $offset
        $day = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$e.TimeMs).UtcDateTime.AddMinutes($o).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        if (-not $counts.ContainsKey($day)) { $counts[$day] = 0; $dayList.Add($day) }
        $counts[$day]++
    }
    $dayArr = $dayList.ToArray()
    [Array]::Sort($dayArr, [StringComparer]::Ordinal)
    $perDay = @($dayArr | ForEach-Object { @{ Day = $_; Count = [int]$counts[$_] } })

    $near = New-Object System.Collections.Generic.List[object]
    if ($null -ne $ReportedWallMs -and [long]$ReportedWallMs -lt $firstMs + [long]$offset * 60000L) {
        foreach ($e in $records) { if (Test-WorkerPerfEventNearWall $e ([long]$ReportedWallMs) $offset) { $near.Add($e) } }
    }
    elseif ($null -ne $ReportedMs -and [long]$ReportedMs -lt $firstMs) {
        $radius = [long]$script:WorkerPerfReportedRadiusMinutes * 60000L
        foreach ($e in $records) {
            $t = [long]$e.TimeMs
            if ($t -ge [long]$ReportedMs - $radius -and $t -le [long]$ReportedMs + $radius) { $near.Add($e) }
        }
    }
    return @{ Days = $days; FromMs = $fromMs; Capped = $capped; EventCount = $records.Length; Incidents = $incidents; PerDay = $perDay; Near = $near.ToArray() }
}

function Get-WorkerPerfCounterGrowth([double[]]$Values) {
    # Errors counted by a running counter: the sum of its increases from the first readable value on (the baseline).
    # A drop means the counter started again from 0 (spooler restart): the new value counts in full. Unreadable values
    # (NaN) are skipped.
    $sum = 0.0
    $last = [double]::NaN
    foreach ($v in $Values) {
        if ([double]::IsNaN($v)) { continue }
        if (-not [double]::IsNaN($last)) {
            if ($v -ge $last) { $sum += $v - $last } else { $sum += $v }
        }
        $last = $v
    }
    return $sum
}

function Get-WorkerPerfPrintState {
    # The print state of the capture: @{ Drivers; Queues; Processes }.
    # - Drivers, in the order of the driver list: @{ Name; Manufacturer; Version; Type; Isolation; Isolated; Files;
    #   Involved; PossiblyInvolved }. Involved: the driver is the key of a print incident or the one driver of a
    #   printdriver pattern (names without regard to case). PossiblyInvolved: not involved, but one of several drivers
    #   whose files hold the module of a printdriver pattern (which of them took part cannot be told).
    # - Queues, by name: @{ Name; MaxJobs (highest waiting jobs, $null when never readable); JobErrors; NotReadyErrors }
    #   with the errors as the growth of the running counters during the capture (Get-WorkerPerfCounterGrowth).
    # - Processes of the role 'Drucken' by K: @{ K; Name; CpuMaxPct; WsMaxMB }.
    param($Model, [object[]]$EventIncidents)
    $involved = @{}
    $possible = @{}
    foreach ($inc in @($EventIncidents)) {
        if ($null -eq $inc) { continue }
        if ([string]$inc.Kind -eq 'print' -and ([string]$inc.Key).Length -gt 0) { $involved[([string]$inc.Key).ToLowerInvariant()] = $true }
        foreach ($p in @(Get-WorkerPerfField $inc 'Patterns')) {
            if ($null -eq $p -or [string]$p.Id -ne 'printdriver') { continue }
            $one = [string](Get-WorkerPerfField $p.Detail 'Driver')
            if ($one.Length -gt 0) { $involved[$one.ToLowerInvariant()] = $true; continue }
            foreach ($n in @(Get-WorkerPerfField $p.Detail 'Drivers')) { if ($null -ne $n) { $possible[([string]$n).ToLowerInvariant()] = $true } }
        }
    }
    $drivers = New-Object System.Collections.Generic.List[object]
    foreach ($d in @(Get-WorkerPerfField $Model 'PrintDrivers')) {
        if ($null -eq $d) { continue }
        $name = [string]$d.Name
        $isInvolved = $involved.ContainsKey($name.ToLowerInvariant())
        $drivers.Add(@{
                Name = $name; Manufacturer = [string]$d.Manufacturer; Version = [string]$d.Version; Type = [int]$d.Type; Isolation = [string]$d.Isolation
                Isolated = ([string]$d.Isolation -eq 'isolated'); Files = [string[]]@(@($d.Files) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
                Involved = $isInvolved; PossiblyInvolved = (-not $isInvolved -and $possible.ContainsKey($name.ToLowerInvariant()))
            })
    }

    # queues: the samples of each queue in time order
    $byQueue = @{}
    $samples = Get-WorkerPerfEventsByTime @(Get-WorkerPerfField $Model 'PrintQueues')
    foreach ($q in $samples) {
        $k = [string]$q.Queue
        if (-not $byQueue.ContainsKey($k)) { $byQueue[$k] = New-Object System.Collections.Generic.List[object] }
        $byQueue[$k].Add($q)
    }
    $names = [string[]]@($byQueue.Keys)
    [Array]::Sort($names, [StringComparer]::OrdinalIgnoreCase)
    $queues = New-Object System.Collections.Generic.List[object]
    foreach ($k in $names) {
        $samples = $byQueue[$k].ToArray()
        $max = $null
        foreach ($q in $samples) {
            $v = [double]$q.Jobs
            if (-not [double]::IsNaN($v) -and ($null -eq $max -or $v -gt $max)) { $max = $v }
        }
        $queues.Add(@{
                Name = $k; MaxJobs = $max
                JobErrors = (Get-WorkerPerfCounterGrowth ([double[]]@($samples | ForEach-Object { [double]$_.JobErrors })))
                NotReadyErrors = (Get-WorkerPerfCounterGrowth ([double[]]@($samples | ForEach-Object { [double]$_.NotReadyErrors })))
            })
    }

    $processes = New-Object System.Collections.Generic.List[object]
    foreach ($p in @(Get-WorkerPerfField $Model 'Proc')) {
        if ($null -eq $p -or [string](Get-WorkerPerfField $p 'Role') -ne 'Drucken') { continue }
        $processes.Add(@{ K = [int]$p.K; Name = [string]$p.Name; CpuMaxPct = [double]$p.CpuMaxPct; WsMaxMB = [Math]::Round([double]$p.WsMaxKB / 1024.0, 1) })
    }
    $procArr = $processes.ToArray()
    if ($procArr.Length -gt 1) { $procArr = @($procArr | Sort-Object -Property @{ Expression = { $_.K } }) }
    return @{ Drivers = $drivers.ToArray(); Queues = $queues.ToArray(); Processes = $procArr }
}

# ---- report output ----
# The report data of events and event incidents (the contract of the report page): ordered records with lower-case keys.

function Test-WorkerPerfEventNearWall($Event, [long]$WallMs, [int]$DefaultOffset) {
    # $true when a record's own local time (its offset, else DefaultOffset) lies within 15 minutes of a reported time
    # given as the server's wall clock (WallMs: the wall-clock fields read as UTC). This is the reported time in UTC
    # with the offset of the record's own day; an ambiguous clock time meets the records of both readings.
    $o = Get-WorkerPerfEventOffset $Event $DefaultOffset
    return ([Math]::Abs([long]$Event['TimeMs'] + [long]$o * 60000L - $WallMs) -le [long]$script:WorkerPerfReportedRadiusMinutes * 60000L)
}

function Test-WorkerPerfIncidentNearWall($Incident, [long]$WallMs, [int]$DefaultOffset) {
    # $true when a reported wall-clock time lies within 15 minutes of an event incident's span, each end in the local
    # time of its own record (Events keeps the first and the last).
    $kept = @($Incident.Events | Where-Object { $null -ne $_ })
    $a = $DefaultOffset; $b = $DefaultOffset
    if ($kept.Count -gt 0) { $a = Get-WorkerPerfEventOffset $kept[0] $DefaultOffset; $b = Get-WorkerPerfEventOffset $kept[$kept.Count - 1] $DefaultOffset }
    $r = [long]$script:WorkerPerfReportedRadiusMinutes * 60000L
    return ($WallMs -ge [long]$Incident.StartMs + [long]$a * 60000L - $r -and $WallMs -le [long]$Incident.EndMs + [long]$b * 60000L + $r)
}

function ConvertTo-WorkerPerfEventOut($Event, [int]$OffsetMinutes = 0) {
    # One event record (a hashtable) for the report: t = UTC milliseconds, offsetMin = the UTC offset of its own time
    # stamp (else OffsetMinutes, the capture's), s = session index or -1, code normalised as in the incidents. The text
    # fields log, group, app, module, code, user, printer, driver, service and object are left out when empty; t,
    # offsetMin, source, id, level, kind, s and text are always there. Reads the fields directly: it runs once per event.
    $o = $Event['OffsetMinutes']
    if ($null -eq $o) { $o = $OffsetMinutes }
    $s = $Event['SessionIndex']
    if ($null -eq $s) { $s = -1 }
    $level = $Event['Level']
    if ($null -eq $level) { $level = -1 }
    $out = [ordered]@{ t = [long]$Event['TimeMs']; offsetMin = [int]$o }
    $v = [string]$Event['Log']; if ($v.Length -gt 0) { $out['log'] = $v }
    $out['source'] = [string]$Event['Source']
    $out['id'] = [int]$Event['EventId']
    $out['level'] = [int]$level
    $v = [string]$Event['Group']; if ($v.Length -gt 0) { $out['group'] = $v }
    $out['kind'] = [string]$Event['Kind']
    $v = [string]$Event['App']; if ($v.Length -gt 0) { $out['app'] = $v }
    $v = [string]$Event['Module']; if ($v.Length -gt 0) { $out['module'] = $v }
    $v = [string]$Event['Code']; if ($v.Length -gt 0) { $v = Format-WorkerPerfErrorCode $v; if ($v.Length -gt 0) { $out['code'] = $v } }
    $out['s'] = [int]$s
    $v = [string]$Event['User']; if ($v.Length -gt 0) { $out['user'] = $v }
    $v = [string]$Event['Printer']; if ($v.Length -gt 0) { $out['printer'] = $v }
    $v = [string]$Event['Driver']; if ($v.Length -gt 0) { $out['driver'] = $v }
    $v = [string]$Event['Service']; if ($v.Length -gt 0) { $out['service'] = $v }
    $v = [string]$Event['Object']; if ($v.Length -gt 0) { $out['object'] = $v }
    $out['text'] = [string]$Event['Text']
    return $out
}

function ConvertTo-WorkerPerfDetailOut($Detail, [int]$OffsetMinutes) {
    # The Detail of a pattern with lower-case first letters, keys in ordinal order; Events as event records.
    $out = [ordered]@{}
    if ($null -eq $Detail) { return $out }
    $keys = [string[]]@($Detail.Keys)
    [Array]::Sort($keys, [StringComparer]::Ordinal)
    foreach ($k in $keys) {
        $name = $k.Substring(0, 1).ToLowerInvariant() + $k.Substring(1)
        $v = $Detail[$k]
        if ($k -eq 'Events') { $v = @(@($v) | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-WorkerPerfEventOut $_ $OffsetMinutes }) }
        elseif ($v -is [System.Array]) { $v = @($v) }
        $out[$name] = $v
    }
    return $out
}

function ConvertTo-WorkerPerfEventIncidentOut {
    # An event incident for the report: every key of a performance incident with neutral values (type 'ereignis'), the
    # incident's kept records as events, and the event part (kind, key, counts, users, modules, codes, patterns with
    # their statement and details, overlap, companions). Texts and OffsetMinutes (the capture's) give the statements.
    param($Incident, [string]$Text, [bool]$Focus, [bool]$Near, $Texts, [int]$OffsetMinutes)
    $inc = $Incident
    $kept = @($inc.Events | Where-Object { $null -ne $_ })
    $startOffset = $OffsetMinutes
    if ($kept.Count -gt 0) { $startOffset = Get-WorkerPerfEventOffset $kept[0] $OffsetMinutes }
    $before = [bool](Get-WorkerPerfField $inc 'Before')
    $startDay = Format-WorkerPerfEventDate ([long]$inc.StartMs) $startOffset
    $patterns = @(@($inc.Patterns) | Where-Object { $null -ne $_ } | ForEach-Object {
            [ordered]@{ id = [string]$_.Id; text = (Get-WorkerPerfPatternStatement $_ $Texts $OffsetMinutes $before $startDay).TrimStart(); detail = (ConvertTo-WorkerPerfDetailOut $_.Detail $OffsetMinutes) }
        })
    $companions = @(@($inc.Companions) | Where-Object { $null -ne $_ } | ForEach-Object {
            [ordered]@{ t = [long]$_.TimeMs; offsetMin = (Get-WorkerPerfEventOffset $_ $OffsetMinutes); group = [string]$_.Group; source = [string]$_.Source
                id = [int]$_.EventId; kind = [string]$_.Kind; object = [string](Get-WorkerPerfField $_ 'Object') }
        })
    $start = [long]$inc.StartMs; $end = [long]$inc.EndMs
    $moduleEvents = Get-WorkerPerfField $inc 'ModuleEvents'
    if ($null -eq $moduleEvents) { $moduleEvents = $inc.Count }
    $eventPart = [ordered]@{
        kind = [string]$inc.Kind; key = [string]$inc.Key; group = [string]$inc.Group; count = [int]$inc.Count; eventsTruncated = [bool](Get-WorkerPerfField $inc 'EventsTruncated')
        users = [string[]]@($inc.Users); sessions = [int[]]@($inc.Sessions); inSession = [bool]$inc.InSession; versions = [string[]]@($inc.Versions)
        modules = @(@($inc.Modules) | Where-Object { $null -ne $_ } | ForEach-Object { [ordered]@{ name = [string]$_.Name; count = [int]$_.Count } })
        moduleEvents = [int]$moduleEvents; sameModule = [bool]$inc.SameModule
        codes = @(@($inc.Codes) | Where-Object { $null -ne $_ } | ForEach-Object { [ordered]@{ code = [string]$_.Code; text = [string]$_.Text; count = [int]$_.Count } })
        app = [string]$inc.App; service = [string]$inc.Service; driver = [string]$inc.Driver; printer = [string]$inc.Printer; source = [string]$inc.Source
        before = $before; patterns = $patterns; overlap = [int[]]@($inc.Overlap); companions = $companions
    }
    return [ordered]@{
        id = [int]$inc.Id; type = 'ereignis'; chronic = $false; severity = [int]$inc.Severity
        start = $start; end = $end; durSec = [Math]::Round(($end - $start) / 1000.0, 1); lead = $null; resources = [string[]]@()
        text = $Text; focus = $Focus; nearReported = $Near; scanActive = $false
        events = @($kept | ForEach-Object { ConvertTo-WorkerPerfEventOut $_ $OffsetMinutes })
        signals = @(); affected = @(); main = $null; cause = $null; contributors = [ordered]@{}
        delayProcs = @(); endpoints = @(); ica = @(); security = [ordered]@{ products = @(); totalPct = $null }
        companion = $null; chronicContext = @(); eventIncidents = [int[]]@(); event = $eventPart
    }
}
