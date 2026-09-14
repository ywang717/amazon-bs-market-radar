param(
    [Parameter(Mandatory = $true)][string]$MarketDate,
    [string]$WorkRoot,
    [string]$PostgresSettingsPath,
    [string]$EmailRecipient = '746254487@qq.com',
    [string]$SubjectPrefix,
    [switch]$SkipEmail
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($WorkRoot)) { $WorkRoot = Join-Path $PSScriptRoot '..\var' }
if ([string]::IsNullOrWhiteSpace($PostgresSettingsPath)) { $PostgresSettingsPath = Join-Path $PSScriptRoot '..\.local\postgres-settings.json' }
Import-Module (Join-Path $PSScriptRoot '..\src\PublicIntelligence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\PublicIntelligencePostgres.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\MailDelivery.psm1') -Force

$publicData = Get-CpscRecallPublicIntelligence -MarketDate $MarketDate -WorkRoot $WorkRoot
$databaseImport = [pscustomobject]@{ Status = 'SKIPPED_SETTINGS_MISSING'; ErrorMessage = $null }
if (Test-Path -LiteralPath $PostgresSettingsPath) {
    try {
        $postgresSettings = Get-Content -LiteralPath $PostgresSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Invoke-PublicIntelligencePostgresImport -ArtifactPath $publicData.ArtifactPath -PostgresSettings $postgresSettings
        $databaseImport = [pscustomobject]@{ Status = 'IMPORTED'; ErrorMessage = $null }
    }
    catch {
        $safeError = [string]$_.Exception.Message
        if ($null -ne $postgresSettings -and -not [string]::IsNullOrWhiteSpace([string]$postgresSettings.password)) { $safeError = $safeError.Replace([string]$postgresSettings.password, '[REDACTED]') }
        $databaseImport = [pscustomobject]@{ Status = 'IMPORT_FAILED_RETRYABLE'; ErrorMessage = $safeError }
    }
}
$publicData | Add-Member -NotePropertyName DatabaseStatus -NotePropertyValue $databaseImport.Status
$report = New-CredentialFreeMarketReport -PublicIntelligence $publicData -WorkRoot $WorkRoot
$delivery = if ($SkipEmail) {
    [pscustomobject]@{ Status = 'SKIPPED_BY_REQUEST'; Recipient = $EmailRecipient; SentAt = $null; ErrorMessage = $null }
} else {
    $mailSettings = Get-DailyReportMailSettings -Recipient $EmailRecipient
    $emailSubject = if ([string]::IsNullOrWhiteSpace($SubjectPrefix)) { $report.Subject } else { "$SubjectPrefix $($report.Subject)" }
    Send-DailyReportEmail -Recipient $EmailRecipient -Subject $emailSubject -HtmlPath $report.HtmlPath `
        -AttachmentPaths @($report.MarkdownPath) -SmtpSettings $mailSettings
}
$deliveryRecords = Write-MailDeliveryRunRecords -MarketDate $MarketDate -ReportKind Daily -WorkRoot $WorkRoot -RunId ([guid]::NewGuid().ToString('N')) -Messages @(
    [pscustomobject]@{ Category = 'general'; ReportPath = [string]$report.MarkdownPath; DeliveryResult = $delivery }
)
[pscustomobject]@{
    Mode = 'PUBLIC_DATA_ONLY'; PublicIntelligence = $publicData; DatabaseImport = $databaseImport; Report = $report
    EmailDelivery = $delivery; EmailDeliveryManifestPath = $deliveryRecords.ManifestPath; EmailDeliveryRecordPaths = @($deliveryRecords.RecordPaths)
} | ConvertTo-Json -Depth 10
