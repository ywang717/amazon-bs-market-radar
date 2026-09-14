param(
    [Parameter(Mandatory = $true)][string]$MarketDate,
    [string]$ConfigPath,
    [string]$WorkRoot,
    [string]$PostgresSettingsPath,
    [string]$EmailRecipient = '746254487@qq.com',
    [switch]$SkipEmail
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $PSScriptRoot '..\config\sources.json' }
if ([string]::IsNullOrWhiteSpace($WorkRoot)) { $WorkRoot = Join-Path $PSScriptRoot '..\var' }
if ([string]::IsNullOrWhiteSpace($PostgresSettingsPath)) { $PostgresSettingsPath = Join-Path $PSScriptRoot '..\.local\postgres-settings.json' }

Import-Module (Join-Path $PSScriptRoot '..\src\AmazonIntelligence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\CreatorsApiAdapter.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\DailyCollection.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\PostgresOutbox.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\DailyDatabasePipeline.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\DailyReport.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\MailDelivery.psm1') -Force

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Source config not found: $ConfigPath" }
if (-not (Test-Path -LiteralPath $PostgresSettingsPath)) { throw "PostgreSQL settings not found: $PostgresSettingsPath" }
$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$postgresSettings = Get-Content -LiteralPath $PostgresSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json

$pipeline = Invoke-DailyCollectionDatabasePipeline -Config $config -MarketDate $MarketDate -WorkRoot $WorkRoot -PostgresSettings $postgresSettings
$report = New-DailyMarketReport -MarketDate $MarketDate -WorkRoot $WorkRoot -PostgresSettings $postgresSettings -PipelineResult $pipeline
$delivery = if ($SkipEmail) {
    [pscustomobject]@{ Status = 'SKIPPED_BY_REQUEST'; Recipient = $EmailRecipient; SentAt = $null; ErrorMessage = $null }
} else {
    $mailSettings = Get-DailyReportMailSettings -Recipient $EmailRecipient
    Send-DailyReportEmail -Recipient $EmailRecipient -Subject $report.Subject -HtmlPath $report.HtmlPath `
        -AttachmentPaths @($report.MarkdownPath) -SmtpSettings $mailSettings
}
$deliveryRecords = Write-MailDeliveryRunRecords -MarketDate $MarketDate -ReportKind Daily -WorkRoot $WorkRoot -RunId ([guid]::NewGuid().ToString('N')) -Messages @(
    [pscustomobject]@{ Category = 'general'; ReportPath = [string]$report.MarkdownPath; DeliveryResult = $delivery }
)

[pscustomobject]@{
    Pipeline = $pipeline; Report = $report; EmailDelivery = $delivery
    EmailDeliveryManifestPath = $deliveryRecords.ManifestPath; EmailDeliveryRecordPaths = @($deliveryRecords.RecordPaths)
} | ConvertTo-Json -Depth 12
