$modulePath = Join-Path $PSScriptRoot '..\src\BestSellersBrandEnrichment.psm1'
Import-Module $modulePath -Force
Import-Module (Join-Path $PSScriptRoot '..\src\BestSellersCaptureReceipt.psm1') -Force

function Write-Utf8Json {
    param([string]$Path, $Value)
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
}

function New-EnrichmentArtifact {
    param([object[]]$Products)
    return [pscustomobject]@{
        schema_version = 'amazon-brand-enrichment-v1'
        marketplace = 'AMAZON_US'
        generated_at = '2026-08-28T00:00:00Z'
        products = $Products
    }
}

Describe 'Best Sellers brand enrichment artifacts and receipts' {

    It 'validates a sorted one-result-per-request artifact and binds its receipt to exact bytes' {
        $artifactPath = Join-Path $TestDrive 'amazon-brand-enrichment.json'
        Write-Utf8Json -Path $artifactPath -Value (New-EnrichmentArtifact -Products @(
            [pscustomobject]@{ asin='B000000001'; detail_url='https://www.amazon.com/dp/B000000001'; verification_status='VERIFIED'; raw_brand='WESTINGHOUSE Outdoor Power Equipment'; brand_source='verified_metadata'; evidence_source='PRODUCT_OVERVIEW_BRAND_FIELD' },
            [pscustomobject]@{ asin='B000000002'; detail_url='https://www.amazon.com/dp/B000000002'; verification_status='MISSING'; raw_brand=$null; brand_source='unknown'; evidence_source=$null }
        ))

        $artifact = Test-BestSellersBrandEnrichmentArtifact -ArtifactPath $artifactPath -RequestedAsins @('B000000002', 'B000000001', 'B000000001')
        $artifact.valid | Should Be $true
        @($artifact.products | ForEach-Object asin) | Should Be @('B000000001', 'B000000002')

        $receipt = New-BestSellersBrandEnrichmentReceipt -ArtifactPath $artifactPath -RequestedAsins @('B000000001', 'B000000002') -GeneratedAt ([datetimeoffset]'2026-08-28T00:00:00Z')
        $receipt.artifact_sha256 | Should Match '^[0-9a-f]{64}$'
        $receipt.requested_asin_set_sha256 | Should Be (Get-BestSellersBrandAsinSetHash -Asins @('B000000002', 'B000000001'))
        $receipt.record_count | Should Be 2
        $receipt.status_counts.VERIFIED | Should Be 1
        $receipt.status_counts.MISSING | Should Be 1
        $receipt.status_counts.CONFLICT | Should Be 0
        $receipt.status_counts.IDENTITY_MISMATCH | Should Be 0
        $receipt.status_counts.VERIFICATION_BLOCKED | Should Be 0
        $receipt.generated_at | Should Be '2026-08-28T00:00:00.0000000+00:00'

        $receiptPath = Join-Path $TestDrive 'amazon-brand-enrichment-receipt.json'
        Write-Utf8Json -Path $receiptPath -Value $receipt
        (Test-BestSellersBrandEnrichmentReceipt -ReceiptPath $receiptPath -ArtifactPath $artifactPath -RequestedAsins @('B000000001', 'B000000002')).valid | Should Be $true
    }

    It 'rejects an artifact whose requested ASINs are not sorted unique one-for-one products' {
        $artifactPath = Join-Path $TestDrive 'bad-enrichment.json'
        Write-Utf8Json -Path $artifactPath -Value (New-EnrichmentArtifact -Products @(
            [pscustomobject]@{ asin='B000000002'; detail_url='https://www.amazon.com/dp/B000000002'; verification_status='MISSING'; raw_brand=$null; brand_source='unknown'; evidence_source=$null },
            [pscustomobject]@{ asin='B000000001'; detail_url='https://www.amazon.com/dp/B000000001'; verification_status='MISSING'; raw_brand=$null; brand_source='unknown'; evidence_source=$null }
        ))

        (Test-BestSellersBrandEnrichmentArtifact -ArtifactPath $artifactPath -RequestedAsins @('B000000001', 'B000000002')).valid | Should Be $false
    }

    It 'rejects verified artifact brands containing BOM dotted-I or NEL characters' {
        $invalidBrands = @(
            ([string][char]0xFEFF + 'Brand'),
            ([string][char]0x0130 + 'stanbul'),
            ('Brand' + [char]0x0085 + 'Name')
        )

        for ($index = 0; $index -lt $invalidBrands.Count; $index++) {
            $artifactPath = Join-Path $TestDrive ("nonportable-$index.json")
            Write-Utf8Json -Path $artifactPath -Value (New-EnrichmentArtifact -Products @(
                [pscustomobject]@{ asin='B000000001'; detail_url='https://www.amazon.com/dp/B000000001'; verification_status='VERIFIED'; raw_brand=$invalidBrands[$index]; brand_source='verified_metadata'; evidence_source='PRODUCT_OVERVIEW_BRAND_FIELD' }
            ))

            $verification = Test-BestSellersBrandEnrichmentArtifact -ArtifactPath $artifactPath -RequestedAsins @('B000000001')
            $verification.valid | Should Be $false
            ($verification.errors -join '; ') | Should Match 'portable normalization boundary'
        }
    }

    It 'uses the ordinal LF-delimited ASIN set hash' {
        (Get-BestSellersBrandAsinSetHash -Asins @('B000000002', 'B000000001', 'B000000002')) | Should Be 'c430287b2ad78ecd3929c86575fea7218d341ebbb9fe8ce1bc55fa876aeb614b'
    }

    It 'refuses a receipt when artifact bytes change after its hash was recorded' {
        $artifactPath = Join-Path $TestDrive 'tampered-enrichment.json'
        $artifact = New-EnrichmentArtifact -Products @([pscustomobject]@{ asin='B000000001'; detail_url='https://www.amazon.com/dp/B000000001'; verification_status='MISSING'; raw_brand=$null; brand_source='unknown'; evidence_source=$null })
        Write-Utf8Json -Path $artifactPath -Value $artifact
        $receipt = New-BestSellersBrandEnrichmentReceipt -ArtifactPath $artifactPath -RequestedAsins @('B000000001')
        $receiptPath = Join-Path $TestDrive 'tampered-receipt.json'
        Write-Utf8Json -Path $receiptPath -Value $receipt
        [IO.File]::AppendAllText($artifactPath, "`n", (New-Object Text.UTF8Encoding($false)))

        (Test-BestSellersBrandEnrichmentReceipt -ReceiptPath $receiptPath -ArtifactPath $artifactPath -RequestedAsins @('B000000001')).valid | Should Be $false
    }

    It 'requires every bounded verification status count even when its value is zero' {
        $artifactPath = Join-Path $TestDrive 'zero-count-enrichment.json'
        $artifact = New-EnrichmentArtifact -Products @([pscustomobject]@{ asin='B000000001'; detail_url='https://www.amazon.com/dp/B000000001'; verification_status='MISSING'; raw_brand=$null; brand_source='unknown'; evidence_source=$null })
        Write-Utf8Json -Path $artifactPath -Value $artifact
        $receipt = New-BestSellersBrandEnrichmentReceipt -ArtifactPath $artifactPath -RequestedAsins @('B000000001')
        $receipt.status_counts.PSObject.Properties.Remove('VERIFICATION_BLOCKED')
        $receiptPath = Join-Path $TestDrive 'zero-count-receipt.json'
        Write-Utf8Json -Path $receiptPath -Value $receipt

        (Test-BestSellersBrandEnrichmentReceipt -ReceiptPath $receiptPath -ArtifactPath $artifactPath -RequestedAsins @('B000000001')).valid | Should Be $false
    }
}

