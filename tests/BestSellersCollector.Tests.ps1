$projectRoot = Split-Path -Parent $PSScriptRoot

Describe 'Visible browser Best Sellers collector wrapper' {
    It 'derives the project root when launched without a ProjectRoot argument' {
        $wrapper = Join-Path $projectRoot 'scripts\Collect-BestSellers.ps1'
        $fixture = Join-Path $projectRoot 'tests\python\fixtures\collector-run-partial.json'
        $outputRoot = Join-Path $TestDrive 'default-root-snapshots'
        $commandOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $wrapper -FixtureInput $fixture -OutputRoot $outputRoot -MarketDate '2026-08-11'
        $exitCode = $LASTEXITCODE
        $result = $commandOutput | ConvertFrom-Json

        $canonicalPath = Join-Path $outputRoot '2026-08-11\amazon-bestsellers.json'
        $exitCode | Should Be 21
        $result.Status | Should Be 'INCOMPLETE'
        $result.CompletenessStatus | Should Be 'FAILED'
        $result.TotalObservations | Should Be 3
        $result.SnapshotPath | Should BeNullOrEmpty
        Test-Path -LiteralPath $canonicalPath | Should Be $false
    }

    It 'uses the project virtual environment and propagates machine-readable incomplete output' {
        $wrapper = Join-Path $projectRoot 'scripts\Collect-BestSellers.ps1'
        $fixture = Join-Path $projectRoot 'tests\python\fixtures\collector-run-partial.json'
        $unicodeLeaf = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5Li05pe25qyh5rWL6K+V5b+r54Wn'))
        $outputRoot = Join-Path $TestDrive $unicodeLeaf
        $commandOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $wrapper -ProjectRoot $projectRoot -FixtureInput $fixture -OutputRoot $outputRoot -MarketDate '2026-08-11'
        $exitCode = $LASTEXITCODE
        $result = $commandOutput | ConvertFrom-Json

        $canonicalPath = Join-Path $outputRoot '2026-08-11\amazon-bestsellers.json'
        $exitCode | Should Be 21
        $result.Status | Should Be 'INCOMPLETE'
        $result.CompletenessStatus | Should Be 'FAILED'
        $result.TotalObservations | Should Be 3
        $result.SnapshotPath | Should BeNullOrEmpty
        Test-Path -LiteralPath $canonicalPath | Should Be $false
        Test-Path -LiteralPath $result.StatusPath | Should Be $true
    }

    It 'keeps the Playwright Chromium fallback under the project root' {
        $sandboxRoot = Join-Path $TestDrive 'portable-browser-project'
        $sandboxVenv = Join-Path $sandboxRoot '.venv'
        $sandboxPythonRoot = Join-Path $sandboxVenv 'Scripts'
        $sandboxCollectorRoot = Join-Path $sandboxRoot 'scripts\python'
        New-Item -ItemType Directory -Path $sandboxPythonRoot, $sandboxCollectorRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $projectRoot '.venv\Scripts\python.exe') -Destination (Join-Path $sandboxPythonRoot 'python.exe')
        Copy-Item -LiteralPath (Join-Path $projectRoot '.venv\pyvenv.cfg') -Destination (Join-Path $sandboxVenv 'pyvenv.cfg')
        $probe = @'
import json
import os
print(json.dumps({"playwright_browsers_path": os.environ.get("PLAYWRIGHT_BROWSERS_PATH")}))
'@
        [IO.File]::WriteAllText((Join-Path $sandboxCollectorRoot 'collect_best_sellers.py'), $probe, (New-Object Text.UTF8Encoding($false)))

        $commandOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'scripts\Collect-BestSellers.ps1') -ProjectRoot $sandboxRoot
        $exitCode = $LASTEXITCODE
        $result = $commandOutput | ConvertFrom-Json

        $exitCode | Should Be 0
        $result.playwright_browsers_path | Should Be (Join-Path $sandboxRoot '.local\playwright')
    }
}
