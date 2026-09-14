Set-StrictMode -Version 2.0

$script:LocalPackageModes = @(
    'Menu',
    'Setup',
    'ConfigureEmail',
    'DailyAuto',
    'DailyImport',
    'Weekly',
    'Health',
    'Test',
    'RegisterTasks',
    'ExportHistory',
    'ImportHistory'
)

$script:LocalPackageCollectorFailureReasons = @(
    'ARTIFACT_BUILD_FAILED',
    'ARTIFACT_WRITE_FAILED',
    'ATTEMPT_ERROR',
    'BROWSER_CLEANUP_FAILED',
    'CATEGORY_MISSING',
    'CATEGORY_NOT_COMPLETE',
    'COLLECTOR_RUNTIME_FAILED',
    'COMPLETENESS_NOT_VERIFIED',
    'CONFIG_LOAD_FAILED',
    'CONTEXT_CLEANUP_FAILED',
    'DUPLICATE_ASIN',
    'DUPLICATE_CATEGORY_RESULT',
    'FIXTURE_LOAD_FAILED',
    'INVALID_RANKS',
    'MISSING_ASIN',
    'MISSING_PRICE_EVIDENCE',
    'MISSING_RANK',
    'MISSING_TITLE',
    'PRICE_VERIFICATION_FAILED',
    'SETUP_FAILED',
    'UNEXPECTED_CATEGORY',
    'UNSAFE_DIAGNOSTIC_REDACTED'
)

function ConvertFrom-LocalPackageBase64 {
    param([Parameter(Mandatory = $true)][string]$Value)
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value))
}

function Get-LocalPackageMenuMode {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Choice)

    $mapping = @{
        '1' = 'DailyAuto'
        '2' = 'DailyImport'
        '3' = 'Weekly'
        '4' = 'Setup'
        '5' = 'ConfigureEmail'
        '6' = 'Health'
        '7' = 'Test'
        '8' = 'RegisterTasks'
        '9' = 'ExportHistory'
        '10' = 'ImportHistory'
        '0' = 'Exit'
    }
    if ($mapping.ContainsKey($Choice)) { return [string]$mapping[$Choice] }
    return $null
}

function Test-LocalPackageMarketDate {
    [CmdletBinding()]
    param([string]$MarketDate)

    if ([string]::IsNullOrWhiteSpace($MarketDate) -or $MarketDate -notmatch '^\d{4}-\d{2}-\d{2}$') { return $false }
    $parsed = [datetime]::MinValue
    return [datetime]::TryParseExact(
        $MarketDate,
        'yyyy-MM-dd',
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None,
        [ref]$parsed
    )
}

function Get-LocalPackageDefaultMarketDate {
    $pacificNow = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTimeOffset]::Now, 'Pacific Standard Time')
    $pacificNow.ToString('yyyy-MM-dd')
}

function Enter-LocalPackageModeLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$Mode
    )

    $lockDirectory = Join-Path $ProjectRoot '.local\locks'
    if (-not (Test-Path -LiteralPath $lockDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $lockDirectory -Force | Out-Null
    }
    $lockPath = Join-Path $lockDirectory (([string]$Mode).ToLowerInvariant() + '.lock')
    try {
        $stream = New-Object IO.FileStream(
            $lockPath,
            [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None
        )
        $stream.SetLength(0)
        $bytes = [Text.Encoding]::UTF8.GetBytes(([Diagnostics.Process]::GetCurrentProcess().Id.ToString()))
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
        return $stream
    }
    catch [IO.IOException] {
        throw "Mode '$Mode' is already running. Wait for it to finish and try again."
    }
}

function Exit-LocalPackageModeLock {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Lock)
    if ($null -ne $Lock) { $Lock.Dispose() }
}

function ConvertTo-LocalPackageArgumentList {
    param([hashtable]$Arguments)
    $list = New-Object System.Collections.ArrayList
    foreach ($name in @($Arguments.Keys | Sort-Object)) {
        $value = $Arguments[$name]
        if ($value -is [bool]) {
            if ($value) { [void]$list.Add("-$name") }
            continue
        }
        if ($null -eq $value -or ($value -is [string] -and [string]::IsNullOrWhiteSpace($value))) { continue }
        [void]$list.Add("-$name")
        [void]$list.Add([string]$value)
    }
    return @($list)
}

