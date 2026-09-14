Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'BestSellersCategoryRegistry.psm1') -Scope Local

function ConvertFrom-OnlineAnalysisUtf8Base64([string]$Value) {
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value))
}

$script:OnlineAnalysisText = @{
    sufficient = ConvertFrom-OnlineAnalysisUtf8Base64 '5YWF5YiG'
    usable = ConvertFrom-OnlineAnalysisUtf8Base64 '5Y+v55So'
    limited = ConvertFrom-OnlineAnalysisUtf8Base64 '5pyJ6ZmQ'
    summary = ConvertFrom-OnlineAnalysisUtf8Base64 '57uT6K665pGY6KaB'
    incomplete_now = ConvertFrom-OnlineAnalysisUtf8Base64 '5b2T5YmN5pWw5o2u5LiN5a6M5pW077yM5pqC5LiN5LiL57uT6K6644CC'
    quality = ConvertFrom-OnlineAnalysisUtf8Base64 '5pWw5o2u6LSo6YeP'
    incomplete_detail = ConvertFrom-OnlineAnalysisUtf8Base64 '5bey6aqM6K+B6KeC5rWLIHswfSDmnaHvvJvnvLrlpLHmjpLlkI3miJbph43lpI3llYblk4Hml7bkuI3nlJ/miJblhbPogZTnu5PorrrjgII='
    complete_today = ConvertFrom-OnlineAnalysisUtf8Base64 '5b2T5pel5Z2H5Li655yf5a6e5Y+v6aqM6K+B55qE5a6M5pW0IFRvcCAzMOOAgg=='
    daily_change = ConvertFrom-OnlineAnalysisUtf8Base64 '5pel5bqm5Y+Y5YyW'
    comparable_daily = ConvertFrom-OnlineAnalysisUtf8Base64 '55u46YK75biC5Zy65pel5Z2H5a6M5pW077yM5o6S5ZCN5Y+Y5YyW5LuF5L2c5o+P6L+w5oCn6KeC5a+f77yb5piO5pi+5byC5Yqo5Lul57ud5a+55Y+Y5YyW5LiN5bCR5LqOIDEwIOWQjeS4uuWHhuOAgg=='
    previous_incomplete = ConvertFrom-OnlineAnalysisUtf8Base64 '5LiK5LiA5biC5Zy65pel5LiN5a6M5pW077yM5pqC5LiN5q+U6L6D5o6S5ZCN5Y+Y5YyW44CC'
    weekly_summary = ConvertFrom-OnlineAnalysisUtf8Base64 '5ZGo5bqm5oql5ZGK5Z+65LqOIHswfSDkuKrlrozmlbTluILlnLrml6XjgII='
    weekly_trend = ConvertFrom-OnlineAnalysisUtf8Base64 '5ZGo5bqm6LaL5Yq/'
    weekly_trend_detail = ConvertFrom-OnlineAnalysisUtf8Base64 '6LaL5Yq/5LuF5o+P6L+w5Y+v6aqM6K+B5o6S5ZCN44CB55WZ5a2Y5ZKM5a2X5q616KaG55uW55qE5YWx5ZCM5Y+Y5YyW77yM5LiN5Luj6KGo5Zug5p6c5YWz57O744CC'
    weekly_insufficient = ConvertFrom-OnlineAnalysisUtf8Base64 '5a6M5pW05biC5Zy65pel5LiN6LazIDUg5Liq77yM5pqC5LiN5LiL57uT6K6677yM5LiN5bGV56S65ZGo5bqm6LaL5Yq/5oiW5oyH5qCH5YWz6IGU44CC'
}

