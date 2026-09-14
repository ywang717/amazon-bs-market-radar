# Best Sellers Price Completeness Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Strictly explain every missing Best Sellers price, safely supplement public detail-page prices, and retry a failed collection in fresh browser sessions before any snapshot reaches downstream processing.

**Architecture:** Keep DOM extraction and price classification as pure, testable Python functions in the existing collector. Add a collection-attempt boundary that collects all active charts, verifies missing prices through isolated detail tabs, emits sanitized diagnostics, and publishes only a successful final attempt atomically; the existing PowerShell orchestrator remains the downstream gate.

**Tech Stack:** Python 3, Playwright sync API, JSON artifacts, PowerShell 5.1/Pester, `unittest`.

## Global Constraints

- Each active category must contain unique global ranks 1–30 and non-empty rank, ASIN, and title.
- A null price is accepted only after detail-page evidence classifies it as `PRICE_NOT_PUBLIC`.
- Use at most three complete attempts: the initial collection plus two fresh-browser retries.
- Each retry recollects every active category; never merge attempts.
- Do not bypass authentication, CAPTCHA, or access controls; do not use persistent profiles or credentials.
- Failed attempts must not overwrite an existing canonical snapshot or start receipt, database, report, backup, or email work.
- Diagnostics must not retain full page bodies, cookies, credentials, or browser configuration.
- Normal reports continue to render an accepted null price as `-` without a reason annotation.

---

### Task 1: Detail-page price evidence classifier

**Files:**
- Modify: `scripts/python/collect_best_sellers.py`
- Test: `tests/python/test_best_sellers_collector.py`

**Interfaces:**
- Produces: `classify_detail_price(page: dict[str, Any]) -> dict[str, Any]` returning `reason_code`, `price`, and `page_status`.
- Produces: `_extract_detail_page(page: Any) -> dict[str, Any]` returning sanitized structured signals only.

- [ ] **Step 1: Write failing table-driven classifier tests**

Add tests with literal expectations for: public price → `DETAIL_PRICE_FOUND`; unavailable/out-of-stock/no-featured-offer/see-all-buying-options/sign-in-to-see-price → `PRICE_NOT_PUBLIC`; CAPTCHA/login/access denied → `VERIFICATION_BLOCKED`; readable page without supported evidence → `PRICE_MISSING_UNEXPLAINED`. Assert a missing selector alone never yields `PRICE_NOT_PUBLIC`.

- [ ] **Step 2: Run tests and verify RED**

Run: `.\.venv\Scripts\python.exe -m unittest tests.python.test_best_sellers_collector.DetailPriceClassificationTests -v`

Expected: FAIL because `classify_detail_price` and `_extract_detail_page` do not exist.

- [ ] **Step 3: Implement minimal extraction and classification**

Extract detail prices from stable Amazon price locations such as `.a-price .a-offscreen`, `#corePrice_feature_div .a-offscreen`, and `#priceblock_ourprice`; extract only URL, title, heading, supported availability/buying-option signals, and blocked markers. Reuse `BLOCKED_MARKERS`; normalize public price text with `_clean_text`; return exactly one of the four reason codes.

- [ ] **Step 4: Run classifier and existing extraction tests**

Run: `.\.venv\Scripts\python.exe -m unittest tests.python.test_best_sellers_collector.DetailPriceClassificationTests tests.python.test_best_sellers_collector.BrowserExtractionTests -v`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add scripts/python/collect_best_sellers.py tests/python/test_best_sellers_collector.py
git commit -m "feat: classify missing price evidence"
```

### Task 2: Verify and supplement missing chart prices

**Files:**
- Modify: `scripts/python/collect_best_sellers.py`
- Test: `tests/python/test_best_sellers_collector.py`

**Interfaces:**
- Consumes: `classify_detail_price(page)` and `_extract_detail_page(page)` from Task 1.
- Produces: `verify_chart_prices(context: Any, chart_results: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[str]]`.

- [ ] **Step 1: Write failing behavior tests**

Use specific fake contexts/pages mirroring Playwright boundaries. Test that already-priced items cause no detail visit; `DETAIL_PRICE_FOUND` updates only that observation's `price`; `PRICE_NOT_PUBLIC` leaves `price` null and succeeds; blocked and unexplained results return failure reasons. Assert evidence records contain category, ASIN, chart URL, detail URL, reason code, supplemented boolean, and source, but no body text.

- [ ] **Step 2: Run tests and verify RED**

Run: `.\.venv\Scripts\python.exe -m unittest tests.python.test_best_sellers_collector.PriceVerificationTests -v`

Expected: FAIL because `verify_chart_prices` does not exist.

- [ ] **Step 3: Implement minimal detail verification**

For every null-price observation, open its canonical item URL in a new tab, extract/classify, close the tab in `finally`, supplement only `DETAIL_PRICE_FOUND`, accept only `PRICE_NOT_PUBLIC`, and collect a deterministic failure reason for blocked/unexplained results. Keep evidence outside the snapshot item schema.

- [ ] **Step 4: Run focused and full Python tests**

Run: `.\.venv\Scripts\python.exe -m unittest tests.python.test_best_sellers_collector.PriceVerificationTests -v`

Run: `.\.venv\Scripts\python.exe -m unittest discover -s tests/python -v`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add scripts/python/collect_best_sellers.py tests/python/test_best_sellers_collector.py
git commit -m "feat: verify missing prices on detail pages"
```

