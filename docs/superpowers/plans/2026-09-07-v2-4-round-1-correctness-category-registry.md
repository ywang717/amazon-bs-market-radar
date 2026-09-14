# V2.4 Round 1 Correctness and Category Registry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复已确认的数据展示正确性问题，并以单一权威 Category Registry 替代生产代码中的三市场重复硬编码，同时保持历史 Snapshot 和现有三个市场兼容。

**Architecture:** `config/category-registry.json` 保存生产 Category、Amazon Source、Segment 和页面默认值；PowerShell 通过独立 Registry 模块读取，Node 生成器产生兼容的 collector source 配置和类型安全 Web artifact。Correctness 修复位于 canonical metadata、validation、Market Universe 和 shared formatting 层，页面只消费共享结果。

**Tech Stack:** PowerShell 7/Pester、Node.js 22、TypeScript 5.9、React 19、Vinext、JSON、现有 Python collector。

**Spec:** `docs/superpowers/specs/2026-09-07-v2-4-round-1-correctness-category-registry-design.md`

## Global Constraints

- 仅实施 Correctness Audit、Correctness Fix、Category Registry + Schema 以及相应验证；完成后停止。
- `sump_pumps`、中文名“污水泵”和 Amazon Node `680335011` 保持不变。
- `pressure_washers` Node 保持 `552856`；`pressure_washer_accessories` Node 保持 `3023451`。
- 历史 Raw Snapshot 只读；不回填、不重写、不重新解释。
- 数据库继续保存字符串 `category_key`；本轮不创建数据库迁移。
- 独立 Accessories Market 不得由 Pressure Washers Raw Ranking 过滤结果替代。
- 未知或禁用 Category 必须 fail closed，不能回退为高压清洗机。
- 不完整日和失败抓取不得生成 Exit、Turnover、Rank Trend 或 Brand Contraction。
- 页面不得自行实现 Product Classification 或 Market Universe。
- 不引入新运行时依赖或大型框架。
- 执行前用 `superpowers:using-git-worktrees` 建立隔离工作树；当前主工作区的既有未提交文件不得被覆盖或加入本轮提交。
- 每个任务只提交该任务列出的文件；执行 `git diff --cached --name-only` 后再提交。

---

### Task 1: 固化 Correctness Audit 与回归基线

**Files:**
- Create: `docs/audits/V2.4-ROUND-1-CORRECTNESS-AUDIT-2026-09-07.md`
- Test: `web/tests/ui-intelligence.test.mjs`
- Test: `web/tests/market-context.test.mjs`
- Test: `tests/BestSellersDataSemantics.Tests.ps1`

**Interfaces:**
- Consumes: 已确认设计规范与当前生产代码。
- Produces: 带具体文件证据、复现方法和最终状态栏的第一轮审计记录；后续任务以其中的 Issue ID 作为验收索引。

- [ ] **Step 1: 记录当前 Git 边界和只读基线**

Run:

```powershell
git status --short
git rev-parse HEAD
git diff --check
```

Expected: 记录隔离工作树的 HEAD；`git diff --check` 无输出。若工作树包含主工作区既有修改，停止并重新创建隔离工作树。

- [ ] **Step 2: 创建包含已验证事实的审计文档**

Create the document with this issue table:

```markdown
| ID | Area | Evidence | Baseline | Target |
| --- | --- | --- | --- | --- |
| C-01 | Product Identity | `web/app/products/[asin]/page.tsx` 未传 metadata | OPEN | 详情与列表一致 |
| C-02 | Deal validation | `discount <= currentPrice` 且有 price 即待确认 | OPEN | 合法大额优惠保留 |
| C-03 | Review event | Signal 使用 compact number；详情无 review event | OPEN | 精确事件格式与时间线 |
| C-04 | Time window | Overview 比较未显式显示 1D | OPEN | 指标窗口明确 |
| C-05 | Product specs | 仅按 Category 过滤 | OPEN | Category + Product Type |
| C-06 | Brand wording | 部分“市场席位”文案 | OPEN | 统一“榜单席位” |
| R-01 | Category source | Category 定义分散 | OPEN | Registry 为唯一权威来源 |
```

Document the exact production categories and nodes under a separate “Immutable Compatibility Facts” heading.

- [ ] **Step 3: 运行当前相关测试并记录基线结果**

Run:

```powershell
pwsh -NoLogo -NoProfile -Command '$r = Invoke-Pester -Path tests/BestSellersDataSemantics.Tests.ps1 -PassThru; if ($r.FailedCount -gt 0) { exit 1 }'
Push-Location web
node --test tests/ui-intelligence.test.mjs tests/market-context.test.mjs tests/valid-market-days.test.mjs
Pop-Location
```

Expected: 记录实际通过/失败数。已有测试通过不代表 C-01 至 C-05 已解决；审计必须指出当前错误行为可能被旧断言固化。

- [ ] **Step 4: 提交审计基线**

```powershell
git add -- docs/audits/V2.4-ROUND-1-CORRECTNESS-AUDIT-2026-09-07.md
git diff --cached --check
git commit -m "docs: audit v2.4 correctness baseline"
```

### Task 2: 修复 Deal 验证与统一展示

**Files:**
- Modify: `web/lib/ui-intelligence.ts`
- Modify: `web/app/products/[asin]/page.tsx`
- Modify: `web/app/rankings/RankingExplorer.tsx`
- Modify: `web/app/products/ProductBrowser.tsx`
- Test: `web/tests/ui-intelligence.test.mjs`
- Test: `web/tests/rendered-html.test.mjs`

**Interfaces:**
- Consumes: `Observation.has_discount`, `Observation.discounts`, optional `price`/reference price evidence.
- Produces: `formatDeal(observation): string` and `validateDealDisplay(input): { valid: boolean; label: string }` as the only UI Deal path.

- [ ] **Step 1: 将旧错误期望改成失败回归测试**

Add or replace assertions:

```js
test("keeps a verified Amazon saving even when it exceeds current price", () => {
  assert.deepEqual(validateDealDisplay({
    currentPrice: 79.99,
    referencePrice: 266.88,
    discount: 186.89,
    hasDiscount: true,
    label: "$186.89 OFF",
  }), { valid: true, label: "$186.89 OFF" });
  assert.equal(formatDeal({
    price: 79.99,
    has_discount: true,
    discounts: [{ kind: "PRICE_DROP", amount: "$186.89 off" }],
  }), "$186.89 OFF");
});

test("fails closed for malformed deal evidence", () => {
  assert.deepEqual(validateDealDisplay({ currentPrice: 79.99, referencePrice: 266.88, discount: -1, hasDiscount: true }), {
    valid: false,
    label: "优惠信息待确认",
  });
});
```

