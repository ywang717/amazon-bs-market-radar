Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'BestSellersDataSemantics.psm1') -Scope Local
Import-Module (Join-Path $PSScriptRoot 'BestSellersCategoryRegistry.psm1') -Scope Local

function ConvertFrom-SellerIntelligenceUtf8Base64([string]$Value) {
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value))
}

$script:SellerIntelligenceText = @{
    check_price_discount = ConvertFrom-SellerIntelligenceUtf8Base64 '5qC45p+l5Lu35qC85LiO5LyY5oOg54q25oCB'
    check_rating_reviews = ConvertFrom-SellerIntelligenceUtf8Base64 '5qC45p+l5pif57qn5LiO6K+E6K665pWw6YeP'
    check_title_specs = ConvertFrom-SellerIntelligenceUtf8Base64 '5qC45p+l5qCH6aKY6KeE5qC85oiW6K+m5oOF6aG15Y+Y5YyW'
    daily_title = ConvertFrom-SellerIntelligenceUtf8Base64 '57uP6JCl6aKE6K2m'
    quality_title = ConvertFrom-SellerIntelligenceUtf8Base64 '5pWw5o2u6LSo6YeP'
    summary_title = ConvertFrom-SellerIntelligenceUtf8Base64 '6KeC5a+f5pGY6KaB'
    weekly_title = ConvertFrom-SellerIntelligenceUtf8Base64 '56ue5LqJ6KeC5a+f'
    competitor_pool_title = ConvertFrom-SellerIntelligenceUtf8Base64 '5qC45b+D56ue5ZOB5rGg'
    incomplete_current = ConvertFrom-SellerIntelligenceUtf8Base64 '5b2T5YmN5biC5Zy65pel5LiN5piv5a6M5pW0IFRvcCAzMO+8jOaaguS4jeS4i+e7k+iuuuOAgg=='
    incomparable_previous = ConvertFrom-SellerIntelligenceUtf8Base64 '5LiK5LiA5biC5Zy65pel5LiN5Y+v5q+U77yM5LuF5L+d55WZ5b2T5pel5LqL5a6e44CC'
    comparable_daily = ConvertFrom-SellerIntelligenceUtf8Base64 '5b2T5YmN5LiO5LiK5LiA5biC5Zy65pel5Z2H5Li65a6M5pW0IFRvcCAzMO+8jOWPr+i/m+ihjOWQjOamnOWNleavlOi+g+OAgg=='
    no_daily_signals = ConvertFrom-SellerIntelligenceUtf8Base64 '5pyq5Y+R546w6L6+5Yiw6Zeo5qeb55qE5b6F5qC45p+l5Y+Y5YyW44CC'
    daily_signal_count = ConvertFrom-SellerIntelligenceUtf8Base64 '5Y+R546wIHswfSDkuKrlvoXmoLjmn6Xlj5jljJbjgII='
    insufficient_week = ConvertFrom-SellerIntelligenceUtf8Base64 '5a6M5pW05biC5Zy65pel5LiN6LazIDUg5Liq77yM5pqC5LiN5LiL57uT6K6644CC'
    weekly_summary = ConvertFrom-SellerIntelligenceUtf8Base64 '5Z+65LqOIHswfSDkuKrlrozmlbTluILlnLrml6XmlbTnkIblj6/pqozor4Hop4Llr5/jgII='
    competitor_pool_summary = ConvertFrom-SellerIntelligenceUtf8Base64 '5qC45b+D56ue5ZOB5rGg5oyJ6L+e57ut5Zyo5qac44CBVG9wIDEwIOWHuueOsOWSjOaOkuWQjeazouWKqOWIhuWxgu+8jOS7heS+m+S6uuW3peaguOafpeOAgg=='
    limitation_manual = ConvertFrom-SellerIntelligenceUtf8Base64 '5LuF5L6b5Lq65bel5qC45p+l77yM5LiN5Luj6KGo6ZSA6YeP5oiW5Yip5ram6aKE5rWL44CC'
    limitation_nulls = ConvertFrom-SellerIntelligenceUtf8Base64 '57y65aSx5a2X5q615L+d5oyB5Li656m65YC877yM5LiN5a+55pyq5piO56Gu5YaZ5Ye655qE6KeE5qC85YGa5o6o5pat44CC'
    limitation_coverage = ConvertFrom-SellerIntelligenceUtf8Base64 '5Lu35qC844CB6K+E5YiG44CB6K+E6K6644CB5LyY5oOg5ZKM6KeE5qC86KaG55uW546H5LuF5Y+N5pig5b2T5YmN5Y+v6aqM6K+B5a2X5q6144CC'
}

