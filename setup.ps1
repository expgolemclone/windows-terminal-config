[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$WaitForTerminalExit
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
$packageRoot = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe'
$localState = Join-Path $packageRoot 'LocalState'
$settingsPath = Join-Path $repositoryRoot 'settings.json'

if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
    throw "Repository settings file is missing: $settingsPath"
}
Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -Depth 100 | Out-Null

if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) {
    throw "Windows Terminal stable package directory is missing: $packageRoot"
}
if ($repositoryRoot.StartsWith($localState + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The repository cannot be inside the LocalState directory.'
}

if ($WaitForTerminalExit -and -not $WhatIfPreference) {
    while (@(Get-Process -Name WindowsTerminal, OpenConsole -ErrorAction SilentlyContinue).Count -ne 0) {
        Start-Sleep -Seconds 2
    }
}

$existingItem = Get-Item -LiteralPath $localState -Force -ErrorAction SilentlyContinue
if ($null -ne $existingItem -and $existingItem.LinkType -eq 'Junction') {
    $target = [IO.Path]::GetFullPath([string]$existingItem.Target).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ([string]::Equals($target, $repositoryRoot, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "Windows Terminal LocalState is already connected: $localState"
        return
    }
}
if ($null -ne $existingItem -and (
        -not $existingItem.PSIsContainer -or
        ($existingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    )) {
    throw "LocalState is not a regular directory and cannot be replaced: $localState"
}

if (-not $PSCmdlet.ShouldProcess($localState, "Back up LocalState and connect it to $repositoryRoot")) {
    return
}

$runningTerminal = @(Get-Process -Name WindowsTerminal, OpenConsole -ErrorAction SilentlyContinue)
if ($runningTerminal.Count -ne 0) {
    throw 'Close every Windows Terminal window before running setup.ps1, then retry from an independent PowerShell or Console Host window.'
}

$runtimeFiles = @()
$backupPath = $null
if ($null -ne $existingItem) {
    $runtimeFiles = @(Get-ChildItem -LiteralPath $localState -File -Force | Where-Object {
            $_.Name -in @('state.json', 'elevated-state.json') -or $_.Name -like 'buffer_*.txt'
        })
    foreach ($file in $runtimeFiles) {
        $destination = Join-Path $repositoryRoot $file.Name
        if (Test-Path -LiteralPath $destination) {
            throw "Runtime state already exists in the repository: $destination"
        }
    }
    $backupName = 'LocalState.backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $backupPath = Join-Path $packageRoot $backupName
    if (Test-Path -LiteralPath $backupPath) {
        throw "Backup path already exists: $backupPath"
    }
}

$copiedFiles = [System.Collections.Generic.List[string]]::new()
try {
    if ($null -ne $existingItem) {
        Rename-Item -LiteralPath $localState -NewName $backupName
        foreach ($file in $runtimeFiles) {
            $destination = Join-Path $repositoryRoot $file.Name
            $copiedFiles.Add($destination)
            Copy-Item -LiteralPath (Join-Path $backupPath $file.Name) -Destination $destination
        }
    }
    New-Item -ItemType Junction -Path $localState -Target $repositoryRoot | Out-Null
}
catch {
    $failed = Get-Item -LiteralPath $localState -Force -ErrorAction SilentlyContinue
    if ($null -ne $failed -and $failed.LinkType -eq 'Junction' -and
        [string]::Equals([IO.Path]::GetFullPath([string]$failed.Target), $repositoryRoot, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $localState -Force
    }
    foreach ($file in $copiedFiles) {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }
    if ($null -ne $backupPath -and (Test-Path -LiteralPath $backupPath) -and -not (Test-Path -LiteralPath $localState)) {
        Rename-Item -LiteralPath $backupPath -NewName 'LocalState'
    }
    throw
}

Write-Host "Windows Terminal LocalState connected: $localState -> $repositoryRoot"
if ($null -ne $backupPath) {
    Write-Host "Previous LocalState backup: $backupPath"
}
