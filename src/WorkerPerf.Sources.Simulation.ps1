#Requires -Version 5.1
# WorkerPerf simulated data source: a deterministic 60-minute scenario ("Drehbuch") with eight scripted incidents.
# Library: defines constants and functions only. State lives in $script: variables and is built by Initialize-WorkerPerfSource.
# Every value is a pure function of the virtual clock: noise comes from a hash of time and key, cumulative process
# counters from a closed formula (base rate times lifetime plus scripted extra times overlap with its window).

$script:WorkerPerfSimCores = 8
$script:WorkerPerfSimRamMB = 65536
$script:WorkerPerfSimCommitLimitMB = 98304
$script:WorkerPerfSimCollectorPid = 4242
$script:WorkerPerfSimDomain = 'CONTOSO'

# Scenario windows in seconds after the start; a window A-B holds for A < t <= B.
# The memory window ends off the snapshot grid (18:51): the growing process exits between two snapshots, one second
# after the last tick over the threshold, so the last snapshot of the incident no longer contains it.
$script:WorkerPerfSimWindows = [ordered]@{
    homeoffice = @{ A = 0.0; B = 3600.0 }
    cpu        = @{ A = 300.0; B = 420.0 }
    memory     = @{ A = 900.0; B = 1131.0 }
    disk       = @{ A = 1500.0; B = 1590.0 }
    share      = @{ A = 1980.0; B = 2040.0 }
    profile    = @{ A = 2400.0; B = 2460.0 }
    backend    = @{ A = 2820.0; B = 2910.0 }
    hang       = @{ A = 3178.0; B = 3180.0 }
}
# Inside the memory window: RAM ramp ends at 16:00, page reads start at 15:30, C: write latency starts at 16:00.
$script:WorkerPerfSimMemRampEnd = 960.0
$script:WorkerPerfSimPagesFrom = 930.0
$script:WorkerPerfSimBaseRamPct = 57.5
$script:WorkerPerfSimPeakRamPct = 93.0
# Working set the ms-teams.exe of user007 gains by 16:00 (MB): the whole RAM ramp.
$script:WorkerPerfSimTeamsGrowthMB = ($script:WorkerPerfSimPeakRamPct - $script:WorkerPerfSimBaseRamPct) / 100.0 * $script:WorkerPerfSimRamMB

$script:WorkerPerfSimSignalIds = @('cpu.host', 'cpu.queue', 'cpu.steal', 'mem.used', 'mem.commit', 'mem.pagesin', 'input.session',
    'disk.latency', 'smb.latency', 'ica.rtt', 'ica.latency', 'probe.connect')

# Noise: a value in [0, 1) per noise key and whole second. Keys (index into the row of Get-WorkerPerfSimNoise):
#   1-9 host values, 10-29 volumes and shares, 30+sid / 60+sid / 90+sid / 120+sid profile volume read ops, write ops,
#   read and write latency, 150+sid base input delay, 180+sid scripted input delay, 210+sid idle time,
#   240+sid ICA round trip, 300+i probes.
$script:WorkerPerfSimNoiseKeys = 320
$script:WorkerPerfSimNoiseSize = 4096
$script:WorkerPerfSimNoiseValues = $null
$script:WorkerPerfSimNoiseOffsets = $null

function Initialize-WorkerPerfSimNoise {
    # Two fixed hash tables (xorshift hash of the index, no running generator), built once: noise values and a start
    # offset per second. A second's row is a slice of the values, so noise stays a pure function of time and key.
    if ($null -ne $script:WorkerPerfSimNoiseValues) { return }
    $n = $script:WorkerPerfSimNoiseSize
    $keys = $script:WorkerPerfSimNoiseKeys
    $mask = 4294967295
    $hash = New-Object double[] (2 * $n + $keys)
    for ($i = 0; $i -lt $hash.Length; $i++) {
        $x = ([long]$i * 2654435761 + 12345) % 4294967296
        for ($r = 0; $r -lt 2; $r++) {
            $x = $x -bxor (($x -shl 13) -band $mask)
            $x = $x -bxor ($x -shr 17)
            $x = $x -bxor (($x -shl 5) -band $mask)
        }
        $hash[$i] = [double]$x / 4294967296.0
    }
    $values = New-Object double[] ($n + $keys)
    [Array]::Copy($hash, 0, $values, 0, $values.Length)
    $offsets = New-Object int[] $n
    for ($i = 0; $i -lt $n; $i++) { $offsets[$i] = [int][Math]::Floor($hash[$n + $keys + $i] * $n) }
    $script:WorkerPerfSimNoiseValues = $values
    $script:WorkerPerfSimNoiseOffsets = $offsets
}

function Get-WorkerPerfSimNoise([double]$Seconds) {
    # The noise of all keys at the whole second of a point in time, as one row (one call per sample keeps it cheap).
    $n = $script:WorkerPerfSimNoiseSize
    $sec = [long][Math]::Floor($Seconds) % $n
    if ($sec -lt 0) { $sec += $n }
    $row = New-Object double[] $script:WorkerPerfSimNoiseKeys
    [Array]::Copy($script:WorkerPerfSimNoiseValues, $script:WorkerPerfSimNoiseOffsets[$sec], $row, 0, $row.Length)
    return , $row
}

