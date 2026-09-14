Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'BestSellersCategoryRegistry.psm1') -Scope Local

function Read-V2JsonConfig {
    param(
        [Parameter(Mandatory=$true)][string]$ConfigPath
    )

    return (Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Assert-V2ProductClassificationConfig {
    param(
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)]$Registry
    )

    if ($null -eq $Config -or [string]$Config.schema_version -ne 'product-classification-config-v1') {
        throw 'Unsupported product classification config version.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Config.rule_version)) {
        throw 'Product classification config requires a rule version.'
    }
    if ($null -eq $Config.PSObject.Properties['rules']) {
        throw 'Product classification config requires rules.'
    }

    $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $allowedTypes = @($Registry.Categories | ForEach-Object {
        $schema = Get-Content -LiteralPath $_.AttributeSchemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
        @($schema.product_types.PSObject.Properties.Name | Where-Object { $_ -cne 'unknown' })
    } | Sort-Object -Unique)
    $overrideCategoryKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    if ($null -ne $Config.PSObject.Properties['reviewed_asin_overrides']) {
        foreach ($override in @($Config.reviewed_asin_overrides)) {
            $id = [string]$override.id
            $asin = [string]$override.asin
            $productType = [string]$override.product_type
            $confidence = [string]$override.confidence
            $sourceUrl = [string]$override.source_url
            $reviewedOn = [string]$override.reviewed_on
            if ([string]::IsNullOrWhiteSpace($id) -or $id -notmatch '^reviewed-asin-[a-z0-9_-]+$' -or -not $ids.Add($id)) {
                throw 'Reviewed ASIN overrides require unique stable ids.'
            }
            if ($asin -cnotmatch '^[A-Z0-9]{10}$' -or $productType -cnotin $allowedTypes -or $confidence -cnotin @('high','medium')) {
                throw "Reviewed ASIN override '$id' has an invalid ASIN or classification."
            }
            if ($sourceUrl -cne "https://www.amazon.com/dp/$asin") {
                throw "Reviewed ASIN override '$id' requires its canonical Amazon product detail URL."
            }
            $parsedReviewedOn = [datetime]::MinValue
            if (-not [datetime]::TryParseExact($reviewedOn,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$parsedReviewedOn)) {
                throw "Reviewed ASIN override '$id' requires a valid reviewed_on date."
            }
            if ($null -eq $override.PSObject.Properties['category_keys'] -or @($override.category_keys).Count -eq 0 -or
                $null -eq $override.PSObject.Properties['evidence'] -or @($override.evidence).Count -eq 0 -or
                @($override.evidence | Where-Object { [string]$_ -notmatch '^AMAZON_PRODUCT_DETAIL:[A-Z0-9_=-]+$' }).Count -gt 0) {
                throw "Reviewed ASIN override '$id' requires scoped categories and product-detail evidence."
            }
            foreach ($categoryKey in @($override.category_keys)) {
                try { Get-BestSellersCategory -Registry $Registry -CategoryKey ([string]$categoryKey) | Out-Null }
                catch { throw "Reviewed ASIN override '$id' contains an unsupported category." }
                if (-not $overrideCategoryKeys.Add("$asin|$([string]$categoryKey)")) {
                    throw 'Reviewed ASIN overrides contain a duplicate ASIN and category.'
                }
            }
        }
    }
    foreach ($rule in @($Config.rules)) {
        if ($null -eq $rule) {
            throw 'Product classification config contains an invalid rule.'
        }
        $id = [string]$rule.id
        if ([string]::IsNullOrWhiteSpace($id) -or $id -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') {
            throw 'Product classification rules require stable non-empty ids.'
        }
        if (-not $ids.Add($id)) {
            throw 'Product classification rules contain duplicate ids.'
        }
        if ([string]::IsNullOrWhiteSpace([string]$rule.product_type) -or [string]::IsNullOrWhiteSpace([string]$rule.confidence)) {
            throw "Product classification rule '$id' is incomplete."
        }
        if ($null -eq $rule.PSObject.Properties['category_keys']) {
            throw "Product classification rule '$id' requires category_keys."
        }
        foreach ($categoryKey in @($rule.category_keys)) {
            try { Get-BestSellersCategory -Registry $Registry -CategoryKey ([string]$categoryKey) | Out-Null }
            catch { throw "Product classification rule '$id' contains an unsupported category." }
        }
    }
}