function Get-OnlineAnalysisCategories {
    param([string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json'))
    $registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
    return @($registry.Categories | Where-Object Enabled | ForEach-Object {
        [pscustomobject]@{ Key = [string]$_.CategoryKey; Label = [string]$_.LabelZh; TargetCount = [int]$_.TargetCount }
    })
}

function Get-OnlineAnalysisProperty {
    param($Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-OnlineAnalysisCategoryQuality {
    param($Items, [ValidateRange(1,100)][int]$TargetCount = 30)
    $rows = @($Items | Where-Object { $null -ne $_ })
    $ranks = @($rows | ForEach-Object { Get-OnlineAnalysisProperty -Object $_ -Name 'rank' })
    $rankSet = [System.Collections.Generic.HashSet[int]]::new()
    $asinSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $rows) {
        $rank = Get-OnlineAnalysisProperty -Object $row -Name 'rank'
        if ($rank -is [int] -or $rank -is [long]) { [void]$rankSet.Add([int]$rank) }
        $asin = [string](Get-OnlineAnalysisProperty -Object $row -Name 'asin')
        if (-not [string]::IsNullOrWhiteSpace($asin)) { [void]$asinSet.Add($asin) }
    }
    $missing = @(1..$TargetCount | Where-Object { -not $rankSet.Contains($_) })
    $complete = $rows.Count -eq $TargetCount -and $missing.Count -eq 0 -and $asinSet.Count -eq $TargetCount
    $fieldCoverage = @{}
    foreach ($field in @('price','rating','reviews')) {
        $present = @($rows | Where-Object { $null -ne (Get-OnlineAnalysisProperty -Object $_ -Name $field) }).Count
        $fieldCoverage[$field] = if ($rows.Count) { [math]::Round($present * 100.0 / $rows.Count, 1) } else { 0.0 }
    }
    return [pscustomobject]@{ Complete=$complete; Count=$rows.Count; Missing=@($missing); FieldCoverage=[pscustomobject]$fieldCoverage }
}

function Get-OnlineAnalysisEvidenceLevel {
    param([int]$CompleteMarketDays)
    if ($CompleteMarketDays -ge 5) { return $script:OnlineAnalysisText.sufficient }
    if ($CompleteMarketDays -ge 2) { return $script:OnlineAnalysisText.usable }
    return $script:OnlineAnalysisText.limited
}

function Get-OnlineAnalysisContentHash {
    param([Parameter(Mandatory = $true)]$Content)
    $text = $Content | ConvertTo-Json -Depth 12 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) }
    finally { $sha.Dispose() }
}

function New-OnlineAnalysisReport {
    param(
        [Parameter(Mandatory = $true)]$Snapshot,
        [Parameter(Mandatory = $true)][string]$ReceiptSha256,
        [Parameter(Mandatory = $true)][ValidateSet('Daily','Weekly')][string]$ReportKind,
        $Category,
        $PreviousSnapshot,
        [int]$CompleteMarketDays = 1,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )
    $onlineCategories = @(Get-OnlineAnalysisCategories -RegistryPath $RegistryPath)
    $selected = @()
    if ($null -eq $Category) { $selected += $onlineCategories } else { $selected += $Category }
    $qualities = @($selected | ForEach-Object { Get-OnlineAnalysisCategoryQuality -Items (Get-OnlineAnalysisProperty -Object $Snapshot -Name $_.Key) -TargetCount $_.TargetCount })
    $complete = @($qualities | Where-Object Complete).Count -eq $selected.Count
    $sampleSize = ($qualities | Measure-Object -Property Count -Sum).Sum
    $coverage = [pscustomobject]@{
        price = [math]::Round((@($qualities | ForEach-Object { $_.FieldCoverage.price } | Measure-Object -Average).Average), 1)
        rating = [math]::Round((@($qualities | ForEach-Object { $_.FieldCoverage.rating } | Measure-Object -Average).Average), 1)
        reviews = [math]::Round((@($qualities | ForEach-Object { $_.FieldCoverage.reviews } | Measure-Object -Average).Average), 1)
    }
    $level = Get-OnlineAnalysisEvidenceLevel -CompleteMarketDays $CompleteMarketDays
    $scopeLabel = if ($null -eq $Category) { @($onlineCategories | ForEach-Object Label) -join '、' } else { $Category.Label }
    $sections = @([pscustomobject]@{ title=$script:OnlineAnalysisText.summary; statements=@() })
    if (-not $complete) {
        $sections[0].statements += "$scopeLabel $($script:OnlineAnalysisText.incomplete_now)"
        $sections += [pscustomobject]@{ title=$script:OnlineAnalysisText.quality; statements=@(($script:OnlineAnalysisText.incomplete_detail -f $sampleSize)) }
    }
    elseif ($ReportKind -eq 'Daily') {
        $sections[0].statements += "$scopeLabel $($script:OnlineAnalysisText.complete_today)"
        if ($null -ne $PreviousSnapshot) {
            $previousComplete = @($selected | ForEach-Object { Get-OnlineAnalysisCategoryQuality -Items (Get-OnlineAnalysisProperty -Object $PreviousSnapshot -Name $_.Key) -TargetCount $_.TargetCount } | Where-Object Complete).Count -eq $selected.Count
            if ($previousComplete) { $sections += [pscustomobject]@{ title=$script:OnlineAnalysisText.daily_change; statements=@($script:OnlineAnalysisText.comparable_daily) } }
            else { $sections += [pscustomobject]@{ title=$script:OnlineAnalysisText.quality; statements=@($script:OnlineAnalysisText.previous_incomplete) } }
        }
    }
    else {
        $sections[0].statements += "$scopeLabel $($script:OnlineAnalysisText.weekly_summary -f $CompleteMarketDays)"
        if ($CompleteMarketDays -ge 5) { $sections += [pscustomobject]@{ title=$script:OnlineAnalysisText.weekly_trend; statements=@($script:OnlineAnalysisText.weekly_trend_detail) } }
        else { $sections += [pscustomobject]@{ title=$script:OnlineAnalysisText.quality; statements=@($script:OnlineAnalysisText.weekly_insufficient) } }
    }
    $kind = $ReportKind.ToLowerInvariant()
    $scope = if ($null -eq $Category) { 'overview' } else { $Category.Key }
    $observedAt = [DateTimeOffset]::MinValue
    $generatedAt = if ([DateTimeOffset]::TryParse([string]$Snapshot.observed_at, [ref]$observedAt)) { $observedAt.ToUniversalTime().ToString('o') } else { [DateTimeOffset]::UtcNow.ToString('o') }
    $content = [ordered]@{
        schemaVersion='amazon-bs-analysis-report-v1'; key="$kind/$($Snapshot.market_date)/$scope.json"; reportKind=$kind; marketDate=[string]$Snapshot.market_date; categoryKey=if ($null -eq $Category) { $null } else { $Category.Key }
        generatedAt=$generatedAt; generatorVersion='rules-v1'; receiptSha256=$ReceiptSha256
        evidence=[ordered]@{ level=$level; completeMarketDays=$CompleteMarketDays; sampleSize=[int]$sampleSize; complete=$complete; fieldCoverage=$coverage }
        sections=@($sections)
    }
    $content.contentSha256 = Get-OnlineAnalysisContentHash -Content $content
    return [pscustomobject]$content
}

function New-OnlineAnalysisReports {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Snapshot,
        [Parameter(Mandatory = $true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ReceiptSha256,
        [Parameter(Mandatory = $true)][ValidateSet('Daily','Weekly')][string]$ReportKind,
        $PreviousSnapshot,
        [ValidateRange(0,365)][int]$CompleteMarketDays = 1,
        [string]$CategoryKey,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )
    $onlineCategories = @(Get-OnlineAnalysisCategories -RegistryPath $RegistryPath)
    if (-not [string]::IsNullOrWhiteSpace($CategoryKey)) {
        if ($ReportKind -ne 'Daily') { throw 'Category-scoped reports require Daily kind.' }
        $selected = @($onlineCategories | Where-Object { $_.Key -ceq $CategoryKey })
        if ($selected.Count -ne 1) { throw 'Unknown analysis report category.' }
        $report = New-OnlineAnalysisReport -Snapshot $Snapshot -ReceiptSha256 $ReceiptSha256 -ReportKind $ReportKind -Category $selected[0] -PreviousSnapshot $PreviousSnapshot -CompleteMarketDays $CompleteMarketDays -RegistryPath $RegistryPath
        if (-not $report.evidence.complete) { throw 'Category-scoped reports require a complete market.' }
        return $report
    }
    $reports = @(New-OnlineAnalysisReport -Snapshot $Snapshot -ReceiptSha256 $ReceiptSha256 -ReportKind $ReportKind -PreviousSnapshot $PreviousSnapshot -CompleteMarketDays $CompleteMarketDays -RegistryPath $RegistryPath)
    foreach ($category in $onlineCategories) { $reports += New-OnlineAnalysisReport -Snapshot $Snapshot -ReceiptSha256 $ReceiptSha256 -ReportKind $ReportKind -Category $category -PreviousSnapshot $PreviousSnapshot -CompleteMarketDays $CompleteMarketDays -RegistryPath $RegistryPath }
    return $reports
}

function Write-OnlineAnalysisReports {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Reports, [Parameter(Mandatory = $true)][string]$OutputDirectory)
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $paths = @()
    foreach ($report in @($Reports)) {
        $relative = ([string]$report.key).Replace('/','\\')
        $path = Join-Path $OutputDirectory $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        [IO.File]::WriteAllText($path, ($report | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
        $paths += $path
    }
    return $paths
}

Export-ModuleMember -Function New-OnlineAnalysisReports, Write-OnlineAnalysisReports