function Get-SellerIntelligenceCategories {
    param([string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json'))
    $registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
    return @($registry.Categories | Where-Object Enabled | ForEach-Object {
        [pscustomobject]@{ Key = [string]$_.CategoryKey; Label = [string]$_.LabelZh; TargetCount = [int]$_.TargetCount }
    })
}

function Get-SellerProperty {
    param($Object, [Parameter(Mandatory = $true)][string]$Name)

    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-SellerStringArray {
    param($Value)

    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) { return @($Value) }
    if ($Value -is [System.Collections.IEnumerable]) {
        return @($Value | Where-Object { $_ -is [string] } | ForEach-Object { [string]$_ })
    }
    return @()
}

function ConvertTo-SellerRankIndex {
    param([object[]]$Items)

    $index = @{}
    foreach ($item in @($Items)) {
        $asin = [string](Get-SellerProperty -Object $item -Name 'asin')
        if (-not [string]::IsNullOrWhiteSpace($asin)) {
            $index[$asin.ToUpperInvariant()] = $item
        }
    }
    return $index
}

function Test-SellerExactTop30 {
    [CmdletBinding()]
    param([object[]]$Items, [ValidateRange(1,100)][int]$TargetCount = 30)

    return BestSellersDataSemantics\Test-BestSellersExactTop30 -Items $Items -TargetCount $TargetCount
}

function Get-SellerSharedChecks {
    return @(
        $script:SellerIntelligenceText.check_price_discount
        $script:SellerIntelligenceText.check_rating_reviews
        $script:SellerIntelligenceText.check_title_specs
    )
}

function Format-SellerDiscountState {
    param($Item)

    $hasDiscount = Get-SellerProperty -Object $Item -Name 'has_discount'
    $discounts = @(Get-SellerStringArray -Value (Get-SellerProperty -Object $Item -Name 'discounts'))
    if ($hasDiscount -eq $true -or $discounts.Count -gt 0) {
        if ($discounts.Count -gt 0) {
            return ($discounts | Sort-Object -Unique) -join '; '
        }
        return 'discount'
    }
    if ($hasDiscount -eq $false) { return 'none' }
    return 'unknown'
}

function Test-SellerDiscountChanged {
    param($CurrentItem, $PreviousItem)

    return (Format-SellerDiscountState -Item $CurrentItem) -ne (Format-SellerDiscountState -Item $PreviousItem)
}

function Test-SellerVerifiableDiscountTransition {
    param($CurrentItem, $PreviousItem)

    $currentState = Format-SellerDiscountState -Item $CurrentItem
    $previousState = Format-SellerDiscountState -Item $PreviousItem
    if ($currentState -eq 'unknown' -or $previousState -eq 'unknown') { return $false }
    return $currentState -ne $previousState
}

function Get-SellerPriorityOrder {
    param([string]$Priority)

    switch ($Priority) {
        'high' { return 4 }
        'watch' { return 3 }
        'activity' { return 2 }
        'medium' { return 2 }
        'low' { return 1 }
        default { return 0 }
    }
}

function Get-SellerDailySignals {
    [CmdletBinding()]
    param([object[]]$Current, [object[]]$Previous, [string]$BaselineDate, [ValidateRange(1,100)][int]$TargetCount = 30)

    if (-not (Test-SellerExactTop30 -Items $Current -TargetCount $TargetCount) -or -not (Test-SellerExactTop30 -Items $Previous -TargetCount $TargetCount)) {
        return @()
    }

    $signals = New-Object System.Collections.Generic.List[object]
    $currentIndex = ConvertTo-SellerRankIndex -Items $Current
    $previousIndex = ConvertTo-SellerRankIndex -Items $Previous

    foreach ($asin in @($currentIndex.Keys | Sort-Object)) {
        if ($previousIndex.ContainsKey($asin)) {
            $currentItem = $currentIndex[$asin]
            $previousItem = $previousIndex[$asin]
            $currentRank = [int](Get-SellerProperty -Object $currentItem -Name 'rank')
            $previousRank = [int](Get-SellerProperty -Object $previousItem -Name 'rank')
            $movement = [math]::Abs($currentRank - $previousRank)

            if ($movement -ge 10) {
                $priority = if ($movement -ge 20) { 'high' } else { 'watch' }
                $signals.Add([pscustomobject]@{
                        priority = $priority
                        kind = 'rank_move'
                        asin = $asin
                        currentRank = $currentRank
                        previousRank = $previousRank
                        checks = @(Get-SellerSharedChecks)
                        evidence = @("Rank moved from #$previousRank to #$currentRank.")
                    })
            }

            if ($currentRank -le 10 -and $previousRank -gt 10) {
                $signals.Add([pscustomobject]@{
                        priority = 'high'
                        kind = 'top10_entry'
                        asin = $asin
                        currentRank = $currentRank
                        previousRank = $previousRank
                        checks = @(Get-SellerSharedChecks)
                        evidence = @("Entered Top 10: #$previousRank -> #$currentRank.")
                    })
            }
            elseif ($currentRank -gt 10 -and $previousRank -le 10) {
                $signals.Add([pscustomobject]@{
                        priority = 'high'
                        kind = 'top10_exit'
                        asin = $asin
                        currentRank = $currentRank
                        previousRank = $previousRank
                        checks = @(Get-SellerSharedChecks)
                        evidence = @("Exited Top 10: #$previousRank -> #$currentRank.")
                    })
            }

            if (Test-SellerVerifiableDiscountTransition -CurrentItem $currentItem -PreviousItem $previousItem) {
                $discountBefore = Format-SellerDiscountState -Item $previousItem
                $discountAfter = Format-SellerDiscountState -Item $currentItem
                $signals.Add([pscustomobject]@{
                        priority = 'watch'
                        kind = 'discount_change'
                        asin = $asin
                        currentRank = $currentRank
                        previousRank = $previousRank
                        checks = @($script:SellerIntelligenceText.check_price_discount)
                        evidence = @("Discount state changed from $discountBefore to $discountAfter.")
                        discountBefore = $discountBefore
                        discountAfter = $discountAfter
                    })
            }

            continue
        }

        $currentItem = $currentIndex[$asin]
        $currentRank = [int](Get-SellerProperty -Object $currentItem -Name 'rank')
        $signals.Add([pscustomobject]@{
                priority = if ($currentRank -le 10) { 'high' } else { 'activity' }
                kind = if ($currentRank -le 10) { 'top10_entry' } else { 'top30_entry' }
                asin = $asin
                currentRank = $currentRank
                previousRank = $null
                checks = @(Get-SellerSharedChecks)
                evidence = @("New Top 30 entry at #$currentRank.")
            })
    }

    foreach ($asin in @($previousIndex.Keys | Sort-Object)) {
        if ($currentIndex.ContainsKey($asin)) { continue }
        $previousItem = $previousIndex[$asin]
        $previousRank = [int](Get-SellerProperty -Object $previousItem -Name 'rank')
        $signals.Add([pscustomobject]@{
                priority = if ($previousRank -le 10) { 'high' } else { 'activity' }
                kind = if ($previousRank -le 10) { 'top10_exit' } else { 'top30_exit' }
                asin = $asin
                currentRank = $null
                previousRank = $previousRank
                checks = @(Get-SellerSharedChecks)
                evidence = @("Exited Top 30 from #$previousRank.")
            })
    }

    $ordered = @($signals | Sort-Object @{ Expression = { Get-SellerPriorityOrder -Priority ([string]$_.priority) }; Descending = $true }, @{ Expression = 'kind'; Descending = $false }, @{ Expression = 'asin'; Descending = $false })
    foreach ($signal in $ordered) {
        $signal | Add-Member -NotePropertyName baselineDate -NotePropertyValue $BaselineDate -Force
    }
    return $ordered
}

function Get-SellerUniqueMatchValue {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string[]]$Patterns,
        [Parameter(Mandatory = $true)][scriptblock]$Transform
    )

    $matches = New-Object System.Collections.Generic.List[object]
    foreach ($pattern in $Patterns) {
        foreach ($match in [regex]::Matches($Title, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            foreach ($group in @($match.Groups | Select-Object -Skip 1)) {
                if ($group.Success -and -not [string]::IsNullOrWhiteSpace($group.Value)) {
                    $matches.Add((& $Transform $group.Value))
                }
            }
        }
    }

    $unique = @($matches | Where-Object { $null -ne $_ } | Select-Object -Unique)
    if ($unique.Count -eq 1) { return $unique[0] }
    return $null
}

function ConvertTo-SellerNumber {
    param([string]$Value)

    $number = 0.0
    if ([double]::TryParse($Value, [Globalization.NumberStyles]::AllowDecimalPoint, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        return $number
    }
    return $null
}

function ConvertTo-SellerNumericValue {
    param([string]$Value)

    $parsed = ConvertTo-SellerNumber -Value $Value
    if ($null -eq $parsed) { return $null }
    if ([math]::Abs($parsed - [math]::Round($parsed)) -lt 0.000001) { return [int][math]::Round($parsed) }
    return [double]$parsed
}

function ConvertTo-SellerFractionOrNumber {
    param([string]$Value)

    if ($Value -match '^\d+/\d+$') { return $Value }
    return ConvertTo-SellerNumericValue -Value $Value
}

function Get-SellerSpecifications {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$CategoryKey,
        [string]$Title,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )

    $registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
    Get-BestSellersCategory -Registry $registry -CategoryKey $CategoryKey | Out-Null
    $text = [string]$Title
    switch ($CategoryKey) {
        'pressure_washers' {
            $powerType = $null
            $hasElectric = $text -match '\belectric\b'
            $hasGas = $text -match '\bgas(?:-powered)?\b'
            if ($hasElectric -xor $hasGas) {
                $powerType = if ($hasElectric) { 'electric' } else { 'gas' }
            }

            return [pscustomobject]@{
                psi = Get-SellerUniqueMatchValue -Title $text -Patterns @('(\d{3,5})\s*PSI\b') -Transform { param($v) ConvertTo-SellerNumericValue -Value $v }
                gpm = Get-SellerUniqueMatchValue -Title $text -Patterns @('(\d+(?:\.\d+)?)\s*GPM\b') -Transform { param($v) ConvertTo-SellerNumericValue -Value $v }
                power_type = $powerType
                hose_length_ft = Get-SellerUniqueMatchValue -Title $text -Patterns @('(\d+(?:\.\d+)?)\s*(?:FT|FOOT|FEET)\s+HOSE\b') -Transform { param($v) ConvertTo-SellerNumericValue -Value $v }
                nozzle_degree = Get-SellerUniqueMatchValue -Title $text -Patterns @('(\d+(?:\.\d+)?)\s*(?:DEGREE|DEGREES)\b') -Transform { param($v) ConvertTo-SellerNumericValue -Value $v }
            }
        }
        'sump_pumps' {
            $switchType = $null
            $hasAutomatic = $text -match '\bautomatic\b|\bauto\b'
            $hasManual = $text -match '\bmanual\b'
            if ($hasAutomatic -xor $hasManual) {
                $switchType = if ($hasAutomatic) { 'automatic' } else { 'manual' }
            }

            return [pscustomobject]@{
                head_ft = Get-SellerUniqueMatchValue -Title $text -Patterns @(
                    '(\d+(?:\.\d+)?)\s*(?:FT|FOOT|FEET)\s+(?:HEAD|LIFT)\b',
                    '\b(?:HEAD|LIFT)\s+(\d+(?:\.\d+)?)\s*(?:FT|FOOT|FEET)\b'
                ) -Transform { param($v) ConvertTo-SellerNumericValue -Value $v }
                flow_gpm = Get-SellerUniqueMatchValue -Title $text -Patterns @('(\d+(?:\.\d+)?)\s*GPM\b') -Transform { param($v) ConvertTo-SellerNumericValue -Value $v }
                horsepower_hp = Get-SellerUniqueMatchValue -Title $text -Patterns @('(\d+(?:\.\d+)?)\s*HP\b') -Transform { param($v) ConvertTo-SellerNumericValue -Value $v }
                watts_w = Get-SellerUniqueMatchValue -Title $text -Patterns @('(\d+(?:\.\d+)?)\s*W\b') -Transform { param($v) ConvertTo-SellerNumericValue -Value $v }
                voltage_v = Get-SellerUniqueMatchValue -Title $text -Patterns @('(\d+(?:\.\d+)?)\s*V\b') -Transform { param($v) ConvertTo-SellerNumericValue -Value $v }
                switch_type = $switchType
            }
        }
        'pressure_washer_accessories' {
            return [pscustomobject]@{
                hose_length_ft = Get-SellerUniqueMatchValue -Title $text -Patterns @('(\d+(?:\.\d+)?)\s*(?:FT|FOOT|FEET)\s+HOSE\b') -Transform { param($v) ConvertTo-SellerNumericValue -Value $v }
                nozzle_degree = Get-SellerUniqueMatchValue -Title $text -Patterns @('(\d+(?:\.\d+)?)\s*(?:DEGREE|DEGREES)\b') -Transform { param($v) ConvertTo-SellerNumericValue -Value $v }
                fitting_size_in = Get-SellerUniqueMatchValue -Title $text -Patterns @(
                    '(\d+(?:/\d+)?(?:\.\d+)?)\s*(?:IN|INCH)\b',
                    '(\d+(?:/\d+)?(?:\.\d+)?)\"'
                ) -Transform { param($v) ConvertTo-SellerFractionOrNumber -Value $v }
            }
        }
    }
}

function Get-SellerCategoryRows {
    param(
        $Snapshot,
        [string]$CategoryKey
    )

    $rows = Get-SellerProperty -Object $Snapshot -Name $CategoryKey
    if ($rows -is [System.Collections.IEnumerable] -and -not ($rows -is [string])) {
        return @($rows)
    }
    return @()
}

function Get-SellerCategoryEvidence {
    param(
        $Rows,
        [string]$CategoryKey,
        [ValidateRange(1,100)][int]$TargetCount = 30,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )

    $list = @($Rows | Where-Object { $null -ne $_ })
    $complete = Test-SellerExactTop30 -Items $list -TargetCount $TargetCount
    $total = $list.Count
    $priceCount = @($list | Where-Object { $null -ne (Get-SellerProperty -Object $_ -Name 'price') }).Count
    $ratingCount = @($list | Where-Object { $null -ne (Get-SellerProperty -Object $_ -Name 'rating') }).Count
    $reviewsCount = @($list | Where-Object { $null -ne (Get-SellerProperty -Object $_ -Name 'reviews') }).Count
    $discountCount = @($list | Where-Object {
            $hasDiscount = Get-SellerProperty -Object $_ -Name 'has_discount'
            $discounts = @(Get-SellerStringArray -Value (Get-SellerProperty -Object $_ -Name 'discounts'))
            $null -ne $hasDiscount -or $discounts.Count -gt 0
        }).Count
    $specCount = @($list | Where-Object {
            $specs = Get-SellerSpecifications -CategoryKey $CategoryKey -Title ([string](Get-SellerProperty -Object $_ -Name 'title')) -RegistryPath $RegistryPath
            @($specs.PSObject.Properties | Where-Object { $null -ne $_.Value }).Count -gt 0
        }).Count

    return [pscustomobject]@{
        Complete = $complete
        Count = $total
        FieldCoverage = [pscustomobject]@{
            price = if ($total -gt 0) { [math]::Round(($priceCount * 100.0) / $total, 1) } else { 0.0 }
            rating = if ($total -gt 0) { [math]::Round(($ratingCount * 100.0) / $total, 1) } else { 0.0 }
            reviews = if ($total -gt 0) { [math]::Round(($reviewsCount * 100.0) / $total, 1) } else { 0.0 }
            discount = if ($total -gt 0) { [math]::Round(($discountCount * 100.0) / $total, 1) } else { 0.0 }
            specs = if ($total -gt 0) { [math]::Round(($specCount * 100.0) / $total, 1) } else { 0.0 }
        }
    }
}

function Get-SellerPriorityScore {
    param(
        [int]$ContinuousDays,
        [int]$Top10Appearances,
        [int]$LatestRank,
        [int]$MaxAbsoluteMovement
    )

    if ($LatestRank -le 10 -or $Top10Appearances -ge 1 -or $ContinuousDays -ge 3 -or $MaxAbsoluteMovement -ge 10) { return 'medium' }
    return 'low'
}

function Sort-SellerSignals {
    param([object[]]$Signals)

    return @($Signals | Sort-Object @{ Expression = { Get-SellerPriorityOrder -Priority ([string]$_.priority) }; Descending = $true }, @{ Expression = 'kind'; Descending = $false }, @{ Expression = 'asin'; Descending = $false })
}

function Get-SellerCompetitorPool {
    [CmdletBinding()]
    param(
        [object[]]$Snapshots,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$CategoryKey,
        [ValidateRange(0,365)][int]$CompleteMarketDays = 0,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )

    $registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
    $category = Get-BestSellersCategory -Registry $registry -CategoryKey $CategoryKey
    if ($CompleteMarketDays -lt 5) { return @() }

    $completeSnapshots = @($Snapshots | Where-Object { Test-SellerExactTop30 -Items (Get-SellerCategoryRows -Snapshot $_ -CategoryKey $CategoryKey) -TargetCount $category.TargetCount })
    if ($completeSnapshots.Count -lt 5) { return @() }

    $byAsin = @{}
    $ordered = @($completeSnapshots | Sort-Object { [string](Get-SellerProperty -Object $_ -Name 'market_date') })
    for ($index = 0; $index -lt $ordered.Count; $index++) {
        $rows = @(Get-SellerCategoryRows -Snapshot $ordered[$index] -CategoryKey $CategoryKey)
        foreach ($row in $rows) {
            $asin = [string](Get-SellerProperty -Object $row -Name 'asin')
            if ([string]::IsNullOrWhiteSpace($asin)) { continue }
            if (-not $byAsin.ContainsKey($asin)) {
                $byAsin[$asin] = [ordered]@{
                    asin = $asin
                    title = [string](Get-SellerProperty -Object $row -Name 'title')
                    ranks = @{}
                    marketDates = @{}
                }
            }
            $date = [string](Get-SellerProperty -Object $ordered[$index] -Name 'market_date')
            $byAsin[$asin].ranks[$date] = [int](Get-SellerProperty -Object $row -Name 'rank')
            $byAsin[$asin].marketDates[$date] = $true
            if ([string]::IsNullOrWhiteSpace([string]$byAsin[$asin].title)) {
                $byAsin[$asin].title = [string](Get-SellerProperty -Object $row -Name 'title')
            }
        }
    }

    $latestDate = [string](Get-SellerProperty -Object $ordered[-1] -Name 'market_date')
    $pool = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $byAsin.GetEnumerator()) {
        $asin = $entry.Key
        $record = $entry.Value
        $daysPresent = $record.ranks.Count
        $top10Appearances = @($record.ranks.GetEnumerator() | Where-Object { [int]$_.Value -le 10 }).Count
        $latestRank = if ($record.ranks.ContainsKey($latestDate)) { [int]$record.ranks[$latestDate] } else { [int]$category.TargetCount + 1 }
        $continuousDays = 0
        for ($index = $ordered.Count - 1; $index -ge 0; $index--) {
            $marketDate = [string](Get-SellerProperty -Object $ordered[$index] -Name 'market_date')
            if ($record.marketDates.ContainsKey($marketDate)) {
                $continuousDays++
                continue
            }
            break
        }

        $maxAbsoluteMovement = 0
        for ($index = 1; $index -lt $ordered.Count; $index++) {
            $currentDate = [string](Get-SellerProperty -Object $ordered[$index] -Name 'market_date')
            $previousDate = [string](Get-SellerProperty -Object $ordered[$index - 1] -Name 'market_date')
            if ($record.ranks.ContainsKey($currentDate) -and $record.ranks.ContainsKey($previousDate)) {
                $movement = [math]::Abs([int]$record.ranks[$currentDate] - [int]$record.ranks[$previousDate])
                if ($movement -gt $maxAbsoluteMovement) { $maxAbsoluteMovement = $movement }
            }
        }

        $pool.Add([pscustomobject]@{
                asin = $asin
                title = [string]$record.title
                latestRank = if ($latestRank -le $category.TargetCount) { $latestRank } else { $null }
                daysPresent = $daysPresent
                continuousDays = $continuousDays
                top10Appearances = $top10Appearances
                maxAbsoluteMovement = $maxAbsoluteMovement
                priority = Get-SellerPriorityScore -ContinuousDays $continuousDays -Top10Appearances $top10Appearances -LatestRank $latestRank -MaxAbsoluteMovement $maxAbsoluteMovement
            })
    }

    return @($pool | Sort-Object @{ Expression = { if ($_.priority -eq 'high') { 3 } elseif ($_.priority -eq 'medium') { 2 } else { 1 } }; Descending = $true }, @{ Expression = 'latestRank'; Descending = $false }, @{ Expression = 'asin'; Descending = $false })
}

