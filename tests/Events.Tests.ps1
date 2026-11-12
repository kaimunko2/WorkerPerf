BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.EventConfig.ps1')
    $script:Cfg = Read-WorkerPerfEventConfig (Join-Path $PSScriptRoot '../src/events.json')
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Events.ps1')
    $script:Set = Read-WorkerPerfEventSettings (Join-Path $PSScriptRoot '../src/thresholds.json'); $script:T0 = 1700000000000
    function New-Ev([double]$Min, [string]$Kind = 'crash', [string]$App = 'EXCEL.EXE', [int]$Sid = 3, [string]$User = 'user002', [string]$Module = 'vbe7.dll', [hashtable]$More = @{}) {
        $e = @{ TimeMs = [long]($T0 + $Min * 60000); Log = 'application'; Source = 'Application Error'; EventId = 1000; Level = 2; Group = 'app'; Kind = $Kind
            App = $App; AppVersion = '16.0'; Module = $Module; ModuleVersion = ''; Code = '0xc0000005'; Pid = 812; SessionId = $Sid; SessionIndex = $Sid; User = $User
            Printer = ''; Driver = ''; Service = ''; Object = ''; Text = '' }
        foreach ($k in $More.Keys) { $e[$k] = $More[$k] }; $e
    }
    function Get-Inc { param([object[]]$Events, [switch]$Before) , @(New-WorkerPerfEventIncidents -Events $Events -Config $Cfg -Settings $Set -Drivers @(
        @{ Name = 'Sim PCL 6'; Manufacturer = 'HP'; Files = @('hpsimgr.dll') }) -FirstId 9 -Before:$Before) }
    function New-Xml([string]$Provider, [int]$Id, [string]$Data, [string]$User = '') {
        "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><System><Provider Name='$Provider'/><EventID>$Id</EventID><Level>2</Level></System>$Data$User</Event>"
    }
    # Muster: Schwellen, Rollen, Treiber, ein Modell mit einem Takt je Minute ab T0 und die Muster je Vorfall
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Findings.ps1')
    $script:Th = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json'); $script:Roles = Read-WorkerPerfRoles (Join-Path $PSScriptRoot '../src/roles.json')
    $script:Drv = @(@{ Name = 'Sim PCL 6'; Manufacturer = 'HP'; Files = @('hpsimgr.dll') })
    $script:Texts = Read-WorkerPerfTexts (Join-Path $PSScriptRoot '../src/texts.de.json')
    function New-PatternModel([double[]]$MemUsed) { @{ Tick = @{ TimeMs = [long[]]@(0..($MemUsed.Count - 1) | ForEach-Object { $T0 + $_ * 60000 }); Signal = @{ 'mem.used' = $MemUsed; 'mem.commit' = [double[]]@($MemUsed | ForEach-Object { 50.0 }) } } } }
    function Get-Pat([object[]]$Events, $Model = (New-PatternModel (@(50) * 60)), [object[]]$Perf = @(), [switch]$Before) {
        $inc = Get-Inc $Events -Before:$Before
        Add-WorkerPerfEventPatterns -Incidents $inc -AllEvents $Events -Model $Model -Thresholds $Th -Settings $Set -Config $Cfg -Roles $Roles -Drivers $Drv -PerfIncidents $Perf -Before:$Before
        , @($inc | ForEach-Object { , @($_.Patterns | ForEach-Object { $_.Id }) })
    }
    function Get-PatInc([object[]]$Events, $Model = (New-PatternModel (@(50) * 60)), [object[]]$Perf = @()) {
        $inc = Get-Inc $Events
        Add-WorkerPerfEventPatterns -Incidents $inc -AllEvents $Events -Model $Model -Thresholds $Th -Settings $Set -Config $Cfg -Roles $Roles -Drivers $Drv -PerfIncidents $Perf
        , $inc
    }
    function Get-Text($Incident, [int]$Offset = 0) { Get-WorkerPerfEventIncidentText -Incident $Incident -Model $null -Texts $Texts -Config $Cfg -OffsetMinutes $Offset }
}
Describe 'events.json' {
    It 'fuehrt jede Kennung zu Gruppe und Art' {
        foreach ($e in $Cfg.Entries) { foreach ($id in $e.ids) {
            # an entry with levels takes only an event of one of them (P1-R36)
            $lv = $(if (@($e.levels).Count -gt 0) { @($e.levels)[0] } else { $null })
            $r = Resolve-WorkerPerfEventEntry $Cfg $e.log $e.provider $id $lv
            $r.group | Should -Be $e.group; $r.kind | Should -Be $e.kind } }
        (Resolve-WorkerPerfEventEntry $Cfg 'application' 'application error' 1000).kind | Should -Be 'crash'
        Resolve-WorkerPerfEventEntry $Cfg 'application' 'Application Error' 1001 | Should -BeNullOrEmpty
        (Resolve-WorkerPerfEventEntry $Cfg 'defender' 'Microsoft-Windows-Windows Defender' 1002).kind | Should -Be 'scan-end'
        $Cfg.Logs['session'].Lookback | Should -BeFalse; $Cfg.ErrorCodes['0xc0000005'] | Should -Be 'Zugriffsverletzung'
    }
    It 'liest die Listen und die Namen der Protokolle' {
        @($Cfg.Logs['applocker'].Names).Count | Should -Be 2
        @($Cfg.ImportantServices) | Should -Contain 'Spooler'
        @($Cfg.PrintServices) | Should -Be @('Spooler', 'cpsvc')                       # Aussage geaendert (M1)
        @($Cfg.PrintProcesses) | Should -Contain 'spoolsv.exe'
        @($Cfg.SystemModules) | Should -Contain 'ntdll.dll'
        $Cfg.ErrorCodes['AppHangB1'] | Should -Not -BeNullOrEmpty
    }
    It 'nennt Eintrag und Feld eines Fehlers' -TestCases @(
        @{ Json = '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"P","ids":[1],"group":"app","kind":"absturz"}]}'; Msg = "*Eintrag 1 (P 1)*Feld 'kind'*" }
        @{ Json = '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"b","provider":"P","ids":[1],"group":"app","kind":"crash"}]}'; Msg = "*Eintrag 1 (P 1)*Feld 'log'*" }
        @{ Json = '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"P","ids":[1],"group":"app","kind":"crash","fields":{"modul":"M"}}]}'; Msg = "*Eintrag 1 (P 1)*Feld 'fields.modul'*" }
        @{ Json = '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"P","ids":[1.5],"group":"app","kind":"crash"}]}'; Msg = "*Eintrag 1 (P 1.5)*Feld 'ids'*" }
        @{ Json = '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"P","ids":[1],"group":"xyz","kind":"crash"}]}'; Msg = "*Eintrag 1 (P 1)*Feld 'group'*" }
        @{ Json = '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"P","ids":[],"group":"app","kind":"crash"}]}'; Msg = "*Eintrag 1 (P )*Feld 'ids'*" }
        @{ Json = '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"P","ids":[1],"group":"app","kind":"crash"},{"log":"a","provider":"p","ids":[2,1],"group":"app","kind":"crash"}]}'; Msg = "*Eintrag 2 (p 2, 1)*Feld 'ids'*doppelte*" }
        @{ Json = '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"P","ids":[1],"group":"app","kind":"crash","fields":{"pid":{"field":"X","format":"octal"}}}]}'; Msg = "*Eintrag 1 (P 1)*Feld 'fields.pid.format'*" }
        @{ Json = '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"P","ids":[1],"group":"app","kind":"crash","fields":{"app":{"field":"X","format":"hex"}}}]}'; Msg = "*Eintrag 1 (P 1)*Feld 'fields.app.format'*" }
        @{ Json = '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"P","ids":[1],"group":"app","kind":"crash","fields":{"pid":{"format":"hex"}}}]}'; Msg = "*Eintrag 1 (P 1)*Feld 'fields.pid.field'*" }
        @{ Json = '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"P","ids":[1],"group":"app","kind":"crash","fields":{"app":"#x"}}]}'; Msg = "*Eintrag 1 (P 1)*Feld 'fields.app'*" }
    ) {
        $f = Join-Path $TestDrive 'e.json'; [IO.File]::WriteAllText($f, $Json)
        { Read-WorkerPerfEventConfig $f } | Should -Throw $Msg
    }
    It 'liest eine einzelne Kennung und fehlende fields' {
        $f = Join-Path $TestDrive 'ok.json'
        [IO.File]::WriteAllText($f, '{"logs":[{"id":"a","names":["A"],"lookback":false}],"events":[{"log":"a","provider":"P","ids":7,"group":"app","kind":"info"}]}')
        $c = Read-WorkerPerfEventConfig $f
        (Resolve-WorkerPerfEventEntry $c 'a' 'P' 7).kind | Should -Be 'info'
        @($c.ImportantServices).Count | Should -Be 0; $c.ErrorCodes.Count | Should -Be 0
    }
}
Describe 'Rohereignis -> Datensatz' {
    It 'liest die strukturierten Felder aus den Datenfeldern, nicht aus dem Meldungstext' {
        $x = New-Xml 'Application Error' 1000 "<EventData><Data Name='AppName'>EXCEL.EXE</Data><Data Name='AppVersion'>16.0.1</Data><Data Name='ModuleName'>vbe7.dll</Data><Data Name='ModuleVersion'>7.1</Data><Data Name='ExceptionCode'>c0000005</Data><Data Name='ProcessId'>0x1f2c</Data></EventData>"
        $p = ConvertFrom-WorkerPerfEventXml $x
        $r = ConvertTo-WorkerPerfEventRecord (Resolve-WorkerPerfEventEntry $Cfg 'application' $p.Provider $p.EventId) $p ([datetime]'2026-01-15 08:00') "Name der fehlerhaften Anwendung: WORD.EXE`r`nweiter"
        $r.App | Should -Be 'EXCEL.EXE'; $r.Module | Should -Be 'vbe7.dll'; $r.Code | Should -Be '0xc0000005'; $r.Pid | Should -Be 7980   # 0x1f2c
        $r.Group | Should -Be 'app'; $r.Kind | Should -Be 'crash'; $r.Level | Should -Be 2; $r.Text | Should -Be 'Name der fehlerhaften Anwendung: WORD.EXE'
        $r.Source | Should -Be 'Application Error'; $r.Log | Should -Be 'application'; $r.Time | Should -Be ([datetime]'2026-01-15 08:00')
    }
    It 'liest die Prozess-ID nach dem Zahlenformat des Eintrags' -TestCases @(
        @{ Fmt = 'hex'; Val = '1234'; Want = 4660 }
        @{ Fmt = 'hex'; Val = '0x1f2c'; Want = 7980 }
        @{ Fmt = 'hex'; Val = '1f2c'; Want = 7980 }
        @{ Fmt = $null; Val = '8012'; Want = 8012 }
        @{ Fmt = $null; Val = '0x1f2c'; Want = 7980 }
        @{ Fmt = $null; Val = '1f2c'; Want = $null }
        @{ Fmt = 'hex'; Val = 'abc!'; Want = $null }
        @{ Fmt = 'hex'; Val = 'zz'; Want = $null }
    ) {
        $ref = $(if ($Fmt) { '{"field":"P","format":"' + $Fmt + '"}' } else { '"P"' })
        $f = Join-Path $TestDrive 'fmt.json'
        [IO.File]::WriteAllText($f, '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"X","ids":[1],"group":"app","kind":"crash","fields":{"pid":' + $ref + '}}]}')
        $c = Read-WorkerPerfEventConfig $f
        $p = ConvertFrom-WorkerPerfEventXml (New-Xml 'X' 1 "<EventData><Data Name='P'>$Val</Data></EventData>")
        $r = ConvertTo-WorkerPerfEventRecord (Resolve-WorkerPerfEventEntry $c 'a' 'X' 1) $p ([datetime]::Now) ''
        if ($null -eq $Want) { $r.Pid | Should -BeNullOrEmpty } else { $r.Pid | Should -Be $Want }
    }
    It 'verlangt hex fuer die Prozess-ID von Absturz und Haenger' {
        foreach ($id in 1000, 1002) {
            $e = Resolve-WorkerPerfEventEntry $Cfg 'application' $(if ($id -eq 1000) { 'Application Error' } else { 'Application Hang' }) $id
            $e.fields['pid'].Format | Should -Be 'hex'
        }
    }
    It 'liest unbenannte Felder nach Position und Benutzer aus UserData' {
        $h = ConvertFrom-WorkerPerfEventXml (New-Xml 'Application Hang' 1002 '<EventData><Data>WINWORD.EXE</Data><Data>16.0</Data><Data>1a2c</Data></EventData>')
        $hr = ConvertTo-WorkerPerfEventRecord (Resolve-WorkerPerfEventEntry $Cfg 'application' $h.Provider 1002) $h ([datetime]::Now) ''
        $hr.App | Should -Be 'WINWORD.EXE'; $hr.AppVersion | Should -Be '16.0'; $hr.Pid | Should -Be 6700   # 1a2c hex
        $s = ConvertFrom-WorkerPerfEventXml (New-Xml 'Microsoft-Windows-TerminalServices-LocalSessionManager' 21 '' "<UserData><EventXML xmlns='x'><User>KLINIK\mueller</User><SessionID>3</SessionID></EventXML></UserData>")
        $r = ConvertTo-WorkerPerfEventRecord (Resolve-WorkerPerfEventEntry $Cfg 'session' $s.Provider 21) $s ([datetime]::Now) ''
        $r.User | Should -Be 'mueller'; $r.SessionId | Should -Be 3; $r.Kind | Should -Be 'logon'
    }
    It 'liest den Dienstnamen aus dem Binaerteil als UTF-16' {
        $hex = (([Text.Encoding]::Unicode.GetBytes("Spooler`0")) | ForEach-Object { $_.ToString('X2') }) -join ''
        $p = ConvertFrom-WorkerPerfEventXml (New-Xml 'Service Control Manager' 7034 "<EventData><Data Name='param1'>Anzeigename</Data><Binary>$hex</Binary></EventData>")
        $r = ConvertTo-WorkerPerfEventRecord (Resolve-WorkerPerfEventEntry $Cfg 'system' $p.Provider 7034) $p ([datetime]::Now) ''
        $r.Service | Should -Be 'Spooler'; $r.Kind | Should -Be 'service'
    }
    It 'schreibt ein Ereignis mit fehlenden Feldern mit leeren Werten' {
        $p = ConvertFrom-WorkerPerfEventXml (New-Xml 'Application Error' 1000 '<EventData><Data>nur ein Wert</Data></EventData>')
        $r = ConvertTo-WorkerPerfEventRecord (Resolve-WorkerPerfEventEntry $Cfg 'application' $p.Provider 1000) $p ([datetime]::Now) $null
        # Aussage geaendert (Task 10, P1-R26): das einzige unbenannte Feld ist die Anwendung (#0), die uebrigen fehlen
        $r.App | Should -Be 'nur ein Wert'; $r.Module | Should -Be ''; $r.Code | Should -Be ''; $r.ProcessStart | Should -BeNullOrEmpty; $r.Pid | Should -BeNullOrEmpty; $r.Kind | Should -Be 'crash'; $r.Text | Should -Be ''
        $r.Printer | Should -Be ''; $r.Object | Should -Be ''; $r.SessionId | Should -BeNullOrEmpty
    }
    It 'vereinheitlicht Fehlercodes und kuerzt Texte auf 300 Zeichen' {
        Format-WorkerPerfErrorCode 'C0000005' | Should -Be '0xc0000005'; Format-WorkerPerfErrorCode '3221225477' | Should -Be '0xc0000005'
        Format-WorkerPerfErrorCode '0xC0000005' | Should -Be '0xc0000005'
        Format-WorkerPerfErrorCode 'AppHangB1' | Should -Be 'AppHangB1'
        (Get-WorkerPerfEventText ('x' * 400)).Length | Should -Be 300
    }
}

