# Page-local Multi-Market Context V2.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make category and segment URL-local inputs for every core page while inheriting them through navigation and keeping all three Amazon markets isolated.

**Architecture:** `MARKET_CONFIG` and `PAGE_MARKET_DEFAULTS` remain the single business-rule source. Server pages resolve and normalize URL search parameters, pass the resulting context to existing loaders and analytical builders, and render one shared client context bar. Client navigation and fetches serialize the same context into links and request keys; no global mutable category or localStorage synchronization is introduced.

**Tech Stack:** TypeScript, React 19, Next-compatible Vinext server/client components, D1, Node test runner, Playwright-based in-app browser QA.

**Spec:** `docs/audits/V2.1-PAGE-LOCAL-MARKET-CONTEXT-AUDIT-2026-08-31.md` plus the user-approved “Page-local Multi-Market Context V2.1 Codex Final Execution PRD”.

## Global Constraints

- US only; do not add a marketplace selector.
- Reuse category node IDs 552856, 680335011 and 3023451 from the existing catalog.
- URL is the source of truth; do not add global mutable market state or localStorage synchronization.
- Never fall back from a missing market to a different category.
- Independent Accessories data must come from category `pressure_washer_accessories`, never filtered Pressure Washers raw rows.
- Preserve crawler, historical observations, D1 schema, current analysis semantics and V2 visual system.

---

### Task 1: Central market configuration and resolver

**Files:**
- Modify: `web/lib/market-context.ts`
- Modify: `web/lib/catalog.ts`
- Test: `web/tests/market-context.test.mjs`

**Interfaces:**
- Produces: `PageMarket`, `MARKET_CONFIG`, `PAGE_MARKET_DEFAULTS`, `resolvePageMarketContext(page, params)`, `serializeMarketContext(context, params)` and explicit accessory segment mappings.
- Consumes: existing `CategoryKey`, `ProductType`, and classification metadata.

- [ ] Add failing tests for every page default, explicit URL, invalid category, invalid segment reset, accessory subsegments, parse/serialize round trips and preservation of unrelated query parameters.
- [ ] Run `node --test tests/market-context.test.mjs` and confirm failures describe missing V2.1 interfaces.
- [ ] Implement config-driven segment validation and filtering. Map `surface_cleaner`, `pressure_washer_gun`, `hose`, and `nozzle` to their independent accessory segments; keep unknown rows in All only.
- [ ] Implement page-aware fallback and normalization without changing strict public API validation.
- [ ] Re-run the target test and commit the green resolver.

### Task 2: URL-local context controls and inherited navigation

**Files:**
- Modify: `web/app/components/MarketContext.tsx`
- Modify: `web/app/components/ShellNavigation.tsx`
- Modify: `web/app/components/SiteShell.tsx`
- Modify: `web/app/v2.css`
- Test: `web/tests/ui-accessibility.test.mjs`
- Test: `web/tests/rendered-html.test.mjs`

**Interfaces:**
- Consumes: `MARKET_CONFIG`, `resolveSegmentForCategory`, and `serializeMarketContext` from Task 1.
- Produces: accessible category and segment selects, URL replacement for normalized context, and primary/drawer links that inherit current category/segment.

- [ ] Add failing source/render tests for select labels, keyboard-native controls, context-preserving links, no localStorage and long-label responsive classes.
- [ ] Implement category change as: select category → resolve valid page default segment → update only current URL → server refresh.
- [ ] Implement segment change validation and URL update; preserve view/window/date/workspace parameters.
- [ ] Build navigation links from the current URL context and include context in drawer API requests and cache keys.
- [ ] Re-run accessibility/render tests and commit.

### Task 3: Core analytical pages

**Files:**
- Modify: `web/app/page.tsx`
- Modify: `web/app/market/page.tsx`
- Modify: `web/app/products/page.tsx`
- Modify: `web/app/products/ProductBrowser.tsx`
- Modify: `web/app/brands/page.tsx`
- Modify: `web/app/insights/page.tsx`
- Modify: `web/lib/ui-intelligence.ts`
- Test: `web/tests/ui-intelligence.test.mjs`
- Test: `web/tests/rendered-html.test.mjs`

**Interfaces:**
- Consumes: resolved `MarketContext` and existing dashboard rows/metadata.
- Produces: context-isolated Overview KPIs/signals/brands, Market views/windows, Products lists/type filters, Brands aggregation, and Data Status metrics.