function ConvertFrom-LocalPackageStepOutput {
    param([object[]]$Output)
    $lines = @($Output | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -gt 0) {
        try { return (($lines -join "`n") | ConvertFrom-Json -ErrorAction Stop) }
        catch { }
    }
    for ($index = $lines.Count - 1; $index -ge 0; $index--) {
        try { return ($lines[$index] | ConvertFrom-Json -ErrorAction Stop) }
        catch { }
    }
    return $null
}

function Get-LocalPackagePropertyValue {
    param(
        $InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Protect-LocalPackageErrorText {
    param([string]$Text, [scriptblock]$EnvironmentValueProvider)
    $safe = $Text
    foreach ($scope in @('Process','User')) {
        $secret = [string](& $EnvironmentValueProvider 'DAILY_REPORT_SMTP_AUTH_CODE' $scope)
        if (-not [string]::IsNullOrWhiteSpace($secret)) { $safe = $safe.Replace($secret, '[REDACTED]') }
    }
    return $safe
}

function Get-LocalPackageCollectorCompletenessFailure {
    param(
        $CollectorResult,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$MarketDate
    )

    $parts = New-Object System.Collections.ArrayList
    [void]$parts.Add('Collector pricing completeness was not COMPLETE; receipt, reports, backup, and email were not started.')

    $diagnosticPath = [string](Get-LocalPackagePropertyValue -InputObject $CollectorResult -Name 'DiagnosticPath')
    if (-not [string]::IsNullOrWhiteSpace($diagnosticPath)) {
        $canonicalDiagnosticPath = Join-Path (Join-Path (Join-Path $ProjectRoot 'var\amazon-bestsellers') $MarketDate) 'price-completeness-diagnostic.json'
        try {
            $normalizedDiagnosticPath = [IO.Path]::GetFullPath($diagnosticPath)
            $normalizedCanonicalPath = [IO.Path]::GetFullPath($canonicalDiagnosticPath)
            if ($normalizedDiagnosticPath -eq $normalizedCanonicalPath) {
                [void]$parts.Add("DiagnosticPath: $normalizedCanonicalPath.")
            }
        }
        catch { }
    }

    $safeReasons = New-Object System.Collections.ArrayList
    $failureReasons = Get-LocalPackagePropertyValue -InputObject $CollectorResult -Name 'FailureReasons'
    foreach ($reasonValue in @($failureReasons)) {
        $reason = [string]$reasonValue
        if ($reason -cin $script:LocalPackageCollectorFailureReasons -and -not $safeReasons.Contains($reason)) {
            [void]$safeReasons.Add($reason)
        }
    }
    if ($safeReasons.Count -gt 0) {
        [void]$parts.Add('FailureReasons: ' + (@($safeReasons) -join ', ') + '.')
    }

    return (@($parts) -join ' ')
}

function Get-LocalPackageConfiguredRecipient {
    param([string]$ProjectRoot)
    $path = Join-Path $ProjectRoot '.local\user-settings.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { $settings = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "Local recipient settings are not valid JSON: $path" }
    $recipient = [string](Get-LocalPackagePropertyValue -InputObject $settings -Name 'recipient_address')
    if ($recipient -notmatch '^[^\s@]+@[^\s@]+\.[^\s@]+$') { throw "Local recipient settings contain an invalid recipient_address: $path" }
    try { $parsed = New-Object Net.Mail.MailAddress($recipient) } catch { throw "Local recipient settings contain an invalid recipient_address: $path" }
    if ($parsed.Address -ne $recipient) { throw "Local recipient settings contain an invalid recipient_address: $path" }
    return $recipient
}

function Invoke-DefaultLocalPackageStep {
    param(
        [Parameter(Mandatory = $true)][string]$Step,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [hashtable]$Arguments = @{}
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "Required script is missing: $ScriptPath. Complete local package setup/update, then retry."
    }
    $powershellPath = if ($IsMacOS) { (Get-Command pwsh -ErrorAction Stop).Source } else { Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
    $argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath)
    $argumentList += ConvertTo-LocalPackageArgumentList -Arguments $Arguments
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $powershellPath @argumentList 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }
    [pscustomobject]@{
        ExitCode = [int]$exitCode
        Result = ConvertFrom-LocalPackageStepOutput -Output $output
    }
}

function Add-LocalPackageStepResult {
    param(
        [Parameter(Mandatory = $true)]$Steps,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Run
    )
    $exitCode = if ($null -ne $Run.PSObject.Properties['ExitCode']) { [int]$Run.ExitCode } else { 1 }
    [void]$Steps.Add([pscustomobject]@{
        name = $Name
        status = if ($exitCode -eq 0) { 'SUCCESS' } else { 'FAILED' }
        exit_code = $exitCode
    })
}

function Set-LocalPackageStepFailed {
    param(
        [Parameter(Mandatory = $true)]$Steps,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $matching = @($Steps | Where-Object { [string]$_.name -eq $Name } | Select-Object -Last 1)
    if ($matching.Count -eq 1) {
        $matching[0].status = 'FAILED'
        $matching[0].exit_code = 1
    }
}

function Invoke-LocalPackageTrackedStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [hashtable]$Arguments = @{},
        [Parameter(Mandatory = $true)][scriptblock]$StepRunner,
        [Parameter(Mandatory = $true)]$Steps
    )
    try {
        $run = & $StepRunner $Name $ScriptPath $Arguments
    }
    catch {
        Add-LocalPackageStepResult -Steps $Steps -Name $Name -Run ([pscustomobject]@{ ExitCode = 1 })
        throw
    }
    if ($null -eq $run) { $run = [pscustomobject]@{ ExitCode = 1; Result = $null } }
    Add-LocalPackageStepResult -Steps $Steps -Name $Name -Run $run
    return $run
}

