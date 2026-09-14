# Amazon BS Market Radar V2.0 Visual UI/UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将现有网站渐进升级为以市场信号为中心、保留数据证据边界的暗色 Amazon Market Intelligence SaaS。

**Architecture:** 在现有 Vinext/React 路由与数据加载上增加纯 UI Intelligence View Model 和共享组件；页面只消费现有排名比较、历史 Observation 与 Product Metadata。全站样式迁移到统一暗色 Token，不引入 UI Framework 或数据库变化。

**Tech Stack:** React 19、TypeScript、Vinext/Vite、Cloudflare Sites、Node `node:test`、原生 CSS。

**Spec:** `docs/superpowers/specs/2026-08-30-v2-visual-ui-ux-design.md`

## Global Constraints

- 保留现有技术栈、路由、API、分析口径、爬虫和历史数据。
- 不新增大型 UI/Chart Framework，不使用假数据，不创建无定义 Market Score。
- 主 UI 中文；ASIN、Top10、Top30、Review、Price 可保留行业术语。
- Dark Theme；单一蓝色 Primary Accent；绿色上涨、红色下降/High、Amber Watch、Purple Entry、Gray Neutral。
- Desktop First；强制验证 1366×768、1440×900、1920×1080；移动端不得严重横向溢出。
- 每个生产行为先写失败测试并观察 RED，再写最小实现。

---

### Task 1: UI Intelligence View Model

**Files:**
- Create: `web/lib/ui-intelligence.ts`
- Modify: `web/lib/live-dashboard-data.ts`
- Create: `web/tests/ui-intelligence.test.mjs`
- Modify: `web/package.json`

**Interfaces:**
- Consumes: `DashboardView`, `Observation`, `ProductMetadata`, existing `comparison` results.
- Produces: `formatCompactNumber`, `formatMarketDate`, `compactProductTitle`, `buildMarketSignals`, `buildMarketState`, `buildBrandMovement`, `buildProductRows`.

- [ ] **Step 1: Write failing unit tests**

```js
test("promotes verified rank facts into ordered high watch and entry signals", () => {
  const signals = buildMarketSignals(fixture);
  assert.deepEqual(signals.map(({ level, kind, asin }) => [level, kind, asin]), [
    ["high", "rank_surge", "B000000001"],
    ["watch", "rank_drop", "B000000002"],
    ["entry", "top30_entry", "B000000003"],
  ]);
});

test("counts only verified brand seats and preserves unknown", () => {
  assert.deepEqual(buildBrandMovement(fixture).slice(0, 2), [
    { brand: "Westinghouse", previousSeats: 1, currentSeats: 2, delta: 1 },
    { brand: "MZK", previousSeats: 0, currentSeats: 1, delta: 1 },
  ]);
});
```

- [ ] **Step 2: Run the new test and verify RED**

Run: bundled Node with `node --test tests/ui-intelligence.test.mjs` from `web`.  
Expected: FAIL because `ui-intelligence.ts` does not exist.

- [ ] **Step 3: Implement minimal pure transformations and metadata loading**

```ts
export function formatCompactNumber(value: number | null) {
  if (value === null) return "—";
  return Intl.NumberFormat("en-US", { notation: value >= 1000 ? "compact" : "standard", maximumFractionDigits: 1 }).format(value);
}
```

Use existing mover thresholds (`>=20` high, `>=10` watch), current/previous ASIN set difference for entries, and verified normalized brand only. Add `productMetadata` to `DashboardView`; fallback is `[]`.

- [ ] **Step 4: Run focused tests and existing data tests**

