#Requires -Version 5.1
# Event catalogue (events.json) and conversion of raw Windows events into records.
# Dot-source after WorkerPerf.Common.ps1; this file only defines functions and runs nothing.

$script:WorkerPerfEventGroups = @('app', 'service', 'storage', 'memory', 'fileserver', 'profile', 'print', 'session', 'security')
$script:WorkerPerfEventKinds = @('crash', 'hang', 'app-detail', 'service', 'print', 'profileerror', 'system', 'logon', 'logoff',
    'disconnect', 'reconnect', 'scan-start', 'scan-end', 'signature-update', 'applocker-block', 'driver-import', 'info')
$script:WorkerPerfEventNumberKeys = @('pid', 'session')
# The list nonPersonAccounts that src/events.json ships; used when a custom events.json has none.
$script:WorkerPerfDefaultNonPersonAccounts = @('SYSTEM', 'LOCAL SERVICE', 'NETWORK SERVICE', 'LOKALER DIENST', 'NETZWERKDIENST', 'DWM-*', 'UMFD-*',
    'ANONYMOUS LOGON', 'ANONYMOUS-ANMELDUNG', '*$')
# The list nonPersonDomains that src/events.json ships: domain parts of virtual and built-in accounts (an account
# "<domain>\<name>" with one of them is never a person). NT-AUTORIT<A-umlaut>T is built from its char code (ASCII source).
$script:WorkerPerfDefaultNonPersonDomains = @('NT SERVICE', 'IIS APPPOOL', 'NT AUTHORITY', ('NT-AUTORIT' + [char]0xC4 + 'T'), 'Window Manager', 'Font Driver Host')
# The list noModules that src/events.json ships: what Windows writes when it found no module ('unknown', 'StackHash_*').
$script:WorkerPerfDefaultNoModules = @('unknown', 'StackHash_*')
$script:WorkerPerfEventFieldKeys = @('app', 'appVersion', 'module', 'moduleVersion', 'code', 'pid', 'session', 'user', 'printer', 'driver', 'service', 'object',
    'processStart')
# Event levels of an entry ("levels" in events.json) -> the Level values of the System part. Information is written
# as 4, by some providers as 0 (LogAlways).
$script:WorkerPerfEventLevels = [ordered]@{ critical = @(1); error = @(2); warning = @(3); information = @(0, 4) }
# Accounts of the well-known service SIDs, independent of the display language of Windows (a German Windows calls
# LOCAL SERVICE "LOKALER DIENST"): the names that nonPersonAccounts lists first.
$script:WorkerPerfWellKnownSids = @{ 'S-1-5-18' = 'SYSTEM'; 'S-1-5-19' = 'LOCAL SERVICE'; 'S-1-5-20' = 'NETWORK SERVICE' }

