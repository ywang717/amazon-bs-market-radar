param(
    [string]$SnapshotsRoot,
    [string]$ReportDate,
    [string]$OutputPath,
    [ValidateRange(1, 14)][int]$DayCount = 7,
    [string]$RegistryPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) { $RegistryPath = Join-Path $projectRoot 'config\category-registry.json' }
if ([string]::IsNullOrWhiteSpace($SnapshotsRoot)) { $SnapshotsRoot = Join-Path $projectRoot 'var\amazon-bestsellers' }
$chinaTimeZone = [TimeZoneInfo]::FindSystemTimeZoneById('America/Los_Angeles')
$generatedAtBeijing = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $chinaTimeZone)
if ([string]::IsNullOrWhiteSpace($ReportDate)) { $ReportDate = $generatedAtBeijing.ToString('yyyy-MM-dd') }
Import-Module (Join-Path $projectRoot 'src\BestSellersAnalysis.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersWeeklyAnalysis.psm1') -Force

$files = @(Get-ChildItem -LiteralPath $SnapshotsRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and $_.Name -le $ReportDate } |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName 'amazon-bestsellers.json' } |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First $DayCount)
if ($files.Count -eq 0) { throw 'No Best Sellers daily snapshots were found.' }
$snapshots = @($files | ForEach-Object { Read-BestSellersSnapshot -Path $_ -RegistryPath $RegistryPath })
$analysis = New-BestSellersWeeklyAnalysis -Snapshots $snapshots -RegistryPath $RegistryPath
$analysis | Add-Member -NotePropertyName generated_at_beijing -NotePropertyValue $generatedAtBeijing.ToString('yyyy-MM-dd HH:mm:ss zzz') -Force
$analysis | Add-Member -NotePropertyName report_timezone -NotePropertyValue 'America/Los_Angeles' -Force
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputDirectory = Join-Path (Join-Path (Join-Path $projectRoot 'var\reports') 'weekly') $ReportDate
    $timestampToken = $generatedAtBeijing.ToString('yyyy-MM-dd_HHmm') + '_BJT'
    $OutputPath = Join-Path $outputDirectory "Amazon_US_Weekly_Best_Sellers_Report_$timestampToken.json"
}
$artifactPath = Write-BestSellersWeeklyAnalysisArtifact -Analysis $analysis -Path $OutputPath
[pscustomobject]@{
    Status = if ($analysis.coverage_complete) { 'SUCCEEDED' } else { 'PARTIAL_COVERAGE' }
    GeneratedAtBeijing = $analysis.generated_at_beijing
    PeriodStart = $analysis.period_start; PeriodEnd = $analysis.period_end
    SnapshotDayCount = $analysis.snapshot_day_count
    LargeSwingCount = @($analysis.large_swings).Count
    NewEntryCount = @($analysis.new_entries).Count
    ExitCount = @($analysis.exits).Count
    ArtifactPath = $artifactPath
} | ConvertTo-Json -Depth 5