Run: `node --test tests/ui-intelligence.test.mjs tests/live-dashboard-data.test.mjs tests/analytics.test.mjs`.  
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add web/lib/ui-intelligence.ts web/lib/live-dashboard-data.ts web/tests/ui-intelligence.test.mjs web/package.json
git commit -m "feat: add market intelligence view models"
```

### Task 2: Design Foundation and Shared Components

**Files:**
- Modify: `web/app/globals.css`
- Modify: `web/app/enhancements.css`
- Modify: `web/app/components/PageHeader.tsx`
- Modify: `web/app/components/QualityBadge.tsx`
- Create: `web/app/components/MarketContext.tsx`
- Create: `web/app/components/MetricCard.tsx`
- Create: `web/app/components/RankDisplay.tsx`
- Create: `web/app/components/ProductIdentity.tsx`
- Create: `web/app/components/SignalCard.tsx`
- Create: `web/app/components/EmptyState.tsx`
- Create: `web/app/components/Tooltip.tsx`
- Create: `web/tests/shared-ui.test.mjs`

**Interfaces:**
- Consumes: Task 1 View Models.
- Produces: stable presentation primitives used by every page.

- [ ] **Step 1: Write failing server-render tests for component semantics**

```js
test("rank and product identity expose readable non-color semantics", () => {
  const html = renderToStaticMarkup(createElement(Fragment, null,
    createElement(RankDisplay, { rank: 15, delta: 11 }),
    createElement(ProductIdentity, { asin: "B000000001", title: longTitle, productType: "electric_pressure_washer" }),
  ));
  assert.match(html, /#15/);
  assert.match(html, /↑11/);
  assert.match(html, /B000000001/);
  assert.match(html, /Electric/);
});
```

- [ ] **Step 2: Verify RED because components are absent**

- [ ] **Step 3: Implement components and tokenized dark CSS**

Define Page/Surface/Elevated/Popover, text, border, accent, semantic colors, 8px spacing, 6/8/12px radius, tabular numbers, focus-visible, reduced-motion and responsive helpers. Preserve class aliases needed by legacy pages until Task 8 cleanup.

- [ ] **Step 4: Run focused component tests and lint**

- [ ] **Step 5: Commit**

```bash
git add web/app/globals.css web/app/enhancements.css web/app/components web/tests/shared-ui.test.mjs
git commit -m "feat: establish dark market intelligence design system"
```

### Task 3: Navigation, Data Status, and Activity Drawers

**Files:**
- Modify: `web/app/components/SiteShell.tsx`
- Create: `web/app/components/SiteNavigation.tsx`
- Create: `web/app/components/DataStatusDrawer.tsx`
- Create: `web/app/components/ActivityDrawer.tsx`
- Modify: `web/tests/rendered-html.test.mjs`

**Interfaces:**
- Consumes: public overview/rankings routes and Task 1 signal builder.
- Produces: six-item navigation, active route, accessible mobile menu, Alerts and Data Status drawers.

- [ ] **Step 1: Add failing built-route assertions**

Assert six labels, accessible names `市场动态` and `数据状态`, Methodology link, no permanent large `卖家分析` top-nav block, and preserved analysis/report routes.

- [ ] **Step 2: Verify RED on current built output**

- [ ] **Step 3: Implement shell and drawers**

Use buttons with `aria-expanded`, `aria-controls`, Escape close, click backdrop close, focus-visible, `role=dialog`, and mobile menu. Drawer fetch failure renders Error State; no sensitive details.

- [ ] **Step 4: Build and run rendered route tests**

- [ ] **Step 5: Commit**

```bash
git add web/app/components web/tests/rendered-html.test.mjs
git commit -m "feat: simplify navigation and add market status drawers"
```

### Task 4: Overview Visual Baseline

**Files:**
- Modify: `web/app/page.tsx`
- Modify: `web/tests/rendered-html.test.mjs`

**Interfaces:**
- Consumes: Task 1 View Models and Task 2 components.
- Produces: compact Market Summary, four KPI, top five signals, Brand Movement and Market Structure.

- [ ] **Step 1: Add failing homepage hierarchy test**

Assert `今天需要关注`, at most five Signal Cards, Brand Movement, Market Structure, and absence of homepage `分析就绪雷达` / `历史数据质量时间轴`.

- [ ] **Step 2: Verify RED**

- [ ] **Step 3: Implement overview using real dashboard data**

Use Pressure Washers raw ranking facts with Machines analytical context disclosure; when comparison is unavailable, show an Incomplete State and no invented KPI.

- [ ] **Step 4: Build, run route tests, and open first meaningful local preview**

- [ ] **Step 5: Commit**

```bash
git add web/app/page.tsx web/tests/rendered-html.test.mjs
git commit -m "feat: make verified market signals the overview focus"
```

### Task 5: Rankings and Product Browser

**Files:**
- Modify: `web/app/rankings/page.tsx`
- Modify: `web/app/rankings/RankingExplorer.tsx`
- Modify: `web/app/products/page.tsx`
- Create: `web/app/products/ProductExplorer.tsx`
- Modify: `web/tests/rendered-html.test.mjs`

**Interfaces:**
- Consumes: Product rows and shared Rank/ProductIdentity components.
- Produces: compact ranking table and searchable/filterable Product Intelligence Browser.

- [ ] **Step 1: Add failing ranking/product route tests**

Assert combined ProductIdentity, no standalone ASIN header, Rank/7D columns, filter names All/Rising/Top10/New/Falling and links to product detail.

- [ ] **Step 2: Verify RED**

- [ ] **Step 3: Implement tables and filters**

Use 52–60px row target, Sticky Header, right-aligned numeric cells, one-line title, Placeholder thumbnail and horizontal scroll.

- [ ] **Step 4: Build and run focused plus adjacent route tests**

- [ ] **Step 5: Commit**

```bash
git add web/app/rankings web/app/products web/tests/rendered-html.test.mjs
git commit -m "feat: streamline rankings and product discovery"
```

### Task 6: Product Detail Timeline

**Files:**
- Modify: `web/app/products/[asin]/page.tsx`
- Create: `web/app/components/RankTimeline.tsx`
- Create: `web/tests/rank-timeline.test.mjs`

**Interfaces:**
- Consumes: verified product history.
- Produces: Product status header, reverse-axis Timeline and factual event markers.

- [ ] **Step 1: Write failing event derivation test**

Given literal history, assert Top10 Entry/Exit and Price/Discount events; assert no event for missing price.

- [ ] **Step 2: Verify RED**

- [ ] **Step 3: Implement timeline and compact detail header**

Render #1 at top, #30 at bottom, subtle Top10 zone, keyboard-readable point labels and event list icons.

- [ ] **Step 4: Run unit, route and accessibility-oriented HTML tests**

- [ ] **Step 5: Commit**

```bash
git add web/app/products/[asin]/page.tsx web/app/components/RankTimeline.tsx web/tests/rank-timeline.test.mjs
git commit -m "feat: focus product detail on rank history events"
```

### Task 7: Market, Brand, Insights and Reports

**Files:**
- Create: `web/app/market/page.tsx`
- Create: `web/app/brands/page.tsx`
- Modify: `web/app/insights/page.tsx`
- Modify: `web/app/analysis/page.tsx`
- Modify: `web/app/analysis/AnalysisCenter.tsx`
- Modify: `web/app/analysis/SellerIntelligenceCenter.tsx`
- Modify: `web/app/reports/page.tsx`
- Modify: `web/app/reports/ReportsArchive.tsx`
- Modify: `web/app/methodology/page.tsx`
- Modify: `web/tests/rendered-html.test.mjs`

**Interfaces:**
- Consumes: Market State, Brand Movement, shared cards and states.
- Produces: Market Intelligence, Brand Presence/Table and consistent insight/report surfaces.

- [ ] **Step 1: Add failing route tests**

Assert `/market` and `/brands` render, Insights does not lead with readiness matrices, Methodology retains evidence definitions, Analysis/Reports retain all existing workspaces and download behavior.

- [ ] **Step 2: Verify RED**

- [ ] **Step 3: Implement pages without changing contracts**

Brand Presence is ASIN seat count, never sales share. Market State uses named Low/Medium/High/Stable values and visible definitions. Move readiness content to Data Status/Methodology links.

- [ ] **Step 4: Build and run all public route tests**

- [ ] **Step 5: Commit**

```bash
git add web/app/market web/app/brands web/app/insights web/app/analysis web/app/reports web/app/methodology web/tests/rendered-html.test.mjs
git commit -m "feat: align market brand insight and report workspaces"
```

### Task 8: Cleanup, Responsive and Accessibility

**Files:**
- Modify: `web/app/globals.css`
- Modify: `web/app/enhancements.css`
- Modify: affected components from Tasks 2–7
- Create: `web/tests/ui-accessibility.test.mjs`

**Interfaces:**
- Consumes: all V2 components/pages.
- Produces: consistent final system with no duplicate legacy presentation paths.

- [ ] **Step 1: Add failing behavior checks for Drawer names, focus semantics, state roles and table wrappers**

- [ ] **Step 2: Verify RED**

- [ ] **Step 3: Remove dead CSS and complete breakpoints**

Preserve compatibility aliases only when a live page still consumes them. Add `prefers-reduced-motion`, 44px mobile hit targets, no page-level overflow, drawer max width and table overflow protection.

- [ ] **Step 4: Run full Web tests, production build and lint**

- [ ] **Step 5: Commit**

```bash
git add web/app web/tests web/package.json
git commit -m "refactor: complete responsive accessible UI migration"
```

### Task 9: Screenshot QA and Sites Release

**Files:**
- Create: `docs/audits/V2-UI-SCREENSHOT-QA-2026-08-30.md`
- Modify only files with verified visual defects.

**Interfaces:**
- Consumes: production build and local preview.
- Produces: QA evidence, final verified build and deployed Sites version.

- [ ] **Step 1: Start the existing development server and verify one non-browser HTTP response**

- [ ] **Step 2: Capture Overview, Rankings, Products, Market and Brands at 1366×768, 1440×900 and 1920×1080**

Record viewport, document width, overflow, first-screen headings, table width and visible first Signal.

- [ ] **Step 3: Verify mobile 390×844 navigation, drawers, card stacking and table scroll**

- [ ] **Step 4: Fix only observed defects with TDD/visual recheck, then rerun full tests/build/lint**

- [ ] **Step 5: Use Sites hosting workflow to deploy the exact reviewed web source and verify public routes**

- [ ] **Step 6: Commit QA record**

```bash
git add docs/audits/V2-UI-SCREENSHOT-QA-2026-08-30.md web
git commit -m "docs: record V2 visual release acceptance"
```

## Plan Self-Review

- Spec coverage: all PRD P0/P1 and the required Phase 1–11 surfaces map to Tasks 1–9; P2 motion remains minimal and contained in CSS.
- No placeholders: every task has exact files, interfaces, RED/GREEN verification and commit boundary.
- Type consistency: all pages consume Task 1 View Models and Task 2 shared components; Drawers use existing public APIs; no later task depends on an undefined database or route contract.
