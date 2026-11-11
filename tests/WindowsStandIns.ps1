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
        Reads = 0; DiskQueries = 0; FailRead = ''; FailCitrix = $false; EuemClass = $true
        Logs = @('Microsoft-Windows-Windows Defender/Operational', 'Microsoft-Windows-AppLocker/EXE and DLL', 'Microsoft-Windows-AppLocker/MSI and Script')
        Perf = @{
            'Processor Information' = @{ '% Processor Time' = @{ '_Total' = 28.8; '0,_Total' = 30.0; '0,0' = 31.0 } }
            'System' = @{ 'Processor Queue Length' = @{ 'systemdiagnosticsperfcounterlibsingleinstance' = 3.0 } }
            'VM Processor' = @{ 'CPU stolen time' = @{ '_Total' = 0.00015 } }
            'Memory' = @{ 'Available Bytes' = @{ 'systemdiagnosticsperfcounterlibsingleinstance' = 33381543936.0 }
                'Committed Bytes' = @{ 'systemdiagnosticsperfcounterlibsingleinstance' = 36549353472.0 }
                'Commit Limit' = @{ 'systemdiagnosticsperfcounterlibsingleinstance' = 83750830080.0 }
                'Pages Input/sec' = @{ 'systemdiagnosticsperfcounterlibsingleinstance' = 42.95 } }
            'PhysicalDisk' = @{ 'Disk Read Bytes/sec' = @{ '_Total' = 5110.5 }; 'Disk Write Bytes/sec' = @{ '_Total' = 115498.6 }; 'Disk Reads/sec' = @{ '_Total' = 2.0 }
                'Disk Writes/sec' = @{ '_Total' = 21.9 }; 'Current Disk Queue Length' = @{ '_Total' = 0.0 } }
            'Network Interface' = @{ 'Bytes Received/sec' = @{ 'vmxnet3 Ethernet Adapter' = 6322.7 }; 'Bytes Sent/sec' = @{ 'vmxnet3 Ethernet Adapter' = 10303.2 } }
            'LogicalDisk' = @{ 'Avg. Disk sec/Read' = $lat.Clone(); 'Avg. Disk sec/Write' = $lat.Clone(); 'Disk Reads/sec' = $ops.Clone(); 'Disk Writes/sec' = $ops.Clone()
                'Disk Read Bytes/sec' = $ops.Clone(); 'Disk Write Bytes/sec' = $ops.Clone(); 'Current Disk Queue Length' = $ops.Clone() }
            'SMB Client Shares' = @{ 'Avg. sec/Read' = @{ '\fs01\daten' = 0.004; '_Total' = 0.004 }; 'Avg. sec/Write' = @{ '\fs01\daten' = 0.0; '_Total' = 0.0 }
                'Read Requests/sec' = @{ '\fs01\daten' = 6.0; '_Total' = 6.0 }; 'Write Requests/sec' = @{ '\fs01\daten' = 0.0; '_Total' = 0.0 }
                'Read Bytes/sec' = @{ '\fs01\daten' = 60000.0; '_Total' = 60000.0 }; 'Write Bytes/sec' = @{ '\fs01\daten' = 0.0; '_Total' = 0.0 } }
            'User Input Delay per Session' = @{ 'Max Input Delay' = @{ '0' = 0.0; '2' = 312.0; 'Average' = 0.3; 'Max' = 312.0 } }
            'User Input Delay per Process' = @{ 'Max Input Delay' = @{ '0:10024 <w3wp.exe>' = 0.0; '2:7964 <EXCEL.EXE>' = 312.0 } }
            'ICA Session' = @{ 'Latency - Last Recorded' = @{ '_Server gesamt' = 0.0; 'ICA-CGP 0 (mueller)' = 12.0 }
                'Output Session Bandwidth' = @{ '_Server gesamt' = 4104.0; 'ICA-CGP 0 (mueller)' = 280.0 } }
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
            $coll[$i] = [pscustomobject]@{ InstanceName = $i; Sample = [pscustomobject]@{ RawValue = $script:WinFake.Reads; Value = $inst[$i] } }
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
    throw "Klasse $ClassName nicht gefunden"
}

function Get-CimInstance {
    [CmdletBinding()] param([string]$ClassName, [string]$Namespace, [string]$Filter, [string[]]$Property, [int]$OperationTimeoutSec)
    switch ($ClassName) {
        'Win32_ComputerSystem' { [pscustomobject]@{ Name = 'VDA-TEST'; NumberOfLogicalProcessors = 6; TotalPhysicalMemory = [uint64]62277025792 } }
        'Win32_OperatingSystem' { [pscustomobject]@{ Caption = 'Microsoft Windows Server 2022 Datacenter'; Version = '10.0.20348' } }
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
        'MSFT_Disk' { $script:WinFake.DiskQueries++; $script:WinFake.Disks.ToArray() }
        'MSFT_Partition' { foreach ($d in $script:WinFake.Disks) { $d.Partitions } }
        'Citrix_Euem_RoundTrip' {
            if ($script:WinFake.FailCitrix) { throw 'Citrix-WMI antwortet nicht' }
            [pscustomobject]@{ SessionID = [uint32]2; RoundtripTime = [uint32]40; NetworkLatency = [uint32]20; InstanceId = 'a'; ProcessId = '1' }
        }
        default { throw "Stand-in kennt $ClassName nicht" }
    }
}

function Get-WinEvent {
    [CmdletBinding()] param([string]$ListLog, [hashtable]$FilterHashtable, [int]$MaxEvents)
    if ($ListLog) {
        if ($script:WinFake.Logs -contains $ListLog) { return [pscustomobject]@{ LogName = $ListLog; IsEnabled = $true } }
        throw "Protokoll $ListLog nicht vorhanden"
    }
    $log = $FilterHashtable.LogName
    if ($script:WinFake.Logs -notcontains $log) { throw "Protokoll $log nicht vorhanden" }
    $events = @()
    if ($log -like '*Defender*') {
        $events = @(
            [pscustomobject]@{ TimeCreated = [datetime]::Now.AddMinutes(-1); Id = 1001; Message = "Die Ueberpruefung wurde beendet.`r`nScan-ID: {1}" }
            [pscustomobject]@{ TimeCreated = [datetime]::Now.AddMinutes(-2); Id = 1000; Message = 'Die Ueberpruefung wurde gestartet.' }
            [pscustomobject]@{ TimeCreated = [datetime]::Now.AddHours(-3); Id = 1000; Message = 'alt' }) |
            Where-Object { $_.TimeCreated -ge $FilterHashtable.StartTime -and $FilterHashtable.Id -contains $_.Id }
    }
    if (@($events).Count -eq 0) {
        throw (New-Object System.Management.Automation.ErrorRecord ((New-Object Exception 'Keine Ereignisse')),
            'NoMatchingEventsFound,Microsoft.PowerShell.Commands.GetWinEventCommand', 'ObjectNotFound', $null)
    }
    $events | Select-Object -First $MaxEvents
}