function Get-BestSellersProductClassification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidatePattern('^[A-Z0-9]{10}$')][string]$Asin,
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][string]$CategoryKey,
        [Parameter(Mandatory=$true)][string]$ConfigPath,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )

    $registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
    Get-BestSellersCategory -Registry $registry -CategoryKey $CategoryKey | Out-Null
    $config = Read-V2JsonConfig -ConfigPath $ConfigPath
    Assert-V2ProductClassificationConfig -Config $config -Registry $registry
    $reviewedOverrides = if ($null -eq $config.PSObject.Properties['reviewed_asin_overrides']) {
        @()
    } else {
        @($config.reviewed_asin_overrides)
    }
    $reviewedOverride = @($reviewedOverrides | Where-Object {
        [string]$_.asin -ceq $Asin -and [string]$CategoryKey -cin @($_.category_keys | ForEach-Object { [string]$_ })
    } | Select-Object -First 1)
    if ($reviewedOverride.Count -eq 1) {
        return [pscustomobject]@{
            asin=$Asin
            product_type=[string]$reviewedOverride[0].product_type
            classification_confidence=[string]$reviewedOverride[0].confidence
            rule_id=[string]$reviewedOverride[0].id
            rule_version=[string]$config.rule_version
            evidence=@($reviewedOverride[0].evidence | ForEach-Object { [string]$_ })
        }
    }
    $normalizedTitle = (($Title.Trim() -replace '\s+', ' ').ToLowerInvariant())
    $ruleMatches = New-Object System.Collections.Generic.List[object]

    function Get-PhraseMatchIndex {
        param([string]$Text, [string]$Phrase)

        $escaped = [regex]::Escape($Phrase.Trim().ToLowerInvariant()) -replace '\\ ', '\s+'
        $match = [regex]::Match($Text, "(?<![a-z0-9])$escaped(?![a-z0-9])", [Text.RegularExpressions.RegexOptions]::CultureInvariant)
        if ($match.Success) { return $match.Index }
        return -1
    }

    foreach ($rule in @($config.rules)) {
        if ([string]$CategoryKey -notin @($rule.category_keys | ForEach-Object { [string]$_ })) { continue }
        $allPhrases = @(if ($null -eq $rule.PSObject.Properties['all_phrases']) { @() } else { @($rule.all_phrases) })
        $anyPhrases = @(if ($null -eq $rule.PSObject.Properties['any_phrases']) { @() } else { @($rule.any_phrases) })
        $allIndexes = @($allPhrases | ForEach-Object { Get-PhraseMatchIndex -Text $normalizedTitle -Phrase ([string]$_) })
        $anyIndexes = @($anyPhrases | ForEach-Object { Get-PhraseMatchIndex -Text $normalizedTitle -Phrase ([string]$_) })
        $allMatch = $allPhrases.Count -eq 0 -or @($allIndexes | Where-Object { $_ -ge 0 }).Count -eq $allPhrases.Count
        $matchedAnyIndexes = @($anyIndexes | Where-Object { $_ -ge 0 })
        $anyMatch = $anyPhrases.Count -eq 0 -or $matchedAnyIndexes.Count -gt 0
        if ($allMatch -and $anyMatch) {
            $candidateIndexes = @($allIndexes + $matchedAnyIndexes | Where-Object { $_ -ge 0 })
            $ruleMatches.Add([pscustomobject]@{
                rule = $rule
                match_index = if ($candidateIndexes.Count -gt 0) { ($candidateIndexes | Measure-Object -Minimum).Minimum } else { [int]::MaxValue }
            })
        }
    }

    $machineTypes = @('electric_pressure_washer','gas_pressure_washer','cordless_pressure_washer')
    $accessoryTypes = @('surface_cleaner','pressure_washer_gun','hose','nozzle','foam_cannon','adapter_connector','extension_wand','sewer_jetter','chemical_cleaner','pump_protector')
    $machineMatches = @($ruleMatches | Where-Object { [string]$_.rule.product_type -in $machineTypes })
    $accessoryMatches = @($ruleMatches | Where-Object { [string]$_.rule.product_type -in $accessoryTypes })
    $machineTypesMatched = @($machineMatches | ForEach-Object { [string]$_.rule.product_type } | Sort-Object -Unique)
    $powerFamilies = @(
        @{ name='gas'; phrases=@('gas','gasoline') },
        @{ name='electric'; phrases=@('electric','corded') },
        @{ name='cordless'; phrases=@('cordless','battery powered','battery-powered') }
    )
    $powerEvidence = @($powerFamilies | Where-Object {
        @($_.phrases | Where-Object { (Get-PhraseMatchIndex -Text $normalizedTitle -Phrase $_) -ge 0 }).Count -gt 0
    } | ForEach-Object { $_.name })
    $hasPressureWasherPhrase = [regex]::IsMatch($normalizedTitle, '(?<![a-z0-9])pressure\s+washer(?![a-z0-9])', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
    if ($accessoryMatches.Count -eq 0 -and $hasPressureWasherPhrase -and $powerEvidence.Count -gt 1) {
        return [pscustomobject]@{
            asin=$Asin
            product_type='unknown'
            classification_confidence='low'
            rule_id=$null
            rule_version=[string]$config.rule_version
            evidence=@($powerEvidence | ForEach-Object { "CONFLICT:power-$($_ -replace ' ', '-')" })
        }
    }
    if ($machineTypesMatched.Count -gt 1 -and $accessoryMatches.Count -eq 0) {
        return [pscustomobject]@{
            asin=$Asin
            product_type='unknown'
            classification_confidence='low'
            rule_id=$null
            rule_version=[string]$config.rule_version
            evidence=@($machineMatches | ForEach-Object { "CONFLICT:$([string]$_.rule.id)" })
        }
    }

    # Product identity normally appears before compatibility/bundle wording.
    # Choosing the earliest specific phrase keeps a machine such as
    # "Electric Pressure Washer with Surface Cleaner" a machine, while
    # "Surface Cleaner for Gas Pressure Washers" remains an accessory.
    $specific = @($ruleMatches | Where-Object { [string]$_.rule.product_type -ne 'other_accessory' })
    if ($specific.Count -gt 0) {
        $earliest = ($specific | Measure-Object -Property match_index -Minimum).Minimum
        $specific = @($specific | Where-Object { $_.match_index -eq $earliest })
    }
    else {
        $specific = @($ruleMatches | ForEach-Object { $_ })
    }
    $types = @($specific | ForEach-Object { [string]$_.rule.product_type } | Sort-Object -Unique)
    if ($types.Count -gt 1) {
        return [pscustomobject]@{
            asin=$Asin
            product_type='unknown'
            classification_confidence='low'
            rule_id=$null
            rule_version=[string]$config.rule_version
            evidence=@($specific | ForEach-Object { "CONFLICT:$([string]$_.rule.id)" })
        }
    }

    $winner = if ($specific.Count -gt 0) { $specific[0].rule } elseif ($ruleMatches.Count -gt 0) { $ruleMatches[0].rule } else { $null }
    if ($null -eq $winner) {
        return [pscustomobject]@{
            asin=$Asin
            product_type='unknown'
            classification_confidence='low'
            rule_id=$null
            rule_version=[string]$config.rule_version
            evidence=@('NO_SAFE_RULE_MATCH')
        }
    }
    return [pscustomobject]@{
        asin=$Asin
        product_type=[string]$winner.product_type
        classification_confidence=[string]$winner.confidence
        rule_id=[string]$winner.id
        rule_version=[string]$config.rule_version
        evidence=@("TITLE_RULE:$([string]$winner.id)")
    }
}

