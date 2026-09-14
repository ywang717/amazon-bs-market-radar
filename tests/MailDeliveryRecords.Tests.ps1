$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src\MailDelivery.psm1') -Force

function Write-TestJsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value,
        [int]$Depth = 12
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    [System.IO.File]::WriteAllText(
        $Path,
        ($Value | ConvertTo-Json -Depth $Depth),
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function New-DailyReportTestItems {
    $items = @()
    foreach ($rank in 1..30) {
        $items += [pscustomobject]@{
            asin = ('B0T{0:D7}' -f $rank)
            rank = $rank
            title = "Sandbox item $rank"
            url = "https://www.amazon.com/dp/B0T$('{0:D7}' -f $rank)"
            price = '$20.00'
            rating = 4.5
            reviews = 100
        }
    }
    return $items
}

function New-DailyReportTestSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Date,
        [switch]$SwapLargeMove
    )

    $pressure = New-DailyReportTestItems
    if ($SwapLargeMove) {
        $pressure[0].rank = 20
        $pressure[19].rank = 1
    }

    return [pscustomobject]@{
        market_date = $Date
        observed_at = "${Date}T01:00:00Z"
        pressure_washers = @($pressure)
        sump_pumps = @(New-DailyReportTestItems)
        pressure_washer_accessories = @(New-DailyReportTestItems)
    }
}

function New-DailyReportScriptSandbox {
    $sandboxRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    $scriptsRoot = Join-Path $sandboxRoot 'scripts'
    $srcRoot = Join-Path $sandboxRoot 'src'
    New-Item -ItemType Directory -Path $scriptsRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $srcRoot -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'config') -Destination (Join-Path $sandboxRoot 'config') -Recurse -Force

    foreach ($relativePath in @(
        'scripts\New-BestSellersDailyReport.ps1',
        'src\BestSellersCategoryRegistry.psm1',
        'src\BestSellersAnalysis.psm1',
        'src\BestSellersDailyReport.psm1',
        'src\MailDelivery.psm1'
    )) {
        $sourcePath = Join-Path $projectRoot $relativePath
        $targetPath = Join-Path $sandboxRoot $relativePath
        $targetDirectory = Split-Path -Parent $targetPath
        if (-not (Test-Path -LiteralPath $targetDirectory)) {
            New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        }
        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
    }

    $pdfStubPath = Join-Path $scriptsRoot 'New-ReportPdf.ps1'
    [System.IO.File]::WriteAllText(
        $pdfStubPath,
@'
param(
    [Parameter(Mandatory = $true)][string]$MarkdownPath,
    [Parameter(Mandatory = $true)][string]$PdfPath,
    [Parameter(Mandatory = $true)][string]$Title,
    [string]$GeneratedAtBeijing
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $MarkdownPath -PathType Leaf)) {
    throw "Markdown report not found: $MarkdownPath"
}
[System.IO.File]::WriteAllText($PdfPath, 'sandbox pdf', (New-Object System.Text.UTF8Encoding($false)))
[pscustomobject]@{
    Status = 'VERIFIED'
    PdfPath = (Resolve-Path -LiteralPath $PdfPath).Path
    PageCount = 1
    SizeBytes = [long](Get-Item -LiteralPath $PdfPath).Length
    GeneratedAtBeijing = $GeneratedAtBeijing
    RenderedPages = @()
} | ConvertTo-Json -Depth 4
'@,
        (New-Object System.Text.UTF8Encoding($false))
    )

    $archiveModulePath = Join-Path $srcRoot 'ReportArchive.psm1'
    [System.IO.File]::WriteAllText(
        $archiveModulePath,
@'
Set-StrictMode -Version Latest

function Copy-BestSellersReportToDesktop {
    param(
        [Parameter(Mandatory = $true)][string]$PdfPath,
        [Parameter(Mandatory = $true)][ValidateSet('Daily', 'Weekly')][string]$ReportKind,
        [string]$CategoryKey,
        [string]$ArchiveRoot,
        [string]$RegistryPath
    )

    $projectRoot = Split-Path -Parent $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($ArchiveRoot)) {
        $ArchiveRoot = Join-Path $projectRoot 'var\archive'
    }

    $categoryFolder = if ($ReportKind -eq 'Daily') { [string]$CategoryKey } else { 'weekly' }
    $targetDirectory = Join-Path $ArchiveRoot $categoryFolder
    New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
    $destinationPath = Join-Path $targetDirectory ([IO.Path]::GetFileName($PdfPath))
    Copy-Item -LiteralPath $PdfPath -Destination $destinationPath -Force
    return (Resolve-Path -LiteralPath $destinationPath).Path
}