- [ ] **Step 2: 运行测试并确认旧实现失败**

Run: `Push-Location web; node --test tests/ui-intelligence.test.mjs; Pop-Location`

Expected: FAIL because `$186.89 off` is currently converted to `优惠信息待确认`.

- [ ] **Step 3: 实施最小验证和格式化修复**

Use this validation rule:

```ts
const valid = input.hasDiscount === true
  && input.currentPrice !== null && input.currentPrice > 0
  && input.referencePrice !== null && input.referencePrice >= input.currentPrice
  && input.discount !== null && input.discount >= 0;
```

Remove the unconditional `price` rejection from `formatDeal`; normalize a verified dollar label with:

```ts
return amount
  .replace(/\$(\d+)\.00\b/, "$$$1")
  .replace(/\boff\b/gi, "OFF");
```

Update Product Detail to import and call `formatDeal(current)` instead of `formatDiscount(current)`. Keep `—` for `has_discount === false` and `优惠信息待确认` only for malformed/insufficient evidence.

- [ ] **Step 4: 验证三个页面路径一致**

Run:

```powershell
Push-Location web
node --test tests/ui-intelligence.test.mjs tests/rendered-html.test.mjs
Pop-Location
```

Expected: PASS; rendered Product Detail and Rankings both contain `$186.89 OFF` for the fixture and do not contain `$30.00 off` or `无优惠`.

- [ ] **Step 5: 提交 Deal 修复**

```powershell
git add -- web/lib/ui-intelligence.ts web/app/products/[asin]/page.tsx web/app/rankings/RankingExplorer.tsx web/app/products/ProductBrowser.tsx web/tests/ui-intelligence.test.mjs web/tests/rendered-html.test.mjs
git diff --cached --check
git commit -m "fix: preserve verified deal evidence"
```

### Task 3: 统一 Product Identity 与 Product-Type 规格语义

**Files:**
- Modify: `web/lib/product-specs.ts`
- Modify: `web/app/products/[asin]/page.tsx`
- Modify: `web/app/components/ProductIdentity.tsx`
- Create: `web/tests/product-specs.test.mjs`
- Modify: `web/tests/rendered-html.test.mjs`

**Interfaces:**
- Consumes: `CategoryKey`, `ProductType`, canonical `ProductMetadata`.
- Produces: `readExplicitSpecificationsForProduct(categoryKey: CategoryKey, productType: ProductType, title: string): ProductSpecification[]`.

- [ ] **Step 1: 写 Product Type 语义失败测试**

```js
import assert from "node:assert/strict";
import test from "node:test";
import { readExplicitSpecificationsForProduct } from "../lib/product-specs.ts";

test("uses pressure semantics only for pressure-washer machines", () => {
  assert.deepEqual(
    readExplicitSpecificationsForProduct("pressure_washers", "electric_pressure_washer", "Westinghouse 2300 PSI 1.76 GPM Electric Pressure Washer"),
    [
      { label: "工作压力", value: "2300 PSI" },
      { label: "流量", value: "1.76 GPM" },
      { label: "动力类型", value: "电动" },
    ],
  );
  assert.equal(
    readExplicitSpecificationsForProduct("pressure_washer_accessories", "hose", "Pressure Washer Hose rated 4000 PSI 50 FT")
      .some(({ label }) => label === "工作压力"),
    false,
  );
});
```

- [ ] **Step 2: 运行并确认函数缺失**

Run: `Push-Location web; node --test tests/product-specs.test.mjs; Pop-Location`

Expected: FAIL because `readExplicitSpecificationsForProduct` is not exported.

- [ ] **Step 3: 实施 Category + Product Type Schema 过滤**

Define explicit allowed labels:

```ts
const specificationLabelsByProductType: Record<ProductType, ReadonlySet<string>> = {
  electric_pressure_washer: new Set(["工作压力", "流量", "动力类型", "软管长度", "电源线长度"]),
  gas_pressure_washer: new Set(["工作压力", "流量", "动力类型", "马力", "软管长度"]),
  cordless_pressure_washer: new Set(["工作压力", "流量", "动力类型", "电压", "软管长度"]),
  surface_cleaner: new Set(["接口尺寸"]),
  pressure_washer_gun: new Set(["接口尺寸"]),
  hose: new Set(["软管长度", "接口尺寸"]),
  nozzle: new Set(["喷嘴角度", "接口尺寸"]),
  chemical_cleaner: new Set(),
  pump_protector: new Set(),
  other_accessory: new Set(["接口尺寸"]),
  unknown: new Set(),
};
```

Rename the parsed PSI label from `压力` to `工作压力`, retain the Category allow-list as an outer safety boundary, then intersect it with the Product Type allow-list.

- [ ] **Step 4: 向详情页注入 canonical metadata**

Resolve once:

```ts
const productMetadata = dashboard.productMetadata.find((row) => row.asin === current.asin) ?? null;
const explicitSpecs = readExplicitSpecificationsForProduct(
  category.key,
  productMetadata?.productType ?? "unknown",
  current.title,
);
```

Render:

```tsx
<ProductIdentity
  asin={current.asin}
  title={current.title}
  type={productMetadata?.productType ?? "unknown"}
  brand={productMetadata?.normalizedBrand ?? productMetadata?.rawBrand ?? null}
/>
```

- [ ] **Step 5: 验证详情、列表和规格测试**

Run:

```powershell
Push-Location web
node --test tests/product-specs.test.mjs tests/rendered-html.test.mjs tests/ui-intelligence.test.mjs
Pop-Location
```

Expected: PASS; known Westinghouse detail fixture displays its metadata type/brand and machine specs use `工作压力`.

- [ ] **Step 6: 提交 Identity 与 Specs 修复**

```powershell
git add -- web/lib/product-specs.ts web/app/products/[asin]/page.tsx web/app/components/ProductIdentity.tsx web/tests/product-specs.test.mjs web/tests/rendered-html.test.mjs
git diff --cached --check
git commit -m "fix: align product identity and specification semantics"
```