function Assert-LocalPackageStepSucceeded {
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)]$Run)
    if ([int]$Run.ExitCode -ne 0) {
        $reason = [string](Get-LocalPackagePropertyValue -InputObject $Run.Result -Name 'error')
        if ([string]::IsNullOrWhiteSpace($reason)) {
            $errors = Get-LocalPackagePropertyValue -InputObject $Run.Result -Name 'errors'
            if ($null -ne $errors) { $reason = (@($errors) -join '; ') }
        }
        if (-not [string]::IsNullOrWhiteSpace($reason)) { throw "Step '$Name' failed: $reason" }
        throw "Step '$Name' failed with exit code $($Run.ExitCode)."
    }
}

function Resolve-LocalPackagePreviousSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$SnapshotsRoot,
        [Parameter(Mandatory = $true)][string]$MarketDate
    )
    if (-not (Test-Path -LiteralPath $SnapshotsRoot -PathType Container)) { return $null }
    $path = @(Get-ChildItem -LiteralPath $SnapshotsRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and $_.Name -lt $MarketDate } |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName 'amazon-bestsellers.json' } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1)
    if ($path.Count -eq 1) { return [string]$path[0] }
    return $null
}

function Copy-LocalPackageImportedSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$SnapshotPath,
        [string]$RequestedMarketDate
    )
    if (-not (Test-Path -LiteralPath $SnapshotPath -PathType Leaf)) { throw "Snapshot is not readable: $SnapshotPath" }
    try {
        $snapshot = Get-Content -LiteralPath $SnapshotPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Snapshot is not readable JSON: $SnapshotPath"
    }
    $snapshotMarketDate = [string]$snapshot.market_date
    if (-not (Test-LocalPackageMarketDate -MarketDate $snapshotMarketDate)) { throw 'Snapshot market_date must use YYYY-MM-DD and be a real calendar date.' }
    if (-not [string]::IsNullOrWhiteSpace($RequestedMarketDate) -and $RequestedMarketDate -ne $snapshotMarketDate) {
        throw "Snapshot market date '$snapshotMarketDate' does not match requested market date '$RequestedMarketDate'."
    }
    $canonicalPath = Join-Path (Join-Path (Join-Path $ProjectRoot 'var\amazon-bestsellers') $snapshotMarketDate) 'amazon-bestsellers.json'
    $sourceResolved = (Resolve-Path -LiteralPath $SnapshotPath).Path
    if (Test-Path -LiteralPath $canonicalPath -PathType Leaf) {
        $canonicalResolved = (Resolve-Path -LiteralPath $canonicalPath).Path
        if ($sourceResolved -ne $canonicalResolved) {
            $sourceHash = (Get-FileHash -LiteralPath $sourceResolved -Algorithm SHA256).Hash
            $canonicalHash = (Get-FileHash -LiteralPath $canonicalResolved -Algorithm SHA256).Hash
            if ($sourceHash -ne $canonicalHash) {
                throw "A different snapshot already exists at $canonicalPath; the existing snapshot was preserved."
            }
        }
    }
    else {
        $directory = Split-Path -Parent $canonicalPath
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
        $stagingPath = Join-Path $directory ('.amazon-bestsellers.' + [guid]::NewGuid().ToString('N') + '.staging')
        try {
            $sourceInfo = Get-Item -LiteralPath $sourceResolved
            $sourceHash = (Get-FileHash -LiteralPath $sourceResolved -Algorithm SHA256).Hash
            Copy-Item -LiteralPath $sourceResolved -Destination $stagingPath
            if (-not (Test-Path -LiteralPath $stagingPath -PathType Leaf)) { throw 'Snapshot staging copy was not created.' }
            $stagingInfo = Get-Item -LiteralPath $stagingPath
            $stagingHash = (Get-FileHash -LiteralPath $stagingPath -Algorithm SHA256).Hash
            if ($stagingInfo.Length -ne $sourceInfo.Length -or $stagingHash -ne $sourceHash) {
                throw 'Snapshot staging copy did not match the source content.'
            }
            [IO.File]::Move($stagingPath, $canonicalPath)
        }
        finally {
            if (Test-Path -LiteralPath $stagingPath -PathType Leaf) { Remove-Item -LiteralPath $stagingPath -Force }
        }
    }
    [pscustomobject]@{ MarketDate = $snapshotMarketDate; SnapshotPath = $canonicalPath }
}

