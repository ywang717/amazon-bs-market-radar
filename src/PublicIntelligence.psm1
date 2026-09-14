Set-StrictMode -Version Latest

function Get-PublicText {
    param($Items)
    return (@($Items | ForEach-Object {
        $property = $_.PSObject.Properties['Name']
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) { [string]$property.Value }
    }) -join '; ')
}

function Get-CpscRecallPublicIntelligence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$MarketDate,
        [Parameter(Mandatory = $true)][string]$WorkRoot,
        [int]$LookbackDays = 90,
        [string[]]$Keywords = @('pressure washer','power washer','sump pump','surface cleaner','foam cannon'),
        [scriptblock]$Transport
    )
    if ($MarketDate -notmatch '^\d{4}-\d{2}-\d{2}$') { throw 'MarketDate must use YYYY-MM-DD.' }
    if ($LookbackDays -lt 1 -or $LookbackDays -gt 3650) { throw 'LookbackDays must be between 1 and 3650.' }
    $marketDay = [DateTime]::ParseExact($MarketDate, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    $lookbackStart = $marketDay.AddDays(-$LookbackDays)
    $allRecords = New-Object System.Collections.Generic.List[object]
    $queryResults = New-Object System.Collections.Generic.List[object]

    foreach ($keyword in $Keywords) {
        $uri = 'https://www.saferproducts.gov/RestWebServices/Recall?ProductName={0}&format=json' -f [Uri]::EscapeDataString($keyword)
        try {
            if ($null -eq $Transport) { $response = Invoke-RestMethod -Method Get -Uri $uri -TimeoutSec 45 }
            else { $response = & $Transport $uri $keyword }
            $records = @($response | ForEach-Object { $_ })
            foreach ($record in $records) {
                if ($null -ne $record -and $null -ne $record.PSObject.Properties['RecallNumber']) { $allRecords.Add($record) }
            }
            $queryResults.Add([pscustomobject]@{ keyword = $keyword; status = 'SUCCEEDED'; record_count = $records.Count; error_message = $null })
            Remove-Variable response -ErrorAction SilentlyContinue
        }
        catch {
            $queryResults.Add([pscustomobject]@{ keyword = $keyword; status = 'FAILED'; record_count = 0; error_message = [string]$_.Exception.Message })
        }
    }

    $deduplicated = @($allRecords | Group-Object { [string]$_.RecallNumber } | ForEach-Object { $_.Group[0] })
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($record in $deduplicated) {
        $recallDate = [DateTime]::MinValue
        if (-not [DateTime]::TryParse([string]$record.RecallDate, [ref]$recallDate)) { continue }
        if ($recallDate.Date -lt $lookbackStart.Date -or $recallDate.Date -gt $marketDay.Date) { continue }
        $products = Get-PublicText $record.Products
        $manufacturers = Get-PublicText $record.Manufacturers
        $hazards = Get-PublicText $record.Hazards
        $remedies = Get-PublicText $record.Remedies
        $searchText = (([string]$record.Title) + ' ' + $products).ToLowerInvariant()
        $category = if ($searchText -match 'sump\s*pump') { 'sump-pump' }
            elseif ($searchText -match 'surface cleaner|foam cannon|spray gun|spray wand|hose|nozzle') { 'pressure-washer-accessories' }
            elseif ($searchText -match 'pressure\s*washer|power\s*washer') { 'pressure-washer' }
            else { 'related-public-safety' }
        $items.Add([pscustomobject]@{
            recall_number = [string]$record.RecallNumber
            recall_date = $recallDate.ToString('yyyy-MM-dd')
            last_publish_date = [string]$record.LastPublishDate
            category_slug = $category
            title = [string]$record.Title
            products = $products
            manufacturers = $manufacturers
            hazards = $hazards
            remedies = $remedies
            url = [string]$record.URL
            source = 'US_CPSC_RECALLS_API'
        })
    }
    foreach ($item in $items) {
        $canonical = $item | ConvertTo-Json -Compress -Depth 8
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical)))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
        $item | Add-Member -NotePropertyName content_hash -NotePropertyValue $hash
    }
    $sortedItems = @($items | Sort-Object recall_date, recall_number -Descending)
    $succeeded = @($queryResults | Where-Object { $_.status -eq 'SUCCEEDED' }).Count
    $status = if ($succeeded -eq $Keywords.Count) { 'SUCCEEDED' } elseif ($succeeded -gt 0) { 'PARTIAL' } else { 'FAILED' }
    $artifactDirectory = Join-Path (Join-Path (Join-Path $WorkRoot 'public-intelligence') $MarketDate) 'raw'
    if (-not (Test-Path -LiteralPath $artifactDirectory)) { New-Item -ItemType Directory -Path $artifactDirectory -Force | Out-Null }
    $artifactPath = Join-Path $artifactDirectory 'cpsc-recalls.json'
    $artifact = [ordered]@{
        schema_version = 'cpsc-public-recall-intelligence-v1'
        market_date = $MarketDate
        collected_at = [DateTimeOffset]::Now.ToString('o')
        source_url = 'https://www.saferproducts.gov/RestWebServices/Recall'
        source_authority = 'United States Consumer Product Safety Commission'
        status = $status
        lookback_days = $LookbackDays
        query_results = @($queryResults | ForEach-Object { $_ })
        items = $sortedItems
    }
    [System.IO.File]::WriteAllText($artifactPath, ($artifact | ConvertTo-Json -Depth 15), (New-Object System.Text.UTF8Encoding($false)))
    return [pscustomobject]@{
        Status = $status; MarketDate = $MarketDate; LookbackDays = $LookbackDays
        QueryCount = $Keywords.Count; SuccessfulQueryCount = $succeeded
        ItemCount = $sortedItems.Count; Items = $sortedItems
        ArtifactPath = (Resolve-Path -LiteralPath $artifactPath).Path
    }
}

