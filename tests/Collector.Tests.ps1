BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1')
    $script:Run = Invoke-SimCapture (Join-Path $TestDrive 'out')
    $script:Meta = Get-Content (Join-Path $Run 'meta.json') -Raw | ConvertFrom-Json
    $script:Snaps = @(Import-Csv (Join-Path $Run 'snapshots.csv'))
    $script:Exp = @(Get-Content (Join-Path $Run 'expected.json') -Raw | ConvertFrom-Json)
}
Describe 'Start-WorkerPerfCapture -Simulate' {
    It 'schreibt jede Datei des Formats mit ihrer Kopfzeile' {
        foreach ($name in $WorkerPerfHeaders.Keys) { Get-Content (Join-Path $Run $name) -TotalCount 1 | Should -Be $WorkerPerfHeaders[$name] }
        Test-Path (Join-Path $Run 'thresholds.json') | Should -BeTrue
    }
    It 'fuehrt meta.json' {
        $Meta.SchemaVersion | Should -Be 2; $Meta.EndReason | Should -Be 'duration'; $Meta.Ticks | Should -Be 1800
        $Meta.Snapshots | Should -Be $Snaps.Count; $Meta.SkippedTicks | Should -Be 0; $Meta.CollectorPid | Should -Be 4242
        $Meta.Sources.'input.session'.Available | Should -BeTrue; @($Meta.Endpoints).Count | Should -Be 3
    }
    It 'schreibt Zahlen mit Dezimalpunkt trotz deutscher Kultur' {              # Review Focus 2
        $lines = Get-Content (Join-Path $Run 'ticks.csv') | Select-Object -Skip 1 -First 50
        foreach ($line in $lines) { $line.Split(',').Count | Should -Be 19 }
        $lines[0] | Should -Match '^0,[^,]+,2,\d+(\.\d+)?,'
    }
    It 'nimmt 240 regulaere Schnappschuesse, davon 12 Stuetzpunkte' {
        @($Snaps | Where-Object Kind -in 'R', 'K').Count | Should -Be 240
        @($Snaps | Where-Object Kind -eq 'K').Count | Should -Be 12; $Snaps[0].Kind | Should -Be 'K'
    }
    It 'verdichtet nur waehrend der Vorfaelle und 60 Sekunden danach' {
        $burst = @($Snaps | Where-Object Kind -eq 'B'); $burst.Count | Should -BeGreaterThan 50
        $windows = @($Exp | Where-Object { -not $_.Chronic })
        foreach ($b in $burst) {
            $ms = [DateTimeOffset]::Parse($b.Timestamp, [cultureinfo]::InvariantCulture).ToUnixTimeMilliseconds()
            @($windows | Where-Object { $ms -ge $_.StartMs -and $ms -le $_.EndMs + 62000 }).Count | Should -BeGreaterThan 0
        }
    }
    It 'laesst ruhende Prozesse aus' {
        $regular = @($Snaps | Where-Object Kind -eq 'R')
        ($regular | Measure-Object RowsWritten -Average).Average | Should -BeLessThan (0.6 * [double]$regular[0].Processes)
    }
    It 'meldet das Ende des robocopy-Prozesses' { @(Get-Content (Join-Path $Run 'procend.csv')).Count | Should -BeGreaterThan 1 }
    It 'legt Proben, Ereignisse und Citrix-Werte ab' {
        @(Import-Csv (Join-Path $Run 'probes.csv')).Count | Should -Be (240 * 3)
        @(Import-Csv (Join-Path $Run 'events.csv')).Kind | Should -Be @('scan-start', 'scan-end', 'applocker-block')
        @(Get-Content (Join-Path $Run 'citrix.csv')).Count | Should -BeGreaterThan 1000
    }
    It 'bleibt unter 10 MB' { (Get-ChildItem $Run | Measure-Object Length -Sum).Sum | Should -BeLessThan 10MB }
    It 'legt das Soll-Ergebnis ab' { $Exp.Count | Should -Be 8; $Exp[1].Key | Should -Be 'cpu' }
    It 'verlangt fuer die Simulation mindestens 60 Minuten' {
        { & (Join-Path $PSScriptRoot '../src/Start-WorkerPerfCapture.ps1') -Simulate -DurationMinutes 10 -OutputPath (Join-Path $TestDrive 'kurz') 6>$null } | Should -Throw '*60*'
    }
}
