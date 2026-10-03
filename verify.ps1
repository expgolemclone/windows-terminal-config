#requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'TerminalConfiguration.psm1') -Force
$localState = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
Assert-TerminalInstallation -RepositoryRoot $PSScriptRoot -LocalState $localState
Write-Host "Windows Terminal live configuration: OK ($localState -> $PSScriptRoot)"
