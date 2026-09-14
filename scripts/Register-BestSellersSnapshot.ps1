param(
    [Parameter(Mandatory = $true)][string]$SnapshotPath,
    [string]$SourceConfigPath,
    [string]$OutputPath,
    [string]$RegistryPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($SourceConfigPath)) { $SourceConfigPath = Join-Path $projectRoot 'config\best-sellers-sources.json' }
if ([string]::IsNullOrWhiteSpace($RegistryPath)) { $RegistryPath = Join-Path $projectRoot 'config\category-registry.json' }
Import-Module (Join-Path $projectRoot 'src\BestSellersAnalysis.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersCaptureReceipt.psm1') -Force
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path (Split-Path -Parent (Resolve-Path -LiteralPath $SnapshotPath).Path) 'best-sellers-capture-receipt.json' }
$receipt = New-BestSellersCaptureReceipt -SnapshotPath $SnapshotPath -SourceConfigPath $SourceConfigPath -RegistryPath $RegistryPath
$path = Write-BestSellersCaptureReceipt -Receipt $receipt -Path $OutputPath
[pscustomobject]@{ Status = $receipt.status; MarketDate = $receipt.market_date; SourceMetadataVerified = $receipt.source_metadata_verified; SnapshotSha256 = $receipt.snapshot_sha256; ReceiptPath = $path } | ConvertTo-Json -Depth 6
