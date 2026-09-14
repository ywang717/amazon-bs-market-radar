# Desktop Report Archive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Copy every verified daily PDF into its chart-specific folder under `桌面\亚马逊bs榜单每日监控`, and copy all verified weekly PDFs into the shared `周报` folder.

**Architecture:** Add a focused PowerShell module that resolves the Windows desktop path, maps report type/category to an archive folder, and copies one verified PDF with overwrite semantics. The existing daily and weekly report entry scripts call this module immediately after PDF verification and expose the archived path in their JSON results while retaining `var/reports` as the canonical report location.

**Tech Stack:** Windows PowerShell 5.1, Pester-compatible PowerShell tests, .NET `Environment.GetFolderPath`, existing report scripts.

## Global Constraints

- Desktop archive root name is exactly `亚马逊bs榜单每日监控`.
- Daily subfolders are exactly `高压清洗机`, `污水泵`, and `高压清洗机配件`.
- All three weekly PDFs are stored directly in the single `周报` subfolder.
- Archive only PDF files after the existing renderer reports `VERIFIED`.
- Preserve the original PDF filename and overwrite an existing same-name archive file.
- Keep project-local reports, email delivery, report content, scheduling, and health-audit paths unchanged.
- Any archive failure stops the report task before its corresponding email is sent.

---

### Task 1: Desktop archive module

**Files:**
- Create: `src/ReportArchive.psm1`
- Modify: `tests/AmazonIntelligence.Tests.ps1`

**Interfaces:**
- Produces: `Copy-BestSellersReportToDesktop -PdfPath <string> -ReportKind <Daily|Weekly> [-CategoryKey <string>] [-ArchiveRoot <string>]` returning the archived PDF absolute path.
- Daily category keys: `pressure_washers`, `sump_pumps`, `pressure_washer_accessories`.
- Weekly calls do not require a category key because every weekly PDF routes to `周报`.

- [ ] **Step 1: Write failing routing and copy tests**

Add a new test block that imports `src/ReportArchive.psm1`, creates a source PDF in `$TestDrive`, and asserts:

```powershell
Describe 'Desktop report archive' {
    BeforeEach {
        $archiveRoot = Join-Path $TestDrive '亚马逊bs榜单每日监控'
        $source = Join-Path $TestDrive 'Amazon_US_Best_Sellers_Test_2026-08-06.pdf'
        [IO.File]::WriteAllText($source, 'first')
    }

    It 'routes each daily chart to its Chinese subfolder' {
        $expectedFolders = @{
            pressure_washers = '高压清洗机'
            sump_pumps = '污水泵'
            pressure_washer_accessories = '高压清洗机配件'
        }
        foreach ($key in $expectedFolders.Keys) {
            $result = Copy-BestSellersReportToDesktop -PdfPath $source -ReportKind Daily -CategoryKey $key -ArchiveRoot $archiveRoot
            Split-Path -Leaf (Split-Path -Parent $result) | Should Be $expectedFolders[$key]
            Test-Path -LiteralPath $result -PathType Leaf | Should Be $true
        }
    }

    It 'routes every weekly report to the shared weekly folder' {
        $result = Copy-BestSellersReportToDesktop -PdfPath $source -ReportKind Weekly -ArchiveRoot $archiveRoot
        Split-Path -Leaf (Split-Path -Parent $result) | Should Be '周报'
    }

    It 'overwrites an existing same-name archive file' {
        $result = Copy-BestSellersReportToDesktop -PdfPath $source -ReportKind Weekly -ArchiveRoot $archiveRoot
        [IO.File]::WriteAllText($source, 'second')
        Copy-BestSellersReportToDesktop -PdfPath $source -ReportKind Weekly -ArchiveRoot $archiveRoot | Out-Null
        [IO.File]::ReadAllText($result) | Should Be 'second'
    }

    It 'rejects missing sources and unknown daily category keys' {
        { Copy-BestSellersReportToDesktop -PdfPath (Join-Path $TestDrive 'missing.pdf') -ReportKind Weekly -ArchiveRoot $archiveRoot } | Should Throw
        { Copy-BestSellersReportToDesktop -PdfPath $source -ReportKind Daily -CategoryKey 'unknown' -ArchiveRoot $archiveRoot } | Should Throw
    }
}
```

