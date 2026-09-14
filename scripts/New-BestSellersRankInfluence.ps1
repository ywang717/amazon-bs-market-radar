param(
    [Parameter(Mandatory = $true)][string]$SnapshotPath,
    [string]$WeeklyAnalysisPath,
    [string]$OutputPath,
    [ValidateRange(3, 50)][int]$MinimumSample = 5,
    [string]$RegistryPath
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) { $RegistryPath = Join-Path $projectRoot 'config\category-registry.json' }
Import-Module (Join-Path $projectRoot 'src\BestSellersAnalysis.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersRankInfluence.psm1') -Force
$snapshot = Read-BestSellersSnapshot -Path $SnapshotPath -RegistryPath $RegistryPath
$weekly = if (-not [string]::IsNullOrWhiteSpace($WeeklyAnalysisPath)) { Get-Content -LiteralPath $WeeklyAnalysisPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$analysis = New-BestSellersRankInfluenceAnalysis -Snapshot $snapshot -WeeklyAnalysis $weekly -MinimumSample $MinimumSample -RegistryPath $RegistryPath
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Split-Path -Parent (Resolve-Path -LiteralPath $SnapshotPath).Path) 'best-sellers-rank-influence.json'
}
$artifactPath = Write-BestSellersRankInfluenceArtifact -Analysis $analysis -Path $OutputPath
$analyzed = @($analysis.categories | ForEach-Object { @($_.cross_sectional_associations | Where-Object { $_.status -eq 'ANALYZED' }) }).Count
[pscustomobject]@{ Status='SUCCEEDED'; MarketDate=$analysis.market_date; HistoryDayCount=$analysis.history_day_count; AnalyzedCrossSectionalAssociations=$analyzed; ArtifactPath=$artifactPath } | ConvertTo-Json -Depth 5
