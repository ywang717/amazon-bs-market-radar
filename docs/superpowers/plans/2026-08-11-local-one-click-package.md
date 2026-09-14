# Amazon BS Local One-Click Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Use TDD for all behavior changes.

**Goal:** Deliver a portable Windows package whose single visible entrypoint is `Start-Amazon-BS.bat`, with a Chinese menu for setup, automatic or imported Top 30 collection, daily/weekly reporting, scheduling, health checks, and history migration.

**Architecture:** The BAT file is a thin launcher. A PowerShell orchestrator owns menus and pipeline sequencing, existing PowerShell modules remain the business layer, and a Python Playwright collector owns visible-browser extraction. All downloaded runtimes and mutable state stay under ignored `.local/` and `var/` directories.

**Tech Stack:** Windows PowerShell 5.1, Python 3.12, Playwright, PostgreSQL 18.4, existing Pester tests.

## Global Constraints

- Windows 10/11 x64; scheduling is registered only when the host uses `China Standard Time`.
- Collect only public Amazon pages; never log in, bypass CAPTCHA, or circumvent access controls.
- Each chart targets verified global ranks 1-30; missing visible values are `null`, never inferred.
- Keep SMTP authorization codes out of files, logs, reports, backups, and process output.
- Do not package `var/`, `.local/`, `.venv/`, `tmp/`, credentials, database files, or generated reports.
- Preserve the existing verified receipt, transactional import, three-PDF delivery, archive, backup, and health-audit gates.

---

### Task 1: Portable runtime and PDF verification

Create behavior tests for resolving project-local Python/PostgreSQL paths and for eliminating Codex cache paths. Implement a runtime settings module and update PDF initialization/rendering to use project-local tools, with Python page rendering verification replacing the hard-coded Poppler executable. Add locked dependencies needed by PDF verification and browser collection.

### Task 2: Visible browser Top 30 collector

Create fixture-driven Python tests first for rank extraction, null fields, duplicate/missing ranks, pagination restart, category mismatch, login pages, and Robot Check. Implement a Playwright collector that writes the existing snapshot schema and a structured collection-status artifact, preferring installed Edge and falling back to project-local Chromium.

### Task 3: One-click launcher, menu, and orchestration

Create PowerShell behavior tests first. Add `Start-Amazon-BS.bat` and a PowerShell entrypoint supporting Menu, Setup, DailyAuto, DailyImport, Weekly, Health, Test, RegisterTasks, ExportHistory, and ImportHistory modes. Daily modes must sequence receipt registration/verification, verified import, three reports, backup, and health audit; zero total observations must not generate or send reports.

### Task 4: Portable setup and configuration

Create tests first for idempotent setup, version manifest validation, safe user settings, SMTP secret handling, relative PostgreSQL settings, and download checksum failures. Implement per-project Python/PostgreSQL/bootstrap installation without administrator rights and browser fallback installation.

### Task 5: Scheduling and history migration

Create tests first for Beijing-time task registration, non-overlap, launcher arguments, export manifests, checksum validation, excluded secrets, and safe restore staging. Implement daily 08:00 and Monday 09:00 tasks plus separate history export/import commands.

### Task 6: Documentation and end-to-end verification

Update README and operating docs to describe the one-click workflow, Top 30 rules, current schedules, portability, setup, failure handling, and migration. Run the full Pester/Python suite, launcher dry runs, complete/partial/zero-data integration fixtures, backup/restore verification, and a `-SkipEmail` end-to-end smoke test.
