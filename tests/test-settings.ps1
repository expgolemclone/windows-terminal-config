#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repositoryRoot 'TerminalConfiguration.psm1') -Force
Assert-TerminalSettings -SettingsPath (Join-Path $repositoryRoot 'settings.json')
Write-Host 'Windows Terminal source settings: OK (not a live-installation check)'
