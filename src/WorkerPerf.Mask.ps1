#Requires -Version 5.1
# WorkerPerf report masking: collects the names of a whole capture and assigns their replacement names (definitions only).
# Requires WorkerPerf.Common.ps1, WorkerPerf.Load.ps1 (Open-WorkerPerfCsvReader), WorkerPerf.EventConfig.ps1 (default
# lists of accounts and domains that are not persons) and WorkerPerf.Events.ps1 (event and print driver readers, person check).
# Separate from the masking of the probe script Test-WorkerPerfSources.ps1, which is not used here.
# Get-WorkerPerfMaskRows emits plain pipeline output: wrap calls in @(...).

# kinds of names that each level replaces
$script:WorkerPerfMaskLevelKinds = @{
    Personen = @('user', 'client', 'sid')
    Alles    = @('user', 'client', 'sid', 'server', 'share', 'domain', 'address', 'printer')
}
$script:WorkerPerfMaskIpv4Text = '(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)'
$script:WorkerPerfMaskIpv4 = New-Object System.Text.RegularExpressions.Regex ('^' + $script:WorkerPerfMaskIpv4Text + '$')
$script:WorkerPerfMaskSid = New-Object System.Text.RegularExpressions.Regex '^S-1-5-21-\d+-\d+-\d+-\d+$', 'IgnoreCase'
# folders under C:\Users that belong to no person
$script:WorkerPerfMaskProfileFolders = @('Public', 'Default', 'Default User', 'All Users')
# Fixed patterns in path and instance texts, scanned left to right: an account SID; a UNC path (not the device prefixes
# \\?\ and \\.\) with its server and, when present, its share (\\server\share); a user folder <drive>:\Users\<name>
# (any drive, any case), and the user of a Citrix UPM mount path \Users\<user>_UPM_local (also without drive).
$script:WorkerPerfMaskPathPatternText = '(?<sid>(?<![\w-])S-1-5-21-\d+-\d+-\d+-\d+(?![\w-]))' +
    '|(?<unc>\\\\(?<server>[^\\/\s,;"?.*:|<>][^\\/\s,;"*:|<>]*)\\(?<share>[^\\/\s,;"*:|<>]+)?)' +
    '|(?<drive>(?<![A-Za-z])[A-Za-z]:)?\\Users\\(?<folder>[^\\]+?)(?<upm>_UPM_local)?(?=\\|$)'
$script:WorkerPerfMaskPathPatterns = New-Object System.Text.RegularExpressions.Regex $script:WorkerPerfMaskPathPatternText, 'IgnoreCase'
# Free texts (meta.json) also hold addresses: an IPv4 address that is not part of a longer dotted number, not part of a
# path (no \ or / directly before or after) and not a version (not after "version", "v" and the like). Path segments,
# file names and version fields are never scanned for addresses.
$script:WorkerPerfMaskTextPatterns = New-Object System.Text.RegularExpressions.Regex ($script:WorkerPerfMaskPathPatternText +
    '|(?<ip>(?<![\d.\\/])(?<!\b(?:version|v)[\s:=]*)' + $script:WorkerPerfMaskIpv4Text + '(?!\.?\d)(?![\\/]))'), 'IgnoreCase'

function Get-WorkerPerfMaskRows {
    # The distinct value combinations of some columns of a capture file, in the order of their first row, each as
    # string[] (a column the file lacks gives ''). Columns by the file's own header; a missing file gives nothing.
    param([string]$Path, [string]$FileName, [string[]]$Columns)
    $seen = @{}
    $reader = $null
    try {
        $csv = Open-WorkerPerfCsvReader $Path $FileName -OwnHeader
        $reader = $csv.Reader; $need = $csv.Need
        $ix = @($Columns | ForEach-Object { if ($csv.Col.ContainsKey($_)) { [int]$csv.Col[$_] } else { -1 } })
        while ($null -ne $reader -and $null -ne ($line = $reader.ReadLine())) {
            if ($line.Length -eq 0) { continue }
            if ($line.IndexOf('"') -lt 0) { $f = $line.Split(',') } else { $f = [string[]]@(Split-WorkerPerfCsvLine $line) }
            if ($f.Length -lt $need) { continue }
            $vals = New-Object string[] $ix.Count
            for ($i = 0; $i -lt $ix.Count; $i++) { $vals[$i] = $(if ($ix[$i] -ge 0) { $f[$ix[$i]] } else { '' }) }
            $key = [string]::Join([string][char]0, $vals)
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            , $vals
        }
    }
    finally { if ($null -ne $reader) { $reader.Dispose() } }
}

