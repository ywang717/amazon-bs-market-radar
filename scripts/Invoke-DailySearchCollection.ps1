param(
    [Parameter(Mandatory = $true)][string]$MarketDate,
    [string]$ConfigPath,
    [string]$WorkRoot
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $PSScriptRoot '..\config\sources.json' }
if ([string]::IsNullOrWhiteSpace($WorkRoot)) { $WorkRoot = Join-Path $PSScriptRoot '..\var' }
Import-Module (Join-Path $PSScriptRoot '..\src\AmazonIntelligence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\CreatorsApiAdapter.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\DailyCollection.psm1') -Force

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "Source config not found: $ConfigPath" }
$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
Invoke-DailySearchCollection -Config $config -MarketDate $MarketDate -WorkRoot $WorkRoot |
    ConvertTo-Json -Depth 12