function Get-SellerObservedAt {
    param($Snapshot)

    $observedAt = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse([string](Get-SellerProperty -Object $Snapshot -Name 'observed_at'), [ref]$observedAt)) {
        return $observedAt.ToUniversalTime().ToString('o')
    }
    return [DateTimeOffset]::UtcNow.ToString('o')
}

function Get-SellerContentHash {
    param([Parameter(Mandatory = $true)]$Content)

    $text = $Content | ConvertTo-Json -Depth 12 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
    }
    finally {
        $sha.Dispose()
    }
}

function Get-SellerProfileValue {
    param([Parameter(Mandatory = $true)][string]$Profile)

    switch ($Profile.ToLowerInvariant()) {
        'selleralert' { return 'seller_alert' }
        'seller_alert' { return 'seller_alert' }
        'competitionstrategy' { return 'competition_strategy' }
        'competition_strategy' { return 'competition_strategy' }
        default { throw "Unsupported seller profile: $Profile" }
    }
}

function Get-SellerReportKey {
    param(
        [string]$Profile,
        [string]$MarketDate,
        $CategoryKey
    )

    if ($Profile -eq 'seller_alert') {
        $scope = if ([string]::IsNullOrWhiteSpace($CategoryKey)) { 'overview' } else { $CategoryKey }
        return "seller-alert/daily/$MarketDate/$scope.json"
    }
    $scope = if ([string]::IsNullOrWhiteSpace($CategoryKey)) { 'overview' } else { $CategoryKey }
    return "competition-strategy/weekly/$MarketDate/$scope.json"
}

