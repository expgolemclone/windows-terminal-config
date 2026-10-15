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
$expectedColors = @{
    blue = '#82AAFF'
    cyan = '#63D9D3'
    brightBlue = '#B4CEFF'
    selectionBackground = '#34404D'
}
foreach ($slot in $expectedColors.Keys) {
    if ($schemes[0][$slot] -ne $expectedColors[$slot]) {
        throw "Unexpected $slot color: expected $($expectedColors[$slot]), got $($schemes[0][$slot])."
    }
}
foreach ($blueSlot in 'blue', 'brightBlue') {
    foreach ($otherSlot in 'cyan', 'brightCyan', 'purple', 'brightPurple') {
        if ($schemes[0][$blueSlot] -eq $schemes[0][$otherSlot]) {
            throw "$blueSlot must be distinct from $otherSlot."
        }
    }
}
Write-Host 'Windows Terminal source settings: OK (not a live-installation check)'