function Test-WorkerPerfSimWindow([string]$Key, [double]$Seconds) {
    $w = $script:WorkerPerfSimWindows[$Key]
    return ($Seconds -gt $w.A -and $Seconds -le $w.B)
}

function Get-WorkerPerfSimOverlap([double]$Seconds, [double]$A, [double]$B) {
    # Seconds of the window A-B that lie before the point in time.
    if ($Seconds -le $A) { return 0.0 }
    if ($Seconds -ge $B) { return $B - $A }
    return $Seconds - $A
}

function Get-WorkerPerfSimElapsed {
    return ($script:WorkerPerfSimNow - $script:WorkerPerfSimStart).TotalSeconds
}

function Get-WorkerPerfSimTeamsGrowthMB([double]$Seconds) {
    $w = $script:WorkerPerfSimWindows['memory']
    if (-not ($Seconds -gt $w.A -and $Seconds -le $w.B)) { return 0.0 }
    $frac = ($Seconds - $w.A) / ($script:WorkerPerfSimMemRampEnd - $w.A)
    if ($frac -gt 1) { $frac = 1.0 }
    return $script:WorkerPerfSimTeamsGrowthMB * $frac
}

function New-WorkerPerfSimProcess {
    param([int]$ProcessId, [int]$ParentId, [string]$Name, [int]$SessionId, [double]$CreatedSec, [string]$Path,
          [double]$Cores = 0, [double]$ReadBps = 0, [double]$WriteBps = 0, [double]$WsMB = 10, [int]$Handles = 200, [int]$Threads = 8,
          [double]$EndSec = [double]::PositiveInfinity, [string]$Arguments = '')
    $cmd = $(if ($Arguments) { '"' + $Path + '" ' + $Arguments } else { '"' + $Path + '"' })
    return @{
        Pid = $ProcessId; ParentId = $ParentId; Name = $Name; SessionId = $SessionId; CreatedSec = $CreatedSec; EndSec = $EndSec
        Created = $script:WorkerPerfSimStart.AddSeconds($CreatedSec); Path = $Path; CommandLine = $cmd
        Cores = $Cores; Rd = $ReadBps; Wr = $WriteBps; WsBytes = $WsMB * 1MB; Handles = $Handles; Threads = $Threads
        Extra = (New-Object System.Collections.Generic.List[object]); Grow = $false
    }
}

function Add-WorkerPerfSimExtra($Proc, [string]$Window, [double]$Cores = 0, [double]$ReadBps = 0, [double]$WriteBps = 0) {
    $w = $script:WorkerPerfSimWindows[$Window]
    $Proc.Extra.Add(@{ A = [double]$w.A; B = [double]$w.B; Cores = $Cores; Rd = $ReadBps; Wr = $WriteBps })
}

