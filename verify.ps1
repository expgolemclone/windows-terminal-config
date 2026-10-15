#requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src/terminal-configuration.psm1') -Force
$configurationDirectory = Join-Path $PSScriptRoot 'config'
$localState = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
Assert-TerminalInstallation -ConfigurationDirectory $configurationDirectory -LocalState $localState
Write-Host "Windows Terminal live configuration: OK ($localState -> $configurationDirectory)"
