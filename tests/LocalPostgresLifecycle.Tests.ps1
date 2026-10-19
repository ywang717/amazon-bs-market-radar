$projectRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $projectRoot 'src\LocalPostgresLifecycle.psm1'

Describe 'Local PostgreSQL startup decisions' {
    BeforeAll {
        Import-Module $modulePath -Force
    }

    It 'restarts a running but unready server instead of attempting a second start' {
        $action = Get-LocalPostgresStartupAction -IsReady:$false -ServerRunning:$true

        $action | Should Be 'RESTART'
    }

    It 'starts a stopped server' {
        $action = Get-LocalPostgresStartupAction -IsReady:$false -ServerRunning:$false

        $action | Should Be 'START'
    }

    It 'does not disturb a ready server' {
        $action = Get-LocalPostgresStartupAction -IsReady:$true -ServerRunning:$true

        $action | Should Be 'ALREADY_READY'
    }
}

Describe 'Local PostgreSQL log path' {
    BeforeAll {
        Import-Module $modulePath -Force
    }

    It 'places the server log beside the PostgreSQL data instead of under the project path' {
        $dataRoot = Join-Path $TestDrive 'amazon-bs-postgres-data'
        $logPath = Get-LocalPostgresLogPath -DataRoot $dataRoot

        $logPath | Should Be (Join-Path $dataRoot 'postgres-server.log')
    }
}
