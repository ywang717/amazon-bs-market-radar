$projectRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $projectRoot 'src\LocalPackageOrchestrator.psm1'

Describe 'Local package menu and validation' {
    BeforeAll {
        Import-Module $modulePath -Force
    }

    It 'maps the approved Chinese menu choices to modes' {
        $expected = [ordered]@{
            '1' = 'DailyAuto'
            '2' = 'DailyImport'
            '3' = 'Weekly'
            '4' = 'Setup'
            '5' = 'ConfigureEmail'
            '6' = 'Health'
            '7' = 'Test'
            '8' = 'RegisterTasks'
            '9' = 'ExportHistory'
            '10' = 'ImportHistory'
            '0' = 'Exit'
        }

        foreach ($choice in $expected.Keys) {
            Get-LocalPackageMenuMode -Choice $choice | Should Be $expected[$choice]
        }
    }

    It 'rejects invalid menu input without invoking a mode and continues until exit' {
        $inputs = New-Object System.Collections.Queue
        $inputs.Enqueue('not-a-choice')
        $inputs.Enqueue('6')
        $inputs.Enqueue('0')
        $invoked = New-Object System.Collections.ArrayList
        $messages = New-Object System.Collections.ArrayList
        $reader = { $inputs.Dequeue() }.GetNewClosure()
        $invoker = {
            param([string]$Mode)
            [void]$invoked.Add($Mode)
            [pscustomobject]@{ mode = $Mode; status = 'SUCCESS'; exit_code = 0 }
        }.GetNewClosure()
        $writer = { param([string]$Message) [void]$messages.Add($Message) }.GetNewClosure()

        Start-LocalPackageMenu -ReadInput $reader -ModeInvoker $invoker -WriteMessage $writer

        @($invoked) | Should Be @('Health')
        ($messages -join "`n") | Should Match 'Invalid|choice'
    }

    It 'prompts for and forwards the snapshot path for DailyImport and displays failures' {
        $inputs = New-Object System.Collections.Queue
        $inputs.Enqueue('2')
        $inputs.Enqueue('0')
        $invoked = New-Object System.Collections.ArrayList
        $messages = New-Object System.Collections.ArrayList
        $reader = { $inputs.Dequeue() }.GetNewClosure()
        $pathReader = { 'C:\incoming\snapshot.json' }
        $invoker = {
            param([string]$Mode, [string]$SnapshotPath)
            [void]$invoked.Add([pscustomobject]@{ Mode = $Mode; SnapshotPath = $SnapshotPath })
            [pscustomobject]@{ mode = $Mode; status = 'FAILED'; exit_code = 1; error = 'Snapshot is not readable.' }
        }.GetNewClosure()
        $writer = { param([string]$Message) [void]$messages.Add($Message) }.GetNewClosure()

        Start-LocalPackageMenu -ReadInput $reader -ReadSnapshotPath $pathReader -ModeInvoker $invoker -WriteMessage $writer

        $invoked.Count | Should Be 1
        $invoked[0].Mode | Should Be 'DailyImport'
        $invoked[0].SnapshotPath | Should Be 'C:\incoming\snapshot.json'
        ($messages -join "`n") | Should Match 'Snapshot is not readable'
    }

    It 'accepts only real calendar dates in YYYY-MM-DD format' {
        Test-LocalPackageMarketDate -MarketDate '2026-08-11' | Should Be $true
        Test-LocalPackageMarketDate -MarketDate '2026-8-11' | Should Be $false
        Test-LocalPackageMarketDate -MarketDate '2026-02-30' | Should Be $false
    }
}