### Task 3: Strict attempt validation and fresh-session retries

**Files:**
- Modify: `scripts/python/collect_best_sellers.py`
- Test: `tests/python/test_best_sellers_collector.py`

**Interfaces:**
- Consumes: `verify_chart_prices(context, chart_results)` from Task 2.
- Produces: `validate_collection_attempt(config, chart_results, price_failures) -> list[str]`.
- Produces: `collect_with_recovery(config, headless=False, playwright_factory=None, max_attempts=3) -> tuple[list[dict[str, Any]], str, dict[str, Any]]`.

- [ ] **Step 1: Write failing strict-validation and retry tests**

Test missing title, non-contiguous rank, duplicate ASIN, non-complete category, unexplained null price, and an accepted `PRICE_NOT_PUBLIC` null. Test attempt 1 failure followed by attempt 2 success; three failures stop at exactly three; each attempt creates and closes a distinct browser/context and recollects all three categories; attempt results are never merged.

- [ ] **Step 2: Run tests and verify RED**

Run: `.\.venv\Scripts\python.exe -m unittest tests.python.test_best_sellers_collector.CollectionRecoveryTests -v`

Expected: FAIL because validation/recovery interfaces do not exist.

- [ ] **Step 3: Implement a one-attempt browser boundary**

Refactor current `collect_with_browser` internals into `_collect_attempt(browser, config)` without changing chart pagination behavior. After all charts are collected, call price verification, then strict validation. Return one complete attempt record containing chart results, sanitized price evidence, and failure reasons.

- [ ] **Step 4: Implement bounded fresh-session recovery**

`collect_with_recovery` launches a new ephemeral browser and context per attempt, closes both before retry, records sanitized attempt summaries, returns immediately on strict success, and after attempt 3 returns a failed diagnostic with no publishable chart result. Preserve `collect_with_browser` as a compatibility wrapper if existing tests or callers require it.

- [ ] **Step 5: Run recovery and all Python tests**

Run: `.\.venv\Scripts\python.exe -m unittest tests.python.test_best_sellers_collector.CollectionRecoveryTests -v`

Run: `.\.venv\Scripts\python.exe -m unittest discover -s tests/python -v`

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add scripts/python/collect_best_sellers.py tests/python/test_best_sellers_collector.py
git commit -m "feat: retry incomplete collections in fresh sessions"
```

### Task 4: Atomic diagnostics and publish gate

**Files:**
- Modify: `scripts/python/collect_best_sellers.py`
- Test: `tests/python/test_best_sellers_collector.py`

**Interfaces:**
- Consumes: recovery diagnostic from `collect_with_recovery`.
- Produces: `price-completeness-diagnostic.json` in the market-date directory.
- Extends status/control results with `CompletenessStatus`, `AttemptCount`, `PriceVerificationCount`, `DiagnosticPath`, and safe `FailureReasons`.

- [ ] **Step 1: Write failing artifact tests**

Test successful diagnostics, supplemented-price snapshots, accepted null prices, and failed diagnostics. Pre-create a canonical snapshot and assert three failed attempts leave its bytes unchanged. Assert failure still updates status/diagnostic artifacts, returns nonzero, and never serializes body text, cookies, credentials, or browser settings.

- [ ] **Step 2: Run tests and verify RED**

Run: `.\.venv\Scripts\python.exe -m unittest tests.python.test_best_sellers_collector.CompletenessArtifactTests -v`

Expected: FAIL because the diagnostic artifact and publish gate are absent.

- [ ] **Step 3: Implement atomic artifact rules**

Always atomically write status and diagnostic files. Write/replace `amazon-bestsellers.json` only when `CompletenessStatus == "COMPLETE"`; otherwise return a dedicated nonzero completeness exit code and `SnapshotPath: null`. Ensure `main()` invokes recovery for live collection and preserves fixture collection as deterministic offline input with the same validation gate but no network retry.

- [ ] **Step 4: Run artifact and all Python tests**

Run: `.\.venv\Scripts\python.exe -m unittest tests.python.test_best_sellers_collector.CompletenessArtifactTests -v`

Run: `.\.venv\Scripts\python.exe -m unittest discover -s tests/python -v`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add scripts/python/collect_best_sellers.py tests/python/test_best_sellers_collector.py
git commit -m "feat: gate snapshots on price completeness"
```

