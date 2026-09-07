$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$settingsPath = Join-Path $repositoryRoot "settings.json"
$settings = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json -Depth 100

if ($settings.firstWindowPreference -ne "defaultProfile") {
    throw "firstWindowPreference must be defaultProfile"
}

if ($settings.windowingBehavior -ne "useNew") {
    throw "windowingBehavior must be useNew"
}

Write-Host "Windows Terminal settings: OK"