Describe 'Best Sellers brand metadata refresh publishing' {
    function New-RefreshMetadataRow {
        param([string]$Asin, $RawBrand = $null)

        [pscustomobject]@{
            marketplace_code='AMAZON_US'; asin=$Asin; product_type='unknown'; classification_confidence='low'; classification_rule_id=$null; classification_rule_version='product-rules-v1'; classification_evidence=@('NO_SAFE_RULE_MATCH')
            raw_brand=$RawBrand; normalized_brand=$RawBrand; normalized_brand_key=$(if ($null -eq $RawBrand) { $null } else { $RawBrand.ToLowerInvariant() }); brand_alias_rule_id=$null; brand_source=$(if ($null -eq $RawBrand) { 'unknown' } else { 'verified_metadata' }); first_seen_market_date='2026-08-01'; last_seen_market_date='2026-08-28'
        }
    }

    It 'builds a refresh payload with the exact artifact UTF-8 text, matching receipt, and complete metadata cohort' {
        $artifactPath = Join-Path $TestDrive 'noncanonical-brand-enrichment.json'
        $artifactText = @'

{
  "schema_version": "amazon-brand-enrichment-v1",
  "marketplace": "AMAZON_US",
  "generated_at": "2026-08-28T00:00:00Z",
  "products": [
    { "asin": "B000000001", "detail_url": "https://www.amazon.com/dp/B000000001", "verification_status": "VERIFIED", "raw_brand": "Westinghouse", "brand_source": "verified_metadata", "evidence_source": "PRODUCT_OVERVIEW_BRAND_FIELD" },
    { "asin": "B000000002", "detail_url": "https://www.amazon.com/dp/B000000002", "verification_status": "MISSING", "raw_brand": null, "brand_source": "unknown", "evidence_source": null }
  ]
}
'@
        [IO.File]::WriteAllText($artifactPath, $artifactText, (New-Object Text.UTF8Encoding($false)))
        $receiptPath = Join-Path $TestDrive 'amazon-brand-enrichment-receipt.json'
        Write-Utf8Json -Path $receiptPath -Value (New-BestSellersBrandEnrichmentReceipt -ArtifactPath $artifactPath -RequestedAsins @('B000000001','B000000002'))

        $payload = New-BestSellersBrandMetadataRefreshPayload -ArtifactPath $artifactPath -ReceiptPath $receiptPath -MetadataRows @(
            (New-RefreshMetadataRow -Asin 'B000000001' -RawBrand 'Westinghouse'),
            (New-RefreshMetadataRow -Asin 'B000000002')
        )

        $payload.schemaVersion | Should Be 'amazon-brand-metadata-refresh-v1'
        $payload.marketplace | Should Be 'AMAZON_US'
        $payload.artifactJson | Should Be $artifactText
        $payload.artifactSha256 | Should Be $payload.receipt.artifact_sha256
        @($payload.productMetadata | ForEach-Object asin) | Should Be @('B000000001','B000000002')
        $payload.productMetadata[0].rawBrand | Should Be 'Westinghouse'
        $payload.productMetadata[1].brandSource | Should Be 'unknown'
    }

    It 'publishes artifact-unknown rows as null even when PostgreSQL merge rows retain trusted brands' {
        $artifactPath = Join-Path $TestDrive 'mixed-brand-evidence.json'
        Write-Utf8Json -Path $artifactPath -Value (New-EnrichmentArtifact -Products @(
            [pscustomobject]@{ asin='B000000001'; detail_url='https://www.amazon.com/dp/B000000001'; verification_status='MISSING'; raw_brand=$null; brand_source='unknown'; evidence_source=$null },
            [pscustomobject]@{ asin='B000000002'; detail_url='https://www.amazon.com/dp/B000000002'; verification_status='IDENTITY_MISMATCH'; raw_brand=$null; brand_source='unknown'; evidence_source=$null },
            [pscustomobject]@{ asin='B000000003'; detail_url='https://www.amazon.com/dp/B000000003'; verification_status='VERIFIED'; raw_brand='Westinghouse'; brand_source='verified_metadata'; evidence_source='PRODUCT_OVERVIEW_BRAND_FIELD' }
        ))
        $receiptPath = Join-Path $TestDrive 'mixed-brand-evidence-receipt.json'
        Write-Utf8Json -Path $receiptPath -Value (New-BestSellersBrandEnrichmentReceipt -ArtifactPath $artifactPath -RequestedAsins @('B000000001','B000000002','B000000003'))
        $manual = New-RefreshMetadataRow -Asin 'B000000001' -RawBrand 'Manual Brand'
        $manual.brand_source = 'manual_review'
        $verifiedExisting = New-RefreshMetadataRow -Asin 'B000000002' -RawBrand 'Existing Brand'
        $verifiedIncoming = New-RefreshMetadataRow -Asin 'B000000003' -RawBrand 'Westinghouse'

        $payload = New-BestSellersBrandMetadataRefreshPayload -ArtifactPath $artifactPath -ReceiptPath $receiptPath -MetadataRows @($manual, $verifiedExisting, $verifiedIncoming)

        $manual.brand_source | Should Be 'manual_review'
        $verifiedExisting.brand_source | Should Be 'verified_metadata'
        foreach ($row in @($payload.productMetadata | Where-Object { $_.asin -in @('B000000001','B000000002') })) {
            $row.rawBrand | Should Be $null
            $row.normalizedBrand | Should Be $null
            $row.normalizedBrandKey | Should Be $null
            $row.brandAliasRuleId | Should Be $null
            $row.brandSource | Should Be 'unknown'
        }
        $payload.productMetadata[2].rawBrand | Should Be 'Westinghouse'
        $payload.productMetadata[2].normalizedBrand | Should Be 'Westinghouse'
        $payload.productMetadata[2].brandSource | Should Be 'verified_metadata'
    }

    It 'rejects a non-portable canonical brand at the artifact-to-metadata boundary' {
        $artifactPath = Join-Path $TestDrive 'portable-payload-artifact.json'
        Write-Utf8Json -Path $artifactPath -Value (New-EnrichmentArtifact -Products @(
            [pscustomobject]@{ asin='B000000001'; detail_url='https://www.amazon.com/dp/B000000001'; verification_status='VERIFIED'; raw_brand='Westinghouse'; brand_source='verified_metadata'; evidence_source='PRODUCT_OVERVIEW_BRAND_FIELD' }
        ))
        $receiptPath = Join-Path $TestDrive 'portable-payload-receipt.json'
        Write-Utf8Json -Path $receiptPath -Value (New-BestSellersBrandEnrichmentReceipt -ArtifactPath $artifactPath -RequestedAsins @('B000000001'))
        $row = New-RefreshMetadataRow -Asin 'B000000001' -RawBrand 'Westinghouse'
        $row.normalized_brand = [string][char]0x0130 + 'stanbul'

        $failure = $null
        try { New-BestSellersBrandMetadataRefreshPayload -ArtifactPath $artifactPath -ReceiptPath $receiptPath -MetadataRows @($row) | Out-Null } catch { $failure = $_ }

        $failure | Should Not Be $null
        $failure.Exception.Message | Should Be 'Verified product metadata contains non-portable brand text for ASIN B000000001.'
    }

    It 'fails closed when a UTF-8 BOM makes the artifact byte hash differ from its publishable text' {
        $artifactPath = Join-Path $TestDrive 'bom-brand-enrichment.json'
        $artifactText = '{"schema_version":"amazon-brand-enrichment-v1","marketplace":"AMAZON_US","generated_at":"2026-08-28T00:00:00Z","products":[{"asin":"B000000001","detail_url":"https://www.amazon.com/dp/B000000001","verification_status":"MISSING","raw_brand":null,"brand_source":"unknown","evidence_source":null}]}'
        [IO.File]::WriteAllText($artifactPath, $artifactText, (New-Object Text.UTF8Encoding($true)))
        $receiptPath = Join-Path $TestDrive 'bom-brand-enrichment-receipt.json'
        Write-Utf8Json -Path $receiptPath -Value (New-BestSellersBrandEnrichmentReceipt -ArtifactPath $artifactPath -RequestedAsins @('B000000001'))

        $failure = $null
        try { New-BestSellersBrandMetadataRefreshPayload -ArtifactPath $artifactPath -ReceiptPath $receiptPath -MetadataRows @(New-RefreshMetadataRow -Asin 'B000000001') | Out-Null } catch { $failure = $_ }
        $failure | Should Not Be $null
        $failure.Exception.Message | Should Be 'Brand enrichment artifact must be UTF-8 without a BOM.'
    }

    It 'uses the shared bearer and UTF-8 request parameters at the product metadata endpoint without leaking a rejected secret' {
        $previousSecret = [Environment]::GetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'Process')
        [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'test-secret', 'Process')
        try {
            $payload = [pscustomobject]@{ schemaVersion='amazon-brand-metadata-refresh-v1'; marketplace='AMAZON_US'; artifactJson="`n{}"; artifactSha256=('a' * 64); receipt=[pscustomobject]@{}; productMetadata=@() }
            $request = Invoke-BestSellersBrandMetadataRefreshPublish -DashboardUrl 'https://example.test/' -Payload $payload -RestAction { param($Parameters) $Parameters }

            $request.Uri.AbsoluteUri | Should Be 'https://example.test/api/sync/v1/product-metadata'
            $request.Headers.Authorization | Should Be 'Bearer test-secret'
            $request.ContentType | Should Be 'application/json; charset=utf-8'
            ([Text.Encoding]::UTF8.GetString($request.Body) | ConvertFrom-Json).artifactJson | Should Be "`n{}"

            $failure = $null
            try { Invoke-BestSellersBrandMetadataRefreshPublish -DashboardUrl 'https://example.test/' -Payload $payload -RestAction { throw 'remote failure: Bearer test-secret' } | Out-Null } catch { $failure = $_ }
            $failure | Should Not Be $null
            $failure.Exception.Message | Should Be 'Brand metadata refresh publication failed.'
            $failure.Exception.Message | Should Not Match 'test-secret'

            $failure = $null
            try { Invoke-BestSellersBrandMetadataRefreshPublish -DashboardUrl 'https://example.test/' -Payload $payload -RestAction { [pscustomobject]@{ StatusCode = 422 } } | Out-Null } catch { $failure = $_ }
            $failure | Should Not Be $null
            $failure.Exception.Message | Should Be 'Brand metadata refresh publication failed.'
        }
        finally {
            [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', $previousSecret, 'Process')
        }
    }
}