function New-LocalPackageSummary {
    param([string]$Mode, [string]$MarketDate)
    [pscustomobject][ordered]@{
        mode = $Mode
        status = 'FAILED'
        market_date = $MarketDate
        artifacts = [pscustomobject][ordered]@{
            snapshot_path = $null
            receipt_path = $null
            previous_snapshot_path = $null
            report_directory = $null
            backup_path = $null
        }
        steps = New-Object System.Collections.ArrayList
        error = $null
        exit_code = 1
    }
}

function Invoke-LocalPackageDailyGates {
    param(
        [Parameter(Mandatory = $true)]$Summary,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$SnapshotPath,
        [Parameter(Mandatory = $true)][string]$MarketDate,
        [switch]$SkipEmail,
        [Parameter(Mandatory = $true)][scriptblock]$StepRunner
    )
    $scriptsRoot = Join-Path $ProjectRoot 'scripts'
    $snapshotDirectory = Split-Path -Parent $SnapshotPath
    $receiptPath = Join-Path $snapshotDirectory 'best-sellers-capture-receipt.json'
    $Summary.artifacts.snapshot_path = $SnapshotPath
    $Summary.artifacts.receipt_path = $receiptPath

    $run = Invoke-LocalPackageTrackedStep -Name 'RegisterReceipt' -ScriptPath (Join-Path $scriptsRoot 'Register-BestSellersSnapshot.ps1') -Arguments @{ SnapshotPath = $SnapshotPath } -StepRunner $StepRunner -Steps $Summary.steps
    Assert-LocalPackageStepSucceeded -Name 'RegisterReceipt' -Run $run

    $run = Invoke-LocalPackageTrackedStep -Name 'VerifyReceipt' -ScriptPath (Join-Path $scriptsRoot 'Test-BestSellersCaptureReceipt.ps1') -Arguments @{ ReceiptPath = $receiptPath } -StepRunner $StepRunner -Steps $Summary.steps
    Assert-LocalPackageStepSucceeded -Name 'VerifyReceipt' -Run $run
    if ((Get-LocalPackagePropertyValue -InputObject $run.Result -Name 'valid') -ne $true) {
        Set-LocalPackageStepFailed -Steps $Summary.steps -Name 'VerifyReceipt'
        throw "Step 'VerifyReceipt' did not return a valid receipt."
    }

    $run = Invoke-LocalPackageTrackedStep -Name 'ImportSnapshot' -ScriptPath (Join-Path $scriptsRoot 'Import-VerifiedBestSellersSnapshot.ps1') -Arguments @{ SnapshotPath = $SnapshotPath; ReceiptPath = $receiptPath } -StepRunner $StepRunner -Steps $Summary.steps
    Assert-LocalPackageStepSucceeded -Name 'ImportSnapshot' -Run $run
    if ([string](Get-LocalPackagePropertyValue -InputObject $run.Result -Name 'Status') -ne 'IMPORTED_VERIFIED_SNAPSHOT') {
        Set-LocalPackageStepFailed -Steps $Summary.steps -Name 'ImportSnapshot'
        throw "Step 'ImportSnapshot' did not confirm a verified import."
    }

    $snapshotsRoot = Join-Path $ProjectRoot 'var\amazon-bestsellers'
    $previousPath = Resolve-LocalPackagePreviousSnapshot -SnapshotsRoot $snapshotsRoot -MarketDate $MarketDate
    $Summary.artifacts.previous_snapshot_path = $previousPath
    $reportDirectory = Join-Path (Join-Path $ProjectRoot 'var\reports') $MarketDate
    $Summary.artifacts.report_directory = $reportDirectory
    $reportArguments = @{ CurrentPath = $SnapshotPath; OutputDirectory = $reportDirectory; SkipEmail = [bool]$SkipEmail }
    $recipient = Get-LocalPackageConfiguredRecipient -ProjectRoot $ProjectRoot
    if (-not [string]::IsNullOrWhiteSpace($recipient)) { $reportArguments.EmailRecipient = $recipient }
    if (-not [string]::IsNullOrWhiteSpace($previousPath)) { $reportArguments.PreviousPath = $previousPath }
    $run = Invoke-LocalPackageTrackedStep -Name 'DailyReports' -ScriptPath (Join-Path $scriptsRoot 'New-BestSellersDailyReport.ps1') -Arguments $reportArguments -StepRunner $StepRunner -Steps $Summary.steps
    Assert-LocalPackageStepSucceeded -Name 'DailyReports' -Run $run
    $reports = Get-LocalPackagePropertyValue -InputObject $run.Result -Name 'Reports'
    if (@($reports).Count -ne 3) {
        Set-LocalPackageStepFailed -Steps $Summary.steps -Name 'DailyReports'
        throw "Step 'DailyReports' did not confirm exactly three reports."
    }
    $delivery = Get-LocalPackagePropertyValue -InputObject $run.Result -Name 'EmailDelivery'
    $deliveryStatus = [string](Get-LocalPackagePropertyValue -InputObject $delivery -Name 'Status')
    $requiredDeliveryStatus = if ($SkipEmail) { 'SKIPPED_BY_REQUEST' } else { 'SENT' }
    if ($deliveryStatus -ne $requiredDeliveryStatus) {
        Set-LocalPackageStepFailed -Steps $Summary.steps -Name 'DailyReports'
        throw "Step 'DailyReports' EmailDelivery.Status must be '$requiredDeliveryStatus', received '$deliveryStatus'."
    }

    $run = Invoke-LocalPackageTrackedStep -Name 'Backup' -ScriptPath (Join-Path $scriptsRoot 'postgres\Backup-LocalPostgres.ps1') -Arguments @{} -StepRunner $StepRunner -Steps $Summary.steps
    Assert-LocalPackageStepSucceeded -Name 'Backup' -Run $run
    $backupStatus = [string](Get-LocalPackagePropertyValue -InputObject $run.Result -Name 'Status')
    $backupPath = [string](Get-LocalPackagePropertyValue -InputObject $run.Result -Name 'BackupPath')
    if ($backupStatus -ne 'BACKED_UP' -or [string]::IsNullOrWhiteSpace($backupPath)) {
        Set-LocalPackageStepFailed -Steps $Summary.steps -Name 'Backup'
        throw "Step 'Backup' did not return a backup artifact."
    }
    $Summary.artifacts.backup_path = $backupPath

    $run = Invoke-LocalPackageTrackedStep -Name 'VerifyBackup' -ScriptPath (Join-Path $scriptsRoot 'postgres\Test-LocalPostgresBackup.ps1') -Arguments @{ BackupPath = $Summary.artifacts.backup_path } -StepRunner $StepRunner -Steps $Summary.steps
    Assert-LocalPackageStepSucceeded -Name 'VerifyBackup' -Run $run
    if ([string](Get-LocalPackagePropertyValue -InputObject $run.Result -Name 'Status') -ne 'VERIFIED') {
        Set-LocalPackageStepFailed -Steps $Summary.steps -Name 'VerifyBackup'
        throw "Step 'VerifyBackup' did not verify the backup."
    }

    $run = Invoke-LocalPackageTrackedStep -Name 'Health' -ScriptPath (Join-Path $scriptsRoot 'Test-BestSellersDailyOperationalHealth.ps1') -Arguments @{ MarketDate = $MarketDate } -StepRunner $StepRunner -Steps $Summary.steps
    Assert-LocalPackageStepSucceeded -Name 'Health' -Run $run
    if ([string](Get-LocalPackagePropertyValue -InputObject $run.Result -Name 'Status') -ne 'HEALTHY') {
        Set-LocalPackageStepFailed -Steps $Summary.steps -Name 'Health'
        throw "Step 'Health' did not report HEALTHY."
    }
}

