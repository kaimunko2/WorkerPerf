#Requires -Version 5.1
# WorkerPerf Windows data source (library, definitions only).
# Moved unchanged from the former Start-WorkerPerfCapture.ps1. The functions of the data source interface
# (Initialize-WorkerPerfSource, Get-WorkerPerfFastSample, ...) follow in a later task; until then the collector
# refuses to run without -Simulate.

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
