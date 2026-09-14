# Local Launcher Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every supported `Start-Amazon-BS.bat` function operational on the current machine without weakening download verification or risking production data.

**Architecture:** Preserve the BAT-to-PowerShell-to-module boundary and add only the missing typed arguments. Keep historical archive validation in `LocalPackageHistory.psm1`, make the PostgreSQL restore drill emit a clean JSON control message, and teach Setup to verify an already configured PostgreSQL installation before considering a download. Persist SMTP secrets only in Windows User environment variables and register the two exact idempotent scheduled tasks through the existing scheduler module.

**Tech Stack:** Windows PowerShell 5.1, Pester 3.4, PostgreSQL 18.4, Windows ScheduledTasks.

## Global Constraints

- Never disable or bypass authoritative SHA-256 validation for new downloads.
- Never restore or overwrite the production database during verification.
- Never print or persist SMTP authorization codes in project files, logs, reports, or scheduled-task arguments.
- Preserve the three public Top 30 collection rules and existing report behavior.
- Every production change follows a failing regression test and a fresh passing verification.

---

### Task 1: History path plumbing and clean restore JSON

**Files:**
- Modify: `tests/LocalPackageLauncher.Tests.ps1`
- Modify: `tests/LocalPackageHistory.Tests.ps1`
- Modify: `scripts/Start-LocalPackage.ps1`
- Modify: `src/LocalPackageOrchestrator.psm1`
- Modify: `scripts/postgres/Test-LocalPostgresRestoreDrill.ps1`

**Interfaces:**
- Consumes: `-ArchivePath <zip>` for `ImportHistory`, optional `-OutputPath <zip>` for `ExportHistory`.
- Produces: one launcher JSON summary and one restore-drill JSON object with no preceding native command output.

- [ ] Add tests asserting parameter forwarding, menu import-path prompting, and direct restore JSON parsing.
- [ ] Run focused tests and confirm failures are caused by missing forwarding and polluted output.
- [ ] Add the two entry parameters, forward them through `Invoke-LocalPackageMode`, and suppress successful `psql` command output.
- [ ] Run focused tests and the real export/import validation cycle.

### Task 2: Reuse a verified configured PostgreSQL installation in Setup

**Files:**
- Modify: `tests/LocalPackageSetup.Tests.ps1`
- Modify: `src/LocalPackageSetup.psm1`
- Modify: `README.md`
- Modify: `docs/phase-7/MAINTENANCE-RUNBOOK.md`

**Interfaces:**
- Consumes: `.local/postgres-settings.json`, `.local/postgres-data/PG_VERSION`, and the configured `install_root`.
- Produces: Setup component status `RETAINED_CONFIGURED` and the verified configured `initdb.exe` path.

- [ ] Add tests for a consistent verified external installation, inconsistent markers, missing executable, and wrong version.
- [ ] Confirm the valid configured-installation test fails before implementation.
- [ ] Resolve and verify the configured installation before attempting the manifest download path; retain fail-closed behavior for new installs.
- [ ] Run focused tests and real `Start-Amazon-BS.bat Setup`.

### Task 3: Persist mail configuration and register scheduled tasks

**Files:**
- Use: `scripts/Set-EmailEnvironment.ps1`
- Use: `scripts/Set-LocalPackageRecipient.ps1`
- Use: `scripts/Register-LocalPackageScheduledTasks.ps1`
- Verify: `tests/LocalPackageScheduledTasks.Tests.ps1`

**Interfaces:**
- Consumes: already configured process-scoped SMTP values and recipient `746254487@qq.com`.
- Produces: user-scoped SMTP variables, `.local/user-settings.json`, and the two fixed scheduled tasks.

- [ ] Verify credentials are present without displaying them.
- [ ] Persist the existing process values to User scope and verify only boolean configuration state.
- [ ] Save the recipient setting without secrets.
- [ ] Register the two idempotent tasks and inspect names, triggers, actions, time zone, and absence of secret text.

### Task 4: Full verification

**Files:**
- Verify: all project tests and runtime artifacts.

**Interfaces:**
- Consumes: repaired launcher and current verified snapshot/database.
- Produces: fresh evidence for every supported BAT mode.

- [ ] Run all Pester tests and require zero failures.
- [ ] Run BAT `Test`, `Setup`, `Health`, `Weekly -SkipEmail`, `ExportHistory`, and `ImportHistory -ArchivePath`.
- [ ] Verify `DailyAuto` and `DailyImport` using safe no-email invocations only if current snapshot state requires it.
- [ ] Confirm planned tasks and SMTP persistence survive a fresh PowerShell process.
- [ ] Report any remaining external limitation explicitly.
