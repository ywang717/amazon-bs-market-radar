Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'AmazonIntelligence.psm1')

function Get-NestedValue {
    param(
        $InputObject,
        [Parameter(Mandatory = $true)][string[]]$Path
    )
    $current = $InputObject
    foreach ($segment in $Path) {
        if ($null -eq $current) { return $null }
        $property = $current.PSObject.Properties[$segment]
        if ($null -eq $property) { return $null }
        $current = $property.Value
    }
    return $current
}

function Get-CreatorsApiCredentialsFromEnvironment {
    [CmdletBinding()]
    param()

    $clientId = [Environment]::GetEnvironmentVariable('AMAZON_CREATORS_CLIENT_ID', 'Process')
    if ([string]::IsNullOrWhiteSpace($clientId)) { $clientId = [Environment]::GetEnvironmentVariable('AMAZON_CREATORS_CLIENT_ID', 'User') }
    $clientSecret = [Environment]::GetEnvironmentVariable('AMAZON_CREATORS_CLIENT_SECRET', 'Process')
    if ([string]::IsNullOrWhiteSpace($clientSecret)) { $clientSecret = [Environment]::GetEnvironmentVariable('AMAZON_CREATORS_CLIENT_SECRET', 'User') }
    $partnerTag = [Environment]::GetEnvironmentVariable('AMAZON_CREATORS_PARTNER_TAG', 'Process')
    if ([string]::IsNullOrWhiteSpace($partnerTag)) { $partnerTag = [Environment]::GetEnvironmentVariable('AMAZON_CREATORS_PARTNER_TAG', 'User') }
    if ([string]::IsNullOrWhiteSpace($clientId) -or
        [string]::IsNullOrWhiteSpace($clientSecret) -or
        [string]::IsNullOrWhiteSpace($partnerTag)) {
        throw 'Creators API credentials are missing. Set AMAZON_CREATORS_CLIENT_ID, AMAZON_CREATORS_CLIENT_SECRET and AMAZON_CREATORS_PARTNER_TAG.'
    }

    return [pscustomobject]@{
        ClientId = $clientId
        ClientSecret = $clientSecret
        PartnerTag = $partnerTag
    }
}

function Test-CreatorsApiSourceConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Source)

    $issues = New-Object System.Collections.Generic.List[string]
    $sourceId = [guid]::Empty
    if (-not [guid]::TryParse([string]$Source.source_id, [ref]$sourceId)) { $issues.Add('INVALID_SOURCE_ID') }
    if ([string]$Source.provider -ne 'CREATORS_API') { $issues.Add('INVALID_PROVIDER') }
    if ([string]$Source.source_type -ne 'SEARCH') { $issues.Add('INVALID_SOURCE_TYPE') }
    if ([string]::IsNullOrWhiteSpace([string]$Source.category_slug)) { $issues.Add('MISSING_CATEGORY_SLUG') }
    if ([string]::IsNullOrWhiteSpace([string]$Source.search_term)) { $issues.Add('MISSING_SEARCH_TERM') }
    if (@('GardenAndOutdoor', 'ToolsAndHomeImprovement') -notcontains [string]$Source.search_index) { $issues.Add('UNREVIEWED_SEARCH_INDEX') }
    if ([int]$Source.target_limit -lt 1 -or [int]$Source.target_limit -gt 100) { $issues.Add('INVALID_TARGET_LIMIT') }
    if ([decimal]$Source.max_requests_per_second -le 0 -or [decimal]$Source.max_requests_per_second -gt 10) { $issues.Add('INVALID_REQUEST_RATE') }
    if ([int]$Source.max_attempts -lt 1 -or [int]$Source.max_attempts -gt 5) { $issues.Add('INVALID_MAX_ATTEMPTS') }
    if ($Source.active -eq $true -and [string]$Source.review_status -ne 'APPROVED_SEARCH_ONLY') { $issues.Add('ACTIVE_SOURCE_NOT_APPROVED') }

    return [pscustomobject]@{
        IsValid = ($issues.Count -eq 0)
        Issues = @($issues | ForEach-Object { $_ })
    }
}

