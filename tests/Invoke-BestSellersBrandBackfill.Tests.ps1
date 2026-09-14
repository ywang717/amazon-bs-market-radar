$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $projectRoot 'scripts\Invoke-BestSellersBrandBackfill.ps1'

function Write-TestJson {
    param([string]$Path, $Value)
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
}

function New-TestBrandArtifact {
    param([string[]]$Asins)
    [pscustomobject]@{
        schema_version='amazon-brand-enrichment-v1'; marketplace='AMAZON_US'; generated_at='2026-08-28T00:00:00Z'
        products=@($Asins | Sort-Object | ForEach-Object { [pscustomobject]@{ asin=$_; detail_url="https://www.amazon.com/dp/$_"; verification_status='MISSING'; raw_brand=$null; brand_source='unknown'; evidence_source=$null } })
    }
}

Describe 'Historical Best Sellers brand backfill' {
    It 'uses the default receipt-verified metadata path without relying on caller module scope' {
        $root = Join-Path $TestDrive 'default-metadata'
        $historyDay = Join-Path $root 'history\2026-08-28'
        New-Item -ItemType Directory -Path $historyDay -Force | Out-Null
        $sourceConfigPath = Join-Path $projectRoot 'config\best-sellers-sources.json'
        $sources = Get-Content -LiteralPath $sourceConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $items = @(1..30 | ForEach-Object { [pscustomobject]@{ rank=$_; asin=('B' + $_.ToString('000000000')); title='Receipt verified history item'; price=$null; rating=$null; reviews=$null } })
        $snapshotPath = Join-Path $historyDay 'amazon-bestsellers.json'
        Write-TestJson -Path $snapshotPath -Value ([pscustomobject]@{
            market_date='2026-08-28'; observed_at='2026-08-28T00:00:00Z'
            sources=[pscustomobject]@{ pressure_washers=$sources.sources[0].url; pressure_washer_accessories=$sources.sources[2].url; sump_pumps=$sources.sources[1].url }
            pressure_washers=$items; pressure_washer_accessories=$items; sump_pumps=$items
        })
        $receiptModulePath = Join-Path $projectRoot 'src\BestSellersCaptureReceipt.psm1'
        Import-Module $receiptModulePath -Force
        $receipt = New-BestSellersCaptureReceipt -SnapshotPath $snapshotPath -SourceConfigPath $sourceConfigPath
        Write-BestSellersCaptureReceipt -Receipt $receipt -Path (Join-Path $historyDay 'best-sellers-capture-receipt.json') | Out-Null
        Remove-Module BestSellersCaptureReceipt -Force

        $calls = New-Object Collections.ArrayList
        $artifactJson = (New-TestBrandArtifact -Asins @('B000000001') | ConvertTo-Json -Depth 20)
        $collect = { param($ArtifactPath,$Asins,$Headless) [void]$calls.Add('collect'); [IO.File]::WriteAllText($ArtifactPath, $artifactJson, (New-Object Text.UTF8Encoding($false))) }.GetNewClosure()
        $postgres = { param($Rows) [void]$calls.Add("postgres:$(@($Rows).Count)") }.GetNewClosure()
        $publish = { param($Payload) [void]$calls.Add("publish:$(@($Payload.productMetadata).Count)") }.GetNewClosure()

        try {
            $result = & $scriptPath -ProjectRoot $projectRoot -OutputRoot $root -SnapshotsRoot (Join-Path $root 'history') -RequestedAsins @('B000000001') -MarketDate '2026-08-28' -CollectAction $collect -PostgresAction $postgres -PublishAction $publish | ConvertFrom-Json
        }
        finally {
            Import-Module $receiptModulePath -Force
        }

        $calls | Should Be @('collect','postgres:1','publish:1')
        $result.StageCounts.metadata_merged_rows | Should Be 1
        $result.StageCounts.postgres_imported_rows | Should Be 1
        $result.StageCounts.dashboard_published | Should Be 1
    }

    It 'uses the injected collection, metadata import, and publish seams only after a verified artifact and receipt' {
        $root = Join-Path $TestDrive 'success'
        $history = Join-Path $root 'history'
        New-Item -ItemType Directory -Path $history -Force | Out-Null
        $calls = New-Object Collections.ArrayList
        $artifactJson = (New-TestBrandArtifact -Asins @('B000000001') | ConvertTo-Json -Depth 20)
        $collect = {
            param($ArtifactPath,$Asins,$Headless)
            [void]$calls.Add("collect:$($Asins -join ','):$Headless")
            [IO.File]::WriteAllText($ArtifactPath, $artifactJson, (New-Object Text.UTF8Encoding($false)))
        }.GetNewClosure()
        $metadata = { param($Asins) @($Asins | ForEach-Object { [pscustomobject]@{ marketplace_code='AMAZON_US'; asin=$_; product_type='unknown'; classification_confidence='low'; classification_rule_id='fallback'; classification_rule_version='v1'; classification_evidence=@(); raw_brand=$null; normalized_brand=$null; normalized_brand_key=$null; brand_alias_rule_id=$null; brand_source='unknown'; first_seen_market_date='2026-08-28'; last_seen_market_date='2026-08-28' } }) }.GetNewClosure()
        $postgres = { param($Rows) [void]$calls.Add("postgres:$(@($Rows).Count)") }.GetNewClosure()
        $publish = { param($Payload) [void]$calls.Add("publish:$($Payload.schemaVersion):$(@($Payload.productMetadata).Count)") }.GetNewClosure()
        $discover = { param($SnapshotsRoot) @('B000000001','B000000002') }

        $result = & $scriptPath -ProjectRoot $projectRoot -OutputRoot $root -RequestedAsins @('B000000002','B000000001','B000000002') -MarketDate '2026-08-28' -MaxProducts 1 -Headless false -DiscoveryAction $discover -CollectAction $collect -MetadataAction $metadata -PostgresAction $postgres -PublishAction $publish | ConvertFrom-Json

        $calls | Should Be @('collect:B000000001:false','postgres:1','publish:amazon-brand-metadata-refresh-v1:1')
        $result.StageCounts.discovered_asins | Should Be 2
        $result.StageCounts.selected_asins | Should Be 1
        $result.StageCounts.collect_or_reuse_products | Should Be 1
        $result.StageCounts.artifact_verified_products | Should Be 1
        $result.StageCounts.receipt_verified_records | Should Be 1
        $result.StageCounts.metadata_merged_rows | Should Be 1
        $result.StageCounts.postgres_imported_rows | Should Be 1
        $result.StageCounts.dashboard_published | Should Be 1
        $result.StageCounts.dashboard_skipped | Should Be 0
        Test-Path (Join-Path $root 'var\brand-enrichment\2026-08-28\amazon-brand-enrichment.json') | Should Be $true
        Test-Path (Join-Path $root 'var\brand-enrichment\2026-08-28\amazon-brand-enrichment-receipt.json') | Should Be $true
    }

    It 'stages injected collection output and atomically promotes a verified artifact and receipt' {
        $root = Join-Path $TestDrive 'staged-success'
        $finalDirectory = Join-Path $root 'var\brand-enrichment\2026-08-28'
        $finalArtifact = Join-Path $finalDirectory 'amazon-brand-enrichment.json'
        $collectedPaths = New-Object Collections.ArrayList
        $artifactJson = (New-TestBrandArtifact -Asins @('B000000001') | ConvertTo-Json -Depth 20)
        $collect = {
            param($ArtifactPath,$Asins,$Headless)
            [void]$collectedPaths.Add($ArtifactPath)
            [IO.File]::WriteAllText($ArtifactPath, $artifactJson, (New-Object Text.UTF8Encoding($false)))
        }.GetNewClosure()
        $discover = { param($SnapshotsRoot) @('B000000001') }
        $metadata = { param($Asins) @([pscustomobject]@{ marketplace_code='AMAZON_US'; asin='B000000001'; product_type='unknown'; classification_confidence='low'; classification_rule_id=$null; classification_rule_version='v1'; classification_evidence=@('NO_SAFE_RULE_MATCH'); raw_brand=$null; normalized_brand=$null; normalized_brand_key=$null; brand_alias_rule_id=$null; brand_source='unknown'; first_seen_market_date='2026-08-28'; last_seen_market_date='2026-08-28' }) }

        & $scriptPath -ProjectRoot $projectRoot -OutputRoot $root -RequestedAsins @('B000000001') -MarketDate '2026-08-28' -DiscoveryAction $discover -CollectAction $collect -MetadataAction $metadata -PostgresAction { param($Rows) } -SkipDashboard | Out-Null

        $collectedPaths.Count | Should Be 1
        $collectedPaths[0] | Should Not Be $finalArtifact
        Test-Path -LiteralPath $finalArtifact -PathType Leaf | Should Be $true
        Test-Path -LiteralPath (Join-Path $finalDirectory 'amazon-brand-enrichment-receipt.json') -PathType Leaf | Should Be $true
        @(Get-ChildItem -LiteralPath $finalDirectory -Force | Where-Object { $_.Name -like '.brand-backfill-*' -or $_.Name -like '*.tmp' }).Count | Should Be 0
    }

    It 'cleans a partial injected artifact without exposing it as reusable output' {
        $root = Join-Path $TestDrive 'staged-failure'
        $finalDirectory = Join-Path $root 'var\brand-enrichment\2026-08-28'
        $discover = { param($SnapshotsRoot) @('B000000001') }
        $collect = {
            param($ArtifactPath,$Asins,$Headless)
            [IO.File]::WriteAllText($ArtifactPath, '{', (New-Object Text.UTF8Encoding($false)))
            throw 'collector interrupted'
        }

        $failure = $null
        try { & $scriptPath -ProjectRoot $projectRoot -OutputRoot $root -RequestedAsins @('B000000001') -MarketDate '2026-08-28' -DiscoveryAction $discover -CollectAction $collect -MetadataAction { param($Asins) @() } -PostgresAction { param($Rows) } -SkipDashboard | Out-Null } catch { $failure = $_ }

        $failure | Should Not Be $null
        Test-Path -LiteralPath (Join-Path $finalDirectory 'amazon-brand-enrichment.json') | Should Be $false
        Test-Path -LiteralPath (Join-Path $finalDirectory 'amazon-brand-enrichment-receipt.json') | Should Be $false
        @(Get-ChildItem -LiteralPath $finalDirectory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '.brand-backfill-*' -or $_.Name -like '*.tmp' }).Count | Should Be 0
    }

    It 'cleans receipt temporary state when atomic receipt commit fails' {
        $root = Join-Path $TestDrive 'receipt-commit-failure'
        $finalDirectory = Join-Path $root 'var\brand-enrichment\2026-08-28'
        $artifactJson = (New-TestBrandArtifact -Asins @('B000000001') | ConvertTo-Json -Depth 20)
        $discover = { param($SnapshotsRoot) @('B000000001') }
        $collect = {
            param($ArtifactPath,$Asins,$Headless)
            [IO.File]::WriteAllText($ArtifactPath, $artifactJson, (New-Object Text.UTF8Encoding($false)))
            New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetDirectoryName($ArtifactPath)) 'amazon-brand-enrichment-receipt.json') -Force | Out-Null
        }.GetNewClosure()

        $failure = $null
        try { & $scriptPath -ProjectRoot $projectRoot -OutputRoot $root -RequestedAsins @('B000000001') -MarketDate '2026-08-28' -DiscoveryAction $discover -CollectAction $collect -MetadataAction { param($Asins) @() } -PostgresAction { param($Rows) } -SkipDashboard | Out-Null } catch { $failure = $_ }

        $failure | Should Not Be $null
        Test-Path -LiteralPath (Join-Path $finalDirectory 'amazon-brand-enrichment.json') | Should Be $false
        Test-Path -LiteralPath (Join-Path $finalDirectory 'amazon-brand-enrichment-receipt.json') | Should Be $false
        @(Get-ChildItem -LiteralPath $finalDirectory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '.brand-backfill-*' -or $_.Name -like '*.tmp' }).Count | Should Be 0
    }

    It 'recovers a validated artifact-only crash state by atomically committing its receipt' {
        $root = Join-Path $TestDrive 'artifact-only-recovery'
        $finalDirectory = Join-Path $root 'var\brand-enrichment\2026-08-28'
        New-Item -ItemType Directory -Path $finalDirectory -Force | Out-Null
        $artifactPath = Join-Path $finalDirectory 'amazon-brand-enrichment.json'
        Write-TestJson -Path $artifactPath -Value (New-TestBrandArtifact -Asins @('B000000001'))
        $calls = New-Object Collections.ArrayList
        $discover = { param($SnapshotsRoot) @('B000000001') }
        $metadata = { param($Asins) @([pscustomobject]@{ marketplace_code='AMAZON_US'; asin='B000000001'; product_type='unknown'; classification_confidence='low'; classification_rule_id=$null; classification_rule_version='v1'; classification_evidence=@('NO_SAFE_RULE_MATCH'); raw_brand=$null; normalized_brand=$null; normalized_brand_key=$null; brand_alias_rule_id=$null; brand_source='unknown'; first_seen_market_date='2026-08-28'; last_seen_market_date='2026-08-28' }) }
        $collect = { param($ArtifactPath,$Asins,$Headless) [void]$calls.Add('collect') }.GetNewClosure()
        $postgres = { param($Rows) [void]$calls.Add('postgres') }.GetNewClosure()

        & $scriptPath -ProjectRoot $projectRoot -OutputRoot $root -RequestedAsins @('B000000001') -MarketDate '2026-08-28' -DiscoveryAction $discover -CollectAction $collect -MetadataAction $metadata -PostgresAction $postgres -SkipDashboard | Out-Null

        $calls | Should Be @('postgres')
        $receiptPath = Join-Path $finalDirectory 'amazon-brand-enrichment-receipt.json'
        Test-Path -LiteralPath $receiptPath -PathType Leaf | Should Be $true
        Import-Module (Join-Path $projectRoot 'src\BestSellersBrandEnrichment.psm1') -Force
        (Test-BestSellersBrandEnrichmentReceipt -ReceiptPath $receiptPath -ArtifactPath $artifactPath -RequestedAsins @('B000000001')).valid | Should Be $true
        @(Get-ChildItem -LiteralPath $finalDirectory -Force | Where-Object { $_.Name -like '.brand-backfill-*' -or $_.Name -like '*.tmp' }).Count | Should Be 0
    }

    It 'keeps PostgreSQL trusted rows separate from artifact-evidence refresh rows' {
        $root = Join-Path $TestDrive 'split-publish-semantics'
        $artifact = [pscustomobject]@{
            schema_version='amazon-brand-enrichment-v1'; marketplace='AMAZON_US'; generated_at='2026-08-28T00:00:00Z'
            products=@(
                [pscustomobject]@{ asin='B000000001'; detail_url='https://www.amazon.com/dp/B000000001'; verification_status='MISSING'; raw_brand=$null; brand_source='unknown'; evidence_source=$null },
                [pscustomobject]@{ asin='B000000002'; detail_url='https://www.amazon.com/dp/B000000002'; verification_status='VERIFIED'; raw_brand='Westinghouse'; brand_source='verified_metadata'; evidence_source='PRODUCT_OVERVIEW_BRAND_FIELD' }
            )
        }
        $artifactJson = $artifact | ConvertTo-Json -Depth 20
        $collect = { param($ArtifactPath,$Asins,$Headless) [IO.File]::WriteAllText($ArtifactPath, $artifactJson, (New-Object Text.UTF8Encoding($false))) }.GetNewClosure()
        $discover = { param($SnapshotsRoot) @('B000000001','B000000002') }
        $metadata = { param($Asins) @(
            [pscustomobject]@{ marketplace_code='AMAZON_US'; asin='B000000001'; product_type='unknown'; classification_confidence='low'; classification_rule_id=$null; classification_rule_version='v1'; classification_evidence=@('NO_SAFE_RULE_MATCH'); raw_brand='Manual Brand'; normalized_brand='Manual Brand'; normalized_brand_key='manual brand'; brand_alias_rule_id=$null; brand_source='manual_review'; first_seen_market_date='2026-08-01'; last_seen_market_date='2026-08-28' },
            [pscustomobject]@{ marketplace_code='AMAZON_US'; asin='B000000002'; product_type='unknown'; classification_confidence='low'; classification_rule_id=$null; classification_rule_version='v1'; classification_evidence=@('NO_SAFE_RULE_MATCH'); raw_brand=$null; normalized_brand=$null; normalized_brand_key=$null; brand_alias_rule_id=$null; brand_source='unknown'; first_seen_market_date='2026-08-01'; last_seen_market_date='2026-08-28' }
        ) }
        $captured = [pscustomobject]@{ PostgresRows=$null; PublishedRows=$null }
        $postgres = { param($Rows) $captured.PostgresRows = @($Rows) }.GetNewClosure()
        $publish = { param($Payload) $captured.PublishedRows = @($Payload.productMetadata) }.GetNewClosure()

        & $scriptPath -ProjectRoot $projectRoot -OutputRoot $root -RequestedAsins @('B000000001','B000000002') -MarketDate '2026-08-28' -DiscoveryAction $discover -CollectAction $collect -MetadataAction $metadata -PostgresAction $postgres -PublishAction $publish | Out-Null

        $captured.PostgresRows[0].brand_source | Should Be 'manual_review'
        $captured.PostgresRows[0].raw_brand | Should Be 'Manual Brand'
        $captured.PublishedRows[0].brandSource | Should Be 'unknown'
        $captured.PublishedRows[0].rawBrand | Should Be $null
        $captured.PostgresRows[1].brand_source | Should Be 'verified_metadata'
        $captured.PublishedRows[1].brandSource | Should Be 'verified_metadata'
        $captured.PublishedRows[1].rawBrand | Should Be 'Westinghouse'
    }

    It 'does not import or publish when collection produces an invalid artifact' {
        $root = Join-Path $TestDrive 'invalid-artifact'; New-Item -ItemType Directory -Path $root -Force | Out-Null
        $calls = New-Object Collections.ArrayList
        $artifactJson = (@{ schema_version='wrong'; products=@() } | ConvertTo-Json -Depth 20)
        $collect = { param($ArtifactPath,$Asins,$Headless) [IO.File]::WriteAllText($ArtifactPath, $artifactJson, (New-Object Text.UTF8Encoding($false))) }.GetNewClosure()
        $postgres = { param($Rows) [void]$calls.Add('postgres') }.GetNewClosure()
        $publish = { param($ArtifactPath,$ReceiptPath) [void]$calls.Add('publish') }.GetNewClosure()
        $discover = { param($SnapshotsRoot) @('B000000001') }

        $thrown = $false
        try { & $scriptPath -ProjectRoot $projectRoot -OutputRoot $root -RequestedAsins @('B000000001') -MarketDate '2026-08-28' -DiscoveryAction $discover -CollectAction $collect -MetadataAction { param($Asins) @() } -PostgresAction $postgres -PublishAction $publish | Out-Null } catch { $thrown = $true }
        $thrown | Should Be $true
        $calls.Count | Should Be 0
        Test-Path -LiteralPath (Join-Path $root 'var\brand-enrichment\2026-08-28\amazon-brand-enrichment.json') | Should Be $false
        @(Get-ChildItem -LiteralPath (Join-Path $root 'var\brand-enrichment\2026-08-28') -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '.brand-backfill-*' -or $_.Name -like '*.tmp' }).Count | Should Be 0
    }

    It 'does not publish after a metadata conflict or PostgreSQL failure' {
        $root = Join-Path $TestDrive 'failed-side-effect'; New-Item -ItemType Directory -Path $root -Force | Out-Null
        $artifactJson = (New-TestBrandArtifact -Asins @('B000000001') | ConvertTo-Json -Depth 20)
        $collect = { param($ArtifactPath,$Asins,$Headless) [IO.File]::WriteAllText($ArtifactPath, $artifactJson, (New-Object Text.UTF8Encoding($false))) }.GetNewClosure()
        $calls = New-Object Collections.ArrayList
        $publish = { param($ArtifactPath,$ReceiptPath) [void]$calls.Add('publish') }.GetNewClosure()
        $discover = { param($SnapshotsRoot) @('B000000001') }

        $thrown = $false
        try { & $scriptPath -ProjectRoot $projectRoot -OutputRoot $root -RequestedAsins @('B000000001') -MarketDate '2026-08-28' -DiscoveryAction $discover -CollectAction $collect -MetadataAction { throw 'brand conflict' } -PostgresAction { param($Rows) } -PublishAction $publish | Out-Null } catch { $thrown = $true }
        $thrown | Should Be $true
        $calls.Count | Should Be 0
        $thrown = $false
        try { & $scriptPath -ProjectRoot $projectRoot -OutputRoot (Join-Path $TestDrive 'database-failure') -RequestedAsins @('B000000001') -MarketDate '2026-08-28' -DiscoveryAction $discover -CollectAction $collect -MetadataAction { param($Asins) @() } -PostgresAction { param($Rows) throw 'db failed' } -PublishAction $publish | Out-Null } catch { $thrown = $true }
        $thrown | Should Be $true
        $calls.Count | Should Be 0
    }

    It 'refuses to reuse an existing date directory for a different requested ASIN set' {
        $root = Join-Path $TestDrive 'rerun'; $output = Join-Path $root 'var\brand-enrichment\2026-08-28'
        New-Item -ItemType Directory -Path $output -Force | Out-Null
        $artifactPath = Join-Path $output 'amazon-brand-enrichment.json'
        Write-TestJson -Path $artifactPath -Value (New-TestBrandArtifact -Asins @('B000000001'))
        Import-Module (Join-Path $projectRoot 'src\BestSellersBrandEnrichment.psm1') -Force
        $receiptPath = Join-Path $output 'amazon-brand-enrichment-receipt.json'
        Write-TestJson -Path $receiptPath -Value (New-BestSellersBrandEnrichmentReceipt -ArtifactPath $artifactPath -RequestedAsins @('B000000001'))
        $artifactHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash
        $receiptHash = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash
        $calls = New-Object Collections.ArrayList
        $collect = { param($ArtifactPath,$Asins,$Headless) [void]$calls.Add('collect') }.GetNewClosure()
        $discover = { param($SnapshotsRoot) @('B000000001','B000000002') }

        $thrown = $false
        try { & $scriptPath -ProjectRoot $projectRoot -OutputRoot $root -RequestedAsins @('B000000002') -MarketDate '2026-08-28' -DiscoveryAction $discover -CollectAction $collect -MetadataAction { param($Asins) @() } -PostgresAction { param($Rows) } -SkipDashboard | Out-Null } catch { $thrown = $true }
        $thrown | Should Be $true
        $calls.Count | Should Be 0
        (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash | Should Be $artifactHash
        (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash | Should Be $receiptHash
        @(Get-ChildItem -LiteralPath $output -Force | Where-Object { $_.Name -like '.brand-backfill-*' -or $_.Name -like '*.tmp' }).Count | Should Be 0
    }

    It 'rejects requested ASINs outside the verified historical cohort before all downstream side effects' {
        $root = Join-Path $TestDrive 'unverified-request'; New-Item -ItemType Directory -Path $root -Force | Out-Null
        $calls = New-Object Collections.ArrayList
        $discover = { param($SnapshotsRoot) @('B000000001') }
        $collect = { param($ArtifactPath,$Asins,$Headless) [void]$calls.Add('collect') }.GetNewClosure()
        $postgres = { param($Rows) [void]$calls.Add('postgres') }.GetNewClosure()
        $publish = { param($ArtifactPath,$ReceiptPath) [void]$calls.Add('publish') }.GetNewClosure()

        $thrown = $false
        try { & $scriptPath -ProjectRoot $projectRoot -OutputRoot $root -RequestedAsins @('B000000099') -MarketDate '2026-08-28' -DiscoveryAction $discover -CollectAction $collect -MetadataAction { param($Asins) @() } -PostgresAction $postgres -PublishAction $publish | Out-Null } catch { $thrown = $true }

        $thrown | Should Be $true
        $calls.Count | Should Be 0
    }
}
