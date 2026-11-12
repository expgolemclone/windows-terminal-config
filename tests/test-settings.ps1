#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$settingsPath = Join-Path $repositoryRoot 'settings.json'
$settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -AsHashtable -Depth 100

if ($settings.ContainsKey('defaultInputScope')) {
    throw 'Terminal must use the default input scope so Japanese IME composition remains available.'
}
$profiles = @($settings.profiles.list | Where-Object { $_.guid -eq $settings.defaultProfile })
if ($profiles.Count -ne 1 -or $profiles[0].ContainsKey('source') -or
    $profiles[0].hidden -ne $false -or $profiles[0]['elevate'] -eq $true -or
    $settings.profiles.defaults['elevate'] -eq $true -or
    $profiles[0]['commandline'] -cne 'mise.exe exec -- pwsh' -or
    $settings.profiles.defaults.ContainsKey('commandline')) {
    throw 'The default profile must be visible, non-elevated PowerShell selected by mise.exe exec -- pwsh, without a dynamic source or default commandline.'
}
foreach ($profile in $settings.profiles.list) {
    if ($profile.guid -eq '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}' -and
        ($profile.hidden -ne $true -or $profile.ContainsKey('commandline'))) {
        throw 'The built-in Windows PowerShell profile must remain hidden without an explicit commandline.'
    }
    if ($profile.ContainsKey('commandline') -and $profile.commandline -match '(?i)(?:powershell|pwsh)(?:\.exe)?' -and
        $profile.commandline -cne 'mise.exe exec -- pwsh') {
        throw 'Every explicit PowerShell commandline must use mise.exe exec -- pwsh.'
    }
}
if ($settings.firstWindowPreference -ne 'defaultProfile' -or $settings.windowingBehavior -ne 'useNew') {
    throw 'Terminal must open new windows using the default profile, not saved layouts.'
}
$expectedBindings = @{
    'ctrl+shift+c' = 'Terminal.CopyToClipboard'
    'ctrl+shift+v' = 'Terminal.PasteFromClipboard'
    'ctrl+c' = 'unbound'
    'ctrl+v' = 'unbound'
    'ctrl+shift+n' = 'Terminal.OpenNewWindow'
}
foreach ($keys in $expectedBindings.Keys) {
    $bindings = @($settings.keybindings | Where-Object { $_.keys -eq $keys })
    if ($bindings.Count -ne 1 -or $bindings[0].id -ne $expectedBindings[$keys]) {
        throw "Unexpected binding for $keys"
    }
}
if (@($settings.actions | Where-Object { $_.id -eq 'User.DuplicateTabToNewWindow' }).Count -ne 0) {
    throw 'Ctrl+Shift+N must not use duplicateTab plus moveTab.'
}

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
Write-Host 'Windows Terminal settings: OK'
