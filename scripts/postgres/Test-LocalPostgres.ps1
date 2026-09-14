param(
    [string]$SettingsPath,
    [scriptblock]$QueryAction
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($SettingsPath)) { $SettingsPath = Join-Path $projectRoot '.local\postgres-settings.json' }
$settings = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$psql = Join-Path $settings.install_root 'bin\psql.exe'
$env:PGPASSWORD = [string]$settings.password
$common = @('-h', [string]$settings.host, '-p', [string]$settings.port, '-U', [string]$settings.username, '-d', [string]$settings.database, '-X', '--no-psqlrc', '-v', 'ON_ERROR_STOP=1')

if ($null -eq $QueryAction) {
    $QueryAction = {
        param([string]$Sql)
        & $psql @common -tAc $Sql
    }
}

function Invoke-HealthQuery {
    param([string]$Sql)

    $lines = @(& $QueryAction $Sql)
    return (($lines | ForEach-Object { [string]$_ }) -join "`n").Trim()
}

try {
    $requiredViews = @(
        'best_sellers_accessory_classification_latest'
        'best_sellers_daily_change'
        'best_sellers_daily_current'
        'best_sellers_daily_exit'
        'best_sellers_opportunity_latest'
        'best_sellers_price_band_latest'
        'best_sellers_rank_association_latest'
        'best_sellers_rank_bucket_latest'
        'best_sellers_valid_category_day'
        'daily_ranking'
        'new_brand_tracker'
        'new_product_entry'
        'public_safety_current'
        'public_safety_daily_change'
        'rising_products'
        'trend_analysis'
    )

    $serverVersion = Invoke-HealthQuery -Sql 'SHOW server_version;'
    $tableCount = [int](Invoke-HealthQuery -Sql "SELECT count(*) FROM information_schema.tables WHERE table_schema='amazon_intelligence';")
    $viewNames = @(
        (Invoke-HealthQuery -Sql "SELECT table_name FROM information_schema.views WHERE table_schema='amazon_intelligence' ORDER BY table_name;") -split '\r?\n' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    )
    $viewCount = $viewNames.Count
    $sourceCount = [int](Invoke-HealthQuery -Sql "SELECT count(*) FROM amazon_intelligence.source_definition WHERE active;")
    $migrationCount = [int](Invoke-HealthQuery -Sql 'SELECT count(*) FROM public.schema_migration;')
    $expectedMigrationCount = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'db\migrations') -Filter '*.sql' -File).Count

    if ($tableCount -lt 20) { throw "Expected at least 20 application tables, found $tableCount" }
    $missingViews = @($requiredViews | Where-Object { $viewNames -cnotcontains $_ })
    $unexpectedViews = @($viewNames | Where-Object { $requiredViews -cnotcontains $_ })
    if ($viewCount -ne $requiredViews.Count -or $missingViews.Count -gt 0 -or $unexpectedViews.Count -gt 0) {
        $missingSummary = if ($missingViews.Count -eq 0) { '(none)' } else { $missingViews -join ', ' }
        $unexpectedSummary = if ($unexpectedViews.Count -eq 0) { '(none)' } else { $unexpectedViews -join ', ' }
        throw "Reporting view set mismatch. Expected exactly $($requiredViews.Count) required views, found $viewCount. Missing: $missingSummary. Unexpected: $unexpectedSummary."
    }
    if ($sourceCount -ne 3) { throw "Expected 3 active Search sources, found $sourceCount" }
    if ($migrationCount -ne $expectedMigrationCount) { throw "Expected $expectedMigrationCount migrations, found $migrationCount" }

    [pscustomobject]@{
        ServerVersion = $serverVersion
        ApplicationTables = $tableCount
        ReportingViews = $viewCount
        ActiveSources = $sourceCount
        AppliedMigrations = $migrationCount
        Status = 'PASSED'
    } | Format-List
}
finally {
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}
