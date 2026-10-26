param(
    [Parameter(Mandatory = $true)][string]$SnapshotPath,
    [string]$ReceiptPath,
    [string]$SourceConfigPath,
    [string]$PostgresSettingsPath,
    [hashtable]$TestHooks
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $SnapshotPath -PathType Leaf)) { throw "Snapshot not found: $SnapshotPath" }
if ([string]::IsNullOrWhiteSpace($ReceiptPath)) { $ReceiptPath = Join-Path (Split-Path -Parent $SnapshotPath) 'best-sellers-capture-receipt.json' }
if ([string]::IsNullOrWhiteSpace($SourceConfigPath)) { $SourceConfigPath = Join-Path $projectRoot 'config\best-sellers-sources.json' }
if ([string]::IsNullOrWhiteSpace($PostgresSettingsPath)) { $PostgresSettingsPath = Join-Path $projectRoot '.local\postgres-settings.json' }

Import-Module (Join-Path $projectRoot 'src\BestSellersCaptureReceipt.psm1') -Force
$authorizedSnapshot = Resolve-BestSellersAuthorizedSnapshot -SnapshotPath $SnapshotPath -ReceiptPath $ReceiptPath

Import-Module (Join-Path $projectRoot 'src\BestSellersDataSemantics.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\BestSellersPostgres.psm1') -Force
$snapshot = Get-Content -LiteralPath $authorizedSnapshot.snapshot_path -Raw -Encoding UTF8 | ConvertFrom-Json
$snapshot | Add-Member -NotePropertyName persisted_complete -NotePropertyValue $true -Force
$partition=$null
$quarantinePath=$null
$metadataRows = if ($null -ne $TestHooks -and $TestHooks.ContainsKey('BuildMetadata')) {
    @(& $TestHooks.BuildMetadata -Snapshot $snapshot -ClassificationConfigPath (Join-Path $projectRoot 'config\v2-product-classification.json') -BrandAliasConfigPath (Join-Path $projectRoot 'config\v2-brand-aliases.json'))
}
else {
    @(New-BestSellersProductMetadataRows -Snapshots @($snapshot) -MarketplaceCode AMAZON_US -ClassificationConfigPath (Join-Path $projectRoot 'config\v2-product-classification.json') -BrandAliasConfigPath (Join-Path $projectRoot 'config\v2-brand-aliases.json'))
}

if ($null -ne $TestHooks -and $TestHooks.ContainsKey('StartPostgres')) {
    & $TestHooks.StartPostgres -SettingsPath $PostgresSettingsPath
}
else {
    & (Join-Path $projectRoot 'scripts\postgres\Start-LocalPostgres.ps1') -SettingsPath $PostgresSettingsPath | Out-Null
}
$settings = if ($null -ne $TestHooks -and $TestHooks.ContainsKey('ImportPostgres')) { [pscustomobject]@{} } else { Get-Content -LiteralPath $PostgresSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json }
if ($null -ne $TestHooks -and $TestHooks.ContainsKey('ImportPostgres')) {
    & $TestHooks.ImportPostgres -ArtifactPath $authorizedSnapshot.snapshot_path -SourceConfigPath $SourceConfigPath -PostgresSettings $settings -MetadataRows $metadataRows
}
else {
    $sourceSha=(Get-FileHash -LiteralPath $authorizedSnapshot.snapshot_path -Algorithm SHA256).Hash.ToLowerInvariant()
    $quarantinePath=Join-Path (Split-Path -Parent $authorizedSnapshot.snapshot_path) 'metadata-quarantine.json'
    $readStored={Get-BestSellersStoredBrands -PostgresSettings $settings}.GetNewClosure()
    $importRows={param([object[]]$Rows) Invoke-BestSellersPostgresImport -ArtifactPath $authorizedSnapshot.snapshot_path -SourceConfigPath $SourceConfigPath -PostgresSettings $settings -MetadataRows $Rows}.GetNewClosure()
    $writeReceipt={param($Receipt)
        $temp=$quarantinePath+'.tmp'
        [IO.File]::WriteAllText($temp,($Receipt|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
        [IO.File]::Move($temp,$quarantinePath,$true)
    }.GetNewClosure()
    $partition=Invoke-BestSellersQuarantineImport -MetadataRows $metadataRows -MarketDate ([string]$snapshot.market_date) -SourceSha $sourceSha -ReadStored $readStored -ImportRows $importRows -WriteReceipt $writeReceipt
}

[pscustomobject]@{
    Status = 'IMPORTED_VERIFIED_SNAPSHOT'
    SnapshotPath = $authorizedSnapshot.snapshot_path
    ReceiptPath = $authorizedSnapshot.receipt_path
    DatabaseImportStatus = 'IMPORTED'
    MetadataCount = if($null -ne $partition){@($partition.Accepted).Count}else{$metadataRows.Count}
    MetadataQuarantined = if($null -ne $partition){@($partition.Conflicts).Count}else{0}
    MetadataQuarantinePath = $quarantinePath
    MetadataStatus = if($null -ne $partition -and @($partition.Conflicts).Count -gt 0){"QUARANTINED"}else{"COMPLETE"}
} | ConvertTo-Json -Depth 4
