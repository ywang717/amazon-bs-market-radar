Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'BestSellersDataSemantics.psm1')
Import-Module (Join-Path $PSScriptRoot 'BestSellersCaptureReceipt.psm1')
Import-Module (Join-Path $PSScriptRoot 'BestSellersAnalysis.psm1')
Import-Module (Join-Path $PSScriptRoot 'DashboardPublishHttp.psm1')
Import-Module (Join-Path $PSScriptRoot 'BestSellersCategoryRegistry.psm1')

$script:BrandVerificationStatuses = @('VERIFIED', 'MISSING', 'CONFLICT', 'IDENTITY_MISMATCH', 'VERIFICATION_BLOCKED')
$script:VerifiedBrandEvidenceSources = @('PRODUCT_OVERVIEW_BRAND_FIELD', 'PRODUCT_DETAILS_BRAND_FIELD', 'DETAIL_BULLET_BRAND_FIELD')

function Get-BestSellersBrandPropertyValue {
    param($Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-BestSellersCanonicalAsins {
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

function Get-BestSellersVerifiedHistoryAsins {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SnapshotsRoot,
        [string]$SnapshotFileName = 'amazon-bestsellers.json',
        [string]$ReceiptFileName = 'best-sellers-capture-receipt.json',
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )

    if (-not (Test-Path -LiteralPath $SnapshotsRoot -PathType Container)) { throw "Snapshots root not found: $SnapshotsRoot" }
    $registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
    $categories = @($registry.Categories | Where-Object Enabled)
    $asins = New-Object 'System.Collections.Generic.List[string]'
    foreach ($snapshotFile in @(Get-ChildItem -LiteralPath $SnapshotsRoot -Filter $SnapshotFileName -File -Recurse | Sort-Object FullName)) {
        $receiptPath = Join-Path $snapshotFile.DirectoryName $ReceiptFileName
        $authorized = Resolve-BestSellersAuthorizedSnapshot -SnapshotPath $snapshotFile.FullName -ReceiptPath $receiptPath -RegistryPath $RegistryPath
        $snapshot = Read-BestSellersSnapshot -Path $authorized.snapshot_path -RegistryPath $RegistryPath
        foreach ($category in $categories) {
            $items = Get-BestSellersBrandPropertyValue -Object $snapshot -Name $category.CategoryKey
            if ($null -eq $items -or -not (Test-BestSellersExactTop30 -Items @($items) -TargetCount $category.TargetCount)) {
                throw "Authorized snapshot does not contain the exact Registry target for category '$($category.CategoryKey)': $($snapshotFile.FullName)"
            }
            foreach ($item in @($items)) { $asins.Add([string](Get-BestSellersBrandPropertyValue -Object $item -Name 'asin')) }
        }
    }
    return @(Get-BestSellersCanonicalAsins -Asins $asins.ToArray())
}

function Get-BestSellersBrandAsinSetHash {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$Asins)

    $canonical = @(Get-BestSellersCanonicalAsins -Asins $Asins)
    $payload = [string]::Join("`n", $canonical)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($payload)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Test-BestSellersBrandEnrichmentArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactPath,
        [Parameter(Mandatory = $true)][string[]]$RequestedAsins
    )

    $errors = New-Object 'System.Collections.Generic.List[string]'
    $artifact = $null
    if (-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf)) {
        $errors.Add("Artifact not found: $ArtifactPath")
    }
    else {
        try { $artifact = Get-Content -LiteralPath $ArtifactPath -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { $errors.Add('Artifact is not valid JSON.') }
    }
    if ($null -ne $artifact) {
        if ([string]$artifact.schema_version -ne 'amazon-brand-enrichment-v1') { $errors.Add('Unsupported artifact schema version.') }
        if ([string]$artifact.marketplace -ne 'AMAZON_US') { $errors.Add('Artifact marketplace must be AMAZON_US.') }
        $generatedAt = [datetimeoffset]::MinValue
        if (-not [datetimeoffset]::TryParse([string]$artifact.generated_at, [ref]$generatedAt)) { $errors.Add('Artifact generated_at is invalid.') }
        if ($null -eq $artifact.PSObject.Properties['products']) { $errors.Add('Artifact products are required.') }
    }

    $products = if ($null -eq $artifact) { @() } else { @($artifact.products) }
    $productAsins = New-Object 'System.Collections.Generic.List[string]'
    $previousAsin = $null
    foreach ($product in $products) {
        foreach ($field in @('asin', 'detail_url', 'verification_status', 'raw_brand', 'brand_source', 'evidence_source')) {
            if ($null -eq $product.PSObject.Properties[$field]) { $errors.Add("Product is missing '$field'.") }
        }
        $asin = ([string](Get-BestSellersBrandPropertyValue -Object $product -Name 'asin')).Trim().ToUpperInvariant()
        if ($asin -notmatch '^[A-Z0-9]{10}$') { $errors.Add("Product has invalid ASIN '$asin'."); continue }
        $productAsins.Add($asin)
        if ($null -ne $previousAsin -and [StringComparer]::Ordinal.Compare($previousAsin, $asin) -ge 0) { $errors.Add('Artifact products must be unique and ordinally sorted by ASIN.') }
        $previousAsin = $asin
        if ([string](Get-BestSellersBrandPropertyValue -Object $product -Name 'detail_url') -ne "https://www.amazon.com/dp/$asin") { $errors.Add("Product detail_url is not canonical for $asin.") }
        $status = [string](Get-BestSellersBrandPropertyValue -Object $product -Name 'verification_status')
        if ($status -notin $script:BrandVerificationStatuses) { $errors.Add("Product has invalid verification_status '$status'.") }
        $rawBrand = Get-BestSellersBrandPropertyValue -Object $product -Name 'raw_brand'
        $brandSource = [string](Get-BestSellersBrandPropertyValue -Object $product -Name 'brand_source')
        $evidenceSource = Get-BestSellersBrandPropertyValue -Object $product -Name 'evidence_source'
        if ($status -eq 'VERIFIED') {
            if ([string]::IsNullOrWhiteSpace([string]$rawBrand) -or $brandSource -ne 'verified_metadata' -or [string]$evidenceSource -notin $script:VerifiedBrandEvidenceSources) { $errors.Add("Verified product $asin has invalid brand provenance.") }
            else {
                try { ConvertTo-BestSellersPortableBrandText -Value ([string]$rawBrand) | Out-Null }
                catch { $errors.Add("Verified product $asin brand text is outside the portable normalization boundary.") }
            }
        }
        elseif ($null -ne $rawBrand -or $brandSource -ne 'unknown' -or $null -ne $evidenceSource) { $errors.Add("Unverified product $asin must retain unknown null brand fields.") }
    }
    try { $requested = @(Get-BestSellersCanonicalAsins -Asins $RequestedAsins) }
    catch { $errors.Add($_.Exception.Message); $requested = @() }
    if (@($productAsins).Count -ne $requested.Count -or -not (@($productAsins) -join "`n").Equals(($requested -join "`n"), [StringComparison]::Ordinal)) { $errors.Add('Artifact products do not match the requested ASIN set.') }

    return [pscustomobject]@{
        schema_version = 'amazon-brand-enrichment-artifact-verification-v1'
        valid = ($errors.Count -eq 0)
        artifact_path = if (Test-Path -LiteralPath $ArtifactPath -PathType Leaf) { (Resolve-Path -LiteralPath $ArtifactPath).Path } else { $ArtifactPath }
        artifact = $artifact
        products = $products
        errors = $errors.ToArray()
    }
}

