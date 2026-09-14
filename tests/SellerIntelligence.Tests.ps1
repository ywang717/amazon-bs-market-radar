$projectRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $projectRoot 'src\SellerIntelligence.psm1'
$semanticsModulePath = Join-Path $projectRoot 'src\BestSellersDataSemantics.psm1'
$receiptModulePath = Join-Path $projectRoot 'src\BestSellersCaptureReceipt.psm1'
$newReportsScript = Join-Path $projectRoot 'scripts\New-SellerIntelligenceReports.ps1'
$backfillScript = Join-Path $projectRoot 'scripts\Invoke-SellerIntelligenceBackfill.ps1'
$projectParent = Split-Path -Parent $projectRoot
$repoRoot = if ((Split-Path -Leaf $projectParent) -eq '.worktrees') {
    Split-Path -Parent $projectParent
}
else {
    $projectRoot
}
$sharedSnapshotsRoot = Join-Path $repoRoot 'var\amazon-bestsellers'

Describe 'Seller intelligence rules' {
    BeforeAll {
        Import-Module $semanticsModulePath -Force -Global
        Import-Module $modulePath -Force
    }

    It 'accepts only an exact Top 30 list' {
        $complete = @(1..30 | ForEach-Object {
                [pscustomobject]@{
                    asin = ('B{0:d9}' -f $_)
                    rank = $_
                    title = 'Example'
                }
            })

        Test-SellerExactTop30 -Items $complete | Should Be $true
        Test-SellerExactTop30 -Items $complete[0..28] | Should Be $false
        Test-SellerExactTop30 -Items (@($complete[0..28]) + [pscustomobject]@{ asin = 'B999999999'; rank = 31; title = 'Example' }) | Should Be $false
    }

    It 'uses the shared exact Top 30 validator' {
        $complete = @(1..30 | ForEach-Object { [pscustomobject]@{ rank = $_; asin = ('B' + $_.ToString('000000000')) } })
        Import-Module $semanticsModulePath -Force

        (SellerIntelligence\Test-SellerExactTop30 -Items $complete) |
            Should Be (BestSellersDataSemantics\Test-BestSellersExactTop30 -Items $complete)
        (SellerIntelligence\Test-SellerExactTop30 -Items $complete[0..28]) |
            Should Be (BestSellersDataSemantics\Test-BestSellersExactTop30 -Items $complete[0..28])
    }

    It 'marks a twenty-two-place improvement high' {
        $current = @(1..30 | ForEach-Object {
                [pscustomobject]@{
                    asin = ('B{0:d9}' -f $_)
                    rank = $_
                    title = '2000 PSI Electric Pressure Washer'
                    has_discount = $false
                    discounts = @()
                }
            })
        $previous = @(1..30 | ForEach-Object {
                [pscustomobject]@{
                    asin = ('B{0:d9}' -f $_)
                    rank = $_
                    title = '2000 PSI Electric Pressure Washer'
                    has_discount = $false
                    discounts = @()
                }
            })

        $current[3] = [pscustomobject]@{
            asin = 'B000000001'
            rank = 4
            title = '2000 PSI Electric Pressure Washer'
            has_discount = $true
            discounts = @('Coupon 10%')
        }
        $current[0] = [pscustomobject]@{
            asin = 'B000000004'
            rank = 1
            title = '2000 PSI Electric Pressure Washer'
            has_discount = $false
            discounts = @()
        }
        $previous[25] = [pscustomobject]@{
            asin = 'B000000001'
            rank = 26
            title = '2000 PSI Electric Pressure Washer'
            has_discount = $false
            discounts = @()
        }
        $previous[0] = [pscustomobject]@{
            asin = 'B000000026'
            rank = 1
            title = '2000 PSI Electric Pressure Washer'
            has_discount = $false
            discounts = @()
        }

        $signals = @(Get-SellerDailySignals -Current $current -Previous $previous)
        $rankSignal = $signals | Where-Object { $_.asin -eq 'B000000001' -and $_.kind -eq 'rank_move' } | Select-Object -First 1
        $top10Signal = $signals | Where-Object { $_.asin -eq 'B000000001' -and $_.kind -eq 'top10_entry' } | Select-Object -First 1
        $discountSignal = $signals | Where-Object { $_.asin -eq 'B000000001' -and $_.kind -eq 'discount_change' } | Select-Object -First 1

        $rankSignal.priority | Should Be 'high'
        $rankSignal.currentRank | Should Be 4
        $rankSignal.previousRank | Should Be 26
        $checkPriceDiscount = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5qC45p+l5Lu35qC85LiO5LyY5oOg54q25oCB'))
        ($rankSignal.checks -contains $checkPriceDiscount) | Should Be $true
        $top10Signal.priority | Should Be 'high'
        # Discount changes are review-worthy but are not high-severity rank events.
        $discountSignal.priority | Should Be 'watch'
    }

    It 'suppresses unverifiable discount changes when either side is unknown' {
        $current = @(1..30 | ForEach-Object {
                [pscustomobject]@{
                    asin = ('B{0:d9}' -f $_)
                    rank = $_
                    title = '2000 PSI Electric Pressure Washer'
                    has_discount = $null
                    discounts = @()
                }
            })
        $previous = @(1..30 | ForEach-Object {
                [pscustomobject]@{
                    asin = ('B{0:d9}' -f $_)
                    rank = $_
                    title = '2000 PSI Electric Pressure Washer'
                    has_discount = $false
                    discounts = @()
                }
            })

        $signals = @(Get-SellerDailySignals -Current $current -Previous $previous)

        @($signals | Where-Object { $_.kind -eq 'discount_change' }).Count | Should Be 0
    }

    It 'orders daily signals by severity before kind and asin' {
        $current = @(1..30 | ForEach-Object {
                [pscustomobject]@{
                    asin = ('B{0:d9}' -f $_)
                    rank = $_
                    title = '2000 PSI Electric Pressure Washer'
                    has_discount = $false
                    discounts = @()
                }
            })
        $previous = @(1..30 | ForEach-Object {
                [pscustomobject]@{
                    asin = ('B{0:d9}' -f $_)
                    rank = $_
                    title = '2000 PSI Electric Pressure Washer'
                    has_discount = $false
                    discounts = @()
                }
            })

        $current[3] = [pscustomobject]@{ asin = 'B000000001'; rank = 4; title = 'Example'; has_discount = $false; discounts = @() }
        $current[0] = [pscustomobject]@{ asin = 'B000000004'; rank = 1; title = 'Example'; has_discount = $false; discounts = @() }
        $previous[25] = [pscustomobject]@{ asin = 'B000000001'; rank = 26; title = 'Example'; has_discount = $false; discounts = @() }
        $previous[0] = [pscustomobject]@{ asin = 'B000000026'; rank = 1; title = 'Example'; has_discount = $false; discounts = @() }
        $current[17] = [pscustomobject]@{ asin = 'B000000002'; rank = 18; title = 'Example'; has_discount = $false; discounts = @() }
        $current[1] = [pscustomobject]@{ asin = 'B000000018'; rank = 2; title = 'Example'; has_discount = $false; discounts = @() }
        $previous[29] = [pscustomobject]@{ asin = 'B000000002'; rank = 30; title = 'Example'; has_discount = $false; discounts = @() }
        $previous[1] = [pscustomobject]@{ asin = 'B000000030'; rank = 2; title = 'Example'; has_discount = $false; discounts = @() }

        $signals = @(Get-SellerDailySignals -Current $current -Previous $previous)
        $rankSignals = @($signals | Where-Object { $_.kind -eq 'rank_move' -and $_.asin -in @('B000000001', 'B000000002') })

        $rankSignals.Count | Should Be 2
        $rankSignals[0].priority | Should Be 'high'
        $rankSignals[1].priority | Should Be 'watch'
    }

    It 'marks ordinary Top 30 entries and exits as activity' {
        $current = @(1..30 | ForEach-Object { [pscustomobject]@{ asin = ('B{0:d9}' -f $_); rank = $_; title = 'Example'; has_discount = $false; discounts = @() } })
        $previous = @(1..30 | ForEach-Object { [pscustomobject]@{ asin = ('B{0:d9}' -f $_); rank = $_; title = 'Example'; has_discount = $false; discounts = @() } })
        $current[29] = [pscustomobject]@{ asin = 'B999999991'; rank = 30; title = 'New entry'; has_discount = $false; discounts = @() }
        $previous[29] = [pscustomobject]@{ asin = 'B999999992'; rank = 30; title = 'Exited entry'; has_discount = $false; discounts = @() }

        $signals = @(Get-SellerDailySignals -Current $current -Previous $previous)

        ($signals | Where-Object { $_.kind -eq 'top30_entry' }).priority | Should Be 'activity'
        ($signals | Where-Object { $_.kind -eq 'top30_exit' }).priority | Should Be 'activity'
    }

    It 'marks a direct new Top 10 entry as high instead of ordinary activity' {
        $current = @(1..30 | ForEach-Object { [pscustomobject]@{ asin = ('B{0:d9}' -f $_); rank = $_; title = 'Example'; has_discount = $false; discounts = @() } })
        $previous = @(1..30 | ForEach-Object { [pscustomobject]@{ asin = ('B{0:d9}' -f $_); rank = $_; title = 'Example'; has_discount = $false; discounts = @() } })
        $current[6] = [pscustomobject]@{ asin = 'B999999993'; rank = 7; title = 'New Top 10 entry'; has_discount = $false; discounts = @() }
        $previous[6] = [pscustomobject]@{ asin = 'B999999994'; rank = 7; title = 'Exited entry'; has_discount = $false; discounts = @() }

        $signals = @(Get-SellerDailySignals -Current $current -Previous $previous)
        $directEntry = $signals | Where-Object { $_.asin -eq 'B999999993' } | Select-Object -First 1
        $directExit = $signals | Where-Object { $_.asin -eq 'B999999994' } | Select-Object -First 1

        $directEntry.kind | Should Be 'top10_entry'
        $directEntry.priority | Should Be 'high'
        $directExit.kind | Should Be 'top10_exit'
        $directExit.priority | Should Be 'high'
    }

    It 'suppresses rank signals without two exact Top 30 lists' {
        (Get-SellerDailySignals -Current @() -Previous @()).Count | Should Be 0
    }

    It 'extracts only explicit washer values' {
        $specs = Get-SellerSpecifications -CategoryKey pressure_washers -Title '2000 PSI 1.8 GPM Electric Pressure Washer with 25 FT Hose and 15 Degree Nozzle'

        $specs.psi | Should Be 2000
        $specs.gpm | Should Be 1.8
        $specs.power_type | Should Be 'electric'
        $specs.hose_length_ft | Should Be 25
        $specs.nozzle_degree | Should Be 15
    }

    It 'keeps absent sump-pump values null' {
        $specs = Get-SellerSpecifications -CategoryKey sump_pumps -Title 'Reliable pump'

        $specs.head_ft | Should Be $null
        $specs.horsepower_hp | Should Be $null
        $specs.voltage_v | Should Be $null
    }

    It 'returns no competitor pool before five complete days' {
        $days = @(
            [pscustomobject]@{
                market_date = '2026-08-20'
                pressure_washers = @(1..30 | ForEach-Object { [pscustomobject]@{ asin = ('B{0:d9}' -f $_); rank = $_; title = 'Example' } })
            }
        )

        @(Get-SellerCompetitorPool -Snapshots $days -CategoryKey pressure_washers -CompleteMarketDays 4).Count | Should Be 0
    }

    It 'assigns competitor-pool priority from presence top-10 and movement without using high' {
        $newDay = {
            param([string]$MarketDate, [int]$Rank, [int]$Offset)

            $rows = @(1..30 | ForEach-Object {
                    if ($_ -eq $Rank) {
                        [pscustomobject]@{ asin = 'B000000001'; rank = $_; title = '2000 PSI Electric Pressure Washer' }
                    }
                    else {
                        [pscustomobject]@{ asin = ('B{0:d9}' -f ($Offset + $_)); rank = $_; title = 'Example' }
                    }
                })
            [pscustomobject]@{
                market_date = $MarketDate
                pressure_washers = $rows
            }
        }

        $days = @(
            & $newDay '2026-08-20' 12 100
            & $newDay '2026-08-21' 8 200
            & $newDay '2026-08-22' 6 300
            & $newDay '2026-08-23' 3 400
            & $newDay '2026-08-24' 5 500
        )

        $pool = @(Get-SellerCompetitorPool -Snapshots $days -CategoryKey pressure_washers -CompleteMarketDays 5)
        $focus = $pool | Where-Object { $_.asin -eq 'B000000001' } | Select-Object -First 1

        $focus.priority | Should Be 'medium'
        $focus.daysPresent | Should Be 5
        $focus.top10Appearances | Should Be 4
        $focus.latestRank | Should Be 5
        $focus.maxAbsoluteMovement | Should Be 4
    }

    It 'preserves rank 31 in a competitor pool whose Registry target is 50' {
        $fixtureRoot = Join-Path $TestDrive 'target-fifty-registry'
        $fixtureConfig = Join-Path $fixtureRoot 'config'
        New-Item -ItemType Directory -Path $fixtureConfig -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $projectRoot 'config\v2-product-classification.json') -Destination $fixtureConfig
        Copy-Item -LiteralPath (Join-Path $projectRoot 'config\v2-product-attributes.json') -Destination $fixtureConfig
        $registry = Get-Content -LiteralPath (Join-Path $projectRoot 'config\category-registry.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        ($registry.categories | Where-Object category_key -eq 'pressure_washers').target_count = 50
        $registryPath = Join-Path $fixtureConfig 'category-registry.json'
        [IO.File]::WriteAllText($registryPath,($registry | ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))

        $days = @(1..5 | ForEach-Object {
                $day = $_
                [pscustomobject]@{
                    market_date = ('2026-08-{0:D2}' -f (19 + $day))
                    pressure_washers = @(1..50 | ForEach-Object {
                            [pscustomobject]@{ asin=('F{0:D9}' -f $_); rank=$_; title="Target 50 Product $_" }
                        })
                }
            })

        $pool = @(Get-SellerCompetitorPool -Snapshots $days -CategoryKey pressure_washers -CompleteMarketDays 5 -RegistryPath $registryPath)
        $focus = $pool | Where-Object asin -eq 'F000000031' | Select-Object -First 1

        $focus.latestRank | Should Be 31
    }

    It 'writes contract-shaped seller reports for each weekly scope' {
        $snapshot = [pscustomobject]@{
            market_date = '2026-08-24'
            observed_at = '2026-08-25T01:00:00Z'
            pressure_washers = @(1..30 | ForEach-Object {
                    [pscustomobject]@{
                        asin = ('B{0:d9}' -f $_)
                        rank = $_
                        title = '2000 PSI 1.8 GPM Electric Pressure Washer with 25 FT Hose'
                        price = '$199.99'
                        rating = 4.5
                        reviews = 150
                        has_discount = $false
                        discounts = @()
                    }
                })
            sump_pumps = @(1..30 | ForEach-Object {
                    [pscustomobject]@{
                        asin = ('C{0:d9}' -f $_)
                        rank = $_
                        title = '1 HP 115 V sump pump with 20 FT head'
                        price = '$149.99'
                        rating = 4.2
                        reviews = 80
                        has_discount = $false
                        discounts = @()
                    }
                })
            pressure_washer_accessories = @(1..30 | ForEach-Object {
                    [pscustomobject]@{
                        asin = ('D{0:d9}' -f $_)
                        rank = $_
                        title = '25 FT hose with 15 Degree nozzle and 1/4 in fitting'
                        price = '$39.99'
                        rating = 4.0
                        reviews = 40
                        has_discount = $false
                        discounts = @()
                    }
                })
        }
        $history = @(
            [pscustomobject]@{
                market_date = '2026-08-20'
                pressure_washers = $snapshot.pressure_washers
                sump_pumps = $snapshot.sump_pumps
                pressure_washer_accessories = $snapshot.pressure_washer_accessories
            },
            [pscustomobject]@{
                market_date = '2026-08-21'
                pressure_washers = $snapshot.pressure_washers
                sump_pumps = $snapshot.sump_pumps
                pressure_washer_accessories = $snapshot.pressure_washer_accessories
            },
            [pscustomobject]@{
                market_date = '2026-08-22'
                pressure_washers = $snapshot.pressure_washers
                sump_pumps = $snapshot.sump_pumps
                pressure_washer_accessories = $snapshot.pressure_washer_accessories
            },
            [pscustomobject]@{
                market_date = '2026-08-23'
                pressure_washers = $snapshot.pressure_washers
                sump_pumps = $snapshot.sump_pumps
                pressure_washer_accessories = $snapshot.pressure_washer_accessories
            },
            [pscustomobject]@{
                market_date = '2026-08-24'
                pressure_washers = $snapshot.pressure_washers
                sump_pumps = $snapshot.sump_pumps
                pressure_washer_accessories = $snapshot.pressure_washer_accessories
            }
        )

        $reports = @(New-SellerIntelligenceReports -Snapshot $snapshot -ReceiptSha256 ('a' * 64) -Profile competition_strategy -HistorySnapshots $history -CompleteMarketDays 5)
        $paths = @(Write-SellerIntelligenceReports -Reports $reports -OutputDirectory $TestDrive)
        $overview = Get-Content -Raw $paths[0] | ConvertFrom-Json
        $washer = @($reports | Where-Object { $_.categoryKey -eq 'pressure_washers' })[0]

        $reports.Count | Should Be 4
        @($paths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }).Count | Should Be 4
        $overview.schemaVersion | Should Be 'seller-intelligence-v1'
        $overview.profile | Should Be 'competition_strategy'
        $overview.key | Should Be 'competition-strategy/weekly/2026-08-24/overview.json'
        $overview.evidence.completeMarketDays | Should Be 5
        $null -ne $overview.strategy | Should Be $true
        $null -eq $overview.strategy.priceBands | Should Be $true
        $null -ne $washer.strategy | Should Be $true
        @($washer.strategy.priceBands).Count | Should BeGreaterThan 0
        $washer.strategy.rankingConcentration.top10Slots | Should Be 10
        $washer.strategy.topStability.baselineDate | Should Be '2026-08-23'
        @($washer.strategy.competitorPool).Count | Should BeGreaterThan 0
        $washer.strategy.specificationTrend.coverage | Should Be 100
        @($washer.strategy.specificationTrend.observedFields).Count | Should BeGreaterThan 0
        $manualOnly = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5LuF5L6b5Lq65bel5qC45p+l77yM5LiN5Luj6KGo6ZSA6YeP5oiW5Yip5ram6aKE5rWL44CC'))
        ($overview.limitations -contains $manualOnly) | Should Be $true
    }

    It 'keeps weekly category gates and history independent from overview completeness' {
        $newSnapshot = {
            param([string]$Date)
            [pscustomobject]@{
                market_date = $Date
                observed_at = "$Date`T01:00:00Z"
                pressure_washers = @(1..30 | ForEach-Object { [pscustomobject]@{ asin = ('B{0:d9}' -f $_); rank = $_; title = '2000 PSI Electric Washer with 25 FT Hose'; price = 100; rating = 4; reviews = 10; has_discount = $false; discounts = @() } })
                sump_pumps = @(1..29 | ForEach-Object { [pscustomobject]@{ asin = ('S{0:d9}' -f $_); rank = $_; title = 'Pump'; price = 100; rating = 4; reviews = 10; has_discount = $false; discounts = @() } })
                pressure_washer_accessories = @(1..29 | ForEach-Object { [pscustomobject]@{ asin = ('A{0:d9}' -f $_); rank = $_; title = 'Accessory'; price = 100; rating = 4; reviews = 10; has_discount = $false; discounts = @() } })
            }
        }
        $history = @(20..24 | ForEach-Object { & $newSnapshot ("2026-08-{0:d2}" -f $_) })
        $reports = @(New-SellerIntelligenceReports -Snapshot $history[-1] -ReceiptSha256 ('a' * 64) -Profile CompetitionStrategy -HistorySnapshots $history -CompleteMarketDays 0 -CategoryCompleteMarketDays @{ pressure_washers = 5; sump_pumps = 0; pressure_washer_accessories = 0 })
        $overview = @($reports | Where-Object { $_.categoryKey -eq $null })[0]
        $washer = @($reports | Where-Object { $_.categoryKey -eq 'pressure_washers' })[0]
        $sump = @($reports | Where-Object { $_.categoryKey -eq 'sump_pumps' })[0]
        $poolTitle = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5qC45b+D56ue5ZOB5rGg'))

        $overview.evidence.completeMarketDays | Should Be 0
        $null -ne $overview.strategy | Should Be $true
        $null -eq $overview.strategy.competitorPool | Should Be $true
        $washer.evidence.completeMarketDays | Should Be 5
        @($washer.sections | Where-Object { $_.title -eq $poolTitle }).Count | Should Be 1
        @($washer.strategy.competitorPool).Count | Should BeGreaterThan 0
        $sump.evidence.completeMarketDays | Should Be 0
        $null -eq $sump.strategy.priceBands | Should Be $true
    }

    It 'writes four seller alert JSON files with distinct keys' {
        $fixtureSnapshot = Join-Path $sharedSnapshotsRoot '2026-08-24\amazon-bestsellers.json'

        $result = & $newReportsScript -SnapshotPath $fixtureSnapshot -SnapshotsRoot $sharedSnapshotsRoot -OutputRoot $TestDrive | ConvertFrom-Json
        $keys = @($result.ReportPaths | ForEach-Object { (Get-Content -LiteralPath $_ -Raw -Encoding UTF8 | ConvertFrom-Json).key })

        $result.Status | Should Be 'CREATED'
        $result.ReportKind | Should Be 'daily'
        $result.ReportCount | Should Be 4
        @($keys | Select-Object -Unique).Count | Should Be 4
        @($keys | Where-Object { $_ -match '^seller-alert/daily/2026-08-24/.+\.json$' }).Count | Should Be 4
    }

    function New-SellerReceiptFixture {
        param(
            [Parameter(Mandatory=$true)][string]$SnapshotsRoot,
            [Parameter(Mandatory=$true)][string]$MarketDate,
            [string]$SnapshotName = 'amazon-bestsellers.json',
            [bool]$Complete = $true,
            [bool]$IncludeSourceMetadata = $true,
            [bool]$SwapPressureRanks = $false
        )

        $directory = Join-Path $SnapshotsRoot $MarketDate
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $snapshotPath = Join-Path $directory $SnapshotName
        $snapshot = Get-Content -LiteralPath (Join-Path $projectRoot 'web\data\verified-snapshot-2026-08-12.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $snapshot.market_date = $MarketDate
        if (-not $Complete) {
            foreach ($category in @('pressure_washers','sump_pumps','pressure_washer_accessories')) { $snapshot.$category = @($snapshot.$category | Select-Object -First 29) }
        }
        if (-not $IncludeSourceMetadata) { $snapshot.PSObject.Properties.Remove('sources') }
        if ($SwapPressureRanks) {
            $firstAsin = $snapshot.pressure_washers[0].asin
            $snapshot.pressure_washers[0].asin = $snapshot.pressure_washers[20].asin
            $snapshot.pressure_washers[20].asin = $firstAsin
        }
        [IO.File]::WriteAllText($snapshotPath, ($snapshot | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
        $receiptPath = Join-Path $directory 'best-sellers-capture-receipt.json'
        $receipt = New-BestSellersCaptureReceipt -SnapshotPath $snapshotPath -SourceConfigPath (Join-Path $projectRoot 'config\best-sellers-sources.json')
        Write-BestSellersCaptureReceipt -Receipt $receipt -Path $receiptPath | Out-Null
        return [pscustomobject]@{ snapshot_path=$snapshotPath; receipt_path=$receiptPath; receipt=$receipt }
    }

    It 'rejects a current snapshot that differs from its sibling receipt' {
        Import-Module $receiptModulePath -Force
        $snapshotRoot = Join-Path $TestDrive 'current-mismatch'
        $authorized = New-SellerReceiptFixture -SnapshotsRoot $snapshotRoot -MarketDate '2026-08-20' -SnapshotName 'authorized-a.json'
        $requested = Join-Path (Split-Path -Parent $authorized.snapshot_path) 'amazon-bestsellers.json'
        Copy-Item -LiteralPath $authorized.snapshot_path -Destination $requested

        { & $newReportsScript -SnapshotPath $requested -SnapshotsRoot $snapshotRoot -OutputRoot $TestDrive | Out-Null } |
            Should Throw 'does not match the receipt snapshot'
    }

    It 'rejects a partial current receipt before report output' {
        Import-Module $receiptModulePath -Force
        $snapshotRoot = Join-Path $TestDrive 'current-partial'
        $fixture = New-SellerReceiptFixture -SnapshotsRoot $snapshotRoot -MarketDate '2026-08-20' -Complete $false
        $fixture.receipt.status | Should Be 'PARTIAL_NOT_ANALYSIS_ELIGIBLE'

        { & $newReportsScript -SnapshotPath $fixture.snapshot_path -SnapshotsRoot $snapshotRoot -OutputRoot $TestDrive | Out-Null } |
            Should Throw 'COMPLETE_VALIDATED'
    }

    It 'skips a history snapshot whose sibling receipt authorizes another file' {
        Import-Module $receiptModulePath -Force
        $snapshotRoot = Join-Path $TestDrive 'history-mismatch'
        New-SellerReceiptFixture -SnapshotsRoot $snapshotRoot -MarketDate '2026-08-18' | Out-Null
        $authorized = New-SellerReceiptFixture -SnapshotsRoot $snapshotRoot -MarketDate '2026-08-19' -SnapshotName 'authorized-a.json'
        Copy-Item -LiteralPath $authorized.snapshot_path -Destination (Join-Path (Split-Path -Parent $authorized.snapshot_path) 'amazon-bestsellers.json')
        $current = New-SellerReceiptFixture -SnapshotsRoot $snapshotRoot -MarketDate '2026-08-20' -SwapPressureRanks $true

        $result = & $newReportsScript -SnapshotPath $current.snapshot_path -SnapshotsRoot $snapshotRoot -OutputRoot $TestDrive | ConvertFrom-Json
        $overview = Get-Content -LiteralPath (@($result.ReportPaths | Where-Object { [IO.Path]::GetFileName($_) -eq 'overview.json' })[0]) -Raw | ConvertFrom-Json

        $result.CompleteMarketDays | Should Be 2
        @($overview.signals | Where-Object { $_.baselineDate -eq '2026-08-18' }).Count | Should BeGreaterThan 0
        @($overview.signals | Where-Object { $_.baselineDate -eq '2026-08-19' }).Count | Should Be 0
    }

    It 'rejects an explicit previous snapshot that differs from its sibling receipt' {
        Import-Module $receiptModulePath -Force
        $snapshotRoot = Join-Path $TestDrive 'explicit-mismatch'
        $authorized = New-SellerReceiptFixture -SnapshotsRoot $snapshotRoot -MarketDate '2026-08-19' -SnapshotName 'authorized-a.json'
        $requestedPrevious = Join-Path (Split-Path -Parent $authorized.snapshot_path) 'amazon-bestsellers.json'
        Copy-Item -LiteralPath $authorized.snapshot_path -Destination $requestedPrevious
        $current = New-SellerReceiptFixture -SnapshotsRoot $snapshotRoot -MarketDate '2026-08-20'

        { & $newReportsScript -SnapshotPath $current.snapshot_path -PreviousSnapshotPath $requestedPrevious -SnapshotsRoot $snapshotRoot -OutputRoot $TestDrive | Out-Null } |
            Should Throw 'Previous seller intelligence snapshot requires an authorized COMPLETE_VALIDATED capture receipt.'
    }

    It 'rejects a ReportDate that differs from the verified snapshot market date' {
        Import-Module $receiptModulePath -Force
        $snapshotRoot = Join-Path $TestDrive 'report-date-mismatch'
        $current = New-SellerReceiptFixture -SnapshotsRoot $snapshotRoot -MarketDate '2026-08-20'

        { & $newReportsScript -SnapshotPath $current.snapshot_path -SnapshotsRoot $snapshotRoot -ReportDate '2026-08-21' -OutputRoot $TestDrive | Out-Null } |
            Should Throw 'ReportDate must match the verified snapshot market_date.'
    }

    It 'skips an invalid receipt between adjacent valid report days' {
        $snapshotRoot = Join-Path $TestDrive 'valid-day-snapshots'
        $sourceConfig = Join-Path $projectRoot 'config\best-sellers-sources.json'
        Import-Module $receiptModulePath -Force
        foreach ($marketDate in @('2026-08-18', '2026-08-19', '2026-08-20')) {
            $sourceDay = Join-Path $sharedSnapshotsRoot '2026-08-18'
            $targetDay = Join-Path $snapshotRoot $marketDate
            New-Item -ItemType Directory -Path $targetDay -Force | Out-Null
            $targetSnapshot = Join-Path $targetDay 'amazon-bestsellers.json'
            Copy-Item -LiteralPath (Join-Path $sourceDay 'amazon-bestsellers.json') -Destination $targetSnapshot
            $snapshotData = Get-Content -LiteralPath $targetSnapshot -Raw -Encoding UTF8 | ConvertFrom-Json
            $snapshotData.market_date = $marketDate
            if ($marketDate -eq '2026-08-20') {
                $firstAsin = $snapshotData.pressure_washers[0].asin
                $snapshotData.pressure_washers[0].asin = $snapshotData.pressure_washers[20].asin
                $snapshotData.pressure_washers[20].asin = $firstAsin
            }
            $snapshotData | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $targetSnapshot -Encoding UTF8
            $receipt = New-BestSellersCaptureReceipt -SnapshotPath $targetSnapshot -SourceConfigPath $sourceConfig
            Write-BestSellersCaptureReceipt -Receipt $receipt -Path (Join-Path $targetDay 'best-sellers-capture-receipt.json') | Out-Null
        }
        $day19Receipt = Join-Path $snapshotRoot '2026-08-19\best-sellers-capture-receipt.json'
        $corruptReceipt = Get-Content -LiteralPath $day19Receipt -Raw -Encoding UTF8 | ConvertFrom-Json
        $corruptReceipt.snapshot_sha256 = ('0' * 64)
        $corruptReceipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $day19Receipt -Encoding UTF8
        $day20Snapshot = Join-Path $snapshotRoot '2026-08-20\amazon-bestsellers.json'

        $result = & $newReportsScript -SnapshotPath $day20Snapshot -SnapshotsRoot $snapshotRoot -OutputRoot $TestDrive | ConvertFrom-Json
        $overview = Get-Content -LiteralPath (@($result.ReportPaths | Where-Object { [IO.Path]::GetFileName($_) -eq 'overview.json' })[0]) -Raw | ConvertFrom-Json

        @($overview.signals | Where-Object { $_.baselineDate -eq '2026-08-19' }).Count | Should Be 0
        @($overview.signals | Where-Object { $_.baselineDate -eq '2026-08-18' }).Count | Should BeGreaterThan 0
    }

    It 'rejects an explicit previous snapshot without a valid sibling receipt' {
        $snapshotRoot = Join-Path $TestDrive 'explicit-previous-snapshots'
        $sourceConfig = Join-Path $projectRoot 'config\best-sellers-sources.json'
        Import-Module $receiptModulePath -Force
        foreach ($marketDate in @('2026-08-19', '2026-08-20')) {
            $sourceDay = Join-Path $sharedSnapshotsRoot '2026-08-18'
            $targetDay = Join-Path $snapshotRoot $marketDate
            New-Item -ItemType Directory -Path $targetDay -Force | Out-Null
            $targetSnapshot = Join-Path $targetDay 'amazon-bestsellers.json'
            Copy-Item -LiteralPath (Join-Path $sourceDay 'amazon-bestsellers.json') -Destination $targetSnapshot
            $snapshotData = Get-Content -LiteralPath $targetSnapshot -Raw -Encoding UTF8 | ConvertFrom-Json
            $snapshotData.market_date = $marketDate
            $snapshotData | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $targetSnapshot -Encoding UTF8
            $receipt = New-BestSellersCaptureReceipt -SnapshotPath $targetSnapshot -SourceConfigPath $sourceConfig
            Write-BestSellersCaptureReceipt -Receipt $receipt -Path (Join-Path $targetDay 'best-sellers-capture-receipt.json') | Out-Null
        }
        $day19Receipt = Join-Path $snapshotRoot '2026-08-19\best-sellers-capture-receipt.json'
        $corruptReceipt = Get-Content -LiteralPath $day19Receipt -Raw -Encoding UTF8 | ConvertFrom-Json
        $corruptReceipt.snapshot_sha256 = ('0' * 64)
        $corruptReceipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $day19Receipt -Encoding UTF8
        $day20Snapshot = Join-Path $snapshotRoot '2026-08-20\amazon-bestsellers.json'
        $day19Snapshot = Join-Path $snapshotRoot '2026-08-19\amazon-bestsellers.json'

        { & $newReportsScript -SnapshotPath $day20Snapshot -PreviousSnapshotPath $day19Snapshot -SnapshotsRoot $snapshotRoot -OutputRoot $TestDrive } |
            Should Throw 'Previous seller intelligence snapshot requires an authorized COMPLETE_VALIDATED capture receipt.'
    }

    It 'generates a comparable daily overview when a valid previous snapshot exists' {
        $fixtureSnapshot = Join-Path $sharedSnapshotsRoot '2026-08-24\amazon-bestsellers.json'
        $qualityTitle = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5pWw5o2u6LSo6YeP'))
        $dailyTitle = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('57uP6JCl6aKE6K2m'))
        $summaryTitle = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('6KeC5a+f5pGY6KaB'))

        $result = & $newReportsScript -SnapshotPath $fixtureSnapshot -SnapshotsRoot $sharedSnapshotsRoot -OutputRoot $TestDrive | ConvertFrom-Json
        $overviewPath = @($result.ReportPaths | Where-Object { [IO.Path]::GetFileName($_) -eq 'overview.json' }) | Select-Object -First 1
        $overview = Get-Content -LiteralPath $overviewPath -Raw -Encoding UTF8 | ConvertFrom-Json

        $overview.key | Should Be 'seller-alert/daily/2026-08-24/overview.json'
        @($overview.signals).Count | Should BeGreaterThan 0
        @($overview.sections | Where-Object { $_.title -eq $dailyTitle }).Count | Should Be 1
        @($overview.sections | Where-Object { $_.title -eq $summaryTitle }).Count | Should Be 1
        @($overview.sections | Where-Object { $_.title -eq $qualityTitle }).Count | Should Be 0
    }

    It 'keeps an incomplete snapshot to a quality disclosure' {
        $qualityTitle = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5pWw5o2u6LSo6YeP'))
        $weeklyTitle = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('56ue5LqJ6KeC5a+f'))
        $poolTitle = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5qC45b+D56ue5ZOB5rGg'))
        $incomplete = [pscustomobject]@{
            market_date = '2026-08-24'
            observed_at = '2026-08-25T01:00:00Z'
            pressure_washers = @(1..29 | ForEach-Object {
                    [pscustomobject]@{
                        asin = ('B{0:d9}' -f $_)
                        rank = $_
                        title = '2000 PSI Electric Pressure Washer'
                    }
                })
            sump_pumps = @()
            pressure_washer_accessories = @()
        }

        $report = New-SellerIntelligenceReport -Snapshot $incomplete -ReceiptSha256 ('a' * 64) -Profile SellerAlert -CategoryKey pressure_washers

        @($report.signals).Count | Should Be 0
        @($report.sections).Count | Should Be 1
        $report.sections[0].title | Should Be $qualityTitle
        @($report.sections | Where-Object { $_.title -in @($weeklyTitle, $poolTitle) }).Count | Should Be 0
    }

    It 'uploads only imported or duplicate seller-intelligence backfill responses without printing the secret' {
        $global:backfillCalls = New-Object System.Collections.ArrayList
        $processSecret = 'seller-backfill-secret'
        $snapshotRoot = Join-Path $TestDrive 'snapshots'
        $sourceRoot = Join-Path $sharedSnapshotsRoot '2026-08-24'
        $targetRoot = Join-Path $snapshotRoot '2026-08-24'
        New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $sourceRoot 'amazon-bestsellers.json') -Destination (Join-Path $targetRoot 'amazon-bestsellers.json')
        Import-Module $receiptModulePath -Force
        $receipt = New-BestSellersCaptureReceipt -SnapshotPath (Join-Path $targetRoot 'amazon-bestsellers.json') -SourceConfigPath (Join-Path $projectRoot 'config\best-sellers-sources.json')
        Write-BestSellersCaptureReceipt -Receipt $receipt -Path (Join-Path $targetRoot 'best-sellers-capture-receipt.json') | Out-Null

        $postImportedBundle = {
            param($Uri, $Method, $Headers, $ContentType, $Body)

            [void]$global:backfillCalls.Add([pscustomobject]@{
                    Uri = [string]$Uri
                    Method = [string]$Method
                    Authorization = [string]$Headers['Authorization']
                    InFile = ''
                    Body = $Body
                })
            return [pscustomobject]@{ status = 'imported' }
        }

        [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', $null, 'User')
        [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', $processSecret, 'Process')
        try {
            $json = & $backfillScript -DashboardUrl 'https://example.test/' -SnapshotsRoot $snapshotRoot -PostOperation $postImportedBundle
            $result = $json | ConvertFrom-Json

            $result.Status | Should Be 'COMPLETED'
            $result.Uploaded | Should Be 4
            $result.Duplicates | Should Be 0
            @($global:backfillCalls).Count | Should Be 1
            @($global:backfillCalls | Where-Object { $_.Uri -ne 'https://example.test/api/sync/v1/seller-intelligence' }).Count | Should Be 0
            @($global:backfillCalls | Where-Object { $_.Authorization -ne "Bearer $processSecret" }).Count | Should Be 0
            @((([string]$global:backfillCalls[0].Body | ConvertFrom-Json).reports)).Count | Should Be 4
            $global:backfillCalls[0].InFile | Should Be ''
            $json | Should Not Match [regex]::Escape($processSecret)
        }
        finally {
            Remove-Variable -Name backfillCalls -Scope Global -ErrorAction SilentlyContinue
            [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', $null, 'Process')
        }
    }

    It 'throws for any seller-intelligence backfill response other than imported or duplicate' {
        $snapshotRoot = Join-Path $TestDrive 'snapshots-error'
        $sourceRoot = Join-Path $sharedSnapshotsRoot '2026-08-24'
        $targetRoot = Join-Path $snapshotRoot '2026-08-24'
        New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $sourceRoot 'amazon-bestsellers.json') -Destination (Join-Path $targetRoot 'amazon-bestsellers.json')
        Import-Module $receiptModulePath -Force
        $receipt = New-BestSellersCaptureReceipt -SnapshotPath (Join-Path $targetRoot 'amazon-bestsellers.json') -SourceConfigPath (Join-Path $projectRoot 'config\best-sellers-sources.json')
        Write-BestSellersCaptureReceipt -Receipt $receipt -Path (Join-Path $targetRoot 'best-sellers-capture-receipt.json') | Out-Null

        $postRejectedBundle = {
            param($Uri, $Method, $Headers, $ContentType, $Body)

            return [pscustomobject]@{ status = 'rejected' }
        }

        [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'seller-backfill-secret', 'Process')
        try {
            { & $backfillScript -DashboardUrl 'https://example.test/' -SnapshotsRoot $snapshotRoot -PostOperation $postRejectedBundle | Out-Null } | Should Throw 'Unexpected seller intelligence bundle sync result for 2026-08-24.'
        }
        finally {
            [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', $null, 'Process')
        }
    }
}
