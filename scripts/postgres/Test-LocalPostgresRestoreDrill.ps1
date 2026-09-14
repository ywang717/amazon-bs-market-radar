param(
    [Parameter(Mandatory = $true)][string]$BackupPath,
    [string]$SettingsPath,
    [string]$RestoreDatabase,
    [switch]$KeepRestoreDatabase
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($SettingsPath)) { $SettingsPath = Join-Path $projectRoot '.local\postgres-settings.json' }
if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) { throw "PostgreSQL settings not found: $SettingsPath" }
if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) { throw "Backup not found: $BackupPath" }
& (Join-Path $PSScriptRoot 'Start-LocalPostgres.ps1') -SettingsPath $SettingsPath | Out-Null

$settings = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$psql = Join-Path $settings.install_root 'bin\psql.exe'
$pgRestore = Join-Path $settings.install_root 'bin\pg_restore.exe'
foreach ($tool in @($psql, $pgRestore)) { if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "PostgreSQL tool not found: $tool" } }
if ([string]::IsNullOrWhiteSpace($RestoreDatabase)) { $RestoreDatabase = 'amazon_intelligence_restore_' + [DateTimeOffset]::UtcNow.ToString('yyyyMMddHHmmss') }
if ($RestoreDatabase -notmatch '^amazon_intelligence_restore_[a-z0-9_]+$') { throw 'RestoreDatabase must use the reserved amazon_intelligence_restore_ prefix and lowercase letters, digits, or underscores.' }
if ($RestoreDatabase -eq [string]$settings.database) { throw 'RestoreDatabase must never be the configured production database.' }

& (Join-Path $PSScriptRoot 'Test-LocalPostgresBackup.ps1') -BackupPath $BackupPath -SettingsPath $SettingsPath | Out-Null

$created = $false
$savedPassword = [Environment]::GetEnvironmentVariable('PGPASSWORD', 'Process')
try {
    $env:PGPASSWORD = [string]$settings.password
    & $psql '-v' 'ON_ERROR_STOP=1' '-h' ([string]$settings.host) '-p' ([string]$settings.port) '-U' ([string]$settings.username) '-d' 'postgres' '-c' ("CREATE DATABASE {0}" -f $RestoreDatabase) | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to create isolated restore database (exit code $LASTEXITCODE)." }
    $created = $true

    & $pgRestore '--exit-on-error' '-h' ([string]$settings.host) '-p' ([string]$settings.port) '-U' ([string]$settings.username) '-d' $RestoreDatabase $BackupPath
    if ($LASTEXITCODE -ne 0) { throw "pg_restore failed with exit code $LASTEXITCODE." }

    $validationSql = "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'amazon_intelligence' AND table_name IN ('marketplace', 'best_sellers_run');"
    $validationOutput = @(& $psql '-v' 'ON_ERROR_STOP=1' '-At' '-h' ([string]$settings.host) '-p' ([string]$settings.port) '-U' ([string]$settings.username) '-d' $RestoreDatabase '-c' $validationSql)
    if ($LASTEXITCODE -ne 0) { throw "Restored database validation failed with exit code $LASTEXITCODE." }
    $validatedTables = 0
    if (-not [int]::TryParse((($validationOutput -join '').Trim()), [ref]$validatedTables)) { throw 'Restored database validation returned an invalid table count.' }
    if ($validatedTables -ne 2) { throw 'Restored database is missing expected application tables.' }

    [pscustomobject]@{ Status='RESTORE_DRILL_PASSED'; BackupPath=(Resolve-Path -LiteralPath $BackupPath).Path; RestoreDatabase=$RestoreDatabase; ValidatedTables=$validatedTables; Retained=$KeepRestoreDatabase.IsPresent } | ConvertTo-Json -Depth 4
}
finally {
    if ($created -and -not $KeepRestoreDatabase.IsPresent) {
        & $psql '-v' 'ON_ERROR_STOP=1' '-h' ([string]$settings.host) '-p' ([string]$settings.port) '-U' ([string]$settings.username) '-d' 'postgres' '-c' ("DROP DATABASE IF EXISTS {0}" -f $RestoreDatabase) | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warning "Could not remove isolated restore database: $RestoreDatabase" }
    }
    if ($null -eq $savedPassword) { Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable('PGPASSWORD', $savedPassword, 'Process') }
}
