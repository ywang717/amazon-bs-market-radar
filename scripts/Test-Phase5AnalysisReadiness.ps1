param(
    [string]$SnapshotsRoot,
    [string]$SourceConfigPath,
    [ValidateRange(2, 30)][int]$RequiredMarketDays = 8,
    [ValidateRange(1, 100)][Nullable[int]]$TargetCount,
    [string]$AsOfDate,
    [string]$PolicyPath,
    [string]$NotBeforeDate,
    [switch]$RequireReady,
    [string]$RegistryPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) { $RegistryPath = Join-Path $projectRoot 'config\category-registry.json' }
if ([string]::IsNullOrWhiteSpace($SnapshotsRoot)) { $SnapshotsRoot = Join-Path $projectRoot 'var\amazon-bestsellers' }
if ([string]::IsNullOrWhiteSpace($SourceConfigPath)) { $SourceConfigPath = Join-Path $projectRoot 'config\best-sellers-sources.json' }
if ([string]::IsNullOrWhiteSpace($PolicyPath)) { $PolicyPath = Join-Path $projectRoot 'config\phase5-analysis-policy.json' }
if (-not (Test-Path -LiteralPath $PolicyPath -PathType Leaf)) { throw "Phase 5 analysis policy not found: $PolicyPath" }
$policy = Get-Content -LiteralPath $PolicyPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($NotBeforeDate)) { $NotBeforeDate = [string]$policy.first_eligible_analysis_date }
Import-Module (Join-Path $projectRoot 'src\BestSellersAnalysis.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersAnalysisReadiness.psm1') -Force
$allowInitialAnalysis = [bool]$policy.allow_initial_weekly_analysis_before_coverage
$readinessParameters = @{
    SnapshotsRoot=$SnapshotsRoot; SourceConfigPath=$SourceConfigPath; RequiredMarketDays=$RequiredMarketDays
    AsOfDate=$AsOfDate; NotBeforeDate=$NotBeforeDate; AllowAnalysisBeforeCoverage=$allowInitialAnalysis; RegistryPath=$RegistryPath
}
if ($null -ne $TargetCount) { $readinessParameters.TargetCount = [int]$TargetCount }
$result = Get-BestSellersAnalysisReadiness @readinessParameters
$result | Add-Member -NotePropertyName analysis_frequency_after_first_run -NotePropertyValue ([string]$policy.analysis_frequency_after_first_run) -Force
$result | ConvertTo-Json -Depth 10
if ($RequireReady -and -not $result.ready) { exit 2 }
