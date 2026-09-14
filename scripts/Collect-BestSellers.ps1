[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$ConfigPath,
    [string]$OutputRoot,
    [string]$MarketDate,
    [switch]$Headless,
    [string]$FixtureInput
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent $PSScriptRoot }
$pythonPath = if ($IsMacOS -and (Test-Path '/usr/bin/python3')) { '/usr/bin/python3' } else { Join-Path $ProjectRoot '.venv\Scripts\python.exe' }
$collectorPath = Join-Path $ProjectRoot 'scripts\python\collect_best_sellers.py'

if (-not (Test-Path -LiteralPath $pythonPath -PathType Leaf)) {
    [Console]::Out.WriteLine((@{ Status = 'ERROR'; ExitCode = 3; ErrorReason = "Project Python virtual environment not found: $pythonPath" } | ConvertTo-Json -Compress))
    exit 3
}
if (-not (Test-Path -LiteralPath $collectorPath -PathType Leaf)) {
    [Console]::Out.WriteLine((@{ Status = 'ERROR'; ExitCode = 4; ErrorReason = "Collector script not found: $collectorPath" } | ConvertTo-Json -Compress))
    exit 4
}

$env:PLAYWRIGHT_BROWSERS_PATH = if ($IsMacOS) { Join-Path $HOME 'Library/Caches/ms-playwright' } else { Join-Path $ProjectRoot '.local\playwright' }
$arguments = @($collectorPath, '--project-root', $ProjectRoot)
if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) { $arguments += @('--config', $ConfigPath) }
if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) { $arguments += @('--output-root', $OutputRoot) }
if (-not [string]::IsNullOrWhiteSpace($MarketDate)) { $arguments += @('--market-date', $MarketDate) }
if ($Headless) { $arguments += '--headless' }
if (-not [string]::IsNullOrWhiteSpace($FixtureInput)) { $arguments += @('--fixture-input', $FixtureInput) }

& $pythonPath @arguments
$collectorExitCode = $LASTEXITCODE
exit $collectorExitCode
