$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src\BestSellersWeeklyAnalysis.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersWeeklyReportContent.psm1') -Force

function New-FinalFixDiscountItem {
    param(
        [string]$Asin,
        [int]$Rank,
        $HasDiscount,
        $Discounts
    )
    [pscustomobject]@{
        asin = $Asin
        rank = $Rank
        title = "Item $Asin"
        url = "https://www.amazon.com/dp/$Asin"
        price = '$100.00'
        rating = 4.5
        reviews = 100
        has_discount = $HasDiscount
        discounts = @($Discounts)
    }
}

function New-FinalFixSnapshot {
    param([string]$Date, $Pressure)
    [pscustomobject]@{
        market_date = $Date
        pressure_washers = @($Pressure)
        sump_pumps = @()
        pressure_washer_accessories = @()
    }
}

Describe 'Final review discount-history regressions' {
    It 'loads the weekly report module in Windows PowerShell' {
        $modulePath = Join-Path $projectRoot 'src\BestSellersWeeklyReportContent.psm1'
        $escapedPath = $modulePath.Replace("'", "''")
        $result = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Import-Module '$escapedPath' -Force -ErrorAction Stop; 'MODULE_LOADED'")

        $LASTEXITCODE | Should Be 0
        ($result -join "`n") | Should Match 'MODULE_LOADED'
    }

    It 'preserves an unknown adjacent observation as a detail row without adding it to known-state counts' {
        $coupon = [pscustomobject]@{ kind = 'COUPON'; amount = '$10.00 off' }
        $day1 = New-FinalFixSnapshot '2026-08-18' @(
            (New-FinalFixDiscountItem 'B0UNKNOWN01' 20 $null @())
        )
        $day2 = New-FinalFixSnapshot '2026-08-19' @(
            (New-FinalFixDiscountItem 'B0UNKNOWN01' 8 $true @($coupon))
        )

        $analysis = New-BestSellersWeeklyAnalysis -Snapshots @($day1, $day2)
        $rows = @($analysis.discount_transitions | Where-Object { $_.category -eq 'pressure_washers' })
        $summary = @($analysis.categories | Where-Object { $_.category -eq 'pressure_washers' })[0].discount_summary

        $rows.Count | Should Be 1
        $rows[0].asin | Should Be 'B0UNKNOWN01'
        $rows[0].transition_kind | Should Be 'UNKNOWN'
        $rows[0].previous_has_discount | Should Be $null
        $rows[0].has_discount | Should Be $true
        $rows[0].previous_rank | Should Be 20
        $rows[0].current_rank | Should Be 8
        $rows[0].rank_change | Should Be 12
        $summary.added_count | Should Be 0
        $summary.removed_count | Should Be 0
        $summary.amount_changed_count | Should Be 0
        $summary.unchanged_count | Should Be 0
        $summary.unknown_count | Should Be 1
    }

    It 'counts a single discount transition row as one section result' {
        $weeklyAnalysis = [pscustomobject]@{
            categories = @(
                [pscustomobject]@{
                    category = 'pressure_washers'
                    discount_summary = [pscustomobject]@{
                        added_count = 0
                        removed_count = 0
                        amount_changed_count = 0
                        unchanged_count = 0
                        unknown_count = 1
                    }
                }
            )
            large_swings = @()
            new_entries = @()
            exits = @()
            discount_transitions = @(
                [pscustomobject]@{
                    category = 'pressure_washers'
                    asin = 'B0UNKNOWN01'
                    previous_market_date = '2026-08-18'
                    market_date = '2026-08-19'
                    previous_has_discount = $null
                    has_discount = $true
                    previous_discounts = @()
                    discounts = @([pscustomobject]@{ kind = 'COUPON'; amount = '$10.00 off' })
                    previous_rank = 20
                    current_rank = 8
                    rank_change = 12
                    transition_kind = 'UNKNOWN'
                }
            )
        }
        $rankInfluence = [pscustomobject]@{
            categories = @(
                [pscustomobject]@{
                    category = 'pressure_washers'
                    cross_sectional_associations = @()
                    longitudinal_associations = @()
                }
            )
        }

        $result = New-BestSellersWeeklyCategorySections -CategoryKey 'pressure_washers' -WeeklyAnalysis $weeklyAnalysis -RankInfluence $rankInfluence

        $result.DiscountTransitionCount | Should Be 1
    }

    It 'renders both sides of an unknown observation as unavailable while retaining its ranks' {
        $coupon = [pscustomobject]@{ kind = 'COUPON'; amount = '$10.00 off' }
        $analysis = New-BestSellersWeeklyAnalysis -Snapshots @(
            (New-FinalFixSnapshot '2026-08-18' @((New-FinalFixDiscountItem 'B0UNKNOWN01' 20 $null @()))),
            (New-FinalFixSnapshot '2026-08-19' @((New-FinalFixDiscountItem 'B0UNKNOWN01' 8 $true @($coupon))))
        )
        $rankInfluence = [pscustomobject]@{
            categories = @(
                [pscustomobject]@{
                    category = 'pressure_washers'
                    cross_sectional_associations = @()
                    longitudinal_associations = @()
                }
            )
        }

        $result = New-BestSellersWeeklyCategorySections -CategoryKey 'pressure_washers' -WeeklyAnalysis $analysis -RankInfluence $rankInfluence

        $result.DiscountTransitionCount | Should Be 1
        $result.Markdown | Should Match 'B0UNKNOWN01'
        $result.Markdown | Should Match '\| Unavailable \| Unavailable \| UNKNOWN \| Unavailable \| Unavailable \| 20 \| 8 \| \+12 \|'
        $result.Html | Should Match 'B0UNKNOWN01'
        $result.Html | Should Match '<td>Unavailable</td><td>Unavailable</td><td>UNKNOWN</td><td>Unavailable</td><td>Unavailable</td><td>20</td><td>8</td><td>\+12</td>'
    }

}
