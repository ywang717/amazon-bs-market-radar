param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot,
    [string]$SnapshotsRoot,
    [string]$MarketDate = ([datetime]::UtcNow.ToString('yyyy-MM-dd')),
    [string[]]$RequestedAsins,
    [ValidateRange(0, [int]::MaxValue)][int]$MaxProducts = 0,
    [ValidateSet('true','false')][string]$Headless = 'true',
    [switch]$SkipDashboard,
    [uri]$DashboardUrl,
    [scriptblock]$DiscoveryAction,
    [scriptblock]$CollectAction,
    [scriptblock]$MetadataAction,
    [scriptblock]$PostgresAction,
    [scriptblock]$PublishAction
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $ProjectRoot 'src\BestSellersBrandEnrichment.psm1') -Force
Import-Module (Join-Path $ProjectRoot 'src\BestSellersDataSemantics.psm1') -Force
Import-Module (Join-Path $ProjectRoot 'src\BestSellersCaptureReceipt.psm1') -Force
Import-Module (Join-Path $ProjectRoot 'src\BestSellersPostgres.psm1') -Force

function Write-BrandBackfillJsonAtomic {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Value)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $directory = [IO.Path]::GetDirectoryName($fullPath)
    if (-not [IO.Directory]::Exists($directory)) { [IO.Directory]::CreateDirectory($directory) | Out-Null }
    $temporaryPath = Join-Path $directory ('.{0}.{1}.tmp' -f [IO.Path]::GetFileName($fullPath), [guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($fullPath)) { [IO.File]::Replace($temporaryPath, $fullPath, $null) }
        else { [IO.File]::Move($temporaryPath, $fullPath) }
    }
    finally {
        if ([IO.File]::Exists($temporaryPath)) { [IO.File]::Delete($temporaryPath) }
    }
}

function ConvertTo-BackfillCanonicalAsins {
    param([Parameter(Mandatory = $true)][string[]]$Asins)
    $unique = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($value in @($Asins)) {
        $asin = ([string]$value).Trim().ToUpperInvariant()
        if ($asin -notmatch '^[A-Z0-9]{10}$') { throw "Invalid ASIN: $value" }
        [void]$unique.Add($asin)
    }
    $result = [string[]]@($unique)
    [Array]::Sort($result, [StringComparer]::Ordinal)
    return $result
}

function Get-BrandBackfillMetadataRows {
    param([Parameter(Mandatory = $true)][string]$HistoryRoot, [Parameter(Mandatory = $true)][string[]]$Asins)
    $snapshots = New-Object 'System.Collections.Generic.List[object]'
    foreach ($file in @(Get-ChildItem -LiteralPath $HistoryRoot -Filter 'amazon-bestsellers.json' -File -Recurse | Sort-Object FullName)) {
        $authorized = Resolve-BestSellersAuthorizedSnapshot -SnapshotPath $file.FullName -ReceiptPath (Join-Path $file.DirectoryName 'best-sellers-capture-receipt.json')
        $snapshot = Get-Content -LiteralPath $authorized.snapshot_path -Raw -Encoding UTF8 | ConvertFrom-Json
        $snapshot | Add-Member -NotePropertyName persisted_complete -NotePropertyValue $true -Force
        $snapshots.Add($snapshot)
    }
    $allRows = @(New-BestSellersProductMetadataRows -Snapshots $snapshots.ToArray() -MarketplaceCode AMAZON_US -ClassificationConfigPath (Join-Path $ProjectRoot 'config\v2-product-classification.json') -BrandAliasConfigPath (Join-Path $ProjectRoot 'config\v2-brand-aliases.json'))
    $allowed = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($asin in $Asins) { [void]$allowed.Add($asin) }
    return @($allRows | Where-Object { $allowed.Contains(([string]$_.asin).ToUpperInvariant()) })
}

