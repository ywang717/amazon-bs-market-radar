Set-StrictMode -Version Latest

function ConvertTo-RankInfluencePostgresLiteral {
    param($Value)
    if ($null -eq $Value) { return 'NULL' }
    return "'" + ([string]$Value).Replace("'", "''") + "'"
}

function New-BestSellersRankInfluenceImportSql {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ArtifactPath)
    if (-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf)) { throw "Rank influence artifact not found: $ArtifactPath" }
    $artifact = Get-Content -LiteralPath $ArtifactPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$artifact.schema_version -ne 'best-sellers-rank-influence-v1') { throw 'Unsupported rank influence schema version.' }
    $artifact | Add-Member -NotePropertyName source_artifact_path -NotePropertyValue ((Resolve-Path -LiteralPath $ArtifactPath).Path) -Force
    $artifact | Add-Member -NotePropertyName source_artifact_sha256 -NotePropertyValue ((Get-FileHash -LiteralPath $ArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant()) -Force
    $json = $artifact | ConvertTo-Json -Compress -Depth 25
    return @('BEGIN;', 'SET search_path TO amazon_intelligence, public;',
        ("SELECT ingest_best_sellers_rank_influence({0}::jsonb);" -f (ConvertTo-RankInfluencePostgresLiteral $json)), 'COMMIT;') -join [Environment]::NewLine
}

function Invoke-BestSellersRankInfluencePostgresImport {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ArtifactPath, [Parameter(Mandatory = $true)]$PostgresSettings)
    $psql = Join-Path $PostgresSettings.install_root 'bin\psql.exe'
    if (-not (Test-Path -LiteralPath $psql)) { throw "psql not found: $psql" }
    $saved = @{}
    foreach ($name in @('PGHOST','PGPORT','PGUSER','PGDATABASE','PGPASSWORD')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
    try {
        $env:PGHOST=[string]$PostgresSettings.host; $env:PGPORT=[string]$PostgresSettings.port
        $env:PGUSER=[string]$PostgresSettings.username; $env:PGDATABASE=[string]$PostgresSettings.database; $env:PGPASSWORD=[string]$PostgresSettings.password
        (New-BestSellersRankInfluenceImportSql -ArtifactPath $ArtifactPath) | & $psql -X --no-psqlrc -v ON_ERROR_STOP=1
        if ($LASTEXITCODE -ne 0) { throw "Rank influence PostgreSQL import failed with exit code $LASTEXITCODE" }
    }
    finally {
        foreach ($name in $saved.Keys) {
            if ($null -eq $saved[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable($name, [string]$saved[$name], 'Process') }
        }
    }
}

Export-ModuleMember -Function New-BestSellersRankInfluenceImportSql, Invoke-BestSellersRankInfluencePostgresImport
