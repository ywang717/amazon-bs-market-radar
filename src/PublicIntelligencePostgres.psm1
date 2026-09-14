Set-StrictMode -Version Latest

function ConvertTo-PublicPostgresLiteral {
    param($Value)
    if ($null -eq $Value) { return 'NULL' }
    return "'" + ([string]$Value).Replace("'", "''") + "'"
}

function New-PublicIntelligenceImportSql {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ArtifactPath)
    if (-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf)) { throw "Public intelligence artifact not found: $ArtifactPath" }
    $artifact = Get-Content -LiteralPath $ArtifactPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$artifact.schema_version -ne 'cpsc-public-recall-intelligence-v1') { throw 'Unsupported public intelligence artifact schema.' }
    $artifact | Add-Member -NotePropertyName artifact_path -NotePropertyValue ((Resolve-Path -LiteralPath $ArtifactPath).Path) -Force
    $json = $artifact | ConvertTo-Json -Compress -Depth 15
    return @(
        'BEGIN;',
        'SET search_path TO amazon_intelligence, public;',
        ("SELECT ingest_public_intelligence({0}::jsonb);" -f (ConvertTo-PublicPostgresLiteral $json)),
        'COMMIT;'
    ) -join [Environment]::NewLine
}

function Invoke-PublicIntelligencePostgresImport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactPath,
        [Parameter(Mandatory = $true)]$PostgresSettings
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
        $sql = New-PublicIntelligenceImportSql -ArtifactPath $ArtifactPath
        $sql | & $psql -X --no-psqlrc -v ON_ERROR_STOP=1
        if ($LASTEXITCODE -ne 0) { throw "Public intelligence PostgreSQL import failed with exit code $LASTEXITCODE" }
    }
    finally {
        foreach ($name in $saved.Keys) {
            if ($null -eq $saved[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable($name, [string]$saved[$name], 'Process') }
        }
    }
}

Export-ModuleMember -Function New-PublicIntelligenceImportSql, Invoke-PublicIntelligencePostgresImport
