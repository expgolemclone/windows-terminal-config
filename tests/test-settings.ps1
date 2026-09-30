$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$settingsPath = Join-Path $repositoryRoot "settings.json"
$settings = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json -Depth 100

$expectedBindings = @{
    'ctrl+shift+c' = 'Terminal.CopyToClipboard'
    'ctrl+shift+v' = 'Terminal.PasteFromClipboard'
    'ctrl+c' = 'unbound'
    'ctrl+v' = 'unbound'
}
foreach ($keys in $expectedBindings.Keys) {
    $bindings = @($settings.keybindings | Where-Object { $_.keys -eq $keys })
    if ($bindings.Count -ne 1 -or $bindings[0].id -ne $expectedBindings[$keys]) {
        throw "Unexpected binding for $keys"
    }
}

if ($settings.firstWindowPreference -ne "defaultProfile") {
    throw "firstWindowPreference must be defaultProfile"
}

if ($settings.windowingBehavior -ne "useNew") {
    throw "windowingBehavior must be useNew"
}

$unsafeAction = @($settings.actions | Where-Object { $_.id -eq "User.DuplicateTabToNewWindow" })
if ($unsafeAction.Count -ne 0) {
    throw "Ctrl+Shift+N must not use duplicateTab plus moveTab"
}

$ctrlShiftN = @($settings.keybindings | Where-Object { $_.keys -eq "ctrl+shift+n" })
if ($ctrlShiftN.Count -ne 1 -or $ctrlShiftN[0].id -ne "Terminal.OpenNewWindow") {
    throw "Ctrl+Shift+N must use Terminal.OpenNewWindow as the safe fallback"
}

Write-Host "Windows Terminal settings: OK"
