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
    It 'ordnet den WEM-Agenten der Rolle Citrix und den Client der Druckerzuordnung der Rolle Drucken zu' {
        # the target environment sets up the user environment with Citrix WEM and maps printers with PrinTaurus SmartSpread
        foreach ($p in 'Citrix.Wem.Agent.Service.exe', 'VUEMUIAgent.exe', 'vuemcmdagent.exe', 'VUEMAppCmd.exe', 'AgentCacheUtility.exe') {
            $hit = Resolve-WorkerPerfRole $Roles $p '' 0
            $hit.Role | Should -Be 'Citrix' -Because $p; $hit.Label | Should -Be 'Citrix Workspace Environment Management' -Because $p
        }
        $hit = Resolve-WorkerPerfRole $Roles 'ptsmartspreadclient.EXE' '' 3
        $hit.Role | Should -Be 'Drucken'; $hit.Label | Should -Be 'PrinTaurus SmartSpread'
        # the entries of both roles, in the order of the file (the first match decides)
        @($Roles | Where-Object role -eq 'Citrix' | ForEach-Object { $_.label }) | Should -Be @('Citrix VDA', 'Citrix Workspace Environment Management')
        @($Roles | Where-Object role -eq 'Drucken' | ForEach-Object { $_.label }) | Should -Be @('Druckdienst', 'Citrix-Druckverwaltung', 'PrinTaurus SmartSpread')
        # the processes of the VDA and of the print service keep their entries
        (Resolve-WorkerPerfRole $Roles 'CtxSvcHost.exe' '' 0).Label | Should -Be 'Citrix VDA'; (Resolve-WorkerPerfRole $Roles 'spoolsv.exe' '' 0).Label | Should -Be 'Druckdienst'
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
Describe 'Messkategorien' {
    It 'liefert die Kategorien in der Reihenfolge der Tabelle, jede einmal, ohne Ruecksicht auf die Schreibweise' {   # Review Focus 4
        Resolve-WorkerPerfSkip @('rueckblick', 'PROZESSE', 'Prozesse') | Should -Be @('Prozesse', 'Rueckblick')
        Resolve-WorkerPerfSkip @('Drucken,citrix', ' Zustand ', '') | Should -Be @('Citrix', 'Drucken')   # eine Zeichenkette mit Kommas; Zustand: angenommen, ohne Wirkung
        @(Resolve-WorkerPerfSkip @()).Count | Should -Be 0
    }
    It 'bildet die alten Schalter auf dieselbe Liste ab' {   # Review Focus 5
        Resolve-WorkerPerfSkip @() $true | Should -Be @('Citrix'); Resolve-WorkerPerfSkip @('Citrix') $true | Should -Be @('Citrix')
        Resolve-WorkerPerfSkip @() $false 0 | Should -Be @('Rueckblick'); Resolve-WorkerPerfSkip @('Rueckblick') $false 3 | Should -Be @('Rueckblick')
    }
    It 'lehnt einen unbekannten Wert mit den gueltigen Werten ab' {
        { Resolve-WorkerPerfSkip @('Prozesse', 'Netz') } | Should -Throw "*'Netz'*Gueltige Werte: Prozesse, Laufwerke, Citrix, Ereignisse, Rueckblick, Drucken, Gegenstellen, Zustand.*"
    }
    It 'fuehrt die acht Kategorien mit Dateien, Quellen und Stellen der Tabelle' {
        @($WorkerPerfCategories.Keys) | Should -Be @('Prozesse', 'Laufwerke', 'Citrix', 'Ereignisse', 'Rueckblick', 'Drucken', 'Gegenstellen', 'Zustand')
        @($WorkerPerfCategories.Keys | Where-Object { -not $WorkerPerfCategories[$_].Active }) | Should -Be @('Zustand')
        $WorkerPerfCategories.Prozesse.Places | Should -Be @('procs', 'apps', 'sessions.resources', 'incidents.contributors', 'incidents.delayProcs', 'print.processes')
        @($WorkerPerfCategories.Ereignisse.Sources).Count | Should -Be 0; $WorkerPerfCategories.Rueckblick.Files | Should -Be @('events_before.csv')
        # jede Datei gehoert hoechstens einer Kategorie; die Basis bleibt uebrig
        $files = @($WorkerPerfCategories.Values | ForEach-Object { $_.Files })
        @($files | Sort-Object -Unique).Count | Should -Be $files.Count
        @($WorkerPerfHeaders.Keys | Where-Object { $files -notcontains $_ }) | Should -Be @('ticks.csv', 'inputdelay.csv', 'snapshots.csv', 'sessions.csv')
    }
    It 'vermerkt die Quellen einer weggelassenen Kategorie und die Protokolle nur, wenn Ereignisse und Rueckblick fehlen' {
        Get-WorkerPerfSkipDetail @('Ereignisse', 'Rueckblick') | Should -Be 'abgeschaltet (-Skip Ereignisse,Rueckblick)'
        'abgeschaltet (-Skip Citrix)' | Should -Match $WorkerPerfSkipDetailPattern; 'abgeschaltet (-NoCitrix)' | Should -Not -Match $WorkerPerfSkipDetailPattern
        $new = { [ordered]@{ 'ica.rtt' = @{ Available = $false; Detail = 'abgeschaltet (-NoCitrix)' }; 'events.system' = @{ Available = $true; Detail = 'x' }; sessions = @{ Available = $true; Detail = 'x' } } }
        $s = & $new; Set-WorkerPerfSkippedSources -Sources $s -Skip @('Citrix', 'Ereignisse') -EventLogIds @('system', 'application')
        $s['ica.rtt'].Detail | Should -Be 'abgeschaltet (-Skip Citrix)'; $s['ica.latency'].Available | Should -BeFalse   # angelegt
        $s['events.system'].Available | Should -BeTrue; $s.Contains('events.application') | Should -BeFalse; $s.sessions.Available | Should -BeTrue
        $s = & $new; Set-WorkerPerfSkippedSources -Sources $s -Skip @('Ereignisse', 'Rueckblick') -EventLogIds @('application')
        foreach ($id in 'events.system', 'events.application') { $s[$id].Available | Should -BeFalse; $s[$id].Detail | Should -Be 'abgeschaltet (-Skip Ereignisse,Rueckblick)' }
        $s['ica.rtt'].Detail | Should -Be 'abgeschaltet (-NoCitrix)'   # Citrix nicht weggelassen: der Eintrag der Quelle bleibt
    }
}
Describe 'Zustandsbild: Format und Werteliste' {
    It 'fuehrt elf Bereiche in fester Reihenfolge und jeden Wert bei genau einem Bereich' {
        $WorkerPerfHealthFormatVersion | Should -Be 1
        $WorkerPerfHealthAreas | Should -Be @('size', 'operation', 'sessions', 'vda', 'profile', 'print', 'security', 'network', 'events', 'maintenance', 'apps')
        $count = @{}
        foreach ($id in $WorkerPerfHealthValues.Keys) {
            $v = $WorkerPerfHealthValues[$id]; $id | Should -BeLike ($v.Area + '.*'); $count[$v.Area] = 1 + [int]$count[$v.Area]
            $v.Type | Should -Match '^(number|bool|time|list|text(:(host|hosts|share|path|user|client|domain|address|protected|free))?)$' -Because $id
            if ($v.Type -eq 'list') {
                @($v.Fields.Keys).Count | Should -BeGreaterThan 0 -Because $id
                foreach ($t in $v.Fields.Values) { $t | Should -Match '^(number|bool|time|value|text(:(host|hosts|share|path|user|client|domain|address|protected|free))?)$' -Because $id }
            }
        }
        $want = @{ size = 16; operation = 8; sessions = 3; vda = 16; profile = 5; print = 8; security = 19; network = 12; events = 1; maintenance = 14; apps = 1 }
        foreach ($a in $WorkerPerfHealthAreas) { $count[$a] | Should -Be $want[$a] -Because $a }
        @($WorkerPerfHealthValues.Keys).Count | Should -Be 103
        $WorkerPerfHealthValues['vda.controllers'].Fields['Entry'] | Should -Be 'text:host'; $WorkerPerfHealthValues['maintenance.tasks'].Fields['Path'] | Should -Be 'text:free'
        $WorkerPerfHealthValues['vda.wemServer'].Type | Should -Be 'text:host'; $WorkerPerfHealthValues['vda.wemCacheLocation'].Type | Should -Be 'text:path'
        @($WorkerPerfHealthValues['operation.volumes'].Fields.Keys) | Should -Be @('Drive', 'SizeGB', 'FreeGB', 'FileSystem', 'System', 'PageFile')
        @($WorkerPerfHealthValues['apps.probes'].Fields.Keys) | Should -Be @('App', 'Id', 'Kind', 'Read', 'State', 'Reason', 'Value', 'Names')
        $WorkerPerfHealthValues['apps.probes'].Fields['Value'] | Should -Be 'value'; $WorkerPerfHealthValues['apps.probes'].Fields['Names'] | Should -Be 'text:free'
        $WorkerPerfHealthValues['operation.lastBoot'].Type | Should -Be 'time'; $WorkerPerfHealthValues['print.mappingClientVersion'].Type | Should -Be 'text'; $WorkerPerfHealthValues['size.memTotalMB'].Unit | Should -Be 'MB'
        @($WorkerPerfHealthValues.Keys | Where-Object { -not $WorkerPerfHealthValues[$_].Documented }) | Should -Be @('size.vmtoolsPresent', 'size.vmtoolsService',
            'operation.pendingServicing', 'operation.pendingUpdate', 'vda.policyRaw', 'profile.policyGpo', 'profile.policyStudio', 'security.applockerCollections')
    }
    It 'ergaenzt einen Bereich um die nicht gelesenen Werte und stuft ihn ein' {   # Review Focus 1
        $a = Complete-WorkerPerfHealthArea 'events' @{ 'events.logs' = (New-WorkerPerfHealthValue 'read' '' @()) } 12.5
        $a.Status | Should -Be 'read'; $a.DurationMs | Should -Be 12.5; $a.Error | Should -Be ''
        $p = Complete-WorkerPerfHealthArea 'print' @{ 'print.queueCount' = (New-WorkerPerfHealthValue 'read' '' 2); 'print.spooler' = (New-WorkerPerfHealthValue 'absent' 'notInstalled') } 10 '' $true
        $p.Status | Should -Be 'partial'
        @($p.Values.Keys) | Should -Be @('print.isolationExecution', 'print.isolationOverride', 'print.queueCount', 'print.spooler', 'print.spoolerStartMode', 'print.citrixPrintService', 'print.operationalLog', 'print.mappingClientVersion')
        $p.Values['print.operationalLog'].State | Should -Be 'unreadable'; $p.Values['print.operationalLog'].Reason | Should -Be 'timeout'
        $f = Complete-WorkerPerfHealthArea 'vda' @{} 3 'Zugriff verweigert'
        $f.Status | Should -Be 'failed'; $f.Error | Should -Be 'Zugriff verweigert'; $f.Values['vda.version'].Reason | Should -Be 'error'
        { Complete-WorkerPerfHealthArea 'vda' @{ 'print.spooler' = (New-WorkerPerfHealthValue 'read' '' 'Running') } 1 } | Should -Throw '*print.spooler*'
        { New-WorkerPerfHealthValue 'gelesen' } | Should -Throw; { New-WorkerPerfHealthValue 'unreadable' 'kaputt' } | Should -Throw
    }
    It 'laesst eine Liste eine Liste sein, auch mit einem oder keinem Eintrag' {
        $one = Complete-WorkerPerfHealthArea 'size' @{ 'size.pagefiles' = (New-WorkerPerfHealthValue 'read' '' ([ordered]@{ Path = 'C:\pagefile.sys'; AllocatedMB = 1 }))
            'size.netAdapters' = (New-WorkerPerfHealthValue 'read' '' @()) } 1
        ($one.Values['size.pagefiles'].Value -is [array]) | Should -BeTrue; @($one.Values['size.pagefiles'].Value).Count | Should -Be 1
        ($one.Values['size.netAdapters'].Value -is [array]) | Should -BeTrue; @($one.Values['size.netAdapters'].Value).Count | Should -Be 0
        ($one | ConvertTo-Json -Depth 10 -Compress) | Should -Match '"size\.pagefiles":\{"State":"read","Reason":"","Value":\[\{"Path"'
    }
    It 'schreibt den Kopf des Zustandsbilds und fuellt fehlende Bereiche' {
        $at = [datetime]::SpecifyKind([datetime]'2026-01-15T08:00:00', [DateTimeKind]::Local)
        $h = New-WorkerPerfHealth $at 4210 @{ events = (Complete-WorkerPerfHealthArea 'events' @{ 'events.logs' = (New-WorkerPerfHealthValue 'read' '' @()) } 5) }
        $h.FormatVersion | Should -Be 1; $h.DurationMs | Should -Be 4210; $h.ReadAt | Should -Match '^2026-01-15T08:00:00\.0000000[+-]\d\d:\d\d$'
        @($h.Areas.Keys) | Should -Be $WorkerPerfHealthAreas; $h.Areas['size'].Status | Should -Be 'failed'; $h.Areas['size'].Error | Should -Be 'notRead'; $h.Areas['events'].Status | Should -Be 'read'
        $h.Areas['apps'].Values['apps.probes'].State | Should -Be 'unreadable'
        $WorkerPerfHealthAreaErrors | Should -Be @('budget', 'noReader', 'notRead', 'notInFile')
        @($WorkerPerfHealthWemServices).Count | Should -Be 3; $WorkerPerfHealthWemServices[0] | Should -Be @('Citrix WEM Agent Host Service', 'Norskale Agent Host Service'); $WorkerPerfHealthWemServices[2] | Should -Be @('System Event Notification Service')
        ConvertTo-WorkerPerfHealthTime ([datetime]::new(1970, 1, 2, 0, 0, 0, [DateTimeKind]::Utc)) | Should -Be 86400000; ConvertTo-WorkerPerfHealthTime ([datetime]::MinValue) | Should -Be 0
    }
    It 'speichert keine Zahl, die nicht endlich ist' {
        # Windows PowerShell 5.1 schriebe NaN und Infinity ohne Anfuehrungszeichen: die ganze Datei waere kein gueltiges JSON
        (New-WorkerPerfHealthValue 'read' '' ([double]::NaN)).State | Should -Be 'unreadable'; (New-WorkerPerfHealthValue 'read' '' ([double]::NaN)).Reason | Should -Be 'error'
        (New-WorkerPerfHealthValue 'read' '' ([double]::PositiveInfinity)).Value | Should -BeNullOrEmpty; (New-WorkerPerfHealthValue 'read' '' 96.5).Value | Should -Be 96.5
        $a = Complete-WorkerPerfHealthArea 'profile' @{ 'profile.containers' = (New-WorkerPerfHealthValue 'read' '' @([ordered]@{ Location = '\\fs01\profile$\a.vhdx'; UsedPct = [double]::NaN })) } 1
        $a.Values['profile.containers'].State | Should -Be 'read'; $a.Values['profile.containers'].Value[0].UsedPct | Should -BeNullOrEmpty
        ($a | ConvertTo-Json -Depth 10) | Should -Not -Match 'NaN|Infinity'
    }
}
