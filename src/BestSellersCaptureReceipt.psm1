Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'BestSellersAnalysis.psm1')
Import-Module (Join-Path $PSScriptRoot 'BestSellersCategoryRegistry.psm1')

function Get-BestSellersCaptureFileHash {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Snapshot not found: $Path" }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path)
        return [pscustomobject]@{ sha256 = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant(); byte_count = [long]$bytes.Length }
    }
    finally { $sha.Dispose() }
}

function Get-BestSellersCapturePropertyValue {
    param($Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-BestSellersCaptureRegistryContext {
    param(
        [Parameter(Mandatory = $true)][string]$RegistryPath,
        [Parameter(Mandatory = $true)][string]$SourceConfigPath
    )
    if (-not (Test-Path -LiteralPath $SourceConfigPath -PathType Leaf)) { throw "Source config not found: $SourceConfigPath" }
    $registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
    $config = Get-Content -LiteralPath $SourceConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $categories = @($registry.Categories | Where-Object Enabled)
    $sources = @($config.sources | Where-Object { $_.active })
    $verified = [string]$config.marketplace -ceq [string]$registry.Marketplace.StorageCode -and $sources.Count -eq $categories.Count
    foreach ($category in $categories) {
        $matches = @($sources | Where-Object { [string]$_.category_key -ceq [string]$category.CategoryKey })
        if ($matches.Count -ne 1 -or
            [string]$matches[0].amazon_node_id -cne [string]$category.NodeId -or
            [string]$matches[0].url -cne [string]$category.SourceUrl) {
            $verified = $false
        }
    }
    return [pscustomobject]@{ Registry=$registry; Config=$config; Categories=$categories; SourceMetadataVerified=$verified }
}

function New-BestSellersCaptureReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SnapshotPath,
        [Parameter(Mandatory = $true)][string]$SourceConfigPath,
        [datetimeoffset]$RegisteredAt = [DateTimeOffset]::UtcNow,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )
    $context = Get-BestSellersCaptureRegistryContext -RegistryPath $RegistryPath -SourceConfigPath $SourceConfigPath
    if (-not $context.SourceMetadataVerified) { throw 'Best Sellers source config does not match the canonical Category Registry.' }
    $snapshot = Read-BestSellersSnapshot -Path $SnapshotPath -RegistryPath $RegistryPath
    $quality = Test-BestSellersTop50Snapshot -Snapshot $snapshot -RegistryPath $RegistryPath
    $fileHash = Get-BestSellersCaptureFileHash -Path $SnapshotPath
    $categories = @()
    $sourceMetadataVerified = $true

    foreach ($category in @($context.Categories)) {
        $key = [string]$category.CategoryKey
        $qualityItem = @($quality.categories | Where-Object { $_.category -eq $key }) | Select-Object -First 1
        $snapshotSources = Get-BestSellersCapturePropertyValue -Object $snapshot -Name 'sources'
        $observedUrl = if ($null -ne $snapshotSources) { [string](Get-BestSellersCapturePropertyValue -Object $snapshotSources -Name $key) } else { $null }
        $urlStatus = if ([string]::IsNullOrWhiteSpace($observedUrl)) { 'MISSING' } elseif ($observedUrl -ceq [string]$category.SourceUrl) { 'MATCH' } else { 'MISMATCH' }
        if ($urlStatus -ne 'MATCH') { $sourceMetadataVerified = $false }
        $categories += [pscustomobject]@{
            category = $key
            amazon_node_id = [string]$category.NodeId
            expected_url = [string]$category.SourceUrl
            observed_url = $observedUrl
            source_url_status = $urlStatus
            target_count = [int]$category.TargetCount
            item_count = [int]$qualityItem.item_count
            completeness_percent = [double]$qualityItem.completeness_percent
            missing_ranks = @($qualityItem.missing_ranks)
            duplicate_asins = @($qualityItem.duplicate_asins)
            duplicate_ranks = @($qualityItem.duplicate_ranks)
            is_complete = [bool]$qualityItem.is_complete
        }
    }
    $complete = [bool]$quality.is_complete
    return [pscustomobject]@{
        schema_version = 'best-sellers-capture-receipt-v1'
        registered_at = $RegisteredAt.ToString('o')
        marketplace = [string]$context.Registry.Marketplace.StorageCode
        market_date = [string]$snapshot.market_date
        observed_at = [string](Get-BestSellersCapturePropertyValue -Object $snapshot -Name 'observed_at')
        snapshot_path = (Resolve-Path -LiteralPath $SnapshotPath).Path
        snapshot_sha256 = $fileHash.sha256
        snapshot_byte_count = $fileHash.byte_count
        source_config_path = (Resolve-Path -LiteralPath $SourceConfigPath).Path
        source_metadata_verified = $sourceMetadataVerified
        quality = $quality
        categories = $categories
        status = if ($complete -and $sourceMetadataVerified) { 'COMPLETE_VALIDATED' } elseif ($complete) { 'COMPLETE_SOURCE_METADATA_INCOMPLETE' } else { 'PARTIAL_NOT_ANALYSIS_ELIGIBLE' }
    }
}

