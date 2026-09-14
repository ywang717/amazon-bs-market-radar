Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'BestSellersCategoryRegistry.psm1') -Scope Local

function Get-WeeklyBestSellersCategoryNames {
    param([string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json'))
    $registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
    return @(Get-BestSellersCategoryKeys -Registry $registry -EnabledOnly)
}

function Get-WeeklyBestSellersPropertyValue {
    param($Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function New-WeeklyBestSellersItemMap {
    param($Items)
    $map = @{}
    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        $asin = [string](Get-WeeklyBestSellersPropertyValue -Object $item -Name 'asin')
        if (-not [string]::IsNullOrWhiteSpace($asin) -and -not $map.ContainsKey($asin)) { $map[$asin] = $item }
    }
    return $map
}

function ConvertTo-WeeklyPriceAmount {
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

function ConvertTo-WeeklyDiscountList {
    param($Discounts)
    $normalized = @()
    foreach ($discount in @($Discounts)) {
        if ($null -eq $discount) { continue }
        $normalized += [pscustomobject]@{
            kind = [string](Get-WeeklyBestSellersPropertyValue -Object $discount -Name 'kind')
            amount = [string](Get-WeeklyBestSellersPropertyValue -Object $discount -Name 'amount')
        }
    }
    return @($normalized)
}

function Test-WeeklyDiscountListsEqual {
    param($PreviousDiscounts, $Discounts)
    $previous = @(ConvertTo-WeeklyDiscountList $PreviousDiscounts)
    $current = @(ConvertTo-WeeklyDiscountList $Discounts)
    if ($previous.Count -ne $current.Count) { return $false }
    for ($index = 0; $index -lt $previous.Count; $index++) {
        if ($previous[$index].kind -ne $current[$index].kind -or $previous[$index].amount -ne $current[$index].amount) { return $false }
    }
    return $true
}

function New-BestSellersWeeklyAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Snapshots,
        [ValidateRange(1, 100)][int]$SwingThreshold = 10,
        [ValidateRange(1, 100)][int]$HighPriorityThreshold = 20,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )
    if ($HighPriorityThreshold -lt $SwingThreshold) { throw 'HighPriorityThreshold must be greater than or equal to SwingThreshold.' }
    $ordered = @($Snapshots | Where-Object { $null -ne $_ } | Sort-Object { [string](Get-WeeklyBestSellersPropertyValue -Object $_ -Name 'market_date') })
    if ($ordered.Count -eq 0) { throw 'At least one Best Sellers snapshot is required.' }
    $dates = @($ordered | ForEach-Object { [string](Get-WeeklyBestSellersPropertyValue -Object $_ -Name 'market_date') })
    $largeSwings = @()
    $newEntries = @()
    $exits = @()
    $discountTransitions = @()
    $categoryResults = @()

    foreach ($categoryName in Get-WeeklyBestSellersCategoryNames -RegistryPath $RegistryPath) {
        $discountSummary = [ordered]@{ added_count = 0; removed_count = 0; amount_changed_count = 0; unchanged_count = 0; unknown_count = 0 }
        $presentSnapshots = @($ordered | Where-Object { $null -ne $_.PSObject.Properties[$categoryName] })
        $productHistory = @{}
        foreach ($snapshot in $presentSnapshots) {
            $date = [string](Get-WeeklyBestSellersPropertyValue -Object $snapshot -Name 'market_date')
            foreach ($item in @((Get-WeeklyBestSellersPropertyValue -Object $snapshot -Name $categoryName))) {
                if ($null -eq $item) { continue }
                $asin = [string](Get-WeeklyBestSellersPropertyValue -Object $item -Name 'asin')
                if ([string]::IsNullOrWhiteSpace($asin)) { continue }
                if (-not $productHistory.ContainsKey($asin)) { $productHistory[$asin] = @() }
                $productHistory[$asin] += [pscustomobject]@{ market_date = $date; item = $item }
            }
        }

        for ($index = 1; $index -lt $ordered.Count; $index++) {
            $previousSnapshot = $ordered[$index - 1]
            $currentSnapshot = $ordered[$index]
            if ($null -eq $previousSnapshot.PSObject.Properties[$categoryName] -or $null -eq $currentSnapshot.PSObject.Properties[$categoryName]) { continue }
            $previousDate = [string](Get-WeeklyBestSellersPropertyValue -Object $previousSnapshot -Name 'market_date')
            $currentDate = [string](Get-WeeklyBestSellersPropertyValue -Object $currentSnapshot -Name 'market_date')
            $previousMap = New-WeeklyBestSellersItemMap -Items (Get-WeeklyBestSellersPropertyValue -Object $previousSnapshot -Name $categoryName)
            $currentMap = New-WeeklyBestSellersItemMap -Items (Get-WeeklyBestSellersPropertyValue -Object $currentSnapshot -Name $categoryName)
            foreach ($asin in @($currentMap.Keys)) {
                if (-not $previousMap.ContainsKey($asin)) {
                    $item = $currentMap[$asin]
                    $newEntries += [pscustomobject]@{
                        category = $categoryName; asin = $asin; market_date = $currentDate
                        current_rank = [int](Get-WeeklyBestSellersPropertyValue -Object $item -Name 'rank')
                        title = [string](Get-WeeklyBestSellersPropertyValue -Object $item -Name 'title')
                        url = [string](Get-WeeklyBestSellersPropertyValue -Object $item -Name 'url')
                    }
                    continue
                }
                $currentItem = $currentMap[$asin]
                $previousItem = $previousMap[$asin]
                $currentRank = [int](Get-WeeklyBestSellersPropertyValue -Object $currentItem -Name 'rank')
                $previousRank = [int](Get-WeeklyBestSellersPropertyValue -Object $previousItem -Name 'rank')
                $change = $previousRank - $currentRank
                $previousHasDiscount = Get-WeeklyBestSellersPropertyValue -Object $previousItem -Name 'has_discount'
                $hasDiscount = Get-WeeklyBestSellersPropertyValue -Object $currentItem -Name 'has_discount'
                $previousDiscounts = @(ConvertTo-WeeklyDiscountList (Get-WeeklyBestSellersPropertyValue -Object $previousItem -Name 'discounts'))
                $discounts = @(ConvertTo-WeeklyDiscountList (Get-WeeklyBestSellersPropertyValue -Object $currentItem -Name 'discounts'))
                if ($null -eq $previousHasDiscount -or $null -eq $hasDiscount) {
                    $discountSummary.unknown_count++
                    $transitionKind = 'UNKNOWN'
                } else {
                    $transitionKind = if (-not [bool]$previousHasDiscount -and [bool]$hasDiscount) { 'DISCOUNT_ADDED' }
                        elseif ([bool]$previousHasDiscount -and -not [bool]$hasDiscount) { 'DISCOUNT_REMOVED' }
                        elseif (-not (Test-WeeklyDiscountListsEqual -PreviousDiscounts $previousDiscounts -Discounts $discounts)) { 'DISCOUNT_AMOUNT_CHANGED' }
                        else { 'UNCHANGED' }
                    switch ($transitionKind) {
                        'DISCOUNT_ADDED' { $discountSummary.added_count++ }
                        'DISCOUNT_REMOVED' { $discountSummary.removed_count++ }
                        'DISCOUNT_AMOUNT_CHANGED' { $discountSummary.amount_changed_count++ }
                        'UNCHANGED' { $discountSummary.unchanged_count++ }
                    }
                }
                $discountTransitions += [pscustomobject]@{
                    category = $categoryName; asin = $asin; previous_market_date = $previousDate; market_date = $currentDate
                    previous_has_discount = $previousHasDiscount; has_discount = $hasDiscount
                    previous_discounts = @($previousDiscounts); discounts = @($discounts)
                    previous_rank = $previousRank; current_rank = $currentRank; rank_change = $change; transition_kind = $transitionKind
                }
                $absoluteChange = [math]::Abs($change)
                if ($absoluteChange -ge $SwingThreshold) {
                    $largeSwings += [pscustomobject]@{
                        category = $categoryName; asin = $asin; market_date = $currentDate; previous_market_date = $previousDate
                        current_rank = $currentRank; previous_rank = $previousRank; rank_change = $change
                        absolute_change = $absoluteChange
                        priority = if ($absoluteChange -ge $HighPriorityThreshold) { 'HIGH' } else { 'WATCH' }
                        title = [string](Get-WeeklyBestSellersPropertyValue -Object $currentItem -Name 'title')
                        url = [string](Get-WeeklyBestSellersPropertyValue -Object $currentItem -Name 'url')
                    }
                }
            }
            foreach ($asin in @($previousMap.Keys)) {
                if ($currentMap.ContainsKey($asin)) { continue }
                $item = $previousMap[$asin]
                $exits += [pscustomobject]@{
                    category = $categoryName; asin = $asin; market_date = $currentDate; previous_market_date = $previousDate
                    previous_rank = [int](Get-WeeklyBestSellersPropertyValue -Object $item -Name 'rank')
                    title = [string](Get-WeeklyBestSellersPropertyValue -Object $item -Name 'title')
                    url = [string](Get-WeeklyBestSellersPropertyValue -Object $item -Name 'url')
                }
            }
        }

        $firstSnapshot = if ($presentSnapshots.Count -gt 0) { $presentSnapshots[0] } else { $null }
        $lastSnapshot = if ($presentSnapshots.Count -gt 0) { $presentSnapshots[$presentSnapshots.Count - 1] } else { $null }
        $firstMap = if ($null -ne $firstSnapshot) { New-WeeklyBestSellersItemMap -Items (Get-WeeklyBestSellersPropertyValue -Object $firstSnapshot -Name $categoryName) } else { @{} }
        $lastMap = if ($null -ne $lastSnapshot) { New-WeeklyBestSellersItemMap -Items (Get-WeeklyBestSellersPropertyValue -Object $lastSnapshot -Name $categoryName) } else { @{} }
        $products = @()
        foreach ($asin in @($productHistory.Keys)) {
            $history = @($productHistory[$asin] | Sort-Object market_date)
            $firstSeen = $history[0].item
            $lastSeen = $history[$history.Count - 1].item
            $ranks = @($history | ForEach-Object { [int](Get-WeeklyBestSellersPropertyValue -Object $_.item -Name 'rank') })
            $startRank = if ($firstMap.ContainsKey($asin)) { [int](Get-WeeklyBestSellersPropertyValue -Object $firstMap[$asin] -Name 'rank') } else { $null }
            $endRank = if ($lastMap.ContainsKey($asin)) { [int](Get-WeeklyBestSellersPropertyValue -Object $lastMap[$asin] -Name 'rank') } else { $null }
            $weeklyChange = if ($null -ne $startRank -and $null -ne $endRank) { $startRank - $endRank } else { $null }
            $reviewsFirst = Get-WeeklyBestSellersPropertyValue -Object $firstSeen -Name 'reviews'
            $reviewsLast = Get-WeeklyBestSellersPropertyValue -Object $lastSeen -Name 'reviews'
            $reviewGrowth = if ($null -ne $reviewsFirst -and $null -ne $reviewsLast) { [long]$reviewsLast - [long]$reviewsFirst } else { $null }
            $priceFirst = ConvertTo-WeeklyPriceAmount (Get-WeeklyBestSellersPropertyValue -Object $firstSeen -Name 'price')
            $priceLast = ConvertTo-WeeklyPriceAmount (Get-WeeklyBestSellersPropertyValue -Object $lastSeen -Name 'price')
            $priceChange = if ($null -ne $priceFirst -and $null -ne $priceLast) { [math]::Round($priceLast - $priceFirst, 2) } else { $null }
            $productSwings = @($largeSwings | Where-Object { $_.category -eq $categoryName -and $_.asin -eq $asin })
            $entryCount = @($newEntries | Where-Object { $_.category -eq $categoryName -and $_.asin -eq $asin }).Count
            $exitCount = @($exits | Where-Object { $_.category -eq $categoryName -and $_.asin -eq $asin }).Count
            $status = if ($entryCount -gt 0 -and $exitCount -gt 0 -and $null -ne $endRank) { 'REENTERED' }
                elseif ($null -eq $startRank -and $null -ne $endRank) { 'NEW_IN_WEEK' }
                elseif ($null -ne $startRank -and $null -eq $endRank) { 'EXITED_WEEK' }
                else { 'CONTINUING' }
            $products += [pscustomobject]@{
                category = $categoryName; asin = $asin
                title = [string](Get-WeeklyBestSellersPropertyValue -Object $lastSeen -Name 'title')
                url = [string](Get-WeeklyBestSellersPropertyValue -Object $lastSeen -Name 'url')
                days_in_chart = $history.Count; start_rank = $startRank; end_rank = $endRank
                weekly_rank_change = $weeklyChange
                average_rank = [math]::Round((($ranks | Measure-Object -Average).Average), 2)
                best_rank = ($ranks | Measure-Object -Minimum).Minimum
                worst_rank = ($ranks | Measure-Object -Maximum).Maximum
                max_daily_absolute_change = if ($productSwings.Count -gt 0) { ($productSwings.absolute_change | Measure-Object -Maximum).Maximum } else { 0 }
                status = $status; entry_count = $entryCount; exit_count = $exitCount
                price_start = $priceFirst; price_end = $priceLast; price_change = $priceChange
                rating_end = Get-WeeklyBestSellersPropertyValue -Object $lastSeen -Name 'rating'
                reviews_start = $reviewsFirst; reviews_end = $reviewsLast; review_growth = $reviewGrowth
            }
        }
        $categoryResults += [pscustomobject]@{
            category = $categoryName
            valid_day_count = $presentSnapshots.Count
            first_market_date = if ($presentSnapshots.Count -gt 0) { [string](Get-WeeklyBestSellersPropertyValue -Object $presentSnapshots[0] -Name 'market_date') } else { $null }
            last_market_date = if ($presentSnapshots.Count -gt 0) { [string](Get-WeeklyBestSellersPropertyValue -Object $presentSnapshots[$presentSnapshots.Count - 1] -Name 'market_date') } else { $null }
            end_item_count = $lastMap.Count
            discount_summary = [pscustomobject]$discountSummary
            products = @($products | Sort-Object @{ Expression = { if ($null -eq $_.end_rank) { 999 } else { $_.end_rank } } }, asin)
        }
    }

    return [pscustomobject]@{
        schema_version = 'best-sellers-weekly-analysis-v1'
        period_start = $dates[0]
        period_end = $dates[$dates.Count - 1]
        snapshot_day_count = $ordered.Count
        swing_threshold = $SwingThreshold
        high_priority_threshold = $HighPriorityThreshold
        coverage_complete = $ordered.Count -eq 7 -and @($categoryResults | Where-Object { $_.valid_day_count -ne 7 }).Count -eq 0
        large_swings = @($largeSwings | Sort-Object @{ Expression = { -1 * $_.absolute_change } }, category, market_date)
        new_entries = @($newEntries | Sort-Object market_date, category, current_rank)
        exits = @($exits | Sort-Object market_date, category, previous_rank)
        discount_transitions = @($discountTransitions | Sort-Object category, market_date, asin)
        categories = $categoryResults
    }
}

function Write-BestSellersWeeklyAnalysisArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Analysis,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, ($Analysis | ConvertTo-Json -Depth 15), (New-Object System.Text.UTF8Encoding($false)))
    return (Resolve-Path -LiteralPath $Path).Path
}

Export-ModuleMember -Function New-BestSellersWeeklyAnalysis, Write-BestSellersWeeklyAnalysisArtifact
