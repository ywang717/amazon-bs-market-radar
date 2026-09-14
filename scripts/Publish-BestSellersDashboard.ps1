param(
    [Parameter(Mandatory=$true)][uri]$DashboardUrl,
    [string]$MarketDate,
    [string]$SnapshotsRoot,
    [string]$ProjectRoot,
    [scriptblock]$PublishOperation,
    [hashtable]$TestHooks,
    [string]$RegistryPath
)

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) { $RegistryPath = Join-Path $sourceRoot 'config\category-registry.json' }
Import-Module (Join-Path $sourceRoot 'src\DashboardPublishHttp.psm1') -Force
Import-Module (Join-Path $sourceRoot 'src\BestSellersCategoryRegistry.psm1') -Force
$categoryRegistry = Import-BestSellersCategoryRegistry -Path $RegistryPath
$script:DashboardEnabledCategoryKeys = @(Get-BestSellersCategoryKeys -Registry $categoryRegistry -EnabledOnly)
$script:DashboardExpectedScopedReportCount = $script:DashboardEnabledCategoryKeys.Count + 1
$script:DashboardReportScopePattern = '(?:overview|' + (@($script:DashboardEnabledCategoryKeys | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')'

function Test-DashboardPublishHook {
    param([Parameter(Mandatory = $true)][string]$Name)

    return $null -ne $TestHooks -and $TestHooks.ContainsKey($Name) -and $null -ne $TestHooks[$Name]
}

function Invoke-DashboardPublishHook {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [object[]]$Arguments = @()
    )

    return & $TestHooks[$Name] @Arguments
}

function Invoke-DashboardPublishRest {
    param(
        [Parameter(Mandatory = $true)][uri]$Uri,
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][hashtable]$Headers,
        [Parameter(Mandatory = $true)][string]$ContentType,
        [string]$InFile,
        $Body
    )

    if (Test-DashboardPublishHook -Name 'Rest') {
        return Invoke-DashboardPublishHook -Name 'Rest' -Arguments @($Uri,$Method,$Headers,$ContentType,$InFile,$Body)
    }
    if ($null -ne (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
        return Invoke-DashboardPublishCurlRest -Uri $Uri -Method $Method -Headers $Headers -ContentType $ContentType -InFile $InFile -Body $Body -BodyProvided:$PSBoundParameters.ContainsKey('Body')
    }
    $requestParameters = New-DashboardPublishRestParameters -Uri $Uri -Method $Method -Headers $Headers -ContentType $ContentType -InFile $InFile -Body $Body -BodyProvided:$PSBoundParameters.ContainsKey('Body')
    if ($Method -ieq 'Get' -and $ContentType -match '^application/json(?:\s*;|$)') {
        if ((Get-Command Invoke-WebRequest).Parameters.ContainsKey('UseBasicParsing')) {
            $requestParameters.UseBasicParsing = $true
        }
        $response = Invoke-WebRequest @requestParameters
        return ConvertFrom-DashboardUtf8JsonResponse -Response $response
    }
    return Invoke-RestMethod @requestParameters
}

function Test-DashboardImmutableKeyConflict {
    param([Parameter(Mandatory = $true)]$Failure)

    $statusCode = $null
    if ($null -ne $Failure.Exception.StatusCode) {
        $statusCode = [int]$Failure.Exception.StatusCode
    }
    elseif ($null -ne $Failure.Exception.Response -and $null -ne $Failure.Exception.Response.StatusCode) {
        $statusCode = [int]$Failure.Exception.Response.StatusCode
    }
    if ($statusCode -ne 409) { return $false }

    foreach ($message in @([string]$Failure.ErrorDetails.Message, [string]$Failure.Exception.Message)) {
        if ([string]::IsNullOrWhiteSpace($message)) { continue }
        try {
            $payload = $message | ConvertFrom-Json
            if ([string]$payload.error -ceq 'immutable_key_conflict') { return $true }
        }
        catch { }
    }
    return $false
}

function ConvertTo-DashboardCanonicalValue {
    param($Value)

    if ($null -eq $Value) { return [pscustomobject]@{ type = 'null' } }
    $numericTypes = @(
        [byte], [sbyte], [int16], [uint16], [int32], [uint32], [int64], [uint64],
        [single], [double], [decimal]
    )
    if ($Value -is [bool]) { return [pscustomobject]@{ type = 'boolean'; value = [bool]$Value } }
    if ($numericTypes -contains $Value.GetType()) {
        $invariantCulture = [Globalization.CultureInfo]::InvariantCulture
        if ($Value -is [double]) {
            $numberText = ([double]$Value).ToString('R', $invariantCulture)
        }
        elseif ($Value -is [single]) {
            $numberText = ([single]$Value).ToString('R', $invariantCulture)
        }
        elseif ($Value -is [decimal]) {
            $numberText = ([decimal]$Value).ToString('G29', $invariantCulture)
        }
        else {
            $numberText = [Convert]::ToString($Value, $invariantCulture)
        }
        return [pscustomobject]@{ type = 'number'; value = $numberText }
    }
    if ($Value -is [string]) { return [pscustomobject]@{ type = 'string'; value = [string]$Value } }
    if ($Value -is [Collections.IDictionary]) {
        $properties = [ordered]@{}
        foreach ($name in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object -CaseSensitive)) {
            $properties[$name] = ConvertTo-DashboardCanonicalValue -Value $Value[$name]
        }
        return [pscustomobject]@{ type = 'object'; value = [pscustomobject]$properties }
    }
    if ($Value -is [Collections.IEnumerable]) {
        $items = @()
        foreach ($item in $Value) { $items += ,(ConvertTo-DashboardCanonicalValue -Value $item) }
        return [pscustomobject]@{ type = 'array'; value = $items }
    }

    $properties = [ordered]@{}
    foreach ($property in @($Value.PSObject.Properties | Sort-Object Name -CaseSensitive)) {
        $properties[$property.Name] = ConvertTo-DashboardCanonicalValue -Value $property.Value
    }
    return [pscustomobject]@{ type = 'object'; value = [pscustomobject]$properties }
}

