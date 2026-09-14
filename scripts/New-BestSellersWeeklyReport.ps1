param(
    [string]$SnapshotsRoot,
    [string]$ReportDate,
    [string]$EmailRecipient = '746254487@qq.com',
    [switch]$SkipEmail,
    [string]$RegistryPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) { $RegistryPath = Join-Path $projectRoot 'config\category-registry.json' }
Import-Module (Join-Path $projectRoot 'src\BestSellersCategoryRegistry.psm1') -Force
$registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
$registryCategories = @($registry.Categories | Where-Object Enabled)
$chinaTimeZone = [TimeZoneInfo]::FindSystemTimeZoneById('America/Los_Angeles')
$generatedAtBeijing = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $chinaTimeZone)
if ([string]::IsNullOrWhiteSpace($ReportDate)) { $ReportDate = $generatedAtBeijing.ToString('yyyy-MM-dd') }
if ($ReportDate -notmatch '^\d{4}-\d{2}-\d{2}$') { throw 'ReportDate must use YYYY-MM-DD.' }
if ([string]::IsNullOrWhiteSpace($SnapshotsRoot)) { $SnapshotsRoot = Join-Path $projectRoot 'var\amazon-bestsellers' }
if (-not (Test-Path -LiteralPath $SnapshotsRoot -PathType Container)) { throw "Snapshot root not found: $SnapshotsRoot" }

function Decode-WeeklyText { param([string]$Value) [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value)) }
$t = @{
    title = Decode-WeeklyText 'QW1hem9uIOe+juWbveermSBCZXN0IFNlbGxlcnMg5ZGo5oql772c5YyX5Lqs5pe26Ze0IA=='
    report_date = Decode-WeeklyText '5oql5ZGK5pel5pyf77ya'; coverage = Decode-WeeklyText '6KaG55uW54q25oCB77ya'; valid_days = Decode-WeeklyText '5a6M5pW0IFRvcCA1MCDmnInmlYjluILlnLrml6U='
    summary = Decode-WeeklyText '5pys5ZGo5pGY6KaB'; processed = Decode-WeeklyText '5bey5aSE55CG5b+r54Wn5pel77ya'; threshold = Decode-WeeklyText '5a6M5pW06KaG55uW6Zeo5qeb77ya5LiJ5Liq5qac5Y2V5ZCEIDgg5Liq5a6M5pW0IFRvcCA1MCDluILlnLrml6XjgII='
    changes = Decode-WeeklyText '5pys5ZGo5Y+Y5YyW6K6w5b2V'; change_rule = Decode-WeeklyText '5piO5pi+5Y+Y5YyW5Y+q5Zyo6L+e57ut5Lik5pel5Z2H5a6M5pW05pe25YiX5Ye644CC'; no_changes = Decode-WeeklyText '5b2T5YmN5peg5Y+v5q+U6L6D55qE5a6M5pW05qac5Y2V5Y+Y5YyW44CC'
    phase5 = Decode-WeeklyText 'UGhhc2UgNSDlkajluqbliIbmnpDnirbmgIE='; limited = Decode-WeeklyText '6aaW5qyh5pyJ6ZmQ5ZGo5bqm5YiG5p6Q77ya6KaG55uW5LiN6Laz77yM5omA5pyJ57uT6K665LuF5L2c5Z+657q/6K6w5b2V77yM5LiN5L2c6LaL5Yq/5oiW5Zug5p6c5Yik5pat44CC'; full = Decode-WeeklyText '5a6M5pW05ZGo5bqm5YiG5p6Q5bey5bCx57uq77yM5Y+v5Zyo5pys5ZGo5oql5Lit5ZGI546w6K+B5o2u6amx5Yqo57uT5p6c44CC'; collecting = Decode-WeeklyText '5LuN5Zyo56ev57Sv5Z+657q/77yb5pyq6L+Q6KGMIFBoYXNlIDUg5YiG5p6Q44CC'
    chart = Decode-WeeklyText '5qac5Y2V'; observed = Decode-WeeklyText '5bey6KeC5a+f5aSp5pWw'; complete = Decode-WeeklyText '5a6M5pW05pyJ5pWI5aSp5pWw'; remaining = Decode-WeeklyText '6L+Y6ZyA5a6M5pW05aSp5pWw'; status = Decode-WeeklyText '54q25oCB'
    incomplete_snapshots = Decode-WeeklyText '5a2Y5Zyo5LiN5a6M5pW05b+r54Wn'; collecting_status = Decode-WeeklyText '6YeH6ZuG5Lit'; ready_status = Decode-WeeklyText '5bey5bCx57uq'; baseline_status = Decode-WeeklyText '5Z+657q/56ev57Sv5Lit'; limited_status = Decode-WeeklyText '5Y+v6L+b6KGM5pyJ6ZmQ5ZGo5bqm5YiG5p6Q'; full_status = Decode-WeeklyText '5Y+v6L+b6KGM5a6M5pW05ZGo5bqm5YiG5p6Q'
    limits = Decode-WeeklyText '5pWw5o2u6IyD5Zu05LiO6ZmQ5Yi2'; limit_one = Decode-WeeklyText '5pys5ZGo5oql5LiN5Lya5oqK5LiN5a6M5pW05b+r54Wn5b2T5L2c5a6M5pW0IFRvcCA1MO+8jOS5n+S4jeaKiuS7t+agvOOAgeaYn+e6p+aIluivhOiuuuaVsOino+mHiuS4uuaOkuWQjeWboOaenOOAgg=='; limit_two = Decode-WeeklyText '5a6M5pW055qE5py65Lya44CB5biC5Zy657uT5p6E5LiO5YWz6IGU5YiG5p6Q5LuF5Zyo5ruh6Laz6KaG55uW6Zeo5qeb5ZCO5L2c5Li65ZGo5oql5YaF5a6544CC'; limit_short = Decode-WeeklyText '5LiN5a6M5pW05b+r54Wn5LiN5L2c5Li65a6M5pW0IFRvcCA1MCDmiJblm6Dmnpzkvp3mja7jgII='; purpose = Decode-WeeklyText '5ZGo5oql6IGM6LSj77ya6K6w5b2V6KaG55uW44CB5qac5Y2V5Y+Y5YyW5LiO5oyJ6Zeo5qeb5YWB6K6455qE5ZGo5bqm5YiG5p6Q44CC'
}
foreach ($textKey in @($t.Keys)) { $t[$textKey] = ([string]$t[$textKey]).Replace('Top 50', 'Top 30') }
foreach ($category in $registryCategories) { $t[$category.CategoryKey] = [string]$category.LabelZh }

