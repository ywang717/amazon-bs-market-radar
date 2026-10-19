# Audit Follow-up Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans task by task; independent fixture/platform tasks may use superpowers:dispatching-parallel-agents.

**Goal:** Resolve remaining audit provenance and repair reproducible PowerShell regressions without weakening production data validation or rewriting historical facts.

**Architecture:** Retain production contracts and the active branch. Fix test fixtures for their explicit category scope, make platform assumptions explicit, and modify runtime code only for confirmed portable behavior defects. Historic sources are selected by validated content hash/capture time rather than folder label alone.

**Tech Stack:** PowerShell/Pester4, Python/Playwright, PostgreSQL read-only backup inspection, existing Sites deployment.

- [x] Reconcile 9/12 against SHA-matched Pacific sources and real browser rank data; update the audit and diagnostic selector, no production write.
- [x] Repair copied Registry config dependencies and outdated current-category expectations; run relevant tests (independent task).
- [x] Repair Windows-only and portable child-process test harness assumptions; mark unavailable actual Windows checks skipped, do not simulate successful platform acceptance (independent task).
- [x] Pin historical three-category fixtures to explicit Registry contracts or upgrade actual current-scope fixtures to17; restore pipeline/publisher regression checks.
- [x] Investigate remaining failures from fresh test output, add focused regressions before any runtime fix, then run full PowerShell tests and applicable Web/build checks.
- [x] Review diff and push runtime fixes (`536bb76`); commit/push diagnostic tests and updated audit. Web runtime unchanged, Sites22 remains active; preserve lock deletion and production data/access.
- [ ] Historical timestamp metadata backfill: NOT_APPLIED. Existing sync rewrites normalized rows and rejects rollback to earlier timestamps; supported reversible metadata maintenance plus raw D1 backup/verification is required.
