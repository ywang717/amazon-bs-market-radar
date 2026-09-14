# Amazon BS 市场雷达全站动态数据实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让首页、榜单、洞察、产品详情和公开 API 在每日同步后自动读取 Sites D1 的最新可验证数据，并在 D1 整体不可用时安全回退到已验证种子快照。

**Architecture:** 将 D1 查询与页面视图组装拆成两个边界：`dashboard-store.ts` 只执行参数化数据读取，`live-dashboard-data.ts` 只执行质量校验、历史比较、证据计算和整体回退。页面与公开 API 统一调用异步服务，不再各自查询 D1 或默认读取静态种子数据。

**Tech Stack:** TypeScript 5.9、React 19 Server Components、vinext、Cloudflare D1、Node `node:test`、Sites。

## Global Constraints

- 保持网站公开、只读，不新增登录、远程任务控制、邮件控制或本机访问能力。
- 不修改现有 D1/R2 逻辑绑定、同步鉴权协议、本机日报/周报任务或数据库结构。
- 当前日与比较日的同一榜单均为完整 Top 30 时，才计算日度排名变化。
- 缺失价格、星级和评论数保持 `null`；覆盖率低于 80% 时对应关联分析暂停。
- 不生成机会评分、因果判断、缺失值插值或推测字段。
- D1 单个榜单不完整时保留真实质量状态，不使用种子数据局部补齐。
- D1 整体不可用或为空时才整体回退到已验证种子数据。
- 公开响应不得泄露邮箱、授权码、本机路径、计划任务名称、绑定名或内部错误。
- 保持现有视觉布局；只把硬编码日期、数量和结论替换为动态值。
- 不新增 npm 依赖，不生成 D1 migration。

---

## 文件结构

- Create `web/lib/dashboard-store.ts`：定义可测试的数据存储接口、D1 行类型与 D1 参数化查询实现。
- Create `web/lib/live-dashboard-data.ts`：组装动态 Dashboard、产品历史、证据与整体回退。
- Create `web/tests/live-dashboard-data.test.mjs`：使用内存 Store 验证动态数据、门禁和回退行为。
- Modify `web/lib/dashboard-data.ts`：导出种子回退视图和明确的种子产品历史函数，不再被线上页面直接调用。
- Modify `web/app/page.tsx`：市场总览改为异步动态数据，移除固定日期和固定结论。
- Modify `web/app/rankings/page.tsx`：榜单页改为异步动态数据。
- Modify `web/app/insights/page.tsx`：洞察页改为异步动态数据和证据状态。
- Modify `web/app/products/[asin]/page.tsx`：产品详情读取动态历史并对不存在产品执行 404。
- Modify `web/app/api/public/overview/route.ts`：复用动态 Dashboard 服务。
- Modify `web/app/api/public/rankings/route.ts`：复用 Store 和统一回退规则。
- Modify `web/app/api/public/products/[asin]/route.ts`：复用动态产品服务并区分“D1 不可用”与“产品不存在”。
- Modify `web/tests/rendered-html.test.mjs`：注入更新市场日，验证四个数据页面不再固定在种子日期。
- Modify `web/package.json`：把新增单元测试加入 `npm test`。

---

### Task 1: 建立 D1 读取边界和动态 Dashboard 组装器

**Files:**
- Create: `web/lib/dashboard-store.ts`
- Create: `web/lib/live-dashboard-data.ts`
- Modify: `web/lib/dashboard-data.ts`
- Create: `web/tests/live-dashboard-data.test.mjs`
- Modify: `web/package.json`

**Interfaces:**
- Produces: `DashboardStore`，包含 `listSnapshots()`、`listCategoryDays()`、`listObservations()` 和 `listProductHistory(asin)`。
- Produces: `createD1DashboardStore(db: D1Database): DashboardStore`。
- Produces: `loadLiveDashboard(options?: { store?: DashboardStore }): Promise<DashboardView>`。
- Produces: `loadLiveProduct(asin: string, options?: { store?: DashboardStore }): Promise<{ status: "found"; product: ProductView } | { status: "not_found" }>`。
- Produces: `DashboardView.source`，值为 `"d1" | "seed_fallback"`，只用于服务端控制，不展示内部错误。

- [ ] **Step 1: 写“最新 D1 数据覆盖种子日期”的失败测试**

在 `web/tests/live-dashboard-data.test.mjs` 创建一个完整的内存 Store。使用两个市场日 `2026-08-12` 和 `2026-08-13`，每个市场日为三个分类各生成 30 条连续排名，并断言：

