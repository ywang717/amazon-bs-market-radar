Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'BestSellersCategoryRegistry.psm1') -Scope Local

function ConvertFrom-BestSellersDailyText {
    param([Parameter(Mandatory = $true)][string]$Base64)
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Base64))
}

function Get-BestSellersDailyText {
    $text = @{
        title_prefix = 'QW1hem9uIOe+juWbveermSBCZXN0IFNlbGxlcnMg5pel5oql772c5YyX5Lqs5pe26Ze0IA=='
        market_date = 'QW1hem9uIOW4guWcuuaXpe+8mg=='; scope = '55uR5o6n6IyD5Zu077ya6auY5Y6L5riF5rSX5py644CB5rGh5rC05rO144CB6auY5Y6L5riF5rSX5py66YWN5Lu277yM5ZCE5qac5Y2V55uu5qCHIFRvcCA1MOOAgg=='
        purpose = '5pel5oql6IGM6LSj77ya6K6w5b2V6YeH6ZuG57uT5p6c5bm25o+Q56S65bey6aqM6K+B55qE5piO5pi+5o6S5ZCN5Y+Y5YyW77yb5LiN6L+b6KGM5py65Lya6K+E5YiG5oiW5b2S5Zug5YiG5p6Q44CC'
        quality = '6YeH6ZuG6LSo6YeP'; chart = '5qac5Y2V'; collected = '5bey6YeH6ZuG'; completeness = '5a6M5pW05oCn'; comparable = '5Y+v55So5LqO5pel546v5q+U'; missing = '57y65aSx5o6S5ZCN'
        complete = '5a6M5pW0IFRvcCA1MA=='; incomplete = '5LiN5a6M5pW0'; yes = '5piv'; no = '5ZCm'; changes = '5piO5pi+5qac5Y2V5Y+Y5YyW'
        baseline = '6aaW5qyh5b+r54Wn77yM5LuF5bu656uL5Z+657q/77yb5pqC5peg5Y+v5q+U6L6D55qE5o6S5ZCN5Y+Y5YyW44CC'
        no_comparison = '5b2T5YmN5oiW5LiK5LiA5biC5Zy65pel5rKh5pyJ5Lu75L2V5a6M5pW0IFRvcCA1MCDmppzljZXvvJvkuLrpgb/lhY3or6/miqXvvIzmnKzml6XkuI3ovpPlh7rmjpLlkI3ljYfpmY3jgIHmlrDlhaXmppzmiJbpgIDlh7rmppzljZXliKTmlq3jgII='
        no_change_prefix = '5bey5a6M5oiQ5Y+v5q+U5qac5Y2V5Lit77yM5rKh5pyJ6L6+5Yiw'; no_change_suffix = '5ZCN55qE5o6S5ZCN5Y+Y5YyW77yM5Lmf5pyq5qOA5rWL5YiwIFRvcCA1MCDmlrDlhaXmppzmiJbpgIDlh7rjgII='
        priority = '5LyY5YWI57qn'; movement = '5Y+Y5YyW'; product = '5ZWG5ZOB'; rank = '5o6S5ZCN'; entry = '5paw5YWlIFRvcCA1MA=='; exit = '6YCA5Ye6IFRvcCA1MA=='; rising = '5LiK5Y2HIA=='; falling = '5LiL6ZmNIA=='; prior_rank = '5LiK5pyfICM='
        notes = '5pWw5o2u6K+05piO'; note_one = '5LuF5L2/55So5LiJ5Liq5YWs5byAIEJlc3QgU2VsbGVycyDni6znq4vmppzljZXnmoTlt7Lpqozor4Hlj6/op4HlrZfmrrXjgILku7fmoLzjgIHmmJ/nuqfkuI7or4TorrrmlbDku4XkvZzorrDlvZXvvIzkuI3lnKjml6XmiqXkuK3op6Pph4rmjpLlkI3lm6DmnpzjgII='
        note_two = '5Lu75L2V5LiN5a6M5pW05qac5Y2V5LiN5Lya6K6h5YWl5a6M5pW05biC5Zy65pel77yM5Lmf5LiN5Lya55So5LqO5pel546v5q+U5oiW5ZGo5bqm5a6M5pW05YiG5p6Q44CC'
        note_three = '5a6M5pW055qE5py65Lya44CB5biC5Zy657uT5p6E5Y+K5Lu35qC8L+aYn+e6py/or4TorrrlhbPogZTliIbmnpDku4XlnKjlkajmiqXkuK3jgIHkuJTmu6HotrPljoblj7Jopobnm5bmnaHku7blkI7lkYjnjrDjgII='
        html_summary = '5pel5oql5LuF6K6w5b2V5LiO5o+Q56S65bey6aqM6K+B5Y+Y5YyW44CC'; html_no_comparison = '5rKh5pyJ5Y+v5q+U6L6D55qE5a6M5pW0IFRvcCA1MCDmppzljZXvvJvmnKzml6XkuI3ovpPlh7rlj5jljJbliKTmlq3jgII='
        html_no_change_prefix = '5rKh5pyJ6L6+5Yiw'; html_no_change_suffix = '5ZCN55qE5Y+Y5YyW77yM5Lmf5rKh5pyJIFRvcCA1MCDmlrDlhaXmppzmiJbpgIDlh7rjgII='
        html_note = '5LiN5a6M5pW05qac5Y2V5LiN5Lya55So5LqO5pel546v5q+U5oiW5a6M5pW05biC5Zy65pel57uf6K6h44CC5Lu35qC844CB5pif57qn5ZKM6K+E6K665pWw5LuF5L2c6K6w5b2V77yb5py65Lya5ZKM5YWz6IGU5YiG5p6Q5Y+q5Zyo56ym5ZCI6KaG55uW5p2h5Lu255qE5ZGo5oql5Lit5bGV56S644CC'
    }
    $result = @{}
    foreach ($key in $text.Keys) { $result[$key] = ConvertFrom-BestSellersDailyText -Base64 $text[$key] }
    return $result
}