- [ ] Add failing unit/integration fixtures for Pressure Washers / Machines, Sump Pumps / All, independent Accessories / All and a filtered accessory segment.
- [ ] Require every analytical builder call to receive the explicit current context; remove implicit page reliance on the Machines default.
- [ ] Normalize invalid URLs before rendering and preserve `view`/`window` during context changes.
- [ ] Add dynamic Product Type filters driven by available segment config, with product detail links carrying context.
- [ ] Verify missing category data produces an honest empty state and never another category’s metrics.
- [ ] Re-run target tests and commit.

### Task 4: Rankings raw-versus-analytical behavior

**Files:**
- Modify: `web/app/rankings/page.tsx`
- Modify: `web/app/rankings/RankingExplorer.tsx`
- Modify: `web/app/api/public/rankings/route.ts` only if its response contract needs selected segment metadata
- Test: `web/tests/public-data-routes.test.mjs`
- Test: `web/tests/rendered-html.test.mjs`

**Interfaces:**
- Consumes: selected category’s independent raw row and optional segment filter.
- Produces: one selected market ranking; Pressure Washers / All is untouched raw Top30, Machines excludes accessory types, independent Accessories always uses node 3023451.

- [ ] Add failing tests proving all three source boundaries and all-vs-machines behavior.
- [ ] Replace the global three-group explorer with the resolved page context while retaining existing dense table UI.
- [ ] Carry context into product details and back navigation.
- [ ] Re-run route/render tests and commit.

### Task 5: Reports and Alerts context

**Files:**
- Modify: `web/app/reports/page.tsx`
- Modify: `web/app/reports/ReportsArchive.tsx`
- Modify: `web/app/analysis/page.tsx`
- Modify: `web/app/analysis/AnalysisCenter.tsx`
- Modify: `web/app/analysis/SellerIntelligenceCenter.tsx`
- Modify: `web/app/api/public/reports/route.ts`
- Test: `web/tests/reports-view.test.mjs`
- Test: `web/tests/rendered-html.test.mjs`
- Test: `web/tests/seller-intelligence-public-routes.test.mjs`

**Interfaces:**
- Consumes: URL category/segment plus existing immutable report category keys.
- Produces: category-filtered archives, market-labelled report/alert links, segment-preserving product links and independent client request keys.

- [ ] Add failing tests for report filtering and category-isolated Alerts, including Sump Pumps and independent Accessories.
- [ ] Add the shared context bar to Reports and seller intelligence workspaces.
- [ ] Filter report lists by category and include category/segment in all report and alert navigation without changing immutable report keys.
- [ ] Ensure client effects depend on serialized context so old responses cannot pollute the new selection.
- [ ] Re-run target tests and commit.

### Task 6: Full isolation and browser QA

**Files:**
- Modify: `web/tests/rendered-html.test.mjs`
- Modify: `web/tests/public-data-routes.test.mjs`
- Create: `docs/audits/V2.1-MULTI-MARKET-SCREENSHOT-QA-2026-08-31.md`
- Create: `docs/screenshots/v2-1-multi-market/*`

**Interfaces:**
- Verifies every interface produced in Tasks 1–5.

- [ ] Add integration tests for inherited navigation, page-local divergence, invalid URL normalization, deep-link refresh, Sump missing-data isolation and accessory node provenance.
- [ ] Run target Node suites, then full `pnpm test` and `pnpm lint`.
- [ ] Start the local production-compatible server and test refresh, back, forward, deep links and three independent tabs.
- [ ] Capture Overview for all three markets plus Products long-label and Rankings at 1366×768 and 1440×900; check mobile overflow and keyboard focus.
- [ ] Record exact observations and any non-blocking limitations in the QA document.
- [ ] Commit QA artifacts.

### Task 7: Final review, build and publish

**Files:**
- Review: all branch changes
- Reuse: `web/.openai/hosting.json`

**Interfaces:**
- Produces: reviewed, reproducibly built and publicly deployed V2.1.

- [ ] Run `git diff --check`, fresh full tests, lint and production build from the final commit candidate.
- [ ] Perform a requirements self-review against PRD sections 90–126 and fix any gap with a failing regression test first.
- [ ] Request an independent code review, verify every finding and address only evidence-backed issues.
- [ ] Commit the final reviewed source, push the exact Sites source state, package the successful build and deploy to the existing public URL.
- [ ] Re-check production pages/API for all three contexts and write the required Multi-Market Context Implementation Summary.