function New-CreatorsApiSearchPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Source,
        [Parameter(Mandatory = $true)][string]$PartnerTag
    )

    $validation = Test-CreatorsApiSourceConfiguration -Source $Source
    if (-not $validation.IsValid) { throw ('Invalid Creators API source: ' + ($validation.Issues -join ',')) }
    $targetLimit = [int]$Source.target_limit
    if ($targetLimit -lt 1 -or $targetLimit -gt 100) { throw 'Creators API SearchItems target_limit must be between 1 and 100.' }

    $requests = New-Object System.Collections.Generic.List[object]
    $pageCount = [math]::Ceiling($targetLimit / 10.0)
    for ($page = 1; $page -le $pageCount; $page++) {
        $remaining = $targetLimit - (($page - 1) * 10)
        $itemCount = [math]::Min(10, $remaining)
        $payload = [ordered]@{
            partnerTag = $PartnerTag
            marketplace = 'www.amazon.com'
            keywords = [string]$Source.search_term
            searchIndex = [string]$Source.search_index
            itemCount = $itemCount
            itemPage = $page
            sortBy = 'Relevance'
            currencyOfPreference = 'USD'
            languagesOfPreference = @('en_US')
            resources = @(
                'browseNodeInfo.browseNodes',
                'browseNodeInfo.browseNodes.salesRank',
                'itemInfo.byLineInfo',
                'itemInfo.manufactureInfo',
                'itemInfo.title',
                'offersV2.listings.availability',
                'offersV2.listings.isBuyBoxWinner',
                'offersV2.listings.merchantInfo',
                'offersV2.listings.price'
            )
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$Source.browse_node_id)) {
            $payload.browseNodeId = [string]$Source.browse_node_id
        }
        $requests.Add([pscustomobject]@{
            Page = $page
            ItemCount = $itemCount
            Method = 'POST'
            Uri = 'https://creatorsapi.amazon/catalog/v1/searchItems'
            MarketplaceHeader = 'www.amazon.com'
            Payload = [pscustomobject]$payload
        })
    }
    return @($requests | ForEach-Object { $_ })
}

function Get-CreatorsApiAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Credentials,
        [scriptblock]$Transport
    )

    $request = [pscustomobject]@{
        Method = 'POST'
        Uri = 'https://api.amazon.com/auth/o2/token'
        Headers = @{ 'Content-Type' = 'application/json' }
        Body = [pscustomobject]@{
            grant_type = 'client_credentials'
            client_id = [string]$Credentials.ClientId
            client_secret = [string]$Credentials.ClientSecret
            scope = 'creatorsapi::default'
        }
    }
    if ($null -eq $Transport) {
        $response = Invoke-RestMethod -Method Post -Uri $request.Uri -ContentType 'application/json' -Body ($request.Body | ConvertTo-Json -Compress)
    }
    else { $response = & $Transport $request }

    if ([string]::IsNullOrWhiteSpace([string]$response.access_token)) { throw 'Creators API token response did not contain access_token.' }
    return [pscustomobject]@{
        AccessToken = [string]$response.access_token
        ExpiresIn = [int]$response.expires_in
        TokenType = [string]$response.token_type
    }
}

function Invoke-CreatorsApiRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Request,
        [Parameter(Mandatory = $true)][string]$AccessToken,
        [scriptblock]$Transport,
        [int]$MaxAttempts = 3,
        [int]$BaseDelayMilliseconds = 1000,
        [scriptblock]$SleepAction
    )

    $wireRequest = [pscustomobject]@{
        Method = [string]$Request.Method
        Uri = [string]$Request.Uri
        Headers = @{
            Authorization = 'Bearer ' + $AccessToken
            'Content-Type' = 'application/json'
            'x-marketplace' = [string]$Request.MarketplaceHeader
        }
        Body = $Request.Payload
    }
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            if ($null -eq $Transport) {
                return Invoke-RestMethod -Method Post -Uri $wireRequest.Uri -Headers $wireRequest.Headers -ContentType 'application/json' -Body ($wireRequest.Body | ConvertTo-Json -Compress -Depth 10)
            }
            return & $Transport $wireRequest
        }
        catch {
            $statusCode = $null
            if ($_.Exception.Data.Contains('StatusCode')) { $statusCode = [int]$_.Exception.Data['StatusCode'] }
            elseif ($null -ne $_.Exception.Response -and $null -ne $_.Exception.Response.StatusCode) { $statusCode = [int]$_.Exception.Response.StatusCode }
            $retryable = ($null -eq $statusCode -or $statusCode -eq 429 -or $statusCode -ge 500)
            if (-not $retryable -or $attempt -ge $MaxAttempts) { throw }
            $delay = [int]($BaseDelayMilliseconds * [math]::Pow(2, $attempt - 1))
            if ($null -eq $SleepAction) { Start-Sleep -Milliseconds $delay }
            else { & $SleepAction $delay }
        }
    }
}