function Get-SellerAveragedCoverage {
    param($Qualities)

    $qualityList = @($Qualities)
    if ($qualityList.Count -eq 0) {
        return [pscustomobject]@{ price = 0.0; rating = 0.0; reviews = 0.0; discount = 0.0; specs = 0.0 }
    }

    return [pscustomobject]@{
        price = [math]::Round((@($qualityList | ForEach-Object { $_.FieldCoverage.price } | Measure-Object -Average).Average), 1)
        rating = [math]::Round((@($qualityList | ForEach-Object { $_.FieldCoverage.rating } | Measure-Object -Average).Average), 1)
        reviews = [math]::Round((@($qualityList | ForEach-Object { $_.FieldCoverage.reviews } | Measure-Object -Average).Average), 1)
        discount = [math]::Round((@($qualityList | ForEach-Object { $_.FieldCoverage.discount } | Measure-Object -Average).Average), 1)
        specs = [math]::Round((@($qualityList | ForEach-Object { $_.FieldCoverage.specs } | Measure-Object -Average).Average), 1)
    }
}

function New-SellerEmptyStrategyFacts {
    return [pscustomobject][ordered]@{
        priceBands = $null
        rankingConcentration = $null
        topStability = $null
        competitorPool = $null
        specificationTrend = $null
    }
}

