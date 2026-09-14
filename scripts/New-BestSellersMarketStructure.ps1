param(
    [Parameter(Mandatory = $true)][string]$SnapshotPath,
    [string]$OutputPath,
    [string]$RegistryPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) { $RegistryPath = Join-Path $projectRoot 'config\category-registry.json' }
Import-Module (Join-Path $projectRoot 'src\BestSellersAnalysis.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersMarketStructure.psm1') -Force
$snapshot = Read-BestSellersSnapshot -Path $SnapshotPath -RegistryPath $RegistryPath
$analysis = New-BestSellersMarketStructureAnalysis -Snapshot $snapshot -RegistryPath $RegistryPath
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $directory = Split-Path -Parent (Resolve-Path -LiteralPath $SnapshotPath).Path
    $OutputPath = Join-Path $directory 'best-sellers-market-structure.json'
}
$artifactPath = Write-BestSellersMarketStructureArtifact -Analysis $analysis -Path $OutputPath
[pscustomobject]@{
    Status = 'SUCCEEDED'
    MarketDate = $analysis.market_date
    CategoryCount = @($analysis.categories).Count
    AccessoryStatus = $analysis.accessory_analysis.status
    AccessoryItemCount = $analysis.accessory_analysis.item_count
    ArtifactPath = $artifactPath
} | ConvertTo-Json -Depth 5
