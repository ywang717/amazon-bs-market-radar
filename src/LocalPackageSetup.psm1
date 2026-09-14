Set-StrictMode -Version Latest

function Resolve-LocalPackageConfinedPath {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$FieldName,
        [scriptblock]$GetPathAttributes = {
            param($Candidate)
            if (Test-Path -LiteralPath $Candidate) { return (Get-Item -LiteralPath $Candidate -Force).Attributes }
            return $null
        }
    )
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath)) {
        throw "Manifest $FieldName must be a project-relative path."
    }
    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')
    $resolved = [IO.Path]::GetFullPath((Join-Path $root $RelativePath))
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Manifest $FieldName must resolve below the project root."
    }
    $current = $root
    foreach ($segment in @($RelativePath -split '[\\/]')) {
        if ([string]::IsNullOrWhiteSpace($segment)) { continue }
        Assert-LocalPackageSafeWindowsSegment -Value $segment -FieldName $FieldName
        $current = Join-Path $current $segment
        $attributes = & $GetPathAttributes $current
        if ($null -ne $attributes -and (([IO.FileAttributes]$attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
            throw "Manifest $FieldName cannot traverse a reparse point or junction: $current"
        }
    }
    return $resolved
}

function Assert-LocalPackageSafeWindowsSegment {
    param([string]$Value, [string]$FieldName)
    $stem = if ($Value.Contains('.')) { $Value.Substring(0, $Value.IndexOf('.')) } else { $Value }
    $reserved = $stem.ToUpperInvariant() -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$'
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -in @('.', '..') -or $Value.EndsWith('.') -or
        $Value.EndsWith(' ') -or $Value.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $reserved) {
        throw "Manifest $FieldName contains an unsafe Windows path segment."
    }
}