```js
test("uses the newest complete D1 market day instead of the seed snapshot", async () => {
  const data = await loadLiveDashboard({ store: completeStore(["2026-08-12", "2026-08-13"]) });
  assert.equal(data.source, "d1");
  assert.equal(data.marketDate, "2026-08-13");
  assert.equal(data.totalObservations, 90);
  assert.equal(data.completeCategories, 3);
  assert.equal(data.completeMarketDays, 2);
  assert.equal(data.categoryRows.every((row) => row.comparison.ready), true);
});
```

- [ ] **Step 2: 运行测试并确认因模块不存在而失败**

Run: `cd web; node --test tests/live-dashboard-data.test.mjs`

Expected: FAIL，错误包含 `ERR_MODULE_NOT_FOUND` 或 `loadLiveDashboard is not defined`。

- [ ] **Step 3: 实现最小 Store 接口和 D1 查询**

在 `web/lib/dashboard-store.ts` 定义行结构与接口：

```ts
export type SnapshotRow = { market_date: string; observed_at: string; complete_category_count: number };
export type CategoryDayRow = { market_date: string; category_key: CategoryKey; observation_count: number; complete: number; missing_ranks_json: string };
export type ObservationRow = Observation & { market_date: string; category_key: CategoryKey };

export interface DashboardStore {
  listSnapshots(): Promise<SnapshotRow[]>;
  listCategoryDays(): Promise<CategoryDayRow[]>;
  listObservations(): Promise<ObservationRow[]>;
  listProductHistory(asin: string): Promise<ObservationRow[]>;
}
```

`createD1DashboardStore` 的四个查询分别使用：

```sql
SELECT market_date, observed_at, complete_category_count FROM snapshots ORDER BY market_date;
SELECT market_date, category_key, observation_count, complete, missing_ranks_json FROM category_days ORDER BY market_date, category_key;
SELECT market_date, category_key, rank, asin, title, url, price, rating, reviews FROM observations ORDER BY market_date, category_key, rank;
SELECT market_date, category_key, rank, asin, title, url, price, rating, reviews FROM observations WHERE asin = ? ORDER BY market_date;
```

最后一个查询必须通过 `.bind(asin)` 参数化。

- [ ] **Step 4: 实现动态 Dashboard 组装**

在 `web/lib/live-dashboard-data.ts`：

1. 默认通过 `getD1()`、`ensureSchema()` 和 `createD1DashboardStore()` 获取 Store。
2. Store 为空时抛出内部 `EmptyDashboardStoreError`，由外层整体回退。
3. 按最新市场日创建三个 `categoryRows`。
4. 每个榜单的 `quality.complete` 必须同时满足实际 `validateCategory()` 和对应 `category_days.complete === 1`。
5. 为每个榜单从较早日期倒序寻找最近的完整 Top 30，并调用 `compareRankings()`；找不到时用 `compareRankings([], current)` 返回门禁状态。
6. 只有三个榜单均完整的日期计入 `completeMarketDays`。
7. `qualityHistory` 只来自 D1，不与种子日期拼接。

返回结构沿用现有页面字段并新增：

```ts
export type DashboardView = ReturnType<typeof getSeedDashboard> & {
  source: "d1" | "seed_fallback";
  previousComparableDate: string | null;
};
```

把 `getSeedDashboard()` 的返回对象增加 `source: "seed_fallback" as const` 和 `previousComparableDate`，确保回退类型一致。

- [ ] **Step 5: 运行测试确认最新 D1 数据测试通过**

Run: `cd web; node --test tests/live-dashboard-data.test.mjs`

Expected: PASS，1 test，0 failures。

- [ ] **Step 6: 写不完整榜单和整体回退的失败测试**

增加三个行为测试：

```js
test("does not compare a category when the current D1 Top 30 is incomplete", async () => {
  const store = completeStore(["2026-08-12", "2026-08-13"]);
  store.observations = store.observations.filter((row) => !(row.market_date === "2026-08-13" && row.category_key === "sump_pumps" && row.rank === 30));
  const data = await loadLiveDashboard({ store });
  const sump = data.categoryRows.find((row) => row.key === "sump_pumps");
  assert.equal(sump.quality.complete, false);
  assert.equal(sump.observations.length, 29);
  assert.equal(sump.comparison.ready, false);
});

test("falls back as one complete dataset when D1 is unavailable", async () => {
  const data = await loadLiveDashboard({ store: failingStore() });
  assert.equal(data.source, "seed_fallback");
  assert.equal(data.marketDate, "2026-08-12");
  assert.equal(data.totalObservations, 90);
});

test("does not return a seed product when D1 works but the ASIN is absent", async () => {
  const result = await loadLiveProduct("B0BVGSX46M", { store: emptyProductStoreWithSnapshots() });
  assert.deepEqual(result, { status: "not_found" });
});
```

