# Weekly Schedule 06:00 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the Monday weekly report task from 09:00 to 06:00 China Standard Time without changing the daily 08:00 task.

**Architecture:** Keep the existing scheduled-task module as the single source of task definitions. Register the new exact weekly task first, then remove only the obsolete exact weekly task name so unrelated Windows tasks remain untouched.

**Tech Stack:** Windows PowerShell 5.1, ScheduledTasks module, Pester.

## Global Constraints

- Daily task remains `Amazon-BS-Package-Daily-0800` at 08:00.
- Weekly task becomes `Amazon-BS-Package-Weekly-0600` on Monday at 06:00.
- Only `Amazon-BS-Package-Weekly-0900` may be removed during migration.
- Do not run collection, send email, or generate reports during verification.

---

### Task 1: Protect the new schedule and migration behavior

**Files:**
- Modify: `tests/LocalPackageScheduledTasks.Tests.ps1`
- Modify: `src/LocalPackageScheduledTasks.psm1`

**Interfaces:**
- Consumes: `Register-LocalPackageScheduledTasks -ProjectRoot <path>`.
- Produces: task definitions for daily 08:00 and Monday weekly 06:00, plus exact obsolete-task cleanup.

- [ ] **Step 1: Write failing tests**

Update behavior assertions to require `Amazon-BS-Package-Weekly-0600`, a Monday trigger at 06:00, and one exact removal of `Amazon-BS-Package-Weekly-0900` after registration.

- [ ] **Step 2: Verify the tests fail against the 09:00 implementation**

Run:

```powershell
Invoke-Pester .\tests\LocalPackageScheduledTasks.Tests.ps1
```

Expected: failures showing the old weekly name/time and absent migration cleanup.

- [ ] **Step 3: Implement the minimal schedule migration**

Change the weekly task definition to 06:00 and attach the single obsolete task name. In the real registration boundary, register the new task first and remove only that exact obsolete name when present.

- [ ] **Step 4: Verify focused tests pass**

```powershell
Invoke-Pester .\tests\LocalPackageScheduledTasks.Tests.ps1
```

Expected: zero failures.

### Task 2: Synchronize entrypoint summaries and operator documentation

**Files:**
- Modify: `scripts/Register-LocalPackageScheduledTasks.ps1`
- Modify: `README.md`
- Modify: `docs/phase-7/MAINTENANCE-RUNBOOK.md`

**Interfaces:**
- Consumes: task names defined by the registration module.
- Produces: accurate failure summaries and current operator instructions.

- [ ] **Step 1: Update current-facing references**

Replace the package weekly task name/time with `Amazon-BS-Package-Weekly-0600` and Monday 06:00. Leave historical checkpoint documents unchanged.

- [ ] **Step 2: Run the full regression suite**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1
```

Expected: zero failures.

### Task 3: Apply and verify the Windows task migration

**Files:**
- No source-file changes.

**Interfaces:**
- Consumes: `scripts/Register-LocalPackageScheduledTasks.ps1`.
- Produces: active Windows tasks `Daily-0800` and `Weekly-0600` only.

- [ ] **Step 1: Register tasks locally**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Register-LocalPackageScheduledTasks.ps1
```

- [ ] **Step 2: Inspect exact task state**

Verify that daily remains 08:00, weekly is Monday 06:00, both actions point to the local launcher, and `Amazon-BS-Package-Weekly-0900` no longer exists.

- [ ] **Step 3: Run the full regression suite again**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1
```

Expected: zero failures and no report/email/collection side effects.

## Self-review

The plan covers the schedule definition, exact-name migration, failure summary, current documentation, local application, and fresh regression verification. It contains no unresolved placeholders. The task names and times are consistent with the approved design.
