param(
    [string]$MarketDate,
    [string]$SnapshotsRoot,
    [string]$ReportsRoot,
    [string]$PostgresSettingsPath,
    [string]$BackupRoot,
    [ValidateRange(1, 168)][int]$MaximumBackupAgeHours = 36,
    [string]$RegistryPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) { $RegistryPath = Join-Path $projectRoot 'config\category-registry.json' }
Import-Module (Join-Path $projectRoot 'src\BestSellersCategoryRegistry.psm1') -Force
$registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
if ([string]::IsNullOrWhiteSpace($MarketDate)) {
    $pacificNow = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTimeOffset]::Now, 'Pacific Standard Time')
    $MarketDate = $pacificNow.ToString('yyyy-MM-dd')
}
if ($MarketDate -notmatch '^\d{4}-\d{2}-\d{2}$') { throw 'MarketDate must use YYYY-MM-DD.' }
if ([string]::IsNullOrWhiteSpace($SnapshotsRoot)) { $SnapshotsRoot = Join-Path $projectRoot 'var\amazon-bestsellers' }
if ([string]::IsNullOrWhiteSpace($ReportsRoot)) { $ReportsRoot = Join-Path $projectRoot 'var\reports' }
if ([string]::IsNullOrWhiteSpace($PostgresSettingsPath)) { $PostgresSettingsPath = Join-Path $projectRoot '.local\postgres-settings.json' }
if ([string]::IsNullOrWhiteSpace($BackupRoot)) { $BackupRoot = Join-Path $projectRoot '.local\postgres-backups' }

$snapshotDirectory = Join-Path $SnapshotsRoot $MarketDate
$snapshotPath = Join-Path $snapshotDirectory 'amazon-bestsellers.json'
$receiptPath = Join-Path $snapshotDirectory 'best-sellers-capture-receipt.json'
if (-not (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) { throw "Snapshot not found: $snapshotPath" }
if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { throw "Capture receipt not found: $receiptPath" }

$receipt = & (Join-Path $projectRoot 'scripts\Test-BestSellersCaptureReceipt.ps1') -ReceiptPath $receiptPath -RegistryPath $RegistryPath | ConvertFrom-Json
if (-not $receipt.valid) { throw 'Capture receipt validation failed.' }
$snapshot = Get-Content -LiteralPath $snapshotPath -Raw -Encoding UTF8 | ConvertFrom-Json
$snapshotObservationCount = [int](@(Get-BestSellersCategoryKeys -Registry $registry -EnabledOnly | ForEach-Object {
    $categoryProperty = $snapshot.PSObject.Properties[[string]$_]
    if ($null -ne $categoryProperty) { @($categoryProperty.Value | Where-Object { $null -ne $_ }).Count } else { 0 }
}) | Measure-Object -Sum).Sum

& (Join-Path $projectRoot 'scripts\postgres\Start-LocalPostgres.ps1') -SettingsPath $PostgresSettingsPath | Out-Null
$settings = Get-Content -LiteralPath $PostgresSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$psql = Join-Path $settings.install_root 'bin\psql.exe'
$savedPassword = [Environment]::GetEnvironmentVariable('PGPASSWORD', 'Process')
try {
    $env:PGPASSWORD = [string]$settings.password
    # A market day can contain retained earlier capture attempts.  Bind the count to
    # the verified snapshot hash rather than summing every historical attempt.
    $snapshotSha256 = [string]$receipt.expected_snapshot_sha256
    if ($snapshotSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Capture receipt has an invalid snapshot SHA-256.' }
    $databaseCountText = @(& $psql '-qAt' '-h' ([string]$settings.host) '-p' ([string]$settings.port) '-U' ([string]$settings.username) '-d' ([string]$settings.database) '-c' ("SET search_path TO amazon_intelligence, public; SELECT count(*) FROM best_sellers_observation o JOIN best_sellers_run r ON r.best_sellers_run_id = o.best_sellers_run_id WHERE r.market_date = DATE '{0}' AND r.artifact_sha256 = '{1}';" -f $MarketDate, $snapshotSha256))
    if ($LASTEXITCODE -ne 0) { throw "Database observation count query failed with exit code $LASTEXITCODE." }
}
finally {
    if ($null -eq $savedPassword) { Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable('PGPASSWORD', $savedPassword, 'Process') }
}
$databaseObservationCount = 0
if (-not [int]::TryParse((($databaseCountText -join '').Trim()), [ref]$databaseObservationCount)) { throw 'Database returned an invalid observation count.' }
if ($databaseObservationCount -ne $snapshotObservationCount) { throw "Database observation count mismatch: snapshot=$snapshotObservationCount database=$databaseObservationCount" }

$reportDirectory = Join-Path $ReportsRoot $MarketDate
$pdfCount = if (Test-Path -LiteralPath $reportDirectory) { @((Get-ChildItem -LiteralPath $reportDirectory -Filter '*.pdf' -File)).Count } else { 0 }
if ($pdfCount -eq 0) { throw "No PDF report found for $MarketDate." }

$backup = @(Get-ChildItem -LiteralPath $BackupRoot -Filter '*.dump' -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
if ($backup.Count -ne 1) { throw 'No PostgreSQL backup archive found.' }
$backupVerification = & (Join-Path $projectRoot 'scripts\postgres\Test-LocalPostgresBackup.ps1') -BackupPath $backup[0].FullName | ConvertFrom-Json
if ($backupVerification.Status -ne 'VERIFIED') { throw 'Latest PostgreSQL backup did not verify.' }
$backupAgeHours = ([DateTimeOffset]::UtcNow - [DateTimeOffset]$backup[0].LastWriteTimeUtc).TotalHours
if ($backupAgeHours -gt $MaximumBackupAgeHours) { throw "Latest PostgreSQL backup is older than $MaximumBackupAgeHours hours." }

$dailyDeliveryLatestPath = Join-Path $reportDirectory 'delivery\daily\latest.json'
$deliveryStatus = if (Test-Path -LiteralPath $dailyDeliveryLatestPath -PathType Leaf) { [string]((Get-Content -LiteralPath $dailyDeliveryLatestPath -Raw -Encoding UTF8 | ConvertFrom-Json).overall_status) } else { 'NOT_RECORDED' }
[pscustomobject]@{
    Status = 'HEALTHY'
    MarketDate = $MarketDate
    CaptureReceiptValid = [bool]$receipt.valid
    SnapshotObservationCount = $snapshotObservationCount
    DatabaseObservationCount = $databaseObservationCount
    PdfCount = $pdfCount
    EmailDeliveryStatus = $deliveryStatus
    LatestBackupPath = $backup[0].FullName
    LatestBackupAgeHours = [Math]::Round($backupAgeHours, 2)
    BackupStatus = $backupVerification.Status
} | ConvertTo-Json -Depth 5
