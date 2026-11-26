#Requires -Version 5.1

<#
.SYNOPSIS
    Builds the sizing report ("Groesse des Servers") from several WorkerPerf recordings of the same server.

.DESCRIPTION
    Reads every recording with the same evaluation as New-WorkerPerfReport.ps1 (loader, findings, incidents, the class
    of every CPU and memory incident) and puts them side by side: which cause of a bottleneck recurs, the typical peak
    load of the main time, and a recommendation per resource as a direction with a projection that is marked as an
    estimate. The report does not replace the report of a recording: it names the command that makes each of them.

    A quick run (-HealthOnly) does not count for the load; its health picture is used as evidence. All recordings must
    come from the same server (the computer name, without regard to case). Under the minimum of the catalogue (three
    recordings and twelve hours of main time) the report is still written, and every recommendation says "wenig Messzeit".

.PARAMETER Path
    The folders of the recordings, in any order (at least one with a measurement; several working days make sense).

.PARAMETER OutFile
    Target file. Default: groesse-<yyyyMMdd-HHmmss>.html in the folder above the first recording.

.PARAMETER Mask
    Replaces names in the report, as in New-WorkerPerfReport.ps1: Personen (users, clients) or Alles (also servers,
    shares, printers, addresses). The names of all recordings get their replacement names in the order given.

.PARAMETER MaskMapFile
    With -Mask: writes the names and their replacement names to this file (it holds the real names: keep it).

.PARAMETER SizingFile
    Catalogue of the size of the server. Default: sizing.de.json next to this script.

.PARAMETER ThresholdFile
    Threshold file. Default: thresholds.json next to this script.

.PARAMETER GuidanceFile
    Guidance catalogue; checked like in the report of a recording and taken over into its command. Default:
    guidance.de.json next to this script.

.PARAMETER AppsFile
    Application list; checked and taken over into the command of each recording. Default: apps.json next to this script.

.PARAMETER RoleFile
    Role file. Default: roles.json next to this script.

.EXAMPLE
    .\New-WorkerPerfSizingReport.ps1 -Path D:\WorkerPerf\VDA01_20261109-070000, D:\WorkerPerf\VDA01_20261110-070000, D:\WorkerPerf\VDA01_20261111-070000
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string[]]$Path,
    [string]$OutFile,
    [ValidateSet('Personen', 'Alles')][string]$Mask,
    [string]$MaskMapFile,
    [string]$SizingFile,
    [string]$ThresholdFile,
    [string]$GuidanceFile,
    [string]$AppsFile,
    [string]$RoleFile
)

$languageMode = "$($ExecutionContext.SessionState.LanguageMode)"
if ($languageMode -ne 'FullLanguage') {
    throw "WorkerPerf benoetigt den PowerShell-Sprachmodus FullLanguage; aktiv ist $languageMode. AppLocker oder WDAC schraenkt diese Konsole ein: bitte eine uneingeschraenkte administrative Konsole verwenden."
}

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture

. (Join-Path $PSScriptRoot 'WorkerPerf.Common.ps1')
. (Join-Path $PSScriptRoot 'WorkerPerf.EventConfig.ps1')
. (Join-Path $PSScriptRoot 'WorkerPerf.Events.ps1')
. (Join-Path $PSScriptRoot 'WorkerPerf.Load.ps1')
. (Join-Path $PSScriptRoot 'WorkerPerf.Findings.ps1')
. (Join-Path $PSScriptRoot 'WorkerPerf.Guidance.ps1')
. (Join-Path $PSScriptRoot 'WorkerPerf.Sizing.ps1')
. (Join-Path $PSScriptRoot 'WorkerPerf.Mask.ps1')
. (Join-Path $PSScriptRoot 'WorkerPerf.Page.ps1')
if ($Mask) { if ($Mask -eq 'Alles') { $Mask = 'Alles' } else { $Mask = 'Personen' } }

$timer = [Diagnostics.Stopwatch]::StartNew()

#region ---------- checks before anything is evaluated ------------------------------------