function ConvertTo-SellerPrice {
    param($Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) { return [double]$Value }
    $text = ([string]$Value).Trim().Replace(',', '')
    if ($text -notmatch '^[^0-9-]*([0-9]+(?:\.[0-9]+)?)[^0-9]*$') { return $null }
    return ConvertTo-SellerNumber -Value $Matches[1]
}

function Get-SellerPriceBands {
    param([object[]]$Rows, [double]$Coverage)

    if ($Coverage -lt 80) { return $null }
    [object[]]$values = @($Rows | ForEach-Object { ConvertTo-SellerPrice -Value (Get-SellerProperty -Object $_ -Name 'price') } | Where-Object { $null -ne $_ } | Sort-Object)
    if ($values.Count -eq 0) { return $null }
    $size = [math]::Max(1, [int][math]::Ceiling($values.Count / 3.0))
    $bands = New-Object System.Collections.Generic.List[object]
    for ($offset = 0; $offset -lt $values.Count; $offset += $size) {
        $end = [math]::Min($values.Count - 1, $offset + $size - 1)
        [object[]]$sample = @($values[$offset..$end])
        $bands.Add([pscustomobject][ordered]@{ lower = [math]::Round([double]$sample[0], 2); upper = [math]::Round([double]$sample[-1], 2); sampleSize = $sample.Count })
    }
    return $bands.ToArray()
}

