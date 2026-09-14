param(
    [string]$MarketDate,
    [string]$EmailRecipient = '746254487@qq.com'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$logDirectory = Join-Path $projectRoot 'var\scheduler'
if (-not (Test-Path -LiteralPath $logDirectory)) { New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null }
if ([string]::IsNullOrWhiteSpace($MarketDate)) {
    $pacificNow = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTimeOffset]::Now, 'Pacific Standard Time')
    $MarketDate = $pacificNow.ToString('yyyy-MM-dd')
}
if ($MarketDate -notmatch '^\d{4}-\d{2}-\d{2}$') { throw 'MarketDate must use YYYY-MM-DD.' }

$logPath = Join-Path $logDirectory ("daily-pipeline-{0}-{1}.log" -f $MarketDate, [DateTime]::Now.ToString('yyyyMMdd-HHmmss'))
$exitCode = 0
Start-Transcript -LiteralPath $logPath -Force | Out-Null
try {
    Write-Output "Scheduled daily pipeline started. MarketDate=$MarketDate"
    & (Join-Path $projectRoot 'scripts\postgres\Start-LocalPostgres.ps1')
    $credentialNames = @('AMAZON_CREATORS_CLIENT_ID','AMAZON_CREATORS_CLIENT_SECRET','AMAZON_CREATORS_PARTNER_TAG')
    $creatorsReady = $true
    foreach ($name in $credentialNames) {
        $value = [Environment]::GetEnvironmentVariable($name, 'Process')
        if ([string]::IsNullOrWhiteSpace($value)) { $value = [Environment]::GetEnvironmentVariable($name, 'User') }
        if ([string]::IsNullOrWhiteSpace($value)) { $creatorsReady = $false }
        Remove-Variable value -ErrorAction SilentlyContinue
    }
    if ($creatorsReady) {
        Write-Output 'Mode=CREATORS_API'
        & (Join-Path $projectRoot 'scripts\Invoke-DailyPipeline.ps1') -MarketDate $MarketDate -EmailRecipient $EmailRecipient
    }
    else {
        Write-Output 'Mode=PUBLIC_DATA_ONLY'
        & (Join-Path $projectRoot 'scripts\Invoke-CredentialFreeDailyPipeline.ps1') -MarketDate $MarketDate -EmailRecipient $EmailRecipient
    }
    Write-Output 'Scheduled daily pipeline completed.'
}
catch {
    $exitCode = 1
    Write-Error $_.Exception.Message
}
finally {
    Stop-Transcript | Out-Null
}
exit $exitCode
