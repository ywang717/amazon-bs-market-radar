Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'BestSellersDataSemantics.psm1')

function ConvertTo-BestSellersPostgresLiteral {
    param($Value)
    if ($null -eq $Value) { return 'NULL' }
    return "'" + ([string]$Value).Replace("'", "''") + "'"
}

function New-BestSellersImportSql {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactPath,
        [Parameter(Mandatory = $true)][string]$SourceConfigPath,
        [object[]]$MetadataRows = @()
    )
    Assert-BestSellersMetadataImportRows -MetadataRows $MetadataRows
    if (-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf)) { throw "Best Sellers artifact not found: $ArtifactPath" }
    if (-not (Test-Path -LiteralPath $SourceConfigPath -PathType Leaf)) { throw "Best Sellers source config not found: $SourceConfigPath" }
    $artifact = Get-Content -LiteralPath $ArtifactPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $sourceConfig = Get-Content -LiteralPath $SourceConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$artifact.market_date -notmatch '^\d{4}-\d{2}-\d{2}$') { throw 'Best Sellers artifact has an invalid market_date.' }
    if ([string]::IsNullOrWhiteSpace([string]$artifact.observed_at)) { throw 'Best Sellers artifact is missing observed_at.' }
    $activeSources = @($sourceConfig.sources | Where-Object { $_.active })
    if ($activeSources.Count -eq 0) { throw 'Best Sellers source config has no active sources.' }
    $sha = (Get-FileHash -LiteralPath $ArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $artifact | Add-Member -NotePropertyName schema_version -NotePropertyValue 'amazon-best-sellers-snapshot-v1' -Force
    $artifact | Add-Member -NotePropertyName artifact_path -NotePropertyValue ((Resolve-Path -LiteralPath $ArtifactPath).Path) -Force
    $artifact | Add-Member -NotePropertyName artifact_sha256 -NotePropertyValue $sha -Force
    $artifact | Add-Member -NotePropertyName target_count -NotePropertyValue ([int]$sourceConfig.target_count) -Force
    $artifact | Add-Member -NotePropertyName source_definitions -NotePropertyValue $activeSources -Force
    $json = $artifact | ConvertTo-Json -Compress -Depth 20
    $statements = @(
        'BEGIN;',
        'SET search_path TO amazon_intelligence, public;',
        ("SELECT ingest_best_sellers_snapshot({0}::jsonb);" -f (ConvertTo-BestSellersPostgresLiteral $json))
    )
    if ($MetadataRows.Count -gt 0) {
        $metadataJson = ConvertTo-Json -InputObject @($MetadataRows) -Compress -Depth 20
        $statements += "SELECT upsert_best_sellers_product_metadata({0}::jsonb);" -f (ConvertTo-BestSellersPostgresLiteral $metadataJson)
    }
    return @($statements + 'COMMIT;') -join [Environment]::NewLine
}

