BeforeAll {
    $script:Probe = Join-Path $PSScriptRoot '../src/Test-WorkerPerfSources.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Probe, [ref]$null, [ref]$null)
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Hide-WorkerPerfName' }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
    # Further pure helpers that run on Linux.
    foreach ($name in 'New-WorkerPerfNameMask', 'Hide-WorkerPerfMaskedText', 'Get-ProbeMaskNames', 'Get-ProbeMaskDomains', 'Hide-ProbeText',
        'Get-ProbeEndpointErrorClass', 'Get-ProbeMaskGap', 'Protect-ProbeValue', 'Get-ProbeFileName', 'Join-ProbeNames', 'Add-ProbeMaskNames', 'Get-ProbeErrorText',
        'Read-ProbeNames', 'Update-ProbeMaskFromSessions', 'Invoke-ProbeCatalogue', 'Add-ProbeServerNames', 'Add-ProbeShareServer', 'Get-ProbeUncHosts', 'Get-ProbeTexts', 'Copy-ProbeValue') {
        $f = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
        if ($null -ne $f) { . ([scriptblock]::Create($f.Extent.Text)) }
    }
    $script:Checks = @(& $Probe -ListChecks)
    # The lists of names to mask and the pattern built from them live in script variables of the probe.
    function Reset-TestMask {
        $script:ProbeUsers = @(); $script:ProbeDomains = @(); $script:ProbeClients = @(); $script:ProbeComputers = @()
        $script:ProbeMask = $null; $script:ProbeMaskNoUsers = $null
    }
    Reset-TestMask
}
Describe 'Quellen-Pruefskript' {
    It 'listet die Pruefungen ohne Systemzugriff' {
        $Checks.Id | Should -Be @('system', 'process.snapshot', 'sessions.wts', 'services.map', 'perf.cpu', 'perf.queue', 'perf.steal', 'perf.memory',
            'perf.disk.total', 'perf.network', 'perf.volumes', 'perf.shares', 'perf.input.session', 'perf.input.process', 'perf.ica',
            'profile.volumes', 'events.defender', 'events.applocker', 'security.products', 'user.processes', 'endpoints')
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
Describe 'Ablauf des Pruefskripts mit nachgestellten Quellen' -Skip:$IsWindows {
    # Der Hauptteil des Skripts laeuft nur unter Windows. Hier wird er mit nachgestellten Quellen ausgefuehrt: die
    # Sitzungen liefert eine Klasse gleichen Namens, die Profile eine Funktion Get-CimInstance, die Pruefungen ein
    # eigener Katalog. Aus dem Skripttext werden dafuer nur die Windows-Sperre und der Katalog ersetzt.
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
            elseif ($ClassName -eq 'Win32_OperatingSystem') { [pscustomobject]@{ Caption = 'Microsoft Windows Server 2022 Standard'; Version = '10.0.20348' } }
        }
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Probe, [ref]$null, [ref]$null)
        $guard = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Extent.Text -like '*laeuft nur unter Windows*' }, $false)
        $catalogue = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$script:Catalogue' }, $false)
        $text = $ast.Extent.Text
        foreach ($edit in @(@{ Node = $guard; Text = '' }, @{ Node = $catalogue; Text = '$script:Catalogue = $TestCatalogue' }) | Sort-Object -Property { $_.Node.Extent.StartOffset } -Descending) {
            $text = $text.Substring(0, $edit.Node.Extent.StartOffset) + $edit.Text + $text.Substring($edit.Node.Extent.EndOffset)
        }
        $script:ProbeMain = [scriptblock]::Create($text)
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
        $r.SchemaVersion | Should -Be 2
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
