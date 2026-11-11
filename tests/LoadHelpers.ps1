# Shared set-up for the loader tests: dot-source inside BeforeAll.
Set-StrictMode -Version 2
. (Join-Path $PSScriptRoot '../src/WorkerPerf.Common.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.EventConfig.ps1')
. (Join-Path $PSScriptRoot '../src/WorkerPerf.Events.ps1'); . (Join-Path $PSScriptRoot '../src/WorkerPerf.Load.ps1')
$script:Th = Read-WorkerPerfThresholds (Join-Path $PSScriptRoot '../src/thresholds.json')
$script:Roles = Read-WorkerPerfRoles (Join-Path $PSScriptRoot '../src/roles.json')
$script:Base = [DateTimeOffset]'2026-01-15T08:00:00+01:00'
function Get-Ts([double]$Sec) { $Base.AddSeconds($Sec).ToString('o') }
function New-TickLine([int]$T, [double]$Cpu = 50) { "$T,$(Get-Ts (2 * ($T + 1))),2,$Cpu,8,,4096,8000,20000,0,0,0,0,0,0,0,0,0,5" }
function New-SnapLine([int]$P, [string]$Kind = 'R') { "$P,$(2 * $P + 1),$(Get-Ts (4 * ($P + 1))),4,$Kind,1,1,3,3,20" }
# Write-TestRun schreibt eine Aufzeichnung im Format 2 (passend zu "SchemaVersion":2): events.csv mit der Kopfzeile von
# Format 2, die Dateien, die erst Format 3 kennt, nur wenn ein Test sie nennt (dann mit der Kopfzeile von Format 3).
$script:Format2Headers = @{ 'events.csv' = 'Timestamp,Source,EventId,Kind,Text' }
$script:Format3Only = @('events_before.csv', 'printdrivers.csv', 'printqueues.csv')
function Write-TestRun([string]$Name, [hashtable]$Files) {
    $dir = Join-Path $TestDrive $Name; [void](New-Item -ItemType Directory -Path $dir -Force)
    foreach ($f in $WorkerPerfHeaders.Keys) {
        if ($Files.ContainsKey($f) -and $null -eq $Files[$f]) { continue }             # $null = die Datei fehlt
        if ($Format3Only -contains $f -and -not $Files.ContainsKey($f)) { continue }
        $header = $(if ($Format2Headers.ContainsKey($f)) { $Format2Headers[$f] } else { $WorkerPerfHeaders[$f] })
        [IO.File]::WriteAllLines((Join-Path $dir $f), [string[]](@($header) + @($Files[$f] | Where-Object { $_ })))
    }
    $meta = '{"SchemaVersion":2,"Computer":"T1","OS":"x","LogicalProcessors":4,"PhysicalMemoryMB":16384,"FastIntervalSeconds":2,"IntervalSeconds":4,"StartTime":"' + (Get-Ts 0) +
        '","EndTime":null,"CollectorPid":4242,"Simulated":false,"Endpoints":[{"Name":"DB","Host":"h","Port":1521,"Role":"Datenbank"}],' +
        '"Sources":{"cpu.host":{"Available":true,"Detail":""},"cpu.steal":{"Available":false,"Detail":"VM Processor fehlt"}}}'
    [IO.File]::WriteAllText((Join-Path $dir 'meta.json'), $meta); $dir
}
function Import-TestRun([string]$Name, [hashtable]$Files, [hashtable]$Extra = @{}) { Import-WorkerPerfRun -Path (Write-TestRun $Name $Files) -Thresholds $Th -Roles $Roles @Extra }
# Grundgeruest: 8 Takte bei 2, 4, ... 16 s; 4 Schnappschuesse bei 4, 8, 12, 16 s (Schnappschuss P liegt auf Takt 2P + 1)
$script:Ticks = 0..7 | ForEach-Object { New-TickLine $_ }
$script:SnapLines = 0..3 | ForEach-Object { New-SnapLine $_ $(if ($_ -eq 0) { 'K' } else { 'R' }) }
