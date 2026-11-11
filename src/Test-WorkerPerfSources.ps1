#Requires -Version 5.1
<#
.SYNOPSIS
    Probes which data sources WorkerPerf can use on a Citrix multi-session VDA.

.DESCRIPTION
    Standalone script: copy this single file to a worker and run it once in an elevated console.
    Every check runs on its own; a failing check is reported and the others continue.
    The script only reads; it changes nothing on the system.

    Results are shown as a table and written as JSON to vda-probe_<yyyyMMdd-HHmmss>.json.
    Names are masked in every text of the file: user, domain, client and computer names, account
    SIDs and server names. Endpoints are reported without host name or address, and neither the
    file name nor the content carries the name of the worker. The checks keep their texts as
    read; the result is masked once, as a whole, after the last check. The sessions are read at
    the start, after every check and before that masking, so a user who logs on during the run
    is masked as well. If the names cannot be determined, or an active session delivers no user
    name, the script stops without writing a file.
    The masking knows the names of its sources and a few fixed patterns. It cannot recognise a
    display name, an organisation name, or a server that appears in no UNC path: look through
    the file before passing it on (docs/vda-probe/README.md).

    Performance counters are read through System.Diagnostics.PerformanceCounterCategory with
    English names (language neutral). For comparison the matching Win32_PerfRawData_* CIM
    class names are listed as well.

.PARAMETER OutFile
    Folder or .json file for the result. A folder (existing, or any path not ending in .json)
    receives the default file name. Default: current folder.

.PARAMETER EndpointFile
    Optional JSON file { "endpoints": [ { "name", "host", "port", "role" } ] } (see
    endpoints.example.json). The TCP connect time to each endpoint is measured.

.PARAMETER InputSeconds
    Number of 1 s samples of 'User Input Delay per Session'; half as many 2 s samples follow.

.PARAMETER ListChecks
    Only list the checks (Id, Signals, Title) without touching the system.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-WorkerPerfSources.ps1 -OutFile C:\Temp
#>
[CmdletBinding()]
param(
    [string]$OutFile,
    [string]$EndpointFile,
    [ValidateRange(2, 600)][int]$InputSeconds = 20,
    [switch]$ListChecks
)

# Where AppLocker or WDAC puts the console into ConstrainedLanguage, Add-Type and .NET types fail with errors that
# do not name the cause. This check uses nothing that the restricted mode forbids.
$languageMode = "$($ExecutionContext.SessionState.LanguageMode)"
if ($languageMode -ne 'FullLanguage') {
    throw "WorkerPerf benoetigt den PowerShell-Sprachmodus FullLanguage; aktiv ist $languageMode. AppLocker oder WDAC schraenkt diese Konsole ein: bitte eine uneingeschraenkte administrative Konsole verwenden."
}

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
# The masking applies more fixed patterns to every text than the regex cache holds by default.
if ([regex]::CacheSize -lt 64) { [regex]::CacheSize = 64 }

#region ---------- masking --------------------------------------------------------------------

function New-WorkerPerfNameMask([string[]]$Users, [string[]]$Domains = @(), [string[]]$Clients = @(), [string[]]$Computers = @()) {
    # The lookup (name -> replacement) and the pattern for a set of names, built once and used for every text:
    # building them per text costs several milliseconds with the names of a full worker.
    # While a text is masked, a replacement is written between two private-use characters instead of < and >, so
    # that no rule and no name (a user called "user" or "sid") can match inside a replacement made before.
    $open = [string][char]0xE000
    $close = [string][char]0xE001
    $mask = @{
        User = $open + 'user' + $close; Server = $open + 'server' + $close; Client = $open + 'client' + $close
        Domain = $open + 'domain' + $close; Sid = $open + 'sid' + $close; Regex = $null; Evaluator = $null
    }
    $token = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($n in @($Users)) { if (-not [string]::IsNullOrEmpty($n) -and -not $token.ContainsKey($n)) { $token[$n] = $mask.User } }
    foreach ($n in @($Computers)) { if (-not [string]::IsNullOrEmpty($n) -and -not $token.ContainsKey($n)) { $token[$n] = $mask.Server } }
    foreach ($n in @($Clients)) { if (-not [string]::IsNullOrEmpty($n) -and -not $token.ContainsKey($n)) { $token[$n] = $mask.Client } }
    foreach ($n in @($Domains)) { if (-not [string]::IsNullOrEmpty($n) -and -not $token.ContainsKey($n)) { $token[$n] = $mask.Domain } }
    if ($token.Count -gt 0) {
        # One pass with an alternation, longest name first.
        $names = @($token.Keys | Sort-Object -Property { $_.Length } -Descending)
        $alternatives = ($names | ForEach-Object { [regex]::Escape($_) }) -join '|'
        $pattern = '(?<![\p{L}\p{N}\uE000])(?:' + $alternatives + ')(?![\p{L}\p{N}\uE001])'
        $mask.Regex = New-Object System.Text.RegularExpressions.Regex ($pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        # The pattern ignores case by the rules of the culture, the lookup by ordinal rules: a match the lookup does
        # not know is still a name and becomes <user>.
        $fallback = $mask.User
        $mask.Evaluator = [System.Text.RegularExpressions.MatchEvaluator] {
            param($m)
            $found = $null
            if ($token.TryGetValue($m.Value, [ref]$found)) { $found } else { $fallback }
        }.GetNewClosure()
    }
    return $mask
}

function Hide-WorkerPerfMaskedText([string]$Text, $Mask) {
    # Masks one text. Rules that need no list come first: account SIDs become <sid>, the name that container folders
    # and files carry beside it becomes <user>, UNC server names become <server>. Then the names of the lists
    # (case-insensitive, whole names only): user names become <user>, computer and server names <server>, client
    # names <client>, domain names <domain>. Last, the domain part beside a masked user becomes <domain>.
    # A text is masked once, when all names are known: masking with a part of the names can cut a longer name
    # apart (anna.meier -> <user>.meier while only anna is known), and no later pass can repair that.
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    # the two private-use characters are reserved for the replacements below; a text that brings its own loses them
    $result = $Text.Replace([string][char]0xE000, '').Replace([string][char]0xE001, '')
    # account SIDs of domain and Entra ID accounts (well-known SIDs such as S-1-5-18 stay), then the user name that
    # container folders carry beside the SID (<sid>_name, name_<sid>) and container files carry after their prefix
    # (Profile_name.vhdx, ODFC_name.vhdx): these hold for users that are in no list.
    $result = [regex]::Replace($result, '(?i)(?<![\p{L}\p{N}])S-1-(?:5-21|12-1)(?:-[0-9]+){3,4}(?![\p{L}\p{N}])', $Mask.Sid)
    $result = [regex]::Replace($result, '(?<=\uE000sid\uE001_)[^\\/\s''"<>\uE000\uE001]+', $Mask.User)
    $result = [regex]::Replace($result, '(?<=^|[\\/\s''"<>\uE001])[^\\/\s''"<>\uE000\uE001]+(?=_\uE000sid\uE001)', $Mask.User)
    $result = [regex]::Replace($result, '(?i)(?<=^|[\\/\s''"])(Profile|ODFC)_[^\\/\s''"<>\uE000\uE001]+?(\.vhdx?)(?![\p{L}\p{N}])', ('${1}_' + $Mask.User + '${2}'))
    # \\server\... at the start or after a non-word character (e.g. quoted in an error message); device paths such
    # as \\?\Volume{...} and \\.\ are kept. Then the long forms \\?\UNC\server\, \??\UNC\server\ and the device
    # paths of the redirector, \Device\Mup\server\ and \Device\LanmanRedirector\;X:...\server\.
    $result = [regex]::Replace($result, '(?<![\p{L}\p{N}_\\])\\\\(?![?.]\\)[^\\\s''"]+', ('\\' + $Mask.Server))
    $result = [regex]::Replace($result, '(?i)(\\\\\?\\UNC\\|\\\?\?\\UNC\\)[^\\\s''"<>\uE000\uE001]+', ('${1}' + $Mask.Server))
    $result = [regex]::Replace($result, '(?i)(\\Device\\(?:Mup|LanmanRedirector)\\(?:;[^\\\s''"]*\\)*)[^\\\s''";<>\uE000\uE001][^\\\s''"<>\uE000\uE001]*', ('${1}' + $Mask.Server))
    # the names of the lists
    if ($null -ne $Mask.Regex) { $result = $Mask.Regex.Replace($result, $Mask.Evaluator) }
    # the domain part beside a user: folder <user>.DOMAIN\ (profile stores), DOMAIN\<user>, <user>@domain
    $result = [regex]::Replace($result, '(?<=\uE000user\uE001\.)[\p{L}\p{N}_-]+(?=[\\/])', $Mask.Domain)
    $result = [regex]::Replace($result, '(?<=\uE000user\uE001@)[\p{L}\p{N}][\p{L}\p{N}.-]*', $Mask.Domain)
    $result = [regex]::Replace($result, '(?<![\p{L}\p{N}\\:._-])[\p{L}\p{N}_-]+(?=\\\uE000user\uE001)', $Mask.Domain)
    return $result.Replace([string][char]0xE000, '<').Replace([string][char]0xE001, '>')
}

function Hide-WorkerPerfName([string]$Text, [string[]]$Users, [string[]]$Domains = @(), [string[]]$Clients = @(), [string[]]$Computers = @()) {
    # One text with one set of names (see Hide-WorkerPerfMaskedText for the rules). The probe itself keeps the
    # pattern between texts (Hide-ProbeText).
    return Hide-WorkerPerfMaskedText -Text $Text -Mask (New-WorkerPerfNameMask -Users $Users -Domains $Domains -Clients $Clients -Computers $Computers)
}

# The names to mask. They only grow while the probe runs (Add-ProbeMaskNames); the patterns are built from them on the
# next text and kept until a name is added.
$script:ProbeUsers = @()
$script:ProbeDomains = @()
$script:ProbeClients = @()
$script:ProbeComputers = @()
$script:ProbeMask = $null
$script:ProbeMaskNoUsers = $null

function Join-ProbeNames([string[]]$Known, [string[]]$More) {
    # $Known plus every name of $More that is not among them yet (case-insensitive); empty names are dropped.
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $list = New-Object 'System.Collections.Generic.List[string]'
    foreach ($n in @($Known) + @($More)) {
        if (-not [string]::IsNullOrEmpty($n) -and $seen.Add($n)) { $list.Add($n) }
    }
    return $list.ToArray()
}

function Add-ProbeMaskNames([string[]]$Users = @(), [string[]]$Domains = @(), [string[]]$Clients = @(), [string[]]$Computers = @()) {
    # Adds names to the lists to mask and returns how many were new. A name stays in its list for the whole run, so
    # a user who logged off meanwhile is still masked.
    $before = @($script:ProbeUsers).Count + @($script:ProbeDomains).Count + @($script:ProbeClients).Count + @($script:ProbeComputers).Count
    $script:ProbeUsers = @(Join-ProbeNames $script:ProbeUsers $Users)
    $script:ProbeDomains = @(Join-ProbeNames $script:ProbeDomains $Domains)
    $script:ProbeClients = @(Join-ProbeNames $script:ProbeClients $Clients)
    $script:ProbeComputers = @(Join-ProbeNames $script:ProbeComputers $Computers)
    $added = @($script:ProbeUsers).Count + @($script:ProbeDomains).Count + @($script:ProbeClients).Count + @($script:ProbeComputers).Count - $before
    if ($added -gt 0) { $script:ProbeMask = $null; $script:ProbeMaskNoUsers = $null }
    return $added
}

function Hide-ProbeText([string]$Text) {
    if ($null -eq $script:ProbeMask) {
        $script:ProbeMask = New-WorkerPerfNameMask -Users $script:ProbeUsers -Domains $script:ProbeDomains -Clients $script:ProbeClients -Computers $script:ProbeComputers
    }
    return Hide-WorkerPerfMaskedText -Text $Text -Mask $script:ProbeMask
}

function Copy-ProbeValue($Value, [scriptblock]$Text, [int]$Depth = 0) {
    # Deep copy of a result in which every text has passed $Text, dictionary keys and property names included.
    # Numbers, booleans, enums, times and GUIDs stay as they are. Anything else that is neither a dictionary nor a
    # list is taken apart into its properties (also a value type such as a key/value pair), so that ConvertTo-Json
    # never serialises something that has not been through here.
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return (& $Text $Value) }
    if ($Value -is [char]) { return (& $Text ([string]$Value)) }
    if ($Value -is [ValueType]) {
        $type = $Value.GetType()
        if ($type.IsPrimitive -or $type.IsEnum -or $Value -is [decimal] -or $Value -is [datetime] -or $Value -is [System.DateTimeOffset] -or
            $Value -is [timespan] -or $Value -is [guid]) { return $Value }
    }
    if ($Depth -ge 16) { return (& $Text ([string]$Value)) }
    if ($Value -is [System.Collections.IDictionary]) {
        $copy = [ordered]@{}
        foreach ($entry in $Value.GetEnumerator()) {
            # keys become texts (JSON knows no others); two keys may read the same after masking: both entries are kept
            $base = & $Text ([string]$entry.Key)
            $key = $base
            $n = 1
            while ($copy.Contains($key)) { $n++; $key = '{0} ({1})' -f $base, $n }
            $copy.Add($key, (Copy-ProbeValue $entry.Value $Text ($Depth + 1)))
        }
        return $copy
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $list = New-Object 'System.Collections.Generic.List[object]'
        foreach ($item in $Value) { $list.Add((Copy-ProbeValue $item $Text ($Depth + 1))) }
        return , $list.ToArray()
    }
    $copy = [ordered]@{}
    foreach ($p in $Value.PSObject.Properties) {
        $v = $null
        try { $v = $p.Value } catch { $v = $null }
        $base = & $Text ([string]$p.Name)
        $key = $base
        $n = 1
        while ($copy.Contains($key)) { $n++; $key = '{0} ({1})' -f $base, $n }
        $copy.Add($key, (Copy-ProbeValue $v $Text ($Depth + 1)))
    }
    return $copy
}