function Assert-LocalPackageSafeLeafName {
    param([string]$Value, [string]$FieldName)
    if ($Value -ne [IO.Path]::GetFileName($Value) -or $Value.Contains('\') -or $Value.Contains('/')) {
        throw "Manifest $FieldName must be a safe leaf filename."
    }
    Assert-LocalPackageSafeWindowsSegment -Value $Value -FieldName $FieldName
}

function Get-LocalPackageProperty {
    param([object]$InputObject, [string]$Name, [string]$Context)
    if ($null -eq $InputObject -or $null -eq $InputObject.PSObject.Properties[$Name]) {
        throw "Manifest $Context is missing required property '$Name'."
    }
    return $InputObject.$Name
}

function Test-LocalPackageRuntimeManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [scriptblock]$GetPathAttributes = {
            param($Candidate)
            if (Test-Path -LiteralPath $Candidate) { return (Get-Item -LiteralPath $Candidate -Force).Attributes }
            return $null
        }
    )
    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) { throw "Project root not found: $ProjectRoot" }
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Runtime manifest not found: $ManifestPath" }
    try { $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "Runtime manifest is not valid JSON: $ManifestPath" }
    if ([string](Get-LocalPackageProperty -InputObject $manifest -Name 'schema_version' -Context 'root') -ne 'local-package-runtime-v1') {
        throw "Manifest schema_version must be 'local-package-runtime-v1'."
    }
    if ([string](Get-LocalPackageProperty -InputObject $manifest -Name 'platform' -Context 'root') -ne 'windows-x64') {
        throw "Manifest platform must be 'windows-x64'."
    }
    $rawComponents = Get-LocalPackageProperty -InputObject $manifest -Name 'components' -Context 'root'
    $normalized = [ordered]@{}
    foreach ($name in @('python', 'postgresql', 'playwright_chromium')) {
        $component = Get-LocalPackageProperty -InputObject $rawComponents -Name $name -Context 'components'
        $context = "components.$name"
        $identifier = [string](Get-LocalPackageProperty $component 'identifier' $context)
        $filename = [string](Get-LocalPackageProperty $component 'filename' $context)
        $urlText = [string](Get-LocalPackageProperty $component 'url' $context)
        $sha256 = [string](Get-LocalPackageProperty $component 'sha256' $context)
        $verified = Get-LocalPackageProperty $component 'checksum_verified' $context
        $destinationRelative = [string](Get-LocalPackageProperty $component 'destination_path' $context)
        $expectedRelative = [string](Get-LocalPackageProperty $component 'expected_path' $context)
        if ([string]::IsNullOrWhiteSpace($identifier)) { throw "Manifest $context.identifier cannot be empty." }
        Assert-LocalPackageSafeLeafName -Value $filename -FieldName "$context.filename"
        $uri = $null
        if (-not [Uri]::TryCreate($urlText, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https') {
            throw "Manifest $context.url must be an absolute HTTPS URL."
        }
        if ($sha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw "Manifest $context.sha256 must contain exactly 64 hexadecimal characters." }
        if ($verified -isnot [bool]) { throw "Manifest $context.checksum_verified must be a boolean." }
        $destination = Resolve-LocalPackageConfinedPath -ProjectRoot $ProjectRoot -RelativePath $destinationRelative -FieldName "$context.destination_path" -GetPathAttributes $GetPathAttributes
        $expected = Resolve-LocalPackageConfinedPath -ProjectRoot $ProjectRoot -RelativePath $expectedRelative -FieldName "$context.expected_path" -GetPathAttributes $GetPathAttributes
        $destinationPrefix = $destination.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        if (-not $expected.StartsWith($destinationPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Manifest $context.expected_path must be below its destination_path."
        }
        $archiveRoot = $null
        if ($name -ne 'python') {
            $archiveRoot = [string](Get-LocalPackageProperty $component 'archive_root' $context)
            Assert-LocalPackageSafeLeafName -Value $archiveRoot -FieldName "$context.archive_root"
        }
        $normalized[$name] = [pscustomobject]@{
            Identifier = $identifier
            Filename = $filename
            Url = $urlText
            Sha256 = $sha256.ToUpperInvariant()
            ChecksumVerified = [bool]$verified
            DestinationPath = $destination
            ExpectedPath = $expected
            ArchiveRoot = $archiveRoot
        }
    }
    return [pscustomobject]@{
        SchemaVersion = 'local-package-runtime-v1'
        Platform = 'windows-x64'
        ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')
        Components = [pscustomobject]$normalized
    }
}

function Write-LocalPackageJsonAtomically {
    param([string]$Path, [string]$Json)
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporary = Join-Path $directory ((Split-Path -Leaf $Path) + '.tmp-' + [guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($temporary, $Json, (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Set-LocalPackageRecipientSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$RecipientAddress,
        [scriptblock]$AtomicJsonWriter = ${function:Write-LocalPackageJsonAtomically}
    )
    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) { throw "Project root not found: $ProjectRoot" }
    $trimmed = $RecipientAddress.Trim()
    $valid = $trimmed -match '^[^\s@]+@[^\s@]+\.[^\s@]+$'
    if ($valid) {
        try { $parsed = New-Object Net.Mail.MailAddress($trimmed) } catch { $valid = $false }
        if ($valid -and $parsed.Address -ne $trimmed) { $valid = $false }
    }
    if (-not $valid) { throw 'Recipient email address is malformed.' }
    $settingsPath = Resolve-LocalPackageConfinedPath -ProjectRoot $ProjectRoot -RelativePath '.local\user-settings.json' -FieldName 'user settings path'
    $settingsRoot = Split-Path -Parent $settingsPath
    New-Item -ItemType Directory -Path $settingsRoot -Force | Out-Null
    $json = ([ordered]@{ recipient_address = $trimmed } | ConvertTo-Json -Compress)
    & $AtomicJsonWriter $settingsPath $json
    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) { throw "Recipient settings were not written: $settingsPath" }
    return [pscustomobject]@{ Status = 'CONFIGURED'; Path = $settingsPath; RecipientPresent = $true }
}

function Get-LocalPackageExitCode {
    param([object]$Result)
    if ($null -eq $Result) { return 0 }
    if ($Result -is [int]) { return [int]$Result }
    if ($null -ne $Result.PSObject.Properties['ExitCode']) { return [int]$Result.ExitCode }
    return 0
}

function Get-VerifiedLocalPackageDownload {
    param(
        [object]$Component,
        [string]$DownloadsRoot,
        [scriptblock]$DownloadFile,
        [scriptblock]$GetFileHash
    )
    if (-not $Component.ChecksumVerified -or $Component.Sha256 -eq ('0' * 64)) {
        throw "No authoritative SHA-256 is recorded for $($Component.Identifier). Update the tracked runtime manifest from an authoritative source before retrying."
    }
    New-Item -ItemType Directory -Path $DownloadsRoot -Force | Out-Null
    $downloadPath = Join-Path $DownloadsRoot $Component.Filename
    if (Test-Path -LiteralPath $downloadPath -PathType Leaf) {
        $existingHash = [string](& $GetFileHash $downloadPath)
        if ([StringComparer]::OrdinalIgnoreCase.Equals($existingHash, [string]$Component.Sha256)) { return $downloadPath }
    }
    $partialPath = $downloadPath + '.part-' + [guid]::NewGuid().ToString('N')
    try {
        & $DownloadFile $Component.Url $partialPath
        if (-not (Test-Path -LiteralPath $partialPath -PathType Leaf)) { throw "Download did not create expected file for $($Component.Identifier)." }
        $actualHash = [string](& $GetFileHash $partialPath)
        if (-not [StringComparer]::OrdinalIgnoreCase.Equals($actualHash, [string]$Component.Sha256)) { throw "Downloaded checksum mismatch for $($Component.Identifier)." }
        Move-Item -LiteralPath $partialPath -Destination $downloadPath -Force
        return $downloadPath
    }
    finally {
        if (Test-Path -LiteralPath $partialPath) { Remove-Item -LiteralPath $partialPath -Force }
    }
}

function Find-DefaultLocalPackageBrowser {
    $edgeCandidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
    )
    if (@($edgeCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }).Count -gt 0) { return 'Edge' }
    $chromeCandidates = @(
        (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
    )
    if (@($chromeCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }).Count -gt 0) { return 'Chrome' }
    return $null
}

