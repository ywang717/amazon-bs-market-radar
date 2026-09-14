Set-StrictMode -Version Latest

function Get-Sha256Hex {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function ConvertTo-NullableDecimal {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    try {
        return [decimal]::Parse(
            [string]$Value,
            [System.Globalization.NumberStyles]::Number,
            [System.Globalization.CultureInfo]::InvariantCulture
        )
    }
    catch { throw "INVALID_DECIMAL:$Value" }
}

function ConvertTo-NullableInteger {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    $parsed = 0
    if (-not [int]::TryParse([string]$Value, [ref]$parsed)) { throw "INVALID_INTEGER:$Value" }
    return $parsed
}

function ConvertTo-CanonicalObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Item,
        [Parameter(Mandatory = $true)]$Envelope
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $asin = ([string]$Item.asin).Trim().ToUpperInvariant()
    $title = ([string]$Item.title).Trim()
    $url = ([string]$Item.url).Trim()

    if ($asin -notmatch '^[A-Z0-9]{10}$') { $errors.Add('INVALID_ASIN') }
    if ([string]::IsNullOrWhiteSpace($title)) { $errors.Add('MISSING_TITLE') }
    if ([string]::IsNullOrWhiteSpace($url)) { $errors.Add('MISSING_URL') }

    $rank = $null
    try { $rank = ConvertTo-NullableInteger $Item.rank } catch { $errors.Add('INVALID_RANK') }
    if ($null -eq $rank -or $rank -le 0) { $errors.Add('INVALID_RANK') }
    elseif ($rank -gt [int]$Envelope.target_limit) { $errors.Add('RANK_EXCEEDS_TARGET') }

    $price = $null
    try { $price = ConvertTo-NullableDecimal $Item.price } catch { $errors.Add('INVALID_PRICE') }
    if ($null -ne $price -and $price -lt 0) { $errors.Add('INVALID_PRICE') }

    $rating = $null
    try { $rating = ConvertTo-NullableDecimal $Item.rating } catch { $errors.Add('INVALID_RATING') }
    if ($null -ne $rating -and ($rating -lt 0 -or $rating -gt 5)) { $errors.Add('INVALID_RATING') }

    $reviewCount = $null
    try { $reviewCount = ConvertTo-NullableInteger $Item.review_count } catch { $errors.Add('INVALID_REVIEW_COUNT') }
    if ($null -ne $reviewCount -and $reviewCount -lt 0) { $errors.Add('INVALID_REVIEW_COUNT') }

    $marketDate = [datetime]::MinValue
    if (-not [datetime]::TryParseExact(
        [string]$Envelope.market_date,
        'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$marketDate
    )) { $errors.Add('INVALID_MARKET_DATE') }

    if ($errors.Count -gt 0) {
        return [pscustomobject]@{
            IsValid = $false
            Errors = @($errors | Select-Object -Unique)
            Asin = $asin
            Record = $null
        }
    }

    $recordKeyInput = '{0}|{1}|{2}|{3}' -f $Envelope.run_id, $Envelope.source_id, $Envelope.category_slug, $asin
    $record = [ordered]@{
        schema_version = 'canonical-observation-v1'
        record_key = Get-Sha256Hex $recordKeyInput
        run_id = [string]$Envelope.run_id
        source_id = [string]$Envelope.source_id
        marketplace = [string]$Envelope.marketplace
        market_date = $marketDate.ToString('yyyy-MM-dd')
        observed_at = [string]$Envelope.observed_at
        source_type = [string]$Envelope.source_type
        search_term = if ($null -eq $Envelope.search_term) { $null } else { [string]$Envelope.search_term }
        category_slug = [string]$Envelope.category_slug
        accessory_type = if ($null -eq $Envelope.accessory_type) { $null } else { [string]$Envelope.accessory_type }
        rank = $rank
        asin = $asin
        title = $title
        brand_raw = ([string]$Item.brand).Trim()
        model = ([string]$Item.model).Trim()
        url = $url
        price = $price
        currency = [string]$Envelope.currency
        coupon = ([string]$Item.coupon).Trim()
        rating = $rating
        review_count = $reviewCount
        seller_raw = ([string]$Item.seller).Trim()
        fba_status = ([string]$Item.fba_status).Trim().ToUpperInvariant()
        first_available_date = if ($null -eq $Item.first_available_date) { $null } else { [string]$Item.first_available_date }
    }

    return [pscustomobject]@{
        IsValid = $true
        Errors = @()
        Asin = $asin
        Record = [pscustomobject]$record
    }
}