function ConvertTo-PublicReportHtmlText {
    param($Value)
    if ($null -eq $Value) { return '' }
    return [Net.WebUtility]::HtmlEncode([string]$Value)
}

function ConvertTo-PublicReportMarkdownText {
    param($Value)
    if ($null -eq $Value) { return '' }
    return ([string]$Value).Replace('|','\|').Replace("`r",' ').Replace("`n",' ')
}

function New-CredentialFreeMarketReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$PublicIntelligence,
        [Parameter(Mandatory = $true)][string]$WorkRoot
    )
    $marketDate = [string]$PublicIntelligence.MarketDate
    $directory = Join-Path (Join-Path $WorkRoot 'reports') $marketDate
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $markdownPath = Join-Path $directory ("Amazon_US_Market_Report_{0}.md" -f $marketDate)
    $htmlPath = Join-Path $directory ("Amazon_US_Market_Report_{0}.html" -f $marketDate)
    $items = @($PublicIntelligence.Items)
    $generatedAt = [DateTimeOffset]::Now.ToString('yyyy-MM-dd HH:mm:ss zzz')

    $md = New-Object Text.StringBuilder
    [void]$md.AppendLine("# Amazon US Home Equipment Public Intelligence Report - $marketDate")
    [void]$md.AppendLine()
    [void]$md.AppendLine('## Executive Summary')
    [void]$md.AppendLine()
    [void]$md.AppendLine("- Mode: PUBLIC DATA ONLY (no Amazon Creators API credentials)")
    [void]$md.AppendLine("- Authoritative public safety records found in the last $($PublicIntelligence.LookbackDays) days: $($items.Count)")
    [void]$md.AppendLine("- CPSC collection status: $($PublicIntelligence.Status)")
    if ($null -ne $PublicIntelligence.PSObject.Properties['DatabaseStatus']) { [void]$md.AppendLine("- Historical database status: $($PublicIntelligence.DatabaseStatus)") }
    [void]$md.AppendLine("- Generated at: $generatedAt")
    [void]$md.AppendLine()
    [void]$md.AppendLine('## Data Availability and Limits')
    [void]$md.AppendLine()
    [void]$md.AppendLine('- Available: official US CPSC recall notices, product names, manufacturers, hazards, remedies, dates, and source URLs.')
    [void]$md.AppendLine('- Unavailable: Amazon ranking, price, coupon, rating, review count, seller, FBA status, sales, Best Sellers, Movers & Shakers, and Search Top 50.')
    [void]$md.AppendLine('- Not calculated: new-product detection, new-brand detection, rank trends, growth signals, and Opportunity Score.')
    [void]$md.AppendLine()
    [void]$md.AppendLine('## Recent Official Product Safety Intelligence')
    [void]$md.AppendLine()
    [void]$md.AppendLine('| Date | Category | Recall | Product / Manufacturer | Hazard | Official source |')
    [void]$md.AppendLine('|---|---|---|---|---|---|')
    foreach ($item in $items) {
        $productText = ((ConvertTo-PublicReportMarkdownText $item.products) + ' / ' + (ConvertTo-PublicReportMarkdownText $item.manufacturers)).Trim(' ','/')
        [void]$md.AppendLine("| $($item.recall_date) | $($item.category_slug) | $(ConvertTo-PublicReportMarkdownText $item.recall_number) | $productText | $(ConvertTo-PublicReportMarkdownText $item.hazards) | [CPSC]($($item.url)) |")
    }
    if ($items.Count -eq 0) { [void]$md.AppendLine('| - | - | No matching recall found in the lookback window | - | - | [CPSC API](https://www.cpsc.gov/Recalls/CPSC-Recalls-Application-Program-Interface-API-Information) |') }
    [void]$md.AppendLine()
    [void]$md.AppendLine('> This report contains public safety intelligence, not Amazon marketplace performance data. Absence of a recall is not evidence that a product is safe or commercially attractive.')

    $rows = New-Object Text.StringBuilder
    foreach ($item in $items) {
        $rowHtml = '<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}<br><small>{4}</small></td><td>{5}</td><td><a href="{6}">CPSC</a></td></tr>' -f `
            $item.recall_date, (ConvertTo-PublicReportHtmlText $item.category_slug), `
            (ConvertTo-PublicReportHtmlText $item.recall_number), (ConvertTo-PublicReportHtmlText $item.products), `
            (ConvertTo-PublicReportHtmlText $item.manufacturers), (ConvertTo-PublicReportHtmlText $item.hazards), `
            (ConvertTo-PublicReportHtmlText $item.url)
        [void]$rows.Append($rowHtml)
    }
    if ($items.Count -eq 0) { [void]$rows.Append('<tr><td colspan="6">No matching recall found in the lookback window.</td></tr>') }
    $html = @"
