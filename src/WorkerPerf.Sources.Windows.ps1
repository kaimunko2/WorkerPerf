#Requires -Version 5.1
# WorkerPerf Windows data source (library, definitions only): the functions of the data source interface, read from
# the local system. Names and counter types follow the probe result of a real VDA (Windows Server 2022, de-DE): the
# performance counters are read through System.Diagnostics.PerformanceCounterCategory with their English names, which
# works in every display language. What can be checked without Windows (instance names, profile container mapping,
# conversion of counter values, Citrix rows, events) sits in pure functions; the Windows calls are thin wrappers that
# the tests replace (Open-/Read-WorkerPerfWinCategory, Get-WorkerPerfWinSampleValue, Get-CimInstance, Get-WinEvent,
# Get-WinSessionRaw).

# C# source of the WTS session wrapper (load with Add-Type -TypeDefinition $script:WorkerPerfWtsSource).
$script:WorkerPerfWtsSource = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace WorkerPerf
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

# C# source of small native helpers: the device name behind a volume GUID path and the free space of a UNC path.
$script:WorkerPerfNativeSource = @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace WorkerPerf
{
    public static class DosDevice
    {
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern uint QueryDosDeviceW(string lpDeviceName, StringBuilder lpTargetPath, int ucchMax);

        // First target of an MS-DOS device name such as "Volume{guid}" (e.g. "\Device\HarddiskVolume12"), or null.
        public static string Query(string deviceName)
        {
            StringBuilder buffer = new StringBuilder(1024);
            uint length = QueryDosDeviceW(deviceName, buffer, buffer.Capacity);
            if (length == 0) return null;
            return buffer.ToString();
        }
    }

    public static class DiskSpace
    {
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool GetDiskFreeSpaceExW(string directory, out ulong freeForCaller, out ulong total, out ulong totalFree);

        // Bytes available to the caller on the volume of a directory; works for UNC paths, unlike DriveInfo.
        public static double FreeBytes(string directory)
        {
            ulong freeForCaller, total, totalFree;
            if (!GetDiskFreeSpaceExW(directory, out freeForCaller, out total, out totalFree))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            return (double)freeForCaller;
        }
    }
}
'@

# C# source of the connect probes: all endpoints are probed at once and in the background, Start returns at once.
$script:WorkerPerfProbeSource = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;

namespace WorkerPerf
{
    public class ProbeResult
    {
        public string Name;
        public string Role;
        public string Host;
        public int Port;
        public double ConnectMs;    // duration of the connect, or until the failure; -1 = not measured
        public string Error;        // "" = connected; timeout, refused, dns or the name of the exception
    }

    public class Probe
    {
        private class Item
        {
            public ProbeResult Result;
            public bool Done;
            public bool Connecting;
            public double ConnectStartMs;
            public TcpClient Client;
        }

        private readonly object gate = new object();
        private readonly List<Item> items = new List<Item>();
        private readonly Stopwatch watch = Stopwatch.StartNew();
        private readonly int timeoutMs;

        public Probe(int timeoutMs) { this.timeoutMs = timeoutMs; }

        public void Add(string name, string role, string host, int port)
        {
            Item item = new Item();
            item.Result = new ProbeResult();
            item.Result.Name = name;
            item.Result.Role = role;
            item.Result.Host = host;
            item.Result.Port = port;
            item.Result.ConnectMs = -1;
            item.Result.Error = "";
            lock (gate) { items.Add(item); }
            try { Dns.BeginGetHostAddresses(host, new AsyncCallback(OnDns), item); }
            catch (Exception) { Finish(item, "dns"); }
        }

        private void OnDns(IAsyncResult ar)
        {
            Item item = (Item)ar.AsyncState;
            IPAddress address = null;
            try
            {
                IPAddress[] all = Dns.EndGetHostAddresses(ar);
                foreach (IPAddress a in all)
                {
                    if (a.AddressFamily == AddressFamily.InterNetwork) { address = a; break; }
                }
                if (address == null && all.Length > 0) address = all[0];
            }
            catch (Exception) { address = null; }
            if (address == null) { Finish(item, "dns"); return; }
            try
            {
                TcpClient client = new TcpClient(address.AddressFamily);
                lock (gate)
                {
                    if (item.Done) { client.Close(); return; }
                    item.Client = client;
                    item.Connecting = true;
                    item.ConnectStartMs = watch.Elapsed.TotalMilliseconds;
                }
                client.BeginConnect(address, item.Result.Port, new AsyncCallback(OnConnect), item);
            }
            catch (Exception e) { Finish(item, Classify(e)); }
        }

        private void OnConnect(IAsyncResult ar)
        {
            Item item = (Item)ar.AsyncState;
            string error = "";
            try { item.Client.EndConnect(ar); }
            catch (Exception e) { error = Classify(e); }
            Finish(item, error);
        }

        private void Finish(Item item, string error)
        {
            lock (gate)
            {
                if (item.Done) return;
                item.Done = true;
                double now = watch.Elapsed.TotalMilliseconds;
                item.Result.ConnectMs = item.Connecting ? now - item.ConnectStartMs : now;
                item.Result.Error = error;
                if (item.Client != null)
                {
                    try { item.Client.Close(); }
                    catch (Exception) { }
                }
            }
        }

        // True once every probe has finished; probes still open after the time limit end as "timeout".
        public bool IsDone
        {
            get
            {
                List<Item> late = new List<Item>();
                lock (gate)
                {
                    bool open = false;
                    foreach (Item i in items) { if (!i.Done) open = true; }
                    if (!open) return true;
                    if (watch.ElapsedMilliseconds < timeoutMs) return false;
                    foreach (Item i in items) { if (!i.Done) late.Add(i); }
                }
                foreach (Item i in late) Finish(i, "timeout");
                return true;
            }
        }

        public ProbeResult[] GetResults()
        {
            lock (gate)
            {
                ProbeResult[] r = new ProbeResult[items.Count];
                for (int k = 0; k < items.Count; k++) r[k] = items[k].Result;
                return r;
            }
        }

        public static string Classify(Exception e)
        {
            Exception x = e;
            while (x != null)
            {
                SocketException se = x as SocketException;
                if (se != null)
                {
                    if (se.SocketErrorCode == SocketError.ConnectionRefused) return "refused";
                    if (se.SocketErrorCode == SocketError.TimedOut) return "timeout";
                    if (se.SocketErrorCode == SocketError.HostNotFound || se.SocketErrorCode == SocketError.NoData || se.SocketErrorCode == SocketError.TryAgain) return "dns";
                    return se.GetType().Name;
                }
                x = x.InnerException;
            }
            return e.GetType().Name;
        }
    }
}
'@

#region ---------- constants: the verified counter table --------------------------------------------------------------

# Performance counters as the probe found them on a VDA (Windows Server 2022, de-DE): read through
# System.Diagnostics.PerformanceCounterCategory with the English names, which works in every display language. One
# group per category; the collector reads each group once per fast tick and calculates every value from two readings.
# Mode: 'Calculate' (CounterSample.Calculate); 'ZeroUnchanged' like Calculate, but an instance whose raw value did not
# change is 0 without calculating (true for AverageCount64; the per-process input delay has one instance per process);
# 'MsPercent' for 'CPU stolen time': its raw value is taken as milliseconds of stolen time, see ConvertTo-WorkerPerfStealPct.
$script:WorkerPerfWinCounters = [ordered]@{
    cpu          = @{ Category = 'Processor Information'; Counters = @('% Processor Time'); Mode = 'Calculate' }
    queue        = @{ Category = 'System'; Counters = @('Processor Queue Length'); Mode = 'Calculate' }
    steal        = @{ Category = 'VM Processor'; Counters = @('CPU stolen time'); Mode = 'MsPercent' }
    memory       = @{ Category = 'Memory'; Counters = @('Available Bytes', 'Committed Bytes', 'Commit Limit', 'Pages Input/sec'); Mode = 'Calculate' }
    disk         = @{ Category = 'PhysicalDisk'; Counters = @('Disk Read Bytes/sec', 'Disk Write Bytes/sec', 'Disk Reads/sec', 'Disk Writes/sec', 'Current Disk Queue Length'); Mode = 'Calculate' }
    network      = @{ Category = 'Network Interface'; Counters = @('Bytes Received/sec', 'Bytes Sent/sec'); Mode = 'Calculate' }
    volumes      = @{ Category = 'LogicalDisk'; Counters = @('Avg. Disk sec/Read', 'Avg. Disk sec/Write', 'Disk Reads/sec', 'Disk Writes/sec', 'Disk Read Bytes/sec', 'Disk Write Bytes/sec', 'Current Disk Queue Length'); Mode = 'Calculate' }
    shares       = @{ Category = 'SMB Client Shares'; Counters = @('Avg. sec/Read', 'Avg. sec/Write', 'Read Requests/sec', 'Write Requests/sec', 'Read Bytes/sec', 'Write Bytes/sec'); Mode = 'Calculate' }
    inputSession = @{ Category = 'User Input Delay per Session'; Counters = @('Max Input Delay'); Mode = 'Calculate' }
    inputProcess = @{ Category = 'User Input Delay per Process'; Counters = @('Max Input Delay'); Mode = 'ZeroUnchanged' }
}

