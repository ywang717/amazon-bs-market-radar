Set-StrictMode -Version Latest

function Protect-MailErrorMessage {
    param([string]$Message, [string]$Secret)
    $safe = [regex]::Replace([string]$Message, '(?i)Bearer\s+[A-Za-z0-9._|+\-/=]+', 'Bearer [REDACTED]')
    if (-not [string]::IsNullOrWhiteSpace($Secret)) { $safe = $safe.Replace($Secret, '[REDACTED]') }
    return $safe
}

function Get-DailyReportMailSettings {
    param([string]$Recipient = '746254487@qq.com')
    $username = [Environment]::GetEnvironmentVariable('DAILY_REPORT_SMTP_USERNAME', 'Process')
    if ([string]::IsNullOrWhiteSpace($username)) { $username = [Environment]::GetEnvironmentVariable('DAILY_REPORT_SMTP_USERNAME', 'User') }
    if ([string]::IsNullOrWhiteSpace($username)) { $username = $Recipient }
    $hostName = [Environment]::GetEnvironmentVariable('DAILY_REPORT_SMTP_HOST', 'Process')
    if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = [Environment]::GetEnvironmentVariable('DAILY_REPORT_SMTP_HOST', 'User') }
    if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = 'smtp.qq.com' }
    $portText = [Environment]::GetEnvironmentVariable('DAILY_REPORT_SMTP_PORT', 'Process')
    if ([string]::IsNullOrWhiteSpace($portText)) { $portText = [Environment]::GetEnvironmentVariable('DAILY_REPORT_SMTP_PORT', 'User') }
    $port = if ([string]::IsNullOrWhiteSpace($portText)) { 587 } else { [int]$portText }
    $authCode = [Environment]::GetEnvironmentVariable('DAILY_REPORT_SMTP_AUTH_CODE', 'Process')
    if ([string]::IsNullOrWhiteSpace($authCode)) { $authCode = [Environment]::GetEnvironmentVariable('DAILY_REPORT_SMTP_AUTH_CODE', 'User') }
    return [pscustomobject]@{
        host = $hostName; port = $port; enable_ssl = $true; username = $username
        password = $authCode
        sender = $username
    }
}

function Send-DailyReportEmail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Recipient,
        [Parameter(Mandatory = $true)][string]$Subject,
        [Parameter(Mandatory = $true)][string]$HtmlPath,
        [Parameter(Mandatory = $true)]$SmtpSettings,
        [string[]]$AttachmentPaths = @(),
        [scriptblock]$MailTransport
    )
    if ($Recipient -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { throw 'Recipient email address is invalid.' }
    if (-not (Test-Path -LiteralPath $HtmlPath)) { throw "HTML report not found: $HtmlPath" }
    if ([string]::IsNullOrWhiteSpace([string]$SmtpSettings.username) -or [string]::IsNullOrWhiteSpace([string]$SmtpSettings.password)) {
        return [pscustomobject]@{ Status = 'SKIPPED_CREDENTIALS_MISSING'; Recipient = $Recipient; SentAt = $null; ErrorMessage = $null }
    }
    foreach ($path in $AttachmentPaths) { if (-not (Test-Path -LiteralPath $path)) { throw "Attachment not found: $path" } }

    $mail = $null
    $client = $null
    try {
        $htmlBody = Get-Content -LiteralPath $HtmlPath -Raw -Encoding UTF8
        if ($null -ne $MailTransport) {
            & $MailTransport $Recipient $Subject $htmlBody $AttachmentPaths $SmtpSettings
        }
        else {
            $mail = New-Object System.Net.Mail.MailMessage
            $mail.From = New-Object System.Net.Mail.MailAddress([string]$SmtpSettings.sender)
            [void]$mail.To.Add($Recipient)
            $mail.Subject = $Subject
            $mail.SubjectEncoding = [System.Text.Encoding]::UTF8
            $mail.Body = $htmlBody
            $mail.BodyEncoding = [System.Text.Encoding]::UTF8
            $mail.IsBodyHtml = $true
            foreach ($path in $AttachmentPaths) { [void]$mail.Attachments.Add((New-Object System.Net.Mail.Attachment($path))) }
            $client = New-Object System.Net.Mail.SmtpClient([string]$SmtpSettings.host, [int]$SmtpSettings.port)
            $client.EnableSsl = [bool]$SmtpSettings.enable_ssl
            $client.UseDefaultCredentials = $false
            $client.Credentials = New-Object System.Net.NetworkCredential([string]$SmtpSettings.username, [string]$SmtpSettings.password)
            $client.Timeout = 30000
            $client.Send($mail)
        }
        return [pscustomobject]@{ Status = 'SENT'; Recipient = $Recipient; SentAt = [DateTimeOffset]::Now.ToString('o'); ErrorMessage = $null }
    }
    catch {
        return [pscustomobject]@{
            Status = 'SEND_FAILED_RETRYABLE'; Recipient = $Recipient; SentAt = $null
            ErrorMessage = Protect-MailErrorMessage -Message $_.Exception.Message -Secret ([string]$SmtpSettings.password)
        }
    }
    finally {
        if ($null -ne $mail) { $mail.Dispose() }
        if ($null -ne $client) { $client.Dispose() }
    }
}

