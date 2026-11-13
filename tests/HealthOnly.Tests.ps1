BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1')
    $script:Capture = Join-Path $PSScriptRoot '../src/Start-WorkerPerfCapture.ps1'
    $script:Console = Join-Path $TestDrive 'ho.console.txt'
    $script:Run = Invoke-SimHealthOnly (Join-Path $TestDrive 'ho') @{} $Console
    function Get-Meta([string]$Dir) { Get-Content (Join-Path $Dir 'meta.json') -Raw | ConvertFrom-Json }
}
Describe 'Schnelllauf -HealthOnly' {
    It 'schreibt Zustandsbild, Rueckblick, Treiberliste, die Kopie der Anwendungsliste und meta.json, sonst nichts' {
        @(Get-ChildItem $Run | ForEach-Object Name | Sort-Object) | Should -Be @('apps.json', 'events_before.csv', 'health.json', 'meta.json', 'printdrivers.csv')
        $m = Get-Meta $Run; $m.HealthOnly | Should -BeTrue; $m.EndReason | Should -Be 'healthonly'; $m.Ticks | Should -Be 0; $m.Snapshots | Should -Be 0; $m.SchemaVersion | Should -Be 3
        @($m.Skip).Count | Should -Be 0; $m.EventLookbackDays | Should -Be 7; $m.Simulated | Should -BeTrue; @($m.SourceErrors.PSObject.Properties).Count | Should -Be 0
        @(Import-Csv (Join-Path $Run 'events_before.csv')).Count | Should -Be 6; @(Import-Csv (Join-Path $Run 'printdrivers.csv')).Count | Should -Be 3
        (Get-Content (Join-Path $Run 'health.json') -Raw | ConvertFrom-Json).FormatVersion | Should -Be 1
        $out = Get-Content $Console -Raw
        $out | Should -Match 'WorkerPerf-Schnelllauf laeuft: [^\r\n]+\r?\nGelesen wird: Zustandsbild, Rueckblick, Treiberliste\r?\nNicht gelesen \(-Skip\): keine\r?\n'
        $out | Should -Match 'Zustandsbild: 10 Bereiche gelesen'; $out | Should -Match 'Schnelllauf beendet: '; $out | Should -Not -Match 'Takt'
    }
    It 'ruft die Quelle fuer nichts auf, was zur Messung gehoert' {
        $throwing = (@('Get-WorkerPerfFastSample', 'Get-WorkerPerfSnapshot', 'Get-WorkerPerfServices', 'Get-WorkerPerfEvents', 'Get-WorkerPerfPrintQueues', 'Start-WorkerPerfProbes',
                'Receive-WorkerPerfProbes', 'Wait-WorkerPerfTick') | ForEach-Object { "function $_ { throw 'Testaufruf $_' }" }) -join "`n"
        $run = (& (New-PatchedSource (Join-Path $TestDrive 'srcho') $throwing) -Simulate -HealthOnly -OutputPath (Join-Path $TestDrive 'ho2') 6>$null 3>$null) | Select-Object -Last 1
        (Get-Meta $run).EndReason | Should -Be 'healthonly'; @((Get-Meta $run).SourceErrors.PSObject.Properties).Count | Should -Be 0
    }
    It 'beachtet -Skip Rueckblick und -Skip Drucken' {
        $con = Join-Path $TestDrive 'ho3.console.txt'
        $run = Invoke-SimHealthOnly (Join-Path $TestDrive 'ho3') @{ Skip = @('Drucken', 'Rueckblick') } $con
        @(Get-ChildItem $run | ForEach-Object Name | Sort-Object) | Should -Be @('apps.json', 'health.json', 'meta.json'); @((Get-Meta $run).Skip) | Should -Be @('Rueckblick', 'Drucken')
        (Get-Content $con -Raw) | Should -Match 'Gelesen wird: Zustandsbild\r?\nNicht gelesen \(-Skip\): Rueckblick, Drucken\r?\n'
    }
    It 'lehnt -Skip Zustand und die Parameter der Messung ab, bevor etwas angelegt wird' {
        $dir = Join-Path $TestDrive 'no'
        { & $Capture -Simulate -HealthOnly -Skip Zustand -OutputPath $dir 6>$null } | Should -Throw '-HealthOnly und -Skip Zustand schliessen sich aus*'
        { & $Capture -Simulate -HealthOnly -DurationMinutes 60 -IntervalSeconds 30 -OutputPath $dir 6>$null } | Should -Throw '*nicht zusammen mit: -IntervalSeconds, -DurationMinutes.'
        { & $Capture -Simulate -HealthOnly -NoCitrix -OutputPath $dir 6>$null } | Should -Throw '*nicht zusammen mit: -NoCitrix.'
        Test-Path $dir | Should -BeFalse
    }
    It 'nimmt eine andere Anwendungsliste an und liest deren vierte Anwendung ohne Aenderung am Code' {
        $run = Invoke-SimHealthOnly (Join-Path $TestDrive 'ho5') @{ AppsFile = (New-TestAppFile $TestDrive) }
        $rows = @((Get-Content (Join-Path $run 'health.json') -Raw | ConvertFrom-Json).Areas.apps.Values.'apps.probes'.Value)
        @($rows | Where-Object App -eq 'simapp').Count | Should -Be 4; ($rows | Where-Object { $_.App -eq 'simapp' -and $_.Id -eq 'installed' }).Value | Should -BeFalse     # Review Focus 3
        @($rows | Where-Object { $_.App -eq 'simapp' -and $_.Id -ne 'installed' -and $_.Reason -ne 'notInstalled' }).Count | Should -Be 0
        (Get-Content (Join-Path $run 'apps.json') -Raw) | Should -Match '"simapp"'
    }
    It 'schreibt im Schnelllauf kein expected.json und keine Kopie der Schwellen' {
        foreach ($f in 'expected.json', 'thresholds.json', 'ticks.csv', 'stop.flag') { Test-Path (Join-Path $Run $f) | Should -BeFalse -Because $f }
    }
    It 'liest und kopiert eine relativ angegebene Anwendungsliste aus dem Ordner der PowerShell' {     # Review Task 8, Punkt 1
        $here = Join-Path $TestDrive 'rel'; [void](New-Item -ItemType Directory -Path $here -Force)
        $apps = New-TestAppFile $here
        $oldCwd = [Environment]::CurrentDirectory
        Push-Location $here
        try {
            # der Prozess steht anderswo als die PowerShell: ein relativer Pfad gilt fuer den Ordner der PowerShell
            [Environment]::CurrentDirectory = $PSScriptRoot
            $run = Invoke-SimHealthOnly 'out' @{ AppsFile = 'apps.test.json' }
        }
        finally { Pop-Location; [Environment]::CurrentDirectory = $oldCwd }
        $run | Should -BeLike (Join-Path $here 'out*')
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $run 'apps.json'))) | Should -Be ([Convert]::ToBase64String([IO.File]::ReadAllBytes($apps)))
        $rows = @((Get-Content (Join-Path $run 'health.json') -Raw | ConvertFrom-Json).Areas.apps.Values.'apps.probes'.Value)
        @($rows | Where-Object App -eq 'simapp').Count | Should -Be 4
    }
}
