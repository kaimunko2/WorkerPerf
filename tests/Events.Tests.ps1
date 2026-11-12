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
}
Describe 'events.json' {
    It 'fuehrt jede Kennung zu Gruppe und Art' {
        foreach ($e in $Cfg.Entries) { foreach ($id in $e.ids) {
            $r = Resolve-WorkerPerfEventEntry $Cfg $e.log $e.provider $id
            $r.group | Should -Be $e.group; $r.kind | Should -Be $e.kind } }
        (Resolve-WorkerPerfEventEntry $Cfg 'application' 'application error' 1000).kind | Should -Be 'crash'
        Resolve-WorkerPerfEventEntry $Cfg 'application' 'Application Error' 1001 | Should -BeNullOrEmpty
        (Resolve-WorkerPerfEventEntry $Cfg 'defender' 'Microsoft-Windows-Windows Defender' 1002).kind | Should -Be 'scan-end'
        $Cfg.Logs['session'].Lookback | Should -BeFalse; $Cfg.ErrorCodes['0xc0000005'] | Should -Be 'Zugriffsverletzung'
    }
    It 'liest die Listen und die Namen der Protokolle' {
        @($Cfg.Logs['applocker'].Names).Count | Should -Be 2
        @($Cfg.ImportantServices) | Should -Contain 'Spooler'
        @($Cfg.PrintServices) | Should -Be @('Spooler')
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
        $r.App | Should -Be ''; $r.Pid | Should -BeNullOrEmpty; $r.Kind | Should -Be 'crash'; $r.Text | Should -Be ''
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
        @{ Log = 'application'; Provider = 'Application Error'; Id = 1000; Group = 'app'; Kind = 'crash'; Fields = 'app=AppName;appVersion=AppVersion;module=ModuleName;moduleVersion=ModuleVersion;code=ExceptionCode;pid=ProcessId/hex' }
        @{ Log = 'application'; Provider = 'Application Hang'; Id = 1002; Group = 'app'; Kind = 'hang'; Fields = 'app=#0;appVersion=#1;pid=#2/hex' }
        @{ Log = 'application'; Provider = '.NET Runtime'; Id = 1026; Group = 'app'; Kind = 'app-detail'; Fields = '' }
        @{ Log = 'application'; Provider = 'Windows Error Reporting'; Id = 1001; Group = 'app'; Kind = 'app-detail'; Fields = '' }
        @{ Log = 'session'; Provider = 'Microsoft-Windows-TerminalServices-LocalSessionManager'; Id = 21; Group = 'session'; Kind = 'logon'; Fields = 'user=User;session=SessionID' }
        @{ Log = 'session'; Provider = 'Microsoft-Windows-TerminalServices-LocalSessionManager'; Id = 23; Group = 'session'; Kind = 'logoff'; Fields = 'user=User;session=SessionID' }
        @{ Log = 'session'; Provider = 'Microsoft-Windows-TerminalServices-LocalSessionManager'; Id = 24; Group = 'session'; Kind = 'disconnect'; Fields = 'user=User;session=SessionID' }
        @{ Log = 'session'; Provider = 'Microsoft-Windows-TerminalServices-LocalSessionManager'; Id = 25; Group = 'session'; Kind = 'reconnect'; Fields = 'user=User;session=SessionID' }
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
        @{ Log = 'smbclient'; Provider = 'Microsoft-Windows-SMBClient'; Id = 30803; Group = 'fileserver'; Kind = 'system'; Fields = 'object=ServerName' }
        @{ Log = 'smbclient'; Provider = 'Microsoft-Windows-SMBClient'; Id = 30807; Group = 'fileserver'; Kind = 'system'; Fields = 'object=ServerName' }
        @{ Log = 'profileservice'; Provider = 'Microsoft-Windows-User Profiles Service'; Id = 1511; Group = 'profile'; Kind = 'profileerror'; Fields = '' }
        @{ Log = 'application'; Provider = 'Microsoft-Windows-User Profiles Service'; Id = 1533; Group = 'profile'; Kind = 'profileerror'; Fields = '' }
        @{ Log = 'defender'; Provider = 'Microsoft-Windows-Windows Defender'; Id = 1000; Group = 'security'; Kind = 'scan-start'; Fields = '' }
        @{ Log = 'defender'; Provider = 'Microsoft-Windows-Windows Defender'; Id = 1001; Group = 'security'; Kind = 'scan-end'; Fields = '' }
        @{ Log = 'defender'; Provider = 'Microsoft-Windows-Windows Defender'; Id = 1002; Group = 'security'; Kind = 'scan-end'; Fields = '' }
        @{ Log = 'defender'; Provider = 'Microsoft-Windows-Windows Defender'; Id = 2000; Group = 'security'; Kind = 'signature-update'; Fields = '' }
        @{ Log = 'applocker'; Provider = 'Microsoft-Windows-AppLocker'; Id = 8004; Group = 'security'; Kind = 'applocker-block'; Fields = '' }
        @{ Log = 'applocker'; Provider = 'Microsoft-Windows-AppLocker'; Id = 8007; Group = 'security'; Kind = 'applocker-block'; Fields = '' }
    ) {
        $e = Resolve-WorkerPerfEventEntry $Cfg $Log $Provider $Id
        $e | Should -Not -BeNullOrEmpty
        $e.group | Should -Be $Group; $e.kind | Should -Be $Kind
        $actual = @($e.fields.Keys | Sort-Object | ForEach-Object {
                $f = $e.fields[$_]; "$_=$($f.Field)" + $(if ($f.Format -eq 'hex') { '/hex' } else { '' }) }) -join ';'
        $expected = (@($Fields -split ';' | Where-Object { $_ } | Sort-Object) -join ';')
        $actual | Should -Be $expected
    }
    It 'hat genau die erwarteten Kennungen je Quelle' {
        $count = 0; foreach ($e in $Cfg.Entries) { $count += @($e.ids).Count }
        $count | Should -Be 45
        @((Resolve-WorkerPerfEventEntry $Cfg 'system' 'disk' 7), (Resolve-WorkerPerfEventEntry $Cfg 'system' 'disk' 153)) | ForEach-Object { $_.ids -join ',' } | Select-Object -Unique | Should -Be '7,11,51,153'
        (Resolve-WorkerPerfEventEntry $Cfg 'smbclient' 'Microsoft-Windows-SMBClient' 30805).ids -join ',' | Should -Be '30803,30804,30805,30806,30807'
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
    }
    It 'findet die Ereignisvorfaelle aus expected.json' {
        $show = { param($k, $app, $drv, $n, $u, $a, $b, $bf) '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}' -f $k, [string]$app, [string]$drv, $n, (@($u) -join '+'), $a, $b, $bf }
        @($SimInc | ForEach-Object { & $show $_.Kind $_.App $_.Driver $_.Count $_.Users $_.StartMs $_.EndMs $_.Before }) |
            Should -Be @($SimExp | ForEach-Object { & $show $_.Kind $_.App $_.Driver $_.Count $_.Users $_.StartMs $_.EndMs $_.Before })
        @($SimInc.Id) | Should -Be @(1..7)
    }
    It 'liefert bei zwei Laeufen dieselben Vorfaelle' {
        @($SimInc2 | ForEach-Object { '{0}:{1}:{2}:{3}' -f $_.Id, $_.Kind, $_.Key, $_.Count }) | Should -Be @($SimInc | ForEach-Object { '{0}:{1}:{2}:{3}' -f $_.Id, $_.Kind, $_.Key, $_.Count })
    }
    It 'gibt den Vorfaellen vor der Messung keine Sitzung der Messung' {
        $b = @($SimInc | Where-Object { $_.Before }); $b.Count | Should -Be 3
        foreach ($i in $b) { @($i.Sessions).Count | Should -Be 0; @($i.Users).Count | Should -Be 1 }
        foreach ($e in @($M.EventsBefore)) { $e.SessionIndex | Should -Be -1 }
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
