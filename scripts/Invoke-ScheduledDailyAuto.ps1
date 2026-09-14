[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('Primary','Recovery')][string]$Mode,
    [string]$MarketDate,
    [string]$ProjectRoot,
    [string]$TargetScript
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent $PSScriptRoot }
$defaultTargetScript = Join-Path $ProjectRoot 'scripts\Start-LocalPackage.ps1'
if ([string]::IsNullOrWhiteSpace($TargetScript)) { $TargetScript = $defaultTargetScript }
$usesProductionTarget = [IO.Path]::GetFullPath($TargetScript) -eq [IO.Path]::GetFullPath($defaultTargetScript)
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ScheduledDailyAutomation.psm1') -Force
if ([string]::IsNullOrWhiteSpace($MarketDate)) {
    $MarketDate = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTimeOffset]::Now,'Pacific Standard Time').ToString('yyyy-MM-dd')
}
if ($MarketDate -notmatch '^\d{4}-\d{2}-\d{2}$') { throw 'MarketDate must use YYYY-MM-DD.' }
if (-not (Test-Path -LiteralPath $TargetScript -PathType Leaf)) { throw "Scheduled daily target not found: $TargetScript" }

$stateDirectory = Join-Path $ProjectRoot 'var\scheduler\daily-auto'
if (-not (Test-Path -LiteralPath $stateDirectory -PathType Container)) { New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null }
$timestamp = [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$logPath = Join-Path $stateDirectory ("daily-auto-{0}-{1}-{2}.log" -f $MarketDate,$Mode.ToLowerInvariant(),$timestamp)
$statePath = Join-Path $stateDirectory ("{0}.json" -f $MarketDate)
$windowsPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$publicationStatus = 'NOT_STARTED'
$startedAt = [DateTimeOffset]::Now.ToString('o')
$diagnosticsPath = $null

function Write-ScheduledDailyState {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Outcome,
        [Parameter(Mandatory = $true)][int]$ExitCode,
        [string]$ErrorMessage
    )
    $state = [pscustomobject][ordered]@{
        Status = $Status
        Outcome = $Outcome
        Mode = $Mode
        MarketDate = $MarketDate
        StartedAt = $startedAt
        PublicationStatus = $publicationStatus
        CompletedAt = [DateTimeOffset]::Now.ToString('o')
        ExitCode = $ExitCode
        LogPath = $logPath
        DiagnosticsPath = $diagnosticsPath
        ErrorMessage = $ErrorMessage
    }
    Write-ScheduledDailyStateFile -Path $statePath -State $state
    Write-ScheduledDailyStateFile -Path ([IO.Path]::ChangeExtension($logPath,'.json')) -State $state
}

function Invoke-LocalPackageChild {
    param([Parameter(Mandatory = $true)][ValidateSet('DailyAuto','Health')][string]$ChildMode)
    $childStartedUtc = [DateTime]::UtcNow
    $arguments = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$TargetScript,'-Mode',$ChildMode,'-MarketDate',$MarketDate)
    $output = @(& $windowsPowerShell @arguments 2>&1)
    $childExitCode = $LASTEXITCODE
    foreach ($line in $output) { Write-Host ([string]$line) }
    if ($ChildMode -eq 'DailyAuto') {
        $snapshotDirectory = Join-Path $ProjectRoot ('var\amazon-bestsellers\' + $MarketDate)
        foreach ($name in @('price-completeness-diagnostic.json','best-sellers-collection-status.json')) {
            $source = Join-Path $snapshotDirectory $name
            if (Test-Path -LiteralPath $source -PathType Leaf) {
                $file = Get-Item -LiteralPath $source
                if ($file.LastWriteTimeUtc -ge $childStartedUtc) {
                    $script:diagnosticsPath = [IO.Path]::ChangeExtension($logPath,$null) + '-diagnostics'
                    New-Item -ItemType Directory -Path $script:diagnosticsPath -Force | Out-Null
                    Copy-Item -LiteralPath $source -Destination (Join-Path $script:diagnosticsPath $name)
                }
            }
        }
    }
    return [pscustomobject]@{ ExitCode = [int]$childExitCode }
}

