$modulePath = Join-Path $PSScriptRoot '..\src\BestSellersDataSemantics.psm1'
Import-Module $modulePath -Force

function Test-SemanticsOperationThrows {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$Operation,
        [Parameter(Mandatory=$true)][string]$MessagePattern
    )

    $failure = $null
    try { & $Operation | Out-Null } catch { $failure = $_ }
    $failure | Should Not Be $null
    $failure.Exception.Message | Should Match $MessagePattern
}

Describe 'V2 product classification' {
    $configPath = Join-Path $PSScriptRoot '..\config\v2-product-classification.json'

    $cases = @(
        @{ Title='Westinghouse Electric Pressure Washer 2500 PSI'; Category='pressure_washers'; Type='electric_pressure_washer'; Confidence='high' },
        @{ Title='Gas Pressure Washer 3200 PSI'; Category='pressure_washers'; Type='gas_pressure_washer'; Confidence='high' },
        @{ Title='Cordless Battery Powered Pressure Washer'; Category='pressure_washers'; Type='cordless_pressure_washer'; Confidence='high' },
        @{ Title='15 Inch Pressure Washer Surface Cleaner'; Category='pressure_washers'; Type='surface_cleaner'; Confidence='high' },
        @{ Title='Pressure Washer Gun and Wand Kit'; Category='pressure_washers'; Type='pressure_washer_gun'; Confidence='high' },
        @{ Title='50 FT Pressure Washer Hose'; Category='pressure_washers'; Type='hose'; Confidence='high' },
        @{ Title='5 Pack Pressure Washer Nozzle Tips'; Category='pressure_washers'; Type='nozzle'; Confidence='high' },
        @{ Title='Pressure Washer Chemical Cleaner Concentrate'; Category='pressure_washers'; Type='chemical_cleaner'; Confidence='high' },
        @{ Title='Pressure Washer Detergent Cleaner Solution'; Category='pressure_washers'; Type='chemical_cleaner'; Confidence='high' },
        @{ Title='Pump Protector for Pressure Washers'; Category='pressure_washers'; Type='pump_protector'; Confidence='high' },
        @{ Title='Foam Cannon for Pressure Washer'; Category='pressure_washer_accessories'; Type='foam_cannon'; Confidence='high' },
        @{ Title='Pressure Washer Adapter Connector Kit'; Category='pressure_washer_accessories'; Type='adapter_connector'; Confidence='high' },
        @{ Title='Pressure Washer Extension Wand 18 Inch'; Category='pressure_washer_accessories'; Type='extension_wand'; Confidence='high' },
        @{ Title='Pressure Washer Sewer Jetter Kit 100 FT'; Category='pressure_washer_accessories'; Type='sewer_jetter'; Confidence='high' },
        @{ Title='Universal Pressure Washer Replacement Accessory'; Category='pressure_washer_accessories'; Type='other_accessory'; Confidence='medium' },
        @{ Title='Outdoor Cleaning Tool'; Category='pressure_washers'; Type='unknown'; Confidence='low' }
    )

    foreach ($case in $cases) {
        It "classifies $($case.Type)" {
            $result = Get-BestSellersProductClassification -Asin 'B000000001' -Title $case.Title -CategoryKey $case.Category -ConfigPath $configPath
            $result.product_type | Should Be $case.Type
            $result.classification_confidence | Should Be $case.Confidence
            $result.rule_version | Should Be 'product-rules-v4'
            @($result.evidence).Count | Should BeGreaterThan 0
        }
    }

    It 'applies the PRD strong machine priority before accessory words' {
        $result = Get-BestSellersProductClassification -Asin 'B000000001' -Title 'Westinghouse Electric Pressure Washer with Surface Cleaner Attachment' -CategoryKey 'pressure_washers' -ConfigPath $configPath
        $result.product_type | Should Be 'electric_pressure_washer'
        $result.classification_confidence | Should Be 'high'
    }

    It 'classifies an accessory when no strong machine phrase is present' {
        $result = Get-BestSellersProductClassification -Asin 'B000000001' -Title 'Pressure Washer Hose Replacement 50 FT' -CategoryKey 'pressure_washers' -ConfigPath $configPath
        $result.product_type | Should Be 'hose'
    }

    It 'returns unknown low for conflicting machine evidence' {
        $result = Get-BestSellersProductClassification -Asin 'B000000001' -Title 'Gas Electric Cordless Pressure Washer' -CategoryKey 'pressure_washers' -ConfigPath $configPath
        $result.product_type | Should Be 'unknown'
        $result.classification_confidence | Should Be 'low'
        @($result.evidence | Where-Object { $_ -like 'CONFLICT:*' }).Count | Should BeGreaterThan 0
    }

    $regressionCases = @(
        @{ Name='surface cleaner compatibility text'; Title='LidoDola 14 Inch Pressure Washer Surface Cleaner with 4 Wheels, for Gas and Electric Power Washer'; Category='pressure_washers'; Type='surface_cleaner' },
        @{ Name='surface cleaner attachment product'; Title='Westinghouse 15 Inch Pressure Washer Surface Cleaner Attachment for Gas and Electric Pressure Washers'; Category='pressure_washers'; Type='surface_cleaner' },
        @{ Name='gun bundled with nozzle tips'; Title='McKillans Short Pressure Washer Gun with Swivel, Includes Nozzle Tips'; Category='pressure_washers'; Type='pressure_washer_gun' },
        @{ Name='high pressure replacement hose'; Title='50 FT High Pressure Hose, Kink Resistant Replacement Hose for Pressure Washer'; Category='pressure_washers'; Type='hose' },
        @{ Name='turbo nozzle'; Title='Pressure Washer Turbo Nozzle, 4000 PSI Rotating Jet Nozzle'; Category='pressure_washers'; Type='nozzle' },
        @{ Name='pump saver synonym'; Title='STA-BIL Pump Protector and Pump Saver for Pressure Washer Storage'; Category='pressure_washers'; Type='pump_protector' },
        @{ Name='cordless portable washer'; Title='Cordless Portable Washer, Battery Operated Power Cleaner for Cars'; Category='pressure_washers'; Type='cordless_pressure_washer' },
        @{ Name='gas model'; Title='Westinghouse WPX3400 Gas Pressure Washer, 3400 PSI'; Category='pressure_washers'; Type='gas_pressure_washer' },
        @{ Name='electric power washer wording'; Title='Sun Joe Pressure Washer, Electric Power Washer, 2500 Max PSI'; Category='pressure_washers'; Type='electric_pressure_washer' }
    )

    foreach ($case in $regressionCases) {
        It "correctly classifies $($case.Name)" {
            $result = Get-BestSellersProductClassification -Asin 'B000000001' -Title $case.Title -CategoryKey $case.Category -ConfigPath $configPath
            $result.product_type | Should Be $case.Type
            $result.classification_confidence | Should Be 'high'
        }
    }

    $reviewedMachineCases = @(
        @{ Name='LWQ verified AC machine'; Asin='B0D739PX62'; RuleId='reviewed-asin-b0d739px62'; Evidence='AMAZON_PRODUCT_DETAIL:POWER_SOURCE=AC'; Title='Pressure Washer, Portable Power Washer, 4 Quick Connect Nozzles, High Pressure Cleaning Machine for Car Fence Driveway Patio Washing and More(Light Green)' },
        @{ Name='FOTING verified 1800W machine'; Asin='B0H87BHW4Y'; RuleId='reviewed-asin-b0h87bhw4y'; Evidence='AMAZON_PRODUCT_DETAIL:MOTOR=1800W'; Title='2026New Pressure Power Washer 5000PSI with Adjustable Touch Screen 8 Level, 34" Tall, 4 Quick Connect Nozzles,Inlet Hose&Filter&500mlFoam Cannon for Cars/Fences/Driveways/Home Cleaning(Yellow)' },
        @{ Name='MZK verified electric machine'; Asin='B0H8P3JVTP'; RuleId='reviewed-asin-b0h8p3jvtp'; Evidence='AMAZON_PRODUCT_DETAIL:POWER_SOURCE=ELECTRIC'; Title='MZK Lightweight Pressure Washer, Portable Power Cleaner with Foam Cannon | High Pressure Cleaning Machine with 4 nozzles for cars, patios, fences, driveways, and home outdoor cleaning.' }
    )
    foreach ($case in $reviewedMachineCases) {
        It "classifies reviewed product detail evidence: $($case.Name)" {
            $result = Get-BestSellersProductClassification -Asin $case.Asin -Title $case.Title -CategoryKey 'pressure_washers' -ConfigPath $configPath

            $result.product_type | Should Be 'electric_pressure_washer'
            $result.classification_confidence | Should Be 'high'
            $result.rule_version | Should Be 'product-rules-v4'
            $result.rule_id | Should Be $case.RuleId
            @($result.evidence).Count | Should Be 1
            $result.evidence[0] | Should Be $case.Evidence
        }
    }

    It 'limits a reviewed machine override to its audited category' {
        $result = Get-BestSellersProductClassification -Asin 'B0D739PX62' -Title '50 FT Pressure Washer Hose Replacement' -CategoryKey 'pressure_washer_accessories' -ConfigPath $configPath

        $result.product_type | Should Be 'hose'
        $result.rule_id | Should Be 'accessory-hose'
    }

    It 'rejects a reviewed override scoped to an unsupported category' {
        $invalidConfigPath = Join-Path $TestDrive 'invalid-reviewed-override.json'
        $invalidConfig = [ordered]@{
            schema_version = 'product-classification-config-v1'
            rule_version = 'product-rules-test'
            reviewed_asin_overrides = @([ordered]@{
                id = 'reviewed-asin-b000000001'
                asin = 'B000000001'
                product_type = 'electric_pressure_washer'
                confidence = 'high'
                category_keys = @('unsupported_category')
                evidence = @('AMAZON_PRODUCT_DETAIL:POWER_SOURCE=AC')
                source_url = 'https://www.amazon.com/dp/B000000001'
                reviewed_on = '2026-09-01'
            })
            rules = @()
        }
        [IO.File]::WriteAllText($invalidConfigPath,($invalidConfig | ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))

        Test-SemanticsOperationThrows -Operation {
            Get-BestSellersProductClassification -Asin 'B000000001' -Title 'Pressure Washer' -CategoryKey 'pressure_washers' -ConfigPath $invalidConfigPath
        } -MessagePattern 'contains an unsupported category'
    }

    It 'keeps Product Type independent when a machine appears in the accessories Amazon market' {
        $result = Get-BestSellersProductClassification -Asin 'B000000001' -Title 'Electric Pressure Washer 2100 PSI' -CategoryKey 'pressure_washer_accessories' -ConfigPath $configPath
        $result.product_type | Should Be 'electric_pressure_washer'
        $result.classification_confidence | Should Be 'high'
    }

    It 'rejects an unsupported input category before classification' {
        Test-SemanticsOperationThrows -Operation {
            Get-BestSellersProductClassification -Asin 'B000000001' -Title 'Pressure Washer' -CategoryKey 'unsupported_category' -ConfigPath $configPath
        } -MessagePattern 'Unknown or disabled category key'
    }

    $nonCanonicalOverrideCases = @(
        @{ Name='product type'; ProductType='Electric_Pressure_Washer'; Confidence='high'; Category='pressure_washers' },
        @{ Name='confidence'; ProductType='electric_pressure_washer'; Confidence='High'; Category='pressure_washers' },
        @{ Name='category'; ProductType='electric_pressure_washer'; Confidence='high'; Category='PRESSURE_WASHERS' }
    )
    foreach ($case in $nonCanonicalOverrideCases) {
        It "rejects non-canonical reviewed override $($case.Name) casing" {
            $invalidConfigPath = Join-Path $TestDrive "invalid-reviewed-override-$($case.Name -replace ' ','-').json"
            $invalidConfig = [ordered]@{
                schema_version = 'product-classification-config-v1'
                rule_version = 'product-rules-test'
                reviewed_asin_overrides = @([ordered]@{
                    id = 'reviewed-asin-b000000001'
                    asin = 'B000000001'
                    product_type = $case.ProductType
                    confidence = $case.Confidence
                    category_keys = @($case.Category)
                    evidence = @('AMAZON_PRODUCT_DETAIL:POWER_SOURCE=AC')
                    source_url = 'https://www.amazon.com/dp/B000000001'
                    reviewed_on = '2026-09-01'
                })
                rules = @()
            }
            [IO.File]::WriteAllText($invalidConfigPath,($invalidConfig | ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))

            Test-SemanticsOperationThrows -Operation {
                Get-BestSellersProductClassification -Asin 'B000000001' -Title 'Pressure Washer' -CategoryKey 'pressure_washers' -ConfigPath $invalidConfigPath
            } -MessagePattern 'invalid ASIN or classification|unsupported category'
        }
    }

    It 'supports an older valid config with no reviewed override collection' {
        $legacyConfigPath = Join-Path $TestDrive 'legacy-config-without-reviewed-overrides.json'
        $legacyConfig = [ordered]@{
            schema_version = 'product-classification-config-v1'
            rule_version = 'product-rules-legacy'
            rules = @()
        }
        [IO.File]::WriteAllText($legacyConfigPath,($legacyConfig | ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))

        $result = Get-BestSellersProductClassification -Asin 'B000000001' -Title 'Outdoor Cleaning Tool' -CategoryKey 'pressure_washers' -ConfigPath $legacyConfigPath

        $result.product_type | Should Be 'unknown'
        $result.rule_version | Should Be 'product-rules-legacy'
    }

    It 'does not treat the word electricity as electric machine evidence' {
        $result = Get-BestSellersProductClassification -Asin 'B000000001' -Title 'Hose Hawk Pro Pressure Washer, No Electricity Needed High Pressure Washer Gun' -CategoryKey 'pressure_washers' -ConfigPath $configPath
        $result.product_type | Should Be 'pressure_washer_gun'
    }

    It 'keeps genuinely ambiguous product identity unknown' {
        $result = Get-BestSellersProductClassification -Asin 'B000000001' -Title 'Universal Outdoor Cleaning Power Tool Kit' -CategoryKey 'pressure_washers' -ConfigPath $configPath
        $result.product_type | Should Be 'unknown'
        $result.classification_confidence | Should Be 'low'
    }

    $otherAccessoryCases = @(
        'Water Pressure Test Gauge for Home and Garden Hose',
        'Pressure Washer O-Rings and Garden Hose Washers Rubber Kit'
    )
    foreach ($title in $otherAccessoryCases) {
        It "classifies a clear other accessory: $title" {
            $result = Get-BestSellersProductClassification -Asin 'B000000001' -Title $title -CategoryKey 'pressure_washer_accessories' -ConfigPath $configPath
            $result.product_type | Should Be 'other_accessory'
            $result.classification_confidence | Should Be 'medium'
        }
    }
}

