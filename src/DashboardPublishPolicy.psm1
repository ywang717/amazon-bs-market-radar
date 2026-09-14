Set-StrictMode -Version Latest

function New-DashboardPublishResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$MarketDate,
        [Parameter(Mandatory = $true)][string]$RemoteStatus,
        [Parameter(Mandatory = $true)][int]$ObservationCount,
        [Parameter(Mandatory = $true)][int]$ReportsUploaded,
        [Parameter(Mandatory = $true)][bool]$ReportUploadFailed
    )

    [pscustomobject]@{
        Status = 'PUBLISHED'
        MarketDate = $MarketDate
        RemoteStatus = $RemoteStatus
        ObservationCount = $ObservationCount
        ReportsStatus = if ($ReportUploadFailed) { 'FAILED' } else { 'UPLOADED' }
        ReportsUploaded = $ReportsUploaded
    }
}

Export-ModuleMember -Function 'New-DashboardPublishResult'
