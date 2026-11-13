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
