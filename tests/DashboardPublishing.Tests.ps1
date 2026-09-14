$projectRoot = Split-Path -Parent $PSScriptRoot

Describe 'Dashboard publishing bundle' {
    function New-TestSellerBundleFiles {
        param([string]$Root)

        $paths = @()
        foreach ($scope in @('overview','pressure_washers','sump_pumps','pressure_washer_accessories')) {
            $path = Join-Path $Root ($scope + '.json')
            [IO.File]::WriteAllText($path, (@{ scope = $scope } | ConvertTo-Json), [Text.Encoding]::UTF8)
            $paths += $path
        }
        $paths
    }

    function New-TestAnalysisReportFiles {
        param([string]$Root)

        $paths = @()
        $evidenceLevel = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5YWF5YiG'))
        $sectionTitle = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('57uT6K665pGY6KaB'))
        $sectionStatement = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5LiJ5Liq5qac5Y2V5Z2H5Li65a6M5pW0IFRvcCAzMOOAgg=='))
        foreach ($scope in @('overview','pressure_washers','sump_pumps','pressure_washer_accessories')) {
            $categoryKey = if ($scope -eq 'overview') { $null } else { $scope }
            $path = Join-Path $Root ("analysis-$scope.json")
            $report = [ordered]@{
                schemaVersion = 'amazon-bs-analysis-report-v1'
                key = "daily/2026-08-24/$scope.json"
                reportKind = 'daily'
                marketDate = '2026-08-24'
                categoryKey = $categoryKey
                generatedAt = '2026-08-25T00:00:00Z'
                generatorVersion = 'rules-v1'
                receiptSha256 = ('a' * 64)
                evidence = [ordered]@{
                    level = $evidenceLevel
                    completeMarketDays = 13
                    sampleSize = 90
                    complete = $true
                    fieldCoverage = [ordered]@{ price = 100.0; rating = 100.0; reviews = 100.0 }
                }
                sections = @([ordered]@{ title = $sectionTitle; statements = @($sectionStatement) })
                contentSha256 = ('b' * 64)
            }
            [IO.File]::WriteAllText($path, ($report | ConvertTo-Json -Depth 10), [Text.Encoding]::UTF8)
            $paths += $path
        }
        $paths
    }

    function New-TestSellerReportFiles {
        param([string]$Root)

        $paths = @()
        foreach ($scope in @('overview','pressure_washers','sump_pumps','pressure_washer_accessories')) {
            $categoryKey = if ($scope -eq 'overview') { $null } else { $scope }
            $path = Join-Path $Root ("seller-$scope.json")
            $report = [ordered]@{
                schemaVersion = 'seller-intelligence-v1'
                key = "seller-alert/daily/2026-08-24/$scope.json"
                reportKind = 'daily'
                profile = 'seller_alert'
                marketDate = '2026-08-24'
                categoryKey = $categoryKey
                generatedAt = '2026-08-25T00:00:00Z'
                generatorVersion = 'seller-rules-v1'
                contentSha256 = ('b' * 64)
                evidence = [ordered]@{ complete=$true; completeMarketDays=13; sampleSize=90; fieldCoverage=[ordered]@{ price=100.0 } }
                signals = @(
                    [ordered]@{ type='rank_move'; asin='B000000001'; currentRank=3; previousRank=8 },
                    [ordered]@{ type='rank_move'; asin='B000000002'; currentRank=5; previousRank=9 }
                )
                sections = @([ordered]@{ title='summary'; statements=@('stable') })
                limitations = @('manual verification')
            }
            [IO.File]::WriteAllText($path, ($report | ConvertTo-Json -Depth 10), [Text.Encoding]::UTF8)
            $paths += $path
        }
        $paths
    }

    function New-TestPublisherHooks {
        param(
            [string[]]$SellerPaths,
            [string]$HealthStatus = 'HEALTHY',
            [System.Collections.ArrayList]$Calls,
            [string]$SellerSyncStatus = 'imported',
            [string]$VerifiedSnapshotSha256 = ('a' * 64)
        )

        $buildSyncBundle = { param($SnapshotPath) [pscustomobject]@{ BundlePath = $SnapshotPath; ReceiptSha256 = ('a' * 64) } }.GetNewClosure()
        $health = { param($MarketDate) [pscustomobject]@{ Status = $HealthStatus } }.GetNewClosure()
        $sellerReports = {
                param($SnapshotPath,$SnapshotsRoot,$ReportKind,$ReportDate)
                [void]$Calls.Add([pscustomobject]@{ Name = 'SellerReports'; ReportKind = $ReportKind; ReportDate = $ReportDate })
                [pscustomobject]@{ Status = 'CREATED'; ReportCount = 4; ReportPaths = $SellerPaths }
            }.GetNewClosure()
        $analysisReports = {
                param($SnapshotPath,$SnapshotsRoot,$ReportKind,$ReportDate)
                [void]$Calls.Add([pscustomobject]@{ Name = 'AnalysisReports'; ReportKind = $ReportKind; ReportDate = $ReportDate })
                [pscustomobject]@{ Status = 'CREATED'; ReportCount = 4; ReportPaths = $SellerPaths }
            }.GetNewClosure()
        $captureReceipt = { param($SnapshotPath) [pscustomobject]@{ valid = $true; actual_snapshot_sha256 = $VerifiedSnapshotSha256 } }.GetNewClosure()
        $rest = {
                param($Uri,$Method,$Headers,$ContentType,$InFile,$Body)
                [void]$Calls.Add([pscustomobject]@{ Name = 'Rest'; Uri = [string]$Uri; Body = $Body; InFile = $InFile })
                if ([string]$Uri -match '/seller-intelligence$') { return [pscustomobject]@{ status = $SellerSyncStatus } }
                return [pscustomobject]@{ status = 'imported'; observations = 90 }
            }.GetNewClosure()
        @{
            BuildSyncBundle = $buildSyncBundle
            Health = $health
            SellerReports = $sellerReports
            AnalysisReports = $analysisReports
            CaptureReceipt = $captureReceipt
            Rest = $rest
        }
    }

    It 'is parseable by Windows PowerShell when the repository file has no UTF-8 BOM' {
        $tokens = $null
        $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1'),
            [ref]$tokens,
            [ref]$parseErrors
        )
        @($parseErrors).Count | Should Be 0
    }

    It 'builds a redacted versioned bundle only after a valid receipt' {
        $script = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\New-DashboardSyncBundle.ps1') -Raw
        $script | Should Match 'Resolve-BestSellersAuthorizedSnapshot'
        $script | Should Match 'Resolve-BestSellersAuthorizedSnapshot[^\r\n]+-RegistryPath \$RegistryPath'
        $script | Should Match 'amazon-bs-dashboard-bundle-v2'
        $script | Should Not Match 'source_config_path|746254487|SMTP'
    }

    It 'uses count-neutral diagnostics for Registry-sized report bundles' {
        $script = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1') -Raw
        $script | Should Not Match 'must contain four unique readable JSON files'
        $script | Should Match 'DashboardExpectedScopedReportCount'
    }

    It 'publishes with a bearer secret without embedding its value' {
        $script = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1') -Raw
        $script | Should Match 'AMAZON_BS_DASHBOARD_SYNC_SECRET'
        $script | Should Match 'Authorization'
        $script | Should Match 'Bearer'
        $script | Should Not Match 'epgnhkaltingbccf'
    }

    It 'routes selected PDF reports to the report upload endpoint after data publishing' {
        $script = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1') -Raw
        $script | Should Match '/api/sync/v1/reports'
        $script | Should Match 'x-report-kind'
        $script | Should Match 'Get-DashboardReportsToUpload'
        $script | Should Match 'ReportsUploaded'
    }

    It 'generates and uploads verified online analysis reports after the health gate' {
        $script = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1') -Raw
        $script | Should Match 'New-OnlineAnalysisReports\.ps1'
        $script | Should Match '/api/sync/v1/analysis-reports'
        $script | Should Match 'Test-BestSellersDailyOperationalHealth\.ps1'
    }

    It 'builds a payload-free GET request without an empty InFile argument' {
        $httpModule = Join-Path $projectRoot 'src\DashboardPublishHttp.psm1'
        if (Test-Path -LiteralPath $httpModule) { Import-Module $httpModule -Force }

        $parameters = New-DashboardPublishRestParameters -Uri ([uri]'https://example.test/api/public/analysis/report.json') -Method Get -Headers @{} -ContentType 'application/json'

        $parameters.Uri.AbsoluteUri | Should Be 'https://example.test/api/public/analysis/report.json'
        $parameters.Method | Should Be 'Get'
        $parameters.ContainsKey('InFile') | Should Be $false
        $parameters.ContainsKey('Body') | Should Be $false
    }

    It 'encodes JSON request bodies as explicit UTF-8 bytes for Windows PowerShell' {
        Import-Module (Join-Path $projectRoot 'src\DashboardPublishHttp.psm1') -Force
        $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5YWF5YiG'))
        $parameters = New-DashboardPublishRestParameters -Uri 'https://example.test/api' -Method Post -Headers @{} -ContentType 'application/json' -Body ([pscustomobject]@{ level = $text }) -BodyProvided

        ($parameters.Body -is [byte[]]) | Should Be $true
        $parameters.ContentType | Should Be 'application/json; charset=utf-8'
        $roundTrip = [Text.Encoding]::UTF8.GetString($parameters.Body) | ConvertFrom-Json
        [string]$roundTrip.level | Should Be $text
    }

    It 'decodes JSON response bytes as UTF-8 under Windows PowerShell' {
        Import-Module (Join-Path $projectRoot 'src\DashboardPublishHttp.psm1') -Force
        $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5YWF5YiG'))
        $bytes = [Text.Encoding]::UTF8.GetBytes((@{ level = $text } | ConvertTo-Json -Compress))
        $stream = New-Object IO.MemoryStream(,$bytes)
        try {
            $response = [pscustomobject]@{ RawContentStream = $stream; Content = $null }
            $result = ConvertFrom-DashboardUtf8JsonResponse -Response $response

            [string]$result.level | Should Be $text
        }
        finally {
            $stream.Dispose()
        }
    }

    It 'uses basic parsing for non-interactive Windows PowerShell JSON downloads' {
        $script = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1') -Raw

        $script | Should Match "Parameters\.ContainsKey\('UseBasicParsing'\)"
        $script | Should Match 'UseBasicParsing\s*=\s*\$true'
    }

    It 'posts the complete daily analysis cohort in one atomic request' {
        $root = Join-Path $TestDrive 'atomic-daily-analysis-cohort'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $snapshotPath = Join-Path $root 'amazon-bestsellers.json'
        [IO.File]::WriteAllText($snapshotPath, '{}', [Text.Encoding]::UTF8)
        $sellerPaths = @(New-TestSellerBundleFiles -Root $root)
        $analysisPaths = @(New-TestAnalysisReportFiles -Root $root)
        $calls = New-Object System.Collections.ArrayList
        $hooks = New-TestPublisherHooks -SellerPaths $sellerPaths -Calls $calls
        $hooks.AnalysisReports = { param($SnapshotPath,$SnapshotsRoot,$ReportKind,$ReportDate) [pscustomobject]@{ Status='CREATED'; ReportCount=4; ReportPaths=$analysisPaths } }.GetNewClosure()
        $hooks.Rest = {
            param($Uri,$Method,$Headers,$ContentType,$InFile,$Body)
            [void]$calls.Add([pscustomobject]@{ Uri=[string]$Uri; Method=$Method; InFile=$InFile; Body=$Body })
            if ([string]$Uri -match '/seller-intelligence$') { return [pscustomobject]@{ status='imported' } }
            if ([string]$Uri -match '/api/sync/v1/analysis-reports$') { return [pscustomobject]@{ status='imported' } }
            return [pscustomobject]@{ status='imported'; observations=90 }
        }.GetNewClosure()
        [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'test-secret', 'Process')
        try {
            & (Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1') -DashboardUrl 'https://example.test/' -MarketDate '2026-08-24' -ProjectRoot $root -SnapshotsRoot $root -TestHooks $hooks | Out-Null
            $analysisCalls = @($calls | Where-Object { $_.Uri -match '/api/sync/v1/analysis-reports$' })
            $analysisCalls.Count | Should Be 1
            @($analysisCalls[0].Body.reports).Count | Should Be 4
            @($analysisCalls[0].Body.reports.key | Select-Object -Unique).Count | Should Be 4
            [string]::IsNullOrWhiteSpace([string]$analysisCalls[0].InFile) | Should Be $true
        }
        finally {
            [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', $null, 'Process')
        }
    }

    It 'continues after an immutable analysis key conflict only when the public report is semantically equivalent' {
        $root = Join-Path $TestDrive 'equivalent-analysis-conflict'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $snapshotPath = Join-Path $root 'amazon-bestsellers.json'
        [IO.File]::WriteAllText($snapshotPath, '{}', [Text.Encoding]::UTF8)
        $sellerPaths = @(New-TestSellerBundleFiles -Root $root)
        $analysisPaths = @(New-TestAnalysisReportFiles -Root $root)
        $localOverview = Get-Content -LiteralPath $analysisPaths[0] -Raw -Encoding UTF8 | ConvertFrom-Json
        $remoteOverview = Get-Content -LiteralPath $analysisPaths[0] -Raw -Encoding UTF8 | ConvertFrom-Json
        $remoteOverview.generatedAt = '2026-08-25T08:00:00Z'
        $remoteOverview.evidence.fieldCoverage.price = 100
        $remoteOverview.evidence.fieldCoverage.rating = 100
        $remoteOverview.evidence.fieldCoverage.reviews = 100
        $remoteOverview.contentSha256 = ('c' * 64)
        $calls = New-Object System.Collections.ArrayList
        $hooks = New-TestPublisherHooks -SellerPaths $sellerPaths -Calls $calls
        $hooks.AnalysisReports = { param($SnapshotPath,$SnapshotsRoot,$ReportKind,$ReportDate) [pscustomobject]@{ Status='CREATED'; ReportCount=4; ReportPaths=$analysisPaths } }.GetNewClosure()
        $hooks.Rest = {
            param($Uri,$Method,$Headers,$ContentType,$InFile,$Body)
            [void]$calls.Add([pscustomobject]@{ Name='Rest'; Uri=[string]$Uri; Method=$Method; InFile=$InFile })
            if ([string]$Uri -match '/seller-intelligence$') { return [pscustomobject]@{ status='imported' } }
            if ([string]$Uri -match '/api/sync/v1/analysis-reports$') {
                $failure = New-Object System.Exception('{"error":"immutable_key_conflict"}')
                $failure | Add-Member -NotePropertyName StatusCode -NotePropertyValue 409 -Force
                throw $failure
            }
            if ([string]$Uri -match '/api/public/analysis/daily/2026-08-24/.+\.json$') {
                $scope = [IO.Path]::GetFileNameWithoutExtension(([uri]$Uri).AbsolutePath)
                if ($scope -eq 'overview') { return $remoteOverview }
                $remotePath = @($analysisPaths | Where-Object { [IO.Path]::GetFileName([string]$_) -eq "analysis-$scope.json" })[0]
                return Get-Content -LiteralPath $remotePath -Raw -Encoding UTF8 | ConvertFrom-Json
            }
            return [pscustomobject]@{ status='imported'; observations=90 }
        }.GetNewClosure()
        [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'test-secret', 'Process')
        try {
            & (Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1') -DashboardUrl 'https://example.test/' -MarketDate '2026-08-24' -ProjectRoot $root -SnapshotsRoot $root -TestHooks $hooks | Out-Null
            Import-Module (Join-Path $projectRoot 'src\DashboardPublishState.psm1') -Force
            (Read-DashboardPublishState -Root $root -MarketDate '2026-08-24').Status | Should Be 'PUBLISHED'
            @($calls | Where-Object { $_.Method -eq 'Get' -and $_.Uri -match '/api/public/analysis/' }).Count | Should Be 4
        }
        finally {
            [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', $null, 'Process')
        }
    }

    It 'fails an immutable analysis key conflict when the public report has different conclusions' {
        $root = Join-Path $TestDrive 'different-analysis-conflict'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $snapshotPath = Join-Path $root 'amazon-bestsellers.json'
        [IO.File]::WriteAllText($snapshotPath, '{}', [Text.Encoding]::UTF8)
        $sellerPaths = @(New-TestSellerBundleFiles -Root $root)
        $analysisPaths = @(New-TestAnalysisReportFiles -Root $root)
        $remoteOverview = Get-Content -LiteralPath $analysisPaths[0] -Raw -Encoding UTF8 | ConvertFrom-Json
        $remoteOverview.sections[0].statements[0] = 'Different analysis conclusion.'
        $remoteOverview.contentSha256 = ('c' * 64)
        $calls = New-Object System.Collections.ArrayList
        $hooks = New-TestPublisherHooks -SellerPaths $sellerPaths -Calls $calls
        $hooks.AnalysisReports = { param($SnapshotPath,$SnapshotsRoot,$ReportKind,$ReportDate) [pscustomobject]@{ Status='CREATED'; ReportCount=4; ReportPaths=$analysisPaths } }.GetNewClosure()
        $hooks.Rest = {
            param($Uri,$Method,$Headers,$ContentType,$InFile,$Body)
            if ([string]$Uri -match '/seller-intelligence$') { return [pscustomobject]@{ status='imported' } }
            if ([string]$Uri -match '/api/sync/v1/analysis-reports$') {
                $failure = New-Object System.Exception('{"error":"immutable_key_conflict"}')
                $failure | Add-Member -NotePropertyName StatusCode -NotePropertyValue 409 -Force
                throw $failure
            }
            if ([string]$Uri -match '/api/public/analysis/daily/2026-08-24/overview.json$') { return $remoteOverview }
            return [pscustomobject]@{ status='imported'; observations=90 }
        }.GetNewClosure()
        [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'test-secret', 'Process')
        try {
            { & (Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1') -DashboardUrl 'https://example.test/' -MarketDate '2026-08-24' -ProjectRoot $root -SnapshotsRoot $root -TestHooks $hooks | Out-Null } | Should Throw 'Analysis report immutable key conflict is not semantically equivalent.'
        }
        finally {
            [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', $null, 'Process')
        }
    }

    It 'rejects immutable analysis conflicts for distinct finite numbers without decimal narrowing' {
        $numericCases = @(
            @(
                [double]::Parse('0.3', [Globalization.CultureInfo]::InvariantCulture),
                [double]::Parse('0.30000000000000004', [Globalization.CultureInfo]::InvariantCulture)
            ),
            @(
                [double]0,
                [double]::Parse('1e-50', [Globalization.CultureInfo]::InvariantCulture)
            )
        )

        for ($caseIndex = 0; $caseIndex -lt $numericCases.Count; $caseIndex++) {
            $root = Join-Path $TestDrive ("numeric-analysis-conflict-$caseIndex")
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $snapshotPath = Join-Path $root 'amazon-bestsellers.json'
            [IO.File]::WriteAllText($snapshotPath, '{}', [Text.Encoding]::UTF8)
            $sellerPaths = @(New-TestSellerBundleFiles -Root $root)
            $analysisPaths = @(New-TestAnalysisReportFiles -Root $root)
            $localOverview = Get-Content -LiteralPath $analysisPaths[0] -Raw -Encoding UTF8 | ConvertFrom-Json
            $localOverview.evidence.fieldCoverage.price = $numericCases[$caseIndex][0]
            [IO.File]::WriteAllText($analysisPaths[0], ($localOverview | ConvertTo-Json -Depth 10), [Text.Encoding]::UTF8)
            $remoteOverview = Get-Content -LiteralPath $analysisPaths[0] -Raw -Encoding UTF8 | ConvertFrom-Json
            $remoteOverview.evidence.fieldCoverage.price = $numericCases[$caseIndex][1]
            $hooks = New-TestPublisherHooks -SellerPaths $sellerPaths -Calls (New-Object System.Collections.ArrayList)
            $hooks.AnalysisReports = { param($SnapshotPath,$SnapshotsRoot,$ReportKind,$ReportDate) [pscustomobject]@{ Status='CREATED'; ReportCount=4; ReportPaths=$analysisPaths } }.GetNewClosure()
            $hooks.Rest = {
                param($Uri,$Method,$Headers,$ContentType,$InFile,$Body)
                if ([string]$Uri -match '/seller-intelligence$') { return [pscustomobject]@{ status='imported' } }
                if ([string]$Uri -match '/api/sync/v1/analysis-reports$') {
                    $failure = New-Object System.Exception('{"error":"immutable_key_conflict"}')
                    $failure | Add-Member -NotePropertyName StatusCode -NotePropertyValue 409 -Force
                    throw $failure
                }
                if ([string]$Uri -match '/api/public/analysis/daily/2026-08-24/overview.json$') { return $remoteOverview }
                return [pscustomobject]@{ status='imported'; observations=90 }
            }.GetNewClosure()
            [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'test-secret', 'Process')
            try {
                { & (Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1') -DashboardUrl 'https://example.test/' -MarketDate '2026-08-24' -ProjectRoot $root -SnapshotsRoot $root -TestHooks $hooks | Out-Null } | Should Throw 'Analysis report immutable key conflict is not semantically equivalent.'
            }
            finally {
                [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', $null, 'Process')
            }
        }
    }

    It 'keeps seller intelligence outside the existing mail path' {
        (Get-Content (Join-Path $projectRoot 'scripts\New-BestSellersDailyReport.ps1') -Raw) | Should Not Match 'seller-intelligence'
    }

    It 'does not generate or sync seller reports when health is not healthy' {
        $calls = New-Object System.Collections.ArrayList
        $snapshotPath = Join-Path $TestDrive 'amazon-bestsellers.json'
        [IO.File]::WriteAllText($snapshotPath, '{}', [Text.Encoding]::UTF8)
        [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'test-secret', 'Process')
        try {
            {
                & (Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1') -DashboardUrl 'https://example.test/' -MarketDate '2026-08-24' -ProjectRoot $TestDrive -SnapshotsRoot $TestDrive -TestHooks (New-TestPublisherHooks -SellerPaths @() -HealthStatus 'UNHEALTHY' -Calls $calls) | Out-Null
            } | Should Throw 'Operational health must be healthy before dashboard publishing.'
            @($calls | Where-Object { $_.Name -in @('SellerReports','Rest') }).Count | Should Be 0
        }
        finally {
            [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', $null, 'Process')
        }
    }

    It 'sends one parsed daily seller bundle only after healthy and fails before a network call for invalid paths' {
        $calls = New-Object System.Collections.ArrayList
        $snapshotPath = Join-Path $TestDrive 'amazon-bestsellers.json'
        [IO.File]::WriteAllText($snapshotPath, '{}', [Text.Encoding]::UTF8)
        [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'test-secret', 'Process')
        try {
            $paths = @(New-TestSellerBundleFiles -Root $TestDrive)
            & (Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1') -DashboardUrl 'https://example.test/' -MarketDate '2026-08-24' -ProjectRoot $TestDrive -SnapshotsRoot $TestDrive -TestHooks (New-TestPublisherHooks -SellerPaths $paths -Calls $calls) | Out-Null
            $sellerPosts = @($calls | Where-Object { $_.Name -eq 'Rest' -and $_.Uri -match '/seller-intelligence$' })
            $sellerPosts.Count | Should Be 1
            @($sellerPosts[0].Body.reports).Count | Should Be 4
            [string]$sellerPosts[0].Body.receiptSha256 | Should Be ('a' * 64)

            $invalidCalls = New-Object System.Collections.ArrayList
            {
                & (Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1') -DashboardUrl 'https://example.test/' -MarketDate '2026-08-24' -ProjectRoot (Join-Path $TestDrive 'invalid') -SnapshotsRoot $TestDrive -TestHooks (New-TestPublisherHooks -SellerPaths @($paths[0],$paths[1],$paths[2],$paths[2]) -Calls $invalidCalls) | Out-Null
            } | Should Throw 'Seller intelligence report paths must contain the Registry-sized set of unique readable JSON files.'
            @($invalidCalls | Where-Object { $_.Name -eq 'Rest' -and $_.Uri -match '/seller-intelligence$' }).Count | Should Be 0

            foreach ($invalidPaths in @(@($paths[0],$paths[1],$paths[2]), @($paths[0],$paths[1],$paths[2],(Join-Path $TestDrive 'missing.json')))) {
                $invalidCalls = New-Object System.Collections.ArrayList
                {
                    & (Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1') -DashboardUrl 'https://example.test/' -MarketDate '2026-08-24' -ProjectRoot (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) -SnapshotsRoot $TestDrive -TestHooks (New-TestPublisherHooks -SellerPaths $invalidPaths -Calls $invalidCalls) | Out-Null
                } | Should Throw 'Seller intelligence report paths must contain the Registry-sized set of unique readable JSON files.'
                @($invalidCalls | Where-Object { $_.Name -eq 'Rest' -and $_.Uri -match '/seller-intelligence$' }).Count | Should Be 0
            }
        }
        finally {
            [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', $null, 'Process')
        }
    }

    It 'marks dashboard publication failed when the seller bundle response is not accepted' {
        $calls = New-Object System.Collections.ArrayList
        $snapshotPath = Join-Path $TestDrive 'amazon-bestsellers.json'
        [IO.File]::WriteAllText($snapshotPath, '{}', [Text.Encoding]::UTF8)
        $paths = @(New-TestSellerBundleFiles -Root $TestDrive)
        [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'test-secret', 'Process')
        try {
            {
                & (Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1') -DashboardUrl 'https://example.test/' -MarketDate '2026-08-24' -ProjectRoot $TestDrive -SnapshotsRoot $TestDrive -TestHooks (New-TestPublisherHooks -SellerPaths $paths -Calls $calls -SellerSyncStatus 'rejected') | Out-Null
            } | Should Throw 'Unexpected seller intelligence sync result.'
            Import-Module (Join-Path $projectRoot 'src\DashboardPublishState.psm1') -Force
            (Read-DashboardPublishState -Root $TestDrive -MarketDate '2026-08-24').Status | Should Be 'FAILED'
        }
        finally {
            [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', $null, 'Process')
        }
    }

    It 'does not upload daily seller reports when the snapshot changes during report generation' {
        $calls = New-Object System.Collections.ArrayList
        $snapshotPath = Join-Path $TestDrive 'amazon-bestsellers.json'
        [IO.File]::WriteAllText($snapshotPath, '{}', [Text.Encoding]::UTF8)
        $paths = @(New-TestSellerBundleFiles -Root $TestDrive)
        [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'test-secret', 'Process')
        try {
            {
                & (Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1') -DashboardUrl 'https://example.test/' -MarketDate '2026-08-24' -ProjectRoot $TestDrive -SnapshotsRoot $TestDrive -TestHooks (New-TestPublisherHooks -SellerPaths $paths -Calls $calls -VerifiedSnapshotSha256 ('b' * 64)) | Out-Null
            } | Should Throw 'Daily seller intelligence snapshot receipt changed during report generation.'
            @($calls | Where-Object { $_.Name -eq 'Rest' -and $_.Uri -match '/seller-intelligence$' }).Count | Should Be 0
        }
        finally {
            [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', $null, 'Process')
        }
    }

    It 'generates the weekly seller bundle only when the matching Beijing weekly JSON exists' {
        $calls = New-Object System.Collections.ArrayList
        $snapshotPath = Join-Path $TestDrive 'amazon-bestsellers.json'
        [IO.File]::WriteAllText($snapshotPath, '{}', [Text.Encoding]::UTF8)
        $chinaTimeZone = [TimeZoneInfo]::FindSystemTimeZoneById('China Standard Time')
        $beijingDate = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $chinaTimeZone).ToString('yyyy-MM-dd')
        $weeklyDirectory = Join-Path (Join-Path (Join-Path $TestDrive 'var\reports') 'weekly') $beijingDate
        New-Item -ItemType Directory -Path $weeklyDirectory -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $weeklyDirectory 'Amazon_US_Weekly_Best_Sellers_Analysis_fixture.json'), '{}', [Text.Encoding]::UTF8)
        [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'test-secret', 'Process')
        try {
            & (Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1') -DashboardUrl 'https://example.test/' -MarketDate '2026-08-24' -ProjectRoot $TestDrive -SnapshotsRoot $TestDrive -TestHooks (New-TestPublisherHooks -SellerPaths @(New-TestSellerBundleFiles -Root $TestDrive) -Calls $calls) | Out-Null
            $weeklyRun = @($calls | Where-Object { $_.Name -eq 'SellerReports' -and $_.ReportKind -eq 'Weekly' })
            $weeklyRun.Count | Should Be 1
            $weeklyRun[0].ReportDate | Should Be '2026-08-24'
            $weeklyAnalysisRun = @($calls | Where-Object { $_.Name -eq 'AnalysisReports' -and $_.ReportKind -eq 'Weekly' })
            $weeklyAnalysisRun.Count | Should Be 1
            $weeklyAnalysisRun[0].ReportDate | Should Be '2026-08-24'
        }
        finally {
            [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', $null, 'Process')
        }
    }

    It 'does not generate or post a weekly seller bundle when the Beijing weekly directory is absent' {
        $sandboxRoot = Join-Path $TestDrive 'weekly-directory-absent'
        New-Item -ItemType Directory -Path $sandboxRoot -Force | Out-Null
        $calls = New-Object System.Collections.ArrayList
        $snapshotPath = Join-Path $sandboxRoot 'amazon-bestsellers.json'
        [IO.File]::WriteAllText($snapshotPath, '{}', [Text.Encoding]::UTF8)
        [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'test-secret', 'Process')
        try {
            & (Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1') -DashboardUrl 'https://example.test/' -MarketDate '2026-08-24' -ProjectRoot $sandboxRoot -SnapshotsRoot $sandboxRoot -TestHooks (New-TestPublisherHooks -SellerPaths @(New-TestSellerBundleFiles -Root $sandboxRoot) -Calls $calls) | Out-Null
            @($calls | Where-Object { $_.Name -eq 'SellerReports' -and $_.ReportKind -eq 'Weekly' }).Count | Should Be 0
            @($calls | Where-Object { $_.Name -eq 'Rest' -and $_.Uri -match '/seller-intelligence$' }).Count | Should Be 1
        }
        finally {
            [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', $null, 'Process')
        }
    }

    It 'does not generate or post a weekly seller bundle for another date or a nonmatching file' {
        $sandboxRoot = Join-Path $TestDrive 'weekly-other-or-nonmatching'
        New-Item -ItemType Directory -Path $sandboxRoot -Force | Out-Null
        $calls = New-Object System.Collections.ArrayList
        $snapshotPath = Join-Path $sandboxRoot 'amazon-bestsellers.json'
        [IO.File]::WriteAllText($snapshotPath, '{}', [Text.Encoding]::UTF8)
        $chinaTimeZone = [TimeZoneInfo]::FindSystemTimeZoneById('China Standard Time')
        $beijingDate = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $chinaTimeZone).ToString('yyyy-MM-dd')
        $otherDate = ([DateTime]::ParseExact($beijingDate, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).AddDays(-1)).ToString('yyyy-MM-dd')
        $otherDirectory = Join-Path (Join-Path (Join-Path $sandboxRoot 'var\reports') 'weekly') $otherDate
        $beijingDirectory = Join-Path (Join-Path (Join-Path $sandboxRoot 'var\reports') 'weekly') $beijingDate
        New-Item -ItemType Directory -Path $otherDirectory -Force | Out-Null
        New-Item -ItemType Directory -Path $beijingDirectory -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $otherDirectory 'Amazon_US_Weekly_Best_Sellers_Analysis_fixture.json'), '{}', [Text.Encoding]::UTF8)
        [IO.File]::WriteAllText((Join-Path $beijingDirectory 'not-a-weekly-analysis.json'), '{}', [Text.Encoding]::UTF8)
        [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'test-secret', 'Process')
        try {
            & (Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1') -DashboardUrl 'https://example.test/' -MarketDate '2026-08-24' -ProjectRoot $sandboxRoot -SnapshotsRoot $sandboxRoot -TestHooks (New-TestPublisherHooks -SellerPaths @(New-TestSellerBundleFiles -Root $sandboxRoot) -Calls $calls) | Out-Null
            @($calls | Where-Object { $_.Name -eq 'SellerReports' -and $_.ReportKind -eq 'Weekly' }).Count | Should Be 0
            @($calls | Where-Object { $_.Name -eq 'Rest' -and $_.Uri -match '/seller-intelligence$' }).Count | Should Be 1
        }
        finally {
            [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', $null, 'Process')
        }
    }

    It 'registers an independent daily 09:00 Beijing publishing task' {
        $script = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\Register-DashboardPublishScheduledTask.ps1') -Raw
        $script | Should Match "At\s+'09:00'"
        $script | Should Match 'China Standard Time'
        $script | Should Match 'Amazon-BS-Dashboard-Publish-0900'
    }

    It 'defines primary and recovery tasks with safe concurrent-run handling' {
        $script = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\Register-DashboardPublishScheduledTask.ps1') -Raw

        $script | Should Match 'Get-Command pwsh\.exe'
        $script | Should Match 'WindowsPowerShell\\v1\.0\\powershell\.exe'
        $script | Should Match 'Amazon-BS-Dashboard-Publish-Recovery-0915'
        $script | Should Match "At\s+'09:15'"
        $script | Should Match 'IgnoreNew'
        $script | Should Match 'Invoke-DashboardPublishRecovery\.ps1'
    }

    It 'uses the bounded HTTP1.1 curl transport for live dashboard requests' {
        $script = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1') -Raw
        $httpModule = Get-Content -LiteralPath (Join-Path $projectRoot 'src\DashboardPublishHttp.psm1') -Raw

        $script | Should Match 'Invoke-DashboardPublishCurlRest'
        $httpModule | Should Match "'--http1\.1'"
        $httpModule | Should Match "'--max-time',\s*'180'"
        $httpModule | Should Match "'--retry',\s*'3',\s*'--retry-all-errors'"
    }

    It 'registers dashboard tasks that can wake and continue on battery power' {
        Mock -CommandName New-ScheduledTaskPrincipal -MockWith { New-CimInstance -ClientOnly -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName 'MSFT_TaskPrincipal' }
        Mock -CommandName New-ScheduledTaskSettingsSet -MockWith { New-CimInstance -ClientOnly -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName 'MSFT_TaskSettings' }
        Mock -CommandName New-ScheduledTaskAction -MockWith { New-CimInstance -ClientOnly -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName 'MSFT_TaskAction' }
        Mock -CommandName New-ScheduledTaskTrigger -MockWith { New-CimInstance -ClientOnly -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName 'MSFT_TaskTrigger' }
        Mock -CommandName New-ScheduledTask -MockWith { New-CimInstance -ClientOnly -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName 'MSFT_ScheduledTask' }
        Mock -CommandName Register-ScheduledTask -MockWith { $null }

        & (Join-Path $projectRoot 'scripts\Register-DashboardPublishScheduledTask.ps1') -DashboardUrl 'https://example.test/' | Out-Null

        Assert-MockCalled -CommandName New-ScheduledTaskSettingsSet -Times 1 -Exactly -ParameterFilter {
            $StartWhenAvailable -and $WakeToRun -and $AllowStartIfOnBatteries -and $DontStopIfGoingOnBatteries -and
            $MultipleInstances -eq 'IgnoreNew' -and $ExecutionTimeLimit.TotalMinutes -eq 120
        }
        Assert-MockCalled -CommandName Register-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskName -eq 'Amazon-BS-Dashboard-Publish-0900' -and $Force }
        Assert-MockCalled -CommandName Register-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskName -eq 'Amazon-BS-Dashboard-Publish-Recovery-0915' -and $Force }
    }

    It 'continues after an immutable seller key conflict only when all public reports are semantically equivalent' {
        $root = Join-Path $TestDrive 'equivalent-seller-conflict'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $snapshotPath = Join-Path $root 'amazon-bestsellers.json'
        [IO.File]::WriteAllText($snapshotPath, '{}', [Text.Encoding]::UTF8)
        $sellerPaths = @(New-TestSellerReportFiles -Root $root)
        $calls = New-Object System.Collections.ArrayList
        $hooks = New-TestPublisherHooks -SellerPaths $sellerPaths -Calls $calls
        $hooks.Rest = {
            param($Uri,$Method,$Headers,$ContentType,$InFile,$Body)
            [void]$calls.Add([pscustomobject]@{ Uri=[string]$Uri; Method=$Method })
            if ($Method -eq 'Post' -and [string]$Uri -match '/seller-intelligence$') {
                $failure = New-Object System.Exception('{"error":"immutable_key_conflict"}')
                $failure | Add-Member -NotePropertyName StatusCode -NotePropertyValue 409 -Force
                throw $failure
            }
            if ($Method -eq 'Get' -and [string]$Uri -match '/api/public/seller-intelligence/') {
                $scope = [IO.Path]::GetFileNameWithoutExtension(([uri]$Uri).AbsolutePath)
                $path = @($sellerPaths | Where-Object { [IO.Path]::GetFileName([string]$_) -eq "seller-$scope.json" })[0]
                $remote = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
                $remote.generatedAt = '2026-08-25T08:00:00+08:00'
                $remote.contentSha256 = ('c' * 64)
                $remote.signals = @($remote.signals | Sort-Object asin -Descending)
                $remote | Add-Member -NotePropertyName receiptSha256 -NotePropertyValue ('a' * 64) -Force
                return $remote
            }
            return [pscustomobject]@{ status='imported'; observations=90 }
        }.GetNewClosure()
        [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'test-secret', 'Process')
        try {
            & (Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1') -DashboardUrl 'https://example.test/' -MarketDate '2026-08-24' -ProjectRoot $root -SnapshotsRoot $root -TestHooks $hooks | Out-Null
            Import-Module (Join-Path $projectRoot 'src\DashboardPublishState.psm1') -Force
            (Read-DashboardPublishState -Root $root -MarketDate '2026-08-24').Status | Should Be 'PUBLISHED'
            @($calls | Where-Object { $_.Method -eq 'Get' -and $_.Uri -match '/api/public/seller-intelligence/' }).Count | Should Be 4
        }
        finally {
            [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', $null, 'Process')
        }
    }

    It 'fails an immutable seller key conflict when a public report has different evidence' {
        $root = Join-Path $TestDrive 'different-seller-conflict'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $snapshotPath = Join-Path $root 'amazon-bestsellers.json'
        [IO.File]::WriteAllText($snapshotPath, '{}', [Text.Encoding]::UTF8)
        $sellerPaths = @(New-TestSellerReportFiles -Root $root)
        $calls = New-Object System.Collections.ArrayList
        $hooks = New-TestPublisherHooks -SellerPaths $sellerPaths -Calls $calls
        $hooks.Rest = {
            param($Uri,$Method,$Headers,$ContentType,$InFile,$Body)
            if ($Method -eq 'Post' -and [string]$Uri -match '/seller-intelligence$') {
                $failure = New-Object System.Exception('{"error":"immutable_key_conflict"}')
                $failure | Add-Member -NotePropertyName StatusCode -NotePropertyValue 409 -Force
                throw $failure
            }
            if ($Method -eq 'Get' -and [string]$Uri -match '/api/public/seller-intelligence/') {
                $scope = [IO.Path]::GetFileNameWithoutExtension(([uri]$Uri).AbsolutePath)
                $path = @($sellerPaths | Where-Object { [IO.Path]::GetFileName([string]$_) -eq "seller-$scope.json" })[0]
                $remote = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
                $remote | Add-Member -NotePropertyName receiptSha256 -NotePropertyValue ('a' * 64) -Force
                if ($scope -eq 'overview') { $remote.evidence.sampleSize = 89 }
                return $remote
            }
            return [pscustomobject]@{ status='imported'; observations=90 }
        }.GetNewClosure()
        [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'test-secret', 'Process')
        try {
            { & (Join-Path $projectRoot 'scripts\Publish-BestSellersDashboard.ps1') -DashboardUrl 'https://example.test/' -MarketDate '2026-08-24' -ProjectRoot $root -SnapshotsRoot $root -TestHooks $hooks | Out-Null } | Should Throw 'Seller intelligence report immutable key conflict is not semantically equivalent.'
        }
        finally {
            [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', $null, 'Process')
        }
    }

    It 'injects a DPAPI-protected sync secret only for the scheduled publish operation' {
        Add-Type -AssemblyName System.Security
        $wrapper = Join-Path $projectRoot 'scripts\Invoke-ProtectedDashboardPublish.ps1'
        $protectedPath = Join-Path $TestDrive 'dashboard-sync-secret.dpapi'
        $secret = 'a' * 64
        $plainBytes = [Text.Encoding]::UTF8.GetBytes($secret)
        try {
            $protectedBytes = [Security.Cryptography.ProtectedData]::Protect(
                $plainBytes,
                $null,
                [Security.Cryptography.DataProtectionScope]::CurrentUser
            )
            [IO.File]::WriteAllBytes($protectedPath, $protectedBytes)
        }
        finally {
            [Array]::Clear($plainBytes, 0, $plainBytes.Length)
        }

        $previous = [Environment]::GetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'Process')
        [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', $null, 'Process')
        try {
            $result = & $wrapper -Mode Publish -DashboardUrl 'https://example.test/' -MarketDate '2026-09-09' -ProtectedSecretPath $protectedPath -Operation {
                param($Mode, $DashboardUrl, $MarketDate)
                [pscustomobject]@{
                    Mode = $Mode
                    MarketDate = $MarketDate
                    DashboardUrl = $DashboardUrl.AbsoluteUri
                    Secret = [Environment]::GetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'Process')
                }
            }

            $result.Mode | Should Be 'Publish'
            $result.MarketDate | Should Be '2026-09-09'
            $result.DashboardUrl | Should Be 'https://example.test/'
            $result.Secret | Should Be $secret
            [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', 'Process')) | Should Be $true
        }
        finally {
            [Environment]::SetEnvironmentVariable('AMAZON_BS_DASHBOARD_SYNC_SECRET', $previous, 'Process')
        }
    }

    It 'registers both dashboard tasks through the protected-secret launcher' {
        $script = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\Register-DashboardPublishScheduledTask.ps1') -Raw

        $script | Should Match 'Invoke-ProtectedDashboardPublish\.ps1'
        $script | Should Match '-Mode Publish'
        $script | Should Match '-Mode Recovery'
    }

    It 'propagates the interactive HTTPS proxy into scheduled publishing' {
        $registerScript = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\Register-DashboardPublishScheduledTask.ps1') -Raw
        $launcherScript = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\Invoke-ProtectedDashboardPublish.ps1') -Raw

        $registerScript | Should Match 'HTTPS_PROXY'
        $registerScript | Should Match '-ProxyUrl'
        $launcherScript | Should Match 'ProxyUrl'
        $launcherScript | Should Match 'http_proxy'
    }
}
