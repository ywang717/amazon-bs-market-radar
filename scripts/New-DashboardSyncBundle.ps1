param(
    [Parameter(Mandatory=$true)][string]$SnapshotPath,
    [string]$OutputPath,
    [string]$CategoryKey,
    [string]$RegistryPath
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) { $RegistryPath = Join-Path $projectRoot 'config\category-registry.json' }
Import-Module (Join-Path $projectRoot 'src\DashboardSyncBundle.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersCaptureReceipt.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersCategoryRegistry.psm1') -Force
$registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
$snapshotFile = Get-Item -LiteralPath $SnapshotPath -ErrorAction Stop
$receiptPath = Join-Path $snapshotFile.DirectoryName 'best-sellers-capture-receipt.json'
if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { throw 'Verified capture receipt is required.' }
$authorizedSnapshot = Resolve-BestSellersAuthorizedSnapshot -SnapshotPath $snapshotFile.FullName -ReceiptPath $receiptPath -RegistryPath $RegistryPath -CategoryKey $CategoryKey
$snapshot = Get-Content -LiteralPath $authorizedSnapshot.snapshot_path -Raw -Encoding UTF8 | ConvertFrom-Json
$snapshot | Add-Member -NotePropertyName persisted_complete -NotePropertyValue $true -Force
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $fileName = if ([string]::IsNullOrWhiteSpace($CategoryKey)) { 'dashboard-sync-bundle.json' } else { 'dashboard-sync-bundle-' + $CategoryKey + '.json' }
    $OutputPath = Join-Path $snapshotFile.DirectoryName $fileName
}
$selectedKeys = if ([string]::IsNullOrWhiteSpace($CategoryKey)) { @(Get-BestSellersCategoryKeys -Registry $registry -EnabledOnly) } else { @($CategoryKey) }
$categories = foreach ($key in $selectedKeys) {
    $observations = @($snapshot.$key | ForEach-Object { ConvertTo-DashboardSyncObservation -Observation $_ })
    [ordered]@{ key=$key; sourceUrl=[string]$snapshot.sources.$key; observations=$observations }
}
$productMetadata = @(New-DashboardSyncProductMetadataCohort -Snapshot $snapshot -RegistryPath $RegistryPath)
if (-not [string]::IsNullOrWhiteSpace($CategoryKey)) {
    $selectedAsins = @($snapshot.$CategoryKey | ForEach-Object { [string]$_.asin })
    $productMetadata = @($productMetadata | Where-Object { $selectedAsins -ccontains [string]$_.asin })
}
$observedDate = [DateTimeOffset]::MinValue
$observedAt = if ([DateTimeOffset]::TryParse([string]$snapshot.observed_at, [ref]$observedDate)) {
    [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId($observedDate, 'Pacific Standard Time').ToString("yyyy-MM-dd'T'HH:mm:ss.fffzzz", [Globalization.CultureInfo]::InvariantCulture)
} else { [string]$snapshot.observed_at }
$bundle = [ordered]@{
    schemaVersion = 'amazon-bs-dashboard-bundle-v2'
    marketDate = [string]$snapshot.market_date
    observedAt = $observedAt
    receiptSha256 = [string]$authorizedSnapshot.snapshot_sha256
    categories = @($categories)
    productMetadata = $productMetadata
    reports = @()
}
[IO.File]::WriteAllText($OutputPath, ($bundle | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
[pscustomobject]@{ Status='CREATED'; MarketDate=$bundle.marketDate; ObservationCount=@($categories | ForEach-Object observations).Count; BundlePath=$OutputPath; ReceiptSha256=$bundle.receiptSha256 } | ConvertTo-Json
