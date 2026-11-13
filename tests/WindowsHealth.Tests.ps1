BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.EventConfig.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Sources.Windows.ps1')
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Capture.ps1'); . (Join-Path $PSScriptRoot 'WindowsStandIns.ps1')
    $script:Cfg = Read-WorkerPerfEventConfig (Join-Path $PSScriptRoot '../src/events.json')
    function Read-Health([string[]]$Skip = @(), [object[]]$Apps = @()) { [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg -Skip $Skip -Apps $Apps 3>$null); Get-WorkerPerfHealth 3>$null }
    function Get-V($H, [string]$Id) { $H.Areas[$WorkerPerfHealthValues[$Id].Area].Values[$Id] }
}
Describe 'Zustandsbild unter Windows: Geruest, Groesse, Betrieb, Ereignisbild' {
    BeforeEach { Reset-WinStandIns }
    It 'liest die drei Bereiche mit den Werten der Platzhalter' {
        $h = Read-Health
        @($h.Areas.Keys) | Should -Be $WorkerPerfHealthAreas; $h.FormatVersion | Should -Be 1; $h.DurationMs | Should -BeGreaterOrEqual 0
        foreach ($a in 'size', 'operation', 'events') { $h.Areas[$a].Status | Should -Be 'read' -Because $a }
        (Get-V $h 'size.cpuLogical').Value | Should -Be 6; (Get-V $h 'size.cpuSockets').Value | Should -Be 2; (Get-V $h 'size.memTotalMB').Value | Should -Be 59392
        (Get-V $h 'size.commitPeakMB').Value | Should -Be 60000; (Get-V $h 'size.pagefiles').Value[0].AllocatedMB | Should -Be 16384; (Get-V $h 'size.pagefiles').Value[0].Path | Should -Be 'C:\pagefile.sys'
        ((Get-V $h 'size.pagefiles').Value -is [array]) | Should -BeTrue                                 # eine Datei: trotzdem eine Liste
        (Get-V $h 'size.model').Value | Should -Be 'VMware, Inc. VMware7,1'; (Get-V $h 'size.hypervisor').Value | Should -BeTrue; (Get-V $h 'size.vmtoolsPresent').Value | Should -BeTrue
        (Get-V $h 'size.vmtoolsService').Value | Should -Be 'Running'; (Get-V $h 'size.vmtoolsVersion').Value | Should -Be '12.3.5.22544099'
        (Get-V $h 'size.netAdapters').Value[0].SpeedMbit | Should -Be 10000; (Get-V $h 'size.storageControllers').Value[0].Driver | Should -Be 'pvscsi'; (Get-V $h 'size.balloonDriver').Value | Should -Be 'Running'
        (Get-V $h 'operation.pendingRename').Value | Should -Be 2; (Get-V $h 'operation.pendingUpdate').Value | Should -BeTrue; (Get-V $h 'operation.pendingServicing').Value | Should -BeFalse
        (Get-V $h 'operation.lastUpdateId').Value | Should -Be 'KB5000002'; (Get-V $h 'operation.lastUpdate').Value | Should -Be (ConvertTo-WorkerPerfHealthTime ([datetime]'2026-10-14'))
        (Get-V $h 'operation.powerPlan').Value | Should -Be 'balanced'
        $c = (Get-V $h 'operation.volumes').Value | Where-Object Drive -eq 'C:'; $c.FreeGB | Should -Be 8; $c.SizeGB | Should -Be 100; $c.System | Should -BeTrue; $c.PageFile | Should -BeTrue
        ((Get-V $h 'operation.volumes').Value | Where-Object Drive -eq 'D:').PageFile | Should -BeFalse
        $logs = (Get-V $h 'events.logs').Value; @($logs).Count | Should -Be 8                          # die Protokolle, die der Katalog liest
        $log = $logs | Where-Object Log -eq 'Application'; $log.Present | Should -BeTrue; $log.Enabled | Should -BeTrue; $log.MaxSizeMB | Should -Be 20; $log.FileSizeMB | Should -Be 12; $log.Mode | Should -Be 'Circular'; $log.Mode | Should -BeOfType [string]
        ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - $log.Oldest) / 86400000 | Should -BeGreaterThan 29.9
    }
    It 'laesst die anderen Werte und Bereiche stehen, wenn ein Aufruf scheitert oder haengt' {   # Review Focus 1
        $script:WinFake.CimFail['Win32_LogicalDisk'] = New-WinStandInDenied 'cim'
        $script:WinFake.Delay['cim:Win32_PageFileUsage'] = 5000; $script:WorkerPerfWinHealthAreaBudgetSec = 1
        try { $h = Read-Health } finally { $script:WorkerPerfWinHealthAreaBudgetSec = 10 }
        (Get-V $h 'operation.volumes').State | Should -Be 'unreadable'; (Get-V $h 'operation.volumes').Reason | Should -Be 'rights'
        (Get-V $h 'operation.powerPlan').State | Should -Be 'read'; $h.Areas['operation'].Status | Should -Be 'partial'; $h.Areas['operation'].Error | Should -Be ''
        # Groesse: die Abfrage der Auslagerungsdatei bekommt den Rest des Limits als Zeitlimit und endet daran; was davor gelesen wurde, bleibt
        (Get-V $h 'size.cpuLogical').State | Should -Be 'read'; (Get-V $h 'size.pagefiles').Reason | Should -Be 'timeout'; (Get-V $h 'size.storageControllers').Reason | Should -Be 'timeout'
        $h.Areas['size'].Status | Should -Be 'partial'; $h.Areas['size'].DurationMs | Should -BeLessThan 3000      # nicht die 5 s des haengenden Aufrufs
        $script:WinFake.Calls.Keys | Should -Not -Contain 'cim:Win32_SCSIController'          # nach dem Limit kein Aufruf mehr
        $h.Areas['events'].Status | Should -Be 'read'
    }
    It 'endet am Gesamtlimit und nennt die uebrigen Bereiche nicht gelesen' {
        $script:WinFake.Delay['cim:Win32_PageFileUsage'] = 5000; $script:WorkerPerfWinHealthTotalBudgetSec = 0.5
        try { $h = Read-Health } finally { $script:WorkerPerfWinHealthTotalBudgetSec = 60 }
        $h.Areas['operation'].Status | Should -Be 'failed'; $h.Areas['operation'].Error | Should -Be 'budget'; (Get-V $h 'operation.lastBoot').Reason | Should -Be 'timeout'
        $script:WinFake.Calls.Keys | Should -Not -Contain 'cim:Win32_LogicalDisk'
    }
    It 'liest die Laufwerke auch, wenn die Liste der Auslagerungsdateien nicht lesbar ist' {   # Review Focus 1
        $script:WinFake.Delay['cim:Win32_PageFileUsage'] = 5000; $script:WorkerPerfWinHealthAreaBudgetSec = 1
        try { $h = Read-Health } finally { $script:WorkerPerfWinHealthAreaBudgetSec = 10 }
        (Get-V $h 'size.pagefiles').Reason | Should -Be 'timeout'
        $c = (Get-V $h 'operation.volumes').Value | Where-Object Drive -eq 'C:'; (Get-V $h 'operation.volumes').State | Should -Be 'read'
        $c.PageFile | Should -BeNullOrEmpty; $c.System | Should -BeTrue; $c.FreeGB | Should -Be 8      # eine Nebenangabe fehlt, der freie Platz bleibt pruefbar
        $h.Areas['operation'].Status | Should -Be 'read'
    }
    It 'ordnet ein Ergebnis nach dem Typ des Werts ein und erkennt verweigerten Zugriff in jeder Form' {
        $ctx = @{ Area = 'vda'; State = $null; Clock = [System.Diagnostics.Stopwatch]::StartNew(); BudgetMs = 10000; Shared = @{}; Values = [ordered]@{} }
        Set-WorkerPerfWinHealthValue $ctx 'vda.controllers' { }                                                               # Liste ohne Ergebnis: gelesen, leer
        Set-WorkerPerfWinHealthValue $ctx 'vda.services' { [ordered]@{ Name = 'X'; State = 'Running'; StartMode = 'Auto' } }   # ein Eintrag mit einem Feld State ist kein Wertsatz
        Set-WorkerPerfWinHealthValue $ctx 'vda.policyRaw' { New-WorkerPerfHealthValue 'unreadable' 'rights' }
        Set-WorkerPerfWinHealthValue $ctx 'vda.version' { }
        Set-WorkerPerfWinHealthValue $ctx 'vda.desktopService' { 'Running' }
        Set-WorkerPerfWinHealthValue $ctx 'vda.listOfSids' { throw (New-WinStandInDenied 'win32') }
        Set-WorkerPerfWinHealthValue $ctx 'vda.farmGuid' { throw (New-WinStandInDenied 'cim') }
        $v = $ctx.Values
        $v['vda.controllers'].State | Should -Be 'read'; ($v['vda.controllers'].Value -is [array]) | Should -BeTrue; @($v['vda.controllers'].Value).Count | Should -Be 0
        $v['vda.services'].State | Should -Be 'read'; ($v['vda.services'].Value -is [array]) | Should -BeTrue; $v['vda.services'].Value[0].State | Should -Be 'Running'
        $v['vda.policyRaw'].State | Should -Be 'unreadable'; $v['vda.policyRaw'].Reason | Should -Be 'rights'
        $v['vda.version'].State | Should -Be 'absent'; $v['vda.version'].Reason | Should -Be ''; $v['vda.desktopService'].Value | Should -Be 'Running'
        $v['vda.listOfSids'].Reason | Should -Be 'rights'; $v['vda.farmGuid'].Reason | Should -Be 'rights'
        $ctx.Values.Clear(); Set-WorkerPerfWinHealthValue $ctx 'vda.farmGuid' { throw 'kaputt' }; $ctx.Values['vda.farmGuid'].Reason | Should -Be 'error'
    }
    It 'uebersetzt die Hilfsklasse' {
        Register-WorkerPerfHealthType; $t = 'WorkerPerf.HealthNative' -as [type]
        $t | Should -Not -BeNullOrEmpty; foreach ($m in 'GetCommit', 'GetActivePowerScheme') { $t.GetMethod($m) | Should -Not -BeNullOrEmpty -Because $m }
    }
    It 'liest das Datum eines Updates nur in einer Form, die es sicher kennt' {
        $qfe = { param($id, $on) [pscustomobject]@{ HotFixID = $id; InstalledOn = $on } }
        $script:WinFake.Cim['Win32_QuickFixEngineering'] = @((& $qfe 'KB1' '10/14/2026'), (& $qfe 'KB2' '14.10.2026'), (& $qfe 'KB3' '1d9a3c'), (& $qfe 'KB4' ''))
        $h = Read-Health; (Get-V $h 'operation.lastUpdateId').Value | Should -Be 'KB1'; (Get-V $h 'operation.lastUpdate').Value | Should -Be (ConvertTo-WorkerPerfHealthTime ([datetime]'2026-10-14'))
        $script:WinFake.Cim['Win32_QuickFixEngineering'] = @((& $qfe 'KB2' '14.10.2026'), (& $qfe 'KB3' '1d9a3c'))
        $h = Read-Health; (Get-V $h 'operation.lastUpdate').State | Should -Be 'absent'; (Get-V $h 'operation.lastUpdateId').State | Should -Be 'absent'
    }
    It 'meldet einen Bereich ohne Leser und einen Leser, der wirft, als nicht gelesen' {
        $keep = $script:WorkerPerfWinHealthReaders
        function Read-TestThrows($Ctx) { Set-WorkerPerfWinHealthValue $Ctx 'operation.pendingRename' { 3 }; throw 'Testfehler im Leser' }
        $script:WorkerPerfWinHealthReaders = [ordered]@{ size = $keep['size']; operation = 'Read-TestThrows' }
        try { $h = Read-Health } finally { $script:WorkerPerfWinHealthReaders = $keep }
        $h.Areas['size'].Status | Should -Be 'read'; $h.Areas['events'].Status | Should -Be 'failed'; $h.Areas['events'].Error | Should -Be 'noReader'
        $h.Areas['operation'].Status | Should -Be 'partial'; $h.Areas['operation'].Error | Should -Be 'Testfehler im Leser'; (Get-V $h 'operation.pendingRename').Value | Should -Be 3
    }
    It 'liest ohne Zustand nichts' {
        Read-Health @('Zustand') | Should -BeNullOrEmpty
        @($script:WinFake.Calls.Keys | Where-Object { $_ -match '^registry:(?!print)|^native:|Win32_PageFileUsage|Win32_LogicalDisk|winevent:oldest' }) | Should -BeNullOrEmpty
    }
    It 'unterscheidet nicht vorhanden, nicht installiert und nicht lesbar' {   # Review Focus 3
        $script:WinFake.Registry.Remove('SOFTWARE\VMware, Inc.\VMware Tools'); $script:WinFake.Registry.Remove('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{A1}')
        $script:WinFake.Services = @($script:WinFake.Services | Where-Object Name -ne 'VMTools'); $script:WinFake.Cim['Win32_QuickFixEngineering'] = @(); $script:WinFake.Cim['Win32_SystemDriver'] = @()
        $script:WinFake.RegistryFail['SYSTEM\CurrentControlSet\Control\Session Manager'] = New-Object System.Security.SecurityException 'kein Zugriff'
        $script:WinFake.Logs = @($script:WinFake.Logs | Where-Object { $_ -ne 'Microsoft-Windows-SMBClient/Connectivity' })
        $h = Read-Health
        (Get-V $h 'size.vmtoolsPresent').Value | Should -BeFalse; (Get-V $h 'size.vmtoolsService').State | Should -Be 'absent'; (Get-V $h 'size.vmtoolsService').Reason | Should -Be 'notInstalled'
        (Get-V $h 'size.vmtoolsVersion').Reason | Should -Be 'notInstalled'; (Get-V $h 'size.balloonDriver').Reason | Should -Be 'notInstalled'; (Get-V $h 'operation.lastUpdate').State | Should -Be 'absent'; (Get-V $h 'operation.lastUpdate').Reason | Should -Be ''
        (Get-V $h 'operation.pendingRename').State | Should -Be 'unreadable'; (Get-V $h 'operation.pendingRename').Reason | Should -Be 'rights'
        $smb = (Get-V $h 'events.logs').Value | Where-Object Log -eq 'Microsoft-Windows-SMBClient/Connectivity'; $smb.Present | Should -BeFalse; $smb.Enabled | Should -BeNullOrEmpty
        # ein Protokoll, das sich nicht abfragen laesst, ist nicht lesbar, nicht "nicht vorhanden"
        $script:WinFake.LogFail['System'] = New-Object System.UnauthorizedAccessException 'Zugriff verweigert'
        $h = Read-Health; (Get-V $h 'events.logs').State | Should -Be 'unreadable'; (Get-V $h 'events.logs').Reason | Should -Be 'rights'; $h.Areas['events'].Status | Should -Be 'failed'
    }
    It 'ordnet eine Abfrage, die an ihrem Zeitlimit endet, als Zeitlimit ein und liest sie im naechsten Bereich noch einmal' {   # Fix 1
        # Zeit vor der Abfrage: der Rest des Limits von 2,5 s ist keine ganze Zahl von Sekunden
        $script:WinFake.DelayOnce['native:perfinfo'] = 600; $script:WinFake.DelayOnce['cim:Win32_PageFileUsage'] = 30000; $script:WorkerPerfWinHealthAreaBudgetSec = 2.5
        try { $h = Read-Health } finally { $script:WorkerPerfWinHealthAreaBudgetSec = 10 }
        (Get-V $h 'size.pagefiles').State | Should -Be 'unreadable'; (Get-V $h 'size.pagefiles').Reason | Should -Be 'timeout'
        (Get-V $h 'size.storageControllers').Reason | Should -Be 'timeout'                    # die Abfrage endet erst am Limit des Bereichs
        $script:WinFake.Calls['cim:Win32_PageFileUsage'] | Should -Be 2                         # der Bereich operation liest noch einmal
        $c = (Get-V $h 'operation.volumes').Value | Where-Object Drive -eq 'C:'; $c.PageFile | Should -BeTrue
    }
    It 'erkennt ein Zeitlimit und verweigerten Zugriff an der Ausnahme selbst' {   # Fix 1, Fix 4
        $ctx = @{ Area = 'size'; State = $null; Clock = [System.Diagnostics.Stopwatch]::StartNew(); BudgetMs = 10000; Shared = @{}; Values = [ordered]@{} }
        Get-WorkerPerfWinHealthFailReason $ctx (New-Object System.TimeoutException 'Zeitlimit') | Should -Be 'timeout'
        Get-WorkerPerfWinHealthFailReason $ctx (New-WinStandInTimedOut 2150858793) | Should -Be 'timeout'       # ERROR_WSMAN_OPERATION_TIMEDOUT
        Get-WorkerPerfWinHealthFailReason $ctx (New-WinStandInTimedOut 2147749993) | Should -Be 'timeout'       # WBEM_E_TIMED_OUT
        Get-WorkerPerfWinHealthFailReason $ctx (New-WinStandInTimedOut 2147749889) | Should -Be 'error'         # WBEM_E_FAILED
        $wrapped = New-Object System.Management.Automation.MethodInvocationException 'Aufruf', (New-Object System.TimeoutException 'Zeitlimit')
        Get-WorkerPerfWinHealthFailReason $ctx $wrapped | Should -Be 'timeout'
        Get-WorkerPerfWinHealthFailReason $ctx (New-Object System.Runtime.InteropServices.COMException 'verweigert', -2147024891) | Should -Be 'rights'   # 0x80070005
        Get-WorkerPerfWinHealthFailReason $ctx (New-Object System.Runtime.InteropServices.COMException 'verweigert', -2147217405) | Should -Be 'rights'   # 0x80041003
        Get-WorkerPerfWinHealthFailReason $ctx (New-Object System.Runtime.InteropServices.COMException 'kaputt', -2147217407) | Should -Be 'error'       # 0x80041001
    }
    It 'liest die Programmliste, auch wenn ein Eintrag nicht lesbar ist' {   # Fix 2
        $script:WinFake.RegistryFail['SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{B2}'] = New-Object System.UnauthorizedAccessException 'Zugriff verweigert'
        $h = Read-Health
        (Get-V $h 'size.vmtoolsVersion').State | Should -Be 'read'; (Get-V $h 'size.vmtoolsVersion').Value | Should -Be '12.3.5.22544099'
    }
    It 'beendet das Lesen der Programmliste am Zeitlimit, und der naechste Bereich liest sie noch einmal' {   # Fix 2
        $root = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        foreach ($k in '{A1}', '{B2}', '{C3}') { $script:WinFake.Delay['registry:' + $root + '\' + $k] = 600 }
        $ctx = @{ Area = 'size'; State = $null; Clock = [System.Diagnostics.Stopwatch]::StartNew(); BudgetMs = 1000; Shared = @{}; Values = [ordered]@{} }
        { Get-WorkerPerfWinHealthUninstall $ctx } | Should -Throw
        $ctx.Shared['uninstall'].Reason | Should -Be 'timeout'
        $script:WinFake.Calls.Keys | Should -Not -Contain ('registry:' + $root + '\{C3}')     # nach dem Limit kein Eintrag mehr
        $script:WinFake.Delay.Clear()
        $ctx2 = @{ Area = 'operation'; State = $null; Clock = [System.Diagnostics.Stopwatch]::StartNew(); BudgetMs = 10000; Shared = $ctx.Shared; Values = [ordered]@{} }
        $list = @(Get-WorkerPerfWinHealthUninstall $ctx2); $list.Count | Should -Be 3
        $script:WinFake.Calls['registry:' + $root + '\{A1}'] | Should -Be 2
    }
}
Describe 'Zustandsbild unter Windows: Sitzungen, Citrix VDA, Profilverwaltung' {
    BeforeEach { Reset-WinStandIns }
    It 'liest Sitzungen mit Trennzeitpunkt, Zeitlimits und lokale Profile' {
        $script:WinFake.Sessions.Add([pscustomobject]@{ SessionId = 3; State = 'Disconnected'; WinStation = ''; User = 'gast'; Domain = 'KLINIK'; ClientName = 'WS-0002'
                LogonTime = [datetime]::Now.AddHours(-30); IdleSec = 7200; ConnectTime = [datetime]::Now.AddHours(-30); DisconnectTime = [datetime]::Now.AddHours(-26) })
        $h = Read-Health; $h.Areas['sessions'].Status | Should -Be 'read'
        $s = (Get-V $h 'sessions.list').Value; @($s).Count | Should -Be 3
        $g = $s | Where-Object User -eq 'gast'; $g.State | Should -Be 'Disconnected'; $g.Client | Should -Be 'WS-0002'; $g.Domain | Should -Be 'KLINIK'; $g.IdleMinutes | Should -Be 120
        ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - $g.DisconnectTime) / 3600000 | Should -BeGreaterThan 25.9
        ($s | Where-Object User -eq 'mueller').DisconnectTime | Should -Be 0           # ein Sitzungsobjekt ohne das Feld: unbekannt
        ((Get-V $h 'sessions.limits').Value | Where-Object Terminal -eq 'ICA-CGP').DisconnectedLimitMin | Should -Be 0
        $script:WinFake.Cim['Win32_TSSessionSetting'][1].DisconnectedSessionLimit = 14400000; $script:WinFake.Cim['Win32_TSSessionSetting'][1].PolicySourceDisconnectedSessionLimit = 1
        $l = (Get-V (Read-Health) 'sessions.limits').Value | Where-Object Terminal -eq 'ICA-CGP'; $l.DisconnectedLimitMin | Should -Be 240; $l.FromPolicy | Should -BeTrue
        $p = (Get-V $h 'sessions.localProfiles').Value; @($p).Count | Should -Be 4
        @(($p | Where-Object { -not $_.Loaded -and -not $_.Special }).Path) | Should -Be @('C:\Users\gast', 'C:\Users\TEMP'); ($p | Where-Object Path -eq 'C:\Users\TEMP').Temporary | Should -BeTrue
        $script:WinFake.CimFail['Win32_TSSessionSetting'] = New-WinStandInDenied 'cim'
        $h = Read-Health; (Get-V $h 'sessions.limits').Reason | Should -Be 'rights'; (Get-V $h 'sessions.list').State | Should -Be 'read'; $h.Areas['sessions'].Status | Should -Be 'partial'
    }
    It 'liest Version, Dienste und Controllerliste des VDA; die Richtlinie geht vor' {
        $h = Read-Health; $h.Areas['vda'].Status | Should -Be 'read'
        (Get-V $h 'vda.version').Value | Should -Be '2203.0.4000.4033'; (Get-V $h 'vda.desktopService').Value | Should -Be 'Running'
        @((Get-V $h 'vda.services').Value.Name) | Should -Be @('BrokerAgent', 'ctxProfile', 'WemAgentSvc', 'WemLogonSvc', 'CtxTeamsSvc', 'CtxHdxWebSocketService', 'CpSvc')
        $c = (Get-V $h 'vda.controllers').Value; @($c.Entry) | Should -Be @('ddc01.klinik.example', 'ddc02'); @($c.Kind) | Should -Be @('fqdn', 'short'); @($c.From | Select-Object -Unique) | Should -Be @('policy')
        (Get-V $h 'vda.listOfSids').Value | Should -BeTrue; (Get-V $h 'vda.farmGuid').Value | Should -BeFalse
        $raw = (Get-V $h 'vda.policyRaw').Value; ($raw | Where-Object Name -eq 'SimDrucker').Value | Should -Be '\\prn01\Etage2'; ($raw | Where-Object Name -eq 'SimDrucker').Key | Should -Be 'ICAPolicies'
        @($raw | Where-Object { $_.Key -match 'UserProfileManager|VirtualDesktopAgent' }).Count | Should -Be 0
        ($h | ConvertTo-Json -Depth 12) | Should -Not -Match 'S-1-5-21-1-2-3-1001'                # der Inhalt von ListOfSIDs wird nicht gespeichert
        $script:WinFake.Registry.Remove('SOFTWARE\Policies\Citrix\VirtualDesktopAgent')
        $c = (Get-V (Read-Health) 'vda.controllers').Value; @($c.Entry) | Should -Be @('10.1.1.5'); $c[0].Kind | Should -Be 'ip'; $c[0].From | Should -Be 'registry'
        ConvertTo-WorkerPerfControllerKind 'fd00::5' | Should -Be 'ip'
    }
    It 'nennt einen Worker ohne VDA und ohne Profilverwaltung nicht installiert' {   # Review Focus 3
        $script:WinFake.Services = @($script:WinFake.Services | Where-Object { $_.PathName -notmatch 'Citrix' }); $script:WinFake.Cim.Remove('Citrix_VirtualDesktopInfo')
        foreach ($k in @($script:WinFake.Registry.Keys | Where-Object { $_ -match 'Citrix|\{B2\}' })) { $script:WinFake.Registry.Remove($k) }
        $script:WinFake.Disks.Clear()
        $h = Read-Health
        foreach ($id in 'vda.version', 'vda.desktopService', 'profile.service', 'profile.version', 'vda.persistentDataLocation', 'vda.wemService', 'vda.wemServices', 'vda.wemVersion', 'vda.wemServer',
            'vda.wemCacheLocation', 'vda.wemGpNetworkTimeout', 'vda.teamsService', 'vda.webSocketService') { (Get-V $h $id).State | Should -Be 'absent' -Because $id; (Get-V $h $id).Reason | Should -Be 'notInstalled' -Because $id }
        foreach ($id in 'vda.controllers', 'vda.services', 'vda.policyRaw', 'profile.containers', 'profile.policyGpo') { (Get-V $h $id).State | Should -Be 'read' -Because $id; @((Get-V $h $id).Value).Count | Should -Be 0 -Because $id }
        $h.Areas['vda'].Status | Should -Be 'read'; $h.Areas['profile'].Status | Should -Be 'read'
    }
    It 'liest den WEM-Agenten, die Dienste der Teams-Umleitung und den bestaendigen Datenort' {
        $h = Read-Health
        (Get-V $h 'vda.wemService').Value | Should -Be 'Running'; (Get-V $h 'vda.wemVersion').Value | Should -Be '2407.1.0.1'
        @((Get-V $h 'vda.wemServices').Value.Name) | Should -Be @('Citrix WEM Agent Host Service', 'Citrix WEM User Logon Service', 'System Event Notification Service')
        @((Get-V $h 'vda.wemServices').Value.StartMode | Select-Object -Unique) | Should -Be @('Auto')
        (Get-V $h 'vda.wemServer').Value | Should -Be 'wem01.klinik.example'; (Get-V $h 'vda.wemCacheLocation').Value | Should -Be 'D:\WEMCache'; (Get-V $h 'vda.wemGpNetworkTimeout').Value | Should -Be 120
        (Get-V $h 'vda.teamsService').Value | Should -Be 'Running'; (Get-V $h 'vda.webSocketService').Value | Should -Be 'Running'; (Get-V $h 'vda.persistentDataLocation').Value | Should -Be 'D:\PersistentData'
        # der fruehere Anzeigename zaehlt; ein leerer Cache-Ort heisst: nicht gesetzt
        ($script:WinFake.Services | Where-Object Name -eq 'WemAgentSvc').DisplayName = 'Norskale Agent Host Service'
        $script:WinFake.Registry['SYSTEM\CurrentControlSet\Control\Norskale\Agent Host']['AgentCacheAlternateLocation'] = ''
        $h = Read-Health; (Get-V $h 'vda.wemService').Value | Should -Be 'Running'; @((Get-V $h 'vda.wemServices').Value.Name)[0] | Should -Be 'Norskale Agent Host Service'
        (Get-V $h 'vda.wemCacheLocation').State | Should -Be 'absent'; (Get-V $h 'vda.wemCacheLocation').Reason | Should -Be ''
        # ein Worker mit VDA, aber ohne WEM-Agent                                                     # Review Focus 3
        $script:WinFake.Services = @($script:WinFake.Services | Where-Object { $_.Name -notlike 'Wem*' })
        $script:WinFake.Calls.Clear()                                                                     # ZB-R12: nur die Lesung ohne Agent zaehlt
        $h = Read-Health; foreach ($id in 'vda.wemService', 'vda.wemServices', 'vda.wemCacheLocation', 'vda.wemGpNetworkTimeout') { (Get-V $h $id).Reason | Should -Be 'notInstalled' -Because $id }
        $script:WinFake.Calls.Keys | Should -Not -Contain 'registry:SOFTWARE\Policies\Norskale\Agent Host'
        (Get-V $h 'vda.version').State | Should -Be 'read'; $h.Areas['vda'].Status | Should -Be 'read'
    }
    It 'findet das Programm eines Dienstes auch in Anfuehrungszeichen und mit Argumenten' {
        Get-WorkerPerfServiceExe '"C:\Program Files\Citrix\User Profile Manager\UserProfileManager.exe" /svc' | Should -Be 'C:\Program Files\Citrix\User Profile Manager\UserProfileManager.exe'
        Get-WorkerPerfServiceExe 'C:\Windows\System32\svchost.exe -k netsvcs -p' | Should -Be 'C:\Windows\System32\svchost.exe'
        Get-WorkerPerfServiceExe 'C:\Program Files\Citrix\System32\CpSvc.exe' | Should -Be 'C:\Program Files\Citrix\System32\CpSvc.exe'; Get-WorkerPerfServiceExe '' | Should -Be ''
        ($script:WinFake.Services | Where-Object Name -eq 'ctxProfile').PathName | Should -BeLike '"*UserProfileManager.exe"'      # der Platzhalter traegt die Form von Windows
        $h = Read-Health; (Get-V $h 'profile.service').Value | Should -Be 'Running'; (Get-V $h 'profile.version').Value | Should -Be '22.3.0.4000'; (Get-V $h 'vda.wemVersion').Value | Should -Be '2407.1.0.1'
        ($script:WinFake.Services | Where-Object Name -eq 'ctxProfile').PathName = '"C:\Program Files\Citrix\User Profile Manager\UserProfileManager.exe" /service'
        (Get-V (Read-Health) 'profile.version').Value | Should -Be '22.3.0.4000'
    }
    It 'liest eine gemeinsame Abfrage neu, die im Bereich davor am Zeitlimit endete, und reicht fehlende Rechte weiter' {   # Review Focus 1
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null); $before = [int]$script:WinFake.Calls['cim:Win32_Service']
        $script:WinFake.DelayOnce['cim:Win32_Service'] = 5000; $script:WorkerPerfWinHealthAreaBudgetSec = 1
        try { $h = Get-WorkerPerfHealth 3>$null } finally { $script:WorkerPerfWinHealthAreaBudgetSec = 10 }
        (Get-V $h 'size.vmtoolsService').State | Should -Be 'unreadable'; (Get-V $h 'size.vmtoolsService').Reason | Should -Be 'timeout'
        (Get-V $h 'vda.services').State | Should -Be 'read'; (Get-V $h 'vda.desktopService').Value | Should -Be 'Running'; (Get-V $h 'profile.service').Value | Should -Be 'Running'
        [int]$script:WinFake.Calls['cim:Win32_Service'] - $before | Should -Be 2                       # ein zweiter Versuch im naechsten Bereich, der die Dienste braucht, danach keiner mehr
        Reset-WinStandIns; [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null); $before = [int]$script:WinFake.Calls['cim:Win32_Service']
        $script:WinFake.CimFail['Win32_Service'] = New-WinStandInDenied 'cim'; $h = Get-WorkerPerfHealth 3>$null
        foreach ($id in 'size.vmtoolsService', 'vda.services', 'profile.service') { (Get-V $h $id).State | Should -Be 'unreadable' -Because $id; (Get-V $h $id).Reason | Should -Be 'rights' -Because $id }
        [int]$script:WinFake.Calls['cim:Win32_Service'] - $before | Should -Be 1                       # fehlende Rechte: kein zweiter Versuch
    }
    It 'liest Container mit Groesse, Belegung und Besitzer' {
        $h = Read-Health; $c = (Get-V $h 'profile.containers').Value; @($c).Count | Should -Be 2
        $m = $c | Where-Object Owner -eq 'mueller'; $m.Location | Should -Be '\\fs01\upm$\mueller.KLINIK\Win2022\UPM_Profile\ProfileContainer_RW.vhdx'
        $m.Mount | Should -Be 'C:\Users\mueller_UPM_local\UpmTempMount'; $m.SessionId | Should -Be 2; $m.SizeGB | Should -Be 50; $m.AllocatedGB | Should -Be 20; $m.VolumeFreeGB | Should -Be 2; $m.UsedPct | Should -Be 96
        $g = $c | Where-Object { $_.Location -like '*gast*' }; $g.Owner | Should -Be ''; $g.SessionId | Should -Be -1; $g.UsedPct | Should -Be 40
        (Get-V $h 'profile.service').Value | Should -Be 'Running'; (Get-V $h 'profile.version').Value | Should -Be '22.3.0.4000'
        @((Get-V $h 'profile.policyGpo').Value.Name | Sort-Object) | Should -Be @('PathToUserStore', 'ServiceActive'); @((Get-V $h 'profile.policyStudio').Value).Count | Should -Be 0
        # die Schnappschuesse fragen die Volumes weiter nicht ab
        Reset-WinStandIns; [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg -Skip Zustand 3>$null); [void](Get-WorkerPerfSnapshot -Kind K)
        $script:WinFake.Calls.Keys | Should -Not -Contain 'cim:MSFT_Volume'
        Reset-WinStandIns; $script:WinFake.FailStorage = $true
        $h = Read-Health; (Get-V $h 'profile.containers').State | Should -Be 'unreadable'; (Get-V $h 'profile.service').State | Should -Be 'read'
    }
    It 'meldet eine gescheiterte Sitzungsabfrage und haelt das Zeitlimit auch in der Abfrage der Container ein' {   # Review Focus 1
        $script:WinFake.SessionsFail = New-Object System.InvalidOperationException 'WTS antwortet nicht'
        $h = Read-Health; (Get-V $h 'sessions.list').State | Should -Be 'unreadable'; (Get-V $h 'sessions.list').Reason | Should -Be 'error'; $h.Areas['sessions'].Status | Should -Be 'partial'
        $c = @((Get-V $h 'profile.containers').Value); $c.Count | Should -Be 2                    # keine Sitzungen heisst nicht: keine Container
        @($c | Where-Object { $_.Owner -ne '' }).Count | Should -Be 0; @($c | Where-Object { $_.SessionId -ne -1 }).Count | Should -Be 0
        Reset-WinStandIns; $script:WinFake.Delay['cim:MSFT_Volume'] = 5000; $script:WorkerPerfWinHealthAreaBudgetSec = 1
        try { $h = Read-Health } finally { $script:WorkerPerfWinHealthAreaBudgetSec = 10 }
        (Get-V $h 'profile.containers').State | Should -Be 'unreadable'; (Get-V $h 'profile.containers').Reason | Should -Be 'timeout'; (Get-V $h 'profile.service').State | Should -Be 'read'
        $h.Areas['profile'].Status | Should -Be 'partial'; $h.Areas['profile'].DurationMs | Should -BeLessThan 3000; $h.Areas['vda'].Status | Should -Be 'read'
    }
    It 'gibt Registrierungswerte als Text wieder und haelt Tiefe, Hoechstzahl und ausgelassene Unterschluessel ein' {
        $base = 'SOFTWARE\Policies\SimTest'
        $script:WinFake.Registry[$base] = [ordered]@{ Liste = [string[]]@('a', 'b'); Daten = [byte[]]@(1, 2, 3) }
        $script:WinFake.Registry[$base + '\Aus'] = [ordered]@{ Weg = 'x' }
        $script:WinFake.Registry[$base + '\Ein'] = [ordered]@{ Zahl = 7 }
        $script:WinFake.Registry[$base + '\Ein\Aus'] = [ordered]@{ Tief = 'y' }                 # nur oben ausgelassen
        $t = @(Get-WorkerPerfRegistryTree $base @('Aus'))
        @($t | ForEach-Object { $_.Key + '|' + $_.Name + '|' + $_.Value }) | Should -Be @('|Liste|a; b', '|Daten|binaer, 3 Byte', 'Ein|Zahl|7', 'Ein\Aus|Tief|y')
        @(Get-WorkerPerfRegistryTree $base @('Aus') -MaxDepth 1).Count | Should -Be 3; @(Get-WorkerPerfRegistryTree $base -MaxValues 2).Count | Should -Be 2
        @(Get-WorkerPerfRegistryTree 'SOFTWARE\Policies\Fehlt').Count | Should -Be 0
        $c = @(ConvertTo-WorkerPerfControllerEntries 'ddc01.klinik.example,ddc02  10.1.1.5' 'policy'); @($c.Entry) | Should -Be @('ddc01.klinik.example', 'ddc02', '10.1.1.5')
        ConvertTo-WorkerPerfControllerKind '12345' | Should -Be 'short'                             # eine Zahl ist keine Adresse
    }
    It 'haelt das Bereichslimit ueber alle drei Abfragen der Container ein' {   # Fix-Runde 1, Punkt 1
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null)
        foreach ($cls in 'MSFT_Disk', 'MSFT_Partition', 'MSFT_Volume') { $script:WinFake.Delay['cim:' + $cls] = 4000 }
        $script:WorkerPerfWinHealthAreaBudgetSec = 5
        try { $h = Get-WorkerPerfHealth 3>$null } finally { $script:WorkerPerfWinHealthAreaBudgetSec = 10 }
        (Get-V $h 'profile.containers').State | Should -Be 'unreadable'; (Get-V $h 'profile.containers').Reason | Should -Be 'timeout'
        $h.Areas['profile'].DurationMs | Should -BeLessThan 6500                                    # nicht 12 s: jede Abfrage bekommt nur den Rest
        $script:WinFake.Calls.Keys | Should -Not -Contain 'cim:MSFT_Volume'                         # nach dem Limit keine Abfrage mehr
    }
    It 'beendet den Gang durch die Registrierung am Zeitlimit des Bereichs' {   # Fix-Runde 1, Punkt 2
        foreach ($i in 1..12) {
            foreach ($k in ('SOFTWARE\Policies\Citrix\Sim{0:D2}' -f $i), ('SOFTWARE\Policies\Citrix\UserProfileManager\Sim{0:D2}' -f $i)) {
                $script:WinFake.Registry[$k] = [ordered]@{ SimWert = $i }; $script:WinFake.Delay['registry:' + $k] = 250
            }
        }
        $script:WorkerPerfWinHealthAreaBudgetSec = 1
        try { $h = Read-Health } finally { $script:WorkerPerfWinHealthAreaBudgetSec = 10 }
        foreach ($id in 'vda.policyRaw', 'profile.policyGpo') { (Get-V $h $id).State | Should -Be 'unreadable' -Because $id; (Get-V $h $id).Reason | Should -Be 'timeout' -Because $id }
        $h.Areas['vda'].DurationMs | Should -BeLessThan 2500; $h.Areas['profile'].DurationMs | Should -BeLessThan 2500   # nicht 3 s fuer 12 Unterschluessel
    }
    It 'laesst die Kopien der Benutzerrichtlinien je Sitzung in den Rohwerten der Richtlinie aus' {   # Fix-Runde 1, Punkt 3
        $script:WinFake.Registry['SOFTWARE\Policies\Citrix\0'] = [ordered]@{}
        $script:WinFake.Registry['SOFTWARE\Policies\Citrix\0\User'] = [ordered]@{ SimSitzung = 1 }
        $script:WinFake.Registry['SOFTWARE\Policies\Citrix\12'] = [ordered]@{ SimZwoelf = 1 }
        $script:WinFake.Registry['SOFTWARE\Policies\Citrix\12\User'] = [ordered]@{ SimSitzung = 2 }
        $raw = @((Get-V (Read-Health) 'vda.policyRaw').Value)
        @($raw.Key | Select-Object -Unique) | Should -Be @('ICAPolicies'); @($raw.Name | Sort-Object) | Should -Be @('SimDrucker', 'SimRichtlinie')
    }
    It 'macht aus einem Registrierungswert vom falschen Typ keinen Text' {   # Fix-Runde 1, Punkt 4
        $script:WinFake.Registry['SYSTEM\CurrentControlSet\Control\Norskale\Agent Host']['AgentCacheAlternateLocation'] = [byte[]](0, 0)
        $script:WinFake.Registry['SOFTWARE\Policies\Norskale\Agent Host']['BrokerSvcName'] = [string[]]@('wem01.klinik.example')   # eine Zeichenkette als Liste: bleibt eine Liste
        $h = Read-Health
        foreach ($id in 'vda.wemCacheLocation', 'vda.wemServer') { (Get-V $h $id).State | Should -Be 'unreadable' -Because $id; (Get-V $h $id).Reason | Should -Be 'error' -Because $id }
        (Get-V $h 'vda.wemService').State | Should -Be 'read'
    }
    It 'liest Pfade der Richtlinie so, wie sie geschrieben stehen' {   # Fix-Runde 1, Punkt 5
        ((Get-V (Read-Health) 'profile.policyGpo').Value | Where-Object Name -eq 'PathToUserStore').Value | Should -Be '\\fs01\upm$\%USERNAME%.%USERDOMAIN%'
        # der duenne Aufruf (unter Linux nicht ausfuehrbar) erweitert REG_EXPAND_SZ nicht
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../src/WorkerPerf.Sources.Windows.ps1'), [ref]$null, [ref]$null)
        $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-WorkerPerfRegistryValues' }, $true)
        $fn.Body.Extent.Text | Should -Match 'GetValue\(\$name, \$null, \[Microsoft\.Win32\.RegistryValueOptions\]::DoNotExpandEnvironmentNames\)'
    }
    It 'beendet die Schleifen ueber Sitzungen und Container am Zeitlimit des Bereichs' {   # Fix-Runde 1, Punkt 6
        foreach ($i in 1..12) { $script:WinFake.Sessions.Add([pscustomobject]@{ SessionId = 10 + $i; State = 'Active'; WinStation = ''; User = ('sim{0:D2}' -f $i); Domain = 'KLINIK'; ClientName = ''; LogonTime = [datetime]::Now; IdleSec = 0 }) }
        foreach ($i in 1..12) { Add-WinStandInDisk ('sim{0:D2}' -f $i) ('C:\Users\sim{0:D2}_UPM_local\UpmTempMount' -f $i) (300 + $i) }
        Mock ConvertTo-WorkerPerfHealthSession { Start-Sleep -Milliseconds 250; [ordered]@{ Id = 0 } }
        Mock ConvertTo-WorkerPerfProfileContainer { Start-Sleep -Milliseconds 250; [ordered]@{ Location = '' } }
        $script:WorkerPerfWinHealthAreaBudgetSec = 1
        try { $h = Read-Health } finally { $script:WorkerPerfWinHealthAreaBudgetSec = 10 }
        foreach ($id in 'sessions.list', 'profile.containers') { (Get-V $h $id).State | Should -Be 'unreadable' -Because $id; (Get-V $h $id).Reason | Should -Be 'timeout' -Because $id }
        $h.Areas['sessions'].DurationMs | Should -BeLessThan 2500; $h.Areas['profile'].DurationMs | Should -BeLessThan 2500
    }
    It 'nennt einen anderen Fehler der VDA-Klasse nicht: nicht installiert' {   # Fix-Runde 1, Punkt 7
        $script:WinFake.CimFail['Citrix_VirtualDesktopInfo'] = New-WinStandInDenied 'cim'
        $v = Get-V (Read-Health) 'vda.persistentDataLocation'; $v.State | Should -Be 'unreadable'; $v.Reason | Should -Be 'rights'
    }
}
Describe 'Zustandsbild unter Windows: Drucken, Sicherheitsprodukte, Netz, Wartung' {
    BeforeEach { Reset-WinStandIns }
    It 'liest den Bereich Drucken auch ohne die Kategorie Drucken' {
        $script:WinFake.Logs += 'Microsoft-Windows-PrintService/Operational'; $script:WinFake.DisabledLogs += 'Microsoft-Windows-PrintService/Operational'
        foreach ($skip in @(), @('Drucken')) {
            $h = Read-Health $skip; $h.Areas['print'].Status | Should -Be 'read' -Because "$skip"
            (Get-V $h 'print.isolationExecution').Value | Should -Be 1; (Get-V $h 'print.isolationOverride').State | Should -Be 'absent'
            (Get-V $h 'print.queueCount').Value | Should -Be 1; (Get-V $h 'print.spooler').Value | Should -Be 'Running'; (Get-V $h 'print.spoolerStartMode').Value | Should -Be 'Auto'
            (Get-V $h 'print.operationalLog').Value | Should -BeFalse; (Get-V $h 'print.citrixPrintService').Value | Should -Be 'Running'; (Get-V $h 'print.mappingClientVersion').Value | Should -Be '6.2.1'
        }
        $script:WinFake.Logs = @($script:WinFake.Logs | Where-Object { $_ -ne 'Microsoft-Windows-PrintService/Operational' })
        (Get-V (Read-Health) 'print.operationalLog').State | Should -Be 'absent'
        $script:WinFake.Registry.Remove('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{C3}')                  # Review Focus 3: kein Client des Zuordnungswerkzeugs
        $m = Get-V (Read-Health) 'print.mappingClientVersion'; $m.State | Should -Be 'absent'; $m.Reason | Should -Be 'notInstalled'
    }
    It 'nennt die Richtlinie der Treiberisolierung nicht lesbar, wenn schon der Treiberleser sie nicht lesen konnte' {
        $script:WinFake.IsolationPolicyFail = New-Object System.Security.SecurityException 'kein Zugriff'
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null); [void]@(Get-WorkerPerfPrintDrivers 3>$null); $h = Get-WorkerPerfHealth 3>$null
        foreach ($id in 'print.isolationExecution', 'print.isolationOverride') { (Get-V $h $id).State | Should -Be 'unreadable' -Because $id; (Get-V $h $id).Reason | Should -Be 'rights' -Because $id }
        (Get-V $h 'print.spooler').State | Should -Be 'read'
    }
    It 'liest Defender, Filtertreiber, Dienste und AppLocker' {
        $h = Read-Health; $h.Areas['security'].Status | Should -Be 'read'
        (Get-V $h 'security.defenderMode').Value | Should -Be 'Normal'; (Get-V $h 'security.defenderSignatureAgeDays').Value | Should -Be 1; (Get-V $h 'security.defenderService').Value | Should -Be 'Running'
        (Get-V $h 'security.defenderExclusionProcesses').Value[0].Path | Should -Be 'C:\Program Files\Citrix\User Profile Manager\UserProfileManager.exe'
        (Get-V $h 'security.defenderExclusionExtensions').Value[0].Extension | Should -Be '.vhdx'; (Get-V $h 'security.defenderSharedSignatures').State | Should -Be 'absent'
        (Get-V $h 'security.mdeOnboarding').Value | Should -Be 1; (Get-V $h 'security.mdeService').Value | Should -Be 'Running'; (Get-V $h 'security.defenderForcePassive').State | Should -Be 'absent'
        @((Get-V $h 'security.filters').Value.Name) | Should -Be @('WdFilter', 'upmjit', 'FileInfo'); (Get-V $h 'security.filters').Value[0].Altitude | Should -Be '328010'
        @((Get-V $h 'security.services').Value).Count | Should -Be @($script:WinFake.Services).Count; ((Get-V $h 'security.services').Value | Where-Object Name -eq 'WinDefend').State | Should -Be 'Running'
        @((Get-V $h 'security.applockerCollections').Value.Collection) | Should -Be @('Exe', 'Dll')
        $dll = (Get-V $h 'security.applockerCollections').Value | Where-Object Collection -eq 'Dll'; $dll.Enforcement | Should -Be 1; $dll.Rules | Should -Be 1
        (Get-V $h 'security.defenderNetworkProtection').Value | Should -Be 0
    }
    It 'nennt verborgene Ausschluesse nicht lesbar und einen fehlenden Defender nicht installiert' {   # Review Focus 3
        $script:WinFake.Cim['MSFT_MpPreference'][0].ExclusionPath = @('N/A: Must be an administrator to view exclusions')
        $h = Read-Health; (Get-V $h 'security.defenderExclusionPaths').State | Should -Be 'unreadable'; (Get-V $h 'security.defenderExclusionPaths').Reason | Should -Be 'rights'
        (Get-V $h 'security.defenderExclusionProcesses').State | Should -Be 'read'; $h.Areas['security'].Status | Should -Be 'partial'
        $script:WinFake.FiltersFail = New-Object System.UnauthorizedAccessException 'Zugriff verweigert'
        (Get-V (Read-Health) 'security.filters').Reason | Should -Be 'rights'
        Reset-WinStandIns; $script:WinFake.Services = @($script:WinFake.Services | Where-Object Name -ne 'WinDefend')
        $h = Read-Health
        foreach ($id in 'security.defenderService', 'security.defenderMode', 'security.defenderExclusionPaths', 'maintenance.scanDay', 'maintenance.scanRandomize') {
            (Get-V $h $id).State | Should -Be 'absent' -Because $id; (Get-V $h $id).Reason | Should -Be 'notInstalled' -Because $id }
        @($script:WinFake.Calls.Keys | Where-Object { $_ -match 'MSFT_Mp' }) | Should -BeNullOrEmpty; (Get-V $h 'security.filters').State | Should -Be 'read'
    }
    It 'liest SMB, DNS und Zeitquelle und fasst die Verbindungen zusammen' {
        $h = Read-Health; $h.Areas['network'].Status | Should -Be 'read'
        $c = (Get-V $h 'network.smbConnections').Value; @($c).Count | Should -Be 2
        ($c | Where-Object Share -eq '\\fs01\upm$').Connections | Should -Be 2; ($c | Where-Object Share -eq '\\alt01\archiv').Dialect | Should -Be '2.1'; ($c | Where-Object Share -eq '\\alt01\archiv').Signed | Should -BeFalse
        (Get-V $h 'network.smb1').State | Should -Be 'absent'; (Get-V $h 'network.smb1').Reason | Should -Be ''
        (Get-V $h 'network.smbDirectoryCache').Value | Should -Be 16; (Get-V $h 'network.smbRequireSigning').Value | Should -BeFalse; (Get-V $h 'network.domainMember').Value | Should -BeTrue
        @((Get-V $h 'network.dnsServers').Value | ForEach-Object { $_.Address }) | Should -Be @('10.1.0.10')   # .Address alone would name the method Address of the array
        (Get-V $h 'network.dnsServers').Value[0].Interface | Should -Be 4
        (Get-V $h 'network.timeType').Value | Should -Be 'NTP'; (Get-V $h 'network.timeServers').Value | Should -Be 'zeit01.klinik.example 10.1.0.20'; (Get-V $h 'network.timeService').Value | Should -Be 'Running'
        $rss = @((Get-V $h 'network.rss').Value); $rss.Count | Should -Be 1; $rss[0].Description | Should -Be 'vmxnet3 Ethernet Adapter'; $rss[0].Enabled | Should -BeTrue
        ($h | ConvertTo-Json -Depth 12) | Should -Not -Match 'Ethernet0'                                 # der Verbindungsname eines Adapters wird nicht gespeichert
        ($h | ConvertTo-Json -Depth 12) | Should -Not -Match 'KLINIK\\\\(mueller|gast)"'              # das Konto einer Verbindung wird nicht gespeichert
        $script:WinFake.Cim['Win32_SystemDriver'] = @([pscustomobject]@{ Name = 'mrxsmb10'; State = 'Running'; StartMode = 'Auto' })
        (Get-V (Read-Health) 'network.smb1').Value | Should -Be 'Auto'
    }
    It 'liest geplante Aufgaben, Scan- und Update-Zeitplaene' {
        $h = Read-Health; $h.Areas['maintenance'].Status | Should -Be 'read'
        $t = (Get-V $h 'maintenance.tasks').Value; @($t.Path) | Should -Be @('\Sim\Inventarlauf', '\Sim\Anmeldeskript')
        $t[0].Triggers | Should -Be 'daily'; $t[1].Triggers | Should -Be 'logon'; $t[1].NextRun | Should -Be 0; $t[0].Action | Should -Be 'C:\Tools\inventar.exe'
        [DateTimeOffset]::FromUnixTimeMilliseconds($t[0].NextRun).LocalDateTime.Hour | Should -Be 10
        (Get-V $h 'maintenance.taskCount').Value | Should -Be 150; ConvertTo-WorkerPerfTriggerWords @(9, 6, 9, 42) | Should -Be 'logon, idle, other'
        ConvertTo-WorkerPerfTaskTime ([datetime]'1899-12-30') | Should -Be ([datetime]::MinValue); ConvertTo-WorkerPerfTaskTime ([datetime]'2026-11-13T10:00:00') | Should -Be ([datetime]'2026-11-13T10:00:00')
        $t[0].LastRun | Should -Be 0; $t[1].LastRun | Should -Be 0                                    # der 30.12.1899 der Aufgabenplanung heisst: kein Lauf
        (Get-V $h 'maintenance.scanDay').Value | Should -Be 0; (Get-V $h 'maintenance.scanTime').Value | Should -Be '02:00'; (Get-V $h 'maintenance.scanRandomize').Value | Should -BeTrue
        (Get-V $h 'maintenance.updateOptions').Value | Should -Be 4; (Get-V $h 'maintenance.updateHour').Value | Should -Be 10
        (Get-V $h 'maintenance.searchService').State | Should -Be 'absent'; (Get-V $h 'maintenance.searchService').Reason | Should -Be 'notInstalled'
        (Get-V $h 'maintenance.updateService').Value | Should -Be 'Manual'
        $script:WinFake.Registry.Remove('SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU')
        (Get-V (Read-Health) 'maintenance.updateOptions').State | Should -Be 'absent'; (Get-V (Read-Health) 'maintenance.updateOptions').Reason | Should -Be ''
    }
    It 'liest Dienste, Sitzungen und Defender-Einstellungen fuer alle Bereiche einmal und die Richtlinie des Treiberlesers nicht noch einmal' {
        [void](Initialize-WorkerPerfSource -StartTime ([datetime]::Now) -EventConfig $Cfg 3>$null); [void]@(Get-WorkerPerfPrintDrivers)
        $before = $script:WinFake.Calls.Clone(); $h = Get-WorkerPerfHealth
        foreach ($k in 'cim:Win32_Service', 'cim:Win32_SystemDriver', 'wts', 'cim:MSFT_MpPreference', 'cim:MSFT_MpComputerStatus', 'com:tasks', 'native:filters') { [int]$script:WinFake.Calls[$k] - [int]$before[$k] | Should -Be 1 -Because $k }
        [int]$script:WinFake.Calls['registry:print'] - [int]$before['registry:print'] | Should -Be 0
        @($h.Areas.Keys | Where-Object { $h.Areas[$_].Status -ne 'read' }) | Should -Be @('apps'); $h.DurationMs | Should -BeLessThan 60000      # apps hat bis Task 7 keinen Leser
        ($h.Areas.Values | ForEach-Object { $_.DurationMs } | Measure-Object -Sum).Sum | Should -BeLessOrEqual ($h.DurationMs + 1)
    }
    It 'haelt das Zeitlimit auch bei einem langsamen Aufruf ohne eigenes Zeitlimit ein' {   # Review Focus 1
        $script:WinFake.Delay['com:tasks'] = 1500; $script:WorkerPerfWinHealthAreaBudgetSec = 1
        try { $h = Read-Health } finally { $script:WorkerPerfWinHealthAreaBudgetSec = 10 }
        (Get-V $h 'maintenance.tasks').State | Should -Be 'read'                                 # der Aufruf lief schon; sein Ergebnis bleibt
        foreach ($id in 'maintenance.taskCount', 'maintenance.scanDay', 'maintenance.searchService') {
            (Get-V $h $id).State | Should -Be 'unreadable' -Because $id; (Get-V $h $id).Reason | Should -Be 'timeout' -Because $id }
        $h.Areas['maintenance'].Status | Should -Be 'partial'; foreach ($a in 'security', 'network', 'events') { $h.Areas[$a].Status | Should -Be 'read' -Because $a }
    }
    It 'speichert nur Zahlen, Wahrheitswerte, Texte und Listen daraus' {
        $script:WinFake.Cim['MSFT_MpPreference'][0].ScanScheduleQuickScanTime = [datetime]'2026-01-01T03:30:00'       # je nach Fassung der Plattform Zeitspanne oder Zeitpunkt
        $h = Read-Health; $bad = New-Object System.Collections.Generic.List[string]
        $plain = { param($x) $null -eq $x -or $x -is [string] -or $x -is [decimal] -or $x.GetType().IsPrimitive }
        foreach ($id in $WorkerPerfHealthValues.Keys) {
            $v = Get-V $h $id; if ($v.State -ne 'read') { continue }
            if ($WorkerPerfHealthValues[$id].Type -ne 'list') { if (-not (& $plain $v.Value)) { $bad.Add($id) }; continue }
            if ($v.Value -isnot [array]) { $bad.Add($id); continue }
            foreach ($item in $v.Value) { foreach ($k in @($item.Keys)) { if (-not (& $plain $item[$k])) { $bad.Add("$id.$k") } } }
        }
        $bad | Should -BeNullOrEmpty                                                             # keine Aufzaehlung, kein DateTime, keine Zeitspanne
        (Get-V $h 'maintenance.scanTime').Value | Should -Be '02:00'; (Get-V $h 'maintenance.quickScanTime').Value | Should -Be '03:30'
    }
    It 'zerlegt den Puffer der Filterabfrage und uebersetzt die Filterabfrage' {
        function New-FilterEntry([string]$Name, [string]$Altitude, [int]$Instances, [bool]$Legacy, [bool]$Last) {
            # FILTER_AGGREGATE_STANDARD_INFORMATION: NextEntryOffset (Byte 0), Flags (4: 1 Minifilter, 2 alter Filter). Minifilter: Flags (8), FrameID (12),
            # NumberOfInstances (16), dann je 2 Byte Namenslaenge, Namensoffset, Hoehenlaenge, Hoehenoffset (ab 20). Alter Filter: Flags (8), dieselben vier (ab 12).
            $n = [Text.Encoding]::Unicode.GetBytes($Name); $a = [Text.Encoding]::Unicode.GetBytes($Altitude); $head = $(if ($Legacy) { 20 } else { 28 })
            $size = [int]([Math]::Ceiling(($head + $n.Length + $a.Length) / 8) * 8) + 8; $b = New-Object byte[] $size
            for ($i = $head + $n.Length + $a.Length; $i -lt $size; $i++) { $b[$i] = 0x41 }                     # hinter den Zeichenketten steht keine Null
            $at = $(if ($Legacy) { 12 } else { 20 })
            [BitConverter]::GetBytes([uint32]$(if ($Last) { 0 } else { $size })).CopyTo($b, 0); [BitConverter]::GetBytes([uint32]$(if ($Legacy) { 2 } else { 1 })).CopyTo($b, 4)
            if (-not $Legacy) { [BitConverter]::GetBytes([uint32]$Instances).CopyTo($b, 16) }
            [BitConverter]::GetBytes([uint16]$n.Length).CopyTo($b, $at); [BitConverter]::GetBytes([uint16]$head).CopyTo($b, $at + 2)
            [BitConverter]::GetBytes([uint16]$a.Length).CopyTo($b, $at + 4); [BitConverter]::GetBytes([uint16]($head + $n.Length)).CopyTo($b, $at + 6)
            $n.CopyTo($b, $head); $a.CopyTo($b, $head + $n.Length); , $b
        }
        $buf = [byte[]]((New-FilterEntry 'WdFilter' '328010' 4 $false $false) + (New-FilterEntry 'upmAction' '265650.5' 2 $false $false) + (New-FilterEntry 'AltFilter' '45000' 0 $true $true))
        $f = @(ConvertFrom-WorkerPerfFilterBuffer $buf)
        @($f.Name) | Should -Be @('WdFilter', 'upmAction', 'AltFilter'); @($f.Altitude) | Should -Be @('328010', '265650.5', '45000')
        @($f.Instances) | Should -Be @(4, 2, 0); @($f.Legacy) | Should -Be @($false, $false, $true)
        @(ConvertFrom-WorkerPerfFilterBuffer ([byte[]]@())).Count | Should -Be 0
        Register-WorkerPerfHealthType; ('WorkerPerf.HealthNative' -as [type]).GetMethod('GetFilterBuffers') | Should -Not -BeNullOrEmpty
    }
    It 'wandelt Registrierungszahlen, Zeitquellen, Aufgaben und SMB-Verbindungen um und nimmt die Richtlinie der Zeitquelle vor dem Dienst' {
        ConvertTo-WorkerPerfRegistryNumber 4 | Should -Be 4; ConvertTo-WorkerPerfRegistryNumber (-1) | Should -Be 4294967295; ConvertTo-WorkerPerfRegistryNumber $null | Should -BeNullOrEmpty
        foreach ($wrong in @('4', [byte[]](4, 0), [string[]]@('4'))) { { ConvertTo-WorkerPerfRegistryNumber $wrong } | Should -Throw -Because "$wrong" }
        ConvertTo-WorkerPerfTimeServers 'zeit01.klinik.example,0x9  10.1.0.20' | Should -Be 'zeit01.klinik.example 10.1.0.20'
        ConvertTo-WorkerPerfClockText ([timespan]'1.07:05:00') | Should -Be '07:05'; { ConvertTo-WorkerPerfClockText '02:00' } | Should -Throw
        ConvertTo-WorkerPerfTaskState 3 | Should -Be 'Ready'; ConvertTo-WorkerPerfTaskState 'Running' | Should -Be 'Running'; ConvertTo-WorkerPerfTaskState 9 | Should -Be '9'
        ConvertFrom-WorkerPerfTaskInterval '' | Should -Be 0; ConvertFrom-WorkerPerfTaskInterval 'PT15M' | Should -Be 15; ConvertFrom-WorkerPerfTaskInterval 'P1DT1H' | Should -Be 1500
        ConvertFrom-WorkerPerfTaskInterval 'jede Stunde' | Should -BeNullOrEmpty
        $conn = { param($sig) [pscustomobject]@{ ServerName = 'fs02'; ShareName = 'daten'; Dialect = '3.0'; Signed = $sig; Encrypted = $false } }
        $rows = @(ConvertTo-WorkerPerfSmbConnectionRows @((& $conn $true), (& $conn $null)))
        $rows.Count | Should -Be 1; $rows[0].Signed | Should -BeNullOrEmpty; $rows[0].Connections | Should -Be 2
        @(ConvertTo-WorkerPerfSmbConnectionRows @((& $conn $true), (& $conn $null), (& $conn $false)))[0].Signed | Should -BeFalse
        $late = @{ Area = 'network'; State = $null; Clock = [System.Diagnostics.Stopwatch]::StartNew(); BudgetMs = 0; Shared = @{}; Values = [ordered]@{} }
        { ConvertTo-WorkerPerfSmbConnectionRows @((& $conn $true)) $late } | Should -Throw -ExceptionType ([System.TimeoutException])
        # Leser: die Richtlinie der Zeitquelle geht vor, ein Registrierungswert vom falschen Typ ist nicht lesbar, ohne AppLocker eine leere Liste
        $script:WinFake.Registry['SOFTWARE\Policies\Microsoft\W32Time\Parameters'] = [ordered]@{ Type = 'NT5DS' }
        $script:WinFake.Registry['SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'].AUOptions = '4'
        foreach ($k in @($script:WinFake.Registry.Keys)) { if ($k -like 'SOFTWARE\Policies\Microsoft\Windows\SrpV2*') { $script:WinFake.Registry.Remove($k) } }
        $h = Read-Health
        (Get-V $h 'network.timeType').Value | Should -Be 'NT5DS'
        (Get-V $h 'network.timeServers').State | Should -Be 'absent'                                   # Fix-Runde 1, Punkt 4: die Server stammen aus dem Schluessel der Art, nicht aus dem des Dienstes
        (Get-V $h 'maintenance.updateOptions').State | Should -Be 'unreadable'; (Get-V $h 'maintenance.updateOptions').Reason | Should -Be 'error'; (Get-V $h 'maintenance.updateHour').Value | Should -Be 10
        (Get-V $h 'security.applockerCollections').State | Should -Be 'read'; @((Get-V $h 'security.applockerCollections').Value).Count | Should -Be 0
    }
    It 'waehlt aus einer Aufgabe die Ausloeser, die kuerzeste Wiederholung und das erste Programm' {   # Fix-Runde 1, Punkt 3
        $trigger = { param([int]$Type, $Interval) [pscustomobject]@{ Type = $Type; Repetition = [pscustomobject]@{ Interval = $Interval } } }
        $exec = { param($Path) [pscustomobject]@{ Type = 0; Path = $Path } }
        $handler = [pscustomobject]@{ Type = 5; ClassId = '{00000000-0000-0000-0000-0000000000c1}' }             # ohne Path: wird nicht gelesen
        $task = { param($Triggers, $Actions) [pscustomobject]@{ Path = '\Sim\Wartung'; Enabled = $true; State = 3; NextRunTime = [datetime]'2026-11-14T10:00:00'
                LastRunTime = [datetime]'1899-12-30'; Definition = [pscustomobject]@{ Triggers = @($Triggers); Actions = @($Actions) } } }
        $triggers = @((& $trigger 2 'PT30M'), (& $trigger 9 ''), (& $trigger 1 'PT10M'), (& $trigger 8 'P1D'), (& $trigger 2 'PT5S'))
        $actions = @($handler, (& $exec ''), (& $exec 'C:\Tools\wartung.exe'), (& $exec 'C:\Tools\zweites.exe'))
        $t = ConvertFrom-WorkerPerfComTask (& $task $triggers $actions)
        @($t.TriggerTypes) | Should -Be @(2, 9, 1, 8, 2); $t.RepeatMinutes | Should -Be 0.1                     # die kuerzeste positive Wiederholung aller Ausloeser
        $t.Action | Should -Be 'C:\Tools\wartung.exe'                                                          # das erste Programm, das einen Befehl nennt
        $t.Path | Should -Be '\Sim\Wartung'; $t.Enabled | Should -BeTrue; $t.State | Should -Be 3; $t.NextRun | Should -Be ([datetime]'2026-11-14T10:00:00')
        $t = ConvertFrom-WorkerPerfComTask (& $task @((& $trigger 9 $null), [pscustomobject]@{ Type = 6; Repetition = $null }) @($handler))
        @($t.TriggerTypes) | Should -Be @(9, 6); $t.RepeatMinutes | Should -Be 0; $t.Action | Should -Be ''
        $t = ConvertFrom-WorkerPerfComTask (& $task @() @((& $exec 'C:\Tools\ohne.exe')))
        @($t.TriggerTypes).Count | Should -Be 0; $t.RepeatMinutes | Should -Be 0; $t.Action | Should -Be 'C:\Tools\ohne.exe'
    }
    It 'zaehlt die Aufgaben aller Ordner und listet nur die ausserhalb von \Microsoft' {   # Fix-Runde 1, Punkt 3
        Test-WorkerPerfMicrosoftTaskFolder '\Microsoft' | Should -BeTrue; Test-WorkerPerfMicrosoftTaskFolder '\Microsoft\Windows\x' | Should -BeTrue
        Test-WorkerPerfMicrosoftTaskFolder '\microsoft\Windows' | Should -BeTrue
        Test-WorkerPerfMicrosoftTaskFolder '\MicrosoftEdgeUpdate' | Should -BeFalse; Test-WorkerPerfMicrosoftTaskFolder '\' | Should -BeFalse
        Test-WorkerPerfMicrosoftTaskFolder '\Sim\Microsoft' | Should -BeFalse
        $task = { param([string]$Path) [pscustomobject]@{ Path = $Path; Enabled = $true; State = 3; NextRunTime = [datetime]'1899-12-30'; LastRunTime = [datetime]'1899-12-30'
                Definition = [pscustomobject]@{ Triggers = @(); Actions = @() } } }
        $folder = { param([string]$Path, [object[]]$Tasks, [object[]]$Subs)
            [pscustomobject]@{ Path = $Path; Tasks = $Tasks; Subs = $Subs } | Add-Member -PassThru ScriptMethod GetTasks { param($Flags) $this.Tasks } |
                Add-Member -PassThru ScriptMethod GetFolders { param($Flags) $this.Subs } }
        $x = & $folder '\Microsoft\Windows\x' @((& $task '\Microsoft\Windows\x\Sim1'), (& $task '\Microsoft\Windows\x\Sim2')) @()
        $ms = & $folder '\Microsoft' @((& $task '\Microsoft\SimOben')) @((& $folder '\Microsoft\Windows' @() @($x)))
        $edge = & $folder '\MicrosoftEdgeUpdate' @((& $task '\MicrosoftEdgeUpdate\SimUpdate')) @()
        $root = & $folder '\' @((& $task '\SimWurzel')) @($ms, $edge, (& $folder '\Leer' @() @()))
        $walk = Get-WorkerPerfTaskWalk $root
        $walk.Count | Should -Be 5; @($walk.Tasks | ForEach-Object { $_.Path } | Sort-Object) | Should -Be @('\MicrosoftEdgeUpdate\SimUpdate', '\SimWurzel')
        { Get-WorkerPerfTaskWalk $root 0.000001 } | Should -Throw -ExceptionType ([System.TimeoutException])
    }
    It 'zaehlt und listet eine Aufgabe, die sich nicht lesen laesst' {   # Fix-Runde 1, Punkt 2
        $broken = New-Object WinStandInTask '\Sim\Kaputt', 'Definition'                                       # der Getter der Definition wirft (beschaedigtes Abbild) ...
        { [WinStandInTask].GetProperty('Definition').GetValue($broken) } | Should -Throw                      # ... PowerShell liefert dafuer $null
        $empty = New-Object WinStandInTask '\Sim\OhneDefinition', ''                                         # die Definition ist $null
        $plain = { param([string]$Path, $Definition) [pscustomobject]@{ Path = $Path; Enabled = $true; State = 3; NextRunTime = [datetime]'1899-12-30'
                LastRunTime = [datetime]'1899-12-30'; Definition = $Definition } }
        $failing = & $plain '\Sim\Ausloeser' ([pscustomobject]@{ Triggers = (New-Object WinStandInBrokenList); Actions = @([pscustomobject]@{ Type = 0; Path = 'C:\Tools\a.exe' }) })
        $state = [pscustomobject]@{ Path = '\Sim\OhneZustand'; Definition = $null }                         # liest sich ausserhalb der Definition nicht (Zugriff wirft)
        $good = & $plain '\Sim\Gut' ([pscustomobject]@{ Triggers = @([pscustomobject]@{ Type = 9; Repetition = $null }); Actions = @() })
        $root = [pscustomobject]@{ Path = '\'; Tasks = @($broken, $empty, $failing, $state, $good) } | Add-Member -PassThru ScriptMethod GetTasks { param($Flags) $this.Tasks } |
            Add-Member -PassThru ScriptMethod GetFolders { param($Flags) }
        $walk = Get-WorkerPerfTaskWalk $root
        $walk.Count | Should -Be 5; @($walk.Tasks | ForEach-Object { $_.Path }) | Should -Be @('\Sim\Kaputt', '\Sim\OhneDefinition', '\Sim\Ausloeser', '\Sim\OhneZustand', '\Sim\Gut')
        foreach ($t in @($walk.Tasks)[0..2]) {
            $t.Enabled | Should -BeTrue -Because $t.Path; $t.State | Should -Be 3 -Because $t.Path                    # was sich lesen liess, bleibt
            @($t.TriggerTypes).Count | Should -Be 0 -Because $t.Path; $t.RepeatMinutes | Should -Be 0 -Because $t.Path; $t.Action | Should -Be '' -Because $t.Path }
        $t = @($walk.Tasks)[3]; $t.Enabled | Should -BeNullOrEmpty; $t.State | Should -BeNullOrEmpty; $t.Action | Should -Be ''; @($t.TriggerTypes).Count | Should -Be 0
        @(@($walk.Tasks)[4].TriggerTypes) | Should -Be @(9)
        # im Bericht: die Aufgabe steht mit ihrem Pfad, die nicht lesbaren Felder leer
        $script:WinFake.Tasks = $walk; $h = Read-Health; $v = Get-V $h 'maintenance.tasks'; $v.State | Should -Be 'read'; (Get-V $h 'maintenance.taskCount').Value | Should -Be 5
        $row = $v.Value | Where-Object Path -eq '\Sim\OhneZustand'
        $row.Enabled | Should -BeNullOrEmpty; $row.State | Should -Be ''; $row.NextRun | Should -Be 0; $row.LastRun | Should -Be 0; $row.Triggers | Should -Be ''; $row.RepeatMinutes | Should -Be 0; $row.Action | Should -Be ''
        ($v.Value | Where-Object Path -eq '\Sim\Kaputt').State | Should -Be 'Ready'
    }
    It 'nimmt die Zeitquellen aus dem Schluessel, aus dem die Art stammt' {   # Fix-Runde 1, Punkt 4
        $script:WinFake.Registry['SOFTWARE\Policies\Microsoft\W32Time\Parameters'] = [ordered]@{ Type = 'NTP'; NtpServer = 'zeit09.klinik.example,0x9' }
        $h = Read-Health; (Get-V $h 'network.timeType').Value | Should -Be 'NTP'; (Get-V $h 'network.timeServers').Value | Should -Be 'zeit09.klinik.example'
        $script:WinFake.Registry['SOFTWARE\Policies\Microsoft\W32Time\Parameters'] = [ordered]@{ NtpServer = 'zeit09.klinik.example,0x9' }   # die Richtlinie setzt nur die Server
        $h = Read-Health; (Get-V $h 'network.timeType').Value | Should -Be 'NTP'; (Get-V $h 'network.timeServers').Value | Should -Be 'zeit01.klinik.example 10.1.0.20'
    }
    It 'nennt die Ausschluesse nicht vorhanden, wenn Defender keine Einstellungen liefert' {   # Fix-Runde 1, Punkt 5
        $script:WinFake.Cim['MSFT_MpPreference'] = @()
        $h = Read-Health
        foreach ($id in 'security.defenderExclusionPaths', 'security.defenderExclusionProcesses', 'security.defenderExclusionExtensions', 'maintenance.scanDay') {
            (Get-V $h $id).State | Should -Be 'absent' -Because $id; (Get-V $h $id).Reason | Should -Be '' -Because $id }
    }
    It 'liest die DNS-Server beider Adressfamilien je Schnittstelle' {   # Fix-Runde 1, Punkt 6 (ZB-R26)
        $dns = { param([int]$Index, [int]$Family, [string[]]$Servers) [pscustomobject]@{ InterfaceAlias = 'Ethernet0'; InterfaceIndex = [uint32]$Index; AddressFamily = [uint16]$Family; ServerAddresses = $Servers } }
        $rows = { param($H) @((Get-V $H 'network.dnsServers').Value | ForEach-Object { '{0} {1}' -f $_.Interface, $_.Address }) }
        # Vorgabe: IPv4 an Schnittstelle 4; die Platzhalter fec0:0:0:ffff::1 bis ::3 (ohne eingetragenen IPv6-Server) und eine Schnittstelle ohne Server fehlen
        $h = Read-Health; & $rows $h | Should -Be @('4 10.1.0.10'); $script:WinFake.Calls.Keys | Should -Not -Contain 'cim:Win32_NetworkAdapterConfiguration'
        ($h | ConvertTo-Json -Depth 12) | Should -Not -Match 'Ethernet0'
        $script:WinFake.Cim['MSFT_DNSClientServerAddress'] = @((& $dns 6 23 @('fd00:10::53', 'FD00:10::53', 'fd00:10::54')), (& $dns 6 2 @()))     # nur IPv6
        & $rows (Read-Health) | Should -Be @('6 fd00:10::53', '6 fd00:10::54')
        $script:WinFake.Cim['MSFT_DNSClientServerAddress'] = @((& $dns 4 2 @('10.1.0.10', '10.1.0.11', '10.1.0.10')), (& $dns 4 23 @('fd00:10::53', 'fec0:0:0:ffff::1')),
            (& $dns 7 2 @('10.1.0.10')))                                                                    # beide Familien; derselbe Server an einer anderen Schnittstelle bleibt
        & $rows (Read-Health) | Should -Be @('4 10.1.0.10', '4 10.1.0.11', '4 fd00:10::53', '7 10.1.0.10')
        $script:WinFake.Cim['MSFT_DNSClientServerAddress'] = @((& $dns 4 2 @()), (& $dns 5 23 $null))       # Schnittstellen ohne Server
        $v = Get-V (Read-Health) 'network.dnsServers'; $v.State | Should -Be 'read'; @($v.Value).Count | Should -Be 0
        foreach ($missing in @((New-WinStandInMissingClass), (New-WinStandInMissingNamespace))) {           # ohne die Klasse: die Klasse des Plans (nur IPv4)
            Reset-WinStandIns; $script:WinFake.CimFail['MSFT_DNSClientServerAddress'] = $missing
            & $rows (Read-Health) | Should -Be @('4 10.1.0.10') -Because $missing.Message; $script:WinFake.Calls['cim:Win32_NetworkAdapterConfiguration'] | Should -Be 1
        }
        Reset-WinStandIns; $script:WinFake.CimFail['MSFT_DNSClientServerAddress'] = New-WinStandInDenied 'cim'
        $v = Get-V (Read-Health) 'network.dnsServers'; $v.State | Should -Be 'unreadable'; $v.Reason | Should -Be 'rights'; $script:WinFake.Calls.Keys | Should -Not -Contain 'cim:Win32_NetworkAdapterConfiguration'
        Test-WorkerPerfDnsPlaceholder 'fec0:0:0:ffff::3' | Should -BeTrue; Test-WorkerPerfDnsPlaceholder 'FEC0:0:0:FFFF:0:0:0:1' | Should -BeTrue
Test-WorkerPerfDnsPlaceholder 'FEC0::FFFF:0:0:2' | Should -BeFalse; Test-WorkerPerfDnsPlaceholder 'fec0:0:0:ffff::4' | Should -BeFalse
        Test-WorkerPerfDnsPlaceholder '10.1.0.10' | Should -BeFalse; Test-WorkerPerfDnsPlaceholder 'kein Server' | Should -BeFalse
    }
    It 'enthaelt keinen Aufruf, der etwas aendert, startet oder einen anderen Rechner anspricht' {
        $src = Get-Content (Join-Path $PSScriptRoot '../src/WorkerPerf.Sources.Windows.ps1') -Raw
        foreach ($bad in 'Microsoft\.Update\.', 'w32tm', 'powercfg', 'fltmc', 'Win32_Product\b', 'Get-MpPreference', 'Get-MpComputerStatus', 'Get-SmbConnection', 'Get-ScheduledTask',
            'Get-AppLockerPolicy', 'Get-Printer\b', 'Get-AppxPackage', 'Get-NetAdapterRss', 'Get-ScheduledTaskInfo', 'VMwareToolboxCmd', 'cscript', 'HKEY_USERS', 'HKCU', 'Start-Process', 'Start-Service', 'Invoke-CimMethod', '-ComputerName', 'New-CimSession') { $src | Should -Not -Match $bad -Because $bad }
        # nichts wird geschrieben, geloescht, angehalten oder ausgefuehrt (Entwurf 3.4)
        foreach ($bad in 'CreateSubKey', 'SetValue', 'DeleteValue', 'DeleteSubKey', 'OpenSubKey\([^)]*\$true', 'Set-ItemProperty', 'New-ItemProperty', 'Remove-ItemProperty', 'Remove-Item\b',
            'Stop-Service', 'Set-Service', 'Stop-Process', '\.Run\(') { $src | Should -Not -Match $bad -Because $bad }
    }
}
