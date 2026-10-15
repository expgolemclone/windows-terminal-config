#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess = $true)]
param([switch]$WaitForTerminalExit)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'TerminalConfiguration.psm1') -Force
$localState = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
$result = Connect-TerminalConfiguration -RepositoryRoot $PSScriptRoot -LocalState $localState -WaitForTerminalExit:$WaitForTerminalExit
if ($null -ne $result) {
    Write-Host "Windows Terminal live configuration verified: $($result.LocalState) -> $($result.RepositoryRoot)"
    if ($result.Changed) { Write-Host 'Connection created.' }
    else { Write-Host 'Already connected; no changes.' }
    if ($null -ne $result.BackupPath) { Write-Host "Previous LocalState backup: $($result.BackupPath)" }
}
