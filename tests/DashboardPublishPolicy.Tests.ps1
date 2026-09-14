$projectRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $projectRoot 'src\DashboardPublishPolicy.psm1'

Describe 'Dashboard publish result policy' {
    BeforeAll {
        Import-Module $modulePath -Force
    }

    It 'keeps the data publication successful when only report upload fails' {
        $result = New-DashboardPublishResult -MarketDate '2026-08-23' -RemoteStatus 'imported' -ObservationCount 90 -ReportsUploaded 0 -ReportUploadFailed:$true

        $result.Status | Should Be 'PUBLISHED'
        $result.ReportsStatus | Should Be 'FAILED'
        $result.MarketDate | Should Be '2026-08-23'
        $result.ObservationCount | Should Be 90
    }

    It 'marks reports uploaded when every selected report completes' {
        $result = New-DashboardPublishResult -MarketDate '2026-08-23' -RemoteStatus 'imported' -ObservationCount 90 -ReportsUploaded 3 -ReportUploadFailed:$false

        $result.Status | Should Be 'PUBLISHED'
        $result.ReportsStatus | Should Be 'UPLOADED'
        $result.ReportsUploaded | Should Be 3
    }
}
