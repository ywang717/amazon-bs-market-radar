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