function ConvertTo-BestSellersPortableBrandText {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Value)

    $portableValue = $Value -replace '^ +| +$', ''
    if ([string]::Equals($portableValue, 'KÄRCHER', [StringComparison]::OrdinalIgnoreCase)) {
        $portableValue = 'KARCHER'
    }
    if ($portableValue -cnotmatch '^[\x20-\x7e]+$') {
        throw 'Brand text is outside the portable normalization boundary.'
    }
    return ($portableValue -replace ' +', ' ')
}

function Normalize-V2BrandText {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return $null }
    return (ConvertTo-BestSellersPortableBrandText -Value $Value).ToLowerInvariant()
}

function Get-V2BrandAliasCatalog {
    param(
        [Parameter(Mandatory=$true)][string]$ConfigPath
    )

    $config = Read-V2JsonConfig -ConfigPath $ConfigPath
    if ($null -eq $config -or [string]$config.schema_version -ne 'brand-alias-config-v1') {
        throw 'Unsupported brand alias config version.'
    }
    if ($null -eq $config.PSObject.Properties['aliases']) {
        throw 'Brand alias config requires aliases.'
    }

    $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $normalizedAliases = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    foreach ($rule in @($config.aliases)) {
        if ($null -eq $rule) { throw 'Brand alias catalog contains an invalid rule.' }
        $id = [string]$rule.id
        $canonical = [string]$rule.canonical_name
        if ([string]::IsNullOrWhiteSpace($id) -or $id -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') {
            throw 'Brand alias rules require stable non-empty ids.'
        }
        if ([string]::IsNullOrWhiteSpace($canonical)) {
            throw "Brand alias rule '$id' requires a non-empty canonical_name."
        }
        $normalizedCanonical = ConvertTo-BestSellersPortableBrandText -Value $canonical
        if (-not [string]::Equals($normalizedCanonical, $canonical, [StringComparison]::Ordinal)) {
            throw "Brand alias rule '$id' canonical_name must already use portable normalized spacing."
        }
        if (-not $ids.Add($id)) {
            throw 'Brand alias catalog contains duplicate rule ids.'
        }
        if ($null -eq $rule.PSObject.Properties['aliases']) {
            throw "Brand alias rule '$id' requires aliases."
        }
        $ruleAliases = @($rule.aliases)
        if ($ruleAliases.Count -eq 0) {
            throw "Brand alias rule '$id' requires at least one alias."
        }
        $ruleNormalizedAliases = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($alias in $ruleAliases) {
            $normalizedAlias = Normalize-V2BrandText -Value ([string]$alias)
            if ([string]::IsNullOrWhiteSpace($normalizedAlias)) {
                throw "Brand alias rule '$id' contains an empty alias."
            }
            if (-not $ruleNormalizedAliases.Add($normalizedAlias)) { continue }
            if ($normalizedAliases.ContainsKey($normalizedAlias)) {
                throw 'Brand alias catalog contains an ambiguous normalized alias.'
            }
            $normalizedAliases[$normalizedAlias] = $id
        }
    }
    return $config
}

