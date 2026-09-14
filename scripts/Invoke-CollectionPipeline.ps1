param(
    [Parameter(Mandatory = $true)][string]$FixturePath,
    [string]$WorkRoot
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($WorkRoot)) { $WorkRoot = Join-Path $PSScriptRoot '..\var' }
Import-Module (Join-Path $PSScriptRoot '..\src\AmazonIntelligence.psm1') -Force

Invoke-CollectionPipeline -FixturePath $FixturePath -WorkRoot $WorkRoot |
    ConvertTo-Json -Depth 10