function Initialize-WorkerPerfSource {
    param([datetime]$StartTime, [object[]]$Endpoints = @(), [string]$CitrixMetricFilter = '', [switch]$IncludeCommandLine, [switch]$NoCitrix)

    if ($null -eq $StartTime -or $StartTime -eq [datetime]::MinValue) {
        $n = [datetime]::Now
        $StartTime = $n.AddTicks(-($n.Ticks % [TimeSpan]::TicksPerSecond))
    }
    $script:WorkerPerfSimStart = $StartTime
    $script:WorkerPerfSimNow = $StartTime
    $script:WorkerPerfSimProbe = $null
    Initialize-WorkerPerfSimNoise
    $script:WorkerPerfSimIncludeCommandLine = [bool]$IncludeCommandLine
    $script:WorkerPerfSimCitrixMetrics = @(@('RoundtripTime', 'NetworkLatency') | Where-Object {
            -not $NoCitrix -and ([string]::IsNullOrEmpty($CitrixMetricFilter) -or $_ -match $CitrixMetricFilter) })

    $script:WorkerPerfSimEndpoints = [object[]]@(
        [pscustomobject]@{ Name = 'Oracle-Listener'; Host = 'ora01.sim.local'; Port = 1521; Role = 'Datenbank' }
        [pscustomobject]@{ Name = 'FortiGate-Proxy'; Host = 'proxy.sim.local'; Port = 8080; Role = 'Proxy' }
        [pscustomobject]@{ Name = 'Dateiserver'; Host = 'fs01.sim.local'; Port = 445; Role = 'Dateiserver' })

    # ---- sessions: user001..user025 with the ids 2..26, all logged on before the start ----
    $sessions = New-Object System.Collections.Generic.List[object]
    for ($sid = 2; $sid -le 26; $sid++) {
        $sessions.Add(@{ Sid = $sid; User = ('user{0:d3}' -f ($sid - 1)); Client = ('WS-{0:d4}' -f (1000 + $sid * 37))
                LogonSec = -5400.0 + $sid * 60; WinStation = ('ICA-CGP#{0}' -f ($sid - 1)) })
    }
    $script:WorkerPerfSimSessions = $sessions.ToArray()

    # ---- processes ----
    $procs = New-Object System.Collections.Generic.List[object]
    $services = @{}
    $boot = -259200.0
    $sys32 = 'C:\Windows\System32\'
    # name, services, cores, read B/s, write B/s, working set MB, handles, threads
    $catalog0 = @(
        @('System', '', 0.04, 20KB, 40KB, 1, 3000, 180), @('Registry', '', 0, 0, 0, 60, 0, 4), @('smss.exe', '', 0, 0, 0, 1, 50, 2),
        @('csrss.exe', '', 0.01, 0, 0, 6, 700, 12), @('wininit.exe', '', 0, 0, 0, 7, 170, 1), @('services.exe', '', 0.01, 0, 0, 12, 900, 9),
        @('lsass.exe', '', 0.02, 2KB, 1KB, 28, 1700, 11), @('svchost.exe', 'DcomLaunch;PlugPlay;Power', 0, 0, 0, 24, 1400, 14),
        @('svchost.exe', 'RpcEptMapper;RpcSs', 0.01, 0, 0, 14, 1200, 12), @('svchost.exe', 'AppIDSvc', 0, 0, 0, 9, 220, 6),
        @('svchost.exe', 'Dnscache', 0.005, 0, 0, 11, 300, 7), @('svchost.exe', 'EventLog', 0.01, 1KB, 6KB, 22, 600, 15),
        @('svchost.exe', 'LanmanWorkstation', 0.02, 4KB, 2KB, 16, 500, 18), @('svchost.exe', 'Schedule', 0, 0, 0, 18, 520, 10),
        @('svchost.exe', 'Winmgmt', 0.03, 1KB, 1KB, 30, 900, 16), @('svchost.exe', 'TermService', 0.04, 1KB, 1KB, 40, 1500, 30),
        @('svchost.exe', 'gpsvc', 0, 0, 0, 12, 330, 8), @('svchost.exe', 'BITS', 0, 0, 0, 13, 300, 6),
        @('svchost.exe', 'wuauserv', 0, 0, 0, 20, 450, 9), @('spoolsv.exe', 'Spooler', 0, 0, 0, 16, 480, 11),
        @('MsMpEng.exe', 'WinDefend', 0.25, 300KB, 20KB, 260, 1300, 45), @('NisSrv.exe', 'WdNisSvc', 0, 0, 0, 12, 250, 7),
        @('BrokerAgent.exe', 'BrokerAgent', 0.03, 2KB, 2KB, 70, 800, 25), @('picaSvc2.exe', 'PorticaService', 0.02, 0, 0, 25, 400, 14),
        @('CtxSvcHost.exe', 'CitrixHealthMon', 0, 0, 0, 20, 300, 9), @('UserProfileManager.exe', 'ctxProfile', 0.01, 8KB, 4KB, 35, 600, 20),
        @('WmiPrvSE.exe', '', 0.03, 0, 0, 30, 500, 12), @('winlogon.exe', '', 0, 0, 0, 9, 260, 4))
    $nextPid = 4
    $winlogonPid = 0
    $i = 0
    foreach ($c in $catalog0) {
        $p = New-WorkerPerfSimProcess -ProcessId $nextPid -ParentId 600 -Name $c[0] -SessionId 0 -CreatedSec ($boot + $i * 2) -Path ($sys32 + $c[0]) `
            -Cores $c[2] -ReadBps $c[3] -WriteBps $c[4] -WsMB $c[5] -Handles $c[6] -Threads $c[7] -Arguments $(if ($c[1]) { '-k ' + $c[1] } else { '' })
        if ($c[0] -eq 'System') { $p.Path = ''; $p.CommandLine = '' }
        if ($c[0] -eq 'MsMpEng.exe') {
            $p.Path = 'C:\ProgramData\Microsoft\Windows Defender\Platform\4.18.24090.11-0\MsMpEng.exe'; $p.CommandLine = '"' + $p.Path + '"'
            Add-WorkerPerfSimExtra $p 'disk' -Cores 0.39 -ReadBps 30MB
        }
        if ($c[1]) { $services[$nextPid] = [string]$c[1] }
        if ($c[0] -eq 'winlogon.exe') { $winlogonPid = $nextPid }
        $procs.Add($p)
        $i++
        $nextPid = 100 + $i * 64
    }
    $collector = New-WorkerPerfSimProcess -ProcessId $script:WorkerPerfSimCollectorPid -ParentId $winlogonPid -Name 'powershell.exe' -SessionId 0 -CreatedSec -120 `
        -Path ($sys32 + 'WindowsPowerShell\v1.0\powershell.exe') -Cores 0.08 -ReadBps 1KB -WriteBps 12KB -WsMB 110 -Handles 900 -Threads 22 `
        -Arguments '-NoProfile -File Start-WorkerPerfCapture.ps1 -Simulate'
    $procs.Add($collector)
    $procs.Add((New-WorkerPerfSimProcess -ProcessId 4250 -ParentId $script:WorkerPerfSimCollectorPid -Name 'conhost.exe' -SessionId 0 -CreatedSec -119 `
                -Path ($sys32 + 'conhost.exe') -WsMB 8 -Handles 110 -Threads 3 -Arguments '0xffffffff -ForceV1'))

    $office = 'C:\Program Files\Microsoft Office\root\Office16\'
    $chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
    # name, path, cores, read B/s, write B/s, working set MB, handles, threads
    $catalog = @(
        @('explorer.exe', 'C:\Windows\explorer.exe', 0, 0, 0, 80, 1800, 60),
        @('nexus.exe', 'C:\Program Files\Nexus\nexus.exe', 0.02, 20KB, 6KB, 180, 900, 40),
        @('chrome.exe', $chrome, 0.025, 30KB, 15KB, 160, 1200, 35), @('chrome.exe', $chrome, 0, 0, 0, 110, 300, 18),
        @('chrome.exe', $chrome, 0, 0, 0, 90, 250, 16), @('chrome.exe', $chrome, 0, 0, 0, 70, 220, 14),
        @('OUTLOOK.EXE', ($office + 'OUTLOOK.EXE'), 0.01, 15KB, 8KB, 200, 2500, 50),
        @('WINWORD.EXE', ($office + 'WINWORD.EXE'), 0, 0, 0, 90, 1100, 25),
        @('EXCEL.EXE', ($office + 'EXCEL.EXE'), 0, 0, 0, 100, 1000, 24),
        @('ms-teams.exe', 'C:\Program Files\WindowsApps\MSTeams_x64\ms-teams.exe', 0.035, 10KB, 10KB, 300, 1500, 45))
    $pidOf = @{}
    foreach ($s in $script:WorkerPerfSimSessions) {
        $sid = [int]$s.Sid
        $explorerPid = 5000 + $sid * 100
        for ($k = 0; $k -lt $catalog.Count; $k++) {
            $c = $catalog[$k]
            $parent = $(if ($k -eq 0) { $winlogonPid } else { $explorerPid })
            $p = New-WorkerPerfSimProcess -ProcessId ($explorerPid + $k * 4) -ParentId $parent -Name $c[0] -SessionId $sid `
                -CreatedSec ($s.LogonSec + 5 + $k * 7) -Path $c[1] -Cores $c[2] -ReadBps $c[3] -WriteBps $c[4] -WsMB $c[5] -Handles $c[6] -Threads $c[7]
            $key = '{0}|{1}' -f $sid, $c[0]
            if (-not $pidOf.ContainsKey($key)) { $pidOf[$key] = $p.Pid }
            if ($sid -eq 4 -and $c[0] -eq 'EXCEL.EXE') { Add-WorkerPerfSimExtra $p 'cpu' -Cores 4.8 }
            if ($sid -eq 6 -and $c[0] -eq 'WINWORD.EXE') { Add-WorkerPerfSimExtra $p 'share' -Cores 0.05 -ReadBps 20MB }
            if ($sid -eq 10 -and $c[0] -eq 'OUTLOOK.EXE') { Add-WorkerPerfSimExtra $p 'profile' -Cores 0.04 -ReadBps 6MB -WriteBps 4MB }
            if ($sid -eq 8 -and $c[0] -eq 'ms-teams.exe') {
                # grows in the memory window and is restarted at its end: the new instance follows below
                $p.EndSec = [double]$script:WorkerPerfSimWindows['memory'].B
                $p.Grow = $true
                Add-WorkerPerfSimExtra $p 'memory' -Cores 0.2
                $procs.Add($p)
                $p = New-WorkerPerfSimProcess -ProcessId ($explorerPid + 60) -ParentId $explorerPid -Name $c[0] -SessionId $sid `
                    -CreatedSec $p.EndSec -Path $c[1] -Cores $c[2] -ReadBps $c[3] -WriteBps $c[4] -WsMB $c[5] -Handles $c[6] -Threads $c[7]
            }
            $procs.Add($p)
        }
        if ($sid -eq 12) {
            $w = $script:WorkerPerfSimWindows['disk']
            $procs.Add((New-WorkerPerfSimProcess -ProcessId ($explorerPid + 64) -ParentId $explorerPid -Name 'robocopy.exe' -SessionId $sid `
                        -CreatedSec $w.A -EndSec $w.B -Path ($sys32 + 'Robocopy.exe') -Cores 0.1 -ReadBps 40MB -WriteBps 40MB -WsMB 40 -Handles 150 -Threads 9 `
                        -Arguments 'D:\Projekte D:\Archiv /MIR'))
        }
    }
    $script:WorkerPerfSimProcs = $procs.ToArray()
    $script:WorkerPerfSimServices = $services
    $script:WorkerPerfSimPidOf = $pidOf

    # CPU of the host: permanent base load plus segments (short-lived processes and scripted extras).
    $base = 0.0
    $segments = New-Object System.Collections.Generic.List[object]
    foreach ($p in $script:WorkerPerfSimProcs) {
        if ($p.CreatedSec -lt 0 -and [double]::IsPositiveInfinity($p.EndSec)) { $base += $p.Cores }
        elseif ($p.Cores -gt 0) { $segments.Add(@{ A = $p.CreatedSec; B = $p.EndSec; Cores = $p.Cores }) }
        foreach ($x in $p.Extra) { if ($x.Cores -gt 0) { $segments.Add(@{ A = $x.A; B = $x.B; Cores = $x.Cores }) } }
    }
    $script:WorkerPerfSimBaseCores = $base
    $script:WorkerPerfSimCpuSegments = $segments.ToArray()

    # Scripted input delay: window, sessions, application with the per-process rows, delay range.
    $inputScript = @(
        @{ W = 'cpu'; Sids = @(2, 3, 4, 5, 6, 7); App = 'EXCEL.EXE'; Low = 300; High = 600 }
        @{ W = 'memory'; Sids = @(8, 9, 10, 11); App = 'chrome.exe'; Low = 200; High = 400 }
        @{ W = 'disk'; Sids = @(12); App = 'explorer.exe'; Low = 250; High = 250 }
        @{ W = 'share'; Sids = @(6); App = 'WINWORD.EXE'; Low = 300; High = 300 }
        @{ W = 'profile'; Sids = @(10); App = 'OUTLOOK.EXE'; Low = 400; High = 400 }
        @{ W = 'backend'; Sids = @(13, 14, 15, 16, 17, 18, 19, 20); App = 'nexus.exe'; Low = 1200; High = 1200 }
        @{ W = 'hang'; Sids = @(15); App = 'WINWORD.EXE'; Low = 800; High = 800 })
    $bySid = @{}
    foreach ($s in $script:WorkerPerfSimSessions) { $bySid[[int]$s.Sid] = New-Object System.Collections.Generic.List[object] }
    foreach ($row in $inputScript) {
        $w = $script:WorkerPerfSimWindows[$row.W]
        foreach ($sid in $row.Sids) {
            $bySid[$sid].Add(@{ A = [double]$w.A; B = [double]$w.B; Pid = [int]$pidOf['{0}|{1}' -f $sid, $row.App]; App = $row.App
                    Low = [double]$row.Low; High = [double]$row.High })
        }
    }
    $script:WorkerPerfSimInputBySid = $bySid

    $script:WorkerPerfSimEvents = @(
        @{ Sec = 1490.0; Source = 'Defender'; EventId = 1000; Kind = 'scan-start'; Text = 'Microsoft Defender Antivirus scan has started.' }
        @{ Sec = 1620.0; Source = 'Defender'; EventId = 1001; Kind = 'scan-end'; Text = 'Microsoft Defender Antivirus scan has finished.' }
        @{ Sec = 1800.0; Source = 'AppLocker'; EventId = 8004; Kind = 'applocker-block'; Text = '%OSDRIVE%\USERS\USER008\DOWNLOADS\TOOL.EXE was prevented from running.' })

    $sources = [ordered]@{}
    foreach ($id in $script:WorkerPerfSimSignalIds) { $sources[$id] = @{ Available = $true; Detail = 'Simulation' } }
    foreach ($id in 'process', 'sessions', 'input.process', 'profile.map', 'events.defender', 'events.applocker') {
        $sources[$id] = @{ Available = $true; Detail = 'Simulation' }
    }
    $sources['probe.connect'].Detail = 'Simulation, 3 Gegenstellen'
    if ($NoCitrix) {
        foreach ($id in 'ica.rtt', 'ica.latency') { $sources[$id] = @{ Available = $false; Detail = 'abgeschaltet (-NoCitrix)' } }
    }

    return @{
        Computer = 'SIM-VDA01'; OS = 'Simulated Windows Server 2022'; LogicalProcessors = $script:WorkerPerfSimCores
        PhysicalMemoryMB = $script:WorkerPerfSimRamMB; CollectorPid = $script:WorkerPerfSimCollectorPid
        Endpoints = $script:WorkerPerfSimEndpoints; Sources = $sources
    }
}