function Get-BestSellersBrandNormalization {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$RawBrand,
        [Parameter(Mandatory=$true)][ValidateSet('verified_metadata','manual_review','unknown')][string]$Source,
        [Parameter(Mandatory=$true)][string]$ConfigPath
    )

    $config = Get-V2BrandAliasCatalog -ConfigPath $ConfigPath
    if ($null -eq $RawBrand -or $RawBrand -cmatch '^ *$') {
        return [pscustomobject]@{ raw_brand=$null; normalized_brand=$null; normalized_key=$null; alias_rule_id=$null; source='unknown' }
    }
    if ($Source -eq 'unknown') { throw 'A raw brand requires a verified source.' }
    $raw = ConvertTo-BestSellersPortableBrandText -Value $RawBrand
    $key = $raw.ToLowerInvariant()
    $matched = @($config.aliases | Where-Object {
        @($_.aliases | ForEach-Object { Normalize-V2BrandText -Value ([string]$_) }) -contains $key
    })
    if ($matched.Count -eq 1) {
        $canonical = [string]$matched[0].canonical_name
        return [pscustomobject]@{ raw_brand=$raw; normalized_brand=$canonical; normalized_key=$canonical.ToLowerInvariant(); alias_rule_id=[string]$matched[0].id; source=$Source }
    }
    return [pscustomobject]@{ raw_brand=$raw; normalized_brand=$raw; normalized_key=$key; alias_rule_id=$null; source=$Source }
}

