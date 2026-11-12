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
            $m = [regex]::Replace($m, '("cpu\.steal": \{\s*"Detail": )"[^"]*"(,\s*"Available": )true', '$1"Grund CANARYSRC"$2false')
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
            function Get-Shape($Value, [string]$Path, [string]$Holder, [string]$Field, $Paths, $Keywords) {
                # every key path of the data, and path=value of every string of a keyword field (rule of WorkerPerfMaskKeywordFields)
                if ($null -eq $Value -or $Value -is [System.Text.StringBuilder] -or $Value -is [ValueType]) { return }
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
            function Get-StringPaths($Value) {
                # every path of the data that holds a string (list levels as []), with the number of its strings
                $out = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
                $walk = { param($v, [string]$p)
                    if ($null -eq $v -or $v -is [System.Text.StringBuilder] -or $v -is [ValueType]) { return }
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
            @($Sim.Mask.Entries | ForEach-Object { '{0}:{1}={2}' -f $_.Kind, $_.Name, $_.Replacement }) | Should -Be $exp.ToArray()
            $Sim.MaskedJson | Should -Not -Match 'user0\d\d'; $Sim.MaskedJson | Should -Not -Match 'CONTOSO'; $Sim.MaskedJson | Should -Match 'Benutzer 01'
            Get-LeftNames $Sim.Masked $Sim.Mask | Should -BeNullOrEmpty
        }
        It 'enthaelt bei Personen keinen Benutzer, Client und kein Konto mehr' {
            $Sim.MaskP.Entries.Count | Should -Be 50; $Sim.MaskedJsonP | Should -Not -Match 'user0\d\d'; $Sim.MaskedJsonP | Should -Not -Match 'WS-1\d\d\d'
            $Sim.MaskedJsonP | Should -Match 'CONTOSO'                                           # Domaenen ersetzt erst Alles
            Get-LeftNames $Sim.MaskedP $Sim.MaskP | Should -BeNullOrEmpty
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
            $census = (Get-Content (Join-Path $PSScriptRoot 'MaskCensus.json') -Raw -Encoding UTF8 | ConvertFrom-Json).fields
            $marks = @{}; foreach ($p in $census.PSObject.Properties) { $marks[$p.Name] = [string]$p.Value }
            @($marks.Values | Where-Object { @('name', 'keyword', 'composed', 'copied') -notcontains $_ }) | Should -BeNullOrEmpty
            $values = Get-StringPaths $Sim.Data
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
            $map.level | Should -Be 'Alles'; @($map.entries | Where-Object kind -eq 'user').Count | Should -Be 25; @($map.entries | Where-Object kind -eq 'printer').replacement | Should -Be @('Drucker 01', 'Drucker 02')
            { New-Masked 'x' @{ MaskMapFile = (Join-Path $TestDrive 'y.maskmap.json') } } | Should -Throw '*setzt -Mask voraus*'
            { New-Masked 'SIM-VDA01-bericht' @{ Mask = 'Alles' } } | Should -Throw '*nennt den Worker*'
            { New-Masked 'sim-vda01' @{ Mask = 'Alles' } } | Should -Throw '*nennt den Worker*'
            Test-Path (Join-Path $TestDrive 'SIM-VDA01-bericht.html') | Should -BeFalse
        }
        It 'schreibt bei Personen nur die Arten in die Zuordnung, die diese Stufe ersetzt' {
            $m = Join-Path $TestDrive 'personen.maskmap.json'
            [void](New-Masked 'personen' @{ Mask = 'Personen'; MaskMapFile = $m })
            $map = [IO.File]::ReadAllText($m) | ConvertFrom-Json
            $map.level | Should -Be 'Personen'
            @($map.entries | ForEach-Object kind | Sort-Object -Unique) | Should -Be @('client', 'user')
            @($map.entries | Where-Object kind -eq 'user').Count | Should -Be 25
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
            foreach ($level in 'Personen', 'Alles') {
                $file = New-Masked "canary-$level" @{ Mask = $level; ReportedTime = $at; FocusUser = 'user003' } -Run $canary
                [IO.File]::ReadAllText($file) | Should -Not -Match 'CANARY' -Because $level
                @((Get-ReportData $file).procs | Where-Object { $_.cmd -ne '' }).Count | Should -Be 0
            }
        }
        It 'nennt auf der Konsole die Ersatznamen der Namen, die Woertern des Berichts gleichen' {                   # P2-R12
            $copy = Copy-SimRun $R.Run (Join-Path $TestDrive 'vocab')
            $file = Join-Path $copy 'sessions.csv'; [IO.File]::WriteAllText($file, ([IO.File]::ReadAllText($file) -replace ',user002,', ',soll,'))
            $text = & { & $Report -Path $copy -OutFile (Join-Path $TestDrive 'vocab.html') -Mask Personen } *>&1 | Out-String
            $text | Should -Match 'Hinweis: 1 Name gleicht einem Wort des Berichts \(Benutzer 02\); Saetze mit diesem Wort'
            $text | Should -Not -Match '(?i)\bsoll\b'
        }
        It 'bleibt ohne -Mask bytegleich zum Bericht ohne Maskierungscode' {
            $src = Join-Path $TestDrive 'nomask-src'; [void](New-Item -ItemType Directory $src); Copy-Item (Join-Path $PSScriptRoot '../src/*') $src
            [IO.File]::WriteAllText((Join-Path $src 'WorkerPerf.Mask.ps1'), "#Requires -Version 5.1`nfunction New-WorkerPerfMask { throw 'aufgerufen' }`nfunction Protect-WorkerPerfReportData { throw 'aufgerufen' }`nfunction Clear-WorkerPerfReportFreeText { throw 'aufgerufen' }`n")
            $a = Join-Path $TestDrive 'plain-a.html'; $b = Join-Path $TestDrive 'plain-b.html'
            [void](& $Report -Path $R.Run -OutFile $a 6>$null); [void](& (Join-Path $src 'New-WorkerPerfReport.ps1') -Path $R.Run -OutFile $b 6>$null)
            $norm = { param($f) [IO.File]::ReadAllText($f) -replace '"generated":\d+', '"generated":0' }
            & $norm $a | Should -BeExactly (& $norm $b); (Get-ReportData $a).meta.PSObject.Properties.Name | Should -Not -Contain 'mask'
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
