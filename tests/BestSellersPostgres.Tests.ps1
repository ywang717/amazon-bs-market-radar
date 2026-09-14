$modulePath = Join-Path $PSScriptRoot '..\src\BestSellersPostgres.psm1'
Import-Module $modulePath -Force

Describe 'Best Sellers metadata-only PostgreSQL import' {
    function New-MetadataRow {
        [pscustomobject]@{ marketplace_code='AMAZON_US'; asin='B000000001'; product_type='gas_pressure_washer'; classification_confidence='high'; classification_rule_id='machine-gas'; classification_rule_version='product-rules-v1'; classification_evidence=@('TITLE_RULE:machine-gas'); raw_brand='Westinghouse'; normalized_brand='Westinghouse'; normalized_brand_key='westinghouse'; brand_alias_rule_id='brand-westinghouse'; brand_source='verified_metadata'; first_seen_market_date='2026-08-01'; last_seen_market_date='2026-08-28' }
    }

    It 'creates a metadata-only transaction with exactly the metadata upsert boundary' {
        $sql = New-BestSellersMetadataImportSql -MetadataRows @(New-MetadataRow)

        $sql | Should Match 'upsert_best_sellers_product_metadata'
        $sql | Should Not Match 'ingest_best_sellers_snapshot|best_sellers_observation|best_sellers_source_run|receipt'
        $sql | Should Match 'BEGIN;'
        $sql | Should Match 'COMMIT;'
    }

    It 'returns without probing PostgreSQL when metadata is empty' {
        $settings = [pscustomobject]@{ install_root=$TestDrive; host='localhost'; port=5432; username='user'; database='db'; password='secret' }

        { Invoke-BestSellersMetadataPostgresImport -MetadataRows @() -PostgresSettings $settings } | Should Not Throw
    }

    It 'rejects conflicting duplicate brands before psql can run' {
        $settings = [pscustomobject]@{ install_root=$TestDrive; host='localhost'; port=5432; username='user'; database='db'; password='secret' }
        $one = New-MetadataRow
        $two = New-MetadataRow
        $two.raw_brand = 'Different Brand'; $two.normalized_brand = 'Different Brand'; $two.normalized_brand_key = 'different brand'

        $failure = $null
        try { Invoke-BestSellersMetadataPostgresImport -MetadataRows @($one, $two) -PostgresSettings $settings | Out-Null } catch { $failure = $_ }

        $failure | Should Not Be $null
        $failure.Exception.Message | Should Be 'Duplicate metadata import row for marketplace AMAZON_US and ASIN B000000001.'
    }

    It 'rejects duplicate unknown rows before psql can run' {
        $settings = [pscustomobject]@{ install_root=$TestDrive; host='localhost'; port=5432; username='user'; database='db'; password='secret' }
        $one = New-MetadataRow
        $one.raw_brand = $null; $one.normalized_brand = $null; $one.normalized_brand_key = $null; $one.brand_alias_rule_id = $null; $one.brand_source = 'unknown'
        $two = New-MetadataRow
        $two.raw_brand = $null; $two.normalized_brand = $null; $two.normalized_brand_key = $null; $two.brand_alias_rule_id = $null; $two.brand_source = 'unknown'

        $failure = $null
        try { Invoke-BestSellersMetadataPostgresImport -MetadataRows @($one, $two) -PostgresSettings $settings | Out-Null } catch { $failure = $_ }

        $failure | Should Not Be $null
        $failure.Exception.Message | Should Be 'Duplicate metadata import row for marketplace AMAZON_US and ASIN B000000001.'
    }

    It 'rejects duplicate trusted rows with the same normalized key before psql can run' {
        $settings = [pscustomobject]@{ install_root=$TestDrive; host='localhost'; port=5432; username='user'; database='db'; password='secret' }
        $one = New-MetadataRow
        $two = New-MetadataRow

        $failure = $null
        try { Invoke-BestSellersMetadataPostgresImport -MetadataRows @($one, $two) -PostgresSettings $settings | Out-Null } catch { $failure = $_ }

        $failure | Should Not Be $null
        $failure.Exception.Message | Should Be 'Duplicate metadata import row for marketplace AMAZON_US and ASIN B000000001.'
    }

    It 'rejects duplicate metadata rows on the snapshot import path too' {
        $artifactPath = Join-Path $TestDrive 'snapshot.json'
        $sourceConfigPath = Join-Path $TestDrive 'sources.json'
        [IO.File]::WriteAllText($artifactPath, '{"market_date":"2026-08-28","observed_at":"2026-08-28T00:00:00Z"}', (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($sourceConfigPath, '{"target_count":30,"sources":[{"active":true}]}', (New-Object Text.UTF8Encoding($false)))
        $one = New-MetadataRow
        $one.raw_brand = $null; $one.normalized_brand = $null; $one.normalized_brand_key = $null; $one.brand_alias_rule_id = $null; $one.brand_source = 'unknown'
        $two = New-MetadataRow
        $two.raw_brand = $null; $two.normalized_brand = $null; $two.normalized_brand_key = $null; $two.brand_alias_rule_id = $null; $two.brand_source = 'unknown'

        $failure = $null
        try { New-BestSellersImportSql -ArtifactPath $artifactPath -SourceConfigPath $sourceConfigPath -MetadataRows @($one, $two) | Out-Null } catch { $failure = $_ }

        $failure | Should Not Be $null
        $failure.Exception.Message | Should Be 'Duplicate metadata import row for marketplace AMAZON_US and ASIN B000000001.'
    }

    It 'rejects non-portable trusted raw and canonical brands before psql can run' {
        $settings = [pscustomobject]@{ install_root=$TestDrive; host='localhost'; port=5432; username='user'; database='db'; password='secret' }
        $rawInvalid = New-MetadataRow
        $rawInvalid.raw_brand = [string][char]0xFEFF + 'Brand'
        $canonicalInvalid = New-MetadataRow
        $canonicalInvalid.normalized_brand = [string][char]0x0130 + 'stanbul'

        $rawFailure = $null
        try { Invoke-BestSellersMetadataPostgresImport -MetadataRows @($rawInvalid) -PostgresSettings $settings | Out-Null } catch { $rawFailure = $_ }
        $rawFailure | Should Not Be $null
        $rawFailure.Exception.Message | Should Be 'Metadata import row B000000001 has non-portable raw_brand.'

        $canonicalFailure = $null
        try { Invoke-BestSellersMetadataPostgresImport -MetadataRows @($canonicalInvalid) -PostgresSettings $settings | Out-Null } catch { $canonicalFailure = $_ }
        $canonicalFailure | Should Not Be $null
        $canonicalFailure.Exception.Message | Should Be 'Metadata import row B000000001 has non-portable normalized_brand.'
    }

    It 'restores PostgreSQL environment variables when the database process fails' {
        $bin = Join-Path $TestDrive 'bin'
        New-Item -ItemType Directory -Path $bin -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\where.exe') -Destination (Join-Path $bin 'psql.exe')
        $settings = [pscustomobject]@{ install_root=$TestDrive; host='new-host'; port=5433; username='new-user'; database='new-db'; password='new-password' }
        $original = [Environment]::GetEnvironmentVariable('PGHOST', 'Process')
        [Environment]::SetEnvironmentVariable('PGHOST', 'before-import', 'Process')
        try {
            $failure = $null
            try { Invoke-BestSellersMetadataPostgresImport -MetadataRows @(New-MetadataRow) -PostgresSettings $settings | Out-Null } catch { $failure = $_ }
            $failure | Should Not Be $null
            $failure.Exception.Message | Should Be 'Best Sellers metadata PostgreSQL import failed with exit code 1'
            [Environment]::GetEnvironmentVariable('PGHOST', 'Process') | Should Be 'before-import'
        }
        finally {
            [Environment]::SetEnvironmentVariable('PGHOST', $original, 'Process')
        }
    }
}