function Test-BestSellersExactTop30 {
    [CmdletBinding()]
    param(
        [object[]]$Items,
        [ValidateRange(1,100)][int]$TargetCount = 30
    )

    $rows = @($Items | Where-Object { $null -ne $_ })
    if ($rows.Count -ne $TargetCount) { return $false }

    $ranks = [System.Collections.Generic.HashSet[int]]::new()
    $asins = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $rows) {
        $rankProperty = $row.PSObject.Properties['rank']
        $asinProperty = $row.PSObject.Properties['asin']
        if ($null -eq $rankProperty -or $null -eq $asinProperty) { return $false }
        $rank = $rankProperty.Value
        $asin = [string]$asinProperty.Value
        if (-not ($rank -is [byte] -or $rank -is [int16] -or $rank -is [int32] -or $rank -is [int64])) { return $false }
        if ([int64]$rank -lt 1 -or [int64]$rank -gt $TargetCount) { return $false }
        if ([string]::IsNullOrWhiteSpace($asin) -or $asin -notmatch '^[A-Za-z0-9]{10}$') { return $false }
        [void]$ranks.Add([int]$rank)
        [void]$asins.Add($asin)
    }

    return $ranks.Count -eq $TargetCount -and $asins.Count -eq $TargetCount
}

function Get-BestSellersValidHistory {
    [CmdletBinding()]
    param(
        [object[]]$Snapshots,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string[]]$CategoryKeys,
        [ValidateRange(1,100)][Nullable[int]]$TargetCount,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )

    $registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
    $targets = @{}
    foreach ($categoryKey in $CategoryKeys) {
        $category = Get-BestSellersCategory -Registry $registry -CategoryKey $categoryKey
        $targets[$categoryKey] = if ($null -ne $TargetCount) { [int]$TargetCount } else { [int]$category.TargetCount }
    }
    return @($Snapshots | Where-Object {
            $snapshot = $_
            if ($null -eq $snapshot) { return $false }
            $persisted = $snapshot.PSObject.Properties['persisted_complete']
            if ($null -eq $persisted -or $persisted.Value -ne $true) { return $false }
            foreach ($categoryKey in $CategoryKeys) {
                $category = $snapshot.PSObject.Properties[$categoryKey]
                if ($null -eq $category -or -not (Test-BestSellersExactTop30 -Items @($category.Value) -TargetCount $targets[$categoryKey])) { return $false }
            }
            return $true
        } | Sort-Object { [string]$_.market_date })
}

function Get-BestSellersPreviousValidSnapshot {
    [CmdletBinding()]
    param(
        [object[]]$Snapshots,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string[]]$CategoryKeys,
        [Parameter(Mandatory=$true)][string]$CurrentMarketDate,
        [ValidateRange(1,100)][Nullable[int]]$TargetCount,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )

    $historyParameters = @{ Snapshots=$Snapshots; CategoryKeys=$CategoryKeys; RegistryPath=$RegistryPath }
    if ($null -ne $TargetCount) { $historyParameters.TargetCount = [int]$TargetCount }
    $eligible = @(Get-BestSellersValidHistory @historyParameters |
        Where-Object { [string]$_.market_date -lt $CurrentMarketDate } |
        Sort-Object { [string]$_.market_date })
    if ($eligible.Count -eq 0) { return $null }
    return $eligible[-1]
}

