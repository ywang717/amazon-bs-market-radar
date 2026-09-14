param(
    [Parameter(Mandatory = $true)][uri]$DashboardUrl,
    [string]$SnapshotsRoot,
    [string]$ProjectRoot,
    [ValidateSet('Daily','Weekly')][string]$ReportKind = 'Daily',
    [scriptblock]$PostOperation
)

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $sourceRoot }
if ([string]::IsNullOrWhiteSpace($SnapshotsRoot)) { $SnapshotsRoot = Join-Path $ProjectRoot 'var\amazon-bestsellers' }

$secret = [Environment]::GetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'User')
if ([string]::IsNullOrWhiteSpace($secret)) { $secret = [Environment]::GetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'Process') }
if ([string]::IsNullOrWhiteSpace($secret)) { throw 'Dashboard sync secret is not configured.' }

$uploaded = 0
$duplicates = 0
$marketDates = @()
$endpoint = [uri]::new($DashboardUrl, '/api/sync/v1/seller-intelligence')
$headers = @{ Authorization = "Bearer $secret" }
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('seller-intelligence-backfill-' + [guid]::NewGuid().ToString('N'))

try {
    foreach ($directory in @(Get-ChildItem -LiteralPath $SnapshotsRoot -Directory -ErrorAction Stop | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' } | Sort-Object Name)) {
        $snapshotPath = Join-Path $directory.FullName 'amazon-bestsellers.json'
        $receiptPath = Join-Path $directory.FullName 'best-sellers-capture-receipt.json'
        if (-not (Test-Path -LiteralPath $snapshotPath -PathType Leaf) -or -not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { continue }

        $validation = & (Join-Path $sourceRoot 'scripts\Test-BestSellersCaptureReceipt.ps1') -ReceiptPath $receiptPath | ConvertFrom-Json
        if (-not $validation.valid) { throw "Seller intelligence backfill requires a valid capture receipt for $($directory.Name)." }

        $runOutputRoot = Join-Path $tempRoot $directory.Name
        $run = & (Join-Path $sourceRoot 'scripts\New-SellerIntelligenceReports.ps1') -SnapshotPath $snapshotPath -SnapshotsRoot $SnapshotsRoot -ReportKind $ReportKind -OutputRoot $runOutputRoot | ConvertFrom-Json
        if ([string]$run.Status -ne 'CREATED' -or [int]$run.ReportCount -ne 4) { throw "Could not generate seller intelligence reports for $($directory.Name)." }

        $reports = @($run.ReportPaths | ForEach-Object { Get-Content -LiteralPath $_ -Raw -Encoding UTF8 | ConvertFrom-Json })
        if ($reports.Count -ne 4) { throw "Could not read four seller intelligence reports for $($directory.Name)." }
        $bundleJson = [pscustomobject]@{ reports = $reports } | ConvertTo-Json -Depth 16 -Compress
        $result = if ($null -ne $PostOperation) {
            & $PostOperation $endpoint 'Post' $headers 'application/json' $bundleJson
        }
        else {
            Invoke-RestMethod -Uri $endpoint -Method Post -Headers $headers -ContentType 'application/json' -Body $bundleJson
        }
        if ([string]$result.status -eq 'imported') {
            $uploaded += 4
        }
        elseif ([string]$result.status -eq 'duplicate') {
            $duplicates += 4
        }
        else {
            throw "Unexpected seller intelligence bundle sync result for $($directory.Name)."
        }

        $marketDates += $directory.Name
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

[pscustomobject]@{
    Status = 'COMPLETED'
    ReportKind = $ReportKind.ToLowerInvariant()
    MarketDates = $marketDates
    Uploaded = $uploaded
    Duplicates = $duplicates
} | ConvertTo-Json -Depth 5
