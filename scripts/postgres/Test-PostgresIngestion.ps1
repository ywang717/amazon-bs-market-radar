param([string]$SettingsPath)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($SettingsPath)) { $SettingsPath = Join-Path $projectRoot '.local\postgres-settings.json' }
$settings = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$psql = Join-Path $settings.install_root 'bin\psql.exe'

Import-Module (Join-Path $projectRoot 'src\AmazonIntelligence.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\PostgresOutbox.psm1') -Force

$runId = '66666666-6666-4666-8666-666666666666'
$sourceId = '71cc7af1-35b1-4d19-8306-ff971db318ee'
$integrationRoot = Join-Path $projectRoot '.local\postgres-integration'
$fixturePath = Join-Path $integrationRoot 'integration-fixture.json'
if (-not (Test-Path -LiteralPath $integrationRoot)) { New-Item -ItemType Directory -Path $integrationRoot -Force | Out-Null }

$fixture = Get-Content -LiteralPath (Join-Path $projectRoot 'tests\fixtures\valid-pressure-washer.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$fixture.run_id = $runId
$fixture.source_id = $sourceId
[System.IO.File]::WriteAllText(
    $fixturePath,
    ($fixture | ConvertTo-Json -Depth 10),
    (New-Object System.Text.UTF8Encoding($false))
)

$pipeline = Invoke-CollectionPipeline -FixturePath $fixturePath -WorkRoot (Join-Path $integrationRoot 'runtime')
if ($pipeline.Status -ne 'SUCCEEDED') { throw "Integration collection failed quality gate: $($pipeline.Status)" }

$savedEnvironment = @{}
foreach ($name in @('PGHOST','PGPORT','PGUSER','PGDATABASE','PGPASSWORD')) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
    $env:PGHOST = [string]$settings.host
    $env:PGPORT = [string]$settings.port
    $env:PGUSER = [string]$settings.username
    $env:PGDATABASE = [string]$settings.database
    $env:PGPASSWORD = [string]$settings.password

    Invoke-PostgresOutboxImport -OutboxPath $pipeline.OutboxPath -PsqlPath $psql
    Invoke-PostgresOutboxImport -OutboxPath $pipeline.OutboxPath -PsqlPath $psql

    $common = @('-h', [string]$settings.host, '-p', [string]$settings.port, '-U', [string]$settings.username, '-d', [string]$settings.database, '-X', '--no-psqlrc', '-tAc')
    $runCount = [int]((& $psql @common "SELECT count(*) FROM amazon_intelligence.collection_run WHERE run_id='$runId';").Trim())
    $rankingCount = [int]((& $psql @common "SELECT count(*) FROM amazon_intelligence.ranking_observation WHERE run_id='$runId';").Trim())
    $offerCount = [int]((& $psql @common "SELECT count(*) FROM amazon_intelligence.offer_snapshot WHERE run_id='$runId';").Trim())
    $listingCount = [int]((& $psql @common "SELECT count(*) FROM amazon_intelligence.listing_snapshot WHERE run_id='$runId';").Trim())
    $viewCount = [int]((& $psql @common "SELECT count(*) FROM amazon_intelligence.daily_ranking WHERE run_id='$runId';").Trim())

    if ($runCount -ne 1) { throw "Expected one collection_run, found $runCount" }
    foreach ($result in @($rankingCount, $offerCount, $listingCount, $viewCount)) {
        if ($result -ne 3) { throw "Expected three idempotent fact/view records, found $result" }
    }

    [pscustomobject]@{
        RunId = $runId
        CollectionRuns = $runCount
        RankingObservations = $rankingCount
        OfferSnapshots = $offerCount
        ListingSnapshots = $listingCount
        DailyRankingRows = $viewCount
        DuplicateImport = 'NO_DUPLICATES'
        Status = 'PASSED'
    } | Format-List
}
finally {
    foreach ($name in $savedEnvironment.Keys) {
        $previous = $savedEnvironment[$name]
        if ($null -eq $previous) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($name, [string]$previous, 'Process') }
    }
}

