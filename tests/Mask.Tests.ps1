BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadHelpers.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Mask.ps1')
    $script:Texts = Read-WorkerPerfTexts (Join-Path $PSScriptRoot '../src/texts.de.json')
    $sess = @('0,0,,,Disconnected,Services,,,', '0,2,mueller,KLINIK,Active,ICA-1,WS-0001,,0', '0,3,MUELLER,KLINIK,Active,ICA-2,WS-0002,,0', '1,4,mu,KLINIK,Active,ICA-3,WS-0003,,0')
    $script:Run = Write-TestRun 'mask' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'sessions.csv' = $sess
        'shares.csv' = @('0,\\fs01\daten,1,1,5,5,1,1'); 'volumes.csv' = @('0,C:\Users\mueller_UPM_local\UpmTempMount,profile,2,\\fs02\upm$,1,1,5,5,1,1,0')
        'probes.csv' = @('0,DB,Datenbank,10.1.2.3,1521,4,'); 'procinfo.csv' = @('0,100,1,EXCEL.EXE,2,,C:\Users\anna\S-1-5-21-1-2-3-1108\x.exe,,') }
    [IO.File]::WriteAllLines((Join-Path $Run 'printqueues.csv'), @('Timestamp,Queue,Jobs,JobErrors,NotReadyErrors', "$(Get-Ts 5),PRN-EG-01,0,0,0"))
    function Get-Entries([string]$Level) { @((New-WorkerPerfMask -Path $Run -Level $Level -Texts $Texts).Entries | ForEach-Object { '{0}:{1}={2}' -f $_.Kind, $_.Name, $_.Replacement }) }
    function Get-RunEntries([string]$Path, [string]$Level, [hashtable]$Extra = @{}) {
        @((New-WorkerPerfMask -Path $Path -Level $Level -Texts $Texts @Extra).Entries | ForEach-Object { '{0}:{1}={2}' -f $_.Kind, $_.Name, $_.Replacement })
    }
    function New-EventLine([double]$Sec, [string]$Group, [string]$App, [string]$Module, [string]$User, [string]$Printer, [string]$Driver, [string]$Service, [string]$Object, [string]$Text) {
        '{0},application,Src,1,2,{1},crash,{2},1.0,{3},1.0,,,-1,{4},{5},{6},{7},{8},{9}' -f (Get-Ts $Sec), $Group, $App, $Module, $User, $Printer, $Driver, $Service, $Object, $Text
    }
}
Describe 'Namen der Aufzeichnung' {
    It 'vergibt Ersatznamen je Art in der Reihenfolge des ersten Auftretens' {
        Get-Entries 'Alles' | Should -Be @('server:T1=Server 01', 'server:h=Server 02', 'user:mueller=Benutzer 01', 'domain:KLINIK=Domäne 01', 'client:WS-0001=Client 01',
            'client:WS-0002=Client 02', 'user:mu=Benutzer 02', 'client:WS-0003=Client 03', 'share:\\fs01\daten=Freigabe 01', 'server:fs01=Server 03',
            'share:\\fs02\upm$=Freigabe 02', 'server:fs02=Server 04', 'address:10.1.2.3=Adresse 01', 'printer:PRN-EG-01=Drucker 01', 'user:anna=Benutzer 03', 'sid:S-1-5-21-1-2-3-1108=Konto 01')
    }
    It 'ersetzt bei Personen nur Benutzer, Clients und Konten' {
        Get-Entries 'Personen' | Should -Be @('user:mueller=Benutzer 01', 'client:WS-0001=Client 01', 'client:WS-0002=Client 02', 'user:mu=Benutzer 02', 'client:WS-0003=Client 03', 'user:anna=Benutzer 03', 'sid:S-1-5-21-1-2-3-1108=Konto 01')
    }
    It 'nimmt keinen leeren Namen auf und kennt die geschuetzten Namen' {                     # Review Focus 3
        $m = New-WorkerPerfMask -Path $Run -Level 'Alles' -Texts $Texts
        @($m.Entries | Where-Object { [string]::IsNullOrWhiteSpace($_.Name) }).Count | Should -Be 0
        $m.Protected | Should -Contain 'EXCEL.EXE'; $m.Protected | Should -Contain 'DB'
    }
}
Describe 'Namen aus Ereignissen, Druckern und Mustern' {
    BeforeAll {
        $script:EvRun = Write-TestRun 'mask-events' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines
            'sessions.csv' = @('0,2,lehmann,KLINIK,Active,ICA-CGP#2,WS-0101,,0'); 'shares.csv' = $null; 'volumes.csv' = $null; 'probes.csv' = $null
            'procinfo.csv' = @('0,100,1,spoolsv.exe,0,,C:\Windows\System32\spoolsv.exe,Spooler;RpcSs,', '1,101,1,tool.exe,2,,\\nas07\tools\tool.exe,,') }
        $h = $WorkerPerfHeaders['events.csv']
        # in the file the later record comes first: the reader orders by time, the names follow that order
        [IO.File]::WriteAllLines((Join-Path $EvRun 'events.csv'), @($h,
                (New-EventLine 30 'print' '' '' 'KLINIK\Lehmann' '\\prt01\PRN-OG-02' 'HP Universal (Test)' '' '' 'Der Auftrag ging an 192.168.7.9'),
                (New-EventLine 20 'app' 'nexus.exe' 'nxreport.dll' 'SYSTEM' '' '' '' '' 'Version 8.2.0.114'),
                (New-EventLine 21 'session' '' '' 'DWM-3' '' '' '' '' ''),
                (New-EventLine 22 'fileserver' '' '' 'FREMD\WORKER7$' '' '' 'LanmanWorkstation' '\\fs09' ''),
                (New-EventLine 23 'storage' '' '' 'S-1-5-21-9-8-7-4242' '' '' '' '\Device\Harddisk1\DR1' ''),
                (New-EventLine 24 'app' 'calc.exe' 'calc.dll' 'koch' '' '' '' '' '')))
        [IO.File]::WriteAllLines((Join-Path $EvRun 'events_before.csv'), @($h, (New-EventLine -9000 'app' 'EXCEL.EXE' 'simaddin.dll' 'KLINIK\weber' '' '' '' '' '')))
        [IO.File]::WriteAllLines((Join-Path $EvRun 'printqueues.csv'), @('Timestamp,Queue,Jobs,JobErrors,NotReadyErrors', "$(Get-Ts 5),PRN-EG-01,0,0,0", "$(Get-Ts 9),prn-og-02,0,0,0"))
        [IO.File]::WriteAllLines((Join-Path $EvRun 'printdrivers.csv'), @('Name,Manufacturer,Version,Type,Isolation,Files', 'HP Universal (Test),HP,1.0,3,none,a.dll'))
    }
    It 'liest Benutzer ohne Domaenenteil, Drucker und Dateiserver aus events.csv, dann events_before.csv' {
        Get-RunEntries $EvRun 'Alles' | Should -Be @('server:T1=Server 01', 'server:h=Server 02', 'user:lehmann=Benutzer 01', 'domain:KLINIK=Domäne 01', 'client:WS-0101=Client 01',
            'server:WORKER7=Server 03', 'domain:FREMD=Domäne 02','server:fs09=Server 04', 'sid:S-1-5-21-9-8-7-4242=Konto 01', 'user:koch=Benutzer 02',
            'printer:\\prt01\PRN-OG-02=Drucker 01', 'server:prt01=Server 05', 'user:weber=Benutzer 03', 'printer:PRN-EG-01=Drucker 02', 'printer:prn-og-02=Drucker 03',
            'share:\\nas07\tools=Freigabe 01', 'server:nas07=Server 06')
    }
    It 'nimmt Dienst-, virtuelle und Computerkonten nicht als Benutzer und keine Versionsnummer als Adresse' {
        $names = @((New-WorkerPerfMask -Path $EvRun -Level 'Alles' -Texts $Texts).Entries | ForEach-Object { $_.Name })
        foreach ($n in 'SYSTEM', 'DWM-3', 'WORKER7$', '8.2.0.114', '192.168.7.9') { $names | Should -Not -Contain $n }
    }
    It 'nimmt bei Personen dieselben Nummern wie bei Alles' {
        Get-RunEntries $EvRun 'Personen' | Should -Be @('user:lehmann=Benutzer 01', 'client:WS-0101=Client 01', 'sid:S-1-5-21-9-8-7-4242=Konto 01', 'user:koch=Benutzer 02', 'user:weber=Benutzer 03')
    }
    It 'nimmt eine eigene Liste der Konten ohne Person aus der Ereigniskonfiguration' {
        $cfg = @{ NonPersonAccounts = @('SYSTEM', 'DWM-*', '*$', 'koch') }
        Get-RunEntries $EvRun 'Personen' @{ EventConfig = $cfg } | Should -Be @('user:lehmann=Benutzer 01', 'client:WS-0101=Client 01', 'sid:S-1-5-21-9-8-7-4242=Konto 01', 'user:weber=Benutzer 02')
    }
    It 'schuetzt Prozess-, Dienst-, Anwendungs-, Modul-, Treiber- und Rollennamen' {
        $m = New-WorkerPerfMask -Path $EvRun -Level 'Alles' -Texts $Texts -RoleLabels @('Microsoft Defender')
        foreach ($n in 'spoolsv.exe', 'Spooler', 'RpcSs', 'nexus.exe', 'nxreport.dll', 'LanmanWorkstation', 'HP Universal (Test)', 'HP', 'EXCEL.EXE', 'DB', 'Datenbank', 'Microsoft Defender') {
            $m.Protected | Should -Contain $n
        }
        @($m.Protected | Where-Object { $_ -eq 'HP Universal (Test)' }).Count | Should -Be 1
    }
    It 'bildet den Namen ohne Ruecksicht auf die Schreibweise ab und setzt das Muster laengere Namen zuerst' {
        $m = New-WorkerPerfMask -Path $EvRun -Level 'Alles' -Texts $Texts
        $m.Level | Should -Be 'Alles'
        $m.Lookup['lehmann'] | Should -Be 'Benutzer 01'; $m.Lookup['prn-og-02'] | Should -Be 'Drucker 03'
        $m.Regex.Replace('\\prt01\PRN-OG-02 von LEHMANN', { param($x) $m.Lookup[$x.Value.ToLowerInvariant()] }) | Should -Be 'Drucker 01 von Benutzer 01'
        (New-WorkerPerfMask -Path $EvRun -Level 'Personen' -Texts $Texts).Lookup.ContainsKey('t1') | Should -BeFalse
    }
}
Describe 'Aufzeichnung ohne Namen' {
    It 'liefert eine leere Liste und kein Muster' {
        $p = Write-TestRun 'mask-empty' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'sessions.csv' = $null; 'events.csv' = $null }
        [IO.File]::WriteAllText((Join-Path $p 'meta.json'), '{"SchemaVersion":2,"Computer":"","Endpoints":[]}')
        $m = New-WorkerPerfMask -Path $p -Level 'Personen' -Texts $Texts
        @($m.Entries).Count | Should -Be 0; $m.Regex | Should -BeNullOrEmpty; $m.Lookup.Count | Should -Be 0
    }
}
Describe 'Benutzerordner, ICA-Sitzungen, Adressen und Vorrang der Personen' {
    BeforeAll {
        $script:FxRun = Write-TestRun 'mask-fix' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines
            'sessions.csv' = @('0,2,adm.anna,KLINIK,Active,ICA-CGP#2,proxy01,,0'); 'shares.csv' = $null; 'volumes.csv' = $null
            'citrix.csv' = @('0,ICA,2,ICA-CGP 9 (KLINIK2\gast.user),Latency,5', '0,ICA,3,ICA-CGP 3 (otto),Latency,5', '1,ICA,3,ICA-CGP 3 (otto),Latency,6')
            'probes.csv' = @('0,Datei,Dateiserver,fs01,445,2,')
            'procinfo.csv' = @('0,100,1,tool.exe,2,,C:\Users\adm.wolf\Desktop\tool.exe,,', '1,101,1,a.exe,2,,d:\USERS\Public\a.exe,,', '2,102,1,b.exe,2,,C:\Users\Default\b.exe,,',
                '3,103,1,c.exe,2,,C:\Users\Default User\c.exe,,', '4,104,1,d.exe,2,,C:\Users\All Users\d.exe,,', '5,105,1,e.exe,0,,C:\Users\SYSTEM\e.exe,,',
                '6,106,1,app.exe,2,,C:\Program Files\App\8.2.0.114\app.exe,,', '7,107,1,x.exe,2,,\\10.4.4.4\apps\x.exe,,') }
        $meta = '{"SchemaVersion":3,"Computer":"vda01","Endpoints":[{"Name":"Proxy","Host":"PROXY01","Port":8080,"Role":"Proxy"},' +
            '{"Name":"Datei","Host":"fs01.sim.local","Port":445,"Role":"Dateiserver"},{"Name":"Ora","Host":"ora.example","Port":1521,"Role":"Datenbank"},' +
            '{"Name":"IP","Host":"10.0.0.5","Port":80,"Role":"Web"}],"Sources":{},"SourceErrors":{},' +
            '"EndMessage":"Verbindung zu 10.9.8.7 fehlgeschlagen, Version 1.2.3.4, v5.6.7.8, version: 2.2.2.2, Pfad C:\\x\\9.9.9.9\\y"}'
        [IO.File]::WriteAllText((Join-Path $FxRun 'meta.json'), $meta)
        $h = $WorkerPerfHeaders['events.csv']
        [IO.File]::WriteAllLines((Join-Path $FxRun 'events.csv'), @($h,
                ('{0},application,Application Error,1000,2,app,crash,app.exe,8.2.0.114,app.dll,8.2.0.114,0xc0000005,106,2,,,,,,' -f (Get-Ts 10)),
                (New-EventLine 11 'service' '' '' 'NT SERVICE\MSSQLSERVER' '' '' '' '' ''), (New-EventLine 12 'app' '' '' 'IIS APPPOOL\DefaultAppPool' '' '' '' '' ''),
                (New-EventLine 13 'app' '' '' "NT-AUTORIT$([char]0xC4)T\LOKALER DIENST" '' '' '' '' ''), (New-EventLine 14 'app' '' '' 'Window Manager\DWM-2' '' '' '' '' ''),
                (New-EventLine 15 'app' '' '' 'Font Driver Host\UMFD-1' '' '' '' '' ''), (New-EventLine 16 'app' '' '' 'NT AUTHORITY\NETWORK SERVICE' '' '' '' '' ''),
                (New-EventLine 17 'session' '' '' 'c.wagner@klinik.example' '' '' '' '' ''), (New-EventLine 18 'storage' '' '' '' '' '' '' 'C:\Users\eva\ntuser.dat' '')))
    }
    It 'sammelt Benutzerordner, ICA-Instanzen, UPN, DNS-Suffixe und Adressen nur aus Hostfeldern' {
        Get-RunEntries $FxRun 'Alles' | Should -Be @('server:vda01=Server 01', 'client:PROXY01=Client 01', 'server:fs01.sim.local=Server 02', 'domain:sim.local=Domäne 01',
            'server:ora.example=Server 03', 'address:10.0.0.5=Adresse 01', 'user:adm.anna=Benutzer 01', 'domain:KLINIK=Domäne 02', 'user:gast.user=Benutzer 02',
            'domain:KLINIK2=Domäne 03', 'user:otto=Benutzer 03', 'server:fs01=Server 04', 'user:c.wagner=Benutzer 04', 'domain:klinik.example=Domäne 04',
            'user:adm.wolf=Benutzer 05', 'share:\\10.4.4.4\apps=Freigabe 01', 'address:10.4.4.4=Adresse 02', 'user:eva=Benutzer 06', 'address:10.9.8.7=Adresse 03')
    }
    It 'nimmt einen Client, der auch Gegenstelle ist, bei Personen als Client' {
        Get-RunEntries $FxRun 'Personen' | Should -Be @('client:PROXY01=Client 01', 'user:adm.anna=Benutzer 01', 'user:gast.user=Benutzer 02', 'user:otto=Benutzer 03',
            'user:c.wagner=Benutzer 04', 'user:adm.wolf=Benutzer 05', 'user:eva=Benutzer 06')
    }
    It 'nimmt Sitzungsbenutzer ohne den Filter der Konten ohne Person' {
        $cfg = @{ NonPersonAccounts = @('SYSTEM', 'adm*'); NonPersonDomains = $WorkerPerfDefaultNonPersonDomains }
        Get-RunEntries $FxRun 'Personen' @{ EventConfig = $cfg } | Should -Be @('client:PROXY01=Client 01', 'user:adm.anna=Benutzer 01', 'user:gast.user=Benutzer 02',
            'user:otto=Benutzer 03', 'user:c.wagner=Benutzer 04', 'user:eva=Benutzer 05')
    }
    It 'kennt die Domaenen virtueller Konten aus events.json' {
        $cfg = Read-WorkerPerfEventConfig (Join-Path $PSScriptRoot '../src/events.json')
        @($cfg.NonPersonDomains) | Should -Contain 'NT SERVICE'; @($cfg.NonPersonDomains) | Should -Contain "NT-AUTORIT$([char]0xC4)T"
        $shipped = (Get-Content (Join-Path $PSScriptRoot '../src/events.json') -Raw -Encoding UTF8 | ConvertFrom-Json).nonPersonDomains
        @($script:WorkerPerfDefaultNonPersonDomains) | Should -Be @($shipped)
        Test-WorkerPerfEventPersonUser 'NT SERVICE\MSSQLSERVER' $cfg | Should -BeFalse; Test-WorkerPerfEventPersonUser 'KLINIK\anna' $cfg | Should -BeTrue
    }
    It 'vergleicht die Konten ohne Person unabhaengig von der Kultur' {
        $cfg = Read-WorkerPerfEventConfig (Join-Path $PSScriptRoot '../src/events.json')
        $old = [Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]'tr-TR'
            Test-WorkerPerfEventPersonUser 'lokaler dienst' $cfg | Should -BeFalse; Test-WorkerPerfEventPersonUser 'netzwerkdienst' $cfg | Should -BeFalse
            Test-WorkerPerfEventPersonUser 'window manager\dwm-2' $cfg | Should -BeFalse
        }
        finally { [Threading.Thread]::CurrentThread.CurrentCulture = $old }
    }
}
Describe 'Ersetzen' {
    BeforeAll {
        function New-TestMask([string[]]$Users, [string[]]$Protected = @(), [string]$Level = 'Personen') {
            $m = New-WorkerPerfMask -Path (Write-TestRun 'leer' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }) -Level $Level -Texts $Texts
            # Testzugang: dieselbe Funktion, die New-WorkerPerfMask nutzt, baut Lookup und Regex aus einer Namensliste
            Set-WorkerPerfMaskNames -Mask $m -Entries @($Users | ForEach-Object -Begin { $n = 0 } -Process { $n++; @{ Kind = 'user'; Name = $_; Replacement = 'Benutzer {0:00}' -f $n } }) -Protected $Protected
            $m
        }
    }
    It 'ersetzt ganze Namen, laengere zuerst, ohne Ruecksicht auf die Schreibweise' {
        $m = New-TestMask @('user01', 'user010', 'mu', 'mueller')
        Hide-WorkerPerfReportText 'user010 und USER01, nicht user0100' $m | Should -Be 'Benutzer 02 und Benutzer 01, nicht user0100'
        Hide-WorkerPerfReportText 'Mueller sagt mu' $m | Should -Be 'Benutzer 04 sagt Benutzer 03'
    }
    It 'ersetzt Benutzer in Pfaden und Instanznamen' {                                          # Review Focus 2
        $m = New-TestMask @('mueller')
        Hide-WorkerPerfReportText 'C:\Users\mueller_UPM_local\UpmTempMount' $m | Should -Be 'C:\Users\Benutzer 01_UPM_local\UpmTempMount'
        Hide-WorkerPerfReportText '\\fs01\upm$\Mueller.KLINIK\x.vhdx KLINIK\MUELLER' $m | Should -Be '\\fs01\upm$\Benutzer 01.KLINIK\x.vhdx KLINIK\Benutzer 01'
    }
    It 'laesst Programm- und Gegenstellennamen stehen und ersetzt den Benutzer gleichen Namens' {   # Review Focus 1
        $m = New-TestMask @('excel', 'oracle') @('EXCEL.EXE', 'Oracle-Listener')
        Hide-WorkerPerfReportText 'Hauptverursacher: EXCEL.EXE in der Sitzung von excel; Gegenstelle Oracle-Listener (oracle)' $m |
            Should -Be 'Hauptverursacher: EXCEL.EXE in der Sitzung von Benutzer 01; Gegenstelle Oracle-Listener (Benutzer 02)'
    }
    It 'entfernt unbekannte Konten-SIDs' { Hide-WorkerPerfReportText 'S-1-5-21-9-9-9-1001_x' (New-TestMask @()) | Should -Be '(Name entfernt)_x' }
    It 'maskiert Texte, Schluessel und Eigenschaftsnamen und haelt gleich gewordene Schluessel getrennt' {   # Review Focus 4
        $m = New-TestMask @('user1')
        # Abweichung vom Plan: [ordered]@{ user1 = 1; User1 = 2 } ist ein Parserfehler (gleiche Schluessel im Literal);
        # 'Benutzer 01' wird nach dem Ersetzen von user1 zum selben Schluessel
        $d = [ordered]@{ meta = [ordered]@{ user = 'user1' }; byUser = [ordered]@{ user1 = 1; 'Benutzer 01' = 2 }; obj = [pscustomobject]@{ user1 = 'a user1' }
            series = (New-Object System.Text.StringBuilder '[1,2,null]'); n = 3.5; list = @('user1', 7) }
        $r = Protect-WorkerPerfReportData $d $m
        $r.meta.user | Should -Be 'Benutzer 01'; @($r.byUser.Keys) | Should -Be @('Benutzer 01', 'Benutzer 01 (2)'); $r.byUser['Benutzer 01 (2)'] | Should -Be 2
        $r.obj['Benutzer 01'] | Should -Be 'a Benutzer 01'; $r.series.ToString() | Should -Be '[1,2,null]'; $r.n | Should -Be 3.5; $r.list | Should -Be @('Benutzer 01', 7)
    }
    It 'leert Meldungstexte und Befehlszeilen' {
        $d = [ordered]@{ meta = [ordered]@{ endMessage = 'x' }; events = @([ordered]@{ text = 'geheim' }); procs = @([ordered]@{ cmd = 'tool.exe /u geheim' })
            incidents = @([ordered]@{ text = 'bleibt'; events = @([ordered]@{ text = 'geheim' }) }); before = [ordered]@{ near = @([ordered]@{ text = 'geheim' }); incidents = @() }
            quality = [ordered]@{ sourceErrors = @([ordered]@{ firstMessage = 'geheim' }) } }
        Clear-WorkerPerfReportFreeText $d
        ($d | ConvertTo-Json -Depth 6) | Should -Not -Match 'geheim'; $d.incidents[0].text | Should -Be 'bleibt'
    }
}
Describe 'Ersetzen: Grenzfaelle' {
    BeforeAll {
        function New-NameMask([string]$Level, [object[]]$Entries, [string[]]$Protected = @()) {
            $m = New-WorkerPerfMask -Path (Write-TestRun 'leer2' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }) -Level $Level -Texts $Texts
            Set-WorkerPerfMaskNames -Mask $m -Entries $Entries -Protected $Protected
            $m
        }
        function New-UserMask([string[]]$Users, [string[]]$Protected = @()) {
            $n = 0
            New-NameMask 'Personen' @($Users | ForEach-Object { $n++; @{ Kind = 'user'; Name = $_; Replacement = 'Benutzer {0:00}' -f $n } }) $Protected
        }
    }
    It 'ersetzt den Ordner eines Programms, das wie ein Benutzer heisst, und laesst die Programmdatei stehen' {   # Nexus-Fall
        $m = New-UserMask @('nexus') @('nexus.exe')
        Hide-WorkerPerfReportText 'C:\Program Files\Nexus\nexus.exe' $m | Should -Be 'C:\Program Files\Benutzer 01\nexus.exe'
    }
    It 'nimmt Regex-Zeichen in Namen woertlich' {
        $m = New-UserMask @('a.b', 'a.b+c', 'm(1)')
        Hide-WorkerPerfReportText 'a.b+c und m(1), nicht axb, a.bbc, axb+c oder m1; aber a.b' $m | Should -Be 'Benutzer 02 und Benutzer 03, nicht axb, a.bbc, axb+c oder m1; aber Benutzer 01'
    }
    It 'schuetzt einen Namen ohne Ruecksicht auf die Schreibweise, am Anfang, am Ende, in Anfuehrungszeichen und Klammern' {
        $m = New-UserMask @('excel') @('EXCEL.EXE')
        foreach ($t in 'excel.exe', 'Start: Excel.Exe', '"EXCEL.exe"', "'excel.EXE'", '(EXCEL.EXE)', '[excel.exe]', 'a=EXCEL.EXE|b', 'Absturz von EXCEL.EXE.') {
            Hide-WorkerPerfReportText $t $m | Should -Be $t -Because $t
        }
        Hide-WorkerPerfReportText 'EXCEL.EXE von excel' $m | Should -Be 'EXCEL.EXE von Benutzer 01'
        Hide-WorkerPerfReportText '"excel"' $m | Should -Be '"Benutzer 01"'
        Hide-WorkerPerfReportText 'excel.exe.bak excel2' $m | Should -Be 'Benutzer 01.exe.bak excel2'
    }
    It 'laesst $null und leere Texte stehen' {
        $m = New-UserMask @('anna')
        $null -eq (Hide-WorkerPerfReportText $null $m) | Should -BeTrue; Hide-WorkerPerfReportText '' $m | Should -Be ''
    }
    It 'ersetzt bei Alles unbekannte Server in UNC-Pfaden, bei Personen nicht, und nie Adressen im Fliesstext' {
        $alles = New-NameMask 'Alles' @(@{ Kind = 'server'; Name = 'fs01'; Replacement = 'Server 01' }, @{ Kind = 'user'; Name = 'anna'; Replacement = 'Benutzer 01' })
        Hide-WorkerPerfReportText '\\nas99\daten\anna\x.txt und \\FS01\upm$' $alles | Should -Be '\\(Name entfernt)\daten\Benutzer 01\x.txt und \\Server 01\upm$'
        Hide-WorkerPerfReportText 'Pfad \\?\C:\x und \\.\pipe\y' $alles | Should -Be 'Pfad \\?\C:\x und \\.\pipe\y'
        Hide-WorkerPerfReportText 'an 10.9.9.9, Version 10.0.20348.1, C:\Citrix\8.2.0.114\x.dll' $alles | Should -Be 'an 10.9.9.9, Version 10.0.20348.1, C:\Citrix\8.2.0.114\x.dll'
        $personen = New-NameMask 'Personen' @(@{ Kind = 'user'; Name = 'anna'; Replacement = 'Benutzer 01' })
        Hide-WorkerPerfReportText '\\nas99\daten\anna S-1-5-21-1-2-3-4 s-1-5-21-1-2-3-4-5' $personen | Should -Be '\\nas99\daten\Benutzer 01 (Name entfernt) s-1-5-21-1-2-3-4-5'
    }
    It 'nimmt fuer eine bekannte SID ihren Ersatznamen' {
        $m = New-NameMask 'Personen' @(@{ Kind = 'sid'; Name = 'S-1-5-21-1-2-3-1108'; Replacement = 'Konto 01' })
        Hide-WorkerPerfReportText 'C:\Users\anna\S-1-5-21-1-2-3-1108\x und S-1-5-21-1-2-3-9' $m | Should -Be 'C:\Users\anna\Konto 01\x und (Name entfernt)'
    }
    It 'baut verschachtelte Daten neu auf und laesst Zahlen, Wahrheitswerte und Zeiten unveraendert' {
        $m = New-UserMask @('anna')
        $when = [datetime]'2026-01-15 08:00:00'
        $in = [ordered]@{ rows = @([ordered]@{ user = 'anna'; sub = @(@{ k = 'anna' }, $null) }, [ordered]@{ user = $null; n = 1 })
            empty = @(); one = @('anna'); b = $true; i = 42; l = [long]7; d = 2.5; t = $when; nul = $null; ints = [int[]]@(1, 2); strs = [string[]]@('anna', 'x')
            gl = (New-Object 'System.Collections.Generic.List[object]') }
        $in.gl.Add('anna')
        $before = $in | ConvertTo-Json -Depth 8
        $r = Protect-WorkerPerfReportData $in $m
        ($in | ConvertTo-Json -Depth 8) | Should -Be $before                                  # Eingabe unveraendert
        [object]::ReferenceEquals($r, $in) | Should -BeFalse; [object]::ReferenceEquals($r.rows[0], $in.rows[0]) | Should -BeFalse
        $r.rows[0].user | Should -Be 'Benutzer 01'; $r.rows[0].sub[0].k | Should -Be 'Benutzer 01'; $null -eq $r.rows[0].sub[1] | Should -BeTrue
        $r.rows[0].sub.Count | Should -Be 2; $r.rows[0].sub[0] | Should -BeOfType [System.Collections.IDictionary]
        $r.rows[1].Contains('user') | Should -BeTrue; $null -eq $r.rows[1].user | Should -BeTrue
        $r.empty.GetType().IsArray | Should -BeTrue; $r.empty.Count | Should -Be 0
        $r.one.GetType().IsArray | Should -BeTrue; $r.one.Count | Should -Be 1; $r.one[0] | Should -Be 'Benutzer 01'
        $r.gl.GetType().IsArray | Should -BeTrue; $r.gl[0] | Should -Be 'Benutzer 01'
        $r.strs | Should -Be @('Benutzer 01', 'x'); $r.ints | Should -Be @(1, 2); $r.ints.GetType() | Should -Be ([int[]])
        $r.b | Should -BeOfType [bool]; $r.b | Should -BeTrue; $r.i | Should -BeOfType [int]; $r.i | Should -Be 42; $r.l | Should -BeOfType [long]
        $r.d | Should -BeOfType [double]; $r.d | Should -Be 2.5; $r.t | Should -BeOfType [datetime]; $r.t | Should -Be $when
        $r.Contains('nul') | Should -BeTrue; $null -eq $r.nul | Should -BeTrue
        $e = Protect-WorkerPerfReportData @() $m; $null -eq $e | Should -BeFalse; $e.GetType().IsArray | Should -BeTrue; $e.Count | Should -Be 0
        $o = Protect-WorkerPerfReportData @('anna') $m; $o.GetType().IsArray | Should -BeTrue; $o.Count | Should -Be 1
        $null -eq (Protect-WorkerPerfReportData $null $m) | Should -BeTrue; Protect-WorkerPerfReportData 'anna' $m | Should -Be 'Benutzer 01'
    }
}
Describe 'Geschuetzte Namen mit Leerraum und Adressen in Zahlenreihen' {
    BeforeAll {
        function New-PhraseMask([object[]]$Entries, [string[]]$Protected = @()) {
            $m = New-WorkerPerfMask -Path (Write-TestRun 'leer3' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }) -Level 'Alles' -Texts $Texts
            Set-WorkerPerfMaskNames -Mask $m -Entries $Entries -Protected $Protected
            $m
        }
        $script:Nexus = @{ Kind = 'user'; Name = 'nexus'; Replacement = 'Benutzer 01' }
    }
    It 'laesst einen Treffer in einem geschuetzten Namen mit Leerzeichen stehen' {                # P2-R6
        $m = New-PhraseMask @($Nexus) @('Nexus KIS', 'nexus.exe')
        Hide-WorkerPerfReportText 'Nexus KIS' $m | Should -Be 'Nexus KIS'
        Hide-WorkerPerfReportText 'Sitzung von nexus' $m | Should -Be 'Sitzung von Benutzer 01'
        Hide-WorkerPerfReportText 'Nexus KIS (nexus)' $m | Should -Be 'Nexus KIS (Benutzer 01)'
        Hide-WorkerPerfReportText 'nexus KIS am Anfang und am Ende NEXUS kis' $m | Should -Be 'nexus KIS am Anfang und am Ende NEXUS kis'
        Hide-WorkerPerfReportText 'Nexus KISS' $m | Should -Be 'Benutzer 01 KISS'
        Hide-WorkerPerfReportText 'XNexus KIS und Nexus KIS2' $m | Should -Be 'XNexus KIS und Benutzer 01 KIS2'
    }
    It 'schuetzt einen Treibernamen mit Leerzeichen und Klammern' {
        $m = New-PhraseMask @(@{ Kind = 'user'; Name = 'hp'; Replacement = 'Benutzer 01' }) @('HP Universal Printing PCL 6 (v7.0.1)', 'HP')
        Hide-WorkerPerfReportText 'Das Modul hpsimgr.dll gehört zum Druckertreiber HP Universal Printing PCL 6 (v7.0.1).' $m |
            Should -Be 'Das Modul hpsimgr.dll gehört zum Druckertreiber HP Universal Printing PCL 6 (v7.0.1).'
        $m2 = New-PhraseMask @(@{ Kind = 'user'; Name = 'hp'; Replacement = 'Benutzer 01' }) @('HP Universal Printing PCL 6 (v7.0.1)')
        Hide-WorkerPerfReportText 'HP Universal Printing PCL 6 (v7.0.1), Sitzung von hp' $m2 | Should -Be 'HP Universal Printing PCL 6 (v7.0.1), Sitzung von Benutzer 01'
        Hide-WorkerPerfReportText 'HP Universal Printing PCL 6 (v7.0.2)' $m2 | Should -Be 'Benutzer 01 Universal Printing PCL 6 (v7.0.2)'
    }
    It 'ersetzt eine Adresse nicht in einer laengeren Zahlenreihe' {
        $m = New-PhraseMask @(@{ Kind = 'address'; Name = '10.0.2.1'; Replacement = 'Adresse 01' }, @{ Kind = 'user'; Name = 'u1'; Replacement = 'Benutzer 01' })
        Hide-WorkerPerfReportText '1.10.0.2.1 und 10.0.2.1.7' $m | Should -Be '1.10.0.2.1 und 10.0.2.1.7'
        Hide-WorkerPerfReportText 'an 10.0.2.1.' $m | Should -Be 'an Adresse 01.'
        Hide-WorkerPerfReportText '10.0.2.1:1521 und a.10.0.2.1 und 10.0.2.1.x' $m | Should -Be 'Adresse 01:1521 und a.Adresse 01 und Adresse 01.x'
        Hide-WorkerPerfReportText 'u1.7 bleibt kein Name' $m | Should -Be 'Benutzer 01.7 bleibt kein Name'
    }
}
Describe 'Meldungstexte ueber den Plan hinaus' {
    It 'leert die Texte der Ereignisse von Mustern, des Rueckblicks und die Begruendung nicht verfuegbarer Quellen' {
        $ev = { param($t) [ordered]@{ t = 1; kind = 'crash'; text = $t } }
        $pattern = [ordered]@{ id = 'companion'; text = 'Zeitnah: bleibt.'; detail = [ordered]@{ events = @((& $ev 'geheim')) } }
        $d = [ordered]@{ meta = [ordered]@{ endMessage = $null }
            quality = [ordered]@{ sourceErrors = @(); sources = @([ordered]@{ id = 'cpu.steal'; available = $false; detail = 'Pruefung fehlgeschlagen: geheim' }, [ordered]@{ id = 'cpu.host'; available = $true; detail = 'Processor / bleibt' }) }
            sollIst = @([ordered]@{ id = 'cpu.steal'; detail = 'Pruefung fehlgeschlagen: geheim' }, [ordered]@{ id = 'cpu.host'; detail = '' })
            events = @([ordered]@{ t = 1; kind = 'logon' }, [ordered]@{ t = 2; text = $null })
            incidents = @([ordered]@{ text = 'bleibt'; events = @(); event = $null }, [ordered]@{ text = 'bleibt'; events = @((& $ev 'geheim')); event = [ordered]@{ codes = @([ordered]@{ code = '0x1'; text = 'Zugriffsverletzung' }); patterns = @($pattern) } })
            before = [ordered]@{ near = @(); nearCapture = @(); incidents = @([ordered]@{ text = 'bleibt'; events = @((& $ev 'geheim')); event = [ordered]@{ patterns = @($pattern) } }) } }
        Clear-WorkerPerfReportFreeText $d
        ($d | ConvertTo-Json -Depth 10) | Should -Not -Match 'geheim'
        $d.quality.sources[1].detail | Should -Be 'Processor / bleibt'; $d.quality.sources[0].detail | Should -Be ''; $d.sollIst[0].detail | Should -Be ''
        $d.incidents[1].event.codes[0].text | Should -Be 'Zugriffsverletzung'; $d.incidents[1].event.patterns[0].text | Should -Be 'Zeitnah: bleibt.'
        $d.events[0].Contains('text') | Should -BeFalse; $d.events[1].Contains('text') | Should -BeTrue; $null -eq $d.events[1].text | Should -BeTrue
        $null -eq $d.meta.endMessage | Should -BeTrue
    }
}
Describe 'Maskierte Berichtsdaten der simulierten Stunde' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        # the names below are not used by the report script, which runs in the same scope
        $maskSimOut = Join-Path $TestDrive 'sim'
        $script:SimRun = Invoke-SimCapture (Join-Path $maskSimOut 'capture')
        $maskSimRoles = New-SimRoleFile (Join-Path $maskSimOut 'roles.sim.json')
        $maskSimReport = Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1'
        # the report data as the report script builds it (the script is dot-sourced in a child scope, which keeps $data);
        # ConvertTo-JsonText is the report's own JSON writer
        $script:Sim = & {
            # a reported time 5 min before the capture fills before.near with events of the capture
            $maskSimFirst = [DateTimeOffset]::Parse((Get-Content (Join-Path $SimRun 'ticks.csv') -TotalCount 2)[1].Split(',')[1], [cultureinfo]::InvariantCulture).ToUnixTimeMilliseconds()
            $null = . $maskSimReport -Path $SimRun -OutFile (Join-Path $maskSimOut 'report.html') -RoleFile $maskSimRoles -FocusUser 'user003' -ReportedTime (Get-ServerTime $SimRun ($maskSimFirst - 300000)) 6>$null
            $maskSimMask = New-WorkerPerfMask -Path $SimRun -Level 'Alles' -Texts $Texts -RoleLabels @(@(Read-WorkerPerfRoles $maskSimRoles) | ForEach-Object { [string]$_.label })
            function Get-MaskSimJson($Value) { $w = New-Object System.IO.StringWriter; ConvertTo-JsonText $Value $w; $w.ToString() }
            $maskSimPlain = Get-MaskSimJson $data
            Clear-WorkerPerfReportFreeText $data
            $maskSimCleared = Get-MaskSimJson $data
            $maskSimMasked = Protect-WorkerPerfReportData $data $maskSimMask
            @{ Data = $data; Masked = $maskSimMasked; Mask = $maskSimMask; Plain = $maskSimPlain; Cleared = $maskSimCleared; ClearedAfter = (Get-MaskSimJson $data)
                MaskedJson = (Get-MaskSimJson $maskSimMasked) }
        }
        function Get-Strings($Value, $List) {
            if ($null -eq $Value -or $Value -is [System.Text.StringBuilder] -or $Value -is [ValueType]) { return }
            if ($Value -is [string]) { $List.Add($Value); return }
            if ($Value -is [System.Collections.IDictionary]) { foreach ($k in $Value.Keys) { $List.Add([string]$k); Get-Strings $Value[$k] $List }; return }
            foreach ($x in $Value) { Get-Strings $x $List }
        }
    }
    It 'leert die Meldungstexte und laesst die Zahlen gleich' {
        $Sim.Plain | Should -Match '"text":"[^"]+'; $Sim.Cleared | Should -Not -Match '"text":"(?!")[^"]*Session'
        @($Sim.Data.events | Where-Object { $_.text -ne '' }).Count | Should -Be 0
        foreach ($inc in @($Sim.Data.incidents) + @($Sim.Data.before.incidents)) { @($inc.events | Where-Object { $_.text -ne '' }).Count | Should -Be 0 }
        @($Sim.Data.before.near).Count | Should -BeGreaterThan 0; @($Sim.Data.before.near | Where-Object { $_.text -ne '' }).Count | Should -Be 0
        @($Sim.Masked.incidents).Count | Should -Be @($Sim.Data.incidents).Count; @($Sim.Masked.incidents).Count | Should -BeGreaterThan 8
        @($Sim.Masked.sessions).Count | Should -Be @($Sim.Data.sessions).Count; @($Sim.Masked.procs).Count | Should -Be @($Sim.Data.procs).Count
        @($Sim.Masked.events).Count | Should -Be @($Sim.Data.events).Count; $Sim.Masked.meta.ticks | Should -Be $Sim.Data.meta.ticks
        $Sim.Masked.host.cpu.ToString() | Should -Be $Sim.Data.host.cpu.ToString()
        $Sim.ClearedAfter | Should -Be $Sim.Cleared                                        # Protect aendert die Eingabe nicht
    }
    It 'enthaelt keinen Namen der Aufzeichnung ausser in einem geschuetzten Wort' {
        $Sim.Mask.Entries.Count | Should -BeGreaterThan 20
        $exp = New-Object System.Collections.Generic.List[string]
        foreach ($x in 'server:SIM-VDA01=Server 01', 'server:ora01.sim.local=Server 02', 'domain:sim.local=Domäne 01', 'server:proxy.sim.local=Server 03', 'server:fs01.sim.local=Server 04') { $exp.Add($x) }
        for ($i = 1; $i -le 25; $i++) {
            $exp.Add(('user:user{0:000}=Benutzer {0:00}' -f $i)); if ($i -eq 1) { $exp.Add('domain:CONTOSO=Domäne 02') }; $exp.Add(('client:WS-{0}=Client {1:00}' -f (1037 + 37 * $i), $i))
        }
        foreach ($x in 'share:\\fs01\daten=Freigabe 01', 'server:fs01=Server 05', 'share:\\fs01\profile$=Freigabe 02', 'printer:PRN-EG-01=Drucker 01', 'printer:PRN-OG-02=Drucker 02') { $exp.Add($x) }
        @($Sim.Mask.Entries | ForEach-Object { '{0}:{1}={2}' -f $_.Kind, $_.Name, $_.Replacement }) | Should -Be $exp.ToArray()
        $Sim.MaskedJson | Should -Not -Match 'user0\d\d'; $Sim.MaskedJson | Should -Not -Match 'CONTOSO'; $Sim.MaskedJson | Should -Match 'Benutzer 01'
        $protected = @{}; foreach ($p in $Sim.Mask.Protected) { $protected[$p.ToLowerInvariant()] = $true }
        $strings = New-Object System.Collections.Generic.List[string]; Get-Strings $Sim.Masked $strings
        $left = New-Object System.Collections.Generic.List[string]
        foreach ($s in $strings) {
            foreach ($hit in $Sim.Mask.Regex.Matches($s)) {
                $a = $hit.Index; $b = $hit.Index + $hit.Length
                while ($a -gt 0 -and $s[$a - 1] -notmatch '[\s\\/()\[\],;:"''<>|=]') { $a-- }
                while ($b -lt $s.Length -and $s[$b] -notmatch '[\s\\/()\[\],;:"''<>|=]') { $b++ }
                $word = $s.Substring($a, $b - $a).ToLowerInvariant()
                if (-not $protected.ContainsKey($word) -and -not $protected.ContainsKey($word.TrimEnd('.'))) { $left.Add("$($hit.Value) in '$s'") }
            }
        }
        $left | Should -BeNullOrEmpty
    }
}
