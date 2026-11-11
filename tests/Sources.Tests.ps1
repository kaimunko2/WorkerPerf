BeforeAll {
    $script:Probe = Join-Path $PSScriptRoot '../src/Test-WorkerPerfSources.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Probe, [ref]$null, [ref]$null)
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Hide-WorkerPerfName' }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
    # Further pure helpers that run on Linux.
    foreach ($name in 'Get-ProbeMaskNames', 'Get-ProbeMaskDomains', 'Hide-ProbeText', 'Hide-ProbeEndpointText', 'Get-ProbeEndpointErrorClass', 'Get-ProbeMaskGap', 'Protect-ProbeValue', 'Get-ProbeFileName') {
        $f = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
        . ([scriptblock]::Create($f.Extent.Text))
    }
    $script:Checks = @(& $Probe -ListChecks)
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
        $hosts = @('ora-db.example.local', '10.1.2.3')
        Hide-ProbeEndpointText -Text 'Oracle auf ORA-DB' -HostNames $hosts | Should -Be 'Oracle auf <server>'
        Hide-ProbeEndpointText -Text 'Proxy 10.1.2.3' -HostNames $hosts | Should -Be 'Proxy <server>'
        Hide-ProbeEndpointText -Text 'Datenbank' -HostNames $hosts | Should -Be 'Datenbank'
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
        $data = [ordered]@{ Id = 'x'; Ok = $true; N = 3; Detail = 'Fehler auf VDA01'; Data = [ordered]@{ List = @('KLINIK\mueller', 7, $null, [ordered]@{ Path = '\\fs01\upm$\mueller' }); Client = 'WS-0815' } }
        $safe = Protect-ProbeValue $data
        ($safe | ConvertTo-Json -Depth 8 -Compress) | Should -Be '{"Id":"x","Ok":true,"N":3,"Detail":"Fehler auf <server>","Data":{"List":["<domain>\\<user>",7,null,{"Path":"\\\\<server>\\upm$\\<user>"}],"Client":"<client>"}}'
        $script:ProbeUsers = @(); $script:ProbeDomains = @(); $script:ProbeClients = @(); $script:ProbeComputers = @()
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
    It 'schreibt keine Datei, wenn eine aktive Sitzung ohne Benutzernamen bleibt und die Profile fehlen' {
        $s = { param($State, $User) [pscustomobject]@{ SessionId = 1; State = $State; User = $User } }
        $noName = @((& $s 'Disconnected' ''), (& $s 'Active' 'mueller'), (& $s 'Active' ''))
        Get-ProbeMaskGap -Sessions $noName -WtsOk $true -ProfilesOk $false | Should -Match 'aktive Sitzung'
        Get-ProbeMaskGap -Sessions $noName -WtsOk $true -ProfilesOk $true | Should -BeNullOrEmpty               # die Profilordner liefern die Namen
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
