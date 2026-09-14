$modulePath = Join-Path $PSScriptRoot '..\src\BestSellersCategoryRegistry.psm1'
$registryPath = Join-Path $PSScriptRoot '..\config\category-registry.json'
$attributeSchemaPath = Join-Path $PSScriptRoot '..\config\v2-product-attributes.json'
Import-Module $modulePath -Force
Import-Module (Join-Path $PSScriptRoot '..\src\BestSellersAnalysis.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\BestSellersDailyReport.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\BestSellersDataSemantics.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\ReportArchive.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\BestSellersWeeklyAnalysis.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\BestSellersMarketStructure.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\BestSellersRankInfluence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\SellerIntelligence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\OnlineAnalysisReport.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\BestSellersCaptureReceipt.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\BestSellersAnalysisReadiness.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\BestSellersBrandEnrichment.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\BestSellersDataSemantics.psm1') -Force

function New-CategoryRegistryFixture {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [scriptblock]$Mutate
    )

    $fixtureRoot = Join-Path $TestDrive $Name
    $fixtureConfig = Join-Path $fixtureRoot 'config'
    New-Item -ItemType Directory -Path $fixtureConfig -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\config\v2-product-classification.json') -Destination $fixtureConfig
    Copy-Item -LiteralPath $attributeSchemaPath -Destination $fixtureConfig

    $raw = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -ne $Mutate) { & $Mutate $raw $fixtureRoot }
    $fixturePath = Join-Path $fixtureConfig 'category-registry.json'
    [IO.File]::WriteAllText($fixturePath, ($raw | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
    return $fixturePath
}

function Test-RegistryOperationThrows {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$Operation,
        [Parameter(Mandatory=$true)][string]$MessagePattern
    )

    $threw = $false
    $message = $null
    try { & $Operation | Out-Null } catch { $threw = $true; $message = $_.Exception.Message }
    $threw | Should Be $true
    $message | Should Match $MessagePattern
}

