$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src/BestSellersAnalysis.psm1') -Force
Import-Module (Join-Path $projectRoot 'src/BestSellersDailyReport.psm1') -Force
Describe 'Daily report Pacific timestamp disclosure' {
    It 'renders the actual Pacific timestamp and label through daylight saving changes' {
        $registry = Get-Content (Join-Path $projectRoot 'config/category-registry.json') -Raw | ConvertFrom-Json
        $snapshot = [ordered]@{ market_date='2026-10-18'; observed_at='2026-10-19T00:00:00Z' }
        foreach ($category in $registry.categories) {
            $snapshot[$category.category_key] = @(foreach ($rank in 1..30) { [pscustomobject]@{asin=('B{0:D9}' -f $rank);rank=$rank;title="Audit item $rank";url="https://www.amazon.com/dp/B$('{0:D9}' -f $rank)";price=20;rating=4.5;reviews=100} })
        }
        foreach ($case in @(@{utc='2026-10-19T00:30:00Z';expected='2026-10-18 17:30'},@{utc='2026-12-20T00:30:00Z';expected='2026-12-19 16:30'})) {
            $report=New-BestSellersDailyReport -CurrentSnapshot ([pscustomobject]$snapshot) -CategoryKeys pressure_washers -GeneratedAtBeijing ([datetimeoffset]$case.utc) -OutputDirectory (Join-Path $TestDrive $case.utc.Substring(0,10))
            $report.Subject | Should Match 'Pacific Time'
            $report.Subject | Should Not Match '北京时间'
            $report.Subject | Should Match $case.expected
            $report.MarketDate | Should Be '2026-10-18'
            (Get-Content $report.MarkdownPath -Raw -Encoding UTF8) | Should Match 'Pacific Time'
        }
    }
}