<!doctype html><html lang="en"><head><meta charset="utf-8"><style>body{font-family:Segoe UI,Arial,sans-serif;color:#1f2937;line-height:1.5}h1{font-size:22px}h2{font-size:17px}.notice{background:#fff7ed;border-left:4px solid #f97316;padding:12px}.meta{background:#eff6ff;padding:12px}table{border-collapse:collapse;width:100%;font-size:13px}th,td{border:1px solid #d1d5db;padding:6px;text-align:left;vertical-align:top}th{background:#f3f4f6}small{color:#6b7280}</style></head><body>
<h1>Amazon US Home Equipment Public Intelligence Report - $marketDate</h1><div class="notice"><strong>PUBLIC DATA ONLY</strong><br>No Amazon Creators API credentials are configured. This is not an Amazon ranking or sales report.</div>
<h2>Executive Summary</h2><div class="meta">CPSC status: $($PublicIntelligence.Status)<br>Lookback: $($PublicIntelligence.LookbackDays) days<br>Matching official safety records: $($items.Count)<br>Generated at: $generatedAt</div>
<h2>Data Availability and Limits</h2><ul><li>Available: official US CPSC recall and safety information.</li><li>Unavailable: Amazon rankings, price, reviews, seller, sales, Best Sellers, Movers & Shakers, and Search Top 50.</li><li>Not calculated: new products, new brands, ranking trends, growth signals, or Opportunity Score.</li></ul>
<h2>Recent Official Product Safety Intelligence</h2><table><thead><tr><th>Date</th><th>Category</th><th>Recall</th><th>Product / Manufacturer</th><th>Hazard</th><th>Source</th></tr></thead><tbody>$rows</tbody></table>
<p><small>This report contains public safety intelligence, not Amazon marketplace performance data. Absence of a recall is not evidence that a product is safe or commercially attractive.</small></p></body></html>
"@
    [IO.File]::WriteAllText($markdownPath, $md.ToString(), (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($htmlPath, $html, (New-Object Text.UTF8Encoding($false)))
    return [pscustomobject]@{
        Status = 'GENERATED'; MarketDate = $marketDate; Mode = 'PUBLIC_DATA_ONLY'; ItemCount = $items.Count
        Subject = "[PUBLIC DATA ONLY] Amazon US Home Equipment Report - $marketDate"
        MarkdownPath = (Resolve-Path -LiteralPath $markdownPath).Path
        HtmlPath = (Resolve-Path -LiteralPath $htmlPath).Path
    }
}

Export-ModuleMember -Function Get-CpscRecallPublicIntelligence, New-CredentialFreeMarketReport