# Signal id -> counter group. Order of the signal ids as in meta.json of the simulation.
$script:WorkerPerfWinSignalGroups = [ordered]@{
    'cpu.host' = 'cpu'; 'cpu.queue' = 'queue'; 'cpu.steal' = 'steal'; 'mem.used' = 'memory'; 'mem.commit' = 'memory'; 'mem.pagesin' = 'memory'
    'input.session' = 'inputSession'; 'disk.latency' = 'volumes'; 'smb.latency' = 'shares'
}

# Citrix: ICA session counters (one instance per ICA session, "<WinStation> (<user>)", plus a total whose name
# is localized, e.g. "_Server gesamt") and the EUEM round trip class.
$script:WorkerPerfWinIcaCategory = 'ICA Session'
$script:WorkerPerfWinIcaLatency = 'Latency - Last Recorded'
$script:WorkerPerfWinEuemNamespace = 'root\citrix\euem'
$script:WorkerPerfWinEuemClass = 'Citrix_Euem_RoundTrip'
# Citrix values of 0 are written only for these metrics; most bandwidth counters of a session are 0 and would multiply
# the size of citrix.csv.
$script:WorkerPerfCitrixKeepZero = 'Latency|Round|RTT'

$script:WorkerPerfWinEventLogs = @(
    @{ Source = 'Defender'; Log = 'Microsoft-Windows-Windows Defender/Operational'; Ids = @(1000, 1001, 1002, 2000) }
    @{ Source = 'AppLocker'; Log = 'Microsoft-Windows-AppLocker/EXE and DLL'; Ids = @(8004, 8007) }
    @{ Source = 'AppLocker'; Log = 'Microsoft-Windows-AppLocker/MSI and Script'; Ids = @(8004, 8007) }
)
$script:WorkerPerfWinMaxEvents = 200

$script:WorkerPerfWinProcessProperties = @('ProcessId', 'ParentProcessId', 'Name', 'SessionId', 'KernelModeTime', 'UserModeTime', 'WorkingSetSize',
    'PrivatePageCount', 'ReadTransferCount', 'WriteTransferCount', 'ReadOperationCount', 'WriteOperationCount', 'HandleCount', 'ThreadCount',
    'CreationDate', 'ExecutablePath')

$script:WorkerPerfWinCimTimeoutSec = 30
$script:WorkerPerfWinProbeTimeoutMs = 2000
# Timeout of the storage queries of the profile container map (they run in a snapshot, so a hanging storage provider
# delays one snapshot by at most twice this time).
$script:WorkerPerfWinStorageTimeoutSec = 10

# State of a capture (set by Initialize-WorkerPerfSource).
$script:WinState = $null
$script:WinEndpoints = @()
$script:WinProbe = $null
$script:WtsAvailable = $false
$script:WarnedOnce = @{}

#endregion

#region ---------- pure helpers (no Windows calls; tested on any platform) ---------------------------------------------

function Write-WarningOnce([string]$Key, [string]$Message) {
    if (-not $script:WarnedOnce.ContainsKey($Key)) {
        $script:WarnedOnce[$Key] = $true
        Write-Warning $Message
    }
}

function Test-WorkerPerfTotalInstance([string]$Name) {
    # Totals start with an underscore: "_Total", and localized ones such as Citrix' "_Server gesamt".
    return $Name.StartsWith('_')
}

function ConvertFrom-WorkerPerfSessionInstance([string]$Instance) {
    # 'User Input Delay per Session' names its instances by session id, besides "Average" and "Max".
    if ($Instance -match '^\d{1,9}$') { return [int]$Instance }
    return $null
}

function ConvertFrom-WorkerPerfInputInstance([string]$Instance) {
    # 'User Input Delay per Process' names its instances "<session>:<pid> <name>" (seen on Server 2022); the form
    # "<name> <session>:<pid>" is accepted as well. Anything else (Average, Max, totals) is no process.
    $m = [regex]::Match($Instance, '^(\d{1,9}):(\d{1,9}) <(.+)>$')
    if ($m.Success) { return @{ SessionId = [int]$m.Groups[1].Value; Pid = [int]$m.Groups[2].Value; Name = $m.Groups[3].Value } }
    $m = [regex]::Match($Instance, '^(.+?) <(\d{1,9}):(\d{1,9})>$')
    if ($m.Success) { return @{ SessionId = [int]$m.Groups[2].Value; Pid = [int]$m.Groups[3].Value; Name = $m.Groups[1].Value } }
    return $null
}

