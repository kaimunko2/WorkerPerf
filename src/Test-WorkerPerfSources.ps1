#Requires -Version 5.1
<#
.SYNOPSIS
    Probes which data sources WorkerPerf can use on a Citrix multi-session VDA.

.DESCRIPTION
    Standalone script: copy this single file to a worker and run it once in an elevated console.
    Every check runs on its own; a failing check is reported and the others continue.
    The script only reads; it changes nothing on the system.

    Results are shown as a table and written as JSON to
    WorkerPerf-Quellen_<COMPUTER>_<yyyyMMdd-HHmmss>.json. The computer name is the only name in
    the file: user names and UNC server names in paths and instance names are masked.

    Performance counters are read through System.Diagnostics.PerformanceCounterCategory with
    English names (language neutral). For comparison the matching Win32_PerfRawData_* CIM
    class names are listed as well.

.PARAMETER OutFile
    Folder or .json file for the result. A folder (existing, or any path not ending in .json)
    receives the default file name. Default: current folder.

.PARAMETER EndpointFile
    Optional JSON file { "endpoints": [ { "name", "host", "port", "role" } ] } (see
    endpoints.example.json). The TCP connect time to each endpoint is measured.

.PARAMETER InputSeconds
    Number of 1 s samples of 'User Input Delay per Session'; half as many 2 s samples follow.

.PARAMETER ListChecks
    Only list the checks (Id, Signals, Title) without touching the system.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-WorkerPerfSources.ps1 -OutFile C:\Temp
