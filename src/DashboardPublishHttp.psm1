Set-StrictMode -Version Latest

function New-DashboardPublishRestParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][uri]$Uri,
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][hashtable]$Headers,
        [Parameter(Mandatory = $true)][string]$ContentType,
        [string]$InFile,
        $Body,
        [switch]$BodyProvided
    )

    $parameters = @{
        Uri = $Uri
        Method = $Method
        Headers = $Headers
        ContentType = $ContentType
    }
    if ($BodyProvided) {
        $json = ($Body | ConvertTo-Json -Depth 16 -Compress)
        $parameters.Body = [Text.Encoding]::UTF8.GetBytes($json)
        if ($ContentType -match '^application/json(?:\s*;|$)' -and $ContentType -notmatch '(?i)charset\s*=') {
            $parameters.ContentType = "$ContentType; charset=utf-8"
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($InFile)) {
        $parameters.InFile = $InFile
    }
    return $parameters
}

function ConvertFrom-DashboardUtf8JsonResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Response
    )

    $json = $null
    if ($null -ne $Response.RawContentStream) {
        $stream = $Response.RawContentStream
        if ($stream.CanSeek) {
            $stream.Position = 0
        }
        $memory = New-Object IO.MemoryStream
        try {
            $stream.CopyTo($memory)
            $json = [Text.Encoding]::UTF8.GetString($memory.ToArray())
        }
        finally {
            $memory.Dispose()
        }
    }
    elseif ($Response.Content -is [byte[]]) {
        $json = [Text.Encoding]::UTF8.GetString([byte[]]$Response.Content)
    }
    else {
        $json = [string]$Response.Content
    }

    return $json | ConvertFrom-Json
}

function Invoke-DashboardPublishCurlRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][uri]$Uri,
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][hashtable]$Headers,
        [Parameter(Mandatory = $true)][string]$ContentType,
        [string]$InFile,
        $Body,
        [switch]$BodyProvided
    )

    $responsePath = [IO.Path]::GetTempFileName()
    $bodyPath = $null
    try {
        $arguments = @(
            '--http1.1', '--silent', '--show-error', '--max-time', '180',
            '--retry', '3', '--retry-all-errors', '--retry-delay', '2',
            '--request', $Method.ToUpperInvariant(), '--output', $responsePath,
            '--write-out', '%{http_code}'
        )
        foreach ($name in @($Headers.Keys | Sort-Object)) {
            $arguments += @('--header', ('{0}: {1}' -f $name, [string]$Headers[$name]))
        }
        if (-not [string]::IsNullOrWhiteSpace($ContentType)) {
            $arguments += @('--header', ('Content-Type: {0}' -f $ContentType))
        }
        if ($BodyProvided) {
            $bodyPath = [IO.Path]::GetTempFileName()
            $json = $Body | ConvertTo-Json -Depth 32 -Compress
            [IO.File]::WriteAllBytes($bodyPath, [Text.Encoding]::UTF8.GetBytes($json))
            $arguments += @('--data-binary', ('@' + $bodyPath))
        }
        elseif (-not [string]::IsNullOrWhiteSpace($InFile)) {
            $arguments += @('--data-binary', ('@' + $InFile))
        }
        $arguments += $Uri.AbsoluteUri

        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $statusOutput = @(& curl.exe @arguments 2>&1)
            $curlExitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        if ($curlExitCode -ne 0) { throw 'Dashboard HTTP transport failed.' }
        $statusText = [string]($statusOutput | Select-Object -Last 1)
        if ($statusText -notmatch '^\d{3}$') { throw 'Dashboard HTTP transport returned an invalid status.' }
        $statusCode = [int]$statusText
        $responseText = [IO.File]::ReadAllText($responsePath, [Text.Encoding]::UTF8)
        if ($statusCode -lt 200 -or $statusCode -ge 300) {
            $message = if ([string]::IsNullOrWhiteSpace($responseText)) { "Dashboard HTTP request failed with status $statusCode." } else { $responseText }
            $exception = New-Object Exception($message)
            $exception | Add-Member -NotePropertyName StatusCode -NotePropertyValue $statusCode
            throw $exception
        }
        if ([string]::IsNullOrWhiteSpace($responseText)) { return [pscustomobject]@{ status = 'ok' } }
        return $responseText | ConvertFrom-Json
    }
    finally {
        Remove-Item -LiteralPath $responsePath -Force -ErrorAction SilentlyContinue
        if ($null -ne $bodyPath) { Remove-Item -LiteralPath $bodyPath -Force -ErrorAction SilentlyContinue }
    }
}

Export-ModuleMember -Function @(
    'New-DashboardPublishRestParameters',
    'ConvertFrom-DashboardUtf8JsonResponse',
    'Invoke-DashboardPublishCurlRest'
)
