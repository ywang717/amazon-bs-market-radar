param(
    [Parameter(Mandatory = $true)][string]$CurrentPath,
    [string]$PreviousPath,
    [string]$OutputDirectory,
    [string]$EmailRecipient = '746254487@qq.com',
    [switch]$SkipEmail,
    [string]$RegistryPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) { $RegistryPath = Join-Path $projectRoot 'config\category-registry.json' }
$pacificTimeZone = [TimeZoneInfo]::FindSystemTimeZoneById('America/Los_Angeles')
$generatedAtBeijing = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $pacificTimeZone)
Import-Module (Join-Path $projectRoot 'src\BestSellersAnalysis.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersDailyReport.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\MailDelivery.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\ReportArchive.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersCategoryRegistry.psm1') -Force

$registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
$current = Read-BestSellersSnapshot -Path $CurrentPath -RegistryPath $RegistryPath
$previous = if ([string]::IsNullOrWhiteSpace($PreviousPath)) { $null } else { Read-BestSellersSnapshot -Path $PreviousPath -RegistryPath $RegistryPath }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path (Join-Path $projectRoot 'var\reports') ([string]$current.market_date) }
$categoryKeys = @(Get-BestSellersCategoryKeys -Registry $registry -EnabledOnly)
$results = @()
foreach ($categoryKey in $categoryKeys) {
    $report = New-BestSellersDailyReport -CurrentSnapshot $current -PreviousSnapshot $previous -OutputDirectory $OutputDirectory -GeneratedAtBeijing $generatedAtBeijing -CategoryKeys $categoryKey -RegistryPath $RegistryPath
    $pdfPath = Join-Path $OutputDirectory (([IO.Path]::GetFileNameWithoutExtension($report.MarkdownPath)) + '.pdf')
    $pdf = & (Join-Path $projectRoot 'scripts\New-ReportPdf.ps1') -MarkdownPath $report.MarkdownPath -PdfPath $pdfPath `
        -Title $report.Subject -GeneratedAtBeijing $generatedAtBeijing.ToString('yyyy-MM-dd HH:mm') | ConvertFrom-Json
    if ($pdf.Status -ne 'VERIFIED') { throw "Best Sellers daily report PDF did not pass rendering verification for $categoryKey." }
    $archivedPdfPath = Copy-BestSellersReportToDesktop -PdfPath $pdf.PdfPath -ReportKind Daily -CategoryKey $categoryKey -RegistryPath $RegistryPath
    $delivery = if ($SkipEmail) {
        [pscustomobject]@{ Status = 'SKIPPED_BY_REQUEST'; Recipient = $EmailRecipient; SentAt = $null; ErrorMessage = $null }
    } else {
        $settings = Get-DailyReportMailSettings -Recipient $EmailRecipient
        Send-DailyReportEmail -Recipient $EmailRecipient -Subject $report.Subject -HtmlPath $report.HtmlPath -AttachmentPaths @($pdf.PdfPath) -SmtpSettings $settings
    }
    $results += [pscustomobject]@{ Category = $categoryKey; Report = $report; Pdf = $pdf; ArchivedPdfPath = $archivedPdfPath; EmailDelivery = $delivery }
}
$deliveryStatuses = @($results | ForEach-Object { [string]$_.EmailDelivery.Status })
$overallDelivery = if ($SkipEmail) {
    [pscustomobject]@{ Status = 'SKIPPED_BY_REQUEST'; Recipient = $EmailRecipient; SentAt = $null; ErrorMessage = $null }
} elseif (@($deliveryStatuses | Where-Object { $_ -ne 'SENT' }).Count -eq 0) {
    [pscustomobject]@{ Status = 'SENT'; Recipient = $EmailRecipient; SentAt = [DateTimeOffset]::Now; ErrorMessage = $null }
} else {
    [pscustomobject]@{ Status = 'PARTIAL_FAILURE'; Recipient = $EmailRecipient; SentAt = $null; ErrorMessage = ('Per-chart delivery statuses: ' + ($deliveryStatuses -join ', ')) }
}
$deliveryRecords = Write-MailDeliveryRunRecords -MarketDate ([string]$current.market_date) -ReportKind Daily -WorkRoot (Join-Path $projectRoot 'var') -RunId ([guid]::NewGuid().ToString('N')) -Messages @(
    $results | ForEach-Object {
        [pscustomobject]@{ Category = [string]$_.Category; ReportPath = [string]$_.Pdf.PdfPath; DeliveryResult = $_.EmailDelivery }
    }
)
[pscustomobject]@{ Reports = $results; EmailDelivery = $overallDelivery; EmailDeliveryManifestPath = $deliveryRecords.ManifestPath; EmailDeliveryRecordPaths = @($deliveryRecords.RecordPaths) } | ConvertTo-Json -Depth 10
