#Requires -Version 5.1
# WorkerPerf page library: the JSON writer of the report data and the writing of a page from its template.
# Defines functions only; used by New-WorkerPerfReport.ps1 and New-WorkerPerfSizingReport.ps1.

$script:JsonSpecial = New-Object System.Text.RegularExpressions.Regex ('[\x00-\x1f"\\<>&\u2028\u2029]', [System.Text.RegularExpressions.RegexOptions]::Compiled)

function Format-JsonString([string]$Text) {
    if ($null -eq $Text) { return 'null' }
    if (-not $script:JsonSpecial.IsMatch($Text)) { return '"' + $Text + '"' }
    $sb = New-Object System.Text.StringBuilder ($Text.Length + 16)
    [void]$sb.Append('"')
    foreach ($c in $Text.ToCharArray()) {
        $code = [int]$c
        if ($c -eq '"') { [void]$sb.Append('\"') }
        elseif ($c -eq '\') { [void]$sb.Append('\\') }
        elseif ($code -lt 32 -or $c -eq '<' -or $c -eq '>' -or $c -eq '&' -or $code -eq 0x2028 -or $code -eq 0x2029) { [void]$sb.Append('\u' + $code.ToString('x4', [Globalization.CultureInfo]::InvariantCulture)) }
        else { [void]$sb.Append($c) }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Format-JsonNumber([double]$Value, [int]$Decimals) {
    if ([double]::IsNaN($Value) -or [double]::IsInfinity($Value)) { return 'null' }
    return [Math]::Round($Value, $Decimals).ToString([Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-JsonText($Value, [System.IO.TextWriter]$Out) {
    # Small JSON writer for ordered records, writing to $Out. A StringBuilder value is inserted verbatim (pre-rendered series).
    if ($null -eq $Value) { $Out.Write('null'); return }
    if ($Value -is [System.Text.StringBuilder]) { $Out.Write($Value.ToString()); return }
    if ($Value -is [string]) { $Out.Write((Format-JsonString $Value)); return }
    if ($Value -is [bool]) { if ($Value) { $Out.Write('true') } else { $Out.Write('false') }; return }
    if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) { $Out.Write((Format-JsonNumber ([double]$Value) 3)); return }
    if ($Value -is [ValueType]) { $Out.Write(([IConvertible]$Value).ToString([Globalization.CultureInfo]::InvariantCulture)); return }
    if ($Value -is [System.Collections.IDictionary]) {
        $Out.Write('{')
        $first = $true
        foreach ($k in $Value.Keys) {
            if (-not $first) { $Out.Write(',') }
            $first = $false
            # plain keys, strings without special characters and whole numbers are written here, without a call per
            # value (one record per event: the writer runs this loop hundreds of thousands of times)
            $ks = [string]$k
            if ($script:JsonSpecial.IsMatch($ks)) { $Out.Write((Format-JsonString $ks)); $Out.Write(':') } else { $Out.Write('"' + $ks + '":') }
            $v = $Value[$k]
            if ($v -is [string] -and -not $script:JsonSpecial.IsMatch($v)) { $Out.Write('"' + $v + '"') }
            elseif ($v -is [int] -or $v -is [long]) { $Out.Write($v.ToString([Globalization.CultureInfo]::InvariantCulture)) }
            else { ConvertTo-JsonText $v $Out }
        }
        $Out.Write('}')
        return
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $Out.Write('[')
        $first = $true
        foreach ($v in $Value) {
            if (-not $first) { $Out.Write(',') }
            $first = $false
            ConvertTo-JsonText $v $Out
        }
        $Out.Write(']')
        return
    }
    $Out.Write((Format-JsonString ([string]$Value)))
}

function Write-WorkerPerfPage([string]$TemplateFile, $Data, [string]$OutFile) {
    # Writes the page: the template with the report data in place of the placeholder's 'null'. The JSON is written straight
    # into the file (UTF-8 without BOM), so the report is never held in memory as a whole. It goes to a temporary file next
    # to the target first; only when it is complete is an existing target deleted and the temporary file moved onto its
    # name. An error while writing, or a target that cannot be deleted (read-only, locked), leaves the previous report as
    # it was. Only an error between the delete and the move leaves no report. The temporary file is removed on any error.
    # No File.Replace: some file systems used for reports (FAT/exFAT, some SMB/NAS and DFS shares) do not support it.
    $template = [IO.File]::ReadAllText($TemplateFile, [Text.Encoding]::UTF8)
    $marker = '<script id="wp-data" type="application/json">null</script>'
    $at = $template.IndexOf($marker)
    if ($at -lt 0) { throw 'Die Berichtsvorlage enthaelt keinen Datenplatzhalter.' }
    $open = '<script id="wp-data" type="application/json">'
    $tmpFile = $OutFile + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $writer = New-Object System.IO.StreamWriter($tmpFile, $false, (New-Object System.Text.UTF8Encoding $false), 65536)
        try {
            $writer.Write($template.Substring(0, $at + $open.Length))
            ConvertTo-JsonText $Data $writer
            $writer.Write($template.Substring($at + $open.Length + 4))
        }
        finally { $writer.Dispose() }
        if ([IO.File]::Exists($OutFile)) { [IO.File]::Delete($OutFile) }
        [IO.File]::Move($tmpFile, $OutFile)
    }
    catch {
        if ([IO.File]::Exists($tmpFile)) { Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue }
        throw
    }
}
