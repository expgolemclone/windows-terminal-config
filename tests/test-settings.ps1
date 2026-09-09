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

$actionId = "User.DuplicateTabToNewWindow"
$action = @($settings.actions | Where-Object { $_.id -eq $actionId })
if ($action.Count -ne 1) {
    throw "Exactly one $actionId action must exist"
}

if ($action[0].command.action -ne "multipleActions") {
    throw "$actionId must use multipleActions"
}

$steps = @($action[0].command.actions)
if ($steps.Count -ne 2 -or $steps[0] -ne "duplicateTab") {
    throw "$actionId must duplicate the active tab first"
}

if ($steps[1].action -ne "moveTab" -or $steps[1].window -ne "new") {
    throw "$actionId must move the duplicated tab to a new window"
}

$ctrlShiftN = @($settings.keybindings | Where-Object { $_.keys -eq "ctrl+shift+n" })
if ($ctrlShiftN.Count -ne 1 -or $ctrlShiftN[0].id -ne $actionId) {
    throw "Ctrl+Shift+N must invoke $actionId"
}

Write-Host "Windows Terminal settings: OK"
