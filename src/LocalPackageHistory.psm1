Set-StrictMode -Version 2.0

function Get-LocalPackageHistoryProperty {
    param($Object,[string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Protect-LocalPackageHistoryText {
    param([string]$Text,[scriptblock]$EnvironmentValueProvider)
    if ($null -eq $EnvironmentValueProvider) { $EnvironmentValueProvider = { param($name,$scope) [Environment]::GetEnvironmentVariable($name,$scope) } }
    $result = [string]$Text
    foreach ($scope in @('Process','User')) {
        foreach ($name in @('DAILY_REPORT_SMTP_AUTH_CODE','PGPASSWORD','AMAZON_BS_POSTGRES_PASSWORD')) {
            $secret = [string](& $EnvironmentValueProvider $name $scope)
            if (-not [string]::IsNullOrWhiteSpace($secret) -and $secret.Length -ge 4) { $result = $result.Replace($secret,'[REDACTED]') }
        }
    }
    return $result
}

function Protect-LocalPackageHistorySummary {
    param($Summary,[scriptblock]$EnvironmentValueProvider)
    if ($null -eq $Summary) { return $null }
    $copy = [ordered]@{}
    foreach ($property in $Summary.PSObject.Properties) {
        $value = $property.Value
        if ($property.Name -ne 'status' -and $value -is [string]) { $value = Protect-LocalPackageHistoryText -Text $value -EnvironmentValueProvider $EnvironmentValueProvider }
        $copy[$property.Name] = $value
    }
    return [pscustomobject]$copy
}

function Get-DefaultLocalPackageHistoryFileSystemRunner {
    return {
        param([string]$Operation,[hashtable]$Arguments)
        switch ($Operation) {
            'CreateDirectory' { New-Item -ItemType Directory -Path $Arguments.Path -Force | Out-Null; return $Arguments.Path }
            'EnumerateFiles' { return @(Get-ChildItem -LiteralPath $Arguments.Path -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object { [pscustomobject]@{FullName=$_.FullName;Length=[long]$_.Length} }) }
            'CopyFile' { New-Item -ItemType Directory -Path (Split-Path -Parent $Arguments.Destination) -Force | Out-Null; Copy-Item -LiteralPath $Arguments.Source -Destination $Arguments.Destination; return $Arguments.Destination }
            'GetLength' { return [long](Get-Item -LiteralPath $Arguments.Path).Length }
            'WriteUtf8' { New-Item -ItemType Directory -Path (Split-Path -Parent $Arguments.Path) -Force | Out-Null; [IO.File]::WriteAllText($Arguments.Path,$Arguments.Content,(New-Object Text.UTF8Encoding($false))); return $Arguments.Path }
            'ReadUtf8' { return Get-Content -LiteralPath $Arguments.Path -Raw -Encoding UTF8 }
            'FileExists' { return Test-Path -LiteralPath $Arguments.Path -PathType Leaf }
            'RemoveTree' { Remove-Item -LiteralPath $Arguments.Path -Recurse -Force; return $true }
            'DeleteFile' { Remove-Item -LiteralPath $Arguments.Path -Force -ErrorAction SilentlyContinue; return $true }
            'AtomicMove' { New-Item -ItemType Directory -Path (Split-Path -Parent $Arguments.Destination) -Force | Out-Null; Move-Item -LiteralPath $Arguments.Source -Destination $Arguments.Destination; return $Arguments.Destination }
            default { throw "Unsupported filesystem operation: $Operation" }
        }
    }
}

function Get-DefaultLocalPackageHistoryHashRunner {
    return { param([string]$Path) (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
}

function ConvertFrom-LocalPackageHistoryProcessJson {
    param($Output,[int]$ExitCode,[string]$Operation)
    $text = (@($Output | ForEach-Object { [string]$_ }) -join "`n").Trim()
    if ($ExitCode -ne 0) { throw "$Operation failed with exit code $ExitCode. $text" }
    try { return $text | ConvertFrom-Json -ErrorAction Stop } catch { throw "$Operation returned malformed JSON." }
}

function Get-DefaultLocalPackageHistoryBackupRunner {
    return {
        param([string]$Operation,[hashtable]$Arguments)
        $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if ($Operation -eq 'Create') {
            $scriptPath = Join-Path $Arguments.ProjectRoot 'scripts\postgres\Backup-LocalPostgres.ps1'
            $output = @(& $powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath 2>&1)
            return ConvertFrom-LocalPackageHistoryProcessJson -Output $output -ExitCode $LASTEXITCODE -Operation 'PostgreSQL backup creation'
        }
        if ($Operation -eq 'Verify') {
            $manifestPath = $null
            if ($Arguments.ContainsKey('ExpectedHash')) {
                $manifestPath = $Arguments.BackupPath + '.json'
                $manifest = [ordered]@{schema_version='local-postgres-backup-v1';sha256=[string]$Arguments.ExpectedHash}
                [IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
            }
            $scriptPath = Join-Path $Arguments.ProjectRoot 'scripts\postgres\Test-LocalPostgresBackup.ps1'
            $argumentList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$scriptPath,'-BackupPath',$Arguments.BackupPath)
            if (-not [string]::IsNullOrWhiteSpace($manifestPath)) { $argumentList += @('-ManifestPath',$manifestPath) }
            $output = @(& $powershell @argumentList 2>&1)
            return ConvertFrom-LocalPackageHistoryProcessJson -Output $output -ExitCode $LASTEXITCODE -Operation 'PostgreSQL backup verification'
        }
        throw "Unsupported backup operation: $Operation"
    }
}

function Get-DefaultLocalPackageHistoryArchiveRunner {
    return {
        param([string]$Operation,[hashtable]$Arguments)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        if ($Operation -eq 'Identity') {
            $stream = [IO.File]::Open($Arguments.ArchivePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
            try { return [pscustomobject]@{Sha256=(Get-FileHash -InputStream $stream -Algorithm SHA256).Hash.ToLowerInvariant();Length=[long]$stream.Length} }
            finally { $stream.Dispose() }
        }
        if ($Operation -eq 'Copy') {
            $source = [IO.File]::Open($Arguments.Source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
            try {
                $destination = [IO.File]::Open($Arguments.Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
                try { $source.CopyTo($destination); $destination.Flush() }
                finally { $destination.Dispose() }
            }
            finally { $source.Dispose() }
            return $Arguments.Destination
        }
        if ($Operation -eq 'Create') {
            if (Test-Path -LiteralPath $Arguments.ArchivePath) { throw "History archive already exists: $($Arguments.ArchivePath)" }
            [IO.Compression.ZipFile]::CreateFromDirectory($Arguments.SourceRoot,$Arguments.ArchivePath,[IO.Compression.CompressionLevel]::Optimal,$false)
            return $Arguments.ArchivePath
        }
        if ($Operation -eq 'List') {
            $zip = [IO.Compression.ZipFile]::OpenRead($Arguments.ArchivePath)
            try { return @($zip.Entries | ForEach-Object { [pscustomobject]@{Path=$_.FullName;IsDirectory=[string]::IsNullOrEmpty($_.Name);Length=[long]$_.Length} }) }
            finally { $zip.Dispose() }
        }
        if ($Operation -eq 'Extract') { [IO.Compression.ZipFile]::ExtractToDirectory($Arguments.ArchivePath,$Arguments.Destination); return $Arguments.Destination }
        throw "Unsupported archive operation: $Operation"
    }
}

function Get-DefaultLocalPackageHistoryDatabaseRunner {
    return {
        param([string]$Operation,[hashtable]$Arguments)
        $projectRoot = $Arguments.ProjectRoot
        $settingsPath = Join-Path $projectRoot '.local\postgres-settings.json'
        if ($Operation -eq 'RestoreDrill') {
            $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $scriptPath = Join-Path $projectRoot 'scripts\postgres\Test-LocalPostgresRestoreDrill.ps1'
            $output = @(& $powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -BackupPath $Arguments.BackupPath 2>&1)
            return ConvertFrom-LocalPackageHistoryProcessJson -Output $output -ExitCode $LASTEXITCODE -Operation 'PostgreSQL restore drill'
        }
        $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $savedPassword = [Environment]::GetEnvironmentVariable('PGPASSWORD','Process')
        try {
            $env:PGPASSWORD = [string]$settings.password
            if ($Operation -eq 'IsPrimaryEmpty') {
                $psql = Join-Path $settings.install_root 'bin\psql.exe'
                $queryRunner = {
                    param([string]$Table)
                    $sql = "SELECT count(*) FROM amazon_intelligence.$Table;"
                    $output = @(& $psql '-v' 'ON_ERROR_STOP=1' '-At' '-h' ([string]$settings.host) '-p' ([string]$settings.port) '-U' ([string]$settings.username) '-d' ([string]$settings.database) '-c' $sql 2>&1)
                    if ($LASTEXITCODE -ne 0) { throw "Could not prove the primary project database table is empty: $Table" }
                    return (($output -join '').Trim())
                }.GetNewClosure()
                return Test-LocalPackageHistoryPrimaryDatabaseEmpty -QueryRunner $queryRunner
            }
            if ($Operation -eq 'RestorePrimary') {
                $pgRestore = Join-Path $settings.install_root 'bin\pg_restore.exe'
                $restoreOutput = @(& $pgRestore '--exit-on-error' '--clean' '--if-exists' '--no-owner' '--no-privileges' '-h' ([string]$settings.host) '-p' ([string]$settings.port) '-U' ([string]$settings.username) '-d' ([string]$settings.database) $Arguments.BackupPath 2>&1)
                if ($LASTEXITCODE -ne 0) { throw "Primary database restore failed with exit code $LASTEXITCODE." }
                return [pscustomobject]@{Status='RESTORED'}
            }
        }
        finally {
            if ($null -eq $savedPassword) { Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable('PGPASSWORD',$savedPassword,'Process') }
        }
        throw "Unsupported database operation: $Operation"
    }
}

function Test-LocalPackageHistoryPrimaryDatabaseEmpty {
    param([Parameter(Mandatory=$true)][scriptblock]$QueryRunner)
    $tables = @(
        'collection_run','best_sellers_run','public_intelligence_run','best_sellers_analysis_run',
        'best_sellers_market_structure_run','best_sellers_rank_influence_run'
    )
    foreach ($table in $tables) {
        $rawCount = & $QueryRunner $table
        $count = 0L
        if (-not [long]::TryParse(([string]$rawCount).Trim(),[ref]$count) -or $count -lt 0) { throw "Primary database emptiness probe returned invalid output for $table." }
        if ($count -gt 0) { return $false }
    }
    return $true
}

function Get-DefaultLocalPackageHistoryReceiptRunner {
    return {
        param([string]$SnapshotPath,[string]$ReceiptPath)
        $receipt = Get-Content -LiteralPath $ReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$receipt.schema_version -ne 'best-sellers-capture-receipt-v1') { throw 'Imported capture receipt has an unsupported schema.' }
        $actualHash = (Get-FileHash -LiteralPath $SnapshotPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $snapshot = Get-Content -LiteralPath $SnapshotPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $valid = [string]$receipt.snapshot_sha256 -ceq $actualHash -and [string]$receipt.market_date -ceq [string]$snapshot.market_date
        return [pscustomobject]@{Valid=$valid}
    }
}

function Get-LocalPackageHistoryRelativePath {
    param([string]$Root,[string]$Path)
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $pathFull = [IO.Path]::GetFullPath($Path)
    if (-not $pathFull.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw "History source escaped its approved root: $Path" }
    return $pathFull.Substring($rootFull.Length + 1).Replace('\','/')
}

function Get-LocalPackageHistoryKindForPath {
    param([string]$Path)
    if ($Path -ceq 'database/history.dump') { return 'database_dump' }
    if ($Path -match '^snapshots/(?:[^/]+/)*amazon-bestsellers\.json$') { return 'snapshot' }
    if ($Path -match '^snapshots/(?:[^/]+/)*best-sellers-capture-receipt\.json$') { return 'capture_receipt' }
    if ($Path -match '^reports/(?:[^/]+/)*[^/]+\.(?:pdf|html|md)$') { return 'report' }
    return $null
}

function Test-LocalPackageHistoryReportRelativePath {
    param([string]$Path)
    $normalized = $Path.Replace('\','/')
    if ([IO.Path]::GetExtension($normalized).ToLowerInvariant() -notin @('.pdf','.html','.md')) { return $false }
    $segments = @($normalized.Split('/'))
    foreach ($segment in @($segments | Select-Object -SkipLast 1)) {
        if ($segment -match '(?i)(cache|browser|profile|tmp|temp|temporary|logs?|credentials?|source[-_. ]?config|passwords?|secrets?)') { return $false }
    }
    $leaf = $segments[-1]
    if ($leaf -match '(?i)(credential|password|secret|source[-_. ]?config|email[-_. ]?delivery[-_. ]?summary|environment|postgres[-_. ]?settings|user[-_. ]?settings|smtp)') { return $false }
    return $true
}

function Test-LocalPackageHistoryRunnerStatus {
    param($Result,[string]$Expected,[string]$Operation)
    if ([string](Get-LocalPackageHistoryProperty $Result 'Status') -cne $Expected) { throw "$Operation did not return status $Expected." }
    $hashMatches = Get-LocalPackageHistoryProperty $Result 'HashMatches'
    if ($null -ne $hashMatches -and -not [bool]$hashMatches) { throw "$Operation reported a checksum mismatch." }
}

function Invoke-LocalPackageHistoryExport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,[string]$OutputPath,
        [scriptblock]$FileSystemRunner,[scriptblock]$HashRunner,[scriptblock]$BackupRunner,[scriptblock]$ArchiveRunner,[scriptblock]$EnvironmentValueProvider
    )
    if ($null -eq $FileSystemRunner) { $FileSystemRunner = Get-DefaultLocalPackageHistoryFileSystemRunner }
    if ($null -eq $HashRunner) { $HashRunner = Get-DefaultLocalPackageHistoryHashRunner }
    if ($null -eq $BackupRunner) { $BackupRunner = Get-DefaultLocalPackageHistoryBackupRunner }
    if ($null -eq $ArchiveRunner) { $ArchiveRunner = Get-DefaultLocalPackageHistoryArchiveRunner }
    if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $ProjectRoot ('.local\history-exports\amazon-bs-history-{0}.zip' -f [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssZ')) }
    $stagingPath = Join-Path $ProjectRoot ('.local\history-export-' + [guid]::NewGuid().ToString('n'))
    try {
        & $FileSystemRunner 'CreateDirectory' @{Path=$stagingPath} | Out-Null
        & $FileSystemRunner 'CreateDirectory' @{Path=(Split-Path -Parent $OutputPath)} | Out-Null
        $backup = & $BackupRunner 'Create' @{ProjectRoot=$ProjectRoot}
        Test-LocalPackageHistoryRunnerStatus -Result $backup -Expected 'BACKED_UP' -Operation 'Backup creation'
        $backupPath = [string](Get-LocalPackageHistoryProperty $backup 'BackupPath')
        if ([string]::IsNullOrWhiteSpace($backupPath)) { throw 'Backup creation did not return a backup path.' }
        $verification = & $BackupRunner 'Verify' @{ProjectRoot=$ProjectRoot;BackupPath=$backupPath}
        Test-LocalPackageHistoryRunnerStatus -Result $verification -Expected 'VERIFIED' -Operation 'Backup verification'
        $sources = New-Object Collections.ArrayList
        [void]$sources.Add([pscustomobject]@{Source=$backupPath;Path='database/history.dump';Kind='database_dump'})
        $snapshotRoot = Join-Path $ProjectRoot 'var\amazon-bestsellers'
        foreach ($file in @(& $FileSystemRunner 'EnumerateFiles' @{Path=$snapshotRoot})) {
            $relative = Get-LocalPackageHistoryRelativePath -Root $snapshotRoot -Path ([string]$file.FullName)
            $leaf = Split-Path -Leaf $relative
            if ($relative -match '^\d{4}-\d{2}-\d{2}/(?:amazon-bestsellers|best-sellers-capture-receipt)\.json$') {
                [void]$sources.Add([pscustomobject]@{Source=[string]$file.FullName;Path=('snapshots/'+$relative);Kind=if($leaf -eq 'amazon-bestsellers.json'){'snapshot'}else{'capture_receipt'}})
            }
        }
        $reportRoot = Join-Path $ProjectRoot 'var\reports'
        foreach ($file in @(& $FileSystemRunner 'EnumerateFiles' @{Path=$reportRoot})) {
            $extension = [IO.Path]::GetExtension([string]$file.FullName).ToLowerInvariant()
            if ($extension -in @('.pdf','.html','.md')) {
                $relative = Get-LocalPackageHistoryRelativePath -Root $reportRoot -Path ([string]$file.FullName)
                if (-not (Test-LocalPackageHistoryReportRelativePath -Path $relative)) { continue }
                [void]$sources.Add([pscustomobject]@{Source=[string]$file.FullName;Path=('reports/'+$relative);Kind='report'})
            }
        }
        $items = New-Object Collections.ArrayList
        foreach ($source in @($sources | Sort-Object Path)) {
            $destination = Join-Path $stagingPath ([string]$source.Path).Replace('/','\')
            & $FileSystemRunner 'CopyFile' @{Source=$source.Source;Destination=$destination} | Out-Null
            $sourceHash = [string](& $HashRunner $source.Source)
            $stagedHash = [string](& $HashRunner $destination)
            if ($sourceHash -cne $stagedHash) { throw "Staged history item hash mismatch: $($source.Path)" }
            [void]$items.Add([ordered]@{path=[string]$source.Path;kind=[string]$source.Kind;sha256=$stagedHash;byte_count=[long](& $FileSystemRunner 'GetLength' @{Path=$destination})})
        }
        $manifest = [ordered]@{schema_version='local-package-history-v1';created_at=[DateTimeOffset]::UtcNow.ToString('o');items=@($items)}
        $manifestPath = Join-Path $stagingPath 'manifest.json'
        & $FileSystemRunner 'WriteUtf8' @{Path=$manifestPath;Content=($manifest|ConvertTo-Json -Depth 8)} | Out-Null
        & $ArchiveRunner 'Create' @{SourceRoot=$stagingPath;ArchivePath=$OutputPath;Manifest=$manifest} | Out-Null
        & $FileSystemRunner 'RemoveTree' @{Path=$stagingPath} | Out-Null
        $dumpItem = @($items | Where-Object {$_.kind -eq 'database_dump'})[0]
        return Protect-LocalPackageHistorySummary -Summary ([pscustomobject]@{status='EXPORTED_REDACTED';archive_path=$OutputPath;manifest_path='manifest.json';dump_hash=$dumpItem.sha256;count=$items.Count;staging_path=$stagingPath;error=$null}) -EnvironmentValueProvider $EnvironmentValueProvider
    }
    catch {
        return Protect-LocalPackageHistorySummary -Summary ([pscustomobject]@{status='FAILED';archive_path=$OutputPath;manifest_path=$null;dump_hash=$null;count=0;staging_path=$stagingPath;error=$_.Exception.Message}) -EnvironmentValueProvider $EnvironmentValueProvider
    }
}

function ConvertTo-LocalPackageHistoryArchiveEntries {
    param($Entries)
    $seen = @{}
    $validated = New-Object Collections.ArrayList
    foreach ($entry in @($Entries)) {
        $original = [string](Get-LocalPackageHistoryProperty $entry 'Path')
        if ([string]::IsNullOrWhiteSpace($original)) { throw 'History archive contains an empty entry name.' }
        if ($original -match '^[A-Za-z]:' -or $original.StartsWith('/') -or $original.StartsWith('\')) { throw "History archive contains an absolute entry: $original" }
        $path = $original.Replace('\','/').TrimEnd('/')
        $segments = @($path.Split('/'))
        if ($segments.Count -eq 0 -or @($segments | Where-Object {$_ -eq '..' -or $_ -eq '.' -or [string]::IsNullOrWhiteSpace($_)}).Count -gt 0) { throw "History archive contains a traversal or malformed entry: $original" }
        $key = $path.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { throw "History archive contains a duplicate entry: $path" }
        $seen[$key] = $true
        $isDirectory = [bool](Get-LocalPackageHistoryProperty $entry 'IsDirectory')
        if (-not $isDirectory -and $path -cne 'manifest.json' -and [string]::IsNullOrWhiteSpace((Get-LocalPackageHistoryKindForPath $path))) { throw "History archive contains an unexpected entry type: $path" }
        [void]$validated.Add([pscustomobject]@{Path=$path;IsDirectory=$isDirectory})
    }
    if (@($validated | Where-Object {-not $_.IsDirectory -and $_.Path -ceq 'manifest.json'}).Count -ne 1) { throw 'History archive manifest.json is missing.' }
    return @($validated)
}

function Invoke-LocalPackageHistoryImport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,[string]$ArchivePath,[switch]$RestoreDatabase,
        [scriptblock]$FileSystemRunner,[scriptblock]$HashRunner,[scriptblock]$BackupRunner,[scriptblock]$DatabaseRunner,[scriptblock]$ArchiveRunner,[scriptblock]$ReceiptRunner,[scriptblock]$EnvironmentValueProvider
    )
    if ($null -eq $FileSystemRunner) { $FileSystemRunner = Get-DefaultLocalPackageHistoryFileSystemRunner }
    if ($null -eq $HashRunner) { $HashRunner = Get-DefaultLocalPackageHistoryHashRunner }
    if ($null -eq $BackupRunner) { $BackupRunner = Get-DefaultLocalPackageHistoryBackupRunner }
    if ($null -eq $DatabaseRunner) { $DatabaseRunner = Get-DefaultLocalPackageHistoryDatabaseRunner }
    if ($null -eq $ArchiveRunner) { $ArchiveRunner = Get-DefaultLocalPackageHistoryArchiveRunner }
    if ($null -eq $ReceiptRunner) { $ReceiptRunner = Get-DefaultLocalPackageHistoryReceiptRunner }
    $stagingPath = $null
    $activeTemporary = $null
    try {
        if ([string]::IsNullOrWhiteSpace($ArchivePath)) { throw 'ArchivePath is required.' }
        $stagingPath = Join-Path $ProjectRoot ('.local\history-import-' + [guid]::NewGuid().ToString('n'))
        & $FileSystemRunner 'CreateDirectory' @{Path=$stagingPath} | Out-Null
        $verifiedArchivePath = Join-Path $stagingPath 'verified-source.zip'
        $identityBefore = & $ArchiveRunner 'Identity' @{ArchivePath=$ArchivePath}
        & $ArchiveRunner 'Copy' @{Source=$ArchivePath;Destination=$verifiedArchivePath} | Out-Null
        $identityAfter = & $ArchiveRunner 'Identity' @{ArchivePath=$ArchivePath}
        if ([string](Get-LocalPackageHistoryProperty $identityBefore 'Sha256') -cne [string](Get-LocalPackageHistoryProperty $identityAfter 'Sha256') -or [long](Get-LocalPackageHistoryProperty $identityBefore 'Length') -ne [long](Get-LocalPackageHistoryProperty $identityAfter 'Length')) { throw 'History archive identity changed while its private copy was created.' }
        $verifiedIdentity = & $ArchiveRunner 'Identity' @{ArchivePath=$verifiedArchivePath}
        if ([string](Get-LocalPackageHistoryProperty $identityBefore 'Sha256') -cne [string](Get-LocalPackageHistoryProperty $verifiedIdentity 'Sha256') -or [long](Get-LocalPackageHistoryProperty $identityBefore 'Length') -ne [long](Get-LocalPackageHistoryProperty $verifiedIdentity 'Length')) { throw 'History archive private copy identity does not match the verified source.' }
        $listed = @(& $ArchiveRunner 'List' @{ArchivePath=$verifiedArchivePath})
        $entries = ConvertTo-LocalPackageHistoryArchiveEntries -Entries $listed
        $verifiedIdentityAfterList = & $ArchiveRunner 'Identity' @{ArchivePath=$verifiedArchivePath}
        if ([string](Get-LocalPackageHistoryProperty $verifiedIdentity 'Sha256') -cne [string](Get-LocalPackageHistoryProperty $verifiedIdentityAfterList 'Sha256') -or [long](Get-LocalPackageHistoryProperty $verifiedIdentity 'Length') -ne [long](Get-LocalPackageHistoryProperty $verifiedIdentityAfterList 'Length')) { throw 'History archive private copy identity changed before extraction.' }
        & $ArchiveRunner 'Extract' @{ArchivePath=$verifiedArchivePath;Destination=$stagingPath} | Out-Null
        try { $manifest = (& $FileSystemRunner 'ReadUtf8' @{Path=(Join-Path $stagingPath 'manifest.json')}) | ConvertFrom-Json -ErrorAction Stop } catch { throw 'History archive manifest is malformed JSON.' }
        if ([string]$manifest.schema_version -cne 'local-package-history-v1') { throw 'History archive manifest schema is unsupported.' }
        $manifestItems = @($manifest.items)
        if ($manifestItems.Count -eq 0) { throw 'History archive manifest contains no items.' }
        $manifestSeen = @{}
        foreach ($item in $manifestItems) {
            $path = [string](Get-LocalPackageHistoryProperty $item 'path')
            $kind = [string](Get-LocalPackageHistoryProperty $item 'kind')
            $hash = [string](Get-LocalPackageHistoryProperty $item 'sha256')
            $byteCount = Get-LocalPackageHistoryProperty $item 'byte_count'
            $key = $path.ToLowerInvariant()
            if ($manifestSeen.ContainsKey($key)) { throw "History manifest contains a duplicate path: $path" }
            $manifestSeen[$key] = $true
            $expectedKind = Get-LocalPackageHistoryKindForPath $path
            if ([string]::IsNullOrWhiteSpace($expectedKind) -or $kind -cne $expectedKind) { throw "History manifest contains an unexpected path or kind: $path" }
            if ($hash -cnotmatch '^[0-9a-f]{64}$') { throw "History manifest contains a malformed SHA-256: $path" }
            $length = 0L
            if ($null -eq $byteCount -or -not [long]::TryParse([string]$byteCount,[ref]$length) -or $length -lt 0) { throw "History manifest contains an invalid byte count: $path" }
        }
        $archiveFiles = @($entries | Where-Object {-not $_.IsDirectory -and $_.Path -cne 'manifest.json'})
        if ($archiveFiles.Count -ne $manifestItems.Count) { throw 'History manifest item set does not match archive entries.' }
        foreach ($entry in $archiveFiles) { if (-not $manifestSeen.ContainsKey($entry.Path.ToLowerInvariant())) { throw "History manifest is missing archive entry: $($entry.Path)" } }
        foreach ($item in $manifestItems) {
            $path = [string]$item.path
            $stagedPath = Join-Path $stagingPath $path.Replace('/','\')
            $actualHash = [string](& $HashRunner $stagedPath)
            if ($actualHash -cne [string]$item.sha256) { throw "History checksum mismatch: $path" }
            if ([long](& $FileSystemRunner 'GetLength' @{Path=$stagedPath}) -ne [long]$item.byte_count) { throw "History size mismatch: $path" }
        }
        $dumpItems = @($manifestItems | Where-Object {$_.kind -eq 'database_dump'})
        if ($dumpItems.Count -ne 1) { throw 'History archive must contain exactly one database dump.' }
        $dumpPath = Join-Path $stagingPath ([string]$dumpItems[0].path).Replace('/','\')
        $backupValidation = & $BackupRunner 'Verify' @{ProjectRoot=$ProjectRoot;BackupPath=$dumpPath;ExpectedHash=[string]$dumpItems[0].sha256}
        Test-LocalPackageHistoryRunnerStatus -Result $backupValidation -Expected 'VERIFIED' -Operation 'Imported backup validation'
        $drill = & $DatabaseRunner 'RestoreDrill' @{ProjectRoot=$ProjectRoot;BackupPath=$dumpPath}
        Test-LocalPackageHistoryRunnerStatus -Result $drill -Expected 'RESTORE_DRILL_PASSED' -Operation 'Temporary database restore drill'
        $snapshotItems = @($manifestItems | Where-Object {$_.kind -eq 'snapshot'})
        foreach ($snapshot in $snapshotItems) {
            $directory = ([string]$snapshot.path).Substring(0,([string]$snapshot.path).LastIndexOf('/'))
            $receiptPath = $directory + '/best-sellers-capture-receipt.json'
            $receiptItem = @($manifestItems | Where-Object {[string]$_.path -ceq $receiptPath -and $_.kind -eq 'capture_receipt'})
            if ($receiptItem.Count -ne 1) { throw "Snapshot capture receipt is missing: $($snapshot.path)" }
            $receiptResult = & $ReceiptRunner (Join-Path $stagingPath ([string]$snapshot.path).Replace('/','\')) (Join-Path $stagingPath $receiptPath.Replace('/','\'))
            $valid = Get-LocalPackageHistoryProperty $receiptResult 'Valid'
            if ($null -eq $valid) { $valid = Get-LocalPackageHistoryProperty $receiptResult 'valid' }
            if (-not [bool]$valid) { throw "Snapshot capture receipt verification failed: $($snapshot.path)" }
        }
        $promotable = @($manifestItems | Where-Object {$_.kind -in @('snapshot','capture_receipt','report')})
        $promotionPlan = New-Object Collections.ArrayList
        $identical = 0
        foreach ($item in $promotable) {
            $path = [string]$item.path
            if ($item.kind -in @('snapshot','capture_receipt')) { $relative = $path.Substring('snapshots/'.Length); $destination = Join-Path $ProjectRoot ('var\amazon-bestsellers\' + $relative.Replace('/','\')) }
            else { $relative = $path.Substring('reports/'.Length); $destination = Join-Path $ProjectRoot ('var\reports\' + $relative.Replace('/','\')) }
            $exists = [bool](& $FileSystemRunner 'FileExists' @{Path=$destination})
            if ($exists) {
                if ([string](& $HashRunner $destination) -cne [string]$item.sha256) { throw "History destination collision with different content: $destination" }
                $identical++
            }
            else { [void]$promotionPlan.Add([pscustomobject]@{Item=$item;Source=(Join-Path $stagingPath $path.Replace('/','\'));Destination=$destination}) }
        }
        $restored = $false
        if ($RestoreDatabase.IsPresent) {
            $empty = [bool](& $DatabaseRunner 'IsPrimaryEmpty' @{ProjectRoot=$ProjectRoot})
            if ($empty) {
                $restore = & $DatabaseRunner 'RestorePrimary' @{ProjectRoot=$ProjectRoot;BackupPath=$dumpPath}
                Test-LocalPackageHistoryRunnerStatus -Result $restore -Expected 'RESTORED' -Operation 'Primary database restore'
                $restored = $true
            }
        }
        $promoted = 0
        foreach ($plan in $promotionPlan) {
            $activeTemporary = Join-Path (Split-Path -Parent $plan.Destination) ('.' + (Split-Path -Leaf $plan.Destination) + '.import-' + [guid]::NewGuid().ToString('n'))
            & $FileSystemRunner 'CopyFile' @{Source=$plan.Source;Destination=$activeTemporary} | Out-Null
            if ([string](& $HashRunner $activeTemporary) -cne [string]$plan.Item.sha256) { throw "Atomic promotion staging hash mismatch: $($plan.Item.path)" }
            & $FileSystemRunner 'AtomicMove' @{Source=$activeTemporary;Destination=$plan.Destination} | Out-Null
            $activeTemporary = $null
            $promoted++
        }
        & $FileSystemRunner 'RemoveTree' @{Path=$stagingPath} | Out-Null
        return Protect-LocalPackageHistorySummary -Summary ([pscustomobject]@{status=if($restored){'IMPORTED_AND_RESTORED'}else{'VALIDATED_NOT_RESTORED'};archive_path=$ArchivePath;manifest_path='manifest.json';count=$manifestItems.Count;promoted_count=$promoted;identical_count=$identical;database_restored=$restored;staging_path=$stagingPath;error=$null}) -EnvironmentValueProvider $EnvironmentValueProvider
    }
    catch {
        if (-not [string]::IsNullOrWhiteSpace($activeTemporary)) { try { & $FileSystemRunner 'DeleteFile' @{Path=$activeTemporary} | Out-Null } catch {} }
        return Protect-LocalPackageHistorySummary -Summary ([pscustomobject]@{status='FAILED';archive_path=$ArchivePath;manifest_path=$null;count=0;promoted_count=0;identical_count=0;database_restored=$false;staging_path=$stagingPath;error=$_.Exception.Message}) -EnvironmentValueProvider $EnvironmentValueProvider
    }
}

Export-ModuleMember -Function Invoke-LocalPackageHistoryExport,Invoke-LocalPackageHistoryImport
