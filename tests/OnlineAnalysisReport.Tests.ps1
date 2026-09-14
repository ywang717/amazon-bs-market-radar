$projectRoot = Split-Path -Parent $PSScriptRoot

Describe 'Online intelligent analysis report generator' {
    It 'generates only the requested complete market without authorizing an overview' {
        Import-Module (Join-Path $projectRoot 'src\OnlineAnalysisReport.psm1') -Force
        $rows = @(1..30 | ForEach-Object { [pscustomobject]@{ rank=$_; asin=('B{0:D9}' -f $_); title='Pump'; price=20; rating=4.5; reviews=100 } })
        $snapshot = [pscustomobject]@{ market_date='2026-08-24'; observed_at='2026-08-25T01:00:00Z'; pressure_washers=@(); sump_pumps=$rows; pressure_washer_accessories=@() }
        $reports = @(New-OnlineAnalysisReports -Snapshot $snapshot -ReceiptSha256 ('b' * 64) -ReportKind Daily -CategoryKey sump_pumps)
        $reports.Count | Should Be 1
        $reports[0].categoryKey | Should Be 'sump_pumps'
        $reports[0].evidence.complete | Should Be $true
        $rejected = $false
        try { New-OnlineAnalysisReports -Snapshot $snapshot -ReceiptSha256 ('b' * 64) -ReportKind Daily -CategoryKey pressure_washers } catch { $rejected = $true }
        $rejected | Should Be $true
    }
    It 'creates a quality disclosure instead of a trend conclusion from an incomplete snapshot' {
        Import-Module (Join-Path $projectRoot 'src\OnlineAnalysisReport.psm1') -Force
        $limited = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5pyJ6ZmQ'))
        $trend = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('6LaL5Yq/'))
        $association = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5YWz6IGU'))
        $noConclusion = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5pqC5LiN5LiL57uT6K66'))
        $incomplete = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5LiN5a6M5pW0'))
        $snapshot = [pscustomobject]@{
            market_date = '2026-08-24'
            observed_at = '2026-08-25T01:00:00Z'
            pressure_washers = @([pscustomobject]@{ rank = 1; asin = 'B000000001'; title = 'Example'; url = 'https://www.amazon.com/dp/B000000001'; price = '$20.00'; rating = 4.5; reviews = 100 })
            sump_pumps = @()
            pressure_washer_accessories = @()
        }

        $reports = @(New-OnlineAnalysisReports -Snapshot $snapshot -ReceiptSha256 ('a' * 64) -ReportKind Daily)

        $reports.Count | Should Be 4
        $reports[0].evidence.level | Should Be $limited
        (@($reports[0].sections | ForEach-Object title) -join ' ') | Should Not Match ($trend + '|' + $association)
        ($reports[0].sections.statements -join ' ') | Should Match ($noConclusion + '|' + $incomplete)
    }

    It 'returns four independently writable report paths' {
        Import-Module (Join-Path $projectRoot 'src\OnlineAnalysisReport.psm1') -Force
        $snapshot = [pscustomobject]@{ market_date='2026-08-24'; observed_at='2026-08-25T01:00:00Z'; pressure_washers=@(); sump_pumps=@(); pressure_washer_accessories=@() }
        $reports = @(New-OnlineAnalysisReports -Snapshot $snapshot -ReceiptSha256 ('b' * 64) -ReportKind Daily)
        $paths = @(Write-OnlineAnalysisReports -Reports $reports -OutputDirectory $TestDrive)

        $paths.Count | Should Be 4
        @($paths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }).Count | Should Be 4
    }
}