Export-ModuleMember -Function Copy-BestSellersReportToDesktop
'@,
        (New-Object System.Text.UTF8Encoding($false))
    )

    return $sandboxRoot
}

function New-OperationalHealthTestSandbox {
    $sandboxRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    $scriptsRoot = Join-Path $sandboxRoot 'scripts'
    $postgresScriptsRoot = Join-Path $scriptsRoot 'postgres'
    $srcRoot = Join-Path $sandboxRoot 'src'
    New-Item -ItemType Directory -Path $postgresScriptsRoot, $srcRoot -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'scripts\Test-BestSellersDailyOperationalHealth.ps1') -Destination (Join-Path $scriptsRoot 'Test-BestSellersDailyOperationalHealth.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $projectRoot 'src\BestSellersCategoryRegistry.psm1') -Destination (Join-Path $srcRoot 'BestSellersCategoryRegistry.psm1') -Force
    Copy-Item -LiteralPath (Join-Path $projectRoot 'config') -Destination $sandboxRoot -Recurse -Force

    [System.IO.File]::WriteAllText((Join-Path $scriptsRoot 'Test-BestSellersCaptureReceipt.ps1'), "[pscustomobject]@{ valid = `$true; expected_snapshot_sha256 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' } | ConvertTo-Json", (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $postgresScriptsRoot 'Start-LocalPostgres.ps1'), 'param([string]$SettingsPath)', (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $postgresScriptsRoot 'Test-LocalPostgresBackup.ps1'), "param([string]`$BackupPath)`n[pscustomobject]@{ Status = 'VERIFIED' } | ConvertTo-Json", (New-Object System.Text.UTF8Encoding($false)))

    $installRoot = Join-Path $sandboxRoot 'postgres'
    $binRoot = Join-Path $installRoot 'bin'
    New-Item -ItemType Directory -Path $binRoot -Force | Out-Null
    $psqlSource = @'
using System;
public static class Program {
    public static int Main(string[] args) {
        Console.WriteLine("90");
        return 0;
    }
}
'@
    $psqlSourcePath = Join-Path $binRoot 'psql.cs'
    $psqlPath = Join-Path $binRoot 'psql.exe'
    [System.IO.File]::WriteAllText($psqlSourcePath, $psqlSource, (New-Object System.Text.UTF8Encoding($false)))
    $cscPath = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $cscPath -PathType Leaf)) { $cscPath = Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
    if (-not (Test-Path -LiteralPath $cscPath -PathType Leaf)) { throw 'The Windows C# compiler is required for the operational health test sandbox.' }
    & $cscPath '/nologo' '/target:exe' ("/out:$psqlPath") $psqlSourcePath | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $psqlPath -PathType Leaf)) { throw 'Could not compile the operational health test psql stub.' }

    return [pscustomobject]@{ Root = $sandboxRoot; HealthScript = (Join-Path $scriptsRoot 'Test-BestSellersDailyOperationalHealth.ps1'); InstallRoot = $installRoot }
}

