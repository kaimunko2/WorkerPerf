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
# active is accepted by -Skip and has no effect. Files may name a file that is not a CSV file (health.json); the writers
# come only from WorkerPerfHeaders. Everything else is the base: ticks.csv, inputdelay.csv, snapshots.csv, sessions.csv,
# meta.json and thresholds.json (apps.json, the copy of the application list, goes with Zustand without being its file).
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
    'Zustand'      = @{ Files = @('health.json'); Sources = @('health'); Places = @(); Active = $true }
}
# The note in Sources of a source that -Skip left out
$script:WorkerPerfSkipDetailPattern = '^abgeschaltet \(-Skip [A-Za-z]+(,[A-Za-z]+)*\)$'

# Health picture (health.json): read values with their state, no rating, no threshold, no German text.
$script:WorkerPerfHealthFormatVersion = 1
$script:WorkerPerfHealthAreas = @('size', 'operation', 'sessions', 'vda', 'profile', 'print', 'security', 'network', 'events', 'maintenance', 'apps')
# Keywords that Error of an area can carry besides the message of an exception: overall time limit reached, no reader,
# not read, not in the file.
$script:WorkerPerfHealthAreaErrors = @('budget', 'noReader', 'notRead', 'notInFile')
# The services the WEM agent needs, each as the list of its names; the first group is the agent service. A service belongs
# to a group when its service name or its display name is one of the group's names (case-insensitive); the list
# vda.wemServices records the name that matched, the service name first. The two Citrix services go by their documented
# display names (English in every language), the Windows service by its service name SENS: its display name is localized.
$script:WorkerPerfHealthWemServices = @(@('Citrix WEM Agent Host Service', 'Norskale Agent Host Service'),
    @('Citrix WEM User Logon Service', 'Citrix WEM Agent User Logon Service'), @('SENS'))