function Get-WorkerPerfNow {
    return $script:WorkerPerfSimNow
}

function Wait-WorkerPerfTick {
    param([datetime]$Until, [string]$StopFlagPath)
    # The virtual clock jumps to the requested time.
    $script:WorkerPerfSimNow = $Until
    if (-not [string]::IsNullOrEmpty($StopFlagPath) -and (Test-Path -LiteralPath $StopFlagPath)) { return $true }
    return $false
}

function New-WorkerPerfSimVolume([string]$Volume, [string]$Kind, $SessionId, [string]$Backing, [double]$ReadLat, [double]$WriteLat,
                                 [double]$ReadOps, [double]$WriteOps, [double]$ReadBps, [double]$WriteBps, [double]$Queue) {
    return [pscustomobject]@{
        Volume = $Volume; Kind = $Kind; SessionId = $SessionId; Backing = $Backing
        ReadLatMs = [Math]::Round($ReadLat, 2); WriteLatMs = [Math]::Round($WriteLat, 2); ReadOps = [Math]::Round($ReadOps); WriteOps = [Math]::Round($WriteOps)
        ReadBps = [Math]::Round($ReadBps); WriteBps = [Math]::Round($WriteBps); Queue = $Queue
    }
}

function Get-WorkerPerfFastSample {
    $e = Get-WorkerPerfSimElapsed
    $nz = Get-WorkerPerfSimNoise $e
    $cores = $script:WorkerPerfSimCores

    # ---- CPU: the same rates the process counters grow by, plus a little noise ----
    $busy = $script:WorkerPerfSimBaseCores
    foreach ($seg in $script:WorkerPerfSimCpuSegments) { if ($e -gt $seg.A -and $e -le $seg.B) { $busy += $seg.Cores } }
    $cpuPct = 100.0 * $busy / $cores + (3 * $nz[1] - 1.5)
    if ($cpuPct -gt 99.5) { $cpuPct = 99.5 }
    $queue = [Math]::Round(1 + 5 * $nz[2])
    if (Test-WorkerPerfSimWindow 'cpu' $e) { $queue = 24 }

    # ---- memory ----
    $inMemory = Test-WorkerPerfSimWindow 'memory' $e
    $growthMB = Get-WorkerPerfSimTeamsGrowthMB $e
    $ramPct = $script:WorkerPerfSimBaseRamPct + (3 * $nz[3] - 1.5)
    if ($inMemory) { $ramPct = $script:WorkerPerfSimBaseRamPct + 100.0 * $growthMB / $script:WorkerPerfSimRamMB }
    $availMB = [Math]::Round($script:WorkerPerfSimRamMB * (1 - $ramPct / 100.0))
    $committedMB = [Math]::Round(40000 + (1600 * $nz[4] - 800) + $growthMB)
    $pagesIn = 4 * $nz[5]
    if ($inMemory -and $e -gt $script:WorkerPerfSimPagesFrom) { $pagesIn = 390 + 20 * $nz[5] }

    # ---- volumes ----
    $volumes = New-Object System.Collections.Generic.List[object]
    $cR = 40 + 40 * $nz[10]; $cW = 30 + 30 * $nz[11]
    $cRl = 1 + 3 * $nz[12]; $cWl = 1.5 + 3.5 * $nz[13]
    $cWb = $cW * 8KB; $cQ = 1
    if ($inMemory -and $e -gt $script:WorkerPerfSimMemRampEnd) { $cW = 300; $cWl = 14.5 + $nz[13]; $cWb = 300 * 32KB; $cQ = 4 }
    $volumes.Add((New-WorkerPerfSimVolume 'C:' 'disk' $null '' $cRl $cWl $cR $cW ($cR * 8KB) $cWb $cQ))

    $dR = 10 + 20 * $nz[14]; $dW = 10 + 20 * $nz[15]
    $dRl = 1 + 3 * $nz[16]; $dWl = 1 + 3 * $nz[17]
    $dRb = $dR * 16KB; $dWb = $dW * 16KB; $dQ = 0
    if (Test-WorkerPerfSimWindow 'disk' $e) {
        $dR = $dR + 100; $dRb = $dRb + 70MB; $dW = 200; $dWl = 58 + 4 * $nz[17]; $dWb = $dWb + 40MB; $dQ = 8
    }
    $volumes.Add((New-WorkerPerfSimVolume 'D:' 'disk' $null '' $dRl $dWl $dR $dW $dRb $dWb $dQ))

    $tick = [long][Math]::Floor($e / 2)
    $slot = $tick % 10
    if ($slot -lt 0) { $slot += 10 }
    $inProfile = Test-WorkerPerfSimWindow 'profile' $e
    foreach ($s in $script:WorkerPerfSimSessions) {
        $sid = [int]$s.Sid
        $name = 'HarddiskVolume{0}' -f ($sid + 8)
        if ($inProfile -and $sid -eq 10) {
            $volumes.Add((New-WorkerPerfSimVolume $name 'profile' $sid '\\fs01\profile$' (44 + 2 * $nz[20]) (44 + 2 * $nz[21]) 30 20 6MB 4MB 3))
        }
        elseif (($sid % 10) -eq $slot) {
            $r = 5 + 15 * $nz[30 + $sid]; $w = 3 + 7 * $nz[60 + $sid]
            $volumes.Add((New-WorkerPerfSimVolume $name 'profile' $sid '\\fs01\profile$' (1 + 4 * $nz[90 + $sid]) (1 + 4 * $nz[120 + $sid]) $r $w ($r * 8KB) ($w * 8KB) 0))
        }
    }

    # ---- shares ----
    $aR = 10 + 30 * $nz[22]; $aW = 5 + 10 * $nz[23]
    $aRl = 1 + 4 * $nz[24]; $aWl = 1 + 4 * $nz[25]; $aRb = $aR * 16KB
    if (Test-WorkerPerfSimWindow 'share' $e) { $aR = 100; $aRl = 78 + 4 * $nz[24]; $aRb = 20MB }
    $pR = 10 + 20 * $nz[26]; $pW = 5 + 10 * $nz[27]
    $shares = [object[]]@(
        [pscustomobject]@{ Share = '\\fs01\daten'; ReadLatMs = [Math]::Round($aRl, 2); WriteLatMs = [Math]::Round($aWl, 2); ReadOps = [Math]::Round($aR)
            WriteOps = [Math]::Round($aW); ReadBps = [Math]::Round($aRb); WriteBps = [Math]::Round($aW * 16KB) }
        [pscustomobject]@{ Share = '\\fs01\profile$'; ReadLatMs = [Math]::Round((1 + 4 * $nz[28]), 2)
            WriteLatMs = [Math]::Round((1 + 4 * $nz[29]), 2); ReadOps = [Math]::Round($pR); WriteOps = [Math]::Round($pW)
            ReadBps = [Math]::Round($pR * 16KB); WriteBps = [Math]::Round($pW * 16KB) })

    # ---- input delay per session and, in the scripted windows, per process ----
    $inSessions = New-Object System.Collections.Generic.List[object]
    $inProcs = New-Object System.Collections.Generic.List[object]
    foreach ($s in $script:WorkerPerfSimSessions) {
        $sid = [int]$s.Sid
        $delay = [Math]::Round(40 * $nz[150 + $sid])
        foreach ($x in $script:WorkerPerfSimInputBySid[$sid]) {
            if ($e -gt $x.A -and $e -le $x.B) {
                $delay = [Math]::Round($x.Low + ($x.High - $x.Low) * $nz[180 + $sid])
                $inProcs.Add([pscustomobject]@{ SessionId = $sid; Pid = $x.Pid; Name = $x.App; DelayMs = $delay })
            }
        }
        $inSessions.Add([pscustomobject]@{ SessionId = $sid; DelayMs = $delay })
    }

    $diskR = 0.0; $diskW = 0.0; $opsR = 0.0; $opsW = 0.0; $diskQ = 0.0
    foreach ($v in $volumes) { $diskR += $v.ReadBps; $diskW += $v.WriteBps; $opsR += $v.ReadOps; $opsW += $v.WriteOps; $diskQ += $v.Queue }
    $netR = (1.5MB + 1.5MB * $nz[6]) + $shares[0].ReadBps + $shares[1].ReadBps
    $netS = (0.8MB + 0.8MB * $nz[7]) + $shares[0].WriteBps + $shares[1].WriteBps

    return [pscustomobject]@{
        Time = $script:WorkerPerfSimNow
        CpuPct = [Math]::Round($cpuPct, 2); ProcQueue = $queue; StealPct = [Math]::Round((0.1 + 0.7 * $nz[8]), 2)
        MemAvailMB = $availMB; MemCommittedMB = $committedMB; MemCommitLimitMB = $script:WorkerPerfSimCommitLimitMB
        PagesInPerSec = [Math]::Round($pagesIn, 1)
        DiskReadBps = [Math]::Round($diskR); DiskWriteBps = [Math]::Round($diskW)
        DiskReadIops = [Math]::Round($opsR / 2, 1); DiskWriteIops = [Math]::Round($opsW / 2, 1); DiskQueue = $diskQ
        NetRecvBps = [Math]::Round($netR); NetSentBps = [Math]::Round($netS)
        Volumes = $volumes.ToArray(); Shares = $shares; InputSessions = $inSessions.ToArray(); InputProcesses = $inProcs.ToArray()
    }
}

