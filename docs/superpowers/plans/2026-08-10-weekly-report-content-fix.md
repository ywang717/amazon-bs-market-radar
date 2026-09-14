# Weekly Report Content Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make each category-specific weekly PDF display its verified rank swings, Top 30 entries/exits, and price/rating/review association results instead of a fixed no-change statement.

**Architecture:** Add a small pure PowerShell rendering module that accepts the in-memory weekly-analysis and rank-influence objects, filters both by category, and produces matching Markdown and HTML fragments. The weekly orchestration script will load both artifacts explicitly as UTF-8, fail closed when required analysis is absent, and inject the shared fragments into each category report before PDF generation and delivery.

**Tech Stack:** Windows PowerShell 5.1, Pester 3.4, existing Markdown-to-PDF renderer, existing report archive and SMTP modules.

## Global Constraints

- Preserve one category per PDF, one PDF per email, and the existing three category names and file tokens.
- Rank swings include absolute changes of at least 10; absolute changes of at least 20 are marked high priority.
- New entries and exits are limited to verified Top 30 transitions from the weekly-analysis artifact.
- Association results must be labelled as statistical association, never causation.
- Limited coverage remains an initial baseline and must not be described as a trend or causal conclusion.
- Weekly-analysis and rank-influence JSON must be read with `-Encoding UTF8` under Windows PowerShell 5.1.
- Missing artifacts or a missing requested category are fatal; the report must not be emailed.
- Markdown and HTML must be generated from the same category-filtered object.
- The workspace has no Git metadata, so verification checkpoints replace commit steps.

---

## File Map

- Create `src/BestSellersWeeklyReportContent.psm1`: category filtering, validation, escaping, label translation, and Markdown/HTML fragment generation.
- Modify `scripts/New-BestSellersWeeklyReport.ps1`: load artifacts, invoke the renderer, and replace hard-coded change/Phase 5 copy.
- Modify `tests/AmazonIntelligence.Tests.ps1`: focused behavior tests for real data, category isolation, association disclosure, and missing-category failure.

### Task 1: Category-specific weekly content renderer

**Files:**
- Create: `src/BestSellersWeeklyReportContent.psm1`
- Test: `tests/AmazonIntelligence.Tests.ps1`

**Interfaces:**
- Consumes: `New-BestSellersWeeklyCategorySections -CategoryKey <string> -WeeklyAnalysis <psobject> -RankInfluence <psobject> -LimitedCoverage <bool>`.
- Produces: a PSCustomObject with `Markdown`, `Html`, `LargeSwingCount`, `NewEntryCount`, `ExitCount`, and `AssociationCount`.

- [ ] **Step 1: Write the failing renderer tests**

Add a Pester `Describe 'Best Sellers weekly report content'` fixture with one distinct ASIN per category, one `HIGH` swing, one entry, one exit, and three cross-sectional associations (`PRICE_USD`, `RATING_STARS`, `LOG10_REVIEW_COUNT_PLUS_1`). Assert that the pressure-washer result contains its own ASIN, does not contain the sump-pump ASIN, contains the Chinese headings for rank swings/new entries/exits, contains price/rating/review labels, contains `Spearman rho`, and contains the non-causal disclosure. Add a second assertion that an unknown category throws.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```powershell
Invoke-Pester -Script .\tests\AmazonIntelligence.Tests.ps1 -TestName 'renders verified changes and associations for only the requested category','rejects a category absent from either analysis artifact'
```

Expected: FAIL because `BestSellersWeeklyReportContent.psm1` and `New-BestSellersWeeklyCategorySections` do not exist.

- [ ] **Step 3: Implement the minimal pure renderer**

Create the module with:

```powershell
function New-BestSellersWeeklyCategorySections {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$CategoryKey,
        [Parameter(Mandatory=$true)]$WeeklyAnalysis,
        [Parameter(Mandatory=$true)]$RankInfluence,
        [bool]$LimitedCoverage = $false
    )
    $weeklyCategory = @($WeeklyAnalysis.categories | Where-Object { $_.category -eq $CategoryKey })
    $influenceCategory = @($RankInfluence.categories | Where-Object { $_.category -eq $CategoryKey })
    if ($weeklyCategory.Count -ne 1 -or $influenceCategory.Count -ne 1) {
        throw "Analysis artifacts do not contain exactly one category: $CategoryKey"
    }
    $swings = @($WeeklyAnalysis.large_swings | Where-Object { $_.category -eq $CategoryKey -and [int]$_.absolute_change -ge 10 })
    $entries = @($WeeklyAnalysis.new_entries | Where-Object { $_.category -eq $CategoryKey })
    $exits = @($WeeklyAnalysis.exits | Where-Object { $_.category -eq $CategoryKey })
    $associations = @($influenceCategory[0].cross_sectional_associations) + @($influenceCategory[0].longitudinal_associations)
    # Build all Markdown and HTML tables from these four arrays, escaping table pipes and HTML special characters.
    # Emit an empty-state sentence only for the individual array that is empty.
    # Return counts with the two rendered fragments.
}
Export-ModuleMember -Function New-BestSellersWeeklyCategorySections
```

The change table columns are priority/date/ASIN/product/previous rank/current rank/change. Entry and exit tables contain date/ASIN/product/rank. Association columns are metric/sample/status/Spearman rho/direction/strength. Map the five metric codes and the direction/strength/status values to Chinese display labels while retaining `Spearman rho` as the statistic name. Mark `absolute_change -ge 20` as `高优先级`; all other qualifying swings are `关注`. Always append `仅表示统计关联，不代表价格、星级或评论数导致排名变化。`; when `LimitedCoverage` is true also prepend `首次有限周度分析：当前结果仅作为初始基线，不构成趋势或因果结论。`.

