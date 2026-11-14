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
        Logs = @(Get-WinStandInCatalogueLogs); DisabledLogs = @(); EventQueries = 0; RecordId = 0; Queries = [System.Collections.Generic.List[string]]::new()
        # FailLogs: log name -> type name of the exception that opening its reader throws; ReadFailOnce: record ids whose
        # read throws once (the reader moves on); ReadFailAlways: log names where every read throws; Unformattable:
        # record ids whose message cannot be formatted; OpenReaders/OpenRecords: not yet disposed
        FailLogs = @{}; ReadFailOnce = [System.Collections.Generic.List[long]]::new(); ReadFailAlways = @(); Unformattable = @()
        OpenReaders = 0; OpenRecords = 0; ReadCalls = 0
        # Calls: every stand-in counts its call by key (check:/open:/perf:<category>, cim:/cimclass:<class>, winevent:list,
        # winevent:read, winevent:oldest, wts, registry:print, registry:<key>, native:perfinfo, native:power, native:filters,
        # com:tasks, file:version, registrykey:<key>, file:probe, file:dirs, com:task), so a test
        # can see which Windows calls a source made
        Calls = @{}
        Events = [System.Collections.Generic.List[object]]::new()
        # SID -> account as Windows translates it; SidTimeout: SIDs whose lookup runs into the time limit
        Sids = @{ 'S-1-5-21-1000-2000-3000-1108' = 'KLINIK\mueller'; 'S-1-5-80-1-2-3-4-5' = 'NT SERVICE\SimDienst' }; SidTimeout = @(); SidLookups = 0
        # printer drivers as MSFT_PrinterDriver lists them; isolation as the registry gives it (here without a groups
        # value, so policy and driver attribute decide); PrinterDriverAttributes per driver key
        Drivers = @(
            [pscustomobject]@{ Name = 'Sim PCL 6'; Manufacturer = 'HP'; MajorVersion = [uint16]3; DriverVersion = ([uint64]61 -shl 48) + ([uint64]310 -shl 32) + ([uint64]1 -shl 16) + 25919
                PrinterEnvironment = 'Windows x64'; Path = 'C:\Windows\System32\spool\DRIVERS\x64\3\hpsimgr.dll'; ConfigFile = 'C:\Windows\System32\spool\DRIVERS\x64\3\hpsimui.dll'
                DataFile = 'C:\Windows\System32\spool\DRIVERS\x64\3\HPSIMUI.DLL'; DependentFiles = [string[]]@('C:\Windows\System32\spool\DRIVERS\x64\3\hpsimgr.dll') }
            [pscustomobject]@{ Name = 'Sim Klasse v4'; Manufacturer = 'Sim'; MajorVersion = [uint16]4; DriverVersion = ([uint64]10 -shl 48) + 20348
                PrinterEnvironment = 'Windows x64'; Path = 'C:\Windows\System32\DriverStore\simklasse.dll'; ConfigFile = $null; DataFile = 'simklasse.gpd'; DependentFiles = $null })
        # IsolationPolicyFail: exception the read of the isolation policies throws
        PrintDriverClass = $true; IsolationGroups = $null; IsolationPolicy = @{ PrintDriverIsolationExecutionPolicy = 1 }; IsolationPolicyFail = $null
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
        # SessionsFail: exception Get-WorkerPerfHealthSessions throws; Volumes: MSFT_Volume (added with each disk)
        Sessions = [System.Collections.Generic.List[object]]::new(); SessionsFail = $null
        Disks = [System.Collections.Generic.List[object]]::new(); Volumes = [System.Collections.Generic.List[object]]::new()
        Devices = @{}
        # health picture: Delay/DelayOnce: call key -> milliseconds the stand-in waits before the call (DelayOnce only
        # for the next call); RegistryFail/CimFail/LogFail: registry key, CIM class or log name -> exception thrown
        Delay = @{}; DelayOnce = @{}; RegistryFail = @{}; CimFail = @{}; LogFail = @{}
        # registry below HKLM: key -> values (hashtables ignore case); the subkeys of a key are the keys listed directly below it
        Registry = @{
            'SOFTWARE\VMware, Inc.\VMware Tools' = [ordered]@{}
            'SYSTEM\CurrentControlSet\Control\Session Manager' = [ordered]@{
                PendingFileRenameOperations = [string[]]@('\??\C:\Sim\alt.dll', '', '\??\C:\Sim\neu.tmp', '\??\C:\Sim\neu.dll') }
            'SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' = [ordered]@{}
            'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' = [ordered]@{}
            'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{A1}' = [ordered]@{ DisplayName = 'VMware Tools'; DisplayVersion = '12.3.5.22544099' }
            'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{B2}' = [ordered]@{
                DisplayName = 'Citrix Virtual Apps and Desktops 7 2203 LTSR CU4 - Virtual Delivery Agent'; DisplayVersion = '2203.0.4000.4033' }
            'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{C3}' = [ordered]@{ DisplayName = 'PrinTaurus SmartSpread Client'; DisplayVersion = '6.2.1' }
            # Citrix VDA: the controller list of the policy goes before the VDA's own; the content of ListOfSIDs is never stored
            'SOFTWARE\Policies\Citrix' = [ordered]@{}
            'SOFTWARE\Policies\Citrix\VirtualDesktopAgent' = [ordered]@{ ListOfDDCs = 'ddc01.klinik.example ddc02' }
            'SOFTWARE\Citrix\VirtualDesktopAgent' = [ordered]@{ ListOfDDCs = '10.1.1.5'; ListOfSIDs = 'S-1-5-21-1-2-3-1001' }
            'SOFTWARE\Policies\Citrix\ICAPolicies' = [ordered]@{ SimRichtlinie = 1; SimDrucker = '\\prn01\Etage2' }
            'SOFTWARE\Policies\Citrix\UserProfileManager' = [ordered]@{ PathToUserStore = '\\fs01\upm$\%USERNAME%.%USERDOMAIN%'; ServiceActive = 1 }
            # WEM agent
            'SOFTWARE\Policies\Norskale\Agent Host' = [ordered]@{ BrokerSvcName = 'wem01.klinik.example' }
            'SYSTEM\CurrentControlSet\Control\Norskale\Agent Host' = [ordered]@{ AgentCacheAlternateLocation = 'D:\WEMCache' }
            'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' = [ordered]@{ GpNetworkStartTimeoutPolicyValue = 120 }
            # security products, time source, update policy; AppLocker: only the number of rule subkeys is read
            'SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status' = [ordered]@{ OnboardingState = 1 }
            'SYSTEM\CurrentControlSet\Services\W32Time\Parameters' = [ordered]@{ Type = 'NTP'; NtpServer = 'zeit01.klinik.example,0x8 10.1.0.20,0x8' }
            'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' = [ordered]@{ AUOptions = 4; ScheduledInstallDay = 0; ScheduledInstallTime = 10; NoAutoRebootWithLoggedOnUsers = 0 }
            'SOFTWARE\Policies\Microsoft\Windows\SrpV2' = [ordered]@{}
            'SOFTWARE\Policies\Microsoft\Windows\SrpV2\Exe' = [ordered]@{ EnforcementMode = 1 }
            'SOFTWARE\Policies\Microsoft\Windows\SrpV2\Exe\{00000000-0000-0000-0000-00000000e001}' = [ordered]@{ Value = '<SimRegel/>' }
            'SOFTWARE\Policies\Microsoft\Windows\SrpV2\Exe\{00000000-0000-0000-0000-00000000e002}' = [ordered]@{ Value = '<SimRegel/>' }
            'SOFTWARE\Policies\Microsoft\Windows\SrpV2\Exe\{00000000-0000-0000-0000-00000000e003}' = [ordered]@{ Value = '<SimRegel/>' }
            'SOFTWARE\Policies\Microsoft\Windows\SrpV2\Dll' = [ordered]@{ EnforcementMode = 1 }
            'SOFTWARE\Policies\Microsoft\Windows\SrpV2\Dll\{00000000-0000-0000-0000-00000000d001}' = [ordered]@{ Value = '<SimRegel/>' }
            # applications of src/apps.json (invented values; the forced extensions may carry addresses, only their number is read)
            'SOFTWARE\Microsoft\Office\ClickToRun\Configuration' = [ordered]@{ UpdateChannel = 'http://officecdn.microsoft.com/pr/00000000-0000-0000-0000-000000000000'
                UpdateUrl = '\\fs01\office$\updates'; VersionToReport = '16.0.17932.20162'; Platform = 'x64'; UpdatesEnabled = 'False' }
            'SOFTWARE\Policies\Microsoft\office\16.0\Common\officeupdate' = [ordered]@{ hideenabledisableupdates = 1 }
            'SOFTWARE\Policies\Microsoft\Edge' = [ordered]@{ StartupBoostEnabled = 0; SleepingTabsEnabled = 0; UserDataDir = '\\fs01\edge$\daten' }
            'SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist' = [ordered]@{ '1' = 'abcdefghijklmnopabcdefghijklmnop'
                '2' = 'ponmlkjihgfedcbaponmlkjihgfedcba;https://intern.klinik.example/ext' }
            'SOFTWARE\Policies\Microsoft\EdgeUpdate' = [ordered]@{ UpdateDefault = 0 }
            'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' = [ordered]@{ pv = '130.0.2849.80' }
            'SOFTWARE\Microsoft\Teams' = [ordered]@{ disableAutoUpdate = 1 }
            'SOFTWARE\Microsoft\Office\Outlook\Addins' = [ordered]@{}
            'SOFTWARE\Microsoft\Office\Outlook\Addins\Sim.Addin1' = [ordered]@{}
            'SOFTWARE\Microsoft\Office\Outlook\Addins\Sim.Addin2' = [ordered]@{}
        }
        # loaded file system filters (Get-WorkerPerfFilterRaw); FiltersFail: exception the filter query throws
        Filters = @(@('WdFilter', '328010', 4), @('upmjit', '182400', 2), @('FileInfo', '45000', 5)) | ForEach-Object {
            [ordered]@{ Name = $_[0]; Altitude = $_[1]; Instances = [int]$_[2]; Legacy = $false } }
        FiltersFail = $null
        # scheduled tasks (Get-WorkerPerfTaskRaw): Count of all, Tasks outside \Microsoft\; times as the Task Scheduler gives
        # them ("no run" is 1899-12-30)
        Tasks = @{ Count = 150; Tasks = @(
                @{ Path = '\Sim\Inventarlauf'; Enabled = $true; State = 'Ready'; NextRun = [datetime]::Today.AddDays(1).AddHours(10); LastRun = [datetime]'1899-12-30'
                    TriggerTypes = [int[]]@(2); RepeatMinutes = 0; Action = 'C:\Tools\inventar.exe' }
                @{ Path = '\Sim\Anmeldeskript'; Enabled = $true; State = 'Ready'; NextRun = [datetime]'1899-12-30'; LastRun = [datetime]'1899-12-30'
                    TriggerTypes = [int[]]@(9); RepeatMinutes = 0; Action = 'C:\Tools\logon.cmd' }) }
        # files (Get-WorkerPerfFileVersion, Get-WorkerPerfPathKind, Get-WorkerPerfDirectoryMatches): path -> product version
        # ('' for none); every path above a key is a folder. Two folders of the new Teams: the higher version counts.
        FileVersions = @{
            'C:\Program Files\Citrix\User Profile Manager\UserProfileManager.exe' = '22.3.0.4000'
            'C:\Program Files (x86)\Citrix\Workspace Environment Management Agent\Citrix.Wem.Agent.Service.exe' = '2407.1.0.1'
            'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' = '130.0.2849.80'
            'C:\Program Files\WindowsApps\MSTeams_24193.1805.3040.8975_x64__8wekyb3d8bbwe\ms-teams.exe' = '24193.1805.3040.8975'
            'C:\Program Files\WindowsApps\MSTeams_24277.3502.3161.3007_x64__8wekyb3d8bbwe\ms-teams.exe' = '24277.3502.3161.3007'
            'C:\Program Files (x86)\Microsoft\TeamsMeetingAdd-in' = ''
        }
        # FileProbeFail: path pattern (-like) -> exception the file stand-ins throw for a matching path
        FileProbeFail = @{}
        # single tasks of the Task Scheduler by full path (Get-WorkerPerfTaskInfo)
        TaskByPath = @{
            '\Microsoft\Office\Office Automatic Updates 2.0' = @{ Enabled = $true; LastRun = [datetime]::Now.AddDays(-1); NextRun = [datetime]::Today.AddDays(1).AddHours(3) }
        }
        # CIM classes besides the fixed ones of Get-CimInstance: class -> objects; Citrix_VirtualDesktopInfo missing here
        # means its namespace is missing (New-WinStandInMissingNamespace)
        Cim = @{
            'Win32_TSSessionSetting' = @('RDP-Tcp', 'ICA-CGP') | ForEach-Object {
                [pscustomobject]@{ TerminalName = $_; IdleSessionLimit = [uint32]0; DisconnectedSessionLimit = [uint32]0; ActiveSessionLimit = [uint32]0
                    BrokenConnectionAction = [uint32]0; PolicySourceDisconnectedSessionLimit = [uint32]0; TimeLimitPolicy = [uint32]1 } }
            # Status is a bit field: 9 = temporary and corrupted
            'Win32_UserProfile' = @(
                [pscustomobject]@{ LocalPath = 'C:\Users\mueller'; Loaded = $true; Special = $false; LastUseTime = [datetime]::Now; Status = [uint32]0 }
                [pscustomobject]@{ LocalPath = 'C:\Users\gast'; Loaded = $false; Special = $false; LastUseTime = [datetime]::Now.AddDays(-40); Status = [uint32]0 }
                [pscustomobject]@{ LocalPath = 'C:\Users\TEMP'; Loaded = $false; Special = $false; LastUseTime = [datetime]::Now.AddDays(-2); Status = [uint32]9 }
                [pscustomobject]@{ LocalPath = 'C:\Windows\ServiceProfiles\NetworkService'; Loaded = $true; Special = $true; LastUseTime = [datetime]::Now; Status = [uint32]0 })
            'Citrix_VirtualDesktopInfo' = @([pscustomobject]@{ PersistentDataLocation = 'D:\PersistentData' })
            'Win32_PageFileUsage' = @([pscustomobject]@{ Name = 'C:\pagefile.sys'; AllocatedBaseSize = [uint32]16384; PeakUsage = [uint32]2100; TempPageFile = $false })
            'Win32_NetworkAdapter' = @([pscustomobject]@{ Name = 'vmxnet3 Ethernet Adapter'; ServiceName = 'vmxnet3ndis6'; Speed = [uint64]10000000000; NetEnabled = $true })
            'Win32_SCSIController' = @([pscustomobject]@{ Name = 'VMware PVSCSI Controller'; DriverName = 'pvscsi' })
            'Win32_SystemDriver' = @([pscustomobject]@{ Name = 'vmmemctl'; State = 'Running'; StartMode = 'System' })
            'Win32_QuickFixEngineering' = @([pscustomobject]@{ HotFixID = 'KB5000001'; InstalledOn = [datetime]'2026-09-10' },
                [pscustomobject]@{ HotFixID = 'KB5000002'; InstalledOn = [datetime]'2026-10-14' })
            'Win32_LogicalDisk' = @([pscustomobject]@{ DeviceID = 'C:'; Size = [uint64]100GB; FreeSpace = [uint64]8GB; FileSystem = 'NTFS' },
                [pscustomobject]@{ DeviceID = 'D:'; Size = [uint64]200GB; FreeSpace = [uint64]150GB; FileSystem = 'NTFS' })
            # Defender: status and preferences (the scan times as a TimeSpan, as newer platforms give them)
            'MSFT_MpComputerStatus' = @([pscustomobject]@{ AMRunningMode = 'Normal'; RealTimeProtectionEnabled = $true; IsTamperProtected = $true
                    AntivirusSignatureAge = [uint32]1; DefenderSignaturesOutOfDate = $false; AMProductVersion = '4.18.24090.11' })
            'MSFT_MpPreference' = @([pscustomobject]@{ ExclusionPath = [string[]]@('C:\Program Files\Citrix')
                    ExclusionProcess = [string[]]@('C:\Program Files\Citrix\User Profile Manager\UserProfileManager.exe'); ExclusionExtension = [string[]]@('.vhdx')
                    SharedSignaturesPath = ''; ScanScheduleDay = [byte]0; ScanScheduleTime = [timespan]'02:00:00'; ScanScheduleQuickScanTime = [timespan]'02:00:00'
                    ScanParameters = [byte]1; RandomizeScheduleTaskTimes = $true; ScanAvgCPULoadFactor = [byte]50; EnableNetworkProtection = [byte]0
                    ScanScheduleOffset = [uint32]120 })
            # SMB client: its configuration and the open connections (with the account, which is not stored)
            'MSFT_SmbClientConfiguration' = @([pscustomobject]@{ RequireSecuritySignature = $false; DirectoryCacheEntriesMax = [uint32]16
                    FileInfoCacheEntriesMax = [uint32]64; FileNotFoundCacheEntriesMax = [uint32]128 })
            'MSFT_SmbConnection' = @(
                [pscustomobject]@{ ServerName = 'fs01'; ShareName = 'upm$'; Dialect = '3.1.1'; Signed = $true; Encrypted = $false; UserName = 'KLINIK\mueller' }
                [pscustomobject]@{ ServerName = 'fs01'; ShareName = 'upm$'; Dialect = '3.1.1'; Signed = $true; Encrypted = $false; UserName = 'KLINIK\gast' }
                [pscustomobject]@{ ServerName = 'alt01'; ShareName = 'archiv'; Dialect = '2.1'; Signed = $false; Encrypted = $false; UserName = 'KLINIK\mueller' })
            'Win32_NetworkAdapterConfiguration' = @([pscustomobject]@{ Index = [uint32]4; DNSServerSearchOrder = [string[]]@('10.1.0.10') })
            # DNS servers per interface and address family (2 IPv4, 23 IPv6); without a configured IPv6 server Windows shows
            # the placeholders fec0:0:0:ffff::1 to ::3; interface 9 has no server; InterfaceAlias is not stored
            'MSFT_DNSClientServerAddress' = @(
                [pscustomobject]@{ InterfaceAlias = 'Ethernet0'; InterfaceIndex = [uint32]4; AddressFamily = [uint16]2; ServerAddresses = [string[]]@('10.1.0.10') }
                [pscustomobject]@{ InterfaceAlias = 'Ethernet0'; InterfaceIndex = [uint32]4; AddressFamily = [uint16]23
                    ServerAddresses = [string[]]@('fec0:0:0:ffff::1', 'fec0:0:0:ffff::2', 'fec0:0:0:ffff::3') }
                [pscustomobject]@{ InterfaceAlias = 'Loopback Pseudo-Interface 1'; InterfaceIndex = [uint32]1; AddressFamily = [uint16]23
                    ServerAddresses = [string[]]@('fec0:0:0:ffff::1', 'fec0:0:0:ffff::2', 'fec0:0:0:ffff::3') }
                [pscustomobject]@{ InterfaceAlias = 'Ethernet1'; InterfaceIndex = [uint32]9; AddressFamily = [uint16]2; ServerAddresses = [string[]]@() })
            # Name is the connection name of the adapter, which is not stored
            'MSFT_NetAdapterRssSettingData' = @([pscustomobject]@{ Name = 'Ethernet0'; InterfaceDescription = 'vmxnet3 Ethernet Adapter'; Enabled = $true })
            # the global TCP/IP offload settings of Windows (ReceiveSideScaling: 0 Disabled, 1 Enabled)
            'MSFT_NetOffloadGlobalSetting' = @([pscustomobject]@{ ReceiveSideScaling = [byte]1 })
        }
        # Win32_Service: every service carries all six properties (the readers run under strict mode)
        Services = @(
            @('RpcSs', 900, 'Running', 'Auto', '', ''), @('Spooler', 0, 'Running', 'Auto', '', ''),
            @('VMTools', 0, 'Running', 'Auto', '', ''), @('WinDefend', 0, 'Running', 'Auto', '', ''), @('Sense', 0, 'Running', 'Auto', '', ''),
            @('AppIDSvc', 0, 'Running', 'Auto', '', ''), @('W32Time', 0, 'Running', 'Auto', '', ''),
            @('BrokerAgent', 0, 'Running', 'Auto', 'Citrix Desktop Service', '"C:\Program Files\Citrix\Virtual Desktop Agent\BrokerAgent.exe"'),
            @('ctxProfile', 0, 'Running', 'Auto', '', '"C:\Program Files\Citrix\User Profile Manager\UserProfileManager.exe"'),
            # invented short names: the readers go by display name and program path
            @('WemAgentSvc', 0, 'Running', 'Auto', 'Citrix WEM Agent Host Service', '"C:\Program Files (x86)\Citrix\Workspace Environment Management Agent\Citrix.Wem.Agent.Service.exe"'),
            @('WemLogonSvc', 0, 'Running', 'Auto', 'Citrix WEM User Logon Service', '"C:\Program Files (x86)\Citrix\Workspace Environment Management Agent\Citrix.Wem.Agent.LogonService.exe"'),
            @('CtxTeamsSvc', 0, 'Running', 'Auto', 'Citrix HDX Teams Redirection Service', '"C:\Program Files (x86)\Citrix\System32\CtxSvcHost.exe" -g TeamsSvcs'),
            @('CtxHdxWebSocketService', 0, 'Running', 'Auto', 'Citrix HDX HTML5 Video Redirection Service', '"C:\Program Files (x86)\Citrix\System32\WebSocketService.exe" /service'),
            @('CpSvc', 0, 'Running', 'Auto', 'Citrix Print Manager Service', 'C:\Program Files\Citrix\System32\CpSvc.exe'),
            @('SENS', 0, 'Running', 'Auto', 'System Event Notification Service', ''), @('wuauserv', 0, 'Stopped', 'Manual', 'Windows Update', ''),
            @('edgeupdate', 0, 'Stopped', 'Manual', 'Microsoft Edge Update Service (edgeupdate)', '')
        ) | ForEach-Object {
            $display = $(if ($_[4]) { $_[4] } else { $_[0] })
            [pscustomobject]@{ Name = $_[0]; DisplayName = $display; State = $_[2]; StartMode = $_[3]; PathName = $_[5]; ProcessId = [uint32]$_[1] }
        }
        PerformanceInfo = @{ CommitTotalMB = 36864; CommitLimitMB = 81920; CommitPeakMB = 60000 }
        PowerScheme = '381b4222-f694-41f0-9685-ff5bb260df2e'
        # per log of events.json: what Get-WinEvent -ListLog adds, and the time of the oldest entry
        LogInfo = @{}; LogOldest = @{}
    }
    foreach ($name in $script:WinFake.Logs) {
        $script:WinFake.LogInfo[$name] = @{ MaximumSizeInBytes = [long]20971520; FileSize = [long]12582912; RecordCount = [long]30000
            LogMode = [WinStandInLogMode]::Circular; IsLogFull = $false }
        $script:WinFake.LogOldest[$name] = [datetime]::Now.AddDays(-30)
    }
    $script:WinFake.Sessions.Add([pscustomobject]@{ SessionId = 0; State = 'Disconnected'; WinStation = 'Services'; User = ''; Domain = ''; ClientName = ''
            LogonTime = [datetime]::MinValue; IdleSec = -1 })
    $script:WinFake.Sessions.Add([pscustomobject]@{ SessionId = 2; State = 'Active'; WinStation = 'ICA-CGP#0'; User = 'mueller'; Domain = 'KLINIK'; ClientName = 'WS-0001'
            LogonTime = [datetime]::Now.AddHours(-1); IdleSec = 4 })
    Add-WinStandInDisk 'mueller' 'C:\Users\mueller_UPM_local\UpmTempMount' 137
    Add-WinStandInDisk 'gast' 'C:\Users\gast_UPM_local\UpmTempMount' 139 32212254720

    # events as ToXml() gives them (invented values); Application Error 1000 in the classic layout with unnamed data fields
    $defender = 'Microsoft-Windows-Windows Defender'; $dlog = 'Microsoft-Windows-Windows Defender/Operational'
    Add-WinStandInEvent $dlog $defender 1001 4 (-1) "Die Ueberpruefung wurde beendet.`r`nScan-ID: {1}"
    Add-WinStandInEvent $dlog $defender 1000 4 (-2) 'Die Ueberpruefung wurde gestartet.'
    Add-WinStandInEvent $dlog $defender 1000 4 (-180) 'alt'
    $crash = @('EXCEL.EXE', '16.0.18129.20158', '65a1b2c3', 'vbe7.dll', '7.1.10.98', '5f00aa11', 'c0000005', '000e1f2c', '1f1c',
        ('{0:x16}' -f [datetime]::UtcNow.AddHours(-2).ToFileTimeUtc()), 'C:\Programme\EXCEL.EXE', 'C:\Programme\vbe7.dll', '00000000-0000-0000-0000-000000000001', '', '')
    Add-WinStandInEvent 'Application' 'Application Error' 1000 2 (-3) 'Name der fehlerhaften Anwendung: EXCEL.EXE, Version: 16.0.18129.20158' -Data $crash -Sid 'S-1-5-21-1000-2000-3000-1108'
    Add-WinStandInEvent 'Application' 'Citrix Profile Management' 1003 3 (-4) 'Sim-Warnung der Profilverwaltung' -Data @('a', 'b')
    Add-WinStandInEvent 'Application' 'Citrix Profile Management' 1000 4 (-4) 'Sim-Information der Profilverwaltung' -Data @('a')
    Add-WinStandInEvent 'Application' 'Sim Sitzungsdienst' 1002 2 (-4) 'nicht im Katalog' -Data @('a')
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
                             [hashtable]$Named = $null, [hashtable]$UserData = $null, [string]$Binary = '', [string]$Sid = '', $At = $null) {
    # At: the exact time (else now plus Minutes); every event gets its record id once, as the event log does
    $script:WinFake.RecordId++
    $time = $(if ($At -is [datetime]) { $At } else { [datetime]::Now.AddMinutes($Minutes) })
    $script:WinFake.Events.Add(@{ LogName = $Log; ProviderName = $Provider; Id = $Id; Level = $Level; TimeCreated = $time; RecordId = [long]$script:WinFake.RecordId
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
    # like an EventLogRecord: TimeCreated (local), RecordId, ToXml(), FormatDescription() (throws for Unformattable), Dispose()
    $script:WinFake.OpenRecords++
    $o = [pscustomobject]@{ ProviderName = $E.ProviderName; Id = $E.Id; LevelValue = $E.Level; TimeCreated = $E.TimeCreated; LogName = $E.LogName
        RecordId = [long]$E.RecordId; Text = $E.Message; Xml = $E.Xml; Disposed = $false }
    $o | Add-Member -MemberType ScriptMethod -Name ToXml -Value { $this.Xml }
    $o | Add-Member -MemberType ScriptMethod -Name FormatDescription -Value {
        if ($script:WinFake.Unformattable -contains $this.RecordId) { throw (New-Object System.InvalidOperationException 'Meldungsdatei fehlt') }
        $this.Text
    }
    $o | Add-Member -MemberType ScriptMethod -Name Dispose -Value { if (-not $this.Disposed) { $this.Disposed = $true; $script:WinFake.OpenRecords-- } }
    $o
}

function Add-WinStandInDisk([string]$User, [string]$Mount, [int]$Volume, [uint64]$FreeBytes = 2147483648) {
    # a container of 50 GB (20 GB allocated in its file) and its volume with FreeBytes free
    $n = $script:WinFake.Disks.Count + 3
    $guid = '\\?\Volume{{00000000-0000-0000-0000-{0:d12}}}\' -f $Volume
    $script:WinFake.Volumes.Add([pscustomobject]@{ Path = $guid; Size = [uint64]53687091200; SizeRemaining = $FreeBytes })
    $script:WinFake.Disks.Add([pscustomobject]@{ Number = $n; Location = "\\fs01\upm$\$User.KLINIK\Win2022\UPM_Profile\ProfileContainer_RW.vhdx"
            Size = [uint64]53687091200; AllocatedSize = [uint64]21474836480
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

function Add-WinStandInCall([string]$Key) {
    # counts the call; for every key but cim:<class> (Get-CimInstance waits itself, within its time limit) the stand-in
    # then waits Delay[key], or once DelayOnce[key]
    $c = $script:WinFake.Calls
    if ($c.ContainsKey($Key)) { $c[$Key]++ } else { $c[$Key] = 1 }
    if ($Key.StartsWith('cim:')) { return }
    $wait = Get-WinStandInDelay $Key
    if ($wait -gt 0) { Start-Sleep -Milliseconds $wait }
}

function Get-WinStandInDelay([string]$Key) {
    # the milliseconds to wait before the call with this key; a DelayOnce entry is used up
    $wait = 0
    if ($script:WinFake.Delay.ContainsKey($Key)) { $wait = [int]$script:WinFake.Delay[$Key] }
    if ($script:WinFake.DelayOnce.ContainsKey($Key)) { $wait = [int]$script:WinFake.DelayOnce[$Key]; $script:WinFake.DelayOnce.Remove($Key) }
    return $wait
}

function New-WinStandInDenied([string]$Kind) {
    # denied access in the form Windows reports it: 'cim' as Get-CimInstance does (NativeErrorCode AccessDenied),
    # 'win32' as a Win32Exception with code 5
    switch ($Kind) {
        'cim' { return (New-Object WinStandInCimException 'Zugriff verweigert') }
        'win32' { return (New-Object System.ComponentModel.Win32Exception -ArgumentList 5) }
    }
    throw "Stand-in kennt die Art '$Kind' nicht"
}

function New-WinStandInMissingNamespace {
    # a CIM query into a namespace that does not exist, as Get-CimInstance reports it (NativeErrorCode InvalidNamespace)
    return (New-Object WinStandInCimException -ArgumentList 'Ungueltiger Namespace', 'InvalidNamespace')
}

function New-WinStandInMissingClass {
    # a CIM query for a class that does not exist in its namespace, as Get-CimInstance reports it (NativeErrorCode InvalidClass)
    return (New-Object WinStandInCimException -ArgumentList 'Ungueltige Klasse', 'InvalidClass')
}

function New-WinStandInTimedOut([uint32]$Code) {
    # a failed CIM call as Get-CimInstance reports it: the native error code in error_Code of ErrorData
    $ex = New-Object WinStandInCimErrorException 'Abfrage gescheitert'
    $ex.ErrorData = [pscustomobject]@{ CimInstanceProperties = @{ error_Code = [pscustomobject]@{ Name = 'error_Code'; Value = $Code } } }
    return $ex
}

function Test-WorkerPerfElevated { return $true }

function Test-WorkerPerfWinCounter([string]$Category, [string]$Counter) {
    Add-WinStandInCall ('check:' + $Category)
    if ($script:WinFake.ThrowCheck -eq $Category) { throw (New-Object InvalidOperationException 'Leistungsindikatoren beschaedigt') }
    if (-not $script:WinFake.Perf.ContainsKey($Category)) { return 'Kategorie nicht vorhanden' }
    if ($Counter -and -not $script:WinFake.Perf[$Category].ContainsKey($Counter)) { return "Zaehler '$Counter' fehlt" }
    return ''
}

function Open-WorkerPerfWinCategory([string]$Name) {
    Add-WinStandInCall ('open:' + $Name)
    if (-not $script:WinFake.Perf.ContainsKey($Name)) { return $null }
    return [pscustomobject]@{ CategoryName = $Name }
}

function Read-WorkerPerfWinCategory($Category) {
    # like ReadCategory: counter names in lower case, one entry per instance; the raw value changes with every reading
    $name = $Category.CategoryName
    Add-WinStandInCall ('perf:' + $name)
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
function Get-WinSessionRaw { Add-WinStandInCall 'wts'; return $script:WinFake.Sessions.ToArray() }
function Get-WorkerPerfHealthSessions {
    Add-WinStandInCall 'wts'
    if ($null -ne $script:WinFake.SessionsFail) { throw $script:WinFake.SessionsFail }
    return $script:WinFake.Sessions.ToArray()
}

function Get-CimClass {
    [CmdletBinding()] param([string]$ClassName, [string]$Namespace, [int]$OperationTimeoutSec)
    Add-WinStandInCall ('cimclass:' + $ClassName)
    if ($Namespace -eq 'root\citrix\euem' -and $script:WinFake.EuemClass) { return [pscustomobject]@{ CimClassName = $ClassName } }
    if ($ClassName -eq 'MSFT_PrinterDriver' -and $script:WinFake.PrintDriverClass) { return [pscustomobject]@{ CimClassName = $ClassName } }
    throw "Klasse $ClassName nicht gefunden"
}

function Get-CimInstance {
    [CmdletBinding()] param([string]$ClassName, [string]$Namespace, [string]$Filter, [string[]]$Property, [int]$OperationTimeoutSec)
    Add-WinStandInCall ('cim:' + $ClassName)
    # a delay longer than the time limit of the call ends at the limit, as on Windows
    $wait = Get-WinStandInDelay ('cim:' + $ClassName)
    if ($wait -gt 0) {
        $limit = $wait
        if ($OperationTimeoutSec -gt 0) { $limit = [Math]::Min($wait, $OperationTimeoutSec * 1000) }
        Start-Sleep -Milliseconds $limit
        if ($limit -lt $wait) { throw (New-Object System.TimeoutException "Zeitlimit der Abfrage von $ClassName ueberschritten") }
    }
    if ($script:WinFake.CimFail.ContainsKey($ClassName)) { throw $script:WinFake.CimFail[$ClassName] }
    switch ($ClassName) {
        'Win32_ComputerSystem' {
            [pscustomobject]@{ Name = 'VDA-TEST'; NumberOfLogicalProcessors = 6; TotalPhysicalMemory = [uint64]62277025792; NumberOfProcessors = 2
                AutomaticManagedPagefile = $false; HypervisorPresent = $true; Manufacturer = 'VMware, Inc.'; Model = 'VMware7,1'; PartOfDomain = $true }
        }
        'Win32_OperatingSystem' {
            [pscustomobject]@{ Caption = 'Microsoft Windows Server 2022 Standard'; Version = '10.0.20348'; LastBootUpTime = [datetime]::Now.AddDays(-2); SystemDrive = 'C:' }
        }
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
        'Win32_Service' {
            # without a filter every service; with the filter of Get-WorkerPerfServices exactly RpcSs and Spooler, as before
            if (-not $Filter) { $script:WinFake.Services }
            elseif ($Filter -eq 'ProcessId > 0') { $script:WinFake.Services | Where-Object { @('RpcSs', 'Spooler') -contains $_.Name } }
            else { throw "Stand-in kennt den Filter $Filter nicht" }
        }
        'MSFT_PrinterDriver' { if (-not $script:WinFake.PrintDriverClass) { throw 'Klasse MSFT_PrinterDriver nicht gefunden' }; $script:WinFake.Drivers }
        'MSFT_Disk' { $script:WinFake.DiskQueries++; if ($script:WinFake.FailStorage) { throw 'Zeitlimit der Speicherabfrage' }; $script:WinFake.Disks.ToArray() }
        'MSFT_Partition' { foreach ($d in $script:WinFake.Disks) { $d.Partitions } }
        'MSFT_Volume' { $script:WinFake.Volumes.ToArray() }
        'Citrix_Euem_RoundTrip' {
            if ($script:WinFake.FailCitrix) { throw 'Citrix-WMI antwortet nicht' }
            [pscustomobject]@{ SessionID = [uint32]2; RoundtripTime = [uint32]40; NetworkLatency = [uint32]20; InstanceId = 'a'; ProcessId = '1' }
        }
        default {
            # any other class from Cim, without regard to the filter; without Citrix_VirtualDesktopInfo its namespace is missing
            if (-not $script:WinFake.Cim.ContainsKey($ClassName)) {
                if ($ClassName -eq 'Citrix_VirtualDesktopInfo') { throw (New-WinStandInMissingNamespace) }
                throw "Stand-in kennt $ClassName nicht"
            }
            $script:WinFake.Cim[$ClassName]
        }
    }
}

function ConvertFrom-WinStandInQuery([xml]$Xml) {
    # The selects of a structured query as the source writes them: @{ Path; Provider; Ids; Levels; After (>=), Before (<=) }.
    # Only the forms the source writes are understood; anything else fails the test.
    foreach ($q in @($Xml.QueryList.Query)) {
        if ($null -eq $q.Attributes['Id']) { throw 'Die angegebene Abfrage ist ungueltig (Query ohne Id)' }
        foreach ($sel in @($q.Select)) {
            $x = [string]$sel.InnerText
            # Windows takes the provider literal in ' (as Event Viewer writes it); a literal in " is refused here
            $m = [regex]::Match($x, "^\*\[System\[Provider\[@Name='([^']*)'\](.*) and TimeCreated\[@SystemTime>='([0-9TZ:.\-]+)'(?: and @SystemTime<='([0-9TZ:.\-]+)')?\]\]\]$")
            if (-not $m.Success) { throw "Stand-in versteht die Abfrage nicht: $x" }
            $mid = $m.Groups[2].Value
            $ids = @([regex]::Matches($mid, 'EventID=(\d+)') | ForEach-Object { [int]$_.Groups[1].Value })
            $levels = @([regex]::Matches($mid, 'Level=(\d+)') | ForEach-Object { [int]$_.Groups[1].Value })
            if (($mid -replace '\(EventID=\d+( or EventID=\d+)*\)', '' -replace '\(Level=\d+( or Level=\d+)*\)', '' -replace ' and ', '').Trim().Length -gt 0) { throw "Stand-in versteht die Abfrage nicht: $x" }
            # every comparison counts against the 32 expressions of a select: provider, ids, levels, time bounds
            $expr = 1 + $ids.Count + $levels.Count + 1 + [int]$m.Groups[4].Success
            if ($expr -gt 32) { throw "Die angegebene Abfrage ist ungueltig ($expr Ausdruecke)" }
            $parse = { param($t) [datetime]::ParseExact($t, "yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal) }
            @{ Path = [string]$sel.Path; QueryPath = [string]$q.Path; Provider = $m.Groups[1].Value; Ids = $ids; Levels = $levels; After = (& $parse $m.Groups[3].Value)
                Before = $(if ($m.Groups[4].Success) { & $parse $m.Groups[4].Value } else { $null }) }
        }
    }
}

function Get-WinEvent {
    # like Get-WinEvent -ListLog (IsEnabled and the sizes, record count, mode and full flag from LogInfo); the source reads
    # events through Open-WorkerPerfEventReader, anything else fails. A missing log is reported with the error id of
    # Windows (NoMatchingLogsFound), a log in LogFail with its exception.
    [CmdletBinding()] param([string]$ListLog, [hashtable]$FilterHashtable, [xml]$FilterXml, [long]$MaxEvents = -1, [switch]$Oldest)
    Add-WinStandInCall $(if ($ListLog) { 'winevent:list' } else { 'winevent:read' })
    if (-not $ListLog) { throw 'Stand-in: Ereignisse liest die Quelle ueber Open-WorkerPerfEventReader, nicht ueber Get-WinEvent' }
    if ($script:WinFake.LogFail.ContainsKey($ListLog)) { throw $script:WinFake.LogFail[$ListLog] }
    if ($script:WinFake.Logs -contains $ListLog) {
        $info = $script:WinFake.LogInfo[$ListLog]
        $field = { param($n) if ($null -ne $info -and $info.ContainsKey($n)) { $info[$n] } else { $null } }
        return [pscustomobject]@{ LogName = $ListLog; IsEnabled = ($script:WinFake.DisabledLogs -notcontains $ListLog)
            MaximumSizeInBytes = (& $field 'MaximumSizeInBytes'); FileSize = (& $field 'FileSize'); RecordCount = (& $field 'RecordCount')
            LogMode = (& $field 'LogMode'); IsLogFull = (& $field 'IsLogFull') }
    }
    $PSCmdlet.ThrowTerminatingError((New-Object System.Management.Automation.ErrorRecord ((New-Object System.Exception "Protokoll $ListLog nicht vorhanden"),
                'NoMatchingLogsFound', ([System.Management.Automation.ErrorCategory]::ObjectNotFound), $ListLog)))
}

function Open-WorkerPerfEventReader([string]$QueryXml, [bool]$Oldest) {
    # like an EventLogReader over the structured query: the selects (provider, ids, levels, SystemTime bounds as UTC
    # literals, the way the event log compares them) pick the fake events, newest first unless Oldest. An event that
    # two selects name comes once per select (the worst case for the source's de-duplication). ReadEvent() returns
    # the next record or $null at the end; FailLogs, ReadFailOnce and ReadFailAlways inject failures.
    Add-WinStandInCall 'winevent:read'
    $xml = [xml]$QueryXml
    $script:WinFake.EventQueries++
    $script:WinFake.Queries.Add($xml.OuterXml)
    $selects = @(ConvertFrom-WinStandInQuery $xml)
    $log = $selects[0].QueryPath
    foreach ($sel in $selects) { if ($sel.Path -ne $log) { throw 'Stand-in: Select und Query nennen verschiedene Protokolle' } }
    if ($script:WinFake.FailLogs.ContainsKey($log)) { throw (New-Object ($script:WinFake.FailLogs[$log]) "Protokoll $log nicht lesbar") }
    # a log that is switched off still holds its events and can be read, as on Windows (M14)
    if ($script:WinFake.Logs -notcontains $log) { throw (New-Object System.IO.FileNotFoundException "Protokoll $log nicht vorhanden") }
    $all = @($script:WinFake.Events | Where-Object { $_.LogName -eq $log })
    if ($log -like '*Defender*' -and $script:WinFake.ManyEvents -gt 0) {
        # one event per second, each with its own fixed record id
        $xmlMany = New-WinStandInXml 'Microsoft-Windows-Windows Defender' 1000 4 @() $null $null '' ''
        $now = [datetime]::Now
        $all = @(foreach ($k in 1..$script:WinFake.ManyEvents) {
                @{ LogName = $log; ProviderName = 'Microsoft-Windows-Windows Defender'; Id = 1000; Level = 4; TimeCreated = $now.AddSeconds(-$k); Message = "Ereignis $k"
                    RecordId = [long](1000000 + $k); Xml = $xmlMany }
            })
    }
    $hits = New-Object System.Collections.Generic.List[object]
    foreach ($sel in $selects) {
        foreach ($e in $all) {
            if ($e.ProviderName -ne $sel.Provider) { continue }
            if ($sel.Ids.Count -gt 0 -and $sel.Ids -notcontains $e.Id) { continue }
            if ($sel.Levels.Count -gt 0 -and $sel.Levels -notcontains $e.Level) { continue }
            $u = $e.TimeCreated.ToUniversalTime()
            if ($u -lt $sel.After) { continue }
            if ($null -ne $sel.Before -and $u -gt $sel.Before) { continue }
            $hits.Add($e)
        }
    }
    $items = @($hits.ToArray() | Sort-Object -Property @{ Expression = { $_.TimeCreated.ToUniversalTime() }; Descending = (-not $Oldest) })
    $script:WinFake.OpenReaders++
    $reader = [pscustomobject]@{ Items = $items; Pos = 0; Log = $log; Disposed = $false }
    $reader | Add-Member -MemberType ScriptMethod -Name ReadEvent -Value {
        $script:WinFake.ReadCalls++
        if ($script:WinFake.ReadFailAlways -contains $this.Log) { throw (New-Object System.InvalidOperationException 'Ereignis nicht lesbar') }
        if ($this.Pos -ge @($this.Items).Count) { return $null }
        $e = $this.Items[$this.Pos]; $this.Pos++
        if ($script:WinFake.ReadFailOnce.Contains([long]$e.RecordId)) {
            [void]$script:WinFake.ReadFailOnce.Remove([long]$e.RecordId)
            throw (New-Object System.InvalidOperationException 'Ereignis beschaedigt')
        }
        New-WinStandInRecord $e
    }
    $reader | Add-Member -MemberType ScriptMethod -Name Dispose -Value { if (-not $this.Disposed) { $this.Disposed = $true; $script:WinFake.OpenReaders-- } }
    $reader
}

function Get-WorkerPerfSidAccount([string]$Sid) {
    $script:WinFake.SidLookups++
    if ($script:WinFake.SidTimeout -contains $Sid) { return @{ Name = ''; TimedOut = $true } }
    return @{ Name = [string]$script:WinFake.Sids[$Sid]; TimedOut = $false }
}

function Get-WorkerPerfPrintIsolationGroups { Add-WinStandInCall 'registry:print'; return $script:WinFake.IsolationGroups }
function Get-WorkerPerfPrintIsolationPolicy {
    Add-WinStandInCall 'registry:print'
    if ($null -ne $script:WinFake.IsolationPolicyFail) { throw $script:WinFake.IsolationPolicyFail }
    return $script:WinFake.IsolationPolicy
}
function Get-WorkerPerfPrintDriverAttribute($Driver) { Add-WinStandInCall 'registry:print'; return $script:WinFake.DriverAttributes[[string]$Driver.Name] }

# health picture: registry, native calls and the oldest entry of a log
function Get-WorkerPerfRegistryValues([string]$SubKey) {
    # values come back as they stand in Registry, like the thin call, which does not expand REG_EXPAND_SZ (%USERNAME% stays)
    Add-WinStandInCall ('registry:' + $SubKey)
    if ($script:WinFake.RegistryFail.ContainsKey($SubKey)) { throw $script:WinFake.RegistryFail[$SubKey] }
    if (-not $script:WinFake.Registry.ContainsKey($SubKey)) { return $null }
    $values = [ordered]@{}
    foreach ($n in @($script:WinFake.Registry[$SubKey].Keys)) { $values[$n] = $script:WinFake.Registry[$SubKey][$n] }
    return @{ Values = $values; SubKeys = [string[]]@(Get-WinStandInSubKeys $SubKey) }
}

function Get-WinStandInSubKeys([string]$SubKey) {
    # the names of the keys of Registry directly below a key, sorted
    $prefix = $SubKey.TrimEnd('\') + '\'
    $subs = @(foreach ($k in @($script:WinFake.Registry.Keys)) {
            if (([string]$k).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                $rest = ([string]$k).Substring($prefix.Length)
                if ($rest.Length -gt 0 -and -not $rest.Contains('\')) { $rest }
            }
        })
    $subs | Sort-Object
}

function Get-WorkerPerfRegistryKeyInfo([string]$SubKey) {
    # the number of values and of subkeys of a key, as the thin call counts them without reading a value
    Add-WinStandInCall ('registrykey:' + $SubKey)
    if ($script:WinFake.RegistryFail.ContainsKey($SubKey)) { throw $script:WinFake.RegistryFail[$SubKey] }
    if (-not $script:WinFake.Registry.ContainsKey($SubKey)) { return $null }
    return @{ ValueCount = [int]$script:WinFake.Registry[$SubKey].Count; SubKeyCount = [int]@(Get-WinStandInSubKeys $SubKey).Count }
}

function Get-WorkerPerfFileVersion([string]$Path) {
    Add-WinStandInCall 'file:version'
    if ($script:WinFake.FileVersions.ContainsKey($Path)) { return [string]$script:WinFake.FileVersions[$Path] }
    return $null
}

function Assert-WinStandInFileAccess([string]$Path) {
    # throws the exception of the first FileProbeFail pattern the path matches
    foreach ($pattern in @($script:WinFake.FileProbeFail.Keys)) { if ($Path -like $pattern) { throw $script:WinFake.FileProbeFail[$pattern] } }
}

function Get-WorkerPerfPathKind([string]$Path) {
    # 'file' for a key of FileVersions, 'folder' for a path above one, '' for anything else
    Add-WinStandInCall 'file:probe'
    Assert-WinStandInFileAccess $Path
    if ($script:WinFake.FileVersions.ContainsKey($Path)) { return 'file' }
    $prefix = $Path.TrimEnd('\') + '\'
    foreach ($k in @($script:WinFake.FileVersions.Keys)) { if (([string]$k).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return 'folder' } }
    return ''
}

function Get-WorkerPerfDirectoryMatches([string]$Folder, [string]$Pattern) {
    # the folder names directly below Folder (as the paths of FileVersions give them) that match Pattern, once each, in
    # descending order of their names (the order of a real listing is not defined)
    Add-WinStandInCall 'file:dirs'
    Assert-WinStandInFileAccess $Folder
    $prefix = $Folder.TrimEnd('\') + '\'
    $names = @{}
    foreach ($k in @($script:WinFake.FileVersions.Keys)) {
        if (-not ([string]$k).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $rest = ([string]$k).Substring($prefix.Length)
        $cut = $rest.IndexOf('\')
        if ($cut -le 0) { continue }
        $name = $rest.Substring(0, $cut)
        if ($name -like $Pattern) { $names[$name] = $true }
    }
    @($names.Keys) | Sort-Object -Descending
}

function Get-WorkerPerfTaskInfo([string]$Path) {
    # one task by its full path from TaskByPath; $null when it is not there
    Add-WinStandInCall 'com:task'
    if ($script:WinFake.TaskByPath.ContainsKey($Path)) { return $script:WinFake.TaskByPath[$Path].Clone() }
    return $null
}

function Get-WorkerPerfFilterRaw {
    # the filters as ConvertFrom-WorkerPerfFilterBuffer gives them, one record per filter
    Add-WinStandInCall 'native:filters'
    if ($null -ne $script:WinFake.FiltersFail) { throw $script:WinFake.FiltersFail }
    foreach ($f in @($script:WinFake.Filters)) { [ordered]@{ Name = $f.Name; Altitude = $f.Altitude; Instances = $f.Instances; Legacy = $f.Legacy } }
}

function Get-WorkerPerfTaskRaw([double]$DeadlineSec = 0) {
    # the walk of the Task Scheduler as one call: Delay['com:tasks'] makes it slow as a whole (a hanging COM call)
    Add-WinStandInCall 'com:tasks'
    $raw = $script:WinFake.Tasks
    return @{ Count = $raw.Count; Tasks = [object[]]@(foreach ($t in @($raw.Tasks)) { $t.Clone() }) }
}

function Get-WorkerPerfPerformanceInfo { Add-WinStandInCall 'native:perfinfo'; return $script:WinFake.PerformanceInfo.Clone() }
function Get-WorkerPerfActivePowerScheme { Add-WinStandInCall 'native:power'; return [string]$script:WinFake.PowerScheme }

function Get-WorkerPerfLogOldestTime([string]$LogName) {
    Add-WinStandInCall 'winevent:oldest'
    if ($script:WinFake.Logs -notcontains $LogName) { throw (New-Object System.IO.FileNotFoundException "Protokoll $LogName nicht vorhanden") }
    if ($script:WinFake.LogOldest.ContainsKey($LogName)) { return $script:WinFake.LogOldest[$LogName] }
    return $null
}

# Test types: the log mode as Windows gives it (an enumeration), and an exception that reports a CIM error the way a
# CimException does (NativeErrorCode, by default AccessDenied); further below an exception that carries a native error
# code in ErrorData.
if (-not ('WinStandInLogMode' -as [type])) {
    Add-Type -TypeDefinition @'
public enum WinStandInLogMode { Circular = 0, AutoBackup = 1, Retain = 2 }
public class WinStandInCimException : System.Exception
{
    private readonly string code;
    public WinStandInCimException(string message) : this(message, "AccessDenied") { }
    public WinStandInCimException(string message, string nativeErrorCode) : base(message) { code = nativeErrorCode; }
    public string NativeErrorCode { get { return code; } }
}
'@
}
if (-not ('WinStandInCimErrorException' -as [type])) {
    Add-Type -TypeDefinition @'
public class WinStandInCimErrorException : System.Exception
{
    public WinStandInCimErrorException(string message) : base(message) { }
    public object ErrorData { get; set; }
}
'@
}
# A registered task of the Task Scheduler whose property named in the second argument cannot be read, as a COM task
# reports a corrupt image or a definition that does not load (a property getter that throws; PowerShell hands such a
# property to a script as $null). Without a broken property its Definition is $null. WinStandInBrokenList: a collection
# whose enumeration fails, as the trigger collection of a definition that does not load.
if (-not ('WinStandInTask' -as [type])) {
    Add-Type -TypeDefinition @'
public class WinStandInTask
{
    private readonly string path;
    private readonly string broken;
    public WinStandInTask(string path, string broken) { this.path = path; this.broken = broken; }
    private void Check(string name)
    {
        if (broken == name) { throw new System.Runtime.InteropServices.COMException("Das Abbild der Aufgabe ist beschaedigt.", unchecked((int)0x80041321)); }
    }
    public string Path { get { Check("Path"); return path; } }
    public bool Enabled { get { Check("Enabled"); return true; } }
    public int State { get { Check("State"); return 3; } }
    public System.DateTime NextRunTime { get { Check("NextRunTime"); return new System.DateTime(1899, 12, 30); } }
    public System.DateTime LastRunTime { get { Check("LastRunTime"); return new System.DateTime(1899, 12, 30); } }
    public object Definition { get { Check("Definition"); return null; } }
}
public class WinStandInBrokenList : System.Collections.IEnumerable
{
    public System.Collections.IEnumerator GetEnumerator()
    {
        throw new System.Runtime.InteropServices.COMException("Die Definition der Aufgabe laesst sich nicht laden.", unchecked((int)0x80041321));
    }
}
'@
}