function Invoke-BestSellersPostgresImport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactPath,
        [Parameter(Mandatory = $true)][string]$SourceConfigPath,
        [Parameter(Mandatory = $true)]$PostgresSettings,
        [object[]]$MetadataRows = @()
    )
    $psql = Join-Path $PostgresSettings.install_root 'bin\psql.exe'
    if (-not (Test-Path -LiteralPath $psql)) { throw "psql not found: $psql" }
    $saved = @{}
    foreach ($name in @('PGHOST','PGPORT','PGUSER','PGDATABASE','PGPASSWORD')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
    try {
        $env:PGHOST = [string]$PostgresSettings.host
        $env:PGPORT = [string]$PostgresSettings.port
        $env:PGUSER = [string]$PostgresSettings.username
        $env:PGDATABASE = [string]$PostgresSettings.database
        $env:PGPASSWORD = [string]$PostgresSettings.password
        $sql = New-BestSellersImportSql -ArtifactPath $ArtifactPath -SourceConfigPath $SourceConfigPath -MetadataRows $MetadataRows
        $sql | & $psql -X --no-psqlrc -v ON_ERROR_STOP=1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Best Sellers PostgreSQL import failed with exit code $LASTEXITCODE" }
    }
    finally {
        foreach ($name in $saved.Keys) {
            if ($null -eq $saved[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable($name, [string]$saved[$name], 'Process') }
        }
    }
}

function Assert-BestSellersMetadataImportRows {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$MetadataRows)

    $identities = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($row in @($MetadataRows)) {
        $marketplace = [string]$row.marketplace_code
        $asin = ([string]$row.asin).ToUpperInvariant()
        if ($marketplace -ne 'AMAZON_US' -or $asin -notmatch '^[A-Z0-9]{10}$') { throw 'Metadata import rows require AMAZON_US and a valid ASIN.' }
        $identity = "$marketplace|$asin"
        if (-not $identities.Add($identity)) { throw "Duplicate metadata import row for marketplace $marketplace and ASIN $asin." }
        $source = [string]$row.brand_source
        $key = [string]$row.normalized_brand_key
        if ($source -in @('verified_metadata', 'manual_review') -and [string]::IsNullOrWhiteSpace($key)) { throw "Metadata import row $asin has an invalid trusted brand." }
        if ($source -notin @('verified_metadata', 'manual_review', 'unknown')) { throw "Metadata import row $asin has an invalid brand source." }
        if ($source -in @('verified_metadata', 'manual_review')) {
            foreach ($field in @('raw_brand', 'normalized_brand', 'normalized_brand_key')) {
                $value = [string]$row.$field
                try { $portableValue = ConvertTo-BestSellersPortableBrandText -Value $value }
                catch { throw "Metadata import row $asin has non-portable $field." }
                if ($portableValue -cne $value) { throw "Metadata import row $asin has non-normalized $field spacing." }
            }
            if ([string]$row.normalized_brand_key -cne ([string]$row.normalized_brand).ToLowerInvariant()) {
                throw "Metadata import row $asin has an incoherent normalized brand key."
            }
        }
    }
}

function New-BestSellersMetadataImportSql {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$MetadataRows)

    Assert-BestSellersMetadataImportRows -MetadataRows $MetadataRows
    if (@($MetadataRows).Count -eq 0) { return $null }
    $metadataJson = ConvertTo-Json -InputObject @($MetadataRows) -Compress -Depth 20
    return @(
        'BEGIN;'
        'SET search_path TO amazon_intelligence, public;'
        ("SELECT upsert_best_sellers_product_metadata({0}::jsonb);" -f (ConvertTo-BestSellersPostgresLiteral $metadataJson))
        'COMMIT;'
    ) -join [Environment]::NewLine
}

