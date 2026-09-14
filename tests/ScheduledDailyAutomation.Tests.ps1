$projectRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $projectRoot 'src\ScheduledDailyAutomation.psm1'

Describe 'Scheduled daily automation state persistence' {
    It 'atomically replaces an existing state file without leaving staging files' {
        Test-Path -LiteralPath $modulePath -PathType Leaf | Should Be $true
        Import-Module $modulePath -Force

        $stateDirectory = Join-Path $TestDrive 'state'
        New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
        $statePath = Join-Path $stateDirectory '2026-08-31.json'
        [IO.File]::WriteAllText($statePath,'{"Outcome":"OLD"}',(New-Object Text.UTF8Encoding($false)))

        Write-ScheduledDailyStateFile -Path $statePath -State ([ordered]@{ Outcome = 'NEW'; ExitCode = 0 })

        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $state.Outcome | Should Be 'NEW'
        $state.ExitCode | Should Be 0
        @(Get-ChildItem -LiteralPath $stateDirectory -File | Where-Object Name -Match '\.(tmp|bak)-').Count | Should Be 0
    }
}
