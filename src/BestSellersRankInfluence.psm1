Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'BestSellersCategoryRegistry.psm1') -Scope Local

function Get-RankInfluenceValue {
    param($Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function ConvertTo-RankInfluenceNumber {
    param($Value)
    if ($null -eq $Value) { return $null }
    $text = ([string]$Value) -replace '[^0-9.\-]', ''
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $number = 0.0
    if ([double]::TryParse($text, [Globalization.NumberStyles]::Number, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) { return $number }
    return $null
}

function ConvertTo-AverageRanks {
    param([double[]]$Values)
    $result = @()
    foreach ($value in $Values) {
        $less = @($Values | Where-Object { $_ -lt $value }).Count
        $equal = @($Values | Where-Object { $_ -eq $value }).Count
        $result += $less + (($equal + 1) / 2.0)
    }
    return ,$result
}

function Get-PearsonCorrelation {
    param([double[]]$X, [double[]]$Y)
    if ($X.Count -ne $Y.Count -or $X.Count -lt 2) { return $null }
    $meanX = ($X | Measure-Object -Average).Average
    $meanY = ($Y | Measure-Object -Average).Average
    $cross = 0.0; $squareX = 0.0; $squareY = 0.0
    for ($index = 0; $index -lt $X.Count; $index++) {
        $dx = $X[$index] - $meanX; $dy = $Y[$index] - $meanY
        $cross += $dx * $dy; $squareX += $dx * $dx; $squareY += $dy * $dy
    }
    if ($squareX -eq 0 -or $squareY -eq 0) { return $null }
    return [math]::Round($cross / [math]::Sqrt($squareX * $squareY), 4)
}

function Get-SpearmanCorrelation {
    param([double[]]$X, [double[]]$Y)
    if ($X.Count -ne $Y.Count -or $X.Count -lt 2) { return $null }
    return Get-PearsonCorrelation -X (ConvertTo-AverageRanks $X) -Y (ConvertTo-AverageRanks $Y)
}

function Get-AssociationStrength {
    param($Rho)
    if ($null -eq $Rho) { return 'UNAVAILABLE' }
    $absolute = [math]::Abs([double]$Rho)
    if ($absolute -lt 0.2) { return 'VERY_WEAK' }
    if ($absolute -lt 0.4) { return 'WEAK' }
    if ($absolute -lt 0.6) { return 'MODERATE' }
    if ($absolute -lt 0.8) { return 'STRONG' }
    return 'VERY_STRONG'
}

function New-RankAssociation {
    param([string]$Metric, $Pairs, [string]$OutcomeName, [int]$MinimumSample = 5)
    $validPairs = @($Pairs | Where-Object { $null -ne $_.x -and $null -ne $_.y })
    $rho = if ($validPairs.Count -ge $MinimumSample) {
        Get-SpearmanCorrelation -X @($validPairs | ForEach-Object { [double]$_.x }) -Y @($validPairs | ForEach-Object { [double]$_.y })
    } else { $null }
    return [pscustomobject]@{
        metric = $Metric
        outcome = $OutcomeName
        sample_size = $validPairs.Count
        minimum_sample_size = $MinimumSample
        status = if ($validPairs.Count -lt $MinimumSample) { 'INSUFFICIENT_SAMPLE' } elseif ($null -eq $rho) { 'NO_VARIANCE' } else { 'ANALYZED' }
        spearman_rho = $rho
        direction = if ($null -eq $rho) { 'UNAVAILABLE' } elseif ($rho -gt 0) { 'HIGHER_ASSOCIATED_WITH_BETTER_RANK' } elseif ($rho -lt 0) { 'HIGHER_ASSOCIATED_WITH_WORSE_RANK' } else { 'NO_MONOTONIC_ASSOCIATION' }
        strength = Get-AssociationStrength $rho
    }
}

function New-RankBucketSummary {
    param([string]$Metric, $Rows, [scriptblock]$BucketSelector)
    $summaries = @()
    foreach ($group in @($Rows | Group-Object { & $BucketSelector $_ })) {
        $members = @($group.Group)
        $summaries += [pscustomobject]@{
            metric = $Metric
            bucket = $group.Name
            item_count = $members.Count
            average_rank = [math]::Round((($members.rank | Measure-Object -Average).Average), 2)
            top_10_count = @($members | Where-Object { $_.rank -le 10 }).Count
            top_10_share_percent = [math]::Round(@($members | Where-Object { $_.rank -le 10 }).Count * 100.0 / $members.Count, 2)
        }
    }
    return @($summaries | Sort-Object bucket)
}

function New-BestSellersRankInfluenceAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Snapshot,
        $WeeklyAnalysis,
        [ValidateRange(3, 50)][int]$MinimumSample = 5,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )
    $registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
    $categoryNames = @(Get-BestSellersCategoryKeys -Registry $registry -EnabledOnly)
    $historyDayCount = if ($null -ne $WeeklyAnalysis) { [int](Get-RankInfluenceValue -Object $WeeklyAnalysis -Name 'snapshot_day_count') } else { 0 }
    $categoryResults = @()
    foreach ($categoryName in $categoryNames) {
        $items = @((Get-RankInfluenceValue -Object $Snapshot -Name $categoryName) | Where-Object { $null -ne $_ })
        $rows = @()
        foreach ($item in $items) {
            $rank = [int](Get-RankInfluenceValue -Object $item -Name 'rank')
            $reviews = ConvertTo-RankInfluenceNumber (Get-RankInfluenceValue -Object $item -Name 'reviews')
            $rows += [pscustomobject]@{
                rank = $rank
                rank_strength = 101 - $rank
                price = ConvertTo-RankInfluenceNumber (Get-RankInfluenceValue -Object $item -Name 'price')
                rating = ConvertTo-RankInfluenceNumber (Get-RankInfluenceValue -Object $item -Name 'rating')
                reviews = $reviews
                log_reviews = if ($null -ne $reviews) { [math]::Log10($reviews + 1) } else { $null }
            }
        }
        $associations = @(
            (New-RankAssociation -Metric 'PRICE_USD' -OutcomeName 'RANK_STRENGTH' -MinimumSample $MinimumSample -Pairs @($rows | ForEach-Object { [pscustomobject]@{ x=$_.price; y=$_.rank_strength } })),
            (New-RankAssociation -Metric 'RATING_STARS' -OutcomeName 'RANK_STRENGTH' -MinimumSample $MinimumSample -Pairs @($rows | ForEach-Object { [pscustomobject]@{ x=$_.rating; y=$_.rank_strength } })),
            (New-RankAssociation -Metric 'LOG10_REVIEW_COUNT_PLUS_1' -OutcomeName 'RANK_STRENGTH' -MinimumSample $MinimumSample -Pairs @($rows | ForEach-Object { [pscustomobject]@{ x=$_.log_reviews; y=$_.rank_strength } }))
        )
        $priceRows = @($rows | Where-Object { $null -ne $_.price })
        $ratingRows = @($rows | Where-Object { $null -ne $_.rating })
        $reviewRows = @($rows | Where-Object { $null -ne $_.reviews })
        $bucketSummaries = @()
        if ($priceRows.Count -gt 0) { $bucketSummaries += New-RankBucketSummary -Metric 'PRICE_USD' -Rows $priceRows -BucketSelector {
            param($row); if ($row.price -lt 25) {'UNDER_25'} elseif ($row.price -lt 50) {'25_TO_49_99'} elseif ($row.price -lt 100) {'50_TO_99_99'} elseif ($row.price -lt 200) {'100_TO_199_99'} else {'200_PLUS'}
        } }
        if ($ratingRows.Count -gt 0) { $bucketSummaries += New-RankBucketSummary -Metric 'RATING_STARS' -Rows $ratingRows -BucketSelector {
            param($row); if ($row.rating -lt 4) {'UNDER_4_0'} elseif ($row.rating -lt 4.3) {'4_0_TO_4_29'} elseif ($row.rating -lt 4.5) {'4_3_TO_4_49'} else {'4_5_PLUS'}
        } }
        if ($reviewRows.Count -gt 0) { $bucketSummaries += New-RankBucketSummary -Metric 'REVIEW_COUNT' -Rows $reviewRows -BucketSelector {
            param($row); if ($row.reviews -lt 100) {'UNDER_100'} elseif ($row.reviews -lt 1000) {'100_TO_999'} elseif ($row.reviews -lt 10000) {'1000_TO_9999'} else {'10000_PLUS'}
        } }

        $longitudinal = @()
        $weeklyCategory = if ($null -ne $WeeklyAnalysis) { @((Get-RankInfluenceValue -Object $WeeklyAnalysis -Name 'categories') | Where-Object { $_.category -eq $categoryName }) | Select-Object -First 1 } else { $null }
        $weeklyProducts = if ($historyDayCount -ge 2 -and $null -ne $weeklyCategory) { @((Get-RankInfluenceValue -Object $weeklyCategory -Name 'products')) } else { @() }
        $longitudinal += New-RankAssociation -Metric 'PRICE_CHANGE_USD' -OutcomeName 'WEEKLY_RANK_CHANGE' -MinimumSample $MinimumSample -Pairs @($weeklyProducts | ForEach-Object { [pscustomobject]@{ x=$_.price_change; y=$_.weekly_rank_change } })
        $longitudinal += New-RankAssociation -Metric 'REVIEW_GROWTH' -OutcomeName 'WEEKLY_RANK_CHANGE' -MinimumSample $MinimumSample -Pairs @($weeklyProducts | ForEach-Object { [pscustomobject]@{ x=$_.review_growth; y=$_.weekly_rank_change } })

        $categoryResults += [pscustomobject]@{
            category = $categoryName
            item_count = $items.Count
            field_coverage = [pscustomobject]@{
                price_percent = if ($items.Count -gt 0) { [math]::Round($priceRows.Count * 100.0 / $items.Count, 2) } else { 0 }
                rating_percent = if ($items.Count -gt 0) { [math]::Round($ratingRows.Count * 100.0 / $items.Count, 2) } else { 0 }
                review_count_percent = if ($items.Count -gt 0) { [math]::Round($reviewRows.Count * 100.0 / $items.Count, 2) } else { 0 }
            }
            cross_sectional_associations = $associations
            bucket_summaries = $bucketSummaries
            longitudinal_associations = $longitudinal
        }
    }
    return [pscustomobject]@{
        schema_version = 'best-sellers-rank-influence-v1'
        model_version = 'rank-influence-v1.0.0'
        generated_at = [DateTimeOffset]::UtcNow.ToString('o')
        market_date = [string](Get-RankInfluenceValue -Object $Snapshot -Name 'market_date')
        history_day_count = $historyDayCount
        method = [pscustomobject]@{
            cross_sectional = 'Spearman rank correlation against rank_strength=101-rank.'
            longitudinal = 'Spearman rank correlation between observed metric change and weekly_rank_change.'
            causal_warning = 'Observational association only. Amazon rank may influence reviews and visibility; product type, promotion and unobserved demand can confound results.'
            minimum_sample_size = $MinimumSample
        }
        categories = $categoryResults
    }
}

function Write-BestSellersRankInfluenceArtifact {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Analysis, [Parameter(Mandatory = $true)][string]$Path)
    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, ($Analysis | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
    return (Resolve-Path -LiteralPath $Path).Path
}

Export-ModuleMember -Function New-BestSellersRankInfluenceAnalysis, Write-BestSellersRankInfluenceArtifact
