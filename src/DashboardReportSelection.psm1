Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'BestSellersCategoryRegistry.psm1') -Scope Local

function ConvertFrom-DashboardUtf8Base64([string]$Value) {
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value))
}

function Get-DashboardReportsToUpload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DesktopRoot,
        [Parameter(Mandatory = $true)][string]$MarketDate,
        [Parameter(Mandatory = $true)][string]$BeijingDate,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )

    $registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
    $definitions = @($registry.Categories | Where-Object Enabled | ForEach-Object {
        [pscustomobject]@{ Key=$_.CategoryKey; DailyDirectory=$_.LabelZh; DailyToken=$_.ReportFileToken; WeeklyToken=$_.ReportFileToken; Title=$_.LabelEn }
    })
    $weeklyDirectory = Join-Path $DesktopRoot (ConvertFrom-DashboardUtf8Base64 '5ZGo5oql')

    foreach ($definition in $definitions) {
        $dailyPattern = "Amazon_US_Best_Sellers_$($definition.DailyToken)_${MarketDate}_*.pdf"
        $dailyFile = Get-ChildItem -LiteralPath (Join-Path $DesktopRoot $definition.DailyDirectory) -File -Filter $dailyPattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($null -eq $dailyFile) { throw "Expected one daily PDF report per enabled category; missing $($definition.Key) for $MarketDate." }
        [pscustomobject]@{
            File = $dailyFile
            Kind = 'daily'
            Category = $definition.Key
            ReportDate = $MarketDate
            Key = "daily/$MarketDate/$($definition.Key).pdf"
            Title = "$($definition.Title) Daily Report $MarketDate BJT"
        }

        $weeklyPattern = "Amazon_US_Weekly_Best_Sellers_$($definition.WeeklyToken)_${BeijingDate}_*.pdf"
        $weeklyFile = Get-ChildItem -LiteralPath $weeklyDirectory -File -Filter $weeklyPattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($null -ne $weeklyFile) {
            [pscustomobject]@{
                File = $weeklyFile
                Kind = 'weekly'
                Category = $definition.Key
                ReportDate = $BeijingDate
                Key = "weekly/$BeijingDate/$($definition.Key).pdf"
                Title = "$($definition.Title) Weekly Report $BeijingDate BJT"
            }
        }
    }
}

Export-ModuleMember -Function 'Get-DashboardReportsToUpload'
