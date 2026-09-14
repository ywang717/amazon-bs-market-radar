Set-StrictMode -Version Latest

function Get-OpportunityPropertyValue {
    param($Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Limit-OpportunityScore {
    param([double]$Value)
    return [math]::Round([math]::Max(0, [math]::Min(100, $Value)), 2)
}

function New-BestSellersOpportunityAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$WeeklyAnalysis,
        [ValidateRange(2, 30)][int]$RequiredHistoryDays = 7
    )
    $snapshotDayCount = [int](Get-OpportunityPropertyValue -Object $WeeklyAnalysis -Name 'snapshot_day_count')
    if ($snapshotDayCount -lt 1) { throw 'Weekly analysis must contain at least one snapshot day.' }

    $weights = [ordered]@{
        rank_growth = 30
        review_velocity = 20
        rating = 15
        new_entry_signal = 15
        brand_growth = 20
    }
    $categoryResults = @()

    foreach ($category in @((Get-OpportunityPropertyValue -Object $WeeklyAnalysis -Name 'categories'))) {
        if ($null -eq $category) { continue }
        $categoryName = [string](Get-OpportunityPropertyValue -Object $category -Name 'category')
        $products = @()
        foreach ($product in @((Get-OpportunityPropertyValue -Object $category -Name 'products'))) {
            if ($null -eq $product) { continue }
            $componentScores = [ordered]@{
                rank_growth = $null
                review_velocity = $null
                rating = $null
                new_entry_signal = $null
                brand_growth = $null
            }
            $evidence = [ordered]@{}
            $availableWeight = 0
            $weightedTotal = 0.0
            $daysInChart = [int](Get-OpportunityPropertyValue -Object $product -Name 'days_in_chart')
            $weeklyRankChange = Get-OpportunityPropertyValue -Object $product -Name 'weekly_rank_change'
            if ($null -ne $weeklyRankChange -and $snapshotDayCount -ge 2) {
                $componentScores.rank_growth = Limit-OpportunityScore (([double]$weeklyRankChange / 20.0) * 100.0)
                $availableWeight += $weights.rank_growth
                $weightedTotal += $componentScores.rank_growth * $weights.rank_growth
                $evidence.weekly_rank_change = [int]$weeklyRankChange
            }

            $reviewGrowth = Get-OpportunityPropertyValue -Object $product -Name 'review_growth'
            if ($null -ne $reviewGrowth -and $daysInChart -ge 2) {
                $reviewVelocity = [math]::Round(([double]$reviewGrowth / [math]::Max(1, $daysInChart - 1)), 2)
                $componentScores.review_velocity = Limit-OpportunityScore (($reviewVelocity / 10.0) * 100.0)
                $availableWeight += $weights.review_velocity
                $weightedTotal += $componentScores.review_velocity * $weights.review_velocity
                $evidence.review_growth = [long]$reviewGrowth
                $evidence.reviews_per_observed_day = $reviewVelocity
            }

            $rating = Get-OpportunityPropertyValue -Object $product -Name 'rating_end'
            if ($null -ne $rating) {
                $componentScores.rating = Limit-OpportunityScore ((([double]$rating - 3.5) / 1.5) * 100.0)
                $availableWeight += $weights.rating
                $weightedTotal += $componentScores.rating * $weights.rating
                $evidence.rating = [double]$rating
            }

            $status = [string](Get-OpportunityPropertyValue -Object $product -Name 'status')
            if ($snapshotDayCount -ge 2) {
                $componentScores.new_entry_signal = if ($status -eq 'NEW_IN_WEEK' -or $status -eq 'REENTERED') { 100.0 } else { 0.0 }
                $availableWeight += $weights.new_entry_signal
                $weightedTotal += $componentScores.new_entry_signal * $weights.new_entry_signal
                $evidence.chart_status = $status
            }

            # Brand growth stays unavailable until a verified brand field and history exist.
            $brandGrowthScore = Get-OpportunityPropertyValue -Object $product -Name 'brand_growth_score'
            if ($null -ne $brandGrowthScore) {
                $componentScores.brand_growth = Limit-OpportunityScore ([double]$brandGrowthScore)
                $availableWeight += $weights.brand_growth
                $weightedTotal += $componentScores.brand_growth * $weights.brand_growth
            }

            $observedScore = if ($availableWeight -gt 0) { [math]::Round($weightedTotal / $availableWeight, 2) } else { $null }
            $historyCoverage = [math]::Min(1.0, $snapshotDayCount / [double]$RequiredHistoryDays)
            $confidence = [math]::Round($availableWeight * $historyCoverage, 2)
            $classification = if ($snapshotDayCount -lt 2) { 'BASELINE_INSUFFICIENT' }
                elseif ($confidence -lt 50) { 'LOW_CONFIDENCE' }
                elseif ($observedScore -ge 70) { 'HIGH_OPPORTUNITY' }
                elseif ($observedScore -ge 45) { 'MEDIUM_OPPORTUNITY' }
                else { 'LOW_OPPORTUNITY' }

            $signals = @()
            $endRank = Get-OpportunityPropertyValue -Object $product -Name 'end_rank'
            $reviewsEnd = Get-OpportunityPropertyValue -Object $product -Name 'reviews_end'
            $maxDailyChange = Get-OpportunityPropertyValue -Object $product -Name 'max_daily_absolute_change'
            if ($null -ne $weeklyRankChange -and [int]$weeklyRankChange -ge 20) { $signals += 'FAST_RISING' }
            if ($null -ne $endRank -and [int]$endRank -le 20 -and $null -ne $reviewsEnd -and [long]$reviewsEnd -le 500) { $signals += 'HIGH_RANK_LOW_REVIEW' }
            if ($status -eq 'NEW_IN_WEEK') { $signals += 'NEW_CHART_ENTRY' }
            if ($status -eq 'REENTERED') { $signals += 'REENTERED_CHART' }
            if ($null -ne $maxDailyChange -and [int]$maxDailyChange -ge 20) { $signals += 'HIGH_VOLATILITY' }
            if ($evidence.Contains('reviews_per_observed_day') -and [double]$evidence.reviews_per_observed_day -ge 10) { $signals += 'REVIEW_SURGE' }

            $missingDimensions = @($componentScores.Keys | Where-Object { $null -eq $componentScores[$_] })
            $products += [pscustomobject]@{
                category = $categoryName
                asin = [string](Get-OpportunityPropertyValue -Object $product -Name 'asin')
                title = [string](Get-OpportunityPropertyValue -Object $product -Name 'title')
                url = [string](Get-OpportunityPropertyValue -Object $product -Name 'url')
                end_rank = $endRank
                observed_score = $observedScore
                confidence_percent = $confidence
                available_weight_percent = $availableWeight
                classification = $classification
                components = [pscustomobject]$componentScores
                signals = $signals
                missing_dimensions = $missingDimensions
                evidence = [pscustomobject]$evidence
            }
        }
        $sortedProducts = @($products | Sort-Object @{ Expression = { if ($null -eq $_.observed_score) { -1 } else { -1 * $_.observed_score } } }, end_rank, asin)
        $categoryResults += [pscustomobject]@{
            category = $categoryName
            product_count = $sortedProducts.Count
            high_opportunity_count = @($sortedProducts | Where-Object { $_.classification -eq 'HIGH_OPPORTUNITY' }).Count
            medium_opportunity_count = @($sortedProducts | Where-Object { $_.classification -eq 'MEDIUM_OPPORTUNITY' }).Count
            low_confidence_count = @($sortedProducts | Where-Object { $_.classification -eq 'LOW_CONFIDENCE' -or $_.classification -eq 'BASELINE_INSUFFICIENT' }).Count
            products = $sortedProducts
        }
    }

    return [pscustomobject]@{
        schema_version = 'best-sellers-opportunity-analysis-v1'
        model_version = 'opportunity-score-v1.0.0'
        generated_at = [DateTimeOffset]::UtcNow.ToString('o')
        period_start = Get-OpportunityPropertyValue -Object $WeeklyAnalysis -Name 'period_start'
        period_end = Get-OpportunityPropertyValue -Object $WeeklyAnalysis -Name 'period_end'
        snapshot_day_count = $snapshotDayCount
        required_history_days = $RequiredHistoryDays
        coverage_complete = [bool](Get-OpportunityPropertyValue -Object $WeeklyAnalysis -Name 'coverage_complete')
        score_policy = [pscustomobject]@{
            weights = [pscustomobject]$weights
            missing_value_policy = 'Skip unavailable dimensions; normalize observed score over available weight; reduce confidence by missing weight and history coverage.'
            classification_policy = 'No opportunity label when fewer than 2 days or confidence below 50 percent.'
        }
        categories = $categoryResults
    }
}

function Write-BestSellersOpportunityArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Analysis,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, ($Analysis | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
    return (Resolve-Path -LiteralPath $Path).Path
}

Export-ModuleMember -Function New-BestSellersOpportunityAnalysis, Write-BestSellersOpportunityArtifact
