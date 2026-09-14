$projectRoot = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $projectRoot 'scripts\Invoke-ScheduledDailyAuto.ps1'

Describe 'Scheduled daily auto launcher' {
    BeforeEach {
        $script:fakeTarget = Join-Path $TestDrive 'FakeLocalPackage.ps1'
        $script:callsPath = Join-Path $TestDrive 'calls.txt'
        $script:callsDirectory = Join-Path $TestDrive 'calls'
        New-Item -ItemType Directory -Path $script:callsDirectory -Force | Out-Null
        Get-ChildItem -LiteralPath $script:callsDirectory -File | Remove-Item -Force
        Remove-Item -LiteralPath $script:callsPath -Force -ErrorAction SilentlyContinue
        $source = @'
param([string]$Mode,[string]$MarketDate)
Add-Content -LiteralPath $env:SCHEDULE_TEST_CALLS -Value $Mode
[IO.File]::WriteAllText((Join-Path $env:SCHEDULE_TEST_CALLS_DIRECTORY ("{0}-{1}-{2}.call" -f $Mode,$PID,[guid]::NewGuid().ToString('N'))),'',(New-Object Text.UTF8Encoding($false)))
[Console]::Out.WriteLine((@{mode=$Mode;market_date=$MarketDate} | ConvertTo-Json -Compress))
if ($Mode -eq 'Health') {
    if (-not [string]::IsNullOrWhiteSpace($env:SCHEDULE_TEST_HEALTH_CALLED)) {
        [IO.File]::WriteAllText($env:SCHEDULE_TEST_HEALTH_CALLED,'called',(New-Object Text.UTF8Encoding($false)))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:SCHEDULE_TEST_HEALTHY_MARKER)) {
        if (Test-Path -LiteralPath $env:SCHEDULE_TEST_HEALTHY_MARKER -PathType Leaf) { exit 0 }
        exit 1
    }
    exit ([int]$env:SCHEDULE_TEST_HEALTH_EXIT)
}
if (-not [string]::IsNullOrWhiteSpace($env:SCHEDULE_TEST_PRIMARY_STARTED)) {
    [IO.File]::WriteAllText($env:SCHEDULE_TEST_PRIMARY_STARTED,'started',(New-Object Text.UTF8Encoding($false)))
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $env:SCHEDULE_TEST_PRIMARY_RELEASE -PathType Leaf)) {
        if ([DateTime]::UtcNow -ge $deadline) { exit 9 }
        Start-Sleep -Milliseconds 50
    }
    [IO.File]::WriteAllText($env:SCHEDULE_TEST_HEALTHY_MARKER,'healthy',(New-Object Text.UTF8Encoding($false)))
}
exit ([int]$env:SCHEDULE_TEST_DAILY_EXIT)
'@
        [IO.File]::WriteAllText($script:fakeTarget,$source,(New-Object Text.UTF8Encoding($false)))
        $env:SCHEDULE_TEST_CALLS = $script:callsPath
        $env:SCHEDULE_TEST_CALLS_DIRECTORY = $script:callsDirectory
        $env:SCHEDULE_TEST_HEALTH_EXIT = '0'
        $env:SCHEDULE_TEST_DAILY_EXIT = '0'
    }

    AfterEach {
        Remove-Item Env:SCHEDULE_TEST_CALLS -ErrorAction SilentlyContinue
        Remove-Item Env:SCHEDULE_TEST_CALLS_DIRECTORY -ErrorAction SilentlyContinue
        Remove-Item Env:SCHEDULE_TEST_HEALTH_EXIT -ErrorAction SilentlyContinue
        Remove-Item Env:SCHEDULE_TEST_DAILY_EXIT -ErrorAction SilentlyContinue
        Remove-Item Env:SCHEDULE_TEST_PRIMARY_STARTED -ErrorAction SilentlyContinue
        Remove-Item Env:SCHEDULE_TEST_PRIMARY_RELEASE -ErrorAction SilentlyContinue
        Remove-Item Env:SCHEDULE_TEST_HEALTHY_MARKER -ErrorAction SilentlyContinue
        Remove-Item Env:SCHEDULE_TEST_HEALTH_CALLED -ErrorAction SilentlyContinue
        Remove-Item Env:SCHEDULE_TEST_INITIALIZER_MARKER -ErrorAction SilentlyContinue
    }

    It 'persists a successful primary run and its transcript' {
        & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entry -Mode Primary -MarketDate '2026-08-31' -ProjectRoot $TestDrive -TargetScript $script:fakeTarget | Out-Null
        $exitCode = $LASTEXITCODE

        $exitCode | Should Be 0
        $state = Get-Content -LiteralPath (Join-Path $TestDrive 'var\scheduler\daily-auto\2026-08-31.json') -Raw | ConvertFrom-Json
        $state.Status | Should Be 'SUCCEEDED'
        $state.Outcome | Should Be 'EXECUTED'
        $state.ExitCode | Should Be 0
        Test-Path -LiteralPath $state.LogPath -PathType Leaf | Should Be $true
        (Get-Content -LiteralPath $state.LogPath -Raw) | Should Match 'DailyAuto'
        @(Get-Content -LiteralPath $script:callsPath) | Should Be @('DailyAuto')
    }

    It 'persists a failed primary run and returns the child exit code' {
        $env:SCHEDULE_TEST_DAILY_EXIT = '7'

        & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entry -Mode Primary -MarketDate '2026-08-31' -ProjectRoot $TestDrive -TargetScript $script:fakeTarget | Out-Null
        $exitCode = $LASTEXITCODE

        $exitCode | Should Be 7
        $state = Get-Content -LiteralPath (Join-Path $TestDrive 'var\scheduler\daily-auto\2026-08-31.json') -Raw | ConvertFrom-Json
        $state.Status | Should Be 'FAILED'
        $state.Outcome | Should Be 'EXECUTED'
        $state.ExitCode | Should Be 7
        Test-Path -LiteralPath $state.LogPath -PathType Leaf | Should Be $true
    }

    It 'repairs a missing project Python environment before the production daily target runs' {
        $scriptsRoot = Join-Path $TestDrive 'scripts'
        $venvScripts = Join-Path $TestDrive '.venv\Scripts'
        $initializerMarker = Join-Path $TestDrive 'python-initializer-called.txt'
        New-Item -ItemType Directory -Path $scriptsRoot -Force | Out-Null
        Copy-Item -LiteralPath $script:fakeTarget -Destination (Join-Path $scriptsRoot 'Start-LocalPackage.ps1')
        $initializer = @'
param()
New-Item -ItemType Directory -Path (Join-Path (Split-Path -Parent $PSScriptRoot) '.venv\Scripts') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path (Split-Path -Parent $PSScriptRoot) '.venv\Scripts\python.exe'),'ready',(New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($env:SCHEDULE_TEST_INITIALIZER_MARKER,'called',(New-Object Text.UTF8Encoding($false)))
exit 0
'@
        [IO.File]::WriteAllText((Join-Path $scriptsRoot 'Initialize-PythonEnvironment.ps1'),$initializer,(New-Object Text.UTF8Encoding($false)))
        $env:SCHEDULE_TEST_INITIALIZER_MARKER = $initializerMarker

        & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entry -Mode Primary -MarketDate '2026-08-31' -ProjectRoot $TestDrive | Out-Null
        $exitCode = $LASTEXITCODE

        $exitCode | Should Be 0
        Test-Path -LiteralPath $initializerMarker -PathType Leaf | Should Be $true
        Test-Path -LiteralPath (Join-Path $venvScripts 'python.exe') -PathType Leaf | Should Be $true
        @(Get-Content -LiteralPath $script:callsPath) | Should Be @('DailyAuto')
    }

    It 'skips recovery when the daily health gate is already healthy' {
        & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entry -Mode Recovery -MarketDate '2026-08-31' -ProjectRoot $TestDrive -TargetScript $script:fakeTarget | Out-Null
        $exitCode = $LASTEXITCODE

        $exitCode | Should Be 0
        @(Get-Content -LiteralPath $script:callsPath) | Should Be @('Health')
        $state = Get-Content -LiteralPath (Join-Path $TestDrive 'var\scheduler\daily-auto\2026-08-31.json') -Raw | ConvertFrom-Json
        $state.Status | Should Be 'SUCCEEDED'
        $state.Outcome | Should Be 'SKIPPED_HEALTHY'
    }

    It 'runs DailyAuto once when recovery finds an unhealthy day' {
        $env:SCHEDULE_TEST_HEALTH_EXIT = '1'

        & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entry -Mode Recovery -MarketDate '2026-08-31' -ProjectRoot $TestDrive -TargetScript $script:fakeTarget | Out-Null
        $exitCode = $LASTEXITCODE

        $exitCode | Should Be 0
        @(Get-Content -LiteralPath $script:callsPath) | Should Be @('Health','DailyAuto')
        $state = Get-Content -LiteralPath (Join-Path $TestDrive 'var\scheduler\daily-auto\2026-08-31.json') -Raw | ConvertFrom-Json
        $state.Status | Should Be 'SUCCEEDED'
        $state.Outcome | Should Be 'RECOVERED'
        $state.ExitCode | Should Be 0
    }

    It 'waits for an in-flight primary run and rechecks health before recovery' {
        $env:SCHEDULE_TEST_PRIMARY_STARTED = Join-Path $TestDrive 'transition-primary-started.txt'
        $env:SCHEDULE_TEST_PRIMARY_RELEASE = Join-Path $TestDrive 'transition-primary-release.txt'
        $env:SCHEDULE_TEST_HEALTHY_MARKER = Join-Path $TestDrive 'transition-healthy.txt'
        $env:SCHEDULE_TEST_HEALTH_CALLED = Join-Path $TestDrive 'health-called.txt'
        $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Mode {{0}} -MarketDate 2026-08-31 -ProjectRoot "{1}" -TargetScript "{2}"' -f $entry,$TestDrive,$script:fakeTarget

        $primary = Start-Process -FilePath powershell.exe -ArgumentList ($arguments -f 'Primary') -PassThru -WindowStyle Hidden
        $deadline = [DateTime]::UtcNow.AddSeconds(10)
        while (-not (Test-Path -LiteralPath $env:SCHEDULE_TEST_PRIMARY_STARTED -PathType Leaf) -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 50
        }
        Test-Path -LiteralPath $env:SCHEDULE_TEST_PRIMARY_STARTED -PathType Leaf | Should Be $true

        $recovery = Start-Process -FilePath powershell.exe -ArgumentList ($arguments -f 'Recovery') -PassThru -WindowStyle Hidden
        $healthDeadline = [DateTime]::UtcNow.AddSeconds(2)
        while (-not (Test-Path -LiteralPath $env:SCHEDULE_TEST_HEALTH_CALLED -PathType Leaf) -and [DateTime]::UtcNow -lt $healthDeadline) {
            Start-Sleep -Milliseconds 50
        }
        [IO.File]::WriteAllText($env:SCHEDULE_TEST_PRIMARY_RELEASE,'release',(New-Object Text.UTF8Encoding($false)))
        $primary.WaitForExit(10000) | Should Be $true
        $recovery.WaitForExit(10000) | Should Be $true

        $primary.ExitCode | Should Be 0
        $recovery.ExitCode | Should Be 0
        @(Get-ChildItem -LiteralPath $script:callsDirectory -Filter 'DailyAuto-*.call').Count | Should Be 1
        @(Get-ChildItem -LiteralPath $script:callsDirectory -Filter 'Health-*.call').Count | Should Be 1
        $state = Get-Content -LiteralPath (Join-Path $TestDrive 'var\scheduler\daily-auto\2026-08-31.json') -Raw | ConvertFrom-Json
        $state.Outcome | Should Be 'SKIPPED_HEALTHY'
    }

    It 'does not overwrite canonical state when recovery times out waiting for primary' {
        $env:SCHEDULE_TEST_PRIMARY_STARTED = Join-Path $TestDrive 'timeout-primary-started.txt'
        $env:SCHEDULE_TEST_PRIMARY_RELEASE = Join-Path $TestDrive 'timeout-primary-release.txt'
        $env:SCHEDULE_TEST_HEALTHY_MARKER = Join-Path $TestDrive 'timeout-healthy.txt'
        $launcherProject = Join-Path $TestDrive 'launcher-copy'
        $dataRoot = Join-Path $TestDrive 'timeout-data'
        New-Item -ItemType Directory -Path $dataRoot -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $launcherProject 'scripts') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $launcherProject 'src') -Force | Out-Null
        $timeoutEntry = Join-Path $launcherProject 'scripts\Invoke-ScheduledDailyAuto.ps1'
        $timeoutSource = (Get-Content -LiteralPath $entry -Raw).Replace('[TimeSpan]::FromMinutes(60)','[TimeSpan]::FromMilliseconds(200)')
        [IO.File]::WriteAllText($timeoutEntry,$timeoutSource,(New-Object Text.UTF8Encoding($false)))
        Copy-Item -LiteralPath (Join-Path $projectRoot 'src\ScheduledDailyAutomation.psm1') -Destination (Join-Path $launcherProject 'src\ScheduledDailyAutomation.psm1')
        $baseArguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Mode {{0}} -MarketDate 2026-08-31 -ProjectRoot "{1}" -TargetScript "{2}"' -f $timeoutEntry,$dataRoot,$script:fakeTarget

        $primary = Start-Process -FilePath powershell.exe -ArgumentList ($baseArguments -f 'Primary') -PassThru -WindowStyle Hidden
        $deadline = [DateTime]::UtcNow.AddSeconds(10)
        while (-not (Test-Path -LiteralPath $env:SCHEDULE_TEST_PRIMARY_STARTED -PathType Leaf) -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 50
        }
        Test-Path -LiteralPath $env:SCHEDULE_TEST_PRIMARY_STARTED -PathType Leaf | Should Be $true

        $recovery = Start-Process -FilePath powershell.exe -ArgumentList ($baseArguments -f 'Recovery') -PassThru -WindowStyle Hidden
        $recovery.WaitForExit(10000) | Should Be $true
        $statePath = Join-Path $dataRoot 'var\scheduler\daily-auto\2026-08-31.json'
        $canonicalStateExistedDuringPrimary = Test-Path -LiteralPath $statePath -PathType Leaf

        [IO.File]::WriteAllText($env:SCHEDULE_TEST_PRIMARY_RELEASE,'release',(New-Object Text.UTF8Encoding($false)))
        $primary.WaitForExit(10000) | Should Be $true

        $recovery.ExitCode | Should Be 1
        $canonicalStateExistedDuringPrimary | Should Be $false
        $primary.ExitCode | Should Be 0
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $state.Status | Should Be 'SUCCEEDED'
        $state.Mode | Should Be 'Primary'
    }
}
