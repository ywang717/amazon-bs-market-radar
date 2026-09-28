# Amazon BS Market Radar V3.0 Phase One Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 V3.0 第一阶段已确认的竞争观察席位、错误分类、分群归档、报告筛选、价格信号和原始榜单说明问题，并用自动化测试与真实浏览器回归证明线上行为正确。

**Architecture:** 保持现有 Next/Vinext、D1、R2 和报告同步边界。把分群上下文作为报告元数据和查询条件的一部分，使用真实过滤后的 observations 计算席位；将底层失败映射为稳定错误类别；在 UI 层保留 URL 上下文并仅展示经验证的数据。历史无法可靠回溯分群的记录继续可读，但标记为未知原始榜单口径。

**Tech Stack:** TypeScript, React Server/Client Components, Cloudflare D1/SQLite, Drizzle schema/migrations, Node `node:test`, Vitest-compatible route harness, Vinext, Playwright/CUA browser validation.

**Spec:** `docs/superpowers/specs/2026-09-24-v3-phase1-design.md`

## Global Constraints

- 保留现有 Pacific Time、America/Los_Angeles 日期派生和历史市场日，不重写历史快照。
- 保留现有 D1、R2、PDF 对象和同步 API 兼容性；迁移只允许一次性、非破坏性的 nullable 字段新增；迁移管理器负责只执行一次。
- 分群分析只使用真实 observations，不补造排名、不把缺失席位填成假数据。
- 旧报告缺少可靠分群信息时必须保持未知，不得回填为 `machines`。
- 公开错误响应不得泄露数据库、文件路径、密钥、堆栈或内部异常文本。
- 第二阶段 Watchlist、对比、聚合、自定义预警和研究清单不在本计划范围内。
- 每个任务遵循 RED → GREEN → REFACTOR，并在任务结束提交独立 commit。

## Review Focus

- 当前 Top10 与基线 Top10 席位数不同：entries/exits 必须按实际集合守恒；测试归入 Task 1。
- 旧卖家情报报告缺失新字段：读取必须仍可验证且保持未知口径；测试归入 Task 3。
- D1/生成/合同/阈值失败：API 和页面必须给出不同稳定提示且不显示内部细节；测试归入 Task 2。
- `kind=all|daily|weekly` 与 category/segment/date 同时存在：筛选和 URL 必须保持一致；测试归入 Task 4。
- 价格只差 `$0.01`：展示实际差额、百分比小于 0.1%，优先级只能是 activity；测试归入 Task 5。

---

### Task 1: Variable Top10 Competition Contract

**Files:**
- Modify: `web/lib/seller-intelligence-contract.ts` (strategy facts types and validation)
- Modify: `web/lib/seller-intelligence.ts` (strategy facts generation)
- Test: `web/tests/seller-intelligence-contract.test.mjs`
- Test: `web/tests/live-analysis.test.mjs`

**Interfaces:**
- Consumes: filtered `Observation[]` from `buildLiveSellerIntelligence` and existing weekly report schema.
- Produces: `SellerStrategyFacts.rankingConcentration.top10Slots`, plus `topStability.currentTop10Slots` and `topStability.baselineTop10Slots`; old reports with missing slot fields remain accepted as unknown legacy facts.

- [ ] **Step 1: Write failing tests** for a current set of 7 slots, a baseline set of 5 slots, and a full 10-slot set. Assert strategy validation accepts valid variable counts, rejects non-conserving retained/entry/exit values, and generated entries/exits equal set differences without synthetic ranks.
- [ ] **Step 2: Run focused tests** with `node --test web/tests/seller-intelligence-contract.test.mjs web/tests/live-analysis.test.mjs`; confirm the new variable-slot cases fail against the hard-coded `10` contract.
- [ ] **Step 3: Implement the minimal type/generator/validator changes** in the two library files. Validate slots as integers `0..10`; require current/baseline conservation only when the new fields are present; permit legacy stability objects without those fields as unknown legacy data; preserve raw ranks and filtered observations.
- [ ] **Step 4: Run the focused tests again** and confirm all pass, then run the existing seller-intelligence contract suite to catch regressions in complete 10-slot reports.
- [ ] **Step 5: Commit** `fix: support variable competition top ten slots`.