function ConvertTo-WorkerPerfEventInt($Value) {
    # JSON number (Int32, Int64, Decimal or Double depending on the PowerShell version) or numeric text -> [int]; else $null.
    if ($null -eq $Value -or $Value -is [bool]) { return $null }
    $d = [double]::NaN
    if ($Value -is [string]) {
        if (-not [double]::TryParse($Value, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $null }
    }
    elseif ($Value -is [ValueType] -and $Value -isnot [char]) { $d = [double]$Value }
    else { return $null }
    if ([double]::IsNaN($d) -or [double]::IsInfinity($d) -or $d -ne [Math]::Floor($d) -or $d -lt 0 -or $d -gt [int]::MaxValue) { return $null }
    return [int]$d
}

function Get-WorkerPerfEventStringList($Json, [string]$Name, [string]$Path) {
    # Optional list of non-empty strings; a single element or a missing list both work in 5.1 and 7.
    $v = Get-WorkerPerfField $Json $Name
    $out = New-Object System.Collections.Generic.List[string]
    if ($null -eq $v) { return , @() }
    foreach ($s in @($v)) {
        if ($s -isnot [string] -or [string]::IsNullOrWhiteSpace($s)) { throw "events.json: Feld '$Name' enthaelt einen Eintrag, der kein Text ist." }
        $out.Add($s)
    }
    return , $out.ToArray()
}

function Get-WorkerPerfEventNamePatterns($Json, [string]$Name, [string]$Path, [string[]]$Default, [string]$What) {
    # Optional list of name patterns: '*' is the only wildcard; a pattern names an account without its domain or a file
    # without its path. A missing list (or null) takes Default; an empty list stays empty.
    $prop = $null
    if ($null -ne $Json) { $prop = $Json.PSObject.Properties[$Name] }
    if ($null -eq $prop -or $null -eq $prop.Value) { return , [string[]]$Default }
    $list = Get-WorkerPerfEventStringList $Json $Name $Path
    foreach ($s in $list) {
        # at least one letter, digit or '$' (the computer accounts '*$'): '*', '*.*' or '*-*' would match nearly every name
        $literal = $false
        foreach ($ch in $s.ToCharArray()) { if ([char]::IsLetterOrDigit($ch) -or $ch -eq '$') { $literal = $true; break } }
        if ($s.IndexOfAny([char[]]@('?', '[', ']', '\', '/', '`')) -ge 0 -or -not $literal) {
            throw "events.json: Feld '$Name' enthaelt ein ungueltiges Muster ('$s'): erlaubt sind $What mit mindestens einem Buchstaben, einer Ziffer oder '$', '*' als einziger Platzhalter."
        }
    }
    return , $list
}

function Get-WorkerPerfEventAccountPatterns($Json, [string]$Path) {
    # Account names that are never a person (service and virtual accounts, computer accounts). The domain is cut off
    # before matching. Without the list the built-in one applies, so SYSTEM never counts as a person.
    return , (Get-WorkerPerfEventNamePatterns $Json 'nonPersonAccounts' $Path $script:WorkerPerfDefaultNonPersonAccounts 'Kontonamen ohne Domaene')
}

function Test-WorkerPerfNamePattern([string]$Name, [string[]]$Patterns) {
    # $true when the name (compared without regard to case) matches one of the patterns of a name list.
    foreach ($p in $Patterns) { if ($Name -like $p) { return $true } }
    return $false
}

function Read-WorkerPerfEventConfig([string]$Path) {
    $json = ConvertFrom-WorkerPerfJsonFile $Path
    $logs = [ordered]@{}
    $n = 0
    foreach ($l in (Get-WorkerPerfJsonList $json 'logs' $Path)) {
        $n++
        $id = [string](Get-WorkerPerfField $l 'id')
        if ([string]::IsNullOrWhiteSpace($id)) { throw "events.json: Protokoll $n (): Feld 'id' fehlt." }
        if ($logs.Contains($id)) { throw "events.json: Protokoll $n ($id): Feld 'id' ist doppelt vorhanden." }
        $names = @()
        foreach ($s in @(Get-WorkerPerfField $l 'names')) {
            if ($s -isnot [string] -or [string]::IsNullOrWhiteSpace($s)) { throw "events.json: Protokoll $n ($id): Feld 'names' enthaelt einen Eintrag, der kein Text ist." }
            $names += $s
        }
        if ($names.Count -eq 0) { throw "events.json: Protokoll $n ($id): Feld 'names' fehlt oder ist leer." }
        $lookback = Get-WorkerPerfField $l 'lookback'
        if ($lookback -isnot [bool]) { throw "events.json: Protokoll $n ($id): Feld 'lookback' muss true oder false sein." }
        $logs[$id] = @{ Id = $id; Names = [string[]]$names; Lookback = $lookback }
    }

    $entries = New-Object System.Collections.Generic.List[object]
    $index = @{}
    $n = 0
    foreach ($e in (Get-WorkerPerfJsonList $json 'events' $Path)) {
        $n++
        $provider = [string](Get-WorkerPerfField $e 'provider')
        $idsValue = Get-WorkerPerfField $e 'ids'
        $allIds = ($idsValue -is [string] -and $idsValue -eq '*')
        $rawIds = $(if ($null -eq $idsValue -or $allIds) { @() } else { @($idsValue) })
        $shown = $(if ($allIds) { '*' } else { ($rawIds | ForEach-Object { [string]$_ }) -join ', ' })
        $where = "events.json: Eintrag $n ($provider $shown)"
        $log = [string](Get-WorkerPerfField $e 'log')
        if (-not $logs.Contains($log)) { throw "$where`: Feld 'log' verweist auf kein bekanntes Protokoll ('$log')." }
        if ([string]::IsNullOrWhiteSpace($provider)) { throw "$where`: Feld 'provider' fehlt." }
        # the event log query writes the name as an XPath literal in ' (XPath 1.0 has no escape inside a literal)
        if ($provider.IndexOf("'") -ge 0) { throw "$where`: Feld 'provider' darf kein ' enthalten." }
        $ids = New-Object System.Collections.Generic.List[int]
        foreach ($raw in $rawIds) {
            $i = ConvertTo-WorkerPerfEventInt $raw
            if ($null -eq $i) { throw "$where`: Feld 'ids' enthaelt keine ganze Zahl ('$raw')." }
            $ids.Add($i)
        }
        if ($ids.Count -eq 0 -and -not $allIds) { throw "$where`: Feld 'ids' fehlt oder ist leer." }
        # levels: optional; required with "ids": "*", which takes every event of the provider at these levels
        $levels = New-Object System.Collections.Generic.List[int]
        $levelProp = $null
        if ($null -ne $e) { $levelProp = $e.PSObject.Properties['levels'] }
        $levelNames = @()
        if ($null -ne $levelProp -and $null -ne $levelProp.Value) { $levelNames = @($levelProp.Value) }
        foreach ($ln in $levelNames) {
            if ($ln -isnot [string]) { throw "$where`: Feld 'levels' enthaelt einen Eintrag, der kein Text ist ('$ln')." }
            if (@($script:WorkerPerfEventLevels.Keys) -cnotcontains $ln) {
                throw "$where`: Feld 'levels' enthaelt eine unbekannte Ebene ('$ln'); erlaubt sind critical, error, warning und information."
            }
            foreach ($lv in $script:WorkerPerfEventLevels[$ln]) { if (-not $levels.Contains($lv)) { $levels.Add($lv) } }
        }
        if ($allIds -and $levels.Count -eq 0) { throw "$where`: Feld 'ids' ist '*' ohne Feld 'levels'; alle Kennungen einer Quelle nur mit den Ebenen, die gelesen werden." }
        $group = [string](Get-WorkerPerfField $e 'group')
        if ($script:WorkerPerfEventGroups -cnotcontains $group) { throw "$where`: Feld 'group' ist ungueltig ('$group')." }
        $kind = [string](Get-WorkerPerfField $e 'kind')
        if ($script:WorkerPerfEventKinds -cnotcontains $kind) { throw "$where`: Feld 'kind' ist ungueltig ('$kind')." }
        $fields = @{}
        $rawFields = Get-WorkerPerfField $e 'fields'
        if ($null -ne $rawFields) {
            if ($rawFields -isnot [pscustomobject]) { throw "$where`: Feld 'fields' muss ein Objekt sein." }
            foreach ($p in $rawFields.PSObject.Properties) {
                if ($script:WorkerPerfEventFieldKeys -cnotcontains $p.Name) { throw "$where`: Feld 'fields.$($p.Name)' ist kein bekannter Feldschluessel." }
                $ref = $p.Value
                $format = $(if ($p.Name -eq 'processStart') { 'filetime' } else { 'decimal' })
                $label = "fields.$($p.Name)"
                if ($ref -is [pscustomobject]) {
                    # object form: { "field": <reference or list>, "format": "hex" | "decimal" }, the format only for the numeric keys
                    $fmt = Get-WorkerPerfField $ref 'format'
                    if ($null -ne $fmt) {
                        if ($script:WorkerPerfEventNumberKeys -cnotcontains $p.Name) { throw "$where`: Feld 'fields.$($p.Name).format' ist nur fuer pid und session erlaubt." }
                        if ($fmt -isnot [string] -or @('hex', 'decimal') -cnotcontains $fmt) { throw "$where`: Feld 'fields.$($p.Name).format' muss 'hex' oder 'decimal' sein." }
                        $format = $fmt
                    }
                    $prop = $ref.PSObject.Properties['field']
                    $ref = $(if ($null -eq $prop) { $null } else { $prop.Value })
                    $label = "fields.$($p.Name).field"
                }
                elseif ($ref -isnot [string] -and $ref -isnot [object[]]) {
                    throw "$where`: Feld 'fields.$($p.Name)' muss ein Datenname, '#n', 'binary:utf16', eine Liste davon oder ein Objekt mit 'field' sein."
                }
                $fields[$p.Name] = @{ Field = (Get-WorkerPerfEventFieldReferences $ref $where $label); Format = $format }
            }
        }
        $keys = @($ids | ForEach-Object { "$log|$($provider.ToLowerInvariant())|$_" })
        if ($allIds) { $keys = @("$log|$($provider.ToLowerInvariant())|*") }
        $seen = @{}
        foreach ($key in $keys) {
            if ($index.ContainsKey($key) -or $seen.ContainsKey($key)) {
                if ($allIds) { throw "$where`: Feld 'ids' ist '*' fuer Protokoll und Quelle doppelt vorhanden." }
                throw "$where`: Feld 'ids' enthaelt die doppelte Kennung $($key.Substring($key.LastIndexOf('|') + 1)) fuer Protokoll und Quelle."
            }
            $seen[$key] = $true
        }
        $entry = [pscustomobject]@{ log = $log; provider = $provider; ids = $ids.ToArray(); allIds = $allIds; levels = $levels.ToArray(); group = $group; kind = $kind; fields = $fields }
        foreach ($key in $keys) { $index[$key] = $entry }
        $entries.Add($entry)
    }

    $codes = @{}
    $n = 0
    $rawCodes = Get-WorkerPerfField $json 'errorCodes'
    if ($null -ne $rawCodes) {
        foreach ($c in @($rawCodes)) {
            $n++
            $code = [string](Get-WorkerPerfField $c 'code')
            $text = [string](Get-WorkerPerfField $c 'text')
            if ([string]::IsNullOrWhiteSpace($code)) { throw "events.json: Fehlercode $n (): Feld 'code' fehlt." }
            if ([string]::IsNullOrWhiteSpace($text)) { throw "events.json: Fehlercode $n ($code): Feld 'text' fehlt." }
            $codeKey = Format-WorkerPerfErrorCode $code
            if ($codes.ContainsKey($codeKey)) { throw "events.json: Fehlercode $n ($code): Feld 'code' ist doppelt vorhanden (gleich nach der Vereinheitlichung wie '$codeKey')." }
            $codes[$codeKey] = $text
        }
    }

    return @{
        Logs              = $logs
        Entries           = $entries.ToArray()
        ImportantServices = (Get-WorkerPerfEventStringList $json 'importantServices' $Path)
        SystemModules     = (Get-WorkerPerfEventNamePatterns $json 'systemModules' $Path @() 'Dateinamen ohne Pfad')
        NoModules         = (Get-WorkerPerfEventNamePatterns $json 'noModules' $Path $script:WorkerPerfDefaultNoModules 'Dateinamen ohne Pfad')
        PrintProcesses    = (Get-WorkerPerfEventStringList $json 'printProcesses' $Path)
        PrintServices     = (Get-WorkerPerfEventStringList $json 'printServices' $Path)
        NonPersonAccounts = (Get-WorkerPerfEventAccountPatterns $json $Path)
        NonPersonDomains  = (Get-WorkerPerfEventNamePatterns $json 'nonPersonDomains' $Path $script:WorkerPerfDefaultNonPersonDomains 'Domaenennamen')
        ErrorCodes        = $codes
        Index             = $index
    }
}

function Get-WorkerPerfEventFieldReferences($Value, [string]$Where, [string]$Label) {
    # A field reference of events.json: a data name, '#n' or 'binary:utf16', or a list of them (alternatives: the first
    # that gives a non-empty value wins). Returns the alternatives as string[].
    $list = @()
    if ($Value -is [string]) { $list = @($Value) }
    elseif ($Value -is [object[]]) { $list = @($Value) }
    if ($list.Count -eq 0) { throw "$Where`: Feld '$Label' muss ein Datenname, '#n', 'binary:utf16' oder eine nicht leere Liste davon sein." }
    foreach ($r in $list) {
        if ($r -isnot [string] -or [string]::IsNullOrWhiteSpace($r)) { throw "$Where`: Feld '$Label' muss ein Datenname, '#n', 'binary:utf16' oder eine nicht leere Liste davon sein." }
        if ($r.StartsWith('#') -and $r -notmatch '^#\d+$') { throw "$Where`: Feld '$Label' hat eine ungueltige Position ('$r')." }
    }
    return , [string[]]$list
}

function Test-WorkerPerfEventEntryLevel($Entry, $Level) {
    # $true when the entry takes an event of this Level: an entry without levels takes every level, one with levels only
    # a known Level that is one of them.
    $levels = @(Get-WorkerPerfField $Entry 'levels')
    if ($levels.Count -eq 0) { return $true }
    return ($null -ne $Level -and $levels -contains [int]$Level)
}

function Resolve-WorkerPerfEventEntry($Config, [string]$LogId, [string]$Provider, [int]$EventId, $Level = $null) {
    # The catalogue entry of an event: by log, provider and id, else the entry with "ids": "*" of log and provider. An
    # entry with levels takes the event only when its Level is one of them ($null: level unknown, no match); an id entry
    # whose levels do not match leaves the event to the "*" entry.
    $p = $Provider.ToLowerInvariant()
    foreach ($key in "$LogId|$p|$EventId", "$LogId|$p|*") {
        if (-not $Config.Index.ContainsKey($key)) { continue }
        $entry = $Config.Index[$key]
        if (Test-WorkerPerfEventEntryLevel $entry $Level) { return $entry }
    }
    return $null
}

function ConvertFrom-WorkerPerfEventXml([string]$Xml) {
    $doc = New-Object System.Xml.XmlDocument
    $doc.XmlResolver = $null
    try { $doc.LoadXml($Xml) } catch { return $null }
    $ns = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
    $ns.AddNamespace('e', 'http://schemas.microsoft.com/win/2004/08/events/event')
    $provider = ''
    $node = $doc.SelectSingleNode('//e:System/e:Provider', $ns)
    if ($null -eq $node) { return $null }   # not an event of the Windows event namespace
    if ($null -ne $node -and $null -ne $node.Attributes['Name']) { $provider = $node.Attributes['Name'].Value }
    $eventId = 0
    $node = $doc.SelectSingleNode('//e:System/e:EventID', $ns)
    if ($null -ne $node) { [void][int]::TryParse($node.InnerText.Trim(), [ref]$eventId) }
    $level = 0
    $node = $doc.SelectSingleNode('//e:System/e:Level', $ns)
    if ($null -ne $node) { [void][int]::TryParse($node.InnerText.Trim(), [ref]$level) }

    $named = @{}
    $positional = New-Object System.Collections.Generic.List[string]
    foreach ($d in $doc.SelectNodes('//e:EventData/e:Data', $ns)) {
        $positional.Add($d.InnerText)
        $nameAttr = $d.Attributes['Name']
        if ($null -ne $nameAttr -and -not $named.ContainsKey($nameAttr.Value)) { $named[$nameAttr.Value] = $d.InnerText }
    }
    foreach ($u in $doc.SelectNodes('//*[local-name()="UserData"]/*')) {
        $children = @($u.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element })
        if ($children.Count -eq 0) { $children = @($u) }
        foreach ($c in $children) {
            $positional.Add($c.InnerText)
            if (-not $named.ContainsKey($c.LocalName)) { $named[$c.LocalName] = $c.InnerText }
        }
    }
    $binary = ''
    $node = $doc.SelectSingleNode('//e:EventData/e:Binary', $ns)
    if ($null -ne $node) { $binary = $node.InnerText.Trim() }
    # the account Windows writes into the System part (a SID); Resolve-WorkerPerfWellKnownSid or the data source names it
    $userSid = ''
    $node = $doc.SelectSingleNode('//e:System/e:Security', $ns)
    if ($null -ne $node -and $null -ne $node.Attributes['UserID']) { $userSid = $node.Attributes['UserID'].Value.Trim() }

    return @{ Provider = $provider; EventId = $eventId; Level = $level; Named = $named; Positional = $positional.ToArray(); Binary = $binary; UserSid = $userSid }
}

function ConvertFrom-WorkerPerfHexUtf16([string]$Hex) {
    # Hex string of UTF-16LE bytes -> text up to the first NUL character; '' when it is not valid hex.
    if ([string]::IsNullOrEmpty($Hex) -or ($Hex.Length % 2) -ne 0 -or $Hex -notmatch '^[0-9a-fA-F]+$') { return '' }
    $bytes = New-Object byte[] ($Hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($Hex.Substring(2 * $i, 2), 16) }
    $text = [Text.Encoding]::Unicode.GetString($bytes)
    $nul = $text.IndexOf([char]0)
    if ($nul -ge 0) { $text = $text.Substring(0, $nul) }
    return $text.Trim()
}

function Get-WorkerPerfEventFieldValue($Parsed, $Reference) {
    # The value of a field reference (one, or a list of alternatives: the first non-empty value wins); '' when the
    # event carries none of them.
    foreach ($ref in @($Reference)) {
        $r = [string]$ref
        if ([string]::IsNullOrEmpty($r)) { continue }
        $value = $null
        if ($r -eq 'binary:utf16') { $value = ConvertFrom-WorkerPerfHexUtf16 $Parsed.Binary }
        elseif ($r -match '^#(\d+)$') {
            $pos = [int]$Matches[1]
            if ($pos -lt @($Parsed.Positional).Count) { $value = $Parsed.Positional[$pos] }
        }
        elseif ($Parsed.Named.ContainsKey($r)) { $value = $Parsed.Named[$r] }
        if ($null -eq $value) { continue }
        $text = ([string]$value).Trim()
        if ($text.Length -gt 0) { return $text }
    }
    return ''
}

function ConvertFrom-WorkerPerfEventFileTime([string]$Text) {
    # A FILETIME written as hex (with or without 0x, as Application Error 1000 writes the start time of the faulting
    # process) -> UTC time; $null for anything else, also 0 and values outside the calendar.
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $t = $Text.Trim()
    if ($t -match '^0[xX]([0-9a-fA-F]{1,16})$') { $t = $Matches[1] }
    elseif ($t -notmatch '^[0-9a-fA-F]{1,16}$') { return $null }
    $v = [int64]0
    if (-not [int64]::TryParse($t, [Globalization.NumberStyles]::AllowHexSpecifier, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { return $null }
    if ($v -le 0 -or $v -gt [datetime]::MaxValue.ToFileTimeUtc()) { return $null }
    return [datetime]::FromFileTimeUtc($v)
}

function Resolve-WorkerPerfWellKnownSid([string]$Sid) {
    # SYSTEM, LOCAL SERVICE, NETWORK SERVICE for their SIDs, whatever the language of Windows; '' for any other SID.
    if ([string]::IsNullOrEmpty($Sid)) { return '' }
    $name = $script:WorkerPerfWellKnownSids[$Sid.Trim().ToUpperInvariant()]
    if ($null -eq $name) { return '' }
    return [string]$name
}

function ConvertTo-WorkerPerfEventAccountName([string]$Account, $Config) {
    # The account of an event's System part as an event user: without its domain, as a session names its user, except
    # when the domain is one of nonPersonDomains (NT SERVICE\..., Window Manager\...): it stays, so the account is
    # never taken for a person.
    if ([string]::IsNullOrEmpty($Account)) { return '' }
    $a = $Account.Trim()
    $cut = $a.LastIndexOf('\')
    if ($cut -lt 0) { return $a }
    $domain = $a.Substring(0, $cut)
    $domains = Get-WorkerPerfField $Config 'NonPersonDomains'
    if ($null -eq $domains) { $domains = $script:WorkerPerfDefaultNonPersonDomains }
    if ($domain.Length -gt 0 -and (Test-WorkerPerfNamePattern $domain ([string[]]@($domains)))) { return $a }
    return $a.Substring($cut + 1)
}

function ConvertTo-WorkerPerfEventNumber([string]$Text, [string]$Format = 'decimal') {
    # Number of a process or session id; the format comes from events.json and is never guessed from the text.
    # 'decimal': digits, or hex with a 0x prefix. 'hex': hex digits with or without 0x. Anything else -> $null.
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $t = $Text.Trim()
    $v = [int64]0
    $ok = $false
    $hexStyle = [Globalization.NumberStyles]::AllowHexSpecifier
    $inv = [Globalization.CultureInfo]::InvariantCulture
    if ($t -match '^0[xX]([0-9a-fA-F]+)$') { $ok = [int64]::TryParse($Matches[1], $hexStyle, $inv, [ref]$v) }
    elseif ($Format -eq 'hex' -and $t -match '^[0-9a-fA-F]+$') { $ok = [int64]::TryParse($t, $hexStyle, $inv, [ref]$v) }
    elseif ($Format -ne 'hex' -and $t -match '^\d+$') { $ok = [int64]::TryParse($t, [ref]$v) }
    if (-not $ok -or $v -lt 0 -or $v -gt [int]::MaxValue) { return $null }
    return [int]$v
}

function Format-WorkerPerfErrorCode([string]$Code) {
    if ([string]::IsNullOrWhiteSpace($Code)) { return '' }
    $t = $Code.Trim()
    $v = [uint32]0
    if ($t -match '^0[xX]([0-9a-fA-F]{1,8})$') {
        $v = [Convert]::ToUInt32($Matches[1], 16)
        return '0x' + $v.ToString('x8')
    }
    if ($t -match '^[0-9a-fA-F]{8}$') { return '0x' + $t.ToLowerInvariant() }
    if ($t -match '^\d{9,10}$' -and [uint32]::TryParse($t, [ref]$v)) { return '0x' + $v.ToString('x8') }
    return $t
}

function Get-WorkerPerfEventText([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $first = ($Text.Trim() -split "\r?\n")[0].Trim()
    if ($first.Length -gt 300) { $first = $first.Substring(0, 300) }
    return $first
}

function ConvertTo-WorkerPerfEventRecord($Entry, $Parsed, [datetime]$Time, [string]$Message) {
    # User comes from the data fields; a data source fills an empty User from Parsed.UserSid (the account Windows wrote
    # into the System part, see ConvertTo-WorkerPerfEventAccountName).
    if ($null -eq $Entry -or $null -eq $Parsed) { return $null }
    $f = $Entry.fields
    $get = {
        param($key)
        if ($f.ContainsKey($key)) { return (Get-WorkerPerfEventFieldValue $Parsed $f[$key].Field) }
        return ''
    }
    $fmt = {
        param($key)
        if ($f.ContainsKey($key)) { return $f[$key].Format }
        return 'decimal'
    }
    $user = & $get 'user'
    $slash = $user.LastIndexOf('\')
    if ($slash -ge 0) { $user = $user.Substring($slash + 1) }
    return [pscustomobject]@{
        Time          = $Time
        Log           = $Entry.log
        Source        = $Parsed.Provider
        EventId       = $Parsed.EventId
        Level         = $Parsed.Level
        Group         = $Entry.group
        Kind          = $Entry.kind
        App           = (& $get 'app')
        AppVersion    = (& $get 'appVersion')
        Module        = (& $get 'module')
        ModuleVersion = (& $get 'moduleVersion')
        Code          = (Format-WorkerPerfErrorCode (& $get 'code'))
        Pid           = (ConvertTo-WorkerPerfEventNumber (& $get 'pid') (& $fmt 'pid'))
        SessionId     = (ConvertTo-WorkerPerfEventNumber (& $get 'session') (& $fmt 'session'))
        User          = $user
        Printer       = (& $get 'printer')
        Driver        = (& $get 'driver')
        Service       = (& $get 'service')
        Object        = (& $get 'object')
        Text          = (Get-WorkerPerfEventText $Message)
        # start time of the process the event names (UTC), so that a reused process id is not taken for a newer process
        ProcessStart  = (ConvertFrom-WorkerPerfEventFileTime (& $get 'processStart'))
    }
}

# Block "events" of thresholds.json: JSON field -> setting and its default. Count settings must be whole numbers.
$script:WorkerPerfEventSettingFields = @(
    @{ Field = 'eventGroupMinutes'; Name = 'GroupMinutes'; Default = 30; Whole = $false }
    @{ Field = 'resourceMinutes'; Name = 'ResourceMinutes'; Default = 5; Whole = $false }
    @{ Field = 'afterhangMinutes'; Name = 'AfterhangMinutes'; Default = 2; Whole = $false }
    @{ Field = 'companionMinutes'; Name = 'CompanionMinutes'; Default = 2; Whole = $false }
    @{ Field = 'manyUsers'; Name = 'ManyUsers'; Default = 3; Whole = $true }
    @{ Field = 'oneUserEvents'; Name = 'OneUserEvents'; Default = 3; Whole = $true })

function Read-WorkerPerfEventSettings([string]$Path) {
    # Settings of the event evaluation from the block "events" of a threshold file. A missing block or field (or null)
    # takes the default, so a custom thresholds.json written before this block still works; a value that is no
    # positive number stops with the field name.
    $json = ConvertFrom-WorkerPerfJsonFile $Path
    $block = Get-WorkerPerfField $json 'events'
    if ($null -ne $block -and $block -isnot [pscustomobject]) { throw "Schwellwert 'events': der Block muss ein Objekt sein (Datei '$Path')." }
    $out = @{}
    foreach ($f in $script:WorkerPerfEventSettingFields) {
        # read the property itself: a function result would unroll a one-element list into its element
        $prop = $null
        if ($null -ne $block) { $prop = $block.PSObject.Properties[$f.Field] }
        if ($null -eq $prop -or $null -eq $prop.Value) { $out[$f.Name] = $f.Default; continue }
        $raw = $prop.Value
        if ($raw -is [System.Collections.IEnumerable] -and $raw -isnot [string]) { throw "Schwellwert 'events': Feld '$($f.Field)' ist keine Zahl ('Liste')." }
        $v = ConvertTo-WorkerPerfThresholdNumber $raw 'events' $f.Field
        if ($v -le 0) { throw "Schwellwert 'events': Feld '$($f.Field)' muss groesser als 0 sein ('$raw')." }
        if ($f.Whole) {
            if ($v -ne [Math]::Floor($v)) { throw "Schwellwert 'events': Feld '$($f.Field)' muss eine ganze Zahl sein ('$raw')." }
            if ($v -gt [int]::MaxValue) { throw "Schwellwert 'events': Feld '$($f.Field)' ist zu gross ('$raw')." }
            $v = [int]$v
        }
        $out[$f.Name] = $v
    }
    return $out
}