$reportDirectory = Join-Path (Join-Path (Join-Path $projectRoot 'var\reports') 'weekly') $ReportDate
if (-not (Test-Path -LiteralPath $reportDirectory)) { New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null }
$files = @(Get-ChildItem -LiteralPath $SnapshotsRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and $_.Name -le $ReportDate } | Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'amazon-bestsellers.json' } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 7)
if ($files.Count -eq 0) { throw 'No Best Sellers daily snapshots were found.' }

$readiness = & (Join-Path $projectRoot 'scripts\Test-Phase5AnalysisReadiness.ps1') -SnapshotsRoot $SnapshotsRoot -AsOfDate $ReportDate -RegistryPath $RegistryPath | ConvertFrom-Json
$readinessStatusName = if ($readiness.status -eq 'READY_FOR_FULL_PHASE_5_ANALYSIS') { $t.full_status } elseif ($readiness.status -eq 'READY_FOR_LIMITED_WEEKLY_ANALYSIS') { $t.limited_status } else { $t.baseline_status }
$timestampToken = $generatedAtBeijing.ToString('yyyy-MM-dd_HHmm') + '_BJT'
$weeklyPath = Join-Path $reportDirectory ("Amazon_US_Weekly_Best_Sellers_Analysis_{0}.json" -f $timestampToken)
$weeklyRun = & (Join-Path $projectRoot 'scripts\New-BestSellersWeeklyAnalysis.ps1') -SnapshotsRoot $SnapshotsRoot -ReportDate $ReportDate -OutputPath $weeklyPath -RegistryPath $RegistryPath | ConvertFrom-Json
$phase5Artifacts = @()
if ($readiness.analysis_due) {
    $latestSnapshot = $files[0]
    $phase5Artifacts += (& (Join-Path $projectRoot 'scripts\New-BestSellersOpportunityAnalysis.ps1') -WeeklyAnalysisPath $weeklyRun.ArtifactPath | ConvertFrom-Json).ArtifactPath
    $phase5Artifacts += (& (Join-Path $projectRoot 'scripts\New-BestSellersMarketStructure.ps1') -SnapshotPath $latestSnapshot -RegistryPath $RegistryPath | ConvertFrom-Json).ArtifactPath
    $phase5Artifacts += (& (Join-Path $projectRoot 'scripts\New-BestSellersRankInfluence.ps1') -SnapshotPath $latestSnapshot -WeeklyAnalysisPath $weeklyRun.ArtifactPath -RegistryPath $RegistryPath | ConvertFrom-Json).ArtifactPath
}
$rankInfluencePaths = @($phase5Artifacts | Where-Object { (Split-Path -Leaf ([string]$_)) -eq 'best-sellers-rank-influence.json' })
if (-not (Test-Path -LiteralPath $weeklyRun.ArtifactPath -PathType Leaf)) { throw "Weekly analysis artifact not found: $($weeklyRun.ArtifactPath)" }
if ($rankInfluencePaths.Count -ne 1 -or -not (Test-Path -LiteralPath $rankInfluencePaths[0] -PathType Leaf)) { throw 'Exactly one rank-influence artifact is required for the weekly report.' }
$rankInfluencePath = [string]$rankInfluencePaths[0]
$weeklyAnalysis = Get-Content -LiteralPath $weeklyRun.ArtifactPath -Raw -Encoding UTF8 | ConvertFrom-Json
$rankInfluence = Get-Content -LiteralPath $rankInfluencePath -Raw -Encoding UTF8 | ConvertFrom-Json
Import-Module (Join-Path $projectRoot 'src\BestSellersWeeklyReportContent.psm1') -Force