function Get-DashboardAnalysisSemanticFingerprint {
    param([Parameter(Mandatory = $true)]$Report)

    $semantic = [ordered]@{}
    foreach ($property in @($Report.PSObject.Properties | Sort-Object Name -CaseSensitive)) {
        if ($property.Name -in @('generatedAt', 'contentSha256')) { continue }
        $semantic[$property.Name] = ConvertTo-DashboardCanonicalValue -Value $property.Value
    }
    return ([pscustomobject]$semantic | ConvertTo-Json -Depth 32 -Compress)
}

function Test-DashboardAnalysisSemanticEquivalent {
    param(
        [Parameter(Mandatory = $true)]$LocalReport,
        [Parameter(Mandatory = $true)]$RemoteReport
    )

    return (Get-DashboardAnalysisSemanticFingerprint -Report $LocalReport) -ceq (Get-DashboardAnalysisSemanticFingerprint -Report $RemoteReport)
}

function Get-DashboardSellerSemanticFingerprint {
    param([Parameter(Mandatory = $true)]$Report)

    $semantic = [ordered]@{}
    foreach ($property in @($Report.PSObject.Properties | Sort-Object Name -CaseSensitive)) {
        if ($property.Name -in @('generatedAt', 'contentSha256', 'receiptSha256')) { continue }
        if ($property.Name -eq 'signals') {
            $semantic[$property.Name] = @(
                @($property.Value) |
                    ForEach-Object { ConvertTo-DashboardCanonicalValue -Value $_ | ConvertTo-Json -Depth 32 -Compress } |
                    Sort-Object -CaseSensitive
            )
        }
        else {
            $semantic[$property.Name] = ConvertTo-DashboardCanonicalValue -Value $property.Value
        }
    }
    return ([pscustomobject]$semantic | ConvertTo-Json -Depth 32 -Compress)
}

