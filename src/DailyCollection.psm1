Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'CreatorsApiAdapter.psm1')

function Protect-CollectionErrorMessage {
    param(
        [string]$Message,
        $Credentials
    )
    $safe = [string]$Message
    $safe = [regex]::Replace($safe, '(?i)Bearer\s+[A-Za-z0-9._|+\-/=]+', 'Bearer [REDACTED]')
    if ($null -ne $Credentials) {
        foreach ($property in @('ClientId', 'ClientSecret', 'PartnerTag')) {
            $valueProperty = $Credentials.PSObject.Properties[$property]
            if ($null -ne $valueProperty -and -not [string]::IsNullOrWhiteSpace([string]$valueProperty.Value)) {
                $safe = $safe.Replace([string]$valueProperty.Value, '[REDACTED]')
            }
        }
    }
    return $safe
}

function Write-DailyManifestAtomic {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $json = $Value | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($temporary, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Invoke-DailySearchCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$MarketDate,
        [Parameter(Mandatory = $true)][string]$WorkRoot,
        $Credentials,
        [scriptblock]$SourceRunner
    )

    $parsedDate = [datetime]::MinValue
    if (-not [datetime]::TryParseExact(
        $MarketDate, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None, [ref]$parsedDate
    )) { throw 'MarketDate must use YYYY-MM-DD.' }

    $activeSources = @($Config.sources | Where-Object { $_.active -eq $true })
    if ($activeSources.Count -eq 0) { throw 'No active Search sources are configured.' }
    if ($activeSources.Count -gt 6) { throw 'Active source count exceeds the project maximum of 6.' }

    $seenSourceIds = @{}
    foreach ($source in $activeSources) {
        $validation = Test-CreatorsApiSourceConfiguration -Source $source
        if (-not $validation.IsValid) { throw ('Invalid source ' + [string]$source.source_id + ': ' + ($validation.Issues -join ',')) }
        if ($seenSourceIds.ContainsKey([string]$source.source_id)) { throw ('Duplicate source_id: ' + [string]$source.source_id) }
        $seenSourceIds[[string]$source.source_id] = $true
    }

    if ($null -eq $SourceRunner -and $null -eq $Credentials) {
        $Credentials = Get-CreatorsApiCredentialsFromEnvironment
    }
    if (-not (Test-Path -LiteralPath $WorkRoot)) { New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null }
    $WorkRoot = (Resolve-Path -LiteralPath $WorkRoot).Path
    $dailyRoot = Join-Path (Join-Path $WorkRoot 'daily') $MarketDate
    if (-not (Test-Path -LiteralPath $dailyRoot)) { New-Item -ItemType Directory -Path $dailyRoot -Force | Out-Null }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($source in $activeSources) {
        $sourceRoot = Join-Path $dailyRoot ([string]$source.category_slug)
        try {
            if ($null -eq $SourceRunner) {
                $run = Invoke-CreatorsApiSearchRun -Source $source -MarketDate $MarketDate -WorkRoot $sourceRoot -Credentials $Credentials
            }
            else { $run = & $SourceRunner $source $MarketDate $sourceRoot $Credentials }

            $results.Add([pscustomobject]@{
                source_id = [string]$source.source_id
                category_slug = [string]$source.category_slug
                status = [string]$run.Status
                run_id = [string]$run.RunId
                accepted_count = [int]$run.Stats.AcceptedCount
                rejected_count = [int]$run.Stats.RejectedCount
                completeness_percent = [decimal]$run.Stats.CompletenessPercent
                manifest_path = [string]$run.ManifestPath
                outbox_path = [string]$run.OutboxPath
                error_code = $null
                error_message = $null
            })
        }
        catch {
            $results.Add([pscustomobject]@{
                source_id = [string]$source.source_id
                category_slug = [string]$source.category_slug
                status = 'FAILED'
                run_id = $null
                accepted_count = 0
                rejected_count = 0
                completeness_percent = 0
                manifest_path = $null
                outbox_path = $null
                error_code = 'SOURCE_RUN_FAILED'
                error_message = Protect-CollectionErrorMessage -Message $_.Exception.Message -Credentials $Credentials
            })
        }
    }

    $resultArray = @($results | ForEach-Object { $_ })
    $succeeded = @($resultArray | Where-Object { $_.status -eq 'SUCCEEDED' }).Count
    $failed = @($resultArray | Where-Object { $_.status -ne 'SUCCEEDED' }).Count
    $dailyStatus = if ($succeeded -eq $activeSources.Count) { 'SUCCEEDED' } elseif ($succeeded -gt 0) { 'PARTIAL' } else { 'FAILED' }
    $summary = [ordered]@{
        schema_version = 'daily-collection-summary-v1'
        market_date = $MarketDate
        status = $dailyStatus
        execution_mode = 'SEQUENTIAL_SHARED_RATE_LIMIT'
        source_count = $activeSources.Count
        succeeded_count = $succeeded
        failed_count = $failed
        results = $resultArray
    }
    $manifestPath = Join-Path $dailyRoot 'daily-summary.json'
    Write-DailyManifestAtomic -Value $summary -Path $manifestPath

    return [pscustomobject]@{
        MarketDate = $MarketDate
        Status = $dailyStatus
        SourceCount = $activeSources.Count
        SucceededCount = $succeeded
        FailedCount = $failed
        Results = $resultArray
        ManifestPath = (Resolve-Path -LiteralPath $manifestPath).Path
    }
}

Export-ModuleMember -Function Invoke-DailySearchCollection

