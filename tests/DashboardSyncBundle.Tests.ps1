$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src\DashboardSyncBundle.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersAnalysis.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersCaptureReceipt.psm1') -Force

Describe 'Dashboard sync observation normalization' {
    It 'converts collector display metrics into the numeric public API contract' {
        $input = [pscustomobject]@{
            rank = 1
            asin = 'B0TEST0001'
            title = 'Test product'
            url = 'https://www.amazon.com/dp/B0TEST0001'
            price = '$1,299.99'
            rating = [decimal]4.6
            reviews = '1,234'
        }

        $result = ConvertTo-DashboardSyncObservation -Observation $input

        $result.price | Should Be 1299.99
        $result.price.GetType().Name | Should Be 'Double'
        $result.rating | Should Be 4.6
        $result.rating.GetType().Name | Should Be 'Double'
        $result.reviews | Should Be 1234
        $result.reviews.GetType().Name | Should Be 'Int64'
    }

    It 'keeps missing metrics null instead of inventing values' {
        $input = [pscustomobject]@{
            rank = 2
            asin = 'B0TEST0002'
            title = 'Missing metrics'
            url = 'https://www.amazon.com/dp/B0TEST0002'
            price = $null
            rating = $null
            reviews = $null
        }

        $result = ConvertTo-DashboardSyncObservation -Observation $input

        $result.price | Should Be $null
        $result.rating | Should Be $null
        $result.reviews | Should Be $null
    }
}

