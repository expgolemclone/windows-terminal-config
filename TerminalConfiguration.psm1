#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-ConfigurationPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar)
}

function Assert-TerminalSettings {
    param([Parameter(Mandatory)][string]$SettingsPath)
    $settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $profiles = @($settings.profiles.list | Where-Object { $_.guid -eq $settings.defaultProfile })
    if ($profiles.Count -ne 1 -or $profiles[0].source -ne 'Windows.Terminal.PowershellCore' -or
        $profiles[0].hidden -ne $false -or $profiles[0]['elevate'] -eq $true -or
        $settings.profiles.defaults['elevate'] -eq $true -or $profiles[0].ContainsKey('commandline') -or
        $settings.profiles.defaults.ContainsKey('commandline')) {
        throw 'The default profile must be the visible, non-elevated PowerShell 7 dynamic profile without a commandline override.'
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
}

function Test-ConfigurationJunction([string]$LocalState, [string]$RepositoryRoot) {
    $item = Get-Item -LiteralPath $LocalState -Force -ErrorAction SilentlyContinue
    return $null -ne $item -and $item.LinkType -eq 'Junction' -and
        [string]::Equals((Resolve-ConfigurationPath ([string]$item.Target)),
            (Resolve-ConfigurationPath $RepositoryRoot), [StringComparison]::OrdinalIgnoreCase)
}

function Assert-TerminalInstallation {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$LocalState
    )
    if (-not (Test-ConfigurationJunction $LocalState $RepositoryRoot)) {
        throw "Windows Terminal LocalState is not connected to this repository: $LocalState -> $RepositoryRoot"
    }
    $source = Join-Path $RepositoryRoot 'settings.json'
    $live = Join-Path $LocalState 'settings.json'
    Assert-TerminalSettings $source
    Assert-TerminalSettings $live
    if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $live).Hash) {
        throw 'Live settings do not match the repository settings.'
    }
}

function Get-TerminalProcesses {
    # The frontend owns LocalState settings and buffers. OpenConsole is a console
    # host also used by background clients; it does not own Terminal configuration.
    return @(Get-Process -Name WindowsTerminal -ErrorAction SilentlyContinue)
}

function Connect-TerminalConfiguration {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$LocalState,
        [switch]$WaitForTerminalExit
    )
    $RepositoryRoot = Resolve-ConfigurationPath $RepositoryRoot
    $LocalState = Resolve-ConfigurationPath $LocalState
    $packageRoot = Split-Path -Parent $LocalState
    Assert-TerminalSettings (Join-Path $RepositoryRoot 'settings.json')
    if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) {
        throw "Windows Terminal package directory is missing: $packageRoot"
    }
    if ($RepositoryRoot -eq $LocalState -or
        $RepositoryRoot.StartsWith($LocalState + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        $LocalState.StartsWith($RepositoryRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Repository and LocalState paths must not contain one another.'
    }
    # A valid installation needs no process shutdown, even with -WaitForTerminalExit.
    if (Test-ConfigurationJunction $LocalState $RepositoryRoot) {
        Assert-TerminalInstallation $RepositoryRoot $LocalState
        return [pscustomobject]@{ Changed = $false; LocalState = $LocalState; RepositoryRoot = $RepositoryRoot; BackupPath = $null }
    }
    $existingItem = Get-Item -LiteralPath $LocalState -Force -ErrorAction SilentlyContinue
    if ($null -ne $existingItem -and (
        -not $existingItem.PSIsContainer -or
        ($existingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "LocalState is not a regular directory and cannot be replaced: $LocalState"
    }
    if (-not $PSCmdlet.ShouldProcess($LocalState, "Back up LocalState and connect it to $RepositoryRoot")) {
        return
    }
    if ($WaitForTerminalExit) {
        while (@(Get-TerminalProcesses).Count -ne 0) { Start-Sleep -Seconds 2 }
    }
    if (@(Get-TerminalProcesses).Count -ne 0) {
        throw 'Close every Windows Terminal window, then retry from an independent PowerShell or Console Host window.'
    }
    # Recheck after waiting: another setup may have completed while Terminal was open.
    if (Test-ConfigurationJunction $LocalState $RepositoryRoot) {
        Assert-TerminalInstallation $RepositoryRoot $LocalState
        return [pscustomobject]@{ Changed = $false; LocalState = $LocalState; RepositoryRoot = $RepositoryRoot; BackupPath = $null }
    }
    $existingItem = Get-Item -LiteralPath $LocalState -Force -ErrorAction SilentlyContinue
    if ($null -ne $existingItem -and (
        -not $existingItem.PSIsContainer -or
        ($existingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "LocalState changed while waiting and cannot be replaced: $LocalState"
    }
    $runtimeFiles = @()
    $backupPath = $null
    if ($null -ne $existingItem) {
        $runtimeFiles = @(Get-ChildItem -LiteralPath $LocalState -File -Force | Where-Object {
            $_.Name -in @('state.json', 'elevated-state.json') -or $_.Name -like 'buffer_*.txt'
        })
        foreach ($file in $runtimeFiles) {
            $destination = Join-Path $RepositoryRoot $file.Name
            if (Test-Path -LiteralPath $destination) { throw "Runtime state already exists: $destination" }
        }
        $backupName = 'LocalState.backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $backupPath = Join-Path $packageRoot $backupName
        if (Test-Path -LiteralPath $backupPath) { throw "Backup path already exists: $backupPath" }
    }
    $copiedFiles = [System.Collections.Generic.List[string]]::new()
    $renamed = $false
    try {
        if ($null -ne $existingItem) {
            Rename-Item -LiteralPath $LocalState -NewName $backupName
            $renamed = $true
            foreach ($file in $runtimeFiles) {
                $destination = Join-Path $RepositoryRoot $file.Name
                $copiedFiles.Add($destination)
                Copy-Item -LiteralPath (Join-Path $backupPath $file.Name) -Destination $destination
            }
        }
        New-Item -ItemType Junction -Path $LocalState -Target $RepositoryRoot | Out-Null
        Assert-TerminalInstallation $RepositoryRoot $LocalState
    }
    catch {
        if (Test-ConfigurationJunction $LocalState $RepositoryRoot) {
            Remove-Item -LiteralPath $LocalState -Force
        }
        foreach ($file in $copiedFiles) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
        if ($renamed -and -not (Test-Path -LiteralPath $LocalState)) {
            Rename-Item -LiteralPath $backupPath -NewName (Split-Path -Leaf $LocalState)
        }
        throw
    }
    return [pscustomobject]@{ Changed = $true; LocalState = $LocalState; RepositoryRoot = $RepositoryRoot; BackupPath = $backupPath }
}

Export-ModuleMember -Function Assert-TerminalSettings, Assert-TerminalInstallation, Connect-TerminalConfiguration
