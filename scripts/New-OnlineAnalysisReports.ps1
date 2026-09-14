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
$completeMarketDays = 0
$validDates = @{}
if (-not [string]::IsNullOrWhiteSpace($CategoryKey)) { $validDates[$ReportDate] = $true }
foreach ($candidate in @(Get-ChildItem -LiteralPath $SnapshotsRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and $_.Name -le $ReportDate } | Sort-Object Name)) {
    $candidateSnapshot = Join-Path $candidate.FullName 'amazon-bestsellers.json'
    $candidateReceipt = Join-Path $candidate.FullName 'best-sellers-capture-receipt.json'
    if (-not (Test-Path -LiteralPath $candidateSnapshot -PathType Leaf) -or -not (Test-Path -LiteralPath $candidateReceipt -PathType Leaf)) { continue }
    try {
        $candidateValidation = & (Join-Path $projectRoot 'scripts\Test-BestSellersCaptureReceipt.ps1') -ReceiptPath $candidateReceipt -RegistryPath $RegistryPath | ConvertFrom-Json
        if (-not $candidateValidation.valid) { continue }
        if (-not [string]::IsNullOrWhiteSpace($CategoryKey)) {
            $candidateAuthorized = Resolve-BestSellersAuthorizedSnapshot -SnapshotPath $candidateSnapshot -ReceiptPath $candidateReceipt -CategoryKey $CategoryKey -RegistryPath $RegistryPath
            if ([string]$candidateAuthorized.market_date -le $ReportDate) { $validDates[[string]$candidateAuthorized.market_date] = $true }
            continue
        }
        $candidateData = Get-Content -LiteralPath $candidateSnapshot -Raw -Encoding UTF8 | ConvertFrom-Json
        $probe = @(New-OnlineAnalysisReports -Snapshot $candidateData -ReceiptSha256 ([string]$candidateValidation.actual_snapshot_sha256) -ReportKind Daily -RegistryPath $RegistryPath)
        if ($probe[0].evidence.complete) { $completeMarketDays++ }
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
$reports = @(New-OnlineAnalysisReports -Snapshot $snapshot -ReceiptSha256 ([string]$receiptValidation.actual_snapshot_sha256) -ReportKind $ReportKind -PreviousSnapshot $previous -CompleteMarketDays $completeMarketDays -RegistryPath $RegistryPath -CategoryKey $CategoryKey)
$paths = @(Write-OnlineAnalysisReports -Reports $reports -OutputDirectory $OutputRoot)
[pscustomobject]@{ Status='CREATED'; ReportKind=$ReportKind.ToLowerInvariant(); MarketDate=$ReportDate; CompleteMarketDays=$completeMarketDays; ReportPaths=$paths; ReportCount=$paths.Count } | ConvertTo-Json -Depth 8
