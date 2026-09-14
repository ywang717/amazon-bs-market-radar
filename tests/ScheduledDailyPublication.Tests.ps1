$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src\ScheduledDailyAutomation.psm1') -Force

Describe 'Daily processing publication handoff' {
    BeforeEach {
        $script:publishScript = Join-Path $TestDrive 'publish.ps1'
        $script:resultPath = Join-Path $TestDrive 'published-date.txt'
        [IO.File]::WriteAllText($script:publishScript, @'
param([string]$MarketDate,[string]$ResultPath)
[IO.File]::WriteAllText($ResultPath,$MarketDate)
exit 0
'@)
        $global:dailyPublicationTestAction = [pscustomobject]@{
            Execute = (Get-Command powershell.exe).Source
            Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -ResultPath "{1}"' -f $script:publishScript,$script:resultPath
            WorkingDirectory = $TestDrive
        }
        Mock Get-ScheduledTask -ModuleName ScheduledDailyAutomation { [pscustomobject]@{ Actions = @($global:dailyPublicationTestAction) } }
    }
    AfterEach { Remove-Variable dailyPublicationTestAction -Scope Global -ErrorAction SilentlyContinue }

    It 'publishes the processed Pacific date instead of recomputing today' {
        $result = Invoke-ScheduledDailyPublication -MarketDate '2026-09-09'
        $result.Status | Should Be 'SUCCEEDED'
        (Get-Content -LiteralPath $script:resultPath -Raw) | Should Be '2026-09-09'
    }

    It 'does not turn a failed publisher into a successful daily publication' {
        [IO.File]::WriteAllText($script:publishScript, 'param([string]$MarketDate,[string]$ResultPath); exit 7')
        $result = Invoke-ScheduledDailyPublication -MarketDate '2026-09-09'
        $result.Status | Should Be 'FAILED'
        $result.ExitCode | Should Be 7
    }

    It 'reports an absent website configuration without claiming publication' {
        Mock Get-ScheduledTask -ModuleName ScheduledDailyAutomation { $null }
        (Invoke-ScheduledDailyPublication -MarketDate '2026-09-09').Status | Should Be 'NOT_CONFIGURED'
    }
}

Describe 'Daily launcher publication boundary' {
    BeforeEach {
        New-Item -ItemType Directory -Path (Join-Path $TestDrive 'scripts'),(Join-Path $TestDrive 'src'),(Join-Path $TestDrive '.venv\Scripts') -Force | Out-Null
        Copy-Item (Join-Path $projectRoot 'scripts\Invoke-ScheduledDailyAuto.ps1') (Join-Path $TestDrive 'scripts\Invoke-ScheduledDailyAuto.ps1') -Force
        [IO.File]::WriteAllText((Join-Path $TestDrive '.venv\Scripts\python.exe'),'placeholder')
        [IO.File]::WriteAllText((Join-Path $TestDrive 'scripts\Start-LocalPackage.ps1'), @'
param($Mode,$MarketDate)
if ($Mode -eq 'Health') { exit 0 }
$dayRoot = Join-Path (Split-Path -Parent $PSScriptRoot) ('var\amazon-bestsellers\' + $MarketDate)
New-Item -ItemType Directory -Path $dayRoot -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $dayRoot 'price-completeness-diagnostic.json'), ('{"exit":' + $env:DAILY_HANDOFF_COLLECT_EXIT + '}'))
exit ([int]$env:DAILY_HANDOFF_COLLECT_EXIT)
'@)
        [IO.File]::WriteAllText((Join-Path $TestDrive 'scripts\publish.ps1'), @'
param($MarketDate)
[IO.File]::WriteAllText((Join-Path (Split-Path -Parent $PSScriptRoot) 'published.txt'),$MarketDate)
exit ([int]$env:DAILY_HANDOFF_PUBLISH_EXIT)
'@)
        $moduleSource = Get-Content (Join-Path $projectRoot 'src\ScheduledDailyAutomation.psm1') -Raw
        $moduleSource += @'

function Get-ScheduledTask {
    param($TaskName,$ErrorAction)
    [pscustomobject]@{ Actions = @([pscustomobject]@{
        Execute = (Get-Command powershell.exe).Source
        Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\publish.ps1') + '"'
        WorkingDirectory = Split-Path -Parent $PSScriptRoot
    }) }
}
'@
        [IO.File]::WriteAllText((Join-Path $TestDrive 'src\ScheduledDailyAutomation.psm1'),$moduleSource)
        $env:DAILY_HANDOFF_COLLECT_EXIT = '0'
        $env:DAILY_HANDOFF_PUBLISH_EXIT = '0'
        Remove-Item (Join-Path $TestDrive 'published.txt') -ErrorAction SilentlyContinue
    }
    AfterEach {
        Remove-Item Env:DAILY_HANDOFF_COLLECT_EXIT,Env:DAILY_HANDOFF_PUBLISH_EXIT -ErrorAction SilentlyContinue
    }
    It 'publishes after success and on healthy recovery without another crawl' -TestCases @(@{Mode='Primary'},@{Mode='Recovery'}) {
        param($Mode)
        & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $TestDrive 'scripts\Invoke-ScheduledDailyAuto.ps1') -Mode $Mode -MarketDate 2026-09-09 | Out-Null
        $LASTEXITCODE | Should Be 0
        Test-Path (Join-Path $TestDrive 'published.txt') | Should Be $true
        $state = Get-Content (Join-Path $TestDrive 'var\scheduler\daily-auto\2026-09-09.json') -Raw | ConvertFrom-Json
        $state.PublicationStatus | Should Be 'SUCCEEDED'
    }
    It 'propagates publication failure into the canonical daily state' {
        $env:DAILY_HANDOFF_PUBLISH_EXIT = '7'
        & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $TestDrive 'scripts\Invoke-ScheduledDailyAuto.ps1') -Mode Primary -MarketDate 2026-09-09 | Out-Null
        $LASTEXITCODE | Should Be 7
        $state = Get-Content (Join-Path $TestDrive 'var\scheduler\daily-auto\2026-09-09.json') -Raw | ConvertFrom-Json
        $state.Status | Should Be 'FAILED'
        $state.PublicationStatus | Should Be 'FAILED'
    }
    It 'does not publish after collection failure' {
        $env:DAILY_HANDOFF_COLLECT_EXIT = '9'
        & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $TestDrive 'scripts\Invoke-ScheduledDailyAuto.ps1') -Mode Primary -MarketDate 2026-09-09 | Out-Null
        $LASTEXITCODE | Should Be 9
        Test-Path (Join-Path $TestDrive 'published.txt') | Should Be $false
        $state = Get-Content (Join-Path $TestDrive 'var\scheduler\daily-auto\2026-09-09.json') -Raw | ConvertFrom-Json
        (Get-Content (Join-Path $state.DiagnosticsPath 'price-completeness-diagnostic.json') -Raw | ConvertFrom-Json).exit | Should Be 9
        Test-Path ([IO.Path]::ChangeExtension($state.LogPath,'.json')) | Should Be $true
    }
}