function Write-MailDeliverySummary {
    param(
        [Parameter(Mandatory = $true)]$DeliveryResult,
        [Parameter(Mandatory = $true)][string]$MarketDate,
        [Parameter(Mandatory = $true)][string]$ReportPath,
        [Parameter(Mandatory = $true)][string]$WorkRoot
    )
    $directory = Join-Path (Join-Path $WorkRoot 'reports') $MarketDate
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $path = Join-Path $directory 'email-delivery-summary.json'
    $value = [ordered]@{
        schema_version = 'daily-email-delivery-summary-v1'
        market_date = $MarketDate
        status = [string]$DeliveryResult.Status
        recipient = [string]$DeliveryResult.Recipient
        sent_at = $DeliveryResult.SentAt
        report_path = $ReportPath
        error_message = $DeliveryResult.ErrorMessage
    }
    $temporary = $path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    [System.IO.File]::WriteAllText($temporary, ($value | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $path -Force
    return (Resolve-Path -LiteralPath $path).Path
}

function Get-MailDeliveryRecordRoot {
    param(
        [Parameter(Mandatory = $true)][string]$WorkRoot,
        [Parameter(Mandatory = $true)][string]$MarketDate,
        [Parameter(Mandatory = $true)][ValidateSet('Daily', 'Weekly')][string]$ReportKind,
        [Parameter(Mandatory = $true)][string]$RunId
    )
    return (Join-Path (Join-Path (Join-Path (Join-Path $WorkRoot 'reports') $MarketDate) 'delivery') (Join-Path $ReportKind $RunId))
}

function Write-MailDeliveryJsonAtomically {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-MailDeliverySha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-MailDeliveryRunRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$MarketDate,
        [Parameter(Mandatory = $true)][ValidateSet('Daily', 'Weekly')][string]$ReportKind,
        [Parameter(Mandatory = $true)][object[]]$Messages,
        [Parameter(Mandatory = $true)][string]$WorkRoot,
        [Parameter(Mandatory = $true)][string]$RunId
    )
    $parsedDate = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($MarketDate, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsedDate)) {
        throw 'MarketDate must use yyyy-MM-dd format.'
    }
    if ([string]::IsNullOrWhiteSpace($RunId) -or $RunId -match '[\\/:*?"<>|]') { throw 'RunId must be nonempty and path-safe.' }
    if (@($Messages).Count -eq 0) { throw 'Messages must contain at least one delivery result.' }

    $recordRoot = Get-MailDeliveryRecordRoot -WorkRoot $WorkRoot -MarketDate $MarketDate -ReportKind $ReportKind -RunId $RunId
    if (-not (Test-Path -LiteralPath $recordRoot)) { New-Item -ItemType Directory -Path $recordRoot -Force | Out-Null }
    $records = @()
    $categories = @{}
    foreach ($message in @($Messages)) {
        $category = [string]$message.Category
        if ([string]::IsNullOrWhiteSpace($category) -or $categories.ContainsKey($category)) { throw 'Messages must have unique, nonempty categories.' }
        if ($category -match '[\\/:*?"<>|]') { throw 'Message category must be path-safe.' }
        $categories[$category] = $true
        $reportPath = [string]$message.ReportPath
        if ([string]::IsNullOrWhiteSpace($reportPath) -or -not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw "Report attachment not found: $reportPath" }
        $result = if (($message.PSObject.Properties.Name -contains 'DeliveryResult') -and $null -ne $message.DeliveryResult) { $message.DeliveryResult } elseif (($message.PSObject.Properties.Name -contains 'Result') -and $null -ne $message.Result) { $message.Result } else { $message }
        $secret = if ($message.PSObject.Properties.Name -contains 'Secret') { [string]$message.Secret } else { '' }
        $errorMessage = Protect-MailErrorMessage -Message ([string]$result.ErrorMessage) -Secret $secret
        $record = [ordered]@{
            schema_version = 'mail-delivery-record-v1'; report_kind = $ReportKind; run_id = $RunId; category = $category
            report_filename = [IO.Path]::GetFileName($reportPath); report_sha256 = Get-MailDeliverySha256 -Path $reportPath
            recipient = [string]$result.Recipient; smtp_status = [string]$result.Status; sent_at = $result.SentAt
            error_message = if ([string]::IsNullOrWhiteSpace($errorMessage)) { $null } else { $errorMessage }
        }
        $recordPath = Join-Path $recordRoot ($category + '.json')
        Write-MailDeliveryJsonAtomically -Path $recordPath -Value $record | Out-Null
        $records += $record
    }
    $deliveryStatuses = @($records | ForEach-Object { [string]$_.smtp_status } | Select-Object -Unique)
    $overallStatus = if ($deliveryStatuses.Count -eq 1) { $deliveryStatuses[0] } else { 'PARTIAL_FAILURE' }
    $manifest = [ordered]@{ schema_version = 'mail-delivery-manifest-v1'; market_date = $MarketDate; report_kind = $ReportKind; run_id = $RunId; overall_status = $overallStatus; record_paths = @($records | ForEach-Object { Join-Path $recordRoot ($_.category + '.json') }) }
    $manifestPath = Write-MailDeliveryJsonAtomically -Path (Join-Path $recordRoot 'manifest.json') -Value $manifest
    $latestPath = Join-Path (Split-Path -Parent $recordRoot) 'latest.json'
    Write-MailDeliveryJsonAtomically -Path $latestPath -Value $manifest | Out-Null
    return [pscustomobject]@{ ManifestPath = $manifestPath; RecordPaths = @($manifest.record_paths); LatestPath = (Resolve-Path -LiteralPath $latestPath).Path; OverallStatus = $overallStatus }
}

Export-ModuleMember -Function Get-DailyReportMailSettings, Send-DailyReportEmail, Write-MailDeliverySummary, Get-MailDeliveryRecordRoot, Write-MailDeliveryJsonAtomically, Get-MailDeliverySha256, Write-MailDeliveryRunRecords
