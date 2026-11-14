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
        $m.Protected | Should -Contain 'EXCEL.EXE'; $m.Designations | Should -Contain 'DB'                # P2-R13: eine Bezeichnung
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
        foreach ($n in 'spoolsv.exe', 'Spooler', 'RpcSs', 'nexus.exe', 'nxreport.dll', 'LanmanWorkstation', 'HP Universal (Test)', 'HP', 'EXCEL.EXE') {
            $m.Protected | Should -Contain $n
        }
        # Aussage geaendert (P2-R13): Bezeichnungen der Gegenstellen und Rollen stehen getrennt von den geschuetzten Namen
        foreach ($n in 'DB', 'Datenbank', 'Microsoft Defender') { $m.Designations | Should -Contain $n; $m.Protected | Should -Not -Contain $n }
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
        # Aussage geaendert (P2-R13): fs01 ist der erste Teil von fs01.sim.local und derselbe Server
        Get-RunEntries $FxRun 'Alles' | Should -Be @('server:vda01=Server 01', 'client:PROXY01=Client 01', 'server:fs01.sim.local=Server 02', 'server:fs01=Server 02', 'domain:sim.local=Domäne 01',
            'server:ora.example=Server 03', 'address:10.0.0.5=Adresse 01', 'user:adm.anna=Benutzer 01', 'domain:KLINIK=Domäne 02', 'user:gast.user=Benutzer 02',
            'domain:KLINIK2=Domäne 03', 'user:otto=Benutzer 03', 'user:c.wagner=Benutzer 04', 'domain:klinik.example=Domäne 04',
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
        # Aussage geaendert (P2-R10): Schluessel werden nur in den Woerterbuechern der Liste WorkerPerfMaskKeyedMaps maskiert;
        # der Test nennt byUser und obj dort
        $old = $script:WorkerPerfMaskKeyedMaps
        try {
            $script:WorkerPerfMaskKeyedMaps = @('byUser', 'obj')
            $r = Protect-WorkerPerfReportData $d $m
        }
        finally { $script:WorkerPerfMaskKeyedMaps = $old }
        $r.meta.user | Should -Be 'Benutzer 01'; @($r.byUser.Keys) | Should -Be @('Benutzer 01', 'Benutzer 01 (2)'); $r.byUser['Benutzer 01 (2)'] | Should -Be 2
        $r.obj['Benutzer 01'] | Should -Be 'a Benutzer 01'; $r.series.ToString() | Should -Be '[1,2,null]'; $r.n | Should -Be 3.5; $r.list | Should -Be @('Benutzer 01', 7)
        @($r.Keys) | Should -Be @('meta', 'byUser', 'obj', 'series', 'n', 'list'); @($r.meta.Keys) | Should -Be @('user')
        @((Protect-WorkerPerfReportData $d $m).byUser.Keys) | Should -Be @('user1', 'Benutzer 01')                  # ohne Listeneintrag bleiben die Schluessel
    }
    It 'laesst Feldnamen und Schluesselwoerter stehen, auch wenn ein Benutzer so heisst' {                         # P2-R10
        $m = New-TestMask @('print', 'user', 'kind', 'crash', 'Sicherheit', 'cpu', 'anna')
        $d = [ordered]@{ print = [ordered]@{ drivers = @() }; quality = [ordered]@{ sources = @([ordered]@{ id = 'print.drivers'; label = 'print' }) }
            events = @([ordered]@{ kind = 'crash'; user = 'anna'; text = '' }); procs = @([ordered]@{ role = 'Sicherheit'; name = 'x.exe' })
            incidents = @([ordered]@{ lead = 'cpu'; resources = [string[]]@('cpu'); contributors = [ordered]@{ cpu = [ordered]@{ procs = @([ordered]@{ role = 'Sicherheit' }) } }; text = 'cpu von anna' }) }
        $r = Protect-WorkerPerfReportData $d $m
        @($r.Keys) | Should -Be @('print', 'quality', 'events', 'procs', 'incidents'); $r.quality.sources[0].id | Should -Be 'print.drivers'
        $r.quality.sources[0].label | Should -Be 'Benutzer 01'; @($r.events[0].Keys) | Should -Be @('kind', 'user', 'text'); $r.events[0].kind | Should -Be 'crash'
        $r.events[0].user | Should -Be 'Benutzer 07'; $r.procs[0].role | Should -Be 'Sicherheit'; $r.incidents[0].lead | Should -Be 'cpu'; $r.incidents[0].resources | Should -Be @('cpu')
        $r.incidents[0].contributors.Contains('cpu') | Should -BeTrue; $r.incidents[0].contributors.cpu.procs[0].role | Should -Be 'Sicherheit'
        $r.incidents[0].text | Should -Be 'Benutzer 06 von Benutzer 07'
    }
    It 'leert Meldungstexte und Befehlszeilen' {
        # Aussage geschaerft (Fix-Runde 1): jedes Feld mit eigenem Text und eigener Pruefung, auch meta.endMessage
        $d = [ordered]@{ meta = [ordered]@{ endMessage = 'geheim-ende' }; events = @([ordered]@{ text = 'geheim-ereignis' }); procs = @([ordered]@{ cmd = 'tool.exe /u geheim-cmd' })
            incidents = @([ordered]@{ text = 'bleibt'; events = @([ordered]@{ text = 'geheim-vorfall' }) }); before = [ordered]@{ near = @([ordered]@{ text = 'geheim-near' }); incidents = @() }
            quality = [ordered]@{ sourceErrors = @([ordered]@{ firstMessage = 'geheim-fehler' }) } }
        Clear-WorkerPerfReportFreeText $d
        ($d | ConvertTo-Json -Depth 6) | Should -Not -Match 'geheim'; $d.incidents[0].text | Should -Be 'bleibt'
        $d.meta.endMessage | Should -Be ''; $d.events[0].text | Should -Be ''; $d.procs[0].cmd | Should -Be ''; $d.incidents[0].events[0].text | Should -Be ''
        $d.before.near[0].text | Should -Be ''; $d.quality.sourceErrors[0].firstMessage | Should -Be ''
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
Describe 'Bezeichnungswort vor dem Ersatznamen' {                                              # fix round 4, C1 (ruling P3-R62)
    BeforeAll {
        function New-WordMask([string]$Level = 'Alles', [hashtable]$TextSet = $Texts) {
            $m = New-WorkerPerfMask -Path (Write-TestRun 'leer9' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }) -Level $Level -Texts $TextSet
            $kinds = $script:WorkerPerfMaskLevelKinds[$Level]
            $entries = @(@{ Kind = 'share'; Name = '\\fs01\daten'; Replacement = ($TextSet['mask.share'] -f 1) }, @{ Kind = 'server'; Name = 'fs01'; Replacement = 'Server 01' },
                @{ Kind = 'server'; Name = 'ps02'; Replacement = 'Druckserver 02' }, @{ Kind = 'user'; Name = 'user014'; Replacement = 'Benutzer 14' },
                @{ Kind = 'user'; Name = 'user015'; Replacement = 'Benutzer 15' }, @{ Kind = 'sid'; Name = 'S-1-5-21-1-2-3-1108'; Replacement = 'Konto 01' },
                @{ Kind = 'printer'; Name = 'PRN-EG-01'; Replacement = 'Drucker 01' }, @{ Kind = 'client'; Name = 'WS-0001'; Replacement = 'Client 01' }) | Where-Object { $kinds -contains $_.Kind }
            Set-WorkerPerfMaskNames -Mask $m -Entries $entries
            $m
        }
    }
    It 'laesst das Wort einmal stehen, wenn der Ersatzname mit demselben Wort beginnt: <Text>' -TestCases @(
        @{ Text = 'Freigabe \\fs01\daten'; Want = 'Freigabe 01' }
        @{ Text = 'Dateiserver-Engpass (Freigabe \\fs01\daten Spitze 82 ms, Soll unter 10 ms).'; Want = 'Dateiserver-Engpass (Freigabe 01 Spitze 82 ms, Soll unter 10 ms).' }
        @{ Text = 'Benutzer user014'; Want = 'Benutzer 14' }
        @{ Text = 'Server fs01'; Want = 'Server 01' }
        @{ Text = 'Messung auf Server fs01 am 13.11.2026'; Want = 'Messung auf Server 01 am 13.11.2026' }
        @{ Text = 'Benutzer user014, user015'; Want = 'Benutzer 14, Benutzer 15' }
        @{ Text = 'Konto S-1-5-21-1-2-3-1108 gesperrt'; Want = 'Konto 01 gesperrt' }
        @{ Text = 'Drucker PRN-EG-01 und Client WS-0001'; Want = 'Drucker 01 und Client 01' }
        @{ Text = "Server`tfs01"; Want = "Server`t01" }
    ) {
        Hide-WorkerPerfReportText $Text (New-WordMask) | Should -BeExactly $Want
    }
    It 'laesst stehen, was zwei verschiedene Dinge nennt oder nicht direkt aufeinander folgt: <Text>' -TestCases @(
        @{ Text = 'Server ps02'; Want = 'Server Druckserver 02' }                       # another kind of server
        @{ Text = 'Druckserver fs01'; Want = 'Druckserver Server 01' }                  # the word is the end of a longer word
        @{ Text = 'Datei-Server fs01'; Want = 'Datei-Server Server 01' }                # the second part of a compound
        @{ Text = 'Server \\fs01\daten'; Want = 'Server Freigabe 01' }                 # a share on a server
        @{ Text = 'Freigabe fs01'; Want = 'Freigabe Server 01' }
        @{ Text = 'Benutzer: user014.'; Want = 'Benutzer: Benutzer 14.' }                # a label and its value
        @{ Text = 'Benutzer (user014)'; Want = 'Benutzer (Benutzer 14)' }
        @{ Text = "Benutzer`nuser014"; Want = "Benutzer`nBenutzer 14" }                 # two lines
        @{ Text = 'benutzer user014'; Want = 'benutzer Benutzer 14' }                   # not the word of the alias
        @{ Text = 'user014 user015'; Want = 'Benutzer 14 Benutzer 15' }
        @{ Text = 'user014'; Want = 'Benutzer 14' }                                     # the whole text is the name
        @{ Text = 'Sitzung von user014 auf fs01'; Want = 'Sitzung von Benutzer 14 auf Server 01' }
    ) {
        Hide-WorkerPerfReportText $Text (New-WordMask) | Should -BeExactly $Want
    }
    It 'nimmt die Woerter aus den Mustern der Ersatznamen, nicht aus einer eigenen Liste' {
        $m = New-WordMask
        $m.AliasWords | Should -Be @('Benutzer', 'Client', 'Konto', 'Server', 'Freigabe', 'Domäne', 'Adresse', 'Drucker')
        @($script:WorkerPerfMaskLevelKinds['Alles'] | ForEach-Object { ($Texts['mask.' + $_] -split ' ')[0] }) | Should -Be $m.AliasWords
        (New-WordMask 'Personen').AliasWords | Should -Be @('Benutzer', 'Client', 'Konto')
        # another pattern, another word: the old word is no designation any more
        $other = @{}; foreach ($k in $Texts.Keys) { $other[$k] = $Texts[$k] }; $other['mask.share'] = 'Netzordner {0:00}'
        $n = New-WordMask 'Alles' $other
        $n.AliasWords | Should -Contain 'Netzordner'; $n.AliasWords | Should -Not -Contain 'Freigabe'
        Hide-WorkerPerfReportText 'Netzordner \\fs01\daten' $n | Should -BeExactly 'Netzordner 01'
        Hide-WorkerPerfReportText 'Freigabe \\fs01\daten' $n | Should -BeExactly 'Freigabe Netzordner 01'
        # a pattern without a word before the number gives none
        $other['mask.share'] = '{0:00}. Freigabe'; (New-WordMask 'Alles' $other).AliasWords | Should -Not -Contain 'Freigabe'
        # a word that is itself a name of the capture is replaced and so is no designation before the next name
        $named = New-WordMask
        Set-WorkerPerfMaskNames -Mask $named -Entries @(@{ Kind = 'user'; Name = 'Server'; Replacement = 'Benutzer 01' }, @{ Kind = 'server'; Name = 'fs01'; Replacement = 'Server 01' },
            @{ Kind = 'user'; Name = 'user014'; Replacement = 'Benutzer 14' })
        Hide-WorkerPerfReportText 'Server fs01, Benutzer user014' $named | Should -BeExactly 'Benutzer 01 Server 01, Benutzer 14'
        # a mask without the words (set by hand) replaces as before
        $bare = New-WordMask; $bare.Remove('AliasWords'); Set-WorkerPerfMaskNames -Mask $bare -Entries @(@{ Kind = 'user'; Name = 'user014'; Replacement = 'Benutzer 14' })
        Hide-WorkerPerfReportText 'Benutzer user014' $bare | Should -BeExactly 'Benutzer Benutzer 14'
    }
    It 'wendet die Regel auf gebildete Texte an, nie auf Schluessel, und bei Personen nur auf deren Namen' {
        $m = New-WordMask
        $d = [ordered]@{ label = 'Freigabe \\fs01\daten'; map = [ordered]@{ 'Benutzer user014' = 'Benutzer user014' }; list = [string[]]@('Server fs01', 'fs01') }
        $old = $script:WorkerPerfMaskKeyedMaps
        try { $script:WorkerPerfMaskKeyedMaps = @('map'); $r = Protect-WorkerPerfReportData $d $m } finally { $script:WorkerPerfMaskKeyedMaps = $old }
        $r.label | Should -BeExactly 'Freigabe 01'; $r.list | Should -Be @('Server 01', 'Server 01')
        @($r.map.Keys) | Should -Be @('Benutzer Benutzer 14'); $r.map['Benutzer Benutzer 14'] | Should -BeExactly 'Benutzer 14'
        # the same text as a value after it was a key, and the other way round: neither takes the other's result
        Hide-WorkerPerfReportText 'Benutzer user014' $m | Should -BeExactly 'Benutzer 14'
        $p = New-WordMask 'Personen'
        Hide-WorkerPerfReportText 'Benutzer user014 auf Server fs01, Freigabe \\fs01\daten' $p | Should -BeExactly 'Benutzer 14 auf Server fs01, Freigabe \\fs01\daten'
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
Describe 'Fix-Runde 1: Vorrang der Namen, unbekannte Objekte, UNC-Server im Satz' {
    BeforeAll {
        function New-FixMask([object[]]$Entries, [string[]]$Protected = @(), [string]$Level = 'Alles') {
            $m = New-WorkerPerfMask -Path (Write-TestRun 'leer4' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }) -Level $Level -Texts $Texts
            Set-WorkerPerfMaskNames -Mask $m -Entries $Entries -Protected $Protected
            $m
        }
    }
    It 'ersetzt einen Benutzer, der wie ein geschuetzter Name heisst; eine Wendung mit dem Namen schuetzt ihn weiter' {   # P2-R9
        $driver = 'HP Universal Printing PCL 6 (v7.0.1)'
        $m = New-FixMask @(@{ Kind = 'user'; Name = 'hp'; Replacement = 'Benutzer 01' }, @{ Kind = 'user'; Name = 'spooler'; Replacement = 'Benutzer 02' }) @('HP', $driver, 'Spooler', 'spoolsv.exe')
        $m.Protected | Should -Not -Contain 'HP'; $m.Protected | Should -Not -Contain 'Spooler'; $m.Protected | Should -Contain $driver
        $r = Protect-WorkerPerfReportData ([ordered]@{ sessions = @([ordered]@{ user = 'hp' }); text = "Benutzer: hp. Treiber $driver"; d = $driver }) $m
        $r.sessions[0].user | Should -Be 'Benutzer 01'; $r.text | Should -Be "Benutzer: Benutzer 01. Treiber $driver"; $r.d | Should -Be $driver
        Hide-WorkerPerfReportText 'HP' $m | Should -Be 'Benutzer 01'
        Hide-WorkerPerfReportText 'Dienst Spooler beendet (spoolsv.exe), Sitzung von SPOOLER' $m | Should -Be 'Dienst Benutzer 02 beendet (spoolsv.exe), Sitzung von Benutzer 02'
    }
    It 'gibt unbekannte Objekte nur maskiert als Text weiter und laesst Zahlen, Zeiten, Aufzaehlungen und Guids unveraendert' {
        $m = New-FixMask @(@{ Kind = 'user'; Name = 'anna'; Replacement = 'Benutzer 01' }) @() 'Personen'
        $g = [guid]'0f8fad5b-d9cb-469f-a165-70867728950e'; $ts = [timespan]::FromMinutes(5); $dto = [DateTimeOffset]'2026-01-15T08:00:00+01:00'
        $r = Protect-WorkerPerfReportData ([ordered]@{ u = [uri]'file://server/anna'; f = [IO.FileInfo]'/x/anna.txt'; v = [version]'1.2'
                g = $g; ts = $ts; dto = $dto; e = [DayOfWeek]::Monday; m = [decimal]1.5; c = [char]'a' }) $m
        $r.u | Should -Be 'file://server/Benutzer 01'; $r.u | Should -BeOfType [string]; $r.f | Should -Be '/x/Benutzer 01.txt'; $r.v | Should -Be '1.2'
        $r.g | Should -BeOfType [guid]; $r.g | Should -Be $g; $r.ts | Should -BeOfType [timespan]; $r.ts | Should -Be $ts
        $r.dto | Should -BeOfType [DateTimeOffset]; $r.dto | Should -Be $dto; $r.e | Should -BeOfType [DayOfWeek]; $r.e | Should -Be ([DayOfWeek]::Monday)
        $r.m | Should -BeOfType [decimal]; $r.c | Should -BeOfType [char]
    }
    It 'nimmt Klammern, Anfuehrungszeichen und den Satzpunkt nicht in den UNC-Server' -TestCases @(
        @{ Text = '(\\fs01)'; Known = '(\\Server 01)'; Unknown = '(\\(Name entfernt))' }
        @{ Text = "'\\fs01\upm$'"; Known = "'\\Server 01\upm$'"; Unknown = "'\\(Name entfernt)\upm$'" }
        @{ Text = '[\\fs01]'; Known = '[\\Server 01]'; Unknown = '[\\(Name entfernt)]' }
        @{ Text = 'auf \\fs01.'; Known = 'auf \\Server 01.'; Unknown = 'auf \\(Name entfernt).' }
        @{ Text = 'auf \\fs01.sim.local.'; Known = 'auf \\(Name entfernt).'; Unknown = 'auf \\(Name entfernt).' }
    ) {
        $withServer = New-FixMask @(@{ Kind = 'server'; Name = 'fs01'; Replacement = 'Server 01' })
        Hide-WorkerPerfReportText $Text $withServer | Should -Be $Known
        $otherServer = New-FixMask @(@{ Kind = 'server'; Name = 'nas99'; Replacement = 'Server 01' })
        Hide-WorkerPerfReportText $Text $otherServer | Should -Be $Unknown
    }
}
Describe 'WebDAV-Pfade' {
    It 'nimmt den Server ohne @SSL und Port auf und ersetzt ihn im Text mit seinem Ersatznamen' {
        $p = Write-TestRun 'mask-dav' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'sessions.csv' = $null; 'shares.csv' = $null; 'volumes.csv' = $null; 'probes.csv' = $null
            'procinfo.csv' = @('0,100,1,x.exe,2,,\\dav01@SSL@8443\apps\x.exe,,', '1,101,1,y.exe,2,,\\dav02@443\tools\y.exe,,') }
        Get-RunEntries $p 'Alles' | Should -Be @('server:T1=Server 01', 'server:h=Server 02', 'share:\\dav01@SSL@8443\apps=Freigabe 01', 'server:dav01=Server 03',
            'share:\\dav02@443\tools=Freigabe 02', 'server:dav02=Server 04')
        $m = New-WorkerPerfMask -Path $p -Level 'Alles' -Texts $Texts
        Hide-WorkerPerfReportText 'C:\x und \\dav01@SSL@8443\andere\z.txt und \\DAV02@443\apps' $m | Should -Be 'C:\x und \\Server 03@SSL@8443\andere\z.txt und \\Server 04@443\apps'
        Hide-WorkerPerfReportText '\\dav01@SSL@8443\apps\x.exe und \\dav09@SSL\q' $m | Should -Be 'Freigabe 01\x.exe und \\(Name entfernt)@SSL\q'
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
Describe 'Vermerk einer weggelassenen Kategorie' {                                     # Messkategorien Task 3
    It 'laesst nur den festen Vermerk des Collectors stehen, nie einen Text der Quelle, der ihn enthaelt' {
        $src = { param($id, $detail) [ordered]@{ id = $id; available = $false; detail = $detail } }
        # Fix-Runde 1 (Minor 3): auch falsche Schreibweise, eine nicht aktive Kategorie, doppelte Namen und eine andere Reihenfolge
        # Aussage angepasst (Zustandsbild, Task 8): Zustand ist aktiv, sein Vermerk ist gueltig
        $good = @('abgeschaltet (-Skip Prozesse)', 'abgeschaltet (-Skip Ereignisse,Rueckblick)', 'abgeschaltet (-Skip Gegenstellen)', 'abgeschaltet (-Skip Zustand)')
        $texts = $good + @('abgeschaltet (-Skip prozesse)', 'abgeschaltet (-Skip Prozesse,Prozesse)', 'abgeschaltet (-Skip Rueckblick,Ereignisse)',
            'abgeschaltet (-Skip Ereignisse,Rueckblick,Rueckblick)', 'abgeschaltet (-Skip GEGENSTELLEN)',
            'Zugriff verweigert fuer geheim01: abgeschaltet (-Skip Prozesse)', 'abgeschaltet (-Skip Prozesse) von geheim02', 'Abgeschaltet (-Skip Prozesse)',
            "abgeschaltet (-Skip Prozesse)`ngeheim03", "abgeschaltet (-Skip Prozesse)`n", 'abgeschaltet (-Skip Geheimname)', 'abgeschaltet (-Skip Prozesse,Geheimname)')
        $ids = @(0..($texts.Count - 1) | ForEach-Object { "src$_" })
        $d = [ordered]@{ quality = [ordered]@{ sources = @(0..($texts.Count - 1) | ForEach-Object { & $src $ids[$_] $texts[$_] }) }
            sollIst = @(0..($texts.Count - 1) | ForEach-Object { [ordered]@{ id = $ids[$_]; detail = $texts[$_] } }) }
        Clear-WorkerPerfReportFreeText $d
        $kept = $good + @('') * ($texts.Count - $good.Count)
        @($d.quality.sources | ForEach-Object { $_.detail }) | Should -Be $kept
        @($d.sollIst | ForEach-Object { $_.detail }) | Should -Be $kept
    }
}
Describe 'Abschlussrunde: Profilordner, Hostnamen, Bezeichnungen und weitere Pfade' {
    BeforeAll {
        function Get-FixRun([string]$Name, [hashtable]$Files, [string]$Meta = $null) {
            $all = @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'sessions.csv' = $null; 'shares.csv' = $null; 'volumes.csv' = $null; 'probes.csv' = $null }
            foreach ($k in $Files.Keys) { $all[$k] = $Files[$k] }
            $p = Write-TestRun $Name $all
            if ($Meta) { [IO.File]::WriteAllText((Join-Path $p 'meta.json'), $Meta) }
            $p
        }
        $script:NoEndpoints = '{"SchemaVersion":3,"Computer":"vda01","Endpoints":[],"Sources":{},"SourceErrors":{}}'
    }
    It 'nimmt einen Profilordner mit Domaene oder Nummer als denselben Benutzer und Ordner ohne Person als keinen' {   # P2-R14
        $p = Get-FixRun 'mask-profiles' @{ 'sessions.csv' = @('0,2,mueller,KLINIK,Active,ICA-1,WS-0001,,0')
            'procinfo.csv' = @('0,100,1,a.exe,2,,C:\Users\mueller.KLINIK\AppData\a.exe,,', '1,101,1,b.exe,2,,C:\Users\mueller.KLINIK.001\b.exe,,',
                '2,102,1,c.exe,2,,D:\Users\anna.003\c.exe,,', '3,103,1,d.exe,2,,C:\Users\TEMP\d.exe,,', '4,104,1,e.exe,2,,C:\Users\TEMP.KLINIK\e.exe,,',
                '5,105,1,f.exe,2,,C:\Users\TEMP.KLINIK.002\f.exe,,', '6,106,1,g.exe,2,,C:\Users\defaultuser0\g.exe,,', '7,107,1,h.exe,2,,C:\Users\DefaultAppPool\h.exe,,',
                '8,108,1,i.exe,2,,C:\Users\.NET v4.5 Classic\i.exe,,', '9,109,1,j.exe,2,,C:\Users\hans.FREMD\j.exe,,') } $NoEndpoints
        Get-RunEntries $p 'Alles' | Should -Be @('server:vda01=Server 01', 'user:mueller=Benutzer 01', 'domain:KLINIK=Domäne 01', 'client:WS-0001=Client 01',
            'user:anna=Benutzer 02', 'user:hans.FREMD=Benutzer 03')
        $personen = New-WorkerPerfMask -Path $p -Level 'Personen' -Texts $Texts; $alles = New-WorkerPerfMask -Path $p -Level 'Alles' -Texts $Texts
        Hide-WorkerPerfReportText 'C:\Users\mueller.KLINIK\AppData\a.exe' $personen | Should -Be 'C:\Users\Benutzer 01.KLINIK\AppData\a.exe'
        Hide-WorkerPerfReportText 'C:\Users\mueller.KLINIK.001\b.exe' $alles | Should -Be 'C:\Users\Benutzer 01.Domäne 01.001\b.exe'
        Hide-WorkerPerfReportText 'C:\Users\TEMP\d.exe und C:\Temp\x' $alles | Should -Be 'C:\Users\TEMP\d.exe und C:\Temp\x'
    }
    It 'nimmt den ersten Teil eines vollstaendigen Hostnamens als denselben Server, aber kein Wort des Berichts und keine Domaene' {   # P2-R13
        $meta = '{"SchemaVersion":3,"Computer":"vda01","Sources":{},"SourceErrors":{},"Endpoints":[{"Name":"Dateiserver fs01","Host":"fs01.sim.local","Port":445,"Role":"Dateiserver"},' +
            '{"Name":"ORA01","Host":"ora01.sim.local","Port":1521,"Role":"Datenbank"},{"Name":"Proxy","Host":"proxy.sim.local","Port":8080,"Role":"Proxy"},' +
            '{"Name":"Web","Host":"klinik.sim.local","Port":443,"Role":"Web"},{"Name":"Portal","Host":"portal.example","Port":443,"Role":"Web"}]}'
        $p = Get-FixRun 'mask-fqdn' @{ 'sessions.csv' = @('0,2,anna,KLINIK,Active,ICA-1,WS-0001,,0'); 'shares.csv' = @('0,\\nas07\daten,1,1,5,5,1,1'); 'probes.csv' = @('0,Ablage,Dateiserver,NAS07.sim.local,445,2,') } $meta
        Get-RunEntries $p 'Alles' | Should -Be @('server:vda01=Server 01', 'server:fs01.sim.local=Server 02', 'server:fs01=Server 02', 'domain:sim.local=Domäne 01',
            'server:ora01.sim.local=Server 03', 'server:ora01=Server 03', 'server:proxy.sim.local=Server 04', 'server:klinik.sim.local=Server 05', 'domain:klinik=Domäne 02',
            'server:portal.example=Server 06', 'user:anna=Benutzer 01', 'client:WS-0001=Client 01', 'share:\\nas07\daten=Freigabe 01', 'server:nas07=Server 07', 'server:NAS07.sim.local=Server 07')
        $m = New-WorkerPerfMask -Path $p -Level 'Alles' -Texts $Texts
        Hide-WorkerPerfReportText 'Dateiserver fs01' $m | Should -Be 'Dateiserver Server 02'
        Hide-WorkerPerfReportText 'ORA01' $m | Should -Be 'Server 03'
        Hide-WorkerPerfReportText 'Proxy und Proxyserver' $m | Should -Be 'Proxy und Proxyserver'
        Hide-WorkerPerfReportText 'nas07 und nas07.sim.local' $m | Should -Be 'Server 07 und Server 07'
    }
    It 'laesst eine Bezeichnung nur einen Namen schuetzen, der Teil eines laengeren Wortes ist' {   # P2-R13
        $m = New-WorkerPerfMask -Path (Write-TestRun 'leer5' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }) -Level 'Alles' -Texts $Texts
        Set-WorkerPerfMaskNames -Mask $m -Entries @(@{ Kind = 'user'; Name = 'oracle'; Replacement = 'Benutzer 01' }, @{ Kind = 'server'; Name = 'fs01'; Replacement = 'Server 01' },
            @{ Kind = 'user'; Name = 'nexus'; Replacement = 'Benutzer 02' }, @{ Kind = 'user'; Name = 'hp'; Replacement = 'Benutzer 03' }) `
            -Protected @('HP Universal Printing PCL 6 (v7.0.1)') -Designations @('Oracle-Listener', 'Oracle-Listener Haus 2', 'Dateiserver fs01', 'Nexus KIS', 'fs01')
        Hide-WorkerPerfReportText 'Oracle-Listener (oracle)' $m | Should -Be 'Oracle-Listener (Benutzer 01)'
        Hide-WorkerPerfReportText 'Oracle-Listener Haus 2' $m | Should -Be 'Oracle-Listener Haus 2'
        Hide-WorkerPerfReportText 'Gegenstelle Dateiserver fs01 langsam' $m | Should -Be 'Gegenstelle Dateiserver Server 01 langsam'
        Hide-WorkerPerfReportText 'Nexus KIS' $m | Should -Be 'Benutzer 02 KIS'
        Hide-WorkerPerfReportText 'Treiber HP Universal Printing PCL 6 (v7.0.1)' $m | Should -Be 'Treiber HP Universal Printing PCL 6 (v7.0.1)'
        $m.Designations | Should -Not -Contain 'fs01'; $m.Shadowed | Should -Not -Contain 'fs01'           # ersetzt, nicht entstellt
    }
    It 'laesst eine Bezeichnung keinen Namen schuetzen, den nur Alles ersetzt: <Text>' -TestCases @(          # P2-R13 praezisiert
        @{ Text = 'Dateiserver-fs01'; Alles = 'Dateiserver-Server 01' }, @{ Text = 'Dateiserver fs01'; Alles = 'Dateiserver Server 01' }
        @{ Text = 'fs01 (Dateiserver)'; Alles = 'Server 01 (Dateiserver)' }, @{ Text = 'FS01/Profile'; Alles = 'Server 01/Profile' }
    ) {
        $m = New-WorkerPerfMask -Path (Write-TestRun 'leer8' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }) -Level 'Alles' -Texts $Texts
        Set-WorkerPerfMaskNames -Mask $m -Entries @(@{ Kind = 'server'; Name = 'fs01'; Replacement = 'Server 01' }, @{ Kind = 'user'; Name = 'oracle'; Replacement = 'Benutzer 01' }) `
            -Designations @('Dateiserver-fs01', 'Dateiserver fs01', 'fs01 (Dateiserver)', 'FS01/Profile', 'Oracle-Listener', 'Oracle-Listener Haus 2')
        Hide-WorkerPerfReportText $Text $m | Should -Be $Alles
        Hide-WorkerPerfReportText 'Oracle-Listener (oracle), Oracle-Listener Haus 2' $m | Should -Be 'Oracle-Listener (Benutzer 01), Oracle-Listener Haus 2'
    }
    It 'ersetzt den ersten Teil eines Hostnamens auch im Wort einer Bezeichnung, einen gleichnamigen Benutzer nicht' {   # P2-R13 praezisiert
        $meta = '{"SchemaVersion":3,"Computer":"vda01","Sources":{},"SourceErrors":{},"Endpoints":[{"Name":"Oracle-Listener","Host":"oracle.sim.local","Port":1521,"Role":"Datenbank"}]}'
        $host1 = Get-FixRun 'mask-oracle-host' @{} $meta
        Get-RunEntries $host1 'Alles' | Should -Be @('server:vda01=Server 01', 'server:oracle.sim.local=Server 02', 'server:oracle=Server 02', 'domain:sim.local=Domäne 01')
        Hide-WorkerPerfReportText 'Oracle-Listener auf oracle.sim.local' (New-WorkerPerfMask -Path $host1 -Level 'Alles' -Texts $Texts) | Should -Be 'Server 02-Listener auf Server 02'
        Hide-WorkerPerfReportText 'Oracle-Listener auf oracle.sim.local' (New-WorkerPerfMask -Path $host1 -Level 'Personen' -Texts $Texts) | Should -Be 'Oracle-Listener auf oracle.sim.local'
        # a user of the same name wins over the server (P2-R5): a person, whom the designation shields at both levels
        $pair = Get-FixRun 'mask-oracle-pair' @{ 'sessions.csv' = @('0,2,oracle,KLINIK,Active,ICA-1,WS-0001,,0') } $meta
        Get-RunEntries $pair 'Alles' | Should -Be @('server:vda01=Server 01', 'server:oracle.sim.local=Server 02', 'user:oracle=Benutzer 01', 'domain:sim.local=Domäne 01',
            'domain:KLINIK=Domäne 02', 'client:WS-0001=Client 01')
        foreach ($level in 'Personen', 'Alles') {
            $exp = $(if ($level -eq 'Alles') { 'Oracle-Listener auf Server 02, Sitzung von Benutzer 01' } else { 'Oracle-Listener auf Benutzer 01.sim.local, Sitzung von Benutzer 01' })   # ein Personenname auch im Hostnamen
            Hide-WorkerPerfReportText 'Oracle-Listener auf oracle.sim.local, Sitzung von oracle' (New-WorkerPerfMask -Path $pair -Level $level -Texts $Texts) | Should -Be $exp -Because $level
        }
    }
    It 'nimmt aus einem Containerpfad Server und Freigabe des UNC-Anfangs und den Benutzer aus dem Pfad' {     # Nachtrag
        $p = Get-FixRun 'mask-backing' @{ 'volumes.csv' = @('0,HarddiskVolume19,profile,2,\\fs01\fslogix\S-1-5-21-1-2-3-1105_user010\Profile_user010.VHDX,1,1,5,5,1,1,0',
                '0,HarddiskVolume20,profile,2,\\fs02\upm$,1,1,5,5,1,1,0') } $NoEndpoints
        Get-RunEntries $p 'Alles' | Should -Be @('server:vda01=Server 01', 'share:\\fs01\fslogix=Freigabe 01', 'server:fs01=Server 02', 'share:\\fs02\upm$=Freigabe 02', 'server:fs02=Server 03',
            'sid:S-1-5-21-1-2-3-1105=Konto 01', 'user:user010=Benutzer 01')
        Hide-WorkerPerfReportText '\\fs01\fslogix\S-1-5-21-1-2-3-1105_user010\Profile_user010.VHDX' (New-WorkerPerfMask -Path $p -Level 'Alles' -Texts $Texts) |
            Should -Be 'Freigabe 01\Konto 01_Benutzer 01\Profile_Benutzer 01.VHDX'
    }
    It 'nimmt ein Konto-SID mit angehaengtem Namen und den Namen dazu auf' {                     # Minor 9
        $p = Get-FixRun 'mask-fslogix' @{ 'volumes.csv' = @('0,HarddiskVolume19,profile,2,\\fs01\fslogix\S-1-5-21-1-2-3-1105_user010\Profile_user010.VHDX,1,1,5,5,1,1,0',
                '0,HarddiskVolume20,profile,2,\\fs01\fslogix\ottokar.hahn_S-1-5-21-1-2-3-1190\Profile_ottokar.hahn.VHDX,1,1,5,5,1,1,0') } $NoEndpoints
        Get-RunEntries $p 'Personen' | Should -Be @('sid:S-1-5-21-1-2-3-1105=Konto 01', 'user:user010=Benutzer 01', 'sid:S-1-5-21-1-2-3-1190=Konto 02', 'user:ottokar.hahn=Benutzer 02')
        Hide-WorkerPerfReportText '\\fs01\fslogix\S-1-5-21-1-2-3-1105_user010\Profile_user010.VHDX' (New-WorkerPerfMask -Path $p -Level 'Personen' -Texts $Texts) |
            Should -Be '\\fs01\fslogix\Konto 01_Benutzer 01\Profile_Benutzer 01.VHDX'
    }
    It 'nimmt in reinen Pfadfeldern eine Freigabe mit Leerzeichen und den WebDAV-Server einer Freigabe ganz auf' {   # Minor 5, 6
        $p = Get-FixRun 'mask-share-space' @{ 'shares.csv' = @('0,\\dav03@SSL@8443\docs,1,1,5,5,1,1'); 'procinfo.csv' = @('0,100,1,x.exe,2,,\\fs01\Abteilung Kardiologie\x.exe,,') } $NoEndpoints
        Get-RunEntries $p 'Alles' | Should -Be @('server:vda01=Server 01', 'share:\\dav03@SSL@8443\docs=Freigabe 01', 'server:dav03=Server 02',
            'share:\\fs01\Abteilung Kardiologie=Freigabe 02', 'server:fs01=Server 03')
        Hide-WorkerPerfReportText '\\fs01\Abteilung Kardiologie\x.exe' (New-WorkerPerfMask -Path $p -Level 'Alles' -Texts $Texts) | Should -Be 'Freigabe 02\x.exe'
    }
    It 'nimmt den Benutzer einer ICA-Instanz auch mit Klammern im Namen' {                        # Minor 7
        $p = Get-FixRun 'mask-ica' @{ 'citrix.csv' = @('0,ICA,2,ICA-CGP 77 (Meier (Extern)),Latency,5', '0,ICA,3,ICA-CGP 78 (KLINIK\ilse.igel),Latency,5') } $NoEndpoints
        Get-RunEntries $p 'Personen' | Should -Be @('user:Meier (Extern)=Benutzer 01', 'user:ilse.igel=Benutzer 02')
        Hide-WorkerPerfReportText 'ICA-CGP 77 (Meier (Extern))' (New-WorkerPerfMask -Path $p -Level 'Personen' -Texts $Texts) | Should -Be 'ICA-CGP 77 (Benutzer 01)'
    }
    It 'sucht in Anwendung und Modul eines Ereignisses Benutzerordner und schuetzt nur den Dateinamen' {   # Minor 4
        $p = Get-FixRun 'mask-evpath' @{} $NoEndpoints
        [IO.File]::WriteAllLines((Join-Path $p 'events.csv'), @($WorkerPerfHeaders['events.csv'],
                (New-EventLine 10 'app' 'C:\Users\zoe.zimmer\AppData\tool\tool.exe' 'C:\Users\zoe.zimmer\AppData\tool\plugin.dll' '' '' '' '' '' '')))
        $m = New-WorkerPerfMask -Path $p -Level 'Personen' -Texts $Texts
        @($m.Entries | ForEach-Object { $_.Name }) | Should -Be @('zoe.zimmer')
        $m.Protected | Should -Contain 'tool.exe'; $m.Protected | Should -Contain 'plugin.dll'; @($m.Protected | Where-Object { $_ -like '*\*' }) | Should -BeNullOrEmpty
        Hide-WorkerPerfReportText 'Absturz von C:\Users\zoe.zimmer\AppData\tool\tool.exe' $m | Should -Be 'Absturz von C:\Users\Benutzer 01\AppData\tool\tool.exe'
    }
    It 'vergleicht die Namen ordinal, unabhaengig von der Kultur' {                                # Minor 2
        $p = Get-FixRun 'mask-ordinal' @{ 'sessions.csv' = @("0,2,wei$([char]0xDF),KLINIK,Active,ICA-1,,,0", '0,3,weiss,KLINIK,Active,ICA-2,,,0') } $NoEndpoints
        Get-RunEntries $p 'Personen' | Should -Be @("user:wei$([char]0xDF)=Benutzer 01", 'user:weiss=Benutzer 02')
        $m = New-WorkerPerfMask -Path $p -Level 'Personen' -Texts $Texts
        $comparer = [System.Collections.Hashtable].GetProperty('EqualityComparer', [Reflection.BindingFlags]'NonPublic, Instance').GetValue($m.Lookup)
        $comparer | Should -Be ([StringComparer]::Ordinal)
    }
    It 'laesst Einheiten und Verweise stehen, auch wenn ein Benutzer so heisst' {                  # P2-R12
        $m = New-WorkerPerfMask -Path (Write-TestRun 'leer6' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }) -Level 'Personen' -Texts $Texts
        Set-WorkerPerfMaskNames -Mask $m -Entries @(@{ Kind = 'user'; Name = 'ms'; Replacement = 'Benutzer 01' }, @{ Kind = 'user'; Name = 'citrix'; Replacement = 'Benutzer 02' })
        $r = Protect-WorkerPerfReportData ([ordered]@{ thresholds = @([ordered]@{ unit = 'ms'; url = 'https://docs.citrix.com/x'; ideal = 'unter 150 ms' }); sessions = @([ordered]@{ user = 'ms' }) }) $m
        $r.thresholds[0].unit | Should -Be 'ms'; $r.thresholds[0].url | Should -Be 'https://docs.citrix.com/x'; $r.thresholds[0].ideal | Should -Be 'unter 150 Benutzer 01'; $r.sessions[0].user | Should -Be 'Benutzer 01'
    }
    It 'nennt die Ersatznamen der Namen, die Woertern des Berichts gleichen, nie die echten Namen' {   # P2-R12
        $m = New-WorkerPerfMask -Path (Write-TestRun 'leer7' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines }) -Level 'Personen' -Texts $Texts
        Set-WorkerPerfMaskNames -Mask $m -Entries @(@{ Kind = 'user'; Name = 'anna'; Replacement = 'Benutzer 01' }, @{ Kind = 'user'; Name = 'soll'; Replacement = 'Benutzer 02' },
            @{ Kind = 'user'; Name = 's'; Replacement = 'Benutzer 03' }, @{ Kind = 'user'; Name = 'hp'; Replacement = 'Benutzer 04' }) -Protected @('HP', 'nexus.exe')
        @(Get-WorkerPerfMaskVocabularyHits -Mask $m -Texts @{ a = 'Soll unter {0}'; b = 'kein Treffer' } -Units @('1/s', '%')) | Should -Be @('Benutzer 02', 'Benutzer 03', 'Benutzer 04')
        @(Get-WorkerPerfMaskVocabularyHits -Mask $m -Texts @{ a = 'nichts' }) | Should -Be @('Benutzer 04')
    }
}
Describe 'Namen aus health.json: Typzusaetze und Grenzfaelle' {                                     # Task 15, ZB-R27
    BeforeAll {
        function Write-HealthFile([string]$Dir, [hashtable]$Values) {
            # health.json with the given values (id -> @{ State; Reason; Value }), each in the area of its id
            $areas = [ordered]@{}
            foreach ($id in $Values.Keys) {
                $a = $id.Split('.')[0]
                if (-not $areas.Contains($a)) { $areas[$a] = [ordered]@{ Status = 'read'; DurationMs = 0; Error = ''; Values = [ordered]@{} } }
                $areas[$a]['Values'][$id] = $Values[$id]
            }
            $json = [ordered]@{ FormatVersion = 1; ReadAt = '2026-11-12T10:00:00.0000000+01:00'; DurationMs = 0; Areas = $areas } | ConvertTo-Json -Depth 12
            [IO.File]::WriteAllText((Join-Path $Dir 'health.json'), $json)
        }
        function New-Read($Value) { [ordered]@{ State = 'read'; Reason = ''; Value = $Value } }
        $script:HealthRun = Write-TestRun 'mask-health' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'sessions.csv' = $null; 'shares.csv' = $null; 'volumes.csv' = $null
            'probes.csv' = $null; 'events.csv' = $null }
        $script:HealthValues = @{
            # :path (WinStation), :user with the domain of the same entry, :domain, :client; an entry that is no record; null and empty fields
            'sessions.list' = New-Read @([ordered]@{ Id = 1; State = 'Active'; WinStation = 'ICA-CGP#1'; User = 'hu.eins'; Domain = 'HDOM'; Client = 'HWS-01' }, 'kein Eintrag',
                [ordered]@{ Id = 2; State = 'Active'; WinStation = ''; User = 'HDOM2\hu.zwei'; Domain = ''; Client = '' },
                [ordered]@{ Id = 3; State = 'Active'; WinStation = $null; User = $null; Domain = $null; Client = $null })
            # :path: a user folder; the folders of the built-in account belong to no person
            'sessions.localProfiles' = New-Read @([ordered]@{ Path = 'C:\Users\hu.vier' }, [ordered]@{ Path = 'C:\Users\Administrator' }, [ordered]@{ Path = 'C:\Users\administrator.HDOM' })
            # :host: a full host name, an IPv6 address with zone index, a host name with a trailing dot, empty, null, a number
            'vda.controllers' = New-Read @([ordered]@{ Entry = 'hddc1.edge.test'; Kind = 'fqdn'; From = 'policy' }, [ordered]@{ Entry = 'fe80::1%12'; Kind = 'ip'; From = 'policy' },
                [ordered]@{ Entry = 'hddc2.edge.test.'; Kind = 'fqdn'; From = 'policy' }, [ordered]@{ Entry = ''; Kind = ''; From = '' }, [ordered]@{ Entry = $null; Kind = ''; From = '' }, 7)
            'vda.policyRaw' = New-Read @([ordered]@{ Key = 'ICAPolicies'; Name = 'Drucker'; Value = '\\hfree1\Etage' })     # :free
            'vda.persistentDataLocation' = [ordered]@{ State = 'absent'; Reason = ''; Value = '\\habsent\daten' }              # not read
            'vda.wemServices' = New-Read @([ordered]@{ Name = 'HEdgeService'; State = 'Running'; StartMode = 'Auto' })       # :protected
            'vda.wemServer' = New-Read 'fd00:30::7'                                                                         # :host, IPv6
            'vda.wemCacheLocation' = New-Read '\\hfs1'                                                                      # :path, UNC with only a server
            'profile.policyGpo' = New-Read @([ordered]@{ Key = ''; Name = 'PathToUserStore'; Value = '\\hfree2\p' })          # :free
            # :path (UNC with share, UPM mount), :user without a domain field
            'profile.containers' = New-Read @([ordered]@{ Location = '\\hfs2\prof$\hu.drei\c.vhdx'; Mount = 'C:\Users\hu.drei_UPM_local\M'; Owner = 'hu.drei'; SessionId = 4 })
            'security.defenderExclusionPaths' = New-Read @([ordered]@{ Path = 'C:\Users\hfree3\x' })                       # :free
            'security.defenderSharedSignatures' = [ordered]@{ State = 'unreadable'; Reason = 'error'; Value = '\\hunread\sig' }   # not read
            'security.filters' = New-Read @([ordered]@{ Name = 'HEdgeFilter'; Altitude = '1'; Instances = 1; Legacy = $false })   # :protected
            'network.smbConnections' = New-Read @([ordered]@{ Share = '\\hfs3\daten' }, [ordered]@{ Share = '\\hfs4' }, [ordered]@{ Share = '\\hfs5\' })   # :share, also with only a server
            'network.dnsServers' = New-Read @([ordered]@{ Interface = 4; Address = '10.30.0.10' }, [ordered]@{ Interface = 4; Address = 'fe80::2%3' })   # :address
            'network.timeServers' = New-Read '  hzeit.edge.test   10.30.0.20  fe80::3 '                                     # :hosts with several blanks
            'maintenance.tasks' = New-Read @([ordered]@{ Path = '\hfree4'; Action = '\\hfree5\a.exe' })                     # :free
            'apps.probes' = New-Read @([ordered]@{ App = 'office'; Id = 'x'; Kind = 'registryValue'; Value = '\\hfree6\v'; Names = '\\hfree7\n' })   # value, :free
            # malformed values: a list given as a text, a value that is no record, a text given as a list
            'size.pagefiles' = New-Read 'kein Liste'; 'security.services' = 5; 'vda.desktopService' = New-Read @('a', 'b')
        }
        Write-HealthFile $HealthRun $HealthValues
        $script:HealthExp = @('server:T1=Server 01', 'server:h=Server 02',
            'user:hu.eins=Benutzer 01', 'domain:HDOM=Domäne 01', 'client:HWS-01=Client 01', 'user:hu.zwei=Benutzer 02', 'domain:HDOM2=Domäne 02',
            'user:hu.vier=Benutzer 03',
            'server:hddc1.edge.test=Server 03', 'server:hddc1=Server 03', 'domain:edge.test=Domäne 03', 'address:fe80::1%12=Adresse 01',
            'server:hddc2.edge.test=Server 04', 'server:hddc2=Server 04',
            'address:fd00:30::7=Adresse 02', 'server:hfs1=Server 05',
            'share:\\hfs2\prof$=Freigabe 01', 'server:hfs2=Server 06', 'user:hu.drei=Benutzer 04',
            'share:\\hfs3\daten=Freigabe 02', 'server:hfs3=Server 07', 'server:hfs4=Server 08', 'server:hfs5=Server 09',
            'address:10.30.0.10=Adresse 03', 'address:fe80::2%3=Adresse 04',
            'server:hzeit.edge.test=Server 10', 'server:hzeit=Server 10', 'address:10.30.0.20=Adresse 05', 'address:fe80::3=Adresse 06')
    }
    It 'nimmt je Typzusatz die Namen in der Reihenfolge der Werteliste auf' {
        Get-RunEntries $HealthRun 'Alles' | Should -Be $HealthExp
        Get-RunEntries $HealthRun 'Personen' | Should -Be @('user:hu.eins=Benutzer 01', 'client:HWS-01=Client 01', 'user:hu.zwei=Benutzer 02', 'user:hu.vier=Benutzer 03', 'user:hu.drei=Benutzer 04')
    }
    It 'nimmt aus freiem Text, Anwendungswerten und nicht gelesenen Werten nichts und schuetzt die Namen mit :protected' {
        $m = New-WorkerPerfMask -Path $HealthRun -Level 'Alles' -Texts $Texts
        $names = @($m.Entries | ForEach-Object Name)
        foreach ($n in 'hfree1', 'hfree2', 'hfree3', 'hfree4', 'hfree5', 'hfree6', 'hfree7', 'habsent', 'hunread', 'Administrator', 'administrator.HDOM', 'kein Liste') {
            @($names | Where-Object { $_ -like "*$n*" }).Count | Should -Be 0 -Because $n
        }
        $names | Should -Not -Contain 'a'; $names | Should -Not -Contain 'b'
        foreach ($p in 'HEdgeService', 'HEdgeFilter') { $m.Protected | Should -Contain $p }
    }
    It 'ersetzt die Namen aus health.json im Text' {
        $m = New-WorkerPerfMask -Path $HealthRun -Level 'Alles' -Texts $Texts
        Hide-WorkerPerfReportText 'Controller hddc2.edge.test. und hddc1, DNS fe80::1%12 und fe80::3, Dateiserver \\hfs4, WEM fd00:30::7, als Administrator' $m |
            Should -Be 'Controller Server 04. und Server 03, DNS Adresse 01 und Adresse 06, Dateiserver \\Server 08, WEM Adresse 02, als Administrator'
    }
    It 'verliert bei einem Fehler nur den Wert, an dem er auftritt' {
        Mock Add-WorkerPerfMaskHost { throw 'kaputt' } -ParameterFilter { $HostName -eq 'hddc1.edge.test' }
        $e = @(Get-RunEntries $HealthRun 'Alles')
        foreach ($x in 'server:hddc1.edge.test', 'address:fe80::1%12', 'server:hddc2.edge.test') { @($e | Where-Object { $_ -like "$x=*" }).Count | Should -Be 0 -Because $x }
        foreach ($x in 'user:hu.vier', 'address:fd00:30::7', 'server:hfs1', 'user:hu.drei', 'server:hzeit.edge.test', 'address:fe80::3') { @($e | Where-Object { $_ -like "$x=*" }).Count | Should -Be 1 -Because $x }
    }
    It 'nimmt aus einer Datei ohne Bereiche, mit Bereichen ohne Werte oder mit Werten anderer Form nichts und wirft nicht: <Json>' -TestCases @(
        @{ Json = '[]' }, @{ Json = '{}' }, @{ Json = '{"Areas":5}' }, @{ Json = '{"Areas":{"vda":5}}' }, @{ Json = '{"Areas":{"vda":{"Values":[1,2]}}}' },
        @{ Json = '{"Areas":{"vda":{"Values":{"vda.controllers":{"State":"read","Value":{"Entry":"hddc9"}}}}}}' }, @{ Json = '' }) {
        $dir = Write-TestRun 'mask-health-odd' @{ 'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'sessions.csv' = $null; 'shares.csv' = $null; 'volumes.csv' = $null
            'probes.csv' = $null; 'events.csv' = $null }
        [IO.File]::WriteAllText((Join-Path $dir 'health.json'), $Json)
        $e = @(Get-RunEntries $dir 'Alles')
        $e | Should -Be @('server:T1=Server 01', 'server:h=Server 02')                  # a list given as one record is no list (the loader drops it too)
    }
}
Describe 'Simulierte Stunde, maskiert' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        # one capture and one set of reports for both blocks below
        $script:R = New-TestReports (Join-Path $TestDrive 'r'); $script:Report = Join-Path $PSScriptRoot '../src/New-WorkerPerfReport.ps1'
        # the role file of the plain report (New-TestReports), so that the reports rate the same processes
        $script:Roles = Join-Path $TestDrive 'r/roles.sim.json'
        function New-CanaryRun([string]$Run, [string]$OutDir) {
            # a copy of a capture with a token of its own in every free-text column and field the collector writes: the
            # message of each event (also of the lookback), each command line, some probe errors, the end message, the first
            # error message of a failed source call and the reason of a source that is not available
            $dir = Copy-SimRun $Run $OutDir
            $setColumn = {
                param([string]$File, [string]$Column, [string]$Value, [int]$Every)
                $p = Join-Path $dir $File; $lines = [IO.File]::ReadAllLines($p); $ix = [array]::IndexOf($lines[0].Split(','), $Column)
                for ($i = 1; $i -lt $lines.Length; $i++) {
                    if ($lines[$i].Length -eq 0 -or ($i % $Every) -ne 0) { continue }
                    $f = [string[]]@(Split-WorkerPerfCsvLine $lines[$i]); $f[$ix] = $Value
                    $lines[$i] = [string]::Join(',', [string[]]@($f | ForEach-Object { if ($_ -match '[",]') { '"' + $_.Replace('"', '""') + '"' } else { $_ } }))
                }
                [IO.File]::WriteAllLines($p, $lines)
            }
            & $setColumn 'events.csv' 'Text' 'Meldung CANARYEVT' 1
            & $setColumn 'events_before.csv' 'Text' 'Meldung CANARYBEF' 1
            & $setColumn 'procinfo.csv' 'CommandLine' 'tool.exe /x CANARYCMD' 1
            & $setColumn 'probes.csv' 'Error' 'Fehler CANARYPRB' 40
            $meta = Join-Path $dir 'meta.json'; $m = [IO.File]::ReadAllText($meta)
            $m = $m.Replace('"EndReason": "duration"', '"EndReason": "error"').Replace('"EndMessage": null', '"EndMessage": "Ende CANARYEND"')
            $m = $m.Replace('"SourceErrors": {}', '"SourceErrors": { "proc.info": { "Count": 2, "FirstTime": "2026-11-12T11:00:00.0000000+00:00", "FirstMessage": "Fehler CANARYERR" } }')
            # the order of Available and Detail in meta.json varies from capture to capture: the whole entry is written anew
            $m = [regex]::Replace($m, '"cpu\.steal": \{[^{}]*\}', '"cpu.steal": { "Available": false, "Detail": "Grund CANARYSRC" }')
            [IO.File]::WriteAllText($meta, $m)
            foreach ($t in 'EndReason": "error', 'CANARYEND', 'CANARYERR', 'CANARYSRC') { if (-not $m.Contains($t)) { throw "Kanarienvogel nicht gesetzt: $t" } }
            $dir
        }
    }
    Describe 'Maskierte Berichtsdaten der simulierten Stunde' {
        BeforeAll {
            # the names below are not used by the report script, which runs in the same scope; the capture of the shared reports
            $maskSimOut = Join-Path $TestDrive 'sim'; [void](New-Item -ItemType Directory -Path $maskSimOut -Force)
            $script:SimRun = $R.Run
            $maskSimRoles = $Roles
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
                $maskSimPersonen = New-WorkerPerfMask -Path $SimRun -Level 'Personen' -Texts $Texts -RoleLabels @(@(Read-WorkerPerfRoles $maskSimRoles) | ForEach-Object { [string]$_.label })
                $maskSimMaskedP = Protect-WorkerPerfReportData $data $maskSimPersonen
                @{ Data = $data; Masked = $maskSimMasked; Mask = $maskSimMask; Plain = $maskSimPlain; Cleared = $maskSimCleared; ClearedAfter = (Get-MaskSimJson $data)
                    MaskedJson = (Get-MaskSimJson $maskSimMasked); MaskP = $maskSimPersonen; MaskedP = $maskSimMaskedP; MaskedJsonP = (Get-MaskSimJson $maskSimMaskedP) }
            }
            function Get-LeftNames($Masked, $Mask) {
                # hits of the level's names in every string and key of the masked data whose word is not a protected name
                $protected = @{}; foreach ($p in $Mask.Protected) { $protected[$p.ToLowerInvariant()] = $true }
                $strings = New-Object System.Collections.Generic.List[string]; Get-Strings $Masked $strings
                $left = New-Object System.Collections.Generic.List[string]
                foreach ($s in $strings) {
                    foreach ($hit in $Mask.Regex.Matches($s)) {
                        $a = $hit.Index; $b = $hit.Index + $hit.Length
                        while ($a -gt 0 -and $s[$a - 1] -notmatch '[\s\\/()\[\],;:"''<>|=]') { $a-- }
                        while ($b -lt $s.Length -and $s[$b] -notmatch '[\s\\/()\[\],;:"''<>|=]') { $b++ }
                        $word = $s.Substring($a, $b - $a).ToLowerInvariant()
                        if (-not $protected.ContainsKey($word) -and -not $protected.ContainsKey($word.TrimEnd('.'))) { $left.Add("$($hit.Value) in '$s'") }
                    }
                }
                , $left.ToArray()
            }
            # the subtrees of tests/MaskCensus.json: one entry of class composed each, whatever keys they hold (P3-R10)
            $script:CensusWhole = [string[]]@((Get-Content (Join-Path $PSScriptRoot 'MaskCensus.json') -Raw -Encoding UTF8 | ConvertFrom-Json).subtrees)
            function Get-Shape($Value, [string]$Path, [string]$Holder, [string]$Field, $Paths, $Keywords) {
                # every key path of the data, and path=value of every string of a keyword field (rule of WorkerPerfMaskKeywordFields);
                # a subtree of the census holds no keyword field
                if ($null -eq $Value -or $Value -is [System.Text.StringBuilder] -or $Value -is [ValueType]) { return }
                if ($CensusWhole -ccontains $Path.TrimStart('.')) { $Keywords = New-Object System.Collections.Generic.List[string] }
                if ($Value -is [string]) {
                    if ($WorkerPerfMaskKeywordFields -contains $Field -or $WorkerPerfMaskKeywordFields -contains "$Holder.$Field") { $Keywords.Add("$Path=$Value") }
                    return
                }
                if ($Value -is [System.Collections.IDictionary]) {
                    foreach ($k in @($Value.Keys)) { [void]$Paths.Add("$Path.$k"); Get-Shape $Value[$k] "$Path.$k" $Field ([string]$k) $Paths $Keywords }
                    return
                }
                foreach ($x in $Value) { Get-Shape $x "$Path[]" $Holder $Field $Paths $Keywords }
            }
            function Get-ShapeOf($Value) {
                $paths = New-Object 'System.Collections.Generic.SortedSet[string]' ([StringComparer]::Ordinal); $kw = New-Object System.Collections.Generic.List[string]
                Get-Shape $Value '' '' '' $paths $kw
                @{ Paths = [string[]]@($paths); Keywords = $kw.ToArray() }
            }
            function Get-Strings($Value, $List) {
                if ($null -eq $Value -or $Value -is [System.Text.StringBuilder] -or $Value -is [ValueType]) { return }
                if ($Value -is [string]) { $List.Add($Value); return }
                if ($Value -is [System.Collections.IDictionary]) { foreach ($k in $Value.Keys) { $List.Add([string]$k); Get-Strings $Value[$k] $List }; return }
                foreach ($x in $Value) { Get-Strings $x $List }
            }
            function Get-StringPaths($Value, [string[]]$Whole = @()) {
                # every path of the data that holds a string (list levels as []), with the number of its strings; a path of
                # Whole (subtrees of tests/MaskCensus.json) is one entry, whatever it holds
                $out = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
                $walk = { param($v, [string]$p)
                    if ($null -eq $v -or $v -is [System.Text.StringBuilder] -or $v -is [ValueType]) { return }
                    if ($Whole -ccontains $p) { $out[$p] = 1 + [int]$out[$p]; return }
                    if ($v -is [string]) { $out[$p] = 1 + [int]$out[$p]; return }
                    if ($v -is [System.Collections.IDictionary]) { foreach ($k in @($v.Keys)) { & $walk $v[$k] $(if ($p) { "$p.$k" } else { [string]$k }) }; return }
                    foreach ($x in $v) { & $walk $x "$p[]" } }
                & $walk $Value ''
                , $out
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
            # Aussage geaendert (P2-R13): der erste Teil eines vollstaendigen Hostnamens ist derselbe Server; proxy ist ein Wort des Berichts
            foreach ($x in 'server:SIM-VDA01=Server 01', 'server:ora01.sim.local=Server 02', 'server:ora01=Server 02', 'domain:sim.local=Domäne 01', 'server:proxy.sim.local=Server 03',
                'server:fs01.sim.local=Server 04', 'server:fs01=Server 04') { $exp.Add($x) }
            for ($i = 1; $i -le 25; $i++) {
                $exp.Add(('user:user{0:000}=Benutzer {0:00}' -f $i)); if ($i -eq 1) { $exp.Add('domain:CONTOSO=Domäne 02') }; $exp.Add(('client:WS-{0}=Client {1:00}' -f (1037 + 37 * $i), $i))
            }
            foreach ($x in 'share:\\fs01\daten=Freigabe 01', 'share:\\fs01\profile$=Freigabe 02', 'printer:PRN-EG-01=Drucker 01', 'printer:PRN-OG-02=Drucker 02') { $exp.Add($x) }
            # Aussage geaendert (Task 15): die Namen aus health.json folgen auf alle anderen
            foreach ($x in 'user:user026=Benutzer 26', 'server:ddc01.sim.local=Server 05', 'server:ddc01=Server 05', 'server:ddc02.sim.local=Server 06', 'server:ddc02=Server 06',
                'server:wem01.sim.local=Server 07', 'server:wem01=Server 07', 'share:\\fs01\defsig$=Freigabe 03', 'address:10.20.0.10=Adresse 01', 'address:10.20.0.11=Adresse 02',
                'address:fd00:20::10=Adresse 03', 'server:zeit01.sim.local=Server 08', 'server:zeit01=Server 08', 'address:10.20.0.20=Adresse 04') { $exp.Add($x) }
            @($Sim.Mask.Entries | ForEach-Object { '{0}:{1}={2}' -f $_.Kind, $_.Name, $_.Replacement }) | Should -Be $exp.ToArray()
            $Sim.MaskedJson | Should -Not -Match 'user0\d\d'; $Sim.MaskedJson | Should -Not -Match 'CONTOSO'; $Sim.MaskedJson | Should -Match 'Benutzer 01'
            Get-LeftNames $Sim.Masked $Sim.Mask | Should -BeNullOrEmpty
        }
        It 'enthaelt bei Personen keinen Benutzer, Client und kein Konto mehr' {
            $Sim.MaskP.Entries.Count | Should -Be 51                                     # Aussage geaendert (Task 15): user026 aus health.json
            $Sim.MaskedJsonP | Should -Not -Match 'user0\d\d'; $Sim.MaskedJsonP | Should -Not -Match 'WS-1\d\d\d'
            $Sim.MaskedJsonP | Should -Match 'CONTOSO'                                           # Domaenen ersetzt erst Alles
            Get-LeftNames $Sim.MaskedP $Sim.MaskP | Should -BeNullOrEmpty
        }
        It 'sammelt die Namen aus health.json nach allen anderen und laesst die bisherigen Nummern stehen' {   # Review Focus 4
            $e = @($Sim.Mask.Entries | ForEach-Object { '{0}:{1}={2}' -f $_.Kind, $_.Name, $_.Replacement })
            $e[-14..-1] | Should -Be @('user:user026=Benutzer 26', 'server:ddc01.sim.local=Server 05', 'server:ddc01=Server 05', 'server:ddc02.sim.local=Server 06', 'server:ddc02=Server 06',
                'server:wem01.sim.local=Server 07', 'server:wem01=Server 07',
                'share:\\fs01\defsig$=Freigabe 03', 'address:10.20.0.10=Adresse 01', 'address:10.20.0.11=Adresse 02', 'address:fd00:20::10=Adresse 03',
                'server:zeit01.sim.local=Server 08', 'server:zeit01=Server 08', 'address:10.20.0.20=Adresse 04')
            $e[0] | Should -Be 'server:SIM-VDA01=Server 01'; $e | Should -Contain 'share:\\fs01\profile$=Freigabe 02'; @($e | Where-Object { $_ -like 'share:*' }).Count | Should -Be 3
            @($Sim.Mask.Entries | Where-Object Name -eq 'Administrator').Count | Should -Be 0                  # der Ordner des eingebauten Kontos ist keine Person
            foreach ($p in 'WdFilter', 'upmjit', 'BrokerAgent', 'WinDefend', 'Citrix WEM Agent Host Service') { $Sim.Mask.Protected | Should -Contain $p }
            Hide-WorkerPerfReportText 'DNS fd00:20::10 und 10.20.0.10, Controller ddc01.sim.local, WEM wem01.sim.local, Zeit zeit01.sim.local, Profil C:\Users\user026, als Administrator anmelden' $Sim.Mask |
                Should -Be 'DNS Adresse 03 und Adresse 01, Controller Server 05, WEM Server 07, Zeit Server 08, Profil C:\Users\Benutzer 26, als Administrator anmelden'
            @($Sim.MaskP.Entries | Where-Object Kind -eq 'user').Count | Should -Be 26
        }
        It 'sammelt aus freiem Servertext nichts und uebersteht eine fehlende oder beschaedigte Datei' {
            $run = Copy-SimRun $SimRun (Join-Path $TestDrive 'maskhealth'); $f = Join-Path $run 'health.json'
            $names = { @((New-WorkerPerfMask -Path $run -Level 'Alles' -Texts $Texts).Entries | ForEach-Object Name) }
            & $names | Should -Not -Contain 'prn01'                                    # steht nur in einem Richtlinienwert (freier Text)
            @(& $names | Where-Object { $_ -match 'office\$' }).Count | Should -Be 0   # die Updatequelle von Office steht nur in einem Anwendungswert mit names: true (freier Text)
            [IO.File]::WriteAllText($f, [IO.File]::ReadAllText($f).Replace('ddc02.sim.local', 'fd00:20::5'))             # ein Controller, der als IPv6-Adresse eingetragen ist
            $v6 = (New-WorkerPerfMask -Path $run -Level 'Alles' -Texts $Texts).Entries | Where-Object Name -eq 'fd00:20::5'; $v6.Kind | Should -Be 'address'; $v6.Replacement | Should -Match '^Adresse \d\d$'
            [IO.File]::WriteAllText($f, '{ kein json'); $broken = @(& $names); $broken | Should -Not -Contain 'ddc01.sim.local'; $broken | Should -Contain 'user001'
            Remove-Item $f; @(& $names).Count | Should -Be $broken.Count
        }
        It 'laesst bei <Level> Aufbau und Schluesselwoerter stehen, auch wenn Benutzer wie Felder und Schluesselwoerter heissen' -TestCases @(
            @{ Level = 'Alles' }, @{ Level = 'Personen' }) {                                    # P2-R10
            $base = $(if ($Level -eq 'Alles') { $Sim.Mask } else { $Sim.MaskP })
            $plain = Get-ShapeOf $Sim.Data
            $names = New-Object System.Collections.Generic.List[string]
            foreach ($k in $Sim.Data.Keys) { $names.Add([string]$k) }
            foreach ($list in 'sessions', 'procs', 'incidents', 'events') { foreach ($r in @($Sim.Data[$list])) { foreach ($k in $r.Keys) { $names.Add([string]$k) } } }
            foreach ($e in $plain.Keywords) { $names.Add($e.Substring($e.IndexOf('=') + 1)) }
            $seen = @{}; foreach ($e in $base.Entries) { $seen[$e.Name.ToLowerInvariant()] = $true }
            $extra = New-Object System.Collections.Generic.List[object]
            foreach ($n in $names) { if ($n.Length -gt 0 -and -not $seen.ContainsKey($n.ToLowerInvariant())) { $seen[$n.ToLowerInvariant()] = $true; $extra.Add(@{ Kind = 'user'; Name = $n; Replacement = ('Benutzer X{0:000}' -f $extra.Count) }) } }
            $extra.Count | Should -BeGreaterThan 100; @($extra | ForEach-Object Name) | Should -Contain 'print'; @($extra | ForEach-Object Name) | Should -Contain 'crash'
            $mx = @{ Level = $Level; Other = $base.Other }
            Set-WorkerPerfMaskNames -Mask $mx -Entries (@($base.Entries) + $extra.ToArray()) -Protected $base.Protected
            $masked = Protect-WorkerPerfReportData $Sim.Data $mx
            $shape = Get-ShapeOf $masked
            $shape.Paths | Should -Be $plain.Paths
            $shape.Keywords | Should -Be $plain.Keywords
            foreach ($s in @($masked.sessions | Where-Object { $_.user -ne '' })) { $s.user | Should -Match '^Benutzer \d\d$'; $s.client | Should -Match '^Client \d\d$' }
            foreach ($e in @($masked.events | Where-Object { $_.Contains('user') })) { $e.user | Should -Match '^Benutzer \d\d$' }
            foreach ($i in @($masked.incidents | Where-Object { $null -ne $_.main })) { $i.main.user | Should -Match '^Benutzer \d\d$' }
        }
        It 'hat in den Schluesselwortfeldern nur Werte in Bezeichnerform, Einheiten und Verweise, und keinen Namen der Liste' {
            $kw = (Get-ShapeOf $Sim.Data).Keywords
            $kw.Count | Should -BeGreaterThan 100
            # Aussage geaendert (P2-R12): unit und url tragen ihre Werte aus thresholds.json
            $free = { param($e) $e -match '\.(unit|url)=' }
            @($kw | Where-Object { -not (& $free $_) } | Where-Object { $v = $_.Substring($_.IndexOf('=') + 1); $v -ne '' -and $v -notmatch '^[A-Za-z0-9_.:-]+$' }) | Should -BeNullOrEmpty
            @($kw | Where-Object { & $free $_ }).Count | Should -BeGreaterThan 10
            foreach ($m in $Sim.Mask, $Sim.MaskP) { @($kw | Where-Object { $m.Regex.IsMatch($_.Substring($_.IndexOf('=') + 1)) }) | Should -BeNullOrEmpty }
        }
        It 'ordnet jedes Textfeld der Berichtsdaten im Bestand tests/MaskCensus.json ein' {                       # P2-R15
            $file = Get-Content (Join-Path $PSScriptRoot 'MaskCensus.json') -Raw -Encoding UTF8 | ConvertFrom-Json; $census = $file.fields
            $marks = @{}; foreach ($p in $census.PSObject.Properties) { $marks[$p.Name] = [string]$p.Value }
            @($marks.Values | Where-Object { @('name', 'keyword', 'composed', 'copied') -notcontains $_ }) | Should -BeNullOrEmpty
            # the catalogue in the data (guidance) is one entry: a catalogue edited by the customer has other keys (P3-R10)
            @($file.subtrees) | Should -Be @('guidance'); $marks['guidance'] | Should -Be 'composed'
            $values = Get-StringPaths $Sim.Data ([string[]]@($file.subtrees))
            $values['guidance'] | Should -Be 1
            $values.Count | Should -BeGreaterThan 150
            @($values.Keys | Where-Object { -not $marks.ContainsKey($_) } | ForEach-Object { "neues Textfeld $_ : in tests/MaskCensus.json einordnen" }) | Should -BeNullOrEmpty
            foreach ($path in $values.Keys) {
                $keys = $path.Replace('[]', '').Split('.'); $field = $keys[-1]; $holder = $(if ($keys.Count -gt 1) { $keys[-2] } else { '' })
                $listed = $WorkerPerfMaskKeywordFields -contains $field -or $WorkerPerfMaskKeywordFields -contains "$holder.$field"
                ($marks[$path] -eq 'keyword') | Should -Be $listed -Because "$path ist im Bestand '$($marks[$path])' und steht $(if ($listed) { '' } else { 'nicht ' })in WorkerPerfMaskKeywordFields"
            }
            # copied: in WorkerPerfMaskFreeTextFields, and after Clear-WorkerPerfReportFreeText empty (a field ?unavailable in the
            # records of sources that are not available)
            $free = @{}; foreach ($f in $WorkerPerfMaskFreeTextFields) { $free[$f.Replace('?unavailable', '')] = $f.EndsWith('?unavailable') }
            @($marks.Keys | Where-Object { $marks[$_] -eq 'copied' } | Where-Object { -not $free.ContainsKey($_) }) | Should -BeNullOrEmpty
            @($free.Keys | Where-Object { $marks[$_] -ne 'copied' }) | Should -BeNullOrEmpty
            $off = @{}; foreach ($q in @($Sim.Data.quality.sources)) { if ($false -eq $q.available) { $off[[string]$q.id] = $true } }
            foreach ($path in @($free.Keys)) {
                $key = $path.Substring($path.LastIndexOf('.') + 1)
                foreach ($r in @(Get-WorkerPerfMaskHolders $Sim.Data $path)) {
                    if ($free[$path] -and -not $off.ContainsKey([string]$r['id'])) { continue }
                    if ($r.Contains($key)) { [string]$r[$key] | Should -Be '' -Because "$path wird geleert" }
                }
            }
            @($values.Keys | Where-Object { $marks[$_] -eq 'copied' }).Count | Should -BeGreaterThan 5
        }
    }
    Describe 'Maskierter Bericht der simulierten Stunde' {
        BeforeAll {
            $script:Plain = Get-ReportData $R.Report
            function New-Masked([string]$Name, [hashtable]$Extra = @{}, [string]$Run = $R.Run) { $out = Join-Path $TestDrive "$Name.html"; [void](& $Report -Path $Run -OutFile $out -RoleFile $Roles @Extra 6>$null); $out }
            function Get-Words([string]$Html) { [IO.File]::ReadAllText($Html) }
            $script:Persons = @(2..26 | ForEach-Object { 'user{0:d3}' -f ($_ - 1) }) + @('WS-\d{4}')
            $script:Others = @('SIM-VDA01', 'CONTOSO', 'fs01', 'ora01\.sim\.local', 'proxy\.sim\.local', 'PRN-EG-01', 'PRN-OG-02')
            function Get-Leaves($o) {                        # Zahlen und Wahrheitswerte in Reihenfolge; Texte zaehlen nur als Platzhalter
                if ($null -eq $o) { 'null' } elseif ($o -is [string]) { 's' } elseif ($o -is [ValueType]) { [string]$o }
                elseif ($o -is [System.Collections.IEnumerable]) { 'a'; foreach ($x in $o) { Get-Leaves $x } }
                else { 'o'; foreach ($p in $o.PSObject.Properties) { Get-Leaves $p.Value } }
            }
            function Get-Filled($Records, [string]$Field) {
                # records whose field holds a text: a missing field, $null and '' count as empty
                @($Records | Where-Object { $p = $_.PSObject.Properties[$Field]; $null -ne $p -and -not [string]::IsNullOrEmpty([string]$p.Value) })
            }
        }
        It 'enthaelt in keiner Stufe einen der zu ersetzenden Namen, weder in den Daten noch in der Datei' {
            # the masked reports of New-TestReports (Personen with an unknown reported user and a reported time)
            $p = Get-Words $R.MaskedP; $a = Get-Words $R.Masked
            foreach ($n in $Persons) { $p | Should -Not -Match $n; $a | Should -Not -Match $n }
            foreach ($n in $Others) { $a | Should -Not -Match $n }
            $a | Should -Not -Match 'USER008'                                                            # Meldungstext des AppLocker-Ereignisses entfaellt
        }
        It 'laesst stehen, was laut Tabelle bleibt' {
            $p = Get-ReportData $R.MaskedP; $a = Get-ReportData $R.Masked
            $p.meta.computer | Should -Be 'SIM-VDA01'; ($p.sessions | Where-Object id -eq 2).domain | Should -Be 'CONTOSO'; @($p.shares.name) | Should -Contain '\\fs01\daten'
            $a.meta.computer | Should -Be 'Server 01'; $a.meta.mask | Should -Be 'Alles'; $p.meta.mask | Should -Be 'Personen'
            @($a.apps.name) | Should -Contain 'EXCEL.EXE'; @($a.probes.name) | Should -Contain 'Oracle-Listener'; ($a.print.drivers | Where-Object involved).name | Should -Be 'HP Universal Printing PCL 6 (Sim)'
            ($a.incidents | Where-Object lead -eq 'cpu').text | Should -Match 'Hauptverursacher: EXCEL\.EXE in der Sitzung von Benutzer \d\d '
            @(Get-Filled $Plain.events 'text').Count | Should -BeGreaterThan 0                          # die Aussage darunter ist nicht leer
            @(Get-Filled $a.events 'text').Count | Should -Be 0                                          # Befehlszeilen: siehe den Kanarientest
        }
        It 'verdoppelt in keinem Text des maskierten Berichts eine Bezeichnung' {                           # fix round 4, C1 (ruling P3-R62)
            $a = Get-ReportData $R.Masked; $p = Get-ReportData $R.MaskedP
            # the words the replacement names start with, from their patterns
            $words = @('user', 'client', 'sid', 'server', 'share', 'domain', 'address', 'printer' | ForEach-Object { ($Texts['mask.' + $_] -split ' ')[0] })
            $words | Should -Be @('Benutzer', 'Client', 'Konto', 'Server', 'Freigabe', 'Domäne', 'Adresse', 'Drucker')
            $doubled = '(?<![\p{L}\p{N}-])(' + ($words -join '|') + ')[ \t\u00A0]+\1 \d\d'
            'Freigabe Freigabe 01' | Should -MatchExactly $doubled; 'Benutzer Benutzer 14' | Should -MatchExactly $doubled; 'Server Server 01 am' | Should -MatchExactly $doubled
            'Server Druckserver 02' | Should -Not -MatchExactly $doubled; 'Benutzer: Benutzer 14' | Should -Not -MatchExactly $doubled; 'Freigabe 01, Freigabe 02' | Should -Not -MatchExactly $doubled
            function Get-Texts($Value, [string]$Path, $List) {
                # every string of the report data with its path (list levels as [])
                if ($null -eq $Value -or $Value -is [ValueType]) { return }
                if ($Value -is [string]) { $List.Add([pscustomobject]@{ Path = $Path; Text = $Value }); return }
                if ($Value -is [System.Collections.IEnumerable]) { foreach ($x in $Value) { Get-Texts $x "$Path[]" $List }; return }
                foreach ($q in $Value.PSObject.Properties) { Get-Texts $q.Value $(if ($Path) { "$Path.$($q.Name)" } else { $q.Name }) $List }
            }
            foreach ($data in $a, $p) {
                $all = New-Object System.Collections.Generic.List[object]; Get-Texts $data '' $all
                $all.Count | Should -BeGreaterThan 5000
                @($all | Where-Object { $_.Text -cmatch $doubled } | ForEach-Object { "$($_.Path): $($_.Text.Substring(0, [Math]::Min(90, $_.Text.Length)))" } | Sort-Object -Unique) | Should -Be @()
            }
            # the fields that doubled the word: the label of a share (chart legend, target comparison) and the sentence of the share incident
            @($a.shares.label) | Should -Be @('Freigabe 01', 'Freigabe 02'); @($Plain.shares.label) | Should -Be @('Freigabe \\fs01\daten', 'Freigabe \\fs01\profile$')
            $share = $a.incidents | Where-Object lead -eq 'share'
            $share.text | Should -Match 'Dateiserver-Engpass \(Freigabe 01 Spitze '; @($share.signals.label) | Should -Contain 'Freigabe 01'
            @($a.sollIst | Where-Object { $_.worstInstance -like 'Freigabe*' } | ForEach-Object { $_.worstInstance }) | Should -Be @('Freigabe 01')
            # the head of a copy text and of the summary: the server once
            ($a.incidents[0].copy.named -split "\r?\n")[0] | Should -Match '^WorkerPerf: Server 01, \d\d\.\d\d\.\d{4}$'; $a.copyAll.named | Should -Match 'Messung auf Server 01 am '
            # a label and its value stay: the users of an event incident
            @($a.incidents | Where-Object { $_.type -eq 'ereignis' -and $_.text -match 'Benutzer: Benutzer \d\d' }).Count | Should -BeGreaterThan 0
            # level Personen keeps the share's name behind its word
            @($p.shares.label) | Should -Be @($Plain.shares.label)
            # the version without names of an unmasked report follows the same rule
            $plainShare = $Plain.incidents | Where-Object lead -eq 'share'
            $plainShare.copy.anonymous | Should -Not -MatchExactly $doubled; ($Plain.incidents.copy.anonymous -join "`n") | Should -Not -MatchExactly $doubled; $Plain.copyAll.anonymous | Should -Not -MatchExactly $doubled
        }
        It 'zeigt dieselben Zahlen, Vorfaelle, Muster und Rangfolge' {
            $a = Get-ReportData $R.Masked                                                                # same options as $Plain
            $l1 = @(Get-Leaves $Plain); $l2 = @(Get-Leaves $a)
            $l2.Count | Should -Be ($l1.Count + 1)                                                         # das Feld meta.mask kommt dazu
            $pat = { param($d) @($d.incidents | Where-Object type -eq 'ereignis' | ForEach-Object { @($_.event.patterns | ForEach-Object { $_.id }) -join ',' }) }
            @($a.incidents.id) | Should -Be @($Plain.incidents.id); & $pat $a | Should -Be (& $pat $Plain)
            ($a.incidents | Where-Object lead -eq 'cpu').contributors.cpu.procs.k | Should -Be ($Plain.incidents | Where-Object lead -eq 'cpu').contributors.cpu.procs.k
        }
        It 'vergibt in zwei Laeufen und in einem Zeitausschnitt dieselben Ersatznamen' {
            $cpu = $Plain.incidents | Where-Object lead -eq 'cpu'
            $m1 = Join-Path $TestDrive 'm1.maskmap.json'; $m2 = Join-Path $TestDrive 'm2.maskmap.json'; $m3 = Join-Path $TestDrive 'm3.maskmap.json'
            [void](New-Masked 'r1' @{ Mask = 'Alles'; MaskMapFile = $m1 }); [void](New-Masked 'r2' @{ Mask = 'Alles'; MaskMapFile = $m2 })
            $cut = Get-ReportData (New-Masked 'r3' @{ Mask = 'Alles'; MaskMapFile = $m3; From = (Get-ServerTime $R.Run ($cpu.start - 60000)); To = (Get-ServerTime $R.Run ($cpu.end + 60000)) })
            [IO.File]::ReadAllText($m1) | Should -Be ([IO.File]::ReadAllText($m2)); [IO.File]::ReadAllText($m1) | Should -Be ([IO.File]::ReadAllText($m3))
            $full = Get-ReportData (Join-Path $TestDrive 'r1.html')
            ($cut.sessions | Where-Object id -eq 4).user | Should -Be ($full.sessions | Where-Object id -eq 4).user
        }
        It 'schreibt die Zuordnung nur mit -MaskMapFile und mit allen Ersatznamen' {
            $before = @(Get-ChildItem $TestDrive -Filter '*.maskmap.json' -Recurse).Count
            [void](New-Masked 'nomap' @{ Mask = 'Alles' }); @(Get-ChildItem $TestDrive -Filter '*.maskmap.json' -Recurse).Count | Should -Be $before
            $map = Get-Content (Join-Path $TestDrive 'm1.maskmap.json') -Raw | ConvertFrom-Json
            $map.level | Should -Be 'Alles'; @($map.entries | Where-Object kind -eq 'user').Count | Should -Be 26; @($map.entries | Where-Object kind -eq 'printer').replacement | Should -Be @('Drucker 01', 'Drucker 02')   # Aussage geaendert (Task 15): user026 aus health.json
            { New-Masked 'x' @{ MaskMapFile = (Join-Path $TestDrive 'y.maskmap.json') } } | Should -Throw '*setzt -Mask voraus*'
            { New-Masked 'SIM-VDA01-bericht' @{ Mask = 'Alles' } } | Should -Throw '*nennt den Server*'
            { New-Masked 'sim-vda01' @{ Mask = 'Alles' } } | Should -Throw '*nennt den Server*'
            Test-Path (Join-Path $TestDrive 'SIM-VDA01-bericht.html') | Should -BeFalse
        }
        It 'schreibt bei Personen nur die Arten in die Zuordnung, die diese Stufe ersetzt' {
            $m = Join-Path $TestDrive 'personen.maskmap.json'
            [void](New-Masked 'personen' @{ Mask = 'Personen'; MaskMapFile = $m })
            $map = [IO.File]::ReadAllText($m) | ConvertFrom-Json
            $map.level | Should -Be 'Personen'
            @($map.entries | ForEach-Object kind | Sort-Object -Unique) | Should -Be @('client', 'user')
            @($map.entries | Where-Object kind -eq 'user').Count | Should -Be 26                                   # Aussage geaendert (Task 15): user026 aus health.json
            $bytes = [IO.File]::ReadAllBytes($m); $bytes[0] | Should -Be ([byte][char]'{')                 # ohne BOM
        }
        It 'ersetzt im Zeitausschnitt auch einen Benutzer ohne Sitzung darin wie im ganzen Bericht' {
            # user025 has a session only in the first 30 snapshots of this copy; the cut starts at snapshot 100
            $copy = Copy-SimRun $R.Run (Join-Path $TestDrive 'nosession')
            $file = Join-Path $copy 'sessions.csv'
            [IO.File]::WriteAllLines($file, @([IO.File]::ReadAllLines($file) | Where-Object { $f = $_.Split(','); -not ($f[1] -eq '26' -and $f[0] -match '^\d+$' -and [int]$f[0] -ge 30) }))
            $at = [DateTimeOffset]::Parse(([IO.File]::ReadAllLines((Join-Path $copy 'snapshots.csv'))[101]).Split(',')[2], [cultureinfo]::InvariantCulture).ToUnixTimeMilliseconds()
            $fullOut = Join-Path $TestDrive 'nosession-full.html'; $cutOut = Join-Path $TestDrive 'nosession-cut.html'
            $fullMap = Join-Path $TestDrive 'nosession-full.maskmap.json'; $cutMap = Join-Path $TestDrive 'nosession-cut.maskmap.json'
            [void](& $Report -Path $copy -OutFile $fullOut -Mask Alles -MaskMapFile $fullMap -FocusUser 'user025' 6>$null)
            [void](& $Report -Path $copy -OutFile $cutOut -Mask Alles -MaskMapFile $cutMap -FocusUser 'user025' -From (Get-ServerTime $copy $at) 6>$null)
            [IO.File]::ReadAllText($cutMap) | Should -Be ([IO.File]::ReadAllText($fullMap))
            $rep = @(([IO.File]::ReadAllText($fullMap) | ConvertFrom-Json).entries | Where-Object name -eq 'user025').replacement
            $rep | Should -Be @('Benutzer 25')
            $cut = Get-ReportData $cutOut; $full = Get-ReportData $fullOut
            @($cut.sessions | ForEach-Object user) | Should -Not -Contain 'Benutzer 25'; @($full.sessions | ForEach-Object user) | Should -Contain 'Benutzer 25'
            $cut.meta.focus.user | Should -Be 'Benutzer 25'; $full.meta.focus.user | Should -Be 'Benutzer 25'
            [IO.File]::ReadAllText($cutOut) | Should -Not -Match 'user025'
        }
        It 'gibt bei Alles auf keinem Ausgabestrom einen der Namen aus' {
            $m = Join-Path $TestDrive 'streams.maskmap.json'
            $text = & { & $Report -Path $R.Run -OutFile (Join-Path $TestDrive 'streams.html') -Mask Alles -MaskMapFile $m -FocusUser 'user003' -Verbose } *>&1 | Out-String
            $text | Should -Match 'streams\.html'
            foreach ($n in @($Persons) + @($Others)) { $text | Should -Not -Match $n }
            $text | Should -Not -Match 'Hinweis'                                                         # kein Name gleicht einem Wort des Berichts
        }
        It 'lehnt eine Zuordnungsdatei ab, die die Berichtsdatei ist, auch als relativer Pfad' {
            Push-Location $TestDrive
            try {
                $abs = Join-Path $TestDrive 'same.html'
                { & $Report -Path $R.Run -OutFile 'same.html' -Mask Alles -MaskMapFile $abs 6>$null } | Should -Throw '*nicht die Berichtsdatei*'
                { & $Report -Path $R.Run -OutFile $abs -Mask Alles -MaskMapFile 'same.html' 6>$null } | Should -Throw '*nicht die Berichtsdatei*'
                { & $Report -Path $R.Run -OutFile $abs -Mask Alles -MaskMapFile $abs 6>$null } | Should -Throw '*nicht die Berichtsdatei*'
                Test-Path $abs | Should -BeFalse
            }
            finally { Pop-Location }
        }
        It 'behaelt den Bericht und meldet den Fehler, wenn die Zuordnungsdatei nicht geschrieben werden kann' {
            # Aussage geaendert (Minor 8): ein fehlender Ordner wird vorab gemeldet; hier ist das Ziel ein Ordner
            $out = Join-Path $TestDrive 'mapfail.html'; $map = Join-Path $TestDrive 'mapfail.maskmap.json'; [void](New-Item -ItemType Directory $map)
            { & $Report -Path $R.Run -OutFile $out -RoleFile $Roles -Mask Alles -MaskMapFile $map 6>$null } | Should -Throw '*Zuordnungsdatei*'
            (Get-ReportData $out).meta.mask | Should -Be 'Alles'; Test-Path $map -PathType Container | Should -BeTrue
        }
        It 'prueft den Ordner der Zuordnungsdatei vorab und ueberschreibt keine Datei der Aufzeichnung' {                # Minor 8
            $out = Join-Path $TestDrive 'mapcheck.html'
            { & $Report -Path $R.Run -OutFile $out -Mask Alles -MaskMapFile (Join-Path $TestDrive 'fehlt/x.maskmap.json') 6>$null } | Should -Throw "*Ordner der Zuordnungsdatei*nicht gefunden*"
            Test-Path $out | Should -BeFalse
            $meta = Join-Path $R.Run 'meta.json'; $before = [IO.File]::ReadAllText($meta)
            { & $Report -Path $R.Run -OutFile $out -Mask Alles -MaskMapFile $meta 6>$null } | Should -Throw '*der Aufzeichnung*'
            Push-Location $R.Run
            try { { & $Report -Path '.' -OutFile $out -Mask Personen -MaskMapFile 'sessions.csv' 6>$null } | Should -Throw '*der Aufzeichnung*' }
            finally { Pop-Location }
            [IO.File]::ReadAllText($meta) | Should -BeExactly $before; Test-Path $out | Should -BeFalse
        }
        It 'entfernt einen gemeldeten Benutzer, den die Aufzeichnung nicht kennt, in beiden Stufen' {                  # P2-R11
            $p = Get-ReportData $R.MaskedP
            $a = Get-ReportData (New-Masked 'focus-unknown' @{ Mask = 'Alles'; FocusUser = 'KLINIK\schmidt.unbekannt' })
            foreach ($d in $p, $a) { $d.meta.focus.user | Should -Be '(Name entfernt)'; $d.meta.focus.found | Should -BeFalse }
            foreach ($f in $R.MaskedP, (Join-Path $TestDrive 'focus-unknown.html')) { $t = [IO.File]::ReadAllText($f); $t | Should -Not -Match 'schmidt'; $t | Should -Not -Match 'KLINIK' }
            (Get-ReportData $R.MaskedP).meta.mask | Should -Be 'Personen'
        }
        It 'laesst keinen Freitext der Aufzeichnung in einen maskierten Bericht' {                                       # P2-R15
            $canary = New-CanaryRun $R.Run (Join-Path $TestDrive 'canary')
            # a reported time 5 min before the capture: the lookback events around it are shown too
            $first = [DateTimeOffset]::Parse((Get-Content (Join-Path $canary 'ticks.csv') -TotalCount 2)[1].Split(',')[1], [cultureinfo]::InvariantCulture).ToUnixTimeMilliseconds()
            $at = Get-ServerTime $canary ($first - 300000)
            $plain = [IO.File]::ReadAllText((New-Masked 'canary-plain' @{ ReportedTime = $at } -Run $canary))
            # every token the report shows unmasked; the probe error only decides whether a probe failed
            foreach ($t in 'CANARYEVT', 'CANARYBEF', 'CANARYCMD', 'CANARYEND', 'CANARYERR', 'CANARYSRC') { $plain | Should -Match $t }
            # the end message reaches the situation summary and the summary to copy of an unmasked report (P3-R9)
            $pd = Get-ReportData (Join-Path $TestDrive 'canary-plain.html')
            @($pd.lagebild.hints) -join ' ' | Should -Match 'CANARYEND'; $pd.copyAll.named | Should -Match 'CANARYEND'
            # the versions without names never quote free text of the server (P3-R44)
            foreach ($c in @($pd.copyAll.anonymous) + @(@($pd.incidents) + @($pd.before.incidents) | ForEach-Object { $_.copy.anonymous })) { $c | Should -Not -Match 'CANARY' }
            foreach ($level in 'Personen', 'Alles') {
                $file = New-Masked "canary-$level" @{ Mask = $level; ReportedTime = $at; FocusUser = 'user003' } -Run $canary
                [IO.File]::ReadAllText($file) | Should -Not -Match 'CANARY' -Because $level
                $md = Get-ReportData $file
                @($md.procs | Where-Object { $_.cmd -ne '' }).Count | Should -Be 0
                # the free texts were cleared before the summary was built: the hint without a message (P3-R9)
                @($md.lagebild.hints) | Should -Contain $md.guidance.hints.errorNoMessage -Because $level
            }
        }
        It 'nennt auf der Konsole die Ersatznamen der Namen, die Woertern des Berichts gleichen' {                   # P2-R12
            $copy = Copy-SimRun $R.Run (Join-Path $TestDrive 'vocab')
            $file = Join-Path $copy 'sessions.csv'; [IO.File]::WriteAllText($file, ([IO.File]::ReadAllText($file) -replace ',user002,', ',soll,'))
            $text = & { & $Report -Path $copy -OutFile (Join-Path $TestDrive 'vocab.html') -Mask Personen } *>&1 | Out-String
            $text | Should -Match 'Hinweis: 1 Name gleicht einem Wort des Berichts \(Benutzer 02\); Saetze mit diesem Wort'
            $text | Should -Not -Match '(?i)\bsoll\b'
        }
        It 'nennt die Meldung einer mit Fehler beendeten Aufzeichnung nur in der Fassung mit Namen' {                 # P3-R44
            $copy = Copy-SimRun $R.Run (Join-Path $TestDrive 'endmsg')
            $meta = Join-Path $copy 'meta.json'; $m = [IO.File]::ReadAllText($meta)
            $m = $m.Replace('"EndReason": "duration"', '"EndReason": "error"').Replace('"EndMessage": null', '"EndMessage": "Zugriff CANARYMSG verweigert: KLINIK\\schmidt.anna auf SIM-VDA01"')
            [IO.File]::WriteAllText($meta, $m); $m | Should -Match 'CANARYMSG'
            $x = Get-ReportData (New-Masked 'endmsg' -Run $copy)
            $flat = { param([string]$t) ($t -replace '\s+', ' ') }
            & $flat $x.copyAll.named | Should -Match 'CANARYMSG verweigert: KLINIK\\schmidt\.anna'
            $anonymous = & $flat $x.copyAll.anonymous
            foreach ($t in 'CANARYMSG', 'schmidt', 'KLINIK', 'SIM-VDA01') { $anonymous | Should -Not -Match $t }
            # the hint without the message, as a masked report has it; the rest of the summary as before
            $anonymous | Should -Match ([regex]::Escape((& $flat $x.guidance.hints.errorNoMessage)))
            $anonymous | Should -Match 'Server 01'
            foreach ($i in @($x.incidents) + @($x.before.incidents)) { $i.copy.anonymous | Should -Not -Match 'CANARYMSG|schmidt' }
            @($x.lagebild.hints) -join ' ' | Should -Match 'CANARYMSG'
        }
        It 'nennt auf der Konsole auch Namen, die einem Wort des Katalogs gleichen' {                                 # Review Task 7, Important 2
            # a user named like a word of the catalogue's texts that neither texts.de.json nor a unit has
            $word = 'Treiber'; $rx = '(?i)(?<![\p{L}\p{N}])' + $word + '(?![\p{L}\p{N}])'
            [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../src/guidance.de.json')) | Should -Match $rx
            [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../src/texts.de.json')) | Should -Not -Match $rx
            $copy = Copy-SimRun $R.Run (Join-Path $TestDrive 'vocab-catalogue')
            $file = Join-Path $copy 'sessions.csv'; [IO.File]::WriteAllText($file, ([IO.File]::ReadAllText($file) -replace ',user002,', ",$word,"))
            $text = & { & $Report -Path $copy -OutFile (Join-Path $TestDrive 'vocab-catalogue.html') -Mask Personen } *>&1 | Out-String
            $text | Should -Match 'Hinweis: 1 Name gleicht einem Wort des Berichts \(Benutzer 02\); Saetze mit diesem Wort'
            $text | Should -Not -Match $rx
        }
        It 'bleibt ohne -Mask bytegleich zum Bericht ohne Maskierungscode, bis auf die Fassungen ohne Namen' {   # Aussage geaendert (P3-R8)
            # without -Mask the report uses the masking code only for the copy texts without names: one mask of level Alles
            # and its replacing; Protect and Clear are never called. Stand-ins: the mask is empty, replacing changes nothing.
            $src = Join-Path $TestDrive 'nomask-src'; [void](New-Item -ItemType Directory $src); Copy-Item (Join-Path $PSScriptRoot '../src/*') $src
            [IO.File]::WriteAllText((Join-Path $src 'WorkerPerf.Mask.ps1'), "#Requires -Version 5.1`nfunction New-WorkerPerfMask { param([string]`$Path, [string]`$Level, `$Texts, `$RoleLabels, `$EventConfig) if (`$Level -ne 'Alles') { throw 'Stufe' }; @{ Level = `$Level } }`nfunction Hide-WorkerPerfReportText(`$Text, `$Mask) { `$Text }`nfunction Protect-WorkerPerfReportData { throw 'aufgerufen' }`nfunction Clear-WorkerPerfReportFreeText { throw 'aufgerufen' }`n")
            $a = Join-Path $TestDrive 'plain-a.html'; $b = Join-Path $TestDrive 'plain-b.html'
            [void](& $Report -Path $R.Run -OutFile $a 6>$null); [void](& (Join-Path $src 'New-WorkerPerfReport.ps1') -Path $R.Run -OutFile $b 6>$null)
            $norm = { param($f) [IO.File]::ReadAllText($f) -replace '"generated":\d+', '"generated":0' -replace '"anonymous":"(?:[^"\\]|\\.)*"', '"anonymous":0' }
            & $norm $a | Should -BeExactly (& $norm $b); (Get-ReportData $a).meta.PSObject.Properties.Name | Should -Not -Contain 'mask'
            # the fields without names are there (16 incidents and the summary) and differ from the named version only by the mask
            $da = Get-ReportData $a; $db = Get-ReportData $b
            @([regex]::Matches([IO.File]::ReadAllText($a), '"anonymous":"').Count) | Should -Be 17
            $db.copyAll.anonymous | Should -BeExactly $db.copyAll.named; $da.copyAll.anonymous | Should -Not -BeExactly $da.copyAll.named
        }
        It 'maskiert die simulierte Stunde, ohne die Laufzeit zu verdoppeln' {                        # Review Focus 5
            $t0 = [Diagnostics.Stopwatch]::StartNew(); [void](New-Masked 'tp'); $plain = $t0.Elapsed.TotalSeconds
            $t1 = [Diagnostics.Stopwatch]::StartNew(); [void](New-Masked 'tm' @{ Mask = 'Alles' }); $masked = $t1.Elapsed.TotalSeconds
            $masked | Should -BeLessThan (2 * $plain)
        }
        It 'legt den maskierten Bericht der Testberichte an' {
            $R.Masked | Should -Not -BeNullOrEmpty; Test-Path $R.Masked | Should -BeTrue
            (Get-ReportData $R.Masked).meta.mask | Should -Be 'Alles'
        }
    }
}