Describe 'Windows PowerShell compatibility' {
    It 'imports the production Registry when Test-Json is unavailable' {
        $windowsPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) { return }

        $module = (Resolve-Path -LiteralPath $modulePath).Path
        $registry = (Resolve-Path -LiteralPath $registryPath).Path
        $script = @"
`$ErrorActionPreference = 'Stop'
Import-Module '$module' -Force
`$registry = Import-BestSellersCategoryRegistry -Path '$registry'
if (`$registry.Categories.Count -ne 3) { throw 'Unexpected production category count.' }
"@
        $output = @(& $windowsPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $script 2>&1)
        $LASTEXITCODE | Should Be 0
        @($output | Where-Object { [string]$_ -match 'Test-Json|schema validation failed' }).Count | Should Be 0
    }
}

function New-TestCategoryRegistryFixture {
    $fixturePath = New-CategoryRegistryFixture -Name 'test-category-integration' -Mutate {
        param($raw)
        $raw.categories += [pscustomobject][ordered]@{
            category_key = 'test_category'
            slug = 'test-category'
            label_zh = '测试榜单'
            label_en = 'Test Category'
            amazon_node_id = '999000111'
            source_url = 'https://www.amazon.com/Best-Sellers-Test/zgbs/test/999000111'
            target_count = 30
            enabled = $true
            report_file_token = 'Test_Category'
            classification_config_path = 'config/v2-product-classification.json'
            attribute_schema_path = 'config/v2-product-attributes.json'
            segments = @([pscustomobject][ordered]@{ key='all'; label_zh='全部榜单'; product_types=@() })
            defaults = [pscustomobject][ordered]@{
                overview='all'; market='all'; products='all'; brands='all'; rankings='all'; reports='all';
                alerts='all'; data_status='all'; product_detail='all'
            }
        }
    }
    return $fixturePath
}

function New-TestCategorySnapshot {
    $testRows = @(1..30 | ForEach-Object {
        [pscustomobject]@{
            rank = $_
            asin = ('TST{0:D7}' -f $_)
            title = "Test Product $_"
            url = ('https://www.amazon.com/dp/TST{0:D7}' -f $_)
            price = 99.99
            rating = 4.5
            reviews = 100 + $_
            has_discount = $false
            discounts = @()
        }
    })
    return [pscustomobject]@{
        market_date = '2026-09-02'
        observed_at = '2026-09-02T06:00:00+08:00'
        sources = [pscustomobject]@{ test_category = 'https://www.amazon.com/Best-Sellers-Test/zgbs/test/999000111' }
        test_category = $testRows
    }
}

function New-TinyCategoryFixture {
    $fixturePath = New-CategoryRegistryFixture -Name 'tiny-category-integration' -Mutate {
        param($raw)
        foreach ($category in @($raw.categories)) { $category.target_count = 2 }
        $raw.categories += [pscustomobject][ordered]@{
            category_key = 'test_category'; slug = 'test-category'; label_zh = '测试榜单'; label_en = 'Test Category'
            amazon_node_id = '999000111'; source_url = 'https://www.amazon.com/Best-Sellers-Test/zgbs/test/999000111'
            target_count = 2; enabled = $true; report_file_token = 'Test_Category'
            classification_config_path = 'config/v2-product-classification.json'; attribute_schema_path = 'config/v2-product-attributes.json'
            segments = @([pscustomobject][ordered]@{ key='all'; label_zh='全部榜单'; product_types=@() })
            defaults = [pscustomobject][ordered]@{
                overview='all'; market='all'; products='all'; brands='all'; rankings='all'; reports='all'
                alerts='all'; data_status='all'; product_detail='all'
            }
        }
    }
    return $fixturePath
}

function New-TinyCategorySnapshot {
    param([Parameter(Mandatory=$true)]$Registry)
    $snapshot = [ordered]@{
        market_date = '2026-09-02'
        observed_at = '2026-09-02T06:00:00+08:00'
        persisted_complete = $true
        sources = [ordered]@{}
    }
    $prefixes = @{ pressure_washers='PWA'; sump_pumps='SUM'; pressure_washer_accessories='ACC'; test_category='TST' }
    foreach ($category in @($Registry.Categories | Where-Object Enabled)) {
        $snapshot.sources[$category.CategoryKey] = $category.SourceUrl
        $prefix = [string]$prefixes[$category.CategoryKey]
        $snapshot[$category.CategoryKey] = @(1..$category.TargetCount | ForEach-Object {
            [pscustomobject]@{
                rank=$_; asin=('{0}{1:D7}' -f $prefix,$_); title="$($category.LabelEn) Product $_"
                url=('https://www.amazon.com/dp/{0}{1:D7}' -f $prefix,$_); price=99.99; rating=4.5; reviews=100+$_
                has_discount=$false; discounts=@()
            }
        })
    }
    return [pscustomobject]$snapshot
}

function Write-TinySourceConfig {
    param([Parameter(Mandatory=$true)]$Registry, [Parameter(Mandatory=$true)][string]$Path)
    $config = [ordered]@{
        marketplace = $Registry.Marketplace.StorageCode
        target_count = 2
        sources = @($Registry.Categories | Where-Object Enabled | ForEach-Object {
            [ordered]@{ active=$true; category_key=$_.CategoryKey; amazon_node_id=$_.NodeId; url=$_.SourceUrl }
        })
    }
    [IO.File]::WriteAllText($Path,($config | ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
    return $Path
}

Describe 'Category Registry contract' {
    It 'preserves the three production categories and nodes' {
        $registry = Import-BestSellersCategoryRegistry -Path $registryPath

        (Get-BestSellersCategory -Registry $registry -CategoryKey 'pressure_washers').NodeId | Should Be '552856'
        (Get-BestSellersCategory -Registry $registry -CategoryKey 'sump_pumps').NodeId | Should Be '680335011'
        (Get-BestSellersCategory -Registry $registry -CategoryKey 'pressure_washer_accessories').NodeId | Should Be '3023451'
        (@(Get-BestSellersCategoryKeys -Registry $registry -EnabledOnly) -join ',') | Should Be 'pressure_washers,sump_pumps,pressure_washer_accessories'
    }

    It 'normalizes category fields, segments, defaults, and referenced paths' {
        $registry = Import-BestSellersCategoryRegistry -Path $registryPath
        $category = Get-BestSellersCategory -Registry $registry -CategoryKey 'pressure_washers'

        (@($registry.PSObject.Properties.Name) -join ',') | Should Be 'SchemaVersion,Marketplace,PageLoading,Path,ProjectRoot,Categories'
        $registry.PageLoading.top_30_rule | Should Be 'collect_only_verified_global_ranks_1_through_30'
        $registry.PageLoading.pagination_rule | Should Match 'global ranks'
        (@($category.PSObject.Properties.Name) -join ',') | Should Be 'CategoryKey,Slug,LabelZh,LabelEn,NodeId,SourceUrl,TargetCount,Enabled,ReportFileToken,ClassificationConfigPath,AttributeSchemaPath,Segments,Defaults'
        $category.Slug | Should Be 'pressure-washer'
        $category.LabelZh | Should Be '高压清洗机'
        $category.LabelEn | Should Be 'Pressure Washers'
        $category.TargetCount | Should Be 30
        (@($category.Segments | ForEach-Object Key) -join ',') | Should Be 'all,machines,electric,gas,cordless'
        (@($category.Segments | Where-Object Key -eq 'machines' | ForEach-Object ProductTypes) -join ',') | Should Be 'electric_pressure_washer,gas_pressure_washer,cordless_pressure_washer'
        $category.Defaults.overview | Should Be 'machines'
        $category.Defaults.rankings | Should Be 'all'
        [IO.Path]::GetFullPath($category.ClassificationConfigPath) | Should Be ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\config\v2-product-classification.json')))
        [IO.Path]::GetFullPath($category.AttributeSchemaPath) | Should Be ([IO.Path]::GetFullPath($attributeSchemaPath))
    }

    It 'preserves every production segment mapping and page default' {
        $registry = Import-BestSellersCategoryRegistry -Path $registryPath
        $sump = Get-BestSellersCategory -Registry $registry -CategoryKey 'sump_pumps'
        $accessories = Get-BestSellersCategory -Registry $registry -CategoryKey 'pressure_washer_accessories'

        (@($sump.Segments | ForEach-Object { "$($_.Key)=$(@($_.ProductTypes) -join '+')" }) -join ',') | Should Be 'all='
        (@($sump.Defaults.PSObject.Properties.Value) -join ',') | Should Be 'all,all,all,all,all,all,all,all,all'
        (@($accessories.Segments | ForEach-Object { "$($_.Key)=$(@($_.ProductTypes) -join '+')" }) -join ',') | Should Be 'all=,surface_cleaners=surface_cleaner,guns=pressure_washer_gun,hoses=hose,nozzles=nozzle,other=foam_cannon+adapter_connector+extension_wand+sewer_jetter+chemical_cleaner+pump_protector+other_accessory'
        (@($accessories.Defaults.PSObject.Properties.Value) -join ',') | Should Be 'all,all,all,all,all,all,all,all,all'
    }

    It 'defines every current product type exactly once in the attribute schema' {
        $schema = Get-Content -LiteralPath $attributeSchemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $schema.schema_version | Should Be 'product-attribute-schema-v1'
        (@($schema.product_types.PSObject.Properties.Name | Sort-Object) -join ',') | Should Be 'adapter_connector,chemical_cleaner,cordless_pressure_washer,electric_pressure_washer,extension_wand,foam_cannon,gas_pressure_washer,hose,nozzle,other_accessory,pressure_washer_gun,pump_protector,sewer_jetter,surface_cleaner,unknown'
        (@($schema.product_types.electric_pressure_washer) -join ',') | Should Be '工作压力,流量,动力类型,软管长度,电源线长度'
        (@($schema.product_types.unknown).Count) | Should Be 0
    }

    It 'rejects duplicate category keys before any consumer runs' {
        $invalidPath = New-CategoryRegistryFixture -Name 'duplicate-key' -Mutate { param($raw) $raw.categories += $raw.categories[0] }
        Test-RegistryOperationThrows -Operation { Import-BestSellersCategoryRegistry -Path $invalidPath } -MessagePattern 'duplicate category key'
    }

    It 'rejects duplicate Amazon nodes before any consumer runs' {
        $invalidPath = New-CategoryRegistryFixture -Name 'duplicate-node' -Mutate { param($raw) $raw.categories[1].amazon_node_id = $raw.categories[0].amazon_node_id }
        Test-RegistryOperationThrows -Operation { Import-BestSellersCategoryRegistry -Path $invalidPath } -MessagePattern 'duplicate Amazon node'
    }

    It 'rejects a page default that is not a supported segment' {
        $invalidPath = New-CategoryRegistryFixture -Name 'invalid-default' -Mutate { param($raw) $raw.categories[0].defaults.overview = 'unsupported' }
        Test-RegistryOperationThrows -Operation { Import-BestSellersCategoryRegistry -Path $invalidPath } -MessagePattern 'invalid default segment'
    }

    It 'rejects a missing source URL' {
        $invalidPath = New-CategoryRegistryFixture -Name 'missing-source' -Mutate { param($raw) $raw.categories[0].PSObject.Properties.Remove('source_url') }
        Test-RegistryOperationThrows -Operation { Import-BestSellersCategoryRegistry -Path $invalidPath } -MessagePattern 'schema validation'
    }

    It 'rejects a missing collector page-loading policy' {
        $invalidPath = New-CategoryRegistryFixture -Name 'missing-page-loading' -Mutate { param($raw) $raw.PSObject.Properties.Remove('page_loading') }
        Test-RegistryOperationThrows -Operation { Import-BestSellersCategoryRegistry -Path $invalidPath } -MessagePattern 'schema validation'
    }

    It 'rejects a missing classification config reference' {
        $invalidPath = New-CategoryRegistryFixture -Name 'missing-classification' -Mutate { param($raw) $raw.categories[0].classification_config_path = 'config/missing-classification.json' }
        Test-RegistryOperationThrows -Operation { Import-BestSellersCategoryRegistry -Path $invalidPath } -MessagePattern 'classification config'
    }

    It 'rejects an invalid classification config reference' {
        $invalidPath = New-CategoryRegistryFixture -Name 'invalid-classification' -Mutate {
            param($raw, $fixtureRoot)
            [IO.File]::WriteAllText((Join-Path $fixtureRoot 'config\v2-product-classification.json'), '{}', (New-Object Text.UTF8Encoding($false)))
        }
        Test-RegistryOperationThrows -Operation { Import-BestSellersCategoryRegistry -Path $invalidPath } -MessagePattern 'classification config is invalid'
    }

    It 'rejects a missing attribute schema reference' {
        $invalidPath = New-CategoryRegistryFixture -Name 'missing-attributes' -Mutate { param($raw) $raw.categories[0].attribute_schema_path = 'config/missing-attributes.json' }
        Test-RegistryOperationThrows -Operation { Import-BestSellersCategoryRegistry -Path $invalidPath } -MessagePattern 'attribute schema'
    }

    It 'rejects an invalid attribute schema reference' {
        $invalidPath = New-CategoryRegistryFixture -Name 'invalid-attributes' -Mutate {
            param($raw, $fixtureRoot)
            [IO.File]::WriteAllText((Join-Path $fixtureRoot 'config\v2-product-attributes.json'), '{}', (New-Object Text.UTF8Encoding($false)))
        }
        Test-RegistryOperationThrows -Operation { Import-BestSellersCategoryRegistry -Path $invalidPath } -MessagePattern 'attribute schema has an unsupported schema version'
    }

    It 'rejects additional category properties through the strict schema' {
        $invalidPath = New-CategoryRegistryFixture -Name 'additional-property' -Mutate { param($raw) $raw.categories[0] | Add-Member -NotePropertyName unexpected -NotePropertyValue $true }
        Test-RegistryOperationThrows -Operation { Import-BestSellersCategoryRegistry -Path $invalidPath } -MessagePattern 'schema validation'
    }

    It 'fails closed for unknown category keys' {
        $registry = Import-BestSellersCategoryRegistry -Path $registryPath
        Test-RegistryOperationThrows -Operation { Get-BestSellersCategory -Registry $registry -CategoryKey 'unsupported_category' } -MessagePattern 'Unknown or disabled category key'
    }

    It 'fails closed for disabled category keys unless explicitly allowed' {
        $disabledPath = New-CategoryRegistryFixture -Name 'disabled-category' -Mutate { param($raw) $raw.categories[1].enabled = $false }
        $registry = Import-BestSellersCategoryRegistry -Path $disabledPath

        (@(Get-BestSellersCategoryKeys -Registry $registry -EnabledOnly) -join ',') | Should Be 'pressure_washers,pressure_washer_accessories'
        Test-RegistryOperationThrows -Operation { Get-BestSellersCategory -Registry $registry -CategoryKey 'sump_pumps' } -MessagePattern 'Unknown or disabled category key'
        (Get-BestSellersCategory -Registry $registry -CategoryKey 'sump_pumps' -AllowDisabled).CategoryKey | Should Be 'sump_pumps'
    }
}

Describe 'PowerShell consumers use the Category Registry' {
    BeforeEach {
        $script:testRegistryPath = New-TestCategoryRegistryFixture
        $script:testSnapshot = New-TestCategorySnapshot
    }

    It 'enumerates operational quality for an injected enabled category' {
        $quality = Test-BestSellersTop50Snapshot -Snapshot $script:testSnapshot -RegistryPath $script:testRegistryPath
        $categoryQuality = @($quality.categories | Where-Object category -eq 'test_category')

        $categoryQuality.Count | Should Be 1
        $categoryQuality[0].target_count | Should Be 30
        $categoryQuality[0].item_count | Should Be 30
        $categoryQuality[0].is_complete | Should Be $true
    }

    It 'creates a selected daily report for an injected enabled category' {
        $report = New-BestSellersDailyReport -CurrentSnapshot $script:testSnapshot -OutputDirectory (Join-Path $TestDrive 'daily') -CategoryKeys test_category -RegistryPath $script:testRegistryPath

        $report.Status | Should Be 'COMPLETE_TOP30'
        ($report.Categories -contains 'test_category') | Should Be $true
        $report.ChartFileToken | Should Be 'Test_Category'
        $markdown = Get-Content -LiteralPath $report.MarkdownPath -Raw -Encoding UTF8
        $markdown | Should Match '测试榜单'
        $markdown | Should Not Match '高压清洗机、污水泵、高压清洗机配件'
    }

    It 'routes an injected daily report by its Registry label' {
        $sourcePdf = Join-Path $TestDrive 'test-category.pdf'
        [IO.File]::WriteAllText($sourcePdf, 'fixture', (New-Object Text.UTF8Encoding($false)))

        $destination = Copy-BestSellersReportToDesktop -PdfPath $sourcePdf -ReportKind Daily -CategoryKey test_category -ArchiveRoot (Join-Path $TestDrive 'archive') -RegistryPath $script:testRegistryPath

        $destination | Should Be (Join-Path (Join-Path (Join-Path $TestDrive 'archive') '测试榜单') 'test-category.pdf')
    }

    It 'classifies an unclaimed injected-category product as unknown' {
        $result = Get-BestSellersProductClassification -Asin 'TST0000001' -Title 'Test Product 1' -CategoryKey test_category -ConfigPath (Join-Path $PSScriptRoot '..\config\v2-product-classification.json') -RegistryPath $script:testRegistryPath

        $result.product_type | Should Be 'unknown'
        $result.classification_confidence | Should Be 'low'
    }

    It 'enumerates an injected category across weekly and structural analysis' {
        $weekly = New-BestSellersWeeklyAnalysis -Snapshots @($script:testSnapshot) -RegistryPath $script:testRegistryPath
        $structure = New-BestSellersMarketStructureAnalysis -Snapshot $script:testSnapshot -RegistryPath $script:testRegistryPath
        $rankInfluence = New-BestSellersRankInfluenceAnalysis -Snapshot $script:testSnapshot -RegistryPath $script:testRegistryPath

        (@($weekly.categories | Where-Object category -eq 'test_category')).Count | Should Be 1
        (@($structure.categories | Where-Object category -eq 'test_category')).Count | Should Be 1
        (@($rankInfluence.categories | Where-Object category -eq 'test_category')).Count | Should Be 1
    }

    It 'enumerates an injected category in online and seller reports' {
        $online = @(New-OnlineAnalysisReports -Snapshot $script:testSnapshot -ReceiptSha256 ('a' * 64) -ReportKind Daily -RegistryPath $script:testRegistryPath)
        $seller = @(New-SellerIntelligenceReports -Snapshot $script:testSnapshot -ReceiptSha256 ('b' * 64) -Profile SellerAlert -RegistryPath $script:testRegistryPath)

        (@($online | Where-Object categoryKey -eq 'test_category')).Count | Should Be 1
        (@($seller | Where-Object categoryKey -eq 'test_category')).Count | Should Be 1
    }

    It 'rejects an unsupported daily category before inspecting snapshot rows' {
        $snapshotWithoutRows = [pscustomobject]@{ market_date='2026-09-02' }
        Test-RegistryOperationThrows -Operation {
            New-BestSellersDailyReport -CurrentSnapshot $snapshotWithoutRows -OutputDirectory (Join-Path $TestDrive 'invalid') -CategoryKeys unsupported_category -RegistryPath $script:testRegistryPath
        } -MessagePattern 'Unknown or disabled category key'
    }

    It 'carries a custom target-two Registry through receipt authorization and the dashboard bundle entry script' {
        $tinyRegistryPath = New-TinyCategoryFixture
        $tinyRegistry = Import-BestSellersCategoryRegistry -Path $tinyRegistryPath
        $tinyRoot = Join-Path $TestDrive 'tiny-entry\2026-09-02'
        New-Item -ItemType Directory -Path $tinyRoot -Force | Out-Null
        $snapshotPath = Join-Path $tinyRoot 'amazon-bestsellers.json'
        $receiptPath = Join-Path $tinyRoot 'best-sellers-capture-receipt.json'
        $sourceConfigPath = Write-TinySourceConfig -Registry $tinyRegistry -Path (Join-Path $tinyRoot 'sources.json')
        [IO.File]::WriteAllText($snapshotPath,((New-TinyCategorySnapshot -Registry $tinyRegistry) | ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))

        $receipt = New-BestSellersCaptureReceipt -SnapshotPath $snapshotPath -SourceConfigPath $sourceConfigPath -RegistryPath $tinyRegistryPath
        Write-BestSellersCaptureReceipt -Receipt $receipt -Path $receiptPath | Out-Null
        $verification = & (Join-Path $PSScriptRoot '..\scripts\Test-BestSellersCaptureReceipt.ps1') -ReceiptPath $receiptPath -RegistryPath $tinyRegistryPath | ConvertFrom-Json
        $bundleResult = & (Join-Path $PSScriptRoot '..\scripts\New-DashboardSyncBundle.ps1') -SnapshotPath $snapshotPath -OutputPath (Join-Path $tinyRoot 'bundle.json') -RegistryPath $tinyRegistryPath | ConvertFrom-Json
        $onlineResult = & (Join-Path $PSScriptRoot '..\scripts\New-OnlineAnalysisReports.ps1') -SnapshotPath $snapshotPath -SnapshotsRoot (Split-Path -Parent $tinyRoot) -OutputRoot (Join-Path $tinyRoot 'online') -RegistryPath $tinyRegistryPath | ConvertFrom-Json
        $sellerResult = & (Join-Path $PSScriptRoot '..\scripts\New-SellerIntelligenceReports.ps1') -SnapshotPath $snapshotPath -SnapshotsRoot (Split-Path -Parent $tinyRoot) -OutputRoot (Join-Path $tinyRoot 'seller') -RegistryPath $tinyRegistryPath | ConvertFrom-Json

        $verification.valid | Should Be $true
        @($receipt.categories | Where-Object target_count -eq 2).Count | Should Be 4
        $bundleResult.ObservationCount | Should Be 8
        $onlineResult.ReportCount | Should Be 5
        $sellerResult.ReportCount | Should Be 5
    }

    It 'uses each Registry TargetCount in online seller readiness brand and command analysis' {
        $tinyRegistryPath = New-TinyCategoryFixture
        $tinyRegistry = Import-BestSellersCategoryRegistry -Path $tinyRegistryPath
        $snapshot = New-TinyCategorySnapshot -Registry $tinyRegistry
        $tinyRoot = Join-Path $TestDrive 'tiny-target\2026-09-02'
        New-Item -ItemType Directory -Path $tinyRoot -Force | Out-Null
        $snapshotPath = Join-Path $tinyRoot 'amazon-bestsellers.json'
        $receiptPath = Join-Path $tinyRoot 'best-sellers-capture-receipt.json'
        $sourceConfigPath = Write-TinySourceConfig -Registry $tinyRegistry -Path (Join-Path $tinyRoot 'sources.json')
        [IO.File]::WriteAllText($snapshotPath,($snapshot | ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
        $receipt = New-BestSellersCaptureReceipt -SnapshotPath $snapshotPath -SourceConfigPath $sourceConfigPath -RegistryPath $tinyRegistryPath
        Write-BestSellersCaptureReceipt -Receipt $receipt -Path $receiptPath | Out-Null

        $online = @(New-OnlineAnalysisReports -Snapshot $snapshot -ReceiptSha256 ('a' * 64) -ReportKind Daily -RegistryPath $tinyRegistryPath)
        $seller = @(New-SellerIntelligenceReports -Snapshot $snapshot -ReceiptSha256 ('b' * 64) -Profile SellerAlert -RegistryPath $tinyRegistryPath)
        $readiness = Get-BestSellersAnalysisReadiness -SnapshotsRoot (Split-Path -Parent $tinyRoot) -SourceConfigPath $sourceConfigPath -RequiredMarketDays 2 -AsOfDate '2026-09-02' -RegistryPath $tinyRegistryPath
        $readinessCommand = & (Join-Path $PSScriptRoot '..\scripts\Test-Phase5AnalysisReadiness.ps1') -SnapshotsRoot (Split-Path -Parent $tinyRoot) -SourceConfigPath $sourceConfigPath -RequiredMarketDays 2 -AsOfDate '2026-09-02' -RegistryPath $tinyRegistryPath | ConvertFrom-Json
        $historyAsins = @(Get-BestSellersVerifiedHistoryAsins -SnapshotsRoot (Split-Path -Parent $tinyRoot) -RegistryPath $tinyRegistryPath)
        $command = & (Join-Path $PSScriptRoot '..\scripts\Analyze-BestSellersSnapshot.ps1') -CurrentPath $snapshotPath -RegistryPath $tinyRegistryPath | ConvertFrom-Json

        @($online | Where-Object { -not $_.evidence.complete }).Count | Should Be 0
        @($seller | Where-Object { -not $_.evidence.complete }).Count | Should Be 0
        @($readiness.categories | Where-Object target_count -ne 2).Count | Should Be 0
        $readiness.target_count | Should Be 2
        $readinessCommand.target_count | Should Be 2
        $historyAsins.Count | Should Be 8
        $command.QualityPassed | Should Be $true
    }

    It 'invalidates a receipt when canonical Registry source metadata changes' {
        $tinyRegistryPath = New-TinyCategoryFixture
        $tinyRegistry = Import-BestSellersCategoryRegistry -Path $tinyRegistryPath
        $tinyRoot = Join-Path $TestDrive 'tiny-drift'
        New-Item -ItemType Directory -Path $tinyRoot -Force | Out-Null
        $snapshotPath = Join-Path $tinyRoot 'amazon-bestsellers.json'
        $receiptPath = Join-Path $tinyRoot 'best-sellers-capture-receipt.json'
        $sourceConfigPath = Write-TinySourceConfig -Registry $tinyRegistry -Path (Join-Path $tinyRoot 'sources.json')
        [IO.File]::WriteAllText($snapshotPath,((New-TinyCategorySnapshot -Registry $tinyRegistry) | ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
        $receipt = New-BestSellersCaptureReceipt -SnapshotPath $snapshotPath -SourceConfigPath $sourceConfigPath -RegistryPath $tinyRegistryPath
        Write-BestSellersCaptureReceipt -Receipt $receipt -Path $receiptPath | Out-Null

        $raw = Get-Content -LiteralPath $tinyRegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        ($raw.categories | Where-Object category_key -eq 'test_category').source_url = 'https://www.amazon.com/Best-Sellers-Test-Changed/zgbs/test/999000111'
        [IO.File]::WriteAllText($tinyRegistryPath,($raw | ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
        $verification = Test-BestSellersCaptureReceipt -ReceiptPath $receiptPath -RegistryPath $tinyRegistryPath

        $verification.valid | Should Be $false
        $verification.source_metadata_verified | Should Be $false
    }

    It 'keeps an injected Test Category isolated from the production Registry and report keys' {
        $productionHashBefore = (Get-FileHash -LiteralPath $registryPath -Algorithm SHA256).Hash
        $reports = @(New-OnlineAnalysisReports -Snapshot $script:testSnapshot -ReceiptSha256 ('c' * 64) -ReportKind Daily -RegistryPath $script:testRegistryPath)
        $productionRegistry = Import-BestSellersCategoryRegistry -Path $registryPath

        (@($reports | ForEach-Object key | Select-Object -Unique)).Count | Should Be $reports.Count
        (@($reports | Where-Object categoryKey -eq 'test_category')).Count | Should Be 1
        (@($reports | Where-Object categoryKey -eq 'test_category')[0].key) | Should Be 'daily/2026-09-02/test_category.json'
        (@(Get-BestSellersCategoryKeys -Registry $productionRegistry -EnabledOnly) -join ',') | Should Be 'pressure_washers,sump_pumps,pressure_washer_accessories'
        (@($productionRegistry.Categories | Where-Object CategoryKey -eq 'test_category')).Count | Should Be 0
        (Get-FileHash -LiteralPath $registryPath -Algorithm SHA256).Hash | Should Be $productionHashBefore
    }
}
