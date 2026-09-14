Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'BestSellersCategoryRegistry.psm1') -Scope Local

function Get-MarketStructureValue {
    param($Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function ConvertTo-MarketPrice {
    param($Value)
    if ($null -eq $Value) { return $null }
    $text = ([string]$Value) -replace '[^0-9.]', ''
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $number = 0.0
    if ([double]::TryParse($text, [Globalization.NumberStyles]::Number, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        return [math]::Round($number, 2)
    }
    return $null
}

function Get-MarketPriceBand {
    param([double]$Price)
    if ($Price -lt 25) { return 'UNDER_25' }
    if ($Price -lt 50) { return '25_TO_49_99' }
    if ($Price -lt 100) { return '50_TO_99_99' }
    if ($Price -lt 200) { return '100_TO_199_99' }
    return '200_PLUS'
}

function Get-AccessoryClassificationRules {
    return @(
        [pscustomobject]@{ type = 'SURFACE_CLEANER'; pattern = '\bsurface cleaner\b' },
        [pscustomobject]@{ type = 'FOAM_CANNON'; pattern = '\b(foam|soap) cannon\b|\bfoam gun\b' },
        [pscustomobject]@{ type = 'PRESSURE_WASHER_HOSE'; pattern = '\bpressure washer hose\b|\bhigh pressure hose\b' },
        [pscustomobject]@{ type = 'SPRAY_GUN_WAND'; pattern = '\b(pressure washer|spray|water) gun\b|\bspray wand\b|\bextension wand\b' },
        [pscustomobject]@{ type = 'SPRAY_NOZZLE'; pattern = '\b(spray|turbo) nozzle\b|\bnozzle tips?\b|\bnozzle set\b' },
        [pscustomobject]@{ type = 'ADAPTER_CONNECTOR'; pattern = '\badapters?\b|\bconnectors?\b|\bcouplers?\b|\bquick connect\b' },
        [pscustomobject]@{ type = 'REPLACEMENT_PARTS'; pattern = '\breplacement\b|\bo-ring\b|\bunloader\b|\bvalve\b|\bseal kit\b|\bpump head\b' }
    )
}

function New-BestSellersMarketStructureAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Snapshot,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )

    $registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
    $categoryNames = @(Get-BestSellersCategoryKeys -Registry $registry -EnabledOnly)
    $bandOrder = @('UNDER_25','25_TO_49_99','50_TO_99_99','100_TO_199_99','200_PLUS')
    $categories = @()
    foreach ($categoryName in $categoryNames) {
        $items = @((Get-MarketStructureValue -Object $Snapshot -Name $categoryName) | Where-Object { $null -ne $_ })
        $priced = @()
        foreach ($item in $items) {
            $price = ConvertTo-MarketPrice (Get-MarketStructureValue -Object $item -Name 'price')
            if ($null -ne $price) {
                $priced += [pscustomobject]@{ item = $item; price = $price; band = Get-MarketPriceBand -Price $price }
            }
        }
        $bands = @()
        foreach ($bandName in $bandOrder) {
            $members = @($priced | Where-Object { $_.band -eq $bandName })
            $ranks = @($members | ForEach-Object { [int](Get-MarketStructureValue -Object $_.item -Name 'rank') })
            $ratings = @($members | ForEach-Object { Get-MarketStructureValue -Object $_.item -Name 'rating' } | Where-Object { $null -ne $_ })
            $reviews = @($members | ForEach-Object { Get-MarketStructureValue -Object $_.item -Name 'reviews' } | Where-Object { $null -ne $_ })
            $bands += [pscustomobject]@{
                price_band = $bandName
                item_count = $members.Count
                share_of_priced_percent = if ($priced.Count -gt 0) { [math]::Round($members.Count * 100.0 / $priced.Count, 2) } else { 0 }
                top_10_count = @($ranks | Where-Object { $_ -le 10 }).Count
                average_rank = if ($ranks.Count -gt 0) { [math]::Round((($ranks | Measure-Object -Average).Average), 2) } else { $null }
                average_price = if ($members.Count -gt 0) { [math]::Round((($members.price | Measure-Object -Average).Average), 2) } else { $null }
                average_rating = if ($ratings.Count -gt 0) { [math]::Round((($ratings | Measure-Object -Average).Average), 2) } else { $null }
                median_reviews = if ($reviews.Count -gt 0) {
                    $sorted = @($reviews | Sort-Object)
                    if ($sorted.Count % 2 -eq 1) { [double]$sorted[[math]::Floor($sorted.Count / 2)] }
                    else { [math]::Round(([double]$sorted[$sorted.Count / 2 - 1] + [double]$sorted[$sorted.Count / 2]) / 2, 2) }
                } else { $null }
            }
        }
        $categories += [pscustomobject]@{
            category = $categoryName
            item_count = $items.Count
            priced_item_count = $priced.Count
            price_coverage_percent = if ($items.Count -gt 0) { [math]::Round($priced.Count * 100.0 / $items.Count, 2) } else { 0 }
            price_bands = $bands
            brand_analysis = [pscustomobject]@{
                status = if ($items.Count -eq 0) { 'NO_CATEGORY_DATA' } else { 'UNAVAILABLE_NO_VERIFIED_BRAND_FIELD' }
                verified_brand_count = 0
                concentration_metrics = $null
                note = 'Product titles are not treated as a verified brand field.'
            }
        }
    }

    $rules = Get-AccessoryClassificationRules
    $accessoryItems = @((Get-MarketStructureValue -Object $Snapshot -Name 'pressure_washer_accessories') | Where-Object { $null -ne $_ })
    $classifiedProducts = @()
    foreach ($item in $accessoryItems) {
        $title = [string](Get-MarketStructureValue -Object $item -Name 'title')
        $matchedTypes = @($rules | Where-Object { $title -match $_.pattern } | ForEach-Object { $_.type })
        $primaryType = if ($matchedTypes.Count -gt 0) { $matchedTypes[0] } else { 'UNCLASSIFIED' }
        $classifiedProducts += [pscustomobject]@{
            asin = [string](Get-MarketStructureValue -Object $item -Name 'asin')
            rank = [int](Get-MarketStructureValue -Object $item -Name 'rank')
            title = $title
            primary_type = $primaryType
            matched_types = $matchedTypes
            classification_basis = if ($matchedTypes.Count -gt 0) { 'TITLE_KEYWORD_MATCH' } else { 'NO_RULE_MATCH' }
        }
    }
    $typeSummaries = @()
    foreach ($typeName in @($rules.type + 'UNCLASSIFIED')) {
        $members = @($classifiedProducts | Where-Object { $_.primary_type -eq $typeName })
        $typeSummaries += [pscustomobject]@{
            accessory_type = $typeName
            item_count = $members.Count
            share_percent = if ($classifiedProducts.Count -gt 0) { [math]::Round($members.Count * 100.0 / $classifiedProducts.Count, 2) } else { 0 }
            best_rank = if ($members.Count -gt 0) { ($members.rank | Measure-Object -Minimum).Minimum } else { $null }
        }
    }

    return [pscustomobject]@{
        schema_version = 'best-sellers-market-structure-v1'
        model_version = 'market-structure-v1.0.0'
        generated_at = [DateTimeOffset]::UtcNow.ToString('o')
        market_date = [string](Get-MarketStructureValue -Object $Snapshot -Name 'market_date')
        price_band_policy = [pscustomobject]@{ currency = 'USD'; boundaries = @('<25','25-49.99','50-99.99','100-199.99','>=200') }
        categories = $categories
        accessory_analysis = [pscustomobject]@{
            status = if ($accessoryItems.Count -eq 0) { 'NO_CATEGORY_DATA' } else { 'ANALYZED' }
            item_count = $accessoryItems.Count
            classified_item_count = @($classifiedProducts | Where-Object { $_.primary_type -ne 'UNCLASSIFIED' }).Count
            classification_coverage_percent = if ($accessoryItems.Count -gt 0) { [math]::Round(@($classifiedProducts | Where-Object { $_.primary_type -ne 'UNCLASSIFIED' }).Count * 100.0 / $accessoryItems.Count, 2) } else { 0 }
            rules = @($rules | ForEach-Object { [pscustomobject]@{ accessory_type = $_.type; pattern = $_.pattern } })
            type_summaries = $typeSummaries
            products = $classifiedProducts
        }
    }
}

function Write-BestSellersMarketStructureArtifact {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Analysis, [Parameter(Mandatory = $true)][string]$Path)
    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, ($Analysis | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
    return (Resolve-Path -LiteralPath $Path).Path
}

Export-ModuleMember -Function New-BestSellersMarketStructureAnalysis, Write-BestSellersMarketStructureArtifact