### Task 5: Downstream orchestration contract

**Files:**
- Modify: `src/LocalPackageOrchestrator.psm1`
- Test: `tests/LocalPackageLauncher.Tests.ps1`

**Interfaces:**
- Consumes collector fields from Task 4.
- Ensures `DailyAuto` calls `Invoke-LocalPackageDailyGates` only when `CompletenessStatus == "COMPLETE"` and `SnapshotPath` is canonical.

- [ ] **Step 1: Write failing Pester tests**

Add a fake Collect result with observations but `CompletenessStatus = FAILED` and assert only `Collect` runs; receipt, import, report, email, and backup steps never run. Add a complete result and assert the existing gate sequence remains unchanged. Assert the failure summary exposes only diagnostic path and safe reason codes.

- [ ] **Step 2: Run tests and verify RED**

Run: `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Invoke-Pester -Script tests/LocalPackageLauncher.Tests.ps1 -PassThru"`

Expected: new incomplete-collection test FAILS because the orchestrator currently gates only on observation count/exit code.

- [ ] **Step 3: Implement the explicit completeness gate**

Immediately after Collect, require `CompletenessStatus == 'COMPLETE'`; otherwise mark Collect failed and throw a sanitized message that includes `DiagnosticPath` and safe failure reason codes. Retain all existing canonical path, market date, receipt, and downstream validations.

- [ ] **Step 4: Run launcher and full Pester tests**

Run: `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Invoke-Pester -Script tests/LocalPackageLauncher.Tests.ps1 -PassThru"`

Run: `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/Test.ps1`

Expected: PASS with zero failures.

- [ ] **Step 5: Commit**

```powershell
git add src/LocalPackageOrchestrator.psm1 tests/LocalPackageLauncher.Tests.ps1
git commit -m "feat: stop daily pipeline on incomplete pricing"
```

### Task 6: Real-page acceptance and operational documentation

**Files:**
- Modify: `docs/phase-7/MAINTENANCE-RUNBOOK.md`
- Verify: `var/amazon-bestsellers/<market-date>/price-completeness-diagnostic.json`

**Interfaces:**
- Documents diagnostic reason codes, retry limit, failure response, and safe manual investigation.

- [ ] **Step 1: Update the runbook**

Document the four price reason codes, three-attempt limit, artifact paths, downstream stop behavior, and the rule that operators must update tested selectors in source control rather than editing source during a scheduled run.

- [ ] **Step 2: Run a real read-only collection without downstream side effects**

Run: `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/Collect-BestSellers.ps1 -MarketDate <current-pacific-date>`

Expected: control JSON reports `CompletenessStatus=COMPLETE`, three categories × 30 observations, and every null price has `PRICE_NOT_PUBLIC` evidence.

- [ ] **Step 3: Inspect sanitized diagnostics and snapshot counts**

Parse both JSON files with PowerShell. Assert 90 observations, ranks 1–30 per category, unique ASINs within each category, no unexplained price failures, and no sensitive diagnostic keys or values.

- [ ] **Step 4: Run final verification**

Run: `.\.venv\Scripts\python.exe -m unittest discover -s tests/python -v`

Run: `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/Test.ps1`

Run: `git diff --check`

Expected: all Python tests pass, all Pester tests pass with zero failures, and diff check exits 0.

- [ ] **Step 5: Commit**

```powershell
git add docs/phase-7/MAINTENANCE-RUNBOOK.md
git commit -m "docs: document price completeness recovery"
```