function Test-DashboardSellerSemanticEquivalent {
    param(
        [Parameter(Mandatory = $true)]$LocalReport,
        [Parameter(Mandatory = $true)]$RemoteReport
    )

    return (Get-DashboardSellerSemanticFingerprint -Report $LocalReport) -ceq (Get-DashboardSellerSemanticFingerprint -Report $RemoteReport)
}

function Invoke-DashboardSellerIntelligenceBundleUpload {
    param(
        [Parameter(Mandatory = $true)][uri]$SyncEndpoint,
        [Parameter(Mandatory = $true)][uri]$DashboardUrl,
        [Parameter(Mandatory = $true)][hashtable]$Headers,
        [Parameter(Mandatory = $true)]$Body
    )

    try {
        return Invoke-DashboardPublishRest -Uri $SyncEndpoint -Method Post -Headers $Headers -ContentType 'application/json' -Body $Body
    }
    catch {
        if (-not (Test-DashboardImmutableKeyConflict -Failure $_)) { throw }

        foreach ($localReport in @($Body.reports)) {
            $key = [string]$localReport.key
            if ($key -notmatch "^(seller-alert/daily|competition-strategy/weekly)/\d{4}-\d{2}-\d{2}/$($script:DashboardReportScopePattern)\.json$") {
                throw 'Seller intelligence report immutable key conflict could not be verified.'
            }
            $encodedKey = (@($key -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/')
            $publicEndpoint = [uri]::new($DashboardUrl, "/api/public/seller-intelligence/$encodedKey")
            try {
                $remoteReport = Invoke-DashboardPublishRest -Uri $publicEndpoint -Method Get -Headers @{} -ContentType 'application/json'
            }
            catch {
                throw 'Seller intelligence report immutable key conflict could not be verified.'
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$Body.receiptSha256) -and [string]$remoteReport.receiptSha256 -cne [string]$Body.receiptSha256) {
                throw 'Seller intelligence report immutable key conflict is not semantically equivalent.'
            }
            if (-not (Test-DashboardSellerSemanticEquivalent -LocalReport $localReport -RemoteReport $remoteReport)) {
                throw 'Seller intelligence report immutable key conflict is not semantically equivalent.'
            }
        }
        return [pscustomobject]@{ status = 'equivalent_conflict'; reportCount = @($Body.reports).Count }
    }
}

function Invoke-DashboardAnalysisReportUpload {
    param(
        [Parameter(Mandatory = $true)][uri]$SyncEndpoint,
        [Parameter(Mandatory = $true)][uri]$DashboardUrl,
        [Parameter(Mandatory = $true)][hashtable]$Headers,
        [Parameter(Mandatory = $true)][string]$AnalysisPath
    )

    try {
        return Invoke-DashboardPublishRest -Uri $SyncEndpoint -Method Post -Headers $Headers -ContentType 'application/json' -InFile $AnalysisPath
    }
    catch {
        if (-not (Test-DashboardImmutableKeyConflict -Failure $_)) { throw }

        $localReport = Get-Content -LiteralPath $AnalysisPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $key = [string]$localReport.key
        if ($key -notmatch "^(daily|weekly)/\d{4}-\d{2}-\d{2}/$($script:DashboardReportScopePattern)\.json$") {
            throw 'Analysis report immutable key conflict could not be verified.'
        }
        $encodedKey = (@($key -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/')
        $publicEndpoint = [uri]::new($DashboardUrl, "/api/public/analysis/$encodedKey")
        try {
            $remoteReport = Invoke-DashboardPublishRest -Uri $publicEndpoint -Method Get -Headers @{} -ContentType 'application/json'
        }
        catch {
            throw 'Analysis report immutable key conflict could not be verified.'
        }
        if (-not (Test-DashboardAnalysisSemanticEquivalent -LocalReport $localReport -RemoteReport $remoteReport)) {
            throw 'Analysis report immutable key conflict is not semantically equivalent.'
        }
        return [pscustomobject]@{ status = 'equivalent_conflict'; key = $key }
    }
}

function Get-DashboardAnalysisBundleBody {
    param([Parameter(Mandatory = $true)]$AnalysisRun)

    $paths = @($AnalysisRun.ReportPaths)
    if ([int]$AnalysisRun.ReportCount -ne $script:DashboardExpectedScopedReportCount -or $paths.Count -ne $script:DashboardExpectedScopedReportCount) { throw 'Analysis report paths must contain the Registry-sized set of unique readable JSON files.' }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $reports = New-Object System.Collections.Generic.List[object]
    foreach ($path in $paths) {
        if ([string]::IsNullOrWhiteSpace([string]$path) -or -not $seen.Add([string]$path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw 'Analysis report paths must contain the Registry-sized set of unique readable JSON files.'
        }
        try {
            $reports.Add((Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json))
        }
        catch {
            throw 'Analysis report paths must contain the Registry-sized set of unique readable JSON files.'
        }
    }
    return [pscustomobject]@{ reports = $reports.ToArray() }
}

function Invoke-DashboardAnalysisBundleUpload {
    param(
        [Parameter(Mandatory = $true)][uri]$SyncEndpoint,
        [Parameter(Mandatory = $true)][uri]$DashboardUrl,
        [Parameter(Mandatory = $true)][hashtable]$Headers,
        [Parameter(Mandatory = $true)]$AnalysisBody
    )

    try {
        return Invoke-DashboardPublishRest -Uri $SyncEndpoint -Method Post -Headers $Headers -ContentType 'application/json' -Body $AnalysisBody
    }
    catch {
        if (-not (Test-DashboardImmutableKeyConflict -Failure $_)) { throw }

        foreach ($localReport in @($AnalysisBody.reports)) {
            $key = [string]$localReport.key
            if ($key -notmatch "^daily/\d{4}-\d{2}-\d{2}/$($script:DashboardReportScopePattern)\.json$") {
                throw 'Analysis report immutable key conflict could not be verified.'
            }
            $encodedKey = (@($key -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/')
            $publicEndpoint = [uri]::new($DashboardUrl, "/api/public/analysis/$encodedKey")
            try {
                $remoteReport = Invoke-DashboardPublishRest -Uri $publicEndpoint -Method Get -Headers @{} -ContentType 'application/json'
            }
            catch {
                throw 'Analysis report immutable key conflict could not be verified.'
            }
            if (-not (Test-DashboardAnalysisSemanticEquivalent -LocalReport $localReport -RemoteReport $remoteReport)) {
                throw 'Analysis report immutable key conflict is not semantically equivalent.'
            }
        }
        return [pscustomobject]@{ status = 'equivalent_conflict'; reports = @($AnalysisBody.reports).Count }
    }
}

function Get-DashboardSellerBundleBody {
    param(
        [Parameter(Mandatory = $true)]$SellerRun,
        [string]$ReceiptSha256
    )

    $paths = @($SellerRun.ReportPaths)
    if ([int]$SellerRun.ReportCount -ne $script:DashboardExpectedScopedReportCount -or $paths.Count -ne $script:DashboardExpectedScopedReportCount) { throw 'Seller intelligence report paths must contain the Registry-sized set of unique readable JSON files.' }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $reports = New-Object System.Collections.Generic.List[object]
    foreach ($path in $paths) {
        if ([string]::IsNullOrWhiteSpace([string]$path) -or -not $seen.Add([string]$path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw 'Seller intelligence report paths must contain the Registry-sized set of unique readable JSON files.'
        }
        try {
            $reports.Add((Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json))
        }
        catch {
            throw 'Seller intelligence report paths must contain the Registry-sized set of unique readable JSON files.'
        }
    }
    $body = [ordered]@{ reports = $reports.ToArray() }
    if (-not [string]::IsNullOrWhiteSpace($ReceiptSha256)) { $body.receiptSha256 = $ReceiptSha256 }
    return [pscustomobject]$body
}

function Invoke-DashboardSellerIntelligenceBundle {
    param(
        [Parameter(Mandatory = $true)][uri]$Endpoint,
        [Parameter(Mandatory = $true)][hashtable]$Headers,
        [Parameter(Mandatory = $true)][string]$SnapshotPath,
        [Parameter(Mandatory = $true)][string]$SnapshotsRoot,
        [Parameter(Mandatory = $true)][ValidateSet('Daily','Weekly')][string]$ReportKind,
        [string]$ReportDate,
        [string]$ReceiptSha256
    )

    $sellerRun = if (Test-DashboardPublishHook -Name 'SellerReports') {
        Invoke-DashboardPublishHook -Name 'SellerReports' -Arguments @($SnapshotPath,$SnapshotsRoot,$ReportKind,$ReportDate)
    }
    else {
        & (Join-Path $sourceRoot 'scripts\New-SellerIntelligenceReports.ps1') -SnapshotPath $SnapshotPath -SnapshotsRoot $SnapshotsRoot -ReportKind $ReportKind -ReportDate $ReportDate -RegistryPath $RegistryPath | ConvertFrom-Json
    }
    if ([string]$sellerRun.Status -ne 'CREATED' -or [int]$sellerRun.ReportCount -ne $script:DashboardExpectedScopedReportCount) {
        $message = if ($ReportKind -eq 'Daily') { 'Seller alert reports were not created.' } else { 'Competition strategy reports were not created.' }
        throw $message
    }
    if ($ReportKind -eq 'Daily' -and $ReceiptSha256 -notmatch '^[a-f0-9]{64}$') { throw 'Daily seller intelligence requires a verified snapshot receipt.' }
    if ($ReportKind -eq 'Daily') {
        $receiptVerification = if (Test-DashboardPublishHook -Name 'CaptureReceipt') {
            Invoke-DashboardPublishHook -Name 'CaptureReceipt' -Arguments @($SnapshotPath)
        }
        else {
            $receiptPath = Join-Path (Split-Path -Parent $SnapshotPath) 'best-sellers-capture-receipt.json'
            & (Join-Path $sourceRoot 'scripts\Test-BestSellersCaptureReceipt.ps1') -ReceiptPath $receiptPath -RegistryPath $RegistryPath | ConvertFrom-Json
        }
        if (-not [bool]$receiptVerification.valid -or [string]$receiptVerification.actual_snapshot_sha256 -cne $ReceiptSha256.ToLowerInvariant()) {
            throw 'Daily seller intelligence snapshot receipt changed during report generation.'
        }
    }
    $body = Get-DashboardSellerBundleBody -SellerRun $sellerRun -ReceiptSha256 $(if ($ReportKind -eq 'Daily') { $ReceiptSha256 } else { $null })
    $sellerResult = Invoke-DashboardSellerIntelligenceBundleUpload -SyncEndpoint $Endpoint -DashboardUrl $DashboardUrl -Headers $Headers -Body $body
    if ([string]$sellerResult.status -notin @('imported','duplicate','equivalent_conflict')) { throw 'Unexpected seller intelligence sync result.' }
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $sourceRoot }
$logDirectory = Join-Path $ProjectRoot 'var\scheduler'
if (-not (Test-Path -LiteralPath $logDirectory -PathType Container)) { New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null }
$logPath = Join-Path $logDirectory ("dashboard-publish-{0}.log" -f [DateTime]::Now.ToString('yyyyMMdd-HHmmss'))
Start-Transcript -LiteralPath $logPath -Force | Out-Null

$mutex = $null
$lockAcquired = $false
try {
    if ([string]::IsNullOrWhiteSpace($MarketDate)) { $MarketDate = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTimeOffset]::Now,'Pacific Standard Time').ToString('yyyy-MM-dd') }
    if ([string]::IsNullOrWhiteSpace($SnapshotsRoot)) { $SnapshotsRoot = Join-Path $ProjectRoot 'var\amazon-bestsellers' }

    Import-Module (Join-Path $sourceRoot 'src\DashboardPublishState.psm1') -Force
    $mutex = Enter-DashboardPublishLock -MarketDate $MarketDate
    $lockAcquired = $true

    if ($null -ne $PublishOperation) {
        $publishResult = & $PublishOperation
    }
    else {
        $secret = [Environment]::GetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET','Process')
        if ([string]::IsNullOrWhiteSpace($secret)) { $secret = [Environment]::GetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET','User') }
        if ([string]::IsNullOrWhiteSpace($secret)) { throw 'Dashboard sync secret is not configured.' }
        $snapshotPath = Join-Path (Join-Path $SnapshotsRoot $MarketDate) 'amazon-bestsellers.json'
        $bundleSummary = if (Test-DashboardPublishHook -Name 'BuildSyncBundle') {
            Invoke-DashboardPublishHook -Name 'BuildSyncBundle' -Arguments @($snapshotPath)
        }
        else {
            & (Join-Path $sourceRoot 'scripts\New-DashboardSyncBundle.ps1') -SnapshotPath $snapshotPath -RegistryPath $RegistryPath | ConvertFrom-Json
        }
        $health = if (Test-DashboardPublishHook -Name 'Health') {
            Invoke-DashboardPublishHook -Name 'Health' -Arguments @($MarketDate)
        }
        else {
            & (Join-Path $sourceRoot 'scripts\Test-BestSellersDailyOperationalHealth.ps1') -MarketDate $MarketDate -RegistryPath $RegistryPath | ConvertFrom-Json
        }
        if ([string]$health.Status -ne 'HEALTHY') { throw 'Operational health must be healthy before dashboard publishing.' }
        $headers = @{ Authorization = "Bearer $secret" }
        $result = Invoke-DashboardPublishRest -Uri ([uri]::new($DashboardUrl,'/api/sync/v1/bundles')) -Method Post -Headers $headers -ContentType 'application/json' -InFile $bundleSummary.BundlePath

        $sellerEndpoint = [uri]::new($DashboardUrl,'/api/sync/v1/seller-intelligence')
        Invoke-DashboardSellerIntelligenceBundle -Endpoint $sellerEndpoint -Headers $headers -SnapshotPath $snapshotPath -SnapshotsRoot $SnapshotsRoot -ReportKind Daily -ReceiptSha256 ([string]$bundleSummary.ReceiptSha256)

        $analysisRun = if (Test-DashboardPublishHook -Name 'AnalysisReports') {
            Invoke-DashboardPublishHook -Name 'AnalysisReports' -Arguments @($snapshotPath,$SnapshotsRoot,'Daily',$null)
        }
        else {
            & (Join-Path $sourceRoot 'scripts\New-OnlineAnalysisReports.ps1') -SnapshotPath $snapshotPath -SnapshotsRoot $SnapshotsRoot -ReportKind Daily -RegistryPath $RegistryPath | ConvertFrom-Json
        }
        if ([string]$analysisRun.Status -ne 'CREATED' -or [int]$analysisRun.ReportCount -ne $script:DashboardExpectedScopedReportCount) { throw 'Daily online analysis reports were not created.' }
        $analysisEndpoint = [uri]::new($DashboardUrl,'/api/sync/v1/analysis-reports')
        $analysisBody = Get-DashboardAnalysisBundleBody -AnalysisRun $analysisRun
        $analysisResult = Invoke-DashboardAnalysisBundleUpload -SyncEndpoint $analysisEndpoint -DashboardUrl $DashboardUrl -Headers $headers -AnalysisBody $analysisBody
        if ([string]$analysisResult.status -notin @('imported','duplicate','replaced','equivalent_conflict')) { throw 'Unexpected daily analysis sync result.' }

        $chinaTimeZone = [TimeZoneInfo]::FindSystemTimeZoneById('China Standard Time')
        $beijingDate = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $chinaTimeZone).ToString('yyyy-MM-dd')
        $weeklyDirectory = Join-Path (Join-Path (Join-Path $ProjectRoot 'var\reports') 'weekly') $beijingDate
        if ((Get-ChildItem -LiteralPath $weeklyDirectory -File -Filter 'Amazon_US_Weekly_Best_Sellers_Analysis_*.json' -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) {
            Invoke-DashboardSellerIntelligenceBundle -Endpoint $sellerEndpoint -Headers $headers -SnapshotPath $snapshotPath -SnapshotsRoot $SnapshotsRoot -ReportKind Weekly -ReportDate $MarketDate

            $weeklyRun = if (Test-DashboardPublishHook -Name 'AnalysisReports') {
                Invoke-DashboardPublishHook -Name 'AnalysisReports' -Arguments @($snapshotPath,$SnapshotsRoot,'Weekly',$MarketDate)
            }
            else {
                & (Join-Path $sourceRoot 'scripts\New-OnlineAnalysisReports.ps1') -SnapshotPath $snapshotPath -SnapshotsRoot $SnapshotsRoot -ReportKind Weekly -ReportDate $MarketDate -RegistryPath $RegistryPath | ConvertFrom-Json
            }
            if ([string]$weeklyRun.Status -ne 'CREATED' -or [int]$weeklyRun.ReportCount -ne $script:DashboardExpectedScopedReportCount) { throw 'Weekly online analysis reports were not created.' }
            foreach ($analysisPath in @($weeklyRun.ReportPaths)) {
                Invoke-DashboardAnalysisReportUpload -SyncEndpoint $analysisEndpoint -DashboardUrl $DashboardUrl -Headers $headers -AnalysisPath $analysisPath | Out-Null
            }
        }

        $reportsUploaded = 0
        $reportUploadFailed = $false
        try {
            Import-Module (Join-Path $sourceRoot 'src\DashboardReportSelection.psm1') -Force
            $desktopRootName = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5Lqa6ams6YCKYnPmppzljZXmr4/ml6Xnm5Hmjqc='))
            $desktopRoot = Join-Path ([Environment]::GetFolderPath('Desktop')) $desktopRootName
            $reportEndpoint = [uri]::new($DashboardUrl,'/api/sync/v1/reports')
            $reportsToUpload = @(Get-DashboardReportsToUpload -DesktopRoot $desktopRoot -MarketDate $MarketDate -BeijingDate $beijingDate -RegistryPath $RegistryPath)

            foreach ($report in $reportsToUpload) {
                $reportHeaders = @{
                    Authorization = "Bearer $secret"
                    'x-report-key' = $report.Key
                    'x-market-date' = $report.ReportDate
                    'x-report-kind' = $report.Kind
                    'x-category-key' = $report.Category
                    'x-report-title' = $report.Title
                }
                Invoke-DashboardPublishRest -Uri $reportEndpoint -Method Post -Headers $reportHeaders -ContentType 'application/pdf' -InFile $report.File.FullName | Out-Null
                $reportsUploaded++
            }
        }
        catch {
            $reportUploadFailed = $true
            Write-Warning 'Dashboard data was published, but report upload failed. See the scheduler transcript for the failure details.'
        }

        Import-Module (Join-Path $sourceRoot 'src\DashboardPublishPolicy.psm1') -Force
        $publishResult = New-DashboardPublishResult -MarketDate $MarketDate -RemoteStatus ([string]$result.status) -ObservationCount ([int]$result.observations) -ReportsUploaded $reportsUploaded -ReportUploadFailed:$reportUploadFailed
    }

    if ($null -eq $publishResult -or [string]$publishResult.Status -ne 'PUBLISHED') {
        throw 'Dashboard publication did not produce a PUBLISHED result.'
    }
    Write-DashboardPublishState -Root $ProjectRoot -MarketDate $MarketDate -Status PUBLISHED -ObservationCount ([int]$publishResult.ObservationCount) -ReportsUploaded ([int]$publishResult.ReportsUploaded) | Out-Null
    $publishResult | ConvertTo-Json
}
catch {
    if ($lockAcquired) {
        try {
            Write-DashboardPublishState -Root $ProjectRoot -MarketDate $MarketDate -Status FAILED -ObservationCount 0 -ReportsUploaded 0 -ErrorMessage $_.Exception.Message | Out-Null
        }
        catch {
            Write-Warning 'Dashboard publication failed and its failure state could not be persisted.'
        }
    }
    throw
}
finally {
    if ($null -ne $mutex) {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
    Stop-Transcript | Out-Null
}