function Protect-ProbeValue($Value) {
    # The one place where the result is masked: every text anywhere in it, with all names known at that moment.
    # The checks themselves keep their texts as they read them.
    return Copy-ProbeValue $Value { param($t) Hide-ProbeText $t }
}

function Get-ProbeTexts($Value) {
    # Every text of a result, dictionary keys included.
    $texts = New-Object 'System.Collections.Generic.List[string]'
    $null = Copy-ProbeValue $Value { param($t) $texts.Add($t); $t }
    return $texts.ToArray()
}

function Get-ProbeUncHosts([string[]]$Texts) {
    # The server names of the UNC paths in the given texts, in the forms the masking knows. Left out: what is no
    # server name (a path with doubled backslashes after a drive letter, a wildcard, localhost, a single character).
    $patterns = @(
        '(?<![\p{L}\p{N}_\\:])\\\\(?![?.]\\)([^\\\s''"<>]+)'
        '(?i)(?:\\\\\?\\UNC\\|\\\?\?\\UNC\\)([^\\\s''"<>]+)'
        '(?i)\\Device\\(?:Mup|LanmanRedirector)\\(?:;[^\\\s''"]*\\)*([^\\\s''";<>][^\\\s''"<>]*)'
    )
    $found = New-Object 'System.Collections.Generic.List[string]'
    foreach ($t in @($Texts)) {
        if ([string]::IsNullOrEmpty($t)) { continue }
        foreach ($p in $patterns) {
            foreach ($m in [regex]::Matches($t, $p)) {
                $name = $m.Groups[1].Value.TrimEnd('.', ',', ';', ':', ')', ']')
                if ($name.Length -ge 2 -and $name -ne 'localhost' -and $name -notmatch '[*?]') { $found.Add($name) }
            }
        }
    }
    return Join-ProbeNames @() $found.ToArray()
}

