param(
    [string]$InstallRoot,
    [string]$DataRoot,
    [int]$Port = 55432
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($InstallRoot)) { $InstallRoot = Join-Path $projectRoot '.local\postgresql' }
if ([string]::IsNullOrWhiteSpace($DataRoot)) { $DataRoot = Join-Path $projectRoot '.local\postgres-data' }
$settingsPath = Join-Path $projectRoot '.local\postgres-settings.json'

$binRoot = Join-Path $InstallRoot 'bin'
$initdb = Join-Path $binRoot 'initdb.exe'
if (-not (Test-Path -LiteralPath $initdb -PathType Leaf)) { throw "PostgreSQL initdb not found: $initdb" }
if (Test-Path -LiteralPath (Join-Path $DataRoot 'PG_VERSION')) { throw "PostgreSQL data directory is already initialized: $DataRoot" }

New-Item -ItemType Directory -Path $DataRoot -Force | Out-Null
$randomBytes = New-Object byte[] 32
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($randomBytes) } finally { $rng.Dispose() }
$password = ([Convert]::ToBase64String($randomBytes)).Replace('/', '_').Replace('+', '-').TrimEnd('=')
$passwordFile = Join-Path $projectRoot '.local\postgres-init-password.tmp'
try {
    [System.IO.File]::WriteAllText($passwordFile, $password, (New-Object System.Text.UTF8Encoding($false)))
    & $initdb -D $DataRoot -U postgres --encoding=UTF8 --locale=C `
        --auth-local=scram-sha-256 --auth-host=scram-sha-256 --pwfile=$passwordFile
    if ($LASTEXITCODE -ne 0) { throw "initdb failed with exit code $LASTEXITCODE" }
}
finally {
    if (Test-Path -LiteralPath $passwordFile) { Remove-Item -LiteralPath $passwordFile -Force }
}

$postgresqlConf = Join-Path $DataRoot 'postgresql.conf'
@(
    "listen_addresses = '127.0.0.1'",
    "port = $Port",
    "max_connections = 30",
    "shared_buffers = '64MB'",
    "timezone = 'UTC'",
    "log_timezone = 'UTC'"
) | Add-Content -LiteralPath $postgresqlConf -Encoding UTF8

$settings = [ordered]@{
    install_root = (Resolve-Path -LiteralPath $InstallRoot).Path
    data_root = (Resolve-Path -LiteralPath $DataRoot).Path
    host = '127.0.0.1'
    port = $Port
    database = 'amazon_us_intelligence'
    username = 'postgres'
    password = $password
}
[System.IO.File]::WriteAllText(
    $settingsPath,
    ($settings | ConvertTo-Json),
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Output "PostgreSQL initialized at $DataRoot"
Write-Output "Settings stored in ignored local file: $settingsPath"