function Get-BestSellersBrandFileHash {
    param([Parameter(Mandatory = $true)][string]$Path)
    $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function New-BestSellersBrandEnrichmentReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactPath,
        [Parameter(Mandatory = $true)][string[]]$RequestedAsins,
        [datetimeoffset]$GeneratedAt = [datetimeoffset]::UtcNow
    )

    $verification = Test-BestSellersBrandEnrichmentArtifact -ArtifactPath $ArtifactPath -RequestedAsins $RequestedAsins
    if (-not $verification.valid) { throw "Brand enrichment artifact validation failed: $($verification.errors -join '; ')" }
    $counts = [ordered]@{}
    foreach ($status in $script:BrandVerificationStatuses) { $counts[$status] = @($verification.products | Where-Object { [string]$_.verification_status -eq $status }).Count }
    return [pscustomobject]@{
        schema_version = 'amazon-brand-enrichment-receipt-v1'
        generated_at = $GeneratedAt.ToUniversalTime().ToString('o')
        marketplace = 'AMAZON_US'
        requested_asin_set_sha256 = Get-BestSellersBrandAsinSetHash -Asins $RequestedAsins
        artifact_sha256 = Get-BestSellersBrandFileHash -Path $ArtifactPath
        record_count = @($verification.products).Count
        status_counts = [pscustomobject]$counts
    }
}

function Test-BestSellersBrandEnrichmentReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ReceiptPath,
        [Parameter(Mandatory = $true)][string]$ArtifactPath,
        [Parameter(Mandatory = $true)][string[]]$RequestedAsins
    )

    $errors = New-Object 'System.Collections.Generic.List[string]'
    $receipt = $null
    if (-not (Test-Path -LiteralPath $ReceiptPath -PathType Leaf)) { $errors.Add("Receipt not found: $ReceiptPath") }
    else { try { $receipt = Get-Content -LiteralPath $ReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $errors.Add('Receipt is not valid JSON.') } }
    $artifact = Test-BestSellersBrandEnrichmentArtifact -ArtifactPath $ArtifactPath -RequestedAsins $RequestedAsins
    if (-not $artifact.valid) { $errors.Add('Artifact does not validate.') }
    if ($null -ne $receipt) {
        if ([string]$receipt.schema_version -ne 'amazon-brand-enrichment-receipt-v1') { $errors.Add('Unsupported receipt schema version.') }
        if ([string]$receipt.marketplace -ne 'AMAZON_US') { $errors.Add('Receipt marketplace must be AMAZON_US.') }
        $generatedAt = [datetimeoffset]::MinValue
        if (-not [datetimeoffset]::TryParse([string]$receipt.generated_at, [ref]$generatedAt)) { $errors.Add('Receipt generated_at is invalid.') }
        if ([string]$receipt.artifact_sha256 -ne (Get-BestSellersBrandFileHash -Path $ArtifactPath)) { $errors.Add('Receipt artifact hash does not match exact artifact bytes.') }
        if ([string]$receipt.requested_asin_set_sha256 -ne (Get-BestSellersBrandAsinSetHash -Asins $RequestedAsins)) { $errors.Add('Receipt requested ASIN hash does not match.') }
        if ([int]$receipt.record_count -ne @($artifact.products).Count) { $errors.Add('Receipt record count does not match.') }
        foreach ($status in $script:BrandVerificationStatuses) {
            if ($null -eq $receipt.status_counts.PSObject.Properties[$status]) { $errors.Add("Receipt is missing the $status count.") }
            elseif ([int](Get-BestSellersBrandPropertyValue -Object $receipt.status_counts -Name $status) -ne @($artifact.products | Where-Object { [string]$_.verification_status -eq $status }).Count) { $errors.Add("Receipt $status count does not match.") }
        }
    }
    return [pscustomobject]@{ schema_version='amazon-brand-enrichment-receipt-verification-v1'; valid=($errors.Count -eq 0); receipt=$receipt; errors=$errors.ToArray() }
}

function Copy-BestSellersBrandMetadataRow {
    param([Parameter(Mandatory = $true)]$Row)
    $copy = [ordered]@{}
    foreach ($property in $Row.PSObject.Properties) { $copy[$property.Name] = $property.Value }
    return [pscustomobject]$copy
}

function Merge-BestSellersBrandEnrichmentMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$MetadataRows,
        [Parameter(Mandatory = $true)]$Artifact,
        [Parameter(Mandatory = $true)][string]$BrandAliasConfigPath
    )

    if ([string]$Artifact.schema_version -ne 'amazon-brand-enrichment-v1' -or [string]$Artifact.marketplace -ne 'AMAZON_US') { throw 'Unsupported brand enrichment artifact.' }
    $byAsin = @{}
    foreach ($product in @($Artifact.products)) { $byAsin[([string]$product.asin).ToUpperInvariant()] = $product }
    $updates = @{}
    foreach ($row in @($MetadataRows)) {
        $asin = ([string]$row.asin).ToUpperInvariant()
        $product = $byAsin[$asin]
        if ($null -eq $product -or [string]$product.verification_status -ne 'VERIFIED') { continue }
        if ([string]$product.brand_source -ne 'verified_metadata' -or [string]::IsNullOrWhiteSpace([string]$product.raw_brand) -or [string]$product.evidence_source -notin $script:VerifiedBrandEvidenceSources) { throw "Verified artifact product $asin has invalid provenance." }
        $normalized = Get-BestSellersBrandNormalization -RawBrand ([string]$product.raw_brand) -Source verified_metadata -ConfigPath $BrandAliasConfigPath
        $existingSource = [string]$row.brand_source
        $existingKey = [string]$row.normalized_brand_key
        if ($existingSource -in @('verified_metadata', 'manual_review') -and -not [string]::IsNullOrWhiteSpace($existingKey) -and -not [string]::Equals($existingKey, [string]$normalized.normalized_key, [StringComparison]::Ordinal)) {
            throw "Brand conflict for ASIN $asin."
        }
        $updates[$asin] = $normalized
    }
    $result = New-Object 'System.Collections.Generic.List[object]'
    foreach ($row in @($MetadataRows | Sort-Object { [string]$_.asin })) {
        $copy = Copy-BestSellersBrandMetadataRow -Row $row
        $normalized = $updates[([string]$copy.asin).ToUpperInvariant()]
        if ($null -ne $normalized) {
            $copy.raw_brand = $normalized.raw_brand
            $copy.normalized_brand = $normalized.normalized_brand
            $copy.normalized_brand_key = $normalized.normalized_key
            $copy.brand_alias_rule_id = $normalized.alias_rule_id
            $copy.brand_source = 'verified_metadata'
        }
        $result.Add($copy)
    }
    return $result.ToArray()
}

