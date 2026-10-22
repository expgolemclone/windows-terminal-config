#requires -Version 7.0
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repositoryRoot 'src/terminal-configuration.psm1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('terminal-setup-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null

function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-Throws([scriptblock]$Action, [string]$MessagePattern) {
    $caught = $null
    try { & $Action } catch { $caught = $_ }
    Assert ($null -ne $caught) "Expected failure matching: $MessagePattern"
    Assert ($caught.Exception.Message -match $MessagePattern) "Unexpected failure: $caught"
}
function New-Fixture([string]$Name) {
    Import-Module $modulePath -Force
    $module = Get-Module terminal-configuration
    # Hermetic process mock; product code still checks the real process list.
    & $module { function script:Get-TerminalProcesses { return @() } }
    $root = Join-Path $testRoot $Name
    $repository = Join-Path $root 'repository'
    $configuration = Join-Path $repository 'config'
    $package = Join-Path $root 'package'
    New-Item -ItemType Directory -Path $configuration, $package | Out-Null
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'config/settings.json') -Destination $configuration
    Set-Content -LiteralPath (Join-Path $repository 'setup.ps1') -Value '# repository tooling'
    return @{ Repository = $repository; Configuration = $configuration; Local = Join-Path $package 'LocalState'; Package = $package; Module = $module }
}
function New-LiveDirectory($Fixture) {
    New-Item -ItemType Directory -Path $Fixture.Local | Out-Null
    Set-Content -LiteralPath (Join-Path $Fixture.Local 'settings.json') -Value '{"original":true}'
    $Fixture.RuntimeContents = @{
        'state.json' = 'runtime-state'
        'elevated-state.json' = 'elevated-runtime-state'
        'buffer_1.txt' = 'runtime-buffer'
    }
    $Fixture.RuntimeSecurity = @{}
    foreach ($name in $Fixture.RuntimeContents.Keys) {
        $path = Join-Path $Fixture.Local $name
        Set-Content -LiteralPath $path -Value $Fixture.RuntimeContents[$name]
        # A protected DACL makes inherited security changes visible without elevation.
        $acl = Get-Acl -LiteralPath $path
        $acl.SetAccessRuleProtection($true, $true)
        Set-Acl -LiteralPath $path -AclObject $acl
        $Fixture.RuntimeSecurity[$name] = (Get-Acl -LiteralPath $path).Sddl
    }
}
function Assert-RuntimeState($Fixture, [string]$Directory) {
    foreach ($name in $Fixture.RuntimeContents.Keys) {
        $path = Join-Path $Directory $name
        Assert ((Get-Content -LiteralPath $path -Raw).Trim() -eq $Fixture.RuntimeContents[$name]) "Runtime contents changed: $name"
        Assert ((Get-Acl -LiteralPath $path).Sddl -eq $Fixture.RuntimeSecurity[$name]) "Runtime owner or ACL changed: $name"
    }
}
function Connect($Fixture) {
    return Connect-TerminalConfiguration -ConfigurationDirectory $Fixture.Configuration -LocalState $Fixture.Local
}
try {
    Import-Module $modulePath -Force
    $module = Get-Module terminal-configuration
    & $module {
        function script:Get-Process {
            param($Name, $ErrorAction)
            if (@($Name).Count -ne 1 -or $Name -ne 'WindowsTerminal') {
                throw 'Only the Terminal frontend should block configuration changes.'
            }
            return [pscustomobject]@{ Id = 123 }
        }
        if (@(Get-TerminalProcesses).Count -ne 1) { throw 'Terminal frontend was not detected.' }
    }
    Write-Host 'Shutdown guard targets the configuration-owning frontend: OK'

    $f = New-Fixture 'regular directory'
    New-LiveDirectory $f
    Assert-Throws { Assert-TerminalInstallation $f.Configuration $f.Local } 'not connected'
    $result = Connect $f
    Assert $result.Changed 'Expected a connection change.'
    Assert ($result.ConfigurationDirectory -eq $f.Configuration) 'Setup returned the wrong configuration directory.'
    Assert ((Get-Item -LiteralPath $f.Local).Target -eq $f.Configuration) 'LocalState must target config, not the repository root.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $f.Local 'setup.ps1'))) 'Repository tooling is exposed through LocalState.'
    Assert (Test-Path -LiteralPath (Join-Path $result.BackupPath 'settings.json')) 'Original settings were not backed up.'
    Assert-RuntimeState $f $f.Configuration
    foreach ($name in $f.RuntimeContents.Keys) {
        Assert (-not (Test-Path -LiteralPath (Join-Path $result.BackupPath $name))) "Runtime file was copied instead of moved: $name"
        Assert (-not (Test-Path -LiteralPath (Join-Path $f.Repository $name))) "Runtime file leaked into the repository root: $name"
    }
    Set-Content -LiteralPath (Join-Path $f.Local 'buffer_2.txt') -Value 'new runtime buffer'
    Assert (Test-Path -LiteralPath (Join-Path $f.Configuration 'buffer_2.txt')) 'New runtime state must stay in config.'
    Assert-TerminalInstallation $f.Configuration $f.Local
    & $f.Module { function script:Get-TerminalProcesses { throw 'No-op must not inspect running processes.' } }
    $repeat = Connect-TerminalConfiguration $f.Configuration $f.Local -WaitForTerminalExit
    Assert (-not $repeat.Changed) 'Second setup must be a no-op.'
    Assert (@(Get-ChildItem -LiteralPath $f.Package -Directory -Filter 'LocalState.backup-*').Count -eq 1) 'No-op made another backup.'
    Write-Host 'Config isolation, runtime owner/ACL preservation, validation and running-Terminal no-op: OK'

    $f = New-Fixture 'missing LocalState'
    $result = Connect $f
    Assert ($result.Changed -and $null -eq $result.BackupPath) 'Missing LocalState should not need a backup.'
    Write-Host 'Initial connection without LocalState: OK'

    $f = New-Fixture 'preview'
    New-LiveDirectory $f
    Connect-TerminalConfiguration $f.Configuration $f.Local -WhatIf
    Assert ((Get-Item -LiteralPath $f.Local).LinkType -ne 'Junction') 'Preview changed LocalState.'
    Assert (@(Get-ChildItem -LiteralPath $f.Package -Directory -Filter 'LocalState.backup-*').Count -eq 0) 'Preview created backup.'
    Write-Host 'Preview is read-only: OK'

    $f = New-Fixture 'running Terminal'
    New-LiveDirectory $f
    & $f.Module { function script:Get-TerminalProcesses { return [pscustomobject]@{ Id = 1 } } }
    Assert-Throws { Connect $f } 'Close every Windows Terminal'
    Assert ((Get-Item -LiteralPath $f.Local).LinkType -ne 'Junction') 'Running-Terminal refusal changed LocalState.'
    Write-Host 'Running Terminal blocks mutation: OK'

    foreach ($target in @('other junction', 'repository root junction', 'broken junction')) {
        $f = New-Fixture $target
        $other = if ($target -eq 'repository root junction') { $f.Repository } else { Join-Path $f.Package 'other' }
        if (-not (Test-Path -LiteralPath $other)) { New-Item -ItemType Directory -Path $other | Out-Null }
        New-Item -ItemType Junction -Path $f.Local -Target $other | Out-Null
        if ($target -eq 'broken junction') { Remove-Item -LiteralPath $other }
        Assert-Throws { Assert-TerminalInstallation $f.Configuration $f.Local } 'not connected'
        Assert-Throws { Connect $f } 'not a regular directory'
        Assert ((Get-Item -LiteralPath $f.Local).Target -eq $other) 'Rejected junction was changed.'
        Remove-Item -LiteralPath $f.Local -Force
        Assert (Test-Path -LiteralPath (Join-Path $f.Repository 'setup.ps1')) 'Repository tooling was removed.'
        Write-Host "Rejected without replacement: $target"
    }

    $f = New-Fixture 'runtime collision'
    New-LiveDirectory $f
    Set-Content -LiteralPath (Join-Path $f.Configuration 'state.json') -Value 'existing-state'
    Assert-Throws { Connect $f } 'Runtime state already exists'
    Assert ((Get-Content -LiteralPath (Join-Path $f.Configuration 'state.json') -Raw).Trim() -eq 'existing-state') 'Collision destroyed existing state.'
    Write-Host 'Runtime collision preserves existing files: OK'

    foreach ($fault in @('partial migration', 'destination race', 'creation', 'verification')) {
        $f = New-Fixture "rollback $fault"
        New-LiveDirectory $f
        if ($fault -in @('partial migration', 'destination race')) {
            & $f.Module {
                param($Fault, $Configuration)
                $script:originalMove = ${function:Move-TerminalRuntimeFile}
                $script:moveFault = $Fault
                $script:moveConfiguration = $Configuration
                $script:forwardMoves = 0
                $script:raceDestination = $null
                function script:Move-TerminalRuntimeFile([string]$Source, [string]$Destination) {
                    if ((Split-Path -Parent $Destination) -eq $script:moveConfiguration) {
                        $script:forwardMoves++
                        if ($script:forwardMoves -eq 2) {
                            if ($script:moveFault -eq 'partial migration') { throw 'Injected runtime migration failure.' }
                            $script:raceDestination = $Destination
                            Set-Content -LiteralPath $Destination -Value 'concurrent-state'
                        }
                    }
                    & $script:originalMove $Source $Destination
                }
            } $fault $f.Configuration
        } elseif ($fault -eq 'creation') {
            & $f.Module { function script:New-Item { throw 'Injected junction creation failure.' } }
        } else {
            & $f.Module { function script:Assert-TerminalInstallation { throw 'Injected live verification failure.' } }
        }
        $pattern = if ($fault -eq 'destination race') { 'Cannot move runtime state' } else { 'Injected' }
        Assert-Throws { Connect $f } $pattern
        Assert ((Get-Item -LiteralPath $f.Local).LinkType -ne 'Junction') 'Rollback left a junction.'
        Assert ((Get-Content -LiteralPath (Join-Path $f.Local 'settings.json') -Raw).Trim() -eq '{"original":true}') 'Rollback did not restore original settings.'
        Assert-RuntimeState $f $f.Local
        $raceDestination = if ($fault -eq 'destination race') { & $f.Module { $script:raceDestination } } else { $null }
        foreach ($name in $f.RuntimeContents.Keys) {
            $destination = Join-Path $f.Configuration $name
            if ($destination -eq $raceDestination) {
                Assert ((Get-Content -LiteralPath $destination -Raw).Trim() -eq 'concurrent-state') 'Rollback destroyed a concurrently created destination.'
            } else {
                Assert (-not (Test-Path -LiteralPath $destination)) "Rollback left moved runtime state: $name"
            }
        }
        Write-Host "Rollback after $fault failure: OK"
    }

    $f = New-Fixture 'overlapping paths'
    Assert-Throws { Connect-TerminalConfiguration $f.Configuration (Join-Path $f.Configuration 'LocalState') } 'must not contain'
    Write-Host 'Overlapping source and destination are rejected: OK'

    foreach ($invalid in @('unknown-profile', 'hidden', 'elevated-defaults', 'elevated-profile', 'commandline', 'dynamic-source', 'hardcoded-commandline', 'system-powershell', 'missing-commandline', 'default-commandline', 'legacy-commandline', 'visible-legacy-profile', 'secondary-hardcoded-powershell', 'saved-layout', 'wrong-keybinding')) {
        $f = New-Fixture "invalid $invalid"
        $path = Join-Path $f.Configuration 'settings.json'
        $settings = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
        $profile = $settings.profiles.list | Where-Object guid -eq $settings.defaultProfile
        switch ($invalid) {
            'unknown-profile' { $settings.defaultProfile = '{00000000-0000-0000-0000-000000000000}' }
            'hidden' { $profile.hidden = $true }
            'elevated-defaults' { $settings.profiles.defaults.elevate = $true }
            'elevated-profile' { $profile.elevate = $true }
            'commandline' { $profile.commandline = 'pwsh.exe' }
            'dynamic-source' { $profile.source = 'Windows.Terminal.PowershellCore' }
            'hardcoded-commandline' { $profile.commandline = 'C:\hardcoded\pwsh.exe' }
            'system-powershell' { $profile.commandline = 'powershell.exe' }
            'missing-commandline' { $profile.Remove('commandline') | Out-Null }
            'default-commandline' { $settings.profiles.defaults.commandline = 'pwsh.exe' }
            'legacy-commandline' { ($settings.profiles.list | Where-Object name -eq 'Windows PowerShell').commandline = 'powershell.exe' }
            'visible-legacy-profile' { ($settings.profiles.list | Where-Object name -eq 'Windows PowerShell').hidden = $false }
            'secondary-hardcoded-powershell' { $settings.profiles.list += @{ guid = '{00000000-0000-0000-0000-000000000000}'; commandline = 'C:\hardcoded\pwsh.exe' } }
            'saved-layout' { $settings.firstWindowPreference = 'persistedWindowLayout' }
            'wrong-keybinding' { ($settings.keybindings | Where-Object keys -eq 'ctrl+c').id = 'Terminal.CopyToClipboard' }
        }
        $settings | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $path
        Assert-Throws { Connect $f } 'default profile|new windows|Unexpected binding|Windows PowerShell profile|Every explicit PowerShell'
    }
    Write-Host 'Invalid source settings block installation: OK'
    Write-Host 'Windows Terminal setup regression tests: OK'
} finally {
    # Remove links first; cleanup must never recurse through a junction.
    Get-ChildItem -LiteralPath $testRoot -Recurse -Directory -Force | Where-Object LinkType -eq 'Junction' |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
    Remove-Item -LiteralPath $testRoot -Recurse -Force
    Remove-Module terminal-configuration -ErrorAction SilentlyContinue
}