function Invoke-BestSellersMetadataPostgresImport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$MetadataRows,
        [Parameter(Mandatory = $true)]$PostgresSettings
    )

    if (@($MetadataRows).Count -eq 0) { return [pscustomobject]@{ imported = $false; metadata_count = 0 } }
    $sql = New-BestSellersMetadataImportSql -MetadataRows $MetadataRows
    $psql = Join-Path $PostgresSettings.install_root 'bin\psql.exe'
    if (-not (Test-Path -LiteralPath $psql)) { throw "psql not found: $psql" }
    $saved = @{}
    foreach ($name in @('PGHOST','PGPORT','PGUSER','PGDATABASE','PGPASSWORD')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
    try {
        $env:PGHOST = [string]$PostgresSettings.host
        $env:PGPORT = [string]$PostgresSettings.port
        $env:PGUSER = [string]$PostgresSettings.username
        $env:PGDATABASE = [string]$PostgresSettings.database
        $env:PGPASSWORD = [string]$PostgresSettings.password
        $sql | & $psql -X --no-psqlrc -v ON_ERROR_STOP=1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Best Sellers metadata PostgreSQL import failed with exit code $LASTEXITCODE" }
        return [pscustomobject]@{ imported = $true; metadata_count = @($MetadataRows).Count }
    }
    finally {
        foreach ($name in $saved.Keys) {
            if ($null -eq $saved[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable($name, [string]$saved[$name], 'Process') }
        }
    }
}

Export-ModuleMember -Function New-BestSellersImportSql, Invoke-BestSellersPostgresImport, New-BestSellersMetadataImportSql, Invoke-BestSellersMetadataPostgresImport

function Split-BestSellersMetadataConflicts {
 param([object[]]$MetadataRows,[object[]]$StoredBrands,[string]$MarketDate,[string]$SourceSha)
 $stored=@{};foreach($r in $StoredBrands){$stored[[string]$r.asin]=$r}
 $accepted=New-Object 'System.Collections.Generic.List[object]';$conflicts=New-Object 'System.Collections.Generic.List[object]'
 foreach($row in $MetadataRows){
  $old=$stored[[string]$row.asin]
  if($null -ne $old -and $row.brand_source -in @('verified_metadata','manual_review') -and $old.brand_source -in @('verified_metadata','manual_review') -and ([string]::IsNullOrWhiteSpace([string]$old.normalized_brand_key) -or [string]$old.normalized_brand_key -cne [string]$row.normalized_brand_key)) {
   $conflicts.Add([pscustomobject]@{asin=$row.asin;market_date=$MarketDate;source_sha256=$SourceSha;old_brand=$old.raw_brand;new_brand=$row.raw_brand;old_key=$old.normalized_brand_key;new_key=$row.normalized_brand_key;reason='trusted_brand_conflict'})
  }else{$accepted.Add($row)}
 }
 [pscustomobject]@{Accepted=@($accepted.ToArray());Conflicts=@($conflicts.ToArray())}
}
function Get-BestSellersStoredBrands {
 param([Parameter(Mandatory=$true)]$PostgresSettings)
 $psql=Join-Path $PostgresSettings.install_root 'bin/psql.exe'
 $saved=[Environment]::GetEnvironmentVariable('PGPASSWORD','Process')
 try{
  $env:PGPASSWORD=[string]$PostgresSettings.password
  $json=@(& $psql -X --no-psqlrc -qAt -v ON_ERROR_STOP=1 -h $PostgresSettings.host -p $PostgresSettings.port -U $PostgresSettings.username -d $PostgresSettings.database -c "SELECT COALESCE(json_agg(t),'[]'::json) FROM (SELECT asin,raw_brand,normalized_brand_key,brand_source FROM amazon_intelligence.best_sellers_product_metadata WHERE marketplace_code='AMAZON_US') t;")
  if($LASTEXITCODE -ne 0){throw 'Stored brand read failed.'}
  @((($json -join '')|ConvertFrom-Json))
 }finally{if($null -eq $saved){Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue}else{$env:PGPASSWORD=$saved}}
}
Export-ModuleMember -Function Split-BestSellersMetadataConflicts,Get-BestSellersStoredBrands
function New-BestSellersQuarantineReceipt {
 param($Partition,[ValidateSet('PENDING','IMPORTED','FAILED')][string]$Status,[string]$MarketDate,[string]$SourceSha)
 [pscustomobject]@{status=$Status;market_date=$MarketDate;source_sha256=$SourceSha;metadata_imported=if($Status -eq 'IMPORTED'){@($Partition.Accepted).Count}else{0};metadata_quarantined=@($Partition.Conflicts).Count;conflicts=@($Partition.Conflicts)}
}
Export-ModuleMember -Function New-BestSellersQuarantineReceipt
function Invoke-BestSellersQuarantineImport {
 param([object[]]$MetadataRows,[string]$MarketDate,[string]$SourceSha,[scriptblock]$ReadStored,[scriptblock]$ImportRows,[scriptblock]$WriteReceipt)
 $previous=$null;$failure=$null
 for($attempt=0;$attempt -lt 2;$attempt++){
  $partition=Split-BestSellersMetadataConflicts -MetadataRows $MetadataRows -StoredBrands @(& $ReadStored) -MarketDate $MarketDate -SourceSha $SourceSha
  if($attempt -gt 0 -and (@($partition.Conflicts|ForEach-Object asin|Sort-Object) -join ',') -eq (@($previous.Conflicts|ForEach-Object asin|Sort-Object) -join ',')){throw $failure}
  & $WriteReceipt -Receipt (New-BestSellersQuarantineReceipt -Partition $partition -Status PENDING -MarketDate $MarketDate -SourceSha $SourceSha)
  try{
   & $ImportRows -Rows @($partition.Accepted)
   & $WriteReceipt -Receipt (New-BestSellersQuarantineReceipt -Partition $partition -Status IMPORTED -MarketDate $MarketDate -SourceSha $SourceSha)
   return $partition
  }catch{
   & $WriteReceipt -Receipt (New-BestSellersQuarantineReceipt -Partition $partition -Status FAILED -MarketDate $MarketDate -SourceSha $SourceSha)
   if($attempt -eq 1){throw};$failure=$_;$previous=$partition
  }
 }
}
Export-ModuleMember -Function Invoke-BestSellersQuarantineImport