Describe 'Dashboard sync product metadata cohort' {
    function New-DashboardMetadataRows {
        param(
            [Parameter(Mandatory=$true)][string]$AsinPrefix,
            [Parameter(Mandatory=$true)][string]$Title,
            [hashtable]$FirstProperties = @{},
            [int]$Count = 30
        )

        return @(1..$Count | ForEach-Object {
            $row = [ordered]@{
                rank = $_
                asin = "$AsinPrefix$($_.ToString('000000000'))"
                title = $Title
                url = "https://www.amazon.com/dp/$AsinPrefix$($_.ToString('000000000'))"
            }
            if ($_ -eq 1) {
                foreach ($key in $FirstProperties.Keys) { $row[$key] = $FirstProperties[$key] }
            }
            [pscustomobject]$row
        })
    }

    function New-DashboardMetadataSnapshot {
        param(
            [bool]$PersistedComplete = $true,
            [hashtable]$PressureFirstProperties = @{},
            [int]$PressureCount = 30
        )

        return [pscustomobject]@{
            marketplace = 'AMAZON_US'
            market_date = '2026-08-12'
            persisted_complete = $PersistedComplete
            pressure_washers = New-DashboardMetadataRows -AsinPrefix 'P' -Title 'Electric pressure washer' -FirstProperties $PressureFirstProperties -Count $PressureCount
            pressure_washer_accessories = New-DashboardMetadataRows -AsinPrefix 'A' -Title 'Pressure washer surface cleaner'
            sump_pumps = New-DashboardMetadataRows -AsinPrefix 'S' -Title 'Sump pump'
        }
    }

    function New-DashboardReceiptFixture {
        param(
            [string]$Name,
            [bool]$Complete = $true,
            [bool]$IncludeSourceMetadata = $true
        )

        $directory = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $snapshotPath = Join-Path $directory 'amazon-bestsellers.json'
        $snapshot = Get-Content -LiteralPath (Join-Path $projectRoot 'web\data\verified-snapshot-2026-08-12.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $Complete) {
            foreach ($category in @('pressure_washers','sump_pumps','pressure_washer_accessories')) { $snapshot.$category = @($snapshot.$category | Select-Object -First 29) }
        }
        if (-not $IncludeSourceMetadata) { $snapshot.PSObject.Properties.Remove('sources') }
        [IO.File]::WriteAllText($snapshotPath, ($snapshot | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
        $receiptPath = Join-Path $directory 'best-sellers-capture-receipt.json'
        $receipt = New-BestSellersCaptureReceipt -SnapshotPath $snapshotPath -SourceConfigPath (Join-Path $projectRoot 'config\best-sellers-sources.json')
        Write-BestSellersCaptureReceipt -Receipt $receipt -Path $receiptPath | Out-Null
        return [pscustomobject]@{ snapshot_path=$snapshotPath; receipt_path=$receiptPath; receipt=$receipt }
    }

    It 'authorizes only a complete category from a partial capture without authorizing the full day' {
        $fixture = New-DashboardReceiptFixture -Name 'isolated-category'
        $snapshot = Get-Content $fixture.snapshot_path -Raw -Encoding UTF8 | ConvertFrom-Json
        $snapshot.pressure_washers = @($snapshot.pressure_washers | Select-Object -First 29)
        [IO.File]::WriteAllText($fixture.snapshot_path,($snapshot | ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding($false)))
        $receipt = New-BestSellersCaptureReceipt -SnapshotPath $fixture.snapshot_path -SourceConfigPath (Join-Path $projectRoot 'config\best-sellers-sources.json')
        Write-BestSellersCaptureReceipt -Receipt $receipt -Path $fixture.receipt_path | Out-Null
        $result = & (Join-Path $projectRoot 'scripts\New-DashboardSyncBundle.ps1') -SnapshotPath $fixture.snapshot_path -CategoryKey sump_pumps | ConvertFrom-Json
        $bundle = Get-Content $result.BundlePath -Raw -Encoding UTF8 | ConvertFrom-Json
        @($bundle.categories).Count | Should Be 1
        $bundle.categories[0].key | Should Be 'sump_pumps'
        @($bundle.categories[0].observations).Count | Should Be 30
        @($bundle.productMetadata).Count | Should Be 30
        $bundle.receiptSha256 | Should Be $receipt.snapshot_sha256
        $analysis = & (Join-Path $projectRoot 'scripts\New-OnlineAnalysisReports.ps1') -SnapshotPath $fixture.snapshot_path -SnapshotsRoot $TestDrive -OutputRoot (Join-Path $TestDrive 'scoped-analysis') -CategoryKey sump_pumps | ConvertFrom-Json
        $analysis.ReportCount | Should Be 1
        $analysisReport = Get-Content $analysis.ReportPaths[0] -Raw -Encoding UTF8 | ConvertFrom-Json
        $analysisReport.categoryKey | Should Be 'sump_pumps'
        $analysisReport.receiptSha256 | Should Be $receipt.snapshot_sha256
        $analysisReport.evidence.completeMarketDays | Should Be 1
        $seller = & (Join-Path $projectRoot 'scripts\New-SellerIntelligenceReports.ps1') -SnapshotPath $fixture.snapshot_path -SnapshotsRoot $TestDrive -OutputRoot (Join-Path $TestDrive 'scoped-seller') -CategoryKey sump_pumps | ConvertFrom-Json
        $seller.ReportCount | Should Be 1
        $sellerReport = Get-Content $seller.ReportPaths[0] -Raw -Encoding UTF8 | ConvertFrom-Json
        $sellerReport.categoryKey | Should Be 'sump_pumps'
        $sellerReport.evidence.complete | Should Be $true
        $fullRejected = $false
        try { Resolve-BestSellersAuthorizedSnapshot -SnapshotPath $fixture.snapshot_path -ReceiptPath $fixture.receipt_path | Out-Null } catch { $fullRejected = $true }
        $fullRejected | Should Be $true
        $partialRejected = $false
        try { Resolve-BestSellersAuthorizedSnapshot -SnapshotPath $fixture.snapshot_path -ReceiptPath $fixture.receipt_path -CategoryKey pressure_washers | Out-Null } catch { $partialRejected = $true }
        $partialRejected | Should Be $true
    }

    It 'builds a v2 bundle with one metadata row per unique snapshot ASIN' {
        $snapshotPath = Join-Path $TestDrive 'amazon-bestsellers.json'
        Copy-Item -LiteralPath (Join-Path $projectRoot 'web\data\verified-snapshot-2026-08-12.json') -Destination $snapshotPath
        & (Join-Path $projectRoot 'scripts\Register-BestSellersSnapshot.ps1') -SnapshotPath $snapshotPath | Out-Null

        $result = & (Join-Path $projectRoot 'scripts\New-DashboardSyncBundle.ps1') -SnapshotPath $snapshotPath | ConvertFrom-Json
        $bundleJson = Get-Content -LiteralPath $result.BundlePath -Raw
        $bundle = $bundleJson | ConvertFrom-Json
        $snapshot = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json
        $allObservations = @($snapshot.pressure_washers) + @($snapshot.sump_pumps) + @($snapshot.pressure_washer_accessories)
        $expectedAsins = @($allObservations | ForEach-Object { [string]$_.asin } | Sort-Object -Unique)

        $allObservations.Count | Should Be 90
        $expectedAsins.Count | Should Be 83
        $bundle.schemaVersion | Should Be 'amazon-bs-dashboard-bundle-v2'
        $bundleJson | Should Match '"observedAt"\s*:\s*"2026-08-13T00:00:03\.307Z"'
        $receipt = Get-Content -LiteralPath (Join-Path $TestDrive 'best-sellers-capture-receipt.json') -Raw | ConvertFrom-Json
        $bundle.receiptSha256 | Should Be $receipt.snapshot_sha256
        $result.ReceiptSha256 | Should Be $receipt.snapshot_sha256
        @($bundle.productMetadata).Count | Should Be $expectedAsins.Count
        @($bundle.productMetadata | Select-Object -ExpandProperty asin -Unique).Count | Should Be $expectedAsins.Count
        @($bundle.productMetadata | Where-Object {
            $_.brandSource -eq 'unknown' -and $null -eq $_.rawBrand -and $null -eq $_.normalizedBrand -and
            $null -eq $_.normalizedBrandKey -and $null -eq $_.brandAliasRuleId
        }).Count | Should Be $expectedAsins.Count
        $snapshot.PSObject.Properties['persisted_complete'] | Should Be $null
    }

    It 'requires persisted complete exact Top 30 categories for the metadata cohort' {
        $notPersisted = New-DashboardMetadataSnapshot -PersistedComplete $false
        @(New-DashboardSyncProductMetadataCohort -Snapshot $notPersisted).Count | Should Be 0

        $partial = New-DashboardMetadataSnapshot -PressureCount 29
        $rows = @(New-DashboardSyncProductMetadataCohort -Snapshot $partial)
        $rows.Count | Should Be 60
        @($rows | Where-Object asin -like 'P*').Count | Should Be 0
    }

    It 'uses pressure washers before accessories and sump pumps when an ASIN spans exact Top 30 categories' {
        $asin = 'B0PRIORITY'
        $snapshot = New-DashboardMetadataSnapshot
        foreach ($category in @('pressure_washers', 'pressure_washer_accessories', 'sump_pumps')) {
            $snapshot.$category[0].asin = $asin
            $snapshot.$category[0].url = "https://www.amazon.com/dp/$asin"
        }

        $result = @(New-DashboardSyncProductMetadataCohort -Snapshot $snapshot -ClassificationConfigPath (Join-Path $projectRoot 'config\v2-product-classification.json'))

        $result.Count | Should Be 88
        $duplicate = @($result | Where-Object asin -eq $asin)
        $duplicate.Count | Should Be 1
        $duplicate[0].productType | Should Be 'electric_pressure_washer'
        $duplicate[0].classificationRuleId | Should Be 'machine-electric'
    }

    It 'normalizes and propagates complete verified and manual brand pairs' {
        foreach ($source in @('verified_metadata', 'manual_review')) {
            $snapshot = New-DashboardMetadataSnapshot -PressureFirstProperties @{
                raw_brand = 'WESTINGHOUSE Outdoor Power Equipment'
                brand_source = $source
            }
            $product = @(New-DashboardSyncProductMetadataCohort -Snapshot $snapshot | Where-Object asin -eq 'P000000001')[0]

            $product.rawBrand | Should Be 'WESTINGHOUSE Outdoor Power Equipment'
            $product.normalizedBrand | Should Be 'Westinghouse'
            $product.normalizedBrandKey | Should Be 'westinghouse'
            $product.brandAliasRuleId | Should Be 'brand-westinghouse'
            $product.brandSource | Should Be $source
        }
    }

    It 'keeps incomplete or unsupported brand provenance unknown without title guessing' {
        foreach ($properties in @(
            @{ raw_brand = 'Westinghouse' },
            @{ brand_source = 'verified_metadata' },
            @{ raw_brand = 'Westinghouse'; brand_source = 'scraped_title' },
            @{ title = 'Westinghouse Electric pressure washer' }
        )) {
            $snapshot = New-DashboardMetadataSnapshot -PressureFirstProperties $properties
            $product = @(New-DashboardSyncProductMetadataCohort -Snapshot $snapshot | Where-Object asin -eq 'P000000001')[0]

            $product.rawBrand | Should Be $null
            $product.normalizedBrand | Should Be $null
            $product.normalizedBrandKey | Should Be $null
            $product.brandAliasRuleId | Should Be $null
            $product.brandSource | Should Be 'unknown'
        }
    }

    It 'rejects a different snapshot than the sibling receipt before creating a v2 bundle' {
        $fixture = New-DashboardReceiptFixture -Name 'verified-a'
        $requestedPath = Join-Path (Split-Path -Parent $fixture.snapshot_path) 'requested-b.json'
        Copy-Item -LiteralPath $fixture.snapshot_path -Destination $requestedPath
        $outputPath = Join-Path $TestDrive 'mismatch-bundle.json'

        { & (Join-Path $projectRoot 'scripts\New-DashboardSyncBundle.ps1') -SnapshotPath $requestedPath -OutputPath $outputPath | Out-Null } |
            Should Throw 'does not match the receipt snapshot'
        (Test-Path -LiteralPath $outputPath) | Should Be $false
    }

    It 'rejects partial and source-incomplete receipts before creating a v2 bundle' {
        $partial = New-DashboardReceiptFixture -Name 'partial' -Complete $false
        $partial.receipt.status | Should Be 'PARTIAL_NOT_ANALYSIS_ELIGIBLE'
        $partialOutput = Join-Path $TestDrive 'partial-bundle.json'
        { & (Join-Path $projectRoot 'scripts\New-DashboardSyncBundle.ps1') -SnapshotPath $partial.snapshot_path -OutputPath $partialOutput | Out-Null } |
            Should Throw 'COMPLETE_VALIDATED'
        (Test-Path -LiteralPath $partialOutput) | Should Be $false

        $sourceIncomplete = New-DashboardReceiptFixture -Name 'source-incomplete' -IncludeSourceMetadata $false
        $sourceIncomplete.receipt.status | Should Be 'COMPLETE_SOURCE_METADATA_INCOMPLETE'
        $sourceOutput = Join-Path $TestDrive 'source-incomplete-bundle.json'
        { & (Join-Path $projectRoot 'scripts\New-DashboardSyncBundle.ps1') -SnapshotPath $sourceIncomplete.snapshot_path -OutputPath $sourceOutput | Out-Null } |
            Should Throw 'COMPLETE_VALIDATED'
        (Test-Path -LiteralPath $sourceOutput) | Should Be $false
    }
}