function Test-DefaultPythonComponent {
    param($Path, $Identifier)
    try {
        $output = @(& $Path --version 2>&1)
        return ($LASTEXITCODE -eq 0 -and ($output -join ' ') -match '\b3\.12\.10\b')
    }
    catch { return $false }
}

function Test-DefaultPostgresComponent {
    param($Path, $Identifier)
    try {
        $output = @(& $Path --version 2>&1)
        return ($LASTEXITCODE -eq 0 -and ($output -join ' ') -match '\b18\.4\b')
    }
    catch { return $false }
}

function Test-DefaultChromiumComponent {
    param($Path, $Identifier)
    try {
        $version = (Get-Item -LiteralPath $Path -Force).VersionInfo
        return (-not [string]::IsNullOrWhiteSpace([string]$version.FileVersion) -and [string]$version.ProductName -match 'Chrome|Chromium')
    }
    catch { return $false }
}

function Protect-LocalPackageSetupText {
    param([string]$Text, [scriptblock]$EnvironmentValueProvider)
    $safe = $Text
    foreach ($scope in @('Process','User')) {
        $secret = [string](& $EnvironmentValueProvider 'DAILY_REPORT_SMTP_AUTH_CODE' $scope)
        if (-not [string]::IsNullOrWhiteSpace($secret)) { $safe = $safe.Replace($secret, '[REDACTED]') }
    }
    return $safe
}

