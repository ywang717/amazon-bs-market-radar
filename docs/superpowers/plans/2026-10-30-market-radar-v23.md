# Amazon BS Market Radar V2.3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add real calendar date selection, custom two-day comparison, real range analysis, signal filtering, sorting, CSV export, and explicit data-quality states while preserving existing data and 1D/7D/30D semantics.

**Architecture:** Keep the existing server-rendered routes and D1-backed `history` as the source of truth. Add pure read-only comparison/range functions in `ui-intelligence.ts`, serialize modes in query parameters, and use small client controls for calendar, filters, sorting, CSV, and local watch state.

**Tech Stack:** React 19, vinext, TypeScript, existing CSS and Node test runner.

**Spec:** User-pasted PRD V2.3 in `/Users/ASUS/.codex/attachments/db694fcd-ec53-4d3e-ac19-66b87d8b580e/已粘贴的文本.txt`.

## Global Constraints

- Preserve Pacific Time, existing API contracts, D1 schema, ingestion, historical records, and signal thresholds.
- Use only real valid market days from existing history; never fill missing ranks, prices, reviews, or dates.
- Keep automatic 1D, 7D, and 30D calculations unchanged.
- No new dependency or heavy chart/state library.

## Review Focus

- Invalid, equal, reversed, future, and insufficient range dates remain explicit and never become fake data.
- Custom comparison keeps prices/reviews null when either endpoint is missing and distinguishes entry/exit from first listing.
- Query navigation preserves category, segment, date, mode, and comparison/range parameters.
- CSV escapes formulas, commas, quotes, newlines, and missing values safely.
- Calendar keyboard and Escape behavior does not alter the Pacific market date unexpectedly.

### Task 1: Pure comparison and range analysis

**Files:** Modify `web/lib/ui-intelligence.ts`; Test `web/tests/ui-intelligence.test.mjs`.

- [ ] Add failing tests for custom endpoint comparison, range validation, real-day product series, brand seat deltas, and null endpoint metrics.
- [ ] Implement `buildTwoDayComparison` and `buildRangeAnalysis` using only supplied history rows.
- [ ] Run focused tests, then full tests.

### Task 2: URL-aware calendar and analysis mode controls

**Files:** Create `web/app/components/MarketDateCalendar.tsx`, modify `MarketContext.tsx`, `v2.css`; Test `web/tests/rendered-html.test.mjs`.

- [ ] Add failing render assertions for calendar trigger, mode labels, and preserved query parameters.
- [ ] Implement accessible calendar with valid-day markers, month navigation, keyboard activation, Escape/outside close, previous/next valid day, latest valid day, and single/two-day/range query serialization.
- [ ] Run focused tests.

### Task 3: Market range workspace and two-day comparison

**Files:** Modify `web/app/market/page.tsx`, create `RangeAnalysisPanel.tsx`, modify `page.tsx`; Test `web/tests/rendered-html.test.mjs` and `ui-intelligence.test.mjs`.

- [ ] Add failing tests for range summary, product/brand trends, endpoint labels, and mode isolation.
- [ ] Render two-day and range panels from real `history`, with explicit insufficient-data states and CSV export.
- [ ] Run focused tests.

### Task 4: Signal filters and list controls

**Files:** Modify `web/app/market/page.tsx`, `ProductBrowser.tsx`, `RankingExplorer.tsx`; create `CsvDownloadButton.tsx`; Test `web/tests/rendered-html.test.mjs`.

- [ ] Add failing tests for combined signal filters, result counts, sort directions, null-last behavior, and filtered CSV columns.
- [ ] Implement URL-backed filters/sorting and UTF-8 BOM CSV export.
- [ ] Run focused tests.

### Task 5: Data quality and regression verification

**Files:** Modify `DashboardDataNotices.tsx`, shared CSS as needed; tests for loading/failure/empty/insufficient states.

- [ ] Add regression tests distinguishing failure, empty, no-match, and insufficient comparison.
- [ ] Run typecheck, lint, full tests, production build, and browser verification at desktop and mobile widths where available.
- [ ] Commit source changes, publish Sites version, and report any browser limitations.
