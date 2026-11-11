BeforeAll {
    $script:Probe = Join-Path $PSScriptRoot '../src/Test-WorkerPerfSources.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Probe, [ref]$null, [ref]$null)
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Hide-WorkerPerfName' }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
    # Further pure helpers that run on Linux.
    foreach ($name in 'New-WorkerPerfNameMask', 'Hide-WorkerPerfMaskedText', 'Get-ProbeMaskNames', 'Get-ProbeMaskDomains', 'Hide-ProbeText',
        'Get-ProbeEndpointErrorClass', 'Get-ProbeMaskGap', 'Protect-ProbeValue', 'Get-ProbeFileName', 'Join-ProbeNames', 'Add-ProbeMaskNames', 'Get-ProbeErrorText',
        'Read-ProbeNames', 'Update-ProbeMaskFromSessions', 'Invoke-ProbeCatalogue', 'Add-ProbeServerNames', 'Add-ProbeShareServer', 'Get-ProbeUncHosts', 'Get-ProbeTexts', 'Copy-ProbeValue',
        'Get-Prop', 'Get-ProbeEventFieldNames', 'Get-ProbeEventSummary', 'Get-ProbeDriverSummary', 'Get-ProbeEventQuery', 'Resolve-ProbeEventProviders',
        'Select-ProbeDriverValueNames', 'Split-ProbeProviderChunks', 'ConvertTo-ProbeProviderInfo', 'Read-ProbeEventRecords', 'Get-ProbeChunkSize',
        'Get-ProbeDriverAttributeCounts', 'Get-ProbeIsolationPolicy', 'Get-ProbeInstanceCount', 'ConvertTo-ProbeDword', 'Test-ProbeQueryName',
        'Get-ProbeEventLog', 'Get-ProbeCitrixRoots', 'Get-ProbeEffectiveIsolation', 'Get-ProbeIsolationGroupMap') {
        $f = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
        if ($null -ne $f) { . ([scriptblock]::Create($f.Extent.Text)) }
    }
    # The settings of the probe ($script:ProbeMaxEvents and the like) that these helpers read.
    foreach ($a in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -like '$script:Probe*' -and
                $n.Parent -eq $ast.EndBlock }, $true)) {
        . ([scriptblock]::Create($a.Extent.Text))
    }
    $script:Checks = @(& $Probe -ListChecks)
    # The lists of names to mask and the pattern built from them live in script variables of the probe.
    function Reset-TestMask {
        $script:ProbeUsers = @(); $script:ProbeDomains = @(); $script:ProbeClients = @(); $script:ProbeComputers = @()
        $script:ProbeMask = $null; $script:ProbeMaskNoUsers = $null
    }
    Reset-TestMask
    # Ein Leser wie EventLogReader: ReadEvent liefert die Datensaetze nacheinander, $null am Ende; ein Eintrag mit Fail wirft.
    function New-TestEventReader([object[]]$Items, [string]$Provider = 'Application Error') {
        $reader = [pscustomobject]@{ Items = $Items; Next = 0; XmlCalls = 0; Disposed = 0; Provider = $Provider }
        $reader | Add-Member ScriptMethod ReadEvent {
            if ($this.Next -ge @($this.Items).Count) { return $null }
            $item = $this.Items[$this.Next]; $this.Next++
            if ($item.Fail) { throw 'Die Daten sind ungueltig' }
            $owner = $this
            $time = $null
            if ($null -ne $item.PSObject.Properties['Time']) { $time = $item.Time }
            $rec = [pscustomobject]@{ ProviderName = $owner.Provider; Id = $item.Id; Owner = $owner; TimeCreated = $time }
            $rec | Add-Member ScriptMethod ToXml { $this.Owner.XmlCalls++; "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><EventData><Data Name='F'>geheim</Data></EventData></Event>" }
            $rec | Add-Member ScriptMethod Dispose { $this.Owner.Disposed++ }
            $rec
        }
        $reader
    }
}
Describe 'Quellen-Pruefskript' {
    It 'listet die Pruefungen ohne Systemzugriff' {
        $Checks.Id | Should -Be @('system', 'process.snapshot', 'sessions.wts', 'services.map', 'perf.cpu', 'perf.queue', 'perf.steal', 'perf.memory',
            'perf.disk.total', 'perf.network', 'perf.volumes', 'perf.shares', 'perf.input.session', 'perf.input.process', 'perf.ica',
            'profile.volumes', 'events.defender', 'events.applocker', 'events.application', 'events.system', 'events.printservice',
            'events.smbclient', 'events.profileservice', 'events.session', 'print.drivers', 'print.queues', 'security.products', 'user.processes', 'endpoints')
    }
    It 'ruft in jeder Pruefung eine Funktion auf, die das Skript definiert' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Probe, [ref]$null, [ref]$null)
        $defined = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
        $assignment = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$script:Catalogue' }, $false)
        $entries = @(& ([scriptblock]::Create($assignment.Right.Extent.Text)))
        @($entries).Count | Should -Be @($Checks).Count
        @($entries | Where-Object { -not ($_.Run -is [string]) } | ForEach-Object { $_.Id }) | Should -BeNullOrEmpty
        @($entries | Where-Object { $defined -notcontains $_.Run } | ForEach-Object { '{0} -> {1}' -f $_.Id, $_.Run }) | Should -BeNullOrEmpty
    }
    It 'deckt jedes bewertete Signal ab' {
        $covered = @($Checks | ForEach-Object { $_.Signals })
        foreach ($id in 'cpu.host', 'cpu.queue', 'cpu.steal', 'mem.used', 'mem.commit', 'mem.pagesin', 'input.session', 'disk.latency', 'smb.latency', 'ica.rtt', 'ica.latency', 'probe.connect') {
            $covered | Should -Contain $id
        }
    }
    It 'maskiert Benutzer- und Servernamen' {
        Hide-WorkerPerfName -Text '\\fs01.klinik.local\upm$\mueller.KLINIK\Win2022\ProfileContainer.vhdx' -Users @('mueller', 'mu') |
            Should -Be '\\<server>\upm$\<user>.<domain>\Win2022\ProfileContainer.vhdx'            # Abschlussrunde I8: ohne den Domaenenteil
        Hide-WorkerPerfName -Text 'C:\Users\Mueller\AppData' -Users @('mueller') | Should -Be 'C:\Users\<user>\AppData'
        Hide-WorkerPerfName -Text 'C:\Program Files\Simulator' -Users @('mu') | Should -Be 'C:\Program Files\Simulator'
    }
    It 'maskiert Servernamen auch mitten im Text' {
        Hide-WorkerPerfName -Text 'Zugriff verweigert: \\fs01\upm$\x' -Users @() | Should -Be 'Zugriff verweigert: \\<server>\upm$\x'
        Hide-WorkerPerfName -Text "Pfad '\\fs01.klinik.local\share' fehlt" -Users @() | Should -Be "Pfad '\\<server>\share' fehlt"
        Hide-WorkerPerfName -Text 'Volume \\?\Volume{1}\ und \\.\pipe' -Users @() | Should -Be 'Volume \\?\Volume{1}\ und \\.\pipe'
    }
    It 'nimmt Profilordner ohne WTS-Sitzungen in die Maskierung auf' {
        $names = @(Get-ProbeMaskNames -SessionUsers @() -ProfilePaths @('C:\Users\mueller.KLINIK', 'C:\Users\schmidt', '') -CurrentUser 'admin')
        foreach ($n in 'mueller.KLINIK', 'mueller', 'schmidt', 'admin') { $names | Should -Contain $n }
        Hide-WorkerPerfName -Text '\\fs01\upm$\schmidt.KLINIK\x.vhdx' -Users $names | Should -Be '\\<server>\upm$\<user>.<domain>\x.vhdx'
    }
    It 'schreibt keine Hostnamen der Gegenstellen' {
        Reset-TestMask
        Add-ProbeServerNames @('ora-db.example.local', '10.1.2.3', '') | Should -BeGreaterThan 0
        Hide-ProbeText 'Oracle auf ORA-DB' | Should -Be 'Oracle auf <server>'                    # auch das erste Namensglied
        Hide-ProbeText 'Listener ora-db.example.local:1521' | Should -Be 'Listener <server>:1521'
        Hide-ProbeText 'Proxy 10.1.2.3' | Should -Be 'Proxy <server>'
        Hide-ProbeText 'Datenbank' | Should -Be 'Datenbank'
        Reset-TestMask
    }
    It 'verweigert die Messung ausserhalb von Windows' -Skip:$IsWindows { { & $Probe } | Should -Throw '*Windows*' }
}
Describe 'Keine Namen im Ergebnis des Pruefskripts' {                              # Abschlussrunde I8
    It 'maskiert Domaenen, Clientnamen und den Computernamen' {
        $a = @{ Users = @('mueller'); Domains = @('KLINIK', 'klinik.local'); Clients = @('WS-0815'); Computers = @('VDA01') }
        Hide-WorkerPerfName -Text 'ICA-CGP 3 (KLINIK\mueller) von WS-0815 auf vda01.klinik.local' @a | Should -Be 'ICA-CGP 3 (<domain>\<user>) von <client> auf <server>.<domain>'
        Hide-WorkerPerfName -Text 'Anmeldung mueller@klinik.local an VDA01' @a | Should -Be 'Anmeldung <user>@<domain> an <server>'
        Hide-WorkerPerfName -Text 'C:\Users\mueller.KLINIK' @a | Should -Be 'C:\Users\<user>.<domain>'
        Hide-WorkerPerfName -Text 'Klinikum und WS-08151' @a | Should -Be 'Klinikum und WS-08151'             # nur ganze Namen
    }
    It 'entfernt den Domaenenteil auch ohne bekannte Domaene' {
        Hide-WorkerPerfName -Text 'C:\Users\mueller.KLINIK\AppData' -Users @('mueller') | Should -Be 'C:\Users\<user>.<domain>\AppData'
        Hide-WorkerPerfName -Text 'Konto KLINIK\mueller gesperrt' -Users @('mueller') | Should -Be 'Konto <domain>\<user> gesperrt'
        Hide-WorkerPerfName -Text 'mueller@klinik.local' -Users @('mueller') | Should -Be '<user>@<domain>'
        Hide-WorkerPerfName -Text 'C:\Users\mueller\Profile_mueller.vhdx' -Users @('mueller') | Should -Be 'C:\Users\<user>\Profile_<user>.vhdx'   # Pfade und Dateiendungen bleiben
    }
    It 'sammelt Domaenen aus Sitzungen, Umgebung und Profilordnern' {
        $d = @(Get-ProbeMaskDomains -SessionDomains @('KLINIK', '', 'KLINIK') -UserDomain 'ADMIN' -UserDnsDomain 'klinik.local' -ProfilePaths @('C:\Users\mueller.KLINIK2', 'C:\Users\schmidt.000', 'C:\Users\meier'))
        foreach ($n in 'KLINIK', 'ADMIN', 'klinik.local', 'KLINIK2') { $d | Should -Contain $n }
        $d | Should -Not -Contain '000'; $d | Should -Not -Contain ''
    }
    It 'maskiert jeden Text des Ergebnisses noch einmal vor dem Schreiben' {
        $script:ProbeUsers = @('mueller'); $script:ProbeDomains = @('KLINIK'); $script:ProbeClients = @('WS-0815'); $script:ProbeComputers = @('VDA01')
        $script:ProbeMask = $null; $script:ProbeMaskNoUsers = $null
        $data = [ordered]@{ Id = 'x'; Ok = $true; N = 3; Detail = 'Fehler auf VDA01'; Data = [ordered]@{ List = @('KLINIK\mueller', 7, $null, [ordered]@{ Path = '\\fs01\upm$\mueller' }); Client = 'WS-0815' } }
        $safe = Protect-ProbeValue $data
        ($safe | ConvertTo-Json -Depth 8 -Compress) | Should -Be '{"Id":"x","Ok":true,"N":3,"Detail":"Fehler auf <server>","Data":{"List":["<domain>\\<user>",7,null,{"Path":"\\\\<server>\\upm$\\<user>"}],"Client":"<client>"}}'
        Reset-TestMask
    }
    It 'meldet Fehler einer Gegenstelle nur als Klasse' {
        $sock = { param($code) New-Object System.Net.Sockets.SocketException ([int][System.Net.Sockets.SocketError]::$code) }
        Get-ProbeEndpointErrorClass (& $sock 'ConnectionRefused') | Should -Be 'refused'
        Get-ProbeEndpointErrorClass (& $sock 'TimedOut') | Should -Be 'timeout'
        Get-ProbeEndpointErrorClass (& $sock 'HostNotFound') | Should -Be 'dns'
        Get-ProbeEndpointErrorClass (& $sock 'NoData') | Should -Be 'dns'
        Get-ProbeEndpointErrorClass (& $sock 'NetworkUnreachable') | Should -Be 'other'
        Get-ProbeEndpointErrorClass (New-Object System.Exception ('aussen', (& $sock 'ConnectionRefused'))) | Should -Be 'refused'     # auch als innere Ausnahme
        Get-ProbeEndpointErrorClass (New-Object System.InvalidOperationException 'No connection could be made because the target machine actively refused it 10.1.2.3:1521') | Should -Be 'other'
    }
    It 'schreibt keine Datei, wenn eine aktive Sitzung ohne Benutzernamen bleibt' {
        $s = { param($State, $User) [pscustomobject]@{ SessionId = 1; State = $State; User = $User } }
        $noName = @((& $s 'Disconnected' ''), (& $s 'Active' 'mueller'), (& $s 'Active' ''))
        Get-ProbeMaskGap -Sessions $noName -WtsOk $true -ProfilesOk $false | Should -Match 'aktive Sitzung'
        # auch mit lesbaren Profilordnern: sie belegen nicht, dass der Name dieser Sitzung darunter ist (temporaeres Profil)
        Get-ProbeMaskGap -Sessions $noName -WtsOk $true -ProfilesOk $true | Should -Match '1 aktive Sitzung.*administrativen Konsole'
        Get-ProbeMaskGap -Sessions @((& $s 'Disconnected' ''), (& $s 'Active' 'mueller')) -WtsOk $true -ProfilesOk $false | Should -BeNullOrEmpty
        Get-ProbeMaskGap -Sessions @() -WtsOk $false -ProfilesOk $false | Should -Match 'nicht ermittelbar'
        Get-ProbeMaskGap -Sessions @() -WtsOk $false -ProfilesOk $true | Should -BeNullOrEmpty
    }
    It 'benennt die Ergebnisdatei ohne den Computernamen' {
        Get-ProbeFileName ([datetime]'2026-11-11T07:08:09') | Should -Be 'vda-probe_20261111-070809.json'
        $text = [IO.File]::ReadAllText($Probe)
        $text | Should -Not -Match 'COMPUTERNAME\s*\}?\s*[,;]?\s*\(Get-Date'              # nicht mehr im Dateinamen
        $text | Should -Not -Match '(?m)^\s*Computer\s*='                                  # und nicht im Ergebnis
    }
}
Describe 'Namen, die das Pruefskript nicht aus einer Liste kennt' {
    It 'ersetzt Konten-SIDs und den Namen daneben' {
        $sid = 'S-1-5-21-1111111111-2222222222-3333333333-1107'
        Hide-WorkerPerfName -Text "\\fs01\profile`$\${sid}_mueller\Profile_mueller.VHDX" -Users @('mueller') | Should -Be '\\<server>\profile$\<sid>_<user>\Profile_<user>.VHDX'
        # derselbe Pfad, ohne dass der Benutzer in einer Liste steht
        Hide-WorkerPerfName -Text "\\fs01\profile`$\${sid}_neu\Profile_neu.VHDX" -Users @() | Should -Be '\\<server>\profile$\<sid>_<user>\Profile_<user>.VHDX'
        Hide-WorkerPerfName -Text "D:\Container\neu_$sid\ODFC_neu.vhd" -Users @() | Should -Be 'D:\Container\<user>_<sid>\ODFC_<user>.vhd'
        Hide-WorkerPerfName -Text "Konto $sid gesperrt" -Users @() | Should -Be 'Konto <sid> gesperrt'
        Hide-WorkerPerfName -Text 'Entra-Konto S-1-12-1-1111111111-2222222222-3333333333-4444444444' -Users @() | Should -Be 'Entra-Konto <sid>'
    }
    It 'laesst bekannte SIDs und aehnliche Texte stehen' {
        Hide-WorkerPerfName -Text 'SYSTEM S-1-5-18, Administratoren S-1-5-32-544' -Users @() | Should -Be 'SYSTEM S-1-5-18, Administratoren S-1-5-32-544'
        Hide-WorkerPerfName -Text 'C:\Program Files\Profile_Tool\Profile.vhdx' -Users @() | Should -Be 'C:\Program Files\Profile_Tool\Profile.vhdx'
    }
    It 'ersetzt Servernamen in den Sonderformen von UNC-Pfaden' {
        Hide-WorkerPerfName -Text '\\?\UNC\fs01.klinik.local\upm$\x.vhdx' -Users @() | Should -Be '\\?\UNC\<server>\upm$\x.vhdx'
        Hide-WorkerPerfName -Text 'Geraet \Device\Mup\fs01\upm$\x' -Users @() | Should -Be 'Geraet \Device\Mup\<server>\upm$\x'
        Hide-WorkerPerfName -Text 'Volume \\?\Volume{1}\ und \Device\HarddiskVolume3' -Users @() | Should -Be 'Volume \\?\Volume{1}\ und \Device\HarddiskVolume3'
    }
    It 'wendet die festen Regeln vor den Namen an, auch wenn ein Benutzer wie ein fester Begriff heisst' {
        $sid = 'S-1-5-21-111-222-333-1105'
        Hide-WorkerPerfName -Text "\\fs01\p\${sid}_neu\Profile_neu.vhdx" -Users @('profile', 's', '222') | Should -Be '\\<server>\p\<sid>_<user>\<user>_<user>.vhdx'
        Hide-WorkerPerfName -Text 'Konto <sid> von <user> auf <server>' -Users @('sid', 'user', 'server') | Should -Be 'Konto <<user>> von <<user>> auf <<user>>'   # fremder Text mit spitzen Klammern
        Hide-WorkerPerfName -Text "Konto $sid" -Users @('sid') | Should -Be 'Konto <sid>'                          # der eigene Ersatz wird nicht noch einmal ersetzt
        Hide-WorkerPerfName -Text 'C:\Users\user\x und \\fs01\y' -Users @('user', 'server') | Should -Be 'C:\Users\<user>\x und \\<server>\y'
    }
    It 'erkennt Containerdateien auch in einem Satz' {
        Hide-WorkerPerfName -Text 'Datei "Profile_neu.vhdx" fehlt' -Users @() | Should -Be 'Datei "Profile_<user>.vhdx" fehlt'
        Hide-WorkerPerfName -Text 'Datei Profile_neu.vhdx fehlt' -Users @() | Should -Be 'Datei Profile_<user>.vhdx fehlt'
        Hide-WorkerPerfName -Text 'UserProfile_Service.vhdx' -Users @() | Should -Be 'UserProfile_Service.vhdx'
    }
    It 'ersetzt Servernamen in den Geraetepfaden des Netzwerk-Redirectors' {
        Hide-WorkerPerfName -Text '\??\UNC\fs01\upm$\x' -Users @() | Should -Be '\??\UNC\<server>\upm$\x'
        Hide-WorkerPerfName -Text '\Device\LanmanRedirector\;Z:0000000000012345\fs01\daten\x' -Users @() | Should -Be '\Device\LanmanRedirector\;Z:0000000000012345\<server>\daten\x'
        Hide-WorkerPerfName -Text '\Device\Mup\;LanmanRedirector\;Z:0000000000012345\fs01\daten' -Users @() | Should -Be '\Device\Mup\;LanmanRedirector\;Z:0000000000012345\<server>\daten'
    }
    It 'liefert beim zweiten Durchgang dasselbe Ergebnis' {
        $a = @{ Users = @('mueller'); Domains = @('KLINIK'); Clients = @('WS-0815'); Computers = @('VDA01') }
        foreach ($text in '\\fs01\profile$\S-1-5-21-1-2-3-1107_mueller\Profile_mueller.VHDX', '\\?\UNC\fs01\upm$\neu_S-1-5-21-1-2-3-1108\x', 'ICA-CGP 3 (KLINIK\mueller) von WS-0815 auf VDA01') {
            $once = Hide-WorkerPerfName -Text $text @a
            Hide-WorkerPerfName -Text $once @a | Should -Be $once
        }
    }
}
Describe 'Eine Maskierung am Ende ueber das ganze Ergebnis' {
    BeforeEach { Reset-TestMask }
    AfterAll { Reset-TestMask }
    It 'maskiert auch Schluessel und die Eigenschaften von Objekten' {
        $null = Add-ProbeMaskNames -Users @('mueller') -Domains @('KLINIK') -Clients @('WS-0815')
        $data = [ordered]@{
            'ICA-CGP 3 (KLINIK\mueller)' = 1
            Rows = @([pscustomobject]@{ Instance = 'ICA-CGP 3 (KLINIK\mueller)'; Value = 2.5; When = [datetime]'2026-11-11T07:08:09'; Inner = [pscustomobject]@{ Client = 'WS-0815' } })
            Flag = $true; Count = [uint64]7; Nothing = $null
        }
        (Protect-ProbeValue $data | ConvertTo-Json -Depth 8 -Compress) |
            Should -Be '{"ICA-CGP 3 (<domain>\\<user>)":1,"Rows":[{"Instance":"ICA-CGP 3 (<domain>\\<user>)","Value":2.5,"When":"2026-11-11T07:08:09","Inner":{"Client":"<client>"}}],"Flag":true,"Count":7,"Nothing":null}'
    }
    It 'nimmt auch Wertetypen mit Eigenschaften auseinander und maskiert Eigenschaftsnamen und andere Schluessel' {
        $null = Add-ProbeMaskNames -Users @('anna') -Computers @('VDA01')
        $pair = New-Object 'System.Collections.Generic.KeyValuePair[string,string]' ('anna', 'VDA01')
        $entry = New-Object System.Collections.DictionaryEntry ('anna', 'Sitzung auf VDA01')
        $json = Protect-ProbeValue ([ordered]@{ Pair = $pair; Entry = $entry; Object = [pscustomobject]@{ anna = 'VDA01' }; Table = @{ 4711 = 'anna' } }) | ConvertTo-Json -Depth 8 -Compress
        $json | Should -Not -Match 'anna'
        $json | Should -Not -Match 'VDA01'
        $json | Should -Match ([regex]::Escape('"Pair":{"Key":"<user>","Value":"<server>"}'))
        $json | Should -Match ([regex]::Escape('"Object":{"<user>":"<server>"}'))
        $json | Should -Match ([regex]::Escape('"Table":{"4711":"<user>"}'))
    }
    It 'laesst Zahlen, Wahrheitswerte, Zeiten und Kennungen unveraendert' {
        $id = [guid]'11111111-2222-3333-4444-555555555555'
        $safe = Protect-ProbeValue ([ordered]@{ A = 1.5; B = [decimal]2; C = $false; D = [datetime]'2026-11-11T07:08:09'; E = [timespan]::FromSeconds(5); F = $id; G = [System.DayOfWeek]::Monday; H = [uint64]7 })
        $safe.A | Should -Be 1.5; $safe.B | Should -Be 2; $safe.C | Should -BeFalse
        $safe.D | Should -Be ([datetime]'2026-11-11T07:08:09'); $safe.E | Should -Be ([timespan]::FromSeconds(5)); $safe.F | Should -Be $id
        $safe.G | Should -Be ([System.DayOfWeek]::Monday); $safe.H | Should -Be 7
    }
    It 'nimmt nur echte Servernamen aus den Texten auf' {
        @(Get-ProbeUncHosts @('C:\\Users\\x', '\\localhost\c$', '\\*\x', 'siehe \\fs01.', "Pfad '\\fs02' fehlt", '\\a\x')) | Sort-Object | Should -Be @('fs01', 'fs02')
        $null = Add-ProbeMaskNames -Users @('anna') -Domains @('KLINIK')
        $null = Add-ProbeServerNames @('klinik.local', 'fs01.klinik.local')
        Hide-ProbeText 'KLINIK\anna, Local Security Authority, fs01 in klinik.local' | Should -Be '<domain>\<user>, Local Security Authority, <server> in <server>'
    }
    It 'entfernt die internen Trennzeichen aus fremdem Text' {
        $text = [string][char]0xE000 + 'anna' + [char]0xE001 + ' und ' + [char]0xE000 + 'user' + [char]0xE001
        Hide-WorkerPerfName -Text $text -Users @() | Should -Be 'anna und user'
        Hide-WorkerPerfName -Text $text -Users @('anna') | Should -Be '<user> und user'
    }
    It 'ersetzt auch einen Treffer, den das Verzeichnis der Namen nicht kennt' {
        # das Muster ignoriert Gross- und Kleinschreibung nach Kulturregeln (Kelvin-Zeichen = k), das Verzeichnis nicht
        Hide-WorkerPerfName -Text ('Konto ' + [char]0x212A + 'arl gesperrt') -Users @('karl') | Should -Be 'Konto <user> gesperrt'
    }
    It 'haelt Schluessel auseinander, die nach der Maskierung gleich lauten' {
        $null = Add-ProbeMaskNames -Users @('mueller', 'schmidt')
        $safe = Protect-ProbeValue ([ordered]@{ 'C:\Users\mueller' = 1; 'C:\Users\schmidt' = 2 })
        @($safe.Keys) | Should -Be @('C:\Users\<user>', 'C:\Users\<user> (2)')
        @($safe.Values) | Should -Be @(1, 2)
    }
    It 'nimmt Servernamen aus UNC-Pfaden des Ergebnisses in die Listen auf und maskiert sie dann auch im Fliesstext' {
        $data = [ordered]@{ Location = '\\fs01.klinik.local\upm$\x.vhdx'; Other = '\\?\UNC\nas7\daten'; Device = '\Device\Mup\dfs9\x'; Volume = '\\?\Volume{1}\'; Detail = 'Der Server FS01 antwortet nicht (nas7, dfs9, klinik.local)' }
        @(Get-ProbeTexts $data).Count | Should -Be 10                                              # fuenf Schluessel, fuenf Werte
        @(Get-ProbeUncHosts @(Get-ProbeTexts $data)) | Sort-Object | Should -Be @('dfs9', 'fs01.klinik.local', 'nas7')
        $null = Add-ProbeServerNames @(Get-ProbeUncHosts @(Get-ProbeTexts $data))
        (Protect-ProbeValue $data).Detail | Should -Be 'Der Server <server> antwortet nicht (<server>, <server>, <domain>)'
    }
    It 'nimmt den Server einer SMB-Freigabe mit einfachem Backslash auf, ohne Geraetepfade anzutasten' {
        Add-ProbeShareServer '\fs01\daten'
        Add-ProbeShareServer '_Total'
        Add-ProbeShareServer '\\fs02\upm$'
        Hide-ProbeText '\fs01\daten' | Should -Be '\<server>\daten'
        Hide-ProbeText '\\fs02\upm$' | Should -Be '\\<server>\upm$'
        Hide-ProbeText '_Total und \Device\HarddiskVolume3' | Should -Be '_Total und \Device\HarddiskVolume3'
    }
    It 'maskiert in keiner Pruefung selbst: Texte bleiben bis zum Schreiben unveraendert' {
        # Eine Pruefung, die mit den Namen ihres Zeitpunkts maskiert, zerschneidet einen Namen, der erst spaeter bekannt
        # wird (aus anna.meier wird <user>.meier, wenn anna schon bekannt ist). Maskiert wird deshalb nur am Ende.
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Probe, [ref]$null, [ref]$null)
        $allowed = @('Hide-ProbeText', 'Protect-ProbeValue', 'Hide-WorkerPerfName', 'Test-ProbeUserInText')
        $offenders = @()
        foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
            if ($allowed -contains $f.Name) { continue }
            $calls = @($f.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
                    Where-Object { @('Hide-ProbeText', 'Hide-WorkerPerfName', 'Hide-WorkerPerfMaskedText', 'Protect-ProbeValue') -contains $_.GetCommandName() })
            if ($calls.Count -gt 0) { $offenders += $f.Name }
        }
        $offenders | Should -BeNullOrEmpty
    }
}
Describe 'Namen, die sich waehrend des Laufs aendern' {
    BeforeEach {
        Reset-TestMask
        $script:NewSession = { param($User, $Client, $State = 'Active') [pscustomobject]@{ SessionId = 1; State = $State; User = $User; Domain = 'KLINIK'; ClientName = $Client } }
    }
    AfterAll { Reset-TestMask }
    It 'nimmt neue Namen in die Listen auf und zaehlt nur die neuen' {
        Add-ProbeMaskNames -Users @('mueller') -Clients @('WS-0001') | Should -Be 2
        Hide-ProbeText '\\fs01\upm$\neu.KLINIK\x.vhdx von WS-0002' | Should -Be '\\<server>\upm$\neu.KLINIK\x.vhdx von WS-0002'
        Add-ProbeMaskNames -Users @('neu', 'MUELLER', '', $null) -Domains @('KLINIK') -Clients @('WS-0002') | Should -Be 3
        Hide-ProbeText '\\fs01\upm$\neu.KLINIK\x.vhdx von WS-0002' | Should -Be '\\<server>\upm$\<user>.<domain>\x.vhdx von <client>'
        Add-ProbeMaskNames -Users @('Neu') | Should -Be 0
        Hide-ProbeText 'C:\Users\mueller' | Should -Be 'C:\Users\<user>'                       # frueher aufgenommene Namen bleiben
    }
    It 'maskiert einen Benutzer, der sich waehrend einer Pruefung anmeldet' {
        $live = New-Object 'System.Collections.Generic.List[object]'
        $live.Add((& $NewSession 'mueller' 'WS-0001'))
        $readSessions = { $live.ToArray() }
        (Read-ProbeNames $readSessions { @('C:\Users\mueller') }).Gap | Should -BeNullOrEmpty
        $catalogue = @(
            @{ Id = 'a'; Signals = @(); Title = 'A'; Run = { param($Ctx, $Check) @{ Ok = $true; Detail = 'ok'; Data = [ordered]@{ Path = 'C:\Users\mueller' } } } }
            @{ Id = 'b'; Signals = @(); Title = 'B'; Run = { param($Ctx, $Check)
                    $live.Add((& $NewSession 'neu' 'WS-0002'))                                      # Anmeldung, waehrend diese Pruefung laeuft
                    @{ Ok = $true; Detail = 'Container \\fs01\upm$\neu.KLINIK\x.vhdx'
                        Data = [ordered]@{ Location = '\\fs01\upm$\neu.KLINIK\Win2022\ProfileContainer.vhdx'; Instance = 'ICA-CGP 4 (KLINIK\neu) WS-0002' } } } }
        )
        $results = @(Invoke-ProbeCatalogue $catalogue @{} $readSessions 6>$null)
        $results.Count | Should -Be 2
        $json = ConvertTo-Json -InputObject (Protect-ProbeValue ([ordered]@{ Checks = $results })) -Depth 8 -Compress
        $json | Should -Not -Match 'neu'
        $json | Should -Not -Match 'WS-0002'
        $json | Should -Not -Match 'KLINIK'
        $json | Should -Match ([regex]::Escape('"Location":"\\\\<server>\\upm$\\<user>.<domain>\\Win2022\\ProfileContainer.vhdx"'))
        $json | Should -Match ([regex]::Escape('"Instance":"ICA-CGP 4 (<domain>\\<user>) <client>"'))
    }
    It 'liest Sitzungen und Profilordner vor dem Schreiben noch einmal' {
        $live = New-Object 'System.Collections.Generic.List[object]'
        $live.Add((& $NewSession 'mueller' 'WS-0001'))
        $folders = New-Object 'System.Collections.Generic.List[string]'
        $folders.Add('C:\Users\mueller')
        $readSessions = { $live.ToArray() }
        $readProfiles = { $folders.ToArray() }
        (Read-ProbeNames $readSessions $readProfiles).Gap | Should -BeNullOrEmpty
        $live.Add((& $NewSession 'spaet' 'WS-0003'))
        $folders.Add('C:\Users\gast.KLINIK2')
        $last = Read-ProbeNames $readSessions $readProfiles
        $last.Gap | Should -BeNullOrEmpty
        @($last.Sessions).Count | Should -Be 2
        # der Ordnername gilt als Ganzes als Benutzername, sein Zusatz ausserdem als Domaene
        Hide-ProbeText 'Sitzung von spaet an WS-0003, Ordner C:\Users\gast.KLINIK2\x, Konto KLINIK2\gast' | Should -Be 'Sitzung von <user> an <client>, Ordner C:\Users\<user>\x, Konto <domain>\<user>'
    }
    It 'haelt an, wenn am Ende eine aktive Sitzung keinen Benutzernamen liefert' {
        $live = New-Object 'System.Collections.Generic.List[object]'
        $live.Add((& $NewSession 'mueller' 'WS-0001'))
        $readSessions = { $live.ToArray() }
        (Read-ProbeNames $readSessions { @('C:\Users\mueller') }).Gap | Should -BeNullOrEmpty
        $live.Add((& $NewSession '' 'WS-0004'))
        (Read-ProbeNames $readSessions { @('C:\Users\mueller') }).Gap | Should -Match 'aktive Sitzung'
    }
    It 'uebersteht ein fehlgeschlagenes Lesen der Sitzungen mitten im Lauf' {
        $null = Add-ProbeMaskNames -Users @('mueller')
        { Update-ProbeMaskFromSessions { throw 'WTS antwortet nicht' } } | Should -Not -Throw
        Hide-ProbeText 'C:\Users\mueller' | Should -Be 'C:\Users\<user>'
    }
    It 'meldet eine unlesbare Quelle, statt abzubrechen' {
        $r = Read-ProbeNames { throw 'WTS antwortet nicht' } { @('C:\Users\mueller') }
        $r.WtsError | Should -Be 'WTS antwortet nicht'
        $r.Gap | Should -BeNullOrEmpty                                                          # die Profilordner liefern die Namen
        Hide-ProbeText 'C:\Users\mueller' | Should -Be 'C:\Users\<user>'
        $both = Read-ProbeNames { throw 'WTS antwortet nicht' } { throw 'Zugriff verweigert' }
        $both.ProfileError | Should -Be 'Zugriff verweigert'
        $both.Gap | Should -Match 'nicht ermittelbar'
    }
    It 'maskiert auch mit vielen Namen schnell, weil das Muster nur einmal entsteht' {
        $users = @(1..120 | ForEach-Object { 'benutzer{0:000}' -f $_ })
        $clients = @(1..120 | ForEach-Object { 'WS-{0:0000}' -f $_ })
        $null = Add-ProbeMaskNames -Users $users -Domains @('KLINIK', 'klinik.local') -Clients $clients -Computers @('VDA01')
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        for ($i = 0; $i -lt 500; $i++) { $t = Hide-ProbeText ('ICA-CGP {0} (KLINIK\benutzer{1:000}) von WS-{1:0000}' -f $i, (($i % 120) + 1)) }
        $sw.Stop()
        $t | Should -Be 'ICA-CGP 499 (<domain>\<user>) von <client>'
        $sw.ElapsedMilliseconds | Should -BeLessThan 1500                                       # vorher rund 7 ms je Text
    }
    It 'liest die Namen im Skript nach den Pruefungen und vor dem Schreiben erneut' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Probe, [ref]$null, [ref]$null)
        $calls = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $false))      # nur die oberste Ebene des Skripts
        $at = { param($Name, $Text) @($calls | Where-Object { $_.GetCommandName() -eq $Name -and $_.Extent.Text -like $Text } | ForEach-Object { $_.Extent.StartOffset }) }
        $read = @(& $at 'Read-ProbeNames' '*')
        $run = @(& $at 'Invoke-ProbeCatalogue' '*')
        $protect = @(& $at 'Protect-ProbeValue' '*$report*')
        $write = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Extent.Text -like '*WriteAllText*' }, $false) | ForEach-Object { $_.Extent.StartOffset })
        $read.Count | Should -Be 2
        $run.Count | Should -Be 1
        $protect.Count | Should -Be 1
        $write.Count | Should -Be 1
        $read[0] | Should -BeLessThan $run[0]
        $run[0] | Should -BeLessThan $read[1]
        $read[1] | Should -BeLessThan $protect[0]
        $protect[0] | Should -BeLessThan $write[0]
    }
}
Describe 'Ereignisse und Drucken im Pruefskript' {
    It 'nennt die Namen der Datenfelder, nie ihre Werte' {
        $x = "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><System><Provider Name='Application Error'/><EventID>1000</EventID></System>" +
             "<EventData><Data Name='AppName'>geheim.exe</Data><Data Name='ModuleName'>geheim.dll</Data></EventData></Event>"
        Get-ProbeEventFieldNames $x | Should -Be @('AppName', 'ModuleName')
        Get-ProbeEventFieldNames ($x -replace " Name='\w+'", '') | Should -Be @('#0', '#1')
        $u = "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><UserData><EventXML xmlns='x'><User>KLINIK\mueller</User><SessionID>3</SessionID></EventXML></UserData></Event>"
        Get-ProbeEventFieldNames $u | Should -Be @('User', 'SessionID')
    }
    It 'zaehlt je Quelle und Kennung ohne Meldungstext' {
        $ev = foreach ($k in 1..3) { $o = [pscustomobject]@{ ProviderName = 'Application Error'; Id = 1000; Message = 'geheimer Text' }
            $o | Add-Member ScriptMethod ToXml { "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><EventData><Data Name='AppName'>geheim.exe</Data></EventData></Event>" }; $o }
        $s = @(Get-ProbeEventSummary @($ev))
        $s.Count | Should -Be 1; $s[0].Provider | Should -Be 'Application Error'; $s[0].Id | Should -Be 1000; $s[0].Count | Should -Be 3; $s[0].Fields | Should -Be @('AppName')
        ($s | ConvertTo-Json -Depth 5) | Should -Not -Match 'geheim'
    }
    It 'fasst Druckertreiber nach Hersteller, Bauart und Isolierung zusammen, ohne Treibernamen' {
        $d = @([pscustomobject]@{ Name = 'Treiber A'; Manufacturer = 'HP'; MajorVersion = 3 }, [pscustomobject]@{ Name = 'Treiber B'; Manufacturer = 'HP'; MajorVersion = 4 },
               [pscustomobject]@{ Name = 'Treiber C'; Manufacturer = 'Kyocera'; MajorVersion = 3 })
        $r = Get-ProbeDriverSummary $d 'Treiber A\\Treiber B\\Treiber C'
        $r.Count | Should -Be 3; $r.ByManufacturer['HP'] | Should -Be 2; $r.ByType['3'] | Should -Be 2; $r.ByType['4'] | Should -Be 1
        $r.ByIsolation['none'] | Should -Be 1; $r.ByIsolation['shared'] | Should -Be 1; $r.ByIsolation['isolated'] | Should -Be 1
        ($r | ConvertTo-Json -Depth 5) | Should -Not -Match 'Treiber'
    }
    It 'nennt weitere Feldarten und uebersteht kaputtes XML' {
        $x = "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><EventData><Data>a</Data><Data Name='Code'>1</Data><Binary>00FF</Binary></EventData></Event>"
        Get-ProbeEventFieldNames $x | Should -Be @('#0', 'Code', 'binary')
        @(Get-ProbeEventFieldNames '<Event><kaputt') | Should -Be @()
        @(Get-ProbeEventFieldNames "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><System/></Event>") | Should -Be @()
    }
    It 'sortiert nach Quelle und Kennung und nimmt die Felder des ersten Ereignisses' {
        $mk = { param($P, $Id, $Xml) $o = [pscustomobject]@{ ProviderName = $P; Id = $Id }; $o | Add-Member NoteProperty X $Xml; $o | Add-Member ScriptMethod ToXml { $this.X }; $o }
        $ns = "xmlns='http://schemas.microsoft.com/win/2004/08/events/event'"
        $ev = @((& $mk 'disk' 153 "<Event $ns><EventData><Data Name='Neu'>1</Data></EventData></Event>"), (& $mk 'Ntfs' 55 "<Event $ns/>"),
                (& $mk 'disk' 7 "<Event $ns/>"), (& $mk 'disk' 153 "<Event $ns><EventData><Data Name='Alt'>1</Data></EventData></Event>"))
        $s = @(Get-ProbeEventSummary $ev)
        @($s | ForEach-Object { '{0}/{1}={2}' -f $_.Provider, $_.Id, $_.Count }) | Should -Be @('disk/7=1', 'disk/153=2', 'Ntfs/55=1')
        $s[1].Fields | Should -Be @('Neu')
        @(Get-ProbeEventSummary @()).Count | Should -Be 0
    }
    It 'baut die Abfrage aus Quellen, Stufen, Kennungen und Zeitraum' {
        Get-ProbeEventQuery @('Application Error', '.NET Runtime') @(1, 2) @() 7 |
            Should -Be "*[System[(Provider[@Name='Application Error' or @Name='.NET Runtime']) and (Level=1 or Level=2) and TimeCreated[timediff(@SystemTime) <= 604800000]]]"
        Get-ProbeEventQuery @() @() @(21, 23) 7 | Should -Be '*[System[(EventID=21 or EventID=23) and TimeCreated[timediff(@SystemTime) <= 604800000]]]'
        Get-ProbeEventQuery @() @() @() 1 | Should -Be '*[System[TimeCreated[timediff(@SystemTime) <= 86400000]]]'
    }
    It 'nimmt aus einem Muster nur Quellen unter einem Citrix-Programmordner, die in das Protokoll schreiben' {
        $info = { param($Name, $Files, $Logs) [ordered]@{ Name = $Name; Files = [string[]]$Files; Logs = [string[]]$Logs } }
        $listed = @(
            (& $info 'Citrix Print Manager Service' @('C:\Program Files\Citrix\System32\CpSvcMsg.dll') @('Application', 'System'))
            (& $info 'Citrix Anmeldeskript Klinikum' @('C:\Windows\Microsoft.NET\Framework64\v4.0.30319\EventLogMessages.dll') @('Application'))
            (& $info 'Citrix Wartung Klinikum' @('C:\Windows\System32\netmsg.dll') @('Application'))                  # beliebige Windows-Datei
            (& $info 'Citrix ohne Datei Klinikum' @() @('Application'))
            (& $info 'Citrix Profile Management' @('C:\Windows\System32\kernel32.dll', 'C:\PROGRAM FILES (X86)\CITRIX\User Profile Manager\upm.dll') @('application'))
            (& $info 'Citrix Ordner Klinikum' @('C:\Daten\CitrixTools\msg.dll') @('Application'))                    # kein Ordner namens Citrix
            (& $info 'Citrix ETW Trace' @('C:\Program Files\Citrix\Trace\trace.dll') @('Citrix-Trace/Debug'))        # schreibt nicht in das Protokoll
            $null                                                                                                     # Metadaten nicht lesbar
            (& $info "Citrix 'A' `"B`"" @('C:\Program Files\Citrix\x.dll') @('Application'))                         # nicht in die Abfrage schreibbar
            (& $info 'Citrix Skripte Klinikum' @('D:\Citrix\Skripte\msg.dll') @('Application'))                      # Citrix-Ordner, aber nicht unter den Programmen
            (& $info 'Citrix Umweg Klinikum' @('C:\Program Files\Citrix\..\Tools\msg.dll') @('Application'))        # verlaesst den Citrix-Ordner
        )
        $roots = @('C:\Program Files\Citrix\', 'C:\Program Files (x86)\Citrix\')
        $asked = New-Object 'System.Collections.Generic.List[string]'
        $r = Resolve-ProbeEventProviders @('Application Error', 'Citrix Profile Management', 'Citrix*', 'Citrix*') 'Application' { param($p) $asked.Add($p); $listed } $roots
        @($r.Names) | Should -Be @('Application Error', 'Citrix Profile Management', 'Citrix Print Manager Service')
        $r.Dropped | Should -Be 8
        $r.NotLinked | Should -Be 1
        $nothing = Resolve-ProbeEventProviders @('Citrix*') 'Application' { param($p) $listed } @()             # ohne Programmordner bleibt keine Quelle
        @($nothing.Names).Count | Should -Be 0
        @($asked) | Should -Be @('Citrix*')
        $q = Resolve-ProbeEventProviders @("Exakt 'A' `"B`"", 'Application Error') 'Application' { throw 'nicht fragen' } $roots
        @($q.Names) | Should -Be @('Application Error'); $q.Dropped | Should -Be 1
        $none = Resolve-ProbeEventProviders @() 'Application' { throw 'nicht fragen' } $roots
        @($none.Names).Count | Should -Be 0; $none.Dropped | Should -Be 0
    }
    It 'leitet die Citrix-Ordner aus den Programmordnern ab' {
        $saved = @{}
        foreach ($n in 'ProgramFiles', 'ProgramFiles(x86)', 'ProgramW6432') { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }
        try {
            [Environment]::SetEnvironmentVariable('ProgramFiles', 'C:\Program Files\')
            [Environment]::SetEnvironmentVariable('ProgramFiles(x86)', 'C:\Program Files (x86)')
            [Environment]::SetEnvironmentVariable('ProgramW6432', 'C:\Program Files')
            @(Get-ProbeCitrixRoots) | Should -Be @('C:\Program Files\Citrix\', 'C:\Program Files (x86)\Citrix\')
            foreach ($n in 'ProgramFiles', 'ProgramFiles(x86)', 'ProgramW6432') { [Environment]::SetEnvironmentVariable($n, $null) }
            @(Get-ProbeCitrixRoots).Count | Should -Be 0
        }
        finally { foreach ($n in $saved.Keys) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) } }
    }
    It 'liest Name, eigene Dateien und Protokolle einer Quelle und meldet unlesbare Metadaten als leer' {
        $env:WP_TEST_CITRIX = 'C:\Program Files\Citrix'
        try {
            $m = [pscustomobject]@{ Name = 'Citrix X'; MessageFilePath = '%WP_TEST_CITRIX%\a.dll; C:\b.dll'; ResourceFilePath = ''; ParameterFilePath = 'C:\Program Files\Citrix\p.dll'
                LogLinks = @([pscustomobject]@{ LogName = 'Application' }, [pscustomobject]@{ LogName = 'System' }) }
            $i = ConvertTo-ProbeProviderInfo $m
            $i.Name | Should -Be 'Citrix X'
            @($i.Files) | Should -Be @('C:\Program Files\Citrix\a.dll', 'C:\b.dll')                                # Parameterdatei zaehlt nicht
            @($i.Logs) | Should -Be @('Application', 'System')
            # PowerShell meldet einen Fehler beim Lesen einer Eigenschaft als leeren Wert: die Quelle hat dann weder Dateien
            # noch Protokolle und wird nie abgefragt
            $bad = [pscustomobject]@{ Name = 'Citrix Y' }
            $bad | Add-Member ScriptProperty LogLinks { throw 'Metadaten nicht verfuegbar' }
            $bad | Add-Member ScriptProperty MessageFilePath { throw 'Metadaten nicht verfuegbar' }
            $b = ConvertTo-ProbeProviderInfo $bad
            @($b.Logs).Count | Should -Be 0; @($b.Files).Count | Should -Be 0
            $r = Resolve-ProbeEventProviders @('Citrix*') 'Application' { param($p) @($b) } @('C:\Program Files\Citrix\')
            @($r.Names).Count | Should -Be 0; $r.NotLinked | Should -Be 1
        }
        finally { Remove-Item Env:\WP_TEST_CITRIX }
    }
    It 'zaehlt einen unlesbaren Datensatz und behaelt die Ereignisse davor und danach' {
        $mk = { param($Id, [switch]$Fail) [pscustomobject]@{ Id = $Id; Fail = [bool]$Fail } }
        $reader = New-TestEventReader @((& $mk 1), (& $mk 1), (& $mk 2), (& $mk 0 -Fail), (& $mk 1), (& $mk 3), (& $mk 3))
        $seen = New-Object 'System.Collections.Generic.List[int]'
        $labels = New-Object 'System.Collections.Generic.List[string]'
        $r = Read-ProbeEventRecords $reader 1000 { param($Label, $Count) $labels.Add($Label); $seen.Add($Count) } 'Application' 10
        @($r.Events).Count | Should -Be 6
        $r.RecordErrors | Should -Be 1
        $r.Capped | Should -BeFalse
        @(Get-ProbeEventSummary $r.Events | ForEach-Object { '{0}={1}' -f $_.Id, $_.Count }) | Should -Be @('1=3', '2=1', '3=2')
        $reader.XmlCalls | Should -Be 3                                                                          # nur das erste Ereignis je Kennung
        $reader.Disposed | Should -Be 6                                                                          # jeder gelesene Datensatz wird freigegeben
        $seen[$seen.Count - 1] | Should -Be 16                                                                   # gezaehlt ab dem Stand davor
        @($labels | Sort-Object -Unique) | Should -Be @('Application')
    }
    It 'haelt bei der Obergrenze an und bricht nach zu vielen unlesbaren Datensaetzen in Folge ab' {
        $mk = { param($Id, [switch]$Fail) [pscustomobject]@{ Id = $Id; Fail = [bool]$Fail } }
        $capped = Read-ProbeEventRecords (New-TestEventReader @(1..5 | ForEach-Object { & $mk $_ })) 2 { param($Label, $Count) }
        @($capped.Events).Count | Should -Be 2; $capped.Capped | Should -BeTrue
        $broken = Read-ProbeEventRecords (New-TestEventReader @(1..50 | ForEach-Object { & $mk 0 -Fail })) 1000 { param($Label, $Count) }
        @($broken.Events).Count | Should -Be 0; $broken.RecordErrors | Should -Be 10; $broken.Capped | Should -BeFalse
    }
    It 'nennt den aeltesten gelesenen Datensatz als Zeitstempel' {
        $t = { param($Id, $Time) [pscustomobject]@{ Id = $Id; Fail = $false; Time = [datetime]::SpecifyKind([datetime]$Time, 'Utc') } }
        $r = Read-ProbeEventRecords (New-TestEventReader @((& $t 1 '2026-11-10T08:00:00'), (& $t 2 '2026-11-05T07:30:00'), (& $t 1 '2026-11-09T00:00:00'))) 1000 { param($Label, $Count) }
        $r.OldestUtc | Should -Be '2026-11-05T07:30:00Z'
        (Read-ProbeEventRecords (New-TestEventReader @()) 1000 { param($Label, $Count) }).OldestUtc | Should -Be ''
    }
    It 'meldet, wie viele Gruppen von Quellen wegen der Obergrenze ungelesen blieben' {
        function Get-WinEvent { param([string]$ListLog, $ErrorAction) [pscustomobject]@{ LogName = $ListLog; IsEnabled = $true } }
        $script:OpenedQueries = New-Object 'System.Collections.Generic.List[string]'
        function Open-ProbeEventReader([string]$Log, [string]$Query) {
            $OpenedQueries.Add($Query)
            $items = @(1..1200 | ForEach-Object { [pscustomobject]@{ Id = 7; Fail = $false; Time = [datetime]::SpecifyKind([datetime]'2026-11-10T12:00:00', 'Utc').AddMinutes(-$_) } })
            New-TestEventReader $items 'Quelle1'
        }
        $providers = @(1..40 | ForEach-Object { 'Quelle{0}' -f $_ })                    # mit drei Stufen: Gruppen zu 16, also drei Abfragen
        $r = Get-ProbeEventLog 'System' $providers @(1, 2, 3) @() 6>$null
        $r.Readable | Should -BeTrue; $r.Capped | Should -BeTrue
        $r.Chunks | Should -Be 3; $r.ChunksNotRead | Should -Be 2
        @($OpenedQueries).Count | Should -Be 1
        $r.OldestUtc | Should -Be '2026-11-09T19:20:00Z'                                 # der 1000. von 1200: 1000 Minuten vor 12:00
        $r.Ids[0].Count | Should -Be 1000
    }
    It 'bemisst die Gruppen nach den 20 Ausdruecken einer Abfrage' {
        Get-ProbeChunkSize 3 0 | Should -Be 16
        Get-ProbeChunkSize 0 4 | Should -Be 15
        Get-ProbeChunkSize 0 0 | Should -Be 19
        Get-ProbeChunkSize 25 0 | Should -Be 1
        $providers = @(1..40 | ForEach-Object { 'Quelle{0}' -f $_ })
        foreach ($chunk in @(Split-ProbeProviderChunks $providers (Get-ProbeChunkSize 3 0))) {
            $query = Get-ProbeEventQuery $chunk @(1, 2, 3) @() 7
            ([regex]::Matches($query, "@Name=|Level=|EventID=|timediff\(")).Count | Should -BeLessOrEqual 20
        }
    }
    It 'zaehlt Druckertreiber nach den Bits ihrer Attribute und liest die Richtlinien als Zahlen' {
        $a = Get-ProbeDriverAttributeCounts @(5, 1, $null, 0x804, 0, [int]-2147483644)
        $a.Read | Should -Be 5; $a.NotRead | Should -Be 1
        $a.SandboxEnabled | Should -Be 3                                                                           # 0x4 PRINTER_DRIVER_SANDBOX_ENABLED
        $a.ByBit['0x00000004'] | Should -Be 3; $a.ByBit['0x00000001'] | Should -Be 2; $a.ByBit['0x00000800'] | Should -Be 1; $a.ByBit['0x80000000'] | Should -Be 1
        @($a.ByBit.Keys) | Should -Be @('0x00000001', '0x00000004', '0x00000800', '0x80000000')
        $p = Get-ProbeIsolationPolicy @{ PrintDriverIsolationExecutionPolicy = 1; PrintDriverIsolationOverrideCompat = 'x' }
        $p.PrintDriverIsolationExecutionPolicy | Should -Be 1; $p.PrintDriverIsolationOverrideCompat | Should -Be 'kein Zahlenwert'
        $n = Get-ProbeIsolationPolicy @{}
        $n.PrintDriverIsolationExecutionPolicy | Should -Be 'nicht gesetzt'; $n.PrintDriverIsolationOverrideCompat | Should -Be 'nicht gesetzt'
    }
    It 'zaehlt die wirksame Isolierung je Treiber nach der Entscheidung von Microsoft' {
        $d = @('A', 'B', 'C', 'D', 'E', 'F') | ForEach-Object { [pscustomobject]@{ Name = "Treiber $_" } }
        $groups = 'Treiber E\\Treiber A\\Treiber F'                                        # E im Druckdienst, A gemeinsam, F allein
        $attr = @(0, 4, 0, $null, 4, 0)
        $set = Get-ProbeIsolationPolicy @{}
        $e = Get-ProbeEffectiveIsolation $d $groups $attr $set
        "$($e.none)/$($e.shared)/$($e.isolated)/$($e.unbekannt)" | Should -Be '2/2/1/1'          # A Gruppe, B Attribut, C ohne Attribut, D nicht gelesen
        $override = Get-ProbeEffectiveIsolation $d $groups $attr (Get-ProbeIsolationPolicy @{ PrintDriverIsolationOverrideCompat = 1 })
        "$($override.none)/$($override.shared)/$($override.isolated)/$($override.unbekannt)" | Should -Be '1/4/1/0'
        $off = Get-ProbeEffectiveIsolation $d $groups $attr (Get-ProbeIsolationPolicy @{ PrintDriverIsolationExecutionPolicy = 0 })
        "$($off.none)/$($off.shared)/$($off.isolated)/$($off.unbekannt)" | Should -Be '6/0/0/0'
        ((Get-ProbeEffectiveIsolation $d $groups $attr $set) | ConvertTo-Json) | Should -Not -Match 'Treiber'
    }
    It 'zaehlt Instanzen ohne _Total' {
        Get-ProbeInstanceCount @('_Total', 'Drucker A', 'Drucker B') | Should -Be 2
        Get-ProbeInstanceCount @() | Should -Be 0
    }
    It 'fragt viele Quellen in Gruppen ab, damit die Abfrage gueltig bleibt' {
        $c = @(Split-ProbeProviderChunks @(1..32 | ForEach-Object { 'P{0}' -f $_ }) 15)
        $c.Count | Should -Be 3
        @($c | ForEach-Object { @($_).Count }) | Should -Be @(15, 15, 2)
        $c[2] | Should -Be @('P31', 'P32')
        $one = @(Split-ProbeProviderChunks @() 15)
        $one.Count | Should -Be 1; @($one[0]).Count | Should -Be 0
        @(Split-ProbeProviderChunks @('A') 15).Count | Should -Be 1
    }
    It 'nennt Namen von Registrierungswerten ohne solche, die einen Treibernamen enthalten' {
        Select-ProbeDriverValueNames @('Driver', 'Data File', 'driver', 'Treiber A Einstellungen', '', 'Version') @('Treiber A', 'Treiber B') |
            Should -Be @('Data File', 'Driver', 'Version')
    }
    It 'ordnet Treiber ausserhalb der Gruppen als unbekannt ein und liest auch mehrere Zeichenketten' {
        $d = @([pscustomobject]@{ Name = 'Treiber A'; Manufacturer = ''; MajorVersion = 4 }, [pscustomobject]@{ Name = 'Treiber Z'; Manufacturer = 'HP'; MajorVersion = 2 })
        $r = Get-ProbeDriverSummary $d @('', 'treiber a\Treiber Q')
        $r.ByIsolation['shared'] | Should -Be 1; $r.ByIsolation['unbekannt'] | Should -Be 1; $r.ByIsolation['none'] | Should -Be 0
        $r.ByType['unbekannt'] | Should -Be 1; $r.ByManufacturer['unbekannt'] | Should -Be 1
        $r.IsolationSource | Should -Be 'PrintDriverIsolationGroups'
        @($r.PropertyNames) | Should -Be @('Name', 'Manufacturer', 'MajorVersion')
        $empty = Get-ProbeDriverSummary @() $null
        $empty.Count | Should -Be 0; $empty.IsolationSource | Should -Be 'keine'; @($empty.PropertyNames).Count | Should -Be 0
    }
}
Describe 'Ablauf des Pruefskripts mit nachgestellten Quellen' -Skip:$IsWindows {
    # Der Hauptteil des Skripts laeuft nur unter Windows. Hier wird er mit nachgestellten Quellen ausgefuehrt: die
    # Sitzungen liefert eine Klasse gleichen Namens, die Profile eine Funktion Get-CimInstance, die Pruefungen ein
    # eigener Katalog. Aus dem Skripttext werden dafuer nur die Windows-Sperre, der Katalog und die zwei
    # duennen Zugriffe auf den Ereignisleser und die Registrierung ersetzt.
    BeforeAll {
        if (-not ('WorkerPerfProbe.Wts' -as [type])) {
            Add-Type -Language CSharp -TypeDefinition @'
using System.Collections.Generic;
namespace WorkerPerfProbe
{
    public class WtsSession { public int SessionId; public string State; public string User; public string Domain; public string ClientName; }
    public static class Wts
    {
        public static List<WtsSession> Sessions = new List<WtsSession>();
        public static List<WtsSession> GetSessions() { return new List<WtsSession>(Sessions); }
    }
}
'@
        }
        $script:AddSession = { param($Id, $User, $Client, $State = 'Active')
            $x = New-Object WorkerPerfProbe.WtsSession
            $x.SessionId = $Id; $x.State = $State; $x.User = $User; $x.Domain = 'KLINIK'; $x.ClientName = $Client
            [WorkerPerfProbe.Wts]::Sessions.Add($x)
        }
        function Get-CimInstance {
            [CmdletBinding()] param([string]$ClassName, [string]$Namespace, [string]$Filter, [int]$OperationTimeoutSec)
            if ($ClassName -eq 'Win32_UserProfile') {
                [pscustomobject]@{ Special = $false; LocalPath = 'C:\Users\mueller' }
                [pscustomobject]@{ Special = $false; LocalPath = 'C:\Users\anna.schmidt' }               # macht "anna" zu einem bekannten Namen
                [pscustomobject]@{ Special = $true; LocalPath = 'C:\Windows\ServiceProfiles\LocalService' }
            }
            elseif ($ClassName -eq 'Win32_Service') {
                & $AddSession 6 'anna.meier' 'WS-0006'                                             # Anmeldung, waehrend die Dienste gelesen werden
                [pscustomobject]@{ Name = 'ICA-CGP 6 (KLINIK\anna.meier)'; ProcessId = 4711 }
                [pscustomobject]@{ Name = 'Spooler'; ProcessId = 0 }
            }
            elseif ($ClassName -eq 'Win32_Process') {
                [pscustomobject]@{ Name = 'svchost.exe'; ProcessId = 4711; SessionId = 0; ExecutablePath = 'C:\Windows\System32\svchost.exe' }
                [pscustomobject]@{ Name = 'svchost.exe'; ProcessId = 4712; SessionId = 0; ExecutablePath = '' }
                [pscustomobject]@{ Name = 'WINWORD.EXE'; ProcessId = 5001; SessionId = 2; ExecutablePath = 'C:\Program Files\Microsoft Office\WINWORD.EXE' }
                [pscustomobject]@{ Name = 'WINWORD.EXE'; ProcessId = 5002; SessionId = 3; ExecutablePath = 'C:\Program Files\Microsoft Office\WINWORD.EXE' }
            }
            elseif ($ClassName -eq 'Win32_OperatingSystem') { [pscustomobject]@{ Caption = 'Microsoft Windows Server 2022 Standard'; Version = '10.0.20348' } }
            elseif ($ClassName -eq 'MSFT_PrinterDriver' -and $Namespace -eq 'root/StandardCimv2') {
                [pscustomobject]@{ Name = 'Zeta Station 3 Klinikum'; Manufacturer = 'HP'; MajorVersion = 3; PrinterEnvironment = 'Windows x64' }
                [pscustomobject]@{ Name = 'Zeta Etiketten Klinikum'; Manufacturer = 'Zebra'; MajorVersion = 4; PrinterEnvironment = 'Windows x64' }
                [pscustomobject]@{ Name = 'Zeta ohne Schluessel Klinikum'; Manufacturer = 'HP'; MajorVersion = 3; PrinterEnvironment = 'Windows x64' }
                [pscustomobject]@{ Name = 'Zeta iR-ADV C5535/5540 Klinikum'; Manufacturer = 'Canon'; MajorVersion = 3; PrinterEnvironment = 'Windows x64' }
            }
        }
        # Ereignisprotokolle: je Protokoll ein Eintrag mit Exists, Readable und den Ereignissen. Die Ereignisse tragen Texte und
        # Feldwerte, die nicht im Ergebnis stehen duerfen; ein Eintrag mit Fail ist ein Datensatz, der sich nicht lesen laesst.
        # Den Leser (EventLogReader) und die Registrierung ersetzt das Skript an seinen zwei duennen Stellen (unten).
        $script:EventQueries = New-Object 'System.Collections.Generic.List[string]'
        $script:ListProviderCalls = New-Object 'System.Collections.Generic.List[string]'
        $script:NewEvent = { param($Provider, $Id, $Xml, [switch]$Fail)
            $o = [pscustomobject]@{ ProviderName = $Provider; Id = $Id; Message = 'Fehler bei mueller auf \\fs01\upm$ geheim'; X = $Xml; Fail = [bool]$Fail
                TimeCreated = [datetime]'2026-11-10T09:00:00' }
            $o | Add-Member ScriptMethod ToXml { $this.X }
            $o | Add-Member ScriptMethod Dispose { }
            $o
        }
        $ns = "xmlns='http://schemas.microsoft.com/win/2004/08/events/event'"
        $appError = "<Event $ns><EventData><Data Name='AppName'>geheim.exe</Data><Data Name='ModuleName'>geheim.dll</Data></EventData></Event>"
        $script:EventLogs = @{
            'Application' = @{ Exists = $true; Readable = $true; Events = @(
                    1..3 | ForEach-Object { & $NewEvent 'Application Error' 1000 $appError }
                    & $NewEvent 'Application Error' 1000 '' -Fail
                    4..1005 | ForEach-Object { & $NewEvent 'Application Error' 1000 $appError }
                    & $NewEvent 'Citrix Anmeldeskript Klinikum' 1 "<Event $ns><EventData><Data>Klinikum</Data></EventData></Event>") }
            'System' = @{ Exists = $true; Readable = $true; Events = @(
                    & $NewEvent 'Citrix Print Manager Service' 1116 "<Event $ns><EventData><Data>Station 3</Data><Binary>00</Binary></EventData></Event>"
                    & $NewEvent 'Service Control Manager' 7031 "<Event $ns><EventData><Data Name='param1'>Spooler</Data></EventData></Event>") }
            'Microsoft-Windows-PrintService/Admin' = @{ Exists = $true; Readable = $true; Events = @() }
            'Microsoft-Windows-PrintService/Operational' = @{ Exists = $true; Readable = $true; Enabled = $false; Events = @() }
            'Microsoft-Windows-SMBClient/Connectivity' = @{ Exists = $true; Readable = $false; Events = @() }
            'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational' = @{ Exists = $true; Readable = $true; Events = @(
                    & $NewEvent 'Microsoft-Windows-TerminalServices-LocalSessionManager' 21 "<Event $ns><UserData><EventXML xmlns='x'><User>KLINIK\mueller</User><SessionID>2</SessionID><Address>WS-0001</Address></EventXML></UserData></Event>") }
        }
        function Get-WinEvent {
            [CmdletBinding()] param([string]$ListLog, [string]$ListProvider)
            if ($ListProvider) {
                $ListProviderCalls.Add($ListProvider)
                $link = { param($Name) [pscustomobject]@{ LogName = $Name } }
                [pscustomobject]@{ Name = 'Citrix Print Manager Service'; MessageFilePath = 'C:\Program Files\Citrix\System32\CpSvcMsg.dll'; ResourceFilePath = $null; LogLinks = @((& $link 'System')) }
                [pscustomobject]@{ Name = 'Citrix Anmeldeskript Klinikum'; MessageFilePath = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\EventLogMessages.dll'; ResourceFilePath = $null; LogLinks = @((& $link 'Application')) }
                [pscustomobject]@{ Name = 'Citrix Druck Klinikum'; MessageFilePath = 'C:\Windows\System32\netmsg.dll'; ResourceFilePath = $null; LogLinks = @((& $link 'Application')) }
                [pscustomobject]@{ Name = 'Citrix ETW Trace'; MessageFilePath = $null; ResourceFilePath = 'C:\Program Files\Citrix\Trace\trace.dll'; LogLinks = @((& $link 'Citrix-Trace/Debug')) }
                return
            }
            if (-not $EventLogs.ContainsKey($ListLog) -or -not $EventLogs[$ListLog].Exists) { throw "There is not an event log on the localhost computer that matches `"$ListLog`"." }
            $enabled = $true
            if ($EventLogs[$ListLog].ContainsKey('Enabled')) { $enabled = $EventLogs[$ListLog].Enabled }
            [pscustomobject]@{ LogName = $ListLog; IsEnabled = $enabled }
        }
        $script:StandInEventReader = { param($Log, $Query)
            $EventQueries.Add($Query)
            $entry = $EventLogs[$Log]
            if (-not $entry.Readable) { throw 'Zugriff verweigert' }
            $hits = @($entry.Events | Where-Object { $Query -notmatch 'Provider\[' -or $Query.Contains("@Name='" + $_.ProviderName + "'") })
            $reader = [pscustomobject]@{ Items = $hits; Next = 0 }
            $reader | Add-Member ScriptMethod ReadEvent {
                if ($this.Next -ge @($this.Items).Count) { return $null }
                $item = $this.Items[$this.Next]; $this.Next++
                if ($item.Fail) { throw 'Die Daten sind ungueltig' }
                $item
            }
            $reader | Add-Member ScriptMethod Dispose { }
            $reader
        }
        # Registrierung unter HKLM: der Schluessel des Druckdienstes, die Richtlinien und die Schluessel der Treiber
        $script:RegistryKeys = @{
            'SYSTEM\CurrentControlSet\Control\Print' = @{ PrintDriverIsolationGroups = 'Zeta Etiketten Klinikum\\Zeta Station 3 Klinikum' }
            'SOFTWARE\Policies\Microsoft\Windows NT\Printers' = @{ PrintDriverIsolationExecutionPolicy = 1 }
            'SYSTEM\CurrentControlSet\Control\Print\Environments\Windows x64\Drivers\Version-3\Zeta Station 3 Klinikum' = [ordered]@{
                'Configuration File' = 'x'; 'Data File' = 'x'; Driver = 'x'; 'Zeta Station 3 Klinikum Station' = 'x'; PrinterDriverAttributes = 5 }
            'SYSTEM\CurrentControlSet\Control\Print\Environments\Windows x64\Drivers\Version-4\Zeta Etiketten Klinikum' = [ordered]@{ Driver = 'x'; PrinterDriverAttributes = 1 }
            'SYSTEM\CurrentControlSet\Control\Print\Environments\Windows x64\Drivers\Version-3\Zeta iR-ADV C5535/5540 Klinikum' = [ordered]@{ Driver = 'x'; PrinterDriverAttributes = 4 }
        }
        $script:StandInRegistryKey = { param($SubKey)
            if (-not $RegistryKeys.ContainsKey($SubKey)) { return $null }
            $key = [pscustomobject]@{ Values = $RegistryKeys[$SubKey] }
            $key | Add-Member ScriptMethod GetValueNames { [string[]]@($this.Values.Keys) }
            $key | Add-Member ScriptMethod GetValue { param($Name) if ($this.Values.Contains($Name)) { $this.Values[$Name] } }
            $key | Add-Member ScriptMethod Close { }
            $key
        }
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Probe, [ref]$null, [ref]$null)
        $guard = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Extent.Text -like '*laeuft nur unter Windows*' }, $false)
        $catalogue = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$script:Catalogue' }, $false)
        $thin = { param($Name) $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name }.GetNewClosure(), $true) }
        $reader = & $thin 'Open-ProbeEventReader'
        $registry = & $thin 'Open-ProbeRegistryKey'
        $text = $ast.Extent.Text
        $edits = @(@{ Node = $guard; Text = '' }, @{ Node = $catalogue; Text = '$script:Catalogue = $TestCatalogue' }
            @{ Node = $reader; Text = 'function Open-ProbeEventReader([string]$Log, [string]$Query) { & $StandInEventReader $Log $Query }' }
            @{ Node = $registry; Text = 'function Open-ProbeRegistryKey([string]$SubKey) { & $StandInRegistryKey $SubKey }' })
        foreach ($edit in $edits | Sort-Object -Property { $_.Node.Extent.StartOffset } -Descending) {
            $text = $text.Substring(0, $edit.Node.Extent.StartOffset) + $edit.Text + $text.Substring($edit.Node.Extent.EndOffset)
        }
        $script:ProbeMain = [scriptblock]::Create($text)
        $script:RealCatalogue = @(& ([scriptblock]::Create($catalogue.Right.Extent.Text)))
        $script:TestCatalogue = @(
            @{ Id = 'a'; Signals = @('cpu.host'); Title = 'A'; Run = { param($Ctx, $Check) @{ Ok = $true; Detail = '{0} Sitzungen' -f @($Ctx.Sessions).Count; Data = [ordered]@{ Path = 'C:\Users\mueller\AppData' } } } }
            @{ Id = 'b'; Signals = @(); Title = 'B'; Run = { param($Ctx, $Check)
                    & $AddSession 3 'neu' 'WS-0002'                                              # Anmeldung, waehrend diese Pruefung laeuft
                    @{ Ok = $true; Detail = 'Container \\fs01\upm$\neu.KLINIK\x.vhdx'
                        Data = [ordered]@{ Location = '\\fs01\profile$\S-1-5-21-1-2-3-1108_neu\Profile_neu.VHDX'; Instances = @('ICA-CGP 3 (KLINIK\neu)', 'ICA-CGP 2 (KLINIK\mueller)'); Client = 'WS-0002' } } } }
            @{ Id = 'c'; Signals = @(); Title = 'C'; Run = { param($Ctx, $Check) throw 'Zugriff verweigert: \\fs01\upm$\neu.KLINIK' } }
            @{ Id = 'd'; Signals = @(); Title = 'D'; Run = { param($Ctx, $Check) @{ Ok = $null; Detail = 'uebersprungen'; Data = $null } } }
        )
    }
    BeforeEach {
        Reset-TestMask
        [WorkerPerfProbe.Wts]::Sessions.Clear()
        & $AddSession 0 '' '' 'Disconnected'                                                     # Sitzung 0 der Dienste
        & $AddSession 2 'mueller' 'WS-0001'
        $script:OutDir = Join-Path ([IO.Path]::GetTempPath()) ('wp-probe-' + [guid]::NewGuid().ToString('N'))
    }
    AfterEach {
        Reset-TestMask
        if (Test-Path -LiteralPath $OutDir) { Remove-Item -LiteralPath $OutDir -Recurse -Force }
    }
    It 'schreibt eine Datei ohne Namen, auch fuer einen Benutzer, der sich waehrend des Laufs anmeldet' {
        & $ProbeMain -OutFile $OutDir 3>$null 6>$null | Out-Null
        $files = @(Get-ChildItem -LiteralPath $OutDir -Filter 'vda-probe_*.json')
        $files.Count | Should -Be 1
        $json = [IO.File]::ReadAllText($files[0].FullName)
        foreach ($name in 'mueller', 'neu', 'KLINIK', 'WS-0001', 'WS-0002', 'fs01', 'S-1-5-21') { $json | Should -Not -Match $name }
        $r = $json | ConvertFrom-Json
        $r.SchemaVersion | Should -Be 3
        @($r.Checks).Count | Should -Be 4
        @($r.Checks | ForEach-Object { $_.Id }) | Should -Be @('a', 'b', 'c', 'd')
        $r.Checks[0].Ok | Should -BeTrue
        $r.Checks[0].Detail | Should -Be '2 Sitzungen'
        $r.Checks[0].Data.Path | Should -Be 'C:\Users\<user>\AppData'
        $r.Checks[1].Data.Location | Should -Be '\\<server>\profile$\<sid>_<user>\Profile_<user>.VHDX'
        @($r.Checks[1].Data.Instances) | Should -Be @('ICA-CGP 3 (<domain>\<user>)', 'ICA-CGP 2 (<domain>\<user>)')
        $r.Checks[1].Data.Client | Should -Be '<client>'
        $r.Checks[2].Ok | Should -BeFalse
        $r.Checks[2].Detail | Should -Be 'Zugriff verweigert: \\<server>\upm$\<user>.<domain>'
        $r.Checks[3].Ok | Should -Be $null
    }
    It 'liest Ereignisprotokolle und Druckertreiber und schreibt nur Anzahlen, Kennungen und Namen von Feldern' {
        $script:TestCatalogueSaved = $TestCatalogue
        $onlyPattern = @{ Id = 'events.pattern'; Signals = @(); Title = 'Nur ein Muster'; Run = 'Invoke-ProbeEventsCheck'; Logs = @('Application'); Providers = @('Citrix*'); Levels = @(); EventIds = @() }
        $script:TestCatalogue = @(@($RealCatalogue | Where-Object { $_.Id -like 'events.*' -or $_.Id -eq 'print.drivers' }) + $onlyPattern)
        $EventQueries.Clear(); $ListProviderCalls.Clear()
        $console = $null
        $savedProgramFiles = $env:ProgramFiles
        $env:ProgramFiles = 'C:\Program Files'
        try { $console = @(& $ProbeMain -OutFile $OutDir 3>$null 6>&1 | ForEach-Object { [string]$_ }) }
        finally { $script:TestCatalogue = $TestCatalogueSaved; $env:ProgramFiles = $savedProgramFiles }
        $json = [IO.File]::ReadAllText(@(Get-ChildItem -LiteralPath $OutDir -Filter 'vda-probe_*.json')[0].FullName)
        foreach ($name in 'geheim', 'mueller', 'KLINIK', 'Klinikum', 'Zeta', 'Station', 'fs01', 'WS-0001', 'Spooler', 'C5535') { $json | Should -Not -Match $name }
        $r = $json | ConvertFrom-Json
        $byId = @{}; foreach ($c in $r.Checks) { $byId[$c.Id] = $c }
        @($r.Checks).Count | Should -Be 10
        # jedes Muster wird einmal aufgeloest, auch wenn drei Pruefungen es nennen
        @($ListProviderCalls) | Should -Be @('Citrix*')
        # Anwendung: ein unlesbarer Datensatz wird gezaehlt, die Ereignisse davor und danach bleiben; gekappt je Protokoll
        $app = $byId['events.application']
        $app.Ok | Should -BeTrue
        $app.Data.Days | Should -Be 7
        $log = @($app.Data.Logs)[0]
        $log.Log | Should -Be 'Application'; $log.Exists | Should -BeTrue; $log.Readable | Should -BeTrue; $log.Capped | Should -BeTrue
        $log.RecordErrors | Should -Be 1
        $log.Chunks | Should -Be 1; $log.ChunksNotRead | Should -Be 0
        $json | Should -Match '"OldestUtc":\s*"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ"'                       # ConvertFrom-Json machte daraus eine Zeit
        @($log.Ids).Count | Should -Be 1
        $log.Ids[0].Provider | Should -Be 'Application Error'; $log.Ids[0].Id | Should -Be 1000; $log.Ids[0].Count | Should -Be $app.Data.MaxEvents
        @($log.Ids[0].Fields) | Should -Be @('AppName', 'ModuleName')
        # nur Quellen unter einem Citrix-Ordner, die in dieses Protokoll schreiben; alle anderen nur gezaehlt und nie abgefragt
        @($log.Providers) | Should -Not -Contain 'Citrix Print Manager Service'
        $log.ProvidersDropped | Should -Be 2; $log.ProvidersNotLinked | Should -Be 2
        @($EventQueries | Where-Object { $_ -match 'Anmeldeskript|Citrix Druck|ETW' }).Count | Should -Be 0
        # System: Stufen und eine Quelle aus dem Muster
        $sys = @($byId['events.system'].Data.Logs)[0]
        @($sys.Providers) | Should -Contain 'Citrix Print Manager Service'
        @($sys.Ids | ForEach-Object { '{0}/{1}' -f $_.Provider, $_.Id }) | Should -Be @('Citrix Print Manager Service/1116', 'Service Control Manager/7031')
        @($sys.Ids[0].Fields) | Should -Be @('#0', 'binary')
        @($EventQueries | Where-Object { $_ -match 'Level=1 or Level=2 or Level=3' }).Count | Should -BeGreaterThan 0
        # ein Muster ohne passende Quelle fragt nichts ab, statt alle Quellen zu lesen
        $only = @($byId['events.pattern'].Data.Logs)[0]
        $byId['events.pattern'].Ok | Should -BeTrue
        $only.Queried | Should -BeFalse; @($only.Ids).Count | Should -Be 0
        @($EventQueries | Where-Object { $_ -notmatch 'Provider\[' -and $_ -notmatch 'EventID=' -and $_ -notmatch 'Level=' }).Count | Should -Be 2   # nur die zwei Druckdienst-Protokolle
        # Druckdienst: ohne Ereignisse lesbar, das abgeschaltete Protokoll wird gemeldet, nicht eingeschaltet
        $print = @($byId['events.printservice'].Data.Logs)
        $print[0].Readable | Should -BeTrue; @($print[0].Ids).Count | Should -Be 0; $print[1].Enabled | Should -BeFalse
        # SMB-Client: ein Protokoll nicht lesbar, das andere nicht vorhanden
        $smb = $byId['events.smbclient']
        $smb.Ok | Should -BeFalse
        @($smb.Data.Logs)[0].Exists | Should -BeTrue; @($smb.Data.Logs)[0].Readable | Should -BeFalse; @($smb.Data.Logs)[0].Error | Should -Be 'Zugriff verweigert'
        @($smb.Data.Logs)[1].Exists | Should -BeFalse
        $smb.Detail | Should -Match 'nicht lesbar'; $smb.Detail | Should -Match 'nicht vorhanden'
        $byId['events.defender'].Ok | Should -BeFalse
        # Sitzungen: Felder aus UserData, ihre Werte nicht
        $ses = @($byId['events.session'].Data.Logs)[0]
        @($ses.Ids[0].Fields) | Should -Be @('User', 'SessionID', 'Address')
        # Konsole: eine Zeile je Protokoll mit Name und Zahl, ohne Quellennamen
        @($console | Where-Object { $_ -match '^\s*(\r)?\s*Application: 1000 Ereignisse' }).Count | Should -BeGreaterThan 0
        ($console -join "`n") | Should -Not -Match 'Klinikum|Application Error|Print Manager|Service Control'      # Titel nennen nur Produkte
        # Druckertreiber
        $drv = $byId['print.drivers']
        $drv.Ok | Should -BeTrue
        $drv.Data.Count | Should -Be 4
        $drv.Data.ByManufacturer.HP | Should -Be 2; $drv.Data.ByType.'3' | Should -Be 3; $drv.Data.ByType.'4' | Should -Be 1
        $drv.Data.ByIsolation.none | Should -Be 1; $drv.Data.ByIsolation.shared | Should -Be 1; $drv.Data.ByIsolation.unbekannt | Should -Be 2
        @($drv.Data.RegistryValueNames) | Should -Be @('Configuration File', 'Data File', 'Driver', 'PrinterDriverAttributes')
        $drv.Data.RegistryKeysRead | Should -Be 3; $drv.Data.RegistryKeysMissing | Should -Be 1                    # auch der Name mit "/"
        $drv.Data.DriverAttributes.Read | Should -Be 3; $drv.Data.DriverAttributes.NotRead | Should -Be 1; $drv.Data.DriverAttributes.SandboxEnabled | Should -Be 2
        $drv.Data.IsolationPolicy.PrintDriverIsolationExecutionPolicy | Should -Be 1
        $drv.Data.IsolationPolicy.PrintDriverIsolationOverrideCompat | Should -Be 'nicht gesetzt'
        # Etiketten in Gruppe 1 (none), Station 3 in Gruppe 2 (shared), C5535 mit Attribut 0x4 (shared), ohne Schluessel unbekannt
        $eff = $drv.Data.ByEffectiveIsolation
        "$($eff.none)/$($eff.shared)/$($eff.isolated)/$($eff.unbekannt)" | Should -Be '1/2/0/1'
    }
    It 'fuehrt die Pruefungen der Prozesse und der Gegenstellen aus und liefert Daten' {
        # eine erreichbare Gegenstelle (eigener Listener) und eine, deren Port geschlossen ist
        $open = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback, 0); $open.Start()
        $closed = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback, 0); $closed.Start()
        $closedPort = $closed.LocalEndpoint.Port; $closed.Stop()
        $endpointFile = Join-Path ([IO.Path]::GetTempPath()) ('wp-endpoints-' + [guid]::NewGuid().ToString('N') + '.json')
        $json = '{{ "endpoints": [ {{ "name": "Datenbank", "host": "127.0.0.1", "port": {0}, "role": "db" }}, {{ "name": "Lizenz", "host": "127.0.0.1", "port": {1}, "role": "lic" }} ] }}' -f $open.LocalEndpoint.Port, $closedPort
        [IO.File]::WriteAllText($endpointFile, $json)
        $script:TestCatalogueSaved = $TestCatalogue
        $script:TestCatalogue = @($RealCatalogue | Where-Object { @('security.products', 'user.processes', 'endpoints') -contains $_.Id })
        try { & $ProbeMain -OutFile $OutDir -EndpointFile $endpointFile 3>$null 6>$null | Out-Null }
        finally { $script:TestCatalogue = $TestCatalogueSaved; $open.Stop(); Remove-Item -LiteralPath $endpointFile -Force }
        $text = [IO.File]::ReadAllText(@(Get-ChildItem -LiteralPath $OutDir -Filter 'vda-probe_*.json')[0].FullName)
        foreach ($name in 'anna', 'meier', 'KLINIK', '127.0.0.1') { $text | Should -Not -Match ([regex]::Escape($name)) }
        $r = $text | ConvertFrom-Json
        @($r.Checks | ForEach-Object { $_.Id }) | Should -Be @('security.products', 'user.processes', 'endpoints')
        $sec = $r.Checks[0]
        $sec.Ok | Should -BeTrue
        $svchost = @($sec.Data.Processes | Where-Object { $_.Name -eq 'svchost.exe' })[0]
        $svchost.Instances | Should -Be 2
        @($svchost.Services) | Should -Be @('ICA-CGP 6 (<domain>\<user>)')
        $usr = $r.Checks[1]
        $usr.Ok | Should -BeTrue
        @($usr.Data.Processes | ForEach-Object { '{0}={1}' -f $_.Name, $_.Instances }) | Should -Be @('WINWORD.EXE=2')
        $ep = $r.Checks[2]
        $ep.Ok | Should -BeFalse
        $ep.Detail | Should -Be '1 von 2 Gegenstellen erreichbar'
        @($ep.Data.Endpoints | ForEach-Object { $_.Index }) | Should -Be @(1, 2)
        $ep.Data.Endpoints[0].ConnectMs | Should -Not -BeNullOrEmpty
        $ep.Data.Endpoints[1].Error | Should -Be 'refused'
    }
    It 'zerschneidet keinen Namen, von dem beim Lesen erst ein Teil bekannt ist' {
        # die echte Pruefung der Dienste, mit nachgestellter CIM-Abfrage: sie liefert einen Text mit dem Namen einer
        # Benutzerin, die sich in diesem Augenblick anmeldet; "anna" ist schon aus einem Profilordner bekannt
        $script:TestCatalogueSaved = $TestCatalogue
        $script:TestCatalogue = @($TestCatalogue[0], @{ Id = 'services.map'; Signals = @(); Title = 'Dienste'; Run = 'Invoke-ProbeServicesCheck' })
        try { & $ProbeMain -OutFile $OutDir 3>$null 6>$null | Out-Null }
        finally { $script:TestCatalogue = $TestCatalogueSaved }
        $json = [IO.File]::ReadAllText(@(Get-ChildItem -LiteralPath $OutDir -Filter 'vda-probe_*.json')[0].FullName)
        foreach ($name in 'meier', 'anna', 'schmidt', 'KLINIK') { $json | Should -Not -Match $name }
        $r = $json | ConvertFrom-Json
        @($r.Checks[1].Data.Services)[0].Name | Should -Be 'ICA-CGP 6 (<domain>\<user>)'
        @($r.Checks[1].Data.Services)[0].ProcessId | Should -Be 4711
    }
    It 'schreibt keine Datei, wenn beim Start eine aktive Sitzung keinen Benutzernamen liefert' {
        & $AddSession 4 '' 'WS-0004'
        { & $ProbeMain -OutFile $OutDir 3>$null 6>$null | Out-Null } | Should -Throw '*1 aktive Sitzung(en) ohne Benutzernamen*Es wird keine Datei geschrieben*'
        @(Get-ChildItem -LiteralPath $OutDir -Filter '*.json' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }
    It 'schreibt keine Datei, wenn am Ende eine aktive Sitzung keinen Benutzernamen liefert' {
        $script:TestCatalogueSaved = $TestCatalogue
        $script:TestCatalogue = @($TestCatalogue[0], @{ Id = 'z'; Signals = @(); Title = 'Z'; Run = { param($Ctx, $Check) & $AddSession 5 '' 'WS-0005'; @{ Ok = $true; Detail = 'ok'; Data = $null } } })
        try {
            { & $ProbeMain -OutFile $OutDir 3>$null 6>$null | Out-Null } | Should -Throw '*aktive Sitzung(en) ohne Benutzernamen*bitte das Skript erneut starten*'
            @(Get-ChildItem -LiteralPath $OutDir -Filter '*.json' -ErrorAction SilentlyContinue).Count | Should -Be 0
        }
        finally { $script:TestCatalogue = $TestCatalogueSaved }
    }
}