### Task 2: Seller Intelligence Error Classification

**Files:**
- Create: `web/lib/seller-intelligence-errors.ts` (stable error categories, public messages, mapper)
- Modify: `web/app/api/public/seller-intelligence/live/route.ts`
- Modify: `web/app/api/public/seller-intelligence/route.ts`
- Modify: `web/app/analysis/SellerIntelligenceCenter.tsx`
- Test: `web/tests/seller-intelligence-public-routes.test.mjs`
- Test: `web/tests/rendered-html.test.mjs`

**Interfaces:**
- Consumes: thrown D1 errors, empty/threshold results, contract validation failures, and report generation errors.
- Produces: `{ error: { code: "database"|"no_data"|"report_generation"|"contract"|"threshold", message: string } }` with safe status codes; list route never converts a failed read into a successful empty archive.

- [ ] **Step 1: Add failing route/page tests** that force database failure, no data, contract failure, generation failure, and threshold insufficiency; assert distinct codes/messages and no internal error text, paths, secrets, or stack traces.
- [ ] **Step 2: Run the focused route/render tests** and confirm current broad catches either return `{reports:[]}`, `{error:"unavailable"}`, or the same empty UI for multiple causes.
- [ ] **Step 3: Implement the mapper and route/page handling**. Preserve existing success JSON and cache headers; use status 503 for infrastructure/generation failures, 200 with a no-data/threshold state for valid empty/insufficient data, and map invalid contracts to a safe contract response. Log only server-side through existing logger conventions.
- [ ] **Step 4: Run focused tests, then the seller-intelligence route and render suites**; verify empty and error states remain accessible and localized.
- [ ] **Step 5: Commit** `fix: distinguish seller intelligence failure states`.

### Task 3: Segment-Aware Report Metadata and Migration

**Files:**
- Modify: `web/db/schema.ts` (nullable `segmentKey` on report tables)
- Create: `web/drizzle/0006_add_report_segment_key.sql` (forward-only nullable columns/indexes)
- Modify: `web/lib/reports-view.ts`, `web/lib/scoped-report-sync.ts`, and seller-intelligence list/read helpers
- Modify: `web/app/api/sync/v1/analysis-reports/route.ts`, `web/app/api/sync/v1/seller-intelligence/route.ts`, and public report routes
- Modify: `web/app/reports/ReportsArchive.tsx` and `web/app/analysis/SellerIntelligenceCenter.tsx`
- Test: `web/tests/migration-integrity.test.mjs`
- Test: `web/tests/analysis-sync-route.test.mjs`
- Test: `web/tests/seller-intelligence-public-routes.test.mjs`
- Test: `web/tests/reports-view.test.mjs`

**Interfaces:**
- Consumes: `MarketContext { marketplace, category, segment }` and current report bundle metadata.
- Produces: new rows keyed/queryable by marketplace/category/segment/marketDate; legacy rows expose `segmentKey: null` and display “原始榜单历史报告” without rewriting object keys or PDFs.

- [ ] **Step 1: Write failing migration/sync/query tests** for new `segmentKey`, segment-preserving list/detail requests, legacy null rows, and no false `machines` labeling.
- [ ] **Step 2: Run focused migration/sync/public tests** and confirm current schema/queries lose segment context or return all category rows.
- [ ] **Step 3: Add the nullable migration and schema/query plumbing**. Keep old insert payloads valid, include segment when present in new payloads, include segment in safe metadata validation, and filter public lists by segment only when supplied; preserve old PDF/R2 keys and null legacy values.
- [ ] **Step 4: Run migration, sync, route, and view tests**, then inspect generated SQL for non-destructive `ALTER TABLE ... ADD COLUMN` behavior.
- [ ] **Step 5: Commit** `fix: persist segment context for reports`.

### Task 4: Real Report-Type Archive Filter

