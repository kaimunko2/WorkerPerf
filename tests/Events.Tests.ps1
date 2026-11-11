BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.EventConfig.ps1')
    $script:Cfg = Read-WorkerPerfEventConfig (Join-Path $PSScriptRoot '../src/events.json')
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
