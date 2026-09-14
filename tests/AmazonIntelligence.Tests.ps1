$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src\AmazonIntelligence.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\CreatorsApiAdapter.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\PostgresOutbox.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\DailyCollection.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\DailyDatabasePipeline.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\DailyReport.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\MailDelivery.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\PublicIntelligence.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\PublicIntelligencePostgres.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersAnalysis.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersDailyReport.psm1') -Force

Describe 'Windows PowerShell report compatibility' {
    It 'loads the daily report module without UTF-8 parser errors' {
        $windowsPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) { return }
        $module = (Resolve-Path -LiteralPath (Join-Path $projectRoot 'src\BestSellersDailyReport.psm1')).Path
        $script = "Import-Module '$module' -Force; Get-Command New-BestSellersDailyReport -ErrorAction Stop | Out-Null"
        @(& $windowsPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $script 2>&1) | Out-Null
        $LASTEXITCODE | Should Be 0
    }
}
Import-Module (Join-Path $projectRoot 'src\BestSellersCaptureReceipt.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersPostgres.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersWeeklyAnalysis.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersOpportunityAnalysis.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersOpportunityPostgres.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersMarketStructure.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersMarketStructurePostgres.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersRankInfluence.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersRankInfluencePostgres.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersAnalysisReadiness.psm1') -Force
Describe 'Category-independent configuration' {
    It 'keeps analysis exports available after the capture receipt module is loaded' {
        Get-Command Test-BestSellersTop50Snapshot -ErrorAction SilentlyContinue | Should Not Be $null
        Get-Command Compare-BestSellersSnapshots -ErrorAction SilentlyContinue | Should Not Be $null
    }

    It 'contains three root categories and seven accessory categories' {
        $config = Get-Content (Join-Path $projectRoot 'config\categories.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        @($config.categories | Where-Object { $_.level -eq 1 }).Count | Should Be 3
        @($config.categories | Where-Object { $_.parent -eq 'pressure-washer-accessories' }).Count | Should Be 7
    }

    It 'defines three verified Amazon Best Sellers nodes' {
        $config = Get-Content (Join-Path $projectRoot 'config\best-sellers-sources.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        @($config.sources | Where-Object { $_.active }).Count | Should Be 3
        @($config.sources.amazon_node_id) -contains '552856' | Should Be $true
        @($config.sources.amazon_node_id) -contains '680335011' | Should Be $true
        @($config.sources.amazon_node_id) -contains '3023451' | Should Be $true
        $config.target_count | Should Be 30
        $config.page_loading.top_30_rule | Should Be 'collect_only_verified_global_ranks_1_through_30'
    }

    It 'documents the independent Top 30 browser collection and safe pagination rule' {
        $protocol = Get-Content (Join-Path $projectRoot 'docs\phase-3\BEST-SELLERS-BROWSER-COLLECTION-PROTOCOL.md') -Raw -Encoding UTF8
        $protocol | Should Match '552856'
        $protocol | Should Match '680335011'
        $protocol | Should Match '3023451'
        $protocol | Should Match 'PAGINATION_MUST_PRESERVE_GLOBAL_RANKS'
        $protocol | Should Match 'Test-BestSellersTop50Snapshot'
    }
}

Describe 'Phase 7 maintenance runbook' {
    It 'documents COMPLETE-only publication, discount unknowns, receipt-gated import, and no-email reports' {
        $runbook = Get-Content (Join-Path $projectRoot 'docs\phase-7\MAINTENANCE-RUNBOOK.md') -Raw -Encoding UTF8
        $decodeUtf8Pattern = { param([string]$Value) [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value)) }
        $completeOnlyPattern = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('57K+56Gu55qEIGBDT01QTEVURWA='))
        $top30Pattern = & $decodeUtf8Pattern '5o6S5ZCNIDHigJMzMA=='
        $discountUnknownPattern = & $decodeUtf8Pattern '5pyq55+l54q25oCB5LiN5piv4oCc5peg5LyY5oOg4oCd'
        $skipEmailPattern = & $decodeUtf8Pattern '5b+F6aG75pi+5byP5Lyg5YWlIGAtU2tpcEVtYWlsYA=='
        # WinPS 5.1 parses UTF-8 no-BOM source through the active ANSI code page, corrupting inline Chinese literals.
        $legacySourcePattern = [Text.Encoding]::Default.GetString([Convert]::FromBase64String('57K+56Gu55qEIGBDT01QTEVURWA='))

        if ($legacySourcePattern -cne $completeOnlyPattern) {
            $legacySourcePattern | Should Not Be $completeOnlyPattern
            $runbook | Should Not Match ([regex]::Escape($legacySourcePattern))
        }
        $runbook | Should Match ([regex]::Escape($completeOnlyPattern))
        $runbook | Should Match ([regex]::Escape($top30Pattern))
        $runbook | Should Match ([regex]::Escape($discountUnknownPattern))
        $runbook | Should Match 'Test-BestSellersCaptureReceipt\.ps1'
        $runbook | Should Match 'Import-VerifiedBestSellersSnapshot\.ps1'
        $runbook | Should Match ([regex]::Escape($skipEmailPattern))
        $runbook | Should Match 'SKIPPED_BY_REQUEST'
    }
}

Describe 'Fixture collector' {
    It 'normalizes a complete valid fixture' {
        $result = Invoke-FixtureCollection -Path (Join-Path $PSScriptRoot 'fixtures\valid-pressure-washer.json')
        $result.Stats.RawCount | Should Be 3
        $result.Stats.AcceptedCount | Should Be 3
        $result.Stats.RejectedCount | Should Be 0
        $result.Stats.CompletenessPercent | Should Be 100
        $result.Accepted[0].schema_version | Should Be 'canonical-observation-v1'
        $result.Accepted[0].asin | Should Be 'B0ABC12345'
        $result.Accepted[0].record_key.Length | Should Be 64
    }

    It 'rejects invalid ASIN, rank, rating and review count with evidence' {
        $result = Invoke-FixtureCollection -Path (Join-Path $PSScriptRoot 'fixtures\invalid-observations.json')
        $result.Stats.AcceptedCount | Should Be 1
        $result.Stats.RejectedCount | Should Be 2
        (@($result.Rejected[0].errors) -contains 'INVALID_ASIN') | Should Be $true
        (@($result.Rejected[1].errors) -contains 'RANK_EXCEEDS_TARGET') | Should Be $true
        (@($result.Rejected[1].errors) -contains 'INVALID_RATING') | Should Be $true
        (@($result.Rejected[1].errors) -contains 'INVALID_REVIEW_COUNT') | Should Be $true
    }

    It 'writes staging records idempotently' {
        $result = Invoke-FixtureCollection -Path (Join-Path $PSScriptRoot 'fixtures\valid-pressure-washer.json')
        $path = Join-Path $TestDrive 'observations.jsonl'
        (Add-ObservationStaging -Observations $result.Accepted -Path $path) | Should Be 3
        (Add-ObservationStaging -Observations $result.Accepted -Path $path) | Should Be 0
        @(Get-Content -LiteralPath $path).Count | Should Be 3
    }

    It 'detects duplicate business records inside one run' {
        $result = Invoke-FixtureCollection -Path (Join-Path $PSScriptRoot 'fixtures\duplicate-observations.json')
        $result.Stats.AcceptedCount | Should Be 1
        $result.Stats.DuplicateCount | Should Be 1
        $result.Stats.DuplicatePercent | Should Be 50
        (@($result.Rejected[0].errors) -contains 'DUPLICATE_RECORD_KEY') | Should Be $true
    }
}

Describe 'Collection pipeline' {
    It 'preserves raw data and publishes a passed run to staging and outbox' {
        $work = Join-Path $TestDrive 'passed'
        $first = Invoke-CollectionPipeline -FixturePath (Join-Path $PSScriptRoot 'fixtures\valid-pressure-washer.json') -WorkRoot $work
        $first.Status | Should Be 'SUCCEEDED'
        $first.QualityGate.Passed | Should Be $true
        $first.NewlyStaged | Should Be 3
        (Test-Path -LiteralPath $first.RawArtifactPath) | Should Be $true
        (Test-Path -LiteralPath $first.ManifestPath) | Should Be $true
        (Test-Path -LiteralPath $first.OutboxPath) | Should Be $true

        $second = Invoke-CollectionPipeline -FixturePath (Join-Path $PSScriptRoot 'fixtures\valid-pressure-washer.json') -WorkRoot $work
        $second.NewlyStaged | Should Be 0
        @(Get-Content -LiteralPath $second.StagingPath).Count | Should Be 3
    }

    It 'quarantines a failed run while retaining raw data and audit manifest' {
        $work = Join-Path $TestDrive 'quarantined'
        $result = Invoke-CollectionPipeline -FixturePath (Join-Path $PSScriptRoot 'fixtures\invalid-observations.json') -WorkRoot $work
        $result.Status | Should Be 'QUARANTINED'
        $result.QualityGate.Passed | Should Be $false
        (Test-Path -LiteralPath $result.RawArtifactPath) | Should Be $true
        (Test-Path -LiteralPath $result.ManifestPath) | Should Be $true
        ($null -eq $result.OutboxPath) | Should Be $true
        ($null -eq $result.StagingPath) | Should Be $true
    }
}

