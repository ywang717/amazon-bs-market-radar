param(
    [Parameter(Mandatory = $true)][string]$ArtifactPath,
    [string]$SourceConfigPath,
    [string]$PostgresSettingsPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($SourceConfigPath)) { $SourceConfigPath = Join-Path $projectRoot 'config\best-sellers-sources.json' }
if ([string]::IsNullOrWhiteSpace($PostgresSettingsPath)) { $PostgresSettingsPath = Join-Path $projectRoot '.local\postgres-settings.json' }
Import-Module (Join-Path $projectRoot 'src\BestSellersPostgres.psm1') -Force
$settings = Get-Content -LiteralPath $PostgresSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
Invoke-BestSellersPostgresImport -ArtifactPath $ArtifactPath -SourceConfigPath $SourceConfigPath -PostgresSettings $settings
[pscustomobject]@{ Status = 'IMPORTED'; ArtifactPath = (Resolve-Path -LiteralPath $ArtifactPath).Path } | ConvertTo-Json
