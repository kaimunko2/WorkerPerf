#Requires -Version 5.1
<#
.SYNOPSIS
    Records performance and resource usage of a Citrix multi-session VDA (terminal server worker)
    down to individual sessions and processes.

.DESCRIPTION
    Takes a snapshot every -IntervalSeconds and writes compact CSV files into a new run folder:

      meta.json      host facts and capture settings
      system.csv     one row per sample: CPU, memory, disk, network, session count
      sessions.csv   one row per sample and session: user, state, client, idle time
      procinfo.csv   one row per process instance: name, session, path, start time
      processes.csv  one row per sample and process: CPU ms, memory, I/O deltas
      citrix.csv     optional ICA/EUEM metrics per session (round trip time, latency, ...)

    All data sources are language neutral (CIM raw classes and the WTS API), so the script
    works on German and English Windows alike. No modules or installations are required.
    Run it elevated (or as SYSTEM via a scheduled task) so that all processes are visible.

    Stop the capture with Ctrl+C, by -DurationMinutes, or by creating a file named
    'stop.flag' inside the run folder.

    Analyse the result with New-WorkerPerfReport.ps1.

.PARAMETER OutputPath
    Base folder. A sub folder <COMPUTER>_<yyyyMMdd-HHmmss> is created per capture.

.PARAMETER IntervalSeconds
    Sample interval. 15 s is a good default for full working days; use 5 s for short,
    detailed captures. Processes that start and end between two samples are not seen.

.PARAMETER DurationMinutes
    Stop automatically after this time. 0 = run until stopped.

.PARAMETER IncludeCommandLine
    Also store process command lines (may contain sensitive data such as file names or URLs).

.PARAMETER NoCitrix
    Skip the Citrix ICA/EUEM WMI metrics.

.PARAMETER CitrixMetricFilter
    Regular expression selecting which numeric Citrix WMI properties are recorded.

.PARAMETER Simulate
    Generate synthetic data instead of reading the local system (no waiting between samples).
    Used for demos and for testing the report on any platform.

.EXAMPLE
    .\Start-WorkerPerfCapture.ps1 -OutputPath D:\WorkerPerf -IntervalSeconds 15 -DurationMinutes 480

.EXAMPLE
    .\Start-WorkerPerfCapture.ps1 -Simulate -DurationMinutes 120 -OutputPath .\demo