function Write-BestSellersCaptureReceipt {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Receipt, [Parameter(Mandatory = $true)][string]$Path)
    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    [IO.File]::WriteAllText($Path, ($Receipt | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
    return (Resolve-Path -LiteralPath $Path).Path
}

function Test-BestSellersCaptureReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ReceiptPath,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )
    if (-not (Test-Path -LiteralPath $ReceiptPath -PathType Leaf)) { throw "Capture receipt not found: $ReceiptPath" }
    $receipt = Get-Content -LiteralPath $ReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$receipt.schema_version -ne 'best-sellers-capture-receipt-v1') { throw 'Unsupported capture receipt schema version.' }
    $snapshotPath = [string]$receipt.snapshot_path
    $sourceConfigPath = [string]$receipt.source_config_path
    $hash = Get-BestSellersCaptureFileHash -Path $snapshotPath
    $context = Get-BestSellersCaptureRegistryContext -RegistryPath $RegistryPath -SourceConfigPath $sourceConfigPath
    $snapshot = Read-BestSellersSnapshot -Path $snapshotPath -RegistryPath $RegistryPath
    $quality = Test-BestSellersTop50Snapshot -Snapshot $snapshot -RegistryPath $RegistryPath
    $qualityMatches = @($receipt.categories).Count -eq @($context.Categories).Count
    $sourceMetadataVerified = [bool]$context.SourceMetadataVerified -and [string]$receipt.marketplace -ceq [string]$context.Registry.Marketplace.StorageCode
    foreach ($category in @($context.Categories)) {
        $recorded = @($receipt.categories | Where-Object { [string]$_.category -ceq [string]$category.CategoryKey }) | Select-Object -First 1
        $current = @($quality.categories | Where-Object { [string]$_.category -ceq [string]$category.CategoryKey }) | Select-Object -First 1
        $snapshotSources = Get-BestSellersCapturePropertyValue -Object $snapshot -Name 'sources'
        $observedUrl = if ($null -ne $snapshotSources) { [string](Get-BestSellersCapturePropertyValue -Object $snapshotSources -Name ([string]$category.CategoryKey)) } else { $null }
        if ($null -eq $recorded -or $null -eq $current -or
            [int]$recorded.target_count -ne [int]$category.TargetCount -or
            [int]$recorded.item_count -ne [int]$current.item_count -or
            [bool]$recorded.is_complete -ne [bool]$current.is_complete) { $qualityMatches = $false }
        if ($null -eq $recorded -or
            [string]$recorded.amazon_node_id -cne [string]$category.NodeId -or
            [string]$recorded.expected_url -cne [string]$category.SourceUrl -or
            [string]$recorded.observed_url -cne $observedUrl -or
            [string]$recorded.source_url_status -cne 'MATCH' -or
            $observedUrl -cne [string]$category.SourceUrl) { $sourceMetadataVerified = $false }
    }
    $hashMatches = [string]$receipt.snapshot_sha256 -eq [string]$hash.sha256
    $marketDateMatches = [string]$receipt.market_date -eq [string]$snapshot.market_date
    return [pscustomobject]@{
        schema_version = 'best-sellers-capture-receipt-verification-v1'
        receipt_path = (Resolve-Path -LiteralPath $ReceiptPath).Path
        snapshot_path = (Resolve-Path -LiteralPath $snapshotPath).Path
        expected_snapshot_sha256 = [string]$receipt.snapshot_sha256
        actual_snapshot_sha256 = [string]$hash.sha256
        receipt_status = [string]$receipt.status
        receipt_market_date = [string]$receipt.market_date
        receipt_snapshot_sha256 = [string]$receipt.snapshot_sha256
        receipt_source_metadata_verified = [bool]$receipt.source_metadata_verified
        hash_matches = $hashMatches
        market_date_matches = $marketDateMatches
        quality_matches = $qualityMatches
        complete = [bool]$quality.is_complete
        complete_categories = @($quality.categories | Where-Object { $_.is_complete } | ForEach-Object { [string]$_.category })
        source_metadata_verified = $sourceMetadataVerified
        valid = $hashMatches -and $marketDateMatches -and $qualityMatches -and $sourceMetadataVerified
    }
}

function Resolve-BestSellersAuthorizedSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SnapshotPath,
        [Parameter(Mandatory = $true)][string]$ReceiptPath,
        [string]$CategoryKey,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )

    $verification = Test-BestSellersCaptureReceipt -ReceiptPath $ReceiptPath -RegistryPath $RegistryPath
    if (-not [string]::IsNullOrWhiteSpace($CategoryKey)) {
        if (-not (@($verification.complete_categories) -ccontains $CategoryKey)) { throw 'Selected category must be complete in the verified capture.' }
    }
    elseif ([string]$verification.receipt_status -ne 'COMPLETE_VALIDATED' -or -not [bool]$verification.complete -or -not [bool]$verification.receipt_source_metadata_verified) {
        throw 'Capture receipt must be COMPLETE_VALIDATED with verified source metadata.'
    }
    if (-not [bool]$verification.valid) { throw 'Capture receipt validation failed.' }
    $requestedSnapshotPath = (Resolve-Path -LiteralPath $SnapshotPath).Path
    $verifiedSnapshotPath = (Resolve-Path -LiteralPath ([string]$verification.snapshot_path)).Path
    if (-not [string]::Equals($requestedSnapshotPath, $verifiedSnapshotPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'SnapshotPath does not match the receipt snapshot.'
    }
    return [pscustomobject]@{
        snapshot_path = $requestedSnapshotPath
        receipt_path = [string]$verification.receipt_path
        market_date = [string]$verification.receipt_market_date
        snapshot_sha256 = [string]$verification.receipt_snapshot_sha256
        category_key = $CategoryKey
        verification = $verification
    }
}

Export-ModuleMember -Function New-BestSellersCaptureReceipt, Write-BestSellersCaptureReceipt, Test-BestSellersCaptureReceipt, Resolve-BestSellersAuthorizedSnapshot
