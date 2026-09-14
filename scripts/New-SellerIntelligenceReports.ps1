param(
    [Parameter(Mandatory = $true)][string]$SnapshotPath,
    [string]$SnapshotsRoot,
    [string]$PreviousSnapshotPath,
    [ValidateSet('Daily','Weekly')][string]$ReportKind = 'Daily',
    [string]$ReportDate,
    [string]$OutputRoot,
    [string]$CategoryKey,
    [string]$RegistryPath
)

$ErrorActionPreference = 'Stop'
$requestedCategoryKey = $CategoryKey
if (-not [string]::IsNullOrWhiteSpace($requestedCategoryKey) -and $ReportKind -ne 'Daily') { throw 'Category-scoped reports require Daily kind.' }
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) { $RegistryPath = Join-Path $projectRoot 'config\category-registry.json' }
if ([string]::IsNullOrWhiteSpace($SnapshotsRoot)) { $SnapshotsRoot = Join-Path $projectRoot 'var\amazon-bestsellers' }
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $projectRoot 'var\seller-intelligence-reports' }
if (-not (Test-Path -LiteralPath $SnapshotPath -PathType Leaf)) { throw 'Seller intelligence reports require a readable snapshot.' }
Import-Module (Join-Path $projectRoot 'src\BestSellersCaptureReceipt.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\SellerIntelligence.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersDataSemantics.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersCategoryRegistry.psm1') -Force
$registry = Import-BestSellersCategoryRegistry -Path $RegistryPath

$receiptPath = Join-Path (Split-Path -Parent $SnapshotPath) 'best-sellers-capture-receipt.json'
$authorizedSnapshot = Resolve-BestSellersAuthorizedSnapshot -SnapshotPath $SnapshotPath -ReceiptPath $receiptPath -RegistryPath $RegistryPath -CategoryKey $requestedCategoryKey

$snapshot = Get-Content -LiteralPath $authorizedSnapshot.snapshot_path -Raw -Encoding UTF8 | ConvertFrom-Json
$snapshot = $snapshot | Select-Object *
$snapshot | Add-Member -NotePropertyName persisted_complete -NotePropertyValue $true -Force
if ([string]::IsNullOrWhiteSpace($ReportDate)) { $ReportDate = [string]$authorizedSnapshot.market_date }
if ($ReportDate -notmatch '^\d{4}-\d{2}-\d{2}$') { throw 'ReportDate must use YYYY-MM-DD.' }
if ([string]$authorizedSnapshot.market_date -ne $ReportDate) { throw 'ReportDate must match the verified snapshot market_date.' }

$historySnapshots = New-Object System.Collections.Generic.List[object]
foreach ($candidate in @(Get-ChildItem -LiteralPath $SnapshotsRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and $_.Name -le $ReportDate } | Sort-Object Name)) {
    $candidateSnapshot = Join-Path $candidate.FullName 'amazon-bestsellers.json'
    $candidateReceipt = Join-Path $candidate.FullName 'best-sellers-capture-receipt.json'
    if (-not (Test-Path -LiteralPath $candidateSnapshot -PathType Leaf) -or -not (Test-Path -LiteralPath $candidateReceipt -PathType Leaf)) { continue }
    try {
        $candidateAuthorization = Resolve-BestSellersAuthorizedSnapshot -SnapshotPath $candidateSnapshot -ReceiptPath $candidateReceipt -RegistryPath $RegistryPath -CategoryKey $requestedCategoryKey
        if ([string]$candidateAuthorization.market_date -gt $ReportDate) { continue }
        $candidateData = Get-Content -LiteralPath $candidateAuthorization.snapshot_path -Raw -Encoding UTF8 | ConvertFrom-Json
        $candidateData = $candidateData | Select-Object *
        $candidateData | Add-Member -NotePropertyName persisted_complete -NotePropertyValue $true -Force
        $historySnapshots.Add($candidateData)
    }
    catch { continue }
}

