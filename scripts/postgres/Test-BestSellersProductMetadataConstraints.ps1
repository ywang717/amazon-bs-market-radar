[CmdletBinding()]
param([switch]$RunAgainstDisposableDatabase)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$databaseUrl = [string]$env:AMAZON_INTELLIGENCE_DISPOSABLE_TEST_DATABASE_URL
if ([string]::IsNullOrWhiteSpace($databaseUrl)) {
    return [pscustomobject]@{
        Status = 'INCONCLUSIVE'
        Reason = 'Set AMAZON_INTELLIGENCE_DISPOSABLE_TEST_DATABASE_URL to a disposable database after applying migrations.'
    }
}
if (-not $RunAgainstDisposableDatabase) {
    throw 'Dynamic metadata constraint probes require -RunAgainstDisposableDatabase.'
}

$psql = Get-Command psql -ErrorAction SilentlyContinue
if ($null -eq $psql) { throw 'Dynamic metadata constraint probes require psql.' }
$probePath = Join-Path $projectRoot 'tests\postgres\012_best_sellers_product_metadata.sql'
& $psql.Source -X --no-psqlrc -v ON_ERROR_STOP=1 "--dbname=$databaseUrl" -f $probePath
if ($LASTEXITCODE -ne 0) { throw 'Best Sellers product metadata constraint probes failed.' }

[pscustomobject]@{
    Status = 'PASSED'
    ProbePath = (Resolve-Path -LiteralPath $probePath).Path
    Transaction = 'ROLLED_BACK'
}