Describe 'V2 brand normalization' {
    $configPath = Join-Path $PSScriptRoot '..\config\v2-brand-aliases.json'

    It 'normalizes case whitespace and an audited alias without changing raw brand' {
        $result = Get-BestSellersBrandNormalization -RawBrand '  WESTINGHOUSE Outdoor Power Equipment ' -Source verified_metadata -ConfigPath $configPath
        $result.raw_brand | Should Be 'WESTINGHOUSE Outdoor Power Equipment'
        $result.normalized_brand | Should Be 'Westinghouse'
        $result.normalized_key | Should Be 'westinghouse'
        $result.alias_rule_id | Should Be 'brand-westinghouse'
    }

    It 'folds only portable ASCII spaces for an unaliased brand' {
        $result = Get-BestSellersBrandNormalization -RawBrand '  ACME   Tools  ' -Source verified_metadata -ConfigPath $configPath

        $result.raw_brand | Should Be 'ACME Tools'
        $result.normalized_brand | Should Be 'ACME Tools'
        $result.normalized_key | Should Be 'acme tools'
        $result.alias_rule_id | Should Be $null
    }

    It 'maps the audited KARCHER umlaut spelling to the portable brand contract' {
        $result = Get-BestSellersBrandNormalization -RawBrand 'KÄRCHER' -Source verified_metadata -ConfigPath $configPath

        $result.raw_brand | Should Be 'KARCHER'
        $result.normalized_brand | Should Be 'KARCHER'
        $result.normalized_key | Should Be 'karcher'
    }

    It 'rejects BOM dotted-I and NEL brand text instead of folding it' {
        $invalidBrands = @(
            ([string][char]0xFEFF + 'Brand'),
            ([string][char]0x0130 + 'stanbul'),
            ('Brand' + [char]0x0085 + 'Name')
        )

        foreach ($brand in $invalidBrands) {
            $failure = $null
            try { Get-BestSellersBrandNormalization -RawBrand $brand -Source verified_metadata -ConfigPath $configPath | Out-Null } catch { $failure = $_ }
            $failure | Should Not Be $null
            $failure.Exception.Message | Should Be 'Brand text is outside the portable normalization boundary.'
        }
    }

    It 'rejects a non-portable canonical brand in the alias catalog' {
        $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $config.aliases[0].canonical_name = 'West' + [char]0x0130 + 'nghouse'
        $invalidPath = Join-Path $TestDrive 'v2-brand-aliases-nonportable-canonical.json'
        [IO.File]::WriteAllText($invalidPath, ($config | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))

        $failure = $null
        try { Get-BestSellersBrandNormalization -RawBrand 'Westinghouse' -Source verified_metadata -ConfigPath $invalidPath | Out-Null } catch { $failure = $_ }
        $failure | Should Not Be $null
        $failure.Exception.Message | Should Be 'Brand text is outside the portable normalization boundary.'
    }

    It 'returns unknown when no verified raw brand exists' {
        $result = Get-BestSellersBrandNormalization -RawBrand $null -Source unknown -ConfigPath $configPath
        $result.raw_brand | Should Be $null
        $result.normalized_brand | Should Be $null
        $result.source | Should Be 'unknown'
    }

    It 'rejects a raw brand whose source is unknown' {
        $threw = $false
        try { & Get-BestSellersBrandNormalization -RawBrand 'Westinghouse' -Source unknown -ConfigPath $configPath } catch { $threw = $true }
        $threw | Should Be $true
    }

    It 'rejects an ambiguous alias catalog before applying any alias' {
        $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $config.aliases += [pscustomobject]@{
            id = 'brand-conflict'
            canonical_name = 'Conflicting Brand'
            aliases = @('westinghouse')
        }
        $conflictingPath = Join-Path $TestDrive 'v2-brand-aliases-conflict.json'
        $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $conflictingPath -Encoding UTF8

        $threw = $false
        try { & Get-BestSellersBrandNormalization -RawBrand 'Unrelated Brand' -Source verified_metadata -ConfigPath $conflictingPath } catch { $threw = $true }
        $threw | Should Be $true
    }

    It 'does not infer a brand from a title because only raw verified brand is accepted' {
        $result = Get-BestSellersBrandNormalization -RawBrand $null -Source unknown -ConfigPath $configPath
        $result.normalized_brand | Should Be $null
    }
}

Describe 'V2 valid market days' {
    function New-Day($date, $complete = $true) {
        $rows = 1..30 | ForEach-Object {
            [pscustomobject]@{
                rank = $_
                asin = ('B' + $_.ToString('000000000'))
                title = 'x'
                price = $null
                rating = $null
                reviews = $null
            }
        }
        [pscustomobject]@{ market_date = $date; persisted_complete = $complete; pressure_washers = $rows }
    }

    It 'skips a failed day and returns the previous valid snapshot' {
        $history = @(New-Day '2026-08-18'; New-Day '2026-08-19' $false; New-Day '2026-08-20')
        $previous = Get-BestSellersPreviousValidSnapshot -Snapshots $history -CategoryKeys @('pressure_washers') -CurrentMarketDate '2026-08-20'

        $previous.market_date | Should Be '2026-08-18'
    }

    It 'rejects a persisted-incomplete day even when it contains thirty valid rows' {
        $history = @(New-Day '2026-08-18'; New-Day '2026-08-19' $false; New-Day '2026-08-20')
        $validDates = @(Get-BestSellersValidHistory -Snapshots $history -CategoryKeys @('pressure_washers') | ForEach-Object market_date)

        $validDates | Should Be @('2026-08-18', '2026-08-20')
    }

    It 'keeps a ranking day valid when optional metrics are null' {
        $day = New-Day '2026-08-20'

        (Test-BestSellersExactTop30 -Items $day.pressure_washers) | Should Be $true
    }
}