function Get-WorkerPerfSnapshot {
    param([string]$Kind = 'R')
    # Kind (K, R, B) is part of the interface; the simulation does not need it.
    $e = Get-WorkerPerfSimElapsed
    $nz = Get-WorkerPerfSimNoise $e
    $now = $script:WorkerPerfSimNow
    $withCmd = $script:WorkerPerfSimIncludeCommandLine

    $procs = New-Object System.Collections.Generic.List[object]
    foreach ($p in $script:WorkerPerfSimProcs) {
        if (-not ($e -gt $p.CreatedSec -and $e -le $p.EndSec)) { continue }
        $life = $e - $p.CreatedSec
        $cpu = $p.Cores * $life; $rd = $p.Rd * $life; $wr = $p.Wr * $life
        foreach ($x in $p.Extra) {
            $o = Get-WorkerPerfSimOverlap $e $x.A $x.B
            $cpu += $x.Cores * $o; $rd += $x.Rd * $o; $wr += $x.Wr * $o
        }
        $ws = $p.WsBytes
        if ($p.Grow) { $ws += (Get-WorkerPerfSimTeamsGrowthMB $e) * 1MB }
        $cpu100 = [Math]::Floor($cpu * 1e7)
        $user = [Math]::Floor($cpu100 * 0.8)
        $rd = [Math]::Floor($rd); $wr = [Math]::Floor($wr)
        $procs.Add([pscustomobject]@{
                ProcessId = $p.Pid; ParentProcessId = $p.ParentId; Name = $p.Name; SessionId = $p.SessionId
                KernelModeTime = [uint64]($cpu100 - $user); UserModeTime = [uint64]$user
                WorkingSetSize = [uint64][Math]::Floor($ws); PrivatePageCount = [uint64][Math]::Floor($ws * 1.2)
                ReadTransferCount = [uint64]$rd; WriteTransferCount = [uint64]$wr
                ReadOperationCount = [uint64][Math]::Floor($rd / 16384); WriteOperationCount = [uint64][Math]::Floor($wr / 16384)
                HandleCount = $p.Handles; ThreadCount = $p.Threads; CreationDate = $p.Created; ExecutablePath = $p.Path
                CommandLine = $(if ($withCmd) { $p.CommandLine } else { $null })
            })
    }

    $sessions = New-Object System.Collections.Generic.List[object]
    $sessions.Add([pscustomobject]@{ SessionId = 0; State = 'Disconnected'; WinStation = 'Services'; User = ''; Domain = ''; ClientName = ''
            LogonTime = [datetime]::MinValue; IdleSec = -1 })
    $citrix = New-Object System.Collections.Generic.List[object]
    foreach ($s in $script:WorkerPerfSimSessions) {
        $sid = [int]$s.Sid
        $sessions.Add([pscustomobject]@{ SessionId = $sid; State = 'Active'; WinStation = $s.WinStation; User = $s.User
                Domain = $script:WorkerPerfSimDomain; ClientName = $s.Client; LogonTime = $script:WorkerPerfSimStart.AddSeconds($s.LogonSec)
                IdleSec = [Math]::Round(30 * $nz[210 + $sid]) })
        $rtt = 20 + 40 * $nz[240 + $sid]
        if ($sid -eq 21 -and (Test-WorkerPerfSimWindow 'homeoffice' $e)) { $rtt = 215 + 10 * $nz[240 + $sid] }
        $rtt = [Math]::Round($rtt)
        foreach ($m in $script:WorkerPerfSimCitrixMetrics) {
            $v = $(if ($m -eq 'RoundtripTime') { $rtt } else { [Math]::Round($rtt * 0.6) })
            $citrix.Add([pscustomobject]@{ Source = 'Citrix_Euem_RoundTrip'; SessionId = $sid; Instance = ''; Metric = $m; Value = [double]$v })
        }
    }

    return @{ Time = $now; Processes = $procs.ToArray(); Sessions = $sessions.ToArray(); Citrix = $citrix.ToArray() }
}