function ConvertTo-WorkerPerfShareName([string]$Instance) {
    # 'SMB Client Shares' names a share "\server\share" (one backslash); the capture format writes "\\server\share".
    return '\\' + $Instance.TrimStart('\')
}

function Get-WorkerPerfShareRoot([string]$Path) {
    # "\\server\share" of a UNC path, or '' for a local path.
    $m = [regex]::Match($Path, '^\\\\([^\\]+)\\([^\\]+)')
    if ($m.Success) { return '\\' + $m.Groups[1].Value + '\' + $m.Groups[2].Value }
    return ''
}

function New-WorkerPerfUserIndex([object[]]$Sessions) {
    # user name (case-insensitive) -> session ids; built once per map or snapshot instead of once per path
    $index = @{}
    foreach ($s in @($Sessions)) {
        if ($null -eq $s) { continue }
        $user = [string](Get-WorkerPerfField $s 'User')
        if ([string]::IsNullOrEmpty($user)) { continue }
        if (-not $index.ContainsKey($user)) { $index[$user] = New-Object System.Collections.Generic.List[int] }
        $id = [int](Get-WorkerPerfField $s 'SessionId')
        if (-not $index[$user].Contains($id)) { $index[$user].Add($id) }
    }
    return $index
}

function Get-WorkerPerfUserCandidates([string]$Segment) {
    # The user names a folder can stand for: the folder itself, every part before a "." or "_" (Citrix UPM:
    # "<user>.<domain>", "<user>_UPM_local") and every part after a "_" (FSLogix "<sid>_<user>").
    $Segment
    for ($i = 1; $i -lt $Segment.Length; $i++) {
        $c = $Segment[$i]
        if ($c -eq '.' -or $c -eq '_') { $Segment.Substring(0, $i) }
        if ($c -eq '_' -and $i -lt $Segment.Length - 1) { $Segment.Substring($i + 1) }
    }
}

function Resolve-WorkerPerfProfileOwner {
    # Session of the user a profile container belongs to, from its location and access paths. The longest matching user
    # name wins ("anna.meier" before "anna"); when that user has more than one session, or two names of the same
    # length match, the owner stays unknown. Index: from New-WorkerPerfUserIndex (built here when missing).
    param([string[]]$Paths, [object[]]$Sessions, $Index = $null)
    if ($null -eq $Index) { $Index = New-WorkerPerfUserIndex $Sessions }
    if ($Index.Count -eq 0) { return $null }
    $bestLength = 0
    $ids = New-Object System.Collections.Generic.List[int]
    foreach ($path in @($Paths)) {
        if ([string]::IsNullOrEmpty($path)) { continue }
        foreach ($seg in $path.Split([char[]]@('\', '/'))) {
            if ($seg.Length -eq 0) { continue }
            foreach ($cand in @(Get-WorkerPerfUserCandidates $seg)) {
                if ($cand.Length -lt $bestLength -or -not $Index.ContainsKey($cand)) { continue }
                if ($cand.Length -gt $bestLength) { $bestLength = $cand.Length; $ids.Clear() }
                foreach ($id in $Index[$cand]) { if (-not $ids.Contains($id)) { $ids.Add($id) } }
            }
        }
    }
    if ($ids.Count -eq 1) { return $ids[0] }
    return $null
}

function New-WorkerPerfProfileMap {
    # LogicalDisk instance -> @{ Kind; SessionId; Backing } for every volume of a profile container, plus the set of
    # instances known at the time of the build. Disks: @{ Location; Partitions = @(@{ DriveLetter ('X:' or ''),
    # AccessPaths, DeviceName ('\Device\HarddiskVolumeN' or '') }) }. The LogicalDisk instance of a volume is its
    # access path without the trailing backslash, its drive letter, or the last part of its device name.
    param([object[]]$Disks, [object[]]$Sessions, [string[]]$Known = @())
    $entries = @{}
    $knownSet = @{}
    $userIndex = New-WorkerPerfUserIndex $Sessions
    foreach ($k in @($Known)) { if (-not [string]::IsNullOrEmpty($k)) { $knownSet[$k] = $true } }
    foreach ($d in @($Disks)) {
        if ($null -eq $d) { continue }
        $location = [string](Get-WorkerPerfField $d 'Location')
        $names = New-Object System.Collections.Generic.List[string]
        $paths = New-Object System.Collections.Generic.List[string]
        $paths.Add($location)
        foreach ($p in @(Get-WorkerPerfField $d 'Partitions')) {
            if ($null -eq $p) { continue }
            $letter = [string](Get-WorkerPerfField $p 'DriveLetter')
            if ($letter) { $names.Add($letter) }
            foreach ($ap in @(Get-WorkerPerfField $p 'AccessPaths')) {
                $a = [string]$ap
                if ([string]::IsNullOrEmpty($a) -or $a.StartsWith('\\?\')) { continue }       # volume GUID path
                $paths.Add($a)
                $names.Add($a.TrimEnd('\'))
            }
            $device = [string](Get-WorkerPerfField $p 'DeviceName')
            if ($device) { $names.Add($device.Substring($device.LastIndexOf('\') + 1)) }
        }
        $entry = @{ Kind = 'profile'; SessionId = (Resolve-WorkerPerfProfileOwner -Paths $paths.ToArray() -Sessions $Sessions -Index $userIndex); Backing = (Get-WorkerPerfShareRoot $location) }
        foreach ($n in $names) {
            if ([string]::IsNullOrEmpty($n)) { continue }
            $entries[$n] = $entry
            $knownSet[$n] = $true
        }
    }
    return @{ Entries = $entries; Known = $knownSet }
}

function Get-WorkerPerfUnknownVolumes {
    # LogicalDisk instances (without totals) that the profile map did not know when it was built.
    param([string[]]$Instances, $Map)
    foreach ($name in @($Instances)) {
        if ([string]::IsNullOrEmpty($name) -or (Test-WorkerPerfTotalInstance $name)) { continue }
        if ($null -ne $Map -and $Map.Known.ContainsKey($name)) { continue }
        $name
    }
}

function Get-WorkerPerfWinGroup($Values, [string]$Group, [string]$Counter) {
    # instance -> value of one counter, or $null when its category was not read
    if ($null -eq $Values -or -not $Values.ContainsKey($Group)) { return $null }
    $g = $Values[$Group]
    if ($null -eq $g -or -not $g.ContainsKey($Counter)) { return $null }
    return $g[$Counter]
}

function Get-WorkerPerfWinHostValue($Values, [string]$Group, [string]$Counter, [string]$Mode) {
    # One host value of a counter: 'total' (the _Total instance), 'first' (single-instance category), 'sum' over all
    # instances. $null when the category was not read or the instance is missing.
    $inst = Get-WorkerPerfWinGroup $Values $Group $Counter
    if ($null -eq $inst) { return $null }
    if ($Mode -eq 'total') {
        if ($inst.ContainsKey('_Total')) { return [double]$inst['_Total'] }
        return $null
    }
    if ($Mode -eq 'first') {
        foreach ($k in $inst.Keys) { return [double]$inst[$k] }
        return $null
    }
    $sum = 0.0; $n = 0
    foreach ($k in $inst.Keys) {
        if (Test-WorkerPerfTotalInstance $k) { continue }
        $sum += [double]$inst[$k]; $n++
    }
    if ($n -eq 0) { return $null }
    return [Math]::Round($sum, 3)
}

function ConvertTo-WorkerPerfStealPct([long]$Raw1, [long]$Raw2, [long]$Time1, [long]$Time2) {
    # 'CPU stolen time' (VMware Tools) declares the type Timer100Ns, but its raw value grows like the milliseconds of
    # the Guest SDK value behind it (VMGuestLib_GetCpuStolenMs): the probe saw 15 per second, which as 100 ns would be
    # 1.5 microseconds of steal per second. So: stolen ms over elapsed wall time in ms (from the sample time stamps,
    # 100 ns units), in percent. $null without elapsed time or when the counter went back.
    $ms = ($Time2 - $Time1) / 10000.0
    if ($ms -le 0 -or $Raw2 -lt $Raw1) { return $null }
    return ($Raw2 - $Raw1) / $ms * 100.0
}

function Get-WorkerPerfWinInstanceValue($Instances, [string]$Name, [double]$Factor, [int]$Decimals) {
    if ($null -eq $Instances -or -not $Instances.ContainsKey($Name)) { return $null }
    return [Math]::Round([double]$Instances[$Name] * $Factor, $Decimals)
}

function ConvertTo-WorkerPerfWinFastSample {
    # The fast sample (capture format, Task 6) from calculated counter values. Values: group -> counter -> instance ->
    # value as CounterSample.Calculate returns it ($null for a group that was not read). Response times come in
    # seconds and go out in ms; operations come as rates and go out as counts over ElapsedSec. StealPct is the
    # stolen CPU time in percent per vCPU: the average of per-vCPU instances when there are any, else the _Total
    # instance (the whole VM, as the probe found it) divided by the number of logical processors.
    # A LogicalDisk instance unknown to the profile map (mounted since its last build) counts as a profile container
    # without session until the next rebuild.
    param($Values, [double]$ElapsedSec, [datetime]$Time, $ProfileMap, [int]$LogicalProcessors = 1)

    $mb = 1048576.0
    $avail = Get-WorkerPerfWinHostValue $Values 'memory' 'Available Bytes' 'first'
    $committed = Get-WorkerPerfWinHostValue $Values 'memory' 'Committed Bytes' 'first'
    $limit = Get-WorkerPerfWinHostValue $Values 'memory' 'Commit Limit' 'first'

    $volumes = New-Object System.Collections.Generic.List[object]
    $rOps = Get-WorkerPerfWinGroup $Values 'volumes' 'Disk Reads/sec'
    if ($null -ne $rOps) {
        $rLat = Get-WorkerPerfWinGroup $Values 'volumes' 'Avg. Disk sec/Read'
        $wLat = Get-WorkerPerfWinGroup $Values 'volumes' 'Avg. Disk sec/Write'
        $wOps = Get-WorkerPerfWinGroup $Values 'volumes' 'Disk Writes/sec'
        $rBps = Get-WorkerPerfWinGroup $Values 'volumes' 'Disk Read Bytes/sec'
        $wBps = Get-WorkerPerfWinGroup $Values 'volumes' 'Disk Write Bytes/sec'
        $queue = Get-WorkerPerfWinGroup $Values 'volumes' 'Current Disk Queue Length'
        foreach ($name in @($rOps.Keys | Sort-Object)) {
            if (Test-WorkerPerfTotalInstance $name) { continue }
            $kind = 'disk'; $sid = $null; $backing = ''
            if ($null -ne $ProfileMap) {
                if ($ProfileMap.Entries.ContainsKey($name)) {
                    $e = $ProfileMap.Entries[$name]
                    $kind = $e.Kind; $sid = $e.SessionId; $backing = $e.Backing
                }
                elseif (-not $ProfileMap.Known.ContainsKey($name)) { $kind = 'profile' }
            }
            $volumes.Add([pscustomobject]@{
                    Volume = $name; Kind = $kind; SessionId = $sid; Backing = $backing
                    ReadLatMs = (Get-WorkerPerfWinInstanceValue $rLat $name 1000 3); WriteLatMs = (Get-WorkerPerfWinInstanceValue $wLat $name 1000 3)
                    ReadOps = (Get-WorkerPerfWinInstanceValue $rOps $name $ElapsedSec 0); WriteOps = (Get-WorkerPerfWinInstanceValue $wOps $name $ElapsedSec 0)
                    ReadBps = (Get-WorkerPerfWinInstanceValue $rBps $name 1 0); WriteBps = (Get-WorkerPerfWinInstanceValue $wBps $name 1 0)
                    Queue = (Get-WorkerPerfWinInstanceValue $queue $name 1 0)
                })
        }
    }

    $shares = New-Object System.Collections.Generic.List[object]
    $sROps = Get-WorkerPerfWinGroup $Values 'shares' 'Read Requests/sec'
    if ($null -ne $sROps) {
        $sRLat = Get-WorkerPerfWinGroup $Values 'shares' 'Avg. sec/Read'
        $sWLat = Get-WorkerPerfWinGroup $Values 'shares' 'Avg. sec/Write'
        $sWOps = Get-WorkerPerfWinGroup $Values 'shares' 'Write Requests/sec'
        $sRBps = Get-WorkerPerfWinGroup $Values 'shares' 'Read Bytes/sec'
        $sWBps = Get-WorkerPerfWinGroup $Values 'shares' 'Write Bytes/sec'
        foreach ($name in @($sROps.Keys | Sort-Object)) {
            if (Test-WorkerPerfTotalInstance $name) { continue }
            $shares.Add([pscustomobject]@{
                    Share = (ConvertTo-WorkerPerfShareName $name)
                    ReadLatMs = (Get-WorkerPerfWinInstanceValue $sRLat $name 1000 3); WriteLatMs = (Get-WorkerPerfWinInstanceValue $sWLat $name 1000 3)
                    ReadOps = (Get-WorkerPerfWinInstanceValue $sROps $name $ElapsedSec 0); WriteOps = (Get-WorkerPerfWinInstanceValue $sWOps $name $ElapsedSec 0)
                    ReadBps = (Get-WorkerPerfWinInstanceValue $sRBps $name 1 0); WriteBps = (Get-WorkerPerfWinInstanceValue $sWBps $name 1 0)
                })
        }
    }

    $steal = $null
    $inst = Get-WorkerPerfWinGroup $Values 'steal' 'CPU stolen time'
    if ($null -ne $inst) {
        $sum = 0.0; $n = 0
        foreach ($k in $inst.Keys) { if (-not (Test-WorkerPerfTotalInstance $k)) { $sum += [double]$inst[$k]; $n++ } }
        if ($n -gt 0) { $steal = $sum / $n }
        elseif ($inst.ContainsKey('_Total')) { $steal = [double]$inst['_Total'] / [Math]::Max(1, $LogicalProcessors) }
    }

    $inSessions = New-Object System.Collections.Generic.List[object]
    $inst = Get-WorkerPerfWinGroup $Values 'inputSession' 'Max Input Delay'
    if ($null -ne $inst) {
        foreach ($name in $inst.Keys) {
            $sid = ConvertFrom-WorkerPerfSessionInstance $name
            if ($null -eq $sid) { continue }
            $inSessions.Add([pscustomobject]@{ SessionId = $sid; DelayMs = [double]$inst[$name] })
        }
    }
    $inProcs = New-Object System.Collections.Generic.List[object]
    $inst = Get-WorkerPerfWinGroup $Values 'inputProcess' 'Max Input Delay'
    if ($null -ne $inst) {
        foreach ($name in $inst.Keys) {
            $v = [double]$inst[$name]
            if ($v -le 0) { continue }
            $p = ConvertFrom-WorkerPerfInputInstance $name
            if ($null -eq $p) { continue }
            $inProcs.Add([pscustomobject]@{ SessionId = $p.SessionId; Pid = $p.Pid; Name = $p.Name; DelayMs = $v })
        }
    }

    return [pscustomobject]@{
        Time             = $Time
        CpuPct           = Get-WorkerPerfWinHostValue $Values 'cpu' '% Processor Time' 'total'
        ProcQueue        = Get-WorkerPerfWinHostValue $Values 'queue' 'Processor Queue Length' 'first'
        StealPct         = $steal
        MemAvailMB       = $(if ($null -ne $avail) { $avail / $mb } else { $null })
        MemCommittedMB   = $(if ($null -ne $committed) { $committed / $mb } else { $null })
        MemCommitLimitMB = $(if ($null -ne $limit) { $limit / $mb } else { $null })
        PagesInPerSec    = Get-WorkerPerfWinHostValue $Values 'memory' 'Pages Input/sec' 'first'
        DiskReadBps      = Get-WorkerPerfWinHostValue $Values 'disk' 'Disk Read Bytes/sec' 'total'
        DiskWriteBps     = Get-WorkerPerfWinHostValue $Values 'disk' 'Disk Write Bytes/sec' 'total'
        DiskReadIops     = Get-WorkerPerfWinHostValue $Values 'disk' 'Disk Reads/sec' 'total'
        DiskWriteIops    = Get-WorkerPerfWinHostValue $Values 'disk' 'Disk Writes/sec' 'total'
        DiskQueue        = Get-WorkerPerfWinHostValue $Values 'disk' 'Current Disk Queue Length' 'total'
        NetRecvBps       = Get-WorkerPerfWinHostValue $Values 'network' 'Bytes Received/sec' 'sum'
        NetSentBps       = Get-WorkerPerfWinHostValue $Values 'network' 'Bytes Sent/sec' 'sum'
        Volumes          = $volumes.ToArray()
        Shares           = $shares.ToArray()
        InputSessions    = $inSessions.ToArray()
        InputProcesses   = $inProcs.ToArray()
    }
}

function Get-WorkerPerfWinCounterValues {
    # Counter -> instance -> value from two readings of a category (ReadCategory: counter -> instance -> InstanceData
    # with InstanceName and Sample). Instances without a previous reading are left out. get_Item, as in the probe
    # script: the string indexers of the ReadCategory collections lower-case the name like their keys.
    param($Previous, $Current, [string[]]$Counters, [switch]$ZeroUnchanged, [switch]$MsPercent)
    $out = @{}
    foreach ($cn in $Counters) {
        $values = @{}
        $c2 = $Current.get_Item($cn)
        $c1 = $Previous.get_Item($cn)
        if ($null -ne $c2 -and $null -ne $c1) {
            foreach ($i2 in $c2.Values) {
                $name = [string]$i2.InstanceName
                $i1 = $c1.get_Item($name)
                if ($null -eq $i1) { continue }
                if ($ZeroUnchanged -and $i1.Sample.RawValue -eq $i2.Sample.RawValue) { $values[$name] = 0.0; continue }
                if ($MsPercent) {
                    $pct = ConvertTo-WorkerPerfStealPct $i1.Sample.RawValue $i2.Sample.RawValue $i1.Sample.TimeStamp100nSec $i2.Sample.TimeStamp100nSec
                    if ($null -ne $pct) { $values[$name] = [double]$pct }
                    continue
                }
                $values[$name] = [double](Get-WorkerPerfWinSampleValue $i1.Sample $i2.Sample)
            }
        }
        $out[$cn] = $values
    }
    return $out
}

function Get-WorkerPerfWinInstantValues {
    # Counter -> instance -> value from one reading (instantaneous counter types such as NumberOfItems32).
    param($Current, [string[]]$Counters)
    $out = @{}
    foreach ($cn in $Counters) {
        $values = @{}
        $c = $Current.get_Item($cn)
        if ($null -ne $c) {
            foreach ($i in $c.Values) { $values[[string]$i.InstanceName] = [double](Get-WorkerPerfWinInstantValue $i.Sample) }
        }
        $out[$cn] = $values
    }
    return $out
}

function Get-WorkerPerfWinInstanceNames($Reading, [string]$Counter) {
    $c = $Reading.get_Item($Counter)
    if ($null -eq $c) { return }
    foreach ($i in $c.Values) { [string]$i.InstanceName }
}

function New-WorkerPerfSessionIndex([object[]]$Sessions) {
    # WinStation name ("#" read as a blank, case-insensitive) and user name -> session ids, once per snapshot
    $station = @{}
    $user = @{}
    foreach ($s in @($Sessions)) {
        if ($null -eq $s) { continue }
        $id = [int](Get-WorkerPerfField $s 'SessionId')
        $ws = ([string](Get-WorkerPerfField $s 'WinStation')).Replace('#', ' ')
        if ($ws) {
            if (-not $station.ContainsKey($ws)) { $station[$ws] = New-Object System.Collections.Generic.List[int] }
            if (-not $station[$ws].Contains($id)) { $station[$ws].Add($id) }
        }
        $u = [string](Get-WorkerPerfField $s 'User')
        if ($u) {
            if (-not $user.ContainsKey($u)) { $user[$u] = New-Object System.Collections.Generic.List[int] }
            if (-not $user[$u].Contains($id)) { $user[$u].Add($id) }
        }
    }
    return @{ Station = $station; User = $user }
}

function Resolve-WorkerPerfIcaSession([string]$Instance, [object[]]$Sessions, $Index = $null) {
    # Session id of an 'ICA Session' instance "<WinStation> (<user>)", also with "<domain>\" before the user: by the
    # WinStation name ("ICA-CGP 2" against "ICA-CGP#2"), else by the user name when that user has exactly one
    # session. $null for totals. Index: from New-WorkerPerfSessionIndex (built here when missing).
    $m = [regex]::Match($Instance, '^(.+?)\s*\(([^()]*)\)\s*$')
    if (-not $m.Success) { return $null }
    if ($null -eq $Index) { $Index = New-WorkerPerfSessionIndex $Sessions }
    $station = $m.Groups[1].Value.Trim()
    $user = $m.Groups[2].Value
    if ($user.Contains('\')) { $user = $user.Substring($user.LastIndexOf('\') + 1) }
    if ($Index.Station.ContainsKey($station) -and $Index.Station[$station].Count -eq 1) { return $Index.Station[$station][0] }
    if ($user -and $Index.User.ContainsKey($user) -and $Index.User[$user].Count -eq 1) { return $Index.User[$user][0] }
    return $null
}

function ConvertTo-WorkerPerfIcaRows {
    # Rows for citrix.csv from the 'ICA Session' counters (counter -> instance -> value): one row per session and
    # counter, without the total; a value of 0 only for latency metrics.
    param($Values, [object[]]$Sessions, [string]$MetricFilter = '')
    $index = New-WorkerPerfSessionIndex $Sessions
    $resolved = @{}        # instance -> session id, resolved once per call
    foreach ($counter in @($Values.Keys | Sort-Object)) {
        if ($MetricFilter -and $counter -notmatch $MetricFilter) { continue }
        $inst = $Values[$counter]
        if ($null -eq $inst) { continue }
        $keepZero = ($counter -match $script:WorkerPerfCitrixKeepZero)
        foreach ($name in @($inst.Keys | Sort-Object)) {
            if (Test-WorkerPerfTotalInstance $name) { continue }
            $v = $inst[$name]
            if ($null -eq $v) { continue }
            if ([double]$v -eq 0 -and -not $keepZero) { continue }
            if (-not $resolved.ContainsKey($name)) { $resolved[$name] = Resolve-WorkerPerfIcaSession $name $Sessions $index }
            [pscustomobject]@{ Source = $script:WorkerPerfWinIcaCategory; SessionId = $resolved[$name]; Instance = $name
                Metric = $counter; Value = [double]$v }
        }
    }
}

function ConvertTo-WorkerPerfCimCitrixRows {
    # Rows for citrix.csv from the instances of a Citrix WMI class: every numeric property matching the filter.
    param([object[]]$Instances, [string]$Source, [string]$MetricFilter = '')
    foreach ($inst in @($Instances)) {
        if ($null -eq $inst) { continue }
        $sid = Get-WorkerPerfField $inst 'SessionId'
        if ($null -ne $sid) { $sid = [int]$sid }
        $props = Get-WorkerPerfField $inst 'CimInstanceProperties'
        if ($null -eq $props) { $props = $inst.PSObject.Properties }
        foreach ($p in $props) {
            $name = [string]$p.Name
            if ($name -eq 'SessionId' -or $name -eq 'ProcessId') { continue }
            if ($MetricFilter -and $name -notmatch $MetricFilter) { continue }
            $v = $p.Value
            if ($null -eq $v -or $v -isnot [ValueType] -or $v -is [bool] -or $v -is [datetime] -or $v -is [char]) { continue }
            $d = [double]$v
            if ($d -eq 0 -and $name -notmatch $script:WorkerPerfCitrixKeepZero) { continue }
            [pscustomobject]@{ Source = $Source; SessionId = $sid; Instance = ''; Metric = $name; Value = $d }
        }
    }
}

function ConvertTo-WorkerPerfServiceMap([object[]]$Services) {
    # PID -> 'Service1;Service2' (sorted) for services with a process.
    $lists = @{}
    foreach ($s in @($Services)) {
        if ($null -eq $s) { continue }
        $id = [int]$s.ProcessId
        if ($id -le 0) { continue }
        if (-not $lists.ContainsKey($id)) { $lists[$id] = New-Object System.Collections.Generic.List[string] }
        $lists[$id].Add([string]$s.Name)
    }
    $map = @{}
    foreach ($id in $lists.Keys) {
        $names = $lists[$id].ToArray()
        [Array]::Sort($names, [StringComparer]::OrdinalIgnoreCase)
        $map[$id] = [string]::Join(';', $names)
    }
    return $map
}

function ConvertTo-WorkerPerfEventKind([string]$Source, [int]$EventId) {
    if ($Source -eq 'Defender') {
        if ($EventId -eq 1000) { return 'scan-start' }
        if ($EventId -eq 1001 -or $EventId -eq 1002) { return 'scan-end' }
        if ($EventId -eq 2000) { return 'signature-update' }
    }
    elseif ($Source -eq 'AppLocker') {
        if ($EventId -eq 8004 -or $EventId -eq 8007) { return 'applocker-block' }
    }
    return $null
}

function Get-WorkerPerfEventText([string]$Text) {
    # First line of an event message, at most 200 characters.
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $t = $Text.Trim()
    $cut = $t.IndexOfAny([char[]]@("`r", "`n"))
    if ($cut -ge 0) { $t = $t.Substring(0, $cut).Trim() }
    if ($t.Length -gt 200) { $t = $t.Substring(0, 200) }
    return $t
}

#endregion

#region ---------- Windows calls (thin; replaced by stand-ins in the tests) --------------------------------------------

function Test-WorkerPerfElevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function Test-WorkerPerfWinCounter([string]$Category, [string]$Counter) {
    # '' when the category (and the counter) exist, else the reason.
    if (-not [System.Diagnostics.PerformanceCounterCategory]::Exists($Category)) { return 'Kategorie nicht vorhanden' }
    if ($Counter -and -not [System.Diagnostics.PerformanceCounterCategory]::CounterExists($Counter, $Category)) { return "Zaehler '$Counter' fehlt" }
    return ''
}

function Open-WorkerPerfWinCategory([string]$Name) {
    if (-not [System.Diagnostics.PerformanceCounterCategory]::Exists($Name)) { return $null }
    return (New-Object System.Diagnostics.PerformanceCounterCategory -ArgumentList $Name)
}

function Read-WorkerPerfWinCategory($Category) {
    return $Category.ReadCategory()
}

function Get-WorkerPerfWinSampleValue($Previous, $Current) {
    return [System.Diagnostics.CounterSample]::Calculate($Previous, $Current)
}

function Get-WorkerPerfWinInstantValue($Sample) {
    return [System.Diagnostics.CounterSample]::Calculate($Sample)
}

function Get-WorkerPerfWinCounterNames($Category) {
    # Counter names in their original spelling (the keys of ReadCategory are lower case). A multi-instance category
    # lists its counters only through an instance; without instances the result is empty.
    $pcs = $null
    try { $pcs = $Category.GetCounters() }
    catch {
        $inst = $Category.GetInstanceNames()
        if ($inst.Length -eq 0) { return }
        $pcs = $Category.GetCounters($inst[0])
    }
    foreach ($pc in $pcs) {
        [string]$pc.CounterName
        $pc.Dispose()
    }
}

function Get-WorkerPerfDosDevice([string]$Name) {
    if (-not ('WorkerPerf.DosDevice' -as [type])) { return $null }
    return [WorkerPerf.DosDevice]::Query($Name)
}

function Register-WorkerPerfNativeTypes {
    # Compiles the WTS wrapper and the native helpers once; returns '' or the error of the WTS wrapper.
    $wtsError = ''
    try { if (-not ('WorkerPerf.Wts' -as [type])) { Add-Type -TypeDefinition $script:WorkerPerfWtsSource -Language CSharp } }
    catch { $wtsError = $_.Exception.Message }
    try { if (-not ('WorkerPerf.DiskSpace' -as [type])) { Add-Type -TypeDefinition $script:WorkerPerfNativeSource -Language CSharp } }
    catch { Write-WarningOnce 'native' "Hilfsfunktionen fuer Laufwerke nicht verfuegbar: $($_.Exception.Message)" }
    $script:WtsAvailable = [string]::IsNullOrEmpty($wtsError)
    return $wtsError
}

function Register-WorkerPerfProbeType {
    if (-not ('WorkerPerf.Probe' -as [type])) { Add-Type -TypeDefinition $script:WorkerPerfProbeSource -Language CSharp }
}

function Get-WinProcessRaw {
    # PID 0 (Idle) is excluded: its "CPU time" is the idle time of the machine.
    $props = @($script:WorkerPerfWinProcessProperties)
    if ($script:WinState.IncludeCommandLine) { $props += 'CommandLine' }
    return @(Get-CimInstance -ClassName Win32_Process -Property $props -Filter 'ProcessId <> 0' -OperationTimeoutSec $script:WorkerPerfWinCimTimeoutSec -ErrorAction Stop)
}

function Get-WinSessionRaw {
    if (-not $script:WtsAvailable) { return @() }
    try { return @([WorkerPerf.Wts]::GetSessions()) }
    catch {
        Write-WarningOnce 'wts' "Sitzungsabfrage fehlgeschlagen: $($_.Exception.Message)"
        return @()
    }
}

function Get-WinCitrixRaw([object[]]$Sessions) {
    # EUEM round trip (CIM) and ICA session counters. Each part catches its own failure, so that a broken Citrix
    # provider never costs the snapshot its processes and sessions.
    $st = $script:WinState
    $rows = New-Object System.Collections.Generic.List[object]
    if ($st.Euem) {
        try {
            $inst = @(Get-CimInstance -Namespace $script:WorkerPerfWinEuemNamespace -ClassName $script:WorkerPerfWinEuemClass `
                    -OperationTimeoutSec $script:WorkerPerfWinCimTimeoutSec -ErrorAction Stop)
            foreach ($r in @(ConvertTo-WorkerPerfCimCitrixRows -Instances $inst -Source $script:WorkerPerfWinEuemClass -MetricFilter $st.CitrixFilter)) { $rows.Add($r) }
        }
        catch { Write-WarningOnce 'citrix.euem' "Citrix-EUEM-Werte nicht lesbar, die Aufzeichnung laeuft ohne sie weiter: $($_.Exception.Message)" }
    }
    if ($null -ne $st.Ica) {
        try {
            $current = Read-WorkerPerfWinCategory $st.Ica
            if ($null -eq $st.IcaCounters) {
                # the counter names are known only while an ICA session exists
                $names = @(@(Get-WorkerPerfWinCounterNames $st.Ica) | Where-Object { -not $st.CitrixFilter -or $_ -match $st.CitrixFilter })
                if ($names.Count -gt 0) { $st.IcaCounters = [string[]]$names }
            }
            if ($null -ne $st.IcaCounters) {
                $values = Get-WorkerPerfWinInstantValues -Current $current -Counters $st.IcaCounters
                foreach ($r in @(ConvertTo-WorkerPerfIcaRows -Values $values -Sessions $Sessions -MetricFilter $st.CitrixFilter)) { $rows.Add($r) }
            }
        }
        catch { Write-WarningOnce 'citrix.ica' "ICA-Sitzungswerte nicht lesbar, die Aufzeichnung laeuft ohne sie weiter: $($_.Exception.Message)" }
    }
    return $rows.ToArray()
}

function Get-WorkerPerfProfileDisks {
    # Profile containers: disks with BusType 15 (file-backed virtual disk) and their partitions, as plain records for
    # New-WorkerPerfProfileMap.
    $ns = 'root\Microsoft\Windows\Storage'
    $disks = @(Get-CimInstance -Namespace $ns -ClassName MSFT_Disk -Filter 'BusType = 15' -OperationTimeoutSec $script:WorkerPerfWinStorageTimeoutSec -ErrorAction Stop)
    if ($disks.Count -eq 0) { return }
    $byDisk = @{}
    foreach ($p in @(Get-CimInstance -Namespace $ns -ClassName MSFT_Partition -OperationTimeoutSec $script:WorkerPerfWinStorageTimeoutSec -ErrorAction Stop)) {
        if ($null -eq $p) { continue }
        $n = [int](Get-WorkerPerfField $p 'DiskNumber')
        if (-not $byDisk.ContainsKey($n)) { $byDisk[$n] = New-Object System.Collections.Generic.List[object] }
        $byDisk[$n].Add($p)
    }
    foreach ($d in $disks) {
        $parts = New-Object System.Collections.Generic.List[object]
        $n = [int](Get-WorkerPerfField $d 'Number')
        if ($byDisk.ContainsKey($n)) {
            foreach ($p in $byDisk[$n]) {
                $letter = ''
                $dl = Get-WorkerPerfField $p 'DriveLetter'
                if ($null -ne $dl -and [int][char]$dl -ne 0) { $letter = ([string][char]$dl) + ':' }
                $paths = @(@(Get-WorkerPerfField $p 'AccessPaths') | Where-Object { -not [string]::IsNullOrEmpty([string]$_) } | ForEach-Object { [string]$_ })
                $device = ''
                foreach ($ap in $paths) {
                    $m = [regex]::Match($ap, '^\\\\\?\\(Volume\{[^}]+\})\\?$')
                    if ($m.Success) {
                        $target = Get-WorkerPerfDosDevice $m.Groups[1].Value
                        if ($target) { $device = [string]$target }
                    }
                }
                $parts.Add(@{ DriveLetter = $letter; AccessPaths = [string[]]$paths; DeviceName = $device })
            }
        }
        @{ Location = [string](Get-WorkerPerfField $d 'Location'); Partitions = $parts.ToArray() }
    }
}

function Update-WorkerPerfProfileMap($State, [object[]]$Sessions) {
    # Rebuilds the profile container map; called from the snapshot (at every keyframe, and at a regular snapshot after
    # the fast cadence saw an unknown LogicalDisk instance), never from the fast cadence. A failure keeps the old map.
    $State.MapPending = $false
    $known = $State.VolumeNames
    if ($null -eq $known) {
        # no fast reading yet: the instances of now are the known ones
        $known = @()
        $cat = $State.Categories['volumes']
        if ($null -ne $cat) {
            try { $known = [string[]]@(Get-WorkerPerfWinInstanceNames (Read-WorkerPerfWinCategory $cat) 'Disk Reads/sec') } catch { $known = @() }
        }
    }
    if ($State.ProfileMapOk) {
        try {
            $disks = @(Get-WorkerPerfProfileDisks)
            $State.Map = New-WorkerPerfProfileMap -Disks $disks -Sessions $Sessions -Known $known
            return
        }
        catch { Write-WarningOnce 'profile.map' "Zuordnung der Profilcontainer fehlgeschlagen, neue Laufwerke erscheinen als Profilcontainer ohne Sitzung: $($_.Exception.Message)" }
    }
    # without the storage classes every volume is a plain disk
    if ($null -eq $State.Map -or -not $State.ProfileMapOk) { $State.Map = New-WorkerPerfProfileMap -Disks @() -Sessions @() -Known $known }
}

#endregion

#region ---------- data source interface ------------------------------------------------------------------------------

function Initialize-WorkerPerfSource {
    param([datetime]$StartTime, [object[]]$Endpoints = @(), [string]$CitrixMetricFilter = '', [switch]$IncludeCommandLine, [switch]$NoCitrix)
    # StartTime exists for the common interface: the clock of this source is the system clock.

    $script:WarnedOnce = @{}
    if (-not (Test-WorkerPerfElevated)) {
        Write-Warning 'WorkerPerf laeuft ohne erhoehte Rechte: Prozesse anderer Benutzer, Profilcontainer und Ereignisprotokolle koennen fehlen.'
    }
    $wtsError = Register-WorkerPerfNativeTypes
    Register-WorkerPerfProbeType

    $cs = @(Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec $script:WorkerPerfWinCimTimeoutSec -ErrorAction Stop)[0]
    $os = @(Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec $script:WorkerPerfWinCimTimeoutSec -ErrorAction Stop)[0]

    $state = @{
        Categories = @{}; Prev = @{}; Clock = $null; Map = $null; MapPending = $false; VolumeNames = $null; ProfileMapOk = $false
        LogicalProcessors = 1
        IncludeCommandLine = [bool]$IncludeCommandLine; CitrixFilter = $CitrixMetricFilter; NoCitrix = [bool]$NoCitrix
        Ica = $null; IcaCounters = $null; Euem = $false; Logs = (New-Object System.Collections.Generic.List[object])
    }

    # ---- performance counters: one status per counter group ----
    $groupStatus = @{}
    foreach ($key in $script:WorkerPerfWinCounters.Keys) {
        $def = $script:WorkerPerfWinCounters[$key]
        $reason = ''
        try {
            foreach ($c in $def.Counters) {
                $reason = [string](Test-WorkerPerfWinCounter $def.Category $c)
                if ($reason) { break }
            }
            if (-not $reason) {
                $cat = Open-WorkerPerfWinCategory $def.Category
                if ($null -eq $cat) { $reason = 'Kategorie nicht vorhanden' } else { $state.Categories[$key] = $cat }
            }
        }
        catch { $reason = 'Pruefung fehlgeschlagen: ' + $_.Exception.Message }
        if ($reason) { $groupStatus[$key] = @{ Available = $false; Detail = ('{0}: {1}' -f $def.Category, $reason) } }
        else { $groupStatus[$key] = @{ Available = $true; Detail = ('{0} / {1}' -f $def.Category, ($def.Counters -join ', ')) } }
    }
    if ($groupStatus['steal'].Available) {
        $groupStatus['steal'].Detail += ' (Rohwert als Millisekunden gelesen, Einheit auf dem VDA nicht bestaetigt; je vCPU: _Total geteilt durch die logischen Prozessoren)'
    }

    $sources = [ordered]@{}
    foreach ($id in $script:WorkerPerfWinSignalGroups.Keys) {
        $g = $groupStatus[$script:WorkerPerfWinSignalGroups[$id]]
        $sources[$id] = @{ Available = $g.Available; Detail = $g.Detail }
    }

    # ---- Citrix ----
    if ($NoCitrix) {
        foreach ($id in 'ica.rtt', 'ica.latency') { $sources[$id] = @{ Available = $false; Detail = 'abgeschaltet (-NoCitrix)' } }
    }
    else {
        try {
            [void](Get-CimClass -Namespace $script:WorkerPerfWinEuemNamespace -ClassName $script:WorkerPerfWinEuemClass -OperationTimeoutSec $script:WorkerPerfWinCimTimeoutSec -ErrorAction Stop)
            $state.Euem = $true
            $sources['ica.rtt'] = @{ Available = $true; Detail = ('{0}: {1}' -f $script:WorkerPerfWinEuemNamespace, $script:WorkerPerfWinEuemClass) }
        }
        catch { $sources['ica.rtt'] = @{ Available = $false; Detail = ('{0}: Klasse {1} nicht vorhanden' -f $script:WorkerPerfWinEuemNamespace, $script:WorkerPerfWinEuemClass) } }
        try {
            $reason = [string](Test-WorkerPerfWinCounter $script:WorkerPerfWinIcaCategory $script:WorkerPerfWinIcaLatency)
            if (-not $reason) { $state.Ica = Open-WorkerPerfWinCategory $script:WorkerPerfWinIcaCategory }
        }
        catch { $reason = 'Pruefung fehlgeschlagen: ' + $_.Exception.Message; $state.Ica = $null }
        if ($null -ne $state.Ica) {
            $sources['ica.latency'] = @{ Available = $true; Detail = ('{0} / {1}' -f $script:WorkerPerfWinIcaCategory, $script:WorkerPerfWinIcaLatency) }
        }
        else {
            if (-not $reason) { $reason = 'Kategorie nicht vorhanden' }
            $sources['ica.latency'] = @{ Available = $false; Detail = ('{0}: {1}' -f $script:WorkerPerfWinIcaCategory, $reason) }
        }
    }

    $script:WinEndpoints = @($Endpoints | Where-Object { $null -ne $_ })
    if ($script:WinEndpoints.Count -gt 0) { $sources['probe.connect'] = @{ Available = $true; Detail = ('{0} Gegenstellen' -f $script:WinEndpoints.Count) } }
    else { $sources['probe.connect'] = @{ Available = $false; Detail = 'keine Gegenstellen (endpoints.json fehlt oder ist leer)' } }

    $sources['process'] = @{ Available = $true; Detail = 'Win32_Process' }
    if ($script:WtsAvailable) { $sources['sessions'] = @{ Available = $true; Detail = 'WTS-Schnittstelle' } }
    else { $sources['sessions'] = @{ Available = $false; Detail = ('WTS-Schnittstelle nicht verfuegbar: {0}' -f $wtsError) } }
    $g = $groupStatus['inputProcess']
    $sources['input.process'] = @{ Available = $g.Available; Detail = $g.Detail }

    # ---- profile containers ----
    try {
        $disks = @(Get-WorkerPerfProfileDisks)
        $state.ProfileMapOk = $true
        $sources['profile.map'] = @{ Available = $true; Detail = ('MSFT_Disk BusType 15, beim Start {0} Container' -f $disks.Count) }
    }
    catch { $sources['profile.map'] = @{ Available = $false; Detail = ('MSFT_Disk nicht lesbar: {0}' -f $_.Exception.Message) } }

    # ---- event logs ----
    foreach ($src in 'Defender', 'AppLocker') {
        $readable = New-Object System.Collections.Generic.List[string]
        foreach ($l in @($script:WorkerPerfWinEventLogs | Where-Object { $_.Source -eq $src })) {
            try {
                $info = Get-WinEvent -ListLog $l.Log -ErrorAction Stop
                if ($null -ne $info -and [bool]$info.IsEnabled) { $state.Logs.Add($l); $readable.Add($l.Log) }
            }
            catch { Write-Verbose ('Protokoll {0} nicht vorhanden: {1}' -f $l.Log, $_.Exception.Message) }
        }
        $id = 'events.' + $src.ToLowerInvariant()
        if ($readable.Count -gt 0) { $sources[$id] = @{ Available = $true; Detail = ($readable.ToArray() -join ', ') } }
        else { $sources[$id] = @{ Available = $false; Detail = 'Protokoll nicht vorhanden oder abgeschaltet' } }
    }

    $state.LogicalProcessors = [Math]::Max(1, [int]$cs.NumberOfLogicalProcessors)
    $script:WinState = $state
    $script:WinProbe = $null

    return @{
        Computer = [string]$cs.Name; OS = ('{0} {1}' -f $os.Caption, $os.Version).Trim()
        LogicalProcessors = [int]$cs.NumberOfLogicalProcessors; PhysicalMemoryMB = [Math]::Round([double]$cs.TotalPhysicalMemory / 1048576.0)
        CollectorPid = $PID; Endpoints = [object[]]$script:WinEndpoints; Sources = $sources
    }
}

function Get-WorkerPerfNow {
    # Local time of the server (Kind Local): written to the files and compared with process start times.
    return [datetime]::Now
}

function Wait-WorkerPerfTick {
    param([datetime]$Until, [string]$StopFlagPath)
    # Waits on UTC in steps of at most 500 ms, so that a step of the local clock (end of daylight saving time) neither
    # lengthens nor shortens the wait; $true as soon as the stop file exists.
    $untilUtc = $Until
    if ($untilUtc.Kind -ne [DateTimeKind]::Utc) { $untilUtc = $untilUtc.ToUniversalTime() }
    while ($true) {
        if (-not [string]::IsNullOrEmpty($StopFlagPath) -and (Test-Path -LiteralPath $StopFlagPath)) { return $true }
        $left = ($untilUtc - [datetime]::UtcNow).TotalMilliseconds
        if ($left -le 0) { return $false }
        Start-Sleep -Milliseconds ([int][Math]::Ceiling([Math]::Min(500.0, $left)))
    }
}

function Get-WorkerPerfFastSample {
    # One reading of every counter group; the values are calculated against the previous reading, so the first call
    # after the start returns a sample without values. A category that cannot be read gives one warning and no values.
    $st = $script:WinState
    if ($null -eq $st) { throw 'Die Windows-Datenquelle ist nicht initialisiert.' }
    $time = [datetime]::Now
    $elapsed = 0.0
    if ($null -eq $st.Clock) { $st.Clock = [System.Diagnostics.Stopwatch]::StartNew() }
    else { $elapsed = $st.Clock.Elapsed.TotalSeconds; $st.Clock.Restart() }

    $values = @{}
    $volumeNames = $null
    foreach ($key in $script:WorkerPerfWinCounters.Keys) {
        $values[$key] = $null
        $cat = $st.Categories[$key]
        if ($null -eq $cat) { continue }
        $def = $script:WorkerPerfWinCounters[$key]
        try { $current = Read-WorkerPerfWinCategory $cat }
        catch {
            Write-WarningOnce ('perf.' + $key) ("Leistungsindikator '{0}' nicht lesbar; seine Werte fehlen, die Aufzeichnung laeuft weiter: {1}" -f $def.Category, $_.Exception.Message)
            $st.Prev.Remove($key)
            continue
        }
        $previous = $st.Prev[$key]
        if ($null -ne $previous) {
            $values[$key] = Get-WorkerPerfWinCounterValues -Previous $previous -Current $current -Counters $def.Counters `
                -ZeroUnchanged:($def.Mode -eq 'ZeroUnchanged') -MsPercent:($def.Mode -eq 'MsPercent')
        }
        $st.Prev[$key] = $current
        if ($key -eq 'volumes') { $volumeNames = [string[]]@(Get-WorkerPerfWinInstanceNames $current 'Disk Reads/sec') }
    }
    if ($null -ne $volumeNames) {
        # a new instance (for example a container mounted at a logon) is mapped by the next regular snapshot
        $st.VolumeNames = $volumeNames
        if ($null -ne $st.Map -and @(Get-WorkerPerfUnknownVolumes -Instances $volumeNames -Map $st.Map).Count -gt 0) { $st.MapPending = $true }
    }

    return ConvertTo-WorkerPerfWinFastSample -Values $values -ElapsedSec $elapsed -Time $time -ProfileMap $st.Map -LogicalProcessors $st.LogicalProcessors
}

function Get-WorkerPerfSnapshot {
    param([string]$Kind = 'R')
    # Kind: 'K' keyframe, 'R' regular, 'B' burst snapshot. The profile container map is rebuilt here: at every keyframe,
    # and at a regular snapshot when the fast cadence has seen a LogicalDisk instance unknown to the map.
    $st = $script:WinState
    if ($null -eq $st) { throw 'Die Windows-Datenquelle ist nicht initialisiert.' }
    $time = [datetime]::Now
    $processes = @(Get-WinProcessRaw)
    $sessions = @(Get-WinSessionRaw)
    if ($Kind -eq 'K' -or $null -eq $st.Map -or ($Kind -eq 'R' -and $st.MapPending)) { Update-WorkerPerfProfileMap $st $sessions }
    $citrix = @()
    if (-not $st.NoCitrix) { $citrix = @(Get-WinCitrixRaw -Sessions $sessions) }
    return @{ Time = $time; Processes = $processes; Sessions = $sessions; Citrix = $citrix }
}

function Get-WorkerPerfServices {
    # PID -> 'Service1;Service2'
    return ConvertTo-WorkerPerfServiceMap @(Get-CimInstance -ClassName Win32_Service -Property Name, ProcessId -Filter 'ProcessId > 0' `
            -OperationTimeoutSec $script:WorkerPerfWinCimTimeoutSec -ErrorAction Stop)
}

function Start-WorkerPerfProbes {
    param([object[]]$Endpoints)
    # Starts a TCP connect to every endpoint (without -Endpoints: those given to Initialize-WorkerPerfSource) and returns
    # at once; Receive-WorkerPerfProbes collects the results.
    Register-WorkerPerfProbeType
    if (-not $PSBoundParameters.ContainsKey('Endpoints')) { $Endpoints = $script:WinEndpoints }
    $list = @($Endpoints | Where-Object { $null -ne $_ })
    $script:WinProbe = $null
    if ($list.Count -eq 0) { return }
    $probe = New-Object WorkerPerf.Probe -ArgumentList $script:WorkerPerfWinProbeTimeoutMs
    foreach ($e in $list) {
        $probe.Add([string](Get-WorkerPerfField $e 'Name'), [string](Get-WorkerPerfField $e 'Role'), [string](Get-WorkerPerfField $e 'Host'),
            [int](Get-WorkerPerfField $e 'Port'))
    }
    $script:WinProbe = $probe
}

function Receive-WorkerPerfProbes {
    # Nothing while probes are open; once all have finished or timed out, one object per endpoint.
    $probe = $script:WinProbe
    if ($null -eq $probe -or -not $probe.IsDone) { return }
    $script:WinProbe = $null
    foreach ($r in $probe.GetResults()) {
        $ms = $null
        if ($r.ConnectMs -ge 0) { $ms = [Math]::Round($r.ConnectMs, 1) }
        [pscustomobject]@{ Name = $r.Name; Role = $r.Role; Host = $r.Host; Port = $r.Port; ConnectMs = $ms; Error = $r.Error }
    }
}

function Get-WorkerPerfEvents {
    param([datetime]$Since)
    # Events of the logs found at the start with Since < Time <= now, oldest first; at most the newest 200 per log and
    # call (one warning per log when more were there).
    $st = $script:WinState
    if ($null -eq $st) { throw 'Die Windows-Datenquelle ist nicht initialisiert.' }
    $now = [datetime]::Now
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($l in $st.Logs) {
        $events = @()
        try {
            # one more than kept, to notice that events were dropped
            $events = @(Get-WinEvent -FilterHashtable @{ LogName = $l.Log; Id = $l.Ids; StartTime = $Since } -MaxEvents ($script:WorkerPerfWinMaxEvents + 1) -ErrorAction Stop)
        }
        catch {
            # no matching events is not an error; the error id is language neutral
            if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') {
                Write-WarningOnce ('events:' + $l.Log) ("Ereignisprotokoll '{0}' nicht lesbar: {1}" -f $l.Log, $_.Exception.Message)
            }
            continue
        }
        if ($events.Count -gt $script:WorkerPerfWinMaxEvents) {
            # Get-WinEvent returns the newest first: the newest 200 are kept, the older ones of this window are lost
            Write-WarningOnce ('events.dropped:' + $l.Log) ("Ereignisprotokoll '{0}': mehr als {1} Ereignisse seit dem letzten Abruf, die aelteren fehlen in events.csv." -f $l.Log, $script:WorkerPerfWinMaxEvents)
            $events = @($events[0..($script:WorkerPerfWinMaxEvents - 1)])
        }
        foreach ($ev in $events) {
            if ($null -eq $ev -or $null -eq $ev.TimeCreated) { continue }
            $t = [datetime]$ev.TimeCreated
            if ($t -le $Since -or $t -gt $now) { continue }
            $kind = ConvertTo-WorkerPerfEventKind $l.Source ([int]$ev.Id)
            if ($null -eq $kind) { continue }
            $text = ''
            try { $text = Get-WorkerPerfEventText ([string]$ev.Message) } catch { $text = '' }
            $rows.Add([pscustomobject]@{ Time = $t; Source = $l.Source; EventId = [int]$ev.Id; Kind = $kind; Text = $text })
        }
    }
    $rows.ToArray() | Sort-Object -Property Time
}

function Get-WorkerPerfFreeSpaceMB {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.StartsWith('\\')) {
        # DriveInfo does not accept UNC paths
        [void](Register-WorkerPerfNativeTypes)
        if (-not $full.EndsWith('\')) { $full += '\' }
        return [WorkerPerf.DiskSpace]::FreeBytes($full) / 1048576.0
    }
    $drive = New-Object System.IO.DriveInfo -ArgumentList ([IO.Path]::GetPathRoot($full))
    return [double]$drive.AvailableFreeSpace / 1048576.0
}

#endregion