Describe 'Best Sellers verified historical ASIN selection' {
    It 'returns a sorted distinct ASIN cohort from receipt-verified exact Top 30 snapshots only' {
        $historyRoot = Join-Path $TestDrive 'history'
        $day = Join-Path $historyRoot '2026-08-28'
        New-Item -ItemType Directory -Path $day -Force | Out-Null
        $sourceConfigPath = Join-Path $PSScriptRoot '..\config\best-sellers-sources.json'
        $sources = Get-Content -LiteralPath $sourceConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $items = @(1..30 | ForEach-Object { [pscustomobject]@{ rank=$_; asin=('B' + $_.ToString('000000000')); title='Verified history item'; price=$null; rating=$null; reviews=$null } })
        $snapshot = [pscustomobject]@{
            market_date='2026-08-28'; observed_at='2026-08-28T00:00:00Z'
            sources=[pscustomobject]@{ pressure_washers=$sources.sources[0].url; pressure_washer_accessories=$sources.sources[2].url; sump_pumps=$sources.sources[1].url }
            pressure_washers=$items; pressure_washer_accessories=$items; sump_pumps=$items
        }
        $snapshotPath = Join-Path $day 'amazon-bestsellers.json'
        Write-Utf8Json -Path $snapshotPath -Value $snapshot
        $captureReceipt = New-BestSellersCaptureReceipt -SnapshotPath $snapshotPath -SourceConfigPath $sourceConfigPath
        Write-BestSellersCaptureReceipt -Receipt $captureReceipt -Path (Join-Path $day 'best-sellers-capture-receipt.json') | Out-Null

        $asins = @(Get-BestSellersVerifiedHistoryAsins -SnapshotsRoot $historyRoot)
        $asins.Count | Should Be 30
        $asins[0] | Should Be 'B000000001'
        $asins[-1] | Should Be 'B000000030'
    }
}

