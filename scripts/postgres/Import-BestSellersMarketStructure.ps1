param([Parameter(Mandatory = $true)][string]$ArtifactPath, [string]$PostgresSettingsPath)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($PostgresSettingsPath)) { $PostgresSettingsPath = Join-Path $projectRoot '.local\postgres-settings.json' }
Import-Module (Join-Path $projectRoot 'src\BestSellersMarketStructurePostgres.psm1') -Force
$settings = Get-Content -LiteralPath $PostgresSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
Invoke-BestSellersMarketStructurePostgresImport -ArtifactPath $ArtifactPath -PostgresSettings $settings
[pscustomobject]@{ Status = 'IMPORTED'; ArtifactPath = (Resolve-Path -LiteralPath $ArtifactPath).Path } | ConvertTo-Json