function ConvertTo-BestSellersDailyMarkdownText { param($Value) if ($null -eq $Value) { return '' }; return ([string]$Value).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ') }
function ConvertTo-BestSellersDailyHtmlText { param($Value) if ($null -eq $Value) { return '' }; return [Net.WebUtility]::HtmlEncode([string]$Value) }
function Get-BestSellersDailyQualityMap { param([Parameter(Mandatory = $true)]$Quality) $map = @{}; foreach ($item in @($Quality.categories)) { $map[[string]$item.category] = $item }; return $map }
function Format-BestSellersDiscountDisplay {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Item)

    $discountProperty = $Item.PSObject.Properties['has_discount']
    if ($null -eq $discountProperty -or $null -eq $discountProperty.Value) { return 'Pending verification' }
    if ($discountProperty.Value -eq $false) { return 'None' }
    $discountsProperty = $Item.PSObject.Properties['discounts']
    $amounts = @()
    if ($null -ne $discountsProperty) {
        foreach ($discount in @($discountsProperty.Value)) {
            if ($null -ne $discount -and -not [string]::IsNullOrWhiteSpace([string]$discount.amount)) { $amounts += [string]$discount.amount }
        }
    }
    return $amounts -join '; '
}
function Get-BestSellersDailyDiscountSummary {
    param([Parameter(Mandatory = $true)]$Items)
    $discounted = 0; $none = 0; $unknown = 0
    foreach ($item in @($Items)) {
        $discountProperty = $item.PSObject.Properties['has_discount']
        if ($null -eq $discountProperty -or $null -eq $discountProperty.Value) { $unknown++ }
        elseif ($discountProperty.Value -eq $true) { $discounted++ }
        else { $none++ }
    }
    return "Verified discounted: $discounted; verified not discounted: $none; pending/unknown: $unknown"
}

function New-BestSellersDailyReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$CurrentSnapshot, $PreviousSnapshot,
        [Parameter(Mandatory = $true)][string]$OutputDirectory,
        [string[]]$CategoryKeys,
        [datetimeoffset]$GeneratedAtBeijing = [DateTimeOffset]::Now,
        [ValidateRange(1, 100)][int]$SwingThreshold = 10,
        [ValidateRange(1, 100)][int]$HighPriorityThreshold = 20,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )
    $registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
    $enabledCategories = @($registry.Categories | Where-Object Enabled)
    $selectedCategoryKeys = @($CategoryKeys | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    $selectedCategories = if ($selectedCategoryKeys.Count -gt 0) {
        @($selectedCategoryKeys | ForEach-Object { Get-BestSellersCategory -Registry $registry -CategoryKey ([string]$_) })
    }
    else { $enabledCategories }
    $selectedCategories = @($selectedCategories)
    $marketDate = [string]$CurrentSnapshot.market_date
    if ($marketDate -notmatch '^\d{4}-\d{2}-\d{2}$') { throw 'Current snapshot must have a YYYY-MM-DD market_date.' }
    if ($HighPriorityThreshold -lt $SwingThreshold) { throw 'HighPriorityThreshold must be greater than or equal to SwingThreshold.' }
    if (-not (Test-Path -LiteralPath $OutputDirectory)) { New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null }
    $t = Get-BestSellersDailyText
    # Keep the existing base64-encoded UTF-8 text table and change only its scope.
    foreach ($textKey in @('scope', 'complete', 'no_comparison', 'no_change_suffix', 'entry', 'exit', 'html_no_comparison', 'html_no_change_suffix')) {
        $t[$textKey] = ([string]$t[$textKey]).Replace('Top 50', 'Top 30')
    }
    $selectedLabels = @($selectedCategories | ForEach-Object LabelZh)
    $categoryDelimiter = [char]0x3001
    $t.scope = (ConvertFrom-BestSellersDailyText -Base64 '55uR5o6n6IyD5Zu077ya') + ($selectedLabels -join $categoryDelimiter) + (ConvertFrom-BestSellersDailyText -Base64 '77yM5ZCE5qac5Y2V55uu5qCH5LulIENhdGVnb3J5IFJlZ2lzdHJ5IOS4uuWHhuOAgg==')
    $t.note_one = ConvertFrom-BestSellersDailyText -Base64 '5LuF5L2/55So5b2T5YmN5oql5ZGK6IyD5Zu05YaF5YWs5byAIEJlc3QgU2VsbGVycyDni6znq4vmppzljZXnmoTlt7Lpqozor4Hlj6/op4HlrZfmrrXjgILku7fmoLzjgIHmmJ/nuqfkuI7or4TorrrmlbDku4XkvZzorrDlvZXvvIzkuI3lnKjml6XmiqXkuK3op6Pph4rmjpLlkI3lm6DmnpzjgII='
    $t.rankings_section = ConvertFrom-BestSellersDailyText -Base64 '5ZCE5qac5Y2V5a6M5pW05o6S5ZCN'
    $t.price = ConvertFrom-BestSellersDailyText -Base64 '5Lu35qC8'
    $t.rating = ConvertFrom-BestSellersDailyText -Base64 '5pif57qn'
    $t.reviews = ConvertFrom-BestSellersDailyText -Base64 '6K+E6K665pWw'
    foreach ($category in $enabledCategories) { $t[$category.CategoryKey] = $category.LabelZh }
    $categories = @($selectedCategories | ForEach-Object CategoryKey)
    $currentQuality = Test-BestSellersTop50Snapshot -Snapshot $CurrentSnapshot -RegistryPath $RegistryPath
    $previousQuality = if ($null -ne $PreviousSnapshot) { Test-BestSellersTop50Snapshot -Snapshot $PreviousSnapshot -RegistryPath $RegistryPath } else { $null }
    $currentMap = Get-BestSellersDailyQualityMap -Quality $currentQuality; $previousMap = if ($null -ne $previousQuality) { Get-BestSellersDailyQualityMap -Quality $previousQuality } else { @{} }
    $comparableCategories = @()
    if ($null -ne $previousQuality) { foreach ($category in $categories) { if ($currentMap[$category].is_complete -and $previousMap[$category].is_complete) { $comparableCategories += $category } } }
    $comparison = Compare-BestSellersSnapshots -CurrentSnapshot $CurrentSnapshot -PreviousSnapshot $PreviousSnapshot -SwingThreshold $SwingThreshold -HighPriorityThreshold $HighPriorityThreshold -RegistryPath $RegistryPath
    $noteworthy = @($comparison.noteworthy | Where-Object { $comparableCategories -contains $_.category })
    $timestamp = $GeneratedAtBeijing.ToString('yyyy-MM-dd HH:mm'); $fileToken = $GeneratedAtBeijing.ToString('yyyy-MM-dd_HHmm') + '_BJT'
    $chartFileToken = if ($selectedCategories.Count -eq 1) { [string]$selectedCategories[0].ReportFileToken } else { 'All_Charts' }
    $reportTitle = if ($categories.Count -eq 1) { "$($t.title_prefix)$($t[$categories[0]]) - $timestamp" } else { "$($t.title_prefix)$timestamp" }
    $markdownPath = Join-Path $OutputDirectory ("Amazon_US_Best_Sellers_{0}_{1}_{2}.md" -f $chartFileToken, $marketDate, $fileToken)
    $htmlPath = Join-Path $OutputDirectory ("Amazon_US_Best_Sellers_{0}_{1}_{2}.html" -f $chartFileToken, $marketDate, $fileToken)
    $md = New-Object Text.StringBuilder
    [void]$md.AppendLine("# $reportTitle"); [void]$md.AppendLine(); [void]$md.AppendLine("- $($t.market_date)$marketDate"); [void]$md.AppendLine("- $($t.scope)"); [void]$md.AppendLine("- $($t.purpose)"); [void]$md.AppendLine()
    [void]$md.AppendLine("## $($t.quality)"); [void]$md.AppendLine(); [void]$md.AppendLine("| $($t.chart) | $($t.collected) | $($t.completeness) | $($t.comparable) | $($t.missing) |"); [void]$md.AppendLine('|---|---:|---|---|---|')
    foreach ($category in $categories) { $quality = $currentMap[$category]; $missing = if (@($quality.missing_ranks).Count -eq 0) { '-' } else { @($quality.missing_ranks) -join ', ' }; $status = if ($quality.is_complete) { $t.complete } else { $t.incomplete }; $comparable = if ($comparableCategories -contains $category) { $t.yes } else { $t.no }; [void]$md.AppendLine("| $($t[$category]) | $($quality.item_count)/$($quality.target_count) | $status ($($quality.completeness_percent)%) | $comparable | $missing |") }
    [void]$md.AppendLine(); [void]$md.AppendLine("## $($t.rankings_section)"); [void]$md.AppendLine()
    foreach ($category in $categories) {
        [void]$md.AppendLine("### $($t[$category])"); [void]$md.AppendLine()
        $categoryItems = @($CurrentSnapshot.$category | Where-Object { $null -ne $_ } | Sort-Object { [int]$_.rank })
        [void]$md.AppendLine("- $(Get-BestSellersDailyDiscountSummary -Items $categoryItems)"); [void]$md.AppendLine()
        [void]$md.AppendLine("| $($t.rank) | $($t.product) | ASIN | $($t.price) | $($t.rating) | $($t.reviews) | Discount |"); [void]$md.AppendLine('|---:|---|---|---:|---:|---:|---|')
        foreach ($item in $categoryItems) {
            $itemRank = if ($null -eq $item.rank) { '-' } else { "#$($item.rank)" }; $price = if ($null -eq $item.price -or [string]::IsNullOrWhiteSpace([string]$item.price)) { '-' } else { [string]$item.price }; $rating = if ($null -eq $item.rating) { '-' } else { [string]$item.rating }; $reviews = if ($null -eq $item.reviews) { '-' } else { [string]$item.reviews }
            $discount = Format-BestSellersDiscountDisplay -Item $item
            [void]$md.AppendLine("| $(ConvertTo-BestSellersDailyMarkdownText $itemRank) | $(ConvertTo-BestSellersDailyMarkdownText $item.title) | $(ConvertTo-BestSellersDailyMarkdownText $item.asin) | $(ConvertTo-BestSellersDailyMarkdownText $price) | $(ConvertTo-BestSellersDailyMarkdownText $rating) | $(ConvertTo-BestSellersDailyMarkdownText $reviews) | $(ConvertTo-BestSellersDailyMarkdownText $discount) |")
        }
        [void]$md.AppendLine()
    }
    [void]$md.AppendLine(); [void]$md.AppendLine("## $($t.changes)"); [void]$md.AppendLine()
    if ($null -eq $PreviousSnapshot) { [void]$md.AppendLine("- $($t.baseline)") } elseif ($comparableCategories.Count -eq 0) { [void]$md.AppendLine("- $($t.no_comparison)") } elseif ($noteworthy.Count -eq 0) { [void]$md.AppendLine("- $($t.no_change_prefix) +/-$SwingThreshold $($t.no_change_suffix)") } else { [void]$md.AppendLine("| $($t.priority) | $($t.chart) | $($t.movement) | $($t.product) | ASIN | $($t.rank) |"); [void]$md.AppendLine('|---|---|---|---|---|---|'); foreach ($item in $noteworthy) { $movement = if ($item.status -eq 'NEW_IN_TOP50') { $t.entry } elseif ($item.status -eq 'DROPPED_FROM_TOP50') { $t.exit } elseif ($item.status -eq 'RISING') { "$($t.rising)$($item.absolute_change)" } else { "$($t.falling)$($item.absolute_change)" }; $rank = if ($null -eq $item.current_rank) { "$($t.prior_rank)$($item.previous_rank)" } else { "#$($item.current_rank)" }; [void]$md.AppendLine("| $($item.priority) | $($t[$item.category]) | $movement | $(ConvertTo-BestSellersDailyMarkdownText $item.title) | $(ConvertTo-BestSellersDailyMarkdownText $item.asin) | $rank |") } }
    [void]$md.AppendLine(); [void]$md.AppendLine("## $($t.notes)"); [void]$md.AppendLine(); [void]$md.AppendLine("- $($t.note_one)"); [void]$md.AppendLine("- $($t.note_two)"); [void]$md.AppendLine('- Observed co-movement only; this does not prove that a discount caused a rank change.')
    $qualityHtml = New-Object Text.StringBuilder
    foreach ($category in $categories) { $quality = $currentMap[$category]; $missing = if (@($quality.missing_ranks).Count -eq 0) { '-' } else { @($quality.missing_ranks) -join ', ' }; $status = if ($quality.is_complete) { $t.complete } else { $t.incomplete }; $comparable = if ($comparableCategories -contains $category) { $t.yes } else { $t.no }; [void]$qualityHtml.Append("<tr><td>$(ConvertTo-BestSellersDailyHtmlText $t[$category])</td><td>$($quality.item_count)/$($quality.target_count)</td><td>$status ($($quality.completeness_percent)%)</td><td>$comparable</td><td>$missing</td></tr>") }
    $rankingsHtml = New-Object Text.StringBuilder
    foreach ($category in $categories) {
        $categoryItems = @($CurrentSnapshot.$category | Where-Object { $null -ne $_ } | Sort-Object { [int]$_.rank })
        $discountSummary = Get-BestSellersDailyDiscountSummary -Items $categoryItems
        [void]$rankingsHtml.Append("<h3>$(ConvertTo-BestSellersDailyHtmlText $t[$category])</h3><p class=`"note`">$(ConvertTo-BestSellersDailyHtmlText $discountSummary)</p><table><thead><tr><th>$($t.rank)</th><th>$($t.product)</th><th>ASIN</th><th>$($t.price)</th><th>$($t.rating)</th><th>$($t.reviews)</th><th>Discount</th></tr></thead><tbody>")
        foreach ($item in $categoryItems) {
            $itemRank = if ($null -eq $item.rank) { '-' } else { "#$($item.rank)" }; $price = if ($null -eq $item.price -or [string]::IsNullOrWhiteSpace([string]$item.price)) { '-' } else { [string]$item.price }; $rating = if ($null -eq $item.rating) { '-' } else { [string]$item.rating }; $reviews = if ($null -eq $item.reviews) { '-' } else { [string]$item.reviews }
            $discount = Format-BestSellersDiscountDisplay -Item $item
            [void]$rankingsHtml.Append("<tr><td>$(ConvertTo-BestSellersDailyHtmlText $itemRank)</td><td>$(ConvertTo-BestSellersDailyHtmlText $item.title)</td><td>$(ConvertTo-BestSellersDailyHtmlText $item.asin)</td><td>$(ConvertTo-BestSellersDailyHtmlText $price)</td><td>$(ConvertTo-BestSellersDailyHtmlText $rating)</td><td>$(ConvertTo-BestSellersDailyHtmlText $reviews)</td><td>$(ConvertTo-BestSellersDailyHtmlText $discount)</td></tr>")
        }
        [void]$rankingsHtml.Append('</tbody></table>')
    }
    $changeHtml = "<p>$($t.baseline)</p>"; if ($null -ne $PreviousSnapshot -and $comparableCategories.Count -eq 0) { $changeHtml = "<p>$($t.html_no_comparison)</p>" } elseif ($null -ne $PreviousSnapshot -and $comparableCategories.Count -gt 0 -and $noteworthy.Count -eq 0) { $changeHtml = "<p>$($t.html_no_change_prefix) +/-$SwingThreshold $($t.html_no_change_suffix)</p>" } elseif ($noteworthy.Count -gt 0) { $changeRows = New-Object Text.StringBuilder; foreach ($item in $noteworthy) { $movement = if ($item.status -eq 'NEW_IN_TOP50') { $t.entry } elseif ($item.status -eq 'DROPPED_FROM_TOP50') { $t.exit } elseif ($item.status -eq 'RISING') { "$($t.rising)$($item.absolute_change)" } else { "$($t.falling)$($item.absolute_change)" }; $rank = if ($null -eq $item.current_rank) { "$($t.prior_rank)$($item.previous_rank)" } else { "#$($item.current_rank)" }; [void]$changeRows.Append("<tr><td>$($item.priority)</td><td>$(ConvertTo-BestSellersDailyHtmlText $t[$item.category])</td><td>$movement</td><td>$(ConvertTo-BestSellersDailyHtmlText $item.title)</td><td>$(ConvertTo-BestSellersDailyHtmlText $item.asin)</td><td>$rank</td></tr>") }; $changeHtml = "<table><thead><tr><th>$($t.priority)</th><th>$($t.chart)</th><th>$($t.movement)</th><th>$($t.product)</th><th>ASIN</th><th>$($t.rank)</th></tr></thead><tbody>$changeRows</tbody></table>" }
    $html = "<!doctype html><html lang=`"zh-CN`"><head><meta charset=`"utf-8`"><style>body{font-family:Segoe UI,Microsoft YaHei,sans-serif;color:#1f2937;line-height:1.55;margin:32px}h1{font-size:22px}h2{font-size:17px;margin-top:28px}h3{font-size:15px;margin-top:24px;break-after:avoid}table{border-collapse:collapse;width:100%;font-size:12px;break-inside:auto}tr{break-inside:avoid}th,td{border:1px solid #d1d5db;padding:6px;text-align:left;vertical-align:top}th{background:#f3f4f6}.meta{background:#eff6ff;padding:12px;border-radius:6px}.note{color:#4b5563;font-size:12px}</style></head><body><h1>$reportTitle</h1><div class=`"meta`">$($t.market_date)$marketDate<br>$($t.scope)<br>$($t.html_summary)</div><h2>$($t.quality)</h2><table><thead><tr><th>$($t.chart)</th><th>$($t.collected)</th><th>$($t.completeness)</th><th>$($t.comparable)</th><th>$($t.missing)</th></tr></thead><tbody>$qualityHtml</tbody></table><h2>$($t.rankings_section)</h2>$rankingsHtml<h2>$($t.changes)</h2>$changeHtml<p class=`"note`">$($t.html_note)</p><p class=`"note`">Observed co-movement only; this does not prove that a discount caused a rank change.</p></body></html>"
    [IO.File]::WriteAllText($markdownPath, $md.ToString(), (New-Object Text.UTF8Encoding($false))); [IO.File]::WriteAllText($htmlPath, $html, (New-Object Text.UTF8Encoding($false)))
    $selectedComplete = @($categories | Where-Object { -not $currentMap[$_].is_complete }).Count -eq 0
    return [pscustomobject]@{ Status = if ($selectedComplete) { 'COMPLETE_TOP30' } else { 'PARTIAL_TOP30' }; Categories = $categories; ChartFileToken = $chartFileToken; MarketDate = $marketDate; PreviousMarketDate = if ($null -eq $PreviousSnapshot) { $null } else { [string]$PreviousSnapshot.market_date }; ComparableCategories = $comparableCategories; NoteworthyChanges = $noteworthy; Quality = $currentQuality; MarkdownPath = (Resolve-Path -LiteralPath $markdownPath).Path; HtmlPath = (Resolve-Path -LiteralPath $htmlPath).Path; Subject = $reportTitle }
}

Export-ModuleMember -Function New-BestSellersDailyReport, Format-BestSellersDiscountDisplay
