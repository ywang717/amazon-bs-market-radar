Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'BestSellersCategoryRegistry.psm1') -Scope Local

function Get-BestSellersCategoryNames {
    param([string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json'))
    $registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
    return @(Get-BestSellersCategoryKeys -Registry $registry -EnabledOnly)
}

function Get-BestSellersPropertyValue {
    param($Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Read-BestSellersSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )

    if (-not (Test-Path -LiteralPath $Path)) { throw "Best Sellers snapshot not found: $Path" }
    $snapshot = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $snapshot) { throw 'Best Sellers snapshot is empty.' }
    if ([string]::IsNullOrWhiteSpace([string](Get-BestSellersPropertyValue -Object $snapshot -Name 'market_date'))) {
        throw 'Best Sellers snapshot is missing market_date.'
    }
    $presentCategoryCount = 0
    foreach ($categoryName in Get-BestSellersCategoryNames -RegistryPath $RegistryPath) {
        if ($null -ne $snapshot.PSObject.Properties[$categoryName]) { $presentCategoryCount++ }
    }
    if ($presentCategoryCount -eq 0) { throw 'Best Sellers snapshot contains no supported category.' }
    return $snapshot
}

function Test-BestSellersTop50Snapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Snapshot,
        [ValidateRange(1, 100)][Nullable[int]]$TargetCount,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )

    $registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
    $categoryNames = @(Get-BestSellersCategoryKeys -Registry $registry -EnabledOnly)
    $categoryResults = @()
    foreach ($categoryName in $categoryNames) {
        $category = Get-BestSellersCategory -Registry $registry -CategoryKey $categoryName
        $expectedCount = if ($null -ne $TargetCount) { [int]$TargetCount } else { [int]$category.TargetCount }
        $categoryPresent = $null -ne $Snapshot.PSObject.Properties[$categoryName]
        $items = @((Get-BestSellersPropertyValue -Object $Snapshot -Name $categoryName))
        $validItems = @($items | Where-Object { $null -ne $_ })
        $asins = @($validItems | ForEach-Object { [string](Get-BestSellersPropertyValue -Object $_ -Name 'asin') })
        $ranks = @($validItems | ForEach-Object { [int](Get-BestSellersPropertyValue -Object $_ -Name 'rank') })
        $duplicateAsins = @($asins | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
        $duplicateRanks = @($ranks | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { [int]$_.Name })
        $missingRanks = @()
        foreach ($expectedRank in 1..$expectedCount) {
            if ($ranks -notcontains $expectedRank) { $missingRanks += $expectedRank }
        }
        $outOfRangeRanks = @($ranks | Where-Object { $_ -lt 1 -or $_ -gt $expectedCount })
        $missingAsinCount = @($asins | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count
        $isComplete = $validItems.Count -eq $expectedCount -and $duplicateAsins.Count -eq 0 -and `
            $duplicateRanks.Count -eq 0 -and $missingRanks.Count -eq 0 -and $outOfRangeRanks.Count -eq 0 -and `
            $missingAsinCount -eq 0
        $categoryResults += [pscustomobject]@{
            category = $categoryName
            category_present = $categoryPresent
            target_count = $expectedCount
            item_count = $validItems.Count
            unique_asin_count = @($asins | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique).Count
            duplicate_asins = $duplicateAsins
            duplicate_ranks = $duplicateRanks
            missing_ranks = $missingRanks
            out_of_range_ranks = $outOfRangeRanks
            missing_asin_count = $missingAsinCount
            completeness_percent = [math]::Round(($validItems.Count * 100.0 / $expectedCount), 2)
            is_complete = $isComplete
        }
    }
    return [pscustomobject]@{
        target_count_per_category = if ($null -ne $TargetCount) { [int]$TargetCount } elseif (@($categoryResults.target_count | Select-Object -Unique).Count -eq 1) { [int]$categoryResults[0].target_count } else { $null }
        is_complete = @($categoryResults | Where-Object { -not $_.is_complete }).Count -eq 0
        categories = $categoryResults
    }
}

function New-BestSellersItemMap {
    param($Items)
    $map = @{}
    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        $asin = [string](Get-BestSellersPropertyValue -Object $item -Name 'asin')
        if ([string]::IsNullOrWhiteSpace($asin)) { continue }
        if (-not $map.ContainsKey($asin)) { $map[$asin] = $item }
    }
    return $map
}