- [ ] **Step 2: Run the archive tests and verify RED**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1
```

Expected: FAIL because `src/ReportArchive.psm1` and `Copy-BestSellersReportToDesktop` do not exist.

- [ ] **Step 3: Implement the minimal archive module**

Create `src/ReportArchive.psm1` with:

```powershell
Set-StrictMode -Version Latest

function Copy-BestSellersReportToDesktop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PdfPath,
        [Parameter(Mandatory = $true)][ValidateSet('Daily', 'Weekly')][string]$ReportKind,
        [string]$CategoryKey,
        [string]$ArchiveRoot
    )

    if (-not (Test-Path -LiteralPath $PdfPath -PathType Leaf)) {
        throw "Report PDF not found: $PdfPath"
    }
    if ([IO.Path]::GetExtension($PdfPath) -ine '.pdf') {
        throw "Only PDF reports can be archived: $PdfPath"
    }
    if ([string]::IsNullOrWhiteSpace($ArchiveRoot)) {
        $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
        if ([string]::IsNullOrWhiteSpace($desktop)) { throw 'Windows desktop path could not be resolved.' }
        $ArchiveRoot = Join-Path $desktop '亚马逊bs榜单每日监控'
    }

    $folder = if ($ReportKind -eq 'Weekly') {
        '周报'
    } else {
        $dailyFolders = @{
            pressure_washers = '高压清洗机'
            sump_pumps = '污水泵'
            pressure_washer_accessories = '高压清洗机配件'
        }
        if (-not $dailyFolders.ContainsKey($CategoryKey)) { throw "Unknown daily category key: $CategoryKey" }
        $dailyFolders[$CategoryKey]
    }

    $targetDirectory = Join-Path $ArchiveRoot $folder
    New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
    $targetPath = Join-Path $targetDirectory ([IO.Path]::GetFileName($PdfPath))
    Copy-Item -LiteralPath $PdfPath -Destination $targetPath -Force
    (Resolve-Path -LiteralPath $targetPath).Path
}