function Invoke-LocalPackageMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Mode,
        [string]$MarketDate,
        [string]$SnapshotPath,
        [string]$ArchivePath,
        [string]$OutputPath,
        [switch]$SkipEmail,
        [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
        [scriptblock]$StepRunner,
        [scriptblock]$EnvironmentValueProvider = { param($Name, $Scope) [Environment]::GetEnvironmentVariable($Name, $Scope) }
    )

    $summary = New-LocalPackageSummary -Mode $Mode -MarketDate $MarketDate
    $lock = $null
    try {
        if ($Mode -notin $script:LocalPackageModes -or $Mode -eq 'Menu') { throw "Unsupported non-menu mode: $Mode" }
        if (-not [string]::IsNullOrWhiteSpace($MarketDate) -and -not (Test-LocalPackageMarketDate -MarketDate $MarketDate)) {
            throw 'MarketDate must use YYYY-MM-DD and be a real calendar date.'
        }
        if ($Mode -in @('DailyAuto','Health') -and [string]::IsNullOrWhiteSpace($MarketDate)) { $MarketDate = Get-LocalPackageDefaultMarketDate }
        $summary.market_date = $MarketDate
        if ($null -eq $StepRunner) { $StepRunner = ${function:Invoke-DefaultLocalPackageStep} }
        $lock = Enter-LocalPackageModeLock -ProjectRoot $ProjectRoot -Mode $Mode

        $scriptsRoot = Join-Path $ProjectRoot 'scripts'
        switch ($Mode) {
            'DailyAuto' {
                $canonicalPath = Join-Path (Join-Path (Join-Path $ProjectRoot 'var\amazon-bestsellers') $MarketDate) 'amazon-bestsellers.json'
                try {
                    $run = Invoke-LocalPackageTrackedStep -Name 'Collect' -ScriptPath (Join-Path $scriptsRoot 'Collect-BestSellers.ps1') -Arguments @{ MarketDate = $MarketDate } -StepRunner $StepRunner -Steps $summary.steps
                }
                catch {
                    Set-LocalPackageStepFailed -Steps $summary.steps -Name 'Collect'
                    throw 'Collector collection failed before pricing completeness could be verified; receipt, reports, backup, and email were not started.'
                }
                $completenessStatus = [string](Get-LocalPackagePropertyValue -InputObject $run.Result -Name 'CompletenessStatus')
                if ($completenessStatus -cne 'COMPLETE') {
                    Set-LocalPackageStepFailed -Steps $summary.steps -Name 'Collect'
                    throw (Get-LocalPackageCollectorCompletenessFailure -CollectorResult $run.Result -ProjectRoot $ProjectRoot -MarketDate $MarketDate)
                }
                $observationValue = Get-LocalPackagePropertyValue -InputObject $run.Result -Name 'TotalObservations'
                $observationCount = if ($null -ne $observationValue) { [int]$observationValue } else { -1 }
                if ($observationCount -eq 0) {
                    Set-LocalPackageStepFailed -Steps $summary.steps -Name 'Collect'
                    throw 'Collector returned zero observations; receipt, reports, backup, and email were not started.'
                }
                if ([int]$run.ExitCode -ne 0) {
                    Set-LocalPackageStepFailed -Steps $summary.steps -Name 'Collect'
                    throw "Collector reported COMPLETE but failed with exit code $($run.ExitCode); receipt, reports, backup, and email were not started."
                }
                $collectorPath = [string](Get-LocalPackagePropertyValue -InputObject $run.Result -Name 'SnapshotPath')
                if ([string]::IsNullOrWhiteSpace($collectorPath)) {
                    Set-LocalPackageStepFailed -Steps $summary.steps -Name 'Collect'
                    throw "Collector SnapshotPath must equal the canonical snapshot path: $canonicalPath"
                }
                try {
                    $normalizedCollectorPath = [IO.Path]::GetFullPath($collectorPath)
                    $normalizedCanonicalPath = [IO.Path]::GetFullPath($canonicalPath)
                }
                catch {
                    Set-LocalPackageStepFailed -Steps $summary.steps -Name 'Collect'
                    throw "Collector SnapshotPath could not be normalized to the canonical snapshot path: $canonicalPath"
                }
                if ($normalizedCollectorPath -ne $normalizedCanonicalPath) {
                    Set-LocalPackageStepFailed -Steps $summary.steps -Name 'Collect'
                    throw "Collector SnapshotPath must equal the canonical snapshot path: $canonicalPath"
                }
                if (-not (Test-Path -LiteralPath $canonicalPath -PathType Leaf)) {
                    Set-LocalPackageStepFailed -Steps $summary.steps -Name 'Collect'
                    throw "Collector did not create the canonical snapshot: $canonicalPath"
                }
                try { $collectedSnapshot = Get-Content -LiteralPath $canonicalPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
                catch {
                    Set-LocalPackageStepFailed -Steps $summary.steps -Name 'Collect'
                    throw "Collector canonical snapshot is not readable JSON: $canonicalPath"
                }
                $collectedMarketDate = [string](Get-LocalPackagePropertyValue -InputObject $collectedSnapshot -Name 'market_date')
                if ($collectedMarketDate -ne $MarketDate) {
                    Set-LocalPackageStepFailed -Steps $summary.steps -Name 'Collect'
                    throw "Collector snapshot market date '$collectedMarketDate' does not match selected market date '$MarketDate'."
                }
                Invoke-LocalPackageDailyGates -Summary $summary -ProjectRoot $ProjectRoot -SnapshotPath $canonicalPath -MarketDate $MarketDate -SkipEmail:$SkipEmail -StepRunner $StepRunner
            }
            'DailyImport' {
                if ([string]::IsNullOrWhiteSpace($SnapshotPath)) { throw 'DailyImport requires -SnapshotPath pointing to a readable JSON snapshot.' }
                $imported = Copy-LocalPackageImportedSnapshot -ProjectRoot $ProjectRoot -SnapshotPath $SnapshotPath -RequestedMarketDate $MarketDate
                $MarketDate = $imported.MarketDate
                $summary.market_date = $MarketDate
                Invoke-LocalPackageDailyGates -Summary $summary -ProjectRoot $ProjectRoot -SnapshotPath $imported.SnapshotPath -MarketDate $MarketDate -SkipEmail:$SkipEmail -StepRunner $StepRunner
            }
            'Weekly' {
                $weeklyArguments = @{ SkipEmail = [bool]$SkipEmail }
                $recipient = Get-LocalPackageConfiguredRecipient -ProjectRoot $ProjectRoot
                if (-not [string]::IsNullOrWhiteSpace($recipient)) { $weeklyArguments.EmailRecipient = $recipient }
                if (-not [string]::IsNullOrWhiteSpace($MarketDate)) { $weeklyArguments.ReportDate = $MarketDate }
                $run = Invoke-LocalPackageTrackedStep -Name 'WeeklyReport' -ScriptPath (Join-Path $scriptsRoot 'New-BestSellersWeeklyReport.ps1') -Arguments $weeklyArguments -StepRunner $StepRunner -Steps $summary.steps
                Assert-LocalPackageStepSucceeded -Name 'WeeklyReport' -Run $run
            }
            'Health' {
                $run = Invoke-LocalPackageTrackedStep -Name 'Health' -ScriptPath (Join-Path $scriptsRoot 'Test-BestSellersDailyOperationalHealth.ps1') -Arguments @{ MarketDate = $MarketDate } -StepRunner $StepRunner -Steps $summary.steps
                Assert-LocalPackageStepSucceeded -Name 'Health' -Run $run
                if ([string](Get-LocalPackagePropertyValue -InputObject $run.Result -Name 'Status') -ne 'HEALTHY') {
                    Set-LocalPackageStepFailed -Steps $summary.steps -Name 'Health'
                    throw "Step 'Health' did not report HEALTHY."
                }
            }
            'Test' {
                $run = Invoke-LocalPackageTrackedStep -Name 'Test' -ScriptPath (Join-Path $scriptsRoot 'Test.ps1') -Arguments @{} -StepRunner $StepRunner -Steps $summary.steps
                Assert-LocalPackageStepSucceeded -Name 'Test' -Run $run
            }
            default {
                $stableScripts = @{
                    Setup = 'Initialize-LocalPackage.ps1'
                    ConfigureEmail = 'Set-EmailEnvironment.ps1'
                    RegisterTasks = 'Register-LocalPackageScheduledTasks.ps1'
                    ExportHistory = 'Export-LocalPackageHistory.ps1'
                    ImportHistory = 'Import-LocalPackageHistory.ps1'
                }
                $utilityArguments = @{}
                if ($Mode -eq 'ImportHistory' -and -not [string]::IsNullOrWhiteSpace($ArchivePath)) { $utilityArguments.ArchivePath = $ArchivePath }
                if ($Mode -eq 'ExportHistory' -and -not [string]::IsNullOrWhiteSpace($OutputPath)) { $utilityArguments.OutputPath = $OutputPath }
                $run = Invoke-LocalPackageTrackedStep -Name $Mode -ScriptPath (Join-Path $scriptsRoot $stableScripts[$Mode]) -Arguments $utilityArguments -StepRunner $StepRunner -Steps $summary.steps
                Assert-LocalPackageStepSucceeded -Name $Mode -Run $run
            }
        }
        $summary.status = 'SUCCESS'
        $summary.exit_code = 0
    }
    catch {
        $summary.status = 'FAILED'
        $summary.exit_code = 1
        $summary.error = Protect-LocalPackageErrorText -Text ([string]$_.Exception.Message) -EnvironmentValueProvider $EnvironmentValueProvider
    }
    finally {
        if ($null -ne $lock) { Exit-LocalPackageModeLock -Lock $lock }
    }
    return $summary
}