function Compare-BestSellersSnapshots {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$CurrentSnapshot,
        $PreviousSnapshot,
        [ValidateRange(1, 100)][int]$SwingThreshold = 10,
        [ValidateRange(1, 100)][int]$HighPriorityThreshold = 20,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
    )

    if ($HighPriorityThreshold -lt $SwingThreshold) { throw 'HighPriorityThreshold must be greater than or equal to SwingThreshold.' }
    $hasBaseline = $null -ne $PreviousSnapshot
    $allChanges = @()
    $noteworthy = @()

    $categoryNames = @(Get-BestSellersCategoryNames -RegistryPath $RegistryPath)
    foreach ($categoryName in $categoryNames) {
        $currentItems = @((Get-BestSellersPropertyValue -Object $CurrentSnapshot -Name $categoryName))
        $categoryHasBaseline = $hasBaseline -and $null -ne $PreviousSnapshot.PSObject.Properties[$categoryName]
        $previousItems = if ($categoryHasBaseline) { @((Get-BestSellersPropertyValue -Object $PreviousSnapshot -Name $categoryName)) } else { @() }
        $currentMap = New-BestSellersItemMap -Items $currentItems
        $previousMap = New-BestSellersItemMap -Items $previousItems
        $allAsins = @($currentMap.Keys + $previousMap.Keys | Select-Object -Unique)

        foreach ($asin in $allAsins) {
            $current = if ($currentMap.ContainsKey($asin)) { $currentMap[$asin] } else { $null }
            $previous = if ($previousMap.ContainsKey($asin)) { $previousMap[$asin] } else { $null }
            $currentRank = if ($null -ne $current) { [int](Get-BestSellersPropertyValue -Object $current -Name 'rank') } else { $null }
            $previousRank = if ($null -ne $previous) { [int](Get-BestSellersPropertyValue -Object $previous -Name 'rank') } else { $null }
            $status = 'BASELINE'
            $rankChange = $null
            $absoluteChange = $null
            $priority = 'NONE'

            if ($categoryHasBaseline) {
                if ($null -eq $previous) { $status = 'NEW_IN_TOP50'; $priority = 'IMPORTANT' }
                elseif ($null -eq $current) { $status = 'DROPPED_FROM_TOP50'; $priority = 'IMPORTANT' }
                else {
                    $rankChange = $previousRank - $currentRank
                    $absoluteChange = [math]::Abs($rankChange)
                    if ($rankChange -gt 0) { $status = 'RISING' }
                    elseif ($rankChange -lt 0) { $status = 'FALLING' }
                    else { $status = 'UNCHANGED' }
                    if ($absoluteChange -ge $HighPriorityThreshold) { $priority = 'HIGH' }
                    elseif ($absoluteChange -ge $SwingThreshold) { $priority = 'WATCH' }
                }
            }

            $sourceItem = if ($null -ne $current) { $current } else { $previous }
            $change = [pscustomobject]@{
                category = $categoryName
                asin = $asin
                title = [string](Get-BestSellersPropertyValue -Object $sourceItem -Name 'title')
                url = [string](Get-BestSellersPropertyValue -Object $sourceItem -Name 'url')
                current_rank = $currentRank
                previous_rank = $previousRank
                rank_change = $rankChange
                absolute_change = $absoluteChange
                status = $status
                priority = $priority
                price = Get-BestSellersPropertyValue -Object $sourceItem -Name 'price'
                rating = Get-BestSellersPropertyValue -Object $sourceItem -Name 'rating'
                reviews = Get-BestSellersPropertyValue -Object $sourceItem -Name 'reviews'
            }
            $allChanges += $change
            if ($priority -ne 'NONE') { $noteworthy += $change }
        }
    }

    $noteworthy = @($noteworthy | Sort-Object @{ Expression = { if ($_.priority -eq 'HIGH') { 0 } elseif ($_.priority -eq 'IMPORTANT') { 1 } else { 2 } } }, `
        @{ Expression = { if ($null -eq $_.absolute_change) { 0 } else { -1 * $_.absolute_change } } }, category, current_rank)
    return [pscustomobject]@{
        current_market_date = [string](Get-BestSellersPropertyValue -Object $CurrentSnapshot -Name 'market_date')
        previous_market_date = if ($hasBaseline) { [string](Get-BestSellersPropertyValue -Object $PreviousSnapshot -Name 'market_date') } else { $null }
        has_baseline = $hasBaseline
        category_baselines = @($categoryNames | ForEach-Object {
            [pscustomobject]@{
                category = $_
                has_baseline = $hasBaseline -and $null -ne $PreviousSnapshot.PSObject.Properties[$_]
            }
        })
        swing_threshold = $SwingThreshold
        high_priority_threshold = $HighPriorityThreshold
        noteworthy_count = $noteworthy.Count
        noteworthy = $noteworthy
        changes = $allChanges
    }
}

function Write-BestSellersAnalysisArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Analysis,
        [Parameter(Mandatory = $true)]$Quality,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $artifact = [ordered]@{
        schema_version = 'best-sellers-analysis-v1'
        generated_at = [DateTimeOffset]::UtcNow.ToString('o')
        quality = $Quality
        analysis = $Analysis
    }
    [System.IO.File]::WriteAllText($Path, ($artifact | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
    return (Resolve-Path -LiteralPath $Path).Path
}

Export-ModuleMember -Function Read-BestSellersSnapshot, Test-BestSellersTop50Snapshot, Compare-BestSellersSnapshots, Write-BestSellersAnalysisArtifact
