# tests/TestHelpers.ps1
function Invoke-SimCapture([string]$OutDir) {
    # 60 Minuten Simulation unter deutscher Kultur; liefert den Aufzeichnungsordner
    [cultureinfo]::CurrentCulture = [cultureinfo]'de-DE'
    $capture = Join-Path $PSScriptRoot '../src/Start-WorkerPerfCapture.ps1'
    (& $capture -Simulate -DurationMinutes 60 -OutputPath $OutDir 6>$null) | Select-Object -Last 1
}
