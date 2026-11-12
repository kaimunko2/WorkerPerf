#Requires -Version 5.1
# WorkerPerf report masking: collects the names of a whole capture and assigns their replacement names (definitions only).
# Requires WorkerPerf.Common.ps1, WorkerPerf.Load.ps1 (Open-WorkerPerfCsvReader), WorkerPerf.EventConfig.ps1 (default
# list of accounts that are not persons) and WorkerPerf.Events.ps1 (event and print driver readers).
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
# Fixed patterns in path and instance texts, scanned left to right: an account SID, the server of a UNC path (not the
# device prefixes \\?\ and \\.\), an IPv4 address that is not part of a longer dotted number (a version such as
# 8.2.0.114 inside 1.8.2.0.114 is not taken), and the user of a Citrix UPM mount path (C:\Users\<user>_UPM_local\...).
$script:WorkerPerfMaskPatterns = New-Object System.Text.RegularExpressions.Regex (
    '(?<sid>(?<![\w-])S-1-5-21-\d+-\d+-\d+-\d+(?![\w-]))' +
    '|\\\\(?<unc>[^\\/\s,;"?.*:|<>][^\\/\s,;"*:|<>]*)\\' +
    '|(?<ip>(?<![\d.])' + $script:WorkerPerfMaskIpv4Text + '(?![\d.]))' +
    '|\\Users\\(?<upm>[^\\]+)_UPM_local(?=\\|$)'), 'IgnoreCase'

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
    # Takes a name once (without regard to case), in the spelling of its first appearance, with the next number of its
    # kind; an empty name and a name already taken (of whatever kind) are passed over.
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $n = $Name.Trim()
    $key = $n.ToLowerInvariant()
    if ($State.Seen.ContainsKey($key)) { return }
    $State.Seen[$key] = $true
    $no = 1
    if ($State.Numbers.ContainsKey($Kind)) { $no = [int]$State.Numbers[$Kind] + 1 }
    $State.Numbers[$Kind] = $no
    $State.Entries.Add(@{ Kind = $Kind; Name = $n; Replacement = ($State.Texts['mask.' + $Kind] -f $no) })
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
    # A host: an IPv4 address, else a server name (leading backslashes of an SMB server name dropped).
    if ([string]::IsNullOrWhiteSpace($HostName)) { return }
    $h = $HostName.Trim().TrimStart('\')
    if ($script:WorkerPerfMaskIpv4.IsMatch($h)) { Add-WorkerPerfMaskName $State 'address' $h }
    else { Add-WorkerPerfMaskName $State 'server' $h }
}

function Add-WorkerPerfMaskUncName($State, [string]$Kind, [string]$Name) {
    # A share or printer name, then the server of its UNC path (\\server\...) when it has one.
    Add-WorkerPerfMaskName $State $Kind $Name
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $m = [regex]::Match($Name.Trim(), '^\\\\([^\\]+)\\')
    if ($m.Success) { Add-WorkerPerfMaskHost $State $m.Groups[1].Value }
}

