Import-Module (Join-Path $PSScriptRoot 'BestSellersDataSemantics.psm1') -Scope Local

function ConvertTo-DashboardSyncNumber {
    param(
        $Value,
        [switch]$Currency,
        [switch]$Integer,
        [double]$Minimum = 0,
        [double]$Maximum = [double]::PositiveInfinity
    )

    if ($null -eq $Value) { return $null }
    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    if ($Currency) { $text = $text -replace '[^0-9,\.\-\+]', '' }
    else { $text = $text.Replace(',', '') }
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    $number = 0.0
    $style = [Globalization.NumberStyles]::Float -bor [Globalization.NumberStyles]::AllowThousands
    if (-not [double]::TryParse($text, $style, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) { return $null }
    if ([double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt $Minimum -or $number -gt $Maximum) { return $null }
    if ($Integer) {
        if ($number -ne [math]::Truncate($number)) { return $null }
        return [long]$number
    }
    return [double]$number
}

function ConvertTo-DashboardSyncObservation {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Observation)

    $normalized = [ordered]@{}
    foreach ($property in $Observation.PSObject.Properties) { $normalized[$property.Name] = $property.Value }
    $normalized.price = ConvertTo-DashboardSyncNumber -Value $Observation.price -Currency -Minimum 0
    $normalized.rating = ConvertTo-DashboardSyncNumber -Value $Observation.rating -Minimum 0 -Maximum 5
    $normalized.reviews = ConvertTo-DashboardSyncNumber -Value $Observation.reviews -Integer -Minimum 0
    return [pscustomobject]$normalized
}

function New-DashboardSyncProductMetadataCohort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Snapshot,
        [string]$ClassificationConfigPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\v2-product-classification.json'),
        [string]$BrandConfigPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\v2-brand-aliases.json'),
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )

    $marketplace = if ([string]::IsNullOrWhiteSpace([string]$Snapshot.marketplace)) { 'AMAZON_US' } else { [string]$Snapshot.marketplace }
    $rows = @(New-BestSellersProductMetadataRows -Snapshots @($Snapshot) -MarketplaceCode $marketplace -ClassificationConfigPath $ClassificationConfigPath -BrandAliasConfigPath $BrandConfigPath -RegistryPath $RegistryPath)
    foreach ($row in $rows) {
        # This is the single snake_case-to-camelCase boundary for centralized semantics.
        [pscustomobject][ordered]@{
            marketplace = [string]$row.marketplace_code
            asin = [string]$row.asin
            productType = [string]$row.product_type
            classificationConfidence = [string]$row.classification_confidence
            classificationRuleId = if ($null -eq $row.classification_rule_id) { $null } else { [string]$row.classification_rule_id }
            classificationRuleVersion = [string]$row.classification_rule_version
            classificationEvidence = @($row.classification_evidence | ForEach-Object { [string]$_ })
            rawBrand = if ($null -eq $row.raw_brand) { $null } else { [string]$row.raw_brand }
            normalizedBrand = if ($null -eq $row.normalized_brand) { $null } else { [string]$row.normalized_brand }
            normalizedBrandKey = if ($null -eq $row.normalized_brand_key) { $null } else { [string]$row.normalized_brand_key }
            brandAliasRuleId = if ($null -eq $row.brand_alias_rule_id) { $null } else { [string]$row.brand_alias_rule_id }
            brandSource = [string]$row.brand_source
            firstSeenMarketDate = [string]$row.first_seen_market_date
            lastSeenMarketDate = [string]$row.last_seen_market_date
        }
    }
}

Export-ModuleMember -Function ConvertTo-DashboardSyncObservation, New-DashboardSyncProductMetadataCohort
