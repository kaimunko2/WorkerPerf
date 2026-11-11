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
