BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1')
    $script:Src = Join-Path $PSScriptRoot '../src'
    $script:Th = Read-WorkerPerfThresholds (Join-Path $Src 'thresholds.json')
    $script:Roles = Read-WorkerPerfRoles (Join-Path $Src 'roles.json')
    function Write-Json([string]$Name, [string]$Json) { $p = Join-Path $TestDrive $Name; [IO.File]::WriteAllText($p, $Json); $p }
    $script:Entry = '{{"id":"{0}","label":"x","unit":"%","direction":"high","warn":{1},"crit":{2},"ideal":"x","minTicks":3,"trigger":false,"origin":"{3}","source":"x","url":""}}'
}
Describe 'Schwellwerte' {
    It 'liefert <Id> mit den Startwerten der Spezifikation' -TestCases @(
        @{ Id = 'cpu.host';      Warn = 75;  Crit = 90;  MinTicks = 3; Trigger = $true;  Origin = 'Herstellerangabe' }
        @{ Id = 'cpu.queue';     Warn = 2;   Crit = 5;   MinTicks = 3; Trigger = $false; Origin = 'Herstellerangabe' }
        @{ Id = 'cpu.steal';     Warn = 5;   Crit = 10;  MinTicks = 3; Trigger = $false; Origin = 'Faustregel' }
        @{ Id = 'mem.used';      Warn = 75;  Crit = 90;  MinTicks = 3; Trigger = $true;  Origin = 'Herstellerangabe' }
        @{ Id = 'mem.commit';    Warn = 80;  Crit = 90;  MinTicks = 3; Trigger = $false; Origin = 'Herstellerangabe' }
        @{ Id = 'mem.pagesin';   Warn = 10;  Crit = 100; MinTicks = 3; Trigger = $false; Origin = 'Faustregel' }
        @{ Id = 'input.session'; Warn = 150; Crit = 500; MinTicks = 1; Trigger = $true;  Origin = 'Herstellerangabe' }
        @{ Id = 'disk.latency';  Warn = 10;  Crit = 20;  MinTicks = 3; Trigger = $true;  Origin = 'Herstellerangabe' }
        @{ Id = 'smb.latency';   Warn = 10;  Crit = 20;  MinTicks = 3; Trigger = $true;  Origin = 'eigene Annahme' }
        @{ Id = 'ica.rtt';       Warn = 150; Crit = 300; MinTicks = 3; Trigger = $false; Origin = 'Herstellerangabe' }
        @{ Id = 'ica.latency';   Warn = 150; Crit = 250; MinTicks = 3; Trigger = $false; Origin = 'Herstellerangabe' }
        @{ Id = 'probe.connect'; Warn = 50;  Crit = 200; MinTicks = 3; Trigger = $false; Origin = 'eigene Annahme' }
    ) {
        $e = $Th[$Id]
        $e.warn | Should -Be $Warn; $e.crit | Should -Be $Crit; $e.minTicks | Should -Be $MinTicks
        $e.trigger | Should -Be $Trigger; $e.origin | Should -Be $Origin
    }
    It 'kennt zwoelf Signale und Mindestaktivitaet nur bei Antwortzeiten' {
        $Th.Count | Should -Be 12
        $Th['disk.latency'].minOps | Should -Be 5; $Th['smb.latency'].minOps | Should -Be 5; $Th['cpu.host'].minOps | Should -Be 0
        $Th['cpu.queue'].unit | Should -Be ''
    }
    It 'kennzeichnet die Citrix-Werte als zu pruefende Startwerte' {             # Abschlussrunde: Vorbehalt aus Abschnitt 6 der Spezifikation
        $citrix = @($Th.Values | Where-Object { $_.source -like 'Citrix*' })
        $citrix.id | Should -Be @('cpu.host', 'mem.used', 'ica.rtt', 'ica.latency')
        foreach ($e in $citrix) { $e.note | Should -Match 'Startwert aus der Citrix-Dokumentation; vor produktiver Nutzung zu prüfen' }
    }
    It 'nennt den fehlerhaften Eintrag oder die Datei' {
        { Read-WorkerPerfThresholds (Write-Json 'a.json' ('{"thresholds":[' + ($Entry -f 'cpu.host', 95, 90, 'Faustregel') + ']}')) } | Should -Throw '*cpu.host*'
        { Read-WorkerPerfThresholds (Write-Json 'b.json' ('{"thresholds":[' + ($Entry -f 'x.y', 1, 2, 'geraten') + ']}')) } | Should -Throw '*x.y*'
        { Read-WorkerPerfThresholds (Write-Json 'c.json' ('{"thresholds":[' + ($Entry -f 'x.y', 1, 2, 'Faustregel') + ',' + ($Entry -f 'x.y', 1, 2, 'Faustregel') + ']}')) } | Should -Throw '*x.y*'
        { Read-WorkerPerfThresholds (Write-Json 'd.json' '{ kaputt') } | Should -Throw '*d.json*'
    }
    It 'nennt Eintrag und Feld, wenn <Field> keine Zahl ist (<Value>)' -TestCases @(      # Abschlussrunde Minor 10
        @{ Field = 'warn'; Value = '"abc"' }, @{ Field = 'crit'; Value = '"10,5"' }, @{ Field = 'minTicks'; Value = '"drei"' }, @{ Field = 'minTicks'; Value = '2.5' }
        @{ Field = 'minOps'; Value = '"5,5"' }, @{ Field = 'warn'; Value = 'true' }, @{ Field = 'crit'; Value = '[90]' }
    ) {
        $e = [ordered]@{ id = '"x.y"'; label = '"x"'; unit = '"%"'; direction = '"high"'; warn = '75'; crit = '90'; ideal = '"x"'; minTicks = '3'; trigger = 'false'
                         origin = '"Faustregel"'; source = '"x"'; url = '""'; minOps = '0' }
        $e[$Field] = $Value
        $json = '{"thresholds":[{' + (($e.Keys | ForEach-Object { '"' + $_ + '":' + $e[$_] }) -join ',') + '}]}'
        { Read-WorkerPerfThresholds (Write-Json "num-$Field.json" $json) } | Should -Throw "*'x.y'*'$Field'*"
    }
    It 'nimmt Zahlen auch als Text mit Dezimalpunkt und liefert sie als Zahl' {
        $json = '{"thresholds":[' + ($Entry -f 'x.y', '"10.5"', '"20"', 'Faustregel') + ']}'
        $t = Read-WorkerPerfThresholds (Write-Json 'numtext.json' $json)
        $t['x.y'].warn | Should -Be 10.5; $t['x.y'].warn | Should -BeOfType [double]; $t['x.y'].crit | Should -Be 20; $t['x.y'].minTicks | Should -Be 3
    }
}
Describe 'Get-WorkerPerfStatus' {
    It 'stuft Werte ein' {
        Get-WorkerPerfStatus 74.9 $Th['cpu.host'] | Should -Be 0
        Get-WorkerPerfStatus 75 $Th['cpu.host'] | Should -Be 1
        Get-WorkerPerfStatus 90 $Th['cpu.host'] | Should -Be 2
        Get-WorkerPerfStatus ([double]::PositiveInfinity) $Th['probe.connect'] | Should -Be 2
        Get-WorkerPerfStatus ([double]::NaN) $Th['cpu.host'] | Should -BeNullOrEmpty
    }
    It 'kehrt die Richtung bei direction low um' {
        $low = [pscustomobject]@{ direction = 'low'; warn = 20; crit = 10 }
        Get-WorkerPerfStatus 25 $low | Should -Be 0; Get-WorkerPerfStatus 20 $low | Should -Be 1; Get-WorkerPerfStatus 10 $low | Should -Be 2
    }
}
Describe 'Get-WorkerPerfHostSignals' {
    It 'leitet die bewerteten Groessen ab' {
        $tick = [pscustomobject]@{ CpuPct = 50; ProcQueue = 16; StealPct = $null; MemAvailMB = 16384; MemCommittedMB = 40000; MemCommitLimitMB = 50000; PagesInPerSec = 3 }
        $s = Get-WorkerPerfHostSignals -Tick $tick -LogicalProcessors 8 -PhysicalMemoryMB 65536
        $s['cpu.host'] | Should -Be 50; $s['cpu.queue'] | Should -Be 2; $s['mem.used'] | Should -Be 75; $s['mem.commit'] | Should -Be 80; $s['mem.pagesin'] | Should -Be 3
        [double]::IsNaN($s['cpu.steal']) | Should -BeTrue
    }
}
Describe 'Resolve-WorkerPerfRole' {
    It 'ordnet nach Prozessname, Muster und Dienst zu' {
        (Resolve-WorkerPerfRole $Roles 'msmpeng.EXE' '' 0).Label | Should -Be 'Microsoft Defender'
        (Resolve-WorkerPerfRole $Roles 'CtxSvcHost.exe' '' 0).Role | Should -Be 'Citrix'
        (Resolve-WorkerPerfRole $Roles 'svchost.exe' 'Foo;AppIDSvc' 0).Label | Should -Be 'AppLocker'
        (Resolve-WorkerPerfRole $Roles 'svchost.exe' 'Dnscache' 0).Role | Should -Be 'System'
        (Resolve-WorkerPerfRole $Roles 'winword.exe' '' 5).Role | Should -Be ''
        (Resolve-WorkerPerfRole $Roles 'spoolsv.exe' 'Spooler' 0).Role | Should -Be 'Drucken'
        (Resolve-WorkerPerfRole $Roles 'svchost.exe' 'Spooler' 0).Label | Should -Be 'Druckdienst'; (Resolve-WorkerPerfRole $Roles 'cpsvc.exe' '' 0).Label | Should -Be 'Citrix-Druckverwaltung'
        # Task 10: die Prozesse von Nexus KIS (vom Auftraggeber freigegeben); der Dienstprozess steht unter processes
        (Resolve-WorkerPerfRole $Roles 'nexus.framework.healthcare.exe' '' 4).Label | Should -Be 'Nexus KIS'
        (Resolve-WorkerPerfRole $Roles 'NexusService.exe' '' 0).Label | Should -Be 'Nexus KIS'
        @(($Roles | Where-Object Label -eq 'Oracle-Client').processes).Count | Should -Be 0
    }
    It 'nennt den fehlerhaften Rolleneintrag' {
        { Read-WorkerPerfRoles (Write-Json 'r.json' '{"roles":[{"role":"Unsinn","label":"Testprodukt","processes":[],"services":[]}]}') } | Should -Throw '*Testprodukt*'
    }
}
Describe 'Gegenstellen' {
    It 'liefert ohne Datei eine leere Liste' { @(Read-WorkerPerfEndpoints (Join-Path $TestDrive 'fehlt.json')).Count | Should -Be 0 }
    It 'liest die Beispieldatei' { @(Read-WorkerPerfEndpoints (Join-Path $Src 'endpoints.example.json')).Count | Should -Be 3 }
    It 'nennt die fehlerhafte Gegenstelle' { { Read-WorkerPerfEndpoints (Write-Json 'e.json' '{"endpoints":[{"name":"DB","host":"h","port":70000,"role":""}]}') } | Should -Throw '*DB*' }
}
Describe 'CSV-Helfer' {
    It 'schreibt Zahlen unabhaengig von der Kultur' {                          # Review Focus 2
        [cultureinfo]::CurrentCulture = [cultureinfo]'de-DE'
        Format-WorkerPerfNumber 12.5 1 | Should -Be '12.5'
        Format-WorkerPerfNumber 1234567.891 0 | Should -Be '1234568'
        Format-WorkerPerfNumber $null | Should -Be ''
        Format-WorkerPerfNumber ([double]::NaN) | Should -Be ''
    }
    It 'uebersteht Komma, Anfuehrungszeichen, Umlaut und Zeilenumbruch' {      # Review Focus 2
        $name = "M$([char]0xFC)ller, K"
        $line = (Format-WorkerPerfCsvText $name) + ',' + (Format-WorkerPerfCsvText 'sagt "hi"') + ',' + (Format-WorkerPerfCsvText "a`r`nb")
        Split-WorkerPerfCsvLine $line | Should -Be @($name, 'sagt "hi"', 'a  b')
    }
}
Describe 'Formatkonstanten' {
    It 'kennt die sechzehn Dateien mit ihren Kopfzeilen' {                  # 16 statt 13 Dateien: Format 3 bringt drei Dateien dazu
        $WorkerPerfHeaders.Count | Should -Be 16; $WorkerPerfFormatVersion | Should -Be 3; $WorkerPerfReadableFormats | Should -Be @(2, 3)
        $WorkerPerfHeaders['events.csv'].Split(',').Count | Should -Be 20; $WorkerPerfHeaders['events_before.csv'] | Should -Be $WorkerPerfHeaders['events.csv']
        $WorkerPerfHeaders['events.csv'] | Should -Be 'Timestamp,Log,Source,EventId,Level,Group,Kind,App,AppVersion,Module,ModuleVersion,Code,Pid,SessionId,User,Printer,Driver,Service,Object,Text'
        $WorkerPerfHeaders['printdrivers.csv'] | Should -Be 'Name,Manufacturer,Version,Type,Isolation,Files'
        $WorkerPerfHeaders['printqueues.csv'] | Should -Be 'Timestamp,Queue,Jobs,JobErrors,NotReadyErrors'
        $names = @($WorkerPerfHeaders.Keys)
        $names.IndexOf('events_before.csv') | Should -Be ($names.IndexOf('events.csv') + 1); $names[14] | Should -Be 'printdrivers.csv'; $names[15] | Should -Be 'printqueues.csv'
        $WorkerPerfHeaders['processes.csv'] | Should -Be 'P,K,CpuMs,WsKB,PrivKB,ReadBytes,WriteBytes,IoOps,Handles,Threads'
        $WorkerPerfHeaders['ticks.csv'].Split(',').Count | Should -Be 19
    }
}
