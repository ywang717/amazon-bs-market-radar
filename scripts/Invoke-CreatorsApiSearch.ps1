param(
    [Parameter(Mandatory = $true)][string]$SourceId,
    [Parameter(Mandatory = $true)][string]$MarketDate,
    [string]$ConfigPath,
    [string]$WorkRoot
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $PSScriptRoot '..\config\sources.json' }
if ([string]::IsNullOrWhiteSpace($WorkRoot)) { $WorkRoot = Join-Path $PSScriptRoot '..\var' }
Import-Module (Join-Path $PSScriptRoot '..\src\AmazonIntelligence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\CreatorsApiAdapter.psm1') -Force

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Source config not found: $ConfigPath. Copy config/sources.example.json to config/sources.json, review it, and explicitly activate only approved sources."
}
$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$source = @($config.sources | Where-Object { [string]$_.source_id -eq $SourceId }) | Select-Object -First 1
if ($null -eq $source) { throw "Unknown source_id: $SourceId" }

Invoke-CreatorsApiSearchRun -Source $source -MarketDate $MarketDate -WorkRoot $WorkRoot |
    ConvertTo-Json -Depth 10