# Send one independently named weekly PDF per monitored chart.
$timestamp = $generatedAtBeijing.ToString('yyyy-MM-dd HH:mm')
$splitResults = @()
Import-Module (Join-Path $projectRoot 'src\ReportArchive.psm1') -Force
foreach ($registryCategory in $registryCategories) {
    $categoryKey = [string]$registryCategory.CategoryKey
    $category = @($readiness.categories | Where-Object { [string]$_.category -eq $categoryKey } | Select-Object -First 1)[0]
    if ($null -eq $category) { throw "Readiness result did not include $categoryKey." }
    $categoryName = $t[$categoryKey]
    $statusName = if ($category.status -eq 'READY') { $t.ready_status } elseif ($category.status -eq 'INCOMPLETE_SNAPSHOTS_PRESENT') { $t.incomplete_snapshots } else { $t.collecting_status }
    $reportTitle = "$($t.title)$categoryName - $timestamp"
    $fileStem = "Amazon_US_Weekly_Best_Sellers_{0}_{1}_{2}" -f $registryCategory.ReportFileToken, $ReportDate, $timestampToken
    $markdownPath = Join-Path $reportDirectory ($fileStem + '.md')
    $htmlPath = Join-Path $reportDirectory ($fileStem + '.html')
    $sections = New-BestSellersWeeklyCategorySections -CategoryKey $categoryKey -WeeklyAnalysis $weeklyAnalysis -RankInfluence $rankInfluence -LimitedCoverage ($readiness.analysis_mode -eq 'LIMITED_WEEKLY')
    $md = New-Object Text.StringBuilder
    [void]$md.AppendLine("# $reportTitle"); [void]$md.AppendLine(); [void]$md.AppendLine("- $($t.report_date)$ReportDate"); [void]$md.AppendLine("- $($t.coverage)$readinessStatusName"); [void]$md.AppendLine("- $($t.purpose)"); [void]$md.AppendLine()
    [void]$md.AppendLine("## $($t.summary)"); [void]$md.AppendLine(); [void]$md.AppendLine("- $($t.processed)$($weeklyRun.SnapshotDayCount)"); [void]$md.AppendLine("- $($t.threshold)"); [void]$md.AppendLine()
    [void]$md.AppendLine("| $($t.chart) | $($t.observed) | $($t.complete) | $($t.remaining) | $($t.status) |"); [void]$md.AppendLine('|---|---:|---:|---:|---|'); [void]$md.AppendLine("| $categoryName | $($category.observed_market_day_count) | $($category.valid_market_day_count) | $($category.missing_valid_days) | $statusName |")
    [void]$md.AppendLine(); [void]$md.Append($sections.Markdown)
    [void]$md.AppendLine(); [void]$md.AppendLine("## $($t.limits)"); [void]$md.AppendLine(); [void]$md.AppendLine("- $($t.limit_one)"); [void]$md.AppendLine("- $($t.limit_two)")
    $html = "<!doctype html><html lang=`"zh-CN`"><head><meta charset=`"utf-8`"><style>body{font-family:Segoe UI,Microsoft YaHei,sans-serif;color:#1f2937;line-height:1.55;margin:32px}h1{font-size:22px}h2{font-size:17px;margin-top:28px}table{border-collapse:collapse;width:100%;font-size:11px;page-break-inside:auto}tr{page-break-inside:avoid}th,td{border:1px solid #d1d5db;padding:5px;text-align:left;vertical-align:top}th{background:#f3f4f6}.meta{background:#eff6ff;padding:12px;border-radius:6px}.warning{background:#fff7ed;border-left:4px solid #f97316;padding:10px}.note{color:#4b5563;font-size:12px}</style></head><body><h1>$reportTitle</h1><div class=`"meta`">$($t.report_date)$ReportDate<br>$($t.coverage)$readinessStatusName<br>$($t.purpose)</div><h2>$($t.summary)</h2><p>$($t.processed)$($weeklyRun.SnapshotDayCount)</p><table><thead><tr><th>$($t.chart)</th><th>$($t.observed)</th><th>$($t.complete)</th><th>$($t.remaining)</th><th>$($t.status)</th></tr></thead><tbody><tr><td>$categoryName</td><td>$($category.observed_market_day_count)</td><td>$($category.valid_market_day_count)</td><td>$($category.missing_valid_days)</td><td>$statusName</td></tr></tbody></table>$($sections.Html)<h2>$($t.limits)</h2><p>$($t.limit_one)</p><p class=`"note`">$($t.limit_two)</p></body></html>"
    [IO.File]::WriteAllText($markdownPath, $md.ToString(), (New-Object Text.UTF8Encoding($false))); [IO.File]::WriteAllText($htmlPath, $html, (New-Object Text.UTF8Encoding($false)))
    $pdfPath = Join-Path $reportDirectory ($fileStem + '.pdf')
    $pdf = & (Join-Path $projectRoot 'scripts\New-ReportPdf.ps1') -MarkdownPath $markdownPath -PdfPath $pdfPath -Title $reportTitle -GeneratedAtBeijing $timestamp | ConvertFrom-Json
    if ($pdf.Status -ne 'VERIFIED') { throw "Weekly PDF did not pass rendering verification for $categoryKey." }
    $archivedPdfPath = Copy-BestSellersReportToDesktop -PdfPath $pdf.PdfPath -ReportKind Weekly
    $splitResults += [pscustomobject]@{ Category = $categoryKey; MarkdownPath = $markdownPath; HtmlPath = $htmlPath; Pdf = $pdf; ArchivedPdfPath = $archivedPdfPath; Subject = $reportTitle }
}
Import-Module (Join-Path $projectRoot 'src\MailDelivery.psm1') -Force
foreach ($result in $splitResults) {
    if ($SkipEmail) {
        $chartDelivery = [pscustomobject]@{ Status = 'SKIPPED_BY_REQUEST'; Recipient = $EmailRecipient; SentAt = $null; ErrorMessage = $null }
    }
    else {
        $settings = Get-DailyReportMailSettings -Recipient $EmailRecipient
        $chartDelivery = Send-DailyReportEmail -Recipient $EmailRecipient -Subject $result.Subject -HtmlPath $result.HtmlPath -AttachmentPaths @($result.Pdf.PdfPath) -SmtpSettings $settings
    }
    $result | Add-Member -NotePropertyName EmailDelivery -NotePropertyValue $chartDelivery
}
$deliveryStatuses = @($splitResults | ForEach-Object { [string]$_.EmailDelivery.Status })
$overallDelivery = if ($SkipEmail) { [pscustomobject]@{ Status = 'SKIPPED_BY_REQUEST'; Recipient = $EmailRecipient; SentAt = $null; ErrorMessage = $null } } elseif (@($deliveryStatuses | Where-Object { $_ -ne 'SENT' }).Count -eq 0) { [pscustomobject]@{ Status = 'SENT'; Recipient = $EmailRecipient; SentAt = [DateTimeOffset]::Now; ErrorMessage = $null } } else { [pscustomobject]@{ Status = 'PARTIAL_FAILURE'; Recipient = $EmailRecipient; SentAt = $null; ErrorMessage = ('Per-chart delivery statuses: ' + ($deliveryStatuses -join ', ')) } }
$deliveryRecords = Write-MailDeliveryRunRecords -MarketDate $ReportDate -ReportKind Weekly -WorkRoot (Join-Path $projectRoot 'var') -RunId ([guid]::NewGuid().ToString('N')) -Messages @(
    $splitResults | ForEach-Object {
        [pscustomobject]@{ Category = [string]$_.Category; ReportPath = [string]$_.Pdf.PdfPath; DeliveryResult = $_.EmailDelivery }
    }
)
[pscustomobject]@{ ReportDate = $ReportDate; Readiness = $readiness; WeeklyAnalysis = $weeklyRun; Phase5Artifacts = $phase5Artifacts; Reports = $splitResults; EmailDelivery = $overallDelivery; EmailDeliveryManifestPath = $deliveryRecords.ManifestPath; EmailDeliveryRecordPaths = @($deliveryRecords.RecordPaths) } | ConvertTo-Json -Depth 12
return

$timestamp = $generatedAtBeijing.ToString('yyyy-MM-dd HH:mm')
$markdownPath = Join-Path $reportDirectory ("Amazon_US_Weekly_Best_Sellers_Report_{0}.md" -f $timestampToken)
$htmlPath = Join-Path $reportDirectory ("Amazon_US_Weekly_Best_Sellers_Report_{0}.html" -f $timestampToken)
$md = New-Object Text.StringBuilder
[void]$md.AppendLine("# $($t.title)$timestamp"); [void]$md.AppendLine(); [void]$md.AppendLine("- $($t.report_date)$ReportDate"); [void]$md.AppendLine("- $($t.coverage)$readinessStatusName"); [void]$md.AppendLine("- $($t.purpose)"); [void]$md.AppendLine()
[void]$md.AppendLine("## $($t.summary)"); [void]$md.AppendLine(); [void]$md.AppendLine("- $($t.processed)$($weeklyRun.SnapshotDayCount)"); [void]$md.AppendLine("- $($t.threshold)"); [void]$md.AppendLine()
[void]$md.AppendLine("| $($t.chart) | $($t.observed) | $($t.complete) | $($t.remaining) | $($t.status) |"); [void]$md.AppendLine('|---|---:|---:|---:|---|')
foreach ($category in @($readiness.categories)) { $categoryName = $t[[string]$category.category]; $statusName = if ($category.status -eq 'READY') { $t.ready_status } elseif ($category.status -eq 'INCOMPLETE_SNAPSHOTS_PRESENT') { $t.incomplete_snapshots } else { $t.collecting_status }; [void]$md.AppendLine("| $categoryName | $($category.observed_market_day_count) | $($category.valid_market_day_count) | $($category.missing_valid_days) | $statusName |") }
[void]$md.AppendLine(); [void]$md.AppendLine("## $($t.changes)"); [void]$md.AppendLine(); [void]$md.AppendLine("- $($t.change_rule)"); [void]$md.AppendLine("- $($t.no_changes)")
[void]$md.AppendLine(); [void]$md.AppendLine("## $($t.phase5)"); [void]$md.AppendLine(); if ($readiness.analysis_mode -eq 'FULL') { [void]$md.AppendLine("- $($t.full)") } elseif ($readiness.analysis_mode -eq 'LIMITED_WEEKLY') { [void]$md.AppendLine("- $($t.limited)") } else { [void]$md.AppendLine("- $($t.collecting)") }
if ($phase5Artifacts.Count -gt 0) { [void]$md.AppendLine("- Phase 5 artifacts generated: $($phase5Artifacts.Count)") }

$rows = New-Object Text.StringBuilder
foreach ($category in @($readiness.categories)) { $categoryName = $t[[string]$category.category]; $statusName = if ($category.status -eq 'READY') { $t.ready_status } elseif ($category.status -eq 'INCOMPLETE_SNAPSHOTS_PRESENT') { $t.incomplete_snapshots } else { $t.collecting_status }; [void]$rows.Append("<tr><td>$categoryName</td><td>$($category.observed_market_day_count)</td><td>$($category.valid_market_day_count)</td><td>$($category.missing_valid_days)</td><td>$statusName</td></tr>") }
$phaseText = if ($readiness.analysis_mode -eq 'FULL') { $t.full } elseif ($readiness.analysis_mode -eq 'LIMITED_WEEKLY') { $t.limited } else { $t.collecting }
$html = "<!doctype html><html lang=`"zh-CN`"><head><meta charset=`"utf-8`"><style>body{font-family:Segoe UI,Microsoft YaHei,sans-serif;color:#1f2937;line-height:1.55;margin:32px}h1{font-size:22px}h2{font-size:17px;margin-top:28px}table{border-collapse:collapse;width:100%;font-size:12px}th,td{border:1px solid #d1d5db;padding:6px;text-align:left;vertical-align:top}th{background:#f3f4f6}.meta{background:#eff6ff;padding:12px;border-radius:6px}.note{color:#4b5563;font-size:12px}</style></head><body><h1>$($t.title)$timestamp</h1><div class=`"meta`">$($t.report_date)$ReportDate<br>$($t.coverage)$readinessStatusName<br>$($t.purpose)</div><h2>$($t.summary)</h2><p>$($t.processed)$($weeklyRun.SnapshotDayCount)</p><table><thead><tr><th>$($t.chart)</th><th>$($t.observed)</th><th>$($t.complete)</th><th>$($t.remaining)</th><th>$($t.status)</th></tr></thead><tbody>$rows</tbody></table><h2>$($t.changes)</h2><p>$($t.change_rule)</p><p>$($t.no_changes)</p><h2>$($t.phase5)</h2><p>$phaseText</p><h2>$($t.limits)</h2><p>$($t.limit_one)</p><p class=`"note`">$($t.limit_two)</p></body></html>"
[IO.File]::WriteAllText($markdownPath, $md.ToString(), (New-Object Text.UTF8Encoding($false))); [IO.File]::WriteAllText($htmlPath, $html, (New-Object Text.UTF8Encoding($false)))
$subject = "$($t.title)$timestamp"
$pdfPath = Join-Path $reportDirectory (([IO.Path]::GetFileNameWithoutExtension($markdownPath)) + '.pdf')
$pdf = & (Join-Path $projectRoot 'scripts\New-ReportPdf.ps1') -MarkdownPath $markdownPath -PdfPath $pdfPath -Title $subject -GeneratedAtBeijing $timestamp | ConvertFrom-Json
if ($pdf.Status -ne 'VERIFIED') { throw 'Weekly PDF did not pass rendering verification.' }
Import-Module (Join-Path $projectRoot 'src\MailDelivery.psm1') -Force
$delivery = if ($SkipEmail) { [pscustomobject]@{ Status = 'SKIPPED_BY_REQUEST'; Recipient = $EmailRecipient; SentAt = $null; ErrorMessage = $null } } else { $settings = Get-DailyReportMailSettings -Recipient $EmailRecipient; Send-DailyReportEmail -Recipient $EmailRecipient -Subject $subject -HtmlPath $htmlPath -AttachmentPaths @($pdf.PdfPath) -SmtpSettings $settings }
$deliveryRecords = Write-MailDeliveryRunRecords -MarketDate $ReportDate -ReportKind Weekly -WorkRoot (Join-Path $projectRoot 'var') -RunId ([guid]::NewGuid().ToString('N')) -Messages @(
    [pscustomobject]@{ Category = 'general'; ReportPath = [string]$pdf.PdfPath; DeliveryResult = $delivery }
)
[pscustomobject]@{ ReportDate = $ReportDate; Readiness = $readiness; WeeklyAnalysis = $weeklyRun; Phase5Artifacts = $phase5Artifacts; MarkdownPath = $markdownPath; HtmlPath = $htmlPath; Pdf = $pdf; EmailDelivery = $delivery; EmailDeliveryManifestPath = $deliveryRecords.ManifestPath; EmailDeliveryRecordPaths = @($deliveryRecords.RecordPaths) } | ConvertTo-Json -Depth 12
