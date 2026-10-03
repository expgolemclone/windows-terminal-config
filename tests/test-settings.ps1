#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repositoryRoot 'TerminalConfiguration.psm1') -Force
$settingsPath = Join-Path $repositoryRoot 'settings.json'
Assert-TerminalSettings -SettingsPath $settingsPath
$settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -AsHashtable -Depth 100
$schemes = @($settings.schemes | Where-Object name -eq $settings.profiles.defaults.colorScheme)
if ($schemes.Count -ne 1 -or $schemes[0].foreground -ne '#FFFFFF' -or
    $schemes[0].brightBlack -ne $schemes[0].foreground) {
    throw 'The active color scheme must use white for default and bright-black text, not pink.'
}
Write-Host 'Windows Terminal source settings: OK (not a live-installation check)'