Describe 'Local package daily orchestration' {
    BeforeAll {
        Import-Module $modulePath -Force
    }

    It 'runs every daily gate in order, uses the latest prior snapshot, and propagates SkipEmail' {
        $sandboxRoot = Join-Path $TestDrive 'daily-project'
        $snapshotRoot = Join-Path $sandboxRoot 'var\amazon-bestsellers'
        $currentPath = Join-Path $snapshotRoot '2026-08-11\amazon-bestsellers.json'
        $olderPath = Join-Path $snapshotRoot '2026-08-08\amazon-bestsellers.json'
        $latestPriorPath = Join-Path $snapshotRoot '2026-08-10\amazon-bestsellers.json'
        foreach ($path in @($currentPath, $olderPath, $latestPriorPath)) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
            [IO.File]::WriteAllText($path, '{"market_date":"' + (Split-Path -Leaf (Split-Path -Parent $path)) + '","pressure_washers":[{}],"sump_pumps":[],"pressure_washer_accessories":[]}', (New-Object Text.UTF8Encoding($false)))
        }
        $calls = New-Object System.Collections.ArrayList
        $runner = {
            param([string]$Step, [string]$ScriptPath, [hashtable]$Arguments)
            [void]$calls.Add([pscustomobject]@{ Step = $Step; ScriptPath = $ScriptPath; Arguments = $Arguments })
            $result = switch ($Step) {
                'Collect' { [pscustomobject]@{ Status = 'COMPLETE'; TotalObservations = 1; SnapshotPath = $currentPath; CompletenessStatus = 'COMPLETE'; DiagnosticPath = (Join-Path (Split-Path -Parent $currentPath) 'price-completeness-diagnostic.json'); FailureReasons = @() } }
                'VerifyReceipt' { [pscustomobject]@{ valid = $true } }
                'ImportSnapshot' { [pscustomobject]@{ Status = 'IMPORTED_VERIFIED_SNAPSHOT' } }
                'DailyReports' { [pscustomobject]@{ Reports = @('one','two','three'); EmailDelivery = [pscustomobject]@{ Status = 'SKIPPED_BY_REQUEST' } } }
                'Backup' { [pscustomobject]@{ Status = 'BACKED_UP'; BackupPath = (Join-Path $sandboxRoot '.local\postgres-backups\test.dump') } }
                'VerifyBackup' { [pscustomobject]@{ Status = 'VERIFIED' } }
                'Health' { [pscustomobject]@{ Status = 'HEALTHY' } }
                default { [pscustomobject]@{ Status = 'OK' } }
            }
            [pscustomobject]@{ ExitCode = 0; Result = $result }
        }.GetNewClosure()

        $summary = Invoke-LocalPackageMode -Mode DailyAuto -MarketDate '2026-08-11' -SkipEmail -ProjectRoot $sandboxRoot -StepRunner $runner

        $summary.status | Should Be 'SUCCESS'
        @($calls | ForEach-Object Step) | Should Be @('Collect','RegisterReceipt','VerifyReceipt','ImportSnapshot','DailyReports','Backup','VerifyBackup','Health')
        ($calls | Where-Object Step -eq 'DailyReports').Arguments.PreviousPath | Should Be $latestPriorPath
        ($calls | Where-Object Step -eq 'DailyReports').Arguments.SkipEmail | Should Be $true
        $summary.artifacts.snapshot_path | Should Be $currentPath
        $summary.artifacts.previous_snapshot_path | Should Be $latestPriorPath
    }

    It 'stops later gates when receipt verification fails' {
        $sandboxRoot = Join-Path $TestDrive 'failed-gate-project'
        $currentPath = Join-Path $sandboxRoot 'var\amazon-bestsellers\2026-08-11\amazon-bestsellers.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $currentPath) -Force | Out-Null
        [IO.File]::WriteAllText($currentPath, '{"market_date":"2026-08-11","pressure_washers":[{}],"sump_pumps":[],"pressure_washer_accessories":[]}', (New-Object Text.UTF8Encoding($false)))
        $calls = New-Object System.Collections.ArrayList
        $runner = {
            param([string]$Step, [string]$ScriptPath, [hashtable]$Arguments)
            [void]$calls.Add($Step)
            if ($Step -eq 'Collect') { return [pscustomobject]@{ ExitCode = 0; Result = [pscustomobject]@{ Status = 'COMPLETE'; TotalObservations = 1; SnapshotPath = $currentPath; CompletenessStatus = 'COMPLETE'; DiagnosticPath = (Join-Path (Split-Path -Parent $currentPath) 'price-completeness-diagnostic.json'); FailureReasons = @() } } }
            if ($Step -eq 'VerifyReceipt') { return [pscustomobject]@{ ExitCode = 2; Result = [pscustomobject]@{ valid = $false } } }
            [pscustomobject]@{ ExitCode = 0; Result = [pscustomobject]@{ Status = 'OK' } }
        }.GetNewClosure()

        $summary = Invoke-LocalPackageMode -Mode DailyAuto -MarketDate '2026-08-11' -ProjectRoot $sandboxRoot -StepRunner $runner

        $summary.status | Should Be 'FAILED'
        @($calls) | Should Be @('Collect','RegisterReceipt','VerifyReceipt')
        $summary.error | Should Match 'VerifyReceipt'
    }

    It 'stops before receipt and reports failure when the collector returns zero observations' {
        $sandboxRoot = Join-Path $TestDrive 'zero-project'
        $calls = New-Object System.Collections.ArrayList
        $runner = {
            param([string]$Step, [string]$ScriptPath, [hashtable]$Arguments)
            [void]$calls.Add($Step)
            [pscustomobject]@{ ExitCode = 0; Result = [pscustomobject]@{ Status = 'COMPLETE'; TotalObservations = 0; CompletenessStatus = 'COMPLETE' } }
        }.GetNewClosure()

        $summary = Invoke-LocalPackageMode -Mode DailyAuto -MarketDate '2026-08-11' -ProjectRoot $sandboxRoot -StepRunner $runner

        $summary.status | Should Be 'FAILED'
        @($calls) | Should Be @('Collect')
        $summary.error | Should Match 'zero observations'
    }

    It 'stops after Collect when observations are incomplete and reports only canonical diagnostics and safe reason codes' {
        $sandboxRoot = Join-Path $TestDrive 'incomplete-pricing-project'
        $diagnosticPath = Join-Path $sandboxRoot 'var\amazon-bestsellers\2026-08-11\price-completeness-diagnostic.json'
        $calls = New-Object System.Collections.ArrayList
        $runner = {
            param([string]$Step, [string]$ScriptPath, [hashtable]$Arguments)
            [void]$calls.Add($Step)
            if ($Step -ne 'Collect') { throw 'later gate must not run' }
            [pscustomobject]@{
                ExitCode = 20
                Result = [pscustomobject]@{
                    Status = 'INCOMPLETE'
                    TotalObservations = 150
                    SnapshotPath = $null
                    CompletenessStatus = 'FAILED'
                    DiagnosticPath = $diagnosticPath
                    FailureReasons = @('MISSING_PRICE_EVIDENCE', 'cookie=collector-secret')
                    error = 'raw collector failure bearer top-secret-token'
                }
            }
        }.GetNewClosure()

        $summary = Invoke-LocalPackageMode -Mode DailyAuto -MarketDate '2026-08-11' -ProjectRoot $sandboxRoot -StepRunner $runner

        $summary.status | Should Be 'FAILED'
        @($calls) | Should Be @('Collect')
        $summary.steps.Count | Should Be 1
        $summary.steps[0].name | Should Be 'Collect'
        $summary.steps[0].status | Should Be 'FAILED'
        $summary.error | Should Match ([regex]::Escape($diagnosticPath))
        $summary.error | Should Match 'MISSING_PRICE_EVIDENCE'
        $summary.error | Should Not Match 'cookie|collector-secret|bearer|top-secret-token'
        $summary.artifacts.snapshot_path | Should BeNullOrEmpty
        $summary.artifacts.receipt_path | Should BeNullOrEmpty
        $summary.artifacts.report_directory | Should BeNullOrEmpty
        $summary.artifacts.backup_path | Should BeNullOrEmpty
    }

    It 'sanitizes a thrown collector exception before it reaches the daily failure summary' {
        $sandboxRoot = Join-Path $TestDrive 'throwing-collector-project'
        $calls = New-Object System.Collections.ArrayList
        $runner = {
            param([string]$Step, [string]$ScriptPath, [hashtable]$Arguments)
            [void]$calls.Add($Step)
            throw 'raw collector failure bearer top-secret-token'
        }.GetNewClosure()

        $summary = Invoke-LocalPackageMode -Mode DailyAuto -MarketDate '2026-08-11' -ProjectRoot $sandboxRoot -StepRunner $runner

        $summary.status | Should Be 'FAILED'
        @($calls) | Should Be @('Collect')
        $summary.steps.Count | Should Be 1
        $summary.steps[0].name | Should Be 'Collect'
        $summary.steps[0].status | Should Be 'FAILED'
        $summary.error | Should Match 'Collector collection failed before pricing completeness could be verified'
        $summary.error | Should Not Match 'raw collector failure|bearer|top-secret-token'
        $summary.artifacts.snapshot_path | Should BeNullOrEmpty
        $summary.artifacts.receipt_path | Should BeNullOrEmpty
        $summary.artifacts.report_directory | Should BeNullOrEmpty
        $summary.artifacts.backup_path | Should BeNullOrEmpty
    }

    It 'rejects non-exact completeness and omits off-project diagnostics and non-allowlisted reasons' {
        $sandboxRoot = Join-Path $TestDrive 'unsafe-incomplete-project'
        $outsidePath = Join-Path $TestDrive 'outside\stolen-cookie.txt'
        $calls = New-Object System.Collections.ArrayList
        $runner = {
            param([string]$Step, [string]$ScriptPath, [hashtable]$Arguments)
            [void]$calls.Add($Step)
            [pscustomobject]@{
                ExitCode = 20
                Result = [pscustomobject]@{
                    TotalObservations = 150
                    CompletenessStatus = 'complete'
                    DiagnosticPath = $outsidePath
                    FailureReasons = @('NOT_ALLOWLISTED_SECRET_REASON')
                }
            }
        }.GetNewClosure()

        $summary = Invoke-LocalPackageMode -Mode DailyAuto -MarketDate '2026-08-11' -ProjectRoot $sandboxRoot -StepRunner $runner

        $summary.status | Should Be 'FAILED'
        @($calls) | Should Be @('Collect')
        $summary.steps[0].status | Should Be 'FAILED'
        $summary.error | Should Match 'pricing completeness'
        $summary.error | Should Not Match 'stolen-cookie|NOT_ALLOWLISTED_SECRET_REASON'
    }

    It 'rejects a collector snapshot outside the canonical market-date path and marks Collect failed' {
        $sandboxRoot = Join-Path $TestDrive 'collector-path-project'
        $wrongPath = Join-Path $sandboxRoot 'var\other\amazon-bestsellers.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $wrongPath) -Force | Out-Null
        [IO.File]::WriteAllText($wrongPath, '{"market_date":"2026-08-11"}', (New-Object Text.UTF8Encoding($false)))
        $calls = New-Object System.Collections.ArrayList
        $runner = {
            param([string]$Step, [string]$ScriptPath, [hashtable]$Arguments)
            [void]$calls.Add($Step)
            if ($Step -ne 'Collect') { throw 'later gate must not run' }
            [pscustomobject]@{ ExitCode = 0; Result = [pscustomobject]@{ Status = 'COMPLETE'; TotalObservations = 1; SnapshotPath = $wrongPath; CompletenessStatus = 'COMPLETE' } }
        }.GetNewClosure()

        $summary = Invoke-LocalPackageMode -Mode DailyAuto -MarketDate '2026-08-11' -ProjectRoot $sandboxRoot -StepRunner $runner

        $summary.status | Should Be 'FAILED'
        @($calls) | Should Be @('Collect')
        $summary.error | Should Match 'canonical'
        $summary.steps[0].name | Should Be 'Collect'
        $summary.steps[0].status | Should Be 'FAILED'
    }

    It 'marks Collect failed when the collector returns a malformed snapshot path' {
        $sandboxRoot = Join-Path $TestDrive 'collector-malformed-path-project'
        $calls = New-Object System.Collections.ArrayList
        $runner = {
            param([string]$Step, [string]$ScriptPath, [hashtable]$Arguments)
            [void]$calls.Add($Step)
            if ($Step -ne 'Collect') { throw 'later gate must not run' }
            [pscustomobject]@{ ExitCode = 0; Result = [pscustomobject]@{ Status = 'COMPLETE'; TotalObservations = 1; SnapshotPath = 'bad|path'; CompletenessStatus = 'COMPLETE' } }
        }.GetNewClosure()

        $summary = Invoke-LocalPackageMode -Mode DailyAuto -MarketDate '2026-08-11' -ProjectRoot $sandboxRoot -StepRunner $runner

        $summary.status | Should Be 'FAILED'
        @($calls) | Should Be @('Collect')
        $summary.steps.Count | Should Be 1
        $summary.steps[0].name | Should Be 'Collect'
        $summary.steps[0].status | Should Be 'FAILED'
    }

    It 'rejects a canonical collector snapshot whose embedded market date differs and marks Collect failed' {
        $sandboxRoot = Join-Path $TestDrive 'collector-date-project'
        $canonical = Join-Path $sandboxRoot 'var\amazon-bestsellers\2026-08-11\amazon-bestsellers.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $canonical) -Force | Out-Null
        [IO.File]::WriteAllText($canonical, '{"market_date":"2026-08-10"}', (New-Object Text.UTF8Encoding($false)))
        $calls = New-Object System.Collections.ArrayList
        $runner = {
            param([string]$Step, [string]$ScriptPath, [hashtable]$Arguments)
            [void]$calls.Add($Step)
            if ($Step -ne 'Collect') { throw 'later gate must not run' }
            [pscustomobject]@{ ExitCode = 0; Result = [pscustomobject]@{ Status = 'COMPLETE'; TotalObservations = 1; SnapshotPath = $canonical; CompletenessStatus = 'COMPLETE' } }
        }.GetNewClosure()

        $summary = Invoke-LocalPackageMode -Mode DailyAuto -MarketDate '2026-08-11' -ProjectRoot $sandboxRoot -StepRunner $runner

        $summary.status | Should Be 'FAILED'
        @($calls) | Should Be @('Collect')
        $summary.error | Should Match 'market date'
        $summary.steps[0].status | Should Be 'FAILED'
    }

    It 'rejects a canonical collector snapshot with no embedded market date and marks Collect failed' {
        $sandboxRoot = Join-Path $TestDrive 'collector-missing-date-project'
        $canonical = Join-Path $sandboxRoot 'var\amazon-bestsellers\2026-08-11\amazon-bestsellers.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $canonical) -Force | Out-Null
        [IO.File]::WriteAllText($canonical, '{}', (New-Object Text.UTF8Encoding($false)))
        $runner = {
            param([string]$Step, [string]$ScriptPath, [hashtable]$Arguments)
            if ($Step -ne 'Collect') { throw 'later gate must not run' }
            [pscustomobject]@{ ExitCode = 0; Result = [pscustomobject]@{ Status = 'COMPLETE'; TotalObservations = 1; SnapshotPath = $canonical; CompletenessStatus = 'COMPLETE' } }
        }.GetNewClosure()

        $summary = Invoke-LocalPackageMode -Mode DailyAuto -MarketDate '2026-08-11' -ProjectRoot $sandboxRoot -StepRunner $runner

        $summary.status | Should Be 'FAILED'
        $summary.steps[0].status | Should Be 'FAILED'
        $summary.error | Should Match 'market date'
    }

    It 'stops before backup when overall daily email delivery is not SENT' {
        foreach ($deliveryStatus in @('PARTIAL_FAILURE','SKIPPED_MISSING_CREDENTIALS')) {
            $sandboxRoot = Join-Path $TestDrive ("delivery-$deliveryStatus")
            $canonical = Join-Path $sandboxRoot 'var\amazon-bestsellers\2026-08-11\amazon-bestsellers.json'
            New-Item -ItemType Directory -Path (Split-Path -Parent $canonical) -Force | Out-Null
            [IO.File]::WriteAllText($canonical, '{"market_date":"2026-08-11"}', (New-Object Text.UTF8Encoding($false)))
            $calls = New-Object System.Collections.ArrayList
            $runner = {
                param([string]$Step, [string]$ScriptPath, [hashtable]$Arguments)
                [void]$calls.Add($Step)
                $result = switch ($Step) {
                    'Collect' { [pscustomobject]@{ Status = 'COMPLETE'; TotalObservations = 1; SnapshotPath = $canonical; CompletenessStatus = 'COMPLETE'; DiagnosticPath = (Join-Path (Split-Path -Parent $canonical) 'price-completeness-diagnostic.json'); FailureReasons = @() } }
                    'VerifyReceipt' { [pscustomobject]@{ valid = $true } }
                    'ImportSnapshot' { [pscustomobject]@{ Status = 'IMPORTED_VERIFIED_SNAPSHOT' } }
                    'DailyReports' { [pscustomobject]@{ Reports = @('one','two','three'); EmailDelivery = [pscustomobject]@{ Status = $deliveryStatus } } }
                    default { [pscustomobject]@{ Status = 'OK' } }
                }
                [pscustomobject]@{ ExitCode = 0; Result = $result }
            }.GetNewClosure()

            $summary = Invoke-LocalPackageMode -Mode DailyAuto -MarketDate '2026-08-11' -ProjectRoot $sandboxRoot -StepRunner $runner

            $summary.status | Should Be 'FAILED'
            @($calls) | Should Be @('Collect','RegisterReceipt','VerifyReceipt','ImportSnapshot','DailyReports')
            ($summary.steps | Where-Object name -eq 'DailyReports').status | Should Be 'FAILED'
            $summary.error | Should Match 'EmailDelivery'
        }
    }

    It 'marks a malformed exit-zero receipt result as a failed VerifyReceipt step' {
        $sandboxRoot = Join-Path $TestDrive 'semantic-receipt-project'
        $canonical = Join-Path $sandboxRoot 'var\amazon-bestsellers\2026-08-11\amazon-bestsellers.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $canonical) -Force | Out-Null
        [IO.File]::WriteAllText($canonical, '{"market_date":"2026-08-11"}', (New-Object Text.UTF8Encoding($false)))
        $runner = {
            param([string]$Step, [string]$ScriptPath, [hashtable]$Arguments)
            $result = if ($Step -eq 'Collect') { [pscustomobject]@{ Status = 'COMPLETE'; TotalObservations = 1; SnapshotPath = $canonical; CompletenessStatus = 'COMPLETE'; DiagnosticPath = (Join-Path (Split-Path -Parent $canonical) 'price-completeness-diagnostic.json'); FailureReasons = @() } } elseif ($Step -eq 'VerifyReceipt') { [pscustomobject]@{} } else { [pscustomobject]@{ Status = 'OK' } }
            [pscustomobject]@{ ExitCode = 0; Result = $result }
        }.GetNewClosure()

        $summary = Invoke-LocalPackageMode -Mode DailyAuto -MarketDate '2026-08-11' -ProjectRoot $sandboxRoot -StepRunner $runner

        $summary.status | Should Be 'FAILED'
        ($summary.steps | Where-Object name -eq 'VerifyReceipt').status | Should Be 'FAILED'
    }

    It 'imports a readable snapshot by its market date before running daily gates' {
        $sandboxRoot = Join-Path $TestDrive 'import-project'
        $sourcePath = Join-Path $TestDrive 'incoming snapshot.json'
        [IO.File]::WriteAllText($sourcePath, '{"market_date":"2026-08-09","pressure_washers":[{}],"sump_pumps":[],"pressure_washer_accessories":[]}', (New-Object Text.UTF8Encoding($false)))
        $calls = New-Object System.Collections.ArrayList
        $runner = {
            param([string]$Step, [string]$ScriptPath, [hashtable]$Arguments)
            [void]$calls.Add($Step)
            $result = switch ($Step) {
                'VerifyReceipt' { [pscustomobject]@{ valid = $true } }
                'ImportSnapshot' { [pscustomobject]@{ Status = 'IMPORTED_VERIFIED_SNAPSHOT' } }
                'DailyReports' { [pscustomobject]@{ Reports = @('one','two','three'); EmailDelivery = [pscustomobject]@{ Status = 'SENT' } } }
                'Backup' { [pscustomobject]@{ Status = 'BACKED_UP'; BackupPath = 'backup.dump' } }
                'VerifyBackup' { [pscustomobject]@{ Status = 'VERIFIED' } }
                'Health' { [pscustomobject]@{ Status = 'HEALTHY' } }
                default { [pscustomobject]@{ Status = 'OK' } }
            }
            [pscustomobject]@{ ExitCode = 0; Result = $result }
        }.GetNewClosure()

        $summary = Invoke-LocalPackageMode -Mode DailyImport -SnapshotPath $sourcePath -ProjectRoot $sandboxRoot -StepRunner $runner
        $canonical = Join-Path $sandboxRoot 'var\amazon-bestsellers\2026-08-09\amazon-bestsellers.json'

        $summary.status | Should Be 'SUCCESS'
        $summary.market_date | Should Be '2026-08-09'
        $summary.artifacts.snapshot_path | Should Be $canonical
        (Get-FileHash -LiteralPath $canonical).Hash | Should Be (Get-FileHash -LiteralPath $sourcePath).Hash
        @($calls) | Should Be @('RegisterReceipt','VerifyReceipt','ImportSnapshot','DailyReports','Backup','VerifyBackup','Health')
    }

    It 'rejects an imported snapshot whose market date does not match the supplied date' {
        $sandboxRoot = Join-Path $TestDrive 'mismatch-project'
        $sourcePath = Join-Path $TestDrive 'mismatch.json'
        [IO.File]::WriteAllText($sourcePath, '{"market_date":"2026-08-09"}', (New-Object Text.UTF8Encoding($false)))
        $calls = New-Object System.Collections.ArrayList
        $runner = { param($Step, $ScriptPath, $Arguments) [void]$calls.Add($Step) }.GetNewClosure()

        $summary = Invoke-LocalPackageMode -Mode DailyImport -MarketDate '2026-08-10' -SnapshotPath $sourcePath -ProjectRoot $sandboxRoot -StepRunner $runner

        $summary.status | Should Be 'FAILED'
        $summary.error | Should Match 'does not match'
        $calls.Count | Should Be 0
        Test-Path -LiteralPath (Join-Path $sandboxRoot 'var\amazon-bestsellers\2026-08-10\amazon-bestsellers.json') | Should Be $false
    }

    It 'does not overwrite a different canonical snapshot' {
        $sandboxRoot = Join-Path $TestDrive 'overwrite-project'
        $sourcePath = Join-Path $TestDrive 'new.json'
        $canonical = Join-Path $sandboxRoot 'var\amazon-bestsellers\2026-08-09\amazon-bestsellers.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $canonical) -Force | Out-Null
        [IO.File]::WriteAllText($sourcePath, '{"market_date":"2026-08-09","value":"new"}', (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($canonical, '{"market_date":"2026-08-09","value":"existing"}', (New-Object Text.UTF8Encoding($false)))

        $summary = Invoke-LocalPackageMode -Mode DailyImport -SnapshotPath $sourcePath -ProjectRoot $sandboxRoot -StepRunner { throw 'must not run' }

        $summary.status | Should Be 'FAILED'
        $summary.error | Should Match 'different snapshot already exists'
        (Get-Content -LiteralPath $canonical -Raw) | Should Match 'existing'
    }

    It 'never leaves a partial canonical snapshot when an import copy is interrupted' {
        $sandboxRoot = Join-Path $TestDrive 'interrupted-import-project'
        $sourcePath = Join-Path $TestDrive 'atomic-source.json'
        $canonical = Join-Path $sandboxRoot 'var\amazon-bestsellers\2026-08-09\amazon-bestsellers.json'
        [IO.File]::WriteAllText($sourcePath, '{"market_date":"2026-08-09","value":"complete"}', (New-Object Text.UTF8Encoding($false)))
        Mock -CommandName Copy-Item -ModuleName LocalPackageOrchestrator -MockWith {
            param($LiteralPath, $Destination)
            [IO.File]::WriteAllText($Destination, 'partial', (New-Object Text.UTF8Encoding($false)))
            throw 'simulated interrupted copy'
        }

        $summary = Invoke-LocalPackageMode -Mode DailyImport -SnapshotPath $sourcePath -ProjectRoot $sandboxRoot -StepRunner { throw 'must not run' }

        $summary.status | Should Be 'FAILED'
        Test-Path -LiteralPath $canonical | Should Be $false
        @((Get-ChildItem -LiteralPath (Split-Path -Parent $canonical) -Filter '*.staging' -File -ErrorAction SilentlyContinue)).Count | Should Be 0
    }

    It 'rejects a completed staging copy whose content does not match the source' {
        $sandboxRoot = Join-Path $TestDrive 'truncated-import-project'
        $sourcePath = Join-Path $TestDrive 'truncated-source.json'
        $canonical = Join-Path $sandboxRoot 'var\amazon-bestsellers\2026-08-09\amazon-bestsellers.json'
        [IO.File]::WriteAllText($sourcePath, '{"market_date":"2026-08-09","value":"complete"}', (New-Object Text.UTF8Encoding($false)))
        Mock -CommandName Copy-Item -ModuleName LocalPackageOrchestrator -MockWith {
            param($LiteralPath, $Destination)
            [IO.File]::WriteAllText($Destination, 'truncated', (New-Object Text.UTF8Encoding($false)))
        }

        $summary = Invoke-LocalPackageMode -Mode DailyImport -SnapshotPath $sourcePath -ProjectRoot $sandboxRoot -StepRunner { throw 'must not run' }

        $summary.status | Should Be 'FAILED'
        $summary.error | Should Match 'did not match'
        Test-Path -LiteralPath $canonical | Should Be $false
        @((Get-ChildItem -LiteralPath (Split-Path -Parent $canonical) -Filter '*.staging' -File -ErrorAction SilentlyContinue)).Count | Should Be 0
    }
}


Describe 'Local package dispatch, locks, and machine output' {
    BeforeAll {
        Import-Module $modulePath -Force
    }

    It 'forwards ReportDate and SkipEmail to the weekly report entry' {
        $sandboxRoot = Join-Path $TestDrive 'weekly-project'
        $call = $null
        $runner = {
            param([string]$Step, [string]$ScriptPath, [hashtable]$Arguments)
            $script:weeklyCall = [pscustomobject]@{ Step = $Step; ScriptPath = $ScriptPath; Arguments = $Arguments }
            [pscustomobject]@{ ExitCode = 0; Result = [pscustomobject]@{ Status = 'OK' } }
        }

        $summary = Invoke-LocalPackageMode -Mode Weekly -MarketDate '2026-08-11' -SkipEmail -ProjectRoot $sandboxRoot -StepRunner $runner

        $summary.status | Should Be 'SUCCESS'
        $script:weeklyCall.Step | Should Be 'WeeklyReport'
        $script:weeklyCall.ScriptPath | Should Be (Join-Path $sandboxRoot 'scripts\New-BestSellersWeeklyReport.ps1')
        $script:weeklyCall.Arguments.ReportDate | Should Be '2026-08-11'
        $script:weeklyCall.Arguments.SkipEmail | Should Be $true
    }

    It 'loads the local recipient and forwards it to both daily and weekly reports' {
        $dailyRoot = Join-Path $TestDrive 'recipient-daily-project'
        $snapshot = Join-Path $dailyRoot 'var\amazon-bestsellers\2026-08-11\amazon-bestsellers.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $snapshot),(Join-Path $dailyRoot '.local') -Force | Out-Null
        [IO.File]::WriteAllText($snapshot, '{"market_date":"2026-08-11","pressure_washers":[{}],"sump_pumps":[],"pressure_washer_accessories":[]}')
        [IO.File]::WriteAllText((Join-Path $dailyRoot '.local\user-settings.json'), '{"recipient_address":"local@example.com"}')
        $recipientCalls = New-Object System.Collections.ArrayList
        $runner = {
            param([string]$Step, [string]$ScriptPath, [hashtable]$Arguments)
            [void]$recipientCalls.Add([pscustomobject]@{ Step=$Step; Arguments=$Arguments })
            $result = switch ($Step) {
                'Collect' { [pscustomobject]@{ Status='COMPLETE'; TotalObservations=1; SnapshotPath=$snapshot; CompletenessStatus='COMPLETE'; DiagnosticPath=(Join-Path (Split-Path -Parent $snapshot) 'price-completeness-diagnostic.json'); FailureReasons=@() } }
                'VerifyReceipt' { [pscustomobject]@{ valid=$true } }
                'ImportSnapshot' { [pscustomobject]@{ Status='IMPORTED_VERIFIED_SNAPSHOT' } }
                'DailyReports' { [pscustomobject]@{ Reports=@(1,2,3); EmailDelivery=[pscustomobject]@{ Status='SKIPPED_BY_REQUEST' } } }
                'Backup' { [pscustomobject]@{ Status='BACKED_UP'; BackupPath=(Join-Path $dailyRoot '.local\postgres-backups\x.dump') } }
                'VerifyBackup' { [pscustomobject]@{ Status='VERIFIED' } }
                'Health' { [pscustomobject]@{ Status='HEALTHY' } }
                default { [pscustomobject]@{ Status='OK' } }
            }
            [pscustomobject]@{ ExitCode=0; Result=$result }
        }.GetNewClosure()

        $daily = Invoke-LocalPackageMode -Mode DailyAuto -MarketDate '2026-08-11' -SkipEmail -ProjectRoot $dailyRoot -StepRunner $runner
        $weekly = Invoke-LocalPackageMode -Mode Weekly -SkipEmail -ProjectRoot $dailyRoot -StepRunner $runner

        $daily.error | Should BeNullOrEmpty
        $daily.status | Should Be 'SUCCESS'
        $weekly.status | Should Be 'SUCCESS'
        ($recipientCalls | Where-Object Step -eq 'DailyReports').Arguments.EmailRecipient | Should Be 'local@example.com'
        ($recipientCalls | Where-Object Step -eq 'WeeklyReport').Arguments.EmailRecipient | Should Be 'local@example.com'
    }

    It 'omits EmailRecipient only when no local recipient file exists' {
        $root = Join-Path $TestDrive 'recipient-fallback-project'
        $script:fallbackArguments = $null
        $runner = {
            param([string]$Step, [string]$ScriptPath, [hashtable]$Arguments)
            $script:fallbackArguments = $Arguments
            [pscustomobject]@{ ExitCode=0; Result=[pscustomobject]@{ Status='OK' } }
        }

        $summary = Invoke-LocalPackageMode -Mode Weekly -SkipEmail -ProjectRoot $root -StepRunner $runner

        $summary.status | Should Be 'SUCCESS'
        $script:fallbackArguments.ContainsKey('EmailRecipient') | Should Be $false
    }

    It 'omits ReportDate when Weekly has no date so the weekly script keeps its Beijing default' {
        $sandboxRoot = Join-Path $TestDrive 'weekly-default-project'
        $script:weeklyDefaultCall = $null
        $runner = {
            param([string]$Step, [string]$ScriptPath, [hashtable]$Arguments)
            $script:weeklyDefaultCall = [pscustomobject]@{ Arguments = $Arguments }
            [pscustomobject]@{ ExitCode = 0; Result = [pscustomobject]@{ Status = 'OK' } }
        }

        $summary = Invoke-LocalPackageMode -Mode Weekly -ProjectRoot $sandboxRoot -StepRunner $runner

        $summary.status | Should Be 'SUCCESS'
        $summary.market_date | Should BeNullOrEmpty
        $script:weeklyDefaultCall.Arguments.ContainsKey('ReportDate') | Should Be $false
    }

    It 'returns an actionable failure when a stable downstream script is missing' {
        $sandboxRoot = Join-Path $TestDrive 'missing-script-project'
        New-Item -ItemType Directory -Path $sandboxRoot -Force | Out-Null

        $summary = Invoke-LocalPackageMode -Mode Setup -ProjectRoot $sandboxRoot

        $summary.status | Should Be 'FAILED'
        $summary.exit_code | Should Not Be 0
        $summary.error | Should Match 'Initialize-LocalPackage.ps1'
        $summary.error | Should Match 'missing'
        $summary.steps.Count | Should Be 1
        $summary.steps[0].name | Should Be 'Setup'
        $summary.steps[0].status | Should Be 'FAILED'
    }

    It 'propagates a redacted actionable inner setup error through the launcher as one JSON object' {
        $sandboxRoot = Join-Path $TestDrive 'inner-setup-error'
        New-Item -ItemType Directory -Path (Join-Path $sandboxRoot 'scripts'),(Join-Path $sandboxRoot 'src') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $projectRoot 'scripts\Start-LocalPackage.ps1') -Destination (Join-Path $sandboxRoot 'scripts\Start-LocalPackage.ps1')
        Copy-Item -LiteralPath $modulePath -Destination (Join-Path $sandboxRoot 'src\LocalPackageOrchestrator.psm1')
        $innerScript = @'
$processSecret = [Environment]::GetEnvironmentVariable('DAILY_REPORT_SMTP_AUTH_CODE','Process')
[pscustomobject]@{ status='FAILED'; errors=@("PostgreSQL archive checksum mismatch $processSecret") } | ConvertTo-Json -Compress
exit 7
'@
        [IO.File]::WriteAllText((Join-Path $sandboxRoot 'scripts\Initialize-LocalPackage.ps1'), $innerScript, (New-Object Text.UTF8Encoding($false)))
        $saved = [Environment]::GetEnvironmentVariable('DAILY_REPORT_SMTP_AUTH_CODE','Process')
        try {
            [Environment]::SetEnvironmentVariable('DAILY_REPORT_SMTP_AUTH_CODE','process-review-secret','Process')
            $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sandboxRoot 'scripts\Start-LocalPackage.ps1') -Mode Setup)
            $exitCode = $LASTEXITCODE
        }
        finally { [Environment]::SetEnvironmentVariable('DAILY_REPORT_SMTP_AUTH_CODE',$saved,'Process') }
        $summary = ($output -join "`n") | ConvertFrom-Json

        $exitCode | Should Be 1
        $summary.status | Should Be 'FAILED'
        $summary.error | Should Match 'PostgreSQL archive checksum mismatch'
        ($output -join "`n") | Should Not Match 'process-review-secret'
    }

    It 'redacts secrets supplied from both Process and User environment scopes' {
        $provider = {
            param([string]$Name, [string]$Scope)
            if ($Scope -eq 'Process') { return 'process-scope-secret' }
            if ($Scope -eq 'User') { return 'user-scope-secret' }
        }
        $runner = { throw 'failure process-scope-secret user-scope-secret' }

        $summary = Invoke-LocalPackageMode -Mode Setup -ProjectRoot (Join-Path $TestDrive 'scope-redaction') -StepRunner $runner -EnvironmentValueProvider $provider

        $summary.error | Should Match '\[REDACTED\]'
        $summary.error | Should Not Match 'process-scope-secret|user-scope-secret'
    }

    It 'parses multiline JSON from a real side-effect-free downstream script' {
        $sandboxRoot = Join-Path $TestDrive 'multiline-project'
        $scriptsRoot = Join-Path $sandboxRoot 'scripts'
        New-Item -ItemType Directory -Path $scriptsRoot -Force | Out-Null
        $healthScript = @'
param([string]$MarketDate)
[pscustomobject]@{ Status = 'HEALTHY'; MarketDate = $MarketDate } | ConvertTo-Json
'@
        [IO.File]::WriteAllText((Join-Path $scriptsRoot 'Test-BestSellersDailyOperationalHealth.ps1'), $healthScript, (New-Object Text.UTF8Encoding($false)))

        $summary = Invoke-LocalPackageMode -Mode Health -MarketDate '2026-08-11' -ProjectRoot $sandboxRoot

        $summary.status | Should Be 'SUCCESS'
        $summary.steps.Count | Should Be 1
    }

    It 'dispatches utility modes to their approved stable script names' {
        $sandboxRoot = Join-Path $TestDrive 'utility-project'
        $expected = [ordered]@{
            Setup = 'scripts\Initialize-LocalPackage.ps1'
            ConfigureEmail = 'scripts\Set-EmailEnvironment.ps1'
            RegisterTasks = 'scripts\Register-LocalPackageScheduledTasks.ps1'
            ExportHistory = 'scripts\Export-LocalPackageHistory.ps1'
            ImportHistory = 'scripts\Import-LocalPackageHistory.ps1'
        }

        foreach ($mode in $expected.Keys) {
            $script:utilityCall = $null
            $runner = {
                param([string]$Step, [string]$ScriptPath, [hashtable]$Arguments)
                $script:utilityCall = [pscustomobject]@{ Step = $Step; ScriptPath = $ScriptPath }
                [pscustomobject]@{ ExitCode = 0; Result = [pscustomobject]@{ Status = 'OK' } }
            }
            $summary = Invoke-LocalPackageMode -Mode $mode -ProjectRoot $sandboxRoot -StepRunner $runner

            $summary.status | Should Be 'SUCCESS'
            $script:utilityCall.ScriptPath | Should Be (Join-Path $sandboxRoot $expected[$mode])
        }
    }

    It 'forwards explicit history archive paths to export and import scripts' {
        $sandboxRoot = Join-Path $TestDrive 'history-path-project'
        $calls = New-Object System.Collections.ArrayList
        $runner = {
            param([string]$Step, [string]$ScriptPath, [hashtable]$Arguments)
            [void]$calls.Add([pscustomobject]@{ Step=$Step; Arguments=$Arguments })
            [pscustomobject]@{ ExitCode=0; Result=[pscustomobject]@{ Status='OK' } }
        }.GetNewClosure()
        $exportPath = Join-Path $sandboxRoot 'out\history.zip'
        $importPath = Join-Path $sandboxRoot 'in\history.zip'

        $export = Invoke-LocalPackageMode -Mode ExportHistory -OutputPath $exportPath -ProjectRoot $sandboxRoot -StepRunner $runner
        $import = Invoke-LocalPackageMode -Mode ImportHistory -ArchivePath $importPath -ProjectRoot $sandboxRoot -StepRunner $runner

        $export.status | Should Be 'SUCCESS'
        $import.status | Should Be 'SUCCESS'
        ($calls | Where-Object Step -eq 'ExportHistory').Arguments.OutputPath | Should Be $exportPath
        ($calls | Where-Object Step -eq 'ImportHistory').Arguments.ArchivePath | Should Be $importPath
    }

    It 'prompts for and forwards the archive path for menu history import' {
        $inputs = New-Object System.Collections.Queue
        $inputs.Enqueue('10')
        $inputs.Enqueue('0')
        $invoked = New-Object System.Collections.ArrayList
        $reader = { $inputs.Dequeue() }.GetNewClosure()
        $archiveReader = { 'C:\incoming\history.zip' }
        $invoker = {
            param([string]$Mode, [string]$SnapshotPath, [string]$ArchivePath)
            [void]$invoked.Add([pscustomobject]@{Mode=$Mode;SnapshotPath=$SnapshotPath;ArchivePath=$ArchivePath})
            [pscustomobject]@{status='SUCCESS'}
        }.GetNewClosure()

        Start-LocalPackageMenu -ReadInput $reader -ReadArchivePath $archiveReader -ModeInvoker $invoker -WriteMessage { param($message) }

        $invoked.Count | Should Be 1
        $invoked[0].Mode | Should Be 'ImportHistory'
        $invoked[0].SnapshotPath | Should BeNullOrEmpty
        $invoked[0].ArchivePath | Should Be 'C:\incoming\history.zip'
    }

    It 'rejects a second same-mode run and succeeds after the first lock is released' {
        $sandboxRoot = Join-Path $TestDrive 'lock-project'
        New-Item -ItemType Directory -Path $sandboxRoot -Force | Out-Null
        $heldLock = Enter-LocalPackageModeLock -ProjectRoot $sandboxRoot -Mode Health
        $runner = { [pscustomobject]@{ ExitCode = 0; Result = [pscustomobject]@{ Status = 'HEALTHY' } } }
        try {
            $blocked = Invoke-LocalPackageMode -Mode Health -MarketDate '2026-08-11' -ProjectRoot $sandboxRoot -StepRunner $runner
            $blocked.status | Should Be 'FAILED'
            $blocked.error | Should Match 'already running'
        }
        finally {
            Exit-LocalPackageModeLock -Lock $heldLock
        }

        $later = Invoke-LocalPackageMode -Mode Health -MarketDate '2026-08-11' -ProjectRoot $sandboxRoot -StepRunner $runner
        $later.status | Should Be 'SUCCESS'
    }

    It 'emits a machine-readable failure summary without invoking side effects for an invalid date' {
        $entry = Join-Path $projectRoot 'scripts\Start-LocalPackage.ps1'
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $entry -Mode Health -MarketDate '2026-02-30'
        $exitCode = $LASTEXITCODE
        $summary = $output | ConvertFrom-Json

        $exitCode | Should Not Be 0
        $summary.mode | Should Be 'Health'
        $summary.status | Should Be 'FAILED'
        $summary.market_date | Should Be '2026-02-30'
        $summary.steps.Count | Should Be 0
        $summary.error | Should Match 'YYYY-MM-DD'
    }

    It 'preserves Unicode arguments and propagates the PowerShell exit code through the BAT launcher' {
        $unicodeDirectory = ([string][char]0x542F) + ([string][char]0x52A8) + ' ' + ([string][char]0x5305)
        $sandboxRoot = Join-Path $TestDrive $unicodeDirectory
        $scriptsRoot = Join-Path $sandboxRoot 'scripts'
        New-Item -ItemType Directory -Path $scriptsRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $projectRoot 'Start-Amazon-BS.bat') -Destination (Join-Path $sandboxRoot 'Start-Amazon-BS.bat')
        $probeScript = @'