- [ ] **Step 4: Run the focused renderer tests and verify GREEN**

Run the same focused `Invoke-Pester` command. Expected: both tests PASS.

### Task 2: Wire verified artifacts into the split weekly report

**Files:**
- Modify: `scripts/New-BestSellersWeeklyReport.ps1`
- Test: `tests/AmazonIntelligence.Tests.ps1`

**Interfaces:**
- Consumes: `New-BestSellersWeeklyCategorySections` from Task 1; `$weeklyRun.ArtifactPath`; the rank-influence path returned in `$phase5Artifacts`.
- Produces: each existing `Reports[]` item with category-correct Markdown, HTML, verified PDF, archive path, subject, and unchanged email behavior.

- [ ] **Step 1: Write the failing orchestration contract test**

Extend the existing weekly PDF test to assert that the script imports `BestSellersWeeklyReportContent.psm1`, reads `$weeklyRun.ArtifactPath` with `Get-Content -Raw -Encoding UTF8 | ConvertFrom-Json`, selects the rank-influence artifact path, invokes `New-BestSellersWeeklyCategorySections`, appends both `.Markdown` and `.Html`, and no longer injects `$t.no_changes` unconditionally.

- [ ] **Step 2: Run the orchestration test and verify RED**

Run:

```powershell
Invoke-Pester -Script .\tests\AmazonIntelligence.Tests.ps1 -TestName 'gates the weekly PDF Phase 5 artifacts through analysis readiness'
```

Expected: FAIL on the new content-module and artifact-loading assertions.

- [ ] **Step 3: Implement artifact loading and shared fragment insertion**

After Phase 5 generation, resolve exactly one path whose filename is `best-sellers-rank-influence.json`; throw if the weekly-analysis artifact, the rank-influence artifact, or either file is missing. Load both using:

```powershell
$weeklyAnalysis = Get-Content -LiteralPath $weeklyRun.ArtifactPath -Raw -Encoding UTF8 | ConvertFrom-Json
$rankInfluence = Get-Content -LiteralPath $rankInfluencePath -Raw -Encoding UTF8 | ConvertFrom-Json
Import-Module (Join-Path $projectRoot 'src\BestSellersWeeklyReportContent.psm1') -Force
```

Inside the category loop, create `$sections = New-BestSellersWeeklyCategorySections ... -LimitedCoverage ($readiness.analysis_mode -eq 'LIMITED_WEEKLY')`. Append `$sections.Markdown` after the coverage table. Build the HTML shell from the same `$sections.Html`. Remove the fixed `no_changes` copy and replace the artifact-count-only Phase 5 paragraph with the actual association table contained in the fragment. Keep report naming, verified PDF generation, desktop archive, and per-category email delivery unchanged.

- [ ] **Step 4: Run the orchestration test and verify GREEN**

Run the same focused Pester command. Expected: PASS.

### Task 3: Regression verification and regenerated delivery

**Files:**
- Verify: `tests/*.ps1`
- Generate: `var/reports/weekly/2026-08-10/*.md`, `*.html`, `*.pdf`
- Archive: `C:\Users\ASUS\Desktop\亚马逊bs榜单每日监控\周报\*.pdf`

**Interfaces:**
- Consumes: the completed renderer and orchestration changes.
- Produces: three visually verified, separately archived and separately emailed weekly PDFs.

- [ ] **Step 1: Run all project tests**

Run:

```powershell
.\scripts\Test.ps1
```

Expected: zero failed Pester tests.

- [ ] **Step 2: Generate without email**

Run:

```powershell
.\scripts\New-BestSellersWeeklyReport.ps1 -ReportDate '2026-08-10' -SkipEmail
```

Expected: three reports with `Pdf.Status = VERIFIED`, distinct category names, and desktop archive paths.

- [ ] **Step 3: Verify content isolation and conclusions**

Inspect the three generated Markdown files. For each file, confirm its large-swing/entry/exit ASINs belong only to its category; confirm the fixed no-change sentence is absent when rows exist; confirm price, rating, review count, `Spearman rho`, and the non-causal disclosure are present.

- [ ] **Step 4: Render and visually inspect every PDF page**

Copy the PDFs to ASCII-only temporary filenames, render every page with the bundled Poppler `pdftoppm.exe`, and inspect every PNG. Reject delivery for clipped rows, broken Chinese glyphs, overlapping text, blank pages, or missing sections.

- [ ] **Step 5: Send three separate emails**

Using `src/MailDelivery.psm1`, send one email per category to `746254487@qq.com`, with only that category's verified PDF attached and the existing Beijing timestamped subject. Require all three delivery statuses to be `SENT`; otherwise report partial failure and do not claim completion.

- [ ] **Step 6: Final verification checkpoint**

Re-run the focused weekly content tests and record the three final PDF paths, archive paths, page counts, and email statuses in the handoff.

## Self-Review

- Spec coverage: rank swings, priority threshold, entries, exits, category isolation, association metrics, non-causal disclosure, limited baseline warning, fail-closed artifacts, shared Markdown/HTML data, full tests, PDF visual QA, archive, and split email delivery are each mapped to a task.
- Placeholder scan: no deferred implementation or unspecified error handling remains; the renderer step defines inputs, outputs, columns, thresholds, labels, and empty states.
- Type consistency: Task 1 produces `Markdown`/`Html` and count properties; Task 2 consumes the same names. Both artifacts expose `categories[]` with `category`; weekly events expose `large_swings`, `new_entries`, and `exits`; influence categories expose cross-sectional and longitudinal association arrays.
