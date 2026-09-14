function Decode-WeeklyReportText {
    param([Parameter(Mandatory=$true)][string]$Value)
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value))
}

function ConvertTo-WeeklyMarkdownCell {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return '-' }
    return ([string]$Value).Replace("`r", ' ').Replace("`n", ' ').Replace('|', '\|')
}

function ConvertTo-WeeklyHtmlCell {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return '-' }
    return [System.Net.WebUtility]::HtmlEncode(([string]$Value).Replace("`r", ' ').Replace("`n", ' '))
}

function Format-WeeklyRankChange {
    param($Value)
    if ($null -eq $Value) { return '-' }
    $number = [int]$Value
    if ($number -gt 0) { return "+$number" }
    return [string]$number
}

function Format-WeeklyDiscountText {
    param($Discounts)
    $parts = @()
    foreach ($discount in @($Discounts)) {
        if ($null -eq $discount) { continue }
        $kind = [string]$discount.kind
        $amount = [string]$discount.amount
        $parts += if ([string]::IsNullOrWhiteSpace($kind)) { $amount } elseif ([string]::IsNullOrWhiteSpace($amount)) { $kind } else { "${kind}: $amount" }
    }
    if ($parts.Count -eq 0) { return '-' }
    return ($parts -join '; ')
}

function New-BestSellersWeeklyCategorySections {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$CategoryKey,
        [Parameter(Mandatory=$true)]$WeeklyAnalysis,
        [Parameter(Mandatory=$true)]$RankInfluence,
        [bool]$LimitedCoverage = $false
    )

    $weeklyCategory = @($WeeklyAnalysis.categories | Where-Object { [string]$_.category -eq $CategoryKey })
    $influenceCategory = @($RankInfluence.categories | Where-Object { [string]$_.category -eq $CategoryKey })
    if ($weeklyCategory.Count -ne 1 -or $influenceCategory.Count -ne 1) {
        throw "Analysis artifacts do not contain exactly one category: $CategoryKey"
    }

    $swings = @($WeeklyAnalysis.large_swings | Where-Object { [string]$_.category -eq $CategoryKey -and [int]$_.absolute_change -ge 10 } | Sort-Object @{Expression='absolute_change';Descending=$true}, market_date, current_rank)
    $entries = @($WeeklyAnalysis.new_entries | Where-Object { [string]$_.category -eq $CategoryKey } | Sort-Object market_date, current_rank)
    $exits = @($WeeklyAnalysis.exits | Where-Object { [string]$_.category -eq $CategoryKey } | Sort-Object market_date, previous_rank)
    $discountTransitions = @(
        if ($null -ne $WeeklyAnalysis.PSObject.Properties['discount_transitions']) {
            @($WeeklyAnalysis.discount_transitions | Where-Object { [string]$_.category -eq $CategoryKey } | Sort-Object market_date, asin)
        } else {
            @()
        }
    )
    $discountSummary = if ($null -ne $weeklyCategory[0].PSObject.Properties['discount_summary']) { $weeklyCategory[0].discount_summary } else { [pscustomobject]@{ added_count=0; removed_count=0; amount_changed_count=0; unchanged_count=0; unknown_count=0 } }
    $associations = @($influenceCategory[0].cross_sectional_associations) + @($influenceCategory[0].longitudinal_associations)

    $label = @{
        limited = Decode-WeeklyReportText '6aaW5qyh5pyJ6ZmQ5ZGo5bqm5YiG5p6Q77ya5b2T5YmN57uT5p6c5LuF5L2c5Li65Yid5aeL5Z+657q/77yM5LiN5p6E5oiQ6LaL5Yq/5oiW5Zug5p6c57uT6K6644CC'
        swings = Decode-WeeklyReportText '5aSn5bmF5o6S5ZCN5Y+Y5YyW77yI57ud5a+55Y+Y5YyW6Iez5bCRIDEwIOWQje+8iQ=='
        empty = Decode-WeeklyReportText '5pys5ZGo5peg56ym5ZCI6ZiI5YC855qE6K6w5b2V44CC'
        priority = Decode-WeeklyReportText '5LyY5YWI57qn'; date = Decode-WeeklyReportText '5pel5pyf'; product = Decode-WeeklyReportText '5Lqn5ZOB'
        previous_rank = Decode-WeeklyReportText '5LiK5LiA5o6S5ZCN'; current_rank = Decode-WeeklyReportText '5b2T5YmN5o6S5ZCN'; change = Decode-WeeklyReportText '5Y+Y5YyW'
        high = Decode-WeeklyReportText '6auY5LyY5YWI57qn'; watch = Decode-WeeklyReportText '5YWz5rOo'
        entries = Decode-WeeklyReportText '5paw5YWlIFRvcCAzMA=='; rank = Decode-WeeklyReportText '5o6S5ZCN'; exits = Decode-WeeklyReportText '6YCA5Ye6IFRvcCAzMA=='
        associations = Decode-WeeklyReportText '5Lu35qC844CB6K+E6K665pif57qn5ZKM6K+E6K665pWw5LiO5o6S5ZCN55qE5YWz6IGU'
        metric = Decode-WeeklyReportText '5oyH5qCH'; sample = Decode-WeeklyReportText '5qC35pys6YeP'; status = Decode-WeeklyReportText '54q25oCB'; direction = Decode-WeeklyReportText '5pa55ZCR'; strength = Decode-WeeklyReportText '5by65bqm'
        disclaimer = Decode-WeeklyReportText '5LuF6KGo56S657uf6K6h5YWz6IGU77yM5LiN5Luj6KGo5Lu35qC844CB6K+E6K665pif57qn5oiW6K+E6K665pWw5a+86Ie05o6S5ZCN5Y+Y5YyW44CC'
        offer_ranking = Decode-WeeklyReportText '5LyY5oOg5LiO5o6S5ZCN6KeC5a+f'; previous_date = Decode-WeeklyReportText '5YmN5LiA5pel5pyf'; current_date = Decode-WeeklyReportText '5b2T5YmN5pel5pyf'; previous_discount = Decode-WeeklyReportText '5YmN5LiA5LyY5oOg'; current_discount = Decode-WeeklyReportText '5b2T5YmN5LyY5oOg'; previous_discount_state = Decode-WeeklyReportText '5YmN5LiA5LyY5oOg54q25oCB'; current_discount_state = Decode-WeeklyReportText '5b2T5YmN5LyY5oOg54q25oCB'; transition_kind = Decode-WeeklyReportText '6L2s5o2i57G75Z6L'
        added = Decode-WeeklyReportText '5paw5aKe5LyY5oOg'; removed = Decode-WeeklyReportText '5Y+W5raI5LyY5oOg'; amount_changed = Decode-WeeklyReportText '5LyY5oOg6YeR6aKd5Y+Y5YyW'; unchanged = Decode-WeeklyReportText '5pyq5Y+Y5YyW'; unknown = Decode-WeeklyReportText '5pyq55+l'
        unavailable = 'Unavailable'
        discount_disclaimer = 'it is observed co-movement only and does not establish a discount caused a rank change.'
    }
    $metricLabels = @{
        PRICE_USD = Decode-WeeklyReportText '5Lu35qC8'; RATING_STARS = Decode-WeeklyReportText '6K+E6K665pif57qn'; LOG10_REVIEW_COUNT_PLUS_1 = Decode-WeeklyReportText '6K+E6K665pWw'
        PRICE_CHANGE_USD = Decode-WeeklyReportText '5Lu35qC85Y+Y5YyW'; REVIEW_GROWTH = Decode-WeeklyReportText '6K+E6K665pWw5aKe6ZW/'
    }
    $statusLabels = @{ ANALYZED = Decode-WeeklyReportText '5bey5YiG5p6Q'; INSUFFICIENT_SAMPLE = Decode-WeeklyReportText '5qC35pys5LiN6Laz'; UNAVAILABLE = Decode-WeeklyReportText '5pWw5o2u5LiN5Y+v55So' }
    $directionLabels = @{ HIGHER_ASSOCIATED_WITH_BETTER_RANK = Decode-WeeklyReportText '5pWw5YC86LaK6auY5LiO5pu05aW95o6S5ZCN55u45YWz'; HIGHER_ASSOCIATED_WITH_WORSE_RANK = Decode-WeeklyReportText '5pWw5YC86LaK6auY5LiO5pu05beu5o6S5ZCN55u45YWz'; NO_CLEAR_DIRECTION = Decode-WeeklyReportText '5peg5piO56Gu5pa55ZCR' }
    $strengthLabels = @{ VERY_STRONG = Decode-WeeklyReportText '5b6I5by6'; STRONG = Decode-WeeklyReportText '5by6'; MODERATE = Decode-WeeklyReportText '5Lit562J'; WEAK = Decode-WeeklyReportText '5byx'; VERY_WEAK = Decode-WeeklyReportText '5b6I5byx'; NONE = Decode-WeeklyReportText '5peg' }

    $md = New-Object Text.StringBuilder
    $html = New-Object Text.StringBuilder
    if ($LimitedCoverage) {
        [void]$md.AppendLine("> $($label.limited)"); [void]$md.AppendLine()
        [void]$html.Append("<p class=`"warning`">$(ConvertTo-WeeklyHtmlCell $label.limited)</p>")
    }

    [void]$md.AppendLine("## $($label.swings)"); [void]$md.AppendLine()
    [void]$html.Append("<h2>$(ConvertTo-WeeklyHtmlCell $label.swings)</h2>")
    if ($swings.Count -eq 0) {
        [void]$md.AppendLine($label.empty); [void]$html.Append("<p>$(ConvertTo-WeeklyHtmlCell $label.empty)</p>")
    } else {
        [void]$md.AppendLine("| $($label.priority) | $($label.date) | ASIN | $($label.product) | $($label.previous_rank) | $($label.current_rank) | $($label.change) |")
        [void]$md.AppendLine('|---|---|---|---|---:|---:|---:|')
        [void]$html.Append("<table><thead><tr><th>$($label.priority)</th><th>$($label.date)</th><th>ASIN</th><th>$($label.product)</th><th>$($label.previous_rank)</th><th>$($label.current_rank)</th><th>$($label.change)</th></tr></thead><tbody>")
        foreach ($item in $swings) {
            $priority = if ([int]$item.absolute_change -ge 20) { $label.high } else { $label.watch }
            $change = Format-WeeklyRankChange $item.rank_change
            [void]$md.AppendLine("| $(ConvertTo-WeeklyMarkdownCell $priority) | $(ConvertTo-WeeklyMarkdownCell $item.market_date) | $(ConvertTo-WeeklyMarkdownCell $item.asin) | $(ConvertTo-WeeklyMarkdownCell $item.title) | $($item.previous_rank) | $($item.current_rank) | $change |")
            [void]$html.Append("<tr><td>$(ConvertTo-WeeklyHtmlCell $priority)</td><td>$(ConvertTo-WeeklyHtmlCell $item.market_date)</td><td>$(ConvertTo-WeeklyHtmlCell $item.asin)</td><td>$(ConvertTo-WeeklyHtmlCell $item.title)</td><td>$($item.previous_rank)</td><td>$($item.current_rank)</td><td>$change</td></tr>")
        }
        [void]$html.Append('</tbody></table>')
    }
    [void]$md.AppendLine()

    foreach ($transition in @(@{ Title=$label.entries; Items=$entries; RankField='current_rank' }, @{ Title=$label.exits; Items=$exits; RankField='previous_rank' })) {
        [void]$md.AppendLine("## $($transition.Title)"); [void]$md.AppendLine()
        [void]$html.Append("<h2>$(ConvertTo-WeeklyHtmlCell $transition.Title)</h2>")
        if ($transition.Items.Count -eq 0) {
            [void]$md.AppendLine($label.empty); [void]$html.Append("<p>$(ConvertTo-WeeklyHtmlCell $label.empty)</p>")
        } else {
            [void]$md.AppendLine("| $($label.date) | ASIN | $($label.product) | $($label.rank) |")
            [void]$md.AppendLine('|---|---|---|---:|')
            [void]$html.Append("<table><thead><tr><th>$($label.date)</th><th>ASIN</th><th>$($label.product)</th><th>$($label.rank)</th></tr></thead><tbody>")
            foreach ($item in $transition.Items) {
                $rankValue = $item.($transition.RankField)
                [void]$md.AppendLine("| $(ConvertTo-WeeklyMarkdownCell $item.market_date) | $(ConvertTo-WeeklyMarkdownCell $item.asin) | $(ConvertTo-WeeklyMarkdownCell $item.title) | $rankValue |")
                [void]$html.Append("<tr><td>$(ConvertTo-WeeklyHtmlCell $item.market_date)</td><td>$(ConvertTo-WeeklyHtmlCell $item.asin)</td><td>$(ConvertTo-WeeklyHtmlCell $item.title)</td><td>$(ConvertTo-WeeklyHtmlCell $rankValue)</td></tr>")
            }
            [void]$html.Append('</tbody></table>')
        }
        [void]$md.AppendLine()
    }

    [void]$md.AppendLine("## $($label.offer_ranking)"); [void]$md.AppendLine()
    [void]$html.Append("<h2>$(ConvertTo-WeeklyHtmlCell $label.offer_ranking)</h2>")
    $summaryText = "$($label.added): $($discountSummary.added_count); $($label.removed): $($discountSummary.removed_count); $($label.amount_changed): $($discountSummary.amount_changed_count); $($label.unchanged): $($discountSummary.unchanged_count); $($label.unknown): $($discountSummary.unknown_count)"
    [void]$md.AppendLine((ConvertTo-WeeklyMarkdownCell $summaryText))
    [void]$html.Append("<p>$(ConvertTo-WeeklyHtmlCell $summaryText)</p>")
    if ($discountTransitions.Count -eq 0) {
        [void]$md.AppendLine($label.empty); [void]$html.Append("<p>$(ConvertTo-WeeklyHtmlCell $label.empty)</p>")
    } else {
        [void]$md.AppendLine("| $($label.previous_date) | $($label.current_date) | ASIN | $($label.previous_discount_state) | $($label.current_discount_state) | $($label.transition_kind) | $($label.previous_discount) | $($label.current_discount) | $($label.previous_rank) | $($label.current_rank) | $($label.change) |")
        [void]$md.AppendLine('|---|---|---|---|---|---|---|---|---:|---:|---:|')
        [void]$html.Append("<table><thead><tr><th>$($label.previous_date)</th><th>$($label.current_date)</th><th>ASIN</th><th>$($label.previous_discount_state)</th><th>$($label.current_discount_state)</th><th>$($label.transition_kind)</th><th>$($label.previous_discount)</th><th>$($label.current_discount)</th><th>$($label.previous_rank)</th><th>$($label.current_rank)</th><th>$($label.change)</th></tr></thead><tbody>")
        foreach ($item in $discountTransitions) {
            $isUnknown = [string]$item.transition_kind -eq 'UNKNOWN'
            $previousDiscountState = if ($isUnknown) { $label.unavailable } else { $item.previous_has_discount }
            $discountState = if ($isUnknown) { $label.unavailable } else { $item.has_discount }
            $previousDiscountText = if ($isUnknown) { $label.unavailable } else { Format-WeeklyDiscountText $item.previous_discounts }
            $discountText = if ($isUnknown) { $label.unavailable } else { Format-WeeklyDiscountText $item.discounts }
            $rankChange = Format-WeeklyRankChange $item.rank_change
            [void]$md.AppendLine("| $(ConvertTo-WeeklyMarkdownCell $item.previous_market_date) | $(ConvertTo-WeeklyMarkdownCell $item.market_date) | $(ConvertTo-WeeklyMarkdownCell $item.asin) | $(ConvertTo-WeeklyMarkdownCell $previousDiscountState) | $(ConvertTo-WeeklyMarkdownCell $discountState) | $(ConvertTo-WeeklyMarkdownCell $item.transition_kind) | $(ConvertTo-WeeklyMarkdownCell $previousDiscountText) | $(ConvertTo-WeeklyMarkdownCell $discountText) | $(ConvertTo-WeeklyMarkdownCell $item.previous_rank) | $(ConvertTo-WeeklyMarkdownCell $item.current_rank) | $(ConvertTo-WeeklyMarkdownCell $rankChange) |")
            [void]$html.Append("<tr><td>$(ConvertTo-WeeklyHtmlCell $item.previous_market_date)</td><td>$(ConvertTo-WeeklyHtmlCell $item.market_date)</td><td>$(ConvertTo-WeeklyHtmlCell $item.asin)</td><td>$(ConvertTo-WeeklyHtmlCell $previousDiscountState)</td><td>$(ConvertTo-WeeklyHtmlCell $discountState)</td><td>$(ConvertTo-WeeklyHtmlCell $item.transition_kind)</td><td>$(ConvertTo-WeeklyHtmlCell $previousDiscountText)</td><td>$(ConvertTo-WeeklyHtmlCell $discountText)</td><td>$(ConvertTo-WeeklyHtmlCell $item.previous_rank)</td><td>$(ConvertTo-WeeklyHtmlCell $item.current_rank)</td><td>$(ConvertTo-WeeklyHtmlCell $rankChange)</td></tr>")
        }
        [void]$html.Append('</tbody></table>')
    }
    [void]$md.AppendLine(); [void]$md.AppendLine("> $($label.discount_disclaimer)")
    [void]$html.Append("<p class=`"note`">$(ConvertTo-WeeklyHtmlCell $label.discount_disclaimer)</p>")
    [void]$md.AppendLine()

    [void]$md.AppendLine("## $($label.associations)"); [void]$md.AppendLine()
    [void]$html.Append("<h2>$(ConvertTo-WeeklyHtmlCell $label.associations)</h2>")
    if ($associations.Count -eq 0) {
        [void]$md.AppendLine($label.empty); [void]$html.Append("<p>$(ConvertTo-WeeklyHtmlCell $label.empty)</p>")
    } else {
        [void]$md.AppendLine("| $($label.metric) | $($label.sample) | $($label.status) | Spearman rho | $($label.direction) | $($label.strength) |")
        [void]$md.AppendLine('|---|---:|---|---:|---|---|')
        [void]$html.Append("<table><thead><tr><th>$($label.metric)</th><th>$($label.sample)</th><th>$($label.status)</th><th>Spearman rho</th><th>$($label.direction)</th><th>$($label.strength)</th></tr></thead><tbody>")
        foreach ($item in $associations) {
            $metric = if ($metricLabels.ContainsKey([string]$item.metric)) { $metricLabels[[string]$item.metric] } else { [string]$item.metric }
            $status = if ($statusLabels.ContainsKey([string]$item.status)) { $statusLabels[[string]$item.status] } else { [string]$item.status }
            $direction = if ($directionLabels.ContainsKey([string]$item.direction)) { $directionLabels[[string]$item.direction] } else { [string]$item.direction }
            $strength = if ($strengthLabels.ContainsKey([string]$item.strength)) { $strengthLabels[[string]$item.strength] } else { [string]$item.strength }
            $rho = if ($null -eq $item.spearman_rho) { '-' } else { [string]$item.spearman_rho }
            [void]$md.AppendLine("| $(ConvertTo-WeeklyMarkdownCell $metric) | $(ConvertTo-WeeklyMarkdownCell $item.sample_size) | $(ConvertTo-WeeklyMarkdownCell $status) | $rho | $(ConvertTo-WeeklyMarkdownCell $direction) | $(ConvertTo-WeeklyMarkdownCell $strength) |")
            [void]$html.Append("<tr><td>$(ConvertTo-WeeklyHtmlCell $metric)</td><td>$(ConvertTo-WeeklyHtmlCell $item.sample_size)</td><td>$(ConvertTo-WeeklyHtmlCell $status)</td><td>$(ConvertTo-WeeklyHtmlCell $rho)</td><td>$(ConvertTo-WeeklyHtmlCell $direction)</td><td>$(ConvertTo-WeeklyHtmlCell $strength)</td></tr>")
        }
        [void]$html.Append('</tbody></table>')
    }
    [void]$md.AppendLine(); [void]$md.AppendLine("> $($label.disclaimer)")
    [void]$html.Append("<p class=`"note`">$(ConvertTo-WeeklyHtmlCell $label.disclaimer)</p>")

    [pscustomobject]@{
        Markdown = $md.ToString(); Html = $html.ToString()
        LargeSwingCount = $swings.Count; NewEntryCount = $entries.Count; ExitCount = $exits.Count; DiscountTransitionCount = $discountTransitions.Count; AssociationCount = $associations.Count
    }
}

Export-ModuleMember -Function New-BestSellersWeeklyCategorySections
