param(
    [Parameter(Mandatory = $true)][string]$FixturePath,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $PSScriptRoot '..\var\staging\observations.jsonl' }
Import-Module (Join-Path $PSScriptRoot '..\src\AmazonIntelligence.psm1') -Force

$result = Invoke-FixtureCollection -Path $FixturePath
$written = Add-ObservationStaging -Observations $result.Accepted -Path $OutputPath

[pscustomobject]@{
    RunId = $result.RunId
    RawCount = $result.Stats.RawCount
    AcceptedCount = $result.Stats.AcceptedCount
    RejectedCount = $result.Stats.RejectedCount
    CompletenessPercent = $result.Stats.CompletenessPercent
    NewlyWritten = $written
    OutputPath = (Resolve-Path -LiteralPath $OutputPath).Path
    Rejections = $result.Rejected
} | ConvertTo-Json -Depth 8