function ConvertTo-BestSellersBrandMetadataRefreshRows {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$MetadataRows,
        [Parameter(Mandatory = $true)][object[]]$ArtifactProducts
    )

    $requiredFields = @(
        'marketplace_code', 'asin', 'product_type', 'classification_confidence', 'classification_rule_id',
        'classification_rule_version', 'classification_evidence', 'raw_brand', 'normalized_brand',
        'normalized_brand_key', 'brand_alias_rule_id', 'brand_source', 'first_seen_market_date', 'last_seen_market_date'
    )
    $rowsByAsin = @{}
    foreach ($row in @($MetadataRows)) {
        foreach ($field in $requiredFields) {
            if ($null -eq $row.PSObject.Properties[$field]) { throw "Product metadata row is missing '$field'." }
        }
        $asin = ([string]$row.asin).Trim().ToUpperInvariant()
        if ([string]$row.marketplace_code -ne 'AMAZON_US' -or $asin -notmatch '^[A-Z0-9]{10}$') { throw 'Product metadata rows require AMAZON_US and valid ASINs.' }
        if ($rowsByAsin.ContainsKey($asin)) { throw "Product metadata contains duplicate ASIN $asin." }
        $rowsByAsin[$asin] = $row
    }

    $artifactByAsin = @{}
    foreach ($product in @($ArtifactProducts)) { $artifactByAsin[[string]$product.asin] = $product }
    if ($rowsByAsin.Count -ne $artifactByAsin.Count -or @($artifactByAsin.Keys | Where-Object { -not $rowsByAsin.ContainsKey($_) }).Count -gt 0) {
        throw 'Product metadata ASIN cohort must exactly match the artifact.'
    }

    $result = New-Object 'System.Collections.Generic.List[object]'
    foreach ($asin in @($artifactByAsin.Keys | Sort-Object)) {
        $row = $rowsByAsin[$asin]
        $product = $artifactByAsin[$asin]
        if ([string]$product.verification_status -eq 'VERIFIED') {
            if ([string]$row.brand_source -ne 'verified_metadata' -or [string]$row.raw_brand -cne [string]$product.raw_brand) {
                throw "Verified product metadata brand does not match artifact for ASIN $asin."
            }
            foreach ($value in @([string]$row.raw_brand, [string]$row.normalized_brand, [string]$row.normalized_brand_key)) {
                try { $portableValue = ConvertTo-BestSellersPortableBrandText -Value $value }
                catch { throw "Verified product metadata contains non-portable brand text for ASIN $asin." }
                if ($portableValue -cne $value) { throw "Verified product metadata contains non-normalized brand spacing for ASIN $asin." }
            }
            if ([string]$row.normalized_brand_key -cne ([string]$row.normalized_brand).ToLowerInvariant()) {
                throw "Verified product metadata has an incoherent normalized brand key for ASIN $asin."
            }
            $rawBrand = if ($null -eq $row.raw_brand) { $null } else { [string]$row.raw_brand }
            $normalizedBrand = if ($null -eq $row.normalized_brand) { $null } else { [string]$row.normalized_brand }
            $normalizedBrandKey = if ($null -eq $row.normalized_brand_key) { $null } else { [string]$row.normalized_brand_key }
            $brandAliasRuleId = if ($null -eq $row.brand_alias_rule_id) { $null } else { [string]$row.brand_alias_rule_id }
            $brandSource = [string]$row.brand_source
        }
        else {
            $rawBrand = $null
            $normalizedBrand = $null
            $normalizedBrandKey = $null
            $brandAliasRuleId = $null
            $brandSource = 'unknown'
        }
        $result.Add([pscustomobject][ordered]@{
            marketplace = [string]$row.marketplace_code
            asin = $asin
            productType = [string]$row.product_type
            classificationConfidence = [string]$row.classification_confidence
            classificationRuleId = if ($null -eq $row.classification_rule_id) { $null } else { [string]$row.classification_rule_id }
            classificationRuleVersion = [string]$row.classification_rule_version
            classificationEvidence = @($row.classification_evidence | ForEach-Object { [string]$_ })
            rawBrand = $rawBrand
            normalizedBrand = $normalizedBrand
            normalizedBrandKey = $normalizedBrandKey
            brandAliasRuleId = $brandAliasRuleId
            brandSource = $brandSource
            firstSeenMarketDate = [string]$row.first_seen_market_date
            lastSeenMarketDate = [string]$row.last_seen_market_date
        })
    }
    return $result.ToArray()
}

function New-BestSellersBrandMetadataRefreshPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactPath,
        [Parameter(Mandatory = $true)][string]$ReceiptPath,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$MetadataRows
    )

    if (-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf)) { throw "Brand enrichment artifact not found: $ArtifactPath" }
    $artifactBytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $ArtifactPath).Path)
    if ($artifactBytes.Length -ge 3 -and $artifactBytes[0] -eq 0xEF -and $artifactBytes[1] -eq 0xBB -and $artifactBytes[2] -eq 0xBF) {
        throw 'Brand enrichment artifact must be UTF-8 without a BOM.'
    }
    $artifactJson = (New-Object Text.UTF8Encoding($false, $true)).GetString($artifactBytes)
    try { $artifact = $artifactJson | ConvertFrom-Json }
    catch { throw 'Brand enrichment artifact is not valid UTF-8 JSON.' }
    $asins = @($artifact.products | ForEach-Object { [string]$_.asin })
    $artifactVerification = Test-BestSellersBrandEnrichmentArtifact -ArtifactPath $ArtifactPath -RequestedAsins $asins
    if (-not $artifactVerification.valid) { throw "Brand enrichment artifact validation failed: $($artifactVerification.errors -join '; ')" }
    $receiptVerification = Test-BestSellersBrandEnrichmentReceipt -ReceiptPath $ReceiptPath -ArtifactPath $ArtifactPath -RequestedAsins $asins
    if (-not $receiptVerification.valid) { throw "Brand enrichment receipt validation failed: $($receiptVerification.errors -join '; ')" }

    return [pscustomobject][ordered]@{
        schemaVersion = 'amazon-brand-metadata-refresh-v1'
        marketplace = 'AMAZON_US'
        artifactJson = $artifactJson
        artifactSha256 = Get-BestSellersBrandFileHash -Path $ArtifactPath
        receipt = $receiptVerification.receipt
        productMetadata = @(ConvertTo-BestSellersBrandMetadataRefreshRows -MetadataRows $MetadataRows -ArtifactProducts $artifactVerification.products)
    }
}

function Invoke-BestSellersBrandMetadataRefreshPublish {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][uri]$DashboardUrl,
        [Parameter(Mandatory = $true)]$Payload,
        [scriptblock]$RestAction
    )

    $secret = [Environment]::GetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'Process')
    if ([string]::IsNullOrWhiteSpace($secret)) { $secret = [Environment]::GetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'User') }
    if ([string]::IsNullOrWhiteSpace($secret)) { throw 'Dashboard sync secret is not configured.' }
    $requestParameters = New-DashboardPublishRestParameters -Uri ([uri]::new($DashboardUrl, '/api/sync/v1/product-metadata')) -Method Post -Headers @{ Authorization = "Bearer $secret" } -ContentType 'application/json' -Body $Payload -BodyProvided
    try {
        $response = if ($null -ne $RestAction) { & $RestAction $requestParameters } else { Invoke-RestMethod @requestParameters }
        if ($null -ne $response -and $null -ne $response.PSObject.Properties['StatusCode'] -and ([int]$response.StatusCode -lt 200 -or [int]$response.StatusCode -gt 299)) {
            throw 'Non-success response status.'
        }
        return $response
    }
    catch {
        throw 'Brand metadata refresh publication failed.'
    }
}

Export-ModuleMember -Function Get-BestSellersVerifiedHistoryAsins, Get-BestSellersBrandAsinSetHash, Test-BestSellersBrandEnrichmentArtifact, New-BestSellersBrandEnrichmentReceipt, Test-BestSellersBrandEnrichmentReceipt, Merge-BestSellersBrandEnrichmentMetadata, New-BestSellersBrandMetadataRefreshPayload, Invoke-BestSellersBrandMetadataRefreshPublish
