param(
    [Parameter(Mandatory = $true)][string]$MarketDate,
    [string]$WorkRoot,
    [string]$PostgresSettingsPath,
    [string]$EmailRecipient = '746254487@qq.com',
    [switch]$SkipEmail
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($WorkRoot)) { $WorkRoot = Join-Path $PSScriptRoot '..\var' }
if ([string]::IsNullOrWhiteSpace($PostgresSettingsPath)) { $PostgresSettingsPath = Join-Path $PSScriptRoot '..\.local\postgres-settings.json' }
if (-not (Test-Path -LiteralPath $PostgresSettingsPath)) { throw "PostgreSQL settings not found: $PostgresSettingsPath" }
$postgresSettings = Get-Content -LiteralPath $PostgresSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
Import-Module (Join-Path $PSScriptRoot '..\src\DailyReport.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\MailDelivery.psm1') -Force

$report = New-DailyMarketReport -MarketDate $MarketDate -WorkRoot $WorkRoot -PostgresSettings $postgresSettings
$delivery = if ($SkipEmail) {
    [pscustomobject]@{ Status = 'SKIPPED_BY_REQUEST'; Recipient = $EmailRecipient; SentAt = $null; ErrorMessage = $null }
} else {
    $settings = Get-DailyReportMailSettings -Recipient $EmailRecipient
    Send-DailyReportEmail -Recipient $EmailRecipient -Subject $report.Subject -HtmlPath $report.HtmlPath `
        -AttachmentPaths @($report.MarkdownPath) -SmtpSettings $settings
}
$deliveryRecords = Write-MailDeliveryRunRecords -MarketDate $MarketDate -ReportKind Daily -WorkRoot $WorkRoot -RunId ([guid]::NewGuid().ToString('N')) -Messages @(
    [pscustomobject]@{ Category = 'general'; ReportPath = [string]$report.MarkdownPath; DeliveryResult = $delivery }
)
[pscustomobject]@{ Report = $report; EmailDelivery = $delivery; EmailDeliveryManifestPath = $deliveryRecords.ManifestPath; EmailDeliveryRecordPaths = @($deliveryRecords.RecordPaths) } | ConvertTo-Json -Depth 8
