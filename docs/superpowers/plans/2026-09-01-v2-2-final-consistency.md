# Amazon BS Market Radar V2.2 Implementation Plan

> Execute in dependency order. Tests precede production changes. Preserve raw snapshots and all existing public routes.

## Task 1 — Classification regression and deterministic rules

- Add fixtures for Westinghouse electric, gas, cordless, surface cleaner, gun, hose, nozzle, pump protector, compatibility language, `electricity`, bundled nozzle/gun, and unknown.
- Make the tests fail against current rules.
- Add boundary-aware matching and explicit rule priority/specificity in `BestSellersDataSemantics.psm1` and config.
- Verify current Top30 audit, unknown counts, and no sump subtype guessing.

## Task 2 — PG/D1 classification-version parity

- Add PG and D1 tests for v1-high→v2-high, v1-medium→v2-medium, confidence upgrade, lower-version rejection and trusted brand conflict preservation.
- Add a new forward migration restoring version-aware classification without weakening migration 013 brand guards.
- Keep D1 upsert behavior semantically identical.
- Generate/import updated metadata through the existing pipeline; never edit snapshots.

## Task 3 — Unified dated Market Universe

- Add a single builder/loader accepting category, segment and requested valid market date.
- Select the most recent valid category day when latest Snapshot is incomplete.
- Return raw rows, analytical rows, previous valid rows, history and one stable ASIN set.
- Replace remaining page/report/alert-specific filtering.
- Add same-context equality and incomplete-day exit protection tests.

## Task 4 — Page-local Context and product detail isolation

- Extend parse/serialize/normalize/navigation inheritance to optional valid `date`.
- Add/upgrade MarketDateSelect using only valid dates.
- Make `loadLiveProduct` category-scoped and segment-validated; preserve category-specific history for duplicate ASINs.
- Preserve context in SignalCard and ProductIdentity links.
- Add deep-link, refresh, back/forward, invalid URL and duplicate-ASIN tests.

## Task 5 — Reports, Alerts and cache isolation

- Pass full MarketContext to live report and seller-intelligence builders.
- Scope new stored report metadata to category+segment+period; label historical category-wide records.
- Cancel/reset stale AnalysisCenter and ReportsArchive requests on context change.
- Fix archive undefined import and add delayed-response ordering tests.

## Task 6 — Page consistency and brand analytics

- Ensure Overview, Market, Products, Brands, Rankings, Reports and Alerts consume the same Universe.
- Count only High in the High KPI; separate Watch and Activity copy.
- Filter zero Brand Movement rows; retain “stable” empty state.
- Keep Brands denominator equal to analytical universe, Top5+Others, seat share and Top3 concentration.
- Add dynamic Product type filters from MARKET_CONFIG; no speculative sump subtype filters.

## Task 7 — Shared display and legacy page cleanup

- Centralize rank, delta, reviews, rating, price, deal, date, percentage and missing formatting.
- Separate RankDisplay from RankDelta; remove all page-local variants.
- Standardize ProductIdentity metadata and context-aware links.
- Migrate Reports/Alerts/Methodology content to the current AppShell language and definitions without redesigning the shell.

## Task 8 — Freshness and operational recovery

- Add an additive collection-run/freshness contract or equivalent existing-pipeline record for real attempt status.
- Surface Latest Crawl, Latest Snapshot and Latest Valid Market Day in Data Status; keep Overview summary compact.
- Diagnose and repair the existing Windows scheduled task without replacing the collector.
- Verify failed/incomplete runs never produce Exit/Turnover/Contraction.

## Task 9 — Verification and release

- Run PowerShell, Python and Web unit/integration suites after each affected layer.
- Browser QA: refresh, deep links, invalid URLs, navigation inheritance, back/forward, rapid switching and three independent tabs.
- Screenshot QA at 1366×768, 1440×900 and 1920×1080 for all PRD pages.
- Run lint/type/build and the full 243+ test suite.
- Request final code review, address findings, deploy through the existing Sites configuration, and verify the public URL.