# the folders exist; the same folder twice is refused
$folders = New-Object System.Collections.Generic.List[string]
foreach ($p in $Path) {
    if ([string]::IsNullOrWhiteSpace($p) -or -not (Test-Path -LiteralPath $p -PathType Container)) { throw "Aufzeichnungsordner '$p' nicht gefunden." }
    $full = (Resolve-Path -LiteralPath $p).Path.TrimEnd([char[]]@('\', '/'))
    foreach ($known in $folders) {
        if ([string]::Equals($known, $full, [StringComparison]::OrdinalIgnoreCase)) { throw "Die Aufzeichnung '$full' ist zweimal angegeben." }
    }
    $folders.Add($full)
}

# catalogues and lists: an error stops here; a file given by the caller goes into the command of each recording
$given = [ordered]@{}
foreach ($name in 'ThresholdFile', 'RoleFile', 'GuidanceFile', 'AppsFile', 'SizingFile') {
    if ($PSBoundParameters.ContainsKey($name) -and $PSBoundParameters[$name]) {
        $given[$name] = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath([string]$PSBoundParameters[$name])
    }
}
if ($given.Contains('ThresholdFile')) { $ThresholdFile = $given['ThresholdFile'] } else { $ThresholdFile = Join-Path $PSScriptRoot 'thresholds.json' }
if ($given.Contains('RoleFile')) { $RoleFile = $given['RoleFile'] } else { $RoleFile = Join-Path $PSScriptRoot 'roles.json' }
if ($given.Contains('GuidanceFile')) { $GuidanceFile = $given['GuidanceFile'] } else { $GuidanceFile = Join-Path $PSScriptRoot 'guidance.de.json' }
if ($given.Contains('AppsFile')) { $AppsFile = $given['AppsFile'] } else { $AppsFile = Join-Path $PSScriptRoot 'apps.json' }
if ($given.Contains('SizingFile')) { $SizingFile = $given['SizingFile'] } else { $SizingFile = Join-Path $PSScriptRoot 'sizing.de.json' }
$templateFile = Join-Path $PSScriptRoot 'sizing-template.html'
if (-not (Test-Path -LiteralPath $templateFile)) { throw "Vorlage nicht gefunden: $templateFile" }
$thresholds = Read-WorkerPerfThresholds $ThresholdFile
$sizing = Read-WorkerPerfSizing $SizingFile $thresholds
$roles = @(Read-WorkerPerfRoles $RoleFile)
$texts = Read-WorkerPerfTexts (Join-Path $PSScriptRoot 'texts.de.json')
# checked as in the report of a recording, so that the command named for each recording runs with these files
$appList = Read-WorkerPerfApps $AppsFile
[void](Read-WorkerPerfGuidance $GuidanceFile -Apps $appList)
$eventConfig = Read-WorkerPerfEventConfig (Join-Path $PSScriptRoot 'events.json')

# the same server (the one place of this check), and at least one recording with a measurement
$heads = @(foreach ($f in $folders) { Get-WorkerPerfRunServer $f })
Assert-WorkerPerfSameServer $heads
if (@($heads | Where-Object { -not $_.HealthOnly }).Count -eq 0) {
    throw 'Die Aufzeichnungen enthalten keine Messung; ein Schnelllauf (-HealthOnly) zaehlt nicht fuer die Last.'
}

if (-not $OutFile) { $OutFile = Join-Path (Split-Path -Parent $folders[0]) ('groesse-{0}.html' -f [datetime]::Now.ToString('yyyyMMdd-HHmmss', $inv)) }
$OutFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
$outDir = Split-Path -Parent $OutFile
if ($outDir -and -not (Test-Path -LiteralPath $outDir -PathType Container)) { throw "Zielordner '$outDir' nicht gefunden." }
if ($MaskMapFile -and -not $Mask) { throw '-MaskMapFile gilt nur zusammen mit -Mask.' }
if ($MaskMapFile) {
    $MaskMapFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($MaskMapFile)
    if ([string]::Equals([IO.Path]::GetFullPath($MaskMapFile), [IO.Path]::GetFullPath($OutFile), [StringComparison]::OrdinalIgnoreCase)) { throw '-MaskMapFile darf nicht die Berichtsdatei sein.' }
    $maskMapDir = Split-Path -Parent $MaskMapFile
    if ($maskMapDir -and -not (Test-Path -LiteralPath $maskMapDir -PathType Container)) { throw "Ordner der Zuordnungsdatei '$maskMapDir' nicht gefunden." }
    # a recording is never changed: the map must not overwrite one of its files
    $maskMapFull = [IO.Path]::GetFullPath($MaskMapFile)
    foreach ($f in $folders) {
        $inside = [IO.Path]::GetFullPath($f).TrimEnd([char[]]@('\', '/')) + [IO.Path]::DirectorySeparatorChar
        if ([IO.File]::Exists($maskMapFull) -and $maskMapFull.StartsWith($inside, [StringComparison]::OrdinalIgnoreCase)) {
            throw "-MaskMapFile nennt die Datei '$maskMapFull' einer Aufzeichnung; eine Aufzeichnung wird nie veraendert: bitte eine Datei ausserhalb der Aufzeichnungsordner waehlen."
        }
    }
}
if ($Mask -eq 'Alles') {
    $serverName = [string]$heads[0].Server
    if ($serverName -and (Split-Path -Leaf $OutFile).IndexOf($serverName, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw 'Der Dateiname des Berichts nennt den Server; bei -Mask Alles bitte einen anderen Namen waehlen.'
    }
}

#endregion

#region ---------- evaluation --------------------------------------------------------------

# the command that makes the report of a recording, with the files the caller gave
$commands = @{}
$quote = { param([string]$Text) "'" + $Text.Replace("'", "''") + "'" }
foreach ($f in $folders) {
    $cmd = ".\New-WorkerPerfReport.ps1 -Path " + (& $quote $f)
    foreach ($name in $given.Keys) { $cmd += ' -' + $name + ' ' + (& $quote ([string]$given[$name])) }
    $commands[$f] = $cmd
}

$runs = New-Object System.Collections.Generic.List[object]
$n = 0
foreach ($f in $folders) {
    $n++
    Write-Host ('Werte Aufzeichnung {0} von {1} aus: {2}' -f $n, $folders.Count, $f)
    $analysis = Get-WorkerPerfRunAnalysis -Path $f -Thresholds $thresholds -Roles $roles -Sizing $sizing
    $runs.Add((Get-WorkerPerfSizingRun -Analysis $analysis -Path $f -Sizing $sizing))
    $analysis = $null
}
# phase 1: one server, the recordings along the axis time
$group = @(Group-WorkerPerfSizingRuns $runs.ToArray() 'time')[0]
$summary = Get-WorkerPerfSizingSummary -Group $group -Sizing $sizing
$data = New-WorkerPerfSizingData -Summary $summary -Sizing $sizing -Commands $commands -Generated ([DateTimeOffset]::Now.ToUnixTimeMilliseconds())

#endregion

#region ---------- copy text, masking, writing ----------------------------------------------

$roleLabels = @($roles | ForEach-Object { [string]$_.label })
$paragraphs = [string[]]@(Get-WorkerPerfSizingCopyParagraphs $data $sizing)
$maskObj = $null
if ($Mask) {
    # the paragraphs are masked with the data and wrapped after that; a masked report has no version without names
    $maskObj = New-WorkerPerfMask -Path $folders.ToArray() -Level $Mask -Texts $texts -RoleLabels $roleLabels -EventConfig $eventConfig
    $data['copy']['named'] = $paragraphs
    $data = Protect-WorkerPerfReportData $data $maskObj
    $data['copy']['named'] = Format-WorkerPerfCopyLines ([string[]]@($data['copy']['named']))
    $data['meta']['mask'] = $Mask
}
else {
    $anonymousMask = New-WorkerPerfMask -Path $folders.ToArray() -Level 'Alles' -Texts $texts -RoleLabels $roleLabels -EventConfig $eventConfig
    $data['copy']['named'] = Format-WorkerPerfCopyLines $paragraphs
    $data['copy']['anonymous'] = Format-WorkerPerfCopyLines ([string[]]@($paragraphs | ForEach-Object { ConvertTo-WorkerPerfAnonymousText $_ $anonymousMask }))
}

Write-Host 'Schreibe Bericht ...'
Write-WorkerPerfPage $templateFile $data $OutFile
# the map only once the report is complete; a failure here leaves the report as written
if ($MaskMapFile) {
    try { Save-WorkerPerfMaskMap -Mask $maskObj -Path $MaskMapFile }
    catch { throw ("Bericht geschrieben ({0}), die Zuordnungsdatei '{1}' aber nicht: {2}" -f $OutFile, $MaskMapFile, $_.Exception.Message) }
}

$timer.Stop()
Write-Host ('Groessenbericht erstellt in {0} s: {1}' -f $timer.Elapsed.TotalSeconds.ToString('0.0', $inv), $OutFile)
Write-Host ('  ' + [string]$data['result']['text'])
foreach ($r in @($data['recommendations'])) {
    $line = '  {0}: {1}' -f (Format-WorkerPerfSizingText $sizing ('rec.' + [string]$r['resource'])), [string]$r['advice']
    if ($null -ne $r['projection']) { $line += ' ' + [string]$r['projection']['text'] }
    Write-Host $line
}
if ($Mask) {
    Write-Host ('  maskiert (Stufe {0}): {1} Namen ersetzt' -f $Mask, @($maskObj.Entries).Count)
    if ($MaskMapFile) { Write-Host ('  Zuordnung der Ersatznamen: {0}' -f $MaskMapFile) }
}
Get-Item -LiteralPath $OutFile

#endregion
