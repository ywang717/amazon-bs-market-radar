param(
    [string]$SettingsPath,
    [string]$ArtifactPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($SettingsPath)) { $SettingsPath = Join-Path $projectRoot '.local\postgres-settings.json' }
if ([string]::IsNullOrWhiteSpace($ArtifactPath)) { $ArtifactPath = Join-Path $projectRoot 'var\public-intelligence\2026-08-04\raw\cpsc-recalls.json' }
$settings = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$psql = Join-Path $settings.install_root 'bin\psql.exe'
Import-Module (Join-Path $projectRoot 'src\PublicIntelligencePostgres.psm1') -Force

Invoke-PublicIntelligencePostgresImport -ArtifactPath $ArtifactPath -PostgresSettings $settings
Invoke-PublicIntelligencePostgresImport -ArtifactPath $ArtifactPath -PostgresSettings $settings

$env:PGPASSWORD = [string]$settings.password
$common = @('-h',[string]$settings.host,'-p',[string]$settings.port,'-U',[string]$settings.username,'-d',[string]$settings.database,'-X','--no-psqlrc','-tAc')
try {
    $runCount = [int]((& $psql @common "SELECT count(*) FROM amazon_intelligence.public_intelligence_run;").Trim())
    $noticeCount = [int]((& $psql @common "SELECT count(*) FROM amazon_intelligence.public_safety_notice;").Trim())
    $observationCount = [int]((& $psql @common "SELECT count(*) FROM amazon_intelligence.public_safety_notice_observation;").Trim())
    $currentCount = [int]((& $psql @common "SELECT count(*) FROM amazon_intelligence.public_safety_current;").Trim())
    if ($runCount -lt 1) { throw 'Expected at least one public intelligence run.' }
    if ($noticeCount -lt 1) { throw 'Expected at least one public safety notice.' }
    if ($observationCount -ne $noticeCount) { throw "Expected one idempotent observation per notice for one market date; notices=$noticeCount observations=$observationCount" }
    if ($currentCount -ne $noticeCount) { throw "Current view count does not match notices: $currentCount vs $noticeCount" }
    [pscustomobject]@{
        PublicRuns = $runCount; PublicNotices = $noticeCount; HistoricalObservations = $observationCount
        CurrentViewRows = $currentCount; DuplicateImport = 'NO_DUPLICATES'; Status = 'PASSED'
    } | Format-List
}
finally { Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue }
