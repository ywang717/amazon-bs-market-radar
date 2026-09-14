$projectRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $projectRoot 'src\LocalPackageSetup.psm1'

function New-TestRuntimeManifest {
    param(
        [string]$Root,
        [string]$PythonHash = ('A' * 64),
        [string]$PostgresHash = ('B' * 64),
        [string]$ChromiumHash = ('C' * 64)
    )
    $configRoot = Join-Path $Root 'config'
    New-Item -ItemType Directory -Path $configRoot -Force | Out-Null
    $manifest = [ordered]@{
        schema_version = 'local-package-runtime-v1'
        platform = 'windows-x64'
        components = [ordered]@{
            python = [ordered]@{
                identifier = 'python-3.12.10-windows-x64-installer'
                filename = 'python-3.12.10-amd64.exe'
                url = 'https://example.test/python.exe'
                sha256 = $PythonHash
                checksum_verified = $true
                destination_path = '.local\python'
                expected_path = '.local\python\python.exe'
            }
            postgresql = [ordered]@{
                identifier = 'postgresql-18.4-windows-x64-binaries'
                filename = 'postgresql-18.4-windows-x64-binaries.zip'
                url = 'https://example.test/postgresql.zip'
                sha256 = $PostgresHash
                checksum_verified = $true
                destination_path = '.local\postgresql'
                expected_path = '.local\postgresql\bin\initdb.exe'
                archive_root = 'pgsql'
            }
            playwright_chromium = [ordered]@{
                identifier = 'playwright-1.49.1-chromium-1148-windows-x64'
                filename = 'chromium-1148-win64.zip'
                url = 'https://example.test/chromium.zip'
                sha256 = $ChromiumHash
                checksum_verified = $true
                destination_path = '.local\playwright'
                expected_path = '.local\playwright\chromium-1148\chrome-win\chrome.exe'
                archive_root = 'chromium-1148'
            }
        }
    }
    $path = Join-Path $configRoot 'manifest.json'
    [IO.File]::WriteAllText($path, ($manifest | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
    return $path
}

function New-TestSetupSeams {
    param(
        [System.Collections.ArrayList]$Calls,
        [string]$PythonHash = ('A' * 64),
        [string]$PostgresHash = ('B' * 64),
        [string]$ChromiumHash = ('C' * 64),
        [string]$Browser = 'Edge'
    )
    return @{
        DownloadFile = {
            param([string]$Uri, [string]$Destination)
            [void]$Calls.Add([pscustomobject]@{ Operation = 'Download'; Uri = $Uri; Path = $Destination })
            New-Item -ItemType File -Path $Destination -Force | Out-Null
        }.GetNewClosure()
        GetFileHash = {
            param([string]$Path)
            if ($Path -like '*python*') { return $PythonHash }
            if ($Path -like '*postgresql*') { return $PostgresHash }
            return $ChromiumHash
        }.GetNewClosure()
        InstallPython = {
            param([string]$InstallerPath, [string]$DestinationRoot)
            [void]$Calls.Add([pscustomobject]@{ Operation = 'InstallPython'; Source = $InstallerPath; Destination = $DestinationRoot })
            New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $DestinationRoot 'python.exe') -Force | Out-Null
            return 0
        }.GetNewClosure()
        InitializePythonEnvironment = {
            param([string]$ScriptPath, [string]$ProjectRoot)
            [void]$Calls.Add([pscustomobject]@{ Operation = 'InitializePythonEnvironment'; ProjectRoot = $ProjectRoot })
            $venvScripts = Join-Path $ProjectRoot '.venv\Scripts'
            New-Item -ItemType Directory -Path $venvScripts -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $venvScripts 'python.exe') -Force | Out-Null
            return 0
        }.GetNewClosure()
        ExtractArchive = {
            param([string]$ArchivePath, [string]$StagingRoot)
            [void]$Calls.Add([pscustomobject]@{ Operation = 'ExtractPostgres'; Source = $ArchivePath; Destination = $StagingRoot })
            $bin = Join-Path $StagingRoot 'pgsql\bin'
            New-Item -ItemType Directory -Path $bin -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $bin 'initdb.exe') -Force | Out-Null
        }.GetNewClosure()
        PromoteDirectory = {
            param([string]$Source, [string]$Destination)
            [void]$Calls.Add([pscustomobject]@{ Operation = 'PromotePostgres'; Source = $Source; Destination = $Destination })
            Move-Item -LiteralPath $Source -Destination $Destination
        }.GetNewClosure()
        InitializeDatabase = {
            param([string]$ScriptPath, [string]$InstallRoot, [string]$DataRoot, [string]$SettingsPath)
            [void]$Calls.Add([pscustomobject]@{ Operation = 'InitializeDatabase'; InstallRoot = $InstallRoot; DataRoot = $DataRoot })
            New-Item -ItemType Directory -Path $DataRoot -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $DataRoot 'PG_VERSION') -Force | Out-Null
            [IO.File]::WriteAllText($SettingsPath, '{"password":"database-secret"}', (New-Object Text.UTF8Encoding($false)))
            return 0
        }.GetNewClosure()
        RunMigrations = {
            param([string]$ScriptPath, [string]$SettingsPath)
            [void]$Calls.Add([pscustomobject]@{ Operation = 'RunMigrations'; SettingsPath = $SettingsPath })
            return 0
        }.GetNewClosure()
        FindSystemBrowser = { return $Browser }.GetNewClosure()
        VerifyPythonComponent = {
            param([string]$Path, [string]$Identifier)
            [void]$Calls.Add([pscustomobject]@{ Operation = 'VerifyPython'; Path = $Path; Identifier = $Identifier })
            return $true
        }.GetNewClosure()
        VerifyPostgresComponent = {
            param([string]$Path, [string]$Identifier)
            [void]$Calls.Add([pscustomobject]@{ Operation = 'VerifyPostgres'; Path = $Path; Identifier = $Identifier })
            return $true
        }.GetNewClosure()
        VerifyChromiumComponent = {
            param([string]$Path, [string]$Identifier)
            [void]$Calls.Add([pscustomobject]@{ Operation = 'VerifyChromium'; Path = $Path; Identifier = $Identifier })
            return $true
        }.GetNewClosure()
        InstallChromium = {
            param([string]$ArchivePath, [string]$StagingRoot, [string]$DestinationRoot, [string]$ArchiveRoot)
            [void]$Calls.Add([pscustomobject]@{ Operation = 'InstallChromium'; Source = $ArchivePath; Destination = $DestinationRoot })
            $chromeRoot = Join-Path (Join-Path $DestinationRoot $ArchiveRoot) 'chrome-win'
            New-Item -ItemType Directory -Path $chromeRoot -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $chromeRoot 'chrome.exe') -Force | Out-Null
        }.GetNewClosure()
    }
}

Describe 'Local package runtime manifest validation' {
    BeforeAll { Import-Module $modulePath -Force }

    It 'accepts the complete Windows x64 runtime manifest and resolves all destinations below the project' {
        $root = Join-Path $TestDrive 'valid-manifest'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $validated = Test-LocalPackageRuntimeManifest -ManifestPath (New-TestRuntimeManifest -Root $root) -ProjectRoot $root

        $validated.Platform | Should Be 'windows-x64'
        $validated.Components.python.DestinationPath | Should Be (Join-Path $root '.local\python')
        $validated.Components.postgresql.ExpectedPath | Should Be (Join-Path $root '.local\postgresql\bin\initdb.exe')
        $validated.Components.playwright_chromium.DestinationPath | Should Be (Join-Path $root '.local\playwright')
    }

    It 'rejects an incomplete or unsupported manifest schema' {
        $root = Join-Path $TestDrive 'bad-schema'
        $path = New-TestRuntimeManifest -Root $root
        $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $manifest.schema_version = 'future-v9'
        [IO.File]::WriteAllText($path, ($manifest | ConvertTo-Json -Depth 8))

        $failure = $null
        try { Test-LocalPackageRuntimeManifest -ManifestPath $path -ProjectRoot $root }
        catch { $failure = $_ }
        $failure | Should Not Be $null
        $failure.Exception.Message | Should Match 'schema_version'
    }

    It 'rejects non-HTTPS URLs, unsafe leaf filenames, traversal paths, and malformed hashes' {
        $root = Join-Path $TestDrive 'unsafe-manifests'
        foreach ($case in @(
            @{ Name = 'url'; Value = 'http://example.test/python.exe' },
            @{ Name = 'filename'; Value = '..\python.exe' },
            @{ Name = 'expected_path'; Value = '..\outside.exe' },
            @{ Name = 'sha256'; Value = 'not-a-sha256' }
        )) {
            $path = New-TestRuntimeManifest -Root $root
            $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            $manifest.components.python.($case.Name) = $case.Value
            [IO.File]::WriteAllText($path, ($manifest | ConvertTo-Json -Depth 8))

            $failure = $null
            try { Test-LocalPackageRuntimeManifest -ManifestPath $path -ProjectRoot $root | Out-Null }
            catch { $failure = $_ }
            $failure | Should Not Be $null
        }
    }

    It 'rejects Windows reserved names and names or path segments ending in a dot or space' {
        $root = Join-Path $TestDrive 'windows-unsafe-names'
        foreach ($case in @(
            @{ Property = 'filename'; Value = 'CON.exe' },
            @{ Property = 'filename'; Value = 'python.exe.' },
            @{ Property = 'destination_path'; Value = '.local\NUL\python' },
            @{ Property = 'expected_path'; Value = '.local\python.\python.exe' }
        )) {
            $path = New-TestRuntimeManifest -Root $root
            $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            $manifest.components.python.($case.Property) = $case.Value
            [IO.File]::WriteAllText($path, ($manifest | ConvertTo-Json -Depth 8))
            $failure = $null
            try { Test-LocalPackageRuntimeManifest -ManifestPath $path -ProjectRoot $root | Out-Null }
            catch { $failure = $_ }
            $failure | Should Not Be $null
        }
    }

    It 'rejects a manifest path that crosses an existing reparse point through an injected filesystem seam' {
        $root = Join-Path $TestDrive 'reparse-project'
        $path = New-TestRuntimeManifest -Root $root
        $attributeReader = {
            param([string]$Candidate)
            if ((Split-Path -Leaf $Candidate) -eq '.local') { return [IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint }
            return [IO.FileAttributes]::Directory
        }

        $failure = $null
        try { Test-LocalPackageRuntimeManifest -ManifestPath $path -ProjectRoot $root -GetPathAttributes $attributeReader | Out-Null }
        catch { $failure = $_ }
        $failure | Should Not Be $null
    }
}

Describe 'Local package setup behavior' {
    BeforeAll { Import-Module $modulePath -Force }

    It 'blocks Python installation when the downloaded checksum mismatches' {
        $root = Join-Path $TestDrive 'python-hash-mismatch'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $manifest = New-TestRuntimeManifest -Root $root
        $calls = New-Object System.Collections.ArrayList
        $seams = New-TestSetupSeams -Calls $calls -PythonHash ('F' * 64)

        $summary = Invoke-LocalPackageSetup -ProjectRoot $root -ManifestPath $manifest @seams

        $summary.status | Should Be 'FAILED'
        $summary.errors -join ' ' | Should Match 'checksum'
        @($calls | Where-Object Operation -eq 'InstallPython').Count | Should Be 0
        @($calls | Where-Object Operation -eq 'ExtractPostgres').Count | Should Be 0
    }

    It 'blocks PostgreSQL extraction when the downloaded checksum mismatches' {
        $root = Join-Path $TestDrive 'postgres-hash-mismatch'
        New-Item -ItemType Directory -Path (Join-Path $root '.local\python') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $root '.local\python\python.exe') -Force | Out-Null
        $manifest = New-TestRuntimeManifest -Root $root
        $calls = New-Object System.Collections.ArrayList
        $seams = New-TestSetupSeams -Calls $calls -PostgresHash ('F' * 64)

        $summary = Invoke-LocalPackageSetup -ProjectRoot $root -ManifestPath $manifest @seams

        $summary.status | Should Be 'FAILED'
        @($calls | Where-Object Operation -eq 'ExtractPostgres').Count | Should Be 0
        @($calls | Where-Object Operation -eq 'InitializeDatabase').Count | Should Be 0
    }

    It 'blocks Chromium installation when the downloaded checksum mismatches' {
        $root = Join-Path $TestDrive 'chromium-hash-mismatch'
        foreach ($path in @('.local\python\python.exe', '.local\postgresql\bin\initdb.exe', '.local\postgres-data\PG_VERSION', '.local\postgres-settings.json')) {
            $full = Join-Path $root $path
            New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
            New-Item -ItemType File -Path $full -Force | Out-Null
        }
        $calls = New-Object System.Collections.ArrayList
        $seams = New-TestSetupSeams -Calls $calls -Browser $null -ChromiumHash ('F' * 64)

        $summary = Invoke-LocalPackageSetup -ProjectRoot $root -ManifestPath (New-TestRuntimeManifest -Root $root) @seams

        $summary.status | Should Be 'FAILED'
        $summary.errors -join ' ' | Should Match 'checksum'
        @($calls | Where-Object Operation -eq 'InstallChromium').Count | Should Be 0
    }

    It 'compares SHA-256 values case-insensitively' {
        $root = Join-Path $TestDrive 'case-insensitive-hash'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $calls = New-Object System.Collections.ArrayList
        $seams = New-TestSetupSeams -Calls $calls -PythonHash ('a' * 64) -PostgresHash ('b' * 64) -Browser 'Edge'

        $summary = Invoke-LocalPackageSetup -ProjectRoot $root -ManifestPath (New-TestRuntimeManifest -Root $root) @seams

        $summary.status | Should Be 'READY'
        @($calls | Where-Object Operation -eq 'InstallPython').Count | Should Be 1
        @($calls | Where-Object Operation -eq 'ExtractPostgres').Count | Should Be 1
    }

    It 'uses only per-project Python, PostgreSQL, virtual-environment, download, and browser destinations' {
        $root = Join-Path $TestDrive 'per-project'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $calls = New-Object System.Collections.ArrayList
        $seams = New-TestSetupSeams -Calls $calls -Browser $null

        $summary = Invoke-LocalPackageSetup -ProjectRoot $root -ManifestPath (New-TestRuntimeManifest -Root $root) @seams

        $summary.status | Should Be 'READY'
        $summary.paths.python | Should Be (Join-Path $root '.local\python\python.exe')
        $summary.paths.postgresql | Should Be (Join-Path $root '.local\postgresql\bin\initdb.exe')
        $summary.paths.venv | Should Be (Join-Path $root '.venv\Scripts\python.exe')
        $summary.paths.playwright | Should Be (Join-Path $root '.local\playwright')
        foreach ($call in $calls) {
            foreach ($property in @('Path','Source','Destination','ProjectRoot','InstallRoot','DataRoot','SettingsPath')) {
                if ($null -ne $call.PSObject.Properties[$property] -and -not [string]::IsNullOrWhiteSpace([string]$call.$property)) {
                    [IO.Path]::GetFullPath([string]$call.$property).StartsWith([IO.Path]::GetFullPath($root), [StringComparison]::OrdinalIgnoreCase) | Should Be $true
                }
            }
        }
    }

    It 'retains existing verified components and never overwrites user data' {
        $root = Join-Path $TestDrive 'idempotent'
        foreach ($path in @(
            '.local\python\python.exe', '.venv\Scripts\python.exe', '.local\postgresql\bin\initdb.exe',
            '.local\postgres-data\PG_VERSION', '.local\postgres-settings.json',
            'var\reports\keep.txt', '.local\postgres-backups\keep.dump'
        )) {
            $full = Join-Path $root $path
            New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
            [IO.File]::WriteAllText($full, "keep:$path")
        }
        $calls = New-Object System.Collections.ArrayList
        $seams = New-TestSetupSeams -Calls $calls -Browser 'Chrome'

        $summary = Invoke-LocalPackageSetup -ProjectRoot $root -ManifestPath (New-TestRuntimeManifest -Root $root) @seams

        $summary.status | Should Be 'READY'
        @($calls | Where-Object Operation -in @('Download','InstallPython','ExtractPostgres','PromotePostgres','InitializeDatabase','InstallChromium')).Count | Should Be 0
        @($calls | Where-Object Operation -eq 'RunMigrations').Count | Should Be 1
        (Get-Content -Raw (Join-Path $root '.local\postgres-data\PG_VERSION')) | Should Be 'keep:.local\postgres-data\PG_VERSION'
        (Get-Content -Raw (Join-Path $root '.local\postgres-settings.json')) | Should Be 'keep:.local\postgres-settings.json'
        (Get-Content -Raw (Join-Path $root 'var\reports\keep.txt')) | Should Be 'keep:var\reports\keep.txt'
        (Get-Content -Raw (Join-Path $root '.local\postgres-backups\keep.dump')) | Should Be 'keep:.local\postgres-backups\keep.dump'
    }

    It 'reuses a verified PostgreSQL installation referenced by consistent existing settings' {
        $root = Join-Path $TestDrive 'configured-postgres'
        $configuredInstall = Join-Path $TestDrive 'shared-postgresql-18.4'
        $configuredData = Join-Path $TestDrive 'shared-postgres-data'
        foreach ($path in @('.local\python\python.exe')) {
            $full = Join-Path $root $path
            New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
            New-Item -ItemType File -Path $full -Force | Out-Null
        }
        New-Item -ItemType Directory -Path $configuredData -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $configuredData 'PG_VERSION') -Force | Out-Null
        $configuredInitDb = Join-Path $configuredInstall 'bin\initdb.exe'
        New-Item -ItemType Directory -Path (Split-Path -Parent $configuredInitDb) -Force | Out-Null
        New-Item -ItemType File -Path $configuredInitDb -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $root '.local\postgres-settings.json'),([ordered]@{install_root=$configuredInstall;data_root=$configuredData}|ConvertTo-Json -Compress))
        $calls = New-Object System.Collections.ArrayList
        $seams = New-TestSetupSeams -Calls $calls -Browser 'Edge'

        $summary = Invoke-LocalPackageSetup -ProjectRoot $root -ManifestPath (New-TestRuntimeManifest -Root $root -PostgresHash ('0' * 64)) @seams

        $summary.status | Should Be 'READY'
        $summary.components.postgresql.status | Should Be 'RETAINED_CONFIGURED'
        $summary.paths.postgresql | Should Be $configuredInitDb
        @($calls | Where-Object Operation -in @('Download','ExtractPostgres','PromotePostgres','InitializeDatabase')).Count | Should Be 0
        $postgresVerifications = @($calls | Where-Object Operation -eq 'VerifyPostgres')
        $postgresVerifications.Count | Should Be 1
        $postgresVerifications[0].Path | Should Be $configuredInitDb
        @($calls | Where-Object Operation -eq 'RunMigrations').Count | Should Be 1
    }

    It 'validates staged initdb then promotes the archive root into the absent install destination' {
        $root = Join-Path $TestDrive 'staged-promotion'
        New-Item -ItemType Directory -Path (Join-Path $root '.local\python') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $root '.local\python\python.exe') -Force | Out-Null
        $calls = New-Object System.Collections.ArrayList
        $seams = New-TestSetupSeams -Calls $calls -Browser 'Edge'

        $summary = Invoke-LocalPackageSetup -ProjectRoot $root -ManifestPath (New-TestRuntimeManifest -Root $root) @seams

        $summary.components.postgresql.status | Should Be 'INSTALLED'
        Test-Path -LiteralPath (Join-Path $root '.local\postgresql\bin\initdb.exe') | Should Be $true
        $promotion = @($calls | Where-Object Operation -eq 'PromotePostgres')[0]
        $promotion.Source | Should Match '\.local\\postgresql-stage-[^\\]+\\pgsql$'
        $promotion.Destination | Should Be (Join-Path $root '.local\postgresql')
    }

    It 'rejects a staged PostgreSQL archive without initdb before promotion' {
        $root = Join-Path $TestDrive 'missing-staged-marker'
        New-Item -ItemType Directory -Path (Join-Path $root '.local\python') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $root '.local\python\python.exe') -Force | Out-Null
        $calls = New-Object System.Collections.ArrayList
        $seams = New-TestSetupSeams -Calls $calls -Browser 'Edge'
        $seams.ExtractArchive = { param([string]$ArchivePath, [string]$StagingRoot) New-Item -ItemType Directory -Path (Join-Path $StagingRoot 'pgsql\bin') -Force | Out-Null }

        $summary = Invoke-LocalPackageSetup -ProjectRoot $root -ManifestPath (New-TestRuntimeManifest -Root $root) @seams

        $summary.status | Should Be 'FAILED'
        $summary.errors -join ' ' | Should Match 'initdb'
        @($calls | Where-Object Operation -eq 'PromotePostgres').Count | Should Be 0
    }

    It 'initializes and migrates only a brand-new database' {
        $root = Join-Path $TestDrive 'new-database'
        New-Item -ItemType Directory -Path (Join-Path $root '.local\python') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $root '.local\python\python.exe') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root '.local\postgresql\bin') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $root '.local\postgresql\bin\initdb.exe') -Force | Out-Null
        $calls = New-Object System.Collections.ArrayList
        $seams = New-TestSetupSeams -Calls $calls -Browser 'Edge'

        $summary = Invoke-LocalPackageSetup -ProjectRoot $root -ManifestPath (New-TestRuntimeManifest -Root $root) @seams

        @($calls | Where-Object Operation -eq 'InitializeDatabase').Count | Should Be 1
        @($calls | Where-Object Operation -eq 'RunMigrations').Count | Should Be 1
        $summary.database_initialized | Should Be $true
        $summary.migrations_run | Should Be $true
    }

    It 'fails actionably when database settings and PG_VERSION are inconsistent' {
        $root = Join-Path $TestDrive 'existing-database'
        foreach ($path in @('.local\python\python.exe', '.local\postgresql\bin\initdb.exe', '.local\postgres-data\PG_VERSION')) {
            $full = Join-Path $root $path
            New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
            New-Item -ItemType File -Path $full -Force | Out-Null
        }
        $calls = New-Object System.Collections.ArrayList
        $seams = New-TestSetupSeams -Calls $calls -Browser 'Edge'

        $summary = Invoke-LocalPackageSetup -ProjectRoot $root -ManifestPath (New-TestRuntimeManifest -Root $root) @seams

        $summary.status | Should Be 'FAILED'
        $summary.errors -join ' ' | Should Match 'inconsistent'
        @($calls | Where-Object Operation -in @('InitializeDatabase','RunMigrations')).Count | Should Be 0
        Test-Path -LiteralPath (Join-Path $root '.local\postgres-settings.json') | Should Be $false
    }

    It 'retries idempotent migrations for every existing consistent database' {
        $root = Join-Path $TestDrive 'existing-consistent-database'
        foreach ($path in @('.local\python\python.exe', '.local\postgresql\bin\initdb.exe', '.local\postgres-data\PG_VERSION', '.local\postgres-settings.json')) {
            $full = Join-Path $root $path
            New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
            New-Item -ItemType File -Path $full -Force | Out-Null
        }
        $calls = New-Object System.Collections.ArrayList
        $seams = New-TestSetupSeams -Calls $calls -Browser 'Edge'

        $summary = Invoke-LocalPackageSetup -ProjectRoot $root -ManifestPath (New-TestRuntimeManifest -Root $root) @seams

        $summary.status | Should Be 'READY'
        $summary.database_initialized | Should Be $false
        $summary.migrations_run | Should Be $true
        @($calls | Where-Object Operation -eq 'RunMigrations').Count | Should Be 1
    }

    It 'fails when existing component markers do not pass executable verification' {
        foreach ($case in @('Python','Postgres','Chromium')) {
            $root = Join-Path $TestDrive ('stale-' + $case)
            foreach ($path in @('.local\python\python.exe', '.local\postgresql\bin\initdb.exe', '.local\postgres-data\PG_VERSION', '.local\postgres-settings.json', '.local\playwright\chromium-1148\chrome-win\chrome.exe')) {
                $full = Join-Path $root $path
                New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
                New-Item -ItemType File -Path $full -Force | Out-Null
            }
            $calls = New-Object System.Collections.ArrayList
            $seams = New-TestSetupSeams -Calls $calls -Browser $null
            $seams["Verify${case}Component"] = { param([string]$Path, [string]$Identifier) return $false }

            $summary = Invoke-LocalPackageSetup -ProjectRoot $root -ManifestPath (New-TestRuntimeManifest -Root $root) @seams

            $summary.status | Should Be 'FAILED'
            $summary.errors -join ' ' | Should Match 'verification'
        }
    }

    It 'fails on an invalid local Chromium marker even when Edge is available' {
        $root = Join-Path $TestDrive 'stale-chromium-with-edge'
        foreach ($path in @('.local\python\python.exe', '.local\postgresql\bin\initdb.exe', '.local\postgres-data\PG_VERSION', '.local\postgres-settings.json', '.local\playwright\chromium-1148\chrome-win\chrome.exe')) {
            $full = Join-Path $root $path
            New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
            New-Item -ItemType File -Path $full -Force | Out-Null
        }
        $calls = New-Object System.Collections.ArrayList
        $seams = New-TestSetupSeams -Calls $calls -Browser 'Edge'
        $seams.VerifyChromiumComponent = { param([string]$Path, [string]$Identifier) return $false }

        $summary = Invoke-LocalPackageSetup -ProjectRoot $root -ManifestPath (New-TestRuntimeManifest -Root $root) @seams

        $summary.status | Should Be 'FAILED'
        $summary.errors -join ' ' | Should Match 'Chromium.*verification'
    }

    It 'prefers Edge then Chrome and installs local Chromium only when neither system browser exists' {
        foreach ($case in @(
            @{ Browser = 'Edge'; Expected = 'Edge'; Installs = 0 },
            @{ Browser = 'Chrome'; Expected = 'Chrome'; Installs = 0 },
            @{ Browser = $null; Expected = 'PlaywrightChromium'; Installs = 1 }
        )) {
            $root = Join-Path $TestDrive ('browser-' + $case.Expected)
            foreach ($path in @('.local\python\python.exe', '.local\postgresql\bin\initdb.exe', '.local\postgres-data\PG_VERSION', '.local\postgres-settings.json')) {
                $full = Join-Path $root $path
                New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
                New-Item -ItemType File -Path $full -Force | Out-Null
            }
            $calls = New-Object System.Collections.ArrayList
            $seams = New-TestSetupSeams -Calls $calls -Browser $case.Browser

            $summary = Invoke-LocalPackageSetup -ProjectRoot $root -ManifestPath (New-TestRuntimeManifest -Root $root) @seams

            $summary.browser_choice | Should Be $case.Expected
            @($calls | Where-Object Operation -eq 'InstallChromium').Count | Should Be $case.Installs
        }
    }

    It 'returns a redacted summary without database or SMTP secrets' {
        $root = Join-Path $TestDrive 'redacted-summary'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $calls = New-Object System.Collections.ArrayList
        $seams = New-TestSetupSeams -Calls $calls -Browser 'Edge'

        $summary = Invoke-LocalPackageSetup -ProjectRoot $root -ManifestPath (New-TestRuntimeManifest -Root $root) -RecipientAddress 'recipient@example.com' @seams
        $json = $summary | ConvertTo-Json -Depth 8 -Compress

        $summary.recipient_present | Should Be $true
        $json | Should Not Match 'database-secret|authorization|smtp.*code|command.?line'
        (@($summary.PSObject.Properties.Name) -contains 'components') | Should Be $true
        (@($summary.PSObject.Properties.Name) -contains 'errors') | Should Be $true
    }

    It 'preserves a working virtual environment and existing snapshot during idempotent setup' {
        $root = Join-Path $TestDrive 'venv-snapshot-preservation'
        foreach ($path in @('.local\python\python.exe', '.venv\Scripts\python.exe', '.local\postgresql\bin\initdb.exe', '.local\postgres-data\PG_VERSION', '.local\postgres-settings.json')) {
            $full = Join-Path $root $path
            New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
            [IO.File]::WriteAllText($full, 'original')
        }
        $snapshot = Join-Path $root 'var\amazon-bestsellers\2026-08-11\amazon-bestsellers.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $snapshot) -Force | Out-Null
        [IO.File]::WriteAllText($snapshot, '{"keep":true}')
        $calls = New-Object System.Collections.ArrayList
        $seams = New-TestSetupSeams -Calls $calls -Browser 'Edge'
        $seams.InitializePythonEnvironment = { param([string]$ScriptPath, [string]$ProjectRoot) return 0 }

        $summary = Invoke-LocalPackageSetup -ProjectRoot $root -ManifestPath (New-TestRuntimeManifest -Root $root) @seams

        $summary.status | Should Be 'READY'
        (Get-Content -Raw (Join-Path $root '.venv\Scripts\python.exe')) | Should Be 'original'
        (Get-Content -Raw $snapshot) | Should Be '{"keep":true}'
    }
}

Describe 'Local package recipient settings' {
    BeforeAll { Import-Module $modulePath -Force }

    It 'atomically writes only a valid recipient address' {
        $root = Join-Path $TestDrive 'recipient'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $writes = New-Object System.Collections.ArrayList
        $writer = {
            param([string]$Path, [string]$Json)
            [void]$writes.Add([pscustomobject]@{ Path = $Path; Json = $Json })
            $temporary = "$Path.atomic-test.tmp"
            [IO.File]::WriteAllText($temporary, $Json, (New-Object Text.UTF8Encoding($false)))
            Move-Item -LiteralPath $temporary -Destination $Path -Force
        }.GetNewClosure()

        $result = Set-LocalPackageRecipientSettings -ProjectRoot $root -RecipientAddress 'recipient@example.com' -AtomicJsonWriter $writer
        $stored = Get-Content -LiteralPath $result.Path -Raw | ConvertFrom-Json

        $stored.recipient_address | Should Be 'recipient@example.com'
        @($stored.PSObject.Properties.Name) | Should Be @('recipient_address')
        $writes.Count | Should Be 1
        Get-ChildItem -LiteralPath (Split-Path -Parent $result.Path) -Filter '*.tmp' | Should BeNullOrEmpty
    }

    It 'uses the default atomic writer without leaving staging files' {
        $root = Join-Path $TestDrive 'default-atomic-recipient'
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        $result = Set-LocalPackageRecipientSettings -ProjectRoot $root -RecipientAddress 'default@example.com'
        $stored = Get-Content -LiteralPath $result.Path -Raw | ConvertFrom-Json

        $stored.recipient_address | Should Be 'default@example.com'
        @(Get-ChildItem -LiteralPath (Split-Path -Parent $result.Path) -Filter '*.tmp-*').Count | Should Be 0
    }

    It 'rejects malformed email without creating local settings' {
        $root = Join-Path $TestDrive 'bad-recipient'
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        $failure = $null
        try { Set-LocalPackageRecipientSettings -ProjectRoot $root -RecipientAddress 'not-an-email' }
        catch { $failure = $_ }
        $failure | Should Not Be $null
        $failure.Exception.Message | Should Match 'email'
        Test-Path -LiteralPath (Join-Path $root '.local\user-settings.json') | Should Be $false
    }
}
