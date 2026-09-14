param([string]$SettingsPath)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($SettingsPath)) { $SettingsPath = Join-Path $projectRoot '.local\postgres-settings.json' }
if (-not (Test-Path -LiteralPath $SettingsPath)) { throw "PostgreSQL settings not found: $SettingsPath" }
$settings = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$pgCtl = Join-Path $settings.install_root 'bin\pg_ctl.exe'

& $pgCtl status -D $settings.data_root *> $null
if ($LASTEXITCODE -ne 0) { Write-Output 'PostgreSQL is not running.'; exit 0 }
& $pgCtl stop -D $settings.data_root -m fast -w -t 30
if ($LASTEXITCODE -ne 0) { throw "pg_ctl stop failed with exit code $LASTEXITCODE" }
Write-Output 'PostgreSQL stopped.'