# The fixed list of read values, in the order of the plan's tables: id -> Area, Type, Unit, Fields (only for a list:
# field name -> type) and Documented ($false: the read source is not documented; the value is a raw value only).
# Each row: id, type, unit, fields ('Name=type, ...'), 'undocumented' where the source is not documented.
$script:WorkerPerfHealthValues = & {
    $services = 'Name=text:protected, State=text, StartMode=text'
    $policy = 'Key=text, Name=text, Value=text:free'
    $rows = @(
        @('size.cpuLogical', 'number'), @('size.cpuSockets', 'number'), @('size.memTotalMB', 'number', 'MB'),
        @('size.commitTotalMB', 'number', 'MB'), @('size.commitLimitMB', 'number', 'MB'), @('size.commitPeakMB', 'number', 'MB'),
        @('size.pagefiles', 'list', '', 'Path=text:path, AllocatedMB=number, PeakUsageMB=number, Temporary=bool'),
        @('size.pagefileManaged', 'bool'), @('size.hypervisor', 'bool'), @('size.model', 'text'),
        @('size.vmtoolsPresent', 'bool', '', '', 'undocumented'), @('size.vmtoolsService', 'text', '', '', 'undocumented'),
        @('size.vmtoolsVersion', 'text'),
        @('size.netAdapters', 'list', '', 'Name=text, Service=text, SpeedMbit=number, Enabled=bool'),
        @('size.storageControllers', 'list', '', 'Name=text, Driver=text'), @('size.balloonDriver', 'text'),

        @('operation.lastBoot', 'time'), @('operation.pendingRename', 'number'),
        @('operation.pendingServicing', 'bool', '', '', 'undocumented'), @('operation.pendingUpdate', 'bool', '', '', 'undocumented'),
        @('operation.lastUpdate', 'time'), @('operation.lastUpdateId', 'text'), @('operation.powerPlan', 'text'),
        @('operation.volumes', 'list', '', 'Drive=text, SizeGB=number, FreeGB=number, FileSystem=text, System=bool, PageFile=bool'),

        @('sessions.list', 'list', '', ('Id=number, State=text, WinStation=text:path, User=text:user, Domain=text:domain, Client=text:client, ' +
            'LogonTime=time, ConnectTime=time, DisconnectTime=time, IdleMinutes=number')),
        @('sessions.limits', 'list', '', 'Terminal=text, IdleLimitMin=number, DisconnectedLimitMin=number, ActiveLimitMin=number, BrokenAction=number, FromPolicy=bool'),
        @('sessions.localProfiles', 'list', '', 'Path=text:path, Loaded=bool, Special=bool, LastUse=time, Temporary=bool'),

        @('vda.version', 'text'), @('vda.services', 'list', '', $services), @('vda.desktopService', 'text'),
        @('vda.controllers', 'list', '', 'Entry=text:host, Kind=text, From=text'), @('vda.listOfSids', 'bool'), @('vda.farmGuid', 'bool'),
        @('vda.policyRaw', 'list', '', $policy, 'undocumented'), @('vda.persistentDataLocation', 'text:path'), @('vda.wemService', 'text'),
        @('vda.wemServices', 'list', '', $services), @('vda.wemVersion', 'text'), @('vda.wemServer', 'text:host'),
        @('vda.wemCacheLocation', 'text:path'), @('vda.wemGpNetworkTimeout', 'number', 's'), @('vda.teamsService', 'text'),
        @('vda.webSocketService', 'text'),

        @('profile.service', 'text'), @('profile.version', 'text'), @('profile.policyGpo', 'list', '', $policy, 'undocumented'),
        @('profile.policyStudio', 'list', '', $policy, 'undocumented'),
        @('profile.containers', 'list', '', ('Location=text:path, Mount=text:path, Owner=text:user, SessionId=number, SizeGB=number, ' +
            'AllocatedGB=number, VolumeSizeGB=number, VolumeFreeGB=number, UsedPct=number')),

        @('print.isolationExecution', 'number'), @('print.isolationOverride', 'number'), @('print.queueCount', 'number'),
        @('print.spooler', 'text'), @('print.spoolerStartMode', 'text'), @('print.citrixPrintService', 'text'),
        @('print.operationalLog', 'bool'), @('print.mappingClientVersion', 'text'),

        @('security.services', 'list', '', $services), @('security.defenderService', 'text'), @('security.defenderMode', 'text'),
        @('security.defenderRealTime', 'bool'), @('security.defenderTamper', 'bool'), @('security.defenderSignatureAgeDays', 'number', 'Tage'),
        @('security.defenderSignaturesOutOfDate', 'bool'), @('security.defenderVersion', 'text'),
        @('security.defenderExclusionPaths', 'list', '', 'Path=text:free'), @('security.defenderExclusionProcesses', 'list', '', 'Path=text:free'),
        @('security.defenderExclusionExtensions', 'list', '', 'Extension=text'), @('security.defenderSharedSignatures', 'text:path'),
        @('security.defenderNetworkProtection', 'number'), @('security.defenderForcePassive', 'number'), @('security.mdeOnboarding', 'number'),
        @('security.mdeService', 'text'), @('security.filters', 'list', '', 'Name=text:protected, Altitude=text, Instances=number, Legacy=bool'),
        @('security.applockerService', 'text'),
        @('security.applockerCollections', 'list', '', 'Collection=text, Enforcement=number, Rules=number', 'undocumented'),

        @('network.domainMember', 'bool'), @('network.smbRequireSigning', 'bool'), @('network.smbDirectoryCache', 'number'),
        @('network.smbFileInfoCache', 'number'), @('network.smbFileNotFoundCache', 'number'), @('network.smb1', 'text'),
        @('network.smbConnections', 'list', '', 'Share=text:share, Dialect=text, Signed=bool, Encrypted=bool, Connections=number'),
        @('network.dnsServers', 'list', '', 'Interface=number, Address=text:address'), @('network.rss', 'list', '', 'Description=text, Enabled=bool'),
        @('network.timeType', 'text'), @('network.timeServers', 'text:hosts'), @('network.timeService', 'text'),

        @('events.logs', 'list', '', ('Log=text, Present=bool, Enabled=bool, MaxSizeMB=number, FileSizeMB=number, Records=number, Mode=text, ' +
            'Full=bool, Oldest=time')),

        @('maintenance.tasks', 'list', '', ('Path=text:free, Enabled=bool, State=text, NextRun=time, LastRun=time, Triggers=text, ' +
            'RepeatMinutes=number, Action=text:free')),
        @('maintenance.taskCount', 'number'), @('maintenance.scanDay', 'number'), @('maintenance.scanTime', 'text'),
        @('maintenance.quickScanTime', 'text'), @('maintenance.scanType', 'number'), @('maintenance.scanRandomize', 'bool'),
        @('maintenance.scanCpuLoad', 'number', '%'), @('maintenance.updateOptions', 'number'), @('maintenance.updateDay', 'number'),
        @('maintenance.updateHour', 'number'), @('maintenance.updateNoRebootWithUsers', 'number'), @('maintenance.searchService', 'text'),
        @('maintenance.updateService', 'text'),

        @('apps.probes', 'list', '', 'App=text, Id=text, Kind=text, Read=text, State=text, Reason=text, Value=value, Names=text:free')
    )
    $list = [ordered]@{}
    foreach ($row in $rows) {
        $fields = $null
        if ($row.Count -gt 3 -and $row[3]) {
            $fields = [ordered]@{}
            foreach ($pair in ($row[3] -split ', ')) { $nameAndType = $pair -split '=', 2; $fields[$nameAndType[0]] = $nameAndType[1] }
        }
        $unit = ''; if ($row.Count -gt 2) { $unit = $row[2] }
        $list[$row[0]] = @{ Area = $row[0].Split('.')[0]; Type = $row[1]; Unit = $unit; Fields = $fields
            Documented = -not ($row.Count -gt 4 -and $row[4] -eq 'undocumented') }
    }
    $list
}

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
        # name patterns of the product's file system filter drivers (as processes: '*' allowed), matched against the
        # loaded filters of the health picture; only entries of the role Sicherheit are counted
        Set-WorkerPerfDefault $r 'filters' @()
        $r.filters = @($r.filters)
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

function Test-WorkerPerfSkipDetail([string]$Text) {
    # $true when the text is a note the collector writes for a left-out source, exactly: the pattern with its case,
    # nothing after it (not even a line break, which $ would let pass), and names that are active categories of the table
    # in their own spelling, each once and in the order of the table (the collector writes one name or Ereignisse,Rueckblick).
    if ($null -eq $Text -or $Text -notmatch '\A[^\r\n]*\z' -or $Text -cnotmatch $script:WorkerPerfSkipDetailPattern) { return $false }
    $active = [string[]]@($script:WorkerPerfCategories.Keys | Where-Object { $script:WorkerPerfCategories[$_].Active })
    $inner = $Text.Substring('abgeschaltet (-Skip '.Length, $Text.Length - 'abgeschaltet (-Skip '.Length - 1)
    $last = -1
    foreach ($n in $inner.Split(',')) {
        $at = [array]::IndexOf($active, $n)   # ordinal: compares with case
        if ($at -le $last) { return $false }
        $last = $at
    }
    return $true
}

function Get-WorkerPerfRecordedSkip($Value) {
    # The active categories in the field Skip of a meta.json, in the order of the table, each once: a text or a list of
    # texts, compared without regard to case. $null, unknown and inactive values are dropped without an error; a capture
    # from before -Skip has no field and so gives none.
    $given = @{}
    if ($null -ne $Value -and ($Value -is [string] -or $Value -is [System.Collections.IEnumerable])) {
        foreach ($v in @($Value)) { if ($v -is [string]) { $given[$v.Trim().ToLowerInvariant()] = $true } }
    }
    foreach ($n in @($script:WorkerPerfCategories.Keys)) {
        if ($given.ContainsKey($n.ToLowerInvariant()) -and $script:WorkerPerfCategories[$n].Active) { $n }
    }
}

function Get-WorkerPerfSkippedOut([string[]]$Skip, [hashtable]$Texts) {
    # The report entry of each left-out category: id, label and reason (texts skip.label.<id>, skip.text.<id>) and the
    # places of the report that depend on it (Places of the table). An unknown name is dropped.
    foreach ($id in @($Skip)) {
        if ($null -eq $id -or -not $script:WorkerPerfCategories.Contains([string]$id)) { continue }
        [ordered]@{ id = [string]$id; label = [string]$Texts['skip.label.' + $id]; text = [string]$Texts['skip.text.' + $id]
            places = [string[]]@($script:WorkerPerfCategories[[string]$id].Places) }
    }
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

function Test-WorkerPerfHealthNonFinite($Value) {
    # True for NaN and plus or minus infinity: Windows PowerShell 5.1 writes them unquoted, which is no valid JSON.
    return (($Value -is [double] -or $Value -is [single]) -and ([double]::IsNaN([double]$Value) -or [double]::IsInfinity([double]$Value)))
}

function ConvertTo-WorkerPerfHealthFinite($Value) {
    # The value with every number that is not finite replaced by $null, at any depth: a list stays a list (an
    # [object[]]), a table becomes an ordered table, a text stays a text.
    if ($null -eq $Value) { return $null }
    if (Test-WorkerPerfHealthNonFinite $Value) { return $null }
    if ($Value -is [string]) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $out = [ordered]@{}
        foreach ($k in @($Value.Keys)) { $out[$k] = ConvertTo-WorkerPerfHealthFinite $Value[$k] }
        return $out
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $out = [ordered]@{}
        foreach ($p in $Value.PSObject.Properties) { $out[$p.Name] = ConvertTo-WorkerPerfHealthFinite $p.Value }
        return $out
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $items = @(foreach ($item in $Value) { , (ConvertTo-WorkerPerfHealthFinite $item) })
        return , ([object[]]$items)
    }
    return $Value
}

function New-WorkerPerfHealthValue([string]$State, [string]$Reason = '', $Value = $null) {
    # One read value of health.json. A content that is not a finite number is not stored: the value is unreadable; a
    # number that is not finite inside a list or table becomes $null.
    if (@('read', 'absent', 'unreadable') -cnotcontains $State) { throw "Zustandsbild: unbekannter Zustand '$State'." }
    if (@('', 'rights', 'notInstalled', 'timeout', 'error') -cnotcontains $Reason) { throw "Zustandsbild: unbekannter Grund '$Reason'." }
    if (Test-WorkerPerfHealthNonFinite $Value) { return [ordered]@{ State = 'unreadable'; Reason = 'error'; Value = $null } }
    return [ordered]@{ State = $State; Reason = $Reason; Value = (ConvertTo-WorkerPerfHealthFinite $Value) }
}

function ConvertTo-WorkerPerfHealthListItem($Item) {
    # An entry of a list value as an ordered record; a number that is not finite, at any depth of a field (or as a
    # plain entry), becomes $null.
    if ($null -eq $Item) { return $null }
    $pairs = @()
    if ($Item -is [System.Collections.IDictionary]) { $pairs = @(foreach ($k in @($Item.Keys)) { , @($k, $Item[$k]) }) }
    elseif ($Item -is [System.Management.Automation.PSCustomObject]) { $pairs = @(foreach ($p in $Item.PSObject.Properties) { , @($p.Name, $p.Value) }) }
    else { return , (ConvertTo-WorkerPerfHealthFinite $Item) }
    $out = [ordered]@{}
    foreach ($pair in $pairs) { $out[[string]$pair[0]] = ConvertTo-WorkerPerfHealthFinite $pair[1] }
    return $out
}

