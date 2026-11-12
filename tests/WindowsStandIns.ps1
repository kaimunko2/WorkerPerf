# tests/WindowsStandIns.ps1
# Stand-ins for the lowest Windows calls of src/WorkerPerf.Sources.Windows.ps1 (performance counters, CIM, event log,
# WTS). Dot-sourced after the source, they replace only those calls; everything above them runs unchanged. The data has
# the shape of the probe result of a real VDA (Windows Server 2022, de-DE, Citrix Profile Management containers);
# all names are invented. Also appended to a copy of the source for a collector run.

function Reset-WinStandIns {
    $lat = @{ 'C:' = 0.0021; 'D:' = 0.001; 'HarddiskVolume1' = 0.0; 'C:\Users\mueller_UPM_local\UpmTempMount' = 0.044
        'C:\Users\gast_UPM_local\UpmTempMount' = 0.002; '_Total' = 0.003 }
    $ops = @{ 'C:' = 10.0; 'D:' = 2.0; 'HarddiskVolume1' = 0.0; 'C:\Users\mueller_UPM_local\UpmTempMount' = 25.0
        'C:\Users\gast_UPM_local\UpmTempMount' = 1.0; '_Total' = 38.0 }
    $script:WinFake = @{
        Reads = 0; DiskQueries = 0; FailRead = ''; FailCitrix = $false; EuemClass = $true; ThrowCheck = ''; ManyEvents = 0; FailStorage = $false
        # every log of events.json exists; DisabledLogs exist but are switched off
        Logs = @(Get-WinStandInCatalogueLogs); DisabledLogs = @(); EventQueries = 0; RecordId = 0
        Events = [System.Collections.Generic.List[object]]::new()
        # SID -> account as Windows translates it; SidTimeout: SIDs whose lookup runs into the time limit
        Sids = @{ 'S-1-5-21-1000-2000-3000-1108' = 'KLINIK\mueller'; 'S-1-5-80-1-2-3-4-5' = 'NT SERVICE\SimDienst' }; SidTimeout = @(); SidLookups = 0
        # printer drivers as MSFT_PrinterDriver lists them; isolation as the registry gives it (no groups value, as on
        # the target server); PrinterDriverAttributes per driver key
        Drivers = @(
            [pscustomobject]@{ Name = 'Sim PCL 6'; Manufacturer = 'HP'; MajorVersion = [uint16]3; DriverVersion = ([uint64]61 -shl 48) + ([uint64]310 -shl 32) + ([uint64]1 -shl 16) + 25919
                PrinterEnvironment = 'Windows x64'; Path = 'C:\Windows\System32\spool\DRIVERS\x64\3\hpsimgr.dll'; ConfigFile = 'C:\Windows\System32\spool\DRIVERS\x64\3\hpsimui.dll'
                DataFile = 'C:\Windows\System32\spool\DRIVERS\x64\3\HPSIMUI.DLL'; DependentFiles = [string[]]@('C:\Windows\System32\spool\DRIVERS\x64\3\hpsimgr.dll') }
            [pscustomobject]@{ Name = 'Sim Klasse v4'; Manufacturer = 'Sim'; MajorVersion = [uint16]4; DriverVersion = ([uint64]10 -shl 48) + 20348
                PrinterEnvironment = 'Windows x64'; Path = 'C:\Windows\System32\DriverStore\simklasse.dll'; ConfigFile = $null; DataFile = 'simklasse.gpd'; DependentFiles = $null })
        PrintDriverClass = $true; IsolationGroups = $null; IsolationPolicy = @{ PrintDriverIsolationExecutionPolicy = 1 }
        DriverAttributes = @{ 'Sim PCL 6' = 0x2; 'Sim Klasse v4' = 0x4 }
        Perf = @{
            'Processor Information' = @{ '% Processor Time' = @{ '_Total' = 27.5; '0,_Total' = 30.0; '0,0' = 31.0 } }
            'System' = @{ 'Processor Queue Length' = @{ 'systemdiagnosticsperfcounterlibsingleinstance' = 3.0 } }
            'VM Processor' = @{ 'CPU stolen time' = @{ '_Total' = 0.0 } }
            'Memory' = @{ 'Available Bytes' = @{ 'systemdiagnosticsperfcounterlibsingleinstance' = 34359738368.0 }
                'Committed Bytes' = @{ 'systemdiagnosticsperfcounterlibsingleinstance' = 38654705664.0 }
                'Commit Limit' = @{ 'systemdiagnosticsperfcounterlibsingleinstance' = 85899345920.0 }
                'Pages Input/sec' = @{ 'systemdiagnosticsperfcounterlibsingleinstance' = 12.5 } }
            'PhysicalDisk' = @{ 'Disk Read Bytes/sec' = @{ '_Total' = 4096.0 }; 'Disk Write Bytes/sec' = @{ '_Total' = 120000.0 }; 'Disk Reads/sec' = @{ '_Total' = 2.0 }
                'Disk Writes/sec' = @{ '_Total' = 20.5 }; 'Current Disk Queue Length' = @{ '_Total' = 0.0 } }
            'Network Interface' = @{ 'Bytes Received/sec' = @{ 'Ethernet-Adapter 1' = 6000.0 }; 'Bytes Sent/sec' = @{ 'Ethernet-Adapter 1' = 10000.0 } }
            'LogicalDisk' = @{ 'Avg. Disk sec/Read' = $lat.Clone(); 'Avg. Disk sec/Write' = $lat.Clone(); 'Disk Reads/sec' = $ops.Clone(); 'Disk Writes/sec' = $ops.Clone()
                'Disk Read Bytes/sec' = $ops.Clone(); 'Disk Write Bytes/sec' = $ops.Clone(); 'Current Disk Queue Length' = $ops.Clone() }
            'SMB Client Shares' = @{ 'Avg. sec/Read' = @{ '\fs01\daten' = 0.004; '_Total' = 0.004 }; 'Avg. sec/Write' = @{ '\fs01\daten' = 0.0; '_Total' = 0.0 }
                'Read Requests/sec' = @{ '\fs01\daten' = 6.0; '_Total' = 6.0 }; 'Write Requests/sec' = @{ '\fs01\daten' = 0.0; '_Total' = 0.0 }
                'Read Bytes/sec' = @{ '\fs01\daten' = 60000.0; '_Total' = 60000.0 }; 'Write Bytes/sec' = @{ '\fs01\daten' = 0.0; '_Total' = 0.0 } }
            'User Input Delay per Session' = @{ 'Max Input Delay' = @{ '0' = 0.0; '2' = 312.0; 'Average' = 0.3; 'Max' = 312.0 } }
            'User Input Delay per Process' = @{ 'Max Input Delay' = @{ '0:4120 <dienst.exe>' = 0.0; '2:7964 <EXCEL.EXE>' = 312.0 } }
            'ICA Session' = @{ 'Latency - Last Recorded' = @{ '_Server gesamt' = 0.0; 'ICA-CGP 0 (mueller)' = 12.0 }
                'Output Session Bandwidth' = @{ '_Server gesamt' = 5000.0; 'ICA-CGP 0 (mueller)' = 300.0 } }
            'Print Queue' = @{ 'Jobs' = @{ '_Total' = 1.0; 'PRN-TEST-01' = 1.0 }; 'Job Errors' = @{ '_Total' = 4.0; 'PRN-TEST-01' = 4.0 }
                'Not Ready Errors' = @{ '_Total' = 0.0; 'PRN-TEST-01' = 0.0 } }
        }
        Sessions = [System.Collections.Generic.List[object]]::new()
        Disks = [System.Collections.Generic.List[object]]::new()
        Devices = @{}
    }
    $script:WinFake.Sessions.Add([pscustomobject]@{ SessionId = 0; State = 'Disconnected'; WinStation = 'Services'; User = ''; Domain = ''; ClientName = ''
            LogonTime = [datetime]::MinValue; IdleSec = -1 })
    $script:WinFake.Sessions.Add([pscustomobject]@{ SessionId = 2; State = 'Active'; WinStation = 'ICA-CGP#0'; User = 'mueller'; Domain = 'KLINIK'; ClientName = 'WS-0001'
            LogonTime = [datetime]::Now.AddHours(-1); IdleSec = 4 })
    Add-WinStandInDisk 'mueller' 'C:\Users\mueller_UPM_local\UpmTempMount' 137
    Add-WinStandInDisk 'gast' 'C:\Users\gast_UPM_local\UpmTempMount' 139

    # events as ToXml() gives them (invented values); Application Error 1000 with unnamed fields as on the target server
    $defender = 'Microsoft-Windows-Windows Defender'; $dlog = 'Microsoft-Windows-Windows Defender/Operational'
    Add-WinStandInEvent $dlog $defender 1001 4 (-1) "Die Ueberpruefung wurde beendet.`r`nScan-ID: {1}"
    Add-WinStandInEvent $dlog $defender 1000 4 (-2) 'Die Ueberpruefung wurde gestartet.'
    Add-WinStandInEvent $dlog $defender 1000 4 (-180) 'alt'
    $crash = @('EXCEL.EXE', '16.0.18129.20158', '65a1b2c3', 'vbe7.dll', '7.1.10.98', '5f00aa11', 'c0000005', '000e1f2c', '1f1c',
        ('{0:x16}' -f [datetime]::UtcNow.AddHours(-2).ToFileTimeUtc()), 'C:\Programme\EXCEL.EXE', 'C:\Programme\vbe7.dll', '00000000-0000-0000-0000-000000000001', '', '')
    Add-WinStandInEvent 'Application' 'Application Error' 1000 2 (-3) 'Name der fehlerhaften Anwendung: EXCEL.EXE, Version: 16.0.18129.20158' -Data $crash -Sid 'S-1-5-21-1000-2000-3000-1108'
    Add-WinStandInEvent 'Application' 'Citrix Profile Management' 1003 3 (-4) 'Sim-Warnung der Profilverwaltung' -Data @('a', 'b')
    Add-WinStandInEvent 'Application' 'Citrix Profile Management' 1000 4 (-4) 'Sim-Information der Profilverwaltung' -Data @('a')
    Add-WinStandInEvent 'Application' 'Citrix Desktop Service' 1002 2 (-4) 'nicht im Katalog' -Data @('a')
    Add-WinStandInEvent 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational' 'Microsoft-Windows-TerminalServices-LocalSessionManager' 21 4 (-10) `
        'Anmeldung erfolgreich' -UserData @{ User = 'KLINIK\mueller'; SessionID = '2'; Address = '10.0.0.1' }
    Add-WinStandInEvent 'System' 'Service Control Manager' 7034 2 (-3.5) 'Der Dienst wurde unerwartet beendet.' -Data @('Sim-Dienst', '1') -Binary 'Spooler' -Sid 'S-1-5-18'
    Add-WinStandInEvent 'Microsoft-Windows-PrintService/Admin' 'Microsoft-Windows-PrintService' 600 2 (-4.2) 'Treiber nicht importiert' `
        -Named @{ DriverSource = 'x'; Driver = 'Sim PCL 6'; Error = '0x5' } -Sid 'S-1-5-80-1-2-3-4-5'
}

function Get-WinStandInCatalogueLogs {
    $json = Get-Content (Join-Path $PSScriptRoot '../src/events.json') -Raw | ConvertFrom-Json
    foreach ($l in $json.logs) { foreach ($n in $l.names) { [string]$n } }
}

function Add-WinStandInEvent([string]$Log, [string]$Provider, [int]$Id, [int]$Level, [double]$Minutes, [string]$Message, [string[]]$Data = @(),
                             [hashtable]$Named = $null, [hashtable]$UserData = $null, [string]$Binary = '', [string]$Sid = '') {
    $script:WinFake.Events.Add(@{ LogName = $Log; ProviderName = $Provider; Id = $Id; Level = $Level; TimeCreated = [datetime]::Now.AddMinutes($Minutes)
            Message = $Message; Xml = (New-WinStandInXml $Provider $Id $Level $Data $Named $UserData $Binary $Sid) })
}

function New-WinStandInXml([string]$Provider, [int]$Id, [int]$Level, [string[]]$Data, [hashtable]$Named, [hashtable]$UserData, [string]$Binary, [string]$Sid) {
    $esc = { param($v) [Security.SecurityElement]::Escape([string]$v) }
    $sec = $(if ($Sid) { "<Security UserID='$Sid'/>" } else { '<Security/>' })
    $body = ''
    if ($null -ne $UserData) {
        $body = '<UserData><EventXML xmlns="Event_NS">' + (($UserData.Keys | ForEach-Object { "<$_>$(& $esc $UserData[$_])</$_>" }) -join '') + '</EventXML></UserData>'
    }
    else {
        $items = @($Data | ForEach-Object { "<Data>$(& $esc $_)</Data>" })
        if ($null -ne $Named) { $items = @($Named.Keys | ForEach-Object { "<Data Name='$_'>$(& $esc $Named[$_])</Data>" }) }
        $bin = ''
        if ($Binary) { $bin = '<Binary>' + ((([Text.Encoding]::Unicode.GetBytes("$Binary`0")) | ForEach-Object { $_.ToString('X2') }) -join '') + '</Binary>' }
        $body = '<EventData>' + ($items -join '') + $bin + '</EventData>'
    }
    "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><System><Provider Name='$Provider'/><EventID>$Id</EventID><Level>$Level</Level>$sec</System>$body</Event>"
}

