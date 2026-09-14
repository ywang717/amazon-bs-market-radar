param(
    [string]$SettingsPath,
    [string]$BackupRoot
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($SettingsPath)) { $SettingsPath = Join-Path $projectRoot '.local\postgres-settings.json' }
if ([string]::IsNullOrWhiteSpace($BackupRoot)) { $BackupRoot = Join-Path $projectRoot '.local\postgres-backups' }
if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) { throw "PostgreSQL settings not found: $SettingsPath" }
& (Join-Path $PSScriptRoot 'Start-LocalPostgres.ps1') -SettingsPath $SettingsPath | Out-Null
if (-not (Test-Path -LiteralPath $BackupRoot)) { New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null }
$settings = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$pgDump = Join-Path $settings.install_root 'bin\pg_dump.exe'
if (-not (Test-Path -LiteralPath $pgDump -PathType Leaf)) { throw "pg_dump not found: $pgDump" }
$timestamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$backupPath = Join-Path $BackupRoot ("amazon-us-intelligence-$timestamp.dump")
$temporaryPath = $backupPath + '.partial'
$savedPassword = [Environment]::GetEnvironmentVariable('PGPASSWORD', 'Process')
try {
    $env:PGPASSWORD = [string]$settings.password
    & $pgDump '-h' ([string]$settings.host) '-p' ([string]$settings.port) '-U' ([string]$settings.username) '-d' ([string]$settings.database) '-F' 'c' '--no-owner' '--no-privileges' '-f' $temporaryPath
    if ($LASTEXITCODE -ne 0) { throw "pg_dump failed with exit code $LASTEXITCODE" }
    Move-Item -LiteralPath $temporaryPath -Destination $backupPath -Force
}
finally {
    if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
    if ($null -eq $savedPassword) { Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable('PGPASSWORD', $savedPassword, 'Process') }
}
$hash = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash.ToLowerInvariant()
$manifestPath = $backupPath + '.json'
$manifest = [ordered]@{
    schema_version = 'local-postgres-backup-v1'
    created_at = [DateTimeOffset]::UtcNow.ToString('o')
    database = [string]$settings.database
    host = [string]$settings.host
    port = [int]$settings.port
    format = 'custom'
    backup_path = (Resolve-Path -LiteralPath $backupPath).Path
    sha256 = $hash
    byte_count = [long](Get-Item -LiteralPath $backupPath).Length
}
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
[pscustomobject]@{ Status='BACKED_UP'; BackupPath=$manifest.backup_path; ManifestPath=(Resolve-Path -LiteralPath $manifestPath).Path; Sha256=$hash; ByteCount=$manifest.byte_count } | ConvertTo-Json -Depth 4
