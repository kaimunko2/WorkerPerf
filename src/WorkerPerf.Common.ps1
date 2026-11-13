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

# Health picture (health.json): read values with their state, no rating, no threshold, no German text.
$script:WorkerPerfHealthFormatVersion = 1
$script:WorkerPerfHealthAreas = @('size', 'operation', 'sessions', 'vda', 'profile', 'print', 'security', 'network', 'events', 'maintenance', 'apps')
# Keywords that Error of an area can carry besides the message of an exception: overall time limit reached, no reader,
# not read, not in the file.
$script:WorkerPerfHealthAreaErrors = @('budget', 'noReader', 'notRead', 'notInFile')
# The services the WEM agent needs, each as the list of its documented display names; the first group is the agent service.
$script:WorkerPerfHealthWemServices = @(@('Citrix WEM Agent Host Service', 'Norskale Agent Host Service'),
    @('Citrix WEM User Logon Service', 'Citrix WEM Agent User Logon Service'), @('System Event Notification Service'))

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

function New-WorkerPerfHealthValue([string]$State, [string]$Reason = '', $Value = $null) {
    # One read value of health.json. A content that is not a finite number is not stored: the value is unreadable.
    if (@('read', 'absent', 'unreadable') -cnotcontains $State) { throw "Zustandsbild: unbekannter Zustand '$State'." }
    if (@('', 'rights', 'notInstalled', 'timeout', 'error') -cnotcontains $Reason) { throw "Zustandsbild: unbekannter Grund '$Reason'." }
    if (Test-WorkerPerfHealthNonFinite $Value) { return [ordered]@{ State = 'unreadable'; Reason = 'error'; Value = $null } }
    return [ordered]@{ State = $State; Reason = $Reason; Value = $Value }
}

function ConvertTo-WorkerPerfHealthListItem($Item) {
    # An entry of a list value as an ordered record; a field that carries a number that is not finite becomes $null.
    if ($null -eq $Item) { return $null }
    $pairs = @()
    if ($Item -is [System.Collections.IDictionary]) { $pairs = @(foreach ($k in @($Item.Keys)) { , @($k, $Item[$k]) }) }
    elseif ($Item -is [System.Management.Automation.PSCustomObject]) { $pairs = @(foreach ($p in $Item.PSObject.Properties) { , @($p.Name, $p.Value) }) }
    else { return $Item }
    $out = [ordered]@{}
    foreach ($pair in $pairs) {
        $v = $pair[1]; if (Test-WorkerPerfHealthNonFinite $v) { $v = $null }
        $out[[string]$pair[0]] = $v
    }
    return $out
}

function Complete-WorkerPerfHealthArea([string]$Area, [System.Collections.IDictionary]$Values, [double]$DurationMs, [string]$ErrorText = '', [bool]$TimedOut = $false) {
    # One area of health.json: its values in the order of the value list, each missing value unreadable (timeout or
    # error), a read list always an array. Status: failed without a read or absent value, partial with an unreadable one.
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
            $entry = [ordered]@{ State = [string](Get-WorkerPerfField $given 'State'); Reason = [string](Get-WorkerPerfField $given 'Reason')
                Value = (Get-WorkerPerfField $given 'Value') }
            if ($script:WorkerPerfHealthValues[$id].Type -eq 'list' -and $entry.State -eq 'read') {
                $items = @()
                if ($null -ne $entry.Value) { $items = @(foreach ($item in @($entry.Value)) { , (ConvertTo-WorkerPerfHealthListItem $item) }) }
                $entry.Value = [object[]]$items
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
    # The whole health picture: the head and every area in fixed order; a missing area is failed with 'notRead'.
    if ($null -eq $Areas) { $Areas = @{} }
    foreach ($key in @($Areas.Keys)) {
        if ($script:WorkerPerfHealthAreas -cnotcontains [string]$key) { throw "Zustandsbild: unbekannter Bereich '$key'." }
    }
    $out = [ordered]@{}
    foreach ($id in $script:WorkerPerfHealthAreas) {
        if ($Areas.Contains($id)) { $out[$id] = $Areas[$id] } else { $out[$id] = Complete-WorkerPerfHealthArea $id @{} 0 'notRead' }
    }
    return [ordered]@{ FormatVersion = $script:WorkerPerfHealthFormatVersion
        ReadAt = $ReadAt.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture); DurationMs = $DurationMs; Areas = $out }
}

function ConvertTo-WorkerPerfHealthTime([datetime]$Time) {
    # Milliseconds since 1970 (UTC), the type time of health.json; [datetime]::MinValue (unknown) gives 0.
    if ($Time -eq [datetime]::MinValue) { return [long]0 }
    return [long](New-Object DateTimeOffset ($Time)).ToUnixTimeMilliseconds()
}
