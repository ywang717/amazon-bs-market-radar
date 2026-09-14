$projectRoot = Split-Path -Parent $PSScriptRoot
$healthScript = Join-Path $projectRoot 'scripts\postgres\Test-LocalPostgres.ps1'

Describe 'Local PostgreSQL schema health' {
    BeforeEach {
        $settingsPath = Join-Path $TestDrive 'postgres-settings.json'
        @{
            install_root = (Join-Path $TestDrive 'fake-postgres')
            host = 'localhost'
            port = 5432
            username = 'postgres'
            database = 'amazon_intelligence'
            password = 'test-only'
        } | ConvertTo-Json | Set-Content -LiteralPath $settingsPath -Encoding UTF8

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
        $migrationCount = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'db\migrations') -Filter '*.sql' -File).Count
    }

    It 'accepts the exact 16 required reporting views after migration 012' {
        $viewOutput = $requiredViews -join "`n"
        $expectedMigrationOutput = [string]$migrationCount
        $queryAction = {
            param([string]$Sql)

            if ($Sql -eq 'SHOW server_version;') { return '16.4' }
            if ($Sql -match 'information_schema\.tables') { return '20' }
            if ($Sql -match 'SELECT table_name FROM information_schema\.views') { return $viewOutput }
            if ($Sql -match 'source_definition') { return '3' }
            if ($Sql -match 'schema_migration') { return $expectedMigrationOutput }
            throw "Unexpected health query: $Sql"
        }.GetNewClosure()

        $output = (& $healthScript -SettingsPath $settingsPath -QueryAction $queryAction | Out-String)

        $output | Should Match 'ReportingViews\s+: 16'
        $output | Should Match 'Status\s+: PASSED'
    }

    It 'rejects a replacement view even when the total remains 16' {
        $viewOutput = @($requiredViews | Where-Object { $_ -ne 'best_sellers_valid_category_day' }) + 'unexpected_replacement_view'
        $viewOutput = $viewOutput -join "`n"
        $expectedMigrationOutput = [string]$migrationCount
        $queryAction = {
            param([string]$Sql)

            if ($Sql -eq 'SHOW server_version;') { return '16.4' }
            if ($Sql -match 'information_schema\.tables') { return '20' }
            if ($Sql -match 'SELECT table_name FROM information_schema\.views') { return $viewOutput }
            if ($Sql -match 'source_definition') { return '3' }
            if ($Sql -match 'schema_migration') { return $expectedMigrationOutput }
            throw "Unexpected health query: $Sql"
        }.GetNewClosure()

        $caught = $null
        try {
            & $healthScript -SettingsPath $settingsPath -QueryAction $queryAction | Out-Null
        }
        catch {
            $caught = $_
        }

        $caught | Should Not BeNullOrEmpty
        $caught.Exception.Message | Should Match 'best_sellers_valid_category_day'
        $caught.Exception.Message | Should Match 'unexpected_replacement_view'
    }
}
