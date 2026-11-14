BeforeDiscovery {
    $script:Sources = @(Get-ChildItem (Join-Path $PSScriptRoot '../src') -Filter *.ps1)
    # the scripts with comment-based help (a .SYNOPSIS line of their own)
    $script:HelpScripts = @($script:Sources | Where-Object { [IO.File]::ReadAllText($_.FullName) -match '(?m)^\s*\.SYNOPSIS\s*$' })
}

BeforeAll {
    function Get-CompatViolations([string]$Path) {
        # Returns the ids of the Windows PowerShell 5.1 compatibility rules that $Path violates.
        $found = [System.Collections.Generic.List[string]]::new()
        $add = { param($rule) if (-not $found.Contains($rule)) { $found.Add($rule) } }

        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) { & $add 'parse' }

        if (@([IO.File]::ReadAllBytes($Path) | Where-Object { $_ -gt 127 }).Count -gt 0) { & $add 'ascii' }

        $firstLine = @([IO.File]::ReadAllLines($Path) | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1)
        if ($firstLine.Count -eq 0 -or $firstLine[0].Trim() -ne '#Requires -Version 5.1') { & $add 'requires' }

        if ($ast.Find({ param($n) $n -is [System.Management.Automation.Language.TernaryExpressionAst] }, $true)) { & $add 'ternary' }
        if ($ast.Find({ param($n) $n -is [System.Management.Automation.Language.PipelineChainAst] }, $true)) { & $add 'chain' }

        $nullKinds = 'QuestionQuestion', 'QuestionQuestionEquals', 'QuestionDot', 'QuestionLBracket'
        if (@($tokens | Where-Object { $nullKinds -contains $_.Kind.ToString() }).Count -gt 0) { & $add 'nullop' }

        # $IsWindows is only allowed as the right operand of "($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows".
        $guard = '($PSVersionTable.PSVersion.Major -lt 6)'
        $platformVars = $ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.VariableExpressionAst] -and
                @('IsWindows', 'IsLinux', 'IsMacOS') -contains $n.VariablePath.UserPath }, $true)
        foreach ($v in $platformVars) {
            $p = $v.Parent
            $allowed = $v.VariablePath.UserPath -eq 'IsWindows' -and
                $p -is [System.Management.Automation.Language.BinaryExpressionAst] -and
                $p.Operator -eq [System.Management.Automation.Language.TokenKind]::Or -and
                [object]::ReferenceEquals($p.Right, $v) -and
                ($p.Left.Extent.Text -replace '\s+', ' ') -eq $guard
            if (-not $allowed) { & $add 'iswindows' }
        }

        # Commands that do not exist in 5.1, and parameters that 5.1 does not know.
        $bannedCommands = 'Join-String', 'Test-Json', 'Get-Error'
        $bannedParams = @{
            'ForEach-Object'    = @('Parallel')
            'ConvertFrom-Json'  = @('AsHashtable', 'Depth')
            'Get-Content'       = @('AsByteStream')
        }
        $aliases = @{ '%' = 'ForEach-Object'; 'foreach' = 'ForEach-Object'; 'gc' = 'Get-Content'; 'cat' = 'Get-Content'; 'type' = 'Get-Content' }
        $commands = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
        foreach ($c in $commands) {
            $name = $c.GetCommandName()
            if (-not $name) { continue }
            if ($aliases.ContainsKey($name)) { $name = $aliases[$name] }
            if ($bannedCommands -contains $name) { & $add 'ps7cmd'; continue }
            $key = @($bannedParams.Keys | Where-Object { $_ -eq $name })
            if ($key.Count -eq 0) { continue }
            foreach ($e in $c.CommandElements) {
                if ($e -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
                $given = $e.ParameterName
                # PowerShell accepts unambiguous prefixes, so "-AsHash" counts as -AsHashtable.
                if ($given.Length -ge 2 -and @($bannedParams[$key[0]] | Where-Object { $_.StartsWith($given, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
                    & $add 'ps7cmd'
                }
            }
        }
        return $found.ToArray()
    }
}

Describe 'Pruefregeln fuer Windows PowerShell 5.1' {
    It 'erkennt <Rule>' -TestCases @(
        @{ Rule = 'ternary';   Code = "#Requires -Version 5.1`n`$a = `$b ? 1 : 2" }
        @{ Rule = 'chain';     Code = "#Requires -Version 5.1`nGet-Item x && Get-Item y" }
        @{ Rule = 'nullop';    Code = "#Requires -Version 5.1`n`$a = `$b ?? 1" }
        @{ Rule = 'ascii';     Code = "#Requires -Version 5.1`n'Datentr$([char]0xE4)ger'" }
        @{ Rule = 'requires';  Code = "'ohne Requires'" }
        @{ Rule = 'iswindows'; Code = "#Requires -Version 5.1`nif (`$IsWindows) { 1 }" }
        @{ Rule = 'ps7cmd';    Code = "#Requires -Version 5.1`n'{}' | ConvertFrom-Json -AsHashtable" }
    ) {
        $file = Join-Path $TestDrive "$Rule.ps1"
        [IO.File]::WriteAllText($file, $Code, (New-Object System.Text.UTF8Encoding $false))
        Get-CompatViolations $file | Should -Contain $Rule
    }
    It 'laesst die abgesicherte Plattformabfrage zu' {
        $file = Join-Path $TestDrive 'ok.ps1'
        [IO.File]::WriteAllText($file, "#Requires -Version 5.1`n`$w = (`$PSVersionTable.PSVersion.Major -lt 6) -or `$IsWindows")
        Get-CompatViolations $file | Should -BeNullOrEmpty
    }
}

Describe 'Quelltext' {
    It '<_.Name> haelt die Regeln ein' -ForEach $Sources { Get-CompatViolations $_.FullName | Should -BeNullOrEmpty }
}

Describe 'Hilfe' {                                                                   # Task 12 Fix 1 O2
    It 'findet die Skripte mit Hilfe' { @($HelpScripts).Count | Should -BeGreaterThan 0 }
    It 'Get-Help <_.Name> zeigt die Kurzbeschreibung' -ForEach $HelpScripts {
        # #Requires directly before the help block hides the help: Get-Help then shows only the syntax.
        $text = [IO.File]::ReadAllText($_.FullName)
        $synopsis = [regex]::Match($text, '(?m)^\s*\.SYNOPSIS\s*\r?\n\s*(\S.*?)\s*$').Groups[1].Value
        $synopsis | Should -Not -BeNullOrEmpty
        ([string](Get-Help $_.FullName).Synopsis).Trim() | Should -BeLike "$([WildcardPattern]::Escape($synopsis))*"
    }
}

Describe 'Funktionsnamen' {
    It 'definiert keinen Funktionsnamen in mehr als einer Datei' {               # Task 14b: Format-WorkerPerfNumber stand in zwei Dateien
        # The data sources WorkerPerf.Sources.*.ps1 define the same fixed names on purpose: they are not compared with each other.
        $owners = @{}
        foreach ($file in Get-ChildItem (Join-Path $PSScriptRoot '../src') -Filter *.ps1) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            $group = $(if ($file.Name -like 'WorkerPerf.Sources.*.ps1') { 'sources' } else { $file.Name })
            $names = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name } | Sort-Object -Unique)
            foreach ($n in $names) {
                if (-not $owners.ContainsKey($n)) { $owners[$n] = [System.Collections.Generic.List[string]]::new() }
                if (-not $owners[$n].Contains($group)) { $owners[$n].Add($group) }
            }
        }
        $clashes = @($owners.Keys | Where-Object { $owners[$_].Count -gt 1 } | Sort-Object | ForEach-Object { "$_ ($($owners[$_] -join ', '))" })
        $clashes | Should -BeNullOrEmpty
    }
}