function Get-SellerRankingConcentration {
    param([object[]]$Rows, [ValidateRange(1,100)][int]$TargetCount = 30)

    if (-not (Test-SellerExactTop30 -Items $Rows -TargetCount $TargetCount)) { return $null }
    $totalWeight = 0
    $top10Weight = 0
    $top10Slots = 0
    foreach ($row in $Rows) {
        $rank = [int](Get-SellerProperty -Object $row -Name 'rank')
        $weight = ($TargetCount + 1) - $rank
        $totalWeight += $weight
        if ($rank -le 10) { $top10Weight += $weight; $top10Slots++ }
    }
    if ($totalWeight -le 0) { return $null }
    return [pscustomobject][ordered]@{ top10RankWeightPercent = [math]::Round(($top10Weight * 100.0) / $totalWeight, 1); top10Slots = $top10Slots }
}

function Get-SellerTopStability {
    param([object[]]$Snapshots, [string]$CategoryKey, [ValidateRange(1,100)][int]$TargetCount = 30)

    [object[]]$complete = @($Snapshots | Where-Object { Test-SellerExactTop30 -Items (Get-SellerCategoryRows -Snapshot $_ -CategoryKey $CategoryKey) -TargetCount $TargetCount } | Sort-Object { [string](Get-SellerProperty -Object $_ -Name 'market_date') })
    if ($complete.Count -lt 2) { return $null }
    $previous = $complete[-2]
    $current = $complete[-1]
    $previousTop10 = ConvertTo-SellerRankIndex -Items @((Get-SellerCategoryRows -Snapshot $previous -CategoryKey $CategoryKey) | Where-Object { [int](Get-SellerProperty -Object $_ -Name 'rank') -le 10 })
    $currentTop10 = ConvertTo-SellerRankIndex -Items @((Get-SellerCategoryRows -Snapshot $current -CategoryKey $CategoryKey) | Where-Object { [int](Get-SellerProperty -Object $_ -Name 'rank') -le 10 })
    return [pscustomobject][ordered]@{
        retainedTop10 = @($currentTop10.Keys | Where-Object { $previousTop10.ContainsKey($_) }).Count
        entries = @($currentTop10.Keys | Where-Object { -not $previousTop10.ContainsKey($_) }).Count
        exits = @($previousTop10.Keys | Where-Object { -not $currentTop10.ContainsKey($_) }).Count
        baselineDate = [string](Get-SellerProperty -Object $previous -Name 'market_date')
    }
}

function Get-SellerSpecificationTrend {
    param(
        [object[]]$Rows,
        [string]$CategoryKey,
        [double]$Coverage,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )

    if ($Coverage -lt 80) { return $null }
    $fields = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
    foreach ($row in $Rows) {
        $specs = Get-SellerSpecifications -CategoryKey $CategoryKey -Title ([string](Get-SellerProperty -Object $row -Name 'title')) -RegistryPath $RegistryPath
        foreach ($property in @($specs.PSObject.Properties | Where-Object { $null -ne $_.Value })) { [void]$fields.Add([string]$property.Name) }
    }
    if ($fields.Count -eq 0) { return $null }
    return [pscustomobject][ordered]@{ coverage = [math]::Round($Coverage, 1); observedFields = @($fields | Sort-Object) }
}

function New-SellerStrategyFacts {
    param(
        $Snapshot,
        [string]$CategoryKey,
        [object[]]$HistorySnapshots,
        [int]$CompleteMarketDays,
        $Coverage,
        [bool]$Complete,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )

    if ([string]::IsNullOrWhiteSpace($CategoryKey) -or -not $Complete -or $CompleteMarketDays -lt 5) { return New-SellerEmptyStrategyFacts }
    $registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
    $category = Get-BestSellersCategory -Registry $registry -CategoryKey $CategoryKey
    [object[]]$rows = @(Get-SellerCategoryRows -Snapshot $Snapshot -CategoryKey $CategoryKey)
    [object[]]$pool = @(Get-SellerCompetitorPool -Snapshots $HistorySnapshots -CategoryKey $CategoryKey -CompleteMarketDays $CompleteMarketDays -RegistryPath $RegistryPath | ForEach-Object {
            [pscustomobject][ordered]@{ asin = [string]$_.asin; title = [string]$_.title; daysPresent = [int]$_.daysPresent; top10Appearances = [int]$_.top10Appearances; latestRank = $_.latestRank; maxAbsoluteMovement = [int]$_.maxAbsoluteMovement; priority = [string]$_.priority }
        })
    return [pscustomobject][ordered]@{
        priceBands = Get-SellerPriceBands -Rows $rows -Coverage ([double]$Coverage.price)
        rankingConcentration = Get-SellerRankingConcentration -Rows $rows -TargetCount $category.TargetCount
        topStability = Get-SellerTopStability -Snapshots $HistorySnapshots -CategoryKey $CategoryKey -TargetCount $category.TargetCount
        competitorPool = if ($pool.Count -gt 0) { $pool } else { $null }
        specificationTrend = Get-SellerSpecificationTrend -Rows $rows -CategoryKey $CategoryKey -Coverage ([double]$Coverage.specs) -RegistryPath $RegistryPath
    }
}

