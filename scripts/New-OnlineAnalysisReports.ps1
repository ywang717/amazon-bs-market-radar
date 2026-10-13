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
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) { $RegistryPath = Join-Path $projectRoot 'config\category-registry.json' }
if ([string]::IsNullOrWhiteSpace($SnapshotsRoot)) { $SnapshotsRoot = Join-Path $projectRoot 'var\amazon-bestsellers' }
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $projectRoot 'var\online-analysis-reports' }
if (-not (Test-Path -LiteralPath $SnapshotPath -PathType Leaf)) { throw 'Analysis reports require a readable snapshot.' }
$receiptPath = Join-Path (Split-Path -Parent $SnapshotPath) 'best-sellers-capture-receipt.json'
if (-not [string]::IsNullOrWhiteSpace($CategoryKey)) {
    if ($ReportKind -ne 'Daily') { throw 'Category-scoped reports require Daily kind.' }
    Import-Module (Join-Path $projectRoot 'src\BestSellersCaptureReceipt.psm1') -Force
    $authorized = Resolve-BestSellersAuthorizedSnapshot -SnapshotPath $SnapshotPath -ReceiptPath $receiptPath -CategoryKey $CategoryKey -RegistryPath $RegistryPath
    if (-not [string]::IsNullOrWhiteSpace($ReportDate) -and $ReportDate -ne [string]$authorized.market_date) { throw 'ReportDate must match the verified market date.' }
}
$receiptValidation = & (Join-Path $projectRoot 'scripts\Test-BestSellersCaptureReceipt.ps1') -ReceiptPath $receiptPath -RegistryPath $RegistryPath | ConvertFrom-Json
if (-not $receiptValidation.valid) { throw 'Analysis reports require a valid capture receipt.' }
$snapshot = Get-Content -LiteralPath $SnapshotPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($ReportDate)) { $ReportDate = [string]$snapshot.market_date }
if ($ReportDate -notmatch '^\d{4}-\d{2}-\d{2}$') { throw 'ReportDate must use YYYY-MM-DD.' }
if ([string]$snapshot.market_date -ne $ReportDate) {
    $snapshot = $snapshot | Select-Object *
    $snapshot | Add-Member -NotePropertyName market_date -NotePropertyValue $ReportDate -Force
}

$previous = $null
if (-not [string]::IsNullOrWhiteSpace($PreviousSnapshotPath) -and (Test-Path -LiteralPath $PreviousSnapshotPath -PathType Leaf)) {
    $previous = Get-Content -LiteralPath $PreviousSnapshotPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

Import-Module (Join-Path $projectRoot 'src\OnlineAnalysisReport.psm1') -Force
Import-Module (Join-Path $projectRoot 'src/BestSellersDataSemantics.psm1') -Force
Import-Module (Join-Path $projectRoot 'src/BestSellersCategoryRegistry.psm1') -Force
$historyRegistry = Import-BestSellersCategoryRegistry -Path $RegistryPath
$historyCategories = @($historyRegistry.Categories | Where-Object Enabled)
$categoryCompleteMarketDays = @{}
foreach ($category in $historyCategories) { $categoryCompleteMarketDays[$category.CategoryKey] = 0 }
$completeMarketDays = 0
$validDates = @{}
if (-not [string]::IsNullOrWhiteSpace($CategoryKey)) { $validDates[$ReportDate] = $true }
foreach ($candidate in @(Get-ChildItem -LiteralPath $SnapshotsRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and $_.Name -le $ReportDate } | Sort-Object Name)) {
    $candidateSnapshot = Join-Path $candidate.FullName 'amazon-bestsellers.json'
    $candidateReceipt = Join-Path $candidate.FullName 'best-sellers-capture-receipt.json'
    if (-not (Test-Path -LiteralPath $candidateSnapshot -PathType Leaf) -or -not (Test-Path -LiteralPath $candidateReceipt -PathType Leaf)) { continue }
    try {
        $candidateReceiptData = Get-Content -LiteralPath $candidateReceipt -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$candidateReceiptData.status -ne 'COMPLETE_VALIDATED' -or $candidateReceiptData.source_metadata_verified -ne $true -or [string]$candidateReceiptData.market_date -ne $candidate.Name) { continue }
        if ((Get-FileHash -LiteralPath $candidateSnapshot -Algorithm SHA256).Hash.ToLowerInvariant() -ne [string]$candidateReceiptData.snapshot_sha256) { continue }
        $candidateData = Get-Content -LiteralPath $candidateSnapshot -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$candidateData.market_date -ne $candidate.Name) { continue }
        $completeCategories = 0
        foreach ($category in $historyCategories) {
            $property = $candidateData.PSObject.Properties[$category.CategoryKey]
            if ($null -ne $property -and (Test-BestSellersExactTop30 -Items @($property.Value) -TargetCount $category.TargetCount)) {
                $categoryCompleteMarketDays[$category.CategoryKey]++
                $completeCategories++
                if ($category.CategoryKey -eq $CategoryKey) { $validDates[$candidate.Name] = $true }
            }
        }
        if ($completeCategories -eq $historyCategories.Count) { $completeMarketDays++ }
    }
    catch { continue }
}
if (-not [string]::IsNullOrWhiteSpace($CategoryKey)) {
    $completeMarketDays = $validDates.Count
    if ($null -ne $previous) {
        $previousReceipt = Join-Path (Split-Path -Parent $PreviousSnapshotPath) 'best-sellers-capture-receipt.json'
        $previousAuthorized = Resolve-BestSellersAuthorizedSnapshot -SnapshotPath $PreviousSnapshotPath -ReceiptPath $previousReceipt -CategoryKey $CategoryKey -RegistryPath $RegistryPath
        if ([string]$previousAuthorized.market_date -ge $ReportDate) { throw 'Previous market date must precede the current date.' }
    }
}
$reports = @(New-OnlineAnalysisReports -Snapshot $snapshot -ReceiptSha256 ([string]$receiptValidation.actual_snapshot_sha256) -ReportKind $ReportKind -PreviousSnapshot $previous -CompleteMarketDays $completeMarketDays -CategoryCompleteMarketDays $(if ($ReportKind -eq 'Weekly') { $categoryCompleteMarketDays } else { $null }) -RegistryPath $RegistryPath -CategoryKey $CategoryKey)
$paths = @(Write-OnlineAnalysisReports -Reports $reports -OutputDirectory $OutputRoot)
[pscustomobject]@{ Status='CREATED'; ReportKind=$ReportKind.ToLowerInvariant(); MarketDate=$ReportDate; CompleteMarketDays=$completeMarketDays; ReportPaths=$paths; ReportCount=$paths.Count } | ConvertTo-Json -Depth 8
