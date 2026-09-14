$projectRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $projectRoot 'src\DashboardReportSelection.psm1'

Describe 'Dashboard report selection across Beijing and Amazon market dates' {
    BeforeEach {
        Remove-Module DashboardReportSelection -ErrorAction SilentlyContinue
        Import-Module $modulePath -Force
        $testRoot = Join-Path $TestDrive 'desktop-reports'
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        $names = @{
            pressure_washers = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('6auY5Y6L5riF5rSX5py6'))
            sump_pumps = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5rGh5rC05rO1'))
            pressure_washer_accessories = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('6auY5Y6L5riF5rSX5py66YWN5Lu2'))
            weekly = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5ZGo5oql'))
        }
        foreach ($directory in @($names.pressure_washers, $names.sump_pumps, $names.pressure_washer_accessories, $names.weekly)) {
            New-Item -ItemType Directory -Path (Join-Path $testRoot $directory) -Force | Out-Null
        }
        Set-Content -LiteralPath (Join-Path (Join-Path $testRoot $names.pressure_washers) 'Amazon_US_Best_Sellers_Pressure_Washers_2026-08-16_2026-08-17_0800_BJT.pdf') -Value 'daily'
        Set-Content -LiteralPath (Join-Path (Join-Path $testRoot $names.sump_pumps) 'Amazon_US_Best_Sellers_Sump_Pumps_2026-08-16_2026-08-17_0800_BJT.pdf') -Value 'daily'
        Set-Content -LiteralPath (Join-Path (Join-Path $testRoot $names.pressure_washer_accessories) 'Amazon_US_Best_Sellers_Pressure_Washer_Parts_Accessories_2026-08-16_2026-08-17_0800_BJT.pdf') -Value 'daily'
        Set-Content -LiteralPath (Join-Path (Join-Path $testRoot $names.weekly) 'Amazon_US_Weekly_Best_Sellers_Pressure_Washers_2026-08-17_2026-08-17_0600_BJT.pdf') -Value 'weekly'
        Set-Content -LiteralPath (Join-Path (Join-Path $testRoot $names.weekly) 'Amazon_US_Weekly_Best_Sellers_Sump_Pumps_2026-08-17_2026-08-17_0600_BJT.pdf') -Value 'weekly'
        Set-Content -LiteralPath (Join-Path (Join-Path $testRoot $names.weekly) 'Amazon_US_Weekly_Best_Sellers_Pressure_Washer_Parts_Accessories_2026-08-17_2026-08-17_0600_BJT.pdf') -Value 'weekly'
    }

    It 'selects Sunday US daily reports and Monday Beijing weekly reports in the same publish run' {
        $selected = @(Get-DashboardReportsToUpload -DesktopRoot $testRoot -MarketDate '2026-08-16' -BeijingDate '2026-08-17')

        @($selected | Where-Object Kind -eq 'daily').Count | Should Be 3
        @($selected | Where-Object Kind -eq 'weekly').Count | Should Be 3
        @($selected | Where-Object Kind -eq 'daily' | Select-Object -ExpandProperty ReportDate -Unique) | Should Be @('2026-08-16')
        @($selected | Where-Object Kind -eq 'weekly' | Select-Object -ExpandProperty ReportDate -Unique) | Should Be @('2026-08-17')
        @($selected | Where-Object Kind -eq 'weekly' | Select-Object -ExpandProperty Key) | Should Be @(
            'weekly/2026-08-17/pressure_washers.pdf',
            'weekly/2026-08-17/sump_pumps.pdf',
            'weekly/2026-08-17/pressure_washer_accessories.pdf'
        )
    }
}
