BeforeAll {
    . (Join-Path $PSScriptRoot 'LoadHelpers.ps1')
}
Describe 'Import-WorkerPerfRun: Prozesse' {
    BeforeAll {
        $start = Get-Ts -3600
        $info = @("0,100,4,EXCEL.EXE,5,$start,C:\x\EXCEL.EXE,,", "1,200,4,chrome.exe,5,$start,C:\x\chrome.exe,,", "2,300,4,chrome.exe,5,$start,C:\x\chrome.exe,,",
                  "3,4242,4,powershell.exe,0,$start,C:\x\powershell.exe,,", "4,200,4,notepad.exe,5,$(Get-Ts 11),C:\x\notepad.exe,,")
        # K0 EXCEL: 100 MB, CPU in P1, 200 MB in P3.  K1 chrome (PID 200): endet in P2.  K2 chrome: ruht.  K3 Collector.  K4 notepad uebernimmt PID 200 in P3.
        $rows = @('0,0,0,102400,102400,0,0,0,10,2', '0,1,0,51200,51200,0,0,0,10,2', '0,2,0,51200,51200,0,0,0,10,2', '0,3,10,20480,20480,0,0,0,10,2',
                  '1,0,500,102400,102400,1048576,0,5,10,2', '3,0,100,204800,204800,0,0,0,10,2', '3,4,40,10240,10240,0,0,0,10,2')
        $script:Files = @{
            'ticks.csv' = $Ticks; 'snapshots.csv' = $SnapLines; 'procinfo.csv' = $info; 'processes.csv' = $rows; 'procend.csv' = @('2,1')
            'sessions.csv' = @(0..3 | ForEach-Object { "$_,5,alice,DOM,Active,ICA#5,PC1,,0" }) + @(0..3 | ForEach-Object { "$_,0,,,Disconnected,Services,,," })
            'inputdelay_proc.csv' = @('1,5,200,chrome.exe,400', '7,5,200,notepad.exe,250')
        }
        $script:M = Import-TestRun 'p' $Files
        $script:A = $M.Sessions | Where-Object User -eq 'alice'
    }
    It 'fuehrt ruhende Prozesse fort und beendet sie' {
        $A.Ws | Should -Be @(204800, 204800, 153600, 266240); $A.N | Should -Be @(3, 3, 2, 3)
        $A.CpuMs | Should -Be @(0, 500, 0, 140); $A.Io[1] | Should -Be 1048576
    }
    It 'fasst Anwendungen und Paare zusammen' {
        $chrome = $M.Apps | Where-Object Name -eq 'chrome.exe'
        $chrome.Instances | Should -Be 2; $chrome.Ws | Should -Be @(102400, 102400, 51200, 51200)
        $M.Pairs["$($A.Index)|$($chrome.Index)"].Instances | Should -Be 2
        $M.Pairs["$($A.Index)|$($chrome.Index)"].Snaps | Should -Be 4                 # K1 bis P1, K2 ruht durchgehend
        $notepad = $M.Apps | Where-Object Name -eq 'notepad.exe'
        $M.Pairs["$($A.Index)|$($notepad.Index)"].Snaps | Should -Be 1                # K4 erst ab P3
    }
    It 'fuehrt Kennzahlen je Prozess' {
        $M.Proc[0].CpuMs | Should -Be 600; $M.Proc[0].WsMaxKB | Should -Be 204800; $M.Proc[0].FirstP | Should -Be 0; $M.Proc[0].LastP | Should -Be 3
        $M.Proc[0].WsAvgKB | Should -Be 128000                    # drei Schnappschuesse mit 100 MB, einer mit 200 MB
        $M.Proc[1].LastP | Should -Be 1; $M.Proc[0].SessionIndex | Should -Be $A.Index
        $M.Proc[3].IsCollector | Should -BeTrue; $M.Proc[0].IsCollector | Should -BeFalse
        $M.TotalCpuMs | Should -Be 650
    }
    It 'legt die Zeilen je Schnappschuss ab' {
        $M.Rows.Start | Should -Be @(0, 4, 5, 5, 7); $M.Rows.K[4] | Should -Be 0; $M.Rows.CpuMs[4] | Should -Be 500
    }
    It 'ordnet Eingabeverzoegerungen dem Prozess zu, der die PID zu dieser Zeit hatte' {       # Review Focus 4
        $M.InputProc.K | Should -Be @(1, 4)
    }
    It 'heilt fehlende Ende-Meldungen am Stuetzpunkt' {
        $f = $Files.Clone(); $f['procend.csv'] = @()
        $f['snapshots.csv'] = @((New-SnapLine 0 'K'), (New-SnapLine 1), (New-SnapLine 2), (New-SnapLine 3 'K'))
        $f['processes.csv'] = @($Files['processes.csv']) + '3,2,0,51200,51200,0,0,0,10,2' + '3,3,0,20480,20480,0,0,0,10,2'
        $m = Import-TestRun 'heal' $f
        ($m.Sessions | Where-Object User -eq 'alice').N | Should -Be @(3, 3, 3, 3)      # K1 fehlt im Stuetzpunkt P3 und gilt ab dort als beendet
        $m.Proc[1].LastP | Should -Be 2
    }
    It 'beginnt einen Zeitausschnitt am vorhergehenden Stuetzpunkt' {
        $m = Import-TestRun 'cut' $Files @{ From = $Base.AddSeconds(11).DateTime }
        $cutAlice = $m.Sessions | Where-Object User -eq 'alice'
        $m.Snap.N | Should -Be 2; $cutAlice.Ws | Should -Be @(153600, 266240); $cutAlice.CpuMs | Should -Be @(0, 140); $m.Proc[0].CpuMs | Should -Be 100
    }
    It 'gibt den vor dem Zeitausschnitt fortgefuehrten Stand je Prozess weiter' {              # Abschlussrunde I5
        $m = Import-TestRun 'carry' $Files @{ From = $Base.AddSeconds(11).DateTime }
        $state = @{}; for ($i = 0; $i -lt $m.Carried.K.Length; $i++) { $state[[int]$m.Carried.K[$i]] = $m.Carried.WsKB[$i] }
        @($state.Keys | Sort-Object) | Should -Be @(0, 2, 3)                            # K1 endet am ersten Schnappschuss des Ausschnitts, K4 beginnt spaeter
        $state[0] | Should -Be 102400; $state[2] | Should -Be 51200; $state[3] | Should -Be 20480
        $script:M.Carried.K.Length | Should -Be 0                                              # ohne Ausschnitt wird nichts fortgefuehrt
    }
    It 'zaehlt den Stand vor dem Zeitausschnitt nicht als Hoechstwert' {
        $f = $Files.Clone()
        $f['processes.csv'] = @('0,0,0,921600,921600,0,0,0,10,2', '3,0,0,51200,51200,0,0,0,10,2')
        $m = Import-TestRun 'cutmax' $f @{ From = $Base.AddSeconds(15).DateTime }
        $m.Snap.N | Should -Be 1
        $m.Proc[0].WsMaxKB | Should -Be 51200; $m.Proc[0].PrivMaxKB | Should -Be 51200
    }
    It 'mittelt das Working Set ueber die Zeit, nicht ueber die Schnappschuesse' {             # P3-R77
        # Schnappschuesse bei 4, 6, 10 und 16 s statt alle 4 s: jeder steht fuer die Sekunden seit dem vorigen, der erste
        # fuer ein regulaeres Intervall (4 s), also 4, 2, 4 und 6 s
        $f = $Files.Clone()
        $f['snapshots.csv'] = @((New-SnapLine 0 'K'), "1,2,$(Get-Ts 6),2,R,1,1,3,3,20", "2,4,$(Get-Ts 10),4,R,1,1,3,3,20", "3,7,$(Get-Ts 16),6,R,1,1,3,3,20")
        $f['citrix.csv'] = @('1,Citrix_Euem_RoundTrip,5,,RoundtripTime,20', '2,Citrix_Euem_RoundTrip,5,,RoundtripTime,100', '4,Citrix_Euem_RoundTrip,5,,RoundtripTime,40', '7,Citrix_Euem_RoundTrip,5,,RoundtripTime,40')
        $m = Import-TestRun 'weight' $f
        $m.Snap.WeightSec | Should -Be @(4, 2, 4, 6)
        # ein Citrix-Messwert: 20, 100, 40, 40 ms -> (80 + 200 + 160 + 240) / 16; ueber die Schnappschuesse waeren es 50
        $m.Citrix[0].Avg | Should -Be 42.5; $m.Citrix[0].N | Should -Be 4; $m.Citrix[0].Max | Should -Be 100
        # K0 EXCEL: 100 MB in den ersten drei Schnappschuessen (10 s), 200 MB im vierten (6 s); ueber die Schnappschuesse waeren es 128000
        $m.Proc[0].WsAvgKB | Should -Be ((102400 * 10 + 204800 * 6) / 16)
        $m.Proc[0].WsAvgKB | Should -Be 140800
        # chrome in der Sitzung von alice: K1 und K2 mit je 50 MB in den ersten beiden Schnappschuessen (6 s), danach K2 allein (10 s)
        # (names of this model's own: PowerShell names ignore case, a local $a would hide the script's $A used below)
        $wAlice = $m.Sessions | Where-Object User -eq 'alice'; $wChrome = $m.Apps | Where-Object Name -eq 'chrome.exe'; $wNotepad = $m.Apps | Where-Object Name -eq 'notepad.exe'
        $pair = $m.Pairs["$($wAlice.Index)|$($wChrome.Index)"]
        $pair.WsAvgKB | Should -Be 70400                                                # (102400 * 6 + 51200 * 10) / 16
        $pair.WsSumKB | Should -Be 307200; $pair.Snaps | Should -Be 4                   # Summe und Zahl der Schnappschuesse bleiben, was sie sind (Mittel 76800)
        $m.Pairs["$($wAlice.Index)|$($wNotepad.Index)"].WsAvgKB | Should -Be 10240            # K4 nur im letzten Schnappschuss
        # ein Zeitausschnitt: sein erster Schnappschuss steht fuer ein regulaeres Intervall
        (Import-TestRun 'weightcut' $f @{ From = $Base.AddSeconds(5).DateTime }).Snap.WeightSec | Should -Be @(4, 4, 6)
        # gleichmaessige Schnappschuesse: das Mittel ueber die Zeit ist das Mittel der Schnappschuesse
        $chrome = $script:M.Apps | Where-Object Name -eq 'chrome.exe'
        $script:M.Snap.WeightSec | Should -Be @(4, 4, 4, 4); $script:M.Pairs["$($script:A.Index)|$($chrome.Index)"].WsAvgKB | Should -Be 76800
    }
    It 'uebergeht Zeilen jenseits des letzten vollstaendigen Schnappschusses' {        # Review Focus 3
        $f = $Files.Clone(); $f['processes.csv'] = @($Files['processes.csv']) + '4,0,999,1,1,0,0,0,1,1' + '4,0,12'; $f['procend.csv'] = @('2,1', '9,77')
        (Import-TestRun 'abort' $f).TotalCpuMs | Should -Be 650
    }
}