### Task 4: 增加精确 Review Event 并标明 1D 窗口

**Files:**
- Modify: `web/lib/ui-intelligence.ts`
- Modify: `web/app/components/SignalCard.tsx`
- Modify: `web/app/components/TimelineEvent.tsx`
- Modify: `web/app/products/[asin]/page.tsx`
- Modify: `web/app/page.tsx`
- Modify: `web/app/market/page.tsx`
- Test: `web/tests/ui-intelligence.test.mjs`
- Test: `web/tests/rendered-html.test.mjs`

**Interfaces:**
- Produces: `formatExactNumber(value: number | null): string` and `formatReviewChange(previous: number, current: number): string`.
- Produces: `TimelineEventKind` extended with `review`.

- [ ] **Step 1: 写精确评论变化失败测试**

```js
test("formats review events exactly instead of compacting evidence", () => {
  assert.equal(formatExactNumber(8949), "8,949");
  assert.equal(formatReviewChange(8949, 8977), "8,949 → 8,977  +28");
  assert.equal(formatReviewChange(8977, 8949), "8,977 → 8,949  -28");
  assert.equal(formatExactNumber(null), "—");
});
```

- [ ] **Step 2: 运行并确认新 formatter 缺失**

Run: `Push-Location web; node --test tests/ui-intelligence.test.mjs; Pop-Location`

Expected: FAIL because the exact event formatters are not exported.

- [ ] **Step 3: 实施精确 formatter 和 review timeline event**

```ts
export function formatExactNumber(value: number | null) {
  return value === null ? "—" : new Intl.NumberFormat("en-US", { maximumFractionDigits: 0 }).format(value);
}

export function formatReviewChange(previous: number, current: number) {
  const delta = current - previous;
  return `${formatExactNumber(previous)} → ${formatExactNumber(current)}  ${delta >= 0 ? "+" : ""}${formatExactNumber(delta)}`;
}
```

Add `review` to `TimelineEventKind` and label it `评论变化`. In Product Detail, append a review event only when both values are non-null and differ:

```ts
if (before.observation.reviews !== null
  && after.observation.reviews !== null
  && before.observation.reviews !== after.observation.reviews) {
  events.push({
    kind: "review",
    date: after.marketDate,
    detail: formatReviewChange(before.observation.reviews, after.observation.reviews),
  });
}
```

Use exact formatting for `review_momentum` evidence in `SignalCard`; retain compact formatting for summary review counts.

- [ ] **Step 4: 标明比较窗口**

Change Overview KPI support text to `1D · 对比上一有效市场日` and the Top10 metric label/detail to `Top10 稳定度（1D）` / `1D · 头部阵容留存`. Keep Market trend cards as `${windowDays}D 当前窗口 vs 前一等长窗口`.

- [ ] **Step 5: 验证事件与页面文案**

Run:

```powershell
Push-Location web
node --test tests/ui-intelligence.test.mjs tests/rendered-html.test.mjs
Pop-Location
```

Expected: PASS; detail fixture contains `评论变化` and exact values; Overview contains explicit `1D`.

- [ ] **Step 6: 提交 Review 与 Window 修复**

```powershell
git add -- web/lib/ui-intelligence.ts web/app/components/SignalCard.tsx web/app/components/TimelineEvent.tsx web/app/products/[asin]/page.tsx web/app/page.tsx web/app/market/page.tsx web/tests/ui-intelligence.test.mjs web/tests/rendered-html.test.mjs
git diff --cached --check
git commit -m "fix: show exact review events and time windows"
```

### Task 5: 建立 Category Registry Schema 与 PowerShell Loader

**Files:**
- Create: `config/category-registry.json`
- Create: `config/schemas/category-registry.schema.json`
- Create: `config/v2-product-attributes.json`
- Create: `src/BestSellersCategoryRegistry.psm1`
- Create: `tests/CategoryRegistry.Tests.ps1`

**Interfaces:**
- Produces: `Import-BestSellersCategoryRegistry -Path <string>`.
- Produces: `Get-BestSellersCategoryKeys -Registry <object> [-EnabledOnly]`.
- Produces: `Get-BestSellersCategory -Registry <object> -CategoryKey <string>`.
- Produces: normalized objects with `CategoryKey`, `Slug`, `LabelZh`, `LabelEn`, `NodeId`, `SourceUrl`, `TargetCount`, `ReportFileToken`, `Segments`, and `Defaults`.

- [ ] **Step 1: 写 Registry 校验失败测试**

Tests must cover the production nodes plus duplicate key/node, invalid default segment, missing source URL, missing classification config, and missing attribute schema. Use `$TestDrive` copies so production config is never modified.

```powershell
It 'preserves the three production categories and nodes' {
    $registry = Import-BestSellersCategoryRegistry -Path $registryPath
    (Get-BestSellersCategory -Registry $registry -CategoryKey 'sump_pumps').NodeId | Should Be '680335011'
    (@(Get-BestSellersCategoryKeys -Registry $registry -EnabledOnly) -join ',') | Should Be 'pressure_washers,sump_pumps,pressure_washer_accessories'
}

It 'rejects duplicate category keys before any consumer runs' {
    $invalidPath = Join-Path $TestDrive 'duplicate-key.json'
    $raw = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $raw.categories += $raw.categories[0]
    $raw | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $invalidPath -Encoding UTF8
    { Import-BestSellersCategoryRegistry -Path $invalidPath } | Should Throw
}
```

- [ ] **Step 2: 运行并确认模块缺失**

Run: `pwsh -NoLogo -NoProfile -Command '$r = Invoke-Pester -Path tests/CategoryRegistry.Tests.ps1 -PassThru; if ($r.FailedCount -gt 0) { exit 1 }'`

Expected: FAIL because `BestSellersCategoryRegistry.psm1` and Registry do not exist.

- [ ] **Step 3: 创建权威 Registry 数据**

Use this normalized shape for every Category:

```json
{
  "schema_version": "category-registry-v1",
  "marketplace": { "context_code": "US", "storage_code": "AMAZON_US" },
  "categories": [{
    "category_key": "sump_pumps",
    "slug": "sump-pump",
    "label_zh": "污水泵",
    "label_en": "Sump Pumps",
    "amazon_node_id": "680335011",
    "source_url": "https://www.amazon.com/Best-Sellers-Tools-Home-Improvement-Sump-Pumps/zgbs/hi/680335011",
    "target_count": 30,
    "enabled": true,
    "report_file_token": "Sump_Pumps",
    "classification_config_path": "config/v2-product-classification.json",
    "attribute_schema_path": "config/v2-product-attributes.json",
    "segments": [{ "key": "all", "label_zh": "全部榜单", "product_types": [] }],
    "defaults": { "overview": "all", "market": "all", "products": "all", "brands": "all", "rankings": "all", "reports": "all", "alerts": "all", "data_status": "all", "product_detail": "all" }
  }]
}
```

Add the other two categories with these exact values:

| Field | `pressure_washers` | `pressure_washer_accessories` |
| --- | --- | --- |
| Slug | `pressure-washer` | `pressure-washer-accessories` |
| Label ZH | 高压清洗机 | 高压清洗机配件 |
| Label EN | Pressure Washers | Pressure Washer Parts & Accessories |
| Node | `552856` | `3023451` |
| Source URL | `https://www.amazon.com/Best-Sellers-Patio-Lawn-Garden-Pressure-Washers/zgbs/lawn-garden/552856` | `https://www.amazon.com/Best-Sellers-Patio-Lawn-Garden-Pressure-Washer-Parts-Accessories/zgbs/lawn-garden/3023451` |
| Target count | `30` | `30` |
| Report token | `Pressure_Washers` | `Pressure_Washer_Parts_Accessories` |

Use these exact Segment mappings:

```text
pressure_washers:
  all=[]
  machines=[electric_pressure_washer,gas_pressure_washer,cordless_pressure_washer]
  electric=[electric_pressure_washer]
  gas=[gas_pressure_washer]
  cordless=[cordless_pressure_washer]

pressure_washer_accessories:
  all=[]
  surface_cleaners=[surface_cleaner]
  guns=[pressure_washer_gun]
  hoses=[hose]
  nozzles=[nozzle]
  other=[chemical_cleaner,pump_protector,other_accessory]
```

For `pressure_washers`, defaults are `machines` for every listed page except `rankings=all`. For `pressure_washer_accessories`, every page default is `all`. The JSON Schema must set `additionalProperties: false` for Registry, Category, Segment and Defaults objects.

Use this attribute Schema shape, with every current `ProductType` present exactly once:

```json
{
  "schema_version": "product-attribute-schema-v1",
  "product_types": {
    "electric_pressure_washer": ["工作压力", "流量", "动力类型", "软管长度", "电源线长度"],
    "gas_pressure_washer": ["工作压力", "流量", "动力类型", "马力", "软管长度"],
    "cordless_pressure_washer": ["工作压力", "流量", "动力类型", "电压", "软管长度"],
    "surface_cleaner": ["接口尺寸"],
    "pressure_washer_gun": ["接口尺寸"],
    "hose": ["软管长度", "接口尺寸"],
    "nozzle": ["喷嘴角度", "接口尺寸"],
    "chemical_cleaner": [],
    "pump_protector": [],
    "other_accessory": ["接口尺寸"],
    "unknown": []
  }
}
```

- [ ] **Step 4: 实施 PowerShell fail-closed loader**

The loader must read UTF-8, validate `category-registry-v1`, resolve referenced files relative to project root, reject duplicates with ordinal comparison, validate every page default against that Category’s segment keys, and throw for unknown/disabled keys:

```powershell
function Get-BestSellersCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Registry,
        [Parameter(Mandatory=$true)][string]$CategoryKey,
        [switch]$AllowDisabled
    )
    $matches = @($Registry.Categories | Where-Object { $_.CategoryKey -ceq $CategoryKey })
    if ($matches.Count -ne 1 -or (-not $AllowDisabled -and -not $matches[0].Enabled)) {
        throw "Unknown or disabled category key: $CategoryKey"
    }
    return $matches[0]
}
```

- [ ] **Step 5: 验证 Registry 合同**

Run: `pwsh -NoLogo -NoProfile -Command '$r = Invoke-Pester -Path tests/CategoryRegistry.Tests.ps1 -PassThru; if ($r.FailedCount -gt 0) { exit 1 }'`

Expected: PASS for production configuration and all fail-closed cases.

- [ ] **Step 6: 提交 Registry 模型与 Loader**

```powershell
git add -- config/category-registry.json config/schemas/category-registry.schema.json config/v2-product-attributes.json src/BestSellersCategoryRegistry.psm1 tests/CategoryRegistry.Tests.ps1
git diff --cached --check
git commit -m "feat: add authoritative category registry"
```

### Task 6: 生成 Collector 与 Web Registry Artifacts

**Files:**
- Create: `scripts/build-category-registry.mjs`
- Modify (generated): `config/best-sellers-sources.json`
- Create (generated): `web/lib/generated/category-registry.ts`
- Create: `web/lib/category-registry.ts`
- Create: `web/tests/category-registry.test.mjs`
- Modify: `web/package.json`

**Interfaces:**
- Produces CLI: `node scripts/build-category-registry.mjs [--check] [--registry <path>] [--sources-output <path>] [--web-output <path>]`.
- Produces: `parseCategoryRegistry(input: unknown): RuntimeCategoryRegistry` and `productionCategoryRegistry`.
- Generated collector artifact retains `{ marketplace, target_count, sources, page_loading }` required by the existing Python/PowerShell consumers.

Define the runtime boundary explicitly:

```ts
export type RegistryPage = "overview" | "market" | "products" | "brands" | "rankings" | "reports" | "alerts" | "data_status" | "product_detail";
export type RuntimeRegistrySegment = { key: string; labelZh: string; productTypes: readonly string[] };
export type RuntimeRegistryCategory = {
  categoryKey: string;
  slug: string;
  labelZh: string;
  labelEn: string;
  nodeId: string;
  sourceUrl: string;
  targetCount: number;
  enabled: boolean;
  reportFileToken: string;
  segments: readonly RuntimeRegistrySegment[];
  defaults: Readonly<Record<RegistryPage, string>>;
};
export type RuntimeCategoryRegistry = {
  schemaVersion: "category-registry-v1";
  marketplace: { contextCode: "US"; storageCode: "AMAZON_US" };
  categories: readonly RuntimeRegistryCategory[];
  productTypeAttributes: Readonly<Record<string, readonly string[]>>;
};
```

- [ ] **Step 1: 写 Artifact parity 与陈旧检测失败测试**