Export-ModuleMember -Function Copy-BestSellersReportToDesktop
```

- [ ] **Step 4: Run tests and verify GREEN**

Run the complete test command from Step 2.

Expected: all archive tests and all existing tests PASS.

- [ ] **Step 5: Commit**

```powershell
git add src/ReportArchive.psm1 tests/AmazonIntelligence.Tests.ps1
git commit -m "feat: add desktop report archive module"
```

If the workspace is still not a Git repository, skip only the commit command and record that fact in the handoff.

---

### Task 2: Daily report archive integration

**Files:**
- Modify: `scripts/New-BestSellersDailyReport.ps1`
- Modify: `tests/AmazonIntelligence.Tests.ps1`

**Interfaces:**
- Consumes: `Copy-BestSellersReportToDesktop` from Task 1.
- Produces: each object in the existing `Reports` array gains `ArchivedPdfPath <string>`.

- [ ] **Step 1: Write a failing daily integration test**

Extend the existing “delivers the Best Sellers daily report” static test:

```powershell
$script | Should Match 'ReportArchive\.psm1'
$script | Should Match 'Copy-BestSellersReportToDesktop.*-ReportKind Daily.*-CategoryKey \$categoryKey'
$script | Should Match 'ArchivedPdfPath'
```

- [ ] **Step 2: Run the test suite and verify RED**

Run `.\scripts\Test.ps1`.

Expected: FAIL because the daily entry script does not import or call the archive module.

- [ ] **Step 3: Integrate archiving after PDF verification**

In `scripts/New-BestSellersDailyReport.ps1`:

```powershell
Import-Module (Join-Path $projectRoot 'src\ReportArchive.psm1') -Force
```

Immediately after the `VERIFIED` check and before email delivery:

```powershell
$archivedPdfPath = Copy-BestSellersReportToDesktop -PdfPath $pdf.PdfPath -ReportKind Daily -CategoryKey $categoryKey
```

Add the path to the result:

```powershell
$results += [pscustomobject]@{
    Category = $categoryKey
    Report = $report
    Pdf = $pdf
    ArchivedPdfPath = $archivedPdfPath
    EmailDelivery = $delivery
}
```

- [ ] **Step 4: Run tests and verify GREEN**

Run `.\scripts\Test.ps1`.

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```powershell
git add scripts/New-BestSellersDailyReport.ps1 tests/AmazonIntelligence.Tests.ps1
git commit -m "feat: archive daily chart reports to desktop"
```

Skip only the commit if no Git repository exists.

---

### Task 3: Weekly report archive integration

**Files:**
- Modify: `scripts/New-BestSellersWeeklyReport.ps1`
- Modify: `tests/AmazonIntelligence.Tests.ps1`

**Interfaces:**
- Consumes: `Copy-BestSellersReportToDesktop` from Task 1.
- Produces: each object in the weekly `Reports` array gains `ArchivedPdfPath <string>`.

- [ ] **Step 1: Write a failing weekly integration test**

Extend the existing weekly PDF static test:

```powershell
$script | Should Match 'ReportArchive\.psm1'
$script | Should Match 'Copy-BestSellersReportToDesktop.*-ReportKind Weekly'
$script | Should Match 'ArchivedPdfPath'
```

- [ ] **Step 2: Run the test suite and verify RED**

Run `.\scripts\Test.ps1`.

Expected: FAIL because the weekly entry script does not import or call the archive module.

- [ ] **Step 3: Integrate archiving after each weekly PDF verification**

Import `src\ReportArchive.psm1` near the other module imports. Immediately after each split PDF passes the `VERIFIED` check:

```powershell
$archivedPdfPath = Copy-BestSellersReportToDesktop -PdfPath $pdf.PdfPath -ReportKind Weekly
```

Add `ArchivedPdfPath = $archivedPdfPath` to the corresponding object in `$splitResults`. Archiving remains before the email loop so any failure stops sending.

- [ ] **Step 4: Run tests and verify GREEN**

Run `.\scripts\Test.ps1`.

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```powershell
git add scripts/New-BestSellersWeeklyReport.ps1 tests/AmazonIntelligence.Tests.ps1
git commit -m "feat: archive weekly reports to desktop"
```

Skip only the commit if no Git repository exists.

---

### Task 4: End-to-end dry-run verification

**Files:**
- Verify: `src/ReportArchive.psm1`
- Verify: `scripts/New-BestSellersDailyReport.ps1`
- Verify: `scripts/New-BestSellersWeeklyReport.ps1`

**Interfaces:**
- Consumes the latest verified snapshot and existing report-generation environment.
- Produces real desktop archive folders and copied PDFs without sending test emails.

- [ ] **Step 1: Run the full automated test suite**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1
```

Expected: exit code 0 with all tests passing.

- [ ] **Step 2: Run a daily report dry run**

Use the latest verified snapshot and `-SkipEmail`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\New-BestSellersDailyReport.ps1 -CurrentPath .\var\amazon-bestsellers\2026-08-06\amazon-bestsellers.json -PreviousPath .\var\amazon-bestsellers\2026-08-05\amazon-bestsellers.json -SkipEmail
```

Expected: three reports with non-empty `ArchivedPdfPath` values.

- [ ] **Step 3: Verify the desktop directory tree and PDF files**

```powershell
$root = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)) '亚马逊bs榜单每日监控'
Get-ChildItem -LiteralPath $root -Recurse -File
```

Expected: one newly generated daily PDF in each daily subfolder. The `周报` folder is created on the first weekly report run.

- [ ] **Step 4: Run weekly report dry run when sufficient snapshots are available**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\New-BestSellersWeeklyReport.ps1 -ReportDate 2026-08-06 -SkipEmail
```

Expected: three weekly reports whose `ArchivedPdfPath` values all have parent folder `周报`.

- [ ] **Step 5: Confirm project-local originals remain present**

Verify the daily PDFs still exist under `var\reports\2026-08-06` and weekly PDFs under `var\reports\weekly\2026-08-06`.

- [ ] **Step 6: Commit final verification updates if any**

No code change is expected. If verification requires a focused correction, follow a new RED-GREEN cycle before committing it. Skip commit commands if the workspace is not a Git repository.