function Add-WorkerPerfMaskAccount($State, [string]$Account, [string]$Domain) {
    # An account name, with or without domain part: a person's account gives its user name (without domain), an
    # account SID gives a sid, a computer account (NAME$) gives the server NAME. Accounts that are not persons
    # (nonPersonAccounts: SYSTEM, LOCAL SERVICE, DWM-1 ...) give nothing, their domain part (NT AUTHORITY, Window Manager)
    # neither. The domain is the account's own domain part, else -Domain.
    if ([string]::IsNullOrWhiteSpace($Account)) { return }
    $a = $Account.Trim()
    $cut = $a.LastIndexOf('\')
    $name = $a.Substring($cut + 1)
    $dom = $Domain
    if ($cut -gt 0) { $dom = $a.Substring(0, $cut) }
    if ($script:WorkerPerfMaskSid.IsMatch($name)) { Add-WorkerPerfMaskName $State 'sid' $name; return }
    if (Test-WorkerPerfEventPersonUser $name $State.EventConfig) { Add-WorkerPerfMaskName $State 'user' $name }
    elseif ($name.Length -gt 1 -and $name.EndsWith('$')) { Add-WorkerPerfMaskHost $State $name.Substring(0, $name.Length - 1) }
    else { return }
    Add-WorkerPerfMaskName $State 'domain' $dom
}

function Add-WorkerPerfMaskPatternNames($State, [string]$Text) {
    # The names the fixed patterns find in a text, in their order in the text.
    if ([string]::IsNullOrEmpty($Text)) { return }
    foreach ($m in $script:WorkerPerfMaskPatterns.Matches($Text)) {
        if ($m.Groups['sid'].Success) { Add-WorkerPerfMaskName $State 'sid' $m.Groups['sid'].Value }
        elseif ($m.Groups['unc'].Success) { Add-WorkerPerfMaskHost $State $m.Groups['unc'].Value }
        elseif ($m.Groups['ip'].Success) { Add-WorkerPerfMaskName $State 'address' $m.Groups['ip'].Value }
        elseif ($m.Groups['upm'].Success) { Add-WorkerPerfMaskAccount $State $m.Groups['upm'].Value '' }
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
    # -EventConfig: from Read-WorkerPerfEventConfig (its NonPersonAccounts); without it the built-in list applies.
    param([string]$Path, [ValidateSet('Personen', 'Alles')][string]$Level, [hashtable]$Texts, [string[]]$RoleLabels = @(), $EventConfig = $null)
    if ($null -eq $EventConfig) { $EventConfig = @{ NonPersonAccounts = $script:WorkerPerfDefaultNonPersonAccounts } }
    $st = @{ Seen = @{}; Numbers = @{}; Entries = (New-Object System.Collections.Generic.List[object]); Texts = $Texts
        Protected = (New-Object System.Collections.Generic.List[string]); ProtectedSeen = @{}; EventConfig = $EventConfig }
    $patternTexts = New-Object System.Collections.Generic.List[string]

    # (1) meta.json: the worker and the endpoints' hosts
    $metaPath = Join-Path $Path 'meta.json'
    if (-not (Test-Path -LiteralPath $metaPath) -and (Test-Path -LiteralPath ($metaPath + '.tmp'))) { $metaPath = $metaPath + '.tmp' }
    $meta = $null
    if (Test-Path -LiteralPath $metaPath) { $meta = ConvertFrom-WorkerPerfJsonFile $metaPath }
    Add-WorkerPerfMaskHost $st ([string](Get-WorkerPerfField $meta 'Computer'))
    $endpoints = @(Get-WorkerPerfField $meta 'Endpoints' | Where-Object { $null -ne $_ })
    foreach ($e in $endpoints) { Add-WorkerPerfMaskHost $st ([string](Get-WorkerPerfField $e 'Host')) }

    # (2) sessions.csv
    $winStations = New-Object System.Collections.Generic.List[string]
    foreach ($r in @(Get-WorkerPerfMaskRows $Path 'sessions.csv' @('User', 'Domain', 'ClientName', 'WinStation'))) {
        Add-WorkerPerfMaskAccount $st $r[0] $r[1]
        Add-WorkerPerfMaskName $st 'client' $r[2]
        $winStations.Add($r[3])
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
            Add-WorkerPerfMaskAccount $st ([string]$ev['User']) ''
            Add-WorkerPerfMaskUncName $st 'printer' ([string]$ev['Printer'])
            if ($ev['Group'] -eq 'fileserver') { Add-WorkerPerfMaskHost $st ([string]$ev['Object']) }
        }
    }
    # (7) printqueues.csv
    foreach ($r in @(Get-WorkerPerfMaskRows $Path 'printqueues.csv' @('Queue'))) { Add-WorkerPerfMaskUncName $st 'printer' $r[0] }

    # (8) fixed patterns: procinfo.csv Path, volumes.csv Volume and Backing, sessions.csv WinStation, the name fields of
    # the events (User, Printer, Object; not Text: it never reaches a masked report, and its version numbers look like
    # addresses), and the free texts of meta.json (source details and error messages)
    $procs = @(Get-WorkerPerfMaskRows $Path 'procinfo.csv' @('Name', 'Path', 'Services'))
    foreach ($r in $procs) { $patternTexts.Add($r[1]) }
    foreach ($r in $volumes) { $patternTexts.Add($r[0]); $patternTexts.Add($r[1]) }
    $patternTexts.AddRange($winStations)
    foreach ($ev in $events) { foreach ($c in 'User', 'Printer', 'Object') { $patternTexts.Add([string]$ev[$c]) } }
    $sources = Get-WorkerPerfField $meta 'Sources'
    if ($null -ne $sources) { foreach ($p in $sources.PSObject.Properties) { $patternTexts.Add([string](Get-WorkerPerfField $p.Value 'Detail')) } }
    $errors = Get-WorkerPerfField $meta 'SourceErrors'
    if ($null -ne $errors) { foreach ($p in $errors.PSObject.Properties) { $patternTexts.Add([string](Get-WorkerPerfField $p.Value 'FirstMessage')) } }
    $patternTexts.Add([string](Get-WorkerPerfField $meta 'EndMessage'))
    foreach ($t in $patternTexts) { Add-WorkerPerfMaskPatternNames $st $t }

    # names that stay
    foreach ($r in $procs) {
        Add-WorkerPerfMaskProtected $st $r[0]
        foreach ($s in $r[2].Split(';')) { Add-WorkerPerfMaskProtected $st $s }
    }
    foreach ($ev in $events) { foreach ($c in 'App', 'Module', 'Service', 'Driver') { Add-WorkerPerfMaskProtected $st ([string]$ev[$c]) } }
    foreach ($d in @(Read-WorkerPerfPrintDrivers $Path)) { Add-WorkerPerfMaskProtected $st $d.Name; Add-WorkerPerfMaskProtected $st $d.Manufacturer }
    foreach ($e in $endpoints) { Add-WorkerPerfMaskProtected $st ([string](Get-WorkerPerfField $e 'Name')); Add-WorkerPerfMaskProtected $st ([string](Get-WorkerPerfField $e 'Role')) }
    foreach ($l in $RoleLabels) { Add-WorkerPerfMaskProtected $st $l }

    $kinds = $script:WorkerPerfMaskLevelKinds[$Level]
    $entries = @($st.Entries | Where-Object { $kinds -contains $_.Kind })
    $lookup = @{}
    foreach ($e in $entries) { $lookup[$e.Name.ToLowerInvariant()] = $e.Replacement }
    $regex = $null
    if ($entries.Count -gt 0) {
        # longer names first (then by name, ordinal), so that a short name never cuts a longer one; whole names: no
        # letter or digit directly before or after
        $names = [string[]]@($entries | ForEach-Object { $_.Name })
        [Array]::Sort($names, [Comparison[string]] { param($a, $b)
                if ($a.Length -ne $b.Length) { return $b.Length - $a.Length }
                return [string]::CompareOrdinal($a, $b) })
        $alt = [string]::Join('|', [string[]]@($names | ForEach-Object { [regex]::Escape($_) }))
        $regex = New-Object System.Text.RegularExpressions.Regex ('(?<![\p{L}\p{N}])(?:' + $alt + ')(?![\p{L}\p{N}])'), 'IgnoreCase, CultureInvariant'
    }
    return @{ Level = $Level; Entries = $entries; Protected = [string[]]$st.Protected.ToArray(); Lookup = $lookup; Regex = $regex }
}