if ([string]::IsNullOrWhiteSpace($SnapshotsRoot)) { $SnapshotsRoot = Join-Path $ProjectRoot 'var\amazon-bestsellers' }
$verifiedAsins = if ($null -ne $DiscoveryAction) { @(ConvertTo-BackfillCanonicalAsins -Asins @(& $DiscoveryAction $SnapshotsRoot)) } else { @(Get-BestSellersVerifiedHistoryAsins -SnapshotsRoot $SnapshotsRoot) }
$asins = @($verifiedAsins)
if ($null -ne $RequestedAsins -and @($RequestedAsins).Count -gt 0) {
    $requested = @(ConvertTo-BackfillCanonicalAsins -Asins $RequestedAsins)
    $verifiedSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($asin in $verifiedAsins) { [void]$verifiedSet.Add($asin) }
    $unverified = @($requested | Where-Object { -not $verifiedSet.Contains($_) })
    if ($unverified.Count -gt 0) { throw "Requested ASINs are not in the receipt-verified historical cohort: $($unverified -join ', ')" }
    $asins = $requested
}
if ($MaxProducts -gt 0) { $asins = @($asins | Select-Object -First $MaxProducts) }
if ($asins.Count -eq 0) { throw 'No verified historical ASINs are available for backfill.' }

if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = $ProjectRoot }
$outputDirectory = Join-Path (Join-Path $OutputRoot 'var\brand-enrichment') $MarketDate
$artifactPath = Join-Path $outputDirectory 'amazon-brand-enrichment.json'
$receiptPath = Join-Path $outputDirectory 'amazon-brand-enrichment-receipt.json'
$artifactVerification = $null
$collectOrReuseProducts = 0

$artifactExists = Test-Path -LiteralPath $artifactPath -PathType Leaf
$receiptExists = Test-Path -LiteralPath $receiptPath -PathType Leaf
if ($receiptExists -and -not $artifactExists) { throw 'Existing brand enrichment receipt has no artifact and cannot be reused.' }

if ($artifactExists -and $receiptExists) {
    $artifactVerification = Test-BestSellersBrandEnrichmentArtifact -ArtifactPath $artifactPath -RequestedAsins $asins
    $receiptVerification = Test-BestSellersBrandEnrichmentReceipt -ReceiptPath $receiptPath -ArtifactPath $artifactPath -RequestedAsins $asins
    if (-not $artifactVerification.valid -or -not $receiptVerification.valid) { throw 'Existing backfill output does not validate for the requested ASIN set.' }
    $collectOrReuseProducts = @($artifactVerification.products).Count
}
elseif ($artifactExists) {
    $artifactVerification = Test-BestSellersBrandEnrichmentArtifact -ArtifactPath $artifactPath -RequestedAsins $asins
    if (-not $artifactVerification.valid) { throw 'Existing artifact-only backfill output does not validate for the requested ASIN set.' }
    $receipt = New-BestSellersBrandEnrichmentReceipt -ArtifactPath $artifactPath -RequestedAsins $asins
    Write-BrandBackfillJsonAtomic -Path $receiptPath -Value $receipt
    $receiptVerification = Test-BestSellersBrandEnrichmentReceipt -ReceiptPath $receiptPath -ArtifactPath $artifactPath -RequestedAsins $asins
    if (-not $receiptVerification.valid) { throw "Recovered brand enrichment receipt validation failed: $($receiptVerification.errors -join '; ')" }
    $collectOrReuseProducts = @($artifactVerification.products).Count
}
else {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    $stagingDirectory = Join-Path $outputDirectory ('.brand-backfill-{0}' -f [guid]::NewGuid().ToString('N'))
    $stagedArtifactPath = Join-Path $stagingDirectory 'amazon-brand-enrichment.json'
    $stagedReceiptPath = Join-Path $stagingDirectory 'amazon-brand-enrichment-receipt.json'
    [IO.Directory]::CreateDirectory($stagingDirectory) | Out-Null
    try {
        if ($null -ne $CollectAction) {
            & $CollectAction $stagedArtifactPath $asins $Headless
        }
        else {
            $requestPath = Join-Path $stagingDirectory 'requested-asins.json'
            Write-BrandBackfillJsonAtomic -Path $requestPath -Value $asins
            & (Join-Path $ProjectRoot '.venv\Scripts\python.exe') (Join-Path $ProjectRoot 'scripts\python\collect_brand_enrichment.py') --asins-json $requestPath --output $stagedArtifactPath --marketplace AMAZON_US --headless $Headless
            if ($LASTEXITCODE -ne 0) { throw 'Brand enrichment collection failed.' }
        }
        $stagedArtifactVerification = Test-BestSellersBrandEnrichmentArtifact -ArtifactPath $stagedArtifactPath -RequestedAsins $asins
        if (-not $stagedArtifactVerification.valid) { throw "Brand enrichment artifact validation failed: $($stagedArtifactVerification.errors -join '; ')" }
        $receipt = New-BestSellersBrandEnrichmentReceipt -ArtifactPath $stagedArtifactPath -RequestedAsins $asins
        Write-BrandBackfillJsonAtomic -Path $stagedReceiptPath -Value $receipt
        $stagedReceiptVerification = Test-BestSellersBrandEnrichmentReceipt -ReceiptPath $stagedReceiptPath -ArtifactPath $stagedArtifactPath -RequestedAsins $asins
        if (-not $stagedReceiptVerification.valid) { throw "Brand enrichment receipt validation failed: $($stagedReceiptVerification.errors -join '; ')" }
        if ((Test-Path -LiteralPath $artifactPath) -or (Test-Path -LiteralPath $receiptPath)) { throw 'Brand enrichment output appeared while the staged pair was being validated.' }
        [IO.File]::Move($stagedArtifactPath, $artifactPath)
        [IO.File]::Move($stagedReceiptPath, $receiptPath)
        $artifactVerification = Test-BestSellersBrandEnrichmentArtifact -ArtifactPath $artifactPath -RequestedAsins $asins
        $receiptVerification = Test-BestSellersBrandEnrichmentReceipt -ReceiptPath $receiptPath -ArtifactPath $artifactPath -RequestedAsins $asins
        if (-not $artifactVerification.valid -or -not $receiptVerification.valid) { throw 'Promoted backfill output failed final validation.' }
        $collectOrReuseProducts = @($artifactVerification.products).Count
    }
    finally {
        if ([IO.Directory]::Exists($stagingDirectory)) { [IO.Directory]::Delete($stagingDirectory, $true) }
    }
}