function Complete-WorkerPerfHealthArea([string]$Area, [System.Collections.IDictionary]$Values, [double]$DurationMs, [string]$ErrorText = '', [bool]$TimedOut = $false) {
    # One area of health.json: its values in the order of the value list, each missing value unreadable (timeout or
    # error), each given value checked like New-WorkerPerfHealthValue, a read list always an array (a read list without
    # content is unreadable with error, not empty). Status: failed without a read or absent value, partial with an
    # unreadable one.
    if ($script:WorkerPerfHealthAreas -cnotcontains $Area) { throw "Zustandsbild: unbekannter Bereich '$Area'." }
    $ids = @(@($script:WorkerPerfHealthValues.Keys) | Where-Object { $script:WorkerPerfHealthValues[$_].Area -ceq $Area })
    if ($null -eq $Values) { $Values = @{} }
    foreach ($key in @($Values.Keys)) {
        if ($ids -cnotcontains [string]$key) { throw "Zustandsbild: der Wert '$key' gehoert nicht zum Bereich '$Area'." }
    }
    $missingReason = 'error'; if ($TimedOut) { $missingReason = 'timeout' }
    $out = [ordered]@{}
    $known = 0; $unreadable = 0
    foreach ($id in $ids) {
        if (-not $Values.Contains($id)) { $out[$id] = New-WorkerPerfHealthValue 'unreadable' $missingReason }
        else {
            $given = $Values[$id]
            # the content read directly: Get-WorkerPerfField would unroll an empty or one-element list
            $content = $null
            if ($given -is [System.Collections.IDictionary]) { if ($given.Contains('Value')) { $content = $given['Value'] } }
            elseif ($null -ne $given -and $null -ne $given.PSObject.Properties['Value']) { $content = $given.PSObject.Properties['Value'].Value }
            $entry = New-WorkerPerfHealthValue ([string](Get-WorkerPerfField $given 'State')) ([string](Get-WorkerPerfField $given 'Reason')) $content
            if ($script:WorkerPerfHealthValues[$id].Type -eq 'list' -and $entry.State -eq 'read') {
                if ($null -eq $entry.Value) { $entry = New-WorkerPerfHealthValue 'unreadable' 'error' }
                else { $entry.Value = [object[]]@(foreach ($item in @($entry.Value)) { , (ConvertTo-WorkerPerfHealthListItem $item) }) }
            }
            $out[$id] = $entry
        }
        if ($out[$id].State -eq 'unreadable') { $unreadable++ } else { $known++ }
    }
    $status = 'read'
    if ($known -eq 0) { $status = 'failed' } elseif ($unreadable -gt 0) { $status = 'partial' }
    return [ordered]@{ Status = $status; DurationMs = $DurationMs; Error = $ErrorText; Values = $out }
}

function New-WorkerPerfHealth([datetime]$ReadAt, [double]$DurationMs, [System.Collections.IDictionary]$Areas) {
    # The whole health picture: the head and every area in fixed order; a missing area (or one given as $null) is
    # failed with 'notRead'.
    if ($null -eq $Areas) { $Areas = @{} }
    foreach ($key in @($Areas.Keys)) {
        if ($script:WorkerPerfHealthAreas -cnotcontains [string]$key) { throw "Zustandsbild: unbekannter Bereich '$key'." }
    }
    $out = [ordered]@{}
    foreach ($id in $script:WorkerPerfHealthAreas) {
        if ($Areas.Contains($id) -and $null -ne $Areas[$id]) { $out[$id] = $Areas[$id] } else { $out[$id] = Complete-WorkerPerfHealthArea $id @{} 0 'notRead' }
    }
    return [ordered]@{ FormatVersion = $script:WorkerPerfHealthFormatVersion
        ReadAt = $ReadAt.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture); DurationMs = $DurationMs; Areas = $out }
}

function ConvertTo-WorkerPerfHealthTime([datetime]$Time) {
    # Milliseconds since 1970 (UTC), the type time of health.json; [datetime]::MinValue (unknown) gives 0.
    if ($Time -eq [datetime]::MinValue) { return [long]0 }
    return [long](New-Object DateTimeOffset ($Time)).ToUnixTimeMilliseconds()
}

# ---------- application list of the health picture (src/apps.json: installed and probes) ----------

# reading kind -> the allowed values of read; the first is the default
$script:WorkerPerfAppProbeKinds = [ordered]@{
    registryValue = @('value')
    registryKey   = @('exists', 'valueCount', 'subKeyCount')
    service       = @('state', 'startMode')
    scheduledTask = @('enabled', 'exists', 'lastRun', 'nextRun')
    file          = @('version', 'exists')
}
$script:WorkerPerfAppProbeFields = @('id', 'kind', 'read', 'path', 'name', 'displayName', 'names', 'label', 'documented')
$script:WorkerPerfAppFields = @('key', 'label', 'processes', 'installed', 'probes')

function Stop-WorkerPerfHealthApps([string]$Path, [string]$App, [string]$Probe, [string]$Reason) {
    # Anwendungsliste '<Pfad>': [Anwendung <Anwendung>: [Probe <Probe>: ]]<Grund>.
    $at = "Anwendungsliste '$Path'"
    if ($App) { $at += ": Anwendung $App" }
    if ($Probe) { $at += ": Probe $Probe" }
    throw "${at}: $Reason."
}

function Get-WorkerPerfHealthAppsMember($Object, [string]$Name) {
    # The property of a JSON object (also one holding an empty or one-element list), or $null when it is missing.
    if ($null -eq $Object -or $Object -isnot [System.Management.Automation.PSCustomObject]) { return $null }
    return $Object.PSObject.Properties[$Name]
}