function Start-LocalPackageMenu {
    [CmdletBinding()]
    param(
        [scriptblock]$ReadInput = { Read-Host (ConvertFrom-LocalPackageBase64 '6K+36YCJ5oup5pON5L2cICgwLTEwKTog') },
        [scriptblock]$ReadSnapshotPath = { Read-Host (ConvertFrom-LocalPackageBase64 '6K+36L6T5YWl5q+P5pel5b+r54WnIEpTT04g6Lev5b6EOiA=') },
        [scriptblock]$ReadArchivePath = { Read-Host '请输入历史归档 ZIP 路径' },
        [scriptblock]$ModeInvoker,
        [scriptblock]$WriteMessage = { param([string]$Message) Write-Host $Message }
    )
    if ($null -eq $ModeInvoker) { $ModeInvoker = { param([string]$Mode, [string]$SnapshotPath, [string]$ArchivePath) Invoke-LocalPackageMode -Mode $Mode -SnapshotPath $SnapshotPath -ArchivePath $ArchivePath } }
    $menuLines = @(
        'QW1hem9uIEJlc3QgU2VsbGVycyDmnKzlnLDov5DooYzoj5zljZU=',
        'MS4g5q+P5pel6Ieq5Yqo6YeH6ZuG',
        'Mi4g5a+85YWl5q+P5pel5b+r54Wn',
        'My4g55Sf5oiQ5ZGo5oql',
        'NC4g5Yid5aeL5YyW5pys5Zyw546v5aKD',
        'NS4g6YWN572u6YKu5Lu2',
        'Ni4g5q+P5pel5YGl5bq35qOA5p+l',
        'Ny4g6L+Q6KGM5rWL6K+V',
        'OC4g5rOo5YaM6K6h5YiS5Lu75Yqh',
        'OS4g5a+85Ye65Y6G5Y+y5pWw5o2u',
        'MTAuIOWvvOWFpeWOhuWPsuaVsOaNrg==',
        'MC4g6YCA5Ye6'
    )
    while ($true) {
        & $WriteMessage ''
        foreach ($line in $menuLines) { & $WriteMessage (ConvertFrom-LocalPackageBase64 $line) }
        $choice = [string](& $ReadInput)
        $mode = Get-LocalPackageMenuMode -Choice $choice
        if ([string]::IsNullOrWhiteSpace($mode)) {
            & $WriteMessage ((ConvertFrom-LocalPackageBase64 '5peg5pWI6YCJ5oup77yM6K+36L6T5YWlIDAg5YiwIDEw44CC') + ' Invalid choice.')
            continue
        }
        if ($mode -eq 'Exit') { return }
        $selectedSnapshotPath = $null
        $selectedArchivePath = $null
        if ($mode -eq 'DailyImport') { $selectedSnapshotPath = [string](& $ReadSnapshotPath) }
        if ($mode -eq 'ImportHistory') { $selectedArchivePath = [string](& $ReadArchivePath) }
        $result = & $ModeInvoker $mode $selectedSnapshotPath $selectedArchivePath
        & $WriteMessage ((ConvertFrom-LocalPackageBase64 '5pON5L2c5a6M5oiQ77yM54q25oCBOiA=') + [string]$result.status)
        if ($null -ne $result.PSObject.Properties['error'] -and -not [string]::IsNullOrWhiteSpace([string]$result.error)) {
            & $WriteMessage ([string]$result.error)
        }
    }
}

Export-ModuleMember -Function @(
    'Get-LocalPackageMenuMode',
    'Test-LocalPackageMarketDate',
    'Enter-LocalPackageModeLock',
    'Exit-LocalPackageModeLock',
    'Invoke-LocalPackageMode',
    'Start-LocalPackageMenu'
)
