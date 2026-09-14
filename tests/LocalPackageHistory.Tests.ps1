$projectRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $projectRoot 'src\LocalPackageHistory.psm1'

function New-HistoryTestFileSystemRunner {
    param([System.Collections.ArrayList]$Calls)
    return {
        param([string]$Operation,[hashtable]$Arguments)
        [void]$Calls.Add([pscustomobject]@{Operation=$Operation;Arguments=$Arguments})
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
            default { throw "Unexpected filesystem operation: $Operation" }
        }
    }.GetNewClosure()
}

function New-HistoryTestHashRunner {
    param([System.Collections.ArrayList]$Calls)
    return { param([string]$Path) [void]$Calls.Add($Path); (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }.GetNewClosure()
}

function New-HistoryImportFixture {
    param([string]$Root,[switch]$BadChecksum,[switch]$MalformedHash,[switch]$DuplicateManifestPath,[switch]$BadKind)
    New-Item -ItemType Directory -Path (Join-Path $Root 'database'),(Join-Path $Root 'snapshots\2026-08-11'),(Join-Path $Root 'reports\2026-08-11') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $Root 'database\history.dump'),'verified-dump')
    [IO.File]::WriteAllText((Join-Path $Root 'snapshots\2026-08-11\amazon-bestsellers.json'),'{"market_date":"2026-08-11"}')
    $snapshotHash = (Get-FileHash -LiteralPath (Join-Path $Root 'snapshots\2026-08-11\amazon-bestsellers.json')).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $Root 'snapshots\2026-08-11\best-sellers-capture-receipt.json'),('{"schema_version":"best-sellers-capture-receipt-v1","snapshot_sha256":"'+$snapshotHash+'","market_date":"2026-08-11"}'))
    [IO.File]::WriteAllText((Join-Path $Root 'reports\2026-08-11\daily.md'),'report')
    $items = @(
        [ordered]@{path='database/history.dump';kind='database_dump';sha256=(Get-FileHash -LiteralPath (Join-Path $Root 'database\history.dump')).Hash.ToLowerInvariant();byte_count=[long](Get-Item (Join-Path $Root 'database\history.dump')).Length},
        [ordered]@{path='snapshots/2026-08-11/amazon-bestsellers.json';kind='snapshot';sha256=$snapshotHash;byte_count=[long](Get-Item (Join-Path $Root 'snapshots\2026-08-11\amazon-bestsellers.json')).Length},
        [ordered]@{path='snapshots/2026-08-11/best-sellers-capture-receipt.json';kind='capture_receipt';sha256=(Get-FileHash -LiteralPath (Join-Path $Root 'snapshots\2026-08-11\best-sellers-capture-receipt.json')).Hash.ToLowerInvariant();byte_count=[long](Get-Item (Join-Path $Root 'snapshots\2026-08-11\best-sellers-capture-receipt.json')).Length},
        [ordered]@{path='reports/2026-08-11/daily.md';kind='report';sha256=(Get-FileHash -LiteralPath (Join-Path $Root 'reports\2026-08-11\daily.md')).Hash.ToLowerInvariant();byte_count=[long](Get-Item (Join-Path $Root 'reports\2026-08-11\daily.md')).Length}
    )
    if ($BadChecksum) { $items[3].sha256 = 'f' * 64 }
    if ($MalformedHash) { $items[3].sha256 = 'not-a-hash' }
    if ($BadKind) { $items[3].kind = 'credential' }
    if ($DuplicateManifestPath) { $items += [ordered]@{path='REPORTS/2026-08-11/DAILY.MD';kind='report';sha256=$items[3].sha256;byte_count=$items[3].byte_count} }
    [IO.File]::WriteAllText((Join-Path $Root 'manifest.json'),([ordered]@{schema_version='local-package-history-v1';created_at='2026-08-11T00:00:00Z';items=$items} | ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
}

function New-HistoryTestArchiveRunner {
    param([string]$FixtureRoot,[System.Collections.ArrayList]$Calls,[object[]]$Entries)
    if ($null -eq $Entries) {
        $Entries = @(Get-ChildItem -LiteralPath $FixtureRoot -File -Recurse | ForEach-Object { [pscustomobject]@{Path=$_.FullName.Substring($FixtureRoot.Length+1).Replace('\','/');IsDirectory=$false} })
    }
    return {
        param([string]$Operation,[hashtable]$Arguments)
        [void]$Calls.Add([pscustomobject]@{Operation=$Operation;Arguments=$Arguments})
        if ($Operation -eq 'Identity') { return [pscustomobject]@{Sha256=('a'*64);Length=1234} }
        if ($Operation -eq 'Copy') { [IO.File]::WriteAllText($Arguments.Destination,'fake verified archive'); return $Arguments.Destination }
        if ($Operation -eq 'List') { return $Entries }
        if ($Operation -eq 'Extract') { Copy-Item -Path (Join-Path $FixtureRoot '*') -Destination $Arguments.Destination -Recurse; return $Arguments.Destination }
        if ($Operation -eq 'Create') { [IO.File]::WriteAllText($Arguments.ArchivePath,'fake archive'); return $Arguments.ArchivePath }
        throw "Unexpected archive operation: $Operation"
    }.GetNewClosure()
}

Describe 'Local package history export' {
    BeforeAll { Import-Module $modulePath -Force }

    It 'exports only a fresh verified dump, canonical snapshots and receipts, and approved report formats with verified hashes' {
        $root = Join-Path $TestDrive 'export-project'
        foreach ($entry in @(
            @{Path='var\amazon-bestsellers\2026-08-11\amazon-bestsellers.json';Text='snapshot'},
            @{Path='var\amazon-bestsellers\2026-08-11\best-sellers-capture-receipt.json';Text='receipt'},
            @{Path='var\amazon-bestsellers\2026-08-11\collection.log';Text='log-secret'},
            @{Path='var\amazon-bestsellers\2026-08-11\source-config.json';Text='source-secret'},
            @{Path='var\amazon-bestsellers\browser-profile\amazon-bestsellers.json';Text='profile-secret'},
            @{Path='var\amazon-bestsellers\cache\best-sellers-capture-receipt.json';Text='cache-secret'},
            @{Path='var\reports\2026-08-11\daily.pdf';Text='pdf'},
            @{Path='var\reports\2026-08-11\daily.html';Text='html'},
            @{Path='var\reports\2026-08-11\daily.md';Text='markdown'},
            @{Path='var\reports\2026-08-11\email-delivery-summary.json';Text='smtp-secret'},
            @{Path='var\reports\2026-08-11\cache.tmp';Text='cache'},
            @{Path='var\reports\cache\plausible.pdf';Text='report-cache-secret'},
            @{Path='var\reports\browser-profile\plausible.md';Text='report-profile-secret'},
            @{Path='var\reports\tmp\plausible.html';Text='report-temp-secret'},
            @{Path='var\reports\credentials\2026-08-11\plausible.pdf';Text='credential-directory-secret'},
            @{Path='var\reports\source-config\nested\plausible.md';Text='source-config-directory-secret'},
            @{Path='var\reports\2026-08-11\credentials\plausible.html';Text='nested-credential-directory-secret'},
            @{Path='var\reports\2026-08-11\database-credentials.pdf';Text='report-credential-secret'},
            @{Path='var\reports\2026-08-11\source-config.md';Text='report-source-secret'},
            @{Path='.local\postgres-settings.json';Text='database-secret'},
            @{Path='.env';Text='environment-secret'}
        )) { $path=Join-Path $root $entry.Path; New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null; [IO.File]::WriteAllText($path,$entry.Text) }
        $backup = Join-Path $root '.local\postgres-backups\fresh.dump'
        New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
        [IO.File]::WriteAllText($backup,'fresh-backup')
        $fsCalls=New-Object Collections.ArrayList; $hashCalls=New-Object Collections.ArrayList; $archiveCalls=New-Object Collections.ArrayList; $backupCalls=New-Object Collections.ArrayList
        $backupRunner = { param($op,$args) [void]$backupCalls.Add($op); if ($op -eq 'Create') { [pscustomobject]@{Status='BACKED_UP';BackupPath=$backup} } else { [pscustomobject]@{Status='VERIFIED';HashMatches=$true} } }.GetNewClosure()

        $result = Invoke-LocalPackageHistoryExport -ProjectRoot $root -OutputPath (Join-Path $root 'history.zip') -FileSystemRunner (New-HistoryTestFileSystemRunner $fsCalls) -HashRunner (New-HistoryTestHashRunner $hashCalls) -BackupRunner $backupRunner -ArchiveRunner (New-HistoryTestArchiveRunner -FixtureRoot $root -Calls $archiveCalls)

        $result.status | Should Be 'EXPORTED_REDACTED'
        @($backupCalls) | Should Be @('Create','Verify')
        $archiveCalls.Count | Should Be 1
        $archiveCalls[0].Operation | Should Be 'Create'
        $manifest = $archiveCalls[0].Arguments.Manifest
        @($manifest.items.path) | Should Be @('database/history.dump','reports/2026-08-11/daily.html','reports/2026-08-11/daily.md','reports/2026-08-11/daily.pdf','snapshots/2026-08-11/amazon-bestsellers.json','snapshots/2026-08-11/best-sellers-capture-receipt.json')
        @($manifest.items | Where-Object { $_.sha256 -notmatch '^[0-9a-f]{64}$' -or $_.byte_count -le 0 }).Count | Should Be 0
        ($manifest | ConvertTo-Json -Depth 8) | Should Not Match 'secret|source-config|collection\.log|email-delivery-summary|cache\.tmp|\.env|postgres-settings'
        $result.dump_hash | Should Be (Get-FileHash -LiteralPath $backup).Hash.ToLowerInvariant()
        $result.count | Should Be 6
        Test-Path -LiteralPath $backup | Should Be $true
        @($hashCalls).Count | Should Be 12
        @($fsCalls | Where-Object Operation -eq 'RemoveTree').Count | Should Be 1
        @($fsCalls | Where-Object Operation -in @('DeleteFile','DeleteSource')).Count | Should Be 0
    }

    It 'retains failed staging, skips archive creation, and redacts Process and User secrets when backup verification fails' {
        $root=Join-Path $TestDrive 'smtp-process-secret-export-failure'; $backup=Join-Path $root '.local\backups\fresh.dump'; New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null; [IO.File]::WriteAllText($backup,'dump')
        $fsCalls=New-Object Collections.ArrayList; $archiveCalls=New-Object Collections.ArrayList
        $backupRunner={param($op,$args) if($op -eq 'Create'){[pscustomobject]@{Status='BACKED_UP';BackupPath=$backup}}else{throw 'verify smtp-process-secret postgres-user-secret'}}.GetNewClosure()
        $provider={param($name,$scope) if($scope -eq 'Process'){'smtp-process-secret'}else{'postgres-user-secret'}}

        $result=Invoke-LocalPackageHistoryExport -ProjectRoot $root -OutputPath (Join-Path $root 'history.zip') -FileSystemRunner (New-HistoryTestFileSystemRunner $fsCalls) -HashRunner (New-HistoryTestHashRunner (New-Object Collections.ArrayList)) -BackupRunner $backupRunner -ArchiveRunner (New-HistoryTestArchiveRunner -FixtureRoot $root -Calls $archiveCalls) -EnvironmentValueProvider $provider

        $result.status | Should Be 'FAILED'
        $result.error | Should Match '\[REDACTED\]'
        $result.error | Should Not Match 'smtp-process-secret|postgres-user-secret'
        $result.archive_path | Should Not Match 'smtp-process-secret|postgres-user-secret'
        $result.staging_path | Should Not Match 'smtp-process-secret|postgres-user-secret'
        $result.status | Should Be 'FAILED'
        $rawStaging=@($fsCalls|Where-Object{$_.Operation -eq 'CreateDirectory' -and $_.Arguments.Path -match 'history-export-'})[0].Arguments.Path
        Test-Path -LiteralPath $rawStaging -PathType Container | Should Be $true
        $archiveCalls.Count | Should Be 0
        @($fsCalls | Where-Object Operation -eq 'RemoveTree').Count | Should Be 0
    }

    It 'retains staging and never archives when a staged export copy has a different hash' {
        $root=Join-Path $TestDrive 'export-stage-mismatch';$backup=Join-Path $root '.local\backups\fresh.dump';New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force|Out-Null;[IO.File]::WriteAllText($backup,'dump')
        $fsCalls=New-Object Collections.ArrayList;$archiveCalls=New-Object Collections.ArrayList
        $hash={param($path)if($path -match '\.local\\history-export-'){return 'f'*64};return 'a'*64}
        $backupRunner={param($op,$args)if($op -eq 'Create'){[pscustomobject]@{Status='BACKED_UP';BackupPath=$backup}}else{[pscustomobject]@{Status='VERIFIED';HashMatches=$true}}}.GetNewClosure()
        $result=Invoke-LocalPackageHistoryExport -ProjectRoot $root -OutputPath (Join-Path $root 'history.zip') -FileSystemRunner (New-HistoryTestFileSystemRunner $fsCalls) -HashRunner $hash -BackupRunner $backupRunner -ArchiveRunner (New-HistoryTestArchiveRunner -FixtureRoot $root -Calls $archiveCalls)
        $result.status|Should Be 'FAILED';$result.error|Should Match 'hash mismatch';$archiveCalls.Count|Should Be 0;Test-Path -LiteralPath $result.staging_path -PathType Container|Should Be $true;Test-Path -LiteralPath $backup -PathType Leaf|Should Be $true;@($fsCalls|Where-Object Operation -eq 'RemoveTree').Count|Should Be 0
    }
}

Describe 'Local package history import validation' {
    BeforeAll { Import-Module $modulePath -Force }

    It 'rejects absolute, traversal, duplicate, missing-manifest, and unexpected archive entries before extraction' {
        foreach ($entries in @(
            @('../escape.md','manifest.json'),
            @('C:/absolute.md','manifest.json'),
            @('/rooted.md','manifest.json'),
            @('manifest.json','reports/a.md','REPORTS/A.MD'),
            @('manifest.json','scripts/evil.ps1'),
            @('database/history.dump','reports/a.md')
        )) {
            $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('n')); New-Item -ItemType Directory -Path $root -Force | Out-Null
            $archiveCalls=New-Object Collections.ArrayList; $fsCalls=New-Object Collections.ArrayList
            $objects=@($entries | ForEach-Object {[pscustomobject]@{Path=$_;IsDirectory=$false}})
            $archive=New-HistoryTestArchiveRunner -FixtureRoot $root -Calls $archiveCalls -Entries $objects
            $result=Invoke-LocalPackageHistoryImport -ProjectRoot $root -ArchivePath (Join-Path $root 'input.zip') -FileSystemRunner (New-HistoryTestFileSystemRunner $fsCalls) -HashRunner {throw 'hash must not run'} -BackupRunner {throw 'backup must not run'} -DatabaseRunner {throw 'database must not run'} -ArchiveRunner $archive -ReceiptRunner {throw 'receipt must not run'}

            $result.status | Should Be 'FAILED'
            @($archiveCalls.Operation) | Should Be @('Identity','Copy','Identity','Identity','List')
            @($fsCalls | Where-Object Operation -eq 'AtomicMove').Count | Should Be 0
            Test-Path -LiteralPath $result.staging_path -PathType Container | Should Be $true
        }
    }

    It 'rejects malformed JSON, schema, hashes, item sets, kinds, sizes, and checksums after extraction and retains staging' {
        foreach ($case in @('MalformedJson','BadSchema','EmptyItems','MissingItem','SizeMismatch','Malformed','Duplicate','BadKind','Mismatch')) {
            $root=Join-Path $TestDrive ('invalid-'+$case); $fixture=Join-Path $TestDrive ('fixture-'+$case); New-Item -ItemType Directory -Path $root,$fixture -Force | Out-Null
            if($case -eq 'Malformed'){New-HistoryImportFixture -Root $fixture -MalformedHash}elseif($case -eq 'Duplicate'){New-HistoryImportFixture -Root $fixture -DuplicateManifestPath}elseif($case -eq 'BadKind'){New-HistoryImportFixture -Root $fixture -BadKind}elseif($case -eq 'Mismatch'){New-HistoryImportFixture -Root $fixture -BadChecksum}else{
                New-HistoryImportFixture -Root $fixture
                $manifestPath=Join-Path $fixture 'manifest.json'
                if($case -eq 'MalformedJson'){[IO.File]::WriteAllText($manifestPath,'{')}
                else{$manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json;if($case -eq 'BadSchema'){$manifest.schema_version='bad-schema'}elseif($case -eq 'EmptyItems'){$manifest.items=@()}elseif($case -eq 'MissingItem'){$manifest.items=@($manifest.items|Select-Object -First 3)}elseif($case -eq 'SizeMismatch'){$manifest.items[3].byte_count=[long]$manifest.items[3].byte_count+1};[IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 8))}
            }
            $archiveCalls=New-Object Collections.ArrayList; $fsCalls=New-Object Collections.ArrayList
            $result=Invoke-LocalPackageHistoryImport -ProjectRoot $root -ArchivePath (Join-Path $root 'input.zip') -FileSystemRunner (New-HistoryTestFileSystemRunner $fsCalls) -HashRunner (New-HistoryTestHashRunner (New-Object Collections.ArrayList)) -BackupRunner {throw 'backup must not run'} -DatabaseRunner {throw 'database must not run'} -ArchiveRunner (New-HistoryTestArchiveRunner -FixtureRoot $fixture -Calls $archiveCalls) -ReceiptRunner {throw 'receipt must not run'}

            $result.status | Should Be 'FAILED'
            Test-Path -LiteralPath $result.staging_path -PathType Container | Should Be $true
            @($archiveCalls.Operation) | Should Be @('Identity','Copy','Identity','Identity','List','Identity','Extract')
            @($fsCalls | Where-Object Operation -eq 'RemoveTree').Count | Should Be 0
        }
    }

    It 'rejects a source archive whose identity changes while its private copy is created' {
        $root=Join-Path $TestDrive 'identity-change';New-Item -ItemType Directory -Path $root -Force|Out-Null
        $calls=New-Object Collections.ArrayList;$identityCalls=New-Object Collections.ArrayList
        $archive={param($op,$arguments)[void]$calls.Add($op);if($op -eq 'Identity'){[void]$identityCalls.Add($op);return [pscustomobject]@{Sha256=if($identityCalls.Count -eq 1){'a'*64}else{'b'*64};Length=10}};if($op -eq 'Copy'){[IO.File]::WriteAllText($arguments.Destination,'copy');return $arguments.Destination};throw 'list and extract must not run'}.GetNewClosure()
        $result=Invoke-LocalPackageHistoryImport -ProjectRoot $root -ArchivePath (Join-Path $root 'input.zip') -FileSystemRunner (New-HistoryTestFileSystemRunner (New-Object Collections.ArrayList)) -HashRunner {throw 'must not hash'} -BackupRunner {throw 'must not backup'} -DatabaseRunner {throw 'must not database'} -ArchiveRunner $archive -ReceiptRunner {throw 'must not receipt'}
        $result.status|Should Be 'FAILED';$result.error|Should Match 'changed|identity';@($calls)|Should Be @('Identity','Copy','Identity');Test-Path -LiteralPath $result.staging_path -PathType Container|Should Be $true
    }

    It 'rejects a private archive copy whose hash or size differs from the verified source' {
        foreach($mismatch in @('Hash','Size')){
            $root=Join-Path $TestDrive ('private-copy-'+$mismatch);New-Item -ItemType Directory -Path $root -Force|Out-Null
            $calls=New-Object Collections.ArrayList;$verifiedArchive=[pscustomobject]@{Path=$null}
            $archive={
                param([string]$operation,[hashtable]$arguments)
                [void]$calls.Add($operation)
                if($operation -eq 'Copy'){$verifiedArchive.Path=$arguments.Destination;[IO.File]::WriteAllText($arguments.Destination,'copy');return $arguments.Destination}
                if($operation -eq 'Identity'){
                    if($arguments.ArchivePath -eq $verifiedArchive.Path){return [pscustomobject]@{Sha256=if($mismatch -eq 'Hash'){'b'*64}else{'a'*64};Length=if($mismatch -eq 'Size'){11}else{10}}}
                    return [pscustomobject]@{Sha256='a'*64;Length=10}
                }
                throw 'list and extract must not run for an unverified private copy'
            }.GetNewClosure()

            $result=Invoke-LocalPackageHistoryImport -ProjectRoot $root -ArchivePath (Join-Path $root 'input.zip') -FileSystemRunner (New-HistoryTestFileSystemRunner (New-Object Collections.ArrayList)) -HashRunner {throw 'must not hash payloads'} -BackupRunner {throw 'must not backup'} -DatabaseRunner {throw 'must not database'} -ArchiveRunner $archive -ReceiptRunner {throw 'must not receipt'}

            $result.status|Should Be 'FAILED'
            $result.error|Should Match 'private copy identity'
            @($calls)|Should Be @('Identity','Copy','Identity','Identity')
            Test-Path -LiteralPath $result.staging_path -PathType Container|Should Be $true
        }
    }

    It 'extracts only a verified private archive copy when the source changes after its final identity check' {
        $root=Join-Path $TestDrive 'source-replacement';$fixture=Join-Path $TestDrive 'source-replacement-fixture';New-Item -ItemType Directory -Path $root,$fixture -Force|Out-Null;New-HistoryImportFixture -Root $fixture
        $sourceArchive=Join-Path $root 'input.zip';[IO.File]::WriteAllText($sourceArchive,'verified-source-bytes')
        $calls=New-Object Collections.ArrayList;$sourceIdentityCalls=New-Object Collections.ArrayList;$verifiedArchive=[pscustomobject]@{Path=$null}
        $entries=@(Get-ChildItem -LiteralPath $fixture -File -Recurse|ForEach-Object{[pscustomobject]@{Path=$_.FullName.Substring($fixture.Length+1).Replace('\','/');IsDirectory=$false}})
        $archive={
            param([string]$operation,[hashtable]$arguments)
            [void]$calls.Add([pscustomobject]@{Operation=$operation;ArchivePath=$arguments.ArchivePath;Source=$arguments.Source;Destination=$arguments.Destination})
            if($operation -eq 'Identity'){
                if($arguments.ArchivePath -eq $sourceArchive){
                    [void]$sourceIdentityCalls.Add($operation)
                    $identity=[pscustomobject]@{Sha256='a'*64;Length=21}
                    if($sourceIdentityCalls.Count -eq 2){[IO.File]::WriteAllText($sourceArchive,'replacement-after-final-source-check')}
                    return $identity
                }
                if($arguments.ArchivePath -eq $verifiedArchive.Path){return [pscustomobject]@{Sha256='a'*64;Length=21}}
            }
            if($operation -eq 'Copy'){$verifiedArchive.Path=$arguments.Destination;[IO.File]::WriteAllText($arguments.Destination,'verified-source-bytes');return $arguments.Destination}
            if($operation -eq 'List'){
                if($arguments.ArchivePath -ne $verifiedArchive.Path){throw 'the mutable source archive was listed'}
                return $entries
            }
            if($operation -eq 'Extract'){
                if($arguments.ArchivePath -ne $verifiedArchive.Path){throw 'the mutable source archive was extracted'}
                Copy-Item -Path (Join-Path $fixture '*') -Destination $arguments.Destination -Recurse
                return $arguments.Destination
            }
            throw "Unexpected archive operation: $operation"
        }.GetNewClosure()

        $result=Invoke-LocalPackageHistoryImport -ProjectRoot $root -ArchivePath $sourceArchive -FileSystemRunner (New-HistoryTestFileSystemRunner (New-Object Collections.ArrayList)) -HashRunner (New-HistoryTestHashRunner (New-Object Collections.ArrayList)) -BackupRunner {[pscustomobject]@{Status='VERIFIED';HashMatches=$true}} -DatabaseRunner {[pscustomobject]@{Status='RESTORE_DRILL_PASSED'}} -ArchiveRunner $archive -ReceiptRunner {[pscustomobject]@{Valid=$true}}

        $result.status|Should Be 'VALIDATED_NOT_RESTORED'
        @($calls|Where-Object Operation -in @('List','Extract')|ForEach-Object ArchivePath|Select-Object -Unique)|Should Be @($verifiedArchive.Path)
        @($calls|Where-Object{($_.Operation -in @('List','Extract')) -and $_.ArchivePath -eq $sourceArchive}).Count|Should Be 0
        (Get-Content -LiteralPath (Join-Path $root 'var\reports\2026-08-11\daily.md') -Raw)|Should Be 'report'
        (Get-Content -LiteralPath $sourceArchive -Raw)|Should Be 'replacement-after-final-source-check'
    }
}

Describe 'Local package history import validation, restore gating, and promotion' {
    BeforeAll { Import-Module $modulePath -Force }

    It 'validates backup and restore drill, verifies receipts, skips identical files, and atomically promotes absent content' {
        $root=Join-Path $TestDrive 'safe-import'; $fixture=Join-Path $TestDrive 'safe-fixture'; New-Item -ItemType Directory -Path $root,$fixture -Force | Out-Null; New-HistoryImportFixture -Root $fixture
        $sameReport=Join-Path $root 'var\reports\2026-08-11\daily.md'; New-Item -ItemType Directory -Path (Split-Path -Parent $sameReport) -Force | Out-Null; [IO.File]::WriteAllText($sameReport,'report')
        $fsCalls=New-Object Collections.ArrayList; $backupCalls=New-Object Collections.ArrayList; $dbCalls=New-Object Collections.ArrayList; $receiptCalls=New-Object Collections.ArrayList
        $backup={param($op,$args)[void]$backupCalls.Add($op);[pscustomobject]@{Status='VERIFIED';HashMatches=$true}}.GetNewClosure()
        $db={param($op,$args)[void]$dbCalls.Add($op);[pscustomobject]@{Status='RESTORE_DRILL_PASSED'}}.GetNewClosure()
        $receipt={param($snapshot,$receipt)[void]$receiptCalls.Add([pscustomobject]@{Snapshot=$snapshot;Receipt=$receipt});[pscustomobject]@{Valid=$true}}.GetNewClosure()

        $result=Invoke-LocalPackageHistoryImport -ProjectRoot $root -ArchivePath (Join-Path $root 'input.zip') -FileSystemRunner (New-HistoryTestFileSystemRunner $fsCalls) -HashRunner (New-HistoryTestHashRunner (New-Object Collections.ArrayList)) -BackupRunner $backup -DatabaseRunner $db -ArchiveRunner (New-HistoryTestArchiveRunner -FixtureRoot $fixture -Calls (New-Object Collections.ArrayList)) -ReceiptRunner $receipt

        $result.status | Should Be 'VALIDATED_NOT_RESTORED'
        @($backupCalls) | Should Be @('Verify')
        @($dbCalls) | Should Be @('RestoreDrill')
        $receiptCalls.Count | Should Be 1
        @($fsCalls | Where-Object Operation -eq 'AtomicMove').Count | Should Be 2
        @($fsCalls | Where-Object Operation -eq 'RemoveTree').Count | Should Be 1
        Test-Path -LiteralPath (Join-Path $root 'var\amazon-bestsellers\2026-08-11\amazon-bestsellers.json') | Should Be $true
        Test-Path -LiteralPath (Join-Path $root 'var\amazon-bestsellers\2026-08-11\best-sellers-capture-receipt.json') | Should Be $true
        (Get-Content -LiteralPath $sameReport -Raw) | Should Be 'report'
    }

    It 'restores primary only with the explicit flag and an empty-data probe' {
        foreach($case in @(@{Flag=$false;Empty=$true;Restores=0;Status='VALIDATED_NOT_RESTORED'},@{Flag=$true;Empty=$false;Restores=0;Status='VALIDATED_NOT_RESTORED'},@{Flag=$true;Empty=$true;Restores=1;Status='IMPORTED_AND_RESTORED'})){
            $root=Join-Path $TestDrive ('restore-'+[guid]::NewGuid().ToString('n'));$fixture=Join-Path $TestDrive ('restore-fixture-'+[guid]::NewGuid().ToString('n'));New-Item -ItemType Directory -Path $root,$fixture -Force|Out-Null;New-HistoryImportFixture -Root $fixture
            $dbCalls=New-Object Collections.ArrayList;$empty=$case.Empty
            $db={param($op,$args)[void]$dbCalls.Add($op);if($op -eq 'IsPrimaryEmpty'){return $empty};if($op -eq 'RestorePrimary'){return [pscustomobject]@{Status='RESTORED'}};[pscustomobject]@{Status='RESTORE_DRILL_PASSED'}}.GetNewClosure()
            $params=@{ProjectRoot=$root;ArchivePath=(Join-Path $root 'input.zip');FileSystemRunner=(New-HistoryTestFileSystemRunner (New-Object Collections.ArrayList));HashRunner=(New-HistoryTestHashRunner (New-Object Collections.ArrayList));BackupRunner={[pscustomobject]@{Status='VERIFIED';HashMatches=$true}};DatabaseRunner=$db;ArchiveRunner=(New-HistoryTestArchiveRunner -FixtureRoot $fixture -Calls (New-Object Collections.ArrayList));ReceiptRunner={[pscustomobject]@{Valid=$true}}}
            if($case.Flag){$params.RestoreDatabase=$true}
            $result=Invoke-LocalPackageHistoryImport @params
            $result.status | Should Be $case.Status
            @($dbCalls|Where-Object{$_ -eq 'RestorePrimary'}).Count | Should Be $case.Restores
        }
    }

    It 'preflights different-content collisions before any promotion and retains failed staging without overwriting' {
        $root=Join-Path $TestDrive 'collision';$fixture=Join-Path $TestDrive 'collision-fixture';New-Item -ItemType Directory -Path $root,$fixture -Force|Out-Null;New-HistoryImportFixture -Root $fixture
        $existing=Join-Path $root 'var\reports\2026-08-11\daily.md';New-Item -ItemType Directory -Path (Split-Path -Parent $existing) -Force|Out-Null;[IO.File]::WriteAllText($existing,'keep-existing')
        $fsCalls=New-Object Collections.ArrayList
        $result=Invoke-LocalPackageHistoryImport -ProjectRoot $root -ArchivePath (Join-Path $root 'input.zip') -FileSystemRunner (New-HistoryTestFileSystemRunner $fsCalls) -HashRunner (New-HistoryTestHashRunner (New-Object Collections.ArrayList)) -BackupRunner {[pscustomobject]@{Status='VERIFIED';HashMatches=$true}} -DatabaseRunner {[pscustomobject]@{Status='RESTORE_DRILL_PASSED'}} -ArchiveRunner (New-HistoryTestArchiveRunner -FixtureRoot $fixture -Calls (New-Object Collections.ArrayList)) -ReceiptRunner {[pscustomobject]@{Valid=$true}}
        $result.status | Should Be 'FAILED';$result.error | Should Match 'collision';(Get-Content -LiteralPath $existing -Raw)|Should Be 'keep-existing';@($fsCalls|Where-Object Operation -eq 'AtomicMove').Count|Should Be 0;Test-Path -LiteralPath $result.staging_path -PathType Container|Should Be $true
    }

    It 'retains staging and redacts scoped secrets when receipt verification fails' {
        $root=Join-Path $TestDrive 'smtp-secret-receipt-failure';$fixture=Join-Path $TestDrive 'receipt-fixture';New-Item -ItemType Directory -Path $root,$fixture -Force|Out-Null;New-HistoryImportFixture -Root $fixture;$fsCalls=New-Object Collections.ArrayList
        $provider={param($name,$scope)if($scope -eq 'Process'){'smtp-secret'}else{'postgres-secret'}}
        $result=Invoke-LocalPackageHistoryImport -ProjectRoot $root -ArchivePath (Join-Path $root 'postgres-secret-input.zip') -FileSystemRunner (New-HistoryTestFileSystemRunner $fsCalls) -HashRunner (New-HistoryTestHashRunner (New-Object Collections.ArrayList)) -BackupRunner {[pscustomobject]@{Status='VERIFIED';HashMatches=$true}} -DatabaseRunner {[pscustomobject]@{Status='RESTORE_DRILL_PASSED'}} -ArchiveRunner (New-HistoryTestArchiveRunner -FixtureRoot $fixture -Calls (New-Object Collections.ArrayList)) -ReceiptRunner {throw 'receipt smtp-secret postgres-secret'} -EnvironmentValueProvider $provider
        $result.status|Should Be 'FAILED';$result.error|Should Match '\[REDACTED\]';$result.error|Should Not Match 'smtp-secret|postgres-secret';$result.archive_path|Should Not Match 'smtp-secret|postgres-secret';$result.staging_path|Should Not Match 'smtp-secret|postgres-secret';@($fsCalls|Where-Object Operation -eq 'RemoveTree').Count|Should Be 0
    }

    It 'retains staging and removes only the temporary promotion copy when its hash mismatches' {
        $root=Join-Path $TestDrive 'promotion-hash';$fixture=Join-Path $TestDrive 'promotion-hash-fixture';New-Item -ItemType Directory -Path $root,$fixture -Force|Out-Null;New-HistoryImportFixture -Root $fixture;$fsCalls=New-Object Collections.ArrayList
        $hash={param($path)if($path -match '\.import-'){return 'f'*64};(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
        $result=Invoke-LocalPackageHistoryImport -ProjectRoot $root -ArchivePath (Join-Path $root 'input.zip') -FileSystemRunner (New-HistoryTestFileSystemRunner $fsCalls) -HashRunner $hash -BackupRunner {[pscustomobject]@{Status='VERIFIED';HashMatches=$true}} -DatabaseRunner {[pscustomobject]@{Status='RESTORE_DRILL_PASSED'}} -ArchiveRunner (New-HistoryTestArchiveRunner -FixtureRoot $fixture -Calls (New-Object Collections.ArrayList)) -ReceiptRunner {[pscustomobject]@{Valid=$true}}
        $result.status|Should Be 'FAILED';$result.error|Should Match 'promotion staging hash mismatch';@($fsCalls|Where-Object Operation -eq 'AtomicMove').Count|Should Be 0;@($fsCalls|Where-Object Operation -eq 'DeleteFile').Count|Should Be 1;Test-Path -LiteralPath $result.staging_path -PathType Container|Should Be $true
    }

    It 'retains staging and leaves no destination when an atomic move fails' {
        $root=Join-Path $TestDrive 'atomic-failure';$fixture=Join-Path $TestDrive 'atomic-fixture';New-Item -ItemType Directory -Path $root,$fixture -Force|Out-Null;New-HistoryImportFixture -Root $fixture;$fsCalls=New-Object Collections.ArrayList;$base=New-HistoryTestFileSystemRunner $fsCalls
        $fs={param([string]$operation,[hashtable]$arguments)if($operation -eq 'AtomicMove'){[void]$fsCalls.Add([pscustomobject]@{Operation=$operation;Arguments=$arguments});throw 'atomic move failed'};& $base $operation $arguments}.GetNewClosure()
        $result=Invoke-LocalPackageHistoryImport -ProjectRoot $root -ArchivePath (Join-Path $root 'input.zip') -FileSystemRunner $fs -HashRunner (New-HistoryTestHashRunner (New-Object Collections.ArrayList)) -BackupRunner {[pscustomobject]@{Status='VERIFIED';HashMatches=$true}} -DatabaseRunner {[pscustomobject]@{Status='RESTORE_DRILL_PASSED'}} -ArchiveRunner (New-HistoryTestArchiveRunner -FixtureRoot $fixture -Calls (New-Object Collections.ArrayList)) -ReceiptRunner {[pscustomobject]@{Valid=$true}}
        $result.status|Should Be 'FAILED';$result.error|Should Match 'atomic move failed';@($fsCalls|Where-Object Operation -eq 'AtomicMove').Count|Should Be 1;@($fsCalls|Where-Object Operation -eq 'DeleteFile').Count|Should Be 1;Test-Path -LiteralPath $result.staging_path -PathType Container|Should Be $true;Test-Path -LiteralPath (Join-Path $root 'var\amazon-bestsellers\2026-08-11\amazon-bestsellers.json')|Should Be $false
    }
}

Describe 'Local package primary database empty-data probe' {
    BeforeAll { Import-Module $modulePath -Force }
    It 'checks every persisted run and analysis table and blocks on any nonzero count' {
        $tables=@('collection_run','best_sellers_run','public_intelligence_run','best_sellers_analysis_run','best_sellers_market_structure_run','best_sellers_rank_influence_run')
        foreach($nonempty in $tables){$queried=New-Object Collections.ArrayList;$runner={param($table)[void]$queried.Add($table);if($table -eq $nonempty){1}else{0}}.GetNewClosure();$empty=& (Get-Module LocalPackageHistory) {param($queryRunner) Test-LocalPackageHistoryPrimaryDatabaseEmpty -QueryRunner $queryRunner} $runner;$empty|Should Be $false;(@($queried) -contains $nonempty)|Should Be $true}
        $queried=New-Object Collections.ArrayList;$runner={param($table)[void]$queried.Add($table);0}.GetNewClosure();$empty=& (Get-Module LocalPackageHistory) {param($queryRunner) Test-LocalPackageHistoryPrimaryDatabaseEmpty -QueryRunner $queryRunner} $runner;$empty|Should Be $true;@($queried)|Should Be $tables
    }
}

Describe 'Local package history child script JSON boundaries' {
    It 'emits exactly one JSON result and the correct exit code for export and import success and thrown failure' {
        foreach($scriptCase in @(@{Script='Export-LocalPackageHistory.ps1';Function='Invoke-LocalPackageHistoryExport';Arguments=@{OutputPath=(Join-Path $TestDrive 'out.zip')}},@{Script='Import-LocalPackageHistory.ps1';Function='Invoke-LocalPackageHistoryImport';Arguments=@{ArchivePath=(Join-Path $TestDrive 'in.zip')}})){
            $successModule=Join-Path $TestDrive ($scriptCase.Function+'Success.psm1');$successSource=('function {0} {{ [pscustomobject]@{{status=''SUCCESS'';archive_path=$env:PGPASSWORD;staging_path=$env:PGPASSWORD;error=$null}} }}; Export-ModuleMember -Function {0}' -f $scriptCase.Function);[IO.File]::WriteAllText($successModule,$successSource)
            $entry=Join-Path $projectRoot ('scripts\'+$scriptCase.Script)
            $exitCodes=New-Object Collections.ArrayList;$exitRunner={param($code)[void]$exitCodes.Add($code)}.GetNewClosure()
            $invokeArguments=@{}+$scriptCase.Arguments;$invokeArguments.ModulePath=$successModule;$invokeArguments.ExitRunner=$exitRunner
            $saved=[Environment]::GetEnvironmentVariable('PGPASSWORD','Process');try{$env:PGPASSWORD='history-script-secret';$output=@(. $entry @invokeArguments);$exitCode=$exitCodes[0]}finally{[Environment]::SetEnvironmentVariable('PGPASSWORD',$saved,'Process')}
            $exitCode|Should Be 0;$output.Count|Should Be 1;$json=$output-join '';$summary=$json|ConvertFrom-Json;$summary.status|Should Be 'SUCCESS';$json|Should Match '\[REDACTED\]';$json|Should Not Match 'history-script-secret'
            $failureModule=Join-Path $TestDrive ($scriptCase.Function+'Failure.psm1');$failureSource=('function {0} {{ throw "failed $env:PGPASSWORD" }}; Export-ModuleMember -Function {0}' -f $scriptCase.Function);[IO.File]::WriteAllText($failureModule,$failureSource)
            $exitCodes=New-Object Collections.ArrayList;$exitRunner={param($code)[void]$exitCodes.Add($code)}.GetNewClosure()
            $invokeArguments=@{}+$scriptCase.Arguments;$invokeArguments.ModulePath=$failureModule;$invokeArguments.ExitRunner=$exitRunner
            $saved=[Environment]::GetEnvironmentVariable('PGPASSWORD','Process');try{$env:PGPASSWORD='history-script-secret';$output=@(. $entry @invokeArguments);$exitCode=$exitCodes[0]}finally{[Environment]::SetEnvironmentVariable('PGPASSWORD',$saved,'Process')}
            $exitCode|Should Not Be 0;$output.Count|Should Be 1;$json=$output-join '';$summary=$json|ConvertFrom-Json;$summary.status|Should Be 'FAILED';$json|Should Match '\[REDACTED\]';$json|Should Not Match 'history-script-secret'
            Remove-Module ([IO.Path]::GetFileNameWithoutExtension($failureModule)) -Force -ErrorAction SilentlyContinue
            Remove-Module ([IO.Path]::GetFileNameWithoutExtension($successModule)) -Force -ErrorAction SilentlyContinue
        }
    }
}