function Get-WorkerPerfServices {
    # PID -> 'Service1;Service2' (a copy, so callers cannot change the scenario).
    return $script:WorkerPerfSimServices.Clone()
}

function Start-WorkerPerfProbes {
    param([object[]]$Endpoints)
    # The built-in endpoints are always probed; -Endpoints exists for interface compatibility only.
    $e = Get-WorkerPerfSimElapsed
    $nz = Get-WorkerPerfSimNoise $e
    $results = New-Object System.Collections.Generic.List[object]
    $i = 0
    foreach ($ep in $script:WorkerPerfSimEndpoints) {
        $ms = 2 + 6 * $nz[300 + $i]
        if ($ep.Name -eq 'Oracle-Listener' -and (Test-WorkerPerfSimWindow 'backend' $e)) { $ms = 340 + 20 * $nz[300 + $i] }
        $results.Add([pscustomobject]@{ Name = $ep.Name; Role = $ep.Role; Host = $ep.Host; Port = $ep.Port; ConnectMs = [Math]::Round($ms, 1); Error = '' })
        $i++
    }
    $script:WorkerPerfSimProbe = @{ Time = $script:WorkerPerfSimNow; Results = $results.ToArray() }
}

function Receive-WorkerPerfProbes {
    # Results of the probes started earlier, once the clock has moved on; nothing while they are open.
    $pending = $script:WorkerPerfSimProbe
    if ($null -eq $pending -or $script:WorkerPerfSimNow -le $pending.Time) { return }
    $script:WorkerPerfSimProbe = $null
    $pending.Results
}

