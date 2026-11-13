#Requires -Version 5.1
# WorkerPerf simulated data source: a deterministic 60-minute scenario ("Drehbuch") with eight scripted incidents.
# Library: defines constants and functions only. State lives in $script: variables and is built by Initialize-WorkerPerfSource.
# Every value is a pure function of the virtual clock: noise comes from a hash of time and key, cumulative process
# counters from a closed formula (base rate times lifetime plus scripted extra times overlap with its window).

# The scenes take log, provider, group and kind of every event from the event catalogue (events.json).
. (Join-Path $PSScriptRoot 'WorkerPerf.EventConfig.ps1')
$script:WorkerPerfSimEventFile = Join-Path $PSScriptRoot 'events.json'

$script:WorkerPerfSimCores = 8
$script:WorkerPerfSimRamMB = 65536
$script:WorkerPerfSimCommitLimitMB = 98304
# Committed memory at rest (MB): the base of the fast sample and the commit charge of the health picture.
$script:WorkerPerfSimBaseCommitMB = 40000
# The one Teams installation of the simulated worker: the running ms-teams.exe and the installed file of the health picture.
$script:WorkerPerfSimTeamsPath = 'C:\Program Files\WindowsApps\MSTeams_24277.3502.3161.3007_x64__8wekyb3d8bbwe\ms-teams.exe'
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

function New-WorkerPerfSimEvent {
    # One scripted event with every field of ConvertTo-WorkerPerfEventRecord, at Sec seconds after the start (negative:
    # before it). Log, Source, Group and Kind come from the catalogue entry of log, provider and id, so the scenes and
    # events.json cannot drift apart; an event the catalogue does not know is an error of the scenario.
    param($Config, [double]$Sec, [string]$LogId, [string]$Provider, [int]$EventId, [int]$Level, [string]$Text,
          [string]$App = '', [string]$AppVersion = '', [string]$Module = '', [string]$ModuleVersion = '', [string]$Code = '',
          $ProcessId = $null, $SessionId = $null, [string]$User = '')
    $entry = Resolve-WorkerPerfEventEntry $Config $LogId $Provider $EventId
    if ($null -eq $entry) { throw ('Simulation: Ereignis {0} {1} im Protokoll {2} fehlt in events.json.' -f $Provider, $EventId, $LogId) }
    return @{
        Sec = $Sec; Log = $entry.log; Source = $entry.provider; EventId = $EventId; Level = $Level; Group = $entry.group; Kind = $entry.kind
        App = $App; AppVersion = $AppVersion; Module = $Module; ModuleVersion = $ModuleVersion; Code = (Format-WorkerPerfErrorCode $Code)
        Pid = $(if ($null -ne $ProcessId) { [int]$ProcessId } else { $null }); SessionId = $(if ($null -ne $SessionId) { [int]$SessionId } else { $null })
        User = $User; Printer = ''; Driver = ''; Service = ''; Object = ''; Text = (Get-WorkerPerfEventText $Text); ProcessStart = $null
    }
}

function ConvertTo-WorkerPerfSimEventRecord($Scene) {
    # The record the collector receives: Time instead of the scenario second.
    return [pscustomobject]@{
        Time = $script:WorkerPerfSimStart.AddSeconds($Scene.Sec); Log = $Scene.Log; Source = $Scene.Source; EventId = $Scene.EventId; Level = $Scene.Level
        Group = $Scene.Group; Kind = $Scene.Kind; App = $Scene.App; AppVersion = $Scene.AppVersion; Module = $Scene.Module; ModuleVersion = $Scene.ModuleVersion
        Code = $Scene.Code; Pid = $Scene.Pid; SessionId = $Scene.SessionId; User = $Scene.User; Printer = $Scene.Printer; Driver = $Scene.Driver
        Service = $Scene.Service; Object = $Scene.Object; Text = $Scene.Text; ProcessStart = $Scene.ProcessStart
    }
}

