#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not ('TerminalConfiguration.NativeMethods' -as [type])) {
    Add-Type -Namespace TerminalConfiguration -Name NativeMethods -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", EntryPoint = "MoveFileExW", CharSet = System.Runtime.InteropServices.CharSet.Unicode, SetLastError = true)]
[return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
public static extern bool MoveFileEx(string source, string destination, uint flags);
'@
}

function Move-TerminalRuntimeFile([string]$Source, [string]$Destination) {
    # Rename the original file, retaining its owner, ACL and integrity label.
    # Neither overwrite nor cross-volume copying is allowed (flags = 0).
    if (-not [TerminalConfiguration.NativeMethods]::MoveFileEx($Source, $Destination, 0)) {
        throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error(),
            "Cannot move runtime state without changing its security: $Source -> $Destination")
    }
}

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

function Test-ConfigurationJunction([string]$LocalState, [string]$ConfigurationDirectory) {
    $item = Get-Item -LiteralPath $LocalState -Force -ErrorAction SilentlyContinue
    return $null -ne $item -and $item.LinkType -eq 'Junction' -and
        [string]::Equals((Resolve-ConfigurationPath ([string]$item.Target)),
            (Resolve-ConfigurationPath $ConfigurationDirectory), [StringComparison]::OrdinalIgnoreCase)
}

function Assert-TerminalInstallation {
    param(
        [Parameter(Mandatory)][string]$ConfigurationDirectory,
        [Parameter(Mandatory)][string]$LocalState
    )
    if (-not (Test-ConfigurationJunction $LocalState $ConfigurationDirectory)) {
        throw "Windows Terminal LocalState is not connected to this configuration directory: $LocalState -> $ConfigurationDirectory"
    }
    $source = Join-Path $ConfigurationDirectory 'settings.json'
    $live = Join-Path $LocalState 'settings.json'
    Assert-TerminalSettings $source
    Assert-TerminalSettings $live
    if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $live).Hash) {
        throw 'Live settings do not match the configuration settings.'
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
        [Parameter(Mandatory)][string]$ConfigurationDirectory,
        [Parameter(Mandatory)][string]$LocalState,
        [switch]$WaitForTerminalExit
    )
    $ConfigurationDirectory = Resolve-ConfigurationPath $ConfigurationDirectory
    $LocalState = Resolve-ConfigurationPath $LocalState
    $packageRoot = Split-Path -Parent $LocalState
    Assert-TerminalSettings (Join-Path $ConfigurationDirectory 'settings.json')
    if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) {
        throw "Windows Terminal package directory is missing: $packageRoot"
    }
    if ($ConfigurationDirectory -eq $LocalState -or
        $ConfigurationDirectory.StartsWith($LocalState + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        $LocalState.StartsWith($ConfigurationDirectory + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Configuration and LocalState paths must not contain one another.'
    }
    # A valid installation needs no process shutdown, even with -WaitForTerminalExit.
    if (Test-ConfigurationJunction $LocalState $ConfigurationDirectory) {
        Assert-TerminalInstallation $ConfigurationDirectory $LocalState
        return [pscustomobject]@{ Changed = $false; LocalState = $LocalState; ConfigurationDirectory = $ConfigurationDirectory; BackupPath = $null }
    }
    $existingItem = Get-Item -LiteralPath $LocalState -Force -ErrorAction SilentlyContinue
    if ($null -ne $existingItem -and (
        -not $existingItem.PSIsContainer -or
        ($existingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "LocalState is not a regular directory and cannot be replaced: $LocalState"
    }
    if (-not $PSCmdlet.ShouldProcess($LocalState, "Back up LocalState and connect it to $ConfigurationDirectory")) {
        return
    }
    if ($WaitForTerminalExit) {
        while (@(Get-TerminalProcesses).Count -ne 0) { Start-Sleep -Seconds 2 }
    }
    if (@(Get-TerminalProcesses).Count -ne 0) {
        throw 'Close every Windows Terminal window, then retry from an independent PowerShell or Console Host window.'
    }
    # Recheck after waiting: another setup may have completed while Terminal was open.
    if (Test-ConfigurationJunction $LocalState $ConfigurationDirectory) {
        Assert-TerminalInstallation $ConfigurationDirectory $LocalState
        return [pscustomobject]@{ Changed = $false; LocalState = $LocalState; ConfigurationDirectory = $ConfigurationDirectory; BackupPath = $null }
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
            $destination = Join-Path $ConfigurationDirectory $file.Name
            if (Test-Path -LiteralPath $destination) { throw "Runtime state already exists: $destination" }
        }
        $backupName = 'LocalState.backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $backupPath = Join-Path $packageRoot $backupName
        if (Test-Path -LiteralPath $backupPath) { throw "Backup path already exists: $backupPath" }
    }
    $movedFiles = [System.Collections.Generic.List[string]]::new()
    $renamed = $false
    try {
        if ($null -ne $existingItem) {
            Rename-Item -LiteralPath $LocalState -NewName $backupName
            $renamed = $true
            foreach ($file in $runtimeFiles) {
                $destination = Join-Path $ConfigurationDirectory $file.Name
                Move-TerminalRuntimeFile (Join-Path $backupPath $file.Name) $destination
                $movedFiles.Add($file.Name)
            }
        }
        New-Item -ItemType Junction -Path $LocalState -Target $ConfigurationDirectory | Out-Null
        Assert-TerminalInstallation $ConfigurationDirectory $LocalState
    }
    catch {
        if (Test-ConfigurationJunction $LocalState $ConfigurationDirectory) {
            Remove-Item -LiteralPath $LocalState -Force
        }
        foreach ($name in $movedFiles) {
            Move-TerminalRuntimeFile (Join-Path $ConfigurationDirectory $name) (Join-Path $backupPath $name)
        }
        if ($renamed -and -not (Test-Path -LiteralPath $LocalState)) {
            Rename-Item -LiteralPath $backupPath -NewName (Split-Path -Leaf $LocalState)
        }
        throw
    }
    return [pscustomobject]@{ Changed = $true; LocalState = $LocalState; ConfigurationDirectory = $ConfigurationDirectory; BackupPath = $backupPath }
}

Export-ModuleMember -Function Assert-TerminalSettings, Assert-TerminalInstallation, Connect-TerminalConfiguration
