#Requires -Version 5.1
# WorkerPerf Windows data source (library, definitions only): the functions of the data source interface, read from
# the local system. Names and counter types follow the probe result of a real VDA (Windows Server 2022, de-DE): the
# performance counters are read through System.Diagnostics.PerformanceCounterCategory with their English names, which
# works in every display language. What can be checked without Windows (instance names, profile container mapping,
# conversion of counter values, Citrix rows, events) sits in pure functions; the Windows calls are thin wrappers that
# the tests replace (Open-/Read-WorkerPerfWinCategory, Get-WorkerPerfWinSampleValue, Get-CimInstance, Get-WinEvent -ListLog,
# Open-WorkerPerfEventReader, Get-WinSessionRaw, Get-WorkerPerfSidAccount and the registry readers of printing). The events come from the logs,
# providers and ids of the event catalogue (events.json, WorkerPerf.EventConfig.ps1 must be dot-sourced before).
# The health picture (Get-WorkerPerfHealth) reads only, within a time budget, through further thin calls
# (Get-WorkerPerfRegistryValues, Get-WorkerPerfPerformanceInfo, Get-WorkerPerfActivePowerScheme, Get-WorkerPerfLogOldestTime).

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

# C# source of the native reads of the health picture: the commit charge (GetPerformanceInfo, psapi.dll; the
# PERFORMANCE_INFORMATION structure counts in pages of PageSize, its SIZE_T fields are UIntPtr) and the active power
# scheme (PowerGetActiveScheme, powrprof.dll; the GUID it allocates is freed with LocalFree). A failed call throws a
# Win32Exception with the error code.
$script:WorkerPerfHealthNativeSource = @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace WorkerPerf
{
    public static class HealthNative
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct PERFORMANCE_INFORMATION
        {
            public uint cb;
            public UIntPtr CommitTotal;
            public UIntPtr CommitLimit;
            public UIntPtr CommitPeak;
            public UIntPtr PhysicalTotal;
            public UIntPtr PhysicalAvailable;
            public UIntPtr SystemCache;
            public UIntPtr KernelTotal;
            public UIntPtr KernelPaged;
            public UIntPtr KernelNonpaged;
            public UIntPtr PageSize;
            public uint HandleCount;
            public uint ProcessCount;
            public uint ThreadCount;
        }

        [DllImport("psapi.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetPerformanceInfo(out PERFORMANCE_INFORMATION pPerformanceInformation, int cb);

        [DllImport("powrprof.dll")]
        private static extern uint PowerGetActiveScheme(IntPtr UserRootPowerKey, out IntPtr ActivePolicyGuid);

        [DllImport("kernel32.dll")]
        private static extern IntPtr LocalFree(IntPtr hMem);

        // Commit charge, commit limit and commit peak in bytes.
        public static long[] GetCommit()
        {
            PERFORMANCE_INFORMATION info;
            int size = Marshal.SizeOf(typeof(PERFORMANCE_INFORMATION));
            if (!GetPerformanceInfo(out info, size)) throw new Win32Exception(Marshal.GetLastWin32Error());
            ulong page = info.PageSize.ToUInt64();
            return new long[] {
                (long)(info.CommitTotal.ToUInt64() * page),
                (long)(info.CommitLimit.ToUInt64() * page),
                (long)(info.CommitPeak.ToUInt64() * page)
            };
        }

        // The GUID of the active power scheme.
        public static Guid GetActivePowerScheme()
        {
            IntPtr scheme = IntPtr.Zero;
            uint rc = PowerGetActiveScheme(IntPtr.Zero, out scheme);
            if (rc != 0) throw new Win32Exception((int)rc);
            if (scheme == IntPtr.Zero) throw new Win32Exception(87);
            try { return (Guid)Marshal.PtrToStructure(scheme, typeof(Guid)); }
            finally { LocalFree(scheme); }
        }
    }
}
'@

# C# source of the SID lookup: the account of an event's System part. Translating a domain SID can ask a domain
# controller, which may take long or hang; the lookup runs on a pool thread and is given up after the time limit.
$script:WorkerPerfSidSource = @'
using System;
using System.Security.Principal;
using System.Threading.Tasks;

namespace WorkerPerf
{
    public static class SidLookup
    {
        // "DOMAIN\name" of a SID, or null when Windows cannot translate it; timedOut when it took longer than timeoutMs
        // (the abandoned lookup finishes on its pool thread).
        public static string Translate(string sid, int timeoutMs, out bool timedOut)
        {
            timedOut = false;
            Task<string> task = Task.Factory.StartNew<string>(delegate
            {
                try { return new SecurityIdentifier(sid).Translate(typeof(NTAccount)).Value; }
                catch (Exception) { return null; }
            });
            if (!task.Wait(timeoutMs)) { timedOut = true; return null; }
            return task.Result;
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

# Counter groups that belong to a category of the capture (-Skip); the others are the base and always read.
$script:WorkerPerfWinCounterCategories = @{ volumes = 'Laufwerke'; shares = 'Laufwerke'; inputProcess = 'Prozesse' }

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

# Events: the catalogue next to this file when Initialize-WorkerPerfSource gets none. At most 200 events per log and read
# of the measurement, at most 2000 per log in the lookback; at most 12 ids per select of an event query (a select may
# hold at most 32 expressions). The lookback stops after a time budget, checked before each log and between its
# records; formatting the Message of a record (FormatDescription) is the slow part of an event.
$script:WorkerPerfWinEventFile = Join-Path $PSScriptRoot 'events.json'
$script:WorkerPerfWinMaxEvents = 200
$script:WorkerPerfWinLookbackMax = 2000
# records of a regular read beyond its cap that are only counted (DroppedEvents in meta.json; the count stops there, so
# the number is a lower bound: each record counted costs a read inside the regular slot)
$script:WorkerPerfWinCountBeyond = 1000
# 12 ids per select: the select then holds at most 20 expressions (provider, 12 ids, 5 levels, 2 time bounds), well
# below the 32 of the query schema; Microsoft's pages disagree on the limit (some name 23 for Get-WinEvent), and a
# select over it makes the query of the whole log invalid
$script:WorkerPerfWinMaxIdsPerQuery = 12
$script:WorkerPerfWinLookbackBudgetSec = 60
# Reads: one EventLogReader per log name and read (a log of the catalogue with two names takes two).
# Account of an event's SID: time limit of one lookup, and how long lookups pause after one ran into it.
$script:WorkerPerfWinSidTimeoutMs = 1000
$script:WorkerPerfWinSidPauseMinutes = 10

# Printing: the driver list (CIM), the isolation settings of the spooler and the queue counters (instantaneous values,
# one instance per queue besides _Total).
$script:WorkerPerfWinDriverNamespace = 'root/StandardCimv2'
$script:WorkerPerfWinDriverClass = 'MSFT_PrinterDriver'
$script:WorkerPerfWinPrintKey = 'SYSTEM\CurrentControlSet\Control\Print'
$script:WorkerPerfWinPrintPolicyKey = 'SOFTWARE\Policies\Microsoft\Windows NT\Printers'
$script:WorkerPerfWinPrintQueueCategory = 'Print Queue'
$script:WorkerPerfWinPrintQueueCounters = @('Jobs', 'Job Errors', 'Not Ready Errors')

$script:WorkerPerfWinProcessProperties = @('ProcessId', 'ParentProcessId', 'Name', 'SessionId', 'KernelModeTime', 'UserModeTime', 'WorkingSetSize',
    'PrivatePageCount', 'ReadTransferCount', 'WriteTransferCount', 'ReadOperationCount', 'WriteOperationCount', 'HandleCount', 'ThreadCount',
    'CreationDate', 'ExecutablePath')

$script:WorkerPerfWinCimTimeoutSec = 30
$script:WorkerPerfWinProbeTimeoutMs = 2000
# Timeout of the storage queries of the profile container map (they run in a snapshot, so a hanging storage provider
# delays one snapshot by at most twice this time).
$script:WorkerPerfWinStorageTimeoutSec = 10

# Health picture: time budget per area and in total (seconds), checked before every value; each CIM query gets the rest
# as its time limit. The readers per area, in the order of $script:WorkerPerfHealthAreas (an area without one is noted
# as 'noReader'). The uninstall keys of both registry views; the documented GUIDs of the power schemes.
$script:WorkerPerfWinHealthAreaBudgetSec = 10
$script:WorkerPerfWinHealthTotalBudgetSec = 60
$script:WorkerPerfWinHealthReaders = [ordered]@{
    size = 'Read-WorkerPerfWinHealthSize'; operation = 'Read-WorkerPerfWinHealthOperation'; events = 'Read-WorkerPerfWinHealthEvents'
}
$script:WorkerPerfWinUninstallKeys = @('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
$script:WorkerPerfWinPowerPlans = @{
    '381b4222-f694-41f0-9685-ff5bb260df2e' = 'balanced'; '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' = 'highPerformance'
    'a1841308-3541-4fab-bc81-f71556f20b4a' = 'powerSaver'
}
# HRESULTs of denied access: E_ACCESSDENIED (0x80070005) and WBEM_E_ACCESS_DENIED (0x80041003)
$script:WorkerPerfWinDeniedHResults = @(-2147024891, -2147217405)
# The error of compiling WorkerPerf.HealthNative, once it failed (the values that need it are then unreadable).
$script:WorkerPerfHealthTypeError = $null

# State of a capture (set by Initialize-WorkerPerfSource).
$script:WinState = $null
$script:WinEndpoints = @()
$script:WinProbe = $null
$script:WtsAvailable = $false
$script:WarnedOnce = @{}
$script:WinSidTypeFailed = $false

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

function Get-WorkerPerfPathUserCandidates([string]$Path) {
    # The user names a container path can stand for, only from the folders that carry the user, so that a user named
    # like a fixed folder ("local", "Profiles", "Microsoft") does not claim every container:
    # - location (UNC path), the folders after \\server\share: the folder itself, every part before a "." (Citrix UPM
    #   "<user>.<domain>"), and the user part of FSLogix "<sid>_<user>" / "<user>_<sid>";
    # - access path: the folder "<user>_UPM_local" (Citrix UPM) and the folder directly under "Users".
    if ([string]::IsNullOrEmpty($Path)) { return }
    $parts = $Path.Split([char[]]@('\', '/'))
    if ($Path.StartsWith('\\')) {
        # parts 0 and 1 are empty, 2 is the server, 3 the share
        for ($k = 4; $k -lt $parts.Length; $k++) {
            $seg = $parts[$k]
            if ($seg.Length -eq 0) { continue }
            $seg
            for ($i = 1; $i -lt $seg.Length; $i++) { if ($seg[$i] -eq '.') { $seg.Substring(0, $i) } }
            $u = $seg.IndexOf('_')
            if ($u -gt 0 -and $u -lt $seg.Length - 1) {
                if ($seg.Substring(0, $u) -match '^S-1-\d') { $seg.Substring($u + 1) }
                $l = $seg.LastIndexOf('_')
                if ($seg.Substring($l + 1) -match '^S-1-\d') { $seg.Substring(0, $l) }
            }
        }
        return
    }
    for ($k = 0; $k -lt $parts.Length; $k++) {
        $seg = $parts[$k]
        if ($seg.Length -eq 0) { continue }
        if ($seg.Length -gt 10 -and $seg.EndsWith('_UPM_local', [StringComparison]::OrdinalIgnoreCase)) { $seg.Substring(0, $seg.Length - 10) }
        if ($k -gt 0 -and [string]::Equals($parts[$k - 1], 'Users', [StringComparison]::OrdinalIgnoreCase)) { $seg }
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
        foreach ($cand in @(Get-WorkerPerfPathUserCandidates $path)) {
            if ($cand.Length -lt $bestLength -or -not $Index.ContainsKey($cand)) { continue }
            if ($cand.Length -gt $bestLength) { $bestLength = $cand.Length; $ids.Clear() }
            foreach ($id in $Index[$cand]) { if (-not $ids.Contains($id)) { $ids.Add($id) } }
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

function Get-WorkerPerfUpmMountUser([string]$Instance) {
    # User of a LogicalDisk instance under the Citrix UPM mount path "...\Users\<user>_UPM_local\UpmTempMount[\...]",
    # or $null for any other volume.
    $m = [regex]::Match($Instance, '\\Users\\([^\\]+)_UPM_local\\UpmTempMount(\\|$)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
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
    # Only a volume the profile map identifies as a container is 'profile'; one mounted since the last build is an
    # ordinary 'disk' until the next rebuild, so that it cannot raise a profile container finding by mistake.
    # A volume the map does not identify (mounted since its last build) is 'profile' only when its LogicalDisk instance
    # is a Citrix UPM mount path; its session comes from the "<user>_UPM_local" folder when that user has exactly one
    # session in Sessions. Every other volume is 'disk'.
    param($Values, [double]$ElapsedSec, [datetime]$Time, $ProfileMap, [int]$LogicalProcessors = 1, [object[]]$Sessions = @())

    $mb = 1048576.0
    $avail = Get-WorkerPerfWinHostValue $Values 'memory' 'Available Bytes' 'first'
    $committed = Get-WorkerPerfWinHostValue $Values 'memory' 'Committed Bytes' 'first'
    $limit = Get-WorkerPerfWinHostValue $Values 'memory' 'Commit Limit' 'first'

    $volumes = New-Object System.Collections.Generic.List[object]
    $userIndex = $null
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
            if ($null -ne $ProfileMap -and $ProfileMap.Entries.ContainsKey($name)) {
                $e = $ProfileMap.Entries[$name]
                $kind = $e.Kind; $sid = $e.SessionId; $backing = $e.Backing
            }
            else {
                $upmUser = Get-WorkerPerfUpmMountUser $name
                if ($null -ne $upmUser) {
                    $kind = 'profile'
                    if ($null -eq $userIndex) { $userIndex = New-WorkerPerfUserIndex $Sessions }
                    if ($userIndex.ContainsKey($upmUser) -and $userIndex[$upmUser].Count -eq 1) { $sid = $userIndex[$upmUser][0] }
                }
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

function New-WorkerPerfEventQueries($Config, [string]$LogId, [string[]]$Names) {
    # The queries of one log of the catalogue: one per log name, read with one EventLogReader. Each holds
    # its selects: per provider its ids, at most 12 per select (with the levels of the entries that name levels), and for
    # the entries with "ids": "*" one select by level. Emits @{ LogName; Selects = @(@{ Provider; Ids; Levels }) }
    # (Ids and Levels int[] or $null). A select stays at or below 20 expressions: provider, at most 12 ids, at most 5
    # levels, 2 time bounds.
    $byProvider = [ordered]@{}
    foreach ($e in @($Config.Entries)) {
        if ($e.log -ne $LogId) { continue }
        $k = $e.provider.ToLowerInvariant()
        if (-not $byProvider.Contains($k)) { $byProvider[$k] = @{ Name = $e.provider; IdSets = [ordered]@{}; Levels = (New-Object System.Collections.Generic.List[int]) } }
        $p = $byProvider[$k]
        if ($e.allIds) { foreach ($lv in @($e.levels)) { if (-not $p.Levels.Contains([int]$lv)) { $p.Levels.Add([int]$lv) } } }
        else {
            # ids grouped by the levels of their entry ('' = every level)
            $lv = @($e.levels | Sort-Object)
            $sig = ($lv | ForEach-Object { [string]$_ }) -join ','
            if (-not $p.IdSets.Contains($sig)) { $p.IdSets[$sig] = @{ Levels = $(if ($lv.Count -gt 0) { [int[]]$lv } else { $null }); Ids = (New-Object System.Collections.Generic.List[int]) } }
            foreach ($i in @($e.ids)) { if (-not $p.IdSets[$sig].Ids.Contains([int]$i)) { $p.IdSets[$sig].Ids.Add([int]$i) } }
        }
    }
    $max = $script:WorkerPerfWinMaxIdsPerQuery
    $selects = New-Object System.Collections.Generic.List[object]
    foreach ($p in $byProvider.Values) {
        foreach ($set in $p.IdSets.Values) {
            $ids = $set.Ids.ToArray()
            for ($i = 0; $i -lt $ids.Length; $i += $max) {
                $n = [Math]::Min($max, $ids.Length - $i)
                $chunk = New-Object int[] $n
                [Array]::Copy($ids, $i, $chunk, 0, $n)
                $selects.Add(@{ Provider = $p.Name; Ids = $chunk; Levels = $set.Levels })
            }
        }
        if ($p.Levels.Count -gt 0) { $selects.Add(@{ Provider = $p.Name; Ids = $null; Levels = $p.Levels.ToArray() }) }
    }
    if ($selects.Count -eq 0) { return }
    foreach ($name in @($Names)) { @{ LogName = $name; Selects = $selects.ToArray() } }
}

function ConvertTo-WorkerPerfXPathLiteral([string]$Text) {
    # A text as an XPath literal in ' (the form Event Viewer writes; XPath 1.0 has no escape inside a literal, and
    # whether the event log takes a literal in " is not verified, so a name with ' is refused; events.json refuses it).
    if ($Text.IndexOf("'") -lt 0) { return "'" + $Text + "'" }
    throw "Name mit ' ist in einer Ereignisabfrage nicht darstellbar: $Text"
}

function Format-WorkerPerfEventQueryTime([datetime]$Utc, [switch]$Up) {
    # A UTC time as the SystemTime literal of an event query, to the millisecond: rounded down (a lower bound) or with
    # -Up rounded up (an upper bound), so the query never cuts an event the exact comparison afterwards keeps.
    $ticks = $Utc.Ticks
    $rest = $ticks % [TimeSpan]::TicksPerMillisecond
    $ticks -= $rest
    if ($Up -and $rest -gt 0) { $ticks += [TimeSpan]::TicksPerMillisecond }
    return ([datetime]::new($ticks, [DateTimeKind]::Utc)).ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [Globalization.CultureInfo]::InvariantCulture)
}

function New-WorkerPerfEventQueryXml($Query, [datetime]$StartUtc, $EndUtc) {
    # The structured XML query of one log name: one Select per select of the query, each with the provider (matched on
    # Provider/@Name, the name ToXml() gives and the catalogue uses), its ids and levels and the time bounds as UTC
    # literals (StartUtc <= SystemTime, and SystemTime <= EndUtc when given). Get-WinEvent -FilterHashtable would turn
    # the bounds into text and parse them back as local time; the literals here carry no culture and no offset.
    $time = "@SystemTime>='" + (Format-WorkerPerfEventQueryTime (ConvertTo-WorkerPerfUtcTime $StartUtc)) + "'"
    if ($null -ne $EndUtc) { $time += " and @SystemTime<='" + (Format-WorkerPerfEventQueryTime (ConvertTo-WorkerPerfUtcTime ([datetime]$EndUtc)) -Up) + "'" }
    $path = [Security.SecurityElement]::Escape([string]$Query.LogName)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<QueryList><Query Id="0" Path="').Append($path).Append('">')
    foreach ($sel in @($Query.Selects)) {
        $x = 'Provider[@Name=' + (ConvertTo-WorkerPerfXPathLiteral ([string]$sel.Provider)) + ']'
        if ($null -ne $sel.Ids) { $x += ' and (' + ((@($sel.Ids) | ForEach-Object { 'EventID=' + [string][int]$_ }) -join ' or ') + ')' }
        if ($null -ne $sel.Levels) { $x += ' and (' + ((@($sel.Levels) | ForEach-Object { 'Level=' + [string][int]$_ }) -join ' or ') + ')' }
        $x = '*[System[' + $x + ' and TimeCreated[' + $time + ']]]'
        [void]$sb.Append('<Select Path="').Append($path).Append('">').Append([Security.SecurityElement]::Escape($x)).Append('</Select>')
    }
    [void]$sb.Append('</Query></QueryList>')
    return $sb.ToString()
}

function ConvertFrom-WorkerPerfDriverVersion([uint64]$Value) {
    # DriverVersion of MSFT_PrinterDriver: four 16-bit parts, highest first -> 'a.b.c.d'; '' for 0 (not set).
    if ($Value -eq 0) { return '' }
    $parts = foreach ($shift in 48, 32, 16, 0) { [string](($Value -shr $shift) -band 0xFFFF) }
    return ($parts -join '.')
}

function ConvertFrom-WorkerPerfIsolationGroups([string]$Value) {
    # PrintDriverIsolationGroups (its strings joined with '\\'): groups separated by '\\', drivers within a group by '\'.
    # The first group runs inside the spooler (none), the second in the shared process (shared), every further one
    # alone (isolated). Driver name (case-insensitive) -> none/shared/isolated; a driver in several groups keeps the first.
    $map = @{}
    if ([string]::IsNullOrEmpty($Value)) { return $map }
    $groups = $Value -split '\\\\'
    for ($g = 0; $g -lt $groups.Length; $g++) {
        $kind = 'isolated'
        if ($g -eq 0) { $kind = 'none' } elseif ($g -eq 1) { $kind = 'shared' }
        foreach ($name in ($groups[$g] -split '\\')) {
            if ($name -ne '' -and -not $map.ContainsKey($name)) { $map[$name] = $kind }
        }
    }
    return $map
}

function ConvertTo-WorkerPerfDword($Value) {
    # A registry DWORD as an unsigned number; $null when the value is missing or no number.
    if ($null -eq $Value) { return $null }
    $v = $null
    try { $v = [int64]$Value } catch { return $null }
    if ($v -lt 0) { $v += 4294967296 }
    return $v
}

function Get-WorkerPerfEffectiveIsolation([string]$Name, $Groups, $Attribute, $Policy) {
    # The mode a driver runs in, as the probe script derives it (Microsoft's decision map, "Printer driver isolation"):
    # isolation switched off by policy (PrintDriverIsolationExecutionPolicy = 0) puts every driver into the spooler;
    # otherwise a driver listed in PrintDriverIsolationGroups ($Groups, from ConvertFrom-WorkerPerfIsolationGroups) runs
    # in that mode; otherwise every driver runs shared when PrintDriverIsolationOverrideCompat = 1; otherwise a driver
    # compatible with isolation (PrinterDriverAttributes bit 0x4) runs shared, an incompatible one in the spooler.
    # $Policy: policy value name -> value (only the values that are set). '' when the attribute was not read and the
    # policies do not decide.
    $exec = $null; $override = $null
    if ($null -ne $Policy) {
        $exec = ConvertTo-WorkerPerfDword (Get-WorkerPerfField $Policy 'PrintDriverIsolationExecutionPolicy')
        $override = ConvertTo-WorkerPerfDword (Get-WorkerPerfField $Policy 'PrintDriverIsolationOverrideCompat')
    }
    if ($null -ne $exec -and $exec -eq 0) { return 'none' }
    if ($null -ne $Groups -and $Name -ne '' -and $Groups.ContainsKey($Name)) { return [string]$Groups[$Name] }
    if ($null -ne $override -and $override -eq 1) { return 'shared' }
    $a = ConvertTo-WorkerPerfDword $Attribute
    if ($null -eq $a) { return '' }
    if (($a -band 4) -ne 0) { return 'shared' }
    return 'none'
}

function ConvertTo-WorkerPerfPrintDriver($Driver, $Groups, $Attribute, $Policy) {
    # One driver of MSFT_PrinterDriver as a record of printdrivers.csv: Type = MajorVersion (3 or 4), Files = the file
    # names without path of the driver, configuration, data and dependent files, each once (case-insensitive).
    $files = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    foreach ($f in @((Get-WorkerPerfField $Driver 'Path'), (Get-WorkerPerfField $Driver 'ConfigFile'), (Get-WorkerPerfField $Driver 'DataFile')) + @(Get-WorkerPerfField $Driver 'DependentFiles')) {
        $t = [string]$f
        if ($t.Trim().Length -eq 0) { continue }
        $leaf = $t.Substring($t.LastIndexOfAny([char[]]@('\', '/')) + 1).Trim()
        if ($leaf.Length -eq 0 -or $seen.ContainsKey($leaf)) { continue }
        $seen[$leaf] = $true
        $files.Add($leaf)
    }
    $type = $null
    $major = Get-WorkerPerfField $Driver 'MajorVersion'
    if ($null -ne $major) { try { $type = [int]$major } catch { $type = $null } }
    $version = ''
    $raw = Get-WorkerPerfField $Driver 'DriverVersion'
    if ($null -ne $raw) { try { $version = ConvertFrom-WorkerPerfDriverVersion ([uint64]$raw) } catch { $version = '' } }
    $name = [string](Get-WorkerPerfField $Driver 'Name')
    return [pscustomobject]@{
        Name = $name; Manufacturer = [string](Get-WorkerPerfField $Driver 'Manufacturer'); Version = $version; Type = $type
        Isolation = (Get-WorkerPerfEffectiveIsolation $name $Groups $Attribute $Policy); Files = [string[]]$files.ToArray()
    }
}

function ConvertTo-WorkerPerfPrintQueueRows($Values) {
    # One record per print queue from the counter values (counter -> instance -> value), without totals, sorted by name.
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($cn in $script:WorkerPerfWinPrintQueueCounters) {
        $v = $Values[$cn]
        if ($null -eq $v) { continue }
        foreach ($i in $v.Keys) { if (-not (Test-WorkerPerfTotalInstance ([string]$i)) -and -not $names.Contains([string]$i)) { $names.Add([string]$i) } }
    }
    $arr = $names.ToArray()
    [Array]::Sort($arr, [StringComparer]::Ordinal)
    $get = { param($counter, $queue) $v = $Values[$counter]; if ($null -ne $v -and $v.ContainsKey($queue)) { $v[$queue] } else { $null } }
    foreach ($q in $arr) {
        [pscustomobject]@{ Queue = $q; Jobs = (& $get 'Jobs' $q); JobErrors = (& $get 'Job Errors' $q); NotReadyErrors = (& $get 'Not Ready Errors' $q) }
    }
}

function ConvertTo-WorkerPerfUtcTime([datetime]$Time) {
    # Event times are compared in UTC: in the repeated hour at the end of daylight saving time local times are ambiguous.
    if ($Time.Kind -eq [DateTimeKind]::Utc) { return $Time }
    return $Time.ToUniversalTime()
}

function ConvertTo-WorkerPerfLogInfo($Info) {
    # The state of an event log from the object of Get-WinEvent -ListLog: Mode is the name of LogMode, not its number
    # (ConvertTo-Json would write the number); a field the object lacks is $null.
    $mb = { param($v) if ($null -eq $v) { $null } else { [Math]::Round([double]$v / 1048576.0, 1) } }
    $enabled = Get-WorkerPerfField $Info 'IsEnabled'; $records = Get-WorkerPerfField $Info 'RecordCount'
    $mode = Get-WorkerPerfField $Info 'LogMode'; $full = Get-WorkerPerfField $Info 'IsLogFull'
    return [ordered]@{
        Enabled = $(if ($null -ne $enabled) { [bool]$enabled } else { $null })
        MaxSizeMB = (& $mb (Get-WorkerPerfField $Info 'MaximumSizeInBytes'))
        FileSizeMB = (& $mb (Get-WorkerPerfField $Info 'FileSize'))
        Records = $(if ($null -ne $records) { [long]$records } else { $null })
        Mode = $(if ($null -ne $mode) { [string]$mode } else { $null })
        Full = $(if ($null -ne $full) { [bool]$full } else { $null })
    }
}

function ConvertTo-WorkerPerfPowerPlan([string]$Guid) {
    # balanced, highPerformance, powerSaver for the documented GUIDs, else other.
    $key = $Guid.Trim().Trim('{', '}').ToLowerInvariant()
    if ($script:WorkerPerfWinPowerPlans.ContainsKey($key)) { return $script:WorkerPerfWinPowerPlans[$key] }
    return 'other'
}

function ConvertFrom-WorkerPerfHotFixDate($Value) {
    # InstalledOn of Win32_QuickFixEngineering: a DateTime as it is, a text only in the form M/d/yyyy (invariant
    # culture); any other form (a local date, a hexadecimal FILETIME, empty) gives $null.
    if ($Value -is [datetime]) { return $Value }
    if ($null -eq $Value) { return $null }
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParseExact(([string]$Value).Trim(), 'M/d/yyyy', [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) { return $parsed }
    return $null
}

function Select-WorkerPerfLatestHotFix([object[]]$HotFixes) {
    # The update with the newest readable installation date: @{ Id; InstalledOn }, or $null without a readable date.
    $best = $null
    foreach ($hf in @($HotFixes)) {
        if ($null -eq $hf) { continue }
        $on = ConvertFrom-WorkerPerfHotFixDate (Get-WorkerPerfField $hf 'InstalledOn')
        if ($null -eq $on) { continue }
        if ($null -eq $best -or $on -gt $best.InstalledOn) { $best = @{ Id = [string](Get-WorkerPerfField $hf 'HotFixID'); InstalledOn = $on } }
    }
    return $best
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

function Register-WorkerPerfSidType {
    # Compiles the SID lookup once, at the start (compiling inside the first read would lengthen that read).
    if ($script:WinSidTypeFailed -or ('WorkerPerf.SidLookup' -as [type])) { return }
    try { Add-Type -TypeDefinition $script:WorkerPerfSidSource -Language CSharp }
    catch {
        $script:WinSidTypeFailed = $true
        Write-WarningOnce 'sid' "Konten der Ereignisse nicht aufloesbar, Ereignisse ohne Benutzer bleiben ohne: $($_.Exception.Message)"
    }
}

function Get-WorkerPerfSidAccount([string]$Sid) {
    # @{ Name ('DOMAIN\name' or ''); TimedOut }: the translation of a SID by Windows, given up after the time limit.
    if ($script:WinSidTypeFailed -or -not ('WorkerPerf.SidLookup' -as [type])) { return @{ Name = ''; TimedOut = $false } }
    $timedOut = $false
    $name = [WorkerPerf.SidLookup]::Translate($Sid, $script:WorkerPerfWinSidTimeoutMs, [ref]$timedOut)
    return @{ Name = [string]$name; TimedOut = [bool]$timedOut }
}

function Open-WorkerPerfEventReader([string]$QueryXml, [bool]$Oldest) {
    # An EventLogReader over the structured XML query (newest first unless Oldest), as the probe script reads events.
    # The query names its log; a missing log throws here (EventLogNotFoundException). The caller disposes the reader.
    $q = New-Object System.Diagnostics.Eventing.Reader.EventLogQuery -ArgumentList $null, ([System.Diagnostics.Eventing.Reader.PathType]::LogName), $QueryXml
    $q.ReverseDirection = (-not $Oldest)
    return (New-Object System.Diagnostics.Eventing.Reader.EventLogReader -ArgumentList $q)
}

function Open-WorkerPerfRegistryKey([string]$SubKey) {
    # A key below HKLM, read only; $null when it does not exist. Unlike the registry provider, a '/' stays part of a name.
    return [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($SubKey, $false)
}

function Get-WorkerPerfRegistryValues([string]$SubKey) {
    # The values (name -> value) and the names of the subkeys of a key below HKLM, read only; $null when it is missing.
    $key = Open-WorkerPerfRegistryKey $SubKey
    if ($null -eq $key) { return $null }
    try {
        $values = [ordered]@{}
        foreach ($name in @($key.GetValueNames())) { $values[[string]$name] = $key.GetValue($name) }
        return @{ Values = $values; SubKeys = [string[]]@($key.GetSubKeyNames()) }
    }
    finally { $key.Close() }
}

function Register-WorkerPerfHealthType {
    # Compiles WorkerPerf.HealthNative once per process, at its first use; a failed compile throws again at every use.
    if ('WorkerPerf.HealthNative' -as [type]) { return }
    if ($null -ne $script:WorkerPerfHealthTypeError) { throw $script:WorkerPerfHealthTypeError }
    try { Add-Type -TypeDefinition $script:WorkerPerfHealthNativeSource -Language CSharp }
    catch {
        $script:WorkerPerfHealthTypeError = $_.Exception
        throw
    }
}

function Get-WorkerPerfPerformanceInfo {
    # Commit charge, limit and peak in MB (GetPerformanceInfo).
    Register-WorkerPerfHealthType
    $c = [WorkerPerf.HealthNative]::GetCommit()
    return @{ CommitTotalMB = [Math]::Round($c[0] / 1048576.0); CommitLimitMB = [Math]::Round($c[1] / 1048576.0); CommitPeakMB = [Math]::Round($c[2] / 1048576.0) }
}

function Get-WorkerPerfActivePowerScheme {
    # The GUID of the active power scheme in lower case (PowerGetActiveScheme).
    Register-WorkerPerfHealthType
    return ([WorkerPerf.HealthNative]::GetActivePowerScheme()).ToString().ToLowerInvariant()
}

function Get-WorkerPerfLogOldestTime([string]$LogName) {
    # The time of the oldest entry of a log (the first record of a reader in ascending direction; its message is not
    # formatted), or $null when the log is empty.
    $query = New-Object System.Diagnostics.Eventing.Reader.EventLogQuery -ArgumentList $LogName, ([System.Diagnostics.Eventing.Reader.PathType]::LogName)
    $query.ReverseDirection = $false
    $reader = New-Object System.Diagnostics.Eventing.Reader.EventLogReader -ArgumentList $query
    try {
        $record = $reader.ReadEvent()
        if ($null -eq $record) { return $null }
        try {
            $created = $record.TimeCreated
            if ($null -eq $created) { return $null }
            return [datetime]$created
        }
        finally { $record.Dispose() }
    }
    finally { $reader.Dispose() }
}

function Get-WorkerPerfPrintIsolationGroups {
    # PrintDriverIsolationGroups of the spooler (one or several strings), or $null when it is not set.
    $key = Open-WorkerPerfRegistryKey $script:WorkerPerfWinPrintKey
    if ($null -eq $key) { return $null }
    try { return $key.GetValue('PrintDriverIsolationGroups') } finally { $key.Close() }
}

function Get-WorkerPerfPrintIsolationPolicy {
    # The group policies on driver isolation that are set: value name -> value.
    $policy = @{}
    $key = Open-WorkerPerfRegistryKey $script:WorkerPerfWinPrintPolicyKey
    if ($null -eq $key) { return $policy }
    try {
        $present = @($key.GetValueNames())
        foreach ($name in 'PrintDriverIsolationExecutionPolicy', 'PrintDriverIsolationOverrideCompat') {
            if ($present -contains $name) { $policy[$name] = $key.GetValue($name) }
        }
    }
    finally { $key.Close() }
    return $policy
}

function Get-WorkerPerfPrintDriverAttribute($Driver) {
    # PrinterDriverAttributes below the driver's key (...\Print\Environments\<env>\Drivers\Version-<n>\<name>), or $null.
    $name = [string](Get-WorkerPerfField $Driver 'Name')
    $environment = [string](Get-WorkerPerfField $Driver 'PrinterEnvironment')
    $version = [string](Get-WorkerPerfField $Driver 'MajorVersion')
    if ($name -eq '' -or $environment -eq '' -or $version -eq '') { return $null }
    $key = Open-WorkerPerfRegistryKey ('{0}\Environments\{1}\Drivers\Version-{2}\{3}' -f $script:WorkerPerfWinPrintKey, $environment, $version, $name)
    if ($null -eq $key) { return $null }
    try { return $key.GetValue('PrinterDriverAttributes') } finally { $key.Close() }
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
    # the fast cadence saw an unknown LogicalDisk instance), never from the fast cadence. A failure keeps the old map,
    # takes the instances of now as known (they stay plain disks) and leaves the next attempt to the next keyframe, so
    # that a hanging storage provider does not stall every regular snapshot.
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
            $State.MapFailed = $false
            return
        }
        catch {
            Write-WarningOnce 'profile.map' "Zuordnung der Profilcontainer fehlgeschlagen; neue Laufwerke erscheinen bis zum naechsten erfolgreichen Versuch an einem Stuetzpunkt als Datentraeger: $($_.Exception.Message)"
            $State.MapFailed = $true
            if ($null -ne $State.Map) {
                foreach ($k in @($known)) { if (-not [string]::IsNullOrEmpty($k)) { $State.Map.Known[$k] = $true } }
                return
            }
        }
    }
    # without the storage classes every volume is a plain disk
    if ($null -eq $State.Map -or -not $State.ProfileMapOk) { $State.Map = New-WorkerPerfProfileMap -Disks @() -Sessions @() -Known $known }
}

#endregion

#region ---------- data source interface ------------------------------------------------------------------------------

function Test-WorkerPerfWinMeasured([string]$Category) {
    # $false when -Skip left the category out of this capture (before the start every category counts as measured).
    $st = $script:WinState
    return ($null -eq $st -or @($st.Skip) -notcontains $Category)
}

function Initialize-WorkerPerfSource {
    param([datetime]$StartTime, [object[]]$Endpoints = @(), [string]$CitrixMetricFilter = '', [switch]$IncludeCommandLine, [string[]]$Skip = @(),
          [object]$EventConfig = $null, [object[]]$Apps = @())
    # StartTime exists for the common interface: the clock of this source is the system clock. EventConfig: the event
    # catalogue (Read-WorkerPerfEventConfig); without it the source reads events.json next to this file.
    # Skip: the categories left out (Resolve-WorkerPerfSkip). For them the source checks and opens nothing, makes no
    # Windows call later and writes no entry into Sources (the collector notes them). The logs events.<id> belong to
    # Ereignisse and Rueckblick together: they are checked while either of the two is measured.
    # The health picture (Get-WorkerPerfHealth) reuses what is read here: the two CIM objects, the objects of
    # Get-WinEvent -ListLog (LogInfo) and the application list given in Apps (as Read-WorkerPerfHealthApps returns it).

    $leftOut = [string[]]@($Skip | Where-Object { $_ })
    $withEventLogs = ($leftOut -notcontains 'Ereignisse' -or $leftOut -notcontains 'Rueckblick')
    $script:WarnedOnce = @{}
    if (-not (Test-WorkerPerfElevated)) {
        Write-Warning 'WorkerPerf laeuft ohne erhoehte Rechte: Prozesse anderer Benutzer, Profilcontainer und Ereignisprotokolle koennen fehlen.'
    }
    $wtsError = Register-WorkerPerfNativeTypes
    if ($leftOut -notcontains 'Gegenstellen') { Register-WorkerPerfProbeType }
    if ($withEventLogs) { Register-WorkerPerfSidType }

    $cs = @(Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec $script:WorkerPerfWinCimTimeoutSec -ErrorAction Stop)[0]
    $os = @(Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec $script:WorkerPerfWinCimTimeoutSec -ErrorAction Stop)[0]

    $state = @{
        Categories = @{}; Prev = @{}; Clock = $null; Map = $null; MapPending = $false; MapFailed = $false; VolumeNames = $null; ProfileMapOk = $false
        LogicalProcessors = 1
        IncludeCommandLine = [bool]$IncludeCommandLine; CitrixFilter = $CitrixMetricFilter; Skip = $leftOut
        Ica = $null; IcaCounters = $null; Euem = $false; Logs = (New-Object System.Collections.Generic.List[object])
        EventConfig = $null; SidCache = @{}; SidPauseUntil = [datetime]::MinValue; PrintDrivers = $false; PrintQueue = $null
        LogErrors = (New-Object System.Collections.Generic.List[object]); LogErrorsSeen = @{}; EventCounts = [ordered]@{}
        ComputerSystem = $cs; OperatingSystem = $os; LogInfo = @{}; Apps = [object[]]@($Apps | Where-Object { $null -ne $_ })
    }

    # ---- performance counters: one status per counter group ----
    $groupStatus = @{}
    foreach ($key in $script:WorkerPerfWinCounters.Keys) {
        if ($leftOut -contains $script:WorkerPerfWinCounterCategories[$key]) { continue }
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
        if ($null -eq $g) { continue }
        $sources[$id] = @{ Available = $g.Available; Detail = $g.Detail }
    }

    # ---- Citrix ----
    if ($leftOut -notcontains 'Citrix') {
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

    $script:WinEndpoints = @()
    if ($leftOut -notcontains 'Gegenstellen') {
        $script:WinEndpoints = @($Endpoints | Where-Object { $null -ne $_ })
        if ($script:WinEndpoints.Count -gt 0) { $sources['probe.connect'] = @{ Available = $true; Detail = ('{0} Gegenstellen' -f $script:WinEndpoints.Count) } }
        else { $sources['probe.connect'] = @{ Available = $false; Detail = 'keine Gegenstellen (endpoints.json fehlt oder ist leer)' } }
    }

    if ($leftOut -notcontains 'Prozesse') { $sources['process'] = @{ Available = $true; Detail = 'Win32_Process' } }
    if ($script:WtsAvailable) { $sources['sessions'] = @{ Available = $true; Detail = 'WTS-Schnittstelle' } }
    else { $sources['sessions'] = @{ Available = $false; Detail = ('WTS-Schnittstelle nicht verfuegbar: {0}' -f $wtsError) } }
    $g = $groupStatus['inputProcess']
    if ($null -ne $g) { $sources['input.process'] = @{ Available = $g.Available; Detail = $g.Detail } }

    # ---- profile containers ----
    if ($leftOut -notcontains 'Laufwerke') {
        try {
            $disks = @(Get-WorkerPerfProfileDisks)
            $state.ProfileMapOk = $true
            $sources['profile.map'] = @{ Available = $true; Detail = ('MSFT_Disk BusType 15, beim Start {0} Container' -f $disks.Count) }
        }
        catch { $sources['profile.map'] = @{ Available = $false; Detail = ('MSFT_Disk nicht lesbar: {0}' -f $_.Exception.Message) } }
    }

    # ---- event logs: every log of the catalogue that an entry reads, available or not ----
    # The capture reads the enabled log names; the lookback also reads a log name that exists but is switched off, for
    # the events it holds from before (M14). A log with no enabled name stays not available for the capture; when the
    # lookback reads it, its source entry says so (LookbackRead).
    if ($null -eq $EventConfig) { $EventConfig = Read-WorkerPerfEventConfig $script:WorkerPerfWinEventFile }
    $state.EventConfig = $EventConfig
    $readLogs = @()
    if ($withEventLogs) { $readLogs = @(Get-WorkerPerfEventReadLogs $EventConfig) }
    foreach ($l in $readLogs) {
        $readable = New-Object System.Collections.Generic.List[string]
        $present = New-Object System.Collections.Generic.List[string]
        foreach ($name in @($l.Names)) {
            try {
                $info = Get-WinEvent -ListLog $name -ErrorAction Stop
                if ($null -ne $info) {
                    $state.LogInfo[$name] = $info
                    $present.Add($name)
                    if ([bool]$info.IsEnabled) { $readable.Add($name) }
                }
            }
            catch { Write-Verbose ('Protokoll {0} nicht vorhanden: {1}' -f $name, $_.Exception.Message) }
        }
        $id = 'events.' + $l.Id
        $lookbackNames = [string[]]@()
        # only a lookback that runs reads a switched-off log (-Skip Rueckblick, also -EventLookbackDays 0, reads none)
        if ($l.Lookback -and $leftOut -notcontains 'Rueckblick') { $lookbackNames = $present.ToArray() }
        if ($readable.Count -gt 0 -or $lookbackNames.Count -gt 0) {
            $names = $readable.ToArray()
            $log = @{ Id = $l.Id; Names = $names; Lookback = ($lookbackNames.Count -gt 0); Queries = @(New-WorkerPerfEventQueries $EventConfig $l.Id $names)
                LookbackNames = $lookbackNames; LookbackQueries = @(New-WorkerPerfEventQueries $EventConfig $l.Id $lookbackNames) }
            $state.Logs.Add($log)
            # every provider name must be writable as a query literal; a catalogue that breaks this stops here, not in a read
            foreach ($q in @($log.Queries) + @($log.LookbackQueries)) { [void](New-WorkerPerfEventQueryXml $q ([datetime]::UtcNow) $null) }
            if ($names.Length -gt 0) { $sources[$id] = @{ Available = $true; Detail = ($names -join ', ') } }
            else { $sources[$id] = @{ Available = $false; Detail = 'Protokoll abgeschaltet; der Rueckblick liest die vorhandenen Ereignisse'; LookbackRead = $true } }
        }
        else { $sources[$id] = @{ Available = $false; Detail = 'Protokoll nicht vorhanden oder abgeschaltet' } }
    }

    # ---- printing: driver list and queue counters (without Drucken PrintDrivers stays off and PrintQueue empty) ----
    if ($leftOut -notcontains 'Drucken') {
        try {
            [void](Get-CimClass -Namespace $script:WorkerPerfWinDriverNamespace -ClassName $script:WorkerPerfWinDriverClass -OperationTimeoutSec $script:WorkerPerfWinCimTimeoutSec -ErrorAction Stop)
            $state.PrintDrivers = $true
            $sources['print.drivers'] = @{ Available = $true; Detail = ('{0}: {1}' -f $script:WorkerPerfWinDriverNamespace, $script:WorkerPerfWinDriverClass) }
        }
        catch { $sources['print.drivers'] = @{ Available = $false; Detail = ('{0}: Klasse {1} nicht vorhanden' -f $script:WorkerPerfWinDriverNamespace, $script:WorkerPerfWinDriverClass) } }
        $reason = ''
        try {
            foreach ($c in $script:WorkerPerfWinPrintQueueCounters) {
                $reason = [string](Test-WorkerPerfWinCounter $script:WorkerPerfWinPrintQueueCategory $c)
                if ($reason) { break }
            }
            if (-not $reason) {
                $state.PrintQueue = Open-WorkerPerfWinCategory $script:WorkerPerfWinPrintQueueCategory
                if ($null -eq $state.PrintQueue) { $reason = 'Kategorie nicht vorhanden' }
            }
        }
        catch { $reason = 'Pruefung fehlgeschlagen: ' + $_.Exception.Message; $state.PrintQueue = $null }
        if ($reason) { $sources['print.queues'] = @{ Available = $false; Detail = ('{0}: {1}' -f $script:WorkerPerfWinPrintQueueCategory, $reason) } }
        else {
            $sources['print.queues'] = @{ Available = $true; Detail = ('{0} / {1}' -f $script:WorkerPerfWinPrintQueueCategory, ($script:WorkerPerfWinPrintQueueCounters -join ', ')) }
        }
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
    $sessions = @()
    if ($null -ne $volumeNames) {
        # a new instance (for example a container mounted at a logon) is mapped by the next regular snapshot
        $st.VolumeNames = $volumeNames
        if ($null -ne $st.Map -and @(Get-WorkerPerfUnknownVolumes -Instances $volumeNames -Map $st.Map).Count -gt 0) { $st.MapPending = $true }
        # until then a UPM mount path not in the map gets its session from the sessions of now (WTS, a few ms)
        foreach ($n in $volumeNames) {
            if ($null -ne $st.Map -and -not $st.Map.Entries.ContainsKey($n) -and $null -ne (Get-WorkerPerfUpmMountUser $n)) { $sessions = @(Get-WinSessionRaw); break }
        }
    }

    return ConvertTo-WorkerPerfWinFastSample -Values $values -ElapsedSec $elapsed -Time $time -ProfileMap $st.Map -LogicalProcessors $st.LogicalProcessors -Sessions $sessions
}

function Get-WorkerPerfSnapshot {
    param([string]$Kind = 'R')
    # Kind: 'K' keyframe, 'R' regular, 'B' burst snapshot. The profile container map is rebuilt here: at every keyframe,
    # and at a regular snapshot when the fast cadence has seen a LogicalDisk instance unknown to the map. Processes
    # need Prozesse, the map Laufwerke, the Citrix values Citrix; the sessions are the base.
    $st = $script:WinState
    if ($null -eq $st) { throw 'Die Windows-Datenquelle ist nicht initialisiert.' }
    $time = [datetime]::Now
    $processes = @()
    if (Test-WorkerPerfWinMeasured 'Prozesse') { $processes = @(Get-WinProcessRaw) }
    $sessions = @(Get-WinSessionRaw)
    if ((Test-WorkerPerfWinMeasured 'Laufwerke') -and ($Kind -eq 'K' -or $null -eq $st.Map -or ($Kind -eq 'R' -and $st.MapPending -and -not $st.MapFailed))) {
        Update-WorkerPerfProfileMap $st $sessions
    }
    $citrix = @()
    if (Test-WorkerPerfWinMeasured 'Citrix') { $citrix = @(Get-WinCitrixRaw -Sessions $sessions) }
    return @{ Time = $time; Processes = $processes; Sessions = $sessions; Citrix = $citrix }
}

function Get-WorkerPerfServices {
    # PID -> 'Service1;Service2'; empty without Prozesse.
    if (-not (Test-WorkerPerfWinMeasured 'Prozesse')) { return @{} }
    return ConvertTo-WorkerPerfServiceMap @(Get-CimInstance -ClassName Win32_Service -Property Name, ProcessId -Filter 'ProcessId > 0' `
            -OperationTimeoutSec $script:WorkerPerfWinCimTimeoutSec -ErrorAction Stop)
}

function Start-WorkerPerfProbes {
    param([object[]]$Endpoints)
    # Starts a TCP connect to every endpoint (without -Endpoints: those given to Initialize-WorkerPerfSource) and returns
    # at once; Receive-WorkerPerfProbes collects the results. Without Gegenstellen no connection is made, whatever
    # -Endpoints names.
    $script:WinProbe = $null
    if (-not (Test-WorkerPerfWinMeasured 'Gegenstellen')) { return }
    Register-WorkerPerfProbeType
    if (-not $PSBoundParameters.ContainsKey('Endpoints')) { $Endpoints = $script:WinEndpoints }
    $list = @($Endpoints | Where-Object { $null -ne $_ })
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

function Resolve-WorkerPerfEventSid([string]$Sid) {
    # The account of an event's SID: the well-known service accounts by their SID, any other once per SID through
    # Windows (cached, also when Windows knows none). After a lookup ran into its time limit the lookups pause for
    # 10 minutes ('' meanwhile), so an unreachable domain controller delays a read by at most one time limit.
    if ([string]::IsNullOrWhiteSpace($Sid)) { return '' }
    $known = Resolve-WorkerPerfWellKnownSid $Sid
    if ($known) { return $known }
    $st = $script:WinState
    if ($st.SidCache.ContainsKey($Sid)) { return [string]$st.SidCache[$Sid] }
    if ([datetime]::UtcNow -lt $st.SidPauseUntil) { return '' }
    $r = $null
    try { $r = Get-WorkerPerfSidAccount $Sid }
    catch { $r = @{ Name = ''; TimedOut = $false } }
    if ($r.TimedOut) {
        $st.SidPauseUntil = [datetime]::UtcNow.AddMinutes($script:WorkerPerfWinSidPauseMinutes)
        return ''
    }
    $st.SidCache[$Sid] = [string]$r.Name
    return [string]$r.Name
}

function ConvertTo-WorkerPerfWinEventRecord($Config, [string]$LogId, $Event) {
    # A record of an event of the log from its XML and the catalogue, or $null (not in the catalogue, unreadable). The
    # User comes from the data fields, else from the account of the System part.
    if ($null -eq $Event -or $null -eq $Event.TimeCreated) { return $null }
    $parsed = ConvertFrom-WorkerPerfEventXml ([string]$Event.Xml)
    if ($null -eq $parsed) { return $null }
    $entry = Resolve-WorkerPerfEventEntry $Config $LogId $parsed.Provider $parsed.EventId $parsed.Level
    if ($null -eq $entry) { return $null }
    $rec = ConvertTo-WorkerPerfEventRecord $entry $parsed ([datetime]$Event.TimeCreated) ([string]$Event.Message)
    if ($null -eq $rec) { return $null }
    if ($rec.User.Length -eq 0 -and $parsed.UserSid.Length -gt 0) { $rec.User = ConvertTo-WorkerPerfEventAccountName (Resolve-WorkerPerfEventSid $parsed.UserSid) $Config }
    return $rec
}

function Get-WorkerPerfErrorClass($Exception) {
    # The class of a failure: the type name of the exception, without the wrappers PowerShell puts around a method
    # that threw (MethodInvocationException, and a plain RuntimeException around a script method's exception).
    $ex = $Exception
    $guard = 0
    while ($null -ne $ex -and $null -ne $ex.InnerException -and $guard -lt 5 -and
        ($ex -is [System.Management.Automation.MethodException] -or $ex.GetType() -eq [System.Management.Automation.RuntimeException])) { $ex = $ex.InnerException; $guard++ }
    if ($null -eq $ex) { return 'Exception' }
    return $ex.GetType().Name
}

function Get-WorkerPerfErrorText($Exception) {
    $ex = $Exception
    $guard = 0
    while ($null -ne $ex -and $null -ne $ex.InnerException -and $guard -lt 5 -and
        ($ex -is [System.Management.Automation.MethodException] -or $ex.GetType() -eq [System.Management.Automation.RuntimeException])) { $ex = $ex.InnerException; $guard++ }
    if ($null -eq $ex) { return '' }
    return [string]$ex.Message
}

function Add-WorkerPerfLogError([string]$Source, [string]$LogId, [string]$LogName, [string]$Class, [string]$Text) {
    # A log name that could not be read: queued once per data source call kind ('events', 'eventsbefore') and log name
    # for Receive-WorkerPerfSourceErrors, under '<kind>.<log id>' (M13: one entry of SourceErrors in meta.json per log),
    # which the collector books and warns about once.
    $st = $script:WinState
    $key = $Source + '|' + $LogName
    if ($st.LogErrorsSeen.ContainsKey($key)) { return }
    $st.LogErrorsSeen[$key] = $true
    $st.LogErrors.Add(@{ Source = ($Source + '.' + $LogId); Message = ("Ereignisprotokoll '{0}' nicht lesbar ({1}): {2}" -f $LogName, $Class, $Text) })
}

function Get-WorkerPerfEventCounter([string]$LogId) {
    # The counters of one log of the catalogue for meta.json (EventReadCounts): numbers only.
    $st = $script:WinState
    if (-not $st.EventCounts.Contains($LogId)) { $st.EventCounts[$LogId] = [ordered]@{ SkippedRecords = 0; UnformattedMessages = 0; DroppedEvents = 0 } }
    return $st.EventCounts[$LogId]
}

function Read-WorkerPerfEventRecords($Reader, [int]$Max, [System.Diagnostics.Stopwatch]$Clock = $null, [double]$BudgetMs = 0, [int]$CountBeyond = 1) {
    # Reads at most Max records from an event reader (ReadEvent until $null) and releases each at once. Per record: its
    # time, record id, XML and message (FormatDescription; a message that cannot be formatted is '' and counted). Then
    # up to CountBeyond further records are only counted (Beyond; neither converted nor formatted). A record that
    # cannot be read, or whose XML cannot be taken, is skipped and counted; after 3 such records in a row the read ends
    # as Failed. With Clock, the read also ends (BudgetHit) when Clock reaches BudgetMs.
    # Bounds: each pass of the loop either keeps or counts a record (at most Max + CountBeyond) or adds a failure; at
    # most 2 failures lie between two such records, so the loop makes at most 3 * (Max + CountBeyond + 1) passes; a
    # counter enforces that bound too. ReadEvent itself returns $null at the end of the result.
    $records = New-Object System.Collections.Generic.List[object]
    $skipped = 0; $unformatted = 0; $inRow = 0; $passes = 0; $beyond = 0
    $failed = $false; $class = ''; $text = ''; $budgetHit = $false
    $maxPasses = 3 * ($Max + $CountBeyond + 1)
    while ($records.Count + $beyond -lt $Max + $CountBeyond -and $passes -lt $maxPasses) {
        $passes++
        if ($null -ne $Clock -and $Clock.ElapsedMilliseconds -ge $BudgetMs) { $budgetHit = $true; break }
        $rec = $null
        try { $rec = $Reader.ReadEvent() }
        catch {
            $skipped++; $inRow++
            if ($inRow -ge 3) { $failed = $true; $class = Get-WorkerPerfErrorClass $_.Exception; $text = Get-WorkerPerfErrorText $_.Exception; break }
            continue
        }
        if ($null -eq $rec) { break }
        if ($records.Count -ge $Max) {
            $beyond++; $inRow = 0
            try { $rec.Dispose() } catch { $null = $_ }
            continue
        }
        try {
            $xml = $null
            try { $xml = [string]$rec.ToXml() }
            catch { $xml = $null; $class = Get-WorkerPerfErrorClass $_.Exception; $text = Get-WorkerPerfErrorText $_.Exception }
            if ([string]::IsNullOrEmpty($xml)) {
                $skipped++; $inRow++
                if ($inRow -ge 3) {
                    $failed = $true
                    if ($class -eq '') { $class = 'EmptyRecord'; $text = 'Ereignis ohne XML' }
                    break
                }
                continue
            }
            $inRow = 0
            $message = $null
            try { $message = $rec.FormatDescription() } catch { $message = $null }
            if ($null -eq $message) { $message = ''; $unformatted++ }
            $records.Add([pscustomobject]@{ TimeCreated = $rec.TimeCreated; RecordId = $rec.RecordId; Xml = $xml; Message = [string]$message })
        }
        finally { try { $rec.Dispose() } catch { $null = $_ } }
    }
    return @{ Records = $records.ToArray(); Beyond = $beyond; Skipped = $skipped; Unformatted = $unformatted; Failed = $failed; Class = $class; Text = $text; BudgetHit = $budgetHit }
}

function Read-WorkerPerfWinLogEvents($Log, [datetime]$StartUtc, $EndUtc, [int]$Max, [switch]$Oldest, [string]$Source = 'events',
                                     [System.Diagnostics.Stopwatch]$Clock = $null, [double]$BudgetMs = 0, [int]$CountBeyond = 1) {
    # The raw events of one log of the catalogue with StartUtc <= time (<= EndUtc): one reader per log name with at
    # most Max records (oldest first with -Oldest, else newest first) and up to CountBeyond more only counted, merged
    # in that order and cut to Max: @{ Events; More (more were there); Dropped (how many were not kept, counted up to
    # CountBeyond per log name); Failed (a log name could not be read); BudgetHit }. No matching event is an
    # empty result. A log name whose reader cannot be opened, or whose read ended after 3 failures in a row, is queued
    # once (Add-WorkerPerfLogError); skipped records and unformattable messages are counted per log.
    $counter = Get-WorkerPerfEventCounter $Log.Id
    $all = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $failed = $false
    $budgetHit = $false
    $beyondTotal = 0
    foreach ($q in @($Log.Queries)) {
        $xml = New-WorkerPerfEventQueryXml $q $StartUtc $EndUtc
        $reader = $null
        try { $reader = Open-WorkerPerfEventReader $xml ([bool]$Oldest) }
        catch {
            Add-WorkerPerfLogError $Source $Log.Id $q.LogName (Get-WorkerPerfErrorClass $_.Exception) (Get-WorkerPerfErrorText $_.Exception)
            $failed = $true
            continue
        }
        try { $part = Read-WorkerPerfEventRecords $reader $Max $Clock $BudgetMs $CountBeyond }
        finally { try { $reader.Dispose() } catch { $null = $_ } }
        $counter.SkippedRecords += $part.Skipped
        $counter.UnformattedMessages += $part.Unformatted
        if ($part.Failed) { Add-WorkerPerfLogError $Source $Log.Id $q.LogName $part.Class $part.Text; $failed = $true }
        if ($part.BudgetHit) { $budgetHit = $true }
        $beyondTotal += $part.Beyond
        foreach ($ev in $part.Records) {
            if ($null -eq $ev.TimeCreated) { continue }
            # a guard: an event that two selects of the query name is taken once
            if ($null -ne $ev.RecordId) {
                $k = [string]$q.LogName + '|' + [string]$ev.RecordId
                if ($seen.ContainsKey($k)) { continue }
                $seen[$k] = $true
            }
            $all.Add($ev)
        }
        if ($budgetHit) { break }
    }
    $sorted = @($all.ToArray() | Sort-Object -Property @{ Expression = { ConvertTo-WorkerPerfUtcTime ([datetime]$_.TimeCreated) }; Descending = (-not $Oldest) })
    $dropped = $beyondTotal
    if ($sorted.Count -gt $Max) { $dropped += $sorted.Count - $Max; $sorted = @($sorted[0..($Max - 1)]) }
    return @{ Events = $sorted; More = ($dropped -gt 0); Dropped = $dropped; Failed = $failed; BudgetHit = $budgetHit }
}

function Get-WorkerPerfEventCounts {
    # Per log of the catalogue: records skipped because they could not be read, messages that could not be formatted,
    # and events of a regular read that the cap of 200 did not keep, counted up to 1000 per read, so at least that many
    # (numbers only, for EventReadCounts in meta.json). A copy, built key by key.
    $st = $script:WinState
    $out = [ordered]@{}
    if ($null -eq $st) { return $out }
    foreach ($k in @($st.EventCounts.Keys)) {
        $copy = [ordered]@{}
        foreach ($c in @($st.EventCounts[$k].Keys)) { $copy[$c] = $st.EventCounts[$k][$c] }
        $out[$k] = $copy
    }
    return $out
}

function Receive-WorkerPerfSourceErrors {
    # The failures of the source's calls that did not stop the call (a log that could not be read), once each, since the
    # last call: @{ Source ('events.<log id>', 'eventsbefore.<log id>'); Message }.
    $st = $script:WinState
    if ($null -eq $st) { return }
    $list = $st.LogErrors.ToArray()
    $st.LogErrors.Clear()
    foreach ($e in $list) { $e }
}

function Get-WorkerPerfEvents {
    param([datetime]$Since)
    # Events of the catalogue in the logs found at the start with Since < Time <= now (compared in UTC), oldest first;
    # at most the oldest 200 per log and call: when more arrived since the last read, the newer ones of this window are
    # lost (one warning per log), so a flood never hides how it began.
    $st = $script:WinState
    if ($null -eq $st) { throw 'Die Windows-Datenquelle ist nicht initialisiert.' }
    if (-not (Test-WorkerPerfWinMeasured 'Ereignisse')) { return }
    $nowUtc = [datetime]::UtcNow
    $sinceUtc = ConvertTo-WorkerPerfUtcTime $Since
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($l in $st.Logs) {
        $r = Read-WorkerPerfWinLogEvents $l $sinceUtc $nowUtc $script:WorkerPerfWinMaxEvents -Oldest -Source 'events' -CountBeyond $script:WorkerPerfWinCountBeyond
        if ($r.More) {
            $counter = Get-WorkerPerfEventCounter $l.Id
            $counter.DroppedEvents += $r.Dropped
            Write-WarningOnce ('events.dropped:' + $l.Id) ("Ereignisprotokoll '{0}': mehr als {1} Ereignisse seit dem letzten Abruf, die neueren fehlen in events.csv; ihre Zahl steht in meta.json (EventReadCounts) und im Bericht." -f ($l.Names -join ', '), $script:WorkerPerfWinMaxEvents)
        }
        foreach ($ev in $r.Events) {
            $u = ConvertTo-WorkerPerfUtcTime ([datetime]$ev.TimeCreated)
            if ($u -le $sinceUtc -or $u -gt $nowUtc) { continue }
            $rec = ConvertTo-WorkerPerfWinEventRecord $st.EventConfig $l.Id $ev
            if ($null -ne $rec) { $rows.Add($rec) }
        }
    }
    $rows.ToArray() | Sort-Object -Property @{ Expression = { ConvertTo-WorkerPerfUtcTime $_.Time } }
}

function Get-WorkerPerfEventsBefore {
    # The lookback: events of the catalogue in the logs with lookback from Until - Days to Until, at most the newest
    # 2000 per log (newest first: the days next to the capture matter most). A log goes to Capped (by its id) when it
    # reached that cap, when one of its log names could not be read, or when the time budget of the lookback ran out
    # before it was read to the end. Returns @{ Events (oldest first); Capped }.
    param([int]$Days, [datetime]$Until)
    $st = $script:WinState
    if ($null -eq $st) { throw 'Die Windows-Datenquelle ist nicht initialisiert.' }
    $events = New-Object System.Collections.Generic.List[object]
    $capped = New-Object System.Collections.Generic.List[string]
    if ($Days -le 0 -or -not (Test-WorkerPerfWinMeasured 'Rueckblick')) { return @{ Events = @(); Capped = @() } }
    $untilUtc = ConvertTo-WorkerPerfUtcTime $Until
    $fromUtc = $untilUtc.AddDays(-$Days)
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $budgetMs = [double]$script:WorkerPerfWinLookbackBudgetSec * 1000
    foreach ($l in $st.Logs) {
        if (-not $l.Lookback) { continue }
        if ($clock.ElapsedMilliseconds -ge $budgetMs) { $capped.Add($l.Id); continue }
        # the lookback reads every log name that exists, also one that is switched off (M14)
        $lb = @{ Id = $l.Id; Names = $l.LookbackNames; Queries = $l.LookbackQueries }
        $r = Read-WorkerPerfWinLogEvents $lb $fromUtc $untilUtc $script:WorkerPerfWinLookbackMax -Source 'eventsbefore' -Clock $clock -BudgetMs $budgetMs
        if ($r.More -or $r.Failed -or $r.BudgetHit) { $capped.Add($l.Id) }
        foreach ($ev in $r.Events) {
            if ($clock.ElapsedMilliseconds -ge $budgetMs) {
                if (-not $capped.Contains($l.Id)) { $capped.Add($l.Id) }
                break
            }
            $u = ConvertTo-WorkerPerfUtcTime ([datetime]$ev.TimeCreated)
            if ($u -le $fromUtc -or $u -gt $untilUtc) { continue }
            $rec = ConvertTo-WorkerPerfWinEventRecord $st.EventConfig $l.Id $ev
            if ($null -ne $rec) { $events.Add($rec) }
        }
    }
    $sorted = @($events.ToArray() | Sort-Object -Property @{ Expression = { ConvertTo-WorkerPerfUtcTime $_.Time } })
    return @{ Events = $sorted; Capped = $capped.ToArray() }
}

function Get-WorkerPerfPrintDrivers {
    # The printer drivers (MSFT_PrinterDriver) with their effective isolation; no output when the class was missing at
    # the start. The isolation settings are read once per call; an unreadable one leaves the isolation to the others.
    $st = $script:WinState
    if ($null -eq $st) { throw 'Die Windows-Datenquelle ist nicht initialisiert.' }
    if (-not $st.PrintDrivers) { return }
    $drivers = @(Get-CimInstance -Namespace $script:WorkerPerfWinDriverNamespace -ClassName $script:WorkerPerfWinDriverClass `
            -OperationTimeoutSec $script:WorkerPerfWinCimTimeoutSec -ErrorAction Stop)
    $groups = $null
    try { $groups = @(Get-WorkerPerfPrintIsolationGroups) }
    catch { Write-WarningOnce 'print.groups' "PrintDriverIsolationGroups nicht lesbar: $($_.Exception.Message)" }
    $map = ConvertFrom-WorkerPerfIsolationGroups ((@($groups) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ }) -join '\\')
    $policy = @{}
    try { $p = Get-WorkerPerfPrintIsolationPolicy; if ($null -ne $p) { $policy = $p } }
    catch { Write-WarningOnce 'print.policy' "Richtlinien der Treiberisolierung nicht lesbar: $($_.Exception.Message)" }
    foreach ($d in $drivers) {
        if ($null -eq $d) { continue }
        $attribute = $null
        try { $attribute = Get-WorkerPerfPrintDriverAttribute $d } catch { $attribute = $null }
        ConvertTo-WorkerPerfPrintDriver $d $map $attribute $policy
    }
}

function Get-WorkerPerfPrintQueues {
    # The raw values of the queue counters (Jobs, Job Errors, Not Ready Errors) per queue, without _Total; no output when
    # the category was missing at the start.
    $st = $script:WinState
    if ($null -eq $st) { throw 'Die Windows-Datenquelle ist nicht initialisiert.' }
    if ($null -eq $st.PrintQueue) { return }
    $current = Read-WorkerPerfWinCategory $st.PrintQueue
    ConvertTo-WorkerPerfPrintQueueRows (Get-WorkerPerfWinInstantValues -Current $current -Counters $script:WorkerPerfWinPrintQueueCounters)
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

#region ---------- health picture (read once before the first tick, within a time budget) ----------------------------
# A reader per area sets each value of its area through Set-WorkerPerfWinHealthValue. The scriptblocks a reader passes
# run inside that function and see the reader's variables; the helpers below therefore name their own variables with
# a prefix (sv, sh, fr, hc), so that they never hide a variable of a reader.

function Test-WorkerPerfWinHealthTimeUp($Ctx) {
    return ($Ctx.Clock.Elapsed.TotalMilliseconds -ge $Ctx.BudgetMs)
}

function Get-WorkerPerfWinHealthFailReason($Ctx, $ErrorRecord) {
    # rights, timeout or error for a failed read: rights for denied access in each form Windows reports it, else
    # timeout when the limit of the area is reached, else error. A failure that Get-WorkerPerfWinHealthShared passes on
    # keeps the reason it got where it fell.
    $frEx = $ErrorRecord
    if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) { $frEx = $ErrorRecord.Exception }
    if ($null -ne $Ctx.Shared) {
        foreach ($frEntry in @($Ctx.Shared.Values)) {
            if ($null -ne $frEntry -and $null -ne $frEntry.Exception -and [object]::ReferenceEquals($frEntry.Exception, $frEx)) { return $frEntry.Reason }
        }
    }
    # without the wrappers PowerShell puts around a method that threw (as Get-WorkerPerfErrorClass)
    $frGuard = 0
    while ($null -ne $frEx -and $null -ne $frEx.InnerException -and $frGuard -lt 5 -and
        ($frEx -is [System.Management.Automation.MethodException] -or $frEx.GetType() -eq [System.Management.Automation.RuntimeException])) { $frEx = $frEx.InnerException; $frGuard++ }
    if ($null -ne $frEx) {
        if ($frEx -is [System.UnauthorizedAccessException] -or $frEx -is [System.Security.SecurityException]) { return 'rights' }
        if ($script:WorkerPerfWinDeniedHResults -contains [int]$frEx.HResult) { return 'rights' }
        if ($frEx -is [System.ComponentModel.Win32Exception] -and $frEx.NativeErrorCode -eq 5) { return 'rights' }
        # a CimException reports denied access in NativeErrorCode
        $frCode = $frEx.PSObject.Properties['NativeErrorCode']
        if ($null -ne $frCode -and [string]$frCode.Value -eq 'AccessDenied') { return 'rights' }
    }
    if (Test-WorkerPerfWinHealthTimeUp $Ctx) { return 'timeout' }
    return 'error'
}

function Set-WorkerPerfWinHealthValue($Ctx, [string]$Id, [scriptblock]$Read) {
    # Reads one value into $Ctx.Values, unless the limit of the area is reached (then unreadable/timeout). A single
    # result that is a value record of New-WorkerPerfHealthValue is taken as it is; else a list value is read with all
    # results (none: an empty list), any other value is absent without a result and read with one. $null results are
    # dropped. A failure makes the value unreadable with its reason.
    $svDef = $script:WorkerPerfHealthValues[$Id]
    if ($null -eq $svDef) { throw "Zustandsbild: unbekannter Wert '$Id'." }
    if (Test-WorkerPerfWinHealthTimeUp $Ctx) { $Ctx.Values[$Id] = New-WorkerPerfHealthValue 'unreadable' 'timeout'; return }
    $svResults = $null
    try { $svResults = @(& $Read | Where-Object { $null -ne $_ }) }
    catch [System.Management.Automation.PipelineStoppedException] { throw }
    catch {
        $Ctx.Values[$Id] = New-WorkerPerfHealthValue 'unreadable' (Get-WorkerPerfWinHealthFailReason $Ctx $_)
        return
    }
    if ($svResults.Count -eq 1 -and $svResults[0] -is [System.Collections.Specialized.OrderedDictionary] -and $svResults[0].Count -eq 3 -and
        $svResults[0].Contains('State') -and $svResults[0].Contains('Reason') -and $svResults[0].Contains('Value')) {
        $Ctx.Values[$Id] = $svResults[0]
        return
    }
    if ($svDef.Type -eq 'list') { $Ctx.Values[$Id] = New-WorkerPerfHealthValue 'read' '' ([object[]]$svResults); return }
    switch ($svResults.Count) {
        0 { $Ctx.Values[$Id] = New-WorkerPerfHealthValue 'absent' }
        1 { $Ctx.Values[$Id] = New-WorkerPerfHealthValue 'read' '' $svResults[0] }
        default { $Ctx.Values[$Id] = New-WorkerPerfHealthValue 'unreadable' 'error' }   # a reader that gives several results for one value
    }
}

function Get-WorkerPerfWinHealthShared($Ctx, [string]$Key, [scriptblock]$Read) {
    # Runs $Read once per call of Get-WorkerPerfHealth and gives every later caller the same result (plain pipeline
    # output). A failure is remembered with its reason and its area and thrown again to a later caller in the same area,
    # and to one in another area unless the reason is timeout: then $Read runs again within that area's own limit.
    $shEntry = $null
    if ($Ctx.Shared.ContainsKey($Key)) { $shEntry = $Ctx.Shared[$Key] }
    if ($null -ne $shEntry) {
        if ($null -eq $shEntry.Exception) { $shEntry.Result; return }
        if ($shEntry.Area -ceq $Ctx.Area -or $shEntry.Reason -ne 'timeout') { throw $shEntry.Error }
    }
    $shResult = $null
    try { $shResult = @(& $Read) }
    catch [System.Management.Automation.PipelineStoppedException] { throw }
    catch {
        $Ctx.Shared[$Key] = @{ Area = $Ctx.Area; Error = $_; Exception = $_.Exception; Reason = (Get-WorkerPerfWinHealthFailReason $Ctx $_); Result = $null }
        throw
    }
    $Ctx.Shared[$Key] = @{ Area = $Ctx.Area; Error = $null; Exception = $null; Reason = ''; Result = $shResult }
    $shResult
}

function Get-WorkerPerfWinHealthCim($Ctx, [string]$ClassName, [string]$Namespace = 'root\cimv2', [string]$Filter = '', [string[]]$Property = @()) {
    # A local CIM query with the rest of the area's limit as its time limit (whole seconds, at least 1).
    $hcRest = [Math]::Max(1, [int][Math]::Floor(($Ctx.BudgetMs - $Ctx.Clock.Elapsed.TotalMilliseconds) / 1000.0))
    $hcArgs = @{ ClassName = $ClassName; Namespace = $Namespace; OperationTimeoutSec = $hcRest; ErrorAction = 'Stop' }
    if ($Filter) { $hcArgs['Filter'] = $Filter }
    if (@($Property).Count -gt 0) { $hcArgs['Property'] = [string[]]$Property }
    Get-CimInstance @hcArgs
}

function Get-WorkerPerfWinHealthLog($Ctx, [string]$Name) {
    # The object of Get-WinEvent -ListLog for a log: kept from Initialize-WorkerPerfSource, else read now. $null only
    # when the log does not exist; any other failure is thrown.
    $hcState = $Ctx.State
    if ($null -ne $hcState -and $null -ne $hcState.LogInfo -and $hcState.LogInfo.ContainsKey($Name)) { return $hcState.LogInfo[$Name] }
    try { return (Get-WinEvent -ListLog $Name -ErrorAction Stop) }
    catch {
        if ([string]$_.FullyQualifiedErrorId -like 'NoMatchingLogsFound*') { return $null }
        if ($null -ne $_.Exception -and $_.Exception.GetType().FullName -eq 'System.Diagnostics.Eventing.Reader.EventLogNotFoundException') { return $null }
        throw
    }
}

# The shared queries of the areas (one per call of Get-WorkerPerfHealth); each gives plain pipeline output.
function Get-WorkerPerfWinHealthServices($Ctx) {
    Get-WorkerPerfWinHealthShared $Ctx 'services' { Get-WorkerPerfWinHealthCim $Ctx 'Win32_Service' -Property Name, DisplayName, State, StartMode, PathName }
}

function Get-WorkerPerfWinHealthUninstall($Ctx) {
    # The entries of both uninstall keys: Key, DisplayName, DisplayVersion.
    Get-WorkerPerfWinHealthShared $Ctx 'uninstall' {
        foreach ($hcRoot in $script:WorkerPerfWinUninstallKeys) {
            $hcKey = Get-WorkerPerfRegistryValues $hcRoot
            if ($null -eq $hcKey) { continue }
            foreach ($hcSub in @($hcKey['SubKeys'])) {
                $hcEntry = Get-WorkerPerfRegistryValues ($hcRoot + '\' + $hcSub)
                if ($null -eq $hcEntry) { continue }
                $hcValues = $hcEntry['Values']
                [pscustomobject]@{ Key = [string]$hcSub; DisplayName = [string]$hcValues['DisplayName']; DisplayVersion = [string]$hcValues['DisplayVersion'] }
            }
        }
    }
}

function Get-WorkerPerfWinHealthPagefiles($Ctx) {
    Get-WorkerPerfWinHealthShared $Ctx 'pagefiles' { Get-WorkerPerfWinHealthCim $Ctx 'Win32_PageFileUsage' -Property Name, AllocatedBaseSize, PeakUsage, TempPageFile }
}

function Get-WorkerPerfWinHealthSystemDrivers($Ctx) {
    # The system drivers the areas read (each reader picks its driver by name).
    Get-WorkerPerfWinHealthShared $Ctx 'systemdrivers' {
        Get-WorkerPerfWinHealthCim $Ctx 'Win32_SystemDriver' -Filter "Name = 'vmmemctl' OR Name = 'mrxsmb10'" -Property Name, State, StartMode
    }
}

function ConvertTo-WorkerPerfWinHealthNumber($Value, [double]$Divisor = 1, [int]$Decimals = 0) {
    # A number for health.json, rounded; nothing for $null (the value is then absent).
    if ($null -eq $Value) { return }
    return [Math]::Round([double]$Value / $Divisor, $Decimals)
}

function ConvertTo-WorkerPerfWinHealthBool($Value) {
    if ($null -eq $Value) { return }
    return [bool]$Value
}

function Read-WorkerPerfWinHealthSize($Ctx) {
    $cs = $Ctx.State.ComputerSystem
    Set-WorkerPerfWinHealthValue $Ctx 'size.cpuLogical' { ConvertTo-WorkerPerfWinHealthNumber (Get-WorkerPerfField $cs 'NumberOfLogicalProcessors') }
    Set-WorkerPerfWinHealthValue $Ctx 'size.cpuSockets' { ConvertTo-WorkerPerfWinHealthNumber (Get-WorkerPerfField $cs 'NumberOfProcessors') }
    Set-WorkerPerfWinHealthValue $Ctx 'size.memTotalMB' { ConvertTo-WorkerPerfWinHealthNumber (Get-WorkerPerfField $cs 'TotalPhysicalMemory') 1048576 }
    $commit = { param([string]$Field) ConvertTo-WorkerPerfWinHealthNumber (@(Get-WorkerPerfWinHealthShared $Ctx 'perfinfo' { Get-WorkerPerfPerformanceInfo })[0][$Field]) }
    Set-WorkerPerfWinHealthValue $Ctx 'size.commitTotalMB' { & $commit 'CommitTotalMB' }
    Set-WorkerPerfWinHealthValue $Ctx 'size.commitLimitMB' { & $commit 'CommitLimitMB' }
    Set-WorkerPerfWinHealthValue $Ctx 'size.commitPeakMB' { & $commit 'CommitPeakMB' }
    Set-WorkerPerfWinHealthValue $Ctx 'size.pagefiles' {
        foreach ($pf in @(Get-WorkerPerfWinHealthPagefiles $Ctx)) {
            [ordered]@{ Path = [string](Get-WorkerPerfField $pf 'Name'); AllocatedMB = (ConvertTo-WorkerPerfWinHealthNumber (Get-WorkerPerfField $pf 'AllocatedBaseSize'))
                PeakUsageMB = (ConvertTo-WorkerPerfWinHealthNumber (Get-WorkerPerfField $pf 'PeakUsage')); Temporary = (ConvertTo-WorkerPerfWinHealthBool (Get-WorkerPerfField $pf 'TempPageFile')) }
        }
    }
    Set-WorkerPerfWinHealthValue $Ctx 'size.pagefileManaged' { ConvertTo-WorkerPerfWinHealthBool (Get-WorkerPerfField $cs 'AutomaticManagedPagefile') }
    Set-WorkerPerfWinHealthValue $Ctx 'size.hypervisor' { ConvertTo-WorkerPerfWinHealthBool (Get-WorkerPerfField $cs 'HypervisorPresent') }
    Set-WorkerPerfWinHealthValue $Ctx 'size.model' {
        $model = ('{0} {1}' -f [string](Get-WorkerPerfField $cs 'Manufacturer'), [string](Get-WorkerPerfField $cs 'Model')).Trim()
        if ($model) { $model }
    }
    Set-WorkerPerfWinHealthValue $Ctx 'size.vmtoolsPresent' { $null -ne (Get-WorkerPerfRegistryValues 'SOFTWARE\VMware, Inc.\VMware Tools') }
    Set-WorkerPerfWinHealthValue $Ctx 'size.vmtoolsService' {
        $svc = @(Get-WorkerPerfWinHealthServices $Ctx | Where-Object { [string](Get-WorkerPerfField $_ 'Name') -eq 'VMTools' })
        if ($svc.Count -eq 0) { New-WorkerPerfHealthValue 'absent' 'notInstalled' } else { [string](Get-WorkerPerfField $svc[0] 'State') }
    }
    Set-WorkerPerfWinHealthValue $Ctx 'size.vmtoolsVersion' {
        $entry = @(Get-WorkerPerfWinHealthUninstall $Ctx | Where-Object { $_.DisplayName -eq 'VMware Tools' })
        if ($entry.Count -eq 0) { New-WorkerPerfHealthValue 'absent' 'notInstalled' } else { $entry[0].DisplayVersion }
    }
    Set-WorkerPerfWinHealthValue $Ctx 'size.netAdapters' {
        foreach ($na in @(Get-WorkerPerfWinHealthCim $Ctx 'Win32_NetworkAdapter' -Filter 'PhysicalAdapter = TRUE' -Property Name, ServiceName, Speed, NetEnabled)) {
            [ordered]@{ Name = [string](Get-WorkerPerfField $na 'Name'); Service = [string](Get-WorkerPerfField $na 'ServiceName')
                SpeedMbit = (ConvertTo-WorkerPerfWinHealthNumber (Get-WorkerPerfField $na 'Speed') 1000000 1); Enabled = (ConvertTo-WorkerPerfWinHealthBool (Get-WorkerPerfField $na 'NetEnabled')) }
        }
    }
    Set-WorkerPerfWinHealthValue $Ctx 'size.storageControllers' {
        foreach ($sc in @(Get-WorkerPerfWinHealthCim $Ctx 'Win32_SCSIController' -Property Name, DriverName)) {
            [ordered]@{ Name = [string](Get-WorkerPerfField $sc 'Name'); Driver = [string](Get-WorkerPerfField $sc 'DriverName') }
        }
    }
    Set-WorkerPerfWinHealthValue $Ctx 'size.balloonDriver' {
        $drv = @(Get-WorkerPerfWinHealthSystemDrivers $Ctx | Where-Object { [string](Get-WorkerPerfField $_ 'Name') -eq 'vmmemctl' })
        if ($drv.Count -eq 0) { New-WorkerPerfHealthValue 'absent' 'notInstalled' } else { [string](Get-WorkerPerfField $drv[0] 'State') }
    }
}

function Read-WorkerPerfWinHealthOperation($Ctx) {
    $os = $Ctx.State.OperatingSystem
    Set-WorkerPerfWinHealthValue $Ctx 'operation.lastBoot' {
        $boot = Get-WorkerPerfField $os 'LastBootUpTime'
        if ($boot -is [datetime]) { ConvertTo-WorkerPerfHealthTime $boot }
    }
    Set-WorkerPerfWinHealthValue $Ctx 'operation.pendingRename' {
        # pairs of source and target; the paths are not kept. An odd count (a list that ends in an empty target) still
        # counts its last pair.
        $sm = Get-WorkerPerfRegistryValues 'SYSTEM\CurrentControlSet\Control\Session Manager'
        $entries = 0
        if ($null -ne $sm -and $sm['Values'].Contains('PendingFileRenameOperations')) { $entries = @($sm['Values']['PendingFileRenameOperations']).Count }
        [Math]::Ceiling($entries / 2.0)
    }
    Set-WorkerPerfWinHealthValue $Ctx 'operation.pendingServicing' {
        $null -ne (Get-WorkerPerfRegistryValues 'SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
    }
    Set-WorkerPerfWinHealthValue $Ctx 'operation.pendingUpdate' {
        $null -ne (Get-WorkerPerfRegistryValues 'SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    }
    $latest = { Select-WorkerPerfLatestHotFix @(Get-WorkerPerfWinHealthShared $Ctx 'hotfixes' { Get-WorkerPerfWinHealthCim $Ctx 'Win32_QuickFixEngineering' -Property HotFixID, InstalledOn }) }
    Set-WorkerPerfWinHealthValue $Ctx 'operation.lastUpdate' { $hf = & $latest; if ($null -ne $hf) { ConvertTo-WorkerPerfHealthTime $hf.InstalledOn } }
    Set-WorkerPerfWinHealthValue $Ctx 'operation.lastUpdateId' { $hf = & $latest; if ($null -ne $hf) { $hf.Id } }
    Set-WorkerPerfWinHealthValue $Ctx 'operation.powerPlan' { ConvertTo-WorkerPerfPowerPlan (Get-WorkerPerfActivePowerScheme) }
    Set-WorkerPerfWinHealthValue $Ctx 'operation.volumes' {
        # the drives first; without the list of page files the value stays read and PageFile is unknown
        $disks = @(Get-WorkerPerfWinHealthCim $Ctx 'Win32_LogicalDisk' -Filter 'DriveType = 3' -Property DeviceID, Size, FreeSpace, FileSystem)
        $pfPaths = $null
        try { $pfPaths = @(@(Get-WorkerPerfWinHealthPagefiles $Ctx) | ForEach-Object { [string](Get-WorkerPerfField $_ 'Name') }) }
        catch [System.Management.Automation.PipelineStoppedException] { throw }
        catch { $pfPaths = $null }
        $systemDrive = [string](Get-WorkerPerfField $os 'SystemDrive')
        foreach ($disk in $disks) {
            $drive = [string](Get-WorkerPerfField $disk 'DeviceID')
            $onDrive = $null
            if ($null -ne $pfPaths) { $onDrive = (@($pfPaths | Where-Object { $drive -and $_.StartsWith($drive, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) }
            [ordered]@{ Drive = $drive; SizeGB = (ConvertTo-WorkerPerfWinHealthNumber (Get-WorkerPerfField $disk 'Size') 1073741824 1)
                FreeGB = (ConvertTo-WorkerPerfWinHealthNumber (Get-WorkerPerfField $disk 'FreeSpace') 1073741824 1)
                FileSystem = [string](Get-WorkerPerfField $disk 'FileSystem'); System = ($systemDrive -ne '' -and $drive -eq $systemDrive); PageFile = $onDrive }
        }
    }
}

function Read-WorkerPerfWinHealthEvents($Ctx) {
    Set-WorkerPerfWinHealthValue $Ctx 'events.logs' {
        # every log name the event catalogue reads; a missing log has Present false and empty fields
        foreach ($evLog in @(Get-WorkerPerfEventReadLogs $Ctx.State.EventConfig)) {
            foreach ($evName in @($evLog.Names)) {
                $evInfo = Get-WorkerPerfWinHealthLog $Ctx ([string]$evName)
                $evItem = [ordered]@{ Log = [string]$evName; Present = ($null -ne $evInfo) }
                $evState = ConvertTo-WorkerPerfLogInfo $evInfo
                foreach ($k in @($evState.Keys)) { $evItem[$k] = $evState[$k] }
                $evItem['Oldest'] = $null
                if ($null -ne $evInfo) {
                    $oldest = Get-WorkerPerfLogOldestTime ([string]$evName)
                    if ($oldest -is [datetime]) { $evItem['Oldest'] = ConvertTo-WorkerPerfHealthTime $oldest }
                }
                $evItem
            }
        }
    }
}

function Get-WorkerPerfHealth {
    # The health picture (New-WorkerPerfHealth), read area by area in fixed order within the time budget; $null without
    # a Windows call when -Skip left out Zustand. A reader that throws keeps the values it set; the area then carries
    # the message of the exception.
    $st = $script:WinState
    if ($null -eq $st) { throw 'Die Windows-Datenquelle ist nicht initialisiert.' }
    if (-not (Test-WorkerPerfWinMeasured 'Zustand')) { return $null }
    $total = [System.Diagnostics.Stopwatch]::StartNew()
    $totalMs = [double]$script:WorkerPerfWinHealthTotalBudgetSec * 1000
    $shared = @{}
    $areas = [ordered]@{}
    foreach ($area in $script:WorkerPerfHealthAreas) {
        $restMs = $totalMs - $total.Elapsed.TotalMilliseconds
        if ($restMs -le 0) { $areas[$area] = Complete-WorkerPerfHealthArea $area @{} 0 'budget' $true; continue }
        $readers = $script:WorkerPerfWinHealthReaders
        if (-not $readers.Contains($area)) { $areas[$area] = Complete-WorkerPerfHealthArea $area @{} 0 'noReader'; continue }
        $ctx = @{ Area = $area; State = $st; Clock = [System.Diagnostics.Stopwatch]::StartNew()
            BudgetMs = [Math]::Min([double]$script:WorkerPerfWinHealthAreaBudgetSec * 1000, $restMs); Shared = $shared; Values = [ordered]@{} }
        $errorText = ''
        try { $null = & ([string]$readers[$area]) $ctx }
        catch [System.Management.Automation.PipelineStoppedException] { throw }
        catch { $errorText = Get-WorkerPerfErrorText $_.Exception }
        $ms = $ctx.Clock.Elapsed.TotalMilliseconds
        $areas[$area] = Complete-WorkerPerfHealthArea $area $ctx.Values ([Math]::Round($ms)) $errorText ($ms -ge $ctx.BudgetMs)
    }
    return (New-WorkerPerfHealth (Get-WorkerPerfNow) ([Math]::Round($total.Elapsed.TotalMilliseconds)) $areas)
}

#endregion