function Add-ProbeServerNames([string[]]$Hosts) {
    # Server names (from UNC paths, SMB share instances and the endpoint file) join the names to mask, so that they
    # are replaced in free text as well: the whole name, of a DNS name also its first label (unless that is a known
    # domain, as in a DFS root \\domain.tld\...), and the rest of the DNS name as a domain when it has more than one
    # label ("local" alone is a word, not a name). Returns how many names were new.
    $servers = New-Object 'System.Collections.Generic.List[string]'
    $domains = New-Object 'System.Collections.Generic.List[string]'
    foreach ($h in @($Hosts)) {
        if ([string]::IsNullOrEmpty($h)) { continue }
        $servers.Add($h)
        $dot = $h.IndexOf('.')
        if ($dot -gt 0 -and $dot -lt $h.Length - 1 -and $h -notmatch '^[0-9.]+$' -and -not $h.Contains(':')) {
            $label = $h.Substring(0, $dot)
            $rest = $h.Substring($dot + 1)
            $isDomain = @($script:ProbeDomains | Where-Object { [string]::Equals($_, $label, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
            if (-not $isDomain) { $servers.Add($label) }
            if ($rest.Contains('.')) { $domains.Add($rest) }
        }
    }
    return Add-ProbeMaskNames -Computers $servers.ToArray() -Domains $domains.ToArray()
}

function Add-ProbeShareServer([string]$Instance) {
    # Instances of 'SMB Client Shares' are named \server\share, with a single backslash, which no general rule can
    # tell from a device path such as \Device\HarddiskVolume3. Their server name joins the names to mask instead.
    $m = [regex]::Match($Instance, '^\\{1,2}([^\\]+)\\')
    if ($m.Success) { $null = Add-ProbeServerNames @($m.Groups[1].Value) }
}

function Test-ProbeUserInText([string]$Text) {
    # True when a known user name occurs in $Text (same matching rules as the masking).
    if ([string]::IsNullOrEmpty($Text)) { return $false }
    $with = Hide-ProbeText $Text
    if ($null -eq $script:ProbeMaskNoUsers) {
        $script:ProbeMaskNoUsers = New-WorkerPerfNameMask -Users @() -Domains $script:ProbeDomains -Clients $script:ProbeClients -Computers $script:ProbeComputers
    }
    $without = Hide-WorkerPerfMaskedText -Text $Text -Mask $script:ProbeMaskNoUsers
    return $with -ne $without
}

function Get-ProbeMaskNames([string[]]$SessionUsers, [string[]]$ProfilePaths, [string]$CurrentUser) {
    # Names to mask: WTS session users, the leaf names of user profile folders (which do not depend
    # on WTS and cover every user with a local profile) and the current user. A profile folder
    # such as C:\Users\mueller.KLINIK also yields the part before the first dot.
    $names = New-Object 'System.Collections.Generic.List[string]'
    foreach ($u in @($SessionUsers)) { if (-not [string]::IsNullOrEmpty($u)) { $names.Add($u) } }
    foreach ($p in @($ProfilePaths)) {
        if ([string]::IsNullOrEmpty($p)) { continue }
        $leaf = @($p -split '[\\/]' | Where-Object { $_ -ne '' })
        if ($leaf.Count -eq 0) { continue }
        $name = $leaf[$leaf.Count - 1]
        $names.Add($name)
        $dot = $name.IndexOf('.')
        if ($dot -gt 0) { $names.Add($name.Substring(0, $dot)) }
    }
    if (-not [string]::IsNullOrEmpty($CurrentUser)) { $names.Add($CurrentUser) }
    return $names.ToArray()
}

function Get-ProbeMaskDomains([string[]]$SessionDomains, [string]$UserDomain, [string]$UserDnsDomain, [string[]]$ProfilePaths) {
    # Domain names to mask: the domain of every WTS session, USERDOMAIN and USERDNSDOMAIN of the current user and the
    # part after the dot of a profile folder such as C:\Users\mueller.KLINIK (not a counter such as .000).
    $names = New-Object 'System.Collections.Generic.List[string]'
    foreach ($d in @($SessionDomains) + @($UserDomain, $UserDnsDomain)) {
        if (-not [string]::IsNullOrEmpty($d) -and -not $names.Contains($d)) { $names.Add($d) }
    }
    foreach ($p in @($ProfilePaths)) {
        if ([string]::IsNullOrEmpty($p)) { continue }
        $leaf = @($p -split '[\\/]' | Where-Object { $_ -ne '' })
        if ($leaf.Count -eq 0) { continue }
        $parts = $leaf[$leaf.Count - 1].Split('.')
        for ($i = 1; $i -lt $parts.Length; $i++) {
            if ($parts[$i] -ne '' -and $parts[$i] -notmatch '^[0-9]+$' -and -not $names.Contains($parts[$i])) { $names.Add($parts[$i]) }
        }
    }
    return $names.ToArray()
}

function Get-ProbeMaskGap($Sessions, [bool]$WtsOk, [bool]$ProfilesOk) {
    # Empty when the names to mask are known well enough to write a result, else the reason (German).
    # An active session without a user name stops the result whatever the profile folders say: they do not prove
    # that the name of this user is among them (temporary profile, no local folder, folder named differently).
    if (-not $WtsOk -and -not $ProfilesOk) {
        return 'Benutzernamen fuer die Maskierung nicht ermittelbar (weder ueber die WTS-Schnittstelle noch ueber die Benutzerprofile)'
    }
    $unnamed = @(@($Sessions) | Where-Object { $null -ne $_ -and [string]$_.State -eq 'Active' -and [string]::IsNullOrEmpty([string]$_.User) })
    if ($unnamed.Count -gt 0) {
        return ('{0} aktive Sitzung(en) ohne Benutzernamen: die Namen dieser Benutzer liessen sich nicht maskieren. Bitte das Skript in einer administrativen Konsole starten' -f $unnamed.Count)
    }
    return ''
}

function Read-ProbeNames([scriptblock]$ReadSessions, [scriptblock]$ReadProfiles) {
    # One reading of the names to mask: the sessions (WTS) and, independent of WTS, the folders of the local user
    # profiles. Every name found joins the lists. Gap says why no result may be written (empty: nothing in the way).
    # The probe reads at its start and once more before it writes: sessions come and go while it runs.
    $r = @{ Sessions = @(); WtsError = ''; ProfilePaths = @(); ProfileError = ''; Gap = '' }
    $wtsFailure = $null
    $profileFailure = $null
    try { $r.Sessions = @(& $ReadSessions) } catch { $wtsFailure = $_ }
    try { $r.ProfilePaths = @(& $ReadProfiles | ForEach-Object { [string]$_ }) } catch { $profileFailure = $_ }
    $null = Add-ProbeMaskNames -Users (Get-ProbeMaskNames -SessionUsers @($r.Sessions | ForEach-Object { [string]$_.User }) -ProfilePaths $r.ProfilePaths -CurrentUser '') `
        -Domains (Get-ProbeMaskDomains -SessionDomains @($r.Sessions | ForEach-Object { [string]$_.Domain }) -UserDomain '' -UserDnsDomain '' -ProfilePaths $r.ProfilePaths) `
        -Clients @($r.Sessions | ForEach-Object { [string]$_.ClientName })
    if ($null -ne $wtsFailure) { $r.WtsError = Get-ProbeErrorText $wtsFailure; if ($r.WtsError -eq '') { $r.WtsError = 'unbekannter Fehler' } }
    if ($null -ne $profileFailure) { $r.ProfileError = Get-ProbeErrorText $profileFailure; if ($r.ProfileError -eq '') { $r.ProfileError = 'unbekannter Fehler' } }
    $r.Gap = Get-ProbeMaskGap -Sessions $r.Sessions -WtsOk ($null -eq $wtsFailure) -ProfilesOk ($null -eq $profileFailure)
    return $r
}

function Update-ProbeMaskFromSessions([scriptblock]$ReadSessions) {
    # Adds the user, domain and client names of the sessions that exist now. A reading that fails changes nothing:
    # the reading before the result is written decides whether a file may be written.
    try { $now = @(& $ReadSessions) } catch { return }
    $null = Add-ProbeMaskNames -Users @($now | ForEach-Object { [string]$_.User }) -Domains @($now | ForEach-Object { [string]$_.Domain }) `
        -Clients @($now | ForEach-Object { [string]$_.ClientName })
}

function Invoke-ProbeCatalogue($Catalogue, $Ctx, [scriptblock]$ReadSessions) {
    # Runs every check on its own; a failing check is reported and the others continue. The results keep their texts
    # as read: they are masked once, after the last check (Protect-ProbeValue). After each check the sessions are
    # read again, so that a user who logged on while it ran is in the lists by then.
    $results = New-Object 'System.Collections.Generic.List[object]'
    $n = 0
    foreach ($c in @($Catalogue)) {
        $n++
        Write-Host ('[{0,2}/{1}] {2} - {3}' -f $n, @($Catalogue).Count, $c.Id, $c.Title)
        $r = [ordered]@{ Id = $c.Id; Signals = [string[]]$c.Signals; Title = $c.Title; Ok = $false; Detail = ''; Data = $null }
        try {
            $out = @(& $c.Run $Ctx $c)[-1]
            if ($null -eq $out.Ok) { $r.Ok = $null } else { $r.Ok = [bool]$out.Ok }   # $null = skipped
            $r.Detail = [string]$out.Detail
            $r.Data = $out.Data
        }
        catch { $r.Detail = Get-ProbeErrorText $_ }
        Update-ProbeMaskFromSessions $ReadSessions
        $results.Add($r)
    }
    return $results.ToArray()                                  # plain output: callers wrap in @(...)
}

function Get-ProbeEndpointErrorClass($Exception) {
    # Short class of a failed connect: refused, timeout, dns or other. The exception text itself is never reported:
    # it can end with the address the host name resolved to.
    $e = $Exception
    while ($null -ne $e) {
        if ($e -is [System.Net.Sockets.SocketException]) {
            switch ($e.SocketErrorCode.ToString()) {
                'ConnectionRefused' { return 'refused' }
                'TimedOut' { return 'timeout' }
                'HostNotFound' { return 'dns' }
                'TryAgain' { return 'dns' }
                'NoData' { return 'dns' }
                'NoRecovery' { return 'dns' }
                default { return 'other' }
            }
        }
        $e = $e.InnerException
    }
    return 'other'
}

function Get-ProbeFileName([datetime]$Now) {
    # The name of the worker appears neither in the file name nor in the file.
    return 'vda-probe_{0}.json' -f $Now.ToString('yyyyMMdd-HHmmss', [Globalization.CultureInfo]::InvariantCulture)
}

#endregion

#region ---------- helpers --------------------------------------------------------------------

function Get-Prop($Object, [string]$Name) {
    # Tolerant property read: returns $null when the property does not exist.
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Get-ProbeErrorText($ErrorRecord) {
    $e = $ErrorRecord.Exception
    while ($null -ne $e.InnerException) { $e = $e.InnerException }
    # Messages may quote paths and names: like every other text they are masked when the result is written.
    return [string]$e.Message
}

function ConvertTo-ProbeNumber($Value) {
    if ($null -eq $Value) { return $null }
    $d = [double]$Value
    if ([double]::IsNaN($d) -or [double]::IsInfinity($d)) { return $null }
    return [Math]::Round($d, 6)
}

function Get-ProbeMs([System.Diagnostics.Stopwatch]$Stopwatch) {
    return [Math]::Round($Stopwatch.Elapsed.TotalMilliseconds, 1)
}

# Every CIM query ends after this time instead of blocking the probe on a loaded worker.
$script:ProbeCimTimeoutSec = 30
# Event counts are taken over at most this many events per log.
$script:ProbeMaxEvents = 1000

function Get-ProbeProcesses($Ctx) {
    if ($null -eq $Ctx.Processes) { $Ctx.Processes = @(Get-CimInstance -ClassName Win32_Process -OperationTimeoutSec $script:ProbeCimTimeoutSec -ErrorAction Stop) }
    return $Ctx.Processes
}

function Get-ProbeServices($Ctx) {
    if ($null -eq $Ctx.Services) { $Ctx.Services = @(Get-CimInstance -ClassName Win32_Service -OperationTimeoutSec $script:ProbeCimTimeoutSec -ErrorAction Stop) }
    return $Ctx.Services
}

function Get-ProbeFileInfo($Ctx, [string]$Path) {
    if ([string]::IsNullOrEmpty($Path)) { return @{ Company = ''; Description = '' } }
    if (-not $Ctx.FileInfo.ContainsKey($Path)) {
        $info = @{ Company = ''; Description = '' }
        try {
            $v = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
            $info.Company = [string]$v.CompanyName
            $info.Description = [string]$v.FileDescription
        }
        catch { $info.Description = '' }
        $Ctx.FileInfo[$Path] = $info
    }
    return $Ctx.FileInfo[$Path]
}

#endregion

#region ---------- native helpers (C# 5) -----------------------------------------------------

# Same WTS wrapper as Start-WorkerPerfCapture.ps1, in its own namespace so both can share a session.
$script:WtsSource = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace WorkerPerfProbe
{
    public class WtsSession
    {
        public int SessionId;
        public string State;
        public string WinStation;
        public string User;
        public string Domain;
        public string ClientName;
        public DateTime LogonTime;      // DateTime.MinValue = unknown
        public double IdleSec;          // -1 = unknown
    }

    public static class Wts
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct WTS_SESSION_INFO
        {
            public int SessionId;
            [MarshalAs(UnmanagedType.LPWStr)] public string pWinStationName;
            public int State;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct WTSINFO
        {
            public int State;
            public int SessionId;
            public int IncomingBytes;
            public int OutgoingBytes;
            public int IncomingFrames;
            public int OutgoingFrames;
            public int IncomingCompressedBytes;
            public int OutgoingCompressedBytes;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string WinStationName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 17)] public string Domain;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 21)] public string UserName;
            public long ConnectTime;
            public long DisconnectTime;
            public long LastInputTime;
            public long LogonTime;
            public long CurrentTime;
        }

        [DllImport("wtsapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool WTSEnumerateSessionsW(IntPtr hServer, int reserved, int version, out IntPtr ppSessionInfo, out int pCount);

        [DllImport("wtsapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool WTSQuerySessionInformationW(IntPtr hServer, int sessionId, int infoClass, out IntPtr ppBuffer, out int pBytesReturned);

        [DllImport("wtsapi32.dll")]
        private static extern void WTSFreeMemory(IntPtr pMemory);

        private static readonly string[] StateNames = { "Active", "Connected", "ConnectQuery", "Shadow", "Disconnected", "Idle", "Listen", "Reset", "Down", "Init" };

        private static string QueryString(int sessionId, int infoClass)
        {
            IntPtr buf; int bytes;
            if (!WTSQuerySessionInformationW(IntPtr.Zero, sessionId, infoClass, out buf, out bytes)) return "";
            try { return Marshal.PtrToStringUni(buf) ?? ""; }
            finally { WTSFreeMemory(buf); }
        }

        public static List<WtsSession> GetSessions()
        {
            List<WtsSession> result = new List<WtsSession>();
            IntPtr pInfo; int count;
            if (!WTSEnumerateSessionsW(IntPtr.Zero, 0, 1, out pInfo, out count))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            try
            {
                int size = Marshal.SizeOf(typeof(WTS_SESSION_INFO));
                for (int i = 0; i < count; i++)
                {
                    WTS_SESSION_INFO si = (WTS_SESSION_INFO)Marshal.PtrToStructure(new IntPtr(pInfo.ToInt64() + (long)i * size), typeof(WTS_SESSION_INFO));
                    if (si.State == 6) continue; // listener
                    WtsSession s = new WtsSession();
                    s.SessionId = si.SessionId;
                    s.State = (si.State >= 0 && si.State < StateNames.Length) ? StateNames[si.State] : si.State.ToString();
                    s.WinStation = si.pWinStationName ?? "";
                    s.User = QueryString(si.SessionId, 5);        // WTSUserName
                    s.Domain = QueryString(si.SessionId, 7);      // WTSDomainName
                    s.ClientName = QueryString(si.SessionId, 10); // WTSClientName
                    s.LogonTime = DateTime.MinValue;
                    s.IdleSec = -1;

                    IntPtr buf; int bytes;
                    if (WTSQuerySessionInformationW(IntPtr.Zero, si.SessionId, 24, out buf, out bytes)) // WTSSessionInfo
                    {
                        try
                        {
                            if (bytes >= Marshal.SizeOf(typeof(WTSINFO)))
                            {
                                WTSINFO wi = (WTSINFO)Marshal.PtrToStructure(buf, typeof(WTSINFO));
                                if (wi.LogonTime > 0) s.LogonTime = DateTime.FromFileTime(wi.LogonTime);
                                if (wi.LastInputTime > 0 && wi.CurrentTime >= wi.LastInputTime)
                                    s.IdleSec = (wi.CurrentTime - wi.LastInputTime) / 1e7;
                            }
                        }
                        catch (ArgumentOutOfRangeException) { }
                        finally { WTSFreeMemory(buf); }
                    }
                    result.Add(s);
                }
            }
            finally { WTSFreeMemory(pInfo); }
            return result;
        }
    }
}
'@

$script:DosDeviceSource = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace WorkerPerfProbe
{
    public static class DosDevice
    {
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern uint QueryDosDeviceW(string lpDeviceName, StringBuilder lpTargetPath, int ucchMax);

        // Returns the first target of an MS-DOS device name (e.g. "Volume{guid}"), or null.
        public static string Query(string deviceName)
        {
            StringBuilder buffer = new StringBuilder(1024);
            uint length = QueryDosDeviceW(deviceName, buffer, buffer.Capacity);
            if (length == 0) return null;
            return buffer.ToString();
        }
    }
}
'@

#endregion

#region ---------- performance counters -------------------------------------------------------

function Test-ProbeInstance([string]$Name, [string]$Mode) {
    switch ($Mode) {
        'total'   { return $Name -eq '_Total' }
        'nototal' { return $Name -ne '_Total' }
        default   { return $true }
    }
}

function Read-ProbePerf {
    # .NET path: reads the category twice, 1 s apart, and calculates each counter value.
    # Instances: 'none' (single instance), 'total', 'all', 'nototal'. MaxInstances 0 = all.
    param([string]$Category, [string[]]$Counters, [string]$Instances, [int]$MaxInstances = 0, [switch]$ShareNames)

    $r = [ordered]@{
        Category = $Category; Exists = $false; CategoryType = ''; CounterNames = @(); CounterNameSource = ''
        InstanceCount = 0; InstanceNames = @(); Counters = @(); Ok = $false; Error = ''
    }
    if (-not [System.Diagnostics.PerformanceCounterCategory]::Exists($Category)) {
        $r.Error = 'Kategorie nicht vorhanden'
        return $r
    }
    $r.Exists = $true
    $cat = New-Object System.Diagnostics.PerformanceCounterCategory -ArgumentList $Category
    $r.CategoryType = $cat.CategoryType.ToString()

    # All counter names of the category, in their original spelling.
    $names = New-Object 'System.Collections.Generic.List[string]'
    try {
        $pcs = $null
        try { $pcs = $cat.GetCounters() }
        catch {
            $inst = $cat.GetInstanceNames()
            if ($inst.Length -gt 0) { $pcs = $cat.GetCounters($inst[0]) }
        }
        if ($null -ne $pcs) {
            foreach ($pc in $pcs) { $names.Add([string]$pc.CounterName); $pc.Dispose() }
            $r.CounterNameSource = 'GetCounters'
        }
    }
    catch { $r.Error = 'Zaehlernamen: ' + (Get-ProbeErrorText $_) }

    $d1 = $cat.ReadCategory()
    Start-Sleep -Seconds 1
    $d2 = $cat.ReadCategory()
    if ($names.Count -eq 0) {
        # ReadCategory keys are lowercased by .NET, so their spelling is not authoritative.
        foreach ($k in $d2.Keys) { $names.Add([string]$k) }
        $r.CounterNameSource = 'ReadCategoryKeys (lowercase)'
    }
    $r.CounterNames = $names.ToArray()

    $wanted = $names.ToArray()
    if ($null -ne $Counters -and $Counters.Length -gt 0) { $wanted = $Counters }

    # One entry per real instance; InstanceIndex links the rows of all counters to it, because the
    # names are not unique once the result is masked (two mount paths may both end in \<user>).
    $instanceNames = New-Object 'System.Collections.Generic.List[string]'
    $instanceIndex = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([StringComparer]::OrdinalIgnoreCase)
    $counterRows = New-Object 'System.Collections.Generic.List[object]'
    $allOk = $wanted.Length -gt 0
    foreach ($cn in $wanted) {
        $e = [ordered]@{ Counter = $cn; Exists = $false; Type = ''; ValueCount = 0; Instances = @() }
        $c1 = $d1.get_Item($cn)
        $c2 = $d2.get_Item($cn)
        if ($null -ne $c2) {
            $e.Exists = $true
            $rows = New-Object 'System.Collections.Generic.List[object]'
            $matched = 0
            foreach ($i2 in @($c2.Values | Sort-Object -Property InstanceName)) {
                $name = [string]$i2.InstanceName
                if (-not (Test-ProbeInstance $name $Instances)) { continue }
                $matched++
                $s2 = $i2.Sample
                $e.Type = $s2.CounterType.ToString()
                $raw1 = $null; $base1 = $null; $time1 = $null; $value = $null
                $i1 = $null
                if ($null -ne $c1) { $i1 = $c1.get_Item($name) }
                if ($null -ne $i1) {
                    $s1 = $i1.Sample
                    $raw1 = $s1.RawValue; $base1 = $s1.BaseValue; $time1 = $s1.TimeStamp100nSec
                    $value = ConvertTo-ProbeNumber ([System.Diagnostics.CounterSample]::Calculate($s1, $s2))
                }
                if ($null -ne $value) { $e.ValueCount = $e.ValueCount + 1 }
                if ($MaxInstances -gt 0 -and $rows.Count -ge $MaxInstances) { continue }

                $shown = ''
                $index = 0
                if ($Instances -ne 'none') {
                    $shown = $name
                    if ($ShareNames) { Add-ProbeShareServer $name }
                    if (-not $instanceIndex.ContainsKey($name)) {
                        $instanceIndex[$name] = $instanceNames.Count
                        $instanceNames.Add($shown)
                    }
                    $index = $instanceIndex[$name]
                }
                $rows.Add([ordered]@{
                        Instance = $shown; InstanceIndex = $index
                        Raw1 = $raw1; Raw2 = $s2.RawValue
                        Base1 = $base1; Base2 = $s2.BaseValue
                        Time1 = $time1; Time2 = $s2.TimeStamp100nSec
                        Value = $value
                    })
            }
            $e.Instances = $rows.ToArray()
            if ($matched -gt $r.InstanceCount) { $r.InstanceCount = $matched }
        }
        if ($e.ValueCount -eq 0) { $allOk = $false }
        $counterRows.Add($e)
    }
    $r.InstanceNames = $instanceNames.ToArray()
    $r.Counters = $counterRows.ToArray()
    $r.Ok = $allOk
    return $r
}

function Get-ProbeCimPerf($Ctx, [string]$Category) {
    # CIM path: names of all Win32_PerfRawData_* classes matching the category name without spaces.
    if ($null -eq $Ctx.CimPerfClasses) {
        try {
            $Ctx.CimPerfClasses = @(Get-CimClass -Namespace 'root\cimv2' -ClassName 'Win32_PerfRawData_*' -OperationTimeoutSec $script:ProbeCimTimeoutSec -ErrorAction Stop |
                    ForEach-Object { [string]$_.CimClassName })
        }
        catch {
            $Ctx.CimPerfClasses = @()
            $Ctx.CimPerfError = Get-ProbeErrorText $_
        }
    }
    $suffix = '_' + ($Category -replace '[^A-Za-z0-9]', '')
    $classes = @($Ctx.CimPerfClasses | Where-Object { $_.EndsWith($suffix, [StringComparison]::OrdinalIgnoreCase) })
    return [ordered]@{ Classes = $classes; Error = $Ctx.CimPerfError }
}

function Invoke-ProbePerfCheck($Ctx, $Check) {
    $p = $Check.Perf
    $dn = $null
    try {
        $dn = Read-ProbePerf -Category $p.Category -Counters $p.Counters -Instances $p.Instances -MaxInstances $p.MaxInstances -ShareNames:($Check.Id -eq 'perf.shares')
    }
    catch {
        $dn = [ordered]@{ Category = $p.Category; Exists = $null; Ok = $false; Error = Get-ProbeErrorText $_ }
    }
    $cim = Get-ProbeCimPerf $Ctx $p.Category

    if ($dn.Ok) {
        $detail = 'DotNet: {0} Zaehler mit Werten, {1} Instanzen' -f @($dn.Counters).Count, $dn.InstanceCount
    }
    elseif ($dn.Error) {
        $detail = 'DotNet: ' + $dn.Error
    }
    else {
        $missing = @($dn.Counters | Where-Object { $_.ValueCount -eq 0 } | ForEach-Object { $_.Counter })
        $detail = 'DotNet: ohne Werte: ' + ($missing -join ', ')
        if ($dn.InstanceCount -eq 0) { $detail = 'DotNet: keine passenden Instanzen' }
    }
    $detail += '; Cim: {0} Klassen' -f $cim.Classes.Count
    return @{ Ok = [bool]$dn.Ok; Detail = $detail; Data = [ordered]@{ DotNet = $dn; Cim = $cim } }
}

function Invoke-ProbeVolumesCheck($Ctx, $Check) {
    $out = Invoke-ProbePerfCheck $Ctx $Check
    $times = New-Object 'System.Collections.Generic.List[object]'
    $dn = $out.Data.DotNet
    if ($dn.Contains('Counters')) {
        $read = @{}; $write = @{}
        foreach ($c in $dn.Counters) {
            foreach ($row in $c.Instances) {
                if ($null -eq $row.Value) { continue }
                if ($c.Counter -eq 'Avg. Disk sec/Read') { $read[$row.InstanceIndex] = $row.Value }
                if ($c.Counter -eq 'Avg. Disk sec/Write') { $write[$row.InstanceIndex] = $row.Value }
            }
        }
        # One row per real instance (by index), even when masked names coincide.
        $names = @($dn.InstanceNames)
        for ($i = 0; $i -lt $names.Count; $i++) {
            $rm = $null; $wm = $null
            if ($read.ContainsKey($i)) { $rm = [Math]::Round($read[$i] * 1000, 3) }
            if ($write.ContainsKey($i)) { $wm = [Math]::Round($write[$i] * 1000, 3) }
            $times.Add([ordered]@{ Instance = $names[$i]; InstanceIndex = $i; ReadMs = $rm; WriteMs = $wm })
        }
    }
    $out.Data.ResponseMs = $times.ToArray()
    return $out
}

function Invoke-ProbeIcaCheck($Ctx, $Check) {
    $out = Invoke-ProbePerfCheck $Ctx $Check
    $euem = [ordered]@{ Namespace = 'root\citrix\euem'; Available = $false; Classes = @(); Error = '' }
    try {
        $classes = New-Object 'System.Collections.Generic.List[object]'
        foreach ($c in @(Get-CimClass -Namespace 'root\citrix\euem' -OperationTimeoutSec $script:ProbeCimTimeoutSec -ErrorAction Stop | Sort-Object -Property CimClassName)) {
            if ($c.CimClassName.StartsWith('__')) { continue }
            $props = @($c.CimClassProperties | ForEach-Object { '{0}:{1}' -f $_.Name, $_.CimType })
            $classes.Add([ordered]@{ Name = [string]$c.CimClassName; Properties = $props })
        }
        $euem.Classes = $classes.ToArray()
        $euem.Available = $true
    }
    catch { $euem.Error = Get-ProbeErrorText $_ }
    $out.Data.Euem = $euem
    $out.Detail += '; EUEM: {0} Klassen' -f @($euem.Classes).Count
    return $out
}

function Read-ProbeInputSeries($Category, [string]$Counter, [int]$Count, [int]$IntervalSec) {
    # $Count readings, $IntervalSec apart; each value is calculated against the previous reading.
    $samples = New-Object 'System.Collections.Generic.List[object]'
    $names = New-Object 'System.Collections.Generic.List[string]'
    $type = ''
    $valueCount = 0
    $prev = $null
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    for ($k = 0; $k -lt $Count; $k++) {
        $wait = [int]($k * $IntervalSec * 1000 - $sw.ElapsedMilliseconds)
        if ($wait -gt 0) { Start-Sleep -Milliseconds $wait }
        $offset = Get-ProbeMs $sw
        $coll = $Category.ReadCategory().get_Item($Counter)
        $readings = New-Object 'System.Collections.Generic.List[object]'
        if ($null -ne $coll) {
            foreach ($i in @($coll.Values | Sort-Object -Property InstanceName)) {
                $name = [string]$i.InstanceName
                $s = $i.Sample
                $type = $s.CounterType.ToString()
                $shown = $name
                if (-not $names.Contains($shown)) { $names.Add($shown) }
                $p = $null
                if ($null -ne $prev) { $p = $prev.get_Item($name) }
                if ($null -ne $p) { $v = [System.Diagnostics.CounterSample]::Calculate($p.Sample, $s) }
                else { $v = [System.Diagnostics.CounterSample]::Calculate($s) }
                $v = ConvertTo-ProbeNumber $v
                if ($null -ne $v) { $valueCount++ }
                $readings.Add([ordered]@{ Instance = $shown; Raw = $s.RawValue; Value = $v })
            }
        }
        $samples.Add([ordered]@{ OffsetMs = $offset; Readings = $readings.ToArray() })
        $prev = $coll
    }
    return @{ Samples = $samples.ToArray(); Names = $names.ToArray(); Type = $type; ValueCount = $valueCount }
}

function Invoke-ProbeInputSessionCheck($Ctx, $Check) {
    $p = $Check.Perf
    $counter = $p.Counters[0]
    $dn = [ordered]@{
        Category = $p.Category; Counter = $counter; Exists = $false; Type = ''; InstanceNames = @()
        InputSeconds = $Ctx.InputSeconds; Interval1s = @(); Interval2s = @(); Ok = $false; Error = ''
    }
    try {
        if ([System.Diagnostics.PerformanceCounterCategory]::Exists($p.Category)) {
            $dn.Exists = $true
            $cat = New-Object System.Diagnostics.PerformanceCounterCategory -ArgumentList $p.Category
            Write-Host '      Bitte jetzt in einer Benutzersitzung tippen oder Fenster bewegen ...'
            $one = Read-ProbeInputSeries $cat $counter $Ctx.InputSeconds 1
            $two = Read-ProbeInputSeries $cat $counter ([int][Math]::Floor($Ctx.InputSeconds / 2)) 2
            $dn.Type = $one.Type
            $all = New-Object 'System.Collections.Generic.List[string]'
            foreach ($n in @($one.Names) + @($two.Names)) { if (-not $all.Contains($n)) { $all.Add($n) } }
            $dn.InstanceNames = $all.ToArray()
            $dn.Interval1s = $one.Samples
            $dn.Interval2s = $two.Samples
            $dn.Ok = $one.ValueCount -gt 0
            if (-not $dn.Ok) { $dn.Error = 'keine Werte' }
        }
        else { $dn.Error = 'Kategorie nicht vorhanden' }
    }
    catch { $dn.Error = Get-ProbeErrorText $_ }
    $cim = Get-ProbeCimPerf $Ctx $p.Category

    if ($dn.Ok) {
        $detail = 'DotNet: {0} Instanzen, {1} Proben je 1 s, {2} Proben je 2 s' -f @($dn.InstanceNames).Count, @($dn.Interval1s).Count, @($dn.Interval2s).Count
    }
    else { $detail = 'DotNet: ' + $dn.Error }
    $detail += '; Cim: {0} Klassen' -f $cim.Classes.Count
    return @{ Ok = [bool]$dn.Ok; Detail = $detail; Data = [ordered]@{ DotNet = $dn; Cim = $cim } }
}

#endregion

#region ---------- other checks -----------------------------------------------------------------

function Invoke-ProbeSystemCheck($Ctx, $Check) {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec $script:ProbeCimTimeoutSec -ErrorAction Stop
    $cpus = @(Get-CimInstance -ClassName Win32_Processor -OperationTimeoutSec $script:ProbeCimTimeoutSec -ErrorAction Stop)
    $cores = 0
    foreach ($c in $cpus) { $cores += [int]$c.NumberOfCores }
    $vmTools = @(Get-CimInstance -ClassName Win32_Service -Filter "Name='VMTools'" -OperationTimeoutSec $script:ProbeCimTimeoutSec -ErrorAction Stop)
    $vmState = ''
    if ($vmTools.Count -gt 0) { $vmState = [string]$vmTools[0].State }
    $data = [ordered]@{
        LogicalProcessors = [int]$cs.NumberOfLogicalProcessors
        Cores             = $cores
        Sockets           = $cpus.Count
        MemoryBytes       = [uint64]$cs.TotalPhysicalMemory
        Manufacturer      = [string]$cs.Manufacturer
        Model             = [string]$cs.Model
        VMToolsPresent    = $vmTools.Count -gt 0
        VMToolsState      = $vmState
    }
    $detail = '{0} logische Prozessoren, {1} Kerne, {2:0.0} GB RAM, {3} {4}, VMTools: {5}' -f $data.LogicalProcessors, $cores,
        ($data.MemoryBytes / 1GB), $data.Manufacturer, $data.Model, $data.VMToolsPresent
    return @{ Ok = $true; Detail = $detail; Data = $data }
}

function Invoke-ProbeProcessSnapshotCheck($Ctx, $Check) {
    $durations = New-Object 'System.Collections.Generic.List[double]'
    $procs = @()
    for ($k = 0; $k -lt 3; $k++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $procs = @(Get-CimInstance -ClassName Win32_Process -OperationTimeoutSec $script:ProbeCimTimeoutSec -ErrorAction Stop)
        $sw.Stop()
        $durations.Add((Get-ProbeMs $sw))
    }
    $Ctx.Processes = $procs
    $d = $durations.ToArray()
    $detail = '{0} Prozesse, Abfrage {1} ms' -f $procs.Count, (($d | ForEach-Object { $_.ToString([Globalization.CultureInfo]::InvariantCulture) }) -join ' / ')
    return @{ Ok = $true; Detail = $detail; Data = [ordered]@{ ProcessCount = $procs.Count; DurationsMs = $d } }
}

function Invoke-ProbeSessionsCheck($Ctx, $Check) {
    $data = [ordered]@{
        Compiled = $Ctx.WtsCompiled; Error = $Ctx.WtsError; SessionCount = 0; ByState = [ordered]@{}
        WithUser = 0; WithLogonTime = 0; WithIdleTime = 0
        MaskProfileCount = $Ctx.ProfileNameCount; MaskProfileError = $Ctx.ProfileError
    }
    $sessions = @($Ctx.Sessions)
    $data.SessionCount = $sessions.Count
    foreach ($s in $sessions) {
        $state = [string]$s.State
        if ($data.ByState.Contains($state)) { $data.ByState[$state] = $data.ByState[$state] + 1 } else { $data.ByState[$state] = 1 }
        if (-not [string]::IsNullOrEmpty($s.User)) { $data.WithUser++ }
        if ($s.LogonTime -gt [DateTime]::MinValue) { $data.WithLogonTime++ }
        if ($s.IdleSec -ge 0) { $data.WithIdleTime++ }
    }
    $ok = $Ctx.WtsCompiled -and [string]::IsNullOrEmpty($Ctx.WtsError)
    if ($ok) {
        $states = @($data.ByState.Keys | ForEach-Object { '{0} {1}' -f $_, $data.ByState[$_] }) -join ', '
        $detail = '{0} Sitzungen ({1})' -f $sessions.Count, $states
    }
    else { $detail = 'WTS: ' + $Ctx.WtsError }
    return @{ Ok = $ok; Detail = $detail; Data = $data }
}

function Invoke-ProbeServicesCheck($Ctx, $Check) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $Ctx.Services = @(Get-CimInstance -ClassName Win32_Service -OperationTimeoutSec $script:ProbeCimTimeoutSec -ErrorAction Stop)
    $sw.Stop()
    $rows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($s in @($Ctx.Services | Where-Object { [int]$_.ProcessId -ne 0 } | Sort-Object -Property Name)) {
        $rows.Add([ordered]@{ Name = [string]$s.Name; ProcessId = [int]$s.ProcessId })
    }
    $ms = Get-ProbeMs $sw
    $detail = '{0} Dienste mit Prozess, Abfrage {1} ms' -f $rows.Count, $ms.ToString([Globalization.CultureInfo]::InvariantCulture)
    return @{ Ok = $true; Detail = $detail; Data = [ordered]@{ DurationMs = $ms; Services = $rows.ToArray() } }
}

function Invoke-ProbeProfileVolumesCheck($Ctx, $Check) {
    $dosError = ''
    try { if (-not ('WorkerPerfProbe.DosDevice' -as [type])) { Add-Type -TypeDefinition $script:DosDeviceSource -Language CSharp } }
    catch { $dosError = Get-ProbeErrorText $_ }

    $ldInstances = @()
    $ldError = ''
    try { $ldInstances = @((New-Object System.Diagnostics.PerformanceCounterCategory -ArgumentList 'LogicalDisk').GetInstanceNames()) }
    catch { $ldError = Get-ProbeErrorText $_ }

    $ns = 'root\Microsoft\Windows\Storage'
    $disks = @(Get-CimInstance -Namespace $ns -ClassName MSFT_Disk -Filter 'BusType = 15' -OperationTimeoutSec $script:ProbeCimTimeoutSec -ErrorAction Stop)
    $rows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($d in $disks) {
        $number = [int](Get-Prop $d 'Number')
        $location = [string](Get-Prop $d 'Location')
        $parts = New-Object 'System.Collections.Generic.List[object]'
        foreach ($p in @(Get-CimInstance -Namespace $ns -ClassName MSFT_Partition -Filter ('DiskNumber = {0}' -f $number) -OperationTimeoutSec $script:ProbeCimTimeoutSec -ErrorAction Stop)) {
            $paths = @(@(Get-Prop $p 'AccessPaths') | Where-Object { -not [string]::IsNullOrEmpty($_) })
            $letter = ''
            $dl = Get-Prop $p 'DriveLetter'
            if ($null -ne $dl -and [int][char]$dl -ne 0) { $letter = ([string][char]$dl) + ':' }

            $device = ''
            $candidates = New-Object 'System.Collections.Generic.List[string]'
            if ($letter) { $candidates.Add($letter) }
            foreach ($ap in $paths) {
                $m = [regex]::Match($ap, '^\\\\\?\\(Volume\{[^}]+\})\\?$')
                if ($m.Success -and -not $dosError) {
                    $dosTarget = [WorkerPerfProbe.DosDevice]::Query($m.Groups[1].Value)
                    if ($dosTarget) {
                        $device = $dosTarget
                        $candidates.Add($dosTarget.Substring($dosTarget.LastIndexOf('\') + 1))
                    }
                }
                else { $candidates.Add($ap.TrimEnd('\')) }
            }
            $instance = ''
            foreach ($li in $ldInstances) {
                if (@($candidates | Where-Object { $_ -eq $li }).Count -gt 0) { $instance = $li; break }
            }
            $userInPaths = @($paths | Where-Object { Test-ProbeUserInText $_ }).Count -gt 0
            $parts.Add([ordered]@{
                    PartitionNumber     = [int](Get-Prop $p 'PartitionNumber')
                    DriveLetter         = $letter
                    Size                = [uint64](Get-Prop $p 'Size')
                    AccessPaths         = @($paths)
                    DeviceName          = $device
                    LogicalDiskInstance = $instance
                    UserInAccessPaths   = $userInPaths
                })
        }
        $rows.Add([ordered]@{
                Number         = $number
                Size           = [uint64](Get-Prop $d 'Size')
                Location       = $location
                UserInLocation = Test-ProbeUserInText $location
                Partitions     = $parts.ToArray()
            })
    }
    $data = [ordered]@{
        Disks                = $rows.ToArray()
        LogicalDiskInstances = @($ldInstances)
        LogicalDiskError     = $ldError
        QueryDosDeviceError  = $dosError
    }
    return @{ Ok = $true; Detail = ('{0} Datentraeger mit BusType 15' -f $rows.Count); Data = $data }
}

function Get-ProbeEventCounts([string]$Log, [int[]]$Ids) {
    $r = [ordered]@{ Log = $Log; Exists = $false; Enabled = $null; Readable = $false; Counts = [ordered]@{}; Capped = $false; Error = '' }
    try {
        $info = Get-WinEvent -ListLog $Log -ErrorAction Stop
        $r.Exists = $true
        $r.Enabled = [bool]$info.IsEnabled
    }
    catch {
        $r.Error = Get-ProbeErrorText $_
        return $r
    }
    try {
        $events = @()
        try {
            $events = @(Get-WinEvent -FilterHashtable @{ LogName = $Log; Id = $Ids; StartTime = (Get-Date).AddDays(-7) } -MaxEvents $script:ProbeMaxEvents -ErrorAction Stop)
        }
        catch {
            # No matching events is not an error; the error id is language neutral.
            if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { throw }
        }
        $r.Readable = $true
        $r.Capped = ($events.Count -ge $script:ProbeMaxEvents)       # the counts cover the newest events only
        foreach ($id in $Ids) { $r.Counts[[string]$id] = @($events | Where-Object { $_.Id -eq $id }).Count }
    }
    catch { $r.Error = Get-ProbeErrorText $_ }
    return $r
}

function Invoke-ProbeEventsCheck($Ctx, $Check) {
    $logs = New-Object 'System.Collections.Generic.List[object]'
    foreach ($log in $Check.Logs) { $logs.Add((Get-ProbeEventCounts $log $Check.EventIds)) }
    $parts = New-Object 'System.Collections.Generic.List[string]'
    $ok = $true
    foreach ($l in $logs) {
        if ($l.Readable) {
            $counts = @($l.Counts.Keys | ForEach-Object { '{0}={1}' -f $_, $l.Counts[$_] }) -join ' '
            $parts.Add(('{0}: {1}' -f $l.Log, $counts))
        }
        else {
            $ok = $false
            $parts.Add(('{0}: nicht lesbar ({1})' -f $l.Log, $l.Error))
        }
    }
    return @{ Ok = $ok; Detail = ($parts.ToArray() -join '; '); Data = [ordered]@{ Days = 7; MaxEvents = $script:ProbeMaxEvents; Logs = $logs.ToArray() } }
}

function Get-ProbeProcessGroups($Ctx, [bool]$SessionZero) {
    $procs = Get-ProbeProcesses $Ctx
    $pidServices = @{}
    if ($SessionZero) {
        foreach ($s in (Get-ProbeServices $Ctx)) {
            $id = [int]$s.ProcessId
            if ($id -eq 0) { continue }
            if (-not $pidServices.ContainsKey($id)) { $pidServices[$id] = New-Object 'System.Collections.Generic.List[string]' }
            $pidServices[$id].Add([string]$s.Name)
        }
    }
    $selected = @($procs | Where-Object { ([int]$_.SessionId -eq 0) -eq $SessionZero })
    $rows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($g in @($selected | Group-Object -Property Name | Sort-Object -Property Name)) {
        $path = ''
        foreach ($p in $g.Group) {
            $ep = [string](Get-Prop $p 'ExecutablePath')
            if ($ep) { $path = $ep; break }
        }
        $info = Get-ProbeFileInfo $Ctx $path
        $row = [ordered]@{
            Name        = [string]$g.Name
            Instances   = $g.Count
            Company     = [string]$info.Company
            Description = [string]$info.Description
        }
        if ($SessionZero) {
            $svc = New-Object 'System.Collections.Generic.List[string]'
            foreach ($p in $g.Group) {
                $id = [int]$p.ProcessId
                if ($pidServices.ContainsKey($id)) { foreach ($n in $pidServices[$id]) { if (-not $svc.Contains($n)) { $svc.Add($n) } } }
            }
            $row.Services = @($svc.ToArray() | Sort-Object)
        }
        $rows.Add($row)
    }
    return @{ Rows = $rows.ToArray(); ProcessCount = $selected.Count }
}

function Invoke-ProbeSecurityProductsCheck($Ctx, $Check) {
    $g = Get-ProbeProcessGroups $Ctx $true
    $detail = '{0} Prozessnamen in Sitzung 0 ({1} Prozesse)' -f @($g.Rows).Count, $g.ProcessCount
    return @{ Ok = $true; Detail = $detail; Data = [ordered]@{ Processes = $g.Rows } }
}

function Invoke-ProbeUserProcessesCheck($Ctx, $Check) {
    $g = Get-ProbeProcessGroups $Ctx $false
    $detail = '{0} Prozessnamen in Benutzersitzungen ({1} Prozesse)' -f @($g.Rows).Count, $g.ProcessCount
    return @{ Ok = $true; Detail = $detail; Data = [ordered]@{ Processes = $g.Rows } }
}

function Invoke-ProbeEndpointsCheck($Ctx, $Check) {
    if ([string]::IsNullOrEmpty($Ctx.EndpointFile)) {
        # Not configured is not a failed source: Ok stays $null and Data says it was skipped.
        return @{ Ok = $null; Detail = 'kein -EndpointFile angegeben, Pruefung uebersprungen'; Data = [ordered]@{ Skipped = $true; TimeoutMs = 2000; Endpoints = @() } }
    }
    # an unreadable endpoint file is reported without the engine's message: that can quote the file, host names included
    $cfg = $null
    try { $cfg = Get-Content -LiteralPath $Ctx.EndpointFile -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw 'Die Datei fuer -EndpointFile ist nicht lesbar oder kein gueltiges JSON.' }
    $rows = New-Object 'System.Collections.Generic.List[object]'
    $reached = 0
    $endpoints = @(Get-Prop $cfg 'endpoints')
    # Host names never reach the result: endpoints are identified by position, name and role, and the hosts join the
    # names to mask, so that a label that quotes a host is masked like every other text.
    $null = Add-ProbeServerNames @($endpoints | ForEach-Object { [string](Get-Prop $_ 'host') })
    $position = 0
    foreach ($e in $endpoints) {
        $position++
        $hostName = [string](Get-Prop $e 'host')
        $row = [ordered]@{
            Index = $position
            Name = [string](Get-Prop $e 'name')
            Role = [string](Get-Prop $e 'role')
            Port = Get-Prop $e 'port'; DnsMs = $null; ConnectMs = $null; Error = ''
        }
        # Error is a short class (dns, refused, timeout, other), never the exception text: under .NET Framework that
        # ends with the address the name resolved to. The resolved address is used for the connect only.
        $address = $null
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $addresses = @([System.Net.Dns]::GetHostAddresses($hostName))
            $row.DnsMs = Get-ProbeMs $sw
            $address = @($addresses | Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork }) + $addresses | Select-Object -First 1
        }
        catch { $address = $null }
        if ($null -eq $address) { $row.Error = 'dns' }
        else {
            try {
                $client = New-Object System.Net.Sockets.TcpClient -ArgumentList $address.AddressFamily
                try {
                    $sw.Restart()
                    $async = $client.BeginConnect($address, [int]$row.Port, $null, $null)
                    if ($async.AsyncWaitHandle.WaitOne(2000)) {
                        $client.EndConnect($async)
                        $row.ConnectMs = Get-ProbeMs $sw
                        $reached++
                    }
                    else { $row.Error = 'timeout' }
                }
                finally { $client.Close() }
            }
            catch { $row.Error = Get-ProbeEndpointErrorClass $_.Exception }
        }
        $rows.Add($row)
    }
    $detail = '{0} von {1} Gegenstellen erreichbar' -f $reached, $rows.Count
    return @{ Ok = ($rows.Count -gt 0 -and $reached -eq $rows.Count); Detail = $detail; Data = [ordered]@{ Skipped = $false; TimeoutMs = 2000; Endpoints = $rows.ToArray() } }
}

#endregion

#region ---------- check catalogue -------------------------------------------------------------

# One list drives both -ListChecks and the run, so they cannot drift apart.
$script:Catalogue = @(
    @{ Id = 'system'; Signals = @(); Title = 'Kerne, RAM, Hersteller, VMware Tools'; Run = 'Invoke-ProbeSystemCheck' }
    @{ Id = 'process.snapshot'; Signals = @(); Title = 'Dauer eines Prozess-Schnappschusses (Win32_Process)'; Run = 'Invoke-ProbeProcessSnapshotCheck' }
    @{ Id = 'sessions.wts'; Signals = @(); Title = 'Sitzungen ueber die WTS-Schnittstelle'; Run = 'Invoke-ProbeSessionsCheck' }
    @{ Id = 'services.map'; Signals = @(); Title = 'Dienste und ihre Prozesse (Win32_Service)'; Run = 'Invoke-ProbeServicesCheck' }
    @{ Id = 'perf.cpu'; Signals = @('cpu.host'); Title = 'CPU-Auslastung des Hosts'; Run = 'Invoke-ProbePerfCheck'
        Perf = @{ Category = 'Processor Information'; Counters = @('% Processor Time'); Instances = 'total'; MaxInstances = 0 } }
    @{ Id = 'perf.queue'; Signals = @('cpu.queue'); Title = 'Prozessor-Warteschlange'; Run = 'Invoke-ProbePerfCheck'
        Perf = @{ Category = 'System'; Counters = @('Processor Queue Length'); Instances = 'none'; MaxInstances = 0 } }
    @{ Id = 'perf.steal'; Signals = @('cpu.steal'); Title = 'CPU-Wartezeit der VM (VMware)'; Run = 'Invoke-ProbePerfCheck'
        Perf = @{ Category = 'VM Processor'; Counters = @('CPU stolen time'); Instances = 'all'; MaxInstances = 0 } }
    @{ Id = 'perf.memory'; Signals = @('mem.used', 'mem.commit', 'mem.pagesin'); Title = 'Arbeitsspeicher, Zusagen, Seiteneingaben'; Run = 'Invoke-ProbePerfCheck'
        Perf = @{ Category = 'Memory'; Counters = @('Available Bytes', 'Committed Bytes', 'Commit Limit', 'Pages Input/sec'); Instances = 'none'; MaxInstances = 0 } }
    @{ Id = 'perf.disk.total'; Signals = @(); Title = 'Physische Datentraeger gesamt'; Run = 'Invoke-ProbePerfCheck'
        Perf = @{ Category = 'PhysicalDisk'; Counters = @('Disk Read Bytes/sec', 'Disk Write Bytes/sec', 'Disk Reads/sec', 'Disk Writes/sec', 'Current Disk Queue Length'); Instances = 'total'; MaxInstances = 0 } }
    @{ Id = 'perf.network'; Signals = @(); Title = 'Netzwerkdurchsatz je Adapter'; Run = 'Invoke-ProbePerfCheck'
        Perf = @{ Category = 'Network Interface'; Counters = @('Bytes Received/sec', 'Bytes Sent/sec'); Instances = 'all'; MaxInstances = 0 } }
    @{ Id = 'perf.volumes'; Signals = @('disk.latency'); Title = 'Antwortzeiten je Laufwerk'; Run = 'Invoke-ProbeVolumesCheck'
        Perf = @{ Category = 'LogicalDisk'; Counters = @('Avg. Disk sec/Read', 'Avg. Disk sec/Write', 'Disk Reads/sec', 'Disk Writes/sec', 'Disk Read Bytes/sec', 'Disk Write Bytes/sec', 'Current Disk Queue Length'); Instances = 'nototal'; MaxInstances = 0 } }
    @{ Id = 'perf.shares'; Signals = @('smb.latency'); Title = 'Antwortzeiten je SMB-Freigabe'; Run = 'Invoke-ProbePerfCheck'
        Perf = @{ Category = 'SMB Client Shares'; Counters = @('Avg. sec/Read', 'Avg. sec/Write', 'Read Requests/sec', 'Write Requests/sec', 'Read Bytes/sec', 'Write Bytes/sec'); Instances = 'all'; MaxInstances = 0 } }
    @{ Id = 'perf.input.session'; Signals = @('input.session'); Title = 'Eingabeverzoegerung je Sitzung'; Run = 'Invoke-ProbeInputSessionCheck'
        Perf = @{ Category = 'User Input Delay per Session'; Counters = @('Max Input Delay'); Instances = 'all'; MaxInstances = 0 } }
    @{ Id = 'perf.input.process'; Signals = @(); Title = 'Eingabeverzoegerung je Prozess'; Run = 'Invoke-ProbePerfCheck'
        Perf = @{ Category = 'User Input Delay per Process'; Counters = @('Max Input Delay'); Instances = 'all'; MaxInstances = 10 } }
    @{ Id = 'perf.ica'; Signals = @('ica.rtt', 'ica.latency'); Title = 'ICA-Sitzungswerte und Citrix EUEM'; Run = 'Invoke-ProbeIcaCheck'
        Perf = @{ Category = 'ICA Session'; Counters = @(); Instances = 'all'; MaxInstances = 3 } }
    @{ Id = 'profile.volumes'; Signals = @(); Title = 'Eingebundene Profilcontainer'; Run = 'Invoke-ProbeProfileVolumesCheck' }
    @{ Id = 'events.defender'; Signals = @(); Title = 'Ereignisprotokoll Microsoft Defender'; Run = 'Invoke-ProbeEventsCheck'
        Logs = @('Microsoft-Windows-Windows Defender/Operational'); EventIds = @(1000, 1001, 1002, 2000) }
    @{ Id = 'events.applocker'; Signals = @(); Title = 'Ereignisprotokolle AppLocker'; Run = 'Invoke-ProbeEventsCheck'
        Logs = @('Microsoft-Windows-AppLocker/EXE and DLL', 'Microsoft-Windows-AppLocker/MSI and Script'); EventIds = @(8004, 8007) }
    @{ Id = 'security.products'; Signals = @(); Title = 'Prozesse und Dienste in Sitzung 0'; Run = 'Invoke-ProbeSecurityProductsCheck' }
    @{ Id = 'user.processes'; Signals = @(); Title = 'Prozesse in Benutzersitzungen'; Run = 'Invoke-ProbeUserProcessesCheck' }
    @{ Id = 'endpoints'; Signals = @('probe.connect'); Title = 'TCP-Verbindungsaufbau zu den Gegenstellen'; Run = 'Invoke-ProbeEndpointsCheck' }
)

#endregion

#region ---------- main ---------------------------------------------------------------------------

if ($ListChecks) {
    foreach ($c in $script:Catalogue) {
        [pscustomobject]@{ Id = $c.Id; Signals = [string[]]$c.Signals; Title = $c.Title }
    }
    return
}

$onWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
if (-not $onWindows) { throw 'Das Pruefskript laeuft nur unter Windows.' }

if ($EndpointFile -and -not (Test-Path -LiteralPath $EndpointFile -PathType Leaf)) {
    throw "Die Datei fuer -EndpointFile wurde nicht gefunden: $EndpointFile"
}

# Resolve the output file first, so a bad path fails before the checks run.
$fileName = Get-ProbeFileName (Get-Date)
if ([string]::IsNullOrEmpty($OutFile)) { $OutFile = (Get-Location).ProviderPath }
$target = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
if ((Test-Path -LiteralPath $target -PathType Container) -or -not $target.EndsWith('.json', [StringComparison]::OrdinalIgnoreCase)) {
    if (-not (Test-Path -LiteralPath $target)) { $null = New-Item -ItemType Directory -Path $target }
    $target = Join-Path $target $fileName
}
else {
    $parent = Split-Path -Parent $target
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent }
}

$ctx = @{
    Sessions = @(); WtsCompiled = $false; WtsError = ''
    Processes = $null; Services = $null; FileInfo = @{}
    CimPerfClasses = $null; CimPerfError = ''
    InputSeconds = $InputSeconds
    EndpointFile = ''
    ProfileNameCount = 0; ProfileError = ''
}
if ($EndpointFile) { $ctx.EndpointFile = (Resolve-Path -LiteralPath $EndpointFile).ProviderPath }

# The two sources of the names to mask: the sessions, and independent of WTS the folders of all local (non-special)
# user profiles.
# The WTS helper is compiled once; when that fails, every reading of the sessions reports the same error.
$wtsCompileError = $null
try { if (-not ('WorkerPerfProbe.Wts' -as [type])) { Add-Type -TypeDefinition $script:WtsSource -Language CSharp } }
catch { $wtsCompileError = $_ }
$readSessions = {
    if ($null -ne $wtsCompileError) { throw $wtsCompileError }
    [WorkerPerfProbe.Wts]::GetSessions()
}
$readProfiles = {
    Get-CimInstance -ClassName Win32_UserProfile -OperationTimeoutSec $script:ProbeCimTimeoutSec -ErrorAction Stop |
        Where-Object { -not (Get-Prop $_ 'Special') } | ForEach-Object { [string](Get-Prop $_ 'LocalPath') }
}
# the names that do not change during the run: the current user, and the worker's own NetBIOS and host name (they
# differ when the name is longer than 15 characters)
$hostName = ''
try { $hostName = [System.Net.Dns]::GetHostName() } catch { $hostName = '' }
$null = Add-ProbeMaskNames -Users @($env:USERNAME) -Domains @($env:USERDOMAIN, $env:USERDNSDOMAIN) -Computers @($env:COMPUTERNAME, $hostName)

# Sessions first: their user names are needed to mask every later result.
$first = Read-ProbeNames $readSessions $readProfiles
$ctx.Sessions = @($first.Sessions)
$ctx.WtsCompiled = [bool]('WorkerPerfProbe.Wts' -as [type])
$ctx.WtsError = $first.WtsError
$ctx.ProfileNameCount = @($first.ProfilePaths).Count
$ctx.ProfileError = $first.ProfileError
# Fail closed: without the user names (no list at all, or an active session without a name) the result could leak
# them, so nothing is measured and nothing is written.
if ($first.Gap) {
    throw (Hide-ProbeText ('{0} (WTS: {1}; Win32_UserProfile: {2}). Es wird keine Datei geschrieben.' -f $first.Gap, $first.WtsError, $first.ProfileError))
}

$isElevated = $false
try {
    $principal = New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())
    $isElevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
catch { $isElevated = $false }
if (-not $isElevated) { Write-Warning 'Konsole ohne erhoehte Rechte: einige Pruefungen liefern weniger Daten.' }

$os = ''
try {
    $o = Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec $script:ProbeCimTimeoutSec -ErrorAction Stop
    $os = '{0} {1}' -f $o.Caption, $o.Version
}
catch { $os = 'unbekannt' }

$results = @(Invoke-ProbeCatalogue $script:Catalogue $ctx $readSessions)

# Sessions and profiles once more: whoever logged on since the start is masked as well, and an active session
# without a user name stops the result here like at the start.
Write-Host 'Namen werden erneut gelesen, das Ergebnis wird maskiert und geschrieben ...'
$last = Read-ProbeNames $readSessions $readProfiles
if ($last.Gap) {
    throw (Hide-ProbeText ('{0} (WTS: {1}; Win32_UserProfile: {2}). Es wird keine Datei geschrieben; bitte das Skript erneut starten.' -f $last.Gap, $last.WtsError, $last.ProfileError))
}

# No name of the worker in the result: several workers are told apart by the time stamp of the file.
$report = [ordered]@{
    SchemaVersion = 2
    OS            = $os
    PSVersion     = $PSVersionTable.PSVersion.ToString()
    Culture       = (Get-Culture).Name
    UICulture     = (Get-UICulture).Name
    IsElevated    = $isElevated
    Checks        = $results
}
# The one masking pass, with every name known by now. Before it, the servers of all UNC paths in the result join
# the names, so that a server is masked in free text too (an error message that quotes it without a path).
$null = Add-ProbeServerNames @(Get-ProbeUncHosts @(Get-ProbeTexts $report))
$report = Protect-ProbeValue $report
$json = ConvertTo-Json -InputObject $report -Depth 16
[System.IO.File]::WriteAllText($target, $json, (New-Object System.Text.UTF8Encoding $false))

# the table shows what the file holds
$report.Checks | ForEach-Object {
    $shownOk = $_.Ok
    if ($null -eq $shownOk) { $shownOk = 'uebersprungen' }
    [pscustomobject]@{ Id = $_.Id; Ok = $shownOk; Detail = $_.Detail }
} |
    Format-Table -AutoSize -Wrap | Out-Host
Write-Host ('Ergebnis gespeichert: {0}' -f $target)
Write-Host 'Bitte diese Datei zur Auswertung zurueckgeben.'

#endregion
