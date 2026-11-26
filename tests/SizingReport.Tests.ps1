BeforeAll {
    Set-StrictMode -Version 2
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    . (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Sizing.ps1')
    $script:Th = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json')
    $script:Sz = Read-WorkerPerfSizing (Join-Path $PSScriptRoot '../src/sizing.de.json') $Th
    $script:SizingScript = Join-Path $PSScriptRoot '../src/New-WorkerPerfSizingReport.ps1'
    $script:R = New-SizingReports (Join-Path $TestDrive 'sz')
    $script:D = Get-ReportData $R.Report
    $script:CanaryRuns = $null
    function New-CanarySizing([string]$Mask, [switch]$MapFile) {
        # Kopien der fuenf Tage unter <TestDrive>/SIM-CANARY01_runs, Computer in meta.json SIM-CANARY01; liefert den Bericht
        # der Stufe, mit -MapFile die Zuordnungsdatei
        if ($null -eq $script:CanaryRuns) {
            $dir = Join-Path $TestDrive 'SIM-CANARY01_runs'
            $script:CanaryRuns = [string[]]@($R.Runs.Days | ForEach-Object {
                    $copy = Copy-SimRun $_ $dir; $mf = Join-Path $copy 'meta.json'
                    [IO.File]::WriteAllText($mf, [IO.File]::ReadAllText($mf).Replace('SIM-VDA01', 'SIM-CANARY01')); $copy })
        }
        $out = Join-Path $TestDrive ("canary-{0}{1}.html" -f $Mask, $(if ($MapFile) { '-map' } else { '' })); $map = Join-Path $TestDrive 'canary-map.json'
        $extra = @{}; if ($MapFile) { $extra['MaskMapFile'] = $map }
        [void](& $SizingScript -Path $CanaryRuns -OutFile $out -RoleFile $R.Roles -Mask $Mask @extra 6>$null)
        if ($MapFile) { $map } else { $out }
    }
}
Describe 'Groessenbericht aus fuenf Tagen und einem Schnelllauf' {
    It 'zaehlt den Schnelllauf nicht fuer die Last und nennt den Server' {
        $D.meta.server | Should -Be 'SIM-VDA01'; $D.meta.recordings | Should -Be 5; $D.meta.quick | Should -Be 1; $D.meta.axis | Should -Be 'time'
        @($D.runs).Count | Should -Be 6; @($D.runs | Where-Object healthOnly).Count | Should -Be 1
        $D.meta.cores | Should -Be 8; $D.meta.ramGB | Should -Be 64; $D.meta.sizeChanged | Should -BeFalse; $D.meta.target | Should -Be 75
    }
    It 'findet die wiederkehrende Kapazitaet und den einmaligen VMware-Host' {
        ($D.recurring | Where-Object id -eq 'capacity').count | Should -Be 4; ($D.recurring | Where-Object id -eq 'capacity').of | Should -Be 5
        @($D.recurring | Where-Object id -eq 'host').Count | Should -Be 0
        $D.result.text | Should -Match '^Wiederkehrender CPU-Engpass aus Kapazität in 4 von 5 Aufzeichnungen; typische Spitzenlast \d+(,\d)? % bei 31 Sitzungen\.$'
        @($D.bottlenecks | Where-Object { $_.classIds -contains 'host' }).Count | Should -BeGreaterOrEqual 1
        @($D.runs | Where-Object { -not $_.healthOnly } | ForEach-Object { @($_.classIds).Count }) | Should -Be @(1, 1, 2, 1, 0)
    }
    It 'rechnet die Spanne mit der Formel des Entwurfs aus L und T' {
        $cpu = $D.recommendations | Where-Object resource -eq 'cpu'; $r = Get-WorkerPerfCpuRange 8 $D.meta.load 75 $Sz
        $cpu.projection.low | Should -Be $r.Low; $cpu.projection.high | Should -Be $r.High; $cpu.status | Should -Be 'act'
        $cpu.hints -join ' ' | Should -Match 'VMware-Host'; $cpu.projection.kind | Should -Be 'range'
        # eine Spanne aus einer Zahl steht als eine Zahl (Review Focus 5)
        $span = $(if ($r.Low -eq $r.High) { [string]$r.Low } else { '{0} bis {1}' -f $r.Low, $r.High })
        $cpu.projection.text | Should -Match ("etwa $span statt 8 vCPU unter 75 %"); $cpu.projection.text | Should -Not -Match '(\d+) bis \1 '
        ($D.recommendations | Where-Object resource -eq 'host').status | Should -Be 'check'                  # einmal gesehen, nicht wiederkehrend
        ($D.recommendations | Where-Object resource -eq 'memory').status | Should -Be 'ok'
    }
    It 'kennzeichnet jede Zahl der Hochrechnung als Schaetzung mit Annahmen' {
        @($D.recommendations | Where-Object { $null -ne $_.projection }).Count | Should -BeGreaterOrEqual 1
        foreach ($rec in @($D.recommendations | Where-Object { $null -ne $_.projection })) {
            $rec.projection.text | Should -Match 'Schätzung'; @($rec.assumptions).Count | Should -Be 5
            $rec.assumptions[-1] | Should -Be 'Vor einem Umbau mit einem Pilot oder Lasttest bestätigen.'
        }
        foreach ($rec in @($D.recommendations | Where-Object { $null -eq $_.projection })) { @($rec.assumptions).Count | Should -Be 0 }
    }
    It 'sagt wenig Messzeit an jeder Empfehlung, mit genug Messzeit nicht' {
        $D.meta.lowMeasure | Should -BeTrue; foreach ($rec in $D.recommendations) { $rec.reliability | Should -Match 'wenig Messzeit' }
        $e = Get-ReportData $R.Enough; $e.meta.lowMeasure | Should -BeFalse; foreach ($rec in $e.recommendations) { $rec.reliability | Should -Not -Match 'enig Messzeit' }
    }
    It 'nennt je Aufzeichnung den Befehl ihres Berichts' { $D.runs[0].command | Should -Be (".\New-WorkerPerfReport.ps1 -Path '{0}' -RoleFile '{1}'" -f $R.Runs.Days[0], $R.Roles) }
    It 'fuehrt Sitzungen je vCPU gegen die Obergrenzen 6/4/2/1 als Einordnung' {
        $D.usersPerVcpu.sessionsPeak | Should -Be 31; @($D.usersPerVcpu.limits.perVcpu) | Should -Be @(6, 4, 2, 1); @($D.usersPerVcpu.limits.sessions) | Should -Be @(48, 32, 16, 8)
        $D.usersPerVcpu.note | Should -Match 'keine Bewertung'
    }
    It 'gibt den Kopiertext mit und ohne Namen' {
        $D.copy.named | Should -Match 'SIM-VDA01'; $D.copy.anonymous | Should -Not -Match 'SIM-VDA01'; $D.copy.named | Should -Match 'Schätzung'
        foreach ($line in @($D.copy.named -split "`r?`n")) { $line.Length | Should -BeLessOrEqual 78 }
    }
    It 'fuehrt die Punkte der Hauptzeit, das Zustandsbild als Beleg und die Quellen' {
        @($D.scatter.cpu).Count | Should -BeGreaterThan 500; @($D.scatter.cpu).Count | Should -BeLessOrEqual 2000; @($D.scatter.sessions).Count | Should -Be @($D.scatter.cpu).Count
        ($D.evidence | Where-Object id -eq 'size.cpuLogical').value | Should -Be '8'
        @($D.sources.id) | Should -Contain 'SZ-42'; ($D.sources | Where-Object id -eq 'SZ-42').url | Should -Match '^https://'
        $D.grades.act.word | Should -Be 'Handeln'; $D.meta.catalogueVersion | Should -Be $Sz.Version
    }
    It 'nennt die Empfehlungen auf der Konsole' {
        $out = @(& $SizingScript -Path $R.Runs.Days -OutFile (Join-Path $TestDrive 'console.html') -RoleFile $R.Roles 6>&1 | ForEach-Object { [string]$_ })
        ($out -join "`n") | Should -Match 'Groessenbericht erstellt in [\d.]+ s: '; ($out -join "`n") | Should -Match 'CPU: '
    }
}
Describe 'Groessenbericht: Abbrueche und Grenzfaelle' {
    It 'bricht bei verschiedenen Servern ab und nennt die Aufzeichnung' {
        $other = Copy-SimRun $R.Runs.Days[1] (Join-Path $TestDrive 'other'); $mf = Join-Path $other 'meta.json'
        [IO.File]::WriteAllText($mf, [IO.File]::ReadAllText($mf).Replace('SIM-VDA01', 'SIM-VDA02'))
        $out = Join-Path $TestDrive 'nie.html'
        { & $SizingScript -Path $R.Runs.Days[0], $other -OutFile $out } | Should -Throw "*'$other'*SIM-VDA02*spaeterer Baustein*"
        Test-Path $out | Should -BeFalse
    }
    It 'lehnt dieselbe Aufzeichnung zweimal ab' { { & $SizingScript -Path $R.Runs.Days[0], $R.Runs.Days[0] } | Should -Throw '*zweimal*' }      # Review Focus 3
    It 'lehnt nur Schnelllaeufe ab' { { & $SizingScript -Path $R.Runs.Quick } | Should -Throw '*keine Messung*' }                                  # Review Focus 3
    It 'lehnt einen fehlenden Ordner und einen fehlerhaften Katalog vor dem Auswerten ab' {
        { & $SizingScript -Path (Join-Path $TestDrive 'gibtsnicht') } | Should -Throw '*nicht gefunden*'
        $bad = Join-Path $TestDrive 'bad-sizing.json'
        $j = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../src/sizing.de.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json; $j.thresholds.coreBusyPct.value = 40
        [IO.File]::WriteAllText($bad, ($j | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding $false))
        { & $SizingScript -Path $R.Runs.Days[0] -SizingFile $bad } | Should -Throw '*coreBusyPct*'
    }
    It 'nimmt die Aufzeichnungen in beliebiger Reihenfolge und eine aeltere dazu' {                                                              # Review Focus 2, 3
        $old = New-OldCaptureCopy $R.Runs.Days[2] (Join-Path $TestDrive 'old3')
        $f = Join-Path $TestDrive 'mix.html'; & $SizingScript -Path $R.Runs.Days[4], $old, $R.Runs.Days[0] -OutFile $f -RoleFile $R.Roles 6>$null | Out-Null
        $d = Get-ReportData $f; @($d.runs.start) | Should -Be @(@($d.runs.start) | Sort-Object); $d.meta.recordings | Should -Be 3
        ($d.recurring | Where-Object id -eq 'capacity').count | Should -Be 2                              # die aeltere zaehlt fuer Last und Klassen
    }
    It 'schreibt ohne -OutFile neben die erste Aufzeichnung' {
        $one = Copy-SimRun $R.Runs.Days[0] (Join-Path $TestDrive 'solo')
        $f = & $SizingScript -Path $one -RoleFile $R.Roles 6>$null
        (Split-Path $f.FullName -Parent) | Should -Be (Split-Path $one -Parent); $f.Name | Should -Match '^groesse-\d{8}-\d{6}\.html$'
    }
}
Describe 'Groessenbericht maskiert' {
    It 'enthaelt bei Alles keinen Namen der Aufzeichnungen, bei Personen den Server' {
        $f = New-CanarySizing -Mask Alles; $t = [IO.File]::ReadAllText($f)
        $t.Contains('SIM-CANARY01') | Should -BeFalse; (Get-ReportData $f).meta.mask | Should -Be 'Alles'
        [IO.File]::ReadAllText((New-CanarySizing -Mask Personen)).Contains('SIM-CANARY01') | Should -BeTrue
        $m = Get-ReportData $R.Masked; $m.meta.server | Should -Not -Be 'SIM-VDA01'; [IO.File]::ReadAllText($R.Masked).Contains('SIM-VDA01') | Should -BeFalse
        $m.copy.anonymous | Should -BeNullOrEmpty; $m.copy.named | Should -Not -Match 'SIM-VDA01'
        (Get-ReportData $R.MaskedP).meta.server | Should -Be 'SIM-VDA01'
    }
    It 'nennt im maskierten Bericht keinen Ordner des Erstellers (Gesamtpruefung, Befund 1)' {
        # Aufzeichnungen und Rollendatei unter einem Ordner, dessen Name in keiner Aufzeichnung steht
        $dir = Join-Path $TestDrive 'kwagner-adm/Desktop'; [void](New-Item -ItemType Directory -Path $dir -Force)
        $copies = [string[]]@($R.Runs.Days[0], $R.Runs.Days[1] | ForEach-Object { Copy-SimRun $_ $dir }); $roles = Join-Path $dir 'rollen.json'; Copy-Item $R.Roles $roles
        foreach ($level in 'Alles', 'Personen') {
            $out = Join-Path $TestDrive "pfad-$level.html"; [void](& $SizingScript -Path $copies -OutFile $out -RoleFile $roles -Mask $level 6>$null)
            $t = [IO.File]::ReadAllText($out); $t.Contains('kwagner') | Should -BeFalse -Because $level
            $shownData = Get-ReportData $out; $shownData.runs[0].command | Should -Match "^\.\\New-WorkerPerfReport\.ps1 -Path '[^\\/']+' -RoleFile '[^\\/']+'$"
        }
        # ohne -Mask steht der ganze Pfad da
        $D.runs[0].folder | Should -Be $R.Runs.Days[0]
    }
    It 'ordnet jedes Textfeld der Berichtsdaten im Bestand ein' {
        $census = Get-Content (Join-Path $PSScriptRoot 'SizingMaskCensus.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        @($census.fields.PSObject.Properties | Where-Object { @('name', 'keyword', 'composed') -notcontains [string]$_.Value }) | Should -BeNullOrEmpty
        $paths = @(Get-StringFieldPaths $D) + @(Get-StringFieldPaths (Get-ReportData (New-CanarySizing -Mask Alles)))
        $paths.Count | Should -BeGreaterThan 60
        foreach ($p in $paths) { $census.fields.PSObject.Properties.Name | Should -Contain $p -Because $p }
        # ein Schluesselwort steht in den Schluesselwortfeldern der Maske
        . (Join-Path $PSScriptRoot '../src/WorkerPerf.EventConfig.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Events.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Load.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Mask.ps1')
        foreach ($p in $census.fields.PSObject.Properties) {
            $keys = $p.Name.Replace('[]', '').Split('.'); $field = $keys[-1]; $holder = $(if ($keys.Count -gt 1) { $keys[-2] } else { '' })
            $listed = $WorkerPerfMaskKeywordFields -contains $field -or $WorkerPerfMaskKeywordFields -contains "$holder.$field"
            $listed | Should -Be ([string]$p.Value -eq 'keyword') -Because $p.Name
        }
    }
    It 'lehnt bei Alles einen Dateinamen mit dem Server ab' { { & $SizingScript -Path $R.Runs.Days -Mask Alles -OutFile (Join-Path $TestDrive 'SIM-VDA01.html') } | Should -Throw '*nennt den Server*' }
    It 'schreibt die Zuordnung mit -MaskMapFile' { (Get-Content (New-CanarySizing -Mask Alles -MapFile) -Raw | ConvertFrom-Json).entries.name | Should -Contain 'SIM-CANARY01' }
}