function Invoke-ObservationEnvelopeCollection {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Envelope)

    foreach ($required in @('run_id', 'source_id', 'marketplace', 'market_date', 'observed_at', 'source_type', 'category_slug', 'target_limit', 'currency', 'items')) {
        if ($null -eq $Envelope.$required) { throw "Missing envelope field: $required" }
    }

    $accepted = New-Object System.Collections.Generic.List[object]
    $rejected = New-Object System.Collections.Generic.List[object]
    $seenRecordKeys = @{}
    $duplicateCount = 0
    $position = 0
    foreach ($item in @($Envelope.items)) {
        $position++
        $converted = ConvertTo-CanonicalObservation -Item $item -Envelope $Envelope
        if ($converted.IsValid) {
            if ($seenRecordKeys.ContainsKey([string]$converted.Record.record_key)) {
                $duplicateCount++
                $rejected.Add([pscustomobject]@{
                    position = $position
                    asin = $converted.Asin
                    errors = @('DUPLICATE_RECORD_KEY')
                })
            }
            else {
                $seenRecordKeys[[string]$converted.Record.record_key] = $true
                $accepted.Add($converted.Record)
            }
        }
        else {
            $rejected.Add([pscustomobject]@{
                position = $position
                asin = $converted.Asin
                errors = @($converted.Errors)
            })
        }
    }

    $rawCount = @($Envelope.items).Count
    $acceptedCount = $accepted.Count
    $completeness = if ([int]$Envelope.target_limit -eq 0) { 0 } else { [math]::Round(($acceptedCount / [double]$Envelope.target_limit) * 100, 2) }

    return [pscustomobject]@{
        RunId = [string]$Envelope.run_id
        SourceId = [string]$Envelope.source_id
        Accepted = @($accepted | ForEach-Object { $_ })
        Rejected = @($rejected | ForEach-Object { $_ })
        Stats = [pscustomobject]@{
            RawCount = $rawCount
            AcceptedCount = $acceptedCount
            RejectedCount = $rejected.Count
            DuplicateCount = $duplicateCount
            DuplicatePercent = if ($rawCount -eq 0) { 0 } else { [math]::Round(($duplicateCount / [double]$rawCount) * 100, 2) }
            TargetCount = [int]$Envelope.target_limit
            CompletenessPercent = $completeness
        }
    }
}

function Invoke-FixtureCollection {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Fixture not found: $Path" }
    $envelope = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    return Invoke-ObservationEnvelopeCollection -Envelope $envelope
}

function Add-ObservationStaging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Observations,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $existingKeys = @{}
    if (Test-Path -LiteralPath $Path) {
        foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                try { $existingKeys[(($line | ConvertFrom-Json).record_key)] = $true } catch { throw "Invalid staging JSONL: $Path" }
            }
        }
    }

    $written = 0
    foreach ($observation in $Observations) {
        if (-not $existingKeys.ContainsKey([string]$observation.record_key)) {
            $observation | ConvertTo-Json -Compress -Depth 8 | Add-Content -LiteralPath $Path -Encoding UTF8
            $existingKeys[[string]$observation.record_key] = $true
            $written++
        }
    }
    return $written
}