- [ ] **Step 7: 运行测试并确认新行为先失败**

Run: `cd web; node --test tests/live-dashboard-data.test.mjs`

Expected: FAIL；失败分别指向不完整门禁、回退来源或产品不存在语义尚未实现。

- [ ] **Step 8: 实现整体回退和产品语义**

`loadLiveDashboard` 只在 Store 初始化、查询或空库错误时捕获并返回 `getSeedDashboard()`；数据读取成功后不捕获单榜单质量问题，而是保留真实数据。

`loadLiveProduct` 的分支固定为：

```ts
try {
  const store = options.store ?? await defaultStore();
  const rows = await store.listProductHistory(asin);
  if (rows.length === 0) return { status: "not_found" } as const;
  return { status: "found", product: buildProductView(rows) } as const;
} catch {
  const seedRows = getSeedProductHistory(asin);
  return seedRows.length
    ? { status: "found", product: buildProductView(seedRows) } as const
    : { status: "not_found" } as const;
}
```

`buildProductView` 返回最新观测、分类、升序历史、`bestRank`、`worstRank` 和 `daysListed`。

- [ ] **Step 9: 运行新增单元测试和现有分析测试**

Run: `cd web; node --test tests/live-dashboard-data.test.mjs tests/analytics.test.mjs`

Expected: PASS，全部测试 0 failures。

- [ ] **Step 10: 把新增测试加入默认测试命令并提交**

将 `web/package.json` 的测试前半段改为包含 `tests/live-dashboard-data.test.mjs`。

```powershell
git add web/lib/dashboard-store.ts web/lib/live-dashboard-data.ts web/lib/dashboard-data.ts web/tests/live-dashboard-data.test.mjs web/package.json
git commit -m "feat: load verified dashboard data from D1"
```

---

### Task 2: 将首页、榜单与洞察切换到动态 Dashboard

**Files:**
- Modify: `web/app/page.tsx`
- Modify: `web/app/rankings/page.tsx`
- Modify: `web/app/insights/page.tsx`
- Modify: `web/tests/rendered-html.test.mjs`

**Interfaces:**
- Consumes: `loadLiveDashboard(): Promise<DashboardView>` from Task 1。
- Produces: 三个服务器页面在每次请求中使用同一套动态数据和证据规则。

- [ ] **Step 1: 写动态页面渲染失败测试**

扩展 `render()`，允许传入一个实现 D1 `prepare/bind/all/first/batch` 最小契约的内存绑定，并在 worker 环境参数中设置 `DB`。用 `2026-08-13` 的三榜 Top 30 数据请求 `/`、`/rankings`、`/insights`：

```js
test("renders the latest D1 market day across dashboard pages", async () => {
  const env = dynamicD1Environment("2026-08-13");
  for (const path of ["/", "/rankings", "/insights"]) {
    const response = await render(path, env);
    assert.equal(response.status, 200, path);
    assert.match(await response.text(), /2026-08-13/, path);
  }
});
```

- [ ] **Step 2: 运行渲染测试并确认仍显示旧种子日期**

Run: `cd web; npm run build; node --test tests/rendered-html.test.mjs`

Expected: FAIL，三个页面至少一个不包含 `2026-08-13`。

- [ ] **Step 3: 改造三个服务器页面**

把三个默认导出组件改为 `async` 并调用：

```ts
const data = await loadLiveDashboard();
```

首页必须删除以下硬编码：

- `8 个连续完整市场日`
- `8/11 → 8/12`
- `8 月 4 日不完整`
- 固定的分析员异动数量文案

替换为：

```ts
const comparisonReady = data.categoryRows.filter((row) => row.comparison.ready).length;
const evidenceCopy = data.completeMarketDays >= 5
  ? `${data.completeMarketDays} 个完整市场日，已开放周度描述性分析`
  : `${data.completeMarketDays} 个完整市场日，暂不输出稳定周趋势`;
const comparisonWindow = data.previousComparableDate
  ? `${data.previousComparableDate} → ${data.marketDate}`
  : "暂无完整相邻比较日";
```

