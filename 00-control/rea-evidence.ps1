$ErrorActionPreference = 'Stop'

Write-Host '--- REA artifact records ---'
& (Join-Path $PSScriptRoot 'rea-artifacts.ps1')
if ($LASTEXITCODE -ne 0) { throw "rea-artifacts.ps1 failed with exit $LASTEXITCODE" }

Write-Host '--- REA member bundles ---'
& (Join-Path $PSScriptRoot 'rea-members.ps1')
if ($LASTEXITCODE -ne 0) { throw "rea-members.ps1 failed with exit $LASTEXITCODE" }
