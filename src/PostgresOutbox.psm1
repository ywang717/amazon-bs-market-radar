Set-StrictMode -Version Latest

function ConvertTo-PostgresLiteral {
    param($Value)
    if ($null -eq $Value) { return 'NULL' }
    return "'" + ([string]$Value).Replace("'", "''") + "'"
}

function New-PostgresOutboxSql {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$OutboxPath)

    if (-not (Test-Path -LiteralPath $OutboxPath -PathType Leaf)) { throw "Outbox not found: $OutboxPath" }
    $batch = Get-Content -LiteralPath $OutboxPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$batch.schema_version -ne 'database-batch-v1') { throw 'Unsupported database batch schema.' }
    if (@($batch.records).Count -eq 0) { throw 'Database batch contains no records.' }

    $first = @($batch.records)[0]
    $runId = ConvertTo-PostgresLiteral $batch.run_id
    $sourceId = ConvertTo-PostgresLiteral $batch.source_id
    $startedAt = ConvertTo-PostgresLiteral $first.observed_at
    $parserVersion = ConvertTo-PostgresLiteral $batch.parser_version
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('BEGIN;')
    $lines.Add('SET search_path TO amazon_intelligence, public;')
    $lines.Add(("SELECT start_collection_run({0}::uuid, {1}::uuid, {2}::timestamptz, {3}, {4});" -f `
        $runId, $sourceId, $startedAt, $parserVersion, [int]$batch.stats.TargetCount))

    foreach ($artifact in @($batch.raw_artifacts)) {
        $mediaTypeProperty = $artifact.PSObject.Properties['MediaType']
        $mediaType = if ($null -eq $mediaTypeProperty -or [string]::IsNullOrWhiteSpace([string]$mediaTypeProperty.Value)) {
            'application/json'
        } else { [string]$mediaTypeProperty.Value }
        $lines.Add(("INSERT INTO raw_artifact (run_id, content_hash, storage_uri, captured_at, media_type) VALUES ({0}::uuid, {1}, {2}, {3}::timestamptz, {4}) ON CONFLICT (run_id, content_hash) DO NOTHING;" -f `
            $runId,
            (ConvertTo-PostgresLiteral $artifact.ContentHash),
            (ConvertTo-PostgresLiteral $artifact.Path),
            $startedAt,
            (ConvertTo-PostgresLiteral $mediaType)))
    }

    foreach ($record in @($batch.records)) {
        $recordJson = $record | ConvertTo-Json -Compress -Depth 12
        $lines.Add(("SELECT ingest_canonical_observation({0}::jsonb);" -f (ConvertTo-PostgresLiteral $recordJson)))
    }

    $lines.Add(("SELECT finish_collection_run({0}::uuid, {1}::timestamptz, 'SUCCEEDED'::run_status, {2}, {3}, {4}, NULL);" -f `
        $runId,
        $startedAt,
        [int]$batch.stats.RawCount,
        [int]$batch.stats.AcceptedCount,
        [int]$batch.stats.RejectedCount))
    $lines.Add('COMMIT;')
    return ($lines -join [Environment]::NewLine)
}

function Invoke-PostgresOutboxImport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$OutboxPath,
        [string]$PsqlPath = 'psql'
    )

    $command = Get-Command $PsqlPath -ErrorAction SilentlyContinue
    if ($null -eq $command) { throw "psql executable not found: $PsqlPath" }
    $sql = New-PostgresOutboxSql -OutboxPath $OutboxPath
    $sql | & $command.Source -X --no-psqlrc -v ON_ERROR_STOP=1
    if ($LASTEXITCODE -ne 0) { throw "PostgreSQL outbox import failed with exit code $LASTEXITCODE" }
}

Export-ModuleMember -Function New-PostgresOutboxSql, Invoke-PostgresOutboxImport
