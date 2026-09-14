param(
    [Parameter(Mandatory = $true)][string]$BackupPath,
    [string]$ManifestPath,
    [string]$SettingsPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($SettingsPath)) { $SettingsPath = Join-Path $projectRoot '.local\postgres-settings.json' }
if ([string]::IsNullOrWhiteSpace($ManifestPath)) { $ManifestPath = $BackupPath + '.json' }
if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) { throw "Backup not found: $BackupPath" }
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Backup manifest not found: $ManifestPath" }
if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) { throw "PostgreSQL settings not found: $SettingsPath" }
$settings = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$pgRestore = Join-Path $settings.install_root 'bin\pg_restore.exe'
if (-not (Test-Path -LiteralPath $pgRestore -PathType Leaf)) { throw "pg_restore not found: $pgRestore" }
$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$manifest.schema_version -ne 'local-postgres-backup-v1') { throw 'Unsupported backup manifest schema version.' }
$actualHash = (Get-FileHash -LiteralPath $BackupPath -Algorithm SHA256).Hash.ToLowerInvariant()
$listing = & $pgRestore '--list' $BackupPath
if ($LASTEXITCODE -ne 0) { throw "pg_restore list validation failed with exit code $LASTEXITCODE" }
$entryCount = @($listing | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count
if ($entryCount -eq 0) { throw 'Backup archive contains no restore entries.' }
$hashMatches = [string]$manifest.sha256 -eq $actualHash
[pscustomobject]@{ Status=if ($hashMatches) { 'VERIFIED' } else { 'HASH_MISMATCH' }; BackupPath=(Resolve-Path -LiteralPath $BackupPath).Path; HashMatches=$hashMatches; RestoreEntryCount=$entryCount; ByteCount=[long](Get-Item -LiteralPath $BackupPath).Length } | ConvertTo-Json -Depth 4
if (-not $hashMatches) { exit 2 }