```js
test("generated production registry preserves category nodes", () => {
  assert.deepEqual(
    Object.fromEntries(productionCategoryRegistry.categories.map((row) => [row.categoryKey, row.nodeId])),
    {
      pressure_washers: "552856",
      sump_pumps: "680335011",
      pressure_washer_accessories: "3023451",
    },
  );
});

test("runtime parser rejects duplicate nodes", () => {
  const fixture = structuredClone(productionCategoryRegistry);
  fixture.categories[1].nodeId = fixture.categories[0].nodeId;
  assert.throws(() => parseCategoryRegistry(fixture), /duplicate.*node/i);
});
```

- [ ] **Step 2: 运行并确认生成模块缺失**

Run: `Push-Location web; node --test tests/category-registry.test.mjs; Pop-Location`

Expected: FAIL because the generated and runtime modules do not exist.

- [ ] **Step 3: 实施确定性生成器**

The script must sort only object keys, preserve the explicit Category and Segment array order, emit UTF-8 with one trailing newline, and support `--check` by comparing expected bytes without writing. Failure text must name the stale output.

Resolve every `attribute_schema_path` during generation and embed its Product-Type-to-label mapping once as `productTypeAttributes`; fail generation if two referenced schemas define the same Product Type differently.

Generate TypeScript from the normalized object with this exact template logic:

```js
const serializedRegistry = JSON.stringify(webRegistry, null, 2);
const typeScript = `export const generatedCategoryRegistry = ${serializedRegistry} as const;\n\n`
  + `export type CategoryKey = (typeof generatedCategoryRegistry.categories)[number]["categoryKey"];\n`
  + `export type SegmentKey = (typeof generatedCategoryRegistry.categories)[number]["segments"][number]["key"];\n`;
```

- [ ] **Step 4: 生成并验证兼容 source artifact**

Run:

```powershell
node scripts/build-category-registry.mjs
node scripts/build-category-registry.mjs --check
```

Expected: both commands exit 0; `best-sellers-sources.json` retains the existing three source URLs, node IDs, target count 30 and pagination rules.

- [ ] **Step 5: 将陈旧检查接入 Web build**

Change scripts to:

```json
"registry:check": "node ../scripts/build-category-registry.mjs --check",
"build": "node ../scripts/build-category-registry.mjs --check && vinext build"
```

Do not add a package dependency.

- [ ] **Step 6: 运行 Registry 与 collector config 回归**

Run:

```powershell
Push-Location web
node --test tests/category-registry.test.mjs
Pop-Location
pwsh -NoLogo -NoProfile -Command '$r = Invoke-Pester -Path tests/AmazonIntelligence.Tests.ps1 -PassThru; if ($r.FailedCount -gt 0) { exit 1 }'
```

Expected: PASS; existing collector/source contract tests still accept the generated compatibility artifact.

- [ ] **Step 7: 提交生成链路**

```powershell
git add -- scripts/build-category-registry.mjs config/best-sellers-sources.json web/lib/generated/category-registry.ts web/lib/category-registry.ts web/tests/category-registry.test.mjs web/package.json
git diff --cached --check
git commit -m "build: generate category registry artifacts"
```

### Task 7: 让 Web Market Context 与分析层消费 Registry

**Files:**
- Modify: `web/lib/catalog.ts`
- Modify: `web/lib/market-context.ts`
- Modify: `web/lib/product-specs.ts`
- Modify: `web/lib/ui-intelligence.ts`
- Modify: `web/lib/live-dashboard-data.ts`
- Modify: `web/lib/seller-intelligence.ts`
- Modify: `web/lib/analysis-report-contract.ts`
- Modify: `web/lib/seller-intelligence-contract.ts`
- Modify: `web/app/api/public/rankings/route.ts`
- Modify: `web/app/api/public/analysis/live/route.ts`
- Modify: `web/app/api/public/analysis/[...key]/route.ts`
- Modify: `web/app/api/public/reports/route.ts`
- Modify: `web/app/brands/page.tsx`
- Modify: `web/app/market/page.tsx`
- Test: `web/tests/category-registry.test.mjs`
- Test: `web/tests/market-context.test.mjs`
- Test: `web/tests/live-dashboard-data.test.mjs`
- Test: `web/tests/ui-intelligence.test.mjs`
- Test: `web/tests/rendered-html.test.mjs`
- Test: `web/tests/public-data-routes.test.mjs`

**Interfaces:**
- Consumes: `productionCategoryRegistry` and generated `CategoryKey`/`SegmentKey`.
- Produces: `createMarketContextResolver(registry)` for fixture injection; existing exported resolver functions delegate to the production instance.
- Produces: `resolvePublicMarketQuery(input, resolver)` returning the existing success/error context shape before any store access.

- [ ] **Step 1: 写 Test Category 和 fail-closed Web 测试**

Create a cloned fixture with `test_category`, node `999000111`, only segment `all`, then assert:

```js
const resolver = createMarketContextResolver(testRegistry);
assert.deepEqual(
  resolver.resolvePageMarketContext("products", { category: "test_category", segment: "all" }).context,
  { marketplace: "US", category: "test_category", segment: "all" },
);
assert.deepEqual(resolver.filterAnalyticalMarket(rows, metadata, {
  marketplace: "US", category: "test_category", segment: "all",
}), rows);
assert.deepEqual(validateMarketContext({ marketplace: "US", category: "missing", segment: "all" }), {
  ok: false, error: "unsupported_market_context",
});
```

- [ ] **Step 2: 运行并确认注入接口缺失**

Run: `Push-Location web; node --test tests/category-registry.test.mjs tests/market-context.test.mjs; Pop-Location`

Expected: FAIL because `createMarketContextResolver` does not exist and current maps are hardcoded.

- [ ] **Step 3: 从生成 Registry 构建 catalog 与 Market Config**

`catalog.ts` must derive `categories` and `categoryByKey` from generated data. `market-context.ts` must build `MARKET_CONFIG` and `PAGE_MARKET_DEFAULTS` from Registry values and expose a resolver factory:

```ts
export function createMarketContextResolver(registry: RuntimeCategoryRegistry) {
  const enabled = registry.categories.filter(({ enabled }) => enabled);
  const categoryByKey = new Map(enabled.map((category) => [category.categoryKey, category]));
  const validateMarketContext = (input: { marketplace: string; category: string; segment: string }) => {
    const category = categoryByKey.get(input.category);
    const supported = category?.segments.some(({ key }) => key === input.segment) ?? false;
    if (input.marketplace !== registry.marketplace.contextCode || !category || !supported) {
      return { ok: false, error: "unsupported_market_context" } as const;
    }
    return { ok: true, context: { marketplace: "US" as const, category: category.categoryKey, segment: input.segment } } as const;
  };
  const marketContextCacheKey = (context: { marketplace: string; category: string; segment: string }, scope: { date?: string | null; window?: string | null } = {}) =>
    [context.marketplace, context.category, context.segment, scope.date || "latest", scope.window || "snapshot"].join(":");
  return { categoryByKey, validateMarketContext, marketContextCacheKey };
}

const productionResolver = createMarketContextResolver(productionCategoryRegistry);
export const validateMarketContext = productionResolver.validateMarketContext;
export const marketContextCacheKey = productionResolver.marketContextCacheKey;
```

Define `resolvePageMarketContext` and `filterAnalyticalMarket` inside the same factory so they close over `categoryByKey`, then export production-bound delegates with their existing public names. Preserve the current return shapes used by pages.

An explicit unknown Category must remain invalid; page normalization may select the Registry’s first enabled Category only when the URL Category is absent/invalid.

- [ ] **Step 4: 删除 Web 生产代码的平行 Category 分支**

Replace `marketContextForCategory` branches, specification Category maps, contract allow-lists and live-dashboard enumeration with Registry lookup. Product Type semantics remain in classification/attribute Schema; Category identity and labels come only from Registry.

Replace the temporary Product Type label map introduced in Task 3 with `productionCategoryRegistry.productTypeAttributes`, so the attribute Schema is the final authority.

Make public route query validation call the shared production resolver. Extract `resolvePublicMarketQuery(input, resolver)` as a pure function so `public-data-routes.test.mjs` can pass the Test Category resolver and assert a `200`-eligible context; unknown Category must return the existing `400` contract without querying the store.

Change the Brands table heading from `市场席位` to `榜单席位`, and the Market concentration note to `按当前榜单席位，不代表销量份额。`. Add rendered HTML assertions that the old phrase is absent from those two surfaces.

- [ ] **Step 5: 运行 Web 相关测试**

Run:

```powershell
Push-Location web
node --test tests/category-registry.test.mjs tests/market-context.test.mjs tests/live-dashboard-data.test.mjs tests/ui-intelligence.test.mjs tests/analysis-report-contract.test.mjs tests/seller-intelligence-contract.test.mjs tests/rendered-html.test.mjs tests/public-data-routes.test.mjs
Pop-Location
```

Expected: PASS; production nodes unchanged, Test Category resolves through the injected Registry, and cache keys differ by Category/Segment/Date/Window.

- [ ] **Step 6: 提交 Web Registry 接入**

```powershell
git add -- web/lib/catalog.ts web/lib/market-context.ts web/lib/product-specs.ts web/lib/ui-intelligence.ts web/lib/live-dashboard-data.ts web/lib/seller-intelligence.ts web/lib/analysis-report-contract.ts web/lib/seller-intelligence-contract.ts web/app/api/public/rankings/route.ts web/app/api/public/analysis/live/route.ts web/app/api/public/analysis/[...key]/route.ts web/app/api/public/reports/route.ts web/app/brands/page.tsx web/app/market/page.tsx web/tests/category-registry.test.mjs web/tests/market-context.test.mjs web/tests/live-dashboard-data.test.mjs web/tests/ui-intelligence.test.mjs web/tests/rendered-html.test.mjs web/tests/public-data-routes.test.mjs
git diff --cached --check
git commit -m "refactor: drive web markets from category registry"
```

### Task 8: 让 PowerShell 分析、报告和运维脚本消费 Registry

**Files:**
- Modify: `src/BestSellersDataSemantics.psm1`
- Modify: `src/BestSellersDailyReport.psm1`
- Modify: `src/BestSellersWeeklyAnalysis.psm1`
- Modify: `src/BestSellersMarketStructure.psm1`
- Modify: `src/BestSellersRankInfluence.psm1`
- Modify: `src/BestSellersBrandEnrichment.psm1`
- Modify: `src/SellerIntelligence.psm1`
- Modify: `src/OnlineAnalysisReport.psm1`
- Modify: `src/ReportArchive.psm1`
- Modify: `scripts/New-BestSellersDailyReport.ps1`
- Modify: `scripts/New-BestSellersWeeklyReport.ps1`
- Modify: `scripts/New-SellerIntelligenceReports.ps1`
- Modify: `scripts/New-DashboardSyncBundle.ps1`
- Modify: `scripts/Publish-BestSellersDashboard.ps1`
- Modify: `scripts/Test-BestSellersDailyOperationalHealth.ps1`
- Test: `tests/CategoryRegistry.Tests.ps1`
- Test: `tests/BestSellersDataSemantics.Tests.ps1`
- Test: `tests/AmazonIntelligence.Tests.ps1`
- Test: `tests/SellerIntelligence.Tests.ps1`
- Test: `tests/ReportArchive.Tests.ps1`

**Interfaces:**
- Consumes: `Import-BestSellersCategoryRegistry`, `Get-BestSellersCategoryKeys`, `Get-BestSellersCategory`.
- Produces: all Category enumeration, validation, labels, nodes and report tokens from Registry; command parameters remain string-compatible.

- [ ] **Step 1: 写第四 Category 的 PowerShell 集成测试**

Build a `$TestDrive` Registry by adding a complete `test_category` and verify daily report selection, operational quality enumeration and report archive token lookup accept it through `-RegistryPath`. Also verify `unsupported_category` throws before reading Snapshot rows.

The injected Category must use these exact values: `category_key=test_category`, `slug=test-category`, `label_zh=测试榜单`, `label_en=Test Category`, `amazon_node_id=999000111`, `source_url=https://www.amazon.com/Best-Sellers-Test/zgbs/test/999000111`, `target_count=30`, `enabled=true`, `report_file_token=Test_Category`, one `all` Segment with no Product Types, and `all` as every page default. Copy the referenced classification and attribute files into the `$TestDrive` fixture tree before loading it.

Build its complete in-memory Snapshot without touching production data:

