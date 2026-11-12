#Requires -Version 5.1
# WorkerPerf analysis library: reads the event and print files of a capture (definitions only).
# Requires WorkerPerf.Common.ps1 (headers) and WorkerPerf.Load.ps1 (Read-WorkerPerfCsvFile, ConvertTo-WorkerPerfTimestamp).
# Each file is read by its own header line (Read-WorkerPerfCsvFile -OwnHeader): a file of an older format has fewer
# columns. -Skipped receives the number of rows left out because they have fewer fields than that header.
# Read-WorkerPerfEventCsv, Read-WorkerPerfPrintDrivers and Read-WorkerPerfPrintQueues emit plain pipeline output: wrap calls in @(...).

$script:WorkerPerfEventNumberColumns = @('EventId', 'Level', 'Pid', 'SessionId')
# Format 2 wrote no group: these kinds were all of the security group.
$script:WorkerPerfSecurityKinds = @('scan-start', 'scan-end', 'signature-update', 'applocker-block')

function Read-WorkerPerfEventCsv([string]$Path, [string]$FileName, [ref]$Skipped) {
    # Events of events.csv or events_before.csv in format 2 or 3 as hashtables with TimeMs and every column of format 3:
    # a column the file lacks is '', the number columns are [int] (empty or unreadable = -1). Sorted by time, on equal
    # times by position in the file (a scan-start and scan-end in the same millisecond must keep their order to pair).
    $csv = Read-WorkerPerfCsvFile $Path $FileName -OwnHeader
    if ($null -ne $Skipped) { $Skipped.Value = [int]$csv.Skipped }
    $col = $csv.Col
    $names = $script:WorkerPerfHeaders['events.csv'].Split(',')
    $list = New-Object System.Collections.Generic.List[object]
    if (-not $col.ContainsKey('Timestamp')) { return }
    $cTs = [int]$col['Timestamp']
    foreach ($f in $csv.Rows) {
        $dto = ConvertTo-WorkerPerfTimestamp $f[$cTs]
        if ($null -eq $dto) { continue }
        $e = @{ TimeMs = $dto.ToUnixTimeMilliseconds() }
        foreach ($n in $names) {
            $text = ''
            if ($col.ContainsKey($n)) { $text = $f[[int]$col[$n]] }
            if ($script:WorkerPerfEventNumberColumns -contains $n) {
                $v = 0
                if (-not [int]::TryParse($text, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { $v = -1 }
                $e[$n] = $v
            }
            else { $e[$n] = $text }
        }
        if ($e['Group'] -eq '' -and $script:WorkerPerfSecurityKinds -contains $e['Kind']) { $e['Group'] = 'security' }
        $list.Add($e)
    }
    $arr = $list.ToArray()
    if ($arr.Length -eq 0) { return }
    $order = @(0..($arr.Length - 1) | Sort-Object -Property @{ Expression = { $arr[$_].TimeMs } }, @{ Expression = { $_ } })
    foreach ($ix in $order) { $arr[$ix] }
}

function Read-WorkerPerfPrintDrivers([string]$Path, [ref]$Skipped) {
    # printdrivers.csv: @{ Name; Manufacturer; Version; Type = [int] (0 = unknown); Isolation; Files = string[] }.
    # Files is split at ';' (the writer joins the file names with it; Windows driver file names carry none).
    $csv = Read-WorkerPerfCsvFile $Path 'printdrivers.csv' -OwnHeader
    if ($null -ne $Skipped) { $Skipped.Value = [int]$csv.Skipped }
    $col = $csv.Col
    foreach ($k in 'Name', 'Manufacturer', 'Version', 'Type', 'Isolation', 'Files') { if (-not $col.ContainsKey($k)) { return } }
    foreach ($f in $csv.Rows) {
        $type = 0
        if (-not [int]::TryParse($f[[int]$col['Type']], [ref]$type)) { $type = 0 }
        $files = [string[]]@($f[[int]$col['Files']].Split(';') | Where-Object { $_.Length -gt 0 })
        @{ Name = $f[[int]$col['Name']]; Manufacturer = $f[[int]$col['Manufacturer']]; Version = $f[[int]$col['Version']]; Type = $type
            Isolation = $f[[int]$col['Isolation']]; Files = $files }
    }
}

function Read-WorkerPerfPrintQueues([string]$Path, [long]$FromMs, [long]$ToMs, [ref]$Skipped) {
    # printqueues.csv rows with FromMs <= TimeMs <= ToMs: @{ TimeMs; Queue; Jobs; JobErrors; NotReadyErrors } (counters as
    # [double], NaN when unreadable; the error counters are running raw values).
    $csv = Read-WorkerPerfCsvFile $Path 'printqueues.csv' -OwnHeader
    if ($null -ne $Skipped) { $Skipped.Value = [int]$csv.Skipped }
    $col = $csv.Col
    foreach ($k in 'Timestamp', 'Queue', 'Jobs', 'JobErrors', 'NotReadyErrors') { if (-not $col.ContainsKey($k)) { return } }
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $style = [Globalization.NumberStyles]::Float
    foreach ($f in $csv.Rows) {
        $dto = ConvertTo-WorkerPerfTimestamp $f[[int]$col['Timestamp']]
        if ($null -eq $dto) { continue }
        $ms = $dto.ToUnixTimeMilliseconds()
        if ($ms -lt $FromMs -or $ms -gt $ToMs) { continue }
        $q = @{ TimeMs = $ms; Queue = $f[[int]$col['Queue']] }
        foreach ($k in 'Jobs', 'JobErrors', 'NotReadyErrors') {
            $v = [double]::NaN
            if (-not [double]::TryParse($f[[int]$col[$k]], $style, $inv, [ref]$v)) { $v = [double]::NaN }
            $q[$k] = $v
        }
        $q
    }
}