function Get-V2ObjectPropertyValue {
    param(
        $Object,
        [Parameter(Mandatory=$true)][string]$Name
    )

    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function New-BestSellersProductMetadataRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object[]]$Snapshots,
        [Parameter(Mandatory=$true)][ValidateSet('AMAZON_US')][string]$MarketplaceCode,
        [Parameter(Mandatory=$true)][string]$ClassificationConfigPath,
        [Parameter(Mandatory=$true)][string]$BrandAliasConfigPath,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )

    $registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
    $categoryPriority = @(Get-BestSellersCategoryKeys -Registry $registry -EnabledOnly)
    $products = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)

    foreach ($snapshot in @($Snapshots)) {
        if ($null -eq $snapshot -or (Get-V2ObjectPropertyValue -Object $snapshot -Name 'persisted_complete') -ne $true) { continue }
        $marketDate = [string](Get-V2ObjectPropertyValue -Object $snapshot -Name 'market_date')
        $parsedDate = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($marketDate, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsedDate)) { continue }
        $marketDate = $parsedDate.ToString('yyyy-MM-dd')

        for ($priority = 0; $priority -lt $categoryPriority.Count; $priority++) {
            $categoryKey = $categoryPriority[$priority]
            $items = @(Get-V2ObjectPropertyValue -Object $snapshot -Name $categoryKey)
            $category = Get-BestSellersCategory -Registry $registry -CategoryKey $categoryKey
            if (-not (Test-BestSellersExactTop30 -Items $items -TargetCount $category.TargetCount)) { continue }

            foreach ($item in $items) {
                $asin = ([string](Get-V2ObjectPropertyValue -Object $item -Name 'asin')).ToUpperInvariant()
                $productKey = "$MarketplaceCode|$asin"
                if (-not $products.ContainsKey($productKey)) {
                    $products[$productKey] = [pscustomobject]@{
                        asin = $asin
                        first_seen_market_date = $marketDate
                        last_seen_market_date = $marketDate
                        records = New-Object 'System.Collections.Generic.List[object]'
                    }
                }
                $product = $products[$productKey]
                if ($marketDate -lt $product.first_seen_market_date) { $product.first_seen_market_date = $marketDate }
                if ($marketDate -gt $product.last_seen_market_date) { $product.last_seen_market_date = $marketDate }
                $product.records.Add([pscustomobject]@{
                    market_date = $marketDate
                    priority = $priority
                    category_key = $categoryKey
                    item = $item
                })
            }
        }
    }

    $result = New-Object 'System.Collections.Generic.List[object]'
    foreach ($product in @($products.Values | Sort-Object asin)) {
        $records = @($product.records | Sort-Object @{ Expression = { $_.market_date }; Descending = $true }, @{ Expression = { $_.priority }; Ascending = $true })
        $latest = $records[0]
        $title = [string](Get-V2ObjectPropertyValue -Object $latest.item -Name 'title')
        $classification = Get-BestSellersProductClassification -Asin $product.asin -Title $title -CategoryKey $latest.category_key -ConfigPath $ClassificationConfigPath -RegistryPath $RegistryPath

        # Raw collector `brand` is intentionally ignored.  A value is eligible only
        # when both the dedicated raw field and an audited provenance are present.
        $rawBrand = Get-V2ObjectPropertyValue -Object $latest.item -Name 'raw_brand'
        $source = [string](Get-V2ObjectPropertyValue -Object $latest.item -Name 'brand_source')
        $brand = if (-not [string]::IsNullOrWhiteSpace([string]$rawBrand) -and $source -in @('verified_metadata', 'manual_review')) {
            Get-BestSellersBrandNormalization -RawBrand ([string]$rawBrand) -Source $source -ConfigPath $BrandAliasConfigPath
        }
        else {
            Get-BestSellersBrandNormalization -RawBrand $null -Source unknown -ConfigPath $BrandAliasConfigPath
        }

        $result.Add([pscustomobject]@{
            marketplace_code = $MarketplaceCode
            asin = $product.asin
            product_type = [string]$classification.product_type
            classification_confidence = [string]$classification.classification_confidence
            classification_rule_id = $classification.rule_id
            classification_rule_version = [string]$classification.rule_version
            classification_evidence = @($classification.evidence | ForEach-Object { [string]$_ })
            raw_brand = $brand.raw_brand
            normalized_brand = $brand.normalized_brand
            normalized_brand_key = $brand.normalized_key
            brand_alias_rule_id = $brand.alias_rule_id
            brand_source = [string]$brand.source
            first_seen_market_date = $product.first_seen_market_date
            last_seen_market_date = $product.last_seen_market_date
        })
    }

    return $result.ToArray()
}

Export-ModuleMember -Function ConvertTo-BestSellersPortableBrandText, Get-BestSellersProductClassification, Get-BestSellersBrandNormalization, Test-BestSellersExactTop30, Get-BestSellersValidHistory, Get-BestSellersPreviousValidSnapshot, New-BestSellersProductMetadataRows