```powershell
$testRows = @(1..30 | ForEach-Object {
    [pscustomobject]@{
        rank = $_
        asin = ('TST{0:D7}' -f $_)
        title = "Test Product $_"
        url = ('https://www.amazon.com/dp/TST{0:D7}' -f $_)
        price = 99.99
        rating = 4.5
        reviews = 100 + $_
        has_discount = $false
        discounts = @()
    }
})
$testSnapshot = [pscustomobject]@{
    market_date = '2026-09-02'
    observed_at = '2026-09-02T06:00:00+08:00'
    sources = [pscustomobject]@{ test_category = 'https://www.amazon.com/Best-Sellers-Test/zgbs/test/999000111' }
    test_category = $testRows
}
```

Call `Get-BestSellersProductClassification` for `TST0000001` and `test_category`; because no rule claims it, assert `product_type=unknown` rather than an exception or a Pressure Washers classification.

```powershell
$keys = @(Get-BestSellersCategoryKeys -Registry (Import-BestSellersCategoryRegistry -Path $testRegistryPath) -EnabledOnly)
$keys | Should Contain 'test_category'
{ Get-BestSellersCategory -Registry (Import-BestSellersCategoryRegistry -Path $testRegistryPath) -CategoryKey 'unsupported_category' } | Should Throw
```

- [ ] **Step 2: 运行并确认当前硬编码路径失败**

Run:

```powershell
pwsh -NoLogo -NoProfile -Command '$r = Invoke-Pester -Path tests/CategoryRegistry.Tests.ps1,tests/BestSellersDataSemantics.Tests.ps1,tests/SellerIntelligence.Tests.ps1,tests/ReportArchive.Tests.ps1 -PassThru; if ($r.FailedCount -gt 0) { exit 1 }'
```

Expected: FAIL because existing `ValidateSet` and script arrays reject `test_category`.

- [ ] **Step 3: 替换固定 ValidateSet 与 Category 数组**

Add optional Registry path parameters using the canonical default:

```powershell
[string]$RegistryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\category-registry.json')
```

Replace fixed `ValidateSet('pressure_washers',...)` with `[ValidateNotNullOrEmpty()][string]`, then immediately validate:

```powershell
$registry = Import-BestSellersCategoryRegistry -Path $RegistryPath
$category = Get-BestSellersCategory -Registry $registry -CategoryKey $CategoryKey
```

Replace production arrays such as `$allCategories` and `$script:SellerIntelligenceCategories` with enabled Registry entries. Use `LabelZh`, `LabelEn`, `ReportFileToken`, `TargetCount` and `NodeId` from the normalized Category object.

- [ ] **Step 4: 让分类配置校验引用 Registry**

Change `Assert-V2ProductClassificationConfig` to receive the normalized Registry and validate each override/rule `category_keys` through `Get-BestSellersCategory`. Keep Product Type validation in the classification config; remove the fixed three-key allow-list.

- [ ] **Step 5: 检查生产硬编码剩余项**

Run:

```powershell
rg -n "ValidateSet\('pressure_washers'|@\('pressure_washers'.*sump_pumps|SellerIntelligenceCategories\s*=\s*@\(" src scripts
rg -n "pressure_washers|sump_pumps|pressure_washer_accessories" src scripts web/lib web/app --glob '!web/lib/generated/**'
```

Expected: no production Category allow-list matches. For the second command, record every remaining match in the correctness audit; literals may remain only in Category-specific classification algorithms or compatibility parsing with an explicit reason, never for enumeration, labels, nodes, defaults or validation.

- [ ] **Step 6: 运行 PowerShell 回归**

Run:

```powershell
pwsh -NoLogo -NoProfile -Command '$r = Invoke-Pester -Path tests/CategoryRegistry.Tests.ps1,tests/BestSellersDataSemantics.Tests.ps1,tests/AmazonIntelligence.Tests.ps1,tests/SellerIntelligence.Tests.ps1,tests/ReportArchive.Tests.ps1 -PassThru; if ($r.FailedCount -gt 0) { exit 1 }'
```

Expected: PASS; three production markets and temporary Test Category both work, unknown Category fails closed.

- [ ] **Step 7: 提交 PowerShell Registry 接入**

```powershell
git add -- src/BestSellersDataSemantics.psm1 src/BestSellersDailyReport.psm1 src/BestSellersWeeklyAnalysis.psm1 src/BestSellersMarketStructure.psm1 src/BestSellersRankInfluence.psm1 src/BestSellersBrandEnrichment.psm1 src/SellerIntelligence.psm1 src/OnlineAnalysisReport.psm1 src/ReportArchive.psm1 scripts/New-BestSellersDailyReport.ps1 scripts/New-BestSellersWeeklyReport.ps1 scripts/New-SellerIntelligenceReports.ps1 scripts/New-DashboardSyncBundle.ps1 scripts/Publish-BestSellersDashboard.ps1 scripts/Test-BestSellersDailyOperationalHealth.ps1 tests/CategoryRegistry.Tests.ps1 tests/BestSellersDataSemantics.Tests.ps1 tests/AmazonIntelligence.Tests.ps1 tests/SellerIntelligence.Tests.ps1 tests/ReportArchive.Tests.ps1
git diff --cached --check
git commit -m "refactor: drive analysis and reports from category registry"
```

### Task 9: 证明统一 Market Universe、缓存隔离与历史安全

**Files:**
- Modify: `web/tests/market-context.test.mjs`
- Modify: `web/tests/live-dashboard-data.test.mjs`
- Modify: `web/tests/ui-intelligence.test.mjs`
- Modify: `web/tests/rendered-html.test.mjs`
- Modify: `tests/CategoryRegistry.Tests.ps1`
- Modify: `docs/audits/V2.4-ROUND-1-CORRECTNESS-AUDIT-2026-09-07.md`

**Interfaces:**
- Consumes: Registry resolver, `buildAnalyticalCategory`, `filterAnalyticalMarket`, valid-market-day selection and report builders.
- Produces: executable evidence that the same Context gives the same ASIN universe and that Test Category does not contaminate production caches or files.

- [ ] **Step 1: 添加同 Context 同 Universe 测试**

For one Pressure Washers fixture containing a machine and accessory, assert Machines excludes the accessory while Raw All preserves it. In `ui-intelligence.test.mjs`, reuse the file’s existing `observation()` and `metadata()` helpers and create the fixture exactly as follows:

