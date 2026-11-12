#Requires -Version 5.1
# Shared constants and helpers for the WorkerPerf collector and report generator.
# Dot-source this file; it only defines variables and functions and runs nothing.

$script:WorkerPerfFormatVersion = 3
# Formats the report reads. Format 2 has the short events.csv (Timestamp,Source,EventId,Kind,Text) and none of the files
# events_before.csv, printdrivers.csv and printqueues.csv; the loader reads each file by its own header line.
$script:WorkerPerfReadableFormats = @(2, 3)

# File name -> header line of the capture format. The only source for file names and headers.
$script:WorkerPerfHeaders = [ordered]@{
    'ticks.csv'           = 'T,Timestamp,ElapsedSec,CpuPct,ProcQueue,StealPct,MemAvailMB,MemCommittedMB,MemCommitLimitMB,PagesInPerSec,DiskReadBps,DiskWriteBps,DiskReadIops,DiskWriteIops,DiskQueue,NetRecvBps,NetSentBps,Burst,CollectMs'
    'volumes.csv'         = 'T,Volume,Kind,SessionId,Backing,ReadLatMs,WriteLatMs,ReadOps,WriteOps,ReadBps,WriteBps,Queue'
    'shares.csv'          = 'T,Share,ReadLatMs,WriteLatMs,ReadOps,WriteOps,ReadBps,WriteBps'
    'inputdelay.csv'      = 'T,SessionId,DelayMs'
    'inputdelay_proc.csv' = 'T,SessionId,Pid,Name,DelayMs'
    'citrix.csv'          = 'T,Source,SessionId,Instance,Metric,Value'
    'probes.csv'          = 'T,Name,Role,Host,Port,ConnectMs,Error'
    'events.csv'          = 'Timestamp,Log,Source,EventId,Level,Group,Kind,App,AppVersion,Module,ModuleVersion,Code,Pid,SessionId,User,Printer,Driver,Service,Object,Text'
    'events_before.csv'   = 'Timestamp,Log,Source,EventId,Level,Group,Kind,App,AppVersion,Module,ModuleVersion,Code,Pid,SessionId,User,Printer,Driver,Service,Object,Text'
    'snapshots.csv'       = 'P,T,Timestamp,ElapsedSec,Kind,Sessions,ActiveSessions,Processes,RowsWritten,CollectMs'
    'sessions.csv'        = 'P,SessionId,User,Domain,State,WinStation,ClientName,LogonTime,IdleSec'
    'procinfo.csv'        = 'K,Pid,ParentPid,Name,SessionId,StartTime,Path,Services,CommandLine'
    'processes.csv'       = 'P,K,CpuMs,WsKB,PrivKB,ReadBytes,WriteBytes,IoOps,Handles,Threads'
    'procend.csv'         = 'P,K'
    'printdrivers.csv'    = 'Name,Manufacturer,Version,Type,Isolation,Files'
    'printqueues.csv'     = 'Timestamp,Queue,Jobs,JobErrors,NotReadyErrors'
}

# Measurement categories that -Skip leaves out, in this order: name -> files, sources (ids in meta.json Sources) and
# places of the report. The sources events.<id> belong to Ereignisse and Rueckblick together. A category that is not
# active is accepted by -Skip and has no effect. Everything else is the base: ticks.csv, inputdelay.csv, snapshots.csv,
# sessions.csv, meta.json and thresholds.json.
$script:WorkerPerfCategories = [ordered]@{
    'Prozesse'     = @{ Files = @('processes.csv', 'procinfo.csv', 'procend.csv', 'inputdelay_proc.csv'); Sources = @('process', 'input.process')
        Places = @('procs', 'apps', 'sessions.resources', 'incidents.contributors', 'incidents.delayProcs', 'print.processes'); Active = $true }
    'Laufwerke'    = @{ Files = @('volumes.csv', 'shares.csv'); Sources = @('disk.latency', 'smb.latency', 'profile.map')
        Places = @('volumes', 'shares', 'sessions.profile'); Active = $true }
    'Citrix'       = @{ Files = @('citrix.csv'); Sources = @('ica.rtt', 'ica.latency'); Places = @('citrix', 'sessions.rtt', 'incidents.ica'); Active = $true }
    'Ereignisse'   = @{ Files = @('events.csv'); Sources = @(); Places = @('events', 'sessions.events', 'incidents.events'); Active = $true }
    'Rueckblick'   = @{ Files = @('events_before.csv'); Sources = @(); Places = @('before'); Active = $true }
    'Drucken'      = @{ Files = @('printdrivers.csv', 'printqueues.csv'); Sources = @('print.drivers', 'print.queues')
        Places = @('print.drivers', 'print.queues'); Active = $true }
    'Gegenstellen' = @{ Files = @('probes.csv'); Sources = @('probe.connect'); Places = @('probes', 'incidents.endpoints'); Active = $true }
    'Zustand'      = @{ Files = @(); Sources = @(); Places = @(); Active = $false }
}
# The note in Sources of a source that -Skip left out
$script:WorkerPerfSkipDetailPattern = '^abgeschaltet \(-Skip [A-Za-z]+(,[A-Za-z]+)*\)$'