Describe 'V2 product metadata rows' {
    $classificationPath = Join-Path $PSScriptRoot '..\config\v2-product-classification.json'
    $brandPath = Join-Path $PSScriptRoot '..\config\v2-brand-aliases.json'

    function New-MetadataCategoryRows {
        param(
            [string]$Title,
            [string]$SharedAsin = 'B000000001',
            [hashtable]$SharedProperties = @{}
        )

        return @(1..30 | ForEach-Object {
                $row = [ordered]@{
                    rank = $_
                    asin = if ($_ -eq 1) { $SharedAsin } else { 'B' + ($_ + 100).ToString('000000000') }
                    title = if ($_ -eq 1) { $Title } else { "Other product $_" }
                    price = $null
                    rating = $null
                    reviews = $null
                }
                if ($_ -eq 1) {
                    foreach ($name in $SharedProperties.Keys) { $row[$name] = $SharedProperties[$name] }
                }
                [pscustomobject]$row
            })
    }

    function New-MetadataSnapshot {
        param(
            [string]$Date,
            [bool]$PersistedComplete = $true,
            [hashtable]$PressureSharedProperties = @{}
        )

        return [pscustomobject]@{
            market_date = $Date
            persisted_complete = $PersistedComplete
            pressure_washers = New-MetadataCategoryRows -Title 'Gas Pressure Washer 3200 PSI' -SharedProperties $PressureSharedProperties
            pressure_washer_accessories = New-MetadataCategoryRows -Title 'Pressure Washer Hose Replacement 50 FT'
            sump_pumps = New-MetadataCategoryRows -Title 'Sump Pump 1/2 HP'
        }
    }

    It 'deduplicates verified exact Top 30 history and excludes failed days from first and last seen' {
        $day18 = New-MetadataSnapshot -Date '2026-08-18'
        $day19 = New-MetadataSnapshot -Date '2026-08-19' -PersistedComplete $false
        $day20 = New-MetadataSnapshot -Date '2026-08-20'

        $rows = New-BestSellersProductMetadataRows -Snapshots @($day20, $day19, $day18) -MarketplaceCode AMAZON_US -ClassificationConfigPath $classificationPath -BrandAliasConfigPath $brandPath
        $product = @($rows | Where-Object asin -eq 'B000000001')

        $product.Count | Should Be 1
        $product[0].first_seen_market_date | Should Be '2026-08-18'
        $product[0].last_seen_market_date | Should Be '2026-08-20'
        $product[0].product_type | Should Be 'gas_pressure_washer'
        $product[0].brand_source | Should Be 'unknown'
        $product[0].raw_brand | Should Be $null
        $product[0].normalized_brand | Should Be $null
        $product[0].normalized_brand_key | Should Be $null
        $product[0].brand_alias_rule_id | Should Be $null
    }

    It 'uses a brand only when an explicit raw brand and verified provenance are both present' {
        $snapshot = New-MetadataSnapshot -Date '2026-08-20' -PressureSharedProperties @{
            raw_brand = 'WESTINGHOUSE Outdoor Power Equipment'
            brand_source = 'verified_metadata'
            brand = 'Ignored Snapshot Brand'
        }

        $product = @(New-BestSellersProductMetadataRows -Snapshots @($snapshot) -MarketplaceCode AMAZON_US -ClassificationConfigPath $classificationPath -BrandAliasConfigPath $brandPath | Where-Object asin -eq 'B000000001')[0]

        $product.raw_brand | Should Be 'WESTINGHOUSE Outdoor Power Equipment'
        $product.normalized_brand | Should Be 'Westinghouse'
        $product.normalized_brand_key | Should Be 'westinghouse'
        $product.brand_alias_rule_id | Should Be 'brand-westinghouse'
        $product.brand_source | Should Be 'verified_metadata'
        $product.first_seen_market_date | Should Be '2026-08-20'
        $product.last_seen_market_date | Should Be '2026-08-20'
    }
}
