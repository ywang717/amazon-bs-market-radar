param([string]$SettingsPath)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($SettingsPath)) { $SettingsPath = Join-Path $projectRoot '.local\postgres-settings.json' }
if (-not (Test-Path -LiteralPath $SettingsPath)) { throw "PostgreSQL settings not found: $SettingsPath" }
$settings = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$pgCtl = Join-Path $settings.install_root 'bin\pg_ctl.exe'
$pgIsReady = Join-Path $settings.install_root 'bin\pg_isready.exe'
foreach ($tool in @($pgCtl, $pgIsReady)) { if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "PostgreSQL tool not found: $tool" } }
Import-Module (Join-Path $projectRoot 'src\LocalPostgresLifecycle.psm1') -Force
$logPath = Get-LocalPostgresLogPath -DataRoot ([string]$settings.data_root)

& $pgIsReady '-h' ([string]$settings.host) '-p' ([string]$settings.port) *> $null
$isReady = $LASTEXITCODE -eq 0
& $pgCtl status -D $settings.data_root *> $null
$serverRunning = $LASTEXITCODE -eq 0
$action = Get-LocalPostgresStartupAction -IsReady:$isReady -ServerRunning:$serverRunning

if ($action -eq 'ALREADY_READY') {
    Write-Output 'PostgreSQL is already running.'
}
else {
    if ($action -eq 'RESTART') {
        & $pgCtl restart -D $settings.data_root -m fast -l $logPath -w -t 45
        if ($LASTEXITCODE -ne 0) { throw "pg_ctl restart failed with exit code $LASTEXITCODE. See $logPath" }
    }
    else {
        & $pgCtl start -D $settings.data_root -l $logPath -w -t 45
        if ($LASTEXITCODE -ne 0) { throw "pg_ctl start failed with exit code $LASTEXITCODE. See $logPath" }
    }
    & $pgIsReady '-h' ([string]$settings.host) '-p' ([string]$settings.port) *> $null
    if ($LASTEXITCODE -ne 0) { throw "PostgreSQL did not accept connections after startup. See $logPath" }
    Write-Output "PostgreSQL $($action.ToLowerInvariant()) completed on $($settings.host):$($settings.port)"
}