Describe 'Official Creators API adapter' {
    BeforeEach {
        $sources = Get-Content (Join-Path $projectRoot 'config\sources.example.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:searchSource = @($sources.sources | Where-Object { $_.category_slug -eq 'pressure-washer' })[0]
    }

    It 'plans exactly five official SearchItems calls for Top 50' {
        $plan = @(New-CreatorsApiSearchPlan -Source $script:searchSource -PartnerTag 'example-20')
        $plan.Count | Should Be 5
        $plan[0].Uri | Should Be 'https://creatorsapi.amazon/catalog/v1/searchItems'
        $plan[0].Payload.itemCount | Should Be 10
        $plan[4].Payload.itemPage | Should Be 5
        $plan[0].Payload.searchIndex | Should Be 'GardenAndOutdoor'
    }

    It 'validates all three established local sources' {
        $local = Get-Content (Join-Path $projectRoot 'config\sources.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        @($local.sources).Count | Should Be 3
        foreach ($source in @($local.sources)) {
            $validation = Test-CreatorsApiSourceConfiguration -Source $source
            $validation.IsValid | Should Be $true
            $source.active | Should Be $true
            $source.review_status | Should Be 'APPROVED_SEARCH_ONLY'
        }
    }

    It 'uses the official OAuth client credentials token contract without logging secrets' {
        $script:capturedTokenRequest = $null
        $transport = {
            param($request)
            $script:capturedTokenRequest = $request
            return [pscustomobject]@{ access_token = 'test-token'; expires_in = 3600; token_type = 'bearer' }
        }
        $token = Get-CreatorsApiAccessToken -Credentials ([pscustomobject]@{
            ClientId = 'test-client'; ClientSecret = 'test-secret'; PartnerTag = 'example-20'
        }) -Transport $transport
        $script:capturedTokenRequest.Uri | Should Be 'https://api.amazon.com/auth/o2/token'
        $script:capturedTokenRequest.Body.grant_type | Should Be 'client_credentials'
        $script:capturedTokenRequest.Body.scope | Should Be 'creatorsapi::default'
        $token.AccessToken | Should Be 'test-token'
        $token.ExpiresIn | Should Be 3600
    }

    It 'adds bearer authentication and the US marketplace header' {
        $request = @(New-CreatorsApiSearchPlan -Source $script:searchSource -PartnerTag 'example-20')[0]
        $transport = {
            param($wireRequest)
            $wireRequest.Headers.Authorization | Should Be 'Bearer offline-token'
            $wireRequest.Headers.'x-marketplace' | Should Be 'www.amazon.com'
            return [pscustomobject]@{ searchResult = [pscustomobject]@{ items = @() } }
        }
        $response = Invoke-CreatorsApiRequest -Request $request -AccessToken 'offline-token' -Transport $transport
        @($response.searchResult.items).Count | Should Be 0
    }

    It 'retries throttled requests with bounded exponential backoff' {
        $request = @(New-CreatorsApiSearchPlan -Source $script:searchSource -PartnerTag 'example-20')[0]
        $script:attempts = 0
        $script:delays = @()
        $transport = {
            param($wireRequest)
            $script:attempts++
            if ($script:attempts -lt 3) {
                $exception = New-Object System.Exception('throttled')
                $exception.Data['StatusCode'] = 429
                throw $exception
            }
            return [pscustomobject]@{ searchResult = [pscustomobject]@{ items = @() } }
        }
        $sleep = { param($milliseconds) $script:delays += $milliseconds }
        $null = Invoke-CreatorsApiRequest -Request $request -AccessToken 'offline-token' -Transport $transport `
            -MaxAttempts 3 -BaseDelayMilliseconds 100 -SleepAction $sleep
        $script:attempts | Should Be 3
        $script:delays.Count | Should Be 2
        $script:delays[0] | Should Be 100
        $script:delays[1] | Should Be 200
    }

    It 'maps an official-style response into canonical observations' {
        $response = Get-Content (Join-Path $PSScriptRoot 'fixtures\creators-api-search-response.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $result = ConvertFrom-CreatorsApiSearchResponse -Response $response -Source $script:searchSource `
            -RunId '44444444-4444-4444-8444-444444444444' -MarketDate '2026-08-03' `
            -ObservedAt '2026-08-03T16:00:00Z' -ItemPage 2 -ExpectedCount 50
        $result.Stats.AcceptedCount | Should Be 2
        $result.Stats.RejectedCount | Should Be 0
        $result.Accepted[0].rank | Should Be 11
        $result.Accepted[0].asin | Should Be 'B0AAA00001'
        $result.Accepted[0].price | Should Be 139.99
        $result.Accepted[0].seller_raw | Should Be 'Amazon.com'
        $result.Accepted[0].fba_status | Should Be 'UNKNOWN'
    }

    It 'runs an offline five-page Top 50 collection without persisting credentials' {
        $activeSource = $script:searchSource | Select-Object *
        $activeSource.active = $true
        $activeSource.review_status = 'APPROVED_SEARCH_ONLY'
        $script:apiCalls = 0
        $tokenTransport = {
            param($request)
            return [pscustomobject]@{ access_token = 'offline-token'; expires_in = 3600; token_type = 'bearer' }
        }
        $apiTransport = {
            param($request)
            $script:apiCalls++
            $page = [int]$request.Body.itemPage
            $items = @()
            for ($offset = 1; $offset -le 10; $offset++) {
                $number = (($page - 1) * 10) + $offset
                $asin = 'B0T' + $number.ToString('0000000')
                $items += [pscustomobject]@{
                    asin = $asin
                    detailPageURL = "https://www.amazon.com/dp/$asin?tag=example-20"
                    itemInfo = [pscustomobject]@{
                        title = [pscustomobject]@{ displayValue = "Offline Product $number" }
                        byLineInfo = [pscustomobject]@{ brand = [pscustomobject]@{ displayValue = 'OfflineBrand' } }
                    }
                    offersV2 = [pscustomobject]@{
                        listings = @([pscustomobject]@{
                            isBuyBoxWinner = $true
                            merchantInfo = [pscustomobject]@{ name = 'Offline Seller' }
                            price = [pscustomobject]@{ money = [pscustomobject]@{ amount = (100 + $number); currency = 'USD' } }
                        })
                    }
                }
            }
            return [pscustomobject]@{ searchResult = [pscustomobject]@{ items = $items; totalResultCount = 500 } }
        }
        $work = Join-Path $TestDrive 'creators-top50'
        $result = Invoke-CreatorsApiSearchRun -Source $activeSource -MarketDate '2026-08-03' -WorkRoot $work `
            -RunId '55555555-5555-4555-8555-555555555555' -ObservedAt '2026-08-03T16:00:00Z' `
            -Credentials ([pscustomobject]@{ ClientId = 'test-client'; ClientSecret = 'test-secret'; PartnerTag = 'example-20' }) `
            -TokenTransport $tokenTransport -ApiTransport $apiTransport -SleepAction { param($milliseconds) }

        $result.Status | Should Be 'SUCCEEDED'
        $result.PageCount | Should Be 5
        $result.Stats.AcceptedCount | Should Be 50
        $result.Stats.CompletenessPercent | Should Be 100
        @($result.RawArtifactPaths).Count | Should Be 5
        $script:apiCalls | Should Be 5
        @(Get-Content -LiteralPath $result.StagingPath).Count | Should Be 50
        $persisted = (Get-Content -LiteralPath $result.ManifestPath -Raw) + (Get-Content -LiteralPath $result.OutboxPath -Raw)
        $persisted | Should Not Match 'offline-token'
        $persisted | Should Not Match 'test-secret'

        $sql = New-PostgresOutboxSql -OutboxPath $result.OutboxPath
        $sql | Should Match '^BEGIN;'
        $sql | Should Match 'SELECT start_collection_run'
        ([regex]::Matches($sql, 'SELECT ingest_canonical_observation').Count) | Should Be 50
        $sql | Should Match 'SELECT finish_collection_run'
        $sql | Should Match 'COMMIT;'
        $sql | Should Not Match 'offline-token'
        $sql | Should Not Match 'test-secret'
    }
}

Describe 'PostgreSQL migrations' {
    It 'defines core facts, metrics, signals and constraints' {
        $sql = Get-Content (Join-Path $projectRoot 'db\migrations\001_initial_schema.sql') -Raw -Encoding UTF8
        $sql | Should Match 'CREATE TABLE ranking_observation'
        $sql | Should Match 'CREATE TABLE offer_snapshot'
        $sql | Should Match 'CREATE TABLE listing_snapshot'
        $sql | Should Match 'CREATE TABLE listing_content_snapshot'
        $sql | Should Match 'CREATE TABLE review_snapshot'
        $sql | Should Match 'CREATE TABLE detection_signal'
        $sql | Should Match 'CREATE TABLE opportunity_score'
        $sql | Should Match 'record_key char\(64\) NOT NULL UNIQUE'
    }

    It 'defines all five required reporting views' {
        $sql = Get-Content (Join-Path $projectRoot 'db\migrations\002_reporting_views.sql') -Raw -Encoding UTF8
        foreach ($view in @('daily_ranking', 'new_product_entry', 'new_brand_tracker', 'rising_products', 'trend_analysis')) {
            $sql | Should Match ("CREATE VIEW {0}" -f $view)
        }
    }

    It 'defines a transaction-oriented ingestion API' {
        $sql = Get-Content (Join-Path $projectRoot 'db\migrations\004_ingestion_api.sql') -Raw -Encoding UTF8
        $sql | Should Match 'CREATE FUNCTION start_collection_run'
        $sql | Should Match 'CREATE FUNCTION ingest_canonical_observation'
        $sql | Should Match 'CREATE FUNCTION finish_collection_run'
        $sql | Should Match 'Unsupported observation schema version'
    }

    It 'defines append-preserving public intelligence history and ingestion' {
        $sql = Get-Content (Join-Path $projectRoot 'db\migrations\006_public_intelligence_history.sql') -Raw -Encoding UTF8
        $sql | Should Match 'CREATE TABLE public_intelligence_run'
        $sql | Should Match 'CREATE TABLE public_safety_notice'
        $sql | Should Match 'CREATE TABLE public_safety_notice_observation'
        $sql | Should Match 'CREATE VIEW public_safety_current'
        $sql | Should Match 'CREATE VIEW public_safety_daily_change'
        $sql | Should Match 'CREATE FUNCTION ingest_public_intelligence'
        $sql | Should Match 'ON CONFLICT \(public_run_id, public_notice_id, content_hash\) DO NOTHING'
    }

    It 'defines append-preserving Best Sellers history, daily changes and exits' {
        $sql = Get-Content (Join-Path $projectRoot 'db\migrations\007_best_sellers_history.sql') -Raw -Encoding UTF8
        $sql | Should Match 'CREATE TABLE best_sellers_run'
        $sql | Should Match 'artifact_sha256 char\(64\) NOT NULL UNIQUE'
        $sql | Should Match 'CREATE TABLE best_sellers_observation'
        $sql | Should Match 'CREATE FUNCTION ingest_best_sellers_snapshot'
        $sql | Should Match 'CREATE VIEW best_sellers_daily_change'
        $sql | Should Match 'CREATE VIEW best_sellers_daily_exit'
    }

    It 'stores structured true false and unknown discount states' {
        $sql = Get-Content (Join-Path $projectRoot 'db\migrations\011_best_sellers_discount_history.sql') -Raw -Encoding UTF8

        $sql | Should Match 'ADD COLUMN has_discount boolean'
        $sql | Should Match "ADD COLUMN discounts jsonb NOT NULL DEFAULT '\[\]'::jsonb"
        $sql | Should Match 'CHECK \(jsonb_typeof\(discounts\) = ''array''\)'
        $sql | Should Match 'CREATE OR REPLACE FUNCTION ingest_best_sellers_snapshot'
        $sql | Should Match "NULLIF\(v_item->>'has_discount', ''\)::boolean"
        $sql | Should Match "COALESCE\(v_item->'discounts', '\[\]'::jsonb\)"
        $sql | Should Match "jsonb_typeof\(v_item->'discounts'\) <> 'array'"
        $sql | Should Match "COALESCE\(discount->>'kind', ''\) NOT IN \('COUPON', 'PRICE_DROP', 'PRIME_EXCLUSIVE'\)"
        $sql | Should Match "btrim\(COALESCE\(discount->>'amount', ''\)\) = ''"
        $sql | Should Match 'CREATE OR REPLACE VIEW best_sellers_daily_current'
        $sql | Should Match 'o.has_discount, o.discounts'
        $sql | Should Match 'CREATE OR REPLACE VIEW best_sellers_daily_change'
    }

    It 'defines product metadata and exact valid category days without rewriting observations' {
        $migration = Get-Content (Join-Path $projectRoot 'db\migrations\012_best_sellers_product_metadata.sql') -Raw -Encoding UTF8

        $migration | Should Match 'CREATE TABLE best_sellers_product_metadata'
        $migration | Should Match 'PRIMARY KEY \(marketplace_code, asin\)'
        $migration | Should Match 'CREATE VIEW best_sellers_valid_category_day'
        $migration | Should Match 'quality_passed'
        $migration | Should Match 'count\(\*\) = 30'
        $migration | Should Match 'count\(DISTINCT o\.rank\) = 30'
        $migration | Should Match 'count\(DISTINCT o\.asin\) = 30'
        $migration | Should Match 'min\(o\.rank\) = 1'
        $migration | Should Match 'max\(o\.rank\) = 30'
        $migration | Should Match 'CREATE FUNCTION upsert_best_sellers_product_metadata'
    }

    It 'preserves higher-quality classifications and verified brands during metadata upserts' {
        $migration = Get-Content (Join-Path $projectRoot 'db\migrations\012_best_sellers_product_metadata.sql') -Raw -Encoding UTF8

        $migration | Should Match "WHEN EXCLUDED\.classification_confidence = 'high' AND \(best_sellers_product_metadata\.classification_confidence <> 'high' OR EXCLUDED\.classification_rule_version > best_sellers_product_metadata\.classification_rule_version\) THEN EXCLUDED\.product_type"
        $migration | Should Match "WHEN EXCLUDED\.classification_confidence = 'medium' AND \(best_sellers_product_metadata\.classification_confidence = 'low' OR \(best_sellers_product_metadata\.classification_confidence = 'medium' AND EXCLUDED\.classification_rule_version > best_sellers_product_metadata\.classification_rule_version\)\) THEN EXCLUDED\.product_type"
        $migration | Should Match "ELSE best_sellers_product_metadata\.product_type"
        $migration | Should Match "WHEN EXCLUDED\.brand_source IN \('verified_metadata', 'manual_review'\) THEN EXCLUDED\.raw_brand"
        $migration | Should Match "ELSE best_sellers_product_metadata\.raw_brand"
        $migration | Should Match 'LEAST\(best_sellers_product_metadata\.first_seen_market_date, EXCLUDED\.first_seen_market_date\)'
        $migration | Should Match 'GREATEST\(best_sellers_product_metadata\.last_seen_market_date, EXCLUDED\.last_seen_market_date\)'
    }

    It 'requires every unknown-brand field to be null, including its alias rule' {
        $migration = Get-Content (Join-Path $projectRoot 'db\migrations\012_best_sellers_product_metadata.sql') -Raw -Encoding UTF8

        $migration | Should Match "brand_source = 'unknown' AND raw_brand IS NULL AND normalized_brand IS NULL AND normalized_brand_key IS NULL AND brand_alias_rule_id IS NULL"
    }

    It 'constrains product types classification shapes and non-empty evidence in migration 012' {
        $migration = Get-Content (Join-Path $projectRoot 'db\migrations\012_best_sellers_product_metadata.sql') -Raw -Encoding UTF8

        foreach ($productType in @(
            'electric_pressure_washer', 'gas_pressure_washer', 'cordless_pressure_washer',
            'surface_cleaner', 'pressure_washer_gun', 'hose', 'nozzle',
            'chemical_cleaner', 'pump_protector', 'other_accessory', 'unknown'
        )) {
            $migration | Should Match ([regex]::Escape("'$productType'"))
        }
        $migration | Should Match '(?s)CHECK \(product_type IN \('
        $migration | Should Match "(?s)product_type = 'unknown'.*classification_confidence = 'low'.*classification_rule_id IS NULL"
        $migration | Should Match "(?s)product_type <> 'unknown'.*classification_confidence IN \('medium', 'high'\).*classification_rule_id IS NOT NULL.*btrim\(classification_rule_id\) <> ''"
        $migration | Should Match "(?s)jsonb_typeof\(classification_evidence\) = 'array'.*jsonb_array_length\(classification_evidence\) > 0"
    }

    It 'keeps migration 012 dynamic constraint probes rollback-only and outside the default Pester run' {
        $testSql = Join-Path $projectRoot 'tests\postgres\012_best_sellers_product_metadata.sql'
        $probe = Get-Content -LiteralPath $testSql -Raw -Encoding UTF8
        $runner = Join-Path $projectRoot 'scripts\postgres\Test-BestSellersProductMetadataConstraints.ps1'
        $previousDatabaseUrl = [Environment]::GetEnvironmentVariable('AMAZON_INTELLIGENCE_DISPOSABLE_TEST_DATABASE_URL', 'Process')
        try {
            [Environment]::SetEnvironmentVariable('AMAZON_INTELLIGENCE_DISPOSABLE_TEST_DATABASE_URL', $null, 'Process')
            $result = & $runner

            $probe | Should Match '(?m)^BEGIN;'
            $probe | Should Match '(?m)^ROLLBACK;'
            $probe | Should Match 'known product type with low confidence was accepted'
            $probe | Should Match 'unsupported product type was accepted'
            $probe | Should Match 'empty classification evidence was accepted'
            $result.Status | Should Be 'INCONCLUSIVE'
            $result.Reason | Should Match 'AMAZON_INTELLIGENCE_DISPOSABLE_TEST_DATABASE_URL'

            [Environment]::SetEnvironmentVariable('AMAZON_INTELLIGENCE_DISPOSABLE_TEST_DATABASE_URL', 'postgresql://not-a-real-host/disposable', 'Process')
            { & $runner | Out-Null } | Should Throw 'RunAgainstDisposableDatabase'
        }
        finally {
            [Environment]::SetEnvironmentVariable('AMAZON_INTELLIGENCE_DISPOSABLE_TEST_DATABASE_URL', $previousDatabaseUrl, 'Process')
        }
    }

    It 'seeds the three approved Search sources' {
        $sql = Get-Content (Join-Path $projectRoot 'db\migrations\005_seed_search_sources.sql') -Raw -Encoding UTF8
        ([regex]::Matches($sql, "CREATORS_API").Count -ge 1) | Should Be $true
        $sql | Should Match 'pressure-washer'
        $sql | Should Match 'sump-pump'
        $sql | Should Match 'pressure-washer-accessories'
    }
}

Describe 'Local PostgreSQL migration runner' {
    It 'counts scalar psql lookup results safely under strict mode' {
        $migrationRunner = Get-Content (Join-Path $projectRoot 'scripts\postgres\Invoke-LocalMigrations.ps1') -Raw
        $migrationRunner | Should Match '@\(\$databaseLookup \| Where-Object'
        $migrationRunner | Should Match '@\(\$migrationLookup \| Where-Object'
    }
}

Describe 'Daily three-category orchestration' {
    BeforeEach {
        $script:dailyConfig = Get-Content (Join-Path $projectRoot 'config\sources.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    It 'creates a successful daily summary for all three sources' {
        $runner = {
            param($source, $marketDate, $sourceRoot, $credentials)
            return [pscustomobject]@{
                Status = 'SUCCEEDED'
                RunId = [guid]::NewGuid().ToString()
                Stats = [pscustomobject]@{ AcceptedCount = 50; RejectedCount = 0; CompletenessPercent = 100 }
                ManifestPath = Join-Path $sourceRoot 'run.json'
                OutboxPath = Join-Path $sourceRoot 'outbox.json'
            }
        }
        $result = Invoke-DailySearchCollection -Config $script:dailyConfig -MarketDate '2026-08-03' `
            -WorkRoot (Join-Path $TestDrive 'daily-success') -SourceRunner $runner
        $result.Status | Should Be 'SUCCEEDED'
        $result.SourceCount | Should Be 3
        $result.SucceededCount | Should Be 3
        $result.FailedCount | Should Be 0
        (Test-Path -LiteralPath $result.ManifestPath) | Should Be $true
    }

    It 'isolates one source failure and continues remaining sources' {
        $script:runnerCalls = 0
        $credentials = [pscustomobject]@{ ClientId = 'safe-client'; ClientSecret = 'sensitive-value'; PartnerTag = 'safe-tag' }
        $runner = {
            param($source, $marketDate, $sourceRoot, $receivedCredentials)
            $script:runnerCalls++
            if ($source.category_slug -eq 'sump-pump') { throw "provider failed with sensitive-value and Bearer abc.def" }
            return [pscustomobject]@{
                Status = 'SUCCEEDED'; RunId = [guid]::NewGuid().ToString()
                Stats = [pscustomobject]@{ AcceptedCount = 50; RejectedCount = 0; CompletenessPercent = 100 }
                ManifestPath = 'run.json'; OutboxPath = 'outbox.json'
            }
        }
        $result = Invoke-DailySearchCollection -Config $script:dailyConfig -MarketDate '2026-08-03' `
            -WorkRoot (Join-Path $TestDrive 'daily-partial') -Credentials $credentials -SourceRunner $runner
        $result.Status | Should Be 'PARTIAL'
        $result.SucceededCount | Should Be 2
        $result.FailedCount | Should Be 1
        $script:runnerCalls | Should Be 3
        $manifest = Get-Content -LiteralPath $result.ManifestPath -Raw
        $manifest | Should Not Match 'sensitive-value'
        $manifest | Should Not Match 'Bearer abc.def'
        $manifest | Should Match '\[REDACTED\]'
    }

    It 'rejects more than six active sources before execution' {
        $template = @($script:dailyConfig.sources)[0]
        $sources = @()
        for ($i = 1; $i -le 7; $i++) {
            $copy = $template | Select-Object *
            $copy.source_id = [guid]::NewGuid().ToString()
            $sources += $copy
        }
        $config = [pscustomobject]@{ sources = $sources }
        $errorMessage = $null
        try {
            Invoke-DailySearchCollection -Config $config -MarketDate '2026-08-03' -WorkRoot (Join-Path $TestDrive 'too-many') -SourceRunner { } | Out-Null
        }
        catch {
            $errorMessage = $_.Exception.Message
        }
        $errorMessage | Should Match 'Active source count exceeds the project maximum of 6'
    }
}

Describe 'Daily collection to PostgreSQL pipeline' {
    BeforeEach {
        $script:pipelineConfig = Get-Content (Join-Path $projectRoot 'config\sources.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:postgresSettings = [pscustomobject]@{
            install_root = 'C:\offline-postgres'
            host = '127.0.0.1'
            port = 55432
            username = 'postgres'
            database = 'amazon_us_intelligence'
            password = 'database-sensitive-value'
        }
    }

    It 'imports all successful source outboxes and writes a daily database summary' {
        $script:importCalls = 0
        $collector = {
            param($config, $marketDate, $workRoot, $credentials)
            $results = @()
            foreach ($source in $config.sources) {
                $directory = Join-Path $workRoot $source.category_slug
                New-Item -ItemType Directory -Path $directory -Force | Out-Null
                $outbox = Join-Path $directory 'outbox.json'
                [System.IO.File]::WriteAllText($outbox, '{}')
                $results += [pscustomobject]@{
                    source_id = $source.source_id; category_slug = $source.category_slug
                    status = 'SUCCEEDED'; run_id = [guid]::NewGuid().ToString()
                    outbox_path = $outbox; error_code = $null; error_message = $null
                }
            }
            return [pscustomobject]@{ Results = $results; ManifestPath = (Join-Path $workRoot 'collection-summary.json') }
        }
        $importer = { param($outboxPath, $runId, $settings) $script:importCalls++ }
        $result = Invoke-DailyCollectionDatabasePipeline -Config $script:pipelineConfig -MarketDate '2026-08-03' `
            -WorkRoot (Join-Path $TestDrive 'db-all-success') -PostgresSettings $script:postgresSettings `
            -DailyCollector $collector -OutboxImporter $importer
        $result.Status | Should Be 'SUCCEEDED'
        $result.ImportedCount | Should Be 3
        $result.ImportFailedCount | Should Be 0
        $script:importCalls | Should Be 3
        (Test-Path -LiteralPath $result.ManifestPath) | Should Be $true
    }

    It 'imports successful collections while skipping a failed collection' {
        $script:importCalls = 0
        $collector = {
            param($config, $marketDate, $workRoot, $credentials)
            $results = @()
            foreach ($source in $config.sources) {
                if ($source.category_slug -eq 'sump-pump') {
                    $results += [pscustomobject]@{
                        source_id = $source.source_id; category_slug = $source.category_slug
                        status = 'FAILED'; run_id = $null; outbox_path = $null
                        error_code = 'SOURCE_RUN_FAILED'; error_message = 'offline failure'
                    }
                } else {
                    $directory = Join-Path $workRoot $source.category_slug
                    New-Item -ItemType Directory -Path $directory -Force | Out-Null
                    $outbox = Join-Path $directory 'outbox.json'
                    [System.IO.File]::WriteAllText($outbox, '{}')
                    $results += [pscustomobject]@{
                        source_id = $source.source_id; category_slug = $source.category_slug
                        status = 'SUCCEEDED'; run_id = [guid]::NewGuid().ToString(); outbox_path = $outbox
                        error_code = $null; error_message = $null
                    }
                }
            }
            return [pscustomobject]@{ Results = $results; ManifestPath = 'collection-summary.json' }
        }
        $importer = { param($outboxPath, $runId, $settings) $script:importCalls++ }
        $result = Invoke-DailyCollectionDatabasePipeline -Config $script:pipelineConfig -MarketDate '2026-08-03' `
            -WorkRoot (Join-Path $TestDrive 'db-collection-partial') -PostgresSettings $script:postgresSettings `
            -DailyCollector $collector -OutboxImporter $importer
        $result.Status | Should Be 'PARTIAL'
        $result.ImportedCount | Should Be 2
        $result.CollectionFailedCount | Should Be 1
        $script:importCalls | Should Be 2
    }

    It 'retains a failed database outbox for retry and redacts the database password' {
        $collector = {
            param($config, $marketDate, $workRoot, $credentials)
            $results = @()
            foreach ($source in $config.sources) {
                $directory = Join-Path $workRoot $source.category_slug
                New-Item -ItemType Directory -Path $directory -Force | Out-Null
                $outbox = Join-Path $directory 'outbox.json'
                [System.IO.File]::WriteAllText($outbox, '{}')
                $results += [pscustomobject]@{
                    source_id = $source.source_id; category_slug = $source.category_slug
                    status = 'SUCCEEDED'; run_id = [guid]::NewGuid().ToString(); outbox_path = $outbox
                    error_code = $null; error_message = $null
                }
            }
            return [pscustomobject]@{ Results = $results; ManifestPath = 'collection-summary.json' }
        }
        $importer = {
            param($outboxPath, $runId, $settings)
            if ($outboxPath -match 'sump-pump') { throw 'database-sensitive-value import failure' }
        }
        $result = Invoke-DailyCollectionDatabasePipeline -Config $script:pipelineConfig -MarketDate '2026-08-03' `
            -WorkRoot (Join-Path $TestDrive 'db-import-partial') -PostgresSettings $script:postgresSettings `
            -DailyCollector $collector -OutboxImporter $importer
        $result.Status | Should Be 'PARTIAL'
        $result.ImportedCount | Should Be 2
        $result.ImportFailedCount | Should Be 1
        $failed = @($result.Results | Where-Object { $_.database_status -eq 'IMPORT_FAILED_RETRYABLE' })[0]
        (Test-Path -LiteralPath $failed.outbox_path) | Should Be $true
        $manifest = Get-Content -LiteralPath $result.ManifestPath -Raw
        $manifest | Should Not Match 'database-sensitive-value'
        $manifest | Should Match '\[REDACTED\]'
    }
}

Describe 'Daily report generation and email delivery' {
    BeforeEach {
        $script:reportPostgresSettings = [pscustomobject]@{
            install_root = 'C:\offline-postgres'; host = '127.0.0.1'; port = 55432
            username = 'postgres'; database = 'amazon_us_intelligence'; password = 'report-database-secret'
        }
        $script:reportDataProvider = {
            param($marketDate, $settings)
            return [pscustomobject]@{
                rankings = @([pscustomobject]@{
                    category_level_1 = 'Pressure Washer'; category_level_2 = $null; accessory_type = $null
                    rank = 1; previous_rank = 3; rank_change = 2; brand = 'Example Brand'; model = 'PW-1'
                    asin = 'B0ABC12345'; title = 'Synthetic Pressure Washer'; url = 'https://example.invalid/item'
                    price = 199.99; coupon = $null; rating = 4.5; review_count = 123; seller = 'Example'
                    fba_status = 'UNKNOWN'; first_available_date = $null; source_type = 'CREATORS_API'; search_term = 'pressure washer'
                })
                runs = @([pscustomobject]@{
                    display_name = 'Pressure Washer Search Top 50'; status = 'SUCCEEDED'; expected_count = 50
                    raw_count = 50; accepted_count = 50; rejected_count = 0; completeness_percent = 100; error_summary = $null
                })
                signals = @([pscustomobject]@{ signal_type = 'RISING_PRODUCT'; signal_count = 1 })
            }
        }
    }

    It 'generates UTF-8 Markdown and HTML reports from report data' {
        $report = New-DailyMarketReport -MarketDate '2026-08-03' -WorkRoot (Join-Path $TestDrive 'report') `
            -PostgresSettings $script:reportPostgresSettings -PipelineResult ([pscustomobject]@{ Status = 'SUCCEEDED' }) `
            -DataProvider $script:reportDataProvider
        $report.Status | Should Be 'GENERATED'
        $report.RankingCount | Should Be 1
        (Test-Path -LiteralPath $report.MarkdownPath) | Should Be $true
        (Test-Path -LiteralPath $report.HtmlPath) | Should Be $true
        (Get-Content -LiteralPath $report.MarkdownPath -Raw -Encoding UTF8) | Should Match 'Synthetic Pressure Washer'
        (Get-Content -LiteralPath $report.HtmlPath -Raw -Encoding UTF8) | Should Match 'RISING_PRODUCT'
    }

    It 'skips email without attempting transport when authorization code is absent' {
        $report = New-DailyMarketReport -MarketDate '2026-08-03' -WorkRoot (Join-Path $TestDrive 'mail-skip') `
            -PostgresSettings $script:reportPostgresSettings -DataProvider $script:reportDataProvider
        $script:transportCalls = 0
        $settings = [pscustomobject]@{ host = 'smtp.qq.com'; port = 587; enable_ssl = $true; username = '746254487@qq.com'; password = $null; sender = '746254487@qq.com' }
        $result = Send-DailyReportEmail -Recipient '746254487@qq.com' -Subject $report.Subject -HtmlPath $report.HtmlPath `
            -AttachmentPaths @($report.MarkdownPath) -SmtpSettings $settings -MailTransport { $script:transportCalls++ }
        $result.Status | Should Be 'SKIPPED_CREDENTIALS_MISSING'
        $script:transportCalls | Should Be 0
        $deliveryRecords = Write-MailDeliveryRunRecords -MarketDate '2026-08-03' `
            -ReportKind Daily -Messages @([pscustomobject]@{ Category = 'general'; ReportPath = $report.MarkdownPath; DeliveryResult = $result }) `
            -WorkRoot (Join-Path $TestDrive 'mail-skip') -RunId 'skipped-email'
        (Test-Path -LiteralPath $deliveryRecords.ManifestPath) | Should Be $true
        (Get-Content -LiteralPath $deliveryRecords.RecordPaths[0] -Raw -Encoding UTF8) | Should Not Match 'password|authorization'
    }

    It 'sends the HTML report and Markdown attachment through an injected transport' {
        $report = New-DailyMarketReport -MarketDate '2026-08-03' -WorkRoot (Join-Path $TestDrive 'mail-send') `
            -PostgresSettings $script:reportPostgresSettings -DataProvider $script:reportDataProvider
        $script:mailRecipient = $null
        $script:attachmentCount = 0
        $transport = {
            param($recipient, $subject, $htmlBody, $attachments, $settings)
            $script:mailRecipient = $recipient; $script:attachmentCount = @($attachments).Count
            if ($htmlBody -notmatch 'Synthetic Pressure Washer') { throw 'missing report body' }
        }
        $settings = [pscustomobject]@{ host = 'smtp.qq.com'; port = 587; enable_ssl = $true; username = '746254487@qq.com'; password = 'mail-auth-secret'; sender = '746254487@qq.com' }
        $result = Send-DailyReportEmail -Recipient '746254487@qq.com' -Subject $report.Subject -HtmlPath $report.HtmlPath `
            -AttachmentPaths @($report.MarkdownPath) -SmtpSettings $settings -MailTransport $transport
        $result.Status | Should Be 'SENT'
        $script:mailRecipient | Should Be '746254487@qq.com'
        $script:attachmentCount | Should Be 1
    }

    It 'marks SMTP failures retryable and redacts the authorization code' {
        $report = New-DailyMarketReport -MarketDate '2026-08-03' -WorkRoot (Join-Path $TestDrive 'mail-fail') `
            -PostgresSettings $script:reportPostgresSettings -DataProvider $script:reportDataProvider
        $settings = [pscustomobject]@{ host = 'smtp.qq.com'; port = 587; enable_ssl = $true; username = '746254487@qq.com'; password = 'mail-auth-secret'; sender = '746254487@qq.com' }
        $result = Send-DailyReportEmail -Recipient '746254487@qq.com' -Subject $report.Subject -HtmlPath $report.HtmlPath `
            -SmtpSettings $settings -MailTransport { throw 'server rejected mail-auth-secret' }
        $result.Status | Should Be 'SEND_FAILED_RETRYABLE'
        $result.ErrorMessage | Should Not Match 'mail-auth-secret'
        $result.ErrorMessage | Should Match '\[REDACTED\]'
    }
}

Describe 'Windows daily scheduler scripts' {
    It 'computes the default market date in the US Pacific time zone' {
        $scriptText = Get-Content (Join-Path $projectRoot 'scripts\Invoke-ScheduledDailyPipeline.ps1') -Raw -Encoding UTF8
        $scriptText | Should Match "Pacific Standard Time"
        $scriptText | Should Match "Start-LocalPostgres.ps1"
        $scriptText | Should Match "Invoke-DailyPipeline.ps1"
    }

    It 'registers a non-overlapping 09:00 interactive scheduled task' {
        $scriptText = Get-Content (Join-Path $projectRoot 'scripts\Register-DailyScheduledTask.ps1') -Raw -Encoding UTF8
        $scriptText | Should Match "DailyAt = '09:00'"
        $scriptText | Should Match 'MultipleInstances IgnoreNew'
        $scriptText | Should Match 'LogonType Interactive'
        $scriptText | Should Match 'ExecutionPolicy Bypass'
    }
}

Describe 'Local PostgreSQL backup tooling' {
    It 'creates a custom-format backup with a password-free integrity manifest' {
        $backup = Get-Content (Join-Path $projectRoot 'scripts\postgres\Backup-LocalPostgres.ps1') -Raw
        $backup | Should Match 'pg_dump\.exe'
        $backup | Should Match "'-F' 'c'"
        $backup | Should Match 'Get-FileHash'
        $backup | Should Match 'local-postgres-backup-v1'
        $backup | Should Match 'Start-LocalPostgres\.ps1'
        $backup | Should Not Match 'Write-Output.*password'
        $starter = Get-Content (Join-Path $projectRoot 'scripts\postgres\Start-LocalPostgres.ps1') -Raw
        $starter | Should Not Match 'exit 0'
        $starter | Should Match 'pg_isready\.exe'
    }

    It 'validates a backup archive without restoring it' {
        $verification = Get-Content (Join-Path $projectRoot 'scripts\postgres\Test-LocalPostgresBackup.ps1') -Raw
        $verification | Should Match 'pg_restore\.exe'
        $verification | Should Match "'--list'"
        $verification | Should Not Match "pg_restore\\.exe.*'-d'"
        $verification | Should Match 'HASH_MISMATCH'
    }

    It 'registers an independent non-overlapping daily backup task' {
        $scheduler = Get-Content (Join-Path $projectRoot 'scripts\postgres\Register-LocalPostgresBackupScheduledTask.ps1') -Raw
        $scheduler | Should Match "TaskName = 'AmazonIntelligence-PostgreSQLBackup-1030'"
        $scheduler | Should Match "DailyAt = '10:30'"
        $scheduler | Should Match 'New-ScheduledTaskTrigger -Daily'
        $scheduler | Should Match 'MultipleInstances IgnoreNew'
        $scheduler | Should Match 'Backup-LocalPostgres\.ps1'
        $scheduler | Should Not Match 'pg_restore|Remove-Item.*postgres-backups'
    }

    It 'uses a reserved temporary database for restore drills and protects production' {
        $drill = Get-Content (Join-Path $projectRoot 'scripts\postgres\Test-LocalPostgresRestoreDrill.ps1') -Raw
        $drill | Should Match "RestoreDatabase -notmatch '\^amazon_intelligence_restore_"
        $drill | Should Match 'RestoreDatabase must never be the configured production database'
        $drill | Should Match "pgRestore '--exit-on-error'"
        $drill | Should Match 'DROP DATABASE IF EXISTS'
        $drill | Should Match "table_schema = 'amazon_intelligence'.*marketplace.*best_sellers_run"
        $drill | Should Match 'Start-LocalPostgres\.ps1'
        $drill | Should Not Match "pgRestore.*'-d'.*settings\.database"
    }

    It 'emits only JSON control output from a successful PostgreSQL restore drill' {
        $drill = Get-Content (Join-Path $projectRoot 'scripts\postgres\Test-LocalPostgresRestoreDrill.ps1') -Raw
        $drill | Should Match "CREATE DATABASE.*\| Out-Null"
        $drill | Should Match "DROP DATABASE IF EXISTS.*\| Out-Null"
    }
}

Describe 'Creators API credential setup script' {
    It 'uses hidden input and user-scoped environment variables without embedded credentials' {
        $scriptText = Get-Content (Join-Path $projectRoot 'scripts\Set-CreatorsApiEnvironment.ps1') -Raw -Encoding UTF8
        $scriptText | Should Match "CLIENT_SECRET' -AsSecureString"
        $scriptText | Should Match 'SetEnvironmentVariable\(\$name, \[string\]\$values\[\$name\], ''User''\)'
        $scriptText | Should Match 'ZeroFreeBSTR'
        $scriptText | Should Not Match 'client_secret\s*=\s*[A-Za-z0-9]{8,}'
    }
}

Describe 'Credential-free public intelligence mode' {
    It 'normalizes and deduplicates recent official CPSC recall records' {
        $transport = {
            param($uri, $keyword)
            return [pscustomobject]@{
                RecallNumber = '26-TEST'; RecallDate = '2026-07-20T00:00:00'; LastPublishDate = '2026-07-21T00:00:00'
                Title = 'Pressure Washers Recalled Due to Shock Hazard'; URL = 'https://www.cpsc.gov/Recalls/2026/test'
                Products = @([pscustomobject]@{ Name = 'Example Electric Pressure Washer' })
                Manufacturers = @([pscustomobject]@{ Name = 'Example Manufacturer' })
                Hazards = @([pscustomobject]@{ Name = 'Shock hazard' })
                Remedies = @([pscustomobject]@{ Name = 'Stop use and request a refund' })
            }
        }
        $result = Get-CpscRecallPublicIntelligence -MarketDate '2026-08-03' -WorkRoot (Join-Path $TestDrive 'public-data') `
            -Keywords @('pressure washer','power washer') -Transport $transport
        $result.Status | Should Be 'SUCCEEDED'
        $result.QueryCount | Should Be 2
        $result.ItemCount | Should Be 1
        $result.Items[0].category_slug | Should Be 'pressure-washer'
        $result.Items[0].content_hash.Length | Should Be 64
        (Test-Path -LiteralPath $result.ArtifactPath) | Should Be $true
        $importSql = New-PublicIntelligenceImportSql -ArtifactPath $result.ArtifactPath
        $importSql | Should Match 'SELECT ingest_public_intelligence'
        $importSql | Should Match 'COMMIT;'
    }

    It 'generates a clearly limited public-data-only report' {
        $publicData = [pscustomobject]@{
            Status = 'SUCCEEDED'; MarketDate = '2026-08-03'; LookbackDays = 90
            Items = @([pscustomobject]@{
                recall_date='2026-07-20'; category_slug='pressure-washer'; recall_number='26-TEST'
                products='Example Washer'; manufacturers='Example Manufacturer'; hazards='Shock hazard'
                url='https://www.cpsc.gov/Recalls/2026/test'
            })
        }
        $report = New-CredentialFreeMarketReport -PublicIntelligence $publicData -WorkRoot (Join-Path $TestDrive 'public-report')
        $report.Mode | Should Be 'PUBLIC_DATA_ONLY'
        $markdown = Get-Content -LiteralPath $report.MarkdownPath -Raw -Encoding UTF8
        $markdown | Should Match 'Unavailable: Amazon ranking'
        $markdown | Should Match 'Not calculated: new-product detection'
        $report.Subject | Should Match 'PUBLIC DATA ONLY'
    }

    It 'ignores successful no-result payloads that are not recall records' {
        $transport = { param($uri, $keyword) [pscustomobject]@{ Message = 'No records found' } }
        $result = Get-CpscRecallPublicIntelligence -MarketDate '2026-08-03' -WorkRoot (Join-Path $TestDrive 'public-empty') `
            -Keywords @('foam cannon') -Transport $transport
        $result.Status | Should Be 'SUCCEEDED'
        $result.ItemCount | Should Be 0
    }

    It 'routes the scheduler to public mode when Creators credentials are unavailable' {
        $scriptText = Get-Content (Join-Path $projectRoot 'scripts\Invoke-ScheduledDailyPipeline.ps1') -Raw -Encoding UTF8
        $scriptText | Should Match 'Mode=PUBLIC_DATA_ONLY'
        $scriptText | Should Match 'Invoke-CredentialFreeDailyPipeline.ps1'
    }
}

Describe 'Best Sellers Top 50 snapshot analysis' {
    function New-TestBestSellerItem {
        param([int]$Rank, [string]$Asin, [string]$Title)
        return [pscustomobject]@{
            rank = $Rank; asin = $Asin; title = $Title; price = '$99.00'
            rating = 4.5; reviews = 100; url = "https://www.amazon.com/dp/$Asin"
        }
    }

    function New-TestBestSellerSnapshot {
        param([string]$MarketDate, [int]$PressureOffset = 0, [switch]$ReplacePressureFirst)
        $pressure = @()
        $sump = @()
        $accessories = @()
        foreach ($rank in 1..30) {
            $pressureAsin = ('B0P{0:D7}' -f ($rank + $PressureOffset))
            if ($ReplacePressureFirst -and $rank -eq 1) { $pressureAsin = 'B0NEW00001' }
            $pressure += New-TestBestSellerItem -Rank $rank -Asin $pressureAsin -Title "Pressure item $rank"
            $sump += New-TestBestSellerItem -Rank $rank -Asin ('B0S{0:D7}' -f $rank) -Title "Sump item $rank"
            $accessories += New-TestBestSellerItem -Rank $rank -Asin ('B0A{0:D7}' -f $rank) -Title "Accessory item $rank"
        }
        return [pscustomobject]@{
            market_date = $MarketDate
            pressure_washers = $pressure
            sump_pumps = $sump
            pressure_washer_accessories = $accessories
        }
    }

    It 'passes a complete and unique Top 30 snapshot' {
        $snapshot = New-TestBestSellerSnapshot -MarketDate '2026-08-04'
        $quality = Test-BestSellersTop50Snapshot -Snapshot $snapshot -TargetCount 30
        $quality.is_complete | Should Be $true
        @($quality.categories).Count | Should Be 3
        $quality.categories[0].item_count | Should Be 30
        $quality.categories[0].missing_ranks.Count | Should Be 0
    }

    It 'reports missing ranks and duplicate ASINs' {
        $snapshot = New-TestBestSellerSnapshot -MarketDate '2026-08-04'
        $snapshot.pressure_washers[29].rank = 29
        $snapshot.pressure_washers[29].asin = $snapshot.pressure_washers[28].asin
        $quality = Test-BestSellersTop50Snapshot -Snapshot $snapshot -TargetCount 30
        $quality.is_complete | Should Be $false
        @($quality.categories[0].duplicate_asins).Count | Should Be 1
        @($quality.categories[0].duplicate_ranks) -contains 29 | Should Be $true
        @($quality.categories[0].missing_ranks) -contains 30 | Should Be $true
    }

    It 'flags large moves, new entries and Top 30 exits' {
        $previous = New-TestBestSellerSnapshot -MarketDate '2026-08-03'
        $current = New-TestBestSellerSnapshot -MarketDate '2026-08-04'
        $moving = $current.pressure_washers[0]
        $other = $current.pressure_washers[24]
        $moving.rank = 25
        $other.rank = 1
        $current.pressure_washers[29].asin = 'B0NEW00001'
        $current.pressure_washers[29].title = 'New pressure item'
        $analysis = Compare-BestSellersSnapshots -CurrentSnapshot $current -PreviousSnapshot $previous
        $analysis.has_baseline | Should Be $true
        (@($analysis.noteworthy | Where-Object { $_.asin -eq 'B0P0000001' })[0]).priority | Should Be 'HIGH'
        (@($analysis.noteworthy | Where-Object { $_.asin -eq 'B0NEW00001' })[0]).status | Should Be 'NEW_IN_TOP50'
        (@($analysis.noteworthy | Where-Object { $_.asin -eq 'B0P0000030' })[0]).status | Should Be 'DROPPED_FROM_TOP50'
    }

    It 'uses BASELINE without false movement signals on the first day' {
        $current = New-TestBestSellerSnapshot -MarketDate '2026-08-04'
        $analysis = Compare-BestSellersSnapshots -CurrentSnapshot $current -PreviousSnapshot $null
        $analysis.has_baseline | Should Be $false
        $analysis.noteworthy_count | Should Be 0
        @($analysis.changes | Where-Object { $_.status -ne 'BASELINE' }).Count | Should Be 0
    }

    It 'creates an independent baseline when a category is added later' {
        $previous = New-TestBestSellerSnapshot -MarketDate '2026-08-03'
        $previous.PSObject.Properties.Remove('pressure_washer_accessories')
        $current = New-TestBestSellerSnapshot -MarketDate '2026-08-04'
        $analysis = Compare-BestSellersSnapshots -CurrentSnapshot $current -PreviousSnapshot $previous
        (@($analysis.category_baselines | Where-Object { $_.category -eq 'pressure_washer_accessories' })[0]).has_baseline | Should Be $false
        @($analysis.changes | Where-Object { $_.category -eq 'pressure_washer_accessories' -and $_.status -ne 'BASELINE' }).Count | Should Be 0
        @($analysis.noteworthy | Where-Object { $_.category -eq 'pressure_washer_accessories' }).Count | Should Be 0
    }
}

Describe 'Best Sellers Chinese daily report' {
    function New-DailyReportTestItems {
        $items = @()
        foreach ($rank in 1..50) {
            $items += [pscustomobject]@{
                asin = ('B0D{0:D7}' -f $rank); rank = $rank; title = "Daily item $rank"
                url = "https://www.amazon.com/dp/B0D$('{0:D7}' -f $rank)"; price = '$20.00'; rating = 4.5; reviews = 100
            }
        }
        return $items
    }

    function New-DailyReportTestSnapshot {
        param([string]$Date, [switch]$Partial, [switch]$SwapLargeMove)
        $pressure = New-DailyReportTestItems
        if ($SwapLargeMove) {
            $pressure[0].rank = 20
            $pressure[19].rank = 1
        }
        if ($Partial) { $pressure = @($pressure | Select-Object -First 30) }
        [pscustomobject]@{
            market_date = $Date; observed_at = "${Date}T01:00:00Z"; pressure_washers = @($pressure | Select-Object -First 30)
            sump_pumps = @((New-DailyReportTestItems | Select-Object -First 30))
            pressure_washer_accessories = if ($Partial) { @() } else { @((New-DailyReportTestItems | Select-Object -First 30)) }
        }
    }

    It 'suppresses change claims when either daily chart is incomplete' {
        $previous = New-DailyReportTestSnapshot -Date '2026-08-04'
        $current = New-DailyReportTestSnapshot -Date '2026-08-05' -Partial
        $report = New-BestSellersDailyReport -CurrentSnapshot $current -PreviousSnapshot $previous -OutputDirectory (Join-Path $TestDrive 'partial')
        $report.Status | Should Be 'PARTIAL_TOP30'
        $report.ComparableCategories.Count | Should Be 2
        $report.NoteworthyChanges.Count | Should Be 0
        (Test-Path -LiteralPath $report.MarkdownPath) | Should Be $true
        (Get-Content -LiteralPath $report.MarkdownPath -Raw -Encoding UTF8) | Should Match 'Top 30'
    }

    It 'reports only verified large movements from complete charts' {
        $previous = New-DailyReportTestSnapshot -Date '2026-08-04'
        $current = New-DailyReportTestSnapshot -Date '2026-08-05' -SwapLargeMove
        $report = New-BestSellersDailyReport -CurrentSnapshot $current -PreviousSnapshot $previous -OutputDirectory (Join-Path $TestDrive 'complete')
        $report.Status | Should Be 'COMPLETE_TOP30'
        $report.ComparableCategories.Count | Should Be 3
        $report.NoteworthyChanges.Count | Should Be 2
        @($report.NoteworthyChanges | Where-Object { $_.priority -eq 'WATCH' }).Count | Should Be 2
        (Test-Path -LiteralPath $report.HtmlPath) | Should Be $true
    }

    It 'escapes dynamic comparison ASIN cells in Markdown and HTML' {
        $previous = New-DailyReportTestSnapshot -Date '2026-08-04'
        $current = New-DailyReportTestSnapshot -Date '2026-08-05' -SwapLargeMove
        $current.pressure_washers[0].asin = "B0|ASIN`n<script>alert(1)</script>"

        $report = New-BestSellersDailyReport -CurrentSnapshot $current -PreviousSnapshot $previous -OutputDirectory (Join-Path $TestDrive 'comparison-asin')
        $markdown = Get-Content -LiteralPath $report.MarkdownPath -Raw -Encoding UTF8
        $html = Get-Content -LiteralPath $report.HtmlPath -Raw -Encoding UTF8

        $markdown | Should Match 'B0\\\|ASIN <script>alert\(1\)</script>'
        $markdown | Should Not Match 'B0\|ASIN'
        $html | Should Match '<td>B0\|ASIN\s*&lt;script&gt;alert\(1\)&lt;/script&gt;</td>'
        $html | Should Not Match '<script>alert\(1\)</script>'
    }

    It 'renders verified discount states, ratings, reviews and a non-causal disclosure in both daily report formats' {
        $current = New-DailyReportTestSnapshot -Date '2026-08-05'
        $current.pressure_washers[0].rating = 4.8
        $current.pressure_washers[0].reviews = 321
        $current.pressure_washers[0] | Add-Member -NotePropertyName has_discount -NotePropertyValue $true
        $current.pressure_washers[0] | Add-Member -NotePropertyName discounts -NotePropertyValue @([pscustomobject]@{ kind = 'COUPON'; amount = '10% off' }, [pscustomobject]@{ kind = 'PRICE_DROP'; amount = '$10.00 off' })
        $current.pressure_washers[1] | Add-Member -NotePropertyName has_discount -NotePropertyValue $false
        $current.pressure_washers[1] | Add-Member -NotePropertyName discounts -NotePropertyValue @()
        $current.pressure_washers[2] | Add-Member -NotePropertyName has_discount -NotePropertyValue $null
        $current.pressure_washers[2] | Add-Member -NotePropertyName discounts -NotePropertyValue @()

        $report = New-BestSellersDailyReport -CurrentSnapshot $current -OutputDirectory (Join-Path $TestDrive 'discounts') -CategoryKeys pressure_washers
        $markdown = Get-Content -LiteralPath $report.MarkdownPath -Raw -Encoding UTF8
        $html = Get-Content -LiteralPath $report.HtmlPath -Raw -Encoding UTF8

        (Format-BestSellersDiscountDisplay -Item $current.pressure_washers[0]) | Should Be '10% off; $10.00 off'
        (Format-BestSellersDiscountDisplay -Item $current.pressure_washers[1]) | Should Be 'None'
        (Format-BestSellersDiscountDisplay -Item $current.pressure_washers[2]) | Should Be 'Pending verification'
        $markdown | Should Match '\|.*Discount \|'
        $markdown | Should Match '10% off; \$10\.00 off'
        $markdown | Should Match 'None'
        $markdown | Should Match 'Pending verification'
        $markdown | Should Match '\| #1 \| Daily item 1 \| B0D0000001 \| \$20\.00 \| 4\.8 \| 321 \| 10% off; \$10\.00 off \|'
        $markdown | Should Match 'Verified discounted: 1; verified not discounted: 1; pending/unknown: 28'
        $markdown | Should Match 'Observed co-movement only; this does not prove that a discount caused a rank change\.'
        $html | Should Match '<th>Discount</th>'
        $html | Should Match '<td>10% off; \$10\.00 off</td>'
        $html | Should Match '<td>4\.8</td><td>321</td><td>10% off; \$10\.00 off</td>'
        $html | Should Match 'Verified discounted: 1; verified not discounted: 1; pending/unknown: 28'
        $html | Should Match 'Observed co-movement only; this does not prove that a discount caused a rank change\.'
    }
}

Describe 'Best Sellers daily operational health' {
    It 'checks the receipt, database counts, PDF output and verified backup without claiming complete Top 50 coverage' {
        $health = Get-Content (Join-Path $projectRoot 'scripts\Test-BestSellersDailyOperationalHealth.ps1') -Raw
        $health | Should Match 'Test-BestSellersCaptureReceipt\.ps1'
        $health | Should Match 'Test-BestSellersCaptureReceipt\.ps1[^\r\n]+-RegistryPath \$RegistryPath'
        $health | Should Match 'best_sellers_observation'
        $health | Should Match 'artifact_sha256'
        $health | Should Match 'Get-ChildItem.*\.pdf'
        $health | Should Match 'Test-LocalPostgresBackup\.ps1'
        $health | Should Match "Status = 'HEALTHY'"
        $health | Should Match 'Where-Object \{ \$null -ne \$_ \}'
        $health | Should Not Match 'is_complete.*throw|quality_passed.*throw'
    }
}

Describe 'Best Sellers capture receipt' {
    It 'binds a complete snapshot to its configured source nodes and immutable content hash' {
        $configPath = Join-Path $projectRoot 'config\best-sellers-sources.json'
        $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $items = @()
        foreach ($rank in 1..30) { $items += [pscustomobject]@{ asin=('B0C{0:D7}' -f $rank); rank=$rank; title="Receipt item $rank"; url="https://www.amazon.com/dp/B0C$('{0:D7}' -f $rank)"; price='$20.00'; rating=4.5; reviews=100 } }
        $sourceUrls = [ordered]@{}
        foreach ($source in @($config.sources)) { $sourceUrls[[string]$source.category_key] = [string]$source.url }
        $snapshot = [pscustomobject]@{ market_date='2026-08-04'; observed_at='2026-08-04T01:00:00Z'; sources=[pscustomobject]$sourceUrls; pressure_washers=$items; sump_pumps=$items; pressure_washer_accessories=$items }
        $snapshotPath = Join-Path $TestDrive 'complete-snapshot.json'
        [IO.File]::WriteAllText($snapshotPath, ($snapshot | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
        $receipt = New-BestSellersCaptureReceipt -SnapshotPath $snapshotPath -SourceConfigPath $configPath
        $receipt.status | Should Be 'COMPLETE_VALIDATED'
        $receipt.snapshot_sha256.Length | Should Be 64
        $receipt.source_metadata_verified | Should Be $true
        @($receipt.categories | Where-Object { $_.source_url_status -ne 'MATCH' }).Count | Should Be 0
        @($receipt.categories | Where-Object { $_.target_count -ne 30 }).Count | Should Be 0
        $path = Write-BestSellersCaptureReceipt -Receipt $receipt -Path (Join-Path $TestDrive 'receipt.json')
        (Test-Path -LiteralPath $path) | Should Be $true
        (Test-BestSellersCaptureReceipt -ReceiptPath $path).valid | Should Be $true
        [IO.File]::AppendAllText($snapshotPath, "`n ")
        (Test-BestSellersCaptureReceipt -ReceiptPath $path).valid | Should Be $false
    }
}

Describe 'Best Sellers PostgreSQL import' {
    It 'preserves true false null and structured discounts in import payloads' {
        $artifactPath = Join-Path $TestDrive 'discount-states.json'
        $snapshot = [pscustomobject]@{
            market_date = '2026-08-04'; observed_at = '2026-08-04T01:00:00Z'
            pressure_washers = @(
                [pscustomobject]@{ asin='B0DISC0001'; rank=1; title='Coupon item'; url='https://www.amazon.com/dp/B0DISC0001'; has_discount=$true; discounts=@([pscustomobject]@{kind='COUPON'; amount='10% off'}) },
                [pscustomobject]@{ asin='B0DISC0002'; rank=2; title='No discount item'; url='https://www.amazon.com/dp/B0DISC0002'; has_discount=$false; discounts=@() },
                [pscustomobject]@{ asin='B0DISC0003'; rank=3; title='Unknown discount item'; url='https://www.amazon.com/dp/B0DISC0003'; has_discount=$null; discounts=@() }
            )
            sump_pumps = @(); pressure_washer_accessories = @()
        }
        [System.IO.File]::WriteAllText($artifactPath, ($snapshot | ConvertTo-Json -Compress -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

        $sql = New-BestSellersImportSql -ArtifactPath $artifactPath -SourceConfigPath (Join-Path $projectRoot 'config\best-sellers-sources.json')

        $sql | Should Match '"has_discount":true'
        $sql | Should Match '"has_discount":false'
        $sql | Should Match '"has_discount":null'
        $sql | Should Match '"discounts":\[\{"kind":"COUPON","amount":"10% off"\}\]'
    }

    It 'keeps snapshots without discount fields compatible with the ingestion API' {
        $artifactPath = Join-Path $TestDrive 'legacy-best-sellers.json'
        [System.IO.File]::WriteAllText($artifactPath, '{"market_date":"2026-08-04","observed_at":"2026-08-04T01:00:00Z","pressure_washers":[],"sump_pumps":[],"pressure_washer_accessories":[]}', (New-Object System.Text.UTF8Encoding($false)))

        $sql = New-BestSellersImportSql -ArtifactPath $artifactPath -SourceConfigPath (Join-Path $projectRoot 'config\best-sellers-sources.json')

        $sql | Should Not Match '"has_discount"'
        $sql | Should Not Match '"discounts"'
        $sql | Should Match 'SELECT ingest_best_sellers_snapshot'
    }

    It 'imports product metadata in the same transaction as the verified snapshot' {
        $artifactPath = Join-Path $TestDrive 'metadata-best-sellers.json'
        [System.IO.File]::WriteAllText($artifactPath, '{"market_date":"2026-08-20","observed_at":"2026-08-20T01:00:00Z","pressure_washers":[],"sump_pumps":[],"pressure_washer_accessories":[]}', (New-Object System.Text.UTF8Encoding($false)))

        $sql = New-BestSellersImportSql -ArtifactPath $artifactPath -SourceConfigPath (Join-Path $projectRoot 'config\best-sellers-sources.json') -MetadataRows @(
            [pscustomobject]@{ marketplace_code='AMAZON_US'; asin='B000000001'; product_type='unknown'; classification_confidence='low'; classification_rule_id=$null; classification_rule_version='product-rules-v1'; classification_evidence=@('NO_SAFE_RULE_MATCH'); raw_brand=$null; normalized_brand=$null; normalized_brand_key=$null; brand_alias_rule_id=$null; brand_source='unknown'; first_seen_market_date='2026-08-20'; last_seen_market_date='2026-08-20' }
        )

        $sql | Should Match 'BEGIN;'
        $sql | Should Match 'ingest_best_sellers_snapshot'
        $sql | Should Match 'upsert_best_sellers_product_metadata'
        $sql | Should Match 'COMMIT;'
    }

    It 'creates a transactional, schema-versioned and credential-free import statement' {
        $artifactPath = Join-Path $TestDrive 'best-sellers.json'
        [System.IO.File]::WriteAllText($artifactPath, '{"market_date":"2026-08-04","observed_at":"2026-08-04T01:00:00Z","pressure_washers":[],"sump_pumps":[],"pressure_washer_accessories":[]}', (New-Object System.Text.UTF8Encoding($false)))
        $sql = New-BestSellersImportSql -ArtifactPath $artifactPath -SourceConfigPath (Join-Path $projectRoot 'config\best-sellers-sources.json')
        $sql | Should Match 'BEGIN;'
        $sql | Should Match 'SELECT ingest_best_sellers_snapshot'
        $sql | Should Match 'amazon-best-sellers-snapshot-v1'
        $sql | Should Match '3023451'
        $sql | Should Match 'COMMIT;'
        $sql | Should Not Match 'password|PGPASSWORD'
        $module = Get-Content (Join-Path $projectRoot 'src\BestSellersPostgres.psm1') -Raw
        $module | Should Match 'psql -X --no-psqlrc -v ON_ERROR_STOP=1 \| Out-Null'
    }

    function New-VerifiedImportFixture {
        param(
            [string]$Name,
            [bool]$Complete = $true,
            [bool]$IncludeSourceMetadata = $true
        )

        $sourceConfigPath = Join-Path $projectRoot 'config\best-sellers-sources.json'
        $config = Get-Content -LiteralPath $sourceConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $items = @(1..$(if ($Complete) { 30 } else { 29 }) | ForEach-Object {
                [pscustomobject]@{
                    rank = $_
                    asin = 'B' + $_.ToString('000000000')
                    title = "Fixture Pressure Washer $_"
                    price = $null
                    rating = $null
                    reviews = $null
                }
            })
        $snapshot = [ordered]@{
            market_date = '2026-08-20'
            observed_at = '2026-08-20T01:00:00Z'
            pressure_washers = $items
            sump_pumps = $items
            pressure_washer_accessories = $items
        }
        if ($IncludeSourceMetadata) {
            $sources = [ordered]@{}
            foreach ($source in @($config.sources)) { $sources[[string]$source.category_key] = [string]$source.url }
            $snapshot.sources = [pscustomobject]$sources
        }
        $snapshotPath = Join-Path $TestDrive "$Name-snapshot.json"
        [IO.File]::WriteAllText($snapshotPath, ([pscustomobject]$snapshot | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
        $receiptPath = Join-Path $TestDrive "$Name-receipt.json"
        $receipt = New-BestSellersCaptureReceipt -SnapshotPath $snapshotPath -SourceConfigPath $sourceConfigPath
        Write-BestSellersCaptureReceipt -Receipt $receipt -Path $receiptPath | Out-Null
        return [pscustomobject]@{ snapshot_path = $snapshotPath; receipt_path = $receiptPath; receipt = $receipt }
    }

    function New-VerifiedImportTestHooks {
        param([Parameter(Mandatory=$true)]$Calls)

        return @{
            BuildMetadata = {
                param($Snapshot, $ClassificationConfigPath, $BrandAliasConfigPath)
                $Calls.metadata_build_count++
                return @()
            }
            StartPostgres = {
                param($SettingsPath)
                $Calls.postgres_start_count++
            }
            ImportPostgres = {
                param($ArtifactPath, $SourceConfigPath, $PostgresSettings, $MetadataRows)
                $Calls.postgres_import_count++
                $Calls.postgres_import_artifact_path = [string]$ArtifactPath
            }
        }
    }

    It 'passes the canonical authorized snapshot path to PostgreSQL import and its success response' {
        $fixture = New-VerifiedImportFixture -Name 'canonical-import'
        $calls = [pscustomobject]@{ metadata_build_count = 0; postgres_start_count = 0; postgres_import_count = 0; postgres_import_artifact_path = $null }
        $runner = Join-Path $projectRoot 'scripts\Import-VerifiedBestSellersSnapshot.ps1'
        $relativeSnapshotPath = Resolve-Path -LiteralPath $fixture.snapshot_path -Relative

        $result = & $runner -SnapshotPath $relativeSnapshotPath -ReceiptPath $fixture.receipt_path -TestHooks (New-VerifiedImportTestHooks -Calls $calls) | ConvertFrom-Json
        $expectedPath = (Resolve-Path -LiteralPath $fixture.snapshot_path).Path

        $calls.postgres_import_count | Should Be 1
        $calls.postgres_import_artifact_path | Should Be $expectedPath
        $result.SnapshotPath | Should Be $expectedPath
    }

    It 'authorizes from the verification result when the receipt changes after its single read' {
        $fixture = New-VerifiedImportFixture -Name 'single-receipt-read'
        $initialReceipt = Get-Content -LiteralPath $fixture.receipt_path -Raw -Encoding UTF8
        $changedReceipt = $initialReceipt | ConvertFrom-Json
        $changedReceipt.status = 'PARTIAL_NOT_ANALYSIS_ELIGIBLE'
        $global:bestSellersReceiptReadCount = 0
        $global:bestSellersInitialReceipt = $initialReceipt
        $global:bestSellersChangedReceipt = $changedReceipt | ConvertTo-Json -Depth 12

        Mock -CommandName Get-Content -ModuleName BestSellersCaptureReceipt -ParameterFilter { $LiteralPath -eq $fixture.receipt_path } -MockWith {
            $global:bestSellersReceiptReadCount++
            if ($global:bestSellersReceiptReadCount -eq 1) { return $global:bestSellersInitialReceipt }
            return $global:bestSellersChangedReceipt
        }

        try {
            $authorized = Resolve-BestSellersAuthorizedSnapshot -SnapshotPath $fixture.snapshot_path -ReceiptPath $fixture.receipt_path

            $global:bestSellersReceiptReadCount | Should Be 1
            $authorized.market_date | Should Be '2026-08-20'
            $authorized.snapshot_sha256 | Should Be $fixture.receipt.snapshot_sha256
            $authorized.verification.receipt_status | Should Be 'COMPLETE_VALIDATED'
        }
        finally {
            Remove-Variable -Name bestSellersReceiptReadCount -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name bestSellersInitialReceipt -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name bestSellersChangedReceipt -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a receipt that verifies a different snapshot before metadata or PostgreSQL work' {
        $verified = New-VerifiedImportFixture -Name 'verified-a'
        $requestedPath = Join-Path $TestDrive 'requested-b.json'
        Copy-Item -LiteralPath $verified.snapshot_path -Destination $requestedPath
        $calls = [pscustomobject]@{ metadata_build_count = 0; postgres_start_count = 0; postgres_import_count = 0 }
        $runner = Join-Path $projectRoot 'scripts\Import-VerifiedBestSellersSnapshot.ps1'

        $threw = $false
        try { & $runner -SnapshotPath $requestedPath -ReceiptPath $verified.receipt_path -TestHooks (New-VerifiedImportTestHooks -Calls $calls) | Out-Null } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'does not match the receipt snapshot'
        }

        $threw | Should Be $true
        $calls.metadata_build_count | Should Be 0
        $calls.postgres_start_count | Should Be 0
        $calls.postgres_import_count | Should Be 0
    }

    It 'rejects a partial receipt before metadata or PostgreSQL work' {
        $fixture = New-VerifiedImportFixture -Name 'partial' -Complete $false
        $fixture.receipt.status | Should Be 'PARTIAL_NOT_ANALYSIS_ELIGIBLE'
        $calls = [pscustomobject]@{ metadata_build_count = 0; postgres_start_count = 0; postgres_import_count = 0 }
        $runner = Join-Path $projectRoot 'scripts\Import-VerifiedBestSellersSnapshot.ps1'

        $threw = $false
        try { & $runner -SnapshotPath $fixture.snapshot_path -ReceiptPath $fixture.receipt_path -TestHooks (New-VerifiedImportTestHooks -Calls $calls) | Out-Null } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'COMPLETE_VALIDATED'
        }

        $threw | Should Be $true
        $calls.metadata_build_count | Should Be 0
        $calls.postgres_start_count | Should Be 0
        $calls.postgres_import_count | Should Be 0
    }

    It 'rejects a receipt without verified source metadata before metadata or PostgreSQL work' {
        $fixture = New-VerifiedImportFixture -Name 'source-unverified' -IncludeSourceMetadata $false
        $fixture.receipt.status | Should Be 'COMPLETE_SOURCE_METADATA_INCOMPLETE'
        $fixture.receipt.source_metadata_verified | Should Be $false
        $calls = [pscustomobject]@{ metadata_build_count = 0; postgres_start_count = 0; postgres_import_count = 0 }
        $runner = Join-Path $projectRoot 'scripts\Import-VerifiedBestSellersSnapshot.ps1'

        $threw = $false
        try { & $runner -SnapshotPath $fixture.snapshot_path -ReceiptPath $fixture.receipt_path -TestHooks (New-VerifiedImportTestHooks -Calls $calls) | Out-Null } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'COMPLETE_VALIDATED'
        }

        $threw | Should Be $true
        $calls.metadata_build_count | Should Be 0
        $calls.postgres_start_count | Should Be 0
        $calls.postgres_import_count | Should Be 0
    }
}

Describe 'Best Sellers weekly analysis' {
    function New-WeeklyTestItem {
        param([string]$Asin, [int]$Rank, [long]$Reviews, $HasDiscount = $false, $Discounts = @())
        [pscustomobject]@{ asin=$Asin; rank=$Rank; title="Item $Asin"; url="https://www.amazon.com/dp/$Asin"; price='$100.00'; rating=4.5; reviews=$Reviews; has_discount=$HasDiscount; discounts=@($Discounts) }
    }
    function New-WeeklyTestSnapshot {
        param([string]$Date, $Pressure, $Sump, $Accessories)
        [pscustomobject]@{ market_date=$Date; observed_at="${Date}T01:00:00Z"; pressure_washers=@($Pressure); sump_pumps=@($Sump); pressure_washer_accessories=@($Accessories) }
    }

    It 'calculates weekly net movement, large daily swings, entries and exits' {
        $day1 = New-WeeklyTestSnapshot -Date '2026-08-03' `
            -Pressure @((New-WeeklyTestItem 'B0AAA00001' 30 100),(New-WeeklyTestItem 'B0EXIT0001' 10 50)) `
            -Sump @((New-WeeklyTestItem 'B0SSS00001' 5 200)) -Accessories @()
        $day2 = New-WeeklyTestSnapshot -Date '2026-08-04' `
            -Pressure @((New-WeeklyTestItem 'B0AAA00001' 5 110),(New-WeeklyTestItem 'B0NEW00001' 40 5)) `
            -Sump @((New-WeeklyTestItem 'B0SSS00001' 6 205)) -Accessories @()
        $day3 = New-WeeklyTestSnapshot -Date '2026-08-05' `
            -Pressure @((New-WeeklyTestItem 'B0AAA00001' 8 125),(New-WeeklyTestItem 'B0NEW00001' 20 15)) `
            -Sump @((New-WeeklyTestItem 'B0SSS00001' 4 212)) -Accessories @()
        $analysis = New-BestSellersWeeklyAnalysis -Snapshots @($day3,$day1,$day2)
        $analysis.period_start | Should Be '2026-08-03'
        $analysis.period_end | Should Be '2026-08-05'
        $analysis.coverage_complete | Should Be $false
        $swing = @($analysis.large_swings | Where-Object { $_.asin -eq 'B0AAA00001' })[0]
        $swing.rank_change | Should Be 25
        $swing.priority | Should Be 'HIGH'
        @($analysis.new_entries | Where-Object { $_.asin -eq 'B0NEW00001' }).Count | Should Be 1
        @($analysis.exits | Where-Object { $_.asin -eq 'B0EXIT0001' }).Count | Should Be 1
        $product = @($analysis.categories[0].products | Where-Object { $_.asin -eq 'B0AAA00001' })[0]
        $product.weekly_rank_change | Should Be 22
        $product.review_growth | Should Be 25
        $product.days_in_chart | Should Be 3
    }

    It 'marks seven fully present snapshot days as complete coverage' {
        $snapshots = @()
        foreach ($day in 1..7) {
            $date = '2026-08-{0:D2}' -f ($day + 2)
            $item = New-WeeklyTestItem 'B0AAA00001' $day (100 + $day)
            $snapshots += New-WeeklyTestSnapshot -Date $date -Pressure @($item) -Sump @($item) -Accessories @($item)
        }
        (New-BestSellersWeeklyAnalysis -Snapshots $snapshots).coverage_complete | Should Be $true
    }

    It 'observes adjacent known discount transitions and counts unknown states' {
        $coupon10 = [pscustomobject]@{ kind='COUPON'; amount='$10' }
        $coupon20 = [pscustomobject]@{ kind='COUPON'; amount='$20' }
        $day1 = New-WeeklyTestSnapshot -Date '2026-08-03' -Pressure @(
            (New-WeeklyTestItem 'B0ADD000001' 20 100 $false @()),
            (New-WeeklyTestItem 'B0REMOVE001' 21 100 $true @($coupon10)),
            (New-WeeklyTestItem 'B0CHANGE001' 22 100 $true @($coupon10)),
            (New-WeeklyTestItem 'B0SAME00001' 23 100 $true @($coupon10)),
            (New-WeeklyTestItem 'B0UNKNOWN01' 24 100 $null @())
        ) -Sump @() -Accessories @()
        $day2 = New-WeeklyTestSnapshot -Date '2026-08-04' -Pressure @(
            (New-WeeklyTestItem 'B0ADD000001' 10 110 $true @($coupon10)),
            (New-WeeklyTestItem 'B0REMOVE001' 30 110 $false @()),
            (New-WeeklyTestItem 'B0CHANGE001' 12 110 $true @($coupon20)),
            (New-WeeklyTestItem 'B0SAME00001' 25 110 $true @($coupon10)),
            (New-WeeklyTestItem 'B0UNKNOWN01' 26 110 $true @($coupon10))
        ) -Sump @() -Accessories @()

        $analysis = New-BestSellersWeeklyAnalysis -Snapshots @($day2, $day1)
        $transitions = @($analysis.discount_transitions | Where-Object category -eq 'pressure_washers')
        $summary = @($analysis.categories | Where-Object category -eq 'pressure_washers')[0].discount_summary

        $transitions.Count | Should Be 5
        (@($transitions | Where-Object transition_kind -eq 'DISCOUNT_ADDED')).Count | Should Be 1
        (@($transitions | Where-Object transition_kind -eq 'DISCOUNT_REMOVED')).Count | Should Be 1
        (@($transitions | Where-Object transition_kind -eq 'DISCOUNT_AMOUNT_CHANGED')).Count | Should Be 1
        (@($transitions | Where-Object transition_kind -eq 'UNCHANGED')).Count | Should Be 1
        (@($transitions | Where-Object transition_kind -eq 'UNKNOWN')).Count | Should Be 1
        (@($transitions | Where-Object asin -eq 'B0UNKNOWN01')).Count | Should Be 1
        (@($transitions | Where-Object asin -eq 'B0ADD000001')[0].rank_change | Should Be 10)
        $summary.added_count | Should Be 1
        $summary.removed_count | Should Be 1
        $summary.amount_changed_count | Should Be 1
        $summary.unchanged_count | Should Be 1
        $summary.unknown_count | Should Be 1
    }
}

Describe 'Best Sellers weekly report content' {
    BeforeAll {
        Import-Module (Join-Path $projectRoot 'src\BestSellersWeeklyReportContent.psm1') -Force -ErrorAction SilentlyContinue
        $script:weeklyReportAnalysis = [pscustomobject]@{
            coverage_complete = $false
            large_swings = @(
                [pscustomobject]@{ category='pressure_washers'; asin='B0PRESS001'; market_date='2026-08-10'; previous_market_date='2026-08-09'; previous_rank=27; current_rank=5; rank_change=22; absolute_change=22; priority='HIGH'; title='Pressure product'; url='https://www.amazon.com/dp/B0PRESS001' },
                [pscustomobject]@{ category='sump_pumps'; asin='B0SUMP0001'; market_date='2026-08-10'; previous_market_date='2026-08-09'; previous_rank=4; current_rank=19; rank_change=-15; absolute_change=15; priority='WATCH'; title='Sump product'; url='https://www.amazon.com/dp/B0SUMP0001' }
            )
            new_entries = @(
                [pscustomobject]@{ category='pressure_washers'; asin='B0ENTRY001'; market_date='2026-08-10'; current_rank=12; title='Entry product'; url='https://www.amazon.com/dp/B0ENTRY001' }
            )
            exits = @(
                [pscustomobject]@{ category='pressure_washers'; asin='B0EXIT0001'; market_date='2026-08-10'; previous_market_date='2026-08-09'; previous_rank=9; title='Exit product'; url='https://www.amazon.com/dp/B0EXIT0001' }
            )
            discount_transitions = @(
                [pscustomobject]@{ category='pressure_washers'; asin='B0OFFER001'; previous_market_date='2026-08-09'; market_date='2026-08-10'; previous_has_discount=$false; has_discount=$true; previous_discounts=@(); discounts=@([pscustomobject]@{kind='COUPON'; amount='$10|off'}); previous_rank=20; current_rank=5; rank_change=15; transition_kind='DISCOUNT_ADDED' }
            )
            categories = @(
                [pscustomobject]@{ category='pressure_washers'; products=@(); discount_summary=[pscustomobject]@{ added_count=1; removed_count=0; amount_changed_count=0; unchanged_count=0; unknown_count=0 } },
                [pscustomobject]@{ category='sump_pumps'; products=@() }
            )
        }
        $script:rankInfluence = [pscustomobject]@{
            categories = @(
                [pscustomobject]@{
                    category='pressure_washers'
                    cross_sectional_associations=@(
                        [pscustomobject]@{ metric='PRICE_USD'; sample_size=28; status='ANALYZED'; spearman_rho=0.5674; direction='HIGHER_ASSOCIATED_WITH_BETTER_RANK'; strength='MODERATE' },
                        [pscustomobject]@{ metric='RATING_STARS'; sample_size=30; status='ANALYZED'; spearman_rho=0.222; direction='HIGHER_ASSOCIATED_WITH_BETTER_RANK'; strength='WEAK' },
                        [pscustomobject]@{ metric='LOG10_REVIEW_COUNT_PLUS_1'; sample_size=28; status='ANALYZED'; spearman_rho=0.1735; direction='HIGHER_ASSOCIATED_WITH_BETTER_RANK'; strength='VERY_WEAK' }
                    )
                    longitudinal_associations=@()
                },
                [pscustomobject]@{ category='sump_pumps'; cross_sectional_associations=@(); longitudinal_associations=@() }
            )
        }
    }

    It 'renders verified changes and associations for only the requested category' {
        $result = New-BestSellersWeeklyCategorySections -CategoryKey 'pressure_washers' -WeeklyAnalysis $weeklyReportAnalysis -RankInfluence $rankInfluence -LimitedCoverage $true
        $decode = { param([string]$Value) [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value)) }
        $result.LargeSwingCount | Should Be 1
        $result.NewEntryCount | Should Be 1
        $result.ExitCount | Should Be 1
        $result.AssociationCount | Should Be 3
        $result.DiscountTransitionCount | Should Be 1
        $result.Markdown | Should Match 'B0PRESS001'
        $result.Markdown | Should Match 'B0ENTRY001'
        $result.Markdown | Should Match 'B0EXIT0001'
        $result.Markdown | Should Match 'B0OFFER001'
        $result.Markdown | Should Match 'DISCOUNT_ADDED'
        $result.Markdown | Should Match '\$10\\\|off'
        $result.Markdown | Should Match 'observed co-movement only and does not establish a discount caused a rank change'
        $result.Markdown | Should Not Match 'B0SUMP0001'
        $result.Markdown | Should Match (& $decode '5aSn5bmF5o6S5ZCN5Y+Y5YyW')
        $result.Markdown | Should Match (& $decode '5paw5YWlIFRvcCAzMA==')
        $result.Markdown | Should Match (& $decode '6YCA5Ye6IFRvcCAzMA==')
        $result.Markdown | Should Match (& $decode '5Lu35qC8')
        $result.Markdown | Should Match (& $decode '6K+E6K665pif57qn')
        $result.Markdown | Should Match (& $decode '6K+E6K665pWw')
        $result.Markdown | Should Match 'Spearman rho'
        $result.Markdown | Should Match (& $decode '5LiN5Luj6KGoLirlr7zoh7TmjpLlkI3lj5jljJY=')
        $result.Markdown | Should Match (& $decode '6aaW5qyh5pyJ6ZmQ5ZGo5bqm5YiG5p6Q')
        $result.Html | Should Match 'B0PRESS001'
        $result.Html | Should Match 'B0OFFER001'
        $result.Html | Should Match 'DISCOUNT_ADDED'
        $result.Html | Should Match '\$10\|off'
        $result.Html | Should Match 'observed co-movement only and does not establish a discount caused a rank change'
        $result.Html | Should Not Match 'B0SUMP0001'
    }

    It 'rejects a category absent from either analysis artifact' {
        $errorMessage = $null
        try {
            New-BestSellersWeeklyCategorySections -CategoryKey 'pressure_washer_accessories' -WeeklyAnalysis $weeklyReportAnalysis -RankInfluence $rankInfluence | Out-Null
        }
        catch {
            $errorMessage = $_.Exception.Message
        }
        $errorMessage | Should Match 'Analysis artifacts do not contain exactly one category'
    }
}

Describe 'PDF report tooling' {
    It 'keeps section headings with the content that follows them' {
        $rendererPath = Join-Path $projectRoot 'scripts\python\render_markdown_pdf.py'
        $pythonPath = Join-Path $projectRoot '.venv\Scripts\python.exe'
        & $pythonPath -c "import importlib.util; spec=importlib.util.spec_from_file_location('renderer', r'$rendererPath'); module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module); styles=module.build_styles('Helvetica'); assert styles['h2'].keepWithNext == 0; assert styles['h2_keep'].keepWithNext == 1; assert styles['h3'].keepWithNext == 0; assert styles['h3_keep'].keepWithNext == 1"
        $LASTEXITCODE | Should Be 0
    }

    It 'does not place a spacer between a heading and its following content' {
        $rendererPath = Join-Path $projectRoot 'scripts\python\render_markdown_pdf.py'
        $pythonPath = Join-Path $projectRoot '.venv\Scripts\python.exe'
        & $pythonPath -c "import importlib.util; spec=importlib.util.spec_from_file_location('renderer', r'$rendererPath'); module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module); assert module.should_add_blank_spacer(['## Heading', '', '- Detail'], 1) is False; assert module.should_add_blank_spacer(['Body', '', 'Body'], 1) is True"
        $LASTEXITCODE | Should Be 0
    }

    It 'allows long tables to split after their section heading' {
        $rendererPath = Join-Path $projectRoot 'scripts\python\render_markdown_pdf.py'
        $pythonPath = Join-Path $projectRoot '.venv\Scripts\python.exe'
        & $pythonPath -c "import importlib.util; spec=importlib.util.spec_from_file_location('renderer', r'$rendererPath'); module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module); assert module.should_keep_heading_with_next(['## Heading', '', '| A |'], 0) is False; assert module.should_keep_heading_with_next(['## Heading', '', '- Detail'], 0) is True"
        $LASTEXITCODE | Should Be 0
    }

    It 'preserves escaped pipes in Markdown table cells' {
        $renderer = Get-Content (Join-Path $projectRoot 'scripts\python\render_markdown_pdf.py') -Raw
        $renderer | Should Match 'def split_markdown_table_row'
        $renderer | Should Match 'elif character == "\\\\"'
        $renderer | Should Match 'split_markdown_table_row\(lines\[index\]\)'
    }

    It 'delivers the Best Sellers daily report as a verified PDF attachment' {
        $script = Get-Content (Join-Path $projectRoot 'scripts\New-BestSellersDailyReport.ps1') -Raw
        $script | Should Match 'New-ReportPdf\.ps1'
        $script | Should Match '-Title \$report\.Subject'
        $script | Should Match 'AttachmentPaths @\(\$pdf\.PdfPath\)'
        $script | Should Match 'SKIPPED_BY_REQUEST'
    }

    It 'gates the weekly PDF Phase 5 artifacts through analysis readiness' {
        $script = Get-Content (Join-Path $projectRoot 'scripts\New-BestSellersWeeklyReport.ps1') -Raw
        $script | Should Match 'Test-Phase5AnalysisReadiness\.ps1'
        $script | Should Match 'if \(\$readiness\.analysis_due\)'
        $script | Should Match 'New-BestSellersOpportunityAnalysis\.ps1'
        $script | Should Match 'BestSellersWeeklyReportContent\.psm1'
        $script | Should Match 'Get-Content -LiteralPath \$weeklyRun\.ArtifactPath -Raw -Encoding UTF8 \| ConvertFrom-Json'
        $script | Should Match '\$rankInfluencePath'
        $script | Should Match 'New-BestSellersWeeklyCategorySections'
        $script | Should Match '\$sections\.Markdown'
        $script | Should Match '\$sections\.Html'
        $script | Should Match 'AttachmentPaths @\(\$pdf\.PdfPath\)'
        $script | Should Match 'SKIPPED_BY_REQUEST'
        $activeScript = ($script -split '(?m)^return\s*$')[0]
        $activeScript | Should Not Match '\$t\.no_changes'
    }
}

Describe 'Best Sellers opportunity analysis' {
    function New-OpportunityWeeklyAnalysis {
        param([int]$Days = 7)
        $product = [pscustomobject]@{
            asin = 'B0OPP00001'; title = 'Evidence based opportunity'; url = 'https://www.amazon.com/dp/B0OPP00001'
            days_in_chart = $Days; start_rank = 30; end_rank = 5; weekly_rank_change = 25
            max_daily_absolute_change = 25; status = 'CONTINUING'; reviews_start = 100
            reviews_end = 170; review_growth = 70; rating_end = 4.7
        }
        [pscustomobject]@{
            schema_version = 'best-sellers-weekly-analysis-v1'; period_start = '2026-08-01'; period_end = '2026-08-07'
            snapshot_day_count = $Days; coverage_complete = ($Days -eq 7)
            categories = @([pscustomobject]@{ category = 'pressure_washers'; products = @($product) })
        }
    }

    It 'scores only available evidence and exposes missing brand data' {
        $analysis = New-BestSellersOpportunityAnalysis -WeeklyAnalysis (New-OpportunityWeeklyAnalysis)
        $product = $analysis.categories[0].products[0]
        $product.classification | Should Be 'HIGH_OPPORTUNITY'
        $product.observed_score | Should BeGreaterThan 70
        $product.confidence_percent | Should Be 80
        @($product.missing_dimensions) -contains 'brand_growth' | Should Be $true
        @($product.signals) -contains 'FAST_RISING' | Should Be $true
        @($product.signals) -contains 'HIGH_RANK_LOW_REVIEW' | Should Be $true
    }

    It 'refuses an opportunity label when history is only a baseline' {
        $weekly = New-OpportunityWeeklyAnalysis -Days 1
        $weekly.categories[0].products[0].weekly_rank_change = $null
        $weekly.categories[0].products[0].review_growth = $null
        $analysis = New-BestSellersOpportunityAnalysis -WeeklyAnalysis $weekly
        $analysis.categories[0].products[0].classification | Should Be 'BASELINE_INSUFFICIENT'
        $analysis.categories[0].products[0].confidence_percent | Should BeLessThan 50
    }

    It 'builds an idempotent credential-free PostgreSQL import statement' {
        $artifactPath = Join-Path $TestDrive 'opportunity.json'
        $analysis = New-BestSellersOpportunityAnalysis -WeeklyAnalysis (New-OpportunityWeeklyAnalysis)
        Write-BestSellersOpportunityArtifact -Analysis $analysis -Path $artifactPath | Out-Null
        $sql = New-BestSellersOpportunityImportSql -ArtifactPath $artifactPath
        $sql | Should Match 'ingest_best_sellers_opportunity_analysis'
        $sql | Should Match 'best-sellers-opportunity-analysis-v1'
        $sql | Should Match 'COMMIT;'
        $sql | Should Not Match 'password|PGPASSWORD'
    }

    It 'defines versioned analysis storage and a latest-signal view' {
        $migration = Get-Content (Join-Path $projectRoot 'db\migrations\008_opportunity_analysis.sql') -Raw
        $migration | Should Match 'CREATE TABLE best_sellers_analysis_run'
        $migration | Should Match 'CREATE TABLE best_sellers_opportunity_signal'
        $migration | Should Match 'CREATE VIEW best_sellers_opportunity_latest'
        $migration | Should Match 'source_artifact_sha256 char\(64\) NOT NULL UNIQUE'
    }
}

Describe 'Best Sellers market structure analysis' {
    function New-MarketStructureItem {
        param([string]$Asin, [int]$Rank, [string]$Price, [string]$Title)
        [pscustomobject]@{ asin=$Asin; rank=$Rank; price=$Price; title=$Title; rating=4.5; reviews=100; url="https://www.amazon.com/dp/$Asin" }
    }

    It 'calculates price-band density without inventing missing prices or brands' {
        $snapshot = [pscustomobject]@{
            market_date = '2026-08-04'
            pressure_washers = @(
                (New-MarketStructureItem 'B0PRICE001' 1 '$19.99' 'Low price washer'),
                (New-MarketStructureItem 'B0PRICE002' 2 '$79.99' 'Mid price washer'),
                (New-MarketStructureItem 'B0PRICE003' 3 $null 'Missing price washer'))
            sump_pumps = @(); pressure_washer_accessories = @()
        }
        $analysis = New-BestSellersMarketStructureAnalysis -Snapshot $snapshot
        $category = @($analysis.categories | Where-Object { $_.category -eq 'pressure_washers' })[0]
        $category.priced_item_count | Should Be 2
        $category.price_coverage_percent | Should Be 66.67
        (@($category.price_bands | Where-Object { $_.price_band -eq 'UNDER_25' })[0]).item_count | Should Be 1
        (@($category.price_bands | Where-Object { $_.price_band -eq '50_TO_99_99' })[0]).item_count | Should Be 1
        $category.brand_analysis.status | Should Be 'UNAVAILABLE_NO_VERIFIED_BRAND_FIELD'
    }

    It 'classifies accessory titles with ordered, auditable keyword rules' {
        $snapshot = [pscustomobject]@{
            market_date = '2026-08-04'; pressure_washers = @(); sump_pumps = @()
            pressure_washer_accessories = @(
                (New-MarketStructureItem 'B0ACC00001' 1 '$39.99' '14 inch Surface Cleaner with Quick Connector'),
                (New-MarketStructureItem 'B0ACC00002' 2 '$29.99' 'Foam Cannon for Pressure Washer'),
                (New-MarketStructureItem 'B0ACC00003' 3 '$9.99' 'Universal Cleaning Tool'))
        }
        $analysis = New-BestSellersMarketStructureAnalysis -Snapshot $snapshot
        $surface = @($analysis.accessory_analysis.products | Where-Object { $_.asin -eq 'B0ACC00001' })[0]
        $surface.primary_type | Should Be 'SURFACE_CLEANER'
        @($surface.matched_types) -contains 'ADAPTER_CONNECTOR' | Should Be $true
        (@($analysis.accessory_analysis.products | Where-Object { $_.asin -eq 'B0ACC00003' })[0]).primary_type | Should Be 'UNCLASSIFIED'
        $analysis.accessory_analysis.classification_coverage_percent | Should Be 66.67
    }

    It 'builds a versioned credential-free market-structure import statement' {
        $artifactPath = Join-Path $TestDrive 'market-structure.json'
        $snapshot = [pscustomobject]@{ market_date='2026-08-04'; pressure_washers=@(); sump_pumps=@(); pressure_washer_accessories=@() }
        Write-BestSellersMarketStructureArtifact -Analysis (New-BestSellersMarketStructureAnalysis -Snapshot $snapshot) -Path $artifactPath | Out-Null
        $sql = New-BestSellersMarketStructureImportSql -ArtifactPath $artifactPath
        $sql | Should Match 'ingest_best_sellers_market_structure'
        $sql | Should Match 'best-sellers-market-structure-v1'
        $sql | Should Not Match 'password|PGPASSWORD'
    }

    It 'defines append-preserving price-band and accessory storage' {
        $migration = Get-Content (Join-Path $projectRoot 'db\migrations\009_market_structure_analysis.sql') -Raw
        $migration | Should Match 'CREATE TABLE best_sellers_market_structure_run'
        $migration | Should Match 'CREATE TABLE best_sellers_price_band_metric'
        $migration | Should Match 'CREATE TABLE best_sellers_accessory_classification'
        $migration | Should Match 'CREATE VIEW best_sellers_price_band_latest'
    }
}

Describe 'Best Sellers rank influence analysis' {
    It 'measures monotonic price, rating and review associations against rank strength' {
        $items = @()
        foreach ($rank in 1..6) {
            $items += [pscustomobject]@{
                asin = ('B0RANK{0:D4}' -f $rank); rank = $rank; price = ('$' + ($rank * 10))
                rating = 5.0 - ($rank * 0.1); reviews = 700 - ($rank * 100); title = "Item $rank"
            }
        }
        $snapshot = [pscustomobject]@{ market_date='2026-08-04'; pressure_washers=$items; sump_pumps=@(); pressure_washer_accessories=@() }
        $analysis = New-BestSellersRankInfluenceAnalysis -Snapshot $snapshot -MinimumSample 5
        $category = @($analysis.categories | Where-Object { $_.category -eq 'pressure_washers' })[0]
        $price = @($category.cross_sectional_associations | Where-Object { $_.metric -eq 'PRICE_USD' })[0]
        $rating = @($category.cross_sectional_associations | Where-Object { $_.metric -eq 'RATING_STARS' })[0]
        $reviews = @($category.cross_sectional_associations | Where-Object { $_.metric -eq 'LOG10_REVIEW_COUNT_PLUS_1' })[0]
        $price.spearman_rho | Should Be -1
        $price.direction | Should Be 'HIGHER_ASSOCIATED_WITH_WORSE_RANK'
        $rating.spearman_rho | Should Be 1
        $reviews.spearman_rho | Should Be 1
        $analysis.method.causal_warning | Should Match 'Observational association only'
    }

    It 'gates small samples and unavailable history' {
        $snapshot = [pscustomobject]@{ market_date='2026-08-04'; pressure_washers=@([pscustomobject]@{asin='B0SMALL001';rank=1;price='$10';rating=4.5;reviews=10;title='Small'}); sump_pumps=@(); pressure_washer_accessories=@() }
        $analysis = New-BestSellersRankInfluenceAnalysis -Snapshot $snapshot -MinimumSample 5
        $category = $analysis.categories[0]
        @($category.cross_sectional_associations | Where-Object { $_.status -ne 'INSUFFICIENT_SAMPLE' }).Count | Should Be 0
        @($category.longitudinal_associations | Where-Object { $_.status -ne 'INSUFFICIENT_SAMPLE' }).Count | Should Be 0
    }

    It 'does not treat a one-day weekly baseline as longitudinal evidence' {
        $items = @(1..5 | ForEach-Object { [pscustomobject]@{ asin=('B0BASE{0:D4}' -f $_); rank=$_; price=('$'+$_); rating=4.5; reviews=100; title='Baseline' } })
        $snapshot = [pscustomobject]@{ market_date='2026-08-04'; pressure_washers=$items; sump_pumps=@(); pressure_washer_accessories=@() }
        $weekly = [pscustomobject]@{ snapshot_day_count=1; categories=@([pscustomobject]@{ category='pressure_washers'; products=@([pscustomobject]@{price_change=0;review_growth=0;weekly_rank_change=0}) }) }
        $analysis = New-BestSellersRankInfluenceAnalysis -Snapshot $snapshot -WeeklyAnalysis $weekly
        @($analysis.categories[0].longitudinal_associations | Where-Object { $_.status -ne 'INSUFFICIENT_SAMPLE' }).Count | Should Be 0
    }

    It 'builds a credential-free versioned rank influence import statement' {
        $artifactPath = Join-Path $TestDrive 'rank-influence.json'
        $snapshot = [pscustomobject]@{ market_date='2026-08-04'; pressure_washers=@(); sump_pumps=@(); pressure_washer_accessories=@() }
        Write-BestSellersRankInfluenceArtifact -Analysis (New-BestSellersRankInfluenceAnalysis -Snapshot $snapshot) -Path $artifactPath | Out-Null
        $sql = New-BestSellersRankInfluenceImportSql -ArtifactPath $artifactPath
        $sql | Should Match 'ingest_best_sellers_rank_influence'
        $sql | Should Match 'best-sellers-rank-influence-v1'
        $sql | Should Not Match 'password|PGPASSWORD'
    }

    It 'defines association and bucket persistence with latest views' {
        $migration = Get-Content (Join-Path $projectRoot 'db\migrations\010_rank_influence_analysis.sql') -Raw
        $migration | Should Match 'CREATE TABLE best_sellers_rank_association'
        $migration | Should Match 'CREATE TABLE best_sellers_rank_bucket_summary'
        $migration | Should Match 'CREATE VIEW best_sellers_rank_association_latest'
        $migration | Should Match 'spearman_rho numeric'
    }
}

Describe 'Phase 5 analysis readiness gate' {
    function New-ReadinessItems {
        $items = @()
        foreach ($rank in 1..30) {
            $items += [pscustomobject]@{
                asin = ('B0R{0:D7}' -f $rank); rank = $rank; title = "Item $rank"
                price = '$20.00'; rating = 4.5; reviews = 100; url = "https://www.amazon.com/dp/B0R$('{0:D7}' -f $rank)"
            }
        }
        return $items
    }

    function Write-ReadinessSnapshot {
        param([string]$Root, [string]$Date, [switch]$IncompleteAccessories)
        $directory = Join-Path $Root $Date
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $accessories = New-ReadinessItems
        if ($IncompleteAccessories) { $accessories = @($accessories | Select-Object -First 29) }
        $snapshot = [pscustomobject]@{
            market_date = $Date; observed_at = "${Date}T01:00:00Z"
            pressure_washers = New-ReadinessItems
            sump_pumps = New-ReadinessItems
            pressure_washer_accessories = $accessories
        }
        [IO.File]::WriteAllText((Join-Path $directory 'amazon-bestsellers.json'), ($snapshot | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
    }

    It 'requires more than seven complete market days for every active category' {
        $root = Join-Path $TestDrive 'snapshots-seven'
        foreach ($offset in 0..6) { Write-ReadinessSnapshot -Root $root -Date ('2026-08-{0:D2}' -f ($offset + 1)) }
        $result = Get-BestSellersAnalysisReadiness -SnapshotsRoot $root -SourceConfigPath (Join-Path $projectRoot 'config\best-sellers-sources.json') -AsOfDate '2026-08-07'
        $result.ready | Should Be $false
        $result.status | Should Be 'COLLECTING_BASELINE'
        @($result.categories | Where-Object { $_.missing_valid_days -ne 1 }).Count | Should Be 0
    }

    It 'does not count incomplete Top 30 days toward the analysis threshold' {
        $root = Join-Path $TestDrive 'snapshots-eight'
        foreach ($offset in 0..7) { Write-ReadinessSnapshot -Root $root -Date ('2026-08-{0:D2}' -f ($offset + 1)) -IncompleteAccessories:($offset -eq 7) }
        $result = Get-BestSellersAnalysisReadiness -SnapshotsRoot $root -SourceConfigPath (Join-Path $projectRoot 'config\best-sellers-sources.json') -AsOfDate '2026-08-08'
        $result.ready | Should Be $false
        (@($result.categories | Where-Object { $_.category -eq 'pressure_washer_accessories' })[0]).valid_market_day_count | Should Be 7
        (@($result.categories | Where-Object { $_.category -eq 'pressure_washer_accessories' })[0]).status | Should Be 'INCOMPLETE_SNAPSHOTS_PRESENT'
    }

    It 'opens the gate only after eight complete Top 30 days for all three categories' {
        $root = Join-Path $TestDrive 'snapshots-ready'
        foreach ($offset in 0..7) { Write-ReadinessSnapshot -Root $root -Date ('2026-08-{0:D2}' -f ($offset + 1)) }
        $result = Get-BestSellersAnalysisReadiness -SnapshotsRoot $root -SourceConfigPath (Join-Path $projectRoot 'config\best-sellers-sources.json') -AsOfDate '2026-08-08'
        $result.ready | Should Be $true
        $result.status | Should Be 'READY_FOR_FULL_PHASE_5_ANALYSIS'
    }

    It 'honors the configured first eligible analysis date even when data coverage is ready' {
        $root = Join-Path $TestDrive 'snapshots-date-gate'
        foreach ($offset in 0..7) { Write-ReadinessSnapshot -Root $root -Date ('2026-08-{0:D2}' -f ($offset + 1)) }
        $before = Get-BestSellersAnalysisReadiness -SnapshotsRoot $root -SourceConfigPath (Join-Path $projectRoot 'config\best-sellers-sources.json') -AsOfDate '2026-08-09' -NotBeforeDate '2026-08-10'
        $before.coverage_ready | Should Be $true
        $before.date_ready | Should Be $false
        $before.ready | Should Be $false
        $after = Get-BestSellersAnalysisReadiness -SnapshotsRoot $root -SourceConfigPath (Join-Path $projectRoot 'config\best-sellers-sources.json') -AsOfDate '2026-08-10' -NotBeforeDate '2026-08-10'
        $after.ready | Should Be $true
    }

    It 'allows the explicitly approved initial weekly analysis after its date with incomplete coverage' {
        $root = Join-Path $TestDrive 'snapshots-initial-weekly'
        foreach ($offset in 0..6) { Write-ReadinessSnapshot -Root $root -Date ('2026-08-{0:D2}' -f ($offset + 1)) }
        $result = Get-BestSellersAnalysisReadiness -SnapshotsRoot $root -SourceConfigPath (Join-Path $projectRoot 'config\best-sellers-sources.json') -AsOfDate '2026-08-10' -NotBeforeDate '2026-08-10' -AllowAnalysisBeforeCoverage
        $result.coverage_ready | Should Be $false
        $result.analysis_due | Should Be $true
        $result.analysis_mode | Should Be 'LIMITED_WEEKLY'
        $result.status | Should Be 'READY_FOR_LIMITED_WEEKLY_ANALYSIS'
    }
}