分析员提示从 `categoryRows[].comparison.movers` 中筛选 `absoluteMove >= 10`，没有记录时显示“当前没有满足阈值的明显排名变化”。不得生成固定产品结论。

榜单页和洞察页的日期按钮使用 `data.marketDate`；洞察证据阶梯根据 `completeMarketDays` 和字段覆盖率生成“可用/暂不下结论”状态。

- [ ] **Step 4: 运行渲染测试确认动态日期通过**

Run: `cd web; npm run build; node --test tests/rendered-html.test.mjs`

Expected: PASS；页面包含 `2026-08-13`，且不包含邮箱、本机路径或秘密字段。

- [ ] **Step 5: 运行 lint 并提交**

Run: `cd web; npm run lint`

Expected: exit 0。

```powershell
git add web/app/page.tsx web/app/rankings/page.tsx web/app/insights/page.tsx web/tests/rendered-html.test.mjs
git commit -m "feat: render dashboard pages from live data"
```

---

### Task 3: 将产品详情与公开 API 统一到动态服务

**Files:**
- Modify: `web/app/products/[asin]/page.tsx`
- Modify: `web/app/api/public/overview/route.ts`
- Modify: `web/app/api/public/rankings/route.ts`
- Modify: `web/app/api/public/products/[asin]/route.ts`
- Modify: `web/tests/rendered-html.test.mjs`
- Create: `web/tests/public-data-routes.test.mjs`
- Modify: `web/package.json`

**Interfaces:**
- Consumes: `loadLiveDashboard()`、`loadLiveProduct(asin)`、`createD1DashboardStore()` from Task 1。
- Produces: 页面和 API 对最新市场日、产品不存在与 D1 回退采用一致语义。

- [ ] **Step 1: 写产品页动态历史和 404 的失败测试**

在渲染测试中注入一个 ASIN `B123456789`，它在 `2026-08-12` 排名 12、在 `2026-08-13` 排名 4：

```js
test("renders a D1 product history and returns not found for an unknown ASIN", async () => {
  const env = dynamicD1Environment("2026-08-13");
  const found = await render("/products/B123456789", env);
  assert.equal(found.status, 200);
  const html = await found.text();
  assert.match(html, /2026-08-13/);
  assert.match(html, /#4/);
  assert.match(html, /2 个市场日/);

  const missing = await render("/products/B000000000", env);
  assert.equal(missing.status, 404);
});
```

- [ ] **Step 2: 写公开路由失败测试**

在 `web/tests/public-data-routes.test.mjs` 通过构建后的 worker 请求接口：

```js
test("public routes expose the same latest market day without internal details", async () => {
  const env = dynamicD1Environment("2026-08-13");
  for (const path of [
    "/api/public/overview",
    "/api/public/rankings?category=pressure_washers",
    "/api/public/products/B123456789",
  ]) {
    const response = await request(path, env);
    assert.equal(response.status, 200, path);
    const body = await response.text();
    assert.match(body, /2026-08-13/, path);
    assert.doesNotMatch(body, /746254487|C:\\\\Users|SYNC_SECRET|password|stack/i, path);
  }
});
```

再断言 D1 正常但未知 ASIN 的产品 API 返回 `404 { "error": "not_found" }`。

- [ ] **Step 3: 运行构建与测试确认失败**

Run: `cd web; npm run build; node --test tests/rendered-html.test.mjs tests/public-data-routes.test.mjs`

Expected: FAIL；产品页面仍使用种子回退产品，或 API 返回旧结构/旧日期。

- [ ] **Step 4: 改造产品页面**

使用 Next `notFound()`：

```ts
const { asin } = await params;
const result = await loadLiveProduct(asin);
if (result.status === "not_found") notFound();
const { current, category, history, bestRank, daysListed } = result.product;
```

市场日取 `history.at(-1)!.marketDate`，曲线和 KPI 全部使用返回的真实历史。删除 `getProduct("B0BVGSX46M")` 默认替代行为和固定 `2026-08-12`。

- [ ] **Step 5: 改造三个公开 API**

`overview` 直接返回 `await loadLiveDashboard()` 中的公开字段；移除重复 D1 查询。

`rankings`：

- 未指定日期时，从 `loadLiveDashboard()` 取最新榜单。
- 指定日期时通过 Store 参数化筛选；找不到该日返回 `404 { error: "not_found" }`。
- 非法类别继续返回 400。
- D1 整体异常时，只对未指定日期的请求回退最新种子榜单；指定日期不得伪造。

`products/[asin]` 调用 `loadLiveProduct()`；`found` 返回升序历史，`not_found` 返回 404。catch 不返回错误文本。