function New-SellerIntelligenceReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Snapshot,
        [Parameter(Mandatory = $true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ReceiptSha256,
        [Parameter(Mandatory = $true)][string]$Profile,
        [string]$CategoryKey,
        $PreviousSnapshot,
        [object[]]$HistorySnapshots = @(),
        [ValidateRange(0,365)][int]$CompleteMarketDays = 0,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )

    $sellerCategories = @(Get-SellerIntelligenceCategories -RegistryPath $RegistryPath)
    if (-not [string]::IsNullOrWhiteSpace($CategoryKey)) {
        $registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
        Get-BestSellersCategory -Registry $registry -CategoryKey $CategoryKey | Out-Null
    }
    $profileValue = Get-SellerProfileValue -Profile $Profile
    $marketDate = [string](Get-SellerProperty -Object $Snapshot -Name 'market_date')
    [object[]]$selectedCategories = if ([string]::IsNullOrWhiteSpace($CategoryKey)) {
        @($sellerCategories)
    }
    else {
        @($sellerCategories | Where-Object { $_.Key -eq $CategoryKey })
    }

    [object[]]$qualities = @($selectedCategories | ForEach-Object {
            Get-SellerCategoryEvidence -Rows (Get-SellerCategoryRows -Snapshot $Snapshot -CategoryKey $_.Key) -CategoryKey $_.Key -TargetCount $_.TargetCount -RegistryPath $RegistryPath
        })
    $complete = @($qualities | Where-Object { $_.Complete }).Count -eq @($selectedCategories).Count
    $sampleSize = [int]((@($qualities | Measure-Object -Property Count -Sum).Sum) | ForEach-Object { if ($null -eq $_) { 0 } else { $_ } })
    $coverage = Get-SellerAveragedCoverage -Qualities $qualities
    $generatedAt = Get-SellerObservedAt -Snapshot $Snapshot
    $signals = @()
    $sections = New-Object System.Collections.Generic.List[object]

    if ($profileValue -eq 'seller_alert') {
        if ([string]::IsNullOrWhiteSpace($CategoryKey)) {
            $previousComplete = $false
            if ($null -ne $PreviousSnapshot) {
                $previousComplete = @($sellerCategories | Where-Object {
                        Test-SellerExactTop30 -Items (Get-SellerCategoryRows -Snapshot $PreviousSnapshot -CategoryKey $_.Key) -TargetCount $_.TargetCount
                    }).Count -eq $sellerCategories.Count
            }

            if (-not $complete) {
                $sections.Add([pscustomobject]@{ title = $script:SellerIntelligenceText.quality_title; statements = @($script:SellerIntelligenceText.incomplete_current) })
            }
            elseif (-not $previousComplete) {
                $sections.Add([pscustomobject]@{ title = $script:SellerIntelligenceText.quality_title; statements = @($script:SellerIntelligenceText.incomparable_previous) })
            }
            else {
                $aggregateSignals = New-Object System.Collections.Generic.List[object]
                foreach ($category in $sellerCategories) {
                    $currentRows = @(Get-SellerCategoryRows -Snapshot $Snapshot -CategoryKey $category.Key)
                    $previousRows = @(Get-SellerCategoryRows -Snapshot $PreviousSnapshot -CategoryKey $category.Key)
                    foreach ($signal in @(Get-SellerDailySignals -Current $currentRows -Previous $previousRows -BaselineDate ([string](Get-SellerProperty -Object $PreviousSnapshot -Name 'market_date')) -TargetCount $category.TargetCount)) {
                        $aggregateSignals.Add($signal)
                    }
                }
                $signals = @(Sort-SellerSignals -Signals $aggregateSignals.ToArray())
                $summary = if ($signals.Count -gt 0) { $script:SellerIntelligenceText.daily_signal_count -f $signals.Count } else { $script:SellerIntelligenceText.no_daily_signals }
                $sections.Add([pscustomobject]@{ title = $script:SellerIntelligenceText.daily_title; statements = @($summary) })
                $sections.Add([pscustomobject]@{ title = $script:SellerIntelligenceText.summary_title; statements = @($script:SellerIntelligenceText.comparable_daily) })
            }
        }
        else {
            $currentRows = @(Get-SellerCategoryRows -Snapshot $Snapshot -CategoryKey $CategoryKey)
            $previousRows = if ($null -ne $PreviousSnapshot) { @(Get-SellerCategoryRows -Snapshot $PreviousSnapshot -CategoryKey $CategoryKey) } else { @() }
            $baselineDate = if ($null -eq $PreviousSnapshot) { $null } else { [string](Get-SellerProperty -Object $PreviousSnapshot -Name 'market_date') }
            $targetCount = [int]$selectedCategories[0].TargetCount
            $signals = @(Get-SellerDailySignals -Current $currentRows -Previous $previousRows -BaselineDate $baselineDate -TargetCount $targetCount)
            if (-not (Test-SellerExactTop30 -Items $currentRows -TargetCount $targetCount)) {
                $sections.Add([pscustomobject]@{ title = $script:SellerIntelligenceText.quality_title; statements = @($script:SellerIntelligenceText.incomplete_current) })
            }
            elseif (-not (Test-SellerExactTop30 -Items $previousRows -TargetCount $targetCount)) {
                $sections.Add([pscustomobject]@{ title = $script:SellerIntelligenceText.quality_title; statements = @($script:SellerIntelligenceText.incomparable_previous) })
            }
            else {
                $summary = if ($signals.Count -gt 0) { $script:SellerIntelligenceText.daily_signal_count -f $signals.Count } else { $script:SellerIntelligenceText.no_daily_signals }
                $sections.Add([pscustomobject]@{ title = $script:SellerIntelligenceText.daily_title; statements = @($summary) })
                $sections.Add([pscustomobject]@{ title = $script:SellerIntelligenceText.summary_title; statements = @($script:SellerIntelligenceText.comparable_daily) })
            }
        }
    }
    else {
        if (-not $complete) {
            $sections.Add([pscustomobject]@{ title = $script:SellerIntelligenceText.quality_title; statements = @($script:SellerIntelligenceText.incomplete_current) })
        }
        elseif ($CompleteMarketDays -lt 5) {
            $sections.Add([pscustomobject]@{ title = $script:SellerIntelligenceText.quality_title; statements = @($script:SellerIntelligenceText.insufficient_week) })
        }
        else {
            $sections.Add([pscustomobject]@{ title = $script:SellerIntelligenceText.weekly_title; statements = @($script:SellerIntelligenceText.weekly_summary -f $CompleteMarketDays) })
            if (-not [string]::IsNullOrWhiteSpace($CategoryKey)) {
                $pool = @(Get-SellerCompetitorPool -Snapshots $HistorySnapshots -CategoryKey $CategoryKey -CompleteMarketDays $CompleteMarketDays -RegistryPath $RegistryPath)
                if ($pool.Count -gt 0) {
                    $counts = @(
                        'high=' + (@($pool | Where-Object { $_.priority -eq 'high' }).Count)
                        'medium=' + (@($pool | Where-Object { $_.priority -eq 'medium' }).Count)
                        'low=' + (@($pool | Where-Object { $_.priority -eq 'low' }).Count)
                    ) -join ', '
                    $sections.Add([pscustomobject]@{ title = $script:SellerIntelligenceText.competitor_pool_title; statements = @($script:SellerIntelligenceText.competitor_pool_summary, "Pool objects $($pool.Count); $counts.") })
                }
            }
        }
    }

    if ($sections.Count -eq 0) {
        $sections.Add([pscustomobject]@{ title = $script:SellerIntelligenceText.quality_title; statements = @($script:SellerIntelligenceText.incomplete_current) })
    }

    $reportKind = if ($profileValue -eq 'seller_alert') { 'daily' } else { 'weekly' }
    $categoryValue = if ([string]::IsNullOrWhiteSpace($CategoryKey)) { $null } else { $CategoryKey }
    $reportKey = Get-SellerReportKey -Profile $profileValue -MarketDate $marketDate -CategoryKey $CategoryValue
    $sectionItems = $sections.ToArray()
    $strategy = if ($profileValue -eq 'competition_strategy') {
        New-SellerStrategyFacts -Snapshot $Snapshot -CategoryKey $categoryValue -HistorySnapshots $HistorySnapshots -CompleteMarketDays $CompleteMarketDays -Coverage $coverage -Complete $complete -RegistryPath $RegistryPath
    }
    else { $null }
    $content = [ordered]@{
        schemaVersion = 'seller-intelligence-v1'
        key = $reportKey
        reportKind = $reportKind
        profile = $profileValue
        marketDate = $marketDate
        categoryKey = $categoryValue
        generatedAt = $generatedAt
        generatorVersion = 'seller-rules-v1'
        contentSha256 = ''
        evidence = [ordered]@{
            complete = $complete
            completeMarketDays = $CompleteMarketDays
            sampleSize = $sampleSize
            fieldCoverage = $coverage
        }
        signals = @($signals)
        sections = $sectionItems
        limitations = @(
            $script:SellerIntelligenceText.limitation_manual
            $script:SellerIntelligenceText.limitation_nulls
            $script:SellerIntelligenceText.limitation_coverage
        )
    }
    if ($profileValue -eq 'competition_strategy') { $content.strategy = $strategy }
    $content.contentSha256 = Get-SellerContentHash -Content $content
    return [pscustomobject]$content
}