function ConvertFrom-CreatorsApiSearchResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Response,
        [Parameter(Mandatory = $true)]$Source,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$MarketDate,
        [Parameter(Mandatory = $true)][string]$ObservedAt,
        [Parameter(Mandatory = $true)][int]$ItemPage,
        [int]$ExpectedCount
    )

    $items = New-Object System.Collections.Generic.List[object]
    $responseItems = @(Get-NestedValue -InputObject $Response -Path @('searchResult', 'items'))
    $position = 0
    foreach ($apiItem in $responseItems) {
        if ($null -eq $apiItem) { continue }
        $position++
        $listings = @(Get-NestedValue -InputObject $apiItem -Path @('offersV2', 'listings'))
        $listing = $listings | Where-Object { (Get-NestedValue $_ @('isBuyBoxWinner')) -eq $true } | Select-Object -First 1
        if ($null -eq $listing) { $listing = $listings | Select-Object -First 1 }

        $items.Add([pscustomobject]@{
            rank = (($ItemPage - 1) * 10) + $position
            asin = [string](Get-NestedValue $apiItem @('asin'))
            title = [string](Get-NestedValue $apiItem @('itemInfo', 'title', 'displayValue'))
            brand = [string](Get-NestedValue $apiItem @('itemInfo', 'byLineInfo', 'brand', 'displayValue'))
            model = [string](Get-NestedValue $apiItem @('itemInfo', 'manufactureInfo', 'model', 'displayValue'))
            url = [string](Get-NestedValue $apiItem @('detailPageURL'))
            price = Get-NestedValue $listing @('price', 'money', 'amount')
            coupon = ''
            rating = $null
            review_count = $null
            seller = [string](Get-NestedValue $listing @('merchantInfo', 'name'))
            fba_status = 'UNKNOWN'
            first_available_date = $null
        })
    }

    $targetCount = if ($ExpectedCount -gt 0) { $ExpectedCount } else { [int]$Source.target_limit }
    $envelope = [pscustomobject]@{
        run_id = $RunId
        source_id = [string]$Source.source_id
        marketplace = 'AMAZON_US'
        market_date = $MarketDate
        observed_at = $ObservedAt
        source_type = 'SEARCH'
        search_term = [string]$Source.search_term
        category_slug = [string]$Source.category_slug
        accessory_type = if ($null -eq $Source.accessory_type) { $null } else { [string]$Source.accessory_type }
        target_limit = $targetCount
        currency = 'USD'
        items = @($items | ForEach-Object { $_ })
    }
    return Invoke-ObservationEnvelopeCollection -Envelope $envelope
}

function Merge-CreatorsApiPageResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$PageResults,
        [Parameter(Mandatory = $true)]$Source,
        [Parameter(Mandatory = $true)][string]$RunId
    )

    $accepted = New-Object System.Collections.Generic.List[object]
    $rejected = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $rawCount = 0
    $duplicateCount = 0
    foreach ($pageResult in $PageResults) {
        $rawCount += [int]$pageResult.Stats.RawCount
        foreach ($record in @($pageResult.Accepted)) {
            if ($seen.ContainsKey([string]$record.record_key)) {
                $duplicateCount++
                $rejected.Add([pscustomobject]@{
                    position = [int]$record.rank
                    asin = [string]$record.asin
                    errors = @('DUPLICATE_RECORD_KEY_ACROSS_PAGES')
                })
            }
            else {
                $seen[[string]$record.record_key] = $true
                $accepted.Add($record)
            }
        }
        foreach ($rejection in @($pageResult.Rejected)) { $rejected.Add($rejection) }
    }

    $target = [int]$Source.target_limit
    $acceptedCount = $accepted.Count
    return [pscustomobject]@{
        RunId = $RunId
        SourceId = [string]$Source.source_id
        Accepted = @($accepted | ForEach-Object { $_ })
        Rejected = @($rejected | ForEach-Object { $_ })
        Stats = [pscustomobject]@{
            RawCount = $rawCount
            AcceptedCount = $acceptedCount
            RejectedCount = $rejected.Count
            DuplicateCount = $duplicateCount
            DuplicatePercent = if ($rawCount -eq 0) { 0 } else { [math]::Round(($duplicateCount / [double]$rawCount) * 100, 2) }
            TargetCount = $target
            CompletenessPercent = if ($target -eq 0) { 0 } else { [math]::Round(($acceptedCount / [double]$target) * 100, 2) }
        }
    }
}

