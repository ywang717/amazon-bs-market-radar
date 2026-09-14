param(
    [string]$MarketDate,
    [string]$ProjectRoot,
    [uri]$DashboardUrl,
    [scriptblock]$Publisher
)

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $sourceRoot }
if ([string]::IsNullOrWhiteSpace($MarketDate)) {
    $MarketDate = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTimeOffset]::Now, 'Pacific Standard Time').ToString('yyyy-MM-dd')
}

Import-Module (Join-Path $sourceRoot 'src\DashboardPublishState.psm1') -Force
$mutex = Enter-DashboardPublishLock -MarketDate $MarketDate
try {
    $state = Read-DashboardPublishState -Root $ProjectRoot -MarketDate $MarketDate
    if ($null -ne $state -and $state.Status -eq 'PUBLISHED') {
        [pscustomobject]@{
            Status = 'SKIPPED_ALREADY_PUBLISHED'
            MarketDate = $MarketDate
        } | ConvertTo-Json -Compress
        return
    }

    if ($null -eq $Publisher) {
        if ($null -eq $DashboardUrl) { throw 'DashboardUrl is required when Publisher is not supplied.' }
        $publishScript = Join-Path $sourceRoot 'scripts\Publish-BestSellersDashboard.ps1'
        & $publishScript -DashboardUrl $DashboardUrl -MarketDate $MarketDate -ProjectRoot $ProjectRoot
    }
    else {
        & $Publisher
    }
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