function ConvertTo-WorkerPerfHealthAppProbe([string]$Path, [string]$App, $Entry, [string]$Name, [bool]$Installed, $Ids) {
    # Checks one probe of the application list (or its probe installed) and returns it with the defaults filled in.
    if ($null -eq $Entry -or $Entry -isnot [System.Management.Automation.PSCustomObject]) { Stop-WorkerPerfHealthApps $Path $App $Name 'ist kein Objekt' }
    $id = ''
    if (-not $Installed) {
        $m = Get-WorkerPerfHealthAppsMember $Entry 'id'
        if ($null -eq $m) { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'id' fehlt" }
        if ($m.Value -isnot [string]) { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'id' ist kein Text" }
        $id = $m.Value; $Name = "'" + $id + "'"
        if ($id -cnotmatch '^[a-z][A-Za-z0-9]*\z') { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'id' muss mit einem Kleinbuchstaben beginnen und darf nur Buchstaben und Ziffern enthalten" }
        if ($id -ceq 'installed') { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'id' darf nicht 'installed' heissen (die Kennung der Installation)" }
        if (-not $Ids.Add($id)) { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'id' ist doppelt" }
    }
    foreach ($p in $Entry.PSObject.Properties) {
        if ($script:WorkerPerfAppProbeFields -cnotcontains $p.Name) { Stop-WorkerPerfHealthApps $Path $App $Name "Feld '$($p.Name)' ist unbekannt" }
        if ($Installed -and @('id', 'read', 'names', 'label') -ccontains $p.Name) { Stop-WorkerPerfHealthApps $Path $App $Name "Feld '$($p.Name)' ist bei der Installation nicht erlaubt" }
    }
    $kinds = @($script:WorkerPerfAppProbeKinds.Keys)
    $m = Get-WorkerPerfHealthAppsMember $Entry 'kind'
    if ($null -eq $m) { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'kind' fehlt" }
    if ($m.Value -isnot [string] -or $kinds -cnotcontains $m.Value) {
        Stop-WorkerPerfHealthApps $Path $App $Name ("Feld 'kind' nennt die unbekannte Leseart '" + [string]$m.Value + "' (erlaubt: " + ($kinds -join ', ') + ')')
    }
    $kind = $m.Value
    $allowed = @($script:WorkerPerfAppProbeKinds[$kind])
    $read = ''
    if (-not $Installed) {
        $read = $allowed[0]
        $m = Get-WorkerPerfHealthAppsMember $Entry 'read'
        if ($null -ne $m) {
            if ($m.Value -isnot [string] -or $allowed -cnotcontains $m.Value) {
                Stop-WorkerPerfHealthApps $Path $App $Name ("Feld 'read' nennt '" + [string]$m.Value + "', das die Leseart '$kind' nicht kennt (erlaubt: " + ($allowed -join ', ') + ')')
            }
            $read = $m.Value
        }
    }
    # location fields: required, allowed or not allowed by the reading kind
    $texts = @{ path = ''; name = ''; displayName = '' }
    foreach ($field in @('path', 'name', 'displayName')) {
        $m = Get-WorkerPerfHealthAppsMember $Entry $field
        if ($null -eq $m) { continue }
        $usable = switch ($field) { 'path' { $kind -ne 'service' } 'name' { @('registryValue', 'service') -ccontains $kind } default { $kind -eq 'service' } }
        if (-not $usable) { Stop-WorkerPerfHealthApps $Path $App $Name "Feld '$field' gilt nicht fuer die Leseart '$kind'" }
        if ($m.Value -isnot [string] -or [string]::IsNullOrWhiteSpace($m.Value)) { Stop-WorkerPerfHealthApps $Path $App $Name "Feld '$field' ist kein Text oder leer" }
        $texts[$field] = $m.Value
    }
    if ($kind -ne 'service' -and -not $texts.path) { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'path' fehlt" }
    switch ($kind) {
        { @('registryValue', 'registryKey') -ccontains $_ } {
            if ($texts.path -notmatch '^HKLM\\.') { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'path' muss mit 'HKLM\' beginnen" }
        }
        'registryValue' { if (-not $texts.name) { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'name' fehlt" } }
        'service' {
            if ([bool]$texts.name -eq [bool]$texts.displayName) { Stop-WorkerPerfHealthApps $Path $App $Name "genau eines der Felder 'name' und 'displayName' muss angegeben sein" }
        }
        'scheduledTask' { if (-not $texts.path.StartsWith('\')) { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'path' muss mit '\' beginnen" } }
        'file' {
            if ($texts.path -notmatch '^[A-Za-z]:\\.') { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'path' muss ein lokaler Pfad sein (X:\...)" }
            if ($texts.path.Contains('/')) { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'path' darf kein '/' enthalten (Trennzeichen ist '\')" }
            $parts = $texts.path.Split('\')
            if (@($parts | Where-Object { $_ -eq '..' }).Count -gt 0) { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'path' darf '..' nicht enthalten" }
            if ($parts[$parts.Count - 1] -eq '') { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'path' darf nicht mit '\' enden (der letzte Teil ist leer)" }
            if ($texts.path.Split('*').Count -gt 2) { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'path' darf hoechstens ein '*' enthalten" }
            if ($parts[$parts.Count - 1].Contains('*')) { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'path' darf im letzten Teil kein '*' enthalten" }
        }
    }
    if (@('registryValue', 'registryKey', 'scheduledTask') -ccontains $kind) {
        # literal paths only: no wildcard, no '..' segment, no empty segment ('/' stays allowed: key names may contain it)
        if ($texts.path.IndexOfAny([char[]]@('*', '?')) -ge 0) { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'path' darf kein '*' und kein '?' enthalten" }
        $parts = $texts.path.Split('\')
        if ($kind -eq 'scheduledTask') { $parts = @($parts | Select-Object -Skip 1) }
        if (@($parts | Where-Object { $_ -eq '..' }).Count -gt 0) { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'path' darf '..' nicht enthalten" }
        if (@($parts | Where-Object { $_ -eq '' }).Count -gt 0) { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'path' darf keinen leeren Teil enthalten ('\\' oder '\' am Ende)" }
    }
    $names = $false
    $m = Get-WorkerPerfHealthAppsMember $Entry 'names'
    if ($kind -eq 'registryValue' -and -not $Installed) {
        if ($null -eq $m) { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'names' fehlt (true oder false)" }
        if ($m.Value -isnot [bool]) { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'names' ist kein Wahrheitswert" }
        $names = $m.Value
    }
    elseif ($null -ne $m) { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'names' gilt nur fuer die Leseart 'registryValue'" }
    $label = $id
    $m = Get-WorkerPerfHealthAppsMember $Entry 'label'
    if ($null -ne $m) {
        if ($m.Value -isnot [string] -or [string]::IsNullOrWhiteSpace($m.Value)) { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'label' ist kein Text oder leer" }
        $label = $m.Value
    }
    $documented = $true
    $m = Get-WorkerPerfHealthAppsMember $Entry 'documented'
    if ($null -ne $m) {
        if ($m.Value -isnot [bool]) { Stop-WorkerPerfHealthApps $Path $App $Name "Feld 'documented' ist kein Wahrheitswert" }
        $documented = $m.Value
    }
    return [ordered]@{ id = $id; kind = $kind; read = $read; path = $texts.path; name = $texts.name; displayName = $texts.displayName
        names = $names; label = $label; documented = $documented }
}

function Read-WorkerPerfHealthApps([string]$Path) {
    # Reads and checks the application list for the health picture: version; apps, each with key (letters and digits,
    # once, compared ordinally like Read-WorkerPerfApps of the guided report), label, processes (at least one text), the
    # optional probe installed and the optional probes (only with installed). Returns per application
    # [ordered]@{ key; label; processes; installed; probes }, the probes with their defaults; an application without
    # installed is returned without probes (the health picture does not read it). Plain pipeline output.
    if (-not $Path -or -not [IO.File]::Exists($Path)) { throw "Anwendungsliste '$Path' fehlt." }
    try { $list = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json }
    catch { Stop-WorkerPerfHealthApps $Path '' '' ('ist nicht lesbar oder kein gueltiges JSON (' + $_.Exception.Message.TrimEnd('.') + ')') }
    if ($null -eq $list -or $list -isnot [System.Management.Automation.PSCustomObject]) { Stop-WorkerPerfHealthApps $Path '' '' 'ist kein JSON-Objekt' }
    $m = Get-WorkerPerfHealthAppsMember $list 'version'
    if ($null -eq $m) { Stop-WorkerPerfHealthApps $Path '' '' "Feld 'version' fehlt" }
    if ($m.Value -isnot [string] -or [string]::IsNullOrWhiteSpace($m.Value)) { Stop-WorkerPerfHealthApps $Path '' '' "Feld 'version' ist kein Text oder leer" }
    $m = Get-WorkerPerfHealthAppsMember $list 'apps'
    if ($null -eq $m) { Stop-WorkerPerfHealthApps $Path '' '' "Feld 'apps' fehlt" }
    if ($m.Value -isnot [array]) { Stop-WorkerPerfHealthApps $Path '' '' "Feld 'apps' ist keine Liste" }
    $entries = @($m.Value)
    $keys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $app = $entries[$i]; $name = "apps[$i]"
        if ($null -eq $app -or $app -isnot [System.Management.Automation.PSCustomObject]) { Stop-WorkerPerfHealthApps $Path $name '' 'ist kein Objekt' }
        $m = Get-WorkerPerfHealthAppsMember $app 'key'
        if ($null -eq $m) { Stop-WorkerPerfHealthApps $Path $name '' "Feld 'key' fehlt" }
        if ($m.Value -isnot [string]) { Stop-WorkerPerfHealthApps $Path $name '' "Feld 'key' ist kein Text" }
        $key = $m.Value; $name = "'" + $key + "'"
        if ($key -cnotmatch '^[A-Za-z0-9]+$') { Stop-WorkerPerfHealthApps $Path $name '' "Feld 'key' darf nur Buchstaben und Ziffern enthalten" }
        if (-not $keys.Add($key)) { Stop-WorkerPerfHealthApps $Path $name '' "Feld 'key' ist doppelt" }
        foreach ($p in $app.PSObject.Properties) {
            if ($script:WorkerPerfAppFields -cnotcontains $p.Name) { Stop-WorkerPerfHealthApps $Path $name '' "Feld '$($p.Name)' ist unbekannt" }
        }
        $m = Get-WorkerPerfHealthAppsMember $app 'label'
        if ($null -eq $m) { Stop-WorkerPerfHealthApps $Path $name '' "Feld 'label' fehlt" }
        if ($m.Value -isnot [string] -or [string]::IsNullOrWhiteSpace($m.Value)) { Stop-WorkerPerfHealthApps $Path $name '' "Feld 'label' ist kein Text oder leer" }
        $label = $m.Value
        $m = Get-WorkerPerfHealthAppsMember $app 'processes'
        if ($null -eq $m) { Stop-WorkerPerfHealthApps $Path $name '' "Feld 'processes' fehlt" }
        if ($m.Value -isnot [array] -or @($m.Value).Count -eq 0) { Stop-WorkerPerfHealthApps $Path $name '' "Feld 'processes' ist keine Liste mit mindestens einem Namen" }
        foreach ($p in @($m.Value)) {
            if ($p -isnot [string]) { Stop-WorkerPerfHealthApps $Path $name '' "Feld 'processes' enthaelt einen Eintrag, der kein Text ist" }
            if ([string]::IsNullOrWhiteSpace($p)) { Stop-WorkerPerfHealthApps $Path $name '' "Feld 'processes' enthaelt einen leeren Namen" }
        }
        $processes = [string[]]@($m.Value)
        $installed = $null; $probes = @()
        $mi = Get-WorkerPerfHealthAppsMember $app 'installed'
        $mp = Get-WorkerPerfHealthAppsMember $app 'probes'
        if ($null -ne $mp -and $null -eq $mi) { Stop-WorkerPerfHealthApps $Path $name '' "Feld 'probes' braucht das Feld 'installed'" }
        if ($null -ne $mi) {
            $installed = ConvertTo-WorkerPerfHealthAppProbe $Path $name $mi.Value "'installed'" $true $null
            if ($null -ne $mp) {
                if ($mp.Value -isnot [array]) { Stop-WorkerPerfHealthApps $Path $name '' "Feld 'probes' ist keine Liste" }
                $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
                $list2 = @($mp.Value)
                $probes = @(for ($j = 0; $j -lt $list2.Count; $j++) { ConvertTo-WorkerPerfHealthAppProbe $Path $name $list2[$j] "probes[$j]" $false $ids })
            }
        }
        [ordered]@{ key = $key; label = $label; processes = $processes; installed = $installed; probes = [object[]]$probes }
    }
}

function Get-WorkerPerfAppFactType($Probe) {
    # The type of the fact of a probe (table "Lesearten"): value, text:free, bool, number, text or time. The probe
    # installed (without read) gives bool.
    $read = [string](Get-WorkerPerfField $Probe 'read')
    switch ([string](Get-WorkerPerfField $Probe 'kind')) {
        'registryValue' { if ($read -eq '') { return 'bool' }; if ([bool](Get-WorkerPerfField $Probe 'names')) { return 'text:free' }; return 'value' }
        'registryKey' { if ($read -eq 'valueCount' -or $read -eq 'subKeyCount') { return 'number' }; return 'bool' }
        'service' { if ($read -eq '') { return 'bool' }; return 'text' }
        'scheduledTask' { if ($read -eq 'lastRun' -or $read -eq 'nextRun') { return 'time' }; return 'bool' }
        'file' { if ($read -eq 'version') { return 'text' }; return 'bool' }
    }
    throw "Anwendungsliste: unbekannte Leseart '$([string](Get-WorkerPerfField $Probe 'kind'))'."
}

function Get-WorkerPerfAppResultField($Result, [string]$Name) {
    # A field of a reader's result as it is (an array stays an array).
    if ($Result -is [System.Collections.IDictionary]) { if ($Result.Contains($Name)) { return , $Result[$Name] }; return $null }
    if ($null -ne $Result -and $null -ne $Result.PSObject.Properties[$Name]) { return , $Result.PSObject.Properties[$Name].Value }
    return $null
}

function ConvertTo-WorkerPerfAppRegistryValue($Value) {
    # A registry value as a fact: a whole number as a number, several strings joined with '; ', binary data as
    # 'binaer, <n> Byte', anything else as text.
    if ($null -eq $Value) { return $null }
    if ($Value -is [byte[]]) { return 'binaer, ' + $Value.Length + ' Byte' }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [int16] -or $Value -is [byte] -or $Value -is [uint16] -or $Value -is [uint32]) { return [long]$Value }
    if ($Value -is [uint64]) { if ($Value -le [uint64][long]::MaxValue) { return [long]$Value }; return [double]$Value }
    if ($Value -is [array]) { return (@($Value | ForEach-Object { [string]$_ }) -join '; ') }
    return [string]$Value
}

function ConvertFrom-WorkerPerfAppResult($Result, [string]$ReadAs) {
    # The fact a reader's result gives for the read $ReadAs. Throws when the result is not a table, lacks the field the
    # read needs or carries a value of the wrong type, so that nothing is invented from a malformed result.
    if ($Result -isnot [System.Collections.IDictionary] -and $Result -isnot [System.Management.Automation.PSCustomObject]) {
        throw 'Anwendungsliste: das Ergebnis des Lesers ist keine Tabelle.'
    }
    if ($ReadAs -eq 'exists') { return $true }
    $field = @{ value = 'Value'; valueCount = 'ValueCount'; subKeyCount = 'SubKeyCount'; state = 'State'; startMode = 'StartMode'
        enabled = 'Enabled'; lastRun = 'LastRun'; nextRun = 'NextRun'; version = 'Version' }[$ReadAs]
    if (-not $field) { throw "Anwendungsliste: unbekannte Lesart '$ReadAs'." }
    $has = $(if ($Result -is [System.Collections.IDictionary]) { $Result.Contains($field) } else { $null -ne $Result.PSObject.Properties[$field] })
    if (-not $has) { throw "Anwendungsliste: dem Ergebnis des Lesers fehlt das Feld '$field'." }
    $v = Get-WorkerPerfAppResultField $Result $field
    $bad = "Anwendungsliste: das Feld '$field' im Ergebnis des Lesers hat nicht den erwarteten Typ."
    switch ($ReadAs) {
        'value' { if ($null -eq $v) { throw $bad }; return , (ConvertTo-WorkerPerfAppRegistryValue $v) }
        { $_ -eq 'valueCount' -or $_ -eq 'subKeyCount' } {
            $whole = $v -is [int] -or $v -is [long] -or $v -is [int16] -or $v -is [byte] -or $v -is [sbyte] -or $v -is [uint16] -or $v -is [uint32] -or ($v -is [uint64] -and $v -le [uint64][long]::MaxValue)
            if (-not $whole) { throw $bad }; return [long]$v
        }
        'enabled' { if ($v -isnot [bool]) { throw $bad }; return $v }
        { $_ -eq 'lastRun' -or $_ -eq 'nextRun' } { if ($v -isnot [datetime]) { throw $bad }; return (ConvertTo-WorkerPerfHealthTime $v) }
        default { if ($v -isnot [string]) { throw $bad }; return $v }
    }
}

function Get-WorkerPerfAppRows {
    # The rows of the value apps.probes: per application with installed first the row installed, then its probes in the
    # order of the file. -Read names per reading kind a reader of the source ($null when the thing is not there).
    # Not installed: no probe is read, each is absent/notInstalled; installed unreadable: each row of the application is
    # unreadable with its reason. A reader that throws, or a result that is not a table, lacks the field its read needs
    # or carries a value of the wrong type, gives unreadable with the reason of -FailReason (default error); once
    # -Expired returns true (or throws) before a row, that row and all following are unreadable/timeout. Plain
    # pipeline output.
    param([object[]]$Apps, [hashtable]$Read, [scriptblock]$FailReason = $null, [scriptblock]$Expired = $null)
    $timedOut = $false
    foreach ($app in @($Apps)) {
        $installed = Get-WorkerPerfField $app 'installed'
        if ($null -eq $installed) { continue }
        $key = [string](Get-WorkerPerfField $app 'key')
        $probes = @(@($installed) + @(Get-WorkerPerfField $app 'probes'))
        $appState = ''; $appReason = ''
        for ($i = 0; $i -lt $probes.Count; $i++) {
            $probe = $probes[$i]; $isInstalled = ($i -eq 0)
            $kind = [string]$probe.kind
            $id = [string]$probe.id; $readAs = [string]$probe.read
            if ($isInstalled) { $id = 'installed'; $readAs = 'exists' }
            $row = [ordered]@{ App = $key; Id = $id; Kind = $kind; Read = $readAs; State = 'read'; Reason = ''; Value = $null; Names = $null }
            if (-not $timedOut -and $null -ne $Expired) {
                $over = $true
                try { $over = [bool](& $Expired) } catch { $over = $true }
                if ($over) { $timedOut = $true }
            }
            if ($timedOut) { $row.State = 'unreadable'; $row.Reason = 'timeout' }
            elseif (-not $isInstalled -and $appState -eq 'absent') { $row.State = 'absent'; $row.Reason = 'notInstalled' }
            elseif (-not $isInstalled -and $appState -eq 'unreadable') { $row.State = 'unreadable'; $row.Reason = $appReason }
            else {
                try {
                    $reader = $Read[$kind]
                    if ($null -eq $reader) { throw "Anwendungsliste: kein Leser fuer die Leseart '$kind'." }
                    $result = switch ($kind) {
                        'registryValue' { & $reader $probe.path $probe.name }
                        'service' { & $reader $probe.name $probe.displayName }
                        default { & $reader $probe.path }
                    }
                    # the conversion runs inside the try: a malformed result makes this row unreadable, not the area
                    if ($null -eq $result) { if ($readAs -eq 'exists') { $row.Value = $false } else { $row.State = 'absent' } }
                    else {
                        $v = ConvertFrom-WorkerPerfAppResult $result $readAs
                        if ($readAs -eq 'value' -and $probe.names) { $row.Names = [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $v) }
                        else { $row.Value = $v }
                    }
                }
                catch {
                    $reason = 'error'
                    if ($null -ne $FailReason) {
                        try { $given = [string](& $FailReason $_); if (@('rights', 'timeout', 'error') -ccontains $given) { $reason = $given } } catch { $reason = 'error' }
                    }
                    $row.State = 'unreadable'; $row.Reason = $reason; $row.Value = $null; $row.Names = $null
                }
            }
            if ($isInstalled) {
                $appState = $row.State; $appReason = $row.Reason
                if ($row.State -eq 'read' -and -not $row.Value) { $appState = 'absent' }
            }
            $row
        }
    }
}