function Invoke-CreatorsApiSearchRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Source,
        [Parameter(Mandatory = $true)][string]$MarketDate,
        [Parameter(Mandatory = $true)][string]$WorkRoot,
        $Credentials,
        [string]$RunId = ([guid]::NewGuid().ToString()),
        [string]$ObservedAt = ([datetime]::UtcNow.ToString('o')),
        [scriptblock]$TokenTransport,
        [scriptblock]$ApiTransport,
        [scriptblock]$SleepAction
    )

    if ($Source.active -ne $true) { throw 'Source is inactive. Explicitly activate a reviewed local source configuration before running.' }
    $validation = Test-CreatorsApiSourceConfiguration -Source $Source
    if (-not $validation.IsValid) { throw ('Invalid Creators API source: ' + ($validation.Issues -join ',')) }
    if ($null -eq $Credentials) { $Credentials = Get-CreatorsApiCredentialsFromEnvironment }
    if (-not (Test-Path -LiteralPath $WorkRoot)) { New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null }
    $WorkRoot = (Resolve-Path -LiteralPath $WorkRoot).Path

    $token = Get-CreatorsApiAccessToken -Credentials $Credentials -Transport $TokenTransport
    $plan = @(New-CreatorsApiSearchPlan -Source $Source -PartnerTag ([string]$Credentials.PartnerTag))
    $artifacts = New-Object System.Collections.Generic.List[object]
    $pageResults = New-Object System.Collections.Generic.List[object]

    $requestNumber = 0
    $requestDelay = [int][math]::Ceiling(1000 / [decimal]$Source.max_requests_per_second)
    foreach ($request in $plan) {
        $requestNumber++
        if ($requestNumber -gt 1) {
            if ($null -eq $SleepAction) { Start-Sleep -Milliseconds $requestDelay }
            else { & $SleepAction $requestDelay }
        }
        $response = Invoke-CreatorsApiRequest -Request $request -AccessToken $token.AccessToken -Transport $ApiTransport `
            -MaxAttempts ([int]$Source.max_attempts) -SleepAction $SleepAction
        $artifacts.Add((Save-RawJsonArtifact -Value $response -RunId $RunId -WorkRoot $WorkRoot))
        $pageResults.Add((ConvertFrom-CreatorsApiSearchResponse -Response $response -Source $Source `
            -RunId $RunId -MarketDate $MarketDate -ObservedAt $ObservedAt -ItemPage $request.Page `
            -ExpectedCount ([int]$Source.target_limit)))
    }

    $merged = Merge-CreatorsApiPageResults -PageResults @($pageResults | ForEach-Object { $_ }) -Source $Source -RunId $RunId
    $published = Publish-CollectionResult -CollectionResult $merged `
        -RawArtifacts @($artifacts | ForEach-Object { $_ }) -WorkRoot $WorkRoot -ParserVersion 'creators-api-search-v1'
    $published | Add-Member -NotePropertyName PageCount -NotePropertyValue $plan.Count
    return $published
}

Export-ModuleMember -Function Get-CreatorsApiCredentialsFromEnvironment, Test-CreatorsApiSourceConfiguration, New-CreatorsApiSearchPlan, Get-CreatorsApiAccessToken, Invoke-CreatorsApiRequest, ConvertFrom-CreatorsApiSearchResponse, Merge-CreatorsApiPageResults, Invoke-CreatorsApiSearchRun