function Save-RawArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$WorkRoot
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) { throw "Artifact source not found: $SourcePath" }
    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $SourcePath).Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }

    $artifactDirectory = Join-Path (Join-Path $WorkRoot 'raw') $RunId
    if (-not (Test-Path -LiteralPath $artifactDirectory)) {
        New-Item -ItemType Directory -Path $artifactDirectory -Force | Out-Null
    }
    $extension = [System.IO.Path]::GetExtension($SourcePath)
    if ([string]::IsNullOrWhiteSpace($extension)) { $extension = '.bin' }
    $artifactPath = Join-Path $artifactDirectory ($hash + $extension.ToLowerInvariant())
    if (-not (Test-Path -LiteralPath $artifactPath)) {
        [System.IO.File]::WriteAllBytes($artifactPath, $bytes)
    }

    return [pscustomobject]@{
        ContentHash = $hash
        Path = (Resolve-Path -LiteralPath $artifactPath).Path
        ByteCount = $bytes.Length
    }
}

function Save-RawJsonArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$WorkRoot
    )

    $json = $Value | ConvertTo-Json -Depth 20 -Compress
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($json)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }

    $artifactDirectory = Join-Path (Join-Path $WorkRoot 'raw') $RunId
    if (-not (Test-Path -LiteralPath $artifactDirectory)) {
        New-Item -ItemType Directory -Path $artifactDirectory -Force | Out-Null
    }
    $artifactPath = Join-Path $artifactDirectory ($hash + '.json')
    if (-not (Test-Path -LiteralPath $artifactPath)) {
        [System.IO.File]::WriteAllBytes($artifactPath, $bytes)
    }

    return [pscustomobject]@{
        ContentHash = $hash
        Path = (Resolve-Path -LiteralPath $artifactPath).Path
        ByteCount = $bytes.Length
        MediaType = 'application/json'
    }
}

