param(
    [string]$SnapshotsRoot,
    [string]$OutputPath
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($SnapshotsRoot)) { $SnapshotsRoot = Join-Path $projectRoot 'var\amazon-bestsellers' }
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $projectRoot 'var\dashboard-history-manifest.json' }
$entries = foreach ($directory in Get-ChildItem -LiteralPath $SnapshotsRoot -Directory | Sort-Object Name) {
    $snapshotPath = Join-Path $directory.FullName 'amazon-bestsellers.json'
    $receiptPath = Join-Path $directory.FullName 'best-sellers-capture-receipt.json'
    $entry = [ordered]@{ marketDate=$directory.Name; eligible=$false; qualityStatus='UNUSABLE'; bundlePath=$null }
    if ((Test-Path -LiteralPath $snapshotPath) -and (Test-Path -LiteralPath $receiptPath)) {
        try {
            $validationText = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'scripts\Test-BestSellersCaptureReceipt.ps1') -ReceiptPath $receiptPath
            $validation = $validationText | ConvertFrom-Json
            if ($validation.valid) {
                $bundlePath = Join-Path $directory.FullName 'dashboard-sync-bundle.json'
                & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'scripts\New-DashboardSyncBundle.ps1') -SnapshotPath $snapshotPath -OutputPath $bundlePath | Out-Null
                $entry.eligible=$true; $entry.qualityStatus='VERIFIED'; $entry.bundlePath=$bundlePath
            } else { $entry.qualityStatus='RECEIPT_INVALID' }
        } catch { $entry.qualityStatus='UNREADABLE' }
    }
    [pscustomobject]$entry
}
[IO.File]::WriteAllText($OutputPath, (@{schemaVersion='amazon-bs-dashboard-history-v1';generatedAt=(Get-Date).ToUniversalTime().ToString('o');entries=@($entries)} | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
[pscustomobject]@{ Status='CREATED'; EligibleCount=@($entries|Where-Object eligible).Count; ExcludedCount=@($entries|Where-Object{-not $_.eligible}).Count; ManifestPath=$OutputPath } | ConvertTo-Json
