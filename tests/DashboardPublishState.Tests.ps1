$projectRoot = Split-Path -Parent $PSScriptRoot
$stateModulePath = Join-Path $projectRoot 'src\DashboardPublishState.psm1'
$primaryScript = Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1'
$recoveryScript = Join-Path $projectRoot 'scripts\Invoke-DashboardPublishRecovery.ps1'

Describe 'Dashboard publish state' {
    BeforeAll {
        Import-Module $stateModulePath -Force
    }

    It 'writes PUBLISHED state atomically after primary success' {
        $path = Write-DashboardPublishState -Root $TestDrive -MarketDate '2026-08-23' -Status PUBLISHED -ObservationCount 90 -ReportsUploaded 6

        $state = Read-DashboardPublishState -Root $TestDrive -MarketDate '2026-08-23'
        $state.Status | Should Be 'PUBLISHED'
        $state.MarketDate | Should Be '2026-08-23'
        $state.ObservationCount | Should Be 90
        $state.ReportsUploaded | Should Be 6
        $state.CompletedAt | Should Not BeNullOrEmpty
        $state.ErrorMessage | Should Be $null
        Test-Path ($path + '.tmp') | Should Be $false
    }

    It 'redacts credential-like values before persisting a failed state' {
        Write-DashboardPublishState -Root $TestDrive -MarketDate '2026-08-23' -Status FAILED -ObservationCount 0 -ReportsUploaded 0 -ErrorMessage 'Authorization: Bearer private-token password=database-secret postgresql://user:uri-secret@localhost/db' | Out-Null

        $state = Read-DashboardPublishState -Root $TestDrive -MarketDate '2026-08-23'
        $state.Status | Should Be 'FAILED'
        $state.ErrorMessage | Should Not Match 'private-token|database-secret|uri-secret'
        $state.ErrorMessage | Should Match '\[REDACTED\]'
    }

    It 'writes PUBLISHED state only after the injected verified publication succeeds' {
        & $primaryScript -DashboardUrl 'https://dashboard.example/' -MarketDate '2026-08-23' -ProjectRoot $TestDrive -PublishOperation {
            [pscustomobject]@{
                Status = 'PUBLISHED'
                MarketDate = '2026-08-23'
                RemoteStatus = 'imported'
                ObservationCount = 90
                ReportsUploaded = 6
                ReportsStatus = 'UPLOADED'
            }
        } | Out-Null

        (Read-DashboardPublishState -Root $TestDrive -MarketDate '2026-08-23').Status | Should Be 'PUBLISHED'
    }

    It 'writes a sanitized FAILED state before rethrowing a primary publication error' {
        $caught = $null
        try { & $primaryScript -DashboardUrl 'https://dashboard.example/' -MarketDate '2026-08-23' -ProjectRoot $TestDrive -PublishOperation { throw 'Bearer private-token' } }
        catch { $caught = $_ }
        ($null -ne $caught) | Should Be $true
        $caught.Exception.Message | Should Match 'Bearer private-token'

        $state = Read-DashboardPublishState -Root $TestDrive -MarketDate '2026-08-23'
        $state.Status | Should Be 'FAILED'
        $state.ErrorMessage | Should Not Match 'private-token'
    }
}

Describe 'Dashboard publish recovery' {
    BeforeAll {
        Import-Module $stateModulePath -Force
    }

    It 'skips 09:15 recovery after a published primary state' {
        Write-DashboardPublishState -Root $TestDrive -MarketDate '2026-08-23' -Status PUBLISHED -ObservationCount 90 -ReportsUploaded 6 | Out-Null

        (& $recoveryScript -MarketDate '2026-08-23' -ProjectRoot $TestDrive -Publisher { throw 'must not run' } | ConvertFrom-Json).Status | Should Be 'SKIPPED_ALREADY_PUBLISHED'
    }

    It 'calls the publisher once when the primary state is failed' {
        Write-DashboardPublishState -Root $TestDrive -MarketDate '2026-08-23' -Status FAILED -ObservationCount 0 -ReportsUploaded 0 -ErrorMessage 'publish failed' | Out-Null
        $callCounter = [pscustomobject]@{ Count = 0 }

        & $recoveryScript -MarketDate '2026-08-23' -ProjectRoot $TestDrive -Publisher {
            $callCounter.Count++
            [pscustomobject]@{ Status = 'PUBLISHED' } | ConvertTo-Json -Compress
        } | Out-Null

        $callCounter.Count | Should Be 1
    }

    It 'does not treat an incomplete PUBLISHED record as a successful primary publication' {
        $stateDirectory = Join-Path $TestDrive 'var\scheduler\dashboard-publish'
        New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
        @{ Status = 'PUBLISHED'; MarketDate = '2026-08-23' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stateDirectory '2026-08-23.json')
        $callCounter = [pscustomobject]@{ Count = 0 }

        & $recoveryScript -MarketDate '2026-08-23' -ProjectRoot $TestDrive -Publisher {
            $callCounter.Count++
            [pscustomobject]@{ Status = 'PUBLISHED' } | ConvertTo-Json -Compress
        } | Out-Null

        $callCounter.Count | Should Be 1
    }

    It 'does not treat a malformed completed time as a successful primary publication' {
        $stateDirectory = Join-Path $TestDrive 'var\scheduler\dashboard-publish'
        New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
        @{ Status = 'PUBLISHED'; MarketDate = '2026-08-23'; CompletedAt = 'not-a-time'; ObservationCount = 90; ReportsUploaded = 6; ErrorMessage = $null } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stateDirectory '2026-08-23.json')
        $callCounter = [pscustomobject]@{ Count = 0 }

        & $recoveryScript -MarketDate '2026-08-23' -ProjectRoot $TestDrive -Publisher {
            $callCounter.Count++
            [pscustomobject]@{ Status = 'PUBLISHED' } | ConvertTo-Json -Compress
        } | Out-Null

        $callCounter.Count | Should Be 1
    }

    It 'does not skip recovery for non-numeric published counters' {
        $stateDirectory = Join-Path $TestDrive 'var\scheduler\dashboard-publish'
        New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
        @{ Status = 'PUBLISHED'; MarketDate = '2026-08-23'; CompletedAt = '2026-08-23T09:00:00.0000000+00:00'; ObservationCount = 'oops'; ReportsUploaded = 'still-bad'; ErrorMessage = $null } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stateDirectory '2026-08-23.json')
        $callCounter = [pscustomobject]@{ Count = 0 }

        $recoveryResult = & $recoveryScript -MarketDate '2026-08-23' -ProjectRoot $TestDrive -Publisher {
            $callCounter.Count++
            [pscustomobject]@{ Status = 'PUBLISHED' } | ConvertTo-Json -Compress
        } | ConvertFrom-Json

        $recoveryResult.Status | Should Not Be 'SKIPPED_ALREADY_PUBLISHED'
        $callCounter.Count | Should Be 1
    }
}