param([string]$Mode, [string]$MarketDate, [string]$SnapshotPath, [switch]$SkipEmail)
[IO.File]::WriteAllText($env:LOCAL_PACKAGE_LAUNCHER_PROBE, ([pscustomobject]@{ Mode=$Mode; MarketDate=$MarketDate; SnapshotPath=$SnapshotPath; SkipEmail=[bool]$SkipEmail } | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
exit 23
'@
        [IO.File]::WriteAllText((Join-Path $scriptsRoot 'Start-LocalPackage.ps1'), $probeScript, (New-Object Text.UTF8Encoding($false)))
        $probePath = Join-Path $TestDrive 'bat-probe.json'
        $unicodeSnapshot = ([string][char]0x5BFC) + ([string][char]0x5165) + ' ' + ([string][char]0x5FEB) + ([string][char]0x7167) + '.json'
        $snapshotPath = Join-Path $TestDrive $unicodeSnapshot
        $savedProbe = [Environment]::GetEnvironmentVariable('LOCAL_PACKAGE_LAUNCHER_PROBE', 'Process')
        try {
            $env:LOCAL_PACKAGE_LAUNCHER_PROBE = $probePath
            Push-Location -LiteralPath $sandboxRoot
            try {
                & $env:ComSpec /d /c ('Start-Amazon-BS.bat -Mode DailyImport -MarketDate 2026-08-11 -SnapshotPath "{0}" -SkipEmail' -f $snapshotPath) | Out-Null
                $exitCode = $LASTEXITCODE
            }
            finally { Pop-Location }
        }
        finally {
            if ($null -eq $savedProbe) { Remove-Item Env:LOCAL_PACKAGE_LAUNCHER_PROBE -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable('LOCAL_PACKAGE_LAUNCHER_PROBE', $savedProbe, 'Process') }
        }
        $probe = Get-Content -LiteralPath $probePath -Raw -Encoding UTF8 | ConvertFrom-Json

        $exitCode | Should Be 23
        $probe.Mode | Should Be 'DailyImport'
        $probe.MarketDate | Should Be '2026-08-11'
        $probe.SnapshotPath | Should Be $snapshotPath
        $probe.SkipEmail | Should Be $true
    }
}