function Get-WorkerPerfEvents {
    param([datetime]$Since)
    foreach ($ev in $script:WorkerPerfSimEvents) {
        $t = $script:WorkerPerfSimStart.AddSeconds($ev.Sec)
        if ($t -gt $Since -and $t -le $script:WorkerPerfSimNow) {
            [pscustomobject]@{ Time = $t; Source = $ev.Source; EventId = $ev.EventId; Kind = $ev.Kind; Text = $ev.Text }
        }
    }
}

function Get-WorkerPerfFreeSpaceMB {
    param([string]$Path)
    return [double]100000
}

function Get-WorkerPerfExpected {
    # Simulation only: the incidents the analysis must find, sorted by start.
    $startMs = ([DateTimeOffset]$script:WorkerPerfSimStart).ToUnixTimeMilliseconds()
    $rows = @(
        @{ Key = 'homeoffice'; Type = 'umfeld'; Lead = $null; Chronic = $true; MainApp = $null; MainUser = $null; Affected = 0; DelayApp = $null; Endpoint = $null; Companion = $null }
        @{ Key = 'cpu'; Type = 'engpass'; Lead = 'cpu'; Chronic = $false; MainApp = 'EXCEL.EXE'; MainUser = 'user003'; Affected = 6; DelayApp = $null; Endpoint = $null; Companion = $null }
        @{ Key = 'memory'; Type = 'engpass'; Lead = 'memory'; Chronic = $false; MainApp = 'ms-teams.exe'; MainUser = 'user007'; Affected = 4; DelayApp = $null; Endpoint = $null; Companion = $null }
        @{ Key = 'disk'; Type = 'engpass'; Lead = 'disk'; Chronic = $false; MainApp = 'robocopy.exe'; MainUser = 'user011'; Affected = 1; DelayApp = $null; Endpoint = $null; Companion = 'Microsoft Defender' }
        @{ Key = 'share'; Type = 'engpass'; Lead = 'share'; Chronic = $false; MainApp = 'WINWORD.EXE'; MainUser = 'user005'; Affected = 1; DelayApp = $null; Endpoint = $null; Companion = $null }
        @{ Key = 'profile'; Type = 'engpass'; Lead = 'profile'; Chronic = $false; MainApp = 'OUTLOOK.EXE'; MainUser = 'user009'; Affected = 1; DelayApp = $null; Endpoint = $null; Companion = $null }
        @{ Key = 'backend'; Type = 'ohne-engpass'; Lead = $null; Chronic = $false; MainApp = $null; MainUser = $null; Affected = 8; DelayApp = 'nexus.exe'; Endpoint = 'Oracle-Listener'; Companion = $null }
        @{ Key = 'hang'; Type = 'ohne-engpass'; Lead = $null; Chronic = $false; MainApp = $null; MainUser = $null; Affected = 1; DelayApp = $null; Endpoint = $null; Companion = $null })
    $out = foreach ($r in $rows) {
        $w = $script:WorkerPerfSimWindows[$r.Key]
        [pscustomobject][ordered]@{
            Key = $r.Key; Type = $r.Type; Lead = $r.Lead; Chronic = $r.Chronic
            StartMs = [long]($startMs + [long]($w.A * 1000)); EndMs = [long]($startMs + [long]($w.B * 1000))
            MainApp = $r.MainApp; MainUser = $r.MainUser; Affected = $r.Affected; DelayApp = $r.DelayApp; Endpoint = $r.Endpoint; Companion = $r.Companion
        }
    }
    $out | Sort-Object -Property StartMs
}