function Test-CollectionQualityGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$CollectionResult,
        [decimal]$MinimumCompletenessPercent = 95,
        [decimal]$MaximumDuplicatePercent = 1
    )

    $reasons = New-Object System.Collections.Generic.List[string]
    if ([decimal]$CollectionResult.Stats.CompletenessPercent -le $MinimumCompletenessPercent) {
        $reasons.Add('COMPLETENESS_NOT_ABOVE_THRESHOLD')
    }
    if ([decimal]$CollectionResult.Stats.DuplicatePercent -ge $MaximumDuplicatePercent) {
        $reasons.Add('DUPLICATE_RATE_NOT_BELOW_THRESHOLD')
    }

    return [pscustomobject]@{
        Passed = ($reasons.Count -eq 0)
        Reasons = @($reasons | ForEach-Object { $_ })
        MinimumCompletenessPercent = $MinimumCompletenessPercent
        MaximumDuplicatePercent = $MaximumDuplicatePercent
    }
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temporaryPath = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $json = $Value | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($temporaryPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Publish-CollectionResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$CollectionResult,
        [Parameter(Mandatory = $true)][object[]]$RawArtifacts,
        [Parameter(Mandatory = $true)][string]$WorkRoot,
        [Parameter(Mandatory = $true)][string]$ParserVersion,
        [decimal]$MinimumCompletenessPercent = 95,
        [decimal]$MaximumDuplicatePercent = 1
    )

    if (-not (Test-Path -LiteralPath $WorkRoot)) {
        New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null
    }
    $WorkRoot = (Resolve-Path -LiteralPath $WorkRoot).Path

    $runId = [string]$CollectionResult.RunId
    $gate = Test-CollectionQualityGate -CollectionResult $CollectionResult -MinimumCompletenessPercent $MinimumCompletenessPercent -MaximumDuplicatePercent $MaximumDuplicatePercent

    $stagingPath = Join-Path (Join-Path $WorkRoot 'staging') 'observations.jsonl'
    $outboxPath = Join-Path (Join-Path $WorkRoot 'outbox') ($runId + '.json')
    $status = if ($gate.Passed) { 'SUCCEEDED' } else { 'QUARANTINED' }
    $written = 0

    if ($gate.Passed) {
        if (@($CollectionResult.Accepted).Count -gt 0) {
            $written = Add-ObservationStaging -Observations $CollectionResult.Accepted -Path $stagingPath
        }
        $databaseBatch = [ordered]@{
            schema_version = 'database-batch-v1'
            run_id = $CollectionResult.RunId
            source_id = $CollectionResult.SourceId
            parser_version = $ParserVersion
            raw_artifacts = @($RawArtifacts)
            stats = $CollectionResult.Stats
            records = @($CollectionResult.Accepted)
        }
        Write-JsonAtomic -Value $databaseBatch -Path $outboxPath
    }

    $manifest = [ordered]@{
        schema_version = 'collection-run-manifest-v1'
        run_id = $CollectionResult.RunId
        source_id = $CollectionResult.SourceId
        status = $status
        parser_version = $ParserVersion
        artifacts = @($RawArtifacts)
        stats = $CollectionResult.Stats
        quality_gate = $gate
        rejected = @($CollectionResult.Rejected)
        staging_path = if ($gate.Passed) { $stagingPath } else { $null }
        outbox_path = if ($gate.Passed) { $outboxPath } else { $null }
    }
    $manifestPath = Join-Path (Join-Path $WorkRoot 'runs') ($runId + '.json')
    Write-JsonAtomic -Value $manifest -Path $manifestPath
    $manifestPath = (Resolve-Path -LiteralPath $manifestPath).Path
    if ($gate.Passed) {
        $stagingPath = (Resolve-Path -LiteralPath $stagingPath).Path
        $outboxPath = (Resolve-Path -LiteralPath $outboxPath).Path
    }

    return [pscustomobject]@{
        RunId = $CollectionResult.RunId
        Status = $status
        QualityGate = $gate
        Stats = $CollectionResult.Stats
        RawArtifactPath = if (@($RawArtifacts).Count -gt 0) { [string]$RawArtifacts[0].Path } else { $null }
        RawArtifactPaths = @($RawArtifacts | ForEach-Object { [string]$_.Path })
        ManifestPath = $manifestPath
        StagingPath = if ($gate.Passed) { $stagingPath } else { $null }
        OutboxPath = if ($gate.Passed) { $outboxPath } else { $null }
        NewlyStaged = $written
    }
}

function Invoke-CollectionPipeline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FixturePath,
        [Parameter(Mandatory = $true)][string]$WorkRoot,
        [decimal]$MinimumCompletenessPercent = 95,
        [decimal]$MaximumDuplicatePercent = 1
    )

    if (-not (Test-Path -LiteralPath $WorkRoot)) {
        New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null
    }
    $WorkRoot = (Resolve-Path -LiteralPath $WorkRoot).Path
    $envelope = Get-Content -LiteralPath $FixturePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $envelope.run_id) { throw 'Missing envelope field: run_id' }
    $artifact = Save-RawArtifact -SourcePath $FixturePath -RunId ([string]$envelope.run_id) -WorkRoot $WorkRoot
    $result = Invoke-FixtureCollection -Path $FixturePath
    return Publish-CollectionResult -CollectionResult $result -RawArtifacts @($artifact) -WorkRoot $WorkRoot `
        -ParserVersion 'fixture-v1' -MinimumCompletenessPercent $MinimumCompletenessPercent `
        -MaximumDuplicatePercent $MaximumDuplicatePercent
}

Export-ModuleMember -Function ConvertTo-CanonicalObservation, Invoke-ObservationEnvelopeCollection, Invoke-FixtureCollection, Add-ObservationStaging, Get-Sha256Hex, Save-RawArtifact, Save-RawJsonArtifact, Test-CollectionQualityGate, Publish-CollectionResult, Invoke-CollectionPipeline
