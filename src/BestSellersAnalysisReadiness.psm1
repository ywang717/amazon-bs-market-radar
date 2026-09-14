Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'BestSellersCategoryRegistry.psm1') -Scope Local

function Get-AnalysisReadinessPropertyValue {
    param($Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-BestSellersAnalysisReadiness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SnapshotsRoot,
        [Parameter(Mandatory = $true)][string]$SourceConfigPath,
        [ValidateRange(2, 30)][int]$RequiredMarketDays = 8,
        [ValidateRange(1, 100)][Nullable[int]]$TargetCount,
        [string]$AsOfDate,
        [string]$NotBeforeDate,
        [switch]$AllowAnalysisBeforeCoverage,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )
    if (-not (Test-Path -LiteralPath $SourceConfigPath -PathType Leaf)) { throw "Source config not found: $SourceConfigPath" }
    if (-not (Test-Path -LiteralPath $SnapshotsRoot -PathType Container)) { throw "Snapshot root not found: $SnapshotsRoot" }
    $registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
    $categories = @(Get-BestSellersCategoryKeys -Registry $registry -EnabledOnly)
    if ($categories.Count -eq 0) { throw 'No active Best Sellers categories are configured.' }
    $validDatesByCategory = @{}
    $observedDatesByCategory = @{}
    $targetByCategory = @{}
    foreach ($category in $categories) {
        $validDatesByCategory[$category] = @(); $observedDatesByCategory[$category] = @()
        $targetByCategory[$category] = if ($null -ne $TargetCount) { [int]$TargetCount } else { [int](Get-BestSellersCategory -Registry $registry -CategoryKey $category).TargetCount }
    }

    $effectiveAsOfDate = $AsOfDate
    if ([string]::IsNullOrWhiteSpace($effectiveAsOfDate)) {
        $chinaTimeZone = try { [TimeZoneInfo]::FindSystemTimeZoneById('China Standard Time') } catch { [TimeZoneInfo]::FindSystemTimeZoneById('Asia/Shanghai') }
        $effectiveAsOfDate = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $chinaTimeZone).ToString('yyyy-MM-dd')
    }
    if ($effectiveAsOfDate -notmatch '^\d{4}-\d{2}-\d{2}$') { throw 'AsOfDate must use yyyy-MM-dd.' }
    if (-not [string]::IsNullOrWhiteSpace($NotBeforeDate) -and $NotBeforeDate -notmatch '^\d{4}-\d{2}-\d{2}$') { throw 'NotBeforeDate must use yyyy-MM-dd.' }
    $snapshotFiles = @(Get-ChildItem -LiteralPath $SnapshotsRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and $_.Name -le $effectiveAsOfDate } |
        Sort-Object Name | ForEach-Object { Join-Path $_.FullName 'amazon-bestsellers.json' } |
        Where-Object { Test-Path -LiteralPath $_ })

    foreach ($file in $snapshotFiles) {
        $snapshot = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
        $marketDate = [string](Get-AnalysisReadinessPropertyValue -Object $snapshot -Name 'market_date')
        if ($marketDate -notmatch '^\d{4}-\d{2}-\d{2}$') { continue }
        $qualityParameters = @{ Snapshot=$snapshot; RegistryPath=$RegistryPath }
        if ($null -ne $TargetCount) { $qualityParameters.TargetCount = [int]$TargetCount }
        $quality = Test-BestSellersTop50Snapshot @qualityParameters
        foreach ($category in $categories) {
            if ($null -eq $snapshot.PSObject.Properties[$category]) { continue }
            $observedDatesByCategory[$category] += $marketDate
            $categoryQuality = @($quality.categories | Where-Object { $_.category -eq $category }) | Select-Object -First 1
            if ($null -ne $categoryQuality -and $categoryQuality.is_complete) { $validDatesByCategory[$category] += $marketDate }
        }
    }

    $categoryResults = @()
    foreach ($category in $categories) {
        $validDates = @($validDatesByCategory[$category] | Select-Object -Unique | Sort-Object)
        $observedDates = @($observedDatesByCategory[$category] | Select-Object -Unique | Sort-Object)
        $categoryResults += [pscustomobject]@{
            category = $category
            target_count = [int]$targetByCategory[$category]
            required_market_days = $RequiredMarketDays
            valid_market_day_count = $validDates.Count
            observed_market_day_count = $observedDates.Count
            missing_valid_days = [math]::Max(0, $RequiredMarketDays - $validDates.Count)
            valid_market_dates = $validDates
            observed_market_dates = $observedDates
            ready = $validDates.Count -ge $RequiredMarketDays
            status = if ($validDates.Count -ge $RequiredMarketDays) { 'READY' } elseif ($observedDates.Count -gt $validDates.Count) { 'INCOMPLETE_SNAPSHOTS_PRESENT' } else { 'COLLECTING' }
        }
    }
    $coverageReady = @($categoryResults | Where-Object { -not $_.ready }).Count -eq 0
    $dateReady = [string]::IsNullOrWhiteSpace($NotBeforeDate) -or $effectiveAsOfDate -ge $NotBeforeDate
    $analysisDue = $dateReady -and ($coverageReady -or $AllowAnalysisBeforeCoverage)
    $ready = $coverageReady -and $dateReady
    return [pscustomobject]@{
        schema_version = 'best-sellers-analysis-readiness-v1'
        generated_at = [DateTimeOffset]::UtcNow.ToString('o')
        snapshots_root = (Resolve-Path -LiteralPath $SnapshotsRoot).Path
        as_of_date = $effectiveAsOfDate
        first_eligible_analysis_date = $NotBeforeDate
        date_ready = $dateReady
        coverage_ready = $coverageReady
        target_count = if ($null -ne $TargetCount) { [int]$TargetCount } elseif (@($targetByCategory.Values | Select-Object -Unique).Count -eq 1) { [int]@($targetByCategory.Values)[0] } else { $null }
        required_market_days = $RequiredMarketDays
        status = if ($ready) { 'READY_FOR_FULL_PHASE_5_ANALYSIS' } elseif ($analysisDue) { 'READY_FOR_LIMITED_WEEKLY_ANALYSIS' } else { 'COLLECTING_BASELINE' }
        ready = $ready
        analysis_due = $analysisDue
        analysis_mode = if ($ready) { 'FULL' } elseif ($analysisDue) { 'LIMITED_WEEKLY' } else { 'COLLECTING_ONLY' }
        categories = $categoryResults
        policy = 'Run Phase 5 analysis on or after the configured date only when full coverage is ready, unless the policy explicitly allows a limited initial weekly analysis before coverage.'
    }
}

Export-ModuleMember -Function Get-BestSellersAnalysisReadiness