$metadataRows = if ($null -ne $MetadataAction) { @(& $MetadataAction $asins) } else { @(Get-BrandBackfillMetadataRows -HistoryRoot $SnapshotsRoot -Asins $asins) }
$mergedRows = @(Merge-BestSellersBrandEnrichmentMetadata -MetadataRows $metadataRows -Artifact $artifactVerification.artifact -BrandAliasConfigPath (Join-Path $ProjectRoot 'config\v2-brand-aliases.json'))
if ($null -ne $PostgresAction) { & $PostgresAction $mergedRows }
else {
    $settingsPath = Join-Path $ProjectRoot '.local\postgres-settings.json'
    $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Invoke-BestSellersMetadataPostgresImport -MetadataRows $mergedRows -PostgresSettings $settings | Out-Null
}
$dashboardPublished = 0
$dashboardSkipped = 0
if (-not $SkipDashboard) {
    $payload = New-BestSellersBrandMetadataRefreshPayload -ArtifactPath $artifactPath -ReceiptPath $receiptPath -MetadataRows $mergedRows
    if ($null -ne $PublishAction) { & $PublishAction $payload }
    else {
        if ($null -eq $DashboardUrl) { throw 'DashboardUrl is required when PublishAction is not supplied.' }
        Invoke-BestSellersBrandMetadataRefreshPublish -DashboardUrl $DashboardUrl -Payload $payload | Out-Null
    }
    $dashboardPublished = 1
}
else { $dashboardSkipped = 1 }

[pscustomobject][ordered]@{
    Status='COMPLETED'
    AsinCount=$asins.Count
    ArtifactPath=$artifactPath
    ReceiptPath=$receiptPath
    MetadataCount=$mergedRows.Count
    Published=(-not $SkipDashboard)
    StageCounts=[pscustomobject][ordered]@{
        discovered_asins=$verifiedAsins.Count
        selected_asins=$asins.Count
        collect_or_reuse_products=$collectOrReuseProducts
        artifact_verified_products=@($artifactVerification.products).Count
        receipt_verified_records=[int]$receiptVerification.receipt.record_count
        metadata_merged_rows=$mergedRows.Count
        postgres_imported_rows=$mergedRows.Count
        dashboard_published=$dashboardPublished
        dashboard_skipped=$dashboardSkipped
    }
} | ConvertTo-Json -Compress