function New-WinStandInRecord($E) {
    $script:WinFake.RecordId++
    $o = [pscustomobject]@{ ProviderName = $E.ProviderName; Id = $E.Id; LevelValue = $E.Level; TimeCreated = $E.TimeCreated; Message = $E.Message; LogName = $E.LogName
        RecordId = [long]$script:WinFake.RecordId }
    $xml = $E.Xml
    $o | Add-Member -MemberType ScriptMethod -Name ToXml -Value ([scriptblock]::Create("'" + $xml.Replace("'", "''") + "'"))
    $o
}

function Add-WinStandInDisk([string]$User, [string]$Mount, [int]$Volume) {
    $n = $script:WinFake.Disks.Count + 3
    $guid = '\\?\Volume{{00000000-0000-0000-0000-{0:d12}}}\' -f $Volume
    $script:WinFake.Disks.Add([pscustomobject]@{ Number = $n; Location = "\\fs01\upm$\$User.KLINIK\Win2022\UPM_Profile\ProfileContainer_RW.vhdx"
            Partitions = @([pscustomobject]@{ DiskNumber = $n; PartitionNumber = 1; DriveLetter = [char]0; AccessPaths = $null },
                [pscustomobject]@{ DiskNumber = $n; PartitionNumber = 2; DriveLetter = [char]0; AccessPaths = [string[]]@("$Mount\", $guid) }) })
    $script:WinFake.Devices[$guid.Substring(4).TrimEnd('\')] = "\Device\HarddiskVolume$Volume"
}

function Add-WinStandInUser([int]$SessionId, [string]$User, [string]$Volume) {
    $script:WinFake.Sessions.Add([pscustomobject]@{ SessionId = $SessionId; State = 'Active'; WinStation = "ICA-CGP#$SessionId"; User = $User; Domain = 'KLINIK'
            ClientName = 'WS-0002'; LogonTime = [datetime]::Now; IdleSec = 0 })
    Add-WinStandInDisk $User $Volume (200 + $SessionId)
    foreach ($c in @($script:WinFake.Perf['LogicalDisk'].Keys)) { $script:WinFake.Perf['LogicalDisk'][$c][$Volume] = 1.0 }
}

function Test-WorkerPerfElevated { return $true }

function Test-WorkerPerfWinCounter([string]$Category, [string]$Counter) {
    if ($script:WinFake.ThrowCheck -eq $Category) { throw (New-Object InvalidOperationException 'Leistungsindikatoren beschaedigt') }
    if (-not $script:WinFake.Perf.ContainsKey($Category)) { return 'Kategorie nicht vorhanden' }
    if ($Counter -and -not $script:WinFake.Perf[$Category].ContainsKey($Counter)) { return "Zaehler '$Counter' fehlt" }
    return ''
}

function Open-WorkerPerfWinCategory([string]$Name) {
    if (-not $script:WinFake.Perf.ContainsKey($Name)) { return $null }
    return [pscustomobject]@{ CategoryName = $Name }
}

function Read-WorkerPerfWinCategory($Category) {
    # like ReadCategory: counter names in lower case, one entry per instance; the raw value changes with every reading
    $name = $Category.CategoryName
    if ($script:WinFake.FailRead -eq $name) { throw "Kategorie $name nicht lesbar" }
    $script:WinFake.Reads++
    $result = @{}
    foreach ($counter in $script:WinFake.Perf[$name].Keys) {
        $coll = @{}
        $inst = $script:WinFake.Perf[$name][$counter]
        foreach ($i in $inst.Keys) {
            $coll[$i] = [pscustomobject]@{ InstanceName = $i; Sample = [pscustomobject]@{ RawValue = $script:WinFake.Reads; TimeStamp100nSec = [long]$script:WinFake.Reads * 20000000; Value = $inst[$i] } }
        }
        $result[$counter.ToLowerInvariant()] = $coll
    }
    return $result
}

function Get-WorkerPerfWinSampleValue($Previous, $Current) { return $Current.Value }
function Get-WorkerPerfWinInstantValue($Sample) { return $Sample.Value }
function Get-WorkerPerfWinCounterNames($Category) { return [string[]]@($script:WinFake.Perf[$Category.CategoryName].Keys) }
function Get-WorkerPerfDosDevice([string]$Name) { return $script:WinFake.Devices[$Name] }
function Get-WinSessionRaw { return $script:WinFake.Sessions.ToArray() }

function Get-CimClass {
    [CmdletBinding()] param([string]$ClassName, [string]$Namespace, [int]$OperationTimeoutSec)
    if ($Namespace -eq 'root\citrix\euem' -and $script:WinFake.EuemClass) { return [pscustomobject]@{ CimClassName = $ClassName } }
    if ($ClassName -eq 'MSFT_PrinterDriver' -and $script:WinFake.PrintDriverClass) { return [pscustomobject]@{ CimClassName = $ClassName } }
    throw "Klasse $ClassName nicht gefunden"
}

function Get-CimInstance {
    [CmdletBinding()] param([string]$ClassName, [string]$Namespace, [string]$Filter, [string[]]$Property, [int]$OperationTimeoutSec)
    switch ($ClassName) {
        'Win32_ComputerSystem' { [pscustomobject]@{ Name = 'VDA-TEST'; NumberOfLogicalProcessors = 6; TotalPhysicalMemory = [uint64]62277025792 } }
        'Win32_OperatingSystem' { [pscustomobject]@{ Caption = 'Microsoft Windows Server 2022 Standard'; Version = '10.0.20348' } }
        'Win32_Process' {
            $start = [datetime]::Now.AddHours(-2)
            foreach ($p in @(@(900, 'svchost.exe', 0), @(7964, 'EXCEL.EXE', 2))) {
                [pscustomobject]@{ ProcessId = [uint32]$p[0]; ParentProcessId = [uint32]4; Name = $p[1]; SessionId = [uint32]$p[2]
                    KernelModeTime = [uint64](1e7 * $script:WinFake.Reads); UserModeTime = [uint64](2e7 * $script:WinFake.Reads)
                    WorkingSetSize = [uint64]200MB; PrivatePageCount = [uint64]150MB; ReadTransferCount = [uint64](1MB * $script:WinFake.Reads); WriteTransferCount = [uint64]0
                    ReadOperationCount = [uint64]$script:WinFake.Reads; WriteOperationCount = [uint64]0; HandleCount = [uint32]300; ThreadCount = [uint32]12
                    CreationDate = $start; ExecutablePath = 'C:\Programme\' + $p[1]; CommandLine = $null }
            }
        }
        'Win32_Service' { [pscustomobject]@{ Name = 'RpcSs'; ProcessId = [uint32]900 }; [pscustomobject]@{ Name = 'Spooler'; ProcessId = [uint32]0 } }
        'MSFT_PrinterDriver' { if (-not $script:WinFake.PrintDriverClass) { throw 'Klasse MSFT_PrinterDriver nicht gefunden' }; $script:WinFake.Drivers }
        'MSFT_Disk' { $script:WinFake.DiskQueries++; if ($script:WinFake.FailStorage) { throw 'Zeitlimit der Speicherabfrage' }; $script:WinFake.Disks.ToArray() }
        'MSFT_Partition' { foreach ($d in $script:WinFake.Disks) { $d.Partitions } }
        'Citrix_Euem_RoundTrip' {
            if ($script:WinFake.FailCitrix) { throw 'Citrix-WMI antwortet nicht' }
            [pscustomobject]@{ SessionID = [uint32]2; RoundtripTime = [uint32]40; NetworkLatency = [uint32]20; InstanceId = 'a'; ProcessId = '1' }
        }
        default { throw "Stand-in kennt $ClassName nicht" }
    }
}

function Get-WinEvent {
    # like Get-WinEvent: -ListLog gives IsEnabled; -FilterHashtable filters by log, provider, id, level and time (compared
    # in UTC, as the event log does), newest first; no match is an error with the language neutral id
    [CmdletBinding()] param([string]$ListLog, [hashtable]$FilterHashtable, [int]$MaxEvents)
    if ($ListLog) {
        if ($script:WinFake.Logs -contains $ListLog) { return [pscustomobject]@{ LogName = $ListLog; IsEnabled = ($script:WinFake.DisabledLogs -notcontains $ListLog) } }
        throw "Protokoll $ListLog nicht vorhanden"
    }
    $script:WinFake.EventQueries++
    $f = $FilterHashtable
    $log = $f.LogName
    if ($script:WinFake.Logs -notcontains $log -or $script:WinFake.DisabledLogs -contains $log) { throw "Protokoll $log nicht vorhanden" }
    $all = @($script:WinFake.Events | Where-Object { $_.LogName -eq $log })
    if ($log -like '*Defender*' -and $script:WinFake.ManyEvents -gt 0) {
        # one event per second
        $all = @(foreach ($k in 1..$script:WinFake.ManyEvents) {
                @{ LogName = $log; ProviderName = 'Microsoft-Windows-Windows Defender'; Id = 1000; Level = 4; TimeCreated = [datetime]::Now.AddSeconds(-$k); Message = "Ereignis $k"
                    Xml = (New-WinStandInXml 'Microsoft-Windows-Windows Defender' 1000 4 @() $null $null '' '') }
            })
    }
    $utc = { param($t) if ($t.Kind -eq 'Utc') { $t } else { $t.ToUniversalTime() } }
    $events = @($all | Where-Object {
            ($null -eq $f['ProviderName'] -or @($f['ProviderName']) -contains $_.ProviderName) -and
            ($null -eq $f['Id'] -or @($f['Id']) -contains $_.Id) -and ($null -eq $f['Level'] -or @($f['Level']) -contains $_.Level) -and
            ($null -eq $f['StartTime'] -or (& $utc $_.TimeCreated) -ge (& $utc $f['StartTime'])) -and
            ($null -eq $f['EndTime'] -or (& $utc $_.TimeCreated) -le (& $utc $f['EndTime'])) } |
            Sort-Object -Property @{ Expression = { $_.TimeCreated }; Descending = $true })
    if (@($f['Id']).Count -gt 23) { throw 'Die angegebene Abfrage ist ungueltig' }
    if ($events.Count -eq 0) {
        throw (New-Object System.Management.Automation.ErrorRecord ((New-Object Exception 'Keine Ereignisse')),
            'NoMatchingEventsFound,Microsoft.PowerShell.Commands.GetWinEventCommand', 'ObjectNotFound', $null)
    }
    foreach ($e in @($events | Select-Object -First $MaxEvents)) { New-WinStandInRecord $e }
}

function Get-WorkerPerfSidAccount([string]$Sid) {
    $script:WinFake.SidLookups++
    if ($script:WinFake.SidTimeout -contains $Sid) { return @{ Name = ''; TimedOut = $true } }
    return @{ Name = [string]$script:WinFake.Sids[$Sid]; TimedOut = $false }
}

function Get-WorkerPerfPrintIsolationGroups { return $script:WinFake.IsolationGroups }
function Get-WorkerPerfPrintIsolationPolicy { return $script:WinFake.IsolationPolicy }
function Get-WorkerPerfPrintDriverAttribute($Driver) { return $script:WinFake.DriverAttributes[[string]$Driver.Name] }