function New-SellerIntelligenceReports {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Snapshot,
        [Parameter(Mandatory = $true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ReceiptSha256,
        [Parameter(Mandatory = $true)][string]$Profile,
        $PreviousSnapshot,
        [hashtable]$PreviousSnapshotsByCategory = @{},
        [object[]]$HistorySnapshots = @(),
        [ValidateRange(0,365)][int]$CompleteMarketDays = 0,
        [hashtable]$CategoryCompleteMarketDays = @{},
        [hashtable]$CategoryHistorySnapshots = @{},
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )

    $profileValue = Get-SellerProfileValue -Profile $Profile
    $reports = New-Object System.Collections.Generic.List[object]
    if ($profileValue -eq 'competition_strategy' -or $profileValue -eq 'seller_alert') {
        $reports.Add((New-SellerIntelligenceReport -Snapshot $Snapshot -ReceiptSha256 $ReceiptSha256 -Profile $profileValue -PreviousSnapshot $PreviousSnapshot -HistorySnapshots $HistorySnapshots -CompleteMarketDays $CompleteMarketDays -RegistryPath $RegistryPath))
    }

    foreach ($category in @(Get-SellerIntelligenceCategories -RegistryPath $RegistryPath)) {
        $categoryDays = if ($CategoryCompleteMarketDays.ContainsKey($category.Key)) { [int]$CategoryCompleteMarketDays[$category.Key] } else { $CompleteMarketDays }
        $categoryHistory = if ($CategoryHistorySnapshots.ContainsKey($category.Key)) { @($CategoryHistorySnapshots[$category.Key]) } else { $HistorySnapshots }
        $categoryPrevious = if ($PreviousSnapshotsByCategory.ContainsKey($category.Key)) { $PreviousSnapshotsByCategory[$category.Key] } else { $PreviousSnapshot }
        $reports.Add((New-SellerIntelligenceReport -Snapshot $Snapshot -ReceiptSha256 $ReceiptSha256 -Profile $profileValue -CategoryKey $category.Key -PreviousSnapshot $categoryPrevious -HistorySnapshots $categoryHistory -CompleteMarketDays $categoryDays -RegistryPath $RegistryPath))
    }

    return $reports.ToArray()
}

function Write-SellerIntelligenceReports {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Reports,
        [Parameter(Mandatory = $true)][string]$OutputDirectory
    )

    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($report in @($Reports)) {
        $relativePath = ([string](Get-SellerProperty -Object $report -Name 'key')).Replace('/', '\')
        $destination = Join-Path $OutputDirectory $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        [IO.File]::WriteAllText($destination, ($report | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($true)))
        $paths.Add($destination)
    }
    return $paths.ToArray()
}

Export-ModuleMember -Function Test-SellerExactTop30, Get-SellerDailySignals, Get-SellerCompetitorPool, Get-SellerSpecifications, New-SellerIntelligenceReport, New-SellerIntelligenceReports, Write-SellerIntelligenceReports