function New-WorkerPerfSimCrash($Config, [double]$Sec, [string]$App, [string]$AppVersion, [string]$Module, [string]$ModuleVersion, [string]$Code,
                                $ProcessId = $null, $SessionId = $null, [string]$User = '') {
    # 'Application Error' 1000 as Windows words its first line.
    $text = 'Faulting application name: {0}, version: {1}, faulting module name: {2}, version: {3}, exception code: {4}' -f $App, $AppVersion, $Module, $ModuleVersion, $Code
    return (New-WorkerPerfSimEvent $Config $Sec 'application' 'Application Error' 1000 2 $text -App $App -AppVersion $AppVersion -Module $Module `
            -ModuleVersion $ModuleVersion -Code $Code -ProcessId $ProcessId -SessionId $SessionId -User $User)
}

function New-WorkerPerfSimSessionEvent($Config, [double]$Sec, [int]$EventId, [string]$What, [int]$SessionId) {
    # Session manager events name their user and session themselves (fields 'User' and 'SessionID' in events.json).
    $user = 'user{0:d3}' -f ($SessionId - 1)
    $text = 'Remote Desktop Services: Session {0} succeeded: User: {1}\{2}, Session ID: {3}' -f $What, $script:WorkerPerfSimDomain, $user, $SessionId
    return (New-WorkerPerfSimEvent $Config $Sec 'session' 'Microsoft-Windows-TerminalServices-LocalSessionManager' $EventId 4 $text -SessionId $SessionId -User $user)
}

# Categories of the capture that -Skip left out (set by Initialize-WorkerPerfSource), and per kind of data the number
# of calls in which the source assembled it (process, input.process, services, volumes, shares, citrix, events,
# eventsbefore, printdrivers, printqueues, probes): a left-out category is never read.
$script:WorkerPerfSimSkip = @()
$script:WorkerPerfSimReads = @{}

function Test-WorkerPerfSimMeasured([string]$Category) {
    return ($script:WorkerPerfSimSkip -notcontains $Category)
}

function Add-WorkerPerfSimRead([string]$Kind) {
    if ($script:WorkerPerfSimReads.ContainsKey($Kind)) { $script:WorkerPerfSimReads[$Kind]++ } else { $script:WorkerPerfSimReads[$Kind] = 1 }
}

function Initialize-WorkerPerfSource {
    param([datetime]$StartTime, [object[]]$Endpoints = @(), [string]$CitrixMetricFilter = '', [switch]$IncludeCommandLine, [string[]]$Skip = @(),
          [object]$EventConfig = $null, [object[]]$Apps = @())
    # EventConfig: the event catalogue (Read-WorkerPerfEventConfig); without it the simulation reads events.json beside it.
    # Apps: the application list of the health picture (Read-WorkerPerfHealthApps); without it the area apps is empty.
    # Skip: the categories left out (Resolve-WorkerPerfSkip). The source reads nothing of them and writes no entry of
    # theirs into Sources (the collector notes them); the base values stay the same.

    if ($null -eq $StartTime -or $StartTime -eq [datetime]::MinValue) {
        $n = [datetime]::Now
        $StartTime = $n.AddTicks(-($n.Ticks % [TimeSpan]::TicksPerSecond))
    }
    $script:WorkerPerfSimStart = $StartTime
    $script:WorkerPerfSimNow = $StartTime
    $script:WorkerPerfSimProbe = $null
    $script:WorkerPerfSimSkip = @($Skip | Where-Object { $_ })
    $script:WorkerPerfSimReads = @{}
    Initialize-WorkerPerfSimNoise
    $script:WorkerPerfSimIncludeCommandLine = [bool]$IncludeCommandLine
    $script:WorkerPerfSimCitrixMetrics = @(@('RoundtripTime', 'NetworkLatency') | Where-Object {
            (Test-WorkerPerfSimMeasured 'Citrix') -and ([string]::IsNullOrEmpty($CitrixMetricFilter) -or $_ -match $CitrixMetricFilter) })

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
        @('svchost.exe', 'SENS', 0, 0, 0, 20, 450, 9), @('spoolsv.exe', 'Spooler', 0, 0, 0, 16, 480, 11),
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
        @('ms-teams.exe', $script:WorkerPerfSimTeamsPath, 0.035, 10KB, 10KB, 300, 1500, 45))
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

    # ---- events: scenes of the hour, the lookback before the start, print drivers and queues ----
    # A crash names no session: the collector finds it through the pid of a process that ran at the time (the crashed
    # process keeps running in the simulation, so the measured hour stays as it is). Session events name their session
    # and user. The profile error names its user but no session: Windows writes the account into the System part of
    # the event, and the Windows source resolves it to the user name. The logon with the profile error lies before the
    # memory scene and far from other scenes, so it matches no pattern (the resource pattern looks 5 minutes back).
    $cfg = $EventConfig
    if ($null -eq $cfg) { $cfg = Read-WorkerPerfEventConfig $script:WorkerPerfSimEventFile }
    # kept for the area events of the health picture
    $script:WorkerPerfSimEventConfig = $cfg
    $spoolerPid = @($script:WorkerPerfSimProcs | Where-Object { $_.Name -eq 'spoolsv.exe' -and $_.SessionId -eq 0 })[0].Pid
    $defender = 'Microsoft-Windows-Windows Defender'
    $script:WorkerPerfSimEvents = @(
        (New-WorkerPerfSimSessionEvent $cfg 555 23 'logoff' 15)
        (New-WorkerPerfSimSessionEvent $cfg 595 21 'logon' 15)
        (New-WorkerPerfSimEvent $cfg 600 'application' 'Microsoft-Windows-User Profiles Service' 1511 3 `
                'Windows cannot find the local profile and is logging you on with a temporary profile (user014).' -User 'user014')
        (New-WorkerPerfSimCrash $cfg 1100 'chrome.exe' '131.0.6778.86' 'chrome.dll' '131.0.6778.86' '0xc0000017' -ProcessId $pidOf['9|chrome.exe'])
        (New-WorkerPerfSimEvent $cfg 1490 'defender' $defender 1000 4 'Microsoft Defender Antivirus scan has started.')
        (New-WorkerPerfSimEvent $cfg 1620 'defender' $defender 1001 4 'Microsoft Defender Antivirus scan has finished.')
        (New-WorkerPerfSimEvent $cfg 1800 'applocker' 'Microsoft-Windows-AppLocker' 8004 2 '%OSDRIVE%\USERS\USER008\DOWNLOADS\TOOL.EXE was prevented from running.')
        (New-WorkerPerfSimCrash $cfg 2100 'OUTLOOK.EXE' '16.0.18129.20158' 'olmapi32.dll' '16.0.18129.20100' '0xc0000005' -ProcessId $pidOf['11|OUTLOOK.EXE'])
        (New-WorkerPerfSimCrash $cfg 2160 'OUTLOOK.EXE' '16.0.18129.20158' 'olmapi32.dll' '16.0.18129.20100' '0xc0000005' -ProcessId $pidOf['12|OUTLOOK.EXE'])
        (New-WorkerPerfSimSessionEvent $cfg 2200 24 'disconnect' 23)
        (New-WorkerPerfSimCrash $cfg 2220 'OUTLOOK.EXE' '16.0.18129.20158' 'olmapi32.dll' '16.0.18129.20100' '0xc0000005' -ProcessId $pidOf['13|OUTLOOK.EXE'])
        (New-WorkerPerfSimSessionEvent $cfg 2230 25 'reconnection' 23)
        (New-WorkerPerfSimCrash $cfg 2600 'spoolsv.exe' '10.0.20348.2849' 'hpsimgr.dll' '61.310.1.25919' '0xc0000005' -ProcessId $spoolerPid))
    # The lookback has no processes to find a session in, so its crashes name session and user (session id = user number + 1;
    # the user comes from the account in the System part of the event, as for the profile error). One crash names neither,
    # as the classic Application Error 1000 is written without an account: its session is unknown (P1-R32).
    $script:WorkerPerfSimEventsBefore = @(
        (New-WorkerPerfSimCrash $cfg -432000 'EXCEL.EXE' '16.0.18129.20158' 'simaddin.dll' '2.4.0.0' '0xc0000005' -SessionId 2 -User 'user001')
        (New-WorkerPerfSimCrash $cfg -431000 'WINWORD.EXE' '16.0.18129.20158' 'simaddin.dll' '2.4.0.0' '0xc0000005' -SessionId 3 -User 'user002')
        (New-WorkerPerfSimCrash $cfg -259200 'nexus.exe' '8.2.0.114' 'nxreport.dll' '8.2.0.114' '0xc0000409' -SessionId 5 -User 'user004')
        (New-WorkerPerfSimCrash $cfg -258600 'nexus.exe' '8.2.0.114' 'nxreport.dll' '8.2.0.114' '0xc0000409' -SessionId 5 -User 'user004')
        (New-WorkerPerfSimCrash $cfg -258000 'nexus.exe' '8.2.0.114' 'nxreport.dll' '8.2.0.114' '0xc0000409' -SessionId 5 -User 'user004')
        (New-WorkerPerfSimCrash $cfg -172800 'simscan.exe' '3.1.0.7' 'simscan.dll' '3.1.0.7' '0xc0000005'))
    $script:WorkerPerfSimPrintDrivers = @(
        @{ Name = 'HP Universal Printing PCL 6 (Sim)'; Manufacturer = 'HP'; Version = '61.310.1.25919'; Type = 3; Isolation = 'none'; Files = @('hpsimgr.dll', 'hpsimui.dll') }
        @{ Name = 'Microsoft IPP Class Driver'; Manufacturer = 'Microsoft'; Version = '10.0.20348.1'; Type = 4; Isolation = 'shared'; Files = @('mxdwdrv.dll') }
        @{ Name = 'Kyocera Sim KX'; Manufacturer = 'Kyocera'; Version = '8.3.1016'; Type = 3; Isolation = 'isolated'; Files = @('kxsim.dll') })
    # Queue PRN-EG-01 holds 3 jobs from 2590 to 2700 s; its job error counter (a running raw value) rises by 1 with the
    # spooler crash at 2600 s.
    $script:WorkerPerfSimQueues = @(
        @{ Queue = 'PRN-EG-01'; JobErrors = 2; Jobs = 3; JobsA = 2590.0; JobsB = 2700.0; ErrorAt = 2600.0 }
        @{ Queue = 'PRN-OG-02'; JobErrors = 0; Jobs = 0; JobsA = 0.0; JobsB = 0.0; ErrorAt = [double]::PositiveInfinity })

    # ---- health picture: the application list and the state of the applications on the simulated worker ----
    # Values: registry path + '|' + value name -> value; Keys: path -> counts; Services: name -> state; Tasks: path ->
    # state ([datetime]::MinValue = no run); Files: path -> version ('' for a folder). Anything not listed does not exist.
    $script:WorkerPerfSimApps = [object[]]@($Apps | Where-Object { $null -ne $_ })
    $webView2Client = 'HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    $c2r = 'HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    $officePolicy = 'HKLM\SOFTWARE\Policies\Microsoft\office\16.0\Common\officeupdate'
    $script:WorkerPerfSimAppState = @{
        Values   = @{
            ($webView2Client + '|pv') = '130.0.2849.80'
            'HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate|UpdateDefault' = 0
            'HKLM\SOFTWARE\Policies\Microsoft\Edge|StartupBoostEnabled' = 0
            'HKLM\SOFTWARE\Policies\Microsoft\Edge|BackgroundModeEnabled' = 1
            ($c2r + '|UpdateChannel') = 'http://officecdn.microsoft.com/pr/00000000-0000-0000-0000-000000000000'
            ($c2r + '|UpdateUrl') = '\\fs01\office$\updates'
            ($c2r + '|VersionToReport') = '16.0.17932.20162'
            ($c2r + '|Platform') = 'x64'
            ($c2r + '|UpdatesEnabled') = 'False'
            ($officePolicy + '|hideupdatenotifications') = 1
            ($officePolicy + '|hideenabledisableupdates') = 1
            'HKLM\SOFTWARE\Microsoft\Teams|DisableFallback' = 2
        }
        Keys     = @{ 'HKLM\SOFTWARE\Microsoft\Office\Outlook\Addins' = @{ ValueCount = 0; SubKeyCount = 3 } }
        Services = @{ edgeupdate = @{ State = 'Stopped'; StartMode = 'Manual'; DisplayName = 'Microsoft Edge Update Service (edgeupdate)' } }
        Tasks    = @{ '\Microsoft\Office\Office Automatic Updates 2.0' = @{ Enabled = $false; LastRun = [datetime]::MinValue; NextRun = [datetime]::MinValue } }
        Files    = @{
            'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' = '130.0.2849.80'
            $script:WorkerPerfSimTeamsPath = '24277.3502.3161.3007'
            'C:\Program Files (x86)\Microsoft\TeamsMeetingAdd-in' = ''
        }
    }

    # Sources: none of a left-out category; the logs events.<id> belong to Ereignisse and Rueckblick together
    $leftOutIds = @{}
    foreach ($c in $script:WorkerPerfSimSkip) {
        if ($script:WorkerPerfCategories.Contains($c)) { foreach ($id in @($script:WorkerPerfCategories[$c].Sources)) { $leftOutIds[$id] = $true } }
    }
    $logIds = @()
    if ((Test-WorkerPerfSimMeasured 'Ereignisse') -or (Test-WorkerPerfSimMeasured 'Rueckblick')) { $logIds = @(@(Get-WorkerPerfEventReadLogs $cfg) | ForEach-Object { 'events.' + $_.Id }) }
    $sources = [ordered]@{}
    $ids = @($script:WorkerPerfSimSignalIds) + @('process', 'sessions', 'input.process', 'profile.map') + $logIds + @('print.drivers', 'print.queues')
    foreach ($id in $ids) { if (-not $leftOutIds.ContainsKey($id)) { $sources[$id] = @{ Available = $true; Detail = 'Simulation' } } }
    if ($sources.Contains('probe.connect')) { $sources['probe.connect'].Detail = 'Simulation, 3 Gegenstellen' }

    return @{
        Computer = 'SIM-VDA01'; OS = 'Simulated Windows Server 2022'; LogicalProcessors = $script:WorkerPerfSimCores
        PhysicalMemoryMB = $script:WorkerPerfSimRamMB; CollectorPid = $script:WorkerPerfSimCollectorPid
        Endpoints = $(if (Test-WorkerPerfSimMeasured 'Gegenstellen') { $script:WorkerPerfSimEndpoints } else { [object[]]@() }); Sources = $sources
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
    $committedMB = [Math]::Round($script:WorkerPerfSimBaseCommitMB + (1600 * $nz[4] - 800) + $growthMB)
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
    $withProcesses = Test-WorkerPerfSimMeasured 'Prozesse'
    if ($withProcesses) { Add-WorkerPerfSimRead 'input.process' }
    $inSessions = New-Object System.Collections.Generic.List[object]
    $inProcs = New-Object System.Collections.Generic.List[object]
    foreach ($s in $script:WorkerPerfSimSessions) {
        $sid = [int]$s.Sid
        $delay = [Math]::Round(40 * $nz[150 + $sid])
        foreach ($x in $script:WorkerPerfSimInputBySid[$sid]) {
            if ($e -gt $x.A -and $e -le $x.B) {
                $delay = [Math]::Round($x.Low + ($x.High - $x.Low) * $nz[180 + $sid])
                if ($withProcesses) { $inProcs.Add([pscustomobject]@{ SessionId = $sid; Pid = $x.Pid; Name = $x.App; DelayMs = $delay }) }
            }
        }
        $inSessions.Add([pscustomobject]@{ SessionId = $sid; DelayMs = $delay })
    }

    $diskR = 0.0; $diskW = 0.0; $opsR = 0.0; $opsW = 0.0; $diskQ = 0.0
    foreach ($v in $volumes) { $diskR += $v.ReadBps; $diskW += $v.WriteBps; $opsR += $v.ReadOps; $opsW += $v.WriteOps; $diskQ += $v.Queue }
    $netR = (1.5MB + 1.5MB * $nz[6]) + $shares[0].ReadBps + $shares[1].ReadBps
    $netS = (0.8MB + 0.8MB * $nz[7]) + $shares[0].WriteBps + $shares[1].WriteBps
    # the totals of disk and network come from the scripted volumes and shares in any case; their rows are read only
    # with Laufwerke
    $volumeRows = [object[]]@(); $shareRows = [object[]]@()
    if (Test-WorkerPerfSimMeasured 'Laufwerke') {
        $volumeRows = $volumes.ToArray(); $shareRows = $shares
        Add-WorkerPerfSimRead 'volumes'; Add-WorkerPerfSimRead 'shares'
    }

    return [pscustomobject]@{
        Time = $script:WorkerPerfSimNow
        CpuPct = [Math]::Round($cpuPct, 2); ProcQueue = $queue; StealPct = [Math]::Round((0.1 + 0.7 * $nz[8]), 2)
        MemAvailMB = $availMB; MemCommittedMB = $committedMB; MemCommitLimitMB = $script:WorkerPerfSimCommitLimitMB
        PagesInPerSec = [Math]::Round($pagesIn, 1)
        DiskReadBps = [Math]::Round($diskR); DiskWriteBps = [Math]::Round($diskW)
        DiskReadIops = [Math]::Round($opsR / 2, 1); DiskWriteIops = [Math]::Round($opsW / 2, 1); DiskQueue = $diskQ
        NetRecvBps = [Math]::Round($netR); NetSentBps = [Math]::Round($netS)
        Volumes = $volumeRows; Shares = $shareRows; InputSessions = $inSessions.ToArray(); InputProcesses = $inProcs.ToArray()
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
    $running = @()
    if (Test-WorkerPerfSimMeasured 'Prozesse') { $running = $script:WorkerPerfSimProcs; Add-WorkerPerfSimRead 'process' }
    foreach ($p in $running) {
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
    if (Test-WorkerPerfSimMeasured 'Citrix') { Add-WorkerPerfSimRead 'citrix' }
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
    # PID -> 'Service1;Service2' (a copy, so callers cannot change the scenario); empty without Prozesse.
    if (-not (Test-WorkerPerfSimMeasured 'Prozesse')) { return @{} }
    Add-WorkerPerfSimRead 'services'
    return $script:WorkerPerfSimServices.Clone()
}

function Start-WorkerPerfProbes {
    param([object[]]$Endpoints)
    # The built-in endpoints are always probed; -Endpoints exists for interface compatibility only. Without
    # Gegenstellen nothing is probed.
    $script:WorkerPerfSimProbe = $null
    if (-not (Test-WorkerPerfSimMeasured 'Gegenstellen')) { return }
    Add-WorkerPerfSimRead 'probes'
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
    if (-not (Test-WorkerPerfSimMeasured 'Ereignisse')) { return }
    Add-WorkerPerfSimRead 'events'
    foreach ($ev in $script:WorkerPerfSimEvents) {
        $t = $script:WorkerPerfSimStart.AddSeconds($ev.Sec)
        if ($t -gt $Since -and $t -le $script:WorkerPerfSimNow) { ConvertTo-WorkerPerfSimEventRecord $ev }
    }
}

function Get-WorkerPerfEventsBefore {
    # The scripted lookback: the events up to Until that are at most Days days older; the simulation caps no log.
    param([int]$Days, [datetime]$Until)
    if (-not (Test-WorkerPerfSimMeasured 'Rueckblick')) { return @{ Events = @(); Capped = @() } }
    Add-WorkerPerfSimRead 'eventsbefore'
    $from = $Until.AddDays(-$Days)
    $events = @(foreach ($ev in $script:WorkerPerfSimEventsBefore) {
            $t = $script:WorkerPerfSimStart.AddSeconds($ev.Sec)
            if ($Days -gt 0 -and $t -gt $from -and $t -le $Until) { ConvertTo-WorkerPerfSimEventRecord $ev }
        })
    return @{ Events = $events; Capped = @() }
}

function Receive-WorkerPerfSourceErrors {
    # The simulated source fails nowhere: no failures to report.
}

function Get-WorkerPerfEventCounts {
    # The simulated source skips no record and drops no event: no counters.
    return [ordered]@{}
}

function Get-WorkerPerfPrintDrivers {
    if (-not (Test-WorkerPerfSimMeasured 'Drucken')) { return }
    Add-WorkerPerfSimRead 'printdrivers'
    foreach ($d in $script:WorkerPerfSimPrintDrivers) {
        [pscustomobject]@{ Name = $d.Name; Manufacturer = $d.Manufacturer; Version = $d.Version; Type = $d.Type; Isolation = $d.Isolation; Files = @($d.Files) }
    }
}

function Get-WorkerPerfPrintQueues {
    # Waiting jobs in the window JobsA < t <= JobsB, the job error counter one higher from ErrorAt on; never "not ready".
    if (-not (Test-WorkerPerfSimMeasured 'Drucken')) { return }
    Add-WorkerPerfSimRead 'printqueues'
    $e = Get-WorkerPerfSimElapsed
    foreach ($q in $script:WorkerPerfSimQueues) {
        [pscustomobject]@{ Queue = $q.Queue; Jobs = $(if ($e -gt $q.JobsA -and $e -le $q.JobsB) { $q.Jobs } else { 0 })
            JobErrors = $(if ($e -ge $q.ErrorAt) { $q.JobErrors + 1 } else { $q.JobErrors }); NotReadyErrors = 0 }
    }
}

function Get-WorkerPerfSimAppReaders {
    # The five readers of Get-WorkerPerfAppRows on the state of the applications: $null when the thing does not exist,
    # otherwise a table with exactly the fields of its kind. The simulation knows no application by name.
    $state = $script:WorkerPerfSimAppState
    return @{
        registryValue = {
            param([string]$Path, [string]$Name)
            $key = $Path + '|' + $Name
            if ($state['Values'].ContainsKey($key)) { return @{ Value = $state['Values'][$key] } }
            return $null
        }.GetNewClosure()
        registryKey   = {
            param([string]$Path)
            if ($state['Keys'].ContainsKey($Path)) { $k = $state['Keys'][$Path]; return @{ ValueCount = [int]$k.ValueCount; SubKeyCount = [int]$k.SubKeyCount } }
            # derived from Values: a key exists only when Values names a value directly under it (a parent of such a
            # key does not exist), and a derived key has those values and no subkeys
            $prefix = $Path + '|'
            $count = @($state['Values'].Keys | Where-Object { ([string]$_).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) }).Count
            if ($count -gt 0) { return @{ ValueCount = [int]$count; SubKeyCount = 0 } }
            return $null
        }.GetNewClosure()
        service       = {
            param([string]$Name, [string]$DisplayName)
            $svc = $null
            if ($Name) { if ($state['Services'].ContainsKey($Name)) { $svc = $state['Services'][$Name] } }
            else { $svc = @($state['Services'].Values | Where-Object { $_.DisplayName -eq $DisplayName }) | Select-Object -First 1 }
            if ($null -eq $svc) { return $null }
            return @{ State = [string]$svc.State; StartMode = [string]$svc.StartMode }
        }.GetNewClosure()
        scheduledTask = {
            param([string]$Path)
            if (-not $state['Tasks'].ContainsKey($Path)) { return $null }
            $t = $state['Tasks'][$Path]
            return @{ Enabled = [bool]$t.Enabled; LastRun = [datetime]$t.LastRun; NextRun = [datetime]$t.NextRun }
        }.GetNewClosure()
        file          = {
            param([string]$Path)
            # a path with '*' matches through -like; of several matches the highest version counts
            $hits = @($state['Files'].Keys | Where-Object { $(if ($Path.Contains('*')) { $_ -like $Path } else { $_ -eq $Path }) })
            if ($hits.Count -eq 0) { return $null }
            $versions = @($hits | ForEach-Object { [string]$state['Files'][$_] })
            $best = $versions | Sort-Object -Descending -Property @{ Expression = { $v = $null; if ([version]::TryParse($_, [ref]$v)) { $v } else { [version]'0.0' } } }, @{ Expression = { $_ } } |
                Select-Object -First 1
            return @{ Version = [string]$best }
        }.GetNewClosure()
    }
}

function Get-WorkerPerfHealth {
    # The scripted health picture of the simulated worker: eleven areas, each value read with the content of the script
    # unless stated otherwise; $null (and no read) without Zustand.
    if (-not (Test-WorkerPerfSimMeasured 'Zustand')) { return $null }
    Add-WorkerPerfSimRead 'health'
    $s = $script:WorkerPerfSimStart
    $ok = { param($Value) New-WorkerPerfHealthValue 'read' '' $Value }
    $absent = New-WorkerPerfHealthValue 'absent'
    $time = { param([datetime]$Time) ConvertTo-WorkerPerfHealthTime $Time }
    $running = { param([string]$Name, [string]$State = 'Running', [string]$StartMode = 'Auto') [ordered]@{ Name = $Name; State = $State; StartMode = $StartMode } }
    $areas = [ordered]@{}

    $areas['size'] = Complete-WorkerPerfHealthArea 'size' ([ordered]@{
            'size.cpuLogical' = & $ok $script:WorkerPerfSimCores; 'size.cpuSockets' = & $ok 2; 'size.memTotalMB' = & $ok $script:WorkerPerfSimRamMB
            'size.commitTotalMB' = & $ok $script:WorkerPerfSimBaseCommitMB; 'size.commitLimitMB' = & $ok $script:WorkerPerfSimCommitLimitMB; 'size.commitPeakMB' = & $ok 61000
            'size.pagefiles' = & $ok @([ordered]@{ Path = 'C:\pagefile.sys'; AllocatedMB = 32768; PeakUsageMB = 5200; Temporary = $false })
            'size.pagefileManaged' = & $ok $false; 'size.hypervisor' = & $ok $true; 'size.model' = & $ok 'VMware, Inc. VMware7,1'
            'size.vmtoolsPresent' = & $ok $true; 'size.vmtoolsService' = & $ok 'Running'; 'size.vmtoolsVersion' = & $ok '12.3.5'
            'size.netAdapters' = & $ok @([ordered]@{ Name = 'vmxnet3 Ethernet Adapter'; Service = 'vmxnet3ndis6'; SpeedMbit = 10000; Enabled = $true })
            'size.storageControllers' = & $ok @([ordered]@{ Name = 'VMware PVSCSI Controller'; Driver = 'pvscsi' })
            'size.balloonDriver' = & $ok 'Running'
        }) 0

    $areas['operation'] = Complete-WorkerPerfHealthArea 'operation' ([ordered]@{
            'operation.lastBoot' = & $ok (& $time $s.AddDays(-3)); 'operation.pendingRename' = & $ok 2
            'operation.pendingServicing' = & $ok $false; 'operation.pendingUpdate' = & $ok $false
            'operation.lastUpdate' = & $ok (& $time $s.AddDays(-20)); 'operation.lastUpdateId' = & $ok 'KB5099999'
            'operation.powerPlan' = & $ok 'highPerformance'
            'operation.volumes' = & $ok @(
                [ordered]@{ Drive = 'C:'; SizeGB = 100; FreeGB = 38; FileSystem = 'NTFS'; System = $true; PageFile = $true }
                [ordered]@{ Drive = 'D:'; SizeGB = 200; FreeGB = 150; FileSystem = 'NTFS'; System = $false; PageFile = $false })
        }) 0

    # sessions: session 0 as in the snapshot (no user, idle time unknown) and the 25 user sessions
    $list = New-Object System.Collections.Generic.List[object]
    $list.Add([ordered]@{ Id = 0; State = 'Disconnected'; WinStation = 'Services'; User = ''; Domain = ''; Client = ''
            LogonTime = (& $time ([datetime]::MinValue)); ConnectTime = (& $time ([datetime]::MinValue)); DisconnectTime = (& $time ([datetime]::MinValue)); IdleMinutes = -1 })
    $containers = New-Object System.Collections.Generic.List[object]
    $profiles = New-Object System.Collections.Generic.List[object]
    foreach ($ses in $script:WorkerPerfSimSessions) {
        $logon = & $time $s.AddSeconds($ses.LogonSec)
        $list.Add([ordered]@{ Id = [int]$ses.Sid; State = 'Active'; WinStation = $ses.WinStation; User = $ses.User; Domain = $script:WorkerPerfSimDomain
                Client = $ses.Client; LogonTime = $logon; ConnectTime = $logon; DisconnectTime = (& $time ([datetime]::MinValue)); IdleMinutes = 0 })
        $full = ($ses.User -eq 'user009')
        $containers.Add([ordered]@{ Location = ('\\fs01\profile$\{0}.{1}\Win2022\ProfileContainer.vhdx' -f $ses.User, $script:WorkerPerfSimDomain)
                Mount = ('C:\Users\{0}_UPM_local\UpmTempMount' -f $ses.User); Owner = $ses.User; SessionId = [int]$ses.Sid; SizeGB = 50
                AllocatedGB = $(if ($full) { 48 } else { 20 }); VolumeSizeGB = 50; VolumeFreeGB = $(if ($full) { 2 } else { 30 }); UsedPct = $(if ($full) { 96 } else { 40 }) })
        $profiles.Add([ordered]@{ Path = ('C:\Users\' + $ses.User); Loaded = $true; Special = $false; LastUse = (& $time $s); Temporary = $false })
    }
    $profiles.Add([ordered]@{ Path = 'C:\Users\user026'; Loaded = $false; Special = $false; LastUse = (& $time $s.AddDays(-10)); Temporary = $false })
    $profiles.Add([ordered]@{ Path = 'C:\Users\Administrator'; Loaded = $false; Special = $false; LastUse = (& $time $s.AddDays(-40)); Temporary = $false })
    $limits = @(foreach ($terminal in 'ICA-CGP', 'RDP-Tcp') {
            [ordered]@{ Terminal = $terminal; IdleLimitMin = 180; DisconnectedLimitMin = 240; ActiveLimitMin = 0; BrokenAction = 0; FromPolicy = $true } })
    $areas['sessions'] = Complete-WorkerPerfHealthArea 'sessions' ([ordered]@{
            'sessions.list' = & $ok $list.ToArray(); 'sessions.limits' = & $ok $limits; 'sessions.localProfiles' = & $ok $profiles.ToArray()
        }) 0

    $areas['vda'] = Complete-WorkerPerfHealthArea 'vda' ([ordered]@{
            'vda.version' = & $ok '2203.0.4000'
            'vda.services' = & $ok @(foreach ($n in 'BrokerAgent', 'PorticaService', 'CitrixHealthMon', 'ctxProfile', 'CpSvc') { & $running $n })
            'vda.desktopService' = & $ok 'Running'
            'vda.controllers' = & $ok @(foreach ($n in 'ddc01.sim.local', 'ddc02.sim.local') { [ordered]@{ Entry = $n; Kind = 'fqdn'; From = 'policy' } })
            'vda.listOfSids' = & $ok $false; 'vda.farmGuid' = & $ok $false
            'vda.policyRaw' = & $ok @(
                [ordered]@{ Key = 'ICAPolicies'; Name = 'SimSitzungslimit'; Value = '1' }
                [ordered]@{ Key = 'ICAPolicies'; Name = 'SimDruckerzuweisung'; Value = '\\prn01\Etage2' })
            'vda.persistentDataLocation' = & $ok 'D:\PersistentData'; 'vda.wemService' = & $ok 'Running'
            # the simulation has no process entries for the two WEM services; SENS runs in a svchost.exe of the process list
            'vda.wemServices' = & $ok @(foreach ($n in 'Citrix WEM Agent Host Service', 'Citrix WEM User Logon Service', 'System Event Notification Service') { & $running $n })
            'vda.wemVersion' = & $ok '2407.1.0.1'; 'vda.wemServer' = & $ok 'wem01.sim.local'; 'vda.wemCacheLocation' = & $ok 'D:\WEMCache'
            'vda.wemGpNetworkTimeout' = & $ok 120; 'vda.teamsService' = & $ok 'Running'; 'vda.webSocketService' = & $ok 'Running'
        }) 0

    $areas['profile'] = Complete-WorkerPerfHealthArea 'profile' ([ordered]@{
            'profile.service' = & $ok 'Running'; 'profile.version' = & $ok '2203.0.4000'
            'profile.policyGpo' = & $ok @(
                [ordered]@{ Key = ''; Name = 'ServiceActive'; Value = '1' }
                [ordered]@{ Key = ''; Name = 'PathToUserStore'; Value = '\\fs01\profile$\%USERNAME%.%USERDOMAIN%' })
            'profile.policyStudio' = & $ok @(); 'profile.containers' = & $ok $containers.ToArray()
        }) 0

    $areas['print'] = Complete-WorkerPerfHealthArea 'print' ([ordered]@{
            'print.isolationExecution' = $absent; 'print.isolationOverride' = $absent; 'print.queueCount' = & $ok 2
            'print.spooler' = & $ok 'Running'; 'print.spoolerStartMode' = & $ok 'Auto'; 'print.citrixPrintService' = & $ok 'Running'
            'print.operationalLog' = & $ok $false; 'print.mappingClientVersion' = & $ok '6.4.1'
        }) 0

    # every service of the processes in the order of their PIDs (all running), then the services the simulated process
    # list has no process entries for: Sense, W32Time, VMTools and CpSvc running, and the Windows Update service stopped
    # and disabled, as maintenance.updateService says (no process hosts it)
    $services = New-Object System.Collections.Generic.List[object]
    foreach ($procId in @($script:WorkerPerfSimServices.Keys | Sort-Object)) {
        foreach ($n in ([string]$script:WorkerPerfSimServices[$procId]).Split(';')) { if ($n) { $services.Add((& $running $n)) } }
    }
    $services.Add((& $running 'Sense' 'Running' 'Manual'))
    foreach ($n in 'W32Time', 'VMTools', 'CpSvc') { $services.Add((& $running $n)) }
    $services.Add((& $running 'wuauserv' 'Stopped' 'Disabled'))
    $areas['security'] = Complete-WorkerPerfHealthArea 'security' ([ordered]@{
            'security.services' = & $ok $services.ToArray(); 'security.defenderService' = & $ok 'Running'; 'security.defenderMode' = & $ok 'Normal'
            'security.defenderRealTime' = & $ok $true; 'security.defenderTamper' = & $ok $true; 'security.defenderSignatureAgeDays' = & $ok 1
            'security.defenderSignaturesOutOfDate' = & $ok $false; 'security.defenderVersion' = & $ok '4.18.24090.11'
            'security.defenderExclusionPaths' = New-WorkerPerfHealthValue 'unreadable' 'rights'
            'security.defenderExclusionProcesses' = New-WorkerPerfHealthValue 'unreadable' 'rights'
            'security.defenderExclusionExtensions' = New-WorkerPerfHealthValue 'unreadable' 'rights'
            'security.defenderSharedSignatures' = & $ok '\\fs01\defsig$'; 'security.defenderNetworkProtection' = & $ok 0
            'security.defenderForcePassive' = $absent; 'security.mdeOnboarding' = & $ok 1; 'security.mdeService' = & $ok 'Running'
            'security.filters' = & $ok @(
                [ordered]@{ Name = 'WdFilter'; Altitude = '328010'; Instances = 4; Legacy = $false }
                [ordered]@{ Name = 'upmjit'; Altitude = '182400'; Instances = 26; Legacy = $false }
                [ordered]@{ Name = 'FileInfo'; Altitude = '45000'; Instances = 5; Legacy = $false })
            'security.applockerService' = & $ok 'Running'
            'security.applockerCollections' = & $ok @(
                [ordered]@{ Collection = 'Exe'; Enforcement = 1; Rules = 12 }
                [ordered]@{ Collection = 'Msi'; Enforcement = 1; Rules = 4 }
                [ordered]@{ Collection = 'Script'; Enforcement = 1; Rules = 6 })
        }) 0

    $areas['network'] = Complete-WorkerPerfHealthArea 'network' ([ordered]@{
            'network.domainMember' = & $ok $true; 'network.smbRequireSigning' = & $ok $false; 'network.smbDirectoryCache' = & $ok 16
            'network.smbFileInfoCache' = & $ok 64; 'network.smbFileNotFoundCache' = & $ok 128; 'network.smb1' = $absent
            'network.smbConnections' = & $ok @(foreach ($share in '\\fs01\daten', '\\fs01\profile$') {
                    [ordered]@{ Share = $share; Dialect = '3.1.1'; Signed = $true; Encrypted = $false; Connections = 25 } })
            'network.dnsServers' = & $ok @(foreach ($a in '10.20.0.10', '10.20.0.11', 'fd00:20::10') { [ordered]@{ Interface = 4; Address = $a } })
            'network.rss' = & $ok @([ordered]@{ Description = 'vmxnet3 Ethernet Adapter'; Enabled = $true })
            'network.timeType' = & $ok 'NT5DS'; 'network.timeServers' = & $ok 'zeit01.sim.local 10.20.0.20'; 'network.timeService' = & $ok 'Running'
        }) 0

    $logs = @(foreach ($l in @(Get-WorkerPerfEventReadLogs $script:WorkerPerfSimEventConfig)) {
            foreach ($n in @($l.Names)) {
                [ordered]@{ Log = $n; Present = $true; Enabled = $true; MaxSizeMB = 20; FileSizeMB = 12; Records = 30000; Mode = 'Circular'; Full = $false
                    Oldest = (& $time $s.AddDays(-30)) }
            } })
    $areas['events'] = Complete-WorkerPerfHealthArea 'events' ([ordered]@{ 'events.logs' = & $ok $logs }) 0

    # the inventory runs at 10:00 on the next working day after the start, the backup at 02:00 the next night
    $workday = $s.Date.AddDays(1)
    while ($workday.DayOfWeek -eq [DayOfWeek]::Saturday -or $workday.DayOfWeek -eq [DayOfWeek]::Sunday) { $workday = $workday.AddDays(1) }
    $areas['maintenance'] = Complete-WorkerPerfHealthArea 'maintenance' ([ordered]@{
            'maintenance.tasks' = & $ok @(
                [ordered]@{ Path = '\Sim\Inventarlauf'; Enabled = $true; State = 'Ready'; NextRun = (& $time $workday.AddHours(10)); LastRun = (& $time $s.AddHours(-22))
                    Triggers = 'daily'; RepeatMinutes = 0; Action = 'C:\Tools\inventar.exe' }
                [ordered]@{ Path = '\Sim\Nachtsicherung'; Enabled = $true; State = 'Ready'; NextRun = (& $time $s.Date.AddDays(1).AddHours(2)); LastRun = (& $time $s.AddHours(-6))
                    Triggers = 'daily'; RepeatMinutes = 0; Action = 'C:\Tools\sicherung.cmd' })
            'maintenance.taskCount' = & $ok 162; 'maintenance.scanDay' = & $ok 0; 'maintenance.scanTime' = & $ok '02:00'
            'maintenance.quickScanTime' = & $ok '02:00'; 'maintenance.scanType' = & $ok 1; 'maintenance.scanRandomize' = & $ok $true
            'maintenance.scanCpuLoad' = & $ok 50; 'maintenance.updateOptions' = $absent; 'maintenance.updateDay' = $absent
            'maintenance.updateHour' = $absent; 'maintenance.updateNoRebootWithUsers' = $absent
            'maintenance.searchService' = New-WorkerPerfHealthValue 'absent' 'notInstalled'; 'maintenance.updateService' = & $ok 'Disabled'
        }) 0

    # the applications of the list, read through the same row builder as on Windows
    $rows = [object[]]@(Get-WorkerPerfAppRows -Apps $script:WorkerPerfSimApps -Read (Get-WorkerPerfSimAppReaders))
    $areas['apps'] = Complete-WorkerPerfHealthArea 'apps' ([ordered]@{ 'apps.probes' = & $ok $rows }) 0

    return (New-WorkerPerfHealth $script:WorkerPerfSimNow 0 $areas)
}

function Get-WorkerPerfFreeSpaceMB {
    param([string]$Path)
    return [double]100000
}

function Get-WorkerPerfExpected {
    # Simulation only: the incidents the analysis must find, sorted by start; the lookback rows (Before) come last.
    # Performance incidents span their scenario window, event incidents their first to last event.
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
    # event incidents: key, kind, patterns, first and last event second, app, driver, event count, users in order of appearance
    $eventRows = @(
        @{ Key = 'crash.memory'; Kind = 'crash'; Patterns = @('resource', 'overlap'); Before = $false; A = 1100; B = 1100; App = 'chrome.exe'; Driver = $null; Count = 1; Users = @('user008') }
        @{ Key = 'profile.logon'; Kind = 'profileerror'; Patterns = @(); Before = $false; A = 600; B = 600; App = $null; Driver = $null; Count = 1; Users = @('user014') }
        @{ Key = 'crash.manyusers'; Kind = 'crash'; Patterns = @('manyusers'); Before = $false; A = 2100; B = 2220; App = 'OUTLOOK.EXE'; Driver = $null; Count = 3
            Users = @('user010', 'user011', 'user012') }
        @{ Key = 'print.spooler'; Kind = 'print'; Patterns = @('printdriver'); Before = $false; A = 2600; B = 2600; App = 'spoolsv.exe'; Driver = 'HP Universal Printing PCL 6 (Sim)'
            Count = 1; Users = @() }
        @{ Key = 'before.shared.excel'; Kind = 'crash'; Patterns = @('sharedmodule'); Before = $true; A = -432000; B = -432000; App = 'EXCEL.EXE'; Driver = $null; Count = 1; Users = @('user001') }
        @{ Key = 'before.shared.word'; Kind = 'crash'; Patterns = @('sharedmodule'); Before = $true; A = -431000; B = -431000; App = 'WINWORD.EXE'; Driver = $null; Count = 1; Users = @('user002') }
        @{ Key = 'before.oneuser'; Kind = 'crash'; Patterns = @('oneuser'); Before = $true; A = -259200; B = -258000; App = 'nexus.exe'; Driver = $null; Count = 3; Users = @('user004') }
        @{ Key = 'before.nosession'; Kind = 'crash'; Patterns = @(); Before = $true; A = -172800; B = -172800; App = 'simscan.exe'; Driver = $null; Count = 1; Users = @() })
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($r in $rows) {
        $w = $script:WorkerPerfSimWindows[$r.Key]
        $out.Add([pscustomobject][ordered]@{
                Key = $r.Key; Type = $r.Type; Lead = $r.Lead; Chronic = $r.Chronic
                StartMs = [long]($startMs + [long]($w.A * 1000)); EndMs = [long]($startMs + [long]($w.B * 1000))
                MainApp = $r.MainApp; MainUser = $r.MainUser; Affected = $r.Affected; DelayApp = $r.DelayApp; Endpoint = $r.Endpoint; Companion = $r.Companion
                Kind = $null; Patterns = [string[]]@(); Before = $false; App = $null; Driver = $null; Count = 0; Users = [string[]]@()
            })
    }
    foreach ($r in $eventRows) {
        $out.Add([pscustomobject][ordered]@{
                Key = $r.Key; Type = 'ereignis'; Lead = $null; Chronic = $false
                StartMs = [long]($startMs + [long]($r.A * 1000)); EndMs = [long]($startMs + [long]($r.B * 1000))
                MainApp = $null; MainUser = $null; Affected = 0; DelayApp = $null; Endpoint = $null; Companion = $null
                Kind = $r.Kind; Patterns = [string[]]$r.Patterns; Before = $r.Before; App = $r.App; Driver = $r.Driver; Count = $r.Count; Users = [string[]]$r.Users
            })
    }
    $out.ToArray() | Sort-Object -Property @{ Expression = { [bool]$_.Before } }, StartMs
}