function Add-WorkerPerfMaskName($State, [string]$Kind, [string]$Name) {
    # Takes a name once (without regard to case), in the spelling and at the place of its first appearance; an empty
    # name is passed over. A name already taken keeps its kind, except that user, client and sid (replaced in both
    # levels) win over the kinds only level Alles replaces: a client that is also an endpoint host is a client.
    # Numbers are given at the end, in the order of the names, per kind.
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $n = $Name.Trim()
    $key = $n.ToLowerInvariant()
    $rec = $State.Seen[$key]
    if ($null -ne $rec) {
        $person = $script:WorkerPerfMaskLevelKinds['Personen']
        if ($person -contains $Kind -and $person -notcontains $rec.Kind) { $rec.Kind = $Kind }
        return
    }
    $rec = @{ Kind = $Kind; Name = $n }
    $State.Seen[$key] = $rec
    $State.Records.Add($rec)
}

function Add-WorkerPerfMaskProtected($State, [string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $n = $Name.Trim()
    $key = $n.ToLowerInvariant()
    if ($State.ProtectedSeen.ContainsKey($key)) { return }
    $State.ProtectedSeen[$key] = $true
    $State.Protected.Add($n)
}

function Add-WorkerPerfMaskHost($State, [string]$HostName) {
    # A host: an IPv4 address, else a server name (leading backslashes of an SMB server name dropped). The DNS suffix of
    # a server name with more than one label after the host (fs01.sim.local -> sim.local) is a domain.
    if ([string]::IsNullOrWhiteSpace($HostName)) { return }
    $h = $HostName.Trim().TrimStart('\')
    if ($script:WorkerPerfMaskIpv4.IsMatch($h)) { Add-WorkerPerfMaskName $State 'address' $h; return }
    Add-WorkerPerfMaskName $State 'server' $h
    $dot = $h.IndexOf('.')
    if ($dot -gt 0 -and $h.IndexOf('.', $dot + 1) -gt $dot + 1 -and -not $h.EndsWith('.')) { Add-WorkerPerfMaskName $State 'domain' $h.Substring($dot + 1) }
}

function Add-WorkerPerfMaskUncName($State, [string]$Kind, [string]$Name) {
    # A share or printer name, then the server of its UNC path (\\server\...) when it has one.
    Add-WorkerPerfMaskName $State $Kind $Name
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $m = [regex]::Match($Name.Trim(), '^\\\\([^\\]+)\\')
    if ($m.Success) { Add-WorkerPerfMaskHost $State $m.Groups[1].Value }
}

function Test-WorkerPerfMaskVirtualDomain($State, [string]$Domain) {
    # $true for the domain part of a virtual or built-in account (nonPersonDomains: NT SERVICE, Window Manager ...).
    if ([string]::IsNullOrEmpty($Domain)) { return $false }
    foreach ($p in @(Get-WorkerPerfField $State.EventConfig 'NonPersonDomains')) {
        if ($null -ne $p -and (Test-WorkerPerfAccountPattern $Domain $p)) { return $true }
    }
    return $false
}

function Add-WorkerPerfMaskAccount($State, [string]$Account, [string]$Domain, [bool]$CheckPerson) {
    # An account name "<domain>\<name>", "<name>@<domain>" or "<name>": an account SID gives a sid, else the name gives
    # the user and its domain part (else -Domain) the domain. -CheckPerson (accounts from events and paths): an account
    # whose domain part is virtual (nonPersonDomains) or whose name is not a person (nonPersonAccounts: SYSTEM, DWM-1 ...)
    # gives neither user nor domain, except a computer account NAME$, which gives the server NAME and the domain.
    if ([string]::IsNullOrWhiteSpace($Account)) { return }
    $a = $Account.Trim()
    $name = $a
    $dom = $Domain
    $cut = $a.LastIndexOf('\')
    $at = $a.LastIndexOf('@')
    if ($cut -ge 0) { $name = $a.Substring($cut + 1); if ($cut -gt 0) { $dom = $a.Substring(0, $cut) } }
    elseif ($at -gt 0 -and $at -lt $a.Length - 1) { $name = $a.Substring(0, $at); $dom = $a.Substring($at + 1) }
    if ($script:WorkerPerfMaskSid.IsMatch($name)) { Add-WorkerPerfMaskName $State 'sid' $name; return }
    if (-not $CheckPerson) { Add-WorkerPerfMaskName $State 'user' $name }
    elseif (Test-WorkerPerfMaskVirtualDomain $State $dom) { return }
    elseif (Test-WorkerPerfEventPersonUser $name $State.EventConfig) { Add-WorkerPerfMaskName $State 'user' $name }
    elseif ($name.Length -gt 1 -and $name.EndsWith('$')) { Add-WorkerPerfMaskHost $State $name.Substring(0, $name.Length - 1) }
    else { return }
    Add-WorkerPerfMaskName $State 'domain' $dom
}

function Add-WorkerPerfMaskPatternNames($State, [string]$Text, [System.Text.RegularExpressions.Regex]$Patterns) {
    # The names the fixed patterns find in a text, in their order in the text.
    if ([string]::IsNullOrEmpty($Text)) { return }
    foreach ($m in $Patterns.Matches($Text)) {
        if ($m.Groups['sid'].Success) { Add-WorkerPerfMaskName $State 'sid' $m.Groups['sid'].Value }
        elseif ($m.Groups['unc'].Success) {
            if ($m.Groups['share'].Success) { Add-WorkerPerfMaskName $State 'share' ($m.Groups['unc'].Value) }
            Add-WorkerPerfMaskHost $State $m.Groups['server'].Value
        }
        elseif ($m.Groups['upm'].Success) { Add-WorkerPerfMaskAccount $State $m.Groups['folder'].Value '' $true }
        elseif ($m.Groups['drive'].Success) {
            $folder = $m.Groups['folder'].Value
            $plain = @($script:WorkerPerfMaskProfileFolders | Where-Object { [string]::Equals($_, $folder, [StringComparison]::OrdinalIgnoreCase) })
            if ($plain.Count -eq 0) { Add-WorkerPerfMaskAccount $State $folder '' $true }
        }
        elseif ($m.Groups['ip'].Success) { Add-WorkerPerfMaskName $State 'address' $m.Groups['ip'].Value }
    }
}

function New-WorkerPerfMask {
    # The names of a whole capture (never a time cut, so every report of one capture uses the same replacements) and their
    # replacement names. Files are read in a fixed order, each from its first line on; the order of first appearance
    # decides the numbers. The numbers do not depend on the level: Personen keeps the numbers of Alles.
    # Returns @{ Level; Entries = @{ Kind; Name; Replacement }[] of the level, in order of first appearance;
    # Protected = string[] of names that must stay (process, service, application, module, driver, endpoint and role names);
    # Lookup = lower-case name -> replacement; Regex = one pattern of all names of the level, longer before shorter,
    # whole names only, without regard to case ($null without names) }.
    # -EventConfig: from Read-WorkerPerfEventConfig (NonPersonAccounts, NonPersonDomains); without it the built-in lists.
    param([string]$Path, [ValidateSet('Personen', 'Alles')][string]$Level, [hashtable]$Texts, [string[]]$RoleLabels = @(), $EventConfig = $null)
    if ($null -eq $EventConfig) {
        $EventConfig = @{ NonPersonAccounts = $script:WorkerPerfDefaultNonPersonAccounts; NonPersonDomains = $script:WorkerPerfDefaultNonPersonDomains }
    }
    $st = @{ Seen = @{}; Records = (New-Object System.Collections.Generic.List[object])
        Protected = (New-Object System.Collections.Generic.List[string]); ProtectedSeen = @{}; EventConfig = $EventConfig }

    # (1) meta.json: the worker and the endpoints' hosts
    $metaPath = Join-Path $Path 'meta.json'
    if (-not (Test-Path -LiteralPath $metaPath) -and (Test-Path -LiteralPath ($metaPath + '.tmp'))) { $metaPath = $metaPath + '.tmp' }
    $meta = $null
    if (Test-Path -LiteralPath $metaPath) { $meta = ConvertFrom-WorkerPerfJsonFile $metaPath }
    Add-WorkerPerfMaskHost $st ([string](Get-WorkerPerfField $meta 'Computer'))
    $endpoints = @(Get-WorkerPerfField $meta 'Endpoints' | Where-Object { $null -ne $_ })
    foreach ($e in $endpoints) { Add-WorkerPerfMaskHost $st ([string](Get-WorkerPerfField $e 'Host')) }

    # (2) sessions.csv (the session's user as it is, without the check for accounts that are not persons)
    $winStations = New-Object System.Collections.Generic.List[string]
    foreach ($r in @(Get-WorkerPerfMaskRows $Path 'sessions.csv' @('User', 'Domain', 'ClientName', 'WinStation'))) {
        Add-WorkerPerfMaskAccount $st $r[0] $r[1] $false
        Add-WorkerPerfMaskName $st 'client' $r[2]
        $winStations.Add($r[3])
    }
    # (2a) citrix.csv: an ICA instance "<WinStation> (<domain>\<user>)" or "<WinStation> (<user>)" names its user
    foreach ($r in @(Get-WorkerPerfMaskRows $Path 'citrix.csv' @('Instance'))) {
        $m = [regex]::Match($r[0], '^(.+?)\s*\(([^()]*)\)\s*$')
        if ($m.Success) { Add-WorkerPerfMaskAccount $st $m.Groups[2].Value '' $false }
    }
    # (3) shares.csv, (4) volumes.csv
    foreach ($r in @(Get-WorkerPerfMaskRows $Path 'shares.csv' @('Share'))) { Add-WorkerPerfMaskUncName $st 'share' $r[0] }
    $volumes = @(Get-WorkerPerfMaskRows $Path 'volumes.csv' @('Volume', 'Backing'))
    foreach ($r in $volumes) { Add-WorkerPerfMaskUncName $st 'share' $r[1] }
    # (5) probes.csv
    foreach ($r in @(Get-WorkerPerfMaskRows $Path 'probes.csv' @('Host'))) { Add-WorkerPerfMaskHost $st $r[0] }

    # (6) events.csv, then events_before.csv (each ordered by time, as the reader gives them)
    $events = New-Object System.Collections.Generic.List[object]
    foreach ($file in 'events.csv', 'events_before.csv') {
        foreach ($ev in @(Read-WorkerPerfEventCsv $Path $file)) {
            $events.Add($ev)
            Add-WorkerPerfMaskAccount $st ([string]$ev['User']) '' $true
            Add-WorkerPerfMaskUncName $st 'printer' ([string]$ev['Printer'])
            if ($ev['Group'] -eq 'fileserver') { Add-WorkerPerfMaskHost $st ([string]$ev['Object']) }
        }
    }
    # (7) printqueues.csv
    foreach ($r in @(Get-WorkerPerfMaskRows $Path 'printqueues.csv' @('Queue'))) { Add-WorkerPerfMaskUncName $st 'printer' $r[0] }

    # (8) fixed patterns: procinfo.csv Path, volumes.csv Volume and Backing, sessions.csv WinStation, the name fields of
    # the events (User, Printer, Object; not Text: it never reaches a masked report), then with addresses the free texts
    # of meta.json (source details and error messages)
    $procs = @(Get-WorkerPerfMaskRows $Path 'procinfo.csv' @('Name', 'Path', 'Services'))
    $pathTexts = New-Object System.Collections.Generic.List[string]
    foreach ($r in $procs) { $pathTexts.Add($r[1]) }
    foreach ($r in $volumes) { $pathTexts.Add($r[0]); $pathTexts.Add($r[1]) }
    $pathTexts.AddRange($winStations)
    foreach ($ev in $events) { foreach ($c in 'User', 'Printer', 'Object') { $pathTexts.Add([string]$ev[$c]) } }
    foreach ($t in $pathTexts) { Add-WorkerPerfMaskPatternNames $st $t $script:WorkerPerfMaskPathPatterns }
    $freeTexts = New-Object System.Collections.Generic.List[string]
    $sources = Get-WorkerPerfField $meta 'Sources'
    if ($null -ne $sources) { foreach ($p in $sources.PSObject.Properties) { $freeTexts.Add([string](Get-WorkerPerfField $p.Value 'Detail')) } }
    $errors = Get-WorkerPerfField $meta 'SourceErrors'
    if ($null -ne $errors) { foreach ($p in $errors.PSObject.Properties) { $freeTexts.Add([string](Get-WorkerPerfField $p.Value 'FirstMessage')) } }
    $freeTexts.Add([string](Get-WorkerPerfField $meta 'EndMessage'))
    foreach ($t in $freeTexts) { Add-WorkerPerfMaskPatternNames $st $t $script:WorkerPerfMaskTextPatterns }

    # names that stay
    foreach ($r in $procs) {
        Add-WorkerPerfMaskProtected $st $r[0]
        foreach ($s in $r[2].Split(';')) { Add-WorkerPerfMaskProtected $st $s }
    }
    foreach ($ev in $events) { foreach ($c in 'App', 'Module', 'Service', 'Driver') { Add-WorkerPerfMaskProtected $st ([string]$ev[$c]) } }
    foreach ($d in @(Read-WorkerPerfPrintDrivers $Path)) { Add-WorkerPerfMaskProtected $st $d.Name; Add-WorkerPerfMaskProtected $st $d.Manufacturer }
    foreach ($e in $endpoints) { Add-WorkerPerfMaskProtected $st ([string](Get-WorkerPerfField $e 'Name')); Add-WorkerPerfMaskProtected $st ([string](Get-WorkerPerfField $e 'Role')) }
    foreach ($l in $RoleLabels) { Add-WorkerPerfMaskProtected $st $l }

    # numbers per kind in the order of the names (whatever the level), then the level's kinds
    $numbers = @{}
    $all = New-Object System.Collections.Generic.List[object]
    foreach ($rec in $st.Records) {
        $no = 1
        if ($numbers.ContainsKey($rec.Kind)) { $no = [int]$numbers[$rec.Kind] + 1 }
        $numbers[$rec.Kind] = $no
        $all.Add(@{ Kind = $rec.Kind; Name = $rec.Name; Replacement = ($Texts['mask.' + $rec.Kind] -f $no) })
    }
    $kinds = $script:WorkerPerfMaskLevelKinds[$Level]
    $entries = @($all | Where-Object { $kinds -contains $_.Kind })
    $lookup = @{}
    foreach ($e in $entries) { $lookup[$e.Name.ToLowerInvariant()] = $e.Replacement }
    $regex = $null
    if ($entries.Count -gt 0) {
        # longer names first (then ordinal), so that a short name never cuts a longer one; whole names: no letter or
        # digit directly before or after
        $names = [string[]]@($entries | ForEach-Object { $_.Name })
        [Array]::Sort($names, [Comparison[string]] { param($a, $b)
                if ($a.Length -ne $b.Length) { return $b.Length - $a.Length }
                return [string]::CompareOrdinal($a, $b) })
        $alt = [string]::Join('|', [string[]]@($names | ForEach-Object { [regex]::Escape($_) }))
        $regex = New-Object System.Text.RegularExpressions.Regex ('(?<![\p{L}\p{N}])(?:' + $alt + ')(?![\p{L}\p{N}])'), 'IgnoreCase, CultureInvariant'
    }
    return @{ Level = $Level; Entries = $entries; Protected = [string[]]$st.Protected.ToArray(); Lookup = $lookup; Regex = $regex }
}
