param(
    [Parameter(Mandatory = $true)][string]$CurrentPath,
    [string]$PreviousPath,
    [string]$OutputPath,
    [ValidateRange(1, 100)][int]$SwingThreshold = 10,
    [ValidateRange(1, 100)][int]$HighPriorityThreshold = 20,
    [switch]$AllowIncomplete,
    [ValidateRange(1, 100)][Nullable[int]]$TargetCount,
    [string]$RegistryPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) { $RegistryPath = Join-Path $projectRoot 'config\category-registry.json' }
Import-Module (Join-Path $PSScriptRoot '..\src\BestSellersAnalysis.psm1') -Force

$current = Read-BestSellersSnapshot -Path $CurrentPath -RegistryPath $RegistryPath
$previous = if ([string]::IsNullOrWhiteSpace($PreviousPath)) { $null } else { Read-BestSellersSnapshot -Path $PreviousPath -RegistryPath $RegistryPath }
$qualityParameters = @{ Snapshot=$current; RegistryPath=$RegistryPath }
if ($null -ne $TargetCount) { $qualityParameters.TargetCount = [int]$TargetCount }
$quality = Test-BestSellersTop50Snapshot @qualityParameters
if (-not $quality.is_complete -and -not $AllowIncomplete) {
    $summary = @($quality.categories | ForEach-Object { "$($_.category)=$($_.item_count)/$($_.target_count)" }) -join ', '
    throw "Best Sellers Registry target quality gate failed: $summary"
}
$analysis = Compare-BestSellersSnapshots -CurrentSnapshot $current -PreviousSnapshot $previous `
    -SwingThreshold $SwingThreshold -HighPriorityThreshold $HighPriorityThreshold -RegistryPath $RegistryPath
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Split-Path -Parent $CurrentPath) 'best-sellers-analysis.json'
}
$artifactPath = Write-BestSellersAnalysisArtifact -Analysis $analysis -Quality $quality -Path $OutputPath
[pscustomobject]@{
    Status = if ($quality.is_complete) { 'SUCCEEDED' } else { 'INCOMPLETE_ALLOWED' }
    CurrentMarketDate = $analysis.current_market_date
    PreviousMarketDate = $analysis.previous_market_date
    HasBaseline = $analysis.has_baseline
    NoteworthyCount = $analysis.noteworthy_count
    QualityPassed = $quality.is_complete
    ArtifactPath = $artifactPath
} | ConvertTo-Json -Depth 6