Describe 'Best Sellers brand enrichment metadata merge' {
    $brandPath = Join-Path $PSScriptRoot '..\config\v2-brand-aliases.json'

    function New-MetadataRow {
        param([string]$Asin, [string]$Source = 'unknown', [AllowNull()]$RawBrand = $null, [AllowNull()]$NormalizedKey = $null)
        [pscustomobject]@{
            marketplace_code='AMAZON_US'; asin=$Asin; product_type='gas_pressure_washer'; classification_confidence='high'; classification_rule_id='machine-gas'; classification_rule_version='product-rules-v1'; classification_evidence=@('TITLE_RULE:machine-gas')
            raw_brand=$RawBrand; normalized_brand=$RawBrand; normalized_brand_key=$NormalizedKey; brand_alias_rule_id=$null; brand_source=$Source; first_seen_market_date='2026-08-01'; last_seen_market_date='2026-08-28'
        }
    }

    function New-ArtifactProduct {
        param([string]$Asin, [string]$Status = 'VERIFIED', [string]$Brand = 'WESTINGHOUSE Outdoor Power Equipment')
        [pscustomobject]@{ asin=$Asin; detail_url="https://www.amazon.com/dp/$Asin"; verification_status=$Status; raw_brand=$(if ($Status -eq 'VERIFIED') { $Brand } else { $null }); brand_source=$(if ($Status -eq 'VERIFIED') { 'verified_metadata' } else { 'unknown' }); evidence_source=$(if ($Status -eq 'VERIFIED') { 'PRODUCT_OVERVIEW_BRAND_FIELD' } else { $null }) }
    }

    It 'converts only VERIFIED evidence through the authoritative normalization function and preserves full metadata' {
        $rows = @(New-MetadataRow -Asin 'B000000001'; New-MetadataRow -Asin 'B000000002')
        $artifact = New-EnrichmentArtifact -Products @((New-ArtifactProduct -Asin 'B000000001'), (New-ArtifactProduct -Asin 'B000000002' -Status 'VERIFICATION_BLOCKED'))

        $merged = @(Merge-BestSellersBrandEnrichmentMetadata -MetadataRows $rows -Artifact $artifact -BrandAliasConfigPath $brandPath)
        $verified = @($merged | Where-Object asin -eq 'B000000001')[0]
        $blocked = @($merged | Where-Object asin -eq 'B000000002')[0]
        $verified.raw_brand | Should Be 'WESTINGHOUSE Outdoor Power Equipment'
        $verified.normalized_brand | Should Be 'Westinghouse'
        $verified.normalized_brand_key | Should Be 'westinghouse'
        $verified.brand_source | Should Be 'verified_metadata'
        $verified.product_type | Should Be 'gas_pressure_washer'
        $verified.classification_confidence | Should Be 'high'
        $verified.first_seen_market_date | Should Be '2026-08-01'
        $verified.last_seen_market_date | Should Be '2026-08-28'
        $blocked.brand_source | Should Be 'unknown'
        ($null -eq $blocked.raw_brand) | Should Be $true
    }

    It 'fails closed before returning any rows when a new verified brand conflicts with verified metadata' {
        $rows = @(New-MetadataRow -Asin 'B000000001' -Source 'verified_metadata' -RawBrand 'Another Brand' -NormalizedKey 'another brand')
        $artifact = New-EnrichmentArtifact -Products @((New-ArtifactProduct -Asin 'B000000001'))

        $failure = $null
        try { @(Merge-BestSellersBrandEnrichmentMetadata -MetadataRows $rows -Artifact $artifact -BrandAliasConfigPath $brandPath) | Out-Null } catch { $failure = $_ }
        $failure | Should Not Be $null
        $failure.Exception.Message | Should Be 'Brand conflict for ASIN B000000001.'
    }

    It 'rejects verified-looking title-inference evidence before producing metadata rows' {
        $rows = @(New-MetadataRow -Asin 'B000000001')
        $product = New-ArtifactProduct -Asin 'B000000001'
        $product.evidence_source = 'TITLE_INFERENCE'
        $artifact = New-EnrichmentArtifact -Products @($product)

        $failure = $null
        try { @(Merge-BestSellersBrandEnrichmentMetadata -MetadataRows $rows -Artifact $artifact -BrandAliasConfigPath $brandPath) | Out-Null } catch { $failure = $_ }
        $failure | Should Not Be $null
        $failure.Exception.Message | Should Be 'Verified artifact product B000000001 has invalid provenance.'
    }

    It 'does not let unknown evidence overwrite a manual verified brand' {
        $rows = @(New-MetadataRow -Asin 'B000000001' -Source 'manual_review' -RawBrand 'Manual Brand' -NormalizedKey 'manual brand')
        $artifact = New-EnrichmentArtifact -Products @((New-ArtifactProduct -Asin 'B000000001' -Status 'MISSING'))

        $merged = @(Merge-BestSellersBrandEnrichmentMetadata -MetadataRows $rows -Artifact $artifact -BrandAliasConfigPath $brandPath)
        $merged[0].raw_brand | Should Be 'Manual Brand'
        $merged[0].brand_source | Should Be 'manual_review'
    }
}
