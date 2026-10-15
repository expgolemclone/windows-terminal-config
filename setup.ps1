#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess = $true)]
param([switch]$WaitForTerminalExit)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src/terminal-configuration.psm1') -Force
$configurationDirectory = Join-Path $PSScriptRoot 'config'
$localState = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
$result = Connect-TerminalConfiguration -ConfigurationDirectory $configurationDirectory -LocalState $localState -WaitForTerminalExit:$WaitForTerminalExit
if ($null -ne $result) {
    Write-Host "Windows Terminal live configuration verified: $($result.LocalState) -> $($result.ConfigurationDirectory)"
    if ($result.Changed) { Write-Host 'Connection created.' }
    else { Write-Host 'Already connected; no changes.' }
    if ($null -ne $result.BackupPath) { Write-Host "Previous LocalState backup: $($result.BackupPath)" }
}