Describe 'Inhalt von events.json' {
    It 'legt Gruppe, Art und Felder jedes Eintrags fest: <Log> <Provider> <Id>' -TestCases @(
        # Aussage geaendert (Task 10, P1-R26): benannte Felder zuerst, die klassischen Positionen dahinter; dazu die Startzeit des Prozesses
        @{ Log = 'application'; Provider = 'Application Error'; Id = 1000; Group = 'app'; Kind = 'crash'; Fields = 'app=AppName|#0;appVersion=AppVersion|#1;module=ModuleName|#3;moduleVersion=ModuleVersion|#4;code=ExceptionCode|#6;pid=ProcessId|#8/hex;processStart=ProcessCreationTime|#9' }
        @{ Log = 'application'; Provider = 'Application Hang'; Id = 1002; Group = 'app'; Kind = 'hang'; Fields = 'app=#0;appVersion=#1;pid=#2/hex;processStart=#3' }
        @{ Log = 'application'; Provider = '.NET Runtime'; Id = 1026; Group = 'app'; Kind = 'app-detail'; Fields = '' }
        @{ Log = 'application'; Provider = 'Windows Error Reporting'; Id = 1001; Group = 'app'; Kind = 'app-detail'; Fields = '' }
        @{ Log = 'session'; Provider = 'Microsoft-Windows-TerminalServices-LocalSessionManager'; Id = 21; Group = 'session'; Kind = 'logon'; Fields = 'user=User;session=SessionID' }
        @{ Log = 'session'; Provider = 'Microsoft-Windows-TerminalServices-LocalSessionManager'; Id = 23; Group = 'session'; Kind = 'logoff'; Fields = 'user=User;session=SessionID' }
        @{ Log = 'session'; Provider = 'Microsoft-Windows-TerminalServices-LocalSessionManager'; Id = 24; Group = 'session'; Kind = 'disconnect'; Fields = 'user=User;session=SessionID' }
        @{ Log = 'session'; Provider = 'Microsoft-Windows-TerminalServices-LocalSessionManager'; Id = 25; Group = 'session'; Kind = 'reconnect'; Fields = 'user=User;session=SessionID' }
        @{ Log = 'system'; Provider = 'Service Control Manager'; Id = 7023; Group = 'service'; Kind = 'service'; Fields = 'service=binary:utf16' }
        @{ Log = 'system'; Provider = 'Service Control Manager'; Id = 7031; Group = 'service'; Kind = 'service'; Fields = 'service=binary:utf16' }
        @{ Log = 'system'; Provider = 'Service Control Manager'; Id = 7034; Group = 'service'; Kind = 'service'; Fields = 'service=binary:utf16' }
        @{ Log = 'system'; Provider = 'disk'; Id = 7; Group = 'storage'; Kind = 'system'; Fields = 'object=#0' }
        @{ Log = 'system'; Provider = 'disk'; Id = 11; Group = 'storage'; Kind = 'system'; Fields = 'object=#0' }
        @{ Log = 'system'; Provider = 'disk'; Id = 51; Group = 'storage'; Kind = 'system'; Fields = 'object=#0' }
        @{ Log = 'system'; Provider = 'disk'; Id = 153; Group = 'storage'; Kind = 'system'; Fields = 'object=#0' }
        @{ Log = 'system'; Provider = 'Ntfs'; Id = 55; Group = 'storage'; Kind = 'system'; Fields = 'object=#0' }
        @{ Log = 'system'; Provider = 'Ntfs'; Id = 98; Group = 'storage'; Kind = 'system'; Fields = 'object=#0' }
        @{ Log = 'system'; Provider = 'Ntfs'; Id = 137; Group = 'storage'; Kind = 'system'; Fields = 'object=#0' }
        @{ Log = 'system'; Provider = 'Ntfs'; Id = 140; Group = 'storage'; Kind = 'system'; Fields = 'object=#0' }
        @{ Log = 'system'; Provider = 'Microsoft-Windows-Resource-Exhaustion-Detector'; Id = 2004; Group = 'memory'; Kind = 'system'; Fields = '' }
        @{ Log = 'printservice'; Provider = 'Microsoft-Windows-PrintService'; Id = 372; Group = 'print'; Kind = 'print'; Fields = '' }
        @{ Log = 'printservice'; Provider = 'Microsoft-Windows-PrintService'; Id = 808; Group = 'print'; Kind = 'print'; Fields = '' }
        @{ Log = 'printservice'; Provider = 'Microsoft-Windows-PrintService'; Id = 6161; Group = 'print'; Kind = 'print'; Fields = '' }
        # P1-R30: 600/601 sind ein Dauerzustand (Treiberimport), kein Vorfall
        @{ Log = 'printservice'; Provider = 'Microsoft-Windows-PrintService'; Id = 600; Group = 'print'; Kind = 'driver-import'; Fields = 'driver=Driver' }
        @{ Log = 'printservice'; Provider = 'Microsoft-Windows-PrintService'; Id = 601; Group = 'print'; Kind = 'driver-import'; Fields = 'driver=Driver' }
        @{ Log = 'printservice'; Provider = 'Microsoft-Windows-PrintService'; Id = 215; Group = 'print'; Kind = 'print'; Fields = 'driver=DriverName' }
        # P1-R33: 30800 (Name nicht aufloesbar) ist kein Vorfall
        @{ Log = 'smbclient'; Provider = 'Microsoft-Windows-SMBClient'; Id = 30800; Group = 'fileserver'; Kind = 'name-resolution'; Fields = 'object=ServerName' }
        @{ Log = 'smbclient'; Provider = 'Microsoft-Windows-SMBClient'; Id = 30803; Group = 'fileserver'; Kind = 'system'; Fields = 'object=ServerName' }
        @{ Log = 'smbclient'; Provider = 'Microsoft-Windows-SMBClient'; Id = 30807; Group = 'fileserver'; Kind = 'system'; Fields = 'object=ServerName' }
        @{ Log = 'application'; Provider = 'Microsoft-Windows-User Profiles Service'; Id = 1533; Group = 'profile'; Kind = 'profileerror'; Fields = '' }
        @{ Log = 'defender'; Provider = 'Microsoft-Windows-Windows Defender'; Id = 1000; Group = 'security'; Kind = 'scan-start'; Fields = '' }
        @{ Log = 'defender'; Provider = 'Microsoft-Windows-Windows Defender'; Id = 1001; Group = 'security'; Kind = 'scan-end'; Fields = '' }
        @{ Log = 'defender'; Provider = 'Microsoft-Windows-Windows Defender'; Id = 1002; Group = 'security'; Kind = 'scan-end'; Fields = '' }
        @{ Log = 'defender'; Provider = 'Microsoft-Windows-Windows Defender'; Id = 2000; Group = 'security'; Kind = 'signature-update'; Fields = '' }
        @{ Log = 'applocker'; Provider = 'Microsoft-Windows-AppLocker'; Id = 8004; Group = 'security'; Kind = 'applocker-block'; Fields = '' }
        @{ Log = 'applocker'; Provider = 'Microsoft-Windows-AppLocker'; Id = 8007; Group = 'security'; Kind = 'applocker-block'; Fields = '' }
    ) {
        # level 2 (error): every entry takes it (P1-R36 limits some entries to critical, error and warning)
        $e = Resolve-WorkerPerfEventEntry $Cfg $Log $Provider $Id 2
        $e | Should -Not -BeNullOrEmpty
        $e.group | Should -Be $Group; $e.kind | Should -Be $Kind
        $actual = @($e.fields.Keys | Sort-Object | ForEach-Object {
                $f = $e.fields[$_]; "$_=$(@($f.Field) -join '|')" + $(if ($f.Format -eq 'hex') { '/hex' } else { '' }) }) -join ';'
        $expected = (@($Fields -split ';' | Where-Object { $_ } | Sort-Object) -join ';')
        $actual | Should -Be $expected
    }
    It 'hat genau die erwarteten Kennungen je Quelle' {
        $count = 0; foreach ($e in $Cfg.Entries) { $count += @($e.ids).Count }
        $count | Should -Be 44                                                   # Aussage geaendert (Task 10, P1-R27): 600, 601, 215, 30800, 7023; M10: ohne die 6 Kennungen des Betriebsprotokolls
        (Resolve-WorkerPerfEventEntry $Cfg 'printservice' 'Microsoft-Windows-PrintService' 823) | Should -BeNullOrEmpty
        (Resolve-WorkerPerfEventEntry $Cfg 'printservice' 'Microsoft-Windows-PrintService' 318) | Should -BeNullOrEmpty
        (Resolve-WorkerPerfEventEntry $Cfg 'printservice' 'Microsoft-Windows-PrintService' 365) | Should -BeNullOrEmpty
        @($Cfg.Entries | Where-Object { $_.allIds }).provider | Should -Be @('Citrix Profile Management', 'Citrix Profile Management')   # P1-R36: Fehler und Warnungen
        @((Resolve-WorkerPerfEventEntry $Cfg 'system' 'disk' 7 2), (Resolve-WorkerPerfEventEntry $Cfg 'system' 'disk' 153 2)) | ForEach-Object { $_.ids -join ',' } | Select-Object -Unique | Should -Be '7,11,51,153'
        (Resolve-WorkerPerfEventEntry $Cfg 'smbclient' 'Microsoft-Windows-SMBClient' 30805 2).ids -join ',' | Should -Be '30803,30804,30805,30806,30807'   # P1-R33
        (Resolve-WorkerPerfEventEntry $Cfg 'smbclient' 'Microsoft-Windows-SMBClient' 30800 2).ids -join ',' | Should -Be '30800'
        (Resolve-WorkerPerfEventEntry $Cfg 'applocker' 'Microsoft-Windows-AppLocker' 8004).ids -join ',' | Should -Be '8004,8007'
    }
    It 'findet nichts bei unbekannter Quelle oder falschem Protokoll' {
        Resolve-WorkerPerfEventEntry $Cfg 'application' 'Unbekannte Quelle' 1000 | Should -BeNullOrEmpty
        Resolve-WorkerPerfEventEntry $Cfg 'system' 'Application Error' 1000 | Should -BeNullOrEmpty
        Resolve-WorkerPerfEventEntry $Cfg 'nolog' 'Application Error' 1000 | Should -BeNullOrEmpty
    }
    It 'vereinheitlicht die Schluessel der Fehlercodetabelle' {
        $Cfg.ErrorCodes['0xC0000005'] | Should -Be 'Zugriffsverletzung'
        $Cfg.ErrorCodes[(Format-WorkerPerfErrorCode 'C0000005')] | Should -Be 'Zugriffsverletzung'
        $Cfg.ErrorCodes[(Format-WorkerPerfErrorCode '3221225477')] | Should -Be 'Zugriffsverletzung'
        $Cfg.ErrorCodes.ContainsKey('0xe0434352') | Should -BeTrue
        $Cfg.ErrorCodes.Count | Should -Be 10
    }
    It 'liest Zahlenformat der Sitzung, Drucker und Treiber aus eigenen Eintraegen' {
        $f = Join-Path $TestDrive 'pd.json'
        [IO.File]::WriteAllText($f, '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"X","ids":[1],"group":"print","kind":"print","fields":{"printer":"PrinterName","driver":"#1","session":{"field":"S","format":"hex"},"user":"U"}}]}')
        $c = Read-WorkerPerfEventConfig $f
        $p = ConvertFrom-WorkerPerfEventXml (New-Xml 'X' 1 "<EventData><Data Name='PrinterName'>Drucker A</Data><Data Name='Other'>Treiber B</Data><Data Name='S'>1f</Data><Data Name='U'>dom\\anna</Data></EventData>")
        $r = ConvertTo-WorkerPerfEventRecord (Resolve-WorkerPerfEventEntry $c 'a' 'X' 1) $p ([datetime]::Now) ''
        $r.Printer | Should -Be 'Drucker A'; $r.Driver | Should -Be 'Treiber B'; $r.SessionId | Should -Be 31; $r.User | Should -Be 'anna'
        $r.Group | Should -Be 'print'
    }
    It 'liest die Sitzungsnummer der Sitzungsereignisse dezimal' {
        $s = ConvertFrom-WorkerPerfEventXml (New-Xml 'Microsoft-Windows-TerminalServices-LocalSessionManager' 24 '' "<UserData><EventXML xmlns='x'><User>a\b</User><SessionID>12</SessionID></EventXML></UserData>")
        (ConvertTo-WorkerPerfEventRecord (Resolve-WorkerPerfEventEntry $Cfg 'session' $s.Provider 24) $s ([datetime]::Now) '').SessionId | Should -Be 12
    }
    It 'findet benannte Felder ohne Ruecksicht auf die Schreibweise' {
        $p = ConvertFrom-WorkerPerfEventXml (New-Xml 'Application Error' 1000 "<EventData><Data Name='appname'>kleinschrift.exe</Data></EventData>")
        $p.Named.ContainsKey('APPNAME') | Should -BeTrue
        (ConvertTo-WorkerPerfEventRecord (Resolve-WorkerPerfEventEntry $Cfg 'application' $p.Provider 1000) $p ([datetime]::Now) '').App | Should -Be 'kleinschrift.exe'
    }
    It 'schneidet den Dienstnamen vor dem ersten NUL ab' {
        $hex = (([Text.Encoding]::Unicode.GetBytes("Spooler`0Rest`0")) | ForEach-Object { $_.ToString('X2') }) -join ''
        (ConvertFrom-WorkerPerfHexUtf16 $hex).Length | Should -Be 7
        (ConvertFrom-WorkerPerfHexUtf16 $hex) | Should -BeExactly 'Spooler'
    }
    It 'schreibt ein vorhandenes, leeres Datenfeld als leeren Wert' {
        $p = ConvertFrom-WorkerPerfEventXml (New-Xml 'Application Error' 1000 "<EventData><Data Name='AppName'></Data><Data Name='ProcessId'/></EventData>")
        $r = ConvertTo-WorkerPerfEventRecord (Resolve-WorkerPerfEventEntry $Cfg 'application' $p.Provider 1000) $p ([datetime]::Now) ''
        $r.App | Should -Be ''; $r.Pid | Should -BeNullOrEmpty
    }
}
Describe 'Alternativen, Ebenen und Konto der Ereignisse (Task 10)' {
    BeforeAll {
        function New-Cfg([string]$Events) {
            $f = Join-Path $TestDrive ('cfg' + [guid]::NewGuid().ToString('n') + '.json')
            [IO.File]::WriteAllText($f, '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[' + $Events + ']}'); $f
        }
        # Application Error 1000 in der klassischen Form mit unbenannten Datenfeldern (Werte erfunden)
        $script:Unnamed = '<EventData><Data>EXCEL.EXE</Data><Data>16.0.1</Data><Data>65a1b2c3</Data><Data>vbe7.dll</Data><Data>7.1.10</Data><Data>5f00aa11</Data>' +
            '<Data>c0000005</Data><Data>000e1f2c</Data><Data>1f1c</Data><Data>01dad0e2a1b2c3d4</Data><Data>C:\Programme\x.exe</Data><Data>C:\Programme\vbe7.dll</Data>' +
            '<Data>00000000-0000-0000-0000-000000000001</Data><Data></Data><Data></Data></EventData>'
    }
    It 'liest Absturzdaten aus unbenannten Feldern nach Position' {
        $p = ConvertFrom-WorkerPerfEventXml (New-Xml 'Application Error' 1000 $Unnamed)
        $r = ConvertTo-WorkerPerfEventRecord (Resolve-WorkerPerfEventEntry $Cfg 'application' $p.Provider 1000) $p ([datetime]::Now) ''
        $r.App | Should -Be 'EXCEL.EXE'; $r.AppVersion | Should -Be '16.0.1'; $r.Module | Should -Be 'vbe7.dll'; $r.ModuleVersion | Should -Be '7.1.10'
        $r.Code | Should -Be '0xc0000005'; $r.Pid | Should -Be 7964                                       # 1f1c hex
        $r.ProcessStart | Should -Be ([datetime]::FromFileTimeUtc(0x01dad0e2a1b2c3d4)); $r.ProcessStart.Kind | Should -Be 'Utc'
    }
    It 'nimmt die erste Alternative, die einen Wert liefert' {
        $c = Read-WorkerPerfEventConfig (New-Cfg '{"log":"a","provider":"X","ids":[1],"group":"app","kind":"crash","fields":{"app":["AppName","#0"],"pid":{"field":["ProcessId","#2"],"format":"hex"}}}')
        $e = Resolve-WorkerPerfEventEntry $c 'a' 'X' 1
        $e.fields['app'].Field | Should -Be @('AppName', '#0')
        $named = ConvertFrom-WorkerPerfEventXml (New-Xml 'X' 1 "<EventData><Data Name='Other'>falsch.exe</Data><Data Name='AppName'>WORD.EXE</Data><Data Name='ProcessId'>0x10</Data></EventData>")
        $r = ConvertTo-WorkerPerfEventRecord $e $named ([datetime]::Now) ''
        $r.App | Should -Be 'WORD.EXE'; $r.Pid | Should -Be 16
        $empty = ConvertFrom-WorkerPerfEventXml (New-Xml 'X' 1 "<EventData><Data Name='Other'>PUNKT.EXE</Data><Data Name='AppName'> </Data><Data Name='Rest'>1a</Data></EventData>")
        $r = ConvertTo-WorkerPerfEventRecord $e $empty ([datetime]::Now) ''
        $r.App | Should -Be 'PUNKT.EXE'; $r.Pid | Should -Be 26                                         # leeres AppName: #0; ProcessId fehlt: #2
        (ConvertTo-WorkerPerfEventRecord $e (ConvertFrom-WorkerPerfEventXml (New-Xml 'X' 1 '')) ([datetime]::Now) '').App | Should -Be ''
    }
    It 'weist ungueltige Listen von Feldverweisen ab' -TestCases @(
        @{ Fields = '{"app":[]}'; Msg = "*Eintrag 1 (X 1)*Feld 'fields.app'*Liste*" }
        @{ Fields = '{"app":["AppName",5]}'; Msg = "*Eintrag 1 (X 1)*Feld 'fields.app'*" }
        @{ Fields = '{"app":["AppName","#x"]}'; Msg = "*Eintrag 1 (X 1)*Feld 'fields.app'*Position*" }
        @{ Fields = '{"pid":{"field":[],"format":"hex"}}'; Msg = "*Eintrag 1 (X 1)*Feld 'fields.pid.field'*" }
        @{ Fields = '{"processStart":{"field":"#9","format":"hex"}}'; Msg = "*Eintrag 1 (X 1)*Feld 'fields.processStart.format'*" }
    ) {
        { Read-WorkerPerfEventConfig (New-Cfg ('{"log":"a","provider":"X","ids":[1],"group":"app","kind":"crash","fields":' + $Fields + '}')) } | Should -Throw $Msg
    }
    It 'liest die Startzeit des Prozesses als FILETIME und laesst Unlesbares leer' {
        ConvertFrom-WorkerPerfEventFileTime '0x01dad0e2a1b2c3d4' | Should -Be ([datetime]::FromFileTimeUtc(0x01dad0e2a1b2c3d4))
        ConvertFrom-WorkerPerfEventFileTime '01dad0e2a1b2c3d4' | Should -Be ([datetime]::FromFileTimeUtc(0x01dad0e2a1b2c3d4))
        foreach ($bad in '', '0', 'xyz', '0xffffffffffffffff', '2026-01-15') { ConvertFrom-WorkerPerfEventFileTime $bad | Should -BeNullOrEmpty -Because $bad }
    }
    It 'nimmt mit "ids": "*" jede Kennung der Quelle auf den genannten Ebenen' {
        $c = Read-WorkerPerfEventConfig (New-Cfg ('{"log":"a","provider":"Sim Profil","ids":"*","levels":["error","warning"],"group":"profile","kind":"profileerror"},' +
                '{"log":"a","provider":"Sim Profil","ids":[7],"group":"app","kind":"app-detail"}'))
        (Resolve-WorkerPerfEventEntry $c 'a' 'sim profil' 1234 2).kind | Should -Be 'profileerror'
        (Resolve-WorkerPerfEventEntry $c 'a' 'Sim Profil' 5 3).kind | Should -Be 'profileerror'
        Resolve-WorkerPerfEventEntry $c 'a' 'Sim Profil' 5 4 | Should -BeNullOrEmpty                 # Information
        Resolve-WorkerPerfEventEntry $c 'a' 'Sim Profil' 5 | Should -BeNullOrEmpty                   # Ebene unbekannt
        (Resolve-WorkerPerfEventEntry $c 'a' 'Sim Profil' 7 4).kind | Should -Be 'app-detail'          # die genannte Kennung geht vor
        Resolve-WorkerPerfEventEntry $c 'a' 'Andere Quelle' 5 2 | Should -BeNullOrEmpty
        $e = @($c.Entries)[0]; $e.allIds | Should -BeTrue; @($e.ids).Count | Should -Be 0; $e.levels | Should -Be @(2, 3)
    }
    It 'laesst ein Ereignis, dessen Ebene der Eintrag mit Kennung nicht nimmt, dem Eintrag mit "*" (M2)' {
        $c = Read-WorkerPerfEventConfig (New-Cfg ('{"log":"a","provider":"Sim Profil","ids":[7],"levels":["information"],"group":"app","kind":"info"},' +
                '{"log":"a","provider":"Sim Profil","ids":"*","levels":["error","warning"],"group":"profile","kind":"profileerror"}'))
        (Resolve-WorkerPerfEventEntry $c 'a' 'Sim Profil' 7 4).kind | Should -Be 'info'
        (Resolve-WorkerPerfEventEntry $c 'a' 'Sim Profil' 7 3).kind | Should -Be 'profileerror'
        Resolve-WorkerPerfEventEntry $c 'a' 'Sim Profil' 7 1 | Should -BeNullOrEmpty
    }
    It 'prueft die Ebene auch bei einem Eintrag mit Kennungen' {
        $c = Read-WorkerPerfEventConfig (New-Cfg '{"log":"a","provider":"X","ids":[1],"levels":["critical","information"],"group":"app","kind":"info"}')
        (Resolve-WorkerPerfEventEntry $c 'a' 'X' 1 1).kind | Should -Be 'info'
        (Resolve-WorkerPerfEventEntry $c 'a' 'X' 1 0).kind | Should -Be 'info'; (Resolve-WorkerPerfEventEntry $c 'a' 'X' 1 4).kind | Should -Be 'info'
        Resolve-WorkerPerfEventEntry $c 'a' 'X' 1 2 | Should -BeNullOrEmpty
    }
    It 'weist "*" ohne Ebenen, unbekannte Ebenen und doppelte Eintraege ab' -TestCases @(
        @{ Events = '{"log":"a","provider":"X","ids":"*","group":"profile","kind":"profileerror"}'; Msg = "*Eintrag 1 (X `*)*Feld 'ids'*levels*" }
        @{ Events = '{"log":"a","provider":"X","ids":"*","levels":[],"group":"profile","kind":"profileerror"}'; Msg = "*Eintrag 1 (X `*)*Feld 'ids'*levels*" }
        @{ Events = '{"log":"a","provider":"X","ids":"*","levels":["Error"],"group":"profile","kind":"profileerror"}'; Msg = "*Eintrag 1 (X `*)*Feld 'levels'*Error*" }
        @{ Events = '{"log":"a","provider":"X","ids":"*","levels":["fatal"],"group":"profile","kind":"profileerror"}'; Msg = "*Eintrag 1 (X `*)*Feld 'levels'*fatal*" }
        # Aussage geaendert (P1-R36): zwei Eintraege "*" derselben Quelle sind erlaubt, solange sich ihre Ebenen nicht ueberschneiden
        @{ Events = '{"log":"a","provider":"X","ids":"*","levels":["error"],"group":"profile","kind":"profileerror"},{"log":"a","provider":"x","ids":"*","levels":["warning","error"],"group":"profile","kind":"profile-warning"}'; Msg = "*Eintrag 2 (x `*)*Feld 'ids'*doppelt*" }
        @{ Events = '{"log":"a","provider":"X","ids":"7","group":"app","kind":"crash"},{"log":"a","provider":"X","ids":[7],"group":"app","kind":"crash"}'; Msg = "*Eintrag 2 (X 7)*doppelte Kennung 7*" }
        @{ Events = '{"log":"a","provider":"X","ids":"alle","group":"app","kind":"crash"}'; Msg = "*Eintrag 1 (X alle)*Feld 'ids'*keine ganze Zahl*" }
        @{ Events = '{"log":"a","provider":"X","ids":"*","levels":["error",3],"group":"profile","kind":"profileerror"}'; Msg = "*Eintrag 1 (X `*)*Feld 'levels'*kein Text*" }   # M3
        @{ Events = '{"log":"a","provider":"Sim O''Brien","ids":[1],"group":"app","kind":"crash"}'; Msg = "*Eintrag 1 (Sim O'Brien 1)*Feld 'provider'*kein '*" }
    ) {
        { Read-WorkerPerfEventConfig (New-Cfg $Events) } | Should -Throw $Msg
    }
    It 'liest die Profilverwaltung von Citrix nach Ebene' {
        (Resolve-WorkerPerfEventEntry $Cfg 'application' 'Citrix Profile Management' 1003 2).group | Should -Be 'profile'
        (Resolve-WorkerPerfEventEntry $Cfg 'application' 'Citrix Profile Management' 1003 2).kind | Should -Be 'profileerror'
        (Resolve-WorkerPerfEventEntry $Cfg 'application' 'Citrix Profile Management' 5 1).kind | Should -Be 'profileerror'
        # Aussage geaendert (P1-R36): eine Warnung wird nur aufgezeichnet, unter einer Art ohne Vorfall
        (Resolve-WorkerPerfEventEntry $Cfg 'application' 'Citrix Profile Management' 5 3).kind | Should -Be 'profile-warning'
        (Resolve-WorkerPerfEventEntry $Cfg 'application' 'Citrix Profile Management' 5 3).group | Should -Be 'profile'
        Resolve-WorkerPerfEventEntry $Cfg 'application' 'Citrix Profile Management' 5 4 | Should -BeNullOrEmpty
        # M7: erfundene Quellen, die der Katalog nicht kennt
        Resolve-WorkerPerfEventEntry $Cfg 'application' 'Sim Sitzungsdienst' 1002 2 | Should -BeNullOrEmpty
        Resolve-WorkerPerfEventEntry $Cfg 'application' 'Sim Messdienst' 1 2 | Should -BeNullOrEmpty
    }
    It 'nimmt Speicher-, Speichermangel- und Dateiserver-Ereignisse nur ab der Ebene Warnung (P1-R36)' {
        foreach ($k in @(@('system', 'Ntfs', 98), @('system', 'disk', 153), @('system', 'Microsoft-Windows-Resource-Exhaustion-Detector', 2004),
                @('smbclient', 'Microsoft-Windows-SMBClient', 30806), @('smbclient', 'Microsoft-Windows-SMBClient', 30800))) {
            foreach ($lv in 1, 2, 3) { Resolve-WorkerPerfEventEntry $Cfg $k[0] $k[1] $k[2] $lv | Should -Not -BeNullOrEmpty -Because "$($k[1]) $($k[2]) Ebene $lv" }
            foreach ($lv in 0, 4, 5) { Resolve-WorkerPerfEventEntry $Cfg $k[0] $k[1] $k[2] $lv | Should -BeNullOrEmpty -Because "$($k[1]) $($k[2]) Ebene $lv" }
        }
    }
    It 'zeichnet fehlgeschlagene Namensaufloesung und Warnungen der Profilverwaltung ohne Vorfall auf und nennt sie mit eigenem Wort (P1-R33, P1-R36)' {
        Get-WorkerPerfEventIncidentKind @{ Kind = 'name-resolution'; Group = 'fileserver'; App = ''; Service = '' } $Cfg | Should -BeNullOrEmpty
        Get-WorkerPerfEventIncidentKind @{ Kind = 'profile-warning'; Group = 'profile'; App = ''; Service = '' } $Cfg | Should -BeNullOrEmpty
        $html = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../src/report-template.html'))
        $html | Should -Match '"name-resolution": "Namensauflösung fehlgeschlagen"'
        $html | Should -Match '"profile-warning": "Warnung der Profilverwaltung"'
    }
    It 'macht fehlgeschlagene Namensaufloesung und Warnungen der Profilverwaltung nicht zu Begleitern (P1-R33, P1-R36)' {
        $nr = New-Ev 11 'name-resolution' '' -1 '' '' @{ Group = 'fileserver'; Source = 'Microsoft-Windows-SMBClient'; EventId = 30800; Object = '\altfs'; Code = ''; Module = '' }
        $pw = New-Ev 11.5 'profile-warning' '' -1 'user003' '' @{ Group = 'profile'; Source = 'Citrix Profile Management'; EventId = 2001; Code = ''; Module = '' }
        $i = Get-PatInc @((New-Ev 10), $nr, $pw)
        $i.Count | Should -Be 1; @($i[0].Patterns | ForEach-Object { $_.Id }) | Should -Not -Contain 'companion'
        $ab = New-Ev 11 'system' '' -1 '' '' @{ Group = 'fileserver'; Source = 'Microsoft-Windows-SMBClient'; EventId = 30803; Object = 'fs01'; Code = ''; Module = '' }
        $j = @((Get-PatInc @((New-Ev 10), $nr, $ab)) | Where-Object { $_.Kind -eq 'crash' })
        @($j[0].Companions | ForEach-Object { [int]$_.EventId }) | Should -Be @(30803)
    }
    It 'kennt den Druckverwaltungsdienst von Citrix unter seinem Kurznamen (M1)' {
        @($Cfg.ImportantServices) | Should -Contain 'cpsvc'; @($Cfg.ImportantServices) | Should -Contain 'CitrixPrintManagerService'
        @($Cfg.PrintServices) | Should -Contain 'cpsvc'
        Get-WorkerPerfEventIncidentKind @{ Kind = 'service'; Service = 'cpsvc'; App = '' } $Cfg | Should -Be 'print'
    }
    It 'nennt im Katalog die Fehlercodes, die selbst Speichermangel sagen' {
        @($Cfg.MemoryCodes) | Should -Be @('0xc0000017')
        { Read-WorkerPerfEventConfig (New-Cfg '{"log":"a","provider":"X","ids":[1],"group":"app","kind":"crash"}],"errorCodes":[{"code":"0x1","text":"t","memory":"ja"}') } | Should -Throw "*Feld 'memory'*"
    }
    It 'fuehrt fuer das Betriebsprotokoll des Profildienstes keinen Eintrag (M10)' {
        @($Cfg.Entries | Where-Object { $_.log -eq 'profileservice' }).Count | Should -Be 0
        $Cfg.Logs.Contains('profileservice') | Should -BeTrue
    }
    It 'trennt Konten unter jeder Kultur am Backslash' {
        $old = [cultureinfo]::CurrentCulture
        try {
            [cultureinfo]::CurrentCulture = [cultureinfo]'th-TH'
            ConvertTo-WorkerPerfEventAccountName 'KLINIK\user005' $Cfg | Should -Be 'user005'
            $x = "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><System><Provider Name='Microsoft-Windows-TerminalServices-LocalSessionManager'/><EventID>21</EventID><Level>4</Level></System>" +
                "<UserData><EventXML xmlns='Event_NS'><User>KLINIK\user005</User><SessionID>4</SessionID></EventXML></UserData></Event>"
            $entry = Resolve-WorkerPerfEventEntry $Cfg 'session' 'Microsoft-Windows-TerminalServices-LocalSessionManager' 21 4
            (ConvertTo-WorkerPerfEventRecord $entry (ConvertFrom-WorkerPerfEventXml $x) ([datetime]::Now) '').User | Should -Be 'user005'
        }
        finally { [cultureinfo]::CurrentCulture = $old }
    }
    It 'liest das Konto aus dem Systemteil' {
        $sys = "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><System><Provider Name='Microsoft-Windows-User Profiles Service'/><EventID>1511</EventID><Level>3</Level>" +
            "<Security UserID='S-1-5-21-1-2-3-1108'/></System></Event>"
        $p = ConvertFrom-WorkerPerfEventXml $sys
        $p.UserSid | Should -Be 'S-1-5-21-1-2-3-1108'
        (ConvertTo-WorkerPerfEventRecord (Resolve-WorkerPerfEventEntry $Cfg 'application' $p.Provider 1511) $p ([datetime]::Now) '').User | Should -Be ''
        (ConvertFrom-WorkerPerfEventXml (New-Xml 'Application Error' 1000 '')).UserSid | Should -Be ''
    }
    It 'nennt die Dienstkonten unabhaengig von der Sprache und nur mit Domaene, wenn sie keine Person ist' {
        Resolve-WorkerPerfWellKnownSid 'S-1-5-18' | Should -Be 'SYSTEM'; Resolve-WorkerPerfWellKnownSid 's-1-5-19' | Should -Be 'LOCAL SERVICE'
        Resolve-WorkerPerfWellKnownSid 'S-1-5-20' | Should -Be 'NETWORK SERVICE'; Resolve-WorkerPerfWellKnownSid 'S-1-5-21-1-2-3-500' | Should -Be ''
        Resolve-WorkerPerfWellKnownSid '' | Should -Be ''
        ConvertTo-WorkerPerfEventAccountName 'KLINIK\anna' $Cfg | Should -Be 'anna'
        ConvertTo-WorkerPerfEventAccountName 'NT SERVICE\SimDienst' $Cfg | Should -Be 'NT SERVICE\SimDienst'
        ConvertTo-WorkerPerfEventAccountName 'Window Manager\DWM-3' $Cfg | Should -Be 'Window Manager\DWM-3'
        ConvertTo-WorkerPerfEventAccountName 'SYSTEM' $Cfg | Should -Be 'SYSTEM'; ConvertTo-WorkerPerfEventAccountName '' $Cfg | Should -Be ''
        foreach ($a in 'SYSTEM', 'LOCAL SERVICE', 'NETWORK SERVICE', 'NT SERVICE\SimDienst', 'Window Manager\DWM-3', ('NT-AUTORIT' + [char]0xC4 + 'T\LOKALER DIENST')) {
            Test-WorkerPerfEventPersonUser (ConvertTo-WorkerPerfEventAccountName $a $Cfg) $Cfg | Should -BeFalse -Because $a
        }
        Test-WorkerPerfEventPersonUser (ConvertTo-WorkerPerfEventAccountName 'KLINIK\anna' $Cfg) $Cfg | Should -BeTrue
    }
}
Describe 'Fehlerfaelle' {
    It 'weist doppelte Kennungen im selben Eintrag ab' {
        $f = Join-Path $TestDrive 'd.json'
        [IO.File]::WriteAllText($f, '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"P","ids":[1,1],"group":"app","kind":"crash"}]}')
        { Read-WorkerPerfEventConfig $f } | Should -Throw "*Eintrag 1 (P 1, 1)*Feld 'ids'*doppelte*"
    }
    It 'meldet fehlende oder leere Kennungen' -TestCases @(
        @{ Ids = '' } ; @{ Ids = ',"ids":[]' }
    ) {
        $f = Join-Path $TestDrive 'i.json'
        [IO.File]::WriteAllText($f, '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"P","group":"app","kind":"crash"' + $Ids + '}]}')
        { Read-WorkerPerfEventConfig $f } | Should -Throw "*Eintrag 1 (P )*Feld 'ids' fehlt oder ist leer*"
    }
    It 'legt Fehlercodes unter dem vereinheitlichten Schluessel ab' {
        $f = Join-Path $TestDrive 'c2.json'
        [IO.File]::WriteAllText($f, '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"P","ids":[1],"group":"app","kind":"crash"}],"errorCodes":[{"code":"C0000005","text":"a"},{"code":"3221225477x","text":"b"}]}')
        $c = Read-WorkerPerfEventConfig $f
        $c.ErrorCodes.ContainsKey('0xc0000005') | Should -BeTrue; $c.ErrorCodes['0xc0000005'] | Should -Be 'a'; $c.ErrorCodes.ContainsKey('3221225477x') | Should -BeTrue
    }
    It 'weist Fehlercodes ab, die nach der Vereinheitlichung gleich sind' {
        $f = Join-Path $TestDrive 'c.json'
        [IO.File]::WriteAllText($f, '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"P","ids":[1],"group":"app","kind":"crash"}],"errorCodes":[{"code":"C0000005","text":"a"},{"code":"0xc0000005","text":"b"}]}')
        { Read-WorkerPerfEventConfig $f } | Should -Throw "*Fehlercode 2 (0xc0000005)*Feld 'code'*doppelt*"
    }
    It 'benennt fields und Feldverweise richtig, wenn der Typ nicht passt' -TestCases @(
        @{ Fields = '"x"'; Msg = "*Eintrag 1 (P 1)*Feld 'fields' muss ein Objekt sein*" }
        @{ Fields = '{"app":5}'; Msg = "*Eintrag 1 (P 1)*Feld 'fields.app'*Objekt*" }
    ) {
        $f = Join-Path $TestDrive 'ft.json'
        [IO.File]::WriteAllText($f, '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"P","ids":[1],"group":"app","kind":"crash","fields":' + $Fields + '}]}')
        { Read-WorkerPerfEventConfig $f } | Should -Throw $Msg
    }
    It 'gibt fuer ungueltiges XML und fremde Namensraeume $null zurueck' {
        ConvertFrom-WorkerPerfEventXml '<Event><nicht zu' | Should -BeNullOrEmpty
        ConvertFrom-WorkerPerfEventXml '' | Should -BeNullOrEmpty
        ConvertFrom-WorkerPerfEventXml '<Event><System><Provider Name="X"/><EventID>1</EventID></System></Event>' | Should -BeNullOrEmpty
    }
    It 'gibt fuer fehlenden Eintrag oder fehlendes Ereignis $null zurueck' {
        $p = ConvertFrom-WorkerPerfEventXml (New-Xml 'Application Error' 1000 '')
        ConvertTo-WorkerPerfEventRecord $null $p ([datetime]::Now) 'x' | Should -BeNullOrEmpty
        ConvertTo-WorkerPerfEventRecord (Resolve-WorkerPerfEventEntry $Cfg 'application' 'Application Error' 1000) $null ([datetime]::Now) 'x' | Should -BeNullOrEmpty
    }
}
Describe 'Ereignisvorfaelle' {
    It 'liest die Abstaende aus den Schwellen' { $Set.GroupMinutes | Should -Be 30; $Set.ResourceMinutes | Should -Be 5; $Set.ManyUsers | Should -Be 3 }
    It 'nimmt ohne Block Standardwerte und nennt ein falsches Feld' {                           # Review Focus 5
        $f = Join-Path $TestDrive 't.json'; [IO.File]::WriteAllText($f, '{"thresholds":[]}'); (Read-WorkerPerfEventSettings $f).GroupMinutes | Should -Be 30
        [IO.File]::WriteAllText($f, '{"thresholds":[],"events":{"eventGroupMinutes":"halb"}}'); { Read-WorkerPerfEventSettings $f } | Should -Throw "*'eventGroupMinutes'*"
    }
    It 'fasst bis 30 Minuten Abstand zusammen' {
        $i = Get-Inc @((New-Ev 0), (New-Ev 30), (New-Ev 61))
        $i.Count | Should -Be 2; $i[0].Count | Should -Be 2; $i[0].Id | Should -Be 9; $i[0].EndMs - $i[0].StartMs | Should -Be 1800000
    }
    It 'bildet den Schluessel je Art' {
        $i = Get-Inc @((New-Ev 0), (New-Ev 1 -App 'WINWORD.EXE'), (New-Ev 2 'service' '' 0 '' '' @{ Service = 'Spooler2'; Group = 'service' }), (New-Ev 3 'service' '' 0 '' '' @{ Service = 'spooler2'; Group = 'service' }),
            (New-Ev 4 'system' '' 0 '' '' @{ Group = 'storage'; Object = 'D:' }), (New-Ev 5 'system' '' 0 '' '' @{ Group = 'storage'; Object = 'E:' }))
        @($i | ForEach-Object { $_.Kind + ':' + $_.Key }) | Should -Be @('crash:EXCEL.EXE', 'crash:WINWORD.EXE', 'service:Spooler2', 'system:storage|D:', 'system:storage|E:')
    }
    It 'macht einen einzelnen Absturz in einer Sitzung zum Vorfall, einen Hintergrundprozess erst bei Wiederholung' {
        (Get-Inc @(New-Ev 0)).Count | Should -Be 1; (Get-Inc @(New-Ev 0))[0].InSession | Should -BeTrue; (Get-Inc @(New-Ev 0))[0].Severity | Should -Be 2
        (Get-Inc @(New-Ev 0 -Sid 0 -User 'SYSTEM')).Count | Should -Be 0
        $bg = Get-Inc @((New-Ev 0 -Sid 0 -User ''), (New-Ev 10 -Sid 0 -User '')); $bg.Count | Should -Be 1; $bg[0].InSession | Should -BeFalse; $bg[0].Severity | Should -Be 1
        (Get-Inc @(New-Ev 0 'service' '' 0 '' '' @{ Service = 'Spooler2'; Group = 'service' })).Count | Should -Be 0
        (Get-Inc @(New-Ev 0 'service' '' 0 '' '' @{ Service = 'BrokerAgent'; Group = 'service' })).Count | Should -Be 1
    }
    It 'zaehlt einen Absturz der Druckwarteschlange als Druckproblem mit dem Treiber als Schluessel' {
        $i = Get-Inc @(New-Ev 0 -App 'spoolsv.exe' -Sid 0 -User '' -Module 'hpsimgr.dll'); $i[0].Kind | Should -Be 'print'; $i[0].Key | Should -Be 'Sim PCL 6'
    }
    It 'nennt Anzahl, Benutzer, Versionen, Module und Fehlercodes' {
        $i = (Get-Inc @((New-Ev 0), (New-Ev 1 -Sid 4 -User 'user003'), (New-Ev 2 -Module 'mso.dll')))[0]
        $i.Users | Should -Be @('user002', 'user003'); $i.Sessions | Should -Be @(3, 4); $i.SameModule | Should -BeFalse
        $i.Modules[0].Name | Should -Be 'vbe7.dll'; $i.Modules[0].Count | Should -Be 2; $i.Codes[0].Text | Should -Be 'Zugriffsverletzung'; $i.Versions | Should -Be @('16.0')
    }
    It 'haelt einen Vorfall mit vielen Ereignissen klein' {                                    # Review Focus 2
        $i = Get-Inc @(1..500 | ForEach-Object { New-Ev ($_ / 100) -Sid 0 -User '' -App 'dienst.exe' })
        $i.Count | Should -Be 1; $i[0].Count | Should -Be 500; @($i[0].Events).Count | Should -Be 50
    }
}
Describe 'Ereignisvorfaelle im Einzelnen' {
    It 'behaelt die Standardwerte fuer fehlende Felder und weist Werte ab, die keine positive Zahl sind' {
        $f = Join-Path $TestDrive 's.json'
        [IO.File]::WriteAllText($f, '{"thresholds":[],"events":{"eventGroupMinutes":10,"manyUsers":null}}')
        $s = Read-WorkerPerfEventSettings $f
        $s.GroupMinutes | Should -Be 10; $s.ManyUsers | Should -Be 3; $s.OneUserEvents | Should -Be 3; $s.AfterhangMinutes | Should -Be 2; $s.CompanionMinutes | Should -Be 2
        foreach ($bad in '{"companionMinutes":0}', '{"resourceMinutes":-5}', '{"oneUserEvents":2.5}', '{"afterhangMinutes":true}') {
            $name = ($bad -split '"')[1]
            [IO.File]::WriteAllText($f, '{"thresholds":[],"events":' + $bad + '}'); { Read-WorkerPerfEventSettings $f } | Should -Throw "Schwellwert 'events': Feld '$name'*"
        }
        [IO.File]::WriteAllText($f, '{"thresholds":[],"events":[1]}'); { Read-WorkerPerfEventSettings $f } | Should -Throw "Schwellwert 'events'*Objekt*"
    }
    It 'laesst die Liste der Schwellen vom Block events unberuehrt' {
        $f = Join-Path $TestDrive 'l.json'; $j = Get-Content (Join-Path $PSScriptRoot '../src/thresholds.json') -Raw | ConvertFrom-Json
        (Get-Content (Join-Path $PSScriptRoot '../src/thresholds.json') -Raw) | Should -Match '"events"\s*:'
        $th = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json'); @($th.Keys).Count | Should -Be @($j.thresholds).Count
        $j.events.eventGroupMinutes | Should -Be 30; $j.events.resourceMinutes | Should -Be 5; $j.events.afterhangMinutes | Should -Be 2
        $j.events.companionMinutes | Should -Be 2; $j.events.manyUsers | Should -Be 3; $j.events.oneUserEvents | Should -Be 3
    }
    It 'ordnet die Art zu' {
        Get-WorkerPerfEventIncidentKind (New-Ev 0 'hang') $Cfg | Should -Be 'hang'
        Get-WorkerPerfEventIncidentKind (New-Ev 0 'hang' 'printisolationhost.exe') $Cfg | Should -Be 'print'
        Get-WorkerPerfEventIncidentKind (New-Ev 0 'crash' 'C:\Windows\System32\spoolsv.exe') $Cfg | Should -Be 'print'
        Get-WorkerPerfEventIncidentKind (New-Ev 0 'service' '' 0 '' '' @{ Service = 'spooler' }) $Cfg | Should -Be 'print'
        Get-WorkerPerfEventIncidentKind (New-Ev 0 'service' '' 0 '' '' @{ Service = 'BrokerAgent' }) $Cfg | Should -Be 'service'
        foreach ($k in 'print', 'profileerror', 'system') { Get-WorkerPerfEventIncidentKind (New-Ev 0 $k) $Cfg | Should -Be $k }
        foreach ($k in 'logon', 'app-detail', 'scan-start', 'applocker-block', 'info', '') { Get-WorkerPerfEventIncidentKind (New-Ev 0 $k) $Cfg | Should -BeNullOrEmpty }
    }
    It 'sucht den Schluessel eines Druckproblems in Treiber, Modul, Drucker und Quelle' {
        $p = @{ Group = 'print'; Source = 'Microsoft-Windows-PrintService' }
        (Get-Inc @(New-Ev 0 'print' '' 0 '' '' ($p + @{ Driver = 'Kyo KX'; Printer = 'PRN-1' })))[0].Key | Should -Be 'Kyo KX'
        $m = Get-Inc @(New-Ev 0 'crash' 'spoolsv.exe' 0 '' 'C:\Windows\System32\spool\drivers\x64\3\HPSIMGR.DLL')
        $m[0].Key | Should -Be 'Sim PCL 6'; $m[0].Driver | Should -Be 'Sim PCL 6'; $m[0].App | Should -Be 'spoolsv.exe'
        $r = (Get-Inc @(New-Ev 0 'print' '' 0 '' '' ($p + @{ Printer = 'PRN-1' })))[0]; $r.Key | Should -Be 'PRN-1'; $r.Printer | Should -Be 'PRN-1'; $r.Driver | Should -Be ''
        (Get-Inc @(New-Ev 0 'print' '' 0 '' 'fremd.dll' $p))[0].Key | Should -Be 'Microsoft-Windows-PrintService'
        $s = (Get-Inc @(New-Ev 0 'service' '' 0 '' '' @{ Service = 'Spooler'; Group = 'service'; Source = 'Service Control Manager' }))[0]
        $s.Kind | Should -Be 'print'; $s.Key | Should -Be 'Service Control Manager'; $s.Service | Should -Be 'Spooler'
    }
    It 'bildet Schluessel fuer Profil und Haenger und trennt die Arten' {
        $i = Get-Inc @((New-Ev 0 'profileerror' '' -1 'user014' '' @{ Group = 'profile'; Source = 'Microsoft-Windows-User Profiles Service' }), (New-Ev 1 'hang'), (New-Ev 2 'hang' -Sid 0 -User ''))
        @($i | ForEach-Object { $_.Kind + ':' + $_.Key + ':' + $_.Count }) | Should -Be @('profileerror:Microsoft-Windows-User Profiles Service:1', 'hang:EXCEL.EXE:2')
    }
    It 'nennt den Benutzer eines Ereignisses ohne Sitzung' {
        $i = (Get-Inc @(New-Ev 0 'profileerror' '' -1 'user014' '' @{ Group = 'profile'; SessionIndex = -1 }))[0]
        $i.Users | Should -Be @('user014'); @($i.Sessions).Count | Should -Be 0; $i.InSession | Should -BeTrue; $i.Severity | Should -Be 2
        $c = Get-Inc @(New-Ev 0 -Sid -1 -User 'user005' -More @{ SessionIndex = -1 }); $c.Count | Should -Be 1; $c[0].Users | Should -Be @('user005')
        (Get-Inc @(New-Ev 0 -Sid -1 -User 'network service' -More @{ SessionIndex = -1 })).Count | Should -Be 0
        (Get-Inc @(New-Ev 0 -Sid -1 -User 'LOCAL SERVICE' -More @{ SessionIndex = -1 })).Count | Should -Be 0
        $sys = (Get-Inc @((New-Ev 0 -Sid 0 -User 'SYSTEM'), (New-Ev 1 -Sid 0 -User 'SYSTEM')))[0]; @($sys.Users).Count | Should -Be 0; $sys.InSession | Should -BeFalse
    }
    It 'fuehrt Benutzer ohne Ruecksicht auf Schreibweise einmal und zaehlt Codes und Module' {
        $i = (Get-Inc @((New-Ev 0), (New-Ev 1 -User 'USER002' -More @{ Code = '0xdeadbeef'; AppVersion = '16.1' }), (New-Ev 2 -Module 'VBE7.DLL' -More @{ Code = '0xdeadbeef' })))[0]
        $i.Users | Should -Be @('user002'); $i.Sessions | Should -Be @(3); $i.Versions | Should -Be @('16.0', '16.1')
        $i.Modules.Count | Should -Be 1; $i.Modules[0].Count | Should -Be 3; $i.SameModule | Should -BeTrue
        $i.Codes[0].Code | Should -Be '0xdeadbeef'; $i.Codes[0].Count | Should -Be 2; $i.Codes[0].Text | Should -Be ''; $i.Codes[1].Text | Should -Be 'Zugriffsverletzung'
        foreach ($k in 'Group', 'App', 'Service', 'Driver', 'Printer', 'Source', 'Before', 'Patterns', 'Overlap', 'Companions') { $i.ContainsKey($k) | Should -BeTrue -Because $k }
        $i.App | Should -Be 'EXCEL.EXE'; $i.Group | Should -Be 'app'; $i.Source | Should -Be 'Application Error'; $i.Before | Should -BeFalse
        @($i.Patterns).Count + @($i.Overlap).Count + @($i.Companions).Count | Should -Be 0
    }
    It 'nummeriert nach Beginn, Art und Schluessel, gleich bei jedem Lauf und unabhaengig von der Eingabereihenfolge' {
        $ev = @((New-Ev 5 'system' '' 0 '' '' @{ Group = 'storage'; Object = 'D:' }), (New-Ev 5 -App 'b.exe'), (New-Ev 5 -App 'A.exe'), (New-Ev 1 -App 'z.exe'), (New-Ev 5 'hang' -App 'a.exe'))
        $show = { param($l) @($l | ForEach-Object { '{0}:{1}:{2}' -f $_.Id, $_.Kind, $_.Key }) }
        $a = & $show (Get-Inc $ev)
        $a | Should -Be @('9:crash:z.exe', '10:crash:A.exe', '11:crash:b.exe', '12:hang:a.exe', '13:system:storage|D:')
        & $show (Get-Inc @($ev[4], $ev[3], $ev[2], $ev[1], $ev[0])) | Should -Be $a
        $b = Get-Inc @($ev[0]) -Before; $b[0].Before | Should -BeTrue
        @(New-WorkerPerfEventIncidents -Events @() -Config $Cfg -Settings $Set -Drivers @() -FirstId 1).Count | Should -Be 0
    }
}
Describe 'Sitzung eines Ereignisses' {
    BeforeAll {
        # Schnappschuesse jede Minute ab T0; Sitzung 5 gehoert erst user001 (Minute 0..3), dann user002 (5..9)
        $script:Model = @{ Meta = @{ IntervalSeconds = 60 }; Snap = @{ N = 10; TimeMs = [long[]]@(0..9 | ForEach-Object { $T0 + $_ * 60000 }) }
            Sessions = @(
                @{ Index = 0; Sid = 0; User = ''; FirstP = 0; LastP = 9 }
                @{ Index = 1; Sid = 5; User = 'user001'; FirstP = 0; LastP = 3 }
                @{ Index = 2; Sid = 5; User = 'user002'; FirstP = 5; LastP = 9 }
                @{ Index = 3; Sid = 7; User = 'user003'; FirstP = 2; LastP = 9 }
                @{ Index = 4; Sid = 8; User = 'user004'; FirstP = -1; LastP = -1 }) }
        function Get-Ix([double]$Min, [int]$Sid, [string]$User = '') {
            $e = New-Ev $Min -Sid $Sid -User $User -More @{ SessionIndex = 99 }; Set-WorkerPerfEventSessions -Events @($e) -Model $Model -Config $Cfg; '{0}|{1}' -f $e.SessionIndex, $e.User
        }
        function Get-SessionUser([double]$Min, [int]$Sid, [string]$User = '') {
            $e = New-Ev $Min -Sid $Sid -User $User; Set-WorkerPerfEventSessions -Events @($e) -Model $Model -Config $Cfg; $e.SessionUser
        }
    }
    It 'nimmt die Sitzung mit gleicher Nummer, die zur Zeit des Ereignisses lebte' {
        Get-Ix 2 5 | Should -Be '1|user001'; Get-Ix 7 5 | Should -Be '2|user002'; Get-Ix 3.5 5 | Should -Be '1|user001'; Get-Ix 4.5 5 | Should -Be '2|user002'
        Get-Ix 9.5 7 'user003' | Should -Be '3|user003'; Get-Ix -0.5 5 | Should -Be '1|user001'
        Get-Ix 4 5 | Should -Be '-1|'                                     # genau beim Schnappschuss zwischen den beiden Sitzungen 5
    }
    It 'nimmt sonst die Sitzung desselben Benutzers, sonst keine' {
        Get-Ix 2 -1 'USER003' | Should -Be '3|USER003'; Get-Ix 7 9 'user002' | Should -Be '2|user002'
        Get-Ix 30 5 | Should -Be '-1|'; Get-Ix -1000 5 | Should -Be '-1|'; Get-Ix 1 -1 'SYSTEM' | Should -Be '-1|SYSTEM'; Get-Ix 1 0 | Should -Be '-1|'
        Get-Ix 1 8 | Should -Be '-1|'; Get-Ix 1 -1 'user004' | Should -Be '-1|user004'
    }
    It 'nimmt eine Sitzung desselben Benutzers nur, wenn sie zur Zeit des Ereignisses lebte' {
        Get-Ix 1 -1 'user002' | Should -Be '-1|user002'; Get-Ix 1 9 'user002' | Should -Be '-1|user002'
        Get-Ix -1000 5 'user002' | Should -Be '-1|user002'; Get-Ix -1000 -1 'user001' | Should -Be '-1|user001'
    }
    It 'gibt einem Ereignis der Sitzung 0 keine Sitzung, auch mit einem Benutzer' {
        Get-Ix 7 0 'user002' | Should -Be '-1|user002'; Get-Ix 7 0 'user003' | Should -Be '-1|user003'
    }
    It 'nimmt ueber ein Systemkonto keine Sitzung desselben Namens' {
        $Model.Sessions[3].User = 'SYSTEM'; try { Get-Ix 3 -1 'SYSTEM' | Should -Be '-1|SYSTEM' } finally { $Model.Sessions[3].User = 'user003' }
    }
    It 'laesst den Benutzer eines Ereignisses stehen und nennt den Besitzer der Sitzung' {
        Get-Ix 2 5 'other' | Should -Be '1|other'; Get-Ix 2 5 'DWM-5' | Should -Be '1|DWM-5'
        Get-SessionUser 2 5 'DWM-5' | Should -Be 'user001'; Get-SessionUser 30 5 'DWM-5' | Should -Be ''
    }
}
Describe 'Ereignisvorfaelle der simulierten Stunde' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Load.ps1')
        $run = Invoke-SimCapture (Join-Path $TestDrive 'out')
        $script:M = Import-WorkerPerfRun -Path $run -Thresholds (Read-WorkerPerfThresholds (Join-Path $run 'thresholds.json')) -Roles (Read-WorkerPerfRoles (Join-Path $PSScriptRoot '../src/roles.json'))
        $set = Read-WorkerPerfEventSettings (Join-Path $run 'thresholds.json')
        $build = {
            $ev = @($M.Events); $before = @($M.EventsBefore)
            Set-WorkerPerfEventSessions -Events $ev -Model $M -Config $Cfg; Set-WorkerPerfEventSessions -Events $before -Model $M -Config $Cfg
            $now = @(New-WorkerPerfEventIncidents -Events $ev -Config $Cfg -Settings $set -Drivers @($M.PrintDrivers) -FirstId 1)
            $now + @(New-WorkerPerfEventIncidents -Events $before -Config $Cfg -Settings $set -Drivers @($M.PrintDrivers) -FirstId ($now.Count + 1) -Before)
        }
        $script:SimInc = @(& $build); $script:SimInc2 = @(& $build)
        $script:SimExp = @(Get-Content (Join-Path $run 'expected.json') -Raw | ConvertFrom-Json | Where-Object Type -eq 'ereignis')
        # Muster der Messzeit gegen die Leistungsvorfaelle der Stunde
        $th = Read-WorkerPerfThresholds (Join-Path $run 'thresholds.json')
        $script:SimPerf = @(Join-WorkerPerfIncidents -Findings @(Get-WorkerPerfFindings -Series @(Get-WorkerPerfSeries $M $th) -Thresholds $th))
        $script:SimNow = @($SimInc | Where-Object { -not $_.Before })
        Add-WorkerPerfEventPatterns -Incidents $SimNow -AllEvents @($M.Events) -Model $M -Thresholds $th -Settings $set -Config $Cfg -Roles $Roles -Drivers @($M.PrintDrivers) -PerfIncidents $SimPerf
        $script:SimText = @($SimNow | ForEach-Object { Get-WorkerPerfEventIncidentText -Incident $_ -Model $M -Texts $Texts -Config $Cfg -OffsetMinutes ([int]$M.Meta.OffsetMinutes) })
    }
    It 'erkennt die Muster der Ereignisvorfaelle der Messzeit aus expected.json' {
        @($SimNow | ForEach-Object { $_.Kind + ':' + (@($_.Patterns | ForEach-Object { $_.Id }) -join ',') }) |
            Should -Be @($SimExp | Where-Object { -not $_.Before } | ForEach-Object { $_.Kind + ':' + (@($_.Patterns) -join ',') })
    }
    It 'verweist zwischen Absturz und Speicherengpass gegenseitig' {
        $crash = $SimNow[1]; $mem = @($SimPerf | Where-Object { $_.Lead -eq 'memory' })
        $mem.Count | Should -Be 1; $crash.Overlap | Should -Be @($mem[0].Id); $mem[0].EventIncidents | Should -Be @($crash.Id)
        foreach ($p in @($SimPerf | Where-Object { $_.Lead -ne 'memory' })) { @($p.EventIncidents).Count | Should -Be 0 -Because $p.Id }
    }
    It 'beschreibt jeden Vorfall der Messzeit in einem Satz' {
        $SimText.Count | Should -Be 4
        $SimText[1] | Should -Match 'Absturz von chrome\.exe \(1-mal\)\. Benutzer: user008\..* Wahrscheinlich Folge des Speichermangels\. Zeitgleich mit Vorfall \d+\.$'
        $SimText[0] | Should -Match 'Profilproblem .* Benutzer: user014\. Kein Muster erkannt\.$'
        $SimText[2] | Should -Match 'Absturz von OUTLOOK\.EXE \(3-mal\)\. Benutzer: user010, user011, user012\..* 3 Benutzer betroffen: spricht für Installation oder Update\.$'
        $SimText[3] | Should -Match 'Druckproblem – HP Universal Printing PCL 6 \(Sim\) .*gehört zum Druckertreiber HP Universal Printing PCL 6 \(Sim\)\.$'
    }
    It 'findet die Ereignisvorfaelle aus expected.json' {
        $show = { param($k, $app, $drv, $n, $u, $a, $b, $bf) '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}' -f $k, [string]$app, [string]$drv, $n, (@($u) -join '+'), $a, $b, $bf }
        @($SimInc | ForEach-Object { & $show $_.Kind $_.App $_.Driver $_.Count $_.Users $_.StartMs $_.EndMs $_.Before }) |
            Should -Be @($SimExp | ForEach-Object { & $show $_.Kind $_.App $_.Driver $_.Count $_.Users $_.StartMs $_.EndMs $_.Before })
        @($SimInc.Id) | Should -Be @(1..8)                                # C1: der Absturz ohne Sitzung im Rueckblick
    }
    It 'liefert bei zwei Laeufen dieselben Vorfaelle' {
        @($SimInc2 | ForEach-Object { '{0}:{1}:{2}:{3}' -f $_.Id, $_.Kind, $_.Key, $_.Count }) | Should -Be @($SimInc | ForEach-Object { '{0}:{1}:{2}:{3}' -f $_.Id, $_.Kind, $_.Key, $_.Count })
    }
    It 'gibt den Vorfaellen vor der Messung keine Sitzung der Messung' {
        # C1: Aussage geaendert, der vierte Vorfall ist der Absturz ohne Sitzung und Konto
        $b = @($SimInc | Where-Object { $_.Before }); $b.Count | Should -Be 4
        foreach ($i in $b) { @($i.Sessions).Count | Should -Be 0; @($i.Users).Count | Should -Be $(if ($i.App -eq 'simscan.exe') { 0 } else { 1 }) }
        @($b | Where-Object { $_.SessionUnknown }).App | Should -Be @('simscan.exe')
        foreach ($e in @($M.EventsBefore)) { $e.SessionIndex | Should -Be -1 }
    }
    It 'fasst den Rueckblick der simulierten Stunde mit Mustern, Datum und Haeufigkeit je Tag zusammen' {
        $lb = Get-WorkerPerfLookback -Model $M -Config $Cfg -Settings $set -Roles $Roles -FirstId 5 -ReportedMs $null
        $exp = @($SimExp | Where-Object { $_.Before })
        @($lb.Incidents | ForEach-Object { '{0}|{1}|{2}|{3}|{4}|{5}' -f $_.Kind, $_.App, (@($_.Patterns | ForEach-Object { $_.Id }) -join ','), $_.Count, $_.StartMs, $_.EndMs }) |
            Should -Be @($exp | ForEach-Object { '{0}|{1}|{2}|{3}|{4}|{5}' -f $_.Kind, $_.App, (@($_.Patterns) -join ','), $_.Count, $_.StartMs, $_.EndMs })
        # C1: Aussage geaendert, ein Vorfall, ein Ereignis und ein Tag mehr
        @($lb.Incidents.Id) | Should -Be @(5, 6, 7, 8); $lb.Days | Should -Be 7; $lb.EventCount | Should -Be 6
        ($lb.PerDay | Measure-Object Count -Sum).Sum | Should -Be 6; @($lb.PerDay).Count | Should -Be 3; @($lb.Near).Count | Should -Be 0
        $off = [int]$M.Meta.OffsetMinutes
        $at = { param($ms, $f) [DateTimeOffset]::FromUnixTimeMilliseconds($ms).UtcDateTime.AddMinutes($off).ToString($f, [cultureinfo]::InvariantCulture) }
        $text = @($lb.Incidents | ForEach-Object { Get-WorkerPerfEventIncidentText -Incident $_ -Model $M -Texts $Texts -Config $Cfg -OffsetMinutes $off })
        $text[0] | Should -BeExactly ((& $at $exp[0].StartMs 'dd.MM.yyyy HH:mm:ss') + ': Absturz von EXCEL.EXE (1-mal). Benutzer: user001. Fehlerhaftes Modul: simaddin.dll, immer dasselbe. Fehlercode: 0xc0000005 (Zugriffsverletzung). Ursache liegt wahrscheinlich im Modul simaddin.dll (betrifft EXCEL.EXE, WINWORD.EXE).')
        $text[1] | Should -Match ('^' + [regex]::Escape((& $at $exp[1].StartMs 'dd.MM.yyyy HH:mm:ss') + ': Absturz von WINWORD.EXE (1-mal). Benutzer: user002.'))
        $span = (& $at $exp[2].StartMs 'dd.MM.yyyy HH:mm:ss') + [char]0x2013 + $(if ((& $at $exp[2].StartMs 'yyyyMMdd') -eq (& $at $exp[2].EndMs 'yyyyMMdd')) { & $at $exp[2].EndMs 'HH:mm:ss' } else { & $at $exp[2].EndMs 'dd.MM.yyyy HH:mm:ss' })
        $text[2] | Should -BeExactly ($span + ': Absturz von nexus.exe (3-mal). Benutzer: user004. Fehlerhaftes Modul: nxreport.dll, immer dasselbe. Fehlercode: 0xc0000409 (Pufferüberlauf erkannt, Programm vom System beendet). Nur user004 betroffen, 3-mal: spricht für Profil oder Daten dieses Benutzers.')
        $text[3] | Should -BeExactly ((& $at $exp[3].StartMs 'dd.MM.yyyy HH:mm:ss') + ': Absturz von simscan.exe (1-mal). Sitzung nicht ermittelt. Fehlerhaftes Modul: simscan.dll, immer dasselbe. Fehlercode: 0xc0000005 (Zugriffsverletzung). Kein Muster erkannt.')
        $script:SimLbText = $text
    }
    It 'liefert den Druckzustand der simulierten Stunde' {
        $ps = Get-WorkerPerfPrintState -Model $M -EventIncidents $SimInc
        @($ps.Drivers | Where-Object Involved | ForEach-Object Name) | Should -Be @('HP Universal Printing PCL 6 (Sim)')
        @($ps.Drivers | Where-Object PossiblyInvolved).Count | Should -Be 0
        $q = @($ps.Queues | Where-Object Name -eq 'PRN-EG-01'); $q.Count | Should -Be 1; $q[0].MaxJobs | Should -Be 3; $q[0].JobErrors | Should -Be 1; $q[0].NotReadyErrors | Should -Be 0
        @($ps.Processes | ForEach-Object Name) | Should -Contain 'spoolsv.exe'
        foreach ($p in @($ps.Processes)) { $M.Proc[$p.K].Role | Should -Be 'Drucken' }
        $script:SimPrint = $ps
    }
    It 'ordnet die Abstuerze der Messzeit ihren Sitzungen zu' {
        foreach ($i in @($SimInc | Where-Object { $_.Kind -eq 'crash' -and -not $_.Before })) {
            @($i.Sessions).Count | Should -Be @($i.Users).Count
            foreach ($s in $i.Sessions) { @($i.Users) | Should -Contain $M.Sessions[$s].User }
        }
    }
}
Describe 'Konten, die keine Person sind' {
    It 'liest die Muster aus events.json' {
        @($Cfg.NonPersonAccounts) | Should -Contain 'SYSTEM'; @($Cfg.NonPersonAccounts) | Should -Contain 'DWM-*'; @($Cfg.NonPersonAccounts) | Should -Contain '*$'
        @($Cfg.NonPersonAccounts) | Should -Contain 'LOKALER DIENST'; @($Cfg.NonPersonAccounts) | Should -Contain 'ANONYMOUS-ANMELDUNG'
    }
    It 'erkennt Systemkonten mit und ohne Domaene' {
        $ae = [string][char]0x00C4
        foreach ($u in 'SYSTEM', 'system', 'NT AUTHORITY\SYSTEM', 'LOCAL SERVICE', 'Network Service', 'LOKALER DIENST', "NT-AUTORIT$($ae)T\NETZWERKDIENST", 'DWM-3', 'umfd-0',
            'Window Manager\DWM-12', 'ANONYMOUS LOGON', 'ANONYMOUS-ANMELDUNG', 'HOST01$', 'CONTOSO\HOST01$', '') {
            Test-WorkerPerfEventPersonUser $u $Cfg | Should -BeFalse -Because $u
        }
        foreach ($u in 'user002', 'CONTOSO\user002', 'svc_backup', 'DWM', 'systemadmin', 'a$b') { Test-WorkerPerfEventPersonUser $u $Cfg | Should -BeTrue -Because $u }
    }
    It 'weist ungueltige Muster mit dem Feldnamen ab' -TestCases @(
        @{ List = '[""]' }; @{ List = '[5]' }; @{ List = '["A?"]' }; @{ List = '["NT AUTHORITY\\SYSTEM"]' }; @{ List = '["*"]' }; @{ List = '["[a]"]' }; @{ List = '["a``b"]' }
    ) {
        $f = Join-Path $TestDrive 'np.json'
        [IO.File]::WriteAllText($f, '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"P","ids":[1],"group":"app","kind":"crash"}],"nonPersonAccounts":' + $List + '}')
        { Read-WorkerPerfEventConfig $f } | Should -Throw "*Feld 'nonPersonAccounts'*"
    }
    It 'nennt den Besitzer der Sitzung statt eines Systemkontos' {
        $dwm = (Get-Inc @(New-Ev 0 -App 'dwm.exe' -Sid 3 -User 'DWM-3' -More @{ SessionUser = 'user002' }))[0]
        $dwm.Users | Should -Be @('user002'); $dwm.InSession | Should -BeTrue
        $cs = (Get-Inc @(New-Ev 0 -App 'csrss.exe' -Sid 3 -User 'SYSTEM' -More @{ SessionUser = 'user002' }))[0]
        $cs.Users | Should -Be @('user002'); $cs.InSession | Should -BeTrue; $cs.Severity | Should -Be 2
        $own = (Get-Inc @(New-Ev 0 -Sid 3 -User 'other' -More @{ SessionUser = 'user002' }))[0]; $own.Users | Should -Be @('user002')
        $none = (Get-Inc @(New-Ev 0 -App 'dwm.exe' -Sid 3 -User 'DWM-3'))[0]; @($none.Users).Count | Should -Be 0; $none.InSession | Should -BeTrue
    }
    It 'zaehlt ein Systemkonto ohne Sitzung nicht als Benutzersitzung' {
        foreach ($u in 'DWM-3', 'LOKALER DIENST', 'HOST01$') { (Get-Inc @(New-Ev 0 -Sid -1 -User $u -More @{ SessionIndex = -1 })).Count | Should -Be 0 -Because $u }
    }
    It 'nimmt ein Konto einer virtuellen Domaene auch im unmaskierten Bericht nicht als Benutzer' {           # P2-R16
        # Aussage geaendert gegenueber dem Stand vor der Maskierung: "NT SERVICE\MSSQLSERVER" war ein Benutzer mit Vorfall
        foreach ($u in 'NT SERVICE\MSSQLSERVER', 'IIS APPPOOL\DefaultAppPool') { (Get-Inc @(New-Ev 0 -Sid -1 -User $u -More @{ SessionIndex = -1 })).Count | Should -Be 0 -Because $u }
        $bg = Get-Inc @((New-Ev 0 -Sid -1 -User 'NT SERVICE\MSSQLSERVER' -More @{ SessionIndex = -1 }), (New-Ev 10 -Sid -1 -User 'NT SERVICE\MSSQLSERVER' -More @{ SessionIndex = -1 }))
        $bg.Count | Should -Be 1; $bg[0].InSession | Should -BeFalse; @($bg[0].Users).Count | Should -Be 0
        (Get-Inc @(New-Ev 0 -Sid -1 -User 'KLINIK\user005' -More @{ SessionIndex = -1 }))[0].Users | Should -Be @('KLINIK\user005')
    }
}
Describe 'Ausfall der Druckwarteschlange' {
    BeforeAll {
        function New-Stop([double]$Min) { New-Ev $Min 'service' '' 0 '' '' @{ Service = 'Spooler'; Group = 'service'; Source = 'Service Control Manager'; EventId = 7034; Code = '' } }
        function New-SpoolCrash([double]$Min) { New-Ev $Min -App 'spoolsv.exe' -Sid 0 -User '' -Module 'hpsimgr.dll' }
    }
    It 'fuehrt Absturz und Dienstende zu einem Druckproblem zusammen' {
        $i = Get-Inc @((New-SpoolCrash 0), (New-Stop 0.1))
        $i.Count | Should -Be 1; $i[0].Kind | Should -Be 'print'; $i[0].Key | Should -Be 'Sim PCL 6'; $i[0].Count | Should -Be 2; $i[0].Group | Should -Be 'print'
        @($i[0].Events | ForEach-Object { $_.Kind }) | Should -Be @('crash', 'service'); $i[0].Service | Should -Be 'Spooler'; $i[0].App | Should -Be 'spoolsv.exe'
        $j = Get-Inc @((New-Stop 0), (New-SpoolCrash 20)); $j.Count | Should -Be 1; $j[0].Key | Should -Be 'Sim PCL 6'; $j[0].StartMs | Should -Be $T0
    }
    It 'laesst ein Dienstende allein oder fern vom Absturz ein eigenes Druckproblem' {
        $a = Get-Inc @(New-Stop 0); $a.Count | Should -Be 1; $a[0].Kind | Should -Be 'print'; $a[0].Key | Should -Be 'Service Control Manager'; $a[0].Group | Should -Be 'print'
        $b = Get-Inc @((New-SpoolCrash 0), (New-Stop 40)); @($b | ForEach-Object { $_.Key + ':' + $_.Count }) | Should -Be @('Sim PCL 6:1', 'Service Control Manager:1')
        $c = Get-Inc @((New-Ev 0 'print' '' 0 '' '' @{ Group = 'print'; Source = 'Microsoft-Windows-PrintService'; Printer = 'PRN-1' }), (New-Stop 1))
        @($c | ForEach-Object { $_.Key }) | Should -Be @('PRN-1', 'Service Control Manager')
    }
    It 'bildet aus fehlgeschlagenen Treiberimporten keinen Vorfall und macht keinen Treiber beteiligt (P1-R30)' {
        $imp = @(foreach ($k in 0..299) { New-Ev ($k * 3) 'driver-import' '' 0 '' '' @{ Group = 'print'; Source = 'Microsoft-Windows-PrintService'; EventId = 600 + ($k % 2); Driver = 'Sim PCL 6'; Code = '' } })
        (Get-Inc $imp).Count | Should -Be 0
        $ps = Get-WorkerPerfPrintState -Model @{ PrintDrivers = @(@{ Name = 'Sim PCL 6'; Manufacturer = 'HP'; Version = '61.1'; Type = 3; Isolation = 'none'; Files = @('hpsimgr.dll') }); PrintQueues = @(); Processes = @() } -EventIncidents (Get-Inc $imp)
        @($ps.Drivers | Where-Object { $_.Involved -or $_.PossiblyInvolved }).Count | Should -Be 0
        # 215 und ein Absturz der Druckwarteschlange bleiben Vorfaelle, die Importe treten ihnen nicht bei
        $inst = New-Ev 10.5 'print' '' 0 '' '' @{ Group = 'print'; Source = 'Microsoft-Windows-PrintService'; EventId = 215; Driver = 'Sim Neu'; Code = '' }
        $i = Get-Inc (@($imp) + @($inst, (New-SpoolCrash 100.5)))
        @($i | ForEach-Object { $_.Key + ':' + $_.Count }) | Should -Be @('Sim Neu:1', 'Sim PCL 6:1')
        @($i | ForEach-Object { @($_.Events | ForEach-Object { $_.Kind }) }) | Should -Not -Contain 'driver-import'
        Get-WorkerPerfEventIncidentKind (New-Ev 0 'driver-import') $Cfg | Should -BeNullOrEmpty
    }
    It 'nennt den fehlgeschlagenen Treiberimport im Bericht mit eigenem Wort (P1-R30)' {
        [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../src/report-template.html')) | Should -Match '"driver-import": "Treiberimport fehlgeschlagen"'
    }
    It 'nimmt die Schreibweise der Treiberliste' {
        $i = Get-Inc @((New-Ev 0 'print' '' 0 '' '' @{ Group = 'print'; Source = 'Microsoft-Windows-PrintService'; Driver = 'sim pcl 6' }), (New-SpoolCrash 1))
        $i.Count | Should -Be 1; $i[0].Key | Should -BeExactly 'Sim PCL 6'; $i[0].Driver | Should -BeExactly 'Sim PCL 6'
        (Get-Inc @(New-Ev 0 'print' '' 0 '' '' @{ Group = 'print'; Driver = 'Fremd X' }))[0].Driver | Should -BeExactly 'Fremd X'
    }
}
Describe 'Gekuerzte Ereignisliste und Einstellungen' {
    It 'behaelt die ersten 49 und das letzte Ereignis und vermerkt die Kuerzung' {
        $i = (Get-Inc @(1..500 | ForEach-Object { New-Ev ($_ / 100) -Sid 0 -User '' -App 'dienst.exe' }))[0]
        @($i.Events).Count | Should -Be 50; $i.EventsTruncated | Should -BeTrue
        $i.Events[48].TimeMs | Should -Be ([long]($T0 + 0.49 * 60000)); $i.Events[49].TimeMs | Should -Be $i.EndMs
        $s = (Get-Inc @(1..50 | ForEach-Object { New-Ev ($_ / 100) }))[0]; @($s.Events).Count | Should -Be 50; $s.EventsTruncated | Should -BeFalse
    }
    It 'nennt das Feld bei zu grossen Zahlen und Listen' -TestCases @(
        @{ Block = '{"manyUsers":1e12}'; Name = 'manyUsers' }; @{ Block = '{"oneUserEvents":3000000000}'; Name = 'oneUserEvents' }
        @{ Block = '{"eventGroupMinutes":[30]}'; Name = 'eventGroupMinutes' }; @{ Block = '{"resourceMinutes":[]}'; Name = 'resourceMinutes' }
        @{ Block = '{"companionMinutes":[1,2]}'; Name = 'companionMinutes' }
    ) {
        $f = Join-Path $TestDrive 'big.json'; [IO.File]::WriteAllText($f, '{"thresholds":[],"events":' + $Block + '}')
        { Read-WorkerPerfEventSettings $f } | Should -Throw "Schwellwert 'events': Feld '$Name'*"
    }
}
Describe 'Muster' {
    It 'resource: Speicher ueber kritisch in den 5 Minuten davor, nicht 6 Minuten davor' {
        # Aussage geaendert (P1-R35): drei Takte in Folge (minTicks des Signals), der letzte in den 5 Minuten davor
        (Get-Pat @(New-Ev 10) (New-PatternModel (@(50) * 4 + @(95) * 3 + @(50) * 53)))[0] | Should -Contain 'resource'     # Takte 4-6, Takt 6 = 4 min vor dem Absturz
        (Get-Pat @(New-Ev 10) (New-PatternModel (@(50) * 2 + @(95) * 3 + @(50) * 55)))[0] | Should -Not -Contain 'resource'  # Takte 2-4, Takt 4 = 6 min davor
        (Get-Pat @(New-Ev 10) (New-PatternModel (@(50) * 6 + @(95) + @(50) * 53)))[0] | Should -Not -Contain 'resource'     # ein einzelner Takt genuegt nicht
        (Get-Pat @((New-Ev 8 'system' '' 0 '' '' @{ Group = 'memory' }), (New-Ev 10)))[1] | Should -Contain 'resource'
    }
    It 'afterhang: Haenger derselben Anwendung in derselben Sitzung hoechstens 2 Minuten vorher' {
        ((Get-Pat @((New-Ev 8 'hang'), (New-Ev 10))) | Select-Object -Last 1) | Should -Contain 'afterhang'
        ((Get-Pat @((New-Ev 7 'hang'), (New-Ev 10))) | Select-Object -Last 1) | Should -Not -Contain 'afterhang'
        ((Get-Pat @((New-Ev 9 'hang' -Sid 4 -User 'user003'), (New-Ev 10))) | Select-Object -Last 1) | Should -Not -Contain 'afterhang'
    }
    It 'sharedmodule: zwei Anwendungen im selben Modul, kein Systemmodul' {
        $p = Get-Pat @((New-Ev 0 -Module 'simaddin.dll'), (New-Ev 1 -App 'WINWORD.EXE' -Module 'simaddin.dll')); $p[0] | Should -Contain 'sharedmodule'; $p[1] | Should -Contain 'sharedmodule'
        (Get-Pat @((New-Ev 0 -Module 'ntdll.dll'), (New-Ev 1 -App 'WINWORD.EXE' -Module 'NTDLL.dll')))[0] | Should -Not -Contain 'sharedmodule'
    }
    It 'printdriver und securitymodule nach Treiberliste und Rollen' {
        (Get-Pat @(New-Ev 0 -Module 'HPSIMGR.DLL'))[0] | Should -Contain 'printdriver'
        (Get-Pat @(New-Ev 0 -Module 'MpOav.dll'))[0] | Should -Be @('securitymodule')
    }
    It 'manyusers ab drei Benutzern, oneuser ab drei Ereignissen eines Benutzers' {
        (Get-Pat @((New-Ev 0), (New-Ev 1 -Sid 4 -User 'u3'), (New-Ev 2 -Sid 5 -User 'u4')))[0] | Should -Be @('manyusers')
        (Get-Pat @((New-Ev 0), (New-Ev 1 -Sid 4 -User 'u3')))[0].Count | Should -Be 0
        (Get-Pat @((New-Ev 0), (New-Ev 1), (New-Ev 2)))[0] | Should -Be @('oneuser')
    }
    It 'companion mit Uhrzeit, overlap mit gegenseitigem Verweis' {
        $perf = @(@{ Id = 1; StartMs = $T0 + 9 * 60000; EndMs = $T0 + 11 * 60000 })
        $p = Get-Pat @((New-Ev 8.5 'system' '' 0 '' '' @{ Group = 'storage'; Object = 'D:' }), (New-Ev 10)) -Perf $perf
        $p[1] | Should -Be @('companion', 'overlap'); $perf[0].EventIncidents | Should -Be @(10)
    }
    It 'nennt mehrere Muster zugleich und sagt es, wenn keines zutrifft' {
        $evs = @((New-Ev 0 -Module 'simaddin.dll'), (New-Ev 1 -Module 'simaddin.dll'), (New-Ev 2 -Module 'simaddin.dll'), (New-Ev 3 -App 'WINWORD.EXE' -Module 'simaddin.dll'))
        $inc = Get-Inc $evs
        Add-WorkerPerfEventPatterns -Incidents $inc -AllEvents $evs -Model (New-PatternModel (@(50) * 60)) -Thresholds $Th -Settings $Set -Config $Cfg -Roles $Roles -Drivers $Drv -PerfIncidents @()
        $texts = Read-WorkerPerfTexts (Join-Path $PSScriptRoot '../src/texts.de.json')
        $t = Get-WorkerPerfEventIncidentText -Incident $inc[0] -Model $null -Texts $texts -Config $Cfg -OffsetMinutes 0
        $t | Should -Match '^\d\d:\d\d:\d\d–\d\d:\d\d:\d\d: Absturz von EXCEL\.EXE \(3-mal\)\. Benutzer: user002\. Fehlerhaftes Modul: simaddin\.dll, immer dasselbe\. Fehlercode: 0xc0000005 \(Zugriffsverletzung\)\.'
        $t | Should -Match 'Ursache liegt wahrscheinlich im Modul simaddin\.dll \(betrifft EXCEL\.EXE, WINWORD\.EXE\)\. Nur user002 betroffen, 3-mal: spricht für Profil oder Daten dieses Benutzers\.$'
        $pe = @(New-Ev 0 'profileerror' '' 3 'user002' '' @{ Group = 'profile'; Source = 'Microsoft-Windows-User Profiles Service' }); $one = Get-Inc $pe
        Add-WorkerPerfEventPatterns -Incidents $one -AllEvents $pe -Model (New-PatternModel (@(50) * 60)) -Thresholds $Th -Settings $Set -Config $Cfg -Roles $Roles -Drivers $Drv -PerfIncidents @()
        (Get-WorkerPerfEventIncidentText -Incident $one[0] -Model $null -Texts $texts -Config $Cfg -OffsetMinutes 0) | Should -Match 'Kein Muster erkannt\.$'
    }
    It 'prueft im Rueckblick nur Muster ohne Messwerte' {
        $perf = @(@{ Id = 1; StartMs = $T0; EndMs = $T0 + 60000 })
        (Get-Pat @((New-Ev 0), (New-Ev 1), (New-Ev 2)) (New-PatternModel (@(95) * 60)) $perf -Before)[0] | Should -Be @('oneuser')
    }
}
Describe 'Muster im Einzelnen' {
    It 'nennt Signal und Hoechstwert oder die Zeit der Speichermangel-Warnung' {
        $i = (Get-PatInc @(New-Ev 10) (New-PatternModel (@(50) * 6 + @(91, 97, 92) + @(50) * 51)))[0]
        $d = $i.Patterns[0].Detail; $d.SignalId | Should -Be 'mem.used'; $d.Peak | Should -Be 97
        $m = Get-PatInc @((New-Ev 8 'system' '' 0 '' '' @{ Group = 'memory' }), (New-Ev 10))
        $m[1].Patterns[0].Detail.WarningMs | Should -Be ([long]($T0 + 8 * 60000))
        @($m[0].Patterns | ForEach-Object { $_.Id }) | Should -Not -Contain 'resource'                 # die Warnung selbst ist nicht ihre eigene Ursache
        (Get-Pat @((New-Ev 4.9 'system' '' 0 '' '' @{ Group = 'memory' }), (New-Ev 10)))[1] | Should -Not -Contain 'resource'
    }
    It 'prueft resource fuer jedes Ereignis, auch ausserhalb der behaltenen 50' {
        # 120 Abstuerze von Minute 0 bis 59.5, Speicher nur um Minute 30 kritisch: Ereignisse 51..70 liegen nicht in der gekuerzten Liste
        $evs = @(0..119 | ForEach-Object { New-Ev ($_ / 2) -Sid 0 -User '' -App 'dienst.exe' })
        $i = (Get-PatInc $evs (New-PatternModel (@(50) * 29 + @(96) * 3 + @(50) * 28)))[0]                         # Aussage geaendert (P1-R35): drei Takte
        $i.EventsTruncated | Should -BeTrue; @($i.Patterns | ForEach-Object { $_.Id }) | Should -Contain 'resource'
    }
    It 'afterhang ohne Sitzung ueber denselben Benutzer und mit der Zeit des Haengers' {
        $h = New-Ev 9 'hang' -Sid -1 -User 'user005' -More @{ SessionIndex = -1 }; $c = New-Ev 10 -Sid -1 -User 'user005' -More @{ SessionIndex = -1 }
        $i = (Get-PatInc @($h, $c))[1]; $i.Patterns[0].Id | Should -Be 'afterhang'; $i.Patterns[0].Detail.HangMs | Should -Be $h.TimeMs
        (Get-Pat @((New-Ev 9 'hang' -Sid -1 -User 'user006' -More @{ SessionIndex = -1 }), $c))[1] | Should -Not -Contain 'afterhang'
        (Get-Pat @((New-Ev 9 'hang' -App 'WINWORD.EXE'), (New-Ev 10)))[1] | Should -Not -Contain 'afterhang'
    }
    It 'nennt Modul, Anwendungen, Treiber und Produkt' {
        $s = (Get-PatInc @((New-Ev 0 -Module 'simaddin.dll'), (New-Ev 1 -App 'winword.exe' -Module 'SimAddin.dll'), (New-Ev 2 -App 'EXCEL.exe' -Module 'simaddin.dll')))[0]
        $s.Patterns[0].Detail.Module | Should -Be 'simaddin.dll'; $s.Patterns[0].Detail.Apps | Should -Be @('EXCEL.EXE', 'winword.exe')
        $p = (Get-PatInc @(New-Ev 0 -App 'spoolsv.exe' -Sid 0 -User '' -Module 'C:\x\hpsimgr.dll'))[0]
        $p.Patterns[0].Id | Should -Be 'printdriver'; $p.Patterns[0].Detail.Driver | Should -Be 'Sim PCL 6'; $p.Patterns[0].Detail.Module | Should -Be 'C:\x\hpsimgr.dll'
        $a = (Get-PatInc @(New-Ev 0 -Module 'CyMemDef64.dll'))[0]
        $a.Patterns[0].Detail.Product | Should -Be 'Arctic Wolf Aurora Endpoint Protection'; (Get-PatInc @(New-Ev 0 -Module 'mpclient.dll'))[0].Patterns[0].Detail.Product | Should -Be 'Microsoft Defender'
    }
    It 'zaehlt Benutzer und Ereignisse ueber den ganzen Vorfall, nicht ueber die behaltenen 50' {
        $many = @(0..59 | ForEach-Object { New-Ev ($_ / 10) }) + @((New-Ev 6.5 -Sid 4 -User 'u3'), (New-Ev 6.6 -Sid 5 -User 'u4'))
        $i = (Get-PatInc $many)[0]; $i.EventsTruncated | Should -BeTrue; $i.Patterns[0].Id | Should -Be 'manyusers'; $i.Patterns[0].Detail.Users | Should -Be 3
        $one = (Get-PatInc @(0..59 | ForEach-Object { New-Ev ($_ / 10) }))[0]
        $one.Patterns[0].Id | Should -Be 'oneuser'; $one.Patterns[0].Detail.User | Should -Be 'user002'; $one.Patterns[0].Detail.Count | Should -Be 60
        # ein Benutzer, aber nur zwei seiner Ereignisse: kein oneuser
        (Get-Pat @((New-Ev 0), (New-Ev 1), (New-Ev 2 -Sid 0 -User '')))[0] | Should -Not -Contain 'oneuser'
        (Get-Pat @((New-Ev 0 'hang' -Sid 0 -User ''), (New-Ev 1 'hang' -Sid 4 -User 'u3'), (New-Ev 2 'hang' -Sid 5 -User 'u4'), (New-Ev 3 'hang' -Sid 6 -User 'u5')))[0] | Should -Be @('manyusers')
        (Get-Pat @((New-Ev 0 'profileerror' '' 3 'a' '' @{ Group = 'profile' }), (New-Ev 1 'profileerror' '' 4 'b' '' @{ Group = 'profile' }), (New-Ev 2 'profileerror' '' 5 'c' '' @{ Group = 'profile' })))[0] | Should -Not -Contain 'manyusers'
    }
    It 'companion: hoechstens zwei Minuten, nicht das eigene Ereignis, hoechstens zehn' {
        (Get-Pat @((New-Ev 7.9 'system' '' 0 '' '' @{ Group = 'storage'; Object = 'D:' }), (New-Ev 10)))[1] | Should -Not -Contain 'companion'
        (Get-Pat @((New-Ev 11.5 'scan-start' '' 0 '' '' @{ Group = 'security' }), (New-Ev 10)))[0] | Should -Be @('companion')
        (Get-Pat @((New-Ev 10.5 'logon' '' 3 'user002' '' @{ Group = 'session' }), (New-Ev 10)))[0].Count | Should -Be 0
        $own = Get-PatInc @((New-Ev 0 'system' '' 0 '' '' @{ Group = 'storage'; Object = 'D:' }), (New-Ev 1 'system' '' 0 '' '' @{ Group = 'storage'; Object = 'D:' }), (New-Ev 1.5 'system' '' 0 '' '' @{ Group = 'storage'; Object = 'E:' }))
        $own[0].Patterns[0].Id | Should -Be 'companion'; @($own[0].Companions).Count | Should -Be 1; $own[0].Companions[0].Object | Should -Be 'E:'
        $twelve = @(1..12 | ForEach-Object { New-Ev (9 + $_ / 10) 'scan-end' '' 0 '' '' @{ Group = 'security' } }) + @(New-Ev 10)
        $i = (Get-PatInc $twelve)[0]; @($i.Patterns[0].Detail.Events).Count | Should -Be 10; @($i.Companions).Count | Should -Be 10
        $i.Companions[0].TimeMs | Should -Be ([long]($T0 + 9.1 * 60000))
    }
    It 'overlap: Rand zaehlt, ein Dauerzustand nicht, jeder Leistungsvorfall bekommt EventIncidents' {
        $perf = @(@{ Id = 1; StartMs = $T0 + 10 * 60000; EndMs = $T0 + 11 * 60000; Chronic = $false }, @{ Id = 2; StartMs = $T0; EndMs = $T0 + 60 * 60000; Chronic = $true },
            @{ Id = 3; StartMs = $T0 + 20 * 60000; EndMs = $T0 + 21 * 60000 })
        $i = (Get-PatInc @(New-Ev 10) -Perf $perf)[0]
        $i.Patterns[0].Id | Should -Be 'overlap'; $i.Patterns[0].Detail.Incidents | Should -Be @(1); $i.Overlap | Should -Be @(1)
        $perf[0].EventIncidents | Should -Be @(9); @($perf[1].EventIncidents).Count | Should -Be 0; @($perf[2].EventIncidents).Count | Should -Be 0
        $perf[2].EventIncidents -is [int[]] | Should -BeTrue
    }
    It 'ordnet mehrere Muster in der festen Reihenfolge und setzt sie bei jedem Aufruf neu' {
        $evs = @((New-Ev 8 'system' '' 0 '' '' @{ Group = 'memory' }), (New-Ev 9.5 'hang'), (New-Ev 10 -Module 'hpsimgr.dll'), (New-Ev 10.2 -Module 'hpsimgr.dll'), (New-Ev 10.4 -Module 'MpOav.dll'),
            (New-Ev 10.6 -App 'WINWORD.EXE' -Module 'hpsimgr.dll'), (New-Ev 11 'system' '' 0 '' '' @{ Group = 'fileserver'; Object = 'fs01' }))
        $perf = @(@{ Id = 4; StartMs = $T0 + 10.1 * 60000; EndMs = $T0 + 10.3 * 60000 })
        $inc = Get-Inc $evs; $crash = @($inc | Where-Object { $_.Kind -eq 'crash' -and $_.App -eq 'EXCEL.EXE' })[0]
        foreach ($n in 1, 2) {
            Add-WorkerPerfEventPatterns -Incidents $inc -AllEvents $evs -Model (New-PatternModel (@(50) * 60)) -Thresholds $Th -Settings $Set -Config $Cfg -Roles $Roles -Drivers $Drv -PerfIncidents $perf
            @($crash.Patterns | ForEach-Object { $_.Id }) | Should -Be @('resource', 'afterhang', 'sharedmodule', 'printdriver', 'securitymodule', 'oneuser', 'companion', 'overlap')
            $perf[0].EventIncidents | Should -Be @($crash.Id)
        }
    }
    It 'laesst im Rueckblick Modell und Leistungsvorfaelle weg' {
        $evs = @((New-Ev 8 'system' '' 0 '' '' @{ Group = 'memory' }), (New-Ev 10))
        $inc = Get-Inc $evs -Before
        Add-WorkerPerfEventPatterns -Incidents $inc -AllEvents $evs -Model $null -Thresholds $Th -Settings $Set -Config $Cfg -Roles $Roles -Drivers @() -PerfIncidents $null -Before
        @($inc[1].Patterns).Count | Should -Be 0; @($inc[1].Overlap).Count | Should -Be 0
    }
}
Describe 'Klartext eines Ereignisvorfalls' {
    It 'nennt Kopf je Art, Zeit in Ortszeit und die Zusaetze' {
        $c = (Get-PatInc @(New-Ev 0 -Sid 0 -User '' -App 'spoolsv.exe' -Module 'hpsimgr.dll'))[0]
        $clock = [DateTimeOffset]::FromUnixTimeMilliseconds($T0).UtcDateTime.AddMinutes(60).ToString('HH:mm:ss')
        Get-Text $c 60 | Should -BeExactly "$($clock): Druckproblem – Sim PCL 6 (1-mal). Ohne Benutzersitzung. Fehlerhaftes Modul: hpsimgr.dll, immer dasselbe. Fehlercode: 0xc0000005 (Zugriffsverletzung). Das Modul hpsimgr.dll gehört zum Druckertreiber Sim PCL 6."
        $h = (Get-PatInc @((New-Ev 0 'hang' -Module '' -More @{ Code = 'AppHangB1'; AppVersion = '1.0' }), (New-Ev 1 'hang' -Sid 4 -User 'user003' -Module '' -More @{ Code = 'AppHangB1'; AppVersion = '1.1' })))[0]
        Get-Text $h | Should -Match ': EXCEL\.EXE reagierte nicht und wurde beendet \(2-mal\)\. Benutzer: user002, user003\. Fehlercode: AppHangB1 \(wegen Nichtreagierens beendet\)\. Versionen: 1\.0, 1\.1\. Kein Muster erkannt\.$'
        $s = (Get-PatInc @(New-Ev 0 'service' '' 0 '' '' @{ Service = 'BrokerAgent'; Group = 'service'; Code = ''; Module = '' }))[0]
        Get-Text $s | Should -Match '^\d\d:\d\d:\d\d: Dienst BrokerAgent unerwartet beendet \(1-mal\)\. Ohne Benutzersitzung\. Kein Muster erkannt\.$'
        $p = (Get-PatInc @(New-Ev 0 'profileerror' '' -1 'user014' '' @{ Group = 'profile'; Source = 'Microsoft-Windows-User Profiles Service'; Code = ''; SessionIndex = -1 }))[0]
        Get-Text $p | Should -Match ': Profilproblem – Microsoft-Windows-User Profiles Service \(1-mal\)\. Benutzer: user014\. Kein Muster erkannt\.$'
        $y = (Get-PatInc @(New-Ev 0 'system' '' 0 '' '' @{ Group = 'storage'; Source = 'disk'; Object = 'D:'; Code = ''; Module = '' }))[0]
        Get-Text $y | Should -Match ': Systemfehler – Datenträgerfehler D: \(1-mal\)\. Ohne Benutzersitzung\. Kein Muster erkannt\.$'
    }
    It 'nennt gemischte Module mit Anzahl, Begleitereignisse mit Uhrzeit und ueberlappende Vorfaelle' {
        $perf = @(@{ Id = 2; StartMs = $T0; EndMs = $T0 + 60000 }, @{ Id = 5; StartMs = $T0 + 30000; EndMs = $T0 + 90000 })
        $i = (Get-PatInc @((New-Ev 0 'system' '' 0 '' '' @{ Group = 'storage'; Source = 'disk'; Object = 'D:' }), (New-Ev 0.5), (New-Ev 1 -Sid 4 -User 'user003' -Module 'mso.dll'), (New-Ev 1.2 -Module 'mso.dll')) -Perf $perf)[1]
        $clock = Format-WorkerPerfClock $T0 0
        $t = Get-Text $i
        $t | Should -Match 'Fehlerhafte Module: mso\.dll \(2-mal\), vbe7\.dll \(1-mal\)\.'
        $t | Should -Match ([regex]::Escape(" Zeitnah: $clock Datenträgerfehler D:. Zeitgleich mit den Vorfällen 2, 5.") + '$')
    }
}
Describe 'Rollen mit Modulen' {
    It 'liest modules als Liste, Standard leer' {
        @(($Roles | Where-Object label -eq 'Microsoft Defender').modules) | Should -Be @('MpOav.dll', 'MpClient.dll')
        @(($Roles | Where-Object label -eq 'Arctic Wolf Aurora Endpoint Protection').modules) | Should -Be @('CyMemDef*.dll')
        ($Roles | Where-Object label -eq 'Arctic Wolf Aurora Endpoint Protection').note | Should -Match 'Module ungeprüft'
        ($Roles | Where-Object label -eq 'AppLocker').modules.Count | Should -Be 0
        $f = Join-Path $TestDrive 'r.json'; [IO.File]::WriteAllText($f, '{"roles":[{"role":"Sicherheit","label":"X","modules":"x.dll"}]}')
        $r = @(Read-WorkerPerfRoles $f); $r[0].modules -is [array] | Should -BeTrue; $r[0].modules | Should -Be @('x.dll')
    }
}
Describe 'Kleine Korrekturen aus der Pruefung von Task 5' {
    BeforeAll {
        function New-Stop2([double]$Min) { New-Ev $Min 'service' '' 0 '' '' @{ Service = 'Spooler'; Group = 'service'; Source = 'Service Control Manager'; EventId = 7034; Code = '' } }
        function New-SpoolCrash2([double]$Min, [hashtable]$More = @{}) { New-Ev $Min -App 'spoolsv.exe' -Sid 0 -User '' -Module 'hpsimgr.dll' -More $More }
    }
    It 'a) ein Dienstende zwischen zwei gleichzeitigen Abstuerzen geht unabhaengig von der Eingabe zum kleineren Schluessel' {
        $x = New-SpoolCrash2 0; $y = New-SpoolCrash2 0 @{ Module = 'other.dll'; Driver = 'Kyo KX' }; $s = New-Stop2 1
        foreach ($order in @(@($x, $y, $s), @($y, $x, $s), @($s, $y, $x))) {
            $r = Get-Inc $order; @($r | ForEach-Object { $_.Key + ':' + $_.Count }) | Should -Be @('Kyo KX:2', 'Sim PCL 6:1')
        }
    }
    It 'b) misst den Abstand eines Dienstendes zum letzten Ereignis des Vorfalls' {
        $drv = New-Ev 20 'print' '' 0 '' '' @{ Group = 'print'; Source = 'Microsoft-Windows-PrintService'; Driver = 'Sim PCL 6'; Module = ''; Code = '' }
        $i = Get-Inc @((New-SpoolCrash2 0), $drv, (New-Stop2 45)); $i.Count | Should -Be 1; $i[0].Count | Should -Be 3
        $c = Get-Inc @((New-SpoolCrash2 0), (New-Stop2 25), (New-Stop2 50)); $c.Count | Should -Be 1; $c[0].Count | Should -Be 3
        # ein Druckvorfall ohne Absturz der Warteschlange nimmt kein Dienstende auf
        $d = Get-Inc @($drv, (New-Stop2 21)); @($d | ForEach-Object { $_.Key }) | Should -Be @('Sim PCL 6', 'Service Control Manager')
    }
    It 'c) nimmt ohne nonPersonAccounts die eingebaute Liste, eine leere Liste bleibt leer' {
        $f = Join-Path $TestDrive 'np0.json'; $base = '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"P","ids":[1],"group":"app","kind":"crash"}]'
        [IO.File]::WriteAllText($f, $base + '}'); $c = Read-WorkerPerfEventConfig $f
        @($c.NonPersonAccounts) | Should -Be @($Cfg.NonPersonAccounts); Test-WorkerPerfEventPersonUser 'SYSTEM' $c | Should -BeFalse
        [IO.File]::WriteAllText($f, $base + ',"nonPersonAccounts":null}'); @((Read-WorkerPerfEventConfig $f).NonPersonAccounts) | Should -Be @($Cfg.NonPersonAccounts)
        [IO.File]::WriteAllText($f, $base + ',"nonPersonAccounts":[]}'); $e = Read-WorkerPerfEventConfig $f
        @($e.NonPersonAccounts).Count | Should -Be 0; Test-WorkerPerfEventPersonUser 'SYSTEM' $e | Should -BeTrue
        $shipped = (Get-Content (Join-Path $PSScriptRoot '../src/events.json') -Raw | ConvertFrom-Json).nonPersonAccounts
        @($script:WorkerPerfDefaultNonPersonAccounts) | Should -Be @($shipped)
    }
    It 'd) gibt einem Ereignis vor dem ersten Takt keine Sitzung, kurz davor schon' {
        $model = @{ Meta = @{ IntervalSeconds = 60 }; Snap = @{ N = 3; TimeMs = [long[]]@(0..2 | ForEach-Object { $T0 + $_ * 60000 }) }
            Tick = @{ TimeMs = [long[]]@(0..10 | ForEach-Object { $T0 - 30000 + $_ * 15000 }) }
            Sessions = @(@{ Index = 0; Sid = 5; User = 'user001'; FirstP = 0; LastP = 2 }) }
        $show = { param([double]$Min) $e = New-Ev $Min -Sid 5 -User ''; Set-WorkerPerfEventSessions -Events @($e) -Model $model -Config $Cfg; '{0}|{1}' -f $e.SessionIndex, $e.SessionUser }
        & $show -0.25 | Should -Be '0|user001'; & $show -0.5 | Should -Be '0|user001'; & $show -0.75 | Should -Be '-1|'
        $byUser = New-Ev -0.75 -Sid -1 -User 'user001'; Set-WorkerPerfEventSessions -Events @($byUser) -Model $model -Config $Cfg; $byUser.SessionIndex | Should -Be -1
    }
}
Describe 'Pruefung von Task 6, Runde 1' {
    BeforeAll {
        function Get-PatIncD([object[]]$Events, [object[]]$Drivers, $Model = (New-PatternModel (@(50) * 60)), [object[]]$Perf = @()) {
            $inc = @(New-WorkerPerfEventIncidents -Events $Events -Config $Cfg -Settings $Set -Drivers $Drivers -FirstId 9)
            Add-WorkerPerfEventPatterns -Incidents $inc -AllEvents $Events -Model $Model -Thresholds $Th -Settings $Set -Config $Cfg -Roles $Roles -Drivers $Drivers -PerfIncidents $Perf
            , $inc
        }
        function Get-Ids($Inc) { , @($Inc.Patterns | ForEach-Object { $_.Id }) }
    }
    It 'C1: unknown, StackHash_ und leere Module sind kein Modul' {
        @($Cfg.NoModules) | Should -Be @('unknown', 'StackHash_*')
        foreach ($m in 'unknown', 'UNKNOWN', 'StackHash_1a2b', 'stackhash_0000') {
            $p = Get-PatInc @((New-Ev 0 -Module $m), (New-Ev 1 -App 'WINWORD.EXE' -Module $m))
            Get-Ids $p[0] | Should -Not -Contain 'sharedmodule' -Because $m
            Get-Text $p[0] | Should -Match 'Benutzer: user002\. Fehlerhaftes Modul nicht ermittelt\. Fehlercode' -Because $m
        }
        Get-Text (Get-PatInc @(New-Ev 0 -Module ''))[0] | Should -Match 'Fehlerhaftes Modul nicht ermittelt\.'
        $drv = @(@{ Name = 'Odd'; Files = @('unknown') }); (Get-Ids (Get-PatIncD @(New-Ev 0 -App 'spoolsv.exe' -Sid 0 -User '' -Module 'unknown') $drv)[0]) | Should -Not -Contain 'printdriver'
        (Get-PatIncD @(New-Ev 0 -App 'spoolsv.exe' -Sid 0 -User '' -Module 'unknown') $drv)[0].Driver | Should -Be ''
        $mix = (Get-PatInc @((New-Ev 0), (New-Ev 1 -Module 'unknown'), (New-Ev 2)))[0]
        Get-Text $mix | Should -Match 'Fehlerhaftes Modul: vbe7\.dll \(2 von 3\)\.'
        Get-Text (Get-PatInc @(New-Ev 0 'hang' -Module ''))[0] | Should -Not -Match 'Modul'
    }
    It 'C1: noModules wird geprueft, fehlt es, gilt die eingebaute Liste' {
        $f = Join-Path $TestDrive 'nm.json'; $base = '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"P","ids":[1],"group":"app","kind":"crash"}]'
        [IO.File]::WriteAllText($f, $base + '}'); @((Read-WorkerPerfEventConfig $f).NoModules) | Should -Be @('unknown', 'StackHash_*')
        [IO.File]::WriteAllText($f, $base + ',"noModules":[]}'); @((Read-WorkerPerfEventConfig $f).NoModules).Count | Should -Be 0
        foreach ($bad in '[""]', '[5]', '["a?"]', '["*"]', '["x\\\\y"]') {
            [IO.File]::WriteAllText($f, $base + ',"noModules":' + $bad + '}'); { Read-WorkerPerfEventConfig $f } | Should -Throw "*Feld 'noModules'*" -Because $bad
        }
    }
    It 'C2: eine Datei mehrerer Treiber nennt keinen einzelnen Treiber, in beiden Reihenfolgen' {
        $a = @{ Name = 'Kyo B'; Files = @('unidrv.dll', 'kyob.dll') }; $b = @{ Name = 'HP A'; Files = @('UNIDRV.DLL') }
        foreach ($drv in @(@($a, $b), @($b, $a))) {
            $i = (Get-PatIncD @(New-Ev 0 -App 'spoolsv.exe' -Sid 0 -User '' -Module 'unidrv.dll') $drv)[0]
            $i.Key | Should -Be 'Application Error'; $i.Driver | Should -Be ''
            $i.Patterns[0].Id | Should -Be 'printdriver'; $i.Patterns[0].Detail.Drivers | Should -Be @('HP A', 'Kyo B'); $i.Patterns[0].Detail.Driver | Should -Be ''
            Get-Text $i | Should -Match '^\d\d:\d\d:\d\d: Druckproblem – spoolsv\.exe \(1-mal\)\..* Das Modul unidrv\.dll gehört zu mehreren Druckertreibern \(HP A, Kyo B\); welcher beteiligt war, ist nicht bestimmbar\.$'
            $k = (Get-PatIncD @(New-Ev 0 -App 'spoolsv.exe' -Sid 0 -User '' -Module 'kyob.dll') $drv)[0]
            $k.Key | Should -Be 'Kyo B'; $k.Patterns[0].Detail.Driver | Should -Be 'Kyo B'; $k.Patterns[0].Detail.Drivers | Should -Be @('Kyo B')
        }
    }
    It 'Important: Laufzeit- und Systemmodule als Muster sind nie gemeinsame Ursache' {
        foreach ($m in 'ntdll.dll', 'VCRUNTIME140.dll', 'vcruntime140_1.dll', 'MSVCP140.dll', 'msvcr120.dll', 'mfc140u.dll', 'clrjit.dll', 'mscorlib.ni.dll', 'OLE32.DLL', 'C:\Windows\System32\rpcrt4.dll') {
            Get-Ids (Get-PatInc @((New-Ev 0 -Module $m), (New-Ev 1 -App 'nexus.exe' -Module $m)))[0] | Should -Not -Contain 'sharedmodule' -Because $m
        }
        @($Cfg.SystemModules) | Should -Contain 'VCRUNTIME*.dll'; @($Cfg.SystemModules).Count | Should -Be 24
        $f = Join-Path $TestDrive 'sm.json'; [IO.File]::WriteAllText($f, '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"P","ids":[1],"group":"app","kind":"crash"}],"systemModules":["a?.dll"]}')
        { Read-WorkerPerfEventConfig $f } | Should -Throw "*Feld 'systemModules'*"
    }
    It 'Minor: afterhang sagt, wie viele Abstuerze einem Haenger folgten' {
        $i = (Get-PatInc @((New-Ev 0), (New-Ev 5), (New-Ev 9.5 'hang' -Module ''), (New-Ev 10)))
        $c = @($i | Where-Object { $_.Kind -eq 'crash' })[0]
        $c.Patterns[0].Detail.Count | Should -Be 1; $c.Patterns[0].Detail.Crashes | Should -Be 3
        Get-Text $c | Should -Match ' Nach Nichtreagieren beendet: 1 von 3\.'                       # N1 (Task 7): Aussage geaendert
        Get-Text (Get-PatInc @((New-Ev 9.5 'hang' -Module ''), (New-Ev 10)))[1] | Should -Match ' Wurde nach Nichtreagieren beendet\.'
    }
    It 'Minor: overlap sortiert und im Plural' {
        $perf = @(@{ Id = 3; StartMs = $T0; EndMs = $T0 + 60000 }, @{ Id = 2; StartMs = $T0; EndMs = $T0 + 60000 })
        $i = (Get-PatInc @(New-Ev 0) -Perf $perf)[0]; $i.Overlap | Should -Be @(2, 3); $i.Patterns[0].Detail.Incidents | Should -Be @(2, 3)
        Get-Text $i | Should -Match ' Zeitgleich mit den Vorfällen 2, 3\.$'
    }
    It 'Minor: mehrere Fehlercodes im Plural' {
        Get-Text (Get-PatInc @((New-Ev 0 -More @{ Code = '0xdeadbeef' }), (New-Ev 1)))[0] | Should -Match ' Fehlercodes: 0xdeadbeef, 0xc0000005 \(Zugriffsverletzung\)\.'
    }
    It 'Minor: Begleitereignisse nennen, was geschah, gleichzeitige in fester Ordnung' {
        $clock = Format-WorkerPerfClock ([long]($T0 + 11 * 60000)) 0
        foreach ($k in @(@('scan-start', 'security', 'Virenscan gestartet'), @('scan-end', 'security', 'Virenscan beendet'), @('signature-update', 'security', 'Signaturen aktualisiert'),
                @('applocker-block', 'security', 'AppLocker hat eine Ausführung blockiert'), @('profileerror', 'profile', 'Profilfehler'), @('info', 'security', 'Quelle X'))) {
            $i = (Get-PatInc @((New-Ev 10), (New-Ev 11 $k[0] '' 0 '' '' @{ Group = $k[1]; Source = 'Quelle X' })))[0]
            Get-Text $i | Should -Match ([regex]::Escape(" Zeitnah: $clock $($k[2]).")) -Because $k[0]
        }
        $s = New-Ev 11 'system' '' 0 '' '' @{ Group = 'storage'; Source = 'disk'; Object = 'D:' }; $f = New-Ev 11 'system' '' 0 '' '' @{ Group = 'fileserver'; Source = 'SMB'; Object = 'fs01' }
        foreach ($order in @(@((New-Ev 10), $s, $f), @($f, $s, (New-Ev 10)))) {
            $i = @((Get-PatInc $order) | Where-Object { $_.Kind -eq 'crash' })[0]
            Get-Text $i | Should -Match ([regex]::Escape(" Zeitnah: $clock Verbindungsabbruch zum Dateiserver fs01, $clock Datenträgerfehler D:."))
        }
    }
    It 'Minor: eine Speichermangel-Warnung ist nicht ihre eigene Ursache, der Kopf nennt die Gruppe' {
        $w = (Get-PatInc @(New-Ev 10 'system' '' 0 '' '' @{ Group = 'memory'; Source = 'Microsoft-Windows-Resource-Exhaustion-Detector'; Module = ''; Code = '' }) (New-PatternModel (@(95) * 60)))[0]
        @($w.Patterns).Count | Should -Be 0
        Get-Text $w | Should -Match ': Systemfehler – Speichermangel-Warnung \(1-mal\)\. Ohne Benutzersitzung\. Kein Muster erkannt\.$'
        Get-Text (Get-PatInc @(New-Ev 0 'system' '' 0 '' '' @{ Group = 'fileserver'; Source = 'SMB'; Object = 'fs01'; Module = ''; Code = '' }))[0] | Should -Match 'Systemfehler – Verbindungsabbruch zum Dateiserver fs01 \(1-mal\)'
    }
    It 'Minor: Listen zeigen hoechstens zehn Eintraege' {                                         # N3 (Task 7): Aussagen geaendert
        $evs = @(1..40 | ForEach-Object { New-Ev ($_ / 10) -Sid (10 + $_) -User ('u{0:d2}' -f $_) })
        $t = Get-Text (Get-PatInc $evs)[0]
        $t | Should -Match ' Benutzer: u01, u02, u03, u04, u05, u06, u07, u08, u09, u10 \(\+30 weitere\)\. '; $t | Should -Match ' 40 Benutzer betroffen'
        $apps = @(1..15 | ForEach-Object { New-Ev ($_ / 10) -App ('app{0:d2}.exe' -f $_) -Module 'simaddin.dll' })
        Get-Text (Get-PatInc $apps)[0] | Should -Match '\(betrifft app01\.exe, .*app10\.exe \(\+5 weitere\)\)\.'
        $mods = @(1..12 | ForEach-Object { New-Ev ($_ / 10) -Module ('m{0:d2}.dll' -f $_) })
        Get-Text (Get-PatInc $mods)[0] | Should -Match 'Fehlerhafte Module: m01\.dll \(1-mal\), .*m10\.dll \(1-mal\) \(\+2 weitere\)\.'
    }
    It 'Minor: eine Anwendung ohne Namen heisst unbekannte Anwendung' {
        # N1 (Task 7): Aussage geaendert, eigene Kopftexte ohne Anwendungsnamen
        Get-Text (Get-PatInc @(New-Ev 0 -App ''))[0] | Should -Match '^\d\d:\d\d:\d\d: Absturz einer unbekannten Anwendung \(1-mal\)\.'
        Get-Text (Get-PatInc @(New-Ev 0 'hang' -App '' -Module ''))[0] | Should -Match '^\d\d:\d\d:\d\d: Eine unbekannte Anwendung reagierte nicht und wurde beendet \(1-mal\)\.'
    }
    It 'Minor: afterhang findet den Haenger auch zwischen vielen anderen Haengern' {
        $evs = @(1..300 | ForEach-Object { New-Ev (8 + $_ / 200) 'hang' -App ('other{0}.exe' -f ($_ % 7)) -Sid (3 + $_ % 5) -Module '' }) + @((New-Ev 9 'hang' -Sid 5 -User 'u5' -Module ''), (New-Ev 9.5 'hang' -Sid -1 -User 'user002' -Module '' -More @{ SessionIndex = -1 }), (New-Ev 10))
        $c = @((Get-PatInc $evs) | Where-Object { $_.Kind -eq 'crash' })[0]
        $c.Patterns[0].Id | Should -Be 'afterhang'; $c.Patterns[0].Detail.HangMs | Should -Be ([long]($T0 + 9.5 * 60000))
    }
}
Describe 'Rueckblick und Druckzustand' {
    BeforeAll {
        function New-LbModel([object[]]$Before) { @{ EventsBefore = $Before; Tick = @{ TimeMs = [long[]]@($T0, $T0 + 60000) }; Meta = @{ OffsetMinutes = 60; EventLookbackDays = 7; LookbackCapped = @('system') }; Sessions = @() } }
    }
    It 'trennt den Rueckblick von der Messzeit und zaehlt je Tag' {                               # Review Focus 3
        $m = New-LbModel @((New-Ev (-3 * 1440)), (New-Ev (-3 * 1440 + 10)), (New-Ev (-3 * 1440 + 20)), (New-Ev (-1440) -App 'WINWORD.EXE' -Module 'mso.dll'), (New-Ev 0))   # Modul geaendert: in vbe7.dll waere es sharedmodule
        $l = Get-WorkerPerfLookback -Model $m -Config $Cfg -Settings $Set -Roles $Roles -FirstId 20 -ReportedMs $null
        $l.EventCount | Should -Be 4; @($l.Incidents).Count | Should -Be 2; $l.Incidents[0].Before | Should -BeTrue; $l.Incidents[0].Id | Should -Be 20
        @($l.Incidents[0].Patterns | ForEach-Object Id) | Should -Be @('oneuser'); @($l.PerDay).Count | Should -Be 2; $l.PerDay[0].Count | Should -Be 3
        $l.Capped | Should -Be @('system'); $l.Days | Should -Be 7
    }
    It 'liefert Ereignisse um eine gemeldete Zeit vor der Messung' {
        $m = New-LbModel @((New-Ev -100), (New-Ev -80), (New-Ev -40))
        @((Get-WorkerPerfLookback -Model $m -Config $Cfg -Settings $Set -Roles $Roles -FirstId 1 -ReportedMs ($T0 - 90 * 60000)).Near).Count | Should -Be 2
        @((Get-WorkerPerfLookback -Model $m -Config $Cfg -Settings $Set -Roles $Roles -FirstId 1 -ReportedMs ($T0 + 60000)).Near).Count | Should -Be 0
    }
    It 'liefert den Druckzustand' {
        $m = @{ PrintDrivers = @(@{ Name = 'Sim PCL 6'; Manufacturer = 'HP'; Version = '61'; Type = 3; Isolation = 'none'; Files = @('hpsimgr.dll') }, @{ Name = 'Sim KX'; Manufacturer = 'Kyocera'; Version = '8'; Type = 3; Isolation = 'isolated'; Files = @('kx.dll') })
            PrintQueues = @(@{ TimeMs = $T0; Queue = 'Q1'; Jobs = 0; JobErrors = 5; NotReadyErrors = 0 }, @{ TimeMs = $T0 + 15000; Queue = 'Q1'; Jobs = 3; JobErrors = 6; NotReadyErrors = 0 },
                            @{ TimeMs = $T0 + 30000; Queue = 'Q1'; Jobs = 1; JobErrors = 0; NotReadyErrors = 0 }, @{ TimeMs = $T0 + 45000; Queue = 'Q1'; Jobs = 0; JobErrors = 2; NotReadyErrors = 0 })
            Proc = @(@{ K = 0; Name = 'spoolsv.exe'; Role = 'Drucken'; CpuMaxPct = 1.5; WsMaxKB = 40960 }, @{ K = 1; Name = 'EXCEL.EXE'; Role = ''; CpuMaxPct = 9; WsMaxKB = 1 }) }
        $s = Get-WorkerPerfPrintState -Model $m -EventIncidents @(@{ Kind = 'print'; Key = 'Sim PCL 6'; Patterns = @() })
        ($s.Drivers | Where-Object Name -eq 'Sim PCL 6').Involved | Should -BeTrue; ($s.Drivers | Where-Object Name -eq 'Sim KX').Isolated | Should -BeTrue
        $s.Queues[0].MaxJobs | Should -Be 3; $s.Queues[0].JobErrors | Should -Be 3                  # 5 -> 6 (+1), Neustart auf 0, 0 -> 2 (+2)
        @($s.Processes).Name | Should -Be @('spoolsv.exe'); $s.Processes[0].WsMaxMB | Should -Be 40
    }
}
Describe 'Rueckblick und Druckzustand im Einzelnen' {
    BeforeAll {
        function New-LbModel2([object[]]$Before, $Meta = @{ OffsetMinutes = 60; EventLookbackDays = 7; LookbackCapped = @() }) { @{ EventsBefore = $Before; Tick = @{ TimeMs = [long[]]@($T0, $T0 + 60000) }; Meta = $Meta; Sessions = @() } }
        function Get-Lb($Model, $Reported = $null) { Get-WorkerPerfLookback -Model $Model -Config $Cfg -Settings $Set -Roles $Roles -FirstId 1 -ReportedMs $Reported }
    }
    It 'beginnt den Rueckblick Days Tage vor dem ersten Takt und laesst Ereignisse ab dem ersten Takt weg' {
        $evs = @((New-Ev -10), (New-Ev 0), (New-Ev 0.5))
        $l = Get-Lb (New-LbModel2 $evs)
        $l.FromMs | Should -Be ([long]($T0 - 7 * 86400000)); $l.EventCount | Should -Be 1; @($l.Incidents).Count | Should -Be 1; $l.Incidents[0].Count | Should -Be 1
        $evs[1].ContainsKey('IncidentId') | Should -BeFalse -Because 'ein Ereignis der Messzeit gehoert nicht zum Rueckblick'
        $evs[0].IncidentId | Should -Be 1; $evs[0].SessionIndex | Should -Be -1 -Because 'vor der Messung gibt es keine Sitzung der Messung'
    }
    It 'liefert ohne Rueckblick leere Listen und Days 0' {
        $l = Get-Lb (New-LbModel2 @() @{ OffsetMinutes = 0; EventLookbackDays = $null; LookbackCapped = [string[]]@() })
        $l.Days | Should -Be 0; $l.EventCount | Should -Be 0; @($l.Incidents).Count | Should -Be 0; @($l.PerDay).Count | Should -Be 0; @($l.Near).Count | Should -Be 0; @($l.Capped).Count | Should -Be 0
        $l.FromMs | Should -Be ([long]$T0)
        $l2 = Get-Lb @{ Tick = @{ TimeMs = [long[]]@($T0) }; Meta = @{ OffsetMinutes = 0 } }
        $l2.EventCount | Should -Be 0; $l2.Days | Should -Be 0; @($l2.Capped).Count | Should -Be 0
    }
    It 'zaehlt je Tag in Ortszeit des Servers, aufsteigend, nur Ereignisse mit Vorfallsart' {
        # T0 = 22:13:20 UTC; mit +60 min ist -50 min noch derselbe Ortstag, -80 min (21:53 Ortszeit) ebenso, -1400 min der Vortag
        $evs = @((New-Ev -1400), (New-Ev -80), (New-Ev -50), (New-Ev -40 'logon' '' 3 'user002' '' @{ Group = 'session' }))
        $l = Get-Lb (New-LbModel2 $evs)
        @($l.PerDay | ForEach-Object { '{0}:{1}' -f $_.Day, $_.Count }) | Should -Be @('2023-11-13:1', '2023-11-14:2')
        $l.EventCount | Should -Be 4
        # -20 und -10 min: mit +60 min 22:53 und 23:03 am 14.11., mit +120 min 23:53 am 14.11. und 00:03 am 15.11.
        $late = @((New-Ev -20), (New-Ev -10))
        @((Get-Lb (New-LbModel2 $late)).PerDay | ForEach-Object { '{0}:{1}' -f $_.Day, $_.Count }) | Should -Be @('2023-11-14:2')
        $l = Get-Lb (New-LbModel2 $late @{ OffsetMinutes = 120; EventLookbackDays = 7; LookbackCapped = @() })
        @($l.PerDay | ForEach-Object { '{0}:{1}' -f $_.Day, $_.Count }) | Should -Be @('2023-11-14:1', '2023-11-15:1')
    }
    It 'nennt im Umkreis alle Ereignisse in zeitlicher Folge, Grenzen eingeschlossen, nur vor der Messung' {
        $evs = @((New-Ev -105.0001), (New-Ev -105), (New-Ev -90 'logon' '' 3 'user002' '' @{ Group = 'session' }), (New-Ev -75), (New-Ev -74.99))
        $near = @((Get-Lb (New-LbModel2 $evs) ($T0 - 90 * 60000)).Near)
        @($near | ForEach-Object { [long]$_.TimeMs }) | Should -Be @([long]($T0 - 105 * 60000), [long]($T0 - 90 * 60000), [long]($T0 - 75 * 60000))
        @((Get-Lb (New-LbModel2 $evs) $T0).Near).Count | Should -Be 0 -Because 'die gemeldete Zeit liegt nicht vor dem ersten Takt'
    }
    It 'prueft im Rueckblick nur die Muster ohne Messwerte' {
        $hang = New-Ev -11 'hang' -Module ''
        $l = Get-Lb (New-LbModel2 @($hang, (New-Ev -10), (New-Ev -10 -App 'WINWORD.EXE' -User 'user003' -Sid 4 -Module 'vbe7.dll')))
        $excel = @($l.Incidents | Where-Object { $_.Kind -eq 'crash' -and $_.App -eq 'EXCEL.EXE' })[0]
        @($excel.Patterns | ForEach-Object Id) | Should -Be @('afterhang', 'sharedmodule')
        foreach ($i in @($l.Incidents)) { @($i.Overlap).Count | Should -Be 0; @($i.Patterns | Where-Object { $_.Id -in 'resource', 'overlap' }).Count | Should -Be 0 }
    }
    It 'nennt Datum und Uhrzeit fuer Vorfaelle vor der Messung, die der Messzeit bleiben unveraendert' {
        $one = (Get-Inc @(New-Ev 0) -Before)[0]
        Get-Text $one 60 | Should -Match '^14\.11\.2023 23:13:20: Absturz von EXCEL\.EXE \(1-mal\)\.'
        $day = (Get-Inc @((New-Ev 0), (New-Ev 10)) -Before)[0]
        Get-Text $day 60 | Should -Match ('^14\.11\.2023 23:13:20' + [char]0x2013 + '23:23:20: Absturz von EXCEL\.EXE \(2-mal\)\.')
        $two = (Get-Inc @((New-Ev 0), (New-Ev 25), (New-Ev 50)) -Before)[0]
        Get-Text $two 60 | Should -Match ('^14\.11\.2023 23:13:20' + [char]0x2013 + '15\.11\.2023 00:03:20: Absturz von EXCEL\.EXE \(3-mal\)\.')
        $now = (Get-Inc @((New-Ev 0), (New-Ev 25), (New-Ev 50)))[0]
        Get-Text $now 60 | Should -Match ('^23:13:20' + [char]0x2013 + '00:03:20: Absturz von EXCEL\.EXE \(3-mal\)\.')
        Get-Text (Get-Inc @(New-Ev 0))[0] 60 | Should -Match '^23:13:20: Absturz'
    }
    It 'liefert Treiber, Warteschlangen und Druckprozesse auch mit Luecken' {
        $m = @{ PrintDrivers = @(@{ Name = 'B Drv'; Manufacturer = 'M'; Version = '1'; Type = 4; Isolation = 'shared'; Files = [string[]]@('b.dll') })
            PrintQueues = @(@{ TimeMs = $T0; Queue = 'Q2'; Jobs = [double]::NaN; JobErrors = 4; NotReadyErrors = 1 }, @{ TimeMs = $T0; Queue = 'q1'; Jobs = 2; JobErrors = 0; NotReadyErrors = 0 },
                @{ TimeMs = $T0 + 15000; Queue = 'Q2'; Jobs = 1; JobErrors = [double]::NaN; NotReadyErrors = 3 }, @{ TimeMs = $T0 + 30000; Queue = 'Q2'; Jobs = 0; JobErrors = 6; NotReadyErrors = 1 },
                @{ TimeMs = $T0 + 45000; Queue = 'Q2'; Jobs = 0; JobErrors = 7; NotReadyErrors = 2 })
            Proc = @($null, @{ K = 1; Name = 'splwow64.exe'; Role = 'Drucken'; CpuMaxPct = 0.5; WsMaxKB = 1536 }, @{ K = 2; Name = 'spoolsv.exe'; Role = 'Drucken'; CpuMaxPct = 2; WsMaxKB = 2048 }) }
        $s = Get-WorkerPerfPrintState -Model $m -EventIncidents @()
        $d = $s.Drivers[0]; '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}' -f $d.Name, $d.Manufacturer, $d.Version, $d.Type, $d.Isolation, $d.Isolated, (@($d.Files) -join ';'), $d.Involved | Should -Be 'B Drv|M|1|4|shared|False|b.dll|False'
        @($s.Queues | ForEach-Object { '{0}:{1}:{2}:{3}' -f $_.Name, $_.MaxJobs, $_.JobErrors, $_.NotReadyErrors }) | Should -Be @('q1:2:0:0', 'Q2:1:3:4')   # 4 -> (fehlt) -> 6 -> 7; 1 -> 3, Neustart auf 1 (+1), 1 -> 2
        @($s.Processes | ForEach-Object { '{0}:{1}:{2}:{3}' -f $_.K, $_.Name, [string]$_.CpuMaxPct, [string]$_.WsMaxMB }) | Should -Be @('1:splwow64.exe:0.5:1.5', '2:spoolsv.exe:2:2')
        $e = Get-WorkerPerfPrintState -Model @{ Meta = @{} } -EventIncidents $null
        @($e.Drivers).Count | Should -Be 0; @($e.Queues).Count | Should -Be 0; @($e.Processes).Count | Should -Be 0
        $n = Get-WorkerPerfPrintState -Model @{ PrintQueues = @(@{ TimeMs = $T0; Queue = 'Q'; Jobs = [double]::NaN; JobErrors = [double]::NaN; NotReadyErrors = [double]::NaN }) } -EventIncidents @()
        $null -eq $n.Queues[0].MaxJobs | Should -BeTrue; $n.Queues[0].JobErrors | Should -Be 0
    }
    It 'nennt einen Treiber beteiligt nur als Schluessel oder einzigen Treiber eines Musters, mehrere als moeglich' {
        $drv = @(@{ Name = 'HP A'; Manufacturer = 'HP'; Version = '1'; Type = 3; Isolation = 'none'; Files = @('unidrv.dll', 'hpa.dll') },
            @{ Name = 'Kyo B'; Manufacturer = 'Kyocera'; Version = '2'; Type = 3; Isolation = 'none'; Files = @('UNIDRV.DLL', 'kyob.dll') },
            @{ Name = 'Xer C'; Manufacturer = 'Xerox'; Version = '3'; Type = 4; Isolation = 'isolated'; Files = @('xerc.dll') })
        $show = { param($s) @($s.Drivers | ForEach-Object { '{0}:{1}:{2}' -f $_.Name, $_.Involved, $_.PossiblyInvolved }) }
        $shared = @(New-WorkerPerfEventIncidents -Events @(New-Ev 0 -App 'spoolsv.exe' -Sid 0 -User '' -Module 'unidrv.dll') -Config $Cfg -Settings $Set -Drivers $drv -FirstId 1)
        Add-WorkerPerfEventPatterns -Incidents $shared -AllEvents @($shared[0].Events) -Model $null -Thresholds $Th -Settings $Set -Config $Cfg -Roles $Roles -Drivers $drv -PerfIncidents @() -Before
        & $show (Get-WorkerPerfPrintState -Model @{ PrintDrivers = $drv } -EventIncidents $shared) | Should -Be @('HP A:False:True', 'Kyo B:False:True', 'Xer C:False:False')
        # Schluessel ohne Beachtung der Gross- und Kleinschreibung; Muster printdriver mit einem Treiber auch an einem Absturz in einer Sitzung
        $crash = @{ Kind = 'crash'; Key = 'EXCEL.EXE'; Patterns = @(@{ Id = 'printdriver'; Detail = @{ Module = 'xerc.dll'; Driver = 'Xer C'; Drivers = [string[]]@('Xer C') } }) }
        & $show (Get-WorkerPerfPrintState -Model @{ PrintDrivers = $drv } -EventIncidents @(@{ Kind = 'print'; Key = 'kyo b'; Patterns = @() }, $crash)) | Should -Be @('HP A:False:False', 'Kyo B:True:False', 'Xer C:True:False')
        # ein Drucker als Schluessel macht keinen Treiber beteiligt; beteiligt geht vor moeglich
        & $show (Get-WorkerPerfPrintState -Model @{ PrintDrivers = $drv } -EventIncidents @(@{ Kind = 'print'; Key = 'PRN-1'; Patterns = @() }, @{ Kind = 'print'; Key = 'HP A'; Patterns = @() }, $shared[0])) |
            Should -Be @('HP A:True:False', 'Kyo B:False:True', 'Xer C:False:False')
    }
}
Describe 'Kleine Korrekturen aus der Pruefung von Task 6' {
    It 'N1: Kopftexte ohne Anwendungsnamen und afterhang bei einem Teil der Abstuerze' {
        $Texts.ContainsKey('event.app.unknown') | Should -BeFalse
        Get-Text (Get-PatInc @(New-Ev 0 -App ''))[0] | Should -Match '^\d\d:\d\d:\d\d: Absturz einer unbekannten Anwendung \(1-mal\)\. Benutzer: user002\.'
        Get-Text (Get-PatInc @((New-Ev 0 'hang' -App '' -Module ''), (New-Ev 1 'hang' -App '' -Module '')))[0] | Should -Match ('^\d\d:\d\d:\d\d' + [char]0x2013 + '\d\d:\d\d:\d\d: Eine unbekannte Anwendung reagierte nicht und wurde beendet \(2-mal\)\.')
        $c = @((Get-PatInc @((New-Ev 0), (New-Ev 5), (New-Ev 9.5 'hang' -Module ''), (New-Ev 10))) | Where-Object { $_.Kind -eq 'crash' })[0]
        Get-Text $c | Should -Match ' Nach Nichtreagieren beendet: 1 von 3\. '
    }
    It 'N3: der Rest einer gekuerzten Liste passt nach jedem Fall' {
        $perf = @(1..13 | ForEach-Object { @{ Id = $_; StartMs = $T0; EndMs = $T0 + 60000 } })
        Get-Text (Get-PatInc @(New-Ev 0) -Perf $perf)[0] | Should -Match ' Zeitgleich mit den Vorfällen 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 \(\+3 weitere\)\.$'
        $evs = @(1..40 | ForEach-Object { New-Ev ($_ / 10) -Sid (10 + $_) -User ('user{0:d3}' -f $_) })
        Get-Text (Get-PatInc $evs)[0] | Should -Match ' Benutzer: user001, user002, .*, user010 \(\+30 weitere\)\. '
    }
    It 'N2: gleichzeitige Begleitereignisse derselben Gruppe und Art stehen nach Quelle und Objekt' {
        $d = New-Ev 11 'system' '' 0 '' '' @{ Group = 'storage'; Source = 'disk'; Object = 'D:' }; $e = New-Ev 11 'system' '' 0 '' '' @{ Group = 'storage'; Source = 'disk'; Object = 'E:' }
        $n = New-Ev 11 'system' '' 0 '' '' @{ Group = 'storage'; Source = 'Ntfs'; Object = 'C:' }
        $clock = Format-WorkerPerfClock ([long]($T0 + 11 * 60000)) 0
        $want = [regex]::Escape(" Zeitnah: $clock Datenträgerfehler C:, $clock Datenträgerfehler D:, $clock Datenträgerfehler E:.")
        foreach ($order in @(@((New-Ev 10), $d, $e, $n), @($e, $n, $d, (New-Ev 10)), @($n, $e, (New-Ev 10), $d))) {
            $i = @((Get-PatInc $order) | Where-Object { $_.Kind -eq 'crash' })[0]
            Get-Text $i | Should -Match $want
        }
    }
    It 'N4: (n von m) zaehlt nur Ereignisse, die ein Modul tragen koennen' {
        $stop = New-Ev 0.1 'service' '' 0 '' '' @{ Service = 'Spooler'; Group = 'service'; Source = 'Service Control Manager'; EventId = 7034; Code = ''; Module = '' }
        $i = (Get-PatInc @((New-Ev 0 -App 'spoolsv.exe' -Sid 0 -User '' -Module 'hpsimgr.dll'), $stop))[0]
        $i.Count | Should -Be 2; $i.SameModule | Should -BeTrue
        Get-Text $i | Should -Match ': Druckproblem – Sim PCL 6 \(2-mal\)\. Ohne Benutzersitzung\. Fehlerhaftes Modul: hpsimgr\.dll, immer dasselbe\. '
        $j = (Get-PatInc @((New-Ev 0 -App 'spoolsv.exe' -Sid 0 -User '' -Module 'hpsimgr.dll'), (New-Ev 0.05 -App 'spoolsv.exe' -Sid 0 -User '' -Module '' -More @{ Driver = 'Sim PCL 6' }), $stop))[0]
        $j.SameModule | Should -BeFalse; Get-Text $j | Should -Match 'Fehlerhaftes Modul: hpsimgr\.dll \(1 von 2\)\.'
    }
    It 'N5: ein Namensmuster braucht einen Buchstaben oder eine Ziffer' {
        $f = Join-Path $TestDrive 'n5.json'; $base = '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"P","ids":[1],"group":"app","kind":"crash"}]'
        foreach ($field in 'noModules', 'systemModules', 'nonPersonAccounts') {
            foreach ($bad in '*.*', '*', '.*', '*-*', '*.') {
                [IO.File]::WriteAllText($f, $base + ',"' + $field + '":["x.dll","' + $bad + '"]}')
                { Read-WorkerPerfEventConfig $f } | Should -Throw "*Feld '$field'*('$bad')*" -Because "$field $bad"
            }
            [IO.File]::WriteAllText($f, $base + ',"' + $field + '":["*.dll","a*","*1*"]}'); { Read-WorkerPerfEventConfig $f } | Should -Not -Throw
        }
        [IO.File]::WriteAllText($f, $base + ',"nonPersonAccounts":["*$"]}'); @((Read-WorkerPerfEventConfig $f).NonPersonAccounts) | Should -Be @('*$')
    }
}
Describe 'Pruefung von Task 7, Runde 1' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/WorkerPerf.Load.ps1')
        function Read-Rows([string[]]$Rows) {
            $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n')); [void](New-Item -ItemType Directory -Path $dir)
            [IO.File]::WriteAllLines((Join-Path $dir 'events_before.csv'), @($WorkerPerfHeaders['events.csv']) + $Rows)
            , @(Read-WorkerPerfEventCsv $dir 'events_before.csv' ([ref]0))
        }
        function New-Row([string]$Ts, [string]$App = 'EXCEL.EXE', [string]$User = 'user002', [string]$Group = 'app', [string]$Kind = 'crash', [string]$Object = '') {
            "$Ts,application,Application Error,1000,2,$Group,$Kind,$App,16.0,vbe7.dll,,0xc0000005,812,3,$User,,,,$Object,x"
        }
        function Get-LbAt([object[]]$Records, [int]$Offset, [string]$FirstTick = '2026-11-12T10:00:00+00:00') {
            $first = [DateTimeOffset]::Parse($FirstTick, [cultureinfo]::InvariantCulture).ToUnixTimeMilliseconds()
            $m = @{ EventsBefore = $Records; Tick = @{ TimeMs = [long[]]@($first) }; Meta = @{ OffsetMinutes = $Offset; EventLookbackDays = 7; LookbackCapped = @() } }
            Get-WorkerPerfLookback -Model $m -Config $Cfg -Settings $Set -Roles $Roles -FirstId 1 -ReportedMs $null
        }
        function Get-LbText($Incident, [int]$Offset) { Get-WorkerPerfEventIncidentText -Incident $Incident -Model $null -Texts $Texts -Config $Cfg -OffsetMinutes $Offset }
    }
    It 'I1: jedes Ereignis behaelt den Zeitversatz seines Zeitstempels, ohne Versatz gilt der der Messung' {
        $r = Read-Rows @((New-Row '2026-11-07T00:30:00+01:00'), (New-Row '2026-11-07T03:30:00Z'), (New-Row '2026-11-07T04:30:00-05:30'), (New-Row '2026-11-07T05:30:00'))
        @($r | ForEach-Object { if ($null -eq $_.OffsetMinutes) { 'null' } else { [string]$_.OffsetMinutes } } | Sort-Object) | Should -Be @('-330', '0', '60', 'null')   # Reihenfolge nach Zeit haengt von der Zone der Maschine ab
        $l = Get-LbAt @($r[0]) 0
        @($l.PerDay | ForEach-Object { '{0}:{1}' -f $_.Day, $_.Count }) | Should -Be @('2026-11-07:1')
        Get-LbText $l.Incidents[0] 0 | Should -Match '^07\.11\.2026 00:30:00: Absturz von EXCEL\.EXE \(1-mal\)\.'
        # ohne Versatz im Zeitstempel: der Versatz der Messung
        $n = @{ TimeMs = [DateTimeOffset]::Parse('2026-11-07T00:30:00Z').ToUnixTimeMilliseconds() } + @{}
        foreach ($k in $r[0].Keys) { if ($k -ne 'TimeMs') { $n[$k] = $r[0][$k] } }; $n['OffsetMinutes'] = $null
        Get-LbText (Get-LbAt @($n) 120).Incidents[0] 120 | Should -Match '^07\.11\.2026 02:30:00: '
    }
    It 'I1: ein Rueckblick ueber das Ende der Sommerzeit zeigt jedes Ereignis in der Ortszeit seines Tages' {
        # Ende der Sommerzeit am 25.10.2026 um 03:00 MESZ; die Messung laeuft in MEZ (+60)
        $r = Read-Rows @((New-Row '2026-10-24T00:30:00+02:00' -App 'a.exe'), (New-Row '2026-10-24T12:00:00+02:00' -App 'b.exe'), (New-Row '2026-10-26T00:30:00+01:00' -App 'c.exe'), (New-Row '2026-10-26T12:00:00+01:00' -App 'd.exe'))
        $l = Get-LbAt $r 60
        @($l.PerDay | ForEach-Object { '{0}:{1}' -f $_.Day, $_.Count }) | Should -Be @('2026-10-24:2', '2026-10-26:2')
        @($l.Incidents | ForEach-Object { (Get-LbText $_ 60).Substring(0, 19) }) | Should -Be @('24.10.2026 00:30:00', '24.10.2026 12:00:00', '26.10.2026 00:30:00', '26.10.2026 12:00:00')
    }
    It 'I1: eine Spanne, deren Enden verschiedene Versaetze haben, nennt jedes Ende in seiner Ortszeit' {
        # 02:50 MESZ = 00:50 UTC, 02:10 MEZ = 01:10 UTC: 20 Minuten spaeter, ein Vorfall
        $r = Read-Rows @((New-Row '2026-10-25T02:50:00+02:00'), (New-Row '2026-10-25T02:10:00+01:00'))
        $l = Get-LbAt $r 60
        @($l.Incidents).Count | Should -Be 1
        Get-LbText $l.Incidents[0] 60 | Should -Match ('^25\.10\.2026 02:50:00' + [char]0x2013 + '02:10:00: Absturz von EXCEL\.EXE \(2-mal\)\.')
        $s = Read-Rows @((New-Row '2026-10-25T23:50:00+01:00'), (New-Row '2026-10-26T00:10:00+01:00'))
        Get-LbText (Get-LbAt $s 0).Incidents[0] 0 | Should -Match ('^25\.10\.2026 23:50:00' + [char]0x2013 + '26\.10\.2026 00:10:00: ')
        # in der Messzeit ebenfalls je Ende der eigene Versatz, ohne Datum
        $now = @(New-WorkerPerfEventIncidents -Events $r -Config $Cfg -Settings $Set -Drivers @() -FirstId 1)
        Get-LbText $now[0] 0 | Should -Match ('^02:50:00' + [char]0x2013 + '02:10:00: Absturz')
    }
    It 'M1: die Fehlermeldung eines Namensmusters nennt, was erlaubt ist' {
        $f = Join-Path $TestDrive 'm1.json'
        [IO.File]::WriteAllText($f, '{"logs":[{"id":"a","names":["A"],"lookback":true}],"events":[{"log":"a","provider":"P","ids":[1],"group":"app","kind":"crash"}],"noModules":["*.*"]}')
        { Read-WorkerPerfEventConfig $f } | Should -Throw "*mindestens einem Buchstaben, einer Ziffer oder '$'*"
    }
    It 'M2: ein Begleitereignis an einem anderen Tag nennt im Rueckblick sein Datum' {
        $r = Read-Rows @((New-Row '2026-11-01T23:59:30+01:00'), (New-Row '2026-11-02T00:00:30+01:00' -App '' -User '' -Group 'storage' -Kind 'system' -Object 'D:'),
            (New-Row '2026-11-03T10:00:00+01:00' -App 'w.exe'), (New-Row '2026-11-03T10:01:00+01:00' -App '' -User '' -Group 'storage' -Kind 'system' -Object 'E:'))
        $l = Get-LbAt $r 60
        $a = @($l.Incidents | Where-Object { $_.App -eq 'EXCEL.EXE' })[0]; $b = @($l.Incidents | Where-Object { $_.App -eq 'w.exe' })[0]
        Get-LbText $a 60 | Should -Match ([regex]::Escape(' Zeitnah: 02.11.2026 00:00:30 Datenträgerfehler D:.'))
        Get-LbText $b 60 | Should -Match ([regex]::Escape(' Zeitnah: 10:01:00 Datenträgerfehler E:.'))
        # in der Messzeit bleibt es die Uhrzeit
        $c = (Get-PatInc @((New-Ev 0), (New-Ev 1 'system' '' 0 '' '' @{ Group = 'storage'; Source = 'disk'; Object = 'D:' })))[0]
        Get-Text $c (24 * 60 - 1) | Should -Match ' Zeitnah: \d\d:\d\d:\d\d Datenträgerfehler D:\.'
    }
    It 'M6: SameModule ist falsch ohne echtes Modul' {
        $stop = New-Ev 0.1 'service' '' 0 '' '' @{ Service = 'Spooler'; Group = 'service'; Source = 'Service Control Manager'; EventId = 7034; Code = ''; Module = '' }
        (Get-Inc @((New-Ev 0 -App 'spoolsv.exe' -Sid 0 -User '' -Module 'unknown' -More @{ Driver = 'Sim PCL 6' }), $stop))[0].SameModule | Should -BeFalse
        (Get-Inc @((New-Ev 0 -Module 'StackHash_1a2b'), (New-Ev 1 -Module 'StackHash_1a2b')))[0].SameModule | Should -BeFalse
        (Get-Inc @((New-Ev 0), (New-Ev 1)))[0].SameModule | Should -BeTrue
    }
}
Describe 'Abschlussrunde: Sitzung, Ursachen und Treiber nur, soweit die Daten sie tragen' {
    BeforeAll {
        function Get-BeforeText([object[]]$Events) {
            $inc = Get-Inc $Events -Before
            Add-WorkerPerfEventPatterns -Incidents $inc -AllEvents $Events -Model $null -Thresholds $Th -Settings $Set -Config $Cfg -Roles $Roles -Drivers $Drv -PerfIncidents $null -Before
            , @($inc | ForEach-Object { Get-Text $_ })
        }
        # a crash as the classic Application Error 1000 of the lookback writes it: no session number, no account
        function New-Bare([double]$Min, [string]$App = 'simtool.exe', [string]$Kind = 'crash') { New-Ev $Min $Kind $App -1 '' 'simtool.dll' @{ SessionIndex = -1 } }
    }
    It 'C1: bildet im Rueckblick aus einem Absturz mit unbekannter Sitzung einen Vorfall und sagt "Sitzung nicht ermittelt"' {
        $i = Get-Inc @(New-Bare 0) -Before
        $i.Count | Should -Be 1; $i[0].Severity | Should -Be 1; $i[0].SessionUnknown | Should -BeTrue; $i[0].NoUserSession | Should -BeFalse
        $t = (Get-BeforeText @(New-Bare 0))[0]
        $t | Should -Match ': Absturz von simtool\.exe \(1-mal\)\. Sitzung nicht ermittelt\. Fehlerhaftes Modul: simtool\.dll'
        $t | Should -Not -Match 'Ohne Benutzersitzung'
        (Get-Inc @(New-Bare 0 -Kind 'hang') -Before).Count | Should -Be 1
    }
    It 'C1: fasst Abstuerze mit unbekannter Sitzung je Anwendung zusammen wie die anderen' {
        $i = Get-Inc @((New-Bare 0), (New-Bare 20), (New-Bare 25 'anders.exe'), (New-Bare 300)) -Before
        @($i | ForEach-Object { $_.App + ':' + $_.Count }) | Should -Be @('simtool.exe:2', 'anders.exe:1', 'simtool.exe:1')
    }
    It 'C1: laesst in der Messzeit den einzelnen Absturz ohne Sitzung weg und nennt bei zweien die unbekannte Sitzung' {
        (Get-Inc @(New-Bare 0)).Count | Should -Be 0
        $i = Get-PatInc @((New-Bare 0), (New-Bare 1))
        $i.Count | Should -Be 1; Get-Text $i[0] | Should -Match ': Absturz von simtool\.exe \(2-mal\)\. Sitzung nicht ermittelt\. '
    }
    It 'C1: sagt "Ohne Benutzersitzung" nur fuer Sitzung 0 und ueber ein Dienstkonto ohne Sitzungsnummer nichts' {
        Get-Text (Get-PatInc @((New-Ev 0 -App 'dienst.exe' -Sid 0 -User 'SYSTEM'), (New-Ev 1 -App 'dienst.exe' -Sid 0 -User 'SYSTEM')))[0] | Should -Match ' \(2-mal\)\. Ohne Benutzersitzung\. '
        $sys = Get-PatInc @((New-Ev 0 -App 'dienst.exe' -Sid -1 -User 'SYSTEM' -More @{ SessionIndex = -1 }), (New-Ev 1 -App 'dienst.exe' -Sid -1 -User 'SYSTEM' -More @{ SessionIndex = -1 }))
        $t = Get-Text $sys[0]; $t | Should -Not -Match 'Ohne Benutzersitzung'; $t | Should -Not -Match 'Sitzung nicht ermittelt'
        (Get-Inc @(New-Ev 0 -App 'dienst.exe' -Sid -1 -User 'SYSTEM' -More @{ SessionIndex = -1 }) -Before).Count | Should -Be 0
        # a system event without session number and account: no statement about a session
        Get-Text (Get-PatInc @(New-Ev 0 'system' '' -1 '' '' @{ Group = 'storage'; Source = 'disk'; Object = 'D:'; Code = ''; Module = ''; SessionIndex = -1 }))[0] | Should -Match ': Systemfehler – Datenträgerfehler D: \(1-mal\)\. Kein Muster erkannt\.$'
        # a crash with a session and a crash with an unknown one: the users are named, nothing about the unknown session
        $mix = Get-PatInc @((New-Ev 0 -App 'simtool.exe'), (New-Bare 1))
        Get-Text $mix[0] | Should -Match ' Benutzer: user002\. '
    }
    It 'C1: gibt die Sitzungslage in die Berichtsdaten' {
        $o = ConvertTo-WorkerPerfEventIncidentOut -Incident (Get-Inc @(New-Bare 0) -Before)[0] -Text 'x' -Focus $false -Near $false -Texts $Texts -OffsetMinutes 0
        $o.event.sessionUnknown | Should -BeTrue; $o.event.noUserSession | Should -BeFalse
        $z = ConvertTo-WorkerPerfEventIncidentOut -Incident (Get-PatInc @(New-Ev 0 -App 'spoolsv.exe' -Sid 0 -User '' -Module 'hpsimgr.dll'))[0] -Text 'x' -Focus $false -Near $false -Texts $Texts -OffsetMinutes 0
        $z.event.sessionUnknown | Should -BeFalse; $z.event.noUserSession | Should -BeTrue
    }
    It 'I2: overlap nur, wenn ein Ereignis des Vorfalls im Fenster des Leistungsvorfalls liegt' {
        $perf = @(@{ Id = 1; StartMs = $T0 + 20 * 60000; EndMs = $T0 + 25 * 60000 }, @{ Id = 2; StartMs = $T0 + 49 * 60000; EndMs = $T0 + 51 * 60000 })
        $i = (Get-PatInc @((New-Ev 0), (New-Ev 25.5), (New-Ev 50)) -Perf $perf)[0]
        $i.Count | Should -Be 3; $i.Overlap | Should -Be @(2); $perf[0].EventIncidents.Count | Should -Be 0; $perf[1].EventIncidents | Should -Be @($i.Id)
    }
    It 'I2: resource nur bei Absturz, Haenger, Dienst und Druckproblem eines Prozesses' {
        $mem = New-PatternModel (@(95) * 60)
        (Get-Pat @(New-Ev 10 'profileerror' '' 3 'user002' '' @{ Group = 'profile'; Source = 'Citrix Profile Management'; Code = ''; Module = '' }) $mem)[0] | Should -Not -Contain 'resource'
        (Get-Pat @(New-Ev 10 'system' '' -1 '' '' @{ Group = 'storage'; Source = 'disk'; Object = 'D:'; Code = ''; Module = '' }) $mem)[0] | Should -Not -Contain 'resource'
        (Get-Pat @(New-Ev 10 'print' '' -1 '' '' @{ Group = 'print'; Source = 'Microsoft-Windows-PrintService'; EventId = 215; Driver = 'Sim Neu'; Code = ''; Module = '' }) $mem)[0] | Should -Not -Contain 'resource'
        (Get-Pat @(New-Ev 10) $mem)[0] | Should -Contain 'resource'
        (Get-Pat @(New-Ev 10 'hang' -Module '') $mem)[0] | Should -Contain 'resource'
        (Get-Pat @(New-Ev 10 'service' '' 0 '' '' @{ Service = 'BrokerAgent'; Group = 'service'; Code = ''; Module = '' }) $mem)[0] | Should -Contain 'resource'
        (Get-Pat @(New-Ev 10 -App 'spoolsv.exe' -Sid 0 -User '' -Module 'hpsimgr.dll') $mem)[0] | Should -Contain 'resource'
    }
    It 'I2: sagt "wahrscheinlich" nur, wenn der Fehlercode selbst Speichermangel sagt, und nennt sonst den Anteil' {
        $mem = New-PatternModel (@(50) * 4 + @(95) * 3 + @(50) * 53)
        Get-Text (Get-PatInc @(New-Ev 10 -More @{ Code = '0xc0000017' }) $mem)[0] | Should -Match ' Wahrscheinlich Folge des Speichermangels\.'
        $t = Get-Text (Get-PatInc @(New-Ev 10) $mem)[0]
        $t | Should -Match ' Kann Folge des Speichermangels sein\.'; $t | Should -Not -Match 'Wahrscheinlich'
        $some = (Get-PatInc @((New-Ev 10), (New-Ev 30)) $mem)[0]
        $some.Patterns[0].Detail.Count | Should -Be 1; $some.Patterns[0].Detail.Total | Should -Be 2
        Get-Text $some | Should -Match ' 1 von 2 bei Speichermangel: kann Folge davon sein\.'
        Get-Text (Get-PatInc @((New-Ev 10 -More @{ Code = '0xc0000017' }), (New-Ev 30)) $mem)[0] | Should -Match ' 1 von 2 bei Speichermangel: wahrscheinlich Folge davon\.'
        $o = ConvertTo-WorkerPerfEventIncidentOut -Incident $some -Text 'x' -Focus $false -Near $false -Texts $Texts -OffsetMinutes 0
        $o.event.patterns[0].text | Should -Be '1 von 2 bei Speichermangel: kann Folge davon sein.'
        $o.event.patterns[0].detail.total | Should -Be 2; $o.event.patterns[0].detail.memoryCode | Should -BeFalse
    }
    It 'M11: nennt neben resource das gemeinsame Modul mit "spricht fuer"' {
        $mem = New-PatternModel (@(95) * 60)
        $evs = @((New-Ev 10 -Module 'simaddin.dll'), (New-Ev 11 -App 'WINWORD.EXE' -Sid 4 -User 'user003' -Module 'simaddin.dll'))
        $t = Get-Text (Get-PatInc $evs $mem)[0]
        $t | Should -Match ' Kann Folge des Speichermangels sein\. Das Modul simaddin\.dll spricht für eine gemeinsame Ursache \(betrifft EXCEL\.EXE, WINWORD\.EXE\)\.'
        $t | Should -Not -Match 'Ursache liegt wahrscheinlich'
        Get-Text (Get-PatInc $evs)[0] | Should -Match ' Ursache liegt wahrscheinlich im Modul simaddin\.dll'
    }
    It 'I4: ein Systemmodul in der Dateiliste eines Treibers macht weder Treiber noch Schutzsoftware beteiligt' {
        $drv = @(@{ Name = 'Sim KX'; Manufacturer = 'Sim'; Version = '1.0'; Type = 3; Isolation = 'isolated'; Files = @('kxsim.dll', 'vcruntime140.dll') })
        $roles = @([pscustomobject]@{ role = 'Sicherheit'; label = 'Sim Schutz'; modules = @('ntdll.dll', 'simguard.dll') })
        $one = { param($evs)
            $inc = @(New-WorkerPerfEventIncidents -Events $evs -Config $Cfg -Settings $Set -Drivers $drv -FirstId 1)
            Add-WorkerPerfEventPatterns -Incidents $inc -AllEvents $evs -Model (New-PatternModel (@(50) * 60)) -Thresholds $Th -Settings $Set -Config $Cfg -Roles $roles -Drivers $drv -PerfIncidents @()
            , $inc }
        $i = & $one @(New-Ev 0 -App 'tabelle.exe' -Module 'VCRUNTIME140.dll')
        @($i[0].Patterns | ForEach-Object { $_.Id }) | Should -Not -Contain 'printdriver'
        $ps = Get-WorkerPerfPrintState -Model @{ PrintDrivers = $drv; PrintQueues = @(); Processes = @() } -EventIncidents $i
        @($ps.Drivers | Where-Object { $_.Involved -or $_.PossiblyInvolved }).Count | Should -Be 0
        # a crash of the spooler in a runtime module names no driver: the print problem is keyed by its source
        $s = & $one @(New-Ev 0 -App 'spoolsv.exe' -Sid 0 -User '' -Module 'vcruntime140.dll')
        $s[0].Kind | Should -Be 'print'; $s[0].Driver | Should -Be ''; @($s[0].Patterns | ForEach-Object { $_.Id }) | Should -Not -Contain 'printdriver'
        (& $one @(New-Ev 0 -App 'spoolsv.exe' -Sid 0 -User '' -Module 'kxsim.dll'))[0].Driver | Should -Be 'Sim KX'
        @((& $one @(New-Ev 0 -Module 'ntdll.dll'))[0].Patterns | ForEach-Object { $_.Id }) | Should -Not -Contain 'securitymodule'
        @((& $one @(New-Ev 0 -Module 'simguard.dll'))[0].Patterns | ForEach-Object { $_.Id }) | Should -Contain 'securitymodule'
    }
    It 'trennt Benutzer und Domaene unter jeder Kultur' {
        $old = [cultureinfo]::CurrentCulture
        try {
            [cultureinfo]::CurrentCulture = [cultureinfo]'th-TH'
            Test-WorkerPerfEventPersonUser 'KLINIK\SYSTEM' $Cfg | Should -BeFalse
            Test-WorkerPerfEventPersonUser 'KLINIK\user005' $Cfg | Should -BeTrue
        }
        finally { [cultureinfo]::CurrentCulture = $old }
    }
}
