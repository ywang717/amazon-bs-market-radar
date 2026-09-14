Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'DailyCollection.psm1')
Import-Module (Join-Path $PSScriptRoot 'PostgresOutbox.psm1')

function Protect-DatabaseErrorMessage {
    param([string]$Message, $PostgresSettings)
    $safe = [regex]::Replace([string]$Message, '(?i)Bearer\s+[A-Za-z0-9._|+\-/=]+', 'Bearer [REDACTED]')
    if ($null -ne $PostgresSettings) {
        $passwordProperty = $PostgresSettings.PSObject.Properties['password']
        if ($null -ne $passwordProperty -and -not [string]::IsNullOrWhiteSpace([string]$passwordProperty.Value)) {
            $safe = $safe.Replace([string]$passwordProperty.Value, '[REDACTED]')
        }
    }
    return $safe
}

function Write-DatabaseSummaryAtomic {
    param($Value, [string]$Path)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    [System.IO.File]::WriteAllText(
        $temporary,
        ($Value | ConvertTo-Json -Depth 12),
        (New-Object System.Text.UTF8Encoding($false))
    )
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Invoke-DefaultOutboxImport {
    param([string]$OutboxPath, [string]$RunId, $PostgresSettings)
    $psql = Join-Path $PostgresSettings.install_root 'bin\psql.exe'
    Invoke-PostgresOutboxImport -OutboxPath $OutboxPath -PsqlPath $psql
    $common = @(
        '-h', [string]$PostgresSettings.host,
        '-p', [string]$PostgresSettings.port,
        '-U', [string]$PostgresSettings.username,
        '-d', [string]$PostgresSettings.database,
        '-X', '--no-psqlrc', '-tAc'
    )
    $count = [int]((& $psql @common "SELECT count(*) FROM amazon_intelligence.collection_run WHERE run_id='$RunId'::uuid AND status='SUCCEEDED';").Trim())
    if ($count -ne 1) { throw "Database verification failed for run_id $RunId" }
}

function Invoke-DailyCollectionDatabasePipeline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$MarketDate,
        [Parameter(Mandatory = $true)][string]$WorkRoot,
        [Parameter(Mandatory = $true)]$PostgresSettings,
        $Credentials,
        [scriptblock]$DailyCollector,
        [scriptblock]$OutboxImporter
    )

    if (-not (Test-Path -LiteralPath $WorkRoot)) { New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null }
    $WorkRoot = (Resolve-Path -LiteralPath $WorkRoot).Path

    if ($null -eq $DailyCollector) {
        $collection = Invoke-DailySearchCollection -Config $Config -MarketDate $MarketDate -WorkRoot $WorkRoot -Credentials $Credentials
    }
    else { $collection = & $DailyCollector $Config $MarketDate $WorkRoot $Credentials }

    $savedEnvironment = @{}
    foreach ($name in @('PGHOST','PGPORT','PGUSER','PGDATABASE','PGPASSWORD')) {
        $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    $databaseResults = New-Object System.Collections.Generic.List[object]
    try {
        $env:PGHOST = [string]$PostgresSettings.host
        $env:PGPORT = [string]$PostgresSettings.port
        $env:PGUSER = [string]$PostgresSettings.username
        $env:PGDATABASE = [string]$PostgresSettings.database
        $env:PGPASSWORD = [string]$PostgresSettings.password

        foreach ($sourceResult in @($collection.Results)) {
            if ([string]$sourceResult.status -ne 'SUCCEEDED') {
                $databaseResults.Add([pscustomobject]@{
                    source_id = [string]$sourceResult.source_id
                    category_slug = [string]$sourceResult.category_slug
                    run_id = $sourceResult.run_id
                    collection_status = [string]$sourceResult.status
                    database_status = 'SKIPPED_COLLECTION_FAILED'
                    outbox_path = $sourceResult.outbox_path
                    error_code = $sourceResult.error_code
                    error_message = $sourceResult.error_message
                })
                continue
            }

            try {
                if ([string]::IsNullOrWhiteSpace([string]$sourceResult.outbox_path) -or -not (Test-Path -LiteralPath $sourceResult.outbox_path)) {
                    throw 'Successful collection did not produce a readable outbox.'
                }
                if ($null -eq $OutboxImporter) {
                    Invoke-DefaultOutboxImport -OutboxPath $sourceResult.outbox_path -RunId $sourceResult.run_id -PostgresSettings $PostgresSettings
                }
                else { & $OutboxImporter $sourceResult.outbox_path $sourceResult.run_id $PostgresSettings }
                $databaseResults.Add([pscustomobject]@{
                    source_id = [string]$sourceResult.source_id
                    category_slug = [string]$sourceResult.category_slug
                    run_id = [string]$sourceResult.run_id
                    collection_status = 'SUCCEEDED'
                    database_status = 'IMPORTED'
                    outbox_path = [string]$sourceResult.outbox_path
                    error_code = $null
                    error_message = $null
                })
            }
            catch {
                $databaseResults.Add([pscustomobject]@{
                    source_id = [string]$sourceResult.source_id
                    category_slug = [string]$sourceResult.category_slug
                    run_id = [string]$sourceResult.run_id
                    collection_status = 'SUCCEEDED'
                    database_status = 'IMPORT_FAILED_RETRYABLE'
                    outbox_path = [string]$sourceResult.outbox_path
                    error_code = 'DATABASE_IMPORT_FAILED'
                    error_message = Protect-DatabaseErrorMessage -Message $_.Exception.Message -PostgresSettings $PostgresSettings
                })
            }
        }
    }
    finally {
        foreach ($name in $savedEnvironment.Keys) {
            $previous = $savedEnvironment[$name]
            if ($null -eq $previous) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable($name, [string]$previous, 'Process') }
        }
    }

    $resultArray = @($databaseResults | ForEach-Object { $_ })
    $importedCount = @($resultArray | Where-Object { $_.database_status -eq 'IMPORTED' }).Count
    $failedCount = @($resultArray | Where-Object { $_.database_status -eq 'IMPORT_FAILED_RETRYABLE' }).Count
    $skippedCount = @($resultArray | Where-Object { $_.database_status -eq 'SKIPPED_COLLECTION_FAILED' }).Count
    $overallStatus = if ($importedCount -eq $resultArray.Count) { 'SUCCEEDED' } elseif ($importedCount -gt 0) { 'PARTIAL' } else { 'FAILED' }
    $summary = [ordered]@{
        schema_version = 'daily-database-pipeline-summary-v1'
        market_date = $MarketDate
        status = $overallStatus
        collection_summary_path = [string]$collection.ManifestPath
        source_count = $resultArray.Count
        imported_count = $importedCount
        import_failed_count = $failedCount
        collection_failed_count = $skippedCount
        results = $resultArray
    }
    $summaryPath = Join-Path (Join-Path (Join-Path $WorkRoot 'daily') $MarketDate) 'daily-database-summary.json'
    Write-DatabaseSummaryAtomic -Value $summary -Path $summaryPath

    return [pscustomobject]@{
        MarketDate = $MarketDate
        Status = $overallStatus
        SourceCount = $resultArray.Count
        ImportedCount = $importedCount
        ImportFailedCount = $failedCount
        CollectionFailedCount = $skippedCount
        Results = $resultArray
        ManifestPath = (Resolve-Path -LiteralPath $summaryPath).Path
    }
}

Export-ModuleMember -Function Invoke-DailyCollectionDatabasePipeline

