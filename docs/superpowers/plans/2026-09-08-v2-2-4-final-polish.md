# Amazon BS Market Radar V2.2.4 Final Polish Implementation Plan

> **For Codex:** Follow the user-approved V2.2.4 PRD in this task. Use test-driven development and keep all changes inside this isolated worktree.

**Goal:** Remove the remaining misleading controls and unfinished states, preserve Pacific market-date semantics and raw rankings, and complete the already-started product-structure and explainable research workflows.

**Architecture:** Extend the existing AppShell, market analysis utilities, product classification, shared formatters, and report components. Do not add parallel engines, change crawler/date boundaries, or alter raw ranking order.

**Tech Stack:** React 19, Vinext/Vite, TypeScript, Node test runner, Cloudflare Sites/D1/R2.

---

### Task 1: Phase 1 semantics and report states

**Files:**
- Modify: `web/app/market/page.tsx`
- Modify: `web/app/reports/page.tsx`
- Modify: `web/app/reports/ReportsArchive.tsx`
- Modify: `web/tests/rendered-html.test.mjs`
- Modify: `web/tests/reports-view.test.mjs`

- [ ] Add failing rendered/report tests for 1D-only Movers/Entrants, Pacific wording, single report empty state, and non-loading completed archives.
- [ ] Implement the smallest UI/state changes.
- [ ] Run the focused Phase 1 tests and confirm green.

### Task 2: Shared display and product-detail semantics

**Files:**
- Modify only if needed: `web/app/components/RankDisplay.tsx`
- Modify only if needed: `web/app/products/[asin]/page.tsx`
- Modify only if needed: `web/app/brands/page.tsx`
- Modify: focused UI tests

- [ ] Add failing tests only for observed gaps in RankDelta, brand period labels, and valid-presence naming.
- [ ] Reuse shared components/formatters and make minimal fixes.
- [ ] Run focused tests and confirm green.

### Task 3: Phase 2 polish without rebuilding existing features

**Files:**
- Modify only directly affected Market/Reports/Methodology components and focused tests.

- [ ] Verify current-state versus trend hierarchy, analytical sample naming, thin Market tabs, product types, Top30 structure, worth-studying evidence, review competition, and window contract.
- [ ] Add red tests and patch only confirmed gaps.
- [ ] Run focused Phase 2 tests and confirm green.

### Task 4: QA, regression, build, and publish

- [ ] Verify Pacific-time/date invariants and raw-ranking invariants.
- [ ] Run lint, focused/full tests, and production build.
- [ ] Run requested browser QA and 1440×900 screenshot QA on the specified pages, including a product with at least 20 valid market days.
- [ ] Publish the verified build through the existing Sites project and verify the production URL.
