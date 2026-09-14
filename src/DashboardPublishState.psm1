Set-StrictMode -Version Latest

function Assert-DashboardPublishMarketDate {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$MarketDate)

    $parsedDate = [DateTime]::MinValue
    if (-not [DateTime]::TryParseExact($MarketDate, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsedDate)) {
        throw 'MarketDate must use yyyy-MM-dd format.'
    }
}

function Get-DashboardPublishStatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$MarketDate
    )

    Assert-DashboardPublishMarketDate -MarketDate $MarketDate
    Join-Path (Join-Path (Join-Path $Root 'var\scheduler') 'dashboard-publish') ($MarketDate + '.json')
}

function ConvertTo-DashboardPublishSanitizedError {
    [CmdletBinding()]
    param([AllowNull()][string]$ErrorMessage)

    if ([string]::IsNullOrWhiteSpace($ErrorMessage)) { return $null }

    $sanitized = $ErrorMessage
    $sanitized = [regex]::Replace($sanitized, '(?i)(?:postgres(?:ql)?|smtp)://[^\s,;]+', '[REDACTED_CONNECTION_STRING]')
    $sanitized = [regex]::Replace($sanitized, '(?i)(bearer\s+)[^\s,;]+', '$1[REDACTED]')
    $sanitized = [regex]::Replace($sanitized, '(?i)((?:password|pwd|secret|token|authorization)\s*[:=]\s*)[^\s,;]+', '$1[REDACTED]')
    $sanitized
}

function Enter-DashboardPublishLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$MarketDate,
        [int]$TimeoutSeconds = 0
    )

    Assert-DashboardPublishMarketDate -MarketDate $MarketDate
    $mutexName = 'AmazonBS-DashboardPublish-' + $MarketDate
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    try {
        if (-not $mutex.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))) {
            throw "Dashboard publication is already running for $MarketDate."
        }
        return $mutex
    }
    catch {
        $mutex.Dispose()
        throw
    }
}

function Read-DashboardPublishState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$MarketDate
    )

    $path = Get-DashboardPublishStatePath -Root $Root -MarketDate $MarketDate
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }

    try {
        $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $propertyNames = @($state.PSObject.Properties | ForEach-Object { $_.Name })
        foreach ($requiredProperty in @('Status', 'MarketDate', 'CompletedAt', 'ObservationCount', 'ReportsUploaded', 'ErrorMessage')) {
            if ($propertyNames -notcontains $requiredProperty) { return $null }
        }
        if ($state.MarketDate -ne $MarketDate) { return $null }
        if (@('PUBLISHED', 'FAILED') -notcontains [string]$state.Status) { return $null }
        if ([string]::IsNullOrWhiteSpace([string]$state.CompletedAt)) { return $null }
        $completedAt = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse([string]$state.CompletedAt, [ref]$completedAt)) { return $null }
        if ($null -eq $state.ObservationCount -or $null -eq $state.ReportsUploaded) { return $null }
        $observationCount = 0
        $reportsUploaded = 0
        if (-not [int]::TryParse([string]$state.ObservationCount, [ref]$observationCount)) { return $null }
        if (-not [int]::TryParse([string]$state.ReportsUploaded, [ref]$reportsUploaded)) { return $null }
        $state.ObservationCount = $observationCount
        $state.ReportsUploaded = $reportsUploaded
        return $state
    }
    catch {
        return $null
    }
}

function Write-DashboardPublishState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$MarketDate,
        [Parameter(Mandatory = $true)][ValidateSet('PUBLISHED', 'FAILED')][string]$Status,
        [Parameter(Mandatory = $true)][int]$ObservationCount,
        [Parameter(Mandatory = $true)][int]$ReportsUploaded,
        [AllowNull()][string]$ErrorMessage
    )

    $path = Get-DashboardPublishStatePath -Root $Root -MarketDate $MarketDate
    $directory = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $state = [ordered]@{
        Status = $Status
        MarketDate = $MarketDate
        CompletedAt = [DateTimeOffset]::UtcNow.ToString('o')
        ObservationCount = $ObservationCount
        ReportsUploaded = $ReportsUploaded
        ErrorMessage = if ($Status -eq 'FAILED') { ConvertTo-DashboardPublishSanitizedError -ErrorMessage $ErrorMessage } else { $null }
    }
    $temporaryPath = $path + '.tmp'
    $backupPath = $path + '.bak'
    [System.IO.File]::WriteAllText($temporaryPath, ($state | ConvertTo-Json -Depth 3), [Text.Encoding]::UTF8)
    try {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            [System.IO.File]::Replace($temporaryPath, $path, $backupPath)
        }
        else {
            [System.IO.File]::Move($temporaryPath, $path)
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            Remove-Item -LiteralPath $backupPath -Force
        }
    }

    $path
}

Export-ModuleMember -Function 'Enter-DashboardPublishLock', 'Read-DashboardPublishState', 'Write-DashboardPublishState'
