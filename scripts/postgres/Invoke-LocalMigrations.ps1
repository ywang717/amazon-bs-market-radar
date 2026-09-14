param([string]$SettingsPath)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($SettingsPath)) { $SettingsPath = Join-Path $projectRoot '.local\postgres-settings.json' }
$settings = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$psql = Join-Path $settings.install_root 'bin\psql.exe'
$createdb = Join-Path $settings.install_root 'bin\createdb.exe'
$env:PGPASSWORD = [string]$settings.password
$common = @('-h', [string]$settings.host, '-p', [string]$settings.port, '-U', [string]$settings.username)

try {
    $databaseLookup = @(& $psql @common -d postgres -X --no-psqlrc -tAc "SELECT 1 FROM pg_database WHERE datname = '$($settings.database)'")
    $databaseExists = @($databaseLookup | Where-Object { ([string]$_).Trim() -eq '1' }).Count -gt 0
    if (-not $databaseExists) {
        & $createdb @common -E UTF8 $settings.database
        if ($LASTEXITCODE -ne 0) { throw 'createdb failed.' }
    }

    & $psql @common -d $settings.database -X --no-psqlrc -v ON_ERROR_STOP=1 -c "CREATE TABLE IF NOT EXISTS public.schema_migration (filename text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now());"
    if ($LASTEXITCODE -ne 0) { throw 'Unable to create schema_migration.' }

    $migrations = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'db\migrations') -Filter '*.sql' | Sort-Object Name
    foreach ($migration in $migrations) {
        $escapedName = $migration.Name.Replace("'", "''")
        $migrationLookup = @(& $psql @common -d $settings.database -X --no-psqlrc -tAc "SELECT 1 FROM public.schema_migration WHERE filename = '$escapedName'")
        $alreadyApplied = @($migrationLookup | Where-Object { ([string]$_).Trim() -eq '1' }).Count -gt 0
        if ($alreadyApplied) { Write-Output "Already applied: $($migration.Name)"; continue }
        & $psql @common -d $settings.database -X --no-psqlrc -v ON_ERROR_STOP=1 -f $migration.FullName
        if ($LASTEXITCODE -ne 0) { throw "Migration failed: $($migration.Name)" }
        & $psql @common -d $settings.database -X --no-psqlrc -v ON_ERROR_STOP=1 -c "INSERT INTO public.schema_migration(filename) VALUES ('$escapedName');"
        if ($LASTEXITCODE -ne 0) { throw "Unable to record migration: $($migration.Name)" }
        Write-Output "Applied: $($migration.Name)"
    }
}
finally {
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}
