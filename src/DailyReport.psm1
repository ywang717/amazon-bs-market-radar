Set-StrictMode -Version Latest

function ConvertTo-ReportHtmlText {
    param($Value)
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function ConvertTo-ReportMarkdownText {
    param($Value)
    if ($null -eq $Value) { return '' }
    return ([string]$Value).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
}

function Invoke-DefaultDailyReportDataProvider {
    param([string]$MarketDate, $PostgresSettings)
    if ($MarketDate -notmatch '^\d{4}-\d{2}-\d{2}$') { throw 'MarketDate must use YYYY-MM-DD.' }
    $psql = Join-Path $PostgresSettings.install_root 'bin\psql.exe'
    if (-not (Test-Path -LiteralPath $psql)) { throw "psql not found: $psql" }

    $savedPassword = [Environment]::GetEnvironmentVariable('PGPASSWORD', 'Process')
    try {
        $env:PGPASSWORD = [string]$PostgresSettings.password
        $arguments = @(
            '-h', [string]$PostgresSettings.host, '-p', [string]$PostgresSettings.port,
            '-U', [string]$PostgresSettings.username, '-d', [string]$PostgresSettings.database,
            '-X', '--no-psqlrc', '-q', '-v', 'ON_ERROR_STOP=1', '-tA', '-c'
        )
        $sql = @"
SET search_path TO amazon_intelligence, public;
SELECT json_build_object(
  'rankings', COALESCE((SELECT json_agg(r ORDER BY r.category_level_1, r.category_level_2, r.rank)
    FROM (SELECT category_level_1, category_level_2, accessory_type, rank, previous_rank, rank_change,
                 brand, model, asin, title, url, price, coupon, rating, review_count, seller,
                 fba_status, first_available_date, source_type, search_term
          FROM daily_ranking WHERE date = DATE '$MarketDate') r), '[]'::json),
  'runs', COALESCE((SELECT json_agg(x ORDER BY x.display_name)
    FROM (SELECT c.name || ' / ' || COALESCE(sd.search_term, sd.source_type::text) AS display_name,
                 cr.status::text, cr.expected_count, cr.raw_count,
                 cr.accepted_count, cr.rejected_count,
                 CASE WHEN cr.expected_count = 0 THEN 0
                      ELSE round(cr.accepted_count * 100.0 / cr.expected_count, 2) END AS completeness_percent,
                 cr.error_summary
          FROM collection_run cr JOIN source_definition sd ON sd.source_id = cr.source_id
          JOIN category c ON c.category_id = sd.category_id
          WHERE (cr.started_at AT TIME ZONE 'America/Los_Angeles')::date = DATE '$MarketDate') x), '[]'::json),
  'signals', COALESCE((SELECT json_agg(s ORDER BY s.signal_type)
    FROM (SELECT signal_type::text, count(*) AS signal_count
          FROM detection_signal WHERE market_date = DATE '$MarketDate' GROUP BY signal_type) s), '[]'::json)
);
"@
        $raw = & $psql @arguments $sql
        if ($LASTEXITCODE -ne 0) { throw "Daily report query failed with exit code $LASTEXITCODE." }
        $json = (@($raw) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ''
        if ([string]::IsNullOrWhiteSpace($json)) { throw 'Daily report query returned no JSON.' }
        return $json | ConvertFrom-Json
    }
    finally {
        if ($null -eq $savedPassword) { Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable('PGPASSWORD', $savedPassword, 'Process') }
    }
}

function New-DailyMarketReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$MarketDate,
        [Parameter(Mandatory = $true)][string]$WorkRoot,
        [Parameter(Mandatory = $true)]$PostgresSettings,
        $PipelineResult,
        [scriptblock]$DataProvider
    )
    if ($MarketDate -notmatch '^\d{4}-\d{2}-\d{2}$') { throw 'MarketDate must use YYYY-MM-DD.' }
    if ($null -eq $DataProvider) { $data = Invoke-DefaultDailyReportDataProvider -MarketDate $MarketDate -PostgresSettings $PostgresSettings }
    else { $data = & $DataProvider $MarketDate $PostgresSettings }

    $rankings = @($data.rankings)
    $runs = @($data.runs)
    $signals = @($data.signals)
    $pipelineStatus = if ($null -ne $PipelineResult) { [string]$PipelineResult.Status } else { 'REPORT_ONLY' }
    $generatedAt = [DateTimeOffset]::Now.ToString('yyyy-MM-dd HH:mm:ss zzz')
    $reportDirectory = Join-Path (Join-Path $WorkRoot 'reports') $MarketDate
    if (-not (Test-Path -LiteralPath $reportDirectory)) { New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null }
    $markdownPath = Join-Path $reportDirectory 'amazon-us-home-equipment-daily-report.md'
    $htmlPath = Join-Path $reportDirectory 'amazon-us-home-equipment-daily-report.html'

    $md = New-Object System.Text.StringBuilder
    [void]$md.AppendLine("# Amazon US Home Equipment Daily Report - $MarketDate")
    [void]$md.AppendLine()
    [void]$md.AppendLine("- Generated at: $generatedAt")
    [void]$md.AppendLine("- Pipeline status: $pipelineStatus")
    [void]$md.AppendLine("- Ranking records: $($rankings.Count)")
    [void]$md.AppendLine()
    [void]$md.AppendLine('## Data quality')
    [void]$md.AppendLine()
    [void]$md.AppendLine('| Source | Status | Expected | Raw | Accepted | Rejected | Completeness |')
    [void]$md.AppendLine('|---|---:|---:|---:|---:|---:|---:|')
    foreach ($run in $runs) {
        [void]$md.AppendLine("| $(ConvertTo-ReportMarkdownText $run.display_name) | $($run.status) | $($run.expected_count) | $($run.raw_count) | $($run.accepted_count) | $($run.rejected_count) | $($run.completeness_percent)% |")
    }
    if ($runs.Count -eq 0) { [void]$md.AppendLine('| No collection run for the market date | - | 0 | 0 | 0 | 0 | 0% |') }
    [void]$md.AppendLine()
    [void]$md.AppendLine('## Ranking details')
    [void]$md.AppendLine()
    [void]$md.AppendLine('| Category | Rank | ASIN | Brand | Title | Price | Rating | Reviews |')
    [void]$md.AppendLine('|---|---:|---|---|---|---:|---:|---:|')
    foreach ($row in $rankings) {
        $category = if ([string]::IsNullOrWhiteSpace([string]$row.category_level_2)) { $row.category_level_1 } else { $row.category_level_2 }
        [void]$md.AppendLine("| $(ConvertTo-ReportMarkdownText $category) | $($row.rank) | $($row.asin) | $(ConvertTo-ReportMarkdownText $row.brand) | $(ConvertTo-ReportMarkdownText $row.title) | $($row.price) | $($row.rating) | $($row.review_count) |")
    }
    if ($rankings.Count -eq 0) { [void]$md.AppendLine('| No qualified ranking data for the market date | - | - | - | - | - | - | - |') }
    [void]$md.AppendLine()
    [void]$md.AppendLine('## Change signals')
    [void]$md.AppendLine()
    foreach ($signal in $signals) { [void]$md.AppendLine("- $($signal.signal_type): $($signal.signal_count)") }
    if ($signals.Count -eq 0) { [void]$md.AppendLine('- No change signals yet; continuous historical data is required.') }
    [void]$md.AppendLine()
    [void]$md.AppendLine('> Data comes from approved Amazon Creators API SearchItems results. It is not a Best Sellers or Movers & Shakers chart. Missing fields remain null and are not inferred.')

    $htmlRows = New-Object System.Text.StringBuilder
    foreach ($row in $rankings) {
        $category = if ([string]::IsNullOrWhiteSpace([string]$row.category_level_2)) { $row.category_level_1 } else { $row.category_level_2 }
        [void]$htmlRows.Append("<tr><td>$(ConvertTo-ReportHtmlText $category)</td><td>$($row.rank)</td><td>$(ConvertTo-ReportHtmlText $row.asin)</td><td>$(ConvertTo-ReportHtmlText $row.brand)</td><td>$(ConvertTo-ReportHtmlText $row.title)</td><td>$(ConvertTo-ReportHtmlText $row.price)</td><td>$(ConvertTo-ReportHtmlText $row.rating)</td><td>$(ConvertTo-ReportHtmlText $row.review_count)</td></tr>")
    }
    if ($rankings.Count -eq 0) { [void]$htmlRows.Append('<tr><td colspan="8">No qualified ranking data for the market date</td></tr>') }
    $qualityRows = New-Object System.Text.StringBuilder
    foreach ($run in $runs) {
        [void]$qualityRows.Append("<tr><td>$(ConvertTo-ReportHtmlText $run.display_name)</td><td>$(ConvertTo-ReportHtmlText $run.status)</td><td>$($run.expected_count)</td><td>$($run.accepted_count)</td><td>$($run.rejected_count)</td><td>$($run.completeness_percent)%</td></tr>")
    }
    if ($runs.Count -eq 0) { [void]$qualityRows.Append('<tr><td colspan="6">No collection run for the market date</td></tr>') }
    $signalItems = if ($signals.Count -eq 0) { '<li>No change signals yet; continuous historical data is required.</li>' } else { (@($signals | ForEach-Object { "<li>$(ConvertTo-ReportHtmlText $_.signal_type): $($_.signal_count)</li>" }) -join '') }
    $html = @"
<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><style>
body{font-family:Segoe UI,Microsoft YaHei,sans-serif;color:#1f2937;line-height:1.5}h1{font-size:22px}h2{font-size:17px;margin-top:24px}table{border-collapse:collapse;width:100%;font-size:13px}th,td{border:1px solid #d1d5db;padding:6px;text-align:left}th{background:#f3f4f6}.meta{background:#eff6ff;padding:12px}.note{color:#4b5563;font-size:12px}
</style></head><body><h1>Amazon US Home Equipment Daily Report - $MarketDate</h1>
<div class="meta">Generated at: $generatedAt<br>Pipeline status: $(ConvertTo-ReportHtmlText $pipelineStatus)<br>Ranking records: $($rankings.Count)</div>
<h2>Data quality</h2><table><thead><tr><th>Source</th><th>Status</th><th>Expected</th><th>Accepted</th><th>Rejected</th><th>Completeness</th></tr></thead><tbody>$qualityRows</tbody></table>
<h2>Ranking details</h2><table><thead><tr><th>Category</th><th>Rank</th><th>ASIN</th><th>Brand</th><th>Title</th><th>Price</th><th>Rating</th><th>Reviews</th></tr></thead><tbody>$htmlRows</tbody></table>
<h2>Change signals</h2><ul>$signalItems</ul><p class="note">Data comes from approved Amazon Creators API SearchItems results. It is not a Best Sellers or Movers & Shakers chart. Missing fields remain null and are not inferred.</p>
</body></html>
"@
    [System.IO.File]::WriteAllText($markdownPath, $md.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText($htmlPath, $html, (New-Object System.Text.UTF8Encoding($false)))
    return [pscustomobject]@{
        MarketDate = $MarketDate; Status = 'GENERATED'; PipelineStatus = $pipelineStatus
        RankingCount = $rankings.Count; RunCount = $runs.Count; SignalTypeCount = $signals.Count
        Subject = "Amazon US Home Equipment Daily Report - $MarketDate"
        MarkdownPath = (Resolve-Path -LiteralPath $markdownPath).Path
        HtmlPath = (Resolve-Path -LiteralPath $htmlPath).Path
    }
}

Export-ModuleMember -Function New-DailyMarketReport