#>
[CmdletBinding()]
param(
    [string]$OutputPath,
    [ValidateRange(1, 3600)][int]$IntervalSeconds = 15,
    [ValidateRange(0, 100000)][double]$DurationMinutes = 0,
    [switch]$IncludeCommandLine,
    [switch]$NoCitrix,
    [string]$CitrixMetricFilter = 'Latency|Round|Bandwidth|FramesPerSecond|Fps',
    [switch]$Simulate,
    [ValidateRange(1, 500)][int]$SimulateSessions = 25
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture

#region ---------- helpers ----------------------------------------------------------------

function Format-Num($Value, [int]$Decimals = 1) {
    if ($null -eq $Value) { return '' }
    return [Math]::Round([double]$Value, $Decimals).ToString($inv)
}

function Format-CsvText([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $t = $Text.Replace("`r", ' ').Replace("`n", ' ')
    if ($t.IndexOfAny([char[]]@(',', '"')) -ge 0) { return '"' + $t.Replace('"', '""') + '"' }
    return $t
}

function Get-Prop($Object, [string]$Name) {
    # Tolerant property read: returns $null when the property does not exist.
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Get-Rate($Current, $Previous, [double]$Seconds) {
    # Per-second rate of a cumulative counter; $null when unavailable or after a counter reset.
    if ($null -eq $Current -or $null -eq $Previous -or $Seconds -le 0) { return $null }
    $d = [double]$Current - [double]$Previous
    if ($d -lt 0) { return $null }
    return $d / $Seconds
}

#endregion

#region ---------- Windows data sources ---------------------------------------------------

$wtsSource = @'
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

$script:WarnedOnce = @{}
function Write-WarningOnce([string]$Key, [string]$Message) {
    if (-not $script:WarnedOnce.ContainsKey($Key)) {
        $script:WarnedOnce[$Key] = $true
        Write-Warning $Message
    }
}

function Get-CimSafe([string]$ClassName, [string]$Filter, [string]$Namespace = 'root\cimv2') {
    # Broken performance counters are common on long-lived servers; never let them abort a capture.
    try {
        $p = @{ ClassName = $ClassName; Namespace = $Namespace; ErrorAction = 'Stop' }
        if ($Filter) { $p.Filter = $Filter }
        return @(Get-CimInstance @p)
    }
    catch {
        Write-WarningOnce $ClassName "Datenquelle $ClassName nicht verfuegbar: $($_.Exception.Message)"
        return @()
    }
}

function Get-WinSystemRaw {
    $cpu = Get-CimSafe 'Win32_PerfRawData_PerfOS_Processor' "Name='_Total'" | Select-Object -First 1
    $mem = Get-CimSafe 'Win32_PerfRawData_PerfOS_Memory' | Select-Object -First 1
    $sys = Get-CimSafe 'Win32_PerfRawData_PerfOS_System' | Select-Object -First 1
    $dsk = Get-CimSafe 'Win32_PerfRawData_PerfDisk_PhysicalDisk' "Name='_Total'" | Select-Object -First 1
    $net = Get-CimSafe 'Win32_PerfRawData_Tcpip_NetworkInterface'

    $rx = $null; $tx = $null
    foreach ($n in $net) {
        $rx = [double]$rx + [double]$n.BytesReceivedPersec
        $tx = [double]$tx + [double]$n.BytesSentPersec
    }
    [pscustomobject]@{
        # PERF_100NSEC_TIMER_INV: the raw value counts idle time, busy% = 1 - delta(value)/delta(timestamp)
        CpuIdleCounter = Get-Prop $cpu 'PercentProcessorTime'
        CpuTimestamp   = Get-Prop $cpu 'Timestamp_Sys100NS'
        QueueLength    = Get-Prop $sys 'ProcessorQueueLength'
        AvailBytes     = Get-Prop $mem 'AvailableBytes'
        CommittedBytes = Get-Prop $mem 'CommittedBytes'
        CommitLimit    = Get-Prop $mem 'CommitLimit'
        PagesCum       = Get-Prop $mem 'PagesPersec'
        DiskRdBytesCum = Get-Prop $dsk 'DiskReadBytesPersec'
        DiskWrBytesCum = Get-Prop $dsk 'DiskWriteBytesPersec'
        DiskRdOpsCum   = Get-Prop $dsk 'DiskReadsPersec'
        DiskWrOpsCum   = Get-Prop $dsk 'DiskWritesPersec'
        DiskQueue      = Get-Prop $dsk 'CurrentDiskQueueLength'
        NetRxCum       = $rx
        NetTxCum       = $tx
    }
}

$script:ProcProps = @('ProcessId', 'ParentProcessId', 'Name', 'SessionId', 'KernelModeTime', 'UserModeTime',
    'WorkingSetSize', 'PrivatePageCount', 'ReadTransferCount', 'WriteTransferCount',
    'ReadOperationCount', 'WriteOperationCount', 'HandleCount', 'ThreadCount', 'CreationDate', 'ExecutablePath')
if ($IncludeCommandLine) { $script:ProcProps += 'CommandLine' }

function Get-WinProcessRaw {
    # PID 0 (Idle) is excluded: its "CPU time" is the idle time of the machine.
    return @(Get-CimInstance -ClassName Win32_Process -Property $script:ProcProps -Filter 'ProcessId <> 0')
}

function Get-WinSessionRaw {
    if (-not $script:WtsAvailable) { return @() }
    try { return @([WorkerPerf.Wts]::GetSessions()) }
    catch {
        Write-WarningOnce 'wts' "Sitzungsabfrage fehlgeschlagen: $($_.Exception.Message)"
        return @()
    }
}

function Initialize-CitrixSources {
    # Returns the list of Citrix WMI classes that exist on this machine.
    $found = @()
    $candidates = @(
        @{ Namespace = 'root\citrix\euem'; Pattern = 'Citrix_Euem_RoundTrip' },
        @{ Namespace = 'root\cimv2'; Pattern = 'Win32_PerfFormattedData_*ICASession*' }
    )
    foreach ($c in $candidates) {
        try {
            $classes = @(Get-CimClass -Namespace $c.Namespace -ClassName $c.Pattern -ErrorAction Stop)
            foreach ($cl in $classes) {
                $found += [pscustomobject]@{ Namespace = $c.Namespace; ClassName = $cl.CimClassName }
            }
        }
        catch { Write-Verbose "Citrix-Quelle $($c.Namespace):$($c.Pattern) nicht vorhanden." }
    }
    return $found
}

function Get-WinCitrixRaw {
    # Generic dump: every numeric property matching -CitrixMetricFilter becomes one metric row.
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($src in $script:CitrixSources) {
        foreach ($inst in (Get-CimSafe $src.ClassName $null $src.Namespace)) {
            $sid = $null
            foreach ($n in 'SessionID', 'SessionId') {
                $v = Get-Prop $inst $n
                if ($null -ne $v) { $sid = $v; break }
            }
            $name = [string](Get-Prop $inst 'Name')
            foreach ($p in $inst.CimInstanceProperties) {
                if ($p.Name -notmatch $CitrixMetricFilter) { continue }
                if ($null -eq $p.Value -or $p.Value -isnot [ValueType] -or $p.Value -is [bool] -or $p.Value -is [datetime]) { continue }
                $rows.Add([pscustomobject]@{ Source = $src.ClassName; SessionId = $sid; Instance = $name; Metric = $p.Name; Value = [double]$p.Value })
            }
        }
    }
    return $rows
}

#endregion

#region ---------- simulated data source --------------------------------------------------

function Initialize-Simulation {
    $script:Rnd = New-Object System.Random 42
    $script:SimProcs = New-Object System.Collections.Generic.List[object]
    $script:SimSessions = New-Object System.Collections.Generic.List[object]
    $script:SimNextPid = 400
    $script:SimSys = @{ Pages = 0.0; DiskRd = 0.0; DiskWr = 0.0; DiskRdOps = 0.0; DiskWrOps = 0.0; NetRx = 0.0; NetTx = 0.0; Idle = 0.0; Ts = 0.0 }
    $script:SimCores = 8
    $script:SimRamBytes = 64GB

    # name, instances, cpu share of one core (average), working set MB, I/O KB/s
    $script:SimCatalog = @(
        @('explorer.exe', 1, 0.004, 95, 2), @('chrome.exe', 7, 0.035, 210, 40), @('msedge.exe', 5, 0.02, 180, 25),
        @('OUTLOOK.EXE', 1, 0.03, 340, 30), @('WINWORD.EXE', 1, 0.02, 190, 8), @('EXCEL.EXE', 1, 0.05, 260, 12),
        @('ms-teams.exe', 1, 0.07, 520, 35), @('msedgewebview2.exe', 5, 0.02, 150, 15), @('AcroRd32.exe', 1, 0.015, 170, 6),
        @('saplogon.exe', 1, 0.02, 230, 10), @('wfshell.exe', 1, 0.001, 18, 0), @('ctfmon.exe', 1, 0.001, 14, 0),
        @('OneDrive.exe', 1, 0.008, 110, 20), @('POWERPNT.EXE', 1, 0.02, 220, 6)
    )
    $system = @(
        @('System', 1, 0.05, 12, 150), @('svchost.exe', 40, 0.002, 22, 3), @('MsMpEng.exe', 1, 0.12, 310, 400),
        @('BrokerAgent.exe', 1, 0.01, 140, 5), @('CtxSvcHost.exe', 4, 0.004, 35, 1), @('lsass.exe', 1, 0.01, 45, 2),
        @('WmiPrvSE.exe', 3, 0.02, 40, 1), @('csrss.exe', 1, 0.003, 8, 0), @('services.exe', 1, 0.002, 11, 0),
        @('SearchIndexer.exe', 1, 0.03, 120, 80), @('spoolsv.exe', 1, 0.002, 25, 1)
    )
    foreach ($a in $system) { for ($i = 0; $i -lt $a[1]; $i++) { Add-SimProcess 0 $a $script:SimStart.AddDays(-3) } }
    $script:SimSessions.Add([pscustomobject]@{ SessionId = 0; State = 'Disconnected'; WinStation = 'Services'; User = ''; Domain = ''; ClientName = ''; LogonTime = [datetime]::MinValue; IdleSec = -1; Activity = 0.0 })

    $script:SimNextSession = 2
    $initial = [int]($SimulateSessions * 0.6)
    for ($i = 0; $i -lt $initial; $i++) { Add-SimSession $script:SimStart.AddMinutes(-$script:Rnd.Next(5, 240)) }
}

function Add-SimProcess([int]$SessionId, $App, [datetime]$Start) {
    $p = [pscustomobject]@{
        ProcessId = $script:SimNextPid; ParentProcessId = 4; Name = $App[0]; SessionId = $SessionId
        KernelModeTime = [uint64]0; UserModeTime = [uint64]0
        WorkingSetSize = [uint64]($App[3] * 1MB * (0.6 + $script:Rnd.NextDouble() * 0.8))
        PrivatePageCount = [uint64]0
        ReadTransferCount = [uint64]0; WriteTransferCount = [uint64]0
        ReadOperationCount = [uint64]0; WriteOperationCount = [uint64]0
        HandleCount = $script:Rnd.Next(150, 2500); ThreadCount = $script:Rnd.Next(4, 80)
        CreationDate = $Start
        ExecutablePath = "C:\Program Files\Sim\$($App[0])"
        CommandLine = "`"C:\Program Files\Sim\$($App[0])`" --simulated"
        SimCpu = [double]$App[2]; SimIo = [double]$App[4]; SimBaseWs = [double]($App[3] * 0.7MB)
        SimLeak = 0.0; SimHog = $false
    }
    $p.PrivatePageCount = [uint64]($p.WorkingSetSize * 1.25)
    $script:SimNextPid += 4
    $script:SimProcs.Add($p)
    return
}

function Add-SimSession([datetime]$Logon) {
    $id = $script:SimNextSession; $script:SimNextSession++
    $s = [pscustomobject]@{
        SessionId = $id; State = 'Active'; WinStation = "ICA-CGP#$id"; User = ('user{0:d3}' -f $id); Domain = 'CONTOSO'
        ClientName = ('WS-{0:d4}' -f $script:Rnd.Next(1, 9999)); LogonTime = $Logon; IdleSec = 0.0
        Activity = 0.3 + $script:Rnd.NextDouble() * 1.4
    }
    $script:SimSessions.Add($s)
    foreach ($a in $script:SimCatalog) {
        if ($a[0] -notin 'explorer.exe', 'wfshell.exe', 'ctfmon.exe' -and $script:Rnd.NextDouble() -gt 0.55) { continue }
        for ($i = 0; $i -lt $a[1]; $i++) { Add-SimProcess $id $a $Logon.AddSeconds($script:Rnd.Next(5, 600)) }
    }
    return
}

function Step-Simulation([double]$Seconds) {
    $now = $script:SimNow
    $userSessions = @($script:SimSessions | Where-Object { $_.SessionId -ne 0 })

    # logon / logoff churn
    if ($userSessions.Count -lt $SimulateSessions -and $script:Rnd.NextDouble() -lt 0.04) { Add-SimSession $now }
    if ($userSessions.Count -gt 3 -and $script:Rnd.NextDouble() -lt 0.006) {
        $victim = $userSessions[$script:Rnd.Next($userSessions.Count)]
        [void]$script:SimSessions.Remove($victim)
        foreach ($p in @($script:SimProcs | Where-Object { $_.SessionId -eq $victim.SessionId })) { [void]$script:SimProcs.Remove($p) }
    }

    $sessionActivity = @{ 0 = 1.0 }
    foreach ($s in $script:SimSessions) {
        if ($s.SessionId -eq 0) { continue }
        $r = $script:Rnd.NextDouble()
        if ($s.State -eq 'Active') {
            if ($r -lt 0.004) { $s.State = 'Disconnected'; $s.WinStation = '' }
            if ($script:Rnd.NextDouble() -lt 0.7) { $s.IdleSec = 0 } else { $s.IdleSec += $Seconds }
        }
        else {
            $s.IdleSec += $Seconds
            if ($r -lt 0.02) { $s.State = 'Active'; $s.WinStation = "ICA-CGP#$($s.SessionId)"; $s.IdleSec = 0 }
        }
        $sessionActivity[$s.SessionId] = $(if ($s.State -eq 'Active') { $s.Activity } else { 0.08 })
    }

    # one runaway process and one leaking process make the report interesting
    $elapsedMin = ($now - $script:SimStart).TotalMinutes
    if ($elapsedMin -gt 20 -and -not $script:SimHogDone) {
        $c = @($script:SimProcs | Where-Object { $_.Name -eq 'EXCEL.EXE' })
        if ($c.Count) { $c[0].SimHog = $true; $script:SimHogDone = $true }
    }
    if (-not $script:SimLeakDone) {
        $c = @($script:SimProcs | Where-Object { $_.Name -eq 'ms-teams.exe' })
        if ($c.Count) { $c[0].SimLeak = 0.35MB; $script:SimLeakDone = $true }
    }

    $busy100ns = 0.0; $ioBytes = 0.0
    $wave = 0.75 + 0.35 * [Math]::Sin($elapsedMin / 18.0)
    foreach ($p in $script:SimProcs) {
        $act = $sessionActivity[[int]$p.SessionId]
        if ($null -eq $act) { $act = 0.1 }
        $burst = $(if ($script:Rnd.NextDouble() -lt 0.05) { 4.0 + $script:Rnd.NextDouble() * 6 } else { $script:Rnd.NextDouble() * 1.6 })
        $share = 0.55 * $p.SimCpu * $act * $wave * $burst
        if ($p.SimHog -and $elapsedMin -lt 55) { $share = 0.9 + $script:Rnd.NextDouble() * 0.1 }
        if ($share -gt 1.5) { $share = 1.5 }
        $cpu = [uint64]($share * $Seconds * 1e7)
        $p.UserModeTime += [uint64]($cpu * 0.8)
        $p.KernelModeTime += [uint64]($cpu * 0.2)
        $busy100ns += $cpu
        $io = $p.SimIo * 1KB * $act * $burst * $Seconds
        $p.ReadTransferCount += [uint64]($io * 0.6); $p.WriteTransferCount += [uint64]($io * 0.4)
        $p.ReadOperationCount += [uint64]($io / 16KB); $p.WriteOperationCount += [uint64]($io / 32KB)
        $ioBytes += $io
        $ws = $p.SimBaseWs * (0.7 + 0.3 * $act) * (0.9 + $script:Rnd.NextDouble() * 0.2) + $p.SimLeak * $elapsedMin * 60
        $p.WorkingSetSize = [uint64]$ws
        $p.PrivatePageCount = [uint64]($ws * 1.25)
    }

    $s = $script:SimSys
    $capacity = $script:SimCores * $Seconds * 1e7
    if ($busy100ns -gt $capacity * 0.99) { $busy100ns = $capacity * 0.99 }
    $s.Ts += $Seconds * 1e7
    # the raw _Total counter is normalised to one processor
    $s.Idle += ($capacity - $busy100ns) / $script:SimCores
    $s.DiskRd += $ioBytes * 0.5; $s.DiskWr += $ioBytes * 0.3
    $s.DiskRdOps += $ioBytes / 32KB; $s.DiskWrOps += $ioBytes / 48KB
    $s.NetRx += $ioBytes * 0.15; $s.NetTx += $ioBytes * 0.25
    $s.Pages += $script:Rnd.Next(0, 400) * $Seconds
}

function Get-SimSystemRaw {
    $ws = 0.0
    foreach ($p in $script:SimProcs) { $ws += $p.WorkingSetSize }
    $s = $script:SimSys
    [pscustomobject]@{
        CpuIdleCounter = $s.Idle; CpuTimestamp = $s.Ts
        QueueLength = $script:Rnd.Next(0, 6)
        AvailBytes = [Math]::Max([double]1GB, [double]$script:SimRamBytes - $ws * 0.8 - 4GB)
        CommittedBytes = $ws * 1.25 + 5GB; CommitLimit = $script:SimRamBytes * 1.2
        PagesCum = $s.Pages
        DiskRdBytesCum = $s.DiskRd; DiskWrBytesCum = $s.DiskWr; DiskRdOpsCum = $s.DiskRdOps; DiskWrOpsCum = $s.DiskWrOps
        DiskQueue = $script:Rnd.Next(0, 3)
        NetRxCum = $s.NetRx; NetTxCum = $s.NetTx
    }
}

function Get-SimCitrixRaw {
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($s in $script:SimSessions) {
        if ($s.State -ne 'Active' -or $s.SessionId -eq 0) { continue }
        $base = 12 + ($s.SessionId * 7) % 60
        $rtt = $base + $script:Rnd.Next(0, 25)
        if ($script:Rnd.NextDouble() -lt 0.03) { $rtt += $script:Rnd.Next(100, 400) }
        $rows.Add([pscustomobject]@{ Source = 'Citrix_Euem_RoundTrip'; SessionId = $s.SessionId; Instance = ''; Metric = 'RoundtripTime'; Value = [double]$rtt })
        $rows.Add([pscustomobject]@{ Source = 'Citrix_Euem_RoundTrip'; SessionId = $s.SessionId; Instance = ''; Metric = 'NetworkLatency'; Value = [double][int]($rtt * 0.6) })
    }
    return $rows
}

#endregion

#region ---------- setup ------------------------------------------------------------------

$isWin = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
if (-not $Simulate -and -not $isWin) { throw 'Die Aufzeichnung realer Daten ist nur unter Windows moeglich. Fuer Testdaten -Simulate verwenden.' }

if (-not $OutputPath) {
    $OutputPath = $(if ($env:ProgramData) { Join-Path $env:ProgramData 'WorkerPerf' } else { Join-Path (Get-Location).Path 'WorkerPerfData' })
}

$script:SimStart = (Get-Date).AddMinutes(-1 * [Math]::Max($DurationMinutes, 1))
$script:SimNow = $script:SimStart
$script:SimHogDone = $false
$script:SimLeakDone = $false
$script:WtsAvailable = $false
$script:CitrixSources = @()

if ($Simulate) {
    if ($DurationMinutes -le 0) { throw '-Simulate erfordert -DurationMinutes.' }
    Initialize-Simulation
    $computer = 'SIM-VDA01'
    $cores = $script:SimCores
    $ramBytes = $script:SimRamBytes
    $osCaption = 'Simulated Windows Server 2022'
    $citrixEnabled = -not $NoCitrix
}
else {
    $principal = New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning 'Nicht mit erhoehten Rechten gestartet - Prozesse anderer Benutzer liefern ggf. unvollstaendige Daten.'
    }
    try { Add-Type -TypeDefinition $wtsSource -Language CSharp; $script:WtsAvailable = $true }
    catch { Write-Warning "WTS-API konnte nicht geladen werden, Sitzungen werden ohne Benutzernamen erfasst: $($_.Exception.Message)" }

    $cs = Get-CimInstance Win32_ComputerSystem
    $os = Get-CimInstance Win32_OperatingSystem
    $computer = $env:COMPUTERNAME
    $cores = [int]$cs.NumberOfLogicalProcessors
    $ramBytes = [double]$cs.TotalPhysicalMemory
    $osCaption = "$($os.Caption) ($($os.Version))"
    $citrixEnabled = $false
    if (-not $NoCitrix) {
        $script:CitrixSources = @(Initialize-CitrixSources)
        $citrixEnabled = $script:CitrixSources.Count -gt 0
        if (-not $citrixEnabled) { Write-Verbose 'Keine Citrix-WMI-Klassen gefunden - citrix.csv bleibt leer.' }
    }
}

function Get-Now { if ($Simulate) { return $script:SimNow } else { return Get-Date } }

$startTime = Get-Now
$runDir = Join-Path $OutputPath ('{0}_{1}' -f $computer, $startTime.ToString('yyyyMMdd-HHmmss'))
[void](New-Item -ItemType Directory -Path $runDir -Force)
$runDir = (Resolve-Path -LiteralPath $runDir).Path
$stopFlag = Join-Path $runDir 'stop.flag'

$meta = [ordered]@{
    SchemaVersion      = 1
    Computer           = $computer
    OS                 = $osCaption
    LogicalProcessors  = $cores
    PhysicalMemoryMB   = [long][Math]::Round($ramBytes / 1MB)
    IntervalSeconds    = $IntervalSeconds
    StartTime          = $startTime.ToString('o')
    EndTime            = $null
    Samples            = 0
    Simulated          = [bool]$Simulate
    IncludeCommandLine = [bool]$IncludeCommandLine
    CitrixSources      = @($script:CitrixSources | ForEach-Object { $_.ClassName })
}
function Save-Meta { ($meta | ConvertTo-Json) | Set-Content -LiteralPath (Join-Path $runDir 'meta.json') -Encoding UTF8 }
Save-Meta

$utf8 = New-Object System.Text.UTF8Encoding $false
function New-Writer([string]$Name, [string]$Header) {
    $w = New-Object System.IO.StreamWriter ((Join-Path $runDir $Name), $false, $utf8, 65536)
    $w.WriteLine($Header)
    return $w
}
$wSys = New-Writer 'system.csv' 'S,Timestamp,ElapsedSec,CpuPct,ProcQueue,MemAvailMB,MemCommittedMB,MemCommitLimitMB,PagesPerSec,DiskReadBps,DiskWriteBps,DiskReadIops,DiskWriteIops,DiskQueue,NetRecvBps,NetSentBps,Sessions,ActiveSessions,Processes,CollectMs'
$wSes = New-Writer 'sessions.csv' 'S,SessionId,User,Domain,State,WinStation,ClientName,LogonTime,IdleSec'
$wInf = New-Writer 'procinfo.csv' 'K,Pid,ParentPid,Name,SessionId,StartTime,Path,CommandLine'
$wPrc = New-Writer 'processes.csv' 'S,K,CpuMs,WsKB,PrivKB,ReadBytes,WriteBytes,IoOps,Handles,Threads'
$wCtx = New-Writer 'citrix.csv' 'S,Source,SessionId,Instance,Metric,Value'
$writers = @($wSys, $wSes, $wInf, $wPrc, $wCtx)

#endregion

#region ---------- capture loop -----------------------------------------------------------

function Get-Snapshot {
    if ($Simulate) {
        return [pscustomobject]@{
            Time = $script:SimNow; System = Get-SimSystemRaw; Processes = $script:SimProcs.ToArray()
            Sessions = $script:SimSessions.ToArray(); Citrix = $(if ($citrixEnabled) { Get-SimCitrixRaw } else { @() })
        }
    }
    return [pscustomobject]@{
        Time = Get-Date; System = Get-WinSystemRaw; Processes = Get-WinProcessRaw
        Sessions = Get-WinSessionRaw; Citrix = $(if ($citrixEnabled) { Get-WinCitrixRaw } else { @() })
    }
}

function Get-ProcessKey($Process) {
    $cd = $Process.CreationDate
    $ticks = $(if ($cd -is [datetime]) { $cd.Ticks } else { 0 })
    return ('{0}|{1}' -f $Process.ProcessId, $ticks)
}

Write-Host "WorkerPerf-Aufzeichnung laeuft: $runDir"
Write-Host "Intervall $IntervalSeconds s$(if ($DurationMinutes -gt 0) { ", Dauer $DurationMinutes min" }). Beenden mit Strg+C oder Datei 'stop.flag' im Ausgabeordner."

$sampleIndex = 0
$nextKey = 0
$state = @{}          # process key -> @(K, cpu100ns, readBytes, writeBytes, ioOps)
$endAt = $(if ($DurationMinutes -gt 0) { $startTime.AddMinutes($DurationMinutes) } else { [datetime]::MaxValue })

try {
    # Baseline: establishes the cumulative counters, nothing is written for it.
    $prev = Get-Snapshot
    foreach ($p in $prev.Processes) {
        $state[(Get-ProcessKey $p)] = @(-1, ([double]$p.KernelModeTime + [double]$p.UserModeTime), [double]$p.ReadTransferCount, [double]$p.WriteTransferCount, ([double]$p.ReadOperationCount + [double]$p.WriteOperationCount))
    }
    $nextTick = $prev.Time.AddSeconds($IntervalSeconds)

    while ($true) {
        if ($Simulate) {
            $script:SimNow = $nextTick
            Step-Simulation $IntervalSeconds
        }
        else {
            while ((Get-Date) -lt $nextTick) {
                if (Test-Path -LiteralPath $stopFlag) { break }
                $remaining = ($nextTick - (Get-Date)).TotalMilliseconds
                if ($remaining -gt 0) { Start-Sleep -Milliseconds ([int][Math]::Min(500, [Math]::Max(1, $remaining))) }
            }
            if (Test-Path -LiteralPath $stopFlag) { break }
        }

        $sw = [Diagnostics.Stopwatch]::StartNew()
        $cur = Get-Snapshot
        $elapsed = ($cur.Time - $prev.Time).TotalSeconds
        if ($elapsed -le 0) { $elapsed = $IntervalSeconds }

        # ---- processes ----
        $newState = @{}
        $cpuMsTotal = 0.0
        foreach ($p in $cur.Processes) {
            $key = Get-ProcessKey $p
            $cpuNow = [double]$p.KernelModeTime + [double]$p.UserModeTime
            $rdNow = [double]$p.ReadTransferCount
            $wrNow = [double]$p.WriteTransferCount
            $opNow = [double]$p.ReadOperationCount + [double]$p.WriteOperationCount
            $old = $state[$key]
            if ($null -ne $old) {
                $k = $old[0]
                $dCpu = $cpuNow - $old[1]; $dRd = $rdNow - $old[2]; $dWr = $wrNow - $old[3]; $dOp = $opNow - $old[4]
            }
            else {
                $k = -1
                # Started during this interval: everything it used so far belongs to this interval.
                if ($p.CreationDate -is [datetime] -and $p.CreationDate -gt $prev.Time) { $dCpu = $cpuNow; $dRd = $rdNow; $dWr = $wrNow; $dOp = $opNow }
                else { $dCpu = 0; $dRd = 0; $dWr = 0; $dOp = 0 }
            }
            if ($dCpu -lt 0) { $dCpu = 0 }; if ($dRd -lt 0) { $dRd = 0 }; if ($dWr -lt 0) { $dWr = 0 }; if ($dOp -lt 0) { $dOp = 0 }

            if ($k -lt 0) {
                $k = $nextKey; $nextKey++
                $startText = $(if ($p.CreationDate -is [datetime]) { $p.CreationDate.ToString('o') } else { '' })
                $cmd = $(if ($IncludeCommandLine) { Format-CsvText ([string](Get-Prop $p 'CommandLine')) } else { '' })
                $wInf.WriteLine(('{0},{1},{2},{3},{4},{5},{6},{7}' -f $k, $p.ProcessId, $p.ParentProcessId, (Format-CsvText $p.Name), $p.SessionId, $startText, (Format-CsvText $p.ExecutablePath), $cmd))
            }
            $newState[$key] = @($k, $cpuNow, $rdNow, $wrNow, $opNow)

            $cpuMs = [long][Math]::Round($dCpu / 10000.0)
            $cpuMsTotal += $cpuMs
            $wPrc.WriteLine([string]::Concat($sampleIndex, ',', $k, ',', $cpuMs, ',',
                    [long]([double]$p.WorkingSetSize / 1024), ',', [long]([double]$p.PrivatePageCount / 1024), ',',
                    [long]$dRd, ',', [long]$dWr, ',', [long]$dOp, ',', $p.HandleCount, ',', $p.ThreadCount))
        }
        $state = $newState

        # ---- sessions ----
        $active = 0; $userSessions = 0
        foreach ($s in $cur.Sessions) {
            if ($s.User) { $userSessions++; if ($s.State -eq 'Active') { $active++ } }
            $logon = $(if ($s.LogonTime -gt [datetime]::MinValue) { $s.LogonTime.ToString('o') } else { '' })
            $idle = $(if ($s.IdleSec -ge 0) { Format-Num $s.IdleSec 0 } else { '' })
            $wSes.WriteLine(('{0},{1},{2},{3},{4},{5},{6},{7},{8}' -f $sampleIndex, $s.SessionId, (Format-CsvText $s.User), (Format-CsvText $s.Domain), $s.State, (Format-CsvText $s.WinStation), (Format-CsvText $s.ClientName), $logon, $idle))
        }

        # ---- citrix ----
        foreach ($c in $cur.Citrix) {
            $wCtx.WriteLine(('{0},{1},{2},{3},{4},{5}' -f $sampleIndex, $c.Source, $c.SessionId, (Format-CsvText $c.Instance), $c.Metric, (Format-Num $c.Value 2)))
        }

        # ---- system ----
        $a = $cur.System; $b = $prev.System
        $cpuPct = $null
        if ($null -ne $a.CpuIdleCounter -and $null -ne $b.CpuIdleCounter) {
            $dTs = [double]$a.CpuTimestamp - [double]$b.CpuTimestamp
            if ($dTs -gt 0) { $cpuPct = 100.0 * (1.0 - (([double]$a.CpuIdleCounter - [double]$b.CpuIdleCounter) / $dTs)) }
        }
        if ($null -eq $cpuPct) { $cpuPct = 100.0 * $cpuMsTotal / ($elapsed * 1000.0 * $cores) }   # fallback: sum of all processes
        $cpuPct = [Math]::Max(0.0, [Math]::Min(100.0, $cpuPct))
        $toMB = { param($v) if ($null -eq $v) { $null } else { [double]$v / 1MB } }
        $sw.Stop()
        $wSys.WriteLine((@(
                    $sampleIndex, $cur.Time.ToString('o'), (Format-Num $elapsed 3), (Format-Num $cpuPct 2), (Format-Num $a.QueueLength 0),
                    (Format-Num (& $toMB $a.AvailBytes) 0), (Format-Num (& $toMB $a.CommittedBytes) 0), (Format-Num (& $toMB $a.CommitLimit) 0),
                    (Format-Num (Get-Rate $a.PagesCum $b.PagesCum $elapsed) 1),
                    (Format-Num (Get-Rate $a.DiskRdBytesCum $b.DiskRdBytesCum $elapsed) 0), (Format-Num (Get-Rate $a.DiskWrBytesCum $b.DiskWrBytesCum $elapsed) 0),
                    (Format-Num (Get-Rate $a.DiskRdOpsCum $b.DiskRdOpsCum $elapsed) 1), (Format-Num (Get-Rate $a.DiskWrOpsCum $b.DiskWrOpsCum $elapsed) 1),
                    (Format-Num $a.DiskQueue 0),
                    (Format-Num (Get-Rate $a.NetRxCum $b.NetRxCum $elapsed) 0), (Format-Num (Get-Rate $a.NetTxCum $b.NetTxCum $elapsed) 0),
                    $userSessions, $active, @($cur.Processes).Count, $sw.ElapsedMilliseconds
                ) -join ','))

        foreach ($w in $writers) { $w.Flush() }
        $prev = $cur
        $sampleIndex++
        $meta.Samples = $sampleIndex

        if (-not $Simulate -and $sw.ElapsedMilliseconds -gt $IntervalSeconds * 500) {
            Write-WarningOnce 'slow' "Eine Messung dauerte $($sw.ElapsedMilliseconds) ms - das Intervall von $IntervalSeconds s ist fuer dieses System knapp bemessen."
        }

        $nextTick = $nextTick.AddSeconds($IntervalSeconds)
        $nowCheck = Get-Now
        if ($nextTick -lt $nowCheck) { $nextTick = $nowCheck }      # never try to catch up missed samples
        if ($nextTick -gt $endAt) { break }
    }
}
finally {
    foreach ($w in $writers) { try { $w.Dispose() } catch { Write-Verbose $_.Exception.Message } }
    $meta.EndTime = (Get-Now).ToString('o')
    Save-Meta
    if (Test-Path -LiteralPath $stopFlag) { Remove-Item -LiteralPath $stopFlag -Force -ErrorAction SilentlyContinue }
    Write-Host "Aufzeichnung beendet: $sampleIndex Messungen in $runDir"
}

#endregion

# Emit the run folder so callers can pipe it into New-WorkerPerfReport.ps1
$runDir