Describe 'Sprachmodus' {                                                              # Abschlussrunde I9
    It '<Script> bricht im eingeschraenkten Sprachmodus mit einer deutschen Meldung ab' -TestCases @(
        @{ Script = 'Start-WorkerPerfCapture.ps1'; Arguments = '-Simulate -DurationMinutes 60 -OutputPath .' }
        @{ Script = 'New-WorkerPerfReport.ps1'; Arguments = '-Path .' }
        @{ Script = 'Test-WorkerPerfSources.ps1'; Arguments = '-ListChecks' }
    ) {
        # ein eigener Prozess: der Sprachmodus einer Sitzung laesst sich nicht zuruecksetzen
        $file = Join-Path $PSScriptRoot "../src/$Script"
        $command = "`$ExecutionContext.SessionState.LanguageMode = 'ConstrainedLanguage'; try { & '$file' $Arguments } catch { 'MELDUNG: ' + `$_.Exception.Message }"
        $out = @(& (Get-Process -Id $PID).Path -NoProfile -Command $command 2>&1 | ForEach-Object { "$_" }) -join "`n"
        $out | Should -Match 'MELDUNG: WorkerPerf benoetigt den PowerShell-Sprachmodus FullLanguage; aktiv ist ConstrainedLanguage\. AppLocker oder WDAC'
        $out | Should -Match 'uneingeschraenkte administrative Konsole'
    }
}