if (-not [string]::IsNullOrWhiteSpace($PreviousSnapshotPath)) {
    if (-not (Test-Path -LiteralPath $PreviousSnapshotPath -PathType Leaf)) {
        throw 'Previous seller intelligence snapshot requires a readable snapshot.'
    }
    $previousReceiptPath = Join-Path (Split-Path -Parent $PreviousSnapshotPath) 'best-sellers-capture-receipt.json'
    try {
        $previousAuthorization = Resolve-BestSellersAuthorizedSnapshot -SnapshotPath $PreviousSnapshotPath -ReceiptPath $previousReceiptPath -RegistryPath $RegistryPath -CategoryKey $requestedCategoryKey
    }
    catch { throw 'Previous seller intelligence snapshot requires an authorized COMPLETE_VALIDATED capture receipt.' }
    $explicitPrevious = Get-Content -LiteralPath $previousAuthorization.snapshot_path -Raw -Encoding UTF8 | ConvertFrom-Json
    $explicitPrevious = $explicitPrevious | Select-Object *
    $explicitPrevious | Add-Member -NotePropertyName persisted_complete -NotePropertyValue $true -Force
    $historySnapshots.Add($explicitPrevious)
}

$categoryKeys = @(Get-BestSellersCategoryKeys -Registry $registry -EnabledOnly)
$historySnapshots.Add($snapshot)
$history = @($historySnapshots.ToArray() |
    Group-Object { [string]$_.market_date } |
    ForEach-Object { if ([string]::IsNullOrWhiteSpace($requestedCategoryKey)) { $_.Group | Select-Object -First 1 } else { $_.Group | Select-Object -Last 1 } } |
    Sort-Object { [string]$_.market_date })
$overviewHistory = @(BestSellersDataSemantics\Get-BestSellersValidHistory -Snapshots $history -CategoryKeys $categoryKeys -RegistryPath $RegistryPath)
$overviewCompleteMarketDays = $overviewHistory.Count
$previous = BestSellersDataSemantics\Get-BestSellersPreviousValidSnapshot -Snapshots $history -CategoryKeys $categoryKeys -CurrentMarketDate $ReportDate -RegistryPath $RegistryPath
$categoryCompleteMarketDays = @{}
$previousSnapshotsByCategory = @{}
$categoryHistorySnapshots = @{}
foreach ($categoryKey in $categoryKeys) {
    $validCategoryHistory = @(BestSellersDataSemantics\Get-BestSellersValidHistory -Snapshots $history -CategoryKeys @($categoryKey) -RegistryPath $RegistryPath)
    $categoryCompleteMarketDays[$categoryKey] = $validCategoryHistory.Count
    $categoryHistorySnapshots[$categoryKey] = $validCategoryHistory
    $previousSnapshotsByCategory[$categoryKey] = BestSellersDataSemantics\Get-BestSellersPreviousValidSnapshot -Snapshots $history -CategoryKeys @($categoryKey) -CurrentMarketDate $ReportDate -RegistryPath $RegistryPath
}

$profile = if ($ReportKind -eq 'Daily') { 'SellerAlert' } else { 'CompetitionStrategy' }
$reports = @(SellerIntelligence\New-SellerIntelligenceReports -Snapshot $snapshot -ReceiptSha256 ([string]$authorizedSnapshot.verification.actual_snapshot_sha256) -Profile $profile -PreviousSnapshot $previous -PreviousSnapshotsByCategory $previousSnapshotsByCategory -HistorySnapshots $overviewHistory -CategoryHistorySnapshots $categoryHistorySnapshots -CompleteMarketDays $overviewCompleteMarketDays -CategoryCompleteMarketDays $categoryCompleteMarketDays -RegistryPath $RegistryPath)
if (-not [string]::IsNullOrWhiteSpace($requestedCategoryKey)) {
    $reports = @($reports | Where-Object { $_.categoryKey -ceq $requestedCategoryKey })
    if ($reports.Count -ne 1 -or -not $reports[0].evidence.complete) { throw 'Category-scoped reports require one complete market report.' }
}
$paths = @(SellerIntelligence\Write-SellerIntelligenceReports -Reports $reports -OutputDirectory $OutputRoot)

[pscustomobject]@{
    Status = 'CREATED'
    ReportKind = $ReportKind.ToLowerInvariant()
    MarketDate = $ReportDate
    CompleteMarketDays = $overviewCompleteMarketDays
    CategoryCompleteMarketDays = $categoryCompleteMarketDays
    ReportPaths = $paths
    ReportCount = $paths.Count
} | ConvertTo-Json -Depth 8