Describe 'Immutable mail delivery records' {
    It 'keeps daily and weekly email evidence separate for one market date' {
        $dailyPdf = Join-Path $TestDrive 'daily.pdf'
        $weeklyPdf = Join-Path $TestDrive 'weekly.pdf'
        [System.IO.File]::WriteAllBytes($dailyPdf, [byte[]](1, 2, 3))
        [System.IO.File]::WriteAllBytes($weeklyPdf, [byte[]](4, 5, 6))
        $dailyMessage = [pscustomobject]@{
            Category = 'general'
            ReportPath = $dailyPdf
            DeliveryResult = [pscustomobject]@{ Status = 'SENT'; Recipient = 'daily@example.com'; SentAt = '2026-08-24T00:00:00Z'; ErrorMessage = $null }
        }
        $weeklyMessage = [pscustomobject]@{
            Category = 'general'
            ReportPath = $weeklyPdf
            DeliveryResult = [pscustomobject]@{ Status = 'SENT'; Recipient = 'weekly@example.com'; SentAt = '2026-08-24T00:01:00Z'; ErrorMessage = $null }
        }

        $daily = Write-MailDeliveryRunRecords -MarketDate '2026-08-24' -ReportKind Daily -WorkRoot $TestDrive -RunId 'daily' -Messages @($dailyMessage)
        $weekly = Write-MailDeliveryRunRecords -MarketDate '2026-08-24' -ReportKind Weekly -WorkRoot $TestDrive -RunId 'weekly' -Messages @($weeklyMessage)

        Test-Path $daily.ManifestPath | Should Be $true
        Test-Path $weekly.ManifestPath | Should Be $true
        (Get-Content -Raw $daily.LatestPath | ConvertFrom-Json).report_kind | Should Be 'Daily'
        (Get-Content -Raw $weekly.LatestPath | ConvertFrom-Json).report_kind | Should Be 'Weekly'
        @($daily.RecordPaths).Count | Should Be 1
        Test-Path (Join-Path $TestDrive 'reports\2026-08-24\email-delivery-summary.json') | Should Be $false
    }

    It 'records HTML and Markdown attachments from legacy one-report callers' {
        foreach ($extension in @('html', 'md')) {
            $reportPath = Join-Path $TestDrive ("daily-report.$extension")
            [System.IO.File]::WriteAllText($reportPath, 'daily report', (New-Object System.Text.UTF8Encoding($false)))
            $message = [pscustomobject]@{
                Category = 'general'
                ReportPath = $reportPath
                DeliveryResult = [pscustomobject]@{
                    Status = 'SKIPPED_BY_REQUEST'
                    Recipient = 'daily@example.com'
                    SentAt = $null
                    ErrorMessage = $null
                }
            }

            $result = Write-MailDeliveryRunRecords -MarketDate '2026-08-24' -ReportKind Daily -WorkRoot $TestDrive -RunId "legacy-$extension" -Messages @($message)

            Test-Path $result.ManifestPath | Should Be $true
            @($result.RecordPaths).Count | Should Be 1
            (Get-Content -Raw $result.RecordPaths[0] | ConvertFrom-Json).report_filename | Should Be "daily-report.$extension"
        }
    }

    It 'preserves uniform skipped statuses in the latest manifest while retaining mixed failures' {
        $reportPath = Join-Path $TestDrive 'delivery-evidence.pdf'
        [System.IO.File]::WriteAllBytes($reportPath, [byte[]](1, 2, 3))
        foreach ($status in @('SKIPPED_BY_REQUEST', 'SKIPPED_CREDENTIALS_MISSING')) {
            $messages = @(
                [pscustomobject]@{ Category = 'first'; ReportPath = $reportPath; DeliveryResult = [pscustomobject]@{ Status = $status; Recipient = 'daily@example.com'; SentAt = $null; ErrorMessage = $null } },
                [pscustomobject]@{ Category = 'second'; ReportPath = $reportPath; DeliveryResult = [pscustomobject]@{ Status = $status; Recipient = 'daily@example.com'; SentAt = $null; ErrorMessage = $null } }
            )
            $result = Write-MailDeliveryRunRecords -MarketDate '2026-08-24' -ReportKind Daily -WorkRoot $TestDrive -RunId ("uniform-$status") -Messages $messages

            (Get-Content -Raw $result.LatestPath | ConvertFrom-Json).overall_status | Should Be $status
        }

        $mixed = Write-MailDeliveryRunRecords -MarketDate '2026-08-24' -ReportKind Daily -WorkRoot $TestDrive -RunId 'mixed-statuses' -Messages @(
            [pscustomobject]@{ Category = 'first'; ReportPath = $reportPath; DeliveryResult = [pscustomobject]@{ Status = 'SENT'; Recipient = 'daily@example.com'; SentAt = '2026-08-24T00:00:00Z'; ErrorMessage = $null } },
            [pscustomobject]@{ Category = 'second'; ReportPath = $reportPath; DeliveryResult = [pscustomobject]@{ Status = 'SEND_FAILED_RETRYABLE'; Recipient = 'daily@example.com'; SentAt = $null; ErrorMessage = 'temporary failure' } }
        )

        (Get-Content -Raw $mixed.LatestPath | ConvertFrom-Json).overall_status | Should Be 'PARTIAL_FAILURE'
    }

    It 'writes three daily message records for three generated category reports' {
        $sandboxRoot = New-DailyReportScriptSandbox
        $dailyScript = Join-Path $sandboxRoot 'scripts\New-BestSellersDailyReport.ps1'
        $previousPath = Join-Path $sandboxRoot 'fixtures\previous.json'
        $currentPath = Join-Path $sandboxRoot 'fixtures\current.json'
        $outputDirectory = Join-Path $sandboxRoot 'output'

        Write-TestJsonFile -Path $previousPath -Value (New-DailyReportTestSnapshot -Date '2026-08-04')
        Write-TestJsonFile -Path $currentPath -Value (New-DailyReportTestSnapshot -Date '2026-08-05' -SwapLargeMove)

        $result = & $dailyScript -CurrentPath $currentPath -PreviousPath $previousPath -OutputDirectory $outputDirectory -SkipEmail | ConvertFrom-Json

        (@($result.PSObject.Properties.Name) -contains 'EmailDeliveryRecordPaths') | Should Be $true
        (@($result.PSObject.Properties.Name) -contains 'EmailDeliveryManifestPath') | Should Be $true
        @($result.EmailDeliveryRecordPaths).Count | Should Be 3
        (Test-Path -LiteralPath $result.EmailDeliveryManifestPath) | Should Be $true
        (Get-Content -LiteralPath $result.EmailDeliveryManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json).report_kind | Should Be 'Daily'
        Test-Path (Join-Path $sandboxRoot 'var\reports\2026-08-05\email-delivery-summary.json') | Should Be $false
    }

    It 'ignores a weekly latest pointer when auditing daily email status' {
        $sandbox = New-OperationalHealthTestSandbox
        $marketDate = '2026-08-05'
        $snapshotsRoot = Join-Path $sandbox.Root 'snapshots'
        $reportsRoot = Join-Path $sandbox.Root 'reports'
        $backupRoot = Join-Path $sandbox.Root 'backups'
        $snapshotDirectory = Join-Path $snapshotsRoot $marketDate
        $reportDirectory = Join-Path $reportsRoot $marketDate
        New-Item -ItemType Directory -Path $snapshotDirectory, $reportDirectory, $backupRoot -Force | Out-Null

        Write-TestJsonFile -Path (Join-Path $snapshotDirectory 'amazon-bestsellers.json') -Value (New-DailyReportTestSnapshot -Date $marketDate)
        [System.IO.File]::WriteAllText((Join-Path $snapshotDirectory 'best-sellers-capture-receipt.json'), '{}', (New-Object System.Text.UTF8Encoding($false)))
        [System.IO.File]::WriteAllBytes((Join-Path $reportDirectory 'daily.pdf'), [byte[]](1, 2, 3))
        [System.IO.File]::WriteAllBytes((Join-Path $backupRoot 'daily.dump'), [byte[]](4, 5, 6))
        Write-TestJsonFile -Path (Join-Path $reportDirectory 'delivery\daily\latest.json') -Value ([pscustomobject]@{ overall_status = 'SENT' })
        Write-TestJsonFile -Path (Join-Path $reportDirectory 'delivery\weekly\latest.json') -Value ([pscustomobject]@{ overall_status = 'SKIPPED_BY_REQUEST' })
        Write-TestJsonFile -Path (Join-Path $sandbox.Root 'postgres-settings.json') -Value ([pscustomobject]@{ install_root = $sandbox.InstallRoot; host = 'localhost'; port = 5432; username = 'test'; password = 'test'; database = 'test' })

        $health = & $sandbox.HealthScript -MarketDate $marketDate -SnapshotsRoot $snapshotsRoot -ReportsRoot $reportsRoot -PostgresSettingsPath (Join-Path $sandbox.Root 'postgres-settings.json') -BackupRoot $backupRoot | ConvertFrom-Json

        $health.EmailDeliveryStatus | Should Be 'SENT'
    }
}
