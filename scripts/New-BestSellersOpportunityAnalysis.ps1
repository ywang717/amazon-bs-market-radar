param(
    [Parameter(Mandatory = $true)][string]$WeeklyAnalysisPath,
    [string]$OutputPath,
    [ValidateRange(2, 30)][int]$RequiredHistoryDays = 7
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src\BestSellersOpportunityAnalysis.psm1') -Force

if (-not (Test-Path -LiteralPath $WeeklyAnalysisPath -PathType Leaf)) {
    throw "Weekly analysis artifact not found: $WeeklyAnalysisPath"
}
$weekly = Get-Content -LiteralPath $WeeklyAnalysisPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$weekly.schema_version -ne 'best-sellers-weekly-analysis-v1') {
    throw 'Unsupported weekly analysis schema version.'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $directory = Split-Path -Parent (Resolve-Path -LiteralPath $WeeklyAnalysisPath).Path
    $baseName = [IO.Path]::GetFileNameWithoutExtension($WeeklyAnalysisPath)
    $OutputPath = Join-Path $directory ($baseName + '-opportunity.json')
}

$analysis = New-BestSellersOpportunityAnalysis -WeeklyAnalysis $weekly -RequiredHistoryDays $RequiredHistoryDays
$artifactPath = Write-BestSellersOpportunityArtifact -Analysis $analysis -Path $OutputPath
$allProducts = @($analysis.categories | ForEach-Object { @($_.products) })
[pscustomobject]@{
    Status = if ($analysis.snapshot_day_count -lt 2) { 'BASELINE_INSUFFICIENT' } elseif (@($allProducts | Where-Object { $_.classification -eq 'LOW_CONFIDENCE' }).Count -gt 0) { 'PARTIAL_CONFIDENCE' } else { 'SUCCEEDED' }
    ModelVersion = $analysis.model_version
    PeriodStart = $analysis.period_start
    PeriodEnd = $analysis.period_end
    SnapshotDayCount = $analysis.snapshot_day_count
    ProductCount = $allProducts.Count
    HighOpportunityCount = @($allProducts | Where-Object { $_.classification -eq 'HIGH_OPPORTUNITY' }).Count
    FlaggedSignalCount = @($allProducts | Where-Object { @($_.signals).Count -gt 0 }).Count
    ArtifactPath = $artifactPath
} | ConvertTo-Json -Depth 5