#>
[CmdletBinding()]
param(
    [string]$OutFile,
    [string]$EndpointFile,
    [ValidateRange(2, 600)][int]$InputSeconds = 20,
    [switch]$ListChecks
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

#region ---------- masking --------------------------------------------------------------------

function Hide-WorkerPerfName([string]$Text, [string[]]$Users) {
    # Replaces user names (case-insensitive, whole names only, longest first) by <user> and a
    # leading UNC server name by <server>. Self-contained: the tests load this function alone.
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $result = $Text
    $names = @(@($Users) | Where-Object { -not [string]::IsNullOrEmpty($_) } | Sort-Object -Unique |
            Sort-Object -Property { $_.Length } -Descending)
    if ($names.Count -gt 0) {
        # One pass with an alternation, so text that was already replaced is never matched again.
        $alternatives = ($names | ForEach-Object { [regex]::Escape($_) }) -join '|'
        $pattern = '(?<![\p{L}\p{N}])(?:' + $alternatives + ')(?![\p{L}\p{N}])'
        $result = [regex]::Replace($result, $pattern, '<user>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    # \\server\... at the start; device paths such as \\?\Volume{...} and \\.\ are kept.
    $m = [regex]::Match($result, '^\\\\(?![?.]\\)[^\\]+')
    if ($m.Success) { $result = '\\<server>' + $result.Substring($m.Length) }
    return $result
}

$script:ProbeUsers = @()

function Hide-ProbeText([string]$Text) {
    return Hide-WorkerPerfName -Text $Text -Users $script:ProbeUsers
}

function Hide-ProbeShareName([string]$Name) {
    # SMB share instances may start with a single backslash (\server\share).
    if ($Name -match '^\\[^\\]') { return (Hide-WorkerPerfName -Text ('\' + $Name) -Users $script:ProbeUsers).Substring(1) }
    return Hide-ProbeText $Name
}

function Test-ProbeUserInText([string]$Text) {
    # True when a known user name occurs in $Text (same matching rules as the masking).
    if ([string]::IsNullOrEmpty($Text)) { return $false }
    return (Hide-WorkerPerfName -Text $Text -Users $script:ProbeUsers) -ne (Hide-WorkerPerfName -Text $Text -Users @())
}

#endregion

#region ---------- helpers --------------------------------------------------------------------

function Get-Prop($Object, [string]$Name) {
    # Tolerant property read: returns $null when the property does not exist.
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Get-ProbeErrorText($ErrorRecord) {
    $e = $ErrorRecord.Exception
    while ($null -ne $e.InnerException) { $e = $e.InnerException }
    # Messages may quote paths, so they are masked like every other text in the result.
    return Hide-ProbeText ([string]$e.Message)
}

function ConvertTo-ProbeNumber($Value) {
    if ($null -eq $Value) { return $null }
    $d = [double]$Value
    if ([double]::IsNaN($d) -or [double]::IsInfinity($d)) { return $null }
    return [Math]::Round($d, 6)
}

function Get-ProbeMs([System.Diagnostics.Stopwatch]$Stopwatch) {
    return [Math]::Round($Stopwatch.Elapsed.TotalMilliseconds, 1)
}

function Get-ProbeProcesses($Ctx) {
    if ($null -eq $Ctx.Processes) { $Ctx.Processes = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop) }
    return $Ctx.Processes
}

function Get-ProbeServices($Ctx) {
    if ($null -eq $Ctx.Services) { $Ctx.Services = @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop) }
    return $Ctx.Services
}

function Get-ProbeFileInfo($Ctx, [string]$Path) {
    if ([string]::IsNullOrEmpty($Path)) { return @{ Company = ''; Description = '' } }
    if (-not $Ctx.FileInfo.ContainsKey($Path)) {
        $info = @{ Company = ''; Description = '' }
        try {
            $v = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
            $info.Company = [string]$v.CompanyName
            $info.Description = [string]$v.FileDescription
        }
        catch { $info.Description = '' }
        $Ctx.FileInfo[$Path] = $info
    }
    return $Ctx.FileInfo[$Path]
}

#endregion

#region ---------- native helpers (C# 5) -----------------------------------------------------

# Same WTS wrapper as Start-WorkerPerfCapture.ps1, in its own namespace so both can share a session.
$script:WtsSource = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace WorkerPerfProbe
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

$script:DosDeviceSource = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace WorkerPerfProbe
{
    public static class DosDevice
    {
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern uint QueryDosDeviceW(string lpDeviceName, StringBuilder lpTargetPath, int ucchMax);

        // Returns the first target of an MS-DOS device name (e.g. "Volume{guid}"), or null.
        public static string Query(string deviceName)
        {
            StringBuilder buffer = new StringBuilder(1024);
            uint length = QueryDosDeviceW(deviceName, buffer, buffer.Capacity);
            if (length == 0) return null;
            return buffer.ToString();
        }
    }
}
'@

#endregion

#region ---------- performance counters -------------------------------------------------------

function Test-ProbeInstance([string]$Name, [string]$Mode) {
    switch ($Mode) {
        'total'   { return $Name -eq '_Total' }
        'nototal' { return $Name -ne '_Total' }
        default   { return $true }
    }
}

function Read-ProbePerf {
    # .NET path: reads the category twice, 1 s apart, and calculates each counter value.
    # Instances: 'none' (single instance), 'total', 'all', 'nototal'. MaxInstances 0 = all.
    param([string]$Category, [string[]]$Counters, [string]$Instances, [int]$MaxInstances = 0, [switch]$ShareNames)

    $r = [ordered]@{
        Category = $Category; Exists = $false; CategoryType = ''; CounterNames = @(); InstanceCount = 0
        InstanceNames = @(); Counters = @(); Ok = $false; Error = ''
    }
    if (-not [System.Diagnostics.PerformanceCounterCategory]::Exists($Category)) {
        $r.Error = 'Kategorie nicht vorhanden'
        return $r
    }
    $r.Exists = $true
    $cat = New-Object System.Diagnostics.PerformanceCounterCategory -ArgumentList $Category
    $r.CategoryType = $cat.CategoryType.ToString()

    # All counter names of the category, in their original spelling.
    $names = New-Object 'System.Collections.Generic.List[string]'
    try {
        $pcs = $null
        try { $pcs = $cat.GetCounters() }
        catch {
            $inst = $cat.GetInstanceNames()
            if ($inst.Length -gt 0) { $pcs = $cat.GetCounters($inst[0]) }
        }
        if ($null -ne $pcs) {
            foreach ($pc in $pcs) { $names.Add([string]$pc.CounterName); $pc.Dispose() }
        }
    }
    catch { $r.Error = 'Zaehlernamen: ' + (Get-ProbeErrorText $_) }

    $d1 = $cat.ReadCategory()
    Start-Sleep -Seconds 1
    $d2 = $cat.ReadCategory()
    if ($names.Count -eq 0) { foreach ($k in $d2.Keys) { $names.Add([string]$k) } }
    $r.CounterNames = $names.ToArray()

    $wanted = $names.ToArray()
    if ($null -ne $Counters -and $Counters.Length -gt 0) { $wanted = $Counters }

    $instanceNames = New-Object 'System.Collections.Generic.List[string]'
    $counterRows = New-Object 'System.Collections.Generic.List[object]'
    $allOk = $wanted.Length -gt 0
    foreach ($cn in $wanted) {
        $e = [ordered]@{ Counter = $cn; Exists = $false; Type = ''; ValueCount = 0; Instances = @() }
        $c1 = $d1.get_Item($cn)
        $c2 = $d2.get_Item($cn)
        if ($null -ne $c2) {
            $e.Exists = $true
            $rows = New-Object 'System.Collections.Generic.List[object]'
            $matched = 0
            foreach ($i2 in @($c2.Values | Sort-Object -Property InstanceName)) {
                $name = [string]$i2.InstanceName
                if (-not (Test-ProbeInstance $name $Instances)) { continue }
                $matched++
                $s2 = $i2.Sample
                $e.Type = $s2.CounterType.ToString()
                $raw1 = $null; $base1 = $null; $time1 = $null; $value = $null
                $i1 = $null
                if ($null -ne $c1) { $i1 = $c1.get_Item($name) }
                if ($null -ne $i1) {
                    $s1 = $i1.Sample
                    $raw1 = $s1.RawValue; $base1 = $s1.BaseValue; $time1 = $s1.TimeStamp100nSec
                    $value = ConvertTo-ProbeNumber ([System.Diagnostics.CounterSample]::Calculate($s1, $s2))
                }
                if ($null -ne $value) { $e.ValueCount = $e.ValueCount + 1 }
                if ($MaxInstances -gt 0 -and $rows.Count -ge $MaxInstances) { continue }

                $shown = ''
                if ($Instances -ne 'none') {
                    if ($ShareNames) { $shown = Hide-ProbeShareName $name } else { $shown = Hide-ProbeText $name }
                    if (-not $instanceNames.Contains($shown)) { $instanceNames.Add($shown) }
                }
                $rows.Add([ordered]@{
                        Instance = $shown
                        Raw1 = $raw1; Raw2 = $s2.RawValue
                        Base1 = $base1; Base2 = $s2.BaseValue
                        Time1 = $time1; Time2 = $s2.TimeStamp100nSec
                        Value = $value
                    })
            }
            $e.Instances = $rows.ToArray()
            if ($matched -gt $r.InstanceCount) { $r.InstanceCount = $matched }
        }
        if ($e.ValueCount -eq 0) { $allOk = $false }
        $counterRows.Add($e)
    }
    $r.InstanceNames = $instanceNames.ToArray()
    $r.Counters = $counterRows.ToArray()
    $r.Ok = $allOk
    return $r
}

function Get-ProbeCimPerf($Ctx, [string]$Category) {
    # CIM path: names of all Win32_PerfRawData_* classes matching the category name without spaces.
    if ($null -eq $Ctx.CimPerfClasses) {
        try {
            $Ctx.CimPerfClasses = @(Get-CimClass -Namespace 'root\cimv2' -ClassName 'Win32_PerfRawData_*' -ErrorAction Stop |
                    ForEach-Object { [string]$_.CimClassName })
        }
        catch {
            $Ctx.CimPerfClasses = @()
            $Ctx.CimPerfError = Get-ProbeErrorText $_
        }
    }
    $suffix = '_' + ($Category -replace '[^A-Za-z0-9]', '')
    $classes = @($Ctx.CimPerfClasses | Where-Object { $_.EndsWith($suffix, [StringComparison]::OrdinalIgnoreCase) })
    return [ordered]@{ Classes = $classes; Error = $Ctx.CimPerfError }
}

function Invoke-ProbePerfCheck($Ctx, $Check) {
    $p = $Check.Perf
    $dn = $null
    try {
        $dn = Read-ProbePerf -Category $p.Category -Counters $p.Counters -Instances $p.Instances -MaxInstances $p.MaxInstances -ShareNames:($Check.Id -eq 'perf.shares')
    }
    catch {
        $dn = [ordered]@{ Category = $p.Category; Exists = $null; Ok = $false; Error = Get-ProbeErrorText $_ }
    }
    $cim = Get-ProbeCimPerf $Ctx $p.Category

    if ($dn.Ok) {
        $detail = 'DotNet: {0} Zaehler mit Werten, {1} Instanzen' -f @($dn.Counters).Count, $dn.InstanceCount
    }
    elseif ($dn.Error) {
        $detail = 'DotNet: ' + $dn.Error
    }
    else {
        $missing = @($dn.Counters | Where-Object { $_.ValueCount -eq 0 } | ForEach-Object { $_.Counter })
        $detail = 'DotNet: ohne Werte: ' + ($missing -join ', ')
        if ($dn.InstanceCount -eq 0) { $detail = 'DotNet: keine passenden Instanzen' }
    }
    $detail += '; Cim: {0} Klassen' -f $cim.Classes.Count
    return @{ Ok = [bool]$dn.Ok; Detail = $detail; Data = [ordered]@{ DotNet = $dn; Cim = $cim } }
}

function Invoke-ProbeVolumesCheck($Ctx, $Check) {
    $out = Invoke-ProbePerfCheck $Ctx $Check
    $times = New-Object 'System.Collections.Generic.List[object]'
    $dn = $out.Data.DotNet
    if ($dn.Contains('Counters')) {
        $read = @{}; $write = @{}
        foreach ($c in $dn.Counters) {
            foreach ($row in $c.Instances) {
                if ($null -eq $row.Value) { continue }
                if ($c.Counter -eq 'Avg. Disk sec/Read') { $read[$row.Instance] = $row.Value }
                if ($c.Counter -eq 'Avg. Disk sec/Write') { $write[$row.Instance] = $row.Value }
            }
        }
        foreach ($name in $dn.InstanceNames) {
            $rm = $null; $wm = $null
            if ($read.ContainsKey($name)) { $rm = [Math]::Round($read[$name] * 1000, 3) }
            if ($write.ContainsKey($name)) { $wm = [Math]::Round($write[$name] * 1000, 3) }
            $times.Add([ordered]@{ Instance = $name; ReadMs = $rm; WriteMs = $wm })
        }
    }
    $out.Data.ResponseMs = $times.ToArray()
    return $out
}

function Invoke-ProbeIcaCheck($Ctx, $Check) {
    $out = Invoke-ProbePerfCheck $Ctx $Check
    $euem = [ordered]@{ Namespace = 'root\citrix\euem'; Available = $false; Classes = @(); Error = '' }
    try {
        $classes = New-Object 'System.Collections.Generic.List[object]'
        foreach ($c in @(Get-CimClass -Namespace 'root\citrix\euem' -ErrorAction Stop | Sort-Object -Property CimClassName)) {
            if ($c.CimClassName.StartsWith('__')) { continue }
            $props = @($c.CimClassProperties | ForEach-Object { '{0}:{1}' -f $_.Name, $_.CimType })
            $classes.Add([ordered]@{ Name = [string]$c.CimClassName; Properties = $props })
        }
        $euem.Classes = $classes.ToArray()
        $euem.Available = $true
    }
    catch { $euem.Error = Get-ProbeErrorText $_ }
    $out.Data.Euem = $euem
    $out.Detail += '; EUEM: {0} Klassen' -f @($euem.Classes).Count
    return $out
}

function Read-ProbeInputSeries($Category, [string]$Counter, [int]$Count, [int]$IntervalSec) {
    # $Count readings, $IntervalSec apart; each value is calculated against the previous reading.
    $samples = New-Object 'System.Collections.Generic.List[object]'
    $names = New-Object 'System.Collections.Generic.List[string]'
    $type = ''
    $valueCount = 0
    $prev = $null
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    for ($k = 0; $k -lt $Count; $k++) {
        $wait = [int]($k * $IntervalSec * 1000 - $sw.ElapsedMilliseconds)
        if ($wait -gt 0) { Start-Sleep -Milliseconds $wait }
        $offset = Get-ProbeMs $sw
        $coll = $Category.ReadCategory().get_Item($Counter)
        $readings = New-Object 'System.Collections.Generic.List[object]'
        if ($null -ne $coll) {
            foreach ($i in @($coll.Values | Sort-Object -Property InstanceName)) {
                $name = [string]$i.InstanceName
                $s = $i.Sample
                $type = $s.CounterType.ToString()
                $shown = Hide-ProbeText $name
                if (-not $names.Contains($shown)) { $names.Add($shown) }
                $p = $null
                if ($null -ne $prev) { $p = $prev.get_Item($name) }
                if ($null -ne $p) { $v = [System.Diagnostics.CounterSample]::Calculate($p.Sample, $s) }
                else { $v = [System.Diagnostics.CounterSample]::Calculate($s) }
                $v = ConvertTo-ProbeNumber $v
                if ($null -ne $v) { $valueCount++ }
                $readings.Add([ordered]@{ Instance = $shown; Raw = $s.RawValue; Value = $v })
            }
        }
        $samples.Add([ordered]@{ OffsetMs = $offset; Readings = $readings.ToArray() })
        $prev = $coll
    }
    return @{ Samples = $samples.ToArray(); Names = $names.ToArray(); Type = $type; ValueCount = $valueCount }
}

function Invoke-ProbeInputSessionCheck($Ctx, $Check) {
    $p = $Check.Perf
    $counter = $p.Counters[0]
    $dn = [ordered]@{
        Category = $p.Category; Counter = $counter; Exists = $false; Type = ''; InstanceNames = @()
        InputSeconds = $Ctx.InputSeconds; Interval1s = @(); Interval2s = @(); Ok = $false; Error = ''
    }
    try {
        if ([System.Diagnostics.PerformanceCounterCategory]::Exists($p.Category)) {
            $dn.Exists = $true
            $cat = New-Object System.Diagnostics.PerformanceCounterCategory -ArgumentList $p.Category
            Write-Host '      Bitte jetzt in einer Benutzersitzung tippen oder Fenster bewegen ...'
            $one = Read-ProbeInputSeries $cat $counter $Ctx.InputSeconds 1
            $two = Read-ProbeInputSeries $cat $counter ([int][Math]::Floor($Ctx.InputSeconds / 2)) 2
            $dn.Type = $one.Type
            $all = New-Object 'System.Collections.Generic.List[string]'
            foreach ($n in @($one.Names) + @($two.Names)) { if (-not $all.Contains($n)) { $all.Add($n) } }
            $dn.InstanceNames = $all.ToArray()
            $dn.Interval1s = $one.Samples
            $dn.Interval2s = $two.Samples
            $dn.Ok = $one.ValueCount -gt 0
            if (-not $dn.Ok) { $dn.Error = 'keine Werte' }
        }
        else { $dn.Error = 'Kategorie nicht vorhanden' }
    }
    catch { $dn.Error = Get-ProbeErrorText $_ }
    $cim = Get-ProbeCimPerf $Ctx $p.Category

    if ($dn.Ok) {
        $detail = 'DotNet: {0} Instanzen, {1} Proben je 1 s, {2} Proben je 2 s' -f @($dn.InstanceNames).Count, @($dn.Interval1s).Count, @($dn.Interval2s).Count
    }
    else { $detail = 'DotNet: ' + $dn.Error }
    $detail += '; Cim: {0} Klassen' -f $cim.Classes.Count
    return @{ Ok = [bool]$dn.Ok; Detail = $detail; Data = [ordered]@{ DotNet = $dn; Cim = $cim } }
}

#endregion

#region ---------- other checks -----------------------------------------------------------------

function Invoke-ProbeSystemCheck($Ctx, $Check) {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $cpus = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
    $cores = 0
    foreach ($c in $cpus) { $cores += [int]$c.NumberOfCores }
    $vmTools = @(Get-CimInstance -ClassName Win32_Service -Filter "Name='VMTools'" -ErrorAction Stop)
    $vmState = ''
    if ($vmTools.Count -gt 0) { $vmState = [string]$vmTools[0].State }
    $data = [ordered]@{
        LogicalProcessors = [int]$cs.NumberOfLogicalProcessors
        Cores             = $cores
        Sockets           = $cpus.Count
        MemoryBytes       = [uint64]$cs.TotalPhysicalMemory
        Manufacturer      = [string]$cs.Manufacturer
        Model             = [string]$cs.Model
        VMToolsPresent    = $vmTools.Count -gt 0
        VMToolsState      = $vmState
    }
    $detail = '{0} logische Prozessoren, {1} Kerne, {2:0.0} GB RAM, {3} {4}, VMTools: {5}' -f $data.LogicalProcessors, $cores,
        ($data.MemoryBytes / 1GB), $data.Manufacturer, $data.Model, $data.VMToolsPresent
    return @{ Ok = $true; Detail = $detail; Data = $data }
}

function Invoke-ProbeProcessSnapshotCheck($Ctx, $Check) {
    $durations = New-Object 'System.Collections.Generic.List[double]'
    $procs = @()
    for ($k = 0; $k -lt 3; $k++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $procs = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop)
        $sw.Stop()
        $durations.Add((Get-ProbeMs $sw))
    }
    $Ctx.Processes = $procs
    $d = $durations.ToArray()
    $detail = '{0} Prozesse, Abfrage {1} ms' -f $procs.Count, (($d | ForEach-Object { $_.ToString([Globalization.CultureInfo]::InvariantCulture) }) -join ' / ')
    return @{ Ok = $true; Detail = $detail; Data = [ordered]@{ ProcessCount = $procs.Count; DurationsMs = $d } }
}

function Invoke-ProbeSessionsCheck($Ctx, $Check) {
    $data = [ordered]@{
        Compiled = $Ctx.WtsCompiled; Error = $Ctx.WtsError; SessionCount = 0; ByState = [ordered]@{}
        WithUser = 0; WithLogonTime = 0; WithIdleTime = 0
    }
    $sessions = @($Ctx.Sessions)
    $data.SessionCount = $sessions.Count
    foreach ($s in $sessions) {
        $state = [string]$s.State
        if ($data.ByState.Contains($state)) { $data.ByState[$state] = $data.ByState[$state] + 1 } else { $data.ByState[$state] = 1 }
        if (-not [string]::IsNullOrEmpty($s.User)) { $data.WithUser++ }
        if ($s.LogonTime -gt [DateTime]::MinValue) { $data.WithLogonTime++ }
        if ($s.IdleSec -ge 0) { $data.WithIdleTime++ }
    }
    $ok = $Ctx.WtsCompiled -and [string]::IsNullOrEmpty($Ctx.WtsError)
    if ($ok) {
        $states = @($data.ByState.Keys | ForEach-Object { '{0} {1}' -f $_, $data.ByState[$_] }) -join ', '
        $detail = '{0} Sitzungen ({1})' -f $sessions.Count, $states
    }
    else { $detail = 'WTS: ' + $Ctx.WtsError }
    return @{ Ok = $ok; Detail = $detail; Data = $data }
}

function Invoke-ProbeServicesCheck($Ctx, $Check) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $Ctx.Services = @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop)
    $sw.Stop()
    $rows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($s in @($Ctx.Services | Where-Object { [int]$_.ProcessId -ne 0 } | Sort-Object -Property Name)) {
        $rows.Add([ordered]@{ Name = Hide-ProbeText ([string]$s.Name); ProcessId = [int]$s.ProcessId })
    }
    $ms = Get-ProbeMs $sw
    $detail = '{0} Dienste mit Prozess, Abfrage {1} ms' -f $rows.Count, $ms.ToString([Globalization.CultureInfo]::InvariantCulture)
    return @{ Ok = $true; Detail = $detail; Data = [ordered]@{ DurationMs = $ms; Services = $rows.ToArray() } }
}

function Invoke-ProbeProfileVolumesCheck($Ctx, $Check) {
    $dosError = ''
    try { if (-not ('WorkerPerfProbe.DosDevice' -as [type])) { Add-Type -TypeDefinition $script:DosDeviceSource -Language CSharp } }
    catch { $dosError = Get-ProbeErrorText $_ }

    $ldInstances = @()
    $ldError = ''
    try { $ldInstances = @((New-Object System.Diagnostics.PerformanceCounterCategory -ArgumentList 'LogicalDisk').GetInstanceNames()) }
    catch { $ldError = Get-ProbeErrorText $_ }

    $ns = 'root\Microsoft\Windows\Storage'
    $disks = @(Get-CimInstance -Namespace $ns -ClassName MSFT_Disk -Filter 'BusType = 15' -ErrorAction Stop)
    $rows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($d in $disks) {
        $number = [int](Get-Prop $d 'Number')
        $location = [string](Get-Prop $d 'Location')
        $parts = New-Object 'System.Collections.Generic.List[object]'
        foreach ($p in @(Get-CimInstance -Namespace $ns -ClassName MSFT_Partition -Filter ('DiskNumber = {0}' -f $number) -ErrorAction Stop)) {
            $paths = @(@(Get-Prop $p 'AccessPaths') | Where-Object { -not [string]::IsNullOrEmpty($_) })
            $letter = ''
            $dl = Get-Prop $p 'DriveLetter'
            if ($null -ne $dl -and [int][char]$dl -ne 0) { $letter = ([string][char]$dl) + ':' }

            $device = ''
            $candidates = New-Object 'System.Collections.Generic.List[string]'
            if ($letter) { $candidates.Add($letter) }
            foreach ($ap in $paths) {
                $m = [regex]::Match($ap, '^\\\\\?\\(Volume\{[^}]+\})\\?$')
                if ($m.Success -and -not $dosError) {
                    $dosTarget = [WorkerPerfProbe.DosDevice]::Query($m.Groups[1].Value)
                    if ($dosTarget) {
                        $device = $dosTarget
                        $candidates.Add($dosTarget.Substring($dosTarget.LastIndexOf('\') + 1))
                    }
                }
                else { $candidates.Add($ap.TrimEnd('\')) }
            }
            $instance = ''
            foreach ($li in $ldInstances) {
                if (@($candidates | Where-Object { $_ -eq $li }).Count -gt 0) { $instance = $li; break }
            }
            $userInPaths = @($paths | Where-Object { Test-ProbeUserInText $_ }).Count -gt 0
            $parts.Add([ordered]@{
                    PartitionNumber     = [int](Get-Prop $p 'PartitionNumber')
                    DriveLetter         = $letter
                    Size                = [uint64](Get-Prop $p 'Size')
                    AccessPaths         = @($paths | ForEach-Object { Hide-ProbeText $_ })
                    DeviceName          = $device
                    LogicalDiskInstance = Hide-ProbeText $instance
                    UserInAccessPaths   = $userInPaths
                })
        }
        $rows.Add([ordered]@{
                Number         = $number
                Size           = [uint64](Get-Prop $d 'Size')
                Location       = Hide-ProbeText $location
                UserInLocation = Test-ProbeUserInText $location
                Partitions     = $parts.ToArray()
            })
    }
    $data = [ordered]@{
        Disks                = $rows.ToArray()
        LogicalDiskInstances = @($ldInstances | ForEach-Object { Hide-ProbeText $_ })
        LogicalDiskError     = $ldError
        QueryDosDeviceError  = $dosError
    }
    return @{ Ok = $true; Detail = ('{0} Datentraeger mit BusType 15' -f $rows.Count); Data = $data }
}

function Get-ProbeEventCounts([string]$Log, [int[]]$Ids) {
    $r = [ordered]@{ Log = $Log; Exists = $false; Enabled = $null; Readable = $false; Counts = [ordered]@{}; Error = '' }
    try {
        $info = Get-WinEvent -ListLog $Log -ErrorAction Stop
        $r.Exists = $true
        $r.Enabled = [bool]$info.IsEnabled
    }
    catch {
        $r.Error = Get-ProbeErrorText $_
        return $r
    }
    try {
        $events = @()
        try {
            $events = @(Get-WinEvent -FilterHashtable @{ LogName = $Log; Id = $Ids; StartTime = (Get-Date).AddDays(-7) } -ErrorAction Stop)
        }
        catch {
            # No matching events is not an error; the error id is language neutral.
            if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { throw }
        }
        $r.Readable = $true
        foreach ($id in $Ids) { $r.Counts[[string]$id] = @($events | Where-Object { $_.Id -eq $id }).Count }
    }
    catch { $r.Error = Get-ProbeErrorText $_ }
    return $r
}

function Invoke-ProbeEventsCheck($Ctx, $Check) {
    $logs = New-Object 'System.Collections.Generic.List[object]'
    foreach ($log in $Check.Logs) { $logs.Add((Get-ProbeEventCounts $log $Check.EventIds)) }
    $parts = New-Object 'System.Collections.Generic.List[string]'
    $ok = $true
    foreach ($l in $logs) {
        if ($l.Readable) {
            $counts = @($l.Counts.Keys | ForEach-Object { '{0}={1}' -f $_, $l.Counts[$_] }) -join ' '
            $parts.Add(('{0}: {1}' -f $l.Log, $counts))
        }
        else {
            $ok = $false
            $parts.Add(('{0}: nicht lesbar ({1})' -f $l.Log, $l.Error))
        }
    }
    return @{ Ok = $ok; Detail = ($parts.ToArray() -join '; '); Data = [ordered]@{ Days = 7; Logs = $logs.ToArray() } }
}

function Get-ProbeProcessGroups($Ctx, [bool]$SessionZero) {
    $procs = Get-ProbeProcesses $Ctx
    $pidServices = @{}
    if ($SessionZero) {
        foreach ($s in (Get-ProbeServices $Ctx)) {
            $id = [int]$s.ProcessId
            if ($id -eq 0) { continue }
            if (-not $pidServices.ContainsKey($id)) { $pidServices[$id] = New-Object 'System.Collections.Generic.List[string]' }
            $pidServices[$id].Add([string]$s.Name)
        }
    }
    $selected = @($procs | Where-Object { ([int]$_.SessionId -eq 0) -eq $SessionZero })
    $rows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($g in @($selected | Group-Object -Property Name | Sort-Object -Property Name)) {
        $path = ''
        foreach ($p in $g.Group) {
            $ep = [string](Get-Prop $p 'ExecutablePath')
            if ($ep) { $path = $ep; break }
        }
        $info = Get-ProbeFileInfo $Ctx $path
        $row = [ordered]@{
            Name        = Hide-ProbeText ([string]$g.Name)
            Instances   = $g.Count
            Company     = Hide-ProbeText $info.Company
            Description = Hide-ProbeText $info.Description
        }
        if ($SessionZero) {
            $svc = New-Object 'System.Collections.Generic.List[string]'
            foreach ($p in $g.Group) {
                $id = [int]$p.ProcessId
                if ($pidServices.ContainsKey($id)) { foreach ($n in $pidServices[$id]) { if (-not $svc.Contains($n)) { $svc.Add($n) } } }
            }
            $row.Services = @($svc.ToArray() | Sort-Object | ForEach-Object { Hide-ProbeText $_ })
        }
        $rows.Add($row)
    }
    return @{ Rows = $rows.ToArray(); ProcessCount = $selected.Count }
}

function Invoke-ProbeSecurityProductsCheck($Ctx, $Check) {
    $g = Get-ProbeProcessGroups $Ctx $true
    $detail = '{0} Prozessnamen in Sitzung 0 ({1} Prozesse)' -f @($g.Rows).Count, $g.ProcessCount
    return @{ Ok = $true; Detail = $detail; Data = [ordered]@{ Processes = $g.Rows } }
}

function Invoke-ProbeUserProcessesCheck($Ctx, $Check) {
    $g = Get-ProbeProcessGroups $Ctx $false
    $detail = '{0} Prozessnamen in Benutzersitzungen ({1} Prozesse)' -f @($g.Rows).Count, $g.ProcessCount
    return @{ Ok = $true; Detail = $detail; Data = [ordered]@{ Processes = $g.Rows } }
}

function Invoke-ProbeEndpointsCheck($Ctx, $Check) {
    if ([string]::IsNullOrEmpty($Ctx.EndpointFile)) {
        return @{ Ok = $false; Detail = 'kein -EndpointFile angegeben, Pruefung entfaellt'; Data = [ordered]@{ TimeoutMs = 2000; Endpoints = @() } }
    }
    $cfg = Get-Content -LiteralPath $Ctx.EndpointFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $rows = New-Object 'System.Collections.Generic.List[object]'
    $reached = 0
    foreach ($e in @(Get-Prop $cfg 'endpoints')) {
        $hostName = [string](Get-Prop $e 'host')
        $row = [ordered]@{
            Name = Hide-ProbeText ([string](Get-Prop $e 'name')); Role = [string](Get-Prop $e 'role')
            Port = Get-Prop $e 'port'; DnsMs = $null; ConnectMs = $null; Error = ''
        }
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $addresses = @([System.Net.Dns]::GetHostAddresses($hostName))
            $row.DnsMs = Get-ProbeMs $sw
            $address = @($addresses | Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork }) + $addresses | Select-Object -First 1
            if ($null -eq $address) { throw 'keine Adresse' }
            $client = New-Object System.Net.Sockets.TcpClient -ArgumentList $address.AddressFamily
            try {
                $sw.Restart()
                $async = $client.BeginConnect($address, [int]$row.Port, $null, $null)
                if ($async.AsyncWaitHandle.WaitOne(2000)) {
                    $client.EndConnect($async)
                    $row.ConnectMs = Get-ProbeMs $sw
                    $reached++
                }
                else { $row.Error = 'Zeitlimit 2 s ueberschritten' }
            }
            finally { $client.Close() }
        }
        catch {
            $msg = Get-ProbeErrorText $_
            if ($hostName) { $msg = $msg.Replace($hostName, '<server>') }
            $row.Error = $msg
        }
        $rows.Add($row)
    }
    $detail = '{0} von {1} Gegenstellen erreichbar' -f $reached, $rows.Count
    return @{ Ok = ($rows.Count -gt 0 -and $reached -eq $rows.Count); Detail = $detail; Data = [ordered]@{ TimeoutMs = 2000; Endpoints = $rows.ToArray() } }
}

#endregion

#region ---------- check catalogue -------------------------------------------------------------

# One list drives both -ListChecks and the run, so they cannot drift apart.
$script:Catalogue = @(
    @{ Id = 'system'; Signals = @(); Title = 'Kerne, RAM, Hersteller, VMware Tools'; Run = 'Invoke-ProbeSystemCheck' }
    @{ Id = 'process.snapshot'; Signals = @(); Title = 'Dauer eines Prozess-Schnappschusses (Win32_Process)'; Run = 'Invoke-ProbeProcessSnapshotCheck' }
    @{ Id = 'sessions.wts'; Signals = @(); Title = 'Sitzungen ueber die WTS-Schnittstelle'; Run = 'Invoke-ProbeSessionsCheck' }
    @{ Id = 'services.map'; Signals = @(); Title = 'Dienste und ihre Prozesse (Win32_Service)'; Run = 'Invoke-ProbeServicesCheck' }
    @{ Id = 'perf.cpu'; Signals = @('cpu.host'); Title = 'CPU-Auslastung des Hosts'; Run = 'Invoke-ProbePerfCheck'
        Perf = @{ Category = 'Processor Information'; Counters = @('% Processor Time'); Instances = 'total'; MaxInstances = 0 } }
    @{ Id = 'perf.queue'; Signals = @('cpu.queue'); Title = 'Prozessor-Warteschlange'; Run = 'Invoke-ProbePerfCheck'
        Perf = @{ Category = 'System'; Counters = @('Processor Queue Length'); Instances = 'none'; MaxInstances = 0 } }
    @{ Id = 'perf.steal'; Signals = @('cpu.steal'); Title = 'CPU-Wartezeit der VM (VMware)'; Run = 'Invoke-ProbePerfCheck'
        Perf = @{ Category = 'VM Processor'; Counters = @('CPU stolen time'); Instances = 'all'; MaxInstances = 0 } }
    @{ Id = 'perf.memory'; Signals = @('mem.used', 'mem.commit', 'mem.pagesin'); Title = 'Arbeitsspeicher, Zusagen, Seiteneingaben'; Run = 'Invoke-ProbePerfCheck'
        Perf = @{ Category = 'Memory'; Counters = @('Available Bytes', 'Committed Bytes', 'Commit Limit', 'Pages Input/sec'); Instances = 'none'; MaxInstances = 0 } }
    @{ Id = 'perf.disk.total'; Signals = @(); Title = 'Physische Datentraeger gesamt'; Run = 'Invoke-ProbePerfCheck'
        Perf = @{ Category = 'PhysicalDisk'; Counters = @('Disk Read Bytes/sec', 'Disk Write Bytes/sec', 'Disk Reads/sec', 'Disk Writes/sec', 'Current Disk Queue Length'); Instances = 'total'; MaxInstances = 0 } }
    @{ Id = 'perf.network'; Signals = @(); Title = 'Netzwerkdurchsatz je Adapter'; Run = 'Invoke-ProbePerfCheck'
        Perf = @{ Category = 'Network Interface'; Counters = @('Bytes Received/sec', 'Bytes Sent/sec'); Instances = 'all'; MaxInstances = 0 } }
    @{ Id = 'perf.volumes'; Signals = @('disk.latency'); Title = 'Antwortzeiten je Laufwerk'; Run = 'Invoke-ProbeVolumesCheck'
        Perf = @{ Category = 'LogicalDisk'; Counters = @('Avg. Disk sec/Read', 'Avg. Disk sec/Write', 'Disk Reads/sec', 'Disk Writes/sec', 'Disk Read Bytes/sec', 'Disk Write Bytes/sec', 'Current Disk Queue Length'); Instances = 'nototal'; MaxInstances = 0 } }
    @{ Id = 'perf.shares'; Signals = @('smb.latency'); Title = 'Antwortzeiten je SMB-Freigabe'; Run = 'Invoke-ProbePerfCheck'
        Perf = @{ Category = 'SMB Client Shares'; Counters = @('Avg. sec/Read', 'Avg. sec/Write', 'Read Requests/sec', 'Write Requests/sec', 'Read Bytes/sec', 'Write Bytes/sec'); Instances = 'all'; MaxInstances = 0 } }
    @{ Id = 'perf.input.session'; Signals = @('input.session'); Title = 'Eingabeverzoegerung je Sitzung'; Run = 'Invoke-ProbeInputSessionCheck'
        Perf = @{ Category = 'User Input Delay per Session'; Counters = @('Max Input Delay'); Instances = 'all'; MaxInstances = 0 } }
    @{ Id = 'perf.input.process'; Signals = @(); Title = 'Eingabeverzoegerung je Prozess'; Run = 'Invoke-ProbePerfCheck'
        Perf = @{ Category = 'User Input Delay per Process'; Counters = @('Max Input Delay'); Instances = 'all'; MaxInstances = 10 } }
    @{ Id = 'perf.ica'; Signals = @('ica.rtt', 'ica.latency'); Title = 'ICA-Sitzungswerte und Citrix EUEM'; Run = 'Invoke-ProbeIcaCheck'
        Perf = @{ Category = 'ICA Session'; Counters = @(); Instances = 'all'; MaxInstances = 3 } }
    @{ Id = 'profile.volumes'; Signals = @(); Title = 'Eingebundene Profilcontainer'; Run = 'Invoke-ProbeProfileVolumesCheck' }
    @{ Id = 'events.defender'; Signals = @(); Title = 'Ereignisprotokoll Microsoft Defender'; Run = 'Invoke-ProbeEventsCheck'
        Logs = @('Microsoft-Windows-Windows Defender/Operational'); EventIds = @(1000, 1001, 1002, 2000) }
    @{ Id = 'events.applocker'; Signals = @(); Title = 'Ereignisprotokolle AppLocker'; Run = 'Invoke-ProbeEventsCheck'
        Logs = @('Microsoft-Windows-AppLocker/EXE and DLL', 'Microsoft-Windows-AppLocker/MSI and Script'); EventIds = @(8004, 8007) }
    @{ Id = 'security.products'; Signals = @(); Title = 'Prozesse und Dienste in Sitzung 0'; Run = 'Invoke-ProbeSecurityProductsCheck' }
    @{ Id = 'user.processes'; Signals = @(); Title = 'Prozesse in Benutzersitzungen'; Run = 'Invoke-ProbeUserProcessesCheck' }
    @{ Id = 'endpoints'; Signals = @('probe.connect'); Title = 'TCP-Verbindungsaufbau zu den Gegenstellen'; Run = 'Invoke-ProbeEndpointsCheck' }
)

#endregion

#region ---------- main ---------------------------------------------------------------------------

if ($ListChecks) {
    foreach ($c in $script:Catalogue) {
        [pscustomobject]@{ Id = $c.Id; Signals = [string[]]$c.Signals; Title = $c.Title }
    }
    return
}

$onWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
if (-not $onWindows) { throw 'Das Pruefskript laeuft nur unter Windows.' }

if ($EndpointFile -and -not (Test-Path -LiteralPath $EndpointFile -PathType Leaf)) {
    throw "Die Datei fuer -EndpointFile wurde nicht gefunden: $EndpointFile"
}

# Resolve the output file first, so a bad path fails before the checks run.
$fileName = 'WorkerPerf-Quellen_{0}_{1}.json' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmmss')
if ([string]::IsNullOrEmpty($OutFile)) { $OutFile = (Get-Location).ProviderPath }
$target = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
if ((Test-Path -LiteralPath $target -PathType Container) -or -not $target.EndsWith('.json', [StringComparison]::OrdinalIgnoreCase)) {
    if (-not (Test-Path -LiteralPath $target)) { $null = New-Item -ItemType Directory -Path $target }
    $target = Join-Path $target $fileName
}
else {
    $parent = Split-Path -Parent $target
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent }
}

$ctx = @{
    Users = @(); Sessions = @(); WtsCompiled = $false; WtsError = ''
    Processes = $null; Services = $null; FileInfo = @{}
    CimPerfClasses = $null; CimPerfError = ''
    InputSeconds = $InputSeconds
    EndpointFile = ''
}
if ($EndpointFile) { $ctx.EndpointFile = (Resolve-Path -LiteralPath $EndpointFile).ProviderPath }

# Sessions first: their user names are needed to mask every later result.
try {
    if (-not ('WorkerPerfProbe.Wts' -as [type])) { Add-Type -TypeDefinition $script:WtsSource -Language CSharp }
    $ctx.WtsCompiled = $true
    $ctx.Sessions = @([WorkerPerfProbe.Wts]::GetSessions())
}
catch { $ctx.WtsError = Get-ProbeErrorText $_ }
$users = New-Object 'System.Collections.Generic.List[string]'
foreach ($s in $ctx.Sessions) { if (-not [string]::IsNullOrEmpty($s.User)) { $users.Add([string]$s.User) } }
if ($env:USERNAME) { $users.Add($env:USERNAME) }
$script:ProbeUsers = $users.ToArray()
$ctx.Users = $script:ProbeUsers

$isElevated = $false
try {
    $principal = New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())
    $isElevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
catch { $isElevated = $false }
if (-not $isElevated) { Write-Warning 'Konsole ohne erhoehte Rechte: einige Pruefungen liefern weniger Daten.' }

$os = ''
try {
    $o = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $os = '{0} {1}' -f $o.Caption, $o.Version
}
catch { $os = 'unbekannt' }

$results = New-Object 'System.Collections.Generic.List[object]'
$n = 0
foreach ($c in $script:Catalogue) {
    $n++
    Write-Host ('[{0,2}/{1}] {2} - {3}' -f $n, $script:Catalogue.Count, $c.Id, $c.Title)
    $r = [ordered]@{ Id = $c.Id; Signals = [string[]]$c.Signals; Title = $c.Title; Ok = $false; Detail = ''; Data = $null }
    try {
        $out = @(& $c.Run $ctx $c)[-1]
        $r.Ok = [bool]$out.Ok
        $r.Detail = [string]$out.Detail
        $r.Data = $out.Data
    }
    catch { $r.Detail = Get-ProbeErrorText $_ }
    $r.Detail = Hide-ProbeText $r.Detail
    $results.Add($r)
}

$report = [ordered]@{
    SchemaVersion = 1
    Computer      = $env:COMPUTERNAME
    OS            = $os
    PSVersion     = $PSVersionTable.PSVersion.ToString()
    Culture       = (Get-Culture).Name
    UICulture     = (Get-UICulture).Name
    IsElevated    = $isElevated
    Checks        = $results.ToArray()
}
$json = ConvertTo-Json -InputObject $report -Depth 16
[System.IO.File]::WriteAllText($target, $json, (New-Object System.Text.UTF8Encoding $false))

$results | ForEach-Object { [pscustomobject]@{ Id = $_.Id; Ok = $_.Ok; Detail = $_.Detail } } |
    Format-Table -AutoSize -Wrap | Out-Host
Write-Host ('Ergebnis gespeichert: {0}' -f $target)
Write-Host 'Bitte diese Datei zur Auswertung zurueckgeben.'

#endregion