$script:WorkerPerfOrigins = @('Herstellerangabe', 'Faustregel', 'eigene Annahme')
$script:WorkerPerfRoleNames = @('Hauptanwendung', 'Sicherheit', 'Profil', 'Citrix', 'Drucken', 'System')

function Test-WorkerPerfWindows {
    return [bool](($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows)
}

function Format-WorkerPerfNumber($Value, [int]$Decimals = 1) {
    if ($null -eq $Value) { return '' }
    $d = [double]$Value
    if ([double]::IsNaN($d) -or [double]::IsInfinity($d)) { return '' }
    return [Math]::Round($d, $Decimals).ToString([Globalization.CultureInfo]::InvariantCulture)
}

function Format-WorkerPerfCsvText([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $t = $Text.Replace("`r", ' ').Replace("`n", ' ')
    if ($t.IndexOfAny([char[]]@(',', '"')) -ge 0) { return '"' + $t.Replace('"', '""') + '"' }
    return $t
}

function Split-WorkerPerfCsvLine([string]$Line) {
    if ($Line.IndexOf('"') -lt 0) { return $Line.Split(',') }
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
    return $out.ToArray()
}

function ConvertFrom-WorkerPerfJsonFile([string]$Path) {
    # Reads a JSON file explicitly as UTF-8; any failure names the file.
    try {
        $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
        return ($text | ConvertFrom-Json)
    }
    catch {
        throw "Datei '$Path' ist nicht lesbar oder kein gueltiges JSON: $($_.Exception.Message)"
    }
}

function Get-WorkerPerfField($Object, [string]$Name) {
    # Strict-mode safe field access for pscustomobject, hashtable and $null; returns $null when missing.
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Set-WorkerPerfDefault($Object, [string]$Name, $Default) {
    # Adds a missing (or null) property so that dot-access works under strict mode.
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { Add-Member -InputObject $Object -MemberType NoteProperty -Name $Name -Value $Default }
    elseif ($null -eq $p.Value) { $p.Value = $Default }
}

function Get-WorkerPerfJsonList($Json, [string]$ListName, [string]$Path) {
    $list = Get-WorkerPerfField $Json $ListName
    if ($null -eq $list) { throw "Datei '$Path' enthaelt keine Liste '$ListName'." }
    return , @($list)
}

function ConvertTo-WorkerPerfThresholdNumber($Value, [string]$Id, [string]$Field) {
    # Number of a threshold entry: a JSON number, or a text with decimal point ("10.5"). Anything else, also a decimal
    # comma ("10,5" would silently become 105), stops with the entry and the field.
    $d = [double]::NaN
    if ($Value -is [string]) {
        if (-not [double]::TryParse($Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { $d = [double]::NaN }
    }
    elseif ($Value -is [ValueType] -and $Value -isnot [bool] -and $Value -isnot [char]) { $d = [double]$Value }
    if ([double]::IsNaN($d) -or [double]::IsInfinity($d)) {
        $shown = [string]$Value
        if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) { $shown = 'Liste' }
        throw "Schwellwert '$Id': Feld '$Field' ist keine Zahl ('$shown'). Erlaubt sind Zahlen mit Dezimalpunkt, z. B. 10.5."
    }
    return $d
}

function Read-WorkerPerfThresholds([string]$Path) {
    $json = ConvertFrom-WorkerPerfJsonFile $Path
    $result = [ordered]@{}
    foreach ($e in (Get-WorkerPerfJsonList $json 'thresholds' $Path)) {
        $id = [string](Get-WorkerPerfField $e 'id')
        if ([string]::IsNullOrWhiteSpace($id)) { throw "Schwellwert ohne id in Datei '$Path'." }
        if ($result.Contains($id)) { throw "Schwellwert '$id' ist doppelt vorhanden (Datei '$Path')." }
        foreach ($f in 'label', 'unit', 'direction', 'warn', 'crit', 'ideal', 'minTicks', 'trigger', 'origin', 'source', 'url') {
            if ($null -eq (Get-WorkerPerfField $e $f)) { throw "Schwellwert '$id': Feld '$f' fehlt." }
        }
        $dir = [string]$e.direction
        if ($dir -ne 'high' -and $dir -ne 'low') { throw "Schwellwert '$id': direction muss 'high' oder 'low' sein." }
        Set-WorkerPerfDefault $e 'minOps' 0
        Set-WorkerPerfDefault $e 'note' ''
        # the numbers are checked and stored as numbers, so every later use reads the same value
        $e.warn = ConvertTo-WorkerPerfThresholdNumber $e.warn $id 'warn'
        $e.crit = ConvertTo-WorkerPerfThresholdNumber $e.crit $id 'crit'
        $minTicks = ConvertTo-WorkerPerfThresholdNumber $e.minTicks $id 'minTicks'
        if ($minTicks -ne [Math]::Floor($minTicks)) { throw "Schwellwert '$id': Feld 'minTicks' muss eine ganze Zahl sein ('$($e.minTicks)')." }
        if ($minTicks -lt 1) { throw "Schwellwert '$id': minTicks muss mindestens 1 sein." }
        $e.minTicks = [int]$minTicks
        $e.minOps = ConvertTo-WorkerPerfThresholdNumber $e.minOps $id 'minOps'
        if ($e.minOps -lt 0) { throw "Schwellwert '$id': Feld 'minOps' darf nicht negativ sein." }
        if ($dir -eq 'high' -and $e.warn -gt $e.crit) { throw "Schwellwert '$id': warn darf bei direction high nicht ueber crit liegen." }
        if ($dir -eq 'low' -and $e.warn -lt $e.crit) { throw "Schwellwert '$id': warn darf bei direction low nicht unter crit liegen." }
        if ($script:WorkerPerfOrigins -notcontains [string]$e.origin) { throw "Schwellwert '$id': origin '$($e.origin)' ist ungueltig." }
        $result[$id] = $e
    }
    return $result
}

function Read-WorkerPerfRoles([string]$Path) {
    $json = ConvertFrom-WorkerPerfJsonFile $Path
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($r in (Get-WorkerPerfJsonList $json 'roles' $Path)) {
        $label = [string](Get-WorkerPerfField $r 'label')
        if ([string]::IsNullOrWhiteSpace($label)) { throw "Rolleneintrag ohne label in Datei '$Path'." }
        if ($script:WorkerPerfRoleNames -notcontains [string](Get-WorkerPerfField $r 'role')) {
            throw "Rolleneintrag '$label': role '$(Get-WorkerPerfField $r 'role')' ist ungueltig."
        }
        Set-WorkerPerfDefault $r 'processes' @()
        Set-WorkerPerfDefault $r 'services' @()
        Set-WorkerPerfDefault $r 'modules' @()
        Set-WorkerPerfDefault $r 'note' ''
        $r.processes = @($r.processes)
        $r.services = @($r.services)
        # file name patterns of the product's modules (as processes: '*' allowed), matched against faulting modules
        $r.modules = @($r.modules)
        $out.Add($r)
    }
    return $out.ToArray()
}

function Read-WorkerPerfEndpoints([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $json = ConvertFrom-WorkerPerfJsonFile $Path
    $out = New-Object System.Collections.Generic.List[object]
    $names = @{}
    foreach ($e in (Get-WorkerPerfJsonList $json 'endpoints' $Path)) {
        $name = [string](Get-WorkerPerfField $e 'name')
        if ([string]::IsNullOrWhiteSpace($name)) { throw "Gegenstelle ohne name in Datei '$Path'." }
        if ($names.ContainsKey($name)) { throw "Gegenstelle '$name' ist doppelt vorhanden." }
        $names[$name] = $true
        if ([string]::IsNullOrWhiteSpace([string](Get-WorkerPerfField $e 'host'))) { throw "Gegenstelle '$name': host fehlt." }
        $port = 0
        if (-not [int]::TryParse([string](Get-WorkerPerfField $e 'port'), [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
            throw "Gegenstelle '$name': port muss zwischen 1 und 65535 liegen."
        }
        Set-WorkerPerfDefault $e 'role' ''
        $out.Add($e)
    }
    return $out.ToArray()
}

function Read-WorkerPerfTexts([string]$Path) {
    # Flat JSON object: key -> text.
    $json = ConvertFrom-WorkerPerfJsonFile $Path
    $texts = @{}
    foreach ($p in $json.PSObject.Properties) { $texts[$p.Name] = [string]$p.Value }
    return $texts
}

function Get-WorkerPerfStatus([double]$Value, $Threshold) {
    if ([double]::IsNaN($Value)) { return $null }
    $warn = [double]$Threshold.warn
    $crit = [double]$Threshold.crit
    if ([string]$Threshold.direction -eq 'low') {
        if ($Value -le $crit) { return 2 }
        if ($Value -le $warn) { return 1 }
        return 0
    }
    if ($Value -ge $crit) { return 2 }
    if ($Value -ge $warn) { return 1 }
    return 0
}

function Get-WorkerPerfHostSignals($Tick, [int]$LogicalProcessors, [double]$PhysicalMemoryMB) {
    $nan = [double]::NaN
    $num = {
        param($Name)
        $v = Get-WorkerPerfField $Tick $Name
        if ($null -eq $v -or ($v -is [string] -and $v -eq '')) { return $nan }
        return [double]$v
    }
    $cpu = & $num 'CpuPct'
    $queue = & $num 'ProcQueue'
    $steal = & $num 'StealPct'
    $avail = & $num 'MemAvailMB'
    $committed = & $num 'MemCommittedMB'
    $limit = & $num 'MemCommitLimitMB'
    $pagesIn = & $num 'PagesInPerSec'

    $queuePerCpu = $nan
    if ($LogicalProcessors -gt 0) { $queuePerCpu = $queue / $LogicalProcessors }
    $used = $nan
    if ($PhysicalMemoryMB -gt 0) { $used = 100 * (1 - $avail / $PhysicalMemoryMB) }
    $commit = $nan
    if ($limit -gt 0) { $commit = 100 * $committed / $limit }

    return @{
        'cpu.host'    = $cpu
        'cpu.queue'   = $queuePerCpu
        'cpu.steal'   = $steal
        'mem.used'    = $used
        'mem.commit'  = $commit
        'mem.pagesin' = $pagesIn
    }
}

function Resolve-WorkerPerfRole($Roles, [string]$ProcessName, [string]$Services, [int]$SessionId) {
    $serviceList = @()
    if (-not [string]::IsNullOrEmpty($Services)) { $serviceList = @($Services.Split(';') | Where-Object { $_ -ne '' }) }
    foreach ($r in @($Roles)) {
        $hit = $false
        foreach ($pattern in @($r.processes)) {
            if ($ProcessName -like $pattern) { $hit = $true; break }
        }
        if (-not $hit) {
            foreach ($svc in @($r.services)) {
                if ($serviceList -contains $svc) { $hit = $true; break }
            }
        }
        if ($hit) { return [pscustomobject]@{ Role = [string]$r.role; Label = [string]$r.label } }
    }
    $role = ''
    if ($SessionId -eq 0) { $role = 'System' }
    return [pscustomobject]@{ Role = $role; Label = '' }
}

function Resolve-WorkerPerfSkip([string[]]$Skip, [bool]$NoCitrix = $false, [int]$EventLookbackDays = 7) {
    # The active categories that -Skip leaves out, in the order of the table, each once. A value may hold several
    # names separated by commas; case does not matter. -NoCitrix adds Citrix, -EventLookbackDays 0 adds Rueckblick.
    $names = @($script:WorkerPerfCategories.Keys)
    $chosen = @{}
    foreach ($value in @($Skip)) {
        if ($null -eq $value) { continue }
        foreach ($part in ([string]$value).Split(',')) {
            $p = $part.Trim()
            if ($p.Length -eq 0) { continue }
            $match = @($names | Where-Object { $_ -eq $p })
            if ($match.Count -eq 0) { throw ("Unbekannte Kategorie '{0}' bei -Skip. Gueltige Werte: {1}." -f $p, ($names -join ', ')) }
            $chosen[$match[0]] = $true
        }
    }
    if ($NoCitrix) { $chosen['Citrix'] = $true }
    if ($EventLookbackDays -eq 0) { $chosen['Rueckblick'] = $true }
    foreach ($n in $names) { if ($chosen.ContainsKey($n) -and $script:WorkerPerfCategories[$n].Active) { $n } }
}

function Get-WorkerPerfSkipDetail([string[]]$Categories) {
    return 'abgeschaltet (-Skip ' + ($Categories -join ',') + ')'
}

function Set-WorkerPerfSkippedSources {
    # Marks in Sources every source of a category that -Skip left out (creating its entry when missing). The logs
    # events.<id> count as left out only when Ereignisse and Rueckblick both are: each present key events.* and each
    # events.<id> of -EventLogIds.
    param($Sources, [string[]]$Skip = @(), [string[]]$EventLogIds = @())
    foreach ($cat in @($Skip)) {
        if (-not $script:WorkerPerfCategories.Contains($cat)) { continue }
        foreach ($id in @($script:WorkerPerfCategories[$cat].Sources)) {
            $Sources[$id] = @{ Available = $false; Detail = (Get-WorkerPerfSkipDetail @($cat)) }
        }
    }
    if (@($Skip) -contains 'Ereignisse' -and @($Skip) -contains 'Rueckblick') {
        $ids = @(@($Sources.Keys) | Where-Object { ([string]$_).StartsWith('events.') }) + @(@($EventLogIds) | Where-Object { $_ } | ForEach-Object { 'events.' + $_ })
        foreach ($id in $ids) { $Sources[$id] = @{ Available = $false; Detail = (Get-WorkerPerfSkipDetail @('Ereignisse', 'Rueckblick')) } }
    }
}