**Files:**
- Modify: `web/app/reports/page.tsx`
- Modify: `web/app/reports/ReportsArchive.tsx`
- Modify: `web/app/api/public/reports/route.ts`
- Modify: `web/lib/reports-view.ts`
- Test: `web/tests/reports-view.test.mjs`
- Test: `web/tests/rendered-html.test.mjs`
- Test: `web/tests/ui-accessibility.test.mjs`

**Interfaces:**
- Consumes: `kind=all|daily|weekly` plus existing market context query parameters.
- Produces: selected filter state in URL and UI; API returns only the requested kind; `全部报告⌄` is an actual control with keyboard semantics and correct empty-state text.

- [ ] **Step 1: Write failing view/API/UI tests** for all/daily/weekly, retained category/segment/date, selected state, and zero-results labels.
- [ ] **Step 2: Run focused tests** and confirm the current anchor only jumps to `#report-archive` and API ignores `kind`.
- [ ] **Step 3: Implement query parsing/filtering and accessible controls** using links or a native select, preserving all existing context parameters and download URLs.
- [ ] **Step 4: Run focused route/render/accessibility tests** and verify no report record is mislabeled or duplicated.
- [ ] **Step 5: Commit** `fix: make report type filter functional`.

### Task 5: Price Precision and Raw Top30 Copy

**Files:**
- Modify: `web/lib/ui-intelligence.ts` and `web/app/components/SignalCard.tsx` (precise price delta and activity threshold)
- Modify: `web/app/analysis/SellerIntelligenceCenter.tsx` or shared analysis copy (raw Top30 title/explanation)
- Test: `web/tests/ui-intelligence.test.mjs`
- Test: `web/tests/seller-intelligence-contract.test.mjs`
- Test: `web/tests/rendered-html.test.mjs`

**Interfaces:**
- Consumes: raw numeric prices and generated price-change signals.
- Produces: `$349.99 → $349.98 · 差额 $0.01 · 变化幅度小于 0.1%` style wording and `activity` priority for changes under 0.1%; raw module title exactly `Amazon 原始 Top30 商品结构` with explanation that it ignores segment filtering.

- [ ] **Step 1: Write failing unit/render tests** for a one-cent change and exact title/disclosure copy.
- [ ] **Step 2: Run focused tests** and confirm current rounding yields `0%` or misleading high-level wording and the old raw module title remains.
- [ ] **Step 3: Implement precise formatting and the ordinary-signal guard**, without changing stored numeric values or other thresholds; update only the raw Top30 module copy.
- [ ] **Step 4: Run focused UI/contract/render tests** and ensure existing larger price moves retain current behavior.
- [ ] **Step 5: Commit** `fix: clarify small price changes and raw top thirty`.

### Task 6: Full Verification, Browser Regression, and Release

**Files:**
- Modify: `docs/superpowers/plans/2026-09-28-v3-phase1-implementation.md` only for checked progress if needed
- Test: all existing `web/tests/*.test.mjs`

**Interfaces:**
- Consumes: completed Tasks 1–5 and existing deployment workflow.
- Produces: passing test/lint/build evidence, real browser interaction evidence, deployed site retaining D1/R2/Pacific behavior, and a pushed branch commit set.

- [ ] **Step 1: Run focused suites and then `pnpm --dir web test`**; save long output under the plan workspace and inspect failures.
- [ ] **Step 2: Run `pnpm --dir web lint` and production build**; fix only confirmed regressions with RED→GREEN tests.
- [ ] **Step 3: Deploy using the repository’s Sites workflow without destructive database operations**; verify deployment reachability and version.
- [ ] **Step 4: Use the cloud browser to open homepage, market, rankings, products, details, brands, reports, daily/weekly analysis, seller alerts, competition strategy, archive, and methodology**; click navigation, market/date/segment/filter/expand/detail/download controls; verify URL/content, Console, Network, empty/error states, segment Top10 behavior, report kind filtering, and raw Top30 copy.
- [ ] **Step 5: Re-run the browser checks after any deployed fix, then push the validated branch and record commit/deployment IDs.**
