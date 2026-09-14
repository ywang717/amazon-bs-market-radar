# Operational Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (\`- [ ]\`) syntax for tracking.

**Goal:** Prevent duplicate automation runs, retain non-overwriting per-email delivery evidence, and add a safe dashboard-publish recovery task.

**Architecture:** Delivery evidence becomes immutable run artifacts under \`var/reports/<market-date>/delivery/<daily|weekly>/<run-id>/\`, with one report-kind-specific \`latest.json\` pointer. Dashboard publishing writes an atomic local result state and uses a cross-process lock; the 09:15 recovery task invokes the same publisher only when the 09:00 primary did not record success.

**Tech Stack:** Windows PowerShell 5.1, Pester 3.4, Windows Task Scheduler, existing PowerShell modules.

**Spec:** \`docs/superpowers/specs/2026-08-24-operational-reliability-design.md\`

## Global Constraints

- Do not send real email while testing; use injected mail transports or \`-SkipEmail\`.
- Never log SMTP authorization codes, database passwords, dashboard sync secrets, cookies, or full private configuration.
- Preserve legacy \`email-delivery-summary.json\` as historical read-only evidence; new runs must not write it.
- \`SENT\` means local SMTP send completed, not confirmed inbox delivery.
- Windows is the only automatic runner: daily 08:00, weekly Monday 06:00, dashboard primary 09:00, dashboard recovery 09:15.
- The three Codex automations remain paused.
- Do not modify Amazon collection rules, D1/R2 contracts, public website responses, report content, snapshots, reports, database data, or backups.

---

## File Structure

- \`src/MailDelivery.psm1\`: immutable per-message records, run manifests, and atomic latest pointers.
- \`scripts/New-BestSellersDailyReport.ps1\`, \`scripts/New-BestSellersWeeklyReport.ps1\`, \`scripts/Invoke-DailyPipeline.ps1\`, \`scripts/Invoke-CredentialFreeDailyPipeline.ps1\`, \`scripts/New-DailyReport.ps1\`: route delivery results to the new record writer.
- \`scripts/Test-BestSellersDailyOperationalHealth.ps1\`: read only the daily latest pointer.
- \`src/DashboardPublishState.psm1\`: lock and atomic dashboard state.
- \`scripts/Publish-BestSellersDashboard.ps1\`, \`scripts/Invoke-DashboardPublishRecovery.ps1\`, \`scripts/Register-DashboardPublishScheduledTask.ps1\`: primary and recovery publish behavior.
- \`src/LocalPackageScheduledTasks.psm1\`: precisely retire the obsolete legacy daily task.
- \`tests/MailDeliveryRecords.Tests.ps1\`, \`tests/DashboardPublishState.Tests.ps1\`, \`tests/DashboardPublishing.Tests.ps1\`, \`tests/LocalPackageScheduledTasks.Tests.ps1\`: regressions.
- \`README.md\` and \`docs/phase-7/MAINTENANCE-RUNBOOK.md\`: supported task topology and evidence semantics.

### Task 1: Immutable delivery records

**Files:**
- Modify: \`src/MailDelivery.psm1:85-110\`
- Create: \`tests/MailDeliveryRecords.Tests.ps1\`

**Interfaces:**
- Consumes: \`Send-DailyReportEmail\` result \`{ Status, Recipient, SentAt, ErrorMessage }\`.
- Produces: \`Write-MailDeliveryRunRecords -MarketDate <string> -ReportKind <Daily|Weekly> -Messages <object[]> -WorkRoot <string> -RunId <string>\`, returning \`{ ManifestPath, RecordPaths, LatestPath, OverallStatus }\`.

- [ ] **Step 1: Write the failing test**

\`\`\`powershell
It 'keeps daily and weekly email evidence separate for one market date' {
    $daily = Write-MailDeliveryRunRecords -MarketDate '2026-08-24' -ReportKind Daily -WorkRoot $TestDrive -RunId 'daily' -Messages @($dailyMessage)
    $weekly = Write-MailDeliveryRunRecords -MarketDate '2026-08-24' -ReportKind Weekly -WorkRoot $TestDrive -RunId 'weekly' -Messages @($weeklyMessage)
    Test-Path $daily.ManifestPath | Should Be $true
    Test-Path $weekly.ManifestPath | Should Be $true
    (Get-Content -Raw $daily.LatestPath | ConvertFrom-Json).report_kind | Should Be 'Daily'
    (Get-Content -Raw $weekly.LatestPath | ConvertFrom-Json).report_kind | Should Be 'Weekly'
    @($daily.RecordPaths).Count | Should Be 1
}
\`\`\`

- [ ] **Step 2: Run test to verify RED**

Run: \`powershell.exe -NoProfile -NonInteractive -Command "Invoke-Pester .\\tests\\MailDeliveryRecords.Tests.ps1 -EnableExit"\`

Expected: FAIL because \`Write-MailDeliveryRunRecords\` is not exported.

- [ ] **Step 3: Implement minimal record writer**

Add \`Get-MailDeliveryRecordRoot\`, \`Write-MailDeliveryJsonAtomically\`, \`Get-MailDeliverySha256\`, and \`Write-MailDeliveryRunRecords\`. Validate date, kind, unique nonempty category, existing PDF, and error sanitization. Write \`<category>.json\` files first, then \`manifest.json\`, then atomically replace only \`delivery/<kind>/latest.json\`. Each record contains report kind, run ID, category, report filename, SHA-256, recipient, SMTP status, sent timestamp, and redacted error.

- [ ] **Step 4: Run test to verify GREEN**

Run: \`powershell.exe -NoProfile -NonInteractive -Command "Invoke-Pester .\\tests\\MailDeliveryRecords.Tests.ps1 -EnableExit"\`

Expected: PASS; no shared \`email-delivery-summary.json\` is created.

- [ ] **Step 5: Commit**

\`\`\`powershell
git add src/MailDelivery.psm1 tests/MailDeliveryRecords.Tests.ps1
git commit -m "feat: preserve per-message delivery records"
\`\`\`

### Task 2: Route reports and health audit to kind-specific evidence

**Files:**
- Modify: \`scripts/New-BestSellersDailyReport.ps1:22-47\`
- Modify: \`scripts/New-BestSellersWeeklyReport.ps1:84-98,124-125\`
- Modify: \`scripts/Invoke-DailyPipeline.ps1:25-42\`
- Modify: \`scripts/Invoke-CredentialFreeDailyPipeline.ps1:35-45\`
- Modify: \`scripts/New-DailyReport.ps1:20-27\`
- Modify: \`scripts/Test-BestSellersDailyOperationalHealth.ps1:64-65\`
- Modify: \`tests/AmazonIntelligence.Tests.ps1:597-607\`
- Test: \`tests/MailDeliveryRecords.Tests.ps1\`

**Interfaces:**
- Consumes: \`Write-MailDeliveryRunRecords\` from Task 1.
- Produces: report JSON fields \`EmailDeliveryManifestPath\` and \`EmailDeliveryRecordPaths\`; health JSON derives \`EmailDeliveryStatus\` only from \`delivery/daily/latest.json\`.

- [ ] **Step 1: Write failing integration tests**

\`\`\`powershell
It 'writes three daily message records for three generated category reports' {
    $result = & $dailyScript -CurrentPath $completeSnapshot -OutputDirectory $TestDrive -SkipEmail | ConvertFrom-Json
    @($result.EmailDeliveryRecordPaths).Count | Should Be 3
    (Get-Content -Raw $result.EmailDeliveryManifestPath | ConvertFrom-Json).report_kind | Should Be 'Daily'
}
It 'ignores a weekly latest pointer when auditing daily email status' {
    # daily/latest.json = SENT; weekly/latest.json = SKIPPED_BY_REQUEST
    $health.EmailDeliveryStatus | Should Be 'SENT'
}
\`\`\`

- [ ] **Step 2: Run test to verify RED**

Run: \`powershell.exe -NoProfile -NonInteractive -Command "Invoke-Pester .\\tests\\MailDeliveryRecords.Tests.ps1 -EnableExit"\`

Expected: FAIL because report scripts call \`Write-MailDeliverySummary\` and health reads the shared path.

- [ ] **Step 3: Implement report routing**

Build one message object per category and call the new writer once after all three send attempts; use \`Daily\` or \`Weekly\` as appropriate. Migrate the three legacy one-report callers with a \`general\` category. Preserve aggregate \`EmailDelivery\`; add manifest and record output fields; stop all new writes to the legacy filename. Change health to return \`NOT_RECORDED\` only when the daily latest pointer is absent.

- [ ] **Step 4: Run test to verify GREEN**

Run: \`powershell.exe -NoProfile -NonInteractive -Command "Invoke-Pester .\\tests\\MailDeliveryRecords.Tests.ps1, .\\tests\\AmazonIntelligence.Tests.ps1 -EnableExit"\`

Expected: PASS without any SMTP connection.

- [ ] **Step 5: Commit**

\`\`\`powershell
git add scripts/New-BestSellersDailyReport.ps1 scripts/New-BestSellersWeeklyReport.ps1 scripts/Invoke-DailyPipeline.ps1 scripts/Invoke-CredentialFreeDailyPipeline.ps1 scripts/New-DailyReport.ps1 scripts/Test-BestSellersDailyOperationalHealth.ps1 tests/AmazonIntelligence.Tests.ps1 tests/MailDeliveryRecords.Tests.ps1
git commit -m "fix: isolate daily and weekly delivery evidence"
\`\`\`

### Task 3: Dashboard publish state and recovery

**Files:**
- Create: \`src/DashboardPublishState.psm1\`
- Modify: \`scripts/Publish-BestSellersDashboard.ps1:1-67\`
- Create: \`scripts/Invoke-DashboardPublishRecovery.ps1\`
- Modify: \`scripts/Register-DashboardPublishScheduledTask.ps1:1-11\`
- Create: \`tests/DashboardPublishState.Tests.ps1\`
- Modify: \`tests/DashboardPublishing.Tests.ps1:1-44\`

**Interfaces:**
- Consumes: existing \`New-DashboardPublishResult\`.
- Produces: \`Enter-DashboardPublishLock\`, \`Read-DashboardPublishState\`, \`Write-DashboardPublishState\`; state shape \`{ Status, MarketDate, CompletedAt, ObservationCount, ReportsUploaded, ErrorMessage }\`.

- [ ] **Step 1: Write failing publish-state tests**

\`\`\`powershell
It 'writes PUBLISHED state atomically after primary success' {
    $path = Write-DashboardPublishState -Root $TestDrive -MarketDate '2026-08-23' -Status PUBLISHED -ObservationCount 90 -ReportsUploaded 6
    (Read-DashboardPublishState -Root $TestDrive -MarketDate '2026-08-23').Status | Should Be 'PUBLISHED'
    Test-Path ($path + '.tmp') | Should Be $false
}
It 'skips 09:15 recovery after a published primary state' {
    Write-DashboardPublishState -Root $TestDrive -MarketDate '2026-08-23' -Status PUBLISHED -ObservationCount 90 -ReportsUploaded 6 | Out-Null
    (& $recoveryScript -MarketDate '2026-08-23' -ProjectRoot $TestDrive -Publisher { throw 'must not run' } | ConvertFrom-Json).Status | Should Be 'SKIPPED_ALREADY_PUBLISHED'
}
\`\`\`

- [ ] **Step 2: Run test to verify RED**

Run: \`powershell.exe -NoProfile -NonInteractive -Command "Invoke-Pester .\\tests\\DashboardPublishState.Tests.ps1 -EnableExit"\`

Expected: FAIL because the state module and recovery script do not exist.

- [ ] **Step 3: Implement publish state and recovery**

Use a named \`System.Threading.Mutex\` keyed by market date. Write state under \`var/scheduler/dashboard-publish/<market-date>.json\` with temp-file replacement. Publisher writes \`PUBLISHED\` only after current verified publication succeeds and writes a sanitized \`FAILED\` state before rethrowing. Recovery returns \`SKIPPED_ALREADY_PUBLISHED\` with exit 0 after valid primary success; otherwise it calls the publisher once.

- [ ] **Step 4: Add and test task registration**

Extend the registration script to use the exact Windows PowerShell executable and register \`Amazon-BS-Dashboard-Publish-0900\` at 09:00 plus \`Amazon-BS-Dashboard-Publish-Recovery-0915\` at 09:15, both interactive and \`IgnoreNew\`.

Run: \`powershell.exe -NoProfile -NonInteractive -Command "Invoke-Pester .\\tests\\DashboardPublishState.Tests.ps1, .\\tests\\DashboardPublishing.Tests.ps1 -EnableExit"\`

Expected: PASS; no test posts to the live dashboard.

- [ ] **Step 5: Commit**

\`\`\`powershell
git add src/DashboardPublishState.psm1 scripts/Publish-BestSellersDashboard.ps1 scripts/Invoke-DashboardPublishRecovery.ps1 scripts/Register-DashboardPublishScheduledTask.ps1 tests/DashboardPublishState.Tests.ps1 tests/DashboardPublishing.Tests.ps1
git commit -m "feat: add dashboard publish recovery"
\`\`\`

### Task 4: Retire legacy daily registration and document ownership

**Files:**
- Modify: \`src/LocalPackageScheduledTasks.psm1:68-89\`
- Modify: \`tests/LocalPackageScheduledTasks.Tests.ps1:25-110\`
- Modify: \`README.md:72-79\`
- Modify: \`docs/phase-7/MAINTENANCE-RUNBOOK.md:15-39,97-100\`

**Interfaces:**
- Consumes: existing injected \`SchedulerRunner\`.
- Produces: canonical task registration that removes only \`AmazonIntelligence-Daily-0900\` and \`Amazon-BS-Package-Weekly-0900\` after their replacements succeed.

- [ ] **Step 1: Write failing scheduler test**

\`\`\`powershell
It 'removes only the two obsolete scheduled task names after successful replacement' {
    Register-LocalPackageScheduledTasks -ProjectRoot $TestDrive -TimeZoneProvider { 'China Standard Time' } -IdentityProvider { 'DOMAIN\\interactive' } -SchedulerRunner $runner | Out-Null
    @($removed) | Should Contain 'AmazonIntelligence-Daily-0900'
    @($removed) | Should Contain 'Amazon-BS-Package-Weekly-0900'
    @($removed).Count | Should Be 2
}
\`\`\`

- [ ] **Step 2: Run test to verify RED**

Run: \`powershell.exe -NoProfile -NonInteractive -Command "Invoke-Pester .\\tests\\LocalPackageScheduledTasks.Tests.ps1 -EnableExit"\`

Expected: FAIL because task definitions support only one obsolete task name.

- [ ] **Step 3: Implement retirement and docs**

Support an \`ObsoleteTaskNames\` array, remove only exact names after registration, and retain canonical actions on \`Start-LocalPackage.ps1\`. Document the four Windows tasks, paused Codex automations, project-local PostgreSQL logging, and the SMTP-acceptance limitation. Do not register \`Invoke-ScheduledDailyPipeline.ps1\`.

- [ ] **Step 4: Run test to verify GREEN**

Run: \`powershell.exe -NoProfile -NonInteractive -Command "Invoke-Pester .\\tests\\LocalPackageScheduledTasks.Tests.ps1, .\\tests\\DashboardPublishState.Tests.ps1 -EnableExit"\`

Expected: PASS and no broad task deletion.

- [ ] **Step 5: Commit**

\`\`\`powershell
git add src/LocalPackageScheduledTasks.psm1 tests/LocalPackageScheduledTasks.Tests.ps1 README.md docs/phase-7/MAINTENANCE-RUNBOOK.md
git commit -m "fix: make Windows scheduler the sole supported runner"
\`\`\`

### Task 5: Full verification and task reconciliation

**Files:**
- Modify: only source files required to correct an in-scope failing test.
- Test: \`scripts/Test.ps1\`, no-email report smoke test, task registration output.

**Interfaces:**
- Consumes: Tasks 1-4.
- Produces: four ready Windows tasks, three paused Codex automations, and verified regression results.

- [ ] **Step 1: Make ignored dependencies available only to this worktree**

Create worktree-local junctions to the main worktree \`.venv\` and ignored \`config/sources.json\` only when each is absent. Confirm both are ignored with \`git check-ignore -v .venv config/sources.json\`; do not copy or commit either path.

- [ ] **Step 2: Run complete offline tests**

Run: \`powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\\scripts\\Test.ps1\`

Expected: zero failures. If a failure remains after dependencies are available, record its exact test and cause before modifying unrelated production code.

- [ ] **Step 3: Run safe smoke checks**

Run: \`powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\\scripts\\postgres\\Start-LocalPostgres.ps1\`

Run: \`powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\\scripts\\New-BestSellersDailyReport.ps1 -CurrentPath .\\tests\\fixtures\\best-sellers\\complete.json -OutputDirectory $env:TEMP\\amazon-bs-delivery-smoke -SkipEmail\`

Expected: database is ready; the daily command writes one manifest and three records without email.

- [ ] **Step 4: Re-register and inspect tasks**

Run: \`powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\\scripts\\Register-LocalPackageScheduledTasks.ps1\`

Run: \`powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\\scripts\\Register-DashboardPublishScheduledTask.ps1 -DashboardUrl 'https://amazon-bs-market-radar.warrenwangyihao.chatgpt.site/'\`

Run: \`Get-ScheduledTask -TaskName 'Amazon-BS-Package-Daily-0800','Amazon-BS-Package-Weekly-0600','Amazon-BS-Dashboard-Publish-0900','Amazon-BS-Dashboard-Publish-Recovery-0915' | Select-Object TaskName,State\`

Expected: all four tasks are \`Ready\`; the exact obsolete daily task is absent.

- [ ] **Step 5: Verify automation state and repository hygiene**

Confirm the three known Codex automation TOML files have \`status = "PAUSED"\`. Run \`git diff --check\`, \`git status --short\`, and the targeted secret scan; stage no ignored runtime artifact or secret.

- [ ] **Step 6: Commit and hand off**

\`\`\`powershell
git add src scripts tests README.md docs
git commit -m "test: verify operational reliability workflow"
\`\`\`

Report the exact test count, task status, paused automation names, and the SMTP/inbox-delivery limitation.

