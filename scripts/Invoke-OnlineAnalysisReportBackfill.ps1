param(
    [Parameter(Mandatory = $true)][uri]$DashboardUrl,
    [string]$SnapshotsRoot,
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $sourceRoot }
if ([string]::IsNullOrWhiteSpace($SnapshotsRoot)) { $SnapshotsRoot = Join-Path $ProjectRoot 'var\amazon-bestsellers' }
$secret = [Environment]::GetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET','User')
if ([string]::IsNullOrWhiteSpace($secret)) { $secret = [Environment]::GetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET','Process') }
if ([string]::IsNullOrWhiteSpace($secret)) { throw 'Dashboard sync secret is not configured.' }
$uploaded = 0; $duplicates = 0; $marketDates = @()
$endpoint = [uri]::new($DashboardUrl, '/api/sync/v1/analysis-reports')
$headers = @{ Authorization = "Bearer $secret" }
foreach ($directory in @(Get-ChildItem -LiteralPath $SnapshotsRoot -Directory -ErrorAction Stop | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' } | Sort-Object Name)) {
    $snapshotPath = Join-Path $directory.FullName 'amazon-bestsellers.json'
    if (-not (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) { continue }
    $run = & (Join-Path $sourceRoot 'scripts\New-OnlineAnalysisReports.ps1') -SnapshotPath $snapshotPath -SnapshotsRoot $SnapshotsRoot -ReportKind Daily | ConvertFrom-Json
    if ([string]$run.Status -ne 'CREATED' -or [int]$run.ReportCount -ne 4) { throw "Could not generate online analysis reports for $($directory.Name)." }
    foreach ($path in @($run.ReportPaths)) {
        $result = Invoke-RestMethod -Uri $endpoint -Method Post -Headers $headers -ContentType 'application/json' -InFile $path
        if ([string]$result.status -eq 'imported') { $uploaded++ } elseif ([string]$result.status -eq 'duplicate') { $duplicates++ } else { throw "Unexpected online analysis sync result for $path." }
    }
    $marketDates += $directory.Name
}
[pscustomobject]@{ Status='COMPLETED'; MarketDates=$marketDates; Uploaded=$uploaded; Duplicates=$duplicates } | ConvertTo-Json -Depth 5