```js
const machine = observation("B000000001", 1, "Westinghouse Electric Pressure Washer");
const accessory = observation("B000000002", 2, "15 Inch Surface Cleaner");
const metadataFixture = [
  metadata(machine.asin, "Westinghouse", "electric_pressure_washer"),
  metadata(accessory.asin, "Generic", "surface_cleaner"),
];
const categoryFixture = {
  key: "pressure_washers",
  label: "高压清洗机",
  marketDate: "2026-09-02",
  observations: [machine, accessory],
  previousObservations: [],
  comparison: { ready: false, movers: [] },
};
const machinesContext = { marketplace: "US", category: "pressure_washers", segment: "machines" };
const rawContext = { marketplace: "US", category: "pressure_washers", segment: "all" };
const analytical = buildAnalyticalCategory(categoryFixture, metadataFixture, machinesContext);
assert.deepEqual(analytical.observations.map(({ asin }) => asin).toSorted(), ["B000000001"]);
assert.deepEqual(filterAnalyticalMarket(categoryFixture.observations, metadataFixture, rawContext).map(({ asin }) => asin).toSorted(), ["B000000001", "B000000002"]);
```

- [ ] **Step 2: 添加 cache isolation 与 incomplete-day 测试**

Assert cache keys differ for production and Test Category, every Segment and every Date/Window. Add a latest incomplete day after a valid day and assert Exit, Turnover and Brand Contraction remain derived from the latest valid pair only.

- [ ] **Step 3: 运行集成测试**

Run:

```powershell
Push-Location web
node --test tests/category-registry.test.mjs tests/market-context.test.mjs tests/live-dashboard-data.test.mjs tests/ui-intelligence.test.mjs tests/valid-market-days.test.mjs tests/rendered-html.test.mjs
Pop-Location
```

Expected: PASS; Test Category cache keys are unique, Machines excludes accessory ASINs, Raw All preserves them, incomplete days cannot produce boundary events.

- [ ] **Step 4: 验证历史 Snapshot 未改动**

Run:

```powershell
git status --short -- data snapshots
git diff --name-only -- data snapshots
```

Expected: no tracked or untracked Snapshot/data changes created by this implementation.

- [ ] **Step 5: 更新审计状态**

Change C-01 through C-06 and R-01 from `OPEN` to `RESOLVED`, adding the exact test file and command that proves each result. If any item is not proven, leave it `OPEN` and list it in Remaining Issues; do not mark the round complete.

- [ ] **Step 6: 提交一致性验收**

```powershell
git add -- web/tests/market-context.test.mjs web/tests/live-dashboard-data.test.mjs web/tests/ui-intelligence.test.mjs web/tests/rendered-html.test.mjs tests/CategoryRegistry.Tests.ps1 docs/audits/V2.4-ROUND-1-CORRECTNESS-AUDIT-2026-09-07.md
git diff --cached --check
git commit -m "test: verify category universe and cache isolation"
```

### Task 10: 全量验证、浏览器 QA 与第一轮收口

**Files:**
- Modify: `docs/audits/V2.4-ROUND-1-CORRECTNESS-AUDIT-2026-09-07.md`
- Create: `docs/audits/V2.4-ROUND-1-BROWSER-QA-2026-09-07.md`

**Interfaces:**
- Consumes: all prior task deliverables.
- Produces: test/build/browser evidence and explicit remaining issues; no Stage 4+ product capability.

- [ ] **Step 1: 运行 Registry 陈旧检查和 diff 检查**

```powershell
node scripts/build-category-registry.mjs --check
git diff --check
```

Expected: both exit 0.

- [ ] **Step 2: 运行完整 PowerShell 测试**

```powershell
pwsh -NoLogo -NoProfile -Command '$r = Invoke-Pester -Path tests -PassThru; "Passed=$($r.PassedCount) Failed=$($r.FailedCount)"; if ($r.FailedCount -gt 0) { exit 1 }'
```

Expected: `Failed=0`. Record the actual Passed count.

- [ ] **Step 3: 运行 Web test、类型检查、lint 与 Production Build**

```powershell
Push-Location web
pnpm test
pnpm exec tsc --noEmit
pnpm lint
Pop-Location
```

Expected: all commands exit 0. `pnpm test` 的现有脚本会在前置 Node tests 后执行 `vinext build`，再运行 built-route tests；从该输出单独记录 Production Build 结果，禁止重复执行同一个 Build。

- [ ] **Step 4: 执行关键页面浏览器回归**

Start the verified production build locally and check these routes using explicit Context parameters:

```text
/?category=pressure_washers&segment=machines
/market?category=sump_pumps&segment=all
/products?category=pressure_washer_accessories&segment=all
/products/B0D739PX62?category=pressure_washers&segment=machines
/brands?category=pressure_washers&segment=electric
/rankings?category=pressure_washers&segment=all
/reports?category=sump_pumps&segment=all
/insights?category=pressure_washer_accessories&segment=all
```

Record PASS/FAIL for metadata identity, Deal format, exact Review Event, 1D labels, Category/Segment preservation, Back/Forward, refresh, Raw-vs-Analytical semantics and absence of cross-market data.

- [ ] **Step 5: 写浏览器 QA 记录并最终审计**

The QA document must include tested URL, viewport, observed Category/Segment, expected universe, result and screenshot path when a visual defect is found. Update the correctness audit with actual test counts, Build result and any remaining issue.

- [ ] **Step 6: 确认没有越过第一轮范围**

Run:

```powershell
git diff --name-only 4706b56..HEAD
rg -n "Opportunity Finder|Revenue Estimate|Sales Estimate|Forecast|Watchlist|AI Assistant" src scripts web config
```

Expected: changed files correspond only to this plan. Product capability matches are absent or pre-existing documentation only; no Seller Decision/Lifecycle/Review Velocity feature was added.

- [ ] **Step 7: 提交 QA 证据**

```powershell
git add -- docs/audits/V2.4-ROUND-1-CORRECTNESS-AUDIT-2026-09-07.md docs/audits/V2.4-ROUND-1-BROWSER-QA-2026-09-07.md
git diff --cached --check
git commit -m "docs: record v2.4 round one verification"
```

- [ ] **Step 8: 停止并提交第一轮结果**

Report completed fixes, Registry architecture, production category compatibility, Test Category evidence, exact PowerShell/Web test counts, lint/build outcome, browser QA and real remaining issues. Do not start Stage 4 or any later V2.4 feature without a new explicit user instruction.
