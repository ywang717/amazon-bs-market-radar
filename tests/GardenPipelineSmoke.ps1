$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'src/LocalPackageOrchestrator.psm1') -Force
Import-Module (Join-Path $root 'src/BestSellersDataSemantics.psm1') -Force
$module = Get-Module LocalPackageOrchestrator
& $module {
    $arguments = ConvertTo-LocalPackageArgumentList @{ CategoryKeys = @('patio_lawn_garden','garden_gardening') }
    if ($arguments[1] -ne 'patio_lawn_garden,garden_gardening') { throw 'Category array must survive child-process CLI serialization.' }
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('garden-pipeline-' + [guid]::NewGuid().ToString('N'))
try {
    [IO.Directory]::CreateDirectory($temp) | Out-Null
    $source = Join-Path $temp 'source.json'
    [IO.File]::WriteAllText($source, '{"market_date":"2026-10-13"}')
    $copy = & $module { param($project,$snapshot) Copy-LocalPackageImportedSnapshot -ProjectRoot $project -SnapshotPath $snapshot } $temp $source
    if ((Get-FileHash $source).Hash -ne (Get-FileHash $copy.SnapshotPath).Hash) { throw 'Staged snapshot content changed.' }
    $items = @(1..30 | ForEach-Object { [pscustomobject]@{ asin=('B{0:d9}' -f $_);rank=$_;title='Garden product';raw_brand='园艺品牌';brand_source='verified_metadata' } })
    $snapshot = [pscustomobject]@{market_date='2026-10-13';persisted_complete=$true;patio_lawn_garden=$items}
    $metadata = @(New-BestSellersProductMetadataRows -Snapshots @($snapshot) -MarketplaceCode AMAZON_US -ClassificationConfigPath (Join-Path $root 'config/v2-product-classification.json') -BrandAliasConfigPath (Join-Path $root 'config/v2-brand-aliases.json'))
    if ($metadata.Count -ne 30 -or @($metadata | Where-Object brand_source -ne unknown).Count -ne 0) { throw 'Unsupported brand aliases must remain unknown without blocking verified rankings.' }
    if ($snapshot.patio_lawn_garden[0].raw_brand -ne '园艺品牌') { throw 'Raw captured brand was modified.' }
    'PASS: category CLI arrays, hidden staging copies, and conservative brand metadata.'
} finally {
    if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
