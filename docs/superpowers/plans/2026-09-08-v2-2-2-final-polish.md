# Amazon BS Market Radar V2.2.2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成 V2.2.2 的时间线、事件、市场控件、分类、市场结构、品牌和报告收口，同时保持 Amazon Raw Ranking 不变。

**Architecture:** 继续复用 `web/lib/ui-intelligence.ts` 作为唯一展示分析层，复用 `config/v2-product-classification.json` 和 `src/BestSellersDataSemantics.psm1` 作为唯一分类链路。页面只消费共享结果，不自行创建事件、分类或格式化规则。

**Tech Stack:** TypeScript、React/Vinext、Node test runner、PowerShell/Pester、现有 CSS。

**Spec:** `C:/Users/ASUS/.codex/attachments/379fa189-c090-40cd-995f-e378e35593a9/pasted-text.txt`

## Global Constraints

- 只局部读取和修改直接相关文件，不重写 crawler、数据库、导航、Design System 或 Raw Ranking。
- 先完成 Phase 1 及相关测试，再进入 Phase 2。
- 新增行为使用 TDD；Phase 结束后再运行对应测试，最终运行 lint、test、build。
- 不创建第二套 Signal、Classification、Event 或 Formatter。

---

### Task 1: Phase 1 时间线与 Canonical Event

**Files:**
- Modify: `web/lib/ui-intelligence.ts`
- Modify: `web/app/products/[asin]/page.tsx`
- Modify: `web/app/components/TimelineEvent.tsx`
- Modify: `web/app/v2.css`
- Test: `web/tests/ui-intelligence.test.mjs`
- Test: `web/tests/ui-accessibility.test.mjs`

**Interfaces:**
- Produces: `resolveCanonicalEventState(input): "first_seen" | "new_entry" | "re_entry" | "exit" | "stable"`
- Produces: `buildProductRankTimeline(history, asin)`，返回按真实 `marketDate` 排序、包含空档、日期比例坐标和关键事件的结构。

- [x] **Step 1: Write failing tests**

```js
assert.deepEqual(buildProductRankTimeline(history, asin).points.map(({ marketDate, rank }) => ({ marketDate, rank })), expected);
assert.deepEqual(states, ["first_seen", "exit", "re_entry"]);
```

- [x] **Step 2: Verify RED**

Run: `pnpm exec node --test tests/ui-intelligence.test.mjs tests/ui-accessibility.test.mjs`
Expected: FAIL because timeline/event APIs and SVG/date labels are absent.

- [x] **Step 3: Implement minimal shared timeline/event logic**

Use valid market-day history only, timestamp-derived X positions, `null` rank gaps, reversed rank Y, sampled date labels, and shared event-state resolution. Product Detail must consume this result rather than infer entry/re-entry/exit locally.

- [x] **Step 4: Verify GREEN**

Run: `pnpm exec node --test tests/ui-intelligence.test.mjs tests/ui-accessibility.test.mjs tests/live-dashboard-data.test.mjs tests/valid-market-days.test.mjs`
Expected: PASS.

### Task 2: Phase 1 一致性与异常保护

**Files:**
- Modify: `web/lib/ui-intelligence.ts`
- Modify: `web/app/market/page.tsx`
- Modify: `web/app/products/[asin]/page.tsx`
- Modify: `web/app/components/SignalCard.tsx`
- Modify: `web/app/rankings/RankingExplorer.tsx`
- Modify: `web/app/products/ProductBrowser.tsx`
- Modify: `web/app/methodology/page.tsx`
- Test: `web/tests/ui-intelligence.test.mjs`
- Test: `web/tests/ui-accessibility.test.mjs`

**Interfaces:**
- Produces: `review_anomaly` signal from centralized abnormal-drop thresholds.
- Reuses: `formatDeal`, `RankDelta`, shared product metadata and Signal Engine.

- [x] **Step 1: Write failing tests for invalid windows, abnormal review drop, terminology and hidden incomplete UI**
- [x] **Step 2: Verify RED with Phase 1 tests**
- [x] **Step 3: Show trend window only on Market Overview; label Movers as 1D; remove Product Detail “参数待补充”; rename “在榜天数” to “有效在榜日”; display verification status separately from evidence sufficiency**
- [x] **Step 4: Verify GREEN with Phase 1 tests**

### Task 3: Phase 2 分类与商品结构

**Files:**
- Modify: `config/v2-product-classification.json`
- Modify: `config/v2-product-attributes.json`
- Modify: `config/category-registry.json`
- Modify: `src/BestSellersDataSemantics.psm1`
- Modify: `web/lib/product-metadata.ts`
- Modify: `web/lib/sync-contract.ts`
- Modify: `web/app/components/ProductIdentity.tsx`
- Modify: generated category-registry artifacts via existing generator
- Test: `tests/BestSellersDataSemantics.Tests.ps1`
- Test: `web/tests/sync-contract.test.mjs`
- Test: `web/tests/category-registry.test.mjs`

**Interfaces:**
- Extends existing `ProductType` with `foam_cannon`, `adapter_connector`, `extension_wand`, and `sewer_jetter`.
- Keeps machine types independent from Amazon category and keeps unknown fail-closed.

- [x] **Step 1: Add failing fixtures for new accessory types and machine-inside-accessories**
- [x] **Step 2: Verify RED in targeted Pester and Node tests**
- [x] **Step 3: Extend central configuration/contracts/labels and regenerate existing registry artifacts**
- [x] **Step 4: Verify GREEN in targeted classification tests**

### Task 4: Phase 2 市场情报、品牌与报告

**Files:**
- Modify: `web/lib/ui-intelligence.ts`
- Modify: `web/app/market/page.tsx`
- Modify: `web/app/brands/page.tsx`
- Modify: `web/app/reports/page.tsx`
- Modify: `web/app/methodology/page.tsx`
- Test: `web/tests/ui-intelligence.test.mjs`
- Test: `web/tests/ui-accessibility.test.mjs`

**Interfaces:**
- Produces: `buildProductTypeStructure(history, metadata, windowDays)`.
- Produces: `buildWorthStudyingProducts(rows)` with centralized, explainable thresholds.
- Produces: `buildReviewCompetition(observations)`.

- [x] **Step 1: Add failing tests for structure seat totals, trend insufficiency, worth-studying exclusions and review medians**
- [x] **Step 2: Verify RED**
- [x] **Step 3: Implement helpers in the existing intelligence module and render them in Market/Reports; add explicit 1D and 7D brand columns; collapse Report Activity and cap Watch at five**
- [x] **Step 4: Verify GREEN with Phase 2 tests**

### Task 5: QA and completion

**Files:**
- Modify only files required by observed QA defects.

- [x] **Step 1: Run Phase 1 and Phase 2 targeted suites**
- [x] **Step 2: Run Browser QA at `pressure_washer_accessories`, `2026-09-06` for Overview, Market, Products, Product Detail, Brands, Rankings, Reports and Methodology**
- [x] **Step 3: Capture 1440×900 screenshots for Overview, Market, Product Detail and Reports; add 1366×768 only if a responsive defect is found**
- [x] **Step 4: Run `pnpm lint`, `pnpm test`, and `pnpm build`**
- [x] **Step 5: Inspect `git diff --check` and final status, then commit only V2.2.2 source/test changes**