function Invoke-LocalPackageSetup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [string]$ManifestPath,
        [string]$RecipientAddress,
        [scriptblock]$DownloadFile = { param($Uri, $Destination) Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing },
        [scriptblock]$GetFileHash = { param($Path) (Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash },
        [scriptblock]$InstallPython = {
            param($InstallerPath, $DestinationRoot)
            $arguments = @('/quiet', 'InstallAllUsers=0', "TargetDir=$DestinationRoot", 'Include_launcher=0', 'Include_test=0', 'PrependPath=0', 'Shortcuts=0')
            (Start-Process -FilePath $InstallerPath -ArgumentList $arguments -Wait -PassThru).ExitCode
        },
        [scriptblock]$InitializePythonEnvironment = { param($ScriptPath, $Root) & $ScriptPath | Out-Null; 0 },
        [scriptblock]$ExtractArchive = { param($ArchivePath, $StagingRoot) Expand-Archive -LiteralPath $ArchivePath -DestinationPath $StagingRoot -Force },
        [scriptblock]$PromoteDirectory = { param($Source, $Destination) Move-Item -LiteralPath $Source -Destination $Destination },
        [scriptblock]$InitializeDatabase = { param($ScriptPath, $InstallRoot, $DataRoot, $SettingsPath) & $ScriptPath -InstallRoot $InstallRoot -DataRoot $DataRoot | Out-Null; 0 },
        [scriptblock]$RunMigrations = { param($ScriptPath, $SettingsPath) & $ScriptPath -SettingsPath $SettingsPath | Out-Null; 0 },
        [scriptblock]$FindSystemBrowser = ${function:Find-DefaultLocalPackageBrowser},
        [scriptblock]$VerifyPythonComponent = ${function:Test-DefaultPythonComponent},
        [scriptblock]$VerifyPostgresComponent = ${function:Test-DefaultPostgresComponent},
        [scriptblock]$VerifyChromiumComponent = ${function:Test-DefaultChromiumComponent},
        [scriptblock]$InstallChromium = {
            param($ArchivePath, $StagingRoot, $DestinationRoot, $ArchiveRoot)
            $stagedChromium = Join-Path $StagingRoot $ArchiveRoot
            New-Item -ItemType Directory -Path $stagedChromium -Force | Out-Null
            Expand-Archive -LiteralPath $ArchivePath -DestinationPath $stagedChromium -Force
            New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
            Move-Item -LiteralPath $stagedChromium -Destination (Join-Path $DestinationRoot $ArchiveRoot)
        },
        [scriptblock]$AtomicJsonWriter = ${function:Write-LocalPackageJsonAtomically},
        [scriptblock]$GetPathAttributes = {
            param($Candidate)
            if (Test-Path -LiteralPath $Candidate) { return (Get-Item -LiteralPath $Candidate -Force).Attributes }
            return $null
        },
        [scriptblock]$EnvironmentValueProvider = { param($Name, $Scope) [Environment]::GetEnvironmentVariable($Name, $Scope) }
    )
    $resolvedRoot = if (Test-Path -LiteralPath $ProjectRoot -PathType Container) { (Resolve-Path -LiteralPath $ProjectRoot).Path } else { [IO.Path]::GetFullPath($ProjectRoot) }
    if ([string]::IsNullOrWhiteSpace($ManifestPath)) { $ManifestPath = Join-Path $resolvedRoot 'config\local-package-runtime-manifest.json' }
    $localRoot = Join-Path $resolvedRoot '.local'
    $downloadsRoot = Join-Path $localRoot 'downloads'
    $settingsPath = Join-Path $localRoot 'postgres-settings.json'
    $dataMarker = Join-Path $localRoot 'postgres-data\PG_VERSION'
    $venvPython = Join-Path $resolvedRoot '.venv\Scripts\python.exe'
    $summary = [ordered]@{
        status = 'FAILED'
        components = [ordered]@{
            python = [ordered]@{ status = 'PENDING' }
            postgresql = [ordered]@{ status = 'PENDING' }
            browser = [ordered]@{ status = 'PENDING' }
        }
        paths = [ordered]@{ python = $null; venv = $venvPython; postgresql = $null; playwright = (Join-Path $localRoot 'playwright'); user_settings = (Join-Path $localRoot 'user-settings.json') }
        database_initialized = $false
        migrations_run = $false
        browser_choice = $null
        recipient_present = $false
        errors = @()
    }
    try {
        $validated = Test-LocalPackageRuntimeManifest -ManifestPath $ManifestPath -ProjectRoot $resolvedRoot -GetPathAttributes $GetPathAttributes
        $python = $validated.Components.python
        $postgres = $validated.Components.postgresql
        $chromium = $validated.Components.playwright_chromium
        $summary.paths.python = $python.ExpectedPath
        $summary.paths.postgresql = $postgres.ExpectedPath
        $summary.paths.playwright = $chromium.DestinationPath
        New-Item -ItemType Directory -Path $localRoot -Force | Out-Null
        $settingsExists = Test-Path -LiteralPath $settingsPath -PathType Leaf
        $configuredSettings = $null
        $effectiveDataMarker = $dataMarker
        $localDataExists = Test-Path -LiteralPath $dataMarker -PathType Leaf
        if ($settingsExists -and -not $localDataExists) {
            try { $configuredSettings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
            catch { throw "Existing PostgreSQL settings are not valid JSON and were left untouched: $settingsPath" }
            $dataRootProperty = $configuredSettings.PSObject.Properties['data_root']
            $configuredDataRoot = if ($null -ne $dataRootProperty) { [string]$dataRootProperty.Value } else { $null }
            if (-not [string]::IsNullOrWhiteSpace($configuredDataRoot)) { $effectiveDataMarker = Join-Path $configuredDataRoot 'PG_VERSION' }
        }
        $dataExists = Test-Path -LiteralPath $effectiveDataMarker -PathType Leaf
        if ($settingsExists -ne $dataExists) { throw 'PostgreSQL database state is inconsistent: postgres-settings.json and its configured PG_VERSION must either both exist or both be absent. Existing state was left untouched.' }

        if (Test-Path -LiteralPath $python.ExpectedPath -PathType Leaf) {
            if ((& $VerifyPythonComponent $python.ExpectedPath $python.Identifier) -ne $true) { throw "Existing Python executable failed version verification and was left untouched: $($python.ExpectedPath)" }
            $summary.components.python.status = 'RETAINED'
        }
        elseif (Test-Path -LiteralPath $python.DestinationPath) {
            throw "Existing Python destination is incomplete and was left untouched: $($python.DestinationPath)"
        }
        else {
            $pythonInstaller = Get-VerifiedLocalPackageDownload -Component $python -DownloadsRoot $downloadsRoot -DownloadFile $DownloadFile -GetFileHash $GetFileHash
            $exitCode = Get-LocalPackageExitCode (& $InstallPython $pythonInstaller $python.DestinationPath)
            if ($exitCode -ne 0) { throw "Project Python installer failed with exit code $exitCode." }
            if (-not (Test-Path -LiteralPath $python.ExpectedPath -PathType Leaf)) { throw "Project Python installer did not create expected executable: $($python.ExpectedPath)" }
            if ((& $VerifyPythonComponent $python.ExpectedPath $python.Identifier) -ne $true) { throw "Installed Python executable failed version verification: $($python.ExpectedPath)" }
            $summary.components.python.status = 'INSTALLED'
        }
        $pythonEnvironmentExit = Get-LocalPackageExitCode (& $InitializePythonEnvironment (Join-Path $resolvedRoot 'scripts\Initialize-PythonEnvironment.ps1') $resolvedRoot)
        if ($pythonEnvironmentExit -ne 0) { throw "Project Python environment initialization failed with exit code $pythonEnvironmentExit." }
        if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) { throw "Project Python virtual environment was not created: $venvPython" }

        if (Test-Path -LiteralPath $postgres.ExpectedPath -PathType Leaf) {
            if ((& $VerifyPostgresComponent $postgres.ExpectedPath $postgres.Identifier) -ne $true) { throw "Existing PostgreSQL executable failed version verification and was left untouched: $($postgres.ExpectedPath)" }
            $summary.components.postgresql.status = 'RETAINED'
        }
        elseif ($settingsExists -and $dataExists) {
            if ($null -eq $configuredSettings) {
                try { $configuredSettings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
                catch { throw "Existing PostgreSQL settings are not valid JSON and were left untouched: $settingsPath" }
            }
            $configuredInstallRoot = [string]$configuredSettings.install_root
            if ([string]::IsNullOrWhiteSpace($configuredInstallRoot)) { throw "Existing PostgreSQL settings do not contain install_root and were left untouched: $settingsPath" }
            $configuredInitDb = Join-Path $configuredInstallRoot 'bin\initdb.exe'
            if (-not (Test-Path -LiteralPath $configuredInitDb -PathType Leaf)) { throw "Configured PostgreSQL executable was not found and existing data was left untouched: $configuredInitDb" }
            if ((& $VerifyPostgresComponent $configuredInitDb $postgres.Identifier) -ne $true) { throw "Configured PostgreSQL executable failed version verification and existing data was left untouched: $configuredInitDb" }
            $summary.paths.postgresql = $configuredInitDb
            $summary.components.postgresql.status = 'RETAINED_CONFIGURED'
        }
        elseif (Test-Path -LiteralPath $postgres.DestinationPath) {
            throw "Existing PostgreSQL destination is incomplete and was left untouched: $($postgres.DestinationPath)"
        }
        else {
            $postgresArchive = Get-VerifiedLocalPackageDownload -Component $postgres -DownloadsRoot $downloadsRoot -DownloadFile $DownloadFile -GetFileHash $GetFileHash
            $stageRoot = Join-Path $localRoot ('postgresql-stage-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $stageRoot | Out-Null
            try {
                & $ExtractArchive $postgresArchive $stageRoot
                $stagedInstall = Join-Path $stageRoot $postgres.ArchiveRoot
                $stagedMarker = Join-Path $stagedInstall 'bin\initdb.exe'
                if (-not (Test-Path -LiteralPath $stagedMarker -PathType Leaf)) { throw "Staged PostgreSQL archive is missing bin\initdb.exe for $($postgres.Identifier)." }
                if ((& $VerifyPostgresComponent $stagedMarker $postgres.Identifier) -ne $true) { throw "Staged PostgreSQL initdb failed version verification for $($postgres.Identifier)." }
                if (Test-Path -LiteralPath $postgres.DestinationPath) { throw "PostgreSQL destination appeared during staging and was left untouched: $($postgres.DestinationPath)" }
                & $PromoteDirectory $stagedInstall $postgres.DestinationPath
            }
            finally {
                if (Test-Path -LiteralPath $stageRoot) { Remove-Item -LiteralPath $stageRoot -Recurse -Force }
            }
            if (-not (Test-Path -LiteralPath $postgres.ExpectedPath -PathType Leaf)) { throw "PostgreSQL promotion did not create expected executable: $($postgres.ExpectedPath)" }
            if ((& $VerifyPostgresComponent $postgres.ExpectedPath $postgres.Identifier) -ne $true) { throw "Promoted PostgreSQL executable failed version verification: $($postgres.ExpectedPath)" }
            $summary.components.postgresql.status = 'INSTALLED'
        }

        if (-not $settingsExists -and -not $dataExists) {
            $dbExit = Get-LocalPackageExitCode (& $InitializeDatabase (Join-Path $resolvedRoot 'scripts\postgres\Initialize-LocalPostgres.ps1') $postgres.DestinationPath (Split-Path -Parent $dataMarker) $settingsPath)
            if ($dbExit -ne 0) { throw "PostgreSQL initialization failed with exit code $dbExit." }
            if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf) -or -not (Test-Path -LiteralPath $dataMarker -PathType Leaf)) { throw 'PostgreSQL initialization did not create both settings and PG_VERSION.' }
            $summary.database_initialized = $true
        }
        $migrationExit = Get-LocalPackageExitCode (& $RunMigrations (Join-Path $resolvedRoot 'scripts\postgres\Invoke-LocalMigrations.ps1') $settingsPath)
        if ($migrationExit -ne 0) { throw "PostgreSQL migrations failed with exit code $migrationExit." }
        $summary.migrations_run = $true

        $localChromiumAvailable = $false
        if (Test-Path -LiteralPath $chromium.ExpectedPath -PathType Leaf) {
            if ((& $VerifyChromiumComponent $chromium.ExpectedPath $chromium.Identifier) -ne $true) { throw "Existing Playwright Chromium executable failed verification and was left untouched: $($chromium.ExpectedPath)" }
            $localChromiumAvailable = $true
        }
        elseif (Test-Path -LiteralPath $chromium.DestinationPath) {
            throw "Existing Playwright destination is incomplete and was left untouched: $($chromium.DestinationPath)"
        }

        $systemBrowser = [string](& $FindSystemBrowser)
        if ($systemBrowser -in @('Edge', 'Chrome')) {
            $summary.browser_choice = $systemBrowser
            $summary.components.browser.status = 'SYSTEM_BROWSER'
        }
        elseif ($localChromiumAvailable) {
            $summary.browser_choice = 'PlaywrightChromium'
            $summary.components.browser.status = 'RETAINED'
        }
        else {
            $chromiumArchive = Get-VerifiedLocalPackageDownload -Component $chromium -DownloadsRoot $downloadsRoot -DownloadFile $DownloadFile -GetFileHash $GetFileHash
            $browserStage = Join-Path $localRoot ('playwright-stage-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $browserStage | Out-Null
            try { & $InstallChromium $chromiumArchive $browserStage $chromium.DestinationPath $chromium.ArchiveRoot }
            finally { if (Test-Path -LiteralPath $browserStage) { Remove-Item -LiteralPath $browserStage -Recurse -Force } }
            if (-not (Test-Path -LiteralPath $chromium.ExpectedPath -PathType Leaf)) { throw "Playwright Chromium install did not create expected executable: $($chromium.ExpectedPath)" }
            if ((& $VerifyChromiumComponent $chromium.ExpectedPath $chromium.Identifier) -ne $true) { throw "Installed Playwright Chromium executable failed verification: $($chromium.ExpectedPath)" }
            $summary.browser_choice = 'PlaywrightChromium'
            $summary.components.browser.status = 'INSTALLED'
        }

        if (-not [string]::IsNullOrWhiteSpace($RecipientAddress)) {
            Set-LocalPackageRecipientSettings -ProjectRoot $resolvedRoot -RecipientAddress $RecipientAddress -AtomicJsonWriter $AtomicJsonWriter | Out-Null
        }
        $summary.recipient_present = Test-Path -LiteralPath (Join-Path $localRoot 'user-settings.json') -PathType Leaf
        $summary.status = 'READY'
    }
    catch {
        $safeMessage = Protect-LocalPackageSetupText -Text ([string]$_.Exception.Message) -EnvironmentValueProvider $EnvironmentValueProvider
        $summary.errors = @($safeMessage)
    }
    return [pscustomobject]$summary
}

Export-ModuleMember -Function @(
    'Test-LocalPackageRuntimeManifest',
    'Set-LocalPackageRecipientSettings',
    'Invoke-LocalPackageSetup'
)
