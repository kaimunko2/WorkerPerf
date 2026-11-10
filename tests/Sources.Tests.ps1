BeforeAll {
    $script:Probe = Join-Path $PSScriptRoot '../src/Test-WorkerPerfSources.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Probe, [ref]$null, [ref]$null)
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Hide-WorkerPerfName' }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
    # Further pure helpers that run on Linux.
    foreach ($name in 'Get-ProbeMaskNames', 'Hide-ProbeEndpointText') {
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
            Should -Be '\\<server>\upm$\<user>.KLINIK\Win2022\ProfileContainer.vhdx'
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
        Hide-WorkerPerfName -Text '\\fs01\upm$\schmidt.KLINIK\x.vhdx' -Users $names | Should -Be '\\<server>\upm$\<user>.KLINIK\x.vhdx'
    }
    It 'schreibt keine Hostnamen der Gegenstellen' {
        $hosts = @('ora-db.example.local', '10.1.2.3')
        Hide-ProbeEndpointText -Text 'Oracle auf ORA-DB' -HostNames $hosts | Should -Be 'Oracle auf <server>'
        Hide-ProbeEndpointText -Text 'Proxy 10.1.2.3' -HostNames $hosts | Should -Be 'Proxy <server>'
        Hide-ProbeEndpointText -Text 'Datenbank' -HostNames $hosts | Should -Be 'Datenbank'
    }
    It 'verweigert die Messung ausserhalb von Windows' -Skip:$IsWindows { { & $Probe } | Should -Throw '*Windows*' }
}
