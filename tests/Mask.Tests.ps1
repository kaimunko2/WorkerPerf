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
            'share:\\fs02\upm$=Freigabe 02', 'server:fs02=Server 04', 'address:10.1.2.3=Adresse 01', 'printer:PRN-EG-01=Drucker 01', 'sid:S-1-5-21-1-2-3-1108=Konto 01')
    }
    It 'ersetzt bei Personen nur Benutzer, Clients und Konten' {
        Get-Entries 'Personen' | Should -Be @('user:mueller=Benutzer 01', 'client:WS-0001=Client 01', 'client:WS-0002=Client 02', 'user:mu=Benutzer 02', 'client:WS-0003=Client 03', 'sid:S-1-5-21-1-2-3-1108=Konto 01')
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
            'server:nas07=Server 06')
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