function Initialize-ScheduledDailyPythonEnvironment {
    if (-not $usesProductionTarget) { return }
    $venvPython = Join-Path $ProjectRoot '.venv\Scripts\python.exe'
    if (Test-Path -LiteralPath $venvPython -PathType Leaf) { return }

    $initializer = Join-Path $ProjectRoot 'scripts\Initialize-PythonEnvironment.ps1'
    if (-not (Test-Path -LiteralPath $initializer -PathType Leaf)) {
        throw "Project Python environment is missing and its initializer was not found: $initializer"
    }
    Write-Host 'Project Python environment is missing; initializing it before the daily run.'
    $output = @(& $windowsPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $initializer 2>&1)
    $initializerExitCode = $LASTEXITCODE
    foreach ($line in $output) { Write-Host ([string]$line) }
    if ($initializerExitCode -ne 0 -or -not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
        throw "Project Python environment initialization failed with exit code $initializerExitCode."
    }
}

$taskExitCode = 1
$taskOutcome = 'EXECUTED'
$dailyMutex = $null
$dailyMutexAcquired = $false
Start-Transcript -LiteralPath $logPath -Force | Out-Null
try {
    $dailyMutex = New-Object System.Threading.Mutex($false,('AmazonBS-DailyAuto-' + $MarketDate))
    $lockTimeout = if ($Mode -eq 'Recovery') { [TimeSpan]::FromMinutes(60) } else { [TimeSpan]::Zero }
    try {
        $dailyMutexAcquired = $dailyMutex.WaitOne($lockTimeout)
    }
    catch [System.Threading.AbandonedMutexException] {
        $dailyMutexAcquired = $true
    }
    if (-not $dailyMutexAcquired) { throw "Another scheduled daily run still owns the lock for $MarketDate." }

    if ($Mode -eq 'Recovery') {
        $health = Invoke-LocalPackageChild -ChildMode Health
        if ($health.ExitCode -eq 0) {
            $taskExitCode = 0
            $taskOutcome = 'SKIPPED_HEALTHY'
        }
        else {
            Initialize-ScheduledDailyPythonEnvironment
            $daily = Invoke-LocalPackageChild -ChildMode DailyAuto
            $taskExitCode = $daily.ExitCode
            $taskOutcome = 'RECOVERED'
        }
    }
    else {
        Initialize-ScheduledDailyPythonEnvironment
        $daily = Invoke-LocalPackageChild -ChildMode DailyAuto
        $taskExitCode = $daily.ExitCode
    }

    if ($taskExitCode -eq 0 -and $usesProductionTarget -and
        [IO.Path]::GetFullPath($ProjectRoot) -eq [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))) {
        $publicationStatus = 'RUNNING'
        $publication = Invoke-ScheduledDailyPublication -MarketDate $MarketDate
        $publicationStatus = $publication.Status
        $taskExitCode = $publication.ExitCode
    }

    if ($taskExitCode -eq 0) {
        Write-ScheduledDailyState -Status SUCCEEDED -Outcome $taskOutcome -ExitCode 0
    }
    else {
        Write-ScheduledDailyState -Status FAILED -Outcome $taskOutcome -ExitCode $taskExitCode -ErrorMessage 'Scheduled daily processing failed; see the transcript log.'
    }
}
catch {
    $taskExitCode = 1
    if ($publicationStatus -eq 'RUNNING') { $publicationStatus = 'FAILED' }
    if ($dailyMutexAcquired) {
        Write-ScheduledDailyState -Status FAILED -Outcome $taskOutcome -ExitCode $taskExitCode -ErrorMessage 'Scheduled daily launcher failed; see the transcript log.'
    }
    else {
        Write-Host 'Canonical daily state was not changed because this launcher did not acquire the daily lock.'
    }
    Write-Error $_.Exception.Message
}
finally {
    if ($dailyMutexAcquired -and $null -ne $dailyMutex) { $dailyMutex.ReleaseMutex() }
    if ($null -ne $dailyMutex) { $dailyMutex.Dispose() }
    Stop-Transcript | Out-Null
}
exit $taskExitCode