所有成功接口保留 `cache-control: public, max-age=300`；回退接口使用 `max-age=60`。

- [ ] **Step 6: 运行路由与渲染测试**

Run: `cd web; npm run build; node --test tests/rendered-html.test.mjs tests/public-data-routes.test.mjs`

Expected: PASS，0 failures。

- [ ] **Step 7: 把路由测试加入默认测试并提交**

将 `tests/public-data-routes.test.mjs` 加入 `web/package.json` 的构建后测试组。

```powershell
git add 'web/app/products/[asin]/page.tsx' web/app/api/public/overview/route.ts web/app/api/public/rankings/route.ts 'web/app/api/public/products/[asin]/route.ts' web/tests/rendered-html.test.mjs web/tests/public-data-routes.test.mjs web/package.json
git commit -m "feat: serve live product and public dashboard data"
```

---

### Task 4: 全量验证、上线并核对公开站点

**Files:**
- Modify only if verification exposes a scoped defect.
- Verify: `web/.openai/hosting.json`
- Verify: `.openai/hosting.json`
- Verify: `scripts/Publish-BestSellersDashboard.ps1`

**Interfaces:**
- Consumes: Tasks 1–3 的完整站点源代码和现有 `project_id`、D1、R2 绑定。
- Produces: 一个新的已部署 Sites 版本；本机日报、周报和 09:00 同步继续独立运行。

- [ ] **Step 1: 运行网站完整测试**

Run: `cd web; npm test`

Expected: 所有 Node 测试通过，构建成功，0 failures。

- [ ] **Step 2: 运行 lint 与独立构建**

Run: `cd web; npm run lint; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run build`

Expected: 两个命令 exit 0；`web/dist/server/index.js` 存在。

- [ ] **Step 3: 运行本地 PowerShell 全量回归**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1`

Expected: 至少 200 tests，Failed: 0。

- [ ] **Step 4: 执行秘密和差异检查**

Run:

```powershell
git diff --check
git status --short
git diff --cached --name-only
```

只允许本任务站点源码/测试的预期变化和既有未跟踪 `AGENTS.md`；不得暂存 `.local/`、`.venv/`、`var/`、`.env`、`config/sources.json` 或真实秘密。

- [ ] **Step 5: 提交最终验证修正（若 Tasks 1–3 后无额外修改则跳过此提交）**

```powershell
git add web
git commit -m "test: verify live dashboard data flow"
```

- [ ] **Step 6: 按 Sites hosting 流程发布现有站点新版本**

1. 复用 `web/.openai/hosting.json` 中的 `project_id`。
2. 为现有 Sites 源仓库获取短期写凭证，不写入 Git 配置或远程 URL。
3. 将经过验证的分支头推送到 Sites 源仓库。
4. 使用 Sites `package-site.sh` 打包 `web/dist`、hosting metadata 和现有迁移。
5. 保存一个新版本并部署到现有公开访问级别；用户此前已明确确认该站点公开生产部署。
6. 轮询部署状态直到 `succeeded` 或明确失败。

Expected: 部署状态 `succeeded`，URL 保持 `https://amazon-bs-market-radar.warrenwangyihao.chatgpt.site/`。

- [ ] **Step 7: 验证线上页面与接口一致**

请求：

```text
/
/rankings
/insights
/products/<最新榜单中一个真实 ASIN>
/api/public/overview
/api/public/rankings?category=pressure_washers
/api/public/reports
```

核对：

- 首页、榜单、洞察、产品和 API 显示同一个最新市场日。
- 三榜各 30 条，最新总观测为 90；若真实最新快照不完整，则按真实数量和质量状态显示。
- 报告中心现有 PDF 数量不减少。
- 页面和 JSON 不包含邮箱、本机路径、授权码、任务名称、绑定名或内部错误。

- [ ] **Step 8: 验证本地计划任务未受影响**

Run:

```powershell
Get-ScheduledTask -TaskName 'Amazon-BS-Package-Daily-0800','Amazon-BS-Package-Weekly-0600','Amazon-BS-Dashboard-Publish-0900' |
  Select-Object TaskName,State
```

Expected: 三个任务均存在且为 `Ready`；日报下次为 08:00，周报下次为周一 06:00，网站同步下次为 09:00。

- [ ] **Step 9: 最终仓库状态检查**

Run: `git status --short; git log -5 --oneline`

Expected: 仅显示既有未跟踪 `AGENTS.md`，没有本任务未提交修改。
