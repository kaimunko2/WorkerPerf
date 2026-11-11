#Requires -Version 5.1
# Event catalogue (events.json) and conversion of raw Windows events into records.
# Dot-source after WorkerPerf.Common.ps1; this file only defines functions and runs nothing.

$script:WorkerPerfEventGroups = @('app', 'service', 'storage', 'memory', 'fileserver', 'profile', 'print', 'session', 'security')
$script:WorkerPerfEventKinds = @('crash', 'hang', 'app-detail', 'service', 'print', 'profileerror', 'system', 'logon', 'logoff',
    'disconnect', 'reconnect', 'scan-start', 'scan-end', 'signature-update', 'applocker-block', 'info')
$script:WorkerPerfEventNumberKeys = @('pid', 'session')
$script:WorkerPerfEventFieldKeys = @('app', 'appVersion', 'module', 'moduleVersion', 'code', 'pid', 'session', 'user', 'printer', 'driver', 'service', 'object')

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
        $rawIds = @(Get-WorkerPerfField $e 'ids')
        $shown = ($rawIds | ForEach-Object { [string]$_ }) -join ', '
        $where = "events.json: Eintrag $n ($provider $shown)"
        $log = [string](Get-WorkerPerfField $e 'log')
        if (-not $logs.Contains($log)) { throw "$where`: Feld 'log' verweist auf kein bekanntes Protokoll ('$log')." }
        if ([string]::IsNullOrWhiteSpace($provider)) { throw "$where`: Feld 'provider' fehlt." }
        $ids = New-Object System.Collections.Generic.List[int]
        foreach ($raw in $rawIds) {
            $i = ConvertTo-WorkerPerfEventInt $raw
            if ($null -eq $i) { throw "$where`: Feld 'ids' enthaelt keine ganze Zahl ('$raw')." }
            $ids.Add($i)
        }
        if ($ids.Count -eq 0) { throw "$where`: Feld 'ids' fehlt oder ist leer." }
        $group = [string](Get-WorkerPerfField $e 'group')
        if ($script:WorkerPerfEventGroups -cnotcontains $group) { throw "$where`: Feld 'group' ist ungueltig ('$group')." }
        $kind = [string](Get-WorkerPerfField $e 'kind')
        if ($script:WorkerPerfEventKinds -cnotcontains $kind) { throw "$where`: Feld 'kind' ist ungueltig ('$kind')." }
        $fields = @{}
        $rawFields = Get-WorkerPerfField $e 'fields'
        if ($null -ne $rawFields) {
            foreach ($p in $rawFields.PSObject.Properties) {
                if ($script:WorkerPerfEventFieldKeys -cnotcontains $p.Name) { throw "$where`: Feld 'fields.$($p.Name)' ist kein bekannter Feldschluessel." }
                $ref = $p.Value
                $format = 'decimal'
                if ($ref -is [string]) { $refText = $ref }
                else {
                    # object form: { "field": <reference>, "format": "hex" | "decimal" }, only for the numeric keys
                    $refText = Get-WorkerPerfField $ref 'field'
                    $fmt = Get-WorkerPerfField $ref 'format'
                    if ($null -ne $fmt) {
                        if ($script:WorkerPerfEventNumberKeys -cnotcontains $p.Name) { throw "$where`: Feld 'fields.$($p.Name).format' ist nur fuer pid und session erlaubt." }
                        if ($fmt -isnot [string] -or @('hex', 'decimal') -cnotcontains $fmt) { throw "$where`: Feld 'fields.$($p.Name).format' muss 'hex' oder 'decimal' sein." }
                        $format = $fmt
                    }
                    if ($refText -isnot [string] -or [string]::IsNullOrWhiteSpace($refText)) { throw "$where`: Feld 'fields.$($p.Name).field' muss ein Datenname, '#n' oder 'binary:utf16' sein." }
                }
                if ($refText -isnot [string] -or [string]::IsNullOrWhiteSpace($refText)) { throw "$where`: Feld 'fields.$($p.Name)' muss ein Datenname, '#n' oder 'binary:utf16' sein." }
                if ($refText.StartsWith('#') -and $refText -notmatch '^#\d+$') { throw "$where`: Feld 'fields.$($p.Name)' hat eine ungueltige Position ('$refText')." }
                $fields[$p.Name] = @{ Field = $refText; Format = $format }
            }
        }
        foreach ($i in $ids) {
            $key = "$log|$($provider.ToLowerInvariant())|$i"
            if ($index.ContainsKey($key)) { throw "$where`: Feld 'ids' enthaelt die doppelte Kennung $i fuer Protokoll und Quelle." }
        }
        $entry = [pscustomobject]@{ log = $log; provider = $provider; ids = $ids.ToArray(); group = $group; kind = $kind; fields = $fields }
        foreach ($i in $ids) { $index["$log|$($provider.ToLowerInvariant())|$i"] = $entry }
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
            $codes[(Format-WorkerPerfErrorCode $code)] = $text
        }
    }

    return @{
        Logs              = $logs
        Entries           = $entries.ToArray()
        ImportantServices = (Get-WorkerPerfEventStringList $json 'importantServices' $Path)
        SystemModules     = (Get-WorkerPerfEventStringList $json 'systemModules' $Path)
        PrintProcesses    = (Get-WorkerPerfEventStringList $json 'printProcesses' $Path)
        PrintServices     = (Get-WorkerPerfEventStringList $json 'printServices' $Path)
        ErrorCodes        = $codes
        Index             = $index
    }
}

function Resolve-WorkerPerfEventEntry($Config, [string]$LogId, [string]$Provider, [int]$EventId) {
    $key = "$LogId|$($Provider.ToLowerInvariant())|$EventId"
    if ($Config.Index.ContainsKey($key)) { return $Config.Index[$key] }
    return $null
}

function ConvertFrom-WorkerPerfEventXml([string]$Xml) {
    $doc = New-Object System.Xml.XmlDocument
    $doc.XmlResolver = $null
    $doc.LoadXml($Xml)
    $ns = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
    $ns.AddNamespace('e', 'http://schemas.microsoft.com/win/2004/08/events/event')
    $provider = ''
    $node = $doc.SelectSingleNode('//e:System/e:Provider', $ns)
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

    return @{ Provider = $provider; EventId = $eventId; Level = $level; Named = $named; Positional = $positional.ToArray(); Binary = $binary }
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

function Get-WorkerPerfEventFieldValue($Parsed, [string]$Reference) {
    # '' when the event does not carry the field.
    if ([string]::IsNullOrEmpty($Reference)) { return '' }
    if ($Reference -eq 'binary:utf16') { return (ConvertFrom-WorkerPerfHexUtf16 $Parsed.Binary) }
    $value = $null
    if ($Reference -match '^#(\d+)$') {
        $pos = [int]$Matches[1]
        if ($pos -lt @($Parsed.Positional).Count) { $value = $Parsed.Positional[$pos] }
    }
    elseif ($Parsed.Named.ContainsKey($Reference)) { $value = $Parsed.Named[$Reference] }
    if ($null -eq $value) { return '' }
    return ([string]$value).Trim()
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
    }
}
